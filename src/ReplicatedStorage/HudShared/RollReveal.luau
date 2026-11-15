--!nocheck
-- HudShared.RollReveal (2026-11-10): the full-screen gacha reveal for the RANDOM shop rolls. CLIENT only.
-- CharacterSelect calls it from its LastRoll listener:
--   RollReveal.play({ cat = "emote"|"ko"|"skin", ids = { wonId, ... }, pool = { { id }, ... }, color = Color3,
--                     noun = "EMOTE", nameOf = function(id) -> string, pick = n (10-roll free picks) }) -- yields until closed
-- EVERY roll is a reel of item cards - each card shows the item's CardArt LOGO - spinning past a gold marker:
--   1 item: one wide reel; the prize then pops into a big card with rays, confetti and NEW!.
--   5 / 10 items: one reel per item, STACKED on top of each other, landing one after another. A 10x takes two stacks of
--   five when ten rows would make the cards too small, and on a screen too short for either (a phone in landscape)
--   VERTICAL reels side by side instead. Then every prize shows as a card in a grid.
-- A click anywhere skips the spin; a click on the result closes it (it also closes by itself after a few seconds).
--
-- VIEWPORT RULES (measured in Play, 2026-11-10, with a test rig of CardArt logos in clipped rows): every CardArt logo is
-- a ViewportFrame (its 3D figure; the comic panel behind it is plain UI).
--   * MOVING is free: 36 logos sliding at 0-48 px a frame, with or without a UIScale above them, all stay drawn.
--   * A logo that leaves its clipping window ENTIRELY loses its drawing, and the fresh draw it needs when it comes back
--     (like one that is switched on, re-parented or just built) is rationed per frame and sometimes dropped: the same
--     rig with a ring longer than its window (spare cards fully clipped part of the time) came out ~25% blank, and the
--     first version of these reels - spare cards parked outside the window - left whole reels blank (the ones built
--     last starve). Hiding the spares (Visible = false) or unparenting them did not help.
-- So each reel is a RING of K cards that are ALL inside the window ALL the time: the window is exactly one card
-- shorter than the ring (len = K * step - card + 1), so the card that wraps around keeps a 1-unit sliver in view, under
-- the edge fade, at both ends. No logo is ever hidden, toggled or rebuilt during a spin. The sequence therefore repeats
-- every K cards (unnoticeable at speed). K is capped so all reels together move at most LOGO_BUDGET logos (36 measured
-- fine), which is what sets 4 cards per reel on a 10x. A reel that lands gets one redraw kick per logo, to be safe.
--
-- LAYOUT: everything is laid out on a canvas of (screen / scale) units under ONE UIScale on a root frame that is
-- exactly that size and centred - a full-screen root under a UIScale grows from its top-left corner and pushed the
-- whole reveal off centre (off the screen corner on a phone).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HS = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(HS:WaitForChild("Kits"))
local CardArt
do
	local ok, m = pcall(function()
		return require(HS:WaitForChild("CardArt", 5))
	end)
	CardArt = ok and m or nil
end

local RollReveal = {}

local INK = Color3.fromRGB(14, 12, 24)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 70)
local FONT_BIG = Kits.FONT_PUNCH or Font.fromEnum(Enum.Font.LuckiestGuy)
local FONT_LABEL = Kits.FONT_LABEL or Font.fromEnum(Enum.Font.GothamBold)
local FONT_GLYPH = Font.fromEnum(Enum.Font.GothamBlack)
local CAT_GLYPH = { emote = "舞", ko = "爆", skin = "色" }
-- a 10x roll is 9 random + 1 FREE PICK (ShopService picksFor / Ext.RollPicks; the player chooses it in the shop's ROLL
-- tab): the pick still gets its own reel - the last one - and lands on this gold "?" card
local PICK = "\0PICK"

local TILE_W, TILE_H = 118, 150 -- the single reel's cards (canvas units); also the biggest a stacked reel's card gets
local NAME_ASPECT = 1.27 -- card height / width when it has a name strip under the logo
local GAP = 12 -- between cards along a reel
local PAD = 6 -- a reel window's margin across its axis
local LOGO_BUDGET = 40 -- ring cards (= moving logos) across all reels (see the header)
local CARDS_PER_SEC = 9.5 -- average cards past the marker per second of spin
local SETTLE = 0.35 -- the overshoot-and-back as a reel lands
-- multi-reel layout (canvas units)
local TOP, BOTTOM, SIDE = 84, 44, 24 -- room for the title above and the footer below
local REEL_BOTTOM = 14 -- the reels' bottom margin (the footer is not up while they spin)
local ROW_GAP, COL_GAP = 8, 24
local MIN_L, MAX_L = 3.2, 5.4 -- a reel window's length in cards (the 1x reel shows ~5; LOGO_BUDGET caps a 10x at 4)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o)
end
local function stroke(o, c, t)
	return new("UIStroke", { Color = c or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function ink(lbl, t)
	new("UIStroke", { Color = INK, Thickness = t or 2 }, lbl)
	return lbl
end
local function label(parent, props)
	local l = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, FontFace = FONT_BIG, TextScaled = true, TextWrapped = true,
		Text = "", ZIndex = 5 }, parent)
	for k, v in pairs(props) do
		l[k] = v
	end
	return l
