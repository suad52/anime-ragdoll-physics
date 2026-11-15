--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- GomuServer.Core: the authoritative server for the Gomu kit (LUFFY, a rubber-bodied brawler). It owns the per-player
-- state (cooldowns, busy lock, cast ids, the Gear Fifth mode, the streamed steering aim), the straw hat's lifetime on
-- the character, request routing, and the server API `S` every move module is built from. The moves themselves live
-- in GomuServer.Moves.<Name> (M1 / Gatling / Rocket / Elephant / Gear5), each
-- `return function(S) return { [action] = handler(p, st, payload), __reset? = fn(p, st, why) } end`.
-- Contract: scratchpad luffy/CONTRACT.md section 5 (the S API is EXACT there; additions here are marked "added").
-- Built from ZangetsuServer.Core (same lifecycle, same query / hit helpers) with the sword removed and:
--   * PvP: every query also returns OTHER players' living characters (CFG.AffectPlayers); every hit function handles
--     a player victim itself (Tempest Evasion check, then GomuKit.Remotes.Knockback to THEIR client - the server
--     never moves a client-owned character). Move modules never branch on players.
--   * the caster is always excluded: route / S.at / S.timeline remember whose cast code runs on the current thread
--     (o.caster overrides), and the hit functions refuse the caster's own character outright.
--   * "Aim" is handled here: the steering stream a cast asks for (ctx.aimStream); moves read it with S.liveAim.
--   * OwnM1 is re-asserted every Heartbeat while equipped + alive (AscendantService clears it on kit switches).
--
-- Broadcast kinds Core sends (Remotes.Broadcast):
--   Cooldown  (to the caster only) { skill, ends }            skill may be "Bajrang"
--   Gear5End  { userId, t0, why, char }                        why = "expired" | "died" | "unequip" | "left"
-- Remotes.Knockback (to ONE victim's client): (vel: Vector3 clamped to 320, ragTime <= PlayerRagdollMax, keep 0..1)
-- Attributes Core writes: player KitLocked (only while Kit == "Gomu", only on change: true while busy, else nil);
-- character OwnM1 (true while equipped + alive; cleared on unequip unless the new kit is in CFG.OwnM1Kits),
-- Gear5Until (server time the mode ends; nil when off). The straw hat: GomuKit.Hat (attach / detach / get).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("GomuKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local Moves = script.Parent:WaitForChild("Moves")

local CORE = type(CFG.Core) == "table" and CFG.Core or {} -- GomuKit.Config.Core (owner: core)
local KIT_ID = CFG.KitId or "Gomu"
local TAG = CFG.TargetTag or "RagdollNPC"
local SKILLS = CFG.Skills or { "M1", "Gatling", "Rocket", "Elephant", "Gear5", "Bajrang" }
local MOVE_NAMES = { "M1", "Gatling", "Rocket", "Elephant", "Gear5" }
local RATE = type(CORE.Rate) == "table" and CORE.Rate or { M1 = 0.05, Aim = 0.033 } -- per-action request limit (s)
local RATE_DEFAULT = tonumber(CORE.RateDefault) or 0.08
local AIM_MAX_AGE = tonumber(CORE.AimMaxAge) or 0.4
local KNOCK_MAX = tonumber(CORE.KnockMax) or 320
local EVADE_GRACE = tonumber(CORE.EvadeGrace) or 0.35 -- s after a dodge in which shoves on that body are dropped
local WATCH_EVERY = tonumber(CORE.WatchEvery) or 1
local RAG_MAX = tonumber(CFG.PlayerRagdollMax) or 2.2

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local TAU = math.pi * 2

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
	warn("[GomuServer] " .. tag .. ": " .. tostring(msg) .. extra)
end

function S.log(fmt, ...)
	local ok, s = pcall(string.format, tostring(fmt), ...)
	print("[Gomu] " .. (ok and s or tostring(fmt)))
end

---------------------------------------------------------------------------------------------------
-- hooks into the rest of the game, every one optional: ragdolls for NPC bodies, self-healing terrain craters, the
-- hit-reaction marks, the dodge check, the combo counter's event, NPC flee, the city's destruction
local GojoServer = ServerScriptService:WaitForChild("GojoServer", 10)
local RagdollService, GroundFX, HitReact, Evasion, AbilityEvent
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
	local shared = ReplicatedStorage:WaitForChild("GojoShared", 10)
	local hr = shared and shared:WaitForChild("HitReact", 10)
	if hr then
		local ok, res = pcall(require, hr)
		if ok and type(res) == "table" then
			HitReact = res
		else
			S.warn("HitReact", "require failed: " .. tostring(res))
		end
	end
	local rem = shared and shared:WaitForChild("Remotes", 10)
	AbilityEvent = rem and rem:WaitForChild("AbilityEvent", 10)
	-- Tempest's dodge hook (optional: without it nothing ever evades)
	local ts = ServerScriptService:FindFirstChild("TempestServer") or ServerScriptService:WaitForChild("TempestServer", 5)
	local ev = ts and ts:FindFirstChild("Evasion")
	if ev then
		local ok, res = pcall(require, ev)
		if ok and type(res) == "table" and type(res.tryEvade) == "function" then
			Evasion = res
		else
			S.warn("Evasion", "require failed: " .. tostring(res))
		end
	end
end

-- GojoServer.<name>:Fire(...) when it exists; looked up on every call, so a hook added later starts working and a
-- missing one is simply skipped. Signatures: WorldBlast(pos, radius, userId), BreakBlast(pos, radius, dir, speed,
-- userId), Threat(pos, radius, secs)
function S.hook(name, ...)
	local ev = GojoServer and GojoServer:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		local ok, err = pcall(ev.Fire, ev, ...)
		if not ok then
			S.warn("hook " .. tostring(name), err)
		end
	end
end

-- GroundFX.<fn>(...) when the module loaded: impact(pos, radius, rocks, rockSpeed), ring(center, radius, n, upSpeed)
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
-- the straw hat module (GomuKit.Hat): required lazily and retried on every spawn / equip, like Zangetsu's sword. A
-- missing or broken one only costs the hat; everything else works
local hatFailed = {} -- [ModuleScript] = true once its require failed (Roblox caches the failure)
local function loadHat(retry)
	if S.Hat then
		return S.Hat
	end
	if retry then
		table.clear(hatFailed)
	end
	local inst = Kit:FindFirstChild("Hat")
	if not inst or not inst:IsA("ModuleScript") or hatFailed[inst] then
		return nil
	end
	local ok, res = pcall(require, inst)
	if ok and type(res) == "table" and type(res.attach) == "function" and type(res.get) == "function"
		and type(res.detach) == "function" then
		S.Hat = res
		S.log("hat module loaded")
		return res
	end
	hatFailed[inst] = true
	S.warn("Hat", ok and "module does not return the Hat API (attach/detach/get)" or ("require failed: " .. tostring(res)))
	return nil
end

-- Hat.<fn>(...) in a pcall; nil when the module is missing / broken or the call errors
local function hatCall(fn, ...)
	local H = S.Hat or loadHat()
	local f = H and H[fn]
	if type(f) ~= "function" then
		return nil
	end
	local ok, res = pcall(f, ...)
	if not ok then
		S.warn("Hat." .. fn, res, 15)
		return nil
	end
	return res
end

---------------------------------------------------------------------------------------------------
-- data

S.CFG = CFG
S.KIT_ID = KIT_ID
S.Hat = nil -- set by loadHat()
S.RagdollService = RagdollService
S.GroundFX = GroundFX
S.HitReact = HitReact
S.Evasion = Evasion -- added
S.UP = UP
S.FLAT = FLAT
S.TAU = TAU -- added

local function now()
	return workspace:GetServerTimeNow()
end
S.now = now

function S.fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

function S.fireTo(p, kind, data)
	if typeof(p) == "Instance" and p:IsA("Player") then
		Broadcast:FireClient(p, kind, data)
	end
end

---------------------------------------------------------------------------------------------------
-- whose cast is running: route, S.at and S.timeline record the caster against the thread they run his code on, so
-- every query leaves his own character out without the move having to say so (o.caster = a Player / Model overrides;
-- a move's own raw task.delay / task.spawn is NOT tracked - use S.at, or pass o.exclude / o.caster)

local CASTER = setmetatable({}, { __mode = "k" }) -- [thread] = Player

local function casterNow()
	return CASTER[coroutine.running()]
end

-- (added) runs fn(...) as `p`'s cast code (pcall'd); returns pcall's results
local function asCaster(p, fn, ...)
	local th = coroutine.running()
	local prev = CASTER[th]
	CASTER[th] = p
	local res = table.pack(pcall(fn, ...))
	CASTER[th] = prev
	return table.unpack(res, 1, res.n)
end
S.asCaster = asCaster

-- the character a query must leave out: o.caster (Player or Model), else the caster of the running cast code
local function casterChar(o)
	local c = o and o.caster
	if typeof(c) == "Instance" then
		if c:IsA("Player") then
			return c.Character
		elseif c:IsA("Model") then
			return c
		end
	end
	local p = casterNow()
	return p and p.Character or nil
end

---------------------------------------------------------------------------------------------------
-- geometry (copied from ZangetsuServer.Core)

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end
S.finite = finite

-- a client-supplied world point we will use as-is: finite and inside the map's sane box (|x|, |y|, |z| < 1e5)
function S.validTarget(v)
	if typeof(v) ~= "Vector3" or v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
		return nil
	end
	if math.abs(v.X) >= 1e5 or math.abs(v.Y) >= 1e5 or math.abs(v.Z) >= 1e5 then
		return nil
	end
	return v
end

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
	local a = math.random() * TAU
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

-- the cursor point a cast aims at: payload.target (or `from` + the flat look * range when the client sent none),
-- clamped to `range` along its direction and pushed out to `minRange`; then a world-only ray from -> point (0.75
-- past it, so a cursor resting ON a wall still finds the wall): a hit moves the point onto that surface.
-- Returns point, normal | nil, onSurface
function S.cursorPoint(payload, from, range, minRange)
	payload = type(payload) == "table" and payload or {}
	range = tonumber(range) or 60
	minRange = math.min(tonumber(minRange) or 0, range)
	if not finite(from) then
		return nil, nil, false
	end
	local look = flatDir(payload.aim)
	local target = S.validTarget(payload.target)
	local dir, dist
	if target then
		local off = target - from
		dist = off.Magnitude
		dir = dist > 1e-3 and off / dist or look
	else
		dir, dist = look, range
	end
	dist = math.clamp(dist, minRange, range)
	local point = from + dir * dist
	refreshIgnore()
	local hit = workspace:Raycast(from, dir * (dist + 0.75), worldParams)
	if hit then
		return hit.Position, hit.Normal, true
	end
	return point, nil, false
end

-- the world point a stretched limb starts from (the client's stretch starts at the same place): "R" / "L" = the
-- UpperTorso shoulder rig attachment, "RL" / "LL" = the LowerTorso hip rig attachment; R6 = Torso offsets; else HRP
local LIMB_RIG = {
	R = { "UpperTorso", "RightShoulderRigAttachment", Vector3.new(1, 0.5, 0) },
	L = { "UpperTorso", "LeftShoulderRigAttachment", Vector3.new(-1, 0.5, 0) },
	RL = { "LowerTorso", "RightHipRigAttachment", Vector3.new(0.5, -1, 0) },
	LL = { "LowerTorso", "LeftHipRigAttachment", Vector3.new(-0.5, -1, 0) },
}
function S.limbRoot(char, limb)
	local rig = LIMB_RIG[limb] or LIMB_RIG.R
	if not char then
		return nil
	end
	local torso = char:FindFirstChild(rig[1])
	local att = torso and torso:FindFirstChild(rig[2])
	if att and att:IsA("Attachment") then
		return att.WorldPosition
	end
	local r6 = char:FindFirstChild("Torso")
	if r6 and r6:IsA("BasePart") then
		return (r6.CFrame * CFrame.new(rig[3])).Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		return (hrp.CFrame * CFrame.new(rig[3])).Position
	end
	return nil
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

local state = {} -- [player] = st (CONTRACT 5.1)
local priv = {} -- [player] = Core-only bookkeeping { char, ready, resetFor, wasEquipped, conns }

function S.state(p)
	local st = state[p]
	if not st then
		st = { cd = {}, busyUntil = 0, id = 0, mode = nil, last = {}, aim = nil }
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

-- the latest "Aim" steering packet for cast `id` (ctx.aimStream), if it is at most maxAge (0.4) s old: aim, target
function S.liveAim(p, id, maxAge)
	local st = state[p]
	local a = st and st.aim
	if not a or (id ~= nil and a.id ~= id) or now() - a.t > (maxAge or AIM_MAX_AGE) then
		return nil
	end
	return a.aim, a.target
end

---------------------------------------------------------------------------------------------------
-- the mode (Gear Fifth): st.mode = { char, untilT, startT }; the character attribute Gear5Until mirrors it

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

-- "Damage", "TickDamage", "SlamDamage", "FinalDamage", ... (never a *Mul)
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
-- (UltChargeMul) shortens the ultimate's on top. The ultimate = Gear5 (the wide G button) and Bajrang, the move that
-- exists only inside it. ShopService writes both attributes.
local ULT_SKILLS = { Gear5 = true, Bajrang = true }
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
		mul = (cm and tonumber(cm[skill])) or 1
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

function S.startMode(p, char, secs)
	if not char or not char.Parent then
		return
	end
	local st = S.state(p)
	local t = now()
	local untilT = t + (tonumber(secs) or (CFG.Mode and CFG.Mode.Time) or 15)
	st.mode = { char = char, untilT = untilT, startT = t }
	char:SetAttribute("Gear5Until", untilT)
	S.log("%s: Gear Fifth for %.1fs", p.Name, untilT - t)
end

-- no-op when off. Clears the mode + Gear5Until and tells every client (Gear5End)
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
		char:SetAttribute("Gear5Until", nil)
	end
	S.fire("Gear5End", { userId = p.UserId, t0 = now(), why = why, char = char })
	S.log("%s: Gear Fifth ended (%s)", p.Name, why)
end

-- (added) an invisible ForceField "GomuShield" on the caster for `secs` (the ult's cinematic); a second call extends it
function S.shield(char, secs)
	if not char or not char.Parent then
		return nil
	end
	secs = tonumber(secs) or 1
	local ff = char:FindFirstChild("GomuShield")
	if not (ff and ff:IsA("ForceField")) then
		ff = Instance.new("ForceField")
		ff.Name = "GomuShield"
		ff.Visible = false
		ff.Parent = char
	end
	local untilT = math.max(tonumber(ff:GetAttribute("Until")) or 0, os.clock() + secs)
	ff:SetAttribute("Until", untilT)
	task.delay(secs + 0.02, function()
		if ff.Parent and os.clock() >= (tonumber(ff:GetAttribute("Until")) or 0) - 0.05 then
			ff:Destroy()
		end
	end)
	return ff
end

---------------------------------------------------------------------------------------------------
-- bodies: tagged RagdollNPC bodies in workspace (alive OR dead unless o.alive) PLUS, with CFG.AffectPlayers, every
-- OTHER player's living character. The caster is always left out. Every row carries pl (the victim Player | nil)

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

local function playerOf(m)
	local fake = T.fakePlayers and T.fakePlayers[m] -- harness only: { [model] = stand-in player }
	if fake then
		return fake
	end
	return (typeof(m) == "Instance" and m:IsA("Model")) and Players:GetPlayerFromCharacter(m) or nil
end
S.playerOf = playerOf -- added

function S.isRagdolled(m)
	if RagdollService and RagdollService.IsRagdolled then
		local ok, res = pcall(RagdollService.IsRagdolled, m)
		if ok then
			return res == true
		end
	end
	return m:GetAttribute("Ragdolled") == true
end

-- every hittable body except `me`
local function targetsExcept(me)
	local list, has = {}, {}
	for _, m in ipairs(CollectionService:GetTagged(TAG)) do
		if m ~= me and not has[m] and m:IsDescendantOf(workspace) and torsoOf(m) then
			has[m] = true
			table.insert(list, m)
		end
	end
	if CFG.AffectPlayers then
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			if ch and ch ~= me and not has[ch] and ch:IsDescendantOf(workspace) and torsoOf(ch) and alive(ch) then
				has[ch] = true
				table.insert(list, ch)
			end
		end
		for ch in pairs(T.fakePlayers or {}) do -- harness only
			if ch ~= me and not has[ch] and ch.Parent and torsoOf(ch) and alive(ch) then
				has[ch] = true
				table.insert(list, ch)
			end
		end
	end
	return list
end

-- every hittable body (the running cast's caster left out)
function S.targets()
	return targetsExcept(casterChar(nil))
end

-- the shared o filters: alive, exclude, skipHeld, maxDY (|tp.Y - refY|), then los (clearLine from o.los)
local function admits(m, tp, o, refY)
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

-- { { m, tp, d, torso, pl } } sorted by d (3D distance from pos to the torso)
function S.inRadius(pos, r, o)
	o = o or {}
	if not finite(pos) or not r then
		return {}
	end
	if o.los then
		refreshIgnore()
	end
	local out = {}
	PvPBal.setAim(pos, nil)
	for _, m in ipairs(targetsExcept(casterChar(o))) do
		local torso = torsoOf(m)
		local tp = torso.Position
		local d = (tp - pos).Magnitude
		if d <= r and admits(m, tp, o, pos.Y) and seen(o, tp) then
			table.insert(out, { m = m, tp = tp, d = d, torso = torso, pl = playerOf(m) })
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, part, d, pl } }: UpperTorso / LowerTorso / Head (R6: Torso / Head / HRP) inside the oriented box (+0.5);
-- sorted by d (distance from the box centre)
local BOX_PARTS = { "UpperTorso", "LowerTorso", "Head" }
local BOX_PARTS_R6 = { "Torso", "Head", "HumanoidRootPart" }
function S.inBox(cf, size, o)
	o = o or {}
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return {}
	end
	if o.los then
		refreshIgnore()
	end
	local hx, hy, hz = size.X * 0.5 + 0.5, size.Y * 0.5 + 0.5, size.Z * 0.5 + 0.5
	local out = {}
	PvPBal.setAim(cf.Position, nil)
	for _, m in ipairs(targetsExcept(casterChar(o))) do
		local names = m:FindFirstChild("UpperTorso") and BOX_PARTS or BOX_PARTS_R6
		local tp = torsoOf(m).Position
		if admits(m, tp, o, cf.Position.Y) then
			local inside = {}
			if PvPBal.isForm(m) then -- (2026-11-08) a giant form: its body point nearest the box centre
				local l = cf:PointToObjectSpace(tp)
				if math.abs(l.X) <= hx and math.abs(l.Y) <= hy and math.abs(l.Z) <= hz then
					table.insert(inside, torsoOf(m))
				end
			end
			for _, n in ipairs(names) do
				local part = m:FindFirstChild(n)
				if part and part:IsA("BasePart") then
					local l = cf:PointToObjectSpace(part.Position)
					if math.abs(l.X) <= hx and math.abs(l.Y) <= hy and math.abs(l.Z) <= hz then
						table.insert(inside, part)
					end
				end
			end
			if #inside > 0 then
				local okPart
				if seen(o, tp) then
					okPart = inside[1]
				else
					for _, part in ipairs(inside) do
						if seen(o, part.Position) then
							okPart = part
							break
						end
					end
				end
				if okPart then
					table.insert(out, { m = m, tp = tp, part = okPart, d = (tp - cf.Position).Magnitude, pl = playerOf(m) })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, d, ang, pl } }: flat distance <= range, flat angle from the flat aim <= halfDeg, |dY| <= o.maxDY (12);
-- sorted by d
function S.inCone(origin, aim, range, halfDeg, o)
	o = o or {}
	if not finite(origin) then
		return {}
	end
	if o.los then
		refreshIgnore()
	end
	local maxDY = o.maxDY or 12
	local fa = flatDir(aim)
	local out = {}
	PvPBal.setAim(origin, nil)
	for _, m in ipairs(targetsExcept(casterChar(o))) do
		local tp = torsoOf(m).Position
		local rel = tp - origin
		local fl = rel * FLAT
		local d = fl.Magnitude
		local ang = angleTo(fl, fa)
		if d <= range and ang <= halfDeg and math.abs(rel.Y) <= maxDY and admits(m, tp, o, nil) and seen(o, tp) then
			table.insert(out, { m = m, tp = tp, d = d, ang = ang, pl = playerOf(m) })
		end
	end
	table.sort(out, function(a, b)
		return a.d < b.d
	end)
	return out
end

-- { { m, tp, along, off, pl } }: 3D distance from the torso to the segment a->b <= r, `along` (the projection on a->b)
-- in [-1, len + 2]; maxDY is measured from the segment point nearest the body; sorted by along
function S.nearSegment(a, b, r, o)
	o = o or {}
	if not finite(a) or not finite(b) then
		return {}
	end
	if o.los then
		refreshIgnore()
	end
	local d = b - a
	local len = d.Magnitude
	local u = len > 1e-3 and d / len or nil
	local out = {}
	for _, m in ipairs(targetsExcept(casterChar(o))) do
		local fc = PvPBal.formCenter(m) -- (2026-11-08) a giant form: its body point nearest the line
		if fc then
			PvPBal.setAim(u and (a + u * math.clamp((fc - a):Dot(u), 0, len)) or a, nil)
		end
		local tp = torsoOf(m).Position
		local rel = tp - a
		local along = u and rel:Dot(u) or 0
		local near = u and (a + u * math.clamp(along, 0, len)) or a
		local off = (tp - near).Magnitude
		if along >= -1 and along <= len + 2 and off <= r and admits(m, tp, o, near.Y) and seen(o, tp) then
			table.insert(out, { m = m, tp = tp, along = along, off = off, pl = playerOf(m) })
		end
	end
	table.sort(out, function(x, y)
		return x.along < y.along
	end)
	return out
end

---------------------------------------------------------------------------------------------------
-- hits. NPC bodies: RagdollService on the server (copied from ZangetsuServer.Core). PLAYER bodies: the Tempest dodge
-- first, then damage here and the knockback on their own client (Remotes.Knockback) - never moved from the server

local evadedAt = setmetatable({}, { __mode = "k" }) -- [character] = os.clock() of its last dodge

-- true = the victim player dodged (Tempest's eye / the Ascendant silver form blinked them behind the attacker)
local function evaded(p, m)
	if not Evasion or not playerOf(m) then
		return false
	end
	local ok, res = pcall(Evasion.tryEvade, m, p and p.Character or nil)
	if ok and res == true then
		evadedAt[m] = os.clock()
		return true
	end
	return false
end
local function justEvaded(m)
	local c = evadedAt[m]
	return c ~= nil and os.clock() - c < EVADE_GRACE
end

-- the knockback a player victim's own client applies (GomuClient handles Remotes.Knockback on every client). A giant
-- form (Morphed) barely budges and StaggerResist shrugs part of it off, as in the other PvP kits
local function knock(pl, m, vel, ragTime, keepFrac)
	if not pl then
		return
	end
	if m and PvPBal.absorbed and PvPBal.absorbed(m) then
		return -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble
	end
	vel = finite(vel) and vel or Vector3.zero
	local resist = m and m:GetAttribute("StaggerResist")
	resist = type(resist) == "number" and math.clamp(resist, 0, 0.9) or 0
	if m and m:GetAttribute("Morphed") then
		vel *= 0.15
	end
	vel *= (1 - resist)
	if vel.Magnitude > KNOCK_MAX then
		vel = vel.Unit * KNOCK_MAX
	end
	local rag = math.clamp(tonumber(ragTime) or 0, 0, RAG_MAX) * (1 - resist)
	if m then
		PvPBal.markDown(m, rag) -- (2026-11-08) the server's clock for "lying on the ground" (M1 strings skip it)
	end
	Knockback:FireClient(pl, vel * PvPBal.knockMul(), rag, math.clamp(tonumber(keepFrac) or 0, 0, 1))
end
S.knock = knock -- added (Core-internal; moves use strike / push / react)

-- damage (living only) + kill credit; true when health was taken
local function dealDamage(p, m, damage)
	if type(damage) ~= "number" or damage <= 0 then
		return false
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and m:GetAttribute("Dead") ~= true then
		if p then
			m:SetAttribute("LastHitBy", p.UserId)
		end
		hum:TakeDamage(PvPBal.dmg(hum, damage))
		return true
	end
	return false
end

-- velocities pinned at zero for `secs`, then `after()`: the server half of the hit-stop (a player's body is never
-- touched: only `after` runs)
local function freezeBody(m, secs, after)
	local untilT = os.clock() + (secs or 0)
	local isPlayer = playerOf(m) ~= nil
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
		if isPlayer then
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

-- damage + kill credit + ragdoll + (optionally hit-stopped) fling. Held bodies take the damage and the ragdoll but
-- keep still; vel nil = ragdoll only. o = { hitStop, spin, keep (players: fraction of their velocity kept) }.
-- Returns landed: false when nothing was hit (gone, the caster himself, or a player who dodged)
function S.strike(p, m, vel, damage, rag, o)
	o = o or {}
	if not m or not m.Parent or (p and p.Character == m) then
		return false
	end
	rag = rag or 3
	local pl = playerOf(m)
	if pl then
		if not alive(m) or evaded(p, m) then
			return false
		end
		dealDamage(p, m, damage)
		if held(m) then
			return true
		end
		local hs = tonumber(o.hitStop) or 0
		if hs > 0 then
			task.delay(hs, function()
				if m.Parent then
					knock(pl, m, vel, rag, o.keep)
				end
			end)
		else
			knock(pl, m, vel, rag, o.keep)
		end
		return true
	end
	dealDamage(p, m, damage)
	if not RagdollService then
		return true
	end
	if not finite(vel) or held(m) then
		RagdollService.Ragdoll(m, rag)
		return true
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
	return true
end

-- damage + kill credit only (a player victim may dodge it); returns landed
function S.hurt(p, m, damage)
	if not m or not m.Parent or type(damage) ~= "number" or damage <= 0 or (p and p.Character == m) then
		return false
	end
	if playerOf(m) and evaded(p, m) then
		return false
	end
	return dealDamage(p, m, damage)
end

-- StunnedUntil = now + secs on a living body (an NPC's AI pauses; a player can't move or act - PvPStunClient and the
-- kits' gates, 2026-11-08); never shortens a longer stun
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

-- the punch knock: a standing NPC body's HRP velocity (held bodies are never moved); a player gets a shove (no tumble)
function S.push(m, vel)
	if not m or not m.Parent or held(m) or not finite(vel) then
		return
	end
	local pl = playerOf(m)
	if pl then
		if m ~= (casterNow() and casterNow().Character) and not justEvaded(m) then
			knock(pl, m, vel, 0, 0)
		end
		return
	end
	local hrp = m:FindFirstChild("HumanoidRootPart")
	if hrp and not hrp.Anchored then
		hrp.AssemblyLinearVelocity = vel
	end
end

-- the standing-body M1 reaction. NPC: HitReact.mark (the flinch clip every client plays: style "flinch" | "twist" |
-- "fold" | "lift", power ~0.4..1.6) + HitReact.slide (slideStuds over 0.12 s) + S.stun(stunSecs). Player: a shove of
-- push * slideStuds * 8 studs/s (no tumble). Call it after S.hurt
function S.react(p, m, push, power, style, slideStuds, stunSecs)
	if not m or not m.Parent or (p and p.Character == m) then
		return
	end
	local dir = (finite(push) and push.Magnitude > 1e-3) and push.Unit or nil
	local pl = playerOf(m)
	if pl then
		if dir and not justEvaded(m) and not held(m) then
			knock(pl, m, dir * (tonumber(slideStuds) or 1) * 8, 0, 0)
		end
		return
	end
	if HitReact then
		if HitReact.mark then
			local ok, err = pcall(HitReact.mark, m, dir or push, power, style)
			if not ok then
				S.warn("HitReact.mark", err)
			end
		end
		if dir and HitReact.slide and (tonumber(slideStuds) or 0) > 0 and not held(m) and not S.isRagdolled(m) then
			local ok, err = pcall(HitReact.slide, m, dir, slideStuds, 0.12)
			if not ok then
				S.warn("HitReact.slide", err)
			end
		end
	end
	S.stun(m, stunSecs or 0)
end

-- reel a body toward a point (call every Heartbeat): homing velocity, no spin. False once it can no longer be reeled.
-- A player is pulled by their own client (a shove at most 10 times a second)
local reelSent = setmetatable({}, { __mode = "k" })
function S.reel(m, slot, gain, maxSpeed, rag)
	local tt = m and m.Parent and torsoOf(m)
	if not tt or held(m) or not finite(slot) then
		return false
	end
	local v = (slot - tt.Position) * (gain or 8)
	if v.Magnitude > (maxSpeed or 120) then
		v = v.Unit * (maxSpeed or 120)
	end
	local pl = playerOf(m)
	if pl then
		if justEvaded(m) then
			return false
		end
		local c = os.clock()
		if c - (reelSent[m] or 0) >= 0.1 then
			reelSent[m] = c
			knock(pl, m, v, 0, 0)
		end
		return true
	end
	if not RagdollService then
		return false
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

-- every target within `radius` of pos flung straight out (flat, + UP * o.up, normalised); k = 1 - d / radius:
-- damage = o.damage * (farMul + (1 - farMul) * k), speed = flingFar + (flingNear - flingFar) * k; S.strike each with
-- o.rag / o.hitStop. o = { damage, farMul (0.5), flingNear (120), flingFar (near * 0.6), up (0.4), rag, hitStop,
-- spin, exclude, los (true = from pos, lifted 1.5), alive, skipHeld, maxDY, loose (false = no prop shove) }.
-- Returns the rows (each with k and landed added)
function S.radial(p, pos, radius, o)
	o = o or {}
	if not finite(pos) or type(radius) ~= "number" or radius <= 0 then
		return {}
	end
	local excl = {}
	for m, v in pairs(o.exclude or {}) do
		excl[m] = v
	end
	local me = p and p.Character
	if me then
		excl[me] = true
	end
	local los = nil
	if o.los == true then
		los = pos + UP * 1.5
	elseif finite(o.los) then
		los = o.los
	end
	local rows = S.inRadius(pos, radius, {
		alive = o.alive, exclude = excl, skipHeld = o.skipHeld, maxDY = o.maxDY, los = los, caster = me or o.caster,
	})
	local farMul = tonumber(o.farMul) or 0.5
	local near = tonumber(o.flingNear) or 120
	local far = tonumber(o.flingFar) or near * 0.6
	local up = tonumber(o.up) or 0.4
	local damage = tonumber(o.damage) or 0
	for _, r in ipairs(rows) do
		local k = math.clamp(1 - r.d / radius, 0, 1)
		local out = (r.tp - pos) * FLAT
		out = out.Magnitude > 0.5 and out.Unit or S.randomFlat()
		local dir = (out + UP * up).Unit
		r.k = k
		r.landed = S.strike(p, r.m, dir * (far + (near - far) * k), damage * (farMul + (1 - farMul) * k), o.rag,
			{ hitStop = o.hitStop, spin = o.spin })
	end
	if o.loose ~= false then
		S.pushLoose(pos, radius, near, up)
	end
	return rows
end

-- a GroundFX crater must never open under the caster's own feet (the self-healing terrain closes over him): if his
-- root stands within r + 1.5 of the centre (and near its height), the centre slides out until he is on the rim
local function offFeet(p, g, r)
	local ch = p and p.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root or not finite(g) then
		return g
	end
	local rel = root.Position - g
	if math.abs(rel.Y) > r + 8 then
		return g
	end
	local need = r + 1.5
	local fl = rel * FLAT
	if fl.Magnitude >= need then
		return g
	end
	local away = fl.Magnitude > 0.2 and -fl.Unit or S.randomFlat()
	local moved = Vector3.new(root.Position.X, g.Y, root.Position.Z) + away * need
	return S.groundAt(moved, 24) or moved
end

-- the ONE destruction call. WorldBlast(pos, radius, uid) always; o.dir: + BreakBlast(pos, radius, dir, o.speed or 120,
-- uid). CityDestruction punches building holes / street craters only for radius >= 6 (smaller = glass, panels, props).
-- o.crater = { r, rocks, speed, depth? } (or { r, rocks, speed } positional): a GroundFX crater at the ground under pos;
-- o.ring = { r, n, size, rocks, speed, delay?, depth? }: n GroundFX craters round pos at r (delay = s between each);
-- o.threat = { radius, secs } (or positional): NPCs flee (GojoServer.Threat). Craters never open under the caster.
function S.blast(p, pos, radius, o)
	o = o or {}
	if not finite(pos) or type(radius) ~= "number" or radius <= 0 then
		return
	end
	local uid = p and p.UserId or 0
	S.hook("WorldBlast", pos, radius, uid)
	if finite(o.dir) and o.dir.Magnitude > 1e-3 then
		S.hook("BreakBlast", pos, radius, o.dir.Unit, tonumber(o.speed) or 120, uid)
	end
	local cr = o.crater
	if type(cr) == "table" then
		local r = tonumber(cr.r or cr[1])
		if r and r > 0 then
			local g = S.groundAt(pos, tonumber(cr.depth or cr[4]) or 14)
			if g then
				S.ground("impact", offFeet(p, g, r), r, tonumber(cr.rocks or cr[2]) or 8, tonumber(cr.speed or cr[3]) or 60)
			end
		end
	end
	local ring = o.ring
	if type(ring) == "table" then
		local rr = tonumber(ring.r or ring[1]) or radius * 0.6
		local n = math.clamp(math.floor(tonumber(ring.n or ring[2]) or 6), 1, 24)
		local size = tonumber(ring.size or ring[3]) or 3
		local rocks = tonumber(ring.rocks or ring[4]) or 2
		local speed = tonumber(ring.speed or ring[5]) or 60
		local delay = tonumber(ring.delay) or 0
		local depth = tonumber(ring.depth) or 24
		local a0 = math.random() * TAU
		for i = 1, n do
			local a = a0 + (i - 1) / n * TAU
			local pt = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * rr
			local function dig()
				local g = S.groundAt(pt, depth)
				if g then
					S.ground("impact", offFeet(p, g, size), size, rocks, speed)
				end
			end
			if delay > 0 then
				task.delay(delay * i, dig)
			else
				dig()
			end
		end
	end
	local th = o.threat
	if type(th) == "table" then
		S.hook("Threat", pos, tonumber(th.radius or th[1]) or radius, tonumber(th.secs or th[2]) or 1.5)
	end
end

-- the combo counter's hit event (ComboCounter counts it; GojoClient draws a spark only when `pos` is set, and Luffy's
-- own clients draw their own, so it is never sent). Once per M1 swing that hit something
function S.punchHit(p, combo, final, comboKind)
	if not AbilityEvent or not p then
		return
	end
	local ok, err = pcall(AbilityEvent.FireAllClients, AbilityEvent, "PunchHit", {
		by = p.UserId, combo = combo, final = final == true, finisher = final and (comboKind or "blast") or nil,
	})
	if not ok then
		S.warn("PunchHit", err)
	end
end

---------------------------------------------------------------------------------------------------
-- time (the caster of the code that schedules is carried over to the callback: queries keep leaving him out)

-- task.delay to an absolute cast time (t0 + secs); an error inside fn is warned, never silent
function S.at(t0, secs, fn, ...)
	local who = casterNow()
	return task.delay(math.max(t0 + (secs or 0) - now(), 0), function(...)
		local ok, err = asCaster(who, fn, ...)
		if not ok then
			S.warn("at()", err)
		end
	end, ...)
end

-- runs step(e) every Heartbeat (e = server seconds since t0) until it returns true; an error stops it, warns and
-- calls onError() so nothing is left reeling or locked. Returns the connection so __reset can cut it
function S.timeline(label, t0, step, onError)
	local who = casterNow()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local ok, res = asCaster(who, step, now() - t0)
		if not ok then
			conn:Disconnect()
			S.warn(tostring(label), res)
			if onError then
				local ok2, err2 = asCaster(who, onError)
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

local HANDLERS = {} -- [action] = handler(p, st, payload)
local OWNER = {} -- [action] = module name
local RESETS = {} -- { { name, fn } }
local LOADED = {} -- [ModuleScript] = true
local RESERVED = { Aim = true } -- Core handles these itself

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
				if RESERVED[k] then
					S.warn(tag, "handler '" .. k .. "' is Core's own (ignored)", 0)
				elseif HANDLERS[k] then
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
	st.aim = nil
	for _, r in ipairs(RESETS) do
		local ok, err = pcall(r.fn, p, st, why)
		if not ok then
			S.warn("Moves." .. r.name .. ".__reset", err)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- requests

-- "Aim": the steering stream of a running cast { id, aim, target } (ctx.aimStream, <= 15 Hz); S.liveAim reads it
local function takeAim(p, st, payload)
	local id = tonumber(payload.id)
	local aim = payload.aim
	if not id or not finite(aim) or aim.Magnitude < 1e-3 then
		return
	end
	st.aim = { id = id, aim = aim.Unit, target = S.validTarget(payload.target), t = now() }
end

local function route(p, action, payload)
	if typeof(action) ~= "string" or #action > 32 or action:sub(1, 2) == "__" or not equipped(p) then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	if action ~= "Aim" and not HANDLERS[action] then
		return
	end
	-- never "Bajrang" from a client (G always sends "Gear5"); refused outside the mode in case a module exposes it
	if action == "Bajrang" and not S.inMode(p) then
		return
	end
	local st = S.state(p)
	local c = os.clock()
	if c - (st.last[action] or -1e9) < (tonumber(RATE[action]) or RATE_DEFAULT) then
		return
	end
	st.last[action] = c
	if action == "Aim" then
		takeAim(p, st, payload)
		return
	end
	-- sanitise the shared fields once: aim = a unit Vector3 | nil, target = a sane world point | nil
	local aim = payload.aim
	payload.aim = (finite(aim) and aim.Magnitude > 1e-3) and aim.Unit or nil
	payload.target = S.validTarget(payload.target)
	if payload.finisher ~= nil and type(payload.finisher) ~= "string" then
		payload.finisher = nil
	end
	local ok, err = asCaster(p, HANDLERS[action], p, st, payload)
	if not ok then
		S.warn(action, err)
	end
end

---------------------------------------------------------------------------------------------------
-- equip, the hat's lifetime, death / respawn / leave

-- the new kit keeps OwnM1 itself (it owns its M1 too): leave the attribute for its server
local function keepsOwnM1(kit)
	local k = CFG.OwnM1Kits
	if type(k) ~= "table" or type(kit) ~= "string" then
		return false
	end
	if k[kit] == true then
		return true
	end
	return table.find(k, kit) ~= nil
end

local function attachHat(char)
	return hatCall("attach", char, CFG.Hat)
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
		attachHat(char)
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
		loadHat(true) -- retry a missing / broken hat module on every spawn
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
		loadHat(true)
		if char then
			if liveChar(p) == char then
				char:SetAttribute("OwnM1", true)
			end
			if pv.ready[char] and liveChar(p) == char then
				attachHat(char)
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
			hatCall("detach", char)
			if not keepsOwnM1(p:GetAttribute("Kit")) then
				char:SetAttribute("OwnM1", nil)
			end
		end
		-- KitLocked is left alone: the new kit's server owns it now
	end
end

local function onPlayer(p)
	if priv[p] then
		return
	end
	local pv = { ready = setmetatable({}, { __mode = "k" }), conns = {} }
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
-- every frame: the mode's expiry, KitLocked and OwnM1; every second: the hat watchdog

local function watchdog(p, pv)
	local char = p.Character
	if not char then
		return
	end
	if not equipped(p) then
		-- a hat left over from an unequip that ran while the hat module was missing / broken
		if char:FindFirstChild("StrawHat") and (S.Hat or loadHat()) then
			hatCall("detach", char)
		end
		return
	end
	if liveChar(p) ~= char or not pv.ready[char] then
		return
	end
	local H = S.Hat or loadHat()
	if not H then
		return
	end
	local okGet, model = pcall(H.get, char)
	if not okGet or model == nil then
		attachHat(char) -- avatar loading replaced the Head (or the hat was never built)
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
			if equipped(p) then
				-- no switching fighter mid-move (KitServer's SetKit checks this). Only the EQUIPPED kit's server
				-- writes KitLocked (every kit server shares the attribute), so this one keeps out of it otherwise
				local locked = t < st.busyUntil
				if p:GetAttribute("KitLocked") ~= (locked or nil) then
					p:SetAttribute("KitLocked", locked or nil)
				end
				-- OwnM1 every frame: AscendantService clears it on kit switches, the shared punch must never fire
				local char = liveChar(p)
				if char and char:GetAttribute("OwnM1") ~= true then
					char:SetAttribute("OwnM1", true)
				end
			end
		end)
		if not ok then
			S.warn("heartbeat", err, 10)
		end
	end
	local c = os.clock()
	if c >= nextWatch then
		nextWatch = c + WATCH_EVERY
		for p, pv in pairs(priv) do
			local ok, err = pcall(watchdog, p, pv)
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

-- the hat module may be published after this script starts
keep(Kit.ChildAdded:Connect(function(c)
	if c.Name == "Hat" and c:IsA("ModuleScript") and not S.Hat then
		task.defer(loadHat)
	end
end))
task.spawn(function()
	if not loadHat() then
		local inst = Kit:WaitForChild("Hat", 30)
		if inst then
			loadHat()
		else
			S.warn("Hat", "GomuKit.Hat missing after 30 s: no straw hat until it appears", 0)
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
-- purchase is saved; when that player holds this kit, Gear Fifth's (and Bajrang's) cooldown is cleared and the HUD told
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
		S.warn("PerkHooks", "ServerStorage.PerkHooks.UltReset missing: Instant Ult Charge does nothing for Gomu", 0)
	end
end)

-- harness handles (Edit-mode tests load a copy of this source as a ModuleScript and drive these directly)
T.S, T.state, T.priv, T.HANDLERS, T.OWNER, T.RESETS, T.CASTER = S, state, priv, HANDLERS, OWNER, RESETS, CASTER
T.route, T.onPlayer, T.onLeave, T.charAdded, T.markReady, T.died, T.kitChanged = route, onPlayer, onLeave, charAdded,
	markReady, died, kitChanged
T.loadMove, T.loadHat, T.heartbeat, T.watchdog, T.keepsOwnM1 = loadMove, loadHat, heartbeat, watchdog, keepsOwnM1
T.offFeet, T.knock, T.evaded = offFeet, knock, evaded
-- swap a dependency for a stub: "RagdollService" | "GroundFX" | "HitReact" | "Evasion" | "AbilityEvent" | "Knockback"
function T.inject(name, v)
	if name == "RagdollService" then
		RagdollService = v
		S.RagdollService = v
	elseif name == "GroundFX" then
		GroundFX = v
		S.GroundFX = v
	elseif name == "HitReact" then
		HitReact = v
		S.HitReact = v
	elseif name == "Evasion" then
		Evasion = v
		S.Evasion = v
	elseif name == "AbilityEvent" then
		AbilityEvent = v
	elseif name == "Knockback" then
		Knockback = v
	end
end
function T.addPlayer(p)
	-- a harness stand-in player (a table): Core bookkeeping without the Player signals
	priv[p] = { ready = setmetatable({}, { __mode = "k" }), conns = {} }
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

print("[GomuServer] online")
