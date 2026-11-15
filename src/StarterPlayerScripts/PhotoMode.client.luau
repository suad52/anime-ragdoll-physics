--!nocheck
-- StarterPlayerScripts.PhotoMode (2026-11-15, shop perk "Free Cam / Photo Mode": HudShared.PerkCatalog PhotoMode).
-- P (or the PHOTO tile on the HUD rail, or the shop's MANAGE) flies the camera free of the character: every HUD and
-- Roblox's own menus hide, my character holds still where it is, and the camera goes anywhere within RANGE studs.
--   WASD / stick  fly (camera-relative)      E / Space  up      Q / Ctrl  down      Shift  fast      Alt  slow
--   hold right mouse (or drag on a touch screen)  look round      wheel / + -  zoom (field of view)
--   F  depth of field (the centre sharp, the rest soft)      H  hide this bar      P / Esc  back to the game
-- Without the perk the tile and P open the shop. Only this screen changes: nobody else sees a thing.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local PERK = "Perk_PhotoMode"
local RANGE = 900
local SPEED, FAST, SLOW = 26, 80, 7
local C = Color3.fromRGB
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function corner(o, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

-- the bar at the bottom while flying
local gui = new("ScreenGui", { Name = "PhotoMode", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 80, Enabled = false }, playerGui)
local barFrame = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(TOUCH and 520 or 760, 44),
	BackgroundColor3 = C(16, 16, 22), BackgroundTransparency = 0.25, BorderSizePixel = 0 }, gui)
corner(barFrame, 12)
new("UIStroke", { Color = C(255, 196, 110), Thickness = 1.5, Transparency = 0.3 }, barFrame)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -230, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = C(235, 235, 245), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	Text = TOUCH and "PHOTO MODE  ·  stick: fly  ·  drag: look  ·  arrows: up / down" or "PHOTO MODE  ·  WASD fly  ·  E/Q up/down  ·  Shift fast  ·  right-drag look  ·  wheel zoom  ·  F focus  ·  H hide" }, barFrame)
local function button(text, x, w, color)
	local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(w, 30), Text = text, Font = Enum.Font.GothamBlack,
		TextSize = 13, TextColor3 = C(20, 18, 26), BackgroundColor3 = color, AutoButtonColor = true, BorderSizePixel = 0 }, barFrame)
	corner(b, 8)
	return b
end
local exitB = button("EXIT", -8, 64, C(255, 120, 110))
local focusB = button("FOCUS", -78, 70, C(255, 196, 110))
local zoomOut = button("-", -154, 30, C(200, 210, 230))
local zoomIn = button("+", -190, 30, C(200, 210, 230))
local upB, downB
if TOUCH then
	upB = new("TextButton", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -130), Size = UDim2.fromOffset(64, 64), Text = "▲", Font = Enum.Font.GothamBlack,
		TextSize = 26, TextColor3 = C(255, 255, 255), BackgroundColor3 = C(16, 16, 22), BackgroundTransparency = 0.3, BorderSizePixel = 0 }, gui)
	corner(upB, 32)
	downB = upB:Clone()
	downB.Text = "▼"
	downB.Position = UDim2.new(1, -24, 1, -60)
	downB.Parent = gui
end

local on = false
local saved = {}
local camCF, yaw, pitch, fov = nil, 0, 0, 70
local vel = Vector3.zero
local touchUp, touchDown = false, false
local dof
local looking = false

local function root()
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end

local function toast(msg)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Photo Mode", Text = msg, Duration = 3 })
	end)
end

