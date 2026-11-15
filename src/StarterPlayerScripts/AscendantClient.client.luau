--!nocheck
local SfxBank = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("SfxBank")) -- (2026-11-12) shared swing / hit variant pools
-- AscendantClient: input, ability bar, flight and local body for the Ascendant kit, plus playback of every cast the
-- server broadcasts (it only renders; hits, damage and ragdolls are decided on the server). Skill-name free: everything
-- skinnable (colours, labels, sounds, timings) comes from ReplicatedStorage.AscendantKit.Config.
--   passive   F / double-tap Space: omnidirectional flight (WASD along the camera, Space up, Shift / Ctrl down)
--   Q Beam    1.5 s charge (aim with the cursor), then 1.5 s of beam (rotation locked)
--   E Warp    a jump behind the enemy under / along the cursor, then an automatic turn kick
--   R Surge   the golden form (R again powers down)
--   G Instinct  a cutscene, then the silver form (G again: the blink flurry)
--   M1        the kit's own four-hit combo
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("AscendantKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Knockback = Remotes:WaitForChild("Knockback")
local GojoClient = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local FX = require(GojoClient:WaitForChild("GojoFX")) -- bolts, arcs, glows, rings, streaks, rubble, impact frames
local Animator = require(GojoClient:WaitForChild("ProceduralAnimator"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib")) -- envelopes, cracks, shake
local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback")) -- damage numbers + hit-confirm
-- (2026-11-11, owner: "have the option to have keybinds") the CFG.Keys / CFG.FlightKey presses below are read through
-- HudShared.Keybinds - logical() turns the physical key into the DEFAULT key whose action the player bound to it - and
-- the key chips draw Keybinds.label() (redrawn on Keybinds.Changed). Config stays the defaults. Movement stays RAW:
-- WASD / arrows / thumbstick, Space (double-tap flight) and flight's Ascend / Descend keys (Space up; Shift / Ctrl / C
-- down) are read straight off the keyboard, so rebinding DASH or SHIFT LOCK never changes how you climb or dive.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local PAL, SND = CFG.Palette, CFG.Sounds
-- PERKS (2026-11-07, kits-D), one table to keep this script's local count down:
--   GOD BLUE skin: a cast whose CASTER's player has Skin == "Alt" (read when its broadcast arrives / when the form's
--     look is built, on every client) draws with AscPerk.ALT = Config.AltPalette over Palette, and the forms take
--     Config.AltForms' hair and eye colours. The handlers shadow PAL with AscPerk.pal(d.userId): the normal look is
--     untouched.
--   AscPerk.cdMul(skill): the local player's cooldown factor, the same as the server's cdFor (CooldownMul, x
--     UltChargeMul for the silver form and its flurry), so the bar counts what the server enforces.
--   AscPerk.trail(char, combo, length): the Trail Pack on this kit's own M1 (see playStrike).
local AscPerk = { ULT = { Instinct = true, Flurry = true } }
do
	local alt = table.clone(PAL)
	for k, v in pairs(CFG.AltPalette or {}) do
		alt[k] = v
	end
	AscPerk.ALT = alt
end
function AscPerk.isAlt(p)
	return typeof(p) == "Instance" and p:IsA("Player") and p:GetAttribute("Skin") == "Alt"
end
function AscPerk.pal(userId)
	return AscPerk.isAlt(Players:GetPlayerByUserId(tonumber(userId) or 0)) and AscPerk.ALT or PAL
end
function AscPerk.cdMul(skill)
	local m = tonumber(player:GetAttribute("CooldownMul")) or 1
	if AscPerk.ULT[skill] then
		m *= tonumber(player:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, as the server does
	local bal = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
	return math.clamp(m, 0.05, 4) * (AscPerk.ULT[skill] and 1 or bal.NON_ULT_COOLDOWN_MUL)
end
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local FWD = Vector3.new(0, 0, -1)
local WHITE = Color3.new(1, 1, 1)
local R = math.rad
local ALONG = CFrame.Angles(0, R(90), 0)  -- turns a Cylinder's axis (X) onto a CFrame's look (-Z)
local VERT = CFrame.Angles(0, 0, R(90))   -- stands a Cylinder upright

local Folder = Instance.new("Folder")
Folder.Name = "Ascendant"
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

local function typing()
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function keyDown(list)
	for _, k in ipairs(list) do
		if UserInputService:IsKeyDown(k) then
			return true
		end
	end
	return false
end

-- parts a ground / cursor ray should look through: effects, flying debris, every body
local FX_FOLDERS = { "KitFX", "FX", "LocalFX", "KitDebris", "DamageNumbers", "VulpineFX", "Tempest", "Carver", "Shifter" }
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
-- (ground point, normal, hit?) under pos
local function groundAt(pos, depth)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -((depth or 80) + 4), 0), groundParams)
	return hit and hit.Position or pos - UP * 3, hit and hit.Normal or UP, hit ~= nil
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

local function handsMid(char)
	local a, b = handPoint(char, false), handPoint(char, true)
	if a and b then
		return (a + b) / 2
	end
	return a or b
end

local function bodyOf(inst)
	local m = inst and inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return m
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- the world point under the cursor (the screen centre on touch-only devices) and the body it is on, if any
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local debugCursor = nil -- Studio test hook: a forced cursor point
local function cursorTarget()
	if debugCursor then
		return debugCursor, nil
	end
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	-- unlike the ground ray, this one lands on bodies too, so a move aimed at an enemy is aimed at the enemy
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
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, cursorParams)
	if hit then
		local body = bodyOf(hit.Instance)
		return hit.Position, body ~= player.Character and body or nil
	end
	return ray.Origin + ray.Direction * 1000, nil
end

-- is a client close enough to `pos` to get the callouts too
local function hears(pos, dist)
	local cam = workspace.CurrentCamera
	return cam ~= nil and pos ~= nil and (cam.CFrame.Position - pos).Magnitude < (dist or 120)
end

local function sound(id, pos, vol, speed, looped)
	if not id or not pos then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.Looped = looped == true
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 420
	s.Parent = Fx2.anchor(Folder, pos, looped and 30 or 8)
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

-- visual building blocks: a glowing part, a stretched ellipsoid, a vertical pillar of light that shoots up and fades
local function neon(name, shape, color, parent)
	return Fx2.part(name, shape, Enum.Material.Neon, color, parent or Folder)
end

local function ellipsoid(name, size, color, material, parent)
	local p = Fx2.part(name, Enum.PartType.Block, material or Enum.Material.Neon, color, parent or Folder)
	p.Size = size
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function pillar(parent, pos, color, core, height, width, life)
	local g = groundAt(pos, 30)
	local base = Vector3.new(pos.X, math.min(g.Y, pos.Y), pos.Z)
	for i, spec in ipairs({ { color, width * 1.8, 0.45 }, { core, width, 0 } }) do
		local c = neon(i == 1 and "PillarGlow" or "PillarCore", Enum.PartType.Cylinder, spec[1], parent)
		c.Transparency = spec[3]
		c.Size = Vector3.new(2, spec[2], spec[2])
		c.CFrame = CFrame.new(base + UP) * VERT
		Fx2.tween(c, life * 0.35, { Size = Vector3.new(height, spec[2] * 1.15, spec[2] * 1.15), CFrame = CFrame.new(base + UP * height / 2) * VERT }, Enum.EasingStyle.Quart)
		task.delay(life * 0.35, function()
			if c.Parent then
				Fx2.tween(c, life * 0.65, { Size = Vector3.new(height * 1.1, 0.1, 0.1), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		Debris:AddItem(c, life + 0.1)
	end
end

-- a thin line of light from a to b that fades (blink trails)
local function streakLine(parent, a, b, color, life, thick)
	local d = (b - a).Magnitude
	if d < 0.5 then
		return
	end
	local p = neon("Streak", Enum.PartType.Block, color, parent)
	p.Size = Vector3.new(thick or 0.35, thick or 0.35, d)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Transparency = 0.15
	Fx2.tween(p, life, { Transparency = 1, Size = Vector3.new(0.05, 0.05, d) })
	Debris:AddItem(p, life + 0.1)
end

-- a glowing ghost of a body at `at` (its root's position; nil = where it stands): every limb and accessory is copied
-- as a translucent shell in the pose it holds right now, then fades
local function afterimage(char, at, color, life, alpha, bodyOnly)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local shift = at and (at - hrp.Position) or Vector3.zero
	local f = castFolder("Afterimage", life + 0.4)
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.9 and (p.Parent == char or (not bodyOnly and (p.Parent:IsA("Accessory") or p.Parent.Name == "AscSpikes"))) then
			local ok, g = pcall(function()
				return p:Clone()
			end)
			if ok and g then
				for _, ch in ipairs(g:GetChildren()) do
					if not ch:IsA("SpecialMesh") then
						ch:Destroy()
					end
				end
				g.Anchored = true
				g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow, g.Massless = false, false, false, false, true
				g.Material = Enum.Material.Neon
				g.Color = color
				g.Transparency = alpha
				if g:IsA("MeshPart") then
					pcall(function()
						g.TextureID = ""
					end)
				end
				local sm = g:FindFirstChildOfClass("SpecialMesh")
				if sm then
					sm.TextureId = ""
				end
				g.CFrame = p.CFrame + shift
				g.Parent = f
				Fx2.tween(g, life, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
	end
end

-- a body vanishes for an instant (the blink between leaving and arriving)
local function hideFor(char, t)
	local list = {}
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") or p:IsA("Decal") then
			table.insert(list, p)
			p.LocalTransparencyModifier = 1
		end
	end
	task.delay(t, function()
		for _, p in ipairs(list) do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- poses (degrees; shoulder flexion +X, elbow bend +X, hip forward +X, knee bend -X, waist lean forward -X,
-- waist / root turn left +Y, neck chin up +X, arm out to the side: RightShoulder +Z / LeftShoulder -Z)
local POSE = {
	-- the beam's charge: hands cupped at the right hip, the body wound to the right, a low wide stance
	Cup = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.55, 0) }, Waist = { -4, -45, 0 }, Neck = { 2, 36, 0 },
		RightShoulder = { -20, 0, -10 }, RightElbow = { 95, 0, 0 }, RightWrist = { 0, 0, -25 },
		LeftShoulder = { 58, 0, 78 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 25 },
		LeftHip = { 30, 0, -14 }, LeftKnee = { -42, 0, 0 }, RightHip = { -8, 0, 16 }, RightKnee = { -26, 0, 0 },
	},
	-- the release: both palms thrust straight out together
	Thrust = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, Waist = { -8, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 90, 0, -10 }, RightElbow = { 4, 0, 0 }, RightWrist = { -50, 0, 0 },
		LeftShoulder = { 90, 0, 10 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -50, 0, 0 },
		LeftHip = { 36, 0, -10 }, LeftKnee = { -38, 0, 0 }, RightHip = { -24, 0, 12 }, RightKnee = { -12, 0, 0 },
	},
	-- bracing against the beam's push halfway through
	ThrustBrace = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.65, 0) }, Waist = { -13, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 94, 0, -10 }, RightElbow = { 8, 0, 0 }, RightWrist = { -50, 0, 0 },
		LeftShoulder = { 94, 0, 10 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -50, 0, 0 },
		LeftHip = { 42, 0, -10 }, LeftKnee = { -46, 0, 0 }, RightHip = { -30, 0, 12 }, RightKnee = { -10, 0, 0 },
	},
	-- two fingers to the forehead
	Focus = {
		RightShoulder = { 90, 0, -70 }, RightElbow = { 70, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 4, 0, -10 }, LeftElbow = { 12, 0, 0 }, Neck = { -10, 0, 0 }, Waist = { 0, 8, 0 },
	},
	-- the turn kick: chamber, spin, leg out, land
	KickChamber = { Root = { 0, -40, 0 }, RightHip = { 75, 0, 22 }, RightKnee = { -95, 0, 0 }, Waist = { 0, 10, 0 }, RightShoulder = { 30, 0, 30 }, LeftShoulder = { 30, 0, -30 } },
	KickOut = { Root = { 0, -150, 12 }, RightHip = { 82, 0, 68 }, RightKnee = { -6, 0, 0 }, LeftKnee = { -14, 0, 0 }, Waist = { 0, -16, 22 }, RightShoulder = { 20, 0, 70 }, LeftShoulder = { 20, 0, -70 }, Neck = { 0, 30, 0 } },
	KickThrough = { Root = { 0, -270, 6 }, RightHip = { 60, 0, 40 }, RightKnee = { -30, 0, 0 }, Waist = { 0, -6, 10 }, RightShoulder = { 20, 0, 40 }, LeftShoulder = { 20, 0, -40 } },
	KickLand = { Root = { 0, -360, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, 0 }, LeftShoulder = { 0, 0, 0 }, Neck = { 0, 0, 0 } },
	-- the M1 combo
	JabL = { LeftShoulder = { 90, 0, 4 }, LeftElbow = { 4, 0, 0 }, RightShoulder = { 46, 0, 14 }, RightElbow = { 110, 0, 0 }, Waist = { -6, -24, 0 }, Neck = { 0, 18, 0 } },
	CrossR = { RightShoulder = { 92, 0, -4 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 46, 0, -14 }, LeftElbow = { 110, 0, 0 }, Waist = { -10, 30, 0 }, Neck = { 0, -22, 0 } },
	Upper = { Root = { 0, 0, 0, pos = Vector3.new(0, 0.25, 0) }, LeftShoulder = { 160, 0, 8 }, LeftElbow = { 40, 0, 0 }, RightShoulder = { 30, 0, 18 }, RightElbow = { 95, 0, 0 }, Waist = { 12, -14, 0 }, Neck = { 14, 0, 0 }, RightHip = { 50, 0, 0 }, RightKnee = { -70, 0, 0 } },
	Guard = { RightShoulder = { 46, 0, 14 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 46, 0, -14 }, LeftElbow = { 110, 0, 0 }, Waist = { 0, 0, 0 } },
	-- the golden power-up: a low squat, fists driven down and back, chest out, head thrown back
	Scream = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.75, 0) }, Waist = { 12, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { -24, 0, 26 }, RightElbow = { 62, 0, 0 }, LeftShoulder = { -24, 0, -26 }, LeftElbow = { 62, 0, 0 },
		RightHip = { 28, 0, 22 }, RightKnee = { -52, 0, 0 }, LeftHip = { 28, 0, -22 }, LeftKnee = { -52, 0, 0 },
	},
	ScreamShake = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.8, 0) }, Waist = { 14, 3, 0 }, Neck = { 34, -2, 0 },
		RightShoulder = { -28, 0, 30 }, RightElbow = { 66, 0, 0 }, LeftShoulder = { -28, 0, -30 }, LeftElbow = { 66, 0, 0 },
		RightHip = { 30, 0, 22 }, RightKnee = { -56, 0, 0 }, LeftHip = { 30, 0, -22 }, LeftKnee = { -56, 0, 0 },
	},
	Flare = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.35, 0) }, Waist = { 6, 0, 0 }, Neck = { 8, 0, 0 },
		RightShoulder = { 10, 0, 62 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 10, 0, -62 }, LeftElbow = { 20, 0, 0 },
		RightHip = { 16, 0, 20 }, RightKnee = { -26, 0, 0 }, LeftHip = { 16, 0, -20 }, LeftKnee = { -26, 0, 0 },
	},
	-- the silver form's breath: loose arms, head bowed, eyes closed; the chest rises and falls
	BreatheIn = { Waist = { 6, 0, 0 }, Neck = { -16, 0, 0 }, RightShoulder = { 6, 0, 14 }, RightElbow = { 18, 0, 0 }, LeftShoulder = { 6, 0, -14 }, LeftElbow = { 18, 0, 0 } },
	BreatheOut = { Waist = { 1, 0, 0 }, Neck = { -20, 0, 0 }, RightShoulder = { 2, 0, 9 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 2, 0, -9 }, LeftElbow = { 12, 0, 0 } },
	Awake = { Waist = { 2, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 8, 0, 20 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 8, 0, -20 }, LeftElbow = { 24, 0, 0 } },
	Release = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.3, 0) }, Waist = { 8, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 14, 0, 48 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 14, 0, -48 }, LeftElbow = { 14, 0, 0 },
		RightHip = { 12, 0, 16 }, RightKnee = { -20, 0, 0 }, LeftHip = { 12, 0, -16 }, LeftKnee = { -20, 0, 0 },
	},
	BreatheDeep = { Waist = { 10, 0, 0 }, Neck = { -12, 0, 0 }, RightShoulder = { 10, 0, 18 }, RightElbow = { 22, 0, 0 }, LeftShoulder = { 10, 0, -18 }, LeftElbow = { 22, 0, 0 } },
	-- gathering before the burst: a slight crouch, fists drawn to the hips
	Gather = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.35, 0) }, Waist = { -6, 0, 0 }, Neck = { -4, 0, 0 },
		RightShoulder = { -10, 0, 8 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { -10, 0, -8 }, LeftElbow = { 80, 0, 0 },
		RightHip = { 14, 0, 10 }, RightKnee = { -26, 0, 0 }, LeftHip = { 14, 0, -10 }, LeftKnee = { -26, 0, 0 },
	},
	-- the burst lifts the body off the ground, arms flung down and out
	Levitate = {
		Root = { 0, 0, 0, pos = Vector3.new(0, 1.4, 0) }, Waist = { 10, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { -8, 0, 55 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -8, 0, -55 }, LeftElbow = { 10, 0, 0 },
		RightHip = { 6, 0, 6 }, RightKnee = { -18, 0, 0 }, LeftHip = { 12, 0, -6 }, LeftKnee = { -30, 0, 0 },
		RightAnkle = { -30, 0, 0 }, LeftAnkle = { -30, 0, 0 },
	},
	LevitateHold = {
		Root = { 0, 0, 0, pos = Vector3.new(0, 1.65, 0) }, Waist = { 6, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { -4, 0, 46 }, RightElbow = { 16, 0, 0 }, LeftShoulder = { -4, 0, -46 }, LeftElbow = { 16, 0, 0 },
		RightHip = { 8, 0, 6 }, RightKnee = { -22, 0, 0 }, LeftHip = { 14, 0, -6 }, LeftKnee = { -34, 0, 0 },
		RightAnkle = { -30, 0, 0 }, LeftAnkle = { -30, 0, 0 },
	},
	-- the form's calm guard: one open palm forward, the other hand low
	Stance = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.15, 0) }, Waist = { -2, 18, 0 }, Neck = { 0, -14, 0 },
		LeftShoulder = { 62, 0, -6 }, LeftElbow = { 38, 0, 0 }, RightShoulder = { 18, 0, 14 }, RightElbow = { 70, 0, 0 },
		LeftHip = { 20, 0, -8 }, LeftKnee = { -24, 0, 0 }, RightHip = { -6, 0, 10 }, RightKnee = { -14, 0, 0 },
	},
	-- flight: an easy hover (one knee drawn up), and the glide (arms back, legs trailing)
	HoverA = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.1, 0) }, Waist = { -3, 0, 0 }, Neck = { 2, 0, 0 },
		RightShoulder = { 8, 0, 16 }, RightElbow = { 26, 0, 0 }, LeftShoulder = { 8, 0, -16 }, LeftElbow = { 26, 0, 0 },
		RightHip = { 26, 0, 4 }, RightKnee = { -46, 0, 0 }, LeftHip = { 6, 0, -4 }, LeftKnee = { -14, 0, 0 },
		RightAnkle = { -20, 0, 0 }, LeftAnkle = { -24, 0, 0 },
	},
	HoverB = {
		Root = { 0, 0, 0, pos = Vector3.new(0, 0.12, 0) }, Waist = { -1, 0, 0 }, Neck = { 4, 0, 0 },
		RightShoulder = { 12, 0, 20 }, RightElbow = { 32, 0, 0 }, LeftShoulder = { 12, 0, -20 }, LeftElbow = { 32, 0, 0 },
		RightHip = { 30, 0, 4 }, RightKnee = { -52, 0, 0 }, LeftHip = { 9, 0, -4 }, LeftKnee = { -18, 0, 0 },
		RightAnkle = { -22, 0, 0 }, LeftAnkle = { -26, 0, 0 },
	},
	GlideA = {
		Root = { 0, 0, 0 }, Waist = { 0, 0, 0 }, Neck = { 40, 0, 0 },
		RightShoulder = { 172, 0, -30 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { -18, 0, -8 }, LeftElbow = { 8, 0, 0 },
		RightHip = { -4, 0, 2 }, RightKnee = { -6, 0, 0 }, LeftHip = { -2, 0, -2 }, LeftKnee = { -22, 0, 0 },
		RightAnkle = { -45, 0, 0 }, LeftAnkle = { -45, 0, 0 },
	},
	GlideB = {
		Root = { 0, 0, 0 }, Waist = { 1, 0, 0 }, Neck = { 42, 0, 0 },
		RightShoulder = { 168, 0, -27 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -22, 0, -10 }, LeftElbow = { 12, 0, 0 },
		RightHip = { -6, 0, 2 }, RightKnee = { -10, 0, 0 }, LeftHip = { -3, 0, -2 }, LeftKnee = { -16, 0, 0 },
		RightAnkle = { -45, 0, 0 }, LeftAnkle = { -45, 0, 0 },
	},
}

