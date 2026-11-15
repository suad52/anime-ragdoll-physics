--!nocheck
-- GodspeedClient: input, ability bar, local movement and playback of every Godspeed cast in the server - the
-- lightning-assassin kit: Lightning Palm (Q), Thunderbolt (E), Rhythm Echo (R) and the Godspeed ultimate (G).
-- The server (ServerScriptService.GodspeedServer) is authoritative: this script sends intents, moves its own
-- character along the timeline the server broadcasts, and draws everything (lightning from GojoShared's GojoFX).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("GodspeedKit")
local CFG = require(Kit:WaitForChild("Config"))
local Clips = require(Kit:WaitForChild("Clips"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local GojoClientFolder = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local Animator = require(GojoClientFolder:WaitForChild("ProceduralAnimator"))
local FX = require(GojoClientFolder:WaitForChild("GojoFX"))
-- (2026-11-11 keybinds) owner: "have the option to have keybinds". The CFG.Keys presses below are read through
-- HudShared.Keybinds - logical() turns the physical key into the DEFAULT key whose action the player bound to it - and
-- the key chips draw Keybinds.label() (redrawn on Keybinds.Changed). With no rebinds both return the key itself, so
-- default play is unchanged. Config.Keys stays the defaults.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))
local keyChips = {} -- [TextLabel] = the default KeyCode whose binding it shows
local function keyChip(lbl, default)
	keyChips[lbl] = default
	return lbl
end
Keybinds.Changed:Connect(function()
	for lbl, d in pairs(keyChips) do
		lbl.Text = Keybinds.label(d)
	end
end)

local PAL = CFG.Palette
local SND = CFG.Sounds
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2
local BOLT_COLORS = { PAL.Bolt, PAL.Core, PAL.Violet }

-- (2026-11-07 perks) VIOLET STORM, the alt skin: Config.AltPalette laid over Config.Palette. A cast is drawn in it when
-- its CASTER's player has Skin == "Alt" (read at cast time, on every client). palOf(userId | Player | character)
-- returns the palette and its bolt colour list; each handler shadows PAL / BOLT_COLORS with them
local ALTPAL = table.clone(PAL)
for k, v in pairs(type(CFG.AltPalette) == "table" and CFG.AltPalette or {}) do
	ALTPAL[k] = v
end
local ALT_BOLTS = { ALTPAL.Bolt, ALTPAL.Core, ALTPAL.Violet }
local function palOf(who)
	local p = who
	if type(who) == "number" then
		local ok, res = pcall(Players.GetPlayerByUserId, Players, who)
		p = ok and res or nil
	elseif typeof(who) == "Instance" and who:IsA("Model") then
		p = Players:GetPlayerFromCharacter(who)
	end
	if typeof(p) == "Instance" and p:IsA("Player") and p:GetAttribute("Skin") == "Alt" and p:GetAttribute("Kit") == CFG.KitId then
		return ALTPAL, ALT_BOLTS
	end
	return PAL, BOLT_COLORS
end

-- everything this kit draws lives under the shared LocalFX folder, which every kit's raycasts already ignore
local Folder = Instance.new("Folder")
Folder.Name = "Godspeed"
Folder.Parent = workspace:WaitForChild("LocalFX", 10) or workspace -- GojoClient makes LocalFX as it starts

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
	return p and p.Character, p
end

local function equipped()
	return player:GetAttribute("Kit") == CFG.KitId
end

local function flat(v, fallback)
	local f = v * FLAT
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end

local function camFacing(p)
	local d = workspace.CurrentCamera.CFrame.Position - p
	return d.Magnitude > 1e-3 and d.Unit or UP
end

local function camDist(p)
	return (workspace.CurrentCamera.CFrame.Position - p).Magnitude
end

local function sound(id, parent, vol, speed)
	if not parent or not parent.Parent then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	s.Parent = parent
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 10)
end

local function soundAt(id, pos, vol, speed)
	sound(id, FX.anchor(Folder, pos, 8), vol, speed)
end

local function castFolder(name)
	local f = Instance.new("Folder")
	f.Name = name or "Cast"
	f.Parent = Folder
	Debris:AddItem(f, 8)
	return f
end

local function playClip(char, clip, startAt)
	if char and clip and (startAt or 0) < clip.length then
		return Animator.play(char, clip, { startAt = math.max(startAt or 0, 0) })
	end
end

---------------------------------------------------------------------------------------------------
-- lightning helpers

-- a bolt from far up in the sky down onto `p`
local function skyBolt(f, p, width, restrike, pal)
	local PAL = pal or PAL
	local top = p + Vector3.new(math.random(-9, 9), 150, math.random(-9, 9))
	FX.bolt(f, top, p, { color = PAL.Bolt, core = PAL.Core, width = width, segments = 14, jag = 0.09, life = 0.32, restrike = restrike or 3, light = true })
end

local LIMBS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
-- a short arc jumping between two random parts of a body
local function bodyArc(f, model, color, width)
	local a = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	local b = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	if a and b and a ~= b and a:IsA("BasePart") and b:IsA("BasePart") then
		FX.bolt(f, a.Position + FX.randUnit() * 0.5, b.Position + FX.randUnit() * 0.5, {
			color = color or PAL.Bolt, width = width or 0.06, jag = 0.35, segments = 4, life = 0.09, restrike = 1,
		})
	end
end

