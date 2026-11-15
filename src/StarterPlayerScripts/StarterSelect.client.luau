--!nocheck
-- StarterSelect (2026-11-07): the first-join pick screen. A new player (ShopService sets StarterPicked = false) sees
-- the whole roster (HudShared.Kits) dealt out as cards and picks Catalog.KITS.STARTER_PICKS of them to own for free.
-- Every pick fires that fighter's own effect (Gojo's infinity rings shove the rivals away, Killua's bolts, Sukuna's
-- cleaves, Goku's golden aura ...), knocks the other cards back, sweeps a name banner over the header and flies the
-- emblem into the team tray. Tap a picked card again to drop it. LOCK IN sends ("pickStarters", ids) and plays the
-- line-up finale, then a wipe reveals the game. The rest unlock later from the CHARACTER menu (CharacterSelect).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local Catalog = require(shared:WaitForChild("ShopCatalog"))
local ShopRequest = shared:WaitForChild("ShopRequest", 30)
local KCFG = Catalog.KITS or {}
local PREMIUM = KCFG.PREMIUM or {} -- Robux-only fighters: shown, never pickable here
-- (2026-11-09) fighters in development (KITS.EARLY) are left out of the pick screen entirely: only the Early Access
-- pass unlocks them (the character menu sells it)
local EARLY = KCFG.EARLY or {}
local ROSTER = {}
for _, k in ipairs(Kits.list) do
	if not EARLY[k.id] and not k.noPowers then -- (the no-powers NORMAL choice is everyone's already: nothing to pick)
		table.insert(ROSTER, k)
	end
end

-- the server decides: nil while the profile loads, true = already has a team
while player:GetAttribute("StarterPicked") == nil do
	player:GetAttributeChangedSignal("StarterPicked"):Wait()
end
if player:GetAttribute("StarterPicked") == true then
	return
end

local C = Color3.fromRGB
local V2 = Vector2.new
local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD, GOLD2 = C(255, 214, 70), C(255, 150, 20)
local RED = C(255, 60, 95)
local HANKO = C(230, 36, 56)
local BLACK_FONT = Font.fromEnum(Enum.Font.GothamBlack)

-- fighters already unlocked (a game pass bought before the first pick) don't take a slot
local preOwned = {}
do
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("KitsOwned") or "[]")
	end)
	for _, id in ipairs(ok and type(list) == "table" and list or {}) do
		preOwned[id] = true
	end
end
local openCount = 0
for _, k in ipairs(ROSTER) do
	if not preOwned[k.id] and not PREMIUM[k.id] then
		openCount += 1
	end
end
local NEED = math.min(KCFG.STARTER_PICKS or 5, openCount)
if NEED <= 0 then
	pcall(function()
		ShopRequest:InvokeServer("pickStarters", {})
	end)
	return
end

local function fmtYen(n)
	local s = tostring(math.floor(n or 0))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return (Catalog.CURRENCY or "") .. " " .. s
end
local PRICE_TEXT = fmtYen(KCFG.PRICE_YEN or 2000) .. " OR R$" .. tostring(KCFG.PRICE_ROBUX or 25)
local premiumNames, premiumPrices = {}, {}
for _, k in ipairs(ROSTER) do
	if PREMIUM[k.id] and not preOwned[k.id] then
		table.insert(premiumNames, k.name)
		premiumPrices[PREMIUM[k.id]] = true
	end
end
local SUB_TEXT = string.format("Pick %d to start - they're yours for good. The rest unlock later for %s each.", NEED, PRICE_TEXT)
if #premiumNames > 0 then
	local onePrice = next(premiumPrices)
	local priceText = next(premiumPrices, onePrice) == nil and ("R$" .. tostring(onePrice)) or "premium"
	SUB_TEXT ..= string.format("  %s: %s, Robux only.", table.concat(premiumNames, " & "), priceText)
end

---------------------------------------------------------------------------------------------------
-- helpers
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
	return new("UIStroke", { Color = color or INK, Thickness = th or 2, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function textStroke(t, th, color)
	new("UIStroke", { Color = color or INK, Thickness = th or 2 }, t)
	return t
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, TextColor3 = WHITE, TextScaled = true, Text = "",
		FontFace = Kits.FONT_PUNCH }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function at(p)
	return UDim2.fromOffset(p.X, p.Y)
end

local SND = {
	Blue = "rbxassetid://113813942754476",
	Red = "rbxassetid://135281137796217",
	Birth = "rbxassetid://102313023652420",
	Launch = "rbxassetid://93530870983093",
	Swing = "rbxassetid://9120972444",
	Hit = "rbxassetid://126976659766267",
	HitFinal = "rbxassetid://79476956608476",
}
local KIT_SND = {
	Limitless = { SND.Blue, 0.7, 1 },
	Vulpine = { SND.Birth, 0.6, 1.1 },
	Godspeed = { SND.Launch, 0.6, 1.3 },
	OneForAll = { SND.HitFinal, 0.8, 0.9 },
	Tempest = { SND.Red, 0.6, 1.15 },
	Carver = { SND.Swing, 0.8, 0.8 },
	Shifter = { SND.HitFinal, 0.9, 0.7 },
	Zangetsu = { SND.Swing, 0.8, 0.65 },
	Ascendant = { SND.Birth, 0.7, 1.3 },
}
local function sfx(id, vol, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = workspace.CurrentCamera or workspace
	s:Play()
	Debris:AddItem(s, 5)
end

---------------------------------------------------------------------------------------------------
-- layers: the backdrop (speed lines, screentone, a giant kanji), the scaled stage (header, cards, tray), and the
-- unscaled effects layer on top (effects spill over everything, in screen pixels)
local gui = new("ScreenGui", { Name = "StarterSelect", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local root = new("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Active = true,
	ZIndex = 1 }, gui)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(26, 19, 48), C(6, 5, 12)) }, root)
local tint = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, root)
local watermark = label(root, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53), Size = UDim2.fromScale(0.6, 0.9), Text = "選",
	FontFace = BLACK_FONT, TextTransparency = 0.94, ZIndex = 2 })

local lines = {}
for i = 1, 28 do
	local f = new("Frame", { AnchorPoint = V2(0, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.86 + math.random() * 0.1,
		BorderSizePixel = 0, Rotation = -12, ZIndex = 3 }, root)
	lines[i] = { f = f, x = math.random() * 1.2, y = math.random(), w = 0.08 + math.random() * 0.22, speed = 0.05 + math.random() * 0.12,
		h = math.random(1, 3) }
end
local lineBoost = 1
for gy = 0, 6 do
	for gx = 0, 10 do
		local s = math.max(1, 12 - (gx + gy) * 0.9)
		corner(new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, 18 + gx * 18, 1, -18 - gy * 18), Size = UDim2.fromOffset(s, s),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 3 }, root))
		corner(new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -18 - gx * 18, 0, 18 + gy * 18), Size = UDim2.fromOffset(s, s),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 3 }, root))
	end
end

local fx = new("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, gui)
local flashF = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 70 }, fx)

