--!nocheck
-- NPCService: keeps a population of wandering ragdoll NPCs (R15 constraint rigs) alive in the arena.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("GojoShared")
local CFG = require(Shared:WaitForChild("Config"):WaitForChild("NPC"))
local GojoServer = ServerScriptService:WaitForChild("GojoServer")
local RagdollService = require(GojoServer:WaitForChild("RagdollService"))
local Threat = GojoServer:WaitForChild("Threat")

RagdollService.Init()

-- the bodies live in a MODEL, not a Folder: a Highlight adorned to a Model outlines every body inside it, which is how
-- the Unlimited Void lights all of them at once past the engine's 31-Highlight limit (a Folder adornee draws nothing)
local npcFolder = workspace:FindFirstChild("NPCs")
if npcFolder and not npcFolder:IsA("Model") then
	local old = npcFolder
	npcFolder = Instance.new("Model")
	npcFolder.Name = "NPCs"
	for _, c in ipairs(old:GetChildren()) do
		c.Parent = npcFolder
	end
	old:Destroy()
	npcFolder.Parent = workspace
elseif not npcFolder then
	npcFolder = Instance.new("Model")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = workspace
end

-- city life (npc-life, 2026-11-07): GojoServer.CityNav builds the city's waypoint graph at start and drives the wander /
-- POI / signal-wait / flee behaviour along it. Absent, failed or still building -> the original open-field wander below.
local CityNav = nil
do
	local m = GojoServer:FindFirstChild("CityNav")
	if m and CFG.CityNav ~= false then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			local okI, e = pcall(res.init, CFG)
			if okI then
				CityNav = res
			else
				warn("[NPCService] CityNav.init failed: " .. tostring(e))
			end
		else
			warn("[NPCService] CityNav failed to load: " .. tostring(res))
		end
	end
end
local function cityOn()
	return CityNav ~= nil and CityNav.ready()
end

local SKIN = {
	Color3.fromRGB(255, 224, 196), Color3.fromRGB(241, 194, 150), Color3.fromRGB(224, 172, 120),
	Color3.fromRGB(198, 140, 92), Color3.fromRGB(150, 98, 60), Color3.fromRGB(110, 72, 46),
}
local SHIRT = {
	Color3.fromRGB(28, 30, 40), Color3.fromRGB(28, 30, 40), Color3.fromRGB(44, 62, 120),
	Color3.fromRGB(150, 40, 48), Color3.fromRGB(232, 232, 236), Color3.fromRGB(58, 110, 72),
	Color3.fromRGB(108, 72, 150), Color3.fromRGB(205, 140, 45), Color3.fromRGB(70, 74, 86),
}
local PANTS = {
	Color3.fromRGB(24, 24, 30), Color3.fromRGB(42, 48, 68), Color3.fromRGB(78, 60, 44),
	Color3.fromRGB(58, 60, 66), Color3.fromRGB(30, 40, 62),
}
local DEFAULT_ANIMS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	sit = "rbxassetid://2506281703",
}
local animIds = nil

