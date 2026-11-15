--!nocheck
-- BeastConstruct: builds the nine-tailed fox (solid orange-red beast: deep chest, haunches, a fanged muzzle, glowing
-- slit eyes in black markings, black-tipped ears, clawed paws and nine thick tails) out of plain Parts and welds it to
-- a character's HumanoidRootPart (never the LowerTorso: the hidden rig's walk animation bobs and twists that part).
-- Every joint a client may animate is a Motor6D:
--   BeastBody (Hips -> Torso), BeastHead (Torso -> Head), BeastJaw (Head -> Jaw), BeastLegFL/FR/BL/BR (Torso -> leg)
--   and Tail<i>_<k> chains (k = 1 sits on the Torso; k = 2.. on the previous segment).
-- Parts the clients look up by name: Nose (the bomb's muzzle point), Paw<FL|FR|BL|BR> (footsteps), TailTip<i>.
-- Local space: -Z forward, +Y up. Designed at Morph.Scale 5 (rig scaled x5) and multiplied by Morph.Scale / 5.
local BeastConstruct = {}
local ServerStorage = game:GetService("ServerStorage")

local R = math.rad
local DESIGN_SCALE = 5
local BODY_Y = 19 -- torso centre above the ground
local BODY_Z = 4 -- the beast sits this far behind the root, so its shoulders stand over the (hidden) rig

local FUR = Color3.fromRGB(236, 100, 30)
local FUR_DARK = Color3.fromRGB(190, 64, 22)
local FUR_TIP = Color3.fromRGB(248, 132, 46)
local INK = Color3.fromRGB(22, 14, 14)
local MOUTH = Color3.fromRGB(86, 10, 14)
local FANG = Color3.fromRGB(246, 238, 220)
local EYE = Color3.fromRGB(255, 62, 28)

BeastConstruct.TAIL_COUNT = 9
local TAIL_LEN = { 12, 11 } -- segment lengths (studs at design scale); a ball rounds each joint and caps the tip
local TAIL_DIA = { 6.6, 6.2 }
local TAIL_JOINT = 7.0

local function yawOnly(cf)
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	return CFrame.lookAt(cf.Position, cf.Position + look)
end

-- a hand-made model from ServerStorage: turned to face where the character faces, dropped so its lowest point
-- rests on the ground, every loose part welded to its PrimaryPart, and the whole thing welded to the root
local function fromTemplate(character, template, hrp)
	local model = template:Clone()
	model.Name = "BeastConstruct"
	local root = model.PrimaryPart
	local hum = character:FindFirstChildOfClass("Humanoid")
	local groundY = hrp.Position.Y - ((hum and hum.HipHeight or 2) + hrp.Size.Y / 2)
	model:PivotTo(yawOnly(hrp.CFrame))
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - (box.Position.Y - size.Y / 2), 0))
	local joined = { [root] = true }
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			if j.Part0 then
				joined[j.Part0] = true
			end
			if j.Part1 then
				joined[j.Part1] = true
			end
		end
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			if not joined[p] then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = root, p
				w.Parent = p
			end
			p.Anchored = false
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "ConstructWeld"
	weld.Part0, weld.Part1 = hrp, root
	weld.C0 = hrp.CFrame:ToObjectSpace(root.CFrame)
	weld.Parent = root
	model.Parent = character
	return model
end

