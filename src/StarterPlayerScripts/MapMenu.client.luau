--!nocheck
-- StarterPlayerScripts.MapMenu (2026-11-14, owner: "add a button on the left that give people the option to switch
-- between maps"): the MAPS pill (CharacterSelect's top strip; HudRails makes it the MAPS tile on the left rail, under
-- QUESTS) opens a panel with one card per map. GO fires ReplicatedStorage.MapSwitch(mapId); the server
-- (ServerScriptService.MapSwitch) moves the character and keeps the choice as player attribute Map.
-- Studio: script.Control:Invoke("open" | "close" | "go", mapId)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local remote = ReplicatedStorage:WaitForChild("MapSwitch")

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local GREEN = Color3.fromRGB(90, 230, 140)
local SOFT = Color3.fromRGB(200, 200, 225)
local ROWC = Color3.fromRGB(30, 28, 48)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local C = Color3.fromRGB

local MAPS = {
	{ id = "Ruins", name = "THE RUINS", sub = "A walled arena: ruined columns, a waterfall cliff, a training yard" },
	{ id = "Sandbox", name = "SANDBOX", sub = "The open test ground: machines, beasts, the lab" },
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, p)
end
local function stroke(p, color, th, tr)
	return new("UIStroke", { Color = color or INK, Thickness = th or 1.5, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, Text = "", FontFace = Kits.FONT_PUNCH }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function inkText(t, th)
	new("UIStroke", { Color = INK, Thickness = th or 1.5 }, t)
	return t
end
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function rect(parent, x, y, w, h, color, z, r)
	local f = new("Frame", { Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = z or 5 }, parent)
	if r then
		corner(f, r)
	end
	return f
end

-- a small drawn picture of each map (no images to upload)
local PREVIEW = {
	Sandbox = function(box)
		rect(box, 0, 0.62, 1, 0.38, C(60, 168, 72), 5)
		rect(box, 0.1, 0.18, 0.1, 0.46, C(210, 206, 196), 6) -- the tower
		rect(box, 0.09, 0.14, 0.12, 0.06, C(170, 166, 158), 7)
		rect(box, 0.36, 0.1, 0.04, 0.54, C(60, 64, 76), 6) -- the slide's tower
		for i = 0, 3 do
			rect(box, 0.3 + (i % 2) * 0.08, 0.16 + i * 0.12, 0.14, 0.05, C(220, 50, 50), 7, 3)
		end
		rect(box, 0.56, 0.38, 0.22, 0.26, C(70, 84, 82), 6) -- the press
		rect(box, 0.54, 0.34, 0.26, 0.06, C(40, 46, 52), 7)
		rect(box, 0.84, 0.5, 0.08, 0.14, C(255, 200, 60), 6) -- the crane
		rect(box, 0.16, 0.72, 0.06, 0.06, C(230, 60, 60), 7, 20)
		rect(box, 0.7, 0.76, 0.06, 0.06, C(230, 60, 60), 7, 20)
	end,
	Ruins = function(box)
		rect(box, 0, 0.5, 1, 0.5, C(60, 150, 60), 5)
		rect(box, 0, 0.36, 1, 0.16, C(150, 132, 146), 6) -- the wall
		for i = 0, 5 do
			rect(box, 0.02 + i * 0.19, 0.3, 0.05, 0.22, C(86, 90, 112), 7)
		end
		rect(box, 0.62, 0.28, 0.38, 0.3, C(92, 100, 128), 8) -- the cliff
		rect(box, 0.62, 0.25, 0.38, 0.05, C(60, 150, 60), 9)
		rect(box, 0.76, 0.3, 0.06, 0.3, C(110, 170, 240), 9) -- the waterfall
		rect(box, 0.66, 0.62, 0.3, 0.12, C(54, 128, 214), 6, 6) -- the pool
		for _, x in ipairs({ 0.1, 0.24, 0.4 }) do -- columns
			rect(box, x, 0.46, 0.05, 0.36, C(214, 212, 206), 8)
			rect(box, x - 0.01, 0.44, 0.07, 0.03, C(180, 178, 172), 9)
		end
		rect(box, 0.5, 0.82, 0.14, 0.04, C(214, 212, 206), 8) -- a fallen one
		rect(box, 0.02, 0.6, 0.08, 0.12, C(46, 128, 56), 7) -- trees
		rect(box, 0.5, 0.56, 0.08, 0.1, C(46, 128, 56), 7)
	end,
}

local gui = new("ScreenGui", { Name = "MapMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 32, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local shade = new("TextButton", { Name = "Shade", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 1 }, gui)
local W, H = 640, 380
local panel = new("Frame", { Name = "Panel", Active = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 2 }, gui)
corner(panel, 16)
stroke(panel, INK, 3)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(44, 40, 70), Color3.fromRGB(16, 14, 26)) }, panel)
local pscale = new("UIScale", {}, panel)
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	pscale.Scale = math.clamp(math.min((vp.X - 30) / W, (vp.Y - 30) / H), 0.45, 1)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
inkText(label(panel, { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(300, 36), Text = "MAPS", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }), 2)
label(panel, { Position = UDim2.fromOffset(26, 54), Size = UDim2.fromOffset(420, 16), Text = "pick where to play", FontFace = Kits.FONT_LABEL, TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(40, 40), Text = "",
	AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 80, 110), BorderSizePixel = 0, ZIndex = 4 }, panel)
