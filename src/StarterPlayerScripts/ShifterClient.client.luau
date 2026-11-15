--!nocheck
-- ShifterClient: input, ability bar and local body for the Shifter kit (grapple reeling, the spinning strike, knockback,
-- super-armour, the giant camera framed on the whole titan, the Founder's orbit camera, X to release a form), plus
-- playback of every cast the server broadcasts. It only renders and moves its own body; hits, damage and ragdolls are
-- decided on the server. Skill-name free: everything skinnable (colours, labels, sounds, timings) comes from
-- ReplicatedStorage.ShifterKit.Config.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("ShifterKit")
local CFG = require(Kit:WaitForChild("Config"))
local Builders = require(Kit:WaitForChild("Builders"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local GojoClient = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local FX = require(GojoClient:WaitForChild("GojoFX")) -- bolts, glows, rings, streaks, rubble, impact frames
local Animator = require(GojoClient:WaitForChild("ProceduralAnimator"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib")) -- envelopes, cracks, shake
local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback")) -- damage numbers + hit-confirm
-- (2026-11-11, owner: "have the option to have keybinds") HudShared.Keybinds holds the player's own key for each move.
-- Moves are still named by their DEFAULT key (CFG.Keys): a press is translated back to the default key it stands for
-- before it is looked up, and every key chip draws the bound key - so with the default binds nothing here changes.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))
-- a label that names a key: drawn now and redrawn whenever the player rebinds
local function keyText(label, make)
	label.Text = make()
	Keybinds.Changed:Connect(function()
		label.Text = make()
	end)
	return label
end
-- a Config hint that opens with its move's own default key ("E again: slam") names the bound key instead
local function keyHint(key, text)
	text = text or ""
	local name = key and key.Name
	if name and string.sub(text, 1, #name + 1) == name .. " " then
		return Keybinds.label(key) .. string.sub(text, #name + 1)
	end
	return text
end

local PAL, SND = CFG.Palette, CFG.Sounds
-- PERKS (2026-11-07, kits-D): the CRYSTAL TITAN skin. A cast whose CASTER's player has Skin == "Alt" (read when its
-- broadcast arrives, on every client) draws with ALT_PAL = Config.AltPalette over Palette (plus the crystal material
-- for the skeleton and its spears). The handlers shadow PAL with palOf(d.userId), so the normal look is untouched.
local ALT_PAL = table.clone(PAL)
for k, v in pairs(CFG.AltPalette or {}) do
	ALT_PAL[k] = v
end
ALT_PAL.BoneMaterial = CFG.AltMaterial
local function palOf(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
	return (p and p:GetAttribute("Skin") == "Alt") and ALT_PAL or PAL
end
local T, W, C, F = CFG.Tether, CFG.Warrior, CFG.Colossus, CFG.Founder
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local R = math.rad
local VERT = CFrame.Angles(0, 0, R(90)) -- a Cylinder part's axis is X; this stands it upright

local Folder = Instance.new("Folder")
Folder.Name = "Shifter"
Folder.Parent = workspace

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

local function isMe(userId)
	return userId == player.UserId
end

local function equipped()
	return player:GetAttribute("Kit") == CFG.KitId
end

local function flat(v, fallback)
	local f = typeof(v) == "Vector3" and v * FLAT or Vector3.zero
	return f.Magnitude > 1e-3 and f.Unit or fallback
end

local function rootOf(model)
	return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end

local function camDist(pos)
	return (workspace.CurrentCamera.CFrame.Position - pos).Magnitude
end

local FX_FOLDERS = { "KitFX", "FX", "LocalFX", "KitDebris", "DamageNumbers", "VulpineFX", "Tempest", "Carver", "TitanSwarm" }

-- parts a ground ray should look through: effects, flying debris, every body
local ignoreCache, ignoreAt = nil, 0
local function ignoreList()
	if ignoreCache and os.clock() - ignoreAt < 0.4 then
		return ignoreCache
	end
	local ignore = { Folder }
	for _, n in ipairs(FX_FOLDERS) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	ignoreCache, ignoreAt = ignore, os.clock()
	return ignore
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(pos, depth)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -(depth or 80), 0), groundParams)
	return hit and hit.Position or pos - UP * 3, hit ~= nil
end

-- the world point under the cursor (the screen centre on touch-only devices); lands on bodies too
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local function cursorRay()
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		m = cam.ViewportSize / 2
	end
	return cam:ViewportPointToRay(m.X, m.Y)
end
local function cursorHit(maxDist)
	local ray = cursorRay()
	local skip = { Folder }
	if player.Character then
		table.insert(skip, player.Character)
	end
	for _, n in ipairs(FX_FOLDERS) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	cursorParams.FilterDescendantsInstances = skip
	return workspace:Raycast(ray.Origin, ray.Direction * (maxDist or 1500), cursorParams), ray
end
local function cursorTarget()
	local hit, ray = cursorHit()
	return hit and hit.Position or ray.Origin + ray.Direction * 1500
end

local function sound(id, pos, vol, speed)
	if not id or not pos then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 40
	s.RollOffMaxDistance = 900
	s.Parent = Fx2.anchor(Folder, pos, 10)
	s:Play()
	return s
end

local function neon(name, shape, color, parent)
	return Fx2.part(name, shape, Enum.Material.Neon, color, parent or Folder)
end

local function seg(part, a, b, thick)
	part.Size = Vector3.new(thick, thick, math.max((b - a).Magnitude, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

---------------------------------------------------------------------------------------------------
-- poses (degrees; shoulder flexion +X, lean forward Waist -X, right arm out RightShoulder Z+, hip flexion +X)
local POSE = {
	-- biting down on the hand to trigger a transformation
	Bite = { RightShoulder = { 115, 0, -35 }, RightElbow = { 125, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftElbow = { 30, 0, 0 }, Waist = { -10, 15, 0 }, Neck = { 10, -10, 0 } },
	Gather = { RightShoulder = { 30, 0, 75 }, RightElbow = { 35, 0, 0 }, LeftShoulder = { 30, 0, -75 }, LeftElbow = { 35, 0, 0 }, Waist = { 14, 0, 0 }, Neck = { -18, 0, 0 } },
	Roar = { RightShoulder = { 25, 0, 55 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 25, 0, -55 }, LeftElbow = { 90, 0, 0 }, Waist = { 16, 0, 0 }, Neck = { -22, 0, 0 }, LeftHip = { 10, 0, -10 }, RightHip = { 10, 0, 10 } },
	-- Waist yaw + turns the right shoulder forward: the windup cocks it back, the punch drives it through and down. FK on
	-- a 4x rig puts the fist ~3.1 x scale ahead of the root, 0.33 x scale right, 0.9 x scale off the ground, which is
	-- where the server lands the hit (Config.Warrior.PunchReach)
	PunchBack = { RightShoulder = { 150, 0, 25 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 45, 0, -20 }, LeftElbow = { 70, 0, 0 }, Waist = { 8, -30, 0 }, Neck = { -5, 20, 0 } },
	Punch = { Root = { -35, 0, 0, pos = Vector3.new(0, -0.3, 0) }, Waist = { -45, 30, 0 }, Neck = { 40, -20, 0 }, RightShoulder = { 130, 0, -10 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 60, 0, 0 }, RightHip = { 60, 0, 0 }, RightKnee = { -55, 0, 0 }, LeftHip = { 25, 0, 0 }, LeftKnee = { -30, 0, 0 } },
	HammerUp = { RightShoulder = { 170, 0, 15 }, RightElbow = { 45, 0, 0 }, LeftShoulder = { 170, 0, -15 }, LeftElbow = { 45, 0, 0 }, Waist = { 14, 0, 0 }, Neck = { -10, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -50, 0, 0 } },
	HammerDown = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.35, 0) }, RightShoulder = { 70, 0, -10 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 70, 0, 10 }, LeftElbow = { 5, 0, 0 }, Waist = { -38, 0, 0 }, Neck = { 18, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { 50, 0, 0 }, RightKnee = { -60, 0, 0 } },
	StompUp = { RightHip = { 75, 0, 5 }, RightKnee = { -80, 0, 0 }, Waist = { 8, 0, 0 }, RightShoulder = { 20, 0, 30 }, LeftShoulder = { 20, 0, -30 } },
	-- a lunge: the foot lands ~1.3 x scale ahead with the back knee bent (the server's crater sits under its toes)
	StompDown = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, RightHip = { 40, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -50, 0, 0 }, Waist = { -14, 0, 0 }, RightShoulder = { 10, 0, 35 }, LeftShoulder = { 10, 0, -35 } },
	Kneel = { Root = { 0, 0, 0, pos = Vector3.new(0, -1.3, 0) }, RightHip = { 95, 0, 0 }, RightKnee = { -95, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -110, 0, 0 }, Waist = { -30, 0, 0 }, RightShoulder = { 55, 0, 10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 55, 0, -10 }, LeftElbow = { 10, 0, 0 }, Neck = { 15, 0, 0 } },
	-- reeling in on the cables: blades trailing, knees up
	Reel = { RightShoulder = { -35, 0, 30 }, RightElbow = { 25, 0, 0 }, LeftShoulder = { -35, 0, -30 }, LeftElbow = { 25, 0, 0 }, Waist = { -22, 0, 0 }, Neck = { 12, 0, 0 }, RightHip = { 35, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { 15, 0, 0 }, LeftKnee = { -30, 0, 0 } },
	SpinOut = { RightShoulder = { 10, 0, 95 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 10, 0, -95 }, LeftElbow = { 5, 0, 0 }, Waist = { -10, 0, 0 }, RightHip = { 25, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftHip = { 25, 0, 0 }, LeftKnee = { -40, 0, 0 } },
	Swipe = { RightShoulder = { 110, 0, -35 }, RightElbow = { 15, 0, 0 }, Waist = { -18, -25, 0 }, Neck = { 10, 15, 0 } },
}
local function mirror(p)
	local out = {}
	for k, v in pairs(p) do
		local name = k
		if k:sub(1, 4) == "Left" then
			name = "Right" .. k:sub(5)
		elseif k:sub(1, 5) == "Right" then
			name = "Left" .. k:sub(6)
		end
		out[name] = { v[1], -v[2], -v[3], pos = v.pos }
	end
	return out
end
-- plays one pose (joint -> {x, y, z, pos?}) for `length` s with a short blend in and out. The animator takes a LIST of
-- keyframes: handing it the bare pose map (as this used to) played nothing at all. A Root `pos` is in body studs and is
-- scaled with the rig, so a 14x giant crouches 14x as far
local function pose(char, keys, length)
	if char and char.Parent then
		pcall(function()
			local sc = char:GetScale()
			local p = keys
			if math.abs(sc - 1) > 0.01 then
				p = {}
				for name, v in pairs(keys) do
					p[name] = v.pos and { v[1], v[2], v[3], pos = v.pos * sc } or v
				end
			end
			Animator.stopAll(char, 0.08)
			Animator.play(char, { length = length, fadeIn = 0.08, fadeOut = 0.25, keys = { { t = 0, pose = p } } })
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- local body: facing the aim during a cast, being knocked back, standing firm while a giant
local faceUntil, faceDirV = 0, nil
local tumbleUntil = 0
local armored = false

local function faceDir(hrp, dir)
	local f = flat(dir, nil)
	if hrp and f then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + f)
	end
end

-- this client owns its body: knockback from any Shifter caster is applied here (a giant with super-armour shrugs it)
Knockback.OnClientEvent:Connect(function(vel, duration, keep)
	local char, hum = myChar()
	if not char or typeof(vel) ~= "Vector3" or char:GetAttribute("SuperArmor") then
		return
	end
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
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "ShifterHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function uiCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = p
end
local function uiStroke(p, color, th, tr, contextual)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = color, th, tr or 0
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

-- cinematic letterbox bars for the transformations
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
	local h = on and 0.1 or 0
	Fx2.tween(barTop, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
	Fx2.tween(barBottom, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
end

-- move-name callout: a kanji line over the move name in a gradient, punched in then faded out
-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title: called only for Founder / Rumble now
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
local function showTitle(key)
	local co = CFG.Callouts[key]
	if not co then
		return
	end
	local token = {}
	titleToken = token
	title.Text = (CFG.Titles and CFG.Titles[key]) or CFG.Labels[key] or key
	kanji.Text = co.kanji or ""
	kanji.TextColor3 = co.c0:Lerp(co.c1, 0.45)
	titleGrad.Color = ColorSequence.new(co.c0, co.c1)
	local dark = co.c1:Lerp(Color3.new(0, 0, 0), 0.82)
	titleStroke.Color, kanjiStroke.Color = dark, dark
	title.TextTransparency, kanji.TextTransparency = 0, 0
	titleStroke.Transparency, kanjiStroke.Transparency = 0, 0
	titleScale.Scale = 1.7
	titleHolder.Rotation = -5
	Fx2.tween(titleScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
	Fx2.tween(titleHolder, 0.16, { Rotation = 0 })
	task.delay(1.7, function()
		if titleToken ~= token then
			return
		end
		for _, o in ipairs({ title, kanji }) do
			Fx2.tween(o, 0.45, { TextTransparency = 1 })
		end
		for _, o in ipairs({ titleStroke, kanjiStroke }) do
			Fx2.tween(o, 0.45, { Transparency = 1 })
		end
	end)
end

-- ability bar, laid out like the other kits': two skills, the shared M1 slot, the big button, and the last form on
-- its own wide button above the row
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
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -172), Size = UDim2.new(1, 0, 0, 16),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold,
})
uiStroke(status, Color3.new(0, 0, 0), 1.5, 0.3, true)

local COOLDOWN = {
	Tether = T.SpinCooldown, Warrior = W.Cooldown, Colossus = C.Cooldown, Founder = F.Cooldown,
	Slam = W.SlamCooldown, Burst = C.BurstCooldown, Rumble = F.RumbleCooldown,
}
local cooldownEnd = { Tether = 0, Warrior = 0, Colossus = 0, Founder = 0, Slam = 0, Burst = 0, Rumble = 0 }
-- PERKS (2026-11-07, kits-D): the local player's cooldown factor for a skill, the same as the server's cdFor
-- (CooldownMul, x UltChargeMul for the Founding Titan and the moves inside it), so the bar counts what is enforced
local ULT_SKILLS = { Founder = true, Rumble = true, Spear = true }
local FORM_M1 = { Punch = true, Stomp = true } -- (2026-11-08) the giant forms' M1 swings keep their cooldowns
local function cdMul(skill)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if ULT_SKILLS[skill] then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, as the server does
	local bal = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
	return math.clamp(m, 0.05, 4) * ((ULT_SKILLS[skill] or FORM_M1[skill]) and 1 or bal.NON_ULT_COOLDOWN_MUL)
end
local SIGNATURE = { Warrior = "Slam", Colossus = "Burst", Founder = "Rumble" }
local M1_LABEL = { Warrior = "TITAN PUNCH", Colossus = "STOMP", Founder = "BONE SPEAR" }
local buttons = {}
local punchLabel

local function myForm()
	local char = player.Character
	return char and char:GetAttribute("TitanForm")
end

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	Request:FireServer(skill, { target = cursorTarget() })
end

local tetherPressed -- defined with the grapple below

local function skillButton(id, size, x)
	local co = CFG.Callouts[id]
	local big = size > 80
	local b = Instance.new("TextButton")
	b.Name = id
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.new(1, x, 1, -16)
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
	uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 12), Position = UDim2.new(0, 4, 1, big and -21 or -18), Text = CFG.Labels[id] or id, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.85)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyText(uiText(chip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, ZIndex = 2 }), function()
		return Keybinds.label(CFG.Keys[id])
	end)
	keyText(uiText(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.35) }), function()
		return keyHint(CFG.Keys[id], co.hint)
	end)
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
	buttons[id] = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, button = b }
	b.Activated:Connect(function()
		if id == "Tether" then
			tetherPressed()
		else
			request(id)
		end
	end)
end
skillButton("Tether", 72, -280)
skillButton("Warrior", 72, -198)
skillButton("Colossus", 104, 0)

-- the M1 slot: the shared punch normally, the giant's own attack while a form stands
do
	local b = Instance.new("TextButton")
	b.Name = "Punch"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(72, 72)
	b.Position = UDim2.new(1, -116, 1, -16)
	b.BackgroundColor3 = Color3.fromRGB(30, 40, 34)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	uiStroke(b, Color3.fromRGB(170, 240, 200), 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = Color3.new(1, 1, 1)
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(235, 255, 240), Color3.fromRGB(90, 200, 140))
	g.Rotation = 45
	g.Parent = orb
	punchLabel = uiText(b, { Size = UDim2.new(1, -8, 0, 12), Position = UDim2.new(0, 4, 1, -19), Text = "SLASH", ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(10, 22, 16)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	uiText(chip, { Size = UDim2.fromScale(1, 1), Text = "M1", Font = Enum.Font.GothamBold, ZIndex = 2 })
	b.Activated:Connect(function()
		if myForm() then
			request("TitanM1")
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

-- the last form on its own wide button above the row (the Domain Expansion slot)
do
	local co = CFG.Callouts.Founder
	local b = Instance.new("TextButton")
	b.Name = "Founder"
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
	g.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.9)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyText(uiText(chip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, ZIndex = 2 }), function()
		return Keybinds.label(CFG.Keys.Founder)
	end)
	uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Founder, ZIndex = 2 })
	keyText(uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 }), function()
		return keyHint(CFG.Keys.Founder, "G again: the rumbling")
	end)
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
	buttons.Founder = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true, button = b }
	b.Activated:Connect(function()
		request("Founder")
	end)
