--!nocheck
-- VulpineClient: input + ability bar for the Vulpine kit, local movement (anchor, thrust, rooting, tumbling when
-- knocked back), enemy-sense outlines, and playback of every Vulpine cast in the server (VFX via FxLib).
-- The server (VulpineServer.KitServer) is authoritative; this script only sends intents and renders.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("VulpineKit")
local CFG = require(Kit:WaitForChild("Config"))
local Fx = require(Kit:WaitForChild("FxLib"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local PAL = CFG.Palette
local UP = Vector3.yAxis

-- (2026-11-11 keybinds) owner: "have the option to have keybinds". The CFG.Keys / CFG.Morph.ReleaseKey presses below
-- are read through HudShared.Keybinds - logical() turns the physical key into the DEFAULT key whose action the player
-- bound to it - and the key chips plus the form's "F: BOMB   X: RELEASE" line draw the player's own binding (redrawn
-- on Keybinds.Changed). With no rebinds both return the key itself, so default play is unchanged. Config stays the
-- defaults; M1 / touch stay raw (not rebindable).
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))
local keyChips = {} -- [TextLabel] = the default KeyCode whose binding it shows
local function keyChip(lbl, default)
	keyChips[lbl] = default
	return lbl
end
-- "F: BOMB   X: RELEASE" (Config text) -> the same line with each action key before a colon swapped for its binding
local ACTION_BY_NAME = {}
for _, a in ipairs(Keybinds.ACTIONS) do
	ACTION_BY_NAME[a.key.Name] = a.key
end
local function keyHint(s)
	return (string.gsub(s, "%f[%w](%w+):", function(name)
		local d = ACTION_BY_NAME[name]
		return d and (Keybinds.label(d) .. ":") or nil
	end))
end
local morphSubForm = keyHint(CFG.Callouts.Morph.subForm or "") -- drawn every frame, so rebuilt only on a rebind
Keybinds.Changed:Connect(function()
	for lbl, d in pairs(keyChips) do
		lbl.Text = Keybinds.label(d)
	end
	morphSubForm = keyHint(CFG.Callouts.Morph.subForm or "")
end)

-- PERKS (2026-11-07, kits-A): the CRIMSON FOX skin swaps the whole palette per cast (the CASTER's Skin == "Alt", read
-- when the cast starts; Config.AltSkin; the form keeps the palette it started with), and the bar's cooldown shading
-- follows the CooldownMul / UltChargeMul scaling the server applies. One table keeps the local count down.
local Perk = { morphPal = {} }
do
	local ok, alt = pcall(function()
		return require(Kit:WaitForChild("Config"):WaitForChild("AltSkin", 10))
	end)
	Perk.ALT = ok and type(alt) == "table" and type(alt.Palette) == "table" and alt or nil
	if not Perk.ALT then
		warn("[VulpineClient] CRIMSON FOX skin unavailable: " .. tostring(alt))
	end
end
-- the palette a caster's casts are drawn in right now
function Perk.pal(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if Perk.ALT and p and p:GetAttribute("Skin") == "Alt" then
		return Perk.ALT.Palette
	end
	return PAL
end
-- (palette, ORANGE, RED, HOT) for a caster, or for a palette a cast already picked
function Perk.skin(userId, pal)
	pal = pal or Perk.pal(userId)
	return pal, pal.BeastBody, pal.BeastAccent, pal.BeastCore
end
-- the cooldown multiplier for a normal skill (false) or the ultimate and its in-form moves (true)
function Perk.cd(isUlt)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, as the server does
	local bal = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
	return math.clamp(m, 0.05, 4) * (isUlt and 1 or bal.NON_ULT_COOLDOWN_MUL)
end

-- optional pose player from the existing kit (poses are skipped if it is missing)
local Animator
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared", 5).Client.ProceduralAnimator)
	end)
	Animator = ok and mod or nil
end

local Debris = game:GetService("Debris")
local GFX -- the shared lightning / glow library (a silent stub if it is missing)
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared", 5).Client.GojoFX)
	end)
	GFX = ok and mod or setmetatable({}, { __index = function() return function() end end })
end
local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback"))

local FX = Instance.new("Folder")
FX.Name = "VulpineFX"
FX.Parent = workspace

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

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId or 0)
	return p and p.Character
end

local function equipped()
	return player:GetAttribute("Kit") == CFG.KitId
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(pos)
	local ignore = { FX }
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "NPCs" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -60, 0), groundParams)
	return hit and hit.Position or pos - UP * 3, hit and hit.Normal or UP
end

-- right-hand anchor point (R15 RightGripAttachment, else the hand, else in front of the chest)
local function handPoint(char)
	local hand = char:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	if grip then
		return grip.WorldPosition
	end
	if hand then
		return hand.Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position + hrp.CFrame.LookVector * 2 or nil
end

