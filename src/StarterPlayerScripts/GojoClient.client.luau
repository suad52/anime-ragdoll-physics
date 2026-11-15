--!nocheck
-- GojoClient: input, HUD, camera juice and playback (procedural animation + VFX) of every cast in the server.
-- The server is authoritative; the local caster predicts its own cast and reconciles with AbilityCast/AbilityResult.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- the Gojo (Limitless) kit only listens while it is the equipped kit (the server owns the player's "Kit" attribute)
local function isGojo()
	local kit = player:GetAttribute("Kit")
	return kit == nil or kit == "Limitless"
end
local Shared = ReplicatedStorage:WaitForChild("GojoShared")
local Remotes = Shared:WaitForChild("Remotes")
local AbilityRequest = Remotes:WaitForChild("AbilityRequest")
local AbilityCast = Remotes:WaitForChild("AbilityCast")
local AbilityEvent = Remotes:WaitForChild("AbilityEvent")
local AbilityResult = Remotes:WaitForChild("AbilityResult")
local ConfigFolder = Shared:WaitForChild("Config")
local HP = require(ConfigFolder:WaitForChild("HollowPurple"))
local PUNCH = require(ConfigFolder:WaitForChild("Punch"))
local ClientFolder = Shared:WaitForChild("Client")
local Animator = require(ClientFolder:WaitForChild("ProceduralAnimator"))
local Clips = require(ClientFolder:WaitForChild("Clips"))
local VFX = require(ClientFolder:WaitForChild("PurpleVFX"))
local FX = require(ClientFolder:WaitForChild("GojoFX"))
local BlueFX = require(ClientFolder:WaitForChild("BlueFX"))
local BLUE = require(ConfigFolder:WaitForChild("Blue"))
local RED = require(ConfigFolder:WaitForChild("Red"))
local DOMAIN = require(ConfigFolder:WaitForChild("Domain"))
local NPCCFG = require(ConfigFolder:WaitForChild("NPC"))
local GrabMove = Remotes:WaitForChild("GrabMove")
local CollectionService = game:GetService("CollectionService")
-- KEYBINDS (2026-11-11, owner: "have the option to have keybinds"): every move key below goes through
-- HudShared.Keybinds - logical() maps the key the player pressed back to the move's DEFAULT key and label() draws the
-- bound key on the chips - so the defaults E / Q / R / G behave exactly as before and a rebound move follows its key.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local LocalFX = Instance.new("Folder")
LocalFX.Name = "LocalFX"
LocalFX.Parent = workspace

-- PERKS (2026-11-07, kits-A): Faster Cooldowns / Faster Ult Charge scale this kit's cooldowns exactly as CombatService
-- does (CooldownMul, and UltChargeMul for the Domain), and the CRIMSON VOID skin (the CASTER's Skin == "Alt", read at
-- cast time) builds that cast's world VFX under LocalFX.LimitlessAltFX, which GojoShared.SkinTint recolours with
-- Config.AltSkin; screen-space colours go through LimitlessPerk.sk. One table keeps this script's local count down.
local LimitlessPerk = {}
do
	local okT, SkinTint = pcall(require, Shared:WaitForChild("SkinTint", 10))
	local okA, ALT = pcall(require, ConfigFolder:WaitForChild("AltSkin", 10))
	LimitlessPerk.ok = okT and okA and type(SkinTint) == "table" and type(ALT) == "table"
	LimitlessPerk.Tint = LimitlessPerk.ok and SkinTint or nil
	LimitlessPerk.ALT = LimitlessPerk.ok and ALT or nil
	LimitlessPerk.map = LimitlessPerk.ok and SkinTint.mapper(ALT) or function(c)
		return c
	end
	LimitlessPerk.AltFX = Instance.new("Folder")
	LimitlessPerk.AltFX.Name = "LimitlessAltFX"
	LimitlessPerk.AltFX.Parent = LocalFX
	if LimitlessPerk.ok then
		SkinTint.watch(LimitlessPerk.AltFX, LimitlessPerk.map)
	else
		warn("[GojoClient] CRIMSON VOID skin unavailable: " .. tostring(not okT and SkinTint or ALT))
	end
	LimitlessPerk.voidAlt = false
end
-- the cooldown multiplier for a normal move (false) or the ultimate (true)
function LimitlessPerk.cd(isUlt)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, as the server does
	local bal = require(ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Balance"))
	return math.clamp(m, 0.05, 4) * (isUlt and 1 or bal.NON_ULT_COOLDOWN_MUL)
end
-- is this caster (a Player) wearing the alternate skin right now?
function LimitlessPerk.alt(caster)
	return LimitlessPerk.ok and typeof(caster) == "Instance" and caster:IsA("Player") and caster:GetAttribute("Skin") == "Alt" or false
end
-- where a cast's world VFX live
function LimitlessPerk.root(alt)
	return alt and LimitlessPerk.AltFX or LocalFX
end
-- a colour as the cast's skin draws it
function LimitlessPerk.sk(alt, c)
	if alt and c then
		return LimitlessPerk.map(c)
	end
	return c
end
-- recolour something built outside the skin folder (on a body part) for an alt-skin cast
function LimitlessPerk.paint(alt, inst)
	if alt and LimitlessPerk.ok and typeof(inst) == "Instance" then
		LimitlessPerk.Tint.applyTree(inst, LimitlessPerk.map)
	end
	return inst
end

local PURPLE = Color3.fromRGB(170, 90, 255)
local TINT = Color3.fromRGB(226, 206, 255)
local RED_C = Color3.fromRGB(255, 60, 50)
local BLUE_C = Color3.fromRGB(80, 160, 255)
local WHITE = Color3.new(1, 1, 1)

-- a normal that faces the camera (for rings that should read as a halo from wherever you look)
local function camFacing(p)
	local d = workspace.CurrentCamera.CFrame.Position - p
	return d.Magnitude > 1e-3 and d.Unit or Vector3.yAxis
end
-- a ring normal tipped at random but still roughly facing the camera, so a ring never reads as a flat bar
local function camTilt(p, amount)
	return (camFacing(p) + FX.randUnit() * (amount or 0.75)).Unit
end

local function now()
	return workspace:GetServerTimeNow()
end

local function myChar()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

-- same clamp as the server: returns (aimDir, flatDir)
local function clampAim(v)
	if typeof(v) ~= "Vector3" or v.Magnitude < 1e-3 then
		return nil
	end
	v = v.Unit
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit
	local pitch = math.clamp(math.deg(math.asin(math.clamp(v.Y, -1, 1))), HP.MinPitch, HP.MaxPitch)
	local r = math.rad(pitch)
	return (flat * math.cos(r) + Vector3.yAxis * math.sin(r)).Unit, flat
end

local debugAim = nil
local function getAim()
	return debugAim or workspace.CurrentCamera.CFrame.LookVector
end

-- Hollow Purple's aim (2026-11-08). It used to fly straight along the camera's LookVector, but the third-person camera
-- sits above and behind the character looking down at it, so that vector pitches 10-25 degrees down and the orb
-- buried itself in the street a few studs out. Now: a living body near the crosshair (screen centre) or under the
-- mouse, in front of the caster, is aimed at directly (torso height); otherwise the orb flies level along the
-- camera's heading, and only tips upward when the camera itself looks up. It never aims down except at a body.
-- (2026-11-08) Reversal Red had the same bug (it went off in the street at the caster's feet) and shares this aim:
-- assistAim(hrp, reach, originOf) where originOf(flatDir) is the ability's launch point for that heading.
local PURPLE_ASSIST_DEG = 10
local function assistAim(hrp, reach, originOf)
	if debugAim then
		return debugAim
	end
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local heading = Vector3.new(look.X, 0, look.Z)
	if heading.Magnitude < 1e-3 then
		return look
	end
	heading = heading.Unit
	local camPos = cam.CFrame.Position
	local m = UserInputService:GetMouseLocation()
	local rays = { look, cam:ViewportPointToRay(m.X, m.Y).Direction.Unit }
	local best, bestAng
	local function consider(model)
		if model == player.Character then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local part = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
		if not (hum and part and part:IsA("BasePart") and hum.Health > 0) then
			return
		end
		local fromMe = part.Position - hrp.Position
		local to = part.Position - camPos
		if to.Magnitude < 1 or fromMe.Magnitude > reach or fromMe:Dot(heading) <= 0 then
			return -- out of range, or behind the caster
		end
		local u = to.Unit
		for _, r in ipairs(rays) do
			local ang = math.deg(math.acos(math.clamp(u:Dot(r), -1, 1)))
			if ang <= PURPLE_ASSIST_DEG and (not bestAng or ang < bestAng) then
				best, bestAng = part, ang
			end
		end
	end
	for _, model in ipairs(CollectionService:GetTagged(NPCCFG.Tag)) do
		consider(model)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player and pl.Character then
			consider(pl.Character)
		end
	end
	if best then
		local f = Vector3.new(best.Position.X - hrp.Position.X, 0, best.Position.Z - hrp.Position.Z)
		f = f.Magnitude > 1e-3 and f.Unit or heading
		local d = best.Position - originOf(f)
		-- the server rebuilds the launch point from the aim's own heading: settle on it (matters for side offsets)
		local f2 = Vector3.new(d.X, 0, d.Z)
		if f2.Magnitude > 1e-3 then
			d = best.Position - originOf(f2.Unit)
		end
		if d.Magnitude > 1 and d:Dot(f) > 0 then
			return d.Unit
		end
	end
	if look.Y > 0 then
		return look -- the camera looks up: fire up with it (clampAim caps it at MaxPitch)
	end
	return heading
end

local function purpleAim(hrp, variant)
	local V = HP.Variants[variant] or HP.Variants.Quick
	return assistAim(hrp, V.Range + V.Radius, function(f)
		return hrp.Position + f * HP.OriginForward + Vector3.yAxis * HP.OriginUp
	end)
end

local function redAim(hrp)
	return assistAim(hrp, RED.Range, function(f)
		return hrp.Position + f * RED.OriginForward + f:Cross(Vector3.yAxis) * RED.OriginRight + Vector3.yAxis * RED.OriginUp
	end)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundBelow(pos, ignore)
	groundParams.FilterDescendantsInstances = { LocalFX, ignore, workspace:FindFirstChild("NPCs"), workspace:FindFirstChild("FX") }
	local hit = workspace:Raycast(pos + Vector3.yAxis * 2, Vector3.new(0, -14, 0), groundParams)
	return hit and hit.Position or (pos - Vector3.yAxis * 3)
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }

---------------------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "GojoHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 14)
	c.Parent = p
	return c
end
local function stroke(p, color, th, tr)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = th
	st.Transparency = tr or 0
	st.Parent = p
	return st
end
local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBlack
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local impactBlack = Instance.new("Frame")
impactBlack.Size = UDim2.fromScale(1, 1)
impactBlack.BackgroundColor3 = Color3.new(0, 0, 0)
impactBlack.BackgroundTransparency = 1
impactBlack.BorderSizePixel = 0
impactBlack.ZIndex = 50
impactBlack.Parent = gui
local impactWhite = impactBlack:Clone()
impactWhite.BackgroundColor3 = Color3.fromRGB(245, 235, 255)
impactWhite.ZIndex = 51
impactWhite.Parent = gui

local titleHolder = Instance.new("Frame")
titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
titleHolder.Position = UDim2.fromScale(0.5, 0.27)
titleHolder.Size = UDim2.fromScale(0.86, 0.15)
titleHolder.BackgroundTransparency = 1
titleHolder.ZIndex = 40
titleHolder.Parent = gui
local titleScale = Instance.new("UIScale")
titleScale.Parent = titleHolder
local title = label(titleHolder, { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), TextScaled = true, Text = "", TextTransparency = 1, ZIndex = 41 })
local titleStroke = stroke(title, Color3.fromRGB(40, 0, 70), 3, 1)
local titleGrad = Instance.new("UIGradient")
titleGrad.Color = ColorSequence.new(Color3.fromRGB(255, 225, 255), Color3.fromRGB(170, 90, 255))
titleGrad.Rotation = 90
titleGrad.Parent = title
local kanji = label(titleHolder, { Size = UDim2.fromScale(1, 0.32), TextScaled = true, Text = "虚式", TextTransparency = 1, ZIndex = 41, TextColor3 = Color3.fromRGB(225, 190, 255) })
local kanjiStroke = stroke(kanji, Color3.fromRGB(40, 0, 70), 2, 1)

local subtitle = label(gui, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromScale(0.7, 0.06),
	TextScaled = true, Text = "", TextTransparency = 1, Font = Enum.Font.GothamBold, ZIndex = 40,
})
local subStroke = stroke(subtitle, Color3.fromRGB(60, 10, 100), 2, 1)
local subScale = Instance.new("UIScale")
subScale.Parent = subtitle

local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -22, 1, -22)
bar.Size = UDim2.fromOffset(380, 112)
bar.BackgroundTransparency = 1
bar.Parent = gui
local barScale = Instance.new("UIScale")
barScale.Parent = bar

local function abilityButton(name, size, pos, key, text, hint, bg)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Text = ""
	b.Size = UDim2.fromOffset(size, size)
	b.Position = pos
	b.AnchorPoint = Vector2.new(1, 1)
	b.BackgroundColor3 = bg
	b.Parent = bar
	corner(b, UDim.new(0, 18))
	stroke(b, Color3.fromRGB(200, 150, 255), 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = Color3.new(1, 1, 1)
	orb.Parent = b
	corner(orb, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 240, 255), name == "Purple" and Color3.fromRGB(150, 60, 255) or (name == "Blue" and Color3.fromRGB(60, 140, 255) or (name == "Red" and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 180, 90))))
	g.Rotation = 45
	g.Parent = orb
	label(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = text, TextScaled = true, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(20, 12, 30)
	chip.Parent = b
	corner(chip, UDim.new(0, 6))
	-- KEYBINDS (2026-11-11): a keyboard move passes its DEFAULT KeyCode and the chip shows the key the player bound to
	-- it, redrawn whenever the binds change ("have the option to have keybinds"); "M1" stays a plain string
	local keyLbl = label(chip, { Size = UDim2.fromScale(1, 1), Text = typeof(key) == "EnumItem" and Keybinds.label(key) or key, TextScaled = true, Font = Enum.Font.GothamBold })
	if typeof(key) == "EnumItem" then
		Keybinds.Changed:Connect(function()
			keyLbl.Text = Keybinds.label(key)
		end)
	end
	if hint then
		label(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Text = hint, TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 200, 255) })
	end
	local cd = Instance.new("Frame")
	cd.Name = "Cooldown"
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	cd.Parent = b
	corner(cd, UDim.new(0, 18))
	local cdText = label(b, { Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.22), Text = "", TextScaled = true, ZIndex = 4 })
	return b, cd, cdText
end

local purpleBtn, purpleCd, purpleCdText = abilityButton("Purple", 104, UDim2.new(1, 0, 1, -16), Enum.KeyCode.E, "HOLLOW PURPLE", "hold: incantation", Color3.fromRGB(42, 18, 74))
local punchBtn, punchCd, punchCdText = abilityButton("Punch", 72, UDim2.new(1, -116, 1, -16), "M1", "PUNCH", nil, Color3.fromRGB(46, 30, 26))
local blueBtn, blueCd, blueCdText = abilityButton("Blue", 72, UDim2.new(1, -198, 1, -16), Enum.KeyCode.Q, "LAPSE BLUE", "hold: grab", Color3.fromRGB(18, 34, 74))
local redBtn, redCd, redCdText = abilityButton("Red", 72, UDim2.new(1, -280, 1, -16), Enum.KeyCode.R, "REVERSAL RED", nil, Color3.fromRGB(74, 16, 20))
-- the ultimate gets its own wide button above the row
local domainBtn = Instance.new("TextButton")
domainBtn.Name = "Domain"
domainBtn.AutoButtonColor = false
domainBtn.Text = ""
domainBtn.AnchorPoint = Vector2.new(1, 1)
domainBtn.Position = UDim2.new(1, 0, 1, -132)
domainBtn.Size = UDim2.fromOffset(186, 36)
domainBtn.BackgroundColor3 = Color3.new(1, 1, 1)
domainBtn.Parent = bar
corner(domainBtn, UDim.new(0, 12))
stroke(domainBtn, Color3.fromRGB(160, 215, 255), 2, 0.1)
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(14, 18, 46), Color3.fromRGB(46, 30, 96))
	g.Rotation = 0
	g.Parent = domainBtn
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
	chip.Parent = domainBtn
	corner(chip, UDim.new(0, 6))
	-- KEYBINDS (2026-11-11): the ultimate's chip shows the key bound to G and follows rebinds
	local gLbl = label(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(Enum.KeyCode.G), TextScaled = true, Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		gLbl.Text = Keybinds.label(Enum.KeyCode.G)
	end)
	label(domainBtn, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = "DOMAIN EXPANSION", TextScaled = true, ZIndex = 2 })
	label(domainBtn, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = "UNLIMITED VOID", TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(170, 210, 255), ZIndex = 2 })
end
local domainCd = Instance.new("Frame")
domainCd.AnchorPoint = Vector2.new(1, 0)
domainCd.Position = UDim2.fromScale(1, 0)
domainCd.Size = UDim2.fromScale(0, 1)
domainCd.BackgroundColor3 = Color3.new(0, 0, 0)
domainCd.BackgroundTransparency = 0.35
domainCd.ZIndex = 3
domainCd.Parent = domainBtn
corner(domainCd, UDim.new(0, 12))
local domainCdText = label(domainBtn, { Size = UDim2.fromScale(1, 1), Text = "", TextScaled = true, ZIndex = 4, TextColor3 = Color3.new(1, 1, 1) })

local function updateScale()
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	barScale.Scale = math.clamp(vp.Y / 720, 0.75, 1.3)
end
updateScale()

