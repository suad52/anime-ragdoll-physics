--!nocheck
-- StarterPlayerScripts.PerkEventsClient (2026-11-14, sandbox shop): how the server events sold in the shop look, on
-- every client.
--   NUKE          PerkShared.Remotes.Nuke ("launch", { id, gz, t0, boom, fall, by, wave, r }) from ServerScriptService.PerkNuke.
--                 From t0: an air-raid siren, a red GROUND ZERO marker (a ring on the ground, a light pillar, a label with
--                 the distance) and an IMPACT IN n countdown. For the last `fall` s the warhead drops onto it, whistling.
--                 At `boom`: a flash, a fireball that swells into a mushroom cloud (it climbs, cools from fire to grey
--                 smoke and drifts away over ~20 s) and a shockwave ring + dust wall that crosses the map at `wave`
--                 studs/s out to `r`. The bang and the camera shake land when the wave reaches you (light first, then
--                 sound). All on server time, so everyone sees the same moment.
--   MOON GRAVITY  workspace attribute MoonUntil (server time; ServerScriptService.PerkWorldEvents): while it runs the
--                 world takes a cold silvery tint, dust motes drift up around you and a MOON GRAVITY countdown shows.
-- Settings: OptNoFlash (softer flash), OptNoShake (no shake: PerkFXClient.Shake checks it). Every part is local,
-- anchored, non-colliding, non-queryable and lives in workspace.PerkFXLocal. The nuke's own parts are NOT given to
-- Debris: a nuke kills dozens of dummies at once, their kill effects flood Debris past its item limit and Debris then
-- destroys its OLDEST items early - which was the mushroom cloud (playtest 2026-11-14). This script removes them itself
-- (and a backstop timer does, if a frame loop ever stops).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")

local C3, V3 = Color3.fromRGB, Vector3.new
local CS, CSK = ColorSequence.new, ColorSequenceKeypoint.new
local NS, NSK, NR = NumberSequence.new, NumberSequenceKeypoint.new, NumberRange.new
local UP = Vector3.yAxis
local TAU = math.pi * 2
local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local NEON, PLASTIC = Enum.Material.Neon, Enum.Material.SmoothPlastic
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is its X: this stands it up

local SIREN = "rbxassetid://9113073742" -- Air Raid Siren Old Fashioned 1 (Pro Sound Effects, 29.6 s)
local BOOM = "rbxassetid://127224055692526"
local WHOOSH = "rbxassetid://9120972444"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local folder = workspace:FindFirstChild("PerkFXLocal")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PerkFXLocal"
	folder.Parent = workspace
end

local function now()
	return workspace:GetServerTimeNow()
end
local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end
local function part(shape, size, cf, color, mat, tr, life)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color or C3(255, 255, 255)
	p.Material = mat or NEON
	p.Transparency = tr or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = folder
	if life then
		Debris:AddItem(p, life)
	end
	return p
end
local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function emitter(parent, o)
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.tex or TEX_SPARK
	e.Color = o.color or CS(C3(255, 255, 255))
	e.Size = o.size or NS(1)
	e.Transparency = o.tr or NS(0)
	e.Lifetime = o.life or NR(1)
	e.Speed = o.speed or NR(5)
	e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Acceleration = o.accel or Vector3.zero
	e.Drag = o.drag or 0
	e.LightEmission = o.light or 0
	e.LightInfluence = o.lightInf or 0
	e.Rotation = NR(0, 360)
	e.RotSpeed = o.rotSpeed or NR(-40, 40)
	e.EmissionDirection = o.dir or Enum.NormalId.Top
	e.Rate = o.rate or 0
	e.Enabled = (o.rate or 0) > 0
	if o.shape then
		e.Shape = o.shape
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	e.Parent = parent
	return e
end
-- a 2D sound (heard the same everywhere) or one on a part
local function sound(id, vol, pitch, onPart, life)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = pitch or 1
	if onPart then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 40
		s.RollOffMaxDistance = 2000
	end
	s.Parent = onPart or game:GetService("SoundService")
	s:Play()
	Debris:AddItem(s, life or 8)
	return s