-- looping flight clips (the first and last keys match, so restarting is seamless)
local CLIP = {
	Hover = { length = 2.4, fadeIn = 0.25, fadeOut = 0, keys = {
		{ t = 0, pose = POSE.HoverA }, { t = 1.2, ease = { "Sine", "InOut" }, pose = POSE.HoverB }, { t = 2.4, ease = { "Sine", "InOut" }, pose = POSE.HoverA },
	} },
	Glide = { length = 1.0, fadeIn = 0.25, fadeOut = 0, keys = {
		{ t = 0, pose = POSE.GlideA }, { t = 0.5, ease = { "Sine", "InOut" }, pose = POSE.GlideB }, { t = 1.0, ease = { "Sine", "InOut" }, pose = POSE.GlideA },
	} },
}

-- a body playing a cast pose is left alone by the flight loop until the pose is done
local castPoseUntil = setmetatable({}, { __mode = "k" })
local function pose(char, keys, length)
	if char and char.Parent then
		Animator.stopAll(char, 0.08)
		Animator.play(char, { length = length, fadeIn = 0.08, fadeOut = 0.25, keys = keys })
		castPoseUntil[char] = os.clock() + length
	end
end

local KICK_KEYS = {
	{ t = 0.06, ease = { "Quad", "Out" }, pose = POSE.KickChamber },
	{ t = 0.16, ease = { "Quad", "Out" }, pose = POSE.KickOut },
	{ t = 0.27, ease = { "Linear", "In" }, pose = POSE.KickThrough },
	{ t = 0.4, ease = { "Quad", "Out" }, pose = POSE.KickLand },
}
local STRIKE = {
	{ keys = { { t = 0.04, pose = POSE.Guard }, { t = 0.1, ease = { "Exponential", "Out" }, pose = POSE.JabL }, { t = 0.3, ease = { "Quad", "InOut" }, pose = POSE.Guard } }, length = 0.42 },
	{ keys = { { t = 0.04, pose = POSE.Guard }, { t = 0.1, ease = { "Exponential", "Out" }, pose = POSE.CrossR }, { t = 0.3, ease = { "Quad", "InOut" }, pose = POSE.Guard } }, length = 0.42 },
	{ keys = { { t = 0.05, pose = POSE.Guard }, { t = 0.13, ease = { "Exponential", "Out" }, pose = POSE.Upper }, { t = 0.36, ease = { "Quad", "InOut" }, pose = POSE.Guard } }, length = 0.5 },
	{ keys = KICK_KEYS, length = 0.6 },
}

---------------------------------------------------------------------------------------------------
-- local body: rooting while casting, facing the aim, being knocked back
local rootUntil, faceUntil, faceDirV = 0, 0, nil
local tumbleUntil = 0
local selfKnock = false
local resistToken
local flight = nil -- this client's own flight: { char, hum, hrp, att, lv, vf, ao, vel, mass, t0 }
local stopFlight -- (reason) defined with the flight controller

local function faceDir(hrp, dir)
	local f = flat(dir, nil)
	if hrp and f then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + f)
	end
end

local function eachAssembly(char, fn)
	local done = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			local root = part.AssemblyRootPart
			if root and not done[root] then
				done[root] = true
				fn(root)
			end
		end
	end
end

-- this client owns its body: knockback from any Ascendant fighter is applied here. Duration 0 = a shove, no tumble.
Knockback.OnClientEvent:Connect(function(vel, duration, keep)
	local char, hum, hrp = myChar()
	if not char or typeof(vel) ~= "Vector3" or char:GetAttribute("SuperArmor") then
		return
	end
	if char:GetAttribute("AscForm") == "Instinct" then
		return -- evaded: the server already blinked this body away
	end
	keep = tonumber(keep) or 0
	duration = tonumber(duration) or 1.5
	if duration <= 0 then
		if not flight then
			hrp:ApplyImpulse((vel - hrp.AssemblyLinearVelocity * (1 - keep)) * hrp.AssemblyMass)
		end
		return
	end
	if flight then
		stopFlight("knocked")
	end
	tumbleUntil = math.max(tumbleUntil, os.clock() + duration)
	selfKnock = true
	hum.PlatformStand = true
	selfKnock = false
	eachAssembly(char, function(root)
		root:ApplyImpulse((vel - root.AssemblyLinearVelocity * (1 - keep)) * root.AssemblyMass)
	end)
end)

-- any OTHER kit knocking this body down: the silver form refuses it (stands straight back up and blinks away), the
-- golden form shrugs part of it off (less speed, a shorter tumble), and flight always ends
-- (2026-11-08, "if someone hits goku out of the sky I want him to be stunned for twice as long") a PvP stun or ragdoll
-- landing on this body in the air knocks it out of the sky: the flight ends and he falls. ServerScriptService.PvP
-- doubles that stun (AIR_STUN_MUL) because the body was Flying when it was hit; no flying again until it wears off.
local function pvpStunned(char)
	if char:GetAttribute("SuperArmor") or char:GetAttribute("Guardian") or char:GetAttribute("AscForm") == "Instinct" then
		return false
	end
	return (tonumber(char:GetAttribute("StunnedUntil")) or 0) > workspace:GetServerTimeNow()
		or char:GetAttribute("Ragdolled") == true
end

local function watchBody(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local function shotDown()
		if flight and flight.char == char and player.Character == char and hum.Health > 0 and pvpStunned(char) then
			stopFlight("knocked")
		end
	end
	char:GetAttributeChangedSignal("StunnedUntil"):Connect(shotDown)
	char:GetAttributeChangedSignal("Ragdolled"):Connect(shotDown)
	hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		if not hum.PlatformStand or selfKnock or player.Character ~= char or hum.Health <= 0 then
			return
		end
		local form = char:GetAttribute("AscForm")
		if form == "Instinct" then
			-- impulses land on the next physics step, so the throw is cancelled after it (for a few steps, in case
			-- the knockback keeps coming)
			task.spawn(function()
				for _ = 1, 3 do
					RunService.Heartbeat:Wait()
					if not hum.Parent then
						return
					end
					hum.PlatformStand = false
					eachAssembly(char, function(root)
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
					end)
				end
				if not flight then
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
			Request:FireServer("Dodge", {})
			return
		end
		if flight then
			stopFlight("knocked")
		end
		local resist = char:GetAttribute("StaggerResist")
		if type(resist) == "number" and resist > 0 then
			task.spawn(function()
				RunService.Heartbeat:Wait() -- after the step that applied the throw
				eachAssembly(char, function(root)
					root.AssemblyLinearVelocity *= (1 - resist)
					root.AssemblyAngularVelocity *= (1 - resist)
				end)
			end)
			local token = {}
			resistToken = token
			task.delay(0.35 + 1.1 * (1 - resist), function()
				if resistToken == token and hum.Parent and hum.PlatformStand and hum.Health > 0 then
					hum.PlatformStand = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Passive: omnidirectional flight. A LinearVelocity on the root does the moving, a VectorForce cancels gravity, an
-- AlignOrientation lines the body up with its flight path (upright in a hover, flat out in level flight, head-first in
-- a dive, banked into turns), and the humanoid is put in its Physics state so it applies no forces of its own.
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

local debugInput = nil -- Studio test hook: Vector3(right, up, back) replacing the keyboard

-- the steering input as (x = right, z = back): the default control module when the place has one, else the keys
-- themselves (WASD / arrows), a gamepad's left stick, and finally whatever is steering the humanoid (a touch stick)
local MOVE_KEYS = {
	{ Enum.KeyCode.W, 0, -1 }, { Enum.KeyCode.Up, 0, -1 }, { Enum.KeyCode.S, 0, 1 }, { Enum.KeyCode.Down, 0, 1 },
	{ Enum.KeyCode.A, -1, 0 }, { Enum.KeyCode.Left, -1, 0 }, { Enum.KeyCode.D, 1, 0 }, { Enum.KeyCode.Right, 1, 0 },
}
local function moveInput()
	if controls then
		local ok, v = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(v) == "Vector3" and v.Magnitude > 0.01 then
			return v
		end
	end
	if not typing() then
		local x, z = 0, 0
		for _, k in ipairs(MOVE_KEYS) do
			if UserInputService:IsKeyDown(k[1]) then
				x += k[2]
				z += k[3]
			end
		end
		x, z = math.clamp(x, -1, 1), math.clamp(z, -1, 1)
		if x ~= 0 or z ~= 0 then
			return Vector3.new(x, 0, z)
		end
	end
	local okPad, pad = pcall(function()
		if UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
			for _, st in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
				if st.KeyCode == Enum.KeyCode.Thumbstick1 and st.Position.Magnitude > 0.2 then
					return Vector3.new(st.Position.X, 0, -st.Position.Y)
				end
			end
		end
		return nil
	end)
	if okPad and pad then
		return pad
	end
	local _, hum = myChar()
	if hum and hum.MoveDirection.Magnitude > 0.05 then
		local f = flat(workspace.CurrentCamera.CFrame.LookVector, FWD)
		local md = hum.MoveDirection
		return Vector3.new(md:Dot(f:Cross(UP)), 0, -md:Dot(f))
	end
	return Vector3.zero
end

local function bodyMass(char)
	local m = 0
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and not p.Massless then
			m += p:GetMass()
		end
	end
	return m
end

local function startFlight()
	if flight or not equipped() then
		return
	end
	local char, hum, hrp = myChar()
	if not char or hum.PlatformStand or hum.Sit or os.clock() < tumbleUntil or pvpStunned(char) then
		return
	end
	local mass = bodyMass(char)
	local att = Instance.new("Attachment")
	att.Name = "AscFlightAttachment"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Name = "AscFlightVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.max(mass * 900, 25000)
	local v0 = hrp.AssemblyLinearVelocity
	lv.VectorVelocity = Vector3.new(v0.X * 0.5, math.max(v0.Y, 0) * 0.3 + 16, v0.Z * 0.5) -- a little lift-off
	lv.Parent = hrp
	local vf = Instance.new("VectorForce")
	vf.Name = "AscAntiGravity"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.new(0, mass * workspace.Gravity, 0)
	vf.Parent = hrp
	local ao = Instance.new("AlignOrientation")
	ao.Name = "AscFlightAlign"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = false
	ao.MaxTorque = math.max(mass * 4000, 1e5)
	ao.Responsiveness = 18
	ao.CFrame = CFrame.lookAt(Vector3.zero, flat(hrp.CFrame.LookVector, FWD))
	ao.Parent = hrp
	hum.AutoRotate = false
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	flight = { char = char, hum = hum, hrp = hrp, att = att, lv = lv, vf = vf, ao = ao, vel = lv.VectorVelocity, mass = mass, t0 = os.clock(), face = flat(hrp.CFrame.LookVector, FWD) }
	Request:FireServer("Flight", { on = true })
	-- lift-off: a ring of wind and dust thrown out from the feet
	local g, _, gh = groundAt(hrp.Position, 20)
	local f = castFolder("LiftOff", 3)
	if gh then
		FX.ring(f, g + UP * 0.3, UP, 2, 18, PAL.Wind, 0.5, { alpha = 0.35 })
		Fx2.dust(f, g, 3, 8)
	end
	FX.streaks(f, hrp.Position - UP * 2, { dir = -UP, spread = 35, count = 14, speed = { 30, 60 }, color = WHITE, color2 = PAL.KiPale, size = 0.4, life = 0.3 })
	sound(SND.Whoosh, hrp.Position, 0.8, 1.15)
end

stopFlight = function(reason)
	local fl = flight
	if not fl then
		return
	end
	flight = nil
	for _, o in ipairs({ fl.lv, fl.vf, fl.ao, fl.att }) do
		if o and o.Parent then
			o:Destroy()
		end
	end
	local hum = fl.hum
	if hum and hum.Parent then
		hum.AutoRotate = true
		if hum.Health > 0 and not hum.PlatformStand then
			-- stand the body back up first (it may be flying flat out or head-down), all of it at once
			local hrp = fl.hrp
			if hrp and hrp.Parent and fl.char.Parent then
				local face = fl.face or flat(workspace.CurrentCamera.CFrame.LookVector, FWD)
				fl.char:PivotTo(CFrame.lookAt(hrp.Position, hrp.Position + face))
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
			hum:ChangeState(reason == "land" and Enum.HumanoidStateType.Landed or Enum.HumanoidStateType.Freefall)
		end
	end
	if reason ~= "respawn" then
		Request:FireServer("Flight", { on = false })
	end
	if reason == "land" and fl.hrp and fl.hrp.Parent then
		local g, _, gh = groundAt(fl.hrp.Position, 12)
		if gh then
			local f = castFolder("Land", 3)
			FX.ring(f, g + UP * 0.3, UP, 2, 12, PAL.Wind, 0.4, { alpha = 0.4 })
			Fx2.dust(f, g, 2.5, 6)
		end
	end
end

local landParams = RaycastParams.new()
landParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFlight(dt, clock)
	local fl = flight
	if not fl then
		return
	end
	local char, hum, hrp = myChar()
	if char ~= fl.char or not equipped() or hum.PlatformStand or hum.Sit or not fl.lv.Parent then
		stopFlight("lost")
		return
	end
	if hum:GetState() ~= Enum.HumanoidStateType.Physics then
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end
	local F = CFG.Flight
	local mul = char:GetAttribute("AscFlightMul") or 1
	local speed = F.Speed * mul
	local cam = workspace.CurrentCamera
	local mv = debugInput or moveInput() -- x = right, z = back (the control module's convention)
	local vert = 0
	if debugInput then
		vert = debugInput.Y
	elseif not typing() then
		vert = (keyDown(CFG.AscendKeys) and 1 or 0) - (keyDown(CFG.DescendKeys) and 1 or 0)
	end
	-- omnidirectional: W / S fly along the camera, A / D strafe level, Space / Shift go straight up / down, all blended
	-- into one direction and flown at the same speed whichever way it points. The usual over-the-shoulder camera looks a
	-- little down at the body, so a camera within LevelBand degrees of level counts as level (W flies straight ahead);
	-- past that the path tips up or down, reaching straight up / down when the camera does.
	local camLook = cam.CFrame.LookVector
	local pitch = math.asin(math.clamp(camLook.Y, -1, 1))
	local band = R(F.LevelBand or 25)
	local tip = 0
	if math.abs(pitch) > band then
		tip = math.sign(pitch) * (math.abs(pitch) - band) / (R(90) - band) * R(90)
	end
	local flatLook = flat(camLook, flat(hrp.CFrame.LookVector, FWD))
	local fwd = flatLook * math.cos(tip) + UP * math.sin(tip)
	local want = flatLook:Cross(UP) * mv.X - fwd * mv.Z + UP * vert
	if want.Magnitude > 1 then
		want = want.Unit
	end
	local target = want * speed
	local rooted = clock < rootUntil
	if rooted then
		target = Vector3.zero -- a cast holds the body still in the air
	end
	fl.vel = fl.vel:Lerp(target, 1 - math.exp(-dt * F.Response))
	fl.lv.VectorVelocity = fl.vel
	fl.vf.Force = Vector3.new(0, fl.mass * workspace.Gravity, 0)
	local look = flat(cam.CFrame.LookVector, flat(hrp.CFrame.LookVector, FWD))
	if clock < faceUntil and faceDirV then
		-- a cast faces its aim (pitch included), standing upright in the air
		local d = faceDirV.Magnitude > 1e-3 and faceDirV.Unit or look
		if math.abs(d.Y) > 0.98 then
			d = look
		end
		fl.ao.CFrame = CFrame.lookAt(Vector3.zero, d)
		fl.bank, fl.lastFace = 0, nil
	else
		-- the body lines up with its flight path: it turns to face where it is going, then tips its head along the path
		-- (upright in a hover or a straight climb, flat out like an arrow in level flight, head-first in a dive) and
		-- banks into turns. A slow drift only leans it a little.
		local v = fl.vel
		local spd = v.Magnitude
		local horiz = v * FLAT
		if horiz.Magnitude > 4 then
			fl.face = horiz.Unit
		elseif spd < 4 then
			fl.face = look
		end
		local face = fl.face or look
		local w = math.clamp((spd - 5) / (speed * 0.55), 0, 1) * (F.Align or 1)
		local elev = spd > 1 and math.asin(math.clamp(v.Y / spd, -1, 1)) or R(90)
		local tilt = (R(90) - elev) * w
		local yawRate = 0
		if fl.lastFace then
			yawRate = math.asin(math.clamp(fl.lastFace:Cross(face).Y, -1, 1)) / math.max(dt, 1e-3)
		end
		fl.lastFace = face
		local bank = math.clamp(-yawRate * 0.22, -R(F.Roll), R(F.Roll)) * w
		fl.bank = (fl.bank or 0) + (bank - (fl.bank or 0)) * (1 - math.exp(-dt * 5))
		-- pitch the head toward the path, then roll about the body's long axis
		fl.ao.CFrame = CFrame.lookAt(Vector3.zero, face) * CFrame.Angles(-tilt, 0, 0) * CFrame.Angles(0, fl.bank, 0)
	end
	-- sinking onto the ground on purpose (Shift / Ctrl, or a steep dive) lands; skimming low over it does not
	if (vert < 0 or fl.vel.Y < -0.6 * speed) and clock - fl.t0 > 0.5 and not rooted then
		landParams.FilterDescendantsInstances = ignoreList()
		local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -(F.LandDistance + 2), 0), landParams)
		if hit and hrp.Position.Y - hit.Position.Y <= F.LandDistance then
			stopFlight("land")
		end
	end
end

-- every flyer (this client included): a wind aura on the lower torso that grows with speed, and the looping hover /
-- glide pose (a cast pose takes over while it plays)
local flyFx = {} -- [char] = { att, wind, streak, ring, track, kind }

local function buildWind(char)
	local torso = char:FindFirstChild("LowerTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")
	if not torso then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "AscWindAura"
	att.Position = Vector3.new(0, -0.5, 0)
	att.Parent = torso
	local st = { att = att }
	st.wind = Fx2.emitter(att, {
		Texture = Fx2.Tex.smoke, Color = ColorSequence.new(PAL.Wind), LightEmission = 0.35, Rate = CFG.Flight.AuraRate,
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(6, 12), EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(55, 55), Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-140, 140),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 4.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) }),
	})
	st.streak = Fx2.emitter(att, {
		Texture = FX.TEX.glow, Color = ColorSequence.new(WHITE, PAL.KiPale), LightEmission = 1, Rate = 4,
		Lifetime = NumberRange.new(0.16, 0.28), Speed = NumberRange.new(18, 32), EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(28, 28), Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2),
		Size = NumberSequence.new(0.35, 0), Transparency = NumberSequence.new(0.35, 1),
	})
	st.ring = Fx2.emitter(att, {
		Texture = FX.TEX.ring, Color = ColorSequence.new(PAL.Wind), LightEmission = 0.6, Rate = 2.5,
		Lifetime = NumberRange.new(0.6), Speed = NumberRange.new(5), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.zero,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
	})
	return st
