--!nocheck
-- ReplicatedStorage.HudShared.CardArt.Icons (2026-11-10): comic 2D icons for the shop's ABSTRACT items - the yen
-- packs, perks with no fighter to show, the random rolls and the title nameplates. (2026-11-14) Also every sandbox item
-- (sliders, Spawn Limit, Kill Effects Pack, Nuke, Moon Gravity, Dummy Rain) and the five gadgets. CardArt (the figure owner) calls:
--   Icons.draw(container: GuiObject, item: table, opts: { zIndex: number? }?) -> boolean
-- It adds ONE child, "CardArt_Icon" (a centred square filling the container), and returns true; or it adds nothing
-- and returns false when it has no art for the item. It never errors (a failed build is destroyed and warned) and it
-- is static: no connections, no per-frame work. Icons.has(item) answers without drawing.
--
-- Pure UI, no image ids: Frames, UICorner, UIStroke, UIGradient, rotated frames and Bangers lettering.
-- Coordinates are UNIT squares (0..1 of the icon, y down; rotations clockwise like GuiObject.Rotation).
-- Ink: every outline is a UIStroke in ScaledSize mode, whose Thickness is a fraction of the stroked object's SMALLER
-- side, so `weight / min(w, h)` draws one ink weight (a fraction of the ICON) at 44 px and at 160 px alike, and it
-- follows UIScale pop-in tweens for free. union() draws a multi-piece shape twice (outlines, then the fills on top)
-- so the shape gets ONE outline round its silhouette instead of seams between its pieces.
local Icons = {}

local C = Color3.fromRGB
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local INKC = C(14, 12, 24) -- the game's ink
local NIGHT = C(30, 27, 50)
local GOLD = C(255, 205, 70)
local STICKER = C(235, 52, 64)
local PLUS = C(56, 198, 104)
local INK = 0.042 -- outline weight as a fraction of the icon (about 2 px at 44, 2.7 at 64, 6.7 at 160)
local THIN = 0.022

local FONT = Font.fromEnum(Enum.Font.GothamBold)
pcall(function()
	local kits = script.Parent and script.Parent.Parent and script.Parent.Parent:FindFirstChild("Kits")
	if kits then
		FONT = require(kits).FONT_PUNCH or FONT
	end
end)

-- colour + geometry helpers -----------------------------------------------------------------------------------
local function lit(c, t)
	return c:Lerp(WHITE, t)
end
local function drk(c, t)
	return c:Lerp(BLACK, t)
end
local function col3(v, fallback)
	return typeof(v) == "Color3" and v or fallback
end
-- the point (dx, dy) of a frame turned `deg` clockwise about (cx, cy)
local function rp(cx, cy, dx, dy, deg)
	local a = math.rad(deg or 0)
	local cs, sn = math.cos(a), math.sin(a)
	return cx + dx * cs - dy * sn, cy + dx * sn + dy * cs
