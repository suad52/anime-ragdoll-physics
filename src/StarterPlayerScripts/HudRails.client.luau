--!nocheck
-- StarterPlayerScripts.HudRails (2026-11-13): the owner sent a reference HUD - square dark tiles down the left edge and a
-- few more top-right, one clean bold font - and asked for this game's to look like it.
-- The fighter / shop / inventory / starter-pack / duel / quest / taunt / settings buttons are built by FIVE different
-- scripts as round pills in CharacterSelect.TopStrip (a row beside Roblox's own buttons). A button cannot be clicked
-- from a script, so they are not rebuilt: each pill is MOVED out of the strip into one of two rails here and laid
-- out again as a tile - its own drawn icon enlarged on top, its own label underneath. Their click handlers, hover
-- tweens, cooldown fills and the text other scripts keep writing into them all carry on untouched.
-- Touch devices keep the top strip: the left edge there belongs to the thumbstick.
-- Where the top-right rail sits comes from SandboxClient (PlayerGui attribute HudTopRightY: under its NEXT panel).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local gui = playerGui:WaitForChild("CharacterSelect", 30)
local strip = gui and gui:WaitForChild("TopStrip", 15)
if not strip then
	return
end

-- (2026-11-14) the owner asked for better icons, in colour: the buttons HudShared.Icons has a drawing for show that
-- instead of their own. Their own icon stays (hidden) so the code that owns it still works. The fighter keeps its kit
-- emblem and the starter pack its card art.
local ICON_FOR = { ShopPill = "shop", InventoryPill = "inventory", QuestPill = "quests", SlidersPill = "sliders", TauntPill = "taunt",
	SettingsPill = "settings", DuelPill = "duel", MapsPill = "map", PhotoPill = "camera" } -- (2026-11-15) PhotoPill = StarterPlayerScripts.PhotoMode
local Icons
pcall(function()
	Icons = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Icons", 10))
end)
-- a square box over `icon` (in `parent`) with the drawing in it; `icon` is hidden and kept hidden
local function drawnIcon(pillName, icon, parent, px)
	if not (Icons and ICON_FOR[pillName]) then
		return nil
	end
	local box = Instance.new("Frame")
	box.Name = "DrawnIcon"
	box.AnchorPoint, box.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(px, px)
	box.BackgroundTransparency = 1
	box.ZIndex = icon.ZIndex
	local ok = pcall(Icons.draw, ICON_FOR[pillName], box, { z = icon.ZIndex, stroke = 0.9 })
	if not ok then
		box:Destroy()
		return nil
	end
	box.Parent = parent
	icon.Visible = false
	icon:GetPropertyChangedSignal("Visible"):Connect(function()
		if icon.Visible then
			icon.Visible = false
		end
	end)
	-- (2026-11-14) "keep the effects": the scripts that own these still animate their own (hidden) icon - the gear turns
	-- on hover, the taunt bubble and the duel swords tilt - so the drawing copies its turn and any change of size
	local baseW = icon.Size.X.Offset
	local sc = Instance.new("UIScale")
	sc.Parent = box
	local function mirror()
		box.Rotation = icon.Rotation
		if baseW > 0 then
			sc.Scale = math.max(icon.Size.X.Offset, 1) / baseW
		end
	end
	mirror()
	icon:GetPropertyChangedSignal("Rotation"):Connect(mirror)
	icon:GetPropertyChangedSignal("Size"):Connect(mirror)
	return box
end
if TOUCH then
	-- touch keeps the top strip (the left edge there belongs to the thumbstick), but its buttons get the drawings too,
	-- in place: a square box where their own icon sits
	local done = {}
	local function swap(pill)
		if done[pill] or not pill:IsA("GuiButton") or not ICON_FOR[pill.Name] then
			return
		end
		local icon, area = nil, 0
		for _, ch in ipairs(pill:GetChildren()) do
			if ch:IsA("GuiObject") and not ch:IsA("TextLabel") and ch.Name ~= "Cooldown" and ch.AnchorPoint.X < 1 then
				local a = ch.Size.X.Offset * ch.Size.Y.Offset
				if a > area then
					icon, area = ch, a
				end
			end
		end
		if icon then
			done[pill] = true
			local box = drawnIcon(pill.Name, icon, pill, math.max(icon.Size.X.Offset, icon.Size.Y.Offset, 8))
			if box then
				box.AnchorPoint, box.Position = icon.AnchorPoint, icon.Position
			end
		end
	end
	strip.ChildAdded:Connect(function(ch)
		task.delay(0.4, swap, ch)
	end)
	task.wait(0.6)
	for _, ch in ipairs(strip:GetChildren()) do
		swap(ch)
	end
	return
end
local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local TILE = Color3.fromRGB(22, 23, 28)
-- which rail, in what order, under what name (no name = keep the text its own script writes: the fighter's name)
-- (2026-11-14, sandbox shop) SlidersPill = StarterPlayerScripts.SandboxSliders, right under the shop
local LEFT = { FighterPill = { 1 }, ShopPill = { 2, "Shop" }, SlidersPill = { 3, "Sliders" }, InventoryPill = { 4, "Inventory" }, QuestPill = { 5, "Quests" }, MapsPill = { 6, "Maps" } }
local RIGHT = { StarterPackPill = { 1, "Starter", noSub = true }, DuelPill = { 2, "Duel" }, TauntPill = { 3, "Taunt" }, SettingsPill = { 4, "Settings" }, PhotoPill = { 5, "Photo" } }

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local left = new("Frame", { Name = "LeftRail", Position = UDim2.new(0, 12, 0.36, 0), Size = UDim2.fromOffset(76, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, ZIndex = 35 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, left)
-- ZIndex: the LEFT rail keeps the strip's 35, above the shop / inventory shade (30), so SHOP <-> INVENTORY still switch with
-- one tap and neither window reaches that far left. The TOP-RIGHT rail goes UNDER the shade: measured, the shop window
-- runs under it and the tiles sat on its CODES tab and beside its close button.
local right = new("Frame", { Name = "TopRightRail", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 150), Size = UDim2.fromOffset(0, 76),
	AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 5 }, gui)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)

local T = 76
local tiles = {}
local function titleCase(s)
	s = string.lower(s)
	return (s:gsub("(%a)([%w']*)", function(a, b)
		return string.upper(a) .. b
	end))
end
local function layout(pill, info)
	pill.Size = UDim2.fromOffset(T, T)
	local hasSub = info.sub ~= nil and info.sub.Visible
	if info.holder then
		-- the holder is the icon's own size and a UIScale blows the pair up to half the tile
		info.holder.Size = UDim2.fromOffset(info.iconPx, info.iconPx)
		info.holder.Position = UDim2.fromScale(0.5, hasSub and 0.33 or 0.38)
		info.scale.Scale = (T * (hasSub and 0.46 or 0.5)) / info.iconPx
	end
	if info.title then
		info.title.Position = UDim2.new(0, 4, hasSub and 0.61 or 0.69, 0)
		info.title.Size = UDim2.new(1, -8, 0.2, 0)
		info.cap.MaxTextSize = math.max(8, math.floor(T * 0.17))
	end
	if info.sub then
		info.sub.Position = UDim2.new(0, 4, 0.82, 0)
		info.sub.Size = UDim2.new(1, -8, 0.125, 0)
	end
end
local function adopt(pill)
	if not pill:IsA("TextButton") or tiles[pill] or not pill.Parent then
		return
	end
	local spec, rail = LEFT[pill.Name], left
	if not spec then
		spec, rail = RIGHT[pill.Name], right
	end
	if not spec then
		spec, rail = { 20 }, right -- a pill some later script adds: it still gets a tile
	end
	local info = { spec = spec }
	tiles[pill] = info
	pill.LayoutOrder = spec[1]
	pill.BackgroundColor3 = TILE
	pill.BackgroundTransparency = 0.14
	local c = pill:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, 9)
	end
	-- its icon is the biggest thing drawn in it that is not a cooldown fill or a right-anchored chevron / badge
	local icon, area = nil, 0
	local labels = {}
	for _, ch in ipairs(pill:GetChildren()) do
		if ch:IsA("TextLabel") then
			table.insert(labels, ch)
		elseif ch:IsA("GuiObject") and ch.Name ~= "Cooldown" then
			if ch.AnchorPoint.X >= 1 then
				if pill.Name == "FighterPill" then
					ch.Visible = false -- the dropdown chevron: a tile does not need one
				end
			else
				local a = ch.Size.X.Offset * ch.Size.Y.Offset
				if a > area then
					icon, area = ch, a
				end
			end
		end
	end
	table.sort(labels, function(a, b)
		return a.Position.Y.Offset < b.Position.Y.Offset
	end)
	info.title, info.sub = labels[1], labels[2]
	if icon then
		info.iconPx = math.max(icon.Size.X.Offset, icon.Size.Y.Offset, 8)
		local holder = new("Frame", { Name = "TileIcon", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 }, pill)
		info.scale = new("UIScale", {}, holder)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = holder
		info.holder = holder
		drawnIcon(pill.Name, icon, holder, math.floor(info.iconPx * 1.12 + 0.5)) -- a touch bigger: the old ones filled a disc edge to edge
	end
	if not info.title then
		info.title = new("TextLabel", { Name = "TileLabel", BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), TextScaled = true, FontFace = FONT,
			Text = spec[2] or pill.Name }, pill)
	end
	info.cap = new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 13 }, info.title)
	for _, l in ipairs({ info.title, info.sub }) do
		l.AnchorPoint = Vector2.zero
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.FontFace = FONT
		local ink = l:FindFirstChildOfClass("UIStroke")
		if ink then
			ink.Enabled = false -- the comic ink outline: on a dark tile the plain letters read better
		end
		-- other scripts keep writing these (the fighter's name, the yen, the perk count) in capitals
		local fixed = (l == info.title) and spec[2] or nil
		local function tidy()
			local want = fixed or titleCase(l.Text)
			if l.Text ~= want then
				l.Text = want
			end
		end
		l:GetPropertyChangedSignal("Text"):Connect(tidy)
		tidy()
	end
	if info.sub then
		if spec.noSub then
			info.sub.Visible = false
		end
		info.sub.TextTransparency = 0.1
	end
	pill.Parent = rail
	layout(pill, info)
end

local function controlsHeight()
	local hud = playerGui:FindFirstChild("SandboxHud")
	local c = hud and hud:FindFirstChild("Controls", true)
	return (c and c.Visible) and c.AbsoluteSize.Y or 0
end
-- (2026-11-14, owner: "move the left side ui up so its aligned vertically") the left rail used to start at 36% of the
-- screen and ran down to just above the key strip (5 tiles once MAPS came in). It is now centred on the screen, unless
-- that would push the controls hint (SandboxClient's Controls, which sits right above the rail) under the topbar or the
-- rail onto the key strip. Its top in real px is published as PlayerGui attribute LeftRailTop; SandboxClient follows it.
local function placeLeft(vp)
	local inset = GuiService:GetGuiInset().Y
	local h = left.AbsoluteSize.Y
	local top = math.floor((vp.Y - h) / 2 + 0.5)
	top = math.max(top, inset + 8 + controlsHeight() + 10)
	top = math.min(top, vp.Y - (tonumber(playerGui:GetAttribute("KeyRowLift")) or 0) - 10 - h)
	left.Position = UDim2.new(0, 12, 0, top)
	if playerGui:GetAttribute("LeftRailTop") ~= top then
		playerGui:SetAttribute("LeftRailTop", top)
	end
end
local function place()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	T = math.clamp(math.floor(vp.Y * 0.105), 58, 104)
	left.Size = UDim2.fromOffset(T, 0)
	right.Size = UDim2.fromOffset(0, T)
	-- (2026-11-15, owner: "move the settings button down a bit, the fps display is overlapping it") the rail never starts
	-- above inset + 52: SettingsMenu's FPS line (64-84 px) and SettingsHud's PING / region line (86-104 px) sit up there
	local inset = GuiService:GetGuiInset().Y
	local y = tonumber(playerGui:GetAttribute("HudTopRightY")) or (inset + 10)
	right.Position = UDim2.new(1, -12, 0, math.max(y, inset + 52))
	placeLeft(vp)
	for pill, info in pairs(tiles) do
		if pill.Parent then
			layout(pill, info)
		else
			tiles[pill] = nil
		end
	end
end
place()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
playerGui:GetAttributeChangedSignal("HudTopRightY"):Connect(place)
-- the rail grows as tiles arrive and the controls hint changes with the weapon: re-centre on either
local function replaceLeft()
	local cam = workspace.CurrentCamera
	placeLeft(cam and cam.ViewportSize or Vector2.new(1280, 720))
end
left:GetPropertyChangedSignal("AbsoluteSize"):Connect(replaceLeft)
playerGui:GetAttributeChangedSignal("KeyRowLift"):Connect(replaceLeft)
task.spawn(function()
	local hud = playerGui:WaitForChild("SandboxHud", 20)
	local c = hud and hud:FindFirstChild("Controls", true)
	if c then
		c:GetPropertyChangedSignal("AbsoluteSize"):Connect(replaceLeft)
		c:GetPropertyChangedSignal("Visible"):Connect(replaceLeft)
	end
	replaceLeft()
end)

-- the pills arrive over the first seconds (four of the scripts wait for the strip, then add theirs), and each one
-- finishes drawing its icon a moment after it parents the button
strip.ChildAdded:Connect(function(ch)
	task.delay(0.4, adopt, ch)
end)
task.wait(0.6)
for _, ch in ipairs(strip:GetChildren()) do
	adopt(ch)
end
