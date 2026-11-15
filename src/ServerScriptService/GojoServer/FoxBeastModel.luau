--!nocheck
-- FoxBeastModel: builds the giant nine-tailed fox (original design) out of parts and welds it to a character's root.
-- Legs, head and tails hang off Motor6Ds named Fox* so every client can animate them locally via .Transform.
-- Local space: -Z is forward, +Y is up. Body centre sits BODY_HEIGHT studs above the ground.
local FoxBeastModel = {}

local BODY_HEIGHT = 13

local AMBER = Color3.fromRGB(238, 140, 42)
local AMBER_DK = Color3.fromRGB(190, 82, 26)
local CREAM = Color3.fromRGB(255, 234, 200)
local CRIMSON = Color3.fromRGB(150, 22, 34)
local EYE = Color3.fromRGB(90, 240, 255)
local DARK = Color3.fromRGB(30, 18, 20)

local R = math.rad

local function newPart(model, name, size, color, kind, material)
	local p
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if kind == "ball" then
			p.Shape = Enum.PartType.Ball
		end
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "ellipsoid" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.Parent = model
	return p
end

-- rigidly attach `p` to `base` at offset `c0` (base-local), and place it there now
local function attach(base, p, c0)
	p.CFrame = base.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = base
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	return p
end

local function bone(base, p, name, c0)
	p.CFrame = base.CFrame * c0
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = base
	m.Part1 = p
	m.C0 = c0
	m.Parent = base
	return m
end

local function buildHead(model, torso)
	local head = newPart(model, "Head", Vector3.new(9, 7.5, 9), AMBER, "ellipsoid")
	-- head pivots at the top of the neck; the skull sits a little up and forward of it
	local pivot = CFrame.new(0, 6, -12)
	local joint = bone(torso, head, "FoxHead", pivot)
	joint.C1 = CFrame.new(0, -1, 1.5)
	head.CFrame = torso.CFrame * pivot * joint.C1:Inverse()

	for _, s in ipairs({ -1, 1 }) do
		attach(head, newPart(model, "Cheek", Vector3.new(3.6, 4.2, 5.5), CREAM, "ellipsoid"), CFrame.new(4.0 * s, -1.6, 0.4) * CFrame.Angles(0, 0, R(-22 * s)))
		attach(head, newPart(model, "CheekTuft", Vector3.new(2.2, 2.6, 3.6), CREAM, "ellipsoid"), CFrame.new(5.6 * s, -2.4, 1.4) * CFrame.Angles(0, 0, R(-48 * s)))
		-- slanted glowing eyes in dark sockets
		attach(head, newPart(model, "EyeSocket", Vector3.new(2.7, 1.3, 0.5), DARK), CFrame.new(2.3 * s, 0.8, -3.75) * CFrame.Angles(R(-12), R(14 * s), R(16 * s)))
		local eye = attach(head, newPart(model, "Eye", Vector3.new(2.1, 0.7, 0.5), EYE, nil, Enum.Material.Neon), CFrame.new(2.3 * s, 0.8, -3.95) * CFrame.Angles(R(-12), R(14 * s), R(16 * s)))
		if s == 1 then
			local l = Instance.new("PointLight")
			l.Color = EYE
			l.Range = 14
			l.Brightness = 2
			l.Shadows = false
			l.Parent = eye
		end
		-- crimson brow flames
		attach(head, newPart(model, "Brow", Vector3.new(2.6, 0.6, 1.6), CRIMSON, "ellipsoid"), CFrame.new(2.1 * s, 2.0, -3.3) * CFrame.Angles(R(-20), 0, R(24 * s)))
		-- tall ears: amber outside, crimson inside
		local ear = attach(head, newPart(model, "Ear", Vector3.new(1.3, 6.2, 3.8), AMBER, "wedge"), CFrame.new(2.9 * s, 5.4, 0.8) * CFrame.Angles(R(8), 0, R(-16 * s)))
		attach(ear, newPart(model, "EarInner", Vector3.new(1.35, 4.3, 2.3), CRIMSON, "wedge"), CFrame.new(0, -0.6, -0.55))
	end
	-- long muzzle with a cream underjaw and a dark nose
	attach(head, newPart(model, "Muzzle", Vector3.new(5, 3.8, 7.5), AMBER, "ellipsoid"), CFrame.new(0, -1.3, -5))
	attach(head, newPart(model, "Jaw", Vector3.new(4.4, 2.3, 6.6), CREAM, "ellipsoid"), CFrame.new(0, -2.4, -4.5))
	attach(head, newPart(model, "Nose", Vector3.new(1.6, 1.6, 1.6), DARK, "ball"), CFrame.new(0, -0.6, -8.6))
	attach(head, newPart(model, "Mouth", Vector3.new(3.4, 0.25, 4), DARK), CFrame.new(0, -2.05, -6.0))
	return head
end

local function buildLeg(model, torso, name, x, z, back)
	local leg = newPart(model, name, Vector3.new(3.8, 9, 4.2), AMBER, "ellipsoid")
	local m = bone(torso, leg, name, CFrame.new(x, -2.5, z))
	m.C1 = CFrame.new(0, 4.5, 0)
	leg.CFrame = torso.CFrame * m.C0 * m.C1:Inverse()
	attach(leg, newPart(model, "Paw", Vector3.new(4.3, 2.2, 5.6), AMBER_DK, "ellipsoid"), CFrame.new(0, -4.5, -0.9))
	attach(leg, newPart(model, "Sock", Vector3.new(3.9, 3, 4.3), AMBER_DK, "ellipsoid"), CFrame.new(0, -3.1, -0.2))
	if back then
		attach(leg, newPart(model, "Haunch", Vector3.new(4.6, 7.5, 7.5), AMBER, "ellipsoid"), CFrame.new(0, 2.6, 0.6))
	else
		attach(leg, newPart(model, "Shoulder", Vector3.new(4.2, 6, 5.5), AMBER, "ellipsoid"), CFrame.new(0, 2.8, 0.2))
	end
	return leg
