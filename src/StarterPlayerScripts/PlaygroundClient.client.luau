--!nocheck
-- PlaygroundClient: local visuals for the playground props (fan blades, conveyor stripes, burning bodies, splashes),
-- sound/VFX for the server's prop cues, and the player-side physics of the props (players never ragdoll, but they
-- still bounce on trampolines, ride launch pads, get pushed by the fan and hop off lava).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("GojoShared")
local AbilityEvent = Shared:WaitForChild("Remotes"):WaitForChild("AbilityEvent")
local VFX = require(Shared:WaitForChild("Client"):WaitForChild("PurpleVFX"))
local NPC_TAG = require(Shared:WaitForChild("Config"):WaitForChild("NPC")).Tag

local SOUNDS = {
	Boing = "rbxassetid://125984645781295",
	Cannon = "rbxassetid://72411732778781",
	Boom = "rbxassetid://127224055692526",
	Splash = "rbxassetid://9125703162",
	Fuse = "rbxassetid://109965479398415",
	Sizzle = "rbxassetid://8927189937",
	Smack = "rbxassetid://126976659766267",
	Thud = "rbxassetid://79476956608476",
	Whoosh = "rbxassetid://9120972444",
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "PlaygroundFX"
fxFolder.Parent = workspace

local function sfx(id, pos, volume, speed)
	VFX.sound(id, VFX.anchor(fxFolder, pos, 6), volume or 0.8, speed or 1)
end

-- a little camera shake for big nearby events (offset after the camera module, never accumulates)
local shakeAmp, shakeT0, shakeDur = 0, 0, 0
local function shakeAt(pos, amount, dur)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	local cam = workspace.CurrentCamera
	local d = (cam.CFrame.Position - pos).Magnitude
	local k = math.clamp(1 - d / 140, 0, 1)
	if k > 0 then
		shakeAmp, shakeT0, shakeDur = math.max(shakeAmp * 0.5, amount * k), os.clock(), dur
	end
end
RunService:BindToRenderStep("PlaygroundShake", Enum.RenderPriority.Camera.Value + 2, function()
	local cam = workspace.CurrentCamera
	local x = os.clock() - shakeT0
	if shakeAmp <= 0 or x > shakeDur or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local a = shakeAmp * (1 - x / shakeDur) ^ 2
	local t = os.clock() * 24
	cam.CFrame = cam.CFrame * CFrame.new(math.noise(t, 0.3) * a, math.noise(0.7, t) * a, 0) * CFrame.Angles(0, 0, math.noise(t, 2.1) * a * 0.04)
end)

local function floatingText(pos, text, color)
	local host = VFX.anchor(fxFolder, pos, 2.2)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 60)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Parent = host
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = color
	l.Parent = bb
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = Color3.fromRGB(20, 10, 30)
	st.Parent = l
	TweenService:Create(bb, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4), { TextTransparency = 1 }):Play()
	TweenService:Create(st, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4), { Transparency = 1 }):Play()
end

local padTweening = {}
local function squash(pad)
	if typeof(pad) ~= "Instance" or not pad:IsA("BasePart") or padTweening[pad] then
		return
	end
	padTweening[pad] = true
	local base = pad.CFrame
	local down = TweenService:Create(pad, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = base - Vector3.new(0, 0.45, 0) })
	down:Play()
	down.Completed:Wait()
	local up = TweenService:Create(pad, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = base })
	up:Play()
	up.Completed:Wait()
	padTweening[pad] = nil
end