end

local function removeWind(char, st)
	for _, e in ipairs({ st.wind, st.streak, st.ring }) do
		e.Enabled = false
	end
	Debris:AddItem(st.att, 1.2)
	if st.track then
		st.track:stop(0.25)
	end
end

local function syncFlyers(clock)
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if char and char.Parent then
			local flying = char:GetAttribute("Flying") == true
			if pl == player then
				flying = flight ~= nil -- this client's own flight shows at once, without waiting for the server
			end
			local st = flyFx[char]
			if flying and not st then
				st = buildWind(char)
				flyFx[char] = st
			elseif st and not flying then
				removeWind(char, st)
				flyFx[char] = nil
				st = nil
			end
			if st then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local spd = hrp and hrp.AssemblyLinearVelocity.Magnitude or 0
				st.wind.Rate = CFG.Flight.AuraRate * (1 + spd / 25)
				st.streak.Rate = spd > 15 and spd * 0.6 or 3
				if (castPoseUntil[char] or 0) <= clock then
					local kind = spd > 26 and "Glide" or "Hover"
					if not st.track or not st.track:isPlaying() or st.kind ~= kind then
						if st.track and st.kind ~= kind then
							st.track:stop(0.3)
						end
						st.track = Animator.play(char, CLIP[kind])
						st.kind = kind
					end
				else
					st.track = nil
				end
			end
		end
	end
	for char, st in pairs(flyFx) do
		if not char.Parent then
			flyFx[char] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "AscendantHUD"
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
	l.TextColor3 = WHITE
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- cinematic letterbox bars for the cutscene
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
	local h = on and 0.11 or 0
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
local titleFade = {}
local function showTitle(key, hold)
	local co = CFG.Callouts[key]
	if not co then
		return
	end
	local token = {}
	titleToken = token
	for _, tw in ipairs(titleFade) do
		tw:Cancel()
	end
	titleFade = {}
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
	task.delay(hold or 1.6, function()
		if titleToken ~= token then
			return
		end
		for _, o in ipairs({ title, kanji }) do
			table.insert(titleFade, Fx2.tween(o, 0.45, { TextTransparency = 1 }))
		end
		for _, o in ipairs({ titleStroke, kanjiStroke }) do
			table.insert(titleFade, Fx2.tween(o, 0.45, { Transparency = 1 }))
		end
	end)
end

-- shouted lines (the beam's syllables, the power-up scream), low on the screen
local subtitle = uiText(gui, {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromScale(0.7, 0.07),
	Text = "", TextTransparency = 1, Font = Enum.Font.GothamBlack, ZIndex = 40,
})
local subStroke = uiStroke(subtitle, Color3.fromRGB(8, 30, 70), 2.5, 1, true)
local subScale = Instance.new("UIScale")
subScale.Parent = subtitle
local subToken
local subFade = {}
local function showSubtitle(text, hold, color)
	local token = {}
	subToken = token
	-- a fade still running from the previous line would drag this one back out, so stop it first
	for _, tw in ipairs(subFade) do
		tw:Cancel()
	end
	subFade = {}
	subtitle.Text = text
	subtitle.TextColor3 = color or WHITE
	subtitle.TextTransparency = 0
	subStroke.Transparency = 0
	subScale.Scale = 1.4
	Fx2.tween(subScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(hold or 0.65, function()
		if subToken ~= token then
			return
		end
		subFade = { Fx2.tween(subtitle, 0.25, { TextTransparency = 1 }), Fx2.tween(subStroke, 0.25, { Transparency = 1 }) }
	end)
end

-- ability bar, laid out like the other kits': two skills, the M1, the big beam button, the silver form on its own
-- wide button above the row, and the flight toggle beside it
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

local COOLDOWN = { Beam = CFG.Beam.Cooldown, Warp = CFG.Warp.Cooldown, Surge = CFG.Surge.Cooldown, Instinct = CFG.Instinct.Cooldown, Flurry = CFG.Instinct.Flurry.Cooldown }
local cooldownEnd = { Beam = 0, Warp = 0, Surge = 0, Instinct = 0, Flurry = 0 }
local buttons = {}
local tryStrike -- the M1 (defined with the combo playback)

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	local target, body = cursorTarget()
	Request:FireServer(skill, { aim = workspace.CurrentCamera.CFrame.LookVector, target = target, model = body })
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
	shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(140, 140, 150))
	shade.Rotation = 90
	shade.Parent = b
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.35), 2, 0.1)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.46, 0.46)
	orb.BackgroundColor3 = WHITE
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local og = Instance.new("UIGradient")
	og.Color = ColorSequence.new(co.c0, co.c1)
	og.Rotation = 45
	og.Parent = orb
	uiStroke(orb, co.c1:Lerp(WHITE, 0.5), 1.5, 0.3)
	local glyph = uiText(orb, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.11), Text = co.glyph or "", ZIndex = 2 })
	uiStroke(glyph, co.c1:Lerp(Color3.new(0, 0, 0), 0.7), 1.5, 0, true)
	local label = uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 12), Position = UDim2.new(0, 4, 1, big and -21 or -18), Text = CFG.Labels[id] or id, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.85)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11) the chip shows the player's bound key (Keybinds), not the Config default
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys[id]), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys[id])
	end)
	local hint = uiText(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Text = co.hint or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.35) })
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
	buttons[id] = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, label = label, hint = hint }
	b.Activated:Connect(function()
		request(id)
	end)
end
skillButton("Surge", 72, -280) -- the Reversal Red slot
skillButton("Warp", 72, -198) -- the Lapse Blue slot
skillButton("Beam", 104, 0) -- the Hollow Purple slot

-- the kit's own M1, in the same slot and style as the other kits' punch
do
	local b = Instance.new("TextButton")
	b.Name = "Strike"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(72, 72)
	b.Position = UDim2.new(1, -116, 1, -16)
	b.BackgroundColor3 = Color3.fromRGB(46, 34, 20)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	uiStroke(b, Color3.fromRGB(255, 214, 140), 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = WHITE
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(255, 244, 225), Color3.fromRGB(255, 186, 80))
	g.Rotation = 45
	g.Parent = orb
	uiText(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = CFG.Labels.Strike, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(24, 16, 8)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	uiText(chip, { Size = UDim2.fromScale(1, 1), Text = "M1", Font = Enum.Font.GothamBold, ZIndex = 2 })
	b.Activated:Connect(function()
		if tryStrike then
			tryStrike()
		end
	end)
end

-- the silver form on its own wide button above the row (the Domain Expansion slot); during the form it is the flurry
local pillLabel, pillSub
do
	local co = CFG.Callouts.Instinct
	local b = Instance.new("TextButton")
	b.Name = "Instinct"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, 0, 1, -132)
	b.Size = UDim2.fromOffset(186, 36)
	b.BackgroundColor3 = WHITE
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.4), 2, 0.1)
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
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys.Instinct), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys.Instinct)
	end)
	pillLabel = uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Instinct, ZIndex = 2 })
	pillSub = uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
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
	buttons.Instinct = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Instinct")
	end)
end

-- the flight toggle (shows whether flight is on)
local flightPill, flightStroke, flightText
do
	local co = CFG.Callouts.Flight
	local b = Instance.new("TextButton")
	b.Name = "Flight"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -196, 1, -132)
	b.Size = UDim2.fromOffset(112, 36)
	b.BackgroundColor3 = Color3.fromRGB(14, 20, 34)
	b.BackgroundTransparency = 0.15
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	flightStroke = uiStroke(b, co.c1, 2, 0.4)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = Color3.fromRGB(6, 10, 18)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.FlightKey), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.FlightKey)
	end)
	flightText = uiText(b, { Size = UDim2.new(1, -42, 0, 15), Position = UDim2.fromOffset(36, 4), Text = CFG.Labels.Flight, ZIndex = 2 })
	uiText(b, { Size = UDim2.new(1, -42, 0, 10), Position = UDim2.fromOffset(36, 21), Text = "2x SPACE", Font = Enum.Font.GothamBold, TextColor3 = co.c1, ZIndex = 2 })
	flightPill = b
	b.Activated:Connect(function()
		if flight then
			stopFlight("toggle")
		else
			startFlight()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- input: skills on their keys, M1, flight (F, or Space twice in quick succession)
local lastSpace = 0
local cutscene = nil -- the silver form's cutscene while it plays (input waits)

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if equipped() and not cutscene and tryStrike then
		tryStrike()
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if not equipped() or typing() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		local clock = os.clock()
		if clock - lastSpace <= CFG.Flight.DoubleTap then
			lastSpace = 0
			if flight then
				stopFlight("toggle")
			else
				startFlight()
			end
		else
			lastSpace = clock
		end
		return
	end
	if gpe or cutscene then
		return
	end
	-- (2026-11-11) the action the player bound to this key (Keybinds); Space above stays raw - it is movement
	local key = Keybinds.logical(input.KeyCode)
	if key == CFG.FlightKey then
		if flight then
			stopFlight("toggle")
		else
			startFlight()
		end
		return
	end
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		if tryStrike then
			tryStrike(true) -- true: a real press (holding it keeps the combo going)
		end
		return
	end
	for skill, k in pairs(CFG.Keys) do
		if key == k then
			request(skill)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- cast playback
local handlers = {}

function handlers.Cooldown(d)
	if cooldownEnd[d.skill] ~= nil and typeof(d.ends) == "number" then
		cooldownEnd[d.skill] = d.ends
	end
end

-- a batch of hits from the server: damage numbers over every body, plus the hit-confirm for the attacker
function handlers.Hits(d)
	Feedback.hits(d, PAL.Numbers)
end

---------------------------------------------------------------------------------------------------
-- Skill 1: the beam. The charge is a hyper-dense ball held between the cupped hands: a white-hot core in a blue body
-- in a crackling force-field shell, light streaming into it, lightning crawling over it, a syllable on each beat.
-- The release is a continuous cylinder of three layers with a burning head, rings racing down it, lightning licking
-- its surface, two spirals of light running its length, and the ground torn up beneath it.
local beams = {} -- [id] = { phase = "charge" | "fire" | "fade", ... }
local beamAimUntil, nextAimSend = 0, 0

local function beamColors(form, pal)
	local PAL = pal or PAL
	return {
		core = PAL.KiCore, body = PAL.Ki, deep = PAL.KiDeep, pale = PAL.KiPale,
		arc = form == "Surge" and PAL.Gold or form == "Instinct" and PAL.Silver or PAL.KiPale,
	}
end

local function beamOrigin(b)
	local hrp = b.char and b.char:FindFirstChild("HumanoidRootPart")
	if hrp and b.dir then
		return hrp.Position + UP * 0.6 + b.dir * 3
	end
	return b.origin
end

local function endBeam(b)
	if b.ended then
		return
	end
	b.ended = true
	for _, h in ipairs(b.helices or {}) do
		h:destroy()
	end
	if b.loop then
		b.loop:Stop()
	end
	if b.rocks and not b.rocks.dead then
		b.rocks:drop()
	end
	Debris:AddItem(b.f, 0.6)
end

function handlers.BeamCharge(d)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local f = castFolder("Beam", d.time + d.fire + 8)
	local sc = d.scale or 1
	local c = beamColors(d.form, AscPerk.pal(d.userId))
	local b = {
		id = d.id, char = char, f = f, mine = isMe(d.userId), t0 = os.clock(), charge = d.time, fireTime = d.fire, scale = sc,
		phase = "charge", c = c, nextArc = 0, nextDust = 0, nextRing = 0, nextSpark = 0, chant = 0, len = 0, ringD = 0, hp = { 0, 0 },
	}
	b.core = neon("ChargeCore", Enum.PartType.Ball, c.core, f)
	b.body = neon("ChargeBody", Enum.PartType.Ball, c.body, f)
	b.body.Transparency = 0.3
	b.shell = Fx2.part("ChargeShell", Enum.PartType.Ball, Enum.Material.ForceField, c.pale, f)
	b.light = Instance.new("PointLight")
	b.light.Color, b.light.Shadows = c.pale, false
	b.light.Parent = b.core
	-- light pours into the ball from all around
	b.halo = Fx2.part("ChargeHalo", Enum.PartType.Ball, Enum.Material.SmoothPlastic, c.pale, f)
	b.halo.Transparency = 1
	b.halo.Size = Vector3.one * 9 * sc
	b.inflow = Fx2.emitter(b.halo, {
		Texture = FX.TEX.glow, Color = ColorSequence.new(c.core, c.body), LightEmission = 1, Rate = 80,
		Lifetime = NumberRange.new(0.26, 0.32), Speed = NumberRange.new(14 * sc, 17 * sc),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2.2),
		Size = NumberSequence.new(0.55, 0.12), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.15), NumberSequenceKeypoint.new(1, 0.1) }),
	})
	b.glint = Fx2.emitter(b.core, {
		Texture = FX.TEX.star, Color = ColorSequence.new(WHITE, c.pale), LightEmission = 1, Rate = 30,
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(2, 7), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.45, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	})
	pose(char, {
		{ t = 0.18, ease = { "Back", "Out" }, pose = POSE.Cup },
		{ t = d.time, ease = { "Sine", "InOut" }, pose = POSE.Cup },
	}, d.time + 0.12)
	sound(SND.Charge, hrp.Position, 1, 0.9)
	b.loop = sound(SND.Hum, hrp.Position, 0.55, 0.8, true)
	if b.mine then
		local clock = os.clock()
		rootUntil = clock + d.time + d.fire + 0.15
		beamAimUntil = clock + d.time
		nextAimSend = 0
		Fx2.envelope({ fov = -7, sat = -0.15, contrast = 0.12, attack = d.time, hold = 0.05, release = 0.3 })
	end
	-- the ground answers a grounded caster: pebbles lift and circle
	local g, _, gh = groundAt(hrp.Position, 12)
	if gh and hrp.Position.Y - g.Y < 8 then
		b.ground = g
		b.rocks = FX.liftRocks(f, g, 10, 12)
	end
	beams[d.id] = b
end

local function updateCharge(b, dt, clock)
	local pos = handsMid(b.char)
	if not pos then
		return
	end
	local hrp = b.char:FindFirstChild("HumanoidRootPart")
	if hrp then
		pos += (pos - hrp.Position) * FLAT * 0.15 -- the ball sits just out from the hip, between the palms
	end
	local k = math.clamp((clock - b.t0) / b.charge, 0, 1)
	local sc = b.scale
	local pulse = 1 + math.sin(clock * 34) * 0.07
	local dCore, dBody, dShell = (0.4 + 1.1 * k) * sc, (0.6 + 1.9 * k) * sc * pulse, (0.9 + 2.7 * k) * sc * pulse
	b.core.Size, b.body.Size, b.shell.Size = Vector3.one * dCore, Vector3.one * dBody, Vector3.one * dShell
	local cf = CFrame.new(pos)
	b.core.CFrame, b.body.CFrame, b.shell.CFrame, b.halo.CFrame = cf, cf, cf * CFrame.Angles(clock * 3, clock * 2, 0), cf
	b.light.Brightness = 2 + 6 * k
	b.light.Range = 8 + 18 * k
	b.pos = pos
	-- lightning crawls over the ball, more as it fills
	if clock >= b.nextArc then
		b.nextArc = clock + 0.13 - 0.07 * k
		FX.arcs(b.f, pos, dShell * 0.5, { count = 1 + math.floor(k * 2.5), colors = { b.c.core, b.c.pale, b.c.arc }, width = 0.05 + 0.06 * k, life = 0.1, jag = 0.35 })
		if k > 0.45 and math.random() < 0.55 then
			FX.bolt(b.f, pos, pos + FX.randUnit() * (3 + 4 * k) * sc, { color = b.c.arc, width = 0.08, life = 0.08, jag = 0.3 })
		end
	end
	-- a syllable on every beat, each with a ring of light snapping shut on the ball
	local el = clock - b.t0
	local B = CFG.Beam
	while b.chant < #B.Chant and el >= (B.ChantAt[b.chant + 1] or math.huge) do
		b.chant += 1
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the chant syllable subtitle is gone; ring + zap stay)
		local cam = workspace.CurrentCamera
		FX.ring(b.f, pos, (cam.CFrame.Position - pos).Unit, 10 * sc, 0.8, b.c.pale, 0.28, { ease = "in" })
		sound(SND.Zap, pos, 0.35, 1.1 + 0.15 * b.chant)
	end
	-- dust swirls round a grounded caster's feet
	if b.ground and clock >= b.nextDust then
		b.nextDust = clock + 0.22
		Fx2.dust(b.f, b.ground + FX.randUnit() * FLAT * 3, 2 + 2 * k, 2)
	end
	if b.loop then
		b.loop.PlaybackSpeed = 0.8 + 0.7 * k
		if b.loop.Parent then
			b.loop.Parent.CFrame = cf
		end
	end
	if b.mine then
		Fx2.shake(0.2 + 0.9 * k, 0.08)
	end
