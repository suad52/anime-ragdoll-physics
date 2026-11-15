--!nocheck
-- CarverClient: input, ability bar and local body for the Carver kit, plus playback of every cast the server
-- broadcasts (it only renders; hits, damage and ragdolls are decided on the server). Skill-name free: everything that
-- is skinnable (colours, labels, sounds, timings) comes from ReplicatedStorage.CarverKit.Config.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("CarverKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local LockRemote = Remotes:WaitForChild("Lock")
local GojoClient = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local FX = require(GojoClient:WaitForChild("GojoFX")) -- bolts, arcs, glows, rings, streaks, impact frames
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

local PAL, SND = CFG.Palette, CFG.Sounds
-- (2026-11-07 perks) Perks.pal: the caster's colourway, read at cast time on every client - Config.AltPalette
-- ("BONE KING") while their player's Skin attribute is "Alt", else the normal palette; every cast handler shadows PAL
-- with it. Perks.cdMul: the local player's cooldown factors (CooldownMul, and UltChargeMul for the domain), the same
-- ones CarverService applies.
local Perks = { base = CFG.Palette, alt = table.clone(CFG.Palette), ULT = { Shrine = true } }
for k, v in pairs(CFG.AltPalette or {}) do
	Perks.alt[k] = v
end
function Perks.pal(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
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
local VERT = CFrame.Angles(0, 0, R(90)) -- a Cylinder part's axis is X; this stands it upright

local Folder = Instance.new("Folder")
Folder.Name = "Carver"
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

-- parts a ground / cursor ray should look through: effects, flying debris, every body
local ignoreCache, ignoreAt = nil, 0
local function ignoreList()
	if ignoreCache and os.clock() - ignoreAt < 0.4 then
		return ignoreCache
	end
	local ignore = { Folder }
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris", "DamageNumbers", "VulpineFX", "Tempest" }) do
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
local function groundAt(pos)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position or pos - UP * 3, hit and hit.Normal or UP
end

-- a hand anchor point (R15 grip attachment, else the hand, else in front of the chest)
local function handPoint(char, left)
	local hand = char:FindFirstChild(left and "LeftHand" or "RightHand")
	local grip = hand and hand:FindFirstChild(left and "LeftGripAttachment" or "RightGripAttachment")
	if grip then
		return grip.WorldPosition
	end
	if hand then
		return hand.Position
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position + hrp.CFrame.LookVector * 2 or nil
end

-- the world point under the cursor (the screen centre on touch-only devices)
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local function cursorTarget()
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	-- unlike the ground ray, this one lands on bodies too, so a shot aimed at an enemy is aimed at the enemy
	local skip = { Folder }
	if player.Character then
		table.insert(skip, player.Character)
	end
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris", "DamageNumbers", "VulpineFX", "Tempest" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	cursorParams.FilterDescendantsInstances = skip
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
	s.RollOffMaxDistance = 420
	s.Parent = Fx2.anchor(Folder, pos, 8)
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

-- visual building blocks: a glowing part, a segment from a to b (Z runs along it), a stretched ellipsoid
local function neon(name, shape, color, parent)
	return Fx2.part(name, shape, Enum.Material.Neon, color, parent or Folder)
end

local function seg(part, a, b, thick)
	part.Size = Vector3.new(thick, thick, math.max((b - a).Magnitude, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

local function ellipsoid(name, size, color, material, parent)
	local p = Fx2.part(name, Enum.PartType.Block, material or Enum.Material.Neon, color, parent or Folder)
	p.Size = size
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- poses (degrees; shoulder flexion +X, lean forward Waist -X, right arm out RightShoulder Z+)
local POSE = {
	-- dismantle: a drawn-back guard, then three cuts that cross
	CutBack = { RightShoulder = { 150, 0, 40 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { -30, 0, -30 }, Waist = { 6, -35, 0 }, Neck = { 4, 20, 0 } },
	CutA = { RightShoulder = { 75, 0, -55 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { -40, 0, -20 }, Waist = { -12, 40, 0 }, Neck = { 8, -25, 0 } },
	CutB = { RightShoulder = { 85, 0, 70 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { -30, 0, -25 }, Waist = { -12, -40, 0 }, Neck = { 8, 25, 0 } },
	CutC = { RightShoulder = { 60, 0, 5 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -50, 0, -20 }, Waist = { -28, 0, 0 }, Neck = { 14, 0, 0 } },
	-- the arrow: no bow in sight, the left arm reaches out, the right hand draws an unseen string back
	Draw = { LeftShoulder = { 90, 0, 6 }, LeftElbow = { 0, 0, 0 }, RightShoulder = { 70, 0, 80 }, RightElbow = { 125, 0, 0 }, Waist = { 0, -40, 0 }, Neck = { 0, 40, 0 } },
	Loose = { LeftShoulder = { 90, 0, 6 }, RightShoulder = { 30, 0, 60 }, RightElbow = { 10, 0, 0 }, Waist = { -6, -34, 0 }, Neck = { 0, 34, 0 } },
	Crouch = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, LeftHip = { 35, 0, -8 }, RightHip = { 12, 0, 8 }, LeftKnee = { -55, 0, 0 }, RightKnee = { -30, 0, 0 } },
	-- the world cut: hands clasped, hands apart, one arm to the sky, then the chop down
	SealA = { RightShoulder = { 55, 0, -35 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 55, 0, 35 }, LeftElbow = { 95, 0, 0 }, Waist = { -6, 0, 0 } },
	SealB = { RightShoulder = { 95, 0, 25 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 95, 0, -25 }, LeftElbow = { 60, 0, 0 }, Waist = { -2, 0, 0 } },
	SealC = { RightShoulder = { 175, 0, 10 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 40, 0, -50 }, LeftElbow = { 80, 0, 0 }, Waist = { 10, 0, 0 } },
	Chop = { RightShoulder = { 95, 0, -5 }, RightElbow = { 5, 0, 0 }, LeftShoulder = { 30, 0, -30 }, Waist = { -26, 0, 0 }, Neck = { 12, 0, 0 } },
	-- the zone: a two-handed seal pressed together at the chest, then both arms thrown wide
	SealD = { RightShoulder = { 60, 0, -30 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 60, 0, 30 }, LeftElbow = { 120, 0, 0 }, Waist = { -4, 0, 0 }, Neck = { -8, 0, 0 } },
	Expand = { RightShoulder = { 70, 0, 100 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 70, 0, -100 }, LeftElbow = { 10, 0, 0 }, Waist = { 10, 0, 0 }, Neck = { 14, 0, 0 } },
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
local function pose(char, keys, length)
	if char and char.Parent then
		Animator.stopAll(char, 0.08)
		Animator.play(char, { length = length, fadeIn = 0.08, fadeOut = 0.25, keys = keys })
	end
end

---------------------------------------------------------------------------------------------------
-- local body: rooting while casting, being knocked back, being locked in the zone
local rootUntil, faceUntil, faceDirV = 0, 0, nil
local tumbleUntil = 0
local lockUntil, joltUntil, joltStrength, nextJolt = 0, 0, 0, 0
local savedWalk, savedJump

local function faceDir(hrp, dir)
	local f = flat(dir, nil)
	if hrp and f then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + f)
	end
end

-- this client owns its body: knockback from any Carver caster is applied here
Knockback.OnClientEvent:Connect(function(vel, duration, keep)
	local char, hum = myChar()
	if not char or typeof(vel) ~= "Vector3" then
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

-- (2026-11-10, "when you use Fuga on someone they get permanently ragdolled") the tumble's get-up used to sit at the
-- end of frame()'s body section, behind every cast's per-frame effects inside one pcall, so an effect error anywhere in
-- the frame skipped it; and nothing ever took the humanoid back out of a Physics state that PvPStunClient (limp while
-- the server has the rig loosened) can leave behind if the rig is put back while a kit's GettingUp is still pending.
-- It now runs on its own Heartbeat, and for a few seconds after it a body still limp (Physics) although the server has
-- already restored its rig (Ragdolled cleared) and nothing holds or flies it is stood up again.
local HELD_ATTRS = { "GrabbedBy", "InDomain", "WhippedBy", "SlashedBy", "Flying" }
local standCheckUntil = 0
RunService.Heartbeat:Connect(function()
	local clock = os.clock()
	local char, hum = myChar()
	if not hum then
		return
	end
	if tumbleUntil > 0 and clock >= tumbleUntil then
		tumbleUntil = 0
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		standCheckUntil = clock + 3
	end
	if standCheckUntil > 0 then
		if clock >= standCheckUntil or tumbleUntil > 0 then
			standCheckUntil = 0 -- over, or a new tumble started (its own end re-arms the check)
		elseif hum:GetState() == Enum.HumanoidStateType.Physics and not char:GetAttribute("Ragdolled") then
			local held = false
			for _, a in ipairs(HELD_ATTRS) do
				if char:GetAttribute(a) ~= nil then
					held = true
					break
				end
			end
			if not held then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end)

-- the zone locks this client: no walking or jumping for `moveLock` seconds, and a micro-impulse every tick for
-- `duration` seconds (strength = studs/s)
-- (2026-11-10, "people can just walk out") the zone now holds a caught body for ALL of its time left (the server sends
-- that as both duration and moveLock, plus the zone's id) and lets it go with ("release", 0, 0, id) the moment the
-- zone ends or its caster dies / leaves - so each zone's hold is kept by id and dropped without being waited out.
local zoneHolds = {} -- [zone id] = { lock = os.clock() it ends, jolt = os.clock() its shudder ends }
local function recomputeHolds()
	lockUntil, joltUntil = 0, 0
	for _, h in pairs(zoneHolds) do
		lockUntil = math.max(lockUntil, h.lock)
		joltUntil = math.max(joltUntil, h.jolt)
	end
end
LockRemote.OnClientEvent:Connect(function(duration, jolt, moveLock, id)
	local key = id ~= nil and id or "zone"
	if duration == "release" then
		zoneHolds[key] = nil
		recomputeHolds()
		return
	end
	local clock = os.clock()
	local h = zoneHolds[key] or { lock = 0, jolt = 0 }
	h.lock = math.max(h.lock, clock + (tonumber(moveLock) or 1))
	h.jolt = math.max(h.jolt, clock + (tonumber(duration) or 1))
	zoneHolds[key] = h
	joltStrength = tonumber(jolt) or 4
	recomputeHolds()
end)

---------------------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "CarverHUD"
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

-- cinematic letterbox bars for the long casts
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
	title.Text = (CFG.Titles and CFG.Titles[skill]) or CFG.Labels[skill] or skill
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
	task.delay(1.6, function()
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

-- incantation subtitles, low on the screen (the same look as the Limitless kit's chant lines)
local subtitle = uiText(gui, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromScale(0.7, 0.06),
	Text = "", TextTransparency = 1, Font = Enum.Font.GothamBold, ZIndex = 40,
})
local subStroke = uiStroke(subtitle, Color3.fromRGB(70, 6, 14), 2, 1, true)
local subScale = Instance.new("UIScale")
subScale.Parent = subtitle
local subToken
local subFade = {}
local function showSubtitle(text, hold)
	local token = {}
	subToken = token
	-- a fade still running from the previous line would drag this one back out, so stop it first
	for _, tw in ipairs(subFade) do
		tw:Cancel()
	end
	subFade = {}
	subtitle.Text = text
	subtitle.TextTransparency = 0
	subStroke.Transparency = 0
	subScale.Scale = 1.35
	Fx2.tween(subScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(hold or 0.65, function()
		if subToken ~= token then
			return
		end
		subFade = { Fx2.tween(subtitle, 0.25, { TextTransparency = 1 }), Fx2.tween(subStroke, 0.25, { Transparency = 1 }) }
	end)
end

-- ability bar, laid out like the Limitless kit's: two skills, the shared M1 punch, the big world-cut button, and the
-- zone on its own wide button above the row
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
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -172), Size = UDim2.new(1, 0, 0, 16), -- above the zone pill
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold,
})
uiStroke(status, Color3.new(0, 0, 0), 1.5, 0.3, true)

local COOLDOWN = { Cleave = CFG.Cleave.Cooldown, Fuga = CFG.Fuga.Cooldown, Sever = CFG.Sever.Cooldown, Shrine = CFG.Shrine.Cooldown }
local cooldownEnd = { Cleave = 0, Fuga = 0, Sever = 0, Shrine = 0 }
local buttons = {}

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	Request:FireServer(skill, { aim = workspace.CurrentCamera.CFrame.LookVector, target = cursorTarget() })
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
	keyText(uiText(chip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, ZIndex = 2 }), function()
		return Keybinds.label(CFG.Keys[id])
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
skillButton("Fuga", 72, -280) -- the Reversal Red slot
skillButton("Cleave", 72, -198) -- the Lapse Blue slot
skillButton("Sever", 104, 0) -- the Hollow Purple slot

-- the shared M1 punch, in the same slot and style as the other kits'
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
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 240, 230), Color3.fromRGB(255, 180, 90))
	g.Rotation = 45
	g.Parent = orb
	uiText(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = "PUNCH", ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(24, 14, 10)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	uiText(chip, { Size = UDim2.fromScale(1, 1), Text = "M1", Font = Enum.Font.GothamBold, ZIndex = 2 })
	b.Activated:Connect(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local gojo = scripts and scripts:FindFirstChild("GojoClient")
		local bind = gojo and gojo:FindFirstChild("SharedPunch")
		if bind then
			bind:Fire()
		end
	end)
end

-- the zone on its own wide button above the row (the Domain Expansion slot)
do
	local co = CFG.Callouts.Shrine
	local b = Instance.new("TextButton")
	b.Name = "Shrine"
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
		return Keybinds.label(CFG.Keys.Shrine)
	end)
	uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Shrine, ZIndex = 2 })
	uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
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
	buttons.Shrine = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Shrine")
	end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	-- (2026-11-11 keybinds) the press as the move's default key, which is what CFG.Keys holds
	local pressed = Keybinds.logical(input.KeyCode)
	for skill, key in pairs(CFG.Keys) do
		if pressed == key then
			request(skill)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- cast playback
local handlers = {}
local fugas = {}     -- [id] = the arrow being charged / flown
local burnZones = {} -- scorched ground left by a fuga burst: { pos, radius, untilT, nextBody, fires }
local bodyFire = {}  -- [model] = a flame emitter on a body standing in a burn zone

function handlers.Cooldown(d)
	if cooldownEnd[d.skill] ~= nil and typeof(d.ends) == "number" then
		cooldownEnd[d.skill] = d.ends
	end
end

-- a batch of hits from the server: damage numbers over every body, plus the hit-confirm for the attacker
function handlers.Hits(d)
	Feedback.hits(d, Color3.fromRGB(255, 105, 105))
end

local function torsoOf(model)
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------------------------------------
-- Skill 1: cleave. A translucent crescent of light flies down each cutting line; every body it cuts flares and
-- keeps a glowing slash across its torso for a couple of seconds.
local CRESCENT_SEGS = 14
local CRESCENT_SPEED = 560

local function crescent(parent, origin, dir, length, tilt, pal)
	local PAL = pal or PAL
	local side = dir:Cross(UP)
	side = side.Magnitude > 0.1 and side.Unit or Vector3.xAxis
	local right = CFrame.fromAxisAngle(dir, R(tilt)):VectorToWorldSpace(side)
	local segs = {}
	for layer = 1, 2 do
		for i = 1, CRESCENT_SEGS do
			local p = neon("Crescent", Enum.PartType.Block, layer == 1 and PAL.SlashCore or PAL.Slash, parent)
			p.Transparency = 1
			segs[#segs + 1] = { part = p, i = i, layer = layer }
		end
	end
	local carrier = Fx2.part("CrescentCarrier", Enum.PartType.Ball, Enum.Material.SmoothPlastic, PAL.Slash, parent)
	carrier.Transparency = 1
	carrier.Size = Vector3.one
	local trail = Fx2.emitter(carrier, {
		Texture = Fx2.Tex.flare, Color = ColorSequence.new(PAL.SlashCore, PAL.Slash), LightEmission = 1, Rate = 220,
		Lifetime = NumberRange.new(0.18, 0.32), Speed = NumberRange.new(2, 10), SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(1, 0) }),
	})
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = PAL.Slash, 26, 4, false
	light.Parent = carrier
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		local travelled = CRESCENT_SPEED * el
		local fade = math.clamp((travelled - length) / 14, 0, 1)
		if fade >= 1 or not parent.Parent then
			conn:Disconnect()
			trail.Enabled = false
			for _, s in ipairs(segs) do
				s.part:Destroy()
			end
			return
		end
		trail.Enabled = fade < 0.2
		local center = origin + dir * math.min(travelled, length)
		local radius = 4.6 * (1 + el * 1.2) -- the crescent opens as it flies
		local pts = {}
		for k = 0, CRESCENT_SEGS do
			local phi = ((k / CRESCENT_SEGS) * 2 - 1) * 1.2
			pts[k] = center + right * (math.sin(phi) * radius) - dir * ((1 - math.cos(phi)) * radius * 1.4)
		end
		for _, s in ipairs(segs) do
			local mid = 1 - math.abs(((s.i - 0.5) / CRESCENT_SEGS) * 2 - 1) -- thickest in the middle, tapering to points
			local thick = (s.layer == 1 and 0.5 or 1.5) * (0.2 + 0.8 * mid) * (1 - fade)
			seg(s.part, pts[s.i - 1], pts[s.i], math.max(thick, 0.05))
			s.part.Transparency = (s.layer == 1 and 0.04 or 0.42) + fade * 0.6
		end
		carrier.CFrame = CFrame.new(center)
	end)
end

-- the slash line left across a body's torso: a hot white core inside a crimson glow, on the face the cut came from
local function slashMark(model, fromPos, tilt, pal)
	local PAL = pal or PAL
	local torso = torsoOf(model)
	if not torso then
		return
	end
	local front = (fromPos - torso.Position):Dot(torso.CFrame.LookVector) > 0
	local zOff = (torso.Size.Z / 2 + 0.06) * (front and -1 or 1)
	local base = torso.CFrame * CFrame.new(0, 0, zOff) * CFrame.Angles(0, 0, R(tilt))
	local life = CFG.Cleave.MarkLife
	local function strip(name, thick, len, color, tr)
		local p = Instance.new("Part")
		p.Name = name
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = tr
		p.Size = Vector3.new(thick, len, 0.08)
		p.CFrame = base
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		p.Parent = Folder
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, p
		w.Parent = p
		Debris:AddItem(p, life + 0.5)
		task.delay(life * 0.55, function()
			if p.Parent then
				Fx2.tween(p, life * 0.45, { Transparency = 1 })
			end
		end)
	end
	strip("MarkGlow", 0.55, 5.6, PAL.Slash, 0.45)
	strip("MarkCore", 0.14, 5.2, PAL.SlashCore, 0)
	if CFG.Cleave.MarkDecal ~= "" then
		local dc = Instance.new("Decal")
		dc.Texture = CFG.Cleave.MarkDecal
		dc.Face = front and Enum.NormalId.Front or Enum.NormalId.Back
		dc.Parent = torso
		Debris:AddItem(dc, life)
	end
end

local function cutImpact(model, origin, dir, i, last, mine, pal)
	local PAL = pal or PAL
	local torso = torsoOf(model)
	if not torso then
		return
	end
	local pos = torso.Position
	local f = castFolder("CleaveHit", 3)
	FX.glow(f, pos, last and 24 or 15, PAL.Slash, 0.3)
	FX.sparks(f, pos, { color = PAL.Steel, color2 = PAL.Slash, count = last and 46 or 26, speed = { 25, 95 }, size = 0.6 })
	FX.streaks(f, pos, { dir = dir, spread = 28, speed = { 60, 150 }, count = last and 26 or 14, color = PAL.SlashCore, color2 = PAL.Slash, size = 0.9 })
	FX.ring(f, pos, dir, 1, last and 18 or 11, PAL.Slash, 0.3)
	Fx2.flash(f, pos, 5, PAL.SlashCore, 0.18)
	slashMark(model, origin, CFG.Cleave.Tilts[i] or 0, PAL)
	sound(SND.HitHeavy, pos, 0.9, last and 1.1 or 1.4)
	sound(SND.Hit, pos, 0.8, 1.9 + i * 0.1)
	Fx2.shake(last and 1.8 or 0.8, 0.2, pos)
	if mine and last then
		FX.impact({ tint = PAL.Slash, lineColor = PAL.SlashCore, flashAlpha = 0.25 })
	end
end

function handlers.CleaveStart(d)
	local char = charOf(d.userId)
	if char then
		local keys = {
			{ t = 0.08, ease = { "Back", "Out" }, pose = POSE.CutBack },
			{ t = d.windup, ease = { "Sine", "InOut" }, pose = POSE.CutBack },
		}
		local cuts = { POSE.CutA, POSE.CutB, POSE.CutC }
		for i = 1, d.lines do
			table.insert(keys, { t = d.windup + (i - 1) * d.interval + 0.05, ease = { "Exponential", "Out" }, pose = cuts[i] or POSE.CutC })
		end
		pose(char, keys, d.windup + (d.lines - 1) * d.interval + 0.5)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			sound(SND.Whoosh, hrp.Position, 0.7, 1.4)
		end
	end
	if isMe(d.userId) then
		faceUntil, faceDirV = os.clock() + d.windup + d.lines * d.interval + 0.15, d.dir
	end
end

function handlers.CleaveLine(d)
	local PAL = Perks.pal(d.userId)
	local f = castFolder("Cleave", 3)
	local origin, dir, i = d.origin, d.dir, d.i
	local last = i == CFG.Cleave.Lines
	crescent(f, origin, dir, d.length, d.tilt, PAL)
	-- where the cut leaves the hand: steel sparks, a streak burst, a flash
	FX.sparks(f, origin, { color = PAL.Steel, color2 = PAL.Slash, dir = dir, spread = 40, count = 22, speed = { 30, 90 }, size = 0.5 })
	FX.streaks(f, origin, { dir = dir, spread = 14, speed = { 120, 260 }, count = 18, color = PAL.SlashCore, color2 = PAL.Slash, size = 0.9, life = 0.25 })
	FX.glow(f, origin, 9, PAL.Slash, 0.2)
	-- the cutting line itself, drawn hair-thin for an instant
	local line = neon("CutLine", Enum.PartType.Block, PAL.SlashCore, f)
	seg(line, origin, origin + dir * d.length, 0.3)
	Fx2.tween(line, 0.3, { Size = Vector3.new(0.02, 0.02, d.length), Transparency = 1 })
	sound(SND.Whoosh, origin, 0.9, 1.6 + i * 0.15)
	sound(SND.Hit, origin, 0.8, 2.2) -- the sharp metal ring of the blade
	if d.blocked then
		local at = origin + dir * d.length
		task.delay(d.length / CRESCENT_SPEED, function()
			FX.sparks(f, at, { color = PAL.Steel, color2 = PAL.Slash, count = 24, speed = { 20, 80 }, size = 0.6 })
			FX.glow(f, at, 10, PAL.Slash, 0.25)
		end)
	end
	for _, m in ipairs(d.targets) do
		if m.Parent then
			local r = m:FindFirstChild("HumanoidRootPart")
			local delay = r and math.max((r.Position - origin):Dot(dir), 0) / CRESCENT_SPEED or 0
			task.delay(delay, function()
				if m.Parent then
					cutImpact(m, origin, dir, i, last, isMe(d.userId), PAL)
				end
			end)
		end
	end
	if isMe(d.userId) then
		Fx2.shake(0.5, 0.15)
		Fx2.envelope({ fov = last and 8 or 3, attack = 0.02, release = 0.2 })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 2: fuga. An unseen string is drawn; a hyper-dense arrow of white-hot core, crimson shaft and a roaring flame
-- aura grows between the hands with fire spiralling round it; it is loosed down the server's line (simulated here so
-- it stays smooth) and bursts into a 25-stud sphere of heat that keeps the ground burning.
local function makeArrow(pal)
	local PAL = pal or PAL
	local v = {}
	v.shaft = neon("FugaShaft", Enum.PartType.Block, PAL.FireDeep)
	v.core = neon("FugaCore", Enum.PartType.Block, PAL.FireCore)
	v.tip = neon("FugaTip", Enum.PartType.Ball, PAL.FireCore)
	v.halo = neon("FugaHalo", Enum.PartType.Ball, PAL.Fire)
	v.halo.Transparency = 0.72
	v.shell = Fx2.part("FugaShell", Enum.PartType.Ball, Enum.Material.ForceField, PAL.Fire, Folder)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = PAL.Fire, 55, 7, false
	l.Parent = v.tip
	v.flame = Fx2.emitter(v.shaft, {
		Texture = Fx2.Tex.fire, Color = ColorSequence.new(PAL.FireCore, PAL.Fire, PAL.FireDeep), LightEmission = 1, Rate = 160,
		Lifetime = NumberRange.new(0.5, 1.0), Speed = NumberRange.new(3, 14), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 16, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-80, 80),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(0.4, 9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	})
	v.embers = Fx2.emitter(v.shaft, {
		Texture = Fx2.Tex.flare, Color = ColorSequence.new(PAL.FireCore, PAL.Fire), LightEmission = 1, Rate = 70,
		Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(8, 26), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 8, 0), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) }),
	})
	v.smoke = Fx2.emitter(v.shaft, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(Color3.fromRGB(90, 36, 20), Color3.fromRGB(30, 22, 22)), LightEmission = 0.2, Rate = 25,
		Lifetime = NumberRange.new(1.0, 1.8), Speed = NumberRange.new(2, 8), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 15) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
	})
	-- a, b = tail and head of the arrow; scale grows it during the charge
	function v:place(a, b, scale)
		seg(self.shaft, a, b, 1.3 * scale)
		seg(self.core, a, b, 0.5 * scale)
		local mid = (a + b) / 2
		self.tip.Size, self.tip.CFrame = Vector3.one * 2.8 * scale, CFrame.new(b)
		self.halo.Size, self.halo.CFrame = Vector3.one * 8 * scale, CFrame.new(mid)
		self.shell.Size, self.shell.CFrame = Vector3.one * 13 * scale, CFrame.new(mid)
	end
	function v:setIntensity(k)
		self.flame.Rate, self.embers.Rate, self.smoke.Rate = 160 * k, 70 * k, 25 * k
	end
	function v:destroy()
		self.flame.Enabled, self.embers.Enabled, self.smoke.Enabled = false, false, false
		for _, p in ipairs({ self.shaft, self.core, self.tip, self.halo, self.shell }) do
			p.Transparency = 1
			Debris:AddItem(p, 1.8)
		end
	end
	return v