local titleToken, subToken
local function showTitle(text, kanjiText, c0, c1, kanjiColor)
	local token = {}
	titleToken = token
	title.Text = text
	kanji.Text = kanjiText or "虚式"
	kanji.TextColor3 = kanjiColor or Color3.fromRGB(225, 190, 255)
	titleGrad.Color = ColorSequence.new(c0 or Color3.fromRGB(255, 225, 255), c1 or Color3.fromRGB(170, 90, 255))
	title.TextTransparency, kanji.TextTransparency = 0, 0
	titleStroke.Transparency, kanjiStroke.Transparency = 0, 0
	titleScale.Scale = 1.7
	titleHolder.Rotation = -5
	TweenService:Create(titleScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(titleHolder, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	task.delay(1.5, function()
		if titleToken ~= token then
			return
		end
		local info = TweenInfo.new(0.45)
		TweenService:Create(title, info, { TextTransparency = 1 }):Play()
		TweenService:Create(kanji, info, { TextTransparency = 1 }):Play()
		TweenService:Create(titleStroke, info, { Transparency = 1 }):Play()
		TweenService:Create(kanjiStroke, info, { Transparency = 1 }):Play()
	end)
end
local function hideTitle()
	titleToken = nil
	title.TextTransparency, kanji.TextTransparency = 1, 1
	titleStroke.Transparency, kanjiStroke.Transparency = 1, 1
end

local function showSubtitle(text, hold)
	local token = {}
	subToken = token
	subtitle.Text = text
	subtitle.TextTransparency = 0
	subStroke.Transparency = 0
	subScale.Scale = 1.35
	TweenService:Create(subScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(hold or 0.65, function()
		if subToken ~= token then
			return
		end
		TweenService:Create(subtitle, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end)
end

-- the anime impact frame (two stark high-contrast frames, a burst of light, speed lines): see GojoFX.impact
local function impactFrame(tint, lineColor)
	FX.impact({ tint = tint, lineColor = lineColor })
end

---------------------------------------------------------------------------------------------------
-- camera envelopes: every effect is a timed envelope; the sum is applied after the camera module each frame,
-- so nothing accumulates and everything returns to the player's own FOV when the last envelope expires
local envelopes = {}
local baseFOV
local cc, blur

local function addEnvelope(e)
	e.t0 = os.clock() + (e.delay or 0)
	e.attack = e.attack or 0.05
	e.hold = e.hold or 0
	e.release = e.release or 0.3
	if #envelopes == 0 and not baseFOV then
		baseFOV = workspace.CurrentCamera.FieldOfView
	end
	table.insert(envelopes, e)
	return e
end

local function clearEnvelopes(tag)
	for i = #envelopes, 1, -1 do
		if envelopes[i].tag == tag then
			table.remove(envelopes, i)
		end
	end
end

local function envWeight(e, t)
	local x = t - e.t0
	if x < 0 then
		return 0
	end
	if x < e.attack then
		return x / e.attack
	end
	x -= e.attack
	if x < e.hold then
		return 1
	end
	x -= e.hold
	if x < e.release then
		local r = 1 - x / e.release
		return r * r
	end
	return nil
end

RunService:BindToRenderStep("GojoCameraFX", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if #envelopes == 0 then
		if baseFOV then
			cam.FieldOfView = baseFOV
			baseFOV = nil
		end
		if cc then
			cc:Destroy()
			cc = nil
		end
		if blur then
			blur:Destroy()
			blur = nil
		end
		return
	end
	if not cc or cc.Parent ~= cam then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "GojoCC"
		cc.Parent = cam
	end
	if not blur or blur.Parent ~= cam then
		blur = Instance.new("BlurEffect")
		blur.Name = "GojoBlur"
		blur.Size = 0
		blur.Parent = cam
	end
	local t = os.clock()
	local fov, bl, br, ct, sat, shake, tintW, freq = 0, 0, 0, 0, 0, 0, 0, 20
	local tint = Color3.new(1, 1, 1)
	local i = 1
	while i <= #envelopes do
		local e = envelopes[i]
		local w = envWeight(e, t)
		if w == nil then
			table.remove(envelopes, i)
		else
			fov += (e.fov or 0) * w
			bl += (e.blur or 0) * w
			br += (e.bright or 0) * w
			ct += (e.contrast or 0) * w
			sat += (e.sat or 0) * w
			if e.shake then
				shake += e.shake * w
				freq = e.freq or freq
			end
			if e.tint and w > tintW then
				tintW = w
				tint = e.tint
			end
			i += 1
		end
	end
	cam.FieldOfView = math.clamp((baseFOV or 70) + fov, 20, 110)
	if player:GetAttribute("OptNoFlash") then -- Settings: flashing lights off
		br = math.min(br, 0.05)
	end
	cc.Brightness, cc.Contrast, cc.Saturation = br, ct, sat
	cc.TintColor = Color3.new(1, 1, 1):Lerp(tint, tintW)
	blur.Size = bl
	if shake > 0.002 and cam.CameraType ~= Enum.CameraType.Scriptable and not player:GetAttribute("OptNoShake") then -- Settings: shake
		local a, b, c = math.noise(t * freq, 0.3, 1.7), math.noise(1.9, t * freq, 4.1), math.noise(7.3, 2.2, t * freq)
		cam.CFrame = cam.CFrame * CFrame.new(a * shake, b * shake, 0) * CFrame.Angles(b * shake * 0.03, a * shake * 0.03, c * shake * 0.04)
	end
end)

local function strengthAt(cast, pos)
	if cast.isLocal then
		return 1
	end
	local cam = workspace.CurrentCamera
	return math.clamp(1 - (cam.CFrame.Position - pos).Magnitude / 250, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- rooting the local caster
local lockState = nil
local function lockMovement(cast, flat)
	local char, hum = myChar()
	if not hum then
		return
	end
	if not lockState then
		lockState = { hum = hum, ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight, ar = hum.AutoRotate }
	end
	lockState.owner = cast
	hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
	cast.faceDir = flat
end

local function unlockMovement(cast)
	if not lockState or (cast and lockState.owner ~= cast) then
		return
	end
	local s = lockState
	lockState = nil
	if s.hum.Parent then
		s.hum.WalkSpeed, s.hum.JumpPower, s.hum.JumpHeight, s.hum.AutoRotate = s.ws, s.jp, s.jh, s.ar
	end
end

---------------------------------------------------------------------------------------------------
-- Hollow Purple playback (any caster)
local casts = {} -- [key] = cast
local pendingLocal = nil
local cooldownEnd = { HollowPurple = 0, Red = 0, Domain = 0, Blue = 0 } -- Blue (2026-11-10): set by the server when a grab ends

local function handPos(char, side)
	local hand = char and char:FindFirstChild(side .. "Hand")
	if not hand then
		return nil
	end
	local grip = hand:FindFirstChild(side .. "GripAttachment")
	return grip and grip.WorldPosition or hand.Position
end

local function mergePoint(cast)
	local char = cast.caster.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		return (hrp.CFrame * CFrame.new(0, 1.0, -2.3)).Position
	end
	return cast.data.origin
end

local function chargeRadius(cast)
	return cast.data.variant == "Incantation" and 3.6 or 2.4
end

local function cleanupAura(cast)
	if cast.aura then
		cast.aura:Destroy()
		cast.aura = nil
	end
end

local function finalize(cast)
	if cast.final then
		return
	end
	cast.final = true
	casts[cast.key] = nil
	cleanupAura(cast)
	if cast.rocks then
		cast.rocks:drop()
		cast.rocks = nil
	end
	if cast.helix then
		cast.helix:destroy()
		cast.helix = nil
	end
	if cast.isLocal then
		unlockMovement(cast)
	end
	local folder = cast.folder
	task.delay(3, function()
		folder:Destroy()
	end)
end

local function cancelPurple(cast)
	if not cast or cast.cancelled or cast.final then
		return
	end
	cast.cancelled = true
	if cast.track then
		cast.track:stop(0.15)
	end
	for _, k in ipairs({ "blue", "red", "purple" }) do
		if cast[k] then
			cast[k]:destroy(0.15)
			cast[k] = nil
		end
	end
	clearEnvelopes(cast)
	-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
	-- (Hollow Purple shows no title any more, so a cancel no longer calls hideTitle - it could only cut the Domain's title)
	if pendingLocal == cast then
		pendingLocal = nil
	end
	finalize(cast)
end

local function endPurple(cast, pos)
	if cast.ended then
		return
	end
	cast.ended = true
	if cast.helix then
		cast.helix:destroy()
		cast.helix = nil
	end
	if cast.purple then
		VFX.flash(cast.folder, pos, cast.data.radius * 1.3, Color3.fromRGB(225, 175, 255), 0.4)
		local R = cast.data.radius
		FX.glow(cast.folder, pos, R * 3, Color3.fromRGB(225, 180, 255), 0.5, { brightness = 3 })
		FX.ring(cast.folder, pos, cast.data.dir, R, R * 5, PURPLE, 0.5)
		FX.streaks(cast.folder, pos, { color = WHITE, color2 = PURPLE, count = 40, speed = { 60, 150 }, size = 0.9 })
		FX.arcs(cast.folder, pos, R * 1.2, { outward = true, count = 5, colors = { RED_C, BLUE_C, WHITE }, width = 0.25 })
		cast.purple:destroy(0.35)
		cast.purple = nil
	end
end

local function newPurpleCast(caster, data, isLocal)
	local clip = (data.variant == "Incantation") and Clips.PurpleIncantation or Clips.PurpleQuick
	local V = HP.Variants[data.variant] or HP.Variants.Quick
	local e = now() - data.startServerTime
	local flightEnd = data.launchTime + data.range / math.max(data.speed, 1)
	if e > math.max(V.LockTime, flightEnd) + 0.25 then
		return nil -- already over
	end
	local cast = {
		caster = caster, data = data, isLocal = isLocal, clip = clip, beats = clip.beats, lockTime = V.LockTime,
		key = data.castId or ("local" .. tostring(os.clock())), chantDone = {},
	}
	cast.folder = Instance.new("Folder")
	cast.folder.Name = "Purple_" .. tostring(cast.key)
	cast.alt = LimitlessPerk.alt(caster)
	cast.folder.Parent = LimitlessPerk.root(cast.alt)
	local char = caster.Character
	if char and e < clip.length then
		cast.track = Animator.play(char, clip, { startAt = math.max(e, 0) })
	end
	if isLocal and e < V.LockTime then
		local _, flat = clampAim(data.dir)
		lockMovement(cast, flat or Vector3.new(0, 0, -1))
	end
	casts[cast.key] = cast
	return cast
end

local function adopt(cast, sd)
	local drift = sd.startServerTime - cast.data.startServerTime
	casts[cast.key] = nil
	cast.key = sd.castId
	cast.data = sd
	casts[cast.key] = cast
	if math.abs(drift) > 0.15 and cast.track and cast.track:isPlaying() then
		cast.track:setTime(math.max(now() - sd.startServerTime, 0))
	end
end

local function updatePurple(cast, dt)
	if cast.final then
		return
	end
	local d, B = cast.data, cast.beats
	local e = now() - d.startServerTime
	local char = cast.caster and cast.caster.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local incant = d.variant == "Incantation"
	local mp = mergePoint(cast)

	-- keep the local caster facing the aim while rooted
	if cast.isLocal and lockState and lockState.owner == cast and hrp and cast.faceDir then
		local want = CFrame.lookAt(Vector3.zero, cast.faceDir)
		local cur = hrp.CFrame - hrp.Position
		hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-14 * dt))
	end
	if cast.isLocal and e >= cast.lockTime then
		unlockMovement(cast)
	end

	-- incantation: chant lines, ground pulses, rising aura
	if B.chant then
		for i, tc in ipairs(B.chant) do
			if e >= tc and not cast.chantDone[i] then
				cast.chantDone[i] = true
				if e < tc + 0.5 and hrp then
					local s = strengthAt(cast, hrp.Position)
					-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
					-- (the incantation's chant-line subtitles are gone; the chant sound, pulses and aura below stay)
					local g = groundBelow(hrp.Position, char)
					VFX.shockwave(cast.folder, g + Vector3.yAxis * 0.2, Vector3.yAxis, 6, 24 + i * 6, PURPLE, 0.9)
					VFX.sound(VFX.Sounds.Chant, hrp, 0.7, 0.55)
					local hp = handPos(char, "Right")
					if hp then
						FX.glow(cast.folder, hp, 5 + i, Color3.fromRGB(205, 160, 255), 0.4)
						FX.sparks(cast.folder, hp, { color = Color3.fromRGB(240, 220, 255), color2 = PURPLE, count = 14, speed = { 6, 16 }, size = 0.45, accel = Vector3.new(0, 6, 0) })
					end
					FX.ring(cast.folder, g + Vector3.yAxis * 0.3, Vector3.yAxis, 4, 26 + i * 8, PURPLE, 0.7, { alpha = 0.15 })
					if i == #B.chant and not cast.rocks then
						cast.rocks = FX.liftRocks(cast.folder, hrp.Position, 14, 14)
					end
					if s > 0 then
						addEnvelope({ tag = cast, fov = -3.5 * s, attack = 0.45, hold = math.max(d.launchTime - tc - 0.45, 0), release = 0.15 })
						addEnvelope({ tag = cast, shake = 0.12 * s, freq = 16, attack = 0.03, hold = 0.05, release = 0.3 })
					end
					if not cast.aura then
						local a = Instance.new("Attachment")
						a.Name = "GojoAura"
						a.Position = Vector3.new(0, -2.5, 0)
						a.Parent = hrp
						local em = Instance.new("ParticleEmitter")
						em.Texture = "rbxasset://textures/particles/smoke_main.dds"
						em.Color = ColorSequence.new(Color3.fromRGB(190, 120, 255), Color3.fromRGB(80, 30, 160))
						em.LightEmission = 0.8
						em.LightInfluence = 0
						em.Size = NumberSequence.new(1.6, 3.2)
						em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
						em.Lifetime = NumberRange.new(0.8, 1.3)
						em.Speed = NumberRange.new(6, 10)
						em.SpreadAngle = Vector2.new(25, 25)
						em.EmissionDirection = Enum.NormalId.Top
						em.Rate = 0
						em.Parent = a
						cast.aura = a
					end
					local em = cast.aura:FindFirstChildOfClass("ParticleEmitter")
					if em then
						em.Rate = 12 * i
					end
				end
			end
		end
	end

	-- merge: the world drains of colour and starts to rumble
	if e >= B.merge and not cast.mergeFx and e < d.launchTime then
		cast.mergeFx = true
		if hrp and not cast.rocks then
			cast.rocks = FX.liftRocks(cast.folder, hrp.Position, incant and 14 or 10, incant and 14 or 9)
		end
		local s = strengthAt(cast, mp)
		if s > 0 then
			addEnvelope({ tag = cast, attack = 0.4, hold = math.max(d.launchTime - B.merge - 0.4, 0), release = 0.25, tint = LimitlessPerk.sk(cast.alt, TINT), sat = -0.18 * s, contrast = 0.12 * s, shake = 0.08 * s, freq = 18 })
		end
	end

	-- Lapse Blue (left hand) and Reversal Red (right hand)
	if e >= B.blue and e < B.birth and not cast.blueDone then
		cast.blueDone = true
		cast.blue = VFX.orb("Blue", cast.folder)
		VFX.sound(VFX.Sounds.Blue, cast.blue.core, 0.75, 1.1)
		local hp = handPos(char, "Left") or mp
		FX.glow(cast.folder, hp, 6, Color3.fromRGB(130, 195, 255), 0.35)
		FX.ring(cast.folder, hp, camFacing(hp), 1, 9, BLUE_C, 0.35)
		FX.streaks(cast.folder, hp, { inward = 6, color = WHITE, color2 = BLUE_C, count = 24, life = 0.3, size = 0.35 })
	end
	if e >= B.red and e < B.birth and not cast.redDone then
		cast.redDone = true
		cast.red = VFX.orb("Red", cast.folder)
		VFX.sound(VFX.Sounds.Red, cast.red.core, 0.75, 1.0)
		local hp = handPos(char, "Right") or mp
		FX.glow(cast.folder, hp, 6, Color3.fromRGB(255, 140, 120), 0.35)
		FX.ring(cast.folder, hp, camFacing(hp), 1, 9, RED_C, 0.35)
		FX.sparks(cast.folder, hp, { color = Color3.fromRGB(255, 200, 170), color2 = RED_C, count = 18, speed = { 12, 30 }, size = 0.45 })
	end
	for _, k in ipairs({ "blue", "red" }) do
		local orb = cast[k]
		if orb then
			local side = (k == "blue") and "Left" or "Right"
			local t0 = (k == "blue") and B.blue or B.red
			local grow = math.clamp((e - t0) / 0.35, 0, 1)
			local r = (incant and 1.5 or 1.0) * TweenService:GetValue(grow, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local pos
			if e < B.release then
				pos = handPos(char, side) or mp
				cast[k .. "Start"] = pos
			else
				local a = math.clamp((e - B.release) / math.max(B.birth - B.release, 0.05), 0, 1)
				local ea = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				local start = cast[k .. "Start"] or mp
				local theta = a * math.pi * 4 + ((k == "blue") and 0 or math.pi)
				local right = hrp and hrp.CFrame.RightVector or Vector3.xAxis
				pos = start:Lerp(mp, ea) + (right * math.cos(theta) + Vector3.yAxis * math.sin(theta)) * 0.9 * (1 - ea)
				r *= 1 - 0.3 * ea
			end
			orb:setRadius(math.max(r, 0.05))
			orb:place(pos, dt)
		end
	end

	-- the two techniques fight each other: lightning cracks between them, faster as they close in
	if (cast.blue or cast.red) and e < B.birth and os.clock() >= (cast.nextArc or 0) then
		local closing = math.clamp((e - B.merge) / math.max(B.birth - B.merge, 0.05), 0, 1)
		cast.nextArc = os.clock() + 0.11 - 0.07 * closing
		local bp = cast.blue and cast.blue.core.Position
		local rp = cast.red and cast.red.core.Position
		if bp and rp then
			FX.bolt(cast.folder, bp, rp, { color = (math.random() < 0.5) and BLUE_C or RED_C, width = 0.1 + 0.14 * closing, jag = 0.22 })
		end
		if bp then
			FX.arcs(cast.folder, bp, math.max(cast.blue.r, 0.4) * 1.1, { count = 1, color = BLUE_C, width = 0.06 })
		end
		if rp then
			FX.arcs(cast.folder, rp, math.max(cast.red.r, 0.4) * 1.1, { count = 1, color = RED_C, width = 0.06 })
		end
	end

	-- Hollow Purple is born where the two collide
	if e >= B.birth and not cast.born and e < d.launchTime + 0.2 then
		cast.born = true
		for _, k in ipairs({ "blue", "red" }) do
			if cast[k] then
				cast[k]:destroy(0.08)
				cast[k] = nil
			end
		end
		cast.purple = VFX.orb("Purple", cast.folder)
		cast.purple:setRadius(0.6)
		cast.purple:place(mp, 0)
		local s = strengthAt(cast, mp)
		VFX.flash(cast.folder, mp, 7, Color3.fromRGB(240, 210, 255), 0.35)
		VFX.burst(cast.folder, mp, Color3.fromRGB(235, 200, 255), 30, 0.9, 30)
		VFX.sound(VFX.Sounds.Birth, cast.purple.core, 0.9, 0.75)
		FX.glow(cast.folder, mp, incant and 26 or 18, Color3.fromRGB(235, 205, 255), 0.5, { brightness = 3 })
		FX.glow(cast.folder, mp, incant and 12 or 8, WHITE, 0.22, { brightness = 4 })
		for k, col in ipairs({ Color3.fromRGB(225, 180, 255), RED_C, BLUE_C }) do
			FX.ring(cast.folder, mp, camTilt(mp), 1, (incant and 34 or 24) + k * 4, col, 0.45 + k * 0.05)
		end
		FX.streaks(cast.folder, mp, { color = WHITE, color2 = PURPLE, count = incant and 90 or 60, speed = { 70, 170 }, size = 0.6, life = 0.4 })
		FX.arcs(cast.folder, mp, incant and 14 or 10, { outward = true, count = 6, colors = { RED_C, BLUE_C, WHITE }, width = 0.18, life = 0.2 })
		FX.sparks(cast.folder, mp, { color = RED_C, color2 = WHITE, count = 18, speed = { 25, 60 } })
		FX.sparks(cast.folder, mp, { color = BLUE_C, color2 = WHITE, count = 18, speed = { 25, 60 } })
		FX.light(cast.folder, mp, Color3.fromRGB(200, 140, 255), 10, 60, 0.6)
		if cast.isLocal then
			impactFrame(LimitlessPerk.sk(cast.alt, Color3.fromRGB(240, 225, 255)), LimitlessPerk.sk(cast.alt, Color3.fromRGB(235, 210, 255)))
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		-- (was: the "HOLLOW PURPLE" / "HOLLOW TECHNIQUE: PURPLE" title for the caster and nearby viewers)
		if s > 0 then
			addEnvelope({ tag = cast, fov = -9 * s, attack = 0.3, hold = math.max(d.launchTime - B.birth - 0.3, 0), release = 0.04 })
		end
	end

	-- charging: grows and drifts from the hands to the launch origin
	if cast.purple and not cast.launched and e < d.launchTime then
		local a = math.clamp((e - B.birth) / math.max(d.launchTime - B.birth, 0.05), 0, 1)
		local ea = TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		cast.purple:setRadius(0.6 + (chargeRadius(cast) - 0.6) * ea)
		cast.purple:place(mp:Lerp(d.origin, ea), dt)
		if os.clock() >= (cast.nextCharge or 0) then
			cast.nextCharge = os.clock() + 0.09
			local cp = cast.purple.core.Position
			FX.arcs(cast.folder, cp, math.max(cast.purple.r, 0.5) * 1.15, { count = 1, colors = { RED_C, BLUE_C, Color3.fromRGB(230, 190, 255) }, width = 0.1 })
			FX.streaks(cast.folder, cp, { inward = 7 + cast.purple.r * 2, color = (math.random() < 0.5) and RED_C or BLUE_C, color2 = WHITE, count = 8, life = 0.28, size = 0.4 })
		end
	end

	-- launch + flight (deterministic: same path the server simulates)
	if e >= d.launchTime and not cast.ended then
		if not cast.purple then
			cast.purple = VFX.orb("Purple", cast.folder) -- joined late
			cast.born = true
		end
		if not cast.launched then
			cast.launched = true
			cast.lastDust = 0
			local s = strengthAt(cast, d.origin)
			local m = incant and 1.6 or 1
			VFX.shockwave(cast.folder, d.origin, d.dir, 2, d.radius * 5, Color3.fromRGB(195, 130, 255), 0.45)
			VFX.flash(cast.folder, d.origin, d.radius * 1.5, Color3.fromRGB(245, 225, 255), 0.4)
			local g = groundBelow(hrp and hrp.Position or d.origin, char)
			VFX.shockwave(cast.folder, g + Vector3.yAxis * 0.2, Vector3.yAxis, 4, d.radius * 4.5, PURPLE, 0.6)
			VFX.dust(cast.folder, g, 6 * m, 12)
			VFX.sound(VFX.Sounds.Launch, VFX.anchor(cast.folder, d.origin, 7), 1, 0.85)
			cast.purple:setTrail(70)
			local R = d.radius
			FX.glow(cast.folder, d.origin, R * 1.6, Color3.fromRGB(230, 200, 255), 0.4, { brightness = 2 })
			for k = 1, 3 do
				FX.ring(cast.folder, d.origin + d.dir * (k * R * 0.6), d.dir, R * 0.6, R * (2.4 + k * 0.9), k == 1 and WHITE or PURPLE, 0.35 + k * 0.08)
			end
			FX.streaks(cast.folder, d.origin, { dir = d.dir, spread = 16, color = WHITE, color2 = PURPLE, count = 50, speed = { 120, 260 }, size = 0.8, life = 0.35 })
			FX.rubble(cast.folder, g, { count = incant and 18 or 12, radius = 5, up = { 25, 45 }, out = { 10, 30 }, dir = d.dir })
			if cast.rocks then
				cast.rocks:drop(d.dir * 40)
				cast.rocks = nil
			end
			if cast.isLocal then
				FX.impact({ tint = LimitlessPerk.sk(cast.alt, Color3.fromRGB(240, 225, 255)), lineColor = LimitlessPerk.sk(cast.alt, Color3.fromRGB(235, 215, 255)), lineTime = 0.5 })
			end
			cast.helix = FX.helix(cast.folder, { RED_C, BLUE_C }, R * 1.2, math.max(R * 0.08, 0.8))
			if s > 0 then
				addEnvelope({ tag = cast, fov = 18 * s * m, attack = 0.05, hold = 0.06, release = 0.6 })
				addEnvelope({ tag = cast, shake = 1.1 * s * m, freq = 22, attack = 0.02, hold = 0.06, release = 0.55 })
				addEnvelope({ tag = cast, blur = 16 * s, attack = 0.02, release = 0.35 })
				addEnvelope({ tag = cast, bright = 0.25 * s, attack = 0.02, release = 1.0, tint = LimitlessPerk.sk(cast.alt, Color3.fromRGB(236, 218, 255)) })
			end
			cleanupAura(cast)
		end
		local dist = math.clamp((e - d.launchTime) * d.speed, 0, d.range)
		local pos = d.origin + d.dir * dist
		local grow = math.clamp((e - d.launchTime) / 0.15, 0, 1)
		local cr = chargeRadius(cast)
		cast.purple:setRadius(cr + (d.radius - cr) * TweenService:GetValue(grow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		cast.purple:place(pos, dt)
		if os.clock() >= (cast.nextRing or 0) then
			cast.nextRing = os.clock() + 0.06
			FX.ring(cast.folder, pos - d.dir * d.radius * 0.6, d.dir, d.radius * 1.4, d.radius * 3.4, Color3.fromRGB(200, 150, 255), 0.3, { alpha = 0.35 })
			FX.arcs(cast.folder, pos, d.radius * 1.05, { count = 2, colors = { RED_C, BLUE_C, WHITE }, width = 0.22, jag = 0.35 })
		end
		if cast.helix then
			cast.helix:place(pos, d.dir, dt)
		end
		while cast.lastDust + 12 <= dist do
			cast.lastDust += 12
			local p = d.origin + d.dir * cast.lastDust
			local hit = workspace:Raycast(p + Vector3.yAxis * d.radius, Vector3.new(0, -d.radius * 2.4, 0), terrainParams)
			if hit then
				VFX.dust(cast.folder, hit.Position, d.radius * 0.45, 4)
				VFX.scorch(cast.folder, hit.Position, d.radius * 0.55)
			end
		end
		if dist >= d.range then
			endPurple(cast, pos)
		end
	end

	if cast.ended and e >= cast.lockTime then
		finalize(cast)
	end
end

local function startLocalPurple(variant)
	local char, _, hrp = myChar()
	if not char or lockState or pendingLocal or now() < cooldownEnd.HollowPurple then
		return
	end
	local aim, flat = clampAim(purpleAim(hrp, variant))
	if not aim then
		return
	end
	local V = HP.Variants[variant]
	local data = {
		castId = nil, variant = variant, startServerTime = now(),
		origin = hrp.Position + flat * HP.OriginForward + Vector3.yAxis * HP.OriginUp,
		dir = aim, launchTime = V.LaunchTime, speed = V.Speed, radius = V.Radius, range = V.Range,
	}
	local cast = newPurpleCast(player, data, true)
	if not cast then
		return
	end
	pendingLocal = cast
	cooldownEnd.HollowPurple = now() + HP.Cooldown * LimitlessPerk.cd(false) -- optimistic; AbilityResult corrects it
	AbilityRequest:FireServer("HollowPurple", { aimDir = aim, variant = variant })
	task.delay(1.2, function()
		if pendingLocal == cast then
			cancelPurple(cast)
			cooldownEnd.HollowPurple = 0
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- punches
local localPunch = { combo = 0, last = -math.huge, lockUntil = 0 }

-- each fighter punches in their own style (ClientFolder.PunchStyles, keyed by the Kit attribute) and the striking
-- limb drags a whoosh trail in the fighter's colour. Trails live in LocalFX (never inside the character, whose
-- descendants kits re-colour / fade); only their two attachments sit on the hand or foot.
local PunchStyles = require(ClientFolder:WaitForChild("PunchStyles"))
local HudKits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))
local LIMB_PARTS = { Right = { "RightHand" }, Left = { "LeftHand" }, RightFoot = { "RightFoot" }, LeftFoot = { "LeftFoot" },
	Both = { "RightHand", "LeftHand" }, All = { "RightFoot", "RightHand", "LeftHand", "LeftFoot" } }
local StrikeFX = require(ClientFolder:WaitForChild("StrikeFX"))
local whooshes = setmetatable({}, { __mode = "k" }) -- [limb part] = Trail
-- Trail Pack perk (2026-11-07): the caster's EquipTrail ("Rainbow" / "Gold" / "BlackFlame") restyles the whoosh through
-- PerkShared.TrailStyle; "" keeps the fighter-colour whoosh. Required lazily without yielding (false = unavailable).
local TrailStyleMod
local function trailStyle()
	if TrailStyleMod == nil then
		local folder = ReplicatedStorage:FindFirstChild("PerkShared")
		local mod = folder and folder:FindFirstChild("TrailStyle")
		if not mod then
			return nil
		end
		local ok, m = pcall(require, mod)
		TrailStyleMod = ok and type(m) == "table" and m or false
	end
	return TrailStyleMod or nil
end
local function whoosh(char, limb, color, dur, trailId)
	for _, name in ipairs(LIMB_PARTS[limb] or LIMB_PARTS.Right) do
		local part = char:FindFirstChild(name)
		if part then
			local tr = whooshes[part]
			if not tr or not tr.Parent then
				local a0 = Instance.new("Attachment")
				a0.Name = "WhooshA"
				a0.Position = Vector3.new(0, 0.7, 0)
				a0.Parent = part
				local a1 = Instance.new("Attachment")
				a1.Name = "WhooshB"
				a1.Position = Vector3.new(0, -0.7, 0)
				a1.Parent = part
				tr = Instance.new("Trail")
				tr.Name = "PunchWhoosh"
				tr.Attachment0, tr.Attachment1 = a0, a1
				tr.Lifetime = 0.26
				tr.MinLength = 0.02
				tr.FaceCamera = true
				tr.LightEmission = 1
				tr.LightInfluence = 0
				tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
				tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.15), NumberSequenceKeypoint.new(1, 0.05) })
				tr.Enabled = false
				tr.Parent = LocalFX
				whooshes[part] = tr
				part.AncestryChanged:Connect(function(_, parent)
					if not parent then
						tr:Destroy()
					end
				end)
			end
			local TS = trailStyle()
			if not (TS and type(trailId) == "string" and trailId ~= "" and TS.apply(tr, trailId)) then
				if TS then
					TS.apply(tr, "") -- a reused whoosh drops a Trail Pack look its caster just unequipped
				end
				tr.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			end
			tr:Clear()
			tr.Enabled = true
			local token = (tr:GetAttribute("Tok") or 0) + 1
			tr:SetAttribute("Tok", token)
			task.delay(dur, function()
				if tr.Parent and tr:GetAttribute("Tok") == token then
					tr.Enabled = false
				end
			end)
		end
	end
end

-- punching on the move (2026-11-07): a hand strike thrown while moving drives the upper body only, so the legs keep
-- walking / running under it instead of sliding along in a fighting stance (kicks, spins and finishers keep the whole
-- body). The copies are cached per clip.
local HAND_LIMB = { Right = true, Left = true, Both = true }
local LOWER_JOINTS = { Root = true, RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true, RightAnkle = true, LeftAnkle = true }
local upperCache = setmetatable({}, { __mode = "k" })
local function upperBody(clip)
	local c = upperCache[clip]
	if c then
		return c
	end
	c = table.clone(clip)
	c.keys = {}
	for i, key in ipairs(clip.keys or {}) do
		local k = table.clone(key)
		k.pose = {}
		for name, v in pairs(key.pose or {}) do
			if not LOWER_JOINTS[name] then
				k.pose[name] = v
			end
		end
		c.keys[i] = k
	end
	upperCache[clip] = c
	return c
end
local function onTheMove(char)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return false
	end
	local v = hrp.AssemblyLinearVelocity
	return hum.MoveDirection.Magnitude > 0.1 or Vector3.new(v.X, 0, v.Z).Magnitude > 3
end

local SfxBank = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("SfxBank"))
local function playPunch(caster, combo, finisher)
	local char = caster.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local kitId = caster:GetAttribute("Kit") or "Limitless"
	local style = PunchStyles[kitId]
	local clip = style and ((finisher and style[finisher]) or style[combo] or style[1]) or Clips.Punch[combo] or Clips.Punch[#Clips.Punch]
	if clip.keys and HAND_LIMB[clip.limb or "Right"] and not finisher and not clip.heavy and combo < PUNCH.ComboLength and onTheMove(char) then
		clip = upperBody(clip)
	end
	Animator.play(char, clip)
	local kit = HudKits.byId[kitId]
	-- (2026-11-09) a blade style (Eren's twin swords, PunchStyles[kit].blade): the swords' own trails light up for the
	-- swing instead of the fist whoosh (a Trail Pack look still rides the hands)
	local bladed = false
	local gear = style and style.blade and char:FindFirstChild("ShifterGear")
	if gear then
		local tok = os.clock()
		for _, d in ipairs(gear:GetDescendants()) do
			if d:IsA("Trail") then
				bladed = true
				d.Enabled = true
				d:SetAttribute("M1Tok", tok)
				task.delay(clip.length * 0.75, function()
					if d.Parent and d:GetAttribute("M1Tok") == tok then
						d.Enabled = false
					end
				end)
			end
		end
	end
	local trailId = caster:GetAttribute("EquipTrail")
	-- (2026-11-12, owner: "make sure the normal swinging attacks have proper swooshing sounds") the swing itself is heard
	-- by everyone near it: a short swish (a fuller one on the finisher, a blade swish for sword styles), never the same
	-- variant twice in a row
	SfxBank.play(bladed and "BLADE" or (finisher and "SWING_HEAVY" or "SWING"), hrp, finisher and 0.9 or 0.8, finisher and 0.95 or 1.05)
	if not bladed or (type(trailId) == "string" and trailId ~= "") then
		whoosh(char, clip.limb or ((combo % 2 == 0) and "Left" or "Right"), kit and kit.accent or Color3.fromRGB(190, 200, 255), clip.length * 0.75, trailId)
	end
	-- the flashy layer at full extension: an air-pressure burst at the striking fist / foot, a ground shockwave on
	-- finishers, and camera kick for the caster (bigger for spins / flips / leaps and finishers)
	local color = kit and kit.accent or Color3.fromRGB(190, 200, 255)
	local strikeT = clip.keys and clip.keys[2] and clip.keys[2].t or 0.13
	local final = clip.heavy or combo >= PUNCH.ComboLength
	task.delay(strikeT, function()
		if not hrp.Parent then
			return
		end
		local names = LIMB_PARTS[clip.limb or "Right"] or LIMB_PARTS.Right
		local p = char:FindFirstChild(names[1])
		local look = hrp.CFrame.LookVector
		local pos = (p and p.Position or hrp.Position) + look * (bladed and 2.6 or 0.6)
		StrikeFX.burst(pos, look, color, final and 1.45 or (clip.tricky and 1.25 or 1))
		if final then
			StrikeFX.ground(hrp.Position - Vector3.new(0, 2.9, 0), color, finisher == "slam" and 1.5 or 1)
		end
		if caster == player then
			StrikeFX.shake(final and 1.2 or (clip.tricky and 0.55 or 0.25), final and 0.28 or 0.12)
		end
	end)
	-- (2026-11-12) the swing sound is SfxBank's varied swish, played above (this one fixed sample was the only one)
	return clip
end

-- ROOT MOTION: the attack really carries the body forward (clip.advance studs between clip.adv0 and adv1 - a punch
-- steps in with the strike, a kick's foot lands in front and the body follows after). With a target ahead it
-- closes the gap (up to +2.2 extra, so a planted string keeps connecting) but stops 3.4 studs short of them; a
-- wall ahead stops it. Local caster only - everyone else sees it through normal character replication.
local motionConn
local motionParams = RaycastParams.new()
motionParams.FilterType = Enum.RaycastFilterType.Exclude
local function rootMotion(clip, flat, targetDist)
	local char, _, hrp = myChar()
	if not hrp or not flat or not clip then
		return
	end
	local dist = clip.advance or 1
	if targetDist then
		dist = math.clamp(targetDist - 3.4, 0, dist + 2.2)
	end
	if motionConn then
		motionConn:Disconnect()
		motionConn = nil
	end
	if dist < 0.05 then
		return
	end
	motionParams.FilterDescendantsInstances = { char, workspace:FindFirstChild("NPCs"), LocalFX, workspace:FindFirstChild("CityDebris"),
		workspace:FindFirstChild("KitFX"), workspace:FindFirstChild("FX") }
	local t0, t1 = clip.adv0 or 0.04, clip.adv1 or 0.2
	local start, done = os.clock(), 0
	motionConn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - start - t0) / math.max(t1 - t0, 0.01), 0, 1)
		local want = dist * (a * a * (3 - 2 * a)) - done -- smoothstep: eases in and out of the step
		if not hrp.Parent then
			a = 1
		elseif want > 0.001 then
			if workspace:Raycast(hrp.Position, flat * (want + 1.6), motionParams) then
				a = 1 -- a wall: stop here
			else
				hrp.CFrame += flat * want
				done += want
			end
		end
		if a >= 1 and motionConn then
			motionConn:Disconnect()
			motionConn = nil
		end
	end)
end

-- (2026-11-07) a click a moment early is held and thrown the instant the swing is allowed, instead of being dropped,
-- and holding M1 keeps the string going - the same feel as Ichigo's and Luffy's M1
local PUNCH_BUFFER = 0.18
local function sharedPunchAllowed()
	local c = player.Character
	return c ~= nil and not c:GetAttribute("Morphed") and not c:GetAttribute("OwnM1")
end
local function punchReadyAt()
	return math.max(localPunch.last + PUNCH.SwingInterval, localPunch.lockUntil)
end

-- (2026-11-09) M1 AIMS AT THE MOUSE: the swing goes toward the world point under the cursor (flat, from the body),
-- not along the camera. Touch-only devices, shift-lock and first person have the cursor at the screen centre, which is
-- the camera heading as before. (Kept on localPunch: this script is near Luau's local limit.)
localPunch.rayParams = RaycastParams.new()
localPunch.rayParams.FilterType = Enum.RaycastFilterType.Exclude
localPunch.mouseAim = function(hrp)
	local cam = workspace.CurrentCamera
	local look = getAim()
	if debugAim or not cam or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
		return look
	end
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local skip = { player.Character, LocalFX }
	for _, n in ipairs({ "FX", "KitFX", "KitDebris", "CityDebris", "DamageNumbers" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	localPunch.rayParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, localPunch.rayParams)
	local point = hit and hit.Position or ray.Origin + ray.Direction * 300
	local off = (point - hrp.Position) * Vector3.new(1, 0, 1)
	if off.Magnitude < 1.5 then
		return look
	end
	return off.Unit
end

local function tryPunch()
	local char, _, hrp = myChar()
	if not char or lockState then
		return
	end
	local t = os.clock()
	local readyAt = punchReadyAt()
	if t < readyAt then
		if readyAt - t <= PUNCH_BUFFER and not localPunch.buffered then
			localPunch.buffered = true
			task.delay(readyAt - t, function()
				localPunch.buffered = false
				if isGojo() or sharedPunchAllowed() then
					tryPunch()
				end
			end)
		end
		return
	end
	if t - localPunch.last > PUNCH.ComboResetTime then
		localPunch.combo = 0
	end
	localPunch.combo = localPunch.combo % PUNCH.ComboLength + 1
	localPunch.last = t
	-- the finisher (hit 5) changes with what you are doing: holding SPACE = a launcher, in the air = a slam
	local finisher
	if localPunch.combo >= PUNCH.ComboLength then
		localPunch.lockUntil = t + PUNCH.FinalCooldown
		local hum = char:FindFirstChildOfClass("Humanoid")
		local st = hum and hum:GetState()
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			finisher = "launch"
		elseif st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
			finisher = "slam"
		end
	end
	local aim, flat = clampAim(localPunch.mouseAim(hrp))
	if flat then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
	end
	-- pressure step: if someone is just out of reach ahead, each strike steps in (a short committed lunge, not
	-- walking) so a planted string keeps connecting as the target gets knocked back
	if flat then
		local best
		local function consider(m)
			local r = m ~= char and m:FindFirstChild("HumanoidRootPart")
			if r then
				local off = (r.Position - hrp.Position) * Vector3.new(1, 0, 1)
				local d = off.Magnitude
				if d > 0.5 and d < 11 and off.Unit:Dot(flat) > 0.6 and (not best or d < best) then
					best = d
				end
			end
		end
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			for _, m in ipairs(npcs:GetChildren()) do
				consider(m)
			end
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				consider(pl.Character)
			end
		end
		localPunch.targetDist = best
	else
		localPunch.targetDist = nil
	end
	-- the swing's window: the walk input carries on through it, slowed (2026-11-07 - it used to plant the feet, which
	-- made M1 unusable on the move). Hand strikes keep most of the pace, kicks / spins less, the finisher least.
	localPunch.rootUntil = t + ((localPunch.combo >= PUNCH.ComboLength) and 0.58 or (localPunch.combo >= 3) and 0.46 or 0.42)
	local clip = playPunch(player, localPunch.combo, finisher)
	localPunch.moveScale = (finisher or localPunch.combo >= PUNCH.ComboLength) and 0.3
		or ((clip and HAND_LIMB[clip.limb or "Right"]) and 0.7 or 0.45)
	rootMotion(clip, flat or (hrp.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit, localPunch.targetDist)
	AbilityRequest:FireServer("Punch", { aimDir = aim or hrp.CFrame.LookVector, finisher = finisher })
end

-- runs right after the control module writes this frame's movement (Input priority) and scales it down while a swing
-- is out (localPunch.moveScale), so you keep moving through a combo and the full pace returns when the swing ends
RunService:BindToRenderStep("PunchRoot", Enum.RenderPriority.Input.Value + 1, function()
	if os.clock() < (localPunch.rootUntil or 0) then
		local c = player.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h then
			h:Move(h.MoveDirection * (localPunch.moveScale or 0.7), false)
		end
	end
end)

-- other kits' HUDs (their PUNCH button) throw the shared punch combo through this
do
	local sharedPunch = Instance.new("BindableEvent")
	sharedPunch.Name = "SharedPunch"
	sharedPunch.Event:Connect(function()
		-- OwnM1: a kit that swings its own M1 (Ichigo's sword) sets this on the character
		if not (player.Character and (player.Character:GetAttribute("Morphed") or player.Character:GetAttribute("OwnM1"))) then
			tryPunch()
		end
	end)
	sharedPunch.Parent = script
end

---------------------------------------------------------------------------------------------------
-- Lapse Blue: hold Q (or the Blue button) to grab a ragdoll with telekinesis; release to throw it where you look
local blue = { holding = nil, nextSend = 0 }
local held = {} -- [userId] = { model, orb, beam, a0, a1, track } visuals for every grab in the server
local npcRay = RaycastParams.new()
npcRay.FilterType = Enum.RaycastFilterType.Include
local mouse = player:GetMouse()

local function aimRay()
	local cam = workspace.CurrentCamera
	if debugAim then
		return cam.CFrame.Position, debugAim
	end
	local ray
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	else
		ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
	end
	return ray.Origin, ray.Direction.Unit
end

local function npcModelOf(inst)
	local m = inst and inst:FindFirstAncestorOfClass("Model")
	while m and not CollectionService:HasTag(m, NPCCFG.Tag) do
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return m
end

-- (2026-11-10, "Blue doesn't grab people") another player can be grabbed too: CombatService.startGrab only marks them and
-- their own client does the hold (SelfHold, below). Skipped exactly as the server refuses: my own body, the dead, the
-- spawn-protected, one already held, and the forms that are immune or too big to grab.
function blue.grabbablePlayer(m)
	local pl = m and Players:GetPlayerFromCharacter(m)
	if not pl or pl == player or m:FindFirstChildOfClass("ForceField") or m:GetAttribute("GrabbedBy") or not m:FindFirstChild("UpperTorso") then
		return false
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 or m:GetAttribute("AscForm") == "Instinct" then
		return false
	end
	for _, a in ipairs({ "SuperArmor", "Guardian", "Morphed", "TitanForm", "FoxBeast" }) do
		if m:GetAttribute(a) then
			return false
		end
	end
	return true
end

-- what the player is pointing at, with a generous aim assist toward the body nearest the aim line
local function pickTarget()
	local _, _, hrp = myChar()
	if not hrp then
		return nil
	end
	-- the dummies plus every grabbable player (2026-11-10: it used to be workspace.NPCs only)
	local folder = workspace:FindFirstChild("NPCs")
	local include, cands = {}, {}
	if folder then
		table.insert(include, folder)
		for _, n in ipairs(folder:GetChildren()) do
			table.insert(cands, n)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if blue.grabbablePlayer(pl.Character) then
			table.insert(include, pl.Character)
			table.insert(cands, pl.Character)
		end
	end
	if #include == 0 then
		return nil
	end
	local origin, dir = aimRay()
	npcRay.FilterDescendantsInstances = include
	local hit = workspace:Raycast(origin, dir * (BLUE.Range + 60), npcRay)
	local m = hit and npcModelOf(hit.Instance)
	if hit and not m then
		-- a player's limb or accessory: climb to the character
		m = hit.Instance:FindFirstAncestorOfClass("Model")
		while m and not Players:GetPlayerFromCharacter(m) do
			m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
		end
	end
	if m and not m:GetAttribute("GrabbedBy") then
		return m
	end
	local best, bestScore
	for _, n in ipairs(cands) do
		local t = n:FindFirstChild("UpperTorso")
		if t and not n:GetAttribute("GrabbedBy") and (t.Position - hrp.Position).Magnitude <= BLUE.Range then
			local rel = t.Position - origin
			local along = rel:Dot(dir)
			if along > 0 then
				local allowance = 4 + along * 0.07
				local perp = (rel - dir * along).Magnitude
				if perp <= allowance then
					local score = perp / allowance + along / BLUE.Range
					if not bestScore or score < bestScore then
						best, bestScore = n, score
					end
				end
			end
		end
	end
	return best
end

local function holdPoint()
	local _, _, hrp = myChar()
	if not hrp then
		return nil
	end
	local look = (debugAim or workspace.CurrentCamera.CFrame.LookVector).Unit
	return hrp.Position + Vector3.yAxis * BLUE.HoldHeight + look * BLUE.HoldDistance
end

local function startBlue(targetOverride)
	local char, _, hrp = myChar()
	if not char or blue.holding or lockState or now() < cooldownEnd.Blue then
		return
	end
	local m = targetOverride or pickTarget()
	if not m then
		-- nothing to grab: a palm thrust and a little vortex closing on empty air, so the press still reads
		local p = hrp.Position + workspace.CurrentCamera.CFrame.LookVector * 4 + Vector3.yAxis * 1.5
		pcall(BlueFX.fizzle, LimitlessPerk.root(LimitlessPerk.alt(player)), p)
		Animator.play(char, Clips.BlueFizzle)
		return
	end
	blue.holding = m
	blue.nextSend = 0
	AbilityRequest:FireServer("BlueGrab", { action = "start", target = m })
end

local function releaseBlue()
	if not blue.holding then
		return
	end
	blue.holding = nil
	AbilityRequest:FireServer("BlueGrab", { action = "release", dir = (debugAim or workspace.CurrentCamera.CFrame.LookVector) })
end

local function clearHeld(userId)
	local h = held[userId]
	if not h then
		return
	end
	held[userId] = nil
	if h.fx then
		pcall(h.fx.release, h.fx, false)
		h.fx = nil
	end
	if h.orb then
		h.orb:destroy(0.15)
	end
	for _, k in ipairs({ "beam", "a0", "a1" }) do
		if h[k] then
			h[k]:Destroy()
		end
	end
	if h.track then
		h.track:stop(0.2)
	end
end

local function onBlueGrab(data)
	local uid = data.userId
	local m = data.model
	clearHeld(uid)
	local ut = typeof(m) == "Instance" and m:FindFirstChild("UpperTorso")
	if not ut then
		return
	end
	local caster = Players:GetPlayerByUserId(uid)
	local char = caster and caster.Character
	local h = { model = m }
	h.alt = LimitlessPerk.alt(caster) -- CRIMSON VOID: this grab's VFX live in the recoloured folder
	h.root = LimitlessPerk.root(h.alt)
	h.orb = VFX.orb("Blue", h.root)
	h.orb:setRadius(1.7)
	local hand = char and char:FindFirstChild("LeftHand")
	if hand then
		h.a0 = Instance.new("Attachment")
		h.a0.Parent = hand
		h.a1 = Instance.new("Attachment")
		h.a1.Parent = ut
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = h.a0, h.a1
		beam.Color = ColorSequence.new(Color3.fromRGB(120, 190, 255), Color3.fromRGB(60, 120, 255))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0, beam.Width1 = 0.35, 1.3
		beam.FaceCamera = true
		beam.Segments = 16
		beam.CurveSize0 = 3
		beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 3
		beam.TextureSpeed = 3
		beam.Transparency = NumberSequence.new(0.1, 0.35)
		beam.Parent = hand
		h.beam = LimitlessPerk.paint(h.alt, beam)
	end
	if char then
		h.track = Animator.play(char, Clips.BlueHold)
		h.legs = Animator.play(char, Clips.BlueGrabLegs)
	end
	VFX.sound(VFX.Sounds.Blue, ut, 0.7, 1.25)
	-- the grab snaps shut: a ring collapses onto the body, light is sucked in, lightning jumps from the hand
	local okFx, fx = pcall(BlueFX.grab, h.root, char, m)
	h.fx = okFx and fx or nil
	local up = ut.Position
	FX.ring(h.root, up, camFacing(up), 16, 1, BLUE_C, 0.28, { ease = "in" })
	FX.streaks(h.root, up, { inward = 14, color = WHITE, color2 = BLUE_C, count = 40, life = 0.3, size = 0.5 })
	FX.glow(h.root, up, 10, Color3.fromRGB(140, 200, 255), 0.3)
	if hand then
		FX.glow(h.root, hand.Position, 4, Color3.fromRGB(160, 215, 255), 0.25)
		FX.bolt(h.root, hand.Position, up, { color = BLUE_C, width = 0.18, jag = 0.12, life = 0.18, restrike = 2, light = true })
	end
	if caster == player then
		FX.speedLines(0.2, { color = LimitlessPerk.sk(h.alt, Color3.fromRGB(190, 225, 255)), alpha = 0.45, inner = 0.5 })
	end
	held[uid] = h
end

local function onBlueRelease(data)
	local h = held[data.userId]
	local ut = h and h.model and h.model:FindFirstChild("UpperTorso")
	if h and h.fx then
		pcall(h.fx.release, h.fx, data.thrown == true)
		h.fx = nil
	end
	if ut and data.thrown then
		local root = h.root or LocalFX
		VFX.burst(root, ut.Position, Color3.fromRGB(110, 180, 255), 16, 1, 30)
		VFX.sound(VFX.Sounds.Swing, ut, 0.8, 0.8)
		local dir = (typeof(data.dir) == "Vector3" and data.dir.Magnitude > 0.1) and data.dir.Unit or -camFacing(ut.Position)
		FX.glow(root, ut.Position, 12, Color3.fromRGB(150, 210, 255), 0.3, { brightness = 3 })
		FX.ring(root, ut.Position, dir, 2, 18, BLUE_C, 0.35)
		FX.ring(root, ut.Position + dir * 3, dir, 1, 11, WHITE, 0.25)
		FX.streaks(root, ut.Position, { dir = dir, spread = 18, color = WHITE, color2 = BLUE_C, count = 30, speed = { 90, 180 }, size = 0.6, life = 0.3 })
		local caster = Players:GetPlayerByUserId(data.userId)
		if caster and caster.Character then
			Animator.play(caster.Character, Clips.BlueThrow)
		end
		if data.userId == player.UserId then
			FX.speedLines(0.28, { color = LimitlessPerk.sk(h.alt, Color3.fromRGB(190, 225, 255)), alpha = 0.6, inner = 0.4 })
			addEnvelope({ fov = 6, shake = 0.3, freq = 22, attack = 0.02, release = 0.3 })
		end
	end
	clearHeld(data.userId)
	if data.userId == player.UserId then
		blue.holding = nil
	end
end

local function updateBlue(dt)
	for uid, h in pairs(held) do
		local ut = h.model and h.model.Parent and h.model:FindFirstChild("UpperTorso")
		if ut then
			h.orb:place(ut.Position, dt)
			if h.fx then
				pcall(h.fx.tick, h.fx, dt)
			end
			-- the pull drags the ground up into it, and the singularity crackles
			if os.clock() >= (h.nextPull or 0) then
				h.nextPull = os.clock() + 0.3
				local g = FX.groundHit(ut.Position, 30)
				if g then
					FX.ring(h.root or LocalFX, g.Position + Vector3.yAxis * 0.2, Vector3.yAxis, 12, 1.5, BLUE_C, 0.35, { ease = "in", alpha = 0.5, brightness = 1.6 })
					FX.streaks(h.root or LocalFX, g.Position + Vector3.yAxis * 0.5, { dir = ut.Position - g.Position, spread = 25, color = Color3.fromRGB(170, 210, 255), count = 6, speed = { 20, 40 }, size = 0.35, life = 0.5 })
				end
				FX.arcs(h.root or LocalFX, ut.Position, 3.2, { count = 1, color = BLUE_C, width = 0.06 })
			end
		else
			clearHeld(uid)
		end
	end
	if blue.holding then
		if not blue.holding.Parent or not myChar() then
			blue.holding = nil
		elseif os.clock() >= blue.nextSend then
			blue.nextSend = os.clock() + 1 / 30
			local p = holdPoint()
			if p then
				GrabMove:FireServer(p)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Reversal: Red (R): charge at the fingertip, fire, and the server tells us where it went off
local redCasts = {} -- [key] = cast
local pendingRed = nil
local RED_TINT = Color3.fromRGB(255, 205, 200)

local function fingertip(char)
	local hand = char and char:FindFirstChild("RightHand")
	if not hand then
		return nil
	end
	-- the fingers point down the hand's -Y, which is forward while the arm is pointing
	return hand.Position - hand.CFrame.UpVector * (hand.Size.Y / 2 + 0.35)
end

local function finalizeRed(cast)
	if cast.final then
		return
	end
	cast.final = true
	redCasts[cast.key] = nil
	if cast.isLocal then
		unlockMovement(cast)
	end
	if cast.orb then
		cast.orb:destroy(0.1)
		cast.orb = nil
	end
	local folder = cast.folder
	task.delay(3, function()
		folder:Destroy()
	end)
end

local function cancelRed(cast)
	if not cast or cast.final then
		return
	end
	if cast.track then
		cast.track:stop(0.12)
	end
	clearEnvelopes(cast)
	if pendingRed == cast then
		pendingRed = nil
	end
	finalizeRed(cast)
end

local function redDetonate(cast, pos, radius)
	if cast.detonated then
		return
	end
	cast.detonated = true
	radius = radius or RED.BlastRadius
	if cast.orb then
		cast.orb:destroy(0.05)
		cast.orb = nil
	end
	local f = cast.folder
	VFX.flash(f, pos, radius * 0.5, Color3.fromRGB(255, 230, 220), 0.28)
	VFX.flash(f, pos, radius * 1.05, Color3.fromRGB(255, 55, 45), 0.55)
	VFX.burst(f, pos, Color3.fromRGB(255, 110, 80), 45, 1.8, 70)
	VFX.burst(f, pos, Color3.fromRGB(255, 240, 230), 20, 1.1, 45)
	local g = groundBelow(pos, nil)
	if (pos - g).Magnitude < radius then
		VFX.shockwave(f, g + Vector3.yAxis * 0.25, Vector3.yAxis, 4, radius * 2.3, Color3.fromRGB(255, 70, 60), 0.55)
		VFX.dust(f, g, radius * 0.3, 18)
	end
	VFX.sound(VFX.Sounds.Launch, VFX.anchor(f, pos, 6), 1, 1.15)
	VFX.sound(VFX.Sounds.Red, VFX.anchor(f, pos, 4), 0.8, 0.7)
	local cam = workspace.CurrentCamera
	local k = math.clamp(1 - (cam.CFrame.Position - pos).Magnitude / 220, 0, 1)
	if k > 0 then
		addEnvelope({ tag = cast, shake = 1.3 * k, freq = 24, attack = 0.02, hold = 0.05, release = 0.5 })
		addEnvelope({ tag = cast, fov = 7 * k, attack = 0.03, release = 0.4 })
		addEnvelope({ tag = cast, tint = LimitlessPerk.sk(cast.alt, RED_TINT), bright = 0.12 * k, contrast = 0.1 * k, attack = 0.02, release = 0.5 })
	end
	FX.glow(f, pos, radius * 0.9, Color3.fromRGB(255, 245, 240), 0.25, { brightness = 4 })
	FX.glow(f, pos, radius * 2, Color3.fromRGB(255, 60, 45), 0.6, { brightness = 2.5 })
	FX.shell(f, pos, 1, radius * 0.8, Color3.fromRGB(255, 70, 50), 0.4)
	FX.shell(f, pos, 1, radius * 1.1, Color3.fromRGB(255, 120, 90), 0.55, Enum.Material.ForceField)
	FX.ring(f, pos, Vector3.yAxis, 2, radius * 2.6, Color3.fromRGB(255, 90, 70), 0.55)
	FX.ring(f, pos, camTilt(pos), 2, radius * 2, Color3.fromRGB(255, 220, 210), 0.45)
	FX.ring(f, pos, camTilt(pos), 2, radius * 1.7, RED_C, 0.5)
	FX.streaks(f, pos, { color = Color3.fromRGB(255, 240, 230), color2 = RED_C, count = 70, speed = { 120, 240 }, size = 0.9, life = 0.4, stretch = 3 })
	FX.arcs(f, pos, radius * 0.55, { outward = true, count = 7, colors = { RED_C, Color3.fromRGB(255, 200, 180), WHITE }, width = 0.22, life = 0.22 })
	FX.sparks(f, pos, { color = Color3.fromRGB(255, 200, 150), color2 = RED_C, count = 40, speed = { 30, 80 }, size = 0.8, life = 1.1, accel = Vector3.new(0, -45, 0) })
	FX.light(f, pos, RED_C, 12, 60, 0.6)
	if (pos - g).Magnitude < radius then
		FX.rubble(f, g, { count = 14, radius = 4, up = { 30, 60 }, out = { 20, 50 } })
	end
	if k > 0.5 then
		FX.impact({ tint = LimitlessPerk.sk(cast.alt, Color3.fromRGB(255, 228, 222)), lineColor = LimitlessPerk.sk(cast.alt, Color3.fromRGB(255, 205, 195)), lineTime = 0.3 })
	end
end

local function newRedCast(caster, data, isLocal)
	local e = now() - data.startServerTime
	local flightEnd = data.launchTime + data.range / math.max(data.speed, 1) + 0.4
	if e > flightEnd then
		return nil
	end
	local cast = { caster = caster, data = data, isLocal = isLocal, lockTime = RED.LockTime, key = data.castId or ("redlocal" .. tostring(os.clock())) }
	cast.folder = Instance.new("Folder")
	cast.folder.Name = "Red_" .. tostring(cast.key)
	cast.alt = LimitlessPerk.alt(caster)
	cast.folder.Parent = LimitlessPerk.root(cast.alt)
	local char = caster.Character
	if char and e < Clips.Red.length then
		cast.track = Animator.play(char, Clips.Red, { startAt = math.max(e, 0) })
	end
	if isLocal and e < RED.LockTime then
		local _, flat = clampAim(data.dir)
		lockMovement(cast, flat or Vector3.new(0, 0, -1))
	end
	redCasts[cast.key] = cast
	return cast
end

local function adoptRed(cast, sd)
	local drift = sd.startServerTime - cast.data.startServerTime
	redCasts[cast.key] = nil
	cast.key = sd.castId
	cast.data = sd
	redCasts[cast.key] = cast
	if math.abs(drift) > 0.15 and cast.track and cast.track:isPlaying() then
		cast.track:setTime(math.max(now() - sd.startServerTime, 0))
	end
end

local function updateRed(cast, dt)
	if cast.final then
		return
	end
	local d = cast.data
	local e = now() - d.startServerTime
	local char = cast.caster and cast.caster.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if cast.isLocal and lockState and lockState.owner == cast and hrp and cast.faceDir then
		local want = CFrame.lookAt(Vector3.zero, cast.faceDir)
		local cur = hrp.CFrame - hrp.Position
		hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-16 * dt))
	end
	if cast.isLocal and e >= cast.lockTime then
		unlockMovement(cast)
	end
	-- charge: a crackling red orb grows at the fingertip
	if e >= 0.1 and not cast.orb and not cast.launched and not cast.detonated then
		cast.orb = VFX.orb("Red", cast.folder)
		VFX.sound(VFX.Sounds.Red, cast.orb.core, 0.8, 1.05)
		local g = groundBelow(hrp and hrp.Position or d.origin, char)
		FX.ring(cast.folder, g + Vector3.yAxis * 0.3, Vector3.yAxis, 3, 20, RED_C, 0.45, { alpha = 0.1 })
		VFX.dust(cast.folder, g, 2.5, 6)
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		-- (was: the "REVERSAL: RED" title with its kanji for the caster and nearby viewers)
	end
	if cast.orb and not cast.launched then
		local grow = math.clamp((e - 0.1) / math.max(d.launchTime - 0.1, 0.05), 0, 1)
		cast.orb:setRadius(0.2 + 1.0 * TweenService:GetValue(grow, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		cast.orb:place(fingertip(char) or d.origin, dt)
		local tip = fingertip(char) or d.origin
		if os.clock() >= (cast.nextCharge or 0) then
			cast.nextCharge = os.clock() + 0.075
			cast.chargeTick = (cast.chargeTick or 0) + 1
			FX.arcs(cast.folder, tip, 0.6 + cast.orb.r * 1.4, { count = 1, colors = { RED_C, Color3.fromRGB(255, 190, 160) }, width = 0.06, jag = 0.4 })
			if cast.chargeTick % 2 == 0 then
				FX.ring(cast.folder, tip, camFacing(tip), 6, 0.5, RED_C, 0.2, { ease = "in", alpha = 0.2 })
			end
		end
	end
	-- fired: fly the same line the server simulates until it reports the blast
	if e >= d.launchTime and not cast.detonated then
		if not cast.launched then
			cast.launched = true
			if not cast.orb then
				cast.orb = VFX.orb("Red", cast.folder)
			end
			cast.orb:setRadius(1.4)
			local att = Instance.new("Attachment")
			att.Parent = cast.orb.core
			local trail = Instance.new("ParticleEmitter")
			trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 80, 60), Color3.fromRGB(80, 10, 10))
			trail.LightEmission = 0.7
			trail.LightInfluence = 0
			trail.Size = NumberSequence.new(1.3, 2.6)
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			trail.Lifetime = NumberRange.new(0.35, 0.6)
			trail.Speed = NumberRange.new(0.5, 2)
			trail.SpreadAngle = Vector2.new(180, 180)
			trail.Rate = 90
			trail.LockedToPart = false
			trail.Parent = att
			VFX.burst(cast.folder, d.origin, Color3.fromRGB(255, 120, 90), 16, 0.9, 30)
			VFX.sound(VFX.Sounds.Swing, VFX.anchor(cast.folder, d.origin, 3), 0.9, 0.6)
			FX.glow(cast.folder, d.origin, 9, Color3.fromRGB(255, 235, 225), 0.22, { brightness = 4 })
			FX.glow(cast.folder, d.origin, 16, RED_C, 0.4, { brightness = 2.5 })
			FX.ring(cast.folder, d.origin + d.dir * 1.5, d.dir, 1.5, 14, Color3.fromRGB(255, 120, 100), 0.3)
			FX.ring(cast.folder, d.origin + d.dir * 4, d.dir, 1, 9, Color3.fromRGB(255, 230, 220), 0.22)
			FX.streaks(cast.folder, d.origin, { dir = d.dir, spread = 14, color = Color3.fromRGB(255, 240, 230), color2 = RED_C, count = 36, speed = { 100, 220 }, size = 0.5, life = 0.28 })
			FX.light(cast.folder, d.origin, RED_C, 9, 30, 0.3)
			FX.trail(cast.orb.core, ColorSequence.new(Color3.fromRGB(255, 235, 225), RED_C), 2.2, 0.22, { tail = 0, brightness = 3 })
			if cast.isLocal then
				FX.speedLines(0.25, { color = Color3.fromRGB(255, 225, 215), alpha = 0.6, inner = 0.45 })
			end
			if cast.isLocal then
				addEnvelope({ tag = cast, fov = 4, shake = 0.25, freq = 20, attack = 0.02, release = 0.25 })
			end
		end
		local dist = math.clamp((e - d.launchTime) * d.speed, 0, d.range)
		local pos = d.origin + d.dir * dist
		if cast.orb then
			cast.orb:place(pos, dt)
		end
		if cast.orb and os.clock() >= (cast.nextRing or 0) then
			cast.nextRing = os.clock() + 0.05
			FX.ring(cast.folder, pos - d.dir * 1.2, d.dir, 1.6, 6.5, Color3.fromRGB(255, 120, 100), 0.22, { alpha = 0.3 })
			FX.arcs(cast.folder, pos, 1.9, { count = 1, colors = { RED_C, Color3.fromRGB(255, 200, 180) }, width = 0.07 })
		end
		if dist >= d.range and e > d.launchTime + d.range / d.speed + 0.35 then
			redDetonate(cast, pos) -- the server's blast message never arrived: go off at the end of the range
		end
	end
	if cast.detonated and e >= cast.lockTime then
		finalizeRed(cast)
	end
end

local function startLocalRed()
	local char, _, hrp = myChar()
	if not char or lockState or pendingRed or pendingLocal or now() < cooldownEnd.Red then
		return
	end
	if blue.holding then
		releaseBlue()
	end
	local aim, flat = clampAim(redAim(hrp)) -- (2026-11-08) level / at a body, never the camera's downward look
	if not aim then
		return
	end
	local right = flat:Cross(Vector3.yAxis)
	local data = {
		castId = nil, startServerTime = now(), dir = aim, launchTime = RED.LaunchTime, speed = RED.Speed, range = RED.Range,
		origin = hrp.Position + flat * RED.OriginForward + right * RED.OriginRight + Vector3.yAxis * RED.OriginUp,
	}
	local cast = newRedCast(player, data, true)
	if not cast then
		return
	end
	pendingRed = cast
	cooldownEnd.Red = now() + RED.Cooldown * LimitlessPerk.cd(false)
	AbilityRequest:FireServer("Red", { aimDir = aim })
	task.delay(1.2, function()
		if pendingRed == cast then
			cancelRed(cast)
			cooldownEnd.Red = 0
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Domain Expansion: Unlimited Void (G): hand-sign cinematic, the expanding dome, the void inside, the shatter
local domainFx = {} -- [castId] = d
local warp = nil -- the starlight rush that follows the camera while it is inside a void (GojoFX.warpField)
local VOID_TINT = Color3.fromRGB(196, 214, 255)
local GLYPHS = { "無量空処", "領域展開", "∞", "無限", "情報", "空", "虚", "∞ ∞", "無下限", "01101001", "10010110", "0110" }
local Lighting = game:GetService("Lighting")

local function domainPart(parent, shape, material, color, size, cf)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = material
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cameraInside(d)
	return not d.collapsed and d.radius > 2 and (workspace.CurrentCamera.CFrame.Position - d.data.center).Magnitude < d.radius - 1
end

-- the void look: night sky full of stars, dark cool ambience, clear air, hot bloom, a cold colour grade.
-- Two weights: w = inside a void (0 = normal world, 1 = inside), dim = how dark the world gets (the lighting and the
-- terrain colours). dim is 1 inside and DIM_OUTSIDE for a camera outside while any void stands, so the floating,
-- highlighted bodies stand out from anywhere. Everything is restored exactly once both return to 0.
local voidSaved, voidW, voidCC = nil, 0, nil
-- every terrain material, so the ground can be darkened while the void stands (client-side only; nobody else sees it)
local TERRAIN_MATS = {}
for _, mat in ipairs(Enum.Material:GetEnumItems()) do
	if pcall(function()
		return workspace.Terrain:GetMaterialColor(mat)
	end) then
		table.insert(TERRAIN_MATS, mat)
	end
end
local VOID_GROUND = Color3.fromRGB(6, 7, 14)
-- (2026-11-08) 0: a camera OUTSIDE a standing void sees the normal world (it was 0.65, which darkened the whole map
-- for everyone while any void stood - back when the void floated every body on the map)
local DIM_OUTSIDE = 0 -- how dark the world gets for a camera OUTSIDE a standing void
local dimW = 0
local function applyVoid(w, dim)
	dim = math.max(dim or w, w)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if dim > 0.001 and not voidSaved then
		voidSaved = {
			ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient, Exposure = Lighting.ExposureCompensation,
			StarCount = sky and sky.StarCount, Celestial = sky and sky.CelestialBodiesShown,
			AtmoDensity = atmo and atmo.Density, AtmoHaze = atmo and atmo.Haze, AtmoGlare = atmo and atmo.Glare,
			BloomI = bloom and bloom.Intensity, BloomT = bloom and bloom.Threshold, BloomS = bloom and bloom.Size,
			Diffuse = Lighting.EnvironmentDiffuseScale, Specular = Lighting.EnvironmentSpecularScale,
			terrain = {}, terrainW = -1,
		}
		for _, mat in ipairs(TERRAIN_MATS) do
			voidSaved.terrain[mat] = workspace.Terrain:GetMaterialColor(mat)
		end
		FX.terrainOriginals = voidSaved.terrain -- rubble and rocks keep the ground's real colour while it is darkened
	end
	local s = voidSaved
	if not s then
		return
	end
	if dim <= 0.001 then
		Lighting.ClockTime, Lighting.Brightness, Lighting.Ambient = s.ClockTime, s.Brightness, s.Ambient
		Lighting.OutdoorAmbient, Lighting.ExposureCompensation = s.OutdoorAmbient, s.Exposure
		if sky then
			sky.StarCount, sky.CelestialBodiesShown = s.StarCount, s.Celestial
		end
		if atmo then
			atmo.Density, atmo.Haze, atmo.Glare = s.AtmoDensity, s.AtmoHaze, s.AtmoGlare
		end
		if bloom then
			bloom.Intensity, bloom.Threshold, bloom.Size = s.BloomI, s.BloomT, s.BloomS
		end
		Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = s.Diffuse, s.Specular
		for mat, col in pairs(s.terrain) do
			workspace.Terrain:SetMaterialColor(mat, col)
		end
		FX.terrainOriginals = nil
		if voidCC then
			voidCC:Destroy()
			voidCC = nil
		end
		voidSaved = nil
		return
	end
	local function lerp(a, b)
		return a + (b - a) * w
	end
	Lighting.ClockTime = (w > 0.5) and 0 or s.ClockTime
	-- the world goes dark round the void so the floating, highlighted bodies (and Gojo) are what you see:
	-- no sun, a faint cold ambient, no environment lighting, and the terrain itself darkened
	local function dlerp(a, b)
		return a + (b - a) * dim
	end
	Lighting.Brightness = dlerp(s.Brightness, 0)
	Lighting.Ambient = s.Ambient:Lerp(LimitlessPerk.voidAlt and LimitlessPerk.ALT.Void.Ambient or Color3.fromRGB(16, 18, 34), dim)
	Lighting.OutdoorAmbient = s.OutdoorAmbient:Lerp(LimitlessPerk.voidAlt and LimitlessPerk.ALT.Void.OutdoorAmbient or Color3.fromRGB(8, 10, 22), dim)
	Lighting.ExposureCompensation = dlerp(s.Exposure, 0.1)
	Lighting.EnvironmentDiffuseScale = dlerp(s.Diffuse, 0)
	Lighting.EnvironmentSpecularScale = dlerp(s.Specular, 0)
	local tw = math.floor(dim * 20 + 0.5) / 20 -- the terrain colours are only re-set in 5% steps
	if tw ~= s.terrainW or s.terrainAlt ~= LimitlessPerk.voidAlt then
		s.terrainW = tw
		s.terrainAlt = LimitlessPerk.voidAlt
		local ground = LimitlessPerk.voidAlt and LimitlessPerk.ALT.Void.Ground or VOID_GROUND
		for mat, col in pairs(s.terrain) do
			workspace.Terrain:SetMaterialColor(mat, col:Lerp(ground, 0.9 * tw))
		end
	end
	if sky then
		sky.StarCount = math.floor(lerp(s.StarCount, 5000))
		sky.CelestialBodiesShown = (w < 0.5) and s.Celestial or false
	end
	if atmo then
		atmo.Density, atmo.Haze, atmo.Glare = lerp(s.AtmoDensity, 0), lerp(s.AtmoHaze, 0), lerp(s.AtmoGlare, 0)
	end
	if bloom then
		bloom.Intensity, bloom.Threshold, bloom.Size = lerp(s.BloomI, 1.35), lerp(s.BloomT, 0.8), lerp(s.BloomS, 40)
	end
	local cam = workspace.CurrentCamera
	if not voidCC or voidCC.Parent ~= cam then
		voidCC = Instance.new("ColorCorrectionEffect")
		voidCC.Name = "VoidGrade"
		voidCC.Parent = cam
	end
	voidCC.TintColor = Color3.new(1, 1, 1):Lerp(LimitlessPerk.voidAlt and LimitlessPerk.ALT.Void.Tint or VOID_TINT, w)
	voidCC.Saturation = -0.12 * w
	voidCC.Contrast = 0.22 * w
end

local function buildInterior(d)
	if d.interior then
		return
	end
	local c, R, facing = d.data.center, d.data.radius, d.data.facing
	local f = Instance.new("Folder")
	f.Name = "Interior"
	f.Parent = d.folder
	d.interior = f
	-- a black mirror floor under everything
	d.floor = domainPart(f, Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, Color3.fromRGB(6, 6, 16), Vector3.new(0.2, R * 1.96, R * 1.96), CFrame.new(c + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	d.floor.Reflectance = 0.55
	-- the cosmic eye overhead: a white-hot core in a blue aura, ringed by three tilted, counter-rotating halos of light
	d.eyePos = c + Vector3.new(0, R * 0.45, 0) + facing * R * 0.2
	d.core = domainPart(f, Enum.PartType.Ball, Enum.Material.Neon, Color3.fromRGB(236, 246, 255), Vector3.one * 12, CFrame.new(d.eyePos))
	d.aura = domainPart(f, Enum.PartType.Ball, Enum.Material.ForceField, Color3.fromRGB(120, 190, 255), Vector3.one * 28, CFrame.new(d.eyePos))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(175, 210, 255)
	light.Brightness = 3
	light.Range = 60
	light.Shadows = false
	light.Parent = d.core
	d.rings = {}
	for i, spec in ipairs({ { 17, 28, Color3.fromRGB(215, 238, 255), 0.35 }, { 26, 36, Color3.fromRGB(120, 165, 255), -0.22 }, { 35, 44, Color3.fromRGB(185, 140, 255), 0.13 } }) do
		local r, n = spec[1], spec[2]
		local segs = {}
		for k = 1, n do
			table.insert(segs, domainPart(f, Enum.PartType.Block, Enum.Material.Neon, spec[3], Vector3.new(r * 2 * math.pi / n * 0.82, 0.18, 0.42), CFrame.new(d.eyePos)))
		end
		table.insert(d.rings, { segs = segs, radius = r, speed = spec[4], tilt = math.rad(14 + i * 11), spin = math.rad(i * 37) })
	end
	-- stars, rushing streaks of "infinite information" and slow nebula clouds filling the dome
	local host = domainPart(f, Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.new(R * 1.5, R * 0.85, R * 1.5), CFrame.new(c + Vector3.new(0, R * 0.45, 0)))
	host.Transparency = 1
	local function emit(props)
		local e = Instance.new("ParticleEmitter")
		e.LightInfluence = 0
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Parent = host
		return e
	end
	emit({
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 200, 255)),
		LightEmission = 1, Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(2.5, 4), Rate = 240, Speed = NumberRange.new(0, 0.5), Rotation = NumberRange.new(0, 360),
	})
	emit({
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 220, 255)),
		LightEmission = 1, Size = NumberSequence.new(0.35), Squash = NumberSequence.new(-3), Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.25, 0.5), Rate = 70, Speed = NumberRange.new(120, 200), SpreadAngle = Vector2.new(180, 180),
	})
	emit({
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(70, 90, 210), Color3.fromRGB(140, 60, 200)),
		LightEmission = 0.45, Size = NumberSequence.new(18, 32), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.82), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(4, 6), Rate = 6, Speed = NumberRange.new(0.5, 2), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-10, 10),
	})
	-- floating fragments of "infinite information"
	d.glyphs = {}
	for i = 1, 30 do
		local a = math.random() * math.pi * 2
		local rr = math.sqrt(math.random()) * R * 0.8
		local base = c + Vector3.new(math.cos(a) * rr, 4 + math.random() * R * 0.45, math.sin(a) * rr)
		local anchor = domainPart(f, Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 0.2, CFrame.new(base))
		anchor.Transparency = 1
		local bb = Instance.new("BillboardGui")
		local w = 5 + math.random() * 7
		bb.Size = UDim2.new(w, 0, w * 0.32, 0)
		bb.LightInfluence = 0
		bb.MaxDistance = 400
		bb.Parent = anchor
		local text = GLYPHS[math.random(#GLYPHS)]
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.TextScaled = true
		l.Font = text:find("^[01 ]+$") and Enum.Font.Code or Enum.Font.GothamBlack
		l.Text = text
		l.TextColor3 = Color3.fromRGB(225, 240, 255):Lerp(Color3.fromRGB(130, 200, 255), math.random())
		l.Parent = bb
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(70, 140, 255)
		st.Transparency = 0.45
		st.Thickness = 1.5
		st.Parent = l
		table.insert(d.glyphs, { anchor = anchor, base = base, label = l, stroke = st, phase = math.random() * math.pi * 2 })
	end
	-- starlight: rays of light streaming out of the eye in every direction, and a galaxy turning beneath it
	d.rays = FX.rays(f, d.eyePos, R * 0.95, 110, {
		Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 230, 255), Color3.fromRGB(150, 195, 255), Color3.fromRGB(205, 175, 255),
	})
	d.galaxy = FX.galaxy(f, d.eyePos - Vector3.yAxis * 3, R * 0.55, math.rad(16), {
		Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 215, 255), Color3.fromRGB(140, 170, 255), Color3.fromRGB(210, 170, 255),
	}, 140)
