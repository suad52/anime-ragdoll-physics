--!nocheck
-- StarterPlayerScripts.SandboxSliders (2026-11-14, sandbox shop): the SANDBOX SLIDERS panel, and this client's own gravity.
-- One row per HudShared.SliderCatalog slider: drag the knob (the track is geometric; the white tick is the default),
-- RESET puts it back, a locked row shows its price and buys its perk (developer product; product 0 = COMING SOON). The
-- Health row also has the GOD MODE switch. The footer sells the Sandbox Sliders Pack while any slider is still locked.
-- Values are saved by ShopService.Ext.Sliders (ShopRequest "sliders", sent when a drag ends) and come back as the player
-- attributes SliderVals / SliderOwned and each slider's own attribute. While dragging, run speed / jump / gravity are also
-- set on THIS client's copy of their attribute so the change is felt at once; the server's answer then puts the real
-- value back.
-- GRAVITY: workspace.Gravity on this client = the world's gravity (workspace attribute WorldGravity, which Moon Gravity
-- changes) x GravityMul. This client simulates its own body, so only this player floats; with GravityMul 1 the server's
-- value is left alone.
-- Opened by the SLIDERS tile (a pill in CharacterSelect.TopStrip that HudRails turns into a left-rail tile) and by
-- HudShared.OpenPanel("sliders") (the shop's MANAGE on a slider perk). Studio: script.Control:Invoke("open" | "close" |
-- "set", key, value | "state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local S = require(shared:WaitForChild("SliderCatalog"))
-- (2026-11-14, owner: no more kanji icons on purchases) each row's orb shows the slider's drawn icon (HudShared.CardArt);
-- without art the kanji orb stays as it was
local CardArt
pcall(function()
	CardArt = require(shared:WaitForChild("CardArt", 10))
end)
local function artInOrb(orb, item)
	if not (CardArt and item) then
		return
	end
	local slot = Instance.new("Frame")
	slot.Name = "ArtSlot"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, 0.5)
	slot.Size = UDim2.fromScale(1.15, 1.15)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.ZIndex = orb.ZIndex + 1
	slot.Parent = orb
	local ok, drew = pcall(CardArt.draw, slot, item)
	if not (ok and drew) then
		slot:Destroy()
		return
	end
	orb.BackgroundTransparency = 1
	for _, c in ipairs(orb:GetChildren()) do
		if c:IsA("UIStroke") then
			c.Enabled = false
		elseif c:IsA("TextLabel") then
			c.Visible = false
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- GRAVITY (first, so it works even if the panel fails to build)
local gravApplied = nil
local function worldGravity()
	local g = workspace:GetAttribute("WorldGravity")
	return (type(g) == "number" and g > 0) and g or S.STD_GRAVITY
end
local function gravityMul()
	local v = player:GetAttribute("GravityMul")
	if type(v) ~= "number" or v ~= v then
		return 1
	end
	return math.clamp(v, S.byKey.gravity.min, S.byKey.gravity.max)
end
local function applyGravity()
	local m = gravityMul()
	if math.abs(m - 1) < 1e-3 then
		if gravApplied then
			gravApplied = nil
			workspace.Gravity = worldGravity() -- hand it back to the world's value
		end
		return
	end
	local want = worldGravity() * m
	gravApplied = want
	if math.abs(workspace.Gravity - want) > 1e-3 then
		workspace.Gravity = want
	end
end
workspace:GetPropertyChangedSignal("Gravity"):Connect(applyGravity) -- the server's value replicated over ours
workspace:GetAttributeChangedSignal("WorldGravity"):Connect(applyGravity)
player:GetAttributeChangedSignal("GravityMul"):Connect(applyGravity)
applyGravity()

