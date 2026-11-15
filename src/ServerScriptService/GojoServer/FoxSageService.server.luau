--!nocheck
-- FoxSageService: server side of the Fox Sage kit (original fox-sage fighter).
-- Q Spiral Orb | E Spiral Shuriken | R Sage Mode | F Nine-Tailed Fox (in beast form: click claw, Q roar, E beast bomb)
-- Hits use the same NPC tag + RagdollService as the Limitless kit. The chosen kit lives in the player's "Kit" attribute.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PvP = require(ServerScriptService:WaitForChild("PvP")) -- (2026-11-08) PvP.stunned gates the moves

local FoxShared = ReplicatedStorage:WaitForChild("FoxSageShared")
local CFG = require(FoxShared:WaitForChild("Config"))
local Remotes = FoxShared:WaitForChild("Remotes")
local FoxRequest = Remotes:WaitForChild("FoxRequest")
local FoxEvent = Remotes:WaitForChild("FoxEvent")
local FoxResult = Remotes:WaitForChild("FoxResult")
local NPC_TAG = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC")).Tag
local GojoServer = ServerScriptService:WaitForChild("GojoServer")
local BeastModel = require(GojoServer:WaitForChild("FoxBeastModel"))
local Threat = GojoServer:WaitForChild("Threat", 10)
local WorldBlast = GojoServer:WaitForChild("WorldBlast", 10)

local RagdollService
do
	local ok, res = pcall(require, GojoServer:WaitForChild("RagdollService", 10))
	if ok and res then
		RagdollService = res
		RagdollService.Init()
	else
		warn("[FoxSage] RagdollService unavailable: " .. tostring(res))
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function finite(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function segDist(p, a, b)
	local ab = b - a
	local len2 = ab:Dot(ab)
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	end
	return (p - (a + ab * t)).Magnitude
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

local function flatLook(hrp)
	local lv = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	return lv.Magnitude > 1e-3 and lv.Unit or Vector3.new(0, 0, -1)
end

-- returns (aimDir, flatDir) with the pitch clamped, or nil
local function clampAim(v)
	if typeof(v) ~= "Vector3" or not finite(v) or v.Magnitude < 1e-3 then
		return nil
	end
	v = v.Unit
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	local pitch = math.clamp(math.deg(math.asin(math.clamp(v.Y, -1, 1))), CFG.MinPitch, CFG.MaxPitch)
	local r = math.rad(pitch)
	return (flat * math.cos(r) + Vector3.yAxis * math.sin(r)).Unit, flat
end

local function aimOr(payload, hrp)
	local aim, flat = clampAim(payload.aimDir)
	if not aim then
		flat = flatLook(hrp)
		aim = flat
	end
	return aim, flat
end

---------------------------------------------------------------------------------------------------
-- player state
local state = {}
local function getState(p)
	local s = state[p]
	if not s then
		s = {
			cd = {}, busy = false, busyToken = 0, reqs = {},
			sageChar = nil, sageUntil = 0, sageToken = 0,
			beastChar = nil, beastUntil = 0, beastToken = 0, beastModel = nil, hidden = nil,
			swipeSide = 1, stompHit = {},
		}
		state[p] = s
	end
	return s
end

local function rateOk(s)
	local t = os.clock()
	local r = s.reqs
	while #r > 0 and t - r[1] > 1 do
		table.remove(r, 1)
	end
	if #r >= 20 then
		return false
	end
	table.insert(r, t)
	return true
end

local function setBusy(s, dur)
	s.busyToken += 1
	local tok = s.busyToken
	s.busy = true
	task.delay(dur, function()
		if s.busyToken == tok then
			s.busy = false
		end
	end)
end

local function isSage(p, s)
	return s.sageChar ~= nil and s.sageChar == p.Character and now() < s.sageUntil
end

local function isBeast(p, s)
	return s.beastChar ~= nil and s.beastChar == p.Character
end

-- (scale, powerMul, damageMul)
local function buffs(p, s)
	if isSage(p, s) then
		return CFG.Sage.Scale, CFG.Sage.PowerMul, CFG.Sage.DamageMul
	end
	return 1, 1, 1
end

local function reply(p, ability, ok, info)
	FoxResult:FireClient(p, ability, ok, info or {})
end

local function applyMovement(p, s)
	local char = p.Character
	if not char then
		return
	end
	local ws, jh = CFG.DefaultWalkSpeed, CFG.DefaultJumpHeight
	if p:GetAttribute("Kit") == "FoxSage" then
		if isBeast(p, s) then
			ws, jh = CFG.Beast.WalkSpeed, CFG.Beast.JumpHeight
		elseif isSage(p, s) then
			ws, jh = CFG.Sage.WalkSpeed, CFG.Sage.JumpHeight
		end
	end
	char:SetAttribute("FoxWalkSpeed", ws)
	char:SetAttribute("FoxJumpHeight", jh)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = ws
		hum.JumpHeight = jh
	end
end

---------------------------------------------------------------------------------------------------
-- hitting things
local function torsoOf(model)
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
end

local function strike(p, model, vel, spin, ragTime, dmg)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if dmg and dmg > 0 and hum and hum.Health > 0 and model:GetAttribute("Dead") ~= true then
		model:SetAttribute("LastHitBy", p.UserId)
		hum:TakeDamage(dmg)
	end
	if RagdollService then
		RagdollService.Fling(model, vel, spin or randomUnit() * 12, ragTime)
	end
end

local function excludeList()
	local list = {}
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		table.insert(list, m)
	end
	return list
end

local looseOverlap = OverlapParams.new()
looseOverlap.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props (bowling pins, swings, debris) get shoved too
local function pushLoose(pos, radius, power, upBias)
	looseOverlap.FilterDescendantsInstances = excludeList()
	local pushed = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, looseOverlap)) do
		local root = part.AssemblyRootPart
		if root and not root.Anchored and not pushed[root] then
			pushed[root] = true
			local off = root.Position - pos
			local d = off.Magnitude
			local k = math.clamp(1 - d / radius, 0, 1)
			local radial = d > 0.5 and off.Unit or Vector3.yAxis
			root.AssemblyLinearVelocity += (radial + Vector3.yAxis * upBias).Unit * power * 0.6 * k
		end
	end
