--!nocheck
-- StarterPlayerScripts.SandboxClient: the ragdoll sandbox's HUD and controls.
--   ARSENAL (right edge, keys 1-7): POWERS (your fighter's own moves) / GRAB / BAT / AXE / KATANA / SLEDGEHAMMER / GUN.
--     While anything but POWERS is held, _G.SandboxArmed is true and the fighters' own M1 handlers stand down.
--     Melee and guns send the camera ray; the server hits the limb under the crosshair. GRAB drags a body part with
--     the mouse (F throws it). The gun slot upgrades with all-time kills (player attribute GunTier).
--   STATUS CARD (bottom right): the last dummy you hurt - an x-ray figure (15 regions, bones, organs) drawn from the
--     model's Anat attribute, its pulse, blood volume, consciousness, state and cause of death.
--   INJURY FEED (bottom middle): what just broke, in words.
--   SPAWN MENU (V, or the hub's DUMMY DEPOT): pick a thing, click the ground to place it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Sandbox")
local Net, GrabAim = Shared:WaitForChild("Net"), Shared:WaitForChild("GrabAim")
local Config = require(Shared:WaitForChild("Config"))
-- (2026-11-14) the drawn colour icons: the hotbar, the spawn menu, the placing banner
local Icons = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Icons"))
local PA
pcall(function()
	PA = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
end)
local C = Color3.fromRGB
local ORANGE, INK, WHITE, PANEL = C(236, 118, 32), C(14, 16, 24), C(244, 244, 248), C(20, 23, 34)
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
_G.SandboxArmed = false

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function corner(o, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end
local function stroke(o, color, w, tr)
	return new("UIStroke", { Color = color or INK, Thickness = w or 1.5, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end
local function text(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = WHITE, TextSize = 14, Text = "" }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- (2026-11-14) DisplayOrder 5, just under CharacterSelect (6): the hotbar and the NEXT panel used to draw over the shop
-- and inventory windows (on a phone the NEXT panel sat on the inventory's close button)
local gui = new("ScreenGui", { Name = "SandboxHud", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local uiScale = new("UIScale", {}, root)
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	uiScale.Scale = math.clamp(math.min(vp.Y / 1000, vp.X / 1500), 0.55, 1.15)
	root.Size = UDim2.fromScale(1 / uiScale.Scale, 1 / uiScale.Scale)
end
fit()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

---------------------------------------------------------------------------------------------------------- toasts
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(600, 120), BackgroundTransparency = 1 }, root)
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
local toastN = 0
local function toast(msg, color)
	toastN += 1
	local t = text(toastHolder, { LayoutOrder = toastN, Size = UDim2.fromOffset(560, 34), Text = msg, Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = color or WHITE, TextTransparency = 1 })
	local st = new("UIStroke", { Color = INK, Thickness = 2.5, Transparency = 1 }, t)
	tween(t, 0.15, { TextTransparency = 0 })
	tween(st, 0.15, { Transparency = 0 })
	task.delay(2.6, function()
		tween(t, 0.4, { TextTransparency = 1 })
		tween(st, 0.4, { Transparency = 1 })
		Debris:AddItem(t, 0.45)
	end)
end
-- (2026-11-15) the owner: "for the kills text ... just make it 1 thing and then as u get more, make a xX thing increase so
-- like x1 x2 x3 x4 rather than keeping on displaying a new one every time". ONE kill line: each kill while it is still up
-- bumps its count (with a little pop) and keeps it up another 2.6 s; once it has faded, the next kill starts at x1 again.
local KILL_COLOR = C(255, 110, 90)
local killLine = { n = 0, token = 0 }
local function killToast(name)
	local K = killLine
	if not (K.label and K.label.Parent) then
		toastN += 1
		K.n = 0
		K.label = text(toastHolder, { Name = "KillLine", LayoutOrder = toastN, Size = UDim2.fromOffset(560, 34), Text = "", Font = Enum.Font.GothamBold,
			TextSize = 21, TextColor3 = KILL_COLOR, TextTransparency = 1 })
		K.stroke = new("UIStroke", { Color = INK, Thickness = 2.5, Transparency = 1 }, K.label)
		K.scale = new("UIScale", { Scale = 1 }, K.label)
	end
	K.n += 1
	K.token += 1
	local my = K.token
	K.label.Text = string.format("KILL  -  %s   x%d", string.upper(tostring(name or "")), K.n)
	tween(K.label, 0.15, { TextTransparency = 0 })
	tween(K.stroke, 0.15, { Transparency = 0 })
	if K.n > 1 then
		K.scale.Scale = 1.22
		tween(K.scale, 0.2, { Scale = 1 })
	end
	task.delay(2.6, function()
		if K.token ~= my or not K.label then
			return
		end
		tween(K.label, 0.4, { TextTransparency = 1 })
		tween(K.stroke, 0.4, { Transparency = 1 })
		task.delay(0.45, function()
			if K.token == my and K.label then
				K.label:Destroy()
				K.label = nil
			end
		end)
	end)
end

--------------------------------------------------------------------------------------------------------- arsenal
local slot = "fists"
local slotBtns = {}
-- (2026-11-13) the owner sent a reference HUD: dark rounded tiles, white icons, one clean bold font. So the weapons
-- are a numbered HOTBAR along the bottom edge (they were a list down the right), what the held weapon does is a
-- CONTROLS list top-left, and the gun's next upgrade is a progress panel top-right. Every icon is drawn from Frames
-- (no image ids). The sizes of the pieces other HUDs must dodge are published on PlayerGui: HotbarLift, KeyRowLift,
-- HudTopRightY (real pixels) - MoveDock, Dash and HudRails read them.
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local TILE, TILE_ON, DIM, DARK = C(22, 23, 28), C(60, 62, 74), C(176, 180, 192), C(10, 11, 14)
local SLOT_W = 84
local FADE = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(0.55, 0.5), NumberSequenceKeypoint.new(1, 1) })
local function tile(o, r)
	o.BackgroundColor3, o.BackgroundTransparency, o.BorderSizePixel = TILE, 0.14, 0
	corner(o, r or 10)
	return stroke(o, C(0, 0, 0), 1.5, 0.5)
end
local function nice(s) -- "TAKES LIMBS OFF" -> "Takes limbs off"
	s = string.lower(tostring(s or ""))
	return (s:gsub("^%l", string.upper))
end
-- one white stroke of an icon: centre, size and corner are fractions of the icon's box, so it scales with the slot
local function bar(parent, x, y, w, h, rot, r)
	local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), Rotation = rot or 0,
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, parent)
	new("UICorner", { CornerRadius = UDim.new(r or 0.5, 0) }, f)
	return f
end
-- (2026-11-14) the slot icons are HudShared.Icons now: full-colour drawings in place of the white silhouettes
-- (2026-11-13) the NORMAL choice in the fighter list (Kits entry with noPowers): no anime moves. Slot 1 is then plain
-- FISTS, and this script throws the punch itself - through the shared punch every fighter already has
-- (GojoClient.SharedPunch), because no kit script is listening for that player's M1.
local function noPowers()
	return player:GetAttribute("Kit") == "Normal"
end
-- (2026-11-13) the owner: "both the normal weapons and the powers shouldn't be visible, it should be just the normal at
-- first and then u can switch to anime characters". So it is one or the other: NORMAL has the whole hotbar and no
-- move bar; an anime fighter has its move bar and only POWERS + GRAB down here (Main refuses the rest too).
local function allowed(id)
	return id == "fists" or id == "grab" or noPowers()
end
local weaponsHint -- the "1 - 7 Weapons" key hint (made further down); styleSlots rewrites it
local fitKeys -- forward (made with the key strip): drops that hint when it would run under the hotbar
local publish -- forward
local hotbar = new("Frame", { Name = "Hotbar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(#Config.SLOTS * (SLOT_W + 8) - 8, SLOT_W), BackgroundTransparency = 1 }, root)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center }, hotbar)

-- CONTROLS (top-left, above the tile rail): what the weapon in your hand does
-- (2026-11-14) it runs from the screen edge, its text on the tile rail's left edge and 10 px clear of the rail (publish()
-- places it): it started 9 px in with its text at 16 px, touching the rail, and read as clipped
local controls = new("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0.36, -12), Size = UDim2.fromOffset(360, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = DARK, BorderSizePixel = 0, Visible = not TOUCH }, root)
new("UIGradient", { Transparency = FADE }, controls)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, controls)
local controlsPad = new("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, controls)
local MOUSE = {}
-- (2026-11-15, owner: "edit the shoot icon to left click") a LEFT CLICK, unmistakably: a dark mouse with a white outline,
-- its left button lit orange, the right one dark, a line between them
local function mouseIcon(parent)
	local m = new("Frame", { Size = UDim2.fromOffset(20, 28), BackgroundColor3 = DARK, BorderSizePixel = 0 }, parent)
	corner(m, 10)
	stroke(m, WHITE, 1.5, 0)
	local left = new("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(0.5, -2, 0.42, 0), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, m)
	new("UICorner", { CornerRadius = UDim.new(0.6, 0) }, left)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.new(0, 1.5, 0.42, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, m)
	new("Frame", { Position = UDim2.new(0, 2, 0.42, 2), Size = UDim2.new(1, -4, 0, 1.5), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, m)
	return m
end
local function controlsFor(id)
	if id == "fists" then
		if noPowers() then
			return { { MOUSE, "Punch" } }
		end
		return { { MOUSE, "Punch" }, { "Q E R G", "Fighter moves" } } -- (2026-11-15) the left-click icon, as on the weapons
	elseif id == "grab" then
		return { { MOUSE, "Hold to drag" }, { "F", "Throw" } }
	elseif id == "gun" then
		if (player:GetAttribute("GunTier") or 1) > 1 then
			return { { MOUSE, "Shoot" }, { "7", "Switch gun" } }
		end
		return { { MOUSE, "Shoot" } }
	end
	return { { MOUSE, "Swing" } }
end
-- (2026-11-15) the gun in hand: GunPick (any unlocked tier, the server checks it), else the newest
local function gunPick()
	local top = player:GetAttribute("GunTier") or 1
	return math.clamp(math.floor(tonumber(player:GetAttribute("GunPick")) or top), 1, top), top
end
local function gunDef()
	return Config.GUNS[(gunPick())] or Config.GUNS[1]
end
local function nameOfSlot(id)
	if id == "gun" then
		return gunDef().name
	elseif id == "fists" and noPowers() then
		return "FISTS"
	end
	return Config.WEAPONS[id].name
end
local function showControls()
	for _, c in ipairs(controls:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local rows = controlsFor(slot)
	local keyW = 22
	for _, r in ipairs(rows) do
		if r[1] ~= MOUSE then
			keyW = math.max(keyW, TextService:GetTextSize(r[1], 21, Enum.Font.GothamBlack, Vector2.new(400, 40)).X)
		end
	end
	-- the weapon's name, and what it is for
	local W = Config.WEAPONS[slot]
	local head = new("Frame", { LayoutOrder = 0, Size = UDim2.fromOffset(310, 30), BackgroundTransparency = 1 }, controls)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center }, head)
	text(head, { LayoutOrder = 1, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Text = nice(nameOfSlot(slot)), TextSize = 21, Font = Enum.Font.GothamBlack })
	if W and W.hint and slot ~= "fists" and slot ~= "grab" and slot ~= "gun" then
		text(head, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Text = nice(W.hint), TextSize = 16, TextColor3 = DIM })
	end
	for i, r in ipairs(rows) do
		local row = new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(310, 34), BackgroundTransparency = 1 }, controls)
		if r[1] == MOUSE then
			local m = mouseIcon(row)
			m.AnchorPoint, m.Position = Vector2.new(0, 0.5), UDim2.new(0, 1, 0.5, 0)
		else
			text(row, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, keyW, 1, 0), Text = r[1], TextSize = 21, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
		end
		text(row, { Position = UDim2.fromOffset(keyW + 16, 0), Size = UDim2.new(1, -keyW - 16, 1, 0), Text = r[2], TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left })
	end
end

-- NEXT (top-right): the gun slot upgrades with all-time kills
local nextP = new("Frame", { Name = "Next", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 96), Size = UDim2.fromOffset(372, 74) }, root)
tile(nextP, 10)
local nextName = text(nextP, { Position = UDim2.fromOffset(16, 9), Size = UDim2.new(1, -140, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, TextTruncate = Enum.TextTruncate.AtEnd })
local nextCount = text(nextP, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 9), Size = UDim2.fromOffset(120, 28), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 22, TextColor3 = DIM })
local nextBack = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -13), Size = UDim2.new(1, -32, 0, 14), BackgroundColor3 = C(54, 56, 66), BorderSizePixel = 0 }, nextP)
corner(nextBack, 7)
local nextFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C(40, 168, 84), BorderSizePixel = 0 }, nextBack)
corner(nextFill, 7)
local lastKills
local function showNext()
	local tier = player:GetAttribute("GunTier") or 1
	local kills = player:GetAttribute("TotalKills") or 0
	if lastKills and kills > lastKills then -- one more toward the next gun: the count flashes green
		nextCount.TextColor3 = C(110, 235, 140)
		tween(nextCount, 0.7, { TextColor3 = DIM })
	end
	lastKills = kills
	local nextG = Config.GUNS[tier + 1]
	if nextG then
		nextName.Text = "Next: " .. nice(nextG.name)
		nextCount.Text = math.min(kills, nextG.kills) .. " / " .. nextG.kills
		tween(nextFill, 0.25, { Size = UDim2.fromScale(math.clamp(kills / math.max(nextG.kills, 1), 0, 1), 1) })
	else
		nextName.Text = "All guns unlocked"
		nextCount.Text = ""
		nextFill.Size = UDim2.fromScale(1, 1)
	end