end
local function tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end
local function sound(parent, id, vol)
	return new("Sound", { SoundId = id, Volume = vol or 0.5 }, parent)
end
local function playSound(s, speed)
	pcall(function()
		if speed then
			s.PlaybackSpeed = speed
		end
		s:Play()
	end)
end

local function burstRays(parent, color, z)
	local holder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(900, 900),
		BackgroundTransparency = 1, ZIndex = z }, parent)
	for i = 1, 12 do
		local r = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 46),
			Rotation = (i - 1) * 15, BackgroundColor3 = color, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = z }, holder)
		new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0),
			NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(0.58, 0), NumberSequenceKeypoint.new(1, 1) }) }, r)
	end
	return holder
end

local function confetti(parent, colors, z, n, spread)
	spread = spread or 420
	for _ = 1, n or 46 do
		local c = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(math.random(7, 13), math.random(10, 18)), Rotation = math.random(0, 360),
			BackgroundColor3 = colors[math.random(1, #colors)], BorderSizePixel = 0, ZIndex = z }, parent)
		local ang = math.random() * math.pi * 2
		local dist = math.random(180, math.max(220, math.floor(spread)))
		local t = math.random(70, 120) / 100
		tween(c, t, { Position = UDim2.new(0.5, math.cos(ang) * dist, 0.46, math.sin(ang) * dist * 0.8 + 140), Rotation = c.Rotation + math.random(-400, 400),
			BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(t + 0.05, function()
			c:Destroy()
		end)
	end
end

-- fade every piece of a subtree (frames, text, images, the logos' ViewportFrames, outlines)
local function fadeOut(container, t)
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("GuiObject") then
			local goal = { BackgroundTransparency = 1 }
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				goal.TextTransparency = 1
			elseif d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("ViewportFrame") then
				goal.ImageTransparency = 1
			end
			pcall(tween, d, t, goal)
		elseif d:IsA("UIStroke") then
			pcall(tween, d, t, { Transparency = 1 })
		end
	end
end

-- force a redraw of a logo that was just switched on (a shown ViewportFrame is sometimes never drawn until something
-- INSIDE it changes - moving it on screen does not count): a tiny FOV twitch, twice for a logo that stands still, once
-- for one on a spinning reel (it passes the marker in a moment anyway). BaseFov is the attribute CardArt's nudge keeps.
local function kick(vp, once)
	local cam = vp and vp.CurrentCamera
	if not cam then
		return
	end
	local base = cam:GetAttribute("BaseFov") or cam.FieldOfView
	cam:SetAttribute("BaseFov", base)
	for i, at in ipairs(once and { 0 } or { 0, 0.3 }) do
		task.delay(at, function()
			if cam.Parent then
				cam.FieldOfView = base + 0.015 * i
				task.delay(0.08, function()
					if cam.Parent then
						cam.FieldOfView = base
					end
				end)
			end
		end)
	end
end

local function itemFor(cat, id)
	return { kind = cat, id = id, kit = cat == "skin" and id or nil }
end

-- the FREE PICK card's art: gold, a glow, a big "?" (plain UI - no ViewportFrame, so it costs no render budget)
local function pickArt(art)
	local z = art.ZIndex
	local f = new("Frame", { Name = "PickArt", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true,
		ZIndex = z + 1 }, art)
	local uc = art:FindFirstChildOfClass("UICorner")
	new("UICorner", { CornerRadius = uc and uc.CornerRadius or UDim.new(0, 8) }, f)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 140, 30)) }, f)
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromScale(0.8, 0.8), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = z + 2 }, f)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, glow)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	ink(label(f, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromScale(0.72, 0.72), Text = "?", ZIndex = z + 3 }), 3)
	ink(label(f, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromScale(0.92, 0.2), Text = "YOU CHOOSE",
		TextColor3 = WHITE, ZIndex = z + 3 }), 2)