end

local function worldFx(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId)
	end
	if Threat then
		Threat:Fire(pos, radius * 2, 2)
	end
end

-- everything within `radius` is thrown straight away from `pos`, harder the closer it was
local function radialBlast(p, pos, radius, power, minPower, upBias, damage, ragTime, fallbackDir)
	local hits = 0
	for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		local t = torsoOf(model)
		if t and model.Parent then
			local off = t.Position - pos
			local d = off.Magnitude
			if d <= radius then
				hits += 1
				local k = 1 - d / radius
				local radial = d > 0.5 and off.Unit or (fallbackDir or Vector3.yAxis)
				local dir = (radial + Vector3.yAxis * upBias).Unit
				strike(p, model, dir * (minPower + (power - minPower) * k), randomUnit() * (10 + 20 * k), ragTime, damage * k)
			end
		end
	end
	pushLoose(pos, radius, power, upBias)
	worldFx(p, pos, radius * 0.6)
	return hits
end

local projRay = RaycastParams.new()
projRay.FilterType = Enum.RaycastFilterType.Exclude

-- flies a projectile from `origin` launched at server time `launchAt`; returns where it stopped (body, wall or range)
local function runProjectile(origin, dir, speed, range, radius, launchAt)
	projRay.FilterDescendantsInstances = excludeList()
	local prev = 0
	while true do
		local dist = math.clamp((now() - launchAt) * speed, 0, range)
		local a = origin + dir * prev
		local b = origin + dir * dist
		local ab = b - a
		local len2 = ab:Dot(ab)
		local hitPos
		if len2 > 1e-6 then
			for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
				local t = torsoOf(model)
				if t and model.Parent and segDist(t.Position, a, b) <= radius + 1.5 then
					local tt = math.clamp((t.Position - a):Dot(ab) / len2, 0, 1)
					hitPos = a + ab * tt
					break
				end
			end
			if not hitPos then
				local res = workspace:Raycast(a, ab + dir * radius, projRay)
				if res then
					hitPos = res.Position - dir * radius * 0.5
				end
			end
		end
		if hitPos or dist >= range then
			return hitPos or b
		end
		prev = dist
		RunService.Heartbeat:Wait()
	end