end
local function styleSlots()
	for id, b in pairs(slotBtns) do
		local on = id == slot
		tween(b.frame, 0.12, { BackgroundColor3 = on and TILE_ON or TILE, BackgroundTransparency = on and 0.04 or 0.14 })
		b.stroke.Color = on and WHITE or C(0, 0, 0)
		b.stroke.Transparency = on and 0.05 or 0.5
		b.stroke.Thickness = on and 2 or 1.5
		if b.alt then
			local plain = noPowers()
			b.alt.Visible = plain
			b.icon.Visible = not plain
		end
		b.frame.Visible = allowed(id)
	end
	showControls()
	showNext()
	-- the gun's upgrade panel and the key hint are NORMAL's too
	local plain = noPowers()
	if nextP.Visible ~= plain then
		nextP.Visible = plain
		if publish then
			publish() -- the tiles under the panel move up into its place
		end
	end
	if weaponsHint then
		for _, l in ipairs(weaponsHint:GetChildren()) do
			if l:IsA("TextLabel") then
				if l.LayoutOrder == 1 then
					l.Text = plain and ("1 - " .. #Config.SLOTS) or "1 - 2"
				else
					l.Text = plain and "Weapons" or "Powers / Grab"
				end
			end
		end
	end
	if fitKeys then
		fitKeys()
	end
end
local equipSlot -- forward
for i, id in ipairs(Config.SLOTS) do
	local f = new("TextButton", { Name = id, LayoutOrder = i, Size = UDim2.fromOffset(SLOT_W, SLOT_W), AutoButtonColor = false, Text = "" }, hotbar)
	local st = tile(f, 10)
	local key = text(f, { Position = UDim2.fromOffset(9, 5), Size = UDim2.fromOffset(20, 20), Text = tostring(i), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left })
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1 }, f)
	Icons.draw(id, icon, { stroke = 1.1 })
	local alt
	if id == "fists" then -- the fist that takes the spark's place for the NORMAL choice
		alt = new("Frame", { Name = "IconPlain", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1, Visible = false }, f)
		Icons.draw("punch", alt, { stroke = 1.1 })
	end
	slotBtns[id] = { frame = f, key = key, stroke = st, icon = icon, alt = alt }
	f.Activated:Connect(function()
		equipSlot(id)
	end)
end
-- what the other HUDs need to know to keep clear of these
function publish()
	fit()
	local s = uiScale.Scale
	local top = math.max(GuiService:GetGuiInset().Y, 36)
	nextP.Position = UDim2.new(1, -16, 0, (top + 10) / s)
	controlsPad.PaddingLeft = UDim.new(0, 12 / s) -- 12 real px: the tile rail's left edge
	-- (2026-11-14) right above the left rail, wherever HudRails centred it (PlayerGui attribute LeftRailTop, real px)
	local railTop = tonumber(playerGui:GetAttribute("LeftRailTop"))
	controls.Position = railTop and UDim2.new(0, 0, 0, (railTop - 10) / s) or UDim2.new(0, 0, 0.36, -10 / s)
	if fitKeys then
		fitKeys()
	end
	playerGui:SetAttribute("HotbarLift", math.floor((SLOT_W + 14 + 8) * s + 0.5))
	playerGui:SetAttribute("KeyRowLift", TOUCH and 0 or math.floor((46 + 14 + 6) * s + 0.5))
	playerGui:SetAttribute("HudTopRightY", math.floor(top + 10 + (nextP.Visible and (74 * s + 8) or 0) + 0.5))
end
publish()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(publish)
playerGui:GetAttributeChangedSignal("LeftRailTop"):Connect(publish) -- (2026-11-14) HudRails re-centred the left rail

------------------------------------------------------------------------------------------------- weapon animation
local function P(rs, re, w, ls, le)
	local pose = { RightShoulder = rs, RightElbow = re, Waist = w }
	if ls then
		pose.LeftShoulder, pose.LeftElbow = ls, le
	end
	return pose
end
local CLIPS = {
	-- (2026-11-13) the owner: "fix the sword and bat swing animations". The old bat was two poses - arm out to the side,
	-- arm in front - with the chest turning AGAINST the swing, so the bat rode along upright and swept about 54 degrees.
	-- These keys were SOLVED, not posed: for seven points along a flat right-to-left arc the shoulder / elbow / wrist
	-- angles were fitted (forward kinematics on an R15 rig) so the hand leads and the bat TIP runs level at chest
	-- height from behind the right shoulder, round the right side, through the front and out to the left - about 310
	-- degrees. The weapon lies along the hand's -Z, so it is the WRIST (not posed before) that lays it into the swing.
	-- Keys are dense because joints interpolate by the shortest rotation: with three keys the tip looped up over the
	-- head between them. The hit lands at Config wind 0.16; the key at 0.185 is the bat crossing the front.
	bat = { length = 0.5, fadeIn = 0.04, fadeOut = 0.12, keys = {
		{ t = 0.1, ease = { "Sine", "Out" }, pose = { RightShoulder = { -130, -128, -142 }, RightElbow = { 128, 0, 0 }, RightWrist = { -63, -54, 0 }, Waist = { 3, -38, 0 } } },
		{ t = 0.125, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -114, -136, -145 }, RightElbow = { 101, 0, 0 }, RightWrist = { -63, -54, 0 }, Waist = { 1, -22, 0 } } },
		{ t = 0.147, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -96, -140, -147 }, RightElbow = { 67, 0, 0 }, RightWrist = { -58, -51, 0 }, Waist = { -1, -6, 0 } } },
		{ t = 0.165, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -70, -134, -153 }, RightElbow = { 26, 0, 0 }, RightWrist = { -64, -21, 0 }, Waist = { -3, 6, 0 } } },
		{ t = 0.185, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -96, -194, -187 }, RightElbow = { 5, 0, 0 }, RightWrist = { -65, 9, 0 }, Waist = { -4, 18, 0 } } },
		{ t = 0.225, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -98, -217, -197 }, RightElbow = { 27, 0, 0 }, RightWrist = { -63, 20, 0 }, Waist = { -5, 31, 0 } } },
		{ t = 0.3, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -104, -236, -199 }, RightElbow = { 59, 0, 0 }, RightWrist = { -64, 15, 0 }, Waist = { -6, 44, 0 } } },
		{ t = 0.5, ease = { "Quad", "InOut" }, pose = { RightShoulder = { 30, 0, 0 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { 0, 0, 0 } } } } },
	axe = { length = 0.8, fadeIn = 0.05, fadeOut = 0.22, keys = {
		{ t = 0.22, ease = { "Sine", "Out" }, pose = P({ 168, 0, 6 }, { 60, 0, 0 }, { -16, 8, 0 }) },
		{ t = 0.34, ease = { "Exponential", "Out" }, pose = P({ 24, 0, -8 }, { 6, 0, 0 }, { 26, -10, 0 }) },
		{ t = 0.8, ease = { "Quad", "Out" }, pose = P({ 30, 0, 0 }, { 30, 0, 0 }, { 0, 0, 0 }) } } },
	-- (2026-11-13) solved the same way: a diagonal cut. Up over the right shoulder, straight down through what is in
	-- front (the key at 0.138; Config wind is 0.12), and out past the left hip with the point at the ground. The wrist
	-- lays the blade nearly in line with the forearm, so the sword reaches instead of standing upright in the fist.
	katana = { length = 0.42, fadeIn = 0.03, fadeOut = 0.1, keys = {
		{ t = 0.075, ease = { "Sine", "Out" }, pose = { RightShoulder = { -59, 150, 190 }, RightElbow = { 111, 0, 0 }, RightWrist = { -83, -52, 0 }, Waist = { 6, -20, 0 } } },
		{ t = 0.098, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -57, 140, 172 }, RightElbow = { 75, 0, 0 }, RightWrist = { -84, -41, 0 }, Waist = { 2, -9, 0 } } },
		{ t = 0.118, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -66, 167, 154 }, RightElbow = { 37, 0, 0 }, RightWrist = { -82, -27, 0 }, Waist = { -2, 3, 0 } } },
		{ t = 0.138, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -92, 204, 163 }, RightElbow = { 14, 0, 0 }, RightWrist = { -81, -11, 0 }, Waist = { -6, 14, 0 } } },
		{ t = 0.175, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -109, 222, 154 }, RightElbow = { 5, 0, 0 }, RightWrist = { -81, -17, 0 }, Waist = { -9, 24, 0 } } },
		{ t = 0.23, ease = { "Linear", "InOut" }, pose = { RightShoulder = { -137, 228, 139 }, RightElbow = { 5, 0, 0 }, RightWrist = { -81, -25, 0 }, Waist = { -12, 34, 0 } } },
		{ t = 0.42, ease = { "Quad", "InOut" }, pose = { RightShoulder = { 30, 0, 0 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { 0, 0, 0 } } } } },
	sledge = { length = 1.1, fadeIn = 0.06, fadeOut = 0.26, keys = {
		{ t = 0.32, ease = { "Sine", "Out" }, pose = P({ 172, 0, 10 }, { 46, 0, 0 }, { -20, 0, 0 }, { 150, 0, -24 }, { 60, 0, 0 }) },
		{ t = 0.46, ease = { "Exponential", "Out" }, pose = P({ 28, 0, -10 }, { 4, 0, 0 }, { 30, 0, 0 }, { 40, 0, -30 }, { 20, 0, 0 }) },
		{ t = 1.1, ease = { "Quad", "Out" }, pose = P({ 30, 0, 0 }, { 30, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }) } } },
	holdGun = { length = 36000, fadeIn = 0.12, fadeOut = 0.15, keys = {
		{ t = 0.12, pose = P({ 86, 0, -6 }, { 4, 0, 0 }, { 0, -6, 0 }) }, { t = 36000, pose = P({ 86, 0, -6 }, { 4, 0, 0 }, { 0, -6, 0 }) } } },
	holdMelee = { length = 36000, fadeIn = 0.15, fadeOut = 0.15, keys = {
		{ t = 0.15, pose = { RightShoulder = { 30, 0, 0 }, RightElbow = { 30, 0, 0 } } }, { t = 36000, pose = { RightShoulder = { 30, 0, 0 }, RightElbow = { 30, 0, 0 } } } } },
	-- (2026-11-15) the BOW: held out at arm's length in the right hand (the gun's arm), the left hand resting at the chest;
	-- bowDraw turns into an archer's stance as it draws (keys SOLVED by forward kinematics on the R15 rig, playtest
	-- 2026-11-15: the chest turned 60 degrees, the bow arm straight ahead with the bow upright, the draw hand back by the ear,
	-- so the nocked arrow points dead ahead - the first guess laid it across the chest); bowRelease snaps the hand open
	holdBow = { length = 36000, fadeIn = 0.15, fadeOut = 0.15, keys = {
		{ t = 0.15, pose = P({ 86, 0, -6 }, { 4, 0, 0 }, { 0, -14, 0 }, { 40, 0, 18 }, { 70, 0, 0 }) },
		{ t = 36000, pose = P({ 86, 0, -6 }, { 4, 0, 0 }, { 0, -14, 0 }, { 40, 0, 18 }, { 70, 0, 0 }) } } },
	bowDraw = { length = 36000, fadeIn = 0.08, fadeOut = 0.12, keys = {
		{ t = 0.14, ease = { "Quad", "Out" }, pose = { Waist = { 0, 35, 0 }, RightShoulder = { 88, 25, 15 }, RightElbow = { 0, 0, 0 }, RightWrist = { -15, -20, 0 },
			LeftShoulder = { 78, -25, -35 }, LeftElbow = { 70, 0, 0 } } },
		{ t = 0.85, ease = { "Sine", "Out" }, pose = { Waist = { 0, 60, 0 }, RightShoulder = { 90, 40, 30 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, -40, 0 },
			LeftShoulder = { 70, -40, -60 }, LeftElbow = { 120, 0, 0 } } },
		{ t = 36000, pose = { Waist = { 0, 60, 0 }, RightShoulder = { 90, 40, 30 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, -40, 0 },
			LeftShoulder = { 70, -40, -60 }, LeftElbow = { 120, 0, 0 } } } } },
	bowRelease = { length = 0.34, fadeIn = 0.01, fadeOut = 0.2, keys = {
		{ t = 0.05, ease = { "Exponential", "Out" }, pose = { Waist = { 0, 60, 0 }, RightShoulder = { 90, 40, 30 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, -40, 0 },
			LeftShoulder = { 60, -50, -85 }, LeftElbow = { 50, 0, 0 } } },
		{ t = 0.34, ease = { "Quad", "InOut" }, pose = { Waist = { 0, -14, 0 }, RightShoulder = { 86, 0, -6 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { 40, 0, 18 }, LeftElbow = { 70, 0, 0 } } } } },
	recoil = { length = 0.16, fadeIn = 0.01, fadeOut = 0.1, keys = {
		{ t = 0.03, pose = P({ 98, 0, -6 }, { 14, 0, 0 }, { -3, -6, 0 }) }, { t = 0.16, pose = P({ 86, 0, -6 }, { 4, 0, 0 }, { 0, -6, 0 }) } } },
}
local holds = setmetatable({}, { __mode = "k" }) -- [character] = track
local function setHold(char, weapon)
	if not PA or not char then
		return
	end
	local old = holds[char]
	if old then
		pcall(function() old:stop(0.15) end)
		holds[char] = nil
	end
	local clip = (weapon == "gun") and CLIPS.holdGun or ((weapon == "bow") and CLIPS.holdBow) or ((CLIPS[weapon] ~= nil) and CLIPS.holdMelee or nil)
	if clip then
		local ok, tr = pcall(PA.play, char, clip)
		if ok then
			holds[char] = tr
		end
	end