end

local TAIL_SIZES = { 4.4, 4.9, 4.8, 4.3, 3.5, 2.4 }

local function buildTail(model, torso, i, count)
	local f = (i - 1) / (count - 1) -- 0..1 across the fan
	local yaw = R(-72 + 144 * f)
	local pitch = R(-(38 + 30 * math.sin(f * math.pi))) -- the middle tails stand tallest
	local base = newPart(model, "Tail" .. i, Vector3.one * TAIL_SIZES[1], AMBER, "ball")
	bone(torso, base, "FoxTail" .. i, CFrame.new(0, 2.5, 9.2) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
	local d = 0
	for k = 2, #TAIL_SIZES do
		d += (TAIL_SIZES[k - 1] + TAIL_SIZES[k]) * 0.36
		local curl = (k - 1) ^ 2 * 0.22 -- tips curl upward
		local color = k >= #TAIL_SIZES - 1 and CREAM or AMBER
		attach(base, newPart(model, "TailSeg", Vector3.one * TAIL_SIZES[k], color, "ball"), CFrame.new(0, curl, d))
	end
	return base
end

-- character: the player's character (root = HumanoidRootPart). Returns the model.
function FoxBeastModel.build(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "FoxBeast"

	local groundOffset = hum.HipHeight + hrp.Size.Y / 2
	local root = newPart(model, "FoxRoot", Vector3.new(1, 1, 1), AMBER)
	root.Transparency = 1
	root.CFrame = hrp.CFrame * CFrame.new(0, BODY_HEIGHT - groundOffset, 0)
	local rootWeld = Instance.new("Weld")
	rootWeld.Name = "FoxRootWeld"
	rootWeld.Part0 = hrp
	rootWeld.Part1 = root
	rootWeld.C0 = CFrame.new(0, BODY_HEIGHT - groundOffset, 0)
	rootWeld.Parent = root

	-- the torso hangs off a Motor6D too so clients can add a breathing / running bob
	local torso = newPart(model, "Torso", Vector3.new(10, 9, 20), AMBER, "ellipsoid")
	bone(root, torso, "FoxBody", CFrame.new())
	model.PrimaryPart = root

	attach(torso, newPart(model, "Belly", Vector3.new(7.6, 6, 15), CREAM, "ellipsoid"), CFrame.new(0, -1.7, -0.5))
	attach(torso, newPart(model, "Ruff", Vector3.new(9.6, 9.5, 7.5), CREAM, "ellipsoid"), CFrame.new(0, 0.2, -7.6))
	attach(torso, newPart(model, "Neck", Vector3.new(7.4, 9.5, 7.4), AMBER, "ellipsoid"), CFrame.new(0, 3.6, -9.4) * CFrame.Angles(R(-30), 0, 0))
	attach(torso, newPart(model, "NeckRuff", Vector3.new(8.4, 5, 6), CREAM, "ellipsoid"), CFrame.new(0, 1.2, -11.2) * CFrame.Angles(R(-20), 0, 0))
	attach(torso, newPart(model, "Back", Vector3.new(8, 4, 16), AMBER_DK, "ellipsoid"), CFrame.new(0, 3.4, 0.5))
	for _, s in ipairs({ -1, 1 }) do
		-- crimson flame markings along the flanks
		attach(torso, newPart(model, "Flame", Vector3.new(0.8, 2.4, 8), CRIMSON, "ellipsoid"), CFrame.new(4.75 * s, 1.0, -1.5) * CFrame.Angles(R(-14), 0, 0))
		attach(torso, newPart(model, "Flame", Vector3.new(0.8, 1.8, 5.5), CRIMSON, "ellipsoid"), CFrame.new(4.6 * s, -0.8, 3.5) * CFrame.Angles(R(-18), 0, 0))
	end

	buildHead(model, torso)
	buildLeg(model, torso, "FoxLegFL", -3.4, -6.5, false)
	buildLeg(model, torso, "FoxLegFR", 3.4, -6.5, false)
	buildLeg(model, torso, "FoxLegBL", -3.6, 6.5, true)
	buildLeg(model, torso, "FoxLegBR", 3.6, 6.5, true)
	for i = 1, 9 do
		buildTail(model, torso, i, 9)
	end

	-- burning chakra aura
	local att = Instance.new("Attachment")
	att.Parent = torso
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Aura"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(220, 40, 20))
	fire.LightEmission = 0.7
	fire.LightInfluence = 0
	fire.Rate = 40
	fire.Lifetime = NumberRange.new(0.6, 1.1)
	fire.Speed = NumberRange.new(4, 9)
	fire.SpreadAngle = Vector2.new(60, 60)
	fire.Size = NumberSequence.new(5, 0)
	fire.Transparency = NumberSequence.new(0.45, 1)
	fire.Acceleration = Vector3.new(0, 10, 0)
	fire.Shape = Enum.ParticleEmitterShape.Box
	fire.Parent = torso
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 32
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = torso

	model.Parent = character
	return model
end

FoxBeastModel.BodyHeight = BODY_HEIGHT
return FoxBeastModel
