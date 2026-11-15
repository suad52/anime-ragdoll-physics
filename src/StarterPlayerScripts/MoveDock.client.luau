--!nocheck
-- MoveDock (orchestrator 2026-11-07): ONE move bar for every kit, bottom-centre - the style name, a health bar, an
-- ultimate-charge strip and themed move boxes. Each kit still builds and drives its own AbilityBar (cooldowns,
-- input, pops); MoveDock reads whichever one is visible, draws its boxes over it, and slides every kit button
-- UNDER its box (the boxes are not Active, so clicks / taps still land on the kit's own button).
-- Generic reading of a kit button: the key chip = a child Frame holding a 1-3 char TextLabel; the cooldown text =
-- the ZIndex >= 4 TextLabel (seconds or ""); the name = the first upper-case label; a wide button = the ultimate.
-- TOUCH (2026-11-08): on a phone / tablet (HudShared.InputMode) the boxes drop the PC key (M1 / Q / E ...) and the
-- move name moves up into its place; the key is still read for ordering. Flips live with the input device.
-- FORM LOCKS (2026-11-10): inside Kurama / Susanoo / a titan / Sukuna's Shrine / Ultra Instinct, the moves the kit's
-- server refuses are greyed under a bold X (FORM_LOCKS below); the rest stay lit. Live, from character attributes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Kits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))
local InputMode
pcall(function()
	InputMode = require(ReplicatedStorage.HudShared:WaitForChild("InputMode", 10))
end)
-- KEYBINDS (2026-11-11, "have the option to have keybinds"): every box's key reads Keybinds.label(<the move's DEFAULT
-- key>), so a rebound move shows its new key. The kits draw their own chips with Keybinds.label too, so the chip text
-- MoveDock reads is the PHYSICAL key; chipDefault() below turns it back into the default key (Q, E, ... - what
-- KEY_ORDER sorts by). The boxes are rewritten every frame, which is what refreshes them on Keybinds.Changed. With no
-- rebinds the label of every default key is the key itself, so the bar is exactly as before.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))
local NAME_POS, NAME_SIZE = UDim2.new(0.5, 0, 0, 33), UDim2.new(1, -10, 0, 30)
local NAME_POS_TOUCH, NAME_SIZE_TOUCH = UDim2.new(0.5, 0, 0, 12), UDim2.new(1, -10, 0, 48)

local BOX_W, BOX_H, ULT_W, GAP = 86, 76, 118, 8
local KEY_ORDER = { M1 = 1, Q = 2, E = 3, R = 4, F = 5, T = 6, G = 7, X = 8 }
-- the actions a kit chip can stand for (M1 is not rebindable and is read as text)
local CHIP_KEYS = { Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.F, Enum.KeyCode.T, Enum.KeyCode.G, Enum.KeyCode.X }
-- a chip's text -> the default key it stands for. A kit draws Keybinds.label(default), so first ask which action is
-- labelled that now; a kit that still draws the plain default letter is caught by the Enum fallback. Sticky per button
-- while the text still agrees with the remembered key either way, so a swap made mid-match (Q <-> E) never makes a
-- not-yet-converted kit's "Q" read as E.
local chipMemo = setmetatable({}, { __mode = "k" })
local function chipDefault(btn, t)
	local d = chipMemo[btn]
	if d and (Keybinds.label(d) == t or d.Name == t) then
		return d
	end
	d = nil
	for _, k in ipairs(CHIP_KEYS) do
		if Keybinds.label(k) == t then
			d = k
			break
		end
	end
	if not d then
		for _, k in ipairs(CHIP_KEYS) do
			if k.Name == t then
				d = k
				break
			end
		end
	end
	chipMemo[btn] = d
	return d
end
local function isChipText(t)
	if t ~= "" and #t <= 3 then
		return true
	end
	-- a move rebound to a long key ("SHIFT", "LCTRL", "NUM4") is still a key chip
	for _, k in ipairs(CHIP_KEYS) do
		if Keybinds.label(k) == t then
			return true
		end
	end
	return false