end

-- the item's CardArt logo filling `art` (the category kanji if CardArt has none)
local function drawArt(art, cat, id, live)
	if id == PICK then
		pickArt(art)
		return true
	end
	local drew = false
	if CardArt then
		local ok, res = pcall(CardArt.draw, art, itemFor(cat, id), { live = live or nil })
		drew = ok and res == true
	end
	if not drew then
		ink(label(art, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = CAT_GLYPH[cat] or "?", FontFace = FONT_GLYPH,
			ZIndex = art.ZIndex + 1 }), 2.5)
	end
	return drew
end

-- a reel card: the category colour round the item's logo, with the item name under it when there is room
local function artTile(parent, cat, id, name, color, w, h, z, showName)
	local f = new("Frame", { Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z }, parent)
	local r = math.max(6, math.floor(w * 0.1))
	corner(f, r)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.18), color:Lerp(INK, 0.55)) }, f)
	local st = stroke(f, INK, w >= 90 and 3 or 2)
	local pad = math.max(3, math.floor(w * 0.045))
	local nameH = showName and math.floor(h * 0.2) or 0
	local art = new("Frame", { Name = "Art", Position = UDim2.fromOffset(pad, pad), Size = UDim2.fromOffset(w - pad * 2, h - pad * 2 - nameH),
		BackgroundColor3 = INK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = z + 1 }, f)
	corner(art, math.max(4, r - pad))
	drawArt(art, cat, id)
	if showName then
		local n = ink(label(f, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -math.max(2, math.floor(pad * 0.5))),
			Size = UDim2.new(1, -pad * 2, 0, nameH), Text = name, ZIndex = z + 2 }), 2)
		new("UITextSizeConstraint", { MaxTextSize = 22 }, n)
	end
	return f, st
end

-- how many ring cards a reel gets and its exact window length: every card must stay at least partly inside the
-- window (see the header), so len = K * step - along + 1. wantLen = the length the layout would like; maxK = this
-- reel's share of LOGO_BUDGET.
local function ringFit(wantLen, along, maxK)
	local step = along + GAP
	local K = math.clamp(math.floor((wantLen + along - 1) / step), 3, math.max(3, maxK))
	return K, K * step - along + 1
end