-- poses (degrees; shoulder flexion +X, lean forward Waist -X, right arm out RightShoulder Z+)
local POSE = {
	Hold = { RightShoulder = { 80, 0, -8 }, RightElbow = { 35, 0, 0 }, LeftShoulder = { 85, 0, 30 }, LeftElbow = { 70, 0, 0 }, Waist = { -8, 22, 0 } },
	Thrust = { RightShoulder = { 95, 0, -4 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { -40, 0, -18 }, LeftElbow = { 30, 0, 0 }, Waist = { -24, 18, 0 } },
	Raise = { RightShoulder = { 170, 0, 8 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 30, 0, -25 }, LeftElbow = { 40, 0, 0 }, Waist = { 6, -10, 0 } },
	Throw = { RightShoulder = { 62, 0, -20 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { -25, 0, -25 }, Waist = { -18, -14, 0 } },
}
local function pose(char, a, b, holdTime, length)
	if not Animator or not char then
		return
	end
	Animator.stopAll(char, 0.08)
	local keys = { { t = 0.12, ease = { "Back", "Out" }, pose = POSE[a] }, { t = holdTime, ease = { "Sine", "InOut" }, pose = POSE[a] } }
	if b then
		table.insert(keys, { t = holdTime + 0.07, ease = { "Exponential", "Out" }, pose = POSE[b] })
		table.insert(keys, { t = length - 0.25, ease = { "Sine", "Out" }, pose = POSE[b] })
	end
	Animator.play(char, { length = length, fadeIn = 0.1, fadeOut = 0.25, keys = keys })
end

---------------------------------------------------------------------------------------------------
-- ability bar
local gui = Instance.new("ScreenGui")
gui.Name = "VulpineHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function uiCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = p
end
local function uiStroke(p, color, th, tr, contextual)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th
	s.Transparency = tr or 0
	s.ApplyStrokeMode = contextual and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function uiText(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- full-screen impact frames: a one-frame black blink, then a tinted white flash (biggest hits only)
local impactBlack = Instance.new("Frame")
impactBlack.Size = UDim2.fromScale(1, 1)
impactBlack.BackgroundColor3 = Color3.new(0, 0, 0)
impactBlack.BackgroundTransparency = 1
impactBlack.BorderSizePixel = 0
impactBlack.ZIndex = 50
impactBlack.Parent = gui
local impactWhite = impactBlack:Clone()
impactWhite.ZIndex = 51
impactWhite.Parent = gui
local function impactFrame(tint)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoFlash") then
		return -- Settings menu: switched off
	end
	impactBlack.BackgroundTransparency = 0.05
	task.delay(0.045, function()
		impactBlack.BackgroundTransparency = 1
		impactWhite.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(tint or Color3.new(1, 1, 1), 0.25)
		impactWhite.BackgroundTransparency = 0.12
		Fx.tween(impactWhite, 0.18, { BackgroundTransparency = 1 })
	end)
end

-- cinematic letterbox bars for the transformation
local barTop = Instance.new("Frame")
barTop.Size = UDim2.new(1, 0, 0, 0)
barTop.BackgroundColor3 = Color3.new(0, 0, 0)
barTop.BorderSizePixel = 0
barTop.ZIndex = 45
barTop.Parent = gui
local barBottom = barTop:Clone()
barBottom.AnchorPoint = Vector2.new(0, 1)
barBottom.Position = UDim2.fromScale(0, 1)
barBottom.Parent = gui
local function letterbox(on, time)
	local h = on and 0.09 or 0
	Fx.tween(barTop, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
	Fx.tween(barBottom, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
end

-- move-name callout: a kanji line over the move name in a gradient, punched in then faded out
local titleHolder = Instance.new("Frame")
titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
titleHolder.Position = UDim2.fromScale(0.5, 0.27)
titleHolder.Size = UDim2.fromScale(0.86, 0.15)
titleHolder.BackgroundTransparency = 1
titleHolder.ZIndex = 40
titleHolder.Parent = gui
local titleScale = Instance.new("UIScale")
titleScale.Parent = titleHolder
local title = uiText(titleHolder, { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 41 })
local titleStroke = uiStroke(title, Color3.new(0, 0, 0), 3, 1, true)
local titleGrad = Instance.new("UIGradient")
titleGrad.Rotation = 90
titleGrad.Parent = title
local kanji = uiText(titleHolder, { Size = UDim2.fromScale(1, 0.32), Text = "", TextTransparency = 1, ZIndex = 41 })
local kanjiStroke = uiStroke(kanji, Color3.new(0, 0, 0), 2, 1, true)
local titleToken
local function showTitle(skill, alt)
	local co = CFG.Callouts[skill]
	if not co then
		return
	end
	local ov = alt and Perk.ALT and Perk.ALT.Callouts and Perk.ALT.Callouts[skill]
	local c0, c1 = (ov and ov.c0) or co.c0, (ov and ov.c1) or co.c1
	local token = {}
	titleToken = token
	title.Text = CFG.Labels[skill] or skill
	kanji.Text = co.kanji or ""
	kanji.TextColor3 = c0:Lerp(c1, 0.45)
	titleGrad.Color = ColorSequence.new(c0, c1)
	local dark = c1:Lerp(Color3.new(0, 0, 0), 0.82)
	titleStroke.Color, kanjiStroke.Color = dark, dark
	title.TextTransparency, kanji.TextTransparency = 0, 0
	titleStroke.Transparency, kanjiStroke.Transparency = 0, 0
	titleScale.Scale = 1.7
	titleHolder.Rotation = -5
	Fx.tween(titleScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
	Fx.tween(titleHolder, 0.16, { Rotation = 0 })
	task.delay(1.5, function()
		if titleToken ~= token then
			return
		end
		for _, o in ipairs({ title, kanji }) do
			Fx.tween(o, 0.45, { TextTransparency = 1 })
		end
		for _, o in ipairs({ titleStroke, kanjiStroke }) do
			Fx.tween(o, 0.45, { Transparency = 1 })
		end
	end)
end

-- ability bar, laid out like the Limitless kit's: two skills, the shared M1 punch, the big Sage Mode button,
-- and the Kurama ultimate on its own wide button above the row
local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -22, 1, -22)
bar.Size = UDim2.fromOffset(380, 112)
bar.BackgroundTransparency = 1
bar.Visible = false
bar.Parent = gui
local barScale = Instance.new("UIScale")
barScale.Parent = bar
local status = uiText(bar, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -172), Size = UDim2.new(1, 0, 0, 16), -- above the ultimate pill
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold,
})
uiStroke(status, Color3.new(0, 0, 0), 1.5, 0.3, true)

local SLOTS = {
	{ id = "Disc", size = 72, x = -280 }, -- the Reversal Red slot
	{ id = "Sphere", size = 72, x = -198 }, -- the Lapse Blue slot
	{ id = "Power", size = 104, x = 0 }, -- the Hollow Purple slot
}
local COOLDOWN = { Sphere = CFG.Sphere.Cooldown, Disc = CFG.Disc.Cooldown, Power = CFG.Power.Cooldown, Morph = CFG.Morph.Cooldown }
local cooldownEnd = { Sphere = 0, Disc = 0, Power = 0, Morph = 0, Bomb = 0, Claw = 0 }
local buttons = {}

-- the world point under the cursor (the screen centre on touch-only devices or while the mouse is locked)
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local function cursorTarget()
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local ignore = { FX }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
	cursorParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, cursorParams)
	return hit and hit.Position or ray.Origin + ray.Direction * 1000
end

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	local aim, target = workspace.CurrentCamera.CFrame.LookVector, cursorTarget()
	-- (2026-11-09) the form's M1 (CLAW) swipes toward the mouse, not along the camera
	if skill == "Claw" and typeof(target) == "Vector3" then
		local _, _, hrp = myChar()
		local off = hrp and (target - hrp.Position) * Vector3.new(1, 0, 1)
		if off and off.Magnitude > 1.5 then
			aim = off.Unit
		end
	end
	Request:FireServer(skill, { aim = aim, target = target })
end

-- true while the Kurama form stands (its attribute is only stamped once the transformation has finished)
local function inForm()
	local char = player.Character
	return char ~= nil and char:GetAttribute("Morphed") == true and (char:GetAttribute("MorphUntil") or 0) > now()
end

-- a square skill button in the skill's own colours: glowing glyph orb, key chip, name, hint, cooldown shade
local function skillButton(sk)
	local co = CFG.Callouts[sk.id]
	local big = sk.size > 80
	local b = Instance.new("TextButton")
	b.Name = sk.id
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(sk.size, sk.size)
	b.Position = UDim2.new(1, sk.x, 1, -16)
	b.BackgroundColor3 = co.c1:Lerp(Color3.fromRGB(8, 8, 14), 0.74)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(140, 140, 150))
	shade.Rotation = 90
	shade.Parent = b
	local st = uiStroke(b, co.c1:Lerp(Color3.new(1, 1, 1), 0.35), 2, 0.1)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.46, 0.46)
	orb.BackgroundColor3 = Color3.new(1, 1, 1)
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local og = Instance.new("UIGradient")
	og.Color = ColorSequence.new(co.c0, co.c1)
	og.Rotation = 45
	og.Parent = orb
	uiStroke(orb, co.c1:Lerp(Color3.new(1, 1, 1), 0.5), 1.5, 0.3)
	local glyph = uiText(orb, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.11), Text = co.glyph or "", ZIndex = 2 })
	uiStroke(glyph, co.c1:Lerp(Color3.new(0, 0, 0), 0.7), 1.5, 0, true)
	uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 12), Position = UDim2.new(0, 4, 1, big and -21 or -18), Text = CFG.Labels[sk.id] or sk.id, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.85)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyChip(uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys[sk.id]), Font = Enum.Font.GothamBold, ZIndex = 2 }), CFG.Keys[sk.id])
	uiText(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Text = co.hint or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.35) })
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	cd.Parent = b
	uiCorner(cd, UDim.new(0, 18))
	local cdText = uiText(b, { Size = UDim2.fromScale(1, 0.38), Position = UDim2.fromScale(0, 0.22), Text = "", ZIndex = 4 })
	buttons[sk.id] = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true }
	b.Activated:Connect(function()
		request(sk.id)
	end)
end
for _, sk in ipairs(SLOTS) do
	skillButton(sk)
end

-- the shared M1 punch, in the same slot and style as the Limitless kit's; clicking / tapping it punches too
local punchName, punchGrad
do
	local b = Instance.new("TextButton")
	b.Name = "Punch"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(72, 72)
	b.Position = UDim2.new(1, -116, 1, -16)
	b.BackgroundColor3 = Color3.fromRGB(46, 30, 26)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	uiStroke(b, Color3.fromRGB(255, 200, 150), 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = Color3.new(1, 1, 1)
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	punchGrad = Instance.new("UIGradient")
	punchGrad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 230), Color3.fromRGB(255, 180, 90))
	punchGrad.Rotation = 45
	punchGrad.Parent = orb
	punchName = uiText(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = "PUNCH", ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(24, 14, 10)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	uiText(chip, { Size = UDim2.fromScale(1, 1), Text = "M1", Font = Enum.Font.GothamBold, ZIndex = 2 })
	b.Activated:Connect(function()
		if inForm() then
			request("Claw")
			return
		end
		local scripts = player:FindFirstChild("PlayerScripts")
		local gojo = scripts and scripts:FindFirstChild("GojoClient")
		local bind = gojo and gojo:FindFirstChild("SharedPunch")
		if bind then
			bind:Fire()
		end
	end)
end

-- the Kurama ultimate on its own wide button above the row (the Domain Expansion slot)
local morphName, morphSub
do
	local co = CFG.Callouts.Morph
	local b = Instance.new("TextButton")
	b.Name = "Morph"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, 0, 1, -132)
	b.Size = UDim2.fromOffset(186, 36)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	local st = uiStroke(b, co.c1:Lerp(Color3.new(1, 1, 1), 0.4), 2, 0.1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(co.c1:Lerp(Color3.new(0, 0, 0), 0.82), co.c1:Lerp(Color3.new(0, 0, 0), 0.45))
	g.Rotation = 0
	g.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.9)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyChip(uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys.Morph), Font = Enum.Font.GothamBold, ZIndex = 2 }), CFG.Keys.Morph)
	morphName = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Morph, ZIndex = 2 })
	morphSub = uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(1, 0)
	cd.Position = UDim2.fromScale(1, 0)
	cd.Size = UDim2.fromScale(0, 1)
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	cd.Parent = b
	uiCorner(cd, UDim.new(0, 12))
	local cdText = uiText(b, { Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 4 })
	buttons.Morph = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Morph")
	end)
end

-- while the Kurama form stands: an "X  RELEASE" chip beside the pill (click / tap it too) that ends the form
local releaseBtn, releaseLabel, releaseStroke
do
	local co = CFG.Callouts.Morph
	local b = Instance.new("TextButton")
	b.Name = "Release"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -194, 1, -132)
	b.Size = UDim2.fromOffset(122, 36)
	b.BackgroundColor3 = Color3.fromRGB(26, 12, 10)
	b.BackgroundTransparency = 0.15
	b.Visible = false
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	releaseStroke = uiStroke(b, co.c1:Lerp(Color3.new(1, 1, 1), 0.4), 2, 0.1)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = Color3.fromRGB(250, 236, 220)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyChip(uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Morph.ReleaseKey), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(40, 16, 10), ZIndex = 2 }), CFG.Morph.ReleaseKey)
	releaseLabel = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Release or "RELEASE", ZIndex = 2 })
	uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = "END FORM", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
	b.Activated:Connect(function()
		request("Release")
	end)
	releaseBtn = b
end

-- a little pop when a skill comes off cooldown
RunService.Heartbeat:Connect(function()
	local t = now()
	for skill, b in pairs(buttons) do
		local ready = t >= (cooldownEnd[skill] or 0)
		if ready and not b.ready then
			b.scale.Scale = 1.14
			Fx.tween(b.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		b.ready = ready
	end
end)

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if equipped() and inForm() then
		request("Claw")
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	-- (2026-11-11 keybinds) compare the DEFAULT key the player's binding maps this press to, not the raw key
	local key = Keybinds.logical(input.KeyCode)
	for skill, k in pairs(CFG.Keys) do
		if key == k then
			request(skill)
		end
	end
	if key == CFG.Morph.ReleaseKey and inForm() then
		request("Release")
	end
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) and inForm() then
		request("Claw")
	end
end)

