--!nocheck
-- StarterPlayerScripts.SettingsMenu (2026-11-09, shop expansion): the SETTINGS panel. A gear pill at the end of the
-- top strip (CharacterSelect.TopStrip) opens it; so does HudShared.OpenPanel("settings", itemId) (the shop's MANAGE).
-- Everything is saved to the player's profile by ShopService.Ext.Settings (ShopRequest "settings", debounced) and
-- comes back as the player attribute Settings (JSON), so it follows them to any server / device.
--   GENERAL  damage numbers, screen shake, flashing lights
--   AUDIO    sound-effect / taunt volume (SoundService.SettingsSFX / SettingsTaunts groups), other players' custom
--            sounds, and the Custom Kill Sound perk's kill / death audio ids
--   GRAPHICS FPS counter, shadows, debris (flying rubble / shards hidden locally)
--   FUN      Fun Filters perk: weather (rain / snow / petals), time (night / sunset / dark), look (bloom / retro /
--            mono), upside-down camera - only this player's screen
--   OUTFIT   Ultimate Outfit perk: pick one of the player's saved Roblox outfits (PerkUltOutfit wears it in a form)
--   CONTROLS (2026-11-11, owner: "add shiftlock (camera view)" / "have the option to have keybinds") the SHIFT LOCK
--            switch (the LocalPlayer attribute OptShiftLock, shared with StarterPlayerScripts.ShiftLock; not saved,
--            off every join) and a key chip for every HudShared.Keybinds action: click it, press the new key (Esc
--            cancels; a key another action uses swaps the two; movement / camera / chat keys are refused with the
--            reason), RESET ALL. Binds save as Settings.keys (Keybinds.serialize) through the same debounced save, and
--            the Keybinds module loads them back from the Settings attribute on every device.
-- (2026-11-11, "wiki extras") more rows from the reference game's settings list: GENERAL combo counter, blood, camera
-- follow, server region, hide my kills, GAME INFO (a guide page); CONTROLS UI size, menu size, sensitivity, toolbar
-- offset ("range" sliders); AUDIO music, voice & emotes, text-to-speech, ragdoll sounds; GRAPHICS destruction smoke,
-- heavy effects; FUN jolly (snow + fog), invert, bloodbath, headcam. EVERY setting is also mirrored to a LOCAL player
-- attribute Opt_<key> (Opt_blood, Opt_uiScale, ...) that StarterPlayerScripts.SettingsEffects and the HUD scripts
-- (MoveDock, Dash, GadgetBar, ComboCounter, CharacterSelect, TauntMenu) read.
-- How the switches reach the game: this script sets LOCAL player attributes OptNoShake / OptNoFlash / OptNoDamage,
-- and the kits' shake / flash functions and DamageNumbersClient return early while they are set.
-- It also plays HudShared.CustomSound (kill / death sounds the server sends for KillSound perk owners).
-- Studio: script.Control:Invoke("open", tab) / ("close") / ("set", key, value) / ("state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local PerkCatalog = require(shared:WaitForChild("PerkCatalog"))
local Keybinds = require(shared:WaitForChild("Keybinds"))
local ShopRequest = shared:WaitForChild("ShopRequest", 30)
local OpenPanel = shared:WaitForChild("OpenPanel", 30)
local CustomSound = shared:WaitForChild("CustomSound", 30)

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local RED = Color3.fromRGB(255, 80, 110)
local GREEN = Color3.fromRGB(90, 230, 140)
local DIM = Color3.fromRGB(170, 170, 195)
local OFFC = Color3.fromRGB(62, 62, 82)
local C0, C1 = Color3.fromRGB(90, 200, 255), Color3.fromRGB(150, 90, 255)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local PILL_H = 40

---------------------------------------------------------------------------------------------------------------------
-- STATE: the same keys / defaults as ShopService.Ext.Settings
local DEFAULTS = {
	damage = true, shake = true, flash = true,
	sfx = 1, music = 1, taunts = 1, custom = true, killId = 0, deathId = 0,
	fps = false, shadows = true, debris = true,
	weather = "", time = "", look = "", flip = false,
	outfit = 0,
	keys = "", -- (2026-11-11) rebound keys, HudShared.Keybinds.serialize() - the CONTROLS tab
	-- (2026-11-11, wiki extras) - same keys / defaults as ShopService.Ext.Settings
	combo = true, camFollow = false, region = false, hideKills = false, blood = true,
	uiScale = 1, menuScale = 1, sens = 1, toolbar = 0,
	voice = 1, tts = false, ragdollSfx = true,
	smoke = true, heavyFx = true,
	invert = false, bloodbath = false, headcam = false,
	npcChat = true, -- (2026-11-15) speech bubbles over the sandbox's NPCs (SandboxWorld reads Opt_npcChat)
}
local cur = table.clone(DEFAULTS)
local pending = {} -- changed here, not confirmed by the server yet

local function perk(id)
	return player:GetAttribute("Perk_" .. id) == true
end
local function fmtId(n)
	return string.format("%d", tonumber(n) or 0)
end

-- sound groups every sound is routed through (volumes are multipliers 0..2)
local function group(name)
	local g = SoundService:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
	end
	return g
end
local SFX = group("SettingsSFX")
local TAUNTS = group("SettingsTaunts") -- the taunt menu puts its sounds here

---------------------------------------------------------------------------------------------------------------------
-- UI helpers (the shop's look)
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
local function tween(o, t, props)
	local tw = TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local gui = new("ScreenGui", { Name = "SettingsMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

-- FPS counter (GRAPHICS > SHOW FPS)
local fpsLabel = inkText(label(gui, { Name = "FPS", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 64),
	Size = UDim2.fromOffset(90, 20), Text = "-- FPS", TextXAlignment = Enum.TextXAlignment.Right, Visible = false }))

---------------------------------------------------------------------------------------------------------------------
-- APPLYING the settings
local origShadows = Lighting.GlobalShadows
local fx = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local WEATHER = {
	rain = { rate = 520, life = 1, speed = 85, size = 0.16, squash = 2.6, c0 = Color3.fromRGB(200, 215, 255), c1 = Color3.fromRGB(160, 180, 230),
		trans = 0.45, spread = 3, parallel = true },
	snow = { rate = 220, life = 7, speed = 9, size = 0.32, squash = 0, c0 = WHITE, c1 = Color3.fromRGB(225, 235, 255), trans = 0.1, spread = 25,
		wind = Vector3.new(1.5, 0, 0.8) },
	petals = { rate = 70, life = 8, speed = 6, size = 0.42, squash = 0.7, c0 = Color3.fromRGB(255, 165, 200), c1 = Color3.fromRGB(255, 215, 232),
		trans = 0.05, spread = 30, spin = true, wind = Vector3.new(3, 0, 1.5) },
	-- (2026-11-11) JOLLY: heavier snow and a winter fog
	jolly = { rate = 300, life = 8, speed = 7, size = 0.38, squash = 0, c0 = WHITE, c1 = Color3.fromRGB(230, 240, 255), trans = 0.05, spread = 30,
		wind = Vector3.new(1, 0, 0.5), fog = true },
}
local INVERT = { b = 0, c = -2, s = 0, t = WHITE } -- (2026-11-11) FUN > INVERT: contrast -2 mirrors every colour
local TIME = {
	night = { b = -0.16, c = 0.1, s = -0.25, t = Color3.fromRGB(150, 170, 255) },
	sunset = { b = 0.02, c = 0.08, s = 0.15, t = Color3.fromRGB(255, 190, 150) },
	dark = { b = -0.3, c = 0.2, s = -0.45, t = Color3.fromRGB(200, 200, 230) },
}
local LOOK = {
	retro = { b = 0.03, c = 0.25, s = -0.35, t = Color3.fromRGB(255, 230, 190) },
	mono = { b = 0, c = 0.15, s = -1, t = WHITE },
}

local function clearFx(key)
	if fx[key] then
		fx[key]:Destroy()
		fx[key] = nil
	end
end

local function setWeather(kind)
	if fx.weatherKind == kind then
		return
	end
	clearFx("weather")
	clearFx("fogMade")
	if fx.fogAtm then -- (jolly) give the city its own fog back
		pcall(function()
			fx.fogAtm.Parent = Lighting
		end)
		fx.fogAtm = nil
	end
	fx.weatherKind = kind
	local w = WEATHER[kind]
	if not w then
		return
	end
	if w.fog then
		-- the server's day / night cycle keeps writing the city's Atmosphere, so it is set aside on THIS client (moved
		-- under ReplicatedStorage locally) and a denser local copy takes its place until the weather changes
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		local made
		if atm then
			made = atm:Clone()
			fx.fogAtm = atm
			atm.Parent = ReplicatedStorage
		else
			made = Instance.new("Atmosphere")
		end
		made.Name = "SettingsFog"
		made.Density = math.max(made.Density, 0.45)
		made.Haze = math.max(made.Haze, 2.2)
		made.Color = Color3.fromRGB(215, 225, 240)
		made.Parent = Lighting
		fx.fogMade = made
	end
	local part = new("Part", { Name = "SettingsWeather", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		CastShadow = false, Transparency = 1, Size = Vector3.new(150, 1, 150) })
	local e = new("ParticleEmitter", {
		Texture = SMOKE, Rate = w.rate, Lifetime = NumberRange.new(w.life * 0.8, w.life), Speed = NumberRange.new(w.speed * 0.85, w.speed),
		EmissionDirection = Enum.NormalId.Bottom, Shape = Enum.ParticleEmitterShape.Box, Size = NumberSequence.new(w.size),
		Squash = NumberSequence.new(w.squash), Color = ColorSequence.new(w.c0, w.c1), LightInfluence = 0.6,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, w.trans),
			NumberSequenceKeypoint.new(0.9, w.trans), NumberSequenceKeypoint.new(1, 1) }),
		SpreadAngle = Vector2.new(w.spread, w.spread), Acceleration = w.wind or Vector3.zero,
	}, part)
	if w.spin then
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-120, 120)
	end
	if w.parallel then
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
	end
	part.Parent = workspace.CurrentCamera
	fx.weather = part