end
local WHITE, INK = Kits.WHITE, Kits.INK

-- FORM LOCKS (2026-11-10): while a character state makes the SERVER refuse some of a kit's moves, those boxes go grey
-- under a bold X in the kit's colour; the moves that still work in that state stay lit. Each rule reads the attributes
-- the kit's server stamps on the character and mirrors that server's own refusal (named per rule). A rule returns nil
-- (no such state: every box normal), { only = set } (only these buttons work) or { block = set } (these do not).
-- Sets are keyed by the kit AbilityBar BUTTON NAME (stable; the key chip and the labels change with forms / skins).
local function attr(char, a)
	return char and char:GetAttribute(a)
end
local FORM_LOCKS = {
	-- VulpineServer.KitServer: from the moment the Kurama form starts (s.morph; Morphed) Sphere, Disc and Sage Mode ON
	-- are refused. M1 = claw, F = Tailed Beast Bomb, X = release; Sage Mode can still be switched OFF.
	Vulpine = function(char)
		if attr(char, "Morphed") ~= true then
			return nil
		end
		return { only = { Punch = true, Morph = true, Release = true, Power = attr(char, "PowerMode") == true or nil } }
	end,
	-- TempestServer.TempestService: while the Susanoo stands (s.guard; Morphed from the summoning, Guardian once built)
	-- Chidori (Lance), Kirin (Pulse) and the eyes ON are refused. M1 = slash, G = Indra's Arrow, X = release.
	Tempest = function(char)
		if attr(char, "Morphed") ~= true and attr(char, "Guardian") ~= true then
			return nil
		end
		return { only = { Punch = true, Guardian = true, Release = true, Eyes = attr(char, "EyeMode") == true or nil } }
	end,
	-- ShifterServer.ShifterService: in a titan (s.form) Hook / Spin (Q) and the OTHER two titans are refused; the
	-- titan's own key is its signature move, M1 its titan swing, X the release. During the entrance (Morphed, no
	-- TitanForm yet) s.busy refuses everything.
	Shifter = function(char)
		local kind = attr(char, "TitanForm")
		if type(kind) == "string" then
			return { only = { Punch = true, Release = true, [kind] = true } }
		elseif attr(char, "Morphed") == true then
			return { only = { Release = true } }
		end
	end,
	-- CarverServer.CarverService: the Shrine sets s.busy for its whole seal + duration, so its gate refuses Fuga, Cleave,
	-- Sever and the Shrine itself; only the shared punch (CombatService) still lands.
	Carver = function(char)
		if attr(char, "Domain") == true then
			return { only = { Punch = true } }
		end
	end,
	-- AscendantServer.AscendantService castSurge: "the silver form outranks it" - no Super Saiyan inside Ultra Instinct
	Ascendant = function(char)
		if attr(char, "AscForm") == "Instinct" then
			return { block = { Surge = true } }
		end
	end,
}
local BOX_BG = ColorSequence.new(Kits.PANEL2, INK)
local LOCK_BG = ColorSequence.new(Color3.fromRGB(74, 74, 82), Color3.fromRGB(26, 26, 30))
local LOCK_EDGE = Color3.fromRGB(92, 92, 102)
local NAME_INK, LOCK_NAME = Color3.fromRGB(235, 235, 245), Color3.fromRGB(135, 135, 145)

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
	return new("UICorner", { CornerRadius = UDim.new(0, r) }, p)
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, Text = "" }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end

local gui = new("ScreenGui", { Name = "MoveDock", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local root = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(420, 150),
	BackgroundTransparency = 1, Visible = false }, gui)
local rootScale = new("UIScale", {}, root)

-- title row: the style name in a brush font (+ the kit's live status text at the right, e.g. "COLOSSAL 15s")
-- (2026-11-14) in the HUD's one clean bold font (the HudRails / SandboxClient tiles) with a light outline, not the brush
-- face under a heavy ink line; the health bar is a dark rounded track like the tiles, its fill inset, no gloss
local CLEAN = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local title = label(root, { Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5),
	Size = UDim2.new(1, 0, 0, 24), FontFace = CLEAN, TextScaled = false, TextSize = 19 })
