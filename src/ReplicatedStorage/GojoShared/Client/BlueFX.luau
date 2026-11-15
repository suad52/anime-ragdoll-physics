--!nocheck
-- BlueFX: extra visual layers for Lapse Blue (the telekinetic grab). Client-only.
-- Adds ON TOP of GojoClient's own blue orb + hand beam (it never touches those).
-- Everything is anchored, non-colliding, parented under the caller's folder; per-frame work stops when
-- that folder (or the handle's own sub-folder) is destroyed, and every lookup is guarded.
--   BlueFX.grab(folder, casterCharacter, targetModel) -> handle  (handle:tick(dt), handle:release(thrown))
--   BlueFX.fizzle(folder, pos)
--   BlueFX._selfTest(folder)   (Play only: smoke-tests every API around (3000, 210, 3050))
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local VFX = nil
pcall(function()
	VFX = require(script.Parent:WaitForChild("PurpleVFX", 5))
end)

local M = {}

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	flare = "rbxasset://textures/particles/fire_sparks_main.dds",
}

local C = {
	core = Color3.fromRGB(175, 222, 255),
	blue = Color3.fromRGB(70, 150, 255),
	deep = Color3.fromRGB(30, 80, 235),
	white = Color3.fromRGB(232, 246, 255),
	rock = Color3.fromRGB(88, 92, 104),
	rockDark = Color3.fromRGB(58, 66, 92),
}

local SND = {
	whoosh = "rbxassetid://9119415101",
	swell = "rbxassetid://9043337370",
	boom = "rbxassetid://127224055692526",
	electric = "rbxassetid://1842430129",
}

local TAU = math.pi * 2
local SPHERE_D = 9 -- gravity sphere diameter around the held body
local ARM_R = 7.5 -- radius the inward spiral streams start from
local RING_R = 4.9 -- accretion ring radius

---------------------------------------------------------------------------------------------------
-- helpers
local function ns(...)
	return NumberSequence.new(...)
end

local function nsk(list)
	local k = {}
	for i, v in ipairs(list) do
		k[i] = NumberSequenceKeypoint.new(v[1], v[2])
	end
	return NumberSequence.new(k)
end

local function alive(inst)
	return typeof(inst) == "Instance" and inst.Parent ~= nil
end

local function newPart(name, shape, material, color, parent)
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
	if parent then
		p.Parent = parent
	end
	return p
end

local function hostPart(parent, pos, size)
	local p = newPart("FxHost", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.new(), nil)
	p.Transparency = 1
	p.Size = size or Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	p.Parent = parent
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LightEmission = 1
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end

local function att(parent, cf)
	local a = Instance.new("Attachment")
	if cf then
		a.CFrame = cf
	end
	a.Parent = parent
	return a
end

local function light(parent, color, brightness, range)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	return l
end

local function sound(id, parent, vol, speed)
	if not alive(parent) then
		return nil
	end
	if VFX and VFX.sound then
		local ok, s = pcall(VFX.sound, id, parent, vol, speed)
		if ok then
			return s
		end
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 400
	s.RollOffMinDistance = 30
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 8)
	return s
end

local function vfx(name, ...)
	if VFX and VFX[name] then
		local ok, r = pcall(VFX[name], ...)
		if ok then
			return r
		end
	end
	return nil
end

local function bodyPart(model)
	if not alive(model) then
		return nil
	end
	if model:IsA("BasePart") then
		return model
	end
	local p = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if p and p:IsA("BasePart") then
		return p
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function handPart(char)
	if not alive(char) then
		return nil
	end
	local p = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftLowerArm")
		or char:FindFirstChild("HumanoidRootPart")
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- two unit vectors perpendicular to dir (and to each other)
local function perpBasis(dir)
	local up = math.abs(dir.Y) > 0.95 and Vector3.xAxis or Vector3.yAxis
	local r = dir:Cross(up).Unit
	local u = r:Cross(dir).Unit
	return r, u
end

-- a CFrame at pos whose Y axis is dir (emitters with EmissionDirection Top shoot along dir)
local function yAlong(pos, dir)
	local x = dir:Cross(Vector3.yAxis)
	if x.Magnitude < 1e-3 then
		x = dir:Cross(Vector3.xAxis)
	end
	return CFrame.fromMatrix(pos, x.Unit, dir)
end

local function destroy(inst)
	if typeof(inst) == "Instance" then
		pcall(inst.Destroy, inst)
	end