end

local function endFuga(id)
	local fg = fugas[id]
	if not fg then
		return
	end
	fugas[id] = nil
	fg.arrow:destroy()
	if fg.helix then
		fg.helix:destroy()
	end
end

function handlers.FugaCharge(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local fg = {
		char = char, t0 = os.clock(), time = d.time, isLocal = isMe(d.userId), phase = "charge", nextFx = 0, nextRing = 0,
		arrow = makeArrow(PAL), pal = PAL, helix = FX.helix(Folder, { PAL.FireCore, PAL.Fire, PAL.FireDeep }, 3.4, 0.9),
	}
	fugas[d.id] = fg
	local drawn = merge(POSE.Crouch, POSE.Draw)
	pose(char, {
		{ t = 0.2, ease = { "Back", "Out" }, pose = drawn },
		{ t = d.time, ease = { "Sine", "InOut" }, pose = drawn },
		{ t = d.time + 0.06, ease = { "Exponential", "Out" }, pose = POSE.Loose },
		{ t = d.time + 0.5, ease = { "Sine", "Out" }, pose = POSE.Loose },
	}, d.time + 0.8)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		sound(SND.Rise, hrp.Position, 1, 0.8)
		sound(SND.Hum, hrp.Position, 0.9, 1.1)
		sound(SND.Crackle, hrp.Position, 0.8, 0.7)
		local g, n = groundAt(hrp.Position)
		Fx2.cracks(Folder, g, n, 10, PAL.Fire, d.time + 2)
	end
	if fg.isLocal then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		rootUntil = os.clock() + d.time + 0.4
		Fx2.envelope({ fov = -9, tint = PAL.Fire, bright = -0.05, contrast = 0.1, attack = d.time * 0.9, release = 0.15 })
		Fx2.shake(0.9, d.time, hrp and hrp.Position)
		task.delay(math.max(d.time - 0.08, 0), function()
			Request:FireServer("FugaAim", { id = d.id, target = cursorTarget() })
		end)
	end
	task.delay(d.time + 3, function()
		if fugas[d.id] == fg and fg.phase == "charge" then
			endFuga(d.id)
		end
	end)
end

function handlers.FugaCancel(d)
	endFuga(d.id)
end

function handlers.FugaLaunch(d)
	local PAL = Perks.pal(d.userId)
	local fg = fugas[d.id]
	if not fg then
		fg = { arrow = makeArrow(PAL), pal = PAL, phase = "charge" }
		fugas[d.id] = fg
	end
	if fg.helix then
		fg.helix:destroy()
		fg.helix = nil
	end
	fg.phase, fg.origin, fg.dir, fg.speed, fg.t0f, fg.nextRing = "flight", d.origin, d.dir, d.speed, os.clock(), 0
	fg.startOffset = fg.pos and (fg.pos - d.origin):Dot(d.dir) or 0
	fg.arrow:setIntensity(2.2)
	local f = castFolder("FugaLaunch", 3)
	FX.ring(f, d.origin, d.dir, 4, 70, PAL.FireCore, 0.4)
	Fx2.shockwave(f, d.origin, d.dir, 5, 56, PAL.Fire, 0.5)
	FX.streaks(f, d.origin, { dir = d.dir, spread = 24, speed = { 110, 280 }, count = 80, color = PAL.FireCore, color2 = PAL.Fire, size = 1.7 })
	FX.glow(f, d.origin, 50, PAL.Fire, 0.5)
	FX.sparks(f, d.origin, { color = PAL.Fire, color2 = PAL.FireCore, count = 50, speed = { 30, 100 }, size = 1.0 })
	sound(SND.Whoosh, d.origin, 1, 0.5)
	sound(SND.Boom, d.origin, 0.9, 1.0)
	sound(SND.Crackle, d.origin, 0.9, 0.8)
	Fx2.shake(2.6, 0.5, d.origin)
	if fg.isLocal then
		FX.speedLines(0.8)
		Fx2.envelope({ fov = 16, blur = 7, tint = PAL.Fire, attack = 0.03, release = 0.5 })
		rootUntil = os.clock() + 0.3
	end
end

function handlers.FugaBlast(d)
	local PAL = Perks.pal(d.userId)
	endFuga(d.id)
	local pos, radius = d.pos, d.radius
	local f = castFolder("FugaBlast", d.burn + 4)
	local g, nrm = groundAt(pos)
	-- 1. the flash and the thermal sphere: a white-hot core, the lethal radius as a shell, a slow outer shock
	Fx2.flash(f, pos, radius * 0.9, PAL.FireCore, 0.7)
	FX.light(f, pos + UP * 6, PAL.Fire, 16, 60, 1.6)
	FX.glow(f, pos, radius * 3.2, PAL.FireCore, 0.55)
	FX.shell(f, pos, 3, radius, PAL.FireCore, 0.4)
	FX.shell(f, pos, 3, radius * 1.1, PAL.Fire, 0.65, Enum.Material.ForceField)
	FX.shell(f, pos, 3, radius * 1.7, PAL.FireDeep, 1.2, Enum.Material.ForceField)
	-- 2. rings along the ground and a standing pressure wave
	for i = 0, 3 do
		task.delay(i * 0.07, function()
			FX.ring(f, g + UP * 0.5, UP, 8, radius * (1.5 + i * 0.55), i % 2 == 0 and PAL.FireCore or PAL.Fire, 0.9)
		end)
	end
	Fx2.shockwave(f, g + UP * 0.6, UP, 10, radius * 3.2, PAL.Fire, 1.0)
	Fx2.shockwave(f, pos, Vector3.xAxis, 8, radius * 2.4, PAL.FireCore, 0.7)
	-- 3. columns of fire: a great pillar in the middle and a crown of eight round the rim
	local function column(at, height, width, delay, life)
		task.delay(delay, function()
			local p = neon("FireColumn", Enum.PartType.Cylinder, PAL.Fire, f)
			p.Transparency = 0.15
			p.Size = Vector3.new(2, width, width)
			p.CFrame = CFrame.new(at + UP) * VERT
			Fx2.tween(p, life, { Size = Vector3.new(height, width * 1.5, width * 1.5), CFrame = CFrame.new(at + UP * height / 2) * VERT, Transparency = 1, Color = PAL.FireDeep }, Enum.EasingStyle.Quart)
			Fx2.emitter(p, {
				Texture = Fx2.Tex.fire, Color = ColorSequence.new(PAL.FireCore, PAL.Fire), LightEmission = 1, Rate = 80,
				Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 8), SpreadAngle = Vector2.new(180, 180),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, width * 0.7), NumberSequenceKeypoint.new(1, 0) }),
			})
		end)
	end
	column(g, 90, 14, 0, 1.2)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		column(g + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.85, 40 + math.random() * 25, 6, 0.1 + i * 0.03, 1.0)
	end
	-- 4. streaks, sparks, dust, scorch
	FX.streaks(f, pos, { count = 150, speed = { 90, 250 }, color = PAL.FireCore, color2 = PAL.Fire, size = 2.0, life = 0.7 })
	FX.sparks(f, pos, { color = PAL.Fire, color2 = PAL.FireCore, count = 140, speed = { 30, 110 }, size = 1.2 })
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		Fx2.dust(f, g + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.45, 11, 7)
	end
	Fx2.cracks(Folder, g, nrm, radius * 0.9, PAL.FireDeep, d.burn + 3)
	sound(SND.Boom, pos, 1, 0.7)
	sound(SND.HitHeavy, pos, 1, 0.5)
	sound(SND.Thunder, pos, 0.9, 0.8)
	Fx2.shake(5.5, 1.5, pos, 340)
	if d.userId == player.UserId or (myChar() and (select(3, myChar()).Position - pos).Magnitude < radius * 2.5) then
		FX.impact({ tint = PAL.Fire, lineColor = PAL.FireCore, flashAlpha = 0.5 })
		Fx2.envelope({ fov = 24, blur = 14, tint = PAL.Fire, contrast = 0.2, bright = 0.3, attack = 0.03, hold = 0.12, release = 1.2 })
	end
	-- 5. the burn zone: flames across the ground, and every body inside burns (see the frame loop)
	local zone = { pos = pos, radius = radius, untilT = os.clock() + d.burn, nextBody = 0, fires = {}, pal = PAL }
	for i = 1, 14 do
		local a, r = math.random() * math.pi * 2, radius * math.sqrt(math.random())
		local at = groundAt(pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		zone.fires[i] = Fx2.emitter(Fx2.anchor(f, at + UP * 0.5, d.burn + 2), {
			Texture = Fx2.Tex.fire, Color = ColorSequence.new(PAL.FireCore, PAL.Fire, PAL.FireDeep), LightEmission = 1, Rate = 22,
			Lifetime = NumberRange.new(0.7, 1.3), Speed = NumberRange.new(3, 9), SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 10, 0), Rotation = NumberRange.new(0, 360),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(0.5, 8), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		})
	end
	table.insert(burnZones, zone)
	task.delay(d.burn, function()
		for _, e in ipairs(zone.fires) do
			e.Enabled = false
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the world cut. Hand seals while a black tear in space opens ahead and stretches up to 30 studs, ringed by
-- distortion waves with the view warping; then a wide dark blade races along the aim leaving a wound in the air
-- and a fissure in the ground, and everything it cut is bisected by a plane of violet light.
local severs = {} -- [id] = the tear being opened

local function loopSound(id, pos, vol, speed, life)
	local s = sound(id, pos, vol, speed)
	if s then
		s.Looped = true
		Debris:AddItem(s.Parent, life)
	end
	return s
end

local function endSever(id)
	local sv = severs[id]
	if not sv then
		return
	end
	severs[id] = nil
	sv.smoke.Enabled = false
	for _, p in ipairs({ sv.core, sv.edge }) do
		Fx2.tween(p, 0.25, { Transparency = 1 })
		Debris:AddItem(p, 0.4)
	end
end

function handlers.SeverStart(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local W = CFG.Sever
	local dir, time = d.dir, d.time
	local f = castFolder("SeverCharge", time + 4)
	local center = hrp.Position + dir * 18 + UP * (W.Height / 2 - 3)
	-- the tear: a black hole of an ellipsoid inside a violet glowing rim, thin along the aim, tall, stretching
	local core = ellipsoid("TearCore", Vector3.new(1.2, 2, 6), PAL.RiftBlack, Enum.Material.SmoothPlastic, f)
	local edge = ellipsoid("TearEdge", Vector3.new(2, 2, 8), PAL.RiftEdge, Enum.Material.Neon, f)
	edge.Transparency = 0.5
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = PAL.Rift, 60, 5, false
	light.Parent = edge
	local smoke = Fx2.emitter(core, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.RiftBlack, PAL.Rift), LightEmission = 0.4, Rate = 60,
		Lifetime = NumberRange.new(0.8, 1.5), Speed = NumberRange.new(3, 12), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 7), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
	})
	severs[d.id] = { t0 = os.clock(), time = time, dir = dir, center = center, core = core, edge = edge, smoke = smoke, nextBolt = 0, nextWave = 0, nextStreak = 0, pulse = 1, isLocal = isMe(d.userId), pal = PAL }
	-- hand seals: clasped, apart, one arm to the sky, then the chop
	pose(char, {
		{ t = 0.2, ease = { "Back", "Out" }, pose = POSE.SealA },
		{ t = time * 0.33, ease = { "Sine", "InOut" }, pose = POSE.SealA },
		{ t = time * 0.36, ease = { "Quad", "Out" }, pose = POSE.SealB },
		{ t = time * 0.66, ease = { "Sine", "InOut" }, pose = POSE.SealB },
		{ t = time * 0.7, ease = { "Quad", "Out" }, pose = POSE.SealC },
		{ t = time, ease = { "Sine", "InOut" }, pose = POSE.SealC },
		{ t = time + 0.07, ease = { "Exponential", "Out" }, pose = POSE.Chop },
		{ t = time + 0.6, ease = { "Sine", "Out" }, pose = POSE.Chop },
	}, time + 0.9)
	sound(SND.Rise, hrp.Position, 1, 0.5)
	loopSound(SND.Hum, hrp.Position, 1, 0.3, time + 0.3) -- a rising sub-bass drone
	sound(SND.Crackle, center, 0.8, 0.6)
	if isMe(d.userId) then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		letterbox(true, 0.4)
		rootUntil = os.clock() + time + 0.4
		faceUntil, faceDirV = os.clock() + time + 0.2, dir
		Fx2.envelope({ fov = -8, tint = PAL.Rift, bright = -0.12, contrast = 0.15, sat = -0.15, attack = time * 0.95, release = 0.08 })
		Fx2.shake(0.7, time, center)
		task.delay(math.max(time - 0.08, 0), function()
			Request:FireServer("SeverAim", { id = d.id, target = cursorTarget() })
		end)
	end
	task.delay(time + 3, function()
		if severs[d.id] then
			endSever(d.id)
		end
	end)
