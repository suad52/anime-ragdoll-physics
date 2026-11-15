--!nocheck
-- FxLib: client-only visual builders for the Vulpine kit. Everything is anchored, non-colliding and parented to a
-- folder the caller owns. Colours/sizes come from Config, so re-skinning never touches this file.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FxLib = {}

FxLib.Tex = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	flare = "rbxasset://textures/particles/fire_sparks_main.dds",
}

-- sound ids: borrow the game's existing set when present (swap these for your own)
FxLib.Sounds = {}
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared", 5).Client.PurpleVFX)
	end)
	if ok and mod and mod.Sounds then
		FxLib.Sounds = { Charge = mod.Sounds.Blue, Launch = mod.Sounds.Launch, Impact = mod.Sounds.HitFinal, Blast = mod.Sounds.Red, Hum = mod.Sounds.Chant, Rise = mod.Sounds.Birth, Step = mod.Sounds.Hit }
	end
end

function FxLib.part(name, shape, material, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one
	p.Parent = parent
	return p
end

function FxLib.emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

function FxLib.tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function FxLib.anchor(parent, pos, life)
	local p = FxLib.part("FxAnchor", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), parent)
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	Debris:AddItem(p, life or 4)
	return p
end

function FxLib.sound(id, parent, pos, volume, speed)
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	s.Parent = FxLib.anchor(parent, pos, 8)
	s:Play()
	return s
end

