--!nocheck
-- ServerScriptService.PvP (2026-11-07): the one place that makes a kit's hits land on OTHER PLAYERS.
-- Kits that were written NPC-only (Gojo's CombatService incl. the shared punch, Godspeed, OneForAll, Zangetsu) build
-- their target lists with PvP.bodies(tag, caster), and RagdollService routes any player body to PvP.knock, because
-- the server cannot move a client-owned character: the victim's own client applies the tumble
-- (StarterPlayerScripts.PvPKnockClient). Damage itself (Humanoid:TakeDamage on the server) already worked on players.
-- COMBAT REWORK (2026-11-11): BLOCK, GUARD BREAK and BREAKOUT live here too (section BLOCK at the bottom), because
-- every kit's hit already passes through PvP.dmg - on NPCs and players alike - so one check covers all 10 fighters.
-- Knobs: PvPShared.Balance (BLOCK_* / GUARD_* / BREAKOUT_*). The BLOCK / BREAKOUT requests come in through
-- ServerScriptService.GuardService; StarterPlayerScripts.GuardClient is the key, the pose and the guard bar.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PvP = {}
PvP.NO_PVP = true -- (ragdoll sandbox) co-op: fighters only hit dummies
PvP.onBodyHit = nil -- set by ServerScriptService.Sandbox (hum, amount, isM1) -> amount?
PvP.MAX_SPEED = 320
PvP.MAX_RAG = 2.2 -- a player is never kept tumbling longer than this

-- BALANCE (2026-11-07, "things do too much damage and ultimates are one-tapping people"). Applied ONLY when the
-- victim is a player (NPC damage is unchanged), by every kit through PvP.dmg(hum, amount):
PvP.DAMAGE_MUL = 0.5     -- a hit on a player does half its NPC damage
PvP.HIT_CAP = 0.25       -- no single hit takes more than 25% of max health
PvP.BURST_CAP = 0.35     -- and no more than 35% lands inside one BURST_WINDOW (an ult can't one-shot)
PvP.BURST_WINDOW = 1.0   -- seconds
PvP.KNOCK_MUL = 0.45     -- (legacy name) player knockback for ABILITIES; 2026-11-11 the M1 string has its own - see PvP.knockMul()

local remote = ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Knockback")

function PvP.playerOf(model)
	return typeof(model) == "Instance" and model:IsA("Model") and Players:GetPlayerFromCharacter(model) or nil
end

-- a living player body that can be hit (not spawn-protected)
function PvP.hittable(pl)
	if PvP.NO_PVP then
		return nil -- (ragdoll sandbox) players never hurt each other; only dummies are targets
	end
	local c = pl and pl.Character
	if not c or not c.Parent or not c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildOfClass("ForceField") then
		return nil
	end
	local h = c:FindFirstChildOfClass("Humanoid")
	return (h and h.Health > 0) and c or nil
end

-- FORMS (2026-11-08, "transformations should be able to take damage that a normal player would have taken and have
-- proper hitboxes"). The Titans (4x-14x) and Kurama (5x) scale the player's own rig and wrap it in a skin / beast
-- model; the Susanoo lifts its caster 16.5 studs up inside a 36-stud construct. Every kit aims its hits at a body's
-- root / torso / a few torso points - for a form all of them sit 11-18 studs up, far above where a normal-height
-- attack lands, so forms were nearly unhittable. A form now answers to the box of its whole body: PvP.formPoint(model,
-- from) is the point of that box nearest `from`. The kits' body helpers use it for forms: rootOf / torsoOf return
-- PvP.formRoot(model) - an unparented stand-in part at the box point nearest PvP.aimFrom, which each kit's
-- enemies()/targets() set to the attacker's root and the area queries set to their own centre. Damage is unchanged.
local FORM_MODELS = { TitanSkin = true, BeastConstruct = true, GuardianConstruct = true }
local formBoxes = setmetatable({}, { __mode = "k" })
local stands = setmetatable({}, { __mode = "k" })
PvP.aimFrom = nil -- where the attack being resolved comes from / is centred (a Vector3)
PvP.aimCaster = nil -- the Player making it (their own form is never replaced by a stand-in)

function PvP.isForm(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:GetAttribute("Morphed") then
		return false
	end
	if not PvP.playerOf(model) then
		return false
	end
	if model:GetAttribute("Guardian") then
		return true
	end
	local ok, s = pcall(model.GetScale, model)
	return ok and type(s) == "number" and s >= 1.5
end

local function formBox(model)
	local t = os.clock()
	local b = formBoxes[model]
	if b and t - b.at < 0.05 then
		return b
	end
	local src
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") and FORM_MODELS[c.Name] then
			src = c
			break
		end
	end
	local ok, cf, size = pcall(function()
		return (src or model):GetBoundingBox()
	end)
	if not ok or not cf then
		return nil
	end
	b = { cf = cf, half = size * 0.5, at = t }
	formBoxes[model] = b
	return b
end

function PvP.formCenter(model)
	local b = PvP.isForm(model) and formBox(model)
	return b and b.cf.Position or nil
end

function PvP.formPoint(model, from)
	local b = PvP.isForm(model) and formBox(model)
	if not b then
		return nil
	end
	if typeof(from) ~= "Vector3" or from ~= from then
		return b.cf.Position
	end
	local l = b.cf:PointToObjectSpace(from)
	local h = b.half
	return b.cf:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
end

-- the stand-in root for a form (nil for anything else, and for the attacker's own form)
function PvP.formRoot(model, from)
	if PvP.aimCaster and PvP.playerOf(model) == PvP.aimCaster then
		return nil
	end
	local pt = PvP.formPoint(model, from or PvP.aimFrom)
	if not pt then
		return nil
	end
	local s = stands[model]
	if not s then
		s = Instance.new("Part")
		s.Name = "FormHitPoint"
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CanTouch = false
		s.Transparency = 1
		s.Size = Vector3.new(1, 1, 1)
		stands[model] = s
	end
	s.CFrame = CFrame.new(pt)
	return s
end

-- the attack being resolved: comes from this Player (their root), or is centred on a point (caster nil)
function PvP.setAim(from, caster)
	if typeof(from) == "Instance" and from:IsA("Player") then
		caster = from
		local c = from.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		from = r and r.Position or nil
	end
	PvP.aimFrom = typeof(from) == "Vector3" and from or PvP.aimFrom
	PvP.aimCaster = caster
	PvP.aimT = os.clock() -- (2026-11-11) the block's front check trusts aimFrom only while it is this fresh
end

-- (2026-11-10) an attack resolved AWAY from its caster - a blast's centre, a projectile's current step, a beam's line -
-- re-aims the stand-in there, so a form answers at its body point nearest where the attack really is (enemies() /
-- targets() aim at the CASTER: a chest-high bomb on a 36-stud Susanoo was measured to a point at the caster's own
-- height on its near face, and missed). Call these INSIDE the target loop (the list call resets the aim). The caster
-- (aimCaster) is kept, so their own form is still never a stand-in.
function PvP.aimAt(pos)
	if typeof(pos) == "Vector3" and pos == pos then
		PvP.aimFrom = pos
		PvP.aimT = os.clock()
	end
end

-- the same for a line a-b: the point of the segment nearest the form's centre (a no-op for a body that is not a form)
function PvP.aimSeg(model, a, b)
	if typeof(a) ~= "Vector3" then
		return
	end
	local fc = PvP.formCenter(model)
	if not fc then
		return
	end
	local from = a
	if typeof(b) == "Vector3" then
		local ab = b - a
		local len2 = ab:Dot(ab)
		if len2 > 1e-6 then
			from = a + ab * math.clamp((fc - a):Dot(ab) / len2, 0, 1)
		end
	end
	PvP.aimFrom = from
	PvP.aimT = os.clock()
end

-- tagged NPC bodies plus every OTHER living player's character (caster = the Player casting; nil = no exclusion)
function PvP.bodies(tag, caster)
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged(tag or "RagdollNPC")) do
		table.insert(list, m)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= caster then
			local c = PvP.hittable(pl)
			if c then
				table.insert(list, c)
			end
		end
	end
	return list
end

-- LAG COMPENSATION (2026-11-10, "it's hard to hit people with the normal attack, especially when they're running
-- around"). A melee hit resolves on the server a beat after the swing started (the move's hit delay, 0.12-0.2 s for the
-- punch string) and tests where the server has the victim NOW; but the attacker swung at where THEIR screen showed
-- the victim - the server's copy, one more network trip + the interpolation buffer older. A runner (16-32 studs/s)
-- covers 2-8 studs in that time, so it had left the box by the time the hit was checked. The server therefore keeps a
-- short history of every player's root position, and a melee test also accepts the victim where it stood at any
-- point between the swing's start (as the attacker saw it) and now:
--   PvP.lagOffsets(model, attacker, hitDelay) -> { Vector3 } offsets to ADD to the victim's part positions: the first
--     is Vector3.zero (now), the others step back through that window. NPCs (server-simulated - nothing to undo) get
--     only { Vector3.zero }, so NPC hits are exactly as before.
--   PvP.MELEE_PAD: extra studs on each half-extent of a melee box when the target is a player.
PvP.MELEE_PAD = 1
PvP.LAG_INTERP = 0.1 -- the client's replication interpolation buffer, roughly
PvP.LAG_MAX = 0.6 -- never rewind further than this (a laggy attacker can't hit someone from half a second ago)
local HIST_SECS = 0.8
local hist = {} -- [Player] = { char = Model, t = { os.clock() }, p = { Vector3 } }, oldest first
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		if hrp then
			local h = hist[pl]
			if not h or h.char ~= c then
				h = { char = c, t = {}, p = {} }
				hist[pl] = h
			end
			table.insert(h.t, t)
			table.insert(h.p, hrp.Position)
			while #h.t > 2 and t - h.t[1] > HIST_SECS do
				table.remove(h.t, 1)
				table.remove(h.p, 1)
			end
		else
			hist[pl] = nil
		end
	end
end)
Players.PlayerRemoving:Connect(function(pl)
	hist[pl] = nil
end)
local function histAt(h, t)
	local ts, ps = h.t, h.p
	if t <= ts[1] then
		return ps[1]
	end
	for i = #ts, 2, -1 do
		if ts[i - 1] <= t then
			local span = ts[i] - ts[i - 1]
			local a = span > 0 and (t - ts[i - 1]) / span or 1
			return ps[i - 1]:Lerp(ps[i], math.clamp(a, 0, 1))
		end
	end
	return ps[#ps]
end
function PvP.lagOffsets(model, attacker, hitDelay)
	local pl = PvP.playerOf(model)
	local h = pl and hist[pl]
	if not h or h.char ~= model or #h.t < 2 then
		return { Vector3.zero }
	end
	local ping = 0
	if typeof(attacker) == "Instance" and attacker:IsA("Player") then
		local ok, v = pcall(attacker.GetNetworkPing, attacker)
		ping = ok and tonumber(v) or 0
	end
	local back = math.clamp((tonumber(hitDelay) or 0) + ping + PvP.LAG_INTERP, 0.05, PvP.LAG_MAX)
	local now = os.clock()
	local cur = h.p[#h.p]
	local out = { Vector3.zero }
	for k = 1, 5 do
		local p = histAt(h, now - back * k / 5)
		local off = p - cur
		if off.Magnitude > 0.25 then -- standing still: nothing to rewind
			table.insert(out, off)
		end
	end
	return out
end

-- MELEE PASS (2026-11-09). Knobs in ReplicatedStorage.PvPShared.Balance.
--   PvP.m1Begin() / PvP.m1End(): an M1 string wraps the loop that resolves its hits in these. While the SAME thread is
--     inside, PvP.dmg scales a player's damage by M1_DAMAGE_MUL instead of DAMAGE_MUL, and a hit that lands breaks the
--     victim's cast (below). (Thread-scoped, so an error or a yield inside the loop can't leave it switched on.)
--   PvP.m1Finish(model, vel, rag) -> vel, rag: the normal finisher's throw, softened when the body is a player.
--   PvP.waitCast(char, secs) -> broken: a kit's long wind-up waits through this instead of task.wait / task.delay. It
--     marks the character as casting (CastingUntil) and returns true the moment an M1 lands on it (CastBrokenAt).
local BAL = require(ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Balance"))
PvP.M1_DAMAGE_MUL = tonumber(BAL.M1_PLAYER_DAMAGE_MUL) or 1
PvP.M1_FINISH_KNOCK = tonumber(BAL.M1_FINISHER_KNOCK_MUL) or 0.4
PvP.M1_FINISH_RAG = tonumber(BAL.M1_FINISHER_RAGDOLL) or 1
PvP.CAST_BREAK_COOLDOWN = tonumber(BAL.CAST_BREAK_COOLDOWN) or 3
local m1Thread = nil
local m1Final = false
-- (2026-11-11) final = this swing is the string's FINISHER: on a block it breaks the guard instead of being soaked
function PvP.m1Begin(final)
	m1Thread = coroutine.running()
	m1Final = final == true
end
-- (2026-11-11) the player-knockback multiplier for a knock happening NOW: M1 strings (inside m1Begin .. m1End on this
-- thread) get Balance.M1_KNOCK_MUL, everything else Balance.ABILITY_KNOCK_MUL. Every kit's player-knock site uses it.
PvP.ABILITY_KNOCK_MUL = tonumber(BAL.ABILITY_KNOCK_MUL) or PvP.KNOCK_MUL
PvP.M1_KNOCK_MUL = tonumber(BAL.M1_KNOCK_MUL) or 1
PvP.KNOCK_MUL = PvP.ABILITY_KNOCK_MUL
function PvP.knockMul()
	if m1Thread ~= nil and m1Thread == coroutine.running() then
		return PvP.M1_KNOCK_MUL
	end
	return PvP.ABILITY_KNOCK_MUL
end
function PvP.m1End()
	m1Thread = nil
	m1Final = false
end
function PvP.m1Finish(model, vel, rag)
	if not PvP.playerOf(model) or typeof(vel) ~= "Vector3" then
		return vel, rag
	end
	return vel * PvP.M1_FINISH_KNOCK, math.min(tonumber(rag) or PvP.M1_FINISH_RAG, PvP.M1_FINISH_RAG)
end
function PvP.breakCast(char)
	if typeof(char) ~= "Instance" or not char.Parent then
		return false
	end
	local t = workspace:GetServerTimeNow()
	if (tonumber(char:GetAttribute("CastingUntil")) or 0) <= t then
		return false
	end
	char:SetAttribute("CastBrokenAt", t)
	char:SetAttribute("CastingUntil", nil)
	return true
end
function PvP.castBrokenSince(char, t0)
	return typeof(char) == "Instance" and (tonumber(char:GetAttribute("CastBrokenAt")) or 0) >= t0
end
function PvP.waitCast(char, secs)
	local t0 = workspace:GetServerTimeNow()
	local untilT = t0 + secs
	char:SetAttribute("CastingUntil", untilT)
	local endAt = os.clock() + secs
	local broken = false
	while os.clock() < endAt and char.Parent do
		if PvP.castBrokenSince(char, t0) then
			broken = true
			break
		end
		task.wait()
	end
	if char.Parent and char:GetAttribute("CastingUntil") == untilT then
		char:SetAttribute("CastingUntil", nil)
	end
	return broken
end

-- the damage a hit should really do to this humanoid: unchanged for NPCs; scaled + capped for players
local burst = setmetatable({}, { __mode = "k" })
local guardCheck -- (2026-11-11) the BLOCK section below; nil-safe forward declaration
function PvP.dmg(hum, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 or amount ~= amount or typeof(hum) ~= "Instance" or not hum.Parent then
		return amount
	end
	-- (2026-11-11) a breakout's dodge frames and a held block (front only) come first, for NPCs and players alike
	if guardCheck then
		amount = guardCheck(hum.Parent, amount, m1Thread ~= nil and m1Thread == coroutine.running(), m1Final)
		if amount <= 0 then
			return 0
		end
	end
	if not Players:GetPlayerFromCharacter(hum.Parent) then
		-- (ragdoll sandbox) every kit's hit on a dummy passes here: the injury system reads where it came from
		-- (PvP.aimFrom / PvP.aimCaster are the attack being resolved) and may scale it
		if PvP.onBodyHit then
			local okH, r = pcall(PvP.onBodyHit, hum, amount, m1Thread ~= nil and m1Thread == coroutine.running())
			if okH and type(r) == "number" then
				amount = r
			end
		end
		return amount
	end
	local maxH = math.max(hum.MaxHealth, 1)
	local m1 = m1Thread ~= nil and m1Thread == coroutine.running() -- (2026-11-09) an M1 hit: full damage, breaks a cast
	local d = math.min(amount * (m1 and PvP.M1_DAMAGE_MUL or PvP.DAMAGE_MUL), maxH * PvP.HIT_CAP)
	-- (2026-11-08) a damage-resistant mode (Ichigo's Tensa Zangetsu) writes DamageTakenMul + DamageTakenUntil (server
	-- time) on its character: hits taken while it lasts are scaled by it
	local ch = hum.Parent
	local takenMul = tonumber(ch:GetAttribute("DamageTakenMul"))
	if takenMul and (tonumber(ch:GetAttribute("DamageTakenUntil")) or 0) > workspace:GetServerTimeNow() then
		d *= math.clamp(takenMul, 0, 1)
	end
	local now = os.clock()
	local b = burst[hum]
	if not b or now - b.t0 > PvP.BURST_WINDOW then
		b = { t0 = now, sum = 0 }
		burst[hum] = b
	end
	d = math.max(0, math.min(d, maxH * PvP.BURST_CAP - b.sum))
	b.sum += d
	if m1 and d > 0 then
		PvP.breakCast(ch)
	end
	return d
end

-- (2026-11-14, ragdoll sandbox) a kit's TRUE damage is written straight to Health (the world-cutting slash, the Flaming
-- Thunder God, the Silver Flash), so it never passes PvP.dmg and the sandbox's injury system never saw it. The kit
-- says so here, just before it writes the Health; nothing about the damage changes.
function PvP.trueHit(hum, amount)
	amount = tonumber(amount) or 0
	if PvP.onBodyHit and amount > 0 and typeof(hum) == "Instance" and hum.Parent and not Players:GetPlayerFromCharacter(hum.Parent) then
		pcall(PvP.onBodyHit, hum, amount, false)
	end
end

-- DOWN (2026-11-08, "the M1 shouldn't work on enemies who get flung and are lying on the ground - it defeats the
-- purpose of combos"). Every M1 string (the shared punch, Ichigo's sword, Luffy's string, Goku's combo) asks
-- PvP.isDown(model) and passes over a body that is down: a ragdolled NPC (attribute Ragdolled), or a player still
-- tumbling. A player's tumble runs on their own client, so the server keeps its own clock: everything that sends a
-- player a tumble (PvP.knock below, and each kit's own Knockback remote) calls PvP.markDown, which stamps DownUntil
-- (server time) on the character. Corpses and bodies held by a move (a Blue grab, a domain) are not "down".
PvP.GETUP = 0.5 -- seconds after a tumble that still count as down (the get-up)
local TUMBLE_IMMUNE = { "SuperArmor", "Guardian" } -- forms the knockback clients never tumble
local HELD = { "GrabbedBy", "InDomain", "WhippedBy", "SlashedBy" }

-- RAGDOLL (2026-11-08, "characters should ragdoll when they're stunned and go flying, right now they're planking").
-- Every kit's tumble is PlatformStand on the victim's own client, and the rig's AnimationConstraints stayed rigid, so
-- the body flew like a plank. While a player tumbles, the SERVER now loosens the rig the way RagdollService does for
-- NPCs: AnimationConstraints off (Root kept), the BallSocketConstraints carry the limbs with looser friction, limbs
-- collide, the root goes massless and non-colliding. Joint changes made here replicate, so the owner (who simulates
-- the body) ragdolls it and everyone sees the same thing; StarterPlayerScripts.PvPStunClient puts the owner's
-- humanoid into Physics while the character's Ragdolled attribute is set. The rig is restored when the tumble ends
-- (a corpse stays loose). Giant / form rigs keep their joints.
local RAG_SKIP = { "Morphed", "TitanForm", "FoxBeast", "Guardian", "SuperArmor" }
PvP.RAG_LOOSE = 0.2 -- ball-socket friction x this while ragdolled (RagdollService uses 0.18 for NPCs)
local ragged = {} -- [character] = { untilT, cons, sockets, parts }

local function ragOff(model)
	local r = ragged[model]
	ragged[model] = nil
	if not r then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if model.Parent and hum and hum.Health > 0 then
		for _, c in ipairs(r.cons) do
			if c.Parent then
				c.Enabled = true
			end
		end
		for s, v in pairs(r.sockets) do
			if s.Parent then
				s.Enabled, s.MaxFrictionTorque, s.UpperAngle = v[1], v[2], v[3]
			end
		end
		for p, v in pairs(r.parts) do
			if p.Parent then
				p.CanCollide, p.Massless = v[1], v[2]
			end
		end
	end
	if model.Parent then
		model:SetAttribute("Ragdolled", nil)
	end
end

function PvP.ragdoll(model, secs)
	secs = tonumber(secs) or 0
	if secs <= 0 or secs ~= secs or not PvP.playerOf(model) then
		return
	end
	for _, a in ipairs(RAG_SKIP) do
		if model:GetAttribute(a) then
			return
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or model:GetAttribute("AscForm") == "Instinct" then
		return
	end
	local untilT = os.clock() + math.min(secs, 5)
	local r = ragged[model]
	if r then
		r.untilT = math.max(r.untilT, untilT)
		return
	end
	r = { untilT = untilT, cons = {}, sockets = {}, parts = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			if d.Name ~= "Root" and d.Enabled then
				d.Enabled = false
				table.insert(r.cons, d)
			end
		elseif d:IsA("BallSocketConstraint") and not d:FindFirstAncestorOfClass("Accessory") then
			r.sockets[d] = { d.Enabled, d.MaxFrictionTorque, d.UpperAngle }
			d.Enabled = true
			d.MaxFrictionTorque = d.MaxFrictionTorque * PvP.RAG_LOOSE
			if d.Name == "WaistBallSocket" then
				d.UpperAngle = math.max(d.UpperAngle, 42)
			elseif d.Name == "NeckBallSocket" then
				d.UpperAngle = math.max(d.UpperAngle, 60)
			end
		end
	end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			r.parts[p] = { p.CanCollide, p.Massless }
			if p.Name == "HumanoidRootPart" then
				p.CanCollide = false
				p.Massless = true
			else
				p.CanCollide = true
			end
		end
	end
	ragged[model] = r
	model:SetAttribute("Ragdolled", true)
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for model, r in pairs(ragged) do
		if t >= r.untilT or not model.Parent then
			ragOff(model)
		end
	end
end)

-- STUN (2026-11-08, "make the attacks stun people like they do the npcs in pvp"). An NPC brain stands still while its
-- StunnedUntil (server time) is in the future, and the kits stamp it on whatever they hit. On a PLAYER it now means
-- the same: StarterPlayerScripts.PvPStunClient switches the owner's movement and jumping off, and every kit's server
-- gate refuses the moves of a player who is stunned or down (PvP.stunned). Super-armour forms shrug it off.
PvP.HIT_STUN = 0.3 -- every real hit on a standing player (HitReactServer), like the NPCs
PvP.HIT_STUN_MIN = 3 -- ...when it took at least this much health (chip ticks like a shield aura don't stun-lock)

-- AIR STUN (2026-11-08, "if someone hits goku out of the sky I want him to be stunned for twice as long"). A body that
-- is FLYING (Goku's flight: character attribute Flying) when a stun or a tumble lands on it is knocked out of the air -
-- AscendantClient ends the flight the moment StunnedUntil / Ragdolled is set on it - and that stun, the tumble and the
-- down time all last AIR_STUN_MUL x as long. The air flag holds for AIR_GRACE seconds after the hit, so the rest of
-- the same hit (HitReactServer stamps a stun first, the kit's knockback follows) is doubled too even if the owner has
-- already reported the flight over.
PvP.AIR_STUN_MUL = 2
PvP.AIR_GRACE = 0.5
local airHit = setmetatable({}, { __mode = "k" })
function PvP.airMul(model)
	if typeof(model) ~= "Instance" then
		return 1
	end
	if model:GetAttribute("Flying") == true then
		airHit[model] = os.clock()
		return PvP.AIR_STUN_MUL
	end
	local t = airHit[model]
	if t and os.clock() - t < PvP.AIR_GRACE then
		return PvP.AIR_STUN_MUL
	end
	return 1
end

local function stunImmune(char)
	return char:GetAttribute("SuperArmor") or char:GetAttribute("Guardian") or char:GetAttribute("AscForm") == "Instinct"
end

function PvP.stun(model, secs)
	secs = tonumber(secs) or 0
	if secs <= 0 or secs ~= secs or typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then
		return
	end
	if PvP.absorbed(model) then
		return -- (2026-11-11) the hit was blocked / dodged: no stun
	end
	if PvP.playerOf(model) then
		secs *= PvP.airMul(model) -- hit out of the sky: twice as long
	end
	local t = workspace:GetServerTimeNow() + secs
	if t > (tonumber(model:GetAttribute("StunnedUntil")) or 0) then
		model:SetAttribute("StunnedUntil", t)
	end
end

-- a player who can't act right now: their character is stunned, ragdolled or still down from a tumble
function PvP.stunned(p)
	local char = p and p.Character
	if not char or stunImmune(char) then
		return false
	end
	if (tonumber(char:GetAttribute("StunnedUntil")) or 0) > workspace:GetServerTimeNow() then
		return true
	end
	return PvP.isDown(char)
end

function PvP.markDown(model, ragTime)
	ragTime = tonumber(ragTime) or 0
	if ragTime <= 0 or ragTime ~= ragTime or not PvP.playerOf(model) then
		return
	end
	for _, a in ipairs(TUMBLE_IMMUNE) do
		if model:GetAttribute(a) then
			return
		end
	end
	if model:GetAttribute("AscForm") == "Instinct" or PvP.absorbed(model) then
		return -- (2026-11-11 absorbed: the hit was blocked / dodged, so no tumble)
	end
	ragTime *= PvP.airMul(model) -- hit out of the sky: the tumble and the get-up last twice as long
	local t = workspace:GetServerTimeNow() + math.min(ragTime, 5) + PvP.GETUP
	if t > (tonumber(model:GetAttribute("DownUntil")) or 0) then
		model:SetAttribute("DownUntil", t)
	end
	PvP.ragdoll(model, ragTime) -- a real ragdoll for the tumble, not a plank
end

function PvP.isDown(model)
	if typeof(model) ~= "Instance" or not model.Parent then
		return false
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 or model:GetAttribute("Dead") == true then
		return false -- a corpse isn't "down": the corpse juggle stays
	end
	for _, a in ipairs(HELD) do
		if model:GetAttribute(a) ~= nil then
			return false
		end
	end
	if model:GetAttribute("Ragdolled") == true then
		return true
	end
	return (tonumber(model:GetAttribute("DownUntil")) or 0) > workspace:GetServerTimeNow()
end

-- knock a player body around on its owner's client; returns true when model was a player (callers then skip the
-- server-side ragdoll/physics, which would fight the owner's simulation)
function PvP.knock(model, vel, ragTime, keep)
	local pl = PvP.playerOf(model)
	if not pl then
		return false
	end
	vel = typeof(vel) == "Vector3" and vel or Vector3.zero
	if vel ~= vel then
		vel = Vector3.zero
	end
	if PvP.absorbed(model) then
		-- (2026-11-11) blocked / dodged: only a little pushback along the ground, no tumble
		local flat = Vector3.new(vel.X, 0, vel.Z)
		if flat.Magnitude > 1 then
			remote:FireClient(pl, flat.Unit * math.min(flat.Magnitude * 0.15, 14), 0, 0.3)
		end
		return true
	end
	vel *= PvP.knockMul()
	if model:GetAttribute("Morphed") or model:GetAttribute("TitanForm") then
		vel *= 0.15 -- a giant barely budges
	end
	if vel.Magnitude > PvP.MAX_SPEED then
		vel = vel.Unit * PvP.MAX_SPEED
	end
	local rag = math.clamp(tonumber(ragTime) or 1.2, 0, PvP.MAX_RAG)
	local air = PvP.airMul(model) -- read before markDown (which applies it to the server's down time itself)
	PvP.markDown(model, rag)
	remote:FireClient(pl, vel, math.min(rag * air, 5), keep or 0)
	return true
end

---------------------------------------------------------------------------------------------------
-- BLOCK (2026-11-11). Character attributes (NPCs can carry them too; the server sets them):
--   Blocking (bool)          the guard is up (GuardService sets it from the owner's BLOCK key)
--   Guard (number 0..MAX)    what is left of the guard; nil = full
--   GuardBrokenUntil (time)  no blocking before this server time (a guard break; the kits' own guard-break moves
--                            - Tempest, Carver, Goku's warp kick / silver form - stamp it too)
--   DodgeUntil (time)        a breakout's dodge frames: every hit misses
--   BreakoutAt (time)        the last breakout (the owner's client ends its tumble on it)
-- PvP.dmg calls guardCheck first. A hit is BLOCKED when the body is Blocking, its guard is not broken, and the attack
-- comes from in front (PvP.frontal against the fresh aim point a kit set, else the LastHitBy attacker). A blocked hit:
--   * M1: 0 damage. Its FINISHER (PvP.m1Begin(true)) breaks the guard at once. Abilities: BLOCK_ABILITY_TAKEN of it.
--   * drains the guard; at 0 the guard breaks (stun GUARD_BREAK_STUN, no block for GUARD_BREAK_LOCK).
--   * marks the body ABSORBED for a moment (PvP.absorbed): PvP.stun / markDown / knock, RagdollService.Ragdoll / Fling,
--     HitReactServer's stun and every kit's own knock helper leave it standing (a small pushback at most). Stun stamps a
--     kit writes straight onto StunnedUntil / DownUntil in the same frame are put back afterwards (task.defer).
local absorbedAt = setmetatable({}, { __mode = "k" }) -- [model] = os.clock()
local guardHitAt = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() of the last blocked hit (regen delay)
local guardFX = ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("GuardFX", 10)
local ABSORB_WINDOW = 0.12

local function bal(k, d)
	return tonumber(BAL[k]) or d
end

function PvP.absorbed(model)
	if typeof(model) ~= "Instance" then
		return false
	end
	if (tonumber(model:GetAttribute("DodgeUntil")) or 0) > workspace:GetServerTimeNow() then
		return true -- a breakout's dodge frames: nothing lands, not even a damage-free shove
	end
	local t = absorbedAt[model]
	return t ~= nil and os.clock() - t < ABSORB_WINDOW
end

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
end

function PvP.guardBroken(model)
	return (tonumber(model:GetAttribute("GuardBrokenUntil")) or 0) > workspace:GetServerTimeNow()
end

function PvP.isBlocking(model)
	if typeof(model) ~= "Instance" or model:GetAttribute("Blocking") ~= true or PvP.guardBroken(model) then
		return false
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and model:GetAttribute("Ragdolled") ~= true
end

-- is `from` in front of the blocker (within BLOCK_ARC degrees of its facing)?
function PvP.frontal(model, from)
	local r = rootOf(model)
	if not r or typeof(from) ~= "Vector3" then
		return true
	end
	local to = (from - r.Position) * Vector3.new(1, 0, 1)
	if to.Magnitude < 0.75 then
		return true -- on top of the blocker: count it as in front
	end
	local look = r.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		return true
	end
	return look.Unit:Dot(to.Unit) >= math.cos(math.rad(bal("BLOCK_ARC", 80)))
end

-- where the hit being resolved comes from
local function attackFrom(model)
	if PvP.aimFrom and os.clock() - (PvP.aimT or -1) < 0.6 then
		local c = PvP.aimCaster and PvP.aimCaster.Character
		if not (c and c == model) then
			return PvP.aimFrom
		end
	end
	local uid = model:GetAttribute("LastHitBy")
	local p = uid and Players:GetPlayerByUserId(uid)
	local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

local function fx(kind, model, extra)
	if not guardFX then
		return
	end
	local r = rootOf(model)
	if r then
		guardFX:FireAllClients(kind, model, r.Position, extra)
	end
end

-- this hit is soaked: no stun, tumble or fling from it; direct stun stamps this frame are reverted
local function absorb(model, keepStunUntil)
	absorbedAt[model] = os.clock()
	local prevStun = model:GetAttribute("StunnedUntil")
	local prevDown = model:GetAttribute("DownUntil")
	task.defer(function()
		if not model.Parent then
			return
		end
		local want = math.max(tonumber(prevStun) or 0, keepStunUntil or 0)
		local cur = tonumber(model:GetAttribute("StunnedUntil")) or 0
		if cur > want + 1e-3 then
			model:SetAttribute("StunnedUntil", want > 0 and want or nil)
		end
		if model:GetAttribute("DownUntil") ~= prevDown then
			model:SetAttribute("DownUntil", prevDown)
		end
	end)
end

function PvP.guardBreak(model, by)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local t = workspace:GetServerTimeNow()
	local stunT = t + bal("GUARD_BREAK_STUN", 1.5)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("Guard", 0)
	model:SetAttribute("GuardBrokenUntil", t + bal("GUARD_BREAK_LOCK", 2.5))
	if (tonumber(model:GetAttribute("StunnedUntil")) or 0) < stunT then
		model:SetAttribute("StunnedUntil", stunT)
	end
	guardHitAt[model] = os.clock()
	fx("break", model, by)
	return stunT
end

-- (hum.Parent, raw amount, is an M1, is the M1 finisher) -> the amount that still lands
guardCheck = function(model, amount, m1, final)
	if typeof(model) ~= "Instance" then
		return amount
	end
	local t = workspace:GetServerTimeNow()
	if (tonumber(model:GetAttribute("DodgeUntil")) or 0) > t then
		absorb(model)
		return 0
	end
	if not PvP.isBlocking(model) then
		return amount
	end
	local from = attackFrom(model)
	if from and not PvP.frontal(model, from) then
		return amount -- from the side / behind: the guard doesn't cover it
	end
	local by = model:GetAttribute("LastHitBy")
	if m1 and final then
		absorb(model, PvP.guardBreak(model, by))
		return 0
	end
	local g = tonumber(model:GetAttribute("Guard")) or bal("GUARD_MAX", 100)
	g -= amount * (m1 and bal("GUARD_M1_MUL", 1.6) or bal("GUARD_ABILITY_MUL", 1))
	guardHitAt[model] = os.clock()
	if g <= 0 then
		absorb(model, PvP.guardBreak(model, by))
		return m1 and 0 or amount * bal("BLOCK_ABILITY_TAKEN", 0.4)
	end
	model:SetAttribute("Guard", g)
	absorb(model)
	fx("block", model, by)
	return m1 and 0 or amount * bal("BLOCK_ABILITY_TAKEN", 0.4)
end

-- guard refill (NPCs and players): GUARD_REGEN / s once GUARD_REGEN_DELAY s pass without a blocked hit
local regenAcc = 0
RunService.Heartbeat:Connect(function(dt)
	regenAcc += dt
	if regenAcc < 0.1 then
		return
	end
	local step = regenAcc
	regenAcc = 0
	local now = os.clock()
	local max = bal("GUARD_MAX", 100)
	for model, at in pairs(guardHitAt) do
		if not model.Parent then
			guardHitAt[model] = nil
		elseif now - at >= bal("GUARD_REGEN_DELAY", 1.2) and not PvP.guardBroken(model) then
			local g = (tonumber(model:GetAttribute("Guard")) or max) + bal("GUARD_REGEN", 25) * step
			if g >= max then
				model:SetAttribute("Guard", nil)
				guardHitAt[model] = nil
			else
				model:SetAttribute("Guard", g)
			end
		end
	end
end)

-- BREAKOUT: (player) -> ok, reason. Stunned / tumbling / guard-broken, not held, off cooldown.
function PvP.breakout(pl)
	local char = pl and pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false, "dead"
	end
	for _, a in ipairs(HELD) do
		if char:GetAttribute(a) ~= nil then
			return false, "held"
		end
	end
	local t = workspace:GetServerTimeNow()
	if (tonumber(pl:GetAttribute("BreakoutReadyAt")) or 0) > t + 0.05 then
		return false, "cooldown"
	end
	local stunnedNow = (tonumber(char:GetAttribute("StunnedUntil")) or 0) > t
	if not (stunnedNow or PvP.isDown(char) or char:GetAttribute("Ragdolled") == true) then
		return false, "free"
	end
	pl:SetAttribute("BreakoutReadyAt", t + bal("BREAKOUT_COOLDOWN", 12))
	char:SetAttribute("StunnedUntil", nil)
	char:SetAttribute("DownUntil", nil)
	char:SetAttribute("GuardBrokenUntil", nil)
	char:SetAttribute("DodgeUntil", t + bal("BREAKOUT_IFRAMES", 0.5))
	char:SetAttribute("BreakoutAt", t)
	ragOff(char)
	-- shove everything near away (no damage): NPCs get a short stun too, players a push on their own client
	local R = bal("BREAKOUT_RADIUS", 12)
	local push = bal("BREAKOUT_PUSH", 70)
	for _, m in ipairs(PvP.bodies("RagdollNPC", pl)) do
		local r = m ~= char and rootOf(m)
		local h = r and m:FindFirstChildOfClass("Humanoid")
		if r and h and h.Health > 0 then
			local off = (r.Position - hrp.Position) * Vector3.new(1, 0, 1)
			if off.Magnitude <= R then
				local dir = off.Magnitude > 0.3 and off.Unit or -hrp.CFrame.LookVector
				local v = dir * push * (0.6 + 0.4 * (1 - off.Magnitude / R)) + Vector3.yAxis * 18
				local vp = PvP.playerOf(m)
				if vp then
					remote:FireClient(vp, v, 0, 0)
					PvP.stun(m, 0.35)
				elseif not r.Anchored and m:GetAttribute("Ragdolled") ~= true then
					r.AssemblyLinearVelocity = v
					if (tonumber(m:GetAttribute("StunnedUntil")) or 0) < t + 0.5 then
						m:SetAttribute("StunnedUntil", t + 0.5) -- never shortens a longer stun already on it
					end
				end
			end
		end
	end
	fx("breakout", char, R)
	return true
end

return PvP