---------------------------------------------------------------------------------------------------
-- local body: anchoring, the thrust, rooting during the channel, tumbling when knocked back
local rootUntil = 0
local thrust = nil -- { lv = LinearVelocity, att = Attachment, id }
local tumbleUntil = 0

local function faceDir(hrp, dir)
	local flat = typeof(dir) == "Vector3" and dir * Vector3.new(1, 0, 1) or Vector3.zero
	if flat.Magnitude > 1e-3 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
	end
end

local function stopThrust(id)
	if thrust and (id == nil or thrust.id == id) then
		thrust.lv:Destroy()
		thrust.att:Destroy()
		thrust = nil
		local _, hum, hrp = myChar()
		if hum then
			hum.AutoRotate = true
		end
		if hrp then
			hrp.AssemblyLinearVelocity *= Vector3.new(0.3, 1, 0.3)
		end
	end
end

-- the caster's own client: anchor while charging, then drive the root `distance` studs forward
local function localSphere(d)
	local _, hum, hrp = myChar()
	if not hrp then
		return
	end
	faceDir(hrp, d.dir)
	hrp.Anchored = true
	task.delay(d.anchor, function()
		if not hrp.Parent then
			return
		end
		hrp.Anchored = false
		faceDir(hrp, d.dir)
		hum.AutoRotate = false
		local att = Instance.new("Attachment")
		att.Parent = hrp
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		lv.PrimaryTangentAxis = Vector3.xAxis
		lv.SecondaryTangentAxis = Vector3.zAxis
		lv.PlaneVelocity = Vector2.new(d.dir.X, d.dir.Z).Unit * (d.distance / d.launch)
		-- strong enough to reach full speed almost instantly, but finite: an unbounded force driven into a solid
		-- body makes the solver eject the caster straight up
		local mass = 0
		for _, part in ipairs(hrp.Parent:GetDescendants()) do
			if part:IsA("BasePart") and not part.Massless then
				mass += part:GetMass()
			end
		end
		lv.MaxForce = math.max(mass, 1) * 2500
		lv.Parent = hrp
		thrust = { lv = lv, att = att, id = d.id }
		task.delay(d.launch, function()
			stopThrust(d.id)
		end)
	end)
end