end

local function startDomainCinematic(d)
	local cam = workspace.CurrentCamera
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	if not hrp or not head then
		return
	end
	d.cinematic = true
	cam.CameraType = Enum.CameraType.Scriptable
	local facing = d.data.facing
	local yaw = math.atan2(-facing.X, -facing.Z)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not d.cinematic or not hrp.Parent or not head.Parent then
			conn:Disconnect()
			d.cinematic = false
			cam.CameraType = Enum.CameraType.Custom
			return
		end
		local e = now() - d.data.startServerTime
		-- keep the avatar visible even if the player was zoomed into first person
		for _, p in ipairs(char:GetDescendants()) do
			if (p:IsA("BasePart") and p.Name ~= "HumanoidRootPart") or p:IsA("Decal") then
				p.LocalTransparencyModifier = 0
			end
		end
		local headPos = head.Position
		local base = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0)
		local camCF
		if e < 0.72 then
			-- 1) close on the seal, slowly pushing in with a slight roll
			local a = TweenService:GetValue(math.clamp(e / 0.72, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			local pos = (base * CFrame.new(1.1 - 0.4 * a, 1.7, -(6 - 2.2 * a))).Position
			camCF = CFrame.lookAt(pos, headPos - Vector3.yAxis * 0.2) * CFrame.Angles(0, 0, math.rad(-8 * a))
		elseif e < 1.3 then
			-- 2) rip back and up as the dome swallows everything
			local a = TweenService:GetValue(math.clamp((e - 0.72) / 0.58, 0, 1), Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
			local p0 = (base * CFrame.new(0.7, 1.7, -3.8)).Position
			local p1 = (base * CFrame.new(-16, 32, -50)).Position
			camCF = CFrame.lookAt(p0:Lerp(p1, a), headPos:Lerp(hrp.Position + Vector3.yAxis * 6, a))
		elseif e < 2.85 then
			-- 3) inside the void: a sweeping orbit around Gojo under the cosmic eye
			local s = TweenService:GetValue(math.clamp((e - 1.3) / 1.55, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local pos = (base * CFrame.Angles(0, math.rad(-70 + 150 * s), 0) * CFrame.new(0, 2.5 + 3.5 * s, -(15 - 5 * s))).Position
			camCF = CFrame.lookAt(pos, headPos + Vector3.yAxis * (0.6 + 2.2 * s))
		else
			conn:Disconnect()
			d.cinematic = false
			cam.CameraType = Enum.CameraType.Custom
			return
		end
		cam.CFrame = camCF
	end)
end

local function loopSound(d, id, volume)
	local host = domainPart(d.folder, Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), Vector3.one * 0.2, CFrame.new(d.data.center + Vector3.yAxis * 8))
	host.Transparency = 1
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = d.data.radius
	s.RollOffMaxDistance = d.data.radius * 1.6
	s.Parent = host
	s:Play()
	TweenService:Create(s, TweenInfo.new(0.8), { Volume = volume }):Play()
	return s
end

local function newDomainFx(caster, data)
	local e = now() - data.startServerTime
	if domainFx[data.castId] or e > data.start + data.expandTime + data.duration + 0.5 then
		return nil
	end
	local d = { caster = caster, data = data, isLocal = caster == player, key = data.castId, radius = 0 }
	d.folder = Instance.new("Folder")
	d.folder.Name = "Domain_" .. tostring(data.castId)
	d.alt = LimitlessPerk.alt(caster) -- CRIMSON VOID
	d.folder.Parent = LimitlessPerk.root(d.alt)
	d.dome = domainPart(d.folder, Enum.PartType.Ball, Enum.Material.SmoothPlastic, Color3.fromRGB(3, 3, 9), Vector3.one * 0.2, CFrame.new(data.center))
	d.rim = domainPart(d.folder, Enum.PartType.Ball, Enum.Material.ForceField, Color3.fromRGB(150, 210, 255), Vector3.one * 0.2, CFrame.new(data.center))
	d.dome.Transparency, d.rim.Transparency = 1, 1
	local crawl = Instance.new("ParticleEmitter")
	crawl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	crawl.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.fromRGB(110, 170, 255))
	crawl.LightEmission = 1
	crawl.LightInfluence = 0
	crawl.Size = NumberSequence.new(1.6, 0)
	crawl.Lifetime = NumberRange.new(0.6, 1.1)
	crawl.Speed = NumberRange.new(2, 6)
	crawl.Shape = Enum.ParticleEmitterShape.Sphere
	crawl.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	crawl.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	crawl.Rate = 90
	crawl.Parent = d.rim
	local char = caster.Character
	if char and e < Clips.Domain.length then
		d.track = Animator.play(char, Clips.Domain, { startAt = math.max(e, 0) })
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and e < 0.5 then
		local sw = VFX.sound(DOMAIN.Sounds.Swell, hrp, 0.9, 1.3)
		task.delay(1.4, function()
			if sw.Parent then
				TweenService:Create(sw, TweenInfo.new(0.4), { Volume = 0 }):Play()
			end
		end)
	end
	if d.isLocal and e < DOMAIN.LockTime then
		lockMovement(d, data.facing)
		if e < 0.4 then
			startDomainCinematic(d)
		end
	end
	domainFx[d.key] = d
	return d
