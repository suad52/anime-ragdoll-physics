--!nocheck
-- TempestClient: input + ability bar for the Tempest kit, local movement (wind-up, dash, being stunned or knocked
-- back), the eye mode's outlines and motion blur, the guardian's animation, and playback of every Tempest cast in
-- the server. Lightning comes from GojoShared's GojoFX; camera pulses, cracks and shake from VulpineKit's FxLib.
-- While the guardian stands: M1 slashes, G looses an arrow, X (or the RELEASE chip) lets it go.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
-- (2026-11-11 keybinds, owner: "have the option to have keybinds") every action key goes through HudShared.Keybinds:
-- logical() maps the physical key pressed back to the DEFAULT key its action is named by (CFG.Keys stays the
-- defaults), label() draws the key chips. With no rebinds it hands every key back unchanged, so default play is as
-- before. Movement / jump stay raw.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("TempestKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local StunRemote = Remotes:WaitForChild("Stun")
local GojoClient = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local FX = require(GojoClient:WaitForChild("GojoFX")) -- bolts, arcs, glows, rings, impact frames
local Animator = require(GojoClient:WaitForChild("ProceduralAnimator"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib")) -- envelopes, cracks, shake
local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback")) -- damage numbers + hit-confirm

local PAL = CFG.Palette
local SND = CFG.Sounds
-- (2026-11-07 perks) Perks.pal: the caster's colourway, read at cast time on every client - Config.AltPalette
-- ("AZURE SUSANOO") while their player's Skin attribute is "Alt", else the normal palette; every cast handler shadows
-- PAL with it. Perks.cdMul: the local player's cooldown factors (CooldownMul, and UltChargeMul for the guardian and
-- the moves inside it), the same ones TempestService applies.
local Perks = { base = CFG.Palette, alt = table.clone(CFG.Palette), ULT = { Guardian = true, Slash = true, Arrow = true } }
for k, v in pairs(CFG.AltPalette or {}) do
	Perks.alt[k] = v
end
function Perks.pal(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
	return (p and p:GetAttribute("Skin") == "Alt") and Perks.alt or Perks.base
end
function Perks.palOfChar(char)
	local p = char and Players:GetPlayerFromCharacter(char)
	return (p and p:GetAttribute("Skin") == "Alt") and Perks.alt or Perks.base
end
function Perks.cdMul(skill)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if Perks.ULT[skill] then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, as the server does
	local bal = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
	return ((m == m and m > 0) and m or 1) * (Perks.ULT[skill] and 1 or bal.NON_ULT_COOLDOWN_MUL)
end
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local R = math.rad

local Folder = Instance.new("Folder")
Folder.Name = "Tempest"
Folder.Parent = workspace:WaitForChild("LocalFX", 10) or workspace -- every kit's raycasts already ignore LocalFX

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
	return f.Magnitude > 1e-3 and f.Unit or (fallback or Vector3.new(0, 0, -1))
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function ignoreList()
	local list = { Folder }
	for _, n in ipairs({ "LocalFX", "KitFX", "FX", "KitDebris", "VulpineFX", "NPCs" }) do
		if workspace:FindFirstChild(n) then
			table.insert(list, workspace[n])
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	return list
end

-- (ground point, normal) under `pos`
local function groundAt(pos)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -60, 0), groundParams)
	return hit and hit.Position or pos - UP * 3, hit and hit.Normal or UP
end

-- the dominant (right) hand's grip point
local function handPoint(char)
	local hand = char and char:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	if grip then
		return grip.WorldPosition, hand
	end
	if hand then
		return hand.Position, hand
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position + hrp.CFrame.LookVector * 2 or nil, hrp
end

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
	cursorParams.FilterDescendantsInstances = { Folder, player.Character, workspace:FindFirstChild("KitDebris"), workspace:FindFirstChild("KitFX") }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, cursorParams)
	return hit and hit.Position or ray.Origin + ray.Direction * 1000
end

local function sound(id, pos, vol, speed)
	if not id or not pos then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	s.Parent = FX.anchor(Folder, pos, 8)
	s:Play()
	return s
end

local function castFolder(name, life)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Folder
	Debris:AddItem(f, life or 8)
	return f
end

-- poses (degrees; shoulder flexion +X, knee flexion -X, lean forward Waist -X, right arm out RightShoulder Z+)
local POSE = {
	Crouch = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.6, 0) }, LeftHip = { 40, 0, -8 }, RightHip = { 10, 0, 8 }, LeftKnee = { -60, 0, 0 }, RightKnee = { -30, 0, 0 } },
	Gather = { RightShoulder = { 20, 0, 25 }, RightElbow = { 40, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { 60, 0, 45 }, LeftElbow = { 70, 0, 0 }, Waist = { -14, 25, 0 }, Neck = { 6, -20, 0 } },
	Thrust = { RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, RightWrist = { -20, 0, 0 }, LeftShoulder = { -40, 0, -20 }, LeftElbow = { 30, 0, 0 }, Waist = { -24, 18, 0 }, Neck = { 14, -16, 0 } },
	Fling = { RightShoulder = { 60, 0, 85 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 60, 0, -85 }, LeftElbow = { 10, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { 12, 0, 0 } },
	Focus = { RightShoulder = { 120, 0, -40 }, RightElbow = { 110, 0, 0 }, Neck = { 6, 0, 0 } },
	Summon = { RightShoulder = { 160, 0, 30 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 160, 0, -30 }, LeftElbow = { 10, 0, 0 }, Waist = { 12, 0, 0 }, Neck = { 18, 0, 0 } },
	-- KIRIN: the right hand thrust straight up at the storm, chin up
	Call = { RightShoulder = { 172, 0, 8 }, RightElbow = { 4, 0, 0 }, RightWrist = { 10, 0, 0 }, LeftShoulder = { 18, 0, -28 }, LeftElbow = { 40, 0, 0 }, Waist = { 8, -8, 0 }, Neck = { 30, 0, 0 } },
}
local function merge(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end
local poseUntil = setmetatable({}, { __mode = "k" }) -- [character] = when its last one-shot pose ends
local function pose(char, keys, length)
	if char and char.Parent then
		Animator.stopAll(char, 0.08)
		Animator.play(char, { length = length, fadeIn = 0.08, fadeOut = 0.25, keys = keys })
		poseUntil[char] = os.clock() + length
	end
end

---------------------------------------------------------------------------------------------------
-- local body: rooting, the dash, being stunned or knocked back
local rootUntil, faceUntil, faceDirV = 0, 0, nil
local dash = nil -- { lv, att, id, endAt }
local tumbleUntil, stunUntil = 0, 0

local function faceDir(hrp, dir)
	local f = flat(dir, nil)
	if hrp and f then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + f)
	end
end

local function bodyMass(char)
	local m = 0
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and not p.Massless then
			m += p:GetMass()
		end
	end
	return math.max(m, 1)
end

local function stopDash(id)
	if dash and (id == nil or dash.id == id) then
		dash.lv:Destroy()
		dash.att:Destroy()
		dash = nil
		local _, hum, hrp = myChar()
		if hum then
			hum.AutoRotate = true
		end
		if hrp then
			hrp.AssemblyLinearVelocity *= Vector3.new(0.3, 1, 0.3)
		end
	end
end

local function startDash(id, dir, distance, time)
	local char, hum, hrp = myChar()
	if not hrp then
		return
	end
	stopDash()
	hum.AutoRotate = false
	faceDir(hrp, dir)
	local att = Instance.new("Attachment")
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis, lv.SecondaryTangentAxis = Vector3.xAxis, Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z).Unit * (distance / time)
	lv.MaxForce = bodyMass(char) * 2500 -- finite, so driving into something solid never ejects the caster
	lv.Parent = hrp
	dash = { lv = lv, att = att, id = id }
	task.delay(time, function()
		stopDash(id)
	end)
end

-- this client owns its body: knockback and stuns from any Tempest caster are applied here
Knockback.OnClientEvent:Connect(function(vel, duration, keep)
	local char, hum = myChar()
	if not char or typeof(vel) ~= "Vector3" or char:GetAttribute("Guardian") then
		return -- (the guardian holds its caster: no tumble out of its chest)
	end
	stopDash()
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

StunRemote.OnClientEvent:Connect(function(duration, hold)
	local char, _, hrp = myChar()
	if not hrp or char:GetAttribute("Guardian") then
		return
	end
	stopDash()
	stunUntil = math.max(stunUntil, os.clock() + (tonumber(duration) or 1))
	hrp.Anchored = true
	task.delay(tonumber(hold) or 0.5, function()
		if hrp.Parent then
			hrp.Anchored = false
		end
	end)
end)

---------------------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "TempestHUD"
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

-- cinematic letterbox bars for the summoning
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
	Fx2.tween(barTop, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
	Fx2.tween(barBottom, time or 0.35, { Size = UDim2.new(1, 0, h, 0) })
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
local function showTitle(skill)
	local co = CFG.Callouts[skill]
	if not co then
		return
	end
	local token = {}
	titleToken = token
	title.Text = CFG.Labels[skill] or skill
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
	task.delay(1.5, function()
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

-- ability bar in the Limitless kit's layout: two skills, the shared M1, the big eye-mode button, and the guardian
-- ultimate on its own wide button above the row
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

local COOLDOWN = { Lance = CFG.Lance.Cooldown, Pulse = CFG.Pulse.Cooldown, Eyes = CFG.Eyes.Cooldown, Guardian = CFG.Guardian.Cooldown, Slash = CFG.Guardian.SlashCooldown }
local cooldownEnd = { Lance = 0, Pulse = 0, Eyes = 0, Guardian = 0, Slash = 0, Arrow = 0 }
local buttons = {}

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	Request:FireServer(skill, { aim = workspace.CurrentCamera.CFrame.LookVector, target = cursorTarget() })
end

local function iHaveGuardian()
	local char = player.Character
	return char ~= nil and char:GetAttribute("Guardian") == true
end

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
	-- (2026-11-11 keybinds) the chip names the key the player bound to this action, and follows a rebind
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys[id]), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys[id])
	end)
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
	buttons[id] = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true }
	b.Activated:Connect(function()
		request(id)
	end)
end
skillButton("Pulse", 72, -280) -- the Reversal Red slot
skillButton("Lance", 72, -198) -- the Lapse Blue slot
skillButton("Eyes", 104, 0) -- the Hollow Purple slot

-- the shared M1: PUNCH normally, SLASH (the guardian's blade) while the guardian stands
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
		if iHaveGuardian() then
			request("Slash")
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

-- the guardian ultimate on its own wide button above the row (the Domain Expansion slot)
local guardName, guardSub
do
	local co = CFG.Callouts.Guardian
	local b = Instance.new("TextButton")
	b.Name = "Guardian"
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
	-- (2026-11-11 keybinds) the chip names the key the player bound to this action, and follows a rebind
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys.Guardian), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys.Guardian)
	end)
	guardName = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Guardian, ZIndex = 2 })
	guardSub = uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
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
	buttons.Guardian = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Guardian")
	end)
end

-- X RELEASE beside the guardian pill: shown while the guardian stands (dim, with a countdown, until its entrance has
-- played out), clickable / tappable too
local releaseChip, releaseLabel, releaseStroke
do
	local co = CFG.Callouts.Guardian
	local b = Instance.new("TextButton")
	b.Name = "Release"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -194, 1, -132)
	b.Size = UDim2.fromOffset(122, 36)
	b.BackgroundColor3 = co.c1:Lerp(Color3.fromRGB(8, 8, 14), 0.78)
	b.Visible = false
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	releaseStroke = uiStroke(b, co.c0, 2, 0.1)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c0
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11 keybinds) the chip names the key the player bound to this action, and follows a rebind
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Guardian.ReleaseKey or Enum.KeyCode.X), Font = Enum.Font.GothamBold, TextColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.6), ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Guardian.ReleaseKey or Enum.KeyCode.X)
	end)
	releaseLabel = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 10), Text = CFG.Labels.Release or "RELEASE", ZIndex = 2 })
	b.Activated:Connect(function()
		request("Release")
	end)
	releaseChip = b
end

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if equipped() and iHaveGuardian() then
		request("Slash")
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	-- (2026-11-11 keybinds) match the ACTION the pressed key is bound to (its default key), not the raw key; M1 stays
	-- a raw mouse button
	local key = Keybinds.logical(input.KeyCode)
	for skill, defaultKey in pairs(CFG.Keys) do
		if key == defaultKey then
			request(skill)
		end
	end
	-- M1 while the guardian stands swings its blade (the shared punch is off while "Morphed" is set)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) and iHaveGuardian() then
		request("Slash")
	end
	-- X lets the guardian go (the server refuses it while the entrance is still playing)
	if key == (CFG.Guardian.ReleaseKey or Enum.KeyCode.X) and iHaveGuardian() then
		request("Release")
	end
end)

---------------------------------------------------------------------------------------------------
-- cast playback
local lances = {}  -- [id] = { char, folder, att, crackle, t0, windup, dashTime, isLocal, nextBolt }
local stunned = {} -- [model] = { untilT, nextArc }
local guards = {}  -- [character] = { model, joints, t, slash, shield, nextArc }
local handlers = {}