Knockback.OnClientEvent:Connect(function(vel, duration, keep)
	local char, hum = myChar()
	if not char or typeof(vel) ~= "Vector3" then
		return
	end
	stopThrust()
	tumbleUntil = math.max(tumbleUntil, os.clock() + (tonumber(duration) or 1.5))
	hum.PlatformStand = true
	local done = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			local root = part.AssemblyRootPart
			if root and not done[root] then
				done[root] = true
				root:ApplyImpulse((vel - root.AssemblyLinearVelocity * (1 - (keep or 0))) * root.AssemblyMass)
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- cast playback
local spheres, discs = {}, {}
local growValues = {} -- NumberValues tweened with TweenService and read every frame

local function grower(from, to, time)
	local v = Instance.new("NumberValue")
	v.Value = from
	Fx.tween(v, time, { Value = to }, Enum.EasingStyle.Back)
	return v
end

local function endSphere(id, fade)
	local s = spheres[id]
	if s then
		spheres[id] = nil
		s.vis:destroy(fade)
		if s.aura then
			s.aura:Destroy()
		end
	end
	if s and s.isLocal then
		stopThrust(id)
	end
end

local function endDisc(id)
	local d = discs[id]
	if d then
		discs[id] = nil
		d.vis:destroy(0.15)
		if d.vortex then
			d.vortex:destroy()
		end
	end
end

local handlers = {}

function handlers.Cooldown(d)
	if cooldownEnd[d.skill] ~= nil and typeof(d.ends) == "number" then
		cooldownEnd[d.skill] = d.ends
	end
end

function handlers.SphereCharge(d)
	local PAL = Perk.pal(d.userId) -- CRIMSON FOX
	local char = charOf(d.userId)
	if not char then
		return
	end
	local s = { char = char, vis = Fx.sphere(FX, PAL), size = grower(0.2, d.size, d.anchor), isLocal = d.userId == player.UserId }
	-- a pulsing aura around the caster while the sphere charges
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
	if torso then
		s.aura = Fx.emitter(torso, {
			Name = "SphereChargeAura", Texture = Fx.Tex.fire, Color = ColorSequence.new(PAL.SphereAura, PAL.SphereShell),
			LightEmission = 0.9, Rate = 45, Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(2, 5),
			Acceleration = Vector3.new(0, 8, 0), Size = NumberSequence.new(1.6, 0), Transparency = NumberSequence.new(0.4, 1),
		})
	end
	spheres[d.id] = s
	pose(char, "Hold", "Thrust", d.anchor, d.anchor + d.launch + 0.45)
	Fx.sound(Fx.Sounds.Charge, FX, handPoint(char) or torso.Position, 0.7, 1.3)
	if s.isLocal then
		localSphere(d)
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		-- the view tightens while it charges, then kicks out with the thrust
		Fx.envelope({ fov = -7, tint = PAL.SphereAura, attack = d.anchor * 0.9, release = 0.15 })
		Fx.envelope({ fov = 12, blur = 3, delay = d.anchor, attack = 0.04, release = 0.35 })
	end
	task.delay(d.anchor + d.launch + 1.5, function()
		if spheres[d.id] == s then
			endSphere(d.id, 0.2)
		end
	end)
end

function handlers.SphereImpact(d)
	local PAL = Perk.pal(d.userId)
	endSphere(d.id, 0.05)
	local pos, dir = d.pos, typeof(d.dir) == "Vector3" and d.dir or Vector3.zAxis
	local ground, normal = groundAt(pos)
	if (ground - pos).Magnitude < 10 then
		Fx.cracks(FX, ground, normal, 7, PAL.SphereShell, 6)
	end
	if d.userId == player.UserId then
		impactFrame(PAL.SphereShell)
		Fx.envelope({ fov = -5, contrast = 0.15, attack = 0.02, release = 0.3 })
	end
	Fx.flash(FX, pos, CFG.Sphere.HitRadius * 1.6, PAL.SphereShell, 0.4)
	Fx.shockwave(FX, ground + UP * 0.3, UP, 3, CFG.Sphere.HitRadius * 5, PAL.SphereAura, 0.5)
	Fx.shockwave(FX, pos, dir, 2, CFG.Sphere.HitRadius * 3, PAL.SphereShell, 0.35)
	Fx.burst(FX, pos, PAL.SphereAura, 34, 1.4, 70)
	Fx.dust(FX, ground, 5, 10)
	Fx.sound(Fx.Sounds.Impact, FX, pos, 1, 0.9)
	Fx.shake(1.3, 0.45, pos)
end

function handlers.SphereEnd(d)
	endSphere(d.id, 0.25)
end

function handlers.DiscChannel(d)
	local PAL = Perk.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	discs[d.id] = { char = char, vis = Fx.disc(FX, PAL), pal = PAL, size = grower(0.4, d.size, 0.5), phase = "channel", isLocal = d.userId == player.UserId }
	pose(char, "Raise", "Throw", d.time, d.time + 0.6)
	local hp = handPoint(char)
	if hp then
		Fx.sound(Fx.Sounds.Charge, FX, hp, 0.9, 0.8)
	end
	if d.userId == player.UserId then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		Fx.envelope({ fov = -6, tint = PAL.Vortex, attack = d.time * 0.9, release = 0.2 })
		rootUntil = os.clock() + d.time + 0.3
		local _, _, hrp = myChar()
		if hrp then
			faceDir(hrp, d.dir)
		end
		-- just before the charge completes, tell the server where the cursor is now: that is where it gets thrown
		task.delay(math.max(d.time - 0.08, 0), function()
			Request:FireServer("DiscAim", { id = d.id, target = cursorTarget() })
		end)
	end
end

function handlers.DiscLaunch(d)
	local c = discs[d.id]
	local PAL = c and c.pal or Perk.pal(d.userId)
	if not c then
		c = { vis = Fx.disc(FX, PAL), pal = PAL, size = grower(CFG.Disc.DiscSize, CFG.Disc.DiscSize, 0.01) }
		discs[d.id] = c
	end
	c.phase = "flight"
	c.carrier = d.carrier
	c.dir = d.dir
	c.isLocal = d.userId == player.UserId
	if d.userId == player.UserId then
		local _, _, hrp = myChar()
		if hrp then
			faceDir(hrp, d.dir) -- turn to face the throw
		end
		Fx.envelope({ fov = 9, blur = 2, attack = 0.03, release = 0.3 })
	end
	c.t0 = os.clock()
	c.origin = c.char and handPoint(c.char) or nil
	if c.origin then
		Fx.sound(Fx.Sounds.Launch, FX, c.origin, 0.9, 1.4)
	end
end

function handlers.DiscImpact(d)
	local c = discs[d.id]
	local PAL = c and c.pal or Perk.pal(d.userId)
	if not c then
		c = { vis = Fx.disc(FX, PAL), pal = PAL, size = grower(d.size, d.size, 0.01) }
		discs[d.id] = c
	end
	c.phase = "vortex"
	c.pos = d.pos
	c.size = grower(d.size, d.size * d.expand, 0.25) -- the disc swells 3x where it hit
	c.vortex = Fx.vortex(FX, PAL, d.pos, d.radius)
	local g, nrm = groundAt(d.pos)
	if (g - d.pos).Magnitude < 12 then
		Fx.cracks(FX, g, nrm, 6, PAL.DiscRim, 5)
	end
	Fx.flash(FX, d.pos, d.radius * 0.5, PAL.Vortex, 0.25)
	Fx.sound(Fx.Sounds.Blast, FX, d.pos, 1, 0.8)
	Fx.shake(0.9, d.time + 0.2, d.pos)
end

function handlers.DiscDetonate(d)
	local PAL = discs[d.id] and discs[d.id].pal or Perk.pal(d.userId)
	local mine = discs[d.id] and discs[d.id].isLocal
	endDisc(d.id)
	local g0, n0 = groundAt(d.pos)
	if (g0 - d.pos).Magnitude < d.radius then
		Fx.cracks(FX, g0, n0, 12, PAL.DiscRim, 7)
	end
	if mine then
		impactFrame(PAL.Vortex)
		Fx.envelope({ fov = 10, contrast = 0.2, blur = 4, attack = 0.02, release = 0.45 })
	end
	local pos, radius = d.pos, d.radius
	Fx.flash(FX, pos, radius * 1.2, PAL.Vortex, 0.45)
	Fx.shockwave(FX, pos, UP, radius, radius * 3.4, PAL.Vortex, 0.6)
	Fx.shockwave(FX, pos, Vector3.new(math.random() - 0.5, 0.4, math.random() - 0.5).Unit, radius * 0.8, radius * 2.6, PAL.DiscRim, 0.5)
	Fx.burst(FX, pos, PAL.Disc, 50, 2.2, 95)
	Fx.dust(FX, groundAt(pos), radius * 0.4, 16)
	Fx.sound(Fx.Sounds.Impact, FX, pos, 1, 0.7)
	Fx.shake(2, 0.6, pos)
end

function handlers.DiscCancel(d)
	endDisc(d.id)
end

function handlers.PowerOn(d)
	local PAL = Perk.pal(d.userId)
	local pos = d.pos
	local gp, np = groundAt(pos)
	Fx.cracks(FX, gp, np, 6, PAL.PowerEmber, 5)
	if d.userId == player.UserId then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		Fx.envelope({ tint = PAL.PowerAura, sat = 0.25, contrast = 0.1, fov = -4, attack = 0.15, hold = 0.4, release = 0.9 })
	end
	Fx.flash(FX, pos, 10, PAL.PowerEmber, 0.45)
	Fx.shockwave(FX, groundAt(pos) + UP * 0.3, UP, 4, 36, PAL.PowerAura, 0.6)
	Fx.burst(FX, pos, PAL.PowerEmber, 40, 1.2, 50)
	Fx.sound(Fx.Sounds.Rise, FX, pos, 1, 1.1)
	Fx.shake(0.8, 0.4, pos)
end

function handlers.PowerOff(d)
	local PAL = Perk.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		Fx.burst(FX, hrp.Position, PAL.PowerEmber, 24, 0.8, 25)
	end
end

-- the beast camera: the player's own zoom limits and distance are saved, the focus is lifted to the beast's head and
-- the camera eased out to frame it; on the way out it eases back in to the saved distance and hands the limits back
local camState -- { min, max, zoom } while the beast camera holds the view, else nil
local camToken = 0
local camTween
local function currentZoom()
	local cam = workspace.CurrentCamera
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude
end
local function cameraOffset(hum, y, time)
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	if hum and hum.Parent then
		camTween = Fx.tween(hum, time, { CameraOffset = Vector3.new(0, y, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end
local function smooth01(a)
	return a * a * (3 - 2 * a)
end
local function beastCamera(on, time)
	local M = CFG.Morph
	time = time or M.GrowTime
	camToken += 1
	local tok = camToken
	local _, hum = myChar()
	if on then
		if not camState then
			camState = { min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance, zoom = currentZoom() }
		end
		player.CameraMaxZoomDistance = math.max(camState.max, M.CameraMaxZoom)
		cameraOffset(hum, M.CameraLift, time)
		-- raising the min zoom pushes the camera out; afterwards the player may scroll back in to CameraMinZoom
		local from = math.min(camState.min, M.CameraZoom)
		local t0 = os.clock()
		task.spawn(function()
			while camToken == tok do
				local a = math.min((os.clock() - t0) / time, 1)
				player.CameraMinZoomDistance = from + (M.CameraZoom - from) * smooth01(a)
				if a >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			if camToken == tok then
				player.CameraMinZoomDistance = M.CameraMinZoom
			end
		end)
	elseif camState then
		local saved = camState
		camState = nil
		cameraOffset(hum, 0, time)
		player.CameraMinZoomDistance = saved.min
		-- lowering the max zoom pulls the camera back in to where the player had it
		local from = math.max(currentZoom(), saved.min)
		local target = math.clamp(saved.zoom, saved.min, saved.max)
		local t0 = os.clock()
		task.spawn(function()
			while camToken == tok and from > target do
				local a = math.min((os.clock() - t0) / time, 1)
				player.CameraMaxZoomDistance = math.max(from + (target - from) * smooth01(a), saved.min)
				if a >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			if camToken == tok then
				player.CameraMaxZoomDistance = saved.max
			end
		end)
	end
end

-- small helpers for the one-shot visuals below
local function fxPart(name, shape, material, color, life)
	local p = Fx.part(name, shape, material, color, FX)
	Debris:AddItem(p, life)
	return p
end
local VERT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder part's axis is X; this stands it upright

local ORANGE, RED, HOT = PAL.BeastBody, PAL.BeastAccent, PAL.BeastCore
local morphRocks = {} -- [userId] = floating rocks lifted during the gather
local beasts = {} -- [character] = construct animation state (filled further down)

function handlers.MorphStart(d)
	Perk.morphPal[d.userId] = Perk.pal(d.userId) -- the form keeps the palette it started with
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	local pos, gather = d.pos, d.gather
	local char = charOf(d.userId)
	local ground, gn = groundAt(pos)
	if char then
		pose(char, "Raise", nil, gather, gather + 0.25)
	end
	-- a column of chakra thickens around the caster
	local pillar = fxPart("ChakraPillar", Enum.PartType.Cylinder, Enum.Material.Neon, ORANGE, gather + 0.1)
	pillar.Size = Vector3.new(500, 1, 1)
	pillar.CFrame = CFrame.new(ground + UP * 250) * VERT
	pillar.Transparency = 0.6
	Fx.tween(pillar, gather, { Size = Vector3.new(500, 9, 9), Transparency = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- waves of light are sucked in, rings collapse onto the caster
	for i = 0, 3 do
		task.delay(i * gather / 4, function()
			GFX.streaks(FX, pos + UP * 4, { inward = 40, count = 38, life = 0.85, size = 1.3, color = HOT, color2 = ORANGE })
			GFX.ring(FX, ground + UP * 0.3, UP, 84 - i * 10, 8, ORANGE, 0.9, { ease = "in" })
			Fx.shake(0.25 + i * 0.2, 0.3, pos)
		end)
	end
	-- chakra lightning crawls up from the ground
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < gather do
			local ang, r = math.random() * math.pi * 2, 4 + math.random() * 16
			local from = ground + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			GFX.bolt(FX, from, pos + UP * (5 + math.random() * 9), { color = ORANGE, core = HOT, width = 0.2, segments = 6, jag = 0.9, life = 0.1 })
			task.wait(0.06)
		end
	end)
	Fx.cracks(FX, ground, gn, 24, RED, gather + 5)
	morphRocks[d.userId] = GFX.liftRocks(FX, ground, 26, 24)
	Fx.sound(Fx.Sounds.Hum, FX, pos, 1, 0.5)
	Fx.sound(Fx.Sounds.Rise, FX, pos, 1, 0.6)
	if d.userId == player.UserId then
		letterbox(true, 0.4)
		Fx.envelope({ fov = -13, tint = RED, bright = -0.1, contrast = 0.12, attack = gather * 0.95, release = 0.08 })
		Fx.shake(0.45, gather, pos)
		-- the burst lifts the bars; if the entrance never gets there (death mid-gather) they still go away
		task.delay(gather + 4, function()
			letterbox(false, 0.5)
		end)
	end
end

function handlers.MorphBurst(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	local pos, radius = d.pos, d.radius
	local ground, gn = groundAt(pos)
	local rocks = morphRocks[d.userId]
	morphRocks[d.userId] = nil
	if rocks then
		rocks:drop(Vector3.new(0, 30, 0))
	end
	-- the beam of chakra that tears up through the sky
	local sky = fxPart("ChakraBlast", Enum.PartType.Cylinder, Enum.Material.Neon, ORANGE, 1.4)
	sky.Size = Vector3.new(700, 16, 16)
	sky.CFrame = CFrame.new(ground + UP * 350) * VERT
	sky.Transparency = 0.05
	Fx.tween(sky, 1.3, { Size = Vector3.new(700, 90, 90), Transparency = 1 }, Enum.EasingStyle.Quart)
	local white = fxPart("ChakraBlastCore", Enum.PartType.Cylinder, Enum.Material.Neon, HOT, 1.0)
	white.Size = Vector3.new(700, 9, 9)
	white.CFrame = CFrame.new(ground + UP * 350) * VERT
	Fx.tween(white, 0.9, { Size = Vector3.new(700, 36, 36), Transparency = 1 }, Enum.EasingStyle.Quart)
	-- domes, rings, light
	GFX.shell(FX, pos + UP * 3, 4, radius, ORANGE, 0.9, Enum.Material.ForceField)
	GFX.shell(FX, pos + UP * 3, 3, radius * 0.6, HOT, 0.5)
	Fx.flash(FX, pos + UP * 6, radius * 0.8, HOT, 0.7)
	GFX.light(FX, pos + UP * 8, ORANGE, 14, 60, 1.2)
	for i = 0, 2 do
		task.delay(i * 0.09, function()
			GFX.ring(FX, ground + UP * 0.4, UP, 6, radius * (1.7 + i * 0.35), i == 1 and HOT or ORANGE, 0.85)
		end)
	end
	Fx.shockwave(FX, ground + UP * 0.5, UP, 8, radius * 2.8, PAL.Shockwave, 1.0)
	Fx.shockwave(FX, pos + UP * 4, Vector3.new(0.3, 1, 0.1).Unit, 6, radius * 2, HOT, 0.7)
	GFX.streaks(FX, pos + UP * 5, { count = 120, speed = { 80, 210 }, color = HOT, color2 = ORANGE, size = 1.7, life = 0.65 })
	GFX.sparks(FX, pos + UP * 5, { color = ORANGE, color2 = HOT, count = 100, speed = { 20, 80 }, size = 1.0 })
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		Fx.dust(FX, ground + Vector3.new(math.cos(a), 0, math.sin(a)) * 14, 9, 7)
	end
	Fx.cracks(FX, ground, gn, radius * 0.5, RED, 9)
	Fx.sound(Fx.Sounds.Impact, FX, pos, 1, 0.45)
	Fx.sound(Fx.Sounds.Blast, FX, pos, 1, 0.5)
	Fx.shake(4.2, 1.3, pos, 260)
	if d.userId == player.UserId then
		impactFrame(RED)
		GFX.speedLines(0.9)
		Fx.envelope({ fov = 30, blur = 14, tint = RED, contrast = 0.2, bright = 0.28, attack = 0.04, hold = 0.2, release = 1.2 })
		showTitle("Morph", PAL ~= CFG.Palette)
		beastCamera(true, d.grow)
		task.delay(1.8, function()
			letterbox(false, 0.5)
		end)
	end
end

function handlers.MorphOn(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	local pos = d.pos
	Fx.flash(FX, pos + UP * 8, 30, HOT, 0.6)
	GFX.glow(FX, pos + UP * 10, 70, ORANGE, 0.7)
	GFX.ring(FX, groundAt(pos) + UP * 0.4, UP, 10, 90, HOT, 0.7)
	Fx.burst(FX, pos + UP * 8, HOT, 60, 2.6, 80)
	Fx.sound(Fx.Sounds.Rise, FX, pos, 1, 0.7)
	Fx.shake(2.2, 0.6, pos)
end

-- the form ends (time up or released): the beast bursts into chakra at its own size and the caster drops out of it
function handlers.MorphEnd(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	Perk.morphPal[d.userId] = nil
	local k = (tonumber(d.scale) or CFG.Morph.Scale) / 5
	local ground = groundAt(d.pos)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		Fx.dust(FX, ground + Vector3.new(math.cos(a), 0, math.sin(a)) * 16 * k, 9 * k, 4)
	end
	Fx.flash(FX, ground + UP * 18 * k, 26 * k, HOT, 0.45)
	GFX.shell(FX, ground + UP * 16 * k, 8 * k, 46 * k, ORANGE, 0.6, Enum.Material.ForceField)
	GFX.sparks(FX, ground + UP * 18 * k, { color = ORANGE, color2 = HOT, count = 70, speed = { 20, 70 }, size = 1.1 })
	GFX.ring(FX, ground + UP * 0.4, UP, 8 * k, 60 * k, ORANGE, 0.6)
	Fx.sound(Fx.Sounds.Rise, FX, d.pos, 0.9, 0.8)
	Fx.shake(1.2, 0.45, d.pos)
	if d.userId == player.UserId then
		beastCamera(false, CFG.Morph.GrowTime)
	end
end

---------------------------------------------------------------------------------------------------
-- the Tailed Beast Bomb: a black core wrapped in a roaring orange shell with spinning rings, charged in the beast's
-- mouth and flown along the server's line (simulated here so it stays smooth)
local bombs = {} -- [id] = { phase, char, vis, size (NumberValue), isLocal, ... }

local function makeBombVis(pal)
	pal = pal or PAL
	local ORANGE, RED, HOT = pal.BeastBody, pal.BeastAccent, pal.BeastCore
	local v = { spin = 0 }
	local function ball(name, material, color, tr)
		local p = Fx.part(name, Enum.PartType.Ball, material, color, FX)
		p.Transparency = tr or 0
		return p
	end
	v.core = ball("BombCore", Enum.Material.SmoothPlastic, pal.BombCore or Color3.fromRGB(24, 5, 5))
	v.mid = ball("BombMid", Enum.Material.Neon, pal.BombMid or Color3.fromRGB(255, 118, 22), 0.25)
	v.outer = ball("BombOuter", Enum.Material.ForceField, RED, 0.1)
	v.halo = ball("BombHalo", Enum.Material.Neon, pal.BombHalo or Color3.fromRGB(255, 186, 90), 0.82)
	v.ringA = Fx.part("BombRingA", Enum.PartType.Cylinder, Enum.Material.Neon, HOT, FX)
	v.ringB = Fx.part("BombRingB", Enum.PartType.Cylinder, Enum.Material.Neon, ORANGE, FX)
	v.ringA.Transparency, v.ringB.Transparency = 0.2, 0.3
	v.light = Instance.new("PointLight")
	v.light.Color, v.light.Range, v.light.Brightness, v.light.Shadows = ORANGE, 70, 7, false
	v.light.Parent = v.mid
	Fx.emitter(v.halo, {
		Texture = Fx.Tex.fire, Color = ColorSequence.new(HOT, ORANGE, RED), LightEmission = 1, Rate = 80,
		Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(4, 16), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.2, 1), Rotation = NumberRange.new(0, 360),
	})
	function v:set(pos, size, dt)
		self.spin += dt * 5
		local cf = CFrame.new(pos)
		self.core.Size, self.core.CFrame = Vector3.one * size * 0.55, cf
		self.mid.Size, self.mid.CFrame = Vector3.one * size * (0.82 + math.sin(self.spin * 3) * 0.03), cf
		self.outer.Size, self.outer.CFrame = Vector3.one * size * 1.02, cf * CFrame.Angles(self.spin * 0.3, self.spin * 0.2, 0)
		self.halo.Size, self.halo.CFrame = Vector3.one * size * 1.55, cf
		self.ringA.Size = Vector3.new(size * 0.05, size * 1.75, size * 1.75)
		self.ringA.CFrame = cf * CFrame.Angles(self.spin, 0, 0.55)
		self.ringB.Size = Vector3.new(size * 0.05, size * 1.55, size * 1.55)
		self.ringB.CFrame = cf * CFrame.Angles(0, self.spin * 0.8, 1.3)
		self.light.Brightness = 6 + math.sin(self.spin * 4) * 1.5
	end
	function v:destroy()
		for _, p in ipairs({ self.core, self.mid, self.outer, self.halo, self.ringA, self.ringB }) do
			p:Destroy()
		end
	end
	return v
end

-- the beast's snout tip, and the way it faces
local function mouthOf(char)
	local model = char and char:FindFirstChild("BeastConstruct")
	local nose = model and model:FindFirstChild("Nose", true)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local fwd = hrp and hrp.CFrame.LookVector * Vector3.new(1, 0, 1) or Vector3.new(0, 0, -1)
	fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
	if nose then
		return nose.Position, fwd
	end
	return hrp and (hrp.Position + fwd * 12 + UP * 8), fwd
end

local function endBomb(id)
	local b = bombs[id]
	if not b then
		return
	end
	bombs[id] = nil
	b.vis:destroy()
	if b.rocks then
		b.rocks:drop()
	end
end

function handlers.BombCharge(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	local char = charOf(d.userId)
	if not char then
		return
	end
	local b = { phase = "charge", char = char, vis = makeBombVis(PAL), pal = PAL, hot = HOT, orange = ORANGE, size = grower(0.5, d.size, d.time * 0.92), isLocal = d.userId == player.UserId, nextFx = 0, nextBolt = 0, time = d.time }
	bombs[d.id] = b
	local mouth = mouthOf(char)
	local ground = mouth and groundAt(mouth) or nil
	if ground then
		b.rocks = GFX.liftRocks(FX, ground, 22, 18)
		Fx.cracks(FX, ground, UP, 20, RED, d.time + 2)
	end
	if mouth then
		Fx.sound(Fx.Sounds.Charge, FX, mouth, 1, 0.45)
		Fx.sound(Fx.Sounds.Hum, FX, mouth, 1, 0.5)
	end
	if b.isLocal then
		showTitle("Bomb", PAL ~= CFG.Palette)
		rootUntil = os.clock() + d.time + 0.55
		Fx.envelope({ fov = -10, tint = RED, bright = -0.07, contrast = 0.1, attack = d.time * 0.9, release = 0.15 })
		Fx.shake(0.8, d.time, mouth)
		task.delay(math.max(d.time - 0.08, 0), function()
			Request:FireServer("DiscAim", { id = d.id, target = cursorTarget() })
		end)
	end
	task.delay(d.time + 3, function()
		if bombs[d.id] == b and b.phase == "charge" then
			endBomb(d.id)
		end
	end)
end

function handlers.BombCancel(d)
	endBomb(d.id)
end

function handlers.BombLaunch(d)
	local b = bombs[d.id]
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, b and b.pal or Perk.morphPal[d.userId])
	if not b then
		b = { vis = makeBombVis(PAL), pal = PAL, hot = HOT, orange = ORANGE, size = grower(d.size, d.size, 0.01), isLocal = d.userId == player.UserId }
		bombs[d.id] = b
	end
	local off = b.lastPos and (b.lastPos - d.origin):Dot(d.dir) or 0
	b.phase, b.origin, b.dir, b.speed, b.t0, b.startOffset, b.nextRing = "flight", d.origin, d.dir, d.speed, os.clock(), off, 0
	if b.rocks then
		b.rocks:drop(d.dir * 40 + UP * 20)
		b.rocks = nil
	end
	-- the muzzle blast
	GFX.streaks(FX, d.origin, { dir = d.dir, spread = 32, speed = { 90, 230 }, count = 70, color = HOT, color2 = ORANGE, size = 1.6 })
	Fx.shockwave(FX, d.origin, d.dir, 6, 56, HOT, 0.45)
	Fx.flash(FX, d.origin, 22, ORANGE, 0.45)
	GFX.sparks(FX, d.origin, { color = ORANGE, color2 = HOT, count = 40, speed = { 30, 90 }, size = 0.9 })
	Fx.sound(Fx.Sounds.Launch, FX, d.origin, 1, 0.45)
	Fx.sound(Fx.Sounds.Blast, FX, d.origin, 0.9, 0.7)
	Fx.shake(2.2, 0.5, d.origin)
	if b.isLocal then
		GFX.speedLines(0.7)
		Fx.envelope({ fov = 16, blur = 7, tint = ORANGE, attack = 0.03, release = 0.5 })
		rootUntil = os.clock() + 0.35
	end
end

function handlers.BombHit(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, bombs[d.id] and bombs[d.id].pal or Perk.morphPal[d.userId])
	local mine = bombs[d.id] and bombs[d.id].isLocal or d.userId == player.UserId
	endBomb(d.id)
	local pos, radius = d.pos, d.radius
	local ground, gn = groundAt(pos)
	if mine then
		impactFrame(ORANGE)
		GFX.speedLines(0.8)
		Fx.envelope({ fov = 26, blur = 16, tint = RED, contrast = 0.25, bright = 0.35, attack = 0.03, hold = 0.15, release = 1.3 })
	end
	-- 1. the flash and the first fireball
	Fx.flash(FX, pos, radius * 0.9, HOT, 0.7)
	GFX.light(FX, pos + UP * 10, ORANGE, 16, 60, 1.5)
	GFX.glow(FX, pos + UP * 6, radius * 2, HOT, 0.55)
	GFX.shell(FX, pos + UP * 4, 4, radius * 0.75, HOT, 0.55)
	GFX.shell(FX, pos + UP * 4, 3, radius * 1.25, ORANGE, 0.9, Enum.Material.ForceField)
	GFX.shell(FX, pos + UP * 4, 2, radius * 1.8, RED, 1.3, Enum.Material.ForceField)
	-- 2. rings racing out along the ground and standing up
	for i = 0, 3 do
		task.delay(i * 0.07, function()
			GFX.ring(FX, ground + UP * 0.5, UP, 8, radius * (1.6 + i * 0.5), i % 2 == 0 and HOT or ORANGE, 0.9)
		end)
	end
	Fx.shockwave(FX, ground + UP * 0.6, UP, 10, radius * 3.4, PAL.Shockwave, 1.1)
	Fx.shockwave(FX, pos + UP * 4, Vector3.new(1, 0.15, 0.2).Unit, 8, radius * 2.2, HOT, 0.8)
	-- 3. the mushroom cloud: a stem of fire, a cap that climbs and spreads, the cap's ring
	local stem = fxPart("BombStem", Enum.PartType.Cylinder, Enum.Material.Neon, ORANGE, 1.7)
	stem.Size = Vector3.new(2, 12, 12)
	stem.CFrame = CFrame.new(ground + UP) * VERT
	Fx.tween(stem, 1.2, { Size = Vector3.new(80, 20, 20), CFrame = CFrame.new(ground + UP * 40) * VERT, Transparency = 0.92 }, Enum.EasingStyle.Quart)
	local cap = fxPart("BombCap", Enum.PartType.Ball, Enum.Material.Neon, HOT, 2.2)
	cap.Size = Vector3.one * 10
	cap.CFrame = CFrame.new(ground + UP * 6)
	cap.Transparency = 0.1
	Fx.tween(cap, 1.8, { Size = Vector3.one * 64, CFrame = CFrame.new(ground + UP * 84), Transparency = 0.93, Color = RED }, Enum.EasingStyle.Quart)
	local capShell = fxPart("BombCapShell", Enum.PartType.Ball, Enum.Material.ForceField, ORANGE, 2.2)
	capShell.Size = Vector3.one * 12
	capShell.CFrame = CFrame.new(ground + UP * 6)
	Fx.tween(capShell, 1.8, { Size = Vector3.one * 78, CFrame = CFrame.new(ground + UP * 84), Transparency = 1 }, Enum.EasingStyle.Quart)
	Fx.emitter(cap, {
		Texture = Fx.Tex.smoke, Color = ColorSequence.new(Color3.fromRGB(70, 30, 20), Color3.fromRGB(30, 22, 22)), LightEmission = 0.25,
		Rate = 70, Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(6, 24), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(1, 34) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }), Rotation = NumberRange.new(0, 360),
	})
	task.delay(0.35, function()
		GFX.ring(FX, ground + UP * 60, UP, 8, 120, HOT, 1.1)
	end)
	-- 4. debris, sparks, dust, scorch, and embers raining down afterwards
	GFX.streaks(FX, pos + UP * 4, { count = 150, speed = { 90, 260 }, color = HOT, color2 = ORANGE, size = 2.0, life = 0.7 })
	GFX.sparks(FX, pos + UP * 4, { color = ORANGE, color2 = HOT, count = 140, speed = { 30, 110 }, size = 1.2 })
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		Fx.dust(FX, ground + Vector3.new(math.cos(a), 0, math.sin(a)) * (radius * 0.4), 12, 8)
	end
	Fx.cracks(FX, ground, gn, 24, RED, 10)
	local rain = fxPart("EmberRain", Enum.PartType.Block, Enum.Material.SmoothPlastic, ORANGE, 5)
	rain.Transparency = 1
	rain.Size = Vector3.new(radius * 1.2, 1, radius * 1.2)
	rain.CFrame = CFrame.new(pos + UP * 40)
	local ember = Fx.emitter(rain, {
		Texture = Fx.Tex.flare, Color = ColorSequence.new(HOT, ORANGE), LightEmission = 1, Rate = 90, Lifetime = NumberRange.new(1.6, 2.6),
		Speed = NumberRange.new(0, 6), Acceleration = Vector3.new(0, -14, 0), EmissionDirection = Enum.NormalId.Bottom,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }),
	})
	task.delay(2.5, function()
		ember.Enabled = false
	end)
	Fx.sound(Fx.Sounds.Impact, FX, pos, 1, 0.38)
	Fx.sound(Fx.Sounds.Blast, FX, pos, 1, 0.45)
	Fx.sound(Fx.Sounds.Impact, FX, pos, 0.9, 0.7)
	Fx.shake(6, 1.6, pos, 360)
end

---------------------------------------------------------------------------------------------------
-- the claw swipe
function handlers.ClawStart(d)
	local char = charOf(d.userId)
	local bs = char and beasts[char]
	if bs then
		bs.claw = { side = d.side or 1, t0 = os.clock(), windup = d.windup or 0.25 }
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		Fx.sound(Fx.Sounds.Launch, FX, hrp.Position, 1, 0.5)
		if d.userId == player.UserId then
			faceDir(hrp, d.dir)
		end
	end
end

function handlers.Claw(d)
	local PAL, ORANGE, RED, HOT = Perk.skin(d.userId, Perk.morphPal[d.userId])
	local origin, dir, side = d.origin, d.dir, d.side or 1
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	-- drawn at the beast's own size: three claw marks sweeping across in front of the forepaws
	local k = CFG.Morph.Scale / 5
	local ground = groundAt(origin)
	local mid = ground + UP * 10 * k
	local base = CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, 0, math.rad(22 * side))
	local half = math.rad(d.arc / 2)
	local n, radius = 10, d.range * 0.55
	local segs = {}
	for claw = -1, 1 do
		for layer = 1, 2 do
			for i = 1, n do
				local k = (i - 1) / (n - 1)
				local seg = fxPart("ClawArc", Enum.PartType.Block, Enum.Material.Neon, layer == 1 and HOT or ORANGE, 0.7)
				seg.Transparency = 1
				table.insert(segs, { part = seg, k = k, mid = 1 - math.abs(k - 0.5) * 2, layer = layer, off = claw * 0.16 })
			end
		end
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 0.6 then
			conn:Disconnect()
			return
		end
		local reveal = math.clamp(t / 0.1, 0, 1)
		local grow = radius + math.max(t - 0.08, 0) * 95
		local fade = math.clamp((t - 0.12) / 0.45, 0, 1)
		for _, s in ipairs(segs) do
			local kk = side > 0 and s.k or 1 - s.k
			if s.part.Parent and kk <= reveal then
				local ang = -half + s.k * 2 * half
				local r = grow * (1 + s.off)
				local thick = (s.layer == 1 and 1.1 or 2.6) * k * (0.2 + 0.8 * s.mid) * (1 - fade * 0.6)
				s.part.Size = Vector3.new(r * 2 * half / n * 1.2, thick, thick * 0.55)
				s.part.CFrame = base * CFrame.Angles(0, ang, 0) * CFrame.new(0, s.off * 22 * k, -r) * CFrame.Angles(0, math.rad(90), 0)
				s.part.Transparency = (s.layer == 1 and 0.05 or 0.4) + fade * 0.95
			end
		end
	end)
	GFX.streaks(FX, mid + dir * radius, { color = HOT, color2 = ORANGE, dir = dir, spread = d.arc / 2, speed = { 90, 190 }, count = 50, size = 1.4 * k })
	GFX.glow(FX, mid + dir * radius * 0.7, 46 * k, ORANGE, 0.4)
	-- three furrows raked into the ground ahead of the paws: one glowing line each, a crack where it ends
	local start = tonumber(d.start) or 8
	for _, ang in ipairs({ -0.5, 0, 0.5 }) do
		local dd = CFrame.fromAxisAngle(UP, ang):VectorToWorldSpace(dir)
		local gs, ge = groundAt(origin + dd * start), groundAt(origin + dd * d.fissure)
		local len = (ge - gs).Magnitude
		local line = fxPart("ClawFurrow", Enum.PartType.Block, Enum.Material.Neon, ORANGE, 1.6)
		line.Size = Vector3.new(1.8 * k, 0.2, len)
		line.CFrame = CFrame.lookAt((gs + ge) / 2 + UP * 0.2, ge + UP * 0.2)
		Fx.tween(line, 1.4, { Size = Vector3.new(0.1, 0.2, len), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local g, nrm = groundAt(origin + dd * d.fissure)
		Fx.cracks(FX, g, nrm, 4.5 * k, ORANGE, 4)
		Fx.dust(FX, groundAt(origin + dd * (start + d.fissure) * 0.5), 7 * k, 3)
	end
	Fx.sound(Fx.Sounds.Impact, FX, origin + dir * radius, 1, 0.8)
	Fx.shake(2.4, 0.5, origin)
	if d.userId == player.UserId then
		GFX.speedLines(0.35)
		Fx.envelope({ fov = 9, blur = 3, attack = 0.03, release = 0.3 })
	end
end

-- a batch of hits from the server: damage numbers over every body, plus the hit-confirm for the attacker
function handlers.Hits(d)
	Feedback.hits(d, Color3.fromRGB(255, 190, 90))
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[VulpineClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- the nine-tailed fox: trotting legs, breathing body, a head that looks into turns, a jaw that opens for the bomb,
-- nine swaying tails and heavy footsteps (Motor6D.Transform, local only). Every client animates every beast, so a
-- far one is animated at half rate and not at all past BEAST_FAR, and its flame accents switch off past BEAST_FX.
local BEAST_FAR, BEAST_HALF, BEAST_FX = 900, 350, 650
local LEGS = { "BeastLegFL", "BeastLegFR", "BeastLegBL", "BeastLegBR" }
local LEG_PHASE = { BeastLegFL = 0, BeastLegBR = 0, BeastLegFR = math.pi, BeastLegBL = math.pi } -- a diagonal trot

local function registerBeast(char, model)
	local joints, tails, emitters = {}, {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			joints[d.Name] = d
			local ti, si = d.Name:match("^Tail(%d+)_(%d+)$")
			if ti then
				tails[tonumber(ti)] = tails[tonumber(ti)] or {}
				tails[tonumber(ti)][tonumber(si)] = d
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(emitters, d)
		end
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	beasts[char] = {
		model = model, joints = joints, tails = tails, emitters = emitters, fxOn = true, nextGate = 0, half = false, owed = 0,
		t = math.random() * 10, phase = 0, stride = 0, air = 0, jaw = 0, lean = 0,
		yaw = hrp and math.atan2(-hrp.CFrame.LookVector.X, -hrp.CFrame.LookVector.Z) or 0,
		sway = 0, swayVel = 0, isLocal = char == player.Character,
	}
end

local function footstep(b, pawName, dist)
	local paw = b.model:FindFirstChild(pawName)
	if not paw or dist > CFG.Morph.StepFxRadius then
		return
	end
	local k = CFG.Morph.Scale / 5
	local foot = groundAt(paw.Position)
	Fx.dust(FX, foot, 5 * k, 3)
	if dist < 220 then
		Fx.sound(Fx.Sounds.Step or Fx.Sounds.Impact, FX, foot, 0.35, 0.45)
	end
	local R = CFG.Morph.StepShakeRadius
	if dist < R then
		-- your own steps are a soft thud; another beast's land harder the closer it is
		Fx.shake(CFG.Morph.StepShake * (1 - dist / R) * (b.isLocal and 0.5 or 1), 0.22)
	end
end

local function animateBeast(char, b, dt)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local cam = workspace.CurrentCamera
	local dist = (cam.Focus.Position - hrp.Position).Magnitude
	local clock = os.clock()
	if clock >= b.nextGate then
		b.nextGate = clock + 0.5
		local want = dist < BEAST_FX
		if want ~= b.fxOn then
			b.fxOn = want
			for _, e in ipairs(b.emitters) do
				e.Enabled = want
			end
		end
	end
	if dist > BEAST_FAR then
		return
	end
	if dist > BEAST_HALF then
		b.half = not b.half
		if b.half then
			b.owed += dt
			return
		end
	end
	dt += b.owed
	b.owed = 0

	local k = CFG.Morph.Scale / 5
	local hum = char:FindFirstChildOfClass("Humanoid")
	local v = hrp.AssemblyLinearVelocity
	local speed = (v * Vector3.new(1, 0, 1)).Magnitude
	local run = math.clamp(speed / (30 * k), 0, 1)
	b.t += dt
	-- legs cycle once per ~two body lengths of travel, so the paws plant instead of skating
	local prevPhase = b.phase
	b.phase += dt * math.pi * speed / (20 * k)
	b.stride += (run - b.stride) * math.min(dt * 6, 1)
	local state = hum and hum:GetState()
	local airborne = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	b.air += ((airborne and 1 or 0) - b.air) * math.min(dt * 8, 1)
	-- turning drives a spring: the body leans in, the head looks in, the tails swing out and settle
	local look = hrp.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local dYaw = (yaw - b.yaw + math.pi) % (2 * math.pi) - math.pi
	b.yaw = yaw
	local turn = math.clamp(-dYaw / math.max(dt, 1e-3) * 0.12, -0.7, 0.7)
	b.swayVel += (turn - b.sway) * 40 * dt
	b.swayVel *= math.exp(-6 * dt)
	b.sway += b.swayVel * dt
	b.lean += (math.clamp(turn * 0.18, -0.1, 0.1) * b.stride - b.lean) * math.min(dt * 5, 1)

	local j = b.joints
	local function set(name, cf)
		local m = j[name]
		if m then
			m.Transform = cf
		end
	end
	local amp = 0.38 * b.stride
	local legs = {}
	for _, name in ipairs(LEGS) do
		local front = name:sub(9, 9) == "F" -- BeastLeg[F|B][L|R]
		local sw = math.sin(b.phase + LEG_PHASE[name]) * amp
		-- in the air the forelegs reach forward and the hind legs trail
		sw += b.air * (front and 0.45 or -0.4)
		legs[name] = CFrame.Angles(sw, 0, 0)
	end
	local breathe = math.sin(b.t * 1.6) * 0.25 * k
	local bob = (math.abs(math.cos(b.phase)) - 0.6) * 0.9 * k * b.stride
	local bodyPitch = math.sin(b.phase * 2) * 0.025 * b.stride - b.air * 0.06
	local bodyLift = 0
	local jawOpen = 0.04 + 0.03 * math.sin(b.t * 2.2)
	local headPitch = math.sin(b.t * 1.1) * 0.04 + math.sin(b.phase * 2) * 0.04 * b.stride
	-- the bomb charging in this beast's mouth: head up, jaws wide
	for _, bm in pairs(bombs) do
		if bm.char == char and bm.phase == "charge" then
			jawOpen = 0.55
			headPitch += 0.12
			break
		end
	end
	-- the claw swipe: rear up, draw one forepaw back and high, then rake it down and across
	local claw = b.claw
	if claw then
		local e = clock - claw.t0
		local w = claw.windup
		local pitch, swing, roll = 0, 0, 0
		if e < w then
			local q = math.sin(e / w * math.pi / 2)
			pitch, swing, roll = 0.2 * q, 1.2 * q, 0.18 * q
		elseif e < w + 0.55 then
			local q = (e - w) / 0.55
			local strike = math.min(q / 0.25, 1)
			local settle = math.clamp((q - 0.35) / 0.65, 0, 1)
			local blend = 1 - settle * settle * (3 - 2 * settle)
			pitch = (0.2 - 0.28 * strike) * blend
			swing = (1.2 - 1.65 * strike) * blend
			roll = (0.18 - 0.5 * strike) * blend
		else
			b.claw = nil
		end
		local side = claw.side > 0 and 1 or -1
		legs[side > 0 and "BeastLegFR" or "BeastLegFL"] = CFrame.Angles(swing, 0, roll * side)
		legs[side > 0 and "BeastLegFL" or "BeastLegFR"] = CFrame.Angles(-math.abs(swing) * 0.25, 0, 0)
		bodyPitch += pitch
		bodyLift += pitch * 7 * k -- rearing about the body centre would sink the hind paws: lift with it
		jawOpen = math.max(jawOpen, 0.3)
	end
	for name, cf in pairs(legs) do
		set(name, cf)
	end
	set("BeastBody", CFrame.new(0, breathe + bob + bodyLift, 0) * CFrame.Angles(bodyPitch, 0, b.lean))
	set("BeastHead", CFrame.Angles(headPitch, math.sin(b.t * 0.6) * 0.07 - b.sway * 0.3, -b.lean * 0.5))
	b.jaw += (jawOpen - b.jaw) * math.min(dt * 10, 1)
	set("BeastJaw", CFrame.Angles(-b.jaw, 0, 0))
	-- tails: each sways on its own beat, the outer segment lagging the inner; running streams them back, a turn
	-- swings them out, a jump lifts them
	for i, chain in pairs(b.tails) do
		for s, m in pairs(chain) do
			local w = s == 1 and 1 or 1.7
			local lift = math.sin(b.t * 1.45 + i * 0.8 - s * 0.9) * 0.08 * w
			local side = math.sin(b.t * 1.05 + i * 1.35 - s * 0.9) * 0.1 * w
			local streak = (s == 1 and -0.16 or 0.06) * b.stride + b.air * 0.12
			m.Transform = CFrame.Angles(lift + streak, side + b.sway * (s == 1 and 0.25 or 0.4), 0)
		end
	end
	-- a footstep each time a forepaw plants
	if b.stride > 0.2 and not airborne and math.floor(prevPhase / math.pi) ~= math.floor(b.phase / math.pi) then
		footstep(b, math.floor(b.phase / math.pi) % 2 == 0 and "PawFL" or "PawFR", dist)
	end
end

RunService.Stepped:Connect(function(_, dt)
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local model = char and char:GetAttribute("Morphed") and char:FindFirstChild("BeastConstruct")
		if model and (not beasts[char] or beasts[char].model ~= model) then
			registerBeast(char, model)
		end
	end
	for char, b in pairs(beasts) do
		if not b.model.Parent or not char.Parent then
			beasts[char] = nil
		else
			local ok, err = pcall(animateBeast, char, b, dt)
			if not ok then
				warn("[VulpineClient] beast anim: " .. tostring(err))
				beasts[char] = nil
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- power-mode enemy sense: outlines on every enemy body within SenseRadius (caster's screen only)
local outlines = {} -- [model] = Highlight
local nextSense = 0
local function updateSense(char, hrp)
	if os.clock() < nextSense then
		return
	end
	nextSense = os.clock() + 0.2
	local active = char and char:GetAttribute("PowerMode") == true
	local want = {}
	if active then
		local list = {}
		for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
			table.insert(list, m)
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= player and pl.Character then
				table.insert(list, pl.Character)
			end
		end
		local near = {}
		for _, m in ipairs(list) do
			local r = m:FindFirstChild("HumanoidRootPart")
			if r and m.Parent then
				local d = (r.Position - hrp.Position).Magnitude
				if d <= CFG.Power.SenseRadius then
					table.insert(near, { m = m, d = d })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.d < b.d
		end)
		for i = 1, math.min(#near, 25) do -- Highlights are capped engine-side, keep well under it
			want[near[i].m] = true
		end
	end
	for m, h in pairs(outlines) do
		if not want[m] then
			h:Destroy()
			outlines[m] = nil
		end
	end
	for m in pairs(want) do
		if not outlines[m] then
			local h = Instance.new("Highlight")
			h.Adornee = m
			local eye = Perk.pal(player.UserId).PowerEye
			h.FillColor = eye
			h.FillTransparency = 0.85
			h.OutlineColor = eye
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = FX
			outlines[m] = h
		end
	end
end

---------------------------------------------------------------------------------------------------
-- per frame: cast visuals, local movement, HUD
local function frame(dt)
	for id, s in pairs(spheres) do
		local hp = s.char.Parent and handPoint(s.char)
		if not hp then
			endSphere(id, 0)
		else
			s.vis:set(hp, s.size.Value, dt)
		end
	end
	for id, c in pairs(discs) do
		local pos
		if c.phase == "channel" then
			local hp = c.char and c.char.Parent and handPoint(c.char)
			pos = hp and hp + UP * (1 + c.size.Value * 0.3)
		elseif c.phase == "flight" then
			-- steer my own disc: keep telling the server where the cursor is while it flies
			if c.isLocal and os.clock() >= (c.nextAim or 0) then
				c.nextAim = os.clock() + CFG.Disc.SteerInterval
				Request:FireServer("DiscAim", { id = id, target = cursorTarget() })
			end
			if c.carrier and c.carrier.Parent then
				pos = c.carrier.Position
			elseif c.origin and c.dir then
				pos = c.origin + c.dir * CFG.Disc.Speed * (os.clock() - c.t0)
			end
		elseif c.phase == "vortex" then
			pos = c.pos
			if c.vortex then
				c.vortex:update(dt)
			end
		end
		if pos then
			c.vis:set(pos, c.size.Value, dt)
		elseif c.phase ~= "vortex" then
			endDisc(id)
		end
	end

	for id, bomb in pairs(bombs) do
		if bomb.phase == "charge" then
			local mouth, fwd = mouthOf(bomb.char)
			if not mouth or not bomb.char.Parent then
				endBomb(id)
			else
				local cur = bomb.size.Value
				local pos = mouth + fwd * (cur * 0.5 + 2) + UP * 1
				bomb.lastPos = pos
				bomb.vis:set(pos, cur, dt)
				if os.clock() >= bomb.nextFx then
					bomb.nextFx = os.clock() + 0.16
					GFX.streaks(FX, pos, { inward = cur * 2.2, count = 10, life = 0.5, size = 1.0, color = bomb.hot or HOT, color2 = bomb.orange or ORANGE })
				end
				if os.clock() >= bomb.nextBolt then
					bomb.nextBolt = os.clock() + 0.05
					GFX.arcs(FX, pos, cur * 0.85, { count = 1, colors = { bomb.orange or ORANGE, bomb.hot or HOT }, width = 0.14, life = 0.1 })
				end
			end
		elseif bomb.phase == "flight" then
			local el = os.clock() - bomb.t0
			local catch = 1 - math.min(el / 0.15, 1)
			local pos = bomb.origin + bomb.dir * (bomb.speed * el + bomb.startOffset * catch)
			bomb.vis:set(pos, bomb.size.Value, dt)
			if os.clock() >= bomb.nextRing then
				bomb.nextRing = os.clock() + 0.045
				Fx.shockwave(FX, pos, bomb.dir, bomb.size.Value * 0.7, bomb.size.Value * 2.6, el % 0.09 < 0.045 and (bomb.hot or HOT) or (bomb.orange or ORANGE), 0.5)
				GFX.arcs(FX, pos, bomb.size.Value * 0.9, { count = 1, colors = { bomb.orange or ORANGE, bomb.hot or HOT }, width = 0.16, life = 0.1 })
				local g = groundAt(pos)
				if (g - pos).Magnitude < 14 then
					Fx.dust(FX, g, 8, 2)
				end
			end
			if el > 3 then
				endBomb(id)
			end
		end
	end

	local char, hum, hrp = myChar()
	if hum then
		local clock = os.clock()
		-- rooted while channelling the disc; otherwise the server's walk speed (power mode / morph)
		local ws = clock < rootUntil and 0 or (char:GetAttribute("KitWalkSpeed") or hum.WalkSpeed)
		if equipped() and hum.WalkSpeed ~= ws then
			hum.WalkSpeed = ws
		end
		if tumbleUntil > 0 and clock >= tumbleUntil then
			tumbleUntil = 0
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	if hrp then
		updateSense(char, hrp)
	end

	-- the beast camera never outlives the form (released, timed out, killed, kit switched)
	if camState and not (char and char:GetAttribute("Morphed")) then
		beastCamera(false)
	end

	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local t = now()
	local form = inForm()
	punchName.Text = form and CFG.Labels.Claw or "PUNCH"
	punchGrad.Color = form and ColorSequence.new(HOT, ORANGE) or ColorSequence.new(Color3.fromRGB(255, 240, 230), Color3.fromRGB(255, 180, 90))
	morphName.Text = form and CFG.Labels.Bomb or CFG.Labels.Morph
	morphSub.Text = form and morphSubForm or (CFG.Callouts.Morph.sub or "") -- (2026-11-11) subForm with the bound keys
	releaseBtn.Visible = form
	if form then
		local ready = t >= (char:GetAttribute("MorphReadyAt") or 0)
		releaseLabel.TextTransparency = ready and 0 or 0.5
		releaseBtn.BackgroundTransparency = ready and 0.15 or 0.45
		releaseStroke.Transparency = ready and (0.25 + 0.25 * math.sin(os.clock() * 4)) or 0.7
	end
	local timers = {}
	for skill, b in pairs(buttons) do
		local activeUntil = char and ((skill == "Power" and char:GetAttribute("PowerMode") and char:GetAttribute("PowerUntil"))
			or (skill == "Morph" and char:GetAttribute("Morphed") and char:GetAttribute("MorphUntil")))
		if activeUntil and activeUntil > t then
			if skill == "Morph" then
				-- in form the pill shows the bomb's cooldown
				local rem = cooldownEnd.Bomb - t
				b.cd.Size = UDim2.fromScale(math.clamp(rem / math.max(CFG.Bomb.Cooldown * Perk.cd(true) + CFG.Bomb.ChargeTime, rem, 0.01), 0, 1), 1)
				b.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""
			else
				b.cd.Size = b.horizontal and UDim2.fromScale(0, 1) or UDim2.fromScale(1, 0)
				b.cdText.Text = ""
			end
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(os.clock() * 6)
			table.insert(timers, string.format("%s %ds", CFG.Labels[skill], math.ceil(activeUntil - t)))
		else
			b.stroke.Transparency = 0
			local rem = cooldownEnd[skill] - t
			local frac = math.clamp(rem / math.max(COOLDOWN[skill] * Perk.cd(skill == "Morph"), rem, 0.01), 0, 1)
			b.cd.Size = b.horizontal and UDim2.fromScale(frac, 1) or UDim2.fromScale(1, frac)
			b.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""
		end
	end
	status.Text = table.concat(timers, "   ")
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok then
		warn("[VulpineClient] frame: " .. tostring(err))
	end
end)

player.CharacterAdded:Connect(function()
	rootUntil, tumbleUntil = 0, 0
	thrust = nil
	-- died / respawned in form: hand the player's own zoom limits straight back (the new humanoid's offset is 0)
	if camState then
		local saved = camState
		camState = nil
		camToken += 1
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = saved.min, saved.max
	end
	letterbox(false, 0.2)
end)

print(string.format("[VulpineClient] ready - Q %s | E %s | R %s | F %s | X %s", CFG.Labels.Sphere, CFG.Labels.Disc, CFG.Labels.Power, CFG.Labels.Morph, CFG.Labels.Release or "RELEASE"))