end

local function collapseFx(d, early)
	if not d or d.collapsed then
		return
	end
	local c, R = d.data.center, d.data.radius
	local wasInside = cameraInside(d)
	d.collapsed = true
	d.cinematic = false
	if d.keyLight then
		d.keyLight:Destroy()
		d.keyLight = nil
	end
	if wasInside then
		impactFrame()
	end
	VFX.flash(d.folder, c + Vector3.yAxis * 6, R * 0.6, Color3.fromRGB(235, 245, 255), 0.45)
	local shards = Instance.new("ParticleEmitter")
	shards.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shards.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 190, 255))
	shards.LightEmission = 1
	shards.LightInfluence = 0
	shards.Size = NumberSequence.new(2.2, 0)
	shards.Lifetime = NumberRange.new(0.8, 1.5)
	shards.Speed = NumberRange.new(45, 100)
	shards.Acceleration = Vector3.new(0, -70, 0)
	shards.Shape = Enum.ParticleEmitterShape.Sphere
	shards.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	shards.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	shards.Rate = 0
	shards.Parent = d.rim
	shards:Emit(260)
	TweenService:Create(d.dome, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * R * 2.15, Transparency = 1 }):Play()
	TweenService:Create(d.rim, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * R * 2.5, Transparency = 1 }):Play()
	VFX.shockwave(d.folder, c + Vector3.yAxis * 0.3, Vector3.yAxis, R * 1.4, R * 3, Color3.fromRGB(170, 215, 255), 0.65)
	VFX.sound(DOMAIN.Sounds.Shatter, VFX.anchor(d.folder, c + Vector3.yAxis * 6, 6), 1, 0.75)
	VFX.sound(VFX.Sounds.Launch, VFX.anchor(d.folder, c + Vector3.yAxis * 6, 6), 1, 0.65)
	FX.shatter(d.folder, c, R, { count = 54 })
	FX.streaks(d.folder, c + Vector3.yAxis * R * 0.3, { color = WHITE, color2 = Color3.fromRGB(150, 200, 255), count = 140, speed = { 120, 260 }, size = 1.2, life = 0.55, stretch = 3 })
	if d.aura then
		d.aura:Destroy()
		d.aura = nil
	end
	for _, s in ipairs({ d.voidSound, d.droneSound }) do
		if s then
			TweenService:Create(s, TweenInfo.new(0.5), { Volume = 0 }):Play()
		end
	end
	if d.interior then
		for _, inst in ipairs(d.interior:GetDescendants()) do
			if inst:IsA("ParticleEmitter") then
				inst.Enabled = false
			elseif inst:IsA("BasePart") then
				TweenService:Create(inst, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			elseif inst:IsA("BillboardGui") then
				inst.Enabled = false
			end
		end
	end
	local cam = workspace.CurrentCamera
	local k = math.clamp(1 - ((cam.CFrame.Position - c).Magnitude - R) / 200, 0, 1)
	if k > 0 then
		addEnvelope({ tag = d, shake = 1.5 * k, freq = 22, attack = 0.02, hold = 0.08, release = 0.7 })
		addEnvelope({ tag = d, fov = 10 * k, attack = 0.03, release = 0.6 })
		addEnvelope({ tag = d, bright = 0.3 * k, attack = 0.02, release = 0.8, tint = LimitlessPerk.sk(d.alt, Color3.fromRGB(230, 240, 255)) })
	end
	if d.isLocal then
		unlockMovement(d)
	end
	local key, folder = d.key, d.folder
	task.delay(3, function()
		if domainFx[key] == d then
			domainFx[key] = nil
		end
		folder:Destroy()
	end)
end

-- every dummy the void has caught: a bright see-through highlight that pulses, a cold glow and a light of its own
-- (so it reads against the darkened world), sparks at the head, a lift-off flash, and a beam of "information"
-- poured into the head from the eye of the void that caught it
local victimFx = {} -- [model] = { highlight, emitter, aura, light, beam, a0, a1, head, phase }
local MAX_HIGHLIGHTS = 28 -- Roblox draws at most 31 Highlights at once; leave room for other kits
local highlightCount = 0
-- once more bodies are caught than that (the map holds 36), ONE Highlight laid over workspace.NPCs (a Model, so the
-- adornee draws everything inside it) outlines every one of them for the price of a single slot
local groupHighlight = nil

local function attachVictimBeam(m, v)
	local uid = m:GetAttribute("InDomain")
	-- a beam belongs to one void: drop it once that void has ended or the body has passed into another one
	if v.beam and (not v.beam.Parent or v.beamUid ~= uid or (v.beamDomain and v.beamDomain.collapsed)) then
		for _, k in ipairs({ "beam", "a0", "a1" }) do
			if v[k] then
				v[k]:Destroy()
				v[k] = nil
			end
		end
		v.beamDomain, v.beamUid = nil, nil
	end
	if v.beam or not v.head or not v.head.Parent then
		return
	end
	for _, dd in pairs(domainFx) do
		if dd.core and dd.core.Parent and not dd.collapsed and dd.caster and dd.caster.UserId == uid then
			local a0 = Instance.new("Attachment")
			a0.Parent = dd.core
			local a1 = Instance.new("Attachment")
			a1.Parent = v.head
			local beam = Instance.new("Beam")
			beam.Attachment0, beam.Attachment1 = a0, a1
			beam.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255), Color3.fromRGB(120, 185, 255))
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Width0, beam.Width1 = 0.5, 0.18
			beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 3
			beam.TextureSpeed = 4
			beam.Transparency = NumberSequence.new(0.35, 0.15)
			beam.Segments = 10
			beam.Parent = dd.core
			v.beam, v.a0, v.a1 = beam, a0, a1
			v.beamDomain, v.beamUid = dd, uid
			return
		end
	end