local function endLance(id, linger)
	local l = lances[id]
	if not l then
		return
	end
	lances[id] = nil
	for _, e in ipairs(l.att:GetChildren()) do
		if e:IsA("ParticleEmitter") then
			e.Enabled = false
		end
	end
	if l.crackle then
		l.crackle:Destroy()
	end
	Debris:AddItem(l.att, linger or 0.4)
	-- (2026-11-08) the dash's hand trail goes with it. It used to be left on the RightHand for good, so after one
	-- lance a blue streak followed the hand every time the arms swung (most visibly while running).
	local tr = l.trail
	l.trail = nil
	if tr then
		local a0, a1 = tr.Attachment0, tr.Attachment1
		tr.Enabled = false
		Debris:AddItem(tr, 0.4)
		if a0 then
			Debris:AddItem(a0, 0.4)
		end
		if a1 then
			Debris:AddItem(a1, 0.4)
		end
	end
	if l.isLocal then
		stopDash(id)
		faceUntil = 0
	end
end

function handlers.Cooldown(d)
	if cooldownEnd[d.skill] ~= nil and typeof(d.ends) == "number" then
		cooldownEnd[d.skill] = d.ends
	end
end

function handlers.LanceCharge(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local _, hand = handPoint(char)
	if not char or not hand then
		return
	end
	pose(char, {
		{ t = 0.1, ease = { "Back", "Out" }, pose = merge(POSE.Crouch, POSE.Gather) },
		{ t = d.windup, ease = { "Sine", "InOut" }, pose = merge(POSE.Crouch, POSE.Gather) },
		{ t = d.windup + 0.06, ease = { "Exponential", "Out" }, pose = POSE.Thrust },
		{ t = d.windup + d.dashTime + 0.2, ease = { "Sine", "Out" }, pose = POSE.Thrust },
	}, d.windup + d.dashTime + 0.45)
	-- a dense knot of lightning in the hand: sparks, a glow, a light and a looping crackle
	local att = Instance.new("Attachment")
	att.Name = "LanceFX"
	local grip = hand:FindFirstChild("RightGripAttachment")
	att.Position = grip and grip.Position or Vector3.zero
	att.Parent = hand
	Fx2.emitter(att, {
		Texture = Fx2.Tex.spark, Color = ColorSequence.new(PAL.Core, PAL.Bolt), LightEmission = 1, Rate = 220,
		Lifetime = NumberRange.new(0.08, 0.22), Speed = NumberRange.new(8, 18), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.45, 0), Drag = 6,
	})
	Fx2.emitter(att, {
		Texture = Fx2.Tex.flare, Color = ColorSequence.new(PAL.Bolt, PAL.Deep), LightEmission = 1, Rate = 60,
		Lifetime = NumberRange.new(0.1, 0.2), Speed = NumberRange.new(0, 1), Size = NumberSequence.new(2.4, 0.6),
		Transparency = NumberSequence.new(0.3, 1), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-600, 600),
	})
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = PAL.Bolt, 5, 16, false
	light.Parent = att
	local crackle = Instance.new("Sound")
	crackle.SoundId = SND.Crackle
	crackle.Looped = true
	crackle.Volume = 0.8
	crackle.PlaybackSpeed = 1.4
	crackle.Parent = hand
	crackle:Play()
	sound(SND.Zap, hand.Position, 1, 1.1)
	local l = { char = char, att = att, crackle = crackle, t0 = os.clock(), windup = d.windup, dashTime = d.dashTime, isLocal = isMe(d.userId), nextBolt = 0, hand = hand, pal = PAL }
	lances[d.id] = l
	if l.isLocal then
		rootUntil = os.clock() + d.windup
		faceUntil, faceDirV = os.clock() + d.windup + d.dashTime, d.dir
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		Fx2.envelope({ fov = -6, tint = PAL.Bolt, attack = d.windup * 0.9, release = 0.15 })
	end
	task.delay(d.windup, function()
		if lances[d.id] ~= l then
			return
		end
		l.trail = FX.trail(hand, PAL.Bolt, 0.9, 0.22, { brightness = 3 }) -- removed by endLance
		sound(SND.Whoosh, hand.Position, 1, 1.3)
		if l.isLocal then
			startDash(d.id, d.dir, d.distance, d.dashTime)
			Fx2.envelope({ fov = 12, blur = 4, attack = 0.04, release = 0.35 })
			FX.speedLines(d.dashTime + 0.15, { color = PAL.Core, alpha = 0.6 })
		end
	end)
	task.delay(d.windup + d.dashTime + 1.2, function()
		endLance(d.id)
	end)
end

function handlers.LanceHit(d)
	local PAL = Perks.pal(d.userId)
	local l = lances[d.id]
	local mine = l and l.isLocal
	endLance(d.id, 0.2)
	local pos, dir = d.pos, typeof(d.dir) == "Vector3" and d.dir or Vector3.zAxis
	local f = castFolder("LanceHit", 3)
	FX.glow(f, pos, 22, PAL.Bolt, 0.35)
	FX.glow(f, pos, 9, PAL.Core, 0.2)
	FX.light(f, pos, PAL.Bolt, 10, 45, 0.45)
	FX.ring(f, pos, dir, 2, 28, PAL.Bolt, 0.45)
	FX.streaks(f, pos, { color = PAL.Core, color2 = PAL.Bolt, dir = dir, spread = 35, speed = { 90, 170 }, count = 40, size = 0.7 })
	FX.sparks(f, pos, { color = PAL.Core, color2 = PAL.Bolt, count = 30, speed = { 25, 60 } })
	FX.arcs(f, pos, 7, { count = 7, outward = true, colors = { PAL.Bolt, PAL.Core, PAL.Deep }, width = 0.16, light = true })
	local g, n = groundAt(pos)
	if (g - pos).Magnitude < 10 then
		Fx2.cracks(Folder, g, n, 6, PAL.Bolt, 5)
		FX.ring(f, g + UP * 0.2, n, 3, 22, PAL.Bolt, 0.5)
	end
	sound(SND.HitHeavy, pos, 1, 0.95)
	sound(SND.Thunder, pos, 0.8, 1.3)
	Fx2.shake(1.4, 0.45, pos)
	if mine then
		FX.impact({ tint = PAL.Bolt, lineColor = PAL.Core })
		Fx2.envelope({ fov = -5, contrast = 0.15, attack = 0.02, release = 0.3 })
	end
end

function handlers.LanceEnd(d)
	endLance(d.id)
end

---------------------------------------------------------------------------------------------------
-- KIRIN (2026-11-08; was a radial pulse around the caster). "KirinCall": the caster thrusts a hand at the sky and a
-- bolt leaps from it into a storm that wheels over the strike point; a ring on the ground marks where it will land;
-- KIRIN_DIVE seconds before the server's strikeAt a dragon of lightning pours out of the clouds, coils down and dives
-- onto the point. "Pulse" is the landing: the column of lightning, the burst, and a bolt to every body caught.
local KIRIN_SEGS = 30   -- body segments
local KIRIN_DIVE = 0.8  -- seconds from the dragon leaving the clouds to its landing
local KIRIN_BODY = 0.32 -- its length, as a share of the dive path
local KIRIN_COIL = 34   -- radius of its first coil (studs)
local KIRIN_TURNS = 1.1 -- coils it makes on the way down
local KIRIN_HEAD = 1.9  -- head scale (the shapes below are built at 1)
local KIRIN_GIRTH = 1.5 -- body thickness scale

local function kirinPart(name, shape, color, parent, list)
	local p = Fx2.part(name, shape, Enum.Material.Neon, color, parent)
	p.Transparency = 1
	if list then
		table.insert(list, p)
	end
	return p
end

-- the dive: a coil around the strike point that tightens and drops into a straight plunge (u: 0 = the clouds, 1 = the
-- ground; the body beyond either end is hidden, still in the storm or already in the ground)
local function kirinPath(k, u)
	local e = math.clamp(u, 0, 1)
	local r = KIRIN_COIL * (1 - e) ^ 1.7
	local th = k.th0 + e * KIRIN_TURNS * 2 * math.pi
	return k.pos + Vector3.new(math.cos(th) * r, k.sky * (1 - e) ^ 1.15, math.sin(th) * r)
end

local function kirinDragon(f, pos, sky, strikeAt, PAL, side)
	local k = { pos = pos, sky = sky, th0 = math.random() * math.pi * 2 }
	local all = {} -- every part of the dragon (destroyed once it has poured into the ground)
	local core, sheath, aura = {}, {}, {}
	for j = 1, KIRIN_SEGS do
		core[j] = kirinPart("KirinCore", Enum.PartType.Block, PAL.Core, f, all)
		sheath[j] = kirinPart("KirinBody", Enum.PartType.Block, PAL.Bolt, f, all)
		aura[j] = kirinPart("KirinAura", Enum.PartType.Block, PAL.Deep, f, all)
	end
	-- the head, in head space (-Z = forward): skull, snout, open jaw, swept-back horns, whiskers, eyes
	local head = {
		{ kirinPart("KirinSkull", Enum.PartType.Block, PAL.Bolt, f, all), Vector3.new(3, 2.4, 5), CFrame.new(0, 0, -0.6), 0.25 },
		{ kirinPart("KirinSnout", Enum.PartType.Block, PAL.Core, f, all), Vector3.new(1.4, 1.1, 5.2), CFrame.new(0, 0.2, -1.2), 0 },
		{ kirinPart("KirinJaw", Enum.PartType.Block, PAL.Bolt, f, all), Vector3.new(2.3, 0.6, 4), CFrame.new(0, -1.1, 0.8) * CFrame.Angles(R(-26), 0, 0) * CFrame.new(0, 0, -2), 0.2 },
		{ kirinPart("KirinHorn", Enum.PartType.Block, PAL.Core, f, all), Vector3.new(0.35, 0.35, 4.6), CFrame.new(0.8, 1.1, 0.6) * CFrame.Angles(R(-32), R(18), 0) * CFrame.new(0, 0, 2.3), 0 },
		{ kirinPart("KirinHorn", Enum.PartType.Block, PAL.Core, f, all), Vector3.new(0.35, 0.35, 4.6), CFrame.new(-0.8, 1.1, 0.6) * CFrame.Angles(R(-32), R(-18), 0) * CFrame.new(0, 0, 2.3), 0 },
		{ kirinPart("KirinWhisker", Enum.PartType.Block, PAL.Bolt, f, all), Vector3.new(0.18, 0.18, 6), CFrame.new(1.3, -0.4, -2.6) * CFrame.Angles(R(-12), R(48), 0) * CFrame.new(0, 0, 3), 0.15 },
		{ kirinPart("KirinWhisker", Enum.PartType.Block, PAL.Bolt, f, all), Vector3.new(0.18, 0.18, 6), CFrame.new(-1.3, -0.4, -2.6) * CFrame.Angles(R(-12), R(-48), 0) * CFrame.new(0, 0, 3), 0.15 },
		{ kirinPart("KirinEye", Enum.PartType.Ball, PAL.Core, f, all), Vector3.one * 0.8, CFrame.new(1.05, 0.7, -1.6), 0 },
		{ kirinPart("KirinEye", Enum.PartType.Ball, PAL.Core, f, all), Vector3.one * 0.8, CFrame.new(-1.05, 0.7, -1.6), 0 },
	}
	for _, h in ipairs(head) do
		h[2] = h[2] * KIRIN_HEAD
		h[3] = CFrame.new(h[3].Position * KIRIN_HEAD) * h[3].Rotation
	end
	local skull = head[1][1]
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = PAL.Bolt, 55, 0, false
	light.Parent = skull
	local sparks = Fx2.emitter(skull, {
		Texture = Fx2.Tex.spark, Color = ColorSequence.new(PAL.Core, PAL.Bolt), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(10, 30), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.9, 0), Drag = 4,
	})
	local trail = FX.trail(skull, ColorSequence.new(PAL.Core, PAL.Bolt), 3 * KIRIN_HEAD, 0.3, { brightness = 3, tail = 0.05 })
	trail.Enabled = false
	local function hide(p)
		p.Transparency = 1
	end
	local startAt = strikeAt - KIRIN_DIVE
	local step = KIRIN_BODY / KIRIN_SEGS
	local shown, landed, nextArc = false, false, 0
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = now() - startAt
		if el < 0 then
			return
		end
		local u = (el / KIRIN_DIVE) ^ 1.3
		if not f.Parent or u - KIRIN_BODY >= 1 then
			conn:Disconnect() -- the whole body has poured into the ground
			for _, p in ipairs(all) do
				p:Destroy()
			end
			return
		end
		if not shown then
			shown = true -- it bursts out of the clouds
			trail.Enabled = true
			light.Brightness = 8
			sparks.Rate = 200
			local at = kirinPath(k, 0)
			FX.glow(f, at, 40, PAL.Bolt, 0.45, { brightness = 4 })
			FX.arcs(f, at, 10, { count = 5, outward = true, colors = { PAL.Bolt, PAL.Core }, width = 0.3, life = 0.15 })
			sound(SND.Thunder, at, 1, 0.7)
			sound(SND.Crackle, at, 1, 0.8)
		end
		-- the body: segment j runs from ua (toward the head) to ub, thick at the neck and thin at the tail
		local visible = {}
		for j = 1, KIRIN_SEGS do
			local ua = math.clamp(u - (j - 1) * step, 0, 1)
			local ub = math.clamp(u - j * step, 0, 1)
			if ua - ub < 1e-4 then
				hide(core[j])
				hide(sheath[j])
				hide(aura[j])
			else
				local pa, pb = kirinPath(k, ua), kirinPath(k, ub)
				local len = (pa - pb).Magnitude
				if len > 1e-3 then
					local thick = (0.5 + 2.9 * (1 - (j - 1) / KIRIN_SEGS) ^ 0.7) * KIRIN_GIRTH
					local cf = CFrame.lookAt((pa + pb) / 2, pa)
					core[j].Size = Vector3.new(thick * 0.38, thick * 0.38, len + thick * 0.4)
					sheath[j].Size = Vector3.new(thick, thick, len + thick * 0.6)
					aura[j].Size = Vector3.new(thick * 1.9, thick * 1.9, len + thick)
					core[j].CFrame, sheath[j].CFrame, aura[j].CFrame = cf, cf, cf
					core[j].Transparency, sheath[j].Transparency, aura[j].Transparency = 0.02, 0.35, 0.82
					visible[#visible + 1] = j
				end
			end
		end
		-- the head leads the body down
		if u <= 1 then
			local hp = kirinPath(k, u)
			local dv = hp - kirinPath(k, math.max(u - 0.02, 0))
			dv = dv.Magnitude > 1e-3 and dv.Unit or -UP
			local hcf = CFrame.lookAt(hp, hp + dv, math.abs(dv.Y) > 0.9 and side or UP)
			for _, h in ipairs(head) do
				h[1].Size = h[2]
				h[1].CFrame = hcf * h[3]
				h[1].Transparency = h[4]
			end
		elseif not landed then
			landed = true -- (the landing burst is the server's "Pulse")
			for _, h in ipairs(head) do
				hide(h[1])
			end
			trail.Enabled = false
			sparks.Rate = 0
			light.Brightness = 0
		end
		-- it is made of lightning: arcs crawl over the body
		local clock = os.clock()
		if clock >= nextArc and #visible > 0 then
			nextArc = clock + 0.035
			for _ = 1, 2 do
				local j = visible[math.random(1, #visible)]
				FX.arcs(f, sheath[j].Position, 2.5 + sheath[j].Size.X, { count = 1, colors = { PAL.Bolt, PAL.Core, PAL.Pulse }, width = 0.14, life = 0.1 })
			end
		end
	end)
end

-- the storm the dragon comes out of: a slab of dark cloud with lightning flickering through it
local function kirinStorm(f, skyPos, life, PAL)
	local cloud = Fx2.part("KirinStorm", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), f)
	cloud.Transparency = 1
	cloud.Size = Vector3.new(84, 8, 84)
	cloud.CFrame = CFrame.new(skyPos)
	local smoke = Fx2.emitter(cloud, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(Color3.fromRGB(62, 66, 92), Color3.fromRGB(24, 24, 38)), LightEmission = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 18), NumberSequenceKeypoint.new(1, 34) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.3), NumberSequenceKeypoint.new(0.75, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.6, 2.4), Rate = 45, Speed = NumberRange.new(1, 4), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25), Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Bottom,
	})
	smoke:Emit(30)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = PAL.Bolt, 60, 0, false
	glow.Parent = cloud
	FX.ring(f, skyPos, UP, 30, 110, PAL.Bolt, 0.9, { alpha = 0.5 })
	task.spawn(function()
		local t0 = os.clock()
		while f.Parent and os.clock() - t0 < life do
			local a = skyPos + Vector3.new(math.random(-34, 34), math.random(-3, 3), math.random(-34, 34))
			local b = a + Vector3.new(math.random(-20, 20), math.random(-6, 2), math.random(-20, 20))
			FX.bolt(f, a, b, { color = PAL.Bolt, core = PAL.Core, width = 0.35, segments = 7, jag = 0.3, life = 0.12, restrike = 1 })
			glow.Brightness = 6
			task.wait(0.06)
			glow.Brightness = 1
			task.wait(0.06 + math.random() * 0.1)
		end
		smoke.Enabled = false
		if glow.Parent then
			Fx2.tween(glow, 0.4, { Brightness = 0 })
		end
	end)
