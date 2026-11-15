--!nocheck
-- StarterPlayerScripts.GuardClient (2026-11-11, combat rework): the client side of BLOCK, GUARD BREAK and BREAKOUT.
--   KEY     hold the BLOCK action of HudShared.Keybinds (Z by default, rebindable in SETTINGS > CONTROLS) or the round
--           BLOCK button on touch screens: tells ServerScriptService.GuardService ("block", true / false). Pressing an
--           attack (M1, the move keys Q E R F G X) drops the guard first; hold the key again to raise it (the
--           server also drops it when an M1 is thrown). Walking is slowed to Balance.BLOCK_MOVE_MUL while the guard is up.
--   POSE    every character with Blocking = true (players and NPCs, within 160 studs) holds a forearms-up guard through
--           GojoShared.Client.ProceduralAnimator (upper body only, so the run / walk legs keep going).
--   HUD     a GUARD bar bottom-left while my guard is up or not full; "GUARD BROKEN" while it is broken; a
--           BREAKOUT prompt while I'm stunned / down and it is ready, else its cooldown.
--   BREAKOUT (2026-11-14, the dash was removed - owner: "remove dashing from this game"): it rode the dash key, so it
--           is the BLOCK key / the touch BLOCK button now - pressed while I can't act it asks GuardService for a
--           breakout instead of raising the guard.
--   FX      PvPShared.GuardFX from the server: "block" (a spark + clink at the blocker), "break" (a shatter, a
--           GUARD BREAK pop-up), "breakout" (a ring burst out to its radius).
-- The rules themselves (what a block stops, the guard meter, the break) are server-side: ServerScriptService.PvP.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local hud = ReplicatedStorage:WaitForChild("HudShared")
local pvpShared = ReplicatedStorage:WaitForChild("PvPShared")
local Kits = require(hud:WaitForChild("Kits"))
local Keybinds = require(hud:WaitForChild("Keybinds"))
local BAL = require(pvpShared:WaitForChild("Balance"))
local Animator = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
local Guard = pvpShared:WaitForChild("Guard")
local GuardFX = pvpShared:WaitForChild("GuardFX")
local InputMode = nil
pcall(function()
	InputMode = require(hud:WaitForChild("InputMode", 10))
end)

local K = Enum.KeyCode
local BLOCK_KEY = K.Z -- the BLOCK action (Keybinds names actions by their default key)
local ATTACK_KEYS = { [K.Q] = true, [K.E] = true, [K.R] = true, [K.F] = true, [K.G] = true, [K.X] = true }
local GUARD_MAX = tonumber(BAL.GUARD_MAX) or 100
local MOVE_MUL = tonumber(BAL.BLOCK_MOVE_MUL) or 0.35
local INK, WHITE = Kits.INK, Kits.WHITE
local STEEL = Color3.fromRGB(150, 205, 255)
local SND_HIT = "rbxassetid://126976659766267"
local SND_BREAK = "rbxassetid://79476956608476"
local SND_WHOOSH = "rbxassetid://9120972444"

local function now()
	return workspace:GetServerTimeNow()
end

local function myChar()
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then
		return c, h, c:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- the key
local held = false -- the BLOCK input is down
local sent = false -- what we last told the server
local function send(on)
	if sent ~= on then
		sent = on
		Guard:FireServer("block", on)
	end
end
local function press(on)
	held = on
	send(on)
end
local function dropForAttack()
	if sent then
		held = false
		send(false)
	end
end
-- stunned / tumbling / guard-broken / down: the BLOCK input is a breakout request instead (the old dash rule)
local function cantAct()
	local c, h = myChar()
	if not c then
		return false
	end
	if c:GetAttribute("SuperArmor") or c:GetAttribute("Guardian") or c:GetAttribute("AscForm") == "Instinct" or c:GetAttribute("Morphed") then
		return false
	end
	local t = now()
	return (tonumber(c:GetAttribute("StunnedUntil")) or 0) > t or c:GetAttribute("Ragdolled") == true
		or (tonumber(c:GetAttribute("DownUntil")) or 0) > t or h.PlatformStand
end
local function blockOrBreakout()
	if cantAct() then
		Guard:FireServer("breakout")
	else
		press(true)
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if player:GetAttribute("KeybindCapture") then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and not gpe then
		dropForAttack()
		return
	end
	if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local l = Keybinds.logical(input.KeyCode)
	if l == BLOCK_KEY then
		blockOrBreakout()
	elseif ATTACK_KEYS[l] then
		dropForAttack()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard and Keybinds.logical(input.KeyCode) == BLOCK_KEY then
		press(false)
	end
