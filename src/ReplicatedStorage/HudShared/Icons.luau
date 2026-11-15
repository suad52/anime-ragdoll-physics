--!nocheck
-- ReplicatedStorage.HudShared.Icons (2026-11-14): the HUD's drawn icons, in colour (the owner: "make the icons
-- better", "i want it to be colourful"). Every icon is built from Frames - rounded boxes with a light-to-dark gradient
-- and a darker outline of the same material, like a sticker - so there are no image ids to upload or moderate.
--   Icons.draw(name, box, opts) fills the square Frame `box` (any size: each part is a fraction of the box).
--     opts.z       base ZIndex for the parts (default box.ZIndex); each part goes one above the last
--     opts.stroke  outline width multiplier (default 1 = 1.5 px before any UIScale)
--   Icons.has(name)
-- Used by SandboxClient (hotbar, spawn menu, placing banner) and HudRails (the tile rails).
local Icons = {}
local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)

-- materials: { light (top), dark (bottom), outline }
local M = {
	wood = { C(236, 190, 128), C(184, 124, 68), C(104, 64, 30) },
	steel = { C(244, 247, 252), C(156, 166, 182), C(66, 72, 88) },
	iron = { C(150, 158, 174), C(80, 86, 102), C(34, 38, 50) },
	red = { C(255, 104, 90), C(206, 40, 42), C(112, 16, 22) },
	gold = { C(255, 230, 120), C(240, 160, 40), C(140, 82, 16) },
	skin = { C(255, 222, 180), C(238, 176, 128), C(146, 92, 58) },
	white = { C(255, 255, 255), C(206, 210, 222), C(98, 102, 118) },
	dark = { C(96, 100, 116), C(44, 46, 58), C(16, 16, 24) },
	grip = { C(70, 66, 92), C(34, 30, 48), C(12, 10, 20) },
	purple = { C(190, 140, 255), C(124, 72, 214), C(56, 26, 108) },
	green = { C(120, 236, 160), C(36, 168, 92), C(14, 84, 44) },
	paper = { C(255, 246, 214), C(236, 208, 148), C(150, 116, 64) },
	orange = { C(255, 170, 70), C(236, 100, 30), C(128, 50, 10) },
}
Icons.M = M

