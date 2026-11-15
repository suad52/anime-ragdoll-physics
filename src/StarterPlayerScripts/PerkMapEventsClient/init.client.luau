--!nocheck
-- StarterPlayerScripts.PerkMapEventsClient (2026-11-15, shop EVENTS): how the events of ServerScriptService.PerkMapEvents
-- look - and what they do to MY character, which only this client can move (the server cannot push a client-owned body).
-- Each running event is a marker Part in workspace.MapEvents (attributes Kind, Id, Area, T0, Ends, AreaC, AreaH and its
-- own; Over = it is ending). A ModuleScript child per Kind:
--   M.start(c, marker) -> state     build its look (local parts in workspace.MapEventsFX)
--   M.step(c, S, marker, dt)        every frame: move the look, act on my character (only while I am on that map)
--   M.stop(c, S, marker)            fade out and clean up (called once, when Over is set or the marker goes)
--   M.fx[kind](c, data)             one-shot effects from PerkShared.Remotes.MapEventFX
-- c is the helper table below. Camera shake obeys Settings (player attribute OptNoShake).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")
local events = workspace:WaitForChild("MapEvents", 60)
if not events then
	warn("[PerkMapEventsClient] no workspace.MapEvents")
	return
end

local c = { player = player, UP = Vector3.yAxis, FLAT = Vector3.new(1, 0, 1), rng = Random.new() }
local fxFolder = workspace:FindFirstChild("MapEventsFX")
if not fxFolder then
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "MapEventsFX"
	fxFolder.Parent = workspace
end
c.folder = fxFolder
c.Debris, c.TweenService, c.Lighting = Debris, TweenService, Lighting

function c.now()
	return workspace:GetServerTimeNow()
end
function c.root()
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid"), ch
end
-- am I (a position) on this event's map
function c.onMap(m, pos, margin)
	local ac, ah = m:GetAttribute("AreaC"), m:GetAttribute("AreaH")
	if not ac or not ah or typeof(pos) ~= "Vector3" then
		return false
	end
	margin = margin or 30
	return math.abs(pos.X - ac.X) <= ah.X + margin and math.abs(pos.Z - ac.Z) <= ah.Z + margin
end
function c.part(o)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(o or {}) do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = (o and o.Parent) or fxFolder
	return p
end
function c.tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
function c.emitter(parent, o)
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture or "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = o.rate or 0
	e.Lifetime = o.life or NumberRange.new(1, 1.5)
	e.Speed = o.speed or NumberRange.new(4, 8)
	e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Size = o.size or NumberSequence.new(2, 4)
	e.Transparency = o.tr or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Color = o.color or ColorSequence.new(Color3.fromRGB(200, 200, 205))
	e.LightEmission = o.light or 0
	e.LightInfluence = o.influence or 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = o.rot or NumberRange.new(-40, 40)
	e.Acceleration = o.accel or Vector3.zero
	e.Drag = o.drag or 0
	if o.dir then
		e.EmissionDirection = o.dir
	end
	if o.shape then
		e.Shape = o.shape
		e.ShapeInOut = o.inout or Enum.ParticleEmitterShapeInOut.Outward
		e.ShapeStyle = o.style or Enum.ParticleEmitterShapeStyle.Volume
	end
	e.Parent = parent
	return e
end
function c.sound(id, parent, vol, speed, looped, maxDist)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.Looped = looped == true
	s.RollOffMinDistance, s.RollOffMaxDistance, s.RollOffMode = 20, maxDist or 260, Enum.RollOffMode.InverseTapered
	s.Parent = parent or fxFolder
	s:Play()
	if not looped then
		Debris:AddItem(s, 8)
	end
	return s
end
function c.soundAt(id, pos, vol, speed, maxDist)
	local a = c.part({ Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(pos) })
	c.sound(id, a, vol, speed, false, maxDist)
	Debris:AddItem(a, 8)