end
local function playSwing(char, weapon)
	if PA and char and CLIPS[weapon] then
		pcall(PA.play, char, CLIPS[weapon])
	end
end
if RunService:IsStudio() then
	-- test hook (Studio only): freeze one moment of a swing - script.DebugPose:Invoke("bat", 0.185, 4) holds the key
	-- nearest 0.185 s for 4 s on your own character. A swing is over in half a second; this is how it gets looked at.
	local hook = Instance.new("BindableFunction")
	hook.Name = "DebugPose"
	hook.OnInvoke = function(weapon, t, secs)
		local clip = CLIPS[weapon]
		if not (PA and clip and player.Character) then
			return false
		end
		local best
		for _, k in ipairs(clip.keys) do
			if not best or math.abs(k.t - t) < math.abs(best.t - t) then
				best = k
			end
		end
		secs = secs or 3
		pcall(PA.play, player.Character, { length = secs, fadeIn = 0.05, fadeOut = 0.1, keys = { { t = 0.05, pose = best.pose }, { t = secs, pose = best.pose } } })
		return best.t
	end
	hook.Parent = script
end
local function watchPlayer(p)
	local function apply()
		setHold(p.Character, p:GetAttribute("Weapon"))
	end
	p:GetAttributeChangedSignal("Weapon"):Connect(apply)
	p.CharacterAdded:Connect(function()
		task.wait(1)
		apply()
	end)
	apply()
end
for _, p in ipairs(Players:GetPlayers()) do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

local SND = { swing = 99266120255392, shot = 3444652484 }
local function sound(id, parent, vol, speed)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. string.format("%d", id)
	s.Volume, s.PlaybackSpeed = vol or 0.6, speed or 1
	s.RollOffMinDistance, s.RollOffMaxDistance, s.RollOffMode = 12, 240, Enum.RollOffMode.InverseTapered
	s.Parent = parent or workspace.CurrentCamera
	s:Play()
	Debris:AddItem(s, 3)
end

----------------------------------------------------------------------------------------------------- status card
-- (2026-11-14) touch: top-LEFT, under the SPAWN button - top-right it covered the NEXT panel and the LOCK button
-- (2026-11-14) restyled to match the HUD's dark tiles: a header with the target's name and a coloured state pill, the
-- x-ray figure on a dark scan panel (capsule limbs, a sweeping scan line, damage as a yellow-to-red heat ramp), a live
-- ECG trace under the BPM, slimmer meters, and the last injuries as a list with a dot coloured by severity.
local MUTED, LINE = C(150, 156, 176), C(255, 255, 255)
local XRAY = C(140, 200, 255)
local card = new("Frame", { Name = "Status", AnchorPoint = TOUCH and Vector2.new(0, 0) or Vector2.new(1, 1), Position = TOUCH and UDim2.new(0, 12, 0, 222) or UDim2.new(1, -16, 1, -18),
	Size = UDim2.fromOffset(336, 296), Visible = false }, root)
tile(card, 14)
local cardScale = new("UIScale", { Scale = TOUCH and 0.72 or 1 }, card)
-- header: who, and what state they are in
text(card, { Position = UDim2.fromOffset(16, 9), Size = UDim2.fromOffset(180, 12), Text = "LAST TARGET", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED, Font = Enum.Font.GothamBlack })
local nameL = text(card, { Position = UDim2.fromOffset(16, 22), Size = UDim2.fromOffset(176, 18), Text = "DUMMY", TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.GothamBlack })
local pill = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(322, 25), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = C(120, 230, 140), BackgroundTransparency = 0.8, BorderSizePixel = 0 }, card)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
local pillStroke = stroke(pill, C(120, 230, 140), 1.2, 0.35)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
local stateL = text(pill, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "HEALTHY", TextSize = 12, Font = Enum.Font.GothamBlack, TextColor3 = C(120, 230, 140) })
new("Frame", { Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = LINE, BackgroundTransparency = 0.92, BorderSizePixel = 0 }, card)

-- the scan panel the figure sits on
local scan = new("Frame", { Name = "Scan", Position = UDim2.fromOffset(12, 56), Size = UDim2.fromOffset(144, 228), BackgroundColor3 = DARK, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, card)
corner(scan, 10)
stroke(scan, XRAY, 1, 0.84)
for k = 1, 8 do
	new("Frame", { Position = UDim2.new(0, 0, k / 9, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = XRAY, BackgroundTransparency = 0.95, BorderSizePixel = 0 }, scan)
end
local fig = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(150, 256), BackgroundTransparency = 1, ZIndex = 2 }, scan)
new("UIScale", { Scale = 0.84 }, fig)
local scanLine = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(1, -12, 0, 2), BackgroundColor3 = XRAY, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 5 }, scan)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, scanLine)

-- the figure faces you: its LEFT side is on your right
local LAYOUT = {
	Head = { 57, 0, 36, 36 }, UpperTorso = { 40, 40, 70, 62 }, LowerTorso = { 44, 104, 62, 26 },
	RightUpperArm = { 18, 42, 20, 46 }, RightLowerArm = { 14, 90, 20, 44 }, RightHand = { 12, 136, 22, 14 },
	LeftUpperArm = { 112, 42, 20, 46 }, LeftLowerArm = { 116, 90, 20, 44 }, LeftHand = { 116, 136, 22, 14 },
	RightUpperLeg = { 44, 132, 28, 54 }, RightLowerLeg = { 46, 188, 24, 50 }, RightFoot = { 42, 240, 30, 12 },
	LeftUpperLeg = { 78, 132, 28, 54 }, LeftLowerLeg = { 80, 188, 24, 50 }, LeftFoot = { 78, 240, 30, 12 },
}
local ORDER = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local ORGANS = { "brain", "heart", "lungL", "lungR", "liver", "stomach", "gut", "aorta", "spine" }
local BODY, BONE_C, HURT, BROKEN, DEADC = XRAY, C(238, 232, 214), C(236, 118, 32), C(255, 84, 60), C(120, 22, 22)
local WARM = C(255, 205, 90) -- a scratch; the heat ramp runs WARM -> BROKEN as the region loses health
local BODY_TR, LINE_TR = 0.76, 0.5
local regionUI, organUI = {}, {}
for _, name in ipairs(ORDER) do
	local L = LAYOUT[name]
	local f = new("Frame", { Name = name, Position = UDim2.fromOffset(L[1], L[2]), Size = UDim2.fromOffset(L[3], L[4]), BackgroundColor3 = BODY, BackgroundTransparency = BODY_TR, BorderSizePixel = 0 }, fig)
	-- capsule limbs, a round head, softer torso corners
	new("UICorner", { CornerRadius = (name == "UpperTorso" and UDim.new(0, 14)) or (name == "LowerTorso" and UDim.new(0, 10)) or UDim.new(0.5, 0) }, f)
	local outline = new("UIStroke", { Color = BODY, Thickness = 1.2, Transparency = LINE_TR, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local bones = {}
	local function bone(x, y, w, h, rot, r)
		local b = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0, BackgroundColor3 = BONE_C, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 3 }, f)
		new("UICorner", { CornerRadius = r or UDim.new(0, 3) }, b)
		table.insert(bones, b)
		return b
	end
	if name == "Head" then
		local sk = bone(L[3] / 2, L[4] / 2, L[3] - 10, L[4] - 10, 0, UDim.new(0.5, 0))
		sk.BackgroundTransparency = 1
		stroke(sk, BONE_C, 2, 0.1)
	elseif name == "UpperTorso" then
		bone(L[3] / 2, L[4] / 2, 4, L[4] - 6) -- sternum / spine
		for k = 0, 3 do
			bone(L[3] / 2 - 15, 12 + k * 12, 24, 3, 12)
			bone(L[3] / 2 + 15, 12 + k * 12, 24, 3, -12)
		end
	elseif name == "LowerTorso" then
		bone(L[3] / 2, L[4] / 2 + 2, L[3] - 16, 5)
		bone(L[3] / 2, L[4] / 2, 4, L[4] - 4)
	elseif name:find("Hand") or name:find("Foot") then
		bone(L[3] / 2, L[4] / 2, L[3] - 8, 3)
	else
		bone(L[3] / 2, L[4] / 2, 5, L[4] - 8)
	end
	regionUI[name] = { frame = f, stroke = outline, bones = bones }
end
local function organ(key, parent, x, y, w, h, r)
	local o = new("Frame", { Name = key, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 2 }, parent)
	corner(o, r or 5)
	organUI[key] = o