end

-- X RELEASE: up while a form stands; the key, a click or a tap leaves the form (the server refuses it mid-entrance)
local releaseBtn, releaseText, releaseStroke
do
	local b = Instance.new("TextButton")
	b.Name = "Release"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -196, 1, -132)
	b.Size = UDim2.fromOffset(150, 36)
	b.BackgroundColor3 = Color3.fromRGB(48, 14, 14)
	b.Visible = false
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	releaseStroke = uiStroke(b, Color3.fromRGB(255, 150, 130), 2, 0.1)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = Color3.fromRGB(255, 238, 230)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyText(uiText(chip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(80, 18, 18), ZIndex = 2 }), function()
		return Keybinds.label(CFG.Keys.Release or Enum.KeyCode.X)
	end)
	releaseText = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Release or "RELEASE", ZIndex = 2 })
	uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = "leave the form", Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(255, 195, 180), ZIndex = 2 })
	b.Activated:Connect(function()
		if myForm() then
			request("Release")
		end
	end)
	releaseBtn = b
end

---------------------------------------------------------------------------------------------------
-- the gear on any body: cable ports, gas port, blade trails
local function gearAttachment(char, name, side)
	local gear = char:FindFirstChild("ShifterGear")
	local a = gear and gear:FindFirstChild(name, true)
	if a and a:IsA("Attachment") then
		return a
	end
	local lt = char:FindFirstChild("LowerTorso") or char:FindFirstChild("HumanoidRootPart")
	if not lt then
		return nil
	end
	local f = lt:FindFirstChild("Shifter" .. name)
	if not f then
		f = Instance.new("Attachment")
		f.Name = "Shifter" .. name
		f.Position = Vector3.new(side * lt.Size.X * 0.55, lt.Size.Y * 0.4, -lt.Size.Z * 0.4)
		f.Parent = lt
	end
	return f
end

local function setTrails(char, on)
	local gear = char and char:FindFirstChild("ShifterGear")
	if gear then
		for _, d in ipairs(gear:GetDescendants()) do
			if d:IsA("Trail") then
				d.Enabled = on
			end
		end
	end
end

local gasEmitters = setmetatable({}, { __mode = "k" })
local function gasPuff(char, n)
	local e = gasEmitters[char]
	if not e or not e.Parent then
		local host = char:FindFirstChild("GasPort", true) or char:FindFirstChild("LowerTorso")
		if not host then
			return
		end
		e = Fx2.emitter(host, {
			Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.Gas), LightInfluence = 0.6, LightEmission = 0.2, Rate = 0,
			Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Back, Drag = 4, Rotation = NumberRange.new(0, 360),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 2.8) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		})
		gasEmitters[char] = e
	end
	e:Emit(n)
end

-- the twin cables: hooks fly out from the hip launchers, bite, hold taut, and reel back in when released
local cables = {} -- [key] = { char, src = {att, att}, anchors, heads, beams, t0, travel, bit, retract, expire }
local function newCables(char, anchors)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local c = { char = char, anchors = anchors, t0 = os.clock(), src = {}, heads = {}, beams = {} }
	c.travel = math.max((anchors[1] - hrp.Position).Magnitude / T.HookSpeed, 0.04)
	for i, name in ipairs({ "HookL", "HookR" }) do
		local src = gearAttachment(char, name, i == 1 and -1 or 1)
		if not src then
			return nil
		end
		local head = Fx2.part("HookHead", Enum.PartType.Block, Enum.Material.Metal, PAL.SteelDark, Folder)
		head.Size = Vector3.new(0.35, 0.35, 0.9)
		head.CFrame = CFrame.new(src.WorldPosition)
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(0, 0, 0.45)
		att.Parent = head
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = src, att
		beam.Width0, beam.Width1 = 0.14, 0.12
		beam.Color = ColorSequence.new(PAL.Cable)
		beam.LightInfluence = 1
		beam.Segments = 14
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0)
		beam.Parent = head
		c.src[i], c.heads[i], c.beams[i] = src, head, beam
	end
	return c
end

local function dropCables(c)
	for _, h in ipairs(c.heads) do
		h:Destroy()
	end
end

local onLocalBite -- set by the grapple: the local hook bit, start reeling
local function updateCables(clock)
	for key, c in pairs(cables) do
		if not c.char.Parent or not c.src[1].Parent or (c.expire and clock > c.expire and not c.retract) then
			c.retract = c.retract or clock
		end
		local k = math.clamp((clock - c.t0) / c.travel, 0, 1)
		if c.retract then
			k = math.min(k, 1 - math.clamp((clock - c.retract) / 0.18, 0, 1))
		end
		for i = 1, 2 do
			local from = c.src[i].Parent and c.src[i].WorldPosition or c.anchors[i]
			local to = c.anchors[i]
			local pos = from:Lerp(to, k)
			local dir = to - from
			c.heads[i].CFrame = CFrame.lookAt(pos, pos + (dir.Magnitude > 0.01 and dir.Unit or UP))
			local slack = (c.bit and not c.retract) and 0 or (1 - k) * 2.5 + (c.retract and 1.5 or 0)
			c.beams[i].CurveSize0, c.beams[i].CurveSize1 = slack, -slack
		end
		if k >= 1 and not c.bit and not c.retract then
			c.bit = true
			for i = 1, 2 do
				FX.sparks(Folder, c.anchors[i], { color = PAL.Steel, color2 = PAL.BladeGlow, count = 10, speed = { 10, 30 }, size = 0.45 })
			end
			Fx2.dust(Folder, c.anchors[1]:Lerp(c.anchors[2], 0.5), 2, 3)
			sound(SND.Hit, c.anchors[1], 0.5, 1.5)
			if key == "me" and onLocalBite then
				onLocalBite()
			end
		end
		if c.retract and k <= 0 then
			dropCables(c)
			cables[key] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 1, local side: the grapple and the spinning strike move this client's own body
local hook = nil  -- { id, anchors, phase = "shoot" | "pull", t0, lv }
local spin = nil  -- { target, t0, lv, angle, dir }
local localCd = { Tether = 0, Spin = 0 }
local hookSerial = 0
local spins = {}  -- [key] = { char, t0, time, nextRing } (every client draws the rings round a spinning body)

