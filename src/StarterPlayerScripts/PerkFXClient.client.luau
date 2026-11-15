--!nocheck
-- StarterPlayerScripts.PerkFXClient (owner: fx, perks 2026-11-07): draws the fx perks for everybody in the server.
--   PerkFX "KO"     { { s = style, p = Vector3, u = userId }, ... }  Confetti / Explosion / Lightning (~1.5 s)
--                   (2026-11-14, sandbox shop) + BlackHole / Firework / Frozen / Soul / Pixel / MiniNuke (~2 s)
--                                                                    (ServerScriptService.PerkKOFX)
--   PerkFX "Meteor" { id, a, b, n, t0, d, s, r, big }               a fiery meteor flying a -> b on SERVER time
--                                                                    (t0 + d = impact), then the impact blast
--   PerkFX "Knock"  (vel, ragTime)                                  this client's own body is tumbled (no damage)
--   Announce        { title, sub, color, accent, time } | string    the big centre banner (queued)
--   PerkFX attribute MeteorUntil (server time)                      the sky is tinted while a shower runs
-- (ServerScriptService.PerkMeteorShower). Every part is local, anchored, CanCollide / CanQuery / CanTouch false,
-- lives in workspace.PerkFXLocal and is destroyed on a timer (Debris), so nothing outlives its effect.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")
local PerkFX = Remotes:WaitForChild("PerkFX")
local Announce = Remotes:WaitForChild("Announce")

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	flare = "rbxasset://textures/particles/fire_sparks_main.dds",
}
local SND = {
	Boom = "rbxassetid://127224055692526",
	Whoosh = "rbxassetid://9120972444",
	Sizzle = "rbxassetid://8927189937",
	Boing = "rbxassetid://125984645781295",
}
local KO_RANGE = 450 -- KO effects farther than this from the camera are skipped
local KO_MAX = 10 -- KO effects alive at once
local CONFETTI_MAX = 500 -- confetti pieces alive at once

local C3 = Color3.fromRGB
local V3 = Vector3.new
local CS = ColorSequence.new
local CSK = ColorSequenceKeypoint.new
local NS = NumberSequence.new
local NSK = NumberSequenceKeypoint.new
local NR = NumberRange.new
local UP = Vector3.yAxis
local TAU = math.pi * 2
local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local NEON, PLASTIC = Enum.Material.Neon, Enum.Material.SmoothPlastic

local folder = workspace:FindFirstChild("PerkFXLocal")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PerkFXLocal"
	folder.Parent = workspace
end
-- (2026-11-07) the shop's KO preview: while set, every part goes into this WorldModel (inside a ViewportFrame) instead
-- of the world, and sounds / camera shake / ground raycasts are skipped. Set only through script.KOPreview (below).
local previewSink = nil

---------------------------------------------------------------------------------------------------
-- helpers
local function rand(a, b)
	return a + math.random() * (b - a)
end

local function randomUnit()
	local v = V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function part(shape, size, cf, color, mat, tr, life)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color or C3(255, 255, 255)
	p.Material = mat or NEON
	p.Transparency = tr or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = previewSink or folder
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

local function unitOr(v, fallback)
	return (typeof(v) == "Vector3" and v == v and v.Magnitude > 1e-3) and v.Unit or fallback
end

-- a tangent of the surface whose normal is n
local function tangentOf(n)
	local ref = math.abs(n.Y) < 0.9 and UP or Vector3.xAxis
	return n:Cross(ref).Unit
end

-- a Cylinder's axis is its X: this lays a disc flat on the surface whose normal is n
local function discCF(pos, n)
	return CFrame.fromMatrix(pos, n, tangentOf(n))
end

-- a frame whose UpVector is n (emitters in it shoot Top = away from the surface)
local function upCF(pos, n)
	return CFrame.fromMatrix(pos, tangentOf(n), n)
end

local function lookCF(pos, dir)
	if math.abs(dir.Y) > 0.98 then
		return CFrame.lookAt(pos, pos + dir, Vector3.xAxis)
	end
	return CFrame.lookAt(pos, pos + dir)
end

-- an invisible anchored holder + a centre Attachment for emitters / lights / sounds; destroyed after `life`
local function host(cf, life)
	local p = part(BLOCK, V3(0.2, 0.2, 0.2), cf, nil, PLASTIC, 1, life)
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

local function emitter(parent, o)
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.tex or TEX.spark
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
	e.RotSpeed = o.rotSpeed or NR(-90, 90)
	e.EmissionDirection = o.dir or Enum.NormalId.Top
	e.ZOffset = o.z or 0
	e.Rate = o.rate or 0
	e.Enabled = (o.rate or 0) > 0
	e.Parent = parent
	return e
end