end

function handlers.BeamFire(d)
	local b = beams[d.id]
	if not b then
		-- (joined mid-cast) a beam with no charge seen: build the minimum
		local char = charOf(d.userId)
		if not char then
			return
		end
		local f = castFolder("Beam", d.time + 8)
		b = { id = d.id, char = char, f = f, mine = isMe(d.userId), scale = d.scale or 1, c = beamColors(d.form, AscPerk.pal(d.userId)), nextArc = 0, nextDust = 0, nextRing = 0, nextSpark = 0, ringD = 0, hp = { 0, 0 } }
		b.core = neon("ChargeCore", Enum.PartType.Ball, b.c.core, f)
		beams[d.id] = b
	end
	local c, f, sc = b.c, b.f, b.scale
	b.phase = "fire"
	b.dir, b.radius, b.range, b.headSpeed = d.dir, d.radius, d.range, d.headSpeed
	b.tf, b.fireTime, b.len, b.targetLen = os.clock(), d.time, 0, d.range
	if b.inflow then
		b.inflow.Enabled = false
	end
	if b.rocks and not b.rocks.dead then
		b.rocks:drop()
		b.rocks = nil
	end
	-- the beam: a white-hot core, a blue body, a crackling force-field skin, a deep-blue haze, a burning head
	b.beamCore = neon("BeamCore", Enum.PartType.Cylinder, c.core, f)
	b.beamBody = neon("BeamBody", Enum.PartType.Cylinder, c.body, f)
	b.beamBody.Transparency = 0.28
	b.beamSkin = Fx2.part("BeamSkin", Enum.PartType.Cylinder, Enum.Material.ForceField, c.pale, f)
	b.beamHaze = neon("BeamHaze", Enum.PartType.Cylinder, c.deep, f)
	b.beamHaze.Transparency = 0.8
	b.head = neon("BeamHead", Enum.PartType.Ball, c.pale, f)
	b.head.Transparency = 0.1
	b.headSkin = Fx2.part("BeamHeadSkin", Enum.PartType.Ball, Enum.Material.ForceField, c.core, f)
	Fx2.emitter(b.head, {
		Texture = FX.TEX.glow, Color = ColorSequence.new(c.core, c.body), LightEmission = 1, Rate = 60,
		Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(20, 50), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * sc), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0.2, 1),
	})
	-- light streaming down the beam's length
	b.flow = Fx2.part("BeamFlow", Enum.PartType.Block, Enum.Material.SmoothPlastic, c.pale, f)
	b.flow.Transparency = 1
	b.flowE = Fx2.emitter(b.flow, {
		Texture = FX.TEX.glow, Color = ColorSequence.new(WHITE, c.pale), LightEmission = 1, Rate = 200,
		Lifetime = NumberRange.new(0.12, 0.22), Speed = NumberRange.new(140, 240), EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2.6),
		Size = NumberSequence.new(0.7 * sc, 0), Transparency = NumberSequence.new(0.2, 1),
	})
	b.lights = {}
	for i = 1, 3 do
		local a = Fx2.part("BeamLight", Enum.PartType.Block, Enum.Material.SmoothPlastic, c.pale, f)
		a.Transparency = 1
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = c.pale, 40, 5, false
		l.Parent = a
		b.lights[i] = a
	end
	b.helices = {
		FX.helix(f, { c.core, c.pale, c.arc }, d.radius * 1.12, 0.5 * sc),
		FX.helix(f, { c.pale, c.core }, d.radius * 1.3, 0.35 * sc),
	}
	pose(b.char, {
		{ t = 0.07, ease = { "Exponential", "Out" }, pose = POSE.Thrust },
		{ t = d.time * 0.5, ease = { "Sine", "InOut" }, pose = POSE.ThrustBrace },
		{ t = d.time, ease = { "Sine", "InOut" }, pose = POSE.Thrust },
	}, d.time + 0.35)
	local origin = beamOrigin(b)
	FX.ring(f, origin, d.dir, 2, 22 * sc, c.pale, 0.45)
	FX.ring(f, origin, d.dir, 1, 14 * sc, c.core, 0.3)
	FX.glow(f, origin, 22 * sc, c.core, 0.35)
	FX.streaks(f, origin, { dir = d.dir, spread = 40, count = 30, speed = { 80, 180 }, color = c.core, color2 = c.body, size = 1, life = 0.3 })
	sound(SND.Boom, origin, 1.1, 0.8)
	sound(SND.Thunder, origin, 0.9, 1.25)
	if b.loop then
		b.loop.Volume = 0.9
		b.loop.PlaybackSpeed = 1.6
	end
	-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (Beam title + FireCall subtitle removed)
	if b.mine then
		local clock = os.clock()
		faceUntil, faceDirV = clock + d.time + 0.1, d.dir -- rotation locked for the whole fire
		beamAimUntil = 0
		FX.impact({ tint = c.pale, lineColor = c.core, flashAlpha = 0.3, lineTime = 0.3 })
		FX.speedLines(d.time, { color = c.core, alpha = 0.45, count = 50, inner = 0.38 })
		Fx2.envelope({ fov = 9, contrast = 0.15, bright = 0.05, attack = 0.06, hold = math.max(d.time - 0.2, 0), release = 0.4 })
	end
end

local function placeCyl(part, origin, dir, len, dia)
	part.Size = Vector3.new(math.max(len, 0.1), dia, dia)
	part.CFrame = CFrame.lookAt(origin + dir * (len / 2), origin + dir * len) * ALONG
end

local function updateFire(b, dt, clock)
	local el = clock - b.tf
	local origin = beamOrigin(b)
	local dir = b.dir
	local head = math.min(b.range, b.headSpeed * el)
	local len = math.max(math.min(head, b.targetLen or head), 0.5)
	b.len = len
	local tip = origin + dir * len
	local grow = math.clamp(el / 0.1, 0, 1)
	local flick = 1 + math.sin(clock * 47) * 0.05 + math.sin(clock * 23) * 0.04
	local rr = b.radius * grow * flick
	placeCyl(b.beamCore, origin, dir, len, rr * 0.85)
	placeCyl(b.beamBody, origin, dir, len, rr * 1.55)
	placeCyl(b.beamSkin, origin, dir, len, rr * 2)
	placeCyl(b.beamHaze, origin, dir, len, rr * 2.7)
	b.head.Size = Vector3.one * rr * 2.5
	b.head.CFrame = CFrame.new(tip)
	b.headSkin.Size = Vector3.one * rr * 3.3 * (1 + math.sin(clock * 30) * 0.08)
	b.headSkin.CFrame = CFrame.new(tip) * CFrame.Angles(clock * 4, clock * 3, 0)
	if b.core then
		b.core.Size = Vector3.one * rr * 1.6
		b.core.CFrame = CFrame.new(origin - dir * 0.6)
	end
	if b.body then
		b.body.Size = Vector3.one * rr * 2.1
		b.body.CFrame = CFrame.new(origin - dir * 0.6)
	end
	if b.shell then
		b.shell.Size = Vector3.one * rr * 2.6
		b.shell.CFrame = CFrame.new(origin - dir * 0.6) * CFrame.Angles(clock * 3, clock * 2, 0)
	end
	if b.halo then
		b.halo.CFrame = CFrame.new(origin)
	end
	b.flow.Size = Vector3.new(rr * 1.3, rr * 1.3, len)
	b.flow.CFrame = CFrame.lookAt(origin + dir * (len / 2), tip)
	b.flowE.Rate = math.min(len * 4, 700)
	for i, a in ipairs(b.lights) do
		a.CFrame = CFrame.new(origin + dir * len * ({ 0.12, 0.5, 0.92 })[i])
	end
	if b.loop and b.loop.Parent then
		b.loop.Parent.CFrame = CFrame.new(origin)
	end
	-- two spirals of light chase each other down the beam
	for i, h in ipairs(b.helices) do
		b.hp[i] = (b.hp[i] + dt * (i == 1 and 330 or 260)) % len
		h:place(origin + dir * b.hp[i], dir, dt)
	end
	-- rings racing down its length
	if clock >= b.nextRing then
		b.nextRing = clock + 0.035
		b.ringD = (b.ringD + 15) % len
		FX.ring(b.f, origin + dir * b.ringD, dir, rr * 1.2, rr * 2.7, b.c.pale, 0.22, { alpha = 0.25 })
	end
	-- lightning licking its surface
	if clock >= b.nextArc then
		b.nextArc = clock + 0.05
		local a0 = math.random() * len
		local r1, u1 = FX.perp(dir)
		local ang = math.random() * math.pi * 2
		local off = (r1 * math.cos(ang) + u1 * math.sin(ang)) * rr * 1.05
		FX.bolt(b.f, origin + dir * a0 + off, origin + dir * math.min(a0 + 8 + math.random() * 10, len) + off * 1.35, { color = b.c.arc, width = 0.12, life = 0.09, jag = 0.25 })
	end
	-- where something stops it: a churning blast against the wall
	if b.blocked and clock >= b.nextSpark then
		b.nextSpark = clock + 0.06
		FX.sparks(b.f, tip, { color = b.c.core, color2 = b.c.body, count = 14, speed = { 30, 90 }, size = 0.8 })
		FX.glow(b.f, tip, rr * 5, b.c.pale, 0.2)
		Fx2.dust(b.f, tip, 3, 2)
	end
	-- a low beam rips the ground up beneath it
	if clock >= b.nextDust then
		b.nextDust = clock + 0.08
		local at = origin + dir * (math.random() * len)
		local g, _, gh = groundAt(at, 20)
		if gh and at.Y - g.Y < rr + 4 then
			Fx2.dust(b.f, g, 3, 3)
			FX.sparks(b.f, g, { color = b.c.pale, count = 6, dir = UP, spread = 50, speed = { 20, 50 }, size = 0.5 })
		end
	end
	if b.mine then
		Fx2.shake(1.1, 0.08)
	else
		Fx2.shake(1.0, 0.08, origin, 140)
	end
end

function handlers.BeamTick(d)
	local b = beams[d.id]
	if b then
		b.targetLen = d.len
		b.blocked = d.blocked
	end
end

-- the beam thins out and dies
local function updateFade(b, clock)
	local a = math.clamp((clock - b.fade0) / 0.35, 0, 1)
	local origin = beamOrigin(b) or b.origin
	if not origin or not b.dir then
		b.dieAt = clock
		return
	end
	local rr = b.radius * (1 - a) ^ 2
	local len = b.len
	if b.beamCore then
		placeCyl(b.beamCore, origin, b.dir, len, math.max(rr * 0.85, 0.05))
		placeCyl(b.beamBody, origin, b.dir, len, math.max(rr * 1.55, 0.05))
		placeCyl(b.beamSkin, origin, b.dir, len, math.max(rr * 2, 0.05))
		placeCyl(b.beamHaze, origin, b.dir, len, math.max(rr * 2.7, 0.05))
		b.beamHaze.Transparency = 0.8 + 0.2 * a
		b.beamBody.Transparency = 0.28 + 0.72 * a
		b.beamCore.Transparency = a
		b.head.Transparency = 0.1 + 0.9 * a
		b.headSkin.Transparency = a
		b.flowE.Enabled = false
	end
	for _, p in ipairs({ b.core, b.body, b.shell }) do
		if p then
			p.Transparency = math.max(p.Transparency, a)
		end
	end
	if a >= 1 then
		b.dieAt = clock
	end
end

function handlers.BeamEnd(d)
	local b = beams[d.id]
	if b then
		b.phase, b.fade0 = "fade", os.clock()
		b.origin = beamOrigin(b)
		if b.loop then
			b.loop:Stop()
		end
		for _, h in ipairs(b.helices or {}) do
			h:destroy()
		end
		b.helices = {}
	end
	local f = castFolder("BeamBlast", 8)
	local pos, r0 = d.pos, d.radius
	local c = b and b.c or beamColors(nil)
	-- the end of the beam detonates
	FX.shell(f, pos, 1, r0 * 0.6, c.core, 0.35)
	FX.shell(f, pos, 2, r0 * 0.9, c.pale, 0.55)
	FX.shell(f, pos, 3, r0 * 1.15, c.pale, 0.75, Enum.Material.ForceField)
	FX.ring(f, pos, UP, 4, r0 * 2.6, c.pale, 0.7)
	FX.ring(f, pos, d.dir, 3, r0 * 2, c.core, 0.5)
	FX.glow(f, pos, r0 * 2.4, c.core, 0.5)
	FX.streaks(f, pos, { count = 50, speed = { 90, 220 }, color = c.core, color2 = c.body, size = 1.4, life = 0.5 })
	FX.sparks(f, pos, { count = 60, speed = { 40, 140 }, color = c.core, color2 = c.body, size = 1 })
	FX.rubble(f, pos, { count = 16, radius = 6, up = { 40, 80 }, out = { 25, 60 } })
	FX.light(f, pos, c.pale, 12, 60, 0.8)
	local g, n, gh = groundAt(pos, 30)
	if gh and (pos - g).Magnitude < r0 then
		Fx2.cracks(f, g, n, r0 * 0.7, c.pale, 6)
	end
	sound(SND.Boom, pos, 1.2, 0.85)
	sound(SND.Thunder, pos, 0.8, 1.1)
	Fx2.shake(2.6, 0.6, pos, 220)
	if isMe(d.userId) then
		FX.impact({ tint = c.pale, lineColor = c.core, flashAlpha = 0.35 })
	end
end

function handlers.BeamCancel(d)
	local b = beams[d.id]
	if b then
		beams[d.id] = nil
		endBeam(b)
		if b.char then
			Animator.stopAll(b.char, 0.2)
			castPoseUntil[b.char] = 0
		end
	end
	if isMe(d.userId) then
		rootUntil, faceUntil, beamAimUntil = 0, 0, 0
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 2: instant transmission. Two fingers to the brow; the body leaves an afterimage and a pop, is gone for an
-- instant, and appears in a flash behind the target, already turning into the kick.
function handlers.WarpStart(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	pose(char, {
		{ t = 0.1, ease = { "Back", "Out" }, pose = POSE.Focus },
		{ t = d.time + 0.1, pose = POSE.Focus },
	}, d.time + 0.15)
	local head = char:FindFirstChild("Head")
	if head then
		local f = castFolder("WarpFocus", 2)
		local p = head.Position + head.CFrame.LookVector * (head.Size.Z * 0.6) + UP * head.Size.Y * 0.2
		FX.glow(f, p, 3, PAL.KiPale, d.time + 0.05)
		FX.sparks(f, p, { count = 8, speed = { 3, 9 }, size = 0.25, color = PAL.KiCore, color2 = PAL.KiPale, accel = Vector3.zero, life = d.time })
		sound(SND.Zap, p, 0.35, 2.2)
	end
	if isMe(d.userId) then
		Fx2.envelope({ fov = -4, attack = d.time, release = 0.15 })
	end
end

function handlers.WarpGo(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local f = castFolder("Warp", 3)
	-- where it left: a ghost, a streak straight up, a sharp pop
	afterimage(char, d.from, PAL.KiPale, 0.4, 0.4)
	FX.streaks(f, d.from, { dir = UP, spread = 10, count = 18, speed = { 60, 120 }, color = PAL.KiCore, color2 = PAL.KiPale, size = 0.7, life = 0.25 })
	FX.glow(f, d.from, 9, PAL.KiPale, 0.18)
	FX.ring(f, d.from, UP, 1, 9, PAL.KiPale, 0.25)
	sound(SND.Zap, d.from, 0.7, 2.6)
	sound(SND.Hit, d.from, 0.4, 3)
	-- where it arrives: light snapping in
	FX.glow(f, d.to, 10, PAL.KiCore, 0.2)
	FX.ring(f, d.to, UP, 9, 0.5, PAL.KiPale, 0.2, { ease = "in" })
	FX.sparks(f, d.to, { count = 14, speed = { 10, 30 }, color = PAL.KiCore, color2 = PAL.KiPale, size = 0.35 })
	sound(SND.Zap, d.to, 0.8, 2.3)
	hideFor(char, 0.07)
	if d.target then
		pose(char, KICK_KEYS, 0.6)
	end
	if isMe(d.userId) then
		FX.flash(PAL.KiCore, 0.25, 0.15)
		FX.speedLines(0.2, { color = PAL.KiCore, alpha = 0.6, count = 40 })
		Fx2.envelope({ fov = 10, attack = 0.02, release = 0.25 })
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (Warp title removed)
	end
end

function handlers.WarpKick(d)
	local PAL = AscPerk.pal(d.userId)
	if d.miss then
		local char = charOf(d.userId)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			sound(SND.Whoosh, hrp.Position, 0.6, 1.3)
		end
		return
	end
	local f = castFolder("Kick", 3)
	local pos, dir = d.pos, d.dir
	FX.glow(f, pos, 14, PAL.KiPale, 0.25)
	FX.ring(f, pos, dir, 1, 16, PAL.KiCore, 0.3)
	FX.streaks(f, pos, { dir = dir, spread = 30, count = 26, speed = { 80, 170 }, color = PAL.KiCore, color2 = PAL.Ki, size = 1 })
	FX.sparks(f, pos, { dir = dir, spread = 50, count = 22, speed = { 30, 80 }, color = WHITE, color2 = PAL.KiPale, size = 0.5 })
	Fx2.shockwave(f, pos, dir, 2, 14, PAL.KiPale, 0.35)
	sound(SND.HitHeavy, pos, 1, 1.05)
	sound(SND.Hit, pos, 0.7, 1.6)
	Fx2.shake(1.6, 0.25, pos)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.KiPale, lineColor = PAL.KiCore, flashAlpha = 0.3, lineTime = 0.3 })
	end
