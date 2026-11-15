--!nocheck
-- StormdrawClient: input, ability bar and local body for the Stormdraw kit (the lightning katana fighter), plus the
-- playback of every cast the server broadcasts - poses, the sword, lightning, afterimages, the dragon. It only renders
-- and moves its OWN character (a dash, a lunge, a root): hits, damage and ragdolls are decided by
-- ServerScriptService.StormdrawServer. Skill-name free: labels, colours, sounds and timings come from
-- ReplicatedStorage.StormdrawKit.Config; the look of each piece from StormdrawKit.Client (Poses, Katana, StormFX, Dragon).
--   M1 / tap  Slash   the sword string (hold to keep swinging; locks onto the body in front, like every M1 here)
--   Q Flash   E Chain   R Focus   G Dragon (the ultimate) - keys through HudShared.Keybinds, so they can be rebound
-- Every client draws every Stormdraw fighter's sword (Katana) and Focus effects (from the FocusUntil attribute).
-- Studio test hook: script.StormDebug (BindableFunction) - ("req", skill), ("slash"), ("state") -> JSON.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local StarterPlayer = game:GetService("StarterPlayer")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("StormdrawKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local Mods = Kit:WaitForChild("Client")
local Poses = require(Mods:WaitForChild("Poses"))
local Katana = require(Mods:WaitForChild("Katana"))
local StormFX = require(Mods:WaitForChild("StormFX"))
local Dragon = require(Mods:WaitForChild("Dragon"))
local GojoClient = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local FX = require(GojoClient:WaitForChild("GojoFX")) -- bolts, arcs, glows, rings, streaks, impact frames
local Animator = require(GojoClient:WaitForChild("ProceduralAnimator"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib")) -- envelopes, cracks, shake
local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback")) -- hit-confirm
local HudShared = ReplicatedStorage:WaitForChild("HudShared")
local Keybinds = require(HudShared:WaitForChild("Keybinds"))
local BAL = require(ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Balance"))

local SND = CFG.Sounds
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

local Folder = Instance.new("Folder")
Folder.Name = "StormdrawFX"
Folder.Parent = workspace
StormFX.init(Folder)

-- a caster's colourway: Config.AltPalette while their player's Skin attribute is "Alt", else the normal palette
local PAL_BASE = CFG.Palette
local PAL_ALT = table.clone(CFG.Palette)
for k, v in pairs(CFG.AltPalette or {}) do
	PAL_ALT[k] = v
end
local function palOf(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
	return (p and p:GetAttribute("Skin") == "Alt") and PAL_ALT or PAL_BASE
end
local function palOfChar(char)
	local p = char and Players:GetPlayerFromCharacter(char)
	return palOf(p and p.UserId)
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

local function charOf(userId)
	local p = Players:GetPlayerByUserId(tonumber(userId) or 0)
	local c = p and p.Character
	return (c and c.Parent) and c or nil
end

local function hrpOf(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function torsoOf(model)
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
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

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function near(pos, dist)
	return typeof(pos) == "Vector3" and (pos - camPos()).Magnitude <= (dist or 220)
end

---------------------------------------------------------------------------------------------------
-- rays: the ground, and the world point under the cursor
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
local function groundAt(pos)
	groundParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(pos + UP * 4, Vector3.new(0, -80, 0), groundParams)
	return hit and hit.Position or pos - UP * 3
end

-- the world point under the cursor (the screen centre on touch-only devices); lands on bodies too
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local function cursorTarget()
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
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
	return hit and hit.Position or ray.Origin + ray.Direction * 1000
end

local function sound(id, pos, vol, speed)
	if not id or typeof(pos) ~= "Vector3" then
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

local function play(char, clip, opts)
	if char and char.Parent and clip then
		Animator.stopAll(char, 0.05)
		return Animator.play(char, clip, opts)
	end
end

-- the CFrame that moves a copy of `char` (as it stands now) so its root stands at `pos` facing `dir`
local function rootOffset(char, pos, dir)
	local hrp = hrpOf(char)
	if not hrp or typeof(pos) ~= "Vector3" then
		return nil
	end
	local f = flat(dir, flat(hrp.CFrame.LookVector, -Vector3.zAxis))
	return CFrame.lookAt(pos, pos + f) * hrp.CFrame:Inverse()
end

-- lock-on feedback: the body a move locked onto glows for a moment
local function markTarget(model, pal, seconds)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillColor, h.OutlineColor = pal.Bolt, pal.BoltCore
	h.FillTransparency, h.OutlineTransparency = 0.7, 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = Folder
	Fx2.tween(h, seconds, { FillTransparency = 1, OutlineTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(h, seconds + 0.1)
end

-- static snapping on a body for a while (a body a dash has cut, before the cut lands)
local function staticOn(model, pal, seconds)
	if typeof(model) ~= "Instance" or not model.Parent then
		return
	end
	StormFX.crackle(function()
		local t = model.Parent and torsoOf(model)
		return t and t.Position or nil
	end, pal, seconds, 2.2, 0.05)
end

---------------------------------------------------------------------------------------------------
-- the sword: drawn while a move holds it, sheathed (with a click) once that time runs out
local blades = setmetatable({}, { __mode = "k" }) -- [character] = { drawnUntil }
local function bladeOf(char)
	local b = blades[char]
	if not b then
		b = { drawnUntil = 0 }
		blades[char] = b
	end
	return b
end
local function drawFor(char, seconds)
	if char then
		local b = bladeOf(char)
		b.drawnUntil = math.max(b.drawnUntil, os.clock() + seconds)
	end
end
local function sheatheNow(char)
	if char then
		bladeOf(char).drawnUntil = 0
	end
end
local function updateBlades(clock)
	for char, b in pairs(blades) do
		local rig = Katana.get(char)
		if rig then
			local want = clock < b.drawnUntil
			if rig.drawn ~= want then
				Katana.setDrawn(char, want)
				local m = Katana.mouth(char)
				if m and near(m, 160) then
					local pal = palOfChar(char)
					sound(SND.Hit, m, want and 0.35 or 0.55, want and 2.4 or 3) -- the ring of the draw / the click home
					FX.sparks(Folder, m, { color = pal.BoltCore, color2 = pal.Bolt, count = want and 5 or 10, speed = { 6, 20 }, size = 0.35, life = 0.35 })
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- my body: rooted through wind-ups, turned toward the aim, driven along a dash, Focus's speed and jump
local rootUntil, faceUntil, faceDirV, busyUntil = 0, 0, nil, 0
local drive = nil -- { from, to, t0, time, face, pin, exit }
local turnedOff = false
local baseJump = { jp = StarterPlayer.CharacterJumpPower, jh = StarterPlayer.CharacterJumpHeight }
local applied, lastWalk, lastJump = false, nil, nil

-- move my root from -> to over `time` seconds (0 = snap). opts.pin: stay held at `to` until releaseDrive();
-- opts.exit: studs/s of forward speed kept when it ends. Written by CFrame every frame (before physics and before
-- rendering), with no velocity of its own, so the body neither falls nor shoves anything on the way through.
local function driveTo(from, to, time, dir, opts)
	opts = opts or {}
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	drive = { from = from, to = to, t0 = os.clock(), time = math.max(time or 0, 0), face = flat(dir, flat(to - from, nil)),
		pin = opts.pin, exit = opts.exit or 0 }
end

local function releaseDrive(exitSpeed)
	local d = drive
	drive = nil
	local _, _, hrp = myChar()
	if d and hrp then
		hrp.AssemblyLinearVelocity = (d.face or Vector3.zero) * (exitSpeed or d.exit or 0)
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

local function applyDrive()
	local d = drive
	if not d then
		return
	end
	local _, _, hrp = myChar()
	if not hrp then
		drive = nil
		return
	end
	local k = d.time > 0 and math.clamp((os.clock() - d.t0) / d.time, 0, 1) or 1
	local pos = d.from:Lerp(d.to, k)
	local face = d.face or flat(hrp.CFrame.LookVector, -Vector3.zAxis)
	hrp.CFrame = CFrame.lookAt(pos, pos + face)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	if k >= 1 and not d.pin then
		releaseDrive()
	end
end
RunService.PreSimulation:Connect(applyDrive)
RunService.PreRender:Connect(applyDrive)

-- walk / jump: the kit's base (KitWalkSpeed, written by VulpineServer.KitServer at spawn) x Focus's multipliers, 0
-- while rooted. Written only when it changes, so PerkMovement's per-frame speed multiplier sits on top of it (the
-- same scheme the Ascendant kit uses). The jump keeps x JumpMul of its launch speed in either jump mode.
local function updateMovement(char, hum, clock)
	if not equipped() then
		if applied then
			applied = false
			lastWalk, lastJump = nil, nil
			hum.WalkSpeed = char:GetAttribute("KitWalkSpeed") or StarterPlayer.CharacterWalkSpeed
			hum.JumpPower, hum.JumpHeight = baseJump.jp, baseJump.jh
		end
		return
	end
	applied = true
	local rooted = clock < rootUntil or drive ~= nil
	local walk = rooted and 0 or (char:GetAttribute("KitWalkSpeed") or StarterPlayer.CharacterWalkSpeed) * (char:GetAttribute("StormWalkMul") or 1)
	local jm = rooted and 0 or (char:GetAttribute("StormJumpMul") or 1)
	if walk ~= lastWalk then
		lastWalk = walk
		hum.WalkSpeed = walk
	end
	if jm ~= lastJump then
		lastJump = jm
		hum.JumpPower = baseJump.jp * jm
		hum.JumpHeight = baseJump.jh * jm * jm
	end
end

local function updateBody(clock)
	local char, hum, hrp = myChar()
	if not hum then
		return
	end
	updateMovement(char, hum, clock)
	local holding = drive ~= nil or (clock < faceUntil and faceDirV ~= nil)
	if holding and equipped() then
		hum.AutoRotate = false
		turnedOff = true
		if not drive then
			local f = flat(faceDirV, nil)
			if f then
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + f)
			end
		end
	elseif turnedOff then
		turnedOff = false
		hum.AutoRotate = true
	end
end

local function iAmStunned(char)
	local t = now()
	return (tonumber(char:GetAttribute("StunnedUntil")) or 0) > t or char:GetAttribute("Ragdolled") == true
		or (tonumber(char:GetAttribute("DownUntil")) or 0) > t
end

---------------------------------------------------------------------------------------------------
-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "StormdrawHUD"
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
-- a label that names a key: drawn now and redrawn whenever the player rebinds
local function keyText(label, make)
	label.Text = make()
	Keybinds.Changed:Connect(function()
		label.Text = make()
	end)
	return label
end

-- cinematic letterbox bars (the ultimate)
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
local titleHolder = Instance.new("Frame")
titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
titleHolder.Position = UDim2.fromScale(0.5, 0.25)
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

-- the ability bar (MoveDock redraws it as the shared bottom bar: it reads each button's key chip, name and the
-- seconds label, and a wide button is the ultimate)
local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -22, 1, -22)
bar.Size = UDim2.fromOffset(330, 112)
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

local cooldownEnd = { Flash = 0, Chain = 0, Focus = 0, Dragon = 0 }
local cooldownDur = { Flash = 0, Chain = 0, Focus = 0, Dragon = 0 }
local buttons = {}
local trySlash -- the M1 (below, with the sword string)

local function request(skill)
	if not equipped() or not myChar() then
		return
	end
	Request:FireServer(skill, { aim = workspace.CurrentCamera.CFrame.LookVector, target = cursorTarget() })
end

local function skillButton(id, size, x)
	local co = CFG.Callouts[id]
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
	uiText(b, { Size = UDim2.new(1, -8, 0, 12), Position = UDim2.new(0, 4, 1, -18), Text = CFG.Labels[id] or id, ZIndex = 2 })
	-- the key chip (after the orb: MoveDock takes the LAST short label inside a child frame as the key)
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.85)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	local chipLabel = uiText(chip, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, ZIndex = 2 })
	if id == "Slash" then
		chipLabel.Text = "M1"
	else
		keyText(chipLabel, function()
			return Keybinds.label(CFG.Keys[id])
		end)
	end
	if co.hint then
		uiText(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Text = co.hint, Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.35) })
	end
	if id ~= "Slash" then
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
	end
	b.Activated:Connect(function()
		if id == "Slash" then
			if trySlash then
				trySlash()
			end
		else
			request(id)
		end
	end)
end
skillButton("Slash", 72, -246)
skillButton("Flash", 72, -164)
skillButton("Chain", 72, -82)
skillButton("Focus", 72, 0)

-- the ultimate on its own wide button above the row
do
	local co = CFG.Callouts.Dragon
	local b = Instance.new("TextButton")
	b.Name = "Dragon"
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
		return Keybinds.label(CFG.Keys.Dragon)
	end)
	uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Dragon, ZIndex = 2 })
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
	buttons.Dragon = { cd = cd, cdText = cdText, stroke = st, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Dragon")
	end)