end

-- the living outrank corpses: when the cap is full a living body takes a corpse's slot; retried every tick, so a
-- slot freed by a corpse fading away is picked up within 0.2 s
local function tryHighlight(m, v)
	if v.highlight or groupHighlight or m == player.Character then -- (2026-11-10) never an always-on-top glow over my own body
		return
	end
	local dead = m:GetAttribute("Dead") == true
	if highlightCount >= MAX_HIGHLIGHTS and not dead then
		for om, ov in pairs(victimFx) do
			if ov.highlight and om:GetAttribute("Dead") == true then
				ov.highlight:Destroy()
				ov.highlight = nil
				highlightCount -= 1
				break
			end
		end
	end
	if highlightCount < MAX_HIGHLIGHTS and (not dead or highlightCount < MAX_HIGHLIGHTS - 6) then
		local h = Instance.new("Highlight")
		h.FillColor = Color3.fromRGB(228, 242, 255) -- near-white: the void's colour grade tints it blue
		h.FillTransparency = 0.14
		h.OutlineColor = Color3.fromRGB(240, 250, 255)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- seen through everything, even the dome wall
		h.Parent = m
		LimitlessPerk.paint(v.alt, h)
		v.highlight = h
		highlightCount += 1
	end
end

local function clearVictim(m, v)
	if v.highlight then
		highlightCount -= 1
	end
	for _, k in ipairs({ "highlight", "emitter", "aura", "light", "beam", "a0", "a1", "pillar", "pillarBase", "pillarTop" }) do
		if v[k] then
			v[k]:Destroy()
		end
	end
	victimFx[m] = nil