end

local function setCC(key, spec, name)
	if not spec then
		clearFx(key)
		return
	end
	local cc = fx[key]
	if not cc then
		cc = new("ColorCorrectionEffect", { Name = name }, Lighting)
		fx[key] = cc
	end
	cc.Brightness, cc.Contrast, cc.Saturation, cc.TintColor = spec.b, spec.c, spec.s, spec.t
end

local function setBloom(on)
	if on and not fx.bloom then
		fx.bloom = new("BloomEffect", { Name = "SettingsBloom", Intensity = 1.6, Size = 36, Threshold = 0.75 }, Lighting)
	elseif not on then
		clearFx("bloom")
	end
end

-- upside-down: the camera is rolled 180 degrees after every camera script ran, and un-rolled first thing next frame
-- (only if nothing rewrote it) so camera code that builds on the last CFrame never sees the roll
local flipOn, flipped, flippedCF = false, nil, nil
RunService:BindToRenderStep("SettingsUnflip", Enum.RenderPriority.First.Value, function()
	local cam = workspace.CurrentCamera
	if flipped and cam and cam.CFrame == flippedCF then
		cam.CFrame = flipped
	end
	flipped, flippedCF = nil, nil
end)
RunService:BindToRenderStep("SettingsFlip", Enum.RenderPriority.Camera.Value + 20, function()
	local cam = workspace.CurrentCamera
	if flipOn and cam then
		flipped = cam.CFrame
		cam.CFrame = flipped * CFrame.Angles(0, 0, math.pi)
		flippedCF = cam.CFrame
	end
end)

-- debris: rubble / shards / chunks hidden on this screen only
local DEBRIS_FOLDERS = { CityDebris = true, KitDebris = true, Shards = true }
local DEBRIS_NAMES = { Rubble = true, Shard = true, OFADebris = true, VoidShard = true, SilverShard = true }
local debrisOff = false
local hiddenDebris = setmetatable({}, { __mode = "k" })
local function isDebris(d)
	if not d:IsA("BasePart") then
		return false
	end
	if DEBRIS_NAMES[d.Name] then
		return true
	end
	local p = d.Parent
	for _ = 1, 4 do
		if not p or p == workspace then
			return false
		end
		if DEBRIS_FOLDERS[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end
local function hide(d)
	d.LocalTransparencyModifier = 1
	hiddenDebris[d] = true
end
local function setDebris(off)
	if off == debrisOff then
		return
	end
	debrisOff = off
	if off then
		for _, f in ipairs(workspace:GetDescendants()) do
			if DEBRIS_FOLDERS[f.Name] and f:IsA("Folder") then
				for _, d in ipairs(f:GetDescendants()) do
					if d:IsA("BasePart") then
						hide(d)
					end
				end
			end
		end
	else
		for d in pairs(hiddenDebris) do
			if d.Parent then
				d.LocalTransparencyModifier = 0
			end
		end
		table.clear(hiddenDebris)
	end
end

-- every sound goes through the SFX group (unless something already gave it a group)
local function routeSound(d)
	if d:IsA("Sound") and d.SoundGroup == nil then
		d.SoundGroup = SFX
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Sound") then
		routeSound(d)
	elseif debrisOff and isDebris(d) then
		hide(d)
	end
end)
playerGui.DescendantAdded:Connect(routeSound)
SoundService.DescendantAdded:Connect(routeSound)
task.spawn(function()
	for _, root in ipairs({ workspace, playerGui, SoundService }) do
		local all = root:GetDescendants()
		for i, d in ipairs(all) do
			routeSound(d)
			if i % 3000 == 0 then
				task.wait()
			end
		end
	end
end)