end

function handlers.SeverCancel(d)
	endSever(d.id)
	letterbox(false, 0.4)
end

-- a plane of violet light slicing through a body, with a flash and a shower of sparks
local function bisect(model, dir, delay, pal)
	local PAL = pal or PAL
	task.delay(delay, function()
		local torso = torsoOf(model)
		if not (torso and model.Parent) then
			return
		end
		local pos = torso.Position
		local f = castFolder("Bisect", 3)
		local plane = neon("BisectPlane", Enum.PartType.Block, PAL.RiftEdge, f)
		plane.Size = Vector3.new(0.18, 11, 7)
		plane.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, R(90), 0)
		plane.Transparency = 0.1
		Fx2.tween(plane, 0.9, { Size = Vector3.new(0.05, 15, 11), Transparency = 1 }, Enum.EasingStyle.Quart)
		FX.bolt(f, pos + UP * 6, pos - UP * 6, { color = PAL.RiftEdge, core = PAL.SlashCore, width = 0.45, segments = 7, jag = 0.08, life = 0.3, restrike = 2 })
		FX.glow(f, pos, 26, PAL.Rift, 0.4)
		FX.sparks(f, pos, { color = PAL.RiftEdge, color2 = PAL.SlashCore, count = 50, speed = { 25, 100 }, size = 0.8 })
		FX.arcs(f, pos, 5, { count = 4, outward = true, colors = { PAL.RiftEdge, PAL.SlashCore }, width = 0.2, life = 0.18 })
		sound(SND.HitHeavy, pos, 1, 0.6)
		Fx2.shake(1.4, 0.25, pos)
	end)