end

local function updateVictims()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	-- (2026-11-10) players caught in a void (CombatService marks them InDomain too) glow and float like the dummies
	local bodies, pchar = CollectionService:GetTagged(NPCCFG.Tag), {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(bodies, pl.Character)
			pchar[pl.Character] = true
		end
	end
	for _, m in ipairs(bodies) do
		-- (a player counts only while it carries a void's VoidHover: other kits may write InDomain on players too)
		local frozen = m:GetAttribute("InDomain") ~= nil and (not pchar[m] or typeof(m:GetAttribute("VoidHover")) == "Vector3")
		local v = victimFx[m]
		if frozen and not v then
			v = { phase = math.random() * math.pi * 2, alt = LimitlessPerk.alt(Players:GetPlayerByUserId(tonumber(m:GetAttribute("InDomain")) or 0)) }
			victimFx[m] = v
			tryHighlight(m, v) -- the living first; corpses only while there is room under the engine's limit
			local head = m:FindFirstChild("Head")
			v.head = head
			if head then
				local e = Instance.new("ParticleEmitter")
				e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 210, 255))
				e.LightEmission = 1
				e.LightInfluence = 0
				e.Size = NumberSequence.new(0.7, 0)
				e.Lifetime = NumberRange.new(0.3, 0.6)
				e.Speed = NumberRange.new(3, 7)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Rate = 22
				e.Parent = head
				v.emitter = LimitlessPerk.paint(v.alt, e)
			end
			local ut = m:FindFirstChild("UpperTorso")
			if ut then
				local a = Instance.new("Attachment")
				a.Name = "VoidGlowAtt"
				a.Parent = ut
				FX.emitter(a, {
					Texture = FX.TEX.glow, Color = ColorSequence.new(Color3.fromRGB(215, 232, 255), Color3.fromRGB(110, 170, 255)),
					Rate = 16, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
					Size = FX.nsk({ { 0, 3 }, { 0.4, 6.5 }, { 1, 8 } }), Transparency = FX.nsk({ { 0, 1 }, { 0.3, 0.55 }, { 1, 1 } }),
					Acceleration = Vector3.new(0, 2, 0), Brightness = 2.2, ZOffset = -1,
				})
				v.aura = a -- destroying the attachment takes its emitter with it
				local l = Instance.new("PointLight")
				l.Color = Color3.fromRGB(170, 210, 255)
				l.Brightness = 2.5
				l.Range = 12
				l.Shadows = false
				l.Parent = ut
				v.light = l
				LimitlessPerk.paint(v.alt, a)
				LimitlessPerk.paint(v.alt, l)
				-- a soft pillar of light from the ground up to the body, so it plainly reads as floating
				local g = FX.groundHit(ut.Position, 20)
				local gp = g and g.Position or (ut.Position - Vector3.yAxis * 3)
				local pa0 = Instance.new("Attachment")
				pa0.Name = "VoidPillarBase"
				pa0.Parent = workspace.Terrain
				pa0.WorldPosition = gp
				local pa1 = Instance.new("Attachment")
				pa1.Name = "VoidPillarTop"
				pa1.Parent = ut
				local pb = Instance.new("Beam")
				pb.Attachment0, pb.Attachment1 = pa0, pa1
				pb.Color = ColorSequence.new(Color3.fromRGB(150, 205, 255), Color3.fromRGB(225, 242, 255))
				pb.Texture = FX.TEX.glow
				pb.TextureMode = Enum.TextureMode.Stretch
				pb.TextureLength = 1
				pb.TextureSpeed = 0
				pb.LightEmission = 1
				pb.LightInfluence = 0
				pb.FaceCamera = true
				pb.Width0, pb.Width1 = 4, 2.2
				pb.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 0.8) })
				pb.Segments = 2
				pb.Parent = ut
				v.pillar, v.pillarBase, v.pillarTop = pb, pa0, pa1
				LimitlessPerk.paint(v.alt, pb)
				-- lift-off: a ring snaps out under it and light streams upward as it leaves the ground
				if (ut.Position - camPos).Magnitude < 260 then
					FX.ring(LimitlessPerk.root(v.alt), gp + Vector3.yAxis * 0.25, Vector3.yAxis, 2, 14, Color3.fromRGB(160, 210, 255), 0.5, { alpha = 0.1 })
					FX.streaks(LimitlessPerk.root(v.alt), gp + Vector3.yAxis * 0.5, { dir = Vector3.yAxis, spread = 12, color = WHITE, color2 = BLUE_C, count = 14, speed = { 30, 60 }, size = 0.45, life = 0.45 })
					FX.glow(LimitlessPerk.root(v.alt), ut.Position, 7, Color3.fromRGB(200, 225, 255), 0.35)
				end
			end
		elseif not frozen and v then
			clearVictim(m, v)
			v = nil
		end
		if frozen and v then
			tryHighlight(m, v)
			attachVictimBeam(m, v)
		end
	end
	for m, v in pairs(victimFx) do
		if not m.Parent then
			clearVictim(m, v)
		end
	end
	-- past the cap, switch to the folder-wide Highlight. The capture wave sweeps the whole map in ~1.5 s, so the folder and
	-- the caught set are the same bodies; back to one Highlight each once the count falls clearly under the cap
	local caught = 0
	for _ in pairs(victimFx) do
		caught += 1
	end
	local npcFolder = workspace:FindFirstChild("NPCs")
	if not groupHighlight and caught > MAX_HIGHLIGHTS and npcFolder and npcFolder:IsA("Model") then -- a Folder adornee draws nothing
		for _, v in pairs(victimFx) do
			if v.highlight then
				v.highlight:Destroy()
				v.highlight = nil
			end
		end
		highlightCount = 0
		local h = Instance.new("Highlight")
		h.Name = "VoidHighlightAll"
		h.FillColor = Color3.fromRGB(228, 242, 255)
		h.FillTransparency = 0.14
		h.OutlineColor = Color3.fromRGB(240, 250, 255)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = npcFolder
		h.Parent = LocalFX
		groupHighlight = h
	elseif groupHighlight and (caught <= MAX_HIGHLIGHTS - 4 or not npcFolder or not groupHighlight.Parent) then
		groupHighlight:Destroy()
		groupHighlight = nil
		for m, v in pairs(victimFx) do
			tryHighlight(m, v)
		end
	end