end

---------------------------------------------------------------------------------------------------
-- M1: the combo (jab, cross, uppercut, spinning kick). This client plays its own swing at once; everyone else's comes
-- from the broadcast. The forms colour the hits: golden shockwaves, silver afterimages and sharp silver bursts.
local localStrike = { combo = 0, last = -math.huge, lock = 0 }

-- PERKS (2026-11-07, kits-D) + the M1 WHOOSH (2026-11-10). Every other fighter's punch drags a whoosh Trail on the
-- striking limb (GojoClient.whoosh, run from playPunch), but this kit owns its M1 (OwnM1), and the first version of
-- this function returned early unless the caster had a Trail Pack look equipped - so a Goku without the perk swung
-- with no swoosh at all. Now every swing whooshes, the same Trail GojoClient.whoosh builds (1.4 wide, 0.26 s life):
-- jab left hand, cross right, uppercut left, and the spinning kick trails all four limbs like the other kits' spin
-- moves. It runs white into the form's colour (ki blue, gold in the golden form, silver-blue in the silver form; GOD
-- BLUE through AltPalette), and the caster's EquipTrail restyles it through PerkShared.TrailStyle exactly as
-- GojoClient.whoosh does. playStrike calls this for the local swing and for every remote caster's Strike broadcast,
-- so everyone sees it. The Trail lives in this script's Folder; only its two attachments sit on the limb.
AscPerk.LIMB = { { "LeftHand" }, { "RightHand" }, { "LeftHand" }, { "RightFoot", "RightHand", "LeftHand", "LeftFoot" } }
AscPerk.trails = setmetatable({}, { __mode = "k" }) -- [limb part] = Trail
function AscPerk.trailStyle()
	if AscPerk.TS == nil then
		local folder = ReplicatedStorage:FindFirstChild("PerkShared")
		local mod = folder and folder:FindFirstChild("TrailStyle")
		if not mod then
			return nil -- (not replicated yet: tried again next swing; the kit-colour whoosh still draws)
		end
		local ok, m = pcall(require, mod)
		AscPerk.TS = ok and type(m) == "table" and m or false
	end
	return AscPerk.TS or nil
end
function AscPerk.trail(char, combo, length, form)
	local pl = Players:GetPlayerFromCharacter(char)
	local id = pl and pl:GetAttribute("EquipTrail")
	local pal = AscPerk.isAlt(pl) and AscPerk.ALT or PAL
	local tint = form == "Surge" and pal.Gold or form == "Instinct" and pal.SilverBlue or pal.Ki
	for _, name in ipairs(AscPerk.LIMB[combo] or AscPerk.LIMB[2]) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local tr = AscPerk.trails[part]
			if not tr or not tr.Parent then
				local a0 = Instance.new("Attachment")
				a0.Name = "AscTrailA"
				a0.Position = Vector3.new(0, 0.7, 0)
				a0.Parent = part
				local a1 = Instance.new("Attachment")
				a1.Name = "AscTrailB"
				a1.Position = Vector3.new(0, -0.7, 0)
				a1.Parent = part
				tr = Instance.new("Trail")
				tr.Name = "StrikeTrail"
				tr.Attachment0, tr.Attachment1 = a0, a1
				tr.Lifetime = 0.26
				tr.MinLength = 0.02
				tr.FaceCamera = true
				tr.LightEmission = 1
				tr.LightInfluence = 0
				tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
				tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.15), NumberSequenceKeypoint.new(1, 0.05) })
				tr.Enabled = false
				tr.Parent = Folder
				AscPerk.trails[part] = tr
				part.AncestryChanged:Connect(function(_, parent)
					if not parent then
						tr:Destroy()
					end
				end)
			end
			local TS = AscPerk.trailStyle()
			if not (TS and type(id) == "string" and id ~= "" and TS.apply(tr, id)) then
				if TS then
					TS.apply(tr, "") -- a reused whoosh drops a Trail Pack look its caster just unequipped
				end
				tr.Color = ColorSequence.new(WHITE, tint)
			end
			tr:Clear()
			tr.Enabled = true
			local token = (tr:GetAttribute("Tok") or 0) + 1
			tr:SetAttribute("Tok", token)
			task.delay(length, function()
				if tr.Parent and tr:GetAttribute("Tok") == token then
					tr.Enabled = false
				end
			end)
		end
	end
end

local function playStrike(char, combo, form)
	local s = STRIKE[combo] or STRIKE[1]
	pose(char, s.keys, s.length)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		SfxBank.play("SWING", hrp, 0.8, 1.05 + combo * 0.04) -- (2026-11-12) the jab swings like every fighter's punch; the 2.3 s wind burst stacked into a roar
	end
	local okT, errT = pcall(AscPerk.trail, char, combo, s.length * 0.7, form)
	if not okT then
		warn("[AscendantClient] strike trail: " .. tostring(errT))
	end
	if form == "Instinct" then
		local col = (AscPerk.isAlt(Players:GetPlayerFromCharacter(char)) and AscPerk.ALT or PAL).Silver
		task.delay(0.08, function()
			afterimage(char, nil, col, 0.22, 0.7)
		end)
	end
end

tryStrike = function(pressed)
	if pressed then
		localStrike.held = true
	end
	if not equipped() or cutscene then
		return
	end
	local char, _, hrp = myChar()
	if not char or os.clock() < rootUntil then
		return
	end
	local M = CFG.Strike
	local t = os.clock()
	-- (2026-11-07) a click a moment early is held and thrown the instant the strike is allowed, instead of dropped;
	-- holding M1 keeps the combo going (the Heartbeat below) - the same feel as every other fighter's M1
	local readyAt = math.max(localStrike.last + M.SwingInterval, localStrike.lock)
	if t < readyAt then
		if readyAt - t <= 0.18 and not localStrike.buffered then
			localStrike.buffered = true
			task.delay(readyAt - t, function()
				localStrike.buffered = false
				tryStrike()
			end)
		end
		return
	end
	if t - localStrike.last > M.ComboReset then
		localStrike.combo = 0
	end
	localStrike.combo = localStrike.combo % M.Combo + 1
	localStrike.last = t
	if localStrike.combo >= M.Combo then
		localStrike.lock = t + M.FinalCooldown
	end
	local target = cursorTarget()
	local aim = flat(target - hrp.Position, flat(workspace.CurrentCamera.CFrame.LookVector, FWD))
	faceUntil, faceDirV = t + 0.28, aim
	playStrike(char, localStrike.combo, char:GetAttribute("AscForm"))
	Request:FireServer("Strike", { aim = aim })
end

-- holding M1 keeps the combo going: the next strike goes out the moment it is allowed (2026-11-07)
RunService.Heartbeat:Connect(function()
	if not localStrike.held then
		return
	end
	if not equipped() or not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not _G.SandboxArmed) then
		localStrike.held = false
	elseif not localStrike.buffered and os.clock() >= math.max(localStrike.last + CFG.Strike.SwingInterval, localStrike.lock) then
		tryStrike()
	end
end)

function handlers.Strike(d)
	if isMe(d.userId) then
		return
	end
	local char = charOf(d.userId)
	if char then
		playStrike(char, d.combo, d.form)
	end
end

function handlers.StrikeHit(d)
	local PAL = AscPerk.pal(d.userId)
	local f = castFolder("StrikeHit", 2)
	local pos, dir = d.pos, d.dir
	local col = d.form == "Surge" and PAL.Gold or d.form == "Instinct" and PAL.Silver or PAL.Hit
	FX.glow(f, pos, d.final and 12 or 6, col, 0.2)
	FX.sparks(f, pos, { count = d.final and 26 or 12, speed = { 20, 60 }, color = WHITE, color2 = col, size = 0.45, dir = dir, spread = 60 })
	FX.ring(f, pos, dir, 0.5, d.final and 12 or 6, col, 0.25)
	if d.form == "Instinct" then
		FX.streaks(f, pos, { dir = dir, spread = 16, count = 14, speed = { 90, 180 }, color = PAL.SilverCore, color2 = PAL.SilverBlue, size = 0.8, life = 0.3 })
		FX.ring(f, pos, dir, 1, d.final and 18 or 10, PAL.SilverPurple, 0.35, { alpha = 0.2 })
	end
	sound(d.final and SND.HitHeavy or SND.Hit, pos, 0.9, d.final and 1 or 1.15 + math.random() * 0.2)
	Fx2.shake(d.final and 1.2 or 0.5, 0.15, pos)
	if d.final and isMe(d.userId) then
		FX.impact({ tint = col, lineColor = col, flashAlpha = 0.2, lineTime = 0.25 })
	end
end

-- the golden form's M1 shockwave
function handlers.StrikeShock(d)
	local PAL = AscPerk.pal(d.userId)
	local f = castFolder("Shock", 2)
	Fx2.shockwave(f, d.pos, d.dir, 1, d.radius * 2, PAL.Gold, 0.35)
	FX.ring(f, d.pos, UP, 1, d.radius * 2.2, PAL.Gold, 0.35, { alpha = 0.1 })
	FX.shell(f, d.pos, 0.5, d.radius * 0.6, PAL.GoldCore, 0.25)
	FX.streaks(f, d.pos, { count = 16, speed = { 50, 110 }, color = PAL.GoldCore, color2 = PAL.Gold, size = 0.6, life = 0.25 })
	FX.arcs(f, d.pos, d.radius * 0.5, { count = 2, colors = { PAL.Bolt, PAL.GoldCore }, width = 0.07, life = 0.1 })
	sound(SND.Zap, d.pos, 0.5, 1.3)
end