end

local function updateHud(clock)
	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	barScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 720, 0.75, 1.3)
	local t = now()
	local char = player.Character
	local focusUntil = char and tonumber(char:GetAttribute("FocusUntil")) or 0
	local timers = {}
	for skill, b in pairs(buttons) do
		if skill == "Focus" and focusUntil > t then
			b.cd.Size = UDim2.fromScale(1, 0)
			b.cdText.Text = ""
			b.stroke.Transparency = 0.5 + 0.5 * math.sin(clock * 6)
			table.insert(timers, string.format("%s %ds", CFG.Labels.Focus, math.ceil(focusUntil - t)))
		else
			b.stroke.Transparency = 0.1
			local rem = (cooldownEnd[skill] or 0) - t
			local frac = math.clamp(rem / math.max(cooldownDur[skill] or 0, rem, 0.01), 0, 1)
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

---------------------------------------------------------------------------------------------------
-- cast playback
local handlers = {}
local casts = {} -- [cast id] = { crackle = Folder } (wind-ups that a later event ends)

local function endCast(id)
	local c = casts[id]
	casts[id] = nil
	if c and c.crackle then
		c.crackle:Destroy()
	end
end

function handlers.Cooldown(d)
	if typeof(d.ends) == "number" and cooldownEnd[d.skill] ~= nil then
		cooldownEnd[d.skill] = d.ends
		cooldownDur[d.skill] = tonumber(d.dur) or 0
	end