-- an afterimage: a ghostly copy of a character's body where it stands, fading away
local function ghost(char, color, alpha, life, offset)
	if not char or not char.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Afterimage"
	local parts = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Archivable then
			local ok, c = pcall(function()
				return d:Clone()
			end)
			if ok and c then
				for _, ch in ipairs(c:GetChildren()) do
					if not ch:IsA("DataModelMesh") then
						ch:Destroy()
					end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Massless = true
				c.Material = Enum.Material.ForceField
				c.Color = color
				c.Transparency = alpha
				c.CFrame = (offset and (CFrame.new(offset) * d.CFrame)) or d.CFrame
				c.Parent = f
				table.insert(parts, c)
			end
		end
	end
	f.Parent = Folder
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, c in ipairs(parts) do
		TweenService:Create(c, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(f, life + 0.1)
	return f
end

-- a crescent claw slash in front of `pos`, swept from his right to his left, then gone
local function slashArc(f, pos, face, radius, tilt, pal)
	local PAL = pal or PAL
	local frame = CFrame.lookAt(pos, pos + face) * CFrame.Angles(0, 0, tilt or math.rad(-26))
	local n = 14
	for layer = 1, 2 do
		local r = radius * (layer == 1 and 1 or 0.82)
		local pts = {}
		for i = 0, n do
			local a = math.rad(-82 + 164 * i / n)
			pts[i] = (frame * CFrame.new(math.sin(a) * r, (layer - 1) * 0.35, -math.cos(a) * r * 0.85)).Position
		end
		for i = 1, n do
			local mid = 1 - math.abs(((i - 0.5) / n) * 2 - 1) -- 0 at the tips, 1 in the middle
			local p0, p1 = pts[i - 1], pts[i]
			local w = (layer == 1 and 0.1 or 0.06) + (layer == 1 and 0.42 or 0.2) * mid
			local seg = FX.part("Slash", Enum.PartType.Block, Enum.Material.Neon, (layer == 1 and PAL.Core or PAL.Violet):Lerp(PAL.Bolt, 1 - mid), nil)
			seg.Size = Vector3.new(w, w * 0.35, (p1 - p0).Magnitude + w)
			seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
			seg.Transparency = 1
			seg.Parent = f
			task.delay(0.085 * (n - i) / n, function()
				if seg.Parent then
					seg.Transparency = 0.02
					TweenService:Create(seg, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = seg.Size * Vector3.new(0.3, 0.3, 1) }):Play()
				end
			end)
			Debris:AddItem(seg, 0.5)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- camera: shakes and FOV kicks as short timed envelopes (cleared back to the player's own FOV when the last ends)
local shakes = {}
local baseFOV, lastFOV -- the FOV underneath our kick, and the value we wrote last frame
local lastShake = nil -- the shake offset applied last frame (undone before the camera module reads the camera)
local function shake(amp, dur, freq, fov)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	if not equipped() then
		fov = 0 -- FOV kicks only for this kit's own player; anyone else just feels the shake
	end
	table.insert(shakes, { t0 = os.clock(), amp = amp, dur = dur, freq = freq or 22, fov = fov or 0 })
end
-- undo last frame's shake before the camera module runs: it builds each frame from the camera's current look
-- direction, so a rotation left in place would add up into a permanent drift of the player's aim
RunService:BindToRenderStep("GodspeedCameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = workspace.CurrentCamera
	if lastShake and cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = cam.CFrame * lastShake:Inverse()
	end
	lastShake = nil
end)
RunService:BindToRenderStep("GodspeedCamera", Enum.RenderPriority.Camera.Value + 2, function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local t = os.clock()
	local amp, fov, freq, anyFov = 0, 0, 22, false
	local i = 1
	while i <= #shakes do
		local e = shakes[i]
		local x = (t - e.t0) / e.dur
		if x >= 1 then
			table.remove(shakes, i)
		else
			local w = (1 - x) ^ 2
			amp += e.amp * w
			fov += e.fov * w
			freq = e.freq
			anyFov = anyFov or e.fov ~= 0
			i += 1
		end
	end
	-- the kick rides on whatever FOV the camera has (another kit may be animating it), and is only taken back off if
	-- nobody else has written the FOV since
	if anyFov then
		local cur = cam.FieldOfView
		if not baseFOV or not lastFOV or math.abs(cur - lastFOV) > 1e-3 then
			baseFOV = cur
		end
		cam.FieldOfView = math.clamp(baseFOV + fov, 20, 110)
		lastFOV = cam.FieldOfView
	elseif baseFOV then
		if lastFOV and math.abs(cam.FieldOfView - lastFOV) < 1e-3 then
			cam.FieldOfView = baseFOV
		end
		baseFOV, lastFOV = nil, nil
	end
	if amp > 0.002 and cam.CameraType ~= Enum.CameraType.Scriptable then
		local a, b, c = math.noise(t * freq, 0.3, 1.7), math.noise(1.9, t * freq, 4.1), math.noise(7.3, 2.2, t * freq)
		local off = CFrame.new(a * amp, b * amp, 0) * CFrame.Angles(b * amp * 0.03, a * amp * 0.03, c * amp * 0.04)
		cam.CFrame = cam.CFrame * off
		lastShake = off
	end
end)

---------------------------------------------------------------------------------------------------
-- HUD: the move-name callout and the ability bar (same layout as the other kits' bars)
local gui = Instance.new("ScreenGui")
gui.Name = "GodspeedHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function uiCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 14)
	c.Parent = p
	return c
end
local function uiStroke(p, color, th, tr)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = th
	st.Transparency = tr or 0
	st.Parent = p
	return st
end
local function uiText(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

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
local titleStroke = uiStroke(title, Color3.new(0, 0, 0), 3, 1)
local titleGrad = Instance.new("UIGradient")
titleGrad.Rotation = 90
titleGrad.Parent = title
local kanji = uiText(titleHolder, { Size = UDim2.fromScale(1, 0.32), Text = "", TextTransparency = 1, ZIndex = 41 })
local kanjiStroke = uiStroke(kanji, Color3.new(0, 0, 0), 2, 1)
local titleToken
local function showTitle(text, kanjiText, c0, c1)
	local token = {}
	titleToken = token
	title.Text = text
	kanji.Text = kanjiText or ""
	kanji.TextColor3 = c0:Lerp(c1, 0.45)
	titleGrad.Color = ColorSequence.new(c0, c1)
	local dark = c1:Lerp(Color3.new(0, 0, 0), 0.82)
	titleStroke.Color, kanjiStroke.Color = dark, dark
	title.TextTransparency, kanji.TextTransparency = 0, 0
	titleStroke.Transparency, kanjiStroke.Transparency = 0, 0
	titleScale.Scale = 1.7
	titleHolder.Rotation = -5
	TweenService:Create(titleScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(titleHolder, TweenInfo.new(0.16), { Rotation = 0 }):Play()
	task.delay(1.5, function()
		if titleToken ~= token then
			return
		end
		local info = TweenInfo.new(0.45)
		for _, o in ipairs({ title, kanji }) do
			TweenService:Create(o, info, { TextTransparency = 1 }):Play()
		end
		for _, o in ipairs({ titleStroke, kanjiStroke }) do
			TweenService:Create(o, info, { Transparency = 1 }):Play()
		end
	end)
end
local function callout(skill, sub)
	local co = CFG.Callouts[skill]
	showTitle(sub or CFG.Labels[skill], co.kanji, co.c0, co.c1)
end
-- the ultimate's titles in the caster's colourway (the alt skin swaps the gradient)
local function godTitle(pal, text, kanjiText)
	local co = CFG.Callouts.Godspeed
	local alt = pal ~= PAL and CFG.AltCallout or nil
	showTitle(text, kanjiText, alt and alt.c0 or co.c0, alt and alt.c1 or co.c1)
end

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
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -172), Size = UDim2.new(0, 186, 0, 18),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack, TextColor3 = PAL.Spark,
})
uiStroke(status, Color3.fromRGB(10, 30, 70), 1.5, 0.2)

local cooldownEnd = { Palm = 0, Thunder = 0, Echo = 0, Godspeed = 0 }
local cooldownLen = { Palm = CFG.Palm.Cooldown, Thunder = CFG.Thunder.Cooldown, Echo = CFG.Echo.Cooldown, Godspeed = CFG.Godspeed.Cooldown }
local buttons = {}

-- the world point under the cursor (the screen centre on touch-only devices)
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local debugAim, debugTarget
local function cursorTarget(fromButton)
	if debugTarget then
		return debugTarget
	end
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if fromButton or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local ignore = {}
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
	table.insert(ignore, Folder)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	cursorParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, cursorParams)
	return hit and hit.Position or ray.Origin + ray.Direction * 200
