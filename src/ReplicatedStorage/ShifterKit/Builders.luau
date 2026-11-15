--!nocheck
-- ShifterKit.Builders (client): the big set pieces every client draws for itself, built from parts.
--   B.founder    the Founding Titan: a spine of vertebrae rising out of the ground behind the territory and humping over
--                it, ribs planted round it like a centipede's legs, skeletal arms clawing the ground in front, and a huge
--                skull with long dark hair and pale burning eyes. ~260 anchored parts; the head breathes on its own.
--   B.marcher    a skinless giant of the wall (raw muscle, pale tendons, a lipless grin), posed by the caller each frame.
--   B.mushroom   the thermal blast's cloud: a fireball that burns out inside a soft column and cap of smoke.
--   B.storm      the boiling ceiling the lightning falls out of.
--   B.steamCloud a burst of steam a body changes inside; dense for a moment, then it thins out.
-- Everything is anchored, non-colliding and non-queryable, and every builder cleans up after itself (Debris, or its
-- own Heartbeat loop, which ends when its model leaves the world).
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local B = {}
local R = math.rad
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local UP = Vector3.yAxis
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local MOVE = Enum.BulkMoveMode.FireCFrameChanged

local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

local function ck(t, c)
	return ColorSequenceKeypoint.new(t, c)
end