end)
-- the server took the guard (a guard break, a swing): hold the key again to raise it
local function watchMine(c)
	sent = false
	held = false
	c:GetAttributeChangedSignal("Blocking"):Connect(function()
		if c:GetAttribute("Blocking") ~= true and sent then
			sent = false
			held = false
		end
	end)
end
player.CharacterAdded:Connect(watchMine)
if player.Character then
	watchMine(player.Character)
end

-- walking slowed while the guard is up (after the control scripts and the punch root, which run at Input + 1)
RunService:BindToRenderStep("GuardMove", Enum.RenderPriority.Input.Value + 2, function()
	local c, h = myChar()
	if c and c:GetAttribute("Blocking") == true then
		h:Move(h.MoveDirection * MOVE_MUL, false)
	end
end)

---------------------------------------------------------------------------------------------------
-- the guard pose (forearms crossed up in front of the face), on every blocking body near me
-- (solved on the stock R15 rig in a playtest: both fists 1.07 studs in front of the root plane at chin height, 0.43
-- apart - head at y 1.21. Mirror rule: the left side flips Y and Z.)
local POSE = {
	Waist = { 10, 0, 0 },
	Neck = { -8, 0, 0 },
	RightShoulder = { 90, 45, -30 },
	RightElbow = { 35, 0, 0 },
	RightWrist = { 0, 0, 0 },
	LeftShoulder = { 90, -45, 30 },
	LeftElbow = { 35, 0, 0 },
	LeftWrist = { 0, 0, 0 },
}
local CLIP = { length = 3600, fadeIn = 0.08, fadeOut = 0, keys = { { t = 0, pose = POSE }, { t = 3600, pose = POSE } } }
local tracks = setmetatable({}, { __mode = "k" })

local function inRange(m)
	local cam = workspace.CurrentCamera
	local r = m:FindFirstChild("HumanoidRootPart")
	return cam and r and (cam.CFrame.Position - r.Position).Magnitude < 160
end
local function refreshPose(m)
	local on = m.Parent ~= nil and m:GetAttribute("Blocking") == true and m:GetAttribute("Ragdolled") ~= true and inRange(m)
	local tr = tracks[m]
	if on and not (tr and tr:isPlaying()) then
		tracks[m] = Animator.play(m, CLIP)
	elseif not on and tr then
		tracks[m] = nil
		tr:stop(0.15)
	end
end
local watched = setmetatable({}, { __mode = "k" })
local function watch(m)
	if watched[m] or not m:IsA("Model") then
		return
	end
	watched[m] = true
	m:GetAttributeChangedSignal("Blocking"):Connect(function()
		refreshPose(m)
	end)
	m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		refreshPose(m)
	end)
	refreshPose(m)
end
for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
	watch(m)
end
CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(watch)
local function hookPlayer(p)
	p.CharacterAdded:Connect(watch)
	if p.Character then
		watch(p.Character)
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)
-- a body that walks into range while already blocking
task.spawn(function()
	while true do
		task.wait(0.5)
		for m in pairs(watched) do
			if m.Parent and m:GetAttribute("Blocking") == true then
				refreshPose(m)
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- HUD: the guard bar and the breakout prompt, bottom-left (where the dash gauge was until 2026-11-14)
local gui = Instance.new("ScreenGui")
gui.Name = "GuardHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local touch = UserInputService.TouchEnabled
-- the bar's bottom edge: just over SandboxClient's key strip (PlayerGui.KeyRowLift), or clear of the thumbstick on touch
local function baseY()
	if touch then
		return -230
	end
	return -18 - (tonumber(gui.Parent:GetAttribute("KeyRowLift")) or 0)
end
local BASE_Y = baseY()
local frame = new("Frame", { Name = "Guard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, BASE_Y), Size = UDim2.fromOffset(210, 26),
	BackgroundColor3 = Kits.PANEL, BackgroundTransparency = 0.15, BorderSizePixel = 0, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
local stroke = new("UIStroke", { Color = INK, Thickness = 2 }, frame)
local label = new("TextLabel", { Position = UDim2.fromOffset(8, 3), Size = UDim2.fromOffset(62, 20), BackgroundTransparency = 1, Text = "GUARD",
	TextScaled = true, FontFace = Kits.FONT_PUNCH, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left }, frame)
new("UIStroke", { Color = INK, Thickness = 1.5 }, label)
local back = new("Frame", { Position = UDim2.fromOffset(74, 7), Size = UDim2.new(1, -82, 0, 12), BackgroundColor3 = INK, BorderSizePixel = 0 }, frame)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, back)
local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = STEEL, BorderSizePixel = 0 }, back)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, fill)

