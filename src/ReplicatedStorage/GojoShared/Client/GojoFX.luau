--!nocheck
-- GojoFX: the flashy layer for Gojo's kit, on top of PurpleVFX's orbs - light streaks, shock rings, lightning,
-- rubble, floating rocks, the Hollow Purple helix, the Unlimited Void's warp field / starlight rays / galaxy /
-- shatter, and the screen-space anime FX (speed lines, impact frames, flashes). Client-only and purely cosmetic.
-- World pieces are anchored (rubble excepted), non-colliding and non-querying, parented under the caller's folder,
-- and clean themselves up. Screen pieces live on their own ScreenGui just UNDER the HUD so titles stay readable.
-- Textures are Studio's built-in particle sheets, so nothing has to stream in from the website:
--   glow = a soft white ball (stretched with Squash it becomes a light streak), ring = a soft ring,
--   star = an 8-point glint, vortex = a glinting ring.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FX = {}

local TEX = {
	glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	star = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
}
FX.TEX = TEX

local TAU = math.pi * 2
local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------------------------------------------
-- helpers
local function ns(...)
	return NumberSequence.new(...)
end
-- NumberSequence from { {t, v}, ... }
local function nsk(list)
	local k = {}
	for i, v in ipairs(list) do
		k[i] = NumberSequenceKeypoint.new(v[1], math.clamp(v[2], 0, 1e4), v[3] or 0)
	end
	return NumberSequence.new(k)
end
local function alpha(list)
	local k = {}
	for i, v in ipairs(list) do
		k[i] = NumberSequenceKeypoint.new(v[1], math.clamp(v[2], 0, 1))
	end
	return NumberSequence.new(k)
end
local function cs(a, b)
	if typeof(a) == "ColorSequence" then
		return a
	end
	return ColorSequence.new(a or WHITE, b or a or WHITE)
end
FX.ns, FX.nsk, FX.cs = ns, nsk, cs

local function randUnit()
	local z = rng:NextNumber(-1, 1)
	local a = rng:NextNumber(0, TAU)
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(a), z, r * math.sin(a))
end
FX.randUnit = randUnit

-- two unit vectors perpendicular to dir and to each other
local function perp(dir)
	local up = math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local r = dir:Cross(up).Unit
	return r, r:Cross(dir).Unit
end
FX.perp = perp

-- a rotation-only CFrame whose +Y axis is dir (an emitter with EmissionDirection Top then fires along dir)
local function yAlong(dir)
	dir = (typeof(dir) == "Vector3" and dir.Magnitude > 1e-4) and dir.Unit or Vector3.yAxis
	local x = dir:Cross(Vector3.yAxis)
	if x.Magnitude < 1e-3 then
		x = dir:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(Vector3.zero, x.Unit, dir)
end
FX.yAlong = yAlong