end
organ("brain", regionUI.Head.frame, 8, 6, 20, 14, 7)
organ("lungR", regionUI.UpperTorso.frame, 7, 8, 20, 36, 8)
organ("lungL", regionUI.UpperTorso.frame, 43, 8, 20, 36, 8)
organ("heart", regionUI.UpperTorso.frame, 34, 22, 15, 15, 6)
organ("aorta", regionUI.UpperTorso.frame, 32, 4, 4, 22, 2)
organ("liver", regionUI.LowerTorso.frame, 5, 3, 26, 11, 5)
organ("stomach", regionUI.LowerTorso.frame, 36, 3, 20, 11, 5)
organ("gut", regionUI.LowerTorso.frame, 12, 15, 38, 8, 4)
organ("spine", regionUI.LowerTorso.frame, 29, 0, 4, 26, 2)

-- vitals, down the right
local RX, RW = 168, 154
local function caption(y, s)
	return text(card, { Position = UDim2.fromOffset(RX, y), Size = UDim2.fromOffset(RW, 12), Text = s, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED, Font = Enum.Font.GothamBlack })
end
caption(57, "HEART RATE")
local bpmRow = new("Frame", { Position = UDim2.fromOffset(RX, 68), Size = UDim2.fromOffset(RW - 28, 34), BackgroundTransparency = 1 }, card)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, bpmRow)
local bpmL = text(bpmRow, { LayoutOrder = 1, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "72", TextSize = 34, Font = Enum.Font.GothamBlack, TextYAlignment = Enum.TextYAlignment.Bottom })
local bpmUnit = text(bpmRow, { LayoutOrder = 2, Size = UDim2.fromOffset(32, 22), Text = "BPM", TextSize = 12, TextColor3 = MUTED, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom })
new("UIPadding", { PaddingBottom = UDim.new(0, 5) }, bpmUnit)
-- the heart: a diamond and two circles, pulsed by a UIScale on every beat
local HEART = C(255, 70, 80)
local heart = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(RX + RW, 86), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1 }, card)
local beatScale = new("UIScale", {}, heart)
local heartParts = {}
for _, h in ipairs({ { 10, 11.5, 45, UDim.new(0, 2) }, { 6.46, 7.96, 0, UDim.new(0.5, 0) }, { 13.54, 7.96, 0, UDim.new(0.5, 0) } }) do
	local p = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(h[1], h[2]), Size = UDim2.fromOffset(10, 10), Rotation = h[3],
		BackgroundColor3 = HEART, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, heart)
	new("UICorner", { CornerRadius = h[4] }, p)
	table.insert(heartParts, p)
end
-- the ECG: one capsule per sample, stretched to join the previous sample so spikes draw as a line
local ECG_N, ECG_H, ECG_STEP = 52, 24, 1 / 45
local ecg = new("Frame", { Position = UDim2.fromOffset(RX, 104), Size = UDim2.fromOffset(RW, ECG_H), BackgroundTransparency = 1 }, card)
new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = LINE, BackgroundTransparency = 0.93, BorderSizePixel = 0 }, ecg)
local ecgDots, ecgX, ecgVals = {}, {}, table.create(ECG_N, 0)
for k = 1, ECG_N do
	ecgX[k] = (k - 0.5) * RW / ECG_N
	local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(ecgX[k], ECG_H / 2), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = C(120, 230, 140),
		BackgroundTransparency = 0.92 * (1 - k / ECG_N) ^ 1.4, BorderSizePixel = 0, ZIndex = 2 }, ecg)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, d)
	ecgDots[k] = d
end
local function ecgDraw()
	local half = ECG_H / 2
	local prevY = half - ecgVals[1] * (half - 2)
	for k = 1, ECG_N do
		local y = half - ecgVals[k] * (half - 2)
		local top, bot = math.min(prevY, y), math.max(prevY, y)
		ecgDots[k].Position = UDim2.fromOffset(ecgX[k], (top + bot) / 2)
		ecgDots[k].Size = UDim2.fromOffset(2.5, bot - top + 2.5)
		prevY = y
	end