-- character: a player's character (already scaled to Morph.Scale). cfg: the VulpineKit Config.
-- Returns the construct Model, parented to the character.
function BeastConstruct.build(character, cfg)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local template = cfg.Morph.TemplateName and ServerStorage:FindFirstChild(cfg.Morph.TemplateName)
	if template and template:IsA("Model") and template.PrimaryPart then
		return fromTemplate(character, template, hrp)
	end
	local k = (cfg.Morph.Scale or DESIGN_SCALE) / DESIGN_SCALE
	local function T(x, y, z)
		return CFrame.new(x * k, y * k, z * k)
	end

	-- the root's height above the feet comes from the rig itself (hip height), not a ground ray, so a crater or a
	-- mid-air release can't sink the construct into the ground
	local hum = character:FindFirstChildOfClass("Humanoid")
	local rootAbove = (hum and hum.HipHeight or 2) + hrp.Size.Y / 2

	local model = Instance.new("Model")
	model.Name = "BeastConstruct"
	local rest = {} -- [part] = its CFrame in body space (origin: torso centre, at rest)
	local origin -- world CFrame of body space

	local function newPart(name, size, color, kind, material)
		local p = kind == "wedge" and Instance.new("WedgePart") or Instance.new("Part")
		if kind == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif kind == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Name = name
		p.Size = size * k
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	-- a part rigidly welded to `base`, placed at body-space `cf`
	local function piece(base, name, size, cf, color, kind, material)
		local p = newPart(name, size, color, kind, material)
		rest[p] = cf
		p.CFrame = origin * cf
		local w = Instance.new("Weld")
		w.Part0, w.Part1 = base, p
		w.C0 = rest[base]:Inverse() * cf
		w.Parent = p
		return p
	end
	-- a part hung off `base` by a Motor6D whose pivot is body-space `joint`
	local function limb(base, name, size, cf, joint, color, kind, material, motorName)
		local p = newPart(name, size, color, kind, material)
		rest[p] = cf
		p.CFrame = origin * cf
		local m = Instance.new("Motor6D")
		m.Name = motorName or name
		m.Part0, m.Part1 = base, p
		m.C0 = rest[base]:Inverse() * joint
		m.C1 = cf:Inverse() * joint
		m.Parent = base
		return p, m
	end

	-- hips: the invisible root, welded to the HumanoidRootPart
	origin = yawOnly(hrp.CFrame) * CFrame.new(0, BODY_Y * k - rootAbove, BODY_Z * k)
	local hips = newPart("Hips", Vector3.one, FUR)
	hips.Transparency = 1
	hips.Size = Vector3.one * 0.4
	rest[hips] = CFrame.identity
	hips.CFrame = origin
	local hipWeld = Instance.new("Weld")
	hipWeld.Name = "ConstructWeld"
	hipWeld.Part0, hipWeld.Part1 = hrp, hips
	hipWeld.C0 = hrp.CFrame:ToObjectSpace(hips.CFrame)
	hipWeld.Parent = hips
	model.PrimaryPart = hips

	-- body: a deep chest, a tucked loin, a sloping rump and a thick neck thrust forward ------------------------
	local torso = limb(hips, "Torso", Vector3.new(16, 16, 17), T(0, 0.5, -5) * CFrame.Angles(R(5), 0, 0), CFrame.identity, FUR, nil, nil, "BeastBody")
	piece(torso, "Loin", Vector3.new(13, 11, 13), T(0, 2.6, 8), FUR)
	piece(torso, "Rump", Vector3.new(15, 12, 9.5), T(0, 3, 15) * CFrame.Angles(R(10), 0, 0), FUR)
	-- the belly line: deepest behind the forelegs, rising to the tucked loin
	piece(torso, "Belly", Vector3.new(13, 4.6, 13), T(0, -5.2, 1.5) * CFrame.Angles(math.pi, 0, 0), FUR, "wedge")
	piece(torso, "Neck", Vector3.new(12, 16, 12), T(0, 9, -13.5) * CFrame.Angles(R(-38), 0, 0), FUR)
	-- the hunch of the shoulders: high over the forelegs, sloping down the back
	piece(torso, "Withers", Vector3.new(14, 4.5, 12), T(0, 10.2, -5.5) * CFrame.Angles(0, math.pi, 0), FUR, "wedge")

	-- head: cranium, flared cheeks, a long snout with a black nose, a hinged jaw full of fangs --------------------
	local HK = 1.15 -- the head is drawn in its own units, then enlarged as a whole
	local H = T(0, 15.5, -20) * CFrame.Angles(R(-6), 0, 0)
	local function HT(x, y, z)
		return H * T(x * HK, y * HK, z * HK)
	end
	local function HS(x, y, z)
		return Vector3.new(x, y, z) * HK
	end
	local head = limb(torso, "Head", HS(13, 10, 11), HT(0, 1.6, -2.2), H, FUR, nil, nil, "BeastHead")
	piece(head, "Muzzle", HS(6.4, 4.6, 10), HT(0, -1.4, -12.4), FUR)
	piece(head, "Bridge", HS(5.6, 3.6, 10), HT(0, 2.7, -12.4), FUR, "wedge")
	piece(head, "Nose", HS(3.2, 2.1, 1.8), HT(0, 0.5, -17.5), INK)
	piece(head, "Mouth", HS(5.6, 2.6, 9.4), HT(0, -3.9, -12.3), MOUTH)
	for _, s in ipairs({ -1, 1 }) do
		-- cheek ruffs: fur tufts swept back from the jaw line
		piece(head, "Cheek", HS(2.4, 6.4, 8.5), HT(6.9 * s, -1.6, 0.6) * CFrame.Angles(0, math.pi + R(16 * s), 0), FUR, "wedge")
		-- black markings: a slanted patch round each eye and a brow streak running up toward the ear
		local eyeCF = HT(3.9 * s, 2.8, -7.75) * CFrame.Angles(0, R(-14 * s), R(17 * s))
		piece(head, "Marking", HS(4.8, 2.8, 0.4), eyeCF * CFrame.new(0, 0, 0.05 * k), INK)
		piece(head, "Streak", HS(1.3, 4.4, 0.4), HT(5.0 * s, 4.3, -7.72) * CFrame.Angles(0, 0, R(-24 * s)), INK)
		-- glowing slit eyes
		piece(head, "Eye", HS(3.8, 1.4, 0.4), eyeCF * CFrame.new(0, 0, -0.2 * k), EYE, nil, Enum.Material.Neon)
		piece(head, "Slit", HS(0.45, 1.5, 0.2), eyeCF * CFrame.new(0, 0, -0.42 * k), INK)
		-- upper fangs, pointing down past the lip
		piece(head, "Fang", HS(1.0, 1.4, 3.2), HT(2.7 * s, -5.2, -16.4) * CFrame.Angles(R(-90), 0, 0), FANG, "wedge")
		-- tall ears: two right-angled halves make the triangle, a similar black triangle caps the top 38%
		local E = HT(4.4 * s, 6.6 + 4.4, 0.4) * CFrame.Angles(R(10), 0, R(-12 * s))
		local hw, eh, et, f = 2.6, 9.2, 1.8, 0.38
		for _, half in ipairs({ -1, 1 }) do
			local turn = CFrame.Angles(0, R(-90 * half), 0)
			piece(head, "Ear", HS(et, eh, hw), E * T(half * hw / 2 * HK, 0, 0) * turn, FUR, "wedge")
			piece(head, "EarTip", HS(et + 0.25, eh * f, hw * f), E * T(half * hw * f / 2 * HK, (eh / 2 - eh * f / 2) * HK, 0) * turn, INK, "wedge")
		end
	end
	-- the lower jaw hangs off its own hinge so the clients can open it (the bomb charges in the mouth)
	local jawJoint = HT(0, -3.6, -7.2)
	local jawRest = jawJoint * CFrame.Angles(R(-12), 0, 0)
	local jaw = limb(head, "Jaw", HS(5.2, 2.4, 9.8), jawRest * T(0, -1.1 * HK, -5.1 * HK), jawJoint, FUR, nil, nil, "BeastJaw")
	for _, s in ipairs({ -1, 1 }) do
		piece(jaw, "LowerFang", HS(0.8, 1.1, 1.8), jawRest * T(1.9 * s * HK, 1.1 * HK, -9.2 * HK) * CFrame.Angles(R(90), 0, 0), FANG, "wedge")
	end
	-- a faint red glow in front of the eyes (it lights the face only, not the body)
	local glowAt = Instance.new("Attachment")
	glowAt.Name = "EyeGlow"
	glowAt.CFrame = rest[head]:Inverse() * HT(0, 2.8, -10)
	glowAt.Parent = head
	local eyeLight = Instance.new("PointLight")
	eyeLight.Color = EYE
	eyeLight.Range = 10 * k
	eyeLight.Brightness = 1.2
	eyeLight.Shadows = false
	eyeLight.Parent = glowAt

	-- legs: each hangs off one Motor6D at the shoulder / hip; paws are flat on the ground at rest (only the
	-- forepaws carry claws: the hind paws are hidden under the body from every gameplay angle) --------------
	local function claws(leg, x, y, z, spread)
		for _, dx in ipairs({ -spread, 0, spread }) do
			piece(leg, "Claw", Vector3.new(1, 1.6, 2.8), T(x + dx, y, z), INK, "wedge")
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		local tag = s < 0 and "L" or "R"
		-- forelegs: a thick upper arm, a straight forearm, a broad paw
		local fx = 5.6 * s
		local fore = limb(torso, "BeastLegF" .. tag, Vector3.new(6.6, 11, 7.6), T(fx, -7.5, -7.6) * CFrame.Angles(R(6), 0, 0), T(fx, -3, -8), FUR)
		piece(fore, "Forearm", Vector3.new(5.4, 8.6, 5.6), T(fx, -13.8, -8.6), FUR_DARK)
		piece(fore, "PawF" .. tag, Vector3.new(7, 2.8, 8), T(fx, -17.6, -10.4), FUR_DARK)
		claws(fore, fx, -18.2, -15.6, 2)
		-- hind legs: a heavy haunch angled forward to the stifle, the shank raked back to the paw
		local hx = 6.6 * s
		local hind = limb(torso, "BeastLegB" .. tag, Vector3.new(6.6, 13, 10), T(hx, -3.2, 12.6) * CFrame.Angles(R(18), 0, 0), T(hx, 1, 14), FUR)
		piece(hind, "Shank", Vector3.new(4.4, 11, 4.8), T(hx, -12.4, 13.8) * CFrame.Angles(R(-28), 0, 0), FUR_DARK)
		piece(hind, "PawB" .. tag, Vector3.new(5.6, 2.4, 7), T(hx, -17.8, 15.2), FUR_DARK)
	end

	-- nine thick tails fanned out behind the rump, alternately high and low: each is two Motor6D segments (the
	-- clients sway them), a ball rounding the bend and a ball capping the tip, so a tail reads as one bushy tube
	local tips = {}
	local n = BeastConstruct.TAIL_COUNT
	for i = 1, n do
		local f = (i - 1) / (n - 1)
		local side = f * 2 - 1
		local high = i % 2 == 0
		local yaw = R(80 * side)
		local pitch = R(12 + 20 * math.sin(f * math.pi) + (high and 10 or 0))
		local J = T(5.2 * side, 6.2 + 1.4 * math.sin(f * math.pi), 17.8) * CFrame.Angles(0, math.pi + yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local prev = torso
		for s, len in ipairs(TAIL_LEN) do
			local d = TAIL_DIA[s]
			if high and s == 1 then
				len += 1.5
			end
			-- cylinders run along X: turn them to run along the chain
			local cf = J * T(0, 0, -len / 2) * CFrame.Angles(0, R(90), 0)
			local seg = limb(prev, "Tail" .. i .. "_" .. s, Vector3.new(len, d, d), cf, J, s == 1 and FUR or FUR_TIP, "cyl")
			seg.CastShadow = false
			J = J * T(0, 0, -len)
			local cap = piece(seg, s == #TAIL_LEN and ("TailTip" .. i) or "TailJoint", Vector3.one * (s == #TAIL_LEN and d or TAIL_JOINT), J, FUR_TIP, "ball")
			cap.CastShadow = false
			tips[i] = cap
			prev = seg
			J = J * CFrame.Angles(R(high and 20 or 26), 0, 0)
		end
	end

	-- chakra accents only: a thin flame lick off the shoulders and three of the tail tips
	local function flames(parent, rate, size)
		local e = Instance.new("ParticleEmitter")
		e.Name = "ChakraFlame"
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 196, 120), Color3.fromRGB(255, 84, 24))
		e.LightEmission = 0.6
		e.LightInfluence = 0
		e.Rate = rate
		e.Lifetime = NumberRange.new(0.45, 0.8)
		e.Speed = NumberRange.new(2 * k, 6 * k)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, 10 * k, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * k), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.Parent = parent
		return e
	end
	flames(torso, 10, 3.4)
	for _, i in ipairs({ 1, 5, 9 }) do
		flames(tips[i], 5, 2.6)
	end

	model.Parent = character
	return model
end

return BeastConstruct