local function part(name, shape, material, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Material = material or Enum.Material.Neon
	p.Color = color or WHITE
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if parent then
		p.Parent = parent
	end
	return p
end
FX.part = part

-- an invisible anchored host for one-shot emitters, lights and sounds
local function anchor(parent, pos, life)
	local p = part("FxHost", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = typeof(pos) == "CFrame" and pos or CFrame.new(pos)
	p.Parent = parent
	if life then
		Debris:AddItem(p, life)
	end
	return p
end
FX.anchor = anchor

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LightEmission = 1
	e.Rate = 0
	for k, v in pairs(props) do
		if k ~= "Brightness" then
			e[k] = v
		end
	end
	if props.Brightness then
		pcall(function()
			e.Brightness = props.Brightness
		end)
	end
	e.Parent = parent
	return e
end
FX.emitter = emitter

local function live(parent)
	return typeof(parent) == "Instance" and parent.Parent ~= nil
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
-- the ground (terrain or a solid part) under pos, ignoring characters, NPCs and effects
local function groundHit(pos, depth)
	local list = {}
	for _, n in ipairs({ "LocalFX", "NPCs", "FX" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	return workspace:Raycast(pos + Vector3.yAxis * 3, Vector3.new(0, -((depth or 14) + 3), 0), groundParams)
end
FX.groundHit = groundHit

---------------------------------------------------------------------------------------------------
-- one-shots

-- a soft camera-facing bloom of light: the flash every hit is built on
function FX.glow(parent, pos, size, color, life, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	life = life or 0.3
	local host = anchor(parent, pos, life + 0.3)
	local a0 = opts.alpha or 0
	local e = emitter(host, {
		Texture = TEX.glow, Color = cs(color), Lifetime = NumberRange.new(life), Speed = NumberRange.new(0),
		Size = nsk({ { 0, size * (opts.from or 0.4) }, { 0.1, size }, { 1, size * (opts.to or 1.25) } }),
		Transparency = alpha({ { 0, a0 }, { 0.3, 0.2 + a0 * 0.6 }, { 1, 1 } }),
		ZOffset = opts.z or 1, Brightness = opts.brightness or 2, Rotation = NumberRange.new(0, 360),
	})
	e:Emit(opts.count or 1)
	return host
end

-- a flat ring of light expanding (or, with from > to, collapsing) across the plane that faces `normal`
function FX.ring(parent, pos, normal, from, to, color, life, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	life = life or 0.4
	local host = anchor(parent, pos, life + 0.3)
	local a = Instance.new("Attachment")
	a.CFrame = yAlong(normal)
	a.Parent = host
	local d = to - from
	local size
	if opts.ease == "in" then
		size = nsk({ { 0, from }, { 0.55, from + d * 0.3 }, { 0.85, from + d * 0.75 }, { 1, to } })
	else
		size = nsk({ { 0, from }, { 0.12, from + d * 0.55 }, { 0.4, from + d * 0.86 }, { 1, to } })
	end
	local a0 = opts.alpha or 0
	local e = emitter(a, {
		Texture = TEX.ring, Color = cs(color), Lifetime = NumberRange.new(life), Speed = NumberRange.new(0.01),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.zero, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = size, Transparency = alpha({ { 0, a0 }, { 0.55, 0.3 + a0 * 0.6 }, { 1, 1 } }),
		Brightness = opts.brightness or 2.5, Rotation = NumberRange.new(0, 360), ZOffset = opts.z or 0,
	})
	e:Emit(opts.count or 1)
	return host
end

-- light streaks: radial (no dir), a cone along opts.dir, or sucked inward from a sphere of radius opts.inward
-- (VelocityParallel particles stretch along their motion with a NEGATIVE Squash; positive widens them across it)
function FX.streaks(parent, pos, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	local life = opts.life or 0.35
	local sz = opts.size or 0.5
	local props = {
		Texture = TEX.glow, Color = cs(opts.color, opts.color2), Lifetime = NumberRange.new(life * 0.6, life),
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-math.min(opts.stretch or 2.6, 3)),
		Size = nsk({ { 0, sz * 0.5 }, { 0.2, sz }, { 1, 0 } }), Transparency = alpha({ { 0, 0.05 }, { 0.7, 0.2 }, { 1, 1 } }),
		Drag = opts.drag or 0, Acceleration = opts.accel or Vector3.zero, Brightness = opts.brightness or 2.5,
		ZOffset = opts.z or 0.5,
	}
	local host = anchor(parent, pos, life + 0.4)
	if opts.inward then
		host.Shape = Enum.PartType.Ball
		host.Size = Vector3.one * opts.inward * 2
		props.Shape = Enum.ParticleEmitterShape.Sphere
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		props.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		local sp = opts.inward / life
		props.Speed = NumberRange.new(sp * 0.95, sp * 1.2)
		props.Transparency = alpha({ { 0, 1 }, { 0.2, 0.1 }, { 0.85, 0.05 }, { 1, 1 } })
		local e = emitter(host, props)
		e:Emit(opts.count or 30)
		return host
	end
	local a = Instance.new("Attachment")
	a.CFrame = opts.dir and yAlong(opts.dir) or CFrame.identity
	a.Parent = host
	props.EmissionDirection = Enum.NormalId.Top
	props.SpreadAngle = opts.dir and Vector2.new(opts.spread or 20, opts.spread or 20) or Vector2.new(180, 180)
	props.Speed = NumberRange.new(opts.speed and opts.speed[1] or 60, opts.speed and opts.speed[2] or 120)
	local e = emitter(a, props)
	e:Emit(opts.count or 30)
	return host
end

-- glinting sparks that tumble and fall
function FX.sparks(parent, pos, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	local life = opts.life or 0.6
	local host = anchor(parent, pos, life + 0.4)
	local a = Instance.new("Attachment")
	a.CFrame = opts.dir and yAlong(opts.dir) or CFrame.identity
	a.Parent = host
	local e = emitter(a, {
		Texture = TEX.star, Color = cs(opts.color, opts.color2), Lifetime = NumberRange.new(life * 0.5, life),
		Speed = NumberRange.new(opts.speed and opts.speed[1] or 20, opts.speed and opts.speed[2] or 50),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = opts.dir and Vector2.new(opts.spread or 35, opts.spread or 35) or Vector2.new(180, 180),
		Size = nsk({ { 0, opts.size or 0.6 }, { 1, 0 } }), Transparency = alpha({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
		Drag = opts.drag or 3, Acceleration = opts.accel or Vector3.new(0, -30, 0), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300), Brightness = opts.brightness or 2,
	})
	e:Emit(opts.count or 24)
	return host
end

-- a point light that flares and dies
function FX.light(parent, pos, color, brightness, range, life)
	if not live(parent) then
		return
	end
	life = life or 0.3
	local host = anchor(parent, pos, life + 0.1)
	local l = Instance.new("PointLight")
	l.Color = color or WHITE
	l.Brightness = brightness or 8
	l.Range = math.min(range or 30, 60)
	l.Shadows = false
	l.Parent = host
	TweenService:Create(l, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	return host
end

-- an expanding ball that burns out (Neon = a fireball of light, ForceField = a crackling energy shell)
function FX.shell(parent, pos, from, to, color, life, material)
	if not live(parent) then
		return
	end
	local b = part("Shell", Enum.PartType.Ball, material or Enum.Material.Neon, color, nil)
	b.Size = Vector3.one * from * 2
	b.CFrame = CFrame.new(pos)
	b.Transparency = (material == Enum.Material.ForceField) and 0 or 0.1
	b.Parent = parent
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * to * 2, Transparency = 1,
	}):Play()
	Debris:AddItem(b, life + 0.1)
	return b
end

-- a trail ribbon dragged behind a moving part
function FX.trail(p, color, width, life, opts)
	opts = opts or {}
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a1.Position = Vector3.new(0, -width / 2, 0)
	a0.Parent, a1.Parent = p, p
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = cs(color)
	t.Lifetime = life or 0.25
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.MinLength = 0.05
	t.Transparency = alpha({ { 0, opts.alpha or 0.05 }, { 1, 1 } })
	t.WidthScale = nsk({ { 0, 1 }, { 1, opts.tail or 0.1 } })
	pcall(function()
		t.Brightness = opts.brightness or 2.5
	end)
	t.Parent = p
	return t
end

---------------------------------------------------------------------------------------------------
-- lightning

-- one jagged bolt a -> b: a hot white core inside a coloured sheath, struck, re-struck, then gone
function FX.bolt(parent, a, b, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	local span = b - a
	local len = span.Magnitude
	if len < 0.2 then
		return
	end
	local color = opts.color or Color3.fromRGB(150, 200, 255)
	local width = opts.width or math.clamp(len * 0.025, 0.06, 0.4)
	local n = opts.segments or math.clamp(math.floor(len / 2), 3, 12)
	local jag = (opts.jag or 0.18) * len
	local life = opts.life or 0.14
	local f = Instance.new("Folder")
	f.Name = "Bolt"
	local cores, sheaths = {}, {}
	for i = 1, n do
		cores[i] = part("BoltCore", Enum.PartType.Block, Enum.Material.Neon, opts.core or Color3.fromRGB(245, 250, 255), f)
		local s = part("BoltGlow", Enum.PartType.Block, Enum.Material.Neon, color, f)
		s.Transparency = 0.45
		sheaths[i] = s
	end
	local r1, u1 = perp(span / len)
	local function strike()
		local pts = { a }
		for i = 1, n - 1 do
			local k = i / n
			local env = math.sin(k * math.pi)
			pts[i + 1] = a + span * k + (r1 * rng:NextNumber(-1, 1) + u1 * rng:NextNumber(-1, 1)) * jag * env
		end
		pts[n + 1] = b
		for i = 1, n do
			local p0, p1 = pts[i], pts[i + 1]
			local seg = (p1 - p0).Magnitude
			if seg > 1e-3 then
				local cf = CFrame.lookAt((p0 + p1) / 2, p1)
				cores[i].Size = Vector3.new(width, width, seg + width)
				cores[i].CFrame = cf
				sheaths[i].Size = Vector3.new(width * 2.8, width * 2.8, seg + width * 2)
				sheaths[i].CFrame = cf
			end
		end
	end
	strike()
	if opts.light then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Brightness = 4
		l.Range = math.clamp(len, 6, 24)
		l.Shadows = false
		l.Parent = cores[math.max(1, math.floor(n / 2))]
	end
	f.Parent = parent
	local restrikes = opts.restrike or 1
	task.spawn(function()
		for _ = 1, restrikes do
			task.wait(life * 0.4)
			if not f.Parent then
				return
			end
			strike()
		end
		task.wait(life * 0.35)
		for step = 1, 3 do
			if not f.Parent then
				return
			end
			for i = 1, n do
				cores[i].Transparency = step / 3
				sheaths[i].Transparency = 0.45 + 0.55 * step / 3
			end
			task.wait(0.025)
		end
		f:Destroy()
	end)
	Debris:AddItem(f, life * 2 + 0.6)
	return f
end

-- crackling arcs: chords across a sphere's surface, or (outward = true) forks bursting out of its centre
function FX.arcs(parent, center, radius, opts)
	opts = opts or {}
	for _ = 1, opts.count or 2 do
		local d1 = randUnit()
		local a, b
		if opts.outward then
			a = center + d1 * radius * 0.2
			b = center + (d1 + randUnit() * 0.35).Unit * radius * rng:NextNumber(0.8, 1.3)
		else
			local d2 = (d1 + randUnit() * rng:NextNumber(0.7, 1.4)).Unit
			a, b = center + d1 * radius, center + d2 * radius
		end
		local colors = opts.colors
		FX.bolt(parent, a, b, {
			color = colors and colors[rng:NextInteger(1, #colors)] or opts.color, width = opts.width, life = opts.life,
			jag = opts.jag or 0.3, segments = opts.segments, light = opts.light,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- the ground

local function groundLook(hit)
	local mat, col = Enum.Material.Slate, Color3.fromRGB(110, 104, 98)
	if hit.Instance:IsA("Terrain") then
		-- while a void has darkened the ground on this client, use the colours it saved (GojoClient sets them)
		local c = FX.terrainOriginals and FX.terrainOriginals[hit.Material]
		if not c then
			local ok, live = pcall(function()
				return workspace.Terrain:GetMaterialColor(hit.Material)
			end)
			c = ok and live or nil
		end
		if c then
			col = c
		end
		mat = hit.Material
		if mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass then
			mat, col = Enum.Material.Ground, Color3.fromRGB(104, 84, 62) -- turf tears up as dirt
		end
	elseif hit.Instance:IsA("BasePart") then
		mat, col = hit.Instance.Material, hit.Instance.Color
	end
	return mat, col
end

-- chunks of the ground blown loose (real client physics in the Debris group, so they never block anyone)
function FX.rubble(parent, pos, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	local hit = groundHit(pos, opts.depth or 10)
	if not hit then
		return
	end
	local mat, col = groundLook(hit)
	local count = opts.count or 10
	local life = opts.life or 2.6
	for i = 1, count do
		local s = rng:NextNumber(opts.min or 0.6, opts.max or 1.7)
		local p = Instance.new("Part")
		p.Name = "Rubble"
		p.Size = Vector3.new(s, s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.7, 1.1))
		pcall(function()
			p.Material = mat
		end)
		p.Color = col:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.25))
		local ang = (i / count) * TAU + rng:NextNumber(-0.3, 0.3)
		local radial = Vector3.new(math.cos(ang), 0, math.sin(ang))
		if opts.dir then
			radial = (radial + Vector3.new(opts.dir.X, 0, opts.dir.Z) * 1.4).Unit
		end
		p.CFrame = CFrame.new(hit.Position + radial * rng:NextNumber(0, opts.radius or 3) + Vector3.yAxis * s) * CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		pcall(function()
			p.CollisionGroup = "Debris"
		end)
		p.Parent = parent
		local up = opts.up or { 25, 50 }
		local out = opts.out or { 12, 32 }
		p.AssemblyLinearVelocity = radial * rng:NextNumber(out[1], out[2]) + Vector3.yAxis * rng:NextNumber(up[1], up[2])
		p.AssemblyAngularVelocity = randUnit() * rng:NextNumber(6, 16)
		task.delay(life * rng:NextNumber(0.7, 1), function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1, Size = p.Size * 0.4 }):Play()
				Debris:AddItem(p, 0.55)
			end
		end)
	end
end

-- rocks tear loose around a point and float up while power builds; :drop(push) lets them fall (or flings them)
local Rocks = {}
Rocks.__index = Rocks
function FX.liftRocks(parent, center, radius, count)
	local self = setmetatable({ list = {}, t = 0, dead = false }, Rocks)
	local hit = groundHit(center, 12)
	if not hit or not live(parent) then
		self.dead = true
		return self
	end
	local mat, col = groundLook(hit)
	for i = 1, count do
		local s = rng:NextNumber(0.5, 1.5)
		local p = part("FloatRock", Enum.PartType.Block, Enum.Material.Slate, col:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.3)), nil)
		pcall(function()
			p.Material = mat
		end)
		p.Size = Vector3.new(s, s * rng:NextNumber(0.55, 0.9), s * rng:NextNumber(0.7, 1.1))
		p.CastShadow = true
		local ang = (i / count) * TAU + rng:NextNumber(-0.25, 0.25)
		local r = radius * rng:NextNumber(0.45, 1)
		local base = hit.Position + Vector3.new(math.cos(ang) * r, -s * 0.3, math.sin(ang) * r)
		p.CFrame = CFrame.new(base)
		p.Parent = parent
		table.insert(self.list, {
			part = p, base = base, height = rng:NextNumber(2.5, 8), delay = rng:NextNumber(0, 0.35), rise = rng:NextNumber(0.7, 1.3),
			spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 1.4, phase = rng:NextNumber(0, TAU),
		})
	end
	self.conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
	task.delay(7, function()
		self:drop()
	end)
	return self
end
function Rocks:_step(dt)
	self.t += dt
	local t = self.t
	for _, r in ipairs(self.list) do
		if r.part.Parent then
			local k = math.clamp((t - r.delay) / r.rise, 0, 1)
			local ease = 1 - (1 - k) ^ 3
			local jitter = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 0.06 * k -- trembling with the pressure
			local pos = r.base + Vector3.yAxis * (r.height * ease + math.sin(t * 2.2 + r.phase) * 0.35 * k) + jitter
			r.part.CFrame = CFrame.new(pos) * CFrame.Angles(t * r.spin.X + r.phase, t * r.spin.Y, t * r.spin.Z)
		end
	end
end
function Rocks:drop(push)
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
	end
	for _, r in ipairs(self.list) do
		local p = r.part
		if p.Parent then
			p.Anchored = false
			p.CanCollide = true
			pcall(function()
				p.CollisionGroup = "Debris"
			end)
			if typeof(push) == "Vector3" then
				p.AssemblyLinearVelocity = push * rng:NextNumber(0.6, 1.2) + randUnit() * 12 + Vector3.yAxis * 10
				p.AssemblyAngularVelocity = randUnit() * 10
			end
			task.delay(rng:NextNumber(1.6, 2.6), function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
					Debris:AddItem(p, 0.55)
				end
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the Hollow Purple helix: lights spiralling round a moving point, each dragging a trail
local Helix = {}
Helix.__index = Helix
function FX.helix(parent, colors, radius, width)
	local self = setmetatable({ t = 0, radius = radius, list = {} }, Helix)
	for i, c in ipairs(colors) do
		local p = part("Helix", Enum.PartType.Ball, Enum.Material.Neon, c, nil)
		p.Size = Vector3.one * width
		p.Parent = parent
		FX.trail(p, ColorSequence.new(WHITE, c), width * 1.6, 0.35, { tail = 0, brightness = 3 })
		table.insert(self.list, { part = p, phase = (i - 1) * TAU / #colors })
	end
	return self
end
function Helix:place(pos, dir, dt)
	self.t += dt or 0
	local r, u = perp(dir)
	for _, h in ipairs(self.list) do
		if h.part.Parent then
			local a = self.t * 11 + h.phase
			h.part.CFrame = CFrame.new(pos + (r * math.cos(a) + u * math.sin(a)) * self.radius)
		end
	end
end
function Helix:destroy()
	for _, h in ipairs(self.list) do
		local tr = h.part:FindFirstChildOfClass("Trail")
		if tr then
			tr.Enabled = false
		end
		h.part.Transparency = 1
		Debris:AddItem(h.part, 0.5)
	end
	self.list = {}
end

-- a rising aura of light on a character (destroy the returned attachment to end it)
function FX.aura(rootPart, color, color2, rate)
	local a = Instance.new("Attachment")
	a.Name = "GojoFXAura"
	a.Position = Vector3.new(0, -2.6, 0)
	a.Parent = rootPart
	emitter(a, {
		Texture = TEX.glow, Color = cs(color, color2), Rate = rate or 50, Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(5, 11), SpreadAngle = Vector2.new(22, 22), EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-1.8),
		Size = nsk({ { 0, 0.4 }, { 0.3, 1.1 }, { 1, 0 } }), Transparency = alpha({ { 0, 0.7 }, { 0.3, 0.35 }, { 1, 1 } }), Brightness = 2,
	})
	emitter(a, {
		Texture = TEX.star, Color = cs(WHITE, color), Rate = (rate or 50) * 0.4, Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Top,
		Size = nsk({ { 0, 0.5 }, { 1, 0 } }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Brightness = 2,
	})
	return a
end

---------------------------------------------------------------------------------------------------
-- Unlimited Void

-- "infinite information": hyperspace. Long, thin streaks of light laid out round the view axis rush at the camera
-- and past it, so whichever way it looks the stars stream out of the centre of the screen. They live in camera
-- space (re-placed every render step, after the camera has moved) plus a sprinkle of glinting particle flecks.
local Warp = {}
Warp.__index = Warp
local warpCount = 0
local WARP_FAR = -190
function FX.warpField(parent, count)
	warpCount += 1
	local self = setmetatable({ list = {}, parts = {}, cfs = {}, intensity = 0, boost = 0, bind = "GojoWarp" .. warpCount }, Warp)
	local colors = { WHITE, WHITE, Color3.fromRGB(205, 230, 255), Color3.fromRGB(160, 200, 255), Color3.fromRGB(215, 185, 255) }
	for i = 1, count or 110 do
		local p = part("WarpStreak", Enum.PartType.Block, Enum.Material.Neon, colors[rng:NextInteger(1, #colors)], nil)
		local w = rng:NextNumber(0.035, 0.11)
		local L = rng:NextNumber(9, 30)
		p.Size = Vector3.new(w, w, L)
		p.Transparency = 1
		p.Parent = parent
		local st = { part = p, len = L }
		self:_spawn(st, rng:NextNumber(WARP_FAR, 0))
		self.list[i] = st
		self.parts[i] = p
		self.cfs[i] = CFrame.identity
	end
	-- glinting flecks riding the same rush
	local host = part("WarpFlecks", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
	host.Transparency = 1
	host.Size = Vector3.new(200, 120, 8)
	host.Parent = parent
	self.host = host
	self.flecks = emitter(host, {
		Texture = TEX.star, EmissionDirection = Enum.NormalId.Back, Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 230, 255)),
		Speed = NumberRange.new(110, 190), Lifetime = NumberRange.new(0.6, 0.9), Size = nsk({ { 0, 0.3 }, { 1, 1.6 } }),
		Transparency = alpha({ { 0, 1 }, { 0.2, 0 }, { 1, 0 } }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		Brightness = 3,
	})
	self.last = os.clock()
	RunService:BindToRenderStep(self.bind, Enum.RenderPriority.Camera.Value + 3, function()
		self:_step()
	end)
	return self
end
function Warp:_spawn(st, z)
	local a = rng:NextNumber(0, TAU)
	local r = 2.5 + rng:NextNumber() ^ 0.8 * 48 -- an annulus round the view axis, denser towards the middle
	st.x, st.y = math.cos(a) * r, math.sin(a) * r * 0.65
	st.z = z or WARP_FAR
	st.speed = rng:NextNumber(280, 520)
end
function Warp:_step()
	local cam = workspace.CurrentCamera
	local now = os.clock()
	local dt = math.min(now - self.last, 0.1)
	self.last = now
	if not cam or not self.host.Parent then
		return
	end
	self.boost = math.max(self.boost - dt * 2.5, 0)
	local k = self.intensity
	local mul = (0.35 + 0.65 * k) * (1 + 2.2 * self.boost)
	local cf = cam.CFrame
	for i, st in ipairs(self.list) do
		st.z += st.speed * dt * mul
		if st.z > 6 then
			self:_spawn(st)
		end
		self.cfs[i] = cf * CFrame.new(st.x, st.y, st.z - st.len * 0.5)
		local fadeIn = math.clamp((st.z - WARP_FAR) / 70, 0, 1)
		st.part.Transparency = 1 - (0.15 + 0.75 * k + 0.1 * self.boost) * fadeIn
	end
	workspace:BulkMoveTo(self.parts, self.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	self.host.CFrame = cf * CFrame.new(0, 0, -120)
	self.flecks.Rate = 55 * k
end
-- how hard the rush runs (0..1), set every frame by the caller
function Warp:setIntensity(k)
	self.intensity = math.clamp(k, 0, 1)
end
-- a surge: everything lunges at the camera for a moment
function Warp:burst(n)
	self.boost = math.min(1, self.boost + (n or 100) / 150)
	if self.host.Parent then
		self.flecks:Emit(math.floor((n or 100) * 0.25))
	end
end
function Warp:destroy()
	pcall(function()
		RunService:UnbindFromRenderStep(self.bind)
	end)
	self.flecks.Enabled = false
	for _, p in ipairs(self.parts) do
		p:Destroy()
	end
	self.parts, self.list = {}, {}
	Debris:AddItem(self.host, 1)
end

-- rays of starlight streaming out of a point in every direction (one BulkMoveTo a frame)
local Rays = {}
Rays.__index = Rays
function FX.rays(parent, origin, reach, count, colors)
	local self = setmetatable({ origin = origin, reach = reach, list = {}, parts = {}, cfs = {} }, Rays)
	for i = 1, count do
		local w = rng:NextNumber(0.05, 0.15)
		local L = rng:NextNumber(6, 24)
		local p = part("StarRay", Enum.PartType.Block, Enum.Material.Neon, colors[rng:NextInteger(1, #colors)], nil)
		p.Size = Vector3.new(w, w, L)
		p.CFrame = CFrame.new(origin)
		p.Parent = parent
		local r = { part = p, len = L }
		self:_spawn(r, rng:NextNumber(0, reach))
		self.list[i] = r
		self.parts[i] = p
		self.cfs[i] = p.CFrame
	end
	return self
end
function Rays:_spawn(r, dist)
	local d = randUnit()
	r.dir = Vector3.new(d.X, d.Y * 0.5, d.Z).Unit -- favour the horizontal: a flattened burst reads as a galaxy
	r.dist = dist or rng:NextNumber(0, 4)
	r.speed = rng:NextNumber(150, 320)
end
function Rays:update(dt, speedMul)
	local o, reach = self.origin, self.reach
	for i, r in ipairs(self.list) do
		r.dist += r.speed * dt * (speedMul or 1)
		if r.dist > reach then
			self:_spawn(r)
		end
		local p = o + r.dir * (r.dist + r.len * 0.5)
		self.cfs[i] = CFrame.lookAt(p, p + r.dir)
		r.part.Transparency = 0.15 + 0.85 * math.clamp((r.dist / reach) ^ 2, 0, 1)
	end
	workspace:BulkMoveTo(self.parts, self.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end
-- a share of the rays snap back to the centre at once: a pulse of starlight
function Rays:burst(share)
	for _, r in ipairs(self.list) do
		if rng:NextNumber() < (share or 1) then
			self:_spawn(r, rng:NextNumber(0, 5))
		end
	end
end

-- a spiral galaxy of light turning (faster at the heart) around a centre
local Galaxy = {}
Galaxy.__index = Galaxy
function FX.galaxy(parent, center, radius, tilt, colors, count)
	local self = setmetatable({ list = {}, parts = {}, cfs = {} }, Galaxy)
	self.frame = CFrame.new(center) * CFrame.Angles(tilt or 0, 0, (tilt or 0) * 0.4)
	for i = 1, count or 130 do
		local arm = i % 3
		local k = rng:NextNumber() ^ 0.8
		local r = radius * (0.07 + 0.93 * k)
		local s = rng:NextNumber(0.25, 0.9) * (1.3 - 0.6 * k)
		local p = part("GalaxyStar", Enum.PartType.Ball, Enum.Material.Neon, colors[rng:NextInteger(1, #colors)], nil)
		p.Size = Vector3.one * s
		p.Parent = parent
		self.list[i] = {
			r = r, a0 = arm * TAU / 3 + k * 4.4 + rng:NextNumber(-0.3, 0.3), y = rng:NextNumber(-1, 1) * (1.6 - k) * 1.5,
			w = 1.7 / math.sqrt(0.15 + k),
		}
		self.parts[i] = p
		self.cfs[i] = CFrame.new(center)
	end
	return self
end
function Galaxy:update(clock)
	for i, s in ipairs(self.list) do
		local a = s.a0 + clock * s.w * 0.35
		self.cfs[i] = self.frame * CFrame.new(math.cos(a) * s.r, s.y, math.sin(a) * s.r)
	end
	workspace:BulkMoveTo(self.parts, self.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- the void shattering: glass shards of the dome blown outward, spinning, fading
function FX.shatter(parent, center, radius, opts)
	if not live(parent) then
		return
	end
	opts = opts or {}
	local shards, cfs, state = {}, {}, {}
	for i = 1, opts.count or 48 do
		local w = Instance.new("WedgePart")
		w.Name = "VoidShard"
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		local glow = i % 3 == 0
		w.Material = glow and Enum.Material.Neon or Enum.Material.Glass
		w.Color = glow and Color3.fromRGB(150, 205, 255) or Color3.fromRGB(16, 20, 44)
		w.Reflectance = glow and 0 or 0.35
		w.Transparency = glow and 0.25 or 0.1
		w.Size = Vector3.new(0.35, rng:NextNumber(3, 9), rng:NextNumber(3, 9))
		local d = randUnit()
		d = Vector3.new(d.X, math.abs(d.Y) * 0.9 + 0.05, d.Z).Unit
		local pos = center + d * radius * rng:NextNumber(0.85, 1)
		local cf = CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, 0, rng:NextNumber(0, TAU))
		w.CFrame = cf
		w.Parent = parent
		shards[i] = w
		cfs[i] = cf
		state[i] = {
			v = d * rng:NextNumber(35, 85) + Vector3.yAxis * rng:NextNumber(0, 25),
			spin = randUnit() * rng:NextNumber(2, 7), base = w.Transparency,
		}
	end
	local t = 0
	local life = opts.life or 1.6
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
		local fade = math.clamp((t - life * 0.45) / (life * 0.55), 0, 1)
		for i, w in ipairs(shards) do
			local s = state[i]
			s.v += Vector3.new(0, -55, 0) * dt
			s.v *= 1 - 0.8 * dt
			local cf = cfs[i]
			cf = (cf + s.v * dt) * CFrame.fromAxisAngle(s.spin.Unit, s.spin.Magnitude * dt)
			cfs[i] = cf
			w.Transparency = s.base + (1 - s.base) * fade
		end
		workspace:BulkMoveTo(shards, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

---------------------------------------------------------------------------------------------------
-- screen space (local player only)

local screenGui
local function screen()
	if screenGui and screenGui.Parent then
		return screenGui
	end
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GojoScreenFX"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = -1 -- under the HUD: titles and buttons stay readable through the flashes
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = pg
	return screenGui
end

function FX.flash(color, a, life)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoFlash") then
		return -- Settings menu: switched off
	end
	local g = screen()
	if not g then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or WHITE
	f.BackgroundTransparency = 1 - (a or 0.5)
	f.ZIndex = 5
	f.Parent = g
	TweenService:Create(f, TweenInfo.new(life or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, (life or 0.25) + 0.05)
end

-- anime speed lines radiating from the centre of the screen, re-drawn every couple of frames so they flicker
function FX.speedLines(duration, opts)
	opts = opts or {}
	local g = screen()
	if not g then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "SpeedLines"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.ZIndex = 3
	holder.Parent = g
	local lines = {}
	for i = 1, opts.count or 56 do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = opts.color or WHITE
		f.BackgroundTransparency = 1
		f.ZIndex = 3
		local gr = Instance.new("UIGradient")
		gr.Transparency = alpha({ { 0, 1 }, { 0.35, 0.1 }, { 1, 0 } })
		gr.Parent = f
		f.Parent = holder
		lines[i] = f
	end
	local t0 = os.clock()
	local attack, release = opts.attack or 0.03, opts.release or math.min(0.25, duration * 0.5)
	local nextDraw = 0
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local t = now - t0
		if t >= duration or not holder.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		if now < nextDraw then
			return
		end
		nextDraw = now + (opts.flicker or 1 / 30)
		local w = math.clamp(math.min(t / attack, (duration - t) / release), 0, 1)
		local a = (opts.alpha or 0.75) * w
		local sz = holder.AbsoluteSize
		local cx, cy = sz.X / 2, sz.Y / 2
		local diag = math.sqrt(cx * cx + cy * cy)
		local inner = opts.inner or 0.42
		for _, f in ipairs(lines) do
			local ang = rng:NextNumber(0, TAU)
			local r0 = diag * (inner + rng:NextNumber(0, 0.3))
			local len = diag * rng:NextNumber(0.3, 0.8)
			local mid = r0 + len / 2
			f.Position = UDim2.fromOffset(cx + math.cos(ang) * mid, cy + math.sin(ang) * mid)
			f.Size = UDim2.fromOffset(len, rng:NextNumber(1.5, opts.thick or 5))
			f.Rotation = math.deg(ang)
			f.BackgroundTransparency = 1 - a * rng:NextNumber(0.35, 1)
		end
	end)
end

-- the anime impact frame: two stark high-contrast frames, a burst of light, and speed lines
function FX.impact(opts)
	opts = opts or {}
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoFlash") then -- Settings: no impact frame, keep the lines
		if opts.lines ~= false then
			FX.speedLines(opts.lineTime or 0.4, { color = opts.lineColor, alpha = 0.85, count = 64, inner = 0.3 })
		end
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "GojoImpact"
	cc.Saturation = -1
	cc.Contrast = 2.4
	cc.Brightness = -0.12
	cc.TintColor = opts.tint or WHITE
	cc.Parent = cam
	task.delay(0.055, function()
		cc.Brightness = 0.28
		cc.Contrast = 3
		cc.TintColor = opts.tint2 or opts.tint or WHITE
	end)
	task.delay(0.11, function()
		cc:Destroy()
		FX.flash(opts.flash or WHITE, opts.flashAlpha or 0.5, opts.flashLife or 0.3)
	end)
	if opts.lines ~= false then
		FX.speedLines(opts.lineTime or 0.4, { color = opts.lineColor, alpha = 0.85, count = 64, inner = 0.3 })
	end
end

return FX
