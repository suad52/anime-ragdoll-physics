--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- ZangetsuServer.Core: the authoritative server for the Zangetsu kit (Ichigo). It owns the per-player state
-- (cooldowns, busy lock, cast ids, the Tensa Zangetsu mode), the sword's lifetime on the character, request routing,
-- and the server API `S` every move module is built from. The moves themselves live in ZangetsuServer.Moves.<Name>
-- (M1 / Getsuga / Shunpo / Hollow / Bankai), each `return function(S) return { [skillId] = handler, __reset? } end`.
-- Contract: scratchpad ichigo/CONTRACT.md section 4 (S is EXACT there; additions here are marked "added").
-- Helpers are copied from OneForAllServer (strike / freezeBody / reel / LOS / wall clamps / ground snaps / hooks).
--
-- Broadcast kinds Core sends (Remotes.Broadcast):
--   Cooldown  (to the caster only) { skill, ends }
--   BankaiEnd { userId, t0, why, char (added: the mode's character), formDelay (added: s until the Shikai swap) }
--             why = "expired" | "died" | "unequip" | "left"
-- Attributes Core writes: player KitLocked (only while Kit == "Zangetsu", only on change: true while busy, else nil);
-- character OwnM1 (true while equipped, nil after), BankaiUntil (server time the mode ends; nil when off).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("ZangetsuKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Moves = script.Parent:WaitForChild("Moves")

local KIT_ID = CFG.KitId or "Zangetsu"
local TAG = CFG.TargetTag or "RagdollNPC"
local SKILLS = CFG.Skills or { "M1", "Getsuga", "Shunpo", "Hollow", "Bankai" }
local MOVE_NAMES = { "M1", "Getsuga", "Shunpo", "Hollow", "Bankai" }
local RATE = { M1 = 0.05 } -- per-action request limit (s); everything else 0.08
local RATE_DEFAULT = 0.08

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

local S = {}
local T = {} -- internal handles for the Edit-mode harness; unused at runtime
local CONNS = {}
local function keep(c)
	table.insert(CONNS, c)
	return c
end

---------------------------------------------------------------------------------------------------
-- logging

local warnAt = {}
-- rate-limited warn: one line per tag every `every` (5) s, with a count of what it swallowed
function S.warn(tag, msg, every)
	tag = tostring(tag)
	local c = os.clock()
	local w = warnAt[tag]
	if w and c - w.t < (every or 5) then
		w.n += 1
		return
	end
	local extra = (w and w.n > 0) and string.format(" (+%d more)", w.n) or ""
	warnAt[tag] = { t = c, n = 0 }
	warn("[ZangetsuServer] " .. tag .. ": " .. tostring(msg) .. extra)
end

function S.log(fmt, ...)
	local ok, s = pcall(string.format, tostring(fmt), ...)
	print("[Zangetsu] " .. (ok and s or tostring(fmt)))
end

---------------------------------------------------------------------------------------------------
-- hooks into the rest of the game, every one optional (OneForAllServer's block): ragdolls for NPC bodies,
-- self-healing terrain craters, NPC flee, explosive barrels, breakable props
local GojoServer = ServerScriptService:WaitForChild("GojoServer", 10)
local RagdollService, GroundFX
do
	local mod = GojoServer and GojoServer:FindFirstChild("RagdollService")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			RagdollService = res
			pcall(RagdollService.Init)
		else
			S.warn("RagdollService", "require failed: " .. tostring(res))
		end
	end
	local vs = ServerScriptService:WaitForChild("VulpineServer", 10)
	local gfx = vs and vs:WaitForChild("GroundFX", 10)
	if gfx then
		local ok, res = pcall(require, gfx)
		if ok and type(res) == "table" then
			GroundFX = res
		else
			S.warn("GroundFX", "require failed: " .. tostring(res))
		end
	end
end

-- GojoServer.<name>:Fire(...) when it exists; looked up on every call, so a hook added later starts working and a
-- missing one (BreakBlast today) is simply skipped
function S.hook(name, ...)
	local ev = GojoServer and GojoServer:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		local ok, err = pcall(ev.Fire, ev, ...)
		if not ok then
			S.warn("hook " .. tostring(name), err)
		end
	end
end

-- GroundFX.<fn>(...) when the module loaded
function S.ground(fn, ...)
	local f = GroundFX and GroundFX[fn]
	if type(f) == "function" then
		local ok, err = pcall(f, ...)
		if not ok then
			S.warn("GroundFX." .. tostring(fn), err)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the sword module: required lazily. Until ZangetsuKit.Sword exists (and loads) there is no sword and everything
-- else works; a missing or broken one is retried on every character spawn / equip and whenever a new one appears
local swordFailed = {} -- [ModuleScript] = true once its require failed (Roblox caches the failure)
-- retry = true (a character spawn / an equip): try a module that failed before once more
local function loadSword(retry)
	if S.Sword then
		return S.Sword
	end
	if retry then
		table.clear(swordFailed)
	end
	local inst = Kit:FindFirstChild("Sword")
	if not inst or not inst:IsA("ModuleScript") or swordFailed[inst] then
		return nil
	end
	local ok, res = pcall(require, inst)
	if ok and type(res) == "table" and type(res.attach) == "function" and type(res.get) == "function" then
		S.Sword = res
		S.log("sword module loaded")
		return res
	end
	swordFailed[inst] = true
	S.warn("Sword", ok and "module does not return the Sword API (attach/get)" or ("require failed: " .. tostring(res)))
	return nil
end

-- Sword.<fn>(...) in a pcall; nil when the module is missing / broken or the call errors
local function swordCall(fn, ...)
	local Sw = S.Sword or loadSword()
	local f = Sw and Sw[fn]
	if type(f) ~= "function" then
		return nil
	end
	local ok, res = pcall(f, ...)
	if not ok then
		S.warn("Sword." .. fn, res, 15)
		return nil
	end
	return res
end

---------------------------------------------------------------------------------------------------
-- data

S.CFG = CFG
S.KIT_ID = KIT_ID
S.Sword = nil -- set by loadSword()
S.RagdollService = RagdollService
S.GroundFX = GroundFX
S.UP = UP
S.FLAT = FLAT

local function now()
	return workspace:GetServerTimeNow()
end
S.now = now

function S.fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

function S.fireTo(p, kind, data)
	Broadcast:FireClient(p, kind, data)
end

---------------------------------------------------------------------------------------------------
-- geometry (copied from OneForAllServer)

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end
S.finite = finite

-- a horizontal unit vector from `v`, or from `fallback` if `v` is unusable
local function flatDir(v, fallback)
	if finite(v) then
		local f = v * FLAT
		if f.Magnitude > 1e-3 then
			return f.Unit
		end
	end
	local f = (finite(fallback) and fallback or Vector3.new(0, 0, -1)) * FLAT
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end
S.flatDir = flatDir

function S.randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

function S.randomFlat()
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- (aim, flat): the client's camera direction (payload.aim) with its pitch clamped to [minDeg, maxDeg]
function S.aimOf(payload, hrp, minDeg, maxDeg)
	local look = flatDir(hrp.CFrame.LookVector)
	local v = type(payload) == "table" and payload.aim or nil
	if not finite(v) or v.Magnitude < 1e-3 then
		return look, look
	end
	local flat = flatDir(v, look)
	local pitch = math.clamp(math.asin(math.clamp(v.Unit.Y, -1, 1)), math.rad(minDeg or -89), math.rad(maxDeg or 89))
	return (flat * math.cos(pitch) + UP * math.sin(pitch)).Unit, flat
end

-- the flat angle (degrees) between a flat offset and the aim; 0 for a body standing on the caster
local function angleTo(fl, aim)
	fl = fl * FLAT
	if fl.Magnitude < 0.5 then
		return 0
	end
	return math.deg(math.acos(math.clamp(fl.Unit:Dot(flatDir(aim)), -1, 1)))
end
S.angleTo = angleTo

-- the world only (no characters, NPC bodies or effects): wall clamps, ground snaps, line of sight
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshIgnore()
	local list = {}
	for _, n in ipairs({ "NPCs", "FX", "KitFX", "KitDebris", "LocalFX" }) do
		local f = workspace:FindFirstChild(n) -- FindFirstChild only: LocalFX never exists on the server
		if f then
			table.insert(list, f)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(TAG)) do
		table.insert(list, m) -- a body standing outside workspace.NPCs must not block the line to itself
	end
	for _, m in ipairs(T.extraIgnore or {}) do
		table.insert(list, m)
	end
	worldParams.FilterDescendantsInstances = list
end
S.refreshIgnore = refreshIgnore

-- nothing solid (world geometry only) between two points; call refreshIgnore() first
local function clearLine(a, b)
	local d = b - a
	if d.Magnitude < 1e-3 then
		return true
	end
	return workspace:Raycast(a, d, worldParams) == nil
end
S.clearLine = clearLine

-- how far you can travel from `from` along `dir` (up to `dist`) before a wall (minus 2)
function S.clampPath(from, dir, dist)
	if not finite(from) or not finite(dir) or dir.Magnitude < 1e-3 or not dist or dist <= 0 then
		return math.max(dist or 0, 0)
	end
	refreshIgnore()
	local hit = workspace:Raycast(from, dir.Unit * dist, worldParams)
	return hit and math.max((hit.Position - from).Magnitude - 2, 0) or dist
end

function S.groundAt(pos, depth)
	if not finite(pos) then
		return nil
	end
	refreshIgnore()
	local hit = workspace:Raycast(pos + UP * 6, Vector3.new(0, -(depth or 40), 0), worldParams)
	return hit and hit.Position or nil
end

local function floorBelow(pos, depth)
	if not finite(pos) then
		return nil
	end
	refreshIgnore()
	local hit = workspace:Raycast(pos, Vector3.new(0, -(depth or 40), 0), worldParams)
	return hit and hit.Position or nil
end
S.floorBelow = function(pOrPos, depth) -- accepts a Player (its root) or a position
	if typeof(pOrPos) == "Vector3" then
		return floorBelow(pOrPos, depth)
	end
	local ch = typeof(pOrPos) == "Instance" and pOrPos:IsA("Player") and pOrPos.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and floorBelow(root.Position, depth) or nil
end

-- a root position for a character standing at `pos`, as high above its ground as `hrp` is above its own
function S.standAt(hrp, pos)
	local own = floorBelow(hrp.Position, 30)
	local hip = own and (hrp.Position.Y - own.Y) or 3
	local g = floorBelow(Vector3.new(pos.X, math.max(pos.Y, hrp.Position.Y) + 1.5, pos.Z), 60)
	return g and Vector3.new(pos.X, g.Y + hip, pos.Z) or pos
end

---------------------------------------------------------------------------------------------------
-- players and casts

local function liveChar(p)
	local char = p and p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end
S.liveChar = liveChar

local function equipped(p)
	return p:GetAttribute("Kit") == KIT_ID
end

-- the caster still has this character and still holds this kit
function S.valid(p, char)
	return char ~= nil and liveChar(p) == char and equipped(p)
end

local state = {} -- [player] = st (CONTRACT 4.1)
local priv = {} -- [player] = Core-only bookkeeping { char, ready, resetFor, wasEquipped, exitUntil, conns }

function S.state(p)
	local st = state[p]
	if not st then
		st = { cd = {}, busyUntil = 0, id = 0, mode = nil, last = {} }
		state[p] = st
	end
	return st
end

local function sendCooldown(p, st, skill)
	S.fireTo(p, "Cooldown", { skill = skill, ends = st.cd[skill] or 0 })
end

-- alive, holding this kit, not mid-move, off cooldown (on cooldown it resends Cooldown so the HUD corrects itself)
function S.gate(p, skill)
	local char, hum, hrp = liveChar(p)
	if not char or not equipped(p) then
		return nil
	end
	if PvPBal.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		return nil
	end
	local st = S.state(p)
	local t = now()
	if t < st.busyUntil then
		return nil
	end
	if t < (st.cd[skill] or 0) then
		sendCooldown(p, st, skill)
		return nil
	end
	return char, hum, hrp, t
end

---------------------------------------------------------------------------------------------------
-- the mode (Tensa Zangetsu): st.mode = { char, untilT }; the character attribute BankaiUntil mirrors it

function S.inMode(p, char)
	local st = state[p]
	local m = st and st.mode
	if not m then
		return false
	end
	return m.char == (char or p.Character) and now() < m.untilT
end

function S.dmgMul(p, char)
	return S.inMode(p, char) and (CFG.Mode and CFG.Mode.DamageMul or 1) or 1
end

-- "Damage", "RoarDamage", "SlashDamage", "FinalWaveDamage", ... (never a *Mul)
local function isDamageKey(k)
	return type(k) == "string" and k:find("Damage", 1, true) ~= nil and k:sub(-3) ~= "Mul"
end

-- a shallow copy of CFG[move]; in the mode CFG.Mode[move] is merged over it. A damage field the mode table sets is
-- final; every other damage field (a number, or a list of numbers like M1.Damage) is multiplied by S.dmgMul
function S.cfgFor(p, char, move)
	local base = CFG[move]
	local out = {}
	if type(base) == "table" then
		for k, v in pairs(base) do
			out[k] = v
		end
	end
	if not S.inMode(p, char) then
		return out
	end
	local over = CFG.Mode and CFG.Mode[move]
	local mul = S.dmgMul(p, char)
	for k, v in pairs(out) do
		if isDamageKey(k) and not (type(over) == "table" and over[k] ~= nil) then
			if type(v) == "number" then
				out[k] = v * mul
			elseif type(v) == "table" then
				local list = {}
				for i, x in pairs(v) do
					list[i] = type(x) == "number" and x * mul or x
				end
				out[k] = list
			end
		end
	end
	if type(over) == "table" then
		for k, v in pairs(over) do
			out[k] = v
		end
	end
	return out
end

-- PERKS (2026-11-07, kitsE): Faster Cooldowns (player CooldownMul) shortens every cooldown; Faster Ult Charge
-- (UltChargeMul) shortens the ultimate's on top. The ultimate = Bankai (the wide G button). ShopService writes both.
local ULT_SKILLS = { Bankai = true, BankaiGrab = true } -- BankaiGrab: G again inside the mode (2026-11-08)
local function perkCdMul(p, skill)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if ULT_SKILLS[skill] then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult
	-- abilities"); the M1 is a swing, not an ability
	local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
	return math.clamp(m, 0.05, 1) * ((ULT_SKILLS[skill] or skill == "M1") and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end
S.perkCdMul = perkCdMul

-- starts the cooldown (shortened in the mode, and by the cooldown perks) and the busy lock; returns the cast id
function S.commit(p, skill, t, lock, char)
	local st = S.state(p)
	t = t or now()
	local sec = CFG[skill]
	local base = (type(sec) == "table" and tonumber(sec.Cooldown)) or 0
	local mul = 1
	if S.inMode(p, char) then
		local cm = CFG.Mode and CFG.Mode.CooldownMul
		mul = (cm and cm[skill]) or 1
	end
	st.cd[skill] = t + base * mul * perkCdMul(p, skill)
	st.busyUntil = math.max(st.busyUntil, t + (lock or 0))
	st.id += 1
	if base > 0 then
		sendCooldown(p, st, skill)
	end
	return st.id
end

function S.extendBusy(p, id, untilT)
	local st = state[p]
	if st and st.id == id and type(untilT) == "number" then
		st.busyUntil = math.max(st.busyUntil, untilT)
	end
end

-- a cancelled cast frees him (only the latest cast may)
function S.release(p, id)
	local st = state[p]
	if st and st.id == id then
		st.busyUntil = 0
	end
end

function S.setForm(char, form)
	if char and (S.Sword or loadSword()) then
		swordCall("setForm", char, form)
	end
end

function S.startMode(p, char, secs)
	if not char or not char.Parent then
		return
	end
	local st = S.state(p)
	local t = now()
	local untilT = t + (tonumber(secs) or (CFG.Mode and CFG.Mode.Time) or 15)
	st.mode = { char = char, untilT = untilT, startT = t }
	char:SetAttribute("BankaiUntil", untilT)
	-- (2026-11-08) Tensa Zangetsu takes less damage from players (ServerScriptService.PvP.dmg reads these two)
	local taken = CFG.Mode and tonumber(CFG.Mode.DamageTakenMul)
	if taken and taken < 1 then
		char:SetAttribute("DamageTakenMul", taken)
		char:SetAttribute("DamageTakenUntil", untilT)
	end
	local pv = priv[p]
	if pv then
		pv.exitUntil = 0
	end
	S.log("%s: Tensa Zangetsu for %.1fs", p.Name, untilT - t)
end

-- no-op when off. Clears the mode + BankaiUntil, tells every client, and puts the Shikai back: ExitFormDelay later
-- for "expired" (the exit performance plays first), at once for "unequip" / "died"
function S.endMode(p, why)
	local st = state[p]
	local m = st and st.mode
	if not m then
		return
	end
	st.mode = nil
	why = why or "expired"
	local char = m.char
	if char and char.Parent then
		char:SetAttribute("BankaiUntil", nil)
		char:SetAttribute("DamageTakenMul", nil)
		char:SetAttribute("DamageTakenUntil", nil)
	end
	local t = now()
	local delay = (CFG.Sword and CFG.Sword.ExitFormDelay) or 0.45
	S.fire("BankaiEnd", {
		userId = p.UserId, t0 = t, why = why, char = char, formDelay = (why == "expired") and delay or 0,
	})
	if why == "expired" then
		local pv = priv[p]
		if pv then
			pv.exitUntil = t + delay + 0.5
		end
		task.delay(delay, function()
			if char and char.Parent and not S.inMode(p, char) and char:GetAttribute("SwordForm") ~= "Shikai" then
				S.setForm(char, "Shikai")
			end
		end)
	elseif why ~= "left" and char and char.Parent then
		S.setForm(char, "Shikai")
	end
	S.log("%s: mode ended (%s)", p.Name, why)
end

---------------------------------------------------------------------------------------------------
-- bodies (every query: tagged bodies in workspace, alive OR dead unless o.alive)

local function torsoOf(m)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the query (PvP.formRoot);
	-- every area query below sets that point (PvPBal.setAim)
	return PvPBal.formRoot(m) or m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
end
S.torsoOf = torsoOf

local function alive(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and m:GetAttribute("Dead") ~= true
end
S.alive = alive

-- held by something else (a Blue grab, a domain): pulls skip it, blasts damage it but never move it
local function held(m)
	return m:GetAttribute("GrabbedBy") ~= nil or m:GetAttribute("InDomain") ~= nil
end
S.held = held

function S.isRagdolled(m)
	if RagdollService and RagdollService.IsRagdolled then
		local ok, res = pcall(RagdollService.IsRagdolled, m)
		if ok then
			return res == true
		end
	end
	return m:GetAttribute("Ragdolled") == true
end

local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) other players are targets too
-- every ragdollable NPC body in the world (alive or dead), plus every player's character; the caster is dropped
-- by admits() (o.los is the caster's own chest at every query site) and by S.strike / S.hurt
local function targets()
	local list = {}
	for _, m in ipairs(PvP.bodies(TAG, nil)) do
		if m:IsDescendantOf(workspace) and torsoOf(m) then
			table.insert(list, m)
		end
	end
	return list
end
S.targets = targets

-- the shared o filters: alive, exclude, skipHeld, maxDY (|tp.Y - refY|), then los (clearLine from o.los)
local function admits(m, tp, o, refY)
	if typeof(o.los) == "Vector3" and PvP.playerOf(m) and (tp - o.los).Magnitude < 3 then
		return false -- the player body standing at the query's own origin is the caster
	end
	if o.alive and not alive(m) then
		return false
	end
	if o.exclude and o.exclude[m] then
		return false
	end
	if o.skipHeld and held(m) then
		return false
	end
	if o.maxDY and refY and math.abs(tp.Y - refY) > o.maxDY then
		return false
	end
	return true
end
local function seen(o, pt)
	return not finite(o.los) or clearLine(o.los, pt)
end

-- LAG COMPENSATION (2026-11-10, "it's hard to hit people with the normal attack, especially when they're just running
-- around"), opt-in per query: o.lag = { by = the attacking Player, delay = the move's hit delay in s }. inBox / inCone /
-- nearSegment then also test a PLAYER body where it stood since the swing started, as the attacker saw it
-- (PvP.lagOffsets), with the shape grown by PvP.MELEE_PAD. An NPC gets only the zero offset and no pad, so NPC hits are
-- exactly as before, and a query without o.lag is untouched. Only Moves.M1 passes it.
local NO_LAG = { Vector3.zero }
local function lagOf(m, o)
	local lag = o.lag
	if type(lag) ~= "table" or not PvP.playerOf(m) then
		return NO_LAG, 0
	end
	local ok, offs = pcall(PvP.lagOffsets, m, lag.by, lag.delay)
	if not ok or type(offs) ~= "table" or #offs == 0 then
		offs = NO_LAG
	end
	return offs, tonumber(PvP.MELEE_PAD) or 0
end

-- { { m, tp, d, torso } } sorted by d (3D distance from pos to the torso)
function S.inRadius(pos, r, o)
	o = o or {}
	if o.los then
		refreshIgnore()
	end
	local out = {}
	PvPBal.setAim(pos, nil)
	for _, m in ipairs(targets()) do
		local torso = torsoOf(m)
		local tp = torso.Position
		local d = (tp - pos).Magnitude
		if d <= r and admits(m, tp, o, pos.Y) and seen(o, tp) then
			table.insert(out, { m = m, tp = tp, d = d, torso = torso })
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, part, d } }: UpperTorso / LowerTorso / Head (R6: Torso / Head / HRP) inside the oriented box (+0.5);
-- sorted by d (distance from the box centre). o.lag (above): a player is also tested at its lag offsets, box + MELEE_PAD
local BOX_PARTS = { "UpperTorso", "LowerTorso", "Head" }
local BOX_PARTS_R6 = { "Torso", "Head", "HumanoidRootPart" }
function S.inBox(cf, size, o)
	o = o or {}
	if o.los then
		refreshIgnore()
	end
	local hx, hy, hz = size.X * 0.5 + 0.5, size.Y * 0.5 + 0.5, size.Z * 0.5 + 0.5
	local out = {}
	PvPBal.setAim(cf.Position, nil)
	for _, m in ipairs(targets()) do
		local names = m:FindFirstChild("UpperTorso") and BOX_PARTS or BOX_PARTS_R6
		local tp = torsoOf(m).Position
		if admits(m, tp, o, cf.Position.Y) then
			local offs, pad = lagOf(m, o)
			local bx, by, bz = hx + pad, hy + pad, hz + pad
			-- pos + the first offset that puts it inside the box, or nil (an NPC: pos itself, as before)
			local function within(pos)
				for _, off in ipairs(offs) do
					local at = pos + off
					local l = cf:PointToObjectSpace(at)
					if math.abs(l.X) <= bx and math.abs(l.Y) <= by and math.abs(l.Z) <= bz then
						return at
					end
				end
				return nil
			end
			local inside, insideAt = {}, {}
			if PvPBal.isForm(m) then -- (2026-11-08) a giant form: its body point nearest the box centre
				local at = within(tp)
				if at then
					table.insert(inside, torsoOf(m))
					table.insert(insideAt, at)
				end
			end
			for _, n in ipairs(names) do
				local part = m:FindFirstChild(n)
				if part and part:IsA("BasePart") then
					local at = within(part.Position)
					if at then
						table.insert(inside, part)
						table.insert(insideAt, at)
					end
				end
			end
			if #inside > 0 then
				local okPart
				if seen(o, tp) then
					okPart = inside[1]
				else
					for i, part in ipairs(inside) do
						if seen(o, insideAt[i]) then -- where it was found inside (the attacker's view, for a player)
							okPart = part
							break
						end
					end
				end
				if okPart then
					table.insert(out, { m = m, tp = tp, part = okPart, d = (tp - cf.Position).Magnitude })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, d, ang } }: flat distance <= range, flat angle from the flat aim <= halfDeg, |dY| <= o.maxDY (12);
-- sorted by d. o.lag (above): a player is also tested at its lag offsets, every limit + MELEE_PAD
function S.inCone(origin, aim, range, halfDeg, o)
	o = o or {}
	if o.los then
		refreshIgnore()
	end
	local maxDY = o.maxDY or 12
	local fa = flatDir(aim)
	local out = {}
	PvPBal.setAim(origin, nil)
	for _, m in ipairs(targets()) do
		local tp = torsoOf(m).Position
		if admits(m, tp, o, nil) then
			local offs, pad = lagOf(m, o) -- an NPC: { zero }, 0 - the one test it always had
			for _, off in ipairs(offs) do
				local at = tp + off
				local rel = at - origin
				local fl = rel * FLAT
				local d = fl.Magnitude
				local ang = angleTo(fl, fa)
				-- the pad widens the edges too: `pad` studs off an edge ray is asin(pad / d) further round
				local slack = pad > 0 and (d > pad and math.deg(math.asin(pad / d)) or 180) or 0
				if d <= range + pad and ang <= halfDeg + slack and math.abs(rel.Y) <= maxDY + pad and seen(o, at) then
					table.insert(out, { m = m, tp = tp, d = d, ang = ang })
					break
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, along, off } }: 3D distance from the torso to the segment a->b <= r, `along` (the projection on a->b)
-- in [-1, len + 2]; maxDY is measured from the segment point nearest the body; sorted by along. o.lag (above): a player
-- is also tested at its lag offsets, r and the along window + MELEE_PAD
function S.nearSegment(a, b, r, o)
	o = o or {}
	if o.los then
		refreshIgnore()
	end
	local d = b - a
	local len = d.Magnitude
	local u = len > 1e-3 and d / len or nil
	local out = {}
	for _, m in ipairs(targets()) do
		local fc = PvPBal.formCenter(m) -- (2026-11-08) a giant form: its body point nearest the line
		if fc then
			PvPBal.setAim(u and (a + u * math.clamp((fc - a):Dot(u), 0, len)) or a, nil)
		end
		local tp = torsoOf(m).Position
		local offs, pad = lagOf(m, o) -- an NPC: { zero }, 0 - the one test it always had
		for _, lo in ipairs(offs) do
			local at = tp + lo
			local rel = at - a
			local along = u and rel:Dot(u) or 0
			local near = u and (a + u * math.clamp(along, 0, len)) or a
			local off = (at - near).Magnitude
			if along >= -1 - pad and along <= len + 2 + pad and off <= r + pad and admits(m, tp, o, near.Y) and seen(o, at) then
				table.insert(out, { m = m, tp = tp, along = along, off = off })
				break
			end
		end
	end
	table.sort(out, function(x, y)
		return x.along < y.along
	end)
	return out
end

---------------------------------------------------------------------------------------------------
-- hits (copied from OneForAllServer)

-- velocities pinned at zero for `secs`, then `after()`: the server half of the hit-stop
local function freezeBody(m, secs, after)
	local untilT = os.clock() + (secs or 0)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not m.Parent or os.clock() >= untilT then
			conn:Disconnect()
			if after then
				local ok, err = pcall(after)
				if not ok then
					S.warn("hit-stop", err)
				end
			end
			return
		end
		for _, part in ipairs(m:GetChildren()) do
			if part:IsA("BasePart") and not part.Anchored then
				part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			end
		end
	end)
	return conn