end

local function request(skill, fromButton)
	if not equipped() or not myChar() then
		return
	end
	local aim = debugAim or workspace.CurrentCamera.CFrame.LookVector
	Request:FireServer(skill, { aim = aim, target = cursorTarget(fromButton) })
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
	b.BackgroundColor3 = co.c1:Lerp(Color3.fromRGB(6, 8, 16), 0.76)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(140, 140, 155))
	shade.Rotation = 90
	shade.Parent = b
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.4), 2, 0.1)
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
	uiStroke(glyph, co.c1:Lerp(Color3.new(0, 0, 0), 0.7), 1.5, 0)
	uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 11), Position = UDim2.new(0, 4, 1, big and -21 or -17), Text = CFG.Labels[id], ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.86)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyChip(uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys[id]), Font = Enum.Font.GothamBold, ZIndex = 2 }), CFG.Keys[id])
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
	buttons[id] = { cd = cd, cdText = cdText, scale = scale, ready = true }
	b.Activated:Connect(function()
		request(id, true)
	end)
end
-- the same slots as the other kits: R in the left slot, Q next to it, the shared punch, E on the big button
skillButton("Echo", 72, -280)
skillButton("Palm", 72, -198)
skillButton("Thunder", 104, 0)

-- the shared M1 punch (thrown by GojoClient's combo)
do
	local b = Instance.new("TextButton")
	b.Name = "Punch"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(72, 72)
	b.Position = UDim2.new(1, -116, 1, -16)
	b.BackgroundColor3 = Color3.fromRGB(26, 32, 46)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	uiStroke(b, Color3.fromRGB(190, 220, 255), 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = WHITE
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255), Color3.fromRGB(150, 200, 255))
	g.Rotation = 45
	g.Parent = orb
	uiText(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = "PUNCH", ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
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

-- the Godspeed ultimate on its own wide button above the row
do
	local co = CFG.Callouts.Godspeed
	local b = Instance.new("TextButton")
	b.Name = "Godspeed"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, 0, 1, -132)
	b.Size = UDim2.fromOffset(186, 36)
	b.BackgroundColor3 = WHITE
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	uiStroke(b, co.c1:Lerp(WHITE, 0.4), 2, 0.1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(co.c1:Lerp(Color3.new(0, 0, 0), 0.84), co.c1:Lerp(Color3.new(0, 0, 0), 0.5))
	g.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c1:Lerp(Color3.new(0, 0, 0), 0.9)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	keyChip(uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys.Godspeed), Font = Enum.Font.GothamBold, ZIndex = 2 }), CFG.Keys.Godspeed)
	uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Godspeed, ZIndex = 2 })
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
	buttons.Godspeed = { cd = cd, cdText = cdText, scale = scale, ready = true, horizontal = true }
	b.Activated:Connect(function()
		request("Godspeed", true)
	end)
end

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
end)

---------------------------------------------------------------------------------------------------
-- the local body: rooting during moves, the Godspeed speed boost, scripted dashes and blinks
local rootUntil = 0 -- os.clock() until which the local character can't walk or jump
local faceDir = nil -- the flat direction it is held facing while rooted
local mover = nil -- { char, t0 (server time), dur, from, to, face, vel }
local wroteMovement = false
local baseMove = nil -- { ws, jp, jh } captured when the character spawns

local function root(secs, face)
	rootUntil = math.max(rootUntil, os.clock() + secs)
	if face then
		faceDir = face
	end
end

local function inMode(char)
	return char ~= nil and (char:GetAttribute("Godspeed") or 0) > now()
end

local function blinkTo(cf)
	local char, _, hrp = myChar()
	if not char then
		return
	end
	char:PivotTo(cf)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- WalkSpeed / jump / AutoRotate are derived from the kit's state every frame (never saved and restored), so a
-- Godspeed mode that starts while rooted can't be lost to a restore
local function updateMovement(dt)
	local char, hum, hrp = myChar()
	if not char or not baseMove then
		return
	end
	if not equipped() then
		if wroteMovement then
			wroteMovement = false
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = baseMove.ws, baseMove.jp, baseMove.jh, true
		end
		return
	end
	wroteMovement = true
	local rooted = os.clock() < rootUntil
	local mode = inMode(char)
	local ws = rooted and 0 or baseMove.ws * (mode and CFG.Godspeed.WalkSpeedMul or 1)
	local jk = rooted and 0 or (mode and CFG.Godspeed.JumpMul or 1)
	if hum.WalkSpeed ~= ws then
		hum.WalkSpeed = ws
	end
	if hum.JumpPower ~= baseMove.jp * jk then
		hum.JumpPower = baseMove.jp * jk
	end
	if hum.JumpHeight ~= baseMove.jh * jk * jk then
		hum.JumpHeight = baseMove.jh * jk * jk
	end
	if hum.AutoRotate == rooted then
		hum.AutoRotate = not rooted
	end
	if rooted and faceDir and not mover then
		local want = CFrame.lookAt(Vector3.zero, faceDir)
		local cur = hrp.CFrame - hrp.Position
		hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-18 * dt))
	end
end

-- the scripted dash: written before physics every step, so the character's own simulation carries it along
RunService.Stepped:Connect(function()
	if not mover then
		return
	end
	local char, _, hrp = myChar()
	if not char or char ~= mover.char then
		mover = nil
		return
	end
	local e = now() - mover.t0
	if e < 0 then
		return
	end
	local k = math.clamp(e / mover.dur, 0, 1)
	local pos = mover.from:Lerp(mover.to, k)
	hrp.CFrame = CFrame.lookAt(pos, pos + mover.face)
	hrp.AssemblyLinearVelocity = mover.vel
	if k >= 1 then
		hrp.AssemblyLinearVelocity = mover.face * 16
		mover = nil
	end
end)