end

-- a pinwheel of inward streaks: one emitter, moved round a ring and Emit()ted at each stop
local function pinwheel(emit, a, centerLocal, radius, stops, perStop, swirl, normalCF)
	if not (emit and a and a.Parent) then
		return
	end
	normalCF = normalCF or CFrame.new()
	for i = 1, stops do
		local ang = (i / stops) * TAU
		local radial = normalCF:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
		local tangent = normalCF:VectorToWorldSpace(Vector3.new(-math.sin(ang), 0, math.cos(ang)))
		local dir = (-radial * (1 - swirl) + tangent * swirl).Unit
		a.CFrame = yAlong(centerLocal + radial * radius, dir)
		emit:Emit(perStop)
	end
end

---------------------------------------------------------------------------------------------------
-- the held-body handle
local Handle = {}
Handle.__index = Handle

function M.grab(folder, casterCharacter, targetModel)
	if typeof(folder) ~= "Instance" then
		return nil
	end
	local self = setmetatable({
		t = 0,
		intro = 0,
		released = false,
		dead = false,
		lastTick = os.clock(),
		caster = casterCharacter,
		target = targetModel,
		folder = folder,
		conns = {},
	}, Handle)

	local body = bodyPart(targetModel)
	local hand = handPart(casterCharacter)
	local center = (body and body.Position) or (hand and hand.Position) or Vector3.zero
	self.center = center
	self.prevCenter = center
	self.vel = Vector3.zero
	self.handPos = (hand and hand.Position) or center

	local root = Instance.new("Folder")
	root.Name = "BlueGrabFX"
	self.root = root

	-- hub: an invisible host at the body's centre for the ring, spiral streams, tendril ends and the light
	local hub = hostPart(root, center)
	self.hub = hub
	self.light = light(hub, C.blue, 2.4, 16)

	-- 1) translucent gravity sphere (outer) + a deeper counter-rotating inner shell
	local outer = newPart("GravitySphere", Enum.PartType.Ball, Enum.Material.ForceField, C.blue, root)
	outer.Transparency = 0.3
	outer.Size = Vector3.one * 0.3
	outer.CFrame = CFrame.new(center)
	local inner = newPart("GravityInner", Enum.PartType.Ball, Enum.Material.ForceField, C.deep, root)
	inner.Transparency = 0.15
	inner.Size = Vector3.one * 0.3
	inner.CFrame = CFrame.new(center)
	self.outer, self.inner = outer, inner
	-- motes sucked in from the sphere's surface
	self.motes = emitter(outer, {
		Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 26,
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(4, 7), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = nsk({ { 0, 0.05 }, { 0.3, 0.3 }, { 1, 0 } }), Transparency = ns(0.1, 0.7), Drag = 1,
	})

	-- 2) accretion ring: a tilted, wobbling circle of light (two curved beams)
	do
		local a0, a1 = att(hub), att(hub)
		local beams = {}
		for _, sgn in ipairs({ 1, -1 }) do
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = a0, a1
			b.Color = ColorSequence.new(C.white, C.blue)
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 24
			b.Texture = TEX.spark
			b.TextureMode = Enum.TextureMode.Wrap
			b.TextureLength = 2.5
			b.TextureSpeed = 2.2 * sgn
			b.Transparency = ns(0.15)
			b.Width0, b.Width1 = 0.05, 0.05
			b:SetAttribute("Sign", sgn)
			b.Parent = hub
			table.insert(beams, b)
		end
		self.ring = { a0 = a0, a1 = a1, beams = beams }
	end

	-- 3) three spiral arms: emitters riding a rotating circle, shooting streaks inward with a swirl
	self.arms = {}
	for i = 1, 3 do
		local a = att(hub)
		local e = emitter(a, {
			Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 34,
			Lifetime = NumberRange.new(0.4, 0.48), Speed = NumberRange.new(15, 17), SpreadAngle = Vector2.new(6, 6),
			EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-1.4),
			Size = nsk({ { 0, 0.12 }, { 0.5, 0.34 }, { 1, 0.04 } }), Transparency = nsk({ { 0, 0.85 }, { 0.25, 0.05 }, { 1, 0.4 } }),
		})
		table.insert(self.arms, { att = a, emitter = e, offset = (i - 1) * TAU / 3 })
	end

	-- 4) orbiting debris: slate chips + two glowing shards on tilted rotating orbits (three with light trails)
	self.rocks = {}
	for i = 1, 7 do
		local shard = i > 5
		local s = shard and (0.25 + math.random() * 0.2) or (0.35 + math.random() * 0.55)
		local p = newPart(shard and "Shard" or "Debris", Enum.PartType.Block, shard and Enum.Material.Neon or Enum.Material.Slate,
			shard and C.core or C.rock:Lerp(C.rockDark, math.random()), root)
		p.Size = Vector3.new(s * (0.8 + math.random() * 0.5), s * (0.7 + math.random() * 0.5), s * (0.8 + math.random() * 0.5))
		p.CFrame = CFrame.new(center - Vector3.new(0, 4, 0))
		local axis = Vector3.new((math.random() - 0.5) * 1.6, 1.5, (math.random() - 0.5) * 1.6).Unit
		local u = perpBasis(axis)
		local r = {
			part = p, size = p.Size, axis = axis, u = u,
			radius = 3.4 + math.random() * 1.8,
			speed = (1.8 + math.random() * 1.8) * ((math.random() < 0.3) and -1 or 1),
			phase = math.random() * TAU, bob = math.random() * TAU,
			spin = Vector3.new(math.random() * 4 - 2, math.random() * 4 - 2, math.random() * 4 - 2),
		}
		if i == 1 or i == 3 or i == 6 then
			local t0 = att(p, CFrame.new(0, 0.22, 0))
			local t1 = att(p, CFrame.new(0, -0.22, 0))
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = t0, t1
			tr.Lifetime = 0.22
			tr.Color = ColorSequence.new(C.core, C.deep)
			tr.Transparency = ns(0.3, 1)
			tr.LightEmission = 1
			tr.LightInfluence = 0
			tr.FaceCamera = true
			tr.Parent = p
		end
		table.insert(self.rocks, r)
	end

	-- 5) caster's hand: glow shell + bright core + light + sparkles drawn into the palm
	local hh = hostPart(root, self.handPos)
	self.handHost = hh
	self.handLight = light(hh, C.blue, 3, 9)
	local glow = newPart("HandGlow", Enum.PartType.Ball, Enum.Material.ForceField, C.blue, root)
	glow.Transparency = 0.1
	glow.Size = Vector3.one * 0.3
	glow.CFrame = CFrame.new(self.handPos)
	local hcore = newPart("HandCore", Enum.PartType.Ball, Enum.Material.Neon, C.core, root)
	hcore.Size = Vector3.one * 0.1
	hcore.CFrame = CFrame.new(self.handPos)
	self.glow, self.hcore = glow, hcore
	self.handSpark = emitter(glow, {
		Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 22,
		Lifetime = NumberRange.new(0.25, 0.4), Speed = NumberRange.new(2, 4), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = nsk({ { 0, 0.05 }, { 0.4, 0.22 }, { 1, 0 } }), Transparency = ns(0.1, 0.6),
	})

	-- 6) three wavy light tendrils hand -> body (own attachment pairs so each can curve in its own plane)
	self.tendrils = {}
	for i = 1, 3 do
		local a0, a1 = att(hh), att(hub)
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.white), ColorSequenceKeypoint.new(0.5, C.blue), ColorSequenceKeypoint.new(1, C.deep),
		})
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Segments = 24
		b.Texture = TEX.spark
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 2
		b.TextureSpeed = 2.5 + i * 0.7
		b.Transparency = nsk({ { 0, 0.5 }, { 0.15, 0.1 }, { 0.85, 0.15 }, { 1, 0.6 } })
		b.Width0, b.Width1 = 0.02, 0.02
		b.Parent = hh
		table.insert(self.tendrils, {
			beam = b, a0 = a0, a1 = a1,
			phase = i * 2.1, freq = 5 + i * 1.3, amp = 1.3 + i * 0.35,
			w0 = 0.1, w1 = 0.28 + i * 0.03,
			rot = (i - 1) * TAU / 3, rotSpeed = (i % 2 == 0) and -1.7 or 1.4,
		})
	end

	root.Parent = folder

	-- the grab "snap": a ring collapsing onto the body + a low swell
	vfx("shockwave", root, center, Vector3.yAxis, 18, 2, C.blue, 0.3)
	sound(SND.swell, hub, 0.35, 1.3)

	-- lifetime: if the caller's folder (or our root) goes away, stop everything
	local wasInGame = root:IsDescendantOf(game)
	table.insert(self.conns, root.AncestryChanged:Connect(function()
		if root.Parent == nil or (wasInGame and not root:IsDescendantOf(game)) then
			self:_kill()
		end
	end))
	table.insert(self.conns, root.Destroying:Connect(function()
		self:_kill()
	end))
	-- watchdog: if the caller stops ticking without releasing, fold up on our own
	task.spawn(function()
		while not self.dead do
			task.wait(0.5)
			if self.dead then
				break
			end
			if not self.released and os.clock() - self.lastTick > 2.5 then
				pcall(self.release, self, false)
			end
		end
	end)

	pcall(self._update, self, 0)
	return self