---------------------------------------------------------------------------------------------------
-- server prop cues
AbilityEvent.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" or typeof(data.pos) ~= "Vector3" then
		return
	end
	local pos = data.pos
	if kind == "PropBoing" then
		sfx(SOUNDS.Boing, pos, 0.6, 0.9 + math.random() * 0.3)
		task.spawn(squash, data.pad)
	elseif kind == "PropLaunch" then
		if not data.quiet then
			sfx(SOUNDS.Whoosh, pos, 0.9, 0.7)
			VFX.dust(fxFolder, pos, 4, 8)
			VFX.burst(fxFolder, pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 235, 170), 14, 0.8, 30)
		end
	elseif kind == "PropFuse" then
		sfx(SOUNDS.Fuse, pos, 0.8, 1)
		for i = 0, 5 do
			task.delay(i * 0.13, function()
				VFX.burst(fxFolder, pos, Color3.fromRGB(255, 200, 90), 6, 0.5, 10)
			end)
		end
	elseif kind == "PropCannon" then
		sfx(SOUNDS.Cannon, pos, 1, 1)
		VFX.flash(fxFolder, pos, 7, Color3.fromRGB(255, 220, 150), 0.3)
		VFX.dust(fxFolder, pos, 6, 14)
		shakeAt(pos, 0.9, 0.45)
	elseif kind == "PropExplode" then
		local r = tonumber(data.radius) or 20
		sfx(SOUNDS.Boom, pos, 1, 0.95 + math.random() * 0.1)
		VFX.flash(fxFolder, pos, r * 0.7, Color3.fromRGB(255, 170, 70), 0.45)
		VFX.burst(fxFolder, pos, Color3.fromRGB(255, 150, 60), 40, 2.2, 60)
		VFX.dust(fxFolder, pos, r * 0.35, 16)
		VFX.shockwave(fxFolder, pos - Vector3.new(0, 1, 0), Vector3.yAxis, 4, r * 2.2, Color3.fromRGB(255, 160, 80), 0.5)
		shakeAt(pos, 1.6, 0.6)
	elseif kind == "PropSizzle" then
		sfx(SOUNDS.Sizzle, pos, 0.5, 1.2)
		VFX.burst(fxFolder, pos, Color3.fromRGB(255, 120, 40), 8, 0.8, 12)
	elseif kind == "PropSmack" then
		sfx(SOUNDS.Smack, pos, data.big and 1 or 0.7, data.big and 0.8 or 1)
		VFX.burst(fxFolder, pos, Color3.fromRGB(255, 250, 225), data.big and 24 or 14, data.big and 1.4 or 1, data.big and 40 or 28)
		shakeAt(pos, data.big and 0.7 or 0.35, 0.3)
	elseif kind == "PropThud" then
		sfx(SOUNDS.Thud, pos, data.hard and 0.9 or 0.6, data.hard and 0.8 or 1)
		VFX.dust(fxFolder, pos, data.hard and 4 or 2.5, data.hard and 10 or 5)
	elseif kind == "PropBowling" then
		local n = tonumber(data.count) or 0
		floatingText(pos, n >= 10 and "STRIKE!" or (n .. " PINS"), n >= 10 and Color3.fromRGB(255, 220, 60) or Color3.new(1, 1, 1))
	elseif kind == "PropRespawn" then
		VFX.burst(fxFolder, pos, Color3.fromRGB(255, 240, 200), 8, 0.6, 8)
	end
end)

---------------------------------------------------------------------------------------------------
-- local animation: fan blades and conveyor stripes (the server never moves them)
local fans = {}
local function addFan(fm)
	local blades = fm:FindFirstChild("Blades")
	local hub = blades and blades:FindFirstChild("Hub")
	if hub then
		fans[fm] = { blades = blades, pivot = blades:GetPivot(), angle = 0 }
	end
end
local belts = {}
local function addBelt(belt)
	local model = belt.Parent
	local stripes = model and model:FindFirstChild("Stripes")
	if stripes then
		local list = {}
		for _, p in ipairs(stripes:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(list, { part = p, local0 = belt.CFrame:ToObjectSpace(p.CFrame) })
			end
		end
		belts[belt] = { list = list, offset = 0 }
	end
end

---------------------------------------------------------------------------------------------------
-- burning bodies (lava) and splashes (pool)
local burning = {}
local function pool()
	local pg = workspace:FindFirstChild("Playground")
	return pg and pg:FindFirstChild("Pool")
end
local poolBox
local lastY = {}

local function updateBodies()
	local nowServer = workspace:GetServerTimeNow()
	if not poolBox then
		local p = pool()
		if p then
			local cf, size = p:GetBoundingBox()
			poolBox = { min = cf.Position - size / 2, max = cf.Position + size / 2, surface = 2.5 }
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		local t = m:FindFirstChild("UpperTorso")
		if t then
			local hot = (m:GetAttribute("Burning") or 0) > nowServer
			local e = burning[m]
			if hot and not e then
				e = Instance.new("ParticleEmitter")
				e.Name = "BurnFx"
				e.Texture = "rbxasset://textures/particles/fire_main.dds"
				e.Color = ColorSequence.new(Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 60, 20))
				e.LightEmission = 1
				e.Size = NumberSequence.new(2.2, 0.2)
				e.Lifetime = NumberRange.new(0.4, 0.8)
				e.Speed = NumberRange.new(4, 8)
				e.Rate = 40
				e.EmissionDirection = Enum.NormalId.Top
				e.Parent = t
				burning[m] = e
			elseif not hot and e then
				e.Enabled = false
				Debris:AddItem(e, 1)
				burning[m] = nil
			end
			if poolBox then
				local p = t.Position
				local inside = p.X > poolBox.min.X and p.X < poolBox.max.X and p.Z > poolBox.min.Z and p.Z < poolBox.max.Z
				local prev = lastY[m]
				if inside and prev and prev > poolBox.surface and p.Y <= poolBox.surface then
					local speed = t.AssemblyLinearVelocity.Magnitude
					sfx(SOUNDS.Splash, p, math.clamp(speed / 120, 0.4, 1), 1 - math.clamp(speed / 600, 0, 0.3))
					local host = VFX.anchor(fxFolder, Vector3.new(p.X, poolBox.surface, p.Z), 3)
					local s = Instance.new("ParticleEmitter")
					s.Texture = "rbxasset://textures/particles/smoke_main.dds"
					s.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
					s.LightInfluence = 1
					s.Size = NumberSequence.new(1.5, 3.5)
					s.Transparency = NumberSequence.new(0.2, 1)
					s.Lifetime = NumberRange.new(0.5, 0.9)
					s.Speed = NumberRange.new(12, 26)
					s.SpreadAngle = Vector2.new(30, 30)
					s.Acceleration = Vector3.new(0, -60, 0)
					s.EmissionDirection = Enum.NormalId.Top
					s.Rate = 0
					s.Parent = host
					s:Emit(math.clamp(math.floor(speed / 8), 8, 30))
				end
				lastY[m] = p.Y
			end
		end
	end
	for m, e in pairs(burning) do
		if not m.Parent then
			burning[m] = nil
		end
	end
	for m in pairs(lastY) do
		if not m.Parent then
			lastY[m] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the local player on the props