end

-- a batch of hits from the server: the attacker's hit-confirm (numbers come from the game's DamageFeed)
function handlers.Hits(d)
	Feedback.hits(d)
end

---------------------------------------------------------------------------------------------------
-- M1: the sword string. Each cut hangs a crescent of light in the air along the blade's path; inside Focus the cuts
-- come faster, wider and throw lightning.
local SLASH_ARCS = {
	{ roll = 35, a0 = -85, a1 = 85 },                         -- 1: rising draw cut, low left -> high right
	{ roll = 40, a0 = 85, a1 = -85 },                         -- 2: return cut, high right -> low left
	{ roll = 0, a0 = -170, a1 = 170, segs = 22, radius = 6.2 }, -- 3: the spinning cut, all the way round
	{ roll = 90, a0 = 75, a1 = -70 },                         -- 4: the cleave, overhead and down
}
local function slashFx(char, combo, dir, focus, pal)
	local hrp = hrpOf(char)
	if not hrp then
		return
	end
	local A = SLASH_ARCS[combo] or SLASH_ARCS[1]
	local c = hrp.Position + UP * 0.4 + dir * 0.5
	local cf = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, 0, math.rad(A.roll))
	local radius = (A.radius or 5.4) * (focus and 1.15 or 1)
	StormFX.slashArc(cf, radius, A.a0, A.a1, pal, { width = focus and 2.2 or 1.5, life = 0.24, segments = A.segs })
	if focus then
		-- the blade throws lightning along the cut
		local f = StormFX.folder("FocusCut", 1)
		for _ = 1, 3 do
			local a = math.rad(A.a0 + (A.a1 - A.a0) * (0.2 + 0.6 * math.random()))
			local p = cf * Vector3.new(math.sin(a) * radius, 0, -math.cos(a) * radius)
			FX.bolt(f, c, p, { color = pal.Bolt, core = pal.BoltCore, width = 0.12, jag = 0.3, life = 0.1 })
		end
	end
end

local function playSlash(char, combo, dir, focus)
	local clip = Poses.Slash[combo] or Poses.Slash[1]
	local speed = focus and 1 / CFG.Slash.FocusSpeedMul or 1
	play(char, clip, { speed = speed })
	drawFor(char, clip.length / speed + CFG.Katana.SheatheAfter)
	local hitT = clip.hitAt / speed
	Katana.swing(char, hitT + 0.14)
	local pal = palOfChar(char)
	local hrp = hrpOf(char)
	if hrp then
		sound(SND.Whoosh, hrp.Position, 0.6, (1.3 + combo * 0.08) * (focus and 1.15 or 1))
		if focus then
			sound(SND.Zap, hrp.Position, 0.3, 1.7)
		end
	end
	task.delay(hitT * 0.75, function()
		if char.Parent then
			slashFx(char, combo, dir, focus, pal)
		end
	end)
end

function handlers.Slash(d)
	if isMe(d.userId) then
		return -- already played the moment it was pressed
	end
	local char = charOf(d.userId)
	if char and typeof(d.dir) == "Vector3" then
		playSlash(char, d.combo, d.dir, d.focus)
	end
end

function handlers.SlashHit(d)
	local pal = palOf(d.userId)
	local dir = typeof(d.dir) == "Vector3" and d.dir or Vector3.zAxis
	for _, h in ipairs(d.hits or {}) do
		if typeof(h.p) == "Vector3" then
			local f = StormFX.folder("SlashHit", 2)
			StormFX.crossSlash(h.p, dir, pal, d.final and 9 or 6, not d.final)
			FX.sparks(f, h.p, { color = pal.Steel, color2 = pal.Slash, count = d.final and 30 or 16, speed = { 20, 80 }, size = 0.5 })
			FX.streaks(f, h.p, { dir = dir, spread = 30, speed = { 50, 130 }, count = d.final and 20 or 10, color = pal.BoltCore, color2 = pal.Slash, size = 0.7 })
			sound(SND.Hit, h.p, 0.8, 1.5 + math.random() * 0.2)
			if d.focus then
				-- Focus: every cut that lands bursts into small golden arcs
				FX.arcs(f, h.p, 3.2, { count = d.final and 6 or 3, outward = true, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.12, life = 0.12 })
				sound(SND.Zap, h.p, 0.5, 1.4)
			end
			if d.final then
				sound(SND.HitHeavy, h.p, 0.9, 1.1)
				FX.ring(f, h.p, dir, 1, d.focus and 22 or 14, pal.Slash, 0.3)
				if d.focus then
					StormFX.skyBolt(groundAt(h.p), pal, { power = 0.55, height = 70, forks = 1, cracks = false })
				end
			end
		end
	end
	if isMe(d.userId) and d.final then
		FX.impact({ tint = pal.Bolt, lineColor = pal.BoltCore, flashAlpha = 0.2, lineTime = 0.25 })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 1: the flash. A low draw stance with static snapping round the scabbard and a thunderclap; then the dasher