function FxLib.flash(parent, pos, radius, color, duration)
	duration = duration or 0.35
	local b = FxLib.part("Flash", Enum.PartType.Ball, Enum.Material.ForceField, color, parent)
	b.Size = Vector3.one * radius * 0.4
	b.CFrame = CFrame.new(pos)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = 8
	l.Range = math.min(radius * 4, 60)
	l.Shadows = false
	l.Parent = b
	FxLib.tween(b, duration, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	FxLib.tween(l, duration, { Brightness = 0 }, Enum.EasingStyle.Quart)
	Debris:AddItem(b, duration + 0.1)
end

-- an expanding ring; `normal` is the axis the ring faces
function FxLib.shockwave(parent, pos, normal, fromD, toD, color, duration)
	duration = duration or 0.45
	local disc = FxLib.part("Shockwave", Enum.PartType.Cylinder, Enum.Material.ForceField, color, parent)
	local up = math.abs(normal.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	disc.CFrame = CFrame.fromMatrix(pos, normal.Unit, normal.Unit:Cross(up).Unit)
	disc.Size = Vector3.new(0.35, fromD, fromD)
	FxLib.tween(disc, duration, { Size = Vector3.new(0.15, toD, toD), Transparency = 1 }, Enum.EasingStyle.Quint)
	Debris:AddItem(disc, duration + 0.1)
end

function FxLib.burst(parent, pos, color, count, size, speed)
	local e = FxLib.emitter(FxLib.anchor(parent, pos, 2), {
		Texture = FxLib.Tex.flare, Color = ColorSequence.new(color), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(size, 0), Drag = 4,
	})
	e:Emit(count)
end

function FxLib.dust(parent, pos, size, count)
	local e = FxLib.emitter(FxLib.anchor(parent, pos, 4), {
		Texture = FxLib.Tex.smoke, Color = ColorSequence.new(Color3.fromRGB(150, 135, 120)), LightEmission = 0, LightInfluence = 1,
		Rate = 0, Lifetime = NumberRange.new(0.9, 1.6), Speed = NumberRange.new(size * 0.6, size * 1.4),
		SpreadAngle = Vector2.new(80, 80), Size = NumberSequence.new(size * 0.5, size * 1.4),
		Transparency = NumberSequence.new(0.4, 1), Rotation = NumberRange.new(0, 360), Drag = 2,
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(count or 6)
end

---------------------------------------------------------------------------------------------------
-- camera shake: shake(amplitude, duration, worldPos?) - scaled down with distance from the camera
local shakes = {}
function FxLib.shake(amp, duration, pos, falloff)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	if pos then
		local cam = workspace.CurrentCamera
		amp *= math.clamp(1 - (cam.Focus.Position - pos).Magnitude / (falloff or 140), 0, 1)
	end
	if amp > 0.02 then
		table.insert(shakes, { amp = amp, t0 = os.clock(), dur = duration })
	end
end
RunService:BindToRenderStep("VulpineKitShake", Enum.RenderPriority.Camera.Value + 3, function()
	local total, t = 0, os.clock()
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = 1 - (t - s.t0) / s.dur
		if k <= 0 then
			table.remove(shakes, i)
		else
			total += s.amp * k * k
		end
	end
	if total > 0 then
		local cam = workspace.CurrentCamera
		local n = t * 38
		cam.CFrame = cam.CFrame * CFrame.new(math.noise(n, 1.3) * total * 0.45, math.noise(2.7, n) * total * 0.45, 0)
			* CFrame.Angles(math.noise(n, 4.1) * total * 0.02, math.noise(5.9, n) * total * 0.02, 0)
	end
end)

---------------------------------------------------------------------------------------------------
-- Energy Sphere visual: neon core, force-field shell, aura shell with inflowing particles, two spinning rings
function FxLib.sphere(parent, palette)
	local self = { t = 0, size = 0.1 }
	local model = Instance.new("Model")
	model.Name = "EnergySphere"
	self.core = FxLib.part("Core", Enum.PartType.Ball, Enum.Material.Neon, palette.SphereCore, model)
	self.shell = FxLib.part("Shell", Enum.PartType.Ball, Enum.Material.ForceField, palette.SphereShell, model)
	self.aura = FxLib.part("Aura", Enum.PartType.Ball, Enum.Material.ForceField, palette.SphereAura, model)
	self.aura.Transparency = 0.3
	self.rings = {}
	for i = 1, 2 do
		local r = FxLib.part("Ring", Enum.PartType.Cylinder, Enum.Material.Neon, i == 1 and palette.SphereAura or palette.SphereCore, model)
		r.Transparency = 0.35
		table.insert(self.rings, r)
	end
	self.light = Instance.new("PointLight")
	self.light.Color = palette.SphereShell
	self.light.Brightness = 4
	self.light.Shadows = false
	self.light.Parent = self.core
	self.inflow = FxLib.emitter(self.aura, {
		Texture = FxLib.Tex.spark, Color = ColorSequence.new(palette.SphereAura), LightEmission = 1, Rate = 90,
		Lifetime = NumberRange.new(0.18, 0.3), Speed = NumberRange.new(6, 10), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = NumberSequence.new(0.3, 0), Transparency = NumberSequence.new(0.1, 0.6),
	})
	self.model = model
	model.Parent = parent
	function self.set(_, pos, size, dt)
		self.t += dt
		self.size = size
		local cf = CFrame.new(pos)
		self.core.Size = Vector3.one * size * 0.55
		self.shell.Size = Vector3.one * size * 0.85
		self.aura.Size = Vector3.one * size * 1.1
		self.light.Range = math.min(size * 4, 40)
		self.core.CFrame = cf
		self.shell.CFrame = cf * CFrame.Angles(0, self.t * 9, 0)
		self.aura.CFrame = cf * CFrame.Angles(self.t * 5, 0, self.t * 3)
		for i, r in ipairs(self.rings) do
			r.Size = Vector3.new(0.06 * size, size * 1.05, size * 1.05)
			r.CFrame = cf * CFrame.fromAxisAngle(i == 1 and Vector3.new(1, 0.3, 0).Unit or Vector3.new(0, 0.4, 1).Unit, self.t * (i == 1 and 14 or -11))
		end
	end
	function self.destroy(_, fade)
		if not self.model then
			return
		end
		local m = self.model
		self.model = nil
		self.inflow.Enabled = false
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") then
				FxLib.tween(p, fade or 0.2, { Size = p.Size * 0.05, Transparency = 1 })
			end
		end
		Debris:AddItem(m, (fade or 0.2) + 0.1)
	end
	return self
end

-- Vortex Disc visual: a flat spinning disc of blades with a bright rim and a whirling particle edge
function FxLib.disc(parent, palette)
	local self = { t = 0, scale = 1 }
	local model = Instance.new("Model")
	model.Name = "VortexDisc"
	self.plate = FxLib.part("Plate", Enum.PartType.Cylinder, Enum.Material.ForceField, palette.DiscRim, model)
	self.hub = FxLib.part("Hub", Enum.PartType.Ball, Enum.Material.Neon, palette.Disc, model)
	self.blades = {}
	for _ = 1, 4 do
		local b = FxLib.part("Blade", Enum.PartType.Block, Enum.Material.Neon, palette.Disc, model)
		b.Transparency = 0.15
		table.insert(self.blades, b)
	end
	self.edge = FxLib.emitter(self.plate, {
		Texture = FxLib.Tex.spark, Color = ColorSequence.new(palette.Vortex), LightEmission = 1, Rate = 70,
		Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(2, 5), Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = NumberSequence.new(0.35, 0),
	})
	local l = Instance.new("PointLight")
	l.Color = palette.DiscRim
	l.Brightness = 4
	l.Range = 18
	l.Shadows = false
	l.Parent = self.hub
	self.model = model
	model.Parent = parent
	-- diameter = disc size in studs; spin around the world up axis
	function self.set(_, pos, diameter, dt)
		self.t += dt
		local base = CFrame.new(pos) * CFrame.Angles(0, self.t * 26, 0)
		self.plate.Size = Vector3.new(0.12, diameter, diameter)
		self.plate.CFrame = CFrame.new(pos) * CFrame.Angles(0, -self.t * 12, math.rad(90))
		self.hub.Size = Vector3.one * diameter * 0.28
		self.hub.CFrame = base
		for i, b in ipairs(self.blades) do
			b.Size = Vector3.new(diameter * 0.16, 0.12 * diameter / 5, diameter * 0.42)
			b.CFrame = base * CFrame.Angles(0, (i - 1) * math.pi / 2, 0) * CFrame.new(0, 0, -diameter * 0.29) * CFrame.Angles(0, math.rad(22), 0)
		end
	end
	function self.destroy(_, fade)
		if not self.model then
			return
		end
		local m = self.model
		self.model = nil
		self.edge.Enabled = false
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") then
				FxLib.tween(p, fade or 0.15, { Transparency = 1 })
			end
		end
		Debris:AddItem(m, (fade or 0.15) + 0.1)
	end
	return self
end

-- wind vortex field: a translucent dome, swirling smoke and flickering wind streaks
function FxLib.vortex(parent, palette, pos, radius)
	local self = { t = 0, pos = pos, radius = radius }
	local model = Instance.new("Model")
	model.Name = "WindVortex"
	self.dome = FxLib.part("Dome", Enum.PartType.Ball, Enum.Material.ForceField, palette.Vortex, model)
	self.dome.CFrame = CFrame.new(pos)
	self.dome.Size = Vector3.one * 2
	FxLib.tween(self.dome, 0.2, { Size = Vector3.one * radius * 2 }, Enum.EasingStyle.Back)
	local host = FxLib.part("Host", Enum.PartType.Ball, Enum.Material.SmoothPlastic, palette.Vortex, model)
	host.Transparency = 1
	host.Size = Vector3.one * radius * 1.6
	host.CFrame = CFrame.new(pos)
	FxLib.emitter(host, {
		Texture = FxLib.Tex.smoke, Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.4, Rate = 70,
		Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(8, 14), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = NumberSequence.new(radius * 0.3, radius * 0.1), Transparency = NumberSequence.new(0.55, 1),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
	})
	self.streaks = {}
	for _ = 1, 28 do
		local s = FxLib.part("Streak", Enum.PartType.Block, Enum.Material.Neon, palette.Vortex, model)
		s.Size = Vector3.new(0.12, 0.12, radius * (0.3 + math.random() * 0.35))
		s.Transparency = 0.2
		table.insert(self.streaks, { part = s, ang = math.random() * 6.28, r = radius * (0.2 + math.random() * 0.75), y = (math.random() - 0.5) * radius })
	end
	local l = Instance.new("PointLight")
	l.Color = palette.Vortex
	l.Range = 60
	l.Brightness = 3
	l.Shadows = false
	l.Parent = host
	self.model = model
	model.Parent = parent
	function self.update(_, dt)
		self.t += dt
		if self.t > 0.2 then
			self.dome.Size = Vector3.one * radius * 2 * (1 + 0.03 * math.sin(self.t * 30))
		end
		for _, s in ipairs(self.streaks) do
			s.ang += dt * (9 + 30 / math.max(s.r, 1))
			local p = pos + Vector3.new(math.cos(s.ang) * s.r, s.y, math.sin(s.ang) * s.r)
			local tangent = Vector3.new(-math.sin(s.ang), 0, math.cos(s.ang))
			s.part.CFrame = CFrame.lookAt(p, p + tangent)
		end
	end
	function self.destroy()
		if self.model then
			self.model:Destroy()
			self.model = nil
		end
	end
	return self
end

---------------------------------------------------------------------------------------------------
-- camera envelopes: timed FOV / tint / blur / contrast pulses. Every envelope is { fov, blur, bright, contrast,
-- sat, tint, attack, hold, release, delay }; they are summed each frame and the camera returns to its own FOV
-- once the last one ends.
local envs = {}
local baseFOV, cc, blur
function FxLib.envelope(e)
	e.t0 = os.clock() + (e.delay or 0)
	e.attack = e.attack or 0.05
	e.hold = e.hold or 0
	e.release = e.release or 0.3
	if #envs == 0 and not baseFOV then
		baseFOV = workspace.CurrentCamera.FieldOfView
	end
	table.insert(envs, e)
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

RunService:BindToRenderStep("VulpineKitCamera", Enum.RenderPriority.Camera.Value + 2, function()
	local cam = workspace.CurrentCamera
	if #envs == 0 then
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
		cc.Name = "VulpineCC"
		cc.Parent = cam
	end
	if not blur or blur.Parent ~= cam then
		blur = Instance.new("BlurEffect")
		blur.Name = "VulpineBlur"
		blur.Size = 0
		blur.Parent = cam
	end
	local t = os.clock()
	local fov, bl, br, ct, sat, tintW = 0, 0, 0, 0, 0, 0
	local tint = Color3.new(1, 1, 1)
	local i = 1
	while i <= #envs do
		local e = envs[i]
		local w = envWeight(e, t)
		if w == nil then
			table.remove(envs, i)
		else
			fov += (e.fov or 0) * w
			bl += (e.blur or 0) * w
			br += (e.bright or 0) * w
			ct += (e.contrast or 0) * w
			sat += (e.sat or 0) * w
			if e.tint and w > tintW then
				tintW, tint = w, e.tint
			end
			i += 1
		end
	end
	cam.FieldOfView = math.clamp((baseFOV or 70) + fov, 20, 110)
	cc.Brightness, cc.Contrast, cc.Saturation = br, ct, sat
	cc.TintColor = Color3.new(1, 1, 1):Lerp(tint, tintW * 0.6)
	blur.Size = bl
end)

---------------------------------------------------------------------------------------------------
-- ground cracks: a scorched disc, jagged fissures that glow `rim` for a moment, and a glowing ring that races
-- outward; everything fades after `life` seconds. `pos` / `normal` = the ground hit.
local CRACK = Color3.fromRGB(32, 28, 30)
function FxLib.cracks(parent, pos, normal, radius, rim, life)
	life = life or 6
	normal = (typeof(normal) == "Vector3" and normal.Magnitude > 0.1) and normal.Unit or Vector3.yAxis
	local right = normal:Cross(Vector3.zAxis)
	if right.Magnitude < 0.1 then
		right = normal:Cross(Vector3.xAxis)
	end
	local base = CFrame.fromMatrix(pos + normal * 0.05, right.Unit, normal) * CFrame.Angles(0, math.random() * 6.28, 0)
	local model = Instance.new("Model")
	model.Name = "GroundCracks"
	local fade = {}
	local scorch = FxLib.part("Scorch", Enum.PartType.Cylinder, Enum.Material.SmoothPlastic, CRACK, model)
	scorch.Size = Vector3.new(0.06, radius * 1.3, radius * 1.3)
	scorch.CFrame = base * CFrame.Angles(0, 0, math.rad(90))
	scorch.Transparency = 0.45
	table.insert(fade, scorch)
	local glows = {}
	local n = math.clamp(math.floor(radius * 1.1), 5, 12)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + (math.random() - 0.5) * 0.5
		local len = radius * (0.55 + math.random() * 0.6)
		local w = 0.18 + math.random() * 0.22
		local dir = base * CFrame.Angles(0, a, 0)
		local crack = FxLib.part("Crack", Enum.PartType.Block, Enum.Material.SmoothPlastic, CRACK, model)
		crack.Size = Vector3.new(w, 0.07, len)
		crack.CFrame = dir * CFrame.new(0, 0.02, -len / 2 - radius * 0.1)
		table.insert(fade, crack)
		local glow = FxLib.part("CrackGlow", Enum.PartType.Block, Enum.Material.Neon, rim, model)
		glow.Size = Vector3.new(w * 0.45, 0.08, len * 0.9)
		glow.CFrame = crack.CFrame
		table.insert(glows, glow)
		if math.random() < 0.55 then
			-- a forked branch off the middle of the crack
			local blen = len * (0.35 + math.random() * 0.3)
			local branch = FxLib.part("Crack", Enum.PartType.Block, Enum.Material.SmoothPlastic, CRACK, model)
			branch.Size = Vector3.new(w * 0.7, 0.07, blen)
			branch.CFrame = dir * CFrame.new(0, 0.02, -len * 0.55 - radius * 0.1) * CFrame.Angles(0, (math.random() < 0.5 and -1 or 1) * math.rad(25 + math.random() * 20), 0) * CFrame.new(0, 0, -blen / 2)
			table.insert(fade, branch)
		end
	end
	local ring = FxLib.part("RimGlow", Enum.PartType.Cylinder, Enum.Material.Neon, rim, model)
	ring.Size = Vector3.new(0.1, radius * 0.6, radius * 0.6)
	ring.CFrame = base * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	model.Parent = parent
	FxLib.tween(ring, 0.5, { Size = Vector3.new(0.1, radius * 2.6, radius * 2.6), Transparency = 1 }, Enum.EasingStyle.Quart)
	for _, g in ipairs(glows) do
		FxLib.tween(g, 1.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(life, function()
		for _, p in ipairs(fade) do
			FxLib.tween(p, 1.2, { Transparency = 1 })
		end
	end)
	Debris:AddItem(model, life + 1.4)
end

-- (2026-11-12, owner: "for abilities, add unique sounds such that they dont all sound the same") Narito's own palette - the
-- set above is borrowed from Goju's Hollow Purple, so the two fighters sounded identical
for k, v in pairs({
	Charge = "rbxassetid://122439012218772", -- rasengan spin-up (magic energy charge burst)
	Rise = "rbxassetid://119573908217733", -- wind burst: sage / kurama rising, rasengan swell
	Launch = "rbxassetid://9120718689", -- rasenshuriken thrown (swish-by)
	Blast = "rbxassetid://104471217536585", -- big detonation
	Impact = "rbxassetid://138533090376585", -- blast impact boom
	Hum = "rbxassetid://9119415101", -- deep chakra hum
	Step = "rbxassetid://9126283592", -- quick swish
}) do
	FxLib.Sounds[k] = v
end

return FxLib