local function reelForce(hrp)
	local att = hrp:FindFirstChild("RootAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "RootAttachment"
		att.Parent = hrp
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "ShifterReel"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = hrp.AssemblyMass * 8000
	lv.VectorVelocity = hrp.AssemblyLinearVelocity
	lv.Parent = hrp
	return lv
end

local function releaseHook(boost)
	if not hook then
		return
	end
	local h = hook
	hook = nil
	if h.lv then
		h.lv:Destroy()
	end
	local c = cables.me
	if c and not c.retract then
		c.retract = os.clock()
	end
	Request:FireServer("Unhook", { id = h.id })
	local char, hum, hrp = myChar()
	if char then
		pcall(Animator.stopAll, char, 0.2) -- (the reel pose is held for the longest pull; let go of it with the cable)
	end
	if boost and hrp then
		-- a hop off the end of the swing keeps the momentum flowing into the next hook
		hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.85 + UP * 38
		gasPuff(char, 10)
	end
end

onLocalBite = function()
	local char, hum, hrp = myChar()
	if not hook or not char then
		return
	end
	hook.phase = "pull"
	hook.t0 = os.clock()
	hook.lv = reelForce(hrp)
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	pose(char, POSE.Reel, T.MaxPull + 0.3)
	FX.speedLines(0.35, { alpha = 0.35, count = 36 })
	sound(SND.Whoosh, hrp.Position, 0.9, 1.2)
	gasPuff(char, 14)
end

local function startHook(point)
	local char, hum, hrp = myChar()
	releaseHook(false)
	local old = cables.me
	if old then
		dropCables(old)
		cables.me = nil
	end
	hookSerial += 1
	local across = flat(point - hrp.Position, flat(hrp.CFrame.LookVector, Vector3.zAxis)):Cross(UP)
	local anchors = { point - across * T.Spread, point + across * T.Spread }
	local c = newCables(char, anchors)
	if not c then
		return
	end
	cables.me = c
	hook = { id = hookSerial, anchors = anchors, phase = "shoot", t0 = os.clock() }
	localCd.Tether = os.clock() + T.Cooldown * cdMul("Tether")
	Request:FireServer("Hook", { id = hookSerial, target = point })
	faceUntil, faceDirV = os.clock() + 0.15, point - hrp.Position
	gasPuff(char, 8)
	sound(SND.Whoosh, hrp.Position, 0.7, 1.6)
	sound(SND.Zap, hrp.Position, 0.25, 2)
end

-- the enemy the cursor is nearest to, within reach of the spinning strike
local function spinTarget(hrp)
	local ray = cursorRay()
	local best, bestScore
	local function consider(model)
		local r = rootOf(model)
		local hum = model:FindFirstChildOfClass("Humanoid")
		if r and hum and hum.Health > 0 then
			local d = (r.Position - hrp.Position).Magnitude
			if d <= T.SpinRange and d > 1.5 then
				local rel = r.Position - ray.Origin
				local along = rel:Dot(ray.Direction)
				local perp = (rel - ray.Direction * along).Magnitude
				local score = perp + d * 0.25
				if along > 0 and (not bestScore or score < bestScore) then
					best, bestScore = model, score
				end
			end
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		consider(m)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player and pl.Character then
			consider(pl.Character)
		end
	end
	return best
end

local function endSpin(hit)
	local s = spin
	if not s then
		return
	end
	spin = nil
	if s.lv then
		s.lv:Destroy()
	end
	local char, hum, hrp = myChar()
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		faceDir(hrp, s.dir or hrp.CFrame.LookVector)
		if hit then
			-- bounce off the cut, up and away
			hrp.AssemblyLinearVelocity = -(s.dir or Vector3.zero) * 28 + UP * 48
		end
	end
	task.delay(0.25, function()
		setTrails(char, false)
	end)
	spins.me = nil
end

local function startSpin(target)
	local char, hum, hrp = myChar()
	releaseHook(false)
	localCd.Spin = os.clock() + T.SpinCooldown * cdMul("Spin")
	cooldownEnd.Tether = now() + T.SpinCooldown * cdMul("Spin")
	spin = { target = target, t0 = os.clock(), lv = reelForce(hrp), angle = 0 }
	hum.PlatformStand = true
	setTrails(char, true)
	pose(char, POSE.SpinOut, T.SpinTime + 0.25)
	Request:FireServer("Spin", { target = target })
	spins.me = { char = char, t0 = os.clock(), time = T.SpinTime, nextRing = 0 }
	-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was showTitle("Spin"))
	gasPuff(char, 16)
	sound(SND.Whoosh, hrp.Position, 1.2, 1.4)
	FX.speedLines(T.SpinTime + 0.1, { alpha = 0.55, count = 50, color = PAL.BladeGlow })
end

tetherPressed = function()
	local char, hum, hrp = myChar()
	if not char or not equipped() or char:GetAttribute("Morphed") or spin then
		return
	end
	local clock = os.clock()
	-- in the air (or mid-reel) with an enemy close: the spinning strike instead
	local airborne = hook ~= nil or hum.FloorMaterial == Enum.Material.Air
	if airborne and clock >= localCd.Spin then
		local target = spinTarget(hrp)
		if target then
			startSpin(target)
			return
		end
	end
	if clock < localCd.Tether then
		return
	end
	local hit = cursorHit(T.Range + 60)
	if hit and (hit.Position - hrp.Position).Magnitude <= T.Range then
		startHook(hit.Position)
	else
		-- nothing in reach: the hooks fire and fall short
		sound(SND.Whoosh, hrp.Position, 0.4, 2)
		gasPuff(char, 4)
	end
end

local function updateGrapple(clock, dt)
	local char, hum, hrp = myChar()
	if hook then
		if not char or char:GetAttribute("Morphed") then
			releaseHook(false)
		elseif hook.phase == "shoot" then
			if clock - hook.t0 > 1.2 then
				releaseHook(false)
			end
		elseif hook.phase == "pull" then
			local mid = (hook.anchors[1] + hook.anchors[2]) / 2
			local off = mid - hrp.Position
			if off.Magnitude <= T.ReleaseDist or clock - hook.t0 > T.MaxPull then
				releaseHook(true)
			else
				local dir = off.Unit
				hook.lv.VectorVelocity = dir * T.PullSpeed + UP * T.UpBias * (1 - math.abs(dir.Y))
				faceUntil, faceDirV = clock + 0.1, dir
				if clock >= (hook.nextGas or 0) then
					hook.nextGas = clock + 0.07
					gasPuff(char, 3)
				end
			end
		end
	end
	if spin then
		local r = spin.target.Parent and rootOf(spin.target)
		local el = clock - spin.t0
		if not char or not r or el > T.SpinTime then
			endSpin(false)
		else
			local off = r.Position - hrp.Position
			local dir = off.Magnitude > 0.1 and off.Unit or hrp.CFrame.LookVector
			spin.dir = dir
			if off.Magnitude <= T.SpinReach then
				endSpin(true)
			else
				spin.lv.VectorVelocity = dir * T.SpinSpeed
				spin.angle += dt * 36
				-- a drill spin round the line of the dash
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir) * CFrame.Angles(0, 0, spin.angle)
				if clock >= (spin.nextGas or 0) then
					spin.nextGas = clock + 0.05
					gasPuff(char, 3)
				end
			end
		end
	end
	-- rings of light round every spinning body
	for key, s in pairs(spins) do
		local r = s.char.Parent and s.char:FindFirstChild("HumanoidRootPart")
		if not r or clock - s.t0 > s.time + 0.3 then
			if key ~= "me" then
				setTrails(s.char, false)
			end
			spins[key] = nil
		elseif clock >= s.nextRing then
			s.nextRing = clock + 0.045
			local v = r.AssemblyLinearVelocity
			local dir = v.Magnitude > 5 and v.Unit or r.CFrame.LookVector
			FX.ring(Folder, r.Position, dir, 3, 10, PAL.BladeGlow, 0.25, { alpha = 0.25 })
			FX.streaks(Folder, r.Position, { dir = -dir, spread = 30, color = Color3.new(1, 1, 1), color2 = PAL.BladeGlow, count = 4, speed = { 40, 80 }, size = 0.5, life = 0.2 })
		end
	end
end

---------------------------------------------------------------------------------------------------
-- giant camera, the Founder's orbit camera, world tint
--
-- While this client's body is a giant (Warrior / Colossus) the normal orbit camera stays in charge (the player turns
-- and zooms it as usual), framed on the whole titan: Humanoid.CameraOffset lifts the focus to Camera.Focus of the
-- giant's height and the zoom sits at Camera.Zoom heights. Both follow the body's LIVE scale every frame, so the
-- camera grows with the body and shrinks back with it on release. The player's own zoom limits and distance are saved
-- first and given back after.
local giantCam = nil -- { char, kind, s0, S, H0, foot0, half0, cfg, free, u }
local savedCam = nil -- { min, max, dist }: the player's own camera before a form took it
local zoomEase = nil -- { from, to, t0, dur, min, max }: a forced zoom glide back to the saved distance

local function camZoom()
	local cam = workspace.CurrentCamera
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude
end

-- the player's zoom limits, written in the order that never lets min pass max
local function setZoomLimits(lo, hi)
	lo = math.max(lo, 0.5)
	hi = math.max(hi, lo)
	if math.abs(player.CameraMinZoomDistance - lo) < 0.01 and math.abs(player.CameraMaxZoomDistance - hi) < 0.01 then
		return
	end
	if lo > player.CameraMaxZoomDistance then
		player.CameraMaxZoomDistance = hi
		player.CameraMinZoomDistance = lo
	else
		player.CameraMinZoomDistance = lo
		player.CameraMaxZoomDistance = hi
	end
end

local function saveCamera()
	if savedCam then
		return
	end
	if zoomEase then
		savedCam = { min = zoomEase.min, max = zoomEase.max, dist = zoomEase.to }
		zoomEase = nil
	else
		local lo, hi = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
		savedCam = { min = lo, max = hi, dist = math.clamp(camZoom(), lo, hi) }
	end
end