end

function handlers.SeverCut(d)
	local PAL = Perks.pal(d.userId)
	local sv = severs[d.id]
	local origin, dir = d.origin, d.dir
	local width, height, range, speed = d.width, d.height, d.range, d.speed
	local flare = sv and sv.center or (origin + dir * 18 + UP * 12)
	task.delay(0.2, function()
		endSever(d.id)
	end)
	local f = castFolder("SeverCut", 6)
	local finish = origin + dir * range
	-- the bass drop: three deep layers at once, and the view slammed
	sound(SND.Boom, origin, 1, 0.3)
	sound(SND.Thunder, origin, 1, 0.45)
	sound(SND.HitHeavy, origin, 1, 0.35)
	loopSound(SND.Hum, origin, 0.9, 0.22, 1.2)
	FX.glow(f, flare, 90, PAL.Rift, 0.5)
	FX.ring(f, flare, dir, 6, 130, PAL.RiftEdge, 0.8)
	Fx2.shockwave(f, flare, dir, 8, 150, PAL.Rift, 0.9)
	Fx2.shockwave(f, groundAt(origin) + UP * 0.5, UP, 8, 100, PAL.Rift, 0.9)
	FX.streaks(f, flare, { dir = dir, spread = 30, speed = { 150, 340 }, count = 120, color = PAL.SlashCore, color2 = PAL.Rift, size = 1.8, life = 0.5 })
	Fx2.shake(5, 1.2, origin)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.Rift, lineColor = PAL.RiftEdge, flashAlpha = 0.45 })
		FX.speedLines(0.9)
		Fx2.envelope({ fov = 26, blur = 12, tint = PAL.Rift, contrast = 0.25, bright = 0.2, attack = 0.03, hold = 0.1, release = 1.0 })
		task.delay(0.9, function()
			letterbox(false, 0.5)
		end)
	end
	-- the blade: a translucent dark sheet with glowing edges, racing along the path
	local base = origin + dir * 4 + UP * (height / 2 - 3)
	local sheet = Fx2.part("CutSheet", Enum.PartType.Block, Enum.Material.SmoothPlastic, PAL.RiftBlack, f)
	sheet.Size = Vector3.new(width, height, 1.4)
	sheet.Transparency = 0.25
	local function edgeBar(w, h)
		local p = neon("CutEdge", Enum.PartType.Block, PAL.RiftEdge, f)
		p.Size = Vector3.new(w, h, 0.7)
		return p
	end
	local top, bottom, left, right = edgeBar(width, 0.6), edgeBar(width, 0.6), edgeBar(0.6, height), edgeBar(0.6, height)
	local centre = edgeBar(0.35, height)
	centre.Color = PAL.SlashCore
	-- the wound it leaves in the air along its whole path, and a violet glow around it
	local wound = Fx2.part("CutWound", Enum.PartType.Block, Enum.Material.SmoothPlastic, PAL.RiftBlack, f)
	local woundGlow = neon("CutWoundGlow", Enum.PartType.Block, PAL.Rift, f)
	woundGlow.Transparency = 0.7
	local woundTop, woundBottom = neon("CutWoundEdge", Enum.PartType.Block, PAL.RiftEdge, f), neon("CutWoundEdge", Enum.PartType.Block, PAL.RiftEdge, f)
	local t0 = os.clock()
	local conn
	local nextBolt, nextRing = 0, 0
	conn = RunService.RenderStepped:Connect(function()
		local el = os.clock() - t0
		local travelled = math.min(speed * el, range)
		local cf = CFrame.lookAt(base + dir * travelled, base + dir * (travelled + 1))
		sheet.CFrame = cf
		top.CFrame, bottom.CFrame = cf * CFrame.new(0, height / 2, 0), cf * CFrame.new(0, -height / 2, 0)
		left.CFrame, right.CFrame = cf * CFrame.new(-width / 2, 0, 0), cf * CFrame.new(width / 2, 0, 0)
		centre.CFrame = cf
		-- the wound grows with the head, then flickers and fades
		local wcf = CFrame.lookAt(base + dir * (travelled / 2), base + dir * (travelled / 2 + 1))
		wound.Size = Vector3.new(1.0, height, math.max(travelled, 0.1))
		wound.CFrame = wcf
		woundGlow.Size = Vector3.new(2.2, height + 1.5, math.max(travelled, 0.1))
		woundGlow.CFrame = wcf
		woundTop.Size, woundBottom.Size = Vector3.new(0.5, 0.5, math.max(travelled, 0.1)), Vector3.new(0.5, 0.5, math.max(travelled, 0.1))
		woundTop.CFrame, woundBottom.CFrame = wcf * CFrame.new(0, height / 2, 0), wcf * CFrame.new(0, -height / 2, 0)
		local flick = 0.1 + math.random() * 0.25
		if travelled >= range then
			local fade = math.clamp((el - range / speed - 0.9) / 0.9, 0, 1)
			for _, p in ipairs({ sheet, top, bottom, left, right, centre }) do
				p.Transparency = 1
			end
			wound.Transparency = math.clamp(flick + fade, 0, 1)
			woundGlow.Transparency = math.clamp(0.6 + flick * 0.4 + fade, 0, 1)
			woundTop.Transparency, woundBottom.Transparency = math.clamp(flick + fade, 0, 1), math.clamp(flick + fade, 0, 1)
			if fade >= 1 then
				conn:Disconnect()
			end
		else
			wound.Transparency = flick
			if os.clock() >= nextBolt then
				nextBolt = os.clock() + 0.03
				local p = base + dir * travelled + (dir:Cross(UP)) * (math.random() - 0.5) * width
				FX.bolt(f, p + UP * (height / 2), p - UP * (height / 2), { color = PAL.RiftEdge, core = PAL.SlashCore, width = 0.3, segments = 8, jag = 0.12, life = 0.1 })
			end
			if os.clock() >= nextRing then
				nextRing = os.clock() + 0.05
				Fx2.shockwave(f, base + dir * travelled, dir, 10, width * 2.2, PAL.Rift, 0.5)
			end
		end
	end)
	-- the fissure in the ground along the path, torn open in step with the blade
	local gs, ge = groundAt(origin + dir * 6), groundAt(finish)
	local len = (ge - gs).Magnitude
	local fissure = neon("Fissure", Enum.PartType.Block, PAL.RiftEdge, f)
	fissure.Size = Vector3.new(3.4, 0.25, len)
	fissure.CFrame = CFrame.lookAt((gs + ge) / 2 + UP * 0.2, ge + UP * 0.2)
	Fx2.tween(fissure, 2.4, { Size = Vector3.new(0.12, 0.25, len), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local darkLine = Fx2.part("FissureDark", Enum.PartType.Block, Enum.Material.SmoothPlastic, PAL.RiftBlack, f)
	darkLine.Size = Vector3.new(5.5, 0.15, len)
	darkLine.CFrame = CFrame.lookAt((gs + ge) / 2 + UP * 0.12, ge + UP * 0.12)
	Fx2.tween(darkLine, 3, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for dist = 8, range, 8 do
		task.delay(dist / speed, function()
			local at = origin + dir * dist
			local g, n = groundAt(at)
			Fx2.cracks(Folder, g, n, 4.5, PAL.RiftEdge, 4)
			Fx2.dust(f, g, 6, 3)
			if dist % 24 == 0 then
				Fx2.shockwave(f, at + UP * 10, dir, 10, 80, PAL.Rift, 0.7) -- a distortion wave rolling off the cut
				FX.sparks(f, at + UP * 4, { color = PAL.RiftEdge, color2 = PAL.SlashCore, count = 20, speed = { 20, 70 }, size = 0.7 })
			end
		end)
	end
	-- everything it cut is bisected
	for _, m in ipairs(d.severed) do
		if m.Parent then
			local r = m:FindFirstChild("HumanoidRootPart")
			bisect(m, dir, r and math.max((r.Position - origin):Dot(dir), 0) / speed or 0, PAL)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the zone. A two-handed seal while a tiered shrine of dark glass rises overhead under a boiling ceiling of
-- fog, a ring of light pillars marks the boundary, the world around turns blood-dark; then hundreds of red and black
-- cutting lines crisscross the whole space for the duration, bodies inside shudder under red arcs, and at the end
-- everything detonates and the shrine shatters.
local domains = {} -- [id] = the zone being sealed / open

-- the sky: any client near an open zone sees the world darken to red under heavy fog
local sky = { on = false, saved = nil, atm = nil, atmSaved = nil, created = false, tweens = {} }
local function skySet(on, pal)
	if on == sky.on then
		return
	end
	sky.on = on
	for _, t in ipairs(sky.tweens) do
		t:Cancel()
	end
	sky.tweens = {}
	local function tw(inst, props, time)
		local t = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Sine), props)
		t:Play()
		table.insert(sky.tweens, t)
	end
	if on then
		if not sky.saved then
			sky.saved = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness, ExposureCompensation = Lighting.ExposureCompensation }
			local atm = Lighting:FindFirstChildOfClass("Atmosphere")
			if atm then
				sky.created = false
			else
				atm = Instance.new("Atmosphere")
				atm.Name = "CarverDomainAtmosphere"
				atm.Density, atm.Offset, atm.Haze, atm.Glare = 0, 0, 0, 0
				atm.Parent = Lighting
				sky.created = true
			end
			sky.atm = atm
			sky.atmSaved = { Density = atm.Density, Offset = atm.Offset, Color = atm.Color, Decay = atm.Decay, Glare = atm.Glare, Haze = atm.Haze }
		end
		local sp = pal or PAL -- (perks) the zone owner's skin tints the sky too
		tw(Lighting, { Ambient = sp.SkyAmbient or Color3.fromRGB(70, 6, 14), OutdoorAmbient = sp.SkyOutdoor or Color3.fromRGB(60, 4, 12), Brightness = 0.4, ExposureCompensation = -0.55 }, 0.6)
		tw(sky.atm, { Density = 0.62, Offset = 0.2, Color = sp.SkyAtmosphere or Color3.fromRGB(110, 8, 22), Decay = sp.SkyDecay or Color3.fromRGB(70, 0, 12), Glare = 0, Haze = 5 }, 0.6)
	elseif sky.saved then
		local saved, atmSaved, atm, created = sky.saved, sky.atmSaved, sky.atm, sky.created
		tw(Lighting, saved, 0.8)
		tw(atm, atmSaved, 0.8)
		task.delay(0.9, function()
			if not sky.on then
				if created and atm.Parent then
					atm:Destroy()
				end
				sky.saved, sky.atm = nil, nil
			end
		end)
	end
