--!nocheck
-- StarterPlayerScripts.ShiftLock (2026-11-11, owner: "add shiftlock (camera view)" and "have the option to have
-- keybinds"): this game's own shift lock. Roblox's built-in one is switched off (StarterPlayer.EnableMouseLockOption =
-- false): Dash used to move it from Shift to Ctrl by rewriting the PlayerModule's MouseLockSwitchAction bindings, which
-- no player could rebind, had no button on a phone, and kept the mouse locked while the shop / settings / emote wheel
-- were open, so their buttons couldn't be clicked.
--   TOGGLE  the SHIFT LOCK action of HudShared.Keybinds (LCTRL by default - RCTRL too while it is; rebindable in
--           SETTINGS > CONTROLS), the round LOCK button on touch screens (right side, beside the EMOTE button), or the
--           switch in SETTINGS > CONTROLS. The state is the LocalPlayer attribute OptShiftLock (true / nil, local only,
--           off by default); SettingsMenu's switch reads and writes the same attribute.
--   ON      the mouse is held at the screen centre under a crosshair (MouseBehavior = LockCenter every frame, after
--           the camera scripts), the camera sits 1.75 studs over the right shoulder (Humanoid.CameraOffset, eased in
--           and out) and the body turns with the camera.
--   PAUSED  free mouse, normal turning, the offset eased away - while dead, ragdolled (Ragdolled / Physics /
--           PlatformStand / FallingDown; Goku's flight is NOT a ragdoll), seated, in a giant form (Morphed /
--           TitanForm), in a scripted camera (ultimate cut-ins), or while any full-screen panel is up (shop,
--           inventory, starter offer, settings, taunts, emote wheel, roll reveal, starter pick, death screen, the
--           character list, Roblox's own menu) so every menu stays clickable. Panels are found generically: each of
--           them opens over a full-screen shade BUTTON, so any shown GuiButton covering the screen pauses the lock.
-- TURNING: the Humanoid turns the body (UserGameSettings.RotationType = CameraRelative - what Roblox's own shift lock
-- does), NOT AutoRotate = false + writing the root's CFrame: eight kit clients (Godspeed, OneForAll, Zangetsu, Gomu,
-- Tempest, Carver, Shifter, Ascendant) put AutoRotate back to true on every frame a move isn't holding the body, so
-- turning it off here would be undone every frame and the two would fight. With CameraRelative a kit that sets
-- AutoRotate = false to face a move's target simply wins for that move, and the camera turn is back the moment it
-- lets go. (If the engine ever refuses the RotationType write, the root is turned by hand instead - and still only
-- while the kit leaves AutoRotate on.)
-- OFFSET: only CameraOffset's X / Z are written here (kits lift Y for giant forms), along the CAMERA's right (the
-- offset is in the root's space, so a body facing elsewhere mid-move would otherwise swing the camera), and they are
-- given up the moment anything else writes them (a titan's shoulder shift, Susanoo's lift tween).
-- Goku's flight descends on LCTRL (AscendantKit.Config.DescendKeys): while flying, those keys don't toggle the lock.
-- Studio: script.Control:Invoke("set", bool) / ("state") -> JSON. The LocalPlayer attribute ShiftLockState mirrors
-- it for tests: "off" / "on" / "paused: <why>".
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local Keybinds = require(shared:WaitForChild("Keybinds"))
local InputMode = nil
pcall(function()
	InputMode = require(shared:WaitForChild("InputMode", 10))
end)

local K = Enum.KeyCode
local ACTION = K.LeftShift -- (2026-11-15, owner: default to left shift, not Ctrl) the SHIFT LOCK action (Keybinds names every action by its default key)
local ATTR = "OptShiftLock"
local CAPTURE = "KeybindCapture" -- SettingsMenu sets it while it waits for a key to bind
local OFFSET = 1.75 -- studs over the right shoulder
local EASE = 14 -- 1/s: how fast the offset eases in and out
local RESUME_DELAY = 0.12 -- s a pause must be over before the mouse locks again (no flicker on a one-frame stumble)
local CROSSHAIR = "rbxasset://textures/MouseLockedCursor.png" -- Roblox's own shift-lock cursor
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Kits.WHITE
local ON_C = Color3.fromRGB(90, 200, 255)

local function isOn()
	return player:GetAttribute(ATTR) == true
end
local function setOn(v)
	player:SetAttribute(ATTR, v and true or nil)
end
local function isTouch()
	return InputMode ~= nil and InputMode.isTouch() == true
end

local function flying(char)
	if char:GetAttribute("Flying") then
		return true
	end
	-- the client starts flying (Physics state + this AlignOrientation) a beat before the server's Flying arrives
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp ~= nil and hrp:FindFirstChild("AscFlightAlign") ~= nil
end

-- Goku's descend keys: while flying, a press of one of them belongs to the flight
local DESCEND = {}
task.spawn(function()
	pcall(function()
		local kit = ReplicatedStorage:WaitForChild("AscendantKit", 30)
		local cfg = kit and require(kit:WaitForChild("Config", 10))
		for _, k in ipairs((type(cfg) == "table" and cfg.DescendKeys) or {}) do
			DESCEND[k] = true
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- THE KEY
local function isToggleKey(kc)
	local l = Keybinds.logical(kc)
	if l == ACTION then
		return true
	end
	-- RCTRL is a spare toggle while SHIFT LOCK sits on its default key and nothing else was bound to RCTRL
	return kc == K.RightControl and l == kc and Keybinds.physical(ACTION) == ACTION
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard or player:GetAttribute(CAPTURE) then
		return
	end
	if not isToggleKey(input.KeyCode) then
		return
	end
	local char = player.Character
	if char and DESCEND[input.KeyCode] and flying(char) then
		return -- that key is taking Goku down
	end
	setOn(not isOn())
end)

---------------------------------------------------------------------------------------------------------------------
-- FULL-SCREEN PANELS: every menu in this game opens over a full-screen shade button (ShopShade, InventoryShade,
-- StarterOfferShade, SettingsShade, TauntShade, the emote wheel's Modal Backdrop, RollReveal's shade), so a SHOWN
-- GuiButton that covers its whole ScreenGui means a menu is open. Collected once as they appear (cheap per frame).
local shades = setmetatable({}, { __mode = "k" })
local function consider(d)
	if not d:IsA("GuiButton") then
		return
	end
	local function check()
		if d.Size.X.Scale >= 0.9 and d.Size.Y.Scale >= 0.9 then
			shades[d] = true
		else
			shades[d] = nil
		end
	end
	check()
	d:GetPropertyChangedSignal("Size"):Connect(check)
end
playerGui.DescendantAdded:Connect(consider)
task.spawn(function()
	for i, d in ipairs(playerGui:GetDescendants()) do
		consider(d)
		if i % 4000 == 0 then
			task.wait()
		end
	end
end)

-- the ScreenGui if o is actually on screen (its gui enabled, it and every GuiObject above it Visible), else nil
local function shown(o)
	local sg = o:FindFirstAncestorOfClass("ScreenGui")
	if not sg or not sg.Enabled or sg.Parent ~= playerGui then
		return nil
	end
	local x = o
	while x ~= sg do
		if not x then
			return nil
		end
		if x:IsA("GuiObject") and not x.Visible then
			return nil
		end
		x = x.Parent
	end
	return sg
end

local function enabledGui(name)
	local g = playerGui:FindFirstChild(name)
	return g ~= nil and g:IsA("ScreenGui") and g.Enabled
end

local function panelReason()
	if GuiService.MenuIsOpen then
		return "roblox menu"
	end
	if player:GetAttribute("StarterPicked") == false then
		return "starter pick"
	end
	for b in pairs(shades) do
		if b.Parent then
			local sg = shown(b)
			if sg then
				local a, s = b.AbsoluteSize, sg.AbsoluteSize
				if a.X >= s.X * 0.85 and a.Y >= s.Y * 0.85 then
					return "panel " .. b.Name
				end
			end
		end
	end
	-- the CHARACTER dropdown under the top strip is a list you click, not a shade
	local cs = playerGui:FindFirstChild("CharacterSelect")
	local drop = cs and cs:FindFirstChild("Characters")
	if drop and drop:IsA("GuiObject") and shown(drop) then
		return "character list"
	end
	local ss = playerGui:FindFirstChild("StarterSelect")
	local bd = ss and ss:FindFirstChild("Backdrop")
	if bd and bd:IsA("GuiObject") and shown(bd) then
		return "starter pick"
	end
	if enabledGui("RollReveal") then
		return "roll reveal"
	end
	if enabledGui("DeathScreen") then
		return "death screen"
	end
	return nil
end

local STATES = {
	[Enum.HumanoidStateType.Dead] = "dead",
	[Enum.HumanoidStateType.Physics] = "ragdoll",
	[Enum.HumanoidStateType.Ragdoll] = "ragdoll",
	[Enum.HumanoidStateType.FallingDown] = "ragdoll",
	[Enum.HumanoidStateType.PlatformStanding] = "ragdoll",
	[Enum.HumanoidStateType.Seated] = "seated",
}

local function pauseReason(char, hum, cam)
	if not char or not hum or not hum.RootPart then
		return "no character"
	end
	if hum.Health <= 0 then
		return "dead"
	end
	if char:GetAttribute("Ragdolled") or hum.PlatformStand then
		return "ragdoll"
	end
	local st = hum:GetState()
	if STATES[st] and not (st == Enum.HumanoidStateType.Physics and flying(char)) then
		return STATES[st]
	end
	if hum.Sit or hum.SeatPart then
		return "seated"
	end
	if char:GetAttribute("Morphed") or char:GetAttribute("TitanForm") then
		return "giant form"
	end
	if not cam or cam.CameraType ~= Enum.CameraType.Custom then
		return "scripted camera"
	end
	local subj = cam.CameraSubject
	if subj ~= hum and not (subj and subj:IsDescendantOf(char)) then
		return "scripted camera"
	end
	return panelReason()
end

---------------------------------------------------------------------------------------------------------------------
-- THE TOUCH BUTTON (phones / tablets: no key) + the touch crosshair (a mouse gets the cursor icon instead). Same inset
-- gui as the EMOTE button so the two line up: it sits right of it (EMOTE spans 150-210 px in from the right edge),
-- above the jump button (its top is 210 px up on a tablet, 90 on a phone) and left of the gadget column (the right
-- 62 px), so it covers none of them; the MoveDock is bottom-centre and the DASH button bottom-left.
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local tgui = new("ScreenGui", { Name = "ShiftLockButton", ResetOnSpawn = false, DisplayOrder = 5 }, playerGui)
-- (not IgnoreGuiInset: this gui's centre is the 3D view's centre, which is where LockCenter holds the mouse)
local crosshair = new("ImageLabel", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(28, 28), BackgroundTransparency = 1, Image = CROSSHAIR, Visible = false }, tgui)
local btn = new("TextButton", { Name = "Toggle", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -84, 1, -230), Size = UDim2.fromOffset(52, 52),
	Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(28, 22, 44), BackgroundTransparency = 0.1, Visible = false }, tgui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)