end

function Handle:_kill()
	if self.dead then
		return
	end
	self.dead = true
	for _, c in ipairs(self.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	self.conns = {}
	destroy(self.root)
end

function Handle:_update(dt)
	dt = math.clamp(tonumber(dt) or 0, 0, 0.1)
	self.t += dt
	local t = self.t
	self.intro = math.min(1, self.intro + dt / 0.3)
	local k = 1 - (1 - self.intro) ^ 2 -- ease-out grow-in

	local body = bodyPart(self.target)
	if body then
		self.center = body.Position
	end
	local hand = handPart(self.caster)
	if hand then
		self.handPos = hand.Position
	end
	local c = self.center
	if dt > 0 then
		self.vel = self.vel:Lerp((c - self.prevCenter) / dt, 0.5)
	end
	self.prevCenter = c

	if alive(self.hub) then
		self.hub.CFrame = CFrame.new(c)
	end
	if self.light then
		self.light.Brightness = (2.2 + 0.6 * math.sin(t * 7)) * k
	end

	-- gravity sphere breathes and churns
	local D = math.max(SPHERE_D * k * (1 + 0.05 * math.sin(t * 6)), 0.2)
	if alive(self.outer) then
		self.outer.Size = Vector3.one * D
		self.outer.CFrame = CFrame.new(c) * CFrame.Angles(t * 0.6, t * 1.1, 0)
	end
	if alive(self.inner) then
		self.inner.Size = Vector3.one * math.max(D * 0.72 * (1 + 0.06 * math.sin(t * 9 + 1)), 0.2)
		self.inner.CFrame = CFrame.new(c) * CFrame.Angles(0, -t * 1.7, t * 0.9)
	end

	-- accretion ring
	local ring = self.ring
	if ring and ring.a0.Parent then
		local R = math.max(RING_R * k, 0.1)
		local rcf = CFrame.Angles(0, t * 0.8, 0) * CFrame.Angles(math.rad(72) + 0.12 * math.sin(t * 1.7), 0, 0)
		ring.a0.CFrame = rcf * CFrame.fromMatrix(Vector3.new(-R, 0, 0), Vector3.yAxis, -Vector3.xAxis)
		ring.a1.CFrame = rcf * CFrame.fromMatrix(Vector3.new(R, 0, 0), -Vector3.yAxis, Vector3.xAxis)
		for _, b in ipairs(ring.beams) do
			local cs = R * 1.333 * b:GetAttribute("Sign")
			b.CurveSize0, b.CurveSize1 = cs, cs
			local w = 0.22 * k * (0.9 + 0.2 * math.sin(t * 13))
			b.Width0, b.Width1 = w, w
		end
	end

	-- spiral arms: the emit points circle the body; each shoots streaks inward with a swirl
	for i, arm in ipairs(self.arms) do
		if arm.att.Parent then
			local ang = t * 3.2 + arm.offset
			local plane = CFrame.Angles(0.35 * math.sin(t * 0.9 + i), 0, 0.35 * math.cos(t * 0.7 + i * 2))
			local radial = plane:VectorToWorldSpace(Vector3.new(math.cos(ang), 0.25 * math.sin(t * 2 + i), math.sin(ang))).Unit
			local motion = plane:VectorToWorldSpace(Vector3.new(-math.sin(ang), 0, math.cos(ang))).Unit
			local dir = (-radial * 0.94 + motion * 0.34).Unit
			arm.att.CFrame = yAlong(radial * ARM_R * (0.6 + 0.4 * k), dir)
		end
	end

	-- orbiting debris (rises up from below during the grow-in)
	local rise = Vector3.new(0, -4 * (1 - k), 0)
	for _, r in ipairs(self.rocks) do
		if r.part.Parent then
			local a = r.phase + t * r.speed
			local off = (CFrame.fromAxisAngle(r.axis, a) * r.u) * (r.radius * (0.4 + 0.6 * k))
				+ Vector3.new(0, 0.35 * math.sin(t * 2.3 + r.bob), 0)
			r.part.CFrame = CFrame.new(c + off + rise) * CFrame.Angles(t * r.spin.X + r.phase, t * r.spin.Y, t * r.spin.Z)
		end
	end

	-- hand glow
	local hp = self.handPos
	if alive(self.handHost) then
		self.handHost.CFrame = CFrame.new(hp)
	end
	if alive(self.glow) then
		self.glow.Size = Vector3.one * math.max((1.5 + 0.18 * math.sin(t * 11)) * k, 0.1)
		self.glow.CFrame = CFrame.new(hp) * CFrame.Angles(t * 2, t * 3, 0)
	end
	if alive(self.hcore) then
		self.hcore.Size = Vector3.one * math.max(0.45 * k, 0.05)
		self.hcore.CFrame = CFrame.new(hp)
	end
	if self.handLight then
		self.handLight.Brightness = (2.6 + 0.8 * math.sin(t * 9)) * k
	end

	-- tendrils: each curves in its own rotating plane, S-waving with a little jitter
	local span = c - hp
	local L = span.Magnitude
	local show = hand ~= nil and L > 0.5
	local r1, u1
	if show then
		r1, u1 = perpBasis(span / L)
	end
	for _, td in ipairs(self.tendrils) do
		local b = td.beam
		if b.Parent then
			b.Enabled = show
			if show then
				local dir = span / L
				local th = td.rot + t * td.rotSpeed
				local side = r1 * math.cos(th) + u1 * math.sin(th)
				local rot = CFrame.fromMatrix(Vector3.zero, side, dir)
				td.a0.CFrame = rot
				td.a1.CFrame = rot
				local amp = td.amp * math.min(1, L / 10) * k
				local jit = (math.random() - 0.5) * 0.45
				b.CurveSize0 = (math.sin(t * td.freq + td.phase) + jit) * amp
				b.CurveSize1 = (math.sin(t * td.freq * 1.3 + td.phase + 1.9) - jit) * amp
				local flick = 0.85 + 0.3 * math.random()
				b.Width0 = td.w0 * k * flick
				b.Width1 = td.w1 * k * flick
			end
		end
	end
end

function Handle:tick(dt)
	if self.dead or self.released then
		return
	end
	self.lastTick = os.clock()
	if not alive(self.root) then
		self:_kill()
		return
	end
	self:_update(dt)
end

-- the throw/drop direction: replicated velocity, then measured motion, then away from the caster's hand
function Handle:_throwDir()
	local body = bodyPart(self.target)
	if body then
		local ok, v = pcall(function()
			return body.AssemblyLinearVelocity
		end)
		if ok and typeof(v) == "Vector3" and v.Magnitude > 6 then
			return v.Unit, v.Magnitude
		end
	end
	if self.vel.Magnitude > 6 then
		return self.vel.Unit, self.vel.Magnitude
	end
	local away = self.center - self.handPos
	if away.Magnitude > 0.5 then
		return away.Unit, 0
	end
	return Vector3.zAxis, 0
end

function Handle:release(thrown)
	if self.released or self.dead then
		return
	end
	self.released = true
	local root = self.root
	if not alive(root) then
		self:_kill()
		return
	end

	-- stop the streams; one last gulp of motes and spiral streaks into the body
	for _, arm in ipairs(self.arms) do
		arm.emitter.Enabled = false
	end
	pcall(function()
		self.motes.Rate = 0
		self.motes:Emit(30)
		self.handSpark.Enabled = false
		local arm = self.arms[1]
		pinwheel(arm.emitter, arm.att, Vector3.zero, ARM_R * 0.8, 10, 3, 0.35)
	end)

	-- snapshot where everything is, then collapse it into the body
	local c0 = self.center
	local snaps = {}
	for _, r in ipairs(self.rocks) do
		if r.part.Parent then
			table.insert(snaps, { part = r.part, off = r.part.Position - c0, size = r.part.Size, spin = r.spin })
		end
	end
	local D0 = alive(self.outer) and self.outer.Size.X or SPHERE_D
	local Di = alive(self.inner) and self.inner.Size.X or SPHERE_D * 0.7
	local G0 = alive(self.glow) and self.glow.Size.X or 1.5
	local tw = {}
	for i, td in ipairs(self.tendrils) do
		tw[i] = { td.beam.Width0, td.beam.Width1, td.beam.CurveSize0, td.beam.CurveSize1 }
	end
	sound(SND.electric, self.hub, 0.25, 1.6)

	local COLLAPSE = 0.2
	local POST = thrown and 0.75 or 0.35
	local relT = 0
	local phase = "collapse"
	local follower, fTrail, fEmit, lastPos
	local conn

	local function snap()
		local c = self.center
		for _, s in ipairs(snaps) do
			destroy(s.part)
		end
		for _, inst in ipairs({ self.outer, self.inner, self.glow, self.hcore, self.handHost }) do
			destroy(inst)
		end
		if self.ring then
			for _, b in ipairs(self.ring.beams) do
				destroy(b)
			end
		end
		if self.light then
			self.light.Enabled = false
		end
		local fx = self.folder
		if not alive(fx) then
			return
		end
		vfx("flash", fx, c, thrown and 3.4 or 2.2, C.white, 0.25)
		if thrown then
			local dir = self:_throwDir()
			vfx("shockwave", fx, c, dir, 1.5, 14, C.blue, 0.35)
			vfx("shockwave", fx, c, dir, 1, 8, C.white, 0.22)
			vfx("burst", fx, c, C.core, 40, 0.6, 45)
			-- a cone of streaks blasted along the throw
			local host = vfx("anchor", fx, c, 2)
			if host then
				local a = att(host, yAlong(Vector3.zero, dir))
				local e = emitter(a, {
					Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 0,
					Lifetime = NumberRange.new(0.18, 0.32), Speed = NumberRange.new(55, 90), SpreadAngle = Vector2.new(14, 14),
					EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityParallel,
					Squash = ns(-2), Size = ns(0.45, 0.05), Transparency = ns(0, 0.6), Drag = 5,
				})
				e:Emit(30)
				sound(SND.boom, host, 0.5, 1.35)
			end
			-- a streak that rides the body for a moment: trail + backward-spraying sparks
			if alive(self.root) then
				follower = hostPart(self.root, c)
				local side = perpBasis(dir)
				follower.CFrame = CFrame.fromMatrix(c, side, dir)
				local t0 = att(follower, CFrame.new(1.1, 0, 0))
				local t1 = att(follower, CFrame.new(-1.1, 0, 0))
				fTrail = Instance.new("Trail")
				fTrail.Attachment0, fTrail.Attachment1 = t0, t1
				fTrail.Lifetime = 0.35
				fTrail.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, C.white), ColorSequenceKeypoint.new(0.4, C.blue), ColorSequenceKeypoint.new(1, C.deep),
				})
				fTrail.Transparency = nsk({ { 0, 0.1 }, { 1, 1 } })
				fTrail.WidthScale = nsk({ { 0, 1 }, { 1, 0 } })
				fTrail.LightEmission = 1
				fTrail.LightInfluence = 0
				fTrail.FaceCamera = true
				fTrail.Parent = follower
				local ea = att(follower)
				fEmit = emitter(ea, {
					Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 70,
					Lifetime = NumberRange.new(0.18, 0.28), Speed = NumberRange.new(8, 14), SpreadAngle = Vector2.new(25, 25),
					EmissionDirection = Enum.NormalId.Bottom, Orientation = Enum.ParticleOrientation.VelocityParallel,
					Squash = ns(-1.5), Size = ns(0.35, 0), Transparency = ns(0.1, 0.8),
				})
				lastPos = c
			end
		else
			vfx("burst", fx, c, C.blue, 14, 0.5, 14)
			local host = vfx("anchor", fx, c, 2)
			if host then
				sound(SND.whoosh, host, 0.3, 1.5)
			end
		end
	end

	local function step(dt)
		dt = math.clamp(dt, 0, 0.1)
		relT += dt
		local body = bodyPart(self.target)
		if body then
			self.center = body.Position
		end
		local c = self.center
		if dt > 0 then
			self.vel = self.vel:Lerp((c - self.prevCenter) / dt, 0.5)
		end
		self.prevCenter = c
		if alive(self.hub) then
			self.hub.CFrame = CFrame.new(c)
		end
		if phase == "collapse" then
			local k = math.min(1, relT / COLLAPSE)
			local e = k * k -- accelerate into the body
			for _, s in ipairs(snaps) do
				if s.part.Parent then
					s.part.Size = s.size * (1 - 0.8 * e)
					s.part.CFrame = CFrame.new(c + s.off * (1 - e)) * CFrame.Angles(relT * s.spin.X * 6, relT * s.spin.Y * 6, 0)
				end
			end
			local swell = 1 + 0.12 * math.sin(math.min(k * 3, 1) * math.pi) -- a quick flex before the crush
			if alive(self.outer) then
				self.outer.Size = Vector3.one * math.max(D0 * swell * (1 - e), 0.2)
				self.outer.Transparency = 0.3 + 0.4 * e
				self.outer.CFrame = CFrame.new(c) * CFrame.Angles(relT * 6, relT * 9, 0)
			end
			if alive(self.inner) then
				self.inner.Size = Vector3.one * math.max(Di * (1 - e), 0.2)
				self.inner.CFrame = CFrame.new(c)
			end
			local ring = self.ring
			if ring and ring.a0.Parent then
				local R = math.max(RING_R * (1 - e), 0.1)
				local rcf = CFrame.Angles(0, relT * 10, 0) * CFrame.Angles(math.rad(72), 0, 0)
				ring.a0.CFrame = rcf * CFrame.fromMatrix(Vector3.new(-R, 0, 0), Vector3.yAxis, -Vector3.xAxis)
				ring.a1.CFrame = rcf * CFrame.fromMatrix(Vector3.new(R, 0, 0), -Vector3.yAxis, Vector3.xAxis)
				for _, b in ipairs(ring.beams) do
					if b.Parent then
						local cs = R * 1.333 * b:GetAttribute("Sign")
						b.CurveSize0, b.CurveSize1 = cs, cs
					end
				end
			end
			for i, td in ipairs(self.tendrils) do
				local b = td.beam
				if b.Parent and tw[i] then
					b.Width0, b.Width1 = tw[i][1] * (1 - k), tw[i][2] * (1 - k)
					b.CurveSize0, b.CurveSize1 = tw[i][3] * (1 - k), tw[i][4] * (1 - k)
				end
			end
			if alive(self.glow) then
				self.glow.Size = Vector3.one * math.max(G0 * (1 - e), 0.1)
			end
			if k >= 1 then
				for _, td in ipairs(self.tendrils) do
					destroy(td.beam)
				end
				phase = "post"
				relT = 0
				snap()
			end
		else
			if follower and follower.Parent then
				local d = c - (lastPos or c)
				if d.Magnitude > 0.05 then
					local dir = d.Unit
					local side = perpBasis(dir)
					follower.CFrame = CFrame.fromMatrix(c, side, dir)
				else
					follower.CFrame = follower.CFrame.Rotation + c
				end
				lastPos = c
				if relT > POST - 0.3 then
					if fEmit then
						fEmit.Enabled = false
					end
					if fTrail then
						fTrail.Enabled = false
					end
				end
			end
			if relT >= POST then
				if conn then
					conn:Disconnect()
				end
				self:_kill()
			end
		end
	end

	conn = RunService.Heartbeat:Connect(function(dt)
		if self.dead then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[BlueFX] release step failed: " .. tostring(err))
			if conn then
				conn:Disconnect()
			end
			self:_kill()
		end
	end)
	table.insert(self.conns, conn)