end

-- the shrine motif, built from parts around a hidden root at the origin: a slab hung with blades, four tiers of
-- glowing-posted walls under sweeping roofs with upturned eaves, a spire. Put a Model named
-- Config.Shrine.TemplateName (with a PrimaryPart) in ReplicatedStorage.CarverKit to use your own art instead.
local function buildShrine(parent, pal)
	local PAL = pal or PAL
	local template = Kit:FindFirstChild(CFG.Shrine.TemplateName)
	local m
	if template and template:IsA("Model") and template.PrimaryPart then
		m = template:Clone()
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = true, false, false, false, true
			end
		end
		m.Parent = parent
	else
		m = Instance.new("Model")
		m.Name = "ShrineMotif"
		local root = Fx2.part("ShrineRoot", Enum.PartType.Block, Enum.Material.SmoothPlastic, PAL.ShrineDark, m)
		root.Transparency = 1
		m.PrimaryPart = root
		local dark, crim, bone = PAL.ShrineDark, PAL.Shrine, PAL.ShrineBone
		local function add(name, shape, size, cf, color, material, tr)
			local p = Fx2.part(name, shape, material or Enum.Material.SmoothPlastic, color, m)
			p.Size, p.CFrame, p.Transparency = size, cf, tr
			return p
		end
		-- foundation slab with glowing edges and blades hanging underneath
		add("Slab", Enum.PartType.Block, Vector3.new(46, 2.4, 46), CFrame.new(0, 0, 0), dark, nil, 0.3)
		add("SlabTop", Enum.PartType.Block, Vector3.new(38, 1.4, 38), CFrame.new(0, 1.8, 0), crim:Lerp(dark, 0.5), nil, 0.35)
		for _, s in ipairs({ -1, 1 }) do
			add("SlabEdge", Enum.PartType.Block, Vector3.new(46, 0.5, 0.5), CFrame.new(0, 1.1, 23 * s), crim, Enum.Material.Neon, 0.1)
			add("SlabEdge", Enum.PartType.Block, Vector3.new(0.5, 0.5, 46), CFrame.new(23 * s, 1.1, 0), crim, Enum.Material.Neon, 0.1)
		end
		for i = 1, 14 do
			local ang = i / 14 * math.pi * 2
			add("Blade", Enum.PartType.Block, Vector3.new(0.9, 12 + (i % 3) * 3, 3), CFrame.new(math.cos(ang) * 21, -7.5, math.sin(ang) * 21) * CFrame.Angles(0, -ang, 0), crim, Enum.Material.Neon, 0.25)
		end
		-- four tiers
		local y = 2.5
		for t = 1, 4 do
			local w = 26 - (t - 1) * 5.2
			local wall = add("Wall", Enum.PartType.Block, Vector3.new(w, 5.5, w), CFrame.new(0, y + 2.75, 0), dark, nil, 0.45)
			local lamp = Instance.new("PointLight")
			lamp.Color, lamp.Range, lamp.Brightness, lamp.Shadows = crim, 40, 2.2, false
			lamp.Parent = wall
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					add("Post", Enum.PartType.Block, Vector3.new(0.9, 5.5, 0.9), CFrame.new(sx * w / 2, y + 2.75, sz * w / 2), crim, Enum.Material.Neon, 0.15)
					-- eave tips: swept out and up from each corner of the roof
					local tip = Vector3.new(sx * (w / 2 + 6.2), y + 6.5, sz * (w / 2 + 6.2))
					add("Eave", Enum.PartType.Block, Vector3.new(2.2, 0.7, 7), CFrame.lookAt(tip, tip + Vector3.new(sx, 0, sz)) * CFrame.Angles(R(24), 0, 0), crim:Lerp(dark, 0.4), nil, 0.25)
				end
			end
			for _, s in ipairs({ -1, 1 }) do
				add("Window", Enum.PartType.Block, Vector3.new(w * 0.5, 2.4, 0.2), CFrame.new(0, y + 3, (w / 2 + 0.06) * s), crim, Enum.Material.Neon, 0.2)
				add("Window", Enum.PartType.Block, Vector3.new(0.2, 2.4, w * 0.5), CFrame.new((w / 2 + 0.06) * s, y + 3, 0), crim, Enum.Material.Neon, 0.2)
			end
			add("Roof", Enum.PartType.Block, Vector3.new(w + 11, 0.9, w + 11), CFrame.new(0, y + 5.95, 0), crim:Lerp(dark, 0.55), nil, 0.3)
			add("RoofUpper", Enum.PartType.Block, Vector3.new(w + 6, 0.9, w + 6), CFrame.new(0, y + 6.8, 0), crim:Lerp(dark, 0.7), nil, 0.3)
			for _, s in ipairs({ -1, 1 }) do
				add("RoofTrim", Enum.PartType.Block, Vector3.new(w + 11, 0.3, 0.3), CFrame.new(0, y + 6.2, (w / 2 + 5.5) * s), crim, Enum.Material.Neon, 0.1)
				add("RoofTrim", Enum.PartType.Block, Vector3.new(0.3, 0.3, w + 11), CFrame.new((w / 2 + 5.5) * s, y + 6.2, 0), crim, Enum.Material.Neon, 0.1)
			end
			y += 7.6
		end
		-- spire with rings and a burning orb
		add("Spire", Enum.PartType.Cylinder, Vector3.new(14, 1.2, 1.2), CFrame.new(0, y + 6, 0) * VERT, bone, nil, 0.2)
		add("Orb", Enum.PartType.Ball, Vector3.one * 3.2, CFrame.new(0, y + 14, 0), crim, Enum.Material.Neon, 0.1)
		for i = 1, 3 do
			add("SpireRing", Enum.PartType.Cylinder, Vector3.new(0.4, 6 - i, 6 - i), CFrame.new(0, y + 2 + i * 2.4, 0) * VERT, bone, nil, 0.25)
		end
		m.Parent = parent
	end
	local parts = {}
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p ~= m.PrimaryPart then
			table.insert(parts, { p = p, base = p.Transparency })
		end
	end
	return m, parts