local btnStroke = new("UIStroke", { Color = WHITE, Thickness = 2.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
local btnIcon = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1, Image = CROSSHAIR }, btn)
local btnCap = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.79), Size = UDim2.fromScale(0.78, 0.24),
	BackgroundTransparency = 1, Text = "LOCK", TextScaled = true, FontFace = Kits.FONT_PUNCH, TextColor3 = WHITE }, btn)
btn.Activated:Connect(function()
	setOn(not isOn())
end)
-- (2026-11-14) never under the sandbox's top-right panel (PlayerGui.HudTopRightY, real px from the top of the screen,
-- published by SandboxClient): on a landscape phone this bottom-anchored spot is up at the top, under the NEXT panel.
-- Pushed down just enough (the EMOTE button beside it does the same); tablets and PCs keep the old spot.
local function clearTop()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local inset = GuiService:GetGuiInset().Y
	local h = cam.ViewportSize.Y - inset
	local minTop = (tonumber(playerGui:GetAttribute("HudTopRightY")) or 0) - inset + 6
	local push = math.max(0, minTop - (h - 230 - 52))
	btn.Position = UDim2.new(1, -84, 1, -230 + push)
end
clearTop()
playerGui:GetAttributeChangedSignal("HudTopRightY"):Connect(clearTop)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(clearTop)
end
local function showButton()
	local on = isOn()
	btn.Visible = isTouch()
	btn.BackgroundColor3 = on and Color3.fromRGB(26, 64, 104) or Color3.fromRGB(28, 22, 44)
	btnStroke.Color = on and ON_C or WHITE
	btnStroke.Transparency = on and 0 or 0.35
	btnIcon.ImageColor3 = on and ON_C or WHITE
	btnCap.TextColor3 = on and ON_C or WHITE