---------------------------------------------------------------------------------------------------
-- the silver form's blink: three ghosts strung along the path (silver, blue, violet), a silver line to where it
-- went, a ripple where it left and light snapping shut where it arrived
function handlers.Dodge(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	if not char then
		return
	end
	afterimage(char, d.from, PAL.Silver, 0.5, 0.25)
	task.delay(0.03, function()
		afterimage(char, d.from:Lerp(d.to, 0.35), PAL.SilverBlue, 0.35, 0.55, true)
	end)
	task.delay(0.06, function()
		afterimage(char, d.from:Lerp(d.to, 0.7), PAL.SilverPurple, 0.3, 0.65, true)
	end)
	local f = castFolder("Dodge", 2)
	streakLine(f, d.from + UP * 0.5, d.to + UP * 0.5, PAL.Silver, 0.25, 0.3)
	FX.ring(f, d.from - UP * 2.5, UP, 1, 9, PAL.Silver, 0.35, { alpha = 0.2 })
	FX.ring(f, d.to, UP, 7, 0.5, PAL.SilverBlue, 0.22, { ease = "in" })
	FX.sparks(f, d.to, { count = 14, speed = { 8, 22 }, color = PAL.SilverCore, color2 = PAL.SilverBlue, size = 0.35, accel = Vector3.zero })
	FX.glow(f, d.to + UP, 7, PAL.Silver, 0.22)
	sound(SND.Whoosh, d.to, 0.8, 1.9)
	sound(SND.Zap, d.to, 0.3, 3)
	if isMe(d.userId) then
		FX.flash(PAL.Silver, 0.15, 0.12)
		Fx2.envelope({ fov = 5, attack = 0.02, release = 0.2 })
	end
end

-- the flurry: a blink to each enemy in turn, a strike on each
function handlers.FlurryStart(d)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if isMe(d.userId) or (hrp and hears(hrp.Position, 120)) then
		showTitle("Flurry", 1.2)
	end
	if hrp then
		sound(SND.Rise, hrp.Position, 0.6, 1.6)
	end
end

function handlers.FlurryHit(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	local f = castFolder("Flurry", 2)
	if char then
		afterimage(char, d.from, PAL.SilverBlue, 0.4, 0.4)
		local s = d.last and STRIKE[4] or STRIKE[(d.i - 1) % 3 + 1]
		pose(char, s.keys, s.length)
	end
	streakLine(f, d.from + UP * 0.6, d.to + UP * 0.6, PAL.Silver, 0.3, 0.35)
	FX.glow(f, d.pos, d.last and 16 or 9, PAL.Silver, 0.25)
	FX.ring(f, d.pos, d.dir, 1, d.last and 20 or 12, PAL.SilverCore, 0.3)
	FX.ring(f, d.pos, d.dir, 1, d.last and 14 or 8, PAL.SilverPurple, 0.35, { alpha = 0.2 })
	FX.streaks(f, d.pos, { dir = d.dir, spread = 20, count = 18, speed = { 90, 190 }, color = PAL.SilverCore, color2 = PAL.SilverBlue, size = 0.9, life = 0.3 })
	sound(SND.HitHeavy, d.pos, 0.9, 1.1 + d.i * 0.05)
	sound(SND.Whoosh, d.to, 0.5, 2)
	Fx2.shake(d.last and 1.8 or 0.9, 0.2, d.pos)
	if isMe(d.userId) and d.last then
		FX.impact({ tint = PAL.Silver, lineColor = PAL.SilverBlue, flashAlpha = 0.3 })
	end
end

function handlers.FlurryNone()
	showSubtitle("NO ONE IN REACH", 0.8, AscPerk.pal(player.UserId).Silver)
end

---------------------------------------------------------------------------------------------------
-- the forms' look, drawn by every client from the character's AscForm attribute. The hair is the centrepiece: a
-- crown of tapering spikes, each a bright Neon core inside a softer glowing shell, that GROWS out of the scalp when
-- the form ignites, sways in the aura's updraft, shimmers between two tones and sheds wisps of light off its tips
-- (any hair underneath is recoloured to match). Then glowing eyes (the golden form adds scowling brows), a light round
-- the head, and the aura: golden flames, sparks and crawling lightning, or layered silver / deep-blue / violet flames
-- with streaming light - and the silver form leaves a trail of afterimages whenever it moves fast.
local looks = {} -- [char] = { kind, hair, parts, lobes, box, e, t0, grown, arcAt, trailAt, trailN }

-- spikes: base (fraction of the head's half-size: x right, y up, z back), direction, length (x head height), width
-- factor. FILL lays short flat lobes over the scalp so no bald patch shows between the roots.
local HAIR = {
	-- the golden form: big, bristling, crackling
	Surge = {
		width = 0.3, sway = 3, swaySpeed = 8, shimmer = 5,
		core = { CFG.Surge.HairColor, PAL.GoldCore }, coreT = 0, shell = PAL.GoldDeep, shellT = 0.68,
		wisp = { PAL.GoldCore, PAL.Gold },
		spikes = {
			{ Vector3.new(0, 0.9, 0.05), Vector3.new(0, 1, 0.25), 1.5 },
			{ Vector3.new(-0.4, 0.8, 0), Vector3.new(-0.35, 1, 0.15), 1.35 },
			{ Vector3.new(0.4, 0.8, 0), Vector3.new(0.35, 1, 0.15), 1.35 },
			{ Vector3.new(-0.3, 0.8, -0.5), Vector3.new(-0.15, 1, -0.25), 1.1 },
			{ Vector3.new(0.3, 0.8, -0.5), Vector3.new(0.2, 1, -0.2), 1.05 },
			{ Vector3.new(0, 0.65, 0.7), Vector3.new(0, 0.8, 1), 1.4 },
			{ Vector3.new(-0.55, 0.55, 0.55), Vector3.new(-0.6, 0.75, 0.7), 1.2 },
			{ Vector3.new(0.55, 0.55, 0.55), Vector3.new(0.6, 0.75, 0.7), 1.2 },
			{ Vector3.new(-0.85, 0.4, 0.1), Vector3.new(-1, 0.7, 0.2), 0.95 },
			{ Vector3.new(0.85, 0.4, 0.1), Vector3.new(1, 0.7, 0.2), 0.95 },
			{ Vector3.new(-0.4, 0.2, 0.85), Vector3.new(-0.4, 0.3, 1), 1.0 },
			{ Vector3.new(0.4, 0.2, 0.85), Vector3.new(0.4, 0.3, 1), 1.0 },
			{ Vector3.new(0.12, 0.72, -0.86), Vector3.new(0.15, -0.65, -0.55), 0.6, 0.6 }, -- a single forelock
		},
	},
	-- the silver form: sleeker, longer, swept up and back, flowing slowly as if underwater
	Instinct = {
		width = 0.25, sway = 6, swaySpeed = 2.2, shimmer = 2.4,
		core = { CFG.Instinct.HairColor, Color3.fromRGB(196, 208, 255) }, coreT = CFG.Instinct.HairTransparency, shell = PAL.SilverBlue, shellT = 0.58,
		wisp = { PAL.SilverCore, PAL.SilverPurple },
		spikes = {
			{ Vector3.new(0, 0.95, 0.15), Vector3.new(0, 1, 0.45), 1.7, 0.95 },
			{ Vector3.new(-0.35, 0.85, 0.05), Vector3.new(-0.4, 1, 0.35), 1.55, 0.9 },
			{ Vector3.new(0.35, 0.85, 0.05), Vector3.new(0.4, 1, 0.35), 1.55, 0.9 },
			{ Vector3.new(-0.25, 0.85, -0.45), Vector3.new(-0.2, 1, -0.05), 1.3, 0.85 },
			{ Vector3.new(0.25, 0.85, -0.45), Vector3.new(0.25, 1, -0.02), 1.25, 0.85 },
			{ Vector3.new(-0.6, 0.85, -0.2), Vector3.new(-0.7, 1, 0.1), 1.05, 0.75 },
			{ Vector3.new(0.6, 0.85, -0.2), Vector3.new(0.7, 1, 0.1), 1.05, 0.75 },
			{ Vector3.new(0, 0.7, 0.75), Vector3.new(0, 0.65, 1), 1.6, 0.95 },
			{ Vector3.new(-0.55, 0.6, 0.55), Vector3.new(-0.65, 0.6, 0.8), 1.4, 0.85 },
			{ Vector3.new(0.55, 0.6, 0.55), Vector3.new(0.65, 0.6, 0.8), 1.4, 0.85 },
			{ Vector3.new(-0.85, 0.45, 0.15), Vector3.new(-1, 0.8, 0.35), 1.15, 0.8 },
			{ Vector3.new(0.85, 0.45, 0.15), Vector3.new(1, 0.8, 0.35), 1.15, 0.8 },
			{ Vector3.new(-0.45, 0.3, 0.85), Vector3.new(-0.45, 0.2, 1), 1.2, 0.8 },
			{ Vector3.new(0.45, 0.3, 0.85), Vector3.new(0.45, 0.2, 1), 1.2, 0.8 },
			{ Vector3.new(0, 0.35, 0.95), Vector3.new(0, 0.05, 1), 1.25, 0.85 },
			{ Vector3.new(-0.15, 0.72, -0.86), Vector3.new(-0.25, -0.6, -0.55), 0.62, 0.55 }, -- two thin forelocks
			{ Vector3.new(0.2, 0.7, -0.86), Vector3.new(0.3, -0.7, -0.5), 0.5, 0.5 },
		},
	},
}
-- PERKS: the same crowns in the GOD BLUE colours (Config.AltForms over the forms' hair, AscPerk.ALT for the glow)
AscPerk.HAIR = {}
do
	local A, AF = AscPerk.ALT, CFG.AltForms or {}
	local AS, AI = AF.Surge or {}, AF.Instinct or {}
	local su = table.clone(HAIR.Surge)
	su.core = { AS.HairColor or CFG.Surge.HairColor, A.GoldCore }
	su.shell = A.GoldDeep
	su.wisp = { A.GoldCore, A.Gold }
	local ins = table.clone(HAIR.Instinct)
	ins.core = { AI.HairColor or CFG.Instinct.HairColor, AI.HairColor2 or HAIR.Instinct.core[2] }
	ins.shell = A.SilverBlue
	ins.wisp = { A.SilverCore, A.SilverPurple }
	AscPerk.HAIR.Surge, AscPerk.HAIR.Instinct = su, ins
end
local FILL = {
	{ Vector3.new(0, 0.62, -0.35), Vector3.new(0, 0.5, -1) },
	{ Vector3.new(-0.45, 0.6, -0.3), Vector3.new(-0.5, 0.45, -1) },
	{ Vector3.new(0.45, 0.6, -0.3), Vector3.new(0.5, 0.45, -1) },
	{ Vector3.new(-0.55, 0.62, 0.2), Vector3.new(-1, 0.6, 0.1) },
	{ Vector3.new(0.55, 0.62, 0.2), Vector3.new(1, 0.6, 0.1) },
	{ Vector3.new(0, 0.62, 0.35), Vector3.new(0, 0.4, 1) },
}

local function cosmetic(p)
	p.Anchored = false
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
end

local function weldTo(part, base)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, part
	w.Parent = part
end

local function ns(...)
	local list = {}
	for _, kv in ipairs({ ... }) do
		table.insert(list, NumberSequenceKeypoint.new(kv[1], kv[2]))
	end
	return NumberSequence.new(list)
end
local function csq(...)
	local list = {}
	for _, kv in ipairs({ ... }) do
		table.insert(list, ColorSequenceKeypoint.new(kv[1], kv[2]))
	end
	return ColorSequence.new(list)
end

local function hairHandles(char)
	local list = {}
	for _, acc in ipairs(char:GetChildren()) do
		if acc:IsA("Accessory") then
			local h = acc:FindFirstChild("Handle")
			local isHair = false
			pcall(function()
				isHair = acc.AccessoryType == Enum.AccessoryType.Hair
			end)
			if not isHair and h then
				isHair = h:FindFirstChild("HairAttachment") ~= nil or acc.Name:lower():find("hair") ~= nil
			end
			if isHair and h and h:IsA("BasePart") then
				table.insert(list, h)
			end
		end
	end
	return list
end

local function tintHair(look, handles, color, transp)
	for _, h in ipairs(handles) do
		local sv = { material = h.Material, color = h.Color, transparency = h.Transparency }
		pcall(function()
			if h:IsA("MeshPart") then
				sv.tex = h.TextureID
				h.TextureID = ""
			end
		end)
		local sm = h:FindFirstChildOfClass("SpecialMesh")
		if sm then
			sv.mesh, sv.meshTex = sm, sm.TextureId
			sm.TextureId = ""
		end
		local sa = h:FindFirstChildOfClass("SurfaceAppearance")
		if sa then
			sv.sa = sa
			pcall(function()
				sa.Parent = nil
			end)
		end
		h.Material = Enum.Material.Neon
		h.Color = color
		h.Transparency = transp
		look.hair[h] = sv
	end
end

local function restoreHair(look)
	for h, sv in pairs(look.hair) do
		if h.Parent then
			h.Material, h.Color, h.Transparency = sv.material, sv.color, sv.transparency
			pcall(function()
				if sv.tex then
					h.TextureID = sv.tex
				end
				if sv.sa then
					sv.sa.Parent = h
				end
			end)
			if sv.mesh then
				sv.mesh.TextureId = sv.meshTex
			end
		end
	end
	look.hair = {}
end

-- one lobe of hair, held on a Weld whose C0 the frame loop animates (root = CFrame in head space, -Z along the spike)
local function addLobe(look, head, parent, rootCF, dist, size, color, transp, layer, phase)
	local p = ellipsoid("HairLobe", size, color, Enum.Material.Neon, parent)
	cosmetic(p)
	p.Transparency = transp
	local w = Instance.new("Weld")
	w.Part0, w.Part1 = head, p
	w.C0 = rootCF
	w.Parent = p
	table.insert(look.lobes, { part = p, weld = w, root = rootCF, dist = dist, size = size, layer = layer, phase = phase, transp = transp })
	return p
end

local function buildHair(look, char, kind)
	local head = char:FindFirstChild("Head")
	local H = (look.alt and AscPerk.HAIR or HAIR)[kind]
	if not head or not H then
		return
	end
	local hs, hh = head.Size / 2, head.Size.Y
	local s = hh / 1.2
	local model = Instance.new("Model")
	model.Name = "AscSpikes"
	for i, sp in ipairs(H.spikes) do
		local base = Vector3.new(sp[1].X * hs.X, sp[1].Y * hs.Y, sp[1].Z * hs.Z)
		local dir = sp[2].Unit
		local rootCF = CFrame.lookAt(base, base + dir)
		local len, w = sp[3] * hh, H.width * hh * (sp[4] or 1)
		local phase = i * 1.7
		-- a bright core (a thick root, a thinner tip) inside a softly glowing shell
		addLobe(look, head, model, rootCF, len * 0.28, Vector3.new(w, w, len * 0.62), H.core[1], H.coreT, "core", phase)
		local tip = addLobe(look, head, model, rootCF, len * 0.62, Vector3.new(w * 0.55, w * 0.55, len * 0.7), H.core[1], H.coreT, "core", phase)
		addLobe(look, head, model, rootCF, len * 0.45, Vector3.new(w * 1.6, w * 1.6, len * 1.08), H.shell, H.shellT, "shell", phase)
		-- wisps of light stream off the longest tips
		if sp[3] >= 1.2 then
			local at = Instance.new("Attachment")
			at.Position = Vector3.new(0, 0, -len * 0.3)
			at.Parent = tip
			Fx2.emitter(at, {
				Texture = FX.TEX.glow, Color = ColorSequence.new(H.wisp[1], H.wisp[2]), LightEmission = 1, Rate = 6,
				Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(3 * s, 6 * s), EmissionDirection = Enum.NormalId.Front,
				SpreadAngle = Vector2.new(14, 14), Acceleration = UP * 6, Orientation = Enum.ParticleOrientation.VelocityParallel,
				Squash = NumberSequence.new(-1.6), Size = ns({ 0, 0.32 * s }, { 1, 0 }), Transparency = ns({ 0, 0.25 }, { 1, 1 }),
			})
		end
	end
	for _, sp in ipairs(FILL) do
		local base = Vector3.new(sp[1].X * hs.X, sp[1].Y * hs.Y, sp[1].Z * hs.Z)
		local dir = sp[2].Unit
		addLobe(look, head, model, CFrame.lookAt(base, base + dir), hh * 0.22, Vector3.new(0.5 * hh, 0.3 * hh, 0.9 * hh), H.core[1], H.coreT, "fill", 0)
	end
	model.Parent = char
	table.insert(look.parts, model)
	-- a soft light round the head
	local glowAt = Instance.new("Attachment")
	glowAt.Name = "AscHairGlow"
	glowAt.Position = Vector3.new(0, hh * 0.7, 0)
	glowAt.Parent = head
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = H.core[1], 7, 1.6, false
	light.Parent = glowAt
	table.insert(look.parts, glowAt)
end

-- a custom accessory slot: an Accessory named in the Config replaces the crown
local function wearTemplate(look, char, name)
	local tpl = name ~= "" and Kit:FindFirstChild(name)
	local head = char:FindFirstChild("Head")
	if not (tpl and tpl:IsA("Accessory") and head) then
		return false
	end
	local acc = tpl:Clone()
	local h = acc:FindFirstChild("Handle")
	if not h then
		acc:Destroy()
		return false
	end
	cosmetic(h)
	local att = h:FindFirstChildOfClass("Attachment")
	local target = att and head:FindFirstChild(att.Name)
	h.CFrame = target and (target.WorldCFrame * att.CFrame:Inverse()) or head.CFrame
	weldTo(h, head)
	acc.Parent = char
	table.insert(look.parts, acc)
	return true
end

-- glowing eyes, and (golden form) brows drawn down in a scowl
local function buildFace(look, char, eyeColor, browColor)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local hs = head.Size / 2
	local fz = -hs.Z * 0.98
	for _, sx in ipairs({ -1, 1 }) do
		local e = ellipsoid("EyeGlow", Vector3.new(hs.X * 0.24, hs.Y * 0.15, 0.05), eyeColor, Enum.Material.Neon, char)
		cosmetic(e)
		e.Transparency = 0.2
		e.CFrame = head.CFrame * CFrame.new(sx * hs.X * 0.34, hs.Y * 0.3, fz)
		weldTo(e, head)
		table.insert(look.parts, e)
		if browColor then
			local b = Instance.new("Part")
			b.Name = "BrowGlow"
			b.Material = Enum.Material.Neon
			b.Color = browColor
			b.Size = Vector3.new(hs.X * 0.42, hs.Y * 0.07, 0.05)
			cosmetic(b)
			b.CFrame = head.CFrame * CFrame.new(sx * hs.X * 0.35, hs.Y * 0.56, fz) * CFrame.Angles(0, 0, R(-16 * sx))
			b.Parent = char
			weldTo(b, head)
			table.insert(look.parts, b)
		end
	end
end

-- the aura box: an invisible shell round the body that the flames rise out of
local function auraBox(look, char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local box = Instance.new("Part")
	box.Name = "AscAura"
	box.Transparency = 1
	box.Size = Vector3.new(2.8, 5.6, 1.9)
	cosmetic(box)
	box.CFrame = hrp.CFrame
	box.Parent = char
	weldTo(box, hrp)
	table.insert(look.parts, box)
	return box
end

local function buildLook(char, kind)
	local look = { kind = kind, hair = {}, parts = {}, lobes = {}, t0 = os.clock(), arcAt = 0, trailAt = 0, trailN = 0 }
	look.alt = AscPerk.isAlt(Players:GetPlayerFromCharacter(char)) -- (GOD BLUE: read once, when the form ignites)
	local PAL = look.alt and AscPerk.ALT or PAL
	local AF = look.alt and CFG.AltForms and CFG.AltForms[kind] or {}
	local S, I = CFG.Surge, CFG.Instinct
	local F = kind == "Surge" and S or I
	local H = (look.alt and AscPerk.HAIR or HAIR)[kind]
	local handles = hairHandles(char)
	tintHair(look, handles, H.core[1], H.coreT)
	if not wearTemplate(look, char, F.HairTemplate or "") and (F.AddSpikes ~= false or #handles == 0) then
		buildHair(look, char, kind)
	end
	buildFace(look, char, AF.EyeColor or F.EyeColor, kind == "Surge" and (AF.HairColor or S.HairColor) or nil)
	local box = auraBox(look, char)
	if box then
		local light = Instance.new("PointLight")
		light.Shadows = false
		light.Parent = box
		if kind == "Surge" then
			light.Color, light.Range, light.Brightness = PAL.Gold, 16, 2.4
			look.e = {
				Fx2.emitter(box, {
					Texture = Fx2.Tex.fire, Color = csq({ 0, PAL.GoldCore }, { 0.4, PAL.Gold }, { 1, PAL.GoldDeep }), LightEmission = 1, Rate = 90,
					Lifetime = NumberRange.new(0.45, 0.8), Speed = NumberRange.new(6, 12), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(18, 18),
					Acceleration = UP * 10, Size = ns({ 0, 2.2 }, { 0.5, 3.2 }, { 1, 0.4 }), Transparency = ns({ 0, 0.55 }, { 0.4, 0.4 }, { 1, 1 }),
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), ZOffset = -0.5,
				}),
				Fx2.emitter(box, {
					Texture = FX.TEX.glow, Color = ColorSequence.new(PAL.GoldCore, PAL.Gold), LightEmission = 1, Rate = 40,
					Lifetime = NumberRange.new(0.3, 0.55), Speed = NumberRange.new(12, 20), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10),
					Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2.4),
					Size = ns({ 0, 0.3 }, { 0.3, 0.7 }, { 1, 0 }), Transparency = ns({ 0, 0.3 }, { 1, 1 }),
				}),
				Fx2.emitter(box, {
					Texture = FX.TEX.star, Color = ColorSequence.new(WHITE, PAL.Bolt), LightEmission = 1, Rate = 14,
					Lifetime = NumberRange.new(0.1, 0.2), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180),
					Size = ns({ 0, 0.7 }, { 1, 0 }), Rotation = NumberRange.new(0, 360),
				}),
			}
		else
			light.Color, light.Range, light.Brightness = PAL.Silver, 15, 2
			look.e = {
				-- inner silver wisps
				Fx2.emitter(box, {
					Texture = FX.TEX.glow, Color = ColorSequence.new(WHITE, PAL.Silver), LightEmission = 1, Rate = 50,
					Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(12, 12),
					Acceleration = UP * 5, Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-1.6),
					Size = ns({ 0, 0.4 }, { 0.4, 1.2 }, { 1, 0 }), Transparency = ns({ 0, 0.5 }, { 0.5, 0.35 }, { 1, 1 }), ZOffset = 1,
				}),
				-- deep blue flames
				Fx2.emitter(box, {
					Texture = Fx2.Tex.fire, Color = csq({ 0, PAL.Silver }, { 0.35, PAL.SilverBlue }, { 1, PAL.SilverBlue }), LightEmission = 1, Rate = 45,
					Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(4, 8), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(16, 16),
					Acceleration = UP * 6, Size = ns({ 0, 1.8 }, { 0.5, 2.8 }, { 1, 0.5 }), Transparency = ns({ 0, 0.6 }, { 0.5, 0.5 }, { 1, 1 }),
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
				}),
				-- violet outer flames, slow and wide
				Fx2.emitter(box, {
					Texture = Fx2.Tex.fire, Color = csq({ 0, PAL.SilverBlue }, { 0.5, PAL.SilverPurple }, { 1, PAL.SilverPurple }), LightEmission = 1, Rate = 30,
					Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(30, 30),
					Acceleration = UP * 4, Size = ns({ 0, 2.6 }, { 0.5, 4.2 }, { 1, 0.8 }), Transparency = ns({ 0, 0.7 }, { 0.5, 0.62 }, { 1, 1 }),
					Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), ZOffset = -1,
				}),
				-- thin lines of light streaming up through it
				Fx2.emitter(box, {
					Texture = FX.TEX.glow, Color = ColorSequence.new(WHITE, PAL.SilverBlue), LightEmission = 1, Rate = 22,
					Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(14, 22), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(6, 6),
					Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-3),
					Size = ns({ 0, 0.25 }, { 1, 0 }), Transparency = ns({ 0, 0.2 }, { 1, 1 }),
				}),
				-- motes of light drifting up
				Fx2.emitter(box, {
					Texture = FX.TEX.star, Color = ColorSequence.new(WHITE, PAL.Silver), LightEmission = 1, Rate = 10,
					Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
					Acceleration = UP * 3, Size = ns({ 0, 0.35 }, { 1, 0 }), Rotation = NumberRange.new(0, 360),
				}),
			}
		end
		look.box = box
	end
	-- the change itself flares on the head
	local head = char:FindFirstChild("Head")
	if head then
		local f = castFolder("FormFlare", 2)
		FX.glow(f, head.Position, 12, H.core[1], 0.4)
		FX.ring(f, head.Position, UP, 1, 9, H.core[1], 0.35)
		FX.sparks(f, head.Position, { count = 22, speed = { 10, 34 }, color = WHITE, color2 = H.core[1], size = 0.4 })
	end
	return look
end

local function clearLook(look)
	restoreHair(look)
	for _, e in ipairs(look.e or {}) do
		e.Enabled = false
	end
	for _, p in ipairs(look.parts) do
		if p == look.box then
			Debris:AddItem(p, 1.2) -- let the last flames burn out
		else
			p:Destroy()
		end
	end
	look.parts, look.lobes = {}, {}
end

local function easeOutBack(x)
	return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
end

-- every frame, per transformed body: the hair grows in (with an overshoot), sways, shimmers; the golden form crackles
-- with lightning; the silver form leaves afterimages when it moves fast
local function updateLook(char, look, clock)
	local PAL = look.alt and AscPerk.ALT or PAL
	local H = (look.alt and AscPerk.HAIR or HAIR)[look.kind]
	if H and #look.lobes > 0 then
		local g = math.clamp((clock - look.t0) / 0.55, 0, 1)
		local grow = easeOutBack(g)
		local growing = not look.grown
		if g >= 1 then
			look.grown = true
		end
		local swayA = R(H.sway)
		for _, l in ipairs(look.lobes) do
			local p = l.part
			if p.Parent then
				local fill = l.layer == "fill"
				local k = fill and math.min(g * 2, 1) or grow
				local sway = fill and 0 or math.sin(clock * H.swaySpeed + l.phase) * swayA
				l.weld.C0 = l.root * CFrame.Angles(sway, 0, sway * 0.6) * CFrame.new(0, 0, -l.dist * k)
				if growing then
					p.Size = Vector3.new(l.size.X, l.size.Y, math.max(l.size.Z * k, 0.05))
				end
				local wave = math.sin(clock * H.shimmer + l.phase)
				if l.layer == "shell" then
					p.Transparency = math.clamp(l.transp + 0.12 * wave, 0, 1)
				else
					p.Color = H.core[1]:Lerp(H.core[2], 0.5 + 0.5 * wave)
				end
			end
		end
	end
	if look.kind == "Surge" and look.box and clock >= look.arcAt then
		-- lightning crawling over the golden form
		look.arcAt = clock + 0.12 + math.random() * 0.25
		local c = look.box.Position + Vector3.new(0, math.random() * 2 - 0.5, 0)
		FX.arcs(Folder, c, 2.2 + math.random() * 0.8, { count = 1, colors = { PAL.Bolt, WHITE }, width = 0.06, life = 0.09, jag = 0.45 })
	elseif look.kind == "Instinct" and clock >= look.trailAt then
		-- a trail of silver afterimages behind a fast-moving silver body
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp.AssemblyLinearVelocity.Magnitude > 20 then
			look.trailAt = clock + 0.12
			look.trailN += 1
			afterimage(char, nil, look.trailN % 2 == 0 and PAL.SilverBlue or PAL.Silver, 0.32, 0.72, true)
		end
	end