-- kind: "block" (default), "ball", "rod" (a Cylinder, axis X), "wedge", "ell" (a block with a sphere mesh)
local function part(parent, name, kind, size, color, material, transparency)
	local p = kind == "wedge" and Instance.new("WedgePart") or Instance.new("Part")
	if kind == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Name = name
	p.Size = V(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = material or SMOOTH
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if kind == "ell" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = parent
	return p
end
B.part = part

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = parent
	return e
end
B.emitter = emitter

-- a Cylinder from a to b (its axis is X); safe for vertical spans
local function rodCF(a, b)
	local mid, dir = (a + b) / 2, b - a
	local up = math.abs(dir.Unit:Dot(UP)) > 0.995 and Vector3.zAxis or UP
	return CFrame.lookAt(mid, b, up) * ANG(0, R(90), 0)
end

-- a block whose length (Z) runs from a to b
local function slabCF(a, b)
	local dir = b - a
	local up = math.abs(dir.Unit:Dot(UP)) > 0.995 and Vector3.zAxis or UP
	return CFrame.lookAt((a + b) / 2, b, up)
end

-- any triangle as two WedgeParts: returns size1, cf1, size2, cf2 (X of each size = thickness, filled in by the caller)
local function triangle(a, b, c)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return V(0, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back),
		V(0, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- points every `step` studs along a Catmull-Rom curve through ctrl[2]..ctrl[#ctrl-1]
local function alongCurve(ctrl, step)
	local dense = {}
	for i = 2, #ctrl - 2 do
		for s = 0, 15 do
			table.insert(dense, catmull(ctrl[i - 1], ctrl[i], ctrl[i + 1], ctrl[i + 2], s / 16))
		end
	end
	table.insert(dense, ctrl[#ctrl - 1])
	local cum = { 0 }
	for i = 2, #dense do
		cum[i] = cum[i - 1] + (dense[i] - dense[i - 1]).Magnitude
	end
	local out, j = {}, 2
	for n = 0, math.floor(cum[#cum] / step) do
		local s = n * step
		while j < #dense and cum[j] < s do
			j += 1
		end
		local a = math.clamp((s - cum[j - 1]) / math.max(cum[j] - cum[j - 1], 1e-6), 0, 1)
		table.insert(out, dense[j - 1]:Lerp(dense[j], a))
	end
	return out
end

---------------------------------------------------------------------------------------------------
-- the Founding Titan. Local space: origin on the ground at the cast point, -Z forward (the way the caster faced); the
-- caster waits under the ribs at the origin. The skull's centre stays at (0, 106, -92), where the client roars from.
--   obj:place(rootCFrame, jawDegrees)  moves it (the body only when the root changes; the head every call)
--   obj:setEyes(k)                     0..1 (more flares the light)
--   obj:collapse(t)                    crumbles it from the head back and removes it
--   obj:destroy()                      removes it now
--   obj:tick(now)                      the idle breathing (the builder runs it itself at 30 Hz; exposed for tests)
-- extras: obj.skullLocal (CFrame), obj.skullOffset (Vector3), obj.height, obj.partCount, obj:skullPosition()
function B.founder(parent, palette, seed)
	local rng = Random.new(seed or 1)
	local model = Instance.new("Model")
	model.Name = "FoundingConstruct"
	local obj = {
		model = model, parts = {}, locals = {}, body = {}, head = {}, jaw = {}, hair = {}, eyes = {}, halos = {}, glows = {},
		jawDeg = 0, t0 = os.clock(),
	}
	local BONE, SHADE, HAIR = palette.Bone, palette.BoneShade, palette.FounderHair
	local DARK = Color3.fromRGB(14, 11, 11)
	local OLD = BONE:Lerp(SHADE, 0.45)
	local MAT = palette.BoneMaterial or SMOOTH -- (the Fighter Skins perk's crystal skeleton passes Glass)

	local function new(name, kind, size, color, material, shadow)
		local p = part(model, name, kind, size, color, material or MAT)
		p.CastShadow = shadow == true
		return p
	end
	local function add(p, cf)
		p.CFrame = cf
		table.insert(obj.parts, p)
		table.insert(obj.locals, cf)
		return #obj.parts
	end
	local function body(p, cf)
		table.insert(obj.body, add(p, cf))
		return p
	end
	local function rod(name, a, b, w, color, group)
		local p = new(name, "rod", V((b - a).Magnitude + w * 0.55, w, w), color or BONE, nil, w >= 6)
		local place = group or body
		place(p, rodCF(a, b))
		return p
	end
	local function tri(name, a, b, c, thick, color, group, shadow)
		local s1, c1, s2, c2 = triangle(a, b, c)
		local place = group or body
		local w1 = new(name, "wedge", V(thick, s1.Y, s1.Z), color, nil, shadow)
		local w2 = new(name, "wedge", V(thick, s2.Y, s2.Z), color, nil, shadow)
		return place(w1, c1), place(w2, c2)
	end

	-- the skull's frame, tilted to look down over the territory; SK scales the skull's own units
	local SK = 1.5
	local S = CF(0, 106, -92) * ANG(R(-12), 0, 0)
	local function at(x, y, z)
		return S * CF(x * SK, y * SK, z * SK)
	end
	local function sz(x, y, z)
		return V(x, y, z) * SK
	end
	local HP = at(0, -9, 13) -- the head turns on the top of the neck
	local HPi = HP:Inverse()
	local hinge = at(0, -8, 6) -- the jaw hinge, in front of the ear
	obj.hinge = hinge
	obj.skullLocal = S
	obj.skullOffset = S.Position
	local hingeRel = HPi * hinge
	local hingeInv = hinge:Inverse()
	local function head(p, cf)
		table.insert(obj.head, { i = add(p, cf), off = HPi * cf })
		return p
	end
	local function jaw(p, cf)
		table.insert(obj.jaw, { i = add(p, cf), off = hingeInv * cf })
		return p
	end

	-------------------------------------------------------------------------------- spine
	-- from the shoulders back over the hump and down into the ground far behind
	local spine = alongCurve({
		V(0, 102, -72), V(0, 100, -46), V(0, 113, -10), V(0, 112, 30), V(0, 97, 76), V(0, 65, 122), V(0, 27, 162),
		V(0, -6, 192), V(0, -34, 214), V(0, -50, 226),
	}, 11.5)
	local frames = {}
	for i, p in ipairs(spine) do
		local t = ((spine[math.min(i + 1, #spine)] - spine[math.max(i - 1, 1)])).Unit -- toward the tail
		local n = (UP - t * UP:Dot(t)).Unit
		frames[i] = CFrame.fromMatrix(p, Vector3.xAxis, n)
	end
	local RIB_FIRST, RIB_COUNT = 2, 7
	local humps = {}
	for i, f in ipairs(frames) do
		local u = (i - 1) / math.max(#frames - 1, 1)
		local D = 20 * (1 - 0.55 * u ^ 1.25)
		local H = 7 + 20 * math.exp(-((u - 0.16) / 0.22) ^ 2)
		if f.Position.Y + D * 0.5 + H > 0 then
			local len = 11.5 * 0.8
			local c = new("Vertebra", "rod", V(len, D, D), (i % 2 == 0) and BONE or OLD, nil, true)
			body(c, f * ANG(0, R(90), 0))
			-- the spinous process: a fin raked back toward the tail
			local fin = new("Spine", "wedge", V(D * 0.16, H, D * 0.5), BONE, nil, H > 12)
			body(fin, f * CF(0, D * 0.38, 0) * ANG(R(28), 0, 0) * CF(0, H / 2, 0))
			if i < RIB_FIRST or i >= RIB_FIRST + RIB_COUNT then
				local tr = new("Process", "block", V(D * 2.1, D * 0.2, D * 0.3), SHADE)
				body(tr, f * CF(0, D * 0.1, 0) * ANG(R(10), 0, 0))
			end
			if H > 20 then
				table.insert(humps, c)
			end
		end
	end

	-------------------------------------------------------------------------------- ribs
	-- planted in the ground on both sides like legs, the caster under the middle of them
	for j = 0, RIB_COUNT - 1 do
		local f = frames[RIB_FIRST + j]
		if f then
			local P = f.Position
			local W = 48 + 22 * math.sin(math.pi * (j + 0.5) / RIB_COUNT)
			local D = 20 * (1 - 0.55 * ((RIB_FIRST + j - 1) / (#frames - 1)) ^ 1.25)
			local wr = 5 + D * 0.16
			for _, s in ipairs({ -1, 1 }) do
				-- out from the spine, bowed wide, then swept back and in to a point driven into the ground
				local pts = {
					P + V(s * D * 0.4, -D * 0.1, 0),
					V(s * W * 0.55, P.Y - 5, P.Z + 12),
					V(s * W * 0.92, P.Y * 0.72, P.Z + 24),
					V(s * W * 1.0, P.Y * 0.42, P.Z + 33),
					V(s * W * 0.86, P.Y * 0.16, P.Z + 40),
					V(s * W * 0.7, -4, P.Z + 45),
				}
				for k = 1, #pts - 1 do
					rod("Rib", pts[k], pts[k + 1], wr * (1 - 0.09 * (k - 1)), (k % 2 == 0) and BONE or OLD)
				end
			end
		end
	end

	-------------------------------------------------------------------------------- neck
	local neckA, neckB = V(0, 100, -48), HP.Position
	local neckC = V(0, 104, -60)
	for k = 1, 4 do
		local t = k / 5
		local p = neckA:Lerp(neckC, t):Lerp(neckC:Lerp(neckB, t), t)
		local q = neckA:Lerp(neckC, t + 0.05):Lerp(neckC:Lerp(neckB, t + 0.05), t + 0.05)
		local D = 15 - k * 0.8
		local c = new("NeckBone", "rod", V(7.5, D, D), (k % 2 == 0) and BONE or OLD, nil, true)
		body(c, rodCF(p, q))
		local tdir = (q - p).Unit
		local n = (UP - tdir * UP:Dot(tdir)).Unit
		local fin = new("Spine", "wedge", V(2.2, 7, 6), BONE)
		body(fin, CFrame.fromMatrix(p, Vector3.xAxis, n) * CF(0, D * 0.45, 0) * ANG(R(20), 0, 0) * CF(0, 3.5, 0))
	end

	-------------------------------------------------------------------------------- arms
	for _, s in ipairs({ -1, 1 }) do
		local sh, el, wr = V(s * 46, 92, -46), V(s * 90, 66, -62), V(s * 80, 10, -128)
		tri("Scapula", V(s * 8, 109, -38), V(s * 42, 99, -50), V(s * 32, 102, -8), 2.4, SHADE, nil, true)
		rod("Clavicle", sh + V(-s * 4, 1, -4), V(s * 7, 92, -60), 4.2, OLD)
		body(new("Shoulder", "ball", V(18, 18, 18), BONE, nil, true), CF(sh))
		rod("Humerus", sh, el, 13, BONE)
		body(new("Elbow", "ball", V(16, 16, 16), OLD, nil, true), CF(el))
		local f = (wr - el).Unit
		local q = f:Cross(UP).Unit
		rod("Radius", el + q * 3.4, wr + q * 2.8, 8, BONE)
		rod("Ulna", el - q * 3.4 + V(0, 1, 0), wr - q * 2.8, 6.6, OLD)
		body(new("Wrist", "ball", V(11, 11, 11), OLD, nil, true), CF(wr))
		local fwd = V(s * 0.22, 0, -1).Unit
		local side = fwd:Cross(UP).Unit
		local palm = wr + fwd * 9 - UP * 4
		local hand = new("Hand", "block", V(20, 5, 17), BONE, nil, true)
		body(hand, CFrame.lookAt(palm, palm + fwd) * ANG(R(-12), 0, 0))
		for d = 1, 5 do
			local thumb = d == 5
			local spread = thumb and R(s * 58) or R(-(d - 2.5) * 15)
			local dir = (CFrame.fromAxisAngle(UP, spread):VectorToWorldSpace(fwd)).Unit
			local k0 = thumb and (wr + fwd * 4 - side * s * 8 - UP * 4) or (palm + fwd * 8 + side * ((d - 2.5) * 4.6) - UP * 1)
			local k1 = k0 + dir * (thumb and 11 or 16) + UP * 6
			local k2 = k1 + dir * (thumb and 9 or 12) - UP * (k1.Y + 1)
			rod("Finger", k0, k1, thumb and 4.6 or 4.4, BONE)
			rod("Claw", k1, k2, thumb and 3.8 or 3.6, OLD)
		end
	end

	-------------------------------------------------------------------------------- skull
	head(new("Cranium", "ell", sz(28, 26, 33), BONE, nil, true), at(0, 6, 4))
	head(new("Face", "block", sz(23, 11, 7), BONE, nil, true), at(0, -2.5, -11))
	for _, s in ipairs({ -1, 1 }) do
		-- a heavy brow slanting down to the middle over deep sockets: it glowers
		head(new("Brow", "block", sz(13, 4.8, 6.4), BONE, nil, true), at(s * 6.2, 6, -12.7) * ANG(0, 0, R(10 * s)))
		head(new("Socket", "block", sz(9, 6.6, 1), DARK), at(s * 6.4, 0.6, -14.6) * ANG(0, 0, R(12 * s)))
		local eye = head(new("Eye", "ball", V(2.2, 2.2, 2.2) * SK, palette.FounderEye, NEON), at(s * 6.2, 0.2, -14.9))
		table.insert(obj.eyes, eye)
		local halo = head(new("EyeGlow", "ball", V(4.2, 4.2, 4.2) * SK, palette.FounderGlow, NEON), at(s * 6.2, 0.2, -14.9))
		halo.Transparency = 1
		table.insert(obj.halos, halo)
		head(new("Cheekbone", "block", sz(4.6, 4.2, 15), BONE, nil, true), at(s * 12.8, -3.2, -5) * ANG(0, R(9 * s), 0))
	end
	tri("NoseHole", at(-2.4, -2.6, -14.75).Position, at(2.4, -2.6, -14.75).Position, at(0, -8.4, -14.75).Position, 0.6 * SK, DARK, head)
	head(new("Maxilla", "block", sz(20, 4.6, 9), OLD), at(0, -10.2, -10))
	for i = 0, 7 do
		local x = -8.4 + i * 2.4
		local z = -13.9 + (x / 8.4) ^ 2 * 3
		head(new("Tooth", "block", sz(2.2, 3.3, 2), palette.Teeth), at(x, -13.9, z) * ANG(0, -math.atan(x * 0.085), 0))
	end
	-- the jaw (relative to the hinge, so place() can drop it for the roar)
	for i = 0, 7 do
		local x = -8 + i * 2.3
		local z = -13.4 + (x / 8) ^ 2 * 3
		jaw(new("Tooth", "block", sz(2.1, 3.1, 2), palette.Teeth), at(x, -17, z) * ANG(0, -math.atan(x * 0.09), 0))
	end
	jaw(new("Jaw", "block", sz(22, 6.6, 10), BONE, nil, true), at(0, -21.2, -9.8))
	for _, s in ipairs({ -1, 1 }) do
		local a, b = at(s * 9.4, -20.5, -6.5).Position, at(s * 11.6, -8, 5.5).Position
		local ramus = new("Ramus", "block", V(4.2 * SK, 7 * SK, (b - a).Magnitude + 3 * SK), BONE, nil, true)
		jaw(ramus, slabCF(a, b))
	end

	-------------------------------------------------------------------------------- hair
	head(new("Scalp", "ell", sz(30.4, 28, 32), HAIR, Enum.Material.Fabric, true), at(0, 6.5, 12))
	local LOCKS = 16
	for i = 0, LOCKS - 1 do
		local th = R(98 + i * (164 / (LOCKS - 1))) -- from behind the right ear, round the back, to behind the left
		local back = math.max(0, -math.cos(th))
		local rootPt = at(math.sin(th) * 15, 10.5 - back * 2, 12 - math.cos(th) * 15).Position
		local out = V(math.sin(th), 0, -math.cos(th))
		local tan = V(math.cos(th), 0, math.sin(th))
		local len = (70 - 30 * back) + rng:NextNumber(-5, 6)
		local width = 7.6 + rng:NextNumber(-0.8, 0.8)
		local parting = (math.sin(th) >= 0 and 1 or -1) * back * 13 -- the back of the hair parts round the neck
		local tip = rootPt + out * (5 + rng:NextNumber(0, 4)) + V(parting + rng:NextNumber(-2, 2), -len, back * 10)
		local lock = CFrame.fromMatrix(rootPt, tan, UP)
		local lockRel = HPi * lock
		local lockInv = lock:Inverse()
		local w1, w2 = tri("Hair", rootPt - tan * width / 2, rootPt + tan * width / 2, tip, 1.5, HAIR, function(p, cf)
			p.Material = Enum.Material.Fabric
			table.insert(obj.hair, { i = add(p, cf), lock = lockRel, off = lockInv * cf, ph = i * 0.7 + rng:NextNumber(0, 1) })
			return p
		end)
		w1.CastShadow, w2.CastShadow = false, false
	end

	-------------------------------------------------------------------------------- glow, steam
	local eyeLight = Instance.new("PointLight")
	eyeLight.Color = palette.FounderGlow
	eyeLight.Range = 26
	eyeLight.Brightness = 0
	eyeLight.Shadows = false
	eyeLight.Parent = obj.eyes[1]
	obj.eyeLight = eyeLight
	for k = 1, math.min(2, #humps) do
		emitter(humps[k * 2 - 1] or humps[k], {
			Texture = SMOKE, Color = ColorSequence.new(palette.Steam), LightInfluence = 0.8, Rate = 1.2,
			Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(25, 25),
			Size = NumberSequence.new({ kp(0, 12), kp(1, 40) }), Transparency = NumberSequence.new({ kp(0, 0.7), kp(0.4, 0.75), kp(1, 1) }),
			EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-10, 10),
		})
	end

	obj.partCount = #obj.parts
	local top = 0
	for _, cf in ipairs(obj.locals) do
		top = math.max(top, cf.Position.Y)
	end
	obj.height = top

	-- fixed part lists for BulkMoveTo (one for the body, one for the head + jaw + hair)
	local bodyList, bodyCfs = table.create(#obj.body), table.create(#obj.body)
	for k, i in ipairs(obj.body) do
		bodyList[k] = obj.parts[i]
	end
	local headList, headCfs = {}, {}
	for _, g in ipairs({ obj.head, obj.jaw, obj.hair }) do
		for _, e in ipairs(g) do
			table.insert(headList, obj.parts[e.i])
		end
	end
	model.Parent = parent

	function obj:poseHead(now)
		local t = now - self.t0
		local sway = ANG(0.035 * math.sin(t * 0.45 + 0.5), 0.06 * math.sin(t * 0.31), 0.025 * math.sin(t * 0.23 + 1.3))
		local hp = self.root * HP * sway
		local n = 0
		for _, e in ipairs(self.head) do
			n += 1
			headCfs[n] = hp * e.off
		end
		local breath = 1.5 + 1.5 * math.sin(t * 0.6)
		local jc = hp * hingeRel * ANG(R(-(self.jawDeg + breath)), 0, 0)
		for _, e in ipairs(self.jaw) do
			n += 1
			headCfs[n] = jc * e.off
		end
		for _, e in ipairs(self.hair) do
			n += 1
			headCfs[n] = hp * e.lock * ANG(0.045 * math.sin(t * 0.8 + e.ph), 0, 0.02 * math.sin(t * 0.6 + e.ph)) * e.off
		end
		workspace:BulkMoveTo(headList, headCfs, MOVE)
		self.posedAt = now
	end

	function obj:place(root, jawDeg)
		if self.dead then
			return
		end
		self.jawDeg = jawDeg or 0
		if self.root ~= root then
			self.root = root
			for k, i in ipairs(self.body) do
				bodyCfs[k] = root * self.locals[i]
			end
			workspace:BulkMoveTo(bodyList, bodyCfs, MOVE)
		end
		self:poseHead(os.clock())
	end

	function obj:tick(now)
		if self.dead or not self.root then
			return
		end
		self:poseHead(now or os.clock())
	end

	function obj:skullPosition()
		return ((self.root or CFrame.identity) * S).Position
	end

	function obj:setEyes(k)
		local v = math.clamp(k, 0, 1)
		for _, e in ipairs(self.eyes) do
			e.Transparency = 1 - v
		end
		for _, h in ipairs(self.halos) do
			h.Transparency = 1 - v * 0.18
		end
		self.eyeLight.Brightness = 2.4 * math.clamp(k, 0, 1.6)
	end

	-- the idle breathing: 30 Hz, only while someone is close enough to see it
	local nextTick = 0
	obj.conn = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			obj.dead = true
			obj.conn:Disconnect()
			return
		end
		local now = os.clock()
		if obj.dead or not obj.root or now < nextTick then
			return
		end
		nextTick = now + 1 / 30
		if now - (obj.posedAt or 0) < 1 / 45 then
			return -- place() posed it this frame
		end
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - obj.root.Position).Magnitude > 2500 then
			return
		end
		obj:poseHead(now)
	end)

	-- crumbles to dust from the skull back along the spine: every bone slumps, tips and fades at its own moment
	function obj:collapse(duration)
		duration = duration or 3
		self.dead = true
		if self.conn then
			self.conn:Disconnect()
		end
		local sand = Color3.fromRGB(196, 182, 156)
		local skull = S.Position
		for i, p in ipairs(self.parts) do
			if p.Parent then
				local order = math.clamp((self.locals[i].Position - skull).Magnitude / 320, 0, 1)
				local delay = duration * 0.4 * order + rng:NextNumber(0, duration * 0.12)
				local drop = 12 + math.max(self.locals[i].Position.Y, 0) * 0.35 + rng:NextNumber(0, 14)
				local goal = p.CFrame * ANG(rng:NextNumber(-0.45, 0.45), 0, rng:NextNumber(-0.45, 0.45)) - UP * drop
				TweenService:Create(p, TweenInfo.new(math.max(duration - delay, 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay), {
					CFrame = goal, Transparency = 1, Color = sand,
				}):Play()
			end
		end
		for _, d in ipairs(self.model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		TweenService:Create(self.eyeLight, TweenInfo.new(0.6), { Brightness = 0 }):Play()
		Debris:AddItem(self.model, duration + 0.5)
	end

	function obj:destroy()
		self.dead = true
		if self.conn then
			self.conn:Disconnect()
		end
		self.model:Destroy()
	end

	return obj
end

---------------------------------------------------------------------------------------------------
-- a marching giant of the wall: skinless, raw red muscle with pale tendons, a lipless grin, steaming.
-- obj:pose(rootCFrame, phase) walks it (root = a point on the ground, facing the way it marches; one step per pi of
-- phase); obj:fade(t) dissolves it. obj.torso is its chest.
function B.marcher(parent, palette, rng, height)
	local h = height
	local MU, TE = palette.ColossusMuscle, palette.ColossusTendon
	local FI = palette.ColossusFiber or MU:Lerp(Color3.new(0, 0, 0), 0.3)
	local FAB = Enum.Material.Fabric
	local m = Instance.new("Model")
	m.Name = "WallGiant"
	local o = { model = m, h = h, phaseOffset = rng:NextNumber(0, math.pi * 2), limbs = {}, parts = {} }
	local function bp(name, size, color, material, kind)
		local p = part(m, name, kind or "block", size * h, color, material or FAB)
		p.CastShadow = false
		table.insert(o.parts, p)
		return p
	end
	o.pelvis = bp("Pelvis", V(0.25, 0.11, 0.15), MU)
	o.belly = bp("Abdomen", V(0.2, 0.13, 0.13), MU)
	o.torso = bp("Chest", V(0.3, 0.16, 0.17), MU)
	o.linea = bp("Linea", V(0.014, 0.2, 0.012), TE, SMOOTH)
	o.neck = bp("Neck", V(0.08, 0.08, 0.085), FI)
	o.head = bp("Head", V(0.125, 0.13, 0.135), MU)
	o.brow = bp("Brow", V(0.134, 0.03, 0.045), FI)
	o.mouth = bp("Mouth", V(0.098, 0.05, 0.02), palette.MouthDark or Color3.fromRGB(26, 8, 8), SMOOTH)
	o.teeth = bp("Teeth", V(0.09, 0.034, 0.024), palette.Teeth, SMOOTH)
	o.eyes = { bp("Eye", V(0.026, 0.016, 0.01), palette.ColossusEye, NEON), bp("Eye", V(0.026, 0.016, 0.01), palette.ColossusEye, NEON) }
	o.cheeks = { bp("Cheek", V(0.014, 0.075, 0.02), TE, SMOOTH), bp("Cheek", V(0.014, 0.075, 0.02), TE, SMOOTH) }
	o.traps = { bp("Trapezius", V(0.12, 0.06, 0.09), MU, nil, "wedge"), bp("Trapezius", V(0.12, 0.06, 0.09), MU, nil, "wedge") }
	for _, s in ipairs({ -1, 1 }) do
		o.limbs[s] = {
			thigh = bp("Thigh", V(0.125, 0.25, 0.13), MU),
			knee = bp("Knee", V(0.06, 0.05, 0.03), TE, SMOOTH),
			shin = bp("Shin", V(0.088, 0.235, 0.095), MU),
			foot = bp("Foot", V(0.08, 0.045, 0.15), FI),
			delt = bp("Deltoid", V(0.1, 0.095, 0.11), MU),
			upper = bp("UpperArm", V(0.082, 0.22, 0.085), MU),
			fore = bp("Forearm", V(0.072, 0.21, 0.075), MU),
			hand = bp("Hand", V(0.07, 0.09, 0.05), FI),
		}
	end
	emitter(o.torso, {
		Texture = SMOKE, Color = ColorSequence.new(palette.Steam), LightInfluence = 0.75, Rate = 2.5,
		Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(h * 0.08, h * 0.2), SpreadAngle = Vector2.new(35, 35),
		Size = NumberSequence.new({ kp(0, h * 0.12), kp(1, h * 0.4) }), Transparency = NumberSequence.new({ kp(0, 0.6), kp(1, 1) }),
		EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360),
	})
	m.Parent = parent

	local THIGH, SHIN, FOOT_H = 0.25 * h, 0.235 * h, 0.045 * h
	local LEG = THIGH + SHIN
	local HIP = FOOT_H + LEG
	local SWING = 0.48
	local list, cfs = {}, {}

	function o:pose(root, phase)
		phase += self.phaseOffset
		local n = 0
		local function set(p, cf)
			n += 1
			list[n] = p
			cfs[n] = cf
		end
		local sw = math.sin(phase)
		-- the body rides highest over a straight stance leg and dips as the stride opens
		local base = root * CF(0, -LEG * (1 - math.cos(sw * SWING)), 0)
		local hips = base * CF(0, HIP, 0) * ANG(0, sw * 0.08, 0)
		set(self.pelvis, hips * CF(0, 0.02 * h, 0))
		local spineCF = hips * ANG(R(-9), -sw * 0.16, 0)
		set(self.belly, spineCF * CF(0, 0.115 * h, 0))
		local chest = spineCF * CF(0, 0.245 * h, -0.01 * h)
		set(self.torso, chest)
		set(self.linea, chest * CF(0, -0.045 * h, -0.083 * h))
		set(self.neck, chest * CF(0, 0.105 * h, 0.005 * h))
		for k, s in ipairs({ -1, 1 }) do
			set(self.traps[k], chest * CF(s * 0.075 * h, 0.105 * h, 0.012 * h) * ANG(0, -s * R(90), 0))
		end
		local headCF = chest * CF(0, 0.178 * h, -0.016 * h) * ANG(R(5) + 0.05 * math.sin(phase * 2), 0, 0)
		set(self.head, headCF)
		set(self.brow, headCF * CF(0, 0.022 * h, -0.058 * h))
		set(self.mouth, headCF * CF(0, -0.035 * h, -0.062 * h))
		set(self.teeth, headCF * CF(0, -0.035 * h, -0.066 * h))
		for k, s in ipairs({ -1, 1 }) do
			set(self.eyes[k], headCF * CF(s * 0.03 * h, 0.003 * h, -0.066 * h))
			set(self.cheeks[k], headCF * CF(s * 0.053 * h, -0.025 * h, -0.06 * h))
		end
		for s, L in pairs(self.limbs) do
			local ph = phase + (s > 0 and math.pi or 0)
			local legSw = math.sin(ph) * SWING
			local bend = 1.05 * math.max(0, math.cos(ph)) ^ 1.5 + 0.06
			local hipJ = hips * CF(s * 0.072 * h, 0, 0) * ANG(legSw, 0, 0)
			set(L.thigh, hipJ * CF(0, -THIGH / 2, 0))
			local kneeJ = hipJ * CF(0, -THIGH, 0) * ANG(-bend, 0, 0)
			set(L.knee, kneeJ * CF(0, -0.01 * h, -0.05 * h))
			set(L.shin, kneeJ * CF(0, -SHIN / 2, 0))
			local ankle = kneeJ * CF(0, -SHIN, 0) * ANG(bend - legSw, 0, 0)
			set(L.foot, ankle * CF(0, -FOOT_H / 2, -0.035 * h))
			set(L.delt, chest * CF(s * 0.158 * h, 0.05 * h, 0))
			local shoulder = chest * CF(s * 0.168 * h, 0.035 * h, 0) * ANG(-legSw * 0.75, 0, s * R(7))
			set(L.upper, shoulder * CF(0, -0.11 * h, 0))
			local elbow = shoulder * CF(0, -0.22 * h, 0) * ANG(R(18) + math.max(0, -legSw) * 0.5, 0, 0)
			set(L.fore, elbow * CF(0, -0.105 * h, 0))
			set(L.hand, elbow * CF(0, -0.235 * h, -0.005 * h))
		end
		workspace:BulkMoveTo(list, cfs, MOVE)
	end

	function o:fade(t)
		for _, p in ipairs(self.parts) do
			TweenService:Create(p, TweenInfo.new(t), { Transparency = 1 }):Play()
		end
		for _, d in ipairs(self.model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		Debris:AddItem(self.model, t + 2)
	end

	return o
end

---------------------------------------------------------------------------------------------------
-- the thermal blast's mushroom cloud: a fireball swells and burns out while a column of smoke punches up and a cap of
-- soft, rolling smoke boils open over it, then the whole cloud stops feeding and thins away. Only the fireball is a
-- visible part (for its first ~1.5 s); the rest is particles riding two invisible carriers.
-- Returns the model and { step = function(a) } (a = 0..1 of life), so a test can pose it without Heartbeat.
function B.mushroom(parent, ground, k, palette, life)
	k = k or 1
	life = life or 8
	local m = Instance.new("Model")
	m.Name = "ThermalCloud"
	local ball = part(m, "Fireball", "ball", V(26, 26, 26) * k, palette.FireCore, NEON)
	local stem = part(m, "Stem", "block", V(20, 20, 20) * k, palette.Smoke, SMOOTH, 1)
	local cap = part(m, "Cap", "block", V(40, 20, 40) * k, palette.Smoke, SMOOTH, 1)
	for _, p in ipairs({ ball, stem, cap }) do
		p.CastShadow = false
	end
	local smokeCol = ColorSequence.new({ ck(0, palette.Fireball), ck(0.28, palette.Smoke:Lerp(palette.Fireball, 0.4)), ck(1, palette.Smoke) })
	local hot = ColorSequence.new({ ck(0, palette.FireCore), ck(0.4, palette.Fireball), ck(1, palette.Ember) })
	local soft = NumberSequence.new({ kp(0, 0.45), kp(0.15, 0.22), kp(0.6, 0.45), kp(1, 1) })
	local capSmoke = emitter(cap, {
		Texture = SMOKE, Color = smokeCol, LightEmission = 0.12, LightInfluence = 0.65, Rate = 0,
		Lifetime = NumberRange.new(3, 4.5), Speed = NumberRange.new(2, 7), SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new({ kp(0, 26 * k), kp(0.4, 44 * k), kp(1, 58 * k) }), Transparency = soft,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-14, 14), Drag = 0.8, Acceleration = V(0, 2.5, 0),
	})
	local stemSmoke = emitter(stem, {
		Texture = SMOKE, Color = smokeCol, LightEmission = 0.1, LightInfluence = 0.65, Rate = 0,
		Lifetime = NumberRange.new(2.5, 3.6), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ kp(0, 14 * k), kp(0.5, 26 * k), kp(1, 32 * k) }), Transparency = soft,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-18, 18), Drag = 1, Acceleration = V(0, 3, 0),
	})
	local capFire = emitter(cap, {
		Texture = FIRE, Color = hot, LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.7, 1.2), Speed = NumberRange.new(3, 10), SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new({ kp(0, 28 * k), kp(1, 8 * k) }), Transparency = NumberSequence.new({ kp(0, 0.25), kp(1, 1) }),
		Rotation = NumberRange.new(0, 360),
	})
	local stemFire = emitter(stem, {
		Texture = FIRE, Color = hot, LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(4, 12), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ kp(0, 18 * k), kp(1, 5 * k) }), Transparency = NumberSequence.new({ kp(0, 0.3), kp(1, 1) }),
		Rotation = NumberRange.new(0, 360),
	})
	local embers = emitter(cap, {
		Texture = SPARK, Color = ColorSequence.new(palette.FireCore, palette.Ember), LightEmission = 1, Rate = 0,
		Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(20, 45), SpreadAngle = Vector2.new(180, 180),
		Acceleration = V(0, -30, 0), Size = NumberSequence.new({ kp(0, 2.2 * k), kp(1, 0) }),
	})
	local emitters = { capSmoke, stemSmoke, capFire, stemFire, embers }

	local function step(a)
		local rise = 1 - (1 - math.min(a * 1.7, 1)) ^ 3
		local capY = (30 + 115 * rise) * k
		local w = (14 + 10 * a) * k
		stem.Size = V(w, capY, w)
		stem.CFrame = CF(ground + UP * capY / 2)
		local cw, ch = (40 + 80 * rise) * k, (22 + 26 * rise) * k
		cap.Size = V(cw, ch, cw)
		cap.CFrame = CF(ground + UP * (capY + ch * 0.1))
		local heat = math.clamp(1 - a * 2.6, 0, 1) -- fire for the first ~40% of its life
		local feed = 1 - math.clamp((a - 0.45) / 0.2, 0, 1) -- the cloud stops growing by ~65%
		capSmoke.Rate = (a > 0.06 and 11 or 0) * feed
		stemSmoke.Rate = 9 * feed
		capFire.Rate = 30 * heat
		stemFire.Rate = 18 * heat
		embers.Rate = 30 * heat + 5 * feed
		local b = math.clamp(a / 0.2, 0, 1)
		ball.Size = V(1, 1, 1) * (26 + 44 * (1 - (1 - b) ^ 2)) * k
		ball.CFrame = CF(ground + UP * (14 + 30 * b) * k)
		ball.Color = palette.FireCore:Lerp(palette.Fireball, b)
		ball.Transparency = math.clamp(0.05 + (a - 0.06) / 0.14, 0.05, 1)
	end

	step(0)
	m.Parent = parent
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not m.Parent then
			conn:Disconnect()
			return
		end
		local a = (os.clock() - t0) / life
		if a >= 1 then
			conn:Disconnect()
			for _, e in ipairs(emitters) do
				e.Enabled = false
			end
			ball.Transparency = 1
			Debris:AddItem(m, 5) -- the last smoke finishes thinning out on its own
			return
		end
		step(a)
	end)
	Debris:AddItem(m, life + 6) -- belt and braces if Heartbeat never reaches the end
	return m, { step = step }
end

---------------------------------------------------------------------------------------------------
-- a low ceiling of boiling cloud for the lightning to fall out of: a few big soft billows, gone soon after `life`
function B.storm(parent, pos, radius, color, life)
	local p = part(parent, "Storm", "block", V(radius * 2, 12, radius * 2), color, SMOOTH, 1)
	p.CFrame = CF(pos)
	p.CastShadow = false
	local e = emitter(p, {
		Texture = SMOKE, Color = ColorSequence.new(color), LightInfluence = 0.9, LightEmission = 0,
		Rate = math.clamp(radius * 0.22, 8, 36), Lifetime = NumberRange.new(2, 3.2), Speed = NumberRange.new(0.5, 3),
		SpreadAngle = Vector2.new(180, 180), Drag = 1,
		Size = NumberSequence.new({ kp(0, math.min(radius * 0.4, 70)), kp(0.5, math.min(radius * 0.6, 95)), kp(1, math.min(radius * 0.68, 100)) }),
		Transparency = NumberSequence.new({ kp(0, 1), kp(0.25, 0.35), kp(0.7, 0.45), kp(1, 1) }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-12, 12),
	})
	e:Emit(math.clamp(math.floor(radius * 0.12), 6, 18))
	task.delay(life, function()
		if e.Parent then
			e.Enabled = false
		end
	end)
	Debris:AddItem(p, life + 3.5)
	return p
end

-- a steam cloud that hides a body while it changes (Emit only): dense for a moment, then it drifts up and thins out.
-- At most 30 billows however many are asked for, so a big form never smothers the screen in white.
function B.steamCloud(parent, pos, size, count, color, life)
	local a = part(parent, "SteamCloud", "block", V(size, size * 0.5, size), color, SMOOTH, 1)
	a.CFrame = CF(pos)
	a.CastShadow = false
	local e = emitter(a, {
		Texture = SMOKE, Color = ColorSequence.new(color), LightInfluence = 0.8, LightEmission = 0.05, Rate = 0,
		Lifetime = NumberRange.new(life * 0.45, life * 0.75), Speed = NumberRange.new(size * 0.06, size * 0.22),
		SpreadAngle = Vector2.new(180, 180), Drag = 2.5, Acceleration = V(0, size * 0.06, 0),
		Size = NumberSequence.new({ kp(0, size * 0.3), kp(0.35, size * 0.5), kp(1, size * 0.62) }),
		Transparency = NumberSequence.new({ kp(0, 0.25), kp(0.2, 0.3), kp(0.55, 0.65), kp(1, 1) }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
	})
	e:Emit(math.clamp(math.floor((count or 20) * 0.55 + 0.5), 4, 30))
	Debris:AddItem(a, life + 0.5)
	return a, e
end

return B
