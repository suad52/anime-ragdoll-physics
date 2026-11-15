--!nocheck
-- StormdrawKit.Client.Dragon: the lightning dragon that carries the ultimate's dash - an eastern dragon of neon and
-- arcs, built from parts (an original design: horned head with an open, fanged jaw, a mane, trailing whiskers, and a
-- long body that corkscrews round the line the dasher flies down). Client-only: it never touches gameplay.
--   local d = Dragon.new(parent, pal, from, to)   the dash runs from -> to; past `to` the path turns up into the sky
--   d:update(headS, dt, fade)                     headS = studs the HEAD has travelled along that path; fade 0..1
--   d:headPosition() -> Vector3 ;  d:destroy()
-- Body pieces that have not left the start point yet stay hidden, so the dragon pours out of where the dash began.
-- Re-skin: the palette; Config.Dragon.Scale / BodyLength; or put your own Model (PrimaryPart facing -Z) named
-- Config.Dragon.TemplateName in ReplicatedStorage.StormdrawKit - it then rides the head's path instead.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = script.Parent.Parent
local CFG = require(Kit:WaitForChild("Config"))
local FX = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("GojoFX"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib"))

local Dragon = {}
Dragon.__index = Dragon

local UP = Vector3.yAxis
local V = Vector3.new
local R = math.rad
local rng = Random.new()

local function ellipsoid(name, size, color, parent, transparency, material)
	local p = Fx2.part(name, Enum.PartType.Block, material or Enum.Material.Neon, color, parent)
	p.Size = size
	p.Transparency = transparency or 0
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function block(name, size, color, parent, transparency)
	local p = Fx2.part(name, Enum.PartType.Block, Enum.Material.Neon, color, parent)
	p.Size = size
	p.Transparency = transparency or 0
	return p
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- the head, in its own space (forward = -Z): { part, cf, alpha } per piece
local function buildHead(parent, pal, sc)
	local pieces = {}
	local function add(part, cf)
		table.insert(pieces, { part = part, cf = CFrame.new(cf.Position * sc) * cf.Rotation, alpha = part.Transparency })
		return part
	end
	local function E(name, size, color, cf, tr)
		return add(ellipsoid(name, size * sc, color, parent, tr), cf)
	end
	local function B(name, size, color, cf, tr)
		return add(block(name, size * sc, color, parent, tr), cf)
	end
	E("Skull", V(4.4, 3.6, 6.2), pal.Bolt, CFrame.new(0, 0.2, 0), 0.1)
	local core = E("SkullCore", V(2.6, 2.2, 4.6), pal.BoltCore, CFrame.new(0, 0.2, -0.3))
	E("Snout", V(3.0, 2.0, 5.2), pal.Bolt, CFrame.new(0, -0.1, -4.0), 0.1)
	E("Nose", V(2.2, 1.2, 1.6), pal.BoltCore, CFrame.new(0, 0.25, -6.3))
	B("UpperJaw", V(2.6, 0.6, 4.6), pal.BoltDeep, CFrame.new(0, -0.9, -4.4) * CFrame.Angles(R(6), 0, 0), 0.05)
	local jaw = CFrame.new(0, -1.9, -0.9) * CFrame.Angles(R(-26), 0, 0) -- the hinge: the mouth hangs open in a roar
	B("LowerJaw", V(2.3, 0.6, 4.4), pal.BoltDeep, jaw * CFrame.new(0, 0, -2.6), 0.05)
	E("Maw", V(1.8, 1.3, 3.4), pal.BoltCore, CFrame.new(0, -1.6, -3.2), 0.2)
	for i = 1, 4 do
		for _, side in ipairs({ -1, 1 }) do
			B("Fang", V(0.3, 0.9 - i * 0.08, 0.3), pal.BoltCore, CFrame.new(side * 0.95, -1.5, -2.2 - i * 0.95))
			B("Fang", V(0.28, 0.75 - i * 0.06, 0.28), pal.BoltCore, jaw * CFrame.new(side * 0.85, 0.6, -0.9 - i * 0.82))
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		E("Eye", V(1.0, 0.8, 1.5), pal.DragonEye, CFrame.new(side * 1.55, 1.0, -1.9) * CFrame.Angles(0, R(-side * 16), 0))
		B("Brow", V(0.5, 0.5, 2.6), pal.BoltDeep, CFrame.new(side * 1.6, 1.6, -1.7) * CFrame.Angles(R(16), R(-side * 14), 0))
		-- a horn: three tapering lengths sweeping back, up and out, with one prong
		local base = V(side * 1.25, 1.7, 0.6)
		local f = CFrame.lookAt(base, base + V(side * 0.25, 0.55, 0.8))
		for i, len in ipairs({ 3.4, 2.8, 2.2 }) do
			local thick = ({ 0.85, 0.6, 0.35 })[i]
			B("Horn", V(thick, thick, len * 1.05), i == 1 and pal.Bolt or pal.BoltCore, f * CFrame.new(0, 0, -len / 2))
			f = f * CFrame.new(0, 0, -len)
			if i == 1 then
				B("Prong", V(0.4, 0.4, 1.7), pal.BoltCore, f * CFrame.Angles(R(55), 0, 0) * CFrame.new(0, 0, -0.85))
			end
			f = f * CFrame.Angles(R(14), R(side * 6), 0)
		end
		-- a whisker: an unseen bead on the snout whose trail streams back as the head moves
		local bead = E("Whisker", V(0.3, 0.3, 0.3), pal.BoltCore, CFrame.new(side * 1.5, -0.3, -6.0), 1)
		FX.trail(bead, ColorSequence.new(pal.BoltCore, pal.Bolt), 0.5 * sc, 0.5, { tail = 0.05, alpha = 0.05 })
	end
	for i = 1, 9 do -- the mane: spikes fanned round the back of the skull
		local a = (i / 9) * math.pi * 2
		local base = V(math.cos(a) * 1.9, 0.2 + math.sin(a) * 1.7, 2.2)
		local dir = V(math.cos(a) * 0.5, math.sin(a) * 0.5, 0.9).Unit
		local len = 3.4 + (i % 3) * 0.7
		B("Mane", V(0.55, 0.55, len), i % 2 == 0 and pal.Bolt or pal.BoltDeep, CFrame.lookAt(base, base + dir) * CFrame.new(0, 0, -len / 2), 0.1)
	end
	for _, x in ipairs({ -0.7, 0, 0.7 }) do
		local base = V(x, -2.3, -1.6)
		B("Beard", V(0.35, 0.35, 2.6), pal.BoltDeep, CFrame.lookAt(base, base + V(x * 0.2, -0.5, 0.85)) * CFrame.new(0, 0, -1.3), 0.1)
	end
	local light = Instance.new("PointLight")
	light.Color = pal.Bolt
	light.Range = 46
	light.Brightness = 5
	light.Shadows = false
	light.Parent = core
	local sparks = Fx2.emitter(core, {
		Texture = Fx2.Tex.flare, Color = ColorSequence.new(pal.BoltCore, pal.Bolt), LightEmission = 1, Rate = 90,
		Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(8, 30), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6 * sc), NumberSequenceKeypoint.new(1, 0) }),
	})
	return pieces, light, { sparks }