local titleStroke = new("UIStroke", { Thickness = 1.2, Color = INK, Transparency = 0.45 }, title)
local status = label(root, { Name = "Status", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -18),
	Size = UDim2.new(1, 0, 0, 16), FontFace = CLEAN, TextTransparency = 1 })
new("UIStroke", { Thickness = 1.2, Color = INK, Transparency = 0.4 }, status)

-- health bar (chunky, with a white chip trailing the drop) and the thin ultimate strip under it
local hpBack = new("Frame", { Name = "Health", Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = Color3.fromRGB(22, 23, 28), BackgroundTransparency = 0.14, BorderSizePixel = 0 }, root)
corner(hpBack, 8)
new("UIStroke", { Thickness = 1.5, Color = Color3.new(0, 0, 0), Transparency = 0.5 }, hpBack)
new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }, hpBack)
local hpChip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, hpBack)
corner(hpChip, 6)
local hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hpBack)
corner(hpFill, 6)
local hpGrad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Kits.HP, Kits.HP2) }, hpFill)
local hpShine = new("Frame", { Position = UDim2.fromScale(0, 0.12), Size = UDim2.new(1, -6, 0.28, 0), BackgroundColor3 = WHITE,
	BackgroundTransparency = 0.6, BorderSizePixel = 0, Visible = false }, hpFill)
corner(hpShine, 3)
local hpText = label(hpBack, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.new(0, 80, 1, 4),
	FontFace = CLEAN, TextScaled = false, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
new("UIStroke", { Thickness = 1, Color = INK, Transparency = 0.35 }, hpText)

local ultBack = new("Frame", { Name = "Ult", Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = Kits.PANEL, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, root)
corner(ultBack, 3)
local ultFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, ultBack)
corner(ultFill, 3)
local ultGrad = new("UIGradient", {}, ultFill)
local ultTag = label(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 61), Size = UDim2.fromOffset(120, 12),
	FontFace = CLEAN, TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
new("UIStroke", { Thickness = 1, Color = INK, Transparency = 0.4 }, ultTag)

local row = new("Frame", { Name = "Moves", Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, BOX_H), BackgroundTransparency = 1 }, root)