end
S.freezeBody = freezeBody

-- damage (living only) + kill credit + ragdoll + (optionally hit-stopped) fling. Held bodies take the damage and the
-- ragdoll but keep still; vel nil = ragdoll only. o = { hitStop, spin }
function S.strike(p, m, vel, damage, rag, o)
	o = o or {}
	if not m or not m.Parent or (p and m == p.Character) then
		return
	end
	rag = rag or 3
	local hum = m:FindFirstChildOfClass("Humanoid")
	if type(damage) == "number" and damage > 0 and hum and hum.Health > 0 and m:GetAttribute("Dead") ~= true then
		m:SetAttribute("LastHitBy", p.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, damage))
	end
	if not RagdollService then
		return
	end
	if not finite(vel) or held(m) then
		RagdollService.Ragdoll(m, rag)
		return
	end
	local spin = finite(o.spin) and o.spin or S.randomUnit() * 10
	if o.hitStop and o.hitStop > 0 then
		RagdollService.Ragdoll(m, rag + o.hitStop)
		freezeBody(m, o.hitStop, function()
			if m.Parent and not held(m) then
				RagdollService.Fling(m, vel, spin, rag)
			end
		end)
	else
		RagdollService.Fling(m, vel, spin, rag)
	end
end

-- damage + kill credit only
function S.hurt(p, m, damage)
	if not m or not m.Parent or (p and m == p.Character) or type(damage) ~= "number" or damage <= 0 then
		return
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and m:GetAttribute("Dead") ~= true then
		m:SetAttribute("LastHitBy", p.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, damage))
	end