end

local castCounter = 0
local function nextId()
	castCounter += 1
	return castCounter
end

-- common gate: alive, not busy, off cooldown. Returns char, hum, hrp, t or nil
local function gate(p, s, ability, cdKey)
	local char, hum, hrp = liveChar(p)
	if not char then
		reply(p, ability, false, { reason = "dead" })
		return nil
	end
	if PvP.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		reply(p, ability, false, { reason = "stunned" })
		return nil
	end
	if s.busy then
		reply(p, ability, false, { reason = "busy" })
		return nil
	end
	local t = now()
	if t < (s.cd[cdKey] or 0) then
		reply(p, ability, false, { reason = "cooldown", cooldownEnd = s.cd[cdKey] })
		return nil
	end
	return char, hum, hrp, t
end

---------------------------------------------------------------------------------------------------
-- Q: Spiral Orb
local function requestOrb(p, s, payload)
	if isBeast(p, s) then
		return
	end
	local char, _, hrp, t = gate(p, s, "Orb", "Orb")
	if not char then
		return
	end
	local O = CFG.Orb
	local scale, pmul, dmul = buffs(p, s)
	local _, flat = aimOr(payload, hrp)
	local id = nextId()
	s.cd.Orb = t + O.Cooldown
	setBusy(s, O.ChargeTime + O.DashTime + 0.3)
	FoxEvent:FireAllClients("OrbStart", {
		id = id, userId = p.UserId, sage = scale > 1, scale = scale, charge = O.ChargeTime, dash = O.DashTime,
		speed = O.DashSpeed, dir = flat,
	})
	reply(p, "Orb", true, { id = id, cooldownEnd = s.cd.Orb })
	task.spawn(function()
		task.wait(O.ChargeTime)
		if liveChar(p) ~= char then
			FoxEvent:FireAllClients("OrbEnd", { id = id, userId = p.UserId })
			return
		end
		local hitR = O.HitRadius * scale
		local t0 = os.clock()
		while os.clock() - t0 < O.DashTime + 0.2 do
			local c2, _, hrp2 = liveChar(p)
			if c2 ~= char then
				break
			end
			local v = hrp2.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local fwd = v.Magnitude > 15 and v.Unit or flatLook(hrp2)
			local front = hrp2.Position + fwd * 2.5
			local best, bestD
			for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
				local tor = torsoOf(model)
				if tor and model.Parent then
					local d = (tor.Position - front).Magnitude
					if d <= hitR and (not bestD or d < bestD) then
						best, bestD = model, d
					end
				end
			end
			if best then
				local hitPos = torsoOf(best).Position
				strike(p, best, fwd * O.Power * pmul + Vector3.yAxis * O.Up * pmul, randomUnit() * O.Spin, O.RagdollTime, O.Damage * dmul)
				local R = O.SplashRadius * scale
				for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
					local tt = model ~= best and torsoOf(model)
					if tt and model.Parent then
						local off = tt.Position - hitPos
						local d = off.Magnitude
						if d <= R then
							local k = 1 - d / R
							local radial = d > 0.5 and off.Unit or fwd
							local dir = (radial + fwd * 0.6 + Vector3.yAxis * 0.5).Unit
							strike(p, model, dir * O.SplashPower * pmul * (0.4 + 0.6 * k), randomUnit() * 15, O.RagdollTime, O.Damage * 0.4 * dmul * k)
						end
					end
				end
				pushLoose(hitPos, R, O.SplashPower * pmul, 0.5)
				worldFx(p, hitPos, R * 0.5)
				FoxEvent:FireAllClients("OrbHit", { id = id, userId = p.UserId, pos = hitPos, dir = fwd, radius = R, sage = scale > 1 })
				return
			end
			RunService.Heartbeat:Wait()
		end
		FoxEvent:FireAllClients("OrbEnd", { id = id, userId = p.UserId })
	end)
end

