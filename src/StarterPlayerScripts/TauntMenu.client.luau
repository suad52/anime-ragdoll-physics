--!nocheck
-- StarterPlayerScripts.TauntMenu (2026-11-09, shop expansion): the TAUNT menu and taunt playback.
-- Open it with T, the speech-bubble pill in the top strip, or HudShared.OpenPanel("taunts") (the shop's MANAGE).
-- Picking a taunt fires HudShared.Taunt(id); TauntService checks it and tells everyone, and every client then plays
-- the sound at that player's head (SoundService.SettingsTaunts group = Settings > Audio > TAUNTS volume) and pops a
-- speech bubble over them. Locked packs show a buy button (the PerkCatalog TauntHype / TauntTrash products).
-- Studio: script.Control:Invoke("open") / ("close") / ("play", id) / ("state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local PerkCatalog = require(shared:WaitForChild("PerkCatalog"))
local T = require(shared:WaitForChild("TauntCatalog"))
local remote = shared:WaitForChild("Taunt", 30)
local OpenPanel = shared:WaitForChild("OpenPanel", 30)
local InputMode = nil
pcall(function()
	InputMode = require(shared:WaitForChild("InputMode", 10))
end)
-- (2026-11-11, "have the option to have keybinds") the menu's key is the TAUNTS action (default T): the press is read
-- through Keybinds.logical and the "PRESS T TO OPEN" hint draws Keybinds.label, so a rebound key opens it and says so.
-- With no rebinds both are T, exactly as before.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local DIM = Color3.fromRGB(170, 170, 195)
local OFFC = Color3.fromRGB(62, 62, 82)
local C0, C1 = Color3.fromRGB(255, 190, 70), Color3.fromRGB(255, 80, 140)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local PILL_H = 40

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
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function tauntGroup()
	local g = SoundService:FindFirstChild("SettingsTaunts")
	if not (g and g:IsA("SoundGroup")) then
		g = new("SoundGroup", { Name = "SettingsTaunts", Volume = 1 }, SoundService)
	end
	return g
end

---------------------------------------------------------------------------------------------------------------------
-- PLAYBACK: a bubble over the taunter's head + the sound from their head
local function playTaunt(who, id)
	local t = T.byId[id]
	local char = who and who.Character
	local head = char and char:FindFirstChild("Head")
	if not (t and head) then
		return
	end
	local old = head:FindFirstChild("TauntBubble")
	if old then
		old:Destroy()
	end
	local bb = new("BillboardGui", { Name = "TauntBubble", Size = UDim2.fromOffset(200, 54), StudsOffset = Vector3.new(0, 3, 0), MaxDistance = 150,
		LightInfluence = 0, AlwaysOnTop = false, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local holder = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bb)
	local sc = new("UIScale", { Scale = 0.2 }, holder)
	local bubble = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(1, -10, 0, 40),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, holder)
	corner(bubble, 14)
	stroke(bubble, INK, 2.5)
	local tail = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(12, 12), Rotation = 45,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 0 }, holder)
	stroke(tail, INK, 2.5)
	bubble.ZIndex = 2
	label(bubble, { Size = UDim2.new(1, -18, 1, -12), Position = UDim2.fromOffset(9, 6), Text = t.line, TextColor3 = INK, ZIndex = 3 })
	bb.Parent = head
	tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(T.BUBBLE_TIME, function()
		if bb.Parent then
			tween(sc, 0.18, { Scale = 0.01 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.2)
			bb:Destroy()
		end
	end)
	local s = new("Sound", { Name = "TauntSound", SoundId = "rbxassetid://" .. string.format("%d", t.sound), Volume = 0.9, RollOffMinDistance = 12,
		RollOffMaxDistance = 140, SoundGroup = tauntGroup() }, head)
	s:Play()
	task.delay(T.MAX_LEN, function()
		if s.Parent then
			tween(s, 0.4, { Volume = 0 })
		end
	end)
	task.delay(T.MAX_LEN + 0.5, function()
		s:Destroy()
	end)
end
if remote then
	remote.OnClientEvent:Connect(function(who, id)
		pcall(playTaunt, who, id)
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- THE MENU
local gui = new("ScreenGui", { Name = "TauntMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local root = new("Frame", { Name = "TauntRoot", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local shade = new("TextButton", { Name = "TauntShade", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5 }, root)
local W, H = 560, 440
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Active = true }, root)
corner(panel, 16)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(24, 20, 40), Color3.fromRGB(10, 9, 18)) }, panel)
stroke(panel, INK, 3)
local pscale = new("UIScale", {}, panel)
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	pscale.Scale = math.clamp(math.min((vp.X - 20) / W, (vp.Y - 20) / H), 0.4, 1) * (tonumber(player:GetAttribute("Opt_menuScale")) or 1)
end
player:GetAttributeChangedSignal("Opt_menuScale"):Connect(fit) -- SETTINGS > CONTROLS > MENU SIZE