end

-- StunnedUntil = now + secs on a living body (its AI pauses); never shortens a longer stun already running
function S.stun(m, secs)
	if not m or not m.Parent or not alive(m) then
		return
	end
	local untilT = now() + (secs or 0)
	local cur = m:GetAttribute("StunnedUntil")
	if type(cur) ~= "number" or cur < untilT then
		m:SetAttribute("StunnedUntil", untilT)
	end
end

-- the punch knock: a standing body's HRP velocity (held bodies are never moved)
function S.push(m, vel)
	if not m or not m.Parent or held(m) or not finite(vel) then
		return
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp and not hrp.Anchored then
		hrp.AssemblyLinearVelocity = vel
	end
end

-- reel a body toward a point (call every Heartbeat): homing velocity, no spin. False once it can no longer be reeled
function S.reel(m, slot, gain, maxSpeed, rag)
	local tt = m and m.Parent and torsoOf(m)
	if not tt or held(m) or not RagdollService or not finite(slot) then
		return false
	end
	local v = (slot - tt.Position) * (gain or 8)
	if v.Magnitude > (maxSpeed or 120) then
		v = v.Unit * (maxSpeed or 120)
	end
	RagdollService.Fling(m, v, Vector3.zero, rag or 3)
	return true
end

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get shoved too (sign = -1 pulls inward)
function S.pushLoose(pos, radius, speed, upBias, sign)
	if not finite(pos) or not radius or radius <= 0 then
		return
	end
	local ignore = {}
	for _, n in ipairs({ "KitFX", "FX", "LocalFX" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(TAG)) do
		table.insert(ignore, m)
	end
	looseParams.FilterDescendantsInstances = ignore
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, looseParams)) do
		local root = part.AssemblyRootPart
		if root and not root.Anchored and not done[root] then
			done[root] = true
			local off = root.Position - pos
			local k = math.clamp(1 - off.Magnitude / radius, 0, 1)
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) * (sign or 1) + UP * (upBias or 0)).Unit
			pcall(function()
				root:ApplyImpulse(dir * (speed or 0) * 0.6 * k * root.AssemblyMass)
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- time

-- task.delay to an absolute cast time (t0 + secs); an error inside fn is warned, never silent
function S.at(t0, secs, fn, ...)
	return task.delay(math.max(t0 + (secs or 0) - now(), 0), function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			S.warn("at()", err)
		end
	end, ...)
end

-- runs step(e) every Heartbeat (e = server seconds since t0) until it returns true; an error stops it, warns and
-- calls onError() so nothing is left reeling or locked. Returns the connection (added) so __reset can cut it
function S.timeline(label, t0, step, onError)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local ok, res = pcall(step, now() - t0)
		if not ok then
			conn:Disconnect()
			S.warn(tostring(label), res)
			if onError then
				local ok2, err2 = pcall(onError)
				if not ok2 then
					S.warn(tostring(label) .. " onError", err2)
				end
			end
		elseif res then
			conn:Disconnect()
		end
	end)
	return conn