local function pointLight(parent, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = math.min(range, 60)
	l.Shadows = false
	l.Parent = parent
	return l
end

-- a one-shot 3D sound at a point (or on a part, so it follows it)
local function sound(id, pos, vol, pitch, maxDist, onPart)
	if previewSink then
		return Instance.new("Sound") -- a silent stand-in: previews make no noise
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = pitch or 1
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = maxDist or 400
	if onPart then
		s.Parent = onPart
	else
		local a = Instance.new("Attachment")
		a.Position = pos
		a.Parent = workspace.Terrain
		s.Parent = a
		Debris:AddItem(a, 7)
	end
	s:Play()
	Debris:AddItem(s, 7)
	return s
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
groundParams.RespectCanCollide = true
local function groundBelow(pos)
	if previewSink then
		return pos - UP * 2.5, UP -- the preview's floor sits 2.5 studs under the body
	end
	local list = { folder }
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(list, npcs)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(pos + UP * 2, V3(0, -16, 0), groundParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return pos - UP * 2.5, UP
end

---------------------------------------------------------------------------------------------------
-- camera shake: applied after the camera updates and taken back off before the next update, so the camera
-- scripts (which read the camera's look vector back) never inherit it
local shakeAmp, shakeEnd, shakeLen = 0, 0, 1
local applied = nil
local function shake(pos, power, range, t)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	if previewSink then
		return
	end
	local k = math.clamp(1 - (camPos() - pos).Magnitude / range, 0, 1)
	if k <= 0 then
		return
	end
	local now = os.clock()
	local left = math.max(shakeEnd - now, 0) / shakeLen * shakeAmp
	local amp = power * k
	if amp > left then
		shakeAmp, shakeLen, shakeEnd = amp, t, now + t
	end
end
-- (2026-11-14) other local scripts shake through this too (StarterPlayerScripts.PerkEventsClient: the Nuke):
-- script.Shake:Fire(pos, power, range, seconds)
do
	local be = Instance.new("BindableEvent")
	be.Name = "Shake"
	be.Archivable = false
	be.Event:Connect(function(pos, power, range, t)
		if typeof(pos) == "Vector3" then
			shake(pos, tonumber(power) or 0, tonumber(range) or 100, tonumber(t) or 0.5)
		end
	end)
	be.Parent = script
end
RunService:BindToRenderStep("PerkFXUnshake", Enum.RenderPriority.First.Value, function()
	if applied then
		local cam = workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Custom then
			cam.CFrame = cam.CFrame * applied:Inverse()
		end
		applied = nil
	end
end)
RunService:BindToRenderStep("PerkFXShake", Enum.RenderPriority.Camera.Value + 2, function()
	local now = os.clock()
	if now >= shakeEnd then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Custom then
		local a = shakeAmp * (shakeEnd - now) / shakeLen
		local off = CFrame.Angles(rand(-a, a), rand(-a, a), rand(-a, a) * 0.5)
		cam.CFrame = cam.CFrame * off
		applied = off
	end
end)

---------------------------------------------------------------------------------------------------
-- KO effects
local KO_INK = {
	Confetti = { C3(255, 240, 120), C3(230, 40, 140) },
	Explosion = { C3(255, 210, 90), C3(170, 30, 10) },
	Lightning = { C3(215, 245, 255), C3(30, 90, 230) },
	BlackHole = { C3(225, 200, 255), C3(70, 20, 150) },
	Firework = { C3(255, 240, 150), C3(220, 40, 120) },
	Frozen = { C3(230, 250, 255), C3(40, 120, 200) },
	Soul = { C3(255, 255, 255), C3(110, 130, 200) },
	Pixel = { C3(150, 255, 255), C3(200, 30, 160) },
	MiniNuke = { C3(255, 230, 120), C3(160, 50, 10) },
}

local function koText(pos, style)
	local ink = KO_INK[style] or KO_INK.Explosion
	local anchor = part(BLOCK, V3(0.2, 0.2, 0.2), CFrame.new(pos), nil, PLASTIC, 1, 1.6)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(7, 40, 2.8, 16)
	bb.StudsOffsetWorldSpace = V3(0, 3.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = KO_RANGE
	bb.Adornee = anchor
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = "K.O.!"
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = ink[1]
	t.Rotation = rand(-10, 10)
	t.Parent = bb
	local st = Instance.new("UIStroke")
	st.Color = ink[2]
	st.Thickness = 3
	st.Parent = t
	local sc = Instance.new("UIScale")
	sc.Scale = 0.2
	sc.Parent = t
	tween(sc, 0.22, { Scale = 1.15 }, Enum.EasingStyle.Back)
	task.delay(0.22, function()
		if sc.Parent then
			tween(sc, 0.15, { Scale = 1 })
		end
	end)
	tween(bb, 1.4, { StudsOffsetWorldSpace = V3(0, 7, 0) }, Enum.EasingStyle.Sine)
	task.delay(0.95, function()
		if t.Parent then
			tween(t, 0.45, { TextTransparency = 1 })
			tween(st, 0.45, { Transparency = 1 })
		end
	end)
end

-- CONFETTI: a popper flash, then ~56 paper pieces simulated here (burst up, then flutter down)
local confetti = {}
local CONF_COLORS = {
	C3(255, 70, 90), C3(255, 200, 40), C3(80, 220, 120), C3(70, 170, 255), C3(200, 90, 255), C3(255, 140, 220), C3(255, 255, 255),
}
local function koConfetti(pos)
	local fl = part(BALL, V3(1, 1, 1), CFrame.new(pos), C3(255, 255, 255), NEON, 0.1, 0.4)
	tween(fl, 0.3, { Size = V3(9, 9, 9), Transparency = 1 })
	local g, n = groundBelow(pos)
	local ring = part(CYL, V3(0.3, 2, 2), discCF(g + n * 0.2, n), C3(255, 220, 90), NEON, 0.2, 0.55)
	tween(ring, 0.5, { Size = V3(0.1, 20, 20), Transparency = 1 })
	local count = math.min(56, CONFETTI_MAX - #confetti)
	local now = os.clock()
	for _ = 1, count do
		local p = part(BLOCK, V3(rand(0.35, 0.6), 0.05, rand(0.22, 0.38)), CFrame.new(pos), CONF_COLORS[math.random(#CONF_COLORS)], PLASTIC, 0, 3)
		local a, h = math.random() * TAU, rand(6, 26)
		table.insert(confetti, {
			p = p, pos = pos, vel = V3(math.cos(a) * h, rand(28, 62), math.sin(a) * h),
			rot = CFrame.Angles(rand(0, TAU), rand(0, TAU), rand(0, TAU)),
			spin = V3(rand(-12, 12), rand(-12, 12), rand(-12, 12)),
			t0 = now, life = rand(1.3, 1.9), ph = math.random() * TAU,
		})
	end
	local _, att = host(CFrame.new(pos), 1.6)
	emitter(att, {
		tex = TEX.spark, color = CS(C3(255, 255, 255), C3(255, 220, 120)), size = NS({ NSK(0, 1.4), NSK(1, 0) }),
		life = NR(0.5, 0.9), speed = NR(18, 36), light = 1, drag = 3,
	}):Emit(40)
	sound(SND.Boing, pos, 0.9, rand(1.15, 1.3), 260)
	shake(pos, 0.006, 60, 0.25)
end

local function stepConfetti(dt, now)
	local drag = math.exp(-3.2 * dt)
	local i = 1
	while i <= #confetti do
		local c = confetti[i]
		local age = now - c.t0
		if age >= c.life or not c.p.Parent then
			c.p:Destroy()
			confetti[i] = confetti[#confetti]
			confetti[#confetti] = nil
		else
			local v = c.vel
			v = V3(v.X * drag, math.max(v.Y * drag - 70 * dt, -9), v.Z * drag)
			c.vel = v
			local sway = V3(math.sin(age * 7 + c.ph), 0, math.cos(age * 6 + c.ph)) * 2.2
			c.pos += (v + sway) * dt
			c.rot *= CFrame.Angles(c.spin.X * dt, c.spin.Y * dt, c.spin.Z * dt)
			c.p.CFrame = CFrame.new(c.pos) * c.rot
			if age > c.life - 0.4 then
				c.p.Transparency = math.clamp((age - (c.life - 0.4)) / 0.4, 0, 1)
			end
			i += 1
		end
	end
end

-- EXPLOSION: a white-hot core, a fireball shell, a ground shockwave, fire / smoke / sparks, a flash of light
local function koExplosion(pos)
	local core = part(BALL, V3(2, 2, 2), CFrame.new(pos), C3(255, 245, 200), NEON, 0, 0.7)
	tween(core, 0.2, { Size = V3(14, 14, 14), Color = C3(255, 150, 40) })
	task.delay(0.18, function()
		if core.Parent then
			tween(core, 0.42, { Size = V3(17, 17, 17), Transparency = 1, Color = C3(200, 40, 20) })
		end
	end)
	local shell = part(BALL, V3(3, 3, 3), CFrame.new(pos), C3(255, 90, 30), NEON, 0.35, 0.65)
	tween(shell, 0.55, { Size = V3(22, 22, 22), Transparency = 1 })
	local g, n = groundBelow(pos)
	local ring = part(CYL, V3(0.4, 4, 4), discCF(g + n * 0.2, n), C3(255, 170, 70), NEON, 0.15, 0.6)
	tween(ring, 0.5, { Size = V3(0.15, 34, 34), Transparency = 1 })
	local h, att = host(CFrame.new(pos), 2.6)
	emitter(att, {
		tex = TEX.fire, color = CS({ CSK(0, C3(255, 240, 180)), CSK(0.4, C3(255, 140, 40)), CSK(1, C3(160, 30, 10)) }),
		size = NS({ NSK(0, 3), NSK(1, 7) }), tr = NS({ NSK(0, 0), NSK(0.7, 0.3), NSK(1, 1) }),
		life = NR(0.35, 0.7), speed = NR(18, 38), drag = 5, light = 1,
	}):Emit(36)
	emitter(att, {
		tex = TEX.smoke, color = CS(C3(60, 52, 48)), size = NS({ NSK(0, 4), NSK(1, 11) }), tr = NS({ NSK(0, 0.25), NSK(1, 1) }),
		life = NR(1, 1.6), speed = NR(6, 14), drag = 2, accel = V3(0, 6, 0), lightInf = 1,
	}):Emit(16)
	emitter(att, {
		tex = TEX.spark, color = CS(C3(255, 210, 90)), size = NS({ NSK(0, 0.6), NSK(1, 0) }),
		life = NR(0.5, 1), speed = NR(40, 75), drag = 1.5, accel = V3(0, -70, 0), light = 1,
	}):Emit(45)
	local l = pointLight(h, C3(255, 150, 60), 10, 34)
	tween(l, 0.7, { Brightness = 0 })
	sound(SND.Boom, pos, 1.1, rand(1.05, 1.2), 350)
	shake(pos, 0.012, 80, 0.35)
end

-- LIGHTNING: three strikes of a jagged bolt (with branches) from the sky onto the body, then arcs crackling over it
local function boltPoints(a, b, segs, jag)
	local pts = { a }
	local dir = b - a
	local s1 = dir:Cross(Vector3.xAxis)
	if s1.Magnitude < 1e-3 then
		s1 = dir:Cross(Vector3.zAxis)
	end
	s1 = s1.Unit
	local s2 = dir.Unit:Cross(s1).Unit
	for i = 1, segs - 1 do
		local t = i / segs
		local env = math.sin(t * math.pi)
		table.insert(pts, a + dir * t + (s1 * rand(-1, 1) + s2 * rand(-1, 1)) * jag * env)
	end
	table.insert(pts, b)
	return pts
end

local function drawBolt(into, pts, width, color, glow)
	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local d = p1 - p0
		local len = d.Magnitude
		if len > 0.05 then
			local cf = lookCF((p0 + p1) / 2, d.Unit)
			table.insert(into, part(BLOCK, V3(width, width, len + width * 0.5), cf, color, NEON, 0, 1.5))
			if glow then
				table.insert(into, part(BLOCK, V3(width * 3, width * 3, len + width), cf, glow, NEON, 0.75, 1.5))
			end
		end
	end
end

local function clearParts(list)
	for _, p in ipairs(list) do
		p:Destroy()
	end
	table.clear(list)
end

local BOLT_CORE, BOLT_GLOW = C3(235, 248, 255), C3(90, 160, 255)
local function koLightning(pos)
	local top = pos + V3(rand(-14, 14), rand(70, 95), rand(-14, 14))
	local g, n = groundBelow(pos)
	local h, att = host(CFrame.new(pos), 2.2)
	local l = pointLight(h, C3(150, 200, 255), 0, 45)
	sound(SND.Sizzle, pos, 1, 1.3, 300)
	sound(SND.Boom, pos, 1, rand(1.5, 1.7), 400)
	task.spawn(function()
		local ok, err = pcall(function()
			local bolts = {}
			for strike = 1, 3 do
				clearParts(bolts)
				local pts = boltPoints(top, pos, 12, 7)
				drawBolt(bolts, pts, 0.45, BOLT_CORE, BOLT_GLOW)
				for _ = 1, 2 do
					local from = pts[math.random(3, 8)]
					local to = from + V3(rand(-14, 14), rand(-22, -8), rand(-14, 14))
					drawBolt(bolts, boltPoints(from, to, 5, 3), 0.25, BOLT_CORE, BOLT_GLOW)
				end
				l.Brightness = 14
				if strike == 1 then
					local fl = part(BALL, V3(1, 1, 1), CFrame.new(pos), C3(220, 240, 255), NEON, 0, 0.4)
					tween(fl, 0.3, { Size = V3(11, 11, 11), Transparency = 1 })
					local ring = part(CYL, V3(0.3, 3, 3), discCF(g + n * 0.2, n), C3(120, 190, 255), NEON, 0.1, 0.6)
					tween(ring, 0.5, { Size = V3(0.1, 26, 26), Transparency = 1 })
					emitter(att, {
						tex = TEX.spark, color = CS(C3(255, 255, 255), C3(110, 180, 255)), size = NS({ NSK(0, 0.9), NSK(1, 0) }),
						life = NR(0.35, 0.8), speed = NR(30, 60), drag = 2, accel = V3(0, -40, 0), light = 1,
					}):Emit(45)
					shake(pos, 0.014, 90, 0.35)
				end
				task.wait(strike == 3 and 0.14 or 0.08)
				clearParts(bolts)
				l.Brightness = 2
				task.wait(0.06)
			end
			local arcs = {}
			local t1 = os.clock()
			while os.clock() - t1 < 0.7 do
				clearParts(arcs)
				for _ = 1, 3 do
					local a = pos + randomUnit() * rand(0.5, 2.5)
					drawBolt(arcs, boltPoints(a, a + randomUnit() * rand(2, 4), 4, 0.8), 0.14, BOLT_CORE, nil)
				end
				l.Brightness = rand(1, 4)
				task.wait(0.05)
			end
			clearParts(arcs)
			tween(l, 0.2, { Brightness = 0 })
		end)
		if not ok then
			warn("[PerkFXClient] lightning failed: " .. tostring(err))
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- (2026-11-14, sandbox shop) six more kill effects. Each builds its parts through mkFor(): a part it makes after the shop
-- preview has let go of its WorldModel still lands in that preview, never in the world at the preview's coordinates.
-- Emitters / lights / sounds are skipped in a preview (a ViewportFrame draws none of them).
local function mkFor()
	local sink = previewSink
	return function(shape, size, cf, color, mat, tr, life)
		local p = part(shape, size, cf, color, mat, tr, life)
		if sink and p.Parent ~= sink then
			p.Parent = sink
		end
		return p
	end, sink
end
-- fn(t, dt) every frame for dur seconds (t 0..1), then once more with t = 1
local function frames(dur, fn)
	task.spawn(function()
		local t0 = os.clock()
		local last = t0
		while true do
			local now = os.clock()
			local t = (now - t0) / dur
			if t >= 1 then
				break
			end
			local ok, err = pcall(fn, t, now - last)
			if not ok then
				warn("[PerkFXClient] kill fx step failed: " .. tostring(err))
				return
			end
			last = now
			RunService.RenderStepped:Wait()
		end
		pcall(fn, 1, 0)
	end)
end

-- BLACK HOLE: a void sphere with a spinning accretion disc swallows a ring of debris, then implodes with a pop
local VOID, VIOLET, PINK = C3(8, 4, 16), C3(150, 70, 255), C3(255, 120, 220)
local function koBlackHole(pos)
	local mk, sink = mkFor()
	local core = mk(BALL, V3(0.5, 0.5, 0.5), CFrame.new(pos), VOID, NEON, 0, 1.6)
	tween(core, 0.25, { Size = V3(6, 6, 6) }, Enum.EasingStyle.Back)
	local rim = mk(BALL, V3(0.6, 0.6, 0.6), CFrame.new(pos), VIOLET, NEON, 0.6, 1.6)
	tween(rim, 0.25, { Size = V3(7.4, 7.4, 7.4) }, Enum.EasingStyle.Back)
	local tilt = CFrame.Angles(math.rad(rand(14, 26)), rand(0, TAU), math.rad(rand(-10, 10)))
	local flat = CFrame.new(pos) * tilt * CFrame.Angles(0, 0, math.pi / 2)
	local disc = mk(CYL, V3(0.15, 0.5, 0.5), flat, VIOLET, NEON, 0.25, 1.6)
	local disc2 = mk(CYL, V3(0.18, 0.5, 0.5), flat, PINK, NEON, 0.1, 1.6)
	tween(disc, 0.3, { Size = V3(0.15, 16, 16) })
	tween(disc2, 0.3, { Size = V3(0.18, 9.5, 9.5) })
	local bits = {}
	for i = 1, 16 do
		local sz = rand(0.4, 0.9)
		bits[i] = { p = mk(BLOCK, V3(sz, sz, sz), CFrame.new(pos), (i % 3 == 0) and PINK or C3(230, 225, 255), NEON, 0, 1.6),
			a = rand(0, TAU), r = rand(7, 12), y = rand(-2.5, 2.5), w = rand(5, 9), sz = sz }
	end
	if not sink then
		local h = part(BALL, V3(20, 20, 20), CFrame.new(pos), nil, PLASTIC, 1, 1.6)
		local e = Instance.new("ParticleEmitter")
		e.Texture = TEX.spark
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.Color = CS(VIOLET, C3(255, 255, 255))
		e.Size = NS({ NSK(0, 0.6), NSK(1, 0) })
		e.LightEmission = 1
		e.Lifetime = NR(0.35, 0.5)
		e.Speed = NR(18, 26)
		e.Rate = 70
		e.Parent = h
		task.delay(1, function()
			e.Enabled = false
		end)
		local l = pointLight(h, VIOLET, 6, 30)
		tween(l, 1.3, { Brightness = 1 })
		sound(SND.Whoosh, pos, 1, 0.45, 260)
		shake(pos, 0.004, 60, 1)
	end
	frames(1.1, function(t, dt)
		local spinA = t * 14
		disc.CFrame = flat * CFrame.Angles(spinA, 0, 0)
		disc2.CFrame = flat * CFrame.Angles(-spinA * 1.6, 0, 0)
		local k = 1 - t
		for _, b in ipairs(bits) do
			b.a += b.w * dt * (1 + 3 * t)
			local r = b.r * k * k + 0.3
			local lv = Vector3.new(math.cos(b.a) * r, b.y * k, math.sin(b.a) * r)
			b.p.CFrame = CFrame.new(pos + tilt:VectorToWorldSpace(lv)) * CFrame.Angles(b.a * 2, b.a, 0)
			b.p.Size = V3(1, 1, 1) * math.max(0.1, b.sz * k + 0.1)
		end
		if t >= 1 then
			for _, b in ipairs(bits) do
				b.p:Destroy()
			end
		end
	end)
	task.delay(1.1, function()
		tween(core, 0.12, { Size = V3(0.1, 0.1, 0.1) })
		tween(rim, 0.12, { Size = V3(0.1, 0.1, 0.1), Transparency = 1 })
		tween(disc, 0.15, { Size = V3(0.1, 0.1, 0.1), Transparency = 1 })
		tween(disc2, 0.15, { Size = V3(0.1, 0.1, 0.1), Transparency = 1 })
		task.delay(0.12, function()
			local fl = mk(BALL, V3(1, 1, 1), CFrame.new(pos), C3(245, 235, 255), NEON, 0, 0.5)
			tween(fl, 0.35, { Size = V3(13, 13, 13), Transparency = 1 })
			local g, n = groundBelow(pos)
			local ring = mk(CYL, V3(0.3, 2, 2), discCF(g + n * 0.2, n), VIOLET, NEON, 0.15, 0.6)
			tween(ring, 0.5, { Size = V3(0.1, 28, 28), Transparency = 1 })
			if not sink then
				sound(SND.Boom, pos, 1, 1.5, 320)
				shake(pos, 0.012, 80, 0.3)
			end
		end)
	end)
end

-- FIREWORK: a rocket streaks up off the body and bursts into a two-colour shell of stars, with crackles
local FW_SETS = {
	{ C3(255, 80, 120), C3(255, 220, 90) }, { C3(90, 200, 255), C3(200, 120, 255) },
	{ C3(120, 255, 150), C3(255, 255, 255) }, { C3(255, 160, 60), C3(255, 90, 200) },
}
local function koFirework(pos)
	local mk, sink = mkFor()
	local set = FW_SETS[math.random(#FW_SETS)]
	local top = pos + V3(rand(-4, 4), rand(30, 38), rand(-4, 4))
	local dir = (top - pos).Unit
	local rocket = mk(CYL, V3(1.4, 0.5, 0.5), CFrame.new(pos), set[2], NEON, 0, 1)
	if not sink then
		local a0 = Instance.new("Attachment")
		a0.Position = V3(-0.7, 0, 0.25)
		a0.Parent = rocket
		local a1 = Instance.new("Attachment")
		a1.Position = V3(-0.7, 0, -0.25)
		a1.Parent = rocket
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = 0.35
		tr.Color = CS(set[2], set[1])
		tr.LightEmission = 1
		tr.Transparency = NS(0, 1)
		tr.FaceCamera = true
		tr.Parent = rocket
		emitter(a0, { tex = TEX.flare, rate = 70, color = CS(set[1]), size = NS({ NSK(0, 0.5), NSK(1, 0) }), life = NR(0.2, 0.4),
			speed = NR(2, 6), light = 1, spread = Vector2.new(25, 25), dir = Enum.NormalId.Left })
		sound(SND.Whoosh, pos, 0.9, 1.7, 260)
	end
	frames(0.55, function(t)
		local e = 1 - (1 - t) ^ 2
		local p = pos:Lerp(top, e) + V3(math.sin(t * 20) * 0.4, 0, math.cos(t * 17) * 0.4)
		rocket.CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.pi / 2, 0)
		if t >= 1 then
			rocket:Destroy()
		end
	end)
	task.delay(0.55, function()
		local fl = mk(BALL, V3(1, 1, 1), CFrame.new(top), C3(255, 255, 255), NEON, 0, 0.4)
		tween(fl, 0.25, { Size = V3(8, 8, 8), Transparency = 1 })
		local stars = {}
		for i = 1, 44 do
			stars[i] = { p = mk(BALL, V3(0.7, 0.7, 0.7), CFrame.new(top), (i % 2 == 0) and set[1] or set[2], NEON, 0, 1.6), pos = top,
				vel = randomUnit() * rand(26, 34) }
		end
		frames(1.4, function(t, dt)
			for _, st in ipairs(stars) do
				st.vel = st.vel * math.exp(-2.2 * dt) + V3(0, -14 * dt, 0)
				st.pos += st.vel * dt
				st.p.CFrame = CFrame.new(st.pos)
				st.p.Transparency = math.clamp((t - 0.55) / 0.45, 0, 1)
				st.p.Size = V3(1, 1, 1) * (0.7 * (1 - 0.5 * t))
			end
			if t >= 1 then
				for _, st in ipairs(stars) do
					st.p:Destroy()
				end
			end
		end)
		if not sink then
			local h, att = host(CFrame.new(top), 2.4)
			emitter(att, { tex = TEX.spark, color = CS(set[1], set[2]), size = NS({ NSK(0, 1.2), NSK(1, 0) }), life = NR(0.8, 1.4),
				speed = NR(18, 30), drag = 1.4, accel = V3(0, -10, 0), light = 1 }):Emit(70)
			local l = pointLight(h, set[1], 10, 50)
			tween(l, 1.2, { Brightness = 0 })
			sound(SND.Boom, top, 1, 1.9, 400)
			sound(SND.Sizzle, top, 0.8, 1.4, 300)
			for k = 1, 3 do
				task.delay(0.35 + k * 0.18, function()
					local c = part(BALL, V3(0.5, 0.5, 0.5), CFrame.new(top + randomUnit() * rand(6, 12)), C3(255, 255, 255), NEON, 0, 0.3)
					tween(c, 0.2, { Size = V3(3, 3, 3), Transparency = 1 })
				end)
			end
			shake(top, 0.006, 90, 0.25)
		end
	end)
end

-- FROZEN: frost spreads, ice spikes and a block of ice close over the body, then it all shatters
local ICE, ICE2 = C3(170, 230, 255), C3(225, 248, 255)
local GLASS = Enum.Material.Glass
local function koFrozen(pos)
	local mk, sink = mkFor()
	local g, n = groundBelow(pos)
	local ring = mk(CYL, V3(0.2, 2, 2), discCF(g + n * 0.15, n), ICE, NEON, 0.2, 1.6)
	tween(ring, 0.35, { Size = V3(0.15, 18, 18) })
	task.delay(0.9, function()
		if ring.Parent then
			tween(ring, 0.5, { Transparency = 1 })
		end
	end)
	local block = mk(BLOCK, V3(0.5, 0.5, 0.5), CFrame.new(pos), ICE2, GLASS, 0.45, 1.2)
	tween(block, 0.22, { Size = V3(4, 6.4, 3.2) }, Enum.EasingStyle.Back)
	local spikes = {}
	for i = 1, 10 do
		local a = (i / 10) * TAU + rand(-0.2, 0.2)
		local d = V3(math.cos(a), rand(0.3, 1.1), math.sin(a)).Unit
		local base = pos + V3(0, rand(-2.2, 1.5), 0)
		local len = rand(3, 6)
		local cf = CFrame.lookAt(base, base + d)
		local sp = mk(BLOCK, V3(0.7, 0.7, 0.1), cf, (i % 2 == 0) and ICE or ICE2, GLASS, 0.2, 1.2)
		tween(sp, 0.2, { Size = V3(0.8, 0.8, len), CFrame = cf * CFrame.new(0, 0, -len / 2) }, Enum.EasingStyle.Back)
		spikes[i] = sp
	end
	if not sink then
		sound(SND.Sizzle, pos, 1, 1.8, 260)
		local _, att = host(CFrame.new(pos), 2.2)
		emitter(att, { tex = TEX.spark, color = CS(ICE2, ICE), size = NS({ NSK(0, 0.6), NSK(1, 0) }), life = NR(0.5, 1), speed = NR(4, 10), light = 1,
			drag = 2 }):Emit(30)
	end
	task.delay(0.85, function()
		for _, sp in ipairs(spikes) do
			sp:Destroy()
		end
		block:Destroy()
		local fl = mk(BALL, V3(1, 1, 1), CFrame.new(pos), C3(240, 250, 255), NEON, 0.1, 0.4)
		tween(fl, 0.3, { Size = V3(10, 10, 10), Transparency = 1 })
		local shards = {}
		for i = 1, 26 do
			local d = (randomUnit() + V3(0, 0.6, 0)).Unit
			shards[i] = { p = mk(BLOCK, V3(rand(0.3, 0.7), rand(0.3, 0.9), rand(0.1, 0.3)), CFrame.new(pos), (i % 2 == 0) and ICE or ICE2, GLASS, 0.15, 1.4),
				pos = pos + randomUnit() * rand(0, 1.5), vel = d * rand(18, 34), rot = CFrame.Angles(rand(0, TAU), rand(0, TAU), rand(0, TAU)),
				spin = V3(rand(-14, 14), rand(-14, 14), rand(-14, 14)) }
		end
		frames(1.1, function(t, dt)
			for _, sh in ipairs(shards) do
				sh.vel = sh.vel * math.exp(-1.2 * dt) + V3(0, -70 * dt, 0)
				sh.pos += sh.vel * dt
				sh.rot *= CFrame.Angles(sh.spin.X * dt, sh.spin.Y * dt, sh.spin.Z * dt)
				sh.p.CFrame = CFrame.new(sh.pos) * sh.rot
				sh.p.Transparency = 0.15 + 0.85 * math.clamp((t - 0.5) / 0.5, 0, 1)
			end
			if t >= 1 then
				for _, sh in ipairs(shards) do
					sh.p:Destroy()
				end
			end
		end)
		if not sink then
			sound(SND.Boom, pos, 0.9, 2.1, 300)
			local _, att = host(CFrame.new(pos), 2)
			emitter(att, { tex = TEX.spark, color = CS(C3(255, 255, 255), ICE), size = NS({ NSK(0, 0.9), NSK(1, 0) }), life = NR(0.6, 1.1),
				speed = NR(20, 40), drag = 2, accel = V3(0, -30, 0), light = 1 }):Emit(50)
			shake(pos, 0.01, 70, 0.3)
		end
	end)
end

-- SOUL: a ghostly wisp with a golden halo leaves the body and drifts up out of sight
local function koSoul(pos)
	local mk, sink = mkFor()
	local g, n = groundBelow(pos)
	local glow = mk(CYL, V3(0.15, 1, 1), discCF(g + n * 0.12, n), C3(235, 245, 255), NEON, 0.35, 2.4)
	tween(glow, 0.4, { Size = V3(0.12, 9, 9) })
	task.delay(1.6, function()
		if glow.Parent then
			tween(glow, 0.6, { Transparency = 1 })
		end
	end)
	local head = mk(BALL, V3(1.6, 1.6, 1.6), CFrame.new(pos), C3(240, 248, 255), NEON, 0.35, 2.6)
	local body = mk(BALL, V3(1.8, 2.8, 1.4), CFrame.new(pos), C3(220, 235, 255), NEON, 0.55, 2.6)
	local tail = mk(BALL, V3(1, 2, 1), CFrame.new(pos), C3(200, 220, 255), NEON, 0.75, 2.6)
	local seg = {}
	for i = 1, 12 do
		seg[i] = mk(BLOCK, V3(0.5, 0.18, 0.25), CFrame.new(pos), C3(255, 225, 120), NEON, 0, 2.6)
	end
	local trailHost
	if not sink then
		trailHost = part(BLOCK, V3(0.2, 0.2, 0.2), CFrame.new(pos), nil, PLASTIC, 1, 2.6)
		local a = Instance.new("Attachment")
		a.Parent = trailHost
		emitter(a, { tex = TEX.spark, rate = 30, color = CS(C3(255, 255, 255), C3(180, 210, 255)), size = NS({ NSK(0, 0.6), NSK(1, 0) }),
			life = NR(0.6, 1), speed = NR(0.5, 2), light = 1 })
		sound(SND.Whoosh, pos, 0.7, 0.6, 220)
	end
	frames(2.3, function(t)
		local e = t * t * (3 - 2 * t)
		local p = pos + V3(math.sin(t * 7) * 1.6, 2 + e * 26, math.cos(t * 6) * 1.2)
		local lean = CFrame.Angles(math.sin(t * 7) * 0.25, 0, math.cos(t * 6) * 0.2)
		local c = CFrame.new(p) * lean
		head.CFrame = c
		body.CFrame = c * CFrame.new(0, -1.8, 0)
		tail.CFrame = c * CFrame.new(math.sin(t * 12) * 0.5, -3.6, 0)
		local hc = c * CFrame.new(0, 1.5, 0)
		local fade = math.clamp((t - 0.6) / 0.4, 0, 1)
		for i, sg in ipairs(seg) do
			local a = i / 12 * TAU + t * 4
			sg.CFrame = hc * CFrame.new(math.cos(a) * 0.95, 0, math.sin(a) * 0.95) * CFrame.Angles(0, -a, 0)
			sg.Transparency = fade
		end
		head.Transparency = 0.35 + 0.65 * fade
		body.Transparency = 0.55 + 0.45 * fade
		tail.Transparency = 0.75 + 0.25 * fade
		if trailHost then
			trailHost.CFrame = CFrame.new(p - V3(0, 2.5, 0))
		end
		if t >= 1 then
			head:Destroy()
			body:Destroy()
			tail:Destroy()
			for _, sg in ipairs(seg) do
				sg:Destroy()
			end
		end
	end)
	for k = 0, 2 do
		task.delay(k * 0.25, function()
			local r = mk(CYL, V3(0.1, 2, 2), discCF(g + n * 0.2, n), C3(220, 235, 255), NEON, 0.3, 1.3)
			tween(r, 1.2, { Size = V3(0.1, 7, 7), Transparency = 1, CFrame = discCF(g + n * 14, n) })
		end)
	end
end

-- PIXELATE: a scan line sweeps the body and it glitches apart into cubes that float off, bottom first
local PIX = { C3(255, 255, 255), C3(220, 220, 228), C3(190, 190, 200), C3(80, 240, 255), C3(255, 70, 200), C3(140, 255, 120) }
local function koPixel(pos)
	local mk, sink = mkFor()
	local cubes = {}
	for i = 1, 46 do
		local o = V3(rand(-1.1, 1.1), rand(-2.6, 2.4), rand(-0.6, 0.6))
		local plain = i <= 30
		local sz = rand(0.45, 0.85)
		cubes[i] = { p = mk(BLOCK, V3(sz, sz, sz), CFrame.new(pos + o), plain and PIX[math.random(1, 3)] or PIX[math.random(4, 6)], plain and PLASTIC or NEON, 0, 2),
			o = o, sz = sz, delay = (o.Y + 2.6) / 5 * 0.55 + rand(0, 0.12), vel = V3(rand(-3, 3), rand(8, 16), rand(-3, 3)) + V3(o.X, 0, o.Z) * 3 }
	end
	local scan = mk(BLOCK, V3(3.4, 0.15, 2), CFrame.new(pos - V3(0, 2.8, 0)), C3(80, 240, 255), NEON, 0.2, 1)
	tween(scan, 0.6, { CFrame = CFrame.new(pos + V3(0, 2.8, 0)) })
	task.delay(0.6, function()
		if scan.Parent then
			tween(scan, 0.2, { Transparency = 1 })
		end
	end)
	if not sink then
		sound(SND.Sizzle, pos, 1, 2.4, 240)
		sound(SND.Boing, pos, 0.5, 2.2, 200)
	end
	frames(1.7, function(t)
		local T = t * 1.7
		for _, c in ipairs(cubes) do
			local age = T - c.delay
			if age < 0 then
				c.p.CFrame = CFrame.new(pos + c.o + V3(rand(-0.12, 0.12), 0, rand(-0.12, 0.12)))
			else
				local p = pos + c.o + c.vel * age + V3(0, 6 * age * age, 0)
				c.p.CFrame = CFrame.new(p) * CFrame.Angles(age * 3, age * 4, 0)
				local k = math.clamp(1 - age / 0.9, 0, 1)
				c.p.Size = V3(1, 1, 1) * math.max(0.05, c.sz * k)
				c.p.Transparency = 1 - k
			end
		end
		if t >= 1 then
			for _, c in ipairs(cubes) do
				c.p:Destroy()
			end
		end
	end)
end

-- MINI NUKE: a flash, a ground shockwave and a little mushroom cloud that rises, darkens and fades
local function koMiniNuke(pos)
	local mk, sink = mkFor()
	local g, n = groundBelow(pos)
	local base = g
	local fl = mk(BALL, V3(1, 1, 1), CFrame.new(pos), C3(255, 255, 235), NEON, 0, 0.5)
	tween(fl, 0.18, { Size = V3(12, 12, 12) })
	task.delay(0.18, function()
		if fl.Parent then
			tween(fl, 0.3, { Transparency = 1 })
		end
	end)
	local ring = mk(CYL, V3(0.4, 3, 3), discCF(g + n * 0.2, n), C3(255, 200, 120), NEON, 0.1, 0.7)
	tween(ring, 0.6, { Size = V3(0.12, 40, 40), Transparency = 1 })
	local dust = mk(CYL, V3(1.2, 4, 4), discCF(g + n * 0.6, n), C3(150, 130, 115), PLASTIC, 0.3, 1.8)
	tween(dust, 1.6, { Size = V3(0.4, 24, 24), Transparency = 1 }, Enum.EasingStyle.Sine)
	local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
	local stem = mk(CYL, V3(0.5, 2.2, 2.2), CFrame.new(base) * UPRIGHT, C3(255, 140, 50), NEON, 0.1, 2.4)
	local cap = mk(BALL, V3(3, 3, 3), CFrame.new(base + V3(0, 2, 0)), C3(255, 160, 60), NEON, 0, 2.4)
	local puffs = {}
	for i = 1, 8 do
		puffs[i] = mk(BALL, V3(2.5, 2.5, 2.5), CFrame.new(base), C3(255, 120, 40), NEON, 0.1, 2.4)
	end
	if not sink then
		sound(SND.Boom, pos, 1.6, 0.6, 500)
		shake(pos, 0.02, 120, 0.45)
		local h, att = host(CFrame.new(base + V3(0, 1, 0)), 2.6)
		emitter(att, { tex = TEX.smoke, color = CS(C3(90, 80, 75)), size = NS({ NSK(0, 3), NSK(1, 8) }), tr = NS({ NSK(0, 0.3), NSK(1, 1) }),
			life = NR(1.2, 1.8), speed = NR(4, 10), drag = 2, accel = V3(0, 4, 0), lightInf = 1 }):Emit(18)
		local l = pointLight(h, C3(255, 150, 60), 12, 40)
		tween(l, 1.5, { Brightness = 0 })
	end
	frames(2.2, function(t)
		local rise = 1 - (1 - math.min(t / 0.55, 1)) ^ 3
		local H = 2 + 12 * rise
		local col = C3(255, 150, 60):Lerp(C3(95, 88, 84), math.clamp((t - 0.25) / 0.5, 0, 1))
		local w = 2.2 - 0.6 * rise
		stem.Size = V3(H, w, w)
		stem.CFrame = CFrame.new(base + V3(0, H / 2, 0)) * UPRIGHT
		stem.Color = col
		local top = base + V3(0, H, 0)
		local cr = 1.5 + 3 * rise
		cap.CFrame = CFrame.new(top + V3(0, 0.6, 0))
		cap.Size = V3(1, 0.75, 1) * (2.4 + 3.2 * rise)
		cap.Color = col
		local fade = math.clamp((t - 0.7) / 0.3, 0, 1)
		for i, pf in ipairs(puffs) do
			local a = i / 8 * TAU + t * 2.5
			pf.CFrame = CFrame.new(top + V3(math.cos(a) * cr, math.sin(t * 9 + i) * 0.3, math.sin(a) * cr))
			pf.Size = V3(1, 1, 1) * (1.6 + 2 * rise)
			pf.Color = col
			pf.Transparency = 0.1 + 0.9 * fade
		end
		stem.Transparency = 0.1 + 0.9 * fade
		cap.Transparency = fade
		if t >= 1 then
			stem:Destroy()
			cap:Destroy()
			for _, pf in ipairs(puffs) do
				pf:Destroy()
			end
		end
	end)
end

local KO_FN = { Confetti = koConfetti, Explosion = koExplosion, Lightning = koLightning, BlackHole = koBlackHole, Firework = koFirework,
	Frozen = koFrozen, Soul = koSoul, Pixel = koPixel, MiniNuke = koMiniNuke }
local liveKO = 0
local function playKO(e)
	if type(e) ~= "table" then
		return
	end
	local fn, pos = KO_FN[e.s], e.p
	if not fn or typeof(pos) ~= "Vector3" or pos ~= pos then
		return
	end
	if liveKO >= KO_MAX or (camPos() - pos).Magnitude > KO_RANGE or previewSink then
		return -- (a KO in the world during a shop preview is skipped, or its parts would land in the preview)
	end
	liveKO += 1
	task.delay(1.6, function()
		liveKO -= 1
	end)
	local ok, err = pcall(fn, pos)
	if not ok then
		warn("[PerkFXClient] KO fx failed: " .. tostring(err))
	end
	pcall(koText, pos, e.s)
end

---------------------------------------------------------------------------------------------------
-- meteors
local meteors = {} -- [id] = rec

local function meteorLaunch(m)
	if type(m) ~= "table" or typeof(m.a) ~= "Vector3" or typeof(m.b) ~= "Vector3" then
		return
	end
	local t0, d = tonumber(m.t0), tonumber(m.d)
	if not t0 or not d or d <= 0 or meteors[m.id] then
		return
	end
	local span = m.b - m.a
	if span.Magnitude < 1 then
		return
	end
	local big = m.big == true
	local size = math.clamp(tonumber(m.s) or 7, 2, 30)
	local radius = math.clamp(tonumber(m.r) or 16, 4, 60)
	local dir = span.Unit
	local n = unitOr(m.n, UP)
	local cf = lookCF(m.a, dir)
	local rec = { id = m.id, a = m.a, b = m.b, n = n, t0 = t0, d = d, dir = dir, size = size, radius = radius, big = big }
	rec.rock = part(BALL, V3(size, size, size), cf, C3(70, 30, 18), Enum.Material.CrackedLava, 0, d + 6)
	rec.glow = part(BALL, V3(size, size, size) * 1.3, cf, C3(255, 120, 30), NEON, 0.45, d + 6)
	rec.halo = part(BALL, V3(size, size, size) * 1.9, cf, C3(255, 200, 110), NEON, 0.82, d + 6)
	-- trails ride the glow shell (it never rolls, so their width stays put)
	local function att(x)
		local a = Instance.new("Attachment")
		a.Position = V3(x, 0, 0)
		a.Parent = rec.glow
		return a
	end
	local fire = Instance.new("Trail")
	fire.Attachment0, fire.Attachment1 = att(-size * 0.55), att(size * 0.55)
	fire.Lifetime = big and 0.65 or 0.45
	fire.FaceCamera = true
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.MinLength = 0.1
	fire.Color = CS({ CSK(0, C3(255, 250, 220)), CSK(0.25, C3(255, 200, 70)), CSK(0.6, C3(255, 100, 30)), CSK(1, C3(150, 25, 10)) })
	fire.Transparency = NS({ NSK(0, 0.05), NSK(0.6, 0.4), NSK(1, 1) })
	fire.WidthScale = NS({ NSK(0, 1), NSK(1, 0.15) })
	fire.Parent = rec.glow
	local smoke = Instance.new("Trail")
	smoke.Attachment0, smoke.Attachment1 = att(-size * 1.3), att(size * 1.3)
	smoke.Lifetime = big and 2 or 1.4
	smoke.FaceCamera = true
	smoke.LightEmission = 0
	smoke.LightInfluence = 1
	smoke.MinLength = 0.1
	smoke.Color = CS(C3(80, 66, 60), C3(36, 34, 34))
	smoke.Transparency = NS({ NSK(0, 0.45), NSK(1, 1) })
	smoke.WidthScale = NS({ NSK(0, 0.35), NSK(1, 1) })
	smoke.Parent = rec.glow
	rec.trails = { fire, smoke }
	local center = Instance.new("Attachment")
	center.Parent = rec.glow
	rec.emitters = {
		emitter(center, {
			tex = TEX.fire, rate = big and 140 or 90, dir = Enum.NormalId.Back, spread = Vector2.new(25, 25),
			color = CS({ CSK(0, C3(255, 235, 160)), CSK(0.5, C3(255, 120, 30)), CSK(1, C3(140, 25, 10)) }),
			size = NS({ NSK(0, size * 0.9), NSK(1, size * 1.5) }), tr = NS({ NSK(0, 0.1), NSK(1, 1) }),
			life = NR(0.3, 0.6), speed = NR(4, 10), light = 1,
		}),
		emitter(center, {
			tex = TEX.smoke, rate = big and 40 or 26, dir = Enum.NormalId.Back, spread = Vector2.new(20, 20),
			color = CS(C3(70, 60, 56), C3(30, 30, 30)), size = NS({ NSK(0, size * 0.8), NSK(1, size * 2.2) }),
			tr = NS({ NSK(0, 0.35), NSK(1, 1) }), life = NR(1.2, 2), speed = NR(2, 5), lightInf = 1,
		}),
		emitter(center, {
			tex = TEX.spark, rate = big and 70 or 40, dir = Enum.NormalId.Back, spread = Vector2.new(60, 60),
			color = CS(C3(255, 220, 120), C3(255, 110, 40)), size = NS({ NSK(0, 0.7), NSK(1, 0) }),
			life = NR(0.6, 1.1), speed = NR(10, 25), accel = V3(0, -40, 0), light = 1,
		}),
	}
	rec.light = pointLight(rec.glow, C3(255, 140, 60), big and 6 or 4, size * 6)
	sound(SND.Whoosh, nil, big and 2 or 1.4, big and 0.5 or rand(0.65, 0.8), 450, rec.glow)
	-- the telegraph on the ground: a pulsing red zone and a fill that grows to it as the meteor lands
	local dcf = discCF(m.b + n * 0.15, n)
	rec.zone = part(CYL, V3(0.12, radius * 2, radius * 2), dcf, C3(255, 50, 30), NEON, 0.75, d + 6)
	rec.fill = part(CYL, V3(0.14, 0.2, 0.2), dcf * CFrame.new(0.02, 0, 0), C3(255, 150, 50), NEON, 0.5, d + 6)
	meteors[m.id] = rec
end

local function meteorImpact(r)
	local pos, n, R, big = r.b, r.n, r.radius, r.big
	for _, t in ipairs(r.trails) do
		t.Enabled = false -- the drawn trail fades out on its own lifetime
	end
	for _, e in ipairs(r.emitters) do
		e.Enabled = false
	end
	r.light.Enabled = false
	r.glow.Transparency = 1
	Debris:AddItem(r.glow, 2.4)
	r.rock:Destroy()
	r.halo:Destroy()
	r.zone:Destroy()
	r.fill:Destroy()

	local flash = part(BALL, V3(1, 1, 1) * R * 0.4, CFrame.new(pos), C3(255, 250, 225), NEON, 0, 0.8)
	tween(flash, 0.16, { Size = V3(1, 1, 1) * R * 2.2 })
	task.delay(0.14, function()
		if flash.Parent then
			tween(flash, 0.5, { Transparency = 1, Color = C3(255, 120, 40) })
		end
	end)
	local fb = part(BALL, V3(1, 1, 1) * R * 0.5, CFrame.new(pos + n * R * 0.2), C3(255, 120, 30), NEON, 0.15, 0.85)
	tween(fb, 0.75, { Size = V3(1, 1, 1) * R * 1.7, Transparency = 1, Color = C3(170, 30, 10) })
	local ring = part(CYL, V3(0.5, R * 0.6, R * 0.6), discCF(pos + n * 0.4, n), C3(255, 190, 100), NEON, 0.2, 0.7)
	tween(ring, 0.6, { Size = V3(0.2, R * 5, R * 5), Transparency = 1 })
	local dust = part(CYL, V3(1.5, R, R), discCF(pos + n * 0.8, n), C3(120, 105, 95), PLASTIC, 0.35, 1.4)
	tween(dust, 1.3, { Size = V3(0.5, R * 4, R * 4), Transparency = 1 }, Enum.EasingStyle.Sine)
	local pillar = part(CYL, V3(R * 4, R * 0.7, R * 0.7), CFrame.fromMatrix(pos + n * R * 2, n, tangentOf(n)), C3(255, 220, 150), NEON, 0.1, 0.5)
	tween(pillar, 0.45, { Size = V3(R * 5, 0.1, 0.1), Transparency = 1 })

	local h, att = host(upCF(pos + n * 0.5, n), 5.5)
	local sz = math.min(R, 30)
	emitter(att, {
		tex = TEX.fire, spread = Vector2.new(70, 70),
		color = CS({ CSK(0, C3(255, 240, 180)), CSK(0.35, C3(255, 140, 40)), CSK(1, C3(150, 25, 10)) }),
		size = NS({ NSK(0, sz * 0.35), NSK(1, sz * 0.8) }), tr = NS({ NSK(0, 0), NSK(0.7, 0.3), NSK(1, 1) }),
		life = NR(0.5, 0.9), speed = NR(R * 1.6, R * 3.4), drag = 4, light = 1,
	}):Emit(big and 70 or 45)
	emitter(att, {
		tex = TEX.smoke, spread = Vector2.new(60, 60), color = CS(C3(70, 62, 58), C3(40, 38, 38)),
		size = NS({ NSK(0, sz * 0.5), NSK(1, sz * 1.4) }), tr = NS({ NSK(0, 0.2), NSK(1, 1) }),
		life = NR(2.5, 4), speed = NR(R * 0.4, R * 0.9), drag = 1.2, accel = V3(0, 5, 0), lightInf = 1,
	}):Emit(big and 30 or 18)
	emitter(att, {
		tex = TEX.flare, spread = Vector2.new(75, 75), color = CS(C3(255, 230, 140), C3(255, 90, 30)),
		size = NS({ NSK(0, 0.9), NSK(1, 0) }), life = NR(1, 1.8), speed = NR(50, 110), drag = 0.6,
		accel = V3(0, -90, 0), light = 1,
	}):Emit(big and 90 or 55)
	local burn = emitter(att, {
		tex = TEX.fire, rate = big and 45 or 28, spread = Vector2.new(30, 30),
		color = CS(C3(255, 200, 90), C3(200, 50, 15)), size = NS({ NSK(0, sz * 0.25), NSK(1, sz * 0.05) }),
		tr = NS({ NSK(0, 0.2), NSK(1, 1) }), life = NR(0.6, 1.1), speed = NR(3, 7), accel = V3(0, 4, 0), light = 1,
	})
	task.delay(2.6, function()
		if burn.Parent then
			burn.Enabled = false
		end
	end)
	local l = pointLight(h, C3(255, 150, 60), big and 16 or 11, R * 3.5)
	tween(l, 1.6, { Brightness = 0 })
	sound(SND.Boom, pos, big and 2.5 or 1.7, big and rand(0.55, 0.65) or rand(0.75, 0.95), big and 900 or 650)
	shake(pos, big and 0.03 or 0.018, big and 260 or 170, big and 0.7 or 0.45)
end

local function dropMeteor(r)
	for _, k in ipairs({ "rock", "glow", "halo", "zone", "fill" }) do
		if r[k] then
			r[k]:Destroy()
		end
	end
end

local function stepMeteors(now)
	for id, r in pairs(meteors) do
		local ok, err = pcall(function()
			local alpha = (now - r.t0) / r.d
			if alpha >= 1 then
				meteors[id] = nil
				meteorImpact(r)
				return
			end
			alpha = math.max(alpha, 0)
			local cf = lookCF(r.a:Lerp(r.b, alpha), r.dir)
			r.glow.CFrame = cf
			r.halo.CFrame = cf
			r.rock.CFrame = cf * CFrame.Angles(now * 3.1, now * 2.3, 0)
			local s = math.max(r.radius * 2 * alpha, 0.2)
			r.fill.Size = V3(0.14, s, s)
			r.zone.Transparency = 0.55 + 0.25 * math.abs(math.sin(now * (6 + 10 * alpha)))
		end)
		if not ok then
			meteors[id] = nil
			pcall(dropMeteor, r)
			warn("[PerkFXClient] meteor failed: " .. tostring(err))
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the sky while a shower runs (a ColorCorrection of our own; nothing else in Lighting is touched)
local tint, tintOn = nil, false
local function setTint(on)
	if on == tintOn then
		return
	end
	tintOn = on
	if on then
		if not tint or not tint.Parent then
			tint = Instance.new("ColorCorrectionEffect")
			tint.Name = "PerkMeteorTint"
			tint.Parent = Lighting
		end
		tween(tint, 1.5, { TintColor = C3(255, 212, 186), Contrast = 0.12, Saturation = 0.15, Brightness = -0.02 })
	elseif tint then
		local t = tint
		local tw = tween(t, 2, { TintColor = C3(255, 255, 255), Contrast = 0, Saturation = 0, Brightness = 0 })
		tw.Completed:Connect(function()
			if not tintOn and t.Parent then
				t:Destroy()
				if tint == t then
					tint = nil
				end
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- being knocked by a meteor (this client owns its body): a tumble, no damage
local tumbleUntil, tumbleMine = 0, false
local function knock(vel, ragTime)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or typeof(vel) ~= "Vector3" or vel ~= vel then
		return
	end
	if vel.Magnitude > 140 then
		vel = vel.Unit * 140
	end
	local rag = math.clamp(tonumber(ragTime) or 1, 0.3, 2.5)
	if char:GetAttribute("Guardian") then
		vel *= 0.3 -- the Tempest guardian holds its caster: a shove, no tumble out of its chest
		rag = 0
	end
	if rag > 0 then
		if not hum.PlatformStand then
			hum.PlatformStand = true
			tumbleMine = true
		end
		tumbleUntil = math.max(tumbleUntil, os.clock() + rag)
	end
	local done = {}
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and not p.Anchored then
			local root = p.AssemblyRootPart
			if root and not root.Anchored and not done[root] then
				done[root] = true
				root:ApplyImpulse((vel - root.AssemblyLinearVelocity * 0.7) * root.AssemblyMass)
			end
		end
	end
end
player.CharacterAdded:Connect(function()
	tumbleUntil, tumbleMine = 0, false
end)

---------------------------------------------------------------------------------------------------
-- banner
local gui = Instance.new("ScreenGui")
gui.Name = "PerkBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function showBanner(data)
	local color = typeof(data.color) == "Color3" and data.color or C3(255, 120, 40)
	local accent = typeof(data.accent) == "Color3" and data.accent or C3(255, 220, 90)
	local hold = math.clamp(tonumber(data.time) or 4.5, 1.5, 10)
	local fade = {}

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.24)
	frame.Size = UDim2.new(0.92, 0, 0, 96)
	frame.BackgroundColor3 = C3(255, 255, 255)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Rotation = -2
	frame.Parent = gui
	table.insert(fade, { frame, "BackgroundTransparency" })
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(840, 96)
	lim.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local grad = Instance.new("UIGradient")
	grad.Color = CS({ CSK(0, C3(34, 6, 6)), CSK(0.5, color:Lerp(C3(0, 0, 0), 0.4)), CSK(1, C3(34, 6, 6)) })
	grad.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	table.insert(fade, { stroke, "Transparency" })

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.Size = UDim2.new(1, -28, 0, 52)
	title.Font = Enum.Font.GothamBlack
	title.Text = data.title
	title.TextScaled = true
	title.TextColor3 = C3(255, 255, 255)
	title.Parent = frame
	local tmax = Instance.new("UITextSizeConstraint")
	tmax.MaxTextSize = 44
	tmax.Parent = title
	local tgrad = Instance.new("UIGradient")
	tgrad.Rotation = 90
	tgrad.Color = CS({ CSK(0, C3(255, 252, 230)), CSK(0.5, accent), CSK(1, color) })
	tgrad.Parent = title
	local tstroke = Instance.new("UIStroke")
	tstroke.Color = C3(20, 4, 4)
	tstroke.Thickness = 2.5
	tstroke.Parent = title
	table.insert(fade, { title, "TextTransparency" })
	table.insert(fade, { tstroke, "Transparency" })

	if data.sub ~= "" then
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.AnchorPoint = Vector2.new(0.5, 0)
		sub.Position = UDim2.new(0.5, 0, 0, 62)
		sub.Size = UDim2.new(1, -40, 0, 24)
		sub.Font = Enum.Font.GothamBold
		sub.Text = data.sub
		sub.TextScaled = true
		sub.TextColor3 = C3(255, 236, 220)
		sub.Parent = frame
		local smax = Instance.new("UITextSizeConstraint")
		smax.MaxTextSize = 22
		smax.Parent = sub
		table.insert(fade, { sub, "TextTransparency" })
	end

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = C3(255, 255, 255)
	flash.BackgroundTransparency = 0
	flash.BorderSizePixel = 0
	flash.ZIndex = 5
	flash.Parent = frame
	corner:Clone().Parent = flash
	tween(flash, 0.35, { BackgroundTransparency = 1 })

	local scale = Instance.new("UIScale")
	scale.Scale = 1.7
	scale.Parent = frame
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	if data.kind == "Meteor" then
		local s = Instance.new("Sound")
		s.SoundId = SND.Boom
		s.Volume = 0.8
		s.PlaybackSpeed = 0.45
		s.Parent = gui
		s:Play()
		Debris:AddItem(s, 6)
	end
	task.wait(0.35 + hold)
	for _, f in ipairs(fade) do
		if f[1].Parent then
			tween(f[1], 0.4, { [f[2]] = 1 })
		end
	end
	tween(frame, 0.4, { Position = UDim2.fromScale(0.5, 0.16) })
	task.wait(0.42)
	frame:Destroy()
end

local bannerQueue, bannerBusy = {}, false
local function queueBanner(data)
	if type(data) == "string" then
		data = { title = data }
	end
	if type(data) ~= "table" or type(data.title) ~= "string" or data.title == "" then
		return
	end
	data.title = string.sub(data.title, 1, 90)
	data.sub = type(data.sub) == "string" and string.sub(data.sub, 1, 120) or ""
	if #bannerQueue >= 4 then
		return
	end
	table.insert(bannerQueue, data)
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local d = table.remove(bannerQueue, 1)
			local ok, err = pcall(showBanner, d)
			if not ok then
				warn("[PerkFXClient] banner failed: " .. tostring(err))
			end
		end
		bannerBusy = false
	end)
end

---------------------------------------------------------------------------------------------------
-- wiring
PerkFX.OnClientEvent:Connect(function(kind, a, b)
	if kind == "KO" then
		if type(a) == "table" then
			for i, e in ipairs(a) do
				if i > 24 then
					break
				end
				playKO(e)
			end
		end
	elseif kind == "Meteor" then
		local ok, err = pcall(meteorLaunch, a)
		if not ok then
			warn("[PerkFXClient] meteor launch failed: " .. tostring(err))
		end
	elseif kind == "Knock" then
		local ok, err = pcall(knock, a, b)
		if not ok then
			warn("[PerkFXClient] knock failed: " .. tostring(err))
		end
	end
end)

Announce.OnClientEvent:Connect(queueBanner)

-- (2026-11-07) the shop's KO preview: script.KOPreview:Invoke(style, worldModel, pos) plays that KO effect inside the
-- given WorldModel (a ViewportFrame's) at pos, for ~1.8 s. Parts render there; particles / lights don't (Roblox draws
-- neither in a ViewportFrame), so the preview is the effect's shapes and colours. Returns true when it started.
do
	local bf = script:FindFirstChild("KOPreview") or Instance.new("BindableFunction")
	bf.Name = "KOPreview"
	bf.Archivable = false
	local token = 0
	bf.OnInvoke = function(style, sink, pos)
		local fn = KO_FN[style]
		if not fn or typeof(sink) ~= "Instance" or typeof(pos) ~= "Vector3" then
			return false
		end
		token += 1
		local mine = token
		previewSink = sink
		local ok, err = pcall(fn, pos)
		if not ok then
			warn("[PerkFXClient] KO preview failed: " .. tostring(err))
		end
		-- the lightning keeps drawing for ~1.5 s from its own thread: hold the sink until it is done
		task.delay(1.8, function()
			if token == mine then
				previewSink = nil
			end
		end)
		return ok
	end
	bf.Parent = script
end

local warned = false
RunService.RenderStepped:Connect(function(dt)
	local ok, err = pcall(function()
		stepConfetti(math.min(dt, 0.1), os.clock())
		stepMeteors(workspace:GetServerTimeNow())
	end)
	if not ok and not warned then
		warned = true
		warn("[PerkFXClient] step failed: " .. tostring(err))
	end
end)

RunService.Heartbeat:Connect(function()
	if tumbleUntil > 0 and os.clock() >= tumbleUntil then
		tumbleUntil = 0
		if tumbleMine then
			tumbleMine = false
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.PlatformStand and hum.Health > 0 then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
	local untilT = PerkFX:GetAttribute("MeteorUntil")
	setTint(type(untilT) == "number" and workspace:GetServerTimeNow() < untilT)
end)