end
local shakeHook = nil
local function shake(pos, power, range, t)
	if not shakeHook or not shakeHook.Parent then
		local fx = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("PerkFXClient")
		shakeHook = fx and fx:FindFirstChild("Shake")
	end
	if shakeHook then
		shakeHook:Fire(pos, power, range, t)
	end
end
local function lerp(a, b, k)
	return a + (b - a) * k
end
local function clamp01(x)
	return math.clamp(x, 0, 1)
end

---------------------------------------------------------------------------------------------------
-- screen layer: the nuke countdown, the moon timer, the flash
local gui = Instance.new("ScreenGui")
gui.Name = "PerkEvents"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 39 -- just under PerkFXClient's banner (40)
gui.Parent = player:WaitForChild("PlayerGui")
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "PerkEventsFlash"
flashGui.ResetOnSpawn = false
flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 60 -- over everything
flashGui.Parent = gui.Parent

local function pill(name, color, y)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, y)
	f.Size = UDim2.fromOffset(300, 40)
	f.BackgroundColor3 = C3(14, 10, 22)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = 2.5
	st.Parent = f
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -24, 1, -8)
	t.Position = UDim2.fromOffset(12, 4)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color:Lerp(C3(255, 255, 255), 0.35)
	t.Text = ""
	t.Parent = f
	local ts = Instance.new("UIStroke")
	ts.Color = C3(10, 6, 14)
	ts.Thickness = 1.5
	ts.Parent = t
	return f, t, st
end
-- (y 64: under Roblox's top bar; the shop's big banner sits lower, at 24% of the screen)
local nukePill, nukeText, nukeStroke = pill("NukeCountdown", C3(255, 70, 40), 64)
local moonPill, moonText = pill("MoonTimer", C3(150, 175, 255), 64)
local function layoutPills()
	-- both up at once: the moon timer moves under the nuke countdown
	moonPill.Position = UDim2.new(0.5, 0, 0, nukePill.Visible and 110 or 64)
end

local function flash(strength, hold, fade)
	if player:GetAttribute("OptNoFlash") then
		strength = strength * 0.35
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = C3(255, 250, 235)
	f.BackgroundTransparency = 1 - strength
	f.BorderSizePixel = 0
	f.Parent = flashGui
	task.delay(hold, function()
		tween(f, fade, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
	end)
	Debris:AddItem(f, hold + fade + 0.2)
end

-- one shared colour grade for every running nuke (the latest one drives it)
local nukeGrade
local function grade()
	if not nukeGrade or not nukeGrade.Parent then
		nukeGrade = Instance.new("ColorCorrectionEffect")
		nukeGrade.Name = "PerkNukeGrade"
		nukeGrade.Parent = Lighting
	end
	return nukeGrade
end

---------------------------------------------------------------------------------------------------
-- NUKE
local nukes = {} -- [id] = true while one runs here

local function buildMarker(gz)
	local parts = {}
	local ring = part(CYL, V3(0.4, 240, 240), CFrame.new(gz + UP * 0.3) * UPRIGHT, C3(255, 40, 30), NEON, 0.7)
	local inner = part(CYL, V3(0.5, 40, 40), CFrame.new(gz + UP * 0.35) * UPRIGHT, C3(255, 90, 60), NEON, 0.45)
	local pillar = part(CYL, V3(700, 7, 7), CFrame.new(gz + UP * 350) * UPRIGHT, C3(255, 50, 40), NEON, 0.65)
	parts = { ring, inner, pillar }
	local anchor = part(BLOCK, V3(0.2, 0.2, 0.2), CFrame.new(gz + UP * 34), nil, PLASTIC, 1)
	table.insert(parts, anchor)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 64)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 5000
	bb.Adornee = anchor
	bb.Parent = anchor
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Text = "GROUND ZERO"
	title.TextColor3 = C3(255, 90, 70)
	title.Parent = bb
	local s1 = Instance.new("UIStroke")
	s1.Color = C3(20, 4, 4)
	s1.Thickness = 2
	s1.Parent = title
	local dist = Instance.new("TextLabel")
	dist.BackgroundTransparency = 1
	dist.Position = UDim2.fromOffset(0, 34)
	dist.Size = UDim2.new(1, 0, 0, 24)
	dist.Font = Enum.Font.GothamBold
	dist.TextScaled = true
	dist.TextColor3 = C3(255, 235, 220)
	dist.Text = ""
	dist.Parent = bb
	local s2 = Instance.new("UIStroke")
	s2.Color = C3(20, 4, 4)
	s2.Thickness = 1.5
	s2.Parent = dist
	return { parts = parts, ring = ring, inner = inner, pillar = pillar, dist = dist }