-- one part: centre x, y and size w, h are fractions of the box. o:
--   m     a material name or a { light, dark, outline } table: gradient + outline
--   c     a flat colour (no outline unless s)       s / sw  outline colour / width multiplier
--   r     corner: a number (scale) or a UDim; false = square; default 0.5 (a pill / circle)
--   rot   rotation in degrees    tr  transparency    gr  gradient rotation (default 90: light on the part's top)
--   line  false = a material part with no outline   text  a glyph instead of a box (drawn in c)
local function painter(box, opts)
	opts = opts or {}
	local z = opts.z or box.ZIndex
	local sw = 1.5 * (opts.stroke or 1)
	return function(x, y, w, h, o)
		o = o or {}
		z += 1
		local f
		if o.text then
			f = Instance.new("TextLabel")
			f.BackgroundTransparency = 1
			f.Text = o.text
			f.TextScaled = true
			f.FontFace = FONT
			f.TextColor3 = o.c or WHITE
		else
			f = Instance.new("Frame")
			f.BackgroundColor3 = o.c or WHITE
			f.BackgroundTransparency = o.tr or 0
		end
		f.Name = "IconPart"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Rotation = o.rot or 0
		f.BorderSizePixel = 0
		f.ZIndex = z
		if not o.text then
			local r = (o.r == nil) and 0.5 or o.r
			if r then
				local cr = Instance.new("UICorner")
				cr.CornerRadius = (typeof(r) == "UDim") and r or UDim.new(r, 0)
				cr.Parent = f
			end
			local m = (type(o.m) == "table") and o.m or (o.m and M[o.m])
			local line = o.s
			if m then
				local g = Instance.new("UIGradient")
				g.Color = ColorSequence.new(m[1], m[2])
				g.Rotation = o.gr or 90
				g.Parent = f
				if o.line ~= false then
					line = line or m[3]
				end
			end
			if line then
				local s = Instance.new("UIStroke")
				s.Color = line
				s.Thickness = sw * (o.sw or 1)
				s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				s.LineJoinMode = Enum.LineJoinMode.Round
				s.Parent = f
			end
		end
		f.Parent = box
		return f
	end
end

local D = {}

------------------------------------------------------------------------------------------------------------ hotbar
D.fists = function(P) -- your fighter's own powers: a burst
	P(0.5, 0.5, 0.98, 0.2, { m = "gold" })
	P(0.5, 0.5, 0.98, 0.2, { m = "gold", rot = 90 })
	P(0.5, 0.5, 0.8, 0.15, { m = "orange", rot = 45 })
	P(0.5, 0.5, 0.8, 0.15, { m = "orange", rot = -45 })
	P(0.5, 0.5, 0.36, 0.36, { m = { C(255, 255, 250), C(255, 226, 130), C(170, 100, 20) } })
	P(0.45, 0.44, 0.1, 0.07, { c = WHITE, rot = -30 }) -- its glint
	P(0.84, 0.16, 0.1, 0.1, { c = WHITE })
	P(0.17, 0.83, 0.07, 0.07, { c = WHITE, tr = 0.2 })
end
D.punch = function(P) -- the NORMAL choice's fists: a boxing glove
	P(0.25, 0.5, 0.26, 0.36, { m = "red", rot = -18 }) -- thumb
	P(0.55, 0.42, 0.7, 0.62, { m = "red", r = 0.42 }) -- the glove
	P(0.6, 0.25, 0.26, 0.08, { c = WHITE, tr = 0.45, rot = -8 }) -- shine
	P(0.55, 0.8, 0.58, 0.24, { m = "white", r = 0.3 }) -- the cuff
	P(0.55, 0.8, 0.58, 0.07, { c = C(206, 40, 42), r = false }) -- its stripe
end
D.grab = function(P) -- an open hand
	for _, f in ipairs({ { 0.3, 0.36, 0.38 }, { 0.45, 0.3, 0.46 }, { 0.6, 0.31, 0.44 }, { 0.745, 0.38, 0.36 } }) do
		P(f[1], f[2], 0.13, f[3], { m = "skin" })
	end
	P(0.2, 0.63, 0.13, 0.36, { m = "skin", rot = -38 }) -- thumb
	P(0.53, 0.69, 0.54, 0.46, { m = "skin", r = 0.32 }) -- palm, over the finger roots: its edge draws the knuckles
	P(0.62, 0.64, 0.2, 0.05, { c = C(214, 150, 104), tr = 0.25, rot = -12 }) -- a crease
end
D.bat = function(P)
	P(0.3, 0.7, 0.42, 0.1, { m = "wood", rot = -45 }) -- handle
	P(0.6, 0.4, 0.64, 0.22, { m = "wood", rot = -45 }) -- barrel
	P(0.565, 0.365, 0.44, 0.05, { c = WHITE, tr = 0.5, rot = -45 }) -- shine
	P(0.235, 0.765, 0.22, 0.12, { m = "grip", rot = -45 }) -- grip tape
	P(0.14, 0.86, 0.15, 0.15, { m = "wood" }) -- knob
end
D.axe = function(P) -- a fire axe
	P(0.41, 0.59, 0.82, 0.09, { m = "wood", rot = -45 }) -- handle
	P(0.58, 0.22, 0.14, 0.12, { m = "iron", rot = 45, r = UDim.new(0, 2) }) -- the pick
	P(0.722, 0.362, 0.38, 0.26, { m = "red", rot = 45, r = UDim.new(0, 3) }) -- the head
	P(0.842, 0.482, 0.1, 0.38, { m = "steel", rot = 45, r = 0.3 }) -- the edge
	P(0.77, 0.31, 0.24, 0.035, { c = WHITE, tr = 0.5, rot = 45 }) -- shine
end
D.katana = function(P)
	P(0.61, 0.39, 0.8, 0.085, { m = "steel", rot = -45, r = UDim.new(0, 2) }) -- blade
	P(0.6, 0.38, 0.72, 0.022, { c = WHITE, rot = -45, r = false }) -- its gleam
	P(0.2, 0.8, 0.28, 0.1, { m = "grip", rot = -45, r = 0.35 }) -- handle
	for _, t in ipairs({ 0.13, 0.2, 0.27 }) do
		P(t, 1 - t, 0.05, 0.05, { c = C(224, 60, 70), r = UDim.new(0, 1) }) -- the wrap's diamonds
	end
	P(0.315, 0.685, 0.08, 0.26, { m = "gold", rot = -45 }) -- guard
	P(0.08, 0.92, 0.08, 0.11, { m = "gold", rot = -45, r = 0.3 }) -- pommel
end
D.sledge = function(P)
	P(0.42, 0.58, 0.86, 0.09, { m = "wood", rot = -45 }) -- handle
	P(0.2, 0.8, 0.24, 0.11, { m = "grip", rot = -45 }) -- grip
	P(0.72, 0.28, 0.5, 0.3, { m = "iron", rot = 45, r = UDim.new(0, 3) }) -- head
	P(0.876, 0.436, 0.07, 0.32, { m = "steel", rot = 45, r = UDim.new(0, 2) }) -- its striking faces
	P(0.564, 0.124, 0.07, 0.32, { m = "steel", rot = 45, r = UDim.new(0, 2) })
	P(0.762, 0.238, 0.3, 0.035, { c = WHITE, tr = 0.55, rot = 45 }) -- shine
end
D.gun = function(P) -- a pistol, muzzle to the left
	P(0.72, 0.68, 0.27, 0.5, { m = "wood", rot = 12, r = UDim.new(0, 4) }) -- grip
	P(0.72, 0.7, 0.11, 0.3, { c = C(150, 96, 52), rot = 12, r = UDim.new(0, 2) }) -- grip panel
	P(0.52, 0.6, 0.22, 0.18, { tr = 1, s = C(140, 148, 166), sw = 0.9 }) -- trigger guard (light: a dark ring vanishes on the tile)
	P(0.5, 0.58, 0.04, 0.1, { c = C(140, 148, 166), r = false }) -- trigger
	P(0.47, 0.37, 0.86, 0.29, { m = "iron", r = UDim.new(0, 4) }) -- slide
	P(0.45, 0.285, 0.72, 0.035, { c = WHITE, tr = 0.55, r = false }) -- shine
	for _, x in ipairs({ 0.74, 0.79, 0.84 }) do
		P(x, 0.4, 0.022, 0.14, { c = C(30, 32, 42), r = false }) -- the slide's serrations
	end
	P(0.06, 0.38, 0.05, 0.14, { c = C(16, 16, 22), r = 0.3 }) -- muzzle
	P(0.15, 0.235, 0.05, 0.05, { c = C(40, 42, 54), r = false }) -- front sight
end

------------------------------------------------------------------------------------------------------- spawn menu
D.dummy = function(P) -- a training dummy, a target on its chest
	P(0.4, 0.87, 0.14, 0.26, { m = "white" })
	P(0.6, 0.87, 0.14, 0.26, { m = "white" })
	P(0.19, 0.55, 0.13, 0.38, { m = "white", rot = 14 })
	P(0.81, 0.55, 0.13, 0.38, { m = "white", rot = -14 })
	P(0.5, 0.56, 0.5, 0.46, { m = "white", r = 0.28 })
	P(0.5, 0.17, 0.3, 0.3, { m = "white" })
	P(0.5, 0.54, 0.28, 0.28, { c = C(226, 52, 52) })
	P(0.5, 0.54, 0.18, 0.18, { c = WHITE })
	P(0.5, 0.54, 0.08, 0.08, { c = C(226, 52, 52) })
end
D.gascan = function(P) -- a red jerrycan
	P(0.8, 0.2, 0.12, 0.32, { m = "gold", rot = 35, r = 0.4 }) -- spout
	P(0.86, 0.09, 0.15, 0.08, { m = "dark", rot = 35, r = UDim.new(0, 2) }) -- its cap
	P(0.46, 0.6, 0.68, 0.74, { m = "red", r = UDim.new(0, 5) }) -- the can
	P(0.38, 0.33, 0.3, 0.1, { c = C(120, 18, 24) }) -- the handle's hole
	P(0.46, 0.66, 0.5, 0.05, { c = C(170, 26, 32), rot = 38, r = false }) -- the pressed X
	P(0.46, 0.66, 0.5, 0.05, { c = C(170, 26, 32), rot = -38, r = false })
	P(0.3, 0.6, 0.06, 0.4, { c = WHITE, tr = 0.6 }) -- shine
end
D.barrel = function(P) -- a fuel drum with a hazard label
	P(0.5, 0.52, 0.68, 0.9, { m = "red", r = UDim.new(0, 5) })
	P(0.5, 0.12, 0.6, 0.06, { c = C(120, 18, 24) }) -- the rim
	P(0.5, 0.33, 0.7, 0.045, { c = C(140, 22, 28), r = false }) -- the ribs
	P(0.5, 0.73, 0.7, 0.045, { c = C(140, 22, 28), r = false })
	P(0.5, 0.53, 0.24, 0.24, { m = "gold", rot = 45, r = UDim.new(0, 2), sw = 0.8 }) -- the hazard diamond
	P(0.5, 0.55, 0.07, 0.1, { c = C(50, 30, 16) }) -- its flame
	P(0.28, 0.52, 0.06, 0.7, { c = WHITE, tr = 0.6 }) -- shine
end
D.crate = function(P) -- a wooden crate
	P(0.5, 0.5, 0.88, 0.88, { m = "wood", r = UDim.new(0, 4) })
	P(0.5, 0.5, 0.62, 0.62, { c = C(170, 112, 60), r = UDim.new(0, 2) }) -- the inset panel
	P(0.5, 0.39, 0.62, 0.025, { c = C(130, 82, 40), r = false }) -- plank seams
	P(0.5, 0.61, 0.62, 0.025, { c = C(130, 82, 40), r = false })
	P(0.5, 0.5, 0.82, 0.13, { m = "wood", rot = 45, r = UDim.new(0, 2) }) -- the brace
	for _, q in ipairs({ { 0.15, 0.15 }, { 0.85, 0.15 }, { 0.15, 0.85 }, { 0.85, 0.85 } }) do
		P(q[1], q[2], 0.06, 0.06, { c = C(70, 44, 22) }) -- nails
	end
end

----------------------------------------------------------------------------------------------------- menu tiles
D.shop = function(P) -- a gold yen coin
	P(0.5, 0.5, 0.9, 0.9, { m = "gold" })
	P(0.5, 0.5, 0.7, 0.7, { tr = 1, s = C(206, 128, 24) }) -- the rim
	P(0.5, 0.53, 0.56, 0.56, { text = "¥", c = C(150, 86, 14) })
	P(0.33, 0.27, 0.16, 0.07, { c = WHITE, tr = 0.3, rot = -40 }) -- shine
end
D.inventory = function(P) -- a purple chest with gold bands
	P(0.5, 0.32, 0.88, 0.32, { m = "purple", r = 0.45 }) -- the domed lid, under the body's top edge
	P(0.5, 0.66, 0.88, 0.5, { m = "purple", r = UDim.new(0, 4) }) -- the body
	P(0.22, 0.54, 0.1, 0.76, { m = "gold", r = UDim.new(0, 2) }) -- bands
	P(0.78, 0.54, 0.1, 0.76, { m = "gold", r = UDim.new(0, 2) })
	P(0.5, 0.5, 0.2, 0.24, { m = "gold", r = UDim.new(0, 3) }) -- the lock
	P(0.5, 0.53, 0.05, 0.09, { c = C(60, 30, 10) }) -- keyhole
	P(0.38, 0.24, 0.2, 0.05, { c = WHITE, tr = 0.5 }) -- shine
end
D.quests = function(P) -- a scroll, ticked
	P(0.5, 0.5, 0.64, 0.76, { m = "paper", r = UDim.new(0, 2) })
	P(0.5, 0.13, 0.82, 0.13, { m = "green" }) -- rollers
	P(0.5, 0.87, 0.82, 0.13, { m = "green" })
	P(0.44, 0.33, 0.32, 0.045, { c = C(150, 116, 64) }) -- lines
	P(0.48, 0.44, 0.4, 0.045, { c = C(150, 116, 64) })
	P(0.4, 0.55, 0.24, 0.045, { c = C(150, 116, 64) })
	P(0.553, 0.713, 0.1, 0.065, { c = C(36, 168, 92), rot = 45 }) -- the tick
	P(0.653, 0.668, 0.22, 0.065, { c = C(36, 168, 92), rot = -49 })
end
D.sliders = function(P) -- three tracks, three coloured knobs
	for _, s in ipairs({ { 0.18, 0.3, C(90, 230, 150) }, { 0.5, 0.7, C(186, 136, 255) }, { 0.82, 0.46, C(255, 96, 96) } }) do
		local y, k, col = s[1], s[2], s[3]
		P(0.5, y, 0.94, 0.12, { m = "dark" }) -- the track
		P((0.04 + k) / 2, y, k - 0.04, 0.08, { c = col, tr = 0.15 }) -- filled up to the knob
		P(k, y, 0.28, 0.28, { m = { col:Lerp(WHITE, 0.4), col, col:Lerp(Color3.new(), 0.55) } }) -- the knob
		P(k - 0.04, y - 0.05, 0.09, 0.06, { c = WHITE, tr = 0.35 }) -- glint
	end
end
D.taunt = function(P) -- a speech bubble, three coloured dots
	P(0.27, 0.8, 0.2, 0.2, { m = "white", rot = 45, r = UDim.new(0, 2) }) -- the tail
	P(0.5, 0.44, 0.94, 0.7, { m = "white", r = 0.45 }) -- the bubble
	P(0.29, 0.44, 0.15, 0.15, { c = C(255, 90, 130) })
	P(0.5, 0.44, 0.15, 0.15, { c = C(255, 200, 60) })
	P(0.71, 0.44, 0.15, 0.15, { c = C(80, 190, 255) })
end
D.settings = function(P) -- a steel-blue gear
	local steel = { C(214, 226, 248), C(118, 134, 172), C(48, 58, 88) }
	for k = 0, 7 do
		local a = math.rad(k * 45)
		P(0.5 + 0.37 * math.cos(a), 0.5 + 0.37 * math.sin(a), 0.2, 0.2, { m = steel, rot = k * 45, r = UDim.new(0, 2) })
	end
	P(0.5, 0.5, 0.7, 0.7, { m = steel })
	P(0.5, 0.5, 0.28, 0.28, { c = C(40, 46, 66), s = C(48, 58, 88) })
	P(0.36, 0.3, 0.16, 0.06, { c = WHITE, tr = 0.5, rot = -35 }) -- shine
end
local function sword(P, flip)
	local function X(x)
		return flip and (1 - x) or x
	end
	local rot = flip and 45 or -45
	P(X(0.56), 0.44, 0.72, 0.085, { m = "steel", rot = rot, r = UDim.new(0, 2) }) -- blade
	P(X(0.21), 0.79, 0.2, 0.09, { m = "red", rot = rot, r = 0.35 }) -- handle
	P(X(0.3), 0.7, 0.07, 0.28, { m = "gold", rot = rot }) -- guard
	P(X(0.11), 0.89, 0.1, 0.1, { m = "gold" }) -- pommel
end
D.duel = function(P) -- crossed swords
	sword(P, false)
	sword(P, true)
end

----------------------------------------------------------------------------------------------- fighter emblems
-- (2026-11-14, owner: "remove the kanji") each fighter's power, drawn - the emblem medallions show these in place of the
-- kanji glyph. Named kit_<Kits id>.
local function silhouette(P, parts, line)
	-- shapes that read as ONE outlined shape: each drawn first a little bigger in the outline colour, then the fills
	for _, s in ipairs(parts) do
		P(s[1], s[2], s[3] + 0.07, s[4] + 0.07, { c = line, rot = s[5], r = s[6] })
	end
	local out = {}
	for _, s in ipairs(parts) do
		table.insert(out, P(s[1], s[2], s[3], s[4], { m = s[7], rot = s[5], r = s[6], line = false }))
	end
	return out
end
D.kit_Normal = function(P) -- no powers: the boxing glove
	D.punch(P)
end
D.kit_Limitless = function(P) -- a void orb in an orbit ring
	P(0.5, 0.5, 0.82, 0.82, { m = { C(206, 176, 255), C(112, 60, 232), C(48, 20, 120) } })
	P(0.5, 0.5, 0.52, 0.52, { m = { C(160, 236, 255), C(40, 120, 255), C(20, 50, 140) }, line = false })
	P(0.5, 0.5, 0.22, 0.22, { c = WHITE })
	P(0.5, 0.5, 1.02, 0.3, { tr = 1, s = WHITE, sw = 1.1, rot = -22 }) -- the orbit
	P(0.36, 0.3, 0.16, 0.07, { c = WHITE, tr = 0.3, rot = -35 })
end
D.kit_Vulpine = function(P) -- a fox's face
	P(0.27, 0.3, 0.32, 0.32, { m = "orange", rot = 30, r = UDim.new(0.12, 0) }) -- ears: diamonds the head half covers
	P(0.73, 0.3, 0.32, 0.32, { m = "orange", rot = 60, r = UDim.new(0.12, 0) })
	P(0.28, 0.32, 0.15, 0.15, { c = C(255, 226, 200), rot = 30, r = UDim.new(0.12, 0) })
	P(0.72, 0.32, 0.15, 0.15, { c = C(255, 226, 200), rot = 60, r = UDim.new(0.12, 0) })
	P(0.5, 0.58, 0.82, 0.64, { m = "orange", r = 0.45 }) -- head
	P(0.5, 0.74, 0.5, 0.32, { m = "white", sw = 0.8 }) -- muzzle
	P(0.5, 0.64, 0.13, 0.09, { c = C(40, 28, 28) }) -- nose
	P(0.33, 0.52, 0.08, 0.12, { c = C(40, 28, 28) }) -- eyes
	P(0.67, 0.52, 0.08, 0.12, { c = C(40, 28, 28) })
end
-- a straight stroke from (x1, y1) to (x2, y2), th thick, as a silhouette part (centre, size, rotation)
local function seg(x1, y1, x2, y2, th, r, m)
	local dx, dy = x2 - x1, y2 - y1
	return { (x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy) + th * 0.5, th, math.deg(math.atan2(dy, dx)), r, m }
end
local function bolt(P, m, line)
	-- a zig-zag: down-left, a short kick right, down-left again; thick at the top, thinning to the point
	silhouette(P, {
		seg(0.72, 0.05, 0.4, 0.5, 0.2, UDim.new(0, 2), m),
		seg(0.4, 0.5, 0.64, 0.47, 0.17, UDim.new(0, 2), m),
		seg(0.64, 0.47, 0.3, 0.95, 0.13, UDim.new(0, 2), m),
	}, line)
end
D.kit_Godspeed = function(P) -- a blue bolt with speed lines
	P(0.13, 0.3, 0.18, 0.05, { c = C(170, 220, 255) })
	P(0.1, 0.44, 0.12, 0.05, { c = C(170, 220, 255), tr = 0.3 })
	P(0.88, 0.6, 0.16, 0.05, { c = C(170, 220, 255) })
	bolt(P, { C(230, 248, 255), C(60, 170, 255) }, C(16, 60, 140))
end
D.kit_OneForAll = function(P) -- a green power fist, crackling
	P(0.17, 0.24, 0.22, 0.05, { c = C(120, 255, 170), rot = 40 })
	P(0.84, 0.2, 0.22, 0.05, { c = C(120, 255, 170), rot = -40 })
	P(0.88, 0.62, 0.18, 0.05, { c = C(120, 255, 170), rot = 20 })
	P(0.27, 0.52, 0.24, 0.32, { m = "green", rot = -18 }) -- thumb
	P(0.55, 0.45, 0.66, 0.56, { m = "green", r = 0.38 }) -- the fist
	for k = 0, 2 do
		P(0.43 + k * 0.13, 0.33, 0.035, 0.16, { c = C(20, 110, 60) }) -- finger creases
	end
	P(0.55, 0.8, 0.5, 0.2, { m = "red", r = 0.3 }) -- a red cuff
end
D.kit_Tempest = function(P) -- an eye with a violet iris, lightning at its corner
	P(0.5, 0.52, 0.96, 0.56, { m = "white" })
	P(0.5, 0.52, 0.46, 0.46, { m = { C(224, 176, 255), C(120, 50, 220), C(50, 20, 110) } })
	P(0.5, 0.52, 0.18, 0.18, { c = C(20, 14, 30) })
	P(0.44, 0.44, 0.08, 0.08, { c = WHITE })
	P(0.84, 0.16, 0.08, 0.28, { c = C(200, 160, 255), rot = 25 })
	P(0.77, 0.28, 0.16, 0.06, { c = C(200, 160, 255), rot = -12 })
end
D.kit_Carver = function(P) -- three claw slashes
	for k = -1, 1 do
		P(0.5 + k * 0.21, 0.5, 0.13, 0.94, { m = "red", rot = 28 })
	end
	for k = -1, 1 do
		P(0.5 + k * 0.21, 0.5, 0.035, 0.66, { c = C(110, 0, 14), rot = 28 })
	end
end
D.kit_Shifter = function(P) -- two crossed blades, teal grips
	for _, flip in ipairs({ false, true }) do
		local function X(x)
			return flip and (1 - x) or x
		end
		local rot = flip and 45 or -45
		P(X(0.58), 0.42, 0.78, 0.075, { m = "steel", rot = rot, r = UDim.new(0, 1) })
		P(X(0.31), 0.69, 0.05, 0.2, { m = "iron", rot = rot })
		P(X(0.19), 0.81, 0.24, 0.12, { m = { C(130, 236, 206), C(30, 150, 120), C(10, 70, 55) }, rot = rot, r = 0.3 })
	end
end
D.kit_Zangetsu = function(P) -- a huge black cleaver, edge out
	local black = { C(84, 88, 106), C(22, 24, 32), C(4, 4, 8) }
	P(0.24, 0.84, 0.13, 0.3, { m = "white", rot = 40, r = 0.3 }) -- the wrapped grip
	for _, t in ipairs({ 0.78, 0.86 }) do
		P(0.24 + (t - 0.84) * -0.64, t, 0.14, 0.03, { c = C(40, 40, 50), rot = 40, r = false }) -- its wrap
	end
	P(0.56, 0.44, 0.44, 0.8, { m = black, rot = 40, r = UDim.new(0, 2) }) -- the broad blade
	P(0.68, 0.53, 0.06, 0.74, { c = C(226, 234, 246), rot = 40, r = false }) -- the bright edge
	P(0.1, 0.97, 0.2, 0.06, { c = C(220, 40, 50), rot = -25 }) -- a tassel
end
D.kit_Ascendant = function(P) -- a golden flame of ki
	silhouette(P, {
		{ 0.26, 0.52, 0.26, 0.26, 45, UDim.new(0.25, 0), "gold" }, -- side tongues
		{ 0.74, 0.5, 0.24, 0.24, 45, UDim.new(0.25, 0), "gold" },
		{ 0.5, 0.4, 0.5, 0.5, 45, UDim.new(0.25, 0), "gold" },
		{ 0.5, 0.63, 0.66, 0.66, 0, 0.5, "gold" },
	}, C(150, 86, 14))
	P(0.5, 0.58, 0.28, 0.28, { c = C(255, 250, 222), rot = 45, r = UDim.new(0.25, 0) })
	P(0.5, 0.7, 0.36, 0.36, { c = C(255, 250, 222) })
	P(0.17, 0.3, 0.08, 0.08, { c = C(255, 230, 120) })
	P(0.85, 0.38, 0.06, 0.06, { c = C(255, 230, 120) })
end
D.kit_Gomu = function(P) -- a straw hat
	local straw = { C(255, 228, 146), C(222, 170, 70), C(120, 80, 20) }
	P(0.5, 0.66, 0.98, 0.26, { m = straw }) -- brim
	P(0.5, 0.44, 0.56, 0.42, { m = straw, r = 0.45 }) -- crown
	P(0.5, 0.57, 0.58, 0.1, { c = C(210, 40, 44), r = false }) -- the red band
	P(0.4, 0.33, 0.14, 0.06, { c = WHITE, tr = 0.4, rot = -20 })
end
D.kit_Stormdraw = function(P) -- a yellow bolt in a flash
	P(0.5, 0.5, 0.86, 0.86, { c = C(255, 240, 150), tr = 0.55 })
	bolt(P, { C(255, 252, 210), C(255, 190, 30) }, C(140, 80, 0))
end
D.star = function(P) -- a gold sparkle: what a badge shows when its glyph was a kanji and it has no art
	P(0.5, 0.5, 0.18, 0.96, { m = "gold" })
	P(0.5, 0.5, 0.96, 0.18, { m = "gold" })
	P(0.5, 0.5, 0.42, 0.42, { m = "gold", rot = 45, r = UDim.new(0.2, 0) })
	P(0.45, 0.45, 0.1, 0.1, { c = WHITE })
end

D.map = function(P) -- (2026-11-14) MAPS: a folded map, green land and blue water, a red pin
	P(0.21, 0.5, 0.3, 0.74, { m = "paper", r = UDim.new(0, 2), rot = -4 })
	P(0.5, 0.52, 0.3, 0.74, { m = "paper", r = UDim.new(0, 2), rot = 4 })
	P(0.79, 0.5, 0.3, 0.74, { m = "paper", r = UDim.new(0, 2), rot = -4 })
	P(0.27, 0.42, 0.24, 0.3, { c = C(64, 176, 92), r = 0.4 }) -- land
	P(0.62, 0.66, 0.3, 0.22, { c = C(64, 176, 92), r = 0.4 })
	P(0.66, 0.34, 0.16, 0.14, { c = C(70, 150, 230), r = 0.5 }) -- a lake
	P(0.42, 0.7, 0.07, 0.07, { c = C(150, 116, 64), r = 0.5 }) -- the path
	P(0.5, 0.56, 0.07, 0.07, { c = C(150, 116, 64), r = 0.5 })
	P(0.42, 0.24, 0.24, 0.24, { m = "red" }) -- the pin
	P(0.42, 0.36, 0.08, 0.16, { m = "red", r = UDim.new(0, 1) })
	P(0.39, 0.21, 0.08, 0.06, { c = WHITE, tr = 0.3 })
end
-- (2026-11-15) BOW (the hotbar's 8th slot): a recurve bow on its string, an arrow nocked across it
D.bow = function(P)
	P(0.36, 0.27, 0.1, 0.46, { m = "wood", rot = 19 }) -- upper limb
	P(0.36, 0.73, 0.1, 0.46, { m = "wood", rot = -19 }) -- lower limb
	P(0.29, 0.5, 0.13, 0.24, { m = { C(120, 80, 54), C(70, 44, 28), C(36, 20, 10) }, r = 0.35 }) -- the grip
	P(0.44, 0.07, 0.11, 0.11, { m = "gold" }) -- tips
	P(0.44, 0.93, 0.11, 0.11, { m = "gold" })
	P(0.445, 0.5, 0.03, 0.84, { c = C(240, 236, 226), r = false }) -- the string
	P(0.6, 0.5, 0.62, 0.055, { m = "wood", r = false }) -- the arrow
	P(0.91, 0.5, 0.13, 0.13, { m = "steel", rot = 45, r = UDim.new(0, 1) }) -- its head
	P(0.33, 0.44, 0.15, 0.05, { m = "red", rot = -30, r = 0.3 }) -- fletching
	P(0.33, 0.56, 0.15, 0.05, { m = "red", rot = 30, r = 0.3 })
end
-- (2026-11-15) CAMERA (Free Cam / Photo Mode, the PHOTO tile): a camera with a big lens and a flash
D.camera = function(P)
	P(0.36, 0.24, 0.24, 0.12, { m = "dark", r = UDim.new(0, 2) }) -- the viewfinder hump
	P(0.5, 0.56, 0.86, 0.56, { m = "dark", r = 0.18 }) -- the body
	P(0.5, 0.56, 0.42, 0.42, { m = "steel" }) -- the lens ring
	P(0.5, 0.56, 0.3, 0.3, { m = { C(120, 200, 255), C(30, 80, 170), C(10, 30, 70) } }) -- the glass
	P(0.45, 0.5, 0.08, 0.08, { c = WHITE, tr = 0.15 }) -- its glint
	P(0.78, 0.38, 0.12, 0.08, { m = "gold", r = UDim.new(0, 2) }) -- the flash
end
-- (2026-11-15) ANYONE (Dummy of Anyone, the spawn menu): an avatar - hair, a face, a blue shirt - with a green "+"
D.anyone = function(P)
	P(0.38, 0.88, 0.13, 0.24, { m = "dark" }) -- legs
	P(0.56, 0.88, 0.13, 0.24, { m = "dark" })
	P(0.2, 0.58, 0.12, 0.34, { m = "skin", rot = 10 }) -- arms
	P(0.74, 0.58, 0.12, 0.34, { m = "skin", rot = -10 })
	P(0.47, 0.6, 0.44, 0.4, { m = { C(120, 190, 255), C(40, 110, 220), C(16, 50, 120) }, r = 0.25 }) -- shirt
	P(0.47, 0.25, 0.32, 0.32, { m = "skin" }) -- head
	P(0.47, 0.13, 0.36, 0.14, { m = { C(150, 100, 60), C(96, 60, 30), C(52, 30, 12) }, r = 0.45 }) -- hair
	P(0.41, 0.27, 0.04, 0.06, { c = C(30, 24, 20) }) -- eyes
	P(0.53, 0.27, 0.04, 0.06, { c = C(30, 24, 20) })
	P(0.47, 0.34, 0.1, 0.03, { c = C(150, 70, 60) }) -- smile
	P(0.82, 0.22, 0.28, 0.28, { m = "green" }) -- the "+" badge
	P(0.82, 0.22, 0.16, 0.05, { c = WHITE, r = false })
	P(0.82, 0.22, 0.05, 0.16, { c = WHITE, r = false })
end

function Icons.has(name)
	return D[name] ~= nil
end
function Icons.draw(name, box, opts)
	local fn = D[name]
	if not fn then
		return false
	end
	fn(painter(box, opts))
	return true
end
Icons.names = {}
for k in pairs(D) do
	table.insert(Icons.names, k)
end
table.sort(Icons.names)
return Icons