end

---------------------------------------------------------------------------------------------------
-- move modules: every ModuleScript in Moves (the five named ones, plus any added later), each in its own pcall

local HANDLERS = {} -- [skill id] = handler(p, st, payload)
local OWNER = {} -- [skill id] = module name
local RESETS = {} -- { { name, fn } }
local LOADED = {} -- [ModuleScript] = true

local function loadMove(mod)
	if LOADED[mod] or not mod:IsA("ModuleScript") then
		return
	end
	LOADED[mod] = true
	local tag = "Moves." .. mod.Name
	local ok, f = pcall(require, mod)
	if not ok then
		S.warn(tag, "require failed (skipped): " .. tostring(f), 0)
		return
	end
	if type(f) ~= "function" then
		S.warn(tag, "does not return function(S) (skipped)", 0)
		return
	end
	local ok2, M = pcall(f, S)
	if not ok2 or type(M) ~= "table" then
		S.warn(tag, "build failed (skipped): " .. tostring(ok2 and "did not return a table" or M), 0)
		return
	end
	local got = {}
	for k, v in pairs(M) do
		if type(k) == "string" and type(v) == "function" then
			if k == "__reset" then
				table.insert(RESETS, { name = mod.Name, fn = v })
				table.insert(got, k)
			elseif k:sub(1, 2) ~= "__" then
				if HANDLERS[k] then
					S.warn(tag, "duplicate handler '" .. k .. "' (kept " .. tostring(OWNER[k]) .. "'s)", 0)
				else
					HANDLERS[k] = v
					OWNER[k] = mod.Name
					table.insert(got, k)
				end
			end
		end
	end
	table.sort(got)
	S.log("move %s loaded: %s", mod.Name, table.concat(got, ", "))