-- stage layout (design pixels; a UIScale fits it to the screen)
local CW, CH, GAP, PER_ROW = 158, 214, 18, 5
local STAGE_W = 1000
local GRID_Y = 128
local rowsN = math.ceil(#ROSTER / PER_ROW)
local gridW = PER_ROW * CW + (PER_ROW - 1) * GAP
local gridH = rowsN * CH + (rowsN - 1) * GAP
local TRAY_Y = GRID_Y + gridH + 26
local STAGE_H = TRAY_Y + 92

local stage = new("Frame", { Name = "Stage", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(STAGE_W, STAGE_H),
	BackgroundTransparency = 1, ZIndex = 5 }, root)
local stageScale = new("UIScale", {}, stage)
local function unit()
	return stageScale.Scale
end
local function centerOf(g)
	return g.AbsolutePosition + g.AbsoluteSize / 2 - fx.AbsolutePosition
end

-- header
local kicker = label(stage, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(STAGE_W / 2, 10), Size = UDim2.fromOffset(500, 18),
	Text = "第一章  ・  YOUR FIRST TEAM", FontFace = Kits.FONT_LABEL, TextColor3 = C(255, 125, 165), ZIndex = 6 })
local title = textStroke(label(stage, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(STAGE_W / 2, 30), Size = UDim2.fromOffset(720, 60),
	Text = "CHOOSE YOUR FIGHTERS", FontFace = Kits.FONT_TITLE, Rotation = -1.5, ZIndex = 7 }), 3)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, C(255, 222, 130)) }, title)
local titleScale = new("UIScale", {}, title)
local sub = label(stage, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(STAGE_W / 2, 94), Size = UDim2.fromOffset(820, 18),
	Text = SUB_TEXT, FontFace = Kits.FONT_LABEL, TextColor3 = C(205, 205, 230), ZIndex = 6 })

local counter = new("Frame", { Name = "Counter", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(STAGE_W - 62, 60), Size = UDim2.fromOffset(84, 84),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6 }, stage)
corner(counter)
new("UIGradient", { Rotation = 60, Color = ColorSequence.new(GOLD, GOLD2) }, counter)
stroke(counter, INK, 3)
local counterScale = new("UIScale", {}, counter)
local counterText = textStroke(label(counter, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.74, 0.44),
	Text = "0/" .. NEED, ZIndex = 7 }), 2)
label(counter, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromScale(0.6, 0.15), Text = "PICKED",
	FontFace = Kits.FONT_LABEL, TextColor3 = INK, ZIndex = 7 })

local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset((STAGE_W - gridW) / 2, GRID_Y), Size = UDim2.fromOffset(gridW, gridH),
	BackgroundTransparency = 1, ZIndex = 6 }, stage)

---------------------------------------------------------------------------------------------------
-- effects (all positions in effects-layer pixels; sizes scale with the stage)
local shakeAmp, shakeUntil, shakeDur = 0, 0, 1
local function shake(amp, dur)
	local now = os.clock()
	local cur = shakeUntil > now and shakeAmp * (shakeUntil - now) / shakeDur or 0
	if amp >= cur then
		shakeAmp, shakeDur, shakeUntil = amp, dur, now + dur
	end
end

local function flash(color, from, dur)
	flashF.BackgroundColor3 = color
	flashF.BackgroundTransparency = from
	tween(flashF, dur, { BackgroundTransparency = 1 })
end

local function ring(c, color, r0, r1, dur, th, delay)
	local U = unit()
	task.delay(delay or 0, function()
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(r0 * 2 * U, r0 * 2 * U), BackgroundTransparency = 1,
			ZIndex = 52 }, fx)
		corner(f)
		local s = new("UIStroke", { Color = color, Thickness = (th or 4) * U }, f)
		tween(f, dur, { Size = UDim2.fromOffset(r1 * 2 * U, r1 * 2 * U) }, Enum.EasingStyle.Quart)
		tween(s, dur, { Transparency = 1, Thickness = 0.5 })
		Debris:AddItem(f, dur + 0.05)
	end)
end

local function sparks(c, colors, n, dist, dur)
	local U = unit()
	for _ = 1, n do
		local a = math.random() * math.pi * 2
		local r = (0.4 + math.random() * 0.6) * dist * U
		local s = (5 + math.random() * 6) * U
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(s, s), BackgroundColor3 = colors[math.random(#colors)],
			BorderSizePixel = 0, ZIndex = 54 }, fx)
		corner(f)
		tween(f, dur, { Position = UDim2.fromOffset(c.X + math.cos(a) * r, c.Y + math.sin(a) * r), Size = UDim2.fromOffset(1, 1),
			BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(f, dur + 0.05)
	end
end

local function rays(c, color, n, len, dur, width)
	local U = unit()
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + math.rad(math.random(-8, 8))
		local d = V2(math.cos(a), math.sin(a))
		local L = len * (0.7 + math.random() * 0.5) * U
		local p0 = c + d * (30 * U + L / 2)
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(p0), Size = UDim2.fromOffset(L * 0.2, (width or 4) * U), Rotation = math.deg(a),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 52 }, fx)
		local p1 = c + d * (60 * U + L)
		tween(f, dur, { Position = at(p1), Size = UDim2.fromOffset(L, 1), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(f, dur + 0.05)
	end
end

-- a jagged bolt from a to b: coloured glow + white core per segment, flickered then gone
local function bolt(a, b, color, width, flickers)
	local U = unit()
	local holder = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 52 }, fx)
	local dv = b - a
	local len = dv.Magnitude
	if len < 1 then
		holder:Destroy()
		return
	end
	local perp = V2(-dv.Y, dv.X).Unit
	local pts = { a }
	local n = 7
	for i = 1, n - 1 do
		table.insert(pts, a + dv * (i / n) + perp * (math.random() - 0.5) * len * 0.22)
	end
	table.insert(pts, b)
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local m, d = (p + q) / 2, q - p
		local rot = math.deg(math.atan2(d.Y, d.X))
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(m), Size = UDim2.fromOffset(d.Magnitude + width * U, width * 3 * U), Rotation = rot,
			BackgroundColor3 = color, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 52 }, holder)
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(m), Size = UDim2.fromOffset(d.Magnitude + width * U, math.max(1, width * U)), Rotation = rot,
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 53 }, holder)
	end
	task.spawn(function()
		for _ = 1, flickers or 2 do
			holder.Visible = true
			task.wait(0.05)
			holder.Visible = false
			task.wait(0.03)
		end
		holder.Visible = true
		task.wait(0.07)
		holder:Destroy()
	end)
end

local function slash(c, angle, len, color, width, dur)
	local U = unit()
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(0, width * U), Rotation = angle,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 55 }, fx)
	new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(1, color) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
	tween(f, 0.07, { Size = UDim2.fromOffset(len * U, width * U) })
	task.delay(0.1, function()
		tween(f, dur, { Size = UDim2.fromOffset(len * 1.1 * U, 1), BackgroundTransparency = 1 })
	end)
	Debris:AddItem(f, dur + 0.2)
	-- the dark cut it leaves behind
	local cut = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(len * 0.85 * U, 3 * U), Rotation = angle,
		BackgroundColor3 = C(30, 0, 8), BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 54 }, fx)
	tween(cut, 0.7, { BackgroundTransparency = 1 })
	Debris:AddItem(cut, 0.75)
end