-- back to the player's own camera: the distance glides home (forced through min = max), then the limits return
-- while giant the city's towers would yank the camera in front of the body (Zoom occlusion): see-through instead
local savedOcclusion = nil
-- (2026-11-07) Player.DevCameraOcclusionMode is server-only (a LocalScript write only logs "Insufficient
-- permissions"), so ServerScriptService.GiantCameraOcclusion now switches Invisicam on the TitanForm attribute.
local function setGiantOcclusion(_on)
	local _ = savedOcclusion
end

local function restoreCamera(glide)
	setGiantOcclusion(false)
	local s = savedCam
	savedCam = nil
	if s then
		zoomEase = { from = glide > 0 and camZoom() or s.dist, to = s.dist, t0 = os.clock(), dur = math.max(glide, 0.25), min = s.min, max = s.max }
	end
end

-- where the default camera focuses over the root part (PlayerModule BaseCamera: R15 head offset + the root's extra size)
local function focusLift(hum, rootHalf)
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.AutomaticScalingEnabled and (1.5 + rootHalf - 1) or 2
	end
	return 1.5
end

-- this client's body starts growing into `kind` (target scale S): measure it while it is still its own size
local function startGiantCam(kind, S)
	local char, hum, hrp = myChar()
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	saveCamera()
	setGiantOcclusion(true)
	local s0 = char:GetScale()
	local foot0 = hum.HipHeight + hrp.Size.Y / 2 -- the root's height over the soles
	local H0 = math.max(head.Position.Y + head.Size.Y / 2 - (hrp.Position.Y - foot0), 3)
	giantCam = {
		char = char, kind = kind, s0 = s0, S = math.max(S or 1, s0 + 0.5), H0 = H0, foot0 = foot0, half0 = hrp.Size.Y / 2,
		cfg = (CFG[kind] and CFG[kind].Camera) or {}, free = false, u = 1,
	}
end

local function updateGiantCam(char, hum)
	local g = giantCam
	if not g then
		return
	end
	if g.char ~= char or not hum then
		giantCam = nil -- died or respawned as a giant
		restoreCamera(0)
		return
	end
	local r = char:GetScale() / g.s0
	local w = math.clamp((r - 1) / (g.S / g.s0 - 1), 0, 1)
	w = w * w * (3 - 2 * w)
	local cfg = g.cfg
	local H = g.H0 * r
	-- the focus sits Focus of the way up the giant (an offset from the default focus over the root)
	local want = ((cfg.Focus or 0.92) * H - g.foot0 * r) - focusLift(hum, g.half0 * r)
	-- (+ an over-the-shoulder shift). (2026-11-10) The shift is along the CAMERA's right, not the body's: CameraOffset
	-- is in the root's own space, so a body-right shift (0.17 x 76 = 13 studs on the Colossal) swung the whole view up to
	-- 26 studs sideways every time the giant turned to walk another way, and swapped shoulders walking toward the lens.
	-- The camera's yaw is the player's own, so converting a camera-right world shift into root space has no feedback.
	local sideW = (cfg.Side or 0) * H * w
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	local camRight = flat(workspace.CurrentCamera.CFrame.RightVector, nil)
	if rootPart and camRight then
		local lo = rootPart.CFrame:VectorToObjectSpace(camRight * sideW)
		hum.CameraOffset = Vector3.new(lo.X, want * w, lo.Z)
	else
		hum.CameraOffset = Vector3.new(sideW, want * w, 0)
	end
	local D = (cfg.Zoom or 1.9) * H
	local standing = char:GetAttribute("TitanForm") == g.kind
	if standing and w > 0.97 then
		if not g.free then
			g.free = true -- fully grown: the player zooms freely between the giant's own limits
			setZoomLimits((cfg.MinZoom or 1) * H, (cfg.MaxZoom or 3.5) * H)
		end
		g.u = math.clamp(camZoom() / D, 0.3, 3)
	else
		-- growing or shrinking: the zoom is carried along with the body
		g.free = false
		local base = savedCam and savedCam.dist or 12
		local z = base + (D * g.u - base) * w
		setZoomLimits(z, z)
	end
	if not standing and not char:GetAttribute("Morphed") and r < 1.01 then
		hum.CameraOffset = Vector3.zero
		giantCam = nil
		restoreCamera(0.2)
	end
end

-- The Founder's view: the caster's body waits hidden at the colossus's heart, so the camera orbits the colossus - the
-- normal orbit camera (right-drag turns it, the wheel zooms) on an invisible anchor that WASD / the thumbstick slides
-- round the territory. It opens with a short glide out to a view over the colossus's shoulder.
local orbit = nil -- { anchor, focus0, phase = "glide" | "settle" | "free", t0, from, goal, D }
local controls = nil
task.spawn(function()
	local ps = player:WaitForChild("PlayerScripts", 10)
	local pm = ps and ps:WaitForChild("PlayerModule", 10)
	if pm then
		pcall(function()
			controls = require(pm):GetControls()
		end)
	end
end)

local function moveInput()
	if controls then
		local ok, v = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	return Vector3.zero
end

local function startOrbit(center, look, obj)
	local FC = F.Camera or {}
	local cam = workspace.CurrentCamera
	saveCamera()
	local H = 120
	pcall(function()
		local _, size = obj.model:GetBoundingBox()
		H = math.clamp(size.Y, 50, 400)
	end)
	local focus = center + UP * H * (FC.Focus or 0.45)
	local anchor = Instance.new("Part")
	anchor.Name = "FounderView"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(focus)
	anchor.Parent = Folder
	local D = math.clamp(H * (FC.Zoom or 1.9), 120, 480)
	local pitch = R(FC.Pitch or 34)
	local back = -flat(look, Vector3.new(0, 0, -1))
	local goal = CFrame.lookAt(focus + (back * math.cos(pitch) + UP * math.sin(pitch)) * D, focus)
	if orbit then
		orbit.anchor:Destroy()
	end
	orbit = { anchor = anchor, focus0 = focus, phase = "glide", t0 = os.clock(), from = cam.CFrame, goal = goal, D = D }
end

local function stopOrbit()
	local o = orbit
	if not o then
		return
	end
	orbit = nil
	local cam = workspace.CurrentCamera
	local _, hum = myChar()
	cam.CameraType = Enum.CameraType.Custom
	if hum then
		cam.CameraSubject = hum
	end
	o.anchor:Destroy()
	restoreCamera(0.6)
end

local function updateOrbit(dt, clock)
	local o = orbit
	if not o then
		return
	end
	local cam = workspace.CurrentCamera
	local FC = F.Camera or {}
	if o.phase == "glide" then
		local a = math.clamp((clock - o.t0) / (FC.Glide or 1.3), 0, 1)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = o.from:Lerp(o.goal, a * a * (3 - 2 * a))
		setZoomLimits(o.D, o.D)
		if a >= 1 then
			-- hand over to the normal orbit camera, framed where the glide ended
			cam.CameraSubject = o.anchor
			cam.CameraType = Enum.CameraType.Custom
			cam.CFrame = o.goal
			o.phase, o.t0 = "settle", clock
		end
	elseif o.phase == "settle" then
		setZoomLimits(o.D, o.D)
		if clock - o.t0 > 0.4 then
			o.phase = "free"
			setZoomLimits(o.D * (FC.MinZoom or 0.45), o.D * (FC.MaxZoom or 1.8))
		end
	else
		if cam.CameraType ~= Enum.CameraType.Custom then
			cam.CameraType = Enum.CameraType.Custom
		end
		if cam.CameraSubject ~= o.anchor then
			cam.CameraSubject = o.anchor
		end
		-- WASD / the thumbstick slide the view (camera-relative), up to PanRange from where it started
		local v = moveInput()
		if v.Magnitude > 0.05 then
			local fwd = flat(cam.CFrame.LookVector, Vector3.new(0, 0, -1))
			local move = fwd:Cross(UP) * v.X - fwd * v.Z
			local speed = (FC.PanSpeed or 120) * math.clamp(camZoom() / o.D, 0.5, 1.6)
			local p = o.anchor.Position + move * speed * dt
			local off = (p - o.focus0) * FLAT
			local range = FC.PanRange or 160
			if off.Magnitude > range then
				p = Vector3.new(o.focus0.X, p.Y, o.focus0.Z) + off.Unit * range
			end
			o.anchor.CFrame = CFrame.new(p)
		end
	end
end

-- after the camera module, every frame: the giant camera, the orbit, the zoom glide home
RunService:BindToRenderStep("ShifterCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local ok, err = pcall(function()
		local clock = os.clock()
		local char, hum = myChar()
		updateGiantCam(char, hum)
		updateOrbit(dt, clock)
		local e = zoomEase
		if e then
			local a = math.clamp((clock - e.t0) / e.dur, 0, 1)
			if a >= 1 then
				zoomEase = nil
				setZoomLimits(e.min, e.max)
			else
				local z = e.from + (e.to - e.from) * (a * a * (3 - 2 * a))
				setZoomLimits(z, z)
			end
		end
	end)
	if not ok then
		warn("[ShifterClient] camera: " .. tostring(err))
	end
end)

-- the pale, drained world while a skeletal colossus stands (every client, wherever it is)
local tintFx = Instance.new("ColorCorrectionEffect")
tintFx.Name = "ShifterFounderTint"
tintFx.Enabled = false
tintFx.Parent = Lighting
local tintOwners = {}
local function founderTint(userId, on)
	tintOwners[userId] = on or nil
	local any = next(tintOwners) ~= nil
	if any then
		tintFx.Enabled = true
		Fx2.tween(tintFx, 1.6, { TintColor = palOf(userId).Tint, Saturation = -0.5, Contrast = 0.18, Brightness = 0.03 })
	else
		local tw = Fx2.tween(tintFx, 1.6, { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 })
		tw.Completed:Connect(function()
			if next(tintOwners) == nil then
				tintFx.Enabled = false
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- input
-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if equipped() and myForm() then
		request("TitanM1")
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	-- (2026-11-11 keybinds) moves match on the default key the pressed key stands for; Space (letting go of the
	-- hook) is a movement key, so it stays the raw physical key below
	local key = Keybinds.logical(input.KeyCode)
	if key == CFG.Keys.Tether then
		tetherPressed()
	elseif key == CFG.Keys.Warrior then
		request("Warrior")
	elseif key == CFG.Keys.Colossus then
		request("Colossus")
	elseif key == CFG.Keys.Founder then
		request("Founder")
	elseif key == (CFG.Keys.Release or Enum.KeyCode.X) then
		-- leave the form (the server refuses it while the entrance is still playing)
		if myForm() then
			request("Release")
		end
	elseif input.KeyCode == Enum.KeyCode.Space and hook and hook.phase == "pull" then
		releaseHook(true)
	end
	-- M1 while a giant stands is the giant's own attack (the shared punch is off while "Morphed" is set)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) and myForm() then
		request("TitanM1")
	end
end)

---------------------------------------------------------------------------------------------------
-- cast playback
local handlers = {}
local entrances = {}  -- [userId] = a transformation being called (gather phase)
local steamRings = {} -- [character] = the steam field round a 60-metre giant's feet
local heats = {}      -- [character] = { parts = {part = colour}, emitters } while a steam release charges
local founders = {}   -- [userId] = the skeletal colossus
local marches = {}    -- marching walls of giants
local stepState = setmetatable({}, { __mode = "k" })

function handlers.Cooldown(d)
	if cooldownEnd[d.skill] ~= nil and typeof(d.ends) == "number" then
		cooldownEnd[d.skill] = d.ends
	end
end

function handlers.Hits(d)
	Feedback.hits(d, Color3.fromRGB(120, 255, 170))
end

-- a column of lightning out of the sky: the main bolt, forks off it, and the column of light it leaves
local function lightning(ground, k, color, pal)
	local PAL = pal or PAL
	local sky = ground + UP * 280 * k + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
	local bottom = ground + UP * 0.5
	FX.bolt(Folder, sky, bottom, { color = color, core = PAL.BoltCore, width = 1.6 * k, segments = 18, jag = 0.1, life = 0.35, restrike = 4, light = true })
	for _ = 1, 3 + math.floor(2 * k) do
		local a = sky:Lerp(bottom, 0.15 + math.random() * 0.6)
		local dir = Vector3.new(math.random() - 0.5, -math.random() * 0.8 - 0.2, math.random() - 0.5).Unit
		FX.bolt(Folder, a, a + dir * (30 + math.random() * 50) * k, { color = color, width = 0.5 * k, segments = 8, jag = 0.25, life = 0.25, restrike = 2 })
	end
	local col = neon("BoltColumn", Enum.PartType.Cylinder, PAL.BoltCore)
	col.Size = Vector3.new((sky - bottom).Magnitude, 7 * k, 7 * k)
	col.CFrame = CFrame.new((sky + bottom) / 2) * VERT
	col.Transparency = 0.2
	Fx2.tween(col, 0.5, { Transparency = 1, Size = Vector3.new(col.Size.X, 0.5, 0.5) })
	Debris:AddItem(col, 0.6)
	FX.glow(Folder, bottom + UP * 3, 55 * k, PAL.BoltCore, 0.4)
	Fx2.flash(Folder, bottom + UP * 3, 18 * k, color, 0.45)
	FX.light(Folder, bottom + UP * 8, color, 12, 60, 0.6)
	if camDist(bottom) < 450 * k then
		FX.flash(color, 0.35, 0.25)
	end
end

-- the gather phase of a transformation, animated every frame until the burst
local function updateEntrance(uid, e, clock)
	local PAL = e.pal or PAL
	local k = math.clamp((clock - e.t0) / e.gather, 0, 1)
	local hrp = e.char and e.char.Parent and e.char:FindFirstChild("HumanoidRootPart")
	local pos = hrp and hrp.Position or e.pos
	if clock > e.t0 + e.gather + 2 then
		entrances[uid] = nil
		return
	end
	if e.kind == "Warrior" or e.kind == "Colossus" then
		local big = e.kind == "Colossus"
		if clock >= e.nextArc then
			e.nextArc = clock + (big and 0.05 or 0.07)
			FX.arcs(Folder, pos, 3 + 3 * k, { count = big and 2 or 1, colors = { PAL.Bolt, PAL.BoltCore, PAL.BoltDeep }, width = 0.12, life = 0.1 })
			FX.streaks(Folder, pos, { inward = 14 + 10 * k, count = 6, life = 0.4, size = 0.7, color = PAL.BoltCore, color2 = PAL.Bolt })
		end
		if clock >= e.nextRing then
			e.nextRing = clock + (big and 0.22 or 0.3)
			FX.ring(Folder, groundAt(pos) + UP * 0.3, UP, big and 70 or 36, 3, PAL.Bolt, 0.5, { ease = "in" })
			Fx2.shake(0.3 + (big and 1.6 or 0.8) * k, 0.3, pos, big and 500 or 200)
			if big then
				-- golden lightning crawling through the storm overhead
				local sky = pos + UP * 220
				local a = sky + Vector3.new(math.random(-120, 120), math.random(-10, 10), math.random(-120, 120))
				local b = sky + Vector3.new(math.random(-120, 120), math.random(-10, 10), math.random(-120, 120))
				FX.bolt(Folder, a, b, { color = PAL.Bolt, core = PAL.BoltCore, width = 1.2, segments = 14, jag = 0.18, life = 0.18, restrike = 2, light = true })
			end
		end
	elseif e.kind == "Founder" then
		-- the ground itself shakes: rings race out, dust bursts, the earth splits around the caster
		if clock >= e.nextRing then
			e.nextRing = clock + 0.32
			FX.ring(Folder, e.pos + UP * 0.5, UP, 6, 320, PAL.BoneShade, 1.1, { alpha = 0.2 })
			Fx2.shake(1 + 2.4 * k, 0.45, e.pos, 1400)
			sound(SND.HitHeavy, e.pos, 1.2, 0.3)
		end
		if clock >= e.nextArc then
			e.nextArc = clock + 0.12
			local a = math.random() * math.pi * 2
			local at = e.pos + Vector3.new(math.cos(a), 0, math.sin(a)) * (15 + math.random() * 140)
			local g = groundAt(at + UP * 30, 120)
			Fx2.dust(Folder, g, 8 + 6 * k, 4)
			if math.random() < 0.3 then
				Fx2.cracks(Folder, g, UP, 6 + 8 * k, PAL.FounderGlow, 5)
				FX.rubble(Folder, g, { count = 5, radius = 3, up = { 20, 50 }, out = { 6, 20 } })
			end
		end
	end
end

local function startEntrance(d, kind)
	local char = charOf(d.userId)
	local PAL = palOf(d.userId)
	entrances[d.userId] = { kind = kind, char = char, pos = d.pos, t0 = os.clock(), gather = d.gather, nextArc = 0, nextRing = 0, pal = PAL }
	if kind ~= "Founder" then
		pose(char, POSE.Bite, d.gather * 0.55)
		task.delay(d.gather * 0.55, function()
			pose(char, POSE.Gather, d.gather * 0.5 + 0.2)
		end)
		-- the bite draws blood: a spark of light at the hand
		task.delay(d.gather * 0.35, function()
			local hand = char and char:FindFirstChild("RightHand")
			if hand then
				FX.glow(Folder, hand.Position, 6, PAL.Bolt, 0.35)
				FX.sparks(Folder, hand.Position, { color = PAL.BoltCore, color2 = PAL.Bolt, count = 14, speed = { 10, 30 }, size = 0.4 })
				sound(SND.Zap, hand.Position, 0.8, 1.2)
			end
		end)
	else
		pose(char, POSE.Kneel, d.gather + 0.4)
	end
	if isMe(d.userId) then
		letterbox(true)
		local dark = kind == "Colossus" and 0.3 or 0.2
		Fx2.envelope({ bright = -dark, sat = -0.4, contrast = 0.3, fov = -10, attack = d.gather * 0.85, hold = 0.25, release = 0.7 })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 1 playback for other clients' casters
function handlers.Hook(d)
	if isMe(d.userId) then
		return
	end
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or typeof(d.target) ~= "Vector3" then
		return
	end
	for _, c in pairs(cables) do
		if c.userId == d.userId and not c.retract then
			c.retract = os.clock()
		end
	end
	local across = flat(d.target - hrp.Position, Vector3.zAxis):Cross(UP)
	local c = newCables(char, { d.target - across * d.spread, d.target + across * d.spread })
	if c then
		c.userId = d.userId
		c.expire = os.clock() + T.MaxPull + 0.8
		cables[d.userId .. ":" .. tostring(d.id)] = c
	end
	gasPuff(char, 8)
	sound(SND.Whoosh, hrp.Position, 0.7, 1.6)
end

function handlers.Unhook(d)
	if isMe(d.userId) then
		return
	end
	local c = cables[d.userId .. ":" .. tostring(d.id)]
	if c and not c.retract then
		c.retract = os.clock()
	end
end

function handlers.Spin(d)
	if isMe(d.userId) then
		return
	end
	local char = charOf(d.userId)
	if not char then
		return
	end
	spins[d.id] = { char = char, t0 = os.clock(), time = d.time, nextRing = 0 }
	setTrails(char, true)
	pose(char, POSE.SpinOut, d.time + 0.2)
	gasPuff(char, 16)
end

-- the strike lands: a cross of light through the body, sparks of steel, a shock ring
function handlers.SpinHit(d)
	local PAL = palOf(d.userId)
	local pos, dir = d.pos, flat(d.dir, Vector3.zAxis)
	for _, a in ipairs({ 45, -45 }) do
		local p = neon("SlashCross", Enum.PartType.Block, Color3.new(1, 1, 1))
		p.Size = Vector3.new(0.35, 0.35, 15)
		p.CFrame = CFrame.lookAt(pos, pos + dir:Cross(UP)) * CFrame.Angles(0, 0, R(a)) * CFrame.Angles(R(a > 0 and 60 or -60), 0, 0)
		local glow = neon("SlashGlow", Enum.PartType.Block, PAL.BladeGlow)
		glow.Size = Vector3.new(1, 1, 16)
		glow.CFrame = p.CFrame
		glow.Transparency = 0.45
		Fx2.tween(p, 0.45, { Size = Vector3.new(0.05, 0.05, 22), Transparency = 1 })
		Fx2.tween(glow, 0.45, { Size = Vector3.new(0.1, 0.1, 24), Transparency = 1 })
		Debris:AddItem(p, 0.5)
		Debris:AddItem(glow, 0.5)
	end
	FX.sparks(Folder, pos, { color = Color3.new(1, 1, 1), color2 = PAL.BladeGlow, count = 30, speed = { 30, 80 }, size = 0.6 })
	FX.streaks(Folder, pos, { dir = dir, spread = 30, color = Color3.new(1, 1, 1), color2 = PAL.BladeGlow, count = 22, speed = { 80, 150 }, size = 0.8 })
	FX.ring(Folder, pos, dir, 2, 18, PAL.BladeGlow, 0.35)
	FX.glow(Folder, pos, 12, Color3.new(1, 1, 1), 0.25)
	sound(SND.HitHeavy, pos, 1.4, 1.2)
	sound(SND.Hit, pos, 1, 0.8)
	if isMe(d.userId) then
		endSpin(true)
		FX.impact({ tint = PAL.BladeGlow, lineColor = Color3.new(1, 1, 1), flashAlpha = 0.25 })
		Fx2.shake(1.4, 0.3)
	else
		Fx2.shake(0.6, 0.25, pos, 120)
	end
end

function handlers.SpinMiss(d)
	if isMe(d.userId) and spin then
		endSpin(false)
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 2: the 15-metre form
function handlers.WarriorStart(d)
	startEntrance(d, "Warrior")
	local e = entrances[d.userId]
	e.storm = Builders.storm(Folder, d.pos + UP * 110, 60, Color3.fromRGB(44, 48, 46), d.gather + 1.5)
	sound(SND.Crackle, d.pos, 1.3)
	sound(SND.Rise, d.pos, 1, 0.8)
end

function handlers.WarriorBurst(d)
	local PAL = palOf(d.userId)
	entrances[d.userId] = nil
	local pos, g = d.pos, d.ground or d.pos
	lightning(g, 1, PAL.Bolt, PAL)
	FX.shell(Folder, pos, 3, d.radius * 0.8, PAL.Fireball, 0.55)
	FX.shell(Folder, pos, 4, d.radius * 1.1, PAL.SteamWarm, 0.8, Enum.Material.ForceField)
	-- the body grows inside this, thin enough that the giant reads through it as it comes up
	Builders.steamCloud(Folder, pos + UP * 6, 30, 18, PAL.Steam, 2.6)
	FX.ring(Folder, g + UP * 0.4, UP, 6, d.radius * 2.6, PAL.SteamWarm, 0.7)
	FX.ring(Folder, g + UP * 0.4, UP, 4, d.radius * 1.6, PAL.Bolt, 0.45)
	Fx2.shockwave(Folder, g + UP, UP, 8, d.radius * 2.2, PAL.Steam, 0.6)
	FX.rubble(Folder, g, { count = 22, radius = 6, up = { 40, 80 }, out = { 30, 70 }, max = 2.6 })
	Fx2.cracks(Folder, g, UP, d.radius * 0.45, PAL.Bolt, 8)
	FX.sparks(Folder, pos, { color = PAL.BoltCore, color2 = PAL.Bolt, count = 40, speed = { 40, 110 }, size = 1.2 })
	sound(SND.Thunder, pos, 2.5)
	sound(SND.Boom, pos, 2.5, 0.8)
	Fx2.shake(3.2, 0.9, pos, 320)
	if isMe(d.userId) or camDist(pos) < 120 then
		FX.impact({ tint = PAL.Bolt, tint2 = PAL.WarriorEye, lineColor = PAL.BoltCore })
	end
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was showTitle("Warrior"))
		startGiantCam("Warrior", d.scale or W.Scale)
	end
