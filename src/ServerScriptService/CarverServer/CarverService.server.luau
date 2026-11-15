--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- CarverService: server side of the Carver kit. Owns cooldowns, hit detection, damage and every ragdoll impulse;
-- clients only render (they send "Request" and play back "Broadcast"). Nothing in here depends on the skill names.
--   Cleave : three raycast cutting lines fired along the cursor, each launching what it cuts
--   Fuga   : a charged arrow, a physical projectile (AssemblyLinearVelocity) that bursts into a 25-stud thermal blast
--   Sever  : a 1.5 s wind-up, then a thick cut that ignores blocks, force fields and invincibility
--   Shrine : a zone: targets locked, cut by lines and jolted every 0.1 s, then thrown down by a final burst
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("CarverKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local LockRemote = Remotes:WaitForChild("Lock")

-- shared pieces from the rest of the game: ragdolls for NPC bodies, self-healing craters, NPC flee, breakables
local RagdollService, GroundFX, Threat, WorldBlast
do
	local gs = ServerScriptService:FindFirstChild("GojoServer")
	local mod = gs and gs:FindFirstChild("RagdollService")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and res then
			RagdollService = res
			RagdollService.Init()
		end
	end
	Threat = gs and gs:FindFirstChild("Threat")
	WorldBlast = gs and gs:FindFirstChild("WorldBlast")
	local vs = ServerScriptService:FindFirstChild("VulpineServer")
	local gfx = vs and vs:FindFirstChild("GroundFX")
	if gfx then
		local ok, res = pcall(require, gfx)
		GroundFX = ok and res or nil
	end
end

local FXFolder = workspace:FindFirstChild("KitFX") or Instance.new("Folder")
FXFolder.Name = "KitFX"
FXFolder.Parent = workspace

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

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

local function segDist(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = len2 > 1e-6 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
	return (p - (a + ab * t)).Magnitude, a + ab * t
end

-- (aim, flat): the direction from `origin` to the client's cursor point (pitch clamped to +-45 degrees), and its
-- horizontal part. Falls back to where the character faces.
local function aimFrom(origin, payload, hrp)
	local look = flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local target = validPoint(type(payload) == "table" and payload.target or nil)
	if target and (target - origin).Magnitude > 4 then
		local d = (target - origin).Unit
		local flat = flatOf(d, look)
		local pitch = math.clamp(math.asin(math.clamp(d.Y, -1, 1)), math.rad(-45), math.rad(45))
		return (flat * math.cos(pitch) + UP * math.sin(pitch)).Unit, flat
	end
	return look, look
end

---------------------------------------------------------------------------------------------------
-- player state
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busy = 0, reqs = {}, token = 0 }
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	while #s.reqs > 0 and t - s.reqs[1] > 1 do
		table.remove(s.reqs, 1)
	end
	if #s.reqs >= 15 then
		return false
	end
	table.insert(s.reqs, t)
	return true
end

local function fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

local function sendCooldown(p, s, skill)
	Broadcast:FireClient(p, "Cooldown", { skill = skill, ends = s.cd[skill] or 0 })
end

-- (2026-11-07 perks) every cooldown scales with the player's perks: CooldownMul on every move, UltChargeMul on top for
-- the ultimate (the domain). CarverClient's bar applies the same factors.
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function cdDur(p, base, isUlt)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return base * m * (isUlt and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

---------------------------------------------------------------------------------------------------
-- targets, damage and impulses
local function rootOf(model)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the attack (PvP.formRoot)
	return PvPBal.formRoot(model) or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

-- every ragdollable body except the caster: tagged NPCs plus (optionally) other living players
local function enemies(caster)
	PvPBal.setAim(caster) -- (2026-11-08) forms are hit at their body point nearest this attacker
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		if m.Parent and rootOf(m) then
			table.insert(list, m)
		end
	end
	if CFG.AffectPlayers then
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= caster and liveChar(pl) then
				table.insert(list, pl.Character)
			end
		end
	end
	return list
end

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel` (constraint rigs are one
-- assembly per limb); `keep` = how much of the current velocity survives (1 = the impulse is simply added)
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

-- hit feedback: damage dealt this frame is batched and broadcast once; clients pop numbers and confirm the hit
local hitBatch = {}
local function recordHit(attacker, model, amount, big)
	local r = rootOf(model)
	if r and amount and amount >= 0.5 and #hitBatch < 60 then
		table.insert(hitBatch, { u = attacker.UserId, p = r.Position, d = amount, big = big or amount >= 35 })
	end
end
RunService.Heartbeat:Connect(function()
	if #hitBatch > 0 then
		local list = hitBatch
		hitBatch = {}
		Broadcast:FireAllClients("Hits", list)
	end
end)

-- (2026-11-11) Sukuna's per-kit damage (PvPShared.Balance.KIT_DAMAGE_MUL.Carver), applied after the PvP caps
local function carverMul()
	local m = type(BAL.KIT_DAMAGE_MUL) == "table" and tonumber(BAL.KIT_DAMAGE_MUL.Carver) or 1
	return m or 1
end

-- ordinary damage (force fields still absorb it)
local function damage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		-- (2026-11-11, "reduce Sukuna's damage a little") PvPShared.Balance.KIT_DAMAGE_MUL.Carver, after the PvP caps
		hum:TakeDamage(PvPBal.dmg(hum, amount) * carverMul())
		recordHit(attacker, model, amount)
	end
end

-- true damage: written straight to Health, so force fields, blocks and invincibility frames never see it
local function trueDamage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		PvPBal.trueHit(hum, amount) -- (2026-11-14) the sandbox's injuries see true damage too (Sandbox.Powers)
		hum.Health = math.max(hum.Health - amount * carverMul(), 0)
		recordHit(attacker, model, amount, true)
	end
end

-- damage + ragdoll + impulse on one body. Players are tumbled by their own client (it owns their physics).
local function knock(attacker, model, vel, ragTime, amount, keep)
	if vel.Magnitude > 320 then
		vel = vel.Unit * 320
	end
	damage(attacker, model, amount)
	if PvPBal.absorbed and PvPBal.absorbed(model) then
		return -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble, no fling
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		if model:GetAttribute("Morphed") then
			vel *= 0.15 -- giants barely budge
		end
		local rag = math.min(ragTime or 2, CFG.PlayerRagdollMax)
		PvPBal.markDown(model, rag) -- (2026-11-08) the server's clock for "lying on the ground" (M1 strings skip it)
		Knockback:FireClient(victim, vel * PvPBal.knockMul(), rag, keep or 0)
		return
	end
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

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get pushed too (sign = -1 pulls inward)
local function pushLoose(pos, radius, speed, upBias, sign)
	local ignore = { FXFolder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
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
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) * (sign or 1) + UP * upBias).Unit
			pcall(function()
				root:ApplyImpulse(dir * speed * 0.6 * k * root.AssemblyMass)
			end)
		end
	end
end

local function worldHooks(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId)
	end
	if Threat then
		Threat:Fire(pos, radius * 2, 2)
	end
end

-- everything within `radius` is thrown straight out from `pos` (outward along the ground, tipped up by upBias), harder
-- the closer it was
-- (2026-11-10, "when you use Fuga on someone they get permanently ragdolled") the throw used to follow the full 3D
-- offset from `pos` to the body's root. A fuga bursts ON the body that set it off - at the point of the arrow's line
-- nearest that root (flyFuga), often under half a stud from it, and above it whenever the arrow comes down at the body
-- (from a roof, a deck, a jump) - so its own victim, the one thrown hardest (k ~ 1: ~250 studs/s, the strongest throw
-- in the kit), was thrown along randomUnit() (any way at all, straight down included) or down into the floor under it.
-- Rammed into a floor at that speed a body ends up wedged in it or under it, with no room for any get-up to stand it
-- (RagdollService's, or the tumble's on a player's own client), and FallGuard only rescues bodies buried in TERRAIN,
-- not inside building floors, decks or slabs. Now the push is the FLAT radial - falling back to the caster->body
-- direction, then a random flat one, when the body is right at the centre - plus UP * upBias, so a blast never throws
-- anything into the ground. Speeds, damage and ragdoll times are unchanged.
local function radialBlast(p, pos, radius, speed, upBias, amount, ragTime, minK)
	minK = minK or 0.35
	local _, _, casterRoot = liveChar(p)
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(pos) -- (2026-11-10) a form answers at its body point nearest the blast, not the caster
		local rp = rootOf(m).Position
		local off = rp - pos
		local d = off.Magnitude
		if d <= radius then
			local k = 1 - d / radius
			local flatOff = off * FLAT
			local radial = (flatOff.Magnitude > 0.5 and flatOff.Unit)
				or (casterRoot and flatOf(rp - casterRoot.Position, nil))
				or flatOf(randomUnit(), Vector3.xAxis)
			local dir = (radial + UP * upBias).Unit
			knock(p, m, dir * speed * (minK + (1 - minK) * k), ragTime, amount * (0.4 + 0.6 * k))
		end
	end
	pushLoose(pos, radius, speed, upBias, 1)
	worldHooks(p, pos, radius * 0.6)
end

-- common gate: alive, not mid-move, off cooldown
local function gate(p, s, skill)
	local char, hum, hrp = liveChar(p)
	if not char or os.clock() < s.busy then
		return nil
	end
	if PvPBal.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		return nil
	end
	local t = now()
	if t < (s.cd[skill] or 0) then
		sendCooldown(p, s, skill)
		return nil
	end
	return char, hum, hrp, t
end

-- a brief invisible force field: a wind-up can't be interrupted by ordinary damage
local function ffOn(char, duration)
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

-- parts a cast should not stop on: bodies (handled by distance tests), effects, flying debris
local castRay = RaycastParams.new()
castRay.FilterType = Enum.RaycastFilterType.Exclude
local function worldFilter()
	local ignore = { FXFolder }
	if GroundFX and GroundFX.folder then
		table.insert(ignore, GroundFX.folder)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	return ignore
end

local function groundBelow(pos)
	castRay.FilterDescendantsInstances = worldFilter()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -60, 0), castRay)
	return hit and hit.Position or nil
end

---------------------------------------------------------------------------------------------------
-- Skill 1: three rapid cutting lines. Each is a raycast along the aim: the world stops it, bodies along it are cut,
-- damaged and launched. Clients draw the crescents and the slash lines on the torsos.
-- (2026-11-08) Dismantle used to fire all three lines along the aim taken BEFORE the wind-up (two of them fanned
-- +-7 degrees, which misses anything past ~30 studs) and only counted a body whose ROOT was within Thickness of the
-- line, so a target that walked, or that the first cut shoved, slipped out of the later cuts, and a cursor on the
-- ground just short of a body cut the street instead. Now the cast locks onto the body the cursor is on (or the one
-- nearest the aim line) and every line re-aims at where that body is when it fires; hits are measured to the
-- body's nearest part. With nothing locked the lines fan along the aim as before.
local function aimPointOf(model)
	local fp = PvPBal.formPoint(model, PvPBal.aimFrom) -- (2026-11-08) a giant form: its nearest body point
	if fp then
		return fp
	end
	local part = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or rootOf(model)
	return part and part:IsA("BasePart") and part.Position or nil
end

local function aliveBody(model)
	local hum = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- distance from a body to the segment a-b, measured to its nearest part (less a little of that part's bulk)
local function bodySegDist(model, a, b)
	-- (2026-11-08) a giant form: the point of its whole body nearest the line
	local fc = PvPBal.formCenter(model)
	if fc then
		local ab = b - a
		local len2 = ab:Dot(ab)
		local near = len2 > 1e-6 and (a + ab * math.clamp((fc - a):Dot(ab) / len2, 0, 1)) or a
		return segDist(PvPBal.formPoint(model, near), a, b)
	end
	local best = math.huge
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local d = segDist(part.Position, a, b)
			d -= math.min(part.Size.Magnitude * 0.25, 4)
			if d < best then
				best = d
			end
		end
	end
	if best == math.huge then
		local r = rootOf(model)
		if r then
			best = segDist(r.Position, a, b)
		end
	end
	return best
end

-- the body this cast is aimed at: the one the cursor is on / nearest to it, else the one nearest the aim line
local function lockCleave(p, origin, aim, cursor)
	local C = CFG.Cleave
	local best, bestScore
	for _, m in ipairs(enemies(p)) do
		local pt = aliveBody(m) and aimPointOf(m)
		if pt then
			local off = pt - origin
			local along = off:Dot(aim)
			if along > 0 and off.Magnitude <= C.Range + C.LockSlack then
				local score = (off - aim * along).Magnitude
				if cursor then
					score = math.min(score, (pt - cursor).Magnitude)
				end
				local allowed = math.max(C.LockRadius, along * math.tan(math.rad(C.LockAngle)))
				if score <= allowed and (not bestScore or score < bestScore) then
					best, bestScore = m, score
				end
			end
		end
	end
	return best
end

local function castCleaveLine(p, char, hrp, id, i, dir0, lock)
	local C = CFG.Cleave
	local origin = hrp.Position + UP * 1.6 + dir0 * 1.5
	local dir, range = nil, C.Range
	local lp = lock and aliveBody(lock) and aimPointOf(lock)
	local toLock = lp and (lp - origin)
	if toLock and toLock.Magnitude > 1 and toLock.Magnitude <= C.Range + C.LockSlack then
		dir = toLock.Unit -- re-aimed at the locked body where it is now
		range = math.max(C.Range, toLock.Magnitude + 6)
	else
		dir = CFrame.fromAxisAngle(UP, math.rad(C.Fan[i] or 0)):VectorToWorldSpace(dir0)
	end
	castRay.FilterDescendantsInstances = worldFilter()
	local hit = workspace:Raycast(origin, dir * range, castRay)
	local length = hit and (hit.Position - origin).Magnitude or range
	local finish = origin + dir * length
	local last = i == C.Lines
	local targets = {}
	for _, m in ipairs(enemies(p)) do
		if bodySegDist(m, origin, finish) <= C.Thickness then
			breakGuard(m, C.GuardBreakTime)
			knock(p, m, (dir * 0.85 + UP * C.UpBias).Unit * C.Impulse * (last and C.FinalMul or C.EarlyMul), C.RagdollTime, C.Damage * (last and C.FinalMul or 1))
			table.insert(targets, m)
		end
	end
	for dist = 8, length, 16 do
		worldHooks(p, origin + dir * dist, 7) -- the cut breaks props along its length
	end
	if hit and GroundFX and hit.Normal.Y > 0.5 then
		GroundFX.impact(hit.Position, 2.2, 1, 40)
	end
	fire("CleaveLine", { id = id, userId = p.UserId, i = i, origin = origin, dir = dir, length = length, tilt = C.Tilts[i] or 0, targets = targets, blocked = hit ~= nil })
end

local function castCleave(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Cleave")
	if not char then
		return
	end
	local C = CFG.Cleave
	s.cd.Cleave = t + cdDur(p, C.Cooldown)
	sendCooldown(p, s, "Cleave")
	local id = nextId()
	s.busy = os.clock() + C.WindUp + (C.Lines - 1) * C.LineInterval + 0.25
	local aimOrigin = hrp.Position + UP * 1.6
	local dir0 = aimFrom(aimOrigin, payload, hrp)
	local lock = lockCleave(p, aimOrigin, dir0, validPoint(type(payload) == "table" and payload.target or nil))
	if lock then
		local toLock = aimPointOf(lock) - aimOrigin
		if toLock.Magnitude > 1 then
			dir0 = toLock.Unit -- the caster turns to face the body being cut
		end
	end
	fire("CleaveStart", { id = id, userId = p.UserId, windup = C.WindUp, interval = C.LineInterval, lines = C.Lines, dir = dir0 })
	task.spawn(function()
		task.wait(C.WindUp)
		for i = 1, C.Lines do
			local c2, _, h2 = liveChar(p)
			if c2 ~= char then
				return
			end
			castCleaveLine(p, char, h2, id, i, dir0, lock)
			if i < C.Lines then
				task.wait(C.LineInterval)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: the fire arrow. The caster's client reports the cursor just before the draw finishes; the arrow is then a
-- real part given AssemblyLinearVelocity (gravity cancelled so it flies true). Each frame the segment it covered is
-- swept for surfaces and bodies; where it stops it bursts into a thermal blast that keeps burning for BurnTime.
local function burstFuga(p, id, pos)
	local F = CFG.Fuga
	fire("FugaBlast", { id = id, userId = p.UserId, pos = pos, radius = F.BlastRadius, burn = F.BurnTime })
	radialBlast(p, pos, F.BlastRadius, F.Impulse, F.UpBias, F.BlastDamage, F.RagdollTime, 0.45)
	local g = groundBelow(pos) or pos
	if GroundFX then
		GroundFX.impact(g, 11, 16, 100)
		for i = 1, 5 do
			local a = (i / 5) * math.pi * 2 + math.random() * 0.5
			local at = g + Vector3.new(math.cos(a), 0, math.sin(a)) * (15 + math.random() * 4)
			GroundFX.impact(at, 3.6, 2, 60)
		end
	end
	-- the scorched zone: everything left inside keeps burning
	task.spawn(function()
		local ticks = math.floor(F.BurnTime / F.BurnTick)
		for _ = 1, ticks do
			task.wait(F.BurnTick)
			for _, m in ipairs(enemies(p)) do
				PvPBal.aimAt(pos) -- (2026-11-10) forms: nearest the burn zone
				if (rootOf(m).Position - pos).Magnitude <= F.BlastRadius then
					damage(p, m, F.BurnDamage)
				end
			end
		end
	end)
end

local function flyFuga(p, id, origin, dir)
	local F = CFG.Fuga
	local carrier = Instance.new("Part")
	carrier.Name = "FugaCarrier"
	carrier.Shape = Enum.PartType.Ball
	carrier.Size = Vector3.one * 2
	carrier.Transparency = 1
	carrier.CanCollide, carrier.CanQuery, carrier.CanTouch = false, false, false
	carrier.CFrame = CFrame.lookAt(origin, origin + dir)
	carrier.Parent = FXFolder
	local att = Instance.new("Attachment")
	att.Parent = carrier
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Attachment0 = att
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Force = Vector3.new(0, workspace.Gravity * carrier.AssemblyMass, 0)
	antiGravity.Parent = carrier
	pcall(function()
		carrier:SetNetworkOwner(nil)
	end)
	carrier.AssemblyLinearVelocity = dir * F.ArrowSpeed
	fire("FugaLaunch", { id = id, userId = p.UserId, origin = origin, dir = dir, speed = F.ArrowSpeed })
	local last, travelled, burstAt = origin, 0, nil
	while travelled < F.Range and not burstAt do
		RunService.Heartbeat:Wait()
		if not carrier.Parent then
			break
		end
		local cur = carrier.Position
		local step = cur - last
		if step.Magnitude > 0.01 then
			castRay.FilterDescendantsInstances = worldFilter()
			local hit = workspace:Raycast(last, step * 1.05, castRay)
			if hit then
				burstAt = hit.Position - step.Unit * 1.5
				break
			end
			for _, m in ipairs(enemies(p)) do
				PvPBal.aimSeg(m, last, cur) -- (2026-11-10) forms: nearest the arrow's path
				local d, closest = segDist(rootOf(m).Position, last, cur)
				if d <= F.HitRadius then
					burstAt = closest
					break
				end
			end
			travelled += step.Magnitude
			last = cur
		end
	end
	carrier:Destroy()
	burstFuga(p, id, burstAt or last)
end

local function castFuga(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Fuga")
	if not char then
		return
	end
	local F = CFG.Fuga
	s.cd.Fuga = t + cdDur(p, F.Cooldown) + F.ChargeTime
	sendCooldown(p, s, "Fuga")
	local id = nextId()
	s.busy = os.clock() + F.ChargeTime + 0.4
	s.fugaAim = { id = id, target = validPoint(type(payload) == "table" and payload.target or nil) }
	fire("FugaCharge", { id = id, userId = p.UserId, time = F.ChargeTime })
	task.spawn(function()
		local broke = PvPBal.waitCast(char, F.ChargeTime) -- (2026-11-09) an M1 that lands during the draw cancels the arrow
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or broke then
			fire("FugaCancel", { id = id })
			if broke then
				s.busy = 0
				s.cd.Fuga = now() + PvPBal.CAST_BREAK_COOLDOWN
				sendCooldown(p, s, "Fuga")
			end
			return
		end
		local look = flatOf(h2.CFrame.LookVector, Vector3.new(0, 0, -1))
		local origin = h2.Position + UP * 2.2 + look * 3
		local aim = s.fugaAim and s.fugaAim.id == id and s.fugaAim.target or nil
		s.fugaAim = nil
		local dir = look
		if aim and (aim - origin).Magnitude > 6 then
			dir = (aim - origin).Unit
		end
		flyFuga(p, id, origin, dir)
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the spatial cut. After the wind-up a thick cut runs along the aim (it ignores walls: space itself is
-- cut). Everything inside its width takes TRUE damage -- written straight to Health, so blocks, force fields and
-- invincibility never apply -- and is thrown into a ragdoll. A fissure is torn into the ground along its path.
local function castSever(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Sever")
	if not char then
		return
	end
	local W = CFG.Sever
	s.cd.Sever = t + cdDur(p, W.Cooldown) + W.WindUp
	sendCooldown(p, s, "Sever")
	local id = nextId()
	s.busy = os.clock() + W.WindUp + 0.9
	local _, flat0 = aimFrom(hrp.Position, payload, hrp)
	s.severAim = { id = id, dir = flat0 }
	-- (2026-11-09) no force field through the wind-up any more: it made the caster unhittable, and an M1 must be able to
	-- land to cancel the cut (it was: ffOn(char, W.WindUp + 0.5))
	fire("SeverStart", { id = id, userId = p.UserId, time = W.WindUp, dir = flat0 })
	task.spawn(function()
		local broke = PvPBal.waitCast(char, W.WindUp) -- (2026-11-09) an M1 that lands during the wind-up cancels the cut
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or broke then
			fire("SeverCancel", { id = id })
			if broke then
				s.busy = 0
				s.cd.Sever = now() + PvPBal.CAST_BREAK_COOLDOWN
				sendCooldown(p, s, "Sever")
			end
			return
		end
		local dir = s.severAim and s.severAim.id == id and s.severAim.dir or flat0
		s.severAim = nil
		local origin = h2.Position
		local across = dir:Cross(UP)
		local severed = {}
		for _, m in ipairs(enemies(p)) do
			local off = rootOf(m).Position - origin
			local along = off:Dot(dir)
			local lateral = ((off - dir * along) * FLAT).Magnitude
			if along >= -3 and along <= W.Range and lateral <= W.Width / 2 then
				trueDamage(p, m, W.Damage)
				breakGuard(m, 3)
				local sideSign = off:Dot(across) >= 0 and 1 or -1
				knock(p, m, (dir * 0.55 + across * sideSign * 0.45 + UP * W.UpBias).Unit * W.Impulse, W.RagdollTime, 0)
				table.insert(severed, m)
			end
		end
		fire("SeverCut", { id = id, userId = p.UserId, origin = origin, dir = dir, range = W.Range, width = W.Width, height = W.Height, speed = W.Speed, severed = severed })
		-- the ground splits one crater after another as the cut races past
		task.spawn(function()
			for dist = 8, W.Range, W.FissureStep do
				local at = origin + dir * dist
				local g = groundBelow(at)
				if g and GroundFX and (g - at).Magnitude < 30 then
					GroundFX.impact(g, 3.8, 2, 60)
				end
				worldHooks(p, at, W.Width * 0.6)
				task.wait(W.FissureStep / W.Speed)
			end
		end)
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the zone. A two-handed seal, then the boundary opens around the user and follows them. Everything inside
-- when it opens (or that walks in while it is open) is caught and held there until it ends. Every Tick (0.1 s) each
-- caught body takes a minor damage tick and a micro-impulse; when the time is up a final burst throws everyone inside
-- (and every caught body) to the ground in a ragdoll.
local function castShrine(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Shrine")
	if not char then
		return
	end
	local D = CFG.Shrine
	local id = nextId()
	s.token += 1
	local tok = s.token
	s.busy = os.clock() + D.SealTime + D.Duration + 1.5
	s.domain = { id = id, char = char }
	ffOn(char, D.SealTime + 0.3)
	local center = hrp.Position
	fire("ShrineStart", { id = id, userId = p.UserId, pos = center, seal = D.SealTime, duration = D.Duration, radius = D.Radius })
	local function alive()
		return s.token == tok and s.domain ~= nil and liveChar(p) == char
	end
	local function finish(cancelled)
		if s.domain and s.domain.id == id then
			s.domain = nil
		end
		if char.Parent then
			char:SetAttribute("Domain", false)
		end
		-- (perks) an Instant Ult bought while the zone was up leaves it ready the moment it ends
		s.cd.Shrine = s.ultReset and 0 or now() + cdDur(p, D.Cooldown, true)
		s.ultReset = nil
		sendCooldown(p, s, "Shrine")
		s.busy = 0
		if cancelled then
			fire("ShrineEnd", { id = id, userId = p.UserId, pos = center, radius = D.Radius, cancelled = true })
		end
	end
	task.spawn(function()
		task.wait(D.SealTime)
		if not alive() then
			finish(true)
			return
		end
		local _, _, h2 = liveChar(p)
		center = h2.Position
		char:SetAttribute("DomainUntil", now() + D.Duration)
		char:SetAttribute("Domain", true)
		fire("ShrineOpen", { id = id, userId = p.UserId, radius = D.Radius, duration = D.Duration })
		-- (2026-11-10, "Fix Sukuna's ult, people can just walk out") a caught body used to be held for only LockTime
		-- (1.5 s) of the zone's 5 s and then simply walked out, and the ticks and the final burst only ever touched bodies
		-- still inside the radius - so the ult did almost nothing to anyone who moved. Now a body the zone catches (inside
		-- when it opens, or walking in while it is open) is TRAPPED until the zone ends: stunned the whole time (PvP.stun,
		-- re-stamped in HOLD-second steps so it lapses at once when let go - PvPStunClient takes a player's walking and
		-- jumping, every kit's server gate refuses their moves, Dash refuses; an NPC's brain stands still), its own client
		-- keeps it rooted (LockRemote with the time left), every tick cuts it through the PvP damage path wherever it is (the
		-- zone follows its caster), and the final burst throws it too. Every caught body is let go the moment the zone ends:
		-- normally, or early when the caster dies, leaves, respawns or switches kit (alive() fails), or the loop errors.
		local HOLD = 0.5
		local locked = {} -- [model] = { victim = Player?, stamp = the StunnedUntil we last wrote, hum, ws, jp }
		local t0 = os.clock()
		local function hold(m, rec)
			-- re-stamped only when it runs low (an attribute write replicates; this runs every tick)
			if (tonumber(m:GetAttribute("StunnedUntil")) or 0) - now() < HOLD * 0.5 then
				PvPBal.stun(m, HOLD)
				rec.stamp = m:GetAttribute("StunnedUntil")
			end
		end
		-- catch one body: players through their own client, NPCs through their humanoid (and the stun flag the brain reads)
		local function lockBody(m)
			if locked[m] then
				return
			end
			-- the forms every other hold treats as immune (PvPStunClient.immune, CombatService.holdImmune) are not rooted;
			-- they still take the final burst, which runs over enemies(p) on its own
			if m:GetAttribute("SuperArmor") or m:GetAttribute("Guardian") or m:GetAttribute("AscForm") == "Instinct" then
				return
			end
			local rec = { victim = Players:GetPlayerFromCharacter(m) }
			locked[m] = rec
			if rec.victim then
				local left = math.max(D.Duration - (os.clock() - t0), D.Tick)
				LockRemote:FireClient(rec.victim, left, D.TickImpulse, left, id)
			else
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum then
					-- a speed already at 0 belongs to another hold (the brain puts its own speed back once the stun ends)
					rec.hum = hum
					rec.ws = hum.WalkSpeed > 0 and hum.WalkSpeed or nil
					rec.jp = hum.JumpPower > 0 and hum.JumpPower or nil
					hum.WalkSpeed, hum.JumpPower = 0, 0
				end
			end
			hold(m, rec)
		end
		local function releaseAll()
			for m, rec in pairs(locked) do
				locked[m] = nil
				if m.Parent then
					-- our stun ends now, unless something else has stunned the body for longer since
					if rec.stamp and m:GetAttribute("StunnedUntil") == rec.stamp then
						m:SetAttribute("StunnedUntil", now())
					end
					local hum = rec.hum
					if hum and hum.Parent then
						if rec.ws and hum.WalkSpeed == 0 then
							hum.WalkSpeed = rec.ws
						end
						if rec.jp and hum.JumpPower == 0 then
							hum.JumpPower = rec.jp
						end
					end
				end
				if rec.victim and rec.victim.Parent then
					LockRemote:FireClient(rec.victim, "release", 0, 0, id)
				end
			end
		end
		local function openZone()
			while os.clock() - t0 < D.Duration and alive() do
				local _, _, h3 = liveChar(p)
				center = h3.Position
				-- anything alive inside the boundary is caught (once)
				for _, m in ipairs(enemies(p)) do
					local r = rootOf(m)
					if r and aliveBody(m) and (r.Position - center).Magnitude <= D.Radius then
						lockBody(m)
					end
				end
				-- every caught body stays held and is cut each tick, wherever it is now
				for m, rec in pairs(locked) do
					if aliveBody(m) then
						hold(m, rec)
						damage(p, m, D.TickDamage)
						if not rec.victim then
							-- a micro-impulse every tick: the locked body shudders under the cuts
							impulseModel(m, randomUnit() * D.TickImpulse + UP * 2, nil, 1)
						end
					end
				end
				task.wait(D.Tick)
			end
			if not alive() then
				releaseAll()
				finish(true)
				return
			end
			-- the final burst: everyone inside is thrown down
			fire("ShrineEnd", { id = id, userId = p.UserId, pos = center, radius = D.Radius })
			radialBlast(p, center, D.Radius, D.FinalImpulse, D.FinalUpBias, D.FinalDamage, D.FinalRagdoll, 0.7)
			-- ...and so is a caught body the moving zone left beyond its boundary (thrown as if it stood on the rim)
			for m in pairs(locked) do
				local r = aliveBody(m) and rootOf(m)
				if r and (r.Position - center).Magnitude > D.Radius then
					local fo = (r.Position - center) * FLAT
					local dir = ((fo.Magnitude > 0.5 and fo.Unit or flatOf(randomUnit(), Vector3.xAxis)) + UP * D.FinalUpBias).Unit
					knock(p, m, dir * D.FinalImpulse * 0.7, D.FinalRagdoll, D.FinalDamage * 0.4)
				end
			end
			releaseAll()
			local g = groundBelow(center) or center
			if GroundFX then
				GroundFX.ring(center, 14, 16, 26)
				GroundFX.impact(g, 10, 14, 90)
			end
			finish(false)
		end
		local ok, err = pcall(openZone)
		if not ok then
			-- never leave anyone trapped (or the caster's zone stuck open) because something in the loop threw
			warn("[CarverService] Shrine: " .. tostring(err))
			pcall(releaseAll)
			if s.domain and s.domain.id == id then
				pcall(finish, true)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- spawning, requests
local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	s.domain = nil
end

local function onPlayer(p)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	-- switching away from this kit drops an open zone
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		local s = state[p]
		if s and p:GetAttribute("Kit") ~= CFG.KitId then
			s.token += 1
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

Request.OnServerEvent:Connect(function(p, action, payload)
	local s = getState(p)
	if type(payload) ~= "table" then
		payload = {}
	end
	-- cursor updates for a charge in progress only move a point, so they skip the request limiter
	if action == "FugaAim" then
		if s.fugaAim and payload.id == s.fugaAim.id then
			s.fugaAim.target = validPoint(payload.target) or s.fugaAim.target
		end
		return
	end
	if action == "SeverAim" then
		if s.severAim and payload.id == s.severAim.id then
			local t = validPoint(payload.target)
			local _, _, hrp = liveChar(p)
			if t and hrp then
				s.severAim.dir = flatOf(t - hrp.Position, s.severAim.dir)
			end
		end
		return
	end
	if typeof(action) ~= "string" or not rateOk(s) then
		return
	end
	if p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	if action == "Cleave" then
		castCleave(p, s, payload)
	elseif action == "Fuga" then
		castFuga(p, s, payload)
	elseif action == "Sever" then
		castSever(p, s, payload)
	elseif action == "Shrine" then
		castShrine(p, s, payload)
	end
end)

---------------------------------------------------------------------------------------------------
-- (2026-11-07 perks) Instant Ult: ServerStorage.PerkHooks.UltReset(player) clears the domain's cooldown for a player on
-- this kit and pushes it to their bar. Bought while the zone is up, the cooldown its end would start is skipped.
local function ultReset(p)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local s = getState(p)
	s.cd.Shrine = 0
	s.ultReset = s.domain ~= nil or nil
	sendCooldown(p, s, "Shrine")
end
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("UltReset", 10)
	if ev then
		ev.Event:Connect(function(p)
			local ok, err = pcall(ultReset, p)
			if not ok then
				warn("[CarverService] UltReset: " .. tostring(err))
			end
		end)
	else
		warn("[CarverService] PerkHooks.UltReset not found")
	end
end)

print("[CarverService] online")