local function groundY(pos, ignoreChar)
	local hit = FX.groundHit(pos, 30)
	return hit and hit.Position.Y or nil
end

---------------------------------------------------------------------------------------------------
-- cinematic camera for the local caster's Godspeed charge: low and close in front of him, pushing in
local cine = nil
local function stopCinematic()
	if cine then
		if cine.conn then
			cine.conn:Disconnect()
		end
		local saved = cine.saved
		cine = nil
		local cam = workspace.CurrentCamera
		if saved then
			cam.CFrame = saved -- the camera module takes its look direction from here
		end
		cam.CameraType = Enum.CameraType.Custom
	end
end
local function startCinematic(char, d)
	stopCinematic()
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp or not head then
		return
	end
	local cam = workspace.CurrentCamera
	local saved = cam.CFrame -- handed back when the shot ends, so play resumes from the player's own view
	cam.CameraType = Enum.CameraType.Scriptable
	local look = flat(hrp.CFrame.LookVector)
	local base = CFrame.lookAt(hrp.Position, hrp.Position + look)
	-- the shot never goes through a wall (Scriptable switches off the camera module's own occlusion)
	local camParams = RaycastParams.new()
	camParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { Folder }
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris", "NPCs" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	camParams.FilterDescendantsInstances = ignore
	cine = { saved = saved }
	cine.conn = RunService.RenderStepped:Connect(function()
		local e = now() - d.t0
		if e >= d.charge or not head.Parent then
			stopCinematic()
			return
		end
		for _, p in ipairs(char:GetDescendants()) do
			if (p:IsA("BasePart") and p.Name ~= "HumanoidRootPart") or p:IsA("Decal") then
				p.LocalTransparencyModifier = 0
			end
		end
		local a = TweenService:GetValue(math.clamp(e / d.charge, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local pos = (base * CFrame.Angles(0, math.rad(-34 + 44 * a), 0) * CFrame.new(0, -0.4 + 1.1 * a, -(9.5 - 3.8 * a))).Position
		local off = pos - head.Position
		local hit = workspace:Raycast(head.Position, off, camParams)
		if hit then
			pos = head.Position + off.Unit * math.max((hit.Position - head.Position).Magnitude - 0.6, 1)
		end
		local jitter = (1 - a) * 0.05
		cam.CFrame = CFrame.lookAt(pos, head.Position - UP * 0.3) * CFrame.new(math.noise(e * 30, 1.3) * jitter, math.noise(2.1, e * 30) * jitter, 0)
	end)
end

---------------------------------------------------------------------------------------------------
-- playback of every cast in the server
local handlers = {}
local gods = {} -- [userId] = the running Godspeed cast

handlers.Cooldown = function(d)
	local skill = d.skill
	if skill and cooldownEnd[skill] then
		local ends = tonumber(d.ends) or 0
		if math.abs(ends - cooldownEnd[skill]) > 0.05 then -- a new cast; a refused one resends the same end time
			local len = ends - now()
			if len > 0.2 then
				cooldownLen[skill] = math.max(len, 0.5)
			end
		end
		cooldownEnd[skill] = ends
	end
end

-- Q -----------------------------------------------------------------------------------------------
handlers.PalmCast = function(d)
	local PAL, BOLT_COLORS = palOf(d.userId)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local e = now() - d.t0
	playClip(char, Clips.Palm, e)
	local f = castFolder("Palm")
	local stopPt = d.origin + d.dir * d.stop
	if isLocal then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		root(d.windup + d.dashTime + 0.2 - math.max(e, 0), d.dir)
		local _, _, hrp = myChar()
		if hrp and char == player.Character then
			local g0 = groundY(hrp.Position)
			local hip = g0 and (hrp.Position.Y - g0) or 3
			local g1 = groundY(Vector3.new(stopPt.X, hrp.Position.Y + 4, stopPt.Z))
			local to = Vector3.new(stopPt.X, g1 and (g1 + hip) or hrp.Position.Y, stopPt.Z)
			mover = {
				char = char, t0 = d.t0 + d.windup, dur = d.dashTime, from = hrp.Position, to = to, face = d.dir,
				vel = d.dir * (d.stop / math.max(d.dashTime, 0.05)),
			}
		end
	end
	-- the windup: current gathers in the striking palm
	local hand = char and char:FindFirstChild("RightHand")
	if hand and e < d.windup then
		FX.glow(f, hand.Position, 4.5, PAL.Bolt, 0.25)
		sound(SND.Crackle, hand, 0.55, 1.5)
		for i = 0, 2 do
			task.delay(i * 0.045, function()
				if hand.Parent then
					FX.arcs(f, hand.Position, 1.2, { count = 2, colors = BOLT_COLORS, width = 0.05 })
				end
			end)
		end
	end
	-- the dash: a streak of lightning down the line, afterimages left along it
	task.delay(math.max(d.windup - e, 0), function()
		local from = d.origin
		soundAt(SND.Whoosh, from, 0.8, 1.6)
		soundAt(SND.Zap, from, 0.5, 1.4)
		FX.bolt(f, from - UP * 1.2, stopPt - UP * 1.2, { color = PAL.Bolt, core = PAL.Core, width = 0.2, jag = 0.07, segments = 9, life = 0.28, restrike = 2, light = true })
		FX.bolt(f, from + UP * 0.6, stopPt + UP * 0.6, { color = PAL.Violet, width = 0.08, jag = 0.14, segments = 7, life = 0.2 })
		FX.streaks(f, from, { dir = d.dir, spread = 7, color = WHITE, color2 = PAL.Bolt, count = 22, speed = { 110, 180 }, size = 0.35, life = 0.25 })
		FX.sparks(f, from - UP * 2.4, { dir = -d.dir + UP * 0.6, spread = 40, color = PAL.Spark, color2 = PAL.Bolt, count = 14, speed = { 15, 35 }, size = 0.45 })
		local g = FX.groundHit(from, 8)
		if g then
			FX.ring(f, g.Position + UP * 0.2, UP, 1, 10, PAL.Bolt, 0.3, { alpha = 0.2 })
		end
		for i = 1, 3 do
			task.delay(d.dashTime * (i - 0.5) / 3, function()
				-- other clients show the body late (replication), so lay those copies along the planned line instead
				local h = char and char:FindFirstChild("HumanoidRootPart")
				local off = nil
				if not isLocal and h then
					off = (d.origin + d.dir * (d.stop * (i - 0.5) / 3) - h.Position) * FLAT
				end
				ghost(char, PAL.Bolt, 0.45, 0.45, off)
			end)
		end
		if isLocal then
			FX.speedLines(d.dashTime + 0.18, { color = PAL.Spark, alpha = 0.55, inner = 0.45 })
			shake(0.25, 0.25, 24, 6)
		end
	end)
end

handlers.PalmHit = function(d)
	local PAL, BOLT_COLORS = palOf(d.userId)
	local f = castFolder("PalmHit")
	local pos = d.pos
	FX.glow(f, pos, 10, PAL.Core, 0.22, { brightness = 4 })
	FX.glow(f, pos, 18, PAL.Bolt, 0.45)
	FX.ring(f, pos, d.dir, 1, 13, PAL.Bolt, 0.32)
	FX.ring(f, pos, camFacing(pos), 1, 8, WHITE, 0.22)
	FX.streaks(f, pos, { dir = d.dir, spread = 30, color = WHITE, color2 = PAL.Bolt, count = 32, speed = { 60, 150 }, size = 0.5, life = 0.32 })
	FX.arcs(f, pos, 4.5, { outward = true, count = 5, colors = BOLT_COLORS, width = 0.12, life = 0.16 })
	FX.sparks(f, pos, { color = PAL.Spark, color2 = PAL.Bolt, count = 26, speed = { 25, 60 } })
	FX.light(f, pos, PAL.Bolt, 10, 30, 0.3)
	soundAt(SND.HitHeavy, pos, 0.9, 1.1)
	soundAt(SND.Zap, pos, 0.8, 1.2)
	if d.userId == player.UserId then
		FX.impact({ tint = PAL.Spark, lineColor = PAL.Spark, lineTime = 0.3 })
		shake(0.65, 0.35, 26, -4)
	elseif camDist(pos) < 80 then
		shake(0.25, 0.25, 26)
	end
end

-- E -----------------------------------------------------------------------------------------------
local function thunderStrike(f, P, R, isLocal, pal)
	local PAL = pal or PAL
	skyBolt(f, P, 1.5, 4, PAL)
	for _ = 1, 3 do
		local a = math.random() * TAU
		local side = P + Vector3.new(math.cos(a), 0, math.sin(a)) * R * (0.5 + math.random() * 0.5)
		FX.bolt(f, P + UP * (25 + math.random() * 30), side, { color = PAL.Violet, width = 0.35, jag = 0.2, life = 0.26, restrike = 1 })
	end
	FX.glow(f, P + UP * 1.5, R * 0.9, PAL.Core, 0.22, { brightness = 3 })
	FX.glow(f, P + UP * 2, R * 1.9, PAL.Bolt, 0.55, { brightness = 1.6, alpha = 0.25 })
	FX.ring(f, P + UP * 0.3, UP, 2, R * 3, PAL.Bolt, 0.6)
	FX.ring(f, P + UP * 0.3, UP, 1, R * 2, WHITE, 0.4)
	FX.ring(f, P + UP * 2, camFacing(P), 2, R * 2.2, PAL.Violet, 0.5)
	FX.streaks(f, P + UP, { color = WHITE, color2 = PAL.Bolt, count = 60, speed = { 80, 180 }, size = 0.8, life = 0.4, stretch = 3 })
	FX.sparks(f, P + UP, { color = PAL.Spark, color2 = PAL.Bolt, count = 40, speed = { 30, 80 }, size = 0.8, life = 1 })
	FX.rubble(f, P, { count = 16, radius = R * 0.3, up = { 35, 65 }, out = { 20, 45 } })
	FX.light(f, P + UP * 6, PAL.Bolt, 14, 60, 0.7)
	for i = 1, 8 do
		task.delay(i * 0.09, function()
			FX.arcs(f, P + UP * 0.6, R * 0.7, { count = 2, colors = { PAL.Bolt, PAL.Violet }, width = 0.08 })
		end)
	end
	soundAt(SND.Thunder, P, 1, 0.9)
	soundAt(SND.Boom, P, 0.9, 1)
	soundAt(SND.Zap, P, 1, 0.8)
	local k = math.clamp(1 - camDist(P) / 220, 0, 1)
	if k > 0 then
		shake(1.4 * k, 0.6, 22, 8 * k)
	end
	if isLocal then
		FX.impact({ tint = PAL.Spark, lineColor = PAL.Spark, lineTime = 0.35, flashAlpha = 0.22, flashLife = 0.2 })
	elseif k > 0 then
		FX.flash(PAL.Flash or Color3.fromRGB(220, 235, 255), 0.25 * k, 0.25)
	end
end

handlers.ThunderCast = function(d)
	local PAL = palOf(d.userId)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local e = now() - d.t0
	playClip(char, Clips.Thunder, e)
	local f = castFolder("Thunder")
	local P = d.point
	if isLocal then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		root(CFG.Thunder.Lock - math.max(e, 0), d.dir)
	end
	-- takeoff
	task.delay(math.max(0.12 - e, 0), function()
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		if isLocal and char == player.Character then
			hrp.AssemblyLinearVelocity = UP * CFG.Thunder.LeapSpeed + d.dir * 4
		end
		local g = FX.groundHit(hrp.Position, 8)
		local gp = g and g.Position or (hrp.Position - UP * 3)
		FX.ring(f, gp + UP * 0.2, UP, 2, 16, PAL.Bolt, 0.4, { alpha = 0.1 })
		FX.streaks(f, gp, { dir = UP, spread = 25, color = WHITE, color2 = PAL.Bolt, count = 14, speed = { 40, 80 }, size = 0.4, life = 0.3 })
		soundAt(SND.Whoosh, gp, 0.7, 1.2)
	end)
	-- the strike point charges up while he is in the air
	for i = 0, 3 do
		local tt = i * 0.13
		if tt >= e - 0.05 and tt < d.strike then
			task.delay(math.max(tt - e, 0), function()
				FX.ring(f, P + UP * 0.25, UP, d.radius * 2.3, 2, PAL.Bolt, 0.32, { ease = "in", alpha = 0.2 })
				FX.arcs(f, P + UP * 1.5, d.radius * 0.6, { count = 1, color = PAL.Bolt, width = 0.06 })
			end)
		end
	end
	if e < d.strike + 0.1 then
		task.delay(math.max(d.strike - e, 0), function()
			thunderStrike(f, P, d.radius, isLocal, PAL)
		end)
	end
end

-- R -----------------------------------------------------------------------------------------------
handlers.EchoCast = function(d)
	local PAL = palOf(d.userId)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local e = now() - d.t0
	playClip(char, Clips.Echo, e)
	local f = castFolder("Echo")
	local side = d.aim:Cross(UP)
	side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
	if isLocal then
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
		root(d.slash + 0.32 - math.max(e, 0), d.aim)
	end
	-- the weave: afterimages peeled off to either side
	for i, off in ipairs({ -1.7, 1.9, -3.3, 3.5 }) do
		local tt = 0.05 + (i - 1) * 0.075
		if tt >= e then
			task.delay(tt - math.max(e, 0), function()
				ghost(char, PAL.Violet, 0.5, 0.6, side * off)
				if i % 2 == 1 then
					soundAt(SND.Whoosh, d.origin, 0.35, 2)
				end
			end)
		end
	end
	-- the blink: gone in a flash, a thread of lightning to where he lands behind the target
	task.delay(math.max(d.sway - e, 0), function()
		ghost(char, PAL.Violet, 0.35, 0.7)
		if isLocal and char == player.Character then
			blinkTo(CFrame.lookAt(d.dest, d.dest + d.face))
			faceDir = d.face
		end
		FX.glow(f, d.origin, 6, PAL.Violet, 0.25)
		FX.bolt(f, d.origin, d.dest, { color = PAL.Violet, core = PAL.Core, width = 0.12, jag = 0.12, life = 0.18 })
		FX.glow(f, d.dest, 5, PAL.Bolt, 0.25)
		FX.streaks(f, d.dest, { inward = 5, color = WHITE, color2 = PAL.Violet, count = 14, life = 0.18, size = 0.3 })
		soundAt(SND.Whoosh, d.dest, 0.8, 1.7)
		if isLocal then
			FX.speedLines(0.22, { color = PAL.EchoTint or Color3.fromRGB(220, 210, 255), alpha = 0.5, inner = 0.5 })
			shake(0.2, 0.2, 26, 4)
		end
	end)
	-- the slash (drawn on the timeline, so it shows even when it cuts only air)
	task.delay(math.max(d.slash - e, 0), function()
		slashArc(f, d.dest + UP * 0.5 + d.face * 0.6, d.face, 5.5, nil, PAL)
		soundAt(SND.Whoosh, d.dest, 0.9, 1.3)
	end)
end

handlers.EchoHit = function(d)
	local PAL, BOLT_COLORS = palOf(d.userId)
	local f = castFolder("EchoHit")
	local pos = d.pos
	FX.glow(f, pos, 11, PAL.Core, 0.22, { brightness = 4 })
	FX.glow(f, pos, 17, PAL.Violet, 0.45)
	FX.ring(f, pos, camFacing(pos), 1, 12, PAL.Violet, 0.3)
	FX.streaks(f, pos, { dir = d.dir, spread = 35, color = WHITE, color2 = PAL.Violet, count = 30, speed = { 60, 140 }, size = 0.5, life = 0.3 })
	FX.arcs(f, pos, 4, { outward = true, count = 4, colors = BOLT_COLORS, width = 0.1 })
	FX.sparks(f, pos, { color = PAL.Spark, color2 = PAL.Violet, count = 22, speed = { 25, 55 } })
	FX.light(f, pos, PAL.Violet, 9, 28, 0.3)
	soundAt(SND.HitHeavy, pos, 1, 0.95)
	if d.userId == player.UserId then
		local tint = PAL.EchoTint or Color3.fromRGB(225, 215, 255)
		FX.impact({ tint = tint, lineColor = tint, lineTime = 0.3 })
		shake(0.6, 0.32, 26, -3)
	end
end

-- G -----------------------------------------------------------------------------------------------
local function endGod(st, keepRoot)
	if not st or st.ended then
		return
	end
	st.ended = true
	st.crackle = false
	if st.aura then
		st.aura:Destroy()
		st.aura = nil
	end
	if st.rocks then
		st.rocks:drop()
		st.rocks = nil
	end
	if gods[st.userId] == st then
		gods[st.userId] = nil
	end
	if st.isLocal then
		stopCinematic()
		if not keepRoot then
			rootUntil = 0
		end
	end
end

handlers.GodspeedCast = function(d)
	local PAL, BOLT_COLORS = palOf(d.userId)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local e = now() - d.t0
	if e > d.charge + 0.5 then
		return -- joined after the charge; the hops draw themselves
	end
	endGod(gods[d.userId])
	playClip(char, Clips.GodCharge, e)
	local f = castFolder("Godspeed")
	local st = {
		id = d.id, userId = d.userId, folder = f, char = char, isLocal = isLocal, crackle = true, nextArc = 0,
		pal = PAL, bolts = BOLT_COLORS, -- the colourway is fixed for the whole cast
	}
	gods[d.userId] = st
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if isLocal then
		root(d.charge + CFG.Godspeed.MaxTargets * CFG.Godspeed.HopEvery + 1.5, flat(hrp and hrp.CFrame.LookVector or Vector3.new(0, 0, -1)))
		if char and e < 0.3 then
			startCinematic(char, d)
		end
		task.delay(math.max(0.1 - e, 0), function()
			godTitle(PAL, CFG.Labels.Godspeed, CFG.Callouts.Godspeed.kanji)
		end)
	elseif hrp and camDist(hrp.Position) < 120 then
		task.delay(math.max(0.1 - e, 0), function()
			godTitle(PAL, CFG.Labels.Godspeed, CFG.Callouts.Godspeed.kanji)
		end)
	end
	if hrp then
		st.aura = FX.aura(hrp, PAL.Core, PAL.Bolt, 80)
		st.rocks = FX.liftRocks(f, hrp.Position, 12, 12)
		sound(SND.Crackle, hrp, 0.9, 0.85)
		sound(SND.Zap, hrp, 0.8, 0.7)
		local g = FX.groundHit(hrp.Position, 8)
		if g then
			for i = 0, 2 do
				task.delay(i * 0.25, function()
					FX.ring(f, g.Position + UP * 0.2, UP, 22, 2, PAL.Bolt, 0.4, { ease = "in", alpha = 0.25 })
				end)
			end
		end
	end
	-- lightning lands around him while he charges
	for _, tt in ipairs({ 0.18, 0.42, 0.66 }) do
		if tt > e then
			task.delay(tt - math.max(e, 0), function()
				local h = char and char:FindFirstChild("HumanoidRootPart")
				if not h or st.ended then
					return
				end
				local a = math.random() * TAU
				local p = h.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * (7 + math.random() * 7)
				local g = FX.groundHit(p, 12)
				p = g and g.Position or (p - UP * 3)
				skyBolt(f, p, 0.55, 1, PAL)
				FX.glow(f, p, 9, PAL.Bolt, 0.3)
				FX.ring(f, p + UP * 0.2, UP, 1, 11, PAL.Bolt, 0.35)
				FX.sparks(f, p, { color = PAL.Spark, color2 = PAL.Bolt, count = 12, speed = { 20, 45 } })
				soundAt(SND.Zap, p, 0.7, 1.1)
				if isLocal then
					shake(0.35, 0.25, 26)
				end
			end)
		end
	end
	-- the release
	task.delay(math.max(d.charge - e, 0), function()
		if st.ended then
			return
		end
		st.crackle = false
		if st.aura then
			st.aura:Destroy()
			st.aura = nil
		end
		if st.rocks then
			st.rocks:drop(UP * 30)
			st.rocks = nil
		end
		local h = char and char:FindFirstChild("HumanoidRootPart")
		if h then
			FX.glow(f, h.Position, 12, PAL.Core, 0.3, { brightness = 3 })
			FX.ring(f, h.Position - UP * 2.6, UP, 2, 44, PAL.Bolt, 0.55)
			FX.streaks(f, h.Position, { color = WHITE, color2 = PAL.Bolt, count = 70, speed = { 90, 200 }, size = 0.7, life = 0.4 })
			FX.arcs(f, h.Position, 8, { outward = true, count = 8, colors = BOLT_COLORS, width = 0.15 })
			soundAt(SND.Boom, h.Position, 1, 1.2)
		end
		if isLocal then
			stopCinematic()
			FX.impact({ tint = PAL.Spark, lineColor = PAL.Spark, lineTime = 0.4 })
			FX.speedLines(CFG.Godspeed.MaxTargets * CFG.Godspeed.HopEvery + 0.6, { color = PAL.Spark, alpha = 0.45, inner = 0.5, count = 48 })
			shake(0.8, 0.4, 24, 10)
		end
	end)
end

handlers.GodspeedHop = function(d)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local st = gods[d.userId]
	local PAL, BOLT_COLORS = palOf(d.userId)
	if st and st.pal then
		PAL, BOLT_COLORS = st.pal, st.bolts or BOLT_COLORS
	end
	local f = st and st.folder or castFolder("Godspeed")
	ghost(char, PAL.Bolt, 0.4, 0.45) -- an afterimage where he was
	FX.bolt(f, d.from, d.to, { color = PAL.Bolt, core = PAL.Core, width = 0.3, jag = 0.12, segments = 8, life = 0.22, restrike = 2, light = true })
	FX.bolt(f, d.from + UP * 0.8, d.to + UP * 0.8, { color = PAL.Violet, width = 0.12, jag = 0.2, life = 0.18 })
	if isLocal and char == player.Character then
		blinkTo(CFrame.lookAt(d.to, d.to + d.face))
		faceDir = d.face
		root(0.6)
		shake(0.45, 0.2, 28, 3)
		if d.i % 3 == 0 then
			FX.impact({ tint = PAL.Spark, lines = false, flashAlpha = 0.25 })
		else
			FX.flash(PAL.Spark, 0.22, 0.12)
		end
	end
	playClip(char, ({ Clips.HopA, Clips.HopB, Clips.HopC })[(d.i - 1) % 3 + 1], 0)
	local pos = d.pos
	FX.glow(f, pos, 9, PAL.Core, 0.2, { brightness = 3.5 })
	FX.ring(f, pos, camFacing(pos), 1, 10, PAL.Bolt, 0.28)
	FX.streaks(f, pos, { dir = d.face, spread = 35, color = WHITE, color2 = PAL.Bolt, count = 22, speed = { 50, 120 }, size = 0.45, life = 0.28 })
	FX.arcs(f, pos, 3, { outward = true, count = 3, colors = { PAL.Bolt, PAL.Violet }, width = 0.1 })
	FX.sparks(f, pos, { color = PAL.Spark, color2 = PAL.Bolt, count = 16, speed = { 20, 50 } })
	soundAt(SND.Hit, pos, 0.8, 1 + (d.i % 4) * 0.08)
	soundAt(SND.Zap, d.to, 0.5, 1.3)
	if isLocal and d.i == 1 then
		godTitle(PAL, "WHIRLWIND", "疾風迅雷")
	end
end

handlers.GodspeedFinale = function(d)
	local char, caster = charOf(d.userId)
	local isLocal = caster == player
	local st = gods[d.userId]
	local PAL = (st and st.pal) or palOf(d.userId)
	local f = st and st.folder or castFolder("Godspeed")
	for i, p in ipairs(d.points or {}) do
		task.delay((i - 1) * 0.025, function()
			skyBolt(f, p, 0.9, 2, PAL)
			FX.glow(f, p, 15, PAL.Bolt, 0.4)
			FX.ring(f, p, UP, 1, 15, PAL.Bolt, 0.35)
			FX.sparks(f, p, { color = PAL.Spark, color2 = PAL.Bolt, count = 18, speed = { 25, 60 } })
			soundAt(SND.Zap, p, 0.6, 0.9 + i * 0.03)
		end)
	end
	local c = d.center
	FX.glow(f, c, 16, PAL.Core, 0.3, { brightness = 2.5 })
	FX.ring(f, c - UP * 2.5, UP, 4, 75, PAL.Bolt, 0.75)
	FX.ring(f, c, camFacing(c), 2, 40, PAL.Violet, 0.5)
	soundAt(SND.Thunder, c, 1, 0.8)
	soundAt(SND.Boom, c, 1, 0.9)
	local k = math.clamp(1 - camDist(c) / 260, 0, 1)
	if k > 0 then
		shake(1.5 * k, 0.7, 22, 10 * k)
		if not isLocal then
			FX.flash(PAL.Flash or Color3.fromRGB(225, 238, 255), 0.3 * k, 0.3)
		end
	end
	playClip(char, Clips.GodFinale, 0)
	if isLocal then
		FX.impact({ tint = PAL.Spark, lineColor = PAL.Spark, lineTime = 0.5, flashAlpha = 0.3 })
		rootUntil = os.clock() + 0.3
	end
	endGod(st, true)
end

handlers.GodspeedCancel = function(d)
	endGod(gods[d.userId])
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	local h = handlers[kind]
	if h and type(d) == "table" then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[GodspeedClient] " .. tostring(kind) .. " failed: " .. tostring(err))
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- every frame: movement, the charge crackle, Godspeed mode on any character, shocked bodies, the HUD
local modeFx = {} -- [character] = { aura, light, nextArc, nextGhost }
local shockFx = {} -- [model] = { light, nextArc }
local shockList, shockScan = {}, 0

local function updateMode(clock)
	local t = now()
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and (char:GetAttribute("Godspeed") or 0) > t then
			seen[char] = true
			local PAL, BOLT_COLORS = palOf(p)
			local m = modeFx[char]
			if m and m.pal ~= PAL then -- the skin was switched mid-mode: rebuild in the new colours
				if m.aura then
					m.aura:Destroy()
				end
				if m.light then
					m.light:Destroy()
				end
				m = nil
			end
			if not m then
				m = { nextArc = 0, nextGhost = 0, pal = PAL }
				m.aura = FX.aura(hrp, PAL.Core, PAL.Bolt, 38)
				local l = Instance.new("PointLight")
				l.Name = "GodspeedLight"
				l.Color = PAL.Bolt
				l.Brightness = 2.2
				l.Range = 14
				l.Shadows = false
				l.Parent = hrp
				m.light = l
				modeFx[char] = m
			end
			if camDist(hrp.Position) < 220 and clock >= m.nextArc then
				m.nextArc = clock + 0.07
				bodyArc(Folder, char, (math.random() < 0.7) and PAL.Bolt or PAL.Violet, 0.07)
				if math.random() < 0.25 then
					FX.arcs(Folder, hrp.Position, 2.6, { outward = true, count = 1, colors = BOLT_COLORS, width = 0.06 })
				end
				m.light.Brightness = 1.6 + math.random() * 1.6
			end
			-- a trail of afterimages while he runs
			if (hrp.AssemblyLinearVelocity * FLAT).Magnitude > 12 and clock >= m.nextGhost and camDist(hrp.Position) < 220 then
				m.nextGhost = clock + (p == player and 0.07 or 0.12)
				ghost(char, PAL.Bolt, 0.6, 0.28)
			end
		end
	end
	for char, m in pairs(modeFx) do
		if not seen[char] then
			if m.aura then
				m.aura:Destroy()
			end
			if m.light then
				m.light:Destroy()
			end
			modeFx[char] = nil
		end
	end
end

local function updateShocked(clock, dt)
	local t = now()
	shockScan += dt
	if shockScan > 0.2 then
		shockScan = 0
		shockList = {}
		for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
			if (m:GetAttribute("Shocked") or 0) > t then
				table.insert(shockList, m)
			end
		end
	end
	local live = {}
	for _, m in ipairs(shockList) do
		local ut = m.Parent and m:FindFirstChild("UpperTorso")
		if ut and (m:GetAttribute("Shocked") or 0) > t then
			live[m] = true
			local s = shockFx[m]
			if not s then
				-- the colourway of whoever shocked it (LastHitBy), so a VIOLET STORM caster's victims crackle violet
				s = { nextArc = 0, pal = palOf(m:GetAttribute("LastHitBy")) }
				local l = Instance.new("PointLight")
				l.Name = "ShockLight"
				l.Color = s.pal.Bolt
				l.Range = 10
				l.Shadows = false
				l.Parent = ut
				s.light = l
				shockFx[m] = s
			end
			if clock >= s.nextArc and camDist(ut.Position) < 220 then
				s.nextArc = clock + 0.09 + math.random() * 0.06
				bodyArc(Folder, m, (math.random() < 0.7) and s.pal.Bolt or s.pal.Violet, 0.06)
				s.light.Brightness = (math.random() < 0.5) and 0.4 or (2 + math.random() * 2)
			end
		end
	end
	for m, s in pairs(shockFx) do
		if not live[m] then
			if s.light then
				s.light:Destroy()
			end
			shockFx[m] = nil
		end
	end
end

local function updateHud()
	local on = equipped()
	bar.Visible = on
	if not on then
		return
	end
	local t = now()
	for skill, b in pairs(buttons) do
		local rem = (cooldownEnd[skill] or 0) - t
		local k = math.clamp(rem / math.max(cooldownLen[skill] or 1, 0.1), 0, 1)
		if b.horizontal then
			b.cd.Size = UDim2.fromScale(k, 1)
		else
			b.cd.Size = UDim2.fromScale(1, k)
		end
		b.cdText.Text = rem > 0 and string.format(rem >= 10 and "%.0f" or "%.1f", rem) or ""
		local ready = rem <= 0
		if ready and not b.ready then
			b.scale.Scale = 1.14
			TweenService:Create(b.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		b.ready = ready
	end
	local char = player.Character
	local untilT = char and char:GetAttribute("Godspeed") or 0
	status.Text = untilT > t and string.format("GODSPEED  %.1fs", untilT - t) or ""
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	barScale.Scale = math.clamp(vp.Y / 720, 0.75, 1.3)
end

RunService.Heartbeat:Connect(function(dt)
	local clock = os.clock()
	local ok, err = pcall(updateMovement, dt)
	if not ok then
		warn("[GodspeedClient] movement: " .. tostring(err))
	end
	for _, st in pairs(gods) do
		if st.crackle and st.char and st.char.Parent and clock >= st.nextArc then
			st.nextArc = clock + 0.045
			local sp = st.pal or PAL
			bodyArc(st.folder, st.char, (math.random() < 0.6) and sp.Bolt or sp.Core, 0.08)
			local hrp = st.char:FindFirstChild("HumanoidRootPart")
			if hrp and math.random() < 0.5 then
				FX.arcs(st.folder, hrp.Position, 3.5, { outward = true, count = 1, colors = st.bolts or BOLT_COLORS, width = 0.08 })
			end
		end
	end
	ok, err = pcall(updateMode, clock)
	if not ok then
		warn("[GodspeedClient] mode: " .. tostring(err))
	end
	ok, err = pcall(updateShocked, clock, dt)
	if not ok then
		warn("[GodspeedClient] shocked: " .. tostring(err))
	end
	updateHud()
end)

-- the local character: capture its own movement numbers, and drop everything if it dies mid-move
local function hookCharacter(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local base = char:GetAttribute("KitWalkSpeed")
	baseMove = { ws = base or (hum.WalkSpeed > 0 and hum.WalkSpeed or 16), jp = hum.JumpPower, jh = hum.JumpHeight }
	wroteMovement = false
	rootUntil, mover, faceDir = 0, nil, nil
	hum.Died:Connect(function()
		rootUntil, mover = 0, nil
		endGod(gods[player.UserId])
		stopCinematic()
	end)
end
if player.Character then
	task.spawn(hookCharacter, player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

-- Studio test hooks (GojoShared.ClientDebug): ("Killua", skill) casts, ("KilluaAim", dir) / ("KilluaTarget", point)
-- stand in for the camera and the cursor
if RunService:IsStudio() then
	local dbg = ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Killua" and type(arg) == "string" then
				request(arg)
			elseif cmd == "KilluaAim" then
				debugAim = (typeof(arg) == "Vector3" and arg.Magnitude > 0) and arg.Unit or nil
			elseif cmd == "KilluaTarget" then
				debugTarget = typeof(arg) == "Vector3" and arg or nil
			end
		end)
	end
end

print("[GodspeedClient] ready - Q: Lightning Palm, E: Thunderbolt, R: Rhythm Echo, G: Godspeed")