end

function handlers.WarriorOn(d)
	local PAL = palOf(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	pose(char, POSE.Roar, 1.4)
	Builders.steamCloud(Folder, d.pos + UP * 10, 22, 6, PAL.Steam, 2)
	task.delay(0.35, function()
		local head = char:FindFirstChild("Head")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not head or not hrp then
			return
		end
		local look = hrp.CFrame.LookVector
		-- the roar: breath and steam blasting out of the open jaw, rings rolling off it
		for i = 0, 2 do
			task.delay(i * 0.12, function()
				FX.ring(Folder, head.Position + look * 3, look, 4, 60 + i * 20, PAL.Steam, 0.6, { alpha = 0.2 })
			end)
		end
		FX.streaks(Folder, head.Position, { dir = look, spread = 30, speed = { 60, 140 }, color = PAL.Steam, color2 = Color3.new(1, 1, 1), count = 30, size = 3, life = 0.5 })
		Fx2.shockwave(Folder, groundAt(hrp.Position, 120) + UP, UP, 10, W.RoarRadius * 2.2, PAL.Steam, 0.7)
		sound(SND.Rise, head.Position, 2.5, 0.5)
		sound(SND.Boom, head.Position, 2, 0.45)
		Fx2.shake(2.2, 1.0, hrp.Position, 260)
	end)
	if isMe(d.userId) then
		letterbox(false, 0.5)
		Fx2.envelope({ fov = 10, attack = 0.1, release = 0.8 })
	end
end

function handlers.WarriorPunch(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local back = d.side > 0 and POSE.PunchBack or mirror(POSE.PunchBack)
	local hit = d.side > 0 and POSE.Punch or mirror(POSE.Punch)
	pose(char, back, d.windup + 0.05)
	task.delay(d.windup, function()
		pose(char, hit, 0.4)
	end)
	if isMe(d.userId) then
		faceUntil, faceDirV = os.clock() + d.windup + 0.2, d.dir
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		sound(SND.Whoosh, hrp.Position, 1.2, 0.6)
	end
end

function handlers.WarriorPunchHit(d)
	local PAL = palOf(d.userId)
	FX.ring(Folder, d.pos + UP * 0.5, UP, 3, 26, PAL.SteamWarm, 0.45)
	Fx2.shockwave(Folder, d.pos + UP * 3, d.dir, 4, 22, PAL.Steam, 0.4)
	Fx2.dust(Folder, d.pos, 6, 10)
	FX.rubble(Folder, d.pos, { count = 10, radius = 3, up = { 25, 50 }, out = { 15, 35 } })
	Fx2.cracks(Folder, d.pos, UP, 6, PAL.WarriorEye, 4)
	FX.streaks(Folder, d.pos + UP * 4, { dir = d.dir, spread = 25, color = PAL.SteamWarm, color2 = Color3.new(1, 1, 1), count = 18, speed = { 60, 120 }, size = 1.2 })
	sound(SND.HitHeavy, d.pos, 1.6, 0.6)
	sound(SND.Boom, d.pos, 1, 1.1)
	Fx2.shake(1.3, 0.35, d.pos, 200)
	if isMe(d.userId) then
		Fx2.envelope({ fov = 4, attack = 0.03, release = 0.25 })
	end
end

function handlers.WarriorSlam(d)
	local PAL = palOf(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	pose(char, POSE.HammerUp, d.air * 0.7)
	task.delay(d.air * 0.62, function()
		pose(char, POSE.HammerDown, 0.8)
	end)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local g = groundAt(hrp.Position, 120)
		Fx2.dust(Folder, g, 9, 12)
		FX.ring(Folder, g + UP * 0.4, UP, 6, 40, PAL.SteamWarm, 0.5)
		sound(SND.Whoosh, hrp.Position, 1.5, 0.5)
	end
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was showTitle("WarriorSlam"))
		local _, hum, h = myChar()
		if h then
			h.AssemblyLinearVelocity = flat(d.dir, h.CFrame.LookVector) * 45 + UP * (workspace.Gravity * d.air * 0.5)
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		faceUntil, faceDirV = os.clock() + d.air, d.dir
		Fx2.envelope({ fov = 12, attack = d.air * 0.6, release = 0.3 })
	end
end

function handlers.WarriorSlamHit(d)
	local PAL = palOf(d.userId)
	local pos, r = d.pos, d.radius
	for i = 0, 2 do
		FX.ring(Folder, pos + UP * 0.5, UP, 6, r * (1.4 + i * 0.6), i == 1 and PAL.WarriorEye or PAL.SteamWarm, 0.5 + i * 0.15)
	end
	Fx2.shockwave(Folder, pos + UP, UP, 10, r * 2.4, PAL.Steam, 0.7)
	Fx2.shockwave(Folder, pos + UP * 2, UP, 6, r * 1.4, PAL.SteamWarm, 0.5)
	Fx2.cracks(Folder, pos, UP, r * 0.5, PAL.WarriorEye, 9)
	FX.rubble(Folder, pos, { count = 30, radius = 8, up = { 50, 100 }, out = { 30, 80 }, min = 1, max = 3.2, life = 3.5 })
	Fx2.dust(Folder, pos, 14, 16)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		Fx2.dust(Folder, groundAt(pos + Vector3.new(math.cos(a), 0, math.sin(a)) * r * 0.55 + UP * 10), 8, 4)
	end
	FX.glow(Folder, pos + UP * 3, 40, PAL.SteamWarm, 0.35)
	sound(SND.Boom, pos, 2.5, 0.6)
	sound(SND.HitHeavy, pos, 2, 0.5)
	Fx2.shake(3.5, 0.8, pos, 300)
	if isMe(d.userId) or camDist(pos) < 70 then
		FX.impact({ tint = PAL.WarriorEye, lineColor = PAL.SteamWarm })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the 60-metre form
function handlers.ColossusStart(d)
	startEntrance(d, "Colossus")
	local e = entrances[d.userId]
	e.storm = Builders.storm(Folder, d.pos + UP * 230, 150, Color3.fromRGB(42, 36, 32), d.gather + 3)
	e.rocks = FX.liftRocks(Folder, d.pos, 22, 16)
	sound(SND.Hum, d.pos, 2, 0.5)
	sound(SND.Crackle, d.pos, 1.5, 0.8)
end

function handlers.ColossusStrike(d)
	local PAL = palOf(d.userId)
	local g = d.ground or d.pos
	lightning(g, 2.2, PAL.Bolt, PAL)
	for i = 1, 2 do
		task.delay(i * 0.06, function()
			lightning(g + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)), 1.3, PAL.BoltDeep, PAL)
		end)
	end
	sound(SND.Thunder, g, 3, 0.7)
	if camDist(g) < 800 then
		FX.flash(PAL.BoltCore, 0.75, 0.35)
	end
	Fx2.shake(2.5, 0.4, g, 800)