local function glyphPop(c, text, color, size)
	local U = unit()
	local l = label(fx, { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(size * U, size * U), Text = text, FontFace = BLACK_FONT,
		TextColor3 = color, TextTransparency = 0.05, ZIndex = 56 })
	local st = new("UIStroke", { Color = INK, Thickness = 3 * U }, l)
	tween(l, 0.75, { Size = UDim2.fromOffset(size * 2 * U, size * 2 * U), TextTransparency = 1 }, Enum.EasingStyle.Quart)
	tween(st, 0.75, { Transparency = 1 })
	Debris:AddItem(l, 0.8)
end

-- a manga sound effect next to the card
local function word(c, text, color)
	local U = unit()
	local p = c + V2(70 * U, -100 * U)
	local l = label(fx, { AnchorPoint = V2(0.5, 0.5), Position = at(p), Size = UDim2.fromOffset(180 * U, 66 * U), Text = text, FontFace = BLACK_FONT,
		TextColor3 = color, Rotation = math.random(-14, 14), ZIndex = 57 })
	local st = new("UIStroke", { Color = INK, Thickness = 4 * U }, l)
	local sc = new("UIScale", { Scale = 1.8 }, l)
	tween(sc, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.55, function()
		tween(l, 0.3, { TextTransparency = 1 })
		tween(st, 0.3, { Transparency = 1 })
	end)
	Debris:AddItem(l, 0.9)
end

local function puff(c, n, spread)
	local U = unit()
	for _ = 1, n do
		local s = (24 + math.random() * 30) * U
		local p = c + V2((math.random() - 0.5) * spread * U, (math.random() - 0.3) * spread * 0.6 * U)
		local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(p), Size = UDim2.fromOffset(s, s), BackgroundColor3 = C(235, 235, 240),
			BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 52 }, fx)
		corner(f)
		local d = 0.8 + math.random() * 0.5
		tween(f, d, { Position = UDim2.fromOffset(p.X + (math.random() - 0.5) * 40 * U, p.Y - (80 + math.random() * 90) * U),
			Size = UDim2.fromOffset(s * 2.6, s * 2.6), BackgroundTransparency = 1 })
		Debris:AddItem(f, d + 0.05)
	end
end

-- run fn(t 0..1) every frame for dur seconds, then done()
local function animate(dur, fn, done)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = (os.clock() - t0) / dur
		if t >= 1 or not gui.Parent then
			conn:Disconnect()
			if done then
				done()
			end
			return
		end
		fn(t, dt)
	end)
end