local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude
local lastBounce, lastPad, lastLava = 0, 0, 0

local function inBox(part, p)
	local l = part.CFrame:PointToObjectSpace(p)
	local h = part.Size / 2
	return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
end

local function updatePlayer(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	downParams.FilterDescendantsInstances = { char, fxFolder }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(hum.HipHeight + hrp.Size.Y / 2 + 1.2), 0), downParams)
	local part = hit and hit.Instance
	local t = os.clock()
	local v = hrp.AssemblyLinearVelocity
	if part and CollectionService:HasTag(part, "Trampoline") and v.Y < 5 and t - lastBounce > 0.3 then
		lastBounce = t
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, (part:GetAttribute("Bounce") or 150) * 0.75, v.Z)
		sfx(SOUNDS.Boing, part.Position, 0.6, 1.1)
		task.spawn(squash, part)
	elseif part and CollectionService:HasTag(part, "LaunchPad") and t - lastPad > 1 then
		lastPad = t
		local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
		local dir = look.Magnitude > 0.01 and look.Unit or Vector3.zero
		hrp.AssemblyLinearVelocity = dir * (part:GetAttribute("Power") or 100) * 0.8 + Vector3.yAxis * (part:GetAttribute("Up") or 100) * 0.7
		sfx(SOUNDS.Whoosh, part.Position, 0.9, 0.7)
	elseif part and CollectionService:HasTag(part, "Lava") and t - lastLava > 0.6 then
		lastLava = t
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, 45, v.Z)
		sfx(SOUNDS.Sizzle, hrp.Position, 0.5, 1.3)
	end
	for _, fm in ipairs(CollectionService:GetTagged("WindFan")) do
		local zone = fm:FindFirstChild("WindZone")
		if zone and inBox(zone, hrp.Position) then
			local dir = zone.CFrame.LookVector
			hrp.AssemblyLinearVelocity += (dir * (fm:GetAttribute("Force") or 300) * 0.35 + Vector3.yAxis * 30) * dt
		end
	end
end

---------------------------------------------------------------------------------------------------
task.spawn(function()
	local pg = workspace:WaitForChild("Playground", 30)
	if not pg then
		return
	end
	task.wait(1)
	for _, fm in ipairs(CollectionService:GetTagged("WindFan")) do
		addFan(fm)
	end
	for _, belt in ipairs(CollectionService:GetTagged("Conveyor")) do
		addBelt(belt)
	end
end)

local bodyAcc = 0
RunService.Heartbeat:Connect(function(dt)
	for fm, f in pairs(fans) do
		if f.blades.Parent then
			f.angle = (f.angle + dt * 12) % (math.pi * 2)
			f.blades:PivotTo(f.pivot * CFrame.Angles(f.angle, 0, 0))
		else
			fans[fm] = nil
		end
	end
	for belt, b in pairs(belts) do
		if belt.Parent then
			local speed = belt:GetAttribute("Speed") or 16
			local len = belt.Size.Z
			b.offset = (b.offset + speed * dt) % 3.3
			for _, s in ipairs(b.list) do
				local z = s.local0.Position.Z - b.offset
				if z < -len / 2 then
					z += len
				end
				s.part.CFrame = belt.CFrame * CFrame.new(s.local0.Position.X, s.local0.Position.Y, z)
			end
		else
			belts[belt] = nil
		end
	end
	local ok, err = pcall(updatePlayer, dt)
	if not ok then
		warn("[PlaygroundClient] " .. tostring(err))
	end
	bodyAcc += dt
	if bodyAcc > 1 / 30 then
		bodyAcc = 0
		pcall(updateBodies)
	end
end)