local function apply()
	player:SetAttribute("OptNoShake", (not cur.shake) or nil)
	player:SetAttribute("OptNoFlash", (not cur.flash) or nil)
	player:SetAttribute("OptNoDamage", (not cur.damage) or nil)
	SFX.Volume = cur.sfx
	TAUNTS.Volume = cur.taunts
	Lighting.GlobalShadows = cur.shadows and origShadows or false
	setDebris(not cur.debris)
	fpsLabel.Visible = cur.fps
	local fun = perk("FunFilters")
	setWeather(fun and cur.weather or "")
	setCC("time", fun and TIME[cur.time] or nil, "SettingsTime")
	local look = fun and cur.look or ""
	setCC("look", LOOK[look], "SettingsLook")
	setBloom(look == "bloom")
	flipOn = fun and cur.flip == true
	setCC("invert", (fun and cur.invert == true) and INVERT or nil, "SettingsInvert")
	-- (2026-11-11) every setting mirrored for SettingsEffects / the HUD scripts
	for k, v in pairs(cur) do
		player:SetAttribute("Opt_" .. k, v)
	end
end

local frames, fpsT0 = 0, os.clock()
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if fx.weather and cam then
		fx.weather.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 38, 0))
	end

	if cur.fps then
		frames += 1
		local now = os.clock()
		if now - fpsT0 >= 0.5 then
			fpsLabel.Text = math.floor(frames / (now - fpsT0) + 0.5) .. " FPS"
			frames, fpsT0 = 0, now
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- THE PANEL
local refreshers, pageConns = {}, {}
local function refresh()
	for _, f in ipairs(refreshers) do
		pcall(f)
	end
end

-- root (shown / hidden) > shade (a full-screen button that closes) + panel ON TOP of it as a sibling: a panel inside
-- the shade let taps on the panel's non-active parts fall through to the shade and close it
local root = new("Frame", { Name = "SettingsRoot", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local shade = new("TextButton", { Name = "SettingsShade", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 }, root)
local W, H = 600, 450
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
player:GetAttributeChangedSignal("Opt_menuScale"):Connect(fit) -- CONTROLS > MENU SIZE

local hd = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
corner(hd, 16)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hd)
local hsq = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hsq)
inkText(label(hd, { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(240, 38), Text = "SETTINGS",
	TextXAlignment = Enum.TextXAlignment.Left }), 2.5)
local statusLbl = inkText(label(hd, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.fromOffset(260, 18),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right }), 1.5)
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(36, 36), AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
corner(closeBtn)
stroke(closeBtn, INK, 2)
label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", TextColor3 = INK })

local statusToken = 0
local function status(text, color)
	statusToken += 1
	local my = statusToken
	statusLbl.Text = text
	statusLbl.TextColor3 = color or WHITE
	task.delay(2.5, function()
		if statusToken == my then
			statusLbl.Text = ""
		end
	end)
end

local TABS = {
	{ id = "general", name = "GENERAL" },
	{ id = "controls", name = "CONTROLS" },
	{ id = "audio", name = "AUDIO" },
	{ id = "graphics", name = "GRAPHICS" },
	{ id = "fun", name = "FUN", perk = "FunFilters" },
	{ id = "outfit", name = "OUTFIT", perk = "UltOutfit" },
}
local tabBar = new("Frame", { Position = UDim2.fromOffset(14, 68), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)
local content = new("ScrollingFrame", { Name = "Content", Position = UDim2.fromOffset(14, 112), Size = UDim2.new(1, -20, 1, -124),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = WHITE, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }, content)

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function section(text)
	return label(content, { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 18), Text = text, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kits.FONT_LABEL })
end

local function row(title, sub, h, titleW)
	h = h or 52
	local r = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = WHITE, BackgroundTransparency = 0.94,
		BorderSizePixel = 0 }, content)
	corner(r, 10)
	local tw = titleW or 0.5
	inkText(label(r, { Name = "Title", Position = UDim2.fromOffset(14, sub and 8 or math.floor((h - 22) / 2)), Size = UDim2.new(tw, -14, 0, sub and 19 or 22),
		Text = title, TextXAlignment = Enum.TextXAlignment.Left }))
	if sub then
		label(r, { Name = "Sub", Position = UDim2.fromOffset(14, 29), Size = UDim2.new(tw, -14, 0, h - 37), Text = sub, TextColor3 = DIM,
			FontFace = Kits.FONT_LABEL, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	end
	return r
end

local function button(parent, text, w, color, textColor)
	local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(w, 30),
		AutoButtonColor = false, Text = "", BackgroundColor3 = color or WHITE, BorderSizePixel = 0 }, parent)
	corner(b, 8)
	stroke(b, INK, 1.5)
	local t = label(b, { Name = "Label", Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), Text = text, TextColor3 = textColor or INK })
	return b, t
end

local set -- forward

-- get / flip (optional, 2026-11-11): a switch for state that is not a saved setting (SHIFT LOCK's OptShiftLock)
local function toggle(r, key, get, flip)
	r.Name = key -- rows are named after their setting (tests click them by path)
	local b = new("TextButton", { Name = "Toggle", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(68, 30),
		AutoButtonColor = false, Text = "", BackgroundColor3 = OFFC, BorderSizePixel = 0 }, r)
	corner(b)
	stroke(b, INK, 1.5)
	local txt = label(b, { Size = UDim2.new(0, 30, 0, 14), Text = "", TextColor3 = WHITE })
	local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, b)
	corner(knob)
	stroke(knob, INK, 1.5)
	local function show()
		local on
		if get then
			on = get() == true
		else
			on = cur[key] == true
		end
		tween(b, 0.12, { BackgroundColor3 = on and GREEN or OFFC })
		tween(knob, 0.12, { Position = on and UDim2.new(1, -27, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
		txt.Text = on and "ON" or "OFF"
		txt.TextColor3 = on and INK or WHITE
		txt.Position = on and UDim2.new(0, 8, 0.5, -7) or UDim2.new(1, -36, 0.5, -7)
	end
	b.Activated:Connect(function()
		if flip then
			flip()
		else
			set(key, not cur[key])
		end
	end)
	table.insert(refreshers, show)
	show()
	return b
end

-- rng (2026-11-11) = { min, max, step, format(v) } for non-volume sliders; volumes are 0..200% in 5% steps
local function pct(v)
	return math.floor(v * 100 + 0.5) .. "%"
end
local VOLUME = { 0, 2, 0.05, pct }
local function slider(r, key, rng)
	r.Name = key
	rng = rng or VOLUME
	local lo, hi, step, fmt = rng[1], rng[2], rng[3], rng[4]
	local track = new("Frame", { Name = "Slider", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -78, 0.5, 0), Size = UDim2.fromOffset(190, 10),
		BackgroundColor3 = OFFC, BorderSizePixel = 0 }, r)
	corner(track)
	local fill = new("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C0, BorderSizePixel = 0 }, track)
	corner(fill)
	local knob = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
	corner(knob)
	stroke(knob, INK, 1.5)
	local val = inkText(label(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(56, 18),
		Text = "", TextXAlignment = Enum.TextXAlignment.Right }))
	local hit = new("TextButton", { Name = "Hit", BackgroundTransparency = 1, Text = "", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -12, 0.5, 0),
		Size = UDim2.new(1, 24, 0, 38) }, track)
	local function show()
		local v = tonumber(cur[key]) or DEFAULTS[key] or lo
		local a = math.clamp((v - lo) / (hi - lo), 0, 1)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		val.Text = fmt(v)
	end
	local dragging = nil
	local function fromX(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local v = lo + a * (hi - lo)
		cur[key] = math.floor((v - lo) / step + 0.5) * step + lo
		apply()
		show()
	end
	hit.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = io
			fromX(io.Position.X)
		end
	end)
	table.insert(pageConns, UserInputService.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			fromX(io.Position.X)
		end
	end))
	table.insert(pageConns, UserInputService.InputEnded:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch) then
			dragging = nil
			local v = cur[key]
			cur[key] = nil -- force set() to record it
			set(key, v)
		end
	end))
	table.insert(refreshers, show)
	show()
	return track