end

-- the body: { back (studs behind the head), coil (radius of its corkscrew), phase, d (thickness), pieces }
local function buildBody(parent, pal, sc, bodyLength)
	local spacing = 1.7 * sc
	local n = math.max(math.floor(bodyLength / spacing), 6)
	local segs = {}
	local emitters = {}
	for i = 1, n do
		local u = i / n
		local d
		if u < 0.15 then
			d = 2.6 + (4.0 - 2.6) * smooth(u / 0.15)
		elseif u < 0.45 then
			d = 4.0
		else
			d = 4.0 + (0.7 - 4.0) * ((u - 0.45) / 0.55) ^ 1.3
		end
		d *= sc
		local sg = { back = 3.0 * sc + i * spacing, coil = sc * 4.2 * smooth(u / 0.12) * (1 - 0.35 * u), phase = i * 0.5, d = d, pieces = {} }
		local function add(part, off, alpha)
			table.insert(sg.pieces, { part = part, off = off, alpha = alpha })
			return part
		end
		add(ellipsoid("Body", V(d, d, spacing * 2.1), pal.Bolt, parent, 0.15), CFrame.identity, 0.15)
		add(ellipsoid("BodyCore", V(d * 0.5, d * 0.5, spacing * 2.1), pal.BoltCore, parent, 0), CFrame.identity, 0)
		if i % 2 == 0 then -- the ridge of fins down its back
			add(block("Fin", V(0.22 * sc, d * 0.85, spacing * 1.5), pal.BoltDeep, parent, 0.1), CFrame.new(0, d * 0.62, 0) * CFrame.Angles(R(-22), 0, 0), 0.1)
		end
		if i % 3 == 0 then -- a crackling shell
			local shell = add(ellipsoid("Shell", V(d * 1.35, d * 1.35, spacing * 2.6), pal.Bolt, parent, 0, Enum.Material.ForceField), CFrame.identity, 0)
			if i % 6 == 0 then
				table.insert(emitters, Fx2.emitter(shell, {
					Texture = Fx2.Tex.flare, Color = ColorSequence.new(pal.BoltCore, pal.BoltDeep), LightEmission = 1, Rate = 26,
					Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(4, 18), SpreadAngle = Vector2.new(180, 180),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1 * sc), NumberSequenceKeypoint.new(1, 0) }),
				}))
			end
		end
		segs[i] = sg
	end
	return segs, emitters