end
local function nseq(points)
	local kp = table.create(#points)
	for i, p in ipairs(points) do
		kp[i] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(kp)
end
local function cseq(points)
	local kp = table.create(#points)
	for i, p in ipairs(points) do
		kp[i] = ColorSequenceKeypoint.new(p[1], p[2])
	end
	return ColorSequence.new(kp)
end
local FADE_ENDS = nseq({ { 0, 1 }, { 0.3, 0 }, { 0.7, 0 }, { 1, 1 } })
local FADE_TAIL = nseq({ { 0, 0 }, { 0.6, 0.05 }, { 1, 0.7 } })

-- primitives ---------------------------------------------------------------------------------------------------
local function nextZ(c)
	c.z += 1
	return c.z
end

local function stroke(obj, weight, minSide, color)
	local s = Instance.new("UIStroke")
	s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	s.Thickness = weight / math.max(minSide, 0.02)
	s.Color = color or INKC
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = obj
	return s
end

local function gradient(obj, color, rot, transparency)
	local g = Instance.new("UIGradient")
	g.Color = color
	g.Rotation = rot or 90
	if transparency then
		g.Transparency = transparency
	end
	g.Parent = obj
	return g
end

-- One Frame centred on (x, y), w x h of the icon, filled `color`. o: rot, round (true = pill / circle, or a 0..0.5
-- corner scale), ink (outline weight), inkc, t (transparency), shade (a 2-tone top-lit fill from color), c0/c1 (an
-- explicit 2-tone), cs (a ColorSequence fill), grot (gradient rotation, default 90 = top to bottom), ts (transparency)
local function piece(c, x, y, w, h, color, o)
	o = o or {}
	local f = Instance.new("Frame")
	f.Name = "Ink"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = o.rot or 0
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = c.outline and 1 or (o.t or 0)
	f.ZIndex = nextZ(c)
	if o.round then
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(o.round == true and 0.5 or o.round, 0)
		k.Parent = f
	end
	if o.ink then
		stroke(f, o.ink, math.min(w, h), o.inkc)
	end
	if not c.outline and (o.shade or o.c1 or o.cs or o.ts) then
		local seq = o.cs
		if not seq then
			local a, b = o.c0 or color, o.c1 or color
			if o.shade then
				a, b = lit(color, 0.4), drk(color, 0.22)
			end
			seq = ColorSequence.new(a, b)
		end
		f.BackgroundColor3 = WHITE
		gradient(f, seq, o.grot, o.ts)
	end
	f.Parent = c.root
	return f
end

local function circle(c, x, y, d, color, o)
	o = o or {}
	o.round = true
	return piece(c, x, y, d, d, color, o)
end

-- a bar from (x1, y1) to (x2, y2); o.cap lengthens it (half at each end) so joints overlap
local function seg(c, x1, y1, x2, y2, w, color, o)
	o = o or {}
	local dx, dy = x2 - x1, y2 - y1
	o.rot = math.deg(math.atan2(dy, dx))
	return piece(c, (x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy) + (o.cap or 0), w, color, o)
end

-- outline only: a ring of diameter d whose stroke (weight th of the icon) sits just outside d
local function ring(c, x, y, d, th, color)
	local f = piece(c, x, y, d, d, WHITE, { round = true, t = 1 })
	return f, stroke(f, th, d, color)
end
-- the part of a ring past `cut` (0..1) along the direction `dir` (0 = right, 90 = down, 180 = left, 270 = up)
local function arc(c, x, y, d, th, color, dir, cut)
	local _, s = ring(c, x, y, d, th, color)
	gradient(s, ColorSequence.new(WHITE), dir, nseq({ { 0, 1 }, { cut, 1 }, { math.min(cut + 0.08, 0.99), 0 }, { 1, 0 } }))
end

local function union(c, draw, weight)
	c.outline = true
	draw(weight or INK)
	c.outline = false
	draw(nil)
end

-- comic lettering: Bangers, ink-stroked, optionally a c0 -> c1 top-to-bottom gradient like the in-game titles
local function text(c, x, y, w, h, str, color, o)
	o = o or {}
	local t = Instance.new("TextLabel")
	t.Name = "Letters"
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
	t.Rotation = o.rot or 0
	t.BackgroundTransparency = 1
	t.ZIndex = nextZ(c)
	t.FontFace = FONT
	t.Text = str
	t.TextScaled = true
	t.TextWrapped = true -- (measured: a TextScaled label with TextWrapped = false stayed at TextSize 8)
	t.TextColor3 = color
	if o.ink ~= false then
		stroke(t, o.ink or INK * 0.85, math.min(w, h))
	end
	if o.c1 then
		t.TextColor3 = WHITE
		gradient(t, ColorSequence.new(color, o.c1), 90)
	end
	t.Parent = c.root
	return t
end

-- comic vocabulary ---------------------------------------------------------------------------------------------
-- a "pow" seal: three squares turned 30 deg apart = a 12-point star with one outline
local function seal(c, x, y, d, color, rot)
	local s = d / 1.414
	union(c, function(ink)
		for i = 0, 2 do
			piece(c, x, y, s, s, color, { rot = (rot or 0) + i * 30, ink = ink })
		end
	end)
end

local function sticker(c, x, y, d, str, color, rot)
	seal(c, x, y, d, color, rot)
	text(c, x, y + d * 0.02, d * 0.74, d * 0.5, str, WHITE, { rot = rot })
end

-- a 4-point twinkle: thin long arms, thicker short arms and a diamond core = a stepped taper (not a "+")
local function sparkle(c, x, y, s, color)
	color = color or WHITE
	union(c, function(ink)
		piece(c, x, y, s, s * 0.09, color, { round = true, ink = ink })
		piece(c, x, y, s * 0.09, s, color, { round = true, ink = ink })
		piece(c, x, y, s * 0.56, s * 0.18, color, { round = true, ink = ink })
		piece(c, x, y, s * 0.18, s * 0.56, color, { round = true, ink = ink })
		piece(c, x, y, s * 0.3, s * 0.3, color, { rot = 45, ink = ink })
	end, THIN * 0.8)
end

-- halftone dots growing toward the lower-right corner (mirror = lower-left)
local function halftone(c, color, t, mirror)
	for j = 0, 4 do
		for i = 0, 4 do
			local k = i + j - 3
			if k > 0 then
				local px = (i + 0.5) / 5
				circle(c, mirror and 1 - px or px, (j + 0.5) / 5, 0.04 + 0.028 * k, color, { t = t })
			end
		end
	end
end

-- speed lines at `deg`; each line {perpendicular offset, offset along, length, width?} from the icon centre
local function speedLines(c, deg, color, lines, t)
	for _, l in ipairs(lines) do
		local x, y = rp(0.5, 0.5, l[2], l[1], deg)
		piece(c, x, y, l[3], l[4] or 0.026, color, { rot = deg, round = true, t = t, ts = FADE_ENDS })
	end
end

-- a glow: n bars through (x, y) fading at both ends
local function rays(c, x, y, len, w, color, n, t, rot0)
	for i = 0, n - 1 do
		piece(c, x, y, len, w, color, { rot = (rot0 or 0) + i * 180 / n, t = t, ts = FADE_ENDS })
	end
end

local function smiley(c, x, y, d, color)
	circle(c, x, y, d, color, { ink = INK, shade = true })
	piece(c, x - d * 0.17, y - d * 0.1, d * 0.11, d * 0.22, INKC, { round = true })
	piece(c, x + d * 0.17, y - d * 0.1, d * 0.11, d * 0.22, INKC, { round = true })
	arc(c, x, y - d * 0.02, d * 0.58, d * 0.09, INKC, 90, 0.62)
end

-- ">" with its tip at (tx, ty)
local function chevron(c, tx, ty, arm, w, color, ink)
	local h = arm * 0.7071
	seg(c, tx - h, ty - h, tx, ty, w, color, { cap = w * 0.5, ink = ink, round = 0.2 })
	seg(c, tx - h, ty + h, tx, ty, w, color, { cap = w * 0.5, ink = ink, round = 0.2 })
end

local function bolt(c, pts, widths, color)
	union(c, function(ink)
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			seg(c, a[1], a[2], b[1], b[2], widths[i], color, { cap = widths[i] * 0.8, ink = ink })
		end
	end)
	local a, b = pts[1], pts[2]
	seg(c, a[1] + 0.005, a[2] + 0.04, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, widths[1] * 0.26, WHITE, { round = true, t = 0.15 })
end

-- yen ----------------------------------------------------------------------------------------------------------
local YEN_INK = C(138, 72, 12)

local function coinFace(c, x, y, d, rot, color)
	circle(c, x, y, d, color, { ink = INK, c0 = lit(color, 0.5), c1 = drk(color, 0.18) })
	ring(c, x, y, d * 0.72, THIN, drk(color, 0.42))
	text(c, x, y + d * 0.03, d * 0.56, d * 0.56, "¥", YEN_INK, { rot = rot, ink = false })
	piece(c, x - d * 0.2, y - d * 0.3, d * 0.24, d * 0.07, WHITE, { rot = -32, round = true, t = 0.1 })
end

local function coinStack(c, x, base, w, n, color)
	for i = 0, n - 1 do
		piece(c, x + (i % 2 == 0 and -0.008 or 0.008), base - i * w * 0.17, w, w * 0.27, color,
			{ round = true, ink = INK, c0 = lit(color, 0.3), c1 = drk(color, 0.32) })
	end
end

local function banknote(c, x, y, w, h, rot)
	piece(c, x, y, w, h, WHITE, { rot = rot, round = 0.12, ink = INK, c0 = C(190, 242, 178), c1 = C(92, 184, 110) })
	local f = piece(c, x, y, w * 0.84, h * 0.66, WHITE, { rot = rot, round = 0.12, t = 1 })
	stroke(f, THIN * 0.8, h * 0.66, C(42, 124, 72))
	circle(c, x, y, h * 0.5, C(228, 252, 216), { ink = THIN })
	text(c, x, y + h * 0.02, h * 0.42, h * 0.42, "¥", C(34, 112, 62), { rot = rot, ink = false })
end

local function yenTier(item)
	local amount = tonumber(item.yen)
	if amount then
		return amount >= 25000 and 4 or amount >= 10000 and 3 or amount >= 4000 and 2 or 1
	end
	return math.clamp(tonumber(string.match(tostring(item.id), "^Yen(%d)$")) or 1, 1, 4)
end

-- Yen1..Yen4: the pile grows with the pack - 1 stack, 2 stacks, + a banknote and a glow, + 2 notes and a bigger coin
local function drawYen(c, item)
	local gold = col3(item.color, GOLD)
	local n = yenTier(item)
	halftone(c, gold, 0.62)
	if n >= 3 then
		rays(c, 0.5, 0.52, 1.08, 0.13, gold, 6, 0.5, 12)
	end
	if n == 4 then
		banknote(c, 0.4, 0.33, 0.64, 0.34, -20)
	end
	if n >= 3 then
		banknote(c, 0.58, 0.35, 0.64, 0.34, 10)
	end
	if n == 1 then
		coinStack(c, 0.33, 0.84, 0.38, 3, gold)
	elseif n == 2 then
		coinStack(c, 0.26, 0.86, 0.36, 4, gold)
		coinStack(c, 0.75, 0.86, 0.34, 2, gold)
	elseif n == 3 then
		coinStack(c, 0.23, 0.88, 0.34, 5, gold)
		coinStack(c, 0.77, 0.88, 0.34, 3, gold)
	else
		coinStack(c, 0.2, 0.9, 0.34, 6, gold)
		coinStack(c, 0.8, 0.9, 0.34, 5, gold)
	end
	local d = ({ 0.5, 0.54, 0.56, 0.6 })[n]
	coinFace(c, n == 1 and 0.6 or 0.5, n == 1 and 0.55 or 0.62, d, 8, gold)
	sparkle(c, 0.83, 0.17, 0.2)
	if n >= 2 then
		sparkle(c, 0.13, 0.24, 0.14)
	end
	if n == 4 then
		sparkle(c, 0.9, 0.6, 0.12)
	end
end

-- YenX2: one big coin + an "x2" pow sticker
local function drawYenX2(c, item)
	local gold = col3(item.color, GOLD)
	halftone(c, gold, 0.62, true)
	speedLines(c, -30, lit(gold, 0.35), { { -0.36, -0.12, 0.42 }, { -0.25, 0.2, 0.3 }, { 0.33, -0.22, 0.36 }, { 0.42, 0.1, 0.3 } }, 0.25)
	coinFace(c, 0.43, 0.58, 0.7, -10, gold)
	sticker(c, 0.75, 0.25, 0.46, "x2", STICKER, 12)
	sparkle(c, 0.14, 0.18, 0.18)
end

-- Cooldowns: a stopwatch spinning (motion arcs) + a fast-forward chevron
local function drawCooldowns(c, item)
	local col = col3(item.color, C(90, 200, 255))
	local cx, cy = 0.45, 0.55
	halftone(c, col, 0.62)
	arc(c, cx, cy, 0.8, 0.034, lit(col, 0.3), 225, 0.6)
	arc(c, cx, cy, 0.95, 0.026, lit(col, 0.3), 225, 0.7)
	arc(c, cx, cy, 0.8, 0.034, lit(col, 0.3), 45, 0.68)
	piece(c, cx, 0.22, 0.09, 0.1, drk(col, 0.15), { ink = INK })
	piece(c, cx, 0.165, 0.22, 0.08, col, { ink = INK, round = 0.4, shade = true })
	local bx, by = rp(cx, cy, 0, -0.34, 45)
	piece(c, bx, by, 0.08, 0.12, drk(col, 0.15), { ink = INK, rot = 45, round = 0.2 })
	circle(c, cx, cy, 0.62, col, { ink = INK, shade = true })
	circle(c, cx, cy, 0.47, C(246, 250, 255), { ink = THIN })
	arc(c, cx, cy, 0.2, 0.09, lit(col, 0.2), 315, 0.45)
	for i = 0, 3 do
		local tx, ty = rp(cx, cy, 0, -0.185, i * 90)
		piece(c, tx, ty, 0.035, 0.07, INKC, { rot = i * 90, round = 0.5 })
	end
	seg(c, cx, cy, cx + 0.12, cy - 0.13, 0.045, C(235, 60, 70), { round = 0.5, cap = 0.03 })
	circle(c, cx, cy, 0.07, INKC)
	union(c, function(ink)
		chevron(c, 0.8, 0.83, 0.19, 0.075, C(255, 222, 70), ink)
		chevron(c, 0.94, 0.83, 0.19, 0.075, C(255, 222, 70), ink)
	end)
end

-- Meteor: a burning rock streaking down over a tiny night skyline
local function drawMeteor(c, item)
	local col = col3(item.color, C(255, 120, 40))
	local BUILDINGS = { { 0.07, 0.14, 0.2 }, { 0.2, 0.14, 0.32 }, { 0.33, 0.12, 0.18 }, { 0.47, 0.15, 0.38 }, { 0.61, 0.12, 0.24 },
		{ 0.74, 0.14, 0.33 }, { 0.88, 0.14, 0.22 } }
	union(c, function(ink)
		for _, b in ipairs(BUILDINGS) do
			piece(c, b[1], 0.97 - b[3] / 2, b[2], b[3], NIGHT, { ink = ink })
		end
	end)
	for _, w in ipairs({ { 0.2, 0.74 }, { 0.2, 0.83 }, { 0.47, 0.68 }, { 0.5, 0.77 }, { 0.44, 0.86 }, { 0.74, 0.74 }, { 0.77, 0.83 }, { 0.61, 0.85 }, { 0.88, 0.85 } }) do
		piece(c, w[1], w[2], 0.032, 0.038, C(255, 214, 110))
	end
	local hx, hy, ang = 0.35, 0.47, -38
	speedLines(c, ang, WHITE, { { -0.3, 0.12, 0.3 }, { 0.3, 0.2, 0.26 }, { -0.42, 0.3, 0.2 } }, 0.3)
	local function along(dist, side)
		return rp(hx, hy, dist, side, ang)
	end
	-- the tail tapers in steps: {centre along the path, length, width, side offset, extra turn}
	local TONGUES = { { 0.16, 0.42, 0.3, 0, 0 }, { 0.3, 0.5, 0.2, -0.045, -5 }, { 0.36, 0.56, 0.12, 0.07, 7 }, { 0.5, 0.48, 0.07, -0.02, -2 } }
	union(c, function(ink)
		for _, t in ipairs(TONGUES) do
			local x, y = along(t[1], t[4])
			piece(c, x, y, t[2], t[3], C(240, 70, 30), { rot = ang + t[5], round = true, ink = ink })
		end
	end)
	for _, t in ipairs({ { 0.14, 0.34, 0.19, 0, 0 }, { 0.28, 0.36, 0.1, -0.035, -5 } }) do
		local x, y = along(t[1], t[4])
		piece(c, x, y, t[2], t[3], col, { rot = ang + t[5], round = true, ts = FADE_TAIL, c0 = lit(col, 0.2), c1 = col, grot = 0 })
	end
	local x, y = along(0.1, 0)
	piece(c, x, y, 0.24, 0.11, C(255, 232, 100), { rot = ang, round = true })
	circle(c, hx, hy, 0.27, C(130, 96, 84), { ink = INK, c0 = C(156, 118, 100), c1 = C(76, 54, 54) })
	circle(c, hx - 0.04, hy + 0.03, 0.075, C(84, 60, 58))
	circle(c, hx + 0.05, hy - 0.05, 0.05, C(84, 60, 58))
	circle(c, hx + 0.035, hy + 0.07, 0.04, C(84, 60, 58))
	arc(c, hx, hy, 0.17, 0.045, C(255, 220, 80), 135, 0.5)
	circle(c, 0.16, 0.66, 0.045, C(255, 190, 70), { ink = THIN })
	circle(c, 0.12, 0.46, 0.03, C(255, 190, 70))
end

-- UltNow: a lightning bolt over a battery charged full
local function drawUltNow(c, item)
	local col = col3(item.color, C(255, 90, 200))
	halftone(c, col, 0.62)
	piece(c, 0.86, 0.6, 0.08, 0.18, C(150, 150, 172), { ink = INK, round = 0.3 })
	piece(c, 0.46, 0.6, 0.72, 0.42, C(34, 30, 54), { ink = INK, round = 0.14 })
	for i = 0, 3 do
		piece(c, 0.2275 + i * 0.155, 0.6, 0.13, 0.3, col, { round = 0.18, shade = true })
	end
	local zap = lit(col, 0.45)
	seg(c, 0.12, 0.2, 0.2, 0.28, 0.032, zap, { round = true })
	seg(c, 0.08, 0.36, 0.19, 0.38, 0.032, zap, { round = true })
	seg(c, 0.8, 0.12, 0.74, 0.22, 0.032, zap, { round = true })
	seg(c, 0.9, 0.26, 0.8, 0.3, 0.032, zap, { round = true })
	bolt(c, { { 0.66, 0.03 }, { 0.41, 0.48 }, { 0.62, 0.46 }, { 0.37, 0.88 }, { 0.33, 0.97 } }, { 0.15, 0.13, 0.11, 0.05 }, C(255, 232, 70))
end

-- EmoteSlots: a fanned hand of emote cards + "+4"
local function drawEmoteSlots(c, item)
	local col = col3(item.color, C(255, 230, 120))
	halftone(c, col, 0.62, true)
	for _, k in ipairs({ { -22, C(110, 200, 255) }, { 22, C(255, 130, 180) }, { 0, C(252, 250, 244) } }) do
		local x, y = rp(0.48, 0.98, 0, -0.46, k[1])
		piece(c, x, y, 0.4, 0.56, k[2], { rot = k[1], round = 0.14, ink = INK, shade = k[1] ~= 0 })
		if k[1] ~= 0 then
			local mx, my = rp(0.48, 0.98, 0, -0.64, k[1])
			circle(c, mx, my, 0.07, WHITE, { t = 0.15 })
		end
	end
	smiley(c, 0.48, 0.44, 0.27, col)
	piece(c, 0.48, 0.65, 0.22, 0.035, C(200, 198, 214), { round = true })
	piece(c, 0.48, 0.71, 0.15, 0.035, C(200, 198, 214), { round = true })
	sticker(c, 0.8, 0.2, 0.38, "+4", PLUS, -10)
end

-- EmotePage: a new page of emote slots (with its search box) + "+1"
local function drawEmotePage(c, item)
	local col = col3(item.color, C(255, 230, 120))
	halftone(c, col, 0.62)
	piece(c, 0.56, 0.54, 0.58, 0.74, C(212, 206, 232), { rot = 9, round = 0.08, ink = INK })
	local px, py, R = 0.45, 0.53, -5
	piece(c, px, py, 0.58, 0.74, C(252, 251, 246), { rot = R, round = 0.08, ink = INK })
	local x, y = rp(px, py, 0, -0.25, R)
	piece(c, x, y, 0.44, 0.1, C(226, 228, 240), { rot = R, round = true, ink = THIN })
	x, y = rp(px, py, -0.15, -0.25, R)
	ring(c, x, y, 0.045, THIN * 0.8, INKC)
	x, y = rp(px, py, 0.05, -0.25, R)
	piece(c, x, y, 0.2, 0.025, C(170, 170, 190), { rot = R, round = true })
	local SLOT = { col, C(110, 200, 255), C(255, 130, 180), PLUS }
	for i = 0, 3 do
		local sx, sy = rp(px, py, (i % 2 == 0) and -0.115 or 0.115, (i < 2) and -0.04 or 0.19, R)
		piece(c, sx, sy, 0.19, 0.19, SLOT[i + 1], { rot = R, round = 0.22, ink = THIN, shade = true })
		piece(c, sx - 0.03, sy - 0.015, 0.025, 0.05, INKC, { rot = R, round = true })
		piece(c, sx + 0.03, sy - 0.015, 0.025, 0.05, INKC, { rot = R, round = true })
	end
	sticker(c, 0.8, 0.2, 0.4, "+1", PLUS, 10)
end

-- KillSound: a speaker cabinet blasting a comic "BOOM!"
local function drawKillSound(c, item)
	local col = col3(item.color, C(255, 120, 140))
	halftone(c, col, 0.62, true)
	arc(c, 0.36, 0.56, 0.5, 0.04, col, 0, 0.62)
	arc(c, 0.36, 0.56, 0.72, 0.04, col, 0, 0.66)
	local cx, cy, R = 0.28, 0.58, -8
	piece(c, cx, cy, 0.4, 0.62, C(52, 46, 80), { rot = R, round = 0.12, ink = INK, c0 = C(74, 68, 108), c1 = C(32, 28, 52) })
	local x, y = rp(cx, cy, 0, 0.1, R)
	circle(c, x, y, 0.3, C(98, 92, 132), { ink = THIN })
	circle(c, x, y, 0.17, C(40, 36, 60))
	circle(c, x, y, 0.07, col)
	x, y = rp(cx, cy, 0, -0.18, R)
	circle(c, x, y, 0.12, col, { ink = THIN, shade = true })
	local bx, by = 0.7, 0.36
	union(c, function(ink)
		for i = 0, 2 do
			piece(c, bx, by, 0.41, 0.41, C(255, 214, 50), { rot = i * 30, ink = ink })
			piece(c, bx + 0.05, by + 0.06, 0.33, 0.33, C(255, 214, 50), { rot = 15 + i * 30, ink = ink })
		end
	end)
	for i = 0, 2 do
		piece(c, bx, by, 0.27, 0.27, C(255, 112, 40), { rot = 8 + i * 30 })
	end
	text(c, bx, by, 0.52, 0.25, "BOOM!", WHITE, { rot = -10 })
end

-- FunFilters: a rainbow fan of filter swatches + a camera lens
local function drawFunFilters(c, item)
	local col = col3(item.color, C(255, 160, 220))
	halftone(c, col, 0.62)
	local RAIN = { C(255, 84, 96), C(255, 166, 52), C(255, 228, 70), C(84, 212, 120), C(80, 164, 255), C(172, 112, 255) }
	local pvx, pvy = 0.6, 0.9
	for i, rc in ipairs(RAIN) do
		local a = -46 + (i - 1) * 16
		local x, y = rp(pvx, pvy, 0, -0.34, a)
		piece(c, x, y, 0.17, 0.62, rc, { rot = a, round = 0.3, ink = INK, shade = true })
	end
	circle(c, pvx, pvy, 0.08, C(200, 200, 215), { ink = THIN })
	local lx, ly = 0.31, 0.63
	circle(c, lx, ly, 0.5, C(44, 40, 62), { ink = INK, c0 = C(74, 70, 98), c1 = C(26, 24, 40) })
	circle(c, lx, ly, 0.38, C(140, 142, 162), { ink = THIN })
	circle(c, lx, ly, 0.29, WHITE, { ink = THIN, grot = 45,
		cs = cseq({ { 0, C(120, 225, 255) }, { 0.5, C(176, 120, 255) }, { 1, C(255, 130, 200) } }) })
	piece(c, lx - 0.055, ly - 0.06, 0.11, 0.04, WHITE, { rot = -45, round = true, t = 0.05 })
	circle(c, lx + 0.06, ly + 0.055, 0.035, WHITE, { t = 0.25 })
	sparkle(c, 0.86, 0.16, 0.16)
end

-- GadgetCrate: a wooden crate with a "?" and a glow
local function drawGadgetCrate(c, item)
	local col = col3(item.color, C(120, 230, 120))
	rays(c, 0.5, 0.54, 1.1, 0.14, col, 6, 0.45, 15)
	local W, H, cx, cy = 0.62, 0.54, 0.5, 0.6
	piece(c, cx, cy, W, H, C(196, 136, 76), { ink = INK, c0 = C(224, 166, 100), c1 = C(158, 100, 50) })
	for _, dy in ipairs({ -0.09, 0.09 }) do
		piece(c, cx, cy + dy, W - 0.02, 0.018, C(118, 72, 36))
	end
	seg(c, cx - W / 2 + 0.06, cy + H / 2 - 0.06, cx + W / 2 - 0.06, cy - H / 2 + 0.06, 0.07, C(214, 156, 92), { ink = THIN })
	piece(c, cx, cy - H / 2 - 0.02, W + 0.08, 0.1, C(176, 116, 62), { ink = INK, c0 = C(204, 144, 84), c1 = C(150, 94, 46) })
	for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		piece(c, cx + s[1] * (W / 2 - 0.035), cy + s[2] * (H / 2 - 0.035), 0.09, 0.09, C(176, 182, 198), { ink = THIN, round = 0.2 })
	end
	circle(c, cx, cy + 0.02, 0.3, NIGHT, { ink = INK })
	text(c, cx, cy + 0.025, 0.26, 0.26, "?", lit(col, 0.15), {})
	sparkle(c, 0.84, 0.17, 0.18)
	sparkle(c, 0.15, 0.3, 0.13)
end

-- StarterPack: a gift box with a ribbon and a popping lid
local function drawStarterPack(c, item)
	local col = col3(item.color, C(255, 175, 60))
	local RIB = C(232, 46, 70)
	rays(c, 0.5, 0.52, 1.1, 0.14, col, 6, 0.5, 0)
	piece(c, 0.5, 0.69, 0.6, 0.42, col, { ink = INK, shade = true })
	piece(c, 0.5, 0.69, 0.13, 0.42, RIB, { shade = true })
	local lx, ly, LR = 0.5, 0.42, -7
	for _, s in ipairs({ -1, 1 }) do
		local x, y = rp(lx, ly, s * 0.1, -0.15, LR)
		piece(c, x, y, 0.22, 0.14, RIB, { rot = LR - s * 25, round = true, ink = INK, shade = true })
		piece(c, x, y, 0.1, 0.05, drk(RIB, 0.45), { rot = LR - s * 25, round = true })
	end
	piece(c, lx, ly, 0.68, 0.15, lit(col, 0.1), { rot = LR, ink = INK, shade = true })
	piece(c, lx, ly, 0.13, 0.15, RIB, { rot = LR })
	local kx, ky = rp(lx, ly, 0, -0.11, LR)
	circle(c, kx, ky, 0.11, drk(RIB, 0.1), { ink = INK })
	sparkle(c, 0.85, 0.2, 0.18)
	sparkle(c, 0.14, 0.34, 0.13)
end

-- random rolls: a gacha capsule with "?" in the roll's category colour (+ more capsules and an xN sticker)
-- an upright toy capsule (a pill, coloured top / white bottom, a seam) - deliberately no centre button
local function capsule(c, x, y, d, rot, col)
	local w = d * 0.74
	piece(c, x, y, w, d, WHITE, { round = true, ink = INK, rot = rot, grot = 90,
		cs = cseq({ { 0, lit(col, 0.4) }, { 0.49, drk(col, 0.08) }, { 0.51, C(250, 250, 252) }, { 1, C(190, 192, 210) } }) })
	piece(c, x, y, w, d * 0.07, drk(col, 0.55), { rot = rot, round = true })
	local gx, gy = rp(x, y, -w * 0.24, -d * 0.24, rot)
	piece(c, gx, gy, w * 0.1, d * 0.24, WHITE, { rot = rot + 12, round = true, t = 0.15 })
	text(c, x, y - d * 0.02, d * 0.5, d * 0.5, "?", WHITE, { rot = rot, ink = INK * 1.1 })
end

local function rollHint(c, cat, x, y, d)
	if cat == "emote" then
		smiley(c, x, y, d, C(255, 226, 90))
	elseif cat == "ko" then
		seal(c, x, y, d, C(255, 90, 50), 0)
		text(c, x, y, d * 0.7, d * 0.45, "KO", WHITE, {})
	elseif cat == "skin" then
		circle(c, x, y, d, WHITE, { ink = INK, grot = 45,
			cs = cseq({ { 0, C(186, 120, 255) }, { 0.49, C(150, 84, 240) }, { 0.51, C(90, 225, 255) }, { 1, C(50, 170, 230) } }) })
	end
end

local function drawRoll(c, item)
	local col = col3(item.color, C(255, 230, 120))
	local n = tonumber(item.count) or 1
	halftone(c, col, 0.55)
	if n >= 10 then
		rays(c, 0.5, 0.52, 1.1, 0.13, col, 6, 0.5, 0)
	end
	if n > 1 then
		capsule(c, 0.27, 0.42, 0.42, -18, col)
		capsule(c, 0.73, 0.42, 0.42, 18, col)
		capsule(c, 0.5, 0.6, 0.56, -8, col)
		sticker(c, 0.8, 0.18, n >= 10 and 0.42 or 0.38, "x" .. n, STICKER, 12)
	else
		capsule(c, 0.52, 0.5, 0.68, -12, col)
		sparkle(c, 0.84, 0.18, 0.18)
	end
	rollHint(c, item.cat, 0.17, 0.83, 0.26)
end

-- titles: the nameplate as players see it over a head (ShopService draws Bangers, c0 -> c1 top to bottom, ink 2)
local function drawTitle(c, item)
	local c0, c1 = col3(item.c0, WHITE), col3(item.c1, C(140, 150, 170))
	halftone(c, c1, 0.55)
	piece(c, 0.5, 0.95, 0.54, 0.2, C(58, 54, 84), { round = 0.5, ink = INK })
	circle(c, 0.5, 0.76, 0.22, C(58, 54, 84), { ink = INK })
	local R = -5
	local tail = drk(c1, 0.45)
	for _, s in ipairs({ -1, 1 }) do
		local x, y = rp(0.5, 0.37, s * 0.41, 0.08, R)
		piece(c, x, y, 0.16, 0.24, tail, { rot = R - s * 12, ink = INK })
	end
	piece(c, 0.5, 0.37, 0.84, 0.42, C(22, 20, 36), { rot = R, round = 0.16, ink = INK })
	local f = piece(c, 0.5, 0.37, 0.78, 0.36, WHITE, { rot = R, round = 0.14, t = 1 })
	stroke(f, THIN * 0.8, 0.36, c1)
	text(c, 0.5, 0.37, 0.74, 0.32, string.upper(tostring(item.name or "TITLE")), c0, { rot = R, c1 = c1, wrap = true, ink = INK * 0.7 })
end

-- SANDBOX SHOP (2026-11-14, owner: "we do not need the japanese character icons for the purchases anymore, make them
-- pertaining to what the purchase is about"): the six sliders, Spawn Limit, Kill Effects Pack, the server events
-- (Nuke, Moon Gravity, Dummy Rain) and the five gadgets (GadgetCatalog ids), so no purchase falls back to its kanji.
local STEEL = C(200, 206, 224)
local DUMMY = C(238, 228, 206)
local HEART = C(240, 62, 84)

-- the sliders' shared mark: a dark track, the part up to the knob filled in `col`, a white knob at `frac` (0..1)
local function sliderBar(c, x, y, w, frac, col)
	local x0 = x - w / 2
	piece(c, x, y, w, 0.085, NIGHT, { round = true, ink = INK })
	local fw = math.max(w * frac, 0.06)
	piece(c, x0 + fw / 2 + 0.005, y, fw - 0.01, 0.042, col, { round = true, shade = true })
	circle(c, x0 + w * frac, y, 0.15, WHITE, { ink = INK, c0 = WHITE, c1 = C(196, 200, 218) })
	circle(c, x0 + w * frac, y, 0.055, col)
end

-- "^" with its tip at (tx, ty)
local function upChevron(c, tx, ty, arm, w, color, ink)
	local h = arm * 0.7071
	seg(c, tx - h, ty + h, tx, ty, w, color, { cap = w * 0.5, ink = ink, round = 0.2 })
	seg(c, tx + h, ty + h, tx, ty, w, color, { cap = w * 0.5, ink = ink, round = 0.2 })
end

-- a stadium-shaped ring w x h turned `rot`: an ink band with a `color` band inside it; half = only its lower half
-- (the front of a planet's ring)
local function band(c, x, y, w, h, rot, color, weight, half)
	local k = INK * 0.55
	local cut = half and gradient or nil
	local a = piece(c, x, y, w, h, WHITE, { rot = rot, round = true, t = 1 })
	local sa = stroke(a, weight + 2 * k, h, INKC)
	local b = piece(c, x, y, w + 2 * k, h + 2 * k, WHITE, { rot = rot, round = true, t = 1 })
	local sb = stroke(b, weight, h + 2 * k, color)
	if cut then
		for _, s in ipairs({ sa, sb }) do
			cut(s, ColorSequence.new(WHITE), 90, nseq({ { 0, 1 }, { 0.5, 1 }, { 0.53, 0 }, { 1, 0 } }))
		end
	end
end

-- a blocky sandbox dummy `s` tall (head to feet ~0.93 s), centred on (x, y), turned `rot` degrees.
-- o: col, t (see-through: a decoy / ghost, no face), inkc, ink = false (no outline)
local DUMMY_PARTS = { -- { x, y, w, h, extra turn, corner } in units of s
	{ -0.2, -0.04, 0.1, 0.3, 28, 0.4 }, -- arms, splayed
	{ 0.2, -0.04, 0.1, 0.3, -28, 0.4 },
	{ -0.085, 0.27, 0.12, 0.32, 10, 0.4 }, -- legs
	{ 0.085, 0.27, 0.12, 0.32, -10, 0.4 },
	{ 0, -0.03, 0.3, 0.36, 0, 0.22 }, -- torso
}
local function dummy(c, x, y, s, rot, o)
	o = o or {}
	rot = rot or 0
	local col = o.col or DUMMY
	local function parts(ink)
		for _, p in ipairs(DUMMY_PARTS) do
			local px, py = rp(x, y, p[1] * s, p[2] * s, rot)
			piece(c, px, py, p[3] * s, p[4] * s, col, { rot = rot + p[5], round = p[6], ink = ink, inkc = o.inkc, shade = not o.t, t = o.t })
		end
		local hx, hy = rp(x, y, 0, -0.36 * s, rot)
		circle(c, hx, hy, 0.27 * s, col, { ink = ink, inkc = o.inkc, shade = not o.t, t = o.t })
	end
	if o.ink == false then
		parts(nil)
	else
		union(c, parts)
	end
	if not o.t then
		for _, sx in ipairs({ -0.055, 0.055 }) do
			local ex, ey = rp(x, y, sx * s, -0.38 * s, rot)
			piece(c, ex, ey, 0.04 * s, 0.075 * s, INKC, { rot = rot, round = true })
		end
	end
end

-- a heart `s` wide centred on (x, y): two lobes + a square on its corner, one outline
local function heart(c, x, y, s, color)
	union(c, function(ink)
		circle(c, x - s * 0.2, y - s * 0.12, s * 0.54, color, { ink = ink })
		circle(c, x + s * 0.2, y - s * 0.12, s * 0.54, color, { ink = ink })
		piece(c, x, y + s * 0.08, s * 0.54, s * 0.54, color, { rot = 45, round = 0.06, ink = ink })
	end)
end

-- a cartoon cloud: puffs over a flat pill, one outline
local function cloud(c, puffs, base, color)
	union(c, function(ink)
		for _, p in ipairs(puffs) do
			circle(c, p[1], p[2], p[3], color, { ink = ink })
		end
		piece(c, base[1], base[2], base[3], base[4], color, { round = true, ink = ink })
	end)
end

-- SliderPack: a little control panel of three sliders + "x6"
local function drawSliderPack(c, item)
	local col = col3(item.color, C(255, 150, 60))
	rays(c, 0.5, 0.52, 1.1, 0.13, col, 6, 0.5, 0)
	piece(c, 0.47, 0.56, 0.84, 0.68, C(44, 40, 68), { round = 0.12, ink = INK, c0 = C(66, 62, 98), c1 = C(30, 28, 48) })
	local ROWS = { { C(110, 255, 160), 0.72 }, { C(150, 170, 255), 0.34 }, { C(255, 90, 90), 0.88 } }
	for i, r in ipairs(ROWS) do
		sliderBar(c, 0.47, 0.34 + (i - 1) * 0.215, 0.64, r[2], r[1])
	end
	sticker(c, 0.82, 0.17, 0.38, "x6", STICKER, 12)
end

-- RunSlider: a sneaker with speed lines
local function drawRunSlider(c, item)
	local col = col3(item.color, C(110, 255, 160))
	local SHOE = C(255, 96, 84)
	halftone(c, col, 0.62)
	speedLines(c, 0, lit(col, 0.2), { { -0.18, -0.3, 0.26, 0.034 }, { -0.06, -0.37, 0.2, 0.034 }, { 0.06, -0.31, 0.24, 0.034 } }, 0.1)
	union(c, function(ink)
		piece(c, 0.57, 0.57, 0.62, 0.11, WHITE, { round = true, ink = ink })
		piece(c, 0.48, 0.42, 0.4, 0.26, SHOE, { round = 0.35, ink = ink })
		piece(c, 0.69, 0.49, 0.36, 0.17, SHOE, { round = true, ink = ink })
		piece(c, 0.34, 0.33, 0.15, 0.16, SHOE, { round = 0.4, ink = ink })
	end)
	piece(c, 0.57, 0.595, 0.56, 0.024, C(196, 200, 220), { round = true })
	piece(c, 0.5, 0.49, 0.34, 0.05, drk(SHOE, 0.25), { rot = -6, round = true })
	for i = 0, 2 do
		piece(c, 0.47 + i * 0.065, 0.37 + i * 0.03, 0.1, 0.03, WHITE, { rot = -28, round = true })
	end
	piece(c, 0.39, 0.37, 0.07, 0.035, WHITE, { rot = -40, round = true, t = 0.2 })
	sliderBar(c, 0.5, 0.85, 0.76, 0.78, col)
end

-- JumpSlider: a coil spring pushing an up arrow
local function drawJumpSlider(c, item)
	local col = col3(item.color, C(150, 170, 255))
	local ARROW = C(255, 222, 70)
	halftone(c, col, 0.62, true)
	for i = 0, 3 do -- the coil: stacked slanted loops
		piece(c, 0.5, 0.628 - i * 0.07, 0.4, 0.078, STEEL, { rot = -8, round = true, ink = INK, c0 = WHITE, c1 = drk(STEEL, 0.3) })
	end
	piece(c, 0.5, 0.675, 0.52, 0.075, C(110, 116, 140), { round = 0.4, ink = INK, shade = true })
	piece(c, 0.5, 0.385, 0.52, 0.075, col, { round = 0.4, ink = INK, shade = true })
	union(c, function(ink)
		seg(c, 0.5, 0.31, 0.5, 0.12, 0.08, ARROW, { cap = 0.03, round = 0.2, ink = ink })
		upChevron(c, 0.5, 0.075, 0.17, 0.08, ARROW, ink)
	end)
	sparkle(c, 0.82, 0.2, 0.16)
	sparkle(c, 0.17, 0.3, 0.12)
	sliderBar(c, 0.5, 0.86, 0.76, 0.6, col)
end

-- GravitySlider: a ringed planet
local function drawGravitySlider(c, item)
	local col = col3(item.color, C(190, 140, 255))
	local RING = C(255, 214, 120)
	halftone(c, col, 0.62)
	local px, py, R = 0.5, 0.41, -16
	band(c, px, py, 0.82, 0.22, R, RING, 0.045)
	circle(c, px, py, 0.46, col, { ink = INK, shade = true })
	circle(c, px - 0.1, py - 0.05, 0.11, drk(col, 0.2))
	circle(c, px + 0.1, py + 0.09, 0.07, drk(col, 0.2))
	circle(c, px + 0.06, py - 0.13, 0.05, drk(col, 0.2))
	piece(c, px - 0.1, py - 0.15, 0.12, 0.045, WHITE, { rot = -38, round = true, t = 0.2 })
	band(c, px, py, 0.82, 0.22, R, RING, 0.045, true)
	sparkle(c, 0.86, 0.14, 0.15)
	sparkle(c, 0.12, 0.66, 0.11)
	sliderBar(c, 0.5, 0.86, 0.76, 0.45, col)
end

-- HealthSlider: a heart with a plus + a GOD sticker (God Mode)
local function drawHealthSlider(c, item)
	local col = col3(item.color, C(90, 230, 140))
	halftone(c, col, 0.62, true)
	rays(c, 0.46, 0.44, 0.9, 0.11, HEART, 6, 0.62, 10)
	heart(c, 0.46, 0.45, 0.58, HEART)
	piece(c, 0.33, 0.33, 0.11, 0.05, WHITE, { rot = -42, round = true, t = 0.15 })
	union(c, function(ink)
		piece(c, 0.46, 0.45, 0.21, 0.07, WHITE, { round = 0.3, ink = ink })
		piece(c, 0.46, 0.45, 0.07, 0.21, WHITE, { round = 0.3, ink = ink })
	end, THIN)
	sticker(c, 0.8, 0.19, 0.36, "GOD", GOLD, 12)
	sliderBar(c, 0.5, 0.86, 0.76, 0.88, col)
end

-- StrengthSlider: a dumbbell + POW
local function drawStrengthSlider(c, item)
	local col = col3(item.color, C(255, 90, 90))
	halftone(c, col, 0.62)
	local cx, cy, R = 0.47, 0.44, -18
	local ax, ay = rp(cx, cy, -0.38, 0, R)
	local bx, by = rp(cx, cy, 0.38, 0, R)
	seg(c, ax, ay, bx, by, 0.065, STEEL, { ink = INK, round = true })
	for i = -2, 2 do
		local gx, gy = rp(cx, cy, i * 0.035, 0, R)
		piece(c, gx, gy, 0.012, 0.05, drk(STEEL, 0.45), { rot = R })
	end
	for _, side in ipairs({ -1, 1 }) do
		for _, d in ipairs({ { 0.2, 0.42 }, { 0.295, 0.31 } }) do
			local px, py = rp(cx, cy, side * d[1], 0, R)
			piece(c, px, py, 0.085, d[2], C(70, 74, 96), { rot = R, round = 0.3, ink = INK, c0 = C(110, 116, 140), c1 = C(44, 46, 62) })
		end
	end
	sticker(c, 0.8, 0.17, 0.36, "POW", STICKER, 12)
	sliderBar(c, 0.5, 0.86, 0.76, 0.7, col)
end

-- FlingSlider: a dummy tumbling through the air
local function drawFlingSlider(c, item)
	local col = col3(item.color, C(90, 200, 255))
	halftone(c, col, 0.62, true)
	speedLines(c, -40, WHITE, { { -0.12, -0.31, 0.3, 0.034 }, { 0.07, -0.35, 0.24, 0.034 }, { 0.2, -0.22, 0.18, 0.034 } }, 0.2)
	dummy(c, 0.58, 0.38, 0.54, 38)
	sparkle(c, 0.88, 0.14, 0.15)
	sliderBar(c, 0.5, 0.86, 0.76, 0.82, col)
end

-- SpawnPlus: three dummies + "x3"
local function drawSpawnPlus(c, item)
	local col = col3(item.color, C(255, 205, 70))
	halftone(c, col, 0.62)
	piece(c, 0.5, 0.9, 0.86, 0.07, drk(col, 0.4), { round = true, t = 0.4 })
	dummy(c, 0.23, 0.6, 0.5, -8)
	dummy(c, 0.77, 0.6, 0.5, 8)
	dummy(c, 0.5, 0.57, 0.62, 0)
	sticker(c, 0.82, 0.17, 0.36, "x3", PLUS, 12)
end

-- KillFXPack: a rainbow-rayed KO burst + sparkles + "ALL"
local function drawKillFXPack(c, item)
	local col = col3(item.color, C(255, 110, 60))
	local RAIN = { C(255, 84, 96), C(255, 196, 52), C(84, 212, 120), C(80, 164, 255), C(172, 112, 255), C(255, 120, 200) }
	for i, rc in ipairs(RAIN) do
		piece(c, 0.5, 0.5, 1.12, 0.1, rc, { rot = (i - 1) * 30 + 8, t = 0.2, ts = FADE_ENDS })
	end
	seal(c, 0.5, 0.5, 0.64, col, 8)
	seal(c, 0.5, 0.5, 0.47, C(255, 214, 50), 23)
	text(c, 0.5, 0.51, 0.48, 0.28, "KO!", WHITE, { rot = -8 })
	sparkle(c, 0.15, 0.17, 0.2, C(255, 240, 150))
	sparkle(c, 0.86, 0.84, 0.16, C(150, 220, 255))
	sparkle(c, 0.88, 0.2, 0.12)
	sticker(c, 0.19, 0.82, 0.32, "ALL", STICKER, -10)
end

-- Nuke: a mushroom cloud over a ground blast
local function drawNuke(c, item)
	local col = col3(item.color, C(255, 230, 90))
	local CAP = C(255, 186, 86)
	rays(c, 0.5, 0.42, 1.15, 0.15, col, 6, 0.45, 15)
	piece(c, 0.5, 0.88, 0.86, 0.14, C(236, 110, 40), { round = true, ink = INK, c0 = C(255, 170, 70), c1 = C(200, 70, 30) })
	piece(c, 0.5, 0.66, 0.2, 0.42, C(255, 210, 130), { round = 0.4, ink = INK, c0 = C(255, 232, 170), c1 = C(240, 150, 70) })
	piece(c, 0.5, 0.63, 0.38, 0.08, C(250, 170, 90), { round = true, ink = INK, shade = true })
	cloud(c, { { 0.32, 0.34, 0.3 }, { 0.68, 0.34, 0.3 }, { 0.5, 0.25, 0.38 } }, { 0.5, 0.41, 0.72, 0.2 }, CAP)
	piece(c, 0.5, 0.46, 0.56, 0.075, C(214, 96, 40), { round = true, t = 0.1 })
	circle(c, 0.42, 0.19, 0.11, WHITE, { t = 0.45 })
	circle(c, 0.28, 0.3, 0.07, WHITE, { t = 0.55 })
	circle(c, 0.66, 0.27, 0.06, WHITE, { t = 0.55 })
	sparkle(c, 0.87, 0.13, 0.15)
end

-- MoonGravity: a cratered moon with a dummy drifting up beside it
local function drawMoonGravity(c, item)
	local col = col3(item.color, C(170, 200, 255))
	halftone(c, col, 0.62, true)
	local mx, my = 0.42, 0.42
	rays(c, mx, my, 0.95, 0.1, lit(col, 0.3), 6, 0.6, 0)
	circle(c, mx, my, 0.6, C(232, 236, 252), { ink = INK, c0 = C(250, 251, 255), c1 = C(176, 186, 222) })
	for _, k in ipairs({ { -0.12, -0.08, 0.15 }, { 0.12, 0.07, 0.11 }, { -0.05, 0.17, 0.08 }, { 0.11, -0.16, 0.06 } }) do
		circle(c, mx + k[1], my + k[2], k[3], C(184, 192, 222), { ink = THIN * 0.8, inkc = C(132, 140, 178) })
	end
	piece(c, 0.27, 0.23, 0.12, 0.045, WHITE, { rot = -40, round = true, t = 0.15 })
	dummy(c, 0.78, 0.66, 0.38, 18)
	piece(c, 0.73, 0.93, 0.026, 0.08, WHITE, { round = true, t = 0.3 })
	piece(c, 0.82, 0.95, 0.026, 0.06, WHITE, { round = true, t = 0.4 })
	sparkle(c, 0.87, 0.14, 0.16)
	sparkle(c, 0.12, 0.84, 0.12)
end

-- DummyRain: dummies falling head-first out of a cloud
local function drawDummyRain(c, item)
	local col = col3(item.color, C(235, 235, 245))
	halftone(c, C(120, 160, 230), 0.62)
	for _, d in ipairs({ { 0.22, 0.66, 0.3, 165 }, { 0.53, 0.8, 0.32, 195 }, { 0.8, 0.62, 0.28, 170 } }) do
		piece(c, d[1], d[2] - d[3] * 0.95, 0.026, d[3] * 0.62, WHITE, { round = true, t = 0.2, ts = FADE_TAIL, grot = 270 })
		dummy(c, d[1], d[2], d[3], d[4])
	end
	cloud(c, { { 0.28, 0.24, 0.28 }, { 0.5, 0.17, 0.36 }, { 0.74, 0.25, 0.28 } }, { 0.51, 0.31, 0.74, 0.17 }, col)
	piece(c, 0.51, 0.355, 0.6, 0.045, C(196, 200, 222), { round = true })
end

-- gadgets (GadgetCatalog) ---------------------------------------------------------------------------------------
-- Smoke: a round bomb with a lit fuse, smoke rolling off it
local function drawSmoke(c, item)
	local col = col3(item.color, C(170, 170, 190))
	union(c, function(ink)
		for _, p in ipairs({ { 0.68, 0.3, 0.34 }, { 0.84, 0.48, 0.26 }, { 0.54, 0.17, 0.24 }, { 0.3, 0.27, 0.2 }, { 0.86, 0.22, 0.18 } }) do
			circle(c, p[1], p[2], p[3], lit(col, 0.3), { ink = ink })
		end
	end, THIN * 1.2)
	circle(c, 0.42, 0.62, 0.52, C(52, 50, 70), { ink = INK, c0 = C(88, 86, 112), c1 = C(26, 24, 38) })
	piece(c, 0.6, 0.44, 0.14, 0.1, C(130, 134, 154), { rot = 45, ink = INK, round = 0.2 })
	seg(c, 0.63, 0.41, 0.72, 0.28, 0.035, C(214, 170, 110), { round = true, ink = THIN })
	sparkle(c, 0.74, 0.25, 0.2, C(255, 210, 80))
	piece(c, 0.31, 0.5, 0.12, 0.05, WHITE, { rot = -40, round = true, t = 0.3 })
end

-- Decoy: a dummy and its see-through double
local function drawDecoy(c, item)
	local col = col3(item.color, C(150, 120, 255))
	halftone(c, col, 0.62)
	dummy(c, 0.66, 0.53, 0.66, 8, { col = lit(col, 0.2), t = 0.45, inkc = drk(col, 0.25) })
	speedLines(c, 0, lit(col, 0.3), { { -0.1, -0.02, 0.16, 0.03 }, { 0.06, 0.0, 0.12, 0.03 } }, 0.2)
	dummy(c, 0.35, 0.55, 0.66, -4)
	sparkle(c, 0.88, 0.14, 0.15)
end

-- Pad: a launch pad with up arrows rising off it
local function drawPad(c, item)
	local col = col3(item.color, C(80, 220, 255))
	piece(c, 0.5, 0.45, 0.56, 0.62, col, { ts = nseq({ { 0, 1 }, { 1, 0.45 } }) })
	piece(c, 0.5, 0.82, 0.86, 0.18, C(50, 54, 76), { round = 0.45, ink = INK, c0 = C(84, 90, 118), c1 = C(30, 32, 48) })
	piece(c, 0.5, 0.79, 0.66, 0.07, col, { round = true, ink = THIN, shade = true })
	union(c, function(ink)
		for _, ty in ipairs({ 0.16, 0.36, 0.56 }) do
			upChevron(c, 0.5, ty, 0.22, 0.085, lit(col, 0.25), ink)
		end
	end)
	sparkle(c, 0.86, 0.18, 0.15)
end

-- Bubble: a dummy inside a shining bubble
local function drawBubble(c, item)
	local col = col3(item.color, C(120, 230, 255))
	dummy(c, 0.5, 0.57, 0.5, 0)
	circle(c, 0.5, 0.52, 0.84, col, { t = 0.6, c0 = lit(col, 0.55), c1 = col, ink = INK, inkc = drk(col, 0.45) })
	arc(c, 0.5, 0.52, 0.68, 0.05, WHITE, 225, 0.62)
	circle(c, 0.3, 0.3, 0.07, WHITE, { t = 0.1 })
	circle(c, 0.76, 0.76, 0.05, WHITE, { t = 0.3 })
	sparkle(c, 0.86, 0.14, 0.16)
end

-- Snack: a burger
local function drawSnack(c, item)
	local col = col3(item.color, C(255, 170, 90))
	local BUN0, BUN1 = C(252, 200, 112), C(214, 136, 60)
	halftone(c, col, 0.62)
	piece(c, 0.5, 0.79, 0.7, 0.13, BUN0, { round = 0.45, ink = INK, c0 = BUN0, c1 = BUN1 })
	piece(c, 0.5, 0.67, 0.78, 0.14, C(120, 66, 40), { round = true, ink = INK, c0 = C(156, 90, 54), c1 = C(90, 46, 26) })
	union(c, function(ink)
		piece(c, 0.5, 0.585, 0.74, 0.06, C(255, 206, 60), { round = 0.2, ink = ink })
		piece(c, 0.3, 0.615, 0.09, 0.09, C(255, 206, 60), { rot = 45, round = 0.15, ink = ink })
		piece(c, 0.66, 0.62, 0.08, 0.08, C(255, 206, 60), { rot = 45, round = 0.15, ink = ink })
	end, THIN * 1.3)
	piece(c, 0.5, 0.535, 0.82, 0.075, C(110, 210, 90), { round = true, ink = INK, shade = true })
	union(c, function(ink)
		piece(c, 0.5, 0.38, 0.74, 0.3, BUN0, { round = 0.5, ink = ink })
		piece(c, 0.5, 0.465, 0.74, 0.1, BUN0, { round = 0.25, ink = ink })
	end)
	piece(c, 0.5, 0.48, 0.66, 0.04, BUN1, { round = true, t = 0.2 })
	for _, s in ipairs({ { 0.36, 0.33, -20 }, { 0.5, 0.29, 5 }, { 0.63, 0.34, 25 }, { 0.44, 0.4, 10 }, { 0.58, 0.41, -15 } }) do
		piece(c, s[1], s[2], 0.05, 0.026, C(255, 248, 228), { rot = s[3], round = true })
	end
	piece(c, 0.34, 0.27, 0.1, 0.04, WHITE, { rot = -25, round = true, t = 0.3 })
end

-- (2026-11-15) the EVENTS tab + two perks ---------------------------------------------------------------------
-- Tornado: a twisting funnel with a dummy and debris flung round it
local function drawTornado(c, item)
	local col = col3(item.color, C(160, 178, 200))
	halftone(c, col, 0.62)
	local rows = { { 0.5, 0.14, 0.84 }, { 0.53, 0.25, 0.72 }, { 0.5, 0.36, 0.6 }, { 0.46, 0.47, 0.48 }, { 0.47, 0.57, 0.36 }, { 0.51, 0.67, 0.26 }, { 0.53, 0.76, 0.17 }, { 0.5, 0.84, 0.1 } }
	union(c, function(ink)
		for _, r in ipairs(rows) do
			piece(c, r[1], r[2], r[3], 0.13, C(150, 158, 176), { round = true, ink = ink, c0 = C(214, 220, 234), c1 = C(112, 120, 140) })
		end
	end)
	for i, r in ipairs(rows) do
		if i % 2 == 1 then
			piece(c, r[1] - r[3] * 0.12, r[2] - 0.01, r[3] * 0.5, 0.025, WHITE, { round = true, t = 0.25, rot = -6 })
		end
	end
	piece(c, 0.5, 0.92, 0.5, 0.06, C(150, 128, 98), { round = true, t = 0.3 })
	dummy(c, 0.82, 0.32, 0.3, 70)
	piece(c, 0.16, 0.5, 0.08, 0.06, C(140, 104, 66), { rot = 30, ink = THIN })
	piece(c, 0.84, 0.66, 0.07, 0.05, C(90, 86, 82), { rot = -20, ink = THIN })
	speedLines(c, 0, WHITE, { { -0.3, -0.36, 0.18, 0.026 }, { 0.12, 0.34, 0.16, 0.026 } }, 0.3)
end

-- Earthquake: a slab of ground splitting down the middle, rocks jumping, shake marks
local function drawEarthquake(c, item)
	local col = col3(item.color, C(214, 150, 80))
	halftone(c, col, 0.62, true)
	union(c, function(ink)
		piece(c, 0.28, 0.72, 0.46, 0.34, C(150, 110, 70), { rot = -6, round = 0.12, ink = ink, c0 = C(196, 150, 98), c1 = C(112, 78, 46) })
		piece(c, 0.74, 0.74, 0.44, 0.32, C(150, 110, 70), { rot = 8, round = 0.12, ink = ink, c0 = C(196, 150, 98), c1 = C(112, 78, 46) })
	end)
	piece(c, 0.28, 0.58, 0.44, 0.06, C(110, 186, 90), { rot = -6, round = true, ink = THIN })
	piece(c, 0.74, 0.6, 0.42, 0.06, C(110, 186, 90), { rot = 8, round = true, ink = THIN })
	local crack = { { 0.5, 0.56 }, { 0.46, 0.64 }, { 0.53, 0.72 }, { 0.47, 0.8 }, { 0.52, 0.9 } }
	for i = 1, #crack - 1 do
		seg(c, crack[i][1], crack[i][2], crack[i + 1][1], crack[i + 1][2], 0.05, INKC, { cap = 0.04, round = true })
	end
	for _, r in ipairs({ { 0.3, 0.3, 0.12, 20 }, { 0.62, 0.22, 0.1, -15 }, { 0.48, 0.4, 0.08, 40 } }) do
		piece(c, r[1], r[2], r[3], r[3] * 0.8, C(120, 104, 90), { rot = r[4], round = 0.25, ink = INK, shade = true })
	end
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, 2 do
			piece(c, 0.5 + s * (0.42 + k * 0.03), 0.35 + k * 0.08, 0.025, 0.1, WHITE, { round = true, t = 0.2 })
		end
	end
	sticker(c, 0.82, 0.15, 0.32, "!!", STICKER, 12)
end

-- BlackHole: a black core with a burning ring round it, a dummy stretching into it
local function drawBlackHole(c, item)
	local col = col3(item.color, C(150, 90, 255))
	rays(c, 0.5, 0.48, 1.15, 0.12, col, 6, 0.5, 10)
	band(c, 0.5, 0.48, 0.92, 0.26, -14, C(255, 160, 70), 0.05)
	circle(c, 0.5, 0.48, 0.46, col, { ink = INK, c0 = lit(col, 0.2), c1 = drk(col, 0.3) })
	circle(c, 0.5, 0.48, 0.36, C(8, 6, 14), { ink = THIN, inkc = C(255, 120, 220) })
	band(c, 0.5, 0.48, 0.92, 0.26, -14, C(255, 160, 70), 0.05, true)
	dummy(c, 0.82, 0.22, 0.28, -50, { col = lit(DUMMY, 0.1) })
	speedLines(c, 135, WHITE, { { -0.04, -0.2, 0.16, 0.026 }, { 0.06, -0.24, 0.12, 0.026 } }, 0.3)
	sparkle(c, 0.14, 0.18, 0.15, C(255, 200, 255))
	sparkle(c, 0.18, 0.82, 0.12)
end

-- Flood: waves over everything, a dummy floating on its back, bubbles
local function drawFlood(c, item)
	local col = col3(item.color, C(60, 150, 240))
	piece(c, 0.5, 0.3, 1, 0.6, C(200, 230, 255), { t = 0.5 })
	piece(c, 0.5, 0.74, 1, 0.56, col, { c0 = lit(col, 0.15), c1 = drk(col, 0.35) })
	for i = 0, 4 do
		circle(c, 0.1 + i * 0.2, 0.47, 0.24, col, { ink = INK, c0 = lit(col, 0.45), c1 = col })
	end
	piece(c, 0.5, 0.56, 1, 0.12, col, {})
	dummy(c, 0.5, 0.48, 0.42, 90)
	for _, b in ipairs({ { 0.2, 0.78, 0.07 }, { 0.28, 0.88, 0.05 }, { 0.78, 0.82, 0.06 }, { 0.7, 0.92, 0.04 } }) do
		ring(c, b[1], b[2], b[3], THIN, WHITE)
	end
	sticker(c, 0.84, 0.15, 0.3, "SPLASH", C(40, 110, 220), 12)
end

-- IceWorld: a dummy frozen in an ice block, a snowflake
local function drawIceWorld(c, item)
	local col = col3(item.color, C(140, 210, 255))
	halftone(c, col, 0.62)
	dummy(c, 0.46, 0.56, 0.5, -6)
	piece(c, 0.46, 0.55, 0.62, 0.66, col, { round = 0.12, t = 0.45, ink = INK, inkc = drk(col, 0.4), c0 = lit(col, 0.6), c1 = col })
	piece(c, 0.3, 0.32, 0.16, 0.05, WHITE, { rot = -40, round = true, t = 0.1 })
	piece(c, 0.62, 0.78, 0.1, 0.04, WHITE, { rot = -40, round = true, t = 0.3 })
	local sx, sy = 0.8, 0.2
	for k = 0, 2 do
		piece(c, sx, sy, 0.3, 0.045, WHITE, { rot = k * 60, round = true, ink = THIN, inkc = drk(col, 0.4) })
	end
	circle(c, sx, sy, 0.07, WHITE, { ink = THIN, inkc = drk(col, 0.4) })
end

-- Zombies: a green dummy reaching out of a grave mound, another one shambling
local function drawZombies(c, item)
	local ZOMBIE = C(132, 176, 104)
	halftone(c, C(90, 120, 80), 0.62, true)
	dummy(c, 0.66, 0.5, 0.62, 6, { col = ZOMBIE })
	union(c, function(ink)
		piece(c, 0.44, 0.41, 0.3, 0.08, ZOMBIE, { rot = -4, round = 0.4, ink = ink })
		piece(c, 0.46, 0.5, 0.3, 0.08, ZOMBIE, { rot = 6, round = 0.4, ink = ink })
	end)
	for _, sx in ipairs({ -0.06, 0.06 }) do
		circle(c, 0.66 + sx * 0.62, 0.27, 0.06, C(200, 255, 80), { ink = THIN })
	end
	piece(c, 0.26, 0.9, 0.5, 0.16, C(104, 84, 62), { round = true, ink = INK, shade = true })
	union(c, function(ink)
		piece(c, 0.22, 0.72, 0.08, 0.26, ZOMBIE, { rot = -10, round = 0.4, ink = ink })
		for i = -1, 1 do
			piece(c, 0.2 + i * 0.035, 0.57, 0.03, 0.09, ZOMBIE, { rot = i * 12, round = true, ink = ink })
		end
	end, THIN)
	sticker(c, 0.17, 0.15, 0.3, "BRAINS", C(90, 160, 60), -10)
end

-- BossDummy: a towering dark dummy with burning eyes over a tiny one, BOSS sticker
local function drawBossDummy(c, item)
	local col = col3(item.color, C(235, 70, 70))
	rays(c, 0.5, 0.42, 1.1, 0.14, col, 6, 0.55, 0)
	dummy(c, 0.5, 0.52, 0.92, 0, { col = C(96, 52, 62) })
	for _, sx in ipairs({ -0.05, 0.05 }) do
		circle(c, 0.5 + sx * 0.92, 0.18, 0.07, C(255, 70, 50), { ink = THIN })
	end
	dummy(c, 0.2, 0.86, 0.22, -10)
	sticker(c, 0.82, 0.16, 0.34, "BOSS", STICKER, 12)
end

-- ChaosBundle: a mushroom cloud with meteors raining round it + "x8"
local function drawChaosBundle(c, item)
	local col = col3(item.color, C(255, 120, 50))
	drawNuke(c, { color = C(255, 230, 90) })
	for _, m in ipairs({ { 0.15, 0.3, 0.12 }, { 0.84, 0.48, 0.1 }, { 0.22, 0.66, 0.09 } }) do
		piece(c, m[1] - 0.07, m[2] - 0.08, 0.035, 0.2, C(255, 200, 90), { rot = -38, round = true, t = 0.2, ts = FADE_TAIL, grot = 270 })
		circle(c, m[1], m[2], m[3], C(120, 80, 60), { ink = INK, c0 = C(255, 150, 70), c1 = C(120, 50, 30) })
	end
	sticker(c, 0.82, 0.16, 0.34, "x8", col, 12)
end

-- DummyAnyone: an avatar-styled figure (hair, shirt) wearing a name tag, a "+" badge
local function drawDummyAnyone(c, item)
	local col = col3(item.color, C(110, 200, 255))
	halftone(c, col, 0.62)
	local SKIN0, SHIRT, PANTS = C(255, 214, 172), C(70, 140, 240), C(54, 56, 76)
	union(c, function(ink)
		piece(c, 0.42, 0.86, 0.11, 0.2, PANTS, { round = 0.3, ink = ink })
		piece(c, 0.56, 0.86, 0.11, 0.2, PANTS, { round = 0.3, ink = ink })
		piece(c, 0.27, 0.6, 0.1, 0.28, SKIN0, { rot = 14, round = 0.4, ink = ink })
		piece(c, 0.71, 0.6, 0.1, 0.28, SKIN0, { rot = -14, round = 0.4, ink = ink })
		piece(c, 0.49, 0.6, 0.34, 0.32, SHIRT, { round = 0.22, ink = ink })
		circle(c, 0.49, 0.32, 0.27, SKIN0, { ink = ink })
	end)
	piece(c, 0.49, 0.22, 0.3, 0.1, C(120, 76, 40), { round = 0.45, ink = THIN, shade = true })
	piece(c, 0.44, 0.33, 0.035, 0.06, INKC, { round = true })
	piece(c, 0.54, 0.33, 0.035, 0.06, INKC, { round = true })
	arc(c, 0.49, 0.34, 0.12, 0.022, INKC, 90, 0.62)
	piece(c, 0.49, 0.07, 0.46, 0.1, WHITE, { round = true, ink = THIN })
	text(c, 0.49, 0.075, 0.4, 0.08, "@ANYONE", C(40, 110, 220), { ink = false })
	sticker(c, 0.85, 0.82, 0.28, "+", PLUS, 12)
end

-- PhotoMode: a camera in a viewfinder frame
local function drawPhotoMode(c, item)
	local col = col3(item.color, C(255, 196, 110))
	halftone(c, col, 0.62, true)
	for _, k in ipairs({ { 0.1, 0.1, 1, 1 }, { 0.9, 0.1, -1, 1 }, { 0.1, 0.9, 1, -1 }, { 0.9, 0.9, -1, -1 } }) do
		piece(c, k[1] + k[3] * 0.06, k[2], 0.14, 0.035, WHITE, { round = true, ink = THIN })
		piece(c, k[1], k[2] + k[4] * 0.06, 0.035, 0.14, WHITE, { round = true, ink = THIN })
	end
	union(c, function(ink)
		piece(c, 0.38, 0.33, 0.22, 0.1, C(60, 62, 80), { round = 0.2, ink = ink })
		piece(c, 0.5, 0.55, 0.66, 0.42, C(60, 62, 80), { round = 0.16, ink = ink })
	end)
	piece(c, 0.5, 0.55, 0.62, 0.38, WHITE, { round = 0.16, t = 1, c0 = C(96, 100, 126), c1 = C(40, 42, 58) })
	circle(c, 0.5, 0.56, 0.32, STEEL, { ink = INK, c0 = WHITE, c1 = drk(STEEL, 0.3) })
	circle(c, 0.5, 0.56, 0.22, C(40, 90, 180), { ink = THIN, c0 = C(130, 200, 255), c1 = C(20, 50, 120) })
	circle(c, 0.46, 0.52, 0.06, WHITE, { t = 0.1 })
	piece(c, 0.74, 0.42, 0.1, 0.06, GOLD, { round = 0.2, ink = THIN })
	sparkle(c, 0.84, 0.24, 0.16)
end

-- dispatch -----------------------------------------------------------------------------------------------------
local BY_ID = {
	Tornado = drawTornado,
	Earthquake = drawEarthquake,
	BlackHole = drawBlackHole,
	Flood = drawFlood,
	IceWorld = drawIceWorld,
	Zombies = drawZombies,
	BossDummy = drawBossDummy,
	ChaosBundle = drawChaosBundle,
	DummyAnyone = drawDummyAnyone,
	PhotoMode = drawPhotoMode,
	Yen1 = drawYen,
	Yen2 = drawYen,
	Yen3 = drawYen,
	Yen4 = drawYen,
	YenX2 = drawYenX2,
	Cooldowns = drawCooldowns,
	Meteor = drawMeteor,
	UltNow = drawUltNow,
	EmoteSlots = drawEmoteSlots,
	EmotePage = drawEmotePage,
	KillSound = drawKillSound,
	FunFilters = drawFunFilters,
	GadgetCrate = drawGadgetCrate,
	StarterPack = drawStarterPack,
	-- (2026-11-14) sandbox shop + gadgets
	SliderPack = drawSliderPack,
	RunSlider = drawRunSlider,
	JumpSlider = drawJumpSlider,
	GravitySlider = drawGravitySlider,
	HealthSlider = drawHealthSlider,
	StrengthSlider = drawStrengthSlider,
	FlingSlider = drawFlingSlider,
	SpawnPlus = drawSpawnPlus,
	KillFXPack = drawKillFXPack,
	Nuke = drawNuke,
	MoonGravity = drawMoonGravity,
	DummyRain = drawDummyRain,
	Smoke = drawSmoke,
	Decoy = drawDecoy,
	Pad = drawPad,
	Bubble = drawBubble,
	Snack = drawSnack,
}

local function pick(item)
	local fn = BY_ID[item.id]
	if fn then
		return fn
	end
	if item.kind == "roll" then
		return drawRoll
	end
	if item.kind == "title" then
		return drawTitle
	end
	if item.kind == "consumable" and tonumber(item.yen) then
		return drawYen
	end
	return nil
end

function Icons.has(item)
	return type(item) == "table" and pick(item) ~= nil
end

function Icons.draw(container, item, opts)
	if typeof(container) ~= "Instance" or not container:IsA("GuiObject") or type(item) ~= "table" then
		return false
	end
	local fn = pick(item)
	if not fn then
		return false
	end
	opts = type(opts) == "table" and opts or {}
	local root
	local ok, err = pcall(function()
		root = Instance.new("Frame")
		root.Name = "CardArt_Icon"
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		root.ZIndex = tonumber(opts.zIndex) or container.ZIndex
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = root
		fn({ root = root, z = 0, outline = false }, item, opts)
		root.Parent = container -- one parent write for the whole icon
	end)
	if not ok then
		if root then
			pcall(root.Destroy, root)
		end
		warn("[CardArt.Icons] " .. tostring(item.id) .. ": " .. tostring(err))
		return false
	end
	return true
end

return Icons