-- a ring of chakra dots spiralling in around a growing orb
local function spiral(c, colors, n, r0, dur)
	local U = unit()
	local dots = {}
	for i = 1, n do
		local d = new("Frame", { AnchorPoint = V2(0.5, 0.5), Size = UDim2.fromOffset(11 * U, 11 * U), BackgroundColor3 = colors[(i % #colors) + 1],
			BorderSizePixel = 0, ZIndex = 53 }, fx)
		corner(d)
		dots[i] = d
	end
	local orb = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(0, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0,
		ZIndex = 54 }, fx)
	corner(orb)
	new("UIGradient", { Rotation = 45, Color = ColorSequence.new(WHITE, colors[1]) }, orb)
	animate(dur, function(t)
		local r = (r0 * (1 - t) + 10) * U
		for i, d in ipairs(dots) do
			local a = (i / n) * math.pi * 2 + t * 16
			d.Position = UDim2.fromOffset(c.X + math.cos(a) * r, c.Y + math.sin(a) * r * 0.9)
		end
		local s = 76 * t * U
		orb.Size = UDim2.fromOffset(s, s)
	end, function()
		for _, d in ipairs(dots) do
			d:Destroy()
		end
		tween(orb, 0.2, { Size = UDim2.fromOffset(140 * U, 140 * U), BackgroundTransparency = 1 })
		Debris:AddItem(orb, 0.25)
	end)
end

-- the red eye: opens, spins its three marks, then flares out
local function eye(c, dur)
	local U = unit()
	local R = 66 * U
	local e = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(c), Size = UDim2.fromOffset(R * 2, R * 2), BackgroundColor3 = C(205, 18, 40),
		BorderSizePixel = 0, ZIndex = 53 }, fx)
	corner(e)
	local es = new("UIStroke", { Color = C(10, 6, 8), Thickness = 4 * U }, e)
	local sc = new("UIScale", { Scale = 0.1 }, e)
	local parts = {}
	local pupil = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.26, 0.26),
		BackgroundColor3 = C(10, 6, 8), BorderSizePixel = 0, ZIndex = 54 }, e)
	corner(pupil)
	table.insert(parts, pupil)
	local spin = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		ZIndex = 54 }, e)
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local tm = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.cos(a) * 0.31, 0.5 + math.sin(a) * 0.31),
			Size = UDim2.fromScale(0.16, 0.16), BackgroundColor3 = C(10, 6, 8), BorderSizePixel = 0, ZIndex = 55 }, spin)
		corner(tm)
		table.insert(parts, tm)
	end
	tween(sc, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(spin, dur, { Rotation = 720 }, Enum.EasingStyle.Quad)
	task.delay(dur, function()
		tween(sc, 0.25, { Scale = 2.2 })
		tween(e, 0.25, { BackgroundTransparency = 1 })
		tween(es, 0.25, { Transparency = 1 })
		for _, p in ipairs(parts) do
			tween(p, 0.25, { BackgroundTransparency = 1 })
		end
		Debris:AddItem(e, 0.3)
	end)
end

-- a wide crescent cut: black blade with a burning edge, drawn along an arc in a sweep
local function crescent(c, edge)
	local U = unit()
	local R = 190 * U
	local n = 18
	local a0, a1 = math.rad(200), math.rad(340)
	local ctr = c + V2(0, 70 * U)
	local segs = {}
	for k = 0, n - 1 do
		local t = k / (n - 1)
		local a = a0 + (a1 - a0) * t
		local th = (6 + 24 * math.sin(t * math.pi)) * U
		local p = ctr + V2(math.cos(a), math.sin(a)) * R
		local seg = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(p), Size = UDim2.fromOffset(R * (a1 - a0) / n * 1.3, th),
			Rotation = math.deg(a) + 90, BackgroundColor3 = C(18, 12, 14), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 53 }, fx)
		local st = new("UIStroke", { Color = edge, Thickness = 2 * U, Transparency = 1 }, seg)
		segs[#segs + 1] = { seg, st }
		task.delay(t * 0.12, function()
			seg.BackgroundTransparency = 0
			st.Transparency = 0
		end)
		Debris:AddItem(seg, 0.75)
	end
	task.delay(0.32, function()
		for _, s in ipairs(segs) do
			tween(s[1], 0.3, { BackgroundTransparency = 1 })
			tween(s[2], 0.3, { Transparency = 1 })
		end
	end)
end

-- golden flames licking up the card
local function flames(c, colors, dur, w, h)
	local U = unit()
	local acc = 0
	animate(dur, function(_, dt)
		acc += dt
		while acc > 0.025 do
			acc -= 0.025
			local x = c.X + (math.random() - 0.5) * w
			local y = c.Y + h / 2
			local f = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(14 * U, 30 * U),
				BackgroundColor3 = colors[math.random(#colors)], BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 52 }, fx)
			corner(f)
			local rise = (90 + math.random() * 130) * U
			tween(f, 0.55, { Position = UDim2.fromOffset(x + (math.random() - 0.5) * 20 * U, y - rise), Size = UDim2.fromOffset(4 * U, 48 * U),
				BackgroundTransparency = 1 })
			Debris:AddItem(f, 0.6)
		end
	end)
end

-- each fighter's pick: c = the card's centre, cd = its card
local FX = {}
FX.Limitless = function(c, kit)
	-- Infinity: slow violet rings bloom out of nowhere (and every other card is shoved away, see rivalsFlinch)
	ring(c, kit.accent, 40, 260, 0.9, 5)
	ring(c, WHITE, 30, 200, 0.7, 3, 0.08)
	ring(c, kit.c1, 50, 340, 1.1, 8, 0.16)
	glyphPop(c, "∞", kit.c0, 170)
	sparks(c, { kit.c0, kit.accent, WHITE }, 18, 180, 0.8)
	shake(5, 0.25)
end
FX.Vulpine = function(c, kit)
	-- a spiralling sphere winds up in the palm and bursts
	spiral(c, { C(130, 205, 255), kit.accent, WHITE }, 16, 130, 0.5)
	task.delay(0.45, function()
		ring(c, kit.accent, 20, 230, 0.5, 7)
		ring(c, C(130, 205, 255), 20, 170, 0.4, 4)
		sparks(c, { kit.accent, C(255, 232, 170) }, 22, 210, 0.6)
		shake(8, 0.22)
		word(c, "ドン!", kit.accent)
	end)
end
FX.Godspeed = function(c, kit)
	-- lightning off the card to every edge, flashing twice
	local U = unit()
	for _ = 1, 5 do
		local a = math.random() * math.pi * 2
		bolt(c, c + V2(math.cos(a), math.sin(a)) * math.random(240, 440) * U, kit.c1, 3, 3)
	end
	flash(kit.c0, 0.55, 0.12)
	task.delay(0.15, function()
		flash(kit.c0, 0.7, 0.12)
	end)
	sparks(c, { WHITE, kit.accent }, 16, 130, 0.4)
	shake(6, 0.2)
	word(c, "バチッ", kit.accent)
end
FX.OneForAll = function(c, kit)
	-- green crackle all round it, then one huge shockwave
	local U = unit()
	for i = 1, 8 do
		local d = V2(math.cos(i / 8 * math.pi * 2), math.sin(i / 8 * math.pi * 2))
		bolt(c + d * 40 * U, c + d * (110 + math.random(0, 60)) * U, kit.c1, 2, 2)
	end
	task.delay(0.12, function()
		ring(c, kit.accent, 30, 400, 0.55, 11)
		ring(c, WHITE, 20, 250, 0.4, 4)
		flash(kit.c0, 0.5, 0.22)
		shake(13, 0.32)
		word(c, "ドォン", kit.accent)
	end)
end
FX.Tempest = function(c, kit)
	-- the red eye opens and spins; purple lightning leaps off it
	local U = unit()
	eye(c, 0.65)
	for _ = 1, 3 do
		bolt(c, c + V2(math.random(-280, 280), math.random(-240, -90)) * U, kit.c1, 3, 2)
	end
	flash(C(120, 0, 30), 0.6, 0.3)
	shake(5, 0.2)
end
FX.Carver = function(c, kit)
	-- five cleaves across the card, one after another
	local U = unit()
	for i = 1, 5 do
		task.delay((i - 1) * 0.06, function()
			local ang = (i % 2 == 0 and 35 or -35) + math.random(-12, 12)
			slash(c + V2(math.random(-40, 40), math.random(-60, 60)) * U, ang, 270, kit.c1, 7, 0.25)
			shake(4, 0.1)
			sfx(SND.Hit, 0.35, 1.3 + i * 0.05)
		end)
	end
	task.delay(0.32, function()
		flash(C(150, 0, 20), 0.55, 0.3)
		word(c, "ゴゴゴ", kit.accent)
	end)
end
FX.Shifter = function(c, kit)
	-- a bolt straight down out of the sky, then the steam rolls off
	bolt(V2(c.X + math.random(-30, 30), -20), c, C(255, 230, 140), 6, 3)
	flash(WHITE, 0.4, 0.2)
	shake(15, 0.36)
	task.delay(0.1, function()
		puff(c, 12, 160)
		ring(c, kit.accent, 30, 270, 0.6, 9)
	end)
end
FX.Zangetsu = function(c, kit)
	-- one wide crescent cut, black with a burning edge
	crescent(c, kit.accent)
	task.delay(0.12, function()
		sparks(c, { kit.accent, C(40, 25, 25) }, 20, 190, 0.6)
		shake(9, 0.25)
		word(c, "ズバッ", kit.accent)
	end)
end
FX.Ascendant = function(c, kit, cd)
	-- a golden aura climbs the card, rays burst off it
	local s = cd.body.AbsoluteSize
	flames(c, { kit.c0, kit.accent, C(255, 240, 170) }, 0.7, s.X, s.Y)
	rays(c, kit.accent, 14, 170, 0.6, 5)
	ring(c, C(255, 235, 150), 30, 290, 0.6, 6)
	flash(C(255, 240, 180), 0.55, 0.25)
	shake(8, 0.3)
	word(c, "ゴオオ", kit.accent)
end
FX.default = function(c, kit)
	ring(c, kit.accent, 30, 260, 0.6, 6)
	sparks(c, { kit.c0, kit.accent }, 18, 180, 0.6)
	glyphPop(c, kit.glyph, kit.c0, 140)
	shake(7, 0.25)
end

-- the name sweeping across the header: only one at a time
local currentBanner
local function banner(kit)
	if currentBanner then
		currentBanner:Destroy()
	end
	local U = unit()
	local b = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(-0.7, 0, 0.13, 0), Size = UDim2.new(1.3, 0, 0, 84 * U), Rotation = -3,
		BackgroundColor3 = INK, BackgroundTransparency = 0.06, BorderSizePixel = 0, ZIndex = 60 }, fx)
	currentBanner = b
	new("Frame", { Size = UDim2.new(1, 0, 0, 5 * U), BackgroundColor3 = kit.accent, BorderSizePixel = 0, ZIndex = 61 }, b)
	new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 5 * U), BackgroundColor3 = kit.accent,
		BorderSizePixel = 0, ZIndex = 61 }, b)
	local nm = textStroke(label(b, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(0.5, 0, 0, 52 * U), Text = kit.name,
		ZIndex = 62 }), 3 * U)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(kit.c0, kit.c1) }, nm)
	label(b, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0.72, 0), Size = UDim2.new(0.5, 0, 0, 16 * U), Text = kit.sub .. "  ・  JOINS YOUR TEAM",
		FontFace = Kits.FONT_LABEL, TextColor3 = kit.accent, ZIndex = 62 })
	tween(b, 0.16, { Position = UDim2.fromScale(0.5, 0.13) }, Enum.EasingStyle.Quart)
	task.delay(0.62, function()
		if b.Parent then
			tween(b, 0.18, { Position = UDim2.new(1.7, 0, 0.13, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		end
	end)
	Debris:AddItem(b, 1)
end

---------------------------------------------------------------------------------------------------
-- cards
local cards = {}
local picks = {} -- kit ids in the order picked
local inFlight = {} -- [kit id] = true while its emblem flies to the tray
local hovered
local finishing, busy = false, false

local function isPicked(id)
	return table.find(picks, id) ~= nil
end
local function restScale(cd)
	return isPicked(cd.kit.id) and 1.04 or 1
end

local togglePick -- defined below

for i, kit in ipairs(ROSTER) do
	local row = math.floor((i - 1) / PER_ROW)
	local inRow = math.min(PER_ROW, #ROSTER - row * PER_ROW)
	local col = (i - 1) % PER_ROW
	local rowW = inRow * CW + (inRow - 1) * GAP
	local cx = (gridW - rowW) / 2 + col * (CW + GAP) + CW / 2
	local cy = row * (CH + GAP) + CH / 2
	local holder = new("Frame", { Name = kit.id, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(CW, CH),
		BackgroundTransparency = 1, ZIndex = 10 }, grid)
	local scale = new("UIScale", { Scale = 0 }, holder)
	local glow = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 22, 1, 22), BackgroundColor3 = kit.accent,
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, holder)
	corner(glow, 22)
	local body = new("TextButton", { Name = "Card", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 11 }, holder)
	corner(body, 14)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, kit.c1:Lerp(INK, 0.2)),
		ColorSequenceKeypoint.new(0.6, kit.c1:Lerp(INK, 0.78)), ColorSequenceKeypoint.new(1, INK) }) }, body)
	local edge = stroke(body, INK, 3)
	-- art: a slowly turning burst behind the fighter's glyph
	local star = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(124, 124), BackgroundTransparency = 1,
		ZIndex = 12 }, body)
	for _, r in ipairs({ 0, 22.5, 45, 67.5 }) do
		new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(80, 80), Rotation = r,
			BackgroundColor3 = kit.accent, BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 12 }, star)
	end
	local glyph = textStroke(label(body, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 86), Size = UDim2.fromOffset(104, 104),
		Text = kit.glyph, FontFace = BLACK_FONT, ZIndex = 14 }), 3)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, kit.c0:Lerp(kit.accent, 0.5)) }, glyph)
	textStroke(label(body, { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(40, 22), Text = string.format("%02d", i), TextColor3 = kit.accent,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 14 }), 1.5)
	textStroke(label(body, { Position = UDim2.new(0, 8, 1, -72), Size = UDim2.new(1, -16, 0, 32), Text = kit.name, ZIndex = 14 }), 2)
	label(body, { Position = UDim2.new(0, 8, 1, -38), Size = UDim2.new(1, -16, 0, 14), Text = kit.sub, FontFace = Kits.FONT_LABEL, TextColor3 = kit.accent,
		ZIndex = 14 })
	new("Frame", { AnchorPoint = V2(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = kit.accent, BorderSizePixel = 0,
		ZIndex = 14 }, body)
	-- the hover shine is hidden between sweeps: a rotated card stops clipping, and a parked strip would show
	local shine = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(0, -50, 0.5, 0), Size = UDim2.new(0, 46, 1.7, 0), Rotation = 18,
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.65, BorderSizePixel = 0, Visible = false, ZIndex = 15 }, body)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1) }) }, shine)
	-- the hanko stamp a pick leaves
	local stamp = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(1, -38, 0, 40), Size = UDim2.fromOffset(62, 62), Rotation = -14,
		BackgroundColor3 = HANKO, BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, ZIndex = 17 }, body)
	corner(stamp)
	stroke(stamp, WHITE, 2.5)
	local stampScale = new("UIScale", {}, stamp)
	label(stamp, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.6, 0.6), Text = "選", FontFace = BLACK_FONT,
		ZIndex = 18 })
	local stampNum = label(stamp, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(0.7, 0.22), Text = "#1", ZIndex = 18 })
	-- the lock a full team puts on the rest
	local lock = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(8, 7, 14), BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, ZIndex = 19 }, body)
	local padlock = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(32, 26), BackgroundColor3 = GOLD,
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 21 }, lock)
	corner(padlock, 6)
	local shackle = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(20, 22), BackgroundTransparency = 1,
		ZIndex = 21 }, padlock)
	corner(shackle)
	local shStroke = new("UIStroke", { Color = GOLD, Thickness = 4, Transparency = 1 }, shackle)
	local lockTitle = label(lock, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.new(1, -24, 0, 30), Text = "LATER",
		TextTransparency = 1, ZIndex = 20 })
	local lockTitleStroke = new("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, lockTitle)
	local lockSub = label(lock, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.new(1, -20, 0, 30),
		Text = "UNLOCK FOR\n" .. PRICE_TEXT, FontFace = Kits.FONT_LABEL, TextColor3 = GOLD, TextTransparency = 1, ZIndex = 20 })
	if preOwned[kit.id] then
		local rib = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.5, 0, 0, 28), Rotation = -22,
			BackgroundColor3 = C(70, 220, 130), BorderSizePixel = 0, ZIndex = 21 }, body)
		stroke(rib, INK, 2)
		textStroke(label(rib, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.6, 0, 1, -6), Text = "ALREADY YOURS",
			ZIndex = 22 }), 1.5)
	end
	-- premium (Robux-only): a gold crown and a shimmering PREMIUM over the card, for good - it can't be picked here
	local premium = PREMIUM[kit.id] ~= nil and not preOwned[kit.id]
	local premShine
	if premium then
		local ov = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C(16, 11, 3), BackgroundTransparency = 0.32, BorderSizePixel = 0,
			ZIndex = 19 }, body)
		local crown = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.2), Size = UDim2.fromOffset(46, 30),
			BackgroundTransparency = 1, ZIndex = 21 }, ov)
		for j, x in ipairs({ 0.13, 0.5, 0.87 }) do
			stroke(new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.new(x, 0, 0.5, j == 2 and -7 or -1), Size = UDim2.fromOffset(15, 15),
				Rotation = 45, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 21 }, crown), INK, 2)
		end
		local band = new("Frame", { AnchorPoint = V2(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(46, 13), BackgroundColor3 = GOLD,
			BorderSizePixel = 0, ZIndex = 22 }, crown)
		stroke(band, INK, 2)
		local pl = textStroke(label(ov, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(1, -18, 0, 34), Text = "PREMIUM",
			ZIndex = 21 }), 2)
		premShine = new("UIGradient", { Rotation = 20, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, GOLD), ColorSequenceKeypoint.new(0.44, GOLD),
			ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(0.56, GOLD), ColorSequenceKeypoint.new(1, GOLD2) }) }, pl)
		label(ov, { AnchorPoint = V2(0.5, 0), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.new(1, -20, 0, 28),
			Text = "ROBUX ONLY\nR$" .. tostring(PREMIUM[kit.id]), FontFace = Kits.FONT_LABEL, TextColor3 = GOLD, ZIndex = 21 })
		edge.Color = GOLD
	end
	local hit = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 23 }, body)

	local cd = { kit = kit, i = i, holder = holder, scale = scale, glow = glow, body = body, edge = edge, star = star, glyph = glyph, shine = shine,
		stamp = stamp, stampScale = stampScale, stampNum = stampNum, lock = lock, padlock = padlock, shStroke = shStroke,
		lockTexts = { lockTitle, lockSub }, lockStrokes = { lockTitleStroke }, hit = hit, base = V2(cx, cy), tilt = (i % 2 == 0) and 2.5 or -2.5,
		premium = premium, premShine = premShine }
	cards[kit.id] = cd

	body.MouseEnter:Connect(function()
		if finishing then
			return
		end
		hovered = cd
		tween(scale, 0.14, { Scale = restScale(cd) + 0.05 }, Enum.EasingStyle.Back)
		tween(holder, 0.14, { Rotation = cd.tilt })
		edge.Color = kit.accent
		shine.Position = UDim2.new(0, -50, 0.5, 0)
		shine.Visible = true
		local sw = tween(shine, 0.45, { Position = UDim2.new(1, 50, 0.5, 0) })
		sw.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				shine.Visible = false
			end
		end)
		watermark.Text = kit.glyph
		watermark.TextColor3 = kit.accent
		tint.BackgroundColor3 = kit.c1
		tween(tint, 0.25, { BackgroundTransparency = 0.9 })
		sfx(SND.Hit, 0.1, 1.9)
	end)
	body.MouseLeave:Connect(function()
		if hovered == cd then
			hovered = nil
		end
		if finishing then
			return
		end
		tween(scale, 0.14, { Scale = restScale(cd) })
		tween(holder, 0.14, { Rotation = 0 })
		if not isPicked(kit.id) then
			edge.Color = premium and GOLD or INK
		end
		if not hovered then
			tween(tint, 0.4, { BackgroundTransparency = 1 })
			watermark.TextColor3 = WHITE
		end
	end)
	body.Activated:Connect(function()
		togglePick(kit.id)
	end)