end

local function chips(r, key, opts)
	r.Name = key
	local holder = new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(#opts * 66 + (#opts - 1) * 6, 30), BackgroundTransparency = 1 }, r)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	local list = {}
	for i, o in ipairs(opts) do
		local b = new("TextButton", { Name = o[1] == "" and "Off" or o[1], LayoutOrder = i, Size = UDim2.fromOffset(66, 30), AutoButtonColor = false,
			Text = "", BackgroundColor3 = OFFC, BorderSizePixel = 0 }, holder)
		corner(b, 8)
		stroke(b, INK, 1.5)
		local t = label(b, { Size = UDim2.new(1, -10, 1, -12), Position = UDim2.fromOffset(5, 6), Text = o[2] })
		b.Activated:Connect(function()
			set(key, o[1])
		end)
		list[i] = { b = b, t = t, v = o[1] }
	end
	local function show()
		for _, c in ipairs(list) do
			local on = cur[key] == c.v
			c.b.BackgroundColor3 = on and C0 or OFFC
			c.t.TextColor3 = on and INK or WHITE
		end
	end
	table.insert(refreshers, show)
	show()
	return holder
end

-- plays an audio id once on this screen (TEST buttons); tells the player when Roblox won't load it
local function testSound(id)
	id = tonumber(id) or 0
	if id <= 0 then
		status("TYPE AN AUDIO ID FIRST", RED)
		return
	end
	local s = new("Sound", { SoundId = "rbxassetid://" .. fmtId(id), Volume = 1, SoundGroup = SFX }, SoundService)
	s:Play()
	Debris:AddItem(s, 6)
	task.delay(3, function()
		if s.Parent and not s.IsLoaded then
			status("THAT SOUND WON'T LOAD - TRY ANOTHER ID", RED)
		end
	end)
end

local function idRow(key, title, sub)
	local r = row(title, sub, 54, 0.42)
	r.Name = key
	local box = new("TextBox", { Name = "Id", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -88, 0.5, 0), Size = UDim2.fromOffset(160, 32),
		BackgroundColor3 = Color3.fromRGB(8, 8, 14), BorderSizePixel = 0, Text = "", PlaceholderText = "AUDIO ID", ClearTextOnFocus = false,
		TextColor3 = WHITE, PlaceholderColor3 = DIM, FontFace = Kits.FONT_LABEL, TextSize = 15 }, r)
	corner(box, 8)
	stroke(box, WHITE, 1, 0.6)
	local function show()
		if not box:IsFocused() then
			box.Text = (cur[key] or 0) > 0 and fmtId(cur[key]) or ""
		end
	end
	box.FocusLost:Connect(function()
		local n = tonumber(box.Text:match("%d+") or "") or 0
		if n > 1e15 then
			n = 0
		end
		set(key, n)
		show()
	end)
	local test = button(r, "TEST", 64, C0)
	test.Activated:Connect(function()
		testSound(tonumber(box.Text:match("%d+") or "") or cur[key])
	end)
	table.insert(refreshers, show)
	show()
end

-- a locked perk: what it does and a buy button (the shop's receipt handler grants it; the panel rebuilds on Perk_)
local function lockCard(perkId, extra)
	local it = PerkCatalog.byId[perkId]
	if not it then
		return
	end
	local r = row(string.upper(it.name), string.upper(it.desc .. (extra and (" " .. extra) or "")), 74, 0.62)
	r.Name = "Lock_" .. perkId
	r.BackgroundColor3 = it.color or GOLD
	r.BackgroundTransparency = 0.86
	stroke(r, it.color or GOLD, 1.5, 0.3)
	local live = (tonumber(it.product) or 0) > 0
	local b = button(r, live and ("R$ " .. it.price .. "  BUY") or "COMING SOON", 150, live and GOLD or OFFC, live and INK or WHITE)
	b.Name = "Buy"
	b.Activated:Connect(function()
		if live then
			pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, it.product)
		else
			status("COMING SOON", GOLD)
		end
	end)
	return r
end