-- one themed box ------------------------------------------------------------------------------------------
local function makeBox()
	local f = new("Frame", { Size = UDim2.fromOffset(BOX_W, BOX_H), BackgroundColor3 = WHITE, BackgroundTransparency = 0,
		BorderSizePixel = 0, Active = false }, row)
	corner(f, 7)
	local bg = new("UIGradient", { Rotation = 90, Color = BOX_BG }, f)
	local stroke = new("UIStroke", { Thickness = 1.6, Color = WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local scale = new("UIScale", {}, f)
	-- a lit cap along the top edge, fading out at both ends
	local cap = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, -10, 0, 2),
		BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 3 }, f)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1) }) }, cap)
	-- corner diamond
	local gem = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(7, 7),
		Rotation = 45, BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 3 }, f)
	-- the key, big comic numerals
	local key = label(f, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.new(1, -16, 0, 26),
		FontFace = Kits.FONT_PUNCH, ZIndex = 4 })
	local keyStroke = new("UIStroke", { Thickness = 1.5, Color = INK }, key)
	local name = label(f, { AnchorPoint = Vector2.new(0.5, 0), Position = NAME_POS, Size = NAME_SIZE,
		FontFace = Kits.FONT_LABEL, TextWrapped = true, TextColor3 = Color3.fromRGB(235, 235, 245), ZIndex = 4 })
	new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 7 }, name)
	-- recharge strip along the bottom
	local stripBack = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, -14, 0, 3),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 3 }, f)
	corner(stripBack, 2)
	local strip = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, stripBack)
	corner(strip, 2)
	-- cooldown veil (drains from the top) + the seconds
	local veil = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 5 }, f)
	corner(veil, 7)
	local secs = label(f, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 0, 34),
		FontFace = Kits.FONT_PUNCH, ZIndex = 6 })
	local secsStroke = new("UIStroke", { Thickness = 2, Color = INK }, secs)
	local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7 }, f)
	corner(flash, 7)
	local tag = label(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5), Size = UDim2.fromOffset(28, 11),
		FontFace = Kits.FONT_PUNCH, Text = "ULT", Visible = false, ZIndex = 4 })
	-- FORM LOCK: a dark wash over the greyed box + a bold X (ink outline under kit-colour bars, so the crossing is clean)
	local lock = new("Frame", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 14, 18),
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 8 }, f)
	corner(lock, 7)
	local xs = new("Frame", { Name = "X", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundTransparency = 1,
		Visible = false, ZIndex = 9 }, f)
	local xScale = new("UIScale", {}, xs)
	local xBars = {}
	for _, rot in ipairs({ 45, -45 }) do
		local edge = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.32, 5, 0, 13),
			Rotation = rot, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 9 }, xs)
		corner(edge, 6)
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1.32, 0, 0, 8),
			Rotation = rot, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 10 }, xs)
		corner(bar, 4)
		table.insert(xBars, bar)
	end
	return { frame = f, bg = bg, stroke = stroke, scale = scale, cap = cap, gem = gem, key = key, keyStroke = keyStroke, name = name,
		strip = strip, veil = veil, secs = secs, flash = flash, tag = tag, maxRem = 0, ready = true,
		lock = lock, x = xs, xScale = xScale, xBars = xBars, locked = false }
end