end

---------------------------------------------------------------------------------------------------
-- Q with nothing to grab: a small inward vortex puff
function M.fizzle(folder, pos)
	if typeof(folder) ~= "Instance" or typeof(pos) ~= "Vector3" then
		return
	end
	local root = Instance.new("Folder")
	root.Name = "BlueFizzleFX"
	local host = hostPart(root, pos)
	local sph = newPart("FizzleSphere", Enum.PartType.Ball, Enum.Material.ForceField, C.blue, root)
	sph.Size = Vector3.one * 4.5
	sph.Transparency = 0.2
	sph.CFrame = CFrame.new(pos)
	local core = newPart("FizzleCore", Enum.PartType.Ball, Enum.Material.Neon, C.core, root)
	core.Size = Vector3.one * 0.15
	core.CFrame = CFrame.new(pos)
	local l = light(host, C.blue, 2.5, 8)
	-- surface motes pulled in
	local shell = hostPart(root, pos, Vector3.one * 5)
	shell.Shape = Enum.PartType.Ball
	local motes = emitter(shell, {
		Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 0,
		Lifetime = NumberRange.new(0.25, 0.32), Speed = NumberRange.new(9, 12), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Size = nsk({ { 0, 0.08 }, { 0.4, 0.28 }, { 1, 0 } }), Transparency = ns(0.1, 0.5),
	})
	-- a pinwheel of swirling streaks
	local a = att(host)
	local swirl = emitter(a, {
		Texture = TEX.spark, Color = ColorSequence.new(C.white, C.blue), Rate = 0,
		Lifetime = NumberRange.new(0.22, 0.28), Speed = NumberRange.new(11, 13), SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = ns(-1.4),
		Size = ns(0.22, 0.05), Transparency = nsk({ { 0, 0.6 }, { 0.3, 0 }, { 1, 0.5 } }),
	})
	root.Parent = folder
	pcall(function()
		motes:Emit(26)
		pinwheel(swirl, a, Vector3.zero, 3.2, 8, 3, 0.45, CFrame.Angles(math.rad(15), 0, 0))
	end)
	vfx("shockwave", root, pos, Vector3.yAxis, 7, 0.5, C.blue, 0.3)
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(sph, info, { Size = Vector3.one * 0.3, Transparency = 0.6 }):Play()
	TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 0.6 }):Play()
	sound(SND.whoosh, host, 0.35, 1.6)
	task.delay(0.3, function()
		if not alive(root) then
			return
		end
		destroy(sph)
		destroy(core)
		pcall(function()
			l.Brightness = 0
		end)
		vfx("flash", root, pos, 1.3, C.white, 0.2)
		vfx("burst", root, pos, C.core, 10, 0.35, 12)
	end)
	Debris:AddItem(root, 1.6)