end

---------------------------------------------------------------------------------------------------
-- the team tray + LOCK IN
local SLOT, SLOT_GAP, BTN_W = 66, 14, 236
local trayW = NEED * SLOT + (NEED - 1) * SLOT_GAP
local rowX = (STAGE_W - (trayW + 28 + BTN_W)) / 2
local tray = new("Frame", { Name = "Tray", Position = UDim2.fromOffset(rowX, TRAY_Y), Size = UDim2.fromOffset(trayW, SLOT), BackgroundTransparency = 1, ZIndex = 6 }, stage)
local slots = {}
for n = 1, NEED do
	local f = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset((n - 1) * (SLOT + SLOT_GAP) + SLOT / 2, SLOT / 2),
		Size = UDim2.fromOffset(SLOT, SLOT), BackgroundColor3 = INK, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 6 }, tray)
	corner(f)
	local st = stroke(f, WHITE, 2, 0.6)
	local sc = new("UIScale", {}, f)
	local num = label(f, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.46, 0.46), Text = tostring(n),
		TextColor3 = C(120, 118, 150), ZIndex = 7 })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false, ZIndex = 8 }, f)
	corner(fill)
	local fg = new("UIGradient", { Rotation = 45 }, fill)
	local fglyph = textStroke(label(fill, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7),
		FontFace = BLACK_FONT, ZIndex = 9 }), 2)
	local fname = textStroke(label(f, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(SLOT + 14, 15), Text = "",
		FontFace = Kits.FONT_LABEL, ZIndex = 9 }), 1)
	slots[n] = { frame = f, stroke = st, scale = sc, num = num, fill = fill, grad = fg, glyph = fglyph, name = fname }
