--!nocheck
-- ServerScriptService.Sandbox.Dummies: every training dummy in the world. Same rig, tag (RagdollNPC), folder
-- (workspace.NPCs) and RagdollService setup as the fighting game's NPCs, so all ten fighters hit them as they are - but
-- they stand still, take anatomical damage (Sandbox.Injury) and come from STATIONS: the map's DummyStation markers
-- (attributes Kind = stand | drop | slide, Every = respawn seconds, Max) keep each area stocked. Players spawn their
-- own through the spawn menu (opts.owner). Dummies.onKill(player, model) is the kill credit.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CFG = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC"))
local RagdollService = require(ServerScriptService:WaitForChild("GojoServer"):WaitForChild("RagdollService"))
local Injury = require(script.Parent:WaitForChild("Injury"))
RagdollService.Init()

local Dummies = { onKill = nil, CAP = 64 }
local records = {}
Dummies.records = records
local count = 0
local IDLE = "rbxassetid://507766666"
local SKINS = { Color3.fromRGB(226, 226, 222), Color3.fromRGB(216, 217, 214), Color3.fromRGB(232, 231, 226) }
-- (2026-11-13) THE LOOK the owner asked for (a reference shot of a white mannequin with a stern face): Roblox's own
-- "Man" body, head and face instead of the bare blocky rig. Same R15 part names and the same constraint rig, so the
-- ragdoll, the injuries and the mutations need nothing changed. The rig is built ONCE and cloned after that - building
-- from a description fetches the assets (0.1-0.2 s measured) and can fail; if it does, the plain rig is the fallback
-- and the proper one is tried again a little later.
local LOOK = { Torso = 86500008, RightArm = 86500036, LeftArm = 86500054, LeftLeg = 86500064, RightLeg = 86500078, Head = 86498048, Face = 86487700 }
local template, plain, retryAt = nil, nil, 0
local function buildRig(look)
	local desc = Instance.new("HumanoidDescription")
	local c = SKINS[1]
	desc.HeadColor, desc.TorsoColor, desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = c, c, c, c, c, c
	if look then
		for k, v in pairs(LOOK) do
			desc[k] = v
		end
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		return rig
	end
	return nil, rig
end
local function newRig()
	if not template and os.clock() >= retryAt then
		local rig, err = buildRig(true)
		if rig then
			template = rig
		else
			retryAt = os.clock() + 20
			warn("[Dummies] could not build the mannequin rig (plain one used for now): " .. tostring(err))
		end
	end
	if not template and not plain then
		plain = buildRig(false)
	end
	local src = template or plain
	return src and src:Clone() or nil
end

local folder = workspace:FindFirstChild("NPCs")
if not folder or not folder:IsA("Model") then
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Model")
	folder.Name = "NPCs"
	folder.Parent = workspace
end
Dummies.folder = folder

function Dummies.is(model)
	return records[model] ~= nil
end
function Dummies.of(part)
	local m = part and part:FindFirstAncestorOfClass("Model")
	while m and not records[m] do
		m = m:FindFirstAncestorOfClass("Model")
	end
	return m
end
function Dummies.count()
	return count
end