---------------------------------------------------------------------------------------------------
-- E: Spiral Shuriken
local function requestShuriken(p, s, payload)
	if isBeast(p, s) then
		return
	end
	local char, _, hrp, t = gate(p, s, "Shuriken", "Shuriken")
	if not char then
		return
	end
	local S = CFG.Shuriken
	local scale, pmul, dmul = buffs(p, s)
	local aim, flat = aimOr(payload, hrp)
	local id = nextId()
	s.cd.Shuriken = t + S.Cooldown
	setBusy(s, S.ChargeTime + 0.35)
	FoxEvent:FireAllClients("ShurikenStart", { id = id, userId = p.UserId, sage = scale > 1, scale = scale, charge = S.ChargeTime, dir = flat })
	reply(p, "Shuriken", true, { id = id, cooldownEnd = s.cd.Shuriken })
	task.spawn(function()
		local launchAt = t + S.ChargeTime
		while now() < launchAt do
			if liveChar(p) ~= char then
				FoxEvent:FireAllClients("ShurikenCancel", { id = id })
				return
			end
			RunService.Heartbeat:Wait()
		end
		local _, _, hrp2 = liveChar(p)
		local origin = hrp2.Position + Vector3.yAxis * (3.4 + scale) + flat * 1.5
		local la = now()
		FoxEvent:FireAllClients("ShurikenThrow", { id = id, userId = p.UserId, origin = origin, dir = aim, speed = S.Speed, range = S.Range, launchAt = la, scale = scale })
		local pos = runProjectile(origin, aim, S.Speed, S.Range, S.ProjectileRadius * scale, la)
		local R = S.BurstRadius * scale
		FoxEvent:FireAllClients("ShurikenBurst", { id = id, pos = pos, radius = R, hold = S.HoldTime })
		worldFx(p, pos, R * 0.5)
		-- the blade storm: everything nearby is sucked in and churned around inside it
		local ticks = math.max(1, math.floor(S.HoldTime / 0.12))
		local tickDmg = S.Damage * 0.5 * dmul / ticks
		local tEnd = os.clock() + S.HoldTime
		local nextTick = 0
		while os.clock() < tEnd do
			if os.clock() >= nextTick then
				nextTick = os.clock() + 0.12
				for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
					local tor = torsoOf(model)
					if tor and model.Parent then
						local off = tor.Position - pos
						local d = off.Magnitude
						if d <= R * 1.15 then
							local tangent = Vector3.yAxis:Cross(off)
							tangent = tangent.Magnitude > 0.1 and tangent.Unit or randomUnit()
							local inward = d > 0.5 and -off.Unit or Vector3.zero
							local v = inward * math.clamp(d * 3, 0, 45) + tangent * 32 + Vector3.yAxis * (4 + math.random() * 6)
							strike(p, model, v, randomUnit() * 20, S.RagdollTime, tickDmg)
						end
					end
				end
			end
			RunService.Heartbeat:Wait()
		end
		FoxEvent:FireAllClients("ShurikenPop", { id = id, pos = pos, radius = R })
		radialBlast(p, pos, R * 1.3, S.Power * pmul, S.Power * 0.45 * pmul, S.UpBias, S.Damage * 0.5 * dmul, S.RagdollTime, aim)
	end)
end

---------------------------------------------------------------------------------------------------
-- R: Sage Mode
local function endSage(p, s, quiet)
	local char = s.sageChar
	if not char then
		return
	end
	s.sageChar = nil
	s.sageUntil = 0
	s.cd.Sage = now() + CFG.Sage.Cooldown
	if char.Parent then
		char:SetAttribute("SageMode", false)
	end
	applyMovement(p, s)
	if not quiet then
		FoxEvent:FireAllClients("SageOff", { userId = p.UserId })
	end
	reply(p, "Sage", true, { active = false, cooldownEnd = s.cd.Sage })
end