end

local function respawnLine(dom, ln)
	local reach = dom.radius * 0.96
	local ang, r = math.random() * math.pi * 2, reach * math.sqrt(math.random())
	local pt = Vector3.new(dom.center.X + math.cos(ang) * r, dom.groundY - 2 + math.random() * 36, dom.center.Z + math.sin(ang) * r)
	local d = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.9, math.random() - 0.5)
	d = d.Magnitude > 1e-3 and d.Unit or Vector3.xAxis
	local len = 14 + math.random() * 30
	local th = ln.red and 0.34 or 0.6
	ln.part.Size = Vector3.new(th, th, len)
	ln.part.CFrame = CFrame.lookAt(pt, pt + d)
	ln.age, ln.life = 0, 0.14 + math.random() * 0.24
	ln.part.Transparency = 0
end

local function bodiesInside(dom)
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		local r = m.Parent and m:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - dom.center).Magnitude <= dom.radius then
			table.insert(list, m)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local r = pl.UserId ~= dom.userId and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - dom.center).Magnitude <= dom.radius then
			table.insert(list, pl.Character)
		end
	end
	return list
end

function handlers.ShrineStart(d)
	local PAL = Perks.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local f = castFolder("Domain", d.seal + d.duration + 10)
	local gp = groundAt(hrp.Position)
	local dom = {
		id = d.id, userId = d.userId, char = char, radius = d.radius, seal = d.seal, duration = d.duration, t0 = os.clock(),
		folder = f, center = hrp.Position, groundY = gp.Y, phase = "seal", pillarH = 0, nextGround = 0, nextArc = 0, nextHi = 0, nextBolt = 0, nextStrike = 0,
		highlights = {}, isLocal = isMe(d.userId), pal = PAL,
	}
	domains[d.id] = dom
	-- the sigil on the ground: a red disc under a black one, growing to the boundary
	dom.discOuter = neon("DomainDisc", Enum.PartType.Cylinder, PAL.Shrine, f)
	dom.discOuter.Transparency = 0.78
	dom.discInner = Fx2.part("DomainDiscInner", Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, PAL.LineBlack, f)
	dom.discInner.Transparency = 0.35
	-- the boundary: a ring of pillars of light
	dom.pillars = {}
	for i = 1, 28 do
		local p = neon("DomainPillar", Enum.PartType.Cylinder, PAL.Shrine, f)
		p.Transparency = 0.5
		dom.pillars[i] = p
	end
	-- the ceiling of fog: two dark layers, boiling smoke between them
	dom.ceil = Fx2.part("DomainCeiling", Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, PAL.Fog, f)
	dom.ceil.Transparency = 0.45
	dom.ceil2 = Fx2.part("DomainCeiling2", Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, PAL.Fog, f)
	dom.ceil2.Transparency = 0.6
	Fx2.emitter(dom.ceil, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.Fog, PAL.ShrineDark), LightEmission = 0.1, Rate = 70,
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(2, 7), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 24), NumberSequenceKeypoint.new(1, 46) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
	})
	Fx2.emitter(dom.ceil2, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.Shrine, PAL.Fog), LightEmission = 0.5, Rate = 30,
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 18), NumberSequenceKeypoint.new(1, 34) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }),
	})
	-- the shrine itself fades in and rises while the seal is held
	dom.shrine, dom.shrineParts = buildShrine(f, PAL)
	for _, e in ipairs(dom.shrineParts) do
		e.p.Transparency = 1
	end
	-- two-handed seal at the chest, then both arms flung wide
	local sealed = merge(POSE.Crouch, POSE.SealD)
	pose(char, {
		{ t = 0.25, ease = { "Back", "Out" }, pose = sealed },
		{ t = d.seal, ease = { "Sine", "InOut" }, pose = sealed },
		{ t = d.seal + 0.1, ease = { "Exponential", "Out" }, pose = POSE.Expand },
		{ t = d.seal + 1.5, ease = { "Sine", "InOut" }, pose = POSE.Expand },
	}, d.seal + 1.9)
	sound(SND.Rise, hrp.Position, 1, 0.55)
	sound(SND.Thunder, hrp.Position, 0.9, 0.5)
	loopSound(SND.Hum, hrp.Position, 1, 0.4, d.seal + d.duration + 1)
	-- the incantation: one line every ChantGap seconds while the seal is held, then "DOMAIN EXPANSION"; the domain's
	-- own name is called when it opens (ShrineOpen). The caster always sees the lines, anyone close enough hears them.
	local S = CFG.Shrine
	local function stillSealing()
		return domains[d.id] == dom and dom.phase == "seal"
	end
	local function hears()
		local cam = workspace.CurrentCamera
		return dom.isLocal or (cam ~= nil and (cam.CFrame.Position - dom.center).Magnitude < dom.radius * 2)
	end
	local gap = S.ChantGap or 0.6
	for i, line in ipairs(S.ChantLines or {}) do
		task.delay((S.ChantStart or 0.15) + (i - 1) * gap, function()
			if not stillSealing() then
				return
			end
			if hears() then
				showSubtitle(line, gap - 0.08)
			end
			-- each line pulses a ring of red out across the ground and the air gets heavier
			local g = Vector3.new(dom.center.X, dom.groundY, dom.center.Z)
			FX.ring(f, g + UP * 0.4, UP, 4, 18 + i * 8, PAL.Shrine, 0.7, { alpha = 0.15 })
			sound(SND.HitHeavy, dom.center, 0.5, 0.4 + i * 0.05)
			if dom.isLocal then
				Fx2.shake(0.35 + i * 0.15, 0.3)
			end
		end)
	end
	task.delay(S.ExpansionAt or math.max(d.seal - 0.65, 0), function()
		if stillSealing() and dom.isLocal then
			showTitle("Expansion")
			sound(SND.Thunder, dom.center, 0.8, 0.8)
		end
	end)
	if dom.isLocal then
		letterbox(true, 0.4)
		rootUntil = os.clock() + d.seal + 0.2
		Fx2.envelope({ fov = -10, tint = PAL.Shrine, bright = -0.1, sat = -0.2, contrast = 0.15, attack = d.seal * 0.9, release = 0.1 })
		Fx2.shake(0.6, d.seal, hrp.Position)
	end
end