local function popReady(b, accent)
	b.scale.Scale = 1.12
	TweenService:Create(b.scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	b.flash.BackgroundTransparency = 0.35
	TweenService:Create(b.flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	b.stroke.Color = WHITE
	TweenService:Create(b.stroke, TweenInfo.new(0.45), { Color = accent }):Play()
end

-- reading a kit's AbilityBar ------------------------------------------------------------------------------
local parsed = setmetatable({}, { __mode = "k" })
local function parse(btn)
	local info = parsed[btn]
	if info then
		return info
	end
	info = { btn = btn }
	for _, c in ipairs(btn:GetChildren()) do
		if c:IsA("TextLabel") then
			local t = c.Text
			if c.ZIndex >= 4 then
				info.cd = c
			elseif t ~= "" and t == string.upper(t) and t:find("%a") then
				if not info.name then
					info.name = c
				elseif not info.sub then
					info.sub = c
				end
			end
		elseif c:IsA("Frame") then
			local l = c:FindFirstChildOfClass("TextLabel")
			if l and l.Text ~= "" and isChipText(l.Text) then
				info.keyLabel = l
			end
		end
	end
	info.wide = btn.Size.X.Offset > btn.Size.Y.Offset * 1.6
	parsed[btn] = info
	-- the kit button stays the click target but draws nothing: its labels, icon, stroke and the kit's ready pings
	-- (added later) are all hidden - the kit only ever writes Size / Text / Color on them, never Visible
	local function hide(d)
		if d:IsA("GuiObject") then
			d.Visible = false
		elseif d:IsA("UIStroke") then
			d.Enabled = false
		end
	end
	for _, d in ipairs(btn:GetDescendants()) do
		hide(d)
	end
	btn.DescendantAdded:Connect(hide)
	btn.BackgroundTransparency = 1
	if btn:IsA("TextButton") then
		btn.TextTransparency = 1
	end
	return info
end

local function activeBar()
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled and g ~= gui then
			local bar = g:FindFirstChild("AbilityBar")
			if bar and bar:IsA("GuiObject") and bar.Visible then
				return bar
			end
		end
	end
end

-- slide a kit button so it sits exactly under its box (convergent: works under any UIScale the kit uses)
local function follow(btn, box)
	local cs, ca = btn.AbsoluteSize, btn.AbsolutePosition
	local bs, ba = box.AbsoluteSize, box.AbsolutePosition
	if cs.X < 1 or bs.X < 1 then
		return
	end
	local us = btn:FindFirstChildOfClass("UIScale")
	local pop = us and us.Scale or 1
	local offX = btn.Size.X.Offset + btn.Size.X.Scale * btn.Parent.AbsoluteSize.X
	if offX < 1 then
		return
	end
	local parentScale = cs.X / offX / pop
	if parentScale <= 0 then
		return
	end
	local want = bs / parentScale
	if math.abs(btn.Size.X.Offset - want.X) > 0.5 or math.abs(btn.Size.Y.Offset - want.Y) > 0.5 or btn.Size.X.Scale ~= 0 then
		btn.Size = UDim2.fromOffset(want.X, want.Y)
	end
	local d = (ba + bs / 2) - (ca + cs / 2)
	if d.Magnitude > 0.75 then
		btn.Position = btn.Position + UDim2.fromOffset(d.X / parentScale, d.Y / parentScale)
	end
	if btn.BackgroundTransparency < 1 then
		btn.BackgroundTransparency = 1
	end
end

-- the bar's non-button children (mode text, timers, pips) are read for the status line and parked off screen
local function park(bar)
	bar.ClipsDescendants = false
	local statusText = ""
	for _, c in ipairs(bar:GetChildren()) do
		if c:IsA("GuiObject") and not c:IsA("GuiButton") then
			if c:IsA("TextLabel") and c.Text ~= "" and statusText == "" then
				statusText = c.Text
			end
			if c.Position ~= UDim2.fromOffset(-5000, -5000) then
				c:SetAttribute("DockParked", true)
				c.Position = UDim2.fromOffset(-5000, -5000)
			end
		end
	end
	return statusText
end

local boxes = {} -- [kitButton] = box
local lastKit
local hpShown, chipShown = 1, 1
local ultWasReady = true

local function keyRank(k)
	return KEY_ORDER[k] or 20
end

RunService.RenderStepped:Connect(function(dt)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	-- (2026-11-11) SETTINGS > CONTROLS: UI SIZE scales the bar, TOOLBAR OFFSET slides it sideways
	rootScale.Scale = math.clamp(math.min(vp.Y / 820, vp.X / 1100), 0.62, 1.2) * (tonumber(player:GetAttribute("Opt_uiScale")) or 1)
	-- (2026-11-13) SandboxClient lays a weapon hotbar along the bottom edge and says how tall it is (PlayerGui.HotbarLift)
	root.Position = UDim2.new(0.5, tonumber(player:GetAttribute("Opt_toolbar")) or 0, 1, -12 - (tonumber(gui.Parent and gui.Parent:GetAttribute("HotbarLift")) or 0))
	local bar = activeBar()
	if not bar then
		-- (2026-11-13) the NORMAL choice (Kits entry with noPowers) has no moves, so no kit HUD puts up an AbilityBar. Its
		-- dock is the name and the health bar alone; the dock is bottom-anchored, so the bar drops to where the move row
		-- would have ended.
		local kit = Kits.byId[player:GetAttribute("Kit") or ""]
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not (kit and kit.noPowers and hum) then
			root.Visible = false
			return
		end
		root.Visible = true
		if kit ~= lastKit then
			lastKit = kit
			title.Text = kit.title
			titleStroke.Color = INK
			for btn, b in pairs(boxes) do
				b.frame:Destroy()
				boxes[btn] = nil
			end
		end
		status.TextTransparency = 1
		ultBack.Visible, ultTag.Visible, row.Visible = false, false, false
		root.Size = UDim2.fromOffset(420, 52)
		local hp = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
		hpShown += (hp - hpShown) * math.min(1, dt * 14)
		if hp < chipShown then
			chipShown = math.max(hp, chipShown - dt * 0.45)
		else
			chipShown = hp
		end
		hpFill.Size = UDim2.fromScale(hpShown, 1)
		hpChip.Size = UDim2.fromScale(chipShown, 1)
		hpGrad.Color = hp > 0.3 and ColorSequence.new(Kits.HP, Kits.HP2)
			or ColorSequence.new(Color3.fromRGB(255, 110, 90), Color3.fromRGB(200, 30, 40))
		hpText.Text = tostring(math.max(0, math.floor(hum.Health + 0.5)))
		return
	end
	root.Visible = true
	ultBack.Visible, ultTag.Visible, row.Visible = true, true, true
	local kit = Kits.current(player)
	local accent = kit.accent
	if kit ~= lastKit then
		lastKit = kit
		title.Text = kit.title
		titleStroke.Color = INK
		ultGrad.Color = ColorSequence.new(kit.c0, kit.c1)
		for btn, b in pairs(boxes) do
			b.frame:Destroy()
			boxes[btn] = nil
		end
	end
	local statusText = park(bar)
	status.Text = statusText
	status.TextTransparency = statusText ~= "" and 0 or 1
	status.TextColor3 = accent

	-- the moves, in key order
	local list = {}
	for _, c in ipairs(bar:GetChildren()) do
		if c:IsA("GuiButton") and c.Visible then
			local info = parse(c)
			local chip = info.keyLabel and info.keyLabel.Text or "?"
			local d = chipDefault(c, chip)
			info.keyText = d and Keybinds.label(d) or chip -- what the box shows (the bound key)
			info.keyRank = d and d.Name or chip -- what it sorts by (the default key)
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = keyRank(a.keyRank), keyRank(b.keyRank)
		if ra ~= rb then
			return ra < rb
		end
		return a.btn.Name < b.btn.Name
	end)
	local seen, x = {}, 0
	local ult
	local touch = InputMode ~= nil and InputMode.isTouch()
	local lockFn = FORM_LOCKS[kit.id]
	local lockRule = lockFn and lockFn(player.Character)
	for i, info in ipairs(list) do
		local btn = info.btn
		seen[btn] = true
		local b = boxes[btn]
		if not b then
			b = makeBox()
			boxes[btn] = b
		end
		local w = info.wide and ULT_W or BOX_W
		b.frame.Size = UDim2.fromOffset(w, BOX_H)
		b.frame.Position = UDim2.fromOffset(x, 0)
		x += w + GAP
		-- text
		b.key.Text = info.keyText
		b.key.Visible = not touch
		b.name.Position = touch and NAME_POS_TOUCH or NAME_POS
		b.name.Size = touch and NAME_SIZE_TOUCH or NAME_SIZE
		local nm = info.name and info.name.Text or btn.Name
		if info.wide and info.sub and info.sub.Text ~= "" then
			nm = info.sub.Text
		end
		b.name.Text = nm
		b.tag.Visible = info.wide
		b.tag.TextColor3 = accent
		b.cap.BackgroundColor3 = accent
		b.gem.BackgroundColor3 = accent
		b.keyStroke.Color = info.wide and kit.c1 or INK
		-- cooldown: the kit's seconds text, normalised by the longest value seen since it started
		local rem = info.cd and tonumber(info.cd.Text) or 0
		if rem > 0 then
			if b.ready or rem > b.maxRem then
				b.maxRem = math.max(rem, b.ready and rem or b.maxRem)
			end
			b.ready = false
			local k = math.clamp(rem / math.max(b.maxRem, 0.1), 0, 1)
			b.veil.Size = UDim2.fromScale(1, k)
			b.strip.Size = UDim2.fromScale(1 - k, 1)
			b.strip.BackgroundColor3 = Color3.fromRGB(150, 150, 170)
			b.secs.Text = info.cd.Text
			b.key.TextTransparency = 0.6
			b.name.TextTransparency = 0.55
			if b.stroke.Color ~= INK then
				b.stroke.Color = Color3.fromRGB(60, 58, 80)
			end
			if info.wide then
				ult = 1 - k
			end
		else
			if not b.ready then
				b.ready = true
				b.maxRem = 0
				if not b.locked then
					popReady(b, accent)
				end
			else
				b.stroke.Color = b.stroke.Color:Lerp(accent, math.min(1, dt * 6))
			end
			b.veil.Size = UDim2.fromScale(1, 0)
			b.strip.Size = UDim2.fromScale(1, 1)
			b.strip.BackgroundColor3 = accent
			b.secs.Text = ""
			b.key.TextTransparency = 0
			b.name.TextTransparency = 0
			if info.wide then
				ult = 1
			end
		end
		b.stroke.Thickness = info.wide and 2.4 or 1.6
		-- FORM LOCK, applied last so it overrides the ready / cooldown colours above
		local locked = lockRule ~= nil
			and ((lockRule.only ~= nil and not lockRule.only[btn.Name]) or (lockRule.block ~= nil and lockRule.block[btn.Name] == true))
			or false
		if locked ~= b.locked then
			b.locked = locked
			b.lock.Visible = locked
			b.x.Visible = locked
			if locked then
				b.bg.Color = LOCK_BG
				b.name.TextColor3 = LOCK_NAME
				b.xScale.Scale = 1.5
				TweenService:Create(b.xScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			else
				b.bg.Color = BOX_BG
				b.name.TextColor3 = NAME_INK
				if b.ready then
					popReady(b, accent) -- usable again
				end
			end
		end
		if locked then
			for _, bar in ipairs(b.xBars) do
				bar.BackgroundColor3 = accent
			end
			b.stroke.Color = LOCK_EDGE
			b.cap.BackgroundColor3 = LOCK_EDGE
			b.gem.BackgroundColor3 = LOCK_EDGE
			b.strip.BackgroundColor3 = LOCK_EDGE
			b.tag.TextColor3 = LOCK_EDGE
			b.key.TextTransparency = 0.6
			b.name.TextTransparency = 0.5
			if info.wide then
				ult = 0 -- a refused ultimate is not "ready"
			end
		end
		follow(btn, b.frame)
	end
	for btn, b in pairs(boxes) do
		if not seen[btn] then
			b.frame:Destroy()
			boxes[btn] = nil
		end
	end
	local width = math.max(x - GAP, 300)
	root.Size = UDim2.fromOffset(width, 74 + BOX_H)
	row.Size = UDim2.new(0, x - GAP, 0, BOX_H)
	row.Position = UDim2.fromOffset((width - (x - GAP)) / 2, 74)

	-- health
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local hp = hum and hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
	hpShown += (hp - hpShown) * math.min(1, dt * 14)
	if hp < chipShown then
		chipShown = math.max(hp, chipShown - dt * 0.45)
	else
		chipShown = hp
	end
	hpFill.Size = UDim2.fromScale(hpShown, 1)
	hpChip.Size = UDim2.fromScale(chipShown, 1)
	hpGrad.Color = hp > 0.3 and ColorSequence.new(Kits.HP, Kits.HP2)
		or ColorSequence.new(Color3.fromRGB(255, 110, 90), Color3.fromRGB(200, 30, 40))
	hpText.Text = hum and tostring(math.max(0, math.floor(hum.Health + 0.5))) or ""

	-- ultimate strip
	ult = ult or 0
	ultFill.Size = UDim2.fromScale(ult, 1)
	local ready = ult >= 1
	if ready then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 5)
		ultGrad.Offset = Vector2.new(math.sin(os.clock() * 2) * 0.3, 0)
		ultTag.Text = "ULTIMATE READY"
		ultTag.TextColor3 = kit.c0:Lerp(accent, pulse)
	else
		ultGrad.Offset = Vector2.zero
		ultTag.Text = string.format("ULT %d%%", math.floor(ult * 100))
		ultTag.TextColor3 = Color3.fromRGB(170, 170, 190)
	end
	ultWasReady = ready
end)