end

local function buildWarhead()
	local m = {}
	local body = part(CYL, V3(11, 3.4, 3.4), CFrame.new(), C3(70, 74, 80), PLASTIC, 0)
	body.Material = Enum.Material.Metal
	local nose = part(BALL, V3(3.4, 3.4, 3.4), CFrame.new(), C3(60, 62, 66), PLASTIC, 0)
	nose.Material = Enum.Material.Metal
	local band = part(CYL, V3(0.8, 3.5, 3.5), CFrame.new(), C3(230, 190, 40), PLASTIC, 0)
	local fins = {}
	for i = 1, 4 do
		fins[i] = part(BLOCK, V3(0.25, 3.2, 3), CFrame.new(), C3(55, 58, 62), PLASTIC, 0)
		fins[i].Material = Enum.Material.Metal
	end
	local tail = part(BLOCK, V3(0.2, 0.2, 0.2), CFrame.new(), nil, PLASTIC, 1)
	local att = Instance.new("Attachment")
	att.Parent = tail
	emitter(att, { tex = TEX_FIRE, color = CS(C3(255, 220, 140), C3(255, 90, 30)), size = NS({ NSK(0, 2.6), NSK(1, 0.4) }),
		tr = NS({ NSK(0, 0.1), NSK(1, 1) }), life = NR(0.25, 0.45), speed = NR(8, 14), spread = Vector2.new(12, 12), light = 1, rate = 90,
		dir = Enum.NormalId.Top })
	emitter(att, { tex = TEX_SMOKE, color = CS(C3(120, 115, 110)), size = NS({ NSK(0, 2), NSK(1, 6) }), tr = NS({ NSK(0, 0.4), NSK(1, 1) }),
		life = NR(1.2, 2), speed = NR(2, 5), spread = Vector2.new(20, 20), lightInf = 1, rate = 40, dir = Enum.NormalId.Top })
	m.parts = { body, nose, band, tail, fins[1], fins[2], fins[3], fins[4] }
	-- place it with its nose at `tip`, pointing along `dir`
	function m.place(tip, dir)
		local look = CFrame.lookAt(tip, tip + dir, math.abs(dir.Y) > 0.98 and Vector3.xAxis or UP)
		nose.CFrame = look * CFrame.new(0, 0, -0.2)
		body.CFrame = look * CFrame.new(0, 0, 5.5) * CFrame.Angles(0, math.pi / 2, 0)
		band.CFrame = look * CFrame.new(0, 0, 3.2) * CFrame.Angles(0, math.pi / 2, 0)
		for i, fn in ipairs(fins) do
			fn.CFrame = look * CFrame.new(0, 0, 10.4) * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 2.6, 0)
		end
		tail.CFrame = look * CFrame.new(0, 0, 11.4) * CFrame.Angles(-math.pi / 2, 0, 0) -- emitters' Top = backwards
	end
	return m
end

local function destroyAll(list)
	for _, p in ipairs(list) do
		if p and p.Parent then
			p:Destroy()
		end
	end
end