end
local function meter(y, label)
	local l = caption(y, label)
	local v = text(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(RX + RW, y - 1), Size = UDim2.fromOffset(70, 14), Text = "100%", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack })
	local back = new("Frame", { Position = UDim2.fromOffset(RX, y + 17), Size = UDim2.fromOffset(RW, 6), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, card)
	corner(back, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, back)
	corner(fill, 3)
	return l, v, fill
end
local _, bloodV, bloodF = meter(138, "BLOOD")
local awakeLab, awakeV, awakeF = meter(171, "CONSCIOUS")
-- the last injuries (newest first), or the cause of death
local SEVC = { C(232, 234, 240), C(255, 224, 110), C(255, 150, 60), C(255, 78, 66) }
local causeHead = caption(205, "RECENT")
local causeL = text(card, { Position = UDim2.fromOffset(RX, 221), Size = UDim2.fromOffset(RW, 60), Text = "", TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Visible = false })
local eventRows = {}
for k = 1, 4 do
	local row = new("Frame", { Position = UDim2.fromOffset(RX, 220 + (k - 1) * 15), Size = UDim2.fromOffset(RW, 14), BackgroundTransparency = 1, Visible = false }, card)
	local dot = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 1, 0.5, 0), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, row)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	local label = text(row, { Position = UDim2.fromOffset(13, 0), Size = UDim2.new(1, -13, 1, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = C(222, 226, 236) })
	eventRows[k] = { frame = row, dot = dot, label = label }
end
local STATE_COL = { Healthy = C(120, 230, 140), Injured = C(250, 220, 90), Bleeding = C(255, 150, 60), Critical = C(255, 84, 70), Unconscious = C(190, 150, 255), Dead = ORANGE }

local target, targetConns = nil, {}
local lastEvents = {} -- { text, severity }, newest first
local function drawAnat(str)
	if type(str) ~= "string" then
		return
	end
	local body, org = string.match(str, "^(.-);(.*)$")
	if not body then
		return
	end
	local i = 0
	for tok in string.gmatch(body, "[^|]+") do
		i += 1
		local name = ORDER[i]
		local ui = name and regionUI[name]
		if ui then
			local hp = tonumber(string.match(tok, "^%d+")) or 100
			local fx, sev, burn = string.find(tok, "f", 1, true) ~= nil, string.find(tok, "s", 1, true) ~= nil, string.find(tok, "b", 1, true) ~= nil
			local dmg = math.clamp((100 - hp) / 70, 0, 1)
			local col = (dmg < 0.04) and BODY or WARM:Lerp(BROKEN, dmg)
			if burn then
				col = col:Lerp(C(70, 44, 30), 0.6)
			end
			-- severed: an empty red outline where the limb was
			ui.frame.BackgroundColor3 = sev and DEADC or col
			ui.frame.BackgroundTransparency = sev and 0.88 or (BODY_TR - dmg * 0.36)
			ui.stroke.Color = sev and BROKEN or col
			ui.stroke.Transparency = sev and 0.2 or (LINE_TR - dmg * 0.3)
			for _, b in ipairs(ui.bones) do
				b.Visible = not sev
				local c = fx and BROKEN or BONE_C
				if b.BackgroundTransparency < 1 then
					b.BackgroundColor3 = c
				else
					local s = b:FindFirstChildOfClass("UIStroke")
					if s then
						s.Color = c
					end
				end
			end
		end
	end
	i = 0
	for tok in string.gmatch(org or "", "[^,]+") do
		i += 1
		local o = organUI[ORGANS[i] or ""]
		if o then
			local v = tonumber(tok) or 100
			o.BackgroundColor3 = (v <= 0) and DEADC or ((v < 62) and HURT or WHITE)
			o.BackgroundTransparency = (v < 62) and 0.05 or 0.5
		end
	end
end
local function refreshVitals()
	local m = target
	if not m or not m.Parent then
		return
	end
	local blood, bpm, awake = m:GetAttribute("Blood") or 100, m:GetAttribute("BPM") or 72, m:GetAttribute("Awake") or 100
	local st = m:GetAttribute("State") or "Healthy"
	local sc = STATE_COL[st] or WHITE
	stateL.Text = string.upper(st)
	stateL.TextColor3 = sc
	pill.BackgroundColor3 = sc
	pillStroke.Color = sc
	for _, d in ipairs(ecgDots) do
		d.BackgroundColor3 = sc
	end
	bpmL.Text = tostring(bpm)
	bpmL.TextColor3 = (bpm == 0) and ORANGE or ((bpm > 150 or bpm < 45) and C(255, 110, 90) or WHITE)
	bloodV.Text = blood .. "%"
	tween(bloodF, 0.2, { Size = UDim2.fromScale(math.clamp(blood / 100, 0, 1), 1), BackgroundColor3 = C(220, 40, 50):Lerp(C(255, 110, 110), blood / 100) })
	awakeLab.Text = (st == "Dead") and "NO SIGNS" or ((awake < 25) and "UNCONSCIOUS" or ((awake < 70) and "FADING" or "CONSCIOUS"))
	awakeV.Text = awake .. "%"
	tween(awakeF, 0.2, { Size = UDim2.fromScale(math.clamp(awake / 100, 0, 1), 1), BackgroundColor3 = C(190, 150, 255):Lerp(XRAY, math.clamp(awake / 100, 0, 1)) })
	local cause = m:GetAttribute("Cause") or ""
	local dead = cause ~= ""
	causeHead.Text = dead and "CAUSE OF DEATH" or "RECENT"
	causeHead.TextColor3 = dead and ORANGE or MUTED
	causeL.Visible = dead
	causeL.Text = cause
	for k, row in ipairs(eventRows) do
		local e = lastEvents[k]
		row.frame.Visible = not dead and e ~= nil
		if e then
			row.label.Text = e[1]
			row.label.TextTransparency = (k - 1) * 0.16 -- older ones fade back
			row.dot.BackgroundColor3 = SEVC[e[2]] or SEVC[1]
			row.dot.BackgroundTransparency = (k - 1) * 0.16
		end
	end
end
local function setTarget(m)
	if m == target then
		return
	end
	for _, c in ipairs(targetConns) do
		c:Disconnect()
	end
	table.clear(targetConns)
	table.clear(lastEvents)
	target = m
	if not m then
		card.Visible = false
		return
	end
	local plr = Players:GetPlayerFromCharacter(m)
	local hum = m:FindFirstChildOfClass("Humanoid")
	nameL.Text = string.upper((plr and plr.DisplayName) or (hum and hum.DisplayName ~= "" and hum.DisplayName) or m.Name)
	card.Visible = true
	cardScale.Scale = (TOUCH and 0.72 or 1) * 0.94
	tween(cardScale, 0.2, { Scale = TOUCH and 0.72 or 1 }, Enum.EasingStyle.Back)
	for _, a in ipairs({ "Blood", "BPM", "Awake", "State", "Cause" }) do
		table.insert(targetConns, m:GetAttributeChangedSignal(a):Connect(refreshVitals))
	end
	table.insert(targetConns, m:GetAttributeChangedSignal("Anat"):Connect(function()
		drawAnat(m:GetAttribute("Anat"))
	end))
	table.insert(targetConns, m.AncestryChanged:Connect(function(_, parent)
		if not parent and target == m then
			task.delay(4, function()
				if target == m then
					setTarget(nil)
				end
			end)
		end
	end))
	drawAnat(m:GetAttribute("Anat"))
	refreshVitals()
end
-- one QRS-ish beat, sampled at ECG_STEP: a small P bump, the spike, a dip, then the T wave
local SPIKE = { 0.08, 0.14, 0.08, 0, 0, -0.12, 1, -0.5, 0, 0, 0, 0.1, 0.2, 0.24, 0.2, 0.1 }
local beatAt, ecgAcc, ecgQ = 0, 0, {}
RunService.Heartbeat:Connect(function(dt)
	if not card.Visible or not target then
		return
	end
	local t = os.clock()
	scanLine.Position = UDim2.new(0.5, 0, 0, 6 + (t * 0.4 % 1) * 216)
	local bpm = target:GetAttribute("BPM") or 0
	if bpm <= 0 then
		for _, p in ipairs(heartParts) do
			p.BackgroundTransparency = 0.7
		end
		table.clear(ecgQ)
	elseif t >= beatAt then
		beatAt = t + 60 / math.clamp(bpm, 20, 220)
		beatScale.Scale = 1.3
		tween(beatScale, 0.25, { Scale = 1 })
		for _, p in ipairs(heartParts) do
			p.BackgroundTransparency = 0
			tween(p, 0.25, { BackgroundTransparency = 0.3 })
		end
		table.clear(ecgQ)
		table.move(SPIKE, 1, #SPIKE, 1, ecgQ)
	end
	ecgAcc = math.min(ecgAcc + dt, 0.25)
	local moved = false
	while ecgAcc >= ECG_STEP do
		ecgAcc -= ECG_STEP
		table.remove(ecgVals, 1)
		table.insert(ecgVals, table.remove(ecgQ, 1) or 0)
		moved = true
	end
	if moved then
		ecgDraw()
	end
end)

------------------------------------------------------------------------------------------------------------ feed
-- (2026-11-15, owner: "less in the middle of the screen and move it down a little") lower-left, beside the tile rail and
-- over the key strip, lines left-aligned - it used to stack in the middle of the screen, over your own character
-- (touch: the lower-left is the thumbstick, so phones keep it centred, just lower than it was)
local feed = new("Frame", { Name = "Feed", AnchorPoint = TOUCH and Vector2.new(0.5, 1) or Vector2.new(0, 1),
	Position = TOUCH and UDim2.new(0.5, 0, 1, -250) or UDim2.new(0.09, 0, 1, -120), Size = UDim2.fromOffset(420, 140), BackgroundTransparency = 1 }, root)
new("UIListLayout", { Padding = UDim.new(0, 3), HorizontalAlignment = TOUCH and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, feed)
local SEV = { C(232, 234, 240), C(255, 224, 110), C(255, 150, 60), C(255, 78, 66) }
local feedN, feedRows = 0, {}
local function pushFeed(msg, sev)
	feedN += 1
	local big = sev >= 4
	local t = text(feed, { LayoutOrder = feedN, Size = UDim2.fromOffset(420, big and 30 or 22), TextXAlignment = TOUCH and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = string.upper(msg), Font = Enum.Font.GothamBold, TextSize = big and 22 or 16, TextColor3 = SEV[sev] or SEV[1], TextTransparency = 1 })
	local st = new("UIStroke", { Color = INK, Thickness = 2.2, Transparency = 1 }, t)
	tween(t, 0.12, { TextTransparency = 0 })
	tween(st, 0.12, { Transparency = 0 })
	table.insert(feedRows, t)
	while #feedRows > 5 do
		table.remove(feedRows, 1):Destroy()
	end
	task.delay(big and 6 or 4.5, function()
		if t.Parent then
			tween(t, 0.5, { TextTransparency = 1 })
			tween(st, 0.5, { Transparency = 1 })
			task.delay(0.55, function()
				local i = table.find(feedRows, t)
				if i then
					table.remove(feedRows, i)
				end
				t:Destroy()
			end)
		end
	end)
end

------------------------------------------------------------------------------------------------------ spawn menu
local placing = nil
-- (2026-11-14) restyled from the orange-header comic panel to the HUD's dark tiles: a plain title row, item cards with a
-- drawn white icon each, a quiet red CLEAR button
-- (2026-11-15) 300 -> 392 tall: the DUMMY OF ANYONE row (shop perk) sits between the cards and CLEAR
local menu = new("Frame", { Name = "SpawnMenu", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(470, 392), Visible = false }, root)
-- (2026-11-14) touch: at the phone HUD scale (0.55) its X was 19 px - 1.5x makes it big enough to tap, and it still fits.
-- Desktop: 1.2x - it is a window you read, and at the HUD's scale on a small screen its text came out at 7 px.
local MENU_S = TOUCH and 1.5 or 1.2
local menuScale = new("UIScale", { Scale = MENU_S }, menu)
tile(menu, 14)
menu.BackgroundTransparency = 0.04 -- a window, not a HUD tile: nearly solid
-- (2026-11-14) the owner wants it colourful: an orange title band (as the menu first had), every item its own colour,
-- a bright red CLEAR
local head = new("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, menu)
corner(head, 14)
new("Frame", { Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = ORANGE, BorderSizePixel = 0 }, head) -- squares the band's lower corners
text(head, { Position = UDim2.fromOffset(18, 0), Size = UDim2.fromOffset(80, 54), Text = "Spawn", Font = Enum.Font.GothamBlack, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = INK })
text(head, { Position = UDim2.fromOffset(100, 1), Size = UDim2.new(1, -156, 1, 0), Text = TOUCH and "Pick one, then tap the ground" or "Pick one, then click the ground", TextSize = 14,
	TextColor3 = INK, TextTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
local closeB = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(32, 32), Text = "", BackgroundColor3 = INK,
	BackgroundTransparency = 0.15, AutoButtonColor = false }, head)
closeB:SetAttribute("ThemeKeep", true) -- keeps its own fill if the light colours (HudShared.Theme.COLOURS) come back
corner(closeB, 16)
bar(closeB, 0.5, 0.5, 0.46, 0.08, 45)
bar(closeB, 0.5, 0.5, 0.46, 0.08, -45)
closeB.MouseEnter:Connect(function() tween(closeB, 0.1, { BackgroundTransparency = 0 }) end)
closeB.MouseLeave:Connect(function() tween(closeB, 0.1, { BackgroundTransparency = 0.15 }) end)
local grid = new("Frame", { Position = UDim2.fromOffset(16, 68), Size = UDim2.new(1, -32, 0, 168), BackgroundTransparency = 1 }, menu)
new("UIGridLayout", { CellSize = UDim2.fromOffset(212, 78), CellPadding = UDim2.fromOffset(14, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
local CARD, CARD_ON = C(36, 38, 46), C(52, 55, 66)
-- every spawnable has its own colour: its icon well, its count bar, its hover outline, the placing banner and marker
local SPAWN_COL = { dummy = C(70, 160, 255), gascan = C(232, 62, 58), barrel = C(52, 186, 104), crate = C(200, 138, 70), anyone = C(110, 200, 255) }
-- a square well tinted with the item's colour (dark at the top, the colour pooling at the bottom, a ring of it) holding
-- the item's full-colour drawing from HudShared.Icons
local function spawnIcon(parent, def, size)
	local acc = SPAWN_COL[def.id] or ORANGE
	local well = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, parent)
	corner(well, math.floor(size / 5))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C(30, 32, 40), acc:Lerp(C(0, 0, 0), 0.4)) }, well)
	stroke(well, acc, 1.5, 0.2)
	local ic = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1 }, well)
	Icons.draw(def.id, ic, { stroke = (size >= 40) and 1 or 0.7 })
	return well, acc
end

-- (2026-11-14) PLACING: a banner in the item's colour - its icon, what to do, how to stop - where the yellow text was
local placeBar = new("Frame", { Name = "Placing", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(0, 50),
	AutomaticSize = Enum.AutomaticSize.X, Visible = false }, root)
local placeStroke = tile(placeBar, 12)
local placeScale = new("UIScale", {}, placeBar)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) }, placeBar)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, placeBar)
local placeIcon -- rebuilt for each item
local placeText = text(placeBar, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 17, RichText = true })
local placeStop = new("Frame", { LayoutOrder = 3, Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, placeBar)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, placeStop)
new("Frame", { LayoutOrder = 0, Size = UDim2.fromOffset(1, 26), BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, placeStop)
if not TOUCH then
	local cap = text(placeStop, { LayoutOrder = 1, Size = UDim2.fromOffset(28, 26), BackgroundTransparency = 0.1, BackgroundColor3 = TILE_ON, Text = "V", TextSize = 15 })
	corner(cap, 6)
	stroke(cap, C(78, 80, 92), 1.2, 0.15)
end
text(placeStop, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Text = TOUCH and "Tap SPAWN to stop" or "to stop", TextSize = 14, TextColor3 = DIM })
local ghost
local function setPlacing(def)
	placing = def
	-- (2026-11-14) the fighters' own M1 stands down while placing too, so the click / tap that places is not also a punch
	_G.SandboxArmed = slot ~= "fists" or def ~= nil
	placeBar.Visible = def ~= nil
	if def then
		local acc = SPAWN_COL[def.id] or ORANGE
		if placeIcon then
			placeIcon:Destroy()
		end
		placeIcon = spawnIcon(placeBar, def, 34)
		placeIcon.LayoutOrder = 1
		placeStroke.Color, placeStroke.Transparency, placeStroke.Thickness = acc, 0.15, 2
		placeText.Text = string.format('%s the ground to place <font color="#%s">%s</font>', TOUCH and "Tap" or "Click", acc:ToHex(), nice(def.name))
		placeScale.Scale = 0.9
		tween(placeScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
		if not ghost then
			ghost = Instance.new("Part")
			ghost.Shape = Enum.PartType.Cylinder
			ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch, ghost.CastShadow = true, false, false, false, false
			ghost.Material, ghost.Transparency = Enum.Material.Neon, 0.45
			ghost.Size = Vector3.new(0.2, 5, 5)
		end
		ghost.Color = acc
		ghost.Parent = (not TOUCH) and workspace or nil -- (touch places where you tap: no marker to follow)
	elseif ghost then
		ghost.Parent = nil
	end
end

-- (2026-11-14) how many of each you have out, against your cap (Sandbox.Main: Config cap x the SpawnCapMul attribute,
-- 1-5). Read from the world: your dummies in workspace.NPCs and your props in workspace.Gore carry Owner = your UserId.
-- At the cap the server swaps your oldest for the new one, and the card says so.
local countRows = {}
local function refreshCounts()
	local have, uid = {}, player.UserId
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in ipairs(npcs:GetChildren()) do
			if m:GetAttribute("Owner") == uid then
				have.dummy = (have.dummy or 0) + 1
			end
		end
	end
	local gore = workspace:FindFirstChild("Gore")
	if gore then
		for _, p in ipairs(gore:GetChildren()) do
			local k = p:GetAttribute("Kind")
			if k and p:GetAttribute("Owner") == uid then
				have[k] = (have[k] or 0) + 1
			end
		end
	end
	local mul = player:GetAttribute("SpawnCapMul")
	mul = (type(mul) == "number" and mul == mul) and math.clamp(mul, 1, 5) or 1
	for _, def in ipairs(Config.SPAWN) do
		local r = countRows[def.id]
		if r then
			local cap = math.floor(def.cap * mul + 0.5)
			local n = math.min(have[def.id] or 0, cap)
			local full = n >= cap
			r.label.Text = n .. " / " .. cap
			r.label.TextColor3 = full and WHITE or r.acc:Lerp(WHITE, 0.2)
			r.hint.Text = full and "Full: swaps your oldest" or r.hintText
			r.hint.TextColor3 = full and r.acc:Lerp(WHITE, 0.35) or DIM
			tween(r.fill, 0.2, { Size = UDim2.fromScale(cap > 0 and n / cap or 0, 1) })
		end
	end
end
local function setMenu(on)
	menu.Visible = on
	if on then
		setPlacing(nil)
		menuScale.Scale = MENU_S * 0.92
		tween(menuScale, 0.18, { Scale = MENU_S }, Enum.EasingStyle.Back)
		refreshCounts()
	end
end
task.spawn(function()
	while true do
		task.wait(0.5)
		if menu.Visible then
			refreshCounts()
		end
	end
end)
for i, def in ipairs(Config.SPAWN) do
	local b = new("TextButton", { LayoutOrder = i, Text = "", AutoButtonColor = false, BackgroundColor3 = CARD, BorderSizePixel = 0 }, grid)
	corner(b, 10)
	local edge = stroke(b, WHITE, 1, 0.9)
	local well, acc = spawnIcon(b, def, 50)
	well.AnchorPoint, well.Position = Vector2.new(0, 0.5), UDim2.new(0, 12, 0.5, 0)
	local wellScale = new("UIScale", {}, well)
	text(b, { Position = UDim2.fromOffset(74, 11), Size = UDim2.new(1, -84, 0, 20), Text = nice(def.name), Font = Enum.Font.GothamBlack, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local hint = text(b, { Position = UDim2.fromOffset(74, 33), Size = UDim2.new(1, -84, 0, 15), Text = nice(def.hint), TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local count = text(b, { Position = UDim2.fromOffset(74, 51), Size = UDim2.fromOffset(50, 14), Text = "0 / " .. def.cap, Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = acc:Lerp(WHITE, 0.2), TextXAlignment = Enum.TextXAlignment.Left })
	local back = new("Frame", { Position = UDim2.fromOffset(126, 56), Size = UDim2.new(1, -140, 0, 5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, b)
	corner(back, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = acc, BorderSizePixel = 0 }, back)
	corner(fill, 3)
	countRows[def.id] = { label = count, fill = fill, acc = acc, hint = hint, hintText = nice(def.hint) }
	b.MouseEnter:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = CARD_ON })
		tween(wellScale, 0.14, { Scale = 1.08 }, Enum.EasingStyle.Back)
		edge.Color, edge.Transparency, edge.Thickness = acc, 0.1, 1.5
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = CARD })
		tween(wellScale, 0.12, { Scale = 1 })
		edge.Color, edge.Transparency, edge.Thickness = WHITE, 0.9, 1
	end)
	b.Activated:Connect(function()
		menu.Visible = false
		setPlacing(def)
	end)
end
-- (2026-11-15, shop perk "Dummy of Anyone") the ANYONE row: type a Roblox username (or press ME), then SPAWN and click
-- the ground like any other spawn; it goes to Sandbox.Main as ("spawn", "anyone", pos, username). Without the perk the
-- button opens the shop instead. HudShared.OpenPanel("anyone") (the shop's MANAGE) opens the menu on this row.
local anyRow, anyBox, anyGo, anyGoText
do
	local acc = SPAWN_COL.anyone
	anyRow = new("Frame", { Name = "Anyone", Position = UDim2.fromOffset(16, 246), Size = UDim2.new(1, -32, 0, 80), BackgroundColor3 = CARD, BorderSizePixel = 0 }, menu)
	corner(anyRow, 10)
	stroke(anyRow, acc, 1.2, 0.55)
	local well = spawnIcon(anyRow, { id = "anyone" }, 50)
	well.AnchorPoint, well.Position = Vector2.new(0, 0.5), UDim2.new(0, 12, 0.5, 0)
	text(anyRow, { Position = UDim2.fromOffset(74, 8), Size = UDim2.new(1, -84, 0, 20), Text = "Dummy of Anyone", Font = Enum.Font.GothamBlack, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left })
	anyBox = new("TextBox", { Position = UDim2.fromOffset(74, 38), Size = UDim2.fromOffset(170, 30), BackgroundColor3 = C(22, 24, 30), BorderSizePixel = 0,
		Text = "", PlaceholderText = "Any Roblox username", PlaceholderColor3 = DIM, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 14,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, anyRow)
	anyBox:SetAttribute("ThemeKeep", true)
	corner(anyBox, 8)
	stroke(anyBox, acc, 1, 0.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, anyBox)
	local me = new("TextButton", { Position = UDim2.fromOffset(250, 38), Size = UDim2.fromOffset(44, 30), Text = "ME", Font = Enum.Font.GothamBlack, TextSize = 13,
		TextColor3 = WHITE, BackgroundColor3 = C(52, 55, 66), AutoButtonColor = false, BorderSizePixel = 0 }, anyRow)
	corner(me, 8)
	me.Activated:Connect(function()
		anyBox.Text = player.Name
	end)
	anyGo = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 38), Size = UDim2.fromOffset(92, 30), Text = "",
		BackgroundColor3 = acc, AutoButtonColor = false, BorderSizePixel = 0 }, anyRow)
	anyGo:SetAttribute("ThemeKeep", true)
	corner(anyGo, 8)
	anyGoText = text(anyGo, { Size = UDim2.fromScale(1, 1), Text = "Spawn", Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = INK })
	local function owned()
		return player:GetAttribute("Perk_DummyAnyone") == true
	end
	local function refresh()
		local own = owned()
		anyGoText.Text = own and "Spawn" or "Get it"
		anyGo.BackgroundColor3 = own and acc or C(255, 196, 70)
		anyBox.TextEditable = own
		anyBox.PlaceholderText = own and "Any Roblox username" or "Shop perk: any avatar"
	end
	refresh()
	player:GetAttributeChangedSignal("Perk_DummyAnyone"):Connect(refresh)
	anyGo.Activated:Connect(function()
		if not owned() then
			menu.Visible = false
			local op = ReplicatedStorage:WaitForChild("HudShared"):FindFirstChild("OpenPanel")
			if op then
				op:Fire("shop")
			end
			toast("DUMMY OF ANYONE IS IN THE SHOP", C(255, 224, 110))
			return
		end
		local name = string.gsub(anyBox.Text, "[^%w_]", "")
		if name == "" then
			name = player.Name
			anyBox.Text = name
		end
		menu.Visible = false
		setPlacing({ id = "anyone", name = name, cap = 8, username = name })
	end)