---------------------------------------------------------------------------------------------------------------------
-- PANEL
local Kits = require(shared:WaitForChild("Kits"))
local PerkCatalog = require(shared:WaitForChild("PerkCatalog"))
local ShopRequest = shared:WaitForChild("ShopRequest", 30)
local OpenPanel = shared:WaitForChild("OpenPanel", 30)

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local GREEN = Color3.fromRGB(90, 230, 140)
local RED = Color3.fromRGB(255, 80, 110)
local GREY = Color3.fromRGB(70, 68, 92)
local SOFT = Color3.fromRGB(200, 200, 225)
local TRACK = Color3.fromRGB(62, 62, 82)
local ROWC = Color3.fromRGB(30, 28, 48)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local LOCAL_KEYS = { speed = true, jump = true, gravity = true } -- felt on this client while dragging

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
local function bounce(btn)
	local sc = btn:FindFirstChildOfClass("UIScale") or new("UIScale", {}, btn)
	sc.Scale = 0.9
	tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function decode(attr)
	local ok, v = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute(attr) or "null")
	return (ok and type(v) == "table") and v or {}
end
local function serverVals()
	return decode("SliderVals")
end
local function ownedSet()
	local s = {}
	for _, k in ipairs(decode("SliderOwned")) do
		s[k] = true
	end
	return s
end
local function hasPerk(id)
	if player:GetAttribute("Perk_" .. id) == true then
		return true
	end
	for _, p in ipairs(decode("Perks")) do
		if p == id then
			return true
		end
	end
	return false
end
local function priceText(it)
	return "R$ " .. tostring(it and it.price or "?")
end

local gui = new("ScreenGui", { Name = "SandboxSliders", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 32,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local shade = new("TextButton", { Name = "Shade", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 1 }, gui)
local W, H = 780, 640
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

-- header
local band = new("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, panel)
corner(band, 3)
new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, S.LIST[1].color), ColorSequenceKeypoint.new(0.5, S.LIST[3].color),
	ColorSequenceKeypoint.new(1, S.LIST[5].color) }) }, band)
inkText(label(panel, { Position = UDim2.fromOffset(24, 16), Size = UDim2.fromOffset(360, 36), Text = "SANDBOX SLIDERS", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }), 2.5)
label(panel, { Position = UDim2.fromOffset(26, 54), Size = UDim2.fromOffset(520, 16), Text = "調整  -  your own physics, saved to your account",
	FontFace = Kits.FONT_LABEL, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(40, 40), Text = "",
	AutoButtonColor = false, BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 4 }, panel)
corner(closeBtn, 10)
stroke(closeBtn, INK, 2)
inkText(label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", ZIndex = 5 }), 2)

local list = new("ScrollingFrame", { Name = "List", Position = UDim2.fromOffset(16, 82), Size = UDim2.new(1, -32, 1, -164), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 5, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 3 }, panel)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }, list)

-- footer: toast + the pack
local footer = new("Frame", { Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -14), Size = UDim2.new(1, -32, 0, 60),
	BackgroundColor3 = ROWC, BorderSizePixel = 0, ZIndex = 3 }, panel)
corner(footer, 12)
local fstroke = stroke(footer, GOLD, 2)
local packItem = PerkCatalog.byId and PerkCatalog.byId[S.PACK]
local packText = inkText(label(footer, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -200, 0, 24), Text = "GET ALL SIX SLIDERS",
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }), 2)
local packSub = label(footer, { Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -200, 0, 16), Text = "", FontFace = Kits.FONT_LABEL,
	TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
local packBtn = new("TextButton", { Name = "BuyPack", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(160, 40),
	Text = "", AutoButtonColor = false, BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 4 }, footer)
corner(packBtn, 9)
stroke(packBtn, INK, 2)
local packBtnText = inkText(label(packBtn, { Size = UDim2.new(1, -14, 1, -12), Position = UDim2.fromOffset(7, 6), Text = priceText(packItem), ZIndex = 5 }), 1.5)
local toast = inkText(label(panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80), Size = UDim2.fromOffset(500, 22), Text = "",
	TextTransparency = 1, ZIndex = 9 }), 2)
local toastTok
local function say(text, color)
	local tok = {}
	toastTok = tok
	toast.Text = text
	toast.TextColor3 = color or WHITE
	toast.TextTransparency = 0
	local st = toast:FindFirstChildOfClass("UIStroke")
	st.Transparency = 0
	task.delay(1.6, function()
		if toastTok == tok then
			tween(toast, 0.35, { TextTransparency = 1 })
			tween(st, 0.35, { Transparency = 1 })
		end
	end)
end