-- the cloud, the fireball and the shockwave, from the detonation on
local LIFE_BACKSTOP = 26
local gradeOwner = nil -- the id of the nuke driving the colour grade (the latest one)
local function detonate(d)
	local gz, boom = d.gz, d.boom
	local wave, reach = math.max(tonumber(d.wave) or 230, 20), math.max(tonumber(d.r) or 640, 50)
	local distToMe = ((camPos() - gz) * V3(1, 0, 1)).Magnitude
	local near = clamp01(1 - distToMe / (reach * 1.1))
	flash(0.55 + 0.4 * near, 0.12, 2.2)
	local g = grade()
	gradeOwner = d.id
	g.Brightness, g.Contrast, g.Saturation, g.TintColor = 0.45, 0.25, 0.25, C3(255, 236, 205)
	tween(g, 2.5, { Brightness = -0.04, Contrast = 0.12, Saturation = -0.25, TintColor = C3(255, 214, 190) }, Enum.EasingStyle.Sine)
	task.delay(14, function()
		if g.Parent and gradeOwner == d.id then
			local tw = tween(g, 7, { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = C3(255, 255, 255) }, Enum.EasingStyle.Sine)
			tw.Completed:Connect(function()
				if g.Parent and gradeOwner == d.id then -- (a newer nuke owns it now: it fades it out itself)
					gradeOwner = nil
					g:Destroy()
				end
			end)
		end
	end)
	-- a rumble straight away (far), the real bang when the wave reaches you
	sound(BOOM, 0.5, 0.3, nil, 8)
	task.delay(math.max(0, boom + distToMe / wave - now()), function()
		sound(BOOM, 1.2 + 1.3 * near, 0.42, nil, 8)
		sound(BOOM, 0.8 + 0.8 * near, 0.6, nil, 8)
		shake(camPos(), 0.05 + 0.13 * near, 1e6, 1.4 + 1.2 * near)
	end)

	-- fireball -> mushroom cloud
	local fire = part(BALL, V3(6, 6, 6), CFrame.new(gz), C3(255, 255, 240), NEON, 0)
	local stem = part(CYL, V3(1, 30, 30), CFrame.new(gz) * UPRIGHT, C3(255, 170, 70), NEON, 0)
	local collar = {} -- (a ring of puffs around the stem; a flat disc read as a cross-bar from the side)
	for i = 1, 8 do
		collar[i] = part(BALL, V3(1, 1, 1), CFrame.new(gz), C3(255, 150, 60), NEON, 0.3)
	end
	local stemPuffs = {} -- billows along the stem so it isn't a plain pole
	for i = 1, 4 do
		stemPuffs[i] = part(BALL, V3(1, 1, 1), CFrame.new(gz), C3(255, 160, 60), NEON, 0)
	end
	local cap = part(BALL, V3(1, 1, 1), CFrame.new(gz), C3(255, 180, 80), NEON, 0)
	local puffs = {}
	for i = 1, 12 do
		puffs[i] = part(BALL, V3(1, 1, 1), CFrame.new(gz), C3(255, 150, 60), NEON, 0)
	end
	local tops = {}
	for i = 1, 5 do
		tops[i] = part(BALL, V3(1, 1, 1), CFrame.new(gz), C3(255, 170, 70), NEON, 0)
	end
	local baseDust = part(CYL, V3(8, 20, 20), CFrame.new(gz + UP * 3) * UPRIGHT, C3(150, 125, 105), PLASTIC, 0.25)
	local smokeHost = part(BLOCK, V3(60, 10, 60), CFrame.new(gz + UP * 8), nil, PLASTIC, 1)
	task.delay(32, function()
		if smokeHost.Parent then
			smokeHost:Destroy()
		end
	end)
	local smoke = emitter(smokeHost, { tex = TEX_SMOKE, color = CS(C3(95, 85, 78), C3(60, 56, 54)), size = NS({ NSK(0, 18), NSK(1, 46) }),
		tr = NS({ NSK(0, 0.35), NSK(0.6, 0.6), NSK(1, 1) }), life = NR(5, 8), speed = NR(6, 16), spread = Vector2.new(60, 60),
		accel = V3(0, 3, 0), drag = 0.4, lightInf = 1, rate = 14, shape = Enum.ParticleEmitterShape.Box })
	local embers = emitter(smokeHost, { tex = TEX_SPARK, color = CS(C3(255, 220, 140), C3(255, 90, 30)), size = NS({ NSK(0, 1.6), NSK(1, 0) }),
		life = NR(1.5, 3), speed = NR(30, 90), spread = Vector2.new(70, 70), accel = V3(0, -40, 0), light = 1, rate = 0,
		shape = Enum.ParticleEmitterShape.Box })
	embers:Emit(160)
	task.delay(9, function()
		smoke.Enabled = false
	end)
	local cloud = { fire, stem, cap, baseDust }
	for _, p in ipairs(collar) do
		table.insert(cloud, p)
	end
	for _, p in ipairs(stemPuffs) do
		table.insert(cloud, p)
	end
	for _, p in ipairs(puffs) do
		table.insert(cloud, p)
	end
	for _, p in ipairs(tops) do
		table.insert(cloud, p)
	end

	-- the shockwave: a glowing ring on the ground and a dust wall right behind it, made of segments
	local SEG, DSEG = 48, 36
	local ring, dust = {}, {}
	for i = 1, SEG do
		ring[i] = part(BLOCK, V3(4, 9, 2.5), CFrame.new(gz), C3(255, 235, 200), NEON, 0.15)
	end
	for i = 1, DSEG do
		dust[i] = part(BLOCK, V3(4, 22, 9), CFrame.new(gz), C3(150, 130, 112), PLASTIC, 0.35)
	end
	local waveDone = false
	task.delay(LIFE_BACKSTOP, function() -- if the frame loop ever stopped, nothing is left in the sky
		destroyAll(cloud)
		destroyAll(ring)
		destroyAll(dust)
	end)

	local FIRE_C = { C3(255, 255, 240), C3(255, 220, 120), C3(255, 140, 50), C3(200, 80, 30) }
	local SMOKE_C, SMOKE_D = C3(118, 106, 98), C3(84, 78, 76)
	local function fireCol(k) -- 0 white-hot .. 1 dull red
		k = clamp01(k) * 3
		local i = math.min(math.floor(k), 2)
		return FIRE_C[i + 1]:Lerp(FIRE_C[i + 2], k - i)
	end
	local LIFE = 22
	local swappedToSmoke = false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			local t = now() - boom
			-- shockwave
			if not waveDone then
				local R = wave * t
				if R >= reach then
					waveDone = true
					destroyAll(ring)
					destroyAll(dust)
				else
					local k = R / reach
					local segLen = TAU * math.max(R, 4) / SEG * 1.08
					for i, s in ipairs(ring) do
						local a = i / SEG * TAU
						local pos = gz + V3(math.cos(a) * R, 3 + 2 * (1 - k), math.sin(a) * R)
						s.CFrame = CFrame.lookAt(pos, pos + V3(-math.sin(a), 0, math.cos(a)))
						s.Size = V3(2.5, 9 * (1 - k * 0.6), segLen)
						s.Transparency = 0.15 + 0.75 * k
					end
					local Rd = math.max(R - 10, 2)
					local dLen = TAU * Rd / DSEG * 1.12
					for i, s in ipairs(dust) do
						local a = (i + 0.5) / DSEG * TAU
						local h = 22 * (1 - k * 0.5) * (0.85 + 0.3 * math.sin(i * 1.7 + t * 3))
						local pos = gz + V3(math.cos(a) * Rd, h / 2, math.sin(a) * Rd)
						s.CFrame = CFrame.lookAt(pos, pos + V3(-math.sin(a), 0, math.cos(a)))
						s.Size = V3(9, h, dLen)
						s.Transparency = 0.35 + 0.6 * k
					end
				end
			end
			-- the cloud: grows for ~7 s, cools from fire to smoke, holds, then thins out and drifts
			local grow = 1 - (1 - clamp01(t / 7)) ^ 3
			local ball = clamp01(t / 0.8)
			local cool = clamp01((t - 0.6) / 4.5)
			local fade = clamp01((t - 13) / (LIFE - 13))
			local drift = V3(1, 0, 0.4) * math.max(t - 8, 0) * 2.2
			local col = cool < 1 and fireCol(cool) or SMOKE_C
			if cool > 0.7 then
				col = fireCol(cool):Lerp(SMOKE_C, (cool - 0.7) / 0.3)
			end
			if not swappedToSmoke and cool >= 0.85 then
				swappedToSmoke = true
				for _, p in ipairs(cloud) do
					if p.Parent and p ~= baseDust then
						p.Material = PLASTIC -- grey neon glows; smoke must not
					end
				end
			end
			local H = 20 + 230 * grow
			local w = lerp(48, 40, grow)
			stem.Size = V3(H, w, w)
			stem.CFrame = CFrame.new(gz + drift * 0.3 + V3(0, H / 2, 0)) * UPRIGHT
			stem.Color = col:Lerp(SMOKE_D, 0.25)
			stem.Transparency = 0.05 + 0.95 * fade
			local top = gz + drift + V3(0, H, 0)
			local capW = 40 + 170 * grow
			cap.Size = V3(capW, capW * 0.56, capW)
			cap.CFrame = CFrame.new(top + V3(0, capW * 0.08, 0))
			cap.Color = col
			cap.Transparency = fade
			for i, p in ipairs(puffs) do
				local a = i / #puffs * TAU + t * 0.25
				local rr = capW * 0.4
				local sz = capW * (0.34 + 0.06 * math.sin(i * 2.3))
				p.Size = V3(sz, sz * 0.8, sz)
				p.CFrame = CFrame.new(top + V3(math.cos(a) * rr, -capW * 0.06 + math.sin(t * 1.3 + i) * 2, math.sin(a) * rr))
				p.Color = col:Lerp(SMOKE_D, 0.15 * (i % 3))
				p.Transparency = 0.05 + 0.95 * fade
			end
			for i, p in ipairs(tops) do
				local a = i / #tops * TAU - t * 0.2
				local sz = capW * 0.42
				p.Size = V3(sz, sz * 0.7, sz)
				p.CFrame = CFrame.new(top + V3(math.cos(a) * capW * 0.18, capW * 0.2, math.sin(a) * capW * 0.18))
				p.Color = col
				p.Transparency = 0.05 + 0.95 * fade
			end
			-- the collar of cloud a third of the way up the stem (it thins out first)
			local cr = w * 0.5 + 14 + 26 * grow
			local cs = 20 + 28 * grow
			local ct = 0.3 + 0.7 * math.max(fade, clamp01((t - 9) / 6))
			for i, p in ipairs(collar) do
				local a = i / #collar * TAU + t * 0.15
				p.Size = V3(cs, cs * 0.6, cs)
				p.CFrame = CFrame.new(gz + drift * 0.5 + V3(math.cos(a) * cr, H * 0.42, math.sin(a) * cr))
				p.Color = col:Lerp(SMOKE_D, 0.3)
				p.Transparency = ct
			end
			-- billows up the stem
			for i, p in ipairs(stemPuffs) do
				local k = i / (#stemPuffs + 1)
				local sz = w * (1.25 + 0.15 * math.sin(i * 1.9 + t))
				p.Size = V3(sz, sz * 0.9, sz)
				p.CFrame = CFrame.new(gz + drift * (0.3 + 0.6 * k) + V3(math.sin(i * 2.1) * w * 0.12, H * k, math.cos(i * 2.1) * w * 0.12))
				p.Color = col:Lerp(SMOKE_D, 0.2)
				p.Transparency = 0.05 + 0.95 * fade
			end
			-- the fireball: swells fast, then rises into the cap and is gone
			local fr = lerp(6, 120, 1 - (1 - ball) ^ 2)
			fire.Size = V3(fr, fr, fr)
			fire.CFrame = CFrame.new(gz + V3(0, fr * 0.3 + H * clamp01((t - 0.8) / 2.5) * 0.9, 0))
			fire.Color = fireCol(clamp01(t / 2.2))
			fire.Transparency = clamp01((t - 1.6) / 1.6)
			-- the dust skirt on the ground
			local bd = lerp(20, 260, 1 - (1 - clamp01(t / 4)) ^ 2)
			baseDust.Size = V3(lerp(8, 18, clamp01(t / 4)), bd, bd)
			baseDust.Transparency = 0.25 + 0.75 * math.max(fade, clamp01((t - 6) / 10))
			if t >= LIFE then
				conn:Disconnect()
				destroyAll(cloud)
				destroyAll(ring)
				destroyAll(dust)
				nukes[d.id] = nil
			end
		end)
		if not ok then
			conn:Disconnect()
			destroyAll(cloud)
			destroyAll(ring)
			destroyAll(dust)
			nukes[d.id] = nil
			warn("[PerkEventsClient] nuke cloud failed: " .. tostring(err))
		end
	end)
