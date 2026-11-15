--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- AscendantService: server side of the Ascendant kit. Owns cooldowns, hit detection, damage, every ragdoll impulse and
-- the forms' rules; clients render the broadcasts and drive their own bodies (flight constraints, poses, camera).
-- Nothing in here depends on the skill names (those are display labels in the Config):
--   Flight   : passive. The client flies itself (LinearVelocity + VectorForce); the server only marks the body "Flying".
--   Beam     : a charge, then a continuous raycast beam: multi-tick damage, a push along it, a closing burst
--   Warp     : a jump along the cursor ray to just behind the enemy it passes, then an automatic guard-breaking kick
--   Surge    : the golden form: speed, jump, damage, stagger resistance, M1 shockwaves
--   Instinct : the silver form after a cutscene: auto-evasion, true-damage M1 with double launches, a blink flurry
--   Strike   : the kit's own M1 combo (the character carries OwnM1 so the shared punch stays out of it)
-- Character attributes written here: Flying, AscForm ("Surge" / "Instinct" / nil), AscFormUntil, AscWalkMul,
-- AscJumpMul, AscFlightMul, StaggerResist, OwnM1. Player attribute: KitLocked (only while this kit is equipped).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("AscendantKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")

-- shared pieces from the rest of the game: NPC ragdolls, self-healing craters, NPC flee, breakables, the dodge hook
local RagdollService, GroundFX, Threat, WorldBlast, Evasion
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
	local ts = ServerScriptService:FindFirstChild("TempestServer")
	local ev = ts and ts:FindFirstChild("Evasion")
	if ev then
		local ok, res = pcall(require, ev)
		Evasion = ok and res or nil
	end
end

local FXFolder = workspace:FindFirstChild("KitFX") or Instance.new("Folder")
FXFolder.Name = "KitFX"
FXFolder.Parent = workspace

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local FWD = Vector3.new(0, 0, -1)

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

-- the direction from `origin` to the cursor point, pitch clamped to +-maxPitch degrees (else where the body faces)
local function aimDir(origin, target, hrp, maxPitch)
	local look = flatOf(hrp.CFrame.LookVector, FWD)
	if target and (target - origin).Magnitude > 4 then
		local d = (target - origin).Unit
		local fl = flatOf(d, look)
		local lim = math.rad(maxPitch)
		local pitch = math.clamp(math.asin(math.clamp(d.Y, -1, 1)), -lim, lim)
		return (fl * math.cos(pitch) + UP * math.sin(pitch)).Unit
	end
	return look
end

---------------------------------------------------------------------------------------------------
-- player state
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busy = 0, reqs = {}, token = 0, combo = 0, lastSwing = 0, strikeLock = 0, lastDodge = 0 }
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	while #s.reqs > 0 and t - s.reqs[1] > 1 do
		table.remove(s.reqs, 1)
	end
	if #s.reqs >= 16 then
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

-- PERKS (2026-11-07, kits-D). Faster Cooldowns / Faster Ult Charge: every cooldown this kit starts is base x the
-- player's CooldownMul, and the ultimate's x UltChargeMul as well (both attributes are written by ShopService only).
-- The silver form is the ultimate (the wide G button); the blink flurry exists only inside it, so it counts too.
-- (The M1 combo's end lag is not an ability cooldown and is left alone, like the shared punch.)
local ULT_SKILLS = { Instinct = true, Flurry = true }
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function cdFor(p, skill, base)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if ULT_SKILLS[skill] then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return base * math.clamp(m, 0.05, 4) * (ULT_SKILLS[skill] and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end

local castId = 0
local function nextId()
	castId += 1
	return castId
end

-- the form a body is in right now ("Surge" / "Instinct" / nil)
local function formOf(s, char)
	local f = s and s.form
	if f and f.char == char and char.Parent and now() < f.untilT then
		return f.kind
	end
	return nil
end

local function instinctOn(s, char)
	return formOf(s, char) == "Instinct"
end

-- outgoing damage, scaled by the golden form
local function dmg(s, char, amount)
	if formOf(s, char) == "Surge" then
		return amount * CFG.Surge.DamageMul
	end
	return amount
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

-- one ApplyImpulse per assembly so every body part ends up moving at roughly `vel` (constraint rigs are one assembly
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

-- hit feedback: damage dealt this frame is batched and broadcast once; clients pop numbers and confirm the hit
local hitBatch = {}
local function recordHit(attacker, model, amount, big)
	local r = rootOf(model)
	if r and amount and amount >= 0.5 and #hitBatch < 60 then
		table.insert(hitBatch, { u = attacker.UserId, p = r.Position, d = amount, big = big or amount >= 35 })
	end
end

local dodge -- (p, s, threatModel, threatPos, threatVel) -> true if the blink happened / still covers; defined below

-- a silver-form player evades whatever is about to hit them: the hit is dropped and they blink behind the attacker
local function evades(attacker, model)
	local pl = Players:GetPlayerFromCharacter(model)
	local s = pl and state[pl]
	if s and instinctOn(s, model) then
		dodge(pl, s, attacker and attacker.Character or nil)
		return true
	end
	return false
end

local function rawDamage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, amount))
		recordHit(attacker, model, amount)
	end
end

-- true damage: written straight to Health, so force fields, blocks and invincibility frames never see it
local function rawTrueDamage(attacker, model, amount)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if amount and amount > 0 and hum and hum.Health > 0 then
		model:SetAttribute("LastHitBy", attacker.UserId)
		PvPBal.trueHit(hum, amount) -- (2026-11-14) the sandbox's injuries see true damage too (Sandbox.Powers)
		hum.Health = math.max(hum.Health - amount, 0)
		recordHit(attacker, model, amount, true)
	end
end

local function damage(attacker, model, amount)
	if not evades(attacker, model) then
		rawDamage(attacker, model, amount)
	end
end

-- damage + ragdoll + impulse on one body. Players are tumbled by their own client (it owns their physics); a body in
-- the golden form shrugs off part of it (StaggerResist). Returns false when the hit was evaded.
local function knock(attacker, model, vel, ragTime, amount, keep, isTrue)
	if evades(attacker, model) then
		return false
	end
	if vel.Magnitude > 320 then
		vel = vel.Unit * 320
	end
	if isTrue then
		rawTrueDamage(attacker, model, amount)
	else
		rawDamage(attacker, model, amount)
	end
	if PvPBal.absorbed and PvPBal.absorbed(model) then
		return false -- (2026-11-11) blocked / dodged (ServerScriptService.PvP, BLOCK): no tumble, no fling
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		local resist = model:GetAttribute("StaggerResist")
		resist = type(resist) == "number" and math.clamp(resist, 0, 0.9) or 0
		if model:GetAttribute("Morphed") then
			vel *= 0.15 -- giants barely budge
		end
		local rag = math.min(ragTime or 2, CFG.PlayerRagdollMax) * (1 - resist)
		PvPBal.markDown(model, rag) -- (2026-11-08) the server's clock for "lying on the ground" (M1 strings skip it)
		Knockback:FireClient(victim, vel * (1 - resist) * PvPBal.knockMul(), rag, keep or 0)
		return true
	end
	if RagdollService and ragTime and ragTime > 0 then
		RagdollService.Ragdoll(model, ragTime)
	end
	impulseModel(model, vel, randomUnit() * 6, keep)
	return true
end

-- breaks a block: clears "Blocking" and stamps "GuardBrokenUntil" for any block system to respect
local function breakGuard(model, duration)
	model:SetAttribute("Blocking", false)
	model:SetAttribute("GuardBrokenUntil", now() + duration)
end

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get pushed too
local function pushLoose(pos, radius, speed, upBias)
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
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) + UP * upBias).Unit
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