end

local function resetMoves(p, why)
	local st = S.state(p)
	for _, r in ipairs(RESETS) do
		local ok, err = pcall(r.fn, p, st, why)
		if not ok then
			S.warn("Moves." .. r.name .. ".__reset", err)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- requests

local function route(p, action, payload)
	if typeof(action) ~= "string" or not equipped(p) or action:sub(1, 2) == "__" then
		return
	end
	local fn = HANDLERS[action]
	if not fn then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	local st = S.state(p)
	local c = os.clock()
	if c - (st.last[action] or -1e9) < (RATE[action] or RATE_DEFAULT) then
		return
	end
	st.last[action] = c
	local ok, err = pcall(fn, p, st, payload)
	if not ok then
		S.warn(action, err)
	end
end

---------------------------------------------------------------------------------------------------
-- equip, the sword's lifetime, death / respawn / leave

local function attach(p, char)
	local model = swordCall("attach", char)
	if model and S.inMode(p, char) and char:GetAttribute("SwordForm") ~= "Bankai" then
		S.setForm(char, "Bankai") -- a re-attach mid-mode (avatar reload) keeps the Bankai look
	end
	return model
end

-- the avatar has loaded (CharacterAppearanceLoaded, or 3 s after CharacterAdded): the body parts are final
local function markReady(p, char)
	local pv = priv[p]
	if not pv or not char or not char.Parent or p.Character ~= char then
		return
	end
	pv.ready[char] = true
	if equipped(p) and liveChar(p) == char then
		char:SetAttribute("OwnM1", true)
		attach(p, char)
	end