end

local function syncLooks(clock)
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if char and char.Parent then
			local kind = char:GetAttribute("AscForm")
			local look = looks[char]
			if (look and look.kind) ~= kind then
				if look then
					clearLook(look)
					looks[char] = nil
				end
				if kind == "Surge" or kind == "Instinct" then
					looks[char] = buildLook(char, kind)
				end
			end
		end
	end
	for char, look in pairs(looks) do
		if not char.Parent then
			clearLook(look)
			looks[char] = nil
		else
			updateLook(char, look, clock)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 3: the golden form's power-up. A low scream: the ground shakes, rocks lift, lightning crawls and light pours
-- in, then the burst: a pillar of gold, rings across the ground, cracks, the hair igniting.
function handlers.SurgeStart(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local keys = { { t = 0.12, ease = { "Back", "Out" }, pose = POSE.Scream } }
	for i = 1, math.floor(d.burstAt / 0.08) do
		table.insert(keys, { t = 0.12 + i * 0.08, pose = i % 2 == 0 and POSE.Scream or POSE.ScreamShake })
	end
	table.insert(keys, { t = d.burstAt + 0.06, ease = { "Exponential", "Out" }, pose = POSE.Flare })
	table.insert(keys, { t = d.time, ease = { "Quad", "InOut" }, pose = POSE.Flare })
	pose(char, keys, d.time + 0.3)
	local f = castFolder("SurgeStart", d.time + 6)
	local g, _, gh = groundAt(hrp.Position, 12)
	local rocks = gh and FX.liftRocks(f, g, 14, 18) or nil
	local mine = isMe(d.userId)
	if mine then
		rootUntil = os.clock() + d.time
		Fx2.envelope({ sat = -0.35, contrast = 0.25, tint = PAL.Gold, fov = -8, attack = d.burstAt, hold = 0.05, release = 0.5 })
	end
	sound(SND.Rise, hrp.Position, 1, 0.8)
	sound(SND.Crackle, hrp.Position, 0.8, 1)
	-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (Surge scream subtitle removed)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < d.burstAt and char.Parent and f.Parent do
			local k = (os.clock() - t0) / d.burstAt
			local c = (char:FindFirstChild("UpperTorso") or hrp).Position
			FX.arcs(f, c, 2.5 + k * 1.5, { count = 1 + math.floor(k * 3), colors = { PAL.Bolt, PAL.GoldCore, PAL.Gold }, width = 0.08, life = 0.1, jag = 0.4 })
			FX.streaks(f, c, { inward = 10, count = 6 + math.floor(k * 10), color = PAL.GoldCore, color2 = PAL.Gold, size = 0.5, life = 0.3 })
			if gh and math.random() < 0.5 then
				Fx2.dust(f, g + FX.randUnit() * FLAT * 6, 2.5, 2)
			end
			Fx2.shake((mine and 0.5 or 0.3) + k * 1.4, 0.12, hrp.Position, 160)
			task.wait(0.09)
		end
		if rocks and not rocks.dead then
			rocks:drop()
		end
	end)
end

function handlers.SurgeBurst(d)
	local PAL = AscPerk.pal(d.userId)
	local pos, rad = d.pos, d.radius
	local f = castFolder("SurgeBurst", 8)
	local g, n, gh = groundAt(pos, 12)
	local floor = gh and g + UP * 0.4 or pos
	pillar(f, pos, PAL.Gold, PAL.GoldCore, 80, 6, 1)
	FX.shell(f, pos, 2, rad * 0.6, PAL.GoldCore, 0.45)
	FX.shell(f, pos, 3, rad, PAL.Gold, 0.7, Enum.Material.ForceField)
	FX.ring(f, floor, UP, 4, rad * 2.4, PAL.Gold, 0.7)
	FX.ring(f, floor, UP, 2, rad * 1.6, PAL.GoldCore, 0.5)
	FX.streaks(f, pos, { count = 60, speed = { 70, 180 }, color = PAL.GoldCore, color2 = PAL.Gold, size = 1.2, life = 0.5 })
	FX.sparks(f, pos, { count = 40, speed = { 30, 90 }, color = WHITE, color2 = PAL.Gold, size = 0.7 })
	FX.light(f, pos, PAL.Gold, 12, 60, 1)
	for i = 1, 6 do
		FX.bolt(f, pos + UP * 2, pos + FX.randUnit() * 14 + UP * 6, { color = PAL.Bolt, width = 0.18, life = 0.18, light = i == 1 })
	end
	if gh then
		Fx2.cracks(f, g, n, 12, PAL.Gold, 8)
		FX.rubble(f, g, { count = 18, radius = 8, up = { 40, 90 }, out = { 20, 50 } })
	end
	sound(SND.Boom, pos, 1.2, 0.95)
	sound(SND.Thunder, pos, 1, 1.15)
	Fx2.shake(3, 0.7, pos, 220)
	-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (Surge title removed)
	if isMe(d.userId) then
		FX.impact({ tint = PAL.Gold, lineColor = PAL.GoldCore, flashAlpha = 0.45 })
		Fx2.envelope({ fov = 10, bright = 0.12, contrast = 0.2, attack = 0.03, hold = 0.1, release = 0.6 })
	end
end

function handlers.FormEnd(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local f = castFolder("FormEnd", 2)
	local col = d.kind == "Surge" and PAL.Gold or PAL.Silver
	FX.ring(f, hrp.Position, UP, 10, 0.5, col, 0.4, { ease = "in" })
	FX.glow(f, hrp.Position, 8, col, 0.3)
	FX.sparks(f, hrp.Position, { count = 20, speed = { 5, 15 }, color = col, size = 0.4, accel = UP * 5 })
	sound(SND.Whoosh, hrp.Position, 0.5, 0.7)
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the silver form. For the caster a cutscene in five shots:
--   1  the still breath: the world drains to grey; the camera circles a calm body while six silver afterimages of it
--      orbit faster and faster, motes of light rise off the ground and two heartbeats ripple out
--   2  the light comes down: a shaft of silver light drops out of the sky onto the body and rings of light climb it
--      from the feet up; a worm's-eye view looks up through the shaft as the afterimages collapse into the body
--   3  the eyes open: an extreme close-up, a glint across the screen, an impact frame, the hair growing out
--   4  the shockwave: the body lifts off the ground and the burst tears out - layered domes, shards of light, a tornado
--      of silver / blue / violet ribbons, rings racing over the ground; the camera snaps wide and sweeps round
--   5  the hero shot: low and rising round the floating body as the aura roars, then home to the player's own view
-- Everyone nearby sees every one of those moments in the world.
local orbits = {}   -- the orbiting afterimages: { char, f, t0, life, ghosts = { { m, parts, phase, tr } } }
local vortices = {} -- the ribbon tornadoes: { f, pos, t0, life, helices }

-- a frozen glowing copy of a body (every limb, accessory and spike, in the pose it holds now) as one movable model
local function ghostModel(char, color)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "SilverGhost"
	local parts = {}
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.5 and (p.Parent == char or p.Parent:IsA("Accessory") or p.Parent.Name == "AscSpikes") then
			local ok, g = pcall(function()
				return p:Clone()
			end)
			if ok and g then
				for _, ch in ipairs(g:GetChildren()) do
					if not ch:IsA("SpecialMesh") then
						ch:Destroy()
					end
				end
				g.Anchored = true
				g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow, g.Massless = false, false, false, false, true
				g.Material = Enum.Material.Neon
				g.Color = color
				g.Transparency = 1
				if g:IsA("MeshPart") then
					pcall(function()
						g.TextureID = ""
					end)
				end
				local sm = g:FindFirstChildOfClass("SpecialMesh")
				if sm then
					sm.TextureId = ""
				end
				g.CFrame = p.CFrame
				g.Parent = m
				table.insert(parts, g)
			end
		end
	end
	m.WorldPivot = hrp.CFrame
	return m, parts
end

-- shards of silver light blown out of the burst, spinning and fading
local function silverShatter(parent, center, radius, count, pal)
	local PAL = pal or PAL
	local shards, cfs, st = {}, {}, {}
	for i = 1, count do
		local w = Instance.new("WedgePart")
		w.Name = "SilverShard"
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
		local glass = i % 3 == 0
		w.Material = glass and Enum.Material.Glass or Enum.Material.Neon
		w.Color = i % 3 == 1 and PAL.Silver or i % 3 == 2 and PAL.SilverBlue or PAL.SilverPurple
		w.Transparency = glass and 0.35 or 0.15
		w.Size = Vector3.new(0.25, 1.5 + math.random() * 4, 1.5 + math.random() * 4)
		local d = FX.randUnit()
		d = Vector3.new(d.X, math.abs(d.Y) * 0.8 + 0.1, d.Z).Unit
		local pos = center + d * radius * (0.3 + math.random() * 0.4)
		cfs[i] = CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, 0, math.random() * 6.28)
		w.CFrame = cfs[i]
		w.Parent = parent
		shards[i] = w
		st[i] = { v = d * (60 + math.random() * 70), spin = FX.randUnit() * (3 + math.random() * 6), base = w.Transparency }
	end
	local t, life = 0, 1.5
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t >= life or not shards[1].Parent then
			conn:Disconnect()
			for _, w in ipairs(shards) do
				w:Destroy()
			end
			return
		end
		local fade = math.clamp((t - life * 0.4) / (life * 0.6), 0, 1)
		for i, w in ipairs(shards) do
			local s = st[i]
			s.v += Vector3.new(0, -40, 0) * dt
			s.v *= 1 - 1.2 * dt
			cfs[i] = (cfs[i] + s.v * dt) * CFrame.fromAxisAngle(s.spin.Unit, s.spin.Magnitude * dt)
			w.Transparency = s.base + (1 - s.base) * fade
		end
		workspace:BulkMoveTo(shards, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

-- the anime eye glint: a line of light flashing across the middle of the screen
local function screenGlint()
	for i, spec in ipairs({ { 0.45, 5, 1.3 }, { 0.45, 2, 0.5 } }) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, spec[1])
		f.Size = i == 1 and UDim2.new(0, 0, 0, spec[2]) or UDim2.new(0, spec[2], 0, 0)
		f.BackgroundColor3 = WHITE
		f.BorderSizePixel = 0
		f.ZIndex = 39
		f.Parent = gui
		local g = Instance.new("UIGradient")
		g.Transparency = ns({ 0, 1 }, { 0.5, 0 }, { 1, 1 })
		g.Rotation = i == 1 and 0 or 90
		g.Parent = f
		Fx2.tween(f, 0.14, { Size = i == 1 and UDim2.new(spec[3], 0, 0, spec[2]) or UDim2.new(0, spec[2], spec[3], 0) }, Enum.EasingStyle.Quart)
		task.delay(0.16, function()
			Fx2.tween(f, 0.35, { BackgroundTransparency = 1 })
		end)
		Debris:AddItem(f, 0.6)
	end
end

local function updateCutFx(dt, clock)
	for i = #orbits, 1, -1 do
		local o = orbits[i]
		local PAL = o.pal or PAL
		local hrp = o.char.Parent and o.char:FindFirstChild("HumanoidRootPart")
		local t = clock - o.t0
		if not hrp or not o.f.Parent or t >= o.life then
			-- the collapse: every afterimage snaps into the body in a flash
			if hrp and o.f.Parent then
				FX.glow(o.f, hrp.Position, 16, PAL.Silver, 0.35)
				FX.ring(o.f, hrp.Position, UP, 10, 0.5, PAL.SilverCore, 0.25, { ease = "in" })
				FX.streaks(o.f, hrp.Position, { inward = 9, count = 30, color = PAL.SilverCore, color2 = PAL.SilverBlue, size = 0.6, life = 0.25 })
				sound(SND.Zap, hrp.Position, 0.6, 2.4)
			end
			for _, g in ipairs(o.ghosts) do
				g.m:Destroy()
			end
			table.remove(orbits, i)
		else
			local a = t / o.life
			local radius = 7.5 * (1 - a * a * a) + 0.4
			local spin = t * 1.4 + t * t * t * 1.2
			local tr = 0.5 + 0.5 * math.clamp(1 - t / 0.6, 0, 1) - 0.2 * a
			for _, g in ipairs(o.ghosts) do
				local ang = g.phase + spin
				local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang))
				local pos = hrp.Position + Vector3.new(math.cos(ang), 0, math.sin(ang)) * radius + UP * math.sin(t * 2 + g.phase) * 0.4
				g.m:PivotTo(CFrame.lookAt(pos, pos + tangent))
				if math.abs((g.tr or -1) - tr) > 0.02 then
					g.tr = tr
					for _, p in ipairs(g.parts) do
						p.Transparency = tr
					end
				end
			end
		end
	end
	for i = #vortices, 1, -1 do
		local v = vortices[i]
		local t = clock - v.t0
		if t >= v.life or not v.f.Parent then
			for _, h in ipairs(v.helices) do
				h:destroy()
			end
			table.remove(vortices, i)
		else
			-- each ribbon spirals up from the ground, the funnel widening as it climbs
			for j, h in ipairs(v.helices) do
				local height = -2 + math.max(t - (j - 1) * 0.12, 0) * 30
				h.radius = (1.5 + j * 1.5) + height * 0.18
				h:place(v.pos + UP * height, UP, dt)
			end
		end
	end
end

local function startCutscene(d)
	local char, _, hrp = myChar()
	if not char then
		return
	end
	local cam = workspace.CurrentCamera
	cutscene = {
		t0 = os.clock(), d = d, char = char, from = cam.CFrame, rootFrom = hrp.Position,
		look = flat(d.look, flat(hrp.CFrame.LookVector, FWD)), shaftAt = math.min(1.3, d.eyes - 0.5),
	}
	letterbox(true, 0.3)
	-- grey and dark until the burst, a narrow lens on the eyes, a wide punch on the shockwave
	Fx2.envelope({ sat = -0.75, contrast = 0.25, bright = -0.08, tint = AscPerk.pal(d.userId).SilverBlue, attack = 0.45, hold = math.max(d.burst - 0.45, 0), release = 0.9 })
	Fx2.envelope({ fov = -16, delay = d.eyes - 0.15, attack = 0.08, hold = d.burst - d.eyes, release = 0.05 })
	Fx2.envelope({ fov = 18, contrast = 0.2, bright = 0.1, delay = d.burst, attack = 0.04, hold = 0.25, release = 1 })
	faceUntil, faceDirV = os.clock() + d.cut, cutscene.look
end

local function endCutscene()
	local cs = cutscene
	if not cs then
		return
	end
	cutscene = nil
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local _, hum = myChar()
	if hum then
		cam.CameraSubject = hum
	end
	letterbox(false, 0.4)
end

local function updateCutscene(clock)
	local cs = cutscene
	if not cs then
		return
	end
	local char, _, hrp = myChar()
	local d = cs.d
	local el = clock - cs.t0
	if not char or char ~= cs.char or el >= d.cut then
		endCutscene()
		return
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local head = char:FindFirstChild("Head")
	local headP = head and head.Position or hrp.Position + UP * 1.5
	local look = cs.look
	local right = look:Cross(UP)
	local open = d.eyes - 0.15
	local cf
	if el < cs.shaftAt then
		-- 1: the still breath: a slow circle round the calm body
		local a = el / cs.shaftAt
		local e = a * a * (3 - 2 * a)
		local off = CFrame.fromAxisAngle(UP, R(-55 + 75 * e)):VectorToWorldSpace(look * (10 - 2.5 * e))
		cf = CFrame.lookAt(headP + off - UP * (0.7 - 0.4 * e), headP - UP * 0.5)
	elseif el < open then
		-- 2: the light comes down: a worm's-eye view up the body into the shaft
		local a = (el - cs.shaftAt) / (open - cs.shaftAt)
		local pos = hrp.Position + look * (5.5 - a) + right * (2.2 - 1.2 * a) - UP * 2.2
		cf = CFrame.lookAt(pos, headP + UP * (3 - 2 * a))
	elseif el < d.burst then
		-- 3: the eyes open: an extreme close-up
		local a = (el - open) / (d.burst - open)
		cf = CFrame.lookAt(headP + look * (2.5 - 0.5 * a) + UP * 0.1 + right * 0.12, headP + UP * 0.1)
	elseif el < d.burst + 0.8 then
		-- 4: the shockwave: snap wide and sweep round fast
		local a = (el - d.burst) / 0.8
		local e = 1 - (1 - a) ^ 3
		local off = CFrame.fromAxisAngle(UP, R(-70 + 110 * e)):VectorToWorldSpace(look * (24 + 6 * e))
		cf = CFrame.lookAt(hrp.Position + off + UP * (0.4 + 2 * e), hrp.Position + UP * 3)
	else
		-- 5: the hero shot: low and slowly rising round the floating body, then home to the player's view
		local a = math.clamp((el - d.burst - 0.8) / (d.cut - d.burst - 0.8), 0, 1)
		local off = CFrame.fromAxisAngle(UP, R(35 + 30 * a)):VectorToWorldSpace(look * (15 - 3 * a))
		cf = CFrame.lookAt(hrp.Position + off + UP * (0.3 + 3 * a), hrp.Position + UP * (2.6 + 0.4 * a))
		if a > 0.62 then
			local home = cs.from + (hrp.Position - cs.rootFrom)
			local b = (a - 0.62) / 0.38
			cf = cf:Lerp(home, b * b * (3 - 2 * b))
		end
	end
	cam.CFrame = cf
end

RunService:BindToRenderStep("AscendantCutscene", Enum.RenderPriority.Camera.Value + 1, function()
	local ok, err = pcall(updateCutscene, os.clock())
	if not ok then
		warn("[AscendantClient] cutscene: " .. tostring(err))
		cutscene = nil
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
	end
end)

