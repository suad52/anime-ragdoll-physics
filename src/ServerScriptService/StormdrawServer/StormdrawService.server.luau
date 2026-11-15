--!nocheck
-- StormdrawService: server side of the Stormdraw kit - a lightning-fast katana fighter. The server owns cooldowns,
-- lock-on, hit detection, damage and every ragdoll impulse; clients only render (they send "Request" and play back
-- "Broadcast") and move their OWN character when a dash says so (a client simulates its own body).
--   Slash  : the M1 sword string (4 cuts; the last launches). Inside Focus it swings faster and the 4th cut hits harder
--   Flash  : an iaido stance, then an instant dash through the locked body; everything on the line is cut 0.3 s later
--   Chain  : six dashes in 1.2 s through up to six bodies, i-frames throughout; the sixth ends in a sky-bolt slam
--   Focus  : 20 s of speed (walk x1.6, jump x1.3, Flash / Chain cooldowns x0.6, a stronger M1)
--   Dragon : a 1 s charge, then a 70-stud dash that bores through everything for true damage and ends in a blast
-- LOCK-ON (StormdrawServer.Targeting.pick): Player > NPC > nothing; with nothing in range a move goes the way the
-- character faces. Ragdoll velocity: NPC bodies get BasePart:ApplyImpulse here (impulseModel); a PLAYER's body is
-- simulated by its owner, so ServerScriptService.PvP.knock sends the velocity to that client, which applies it with
-- ApplyImpulse on every assembly (StarterPlayerScripts.PvPKnockClient) - the same path every kit in this place uses.
-- Character attributes written here: OwnM1 (the shared punch stays out), FocusUntil, StormWalkMul, StormJumpMul.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local PvP = require(ServerScriptService:WaitForChild("PvP"))
local BAL = require(ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Balance"))
local Kit = ReplicatedStorage:WaitForChild("StormdrawKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Targeting = require(script.Parent:WaitForChild("Targeting"))

-- shared pieces from the rest of the game: ragdolls for NPC bodies, self-healing craters, NPC flee, breakables,
-- hit flinches, the dodge forms
local RagdollService, GroundFX, Threat, WorldBlast, HitReact, Evasion
do
	local function try(mod)
		if mod then
			local ok, res = pcall(require, mod)
			if ok then
				return res
			end
			warn("[StormdrawService] " .. mod:GetFullName() .. ": " .. tostring(res))
		end
		return nil
	end
	local gs = ServerScriptService:FindFirstChild("GojoServer")
	RagdollService = try(gs and gs:FindFirstChild("RagdollService"))
	if RagdollService then
		pcall(RagdollService.Init)
	end
	Threat = gs and gs:FindFirstChild("Threat")
	WorldBlast = gs and gs:FindFirstChild("WorldBlast")
	local vs = ServerScriptService:FindFirstChild("VulpineServer")
	GroundFX = try(vs and vs:FindFirstChild("GroundFX"))
	local ts = ServerScriptService:FindFirstChild("TempestServer")
	Evasion = try(ts and ts:FindFirstChild("Evasion"))
	local shared = ReplicatedStorage:FindFirstChild("GojoShared")
	HitReact = try(shared and shared:FindFirstChild("HitReact"))
end

local FXFolder = workspace:FindFirstChild("KitFX") or Instance.new("Folder")
FXFolder.Name = "KitFX"
FXFolder.Parent = workspace

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local FOCUS_CUT = { Flash = true, Chain = true } -- the cooldowns the Focus state shortens
local OWN_M1_KITS = { Zangetsu = true, Ascendant = true, Gomu = true } -- other kits that keep OwnM1 themselves

local function now()
	return workspace:GetServerTimeNow()
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function liveChar(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

local function flatOf(v, fallback)
	local f = typeof(v) == "Vector3" and v * FLAT or Vector3.zero
	return f.Magnitude > 1e-3 and f.Unit or fallback
end

-- a world point the client says its cursor is on (nil if it is not a sane position)
local function validPoint(v)
	if typeof(v) ~= "Vector3" or v ~= v or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5 then
		return nil
	end
	return v
end

local function pick(v, i)
	if type(v) == "table" then
		return v[i] or v[#v]
	end
	return v
end

local function rotateY(v, degrees)
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(v)
end

---------------------------------------------------------------------------------------------------
-- world queries: what a dash can pass through, where the ground is
local filterCache, filterAt = nil, 0
local function worldFilter()
	local t = os.clock()
	if filterCache and t - filterAt < 0.1 then
		return filterCache
	end
	local ignore = { FXFolder }
	if GroundFX and GroundFX.folder then
		table.insert(ignore, GroundFX.folder)
	end
	local debris = workspace:FindFirstChild("KitDebris")
	if debris then
		table.insert(ignore, debris)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	filterCache, filterAt = ignore, t
	return ignore
end
Targeting.init(CFG, worldFilter)

local castRay = RaycastParams.new()
castRay.FilterType = Enum.RaycastFilterType.Exclude

-- a part a dash, a ground probe or a line of sight goes straight through: non-colliding, or loose (flung rocks,
-- rubble, broken props - anything whose assembly is not anchored)
local function passable(inst)
	if not inst:IsA("BasePart") then
		return false
	end
	if not inst.CanCollide then
		return true
	end
	local r = inst.AssemblyRootPart
	return not (r and r.Anchored)
end
Targeting.passable = passable

-- a ray (radius nil) or a swept sphere that only stops on solid, anchored world geometry
local function solidCast(origin, vec, radius)
	local filter = table.clone(worldFilter())
	for _ = 1, 6 do
		castRay.FilterDescendantsInstances = filter
		local hit
		if radius then
			local ok, res = pcall(workspace.Spherecast, workspace, origin, radius, vec, castRay)
			hit = ok and res or workspace:Raycast(origin, vec, castRay)
		else
			hit = workspace:Raycast(origin, vec, castRay)
		end
		if not hit or not passable(hit.Instance) then
			return hit
		end
		table.insert(filter, hit.Instance)
	end
	return nil
end

local function groundBelow(pos, reach)
	local hit = solidCast(pos + UP * 4, Vector3.new(0, -((reach or 60) + 4), 0))
	return hit and hit.Position or nil
end

-- how far a body can dash from `origin` (its root) along `dir` before the world stops it. The sweep runs through the
-- upper body (DASH_LIFT above the root, DASH_RADIUS wide): walls, buildings and anything as tall as a person stop it,
-- a dash still goes over guard rails, benches, kerbs and loose debris, and it never ends inside a wall.
local DASH_LIFT, DASH_RADIUS = 1.8, 0.9
local function clearDistance(origin, dir, dist)
	if dist <= 0.05 then
		return 0
	end
	local hit = solidCast(origin + UP * DASH_LIFT, dir * dist, DASH_RADIUS)
	return hit and math.max(hit.Distance - 0.6, 0) or dist
end

---------------------------------------------------------------------------------------------------
-- player state, cooldowns
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, cdDur = {}, busy = 0, reqs = {}, token = 0, m1 = { combo = 0, last = -1e9, lockUntil = 0, gen = 0 } }
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	while #s.reqs > 0 and t - s.reqs[1] > 1 do
		table.remove(s.reqs, 1)
	end
	if #s.reqs >= 18 then
		return false
	end
	table.insert(s.reqs, t)
	return true
end

local function fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

local function sendCooldown(p, s, skill)
	Broadcast:FireClient(p, "Cooldown", { skill = skill, ends = s.cd[skill] or 0, dur = s.cdDur[skill] or 0 })
end

local function focusOn(p, s)
	local f = s.focus
	return f ~= nil and f.char == p.Character and now() < f.untilT
end

-- a cooldown's length for this player: its perks (CooldownMul, and UltChargeMul for the ultimate), the game-wide
-- non-ultimate multiplier (PvPShared.Balance), and the Focus state's cut on Flash / Chain. The length is sent with
-- the end time, so the client's bar never has to redo this sum.
local function cooldownFor(p, s, skill, base, isUlt)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	local d = base * m * (isUlt and 1 or (tonumber(BAL.NON_ULT_COOLDOWN_MUL) or 1))
	if FOCUS_CUT[skill] and focusOn(p, s) then
		d *= CFG.Focus.CooldownMul
	end
	return d
end

local function startCooldown(p, s, skill, base, isUlt, extra)
	local d = cooldownFor(p, s, skill, base, isUlt) + (extra or 0)
	s.cd[skill] = now() + d
	s.cdDur[skill] = d
	sendCooldown(p, s, skill)
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

-- common gate: alive, not mid-move, not stunned / down, off cooldown (skill nil = no cooldown to check)
local function gate(p, s, skill)
	local char, hum, hrp = liveChar(p)
	if not char or os.clock() < s.busy or PvP.stunned(p) then
		return nil
	end
	local t = now()
	if skill and t < (s.cd[skill] or 0) then
		sendCooldown(p, s, skill)
		return nil
	end
	return char, hum, hrp, t
end

---------------------------------------------------------------------------------------------------
-- damage, impulses, ragdolls

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel` (a ragdolled rig is one assembly
-- per limb); `keep` = how much of the current velocity survives (1 = the impulse is simply added)
local function impulseModel(model, vel, spin, keep)
	local done = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			local root = part.AssemblyRootPart
			if root and not root.Anchored and not done[root] then
				done[root] = true
				local m = root.AssemblyMass
				root:ApplyImpulse((vel - root.AssemblyLinearVelocity * (1 - (keep or 0))) * m)
				if spin then
					root:ApplyAngularImpulse(spin * m)
				end
			end
		end
	end
end

-- hit feedback: damage dealt this frame is batched and broadcast once; the attacker's client confirms the hit
local hitBatch = {}
local function recordHit(attacker, model, amount, big)
	local r = Targeting.rootOf(model)
	if r and amount and amount >= 0.5 and #hitBatch < 60 then
		table.insert(hitBatch, { u = attacker.UserId, p = r.Position, d = amount, big = big or amount >= 35 })
	end
end

-- per-kit damage (PvPShared.Balance.KIT_DAMAGE_MUL[KitId]): a buff scales a hit before the PvP caps, a nerf after
local function kitMul()
	local m = type(BAL.KIT_DAMAGE_MUL) == "table" and tonumber(BAL.KIT_DAMAGE_MUL[CFG.KitId]) or 1
	return m or 1
end

-- ordinary damage (force fields absorb it; on a player PvP.dmg applies the game-wide scale and caps)
local function damage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		local k = kitMul()
		hum:TakeDamage(k >= 1 and PvP.dmg(hum, amount * k) or PvP.dmg(hum, amount) * k)
		recordHit(attacker, model, amount)
	end
end

-- true damage: written straight to Health, so force fields, blocks and invincibility frames never see it
local function trueDamage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		PvP.trueHit(hum, amount) -- (2026-11-14) the sandbox's injuries see true damage too (Sandbox.Powers)
		hum.Health = math.max(hum.Health - amount * kitMul(), 0)
		recordHit(attacker, model, amount, true)
	end
end

-- damage + ragdoll + launch on one body
local function knock(attacker, model, vel, ragTime, amount, keep, isTrue)
	if vel.Magnitude > 320 then
		vel = vel.Unit * 320
	end
	if amount and amount > 0 then
		if isTrue then
			trueDamage(attacker, model, amount)
		else
			damage(attacker, model, amount)
		end
	end
	-- a player: tumbled by their own client (PvPShared.Knockback -> PvPKnockClient -> ApplyImpulse per assembly)
	if PvP.knock(model, vel, math.min(ragTime or 2, CFG.PlayerRagdollMax), keep) then
		return
	end
	-- an NPC: ragdolled and launched right here
	if RagdollService then
		RagdollService.Ragdoll(model, ragTime)
	end
	impulseModel(model, vel, randomUnit() * 6, keep)
end

-- breaks a block: clears "Blocking" and stamps "GuardBrokenUntil" for any block system to respect
local function breakGuard(model, duration)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("GuardBrokenUntil", now() + duration)
end

-- a player in a dodge form (the eye mode, the silver form) may slip a sword cut
local function evaded(model, attackerChar)
	return Evasion ~= nil and PvP.playerOf(model) ~= nil and Evasion.tryEvade(model, attackerChar) == true
end

-- invulnerability frames: an invisible force field (ordinary damage is absorbed and other kits stop targeting it)
local function shield(char, duration)
	local ff = Instance.new("ForceField")
	ff.Name = "CastShield"
	ff.Visible = false
	ff.Parent = char
	task.delay(duration, function()
		if ff.Parent then
			ff:Destroy()
		end
	end)
	return ff
end

local function worldHooks(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId) -- breakable props
	end
	if Threat then
		Threat:Fire(pos, radius * 2, 2) -- NPCs flee
	end
end

-- the flat direction from `origin` to the locked body (the facing when there is none)
local function lockDir(origin, facing, lock)
	local pt = lock and Targeting.alive(lock) and Targeting.pointOf(lock)
	return pt and flatOf(pt - origin, facing) or facing
end

-- where a dash goes: through the locked body, ending `pass` studs beyond it (at most `range`); with no lock, `range`
-- studs the way the caster faces
local function dashAim(origin, facing, lock, range, pass)
	if lock and Targeting.alive(lock) then
		PvP.aimAt(origin)
		local root = Targeting.rootOf(lock)
		if root then
			local off = root.Position - origin
			if math.abs(off.Y) < 2 then
				off = off * FLAT -- level ground: a flat dash
			end
			if off.Magnitude > 0.5 and off.Magnitude <= range + 12 then
				return off.Unit, math.min(off.Magnitude + pass, range)
			end
		end
	end
	return facing, range
end

---------------------------------------------------------------------------------------------------
-- M1: the sword string. Like every M1 in this place the swing locks onto the first standing body in a corridor along
-- the aim (PvPShared.Balance M1_LOCK_*), its hits are resolved inside PvP.m1Begin / m1End (full damage on players,
-- a landed hit breaks a cast), bodies that are down are passed over, and the finisher's throw on a player is softened
-- by PvP.m1Finish. Inside the Focus state the string is FocusSpeedMul faster and every 4th cut adds FocusBonus on top
-- of the launch (and keeps the body down for FocusBonusRagdoll).
local function react(m, combo, dir)
	if not HitReact then
		return
	end
	local right = dir:Cross(UP)
	local push, style = dir, "flinch"
	if right.Magnitude > 1e-3 then
		right = right.Unit
		if combo == 1 then
			push, style = (dir * 0.45 + right * 0.9 + UP * 0.3).Unit, "twist" -- the rising draw cut, left to right
		elseif combo == 2 then
			push, style = (dir * 0.45 - right * 0.9).Unit, "twist" -- the return cut, right to left
		else
			push, style = (dir * 0.8 + right * 0.5).Unit, "twist" -- the spinning cut
		end
	end
	pcall(HitReact.mark, m, push, combo == 3 and 1.25 or 1.1, style)
	if HitReact.slide then
		pcall(HitReact.slide, m, flatOf(push, dir), CFG.Slash.HitSlide, 0.12)
	end
end

local function resolveSlash(p, s, char, gen, combo, final, dir, lock, focus, hitAt)
	if s.m1.gen ~= gen then
		return
	end
	local c2, _, hrp = liveChar(p)
	if c2 ~= char or p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local S = CFG.Slash
	local pos = hrp.Position
	local chest = pos + UP
	local cf = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -S.Range)
	local rows = Targeting.inBox(p, cf, S.HitboxSize, hitAt)
	-- the swing's lock-on body is cut too while it is still in reach, even if the box missed it
	if lock and Targeting.alive(lock) and not PvP.isDown(lock) then
		local found = false
		for _, r in ipairs(rows) do
			if r.model == lock then
				found = true
				break
			end
		end
		if not found then
			PvP.aimAt(pos)
			local pt = Targeting.pointOf(lock)
			if pt and (pt - pos).Magnitude <= (tonumber(BAL.M1_LOCK_REACH) or 12) + 2 then
				table.insert(rows, 1, { model = lock })
			end
		end
	end
	local dmg = pick(S.Damage, combo)
	local hits = {}
	PvP.m1Begin()
	for _, r in ipairs(rows) do
		local m = r.model
		PvP.aimAt(pos)
		local pt = Targeting.pointOf(m)
		if pt and Targeting.sight(chest, pt) and not evaded(m, char) then
			if final then
				local L = S.FinalLaunch
				local vel, rag = PvP.m1Finish(m, dir * L.X + UP * L.Y, S.RagdollTime)
				if focus then
					-- the Focus bonus: every 4th cut throws harder and keeps the body down longer
					vel += dir * S.FocusBonus.X + UP * S.FocusBonus.Y
					rag = math.max(rag or 0, S.FocusBonusRagdoll)
				end
				knock(p, m, vel, rag, dmg)
			else
				damage(p, m, dmg)
				PvP.stun(m, S.StunTime)
				react(m, combo, dir)
			end
			table.insert(hits, { m = m, p = pt })
		end
	end
	PvP.m1End()
	if #hits > 0 then
		fire("SlashHit", { userId = p.UserId, combo = combo, final = final, focus = focus, dir = dir, hits = hits })
	end
	worldHooks(p, chest + dir * S.Range, 4.5)
	if final and GroundFX then
		local g = groundBelow(pos, 10)
		if g then
			GroundFX.ring(g, 4, focus and 7 or 4, 25)
		end
	end
end

local function castSlash(p, s, payload)
	local char, _, hrp, t = gate(p, s, nil)
	if not char then
		return
	end
	local S = CFG.Slash
	local focus = focusOn(p, s)
	local speed = focus and S.FocusSpeedMul or 1
	local m = s.m1
	if t - m.last < S.SwingInterval * speed - 0.04 or t < m.lockUntil then
		return
	end
	if t - m.last > S.ComboResetTime then
		m.combo = 0
	end
	local combo = m.combo % S.ComboLength + 1
	m.combo, m.last = combo, t
	local final = combo == S.ComboLength
	if final then
		m.lockUntil = t + S.FinalCooldown * speed
	end
	local dir = flatOf(payload.aim, flatOf(hrp.CFrame.LookVector, -Vector3.zAxis))
	local lock, at = Targeting.corridor(p, hrp.Position, dir, tonumber(BAL.M1_LOCK_REACH) or 12, tonumber(BAL.M1_LOCK_RADIUS) or 3.5)
	if lock and at then
		dir = flatOf(at - hrp.Position, dir) -- the swing turns to its target
	end
	local hitAt = pick(S.HitAt, combo) * speed
	fire("Slash", { userId = p.UserId, combo = combo, dir = dir, hitAt = hitAt, focus = focus, final = final, target = lock })
	local gen = m.gen
	task.delay(hitAt, function()
		local ok, err = pcall(resolveSlash, p, s, char, gen, combo, final, dir, lock, focus, hitAt)
		if not ok then
			PvP.m1End()
			warn("[StormdrawService] Slash: " .. tostring(err))
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 1: the flash. The stance locks on (Player > NPC > the facing); after WindUp the dash line is fixed - through
-- the locked body where it is NOW, PassThrough studs beyond it, never more than Range, stopped early by the world -
-- and the caster's client snaps along it in DashTime. Every body within Thickness of the line is cut: held where it
-- stands, its guard broken, and HitDelay after the dash the cut lands - damage, a launch and a ragdoll.
local function castFlash(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Flash")
	if not char then
		return
	end
	local F = CFG.Flash
	startCooldown(p, s, "Flash", F.Cooldown, false, F.WindUp)
	local id = nextId()
	s.busy = os.clock() + F.WindUp + F.DashTime + 0.2
	local facing = flatOf(hrp.CFrame.LookVector, -Vector3.zAxis)
	local lock = Targeting.pick(p, hrp.Position, facing, { range = F.Range, cursor = validPoint(payload.target) })
	local dir0 = lockDir(hrp.Position, facing, lock)
	fire("FlashStart", { id = id, userId = p.UserId, windup = F.WindUp, dir = dir0, target = lock })
	task.spawn(function()
		task.wait(F.WindUp)
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or PvP.stunned(p) or p:GetAttribute("Kit") ~= CFG.KitId then
			fire("FlashCancel", { id = id, userId = p.UserId })
			s.busy = 0
			return
		end
		local origin = h2.Position
		local dir, dist = dashAim(origin, dir0, lock, F.Range, F.PassThrough)
		dist = clearDistance(origin, dir, dist)
		local to = origin + dir * dist
		shield(char, F.IFrames)
		local rows = Targeting.sweep(p, origin, to, F.Thickness)
		local marks = {}
		for _, r in ipairs(rows) do
			table.insert(marks, r.model)
			PvP.stun(r.model, F.DashTime + F.HitDelay + 0.1) -- cut, but it has not landed yet
			breakGuard(r.model, F.GuardBreakTime)
		end
		fire("FlashDash", { id = id, userId = p.UserId, from = origin, to = to, dir = dir, time = F.DashTime, delay = F.HitDelay, marks = marks })
		for d = 6, dist, 12 do
			worldHooks(p, origin + dir * d, 5) -- props on the line break
		end
		if GroundFX then
			local g = groundBelow(origin, 8)
			if g then
				GroundFX.ring(g, 3, 5, 24)
			end
		end
		task.wait(F.DashTime + F.HitDelay)
		local side = dir:Cross(UP)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local hits = {}
		for _, r in ipairs(rows) do
			local m = r.model
			if Targeting.alive(m) and not evaded(m, char) then
				PvP.aimAt(to)
				local pt = Targeting.pointOf(m) or to
				local lateral = (math.random() < 0.5 and -1 or 1) * 0.3
				knock(p, m, (dir * 0.8 + side * lateral + UP * F.UpBias).Unit * F.Impulse, F.RagdollTime, F.Damage)
				table.insert(hits, { m = m, p = pt })
			end
		end
		fire("FlashHit", { id = id, userId = p.UserId, dir = dir, hits = hits })
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: the six-fold ricochet. Up to MaxTargets bodies within Radius are woven into one path: the six dashes
-- cycle through them so the LAST lands on the highest-priority body (one body = six passes through it from six
-- angles; no body at all = a zig-zag the way the caster faces). Each dash ends Overshoot past the body it cuts, its
-- exit turned Deflect degrees to alternating sides, so the trails cross into a web. A body takes Damage over the
-- whole move, split across the cuts that land on it; the sixth cut pops its body up and SlamDelay later a bolt
-- drives it into the ground (FinalShare of the damage, a ragdoll, a crater). The caster is invulnerable throughout.
local function strikeOrder(list, strikes)
	local n = #list
	if n == 0 then
		return nil
	end
	local seq = {}
	for i = strikes, 1, -1 do
		local k = (strikes - i) % n -- 0 for the last strike: list[1], the highest-priority body
		seq[i] = list[(n - k) % n + 1]
	end
	return seq
end

local function castChain(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Chain")
	if not char then
		return
	end
	local C = CFG.Chain
	startCooldown(p, s, "Chain", C.Cooldown, false, C.WindUp + C.Duration)
	local id = nextId()
	s.token += 1
	local tok = s.token
	s.busy = os.clock() + C.WindUp + C.Duration + C.SlamDelay + 0.3
	local legTime = C.Duration / C.Strikes
	local facing = flatOf(hrp.CFrame.LookVector, -Vector3.zAxis)
	fire("ChainStart", { id = id, userId = p.UserId, windup = C.WindUp, strikes = C.Strikes, legTime = legTime, dir = facing })
	task.spawn(function()
		task.wait(C.WindUp)
		local function alive()
			return s.token == tok and liveChar(p) == char and p:GetAttribute("Kit") == CFG.KitId
		end
		local _, _, h2 = liveChar(p)
		if not alive() or PvP.stunned(p) then
			fire("ChainEnd", { id = id, userId = p.UserId, cancelled = true })
			s.busy = 0
			return
		end
		shield(char, C.Duration + C.SlamDelay + 0.2)
		local origin = h2.Position
		facing = flatOf(h2.CFrame.LookVector, facing)
		local g0 = groundBelow(origin, 12)
		local standH = g0 and math.clamp(origin.Y - g0.Y, 2, 4.5) or 3
		local list = Targeting.around(p, origin, C.Radius, C.MaxTargets)
		local seq = strikeOrder(list, C.Strikes)
		local visits = {}
		for _, m in ipairs(seq or {}) do
			visits[m] = (visits[m] or 0) + 1
		end
		local finalBody = seq and seq[C.Strikes] or nil
		local dealt = {}
		-- this cut's share of the move's damage on body m (never more than Damage in total). own = m is this dash's
		-- target; a body a dash merely passes through on the way to another takes a small nick. The slam's share is
		-- held back for it, so the finisher always lands its full FinalShare.
		local function share(m, slam, own)
			local amount, budget
			if slam then
				amount, budget = C.Damage * C.FinalShare, C.Damage
			else
				budget = m == finalBody and C.Damage * (1 - C.FinalShare) or C.Damage
				if not own then
					amount = C.Damage / C.Strikes * 0.5
				else
					amount = budget / math.max(visits[m] or 1, 1)
				end
			end
			amount = math.clamp(amount, 0, budget - (dealt[m] or 0))
			dealt[m] = (dealt[m] or 0) + amount
			return amount
		end
		local cur, lastDir = origin, facing
		for i = 1, C.Strikes do
			if not alive() then
				break
			end
			local target = seq and seq[i] or nil
			if target and not Targeting.alive(target) then
				target = nil
				for _, m in ipairs(list) do
					if Targeting.alive(m) then
						target = m
						break
					end
				end
			end
			local sign = (i % 2 == 0) and 1 or -1
			local to
			PvP.setAim(p)
			PvP.aimAt(cur)
			local root = target and Targeting.rootOf(target)
			if root then
				local tp = root.Position
				to = tp + rotateY(flatOf(tp - cur, lastDir), sign * C.Deflect) * C.Overshoot
			else
				target = nil
				to = cur + rotateY(facing, sign * (C.Deflect + 10)) * C.Overshoot
			end
			local g = groundBelow(to, 40)
			if g and to.Y < g.Y + standH then
				to = Vector3.new(to.X, g.Y + standH, to.Z) -- never under the floor
			end
			local span = to - cur
			local dir = span.Magnitude > 0.5 and span.Unit or lastDir
			local dist = clearDistance(cur, dir, span.Magnitude)
			to = cur + dir * dist
			local final = i == C.Strikes
			local rows = Targeting.sweep(p, cur, to, C.Thickness)
			if target then
				-- the dash's own body is always cut (the lock), unless the world stopped the dash well short of it
				local found = false
				for _, r in ipairs(rows) do
					if r.model == target then
						found = true
						break
					end
				end
				PvP.aimAt(to)
				local pt = not found and Targeting.pointOf(target)
				if pt and (pt - to).Magnitude <= C.Overshoot + 6 then
					table.insert(rows, { model = target })
				end
			end
			local marks = {}
			for _, r in ipairs(rows) do
				local m = r.model
				if not evaded(m, char) then
					table.insert(marks, m)
					breakGuard(m, 1)
					if final and m == finalBody then
						-- popped up now; the bolt drives it down after SlamDelay
						knock(p, m, UP * C.LiftSpeed + dir * 4, C.SlamDelay + 0.6, share(m, false, m == target))
					else
						damage(p, m, share(m, false, m == target))
						PvP.stun(m, C.StunTime)
						if HitReact then
							pcall(HitReact.mark, m, dir, 1.1, (i % 2 == 0) and "twist" or "flinch")
						end
					end
				end
			end
			fire("ChainLeg", {
				id = id, userId = p.UserId, i = i, from = cur, to = to, dir = dir, time = C.DashTime, hold = legTime,
				target = target, final = final, hits = marks,
			})
			worldHooks(p, cur:Lerp(to, 0.5), 6)
			cur, lastDir = to, dir
			task.wait(legTime)
		end
		if alive() and finalBody and Targeting.alive(finalBody) then
			task.wait(math.max(C.SlamDelay - legTime, 0))
			if Targeting.alive(finalBody) then
				PvP.setAim(p)
				PvP.aimAt(cur)
				local root = Targeting.rootOf(finalBody)
				local pos = root and root.Position or cur
				local out = flatOf(pos - cur, lastDir)
				local ground = groundBelow(pos, 60) or pos
				fire("ChainSlam", { id = id, userId = p.UserId, pos = ground, target = finalBody })
				knock(p, finalBody, out * C.Slam.X + UP * C.Slam.Y, C.SlamRagdoll, share(finalBody, true))
				if GroundFX then
					GroundFX.impact(ground, C.SlamCrater, 8, 70)
				end
				worldHooks(p, ground, 10)
			end
		end
		fire("ChainEnd", { id = id, userId = p.UserId, pos = cur, dir = lastDir, cancelled = not alive() })
		s.busy = math.min(s.busy, os.clock() + 0.2)
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the focus state. A breath (Inhale, rooted), then Duration seconds of: walk x WalkMul and jump x JumpMul
-- (character attributes the owner's client applies - it simulates the body), Flash / Chain cooldowns x CooldownMul
-- (cooldownFor; cooldowns already running are cut the moment the state starts), and the stronger M1 (castSlash).
-- Its own cooldown counts from when the state ends.
local function endFocus(p, s)
	local f = s.focus
	if not f then
		return
	end
	s.focus = nil
	local char = f.char
	if char and char.Parent then
		char:SetAttribute("FocusUntil", nil)
		char:SetAttribute("StormWalkMul", nil)
		char:SetAttribute("StormJumpMul", nil)
	end
	if p.Parent then
		startCooldown(p, s, "Focus", CFG.Focus.Cooldown, false)
		fire("FocusOff", { userId = p.UserId })
	end
end

local function castFocus(p, s, payload)
	if s.focus then
		return
	end
	local char, _, hrp = gate(p, s, "Focus")
	if not char then
		return
	end
	local Fo = CFG.Focus
	local id = nextId()
	s.busy = os.clock() + Fo.Inhale
	-- the bar greys the move from the cast; the real cooldown is written when the state ends (endFocus)
	s.cd.Focus = now() + Fo.Inhale + Fo.Duration
	s.cdDur.Focus = Fo.Inhale + Fo.Duration
	fire("FocusStart", { id = id, userId = p.UserId, inhale = Fo.Inhale })
	task.spawn(function()
		task.wait(Fo.Inhale)
		if liveChar(p) ~= char or p:GetAttribute("Kit") ~= CFG.KitId or PvP.stunned(p) then
			fire("FocusCancel", { id = id, userId = p.UserId })
			s.cd.Focus, s.cdDur.Focus = 0, 0
			sendCooldown(p, s, "Focus")
			return
		end
		local untilT = now() + Fo.Duration
		s.focus = { char = char, untilT = untilT }
		char:SetAttribute("StormWalkMul", Fo.WalkMul)
		char:SetAttribute("StormJumpMul", Fo.JumpMul)
		char:SetAttribute("FocusUntil", untilT)
		-- cooldowns already running are cut too
		for skill in pairs(FOCUS_CUT) do
			local rem = (s.cd[skill] or 0) - now()
			if rem > 0 then
				s.cd[skill] = now() + rem * Fo.CooldownMul
				s.cdDur[skill] = math.max((s.cdDur[skill] or rem) * Fo.CooldownMul, rem * Fo.CooldownMul)
				sendCooldown(p, s, skill)
			end
		end
		fire("FocusOn", { id = id, userId = p.UserId, untilT = untilT, duration = Fo.Duration })
		if GroundFX then
			local g = groundBelow(char.HumanoidRootPart.Position, 10)
			if g then
				GroundFX.ring(g, 5, 9, 30)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 4 (the ultimate): the dragon dash. Charge seconds locked in the slumber stance (PvP.waitCast: an M1 that
-- lands cancels it for the short CAST_BREAK_COOLDOWN, like every long wind-up in this place), then a Range-stud dash
-- at the locked body (or the facing) that the world can stop but bodies cannot. As the head passes, every body within
-- Width of the line takes TRUE damage - written straight to Health - and is launched high in a full ragdoll; the
-- ground is trenched under it; and where it ends a blast catches everything within BlastRadius the same way.
local function castDragon(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Dragon")
	if not char then
		return
	end
	local D = CFG.Dragon
	local id = nextId()
	s.token += 1
	local tok = s.token
	s.busy = os.clock() + D.Charge + D.DashTime + 1.2
	startCooldown(p, s, "Dragon", D.Cooldown, true, D.Charge)
	local facing = flatOf(hrp.CFrame.LookVector, -Vector3.zAxis)
	local lock = Targeting.pick(p, hrp.Position, facing, { range = D.Range, cursor = validPoint(payload.target) })
	local dir0 = lockDir(hrp.Position, facing, lock)
	fire("DragonCharge", { id = id, userId = p.UserId, time = D.Charge, dir = dir0, pos = hrp.Position, target = lock })
	task.spawn(function()
		local broke = PvP.waitCast(char, D.Charge)
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or broke or s.token ~= tok or p:GetAttribute("Kit") ~= CFG.KitId then
			fire("DragonCancel", { id = id, userId = p.UserId })
			s.busy = 0
			if broke then
				s.cd.Dragon = now() + PvP.CAST_BREAK_COOLDOWN
				s.cdDur.Dragon = PvP.CAST_BREAK_COOLDOWN
				sendCooldown(p, s, "Dragon")
			end
			return
		end
		local origin = h2.Position
		local dir = lockDir(origin, dir0, lock)
		local dist = clearDistance(origin, dir, D.Range)
		local to = origin + dir * dist
		shield(char, D.DashTime + 0.5)
		fire("DragonDash", { id = id, userId = p.UserId, from = origin, to = to, dir = dir, time = D.DashTime })
		local side = dir:Cross(UP)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local struck = {}
		local function bore(m, vel)
			struck[m] = true
			breakGuard(m, 3)
			PvP.aimAt(origin)
			local pt = Targeting.pointOf(m) or to
			knock(p, m, vel, D.RagdollTime, D.Damage, 0, true)
			fire("DragonHit", { id = id, userId = p.UserId, m = m, p = pt })
		end
		-- the head runs the line; whatever it passes is bored through, and the ground is trenched behind it
		local t0 = os.clock()
		local prev = origin
		local nextTrench = D.TrenchStep * 0.5
		while true do
			local k = math.clamp((os.clock() - t0) / D.DashTime, 0, 1)
			local head = origin + dir * (dist * k)
			for _, r in ipairs(Targeting.sweep(p, prev, head, D.Width)) do
				if not struck[r.model] then
					bore(r.model, UP * D.Launch.Y + dir * D.Launch.X + side * ((math.random() - 0.5) * 30))
				end
			end
			while nextTrench <= dist * k do
				local at = origin + dir * nextTrench
				local g = groundBelow(at, 14)
				if g and GroundFX then
					GroundFX.impact(g, 2.6, 2, 55)
				end
				worldHooks(p, at, D.Width)
				nextTrench += D.TrenchStep
			end
			prev = head
			if k >= 1 or liveChar(p) ~= char then
				break
			end
			RunService.Heartbeat:Wait()
		end
		-- the blast where the dash ends
		fire("DragonBlast", { id = id, userId = p.UserId, pos = to, dir = dir, radius = D.BlastRadius })
		for _, b in ipairs(Targeting.bodies(p)) do
			local m = b.model
			if not struck[m] then
				PvP.aimAt(to)
				local root = Targeting.rootOf(m)
				if root and (root.Position - to).Magnitude <= D.BlastRadius then
					local out = flatOf(root.Position - to, dir)
					bore(m, UP * D.Launch.Y + out * (D.Launch.X + 20))
				end
			end
		end
		local g = groundBelow(to, 30) or to
		if GroundFX then
			GroundFX.impact(g, 11, 16, 110)
			GroundFX.ring(g, 16, 14, 34)
			for i = 1, 5 do
				local a = (i / 5) * math.pi * 2 + math.random() * 0.5
				GroundFX.impact(g + Vector3.new(math.cos(a), 0, math.sin(a)) * (13 + math.random() * 4), 3.4, 2, 60)
			end
		end
		worldHooks(p, to, D.BlastRadius)
		s.busy = math.min(s.busy, os.clock() + 0.6)
	end)
end

---------------------------------------------------------------------------------------------------
-- spawning, fighter switches, requests
local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	s.m1.gen += 1
	s.m1.combo, s.m1.last, s.m1.lockUntil = 0, -1e9, 0
	endFocus(p, s)
	if p:GetAttribute("Kit") == CFG.KitId then
		char:SetAttribute("OwnM1", true)
	end
end

local function onKitChanged(p)
	local s = getState(p)
	local char = p.Character
	if p:GetAttribute("Kit") == CFG.KitId then
		if char then
			char:SetAttribute("OwnM1", true)
		end
		return
	end
	-- switched away: drop everything this kit was doing
	s.token += 1
	s.busy = 0
	s.m1.gen += 1
	endFocus(p, s)
	if char and char:GetAttribute("OwnM1") and not OWN_M1_KITS[p:GetAttribute("Kit")] then
		char:SetAttribute("OwnM1", nil)
	end
end

local function onPlayer(p)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		onKitChanged(p)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

local CASTS = { Slash = castSlash, Flash = castFlash, Chain = castChain, Focus = castFocus, Dragon = castDragon }
Request.OnServerEvent:Connect(function(p, action, payload)
	local s = getState(p)
	if typeof(action) ~= "string" or not rateOk(s) or p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local cast = CASTS[action]
	if cast then
		cast(p, s, type(payload) == "table" and payload or {})
	end
end)

-- every frame: the hit batch and Focus running out; four times a second: OwnM1 (other kits clear it on a switch)
local watchAt = 0
RunService.Heartbeat:Connect(function()
	if #hitBatch > 0 then
		local list = hitBatch
		hitBatch = {}
		Broadcast:FireAllClients("Hits", list)
	end
	local t = now()
	for p, s in pairs(state) do
		local f = s.focus
		if f and (p.Character ~= f.char or t >= f.untilT) then
			endFocus(p, s)
		end
	end
	local clock = os.clock()
	if clock >= watchAt then
		watchAt = clock + 0.25
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and p:GetAttribute("Kit") == CFG.KitId and char:GetAttribute("OwnM1") ~= true then
				char:SetAttribute("OwnM1", true)
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- PERKS: the "Instant Ult" product (ServerStorage.PerkHooks.UltReset) makes the dragon dash ready at once
task.spawn(function()
	local hooks = ServerStorage:WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("UltReset", 10)
	if not ev then
		warn("[StormdrawService] PerkHooks.UltReset not found")
		return
	end
	ev.Event:Connect(function(p)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
			return
		end
		local s = getState(p)
		s.cd.Dragon, s.cdDur.Dragon = 0, 0
		sendCooldown(p, s, "Dragon")
	end)
end)

print("[StormdrawService] online")