end

function handlers.ColossusBlast(d)
	local PAL = palOf(d.userId)
	local e = entrances[d.userId]
	if e and e.rocks then
		pcall(function()
			e.rocks:drop(90)
		end)
	end
	entrances[d.userId] = nil
	local g = d.ground or d.pos
	local r = d.radius
	-- the fireball, the shock front racing across the ground, a condensation ring overhead, the mushroom cloud
	FX.shell(Folder, g + UP * 4, 6, r, PAL.FireCore, 0.9)
	FX.shell(Folder, g + UP * 4, 6, r * 1.15, PAL.Fireball, 1.4)
	FX.shell(Folder, g + UP * 4, 8, r * 1.8, PAL.SteamWarm, 1.6, Enum.Material.ForceField)
	Builders.mushroom(Folder, g, 1, PAL, 8)
	Builders.steamCloud(Folder, g + UP * 20, 70, 22, PAL.SteamWarm, 4) -- (60 puffs for 6 s hid the giant it revealed)
	FX.ring(Folder, g + UP * 0.6, UP, 10, 380, PAL.SteamWarm, 1.3)
	FX.ring(Folder, g + UP * 0.6, UP, 10, 240, PAL.Fireball, 0.9)
	Fx2.shockwave(Folder, g + UP * 2, UP, 20, 320, PAL.Steam, 1.2)
	FX.ring(Folder, g + UP * 70, UP, 20, 260, Color3.new(1, 1, 1), 1.6, { alpha = 0.3 })
	FX.rubble(Folder, g, { count = 40, radius = 14, up = { 60, 120 }, out = { 50, 110 }, min = 1.5, max = 4.5, life = 4 })
	Fx2.cracks(Folder, g, UP, 30, PAL.Ember, 10)
	FX.sparks(Folder, g + UP * 10, { color = PAL.FireCore, color2 = PAL.Ember, count = 80, speed = { 60, 160 }, size = 2, life = 1.5 })
	FX.light(Folder, g + UP * 20, PAL.Fireball, 14, 60, 1.5)
	sound(SND.Boom, g, 4, 0.45)
	sound(SND.Thunder, g, 3, 0.6)
	task.delay(0.35, function()
		sound(SND.Boom, g, 3, 0.3)
	end)
	local dist = camDist(g)
	Fx2.shake(7, 1.8, g, 900)
	if dist < 900 then
		Fx2.envelope({ tint = PAL.Fireball, bright = 0.35, contrast = 0.2, sat = 0.2, attack = 0.05, hold = 0.4, release = 2.5 })
	end
	if dist < 350 or isMe(d.userId) then
		FX.impact({ tint = PAL.Fireball, tint2 = PAL.FireCore, lineColor = PAL.FireCore, lineTime = 0.6 })
	end
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was showTitle("Colossus"))
		startGiantCam("Colossus", d.scale or C.Scale)
	end
end

-- the steam field round a 60-metre giant's feet: thin ground steam that marks the scalding zone without hiding the body
-- (it was 50 puffs a second of 24-stud smoke at 45% opacity: a fog over the whole view)
local function makeSteamRing(radius)
	local p = Builders.part(Folder, "SteamField", "block", Vector3.new(radius * 1.7, 1, radius * 1.7), PAL.Steam, Enum.Material.SmoothPlastic, 1)
	p.CastShadow = false
	Builders.emitter(p, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.Steam, PAL.SteamWarm), LightInfluence = 0.6, LightEmission = 0.05,
		Rate = 12, Lifetime = NumberRange.new(1.1, 1.8), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 3, 0), Drag = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 15) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(0.35, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
	})
	return p
end

-- one round every standing Colossus on every client, kept from the attribute (so a late joiner gets one too)
local function ensureSteamRing(char)
	if not steamRings[char] then
		steamRings[char] = makeSteamRing(C.SteamRadius)
	end
end