end

function handlers.KirinCall(d)
	local PAL = Perks.pal(d.userId)
	local pos = d.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	local radius, sky = tonumber(d.radius) or 18, tonumber(d.sky) or 150
	local strikeAt = tonumber(d.strikeAt) or (now() + (tonumber(d.delay) or 1.2))
	local remaining = math.max(strikeAt - now(), 0)
	local f = castFolder("Kirin", remaining + 3)
	local skyPos = pos + UP * sky
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local side = hrp and flat(pos - hrp.Position, Vector3.zAxis) or Vector3.zAxis
	-- the call: the right hand thrust at the sky and a bolt leaping from it into the storm; at the strike the arm
	-- comes down at the target
	if char then
		local hold = math.max(remaining, 0.4)
		pose(char, {
			{ t = 0.12, ease = { "Back", "Out" }, pose = POSE.Call },
			{ t = hold, ease = { "Sine", "InOut" }, pose = POSE.Call },
			{ t = hold + 0.1, ease = { "Exponential", "Out" }, pose = POSE.Thrust },
			{ t = hold + 0.35, pose = POSE.Thrust },
		}, hold + 0.6)
		task.delay(0.12, function()
			local hp = char.Parent and handPoint(char)
			if hp then
				FX.bolt(f, hp, hp + (skyPos - hp).Unit * 90, { color = PAL.Bolt, core = PAL.Core, width = 0.35, segments = 12, jag = 0.08, life = 0.2, restrike = 2, light = true })
				FX.glow(f, hp, 9, PAL.Bolt, 0.3)
				FX.arcs(f, hp, 2.5, { count = 4, outward = true, colors = { PAL.Bolt, PAL.Core }, width = 0.1 })
				sound(SND.Zap, hp, 1, 0.9)
				sound(SND.Rise, hp, 0.8, 1.2)
			end
		end)
	end
	if isMe(d.userId) then
		rootUntil = os.clock() + 0.5
		faceUntil, faceDirV = os.clock() + 0.6, side
		Fx2.envelope({ fov = -4, tint = PAL.Bolt, contrast = 0.12, attack = 0.25, hold = math.max(remaining - 0.35, 0), release = 0.2 })
	end
	-- the storm, and where it will land
	kirinStorm(f, skyPos, remaining + 0.6, PAL)
	sound(SND.Thunder, skyPos, 1, 0.55)
	local g, n = groundAt(pos)
	local mark = Fx2.part("KirinMark", Enum.PartType.Cylinder, Enum.Material.Neon, PAL.Bolt, f)
	local up = math.abs(n.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	mark.CFrame = CFrame.fromMatrix(g + n * 0.15, n, n:Cross(up).Unit)
	mark.Size = Vector3.new(0.1, radius * 2, radius * 2)
	mark.Transparency = 1
	Fx2.tween(mark, math.max(remaining * 0.7, 0.1), { Transparency = 0.8 })
	task.spawn(function()
		while f.Parent and now() < strikeAt - 0.05 do
			FX.ring(f, g + n * 0.25, n, radius * 2.5, radius * 1.9, PAL.Bolt, 0.3, { alpha = 0.3 })
			if math.random() < 0.5 then
				FX.arcs(f, g + n * 0.5, radius * 0.8, { count = 1, colors = { PAL.Bolt, PAL.Core }, width = 0.08, life = 0.08 })
			end
			task.wait(0.2)
		end
		if mark.Parent then
			mark:Destroy()
		end
	end)
	-- the dragon
	kirinDragon(f, g, sky, strikeAt, PAL, side)
end

-- the landing
function handlers.Pulse(d)
	local PAL = Perks.pal(d.userId)
	local pos, radius = d.pos, d.radius
	if typeof(pos) ~= "Vector3" then
		return
	end
	local sky = tonumber(d.sky) or 150
	local f = castFolder("Pulse", 4)
	-- a column of lightning out of the storm, a white flash, a sphere of lightning bursting out to the radius
	FX.bolt(f, pos + UP * sky, pos, { color = PAL.Bolt, core = PAL.Core, width = 1.2, segments = 16, jag = 0.05, life = 0.32, restrike = 3, light = true })
	FX.bolt(f, pos + UP * sky + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14)), pos, { color = PAL.Bolt, core = PAL.Core, width = 0.5, segments = 14, jag = 0.1, life = 0.22, restrike = 2 })
	Fx2.flash(f, pos + UP * 2, radius * 0.8, PAL.Core, 0.3)
	FX.glow(f, pos + UP * 2, radius * 2.4, PAL.Bolt, 0.45, { brightness = 4 })
	FX.shell(f, pos, 1, radius, PAL.Bolt, 0.45, Enum.Material.ForceField)
	FX.shell(f, pos, 0.5, radius * 0.45, PAL.Core, 0.22)
	FX.light(f, pos + UP * 4, PAL.Bolt, 12, 80, 0.7)
	FX.ring(f, pos + UP * 0.3, UP, 2, radius * 2.6, PAL.Bolt, 0.55)
	FX.ring(f, pos + UP * 0.3, UP, 2, radius * 1.6, PAL.Core, 0.35)
	FX.ring(f, pos + UP * 3, flat(workspace.CurrentCamera.CFrame.LookVector), 2, radius * 2, PAL.Core, 0.4)
	Fx2.shockwave(f, pos + UP * 0.2, UP, 4, radius * 3.4, PAL.Pulse, 0.6)
	FX.streaks(f, pos + UP * 2, { color = PAL.Core, color2 = PAL.Bolt, speed = { 80, 160 }, count = 60, size = 0.7 })
	FX.sparks(f, pos + UP * 2, { color = PAL.Core, color2 = PAL.Bolt, count = 40, speed = { 30, 80 } })
	task.spawn(function()
		for i = 1, 6 do
			FX.arcs(f, pos + UP * 2, radius * (0.35 + i * 0.11), { count = 4, colors = { PAL.Bolt, PAL.Core, PAL.Pulse }, width = 0.18, jag = 0.35 })
			task.wait(0.06)
		end
	end)
	-- a bolt chains out to every body it caught, and they crackle for as long as they are stunned
	if type(d.caught) == "table" then
		for _, m in ipairs(d.caught) do
			local r = typeof(m) == "Instance" and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart"))
			if r then
				FX.bolt(f, pos + UP * 2, r.Position, { color = PAL.Bolt, core = PAL.Core, width = 0.22, segments = 8, jag = 0.22, life = 0.25, restrike = 3, light = true })
				stunned[m] = { untilT = os.clock() + d.stun, nextArc = 0, pal = PAL }
			end
		end
	end
	local g, n = groundAt(pos)
	Fx2.cracks(Folder, g, n, radius * 0.75, PAL.Bolt, 6)
	sound(SND.Thunder, pos, 1, 0.85)
	sound(SND.Boom, pos, 1, 1)
	sound(SND.HitHeavy, pos, 0.9, 0.8)
	Fx2.shake(2.2, 0.7, pos, 220)
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		FX.impact({ tint = PAL.Bolt, lineColor = PAL.Core })
		Fx2.envelope({ fov = 8, tint = PAL.Bolt, contrast = 0.2, attack = 0.03, hold = 0.1, release = 0.5 })
	end
end