end
showButton()
player:GetAttributeChangedSignal(ATTR):Connect(showButton)
if InputMode then
	InputMode.changed(showButton)
end

---------------------------------------------------------------------------------------------------------------------
-- EVERY FRAME
local active, reason, clearSince = false, "off", nil
local offX, wroteHum, lastCo, holdUntil = 0, nil, nil, 0
local rotOwned, rotFailed = false, false
local mouseHeld, savedIcon, lastState = false, nil, nil

local function setRotation(want)
	if want then
		if not rotFailed and UserGameSettings.RotationType ~= Enum.RotationType.CameraRelative then
			local ok = pcall(function()
				UserGameSettings.RotationType = Enum.RotationType.CameraRelative
			end)
			rotFailed = not ok
		end
		rotOwned = true
	elseif rotOwned then
		rotOwned = false
		pcall(function()
			UserGameSettings.RotationType = Enum.RotationType.MovementRelative
		end)
	end
end

-- before the camera scripts (so this frame's camera already uses this frame's offset): on / paused, turning, offset
RunService:BindToRenderStep("ShiftLockPre", Enum.RenderPriority.Camera.Value - 1, function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = hum and hum.RootPart
	local cam = workspace.CurrentCamera
	local now = os.clock()
	local why = "off"
	if isOn() then
		why = pauseReason(char, hum, cam) -- nil = nothing in the way
	end
	if why then
		active, clearSince, reason = false, nil, why
	elseif not active then
		clearSince = clearSince or now
		if now - clearSince >= RESUME_DELAY then
			active = true
		end
	end

	-- turning
	setRotation(active)
	if active and rotFailed and hum.AutoRotate then
		local look = cam.CFrame.LookVector * FLAT
		if look.Magnitude > 1e-3 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look)
		end
	end

	-- the shoulder offset (X / Z only, along the camera's right)
	if hum ~= wroteHum then
		offX, wroteHum, lastCo = 0, hum, nil -- a new body
	end
	if hum and hrp and cam then
		local co = hum.CameraOffset
		if lastCo and co ~= lastCo then
			-- something else wrote CameraOffset since last frame (a titan's shoulder shift, a giant form's lift tween - a
			-- tween writes all three axes): it's theirs until it has been left alone for a moment
			offX, holdUntil = 0, now + 0.3
		end
		if now >= holdUntil then
			-- (review fix) no shoulder offset in first person - the eye would sit beside the head (Roblox's own lock does the same)
			local fp = (cam.CFrame.Position - cam.Focus.Position).Magnitude < 1
			local target = (active and not fp) and OFFSET or 0
			if target > 0 or offX > 0 then -- (eased all the way out = hands off: nothing is written at 0)
				offX += (target - offX) * (1 - math.exp(-EASE * dt))
				if math.abs(target - offX) < 0.01 then
					offX = target
				end
				local loc = Vector3.zero
				local right = cam.CFrame.RightVector * FLAT
				if offX > 0 and right.Magnitude > 1e-3 then
					loc = hrp.CFrame:VectorToObjectSpace(right.Unit * offX)
				end
				hum.CameraOffset = Vector3.new(loc.X, co.Y, loc.Z)
			end
		end
		lastCo = hum.CameraOffset
	end
end)

-- after the camera scripts (they restore the mouse when THEY are done with it): the mouse, the cursor, the state
RunService:BindToRenderStep("ShiftLockMouse", Enum.RenderPriority.Camera.Value + 1, function()
	local touch = isTouch()
	if active and not touch then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		if UserInputService.MouseIcon ~= CROSSHAIR then
			savedIcon = UserInputService.MouseIcon
			UserInputService.MouseIcon = CROSSHAIR
		end
		mouseHeld = true
	elseif mouseHeld then
		-- set Default even if the camera scripts swapped in LockCurrentPosition (right-drag) meanwhile: they saved OUR
		-- LockCenter as the thing to restore, and would lock the mouse again on release
		mouseHeld = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if UserInputService.MouseIcon == CROSSHAIR then
			UserInputService.MouseIcon = savedIcon or ""
		end
		savedIcon = nil
	end
	crosshair.Visible = active and touch
	local s = (not isOn() and "off") or (active and "on") or ("paused: " .. tostring(reason))
	if s ~= lastState then
		lastState = s
		player:SetAttribute("ShiftLockState", s)
	end
end)

-- Studio test hook
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a)
		if cmd == "set" then
			setOn(a == true)
			return true
		elseif cmd == "state" then
			return HttpService:JSONEncode({ on = isOn(), active = active, reason = reason, offset = offX,
				rotation = UserGameSettings.RotationType.Name, mouse = UserInputService.MouseBehavior.Name, rotFailed = rotFailed,
				key = Keybinds.label(ACTION), touch = isTouch() })
		end
		return nil
	end
	ctl.Parent = script
end