local hd = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
corner(hd, 16)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hd)
local hsq = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hsq)
inkText(label(hd, { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(200, 38), Text = "TAUNTS", TextXAlignment = Enum.TextXAlignment.Left }), 2.5)
local hint = inkText(label(hd, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.fromOffset(240, 16),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right }), 1.5)
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(36, 36),
	AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
corner(closeBtn)
stroke(closeBtn, INK, 2)
label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", TextColor3 = INK })

local content = new("ScrollingFrame", { Name = "Content", Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -20, 1, -82), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = WHITE, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y }, panel)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }, content)

local function idleHint()
	return (InputMode and InputMode.isTouch()) and "" or ("PRESS " .. Keybinds.label(Enum.KeyCode.T) .. " TO OPEN")
end
local statusToken = 0
local hintFlashing = false
local function flashHint(text, color)
	statusToken += 1
	local my = statusToken
	hintFlashing = true
	hint.Text = text
	hint.TextColor3 = color or WHITE
	task.delay(2, function()
		if my == statusToken then
			hintFlashing = false
			hint.Text = idleHint()
			hint.TextColor3 = WHITE
		end
	end)
end

local readyAt = 0
local cooldownBar -- set with the pill
local close -- forward
local function tryTaunt(id)
	local t = T.byId[id]
	if not t or not remote then
		return false
	end
	if not T.owns(player, t) then
		flashHint("LOCKED - GET THE PACK", GOLD)
		return false
	end
	local now = os.clock()
	if now < readyAt then
		flashHint(string.format("WAIT %.1fs", readyAt - now), GOLD)
		return false
	end
	readyAt = now + T.COOLDOWN
	remote:FireServer(id)
	if cooldownBar then
		cooldownBar.Size = UDim2.fromScale(1, 1)
		tween(cooldownBar, T.COOLDOWN, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Linear)
	end
	close()
	return true
end

local function build()
	for _, c in ipairs(content:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then
			c:Destroy()
		end
	end
	local order = 0
	for _, pack in ipairs(T.PACKS) do
		local owned = pack.perk == nil or player:GetAttribute("Perk_" .. pack.perk) == true
		order += 1
		local head = new("Frame", { Name = "Pack_" .. pack.id, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, content)
		label(head, { Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.fromOffset(2, 8), Text = pack.name, TextColor3 = owned and GOLD or Color3.fromRGB(255, 160, 220),
			FontFace = Kits.FONT_LABEL, TextXAlignment = Enum.TextXAlignment.Left })
		if not owned then
			local it = PerkCatalog.byId[pack.perk]
			local live = it and (tonumber(it.product) or 0) > 0
			local b = new("TextButton", { Name = "Buy", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(150, 30),
				AutoButtonColor = false, Text = "", BackgroundColor3 = live and GOLD or OFFC, BorderSizePixel = 0 }, head)
			corner(b, 8)
			stroke(b, INK, 1.5)
			label(b, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), Text = live and ("R$ " .. it.price .. "  UNLOCK") or "COMING SOON",
				TextColor3 = live and INK or WHITE })
			b.Activated:Connect(function()
				if live then
					pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, it.product)
				else
					flashHint("COMING SOON", GOLD)
				end
			end)
		end
		order += 1
		local grid = new("Frame", { Name = "Grid_" .. pack.id, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1 }, content)
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 0, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for _, t in ipairs(T.LIST) do
			if t.pack == pack.id then
				local b = new("TextButton", { Name = t.id, LayoutOrder = t.order, AutoButtonColor = false, Text = "", BackgroundColor3 = owned and WHITE or OFFC,
					BackgroundTransparency = owned and 0 or 0.2, BorderSizePixel = 0 }, grid)
				corner(b, 10)
				stroke(b, INK, 1.5)
				if owned then
					new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(225, 225, 240)) }, b)
				end
				label(b, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 6), Text = t.name, TextColor3 = owned and INK or DIM })
				label(b, { Size = UDim2.new(1, -16, 0, 11), Position = UDim2.fromOffset(8, 27), Text = owned and t.line or "LOCKED", TextColor3 = owned and Color3.fromRGB(90, 80, 120) or DIM,
					FontFace = Kits.FONT_LABEL })
				local sc = new("UIScale", {}, b)
				b.MouseEnter:Connect(function()
					tween(sc, 0.1, { Scale = 1.04 })
				end)
				b.MouseLeave:Connect(function()
					tween(sc, 0.1, { Scale = 1 })
				end)
				b.Activated:Connect(function()
					tryTaunt(t.id)
				end)
			end
		end
	end