end
local CLR, CLR_ON = C(196, 48, 52), C(226, 66, 66)
local clearB = new("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -32, 0, 40), Text = "Clear everything I spawned", Font = Enum.Font.GothamBold, TextSize = 15,
	TextColor3 = WHITE, BackgroundColor3 = CLR, AutoButtonColor = false }, menu)
corner(clearB, 10)
stroke(clearB, C(0, 0, 0), 1.5, 0.5)
clearB.MouseEnter:Connect(function() tween(clearB, 0.1, { BackgroundColor3 = CLR_ON }) end)
clearB.MouseLeave:Connect(function() tween(clearB, 0.1, { BackgroundColor3 = CLR }) end)
clearB.Activated:Connect(function()
	Net:FireServer("clear")
	toast("CLEARED", C(255, 224, 110))
end)
closeB.Activated:Connect(function() setMenu(false) end)
-- (2026-11-13) the keys that always work, as a strip along the bottom-left (this was one blue SPAWN button)
local keyRow = new("Frame", { Name = "Keys", AnchorPoint = TOUCH and Vector2.new(0, 0) or Vector2.new(0, 1), Position = TOUCH and UDim2.new(0, 12, 0, 150) or UDim2.new(0, 0, 1, -14),
	Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = DARK, BackgroundTransparency = TOUCH and 1 or 0, BorderSizePixel = 0 }, root)
new("UIGradient", { Transparency = FADE }, keyRow)
if TOUCH then -- (2026-11-14) the SPAWN button was 22 px tall on a phone: a real thumb-sized button now
	new("UIScale", { Scale = 1.5 }, keyRow)
end
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, keyRow)
local keyPad = new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, TOUCH and 0 or 90) }, keyRow)
local function keyHint(order, key, labelText)
	local b = new("TextButton", { LayoutOrder = order, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, keyRow)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 9), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, b)
	if key then
		local w = math.max(38, TextService:GetTextSize(key, 20, Enum.Font.GothamBold, Vector2.new(300, 40)).X + 20)
		local cap = text(b, { LayoutOrder = 1, Size = UDim2.fromOffset(w, 38), BackgroundTransparency = 0.1, BackgroundColor3 = TILE, Text = key, TextSize = 20 })
		corner(cap, 7)
		stroke(cap, C(78, 80, 92), 1.5, 0.15)
	end
	text(b, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, Text = labelText, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
	return b
end
local spawnBtn = keyHint(1, (not TOUCH) and "V" or nil, "Spawn")
spawnBtn.Name = "SpawnButton"
if TOUCH then -- no key to show: it has to look like a button
	spawnBtn.BackgroundTransparency = 0.14
	spawnBtn.BackgroundColor3 = TILE
	corner(spawnBtn, 9)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, spawnBtn)
else
	keyHint(2, "F", "Throw").Active = false
	weaponsHint = keyHint(3, "1 - " .. #Config.SLOTS, "Weapons")
	weaponsHint.Active = false
end
spawnBtn.Activated:Connect(function()
	if placing then
		setPlacing(nil)
	else
		setMenu(not menu.Visible)
	end
end)
-- (2026-11-14) the strip ran under hotbar slot 1 on screens narrower than about 1.63:1 (16:10 laptops, a small Studio
-- window). The slots carry their own numbers, so when "1 - 7 Weapons" would reach the hotbar, that hint is what goes.
-- Its text starts on the tile rail's left edge (12 px), like CONTROLS above. publish() and styleSlots() call this.
fitKeys = function()
	if TOUCH then
		return
	end
	local s = uiScale.Scale
	keyPad.PaddingLeft = UDim.new(0, 12 / s)
	if not weaponsHint then
		return
	end
	local shown = 0
	for _, b in pairs(slotBtns) do
		if b.frame.Visible then
			shown += 1
		end
	end
	local barLeft = (workspace.CurrentCamera.ViewportSize.X / s - (shown * (SLOT_W + 8) - 8)) / 2
	local right, n = 12 / s, 0
	for _, h in ipairs(keyRow:GetChildren()) do
		if h:IsA("GuiButton") then
			n += 1
			for _, l in ipairs(h:GetChildren()) do
				if l:IsA("TextLabel") then
					right += (l.LayoutOrder == 1) and (l.Size.X.Offset + 9) or TextService:GetTextSize(l.Text, l.TextSize, l.Font, Vector2.new(600, 40)).X
				end
			end
		end
	end
	right += 20 * math.max(n - 1, 0)
	weaponsHint.Visible = right + 24 <= barLeft
end
fitKeys()

----------------------------------------------------------------------------------------------------------- input
local function camRay()
	local cam = workspace.CurrentCamera
	local pos = TOUCH and (cam.ViewportSize / 2) or UserInputService:GetMouseLocation()
	local r = cam:ViewportPointToRay(pos.X, pos.Y)
	return r.Origin, r.Direction
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function mouseHit(range)
	local o, d = camRay()
	rayParams.FilterDescendantsInstances = { player.Character, ghost, workspace:FindFirstChild("FX") }
	local hit = workspace:Raycast(o, d * (range or 300), rayParams)
	return hit, o, d
end
local endDraw -- (2026-11-15) forward: the bow's (made with the attack code further down)
function equipSlot(id)
	if not Config.WEAPONS[id] or not allowed(id) then
		return
	end
	-- (2026-11-15) the gun slot again while holding a gun: the next gun you have unlocked (the old ones stay yours)
	if id == "gun" and slot == "gun" then
		local cur, top = gunPick()
		if top > 1 then
			local nxt = cur % top + 1
			Net:FireServer("equip", "gun", nxt)
			toast(nice(Config.GUNS[nxt].name) .. "  (" .. nxt .. " / " .. top .. ")", WHITE)
		end
		return
	end
	slot = id
	if endDraw then
		endDraw() -- (2026-11-15) a half-drawn arrow is put away with the bow
	end
	_G.SandboxArmed = id ~= "fists"
	Net:FireServer("equip", id)
	styleSlots()
	setPlacing(nil)
end
player:GetAttributeChangedSignal("GunPick"):Connect(styleSlots)
player:GetAttributeChangedSignal("GunTier"):Connect(function()
	styleSlots()
	if slot == "gun" then
		Net:FireServer("equip", "gun")
	end
end)
player:GetAttributeChangedSignal("TotalKills"):Connect(styleSlots)
player:GetAttributeChangedSignal("Kit"):Connect(function() -- NORMAL <-> an anime fighter
	if not allowed(slot) then
		equipSlot("fists") -- the weapon in your hand goes away with NORMAL (equipSlot restyles)
	else
		styleSlots()
	end
end)
local nextSwing, holding, grabbing, grabDist = 0, false, false, 12
local crossKick = 0 -- how far the gun's crosshair is knocked open (see the crosshair, further down)

-- (2026-11-15) THE BOW. Press: start drawing (the bowDraw pose; the string and a nocked arrow follow MY left hand on this
-- screen). Let go: the draw so far (0..1 over Config draw s) goes to Sandbox.Main as ("arrow", from, dir, draw); a tap
-- that hardly drew is cancelled. The arrow leaves the bow's grip aimed at the point under the cursor (the screen centre
-- on touch), so the crosshair is where it goes - less the drop of its arc at a weak draw.
local BOW = Config.WEAPONS.bow and Config.WEAPONS.bow.bow
local drawing -- { t0, track, string = {part, part}, arrow = model }
local function bowDrawK()
	return drawing and BOW and math.clamp((os.clock() - drawing.t0) / BOW.draw, 0, 1) or 0