end

local function died(p, char)
	local pv = priv[p]
	if not pv or pv.resetFor == char then
		return
	end
	pv.resetFor = char
	S.endMode(p, "died")
	S.state(p).busyUntil = 0
	if equipped(p) then
		resetMoves(p, "died")
	end
end

local function charAdded(p, char, readyNow)
	local pv = priv[p]
	if not pv then
		return
	end
	local st = S.state(p)
	if pv.char and pv.char ~= char and pv.resetFor ~= pv.char then
		died(p, pv.char) -- replaced without dying (LoadCharacter): same cleanup
	end
	S.endMode(p, "died")
	st.busyUntil = 0
	pv.char = char
	pv.resetFor = nil
	if equipped(p) then
		char:SetAttribute("OwnM1", true)
		loadSword(true) -- retry a missing / broken sword module on every spawn
	end
	task.spawn(function()
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
		if hum and pv.conns then
			table.insert(pv.conns, hum.Died:Connect(function()
				died(p, char)
			end))
		end
	end)
	if readyNow then
		markReady(p, char)
	end
	task.delay(3, markReady, p, char)
end

local function kitChanged(p)
	local pv = priv[p]
	if not pv then
		return
	end
	local st = S.state(p)
	local char = p.Character
	if equipped(p) then
		pv.wasEquipped = true
		loadSword(true)
		if char then
			char:SetAttribute("OwnM1", true)
			if pv.ready[char] and liveChar(p) == char then
				attach(p, char)
			end
		end
		for _, skill in ipairs(SKILLS) do
			sendCooldown(p, st, skill) -- the HUD picks up any cooldown still running from before a switch
		end
	elseif pv.wasEquipped then
		pv.wasEquipped = false
		S.endMode(p, "unequip")
		resetMoves(p, "unequip")
		st.busyUntil = 0
		if char then
			swordCall("detach", char)
			char:SetAttribute("OwnM1", nil)
		end
		-- KitLocked is left alone: the new kit's server owns it now
	end