end

local btn = new("TextButton", { Name = "LockIn", AutoButtonColor = false, Text = "", Position = UDim2.fromOffset(rowX + trayW + 28, TRAY_Y + 2), Size = UDim2.fromOffset(BTN_W, 62),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 6 }, stage)
corner(btn, 14)
local btnGrad = new("UIGradient", { Rotation = 90 }, btn)
stroke(btn, INK, 3)
local btnScale = new("UIScale", {}, btn)
local btnText = textStroke(label(btn, { Position = UDim2.fromOffset(10, 7), Size = UDim2.new(1, -20, 0, 34), ZIndex = 7 }), 2)
local btnSub = label(btn, { Position = UDim2.new(0, 10, 1, -20), Size = UDim2.new(1, -20, 0, 13), FontFace = Kits.FONT_LABEL, TextColor3 = INK, ZIndex = 7 })
local btnHover = false
btn.MouseEnter:Connect(function()
	btnHover = true
end)
btn.MouseLeave:Connect(function()
	btnHover = false
end)

local toast = label(stage, { AnchorPoint = V2(0.5, 1), Position = UDim2.fromOffset(STAGE_W / 2, TRAY_Y - 4), Size = UDim2.fromOffset(560, 20),
	TextTransparency = 1, ZIndex = 30 })