-- one reel: a window holding a RING of K cards. Sequence position i (0, 1, 2 ...) is drawn by card i % K, and the
-- window is one card shorter than the ring, so all K cards are always (at least partly) in view. Position i's centre
-- sits at i*step + step/2 - offset along the reel (horizontal: from the left edge, cards slide LEFT; vertical: from
-- the bottom edge, cards roll DOWN). A spin raises `offset` until position T is under the marker.
-- o = { cat, prize, pool = { ids }, nameOf, color, vertical, tw, th, showName, K, len, pos, z, T, small }
local function newReel(root, o)
	local vertical = o.vertical
	local along = vertical and o.th or o.tw
	local step = along + GAP
	local K, len = o.K, o.len
	local crossLen = (vertical and o.tw or o.th) + PAD * 2
	local window = new("Frame", { Name = "Reel", AnchorPoint = Vector2.new(0.5, 0.5), Position = o.pos,
		Size = vertical and UDim2.fromOffset(crossLen, len) or UDim2.fromOffset(len, crossLen),
		BackgroundColor3 = INK, BackgroundTransparency = 0.15, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = o.z }, root)
	corner(window, o.small and 10 or 16)
	local wStroke = stroke(window, o.color, o.small and 2 or 3)
	local strip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = o.z + 1 }, window)

	local pool = (type(o.pool) == "table" and #o.pool > 0) and o.pool or { o.prize }
	local T = o.T
	local kPrize = T % K
	-- what each ring card shows: the prize on its card, the rest from a shuffled bag, never next to its own twin
	local items = { [kPrize] = o.prize }
	local bag = {}
	local function fromBag()
		if #bag == 0 then
			for _, id in ipairs(pool) do
				table.insert(bag, math.random(1, #bag + 1), id)
			end
		end
		return table.remove(bag)
	end
	for k = 0, K - 1 do
		if k ~= kPrize then
			local id
			for _ = 1, 8 do
				id = fromBag()
				if #pool < 3 or (id ~= items[(k - 1) % K] and id ~= items[(k + 1) % K]) then
					break
				end
			end
			items[k] = id
		end
	end
	local tiles = {}
	for k = 0, K - 1 do
		local f, st = artTile(strip, o.cat, items[k], o.nameOf(items[k]), o.color, o.tw, o.th, o.z + 2, o.showName)
		tiles[k] = { f = f, st = st, vp = f:FindFirstChildWhichIsA("ViewportFrame", true) }
	end

	-- the gold marker across the middle, pointers at both ends
	local marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = vertical and UDim2.new(1, 8, 0, 4) or UDim2.new(0, 4, 1, 8), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = o.z + 9 }, window)
	local mScale = new("UIScale", {}, marker)
	local ptr = math.clamp(math.floor(crossLen * 0.2), 16, 34)
	for _, first in ipairs({ true, false }) do
		local tri
		if vertical then
			tri = label(window, { AnchorPoint = Vector2.new(first and 0 or 1, 0.5), Position = UDim2.new(first and 0 or 1, first and -4 or 4, 0.5, 0),
				Size = UDim2.fromOffset(ptr, ptr), Text = first and "▶" or "◀", TextColor3 = GOLD, FontFace = FONT_GLYPH, ZIndex = o.z + 10 })
		else
			tri = label(window, { AnchorPoint = Vector2.new(0.5, first and 0 or 1), Position = UDim2.new(0.5, 0, first and 0 or 1, first and -6 or 6),
				Size = UDim2.fromOffset(ptr, math.floor(ptr * 0.9)), Text = first and "▼" or "▲", TextColor3 = GOLD, FontFace = FONT_GLYPH, ZIndex = o.z + 10 })
		end
		ink(tri, 2)
	end
	-- edge fades so cards slide in and out of the dark (and hide the sliver of the card that is wrapping round)
	local fadeLen = math.floor(math.min(90, len * 0.2))
	for _, first in ipairs({ true, false }) do
		local fade
		if vertical then
			fade = new("Frame", { AnchorPoint = Vector2.new(0, first and 0 or 1), Position = UDim2.fromScale(0, first and 0 or 1), Size = UDim2.new(1, 0, 0, fadeLen),
				BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = o.z + 8 }, window)
			new("UIGradient", { Rotation = first and 90 or 270, Transparency = NumberSequence.new(0, 1) }, fade)
		else
			fade = new("Frame", { AnchorPoint = Vector2.new(first and 0 or 1, 0), Position = UDim2.fromScale(first and 0 or 1, 0), Size = UDim2.new(0, fadeLen, 1, 0),
				BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = o.z + 8 }, window)
			new("UIGradient", { Rotation = first and 0 or 180, Transparency = NumberSequence.new(0, 1) }, fade)
		end
	end

	local reel = { window = window, wStroke = wStroke, tiles = tiles, K = K, kPrize = kPrize, T = T, step = step, len = len, mScale = mScale,
		offset = -1, fit = (crossLen - 8) / (vertical and o.tw or o.th) }
	reel.offEnd = T * step + step / 2 - len / 2
	local ring = K * step
	local x0 = 1 - along -- a card's leading edge runs over [x0, x0 + ring): never fully out of the window
	function reel.place(offset)
		offset = math.floor(offset + 0.5) -- whole units
		if offset == reel.offset then
			return
		end
		reel.offset = offset
		for k = 0, K - 1 do
			local x = (k * step + step / 2 - along / 2 - offset - x0) % ring + x0
			tiles[k].f.Position = vertical and UDim2.fromOffset(PAD, len - x - along) or UDim2.fromOffset(x, PAD)
		end
	end
	-- which sequence position is under the marker
	function reel.under(offset)
		return math.floor((offset + len / 2) / step)
	end
	function reel.kickAll()
		for k = 0, K - 1 do
			kick(tiles[k].vp)
		end
	end
	reel.destroy = function()
		window:Destroy()
	end
	reel.place(0)
	return reel
end

-- the reels for a 5 / 10 roll on a canvas of cw x ch units (scale = canvas units -> screen pixels)
local function layoutMulti(n, cw, ch, scale)
	-- the reels may run down to the bottom margin: the footer only appears once they are gone
	local aw, ah = cw - SIDE * 2, ch - TOP - REEL_BOTTOM
	local maxK = math.floor(LOGO_BUDGET / n)
	local cands = {}
	-- horizontal reels stacked on top of each other (one stack; two stacks of five for 6+)
	for _, c in ipairs(n >= 6 and { 1, 2 } or { 1 }) do
		local r = math.ceil(n / c)
		local colW = (aw - (c - 1) * COL_GAP) / c
		local thAvail = (ah - (r - 1) * ROW_GAP) / r - PAD * 2
		local twMax = math.min(TILE_W, colW / MIN_L - GAP)
		-- a 5x always stacks (vertical reels were only allowed for a 10x that will not fit); a 10x takes one stack of
		-- ten when its cards are big enough, else two stacks of five
		local L = { vertical = false, rows = r, cols = c, need = (n <= 5 and 0) or (c == 1 and 72 or 56) }
		if math.min(twMax, thAvail / NAME_ASPECT) >= 96 then
			L.tw = math.floor(math.min(twMax, thAvail / NAME_ASPECT))
			L.th = math.floor(L.tw * NAME_ASPECT)
			L.showName = true
		else
			L.tw = math.floor(math.min(twMax, thAvail))
			L.th = L.tw
		end
		L.K, L.len = ringFit(math.min(MAX_L * (L.tw + GAP), colW), L.tw, maxK)
		table.insert(cands, L)
	end
	-- vertical reels side by side (one row; two rows for 6+) - a phone in landscape: keep clear of the notch (the gui
	-- ignores the safe-area inset, about 44 pt each side in landscape)
	local vaw = cw - 2 * math.max(SIDE, math.ceil(48 / scale))
	for _, rr in ipairs(n >= 6 and { 1, 2 } or { 1 }) do
		local c = math.ceil(n / rr)
		local rowH = (ah - (rr - 1) * ROW_GAP) / rr
		local twMax = math.min(TILE_W, (vaw - (c - 1) * ROW_GAP) / c - PAD * 2)
		local L = { vertical = true, rows = rr, cols = c, need = 44 }
		local twNamed = math.min(twMax, (rowH / MIN_L - GAP) / NAME_ASPECT)
		if twNamed >= 84 then
			L.tw = math.floor(twNamed)
			L.th = math.floor(L.tw * NAME_ASPECT)
			L.showName = true
		else
			L.tw = math.floor(math.min(twMax, rowH / MIN_L - GAP))
			L.th = L.tw
		end
		L.K, L.len = ringFit(math.min(MAX_L * (L.th + GAP), rowH), L.th, maxK)
		table.insert(cands, L)
	end
	-- stacked horizontal reels (what was asked for) whenever their cards come out big enough on screen; otherwise
	-- the vertical layout with the biggest cards (unless a horizontal one is bigger still)
	local pick
	for _, L in ipairs(cands) do
		if not L.vertical and L.tw * scale >= L.need then
			pick = L
			break
		end
	end
	if not pick then
		for _, L in ipairs(cands) do
			if L.vertical and (not pick or L.tw > pick.tw) then
				pick = L
			end
		end
		for _, L in ipairs(cands) do
			if not L.vertical and L.tw > pick.tw then
				pick = L
			end
		end
	end
	pick.small = pick.tw < 90
	-- each reel's centre on the canvas: horizontal stacks fill top to bottom then the next stack; vertical reels fill
	-- left to right then the next row - so they land in reading order
	pick.pos = {}
	if pick.vertical then
		local wW = pick.tw + PAD * 2
		local totalW = pick.cols * wW + (pick.cols - 1) * ROW_GAP
		local totalH = pick.rows * pick.len + (pick.rows - 1) * ROW_GAP
		local x0 = (cw - totalW) / 2 + wW / 2
		local y0 = TOP + (ah - totalH) / 2 + pick.len / 2
		for i = 1, n do
			local col, row = (i - 1) % pick.cols, math.floor((i - 1) / pick.cols)
			pick.pos[i] = UDim2.fromOffset(math.floor(x0 + col * (wW + ROW_GAP)), math.floor(y0 + row * (pick.len + ROW_GAP)))
		end
	else
		local wH = pick.th + PAD * 2
		local totalW = pick.cols * pick.len + (pick.cols - 1) * COL_GAP
		local totalH = pick.rows * wH + (pick.rows - 1) * ROW_GAP
		local x0 = (cw - totalW) / 2 + pick.len / 2
		local y0 = TOP + (ah - totalH) / 2 + wH / 2
		for i = 1, n do
			local col, row = math.floor((i - 1) / pick.rows), (i - 1) % pick.rows
			pick.pos[i] = UDim2.fromOffset(math.floor(x0 + col * (pick.len + COL_GAP)), math.floor(y0 + row * (wH + ROW_GAP)))
		end
	end
	return pick
end

local busy = false
function RollReveal.isPlaying()
	return busy
end

-- exposed for tests: the layout a roll of n items gets on a screen of w x h pixels
function RollReveal.layoutFor(n, w, h)
	local scale = math.clamp(math.min(w / 900, h / 620), 0.55, 1.15)
	return layoutMulti(n, w / scale, h / scale, scale), scale
end

function RollReveal.play(o)
	if busy or type(o) ~= "table" or type(o.ids) ~= "table" or #o.ids == 0 then
		return
	end
	busy = true
	local ok, err = pcall(function()
		local player = Players.LocalPlayer
		local cat, won = o.cat, o.ids
		-- the reels: every item won, then one more per free pick (a 10x = 9 + 1)
		local picks = math.clamp(math.floor(tonumber(o.pick) or 0), 0, 3)
		local ids = table.clone(won)
		for _ = 1, picks do
			table.insert(ids, PICK)
		end
		local n = #ids
		local color = typeof(o.color) == "Color3" and o.color or GOLD
		local nameOf = type(o.nameOf) == "function" and o.nameOf or function(id)
			return string.upper(tostring(id))
		end
		local safeName = function(id)
			if id == PICK then
				return "FREE PICK"
			end
			local okN, s = pcall(nameOf, id)
			return okN and type(s) == "string" and s or string.upper(tostring(id))
		end
		local pool = {}
		if type(o.pool) == "table" then
			for _, x in ipairs(o.pool) do
				local id = type(x) == "table" and x.id or x
				if id ~= nil then
					table.insert(pool, id)
				end
			end
		end
		if #pool == 0 then
			pool = table.clone(won)
		end

		local gui = new("ScreenGui", { Name = "RollReveal", DisplayOrder = 95, IgnoreGuiInset = true, ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
		local shade = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 6, 18), BackgroundTransparency = 1,
			Text = "", AutoButtonColor = false, ZIndex = 1 }, gui)
		gui.Parent = player:WaitForChild("PlayerGui")
		-- o.viewport (Vector2, tests only): lay out for that screen size, centred - how a phone layout is checked in Studio
		local vp = typeof(o.viewport) == "Vector2" and o.viewport or gui.AbsoluteSize
		if vp.X < 10 or vp.Y < 10 then
			local cam = workspace.CurrentCamera
			vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		end
		local scale = math.clamp(math.min(vp.X / 900, vp.Y / 620), 0.55, 1.15)
		local cw, ch = vp.X / scale, vp.Y / scale
		-- the canvas: exactly (screen / scale) units, centred, so ONE UIScale maps it onto the screen
		local root = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(cw, ch),
			BackgroundTransparency = 1, ZIndex = 2 }, gui)
		local rootScale = new("UIScale", { Scale = scale }, root)
		tween(shade, 0.25, { BackgroundTransparency = 0.25 })
		local tickS = sound(gui, "rbxasset://sounds/clickfast.wav", 0.35)
		local dingS = sound(gui, "rbxasset://sounds/electronicpingshort.wav", 0.6)

		local multi = n > 1
		local titleY = multi and 16 or math.max(12, math.floor(ch / 2 - 230))
		local title = ink(label(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, titleY), Size = UDim2.fromOffset(math.min(620, cw - 40), 54),
			Text = (multi and (n .. "x ") or "") .. "ROLLING " .. (o.noun or "ITEM") .. (multi and "S" or "") .. "...", ZIndex = 40 }), 3)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, color) }, title)
		local titlePop = new("UIScale", { Scale = 0.6 }, title)
		tween(titlePop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

		local skip, closed = false, false
		local stage = "spin"
		local doneAt = math.huge
		shade.Activated:Connect(function()
			if stage == "spin" then
				skip = true
			elseif stage == "done" and os.clock() - doneAt > 1 then -- taps that skipped the spin must not close it too
				closed = true
			end
		end)

		-- the result card for one item: its logo big, its name under it
		local function bigCard(id, z, pos, w, h, live)
			local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BorderSizePixel = 0,
				ZIndex = z }, root)
			corner(card, math.max(8, math.floor(w * 0.06)))
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(INK, 0.6)) }, card)
			stroke(card, INK, w >= 200 and 4 or 3)
			local m = math.max(6, math.floor(w * 0.052))
			local nameH = math.clamp(math.floor(h * 0.16), 22, 52)
			local art = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, m), Size = UDim2.new(1, -m * 2, 1, -(m * 2 + nameH)),
				BackgroundColor3 = INK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = z + 1 }, card)
			corner(art, math.max(6, math.floor(w * 0.045)))
			drawArt(art, cat, id, live)
			ink(label(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -math.max(4, math.floor(m * 0.6))), Size = UDim2.new(1, -m * 2, 0, nameH),
				Text = safeName(id), ZIndex = z + 2 }), w >= 200 and 3 or 2)
			return card
		end

		------------------------------------------------------------------------------------------------- build the reels
		local reels = {}
		local L
		if multi then
			L = layoutMulti(n, cw, ch, scale)
		else
			L = { vertical = false, tw = TILE_W, th = TILE_H, showName = true, pos = { UDim2.fromScale(0.5, 0.5) } }
			L.K, L.len = ringFit(math.min(cw - 60, 680), TILE_W, LOGO_BUDGET)
		end
		local base, stag = 4.2, 0
		if n >= 6 then
			base, stag = 3.2, 0.2
		elseif multi then
			base, stag = 3.4, 0.32
		end
		local along = L.vertical and L.th or L.tw
		for i, id in ipairs(ids) do
			local dur = base + (i - 1) * stag
			local T = math.max(L.K + 8, math.floor(dur * CARDS_PER_SEC + 0.5))
			local r = newReel(root, { cat = cat, prize = id, pool = pool, nameOf = safeName, color = color, vertical = L.vertical, tw = L.tw, th = L.th,
				showName = L.showName, K = L.K, len = L.len, pos = L.pos[i], z = 4, T = T, small = L.small })
			r.dur, r.delay = dur, (i - 1) * 0.05
			r.jitter = (math.random() - 0.5) * along * 0.6
			if multi then
				-- fade the windows in: a scale pop would resize every logo of every reel at once (a re-render each)
				local bt = r.window.BackgroundTransparency
				r.window.BackgroundTransparency = 1
				tween(r.window, 0.2, { BackgroundTransparency = bt })
			else
				local pop = new("UIScale", { Scale = 0.7 }, r.window)
				tween(pop, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			reels[i] = r
			if multi then
				task.wait() -- one reel's logos per frame, so their first renders fit the frame budget
			end
		end
		task.wait(multi and 0.45 or 0.3) -- let the new logos draw before they start moving

		------------------------------------------------------------------------------------------------- spin
		local landed = 0
		local function onLand(r)
			r.kickAll() -- it stands still from here: one redraw kick per logo, to be safe
			local t = r.tiles[r.kPrize]
			-- grow the prize from its centre (a UIScale grows from the AnchorPoint), no taller than the window
			t.f.AnchorPoint = Vector2.new(0.5, 0.5)
			t.f.Position += UDim2.fromOffset(t.f.Size.X.Offset / 2, t.f.Size.Y.Offset / 2)
			local ps = new("UIScale", {}, t.f)
			tween(ps, 0.2, { Scale = math.min(multi and 1.06 or 1.14, r.fit) }, Enum.EasingStyle.Back)
			t.st.Color = GOLD
			t.st.Thickness += 1
			tween(r.wStroke, 0.15, { Color = GOLD, Thickness = r.wStroke.Thickness + 1 })
			if multi and not skip then
				local s = sound(gui, "rbxasset://sounds/electronicpingshort.wav", 0.32)
				playSound(s, 0.8 + landed * (n >= 6 and 0.05 or 0.09))
				task.delay(2, function()
					s:Destroy()
				end)
			end
		end
		local frameNo, lastTick = 0, -1
		local tStart = os.clock()
		local finished = false
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not gui.Parent then
				conn:Disconnect()
				finished = true
				return
			end
			frameNo += 1
			local now = os.clock() - tStart
			for _, r in ipairs(reels) do
				if not r.landed then
					local off
					if not r.settleAt then
						local a = skip and 1 or math.clamp((now - r.delay) / r.dur, 0, 1)
						r.e = 1 - (1 - a) ^ 4 -- fast, then a long slow-down
						off = (r.offEnd + r.jitter) * r.e
						if a >= 1 then
							r.settleAt = now
						end
					end
					if r.settleAt then
						local b = math.clamp((now - r.settleAt) / (skip and 0.06 or SETTLE), 0, 1)
						off = r.offEnd + r.jitter * (1 - TweenService:GetValue(b, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
						if b >= 1 then
							off = r.offEnd
							r.final = true
						end
					end
					-- a tick (and a marker pop) for every card passing the marker
					local idx = r.under(off)
					if idx ~= r.lastIdx then
						r.lastIdx = idx
						if not skip and not r.settleAt and frameNo > 1 then
							r.mScale.Scale = 1.35
							tween(r.mScale, 0.12, { Scale = 1 })
							if now - lastTick > (multi and 0.05 or 0) then
								lastTick = now
								playSound(tickS, 0.9 + (r.e or 0) * 0.5)
							end
						end
					end
					r.place(off)
					if r.final then
						r.landed = true
						landed += 1
						onLand(r)
					end
				end
			end
			if landed >= #reels then
				conn:Disconnect()
				finished = true
			end
		end)
		while not finished do
			task.wait()
		end
		if not gui.Parent then
			return
		end
		stage = "reveal"

		------------------------------------------------------------------------------------------------- the prize(s)
		task.wait(skip and 0.08 or (multi and 0.45 or 0.3))
		local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 60 }, gui)
		tween(flash, 0.45, { BackgroundTransparency = 1 })
		playSound(dingS)
		task.delay(0.5, function()
			flash:Destroy()
		end)
		task.wait(skip and 0.1 or (multi and 0.12 or 0.5))
		for _, r in ipairs(reels) do
			r.destroy()
		end
		local rays = burstRays(root, color, 3)
		TweenService:Create(rays, TweenInfo.new(multi and 18 or 14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
		if not multi then
			local card = bigCard(ids[1], 12, UDim2.fromScale(0.5, 0.5), 270, 330, true)
			local cs = new("UIScale", { Scale = 0.2 }, card)
			tween(cs, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			local stamp = ink(label(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 118, 0.5, -150), Size = UDim2.fromOffset(120, 46),
				Text = "NEW!", TextColor3 = GOLD, Rotation = 14, ZIndex = 16 }), 3)
			local ss = new("UIScale", { Scale = 3 }, stamp)
			tween(ss, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			confetti(root, { color, GOLD, WHITE, color:Lerp(WHITE, 0.5) }, 15, 46, math.min(cw, ch) * 0.55)
			title.Text = "YOU GOT"
		else
			-- every prize as a card, in a grid that fits between the title and the footer
			local cols = n <= 5 and n or 5
			local rows = math.ceil(n / cols)
			local aw, ah = cw - SIDE * 2, ch - TOP - BOTTOM
			local g = 14
			local w = math.min(178, math.floor((aw - (cols - 1) * g) / cols))
			local h = math.floor(w * 1.25)
			if rows * h + (rows - 1) * g > ah then
				h = math.floor((ah - (rows - 1) * g) / rows)
				w = math.floor(h / 1.25)
			end
			local x0 = (cw - (cols * w + (cols - 1) * g)) / 2 + w / 2
			local y0 = TOP + (ah - (rows * h + (rows - 1) * g)) / 2 + h / 2
			for i, id in ipairs(ids) do
				local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
				local card = bigCard(id, 12, UDim2.fromOffset(math.floor(x0 + c * (w + g)), math.floor(y0 + rr * (h + g))), w, h, n <= 5)
				local cs = new("UIScale", { Scale = 0.2 }, card)
				tween(cs, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
				if not skip then
					playSound(tickS, 1 + i * 0.05)
					task.wait(0.07)
				end
			end
			confetti(root, { color, GOLD, WHITE, color:Lerp(WHITE, 0.5) }, 15, 60, math.min(cw, ch) * 0.6)
			title.Text = #won .. " NEW " .. (o.noun or "ITEM") .. (#won == 1 and "" or "S")
				.. (picks > 0 and (" + " .. picks .. " FREE PICK" .. (picks > 1 and "S" or "")) or "") .. "!"
		end
		titlePop.Scale = 1.25
		tween(titlePop, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

		------------------------------------------------------------------------------------------------- footer + close
		local footY = multi and (ch - 10) or math.min(ch - 8, ch / 2 + 212)
		local foot = ink(label(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, footY), Size = UDim2.fromOffset(math.min(620, cw - 40), 26),
			Text = ((tonumber(o.pick) or 0) > 0 and "+1 FREE PICK - CHOOSE IT IN THE SHOP  ・  " or "") .. "TAP TO CONTINUE", FontFace = FONT_LABEL,
			TextColor3 = GOLD, ZIndex = 40 }), 2)
		foot.TextTransparency = 1
		tween(foot, 0.4, { TextTransparency = 0 })
		stage = "done"
		doneAt = os.clock()
		local tEnd = os.clock() + (multi and 7 or 5)
		while not closed and os.clock() < tEnd and gui.Parent do
			task.wait(0.05)
		end
		if not gui.Parent then
			return
		end
		tween(rootScale, 0.2, { Scale = scale * 0.92 })
		tween(shade, 0.2, { BackgroundTransparency = 1 })
		fadeOut(root, 0.2)
		task.wait(0.22)
		gui:Destroy()
	end)
	busy = false
	if not ok then
		warn("[RollReveal] " .. tostring(err))
		local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local g = pg and pg:FindFirstChild("RollReveal")
		if g then
			g:Destroy()
		end
	end
	if type(o.onDone) == "function" then
		pcall(o.onDone)
	end
end

return RollReveal
