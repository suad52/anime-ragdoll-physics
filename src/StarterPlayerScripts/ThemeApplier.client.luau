--!nocheck
-- StarterPlayerScripts.ThemeApplier (2026-11-14): puts every screen GUI in HudShared.Theme's BRIGHT CARTOON look and
-- takes the Japanese out of its text - live: what scripts build or recolour later is caught too.
--   * dark fills and gradients -> light tints of the same hue (Theme.lightBg); dark / white outlines -> navy
--   * every label -> Fredoka One. On a light fill, white text -> navy and pale accents -> a deeper shade (its outline
--     goes white, a sticker edge); over a coloured fill or over the world, text keeps its colour with a navy outline
--   * Japanese in any label is stripped (Theme.strip); a badge whose glyph was only kanji shows a gold star instead
-- LEFT ALONE: the kits' HUDs + vignettes (the power cut-ins keep their titles), the crosshair and the full-screen
-- flashes (text only), and inside every GUI anything DRAWN: HudShared.Icons parts, fighter emblems, CardArt, the rail
-- tiles' icons, the hotbar icons, the status card's x-ray scan, viewports.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Theme = require(RS:WaitForChild("HudShared"):WaitForChild("Theme"))
local Icons
pcall(function()
	Icons = require(RS.HudShared:WaitForChild("Icons", 10))
end)
local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
local NAVY, WHITE = Theme.NAVY, Theme.WHITE

local TEXT_ONLY = { SandboxCrosshair = true, PerkEventsFlash = true, VictoryFlash = true, PlayerMarkersEdge = true }
local IGNORE = { Freecam = true, BubbleChat = true, Chat = true, TouchGui = true }
local function modeOf(g)
	if not g:IsA("ScreenGui") or IGNORE[g.Name] then
		return nil
	end
	local n = g.Name
	if string.sub(n, -3) == "HUD" or string.sub(n, -8) == "Vignette" then
		return "rename" -- a kit's own HUD: left as it is, except copyrighted names (Theme.RENAME) are swapped
	end
	return TEXT_ONLY[n] and "text" or "full"
end
local SKIP = { Emblem = true, EmblemIcon = true, TileIcon = true, DrawnIcon = true, Scan = true, ArtSlot = true, Icon = true, IconPlain = true, GlyphStar = true }
local function skipped(o, g)
	local p = o
	while p and p ~= g do
		local n = p.Name
		if SKIP[n] or n == "IconPart" or string.sub(n, 1, 8) == "CardArt_" or p:IsA("ViewportFrame") then
			return true
		end
		p = p.Parent
	end
	return false
end