end

local victimAcc = 0
local function updateDomains(dt)
	local anyInside = false
	local anyActive = false
	local clock = os.clock()
	for key, d in pairs(domainFx) do
		local data = d.data
		local e = now() - data.startServerTime
		local char = d.caster and d.caster.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if d.isLocal and lockState and lockState.owner == d and hrp then
			local want = CFrame.lookAt(Vector3.zero, data.facing)
			local cur = hrp.CFrame - hrp.Position
			hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-10 * dt))
		end
		if d.isLocal and e >= DOMAIN.LockTime then
			unlockMovement(d)
		end
		if not d.collapsed then
			if e >= 0.25 and not d.titled then
				d.titled = true
				if d.isLocal then
					showTitle("DOMAIN EXPANSION", "領域展開", Color3.fromRGB(255, 255, 255), LimitlessPerk.sk(d.alt, Color3.fromRGB(150, 200, 255)), LimitlessPerk.sk(d.alt, Color3.fromRGB(220, 235, 255)))
				end
			end
			local grow = math.clamp((e - data.start) / data.expandTime, 0, 1)
			d.radius = data.radius * TweenService:GetValue(grow, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			if d.radius > 0.5 then
				d.dome.Transparency, d.rim.Transparency = 0, 0.15
				d.dome.Size = Vector3.one * d.radius * 2
				d.rim.Size = Vector3.one * (d.radius * 2 + 2)
				if not d.stung then
					d.stung = true
					VFX.sound(DOMAIN.Sounds.Sting, VFX.anchor(d.folder, data.center + Vector3.yAxis * 4, 6), 1, 1)
					VFX.shockwave(d.folder, data.center + Vector3.yAxis * 0.3, Vector3.yAxis, 6, data.radius * 2.2, Color3.fromRGB(160, 210, 255), data.expandTime + 0.3)
					VFX.flash(d.folder, data.center + Vector3.yAxis * 4, 10, Color3.fromRGB(220, 240, 255), 0.4)
				end
			end
			if grow >= 0.45 and not d.interior then
				buildInterior(d)
			end
			if grow >= 1 and not d.formed then
				d.formed = true
				local inside = cameraInside(d)
				if d.isLocal or inside then
					impactFrame(LimitlessPerk.sk(d.alt, Color3.fromRGB(225, 238, 255)), LimitlessPerk.sk(d.alt, Color3.fromRGB(200, 228, 255)))
					showTitle("UNLIMITED VOID", "無量空処", Color3.fromRGB(255, 255, 255), LimitlessPerk.sk(d.alt, Color3.fromRGB(110, 170, 255)), LimitlessPerk.sk(d.alt, Color3.fromRGB(235, 245, 255)))
				end
				VFX.sound(DOMAIN.Sounds.Hit, VFX.anchor(d.folder, data.center + Vector3.yAxis * 6, 7), 1, 0.85)
				-- the void forms: a supernova of starlight out of the eye
				if d.eyePos then
					FX.streaks(d.folder, d.eyePos, { color = WHITE, color2 = Color3.fromRGB(150, 200, 255), count = 160, speed = { 160, 320 }, size = 1.1, life = 0.5, stretch = 3 })
					FX.glow(d.folder, d.eyePos, 70, Color3.fromRGB(220, 240, 255), 0.6, { brightness = 3 })
					d.rays:burst(1)
				end
				if inside then
					addEnvelope({ tag = d, fov = 24, attack = 0.04, hold = 0.08, release = 0.7 })
					if warp then
						warp:burst(220)
					end
				end
				if hrp then
					d.aura = LimitlessPerk.paint(d.alt, FX.aura(hrp, Color3.fromRGB(190, 225, 255), Color3.fromRGB(120, 170, 255), 45))
				end
				-- a soft cold key light on Gojo so he reads against the void
				if hrp then
					local pl = Instance.new("PointLight")
					pl.Name = "VoidKeyLight"
					pl.Color = LimitlessPerk.sk(d.alt, Color3.fromRGB(175, 215, 255))
					pl.Brightness = 2.6
					pl.Range = 20
					pl.Shadows = false
					pl.Parent = hrp
					d.keyLight = pl
				end
				d.voidSound = loopSound(d, DOMAIN.Sounds.Void, 0.9)
				d.droneSound = loopSound(d, DOMAIN.Sounds.Drone, 0.45)
			end
			if d.interior then
				for _, ring in ipairs(d.rings) do
					local n = #ring.segs
					local frame = CFrame.new(d.eyePos) * CFrame.Angles(ring.tilt, ring.spin, 0)
					for k, seg in ipairs(ring.segs) do
						local a = (k / n) * math.pi * 2 + clock * ring.speed * 2.6
						seg.CFrame = frame * CFrame.Angles(0, -a, 0) * CFrame.new(ring.radius, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
					end
				end
				d.core.Size = Vector3.one * (12 + math.sin(clock * 3) * 0.9)
				d.aura.CFrame = CFrame.new(d.eyePos) * CFrame.Angles(clock * 0.3, clock * 0.5, 0)
				for _, g in ipairs(d.glyphs) do
					g.anchor.CFrame = CFrame.new(g.base + Vector3.new(0, math.sin(clock * 0.6 + g.phase) * 2.2, 0))
					local flicker = (0.5 + 0.5 * math.sin(clock * 2.1 + g.phase)) ^ 3
					g.label.TextTransparency = 0.1 + 0.7 * flicker
					g.stroke.Transparency = 0.45 + 0.5 * flicker
				end
				d.rays:update(dt, d.formed and 1 or 0.6)
				d.galaxy:update(clock)
				-- the rapid pulse of information: the eye flares, a share of the starlight resets, a ring tears outward
				if clock >= (d.nextPulse or 0) then
					d.nextPulse = clock + 0.5 + math.random() * 0.25
					d.rays:burst(0.35)
					FX.glow(d.folder, d.eyePos, 44, Color3.fromRGB(210, 235, 255), 0.35, { brightness = 2 })
					FX.ring(d.folder, d.eyePos, camTilt(d.eyePos, 0.9), 14, 95, Color3.fromRGB(170, 215, 255), 0.6, { alpha = 0.25 })
					if cameraInside(d) then
						FX.flash(LimitlessPerk.sk(d.alt, Color3.fromRGB(205, 228, 255)), 0.1, 0.18)
						if warp then
							warp:burst(50)
						end
						addEnvelope({ tag = d, fov = 3, attack = 0.03, release = 0.25 })
					end
				end
			end
			if d.radius > 0.5 then
				anyActive = true
			end
			local insideNow = cameraInside(d)
			if insideNow then
				anyInside = true
			end
			-- the boundary sweeping over the camera: swallowed into the void
			if insideNow and not d.swallowed then
				d.swallowed = true
				d.swallowBurst = true
				FX.flash(LimitlessPerk.sk(d.alt, Color3.fromRGB(225, 238, 255)), 0.55, 0.35)
				FX.speedLines(0.6, { color = LimitlessPerk.sk(d.alt, Color3.fromRGB(210, 232, 255)), alpha = 0.8, count = 70, inner = 0.25 })
				addEnvelope({ tag = d, fov = 14, attack = 0.03, hold = 0.05, release = 0.5 })
			end
		end
	end
	-- the caught pulse with light, each out of step with the others
	for _, v in pairs(victimFx) do
		if v.highlight then
			v.highlight.FillTransparency = 0.14 + 0.1 * math.sin(clock * 4.2 + v.phase)
		end
	end
	if groupHighlight then
		groupHighlight.FillTransparency = 0.14 + 0.1 * math.sin(clock * 4.2)
	end
	-- the void eases in and out around the camera
	local target = anyInside and 1 or 0
	voidW += (target - voidW) * math.min(1, dt * 5)
	if math.abs(voidW - target) < 0.01 then
		voidW = target
	end
	local dimTarget = anyInside and 1 or (anyActive and DIM_OUTSIDE or 0)
	dimW += (dimTarget - dimW) * math.min(1, dt * 4)
	if math.abs(dimW - dimTarget) < 0.01 then
		dimW = dimTarget
	end
	-- CRIMSON VOID: the world takes the palette of the void the camera is inside, else of any standing alt void; the
	-- last palette is kept while the void fades out, so nothing snaps
	if anyActive or anyInside then
		local va, insideOne = false, false
		for _, dd in pairs(domainFx) do
			if not dd.collapsed and dd.radius > 0.5 then
				if cameraInside(dd) then
					if not insideOne then
						insideOne, va = true, dd.alt == true
					end
				elseif not insideOne and dd.alt then
					va = true
				end
			end
		end
		LimitlessPerk.voidAlt = va
	end
	applyVoid(voidW, dimW)
	-- the starlight rush follows the camera for as long as it is inside a void
	if voidW > 0.02 then
		if warp and LimitlessPerk.warpAlt ~= LimitlessPerk.voidAlt then
			warp:destroy()
			warp = nil
		end
		if not warp then
			warp = FX.warpField(LimitlessPerk.root(LimitlessPerk.voidAlt))
			LimitlessPerk.warpAlt = LimitlessPerk.voidAlt
		end
		warp:setIntensity(math.clamp(voidW, 0, 1))
		for _, dd in pairs(domainFx) do
			if dd.swallowBurst then
				dd.swallowBurst = nil
				warp:burst(150)
			end
		end
	elseif warp then
		warp:destroy()
		warp = nil
	end
	victimAcc += dt
	if victimAcc > 0.2 then
		victimAcc = 0
		updateVictims()
	end
end

local function requestDomain()
	if not myChar() or lockState or now() < cooldownEnd.Domain then
		return
	end
	local kit = player:GetAttribute("Kit")
	if kit ~= nil and kit ~= "Limitless" then
		return -- another kit is equipped
	end
	if blue.holding then
		releaseBlue()
	end
	AbilityRequest:FireServer("Domain", {})
end

---------------------------------------------------------------------------------------------------
-- input
local holding, holdStart = false, 0
local function beginPurpleHold()
	if holding or lockState or pendingLocal or now() < cooldownEnd.HollowPurple or not myChar() then
		return
	end
	holding = true
	holdStart = os.clock()
	local started = holdStart
	task.delay(HP.HoldThreshold, function()
		if holding and holdStart == started then
			holding = false
			startLocalPurple("Incantation")
		end
	end)
end
local function endPurpleHold()
	if holding then
		holding = false
		startLocalPurple("Quick")
	end
end

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if isGojo() or sharedPunchAllowed() then
		tryPunch()
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	-- the M1 punch combo is shared by every kit (but not while morphed into a giant form)
	if not isGojo() then
		if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) and not (player.Character and (player.Character:GetAttribute("Morphed") or player.Character:GetAttribute("OwnM1"))) then
			localPunch.held = true
			tryPunch()
		end
		return
	end
	-- KEYBINDS (2026-11-11): the move is the one the player bound to this key, not the raw KeyCode ("have the option to
	-- have keybinds"); a mouse click has KeyCode Unknown and still falls through to the M1 branch below
	local key = Keybinds.logical(input.KeyCode)
	if key == Enum.KeyCode.E then
		beginPurpleHold()
	elseif key == Enum.KeyCode.Q then
		startBlue()
	elseif key == Enum.KeyCode.R then
		startLocalRed()
	elseif key == Enum.KeyCode.G then
		requestDomain()
	elseif (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		localPunch.held = true
		tryPunch()
	end
end)
-- holding M1 keeps the string going: the next swing goes out the moment it is allowed
RunService.Heartbeat:Connect(function()
	if not localPunch.held then
		return
	end
	if not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not _G.SandboxArmed) or not (isGojo() or sharedPunchAllowed()) then
		localPunch.held = false
	elseif not localPunch.buffered and os.clock() >= punchReadyAt() then
		tryPunch()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local key = Keybinds.logical(input.KeyCode) -- KEYBINDS (2026-11-11): let go of the move bound to this key
	if key == Enum.KeyCode.E then
		endPurpleHold()
	elseif key == Enum.KeyCode.Q then
		releaseBlue()
	end
end)

purpleBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		beginPurpleHold()
	end
end)
purpleBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		endPurpleHold()
	end