local prompt = new("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, BASE_Y - 30), Size = UDim2.fromOffset(210, 22),
	BackgroundTransparency = 1, Text = "", TextScaled = true, FontFace = Kits.FONT_PUNCH, TextColor3 = Color3.fromRGB(255, 214, 70),
	TextXAlignment = Enum.TextXAlignment.Left, Visible = false }, gui)
new("UIStroke", { Color = INK, Thickness = 2 }, prompt)
gui.Parent:GetAttributeChangedSignal("KeyRowLift"):Connect(function()
	BASE_Y = baseY()
	frame.Position = UDim2.new(0, 18, 1, BASE_Y)
	prompt.Position = UDim2.new(0, 18, 1, BASE_Y - 30)
end)

-- touch: a hold-to-block button on the bottom row, just right of the thumbstick (where the DASH button was)
local touchBtn
if touch then
	touchBtn = new("TextButton", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 117, 1, -18), Size = UDim2.fromOffset(64, 64), Text = "BLOCK",
		TextScaled = true, FontFace = Kits.FONT_PUNCH, TextColor3 = INK, BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, AutoButtonColor = true }, gui)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, touchBtn)
	new("UIStroke", { Color = INK, Thickness = 2 }, touchBtn)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, touchBtn)
	touchBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			blockOrBreakout()
		end
	end)
	touchBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			press(false)
		end
	end)
	-- read where Roblox put the thumbstick (it slides in when the controls first show, so wait until its right edge has
	-- held still for 1.5 s) and sit 14 px right of it; only a spot in the left part of the screen is trusted
	task.spawn(function()
		local tg = player.PlayerGui:WaitForChild("TouchGui", 15)
		local stick = tg and tg:WaitForChild("TouchControlFrame", 5) and (tg:FindFirstChild("ThumbstickStart", true) or tg:FindFirstChild("ThumbstickFrame", true))
		if not stick then
			return
		end
		local edge, since, t0 = nil, os.clock(), os.clock()
		while os.clock() - t0 < 10 do
			task.wait(0.25)
			local x = stick.AbsolutePosition.X + stick.AbsoluteSize.X
			if x ~= edge then
				edge, since = x, os.clock()
			elseif os.clock() - since >= 1.5 then
				break
			end
		end
		local cam = workspace.CurrentCamera
		if edge and edge > 0 and cam and edge < cam.ViewportSize.X * 0.3 then
			touchBtn.Position = UDim2.new(0, math.floor(edge + 14), 1, -18)
		end
	end)
end

local shownBreak = 0
RunService.RenderStepped:Connect(function()
	local c = myChar()
	gui.Enabled = c ~= nil and player:GetAttribute("StarterPicked") ~= false
	if not c then
		return
	end
	local t = now()
	local g = tonumber(c:GetAttribute("Guard")) or GUARD_MAX
	local broken = (tonumber(c:GetAttribute("GuardBrokenUntil")) or 0) > t
	local blocking = c:GetAttribute("Blocking") == true
	frame.Visible = blocking or broken or g < GUARD_MAX - 0.5
	fill.Size = UDim2.fromScale(math.clamp(g / GUARD_MAX, 0, 1), 1)
	fill.BackgroundColor3 = broken and Color3.fromRGB(255, 80, 80) or (g < GUARD_MAX * 0.3 and Color3.fromRGB(255, 170, 70) or STEEL)
	label.Text = broken and "BROKEN" or "GUARD"
	stroke.Color = blocking and STEEL or INK
	if touchBtn then
		touchBtn.BackgroundTransparency = blocking and 0 or 0.25
	end
	-- the breakout prompt while I can't act
	local stunned = (tonumber(c:GetAttribute("StunnedUntil")) or 0) > t or c:GetAttribute("Ragdolled") == true
		or (tonumber(c:GetAttribute("DownUntil")) or 0) > t
	local ready = (tonumber(player:GetAttribute("BreakoutReadyAt")) or 0) - t
	if stunned then
		prompt.Visible = true
		if ready <= 0 then
			prompt.Text = touch and "TAP BLOCK: BREAK OUT" or ("[" .. Keybinds.label(BLOCK_KEY) .. "] BREAK OUT")
			prompt.TextColor3 = Color3.fromRGB(255, 214, 70)
		else
			prompt.Text = string.format("BREAKOUT %.1fs", ready)
			prompt.TextColor3 = Color3.fromRGB(200, 200, 210)
		end
	elseif t - shownBreak < 0.8 then
		prompt.Visible = true
	else
		prompt.Visible = false
	end
end)