local function buy(it)
	if not it then
		return
	end
	local pid = type(it.product) == "number" and it.product > 0 and it.product or nil
	if not pid then
		say(string.upper(it.name) .. " - COMING SOON", GOLD)
	elseif player:GetAttribute("ShopOffline") then
		say("SHOP OFFLINE - REJOIN TO BUY", RED)
	elseif hasPerk(it.id) then
		say("YOU ALREADY OWN " .. string.upper(it.name), GOLD)
	elseif not pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, pid) then
		say("PURCHASE UNAVAILABLE - TRY AGAIN", RED)
	end
end
packBtn.Activated:Connect(function()
	bounce(packBtn)
	buy(packItem)
end)

---------------------------------------------------------------------------------------------------------------------
-- rows
local rows = {}
local override = {} -- key -> value shown while dragging / saving ("god" too)
local seqOf = {}
local nextSend = 0
local dragging = nil -- { r, io, x }
local refresh

local function valueOf(def)
	if override[def.key] ~= nil then
		return override[def.key]
	end
	local v = serverVals()[def.key]
	return type(v) == "number" and v or def.default
end
local function godOn()
	if override.god ~= nil then
		return override.god
	end
	return serverVals().god == true
end

-- put this client's preview attributes back to what the server holds
local function syncLocal()
	local vals = serverVals()
	for key in pairs(LOCAL_KEYS) do
		local def = S.byKey[key]
		if override[key] == nil then
			local v = vals[key]
			player:SetAttribute(def.attr, type(v) == "number" and v or def.default)
		end
	end
end

local function send(key, value)
	if not ShopRequest then
		say("SHOP OFFLINE", RED)
		return
	end
	override[key] = value
	local seq = (seqOf[key] or 0) + 1
	seqOf[key] = seq
	task.spawn(function()
		-- the server refuses shop calls closer than 0.15 s apart
		local now = os.clock()
		local at = math.max(now, nextSend)
		nextSend = at + 0.2
		if at > now then
			task.wait(at - now)
		end
		if seqOf[key] ~= seq then
			return -- a newer value for this slider is already on its way
		end
		local ok, changed, msg = pcall(function()
			return ShopRequest:InvokeServer("sliders", { [key] = value })
		end)
		if seqOf[key] ~= seq then
			return
		end
		override[key] = nil
		if ok and changed then
			if key == "god" then
				say(value and "GOD MODE ON - NOTHING CAN HURT YOU" or "GOD MODE OFF", value and GREEN or WHITE)
			else
				local def = S.byKey[key]
				say(def.name .. "  " .. S.format(def, value), GREEN)
			end
		else
			say(ok and tostring(msg or "TRY AGAIN") or "TRY AGAIN", RED)
		end
		syncLocal()
		refresh()
	end)
end

local function preview(def, v)
	if LOCAL_KEYS[def.key] then
		player:SetAttribute(def.attr, v)
	end
end