function handlers.ShrineOpen(d)
	local dom = domains[d.id]
	if not dom then
		return
	end
	local PAL = dom.pal or Perks.pal(d.userId)
	dom.phase, dom.tOpen = "open", os.clock()
	dom.lines = {}
	for i = 1, CFG.Shrine.Lines do
		local red = i % 2 == 0
		local p = neon("DomainLine", Enum.PartType.Block, red and PAL.LineRed or PAL.LineBlack, dom.folder)
		p.Transparency = 1
		dom.lines[i] = { part = p, red = red, age = 0, life = 0, wait = math.random() * 0.35 }
	end
	local f = dom.folder
	local pos, radius = dom.center, dom.radius
	local g = Vector3.new(pos.X, dom.groundY, pos.Z)
	-- the opening: a flash, rings racing to the boundary, a dome of red over a dome of bone
	Fx2.flash(f, pos + UP * 6, radius * 0.7, PAL.ShrineBone, 0.6)
	FX.glow(f, pos + UP * 8, radius * 2.2, PAL.Shrine, 0.6)
	FX.shell(f, pos + UP * 3, 4, radius * 1.05, PAL.Shrine, 0.9, Enum.Material.ForceField)
	FX.shell(f, pos + UP * 3, 3, radius * 0.55, PAL.ShrineBone, 0.4)
	for i = 0, 2 do
		task.delay(i * 0.08, function()
			FX.ring(f, g + UP * 0.5, UP, 6, radius * (1.9 + i * 0.4), i == 1 and PAL.ShrineBone or PAL.Shrine, 0.85)
		end)
	end
	Fx2.shockwave(f, g + UP * 0.6, UP, 8, radius * 2.6, PAL.Shrine, 1.0)
	FX.streaks(f, pos + UP * 5, { count = 130, speed = { 90, 230 }, color = PAL.ShrineBone, color2 = PAL.Shrine, size = 1.7, life = 0.65 })
	Fx2.cracks(Folder, g, UP, radius * 0.5, PAL.Shrine, d.duration)
	sound(SND.Boom, pos, 1, 0.5)
	sound(SND.HitHeavy, pos, 1, 0.45)
	sound(SND.Thunder, pos, 1, 0.65)
	Fx2.shake(3.4, 0.9, pos, 260)
	-- the domain's name, for the caster and for everyone caught inside it
	local cam = workspace.CurrentCamera
	if dom.isLocal or (cam ~= nil and (cam.CFrame.Position - pos).Magnitude < radius * 1.5) then
		showTitle("Shrine")
	end
	if dom.isLocal then
		FX.impact({ tint = PAL.Shrine, lineColor = PAL.ShrineBone, flashAlpha = 0.5 })
		FX.speedLines(0.8)
		Fx2.envelope({ tint = PAL.Shrine, sat = -0.3, contrast = 0.18, bright = -0.04, attack = 0.4, hold = math.max(d.duration - 1.0, 0.1), release = 0.7 })
		task.delay(1.2, function()
			letterbox(false, 0.5)
		end)
	end
	-- a low rumble for as long as the cuts fall
	Fx2.shake(0.7, d.duration, pos, 200)
end

function handlers.ShrineEnd(d)
	local dom = domains[d.id]
	if not dom then
		return
	end
	local PAL = dom.pal or Perks.pal(d.userId)
	domains[d.id] = nil
	local f = dom.folder
	Debris:AddItem(f, 3)
	local pos, radius = d.pos or dom.center, d.radius or dom.radius
	local g = Vector3.new(pos.X, dom.groundY, pos.Z)
	-- the shrine shatters outward, the lines strike all at once for a last instant
	if dom.shrine and dom.shrine.Parent then
		local scatter = d.cancelled and 0.4 or 1
		for _, e in ipairs(dom.shrineParts) do
			if e.p.Parent then
				local away = e.p.Position - pos
				away = away.Magnitude > 1 and away.Unit or UP
				Fx2.tween(e.p, 0.9 * scatter + 0.1, { Position = e.p.Position + away * (22 + math.random() * 28) + UP * math.random() * 12, Transparency = 1 }, Enum.EasingStyle.Quad)
			end
		end
	end
	if dom.lines and not d.cancelled then
		for _, ln in ipairs(dom.lines) do
			dom.center = pos
			ln.wait = 0
			respawnLine(dom, ln)
			ln.life = 0.5
		end
	end
	for _, p in ipairs({ dom.discOuter, dom.discInner, dom.ceil, dom.ceil2 }) do
		Fx2.tween(p, 0.8, { Transparency = 1 })
	end
	for _, p in ipairs(dom.pillars) do
		Fx2.tween(p, 0.6, { Transparency = 1 })
	end
	for _, h in pairs(dom.highlights) do
		h:Destroy()
	end
	dom.highlights = {}
	dom.ending = os.clock() + 0.55 -- lines keep animating through the burst
	domains[d.id .. "-ending"] = dom
	if d.cancelled then
		return
	end
	local fx = castFolder("DomainEnd", 5)
	Fx2.flash(fx, pos + UP * 6, radius * 0.9, PAL.ShrineBone, 0.7)
	FX.light(fx, pos + UP * 8, PAL.Shrine, 16, 60, 1.4)
	FX.shell(fx, pos + UP * 3, 3, radius * 1.15, PAL.Shrine, 0.7, Enum.Material.ForceField)
	FX.shell(fx, pos + UP * 3, 3, radius * 0.7, PAL.ShrineBone, 0.45)
	FX.shell(fx, pos + UP * 3, 2, radius * 1.7, PAL.ShrineDark, 1.1, Enum.Material.ForceField)
	for i = 0, 3 do
		task.delay(i * 0.07, function()
			FX.ring(fx, g + UP * 0.5, UP, 8, radius * (1.5 + i * 0.5), i % 2 == 0 and PAL.ShrineBone or PAL.Shrine, 0.9)
		end)
	end
	Fx2.shockwave(fx, g + UP * 0.6, UP, 10, radius * 3, PAL.Shrine, 1.0)
	for i = 1, 22 do
		local ang = i / 22 * math.pi * 2 + math.random() * 0.2
		local reach = radius * (0.6 + math.random() * 0.7)
		FX.bolt(fx, pos + UP * 3, g + Vector3.new(math.cos(ang) * reach, 0.5, math.sin(ang) * reach), { color = PAL.Shrine, core = PAL.ShrineBone, width = 0.35, segments = 10, jag = 0.14, life = 0.22, restrike = 2 })
	end
	FX.streaks(fx, pos + UP * 3, { count = 160, speed = { 90, 260 }, color = PAL.ShrineBone, color2 = PAL.Shrine, size = 1.9, life = 0.7 })
	FX.sparks(fx, pos + UP * 3, { color = PAL.Shrine, color2 = PAL.ShrineBone, count = 120, speed = { 30, 110 }, size = 1.2 })
	for i = 1, 12 do
		local ang = i / 12 * math.pi * 2
		Fx2.dust(fx, g + Vector3.new(math.cos(ang), 0, math.sin(ang)) * radius * 0.5, 11, 7)
	end
	Fx2.cracks(Folder, g, UP, radius * 0.7, PAL.Shrine, 8)
	sound(SND.Boom, pos, 1, 0.5)
	sound(SND.HitHeavy, pos, 1, 0.5)
	sound(SND.Thunder, pos, 1, 0.7)
	Fx2.shake(5.5, 1.4, pos, 320)
	if dom.isLocal or (myChar() and (select(3, myChar()).Position - pos).Magnitude < radius * 1.4) then
		FX.impact({ tint = PAL.Shrine, lineColor = PAL.ShrineBone, flashAlpha = 0.5 })
		Fx2.envelope({ fov = 22, blur = 12, tint = PAL.Shrine, contrast = 0.25, bright = 0.3, attack = 0.03, hold = 0.1, release = 1.0 })
	end
end

