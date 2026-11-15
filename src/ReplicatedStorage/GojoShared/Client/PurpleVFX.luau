--!nocheck
-- PurpleVFX: client-only builders for Lapse Blue / Reversal Red / Hollow Purple orbs and their impact effects.
-- Everything is anchored, non-colliding, parented under the caller's per-cast folder, and cheap to destroy.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local PurpleVFX = {}

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	flare = "rbxasset://textures/particles/fire_sparks_main.dds",
	glow = "rbxasset://textures/particles/explosion01_implosion_main.dds", -- a soft white ball of light
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}

PurpleVFX.Sounds = {
	Blue = "rbxassetid://113813942754476",
	Red = "rbxassetid://135281137796217",
	Birth = "rbxassetid://102313023652420",
	Launch = "rbxassetid://93530870983093",
	Chant = "rbxassetid://96359585058783",
	Swing = "rbxassetid://122439012218772",
	Hit = "rbxassetid://74041775202019",
	HitFinal = "rbxassetid://9126050116",
}

local STYLE = {
	Blue = { core = Color3.fromRGB(120, 195, 255), shell = Color3.fromRGB(40, 120, 255), aura = Color3.fromRGB(60, 150, 255), light = Color3.fromRGB(80, 160, 255), spark = Color3.fromRGB(150, 210, 255) },
	Red = { core = Color3.fromRGB(255, 196, 182), shell = Color3.fromRGB(255, 40, 40), aura = Color3.fromRGB(255, 70, 55), light = Color3.fromRGB(255, 70, 60), spark = Color3.fromRGB(255, 150, 110) },
	Purple = { core = Color3.fromRGB(215, 150, 255), shell = Color3.fromRGB(135, 35, 255), aura = Color3.fromRGB(175, 90, 255), light = Color3.fromRGB(170, 80, 255), spark = Color3.fromRGB(230, 170, 255) },
}

local function part(name, shape, material, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Material = material
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function ns(...)
	return NumberSequence.new(...)
end
-- HDR brightness on an emitter (pcall: older clients may not have the property)
local function bright(e, v)
	pcall(function()
		e.Brightness = v
	end)
	return e
end

function PurpleVFX.sound(id, parent, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 400
	s.RollOffMinDistance = 30
	s.Parent = parent
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 12)
	return s
end

-- an anchored, invisible point host for one-shot emitters/sounds
function PurpleVFX.anchor(parent, pos, life)
	local p = part("FxAnchor", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), parent)
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	Debris:AddItem(p, life or 4)
	return p
end

---------------------------------------------------------------------------------------------------
local Orb = {}
Orb.__index = Orb