local function requestSage(p, s)
	if isSage(p, s) then
		endSage(p, s)
		return
	end
	local char, _, _, t = gate(p, s, "Sage", "Sage")
	if not char then
		return
	end
	local G = CFG.Sage
	setBusy(s, G.TransformTime)
	s.sageToken += 1
	local tok = s.sageToken
	s.cd.Sage = t + G.TransformTime + 0.5 -- blocks re-casting while meditating
	FoxEvent:FireAllClients("SageStart", { userId = p.UserId, time = G.TransformTime, beast = isBeast(p, s) })
	reply(p, "Sage", true, { transforming = true, time = G.TransformTime })
	task.delay(G.TransformTime, function()
		local c2, _, hrp2 = liveChar(p)
		if s.sageToken ~= tok or c2 ~= char then
			FoxEvent:FireAllClients("SageCancel", { userId = p.UserId })
			return
		end
		s.sageChar = char
		s.sageUntil = now() + G.Duration
		char:SetAttribute("SageUntil", s.sageUntil)
		char:SetAttribute("SageMode", true)
		applyMovement(p, s)
		FoxEvent:FireAllClients("SageOn", { userId = p.UserId, pos = hrp2.Position })
		radialBlast(p, hrp2.Position, 16, 85, 40, 0.6, 0, 2)
		reply(p, "Sage", true, { active = true, untilTime = s.sageUntil })
	end)
end

---------------------------------------------------------------------------------------------------
-- F: Nine-Tailed Fox
local function hideCharacter(char, s)
	s.hidden = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			s.hidden[d] = d.Transparency
			d.Transparency = 1
		end
	end
end

local function showCharacter(s)
	for inst, tr in pairs(s.hidden or {}) do
		if inst.Parent then
			inst.Transparency = tr
		end
	end
	s.hidden = nil
end

local function endBeast(p, s)
	local char = s.beastChar
	if not char then
		return
	end
	s.beastChar = nil
	s.beastUntil = 0
	if s.beastModel then
		s.beastModel:Destroy()
		s.beastModel = nil
	end
	showCharacter(s)
	if char.Parent then
		char:SetAttribute("FoxBeast", false)
	end
	s.cd.Beast = now() + CFG.Beast.Cooldown
	applyMovement(p, s)
	local _, _, hrp = liveChar(p)
	FoxEvent:FireAllClients("BeastEnd", { userId = p.UserId, pos = hrp and hrp.Position })
	reply(p, "Beast", true, { active = false, cooldownEnd = s.cd.Beast })
end

local function requestBeast(p, s)
	if isBeast(p, s) then
		endBeast(p, s)
		return
	end
	local char, _, hrp, t = gate(p, s, "Beast", "Beast")
	if not char then
		return
	end
	local B = CFG.Beast
	setBusy(s, B.TransformTime)
	s.beastToken += 1
	local tok = s.beastToken
	s.cd.Beast = t + B.TransformTime + 0.5
	FoxEvent:FireAllClients("BeastStart", { userId = p.UserId, time = B.TransformTime, pos = hrp.Position })
	reply(p, "Beast", true, { transforming = true, time = B.TransformTime })
	task.delay(B.TransformTime, function()
		local c2, _, hrp2 = liveChar(p)
		if s.beastToken ~= tok or c2 ~= char then
			FoxEvent:FireAllClients("BeastCancel", { userId = p.UserId })
			return
		end
		hideCharacter(char, s)
		local ok, model = pcall(BeastModel.build, char)
		if not ok or not model then
			warn("[FoxSage] beast build failed: " .. tostring(model))
			showCharacter(s)
			FoxEvent:FireAllClients("BeastCancel", { userId = p.UserId })
			return
		end
		s.beastModel = model
		s.beastChar = char
		s.beastUntil = now() + B.Duration
		char:SetAttribute("FoxBeastUntil", s.beastUntil)
		char:SetAttribute("FoxBeast", true)
		applyMovement(p, s)
		FoxEvent:FireAllClients("BeastOn", { userId = p.UserId, pos = hrp2.Position })
		radialBlast(p, hrp2.Position, 26, 150, 60, 0.7, 20, 3)
		reply(p, "Beast", true, { active = true, untilTime = s.beastUntil })
	end)
end