end

local function onPlayer(p)
	if priv[p] then
		return
	end
	local pv = { ready = setmetatable({}, { __mode = "k" }), conns = {}, exitUntil = 0 }
	priv[p] = pv
	S.state(p)
	table.insert(pv.conns, p.CharacterAdded:Connect(function(char)
		charAdded(p, char, false)
	end))
	table.insert(pv.conns, p.CharacterAppearanceLoaded:Connect(function(char)
		markReady(p, char)
	end))
	table.insert(pv.conns, p:GetAttributeChangedSignal("Kit"):Connect(function()
		kitChanged(p)
	end))
	if p.Character then
		local ok, loaded = pcall(p.HasAppearanceLoaded, p)
		charAdded(p, p.Character, ok and loaded)
	end
	if equipped(p) then
		kitChanged(p)
	end
end

local function onLeave(p)
	local pv = priv[p]
	if state[p] then
		S.endMode(p, "left")
		if equipped(p) or (pv and pv.wasEquipped) then
			resetMoves(p, "left")
		end
	end
	state[p] = nil
	if pv then
		for _, c in ipairs(pv.conns) do
			c:Disconnect()
		end
		pv.conns = nil
	end
	priv[p] = nil
end

---------------------------------------------------------------------------------------------------
-- every frame: the mode's expiry and KitLocked; every second: the sword / OwnM1 watchdog