local function buildRow(def)
	local it = PerkCatalog.byId and PerkCatalog.byId[def.perk]
	local row = new("Frame", { Name = "Row_" .. def.key, LayoutOrder = def.order, Size = UDim2.new(1, -4, 0, 86), BackgroundColor3 = ROWC,
		BorderSizePixel = 0, ZIndex = 4 }, list)
	corner(row, 12)
	local rst = stroke(row, INK, 2)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(22, 20, 36)) }, row)
	corner(new("Frame", { Position = UDim2.fromOffset(8, 10), Size = UDim2.new(0, 5, 1, -20), BackgroundColor3 = def.color, BorderSizePixel = 0, ZIndex = 5 }, row), 3)
	local orb = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ZIndex = 5 }, row)
	corner(orb)
	stroke(orb, INK, 2)
	local orbGrad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(def.color, def.color:Lerp(INK, 0.45)) }, orb)
	inkText(label(orb, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = it and it.glyph or "?",
		FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 6 }), 1.5)
	artInOrb(orb, it)
	inkText(label(row, { Position = UDim2.fromOffset(82, 12), Size = UDim2.fromOffset(250, 24), Text = def.name, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5 }), 2)
	label(row, { Position = UDim2.fromOffset(84, 38), Size = UDim2.fromOffset(246, 14), Text = def.jp, FontFace = Kits.FONT_LABEL, TextColor3 = def.color,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
	local desc = label(row, { Position = UDim2.fromOffset(84, 54), Size = UDim2.fromOffset(250, 26), Text = def.desc, FontFace = Kits.FONT_SMALL, TextColor3 = SOFT,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5 })
	new("UITextSizeConstraint", { MaxTextSize = 13 }, desc)

	-- the control area (right of X0)
	local X0 = 350
	local ctl = new("Frame", { Name = "Control", Position = UDim2.fromOffset(X0, 0), Size = UDim2.new(1, -X0, 1, 0), BackgroundTransparency = 1, ZIndex = 5 }, row)
	local track = new("Frame", { Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 8), Size = UDim2.new(1, -150, 0, 12),
		BackgroundColor3 = TRACK, BorderSizePixel = 0, ZIndex = 5 }, ctl)
	corner(track)
	stroke(track, INK, 1.5)
	local fill = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = def.color, BorderSizePixel = 0, ZIndex = 6 }, track)
	corner(fill)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(S.alpha(def, def.default), 0.5), Size = UDim2.fromOffset(3, 22),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 7 }, track)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 8 }, track)
	corner(knob)
	stroke(knob, INK, 2)
	label(ctl, { Position = UDim2.new(0, 0, 0.5, 20), Size = UDim2.fromOffset(70, 14), Text = S.format(def, def.min), FontFace = Kits.FONT_LABEL,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
	label(ctl, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0.5, 20), Size = UDim2.fromOffset(70, 14), Text = S.format(def, def.max),
		FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 })
	local val = inkText(label(ctl, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 8), Size = UDim2.fromOffset(80, 30), Text = "",
		ZIndex = 5 }), 2)
	local reset = new("TextButton", { Name = "Reset", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 8), Size = UDim2.fromOffset(46, 28),
		Text = "", AutoButtonColor = false, BackgroundColor3 = GREY, BorderSizePixel = 0, ZIndex = 6 }, ctl)
	corner(reset, 7)
	stroke(reset, INK, 1.5)
	label(reset, { Size = UDim2.new(1, -10, 1, -12), Position = UDim2.fromOffset(5, 6), Text = "RESET", ZIndex = 7 })
	local hit = new("TextButton", { Name = "Hit", BackgroundTransparency = 1, Text = "", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -14, 0.5, 0),
		Size = UDim2.new(1, 28, 0, 44), ZIndex = 9 }, track)
	local r = { def = def, item = it, row = row, stroke = rst, orbGrad = orbGrad, track = track, fill = fill, knob = knob, val = val, reset = reset }

	-- GOD MODE (health row): a switch above the track
	if def.god then
		label(ctl, { Position = UDim2.fromOffset(0, 12), Size = UDim2.fromOffset(110, 18), Text = "GOD MODE", FontFace = Kits.FONT_LABEL, TextColor3 = GOLD,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
		local sw = new("TextButton", { Name = "God", Position = UDim2.fromOffset(96, 8), Size = UDim2.fromOffset(62, 26), Text = "", AutoButtonColor = false,
			BackgroundColor3 = GREY, BorderSizePixel = 0, ZIndex = 6 }, ctl)
		corner(sw)
		stroke(sw, INK, 2)
		local swText = inkText(label(sw, { Size = UDim2.fromOffset(28, 14), Position = UDim2.fromOffset(28, 6), Text = "OFF", ZIndex = 7 }), 1)
		local swKnob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = WHITE,
			BorderSizePixel = 0, ZIndex = 8 }, sw)
		corner(swKnob)
		stroke(swKnob, INK, 1.5)
		r.god = { button = sw, text = swText, knob = swKnob }
		sw.Activated:Connect(function()
			if not ownedSet()[def.key] then
				buy(it)
				return
			end
			send("god", not godOn())
			refresh()
		end)
	end

	-- locked: dims the controls; tapping it opens the purchase
	local lock = new("TextButton", { Name = "Locked", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(X0 - 10, 6), Size = UDim2.new(1, -(X0 - 4), 1, -12),
		BackgroundColor3 = INK, BackgroundTransparency = 0.03, BorderSizePixel = 0, ZIndex = 20 }, row) -- (2026-11-15) near-solid: the slider's own labels showed through
	corner(lock, 10)
	stroke(lock, GOLD, 1.5, 0.45)
	local pad = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 26, 0.5, 4), Size = UDim2.fromOffset(18, 14), BackgroundColor3 = GOLD,
		BorderSizePixel = 0, ZIndex = 21 }, lock)
	corner(pad, 3)
	stroke(pad, INK, 1.5)
	local shackle = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(11, 12), BackgroundTransparency = 1,
		ZIndex = 21 }, pad)
	corner(shackle)
	new("UIStroke", { Color = GOLD, Thickness = 2.5 }, shackle)
	-- (2026-11-15) just LOCKED (the row's title already names the slider): the full name wrapped onto 3 cramped lines
	local lockText = inkText(label(lock, { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -230, 1, 0), Text = "LOCKED",
		TextColor3 = GOLD, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 }), 1.5)
	new("UITextSizeConstraint", { MaxTextSize = 22 }, lockText)
	local lockBuy = new("TextButton", { Name = "Unlock", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 38),
		Text = "", AutoButtonColor = false, BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 22 }, lock)
	corner(lockBuy, 9)
	stroke(lockBuy, INK, 2)
	local lockBuyText = inkText(label(lockBuy, { Size = UDim2.new(1, -14, 1, -12), Position = UDim2.fromOffset(7, 6), Text = "UNLOCK  " .. priceText(it),
		ZIndex = 23 }), 1.5)
	r.lock, r.lockBuy, r.lockBuyText = lock, lockBuy, lockBuyText
	local function doBuy()
		bounce(lockBuy)
		buy(it)
	end
	lock.Activated:Connect(doBuy)
	lockBuy.Activated:Connect(doBuy)

	-- dragging
	local function fromX(x)
		local a = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		local v = S.value(def, a)
		override[def.key] = v
		preview(def, v)
		refresh()
	end
	hit.InputBegan:Connect(function(io)
		if not ownedSet()[def.key] then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = { r = r, io = io, x = fromX }
			seqOf[def.key] = (seqOf[def.key] or 0) + 1 -- a save still in flight must not snap the knob back mid-drag
			list.ScrollingEnabled = false
			fromX(io.Position.X)
		end
	end)
	reset.Activated:Connect(function()
		bounce(reset)
		preview(def, def.default)
		send(def.key, def.default)
		refresh()
	end)
	rows[def.key] = r