local function setOn(want)
	if want == on then
		return
	end
	local cam = workspace.CurrentCamera
	if want then
		if player:GetAttribute(PERK) ~= true then
			local op = ReplicatedStorage:FindFirstChild("HudShared") and ReplicatedStorage.HudShared:FindFirstChild("OpenPanel")
			if op then
				op:Fire("shop")
			end
			toast("Free Cam / Photo Mode is in the SHOP (PERKS)")
			return
		end
		local hrp, hum = root()
		if not hrp or not hum or hum.Health <= 0 then
			return
		end
		on = true
		saved = { camType = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView, guis = {}, core = {}, mouse = UserInputService.MouseBehavior,
			icon = UserInputService.MouseIconEnabled, anchored = hrp.Anchored, hrp = hrp }
		for _, g in ipairs(playerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				g.Enabled = false
				table.insert(saved.guis, g)
			end
		end
		for _, t in ipairs({ Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }) do
			local okG, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
			if okG and was then
				saved.core[t] = true
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
			end
		end
		hrp.Anchored = true -- my body holds still while the camera is away (only on this client)
		camCF = cam.CFrame
		local look = camCF.LookVector
		yaw = math.atan2(-look.X, -look.Z)
		pitch = math.asin(math.clamp(look.Y, -1, 1))
		fov = cam.FieldOfView
		vel = Vector3.zero
		cam.CameraType = Enum.CameraType.Scriptable
		gui.Enabled = true
		barFrame.Visible = true
	else
		on = false
		gui.Enabled = false
		if dof then
			dof:Destroy()
			dof = nil
		end
		looking = false
		UserInputService.MouseBehavior = saved.mouse or Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = saved.icon ~= false
		for _, g in ipairs(saved.guis or {}) do
			if g.Parent then
				g.Enabled = true
			end
		end
		for t in pairs(saved.core or {}) do
			pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true)
		end
		if saved.hrp and saved.hrp.Parent then
			saved.hrp.Anchored = saved.anchored == true
		end
		cam.FieldOfView = saved.fov or 70
		cam.CameraType = saved.camType or Enum.CameraType.Custom
		local _, hum = root()
		cam.CameraSubject = hum or saved.subject
		saved = {}
	end
end

local function toggleDof()
	if dof then
		dof:Destroy()
		dof = nil
		focusB.BackgroundColor3 = C(255, 196, 110)
	else
		dof = new("DepthOfFieldEffect", { Name = "PhotoModeFocus", FarIntensity = 0.75, NearIntensity = 0.6, FocusDistance = 18, InFocusRadius = 14 }, Lighting)
		focusB.BackgroundColor3 = C(120, 240, 160)
	end
end

exitB.Activated:Connect(function()
	setOn(false)
end)
focusB.Activated:Connect(toggleDof)
zoomIn.Activated:Connect(function()
	fov = math.clamp(fov - 8, 8, 110)
end)
zoomOut.Activated:Connect(function()
	fov = math.clamp(fov + 8, 8, 110)
end)
if upB then
	upB.MouseButton1Down:Connect(function() touchUp = true end)
	upB.MouseButton1Up:Connect(function() touchUp = false end)
	downB.MouseButton1Down:Connect(function() touchDown = true end)
	downB.MouseButton1Up:Connect(function() touchDown = false end)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.P and not processed then
		setOn(not on)
		return
	end
	if not on then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		setOn(false)
	elseif input.KeyCode == Enum.KeyCode.F and not processed then
		toggleDof()
	elseif input.KeyCode == Enum.KeyCode.H and not processed then
		barFrame.Visible = not barFrame.Visible
	elseif (input.KeyCode == Enum.KeyCode.Equals or input.KeyCode == Enum.KeyCode.KeypadPlus) and not processed then
		fov = math.clamp(fov - 6, 8, 110)
	elseif (input.KeyCode == Enum.KeyCode.Minus or input.KeyCode == Enum.KeyCode.KeypadMinus) and not processed then
		fov = math.clamp(fov + 6, 8, 110)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		looking = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and on then
		looking = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)
UserInputService.InputChanged:Connect(function(input, processed)
	if not on then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement and looking then
		yaw -= input.Delta.X * 0.0045
		pitch = math.clamp(pitch - input.Delta.Y * 0.0045, -1.45, 1.45)
	elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
		yaw -= input.Delta.X * 0.006
		pitch = math.clamp(pitch - input.Delta.Y * 0.006, -1.45, 1.45)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		fov = math.clamp(fov - input.Position.Z * 4, 8, 110)
	end
end)

local function key(k)
	return UserInputService:IsKeyDown(k)