function handlers.ColossusOn(d)
	local PAL = palOf(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	ensureSteamRing(char)
	pose(char, POSE.Roar, 1.8)
	local head = char:FindFirstChild("Head")
	if head then
		FX.ring(Folder, head.Position, char.HumanoidRootPart.CFrame.LookVector, 20, 260, PAL.Steam, 1.2, { alpha = 0.2 })
		sound(SND.Rise, head.Position, 3, 0.35)
	end
	sound(SND.Boom, d.pos, 2.5, 0.3)
	Fx2.shake(3, 1.2, d.pos, 700)
	if isMe(d.userId) then
		letterbox(false, 0.8)
	end
end

function handlers.ColossusStomp(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local up = d.side > 0 and POSE.StompUp or mirror(POSE.StompUp)
	local down = d.side > 0 and POSE.StompDown or mirror(POSE.StompDown)
	pose(char, up, d.windup + 0.05)
	task.delay(d.windup, function()
		pose(char, down, 0.6)
	end)
	if isMe(d.userId) then
		faceUntil, faceDirV = os.clock() + d.windup + 0.2, d.dir
	end
end

function handlers.ColossusStompHit(d)
	local PAL = palOf(d.userId)
	local pos, r = d.pos, d.radius
	FX.ring(Folder, pos + UP * 0.5, UP, 8, r * 2.4, PAL.SteamWarm, 0.7)
	FX.ring(Folder, pos + UP * 0.5, UP, 6, r * 1.4, PAL.Ember, 0.5)
	Fx2.shockwave(Folder, pos + UP, UP, 10, r * 2.2, PAL.Steam, 0.7)
	Fx2.dust(Folder, pos, 16, 14)
	FX.rubble(Folder, pos, { count = 26, radius = 8, up = { 50, 100 }, out = { 30, 80 }, min = 1.2, max = 3.5, life = 3.5 })
	Fx2.cracks(Folder, pos, UP, r * 0.5, PAL.Ember, 6)
	sound(SND.Boom, pos, 2.5, 0.4)
	sound(SND.HitHeavy, pos, 2, 0.4)
	Fx2.shake(4, 0.7, pos, 500)
	if isMe(d.userId) then
		Fx2.envelope({ fov = 5, attack = 0.04, release = 0.35 })
	end
end

function handlers.ColossusBurstCharge(d)
	local PAL = palOf(d.userId)
	local char = charOf(d.userId)
	local skin = char and char:FindFirstChild("TitanSkin")
	if not skin then
		return
	end
	pose(char, POSE.Gather, d.time + 0.4)
	-- the body heats up: every muscle glows, every vent pours
	local h = { parts = {}, emitters = {} }
	for _, p in ipairs(skin:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Tooth" and p.Name ~= "Eye" then
			h.parts[p] = p.Color
			Fx2.tween(p, d.time, { Color = PAL.ColossusHeat })
		elseif p:IsA("ParticleEmitter") then
			h.emitters[p] = p.Rate
			p.Rate *= 4
		end
	end
	heats[char] = h
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		FX.streaks(Folder, hrp.Position, { inward = 60, count = 40, life = d.time, size = 4, color = PAL.SteamWarm, color2 = PAL.ColossusHeat })
		sound(SND.Hum, hrp.Position, 2.5, 0.7)
		sound(SND.Rise, hrp.Position, 2, 0.6)
	end
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was showTitle("ColossusBurst"))
		Fx2.envelope({ tint = PAL.ColossusHeat, bright = 0.1, fov = -6, attack = d.time, release = 0.4 })
	end
end

local function coolDown(char)
	local h = heats[char]
	if not h then
		return
	end
	heats[char] = nil
	for p, col in pairs(h.parts) do
		if p.Parent then
			Fx2.tween(p, 1.2, { Color = col })
		end
	end
	for e, rate in pairs(h.emitters) do
		if e.Parent then
			e.Rate = rate
		end
	end
end

function handlers.ColossusBurst(d)
	local PAL = palOf(d.userId)
	local pos, feet, r = d.pos, d.feet, d.radius
	FX.shell(Folder, pos, 10, r, PAL.Steam, 0.9, Enum.Material.ForceField)
	FX.shell(Folder, pos, 8, r * 0.6, PAL.SteamWarm, 0.5)
	-- jets of steam rolling out along the ground in every direction (a ring of low clouds round the feet) instead of
	-- one white ball round the whole body, so the giant stays in view through its own blast
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local at = feet + Vector3.new(math.cos(a), 0, math.sin(a)) * r * 0.42 + UP * 8
		Builders.steamCloud(Folder, at, 34, 3, i % 2 == 0 and PAL.SteamWarm or PAL.Steam, 2.4)
	end
	Builders.steamCloud(Folder, pos, 40, 6, PAL.Steam, 2.2)
	FX.ring(Folder, feet + UP * 0.6, UP, 10, r * 2.4, PAL.SteamWarm, 0.8)
	FX.ring(Folder, feet + UP * 4, UP, 6, r * 1.6, PAL.ColossusHeat, 0.5, { alpha = 0.2 })
	Fx2.shockwave(Folder, feet + UP * 2, UP, 10, r * 2.2, PAL.Steam, 0.8)
	FX.streaks(Folder, pos, { color = Color3.new(1, 1, 1), color2 = PAL.Steam, count = 60, speed = { 120, 260 }, size = 6, life = 0.6 })
	FX.light(Folder, pos, PAL.ColossusHeat, 10, 60, 0.8)
	sound(SND.Boom, pos, 3, 0.5)
	sound(SND.Whoosh, pos, 2.5, 0.4)
	Fx2.shake(4.5, 1.0, pos, 600)
	local char = charOf(d.userId)
	if char then
		coolDown(char)
	end
	if isMe(d.userId) then
		Fx2.envelope({ bright = 0.12, sat = -0.15, attack = 0.04, hold = 0.1, release = 0.8 })
	elseif camDist(pos) < r * 2.5 then
		Fx2.envelope({ bright = 0.3, sat = -0.3, attack = 0.04, hold = 0.15, release = 1.2 })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the skeletal colossus
local function territoryRing(center, radius, pal)
	local PAL = pal or PAL
	local m = Instance.new("Model")
	m.Name = "Territory"
	local n = 32 -- (56 segments read no rounder at this size)
	local pts = {}
	for i = 0, n do
		local a = i / n * math.pi * 2
		pts[i] = groundAt(center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius + UP * 40, 140) + UP * 0.35
	end
	for i = 1, n do
		local p = neon("RingSeg", Enum.PartType.Block, PAL.FounderGlow, m)
		seg(p, pts[i - 1], pts[i], 0.7)
		p.Transparency = 0.25
	end
	m.Parent = Folder
	return m
end

function handlers.FounderStart(d)
	startEntrance(d, "Founder")
	founderTint(d.userId, true)
	sound(SND.Hum, d.pos, 2.5, 0.35)
	sound(SND.Rise, d.pos, 2, 0.45)
end

function handlers.FounderRise(d)
	local PAL = palOf(d.userId)
	entrances[d.userId] = nil
	local old = founders[d.userId]
	if old then
		old.obj:destroy()
		old.ring:Destroy()
	end
	founderTint(d.userId, true) -- (a late joiner's sync arrives without the FounderStart before it)
	local look = flat(d.dir, Vector3.new(0, 0, -1))
	local root = CFrame.lookAt(d.pos, d.pos + look)
	local obj = Builders.founder(Folder, PAL, d.seed)
	obj:setEyes(0)
	obj:place(root - UP * 150, 0)
	founders[d.userId] = {
		obj = obj, root = root, pos = d.pos, look = look, t0 = os.clock(), rise = d.rise, radius = d.radius,
		roarT = -10, ring = territoryRing(d.pos, d.radius, PAL), expire = os.clock() + d.rise + d.duration + 3, nextDust = 0,
	}
	if d.sync then
		return
	end
	-- a pillar of pale light where it breaks the surface
	local pillar = neon("RisePillar", Enum.PartType.Cylinder, PAL.FounderGlow)
	pillar.Size = Vector3.new(700, 40, 40)
	pillar.CFrame = CFrame.new(d.pos + UP * 350) * VERT
	pillar.Transparency = isMe(d.userId) and 0.55 or 0.3 -- (the caster's camera starts inside it)
	Fx2.tween(pillar, 1.6, { Transparency = 1, Size = Vector3.new(700, 140, 140) })
	Debris:AddItem(pillar, 1.7)
	FX.ring(Folder, d.pos + UP, UP, 20, 420, PAL.FounderGlow, 1.4)
	Fx2.shockwave(Folder, d.pos + UP * 2, UP, 20, 300, PAL.Bone, 1.2)
	Fx2.shake(4, 1.5, d.pos, 1500)
	sound(SND.Boom, d.pos, 3, 0.3)
	sound(SND.Rise, d.pos, 2.5, 0.4)
	if isMe(d.userId) then
		showTitle("Founder")
		letterbox(false, 1)
		startOrbit(d.pos, look, obj)
	end
end

local function skullPos(fo)
	-- the eyes: the one landmark every version of the set piece has
	local eyes = fo.obj and fo.obj.eyes
	if eyes and #eyes > 0 then
		local sum = Vector3.zero
		for _, e in ipairs(eyes) do
			sum += e.Position
		end
		return sum / #eyes
	end
	return (fo.root * CFrame.new(0, 106, -92)).Position
end

function handlers.FounderRoar(d)
	local PAL = palOf(d.userId)
	local fo = founders[d.userId]
	local pos, r = d.pos, d.radius
	local skull = fo and skullPos(fo) or pos + UP * 100
	local look = fo and fo.look or Vector3.zAxis
	if fo then
		fo.roarT = os.clock()
	end
	for i = 0, 2 do
		task.delay(i * 0.15, function()
			FX.ring(Folder, skull + look * 10, look, 10, 260, PAL.FounderGlow, 1.1, { alpha = 0.15 })
		end)
	end
	FX.ring(Folder, pos + UP, UP, 20, r * 2.2, PAL.FounderGlow, 1.0)
	Fx2.shockwave(Folder, pos + UP * 2, UP, 20, r * 2, PAL.Bone, 1.0)
	FX.shell(Folder, skull, 10, 120, PAL.FounderGlow, 0.8, Enum.Material.ForceField)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local at = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * r * (0.5 + math.random() * 0.5)
		Fx2.dust(Folder, groundAt(at + UP * 30, 120), 12, 4)
	end
	sound(SND.Boom, pos, 3, 0.28)
	sound(SND.Rise, skull, 3, 0.35)
	sound(SND.Thunder, pos, 1.5, 0.5)
	Fx2.shake(3, 1.0, pos, 600)
	if camDist(pos) < r * 2.5 or isMe(d.userId) then
		Fx2.envelope({ fov = 14, blur = 8, sat = -0.3, attack = 0.08, hold = 0.2, release = 0.8 })
	end
end

local function endFounder(uid)
	local fo = founders[uid]
	if not fo then
		return
	end
	founders[uid] = nil
	fo.obj:collapse(3)
	for _, p in ipairs(fo.ring:GetChildren()) do
		Fx2.tween(p, 1.5, { Transparency = 1 })
	end
	Debris:AddItem(fo.ring, 1.6)
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		Fx2.dust(Folder, groundAt(fo.pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 60 + UP * 30, 120), 18, 5)
	end
	sound(SND.Boom, fo.pos, 2.5, 0.25)
	Fx2.shake(2.5, 1.5, fo.pos, 900)
	founderTint(uid, false)
end

function handlers.SwarmSpawn(d)
	local PAL = palOf(d.userId)
	FX.bolt(Folder, d.pos + UP * 140, d.pos + UP * 0.5, { color = PAL.Bolt, core = PAL.BoltCore, width = 0.8, segments = 12, jag = 0.12, life = 0.22, restrike = 2, light = true })
	Builders.steamCloud(Folder, d.pos + UP * d.scale * 2.5, d.scale * 5, 14, PAL.Steam, 2.5)
	Fx2.dust(Folder, d.pos, d.scale * 2, 6)
	sound(SND.Thunder, d.pos, 0.9, 1.2)
end

function handlers.SwarmSwipe(d)
	if typeof(d.model) == "Instance" then
		pose(d.model, POSE.Swipe, 0.55)
		local r = rootOf(d.model)
		if r then
			sound(SND.Whoosh, r.Position, 0.8, 0.7)
		end
	end
end

function handlers.SwarmEvaporate(d)
	if typeof(d.model) == "Instance" then
		for _, p in ipairs(d.model:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then
				Fx2.tween(p, 1.2, { Transparency = 1 })
			end
		end
	end
	if typeof(d.pos) == "Vector3" then
		Builders.steamCloud(Folder, d.pos, (d.scale or 3) * 5, 12, PAL.Steam, 2.5)
	end
end

function handlers.BoneSpearWarn(d)
	local PAL = palOf(d.userId)
	local disc = neon("SpearWarn", Enum.PartType.Cylinder, PAL.FounderGlow)
	disc.Size = Vector3.new(0.3, 2, 2)
	disc.CFrame = CFrame.new(d.pos + UP * 0.2) * VERT
	disc.Transparency = 0.3
	Fx2.tween(disc, d.delay, { Size = Vector3.new(0.3, d.radius * 2, d.radius * 2), Transparency = 0.55 })
	Debris:AddItem(disc, d.delay + 0.05)
	Fx2.cracks(Folder, d.pos, UP, d.radius * 0.8, PAL.FounderGlow, d.delay + 1.5)
	Fx2.dust(Folder, d.pos, 4, 4)
	sound(SND.HitHeavy, d.pos, 0.8, 0.4)
end

-- a spear of bone tears up out of the ground with smaller spikes splaying round it, then sinks back
function handlers.BoneSpear(d)
	local PAL = palOf(d.userId)
	local pos, r = d.pos, d.radius
	local m = Instance.new("Model")
	m.Name = "BoneSpear"
	local pieces = {}
	local function spike(base, dir, length, width)
		local widths = { 1, 0.7, 0.42 } -- (three tapering lengths a spike: 20 parts a spear, was 30)
		for i, wk in ipairs(widths) do
			local a = base + dir * length * (i - 1) / #widths
			local b = base + dir * length * i / #widths
			local p = Builders.part(m, "Bone", "rod", Vector3.new((b - a).Magnitude + width * 0.3, width * wk, width * wk), i % 2 == 0 and PAL.BoneShade or PAL.Bone, PAL.BoneMaterial)
			table.insert(pieces, { p = p, cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, R(90), 0) })
		end
		local tipBase = base + dir * length
		local tip = Builders.part(m, "Tip", "wedge", Vector3.new(width * 0.3, width * 0.3, length * 0.18), PAL.Bone, PAL.BoneMaterial)
		table.insert(pieces, { p = tip, cf = CFrame.lookAt(tipBase + dir * length * 0.09, tipBase + dir * length) })
	end
	spike(pos - UP * 2, UP, 34, 5)
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + math.random()
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		spike(pos + out * 3 - UP * 2, (UP * 1.4 + out).Unit, 14 + math.random() * 8, 2.4)
	end
	m.Parent = Folder
	for _, pc in ipairs(pieces) do
		pc.p.CFrame = pc.cf - UP * 36
		Fx2.tween(pc.p, 0.14, { CFrame = pc.cf }, Enum.EasingStyle.Back)
	end
	task.delay(1.3, function()
		for _, pc in ipairs(pieces) do
			Fx2.tween(pc.p, 0.6, { CFrame = pc.cf - UP * 30, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		Debris:AddItem(m, 0.7)
	end)
	FX.ring(Folder, pos + UP * 0.5, UP, 4, r * 3, PAL.FounderGlow, 0.5)
	FX.rubble(Folder, pos, { count = 16, radius = 4, up = { 40, 80 }, out = { 15, 40 } })
	Fx2.dust(Folder, pos, 8, 10)
	FX.sparks(Folder, pos + UP * 10, { color = PAL.Bone, color2 = PAL.FounderGlow, count = 20, speed = { 20, 60 }, size = 0.8 })
	sound(SND.HitHeavy, pos, 1.5, 0.6)
	sound(SND.Boom, pos, 1.2, 1.2)
	Fx2.shake(1.6, 0.35, pos, 300)
end

-- the wall marches: giants climb out of the ground in a line and stride forward, the earth jumping under them
function handlers.Rumble(d)
	local PAL = palOf(d.userId)
	local rng = Random.new(d.seed or 1)
	local across = d.dir:Cross(UP)
	local march = { t0 = os.clock(), d = d, giants = {}, across = across, nextBoom = 0, pal = PAL }
	for i = 1, d.count do
		local off = ((i - 1) / math.max(d.count - 1, 1) - 0.5) * d.width + rng:NextNumber(-3, 3)
		local h = rng:NextNumber(38, 54)
		table.insert(march.giants, { obj = Builders.marcher(Folder, PAL, rng, h), off = off, lag = rng:NextNumber(0, 8), h = h, lastStep = 0, ground = nil, nextGround = 0 })
	end
	table.insert(marches, march)
	if isMe(d.userId) then
		showTitle("Rumble")
	end
	sound(SND.Boom, d.origin, 3, 0.3)
	sound(SND.Rise, d.origin, 2, 0.35)
end

local function updateMarches(clock)
	for i = #marches, 1, -1 do
		local m = marches[i]
		local d = m.d
		local PAL = m.pal or PAL
		local travelled = (clock - m.t0) * d.speed
		local front = math.min(travelled, d.length)
		for _, g in ipairs(m.giants) do
			local along = front - g.lag - 18
			local flatPos = d.origin + d.dir * along + m.across * g.off
			if clock >= g.nextGround or not g.ground then
				g.nextGround = clock + 0.25
				g.ground = groundAt(flatPos + UP * 40, 140).Y
			end
			-- they climb up out of the earth at the start
			local sink = math.min(0, (clock - m.t0) * 30 - g.h)
			local base = Vector3.new(flatPos.X, g.ground + sink, flatPos.Z)
			local phase = along / (g.h * 0.9) * math.pi
			g.obj:pose(CFrame.lookAt(base, base + d.dir), phase)
			local step = math.floor((phase + g.obj.phaseOffset) / math.pi)
			if step ~= g.lastStep then
				g.lastStep = step
				Fx2.dust(Folder, Vector3.new(base.X, g.ground, base.Z), g.h * 0.12, 3)
			end
		end
		local center = d.origin + d.dir * front
		if clock >= m.nextBoom and travelled < d.length then
			m.nextBoom = clock + 0.42
			sound(SND.Boom, center, 2.2, 0.32)
			Fx2.shake(2.4, 0.4, center, 500)
			FX.ring(Folder, groundAt(center + UP * 40, 140) + UP, UP, 10, d.width * 1.1, PAL.BoneShade, 0.6, { alpha = 0.3 })
		end
		if travelled >= d.length + 20 then
			for _, g in ipairs(m.giants) do
				g.obj:fade(1.2)
				Builders.steamCloud(Folder, g.obj.torso.Position, g.h * 0.6, 6, PAL.Steam, 2.5)
			end
			table.remove(marches, i)
		end
	end
end

local function updateFounders(clock)
	for uid, fo in pairs(founders) do
		if clock > fo.expire then
			endFounder(uid)
		else
			local a = math.clamp((clock - fo.t0) / fo.rise, 0, 1)
			local e = 1 - (1 - a) ^ 3
			local re = clock - fo.roarT
			local jaw = re < 1.4 and 30 * math.sin(math.clamp(re / 1.4, 0, 1) * math.pi) or 0
			if a < 1 or re < 1.5 or not fo.settled then
				fo.obj:place(fo.root - UP * 150 * (1 - e), jaw)
				fo.settled = a >= 1 and re >= 1.5
			end
			if a < 1 then
				fo.obj:setEyes(math.clamp((a - 0.7) / 0.3, 0, 1))
				if clock >= fo.nextDust then
					fo.nextDust = clock + 0.1
					local ang = math.random() * math.pi * 2
					local at = fo.pos + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (20 + math.random() * 80)
					local g = groundAt(at + UP * 40, 140)
					Fx2.dust(Folder, g, 14, 4)
					if math.random() < 0.35 then
						FX.rubble(Folder, g, { count = 6, radius = 4, up = { 30, 70 }, out = { 10, 30 }, max = 3 })
					end
					Fx2.shake(1.4, 0.3, fo.pos, 900)
				end
			else
				local flare = re < 1.2 and (1 - re / 1.2) or 0
				fo.obj:setEyes(0.75 + 0.15 * math.sin(clock * 3) + flare)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- endings
function handlers.Husk(d)
	local model = d.model
	if typeof(model) ~= "Instance" then
		return
	end
	local life = d.life or 4
	local pale = Color3.fromRGB(225, 220, 212)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			Fx2.tween(p, life * 0.4, { Color = p.Color:Lerp(pale, 0.6) })
			TweenService:Create(p, TweenInfo.new(life * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.35), { Transparency = 1 }):Play()
		end
	end
end

function handlers.FormEnd(d)
	local char = charOf(d.userId)
	local size = 10 * math.max(d.scale or 1, 1) ^ 0.75
	Builders.steamCloud(Folder, d.pos, size, 14, PAL.Steam, 3)
	sound(SND.Whoosh, d.pos, 1.5, 0.5)
	if char then
		coolDown(char)
		local ring = steamRings[char]
		if ring then
			steamRings[char] = nil
			for _, e in ipairs(ring:GetChildren()) do
				if e:IsA("ParticleEmitter") then
					e.Enabled = false
				end
			end
			Debris:AddItem(ring, 2)
		end
	end
	if d.kind == "Founder" then
		endFounder(d.userId)
	end
	if isMe(d.userId) then
		stopOrbit() -- (the giant camera follows the body's scale back down by itself)
		letterbox(false)
	end
end

---------------------------------------------------------------------------------------------------
-- Broadcast dispatch
Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[ShifterClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- per-frame

-- giants shake the world where they step: every client watches the feet of every giant
local function footsteps()
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local form = char and char:GetAttribute("TitanForm")
		if form == "Colossus" then
			ensureSteamRing(char)
		end
		if form == "Warrior" or form == "Colossus" then
			local st = stepState[char]
			if not st then
				st = {}
				stepState[char] = st
			end
			local sc = char:GetScale()
			local big = form == "Colossus"
			for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
				local foot = char:FindFirstChild(n)
				if foot then
					local g, found = groundAt(foot.Position + UP * sc, sc * 5)
					local h = foot.Position.Y - g.Y
					if found and h < foot.Size.Y * 0.9 then
						if st[n] == "up" then
							-- (your own giant's steps shake your view less: you walk it the whole time)
							Fx2.shake((big and 2.6 or 0.9) * (pl == player and 0.55 or 1), 0.35, g, big and 700 or 220)
							Fx2.dust(Folder, g, sc * (big and 0.9 or 1.2), big and 8 or 4)
							FX.ring(Folder, g + UP * 0.3, UP, sc * 0.5, sc * 3, PAL.SteamWarm, 0.5, { alpha = 0.35 })
							sound(SND.HitHeavy, g, big and 1.8 or 1, big and 0.32 or 0.6)
							if big then
								Fx2.cracks(Folder, g, UP, sc * 0.6, PAL.Ember, 4)
							end
						end
						st[n] = "down"
					elseif h > foot.Size.Y * 1.6 then
						st[n] = "up"
					end
				end
			end
		end
	end
end

local function updateSteamRings()
	for char, p in pairs(steamRings) do
		local hrp = char.Parent and char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or char:GetAttribute("TitanForm") ~= "Colossus" then
			for _, e in ipairs(p:GetChildren()) do
				if e:IsA("ParticleEmitter") then
					e.Enabled = false
				end
			end
			Debris:AddItem(p, 3)
			steamRings[char] = nil
		else
			local feet = hrp.Position - UP * (hum.HipHeight + hrp.Size.Y / 2)
			p.CFrame = CFrame.new(feet + UP)
			local e = p:FindFirstChildOfClass("ParticleEmitter")
			if e then
				e.Enabled = camDist(feet) < 900 -- (nobody sees ground steam from further out)
			end
		end
	end
end

local function frame(dt)
	local clock = os.clock()
	updateCables(clock)
	updateGrapple(clock, dt)
	for uid, e in pairs(entrances) do
		updateEntrance(uid, e, clock)
	end
	footsteps()
	updateSteamRings()
	updateFounders(clock)
	updateMarches(clock)

	local char, hum, hrp = myChar()
	if hum then
		-- turned toward the aim during a cast
		if not spin then
			if clock < faceUntil and faceDirV then
				hum.AutoRotate = false
				faceDir(hrp, faceDirV)
			elseif not hum.AutoRotate then
				hum.AutoRotate = true
			end
		end
		-- super-armour: a standing giant can't be knocked down or ragdolled
		local armorNow = char:GetAttribute("SuperArmor") == true
		if armorNow then
			if hum.PlatformStand then
				hum.PlatformStand = false
			end
			tumbleUntil = 0
			local st = hum:GetState()
			if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Physics then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
		if armorNow ~= armored then
			armored = armorNow
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not armorNow)
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not armorNow)
		end
		if tumbleUntil > 0 and clock >= tumbleUntil then
			tumbleUntil = 0
			if not spin then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end

	-- HUD
	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local t = now()
	local form = myForm()
	local formUntil = char and char:GetAttribute("FormUntil")
	punchLabel.Text = form and M1_LABEL[form] or "SLASH"
	-- the release chip: up while a form stands, dimmed with a countdown until the server will take it (the rise)
	releaseBtn.Visible = form ~= nil
	if form then
		local wait = ((char and char:GetAttribute("ReleaseAt")) or 0) - t
		if wait > 0 then
			releaseText.Text = string.format("%s  %.1f", CFG.Labels.Release or "RELEASE", wait)
			releaseStroke.Transparency = 0.7
		else
			releaseText.Text = CFG.Labels.Release or "RELEASE"
			releaseStroke.Transparency = 0.15 + 0.25 * math.sin(clock * 4)
		end
	end
	local timers = {}
	for skill, b in pairs(buttons) do
		local rem, total
		if skill == "Tether" then
			rem, total = localCd.Spin - clock, T.SpinCooldown * cdMul("Spin")
			b.stroke.Transparency = form and 0.75 or 0.1
		elseif form == skill then
			-- the form stands: the button pulses and shows its signature move's cooldown
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(clock * 6)
			local sig = SIGNATURE[skill]
			rem, total = cooldownEnd[sig] - t, COOLDOWN[sig] * cdMul(sig)
			if formUntil and formUntil > t then
				table.insert(timers, string.format("%s %ds", CFG.Labels[skill], math.ceil(formUntil - t)))
			end
		else
			b.stroke.Transparency = form and 0.75 or 0.1
			rem, total = cooldownEnd[skill] - t, COOLDOWN[skill] * cdMul(skill)
		end
		local frac = math.clamp(rem / math.max(total, rem, 0.01), 0, 1)
		b.cd.Size = b.horizontal and UDim2.fromScale(frac, 1) or UDim2.fromScale(1, frac)
		b.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""
		local ready = rem <= 0
		if ready and not b.ready then
			b.scale.Scale = 1.14
			Fx2.tween(b.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		b.ready = ready
	end
	if form == "Founder" then
		table.insert(timers, "WASD: pan view  RMB: turn")
	end
	status.Text = table.concat(timers, "   ")
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok then
		warn("[ShifterClient] frame: " .. tostring(err))
	end
end)

player.CharacterAdded:Connect(function()
	faceUntil, tumbleUntil = 0, 0
	armored = false
	hook, spin = nil, nil
	local c = cables.me
	if c then
		dropCables(c)
		cables.me = nil
	end
	spins.me = nil
	stopOrbit()
	giantCam = nil
	restoreCamera(0)
	letterbox(false, 0.1)
end)

-- Studio-only test hook: lets a test script fire the grapple / strike without real mouse input
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "ShifterDebug"
	dbg.OnInvoke = function(cmd, arg)
		if cmd == "hook" and myChar() then
			startHook(arg)
			return true
		elseif cmd == "spin" and myChar() then
			startSpin(arg)
			return true
		elseif cmd == "state" then
			local n = 0
			for _ in pairs(founders) do
				n += 1
			end
			return { hook = hook and hook.phase or "none", spin = spin ~= nil, founders = n, marches = #marches, orbit = orbit and orbit.phase or "none", giantCam = giantCam and giantCam.kind or "none", cables = cables.me ~= nil }
		end
		return false
	end
	dbg.Parent = script
end

-- giants never sink (2026-11-07): the avatar's own animations (its Animate "mood" / idle tracks drop the
-- LowerTorso a little) are scaled with the body, so a -1.4 stud dip became -19.7 on the Colossal Titan and buried
-- its legs in the street. Every client clamps the Root drop of any character in a giant form, every frame, right
-- after the animators; the kit's own crouching poses (stomps) are clips written after this and still play.
local giantRoots = setmetatable({}, { __mode = "k" })
RunService.Stepped:Connect(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch and ch:GetAttribute("TitanForm") then
			local root = giantRoots[ch]
			if not root or not root.Parent then
				local lt = ch:FindFirstChild("LowerTorso")
				root = (lt and lt:FindFirstChild("Root")) or ch:FindFirstChild("Root", true)
				giantRoots[ch] = root
			end
			if root then
				local t = root.Transform
				local floor = -0.12 * ch:GetScale()
				if t.Position.Y < floor then
					root.Transform = CFrame.new(t.Position.X, floor, t.Position.Z) * t.Rotation
				end
			end
		end
	end
end)

-- giant gait (2026-11-10): the avatar's Animate times its walk by heightScale = Humanoid.HipHeight / 2, DAMPED by its
-- ScaleDampeningPercent value (0.4 on many avatars), so at 14x the stride cycled ~2.3x too fast for the ground the
-- Colossal really covered and its feet skated (the Attack Titan's ~1.9x). This client's OWN giant gets its walk / run
-- tracks re-timed every frame from the body's real ground speed and its scaled leg length - Animate's own formula,
-- undamped (identical to Animate when the avatar's value is 1, so then nothing changes). PreAnimation sets what this
-- frame draws; Heartbeat re-applies it after Animate's Humanoid.Running handler, so the replicated speed is this one.
local GAIT_TRACKS = { WalkAnim = true, RunAnim = true }
local function giantGait()
	local char = player.Character
	local form = char and char:GetAttribute("TitanForm")
	if form ~= "Warrior" and form ~= "Colossus" then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not (animator and hrp) then
		return
	end
	-- Animate: runSpeed = speed / 16 * 1.25 / heightScale; walk zone (<= 0.5) warp = runSpeed / 0.5, blend zone 1,
	-- run zone runSpeed (one warp for both tracks)
	local v = (hrp.AssemblyLinearVelocity * FLAT).Magnitude
	local runSpeed = v / 16 * 1.25 / math.max(hum.HipHeight / 2, 0.1)
	local warp = runSpeed <= 0.5 and runSpeed / 0.5 or (runSpeed < 1 and 1 or runSpeed)
	for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
		local a = tr.Animation
		if a and GAIT_TRACKS[a.Name] and math.abs(tr.Speed - warp) > 0.01 then
			tr:AdjustSpeed(warp)
		end
	end
end
RunService.PreAnimation:Connect(function()
	pcall(giantGait)
end)
RunService.Heartbeat:Connect(function()
	pcall(giantGait)
end)

-- a client that has just started asks once for the set pieces already standing (another player's colossus)
Request:FireServer("Sync")
print(string.format("[ShifterClient] ready - Q %s | E %s | R %s | G %s | X release", CFG.Labels.Tether, CFG.Labels.Warrior, CFG.Labels.Colossus, CFG.Labels.Founder))