-- beast click: a huge claw swipe that alternates paws
local function requestSwipe(p, s)
	if not isBeast(p, s) then
		return
	end
	local char, _, _, t = gate(p, s, "Swipe", "Swipe")
	if not char then
		return
	end
	local W = CFG.Beast.Swipe
	s.cd.Swipe = t + W.Cooldown
	s.swipeSide = -s.swipeSide
	local side = s.swipeSide
	FoxEvent:FireAllClients("SwipeStart", { userId = p.UserId, side = side, windup = W.Windup })
	task.delay(W.Windup, function()
		local _, _, hrp = liveChar(p)
		if not hrp or not isBeast(p, s) then
			return
		end
		local fwd = flatLook(hrp)
		local right = fwd:Cross(Vector3.yAxis)
		local center = hrp.Position + fwd * W.Reach + Vector3.yAxis * 2
		local sweep = right * -side -- right paw sweeps to the left and vice versa
		for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
			local tor = torsoOf(model)
			if tor and model.Parent then
				local off = tor.Position - center
				if (off * Vector3.new(1, 0, 1)).Magnitude <= W.Radius and math.abs(off.Y) <= 20 then
					local dir = (fwd * 0.6 + sweep * 0.8 + Vector3.yAxis * 0.5).Unit
					strike(p, model, dir * W.Power + Vector3.yAxis * W.Up * 0.3, randomUnit() * 22, 3, W.Damage)
				end
			end
		end
		pushLoose(center, W.Radius, W.Power, 0.5)
		worldFx(p, center, W.Radius * 0.5)
		FoxEvent:FireAllClients("SwipeHit", { userId = p.UserId, pos = center, side = side, dir = fwd })
	end)
end

-- beast Q: a roar shockwave all around
local function requestRoar(p, s)
	if not isBeast(p, s) then
		return
	end
	local char, _, _, t = gate(p, s, "Roar", "Roar")
	if not char then
		return
	end
	local W = CFG.Beast.Roar
	s.cd.Roar = t + W.Cooldown
	setBusy(s, W.Windup + 0.3)
	FoxEvent:FireAllClients("RoarStart", { userId = p.UserId, windup = W.Windup })
	reply(p, "Roar", true, { cooldownEnd = s.cd.Roar })
	task.delay(W.Windup, function()
		local _, _, hrp = liveChar(p)
		if not hrp or not isBeast(p, s) then
			return
		end
		FoxEvent:FireAllClients("Roar", { userId = p.UserId, pos = hrp.Position, radius = W.Radius })
		radialBlast(p, hrp.Position, W.Radius, W.Power, W.Power * 0.4, W.UpBias, W.Damage, 3)
	end)
end

-- beast E: charge a dense chakra bomb in the jaws and fire it
local function requestBomb(p, s, payload)
	if not isBeast(p, s) then
		return
	end
	local char, hum, hrp, t = gate(p, s, "Bomb", "Bomb")
	if not char then
		return
	end
	local W = CFG.Beast.Bomb
	local aim = aimOr(payload, hrp)
	local id = nextId()
	s.cd.Bomb = t + W.Cooldown
	setBusy(s, W.ChargeTime + 0.3)
	FoxEvent:FireAllClients("BombStart", { id = id, userId = p.UserId, charge = W.ChargeTime })
	reply(p, "Bomb", true, { id = id, cooldownEnd = s.cd.Bomb })
	task.spawn(function()
		task.wait(W.ChargeTime)
		local c2, hum2, hrp2 = liveChar(p)
		if c2 ~= char or not isBeast(p, s) then
			FoxEvent:FireAllClients("BombCancel", { id = id })
			return
		end
		local groundOffset = hum2.HipHeight + hrp2.Size.Y / 2
		local fwd = flatLook(hrp2)
		local origin = hrp2.Position + fwd * 20 + Vector3.yAxis * (BeastModel.BodyHeight - groundOffset + 4.5)
		local la = now()
		FoxEvent:FireAllClients("BombFire", { id = id, userId = p.UserId, origin = origin, dir = aim, speed = W.Speed, range = W.Range, launchAt = la })
		local pos = runProjectile(origin, aim, W.Speed, W.Range, W.ProjectileRadius, la)
		FoxEvent:FireAllClients("BombBlast", { id = id, pos = pos, radius = W.Radius })
		radialBlast(p, pos, W.Radius, W.Power, W.Power * 0.35, W.UpBias, W.Damage, 4, aim)
	end)