function handlers.EyesOn(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local head = char and char:FindFirstChild("Head")
	if head then
		local f = castFolder("EyesOn", 3)
		FX.glow(f, head.Position, 6, PAL.EyeRight, 0.35)
		FX.glow(f, head.Position, 4, PAL.EyeLeft, 0.5)
		FX.ring(f, head.Position, head.CFrame.LookVector, 0.5, 9, PAL.EyeTrail, 0.4)
		sound(SND.Rise, head.Position, 0.8, 1.4)
		pose(char, { { t = 0.12, pose = POSE.Focus }, { t = 0.5, pose = POSE.Focus } }, 0.8)
	end
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		Fx2.envelope({ tint = PAL.EyeLeft, sat = -0.25, contrast = 0.2, attack = 0.15, hold = 0.35, release = 0.8 })
	end
end

function handlers.EyesOff(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local head = char and char:FindFirstChild("Head")
	if head and d.reason ~= "dodge" then
		FX.sparks(castFolder("EyesOff", 2), head.Position, { color = PAL.EyeTrail, count = 14, speed = { 6, 14 } })
	end
end

-- the dodge: a violet afterimage where the hit would have landed, a streak to the new spot behind the attacker
function handlers.EyesDodge(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local f = castFolder("Dodge", 3)
	if char and typeof(d.from) == "Vector3" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local shift = hrp and (d.from - hrp.Position) or Vector3.zero
		for _, p in ipairs(char:GetChildren()) do
			if p:IsA("BasePart") and p.Transparency < 1 and p.Name ~= "HumanoidRootPart" then
				local ghost = Fx2.part("Afterimage", Enum.PartType.Block, Enum.Material.Neon, PAL.EyeTrail, f)
				ghost.Size = p.Size
				ghost.CFrame = p.CFrame + shift
				ghost.Transparency = 0.35
				Fx2.tween(ghost, 0.6, { Transparency = 1, Size = p.Size * 1.15 })
			end
		end
		FX.glow(f, d.from, 10, PAL.EyeLeft, 0.4)
	end
	if typeof(d.from) == "Vector3" and typeof(d.to) == "Vector3" then
		local streak = Fx2.part("BlinkStreak", Enum.PartType.Block, Enum.Material.Neon, PAL.EyeTrail, f)
		local span = d.to - d.from
		streak.Size = Vector3.new(0.5, 0.5, math.max(span.Magnitude, 0.5))
		streak.CFrame = CFrame.lookAt((d.from + d.to) / 2 + UP, d.to + UP)
		Fx2.tween(streak, 0.35, { Size = Vector3.new(0.05, 0.05, span.Magnitude), Transparency = 1 })
		FX.glow(f, d.to, 8, PAL.EyeRight, 0.3)
		FX.sparks(f, d.to, { color = PAL.EyeTrail, color2 = PAL.EyeRight, count = 20 })
		sound(SND.Whoosh, d.to, 1, 0.8)
	end
	if isMe(d.userId) then
		FX.impact({ tint = PAL.EyeLeft, lineColor = PAL.EyeTrail })
	end
end

-- (2026-11-10) the Susanoo face beat: the moment G is cast the caster is held still (no walking, jumping or turning)
-- and their own camera swings round to a close-up of Sasuke's face - in front of the head along its LookVector, a
-- touch below eye level - holds there while the storm gathers and the guardian forms round him, then hands back to
-- the follow camera before the arrow is drawn. The default camera keeps running underneath the whole time: its own
-- output is put back before it runs each frame (so the close-up never leaks into its look direction) and the
-- close-up is blended over it after the kit's shake, so the return lands on wherever the follow camera has got to
-- (the guardian framing by then). Guardian parts (and the shield dome) between the lens and the face are hidden on
-- this client only. It lets go early on GuardianEnd, a summon that never bursts, death, a respawn, a kit change or
-- anything else taking the camera, and nothing it touches outlives it.
local FaceCam = {}
do
	local PRE, FOLLOW, POST = "TempestFaceCamPre", "TempestFaceCamFollow", "TempestFaceCamPost"
	local CAMERA = Enum.RenderPriority.Camera.Value
	local st -- the running beat (nil when none)
	local wallRay = RaycastParams.new()
	wallRay.FilterType = Enum.RaycastFilterType.Exclude

	local function ease(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end

	-- does the segment a -> b pass through this part's box (padded)?
	local AXES = { "X", "Y", "Z" }
	local function crosses(part, a, b, pad)
		local cf, half = part.CFrame, part.Size * 0.5 + Vector3.one * pad
		local p0 = cf:PointToObjectSpace(a)
		local d = cf:PointToObjectSpace(b) - p0
		local t0, t1 = 0, 1
		for _, ax in ipairs(AXES) do
			local o, v, h = p0[ax], d[ax], half[ax]
			if math.abs(v) < 1e-6 then
				if o < -h or o > h then
					return false
				end
			else
				local ta, tb = (-h - o) / v, (h - o) / v
				if ta > tb then
					ta, tb = tb, ta
				end
				t0, t1 = math.max(t0, ta), math.min(t1, tb)
				if t0 > t1 then
					return false
				end
			end
		end
		return true
	end

	-- hidden (on this client) while it stands between the lens and the face; shown again once it does not
	local function screen(s, p, lens, eye, on)
		if on and p.Parent and crosses(p, lens, eye, 0.6) then
			s.hidden[p] = true
			p.LocalTransparencyModifier = 1
		elseif s.hidden[p] then
			s.hidden[p] = nil
			p.LocalTransparencyModifier = 0
		end
	end

	local function unfreeze(s)
		if s.frozen then
			s.frozen = false
			if s.hum and s.hum.Parent then
				s.hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, s.jumpWas ~= false)
			end
		end
	end

	local function finish()
		local s = st
		if not s then
			return
		end
		st = nil
		for _, n in ipairs({ PRE, FOLLOW, POST }) do
			pcall(RunService.UnbindFromRenderStep, RunService, n)
		end
		unfreeze(s)
		for p in pairs(s.hidden) do
			p.LocalTransparencyModifier = 0
		end
		table.clear(s.hidden)
		if s.outline and s.outline.Parent then
			s.outline.Enabled = true
		end
		local cam = workspace.CurrentCamera
		if s.chain and cam then
			cam.CFrame = s.chain -- the follow camera exactly as it last was
		end
	end

	-- hand the camera back over `dur` seconds from wherever the blend is; `release` lets the body go at once
	function FaceCam.out(dur, release)
		local s = st
		if not s then
			return
		end
		if release then
			unfreeze(s)
		end
		if s.phase ~= "out" then
			s.phase, s.outFrom, s.outT0, s.outDur = "out", s.a, os.clock(), math.max(dur or 0.5, 0.05)
		end
	end
	function FaceCam.stop()
		finish()
	end
	function FaceCam.burst()
		if st then
			st.burst = true
		end
	end
	function FaceCam.active()
		return st ~= nil
	end
	function FaceCam.frozen()
		return st ~= nil and st.frozen
	end
	-- the follow camera's own CFrame (what the camera would show without the beat)
	function FaceCam.camCF()
		return (st and st.chain) or workspace.CurrentCamera.CFrame
	end

	local function pre()
		local cam = workspace.CurrentCamera
		if st and st.chain and cam then
			cam.CFrame = st.chain
		end
	end
	local function follow()
		if st then
			st.follow = workspace.CurrentCamera.CFrame
		end
	end
	local function step(dt)
		local s = st
		if not (s and s.follow) then
			return
		end
		local cam = workspace.CurrentCamera
		local char, hum, hrp = myChar()
		local head = char and char:FindFirstChild("Head")
		local subj = cam and cam.CameraSubject
		local now = os.clock()
		local el = now - s.t0
		if not (head and char == s.char and subj and (subj == hum or subj:IsDescendantOf(char))) or cam.CameraType ~= Enum.CameraType.Custom or el > s.gather + 6 then
			finish() -- died, respawned, or something else has the camera: let go at once
			return
		end
		local chain = cam.CFrame -- the follow camera plus the kit's shake, as it would have shown
		s.chain = chain
		if not equipped() then
			FaceCam.out(0.3, true)
		elseif s.phase ~= "out" and not s.burst and el > s.gather + 0.6 then
			FaceCam.out(0.4, true) -- the summon was refused or cut short before the guardian burst out
		end
		local a = s.a
		if s.phase == "in" then
			a = ease(el / s.tIn)
			if el >= s.tIn then
				s.phase = "hold"
			end
		elseif s.phase == "hold" then
			a = 1
			if el >= s.holdEnd then
				s.a = 1
				FaceCam.out(s.tOut)
			end
		end
		if s.phase == "out" then
			local k = (now - s.outT0) / s.outDur
			if k >= 1 then
				finish()
				return
			end
			a = s.outFrom * (1 - ease(k))
		end
		s.a = a
		-- the close-up: in front of the face along the head's own LookVector, a touch below eye level, looking at it
		local hs = head.Size.Y
		local aim = head.Position
		local look = flat(head.CFrame.LookVector, flat(hrp.CFrame.LookVector))
		s.look = s.look and flat(s.look:Lerp(look, 1 - math.exp(-10 * dt)), look) or look
		local fovY = math.rad(math.clamp(cam.FieldOfView, 20, 110))
		local dist = math.clamp(hs * (CFG.Guardian.FaceCamFrame or 2.7) / (2 * math.tan(fovY / 2)), 1.4, 7)
		local want = aim + s.look * dist - UP * (hs * 0.22)
		-- a wall right in front of him: the lens stops short of it
		wallRay.FilterDescendantsInstances = ignoreList()
		local hit = workspace:Raycast(aim, want - aim, wallRay)
		if hit and hit.Instance.CanCollide then
			want = aim + (want - aim).Unit * math.max(hit.Distance - 0.35, 1.1)
		end
		local cf = chain
		if a > 0.001 then
			-- swung round the head (never straight through the body) from the follow camera to the close-up
			local fol = s.follow
			local o0, o1 = fol.Position - aim, want - aim
			local r0, r1 = Vector2.new(o0.X, o0.Z).Magnitude, Vector2.new(o1.X, o1.Z).Magnitude
			local dy = (math.atan2(o1.X, o1.Z) - math.atan2(o0.X, o0.Z) + math.pi) % (2 * math.pi) - math.pi
			-- round the same side all the way (a near half-turn must not flip sides as the follow camera drifts)
			s.side = s.side or (dy >= 0 and 1 or -1)
			if dy * s.side < 0 and math.abs(dy) > 2.2 then
				dy += 2 * math.pi * s.side
			end
			local yaw = math.atan2(o0.X, o0.Z) + dy * a
			local r = r0 + (r1 - r0) * a
			local pos = aim + Vector3.new(math.sin(yaw) * r, o0.Y + (o1.Y - o0.Y) * a, math.cos(yaw) * r)
			local target = (fol.Position + fol.LookVector * o0.Magnitude):Lerp(aim, a)
			if (target - pos).Magnitude > 0.05 then
				-- a quarter of the kit's shake still reaches the close-up
				cf = CFrame.lookAt(pos, target) * CFrame.identity:Lerp(fol:ToObjectSpace(chain), 1 - 0.75 * a)
			end
		end
		cam.CFrame = cf
		-- the guardian (and its shield dome) is hidden where it stands between the lens and the face, this client only
		local model = char:FindFirstChild("GuardianConstruct")
		if model ~= s.model or now >= s.nextScan then
			s.model, s.parts, s.nextScan = model, {}, now + 0.25
			if model then
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") then
						table.insert(s.parts, p)
					end
				end
			end
		end
		local on, lens = a > 0.02, cf.Position
		for _, p in ipairs(s.parts) do
			screen(s, p, lens, aim, on)
		end
		local g = guards[char]
		if g and g.shield then
			screen(s, g.shield, lens, aim, on)
		end
		if g and g.outline and g.outline.Parent then
			s.outline = g.outline
			g.outline.Enabled = a < 0.35 -- (the silhouette outline would draw the hidden chest over the face)
		end
	end
	local function post(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[TempestClient] face cam: " .. tostring(err))
			finish()
		end
	end

	-- GuardianStart on the caster's own client
	function FaceCam.start(gather)
		finish()
		local char, hum, hrp = myChar()
		if not char or not equipped() or not char:FindFirstChild("Head") then
			return
		end
		local G = CFG.Guardian
		local summon = G.SummonTime or 1.6
		local s = { char = char, hum = hum, t0 = os.clock(), gather = gather or G.GatherTime or 1.2, phase = "in", a = 0, hidden = {}, parts = {}, nextScan = 0, frozen = true }
		s.tIn, s.tOut = G.FaceCamIn or 0.55, G.FaceCamOut or 0.7
		-- the hold ends part-way into the guardian's reveal, and the hand-back is always over before the arrow is drawn
		s.holdEnd = math.max(s.tIn, math.min(s.gather + summon * (G.FaceCamHold or 0.5), s.gather + summon - s.tOut - 0.05))
		-- held still: no jump (walk speed and turning are held by frame() while FaceCam.frozen())
		s.jumpWas = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		hum.AutoRotate = false
		hrp.AssemblyLinearVelocity *= Vector3.new(0, 1, 0)
		st = s
		RunService:BindToRenderStep(PRE, CAMERA - 1, pre)
		RunService:BindToRenderStep(FOLLOW, CAMERA + 1, follow)
		RunService:BindToRenderStep(POST, CAMERA + 4, post) -- after the kit's envelopes (+2) and shake (+3)
	end
end

-- the guardian camera: pulled back and up to frame a ~35-stud giant, then given back exactly as it was (zoom limits,
-- the zoom distance itself, CameraOffset 0)
local camTween
local camSaved -- { min, max, zoom } while the guardian camera is on
local camGrace = 0
local function guardCamera(on, time)
	local _, hum = myChar()
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	local G = CFG.Guardian
	local k = G.Scale or 1
	if on then
		local cam = workspace.CurrentCamera
		if not camSaved then
			camSaved = { min = player.CameraMinZoomDistance, max = player.CameraMaxZoomDistance, zoom = (FaceCam.camCF().Position - cam.Focus.Position).Magnitude }
		end
		camGrace = os.clock() + 3
		local saved = camSaved
		local zoom = (G.CameraZoom or 46) * k
		player.CameraMaxZoomDistance = math.max(saved.max, (G.CameraZoomMax or 120) * k)
		player.CameraMinZoomDistance = zoom -- pushes the camera out to frame it...
		task.delay(0.8, function()
			if camSaved == saved then
				player.CameraMinZoomDistance = math.min((G.CameraZoomMin or 30) * k, zoom) -- ...then the wheel is free again
			end
		end)
		if hum then
			camTween = Fx2.tween(hum, time or 0.8, { CameraOffset = Vector3.new(0, (G.CameraLift or 6) * k, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	else
		if hum then
			camTween = Fx2.tween(hum, time or 0.5, { CameraOffset = Vector3.zero }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
		local saved = camSaved
		camSaved = nil
		if saved then
			local back = math.clamp(saved.zoom, saved.min, saved.max)
			player.CameraMinZoomDistance = math.min(saved.min, back)
			player.CameraMaxZoomDistance = back -- pulls the camera back in to where it was...
			task.delay(0.8, function()
				if camSaved == nil then
					player.CameraMaxZoomDistance = saved.max -- ...then the normal limits
					player.CameraMinZoomDistance = saved.min
				end
			end)
		end
	end
end

local VERT = CFrame.Angles(0, 0, R(90)) -- a Cylinder part's axis is X; this stands it upright
local arrows = {} -- [id] = the bow being drawn

-- a thick segment from a to b (a Block part whose Z axis runs along it)
local function seg(part, a, b, thick)
	part.Size = Vector3.new(thick, thick, math.max((b - a).Magnitude, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

local function neon(name, shape, color, parent)
	return Fx2.part(name, shape, Enum.Material.Neon, color, parent or Folder)
end

-- a part of a player's standing guardian (nil while it is not up, or for a template construct without it)
local function guardPart(char, name)
	local model = char and char:FindFirstChild("GuardianConstruct")
	return model and model:FindFirstChild(name)
end

-- the guardian's bow grip: the arrow leaves from here
local function bowPoint(char)
	local grip = guardPart(char, "BowGrip")
	if grip then
		return grip.Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position + hrp.CFrame.LookVector * 6 + UP * 9) or Vector3.zero
end

-- what each client remembers about a construct: every part's transparency as built (the reveal, the dissolve and the
-- sword let go for the draw all come back to it) and the parts a drawn bow is hiding
local baseT = setmetatable({}, { __mode = "k" })
local drawHidden = setmetatable({}, { __mode = "k" })
local function rememberBase(model)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and baseT[p] == nil then
			baseT[p] = p.Transparency
		end
	end
end
local SWORD = { Blade = true, BladeCore = true, BladeTip = true, Tsuba = true, Hilt = true, BowString = true }

-- the drawn string and the arrow on it, rebuilt from the guardian's own bow every frame: the string runs from both
-- bow tips to the right gauntlet, the arrow from that nock out through the grip
local function makeDraw(pal)
	local PAL = pal or PAL
	local v = {}
	v.str1, v.str2 = neon("BowString", Enum.PartType.Block, PAL.Core), neon("BowString", Enum.PartType.Block, PAL.Core)
	v.shaft = neon("ArrowShaft", Enum.PartType.Block, PAL.Guard)
	v.shaftCore = neon("ArrowShaftCore", Enum.PartType.Block, PAL.Core)
	v.head = neon("ArrowHead", Enum.PartType.Block, PAL.Core)
	v.parts = { v.str1, v.str2, v.shaft, v.shaftCore, v.head }
	for _, p in ipairs(v.parts) do
		p.Transparency = 1
	end
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = PAL.Guard, 16, 2, false
	l.Parent = v.head
	function v:destroy()
		for _, p in ipairs(self.parts) do
			p:Destroy()
		end
	end
	-- w: 0 = the string at rest, 1 = full draw (it follows the right gauntlet in as the draw pose blends in)
	function v:update(char, w)
		local grip = guardPart(char, "BowGrip")
		local fist = guardPart(char, "GauntletRight")
		local top = grip and grip:FindFirstChild("BowTipTop")
		local bottom = grip and grip:FindFirstChild("BowTipBottom")
		if not (grip and fist and top and bottom) then
			return nil
		end
		local a, b = top.WorldPosition, bottom.WorldPosition
		local nock = ((a + b) / 2):Lerp(fist.Position, w)
		seg(self.str1, a, nock, 0.22)
		seg(self.str2, nock, b, 0.22)
		local dir = grip.Position - nock
		dir = dir.Magnitude > 0.5 and dir.Unit or grip.CFrame.LookVector
		local tip = grip.Position + dir * 4
		local g = math.clamp(w * 1.5, 0.05, 1)
		seg(self.shaft, nock, tip, 0.9 * g)
		seg(self.shaftCore, nock, tip, 0.36 * g)
		self.head.Size = Vector3.new(1.7, 1.7, 3.6) * g
		self.head.CFrame = CFrame.lookAt(tip + dir * 1.6, tip + dir * 3) * CFrame.Angles(0, 0, R(45))
		if self.parts[1].Transparency ~= 0 then
			for _, p in ipairs(self.parts) do
				p.Transparency = 0
			end
		end
		return tip, grip.Position
	end
	return v
end

local function endBow(id, restoreAfter)
	local a = arrows[id]
	if not a then
		return
	end
	arrows[id] = nil
	a.bow:destroy()
	local g = guards[a.char]
	if g and g.draw and g.draw.id == id then
		g.draw = nil
		g.loose = { t0 = os.clock() } -- the arms come back down
	end
	-- the sword comes back to the right hand (unless the guardian is already dissolving)
	task.delay(restoreAfter or 0, function()
		for part in pairs(a.hidden) do
			drawHidden[part] = nil
			if part.Parent and part.Parent.Name == "GuardianConstruct" and baseT[part] then
				part.Transparency = baseT[part]
			end
		end
	end)
end

function handlers.GuardianStart(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local pos, gather = d.pos, d.gather
	local g, n = groundAt(pos)
	if char then
		pose(char, { { t = 0.25, ease = { "Quad", "Out" }, pose = POSE.Summon }, { t = gather, pose = POSE.Summon } }, gather + 0.3)
	end
	local f = castFolder("Summon", gather + 3)
	-- a column of violet light thickens around the caster
	local pillar = neon("Pillar", Enum.PartType.Cylinder, PAL.Guard, f)
	pillar.Transparency = 0.6
	pillar.Size = Vector3.new(600, 1, 1)
	pillar.CFrame = CFrame.new(g + UP * 300) * VERT
	Fx2.tween(pillar, gather, { Size = Vector3.new(600, 11, 11), Transparency = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(pillar, gather + 0.1)
	Fx2.cracks(Folder, g, n, 24, PAL.Guard, gather + 6)
	-- a lightning storm closes in: sky strikes land nearer and faster as the gather runs out
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < gather do
			local prog = (os.clock() - t0) / gather
			local ang, r = math.random() * math.pi * 2, (32 - 24 * prog) * (0.35 + math.random() * 0.65)
			local at = g + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			FX.bolt(f, at + UP * 130 + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14)), at, { color = PAL.Guard, core = PAL.Core, width = 0.4, segments = 10, jag = 1.5, life = 0.13, restrike = 1 })
			FX.glow(f, at + UP, 16, PAL.Guard, 0.25)
			if math.random() < 0.5 then
				FX.arcs(f, pos + UP * 5, 7, { count = 2, colors = { PAL.Guard, PAL.Core }, width = 0.15 })
			end
			if math.random() < 0.3 then
				sound(SND.Zap, at, 0.7, 0.8 + math.random() * 0.4)
			end
			task.wait(0.05 + 0.05 * (1 - prog))
		end
	end)
	for i = 0, 3 do
		task.delay(i * gather / 4, function()
			FX.ring(f, g + UP * 0.3, UP, 84 - i * 10, 6, PAL.Guard, 0.9, { ease = "in" })
			FX.streaks(f, pos + UP * 5, { inward = 36, count = 30, life = 0.8, size = 1.1, color = PAL.Core, color2 = PAL.Guard })
			Fx2.shake(0.25 + i * 0.2, 0.3, pos)
		end)
	end
	sound(SND.Hum, pos, 1, 0.6)
	sound(SND.Rise, pos, 1, 0.75)
	sound(SND.Thunder, pos, 0.9, 0.9)
	if isMe(d.userId) then
		FaceCam.start(gather) -- (held still; the camera pans in to his face)
		letterbox(true, 0.4)
		-- (no FOV squeeze under the close-up: the face beat frames the shot itself)
		Fx2.envelope({ fov = FaceCam.active() and 0 or -13, tint = PAL.Guard, bright = -0.16, contrast = 0.15, attack = gather * 0.95, release = 0.08 })
		Fx2.shake(0.45, gather, pos)
	end
end

function handlers.GuardianBurst(d)
	local PAL = Perks.pal(d.userId)
	local pos, radius = d.pos, d.radius
	local g, n = groundAt(pos)
	local f = castFolder("SummonBurst", 4)
	-- the bolt that tears down from the sky and into the caster
	local sky = neon("SkyBolt", Enum.PartType.Cylinder, PAL.Guard, f)
	sky.Size = Vector3.new(700, 18, 18)
	sky.CFrame = CFrame.new(g + UP * 350) * VERT
	sky.Transparency = 0.05
	Fx2.tween(sky, 1.3, { Size = Vector3.new(700, 100, 100), Transparency = 1 }, Enum.EasingStyle.Quart)
	local white = neon("SkyBoltCore", Enum.PartType.Cylinder, PAL.Core, f)
	white.Size = Vector3.new(700, 9, 9)
	white.CFrame = CFrame.new(g + UP * 350) * VERT
	Fx2.tween(white, 0.9, { Size = Vector3.new(700, 38, 38), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(sky, 1.4)
	Debris:AddItem(white, 1.0)
	FX.shell(f, pos + UP * 4, 4, radius, PAL.Guard, 0.9, Enum.Material.ForceField)
	FX.shell(f, pos + UP * 4, 3, radius * 0.6, PAL.Core, 0.5)
	FX.glow(f, pos + UP * 8, radius * 0.8, PAL.Guard, 0.6)
	FX.light(f, pos + UP * 8, PAL.Guard, 14, 60, 1.2)
	for i = 0, 2 do
		task.delay(i * 0.09, function()
			FX.ring(f, g + UP * 0.4, UP, 6, radius * (1.7 + i * 0.35), i == 1 and PAL.Core or PAL.Guard, 0.85)
		end)
	end
	Fx2.shockwave(f, g + UP * 0.5, UP, 8, radius * 2.8, PAL.Guard, 1.0)
	FX.streaks(f, pos + UP * 6, { count = 120, speed = { 80, 210 }, color = PAL.Core, color2 = PAL.Guard, size = 1.6, life = 0.65 })
	FX.sparks(f, pos + UP * 6, { color = PAL.Guard, color2 = PAL.Core, count = 100, speed = { 20, 80 }, size = 1.0 })
	-- forks radiate out along the ground
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2 + math.random() * 0.3
		local reach = radius * (0.6 + math.random() * 0.6)
		FX.bolt(f, pos + UP * 2, g + Vector3.new(math.cos(a) * reach, 0.5, math.sin(a) * reach), { color = PAL.Guard, core = PAL.Core, width = 0.3, segments = 9, jag = 1.2, life = 0.2, restrike = 2 })
	end
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		Fx2.dust(f, g + Vector3.new(math.cos(a), 0, math.sin(a)) * 13, 9, 7)
	end
	Fx2.cracks(Folder, g, n, radius * 0.5, PAL.Guard, 9)
	sound(SND.Thunder, pos, 1, 0.7)
	sound(SND.Boom, pos, 1, 0.55)
	sound(SND.HitHeavy, pos, 1, 0.5)
	Fx2.shake(4.2, 1.3, pos, 260)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.Guard, lineColor = PAL.GuardBone, flashAlpha = 0.35 })
		FX.speedLines(0.9)
		FaceCam.burst()
		local close = FaceCam.active() -- (no FOV punch, and little blur, while the camera is on his face)
		Fx2.envelope({ fov = close and 0 or 18, blur = close and 2 or 6, tint = PAL.Guard, contrast = 0.2, bright = 0.12, attack = 0.04, hold = 0.15, release = 0.9 })
		showTitle("Guardian")
		guardCamera(true, CFG.Guardian.RiseTime or d.time)
		task.delay(1.8, function()
			letterbox(false, 0.5)
		end)
	end
end

-- the guardian takes shape from the ground up: the skeleton first, then the armour, then helm, weapons and mantle,
-- the gold eyes lighting last (the caster is lifted into its chest meanwhile, so it rises out of the ground)
function handlers.GuardianOn(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local f = castFolder("GuardianOn", 3)
	local pos = d.pos + UP * 8
	FX.glow(f, pos, 34, PAL.Guard, 0.5)
	FX.ring(f, groundAt(d.pos) + UP * 0.3, UP, 6, 80, PAL.Guard, 0.8)
	sound(SND.HitHeavy, d.pos, 1, 0.55)
	Fx2.shake(2.2, 0.7, d.pos)
	task.spawn(function()
		local model
		for _ = 1, 40 do
			model = char and char:FindFirstChild("GuardianConstruct")
			if model then
				break
			end
			task.wait(0.05)
		end
		if not model then
			return
		end
		rememberBase(model)
		local list, lo, hi = {}, math.huge, -math.huge
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and (baseT[p] or 1) < 0.99 then
				local y = p.Position.Y
				lo, hi = math.min(lo, y), math.max(hi, y)
				table.insert(list, { p = p, y = y, stage = math.clamp(p:GetAttribute("Stage") or 2, 1, 3) })
				p.Transparency = 1
			end
		end
		local windows = { { 0, 0.5 }, { 0.3, 0.8 }, { 0.6, 0.95 } }
		local T, t0 = math.max(d.reveal or 1, 0.2), os.clock()
		local flared, lit = false, false
		while model.Parent and model.Name == "GuardianConstruct" do
			local el = (os.clock() - t0) / T
			for _, e in ipairs(list) do
				if e.p.Parent and not drawHidden[e.p] then
					local w = windows[e.stage]
					local half = (w[2] - w[1]) * 0.5
					local h = (e.y - lo) / math.max(hi - lo, 1) -- bottom first within each stage
					local a = math.clamp((el - w[1] - h * half) / half, 0, 1)
					e.p.Transparency = 1 - (1 - baseT[e.p]) * a
				end
			end
			if el > 0.3 and not flared then
				flared = true
				FX.arcs(f, d.pos + UP * 12, 11, { count = 6, colors = { PAL.Guard, PAL.Core }, width = 0.24, life = 0.15 })
				FX.streaks(f, pos + UP * 6, { color = PAL.Core, color2 = PAL.Guard, speed = { 40, 90 }, count = 40, size = 0.9 })
			end
			if el > 0.9 and not lit then
				lit = true
				local face = model:FindFirstChild("Face")
				if face then
					FX.glow(f, face.Position - face.CFrame.LookVector * -2.6, 9, PAL.GuardEye, 0.35)
					sound(SND.Zap, face.Position, 0.8, 0.7)
				end
			end
			if el >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		-- every part exactly as built (except what a drawn bow is hiding)
		if model.Parent and model.Name == "GuardianConstruct" then
			for _, e in ipairs(list) do
				if e.p.Parent and not drawHidden[e.p] then
					e.p.Transparency = baseT[e.p]
				end
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- the arrow: a bow of light forms in the guardian's left hand, the string is drawn, the arrow loosed
function handlers.ArrowCharge(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local a = { char = char, bow = makeDraw(PAL), pal = PAL, t0 = os.clock(), time = d.time, isLocal = isMe(d.userId), nextFx = 0, nextArc = 0, hidden = {} }
	arrows[d.id] = a
	local model = char:FindFirstChild("GuardianConstruct")
	if model then
		rememberBase(model)
		-- the right hand lets the sword go to draw the string; the bow's resting string is replaced by the drawn one
		for _, p in ipairs(model:GetChildren()) do
			if p:IsA("BasePart") and SWORD[p.Name] then
				a.hidden[p] = true
				drawHidden[p] = true
				p.Transparency = 1
			end
		end
	end
	local g = guards[char]
	if g then
		g.draw = { id = d.id, t0 = os.clock(), time = d.time }
		g.loose = nil
	end
	local hand = bowPoint(char)
	sound(SND.Rise, hand, 1, 1.1)
	sound(SND.Hum, hand, 0.9, 0.9)
	if a.isLocal then
		showTitle("Arrow")
		rootUntil = os.clock() + d.time + 0.5
		-- the guardian turns to the cursor while it draws (the server looses along this facing)
		local _, _, hrp = myChar()
		if hrp then
			faceUntil, faceDirV = os.clock() + d.time + 0.1, flat(cursorTarget() - hrp.Position, hrp.CFrame.LookVector)
		end
		Fx2.envelope({ fov = -6, tint = PAL.Guard, bright = -0.05, contrast = 0.1, attack = d.time * 0.9, release = 0.15 })
		Fx2.shake(0.5, d.time, hand)
		task.delay(math.max(d.time - 0.08, 0), function()
			Request:FireServer("ArrowAim", { id = d.id, target = cursorTarget() })
		end)
	end
	task.delay(d.time + 3, function()
		if arrows[d.id] == a then
			endBow(d.id)
		end
	end)
end

function handlers.ArrowCancel(d)
	endBow(d.id)
end

function handlers.ArrowFire(d)
	local PAL = Perks.pal(d.userId)
	local origin, dir, length, speed = d.origin, d.dir, d.length, d.speed
	local pending = arrows[d.id]
	-- the shot leaves this client's own view of the bow; the server's line keeps its far end
	if pending and typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
		local grip = guardPart(pending.char, "BowGrip")
		if grip and (grip.Position - origin).Magnitude < 25 then
			local finish = origin + dir * length
			local span = finish - grip.Position
			if span.Magnitude > 2 then
				origin, dir, length = grip.Position, span.Unit, span.Magnitude
			end
		end
	end
	endBow(d.id, 0.6)
	local f = castFolder("Arrow", length / speed + 2.5)
	-- the release
	FX.streaks(f, origin, { dir = dir, spread = 26, speed = { 100, 260 }, count = 80, color = PAL.Core, color2 = PAL.Guard, size = 1.7 })
	Fx2.shockwave(f, origin, dir, 6, 64, PAL.Core, 0.45)
	FX.glow(f, origin, 70, PAL.Guard, 0.5)
	FX.sparks(f, origin, { color = PAL.Guard, color2 = PAL.Core, count = 60, speed = { 30, 100 }, size = 1.0 })
	sound(SND.Thunder, origin, 1, 1.0)
	sound(SND.Whoosh, origin, 1, 0.6)
	sound(SND.Boom, origin, 0.9, 0.8)
	Fx2.shake(2.6, 0.5, origin)
	if isMe(d.userId) then
		FX.speedLines(0.7)
		Fx2.envelope({ fov = 16, blur = 7, tint = PAL.Guard, attack = 0.03, release = 0.5 })
		rootUntil = os.clock() + 0.3
	end
	-- the arrow itself: a fat bar of light with a white head, trailing 70 studs, racing along the line
	local shaft = neon("ArrowFlight", Enum.PartType.Block, PAL.Guard, f)
	local core = neon("ArrowFlightCore", Enum.PartType.Block, PAL.Core, f)
	local head = neon("ArrowFlightHead", Enum.PartType.Ball, PAL.Core, f)
	head.Size = Vector3.one * 9
	local hl = Instance.new("PointLight")
	hl.Color, hl.Range, hl.Brightness, hl.Shadows = PAL.Guard, 60, 8, false
	hl.Parent = head
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		local headD = math.min(speed * el, length)
		local tailD = math.max(headD - 70, 0)
		local a0, b0 = origin + dir * tailD, origin + dir * headD
		seg(shaft, a0, b0, 4.6)
		seg(core, a0, b0, 1.9)
		head.CFrame = CFrame.new(b0)
		if math.random() < 0.7 then
			FX.arcs(f, b0, 8, { count = 1, colors = { PAL.Guard, PAL.Core }, width = 0.22, life = 0.1 })
		end
		if headD >= length or not f.Parent then
			conn:Disconnect()
			for _, p in ipairs({ shaft, core, head }) do
				Fx2.tween(p, 0.35, { Transparency = 1 })
			end
		end
	end)
	-- rings and forks left along the line, each appearing as the head passes
	local side = dir:Cross(UP)
	side = side.Magnitude > 0.1 and side.Unit or Vector3.xAxis
	for dist = 8, length, 14 do
		task.delay(dist / speed, function()
			local at = origin + dir * dist
			Fx2.shockwave(f, at, dir, 5, 30, PAL.Guard, 0.55)
			local off = (side * (math.random() - 0.5) * 2 + UP * (math.random() - 0.3)).Unit * (6 + math.random() * 8)
			FX.bolt(f, at, at + off, { color = PAL.Guard, core = PAL.Core, width = 0.25, segments = 6, jag = 1.0, life = 0.18, restrike = 1 })
		end)
	end
	-- the line of light lingers and burns out
	task.delay(length / speed, function()
		local finish = origin + dir * length
		local beam = neon("ArrowBeam", Enum.PartType.Block, PAL.Guard, f)
		local bcore = neon("ArrowBeamCore", Enum.PartType.Block, PAL.Core, f)
		seg(beam, origin, finish, 6)
		seg(bcore, origin, finish, 2.4)
		Fx2.tween(beam, 0.9, { Size = Vector3.new(0.4, 0.4, length), Transparency = 1 })
		Fx2.tween(bcore, 0.6, { Size = Vector3.new(0.2, 0.2, length), Transparency = 1 })
	end)
end

function handlers.ArrowHit(d)
	local PAL = Perks.pal(d.userId)
	local pos, radius = d.pos, d.radius
	local f = castFolder("ArrowHit", 4)
	local g, nrm = groundAt(pos)
	-- a column of lightning stabs down through the point of impact
	local col = neon("StrikeColumn", Enum.PartType.Cylinder, PAL.Guard, f)
	col.Size = Vector3.new(700, 12, 12)
	col.CFrame = CFrame.new(pos + UP * 340) * VERT
	col.Transparency = 0.05
	Fx2.tween(col, 1.2, { Size = Vector3.new(700, 64, 64), Transparency = 1 }, Enum.EasingStyle.Quart)
	local wcol = neon("StrikeColumnCore", Enum.PartType.Cylinder, PAL.Core, f)
	wcol.Size = Vector3.new(700, 5, 5)
	wcol.CFrame = CFrame.new(pos + UP * 340) * VERT
	Fx2.tween(wcol, 0.8, { Size = Vector3.new(700, 24, 24), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(col, 1.3)
	Debris:AddItem(wcol, 0.9)
	FX.shell(f, pos + UP * 3, 3, radius * 0.7, PAL.Core, 0.5)
	FX.shell(f, pos + UP * 3, 2, radius * 1.5, PAL.Guard, 0.9, Enum.Material.ForceField)
	FX.shell(f, pos + UP * 3, 2, radius * 2.1, PAL.GuardDeep, 1.3, Enum.Material.ForceField)
	FX.glow(f, pos + UP * 5, radius * 2.4, PAL.Guard, 0.6)
	FX.light(f, pos + UP * 8, PAL.Guard, 16, 60, 1.4)
	for i = 0, 3 do
		task.delay(i * 0.07, function()
			FX.ring(f, g + UP * 0.5, UP, 8, radius * (1.5 + i * 0.5), i % 2 == 0 and PAL.Core or PAL.Guard, 0.9)
		end)
	end
	Fx2.shockwave(f, g + UP * 0.6, UP, 10, radius * 3.2, PAL.Guard, 1.1)
	-- forks burst out in every direction, and strikes rain down around the crater
	for i = 1, 18 do
		local a = (i / 18) * math.pi * 2 + math.random() * 0.3
		local reach = radius * (0.7 + math.random() * 0.7)
		FX.bolt(f, pos + UP * 2, g + Vector3.new(math.cos(a) * reach, 0.5, math.sin(a) * reach), { color = PAL.Guard, core = PAL.Core, width = 0.35, segments = 10, jag = 1.3, life = 0.22, restrike = 2 })
	end
	for i = 1, 8 do
		local a = math.random() * math.pi * 2
		local r = radius * (0.4 + math.random() * 0.8)
		local at = g + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		task.delay(0.1 + i * 0.07, function()
			FX.bolt(f, at + UP * 120, at, { color = PAL.Guard, core = PAL.Core, width = 0.4, segments = 10, jag = 1.5, life = 0.14, restrike = 1 })
			FX.glow(f, at + UP, 18, PAL.Guard, 0.3)
		end)
	end
	FX.streaks(f, pos + UP * 3, { count = 140, speed = { 90, 250 }, color = PAL.Core, color2 = PAL.Guard, size = 1.9, life = 0.7 })
	FX.sparks(f, pos + UP * 3, { color = PAL.Guard, color2 = PAL.Core, count = 130, speed = { 30, 110 }, size = 1.2 })
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		Fx2.dust(f, g + Vector3.new(math.cos(a), 0, math.sin(a)) * (radius * 0.4), 11, 7)
	end
	Fx2.cracks(Folder, g, nrm, 22, PAL.Guard, 10)
	sound(SND.Thunder, pos, 1, 0.6)
	sound(SND.Boom, pos, 1, 0.45)
	sound(SND.HitHeavy, pos, 1, 0.4)
	Fx2.shake(5.5, 1.5, pos, 340)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.Guard, lineColor = PAL.Blade, flashAlpha = 0.3 })
		FX.speedLines(0.7)
		Fx2.envelope({ fov = 14, blur = 6, tint = PAL.Guard, contrast = 0.2, bright = 0.12, attack = 0.03, hold = 0.1, release = 0.9 })
	end
end

function handlers.Hits(d)
	Feedback.hits(d, Color3.fromRGB(190, 150, 255))
end

function handlers.GuardianEnd(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	if typeof(d.pos) == "Vector3" then
		local f = castFolder("GuardianEnd", 3)
		FX.glow(f, d.pos + UP * 10, 30, PAL.Guard, 0.5)
		FX.sparks(f, d.pos + UP * 10, { color = PAL.Guard, color2 = PAL.Core, count = 50, speed = { 10, 35 }, size = 0.8 })
		sound(SND.Rise, d.pos, 0.8, 0.6)
	end
	local g = char and guards[char]
	if g then
		g.ending = os.clock()
	end
	-- the guardian dissolves from the top down; the server removes it after d.fade
	local model = char and (char:FindFirstChild("GuardianConstruct_Fading") or char:FindFirstChild("GuardianConstruct"))
	if model then
		local fade = math.max((tonumber(d.fade) or 0.6) - 0.05, 0.1)
		local list, lo, hi = {}, math.huge, -math.huge
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Transparency < 1 then
					table.insert(list, p)
					lo, hi = math.min(lo, p.Position.Y), math.max(hi, p.Position.Y)
				end
			elseif p:IsA("ParticleEmitter") or p:IsA("Trail") or p:IsA("Light") then
				p.Enabled = false
			end
		end
		for _, p in ipairs(list) do
			local h = 1 - (p.Position.Y - lo) / math.max(hi - lo, 1)
			task.delay(h * fade * 0.4, function()
				if p.Parent then
					Fx2.tween(p, fade * 0.6, { Transparency = 1 })
				end
			end)
		end
	end
	if isMe(d.userId) then
		FaceCam.out(0.35, true) -- (an end during the face beat lets the body and the camera go)
		guardCamera(false, 0.5)
		letterbox(false, 0.3) -- (an end during the gather never reached the burst's own letterbox-off)
	end
end

function handlers.SlashStart(d)
	local char = charOf(d.userId)
	local g = char and guards[char]
	if g then
		g.slash = { side = d.side or 1, t0 = os.clock(), windup = d.windup or 0.2 }
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		sound(SND.Whoosh, hrp.Position, 1, 0.55)
		if isMe(d.userId) then
			faceDir(hrp, d.dir)
		end
	end
end

-- the blade slash: a crescent of light sweeping across the swing, then racing outward, and the ground split open
function handlers.Slash(d)
	local PAL = Perks.pal(d.userId)
	local origin, dir, side = d.origin, d.dir, d.side or 1
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return
	end
	local f = castFolder("Slash", 3)
	-- the crescent comes off the guardian's sword shoulder, tilted along the cut (high on its right, low on its left)
	local pivot = typeof(d.pivot) == "Vector3" and d.pivot or origin + UP * 6
	local base = CFrame.lookAt(pivot, pivot + dir) * CFrame.Angles(R(-8), 0, R(24))
	local half = R(d.arc / 2)
	local n = 28
	local radius = d.range * (typeof(d.pivot) == "Vector3" and 0.7 or 0.45)
	local segs = {}
	for layer = 1, 2 do
		for i = 1, n do
			local k = (i - 1) / (n - 1)
			local mid = 1 - math.abs(k - 0.5) * 2 -- thickest in the middle of the arc
			local seg = Fx2.part("SlashArc", Enum.PartType.Block, Enum.Material.Neon, layer == 1 and PAL.Core or PAL.Blade, f)
			seg.Transparency = 1
			table.insert(segs, { part = seg, k = k, mid = mid, layer = layer })
		end
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 0.5 or not f.Parent then
			conn:Disconnect()
			return
		end
		local reveal = math.clamp(t / 0.1, 0, 1) -- sweeps across in a tenth of a second
		local grow = radius + math.max(t - 0.08, 0) * 90 -- then races outward
		local fade = math.clamp((t - 0.12) / 0.38, 0, 1)
		for _, s in ipairs(segs) do
			local kk = side > 0 and s.k or 1 - s.k
			if kk <= reveal then
				local a = -half + s.k * 2 * half
				local r = grow * (s.layer == 1 and 1 or 1.04)
				local p = (base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)).Position
				-- each piece lies ALONG the arc (it used to be turned 90 degrees, which drew a dotted line of radial dashes),
				-- a flat band wide in the radial direction
				local thick = (s.layer == 1 and 1.2 or 3.0) * (0.25 + 0.75 * s.mid) * (1 - fade * 0.6)
				s.part.Size = Vector3.new(r * 2 * half / n * 1.15, s.layer == 1 and 0.35 or 0.6, thick)
				s.part.CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
				s.part.Transparency = (s.layer == 1 and 0.05 or 0.35) + fade * 0.95
			end
		end
	end)
	FX.streaks(f, pivot + dir * radius, { color = PAL.Core, color2 = PAL.Blade, dir = dir, spread = d.arc / 2, speed = { 80, 150 }, count = 45, size = 0.8 })
	FX.glow(f, pivot + dir * radius * 0.6, 30, PAL.Blade, 0.35)
	-- the fissure: a glowing split in the ground along the swing, cracks and dust down its length
	local start = origin + dir * 6
	local finish = origin + dir * d.fissure
	local gs = groundAt(start)
	local ge = groundAt(finish)
	local fissure = Fx2.part("Fissure", Enum.PartType.Block, Enum.Material.Neon, PAL.Blade, f)
	fissure.Size = Vector3.new(1.4, 0.2, (ge - gs).Magnitude)
	fissure.CFrame = CFrame.lookAt((gs + ge) / 2 + UP * 0.15, ge + UP * 0.15)
	Fx2.tween(fissure, 1.4, { Size = Vector3.new(0.1, 0.2, (ge - gs).Magnitude), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for dist = 6, d.fissure, 6 do
		local g, nrm = groundAt(origin + dir * dist)
		Fx2.cracks(Folder, g, nrm, 3.5, PAL.Blade, 5)
		Fx2.dust(f, g, 4, 3)
	end
	sound(SND.HitHeavy, origin + dir * 12, 1, 0.7)
	sound(SND.Boom, origin + dir * 18, 0.8, 1.2)
	Fx2.shake(1.6, 0.45, origin)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.Guard, lineColor = PAL.Blade, flashAlpha = 0.3 })
		Fx2.envelope({ fov = 7, attack = 0.03, release = 0.3 })
	end
end

function handlers.ShieldHit(d)
	local PAL = Perks.pal(d.userId)
	if typeof(d.pos) == "Vector3" then
		local f = castFolder("Shield", 2)
		FX.sparks(f, d.pos, { color = PAL.Guard, color2 = PAL.Core, count = 10, speed = { 10, 25 } })
		FX.arcs(f, d.pos, 2.5, { count = 2, colors = { PAL.Guard, PAL.Core }, width = 0.12 })
	end
end

-- X pressed while the entrance is still playing: the release chip flashes red
function handlers.ReleaseDenied(d)
	releaseStroke.Color = PAL.EyeRight
	task.delay(0.35, function()
		releaseStroke.Color = CFG.Callouts.Guardian.c0
	end)
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[TempestClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- the guardian: idle breathing and sway, the mantle flaring with speed, the two-step blade swing and the archer's draw
-- (Motor6D.Transform, local to every client), the caster floating in its chest, the force-shield dome round its base
-- and a clean outline round the whole silhouette. The poses were solved by FK on a preview build of the construct.
local function A(x, y, z)
	return CFrame.Angles(R(x), R(y), R(z))
end
local GPOSE = {
	draw = { GuardBody = A(0, -38, 0), GuardLeftArm = A(51.4, -17.8, -36), GuardLeftElbow = A(-66, 0, 0), GuardBowGrip = A(-3.4, -61.2, 26.8), GuardRightArm = A(157.5, 0, -79.4), GuardRightElbow = A(-61.9, 0, 0) },
	high = { GuardBody = A(0, -25, 0), GuardRightArm = A(81.7, -17.6, 24.3), GuardRightElbow = A(36.3, 0, 0) },
	mid = { GuardBody = CFrame.identity, GuardRightArm = A(101.1, 73.7, -29.1), GuardRightElbow = A(-68, 0, 0) },
	low = { GuardBody = A(0, 28, 0), GuardRightArm = A(12.8, -38.8, -45), GuardRightElbow = A(-68, 0, 0) },
}
local FLOAT = { length = 3600, fadeIn = 0.5, fadeOut = 0.01, keys = { { t = 0, pose = {
	LeftHip = { 14, 0, -4 }, RightHip = { 4, 0, 4 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -14, 0, 0 },
	LeftShoulder = { 8, 0, -12 }, RightShoulder = { 8, 0, 12 }, LeftElbow = { 18, 0, 0 }, RightElbow = { 18, 0, 0 },
} } } }
local GUARD_FAR = 420 -- other players' guardians farther than this from the camera hold still (no joint writes)

local function smoothstep(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function blend(p, target, w)
	if w > 0 then
		for name, cf in pairs(target) do
			p[name] = (p[name] or CFrame.identity):Lerp(cf, math.min(w, 1))
		end
	end
end

local function registerGuard(char, model)
	local PAL = Perks.palOfChar(char)
	local joints = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") then
			joints[m.Name] = m
		end
	end
	rememberBase(model)
	-- the force shield: a faint dome round the guardian's base (it shoves anything that steps inside back out)
	local shield = Fx2.part("ShieldDome", Enum.PartType.Ball, Enum.Material.ForceField, PAL.Guard, Folder)
	shield.Size = Vector3.one * CFG.Guardian.ShieldRadius * 2
	shield.Transparency = 0.5
	local outline = Instance.new("Highlight")
	outline.Name = "GuardianOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = PAL.Guard:Lerp(PAL.GuardBone, 0.55)
	outline.OutlineTransparency = 0.15
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Adornee = model
	outline.Parent = Folder
	local blade = model:FindFirstChild("Blade")
	guards[char] = {
		model = model, joints = joints, t = 0, speed = 0, shield = shield, outline = outline, nextArc = 0, pal = PAL,
		trail = blade and blade:FindFirstChild("SlashTrail"),
	}
end

local function dropGuard(char)
	local g = guards[char]
	if g then
		guards[char] = nil
		for _, o in ipairs({ g.shield, g.outline }) do
			if o then
				o:Destroy()
			end
		end
		if g.float then
			g.float:stop(0.3)
		end
		if g.trail and g.trail.Parent then
			g.trail.Enabled = false
		end
	end
end

local function animateGuard(char, g, dt)
	g.t += dt
	local t, clock = g.t, os.clock()
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local speed = hrp and (hrp.AssemblyLinearVelocity * FLAT).Magnitude or 0
	g.speed += (math.min(speed, 24) - g.speed) * math.min(dt * 4, 1)
	local sp = g.speed
	local p = {
		GuardBody = CFrame.new(0, math.sin(t * 1.4) * 0.3, 0) * CFrame.Angles(math.sin(t * 1.4) * 0.015 - sp * 0.004, 0, 0),
		GuardHead = CFrame.Angles(math.sin(t * 0.9) * 0.04, math.sin(t * 0.55) * 0.08, 0),
		GuardRightArm = CFrame.Angles(math.sin(t * 1.2) * 0.05 - sp * 0.006, 0, 0),
		GuardLeftArm = CFrame.Angles(math.sin(t * 1.2 + 1) * 0.05 - sp * 0.006, 0, 0),
		GuardRightElbow = CFrame.identity,
		GuardLeftElbow = CFrame.identity,
		GuardBowGrip = CFrame.identity,
		-- the mantle streams back as it moves
		GuardMantle = CFrame.Angles(-R(2 + sp * 0.9) + math.sin(t * 1.7) * 0.03, 0, math.sin(t * 0.8) * 0.02),
	}
	-- the blade: wind up, cut through the middle, hold, settle (the forehand ends low-left, the backhand high-right)
	local trailOn = false
	if g.slash then
		local e = clock - g.slash.t0
		local w = g.slash.windup
		local from, to = GPOSE.high, GPOSE.low
		if g.slash.side < 0 then
			from, to = GPOSE.low, GPOSE.high
		end
		if e < w then
			blend(p, from, smoothstep(e / w))
		elseif e < w + 0.07 then
			blend(p, from, 1)
			blend(p, GPOSE.mid, (e - w) / 0.07)
		elseif e < w + 0.14 then
			blend(p, GPOSE.mid, 1)
			blend(p, to, (e - w - 0.07) / 0.07)
		elseif e < w + 0.55 then
			blend(p, to, 1 - smoothstep((e - w - 0.24) / 0.31))
		else
			g.slash = nil
		end
		trailOn = e > w - 0.03 and e < w + 0.2
	end
	if g.trail and g.trail.Enabled ~= trailOn then
		g.trail.Enabled = trailOn
	end
	-- the bow: side-on, bow arm out, string to the cheek; after the shot the arms come back down
	if g.draw then
		blend(p, GPOSE.draw, smoothstep((clock - g.draw.t0) / 0.3))
	elseif g.loose then
		local e = clock - g.loose.t0
		if e < 0.5 then
			blend(p, GPOSE.draw, 1 - smoothstep((e - 0.08) / 0.42))
		else
			g.loose = nil
		end
	end
	for name, cf in pairs(p) do
		local j = g.joints[name]
		if j then
			j.Transform = cf
		end
	end
	-- the shield dome sits on the ground round the guardian's base, breathing, with arcs crawling over it now and then
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and g.shield then
		local r = CFG.Guardian.ShieldRadius * (1 + math.sin(t * 3) * 0.02)
		local ground = hrp.Position - UP * (hum.HipHeight + hrp.Size.Y / 2)
		g.shield.Size = Vector3.one * r * 2
		g.shield.CFrame = CFrame.new(ground) * CFrame.Angles(0, t * 0.6, 0)
		if clock >= g.nextArc then
			g.nextArc = clock + 0.3 + math.random() * 0.4
			local gp = g.pal or PAL
			FX.arcs(Folder, ground + UP * 4, r * 0.9, { count = 1, colors = { gp.Guard, gp.Core }, width = 0.14, life = 0.12 })
		end
	end
end

RunService.Stepped:Connect(function(_, dt)
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local model = char and char:GetAttribute("Guardian") and char:FindFirstChild("GuardianConstruct")
		if model and (not guards[char] or guards[char].model ~= model) then
			dropGuard(char)
			registerGuard(char, model)
		end
	end
	local camPos = workspace.CurrentCamera.CFrame.Position
	local clock = os.clock()
	for char, g in pairs(guards) do
		if not g.model.Parent or not char.Parent then
			dropGuard(char)
		else
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local near = char == player.Character or (hrp ~= nil and (hrp.Position - camPos).Magnitude < GUARD_FAR)
			if near then
				local ok, err = pcall(animateGuard, char, g, dt)
				if not ok then
					warn("[TempestClient] guardian anim: " .. tostring(err))
					dropGuard(char)
				end
			end
			if guards[char] == g then
				-- the caster floats in its chest (a one-shot pose from another move wins while it plays)
				local floatWanted = near and not g.ending
				if floatWanted and (not g.float or not g.float:isPlaying()) and clock >= (poseUntil[char] or 0) then
					g.float = Animator.play(char, FLOAT)
				elseif not floatWanted and g.float then
					g.float:stop(0.3)
					g.float = nil
				end
				local shieldT = (near and not g.ending) and 0.5 or 1
				if g.shield.Transparency ~= shieldT then
					g.shield.Transparency = shieldT
				end
				if g.ending and g.outline.OutlineTransparency < 1 then
					g.outline.OutlineTransparency = math.min(g.outline.OutlineTransparency + dt * 2.5, 1)
				end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- eye mode on this client: outlines on every enemy within SenseRadius, and motion blur that rises with speed
local outlines = {}
local nextSense = 0
local motionBlur
local function updateEyes(char, hrp)
	local active = char and char:GetAttribute("EyeMode") == true
	-- motion blur
	if active then
		if not motionBlur or motionBlur.Parent ~= workspace.CurrentCamera then
			motionBlur = Instance.new("BlurEffect")
			motionBlur.Name = "TempestMotionBlur"
			motionBlur.Size = 0
			motionBlur.Parent = workspace.CurrentCamera
		end
		local speed = (hrp.AssemblyLinearVelocity * FLAT).Magnitude
		motionBlur.Size = motionBlur.Size + (math.clamp((speed - 8) / 18, 0, 1) * 7 - motionBlur.Size) * 0.2
	elseif motionBlur then
		motionBlur:Destroy()
		motionBlur = nil
	end
	if os.clock() < nextSense then
		return
	end
	nextSense = os.clock() + 0.2
	local want = {}
	if active then
		local near = {}
		local list = CollectionService:GetTagged(CFG.TargetTag)
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl ~= player and pl.Character then
				table.insert(list, pl.Character)
			end
		end
		for _, m in ipairs(list) do
			local r = m:FindFirstChild("HumanoidRootPart")
			if r and m.Parent then
				local d = (r.Position - hrp.Position).Magnitude
				if d <= CFG.Eyes.SenseRadius then
					table.insert(near, { m = m, d = d })
				end
			end
		end
		table.sort(near, function(a, b)
			return a.d < b.d
		end)
		for i = 1, math.min(#near, 25) do
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
			local myPal = Perks.pal(player.UserId)
			h.FillColor = myPal.EyeRight
			h.FillTransparency = 0.85
			h.OutlineColor = myPal.EyeTrail
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = Folder
			outlines[m] = h
		end
	end
end

---------------------------------------------------------------------------------------------------
-- per frame: hand lightning, stunned bodies crackling, the local body, HUD
local savedWalk
local function frame(dt)
	local clock = os.clock()
	-- lightning crawling off every charged hand
	for _, l in pairs(lances) do
		local PAL = l.pal or PAL
		if l.hand and l.hand.Parent and clock >= l.nextBolt then
			l.nextBolt = clock + 0.03
			local p = l.att.WorldPosition
			local reach = 1.5 + math.random() * 3.5
			local dirv = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			if dirv.Magnitude > 1e-3 then
				FX.bolt(Folder, p, p + dirv.Unit * reach, { color = PAL.Bolt, core = PAL.Core, width = 0.1, segments = 4, jag = 0.4, life = 0.08, restrike = 1 })
			end
			if math.random() < 0.15 then
				local g = groundAt(p)
				FX.bolt(Folder, p, g + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)), { color = PAL.Bolt, core = PAL.Core, width = 0.08, segments = 6, jag = 0.3, life = 0.08 })
			end
		end
	end
	for id, a in pairs(arrows) do
		local PAL = a.pal or PAL
		local c = a.char
		local hrp0 = c.Parent and c:FindFirstChild("HumanoidRootPart")
		if not hrp0 then
			endBow(id)
		else
			local el = clock - a.t0
			-- the drawn string follows the right gauntlet in as the draw pose settles (the same 0.3 s blend)
			local tip = a.bow:update(c, smoothstep((el - 0.02) / 0.3))
			if a.isLocal and clock < faceUntil then
				faceDirV = flat(cursorTarget() - hrp0.Position, faceDirV) -- keeps turning to the cursor while it draws
			end
			if tip then
				if clock >= a.nextFx then
					a.nextFx = clock + 0.13
					FX.streaks(Folder, tip, { inward = 9, count = 8, life = 0.4, size = 0.9, color = PAL.Core, color2 = PAL.Guard })
				end
				if clock >= a.nextArc then
					a.nextArc = clock + 0.05
					FX.arcs(Folder, tip, 3 + el * 3, { count = 1, colors = { PAL.Guard, PAL.Core }, width = 0.16, life = 0.1 })
				end
			end
		end
	end
	-- bodies caught in the pulse crackle until the stun ends
	for m, st in pairs(stunned) do
		local PAL = st.pal or PAL
		local r = m.Parent and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart"))
		if not r or clock >= st.untilT then
			stunned[m] = nil
		elseif clock >= st.nextArc then
			st.nextArc = clock + 0.08
			FX.arcs(Folder, r.Position, 2.6, { count = 2, colors = { PAL.Pulse, PAL.Core, PAL.PulseDeep }, width = 0.1, life = 0.1 })
		end
	end

	local char, hum, hrp = myChar()
	if hum then
		-- rotation locked toward the aim during the lance wind-up and dash (and held through the Susanoo face beat)
		if FaceCam.frozen() then
			hum.AutoRotate = false
		elseif clock < faceUntil and faceDirV then
			hum.AutoRotate = false
			faceDir(hrp, faceDirV)
		elseif not dash and not hum.AutoRotate then
			hum.AutoRotate = true
		end
		-- held still by a wind-up or a stun; otherwise the server's walk speed
		local held = clock < rootUntil or clock < stunUntil or FaceCam.frozen()
		if held then
			savedWalk = savedWalk or (char:GetAttribute("KitWalkSpeed") or hum.WalkSpeed)
			hum.WalkSpeed = 0
		elseif savedWalk then
			hum.WalkSpeed = char:GetAttribute("KitWalkSpeed") or savedWalk
			savedWalk = nil
		elseif equipped() and char:GetAttribute("KitWalkSpeed") and hum.WalkSpeed ~= char:GetAttribute("KitWalkSpeed") then
			hum.WalkSpeed = char:GetAttribute("KitWalkSpeed")
		end
		if tumbleUntil > 0 and clock >= tumbleUntil then
			tumbleUntil = 0
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		updateEyes(char, hrp)
	end

	-- the camera is given back even if the guardian went without a GuardianEnd (death, a kit switch, a lost event)
	if camSaved and os.clock() > camGrace and not iHaveGuardian() then
		guardCamera(false, 0.3)
	end

	-- HUD
	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local guarding = iHaveGuardian()
	punchName.Text = guarding and (CFG.Labels.Slash or "SLASH") or "PUNCH"
	punchGrad.Color = guarding and ColorSequence.new(Perks.pal(player.UserId).Core, Perks.pal(player.UserId).Guard) or ColorSequence.new(Color3.fromRGB(255, 240, 230), Color3.fromRGB(255, 180, 90))
	guardName.Text = guarding and CFG.Labels.Arrow or CFG.Labels.Guardian
	-- (2026-11-11 keybinds) subForm reads "G AGAIN: ARROW" - its leading G names the guardian's key, so it is
	-- redrawn with the key the player bound to it
	local subForm = CFG.Callouts.Guardian.subForm or ""
	local gName = CFG.Keys.Guardian.Name
	if guarding and string.sub(subForm, 1, #gName + 1) == gName .. " " then
		subForm = Keybinds.label(CFG.Keys.Guardian) .. string.sub(subForm, #gName + 1)
	end
	guardSub.Text = guarding and subForm or (CFG.Callouts.Guardian.sub or "")
	-- X RELEASE while it stands: dim, with a countdown, until the entrance has played out
	releaseChip.Visible = guarding
	if guarding then
		local wait = (char and char:GetAttribute("GuardianReleaseAt") or 0) - now()
		local label = CFG.Labels.Release or "RELEASE"
		releaseLabel.Text = wait > 0 and string.format("%s %.1f", label, wait) or label
		releaseChip.BackgroundTransparency = wait > 0 and 0.4 or 0
		releaseStroke.Transparency = wait > 0 and 0.65 or 0.1 + 0.3 * math.sin(os.clock() * 4) ^ 2
	end
	local t = now()
	local timers = {}
	for skill, b in pairs(buttons) do
		local activeUntil = char and ((skill == "Eyes" and char:GetAttribute("EyeMode") and char:GetAttribute("EyeUntil"))
			or (skill == "Guardian" and char:GetAttribute("Guardian") and char:GetAttribute("GuardianUntil")))
		if activeUntil and activeUntil > t then
			if skill == "Guardian" then
				-- while it stands the pill shows the arrow's cooldown
				local rem = cooldownEnd.Arrow - t
				b.cd.Size = UDim2.fromScale(math.clamp(rem / (CFG.Arrow.Cooldown * Perks.cdMul("Arrow") + CFG.Arrow.ChargeTime), 0, 1), 1)
				b.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""
			else
				b.cd.Size = b.horizontal and UDim2.fromScale(0, 1) or UDim2.fromScale(1, 0)
				b.cdText.Text = ""
			end
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(os.clock() * 6)
			table.insert(timers, string.format("%s %ds", CFG.Labels[skill], math.ceil(activeUntil - t)))
		else
			b.stroke.Transparency = 0.1
			local rem = cooldownEnd[skill] - t
			local frac = math.clamp(rem / math.max(COOLDOWN[skill] * Perks.cdMul(skill), rem), 0, 1)
			b.cd.Size = b.horizontal and UDim2.fromScale(frac, 1) or UDim2.fromScale(1, frac)
			b.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""
			local ready = rem <= 0
			if ready and not b.ready then
				b.scale.Scale = 1.14
				Fx2.tween(b.scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
			b.ready = ready
		end
	end
	status.Text = table.concat(timers, "   ")
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok then
		warn("[TempestClient] frame: " .. tostring(err))
	end
end)

player.CharacterAdded:Connect(function()
	rootUntil, faceUntil, tumbleUntil, stunUntil = 0, 0, 0, 0
	dash, savedWalk = nil, nil
	FaceCam.stop()
	if camSaved then
		-- died inside the guardian: back to the zoom limits from before it
		player.CameraMinZoomDistance, player.CameraMaxZoomDistance = camSaved.min, camSaved.max
		camSaved = nil
	else
		player.CameraMinZoomDistance = 0.5
	end
end)

-- Studio test hooks (GojoShared.ClientDebug): ("Sasuke", skill) casts as if its key were pressed - Lance, Pulse, Eyes,
-- Guardian (again while it stands = the arrow), Slash, Release
if RunService:IsStudio() then
	local dbg = ReplicatedStorage:FindFirstChild("GojoShared") and ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Sasuke" and type(arg) == "string" then
				request(arg)
			end
		end)
	end
end

print(string.format("[TempestClient] ready - Q %s | E %s | R %s | G %s | M1 %s / G %s / X %s while the guardian stands",
	CFG.Labels.Lance, CFG.Labels.Pulse, CFG.Labels.Eyes, CFG.Labels.Guardian, CFG.Labels.Slash, CFG.Labels.Arrow, CFG.Labels.Release or "RELEASE"))