function Dummies.remove(model, fade)
	local rec = records[model]
	if not rec then
		return
	end
	records[model] = nil
	count -= 1
	Injury.forget(model)
	model:SetAttribute("Retired", true)
	if fade and model.Parent then
		local info = TweenInfo.new(1)
		for _, d in ipairs(model:GetDescendants()) do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		task.delay(1.05, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	elseif model.Parent then
		model:Destroy()
	end
end

local function onDeath(rec)
	if rec.dead then
		return
	end
	rec.dead = true
	rec.diedAt = os.clock()
	local model = rec.model
	model:SetAttribute("Dead", true)
	RagdollService.Ragdoll(model, nil)
	Injury.humDied(model)
	if rec.track then
		rec.track:Stop(0.1)
	end
	local uid = model:GetAttribute("LastHitBy")
	local p = uid and Players:GetPlayerByUserId(uid)
	if p and Dummies.onKill and not rec.counted then -- (it may already have counted when it was put down: see the loop below)
		rec.counted = true
		task.spawn(Dummies.onKill, p, model)
	end
end

-- cf: where its feet go and which way it faces. opts: owner (Player), station, ragdoll (seconds), life (seconds),
-- (2026-11-15, shop perk Dummy of Anyone) desc = a HumanoidDescription to build it from (someone's avatar) + lookOf =
-- the username shown over its head
function Dummies.spawn(cf, opts)
	opts = opts or {}
	if count >= Dummies.CAP then
		return nil
	end
	local skin = SKINS[math.random(#SKINS)]
	local rig
	if typeof(opts.desc) == "Instance" and opts.desc:IsA("HumanoidDescription") then
		local ok, r = pcall(function()
			return Players:CreateHumanoidModelFromDescription(opts.desc, Enum.HumanoidRigType.R15)
		end)
		rig = ok and r or nil
	else
		rig = newRig()
	end
	if not rig then
		warn("[Dummies] could not build a rig")
		return nil
	end
	for _, n in ipairs({ "Animate", "Health" }) do
		local c = rig:FindFirstChild(n)
		if c then
			c:Destroy()
		end
	end
	if not opts.desc then -- an avatar keeps its own colours and face
		local bc = rig:FindFirstChildOfClass("BodyColors")
		if bc then
			bc:Destroy()
		end
		for _, p in ipairs(rig:GetChildren()) do
			if p:IsA("BasePart") then
				p.Color = skin
			end
		end
	else
		for _, a in ipairs(rig:GetChildren()) do -- accessories never catch on anything
			if a:IsA("Accessory") then
				for _, d in ipairs(a:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide, d.Massless, d.CanQuery = false, true, false
					end
				end
			end
		end
	end
	local head = rig:FindFirstChild("Head")
	if type(opts.lookOf) == "string" and head then
		local tag = Instance.new("BillboardGui")
		tag.Name = "LookOf"
		tag.Size = UDim2.fromOffset(160, 22)
		tag.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 70
		tag.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(255, 255, 255)
		t.TextStrokeTransparency = 0.4
		t.Text = opts.lookOf
		t.Parent = tag
		tag.Parent = head
		rig:SetAttribute("LookOf", opts.lookOf)
	end
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
	rig.Name = "Dummy"
	hum.MaxHealth = CFG.MaxHealth
	hum.Health = CFG.MaxHealth
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = 0
	local p = cf.Position
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
	local stand = Vector3.new(p.X, p.Y + hum.HipHeight + hrp.Size.Y / 2 + 0.1, p.Z)
	rig:PivotTo(CFrame.lookAt(stand, stand + look))
	CollectionService:AddTag(rig, CFG.Tag)
	rig:SetAttribute("NPC", true)
	rig:SetAttribute("Dummy", true)
	rig:SetAttribute("Ragdolled", false)
	rig:SetAttribute("Dead", false)
	if opts.owner then
		rig:SetAttribute("Owner", opts.owner.UserId)
	end
	rig.Parent = folder
	RagdollService.Setup(rig)
	local rec = { model = rig, hum = hum, hrp = hrp, owner = opts.owner, station = opts.station, born = os.clock(), life = opts.life, dead = false }
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local a = Instance.new("Animation")
	a.AnimationId = IDLE
	local okT, tr = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if okT and tr then
		tr.Looped = true
		tr.Priority = Enum.AnimationPriority.Idle
		tr:Play(0.2)
		rec.track = tr
	end
	records[rig] = rec
	count += 1
	Injury.register(rig)
	hum.Died:Connect(function()
		onDeath(rec)
	end)
	if opts.ragdoll then
		RagdollService.Ragdoll(rig, opts.ragdoll)
	end
	return rig
end

function Dummies.clearOwner(player)
	for model, rec in pairs(records) do
		if rec.owner == player then
			Dummies.remove(model, true)
		end
	end
end
function Dummies.ownerCount(player)
	local n, oldest = 0, nil
	for model, rec in pairs(records) do
		if rec.owner == player then
			n += 1
			if not oldest or rec.born < records[oldest].born then
				oldest = model
			end
		end
	end
	return n, oldest
end

-- stations
local stations = {}
local function addStation(marker)
	table.insert(stations, { marker = marker, kind = marker:GetAttribute("Kind") or "stand", every = marker:GetAttribute("Every") or 8,
		max = marker:GetAttribute("Max") or 1, alive = {}, nextAt = os.clock() }) -- (2026-11-15) filled on the first tick, not 1-5 s in: the owner wants every NPC there from the start
end
for _, m in ipairs(CollectionService:GetTagged("DummyStation")) do
	addStation(m)
end
CollectionService:GetInstanceAddedSignal("DummyStation"):Connect(addStation)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.5 then
		return
	end
	acc = 0
	local now = os.clock()
	for model, rec in pairs(records) do
		local held = model:GetAttribute("GrabbedBy") or model:GetAttribute("Strapped")
		if not model.Parent then
			records[model] = nil
			count -= 1
			Injury.forget(model)
		elseif rec.hrp.Position.Y < -90 or rec.hrp.Position.Y > 2500 then
			Dummies.remove(model, false)
		elseif not held then
			if rec.dead and now - rec.diedAt > (rec.owner and 75 or 18) then
				Dummies.remove(model, true)
			elseif rec.life and now - rec.born > rec.life then
				Dummies.remove(model, true)
			elseif model:GetAttribute("Hurt") and model:GetAttribute("Ragdolled") then
				-- (2026-11-13) hurt and down: RagdollService never stands it up again, so without this the map fills with
				-- wounded bodies and every machine post stays taken by one
				rec.downAt = rec.downAt or now
				-- (2026-11-13) the owner: "make it to where the gun upgrade works per kill quota". It DID count - on death only,
				-- and a body takes about eleven pistol hits to kill (measured). Since hurt bodies stopped getting up they are
				-- shot once, lie there and fade after 32 s still alive, so the counter never moved. A body somebody put down
				-- for good now COUNTS for them, once, as soon as it has stayed down a moment (or when it dies, if that comes
				-- first: onDeath). Bodies the map hurt by itself have no LastHitBy and count for nobody.
				if not rec.counted and now - rec.downAt >= 1.2 then
					local uid = model:GetAttribute("LastHitBy")
					local by = uid and Players:GetPlayerByUserId(uid)
					if by and Dummies.onKill then
						rec.counted = true
						task.spawn(Dummies.onKill, by, model, true)
					end
				end
				if now - rec.downAt > (rec.owner and 90 or 32) then
					Dummies.remove(model, true)
				end
			else
				rec.downAt = nil
			end
		elseif rec.downAt then
			rec.downAt = now -- being carried or strapped: the clock starts again when it is let go
		end
	end
	for _, S in ipairs(stations) do
		if S.marker.Parent then
			for i = #S.alive, 1, -1 do
				local rec = records[S.alive[i]]
				if not rec or rec.dead then
					table.remove(S.alive, i)
					S.nextAt = math.max(S.nextAt, now + S.every)
				elseif S.kind == "stand" and (rec.hrp.Position - S.marker.Position).Magnitude > 45 then
					-- (2026-11-13) blown / batted / fired far away and still alive: that frees the post (the fan, the blender
					-- and the cannon were left with nobody to work on), and the stray expires on its own
					rec.life = (now - rec.born) + 50
					table.remove(S.alive, i)
					S.nextAt = math.max(S.nextAt, now + S.every)
				elseif S.kind == "stand" and rec.downAt and now - rec.downAt > 5 then
					-- wounded on the floor at its post: a fresh one takes over, the body lies there until it is cleared
					table.remove(S.alive, i)
					S.nextAt = math.max(S.nextAt, now + S.every)
				end
			end
			if #S.alive < S.max and now >= S.nextAt and count < Dummies.CAP - 12 then
				S.nextAt = now + S.every
				local cf = S.marker.CFrame
				local m
				if S.kind == "stand" then
					m = Dummies.spawn(cf, { station = S })
				else
					m = Dummies.spawn(cf, { station = S, ragdoll = 2.5, life = 26 })
				end
				if m then
					table.insert(S.alive, m)
				end
			end
		end
	end
end)

return Dummies