end)
punchBtn.Activated:Connect(tryPunch)
redBtn.Activated:Connect(startLocalRed)
domainBtn.Activated:Connect(requestDomain)
blueBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		startBlue()
	end
end)
blueBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		releaseBlue()
	end
end)

if RunService:IsStudio() then
	local dbg = Shared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd ~= "Aim" and not isGojo() then
				return
			end
			if cmd == "Purple" then
				startLocalPurple(arg == "Incantation" and "Incantation" or "Quick")
			elseif cmd == "Punch" then
				tryPunch()
			elseif cmd == "Domain" then
				requestDomain()
			elseif cmd == "Red" then
				startLocalRed()
			elseif cmd == "Grab" then
				startBlue(typeof(arg) == "Instance" and arg or nil)
			elseif cmd == "Release" then
				releaseBlue()
			elseif cmd == "Aim" then
				debugAim = (typeof(arg) == "Vector3" and arg.Magnitude > 0) and arg.Unit or nil
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- network
AbilityCast.OnClientEvent:Connect(function(caster, ability, data)
	if typeof(caster) ~= "Instance" or type(data) ~= "table" then
		return
	end
	if ability == "HollowPurple" then
		if caster == player and pendingLocal and not pendingLocal.cancelled then
			local c = pendingLocal
			pendingLocal = nil
			adopt(c, data)
		elseif not casts[data.castId] then
			newPurpleCast(caster, data, caster == player)
		end
	elseif ability == "Punch" and caster ~= player then
		playPunch(caster, tonumber(data.combo) or 1, data.finisher)
	elseif ability == "Domain" then
		newDomainFx(caster, data)
	elseif ability == "Red" then
		if caster == player and pendingRed and not pendingRed.final then
			local c = pendingRed
			pendingRed = nil
			adoptRed(c, data)
		elseif not redCasts[data.castId] then
			newRedCast(caster, data, caster == player)
		end
	end
end)

AbilityResult.OnClientEvent:Connect(function(ability, ok, info)
	info = type(info) == "table" and info or {}
	if ability == "Blue" then
		if info.cooldownEnd then
			cooldownEnd.Blue = info.cooldownEnd
		end
		return
	end
	if ability == "Domain" then
		if info.cooldownEnd then
			cooldownEnd.Domain = info.cooldownEnd
		end
		return
	end
	if ability == "Red" then
		if info.cooldownEnd then
			cooldownEnd.Red = info.cooldownEnd
		end
		if not ok then
			if pendingRed then
				cancelRed(pendingRed)
			end
			if info.reason ~= "cooldown" then
				cooldownEnd.Red = 0
			end
		end
		return
	end
	if ability ~= "HollowPurple" then
		return
	end
	if info.cooldownEnd then
		cooldownEnd.HollowPurple = info.cooldownEnd
	end
	if not ok then
		if pendingLocal then
			cancelPurple(pendingLocal)
		end
		if info.reason ~= "cooldown" then
			cooldownEnd.HollowPurple = 0
		end
	end
end)

AbilityEvent.OnClientEvent:Connect(function(kind, data)
	if type(data) ~= "table" then
		return
	end
	if kind == "PunchHit" and typeof(data.pos) == "Vector3" then
		local final = data.final == true
		VFX.burst(LocalFX, data.pos, final and Color3.fromRGB(255, 200, 120) or Color3.fromRGB(255, 250, 230), final and 28 or 12, final and 1.5 or 0.9, final and 45 or 26)
		-- (2026-11-12) varied punch hits (SfxBank pools); a finisher lands heavy
		SfxBank.play(final and "HIT_HEAVY" or "HIT", data.pos, final and 0.9 or 0.6, final and 0.95 or 1.04)
		local _, _, hrp = myChar()
		if hrp and (hrp.Position - data.pos).Magnitude < 14 then
			addEnvelope({ shake = final and 0.55 or 0.22, freq = 25, attack = 0.01, release = final and 0.3 or 0.15, fov = final and -3 or 0 })
		end
	elseif kind == "PurpleHit" and typeof(data.pos) == "Vector3" then
		local pc = casts[data.castId]
		VFX.burst(LimitlessPerk.root(pc and pc.alt), data.pos, Color3.fromRGB(225, 170, 255), 18, 1.2, 35)
	elseif kind == "PurpleEnd" then
		local cast = casts[data.castId]
		if cast and typeof(data.pos) == "Vector3" then
			endPurple(cast, data.pos)
		end
	elseif kind == "PurpleCancel" then
		cancelPurple(casts[data.castId])
	elseif kind == "RedBlast" and typeof(data.pos) == "Vector3" then
		local cast = redCasts[data.castId]
		if not cast then
			local a = LimitlessPerk.alt(Players:GetPlayerByUserId(tonumber(data.userId) or 0))
			cast = { folder = LimitlessPerk.root(a), isLocal = false, alt = a }
		end
		redDetonate(cast, data.pos, tonumber(data.radius))
	elseif kind == "RedCancel" then
		cancelRed(redCasts[data.castId])
	elseif kind == "DomainCollapse" then
		collapseFx(domainFx[data.castId], data.early)
	elseif kind == "BlueGrab" then
		onBlueGrab(data)
	elseif kind == "BlueRelease" then
		onBlueRelease(data)
	end
end)

---------------------------------------------------------------------------------------------------
-- (2026-11-10) PvP: a Lapse Blue or an Unlimited Void that caught ME ("people can just walk out" of the domain, "blue
-- doesn't grab people"). The server can't move a client-owned body, so CombatService only marks my character -
-- GrabbedBy + BlueHoldPos (the hold point the caster steers) or InDomain + VoidHover (where the void floats me) - and
-- this block, which runs for every player whatever kit they have equipped, hangs my body there with my own
-- constraints, the way the server hangs an NPC: a Blue pulls my chest to the orb and holds it there (the server has my
-- rig ragdolled, so the rest dangles); a void floats me weightless, upright and slowly turning over VoidHover (a giant
-- form is only pinned where it stands). The server keeps me stunned meanwhile, so walking, jumping, dashing, flying
-- and every move are refused (PvPStunClient, Dash, the kits' gates) even if this hold failed. Let go the moment the
-- mark is cleared (the release throw / the void's shatter then arrives as a normal PvP knockback), or I die / respawn.
local SelfHold = { mode = nil, parts = {}, knockAt = 0 }

function SelfHold.clear()
	for _, inst in ipairs(SelfHold.parts) do
		inst:Destroy()
	end
	SelfHold.parts = {}
	SelfHold.mode, SelfHold.char, SelfHold.align, SelfHold.upright = nil, nil, nil, nil
end

function SelfHold.add(inst, name, parent)
	inst.Name = name
	inst.Parent = parent
	table.insert(SelfHold.parts, inst)
	return inst
end

function SelfHold.begin(mode, char, point)
	SelfHold.clear()
	SelfHold.mode, SelfHold.char = mode, char
	local ut = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	if not ut then
		return
	end
	local giant = char:GetAttribute("Morphed") or char:GetAttribute("TitanForm") or char:GetAttribute("FoxBeast")
	local float = mode == "void" and not giant
	-- my mass, part by part; in a void every part is made weightless (like the server's VoidFloat on a dummy). Per PART,
	-- at its own centre, so it stays right when the server's ragdoll (PvP.ragdoll) regroups the rig's assemblies later
	local mass = 0
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and not p.Anchored and not p.Massless then
			local pm = p:GetMass()
			mass += pm
			if float then
				local a = SelfHold.add(Instance.new("Attachment"), "SelfVoidAtt", p)
				local f = Instance.new("VectorForce")
				f.Attachment0 = a
				f.RelativeTo = Enum.ActuatorRelativeTo.World
				f.ApplyAtCenterOfMass = false
				f.Force = Vector3.new(0, pm * workspace.Gravity, 0)
				SelfHold.add(f, "SelfVoidFloat", p)
			end
		end
	end
	local att = SelfHold.add(Instance.new("Attachment"), "SelfHoldAtt", ut)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.Position = typeof(point) == "Vector3" and point or ut.Position
	if mode == "blue" then
		ap.MaxForce, ap.MaxVelocity, ap.Responsiveness = BLUE.MaxForce, BLUE.MaxVelocity, BLUE.Responsiveness
	else
		-- the server's VoidHover numbers; the force grows with a heavier body (and holds a giant's full weight)
		ap.MaxForce = math.max(6000, mass * (float and 400 or workspace.Gravity * 3))
		ap.MaxVelocity, ap.Responsiveness = 18, 6
	end
	SelfHold.align = SelfHold.add(ap, "SelfHoldAlign", ut)
	if float then
		local _, yaw = ut.CFrame:ToEulerAnglesYXZ()
		local ao = Instance.new("AlignOrientation")
		ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
		ao.Attachment0 = att
		ao.Responsiveness = 4
		ao.MaxTorque = math.max(2500, mass * 150)
		ao.CFrame = CFrame.Angles(0, yaw, 0)
		SelfHold.upright = SelfHold.add(ao, "SelfVoidUpright", ut)
		SelfHold.yaw = yaw
		SelfHold.spin = (math.random() < 0.5 and -1 or 1) * (0.25 + math.random() * 0.35)
		SelfHold.phase = math.random() * math.pi * 2
	end
end

function SelfHold.step(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local mode, point = nil, nil
	if hum and hum.Health > 0 then
		-- only Gojo's own marks, which always carry their point: other kits write GrabbedBy / InDomain on players too
		-- (Ichigo's Bankai grab holds its victim its own way) and must not be hung up here
		local bp, vh = char:GetAttribute("BlueHoldPos"), char:GetAttribute("VoidHover")
		if char:GetAttribute("GrabbedBy") ~= nil and typeof(bp) == "Vector3" then
			mode, point = "blue", bp
		elseif char:GetAttribute("InDomain") ~= nil and typeof(vh) == "Vector3" then
			mode, point = "void", vh
		end
	end
	if mode ~= SelfHold.mode or char ~= SelfHold.char or (SelfHold.align and not SelfHold.align.Parent) then
		if mode then
			SelfHold.begin(mode, char, point)
		else
			SelfHold.clear()
		end
	end
	local ap = SelfHold.align
	if not ap then
		return
	end
	-- a knockback that lands while I am held (an M1 on my floating body, or the release throw arriving a beat ahead of
	-- the cleared mark) gets a moment to move me before the hold takes me back
	local free = os.clock() - SelfHold.knockAt < 0.2
	ap.Enabled = not free
	if SelfHold.upright then
		SelfHold.upright.Enabled = not free
	end
	if typeof(point) ~= "Vector3" then
		return
	end
	if SelfHold.upright then
		-- the drift, bob and slow turn the server gives a floating dummy
		local c, ph = os.clock(), SelfHold.phase
		ap.Position = point + Vector3.new(math.cos(c * 0.4 + ph) * 1.6, math.sin(c * 1.3 + ph) * 1.3, math.sin(c * 0.5 + ph) * 1.6)
		SelfHold.yaw += SelfHold.spin * dt
		SelfHold.upright.CFrame = CFrame.Angles(math.sin(c * 0.7 + ph) * 0.18, SelfHold.yaw, math.cos(c * 0.6 + ph) * 0.18)
	else
		ap.Position = point
	end
end

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("PvPShared", 30)
	local kb = shared and shared:WaitForChild("Knockback", 30)
	if kb then
		kb.OnClientEvent:Connect(function()
			SelfHold.knockAt = os.clock()
		end)
	end
end)
RunService.Heartbeat:Connect(function(dt)
	local ok, err = pcall(SelfHold.step, dt)
	if not ok then
		warn("[GojoClient] self hold failed: " .. tostring(err))
		pcall(SelfHold.clear)
	end
end)

-- the local character dying mid-cast: drop the pose and the root lock (the orb keeps flying if already launched)
local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		for _, cast in pairs(casts) do
			if cast.isLocal then
				if cast.launched then
					if cast.track then
						cast.track:stop(0.1)
					end
					unlockMovement(cast)
				else
					cancelPurple(cast)
				end
			end
		end
		holding = false
		releaseBlue()
		for _, dd in pairs(domainFx) do
			if dd.isLocal then
				dd.cinematic = false
				unlockMovement(dd)
			end
		end
		for _, rc in pairs(redCasts) do
			if rc.isLocal then
				if rc.launched then
					if rc.track then
						rc.track:stop(0.1)
					end
					unlockMovement(rc)
				else
					cancelRed(rc)
				end
			end
		end
	end)
end
if player.Character then
	task.spawn(hookCharacter, player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

---------------------------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local okB, errB = pcall(updateBlue, dt)
	if not okB then
		warn("[GojoClient] blue update failed: " .. tostring(errB))
	end
	for _, rc in pairs(redCasts) do
		local okR, errR = pcall(updateRed, rc, dt)
		if not okR then
			warn("[GojoClient] red update failed: " .. tostring(errR))
			cancelRed(rc)
		end
	end
	local okD, errD = pcall(updateDomains, dt)
	if not okD then
		warn("[GojoClient] domain update failed: " .. tostring(errD))
	end
	local drem = cooldownEnd.Domain - now()
	domainCd.Size = UDim2.fromScale(math.clamp(drem / math.max(DOMAIN.Cooldown * LimitlessPerk.cd(true), drem, 0.01), 0, 1), 1)
	domainCdText.Text = drem > 0 and string.format("%.0f", drem) or ""
	local rrem = cooldownEnd.Red - now()
	redCd.Size = UDim2.fromScale(1, math.clamp(rrem / math.max(RED.Cooldown * LimitlessPerk.cd(false), rrem, 0.01), 0, 1))
	redCdText.Text = rrem > 0 and string.format("%.1f", rrem) or ""
	local brem = cooldownEnd.Blue - now()
	blueCd.Size = UDim2.fromScale(1, math.clamp(brem / math.max(BLUE.Cooldown * LimitlessPerk.cd(false), brem, 0.01), 0, 1))
	blueCdText.Text = brem > 0 and string.format("%.1f", brem) or ""
	for _, cast in pairs(casts) do
		local ok, err = pcall(updatePurple, cast, dt)
		if not ok then
			warn("[GojoClient] cast update failed: " .. tostring(err))
			cancelPurple(cast)
		end
	end
	local rem = cooldownEnd.HollowPurple - now()
	purpleCd.Size = UDim2.fromScale(1, math.clamp(rem / math.max(HP.Cooldown * LimitlessPerk.cd(false), rem, 0.01), 0, 1))
	purpleCdText.Text = rem > 0 and string.format("%.1f", rem) or ""
	local prem = localPunch.lockUntil - os.clock()
	punchCd.Size = UDim2.fromScale(1, math.clamp(prem / PUNCH.FinalCooldown, 0, 1))
	punchCdText.Text = ""
	updateScale()
end)

-- show this kit's ability bar only while it is equipped; drop anything held when switching away
local function applyKit()
	local on = isGojo()
	bar.Visible = on
	if not on then
		holding = false
		releaseBlue()
	end
end
applyKit()
player:GetAttributeChangedSignal("Kit"):Connect(applyKit)

print("[GojoClient] ready - E: Hollow Purple (hold for the incantation), Q: Lapse Blue grab (hold), R: Reversal Red, G: Domain Expansion, Click: punch")