local toastStroke = new("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, toast)
local toastTok
local function say(text, color)
	local tok = {}
	toastTok = tok
	toast.Text = text
	toast.TextColor3 = color or WHITE
	toast.TextTransparency = 0
	toastStroke.Transparency = 0
	task.delay(1.6, function()
		if toastTok == tok then
			tween(toast, 0.35, { TextTransparency = 1 })
			tween(toastStroke, 0.35, { Transparency = 1 })
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- state -> look
local function setLock(cd, on)
	if cd.locked == on then
		return
	end
	cd.locked = on
	if on then
		cd.lock.Visible = true
		tween(cd.lock, 0.25, { BackgroundTransparency = 0.25 })
		for _, t in ipairs(cd.lockTexts) do
			tween(t, 0.25, { TextTransparency = 0 })
		end
		for _, s in ipairs(cd.lockStrokes) do
			tween(s, 0.25, { Transparency = 0 })
		end
		cd.padlock.BackgroundTransparency = 0
		cd.shStroke.Transparency = 0
		cd.padlock.Position = UDim2.fromScale(0.5, 0.02)
		tween(cd.padlock, 0.35, { Position = UDim2.fromScale(0.5, 0.24) }, Enum.EasingStyle.Bounce)
	else
		tween(cd.lock, 0.15, { BackgroundTransparency = 1 })
		for _, t in ipairs(cd.lockTexts) do
			tween(t, 0.15, { TextTransparency = 1 })
		end
		for _, s in ipairs(cd.lockStrokes) do
			tween(s, 0.15, { Transparency = 1 })
		end
		tween(cd.padlock, 0.15, { BackgroundTransparency = 1 })
		tween(cd.shStroke, 0.15, { Transparency = 1 })
		task.delay(0.16, function()
			if not cd.locked then
				cd.lock.Visible = false
			end
		end)
	end
end

local function refreshTray()
	for n, s in ipairs(slots) do
		local id = picks[n]
		local cd = id and cards[id]
		local show = cd ~= nil and not inFlight[id]
		s.fill.Visible = show
		s.num.Visible = not show
		s.name.Text = show and cd.kit.name or ""
		s.stroke.Color = show and cd.kit.accent or WHITE
		s.stroke.Transparency = show and 0 or 0.6
		if show then
			s.grad.Color = ColorSequence.new(cd.kit.c0, cd.kit.c1)
			s.glyph.Text = cd.kit.glyph
		end
	end
end

local function refreshButton()
	local left = NEED - #picks
	if left <= 0 then
		btnGrad.Color = ColorSequence.new(GOLD, GOLD2)
		btnText.Text = "LOCK IN!"
		btnSub.Text = "START WITH THIS TEAM"
		btnSub.TextColor3 = INK
	else
		btnGrad.Color = ColorSequence.new(C(72, 70, 96), C(40, 38, 58))
		btnText.Text = left == NEED and ("PICK " .. NEED) or ("PICK " .. left .. " MORE")
		btnSub.Text = "TAP A CARD TO ADD IT"
		btnSub.TextColor3 = C(195, 195, 220)
	end
end

local lastCount = 0
local function refreshAll()
	local full = #picks >= NEED
	for id, cd in pairs(cards) do
		local n = table.find(picks, id)
		cd.stamp.Visible = n ~= nil
		if n then
			cd.stampNum.Text = "#" .. n
		else
			cd.glow.BackgroundTransparency = 1
		end
		cd.edge.Color = (n or hovered == cd) and cd.kit.accent or (cd.premium and GOLD or INK)
		cd.edge.Thickness = n and 4 or 3
		setLock(cd, full and not n and not preOwned[id] and not cd.premium)
	end
	counterText.Text = #picks .. "/" .. NEED
	if #picks ~= lastCount then
		counterScale.Scale = 1.3
		tween(counterScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		lastCount = #picks
	end
	refreshTray()
	refreshButton()
end

-- every other card is knocked back from the one picked (Gojo's Infinity shoves them much harder)
local function rivalsFlinch(src, power)
	for _, cd in pairs(cards) do
		if cd ~= src then
			local d = cd.base - src.base
			local dist = d.Magnitude
			local dir = dist > 1 and d.Unit or V2(0, 1)
			local push = (30 * power) / (1 + dist / 380)
			task.delay(dist / 2400, function()
				if finishing then
					return
				end
				local off = cd.base + dir * push
				tween(cd.holder, 0.07, { Position = at(off), Rotation = (dir.X >= 0 and 1 or -1) * 5 * power })
				cd.hit.BackgroundTransparency = 0.55
				tween(cd.hit, 0.35, { BackgroundTransparency = 1 })
				task.delay(0.07, function()
					if not finishing then
						tween(cd.holder, 0.55, { Position = at(cd.base), Rotation = 0 }, Enum.EasingStyle.Elastic)
					end
				end)
			end)
		end
	end
end

local function flyToTray(cd)
	local n = table.find(picks, cd.kit.id)
	local slot = n and slots[n]
	if not slot then
		return
	end
	local U = unit()
	local a, b = centerOf(cd.glyph), centerOf(slot.frame)
	local e = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = at(a), Size = UDim2.fromOffset(SLOT * U, SLOT * U), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ZIndex = 58 }, fx)
	corner(e)
	new("UIGradient", { Rotation = 45, Color = ColorSequence.new(cd.kit.c0, cd.kit.c1) }, e)
	stroke(e, INK, 2)
	textStroke(label(e, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.7, 0.7), Text = cd.kit.glyph,
		FontFace = BLACK_FONT, ZIndex = 59 }), 2)
	inFlight[cd.kit.id] = true
	refreshTray()
	tween(e, 0.4, { Position = at(b) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.4, function()
		e:Destroy()
		inFlight[cd.kit.id] = nil
		refreshTray()
		local n2 = table.find(picks, cd.kit.id)
		local s2 = n2 and slots[n2]
		if s2 then
			s2.scale.Scale = 1.35
			tween(s2.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			ring(centerOf(s2.frame), cd.kit.accent, 24, 64, 0.35, 3)
		end
	end)
end

local function nope(cd)
	for k = 1, 5 do
		task.delay(k * 0.04, function()
			cd.holder.Rotation = (k % 2 == 0) and -4 or 4
		end)
	end
	task.delay(0.24, function()
		cd.holder.Rotation = 0
	end)
	sfx(SND.Hit, 0.25, 0.6)
end

local function pickFx(cd)
	local kit = cd.kit
	local c = centerOf(cd.body)
	cd.scale.Scale = 1.25
	tween(cd.scale, 0.35, { Scale = 1.04 }, Enum.EasingStyle.Back)
	cd.stamp.Visible = true
	cd.stampScale.Scale = 2.4
	tween(cd.stampScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	tint.BackgroundColor3 = kit.c1
	tint.BackgroundTransparency = 0.6
	tween(tint, 0.8, { BackgroundTransparency = hovered and 0.9 or 1 })
	flash(kit.c0, 0.8, 0.2)
	rivalsFlinch(cd, kit.id == "Limitless" and 2.4 or 1)
	banner(kit)
	sfx(SND.Hit, 0.5, 1.1)
	local s = KIT_SND[kit.id]
	if s then
		sfx(s[1], s[2], s[3])
	end
	local ok, err = pcall(FX[kit.id] or FX.default, c, kit, cd)
	if not ok then
		warn("[StarterSelect] effect failed: " .. tostring(err))
	end
	flyToTray(cd)
end

local function unpickFx(cd)
	tween(cd.stampScale, 0.15, { Scale = 0 })
	cd.scale.Scale = 0.9
	tween(cd.scale, 0.3, { Scale = hovered == cd and 1.05 or 1 }, Enum.EasingStyle.Back)
	nope(cd)
	puff(centerOf(cd.body), 5, 70)
	sfx(SND.Swing, 0.3, 0.7)
end

function togglePick(id)
	if busy or finishing then
		return
	end
	local cd = cards[id]
	if preOwned[id] then
		say(cd.kit.name .. " IS ALREADY YOURS", cd.kit.accent)
		nope(cd)
		return
	end
	if cd.premium then
		-- Robux-only: a gold glint and a pointer to where it's sold
		say(cd.kit.name .. " IS PREMIUM - R$" .. tostring(PREMIUM[id]) .. ", ROBUX ONLY, FROM THE CHARACTER MENU", GOLD)
		nope(cd)
		local c = centerOf(cd.body)
		sparks(c, { GOLD, GOLD2, WHITE }, 18, 160, 0.5)
		ring(c, GOLD, 30, 160, 0.45, 4)
		return
	end
	local idx = table.find(picks, id)
	if idx then
		table.remove(picks, idx)
		unpickFx(cd)
	else
		if #picks >= NEED then
			say("TEAM FULL - TAP A PICKED FIGHTER TO SWAP THEM OUT", RED)
			nope(cd)
			return
		end
		table.insert(picks, id)
		pickFx(cd)
	end
	refreshAll()
end

---------------------------------------------------------------------------------------------------
-- LOCK IN and the finale
local renderConn

local function wipeOut()
	local w = new("Frame", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(-1.3, 0.5), Size = UDim2.fromScale(1.7, 3), Rotation = 14,
		BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 10 }, gui)
	for _, x in ipairs({ 0, 1 }) do
		new("Frame", { AnchorPoint = V2(x, 0), Position = UDim2.fromScale(x, 0), Size = UDim2.new(0, 16, 1, 0), BackgroundColor3 = GOLD, BorderSizePixel = 0,
			ZIndex = 11 }, w)
	end
	tween(w, 0.42, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
	task.delay(0.42, function()
		root.Visible = false
		fx.Visible = false
		tween(w, 0.5, { Position = UDim2.fromScale(2.3, 0.5) }, Enum.EasingStyle.Quart)
		task.delay(0.55, function()
			if renderConn then
				renderConn:Disconnect()
			end
			gui:Destroy()
		end)
	end)
end

local function finale()
	finishing = true
	hovered = nil
	if currentBanner then
		currentBanner:Destroy()
	end
	tween(tint, 0.3, { BackgroundTransparency = 1 })
	watermark.Text = "闘"
	tween(tray, 0.3, { Position = UDim2.fromOffset(rowX, TRAY_Y + 160) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(btn, 0.3, { Position = UDim2.fromOffset(rowX + trayW + 28, TRAY_Y + 162) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(counterScale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	-- the rest of the roster falls away
	for id, cd in pairs(cards) do
		if not isPicked(id) then
			tween(cd.holder, 0.4, { Position = UDim2.fromOffset(cd.base.X, cd.base.Y + 140), Rotation = math.random(-25, 25) }, Enum.EasingStyle.Back,
				Enum.EasingDirection.In)
			tween(cd.scale, 0.4, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
	end
	-- the team lines up across the middle
	local n = #picks
	for i, id in ipairs(picks) do
		local cd = cards[id]
		cd.holder.ZIndex = 12
		local x = gridW / 2 + (i - (n + 1) / 2) * (CW + 26)
		task.delay(0.25 + 0.09 * i, function()
			tween(cd.holder, 0.45, { Position = UDim2.fromOffset(x, gridH / 2), Rotation = 0 }, Enum.EasingStyle.Back)
			tween(cd.scale, 0.45, { Scale = 1.12 }, Enum.EasingStyle.Back)
			task.delay(0.42, function()
				ring(centerOf(cd.body), cd.kit.accent, 50, 170, 0.5, 5)
				sfx(SND.Hit, 0.4, 0.9 + i * 0.08)
			end)
		end)
	end
	local tFight = 0.25 + 0.09 * n + 0.75
	task.delay(tFight, function()
		title.Text = "YOUR TEAM IS READY"
		titleScale.Scale = 1.4
		tween(titleScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		sub.Text = "Unlock the rest any time from CHARACTER, top-left."
		local U = unit()
		local c = V2(fx.AbsoluteSize.X / 2, fx.AbsoluteSize.Y / 2)
		-- text tops out at 100 px (TextScaled re-fits after a UIScale), so the stamp is a fixed 100 px drawn by a UIScale
		local f = textStroke(label(fx, { AnchorPoint = V2(0.5, 0.5), Position = at(c + V2(0, 175 * U)), Size = UDim2.fromOffset(320, 110), Text = "FIGHT!",
			TextScaled = false, TextSize = 100, Rotation = -8, ZIndex = 65 }), 4)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(255, 250, 220), GOLD2) }, f)
		local fs = new("UIScale", { Scale = 5 * U }, f)
		tween(fs, 0.28, { Scale = 2 * U }, Enum.EasingStyle.Back)
		flash(WHITE, 0.25, 0.4)
		shake(16, 0.4)
		lineBoost = 7
		sfx(SND.HitFinal, 0.9, 0.8)
		ring(c, GOLD, 60, 720, 0.8, 12)
		rays(c, GOLD, 22, 380, 0.7, 6)
	end)
	task.delay(tFight + 1.3, wipeOut)
end

btn.Activated:Connect(function()
	if busy or finishing then
		return
	end
	local left = NEED - #picks
	if left > 0 then
		say("PICK " .. left .. " MORE FIGHTER" .. (left > 1 and "S" or ""), RED)
		btnScale.Scale = 0.92
		tween(btnScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		return
	end
	if not ShopRequest then
		say("SERVER NOT READY - TRY AGAIN", RED)
		return
	end
	busy = true
	btnText.Text = "..."
	local ok, a, b = pcall(function()
		return ShopRequest:InvokeServer("pickStarters", table.clone(picks))
	end)
	busy = false
	if ok and a then
		finale()
	else
		say(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
		refreshButton()
	end
end)

---------------------------------------------------------------------------------------------------
-- every frame: fit the stage, run the speed lines, pulse the picks, breathe the button, shake
renderConn = RunService.RenderStepped:Connect(function(dt)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or V2(1280, 720)
	stageScale.Scale = math.clamp(math.min(vp.X / (STAGE_W + 40), vp.Y / (STAGE_H + 30)), 0.4, 1.3)
	local t = os.clock()
	for _, l in ipairs(lines) do
		l.x -= l.speed * dt * lineBoost
		if l.x + l.w < -0.15 then
			l.x = 1.05 + math.random() * 0.3
			l.y = math.random()
		end
		l.f.Position = UDim2.fromScale(l.x, l.y)
		l.f.Size = UDim2.new(l.w, 0, 0, l.h)
	end
	for id, cd in pairs(cards) do
		local on = isPicked(id)
		if on then
			cd.glow.BackgroundTransparency = 0.5 + 0.18 * math.sin(t * 4 + cd.i)
		end
		cd.star.Rotation = (cd.star.Rotation + dt * (on and 45 or (hovered == cd and 120 or 10))) % 360
		if cd.premShine and not finishing then
			cd.premShine.Offset = V2(((t * 0.55 + cd.i * 0.3) % 2) - 1, 0)
			if hovered ~= cd then
				cd.edge.Color = GOLD:Lerp(GOLD2, 0.5 + 0.5 * math.sin(t * 3 + cd.i))
			end
		end
	end
	if not finishing then
		local ready = #picks >= NEED and not busy
		local target = (btnHover and 1.05 or 1) + (ready and 0.035 * math.sin(t * 6) or 0)
		btnScale.Scale += (target - btnScale.Scale) * math.min(1, dt * 14)
	end
	local rem = shakeUntil - t
	if rem > 0 then
		local k = shakeAmp * (rem / shakeDur)
		stage.Position = UDim2.new(0.5, (math.random() - 0.5) * 2 * k, 0.5, (math.random() - 0.5) * 2 * k)
	else
		stage.Position = UDim2.fromScale(0.5, 0.5)
	end
end)

-- (2026-11-07 perks integration) the team can arrive from elsewhere while this screen is up - an All Fighters purchase
-- (or its receipt redelivered on join) makes ShopService set StarterPicked = true - and LOCK IN would then only ever
-- answer ALREADY PICKED, trapping the player here. Close the screen instead (never during our own LOCK IN: its finale
-- closes it).
player:GetAttributeChangedSignal("StarterPicked"):Connect(function()
	if player:GetAttribute("StarterPicked") == true and not finishing and not busy and gui.Parent then
		finishing = true
		wipeOut()
	end
end)

-- opening: the title slams in, then the cards are dealt one by one
refreshAll()
titleScale.Scale = 2.6
title.TextTransparency = 1
tween(titleScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
tween(title, 0.2, { TextTransparency = 0 })
task.delay(0.3, function()
	shake(6, 0.2)
	sfx(SND.HitFinal, 0.5, 1.2)
end)
for _, kit in ipairs(ROSTER) do
	local cd = cards[kit.id]
	cd.holder.Rotation = cd.tilt * 4
	task.delay(0.35 + cd.i * 0.07, function()
		if finishing then
			return
		end
		tween(cd.scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(cd.holder, 0.32, { Rotation = 0 }, Enum.EasingStyle.Back)
		sfx(SND.Swing, 0.15, 1.4 + cd.i * 0.03)
	end)
end