corner(closeBtn, 10)
stroke(closeBtn, INK, 2)
inkText(label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", ZIndex = 5 }), 2)

local row = new("Frame", { Position = UDim2.fromOffset(16, 84), Size = UDim2.new(1, -32, 1, -100), BackgroundTransparency = 1, ZIndex = 3 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder }, row)
local cards = {}
local fader = new("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	Visible = false, ZIndex = 50 }, gui)
local busy = false
local function current()
	return player:GetAttribute("Map") or "Ruins"
end
local function refresh()
	for id, c in pairs(cards) do
		local here = current() == id
		c.stroke.Color = here and GREEN or INK
		c.stroke.Thickness = here and 3 or 2
		c.btn.BackgroundColor3 = here and Color3.fromRGB(70, 68, 92) or GREEN
		c.btnText.Text = here and "YOU ARE HERE" or "GO"
	end
end
local function close()
	panel.Visible = false
	shade.Visible = false
end
local function open()
	refresh()
	shade.Visible = true
	panel.Visible = true
	local sc = pscale.Scale
	pscale.Scale = sc * 0.92
	tween(pscale, 0.18, { Scale = sc }, Enum.EasingStyle.Back)
end
local function go(id)
	if busy or id == current() then
		return
	end
	busy = true
	close()
	fader.Visible = true
	fader.BackgroundTransparency = 1
	tween(fader, 0.22, { BackgroundTransparency = 0 }).Completed:Wait()
	remote:FireServer(id)
	local t0 = os.clock()
	while current() ~= id and os.clock() - t0 < 2 do
		task.wait()
	end
	task.wait(0.1)
	-- the camera keeps whatever way it was looking: put it behind the character, looking the way it faces
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if hrp and cam and cam.CameraType == Enum.CameraType.Custom then
		local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
		local eye = hrp.Position - look * 14 + Vector3.new(0, 5, 0)
		cam.CFrame = CFrame.lookAt(eye, hrp.Position + look * 6 + Vector3.new(0, 1.5, 0))
	end
	task.wait(0.05)
	tween(fader, 0.35, { BackgroundTransparency = 1 }).Completed:Wait()
	fader.Visible = false
	busy = false
end

for i, M in ipairs(MAPS) do
	local card = new("Frame", { Name = "Card_" .. M.id, LayoutOrder = i, Size = UDim2.new(0.5, -8, 1, 0), BackgroundColor3 = ROWC, BorderSizePixel = 0, ZIndex = 3 }, row)
	corner(card, 12)
	local st = stroke(card, INK, 2)
	local pic = new("Frame", { Name = "Preview", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 130), BackgroundColor3 = C(150, 210, 245), BorderSizePixel = 0,
		ClipsDescendants = true, ZIndex = 4 }, card)
	corner(pic, 8)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(180, 228, 255), C(120, 190, 240)) }, pic)
	PREVIEW[M.id](pic)
	inkText(label(card, { Position = UDim2.fromOffset(12, 148), Size = UDim2.new(1, -24, 0, 28), Text = M.name, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }), 2)
	label(card, { Position = UDim2.fromOffset(12, 180), Size = UDim2.new(1, -24, 0, 30), Text = M.sub, FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, TextScaled = true,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4 })
	local btn = new("TextButton", { Name = "Go", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 40), Text = "",
		AutoButtonColor = false, BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 4 }, card)
	corner(btn, 9)
	stroke(btn, INK, 2)
	local bt = inkText(label(btn, { Size = UDim2.new(1, -14, 1, -12), Position = UDim2.fromOffset(7, 6), Text = "GO", ZIndex = 5 }), 1.5)
	btn.Activated:Connect(function()
		go(M.id)
	end)
	cards[M.id] = { card = card, stroke = st, btn = btn, btnText = bt }
end
refresh()
player:GetAttributeChangedSignal("Map"):Connect(refresh)
closeBtn.Activated:Connect(close)
shade.Activated:Connect(close)

-- THE PILL (CharacterSelect's top strip; HudRails turns it into the MAPS tile on the left rail)
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b = new("TextButton", { Name = "MapsPill", LayoutOrder = 6, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 })
	if not strip then
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(0, 14, 0.72, 0)
	end
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	-- its own simple icon (HudRails draws HudShared.Icons' "map" over it on the rail)
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1 }, b)
	for i, x in ipairs({ 0.18, 0.5, 0.82 }) do
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.new(0.3, 0, 0.8, 0), Rotation = (i % 2 == 0) and 5 or -5,
			BackgroundColor3 = Color3.fromRGB(255, 240, 200), BorderSizePixel = 0 }, icon)
		corner(f, 2)
	end
	b.MouseEnter:Connect(function()
		tween(st, 0.12, { Transparency = 0 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.12, { Transparency = 0.55 })
	end)
	b.Activated:Connect(function()
		if panel.Visible then
			close()
		else
			open()
		end
	end)
	b.Parent = strip or gui
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a)
		if cmd == "open" then
			open()
		elseif cmd == "close" then
			close()
		elseif cmd == "go" then
			task.spawn(go, a)
		end
		return true
	end
	ctl.Parent = script
end