function PurpleVFX.orb(kind, parent)
	local st = STYLE[kind]
	local self = setmetatable({ kind = kind, r = 0, t = 0 }, Orb)
	local model = Instance.new("Model")
	model.Name = kind .. "Orb"
	self.core = part("Core", Enum.PartType.Ball, Enum.Material.Neon, st.core, model)
	self.shell = part("Shell", Enum.PartType.Ball, Enum.Material.ForceField, st.shell, model)
	self.aura = part("Aura", Enum.PartType.Ball, Enum.Material.ForceField, st.aura, model)
	self.aura.Transparency = 0.25
	self.light = Instance.new("PointLight")
	self.light.Color = st.light
	self.light.Brightness = kind == "Purple" and 6 or 3
	self.light.Shadows = false
	self.light.Parent = self.core
	local att = Instance.new("Attachment")
	att.Parent = self.core
	self.emitters = {}
	-- a soft bloom halo riding the orb and glints flickering over its surface (both sized in setRadius)
	self.emitters.halo = bright(emitter(att, {
		Texture = TEX.glow, Color = ColorSequence.new(st.aura), LightEmission = 1, Rate = 22, LockedToPart = true,
		Lifetime = NumberRange.new(0.16, 0.24), Speed = NumberRange.new(0), Size = ns(1), ZOffset = -0.5,
		Transparency = ns({ NumberSequenceKeypoint.new(0, kind == "Purple" and 0.6 or 0.3), NumberSequenceKeypoint.new(1, 1) }), Rotation = NumberRange.new(0, 360),
	}), 2.5)
	self.emitters.glint = bright(emitter(self.shell, {
		Texture = TEX.spark, Color = ColorSequence.new(Color3.new(1, 1, 1), st.spark), LightEmission = 1, Rate = 18, LockedToPart = true,
		Lifetime = NumberRange.new(0.1, 0.2), Speed = NumberRange.new(0.5, 2), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = ns(0.4, 0), Rotation = NumberRange.new(0, 360),
	}), 2)
	if kind == "Red" then
		-- an anamorphic flare: a wide streak of light straight through the orb
		self.emitters.flare = bright(emitter(att, {
			Texture = TEX.glow, Color = ColorSequence.new(Color3.fromRGB(255, 205, 185), st.shell), LightEmission = 1, Rate = 30,
			LockedToPart = true, Lifetime = NumberRange.new(0.12, 0.2), Speed = NumberRange.new(0), Squash = ns(-2.8),
			Size = ns(1), Transparency = ns({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }), ZOffset = 0.5,
		}), 3)
	elseif kind == "Blue" then
		-- light sucked in from every side, spiralling with the churning aura
		self.emitters.suck = bright(emitter(self.aura, {
			Texture = TEX.glow, Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), st.shell), LightEmission = 1, Rate = 50,
			LockedToPart = true, Lifetime = NumberRange.new(0.16, 0.22), Speed = NumberRange.new(8, 10), Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-2.4), Size = ns(0.3, 0.05),
			Transparency = ns({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 0.4) }),
		}), 2.5)
	end
	if kind == "Blue" then
		-- Lapse Blue: particles stream INTO the orb (attraction)
		self.emitters.pull = emitter(self.aura, {
			Texture = TEX.spark, Color = ColorSequence.new(st.spark), LightEmission = 1, Rate = 70,
			Lifetime = NumberRange.new(0.25, 0.4), Speed = NumberRange.new(6, 10), Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			Size = ns(0.35, 0), Transparency = ns(0.1, 0.6),
		})
	elseif kind == "Red" then
		-- Reversal Red: crackling sparks thrown OUT (repulsion)
		self.emitters.push = emitter(att, {
			Texture = TEX.flare, Color = ColorSequence.new(st.spark, Color3.fromRGB(255, 60, 40)), LightEmission = 1, Rate = 60,
			Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(180, 180),
			Size = ns(0.4, 0), Transparency = ns(0, 0.5), Drag = 3,
		})
	else
		self.emitters.crackle = emitter(att, {
			Texture = TEX.flare, Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 255)),
			}), LightEmission = 1, Rate = 45, Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(10, 25),
			SpreadAngle = Vector2.new(180, 180), Size = ns(0.6, 0), Drag = 2,
		})
		self.emitters.trail = emitter(att, {
			Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(120, 40, 200), Color3.fromRGB(30, 10, 50)),
			LightEmission = 0.35, Rate = 0, Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(180, 180), Size = ns(1, 2), Transparency = ns({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), LockedToPart = false,
		})
		-- the surface churning: a glinting vortex spun hard over the orb
		self.emitters.swirl = bright(emitter(att, {
			Texture = TEX.vortex, Color = ColorSequence.new(Color3.fromRGB(255, 235, 255), st.spark), LightEmission = 1, Rate = 8,
			LockedToPart = true, Lifetime = NumberRange.new(0.35, 0.5), Speed = NumberRange.new(0), Size = ns(1),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-720, 720),
			Transparency = ns({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		}), 2.5)
		-- two tumbling energy rings (red + blue) built from curved beams
		self.rings = {}
		for i, col in ipairs({ Color3.fromRGB(255, 70, 70), Color3.fromRGB(80, 150, 255) }) do
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Parent, a1.Parent = self.core, self.core
			local beams = {}
			for _, sgn in ipairs({ 1, -1 }) do
				local b = Instance.new("Beam")
				b.Attachment0, b.Attachment1 = a0, a1
				b.Color = ColorSequence.new(col)
				b.LightEmission = 1
				b.LightInfluence = 0
				b.FaceCamera = true
				b.Segments = 24
				b.Transparency = ns(0.05)
				b:SetAttribute("Sign", sgn)
				b.Parent = self.core
				table.insert(beams, b)
			end
			table.insert(self.rings, { a0 = a0, a1 = a1, beams = beams, axis = (i == 1) and Vector3.new(1, 0.3, 0).Unit or Vector3.new(0, 0.4, 1).Unit, speed = (i == 1) and 5.5 or -4.2 })
		end
	end
	model.Parent = parent
	self.model = model
	return self
end

function Orb:setRadius(r)
	r = math.max(r, 0.05)
	if math.abs(r - self.r) < 0.01 then
		return
	end
	self.r = r
	local coreScale = self.kind == "Purple" and 1.3 or 1.2
	self.core.Size = Vector3.one * r * coreScale
	self.shell.Size = Vector3.one * r * 1.75
	self.aura.Size = Vector3.one * r * 2.2
	self.light.Range = math.min(r * (self.kind == "Purple" and 4 or 6), 60)
	if self.emitters.crackle then
		self.emitters.crackle.Size = ns(0.25 * r + 0.3, 0)
		self.emitters.crackle.Speed = NumberRange.new(r * 2, r * 4)
	end
	if self.emitters.trail then
		self.emitters.trail.Size = ns(r * 1.1, r * 1.9)
	end
	local em = self.emitters
	if em.halo then
		em.halo.Size = ns(r * (self.kind == "Purple" and 2.6 or 4.4))
	end
	if em.glint then
		em.glint.Size = ns(math.max(0.25, r * 0.38), 0)
	end
	if em.flare then
		em.flare.Size = ns(r * 4.8)
	end
	if em.suck then
		em.suck.Speed = NumberRange.new(r * 5, r * 6.5)
		em.suck.Size = ns(math.max(0.15, r * 0.22), 0.03)
	end
	if em.swirl then
		em.swirl.Size = ns(r * 2.9)
	end
	if self.rings then
		for _, ring in ipairs(self.rings) do
			for _, b in ipairs(ring.beams) do
				local k = r * 1.45 * b:GetAttribute("Sign")
				b.CurveSize0, b.CurveSize1 = k, k
				b.Width0, b.Width1 = r * 0.16, r * 0.16
			end
		end
	end
end

function Orb:place(pos, dt)
	self.t += dt or 0
	local cf = CFrame.new(pos)
	self.core.CFrame = cf
	self.shell.CFrame = cf * CFrame.Angles(0, self.t * 2, 0)
	self.aura.CFrame = cf * CFrame.Angles(self.t * 1.3, 0, self.t * 0.7)
	if self.rings then
		local R = self.r * 1.05
		for _, ring in ipairs(self.rings) do
			local spin = CFrame.fromAxisAngle(ring.axis, self.t * ring.speed)
			ring.a0.CFrame = spin * CFrame.fromMatrix(Vector3.new(-R, 0, 0), Vector3.yAxis, -Vector3.xAxis)
			ring.a1.CFrame = spin * CFrame.fromMatrix(Vector3.new(R, 0, 0), -Vector3.yAxis, Vector3.xAxis)
		end
	end
end

function Orb:setTrail(rate)
	if self.emitters.trail then
		self.emitters.trail.Rate = rate
	end
end

function Orb:destroy(fade)
	local model = self.model
	if not model or not model.Parent then
		return
	end
	self.model = nil
	for _, e in pairs(self.emitters) do
		e.Enabled = false
	end
	if fade and fade > 0 then
		local info = TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, p in ipairs({ self.core, self.shell, self.aura }) do
			TweenService:Create(p, info, { Size = p.Size * 0.05 }):Play()
		end
		TweenService:Create(self.light, info, { Brightness = 0 }):Play()
		Debris:AddItem(model, fade + 2.5) -- trail smoke keeps drifting a moment
	else
		model:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- one-shot effects
function PurpleVFX.flash(parent, pos, radius, color, duration)
	duration = duration or 0.35
	local b = part("Flash", Enum.PartType.Ball, Enum.Material.ForceField, color or Color3.new(1, 1, 1), parent)
	b.Size = Vector3.one * radius * 0.4
	b.CFrame = CFrame.new(pos)
	local l = Instance.new("PointLight")
	l.Color = color or Color3.new(1, 1, 1)
	l.Brightness = 8
	l.Range = math.min(radius * 4, 60)
	l.Shadows = false
	l.Parent = b
	-- a camera-facing bloom so the flash reads as light, not just a growing bubble
	local ga = Instance.new("Attachment")
	ga.Parent = b
	bright(emitter(ga, {
		Texture = TEX.glow, Color = ColorSequence.new(color or Color3.new(1, 1, 1)), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(duration), Speed = NumberRange.new(0), ZOffset = 1,
		Size = ns({ NumberSequenceKeypoint.new(0, radius * 0.8), NumberSequenceKeypoint.new(0.15, radius * 2.4), NumberSequenceKeypoint.new(1, radius * 2.8) }),
		Transparency = ns({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
	}), 2.5):Emit(1)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(b, info, { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	TweenService:Create(l, info, { Brightness = 0 }):Play()
	Debris:AddItem(b, duration + 0.1)
end

-- a flat expanding disc; `normal` is the disc's facing axis
function PurpleVFX.shockwave(parent, pos, normal, fromD, toD, color, duration)
	duration = duration or 0.4
	local disc = part("Shockwave", Enum.PartType.Cylinder, Enum.Material.ForceField, color, parent)
	local up = math.abs(normal.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	disc.CFrame = CFrame.fromMatrix(pos, normal.Unit, normal.Unit:Cross(up).Unit)
	disc.Size = Vector3.new(0.35, fromD, fromD)
	-- a ring of light riding the disc (the disc's axis is its X; the emitter fires along the attachment's Y)
	local ra = Instance.new("Attachment")
	ra.CFrame = CFrame.Angles(0, 0, -math.pi / 2)
	ra.Parent = disc
	bright(emitter(ra, {
		Texture = TEX.ring, Color = ColorSequence.new(color), LightEmission = 1, Rate = 0, Lifetime = NumberRange.new(duration),
		Speed = NumberRange.new(0.01), EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = ns({ NumberSequenceKeypoint.new(0, fromD), NumberSequenceKeypoint.new(0.3, toD * 0.9), NumberSequenceKeypoint.new(1, toD * 1.08) }),
		Transparency = ns({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360),
	}), 2.5):Emit(1)
	TweenService:Create(disc, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, toD, toD), Transparency = 1,
	}):Play()
	Debris:AddItem(disc, duration + 0.1)
end

function PurpleVFX.burst(parent, pos, color, count, size, speed)
	local host = PurpleVFX.anchor(parent, pos, 2)
	local e = emitter(host, {
		Texture = TEX.flare, Color = ColorSequence.new(color), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(180, 180), Size = ns(size, 0), Drag = 4,
	})
	e:Emit(count)
	-- and streaks of light flung out with the sparks
	bright(emitter(host, {
		Texture = TEX.glow, Color = ColorSequence.new(Color3.new(1, 1, 1), color), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.15, 0.32), Speed = NumberRange.new(speed * 0.8, speed * 1.6), SpreadAngle = Vector2.new(180, 180),
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-2.6), Size = ns(size * 0.9, 0), Drag = 3,
	}), 2.5):Emit(math.max(4, math.floor(count * 0.5)))
	return host
end

function PurpleVFX.dust(parent, pos, size, count)
	local host = PurpleVFX.anchor(parent, pos, 4)
	local e = emitter(host, {
		Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(150, 128, 110)), LightEmission = 0, LightInfluence = 1,
		Rate = 0, Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(size * 0.6, size * 1.4),
		SpreadAngle = Vector2.new(80, 80), Size = ns(size * 0.5, size * 1.4),
		Transparency = ns({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Drag = 2,
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(count or 6)
	return host
end

-- lingering purple scorch smoke along the trench
function PurpleVFX.scorch(parent, pos, size)
	local host = PurpleVFX.anchor(parent, pos, 3)
	local e = emitter(host, {
		Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(110, 40, 180), Color3.fromRGB(25, 10, 40)),
		LightEmission = 0.4, Rate = 0, Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(60, 60), Size = ns(size * 0.6, size * 1.2),
		Transparency = ns({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(4)
end

return PurpleVFX