end
local function localArrow()
	local m = Instance.new("Model")
	m.Name = "LocalArrow"
	local function add(size, off, color, mat)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size, p.Color, p.Material = size, color, mat
		p:SetAttribute("Off", off)
		p.Parent = m
		return p
	end
	add(Vector3.new(0.11, 0.11, 3), CFrame.identity, C(176, 132, 84), Enum.Material.Wood)
	add(Vector3.new(0.2, 0.2, 0.42), CFrame.new(0, 0, -1.65) * CFrame.Angles(0, 0, math.rad(45)), C(70, 72, 80), Enum.Material.Metal)
	add(Vector3.new(0.03, 0.34, 0.55), CFrame.new(0, 0, 1.2), C(220, 60, 60), Enum.Material.SmoothPlastic)
	add(Vector3.new(0.34, 0.03, 0.55), CFrame.new(0, 0, 1.2), C(240, 240, 240), Enum.Material.SmoothPlastic)
	m.Parent = workspace.CurrentCamera
	return m
end
local function placeArrow(m, cf)
	for _, p in ipairs(m:GetChildren()) do
		p.CFrame = cf * (p:GetAttribute("Off") or CFrame.identity)
	end
end
local function bowParts()
	local w = player.Character and player.Character:FindFirstChild("SandboxWeapon")
	return w and w:FindFirstChild("BowGrip"), w and w:FindFirstChild("TipTop"), w and w:FindFirstChild("TipBottom"), w and w:FindFirstChild("String")
end
endDraw = function()
	if not drawing then
		return
	end
	if drawing.track then
		pcall(function() drawing.track:stop(0.08) end)
	end
	for _, s in ipairs(drawing.string or {}) do
		s:Destroy()
	end
	if drawing.arrow then
		drawing.arrow:Destroy()
	end
	local _, _, _, str = bowParts()
	if str then
		str.LocalTransparencyModifier = 0
	end
	drawing = nil
end
local function startDraw()
	if drawing or not BOW or os.clock() < nextSwing then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	drawing = { t0 = os.clock(), string = {} }
	if PA then
		local ok, tr = pcall(PA.play, char, CLIPS.bowDraw)
		if ok then
			drawing.track = tr
		end
	end
	for i = 1, 2 do
		local s = Instance.new("Part")
		s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
		s.Size, s.Color, s.Material = Vector3.new(0.05, 0.05, 1), C(236, 232, 220), Enum.Material.SmoothPlastic
		s.Parent = workspace.CurrentCamera
		drawing.string[i] = s
	end
	drawing.arrow = localArrow()
	sound(SND.swing, char:FindFirstChild("HumanoidRootPart"), 0.25, 0.55)
end
-- the string pulled to my left hand and the arrow on it, every frame while drawing
RunService.RenderStepped:Connect(function()
	if not drawing then
		return
	end
	local char = player.Character
	local grip, top, bottom, str = bowParts()
	local lh = char and char:FindFirstChild("LeftHand")
	if not (grip and top and bottom and lh) then
		return
	end
	str.LocalTransparencyModifier = 1
	local k = bowDrawK()
	-- face where the arrow is going while drawing (the stance's arrow runs along the body's facing)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and not hrp.Anchored then
		local hitA, oA, dA = mouseHit(400)
		local aimAt = hitA and hitA.Position or (oA + dA * 200)
		local flat = (aimAt - hrp.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > 1 then
			hrp.CFrame = hrp.CFrame:Lerp(CFrame.lookAt(hrp.Position, hrp.Position + flat), 0.35)
		end
	end
	local rest = str.Position
	local nock = rest:Lerp(lh.Position, math.clamp(0.25 + k * 0.75, 0, 1))
	for i, tip in ipairs({ top, bottom }) do
		local s = drawing.string[i]
		local a, b = tip.Position, nock
		s.Size = Vector3.new(0.05, 0.05, (b - a).Magnitude)
		s.CFrame = CFrame.lookAt((a + b) / 2, b)
	end
	local fwd = grip.Position - nock
	if fwd.Magnitude > 0.2 then
		fwd = fwd.Unit
		placeArrow(drawing.arrow, CFrame.lookAt(nock + fwd * 1.5, nock + fwd * 3))
	end
end)
local function releaseDraw()
	if not drawing then
		return
	end
	local k = bowDrawK()
	local grip = bowParts()
	endDraw()
	if k < 0.12 or not BOW then
		return -- barely drawn: the arrow stays on the string
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local hit, o, d = mouseHit(600)
	local target = hit and hit.Position or (o + d * 300)
	local from = grip and grip.Position or (hrp.Position + Vector3.new(0, 1.5, 0) + hrp.CFrame.LookVector * 1.5)
	local flat = (target - hrp.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > 1 and not hrp.Anchored then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
	end
	local dir = target - from
	if dir.Magnitude < 1 then
		dir = d
	end
	nextSwing = os.clock() + BOW.cd
	crossKick = 1
	if PA and char then
		pcall(PA.play, char, CLIPS.bowRelease)
	end
	sound(SND.swing, hrp, 0.7, 1.7)
	Net:FireServer("arrow", from, dir.Unit, k)
end
local function attack()
	local W = Config.WEAPONS[slot]
	local t = os.clock()
	if t < nextSwing then
		return
	end
	if slot == "fists" then
		-- only the NORMAL choice gets here (see the input handler): every real fighter's own script throws its M1
		if noPowers() then
			nextSwing = t + 0.2
			local ps = player:FindFirstChild("PlayerScripts")
			local gc = ps and ps:FindFirstChild("GojoClient")
			local ev = gc and gc:FindFirstChild("SharedPunch")
			if ev then
				ev:Fire()
			end
		end
		return
	end
	if slot == "bow" then -- (2026-11-15) press starts the draw; letting go shoots (releaseDraw)
		startDraw()
		return
	end
	local o, d = camRay()
	do -- face what you are attacking
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local hit = mouseHit(250)
		local pt = hit and hit.Position or (o + d * 60)
		if hrp and not hrp.Anchored then
			local flat = (pt - hrp.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude > 1 then
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
			end
		end
	end
	if W and W.dmg then
		nextSwing = t + W.cd
		playSwing(player.Character, slot)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		sound(SND.swing, hrp, 0.6, (slot == "sledge" or slot == "axe") and 0.8 or 1.1)
		Net:FireServer("swing", o, d)
	elseif slot == "gun" then
		local G = gunDef()
		nextSwing = t + G.cd
		crossKick = 1 -- the crosshair jumps open
		playSwing(player.Character, "recoil")
		Net:FireServer("shoot", o, d)
	end
end
local function startGrab()
	local hit, o = mouseHit(70)
	if hit and hit.Instance and not hit.Instance.Anchored then
		grabbing = true
		grabDist = math.clamp((hit.Position - o).Magnitude, 6, 60)
		Net:FireServer("grab", hit.Instance, hit.Instance.CFrame:PointToObjectSpace(hit.Position))
	end
end
local function stopGrab(throw)
	if grabbing then
		grabbing = false
		Net:FireServer("release", throw)
	end
end
local KEYS = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8 } -- (2026-11-15) 8 = the bow
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local k = KEYS[input.KeyCode]
		if k then
			equipSlot(Config.SLOTS[k])
		elseif input.KeyCode == Enum.KeyCode.V then
			if placing then
				setPlacing(nil)
			else
				setMenu(not menu.Visible)
			end
		elseif input.KeyCode == Enum.KeyCode.F and grabbing then
			local _, d = camRay()
			stopGrab(d * 130)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if placing then
			local hit = mouseHit(120)
			if hit then
				Net:FireServer("spawn", placing.id, hit.Position, placing.username)
			end
		elseif slot == "grab" then
			startGrab()
		elseif slot ~= "fists" or noPowers() then
			holding = true
			attack()
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
		stopGrab(nil)
		releaseDraw()
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if grabbing and input.UserInputType == Enum.UserInputType.MouseWheel then
		grabDist = math.clamp(grabDist + input.Position.Z * 2.5, 5, 60)
	end
end)
-- touch: one big button does what the mouse does
local touchBtn = new("TextButton", { Name = "TouchAttack", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -26, 0.5, 0), Size = UDim2.fromOffset(120, 120), Text = "HIT", Font = Enum.Font.GothamBold, TextSize = 24,
	TextColor3 = INK, BackgroundColor3 = ORANGE, BackgroundTransparency = 0.1, Visible = false, AutoButtonColor = false }, root)
corner(touchBtn, 60)
stroke(touchBtn, INK, 3)
touchBtn.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
		if placing then
			local hit = mouseHit(120)
			if hit then
				Net:FireServer("spawn", placing.id, hit.Position, placing.username)
			end
		elseif slot == "grab" then
			if grabbing then
				local _, d = camRay()
				stopGrab(d * 110)
			else
				startGrab()
			end
		else
			holding = true
			attack()
		end
	end
end)
touchBtn.InputEnded:Connect(function()
	holding = false
	releaseDraw()
end)
-- (2026-11-14) touch: while placing, a tap on the ground places the thing where you tapped. (It used to be the HIT
-- button, aimed down the middle of the screen - which is where your own character stands, so the marker hid behind
-- you.) Taps on buttons and the thumbstick arrive with processedByUI and are ignored.
if TOUCH then
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if processedByUI or not placing then
			return
		end
		local cam = workspace.CurrentCamera
		local r = cam:ScreenPointToRay(pos.X, pos.Y)
		rayParams.FilterDescendantsInstances = { player.Character, ghost, workspace:FindFirstChild("FX") }
		local hit = workspace:Raycast(r.Origin, r.Direction * 120, rayParams) -- (the same reach as a mouse click)
		if hit then
			Net:FireServer("spawn", placing.id, hit.Position, placing.username)
		end
	end)
end
-- (2026-11-13) the owner: "make it to where u have a crosshair when ur holding the gun". The gun fires along the ray
-- under the MOUSE (camRay), so the crosshair rides the mouse and stands in for the cursor while the gun is out (it is
-- drawn above every menu, so it still works as the pointer); on touch the shot goes down the middle of the screen, so
-- it sits there. It opens when you fire and turns red over a dummy. Drawn from Frames - no image.
local crossGui = new("ScreenGui", { Name = "SandboxCrosshair", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, Enabled = false }, playerGui)
local cross = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }, crossGui)
local crossBits = {}
for _, t in ipairs({ { 0, -1, 3, 10 }, { 0, 1, 3, 10 }, { -1, 0, 10, 3 }, { 1, 0, 10, 3 }, { 0, 0, 4, 4 } }) do
	local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(t[3], t[4]), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, cross)
	corner(f, 1)
	stroke(f, C(0, 0, 0), 1, 0.3)
	table.insert(crossBits, { f, t[1], t[2] })
end
local crossOn, crossHot, crossAcc = false, false, 0
local aimAcc = 0
RunService.RenderStepped:Connect(function(dt)
	local gunOut = (slot == "gun" or slot == "bow") and placing == nil -- (2026-11-15) the bow aims with it too
	if gunOut ~= crossOn then
		crossOn = gunOut
		crossGui.Enabled = gunOut
		if not TOUCH then
			UserInputService.MouseIconEnabled = not gunOut
		end
	end
	if gunOut then
		local cam = workspace.CurrentCamera
		local at = TOUCH and (cam.ViewportSize / 2) or UserInputService:GetMouseLocation()
		cross.Position = UDim2.fromOffset(at.X, at.Y)
		crossKick = math.max(0, crossKick - dt * 7)
		local gap = 9 + crossKick * 9
		if slot == "bow" then -- it closes in as the draw comes on
			gap = 16 - bowDrawK() * 10 + crossKick * 9
		end
		for _, b in ipairs(crossBits) do
			b[1].Position = UDim2.new(0.5, b[2] * gap, 0.5, b[3] * gap)
		end
		crossAcc += dt
		if crossAcc > 0.1 then -- is there a body under it?
			crossAcc = 0
			local hit = mouseHit(400)
			local npcs = workspace:FindFirstChild("NPCs")
			local hot = hit ~= nil and hit.Instance ~= nil and npcs ~= nil and hit.Instance:IsDescendantOf(npcs)
			if hot ~= crossHot then
				crossHot = hot
				for _, b in ipairs(crossBits) do
					b[1].BackgroundColor3 = hot and C(255, 86, 72) or WHITE
				end
			end
		end
	end
	if TOUCH then
		touchBtn.Visible = placing == nil and (slot ~= "fists" or noPowers()) -- (placing on touch is a tap on the ground)
		touchBtn.Text = placing and "PLACE" or ((slot == "grab") and (grabbing and "THROW" or "GRAB") or ((slot == "gun") and "FIRE" or ((slot == "bow") and "DRAW" or "HIT")))
	end
	if holding and slot == "gun" and gunDef().auto then
		attack()
	end
	if placing and ghost then
		local hit = mouseHit(120)
		if hit then
			ghost.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end
	if grabbing then
		aimAcc += dt
		if aimAcc >= 1 / 30 then
			aimAcc = 0
			local o, d = camRay()
			GrabAim:FireServer(o + d * grabDist)
		end
	end
end)