-- everything within `radius` is thrown straight out from `pos`, harder the closer it was (`skip` = bodies to leave out)
local function radialBlast(p, pos, radius, speed, upBias, amount, ragTime, minK, skip)
	minK = minK or 0.35
	for _, m in ipairs(enemies(p)) do
		PvPBal.aimAt(pos) -- (2026-11-10) a form answers at its body point nearest the blast, not the caster
		if not (skip and skip[m]) then
			local off = rootOf(m).Position - pos
			local d = off.Magnitude
			if d <= radius then
				local k = 1 - d / radius
				local dir = ((d > 0.5 and off.Unit or randomUnit()) + UP * upBias).Unit
				knock(p, m, dir * speed * (minK + (1 - minK) * k), ragTime, amount * (0.4 + 0.6 * k))
			end
		end
	end
	pushLoose(pos, radius, speed, upBias)
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
local function ffOn(char, duration, name)
	local ff = Instance.new("ForceField")
	ff.Name = name or "CastShield"
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
	for _, n in ipairs({ "Ascendant", "KitDebris" }) do
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
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	return ignore
end

local function groundBelow(pos, depth)
	castRay.FilterDescendantsInstances = worldFilter()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -(depth or 60), 0), castRay)
	return hit and hit.Position or nil
end

-- where a body's root should go to stand at `pos` (snapped onto the ground below unless it is flying)
local function standAt(pos, hum, hrp, flying)
	if flying then
		return pos
	end
	local g = groundBelow(pos + UP * 3, 14)
	if g then
		return Vector3.new(pos.X, g.Y + hum.HipHeight + hrp.Size.Y / 2, pos.Z)
	end
	return pos
end

-- moves a body from `from` toward `dest` but stops short of any wall in between
local function clearPath(from, dest)
	local off = dest - from
	if off.Magnitude < 0.1 then
		return dest
	end
	castRay.FilterDescendantsInstances = worldFilter()
	local wall = workspace:Raycast(from, off, castRay)
	if wall then
		return from + off.Unit * math.max((wall.Position - from).Magnitude - 1.5, 0)
	end
	return dest
end

local function blink(char, dest, face)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	char:PivotTo(CFrame.lookAt(dest, Vector3.new(face.X, dest.Y, face.Z)))
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