end
RunService:BindToRenderStep("PhotoModeCam", Enum.RenderPriority.Camera.Value + 5, function(dt)
	if not on then
		return
	end
	local cam = workspace.CurrentCamera
	local hrp, hum = root()
	if not hrp or not hum or hum.Health <= 0 then
		setOn(false)
		return
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local move = Vector3.zero
	if key(Enum.KeyCode.W) then move += Vector3.new(0, 0, -1) end
	if key(Enum.KeyCode.S) then move += Vector3.new(0, 0, 1) end
	if key(Enum.KeyCode.A) then move += Vector3.new(-1, 0, 0) end
	if key(Enum.KeyCode.D) then move += Vector3.new(1, 0, 0) end
	local world = rot:VectorToWorldSpace(move)
	-- a stick: the humanoid still reads it as a camera-relative direction (the body is anchored)
	if move.Magnitude < 0.01 and hum.MoveDirection.Magnitude > 0.05 then
		local md = hum.MoveDirection
		local flatLook = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
		local fwd = md:Dot(flatLook)
		world = rot.LookVector * fwd + (md - flatLook * fwd)
	end
	if key(Enum.KeyCode.E) or key(Enum.KeyCode.Space) or touchUp then world += Vector3.yAxis end
	if key(Enum.KeyCode.Q) or key(Enum.KeyCode.LeftControl) or touchDown then world -= Vector3.yAxis end
	local speed = (key(Enum.KeyCode.LeftShift) and FAST) or (key(Enum.KeyCode.LeftAlt) and SLOW) or SPEED
	local want = world.Magnitude > 0.01 and world.Unit * speed or Vector3.zero
	vel = vel:Lerp(want, 1 - math.exp(-dt * 8))
	local pos = camCF.Position + vel * dt
	local off = pos - hrp.Position
	if off.Magnitude > RANGE then
		pos = hrp.Position + off.Unit * RANGE
	end
	camCF = CFrame.new(pos) * rot
	cam.CFrame = camCF
	cam.FieldOfView += (fov - cam.FieldOfView) * (1 - math.exp(-dt * 10))
	if dof then
		local hit = workspace:Raycast(camCF.Position, camCF.LookVector * 400)
		local d = hit and (hit.Position - camCF.Position).Magnitude or 120
		dof.FocusDistance += (d - dof.FocusDistance) * (1 - math.exp(-dt * 6))
		dof.InFocusRadius = math.clamp(d * 0.35, 4, 40)
	end
end)

player.CharacterAdded:Connect(function()
	if on then
		setOn(false)
	end
end)

-- the tile on the HUD rail: a pill in CharacterSelect's top strip (StarterPlayerScripts.HudRails moves it into the rail)
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b = new("TextButton", { Name = "PhotoPill", LayoutOrder = 9, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = C(20, 20, 28), BackgroundTransparency = 0.22, BorderSizePixel = 0 })
	corner(b, 20)
	new("UIStroke", { Color = C(255, 255, 255), Thickness = 1.5, Transparency = 0.55 }, b)
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1 }, b)
	local body = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.9, 0.62),
		BackgroundColor3 = C(255, 240, 200), BorderSizePixel = 0 }, icon)
	corner(body, 3)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), Size = UDim2.fromScale(0.36, 0.36), BackgroundColor3 = C(20, 20, 28),
		BorderSizePixel = 0, ZIndex = 2 }, icon)
	b.Activated:Connect(function()
		setOn(not on)
	end)
	if not strip then
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(0, 14, 0.8, 0)
	end
	b.Parent = strip or gui
end)

-- the shop's MANAGE on the perk
local hs = ReplicatedStorage:WaitForChild("HudShared", 30)
local op = hs and hs:FindFirstChild("OpenPanel")
if op then
	op.Event:Connect(function(name)
		if name == "photo" then
			setOn(true)
		end
	end)
end

-- Studio: script.Control:Invoke("on" | "off" | "state")
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd)
		if cmd == "on" then
			setOn(true)
		elseif cmd == "off" then
			setOn(false)
		end
		local cam = workspace.CurrentCamera
		local hrp = root()
		return { on = on, camType = cam.CameraType.Name, camPos = cam.CFrame.Position, anchored = hrp and hrp.Anchored, hidden = saved.guis and #saved.guis or 0, fov = cam.FieldOfView }
	end
	ctl.Parent = script
end