end

local function runNuke(d)
	if type(d) ~= "table" or typeof(d.gz) ~= "Vector3" or type(d.boom) ~= "number" then
		return
	end
	local id = d.id or tostring(d.boom)
	d.id = id
	if nukes[id] or now() > d.boom + 2 then
		return -- already drawing it, or it went off before we heard about it
	end
	nukes[id] = true
	local gz, boom = d.gz, d.boom
	local fall = math.clamp(tonumber(d.fall) or 3, 0.5, 10)
	local mk = buildMarker(gz)
	local siren = sound(SIREN, 0.55, 1, nil, 40)
	local warhead, whistle = nil, nil
	local H0 = 560
	local tilt = V3(math.random() - 0.5, 0, math.random() - 0.5) * 0.25
	nukePill.Visible = true
	nukeStroke.Color = C3(255, 70, 40)
	layoutPills()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(function()
			local n = now()
			local left = boom - n
			if left > 0 then
				nukeText.Text = string.format("NUKE IMPACT IN %d", math.ceil(left))
				local pulse = 0.5 + 0.5 * math.sin(n * 9)
				nukeStroke.Thickness = 2 + 2 * pulse
				mk.ring.Transparency = 0.55 + 0.3 * pulse
				mk.inner.Transparency = 0.35 + 0.3 * (1 - pulse)
				mk.pillar.Transparency = 0.55 + 0.25 * pulse
				mk.dist.Text = string.format("%d STUDS AWAY", math.floor(((camPos() - gz) * V3(1, 0, 1)).Magnitude + 0.5))
				-- the warhead, for the last `fall` seconds
				if left <= fall then
					if not warhead then
						warhead = buildWarhead()
						whistle = sound(WHOOSH, 2, 0.32, warhead.parts[1], 6)
						whistle.Looped = true
					end
					local s = clamp01(1 - left / fall)
					local y = H0 * (1 - s * s)
					local off = tilt * y
					local tip = gz + V3(off.X, y + 2, off.Z)
					warhead.place(tip, (-UP - tilt).Unit)
					if whistle then
						whistle.PlaybackSpeed = 0.32 + 0.25 * s
					end
				end
			else
				conn:Disconnect()
				destroyAll(mk.parts)
				if warhead then
					destroyAll(warhead.parts)
				end
				if siren and siren.Parent then
					local tw = tween(siren, 2.5, { Volume = 0 })
					tw.Completed:Connect(function()
						siren:Destroy()
					end)
				end
				nukeText.Text = "NUKE IMPACT!"
				task.delay(2.5, function()
					local other = false
					for _ in pairs(nukes) do
						other = true
					end
					-- (the next queued nuke re-shows it with its own countdown)
					if nukeText.Text == "NUKE IMPACT!" then
						nukePill.Visible = false
						layoutPills()
					end
				end)
				detonate(d)
			end
		end)
		if not ok then
			conn:Disconnect()
			destroyAll(mk.parts)
			if warhead then
				destroyAll(warhead.parts)
			end
			nukes[id] = nil
			nukePill.Visible = false
			layoutPills()
			warn("[PerkEventsClient] nuke failed: " .. tostring(err))
		end
	end)