end

function Dragon.new(parent, pal, from, to)
	local D = CFG.Dragon
	local self = setmetatable({}, Dragon)
	local span = to - from
	self.from, self.to = from, to
	self.length = span.Magnitude
	self.dir = self.length > 0.1 and span.Unit or V(0, 0, -1)
	self.rise = 26 -- radius of the turn up into the sky once the dash line is spent
	self.spin = 8 -- radians / second the coil turns
	self.t = 0
	self.arcAt = 0
	self.pal = pal
	self.scale = D.Scale or 1
	self.shown = {} -- [part] = the transparency last written
	self.moveParts, self.moveCFs = {}, {}
	local model = Instance.new("Model")
	model.Name = "LightningDragon"
	self.model = model
	self.pieces, self.segs, self.emitters = {}, {}, {}
	local template = Kit:FindFirstChild(D.TemplateName or "")
	if template and template:IsA("Model") and template.PrimaryPart then
		local t = template:Clone()
		for _, d in ipairs(t:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
		t.Parent = model
		self.template = t
	else
		local emitters
		self.pieces, self.light, emitters = buildHead(model, pal, self.scale)
		self.segs, self.emitters = buildBody(model, pal, self.scale, D.BodyLength or 54)
		for _, e in ipairs(emitters) do
			table.insert(self.emitters, e)
		end
	end
	-- everything starts hidden at the start point; update() shows each piece as it comes out
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not self.template then
			d.CFrame = CFrame.new(from)
			d.Transparency = 1
		end
	end
	model.Parent = parent
	return self
end

-- the path: position, tangent and normal `s` studs from the start (straight, then a quarter turn up, then straight up)
function Dragon:pathAt(s)
	local L, Rr, dir = self.length, self.rise, self.dir
	if s <= L then
		return self.from + dir * s, dir, UP
	end
	local a = (s - L) / Rr
	if a <= math.pi / 2 then
		return self.to + dir * (Rr * math.sin(a)) + UP * (Rr * (1 - math.cos(a))), dir * math.cos(a) + UP * math.sin(a),
			UP * math.cos(a) - dir * math.sin(a)
	end
	return self.to + dir * Rr + UP * (Rr + (s - L - Rr * math.pi / 2)), UP, -dir
end

function Dragon:headPosition()
	return self.headPos or self.from
end

local function show(self, part, alpha)
	if self.shown[part] ~= alpha then
		self.shown[part] = alpha
		part.Transparency = alpha
	end
end

function Dragon:update(headS, dt, fade)
	if not self.model then
		return
	end
	self.t += dt
	fade = math.clamp(fade or 0, 0, 1)
	local sc = self.scale
	local pos, tan, nrm = self:pathAt(headS)
	local right = tan:Cross(nrm)
	-- the head sways a little, so it reads as alive rather than on a rail
	local headAt = pos + (right * math.sin(self.t * 9) + nrm * math.cos(self.t * 7)) * 0.5 * sc
	local headCF = CFrame.lookAt(headAt, headAt + tan, nrm)
	self.headPos = headAt
	if self.template then
		self.template:PivotTo(headCF)
		return
	end
	local parts, cfs = self.moveParts, self.moveCFs
	local n = 0
	for _, pc in ipairs(self.pieces) do
		n += 1
		parts[n], cfs[n] = pc.part, headCF * pc.cf
		show(self, pc.part, pc.alpha + (1 - pc.alpha) * fade)
	end
	if self.light then
		self.light.Brightness = 5 * (1 - fade)
	end
	local prev = headAt - tan * (2.4 * sc) -- where the neck meets the skull
	local visible = {}
	for _, sg in ipairs(self.segs) do
		local s = headS - sg.back
		if s > 0 then
			local p, t2, n2 = self:pathAt(s)
			local r2 = t2:Cross(n2)
			local ang = sg.phase - self.t * self.spin
			local out = r2 * math.cos(ang) + n2 * math.sin(ang)
			local c = p + out * sg.coil
			local look = prev - c
			local cf = look.Magnitude > 1e-3 and CFrame.lookAt(c, prev, out) or CFrame.new(c)
			for _, pc in ipairs(sg.pieces) do
				n += 1
				parts[n], cfs[n] = pc.part, cf * pc.off
				show(self, pc.part, pc.alpha + (1 - pc.alpha) * fade)
			end
			prev = c
			table.insert(visible, c)
		else
			for _, pc in ipairs(sg.pieces) do
				show(self, pc.part, 1)
			end
		end
	end
	for i = n + 1, #parts do
		parts[i], cfs[i] = nil, nil
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- lightning along the spine and down to the ground
	if fade < 0.7 and self.t >= self.arcAt and #visible >= 2 then
		self.arcAt = self.t + 0.03
		local i = rng:NextInteger(1, #visible)
		local j = math.clamp(i + rng:NextInteger(2, 6), 1, #visible)
		if i ~= j then
			FX.bolt(self.model, visible[i], visible[j], { color = rng:NextNumber() < 0.5 and self.pal.Bolt or self.pal.BoltDeep, core = self.pal.BoltCore, width = 0.22 * sc, life = 0.07, jag = 0.3 })
		end
		if rng:NextNumber() < 0.45 then
			local from = visible[rng:NextInteger(1, #visible)]
			local hit = FX.groundHit(from, 26)
			if hit then
				FX.bolt(self.model, from, hit.Position, { color = self.pal.Bolt, core = self.pal.BoltCore, width = 0.3 * sc, life = 0.09, jag = 0.2, light = true })
				FX.glow(self.model, hit.Position, 7 * sc, self.pal.Bolt, 0.18)
			end
		end
	end
end

function Dragon:destroy()
	local m = self.model
	if not m then
		return
	end
	self.model = nil
	for _, e in ipairs(self.emitters) do
		e.Enabled = false
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("Trail") then
			d.Enabled = false
		end
	end
	Debris:AddItem(m, 0.7)
end

return Dragon