end

---------------------------------------------------------------------------------------------------
-- kit selection
local function setKit(p, s, kit)
	if kit ~= "FoxSage" and kit ~= "Limitless" then
		return
	end
	-- fighters are unlocked per player (2026-11-07, ShopService's KitsOwned): this old switch must not hand out a
	-- locked one. FoxSage is not on the roster, so it is never owned and this path can no longer reach it.
	local raw = p:GetAttribute("KitsOwned")
	local ok, list = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	if not ok or type(list) ~= "table" or not table.find(list, kit) then
		return
	end
	if p:GetAttribute("Kit") == kit or s.busy then
		return
	end
	if isBeast(p, s) then
		endBeast(p, s)
	end
	if isSage(p, s) then
		endSage(p, s)
	end
	p:SetAttribute("Kit", kit)
	applyMovement(p, s)
end

local function onCharacter(p, char)
	local s = getState(p)
	s.busy = false
	s.busyToken += 1
	s.sageToken += 1
	s.beastToken += 1
	if s.sageChar and s.sageChar ~= char then
		s.sageChar = nil
		s.sageUntil = 0
	end
	if s.beastChar and s.beastChar ~= char then
		s.beastChar = nil
		s.beastModel = nil
		s.hidden = nil
		s.cd.Beast = now() + CFG.Beast.Cooldown
	end
	char:WaitForChild("Humanoid", 10)
	applyMovement(p, s)
end

local function onPlayer(p)
	if p:GetAttribute("Kit") == nil then
		p:SetAttribute("Kit", "Limitless")
	end
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

FoxRequest.OnServerEvent:Connect(function(p, ability, payload)
	local s = getState(p)
	if typeof(ability) ~= "string" or not rateOk(s) then
		return
	end
	if type(payload) ~= "table" then
		payload = {}
	end
	if ability == "SetKit" then
		setKit(p, s, payload.kit)
		return
	end
	if p:GetAttribute("Kit") ~= "FoxSage" then
		return
	end
	if ability == "Orb" then
		requestOrb(p, s, payload)
	elseif ability == "Shuriken" then
		requestShuriken(p, s, payload)
	elseif ability == "Sage" then
		requestSage(p, s)
	elseif ability == "Beast" then
		requestBeast(p, s)
	elseif ability == "Swipe" then
		requestSwipe(p, s)
	elseif ability == "Roar" then
		requestRoar(p, s)
	elseif ability == "Bomb" then
		requestBomb(p, s, payload)
	end
end)

---------------------------------------------------------------------------------------------------
-- timers + the beast trampling whatever it runs through
RunService.Heartbeat:Connect(function()
	local t = now()
	local clock = os.clock()
	for p, s in pairs(state) do
		if s.sageChar and (p.Character ~= s.sageChar or t >= s.sageUntil) then
			endSage(p, s, p.Character ~= s.sageChar)
		end
		if s.beastChar then
			local char, _, hrp = liveChar(p)
			if char ~= s.beastChar or t >= s.beastUntil then
				endBeast(p, s)
			else
				local v = hrp.AssemblyLinearVelocity
				if (v * Vector3.new(1, 0, 1)).Magnitude > 10 then
					local B = CFG.Beast
					for _, model in ipairs(CollectionService:GetTagged(NPC_TAG)) do
						local tor = torsoOf(model)
						if tor and model.Parent and clock >= (s.stompHit[model] or 0) then
							local off = (tor.Position - hrp.Position) * Vector3.new(1, 0, 1)
							if off.Magnitude <= B.StompRadius and math.abs(tor.Position.Y - hrp.Position.Y) < 16 then
								s.stompHit[model] = clock + 0.8
								local radial = off.Magnitude > 0.5 and off.Unit or randomUnit()
								local dir = (radial + Vector3.yAxis * 0.8).Unit
								strike(p, model, dir * B.StompPower + v * 0.5, randomUnit() * 18, 2.5, B.StompDamage)
							end
						end
					end
				end
			end
		end
	end
end)

print("[FoxSage] online")