end

task.spawn(function()
	local NukeRemote = Remotes:WaitForChild("Nuke", 60)
	if not NukeRemote then
		warn("[PerkEventsClient] PerkShared.Remotes.Nuke never appeared - no nuke visuals")
		return
	end
	NukeRemote.OnClientEvent:Connect(function(kind, data)
		if kind == "launch" then
			local ok, err = pcall(runNuke, data)
			if not ok then
				warn("[PerkEventsClient] nuke launch failed: " .. tostring(err))
			end
		end
	end)
end)

---------------------------------------------------------------------------------------------------
-- MOON GRAVITY
local moonOn = false
local moonGrade, motesHost
local function setMoon(on)
	if on == moonOn then
		return
	end
	moonOn = on
	moonPill.Visible = on
	layoutPills()
	if on then
		if not moonGrade or not moonGrade.Parent then
			moonGrade = Instance.new("ColorCorrectionEffect")
			moonGrade.Name = "PerkMoonGrade"
			moonGrade.Parent = Lighting
		end
		tween(moonGrade, 1.5, { TintColor = C3(208, 218, 255), Saturation = -0.35, Contrast = 0.1, Brightness = -0.02 }, Enum.EasingStyle.Sine)
		if not motesHost or not motesHost.Parent then
			motesHost = part(BLOCK, V3(90, 36, 90), CFrame.new(camPos()), nil, PLASTIC, 1)
			emitter(motesHost, { tex = TEX_SPARK, color = CS(C3(230, 238, 255), C3(160, 180, 255)), size = NS({ NSK(0, 0), NSK(0.2, 0.28), NSK(0.8, 0.22), NSK(1, 0) }),
				life = NR(4, 7), speed = NR(0.4, 1.4), spread = Vector2.new(180, 180), accel = V3(0, 0.8, 0), light = 0.7, rate = 30,
				shape = Enum.ParticleEmitterShape.Box })
		end
	else
		if moonGrade and moonGrade.Parent then
			local g = moonGrade
			local tw = tween(g, 2, { TintColor = C3(255, 255, 255), Saturation = 0, Contrast = 0, Brightness = 0 }, Enum.EasingStyle.Sine)
			tw.Completed:Connect(function()
				if not moonOn and g.Parent then
					g:Destroy()
				end
			end)
		end
		if motesHost and motesHost.Parent then
			local h = motesHost
			motesHost = nil
			for _, e in ipairs(h:GetChildren()) do
				if e:IsA("ParticleEmitter") then
					e.Enabled = false
				end
			end
			Debris:AddItem(h, 8)
		end
	end
end

RunService.Heartbeat:Connect(function()
	local untilT = workspace:GetAttribute("MoonUntil")
	local left = type(untilT) == "number" and (untilT - now()) or 0
	setMoon(left > 0)
	if moonOn then
		local s = math.max(0, math.ceil(left))
		moonText.Text = string.format("MOON GRAVITY  %d:%02d", s // 60, s % 60)
		if motesHost and motesHost.Parent then
			motesHost.CFrame = CFrame.new(camPos())
		end
	end
end)

-- Studio-only test hook: script.EventsDebug:Invoke("state") -> what is showing
if RunService:IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "EventsDebug"
	bf.OnInvoke = function()
		local n = 0
		for _ in pairs(nukes) do
			n += 1
		end
		return { nukes = n, nukePill = nukePill.Visible, nukeText = nukeText.Text, moon = moonOn, moonText = moonText.Text,
			parts = #folder:GetChildren(), nukeGrade = nukeGrade ~= nil and nukeGrade.Parent ~= nil, moonGrade = moonGrade ~= nil and moonGrade.Parent ~= nil }
	end
	bf.Parent = script
end