---------------------------------------------------------------------------------------------------
-- Passive: flight. The client builds and steers its own LinearVelocity (it owns its physics); this only publishes the
-- state so every client can draw the wind aura and the hover pose.
local function setFlying(p, on)
	local char = liveChar(p)
	if char and char:GetAttribute("Flying") ~= on then
		char:SetAttribute("Flying", on)
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 1: the beam. The charge follows the cursor (the client streams BeamAim); on release the direction is locked
-- and every Tick a raycast finds where the world stops the beam. Bodies within Radius of its axis take a damage tick
-- and are carried along it (ragdolled); when the fire ends, everything it carried is thrown by a final burst and the
-- end of the beam explodes.
local function castBeam(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Beam")
	if not char then
		return
	end
	local B = CFG.Beam
	local form = formOf(s, char)
	local scale = (form and B.FormScale[form]) or 1
	s.cd.Beam = t + cdFor(p, "Beam", B.Cooldown) + B.ChargeTime + B.FireTime
	sendCooldown(p, s, "Beam")
	local id = nextId()
	s.busy = os.clock() + B.ChargeTime + B.FireTime + 0.35
	s.beam = { id = id, target = validPoint(payload.target) }
	fire("BeamCharge", { id = id, userId = p.UserId, time = B.ChargeTime, fire = B.FireTime, scale = scale, form = form })
	task.spawn(function()
		local broke = PvPBal.waitCast(char, B.ChargeTime) -- (2026-11-09) an M1 that lands during the charge cancels the beam
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or not s.beam or s.beam.id ~= id or broke then
			fire("BeamCancel", { id = id, userId = p.UserId })
			if broke then
				if s.beam and s.beam.id == id then
					s.beam = nil
				end
				s.busy = 0
				s.cd.Beam = now() + PvPBal.CAST_BREAK_COOLDOWN
				sendCooldown(p, s, "Beam")
			end
			return
		end
		local flying = char:GetAttribute("Flying") == true
		local chest = h2.Position + UP * 0.6
		local dir = aimDir(chest, s.beam.target, h2, flying and 80 or B.MaxPitch)
		local radius = B.Radius * scale
		fire("BeamFire", { id = id, userId = p.UserId, dir = dir, time = B.FireTime, radius = radius, range = B.Range, headSpeed = B.HeadSpeed, scale = scale, form = form })
		local caught = {}
		local t0 = os.clock()
		local ticks = math.max(1, math.floor(B.FireTime / B.Tick + 0.5))
		local finish, blocked = chest + dir * 3, false
		local trenched = 0
		for k = 1, ticks do
			local c3, _, h3 = liveChar(p)
			if c3 ~= char or not s.beam or s.beam.id ~= id then
				break
			end
			local origin = h3.Position + UP * 0.6 + dir * 3
			local head = math.min(B.Range, B.HeadSpeed * (os.clock() - t0 + B.Tick))
			castRay.FilterDescendantsInstances = worldFilter()
			local hit = workspace:Raycast(origin, dir * head, castRay)
			local len = hit and (hit.Position - origin).Magnitude or head
			blocked = hit ~= nil
			finish = origin + dir * len
			for _, m in ipairs(enemies(p)) do
				PvPBal.aimSeg(m, origin, finish) -- (2026-11-10) forms: nearest the beam
				if segDist(rootOf(m).Position, origin, finish) <= radius + 1.5 then
					if knock(p, m, dir * B.PushSpeed + UP * 4, B.TickRagdoll, dmg(s, char, B.TickDamage), B.PushKeep) then
						caught[m] = true
					end
				end
			end
			-- the beam's end chews into whatever stops it
			if blocked and k % 3 == 1 then
				worldHooks(p, finish, radius * 1.6)
				if GroundFX then
					GroundFX.impact(finish, radius * 0.9, 4, 70)
				end
			end
			-- a trench is torn into the ground under a low beam
			if GroundFX then
				while trenched + 10 <= len do
					trenched += 10
					local at = origin + dir * trenched
					local g = groundBelow(at, 40)
					if g and at.Y - g.Y < radius + 3 then
						GroundFX.impact(g, 2.6, 2, 45)
					end
				end
			end
			fire("BeamTick", { id = id, len = len, blocked = blocked, origin = origin })
			task.wait(B.Tick)
		end
		if liveChar(p) ~= char or not s.beam or s.beam.id ~= id then
			fire("BeamCancel", { id = id, userId = p.UserId })
			if s.beam and s.beam.id == id then
				s.beam = nil
			end
			return
		end
		s.beam = nil
		-- the closing burst: everything the beam carried is thrown on, and the end of the beam detonates
		fire("BeamEnd", { id = id, userId = p.UserId, pos = finish, dir = dir, radius = B.BlastRadius * scale, blocked = blocked })
		for m in pairs(caught) do
			if m.Parent then
				knock(p, m, (dir + UP * B.FinalUpBias).Unit * B.FinalImpulse, B.FinalRagdoll, dmg(s, char, B.FinalDamage))
			end
		end
		radialBlast(p, finish, B.BlastRadius * scale, B.BlastImpulse, 0.5, dmg(s, char, B.BlastDamage), B.FinalRagdoll, 0.4, caught)
		local g = groundBelow(finish, 40)
		if g and GroundFX and (finish - g).Magnitude < B.BlastRadius then
			GroundFX.impact(g, 9 * scale, 14, 110)
			GroundFX.ring(g, 12 * scale, 14, 24)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 2: instant transmission. After the gesture, the cursor ray (MaxDistance) picks the enemy it passes closest
-- to (or the one the client hovered); the body is set Behind studs behind that enemy, facing its back, and a
-- guard-breaking turn kick follows. With no enemy on the ray the jump lands where the ray does.
local function pickWarpTarget(p, from, dirU, hinted)
	local W = CFG.Warp
	local list = enemies(p)
	if typeof(hinted) == "Instance" then
		for _, m in ipairs(list) do
			if m == hinted and (rootOf(m).Position - from).Magnitude <= W.MaxDistance + W.Behind then
				return m
			end
		end
	end
	local best, bestScore
	for _, m in ipairs(list) do
		local off = rootOf(m).Position - from
		local along = off:Dot(dirU)
		if along > 0 and along <= W.MaxDistance + W.Behind then
			local perp = (off - dirU * along).Magnitude
			if perp <= W.TargetRadius then
				local score = perp + along * 0.04
				if not bestScore or score < bestScore then
					best, bestScore = m, score
				end
			end
		end
	end
	return best
end

local function warpKick(p, s, char, target, id)
	local W = CFG.Warp
	local c2, _, h2 = liveChar(p)
	local r = target.Parent and rootOf(target)
	if c2 ~= char or not r or (r.Position - h2.Position).Magnitude > W.Behind + 8 then
		fire("WarpKick", { id = id, userId = p.UserId, miss = true })
		return
	end
	if Players:GetPlayerFromCharacter(target) and Evasion and Evasion.tryEvade(target, char) then
		fire("WarpKick", { id = id, userId = p.UserId, miss = true })
		return
	end
	breakGuard(target, W.GuardBreakTime)
	local fwd = flatOf(r.Position - h2.Position, flatOf(h2.CFrame.LookVector, FWD))
	local side = -fwd:Cross(UP) -- the turn kick sweeps right to left: the target is thrown off to the side
	local dir = (side * 0.85 + fwd * 0.4 + UP * W.KickUpBias).Unit
	local hitPos = r.Position
	if knock(p, target, dir * W.KickImpulse, W.KickRagdoll, dmg(s, char, W.KickDamage)) then
		fire("WarpKick", { id = id, userId = p.UserId, pos = hitPos, dir = dir, target = target })
		pushLoose(hitPos, 10, W.KickImpulse, 0.3)
		worldHooks(p, hitPos, 6)
	else
		fire("WarpKick", { id = id, userId = p.UserId, miss = true })
	end
end

local function castWarp(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Warp")
	if not char then
		return
	end
	local W = CFG.Warp
	s.cd.Warp = t + cdFor(p, "Warp", W.Cooldown)
	sendCooldown(p, s, "Warp")
	local id = nextId()
	s.busy = os.clock() + W.Gesture + W.KickDelay + 0.3
	local cursor = validPoint(payload.target)
	local hinted = payload.model
	fire("WarpStart", { id = id, userId = p.UserId, time = W.Gesture })
	task.delay(W.Gesture, function()
		local c2, hum, h2 = liveChar(p)
		if c2 ~= char then
			return
		end
		local flying = char:GetAttribute("Flying") == true
		local from = h2.Position
		local head = from + UP * 1.5
		local dirU = cursor and (cursor - head).Magnitude > 1 and (cursor - head).Unit or flatOf(h2.CFrame.LookVector, FWD)
		local target = pickWarpTarget(p, head, dirU, hinted)
		local dest, face
		if target then
			local r = rootOf(target)
			local facing = flatOf(r.CFrame.LookVector, flatOf(r.Position - from, FWD))
			dest = clearPath(r.Position, r.Position - facing * W.Behind)
			dest = standAt(dest, hum, h2, flying or r.Position.Y - (groundBelow(r.Position, 30) or r.Position).Y > 8)
			face = r.Position
		else
			castRay.FilterDescendantsInstances = worldFilter()
			local hit = workspace:Raycast(head, dirU * W.MaxDistance, castRay)
			dest = hit and (hit.Position - dirU * 2.5 + hit.Normal * 1.5) or (head + dirU * W.MaxDistance)
			dest = standAt(dest, hum, h2, flying)
			face = dest + flatOf(dirU, FWD) * 10
		end
		blink(char, dest, face)
		fire("WarpGo", { id = id, userId = p.UserId, from = from, to = dest, target = target })
		if target then
			task.delay(W.KickDelay, warpKick, p, s, char, target, id)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- the forms. Their rules live on the character as attributes (every client reads them for the look; the owner's
-- client applies the speed / jump multipliers itself, since it owns its movement).
local function applyForm(char, kind)
	local S = CFG.Surge
	local gold = kind == "Surge"
	char:SetAttribute("AscForm", kind)
	char:SetAttribute("AscWalkMul", gold and S.WalkMul or nil)
	char:SetAttribute("AscJumpMul", gold and S.JumpMul or nil)
	char:SetAttribute("AscFlightMul", gold and S.FlightMul or nil)
	char:SetAttribute("StaggerResist", gold and S.StaggerResist or nil)
end

local function endForm(p, s, reason)
	local f = s.form
	if not f then
		return
	end
	s.form = nil
	if f.shield and f.shield.Parent then
		f.shield:Destroy()
	end
	if f.hconn then
		f.hconn:Disconnect()
	end
	if f.char and f.char.Parent then
		applyForm(f.char, nil)
		f.char:SetAttribute("AscFormUntil", nil)
	end
	if f.kind == "Instinct" and s.ultFree then
		s.ultFree = nil -- (an Instant Ult Charge bought during this silver form: its ending starts no cooldown)
		s.cd[f.kind] = 0
	else
		s.cd[f.kind] = now() + cdFor(p, f.kind, CFG[f.kind].Cooldown)
	end
	sendCooldown(p, s, f.kind)
	fire("FormEnd", { userId = p.UserId, kind = f.kind, reason = reason })
end

local function startForm(p, s, char, kind, duration)
	if s.form then
		endForm(p, s, "replaced")
	end
	local f = { kind = kind, char = char, untilT = now() + duration }
	s.form = f
	applyForm(char, kind)
	char:SetAttribute("AscFormUntil", f.untilT)
	if kind == "Instinct" then
		-- ordinary damage never lands (an invisible force field); anything that still takes health (true damage) is
		-- undone on the spot and turned into a blink behind whoever dealt it
		f.shield = Instance.new("ForceField")
		f.shield.Name = "InstinctShield"
		f.shield.Visible = false
		f.shield.Parent = char
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			local last = hum.Health
			local restoring = false
			f.hconn = hum.HealthChanged:Connect(function(h)
				if restoring or s.form ~= f then
					return
				end
				if h < last - 0.01 then
					restoring = true
					hum.Health = last
					restoring = false
					local uid = char:GetAttribute("LastHitBy")
					local ap = uid and Players:GetPlayerByUserId(uid)
					dodge(p, s, ap and ap.Character or nil)
				else
					last = h
				end
			end)
		end
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the golden form. A power-up burst (shielded), then the form for Duration: the multipliers above, damage
-- x DamageMul, stagger resistance, M1 shockwaves. R again during the form powers down (cooldown from then).
local function castSurge(p, s)
	local cur = liveChar(p)
	if cur and formOf(s, cur) == "Surge" then
		if os.clock() >= s.busy then
			endForm(p, s, "cancel")
		end
		return
	end
	local char, _, hrp, t = gate(p, s, "Surge")
	if not char or formOf(s, char) == "Instinct" then
		return -- the silver form outranks it
	end
	local S = CFG.Surge
	s.cd.Surge = t + S.BurstTime + S.Duration + cdFor(p, "Surge", S.Cooldown) -- replaced by the real cooldown when the form ends
	sendCooldown(p, s, "Surge")
	s.busy = os.clock() + S.BurstTime
	ffOn(char, S.BurstTime + 0.2, "PowerUpShield")
	s.token += 1
	local tok = s.token
	fire("SurgeStart", { userId = p.UserId, pos = hrp.Position, time = S.BurstTime, burstAt = S.BurstAt })
	task.delay(S.BurstAt, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or s.token ~= tok then
			s.cd.Surge = now() + 2
			sendCooldown(p, s, "Surge")
			return
		end
		startForm(p, s, char, "Surge", S.Duration)
		local pos = h2.Position
		radialBlast(p, pos, S.BurstRadius, S.BurstImpulse, 0.55, S.BurstDamage, 2.5, 0.35)
		local g = groundBelow(pos, 30)
		if g and GroundFX then
			GroundFX.impact(g, 4, 12, 95)
			GroundFX.ring(g, 13, 16, 30)
		end
		fire("SurgeBurst", { userId = p.UserId, pos = pos, radius = S.BurstRadius })
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the silver form. The caster's client runs the cutscene; here the caster is shielded through it, the form
-- (and the evasion) switches on when the eyes open, and the shockwave throws everything around at BurstAt.
-- G during the form: the flurry - a blink to each of the nearest enemies in turn, a true-damage strike on each.
local function castFlurry(p, s)
	local char, _, hrp = liveChar(p)
	if not char or os.clock() < s.busy then
		return
	end
	local F = CFG.Instinct.Flurry
	local t = now()
	if t < (s.cd.Flurry or 0) then
		sendCooldown(p, s, "Flurry")
		return
	end
	local list = {}
	for _, m in ipairs(enemies(p)) do
		local d = (rootOf(m).Position - hrp.Position).Magnitude
		if d <= F.Range then
			table.insert(list, { m = m, d = d })
		end
	end
	if #list == 0 then
		Broadcast:FireClient(p, "FlurryNone", {})
		return
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	s.cd.Flurry = t + cdFor(p, "Flurry", F.Cooldown)
	sendCooldown(p, s, "Flurry")
	local n = math.min(#list, F.Targets)
	s.busy = os.clock() + n * F.Step + 0.25
	local id = nextId()
	fire("FlurryStart", { id = id, userId = p.UserId, n = n })
	task.spawn(function()
		for i = 1, n do
			local c2, hum, h2 = liveChar(p)
			if c2 ~= char or not instinctOn(s, char) then
				break
			end
			local m = list[i].m
			local r = m.Parent and rootOf(m)
			if r then
				local from = h2.Position
				local toward = flatOf(r.Position - from, flatOf(h2.CFrame.LookVector, FWD))
				local dest = clearPath(r.Position, r.Position - toward * 3.2)
				dest = standAt(dest, hum, h2, char:GetAttribute("Flying") == true)
				blink(char, dest, r.Position)
				breakGuard(m, 2)
				knock(p, m, (toward + UP * F.UpBias).Unit * F.Impulse, F.Ragdoll, F.Damage, 0, true)
				fire("FlurryHit", { id = id, userId = p.UserId, from = from, to = dest, pos = r.Position, dir = toward, i = i, last = i == n })
				worldHooks(p, r.Position, 6)
			end
			task.wait(F.Step)
		end
	end)
end

local function castInstinct(p, s)
	local cur = liveChar(p)
	if cur and instinctOn(s, cur) then
		castFlurry(p, s)
		return
	end
	local char, _, hrp, t = gate(p, s, "Instinct")
	if not char then
		return
	end
	local I = CFG.Instinct
	s.cd.Instinct = t + I.CutTime + I.Duration + cdFor(p, "Instinct", I.Cooldown) -- replaced by the real cooldown when the form ends
	s.instinctAt = t
	sendCooldown(p, s, "Instinct")
	s.busy = os.clock() + I.CutTime
	ffOn(char, I.CutTime + 0.2, "CutsceneShield")
	s.token += 1
	local tok = s.token
	fire("InstinctStart", { userId = p.UserId, pos = hrp.Position, look = flatOf(hrp.CFrame.LookVector, FWD), cut = I.CutTime, eyes = I.EyesAt, burst = I.BurstAt })
	task.delay(I.EyesAt, function()
		if liveChar(p) ~= char or s.token ~= tok then
			s.cd.Instinct = now() + 3
			sendCooldown(p, s, "Instinct")
			return
		end
		startForm(p, s, char, "Instinct", (I.CutTime - I.EyesAt) + I.Duration)
		fire("InstinctEyes", { userId = p.UserId })
	end)
	task.delay(I.BurstAt, function()
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or s.token ~= tok then
			return
		end
		local pos = h2.Position
		radialBlast(p, pos, I.BurstRadius, I.BurstImpulse, 0.5, I.BurstDamage, I.BurstRagdoll, 0.4)
		local g = groundBelow(pos, 30)
		if g and GroundFX then
			GroundFX.impact(g, 5, 18, 120)
			GroundFX.ring(g, 18, 22, 34)
			GroundFX.ring(g, 30, 18, 26)
		end
		fire("InstinctBurst", { userId = p.UserId, pos = pos, radius = I.BurstRadius })
	end)
end

-- the blink: BEHIND the attacker (facing its back) when there is one, else a sidestep off the projectile's line
dodge = function(p, s, threatModel, threatPos, threatVel)
	local char, hum, hrp = liveChar(p)
	if not char or not instinctOn(s, char) then
		return false
	end
	local I = CFG.Instinct
	local clock = os.clock()
	if clock - s.lastDodge < I.DodgeInterval then
		return true -- still inside the last blink: this one is evaded too
	end
	s.lastDodge = clock
	local from = hrp.Position
	local flying = char:GetAttribute("Flying") == true
	local dest, face
	local r = threatModel and threatModel.Parent and threatModel ~= char and rootOf(threatModel)
	if r and (r.Position - from).Magnitude < 90 then
		local facing = flatOf(r.CFrame.LookVector, flatOf(from - r.Position, FWD))
		dest = clearPath(r.Position, r.Position - facing * I.DodgeBehind)
		face = r.Position
	else
		local v = threatVel and flatOf(threatVel, nil)
		local side = v and v:Cross(UP) or flatOf(hrp.CFrame.RightVector, Vector3.xAxis)
		if math.random() < 0.5 then
			side = -side
		end
		dest = clearPath(from, from + side * 8)
		face = threatPos or (from + flatOf(hrp.CFrame.LookVector, FWD) * 10)
	end
	dest = standAt(dest, hum, hrp, flying)
	blink(char, dest, face)
	fire("Dodge", { userId = p.UserId, from = from, to = dest })
	return true
end

-- the shared melee dodge hook (other kits call Evasion.tryEvade before a melee hit lands on a player)
if Evasion and Evasion.addHandler then
	Evasion.addHandler(function(victim, attacker)
		local pl = Players:GetPlayerFromCharacter(victim)
		local s = pl and state[pl]
		if s and instinctOn(s, victim) then
			return dodge(pl, s, attacker)
		end
		return false
	end)
end

-- 20x a second: an enemy body (or a loose projectile) closing on a silver-form player inside DodgeRadius sets off a blink
local function threatScan()
	local I = CFG.Instinct
	local clock = os.clock()
	for p, s in pairs(state) do
		local char, _, hrp = liveChar(p)
		if char and instinctOn(s, char) and clock >= s.busy and clock - s.lastDodge >= I.DodgeInterval then
			local pos = hrp.Position
			local found = false
			for _, m in ipairs(enemies(p)) do
				local r = rootOf(m)
				local off = pos - r.Position
				local d = off.Magnitude
				-- only the enemy's own motion counts (walking up to a standing enemy is not a threat)
				if d <= I.DodgeRadius and d > 0.1 and r.AssemblyLinearVelocity:Dot(off.Unit) >= I.ClosingSpeed then
					dodge(p, s, m)
					found = true
					break
				end
			end
			if not found then
				for _, part in ipairs(FXFolder:GetChildren()) do
					if part:IsA("BasePart") and not part.Anchored then
						local toMe = pos - part.Position
						local d = toMe.Magnitude
						if d <= I.DodgeRadius + 2 and d > 0.1 and part.AssemblyLinearVelocity:Dot(toMe.Unit) >= I.ProjectileSpeed then
							dodge(p, s, nil, part.Position, part.AssemblyLinearVelocity)
							break
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- M1: the kit's own four-hit combo. A box in front of the root (like the shared punch) catches NPCs and players.
-- Golden form: x1.2 damage and every connecting swing throws a small energy shockwave. Silver form: true damage, blocks
-- and dodges ignored, and every hit launches with StrikeImpulseMul x the impulse.
local function resolveStrike(p, s, char, combo, aim)
	local M = CFG.Strike
	local c2, _, hrp = liveChar(p)
	if c2 ~= char then
		return
	end
	local form = formOf(s, char)
	local final = combo >= M.Combo
	local cf = CFrame.lookAt(hrp.Position, hrp.Position + aim) * CFrame.new(0, 0, -M.Range)
	local half = M.HitboxSize / 2 + Vector3.new(0.5, 0.5, 0.5)
	local shockAt
	local struck = {}
	PvPBal.m1Begin(final) -- (2026-11-09) M1 hits: full damage on players, and they break a cast; (2026-11-11) a finisher breaks a block
	for _, m in ipairs(enemies(p)) do
		local hitPos
		-- (2026-11-10, "hard to hit people with the normal attack when they're running") a PLAYER is also tested where it
		-- stood since this swing started, as the attacker saw it (PvP.lagOffsets, rewound over M.HitDelay + ping + the
		-- interpolation buffer), in a box PvP.MELEE_PAD studs bigger each way. An NPC gets { zero } and the plain box: unchanged.
		local offs = PvPBal.lagOffsets(m, p, M.HitDelay)
		local hb = PvPBal.playerOf(m) and (half + Vector3.one * PvPBal.MELEE_PAD) or half
		local function inBox(pos)
			for _, off in ipairs(offs) do
				local l = cf:PointToObjectSpace(pos + off)
				if math.abs(l.X) <= hb.X and math.abs(l.Y) <= hb.Y and math.abs(l.Z) <= hb.Z then
					return true
				end
			end
			return false
		end
		-- (2026-11-10) a giant form: its body point nearest the strike box counts (its real parts float far above a
		-- normal-height swing, so Goku's combo used to pass straight through Kurama / the Susanoo)
		local fp = not PvPBal.isDown(m) and PvPBal.formPoint(m, cf.Position)
		if fp and inBox(fp) then
			hitPos = fp
		end
		-- (2026-11-08) a body that was flung and is still down is passed over: no juggling someone on the ground
		for _, n in ipairs(PvPBal.isDown(m) and {} or { "UpperTorso", "LowerTorso", "Head", "Torso", "HumanoidRootPart" }) do
			local part = m:FindFirstChild(n)
			if part and inBox(part.Position) then
				hitPos = part.Position
				break
			end
		end
		local victim = hitPos and Players:GetPlayerFromCharacter(m)
		local dodged = hitPos and victim and form ~= "Instinct" and Evasion and Evasion.tryEvade(m, char)
		if hitPos and not dodged then
			local amount = final and M.FinalDamage or M.Damage
			local landed = true
			if form == "Instinct" then
				local I = CFG.Instinct
				local L = final and M.FinalLaunch or M.LightLaunch
				breakGuard(m, 1.2)
				landed = knock(p, m, (aim * L.X + UP * L.Y) * I.StrikeImpulseMul, final and M.FinalRagdoll or M.LightRagdoll, amount, 0, true)
			else
				amount = dmg(s, char, amount) -- (2026-11-11) a held guard is handled in PvP.dmg now (the old local x0.25 is gone)
				if final then
					local fv, fr = PvPBal.m1Finish(m, aim * M.FinalLaunch.X + UP * M.FinalLaunch.Y, M.FinalRagdoll) -- (2026-11-09) a player stays within reach
					landed = knock(p, m, fv, fr, amount)
				elseif evades(p, m) then
					landed = false
				else
					rawDamage(p, m, amount)
					if PvPBal.absorbed and PvPBal.absorbed(m) then
						landed = false -- (2026-11-11) blocked: no shove, no stun
					elseif victim then
						Knockback:FireClient(victim, (aim * M.Push + UP * 4) * PvPBal.knockMul(), 0, 0.5) -- a shove, no tumble
						PvPBal.stun(m, M.StunTime) -- (2026-11-08) and the same stun the NPCs get
					elseif RagdollService and RagdollService.IsRagdolled(m) then
						RagdollService.Fling(m, aim * 30 + UP * 30, randomUnit() * 10, 2.6)
					else
						m:SetAttribute("StunnedUntil", now() + M.StunTime)
						local r = rootOf(m)
						if r then
							r.AssemblyLinearVelocity = aim * M.Push + UP * 4
						end
					end
				end
			end
			if landed then
				struck[m] = true
				shockAt = shockAt or hitPos
				fire("StrikeHit", { userId = p.UserId, pos = hitPos, combo = combo, final = final, form = form, dir = aim })
			end
		end
	end
	PvPBal.m1End()
	if shockAt and form == "Surge" then
		-- the golden form's shockwave: everything near the struck body is shoved out (the struck body included)
		local S = CFG.Surge
		for _, m in ipairs(enemies(p)) do
			PvPBal.aimAt(shockAt) -- (2026-11-10) forms: nearest the shockwave
			local off = rootOf(m).Position - shockAt
			local d = off.Magnitude
			if struck[m] and not final then
				damage(p, m, dmg(s, char, S.ShockDamage))
			elseif d <= S.ShockRadius and not PvPBal.isDown(m) then
				local dir = ((d > 0.5 and off.Unit or aim) + aim * 0.6 + UP * 0.4).Unit
				knock(p, m, dir * S.ShockImpulse * (0.5 + 0.5 * (1 - d / S.ShockRadius)), final and M.FinalRagdoll or 1.4, dmg(s, char, S.ShockDamage), 0.6)
			end
		end
		pushLoose(shockAt, S.ShockRadius, S.ShockImpulse, 0.4)
		fire("StrikeShock", { userId = p.UserId, pos = shockAt, dir = aim, radius = S.ShockRadius, final = final })
	end
	if WorldBlast then
		WorldBlast:Fire(cf.Position, 4.5, p.UserId)
	end
end

local function castStrike(p, s, payload)
	local M = CFG.Strike
	local char, _, hrp = liveChar(p)
	if not char or os.clock() < s.busy or PvPBal.stunned(p) then -- (2026-11-08) no M1 while stunned in PvP
		return
	end
	local clock = os.clock()
	-- 0.1 s of slack (2026-11-07): the client sends a buffered / held strike right on the interval, and network jitter
	-- must not get it refused while the client already plays it
	if clock - s.lastSwing < M.SwingInterval - 0.1 or clock < s.strikeLock - 0.1 then
		return
	end
	if clock - s.lastSwing > M.ComboReset then
		s.combo = 0
	end
	s.combo = s.combo % M.Combo + 1
	s.lastSwing = clock
	local combo = s.combo
	if combo >= M.Combo then
		s.strikeLock = clock + M.FinalCooldown
	end
	local aim = flatOf(payload.aim, flatOf(hrp.CFrame.LookVector, FWD))
	fire("Strike", { userId = p.UserId, combo = combo, dir = aim, form = formOf(s, char) })
	task.delay(M.HitDelay, resolveStrike, p, s, char, combo, aim)
end

---------------------------------------------------------------------------------------------------
-- spawning, kit switching, requests
local function onCharacter(p, char)
	local s = getState(p)
	s.token += 1
	s.busy = 0
	s.beam = nil
	s.combo = 0
	if s.form then
		endForm(p, s, "death")
	end
	if p:GetAttribute("Kit") == CFG.KitId then
		char:SetAttribute("OwnM1", true)
	end
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.Died:Connect(function()
			if s.form and s.form.char == char then
				endForm(p, s, "death")
			end
			s.beam = nil
		end)
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
	s.beam = nil
	s.busy = 0
	if s.form then
		endForm(p, s, "switch")
	end
	if char then
		if char:GetAttribute("Flying") then
			char:SetAttribute("Flying", false)
		end
		if char:GetAttribute("OwnM1") and p:GetAttribute("Kit") ~= "Zangetsu" then
			char:SetAttribute("OwnM1", nil)
		end
	end
end

local function onPlayer(p)
	getState(p)
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

Request.OnServerEvent:Connect(function(p, action, payload)
	local s = getState(p)
	if type(payload) ~= "table" then
		payload = {}
	end
	-- cursor updates for a charge in progress only move a point, so they skip the request limiter
	if action == "BeamAim" then
		if s.beam then
			s.beam.target = validPoint(payload.target) or s.beam.target
		end
		return
	end
	if typeof(action) ~= "string" or not rateOk(s) then
		return
	end
	if p:GetAttribute("Kit") ~= CFG.KitId then
		if action == "Flight" and payload.on == false then
			setFlying(p, false)
		end
		return
	end
	if action == "Flight" then
		setFlying(p, payload.on == true)
	elseif action == "Strike" then
		castStrike(p, s, payload)
	elseif action == "Beam" then
		castBeam(p, s, payload)
	elseif action == "Warp" then
		castWarp(p, s, payload)
	elseif action == "Surge" then
		castSurge(p, s)
	elseif action == "Instinct" then
		castInstinct(p, s)
	elseif action == "Dodge" then
		-- the client caught itself being knocked down while in the silver form: blink away from whoever did it
		local char, _, hrp = liveChar(p)
		if char and instinctOn(s, char) then
			local uid = char:GetAttribute("LastHitBy")
			local ap = uid and Players:GetPlayerByUserId(uid)
			local threat = ap and ap.Character
			if not threat then
				local bestD
				for _, m in ipairs(enemies(p)) do
					local d = (rootOf(m).Position - hrp.Position).Magnitude
					if d < 40 and (not bestD or d < bestD) then
						threat, bestD = m, d
					end
				end
			end
			dodge(p, s, threat)
		end
	end
end)

-- every frame: hit batches, forms running out, KitLocked; 20x a second: the evasion scan; every second: OwnM1
local hitBatchT, scanAt, watchAt = 0, 0, 0
RunService.Heartbeat:Connect(function()
	if #hitBatch > 0 then
		local list = hitBatch
		hitBatch = {}
		Broadcast:FireAllClients("Hits", list)
	end
	local clock = os.clock()
	local t = now()
	for p, s in pairs(state) do
		if s.form and (not s.form.char.Parent or t >= s.form.untilT) then
			endForm(p, s, "time")
		end
		-- KitLocked is shared by every kit server: only written while this kit is equipped, and only on change
		if p:GetAttribute("Kit") == CFG.KitId then
			local locked = clock < s.busy
			if (p:GetAttribute("KitLocked") == true) ~= locked then
				p:SetAttribute("KitLocked", locked or nil)
			end
		end
	end
	if clock >= scanAt then
		scanAt = clock + 0.05
		threatScan()
	end
	if clock >= watchAt then
		watchAt = clock + 1
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and p:GetAttribute("Kit") == CFG.KitId and char:GetAttribute("OwnM1") ~= true then
				char:SetAttribute("OwnM1", true)
			end
		end
	end
end)

-- Studio-only test hook: runs the shared dodge path / reads state without a second player
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "AscendantServerDebug"
	hook.OnInvoke = function(cmd, a, b)
		if cmd == "evade" then
			return Evasion ~= nil and Evasion.tryEvade(a, b)
		elseif cmd == "state" then
			local s = state[a]
			local char = a and a.Character
			return s and { form = formOf(s, char), busy = s.busy - os.clock(), cd = s.cd, flying = char and char:GetAttribute("Flying") } or nil
		elseif cmd == "hurt" then
			-- deals `b` true damage to player a's character (tests the silver form's undo)
			local char = a and a.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.Health = math.max(hum.Health - b, 0)
				return hum.Health
			end
		end
		return nil
	end
	hook.Parent = script
end

-- PERKS (2026-11-07, kits-D): Instant Ult Charge. ShopService fires ServerStorage.PerkHooks.UltReset(player) after the
-- purchase is saved; an Ascendant player's silver form (and its flurry) is ready at once. Bought while the form stands
-- or its cutscene plays, the form's ending starts no cooldown either.
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("UltReset", 30)
	if not (ev and ev:IsA("BindableEvent")) then
		warn("[AscendantService] PerkHooks.UltReset not found: the instant ult product does nothing for the Ascendant")
		return
	end
	ev.Event:Connect(function(p)
		if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
			return
		end
		local s = getState(p)
		if instinctOn(s, p.Character) or (s.instinctAt and now() - s.instinctAt < CFG.Instinct.EyesAt + 0.5) then
			s.ultFree = true
		end
		s.cd.Instinct, s.cd.Flurry = 0, 0
		sendCooldown(p, s, "Instinct")
		sendCooldown(p, s, "Flurry")
	end)
end)

print("[AscendantService] online")