-- the colour actually painted behind a piece of text: its own fill (a button) or the nearest ancestor's
local function fillBehind(o, g)
	local p = o
	while p and p ~= g do
		if p:IsA("GuiObject") and p.BackgroundTransparency < 0.5 then
			if (p:IsA("ImageLabel") or p:IsA("ImageButton")) and p.Image ~= "" then
				return nil
			end
			local c = p.BackgroundColor3
			local gr = p:FindFirstChildOfClass("UIGradient")
			if gr and gr.Enabled then
				local k = gr.Color.Keypoints
				local m = k[1].Value:Lerp(k[#k].Value, 0.5)
				c = Color3.new(c.R * m.R, c.G * m.G, c.B * m.B)
			end
			return c
		end
		p = p.Parent
	end
	return nil
end
local function textStroke(t)
	for _, s in ipairs(t:GetChildren()) do
		if s:IsA("UIStroke") and (not t:IsA("TextButton") or s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual) then
			return s
		end
	end
end

local styleText, seen -- forward: a fill that changes re-reads the text on it
local function styleFill(o, g)
	if o.BackgroundTransparency >= 1 or o:GetAttribute("ThemeKeep") then
		return -- ThemeKeep: a piece that keeps its own fill on purpose
	end
	local c = o.BackgroundColor3
	-- a full-screen dim behind a menu: navy, not a white haze (the light panel needs the contrast)
	if o.BackgroundTransparency > 0.15 and o.Size.X.Scale >= 0.99 and o.Size.Y.Scale >= 0.99 and Theme.lum(c) < 0.32 then
		if c ~= NAVY then
			o.BackgroundColor3 = NAVY
		end
		return
	end
	local n = Theme.lightBg(c)
	if n ~= c then
		o.BackgroundColor3 = n
		-- text already styled on this fill was judged against the old colour (a fill can turn light after its label
		-- was styled - the rail tiles do): judge it again
		if g and seen then
			for _, d in ipairs(o:GetDescendants()) do
				if seen[d] and (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then
					styleText(d, g)
				end
			end
			if seen[o] and (o:IsA("TextButton") or o:IsA("TextLabel")) then
				styleText(o, g)
			end
		end
	end
end
local function styleGrad(gr)
	local par = gr.Parent
	if not (par and par:IsA("GuiObject")) or par:IsA("TextLabel") or par:IsA("TextBox") then
		return
	end
	local k, nk, changed = gr.Color.Keypoints, {}, false
	for i, kp in ipairs(k) do
		local v = Theme.lightBg(kp.Value)
		changed = changed or v ~= kp.Value
		nk[i] = ColorSequenceKeypoint.new(kp.Time, v)
	end
	if changed then
		gr.Color = ColorSequence.new(nk)
	end
end
local function styleStroke(s)
	local p = s.Parent
	if not (p and p:IsA("GuiObject")) or p:IsA("TextLabel") or p:IsA("TextBox") then
		return
	end
	if p:IsA("TextButton") and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
		return
	end
	local L = Theme.lum(s.Color)
	if s.Color ~= NAVY and (L < 0.3 or L > 0.8) then
		s.Color = NAVY -- ink rings and white rings both become the navy outline; coloured accents stay
	end
end
function styleText(t, g)
	if t.FontFace ~= Theme.FONT then
		t.FontFace = Theme.FONT
	end
	local bg = fillBehind(t, g)
	local s = textStroke(t)
	if bg and Theme.lum(bg) > 0.6 then
		local n = Theme.inkOnLight(t.TextColor3)
		if n ~= t.TextColor3 then
			t.TextColor3 = n
		end
		if s and s.Color ~= WHITE then
			s.Color = WHITE
		end
	elseif s and s.Color ~= NAVY and Theme.lum(s.Color) < 0.3 then
		s.Color = NAVY
	end
end
local function sanitize(t)
	-- (2026-11-15) original names for copyrighted move / form names (Theme.RENAME) - on every label
	local renamed = Theme.rename(t.Text)
	if renamed ~= t.Text then
		t.Text = renamed
		return -- the Text change runs this again
	end
	local star = t:FindFirstChild("GlyphStar")
	local s = t.Text
	if not Theme.hasCJK(s) then
		if star and s ~= "" then
			star:Destroy()
		end
		return
	end
	local r = Theme.strip(s)
	t.Text = r
	if r ~= "" then
		if star then
			star:Destroy()
		end
		return
	end
	-- the text was only kanji: if it was a badge's glyph (a squarish label) a gold star takes its place
	if star or not Icons then
		return
	end
	local a = t.AbsoluteSize
	local square = (a.X > 4 and math.abs(a.X - a.Y) <= a.X * 0.3)
		or (a.X <= 4 and math.abs(t.Size.X.Scale - t.Size.Y.Scale) < 0.05 and math.abs(t.Size.X.Offset - t.Size.Y.Offset) < 4)
	if square then
		local box = Instance.new("Frame")
		box.Name = "GlyphStar"
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromScale(0.86, 0.86)
		box.ZIndex = t.ZIndex
		pcall(Icons.draw, "star", box, { z = t.ZIndex, stroke = 0.7 })
		box.Parent = t
	end
end

seen = setmetatable({}, { __mode = "k" })
local function hook(o, prop, fn)
	o:GetPropertyChangedSignal(prop):Connect(fn)
end
local function apply(o, g, mode)
	if not seen[o] and mode ~= "rename" and skipped(o, g) and (o:IsA("TextLabel") or o:IsA("TextButton")) then
		-- drawn art (card letters etc.) keeps its look, but copyrighted names still get swapped
		seen[o] = true
		local function rn()
			local r = Theme.strip(Theme.rename(o.Text)) -- (2026-11-15) no kanji anywhere, the swastika-like 卍 included
			if r ~= o.Text then
				o.Text = r
			end
		end
		rn()
		hook(o, "Text", rn)
		return
	end
	if seen[o] or skipped(o, g) then
		return
	end
	seen[o] = true
	local isText = o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")
	if mode == "rename" then
		if isText then
			local function rn()
				local r = Theme.strip(Theme.rename(o.Text)) -- (2026-11-15) no kanji anywhere, the swastika-like 卍 included
				if r ~= o.Text then
					o.Text = r
				end
			end
			rn()
			hook(o, "Text", rn)
		end
		return
	end
	if isText then
		sanitize(o)
		hook(o, "Text", function()
			sanitize(o)
		end)
	end
	if mode ~= "full" then
		return
	end
	if not Theme.COLOURS then
		-- (2026-11-14) colours stay as each script made them (the owner went back to the dark look): only the font
		if isText then
			local function font()
				if o.FontFace ~= Theme.FONT then
					o.FontFace = Theme.FONT
				end
			end
			font()
			hook(o, "FontFace", font)
		end
		return
	end
	if o:IsA("UIGradient") then
		styleGrad(o)
		hook(o, "Color", function()
			styleGrad(o)
		end)
		return
	end
	if o:IsA("UIStroke") then
		styleStroke(o)
		hook(o, "Color", function()
			styleStroke(o)
		end)
		local p = o.Parent
		if p and (p:IsA("TextLabel") or p:IsA("TextButton")) and seen[p] then
			styleText(p, g) -- a text outline added after its label was styled
		end
		return
	end
	if o:IsA("GuiObject") then
		if not (o:IsA("ImageLabel") or o:IsA("ImageButton")) or o.Image == "" then
			styleFill(o, g)
			hook(o, "BackgroundColor3", function()
				styleFill(o, g)
			end)
		end
		if isText then
			styleText(o, g)
			hook(o, "TextColor3", function()
				styleText(o, g)
			end)
			hook(o, "FontFace", function()
				styleText(o, g)
			end)
		end
	end
end

local function watchGui(g)
	local mode = modeOf(g)
	if not mode then
		return
	end
	g.DescendantAdded:Connect(function(d)
		task.defer(function()
			if d:IsDescendantOf(g) then
				apply(d, g, mode)
				for _, x in ipairs(d:GetDescendants()) do
					apply(x, g, mode)
				end
			end
		end)
	end)
	-- what is there now: fills and gradients first, so the text can read the light fill behind it
	local all = g:GetDescendants()
	local texts = {}
	for i, d in ipairs(all) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			table.insert(texts, d)
			if mode == "full" and Theme.COLOURS and not skipped(d, g) then
				styleFill(d, g) -- a button's own fill, before any text reads it
			end
		else
			apply(d, g, mode)
		end
		if i % 400 == 0 then
			task.wait()
		end
	end
	for i, t in ipairs(texts) do
		if t.Parent then
			apply(t, g, mode)
		end
		if i % 400 == 0 then
			task.wait()
		end
	end
end

for _, g in ipairs(pg:GetChildren()) do
	task.spawn(watchGui, g)
end
-- (2026-11-15) world text too: billboards and signs (Sora's incantation, emote bubbles, city signs) get the same
-- copyrighted-name swap and kanji strip as the screen.
local function worldText(d)
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		local function rn()
			local r = Theme.strip(Theme.rename(d.Text))
			if r ~= d.Text then
				d.Text = r
			end
		end
		rn()
		d:GetPropertyChangedSignal("Text"):Connect(rn)
	end
end
for _, d in ipairs(workspace:GetDescendants()) do
	worldText(d)
end
workspace.DescendantAdded:Connect(function(d)
	task.defer(worldText, d)
end)
pg.ChildAdded:Connect(function(g)
	task.defer(watchGui, g)
end)