end

---------------------------------------------------------------------------------------------------
-- Play-only smoke test: a fake caster hand and a fake held torso near (3000, 210, 3050)
function M._selfTest(folder)
	folder = (typeof(folder) == "Instance") and folder or workspace
	local base = Vector3.new(3000, 210, 3050)
	local test = Instance.new("Folder")
	test.Name = "BlueFXSelfTest"
	test.Parent = folder
	local caster = Instance.new("Model")
	caster.Name = "TestCaster"
	local hand = newPart("LeftHand", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.fromRGB(240, 200, 170), caster)
	hand.Size = Vector3.new(0.6, 0.6, 0.6)
	hand.CFrame = CFrame.new(base + Vector3.new(-8, 0, 0))
	caster.Parent = test
	local target = Instance.new("Model")
	target.Name = "TestTarget"
	local ut = newPart("UpperTorso", Enum.PartType.Block, Enum.Material.SmoothPlastic, Color3.fromRGB(90, 90, 100), target)
	ut.Size = Vector3.new(2, 1.6, 1)
	ut.CFrame = CFrame.new(base)
	target.Parent = test
	local report, seen = {}, {}
	local function try(name, fn, ...)
		local ok, r = pcall(fn, ...)
		if not seen[name] or not ok then
			if not (seen[name] == "ERR") then
				table.insert(report, name .. "=" .. (ok and "ok" or ("ERR " .. tostring(r))))
			end
			seen[name] = ok and "ok" or "ERR"
		end
		return ok and r or nil
	end
	task.spawn(function()
		-- held, then thrown
		local h = try("grab", M.grab, test, caster, target)
		local t0 = os.clock()
		while h and os.clock() - t0 < 2 do
			local dt = task.wait()
			local tt = os.clock() - t0
			ut.CFrame = CFrame.new(base + Vector3.new(0, math.sin(tt * 2) * 0.8, 0))
			hand.CFrame = CFrame.new(base + Vector3.new(-8, 0.5 * math.sin(tt * 3), 0))
			try("tick", h.tick, h, dt)
		end
		if h then
			try("release(true)", h.release, h, true)
		end
		local t1 = os.clock()
		while os.clock() - t1 < 1.2 do
			local dt = task.wait()
			ut.CFrame = ut.CFrame + Vector3.new(60 * dt, 6 * dt, 0)
		end
		-- fizzle
		try("fizzle", M.fizzle, test, base + Vector3.new(-4, 0, 6))
		-- held briefly, then dropped
		ut.CFrame = CFrame.new(base)
		local h2 = try("grab2", M.grab, test, caster, target)
		local t2 = os.clock()
		while h2 and os.clock() - t2 < 0.8 do
			try("tick2", h2.tick, h2, task.wait())
		end
		if h2 then
			try("release(false)", h2.release, h2, false)
		end
		task.wait(2)
		print("[BlueFX] self-test: " .. table.concat(report, ", "))
		destroy(test)
	end)
	return test
end

return M