----------------------------------------------------------------------------------------------------- net + world
local function shake(mag)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or player:GetAttribute("OptNoShake") then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.35 do
			local k = (1 - (os.clock() - t0) / 0.35) * mag
			hum.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
			RunService.RenderStepped:Wait()
		end
		hum.CameraOffset = Vector3.zero
	end)
end
local function near(pos, dist)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position - pos).Magnitude <= dist
end
Net.OnClientEvent:Connect(function(action, a, b, c, d)
	if action == "anyone" then -- (2026-11-15) Dummy of Anyone's answer
		toast(tostring(b or ""), a and C(120, 240, 160) or C(255, 110, 100))
		return
	end
	if action == "inj" then
		local mine = d == player.UserId
		if mine and typeof(a) == "Instance" then
			setTarget(a)
		end
		if a == target or mine then
			pushFeed(b, c or 1)
			if a == target and not string.find(b, "DEAD", 1, true) then
				table.insert(lastEvents, 1, { b, c or 1 })
				while #lastEvents > 4 do
					table.remove(lastEvents)
				end
				refreshVitals()
			end
		end
	elseif action == "swing" then
		if a ~= player and typeof(a) == "Instance" and a.Character then
			playSwing(a.Character, b)
			local hrp = a.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				sound(SND.swing, hrp, 0.5, 1.05)
			end
		end
	elseif action == "shot" then
		local from, ends, id = b, c, d
		if typeof(from) ~= "Vector3" or type(ends) ~= "table" then
			return
		end
		-- (2026-11-14) the tracer leaves the gun's barrel as THIS client sees it (Sandbox.GunModels' Muzzle part); the
		-- server's arm is not in the held pose, so its point is only a fallback
		local wm = typeof(a) == "Instance" and a:IsA("Player") and a.Character and a.Character:FindFirstChild("SandboxWeapon")
		local mz = wm and wm:FindFirstChild("Muzzle")
		if mz and mz:IsA("BasePart") then
			from = mz.Position
		end
		local pitch = ({ pistol = 2.3, revolver = 1.9, smg = 2.6, shotgun = 1.5, rifle = 2.2, sniper = 1.25, minigun = 2.8, launcher = 0.9 })[id] or 2.2
		local att = Instance.new("Attachment")
		att.WorldPosition = from
		att.Parent = workspace.Terrain
		Debris:AddItem(att, 2)
		sound(SND.shot, att, (id == "smg" or id == "minigun") and 0.35 or 0.6, pitch)
		local fl = Instance.new("PointLight")
		fl.Range, fl.Brightness, fl.Color = 14, 4, C(255, 210, 140)
		fl.Parent = att
		Debris:AddItem(fl, 0.05)
		for _, e in ipairs(ends) do
			if typeof(e) == "Vector3" then
				local len = (e - from).Magnitude
				local tr = Instance.new("Part")
				tr.Anchored, tr.CanCollide, tr.CanQuery, tr.CanTouch, tr.CastShadow = true, false, false, false, false
				tr.Material, tr.Color, tr.Transparency = Enum.Material.Neon, C(255, 228, 160), 0.25
				tr.Size = Vector3.new(0.09, 0.09, len)
				tr.CFrame = CFrame.lookAt((from + e) / 2, e)
				tr.Parent = workspace.Terrain
				tween(tr, 0.09, { Transparency = 1 })
				Debris:AddItem(tr, 0.1)
			end
		end
		if a == player then
			shake(id == "sniper" and 0.5 or 0.16)
		end
	elseif action == "arrow" then -- (2026-11-15) an arrow in flight (Sandbox.Main fireArrow): the same arc, drawn here
		local from, vel, grav = b, c, tonumber(d) or 60
		if typeof(from) ~= "Vector3" or typeof(vel) ~= "Vector3" then
			return
		end
		local m = localArrow()
		local shaft = m:GetChildren()[1]
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, 0.06, 1.3), Vector3.new(0, -0.06, 1.3)
		a0.Parent, a1.Parent = shaft, shaft
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime, tr.LightEmission = 0.18, 0.4
		tr.Color = ColorSequence.new(WHITE)
		tr.Transparency = NumberSequence.new(0.5, 1)
		tr.Parent = shaft
		local g = Vector3.new(0, -grav, 0)
		local ignore = { m, workspace:FindFirstChild("Arrows"), workspace:FindFirstChild("FX") }
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(ignore, pl.Character)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		local t0, last = os.clock(), from
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			local pos = from + vel * t + g * (0.5 * t * t)
			local v = vel + g * t
			local hit = (pos - last).Magnitude > 0.01 and workspace:Raycast(last, pos - last, params) or nil
			if hit or t > 4 or pos.Y < -150 then
				conn:Disconnect()
				if hit then
					placeArrow(m, CFrame.lookAt(hit.Position - v.Unit * 1.25, hit.Position))
				end
				Debris:AddItem(m, hit and 0.12 or 0)
				return
			end
			placeArrow(m, CFrame.lookAt(pos, pos + v))
			last = pos
		end)
	elseif action == "jolt" then -- (2026-11-13) a body THIS client is simulating was hit again: the push happens here
		if typeof(a) == "Instance" and typeof(b) == "Vector3" then
			for _, part in ipairs(a:GetChildren()) do
				if part:IsA("BasePart") and not part.Anchored then
					part.AssemblyLinearVelocity += b * ((part.Name == "UpperTorso" or part.Name == "LowerTorso") and 1 or 0.72)
				end
			end
		end
	elseif action == "hit" then -- (2026-11-13) your melee blow landed
		shake(math.clamp(0.14 + (tonumber(c) or 20) / 140, 0.15, 0.8))
	elseif action == "boom" then
		if typeof(a) == "Vector3" and near(a, (b or 20) * 4) then
			shake(math.clamp((b or 20) / 14, 0.4, 2.2))
		end
	elseif action == "tier" then
		local G = Config.GUNS[a]
		if G then
			toast("NEW GUN UNLOCKED: " .. G.name, C(255, 214, 90))
		end
	elseif action == "kill" then
		killToast(a)
	end
end)
-- your own bounce (the server cannot push a player's character)
local bounceAt = 0
local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or os.clock() < bounceAt then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	if v.Y > 4 then
		return
	end
	downParams.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -4.6, 0), downParams)
	if hit and CollectionService:HasTag(hit.Instance, "Trampoline") then
		bounceAt = os.clock() + 0.3
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, hit.Instance:GetAttribute("Power") or 90, v.Z)
		sound(SND.swing, hrp, 0.5, 0.7)
	end
end)
-- kiosks
for _, k in ipairs(CollectionService:GetTagged("SpawnKiosk")) do
	local pp = k:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Triggered:Connect(function() setMenu(true) end)
	end
end
-- (2026-11-15) the shop's MANAGE on Dummy of Anyone opens the menu with the username box ready
do
	local op = ReplicatedStorage:WaitForChild("HudShared"):FindFirstChild("OpenPanel")
	if op then
		op.Event:Connect(function(name)
			if name == "anyone" then
				setMenu(true)
				task.defer(function()
					if anyBox and anyBox.TextEditable then
						anyBox:CaptureFocus()
					end
				end)
			end
		end)
	end
end
for _, k in ipairs(CollectionService:GetTagged("ShopKiosk")) do
	local pp = k:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Triggered:Connect(function()
			local op = ReplicatedStorage:WaitForChild("HudShared"):FindFirstChild("OpenPanel")
			if op then
				op:Fire("shop")
			end
		end)
	end
end
-- BLOOD setting off: wounds, stumps and pools are hidden on this screen only
-- (2026-11-14) + the stains, scraps and blood particles Sandbox.Gore makes
local GORY = { Blood = true, Wound = true, Stump = true, StumpBone = true, Splat = true, Gib = true }
local function hideGore(d)
	if player:GetAttribute("Opt_blood") ~= false then
		return
	end
	if d:IsA("BasePart") and d.Name == "Carved" then
		-- (2026-11-14) a limb with a piece cut out of it (Sandbox.Wounds.carve hides the limb behind this shell): with
		-- BLOOD off this screen keeps the whole limb instead
		d.LocalTransparencyModifier = 1
		local limb = d.Parent
		if limb and limb:IsA("BasePart") then
			local function show()
				if limb.Transparency == 1 and d.Parent == limb and not (limb.Parent and limb.Parent:GetAttribute("Retired")) then
					limb.Transparency = 0
				end
			end
			task.delay(0.15, show)
			limb:GetPropertyChangedSignal("Transparency"):Connect(show)
		end
	elseif d:IsA("BasePart") and GORY[d.Name] then
		d.LocalTransparencyModifier = 1
	elseif d:IsA("ParticleEmitter") and d.Name == "BloodFx" then
		d.Transparency = NumberSequence.new(1) -- (on this screen only: the server never writes it again)
	end
end
workspace.DescendantAdded:Connect(hideGore)
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	equipSlot("fists")
end)
-- (2026-11-14, owner: "some npcs do random circles while theyre ragdolled") a downed NPC THIS machine simulates
-- (RagdollService lends a hit body to whoever hit it) must stay in Physics here too: the server's state locks do not
-- reach this machine's copy of the humanoid, which otherwise ran as Running and steered the limp body round in
-- circles. Same states RagdollService locks; only the copy simulated here (ReceiveAge 0) is ever changed.
do
	local HS = Enum.HumanoidStateType
	local LOCK = { HS.Running, HS.RunningNoPhysics, HS.Jumping, HS.Freefall, HS.Landed, HS.Climbing, HS.Swimming, HS.Seated, HS.StrafingNoPhysics,
		HS.GettingUp, HS.FallingDown, HS.Ragdoll }
	local downed = setmetatable({}, { __mode = "k" }) -- [model] = its humanoid
	local function apply(m)
		local h = m:FindFirstChildOfClass("Humanoid")
		if not h then
			return
		end
		local on = m:GetAttribute("Ragdolled") == true
		if on and not downed[m] then
			downed[m] = h
			for _, s in ipairs(LOCK) do
				pcall(h.SetStateEnabled, h, s, false)
			end
		elseif not on and downed[m] then
			downed[m] = nil
			for _, s in ipairs(LOCK) do
				pcall(h.SetStateEnabled, h, s, true)
			end
		end
	end
	local function watch(m)
		if m:IsA("Model") then
			m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
				apply(m)
			end)
			apply(m)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
		watch(m)
	end
	CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(watch)
	RunService.Heartbeat:Connect(function() -- every frame: a slip into Running is undone before it can steer at all
		for m, h in pairs(downed) do
			if not m.Parent or not h.Parent then
				downed[m] = nil
			elseif h.Health > 0 then
				local t = m:FindFirstChild("UpperTorso")
				if t and t.ReceiveAge == 0 then
					local s = h:GetState()
					if s ~= HS.Physics and s ~= HS.Dead then
						h:ChangeState(HS.Physics)
					end
				end
			end
		end
	end)
end
styleSlots()
