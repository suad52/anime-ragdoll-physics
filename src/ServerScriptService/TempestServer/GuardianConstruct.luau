--!nocheck
-- GuardianConstruct: builds the spectral guardian and welds it to the caster's HumanoidRootPart. Original design: a
-- giant armoured warrior of violet light (~35 studs tall at Scale 1) that the caster floats inside - TempestService
-- lifts the caster's root to Guardian.RootHeight so they ride in its open ribcage. A flared lamellar skirt, a
-- cuirass over a solid inner skeleton (spine, ribs, arm bones), layered shoulder plates, a horned helm with gold
-- eye slits, a mantle down the back, an energy greatsword in the right fist and a great bow in the left.
-- Model space: origin on the ground under the caster, -Z forward, +X the caster's right, studs at Scale 1.
-- Animatable joints (Motor6D, posed by TempestClient via .Transform): GuardBody (waist), GuardHead (neck),
-- GuardRightArm / GuardLeftArm (shoulders), GuardRightElbow / GuardLeftElbow, GuardBowGrip (left wrist) and
-- GuardMantle (upper back). Every part carries a "Stage" attribute (1 skeleton, 2 armour, 3 helm details, weapons,
-- mantle) that the client's reveal walks; the client also reads the parts named Blade / BladeCore / BladeTip / Tsuba /
-- Hilt (the sword, hidden while the bow is drawn), BowString / BowGrip, GauntletRight (draws the string), the
-- BowGrip's attachments BowTipTop / BowTipBottom and the Blade's SlashTrail.
-- A Model named Config.Guardian.TemplateName in ServerStorage (PrimaryPart at the caster's root, facing -Z)
-- replaces the built-in construct.
local ServerStorage = game:GetService("ServerStorage")

local GuardianConstruct = {}
local R = math.rad
local CF = CFrame.new
local ANG = CFrame.Angles

GuardianConstruct.RootHeight = 16.5 -- where the caster's root rides (model space) unless Config.Guardian.RootHeight says
local SHOULDER = Vector3.new(9, 22.6, 0.2) -- the right shoulder joint (model space)
-- the bow grip at full draw (model space): where TempestClient's DRAW pose puts it, measured by FK on a preview
-- build. The server looses the arrow from here so the shot leaves the bow.
local MUZZLE = Vector3.new(-6.6, 22.1, -21.9)

-- root-space points (the caster's HumanoidRootPart frame) for the server's hit maths
function GuardianConstruct.points(cfg)
	local G = cfg.Guardian
	local k = G.Scale or 1
	local H = G.RootHeight or GuardianConstruct.RootHeight
	return {
		shoulder = (SHOULDER - Vector3.new(0, H, 0)) * k,
		muzzle = (MUZZLE - Vector3.new(0, H, 0)) * k,
		ground = -H * k,
	}
end

local function newPart(model, name, size, st, shape)
	local p = shape == "wedge" and Instance.new("WedgePart") or Instance.new("Part")
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "rod" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Name = name
	p.Size = size
	p.Color = st.color
	p.Material = st.material
	p.Transparency = st.transparency
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p:SetAttribute("Stage", st.stage)
	p.Parent = model
	return p
end

local function styles(P, G)
	local shellMat = Enum.Material[G.ShellMaterial or "SmoothPlastic"]
	local T = G.BodyTransparency or 0.45
	local edge = P.Guard:Lerp(P.GuardBone, 0.35)
	return {
		hidden = { color = P.Guard, material = Enum.Material.SmoothPlastic, transparency = 1, stage = 0 },
		shell = { color = P.Guard, material = shellMat, transparency = T, stage = 2 },
		plate = { color = P.GuardDeep, material = shellMat, transparency = math.max(T - 0.1, 0), stage = 2 },
		face = { color = P.GuardDeep:Lerp(Color3.new(0, 0, 0), 0.35), material = Enum.Material.SmoothPlastic, transparency = 0.25, stage = 2 },
		bone = { color = P.GuardBone, material = Enum.Material.SmoothPlastic, transparency = G.BoneTransparency or 0, stage = 1 },
		trim = { color = edge, material = Enum.Material.Neon, transparency = 0.15, stage = 3 },
		eye = { color = P.GuardEye, material = Enum.Material.Neon, transparency = 0, stage = 3 },
		blade = { color = P.Blade, material = Enum.Material.Neon, transparency = 0.3, stage = 3 },
		core = { color = P.Core, material = Enum.Material.Neon, transparency = 0.05, stage = 3 },
		grip = { color = P.GuardDeep, material = Enum.Material.SmoothPlastic, transparency = 0.1, stage = 3 },
		mantle = { color = P.GuardDeep, material = shellMat, transparency = math.min(T + 0.1, 0.9), stage = 3 },
	}
end

local function fromTemplate(character, template, hrp)
	local model = template:Clone()
	model.Name = "GuardianConstruct"
	local root = model.PrimaryPart
	model:PivotTo(hrp.CFrame)
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
	local w = Instance.new("Weld")
	w.Name = "GuardianWeld"
	w.Part0, w.Part1, w.C0 = hrp, root, hrp.CFrame:ToObjectSpace(root.CFrame)
	w.Parent = root
	model.Parent = character
	return model
end

local function M(x, y, z, rx, ry, rz)
	return CF(x, y, z) * ANG(R(rx or 0), R(ry or 0), R(rz or 0))
end

function GuardianConstruct.build(character, cfg)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local G = cfg.Guardian
	local template = G.TemplateName and ServerStorage:FindFirstChild(G.TemplateName)
	if template and template:IsA("Model") and template.PrimaryPart then
		return fromTemplate(character, template, hrp)
	end
	local P = cfg.Palette
	local k = G.Scale or 1
	local H = G.RootHeight or GuardianConstruct.RootHeight
	local S = styles(P, G)

	local model = Instance.new("Model")
	model.Name = "GuardianConstruct"
	-- model space -> world: the ground under the caster once they ride at RootHeight
	local ground = hrp.CFrame * CF(0, -H * k, 0)
	local function world(cf)
		return ground * (CF(cf.Position * k) * cf.Rotation)
	end
	local function part(name, size, st, cf, shape)
		local p = newPart(model, name, size * k, st, shape)
		p.CFrame = world(cf)
		return p
	end
	local function weld(base, p)
		local w = Instance.new("Weld")
		w.Part0, w.Part1, w.C0 = base, p, base.CFrame:ToObjectSpace(p.CFrame)
		w.Parent = p
		return p
	end
	local function on(base, name, size, st, cf, shape)
		return weld(base, part(name, size, st, cf, shape))
	end
	local function joint(name, p0, p1, pivot)
		local pw = world(pivot)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0, m.Part1 = p0, p1
		m.C0, m.C1 = p0.CFrame:ToObjectSpace(pw), p1.CFrame:ToObjectSpace(pw)
		m.Parent = p0
		return m
	end
	-- a round bone (cylinder) from a to b, model space
	local function bone(base, a, b, width, name)
		local d = b - a
		local up = math.abs(d.Unit.Y) > 0.95 and Vector3.zAxis or Vector3.yAxis
		local cf = CFrame.lookAt((a + b) / 2, b, up) * ANG(0, R(90), 0)
		return on(base, name or "Bone", Vector3.new(d.Magnitude, width, width), S.bone, cf, "rod")
	end
	-- a flat plate hung from `top` to `bottom` (model space), its width along `tangent`
	local function panel(base, name, top, bottom, width, thick, st, tangent)
		local up = (top - bottom).Unit
		local rt = (tangent - up * tangent:Dot(up)).Unit
		local cf = CFrame.fromMatrix((top + bottom) / 2, rt, up)
		return on(base, name, Vector3.new(width, (top - bottom).Magnitude, thick), st, cf)
	end

	local root = newPart(model, "GuardRoot", Vector3.one, S.hidden)
	root.CFrame = hrp.CFrame
	local rw = Instance.new("Weld")
	rw.Name = "GuardianWeld"
	rw.Part0, rw.Part1 = hrp, root
	rw.Parent = root
	model.PrimaryPart = root

	-- the armour skirt: a belt and seven lamellar panels flaring out to the ground (split at the front)
	on(root, "Belt", Vector3.new(11.6, 2.2, 8.6), S.plate, M(0, 11.5, 0.4))
	on(root, "BeltTrim", Vector3.new(11.9, 0.35, 8.9), S.trim, M(0, 12.55, 0.4))
	for _, deg in ipairs({ 25, 75, 125, 180, -125, -75, -25 }) do
		local th = R(deg)
		local o = Vector3.new(math.sin(th), 0, -math.cos(th))
		local r0 = 1 / math.sqrt((math.sin(th) / 5.4) ^ 2 + (math.cos(th) / (deg == 180 and 4.6 or 4.1)) ^ 2)
		local c = Vector3.new(0, 0, 0.4)
		panel(root, "Skirt", c + o * r0 + Vector3.new(0, 10.6, 0), c + o * (r0 + 3.4) + Vector3.new(0, 0.5, 0), 5.6, 0.5, S.shell, Vector3.new(math.cos(th), 0, math.sin(th)))
	end

	-- the torso rides the waist joint: a broad upper back (the joint's part) over a narrower lower back, the two
	-- cuirass plates meeting in a ridge, the gorget
	local back = part("BackPlate", Vector3.new(14.4, 6.8, 1), S.shell, M(0, 21.1, 4.1, -4, 0, 0))
	joint("GuardBody", root, back, M(0, 11.8, 0.4))
	on(back, "LowerBack", Vector3.new(10.4, 5.6, 1), S.shell, M(0, 15.3, 3.7, 5, 0, 0))
	for _, s in ipairs({ -1, 1 }) do
		on(back, "ChestPlate", Vector3.new(7.6, 7.2, 1.1), S.shell, M(3.5 * s, 20.9, -4.4, 8, -16 * s, 0))
	end
	on(back, "Gorget", Vector3.new(6.6, 1.8, 6.4), S.plate, M(0, 24.3, 0.2))

	-- the solid skeleton inside: spine, sternum and three pairs of ribs (the lowest open at the front so the caster
	-- shows through)
	bone(back, Vector3.new(0, 10.8, 3.0), Vector3.new(0, 24.6, 3.1), 1.1, "Spine")
	bone(back, Vector3.new(0, 15.6, -3.7), Vector3.new(0, 23.2, -3.9), 0.9, "Sternum")
	for i, y in ipairs({ 14.6, 17.4, 20.2 }) do
		for _, s in ipairs({ -1, 1 }) do
			local spine = Vector3.new(0.4 * s, y, 2.9)
			local side = Vector3.new(5.5 * s, y - 0.8, 0.1)
			local front = i == 1 and Vector3.new(3.9 * s, y - 1.9, -3.1) or Vector3.new(0.9 * s, y - 1.6, -3.7)
			bone(back, spine, side, 0.7, "Rib")
			bone(back, side, front, 0.6, "Rib")
		end
	end

	-- shoulder caps and the layered shoulder plates hanging off them
	for _, s in ipairs({ -1, 1 }) do
		on(back, "ShoulderCap", Vector3.new(6.2, 1.5, 7.6), S.plate, M(9.5 * s, 25.1, 0.3, 0, 0, -20 * s))
		for i = 1, 3 do
			on(back, "ShoulderPlate", Vector3.new(1, 2.6, 7.8 + i * 0.35), S.shell, M((11.6 + i * 0.75) * s, 24.7 - i * 2.4, 0.3, 0, 0, 16 * s))
		end
	end

	-- the helm: a dome with a dark face, gold eye slits, a peak, a flared neck guard, two horns and a crest disc
	local helm = part("Helm", Vector3.new(6.4, 6.4, 6.4), S.shell, M(0, 29.6, 0.4), "ball")
	joint("GuardHead", back, helm, M(0, 25.2, 0.3))
	local face = on(helm, "Face", Vector3.new(4.2, 4, 4.4), S.face, M(0, 27.3, -0.6))
	on(helm, "Brim", Vector3.new(6.6, 0.5, 2.8), S.trim, M(0, 29.1, -2.9, 14, 0, 0))
	on(helm, "NeckGuard", Vector3.new(8, 1.6, 6.8), S.shell, M(0, 27.8, 1.7, 18, 0, 0))
	on(helm, "Jaw", Vector3.new(3.4, 1.3, 0.7), S.plate, M(0, 25.9, -2.75, -10, 0, 0))
	for _, s in ipairs({ -1, 1 }) do
		on(helm, "Eye", Vector3.new(1.4, 0.36, 0.3), S.eye, M(1.05 * s, 27.9, -2.85, 0, 0, 12 * s))
		on(helm, "HelmWing", Vector3.new(0.5, 2.8, 2.6), S.shell, M(3.5 * s, 28.4, -1.5, 0, -30 * s, 12 * s))
		-- the horns: a short upright root, then a long blade sweeping out and back
		on(helm, "Horn", Vector3.new(0.7, 3.8, 1.2), S.trim, M(1.25 * s, 30.6, -2.9, 6, 0, -11 * s))
		on(helm, "Horn", Vector3.new(0.55, 5.4, 1), S.trim, M(3.0 * s, 34.4, -2.5, 12, 0, -33 * s))
	end
	on(helm, "Crest", Vector3.new(0.5, 2.2, 2.2), S.eye, M(0, 30.1, -3.05, 0, 90, 0), "rod")
	local eyeLight = Instance.new("PointLight")
	eyeLight.Color, eyeLight.Range, eyeLight.Brightness, eyeLight.Shadows = P.GuardEye, 8 * k, 1.5, false
	eyeLight.Parent = face

	-- the arms: shoulder and elbow joints, an armoured sleeve and bracer around a solid bone, a gauntlet fist (no R15
	-- part names here, so no animation track ever claims these joints)
	local fists = {}
	for _, s in ipairs({ 1, -1 }) do
		local tag = s > 0 and "Right" or "Left"
		local sh = CF(SHOULDER * Vector3.new(s, 1, 1)) * ANG(R(15), 0, R(10 * s))
		local upper = part("Sleeve" .. tag, Vector3.new(3.6, 8, 3.6), S.shell, sh * CF(0, -4, 0))
		joint("Guard" .. tag .. "Arm", back, upper, sh)
		bone(upper, (sh * CF(0, -0.4, 0)).Position, (sh * CF(0, -7.6, 0)).Position, 0.9, "ArmBone")
		local el = sh * CF(0, -8, 0) * ANG(R(70), 0, 0)
		local fore = part("Bracer" .. tag, Vector3.new(3.8, 7.4, 3.8), S.shell, el * CF(0, -3.7, 0))
		joint("Guard" .. tag .. "Elbow", upper, fore, el)
		local wrist = el * CF(0, -8.6, 0)
		fists[tag] = { part = on(fore, "Gauntlet" .. tag, Vector3.new(3.2, 3, 3.6), S.plate, wrist), at = wrist.Position }
	end

	-- the energy greatsword in the right fist, point forward and raised
	local fistR = fists.Right.part
	local gp = fists.Right.at
	local sword = CFrame.lookAt(gp, gp + Vector3.new(0.12, 0.45, -1).Unit) * ANG(0, 0, R(G.BladeRoll or 90))
	local function along(d0, len)
		return sword * CF(0, 0, -(d0 + len / 2))
	end
	on(fistR, "Hilt", Vector3.new(0.9, 0.9, 4.6), S.grip, along(-2.4, 4.6))
	on(fistR, "Tsuba", Vector3.new(0.5, 3.6, 3.6), S.trim, along(2.0, 0.5) * ANG(0, R(90), 0), "rod")
	local blade = on(fistR, "Blade", Vector3.new(0.5, 2.4, 22), S.blade, along(2.3, 22))
	on(fistR, "BladeCore", Vector3.new(0.62, 0.8, 21.6), S.core, along(2.4, 21.6))
	on(fistR, "BladeTip", Vector3.new(0.5, 2.4, 3.4), S.blade, along(24.3, 3.4), "wedge")
	-- the swing's light trail, from the guard to the point (TempestClient switches it on for the cut only)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Name, a1.Name = "TrailBase", "TrailTip"
	a0.Position, a1.Position = Vector3.new(0, 0, 8 * k), Vector3.new(0, 0, -14 * k)
	a0.Parent, a1.Parent = blade, blade
	local trail = Instance.new("Trail")
	trail.Name = "SlashTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(P.Core, P.Blade)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.2
	trail.LightEmission, trail.LightInfluence = 1, 0
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = blade

	-- the great bow in the left fist: a recurved bow of light on its own wrist joint (turned to face the target
	-- while drawing), and its string
	local fistL = fists.Left.part
	local bowCF = CF(fists.Left.at) * ANG(0, R(65), 0) * ANG(0, 0, R(-8))
	local grip = part("BowGrip", Vector3.new(1.3, 3.2, 1.3), S.grip, bowCF)
	joint("GuardBowGrip", fistL, grip, bowCF)
	local limb = { Vector3.new(0, 1.5, 0), Vector3.new(0, 5.2, 0.9), Vector3.new(0, 8.8, 2.5), Vector3.new(0, 11.6, 4.0) }
	for _, sy in ipairs({ 1, -1 }) do
		for i = 1, 3 do
			local a = bowCF * (limb[i] * Vector3.new(1, sy, 1))
			local b = bowCF * (limb[i + 1] * Vector3.new(1, sy, 1))
			local cf = CFrame.lookAt((a + b) / 2, b, bowCF.LookVector)
			local w = 1.05 - i * 0.15
			on(grip, "BowLimb", Vector3.new(w, w, (b - a).Magnitude + 0.35), S.blade, cf)
		end
		local tip = Instance.new("Attachment")
		tip.Name = sy > 0 and "BowTipTop" or "BowTipBottom"
		tip.Position = limb[4] * Vector3.new(1, sy, 1) * k
		tip.Parent = grip
	end
	on(grip, "BowString", Vector3.new(0.16, limb[4].Y * 2, 0.16), S.core, bowCF * CF(0, 0, limb[4].Z))

	-- the mantle down the back on its own joint (it sways), and spectral wisps rising off the shoulders
	local cape = panel(back, "Mantle", Vector3.new(0, 23.6, 4.8), Vector3.new(0, 1.6, 9.8), 8.6, 0.4, S.mantle, Vector3.xAxis)
	cape:FindFirstChildOfClass("Weld"):Destroy()
	joint("GuardMantle", back, cape, M(0, 23.6, 4.8))
	for _, s in ipairs({ -1, 1 }) do
		panel(cape, "MantleSide", Vector3.new(5.2 * s, 23.2, 4.6), Vector3.new(9.4 * s, 2.6, 8.6), 6.6, 0.4, S.mantle, Vector3.new(math.cos(R(24)), 0, -math.sin(R(24)) * s))
	end
	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "Wisps"
	wisps.Texture = "rbxasset://textures/particles/fire_main.dds"
	wisps.Color = ColorSequence.new(P.Guard, P.GuardDeep)
	wisps.LightEmission, wisps.LightInfluence = 0.6, 0
	wisps.Rate = 14
	wisps.Lifetime = NumberRange.new(0.7, 1.2)
	wisps.Speed = NumberRange.new(2, 5)
	wisps.SpreadAngle = Vector2.new(30, 30)
	wisps.Acceleration = Vector3.new(0, 6, 0)
	wisps.Size = NumberSequence.new(3.2 * k, 0)
	wisps.Transparency = NumberSequence.new(0.55, 1)
	wisps.Parent = back

	model.Parent = character
	return model
end

return GuardianConstruct