function handlers.InstinctStart(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local mine = isMe(d.userId)
	local shaftAt = math.min(1.3, d.eyes - 0.5)
	-- the breath (in, out, deep in), the eyes opening, gathering, the lift-off, floating, settling into the guard
	pose(char, {
		{ t = 0.25, ease = { "Sine", "InOut" }, pose = POSE.BreatheOut },
		{ t = 0.75, ease = { "Sine", "InOut" }, pose = POSE.BreatheIn },
		{ t = 1.25, ease = { "Sine", "InOut" }, pose = POSE.BreatheOut },
		{ t = d.eyes - 0.2, ease = { "Sine", "InOut" }, pose = POSE.BreatheDeep },
		{ t = d.eyes + 0.1, ease = { "Quad", "Out" }, pose = POSE.Awake },
		{ t = d.burst - 0.1, ease = { "Sine", "InOut" }, pose = POSE.Gather },
		{ t = d.burst + 0.1, ease = { "Exponential", "Out" }, pose = POSE.Levitate },
		{ t = d.burst + 0.8, ease = { "Sine", "InOut" }, pose = POSE.LevitateHold },
		{ t = d.cut - 0.45, ease = { "Quad", "InOut" }, pose = POSE.Stance },
		{ t = d.cut, pose = POSE.Stance },
	}, d.cut + 0.3)
	local f = castFolder("InstinctStart", d.cut + 6)
	local pos = hrp.Position
	local g, _, gh = groundAt(pos, 14)
	local floor = gh and g + UP * 0.2 or pos - UP * 3
	-- silver motes rising from the ground around the still body
	local field = Fx2.part("MoteField", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, f)
	field.Transparency = 1
	field.Size = Vector3.new(18, 0.2, 18)
	field.CFrame = CFrame.new(floor)
	local motes = Fx2.emitter(field, {
		Texture = FX.TEX.star, Color = ColorSequence.new(WHITE, PAL.Silver), LightEmission = 1, Rate = 60,
		Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10),
		Size = ns({ 0, 0 }, { 0.2, 0.4 }, { 1, 0 }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
	})
	task.delay(d.burst, function()
		motes.Enabled = false
	end)
	local rocks = gh and FX.liftRocks(f, g, 16, 22) or nil
	task.delay(d.burst, function()
		if rocks and not rocks.dead then
			rocks:drop()
		end
	end)
	-- two heartbeats crossing the ground
	for _, at in ipairs({ 0.45, 1.0 }) do
		task.delay(at, function()
			if f.Parent then
				FX.ring(f, floor, UP, 2, 38, PAL.Silver, 1.1, { alpha = 0.4 })
				FX.ring(f, floor, UP, 1, 24, PAL.SilverBlue, 0.9, { alpha = 0.5 })
				FX.glow(f, pos, 10, PAL.Silver, 0.4, { alpha = 0.5 })
				sound(SND.HitHeavy, pos, 0.35, 0.45)
			end
		end)
	end
	-- six afterimages of the body, orbiting faster and faster until they collapse into it
	local orbit = { char = char, f = f, t0 = os.clock(), life = math.max(d.eyes - 0.12, 0.5), ghosts = {}, pal = PAL }
	for i = 1, 6 do
		local gm, parts = ghostModel(char, i % 2 == 0 and PAL.SilverBlue or PAL.Silver)
		if gm then
			gm.Parent = f
			table.insert(orbit.ghosts, { m = gm, parts = parts, phase = (i - 1) / 6 * math.pi * 2 })
		end
	end
	table.insert(orbits, orbit)
	-- the light comes down out of the sky onto the body, and rings of light climb it from the feet up
	task.delay(shaftAt, function()
		if not f.Parent then
			return
		end
		local top = 260
		local shafts = {}
		for i, spec in ipairs({ { PAL.SilverBlue, 0.7, 9 }, { PAL.SilverCore, 0.3, 3.2 } }) do
			local s = neon(i == 1 and "LightShaft" or "LightShaftCore", Enum.PartType.Cylinder, spec[1], f)
			s.Transparency = spec[2]
			s.Size = Vector3.new(top, 0.4, 0.4)
			s.CFrame = CFrame.new(floor + UP * top * 1.5) * VERT
			Fx2.tween(s, 0.28, { CFrame = CFrame.new(floor + UP * top / 2) * VERT, Size = Vector3.new(top, spec[3], spec[3]) }, Enum.EasingStyle.Quart)
			shafts[i] = s
		end
		task.delay(0.26, function()
			if f.Parent then
				FX.ring(f, floor, UP, 2, 16, PAL.Silver, 0.6, { alpha = 0.1 })
				FX.glow(f, floor + UP * 2, 14, PAL.SilverCore, 0.5)
				Fx2.dust(f, floor, 3, 8)
				sound(SND.Rise, pos, 0.9, 1.1)
			end
		end)
		for i = 0, 6 do
			task.delay(0.3 + i * 0.1, function()
				if f.Parent then
					FX.ring(f, floor + UP * (0.3 + i * 0.95), UP, 2.5, 7.5, i % 2 == 0 and PAL.Silver or PAL.SilverBlue, 0.4, { alpha = 0.15 })
				end
			end)
		end
		-- the burst blows the shaft apart
		task.delay(math.max(d.burst - shaftAt, 0), function()
			for i, s in ipairs(shafts) do
				if s.Parent then
					Fx2.tween(s, i == 1 and 0.7 or 0.5, { Size = Vector3.new(top, i == 1 and 30 or 12, i == 1 and 30 or 12), Transparency = 1 })
				end
			end
		end)
	end)
	-- power crackling inward from the eyes opening to the burst
	task.delay(d.eyes, function()
		local t0 = os.clock()
		while os.clock() - t0 < d.burst - d.eyes and f.Parent and hrp.Parent do
			local c = hrp.Position
			FX.streaks(f, c, { inward = 9, count = 10, color = PAL.SilverCore, color2 = PAL.SilverPurple, size = 0.45, life = 0.28 })
			Fx2.shake(mine and 0.8 or 0.4, 0.1, c, 160)
			task.wait(0.08)
		end
	end)
	sound(SND.Hum, pos, 0.8, 0.55)
	if mine then
		rootUntil = os.clock() + d.cut
		startCutscene(d)
	elseif hears(pos, 150) then
		Fx2.envelope({ sat = -0.45, contrast = 0.12, attack = 0.5, hold = math.max(d.burst - 0.5, 0), release = 0.8 })
	end
end

function handlers.InstinctEyes(d)
	local PAL = AscPerk.pal(d.userId)
	local char = charOf(d.userId)
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local f = castFolder("Eyes", 2)
	local p = head.Position + head.CFrame.LookVector * (head.Size.Z * 0.5) + head.CFrame.UpVector * head.Size.Y * 0.15
	FX.glow(f, p, 5, PAL.Silver, 0.4)
	FX.streaks(f, p, { count = 16, speed = { 20, 45 }, color = WHITE, color2 = PAL.Silver, size = 0.25, life = 0.25 })
	-- a horizontal glint across both eyes
	local glint = neon("EyeGlint", Enum.PartType.Block, WHITE, f)
	glint.Size = Vector3.new(0.1, 0.06, 0.04)
	glint.CFrame = CFrame.lookAt(p, p + head.CFrame.LookVector)
	Fx2.tween(glint, 0.22, { Size = Vector3.new(8, 0.05, 0.04), Transparency = 1 }, Enum.EasingStyle.Quart)
	sound(SND.Zap, p, 0.6, 2.8)
	sound(SND.Rise, p, 0.6, 1.4)
	if isMe(d.userId) or hears(head.Position, 150) then
		showTitle("Instinct", 2.4)
	end
	if isMe(d.userId) then
		screenGlint()
		FX.impact({ tint = PAL.Silver, lineColor = PAL.SilverBlue, flashAlpha = 0.3, lines = false })
	end
end

function handlers.InstinctBurst(d)
	local PAL = AscPerk.pal(d.userId)
	local pos, rad = d.pos, d.radius
	local f = castFolder("InstinctBurst", 8)
	local g, n, gh = groundAt(pos, 14)
	local floor = gh and g + UP * 0.4 or pos
	-- the violent shockwave of a calm body: layered domes of silver, deep blue and violet, shards of light
	FX.shell(f, pos, 2, rad * 0.5, PAL.SilverCore, 0.4)
	FX.shell(f, pos, 3, rad * 0.8, PAL.SilverBlue, 0.65, Enum.Material.ForceField)
	FX.shell(f, pos, 4, rad, PAL.SilverPurple, 0.85, Enum.Material.ForceField)
	silverShatter(f, pos, rad * 0.5, 44, PAL)
	-- rings racing over the ground, one after another
	for _, spec in ipairs({ { 0, PAL.Silver, 2.4 }, { 0.1, PAL.SilverBlue, 1.9 }, { 0.2, PAL.SilverPurple, 1.4 }, { 0.32, PAL.SilverCore, 1 } }) do
		task.delay(spec[1], function()
			if f.Parent then
				FX.ring(f, floor, UP, 3, rad * spec[3], spec[2], 0.9)
			end
		end)
	end
	pillar(f, pos, PAL.SilverBlue, PAL.SilverCore, 110, 8, 1.3)
	-- a tornado of silver, blue and violet ribbons spiralling up out of the ground
	table.insert(vortices, {
		f = f, pos = floor, t0 = os.clock(), life = 1.5,
		helices = {
			FX.helix(f, { PAL.SilverCore, PAL.SilverBlue }, 3, 0.6),
			FX.helix(f, { PAL.SilverPurple, PAL.Silver }, 4.5, 0.5),
			FX.helix(f, { PAL.SilverBlue, PAL.SilverPurple }, 6, 0.45),
		},
	})
	FX.streaks(f, pos, { count = 80, speed = { 90, 220 }, color = PAL.SilverCore, color2 = PAL.SilverBlue, size = 1.3, life = 0.6 })
	FX.sparks(f, pos, { count = 50, speed = { 30, 100 }, color = WHITE, color2 = PAL.SilverPurple, size = 0.7 })
	FX.light(f, pos, PAL.Silver, 14, 60, 1.2)
	if gh then
		Fx2.cracks(f, g, n, 16, PAL.SilverBlue, 9)
		FX.rubble(f, g, { count = 24, radius = 10, up = { 50, 100 }, out = { 30, 70 } })
		for i = 1, 10 do
			local ang = i / 10 * math.pi * 2
			Fx2.dust(f, floor + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 9, 4, 3)
		end
	end
	-- and silver sparkles drifting down after it
	local plate = Fx2.part("SparkRain", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, f)
	plate.Transparency = 1
	plate.Size = Vector3.new(40, 0.2, 40)
	plate.CFrame = CFrame.new(pos + UP * 22)
	local rain = Fx2.emitter(plate, {
		Texture = FX.TEX.star, Color = ColorSequence.new(WHITE, PAL.Silver), LightEmission = 1, Rate = 90,
		Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(4, 8), EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = -UP * 4, Size = ns({ 0, 0.5 }, { 1, 0 }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
	})
	task.delay(1.6, function()
		rain.Enabled = false
	end)
	sound(SND.Boom, pos, 1.3, 0.8)
	sound(SND.Thunder, pos, 1, 0.9)
	sound(SND.HitHeavy, pos, 0.8, 0.7)
	Fx2.shake(3.2, 0.8, pos, 260)
	if isMe(d.userId) then
		FX.flash(WHITE, 0.7, 0.4)
		FX.impact({ tint = PAL.Silver, lineColor = PAL.SilverPurple, flashAlpha = 0.4, lineTime = 0.5 })
		FX.speedLines(0.8, { color = PAL.Silver, alpha = 0.7, count = 60, inner = 0.3 })
	elseif hears(pos, 200) then
		FX.flash(PAL.Silver, 0.25, 0.3)
	end
end

---------------------------------------------------------------------------------------------------
-- every frame
local deadLocked = false
local lastWalk, lastJump = nil, nil
local baseJump = { jp = 50, jh = 7.2 }
local appliedMove = false

-- this client owns its movement: the forms' multipliers and the casts' rooting are written here, only on change, so
-- other systems' own holds on the humanoid are not fought every frame
local function updateMovement(char, hum, clock)
	if not equipped() then
		if appliedMove then
			appliedMove = false
			lastWalk, lastJump = nil, nil
			hum.WalkSpeed = char:GetAttribute("KitWalkSpeed") or 16
			hum.JumpPower, hum.JumpHeight = baseJump.jp, baseJump.jh
		end
		return
	end
	appliedMove = true
	local rooted = clock < rootUntil
	local walk = rooted and 0 or (char:GetAttribute("KitWalkSpeed") or 16) * (char:GetAttribute("AscWalkMul") or 1)
	local jm = char:GetAttribute("AscJumpMul") or 1
	local jump = rooted and 0 or jm
	if walk ~= lastWalk then
		lastWalk = walk
		hum.WalkSpeed = walk
	end
	if jump ~= lastJump then
		lastJump = jump
		hum.JumpPower = baseJump.jp * jump
		hum.JumpHeight = baseJump.jh * jump * jump
	end
end

local function frame(dt)
	local clock = os.clock()
	for id, b in pairs(beams) do
		local alive = b.char and b.char.Parent
		if alive and b.phase == "charge" then
			updateCharge(b, dt, clock)
		elseif alive and b.phase == "fire" then
			updateFire(b, dt, clock)
		elseif b.phase == "fade" then
			updateFade(b, clock)
		end
		if not alive or (b.dieAt and clock >= b.dieAt) then
			beams[id] = nil
			endBeam(b)
		end
	end
	syncFlyers(clock)
	syncLooks(clock)
	updateCutFx(dt, clock)

	local char, hum, hrp = myChar()
	if hum then
		updateFlight(dt, clock)
		-- during the beam's charge the body turns to the cursor and the server is told where it is
		if clock < beamAimUntil then
			local tgt = cursorTarget()
			faceUntil, faceDirV = math.max(faceUntil, clock + 0.05), tgt - hrp.Position
			if clock >= nextAimSend then
				nextAimSend = clock + 0.1
				Request:FireServer("BeamAim", { target = tgt })
			end
		end
		-- turned toward the aim during a cast (in the air the flight controller does the turning)
		if not flight then
			if clock < faceUntil and faceDirV then
				hum.AutoRotate = false
				faceDir(hrp, faceDirV)
			elseif not hum.AutoRotate then
				hum.AutoRotate = true
			end
		end
		updateMovement(char, hum, clock)
		if tumbleUntil > 0 and clock >= tumbleUntil then
			tumbleUntil = 0
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		-- the silver form cannot be killed outright (the server undoes the damage); re-armed when it ends
		local inst = char:GetAttribute("AscForm") == "Instinct"
		if inst ~= deadLocked then
			deadLocked = inst
			hum:SetStateEnabled(Enum.HumanoidStateType.Dead, not inst)
		end
	end

	-- HUD
	local on = equipped()
	bar.Visible = on and not cutscene
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local t = now()
	local timers = {}
	local form = char and char:GetAttribute("AscForm")
	local formUntil = char and char:GetAttribute("AscFormUntil")
	local inInstinct = form == "Instinct"
	pillLabel.Text = inInstinct and CFG.Labels.Flurry or CFG.Labels.Instinct
	pillSub.Text = inInstinct and CFG.Callouts.Flurry.sub or CFG.Callouts.Instinct.sub
	for skill, b in pairs(buttons) do
		local key = (skill == "Instinct" and inInstinct) and "Flurry" or skill
		local active = form == skill and formUntil and formUntil > t
		if active then
			table.insert(timers, string.format("%s %ds", CFG.Labels[skill], math.ceil(formUntil - t)))
		end
		if active and skill == "Surge" then
			b.cd.Size = UDim2.fromScale(1, 0)
			b.cdText.Text = ""
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(clock * 6)
		else
			b.stroke.Transparency = active and (0.5 + 0.5 * math.sin(clock * 6)) or 0.1
			local rem = cooldownEnd[key] - t
			local frac = math.clamp(rem / math.max(COOLDOWN[key] * AscPerk.cdMul(key), rem), 0, 1)
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
	flightStroke.Transparency = flight and 0 or 0.45
	flightStroke.Thickness = flight and 3 or 2
	flightText.Text = flight and "FLYING" or CFG.Labels.Flight
	if flight then
		table.insert(timers, 1, "FLIGHT")
	end
	status.Text = table.concat(timers, "   ")
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok then
		warn("[AscendantClient] frame: " .. tostring(err))
	end
end)

Broadcast.OnClientEvent:Connect(function(kind, data)
	local h = handlers[kind]
	if h and type(data) == "table" then
		local ok, err = pcall(h, data)
		if not ok then
			warn("[AscendantClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

local function onCharacter(char)
	if flight then
		stopFlight("respawn")
	end
	flight = nil
	rootUntil, faceUntil, tumbleUntil, beamAimUntil = 0, 0, 0, 0
	lastWalk, lastJump, deadLocked = nil, nil, false
	endCutscene()
	task.spawn(watchBody, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		baseJump = { jp = hum.JumpPower, jh = hum.JumpHeight }
	end
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Studio-only test hook: lets a test script fly, steer, aim and cast without a keyboard
if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "AscendantDebug"
	hook.OnInvoke = function(cmd, a, b)
		if cmd == "fly" then
			if a then
				startFlight()
			else
				stopFlight("toggle")
			end
			return flight ~= nil
		elseif cmd == "input" then
			debugInput = a
		elseif cmd == "aim" then
			debugCursor = a
		elseif cmd == "cast" then
			request(a)
		elseif cmd == "strike" then
			tryStrike()
		elseif cmd == "state" then
			local char, hum, hrp = myChar()
			local cam = workspace.CurrentCamera
			local lookParts = 0
			local lk = char and looks[char]
			if lk then
				lookParts = #lk.parts
			end
			local nb = 0
			for _ in pairs(beams) do
				nb += 1
			end
			return {
				flying = flight ~= nil, pos = hrp and hrp.Position, vel = hrp and hrp.AssemblyLinearVelocity,
				state = hum and hum:GetState().Name, walk = hum and hum.WalkSpeed, jump = hum and hum.JumpPower,
				form = char and char:GetAttribute("AscForm"), look = lk and lk.kind, lookParts = lookParts,
				cutscene = cutscene ~= nil, camType = cam.CameraType.Name, beams = nb, wind = char and flyFx[char] ~= nil,
				attrFlying = char and char:GetAttribute("Flying"), ownM1 = char and char:GetAttribute("OwnM1"),
				bar = bar.Visible, deadEnabled = hum and hum:GetStateEnabled(Enum.HumanoidStateType.Dead),
				lobes = lk and #lk.lobes or 0, grown = lk and lk.grown, orbits = #orbits, vortices = #vortices,
			}
		end
		return nil
	end
	hook.Parent = script
end

print(string.format("[AscendantClient] ready - F/2xSpace %s | Q %s | E %s | R %s | G %s", CFG.Labels.Flight, CFG.Labels.Beam, CFG.Labels.Warp, CFG.Labels.Surge, CFG.Labels.Instinct))