local function updateDomain(dom, dt, clock)
	local PAL = dom.pal or PAL
	local ending = dom.ending ~= nil
	-- the zone follows its owner
	local char = dom.char
	local hrp = char and char.Parent and char:FindFirstChild("HumanoidRootPart")
	if hrp and not ending then
		dom.center = hrp.Position
	end
	if clock >= dom.nextGround then
		dom.nextGround = clock + 0.4
		dom.groundY = groundAt(dom.center).Y
	end
	local center, y0 = dom.center, dom.groundY
	local t = clock - dom.t0
	local grow = math.clamp(t / dom.seal, 0, 1)
	grow = grow * grow * (3 - 2 * grow)
	local dia = dom.radius * 2 * (ending and 1 or grow)
	if not ending then
		dom.discOuter.Size = Vector3.new(0.3, math.max(dia, 0.1), math.max(dia, 0.1))
		dom.discInner.Size = Vector3.new(0.34, math.max(dia - 5, 0.1), math.max(dia - 5, 0.1))
		dom.discOuter.CFrame = CFrame.new(center.X, y0 + 0.14, center.Z) * VERT
		dom.discInner.CFrame = CFrame.new(center.X, y0 + 0.17, center.Z) * VERT
		dom.pillarH = math.min(dom.pillarH + dt * 90, 70)
		for i, p in ipairs(dom.pillars) do
			local ang = i / #dom.pillars * math.pi * 2
			p.Size = Vector3.new(dom.pillarH, 1.6, 1.6)
			p.CFrame = CFrame.new(center.X + math.cos(ang) * dom.radius, y0 + dom.pillarH / 2, center.Z + math.sin(ang) * dom.radius) * VERT
			p.Transparency = 0.45 + 0.35 * math.sin(clock * 9 + i)
		end
		local cdia = dom.radius * 2.3 * (0.3 + 0.7 * grow)
		dom.ceil.Size = Vector3.new(3, cdia, cdia)
		dom.ceil.CFrame = CFrame.new(center.X, y0 + 38, center.Z) * VERT
		dom.ceil2.Size = Vector3.new(2, cdia * 0.8, cdia * 0.8)
		dom.ceil2.CFrame = CFrame.new(center.X, y0 + 30, center.Z) * VERT
		-- the shrine fades in and rises, turning slowly, bobbing
		local rise = math.clamp(t / 1.1, 0, 1)
		rise = rise * rise * (3 - 2 * rise)
		for _, e in ipairs(dom.shrineParts) do
			e.p.Transparency = 1 - (1 - e.base) * rise
		end
		dom.shrine:PivotTo(CFrame.new(center.X, y0 + 14 + rise * 30 + math.sin(clock * 1.3) * 0.8, center.Z) * CFrame.Angles(0, clock * 0.12, 0))
		-- red lightning boiling inside the cloud, and strikes on the boundary during the seal
		if clock >= dom.nextBolt then
			dom.nextBolt = clock + 0.22
			local a1, a2 = math.random() * math.pi * 2, math.random() * math.pi * 2
			local r1, r2 = dom.radius * math.random(), dom.radius * math.random()
			FX.bolt(dom.folder, Vector3.new(center.X + math.cos(a1) * r1, y0 + 38, center.Z + math.sin(a1) * r1), Vector3.new(center.X + math.cos(a2) * r2, y0 + 30, center.Z + math.sin(a2) * r2), { color = PAL.Shrine, core = PAL.ShrineBone, width = 0.5, segments = 8, jag = 0.2, life = 0.14 })
		end
		if dom.phase == "seal" and clock >= dom.nextStrike then
			dom.nextStrike = clock + 0.11
			local ang = math.random() * math.pi * 2
			local at = Vector3.new(center.X + math.cos(ang) * dom.radius, y0, center.Z + math.sin(ang) * dom.radius)
			FX.bolt(dom.folder, at + UP * 120, at, { color = PAL.Shrine, core = PAL.ShrineBone, width = 0.45, segments = 10, jag = 0.12, life = 0.13, restrike = 1 })
			FX.glow(dom.folder, at + UP, 16, PAL.Shrine, 0.25)
		end
	end
	-- the cutting lines: each strikes at full length, burns for a moment, fades; a new one takes its place
	if dom.lines then
		local lines = dom.lines
		for _, ln in ipairs(lines) do
			if ln.life > 0 then
				ln.age += dt
				local k = ln.age / ln.life
				if k >= 1 then
					ln.life = 0
					ln.part.Transparency = 1
					ln.wait = ending and 99 or math.random() * 0.12
				else
					ln.part.Transparency = k * k
				end
			elseif not ending then
				ln.wait -= dt
				if ln.wait <= 0 then
					respawnLine(dom, ln)
				end
			end
		end
	end
	-- bodies inside: red arcs crackle over them, and the nearest are outlined
	if dom.phase == "open" and not ending and clock >= dom.nextArc then
		dom.nextArc = clock + 0.12
		local bodies = bodiesInside(dom)
		local want = {}
		for i, m in ipairs(bodies) do
			local torso = torsoOf(m)
			if torso and i <= 14 then
				FX.arcs(dom.folder, torso.Position, 3, { count = 1, colors = { PAL.LineRed, PAL.ShrineBone }, width = 0.12, life = 0.1 })
				if i <= 10 then
					want[m] = true
				end
			end
		end
		if clock >= dom.nextHi then
			dom.nextHi = clock + 0.4
			for m, h in pairs(dom.highlights) do
				if not want[m] or not m.Parent then
					h:Destroy()
					dom.highlights[m] = nil
				end
			end
			for m in pairs(want) do
				if not dom.highlights[m] then
					local h = Instance.new("Highlight")
					h.Adornee = m
					h.FillColor, h.OutlineColor = PAL.LineRed, PAL.ShrineBone
					h.FillTransparency, h.DepthMode = 0.8, Enum.HighlightDepthMode.AlwaysOnTop
					h.Parent = dom.folder
					dom.highlights[m] = h
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Broadcast dispatch
Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[CarverClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- per-frame playback
local bodyFireSeen = {} -- [model] = last time it stood in a burn zone

-- the arrow being drawn: grows between the hands, fire spiralling round it, the hands' pose decides the rest
local function updateFugaCharge(id, fg, clock, dt)
	local PAL = fg.pal or PAL
	local char = fg.char
	local hrp = char.Parent and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		endFuga(id)
		return
	end
	local fwd = flat(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
	local k = math.clamp((clock - fg.t0) / fg.time, 0, 1)
	local hand = handPoint(char, true) or (hrp.Position + fwd * 3 + UP * 2)
	local nock = hand - fwd * (1 + 2 * k)
	local tip = nock + fwd * (4 + 10 * k)
	fg.arrow:place(nock, tip, 0.25 + 1.45 * k)
	fg.arrow:setIntensity(0.3 + k)
	if fg.helix then
		fg.helix:place((nock + tip) / 2, fwd, dt)
	end
	fg.pos = tip
	if clock >= fg.nextFx then
		fg.nextFx = clock + 0.12
		FX.streaks(Folder, (nock + tip) / 2, { inward = 7 + 12 * k, count = 8, life = 0.45, size = 0.9, color = PAL.FireCore, color2 = PAL.Fire })
	end
	if clock >= fg.nextRing then
		fg.nextRing = clock + 0.32
		FX.ring(Folder, groundAt(hrp.Position) + UP * 0.3, UP, 24, 3, PAL.Fire, 0.55, { ease = "in" })
	end
	-- the caster turns to follow the cursor while drawing
	if fg.isLocal then
		faceUntil, faceDirV = clock + 0.1, flat(cursorTarget() - hrp.Position, fwd)
	end
end

local function updateFugaFlight(id, fg, clock)
	local PAL = fg.pal or PAL
	local el = clock - fg.t0f
	local catch = 1 - math.min(el / 0.12, 1)
	local tip = fg.origin + fg.dir * (fg.speed * el + fg.startOffset * catch)
	fg.arrow:place(tip - fg.dir * 17, tip, 1.7)
	if clock >= fg.nextRing then
		fg.nextRing = clock + 0.035
		Fx2.shockwave(Folder, tip - fg.dir * 6, fg.dir, 5, 22, PAL.Fire, 0.45) -- rings left behind the head
		if math.random() < 0.5 then
			FX.sparks(Folder, tip, { color = PAL.FireCore, color2 = PAL.Fire, count = 6, speed = { 10, 40 }, size = 0.8 })
		end
		local g = groundAt(tip)
		if (g - tip).Magnitude < 12 then
			Fx2.dust(Folder, g, 6, 2)
		end
	end
	if el > 3.5 then
		endFuga(id)
	end
end

local function updateSever(id, sv, clock)
	local PAL = sv.pal or PAL
	local W = CFG.Sever
	local k = math.clamp((clock - sv.t0) / sv.time, 0, 1)
	local h = 2 + (W.Height - 2) * (k ^ 1.4)
	local w = 6 + 4 * k
	local jitter = 1 + (math.random() - 0.5) * 0.06
	local cf = CFrame.lookAt(sv.center, sv.center + sv.dir)
	sv.core.Size = Vector3.new(1.2 * (0.5 + k), h * jitter, w)
	sv.edge.Size = Vector3.new(2.2 * (0.5 + k), h * 1.05 * jitter, w + 2)
	sv.core.CFrame, sv.edge.CFrame = cf, cf
	sv.smoke.Rate = 40 + 120 * k
	if clock >= sv.nextBolt then
		sv.nextBolt = clock + 0.045
		local across = sv.dir:Cross(UP) * ((math.random() - 0.5) * w * 0.7)
		FX.bolt(Folder, sv.center + UP * h / 2 + across, sv.center - UP * h / 2 + across, { color = PAL.RiftEdge, core = PAL.SlashCore, width = 0.12 + 0.25 * k, segments = 8, jag = 0.1, life = 0.1 })
	end
	if clock >= sv.nextWave then
		sv.nextWave = clock + 0.32
		Fx2.shockwave(Folder, sv.center, sv.dir, 4, 40 + 60 * k, PAL.Rift, 0.7) -- distortion rings rolling off the tear
		if sv.isLocal then
			sv.pulse = -sv.pulse -- the view warps in and out with each wave
			Fx2.envelope({ fov = 4 * sv.pulse * (0.5 + k), blur = 2, attack = 0.08, release = 0.25 })
		end
		Fx2.shake(0.3 + 1.0 * k, 0.2, sv.center)
	end
	if clock >= sv.nextStreak then
		sv.nextStreak = clock + 0.14
		FX.streaks(Folder, sv.center, { inward = 18 + 12 * k, count = 10, life = 0.6, size = 1.1, color = PAL.RiftEdge, color2 = PAL.Rift })
	end
end

-- every body standing in a fuga burn zone burns: a flame emitter on its torso while it stays inside
local function updateBurnZones(clock)
	for i = #burnZones, 1, -1 do
		local z = burnZones[i]
		if clock >= z.untilT then
			table.remove(burnZones, i)
		elseif clock >= z.nextBody then
			z.nextBody = clock + 0.15
			local PAL = z.pal or PAL
			local function consider(m)
				local torso = m.Parent and torsoOf(m)
				if torso and (torso.Position - z.pos).Magnitude <= z.radius then
					bodyFireSeen[m] = clock
					if not bodyFire[m] then
						bodyFire[m] = Fx2.emitter(torso, {
							Texture = Fx2.Tex.fire, Color = ColorSequence.new(PAL.FireCore, PAL.Fire, PAL.FireDeep), LightEmission = 1, Rate = 45,
							Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(3, 9), SpreadAngle = Vector2.new(60, 60),
							EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 14, 0), Rotation = NumberRange.new(0, 360),
							Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 0) }),
						})
					end
				end
			end
			for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
				consider(m)
			end
			for _, pl in ipairs(Players:GetPlayers()) do
				if pl.Character then
					consider(pl.Character)
				end
			end
		end
	end
	for m, e in pairs(bodyFire) do
		if not m.Parent or clock - (bodyFireSeen[m] or 0) > 0.5 then
			e.Enabled = false
			Debris:AddItem(e, 1.5)
			bodyFire[m] = nil
		end
	end
end

local function frame(dt)
	local clock = os.clock()
	for id, fg in pairs(fugas) do
		if fg.phase == "charge" and fg.char then
			updateFugaCharge(id, fg, clock, dt)
		elseif fg.phase == "flight" then
			updateFugaFlight(id, fg, clock)
		end
	end
	for id, sv in pairs(severs) do
		updateSever(id, sv, clock)
	end
	updateBurnZones(clock)

	-- zones: animate each, drop finished ones, darken the sky for a client near an open one
	local nearZone, nearPal = false, nil
	local cam = workspace.CurrentCamera
	for key, dom in pairs(domains) do
		updateDomain(dom, dt, clock)
		if dom.ending then
			if clock >= dom.ending then
				domains[key] = nil
			end
		elseif cam and (cam.CFrame.Position - dom.center).Magnitude < dom.radius * 1.7 then
			nearZone, nearPal = true, dom.pal
		end
	end
	skySet(nearZone, nearPal)

	local char, hum, hrp = myChar()
	if hum then
		-- turned toward the aim during a cast
		if clock < faceUntil and faceDirV then
			hum.AutoRotate = false
			faceDir(hrp, faceDirV)
		elseif not hum.AutoRotate then
			hum.AutoRotate = true
		end
		-- held still by a charge or by a zone; otherwise left alone
		if clock < rootUntil or clock < lockUntil then
			savedWalk = savedWalk or hum.WalkSpeed
			hum.WalkSpeed = 0
			if clock < lockUntil then
				savedJump = savedJump or { hum.JumpPower, hum.JumpHeight }
				hum.JumpPower, hum.JumpHeight = 0, 0
			end
		else
			if savedWalk then
				hum.WalkSpeed = savedWalk
				savedWalk = nil
			end
			if savedJump then
				hum.JumpPower, hum.JumpHeight = savedJump[1], savedJump[2]
				savedJump = nil
			end
		end
		-- the zone's micro-impulses: a small random shove every tick for as long as it lasts
		if clock < joltUntil and clock >= nextJolt and hrp then
			nextJolt = clock + 0.1
			local v = Vector3.new(math.random() - 0.5, math.random() * 0.4, math.random() - 0.5)
			if v.Magnitude > 1e-3 then
				hrp:ApplyImpulse(v.Unit * joltStrength * hrp.AssemblyMass)
			end
		end
		-- (the tumble's get-up runs on its own Heartbeat now - see the Knockback handler)
	end

	-- HUD
	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local t = now()
	local timers = {}
	for skill, b in pairs(buttons) do
		local activeUntil = skill == "Shrine" and char and char:GetAttribute("Domain") and char:GetAttribute("DomainUntil")
		if activeUntil and activeUntil > t then
			b.cd.Size = b.horizontal and UDim2.fromScale(0, 1) or UDim2.fromScale(1, 0)
			b.cdText.Text = ""
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(clock * 6)
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
		warn("[CarverClient] frame: " .. tostring(err))
	end
end)

player.CharacterAdded:Connect(function()
	rootUntil, faceUntil, tumbleUntil, lockUntil, joltUntil = 0, 0, 0, 0, 0
	savedWalk, savedJump = nil, nil
	standCheckUntil = 0
	table.clear(zoneHolds)
end)

print(string.format("[CarverClient] ready - Q %s | E %s | R %s | G %s", CFG.Labels.Cleave, CFG.Labels.Fuga, CFG.Labels.Sever, CFG.Labels.Shrine))