-- vanishes, a thick jagged bolt is left from where they stood to where they land, and a beat later every body on
-- the line is cut.
function handlers.FlashStart(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local pal = palOf(d.userId)
	local hrp = hrpOf(char)
	play(char, Poses.hold(Poses.Iai, d.windup + 0.25, 0.06, 0.05))
	sheatheNow(char)
	if hrp then
		sound(SND.Thunder, hrp.Position, 0.9, 1.3) -- the thunderclap
		sound(SND.Crackle, hrp.Position, 0.9, 1.15)
		local g = groundAt(hrp.Position)
		FX.ring(Folder, g + UP * 0.25, UP, 16, 2, pal.Bolt, d.windup, { ease = "in" })
		FX.streaks(Folder, hrp.Position, { inward = 8, count = 18, life = d.windup, size = 0.6, color = pal.BoltCore, color2 = pal.Bolt })
		Fx2.dust(Folder, g, 3.5, 4)
	end
	casts[d.id] = {
		crackle = StormFX.crackle(function()
			return char.Parent and Katana.mouth(char) or nil
		end, pal, d.windup + 0.05, 1.6, 0.03),
	}
	if isMe(d.userId) then
		rootUntil = os.clock() + d.windup + 0.3
		faceUntil, faceDirV = os.clock() + d.windup + 0.1, d.dir
		busyUntil = os.clock() + d.windup + 0.4
		showTitle("Flash")
		markTarget(d.target, pal, d.windup + 0.5)
		Fx2.envelope({ fov = -5, contrast = 0.1, attack = d.windup * 0.8, release = 0.1 })
	end
end

function handlers.FlashCancel(d)
	endCast(d.id)
	local char = charOf(d.userId)
	if char then
		Animator.stopAll(char, 0.15)
	end
	if isMe(d.userId) then
		rootUntil, busyUntil = 0, 0
	end
end

function handlers.FlashDash(d)
	endCast(d.id)
	local char = charOf(d.userId)
	local pal = palOf(d.userId)
	local from, to, dir = d.from, d.to, d.dir
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	-- the push-off: the ground cracks where the foot was, a clap of thunder
	sound(SND.Thunder, from, 1.2, 1.05)
	sound(SND.Boom, from, 0.8, 1.6)
	sound(SND.Zap, to, 0.9, 1.1)
	local g = groundAt(from)
	Fx2.cracks(Folder, g, UP, 4, pal.Bolt, 3)
	Fx2.dust(Folder, g, 5, 6)
	FX.ring(Folder, g + UP * 0.3, UP, 2, 20, pal.Bolt, 0.35)
	Fx2.shockwave(Folder, from, dir, 3, 16, pal.Bolt, 0.3)
	StormFX.thunderTrail(from, to, pal, { width = 1.3, life = 0.5, linger = 0.8, forks = 3 })
	if char then
		local clip = Poses.zanshin(0.12)
		StormFX.afterimage(char, pal.Ghost, { life = 0.5, alpha = 0.3, offset = rootOffset(char, from, dir) })
		StormFX.ghost(char, CFG.Flash.GhostTime)
		play(char, clip)
		drawFor(char, d.time + clip.sheatheAt) -- the click home lands with the cut
		task.delay(d.time + CFG.Flash.GhostTime, function()
			if char.Parent then
				StormFX.afterimage(char, pal.Ghost, { life = 0.3, alpha = 0.55 })
			end
		end)
	end
	for _, m in ipairs(d.marks or {}) do
		staticOn(m, pal, d.time + d.delay)
	end
	if isMe(d.userId) then
		driveTo(from, to, d.time, dir, { exit = 18 })
		rootUntil = os.clock() + d.time + 0.25
		busyUntil = os.clock() + d.time + 0.2
		FX.speedLines(0.35, { color = pal.BoltCore, alpha = 0.8, count = 60, inner = 0.25 })
		Fx2.envelope({ fov = 14, blur = 6, attack = 0.03, release = 0.35 })
		Fx2.shake(1.0, 0.25)
	end
end

function handlers.FlashHit(d)
	local pal = palOf(d.userId)
	local dir = typeof(d.dir) == "Vector3" and d.dir or Vector3.zAxis
	local any = false
	for _, h in ipairs(d.hits or {}) do
		if typeof(h.p) == "Vector3" then
			any = true
			local f = StormFX.folder("FlashHit", 3)
			StormFX.crossSlash(h.p, dir, pal, 11, false)
			FX.glow(f, h.p, 16, pal.Bolt, 0.3)
			FX.sparks(f, h.p, { color = pal.BoltCore, color2 = pal.Bolt, count = 40, speed = { 25, 100 }, size = 0.6 })
			FX.streaks(f, h.p, { dir = dir, spread = 25, speed = { 80, 180 }, count = 24, color = pal.BoltCore, color2 = pal.Bolt, size = 0.9 })
			FX.arcs(f, h.p, 4, { count = 5, outward = true, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.15, life = 0.14 })
			FX.ring(f, h.p, dir, 1, 20, pal.Bolt, 0.35)
			sound(SND.HitHeavy, h.p, 1, 1)
			sound(SND.Zap, h.p, 0.8, 1.3)
			Fx2.shake(1.4, 0.25, h.p)
		end
	end
	if any and isMe(d.userId) then
		FX.impact({ tint = pal.Bolt, tint2 = pal.BoltCore, lineColor = pal.BoltCore, flashAlpha = 0.3 })
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 2: six-fold. Six thunderclaps in a row; every dash leaves its own bolt (they linger, so the six cross into a
-- web) and a glowing clone of the dasher where it landed; the sixth ends in a bolt out of the sky.
local CHAIN_POSES = { Poses.Zanshin, Poses.Slash[2].keys[2].pose, Poses.Slash[1].keys[2].pose }

function handlers.ChainStart(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local pal = palOf(d.userId)
	local hrp = hrpOf(char)
	play(char, Poses.hold(Poses.Iai, d.windup + 0.1, 0.05, 0.03))
	sheatheNow(char)
	if hrp then
		sound(SND.Crackle, hrp.Position, 1, 1)
		sound(SND.Hum, hrp.Position, 0.6, 1.4)
		FX.ring(Folder, groundAt(hrp.Position) + UP * 0.25, UP, 22, 3, pal.Bolt, d.windup, { ease = "in" })
	end
	casts[d.id] = {
		crackle = StormFX.crackle(function()
			return char.Parent and Katana.mouth(char) or nil
		end, pal, d.windup + 0.05, 2, 0.025),
	}
	if isMe(d.userId) then
		rootUntil = os.clock() + d.windup + 0.2
		faceUntil, faceDirV = os.clock() + d.windup, d.dir
		busyUntil = os.clock() + d.windup + d.strikes * d.legTime + 0.5
		showTitle("Chain")
		Fx2.envelope({ fov = -4, contrast = 0.1, attack = d.windup, release = 0.1 })
	end
end

function handlers.ChainLeg(d)
	endCast(d.id)
	local char = charOf(d.userId)
	local pal = palOf(d.userId)
	local from, to, dir = d.from, d.to, d.dir
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	sound(SND.Thunder, from, 1, 0.9 + d.i * 0.08) -- six thunderclaps, each a little higher
	sound(SND.Zap, to, 0.7, 1 + d.i * 0.1)
	StormFX.thunderTrail(from, to, pal, { width = 0.9, life = 0.45, linger = 1.2, forks = 2 })
	FX.ring(Folder, groundAt(from) + UP * 0.25, UP, 2, 12, pal.Bolt, 0.3)
	if char then
		StormFX.ghost(char, CFG.Chain.GhostTime)
		play(char, Poses.hold(CHAIN_POSES[(d.i - 1) % #CHAIN_POSES + 1], d.hold + 0.15, 0.03, 0.08))
		drawFor(char, d.hold + 0.6)
		Katana.swing(char, d.time + 0.1)
		-- the clone left where this dash landed
		task.delay(d.time, function()
			if char.Parent then
				StormFX.afterimage(char, pal.Ghost, { life = 0.9, alpha = 0.35, offset = rootOffset(char, to, dir) })
			end
		end)
	end
	for _, m in ipairs(d.hits or {}) do
		local t = typeof(m) == "Instance" and m.Parent and torsoOf(m)
		if t then
			local f = StormFX.folder("ChainHit", 2)
			StormFX.crossSlash(t.Position, dir, pal, 7, true)
			FX.sparks(f, t.Position, { color = pal.BoltCore, color2 = pal.Bolt, count = 18, speed = { 20, 70 }, size = 0.5 })
			sound(SND.Hit, t.Position, 0.8, 1.4 + d.i * 0.05)
		end
	end
	if isMe(d.userId) then
		driveTo(from, to, d.time, dir, { pin = true })
		FX.speedLines(0.2, { color = pal.BoltCore, alpha = 0.7, count = 44, inner = 0.3 })
		Fx2.envelope({ fov = 8, attack = 0.02, release = 0.18 })
		Fx2.shake(0.6, 0.15)
	end
end

function handlers.ChainSlam(d)
	local pal = palOf(d.userId)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	StormFX.skyBolt(d.pos, pal, { power = 1.3, forks = 4 })
	sound(SND.Boom, d.pos, 1.3, 0.9)
	sound(SND.Thunder, d.pos, 1.3, 0.8)
	Fx2.shake(2.4, 0.5, d.pos, 220)
	if isMe(d.userId) then
		FX.impact({ tint = pal.Bolt, tint2 = pal.BoltCore, lineColor = pal.BoltCore, flashAlpha = 0.35, lineTime = 0.4 })
	elseif near(d.pos, 200) then
		FX.flash(pal.BoltCore, 0.2, 0.25)
	end
end

function handlers.ChainEnd(d)
	endCast(d.id)
	local char = charOf(d.userId)
	if char and not d.cancelled then
		local clip = Poses.zanshin(0.25)
		play(char, clip)
		drawFor(char, clip.sheatheAt)
		StormFX.afterimage(char, palOf(d.userId).Ghost, { life = 0.4, alpha = 0.45 })
	elseif char then
		Animator.stopAll(char, 0.15)
	end
	if isMe(d.userId) then
		releaseDrive(0)
		rootUntil = os.clock() + 0.2
		busyUntil = 0
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 3: focus. A deep breath that draws a vortex of wind in to the chest, then (for as long as FocusUntil lasts,
-- on every client) a golden aura, a rhythmic plume of breath vapour, static along the blade and round the feet, and
-- afterimages trailing the body whenever it runs fast.
local focusFx = {} -- [character] = { pal, aura, breathAtt, breath, nextBreath, nextArc, nextTrail, flip }

local function stopFocusFx(char)
	local fx = focusFx[char]
	focusFx[char] = nil
	if fx then
		if fx.aura then
			fx.aura:Destroy()
		end
		if fx.breathAtt then
			fx.breathAtt:Destroy()
		end
	end
end

local function startFocusFx(char)
	if focusFx[char] then
		return
	end
	local pal = palOfChar(char)
	local hrp, head = hrpOf(char), char:FindFirstChild("Head")
	local fx = { pal = pal, nextBreath = 0, nextArc = 0, nextTrail = 0 }
	if hrp then
		fx.aura = FX.aura(hrp, pal.Bolt, pal.BoltCore, 16)
	end
	if head then
		fx.breathAtt, fx.breath = StormFX.breath(head, pal)
	end
	focusFx[char] = fx
end

local function updateFocusFx(char, fx, clock, cp)
	local hrp = hrpOf(char)
	if not hrp then
		return
	end
	local close = (hrp.Position - cp).Magnitude < 170
	if clock >= fx.nextBreath then
		fx.nextBreath = clock + 1.15
		if close and fx.breath then
			fx.breath:Emit(6)
		end
	end
	if close and clock >= fx.nextArc then
		fx.nextArc = clock + 0.06
		fx.flip = not fx.flip
		local pal = fx.pal
		if fx.flip then
			local a, b = Katana.points(char)
			if a then
				FX.bolt(Folder, a, b, { color = pal.Bolt, core = pal.BoltCore, width = 0.06, segments = 5, jag = 0.22, life = 0.06 })
			end
		else
			for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
				local foot = char:FindFirstChild(n)
				if foot then
					FX.arcs(Folder, foot.Position, 0.9, { count = 1, color = pal.Bolt, width = 0.05, life = 0.06, jag = 0.4 })
				end
			end
		end
	end
	if close and clock >= fx.nextTrail then
		local v = hrp.AssemblyLinearVelocity * FLAT
		if v.Magnitude >= CFG.Focus.TrailSpeed then
			fx.nextTrail = clock + CFG.Focus.TrailEvery
			StormFX.afterimage(char, fx.pal.Ghost, { life = 0.28, alpha = 0.55 })
		end
	end
end

function handlers.FocusStart(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local pal = palOf(d.userId)
	local hrp = hrpOf(char)
	play(char, Poses.inhale(d.inhale))
	sheatheNow(char)
	if hrp then
		sound(SND.Whoosh, hrp.Position, 0.9, 0.45) -- the long breath in
		sound(SND.Hum, hrp.Position, 0.5, 0.9)
		StormFX.windIn(function()
			local t = char.Parent and char:FindFirstChild("UpperTorso")
			return t and t.Position + UP * 0.4 or nil
		end, pal, d.inhale + 0.15, 11)
		FX.streaks(Folder, hrp.Position + UP * 0.6, { inward = 10, count = 26, life = d.inhale, size = 0.5, color = pal.Mist, color2 = pal.Calm })
	end
	if isMe(d.userId) then
		rootUntil = os.clock() + d.inhale
		busyUntil = os.clock() + d.inhale
		showTitle("Focus")
		Fx2.envelope({ fov = -4, sat = -0.25, attack = d.inhale * 0.8, release = 0.25 })
	end
end

function handlers.FocusCancel(d)
	local char = charOf(d.userId)
	if char then
		Animator.stopAll(char, 0.15)
	end
	if isMe(d.userId) then
		rootUntil, busyUntil = 0, 0
	end
end

function handlers.FocusOn(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local pal = palOf(d.userId)
	local hrp = hrpOf(char)
	startFocusFx(char)
	if hrp then
		local pos = hrp.Position
		local g = groundAt(pos)
		FX.ring(Folder, g + UP * 0.3, UP, 3, 34, pal.Bolt, 0.5)
		FX.ring(Folder, pos, UP, 2, 16, pal.Calm, 0.4)
		Fx2.shockwave(Folder, pos, UP, 3, 24, pal.BoltCore, 0.4)
		FX.glow(Folder, pos, 14, pal.Bolt, 0.3)
		FX.arcs(Folder, pos, 5, { count = 6, outward = true, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.14, life = 0.16 })
		sound(SND.Thunder, pos, 0.8, 1.4)
		sound(SND.Rise, pos, 0.6, 1.3)
	end
	if isMe(d.userId) then
		Fx2.envelope({ fov = 6, tint = pal.Bolt, bright = 0.05, attack = 0.04, release = 0.5 })
		FX.flash(pal.BoltCore, 0.15, 0.25)
	end
end

function handlers.FocusOff(d)
	local char = charOf(d.userId)
	if char then
		stopFocusFx(char)
		local hrp = hrpOf(char)
		if hrp and near(hrp.Position, 160) then
			Fx2.dust(Folder, hrp.Position, 3, 4)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Skill 4: the dragon. Asleep on his feet: the head drops, calm blue and gold rings ripple out of the ground and
-- dense arcs crawl over the body and the scabbard; he wakes in a column of light, and the dash goes out inside a
-- coiling lightning dragon that roars through everything on the line, rises into the sky and fades, leaving a
-- trench of light and a lightning explosion where the dash ends.
local charges = {} -- [cast id] = { char, pal, parts, t0, time, wakeAt, woke, nextRing, nextArc, flip, mine }
local dragons = {} -- [cast id] = { d, t0, time, len, dir }

local function updateCharges(clock)
	for id, c in pairs(charges) do
		local el = clock - c.t0
		local char = c.char
		local hrp = char and char.Parent and hrpOf(char)
		if not hrp or el > c.time + 0.2 then
			charges[id] = nil
		else
			local pal = c.pal
			local pos = hrp.Position
			if clock >= c.nextRing then
				c.nextRing = clock + 0.24
				c.flip = not c.flip
				FX.ring(Folder, groundAt(pos) + UP * 0.25, UP, 3, 28, c.flip and pal.Calm or pal.Bolt, 0.6)
				if c.flip then
					FX.shell(Folder, pos, 1, 6, pal.Calm, 0.45, Enum.Material.ForceField)
				end
			end
			if clock >= c.nextArc and near(pos, 220) then
				c.nextArc = clock + 0.025
				local p = c.parts[math.random(1, #c.parts)]
				if p and p.Parent then
					FX.arcs(Folder, p.Position, 1.3 + math.random() * 1.3, { count = 1, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.08, life = 0.07, jag = 0.35 })
				end
				local m = Katana.mouth(char)
				local q = c.parts[math.random(1, #c.parts)]
				if m and q and q.Parent and math.random() < 0.4 then
					FX.bolt(Folder, m, q.Position, { color = pal.Bolt, core = pal.BoltCore, width = 0.07, jag = 0.3, life = 0.07 })
				end
			end
			if not c.woke and el >= c.wakeAt then
				c.woke = true
				-- the eyes open: a flash, a column of light, thunder
				FX.glow(Folder, pos, 30, pal.BoltCore, 0.35)
				StormFX.pillar(groundAt(pos), pal, 7, 90, 0.55)
				FX.arcs(Folder, pos, 7, { count = 7, outward = true, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.22, life = 0.16 })
				sound(SND.Thunder, pos, 1.2, 1.15)
				sound(SND.Zap, pos, 0.9, 0.8)
				if c.mine then
					FX.flash(pal.BoltCore, 0.35, 0.25)
					Fx2.shake(1.5, 0.3)
				end
			end
		end
	end
end

local function updateDragons(clock, dt)
	for id, g in pairs(dragons) do
		local e = clock - g.t0
		local speed = math.max(g.len, 10) / math.max(g.time, 0.05)
		local lead = 9
		local headS = e < g.time and (e / g.time) * g.len + lead or g.len + lead + (e - g.time) * speed
		local fade = math.clamp((e - g.time - 0.3) / 0.45, 0, 1)
		local ok, err = pcall(g.d.update, g.d, headS, dt, fade)
		if not ok then
			warn("[StormdrawClient] dragon: " .. tostring(err))
		end
		if not ok or fade >= 1 then
			g.d:destroy()
			dragons[id] = nil
		end
	end
end

function handlers.DragonCharge(d)
	local char = charOf(d.userId)
	if not char then
		return
	end
	local pal = palOf(d.userId)
	local clip = Poses.dragonCharge(d.time)
	play(char, clip)
	sheatheNow(char)
	local parts = {}
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			table.insert(parts, p)
		end
	end
	if #parts == 0 then
		table.insert(parts, hrpOf(char))
	end
	charges[d.id] = { char = char, pal = pal, parts = parts, t0 = os.clock(), time = d.time, wakeAt = clip.wakeAt, nextRing = 0, nextArc = 0,
		mine = isMe(d.userId) }
	local hrp = hrpOf(char)
	if hrp then
		sound(SND.Hum, hrp.Position, 0.9, 0.7)
		sound(SND.Rise, hrp.Position, 0.7, 0.8)
		sound(SND.Crackle, hrp.Position, 0.8, 0.9)
	end
	if isMe(d.userId) then
		rootUntil = os.clock() + d.time + 0.2
		faceUntil, faceDirV = os.clock() + d.time, d.dir
		busyUntil = os.clock() + d.time + 1.2
		showTitle("Dragon")
		letterbox(true, 0.3)
		markTarget(d.target, pal, d.time + 0.6)
		Fx2.envelope({ fov = -8, sat = -0.35, bright = -0.06, attack = 0.35, hold = math.max(d.time - 0.45, 0), release = 0.3 })
	end
end

function handlers.DragonCancel(d)
	charges[d.id] = nil
	local char = charOf(d.userId)
	if char then
		Animator.stopAll(char, 0.15)
	end
	if isMe(d.userId) then
		rootUntil, busyUntil = 0, 0
		letterbox(false, 0.3)
	end
end

function handlers.DragonDash(d)
	charges[d.id] = nil
	local char = charOf(d.userId)
	local pal = palOf(d.userId)
	local from, to, dir = d.from, d.to, d.dir
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local ok, dg = pcall(Dragon.new, Folder, pal, from, to)
	if ok and dg then
		dragons[d.id] = { d = dg, t0 = os.clock(), time = d.time, len = (to - from).Magnitude, dir = dir }
	else
		warn("[StormdrawClient] dragon: " .. tostring(dg))
	end
	sound(SND.Thunder, from, 1.4, 0.8)
	sound(SND.Boom, from, 1.1, 0.9)
	sound(SND.Zap, from, 1, 0.7)
	sound(SND.Rise, from, 0.8, 1.2)
	local g = groundAt(from)
	Fx2.cracks(Folder, g, UP, 7, pal.Bolt, 5)
	Fx2.dust(Folder, g, 8, 10)
	FX.ring(Folder, g + UP * 0.3, UP, 4, 40, pal.Bolt, 0.5)
	Fx2.shockwave(Folder, from, dir, 4, 30, pal.BoltCore, 0.4)
	task.delay(d.time, function()
		StormFX.thunderTrail(from, to, pal, { width = 2.2, life = 0.6, linger = 1.4, forks = 4 })
	end)
	if char then
		play(char, Poses.hold(Poses.Thrust, d.time + 0.25, 0.04, 0.2))
		drawFor(char, d.time + 1.2)
		Katana.swing(char, d.time + 0.2)
		task.delay(d.time, function()
			if char.Parent then
				local clip = Poses.zanshin(0.45)
				play(char, clip)
				drawFor(char, clip.sheatheAt)
			end
		end)
	end
	if isMe(d.userId) then
		driveTo(from, to, d.time, dir, { exit = 30 })
		rootUntil = os.clock() + d.time + 0.45
		letterbox(false, 0.6)
		FX.speedLines(d.time + 0.3, { color = pal.BoltCore, alpha = 0.85, count = 70, inner = 0.2 })
		Fx2.envelope({ fov = 22, blur = 4, attack = 0.06, hold = d.time, release = 0.4 })
		Fx2.shake(2.2, d.time + 0.2)
	end
end

function handlers.DragonHit(d)
	local pal = palOf(d.userId)
	local p = d.p
	if typeof(p) ~= "Vector3" then
		return
	end
	local g = dragons[d.id]
	local dir = g and g.dir or Vector3.zAxis
	local f = StormFX.folder("DragonHit", 3)
	StormFX.crossSlash(p, dir, pal, 12, false)
	FX.glow(f, p, 20, pal.Bolt, 0.3)
	FX.sparks(f, p, { color = pal.BoltCore, color2 = pal.Bolt, count = 40, speed = { 30, 110 }, size = 0.7 })
	FX.streaks(f, p, { dir = UP, spread = 20, speed = { 90, 200 }, count = 22, color = pal.BoltCore, color2 = pal.Bolt, size = 1 })
	FX.bolt(f, p, p + UP * 45 + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)), { color = pal.Bolt, core = pal.BoltCore, width = 0.5, life = 0.2, restrike = 2, jag = 0.12 })
	sound(SND.HitHeavy, p, 1.1, 0.9)
	sound(SND.Zap, p, 0.8, 0.9)
	Fx2.shake(1.6, 0.25, p)
end

function handlers.DragonBlast(d)
	local pal = palOf(d.userId)
	if typeof(d.pos) ~= "Vector3" then
		return
	end
	local pos = groundAt(d.pos)
	local r = d.radius or 20
	StormFX.skyBolt(pos, pal, { power = 2, width = 2.6, forks = 6 })
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2 + math.random()
		local at = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * r * (0.45 + math.random() * 0.4)
		task.delay(0.05 + i * 0.05, function()
			StormFX.skyBolt(groundAt(at + UP * 3), pal, { power = 0.7, forks = 1 })
		end)
	end
	local f = StormFX.folder("DragonBlast", 8)
	FX.shell(f, pos + UP * 2, 3, r * 1.1, pal.BoltCore, 0.45)
	FX.shell(f, pos + UP * 2, 4, r * 1.6, pal.Bolt, 0.7, Enum.Material.ForceField)
	FX.ring(f, pos + UP * 0.5, UP, 6, r * 4.5, pal.Bolt, 0.8)
	Fx2.shockwave(f, pos + UP, UP, 6, r * 4, pal.BoltCore, 0.6)
	Fx2.cracks(f, pos, UP, r * 0.7, pal.Bolt, 6)
	FX.rubble(f, pos, { count = 26, radius = 8, up = { 40, 90 }, out = { 20, 50 }, max = 2.4 })
	Fx2.dust(f, pos, 14, 14)
	FX.arcs(f, pos + UP * 3, r, { count = 10, outward = true, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.3, life = 0.25 })
	sound(SND.Boom, pos, 1.6, 0.75)
	sound(SND.Thunder, pos, 1.4, 0.7)
	sound(SND.HitHeavy, pos, 1, 0.6)
	Fx2.shake(4, 0.9, pos, 300)
	if isMe(d.userId) then
		FX.impact({ tint = pal.Bolt, tint2 = pal.BoltCore, lineColor = pal.BoltCore, flashAlpha = 0.5, lineTime = 0.6 })
	elseif near(pos, 220) then
		FX.flash(pal.BoltCore, 0.25, 0.3)
	end
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[StormdrawClient] " .. tostring(kind) .. ": " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- M1 input: the string is played here the moment it is pressed (the server decides what it hits). Like every M1 in
-- this place it swings at the world point under the cursor, and when a standing body is in the corridor along that
-- aim (PvPShared.Balance M1_LOCK_*, the same test the server runs) the swing turns to it and steps in.
local S = CFG.Slash
local m1 = { combo = 0, last = -1e9, lock = 0, held = false }
local m1Ray = RaycastParams.new()
m1Ray.FilterType = Enum.RaycastFilterType.Exclude
local LOCK_PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }
local HELD = { "GrabbedBy", "InDomain", "WhippedBy", "SlashedBy" }

local function standing(m)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or m:GetAttribute("Dead") == true then
		return false
	end
	for _, a in ipairs(HELD) do
		if m:GetAttribute(a) ~= nil then
			return true
		end
	end
	return m:GetAttribute("Ragdolled") ~= true and (tonumber(m:GetAttribute("DownUntil")) or 0) <= now()
end

local function m1Lock(char, hrp, aim)
	local reach, radius = tonumber(BAL.M1_LOCK_REACH) or 12, tonumber(BAL.M1_LOCK_RADIUS) or 3.5
	local a = hrp.Position
	local list = CollectionService:GetTagged(CFG.TargetTag)
	if CFG.AffectPlayers then
		for _, pl in ipairs(Players:GetPlayers()) do
			local c = pl ~= player and pl.Character
			if c and c:FindFirstChild("HumanoidRootPart") and not c:FindFirstChildOfClass("ForceField") then
				table.insert(list, c)
			end
		end
	end
	m1Ray.FilterDescendantsInstances = ignoreList()
	local best, bestAlong, bestRoot = nil, nil, nil
	for _, m in ipairs(list) do
		if m ~= char and m.Parent and standing(m) then
			local r = radius + (Players:GetPlayerFromCharacter(m) and 1 or 0)
			for _, n in ipairs(LOCK_PARTS) do
				local part = m:FindFirstChild(n)
				if part and part:IsA("BasePart") then
					local q = part.Position
					local along = (q - a):Dot(aim)
					if along >= -1 and along <= reach and (bestAlong == nil or along < bestAlong)
						and (q - (a + aim * math.clamp(along, 0, reach))).Magnitude <= r
						and not workspace:Raycast(a, q - a, m1Ray) then
						local root = m:FindFirstChild("HumanoidRootPart")
						best, bestAlong, bestRoot = m, along, root and root.Position or q
					end
				end
			end
		end
	end
	return best, bestRoot
end

local debugAim = nil -- Studio test hook only: the next swing's aim
trySlash = function(held)
	if held then
		m1.held = true
	end
	if not equipped() then
		return
	end
	local clock = os.clock()
	if clock < busyUntil or drive ~= nil then
		return
	end
	local char, hum, hrp = myChar()
	if not char or iAmStunned(char) then
		return
	end
	local focus = (tonumber(char:GetAttribute("FocusUntil")) or 0) > now()
	local sp = focus and S.FocusSpeedMul or 1
	if clock - m1.last < S.SwingInterval * sp + 0.02 or clock < m1.lock then
		return
	end
	if clock - m1.last > S.ComboResetTime then
		m1.combo = 0
	end
	m1.combo = m1.combo % S.ComboLength + 1
	m1.last = clock
	if m1.combo == S.ComboLength then
		m1.lock = clock + S.FinalCooldown * sp
	end
	local aim = debugAim or flat(cursorTarget() - hrp.Position, flat(hrp.CFrame.LookVector, -Vector3.zAxis))
	debugAim = nil
	local ok, lock, at = pcall(m1Lock, char, hrp, aim)
	if ok and lock and at then
		local off = (at - hrp.Position) * FLAT
		if off.Magnitude > 0.5 then
			aim = off.Unit
			local step = math.clamp(off.Magnitude - (tonumber(BAL.M1_LUNGE_STOP) or 3), 0, tonumber(BAL.M1_LUNGE_MAX) or 5)
			if step > 0.3 and math.abs(at.Y - hrp.Position.Y) < 3 and clock >= rootUntil then
				driveTo(hrp.Position, hrp.Position + aim * step, 0.1, aim)
			end
		end
	end
	faceUntil, faceDirV = clock + 0.3, aim
	playSlash(char, m1.combo, aim, focus)
	Request:FireServer("Slash", { aim = aim })
end

-- holding M1 keeps the string going
RunService.Heartbeat:Connect(function()
	if not m1.held then
		return
	end
	if not equipped() or not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not _G.SandboxArmed) then
		m1.held = false
	else
		trySlash()
	end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() or player:GetAttribute("KeybindCapture") then
		return
	end
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		trySlash(true)
		return
	end
	-- the press as the move's default key (HudShared.Keybinds), which is what Config.Keys holds
	local pressed = Keybinds.logical(input.KeyCode)
	for skill, key in pairs(CFG.Keys) do
		if pressed == key then
			request(skill)
		end
	end
end)

-- TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or not equipped() or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	trySlash()
end)

---------------------------------------------------------------------------------------------------
-- every frame: who carries a sword, the sword's state, Focus effects, the ultimate, my body, the bar
local function scan()
	local t = now()
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and char.Parent and hum then
			local on = pl:GetAttribute("Kit") == CFG.KitId
			local rig = Katana.get(char)
			if rig then
				-- re-built if the body it hangs on was swapped (an outfit change replaces body parts)
				local hw = rig.scabbard and rig.scabbard:FindFirstChild("ScabbardHip")
				local broken = not hw or not hw.Part0 or hw.Part0.Parent ~= char or not rig.grip.Part0 or rig.grip.Part0.Parent ~= char
				if broken or not on then
					Katana.detach(char)
					rig = nil
				end
			end
			if on and not rig and hum.Health > 0 then
				local ok, err = pcall(Katana.attach, char, palOf(pl.UserId))
				if not ok then
					warn("[StormdrawClient] katana: " .. tostring(err))
				end
				bladeOf(char)
			end
			local focusing = on and hum.Health > 0 and (tonumber(char:GetAttribute("FocusUntil")) or 0) > t
			if focusing then
				startFocusFx(char)
			elseif focusFx[char] then
				stopFocusFx(char)
			end
		end
	end
	for char in pairs(focusFx) do
		if not char.Parent then
			stopFocusFx(char)
		end
	end
end

local scanAt = 0
local function frame(dt)
	local clock = os.clock()
	if clock >= scanAt then
		scanAt = clock + 0.4
		scan()
	end
	updateBlades(clock)
	updateCharges(clock)
	updateDragons(clock, dt)
	local cp = camPos()
	for char, fx in pairs(focusFx) do
		updateFocusFx(char, fx, clock, cp)
	end
	updateBody(clock)
	updateHud(clock)
end

RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(frame, dt)
	if not ok then
		warn("[StormdrawClient] frame: " .. tostring(err))
	end
end)

player.CharacterAdded:Connect(function()
	rootUntil, faceUntil, busyUntil = 0, 0, 0
	drive, faceDirV = nil, nil
	turnedOff = false
	applied, lastWalk, lastJump = false, nil, nil
	m1.combo, m1.last, m1.lock, m1.held = 0, -1e9, 0, false
	letterbox(false, 0.1)
end)
player:GetAttributeChangedSignal("Kit"):Connect(function()
	if not equipped() then
		drive = nil
		rootUntil, faceUntil, busyUntil = 0, 0, 0
		letterbox(false, 0.1)
	end
end)

-- Studio test hook (harness scripts drive the kit through this; never present in a live server)
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "StormDebug"
	dbg.OnInvoke = function(cmd, a)
		if cmd == "req" then
			request(a)
			return true
		elseif cmd == "slash" then
			debugAim = typeof(a) == "Vector3" and flat(a, nil) or nil
			trySlash()
			return true
		elseif cmd == "state" then
			local char, hum, hrp = myChar()
			local rig = char and Katana.get(char)
			return HttpService:JSONEncode({
				equipped = equipped(), walk = hum and hum.WalkSpeed, jumpPower = hum and hum.JumpPower, drive = drive ~= nil,
				katana = rig ~= nil, drawn = rig and rig.drawn or false, combo = m1.combo, focusFx = char and focusFx[char] ~= nil or false,
				dragons = (function() local n = 0 for _ in pairs(dragons) do n += 1 end return n end)(),
				pos = hrp and { hrp.Position.X, hrp.Position.Y, hrp.Position.Z } or nil,
				cd = cooldownEnd, fx = #Folder:GetChildren(),
			})
		end
		return nil
	end
	dbg.Parent = script
end

print(string.format("[StormdrawClient] ready - Q %s | E %s | R %s | G %s", CFG.Labels.Flash, CFG.Labels.Chain, CFG.Labels.Focus, CFG.Labels.Dragon))