local records = {} -- [model] = rec
local pendingSpawns = 0
local serial = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function pick(t)
	return t[math.random(#t)]
end

local function refreshRayFilter()
	local list = { npcFolder }
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(list, fx)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function boundsPart()
	local a = workspace:FindFirstChild("Arena")
	return a and a:FindFirstChild("ArenaBounds")
end

local function spawnParts()
	local a = workspace:FindFirstChild("Arena")
	local f = a and a:FindFirstChild("NPCSpawns")
	local list = {}
	if f then
		for _, p in ipairs(f:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

local function randomInBounds()
	local b = boundsPart()
	if b then
		local half = b.Size / 2
		return b.CFrame:PointToWorldSpace(Vector3.new((math.random() * 2 - 1) * (half.X - 6), 0, (math.random() * 2 - 1) * (half.Z - 6)))
	end
	return Vector3.new(math.random(-110, 110), 10, math.random(-110, 110))
end

local function clampToBounds(pos)
	local b = boundsPart()
	if not b then
		return Vector3.new(math.clamp(pos.X, -120, 120), pos.Y, math.clamp(pos.Z, -120, 120))
	end
	local l = b.CFrame:PointToObjectSpace(pos)
	local half = b.Size / 2
	l = Vector3.new(math.clamp(l.X, -half.X + 4, half.X - 4), l.Y, math.clamp(l.Z, -half.Z + 4, half.Z - 4))
	return b.CFrame:PointToWorldSpace(l)
end

-- studs a point lies beyond the arena's edge, measured flat (0 anywhere inside it)
local function outsideBy(pos)
	local b = boundsPart()
	if not b then
		return math.max(math.abs(pos.X) - 120, math.abs(pos.Z) - 120, 0)
	end
	local l = b.CFrame:PointToObjectSpace(pos)
	local half = b.Size / 2
	return math.max(math.abs(l.X) - half.X, math.abs(l.Z) - half.Z, 0)
end

local function groundAt(pos)
	refreshRayFilter()
	local hit = workspace:Raycast(Vector3.new(pos.X, pos.Y + 80, pos.Z), Vector3.new(0, -260, 0), rayParams)
	return hit and hit.Position or Vector3.new(pos.X, 2, pos.Z)
end

local function randomFlat()
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function readAnimIds(rig)
	if animIds then
		return
	end
	local ids = {}
	local animate = rig:FindFirstChild("Animate")
	if animate then
		for _, key in ipairs({ "idle", "walk", "run", "sit" }) do
			local sv = animate:FindFirstChild(key)
			local anim = sv and sv:FindFirstChildOfClass("Animation")
			if anim and anim.AnimationId ~= "" then
				ids[key] = anim.AnimationId
			end
		end
	end
	animIds = {
		idle = ids.idle or DEFAULT_ANIMS.idle,
		walk = ids.walk or DEFAULT_ANIMS.walk,
		run = ids.run or DEFAULT_ANIMS.run,
		sit = ids.sit or DEFAULT_ANIMS.sit,
	}
end

local function setAnim(rec, key, speed)
	if rec.current ~= key then
		local old = rec.current and rec.tracks[rec.current]
		if old then
			old:Stop(0.2)
		end
		rec.current = key
		local new = key and rec.tracks[key]
		if new then
			new:Play(0.2)
		end
	end
	local tr = key and rec.tracks[key]
	if tr and speed then
		tr:AdjustSpeed(speed)
	end
end

local function makeHealthBar(model, head)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(64, 7)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	back.BorderSizePixel = 0
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 230, 120)
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner:Clone().Parent = fill
	bb.Parent = model
	return bb, fill
end

local function fadeAndDestroy(model)
	local info = TweenInfo.new(CFG.FadeTime)
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(CFG.FadeTime + 0.05, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- with more bodies than spawn pads, a new one goes to the pad with the most room: clear of the other bodies, and not
-- right under a player's nose (a replacement should walk in, not pop up in someone's face)
local function pickSpawn()
	local spots = spawnParts()
	if #spots == 0 then
		return nil
	end
	local others = {}
	for _, rec in pairs(records) do
		if not rec.dead and rec.hrp.Parent then
			table.insert(others, rec.hrp.Position)
		end
	end
	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			table.insert(players, r.Position)
		end
	end
	local best, bestScore
	for _, s in ipairs(spots) do
		local pos = s.Position
		local room = 24
		for _, o in ipairs(others) do
			room = math.min(room, ((o - pos) * Vector3.new(1, 0, 1)).Magnitude)
		end
		local seen = 30
		for _, o in ipairs(players) do
			seen = math.min(seen, (o - pos).Magnitude)
		end
		local score = room + seen * 0.5 + math.random() * 8
		if not bestScore or score > bestScore then
			best, bestScore = s, score
		end
	end
	return best
end

local spawnNPC -- forward

local function onDeath(rec)
	if rec.dead then
		return
	end
	rec.dead = true
	local model = rec.model
	model:SetAttribute("Dead", true)
	RagdollService.Ragdoll(model, nil)
	setAnim(rec, nil)
	if rec.bar then
		rec.bar.Enabled = false
	end
	local uid = model:GetAttribute("LastHitBy")
	if uid then
		local p = Players:GetPlayerByUserId(uid)
		local ls = p and p:FindFirstChild("leaderstats")
		local kills = ls and ls:FindFirstChild("Kills")
		if kills and not kills:IsA("IntValue") then -- (2026-11-11) HIDE MY KILLS: the real counter is in HiddenStats
			local hs = p:FindFirstChild("HiddenStats")
			kills = hs and hs:FindFirstChild("Kills")
		end
		if kills then
			kills.Value += 1
		end
	end
	pendingSpawns += 1
	task.delay(CFG.RespawnDelay, function()
		pendingSpawns -= 1
		spawnNPC()
	end)
	task.delay(CFG.CorpseTime, function()
		if model.Parent then
			fadeAndDestroy(model)
		end
	end)
end

spawnNPC = function()
	serial += 1
	local desc = Instance.new("HumanoidDescription")
	local skin, shirt, pants = pick(SKIN), pick(SHIRT), pick(PANTS)
	desc.HeadColor = skin
	desc.TorsoColor = shirt
	desc.LeftArmColor = shirt
	desc.RightArmColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		warn("[NPCService] could not build an NPC rig: " .. tostring(rig))
		return nil
	end
	readAnimIds(rig)
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local bc = rig:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	for _, n in ipairs({ "LeftHand", "RightHand" }) do
		local h = rig:FindFirstChild(n)
		if h then
			h.Color = skin
		end
	end
	local head = rig:FindFirstChild("Head")
	if head and not head:FindFirstChildOfClass("Decal") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = "rbxasset://textures/face.png"
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end
	local hum = rig:FindFirstChildOfClass("Humanoid")
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		rig:Destroy()
		return nil
	end
	rig.Name = "NPC_" .. serial
	hum.MaxHealth = CFG.MaxHealth
	hum.Health = CFG.MaxHealth
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	local walkSpeed = CFG.WalkSpeedMin + math.random() * (CFG.WalkSpeedMax - CFG.WalkSpeedMin)
	hum.WalkSpeed = walkSpeed

	local spot = pickSpawn()
	local base = spot and (spot.Position + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))) or randomInBounds()
	local g = groundAt(base)
	local standY = g.Y + hum.HipHeight + hrp.Size.Y / 2 + 0.15
	rig:PivotTo(CFrame.new(g.X, standY, g.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	CollectionService:AddTag(rig, CFG.Tag)
	rig:SetAttribute("NPC", true)
	rig:SetAttribute("Ragdolled", false)
	rig:SetAttribute("Dead", false)
	rig.Parent = npcFolder
	RagdollService.Setup(rig)

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for key, id in pairs(animIds) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local okT, tr = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if okT and tr then
			tr.Looped = true
			tr.Priority = (key == "idle") and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement
			tracks[key] = tr
		end
	end

	local bar, fill = makeHealthBar(rig, head)
	bar.Enabled = false -- (2026-11-11) "take away npc health bars": kept (the updates write to it) but never shown
	local t = os.clock()
	local rec = {
		model = rig, hum = hum, hrp = hrp, tracks = tracks, current = nil,
		mode = "idle", nextAt = t + math.random() * 2, target = nil, deadline = 0, stuck = 0,
		fleeUntil = 0, fleeFrom = nil, nextFleeAt = 0, walkSpeed = walkSpeed,
		bar = bar, fill = fill, dead = false, wasRagdolled = false, lastMoveTo = 0,
	}
	records[rig] = rec
	if CityNav then
		CityNav.onSpawn(rec)
	end
	setAnim(rec, "idle", 1)
	hum.HealthChanged:Connect(function(h)
		local frac = math.clamp(h / hum.MaxHealth, 0, 1)
		fill.Size = UDim2.fromScale(frac, 1)
		fill.BackgroundColor3 = Color3.fromRGB(230, 70, 60):Lerp(Color3.fromRGB(110, 230, 120), frac)
		bar.Enabled = frac < 1 and frac > 0
	end)
	hum.Died:Connect(function()
		onDeath(rec)
	end)
	return rig
end

local function updateNPC(rec, t, serverNow, dt)
	local model, hum, hrp = rec.model, rec.hum, rec.hrp
	if model:GetAttribute("Ragdolled") then
		rec.wasRagdolled = true
		setAnim(rec, nil)
		return
	end
	if rec.wasRagdolled then
		rec.wasRagdolled = false
		rec.mode = "idle"
		rec.nextAt = t + 0.7
		hum.WalkSpeed = rec.walkSpeed
		if CityNav then
			CityNav.reset(rec)
		end
	end
	if (model:GetAttribute("StunnedUntil") or 0) > serverNow then
		if rec.mode ~= "stunned" then
			hum:MoveTo(hrp.Position)
		end
		rec.mode = "stunned"
		rec.nextAt = t + 0.25
	elseif rec.fleeUntil > t and rec.fleeFrom then
		hum.WalkSpeed = CFG.RunSpeed
		if cityOn() then
			CityNav.flee(rec, t)
		elseif t >= rec.nextFleeAt then
			rec.nextFleeAt = t + 0.5
			local away = (hrp.Position - rec.fleeFrom) * Vector3.new(1, 0, 1)
			if away.Magnitude < 0.5 then
				away = randomFlat()
			end
			hum:MoveTo(clampToBounds(hrp.Position + away.Unit * 30))
		end
		rec.mode = "flee"
	else
		if rec.mode == "flee" or rec.mode == "stunned" then
			rec.mode = "idle"
			rec.nextAt = t + 0.4
			hum.WalkSpeed = rec.walkSpeed
			hum:MoveTo(hrp.Position)
			if CityNav then
				CityNav.reset(rec)
			end
		end
		if cityOn() then
			CityNav.wander(rec, t, dt)
		elseif rec.mode == "idle" then
			if t >= rec.nextAt then
				local dist = CFG.WanderStepMin + math.random() * (CFG.WanderStepMax - CFG.WanderStepMin)
				rec.target = clampToBounds(hrp.Position + randomFlat() * dist)
				rec.deadline = t + 8
				rec.stuck = 0
				rec.mode = "walk"
				rec.lastMoveTo = t
				hum.WalkSpeed = rec.walkSpeed
				hum:MoveTo(rec.target)
			end
		elseif rec.mode == "walk" then
			local flat = (hrp.Position - rec.target) * Vector3.new(1, 0, 1)
			local speed = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			rec.stuck = (speed < 0.6) and (rec.stuck + dt) or 0
			if flat.Magnitude < 2.5 or t > rec.deadline or rec.stuck > 1.5 then
				rec.mode = "idle"
				rec.nextAt = t + CFG.IdleTimeMin + math.random() * (CFG.IdleTimeMax - CFG.IdleTimeMin)
				hum:MoveTo(hrp.Position)
			end
		end
	end
	local v = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
	if v > 14 then
		setAnim(rec, "run", v / 16)
	elseif v > 0.8 then
		setAnim(rec, "walk", v / 10)
	else
		setAnim(rec, (rec.pose == "sit" and rec.tracks.sit) and "sit" or "idle", 1)
	end
end

-- a living body knocked out of play - launched off across the map, stranded outside the arena, or hung up in the sky -
-- is retired like a death (onDeath credits whoever hit it last and schedules the replacement)
local function checkLost(rec, pos, t)
	local m = rec.model
	if m:GetAttribute("GrabbedBy") or m:GetAttribute("InDomain") then
		rec.lostSince = nil -- held by a move: wherever it is, it is still in play
		return
	end
	local out = outsideBy(pos)
	local limit
	if out > CFG.FarMargin then
		limit = CFG.FarTime
	elseif out > CFG.LostMargin then
		limit = CFG.LostTime
	elseif pos.Y > CFG.SkyHeight then
		limit = CFG.SkyTime
	end
	if not limit then
		rec.lostSince = nil
		return
	end
	rec.lostSince = rec.lostSince or t
	if t - rec.lostSince >= limit then
		m:SetAttribute("Retired", true) -- removed by the game, not by a hit: DamageFeed shows no number for it
		rec.hum.Health = 0
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then
		return
	end
	local step = acc
	acc = 0
	local t = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, rec in pairs(records) do
		if not model.Parent or not rec.hrp.Parent or not rec.hum.Parent then
			records[model] = nil
			if not rec.dead then
				-- removed some other way (fell out of the world etc.): the population loop replaces it
				rec.dead = true
			end
			if model.Parent then
				model:Destroy()
			end
		elseif not rec.dead then
			local torso = model:FindFirstChild("LowerTorso") or rec.hrp
			local pos = torso.Position
			if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or pos.Magnitude > 1e5 then
				-- the physics blew up (NaN, or flung off to infinity): nothing left to save, the population loop replaces it
				model:Destroy()
			elseif pos.Y < -150 then
				model:SetAttribute("Retired", true) -- fell out of the world: no damage number
				rec.hum.Health = 0
			else
				local ok, err = pcall(updateNPC, rec, t, serverNow, step)
				if not ok then
					warn("[NPCService] AI error: " .. tostring(err))
				end
				checkLost(rec, pos, t)
				if CityNav then
					CityNav.checkStranded(rec, pos, t)
				end
			end
		elseif ((model:FindFirstChild("LowerTorso") or rec.hrp).Position.Y) < -150 then
			model:Destroy()
		end
	end
end)

Threat.Event:Connect(function(pos, radius, duration)
	if typeof(pos) ~= "Vector3" then
		return
	end
	radius = tonumber(radius) or 50
	duration = tonumber(duration) or 2
	local t = os.clock()
	for model, rec in pairs(records) do
		if not rec.dead and not model:GetAttribute("Ragdolled") and rec.hrp.Parent then
			if (rec.hrp.Position - pos).Magnitude <= radius then
				rec.fleeFrom = pos
				rec.fleeUntil = math.max(rec.fleeUntil, t + duration)
				rec.nextFleeAt = 0
				if math.random() < 0.3 then
					rec.hum.Jump = true
				end
			end
		end
	end
end)

local function setupPlayer(p)
	if p:FindFirstChild("leaderstats") then
		return
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local k = Instance.new("IntValue")
	k.Name = "Kills"
	k.Parent = ls
	ls.Parent = p
end
for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p)
end
Players.PlayerAdded:Connect(setupPlayer)

task.spawn(function()
	-- give the arena a moment so the first wave uses the real spawn points
	local t0 = os.clock()
	while #spawnParts() == 0 and os.clock() - t0 < 5 do
		task.wait(0.25)
	end
	while true do
		local living = 0
		for _, rec in pairs(records) do
			if not rec.dead then
				living += 1
			end
		end
		local need = CFG.Count - living - pendingSpawns
		for _ = 1, math.max(0, need) do
			local ok, err = pcall(spawnNPC)
			if not ok then
				warn("[NPCService] spawn failed: " .. tostring(err))
			end
			task.wait(0.05)
		end
		task.wait(1)
	end
end)

print("[NPCService] online, population " .. CFG.Count)