end
c.SND = { boom = "rbxassetid://138533090376585", whoosh = "rbxassetid://9120972444", flow = "rbxassetid://9120551511",
	drone = "rbxassetid://9114353273", swell = "rbxassetid://9043337370", hit = "rbxassetid://126976659766267", crack = "rbxassetid://9114592102" }
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = true
function c.ground(x, z, fromY)
	local list = { fxFolder, events }
	for _, n in ipairs({ "NPCs", "Gore", "PerkFXLocal", "GadgetFX", "Arrows" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local y = fromY or 300
	local hit = workspace:Raycast(Vector3.new(x, y, z), Vector3.new(0, -(y + 120), 0), groundParams)
	return hit and hit.Position or Vector3.new(x, 0, z)
end

-- camera shake: the strongest request of the frame wins; kicks decay
local shakeWant, kick = 0, 0
function c.shake(power)
	shakeWant = math.max(shakeWant, power)
end
function c.kick(power)
	kick = math.max(kick, power)
end
RunService:BindToRenderStep("MapEventShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	local p = math.max(shakeWant, kick)
	shakeWant = 0
	kick = math.max(0, kick - dt * 2.2)
	if p < 0.01 or player:GetAttribute("OptNoShake") then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local t = os.clock()
	local n1, n2, n3 = math.noise(t * 18, 1.7), math.noise(t * 18, 5.3), math.noise(t * 14, 9.1)
	cam.CFrame = cam.CFrame * CFrame.new(n1 * p * 0.9, n2 * p * 0.7, 0) * CFrame.Angles(n2 * p * 0.02, n3 * p * 0.02, n1 * p * 0.03)
end)

-- a tumble of my own body (as PerkFXClient's "Knock"): PlatformStand for `secs`, then up again
local tumbleUntil, tumbleMine = 0, false
function c.tumble(vel, secs)
	local hrp, hum, ch = c.root()
	if not hum or hum.Health <= 0 or typeof(vel) ~= "Vector3" or vel ~= vel then
		return
	end
	if ch:GetAttribute("Guardian") or ch:GetAttribute("Morphed") then
		vel *= 0.25
		secs = 0
	end
	if (secs or 0) > 0 then
		if not hum.PlatformStand then
			hum.PlatformStand = true
			tumbleMine = true
		end
		tumbleUntil = math.max(tumbleUntil, os.clock() + math.min(secs, 2.5))
	end
	local done = {}
	for _, p in ipairs(ch:GetDescendants()) do
		if p:IsA("BasePart") and not p.Anchored then
			local r = p.AssemblyRootPart
			if r and not r.Anchored and not done[r] then
				done[r] = true
				r:ApplyImpulse((vel - r.AssemblyLinearVelocity * 0.7) * r.AssemblyMass)
				r:ApplyAngularImpulse(Vector3.new(c.rng:NextNumber(-1, 1), c.rng:NextNumber(-1, 1), c.rng:NextNumber(-1, 1)) * 6 * r.AssemblyMass)
			end
		end
	end
end
function c.tumbling()
	return os.clock() < tumbleUntil
end
RunService.Heartbeat:Connect(function()
	if tumbleUntil > 0 and os.clock() >= tumbleUntil then
		tumbleUntil = 0
		local _, hum = c.root()
		if tumbleMine and hum and hum.Health > 0 then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		tumbleMine = false
	end
end)
player.CharacterAdded:Connect(function()
	tumbleUntil, tumbleMine = 0, false
end)

-- a jump press (for swimming up)
c.jumpAt = 0
UserInputService.JumpRequest:Connect(function()
	c.jumpAt = os.clock()
end)

-- a ColorCorrection this script owns, blended from every event's request each frame
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "MapEventGrade"
grade.Enabled = false
grade.Parent = Lighting
local gradeWant
function c.grade(tint, bright, contrast, sat, k)
	if k <= 0.01 then
		return
	end
	if not gradeWant or k > gradeWant.k then
		gradeWant = { tint = tint, bright = bright, contrast = contrast, sat = sat, k = k }
	end
end
local gradeK = 0
local gradeLast

---------------------------------------------------------------------------------------------------------------------
local MODS = {}
for _, m in ipairs(script:GetChildren()) do
	if m:IsA("ModuleScript") then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			MODS[m.Name] = res
		else
			warn("[PerkMapEventsClient] " .. m.Name .. ": " .. tostring(res))
		end
	end
end

local live = {} -- [marker] = { mod, S, stopped }
local function begin(m)
	if live[m] or not m:IsA("BasePart") then
		return
	end
	local kind = m:GetAttribute("Kind")
	local t0 = os.clock()
	while not kind and os.clock() - t0 < 3 do -- attributes can land a beat after the part
		task.wait()
		kind = m:GetAttribute("Kind")
	end
	local M = kind and MODS[kind]
	if not M or not M.start or m:GetAttribute("Over") or not m.Parent then
		return
	end
	local ok, S = pcall(M.start, c, m)
	if not ok then
		warn("[PerkMapEventsClient] " .. kind .. " start: " .. tostring(S))
		return
	end
	live[m] = { mod = M, S = S or {}, kind = kind }
end
local function finish(m)
	local L = live[m]
	if not L or L.stopped then
		return
	end
	L.stopped = true
	if L.mod.stop then
		local ok, err = pcall(L.mod.stop, c, L.S, m)
		if not ok then
			warn("[PerkMapEventsClient] " .. L.kind .. " stop: " .. tostring(err))
		end
	end
end
for _, m in ipairs(events:GetChildren()) do
	task.spawn(begin, m)
end
events.ChildAdded:Connect(function(m)
	task.spawn(begin, m)
end)
events.ChildRemoved:Connect(function(m)
	finish(m)
	live[m] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	gradeWant = nil
	for m, L in pairs(live) do
		if not L.stopped then
			if m:GetAttribute("Over") or not m.Parent then
				finish(m)
			elseif L.mod.step then
				local ok, err = pcall(L.mod.step, c, L.S, m, dt)
				if not ok and not L.warned then
					L.warned = true
					warn("[PerkMapEventsClient] " .. L.kind .. " step: " .. tostring(err))
				end
			end
		end
	end
	local target = gradeWant and gradeWant.k or 0
	gradeK += (target - gradeK) * (1 - math.exp(-dt * 2.5))
	if gradeWant then
		gradeLast = gradeWant
	end
	if gradeK > 0.01 and gradeLast then
		grade.Enabled = true
		grade.TintColor = Color3.new(1, 1, 1):Lerp(gradeLast.tint, gradeK)
		grade.Brightness = gradeLast.bright * gradeK
		grade.Contrast = gradeLast.contrast * gradeK
		grade.Saturation = gradeLast.sat * gradeK
	else
		grade.Enabled = false
	end
end)

local FX = Remotes:WaitForChild("MapEventFX", 60)
if FX then
	FX.OnClientEvent:Connect(function(kind, data)
		for name, M in pairs(MODS) do
			local f = M.fx and M.fx[kind]
			if f then
				local ok, err = pcall(f, c, data or {})
				if not ok then
					warn("[PerkMapEventsClient] " .. name .. "." .. kind .. ": " .. tostring(err))
				end
			end
		end
	end)
end

-- Studio: script.Debug:Invoke("state") -> what is running here and my character's state
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "Debug"
	dbg.OnInvoke = function(cmd)
		local out = { live = {}, parts = #fxFolder:GetDescendants(), tumbling = c.tumbling() }
		for m, L in pairs(live) do
			table.insert(out.live, { kind = L.kind, stopped = L.stopped, info = L.S.info })
		end
		local hrp, hum = c.root()
		if hrp then
			out.pos, out.vel, out.floor, out.state = hrp.Position, hrp.AssemblyLinearVelocity, hum.FloorMaterial.Name, hum:GetState().Name
		end
		out.grade = grade.Enabled and gradeK or 0
		return out
	end
	dbg.Parent = script
end