end

local function open()
	fit()
	build()
	hint.Text = idleHint()
	root.Visible = true
	panel.Position = UDim2.fromScale(0.5, 0.56)
	tween(panel, 0.18, { Position = UDim2.fromScale(0.5, 0.52) })
end
close = function()
	root.Visible = false
end
closeBtn.Activated:Connect(close)
shade.Activated:Connect(function(io)
	if io and io.Position then
		local a, s = panel.AbsolutePosition, panel.AbsoluteSize
		if io.Position.X >= a.X and io.Position.X <= a.X + s.X and io.Position.Y >= a.Y and io.Position.Y <= a.Y + s.Y then
			return
		end
	end
	close()
end)

UserInputService.InputBegan:Connect(function(io, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	if false and Keybinds.logical(io.KeyCode) == Enum.KeyCode.T then -- (2026-11-15) taunts removed: the key no longer opens the menu
		if root.Visible then
			close()
		else
			open()
		end
	end
end)

-- a rebind made while the menu is open redraws the idle hint at once (a status flash keeps its 2 s)
Keybinds.Changed:Connect(function()
	if root.Visible and not hintFlashing then
		hint.Text = idleHint()
	end
end)

if OpenPanel then
	OpenPanel.Event:Connect(function(name)
		if name == "taunts" then
			open()
		end
	end)
end
player.AttributeChanged:Connect(function(name)
	if (name == "Perk_TauntHype" or name == "Perk_TauntTrash") and root.Visible then
		build()
	end
end)

-- THE PILL (top strip, just before the Settings gear): a speech bubble with three dots and a cooldown shade
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b
	if strip then
		b = new("TextButton", { Name = "TauntPill", LayoutOrder = 8, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(PILL_H, PILL_H),
			BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0, ClipsDescendants = true }, strip)
	else
		b = new("TextButton", { Name = "TauntPill", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -62, 0, 8), AutoButtonColor = false, Text = "",
			Size = UDim2.fromOffset(PILL_H, PILL_H), BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0, ClipsDescendants = true }, gui)
	end
	-- (2026-11-14, ragdoll sandbox) owner: "remove the starter the duels and the taunt buttons we dont need those". The
	-- button is still built (its cooldown shade is used above) but never shown. The taunt menu itself still opens with
	-- its key and from an owned taunt pack's MANAGE button in the shop.
	b.Visible = false
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	cooldownBar = new("Frame", { Name = "Cooldown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = C1, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, b)
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -1), Size = UDim2.fromOffset(24, 17),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, b)
	corner(icon, 6)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 7, 1, 1), Size = UDim2.fromOffset(7, 7), Rotation = 45,
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, icon)
	for i = -1, 1 do
		corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 6, 0.5, 0), Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = PILL_BG, BorderSizePixel = 0, ZIndex = 2 }, icon))
	end
	b.MouseEnter:Connect(function()
		tween(st, 0.12, { Transparency = 0 })
		tween(icon, 0.15, { Rotation = -8 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.12, { Transparency = 0.55 })
		tween(icon, 0.15, { Rotation = 0 })
	end)
	b.Activated:Connect(function()
		if root.Visible then
			close()
		else
			open()
		end
	end)
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a)
		if cmd == "open" then
			open()
		elseif cmd == "close" then
			close()
		elseif cmd == "play" then
			return tryTaunt(a)
		elseif cmd == "state" then
			return HttpService:JSONEncode({ open = root.Visible, cooldown = math.max(0, readyAt - os.clock()) })
		end
		return true
	end
	ctl.Parent = script
end