local function watchdog(p, pv, t)
	if not equipped(p) then
		return
	end
	local char = liveChar(p)
	if not char then
		return
	end
	if char:GetAttribute("OwnM1") ~= true then
		char:SetAttribute("OwnM1", true)
	end
	local Sw = S.Sword or loadSword()
	if not Sw or not pv.ready[char] then
		return
	end
	local okGet, info = pcall(Sw.get, char)
	if not okGet or info == nil then
		attach(p, char) -- avatar loading replaced the RightHand (or the sword was never built)
		return
	end
	-- a Bankai look with no mode, no cast running and no exit pending (a cancelled Bankai): back to Shikai
	local st = S.state(p)
	if char:GetAttribute("SwordForm") == "Bankai" and not S.inMode(p, char) and t > st.busyUntil + 0.25
		and t > (pv.exitUntil or 0) then
		S.warn("form", p.Name .. ": Bankai form with no mode; restoring Shikai", 10)
		S.setForm(char, "Shikai")
	end
end

local nextWatch = 0
local function heartbeat()
	local t = now()
	for p, st in pairs(state) do
		local ok, err = pcall(function()
			local m = st.mode
			if m then
				if t >= m.untilT then
					S.endMode(p, "expired")
				elseif not m.char.Parent or liveChar(p) ~= m.char then
					S.endMode(p, "died")
				end
			end
			-- no switching fighter mid-move (KitServer's SetKit checks this). Only the EQUIPPED kit's server writes
			-- KitLocked (every kit server shares the attribute), so this one keeps out of it while another is held
			if equipped(p) then
				local locked = t < st.busyUntil
				if p:GetAttribute("KitLocked") ~= (locked or nil) then
					p:SetAttribute("KitLocked", locked or nil)
				end
			end
		end)
		if not ok then
			S.warn("heartbeat", err, 10)
		end
	end
	local c = os.clock()
	if c >= nextWatch then
		nextWatch = c + 1
		for p, pv in pairs(priv) do
			local ok, err = pcall(watchdog, p, pv, t)
			if not ok then
				S.warn("watchdog", err, 10)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- start

keep(Request.OnServerEvent:Connect(route))
keep(RunService.Heartbeat:Connect(heartbeat))
keep(Players.PlayerAdded:Connect(onPlayer))
keep(Players.PlayerRemoving:Connect(onLeave))
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end

-- the sword module may be published after this script starts
keep(Kit.ChildAdded:Connect(function(c)
	if c.Name == "Sword" and c:IsA("ModuleScript") and not S.Sword then
		task.defer(loadSword)
	end
end))
task.spawn(function()
	if not loadSword() then
		local inst = Kit:WaitForChild("Sword", 30)
		if inst then
			loadSword()
		else
			S.warn("Sword", "ZangetsuKit.Sword missing after 30 s: no sword until it appears", 0)
		end
	end
end)

-- the moves: the five named modules (10 s each, in parallel), anything else already there, anything added later
for _, name in ipairs(MOVE_NAMES) do
	task.spawn(function()
		local mod = Moves:WaitForChild(name, 10)
		if mod then
			loadMove(mod)
		else
			S.warn("Moves." .. name, "missing after 10 s (skipped; loads if added later)", 0)
		end
	end)
end
for _, c in ipairs(Moves:GetChildren()) do
	task.spawn(loadMove, c)
end
keep(Moves.ChildAdded:Connect(function(c)
	task.defer(loadMove, c)
end))

-- PERKS (2026-11-07, kitsE): Instant Ult Charge. ShopService fires ServerStorage.PerkHooks.UltReset(player) once the
-- purchase is saved; when that player holds this kit, Bankai's cooldown is cleared and the HUD told (Cooldown ends 0)
local function ultReset(p)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not equipped(p) then
		return
	end
	local st = S.state(p)
	for skill in pairs(ULT_SKILLS) do
		st.cd[skill] = 0
		sendCooldown(p, st, skill)
	end
	S.log("%s: ultimate charged (Instant Ult Charge)", p.Name)
end
T.ultReset = ultReset
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 60)
	local ev = hooks and hooks:WaitForChild("UltReset", 60)
	if ev and ev:IsA("BindableEvent") then
		keep(ev.Event:Connect(function(p)
			local ok, err = pcall(ultReset, p)
			if not ok then
				S.warn("UltReset", err, 5)
			end
		end))
	else
		S.warn("PerkHooks", "ServerStorage.PerkHooks.UltReset missing: Instant Ult Charge does nothing for Zangetsu", 0)
	end
end)

-- harness handles (Edit-mode tests load a copy of this source as a ModuleScript and drive these directly)
T.S, T.state, T.priv, T.HANDLERS, T.OWNER, T.RESETS = S, state, priv, HANDLERS, OWNER, RESETS
T.route, T.onPlayer, T.onLeave, T.charAdded, T.markReady, T.died, T.kitChanged = route, onPlayer, onLeave, charAdded,
	markReady, died, kitChanged
T.loadMove, T.loadSword, T.heartbeat, T.watchdog = loadMove, loadSword, heartbeat, watchdog
function T.addPlayer(p)
	-- a harness stand-in player (a table): Core bookkeeping without the Player signals
	priv[p] = { ready = setmetatable({}, { __mode = "k" }), conns = {}, exitUntil = 0 }
	S.state(p)
end
function T.shutdown()
	for _, c in ipairs(CONNS) do
		c:Disconnect()
	end
	for _, pv in pairs(priv) do
		for _, c in ipairs(pv.conns or {}) do
			c:Disconnect()
		end
	end
	table.clear(state)
	table.clear(priv)
end

print("[ZangetsuServer] online")