Guard.OnClientEvent:Connect(function(kind, ok, why)
	if kind == "breakout" and not ok and why == "cooldown" then
		shownBreak = now()
	end
end)

---------------------------------------------------------------------------------------------------
-- FX
local function fxFolder()
	local f = workspace:FindFirstChild("LocalFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "LocalFX"
		f.Parent = workspace
	end
	return f
end
local function neon(size, color, cf, shape)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Shape = shape or Enum.PartType.Block
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = fxFolder()
	return p
end
local function sound(id, pos, vol, pitch)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.Transparency = true, false, false, false, 1
	a.Size = Vector3.one * 0.2
	a.CFrame = CFrame.new(pos)
	a.Parent = fxFolder()
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = 140
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 2)
end
local function near(pos, d)
	local cam = workspace.CurrentCamera
	return cam and (cam.CFrame.Position - pos).Magnitude < d
end

local function frontOf(model, pos)
	local r = model and model:FindFirstChild("HumanoidRootPart")
	if r then
		return r.Position + r.CFrame.LookVector * 1.4 + Vector3.yAxis * 1.2, r.CFrame
	end
	return pos + Vector3.yAxis, CFrame.new(pos)
end

local function sparks(at, color, n, len)
	for _ = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5)
		dir = dir.Magnitude > 1e-3 and dir.Unit or Vector3.yAxis
		local s = neon(Vector3.new(0.12, 0.12, len), color, CFrame.lookAt(at, at + dir) * CFrame.new(0, 0, -len / 2))
		TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Transparency = 1, CFrame = s.CFrame * CFrame.new(0, 0, -len * 0.8),
			Size = Vector3.new(0.03, 0.03, len * 0.4) }):Play()
		Debris:AddItem(s, 0.25)
	end
end

local function popup(model, text, color)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(220, 46), StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0), AlwaysOnTop = true,
		Adornee = head, MaxDistance = 160 }, fxFolder())
	local tl = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, TextScaled = true,
		FontFace = Kits.FONT_PUNCH, TextColor3 = color }, bb)
	local st = new("UIStroke", { Color = INK, Thickness = 3 }, tl)
	local sc = new("UIScale", { Scale = 1.5 }, tl)
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(0.6, function()
		TweenService:Create(tl, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(st, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(bb, TweenInfo.new(0.3), { StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0) }):Play()
	end)
	Debris:AddItem(bb, 1)
end

GuardFX.OnClientEvent:Connect(function(kind, model, pos, extra)
	if typeof(pos) ~= "Vector3" or not near(pos, 200) then
		return
	end
	if kind == "block" then
		local at, cf = frontOf(model, pos)
		sparks(at, STEEL:Lerp(WHITE, 0.4), 7, 1.2)
		local disc = neon(Vector3.new(0.1, 2.6, 2.6), STEEL, cf * CFrame.new(0, 1.2, -1.4) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		disc.Transparency = 0.35
		TweenService:Create(disc, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(0.05, 3.6, 3.6) }):Play()
		Debris:AddItem(disc, 0.2)
		sound(SND_HIT, at, 0.55, 1.7)
	elseif kind == "break" then
		local at = frontOf(model, pos)
		sparks(at, Color3.fromRGB(255, 120, 90), 16, 2.2)
		for i = 1, 6 do
			local a = math.rad(i * 60 + math.random(-15, 15))
			local off = Vector3.new(math.cos(a), math.random() * 0.8, math.sin(a))
			local shard = neon(Vector3.new(0.5, 0.9, 0.08), STEEL, CFrame.new(at) * CFrame.Angles(math.random() * 6, math.random() * 6, 0))
			TweenService:Create(shard, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = CFrame.new(at + off * 3.5) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
				Transparency = 1 }):Play()
			Debris:AddItem(shard, 0.5)
		end
		if typeof(model) == "Instance" then
			popup(model, "GUARD BREAK", Color3.fromRGB(255, 110, 90))
		end
		sound(SND_BREAK, at, 0.9, 0.75)
	elseif kind == "breakout" then
		local R = tonumber(extra) or 12
		local ring = neon(Vector3.new(0.4, 2, 2), WHITE, CFrame.new(pos - Vector3.yAxis * 1.5) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
		ring.Transparency = 0.2
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, R * 2, R * 2), Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.4)
		sparks(pos, Color3.fromRGB(255, 230, 150), 10, 2.5)
		if typeof(model) == "Instance" then
			popup(model, "BREAKOUT", Color3.fromRGB(255, 214, 70))
		end
		sound(SND_WHOOSH, pos, 0.8, 0.8)
	end
end)