local function note(text)
	local t = label(content, { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 30), Text = text, TextColor3 = DIM, FontFace = Kits.FONT_LABEL,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
	new("UITextSizeConstraint", { MaxTextSize = 14 }, t)
	return t
end

-- (2026-11-11) a paragraph of any length (the GAME INFO page)
local function para(text)
	return label(content, { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text,
		TextColor3 = Color3.fromRGB(225, 225, 240), FontFace = Kits.FONT_LABEL, TextScaled = false, TextSize = 15, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
end

-- OUTFITS (Ultimate Outfit): the player's saved Roblox outfits, read after they allow inventory access
local outfits = nil -- { {id, name} }
local outfitBusy = false
local buildPage -- forward
local curTab = "general"
local function loadOutfits()
	if outfitBusy then
		return
	end
	outfitBusy = true -- (the panel's visibility is root.Visible)
	status("ASKING ROBLOX...", WHITE)
	local result = nil
	local conn = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(r)
		result = r
	end)
	local ok, err = pcall(AvatarEditorService.PromptAllowInventoryReadAccess, AvatarEditorService)
	local t0 = os.clock()
	while ok and result == nil and os.clock() - t0 < 90 do
		task.wait(0.1)
	end
	conn:Disconnect()
	if not ok or result ~= Enum.AvatarPromptResult.Success then
		outfitBusy = false
		status(ok and "ALLOW ACCESS TO PICK AN OUTFIT" or "OUTFITS UNAVAILABLE RIGHT NOW", RED)
		if not ok then
			warn("[SettingsMenu] outfits: " .. tostring(err))
		end
		return
	end
	local list = {}
	local ok2, err2 = pcall(function()
		local pages = AvatarEditorService:GetOutfits(Enum.OutfitSource.Created)
		while #list < 60 do
			for _, o in ipairs(pages:GetCurrentPage()) do
				table.insert(list, { id = o.Id, name = o.Name })
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	outfitBusy = false
	if not ok2 then
		warn("[SettingsMenu] GetOutfits: " .. tostring(err2))
		status("COULDN'T READ YOUR OUTFITS", RED)
		return
	end
	outfits = list
	status(#list .. " OUTFITS", GREEN)
	if root.Visible and curTab == "outfit" then
		buildPage("outfit")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- PAGES
local PAGES = {}
-- (2026-11-15, owner: "make the settings more relevant to the game") GENERAL / AUDIO / GRAPHICS / GAME INFO reworded for
-- the ragdoll sandbox (NPCs, machines, the two maps, wounds); the dead TAUNTS + MUSIC sliders are gone (no taunt button,
-- no music); new: REPLAY INTRO (sets the player attribute OnboardReplay - StarterPlayerScripts.Onboarding runs the tour
-- again and this panel closes) and NPC CHATTER (Opt_npcChat - SandboxWorld skips the speech bubbles).
PAGES.general = function()
	section("HELP")
	local ir = row("GAME INFO", "MAPS, FIGHTERS, NPCS, MACHINES, SPAWNING AND THE SHOP", 54, 0.62)
	ir.Name = "GameInfo"
	local ib = button(ir, "OPEN", 90, C0)
	ib.Name = "Open"
	ib.Activated:Connect(function()
		buildPage("info")
	end)
	local rr = row("REPLAY INTRO", "THE QUICK TOUR OF THE FIGHTER AND MAP BUTTONS", 54, 0.62)
	rr.Name = "ReplayIntro"
	local rb = button(rr, "REPLAY", 90, C0)
	rb.Name = "Replay"
	rb.Activated:Connect(function()
		player:SetAttribute("OnboardReplay", os.clock())
	end)
	section("SCREEN")
	toggle(row("DAMAGE NUMBERS", "THE NUMBERS THAT POP OFF EVERY NPC AND FIGHTER YOU HIT"), "damage")
	toggle(row("COMBO COUNTER", "YOUR HIT COUNT AND COMBO RANK, RIGHT SIDE OF THE SCREEN"), "combo")
	toggle(row("SCREEN SHAKE", "CAMERA SHAKE FROM HITS, BLASTS, MACHINES AND ULTIMATES"), "shake")
	toggle(row("FLASHING LIGHTS", "WHITE FLASHES AND IMPACT FRAMES - TURN OFF IF FLASHES BOTHER YOU"), "flash")
	toggle(row("BLOOD", "CARTOON BLOOD FROM HITS, WOUNDS AND KOS"), "blood")
	section("NPCS")
	toggle(row("NPC CHATTER", "SPEECH BUBBLES OVER THE NPCS WHEN THEY TALK, YELL AND REACT"), "npcChat")
	section("CAMERA & HUD")
	toggle(row("CAMERA FOLLOW", "THE CAMERA FOLLOWS YOUR HEAD INSTEAD OF YOUR BODY"), "camFollow")
	toggle(row("SERVER REGION", "WHERE THIS SERVER IS AND YOUR PING, TOP RIGHT"), "region")
	toggle(row("HIDE MY KILLS", "EVERYONE SEES - INSTEAD OF YOUR KILLS ON THE PLAYER LIST"), "hideKills")
	note("SETTINGS ARE SAVED TO YOUR ACCOUNT AND FOLLOW YOU TO EVERY SERVER.")
end

-- (2026-11-11) GAME INFO: opened from GENERAL; the keys shown follow the player's own binds
PAGES.info = function()
	local function k(code)
		return Keybinds.label(code)
	end
	local K = Enum.KeyCode
	local back = row("GAME INFO", "EVERYTHING IN ONE PLACE", 54, 0.62)
	back.Name = "Info"
	local bb = button(back, "BACK", 90, OFFC, WHITE)
	bb.Name = "Back"
	bb.Activated:Connect(function()
		buildPage("general")
	end)
	section("THE MAPS")
	para("You start in THE RUINS, a walled arena where columns, trees and props break apart under your moves (the outer walls hold). "
		.. "The MAPS button on the left takes you to THE SANDBOX, the big open field full of machines, and back again.")
	section("FIGHTERS")
	para("Pick a fighter from the button at the top left. Click (or tap) to punch; " .. k(K.Q) .. " / " .. k(K.E) .. " / " .. k(K.R)
		.. " are your fighter's moves and " .. k(K.G) .. " is the ultimate. Every move leaves its own wounds - a Hollow Purple tears a huge hole, "
		.. "a Rasenshuriken leaves dozens of small ones. SHIFT LOCK (" .. k(K.LeftShift) .. ") keeps the camera behind you.")
	section("NPCS")
	para("The NPCs walk around, chat and react to what they see: hurt one in front of the others and they panic and run. "
		.. "Knock them down and they ragdoll; wounded ones stay down and are replaced after a while.")
	section("SPAWN, GRAB & THROW")
	para(k(K.V) .. " spawns an NPC in front of you. " .. k(K.One) .. " / " .. k(K.Two) .. " switch between your POWERS and GRAB; "
		.. "grab a body and press " .. k(K.F) .. " to throw it - into a machine, a wall or another NPC.")
	section("MACHINES")
	para("The Sandbox is full of machines - the train, crushers, the wrecking ball, saws, the blender, cannons and more. "
		.. "Press their buttons, or feed them NPCs and watch.")
	section("SLIDERS, SHOP & QUESTS")
	para("SLIDERS change your run speed, jump, gravity and more. The SHOP sells fighters, perks and effects for Yen; "
		.. "QUESTS (the scroll button) give daily and weekly jobs that pay Yen. Rebind any key in CONTROLS.")
end
PAGES.audio = function()
	section("VOLUME")
	slider(row("SOUND EFFECTS", "HITS, ABILITIES, MACHINES AND EXPLOSIONS"), "sfx")
	slider(row("VOICE & EMOTES", "EMOTE SOUNDS AND SPOKEN CHAT"), "voice")
	toggle(row("CUSTOM SOUNDS", "OTHER PLAYERS' KILL AND DEATH SOUNDS"), "custom")
	toggle(row("TEXT TO SPEECH", "NEARBY PLAYERS' CHAT IS READ ALOUD - A RANDOM VOICE EACH LIFE"), "tts")
	toggle(row("RAGDOLL SOUNDS", "THUDS WHEN RAGDOLLED NPCS AND FIGHTERS HIT THINGS"), "ragdollSfx")
	section("CUSTOM KILL SOUND")
	if perk("KillSound") then
		idRow("killId", "KILL SOUND", "PLAYS ON ANYONE YOU KO")
		idRow("deathId", "DEATH SOUND", "PLAYS WHEN YOU GET KO'D")
		note("USE ANY PUBLIC AUDIO FROM THE CREATOR STORE (AUDIO). EMPTY = NONE.")
	else
		lockCard("KillSound")
	end
end
PAGES.graphics = function()
	section("PERFORMANCE")
	toggle(row("SHOW FPS", "FRAMES PER SECOND, TOP RIGHT"), "fps")
	toggle(row("SHADOWS", "TURN OFF FOR MORE FPS"), "shadows")
	toggle(row("PHYSICS DEBRIS", "FLYING RUBBLE, ROCKS AND SHARDS FROM BROKEN RUINS AND PROPS - TURN OFF FOR MORE FPS"), "debris")
	toggle(row("DESTRUCTION SMOKE", "DUST PUFFS WHEN COLUMNS, TREES AND PROPS BREAK"), "smoke")
	toggle(row("HEAVY EFFECTS", "OFF = FAR FEWER PARTICLES FROM MOVES - TURN OFF FOR MORE FPS"), "heavyFx")
end
PAGES.fun = function()
	if not perk("FunFilters") then
		lockCard("FunFilters")
		section("WHAT YOU GET")
		note("WEATHER: RAIN, SNOW, CHERRY PETALS, JOLLY  -  TIME: NIGHT, SUNSET, DARK  -  LOOK: BLOOM, RETRO, BLACK & WHITE  -  INVERT, BLOODBATH, HEADCAM, UPSIDE-DOWN")
		return
	end
	section("FILTERS - ONLY YOU SEE THESE")
	chips(row("WEATHER", nil, 52, 0.3), "weather", { { "", "OFF" }, { "rain", "RAIN" }, { "snow", "SNOW" }, { "petals", "PETALS" }, { "jolly", "JOLLY" } })
	chips(row("TIME", nil, 52, 0.38), "time", { { "", "OFF" }, { "night", "NIGHT" }, { "sunset", "SUNSET" }, { "dark", "DARK" } })
	chips(row("LOOK", nil, 52, 0.38), "look", { { "", "OFF" }, { "bloom", "BLOOM" }, { "retro", "RETRO" }, { "mono", "B & W" } })
	toggle(row("UPSIDE DOWN", "FLIPS YOUR CAMERA"), "flip")
	toggle(row("INVERT", "REVERSES EVERY COLOUR"), "invert")
	toggle(row("BLOODBATH", "BLOOD STAYS FOR MINUTES (NEEDS BLOOD ON)"), "bloodbath")
	toggle(row("HEADCAM", "FIRST PERSON FROM YOUR HEAD - YOUR BODY STAYS VISIBLE"), "headcam")
end
PAGES.outfit = function()
	if not perk("UltOutfit") then
		lockCard("UltOutfit")
		return
	end
	section("ULTIMATE OUTFIT")
	local r = row("WORN IN YOUR ULTIMATE", "", 54, 0.6)
	local sub = r:FindFirstChild("Sub")
	local clear = button(r, "NONE", 80, OFFC, WHITE)
	clear.Name = "None"
	clear.Activated:Connect(function()
		set("outfit", 0)
	end)
	local function showCur()
		local name = nil
		for _, o in ipairs(outfits or {}) do
			if o.id == cur.outfit then
				name = o.name
			end
		end
		sub.Text = cur.outfit > 0 and ("CURRENT: " .. string.upper(name or ("OUTFIT #" .. fmtId(cur.outfit)))) or "CURRENT: NONE"
	end
	table.insert(refreshers, showCur)
	showCur()
	if not outfits then
		local lr = row("YOUR SAVED OUTFITS", "ROBLOX ASKS ONCE IF THE GAME MAY SEE YOUR OUTFITS", 54, 0.6)
		local b = button(lr, "LOAD OUTFITS", 140, C0)
		b.Name = "Load"
		b.Activated:Connect(function()
			task.spawn(loadOutfits)
		end)
	elseif #outfits == 0 then
		note("NO SAVED OUTFITS - MAKE ONE IN THE ROBLOX AVATAR EDITOR (CREATIONS > OUTFITS), THEN REOPEN THIS.")
	else
		local grid = new("Frame", { Name = "Outfits", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1 }, content)
		new("UIGridLayout", { CellSize = UDim2.fromOffset(102, 128), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local cards = {}
		for i, o in ipairs(outfits) do
			local c = new("TextButton", { Name = "Outfit_" .. fmtId(o.id), LayoutOrder = i, AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.92, BorderSizePixel = 0 }, grid)
			corner(c, 10)
			local st = stroke(c, C0, 2, 1)
			new("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(90, 90),
				Image = "rbxthumb://type=Outfit&id=" .. fmtId(o.id) .. "&w=150&h=150" }, c)
			label(c, { Position = UDim2.fromOffset(6, 100), Size = UDim2.new(1, -12, 0, 20), Text = string.upper(o.name or ""), FontFace = Kits.FONT_LABEL })
			c.Activated:Connect(function()
				set("outfit", o.id)
			end)
			cards[o.id] = st
		end
		table.insert(refreshers, function()
			for id, st in pairs(cards) do
				st.Transparency = id == cur.outfit and 0 or 1
			end
		end)
	end
	note("WORN WHILE YOUR ULTIMATE FORM IS ACTIVE: ITS CLOTHES, FACE AND ACCESSORIES. GIANT FORMS KEEP THEIR OWN LOOK.")
	refresh()
end

-- CONTROLS (2026-11-11, owner: "add shiftlock (camera view)" / "have the option to have keybinds"): SHIFT LOCK's
-- switch + a key chip per HudShared.Keybinds action. A clicked chip waits for the next key through a ContextActionService
-- bind on the whole keyboard at a high priority: that catches the press AND marks it game-processed, so the kits'
-- InputBegan handlers (all gpe-guarded) don't also fire a move with it. The LocalPlayer attribute KeybindCapture is set
-- meanwhile too (Dash and ShiftLock ignore keys while it is).
local SHIFT_LOCK = Enum.KeyCode.LeftShift -- the SHIFT LOCK action (Keybinds names actions by their default key)
local CAPTURE_ACTION = "SettingsKeyCapture"
local capture = nil -- { key = the action's default KeyCode, chip, txt } while a chip waits for a key
local function endCapture()
	if not capture then
		return
	end
	capture = nil
	ContextActionService:UnbindAction(CAPTURE_ACTION)
	-- cleared a beat later: the press that ended the wait may reach the InputBegan handlers after this callback
	task.delay(0.15, function()
		if not capture then
			player:SetAttribute("KeybindCapture", nil)
		end
	end)
	refresh()
end
GuiService.MenuOpened:Connect(endCapture) -- Esc can open Roblox's menu before the bind ever sees it

local function refusal(kc)
	local n = kc.Name
	if n == "W" or n == "A" or n == "S" or n == "D" or n == "Space" or n == "Up" or n == "Down" or n == "Left" or n == "Right" then
		return "THAT'S A MOVEMENT KEY"
	elseif n == "I" or n == "O" or n == "Comma" or n == "Period" or n == "PageUp" or n == "PageDown" then
		return "THAT'S A CAMERA KEY"
	elseif n == "Slash" or n == "Return" or n == "KeypadEnter" or n == "Backquote" or n == "Tab" or n == "Backspace" then
		return "THAT'S A CHAT / MENU KEY"
	end
	return "ROBLOX USES THAT KEY"
end

local function startCapture(key, chip, txt)
	if capture and capture.key == key then
		endCapture() -- a second click on the waiting chip cancels
		return
	end
	endCapture()
	local my = { key = key, chip = chip, txt = txt }
	capture = my
	chip.BackgroundColor3 = C0
	txt.Text = "PRESS A KEY..."
	txt.TextColor3 = INK
	player:SetAttribute("KeybindCapture", true)
	ContextActionService:BindActionAtPriority(CAPTURE_ACTION, function(_, state, io)
		if capture ~= my or state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local kc = io.KeyCode
		if kc == Enum.KeyCode.Escape then
			endCapture()
			return Enum.ContextActionResult.Sink
		end
		if kc == Enum.KeyCode.Unknown then
			return Enum.ContextActionResult.Sink
		end
		-- whichever action has that key now swaps onto this one's old key (Keybinds.set does it; the row follows)
		local other = nil
		for _, a in ipairs(Keybinds.ACTIONS) do
			if a.key ~= key and Keybinds.physical(a.key) == kc then
				other = a.name
			end
		end
		if Keybinds.set(key, kc) then
			endCapture()
			set("keys", Keybinds.serialize())
			if other then
				status("SWAPPED WITH " .. other, GOLD)
			end
		else
			-- refused: say why (chip + header) and keep waiting
			chip.BackgroundColor3 = RED
			txt.Text = "CAN'T USE"
			txt.TextColor3 = WHITE
			status(string.upper(kc.Name) .. ": " .. refusal(kc), RED)
			task.delay(0.9, function()
				if capture == my then
					chip.BackgroundColor3 = C0
					txt.Text = "PRESS A KEY..."
					txt.TextColor3 = INK
				end
			end)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.UserInputType.Keyboard)
	task.delay(8, function()
		if capture == my then
			endCapture()
			status("NO KEY PRESSED", DIM)
		end
	end)
end

PAGES.controls = function()
	section("CAMERA")
	local sl = row("SHIFT LOCK", "", 52, 0.62)
	local slSub = sl:FindFirstChild("Sub")
	toggle(sl, "shiftlock", function()
		return player:GetAttribute("OptShiftLock") == true
	end, function()
		player:SetAttribute("OptShiftLock", (player:GetAttribute("OptShiftLock") ~= true) or nil)
	end)
	table.insert(refreshers, function()
		slSub.Text = "CAMERA OVER YOUR SHOULDER, MOUSE LOCKED - " .. Keybinds.label(SHIFT_LOCK) .. " TOGGLES IT"
	end)
	-- (2026-11-11, wiki extras)
	section("SIZE & FEEL")
	slider(row("UI SIZE", "MOVE BAR, GADGETS, COMBO COUNTER"), "uiScale", { 0.6, 1.4, 0.05, pct })
	slider(row("MENU SIZE", "SHOP, INVENTORY, SETTINGS, QUESTS"), "menuScale", { 0.7, 1.3, 0.05, pct })
	slider(row("SENSITIVITY", "CAMERA TURN SPEED, ON TOP OF ROBLOX'S OWN SETTING"), "sens", { 0.2, 3, 0.05, function(v)
		return string.format("%.2fx", v)
	end })
	slider(row("TOOLBAR OFFSET", "SLIDE THE MOVE BAR LEFT OR RIGHT"), "toolbar", { -400, 400, 10, function(v)
		v = math.floor(v + 0.5)
		return v == 0 and "MIDDLE" or ((v > 0 and "+" or "") .. v)
	end })
	section("KEYS - CLICK ONE, THEN PRESS THE NEW KEY")
	for _, a in ipairs(Keybinds.ACTIONS) do
		local r = row(a.name, string.upper(a.hint), 52, 0.62)
		r.Name = "Key_" .. a.key.Name
		local chip, txt = button(r, "", 110, WHITE)
		chip.Name = "Chip"
		chip.Activated:Connect(function()
			startCapture(a.key, chip, txt)
		end)
		table.insert(refreshers, function()
			if capture and capture.key == a.key then
				return
			end
			chip.BackgroundColor3 = Keybinds.physical(a.key) ~= a.key and GOLD or WHITE -- gold = moved off its default
			txt.Text = Keybinds.label(a.key)
			txt.TextColor3 = INK
		end)
	end
	local rr = row("RESET ALL KEYS", "EVERY ACTION BACK TO ITS DEFAULT KEY", 52, 0.62)
	rr.Name = "ResetKeys"
	local rb = button(rr, "RESET ALL", 110, OFFC, WHITE)
	rb.Name = "Reset"
	rb.Activated:Connect(function()
		endCapture()
		Keybinds.reset()
		set("keys", Keybinds.serialize())
		status("KEYS RESET", GREEN)
	end)
	note("A KEY ANOTHER ACTION ALREADY USES SWAPS THE TWO. MOVEMENT, CAMERA AND CHAT KEYS CAN'T BE USED. ESC CANCELS.")
	refresh()
end

local tabButtons = {}
buildPage = function(id)
	endCapture() -- the chips are about to be rebuilt
	curTab = PAGES[id] and id or "general"
	for _, c in ipairs(pageConns) do
		c:Disconnect()
	end
	table.clear(pageConns)
	table.clear(refreshers)
	for _, ch in ipairs(content:GetChildren()) do
		if not (ch:IsA("UIListLayout") or ch:IsA("UIPadding")) then
			ch:Destroy()
		end
	end
	order = 0
	content.CanvasPosition = Vector2.zero
	PAGES[curTab]()
	for tid, t in pairs(tabButtons) do
		local on = tid == curTab
		t.b.BackgroundColor3 = on and WHITE or OFFC
		t.t.TextColor3 = on and INK or WHITE
	end
end

for i, tab in ipairs(TABS) do
	local w = math.floor((W - 28 - 6 * (#TABS - 1)) / #TABS)
	local b = new("TextButton", { Name = "Tab_" .. tab.id, LayoutOrder = i, Size = UDim2.fromOffset(w, 34), AutoButtonColor = false, Text = "",
		BackgroundColor3 = OFFC, BorderSizePixel = 0 }, tabBar)
	corner(b, 10)
	stroke(b, INK, 1.5)
	local t = label(b, { Size = UDim2.new(1, -16, 1, -14), Position = UDim2.fromOffset(8, 7), Text = tab.name })
	if tab.perk then -- a small pink dot while the perk isn't owned
		local dot = new("Frame", { Name = "Lock", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.fromRGB(255, 160, 220), BorderSizePixel = 0 }, b)
		corner(dot)
		tabButtons[tab.id] = { b = b, t = t, dot = dot, perk = tab.perk }
	else
		tabButtons[tab.id] = { b = b, t = t }
	end
	b.Activated:Connect(function()
		buildPage(tab.id)
	end)
end
local function showLocks()
	for _, t in pairs(tabButtons) do
		if t.dot then
			t.dot.Visible = not perk(t.perk)
		end
	end
end

local function open(tab)
	fit()
	showLocks()
	root.Visible = true
	buildPage(tab or curTab)
	panel.Position = UDim2.fromScale(0.5, 0.56)
	tween(panel, 0.18, { Position = UDim2.fromScale(0.5, 0.52) })
end
local function close()
	-- (2026-11-15) REPLAY INTRO: the tour needs the screen, so the panel gets out of the way (hooked below)
	endCapture()
	root.Visible = false
end
player:GetAttributeChangedSignal("OnboardReplay"):Connect(function()
	close()
end)
closeBtn.Activated:Connect(close)
shade.Activated:Connect(function(io)
	-- only taps OUTSIDE the panel close it
	if io and io.Position then
		local a, s = panel.AbsolutePosition, panel.AbsoluteSize
		local x, y = io.Position.X, io.Position.Y
		if x >= a.X and x <= a.X + s.X and y >= a.Y and y <= a.Y + s.Y then
			return
		end
	end
	close()
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

---------------------------------------------------------------------------------------------------------------------
-- SAVING
local flushToken = 0
local function readServer()
	local raw = player:GetAttribute("Settings")
	if type(raw) ~= "string" then
		return
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(t) ~= "table" then
		return
	end
	for k, v in pairs(t) do
		if DEFAULTS[k] ~= nil and pending[k] == nil and type(v) == type(DEFAULTS[k]) then
			cur[k] = v
		end
	end
	apply()
	if root.Visible then
		refresh()
	end
	-- (review fix) Keybinds reloads Settings.keys on every publish; a rebind still waiting in the debounce must win, or an
	-- older publish landing mid-edit would revert it and the next save would drop it
	if pending.keys ~= nil then
		task.defer(function()
			if pending.keys ~= nil and Keybinds.serialize() ~= pending.keys then
				Keybinds.load(pending.keys)
			end
		end)
	end
end

local function flushSoon()
	flushToken += 1
	local my = flushToken
	task.delay(0.6, function()
		if my ~= flushToken or not ShopRequest then
			return
		end
		local send = table.clone(pending)
		if next(send) == nil then
			return
		end
		local ok, a, b = pcall(ShopRequest.InvokeServer, ShopRequest, "settings", send)
		for k, v in pairs(send) do
			if pending[k] == v then
				pending[k] = nil
			end
		end
		if ok and a then
			status("SAVED", GREEN)
		else
			status(ok and tostring(b or "COULDN'T SAVE") or "COULDN'T SAVE - TRY AGAIN", RED)
		end
		readServer()
	end)
end

set = function(key, v)
	if DEFAULTS[key] == nil or cur[key] == v then
		return
	end
	cur[key] = v
	pending[key] = v
	apply()
	refresh()
	flushSoon()
end

player:GetAttributeChangedSignal("Settings"):Connect(readServer)
-- CONTROLS: the chips follow every rebind (a swap moves two rows; saved binds load in), the SHIFT LOCK switch follows the
-- key and the touch button
local function refreshControls()
	if root.Visible and curTab == "controls" then
		refresh()
	end
end
Keybinds.Changed:Connect(refreshControls)
player:GetAttributeChangedSignal("OptShiftLock"):Connect(refreshControls)
player.AttributeChanged:Connect(function(name)
	if name == "Perk_FunFilters" or name == "Perk_KillSound" or name == "Perk_UltOutfit" then
		apply()
		showLocks()
		if root.Visible then
			buildPage(curTab)
		end
	end
end)
readServer()
apply()

if OpenPanel then
	OpenPanel.Event:Connect(function(name, itemId)
		if name == "settings" then
			open(({ KillSound = "audio", FunFilters = "fun", UltOutfit = "outfit" })[itemId or ""])
		end
	end)
end

-- kill / death sounds (the server only sends them for KillSound perk owners)
local lastCustom = 0
if CustomSound then
	CustomSound.OnClientEvent:Connect(function(id, pos, kind, uid)
		id = tonumber(id)
		if not id or id <= 0 or typeof(pos) ~= "Vector3" then
			return
		end
		if uid ~= player.UserId and not cur.custom then
			return
		end
		local now = os.clock()
		if now - lastCustom < 0.12 then
			return
		end
		lastCustom = now
		local a = new("Attachment", { Name = "CustomSound", Position = pos })
		local s = new("Sound", { SoundId = "rbxassetid://" .. fmtId(id), Volume = 1.2, RollOffMinDistance = 20, RollOffMaxDistance = 260,
			SoundGroup = SFX }, a)
		a.Parent = workspace.Terrain
		s:Play()
		Debris:AddItem(a, 6)
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- THE GEAR PILL (end of the top strip; its own corner button if the strip isn't there)
local function gearIcon(parent, size, hole)
	local g = new("Frame", { Name = "Gear", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1 }, parent)
	local r = size * 0.36
	for i = 0, 7 do
		local a = i * math.pi / 4
		corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r),
			Size = UDim2.fromOffset(size * 0.22, size * 0.26), Rotation = math.deg(a) + 90, BackgroundColor3 = WHITE, BorderSizePixel = 0 }, g), 2)
	end
	corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size * 0.74, size * 0.74),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, g))
	corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size * 0.3, size * 0.3),
		BackgroundColor3 = hole, BorderSizePixel = 0 }, g))
	return g
end

task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b
	if strip then
		b = new("TextButton", { Name = "SettingsPill", LayoutOrder = 9, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(PILL_H, PILL_H),
			BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, strip)
	else
		b = new("TextButton", { Name = "SettingsPill", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), AutoButtonColor = false,
			Text = "", Size = UDim2.fromOffset(PILL_H, PILL_H), BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, gui)
	end
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	local g = gearIcon(b, 24, PILL_BG)
	b.MouseEnter:Connect(function()
		tween(st, 0.12, { Transparency = 0 })
		tween(g, 0.25, { Rotation = 45 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.12, { Transparency = 0.55 })
		tween(g, 0.25, { Rotation = 0 })
	end)
	b.Activated:Connect(function()
		if root.Visible then
			close()
		else
			open()
		end
	end)
end)

-- Studio test hook
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			open(a)
		elseif cmd == "close" then
			close()
		elseif cmd == "set" then
			set(a, b)
		elseif cmd == "bind" then -- ("bind", "Q", "Z"); ("bind", "Q") = Q's action back to Q; ("bind") = reset all
			local ok, why = true, nil
			if a == nil then
				Keybinds.reset()
			else
				ok, why = Keybinds.set(Enum.KeyCode[a], b and Enum.KeyCode[b] or nil)
			end
			if ok then
				set("keys", Keybinds.serialize())
			end
			return ok, why
		elseif cmd == "state" then
			return HttpService:JSONEncode({ cur = cur, pending = pending, tab = curTab, open = root.Visible, weather = fx.weatherKind,
				keys = Keybinds.serialize(), capture = capture and capture.key.Name or nil, shiftLock = player:GetAttribute("OptShiftLock") == true,
				flip = flipOn, debrisOff = debrisOff, sfx = SFX.Volume })
		end
		return true
	end
	ctl.Parent = script
end