end

for _, def in ipairs(S.LIST) do
	buildRow(def)
end

UserInputService.InputChanged:Connect(function(io)
	local d = dragging
	if not d then
		return
	end
	if io.UserInputType == Enum.UserInputType.MouseMovement or (io.UserInputType == Enum.UserInputType.Touch and io == d.io) then
		d.x(io.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(io)
	local d = dragging
	if not d then
		return
	end
	if io.UserInputType == Enum.UserInputType.MouseButton1 or (io.UserInputType == Enum.UserInputType.Touch and io == d.io) then
		dragging = nil
		list.ScrollingEnabled = true
		local key = d.r.def.key
		send(key, override[key] or valueOf(d.r.def))
	end
end)

refresh = function()
	local owned = ownedSet()
	local nOwned = 0
	for key, r in pairs(rows) do
		local def = r.def
		local own = owned[key] == true
		if own then
			nOwned += 1
		end
		local v = valueOf(def)
		local a = S.alpha(def, v)
		r.fill.Size = UDim2.fromScale(a, 1)
		r.knob.Position = UDim2.fromScale(a, 0.5)
		r.val.Text = S.format(def, v)
		local moved = math.abs(v - def.default) > 1e-6
		r.val.TextColor3 = moved and def.color or WHITE
		r.reset.Visible = own and moved
		r.lock.Visible = not own
		local ctlF = r.lock.Parent and r.lock.Parent:FindFirstChild("Control")
		if ctlF then
			ctlF.Visible = own -- (2026-11-15) a locked row hides its slider, so nothing ghosts through the LOCKED cover
		end
		r.stroke.Color = own and def.color:Lerp(INK, 0.25) or INK
		r.orbGrad.Color = own and ColorSequence.new(def.color, def.color:Lerp(INK, 0.45))
			or ColorSequence.new(Color3.fromRGB(130, 128, 145), Color3.fromRGB(46, 44, 60))
		local it = r.item
		local sellable = it and type(it.product) == "number" and it.product > 0
		r.lockBuyText.Text = sellable and ("UNLOCK  " .. priceText(it)) or "COMING SOON"
		r.lockBuy.BackgroundColor3 = sellable and GREEN or GREY
		if r.god then
			local on = own and godOn()
			r.god.text.Text = on and "ON" or "OFF"
			r.god.text.Position = on and UDim2.fromOffset(6, 6) or UDim2.fromOffset(28, 6)
			r.god.knob.Position = on and UDim2.new(1, -22, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
			r.god.button.BackgroundColor3 = on and GOLD or GREY
		end
	end
	local all = nOwned >= #S.LIST
	local packOwned = all or hasPerk(S.PACK)
	packBtn.Visible = not packOwned
	local sellable = packItem and type(packItem.product) == "number" and packItem.product > 0
	packBtnText.Text = sellable and priceText(packItem) or "COMING SOON"
	packBtn.BackgroundColor3 = sellable and GREEN or GREY
	if packOwned then
		packText.Text = "EVERY SLIDER UNLOCKED"
		packSub.Text = "drag a knob - RESET puts it back - your settings follow you to every server"
		fstroke.Color = GREEN
	else
		packText.Text = "GET ALL SIX SLIDERS"
		local worth = 0
		for _, def in ipairs(S.LIST) do
			local it = PerkCatalog.byId[def.perk]
			worth += it and it.price or 0
		end
		packSub.Text = string.format("%d of %d unlocked  -  the pack is worth R$ %d", nOwned, #S.LIST, worth)
		fstroke.Color = GOLD
	end
end

for _, a in ipairs({ "SliderVals", "SliderOwned", "Perks" }) do
	player:GetAttributeChangedSignal(a):Connect(function()
		if panel.Visible then
			refresh()
		end
	end)
end

local function open()
	refresh()
	fit()
	shade.Visible = true
	shade.BackgroundTransparency = 1
	tween(shade, 0.2, { BackgroundTransparency = 0.45 })
	panel.Visible = true
	panel.Position = UDim2.fromScale(0.5, 0.58)
	tween(panel, 0.28, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
end
local function close()
	dragging = nil
	list.ScrollingEnabled = true
	shade.Visible = false
	panel.Visible = false
end
closeBtn.Activated:Connect(close)
shade.Activated:Connect(close)
if OpenPanel then
	OpenPanel.Event:Connect(function(name)
		if name == "sliders" then
			open()
		elseif panel.Visible and (name == "shop" or name == "settings") then
			close()
		end
	end)
end

-- THE PILL (CharacterSelect's top strip; HudRails turns it into the SLIDERS tile on the left rail)
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b = new("TextButton", { Name = "SlidersPill", LayoutOrder = 3, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 })
	if not strip then
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(0, 14, 0.62, 0)
	end
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1 }, b)
	for i, x in ipairs({ 0.28, 0.72, 0.46 }) do
		local y = (i - 0.5) / 3
		corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = WHITE,
			BorderSizePixel = 0 }, icon), 2)
		local k = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = S.LIST[i * 2 - 1].color, BorderSizePixel = 0 }, icon)
		corner(k)
		stroke(k, WHITE, 1.5)
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
		elseif OpenPanel then
			OpenPanel:Fire("sliders")
		else
			open()
		end
	end)
	b.Parent = strip or gui
end)

-- Studio test hook
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			open()
		elseif cmd == "close" then
			close()
		elseif cmd == "set" then
			local def = S.byKey[a]
			if a == "god" then
				send("god", b == true)
			elseif def then
				preview(def, S.snap(def, b))
				send(a, S.snap(def, b))
			end
		elseif cmd == "state" then
			local out = { open = panel.Visible, owned = ownedSet(), vals = serverVals(), gravity = workspace.Gravity, gravApplied = gravApplied,
				override = override }
			for key, r in pairs(rows) do
				out["row_" .. key] = { locked = r.lock.Visible, text = r.val.Text, lockText = r.lockBuyText.Text }
			end
			return HttpService:JSONEncode(out)
		end
		return true
	end
	ctl.Parent = script
end
