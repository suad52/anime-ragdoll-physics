--!nocheck
-- TitanSkins: the bodies welded over a shifter's rig (built from parts: no meshes, no images), the twin-blade gear,
-- and the bodies of the swarm giants. Every piece is designed on the default R15 body (sizes and offsets in DEF
-- studs, at scale 1) and mapped onto the real limb axis by axis, so any avatar at any scale gets a body that fits and
-- whose joints line up. Pieces are massless, non-colliding, non-querying and welded to the limbs, so the rig's own
-- animations (walk, jump, the kit's poses) move the giant.
-- Style: a few deliberate shapes per muscle group (cylinders for the long muscles, blocks and wedges for the cut
-- ones, a ball hidden inside each elbow and knee so a bend never opens a gap). Glow only on the eyes, no lights on
-- the body, and steam only as small rising vents parented to the body itself (so it leaves with the body).
-- Put a Model named Config.<Form>.TemplateName (with a PrimaryPart) in ServerStorage to use your own art instead.
local ServerStorage = game:GetService("ServerStorage")

local TitanSkins = {}
local R = math.rad
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local SIDES = { -1, 1 }
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local UPRIGHT = ANG(0, 0, R(90)) -- a cylinder standing along the limb
local LENGTHWISE = ANG(0, R(90), 0) -- a cylinder lying front to back

local DEF = {
	Head = V(1.16, 1.18, 1.16), UpperTorso = V(1.94, 1.70, 1.00), LowerTorso = V(1.99, 0.40, 1.00),
	LeftUpperArm = V(1, 1.24, 1), RightUpperArm = V(1, 1.24, 1), LeftLowerArm = V(1, 1.12, 1), RightLowerArm = V(1, 1.12, 1),
	LeftHand = V(0.98, 0.32, 1.03), RightHand = V(0.98, 0.32, 1.03),
	LeftUpperLeg = V(0.99, 1.36, 0.97), RightUpperLeg = V(0.99, 1.36, 0.97), LeftLowerLeg = V(0.99, 1.30, 0.97),
	RightLowerLeg = V(0.99, 1.30, 0.97), LeftFoot = V(1.01, 0.31, 1.00), RightFoot = V(1.01, 0.31, 1.00),
}

local function newPart(parent, name, kind, size, color, material, transparency)
	local p
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		if kind == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif kind == "rod" then
			p.Shape = Enum.PartType.Cylinder
		end
	end
	p.Name = name
	p.Size = V(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = material or SMOOTH
	p.Transparency = transparency or 0
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.Anchored = false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- one piece on a limb: size and offset in default-body studs. The offset is stretched along the limb's own axes and
-- each side of the piece by the stretch along the direction it points, so pieces meet where they were designed to.
local function add(model, limb, name, kind, size, offset, color, material, transparency)
	local d = DEF[limb.Name]
	local f = d and limb.Size / d or V(1, 1, 1)
	local rot = offset.Rotation
	local c0 = CF(offset.Position * f) * rot
	local sz
	if kind == "ball" then
		sz = size * ((f.X + f.Y + f.Z) / 3)
	else
		sz = V(size.X * (rot.XVector * f).Magnitude, size.Y * (rot.YVector * f).Magnitude, size.Z * (rot.ZVector * f).Magnitude)
	end
	local p = newPart(model, name, kind, sz, color, material, transparency)
	-- only the big masses throw shadows; teeth, eyes and lines do not need to
	p.CastShadow = size.X * size.Y + size.Y * size.Z + size.X * size.Z > 0.5
	p.CFrame = limb.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = limb
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	return p
end

-- a cylinder standing along the limb (diameter, length, centre)
local function post(model, limb, name, dia, len, pos, color, material, tilt)
	return add(model, limb, name, "rod", V(len, dia, dia), CF(pos) * (tilt or CFrame.identity) * UPRIGHT, color, material)
end

-- a right-triangle plate: its straight edge runs `width` along `across` from `top`, its point hangs `len` toward
-- `dir` at the +across end (hair tips, fangs)
local function spike(model, limb, name, top, across, dir, width, len, thick, color, material)
	across = across.Unit
	dir = (dir - across * dir:Dot(across)).Unit
	local centre = top + dir * (len / 2)
	local cf = CFrame.fromMatrix(centre, dir:Cross(across), dir, across)
	return add(model, limb, name, "wedge", V(thick, len, width), cf, color, material)
end

-- a row of teeth along the jaw arc; t runs -1..1 across the mouth
local function teethRow(model, head, n, halfW, y, z, curve, w, h, color, drop)
	for i = 0, n - 1 do
		local t = ((i + 0.5) / n) * 2 - 1
		local hh = h * (1 - 0.3 * t * t)
		add(model, head, "Tooth", "block", V(w, hh, 0.05), CF(t * halfW, y + drop * hh / 2, z + t * t * curve) * ANG(0, -t * R(38), 0), color)
	end
end

local function kp(t, v)
	return NumberSequenceKeypoint.new(t, v)
end

-- a small vent of rising steam on a body piece (`at` in that piece's own studs). Sparse and rising, so it reads as
-- heat coming off the body and never as fog round the camera.
local function vent(part, at, scale, rate, color, size, rise)
	local a = Instance.new("Attachment")
	a.Name = "SteamPort"
	a.CFrame = at
	a.Parent = part
	local e = Instance.new("ParticleEmitter")
	e.Name = "Steam"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color or Color3.fromRGB(236, 236, 236))
	e.LightEmission = 0.05
	e.LightInfluence = 0.8
	e.Rate = rate
	e.Lifetime = NumberRange.new(1.3, 2.2)
	e.Speed = NumberRange.new(rise * 0.6 * scale, rise * scale)
	e.SpreadAngle = Vector2.new(12, 12)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = V(0, 0.6 * rise * scale, 0)
	e.Drag = 0.4
	e.Size = NumberSequence.new({ kp(0, size * 0.3 * scale), kp(1, size * scale) })
	e.Transparency = NumberSequence.new({ kp(0, 1), kp(0.15, 0.68), kp(0.55, 0.82), kp(1, 1) })
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Parent = a
	return e
end

-- a hand-made model: faced the way the character faces, feet on the ground, everything welded to the LowerTorso
local function fromTemplate(character, name)
	local template = name and ServerStorage:FindFirstChild(name)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local lt = character:FindFirstChild("LowerTorso") or hrp
	local hum = character:FindFirstChildOfClass("Humanoid")
	local model = template:Clone()
	model.Name = "TitanSkin"
	local root = model.PrimaryPart
	local flat = hrp.CFrame.LookVector * V(1, 0, 1)
	flat = flat.Magnitude > 1e-3 and flat.Unit or V(0, 0, -1)
	model:PivotTo(CFrame.lookAt(lt.Position, lt.Position + flat))
	local groundY = hrp.Position.Y - ((hum and hum.HipHeight or 2) + hrp.Size.Y / 2)
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + V(0, groundY - (box.Position.Y - size.Y / 2), 0))
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
	weld.Part0, weld.Part1 = lt, root
	weld.C0 = lt.CFrame:ToObjectSpace(root.CFrame)
	weld.Parent = root
	model.Parent = character
	return model
end

-- the avatar itself becomes the titan's base body (2026-11-07): the skin's detail pieces sit on the player's own
-- limbs, so clothing, hats, hair and the face used to scale up 14x with them (a giant beanie for a head, the shirt
-- showing in every gap - "a red mannequin"). While a skin is on, every body limb takes the titan's colour and
-- material with no texture, clothing / accessories / the face are hidden and BodyColors is parked; all of it comes
-- back the moment the skin goes (release, timeout, death, kit switch).
-- (2026-11-10, "after becoming a titan and going back to human you go bald and your clothes fall off") two restore bugs:
--  1. ShifterService.hideBody runs BEFORE the skin is built and has already set every accessory and the face to
--     Transparency 1, so this recorded 1 as their "original". showBody brought them back at the form's end, and then
--     this restore re-hid hair, hats, layered clothing and the face for good. Only what is visible NOW is hidden and
--     recorded here; anything already hidden belongs to whoever hid it (hideBody puts its own values back).
--  2. The restore waited for the skin's parent to become nil, but clearForm re-parents the skin to the FX folder as a
--     husk that stands 4.5-6 s, so the human body came back tan, shirtless and without BodyColors for that long - and
--     a second form inside that window saved those blanks as the originals. Now it restores the moment the skin
--     leaves the body, and ShifterService.clearForm calls TitanSkins.undress first thing (before the form attributes
--     clear, so FighterSkinLook / PerkUltOutfit never read the titan's blanks as the player's look).
-- A value something else rewrote meanwhile (an ApplyDescription) is left alone: only what still holds the skin's
-- value is put back.
local undo = setmetatable({}, { __mode = "k" }) -- [skin model] = its restore
local function same(a, b)
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		-- BasePart.Color is stored 8-bit, so it reads back a hair off what was written
		return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
	end
	return a == b
end
local function dress(char, skin, colorFor, material)
	local saved = {}
	local function keep(inst, prop, value)
		local ok, old = pcall(function()
			return inst[prop]
		end)
		if ok and pcall(function()
			inst[prop] = value
		end) then
			table.insert(saved, { inst, prop, old, value })
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		if not d:IsDescendantOf(skin) then
			if d:IsA("BasePart") and DEF[d.Name] and d.Parent == char then
				keep(d, "Color", colorFor(d.Name))
				keep(d, "Material", material)
				if d:IsA("MeshPart") then
					keep(d, "TextureID", "")
				end
			elseif d:IsA("BasePart") and d:FindFirstAncestorOfClass("Accessory") then
				if d.Transparency < 1 then
					keep(d, "Transparency", 1)
				end
			elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
				if d.Transparency < 1 then
					keep(d, "Transparency", 1)
				end
			elseif d:IsA("SurfaceAppearance") then
				keep(d, "Parent", nil)
			end
		end
	end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Shirt") then
			keep(c, "ShirtTemplate", "")
		elseif c:IsA("Pants") then
			keep(c, "PantsTemplate", "")
		elseif c:IsA("ShirtGraphic") then
			keep(c, "Graphic", "")
		elseif c:IsA("BodyColors") then
			keep(c, "Parent", nil)
		end
	end
	local done = false
	local function restore()
		if done then
			return
		end
		done = true
		undo[skin] = nil
		for i = #saved, 1, -1 do
			local s = saved[i]
			pcall(function()
				if same(s[1][s[2]], s[4]) then
					s[1][s[2]] = s[3]
				end
			end)
		end
	end
	undo[skin] = restore
	skin.Destroying:Connect(restore)
	-- the moment the skin is no longer on this body (husk, destroyed, or the body itself gone)
	skin.AncestryChanged:Connect(function()
		if not skin:IsDescendantOf(char) then
			restore()
		end
	end)
end

-- puts the avatar's own look back now (ShifterService.clearForm); a skin with nothing to undo is a no-op
function TitanSkins.undress(skin)
	local restore = skin and undo[skin]
	if restore then
		restore()
	end
end

local function limbs(char)
	local L = {}
	for name in pairs(DEF) do
		L[name] = char:FindFirstChild(name)
	end
	return L
end

---------------------------------------------------------------------------------------------------
-- the shared anatomy. `st` picks the colours and the level of detail:
--   skin (main mass), skin2 (secondary masses), line (grooves), joint (elbow/knee filler), mat, w (limb thickness),
--   waist (waist width), tendon (pale tendons on a skinless body, or nil), ribs (rib lines a side), lite (the swarm's
--   cheap version: a few big shapes per limb, no muscle detail)

local function torso(m, L, st)
	local ut, lt = L.UpperTorso, L.LowerTorso
	local SK, S2, LN, MAT = st.skin, st.skin2, st.line, st.mat
	local waistW = st.waist or 1.42
	if ut then
		post(m, ut, "Neck", st.neckDia or 0.5, st.neckLen or 0.52, V(0, 0.95, 0.03), SK, MAT)
		add(m, ut, "Chest", "block", V(1.9, 0.86, 0.96), CF(0, 0.27, 0), S2, MAT)
		add(m, ut, "Waist", "block", V(waistW, 0.82, 0.8), CF(0, -0.43, 0.03), SK, MAT)
		if st.lite then
			add(m, ut, "Pecs", "block", V(1.6, 0.42, 0.16), CF(0, 0.46, -0.5) * ANG(R(8), 0, 0), SK, MAT)
		else
			for _, s in ipairs(SIDES) do
				add(m, ut, "Trap", "wedge", V(0.62, 0.34, 0.78), CF(s * 0.44, 0.84, 0.06) * ANG(0, R(-s * 90), 0), SK, MAT)
				add(m, ut, "Pec", "block", V(0.86, 0.48, 0.22), CF(s * 0.46, 0.46, -0.5) * ANG(R(10), 0, R(s * 8)), SK, MAT)
				add(m, ut, "Lat", "block", V(0.34, 0.92, 0.78), CF(s * (0.47 + waistW / 4), -0.3, 0.05) * ANG(0, 0, R(-s * 14)), S2, MAT)
				add(m, ut, "Blade", "block", V(0.56, 0.62, 0.12), CF(s * 0.42, 0.4, 0.5) * ANG(0, 0, R(-s * 10)), SK, MAT)
				add(m, ut, "Neckline", "block", V(0.09, 0.52, 0.09), CF(s * 0.13, 0.93, -0.13) * ANG(R(25), 0, R(-s * 20)), st.tendon or S2, MAT)
				add(m, ut, "Erector", "block", V(0.3, 0.75, 0.12), CF(s * 0.19, -0.42, 0.46), SK, MAT)
				for k = 0, 1 do
					add(m, ut, "Abs", "block", V(0.3, 0.24, 0.1), CF(s * 0.17, -0.2 - k * 0.28, -0.41), SK, MAT)
				end
				for k = 0, (st.ribs or 1) - 1 do
					local y = 0.06 - k * 0.13
					add(m, ut, "Serratus", "block", V(0.3, 0.07, 0.12), CF(s * 0.72, y, y > -0.16 and -0.49 or -0.4) * ANG(0, R(s * 30), R(s * 26)), st.tendon or LN, MAT)
				end
			end
		end
	end
	if lt then
		add(m, lt, "Pelvis", "block", V(st.hips or 1.6, 0.62, 0.86), CF(0, -0.08, 0.03), SK, MAT)
		if not st.lite then
			for _, s in ipairs(SIDES) do
				add(m, lt, "Glute", "block", V(0.72, 0.62, 0.28), CF(s * 0.38, -0.2, 0.4), SK, MAT)
				add(m, lt, "Abs", "block", V(0.28, 0.2, 0.1), CF(s * 0.16, 0.1, -0.42), SK, MAT)
			end
		end
	end
end

local FINGERS = { 0.5, 0.56, 0.52, 0.42 }
local function arms(m, L, st)
	local SK, S2, MAT, w = st.skin, st.skin2, st.mat, st.w or 1
	for _, side in ipairs({ "Left", "Right" }) do
		local s = side == "Left" and -1 or 1
		local ua, la, hd = L[side .. "UpperArm"], L[side .. "LowerArm"], L[side .. "Hand"]
		if ua then
			-- the shoulder: a round cap tucked in against the chest, not a knob on the end of the arm
			add(m, ua, "Delt", "ball", V(0.84, 0.84, 0.84) * w, CF(-s * 0.06, 0.2, 0), SK, MAT)
			post(m, ua, "Arm", 0.74 * w, 1.02, V(0, -0.12, 0.02), S2, MAT)
			if not st.lite then
				post(m, ua, "Bicep", 0.52 * w, 0.6, V(0, -0.1, -0.15 * w), SK, MAT)
				add(m, ua, "Tricep", "block", V(0.44 * w, 0.6, 0.2), CF(0, -0.02, 0.25 * w), SK, MAT)
				add(m, ua, "Elbow", "ball", V(0.68, 0.68, 0.68) * w, CF(0, -0.38, 0.02), st.joint, MAT)
			end
		end
		if la then
			if st.lite then
				post(m, la, "Forearm", 0.66 * w, 1.15, V(0, -0.09, 0), SK, MAT)
			else
				post(m, la, "Forearm", 0.76 * w, 0.55, V(0, 0.12, 0), SK, MAT)
				post(m, la, "Wrist", 0.56 * w, 0.6, V(0, -0.3, 0), S2, MAT)
			end
		end
		if hd then
			if st.lite then
				add(m, hd, "Hand", "block", V(0.3, 0.95, 0.68), CF(0, -0.38, -0.02), SK, MAT)
			else
				add(m, hd, "Palm", "block", V(0.34, 0.62, 0.74), CF(0, -0.22, -0.02), SK, MAT)
				for i = 0, 3 do
					local len = FINGERS[i + 1]
					add(m, hd, "Finger", "block", V(0.2, len, 0.15), CF(-s * 0.03, -0.5 - len / 2 + 0.03, -0.27 + i * 0.18) * ANG(0, 0, R(-s * 12)), SK, MAT)
				end
				add(m, hd, "Thumb", "block", V(0.18, 0.42, 0.16), CF(-s * 0.1, -0.32, -0.42) * ANG(R(28), 0, R(-s * 15)), SK, MAT)
			end
		end
	end
end

local function legs(m, L, st)
	local SK, S2, MAT, w = st.skin, st.skin2, st.mat, st.w or 1
	for _, side in ipairs({ "Left", "Right" }) do
		local s = side == "Left" and -1 or 1
		local ul, ll, ft = L[side .. "UpperLeg"], L[side .. "LowerLeg"], L[side .. "Foot"]
		if ul then
			post(m, ul, "Thigh", 0.94 * w, 1.3, V(0, 0.02, 0), S2, MAT)
			add(m, ul, "Knee", "ball", V(0.78, 0.78, 0.78) * w, CF(0, -0.5, 0), st.joint, MAT)
			if not st.lite then
				post(m, ul, "Quad", 0.64 * w, 1.0, V(s * 0.05, 0.02, -0.18 * w), SK, MAT)
				add(m, ul, "Hamstring", "block", V(0.58 * w, 0.92, 0.2), CF(0, -0.02, 0.37 * w), SK, MAT)
				add(m, ul, "Kneecap", "block", V(0.32, 0.28, 0.14) * w, CF(0, -0.52, -0.4 * w), st.tendon or SK, MAT)
			end
		end
		if ll then
			post(m, ll, "Shin", 0.72 * w, 1.2, V(0, -0.06, 0), S2, MAT)
			if not st.lite then
				post(m, ll, "Calf", 0.6 * w, 0.62, V(0, 0.14, 0.17 * w), SK, MAT)
			end
		end
		if ft then
			add(m, ft, "Foot", "block", V(0.74, 0.3, 1.32), CF(0, -0.005, -0.22), SK, MAT)
			if not st.lite then
				add(m, ft, "Instep", "wedge", V(0.64, 0.3, 0.62), CF(0, 0.295, -0.2), S2, MAT)
				add(m, ft, "Toes", "block", V(0.74, 0.17, 0.24), CF(0, -0.065, -0.98), SK, MAT)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the 15-metre form: a lean, deeply cut giant with tan skin; long dark shaggy hair framing the face, swept-back
-- pointed ears, glowing green eyes under a heavy brow, and a lipless mouth torn back over bare jaw muscle and teeth
local BACK_LOCKS = { { -0.33, 0.82, -9 }, { -0.11, 1.0, -6 }, { 0.11, 0.94, -7 }, { 0.33, 0.8, -10 } }
function TitanSkins.warrior(char, cfg)
	local tpl = fromTemplate(char, cfg.Warrior.TemplateName)
	if tpl then
		return tpl
	end
	local P = cfg.Palette
	local L = limbs(char)
	local head, ut, lt = L.Head, L.UpperTorso, L.LowerTorso
	if not (head and ut and lt) then
		return nil
	end
	local scale = char:GetScale()
	local SK, SH, MU, HAIR = P.WarriorSkin, P.WarriorShade, P.WarriorMuscle, P.WarriorHair
	local S2 = SK:Lerp(SH, 0.28)
	local m = Instance.new("Model")
	m.Name = "TitanSkin"

	-- head: a long face under a heavy brow; the mouth is a recessed band so the teeth stand in front of it
	add(m, head, "Cranium", "block", V(0.84, 0.62, 0.92), CF(0, 0.14, 0.02), SK)
	add(m, head, "Face", "block", V(0.76, 0.33, 0.8), CF(0, -0.075, -0.05), SK)
	add(m, head, "Jaw", "block", V(0.66, 0.14, 0.66), CF(0, -0.42, -0.1), S2)
	add(m, head, "Chin", "block", V(0.3, 0.12, 0.1), CF(0, -0.44, -0.46), SK)
	add(m, head, "Maw", "block", V(0.56, 0.13, 0.05), CF(0, -0.3, -0.41), P.MouthDark)
	add(m, head, "Mask", "block", V(0.5, 0.11, 0.05), CF(0, -0.02, -0.455), P.MouthDark)
	add(m, head, "Nose", "wedge", V(0.15, 0.24, 0.13), CF(0, -0.13, -0.51), SK)
	teethRow(m, head, 4, 0.24, -0.245, -0.45, 0.035, 0.1, 0.075, P.Teeth, -1)
	teethRow(m, head, 4, 0.22, -0.37, -0.445, 0.035, 0.1, 0.065, P.Teeth, 1)
	for _, s in ipairs(SIDES) do
		add(m, head, "Brow", "block", V(0.42, 0.13, 0.22), CF(s * 0.19, 0.07, -0.43) * ANG(R(14), 0, R(s * 11)), S2)
		add(m, head, "Eye", "block", V(0.16, 0.05, 0.04), CF(s * 0.17, -0.025, -0.475) * ANG(0, 0, R(s * 10)), P.WarriorEye, NEON)
		add(m, head, "Cheekbone", "block", V(0.16, 0.1, 0.32), CF(s * 0.32, -0.1, -0.32) * ANG(0, R(s * 22), 0), SK)
		-- no lips: the cheek is torn back to the jaw hinge and the muscle shows, striped
		add(m, head, "CheekMuscle", "block", V(0.1, 0.2, 0.24), CF(s * 0.31, -0.3, -0.32) * ANG(0, R(s * 25), 0), MU)
		add(m, head, "CheekFiber", "block", V(0.03, 0.2, 0.03), CF(s * 0.34, -0.3, -0.41) * ANG(0, R(s * 25), R(s * 8)), P.Gums)
		-- the ear: a long point swept up, out and back between the side locks
		spike(m, head, "Ear", V(s * 0.42, -0.1, -0.08), V(0, 0.1, 1), V(s * 1.0, 0.9, 0.3), 0.28, 0.46, 0.05, SK)
	end

	-- hair: a cap with two tufts, four back locks of different lengths to the shoulders, a lock behind and in front
	-- of each ear, a ragged fringe parted in the middle, and a pointed end on every lock so it reads shaggy
	add(m, head, "HairCap", "block", V(0.94, 0.2, 1.0), CF(0, 0.52, 0.05), HAIR)
	for _, b in ipairs(BACK_LOCKS) do
		local x, len, tilt = b[1], b[2], b[3]
		local cf = CF(x, 0.5 - len / 2, 0.55) * ANG(R(tilt), 0, R(x * 18))
		add(m, head, "HairLock", "block", V(0.25, len, 0.16), cf, HAIR)
		local bottom = (cf * CF(0, -len / 2, 0)).Position
		local across = cf.XVector * (x > 0 and 1 or -1)
		spike(m, head, "HairTip", bottom - across * 0.02, across, -cf.YVector + across * 0.25, 0.25, 0.24, 0.13, HAIR)
	end
	for _, s in ipairs(SIDES) do
		spike(m, head, "HairTuft", V(s * 0.2, 0.6, 0.02), V(0, 0, 1), V(s * 0.35, 1, 0.5), 0.5, 0.16, 0.22, HAIR)
		add(m, head, "HairSide", "block", V(0.16, 0.86, 0.46), CF(s * 0.5, 0.06, 0.3) * ANG(0, 0, R(s * 5)), HAIR)
		spike(m, head, "HairTip", V(s * 0.535, -0.37, 0.3), V(0, 0, 1), V(s * 0.25, -1, 0), 0.44, 0.24, 0.12, HAIR)
		add(m, head, "HairFrame", "block", V(0.12, 0.62, 0.18), CF(s * 0.45, 0.12, -0.32) * ANG(0, 0, R(s * 4)), HAIR)
		spike(m, head, "Fringe", V(s * 0.04, 0.44, -0.5), V(s, 0, 0), V(s * 0.5, -1, -0.15), 0.24, 0.3, 0.08, HAIR)
		spike(m, head, "Fringe", V(s * 0.24, 0.44, -0.48), V(s, 0, 0), V(s * 0.35, -1, -0.12), 0.22, 0.36, 0.08, HAIR)
	end

	local st = { skin = SK, skin2 = S2, line = SK:Lerp(SH, 0.7), joint = S2, mat = SMOOTH, w = 0.9 }
	torso(m, L, st)
	arms(m, L, st)
	legs(m, L, st)

	-- definition: dark grooves down the abs, round the pecs and along the long muscles, so the cut body reads at range
	local GROOVE = SK:Lerp(SH, 0.85)
	add(m, ut, "Linea", "block", V(0.05, 0.8, 0.04), CF(0, -0.42, -0.46), GROOVE)
	for k = 0, 1 do
		add(m, ut, "AbLine", "block", V(0.5, 0.035, 0.04), CF(0, -0.32 - k * 0.27, -0.455), GROOVE)
	end
	for _, s in ipairs(SIDES) do
		add(m, ut, "PecLine", "block", V(0.7, 0.035, 0.04), CF(s * 0.44, 0.25, -0.6) * ANG(R(10), 0, R(-s * 12)), GROOVE)
		add(m, ut, "Collarbone", "block", V(0.48, 0.05, 0.06), CF(s * 0.36, 0.66, -0.48) * ANG(0, 0, R(s * 14)), S2)
		local side = s < 0 and "Left" or "Right"
		local ua, ul = L[side .. "UpperArm"], L[side .. "UpperLeg"]
		if ua then
			add(m, ua, "ArmGroove", "block", V(0.035, 0.55, 0.035), CF(s * 0.2, -0.1, -0.33), GROOVE)
		end
		if ul then
			add(m, ul, "ThighGroove", "block", V(0.035, 0.85, 0.035), CF(-s * 0.08, 0, -0.44), GROOVE)
		end
	end

	-- a freshly formed body steams a little off the shoulders
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Trap" then
			vent(p, CF(0, p.Size.Y * 0.4, 0), scale, 1.8, P.Steam, 1.6, 1.2)
		end
	end
	m.Parent = char
	-- the avatar under it becomes tan titan flesh (the head a touch darker under the hair)
	dress(char, m, function(name)
		return name == "Head" and S2 or SK
	end, SMOOTH)
	return m
end

---------------------------------------------------------------------------------------------------
-- the 60-metre form: no skin at all, and lean for its size: raw red muscle shaded darker in its hollows, pale tendon
-- over the collarbones, sternum, ribs, belly line and every joint, dark fibre lines along the long muscles; a bare
-- skull face on a long neck, a heavy brow over deep black sockets with small pale eyes, pale cheekbones, and the
-- whole row of teeth bared over the gums; steam venting from the shoulders and back
function TitanSkins.colossus(char, cfg)
	local tpl = fromTemplate(char, cfg.Colossus.TemplateName)
	if tpl then
		return tpl
	end
	local P = cfg.Palette
	local L = limbs(char)
	local head, ut, lt = L.Head, L.UpperTorso, L.LowerTorso
	if not (head and ut and lt) then
		return nil
	end
	local scale = char:GetScale()
	local MU, FI, TE = P.ColossusMuscle, P.ColossusFiber, P.ColossusTendon
	-- a deep, matte red with darker hollows: bright red plastic reads as a toy
	local M1, M2 = MU:Lerp(FI, 0.2), MU:Lerp(FI, 0.5)
	local FAB = Enum.Material.Fabric
	local m = Instance.new("Model")
	m.Name = "TitanSkin"
	local function fiber(limb, x, y, z, len, tilt)
		add(m, limb, "Fiber", "block", V(0.045, len, 0.04), CF(x, y, z) * ANG(0, 0, R(tilt or 0)), FI)
	end

	-- head: sits high on the neck; a bald dome of muscle over a long, flat-fronted face
	local up = 0.05
	add(m, head, "Cranium", "ball", V(0.84, 0.84, 0.84), CF(0, 0.12 + up, 0.06), M1, FAB)
	add(m, head, "Face", "block", V(0.7, 0.32, 0.76), CF(0, -0.06 + up, -0.04), M1, FAB)
	add(m, head, "Nose", "wedge", V(0.14, 0.2, 0.12), CF(0, -0.12 + up, -0.46), M1, FAB)
	add(m, head, "Jaw", "block", V(0.64, 0.14, 0.62), CF(0, -0.47 + up, -0.1), M1, FAB)
	add(m, head, "Chin", "block", V(0.3, 0.12, 0.1), CF(0, -0.49 + up, -0.44), M2, FAB)
	-- the mouth: recessed and dark, gums over and under, the teeth standing in front
	add(m, head, "Maw", "block", V(0.58, 0.18, 0.05), CF(0, -0.31 + up, -0.4), P.MouthDark)
	add(m, head, "Gums", "block", V(0.6, 0.05, 0.05), CF(0, -0.215 + up, -0.43), P.Gums)
	add(m, head, "Gums", "block", V(0.56, 0.05, 0.05), CF(0, -0.405 + up, -0.425), P.Gums)
	teethRow(m, head, 5, 0.26, -0.235 + up, -0.445, 0.03, 0.095, 0.08, P.Teeth, -1)
	teethRow(m, head, 5, 0.24, -0.385 + up, -0.44, 0.03, 0.095, 0.075, P.Teeth, 1)
	for _, s in ipairs(SIDES) do
		add(m, head, "Brow", "block", V(0.38, 0.12, 0.16), CF(s * 0.17, 0.065 + up, -0.41) * ANG(R(18), 0, R(s * 9)), M2, FAB)
		add(m, head, "Socket", "block", V(0.24, 0.14, 0.06), CF(s * 0.17, -0.03 + up, -0.42) * ANG(0, 0, R(s * 8)), P.MouthDark)
		add(m, head, "Eye", "block", V(0.045, 0.035, 0.03), CF(s * 0.17, -0.04 + up, -0.455), P.ColossusEye, NEON)
		add(m, head, "Cheekbone", "block", V(0.16, 0.09, 0.3), CF(s * 0.3, -0.1 + up, -0.3) * ANG(0, R(s * 22), 0), TE)
		add(m, head, "Masseter", "block", V(0.1, 0.26, 0.26), CF(s * 0.31, -0.31 + up, -0.28) * ANG(0, R(s * 22), 0), M2, FAB)
		add(m, head, "JawTendon", "block", V(0.04, 0.3, 0.04), CF(s * 0.35, -0.3 + up, -0.36) * ANG(0, R(s * 22), R(s * 12)), TE)
	end

	local st = { skin = M1, skin2 = M2, line = FI, joint = TE, mat = FAB, tendon = TE, w = 0.82, waist = 1.18, hips = 1.46, ribs = 3, neckDia = 0.6, neckLen = 0.62 }
	torso(m, L, st)
	arms(m, L, st)
	legs(m, L, st)

	-- torso accents: pale collarbones, sternum, belly line and the cross lines of the abs; fibre over the pecs
	for _, s in ipairs(SIDES) do
		add(m, ut, "Collarbone", "block", V(0.5, 0.05, 0.06), CF(s * 0.36, 0.64, -0.48) * ANG(0, 0, R(s * 14)), TE)
		add(m, ut, "PecFiber", "block", V(0.66, 0.035, 0.04), CF(s * 0.46, 0.46, -0.615) * ANG(R(10), 0, R(s * 22)), FI)
		add(m, ut, "LatFiber", "block", V(0.05, 0.8, 0.04), CF(s * 0.5, -0.05, 0.5) * ANG(0, 0, R(-s * 24)), FI)
	end
	add(m, ut, "Sternum", "block", V(0.1, 0.55, 0.06), CF(0, 0.42, -0.5), TE)
	add(m, ut, "Linea", "block", V(0.06, 0.82, 0.05), CF(0, -0.42, -0.45), TE)
	for k = 0, 1 do
		add(m, ut, "AbLine", "block", V(0.56, 0.04, 0.05), CF(0, -0.34 - k * 0.28, -0.45), FI)
	end
	add(m, ut, "Spine", "block", V(0.08, 1.5, 0.06), CF(0, -0.05, 0.5), TE:Lerp(M1, 0.35))
	-- limb accents: pale bands at the wrists and ankles, dark fibre along the biceps, forearms, thighs and shins
	local w = st.w
	for _, side in ipairs({ "Left", "Right" }) do
		local s = side == "Left" and -1 or 1
		local ua, la, ul, ll = L[side .. "UpperArm"], L[side .. "LowerArm"], L[side .. "UpperLeg"], L[side .. "LowerLeg"]
		if ua then
			fiber(ua, 0, -0.1, -0.41 * w, 0.5)
		end
		if la then
			post(m, la, "WristBand", 0.6 * w, 0.1, V(0, -0.5, 0), TE)
			fiber(la, s * 0.1, 0.05, -0.37 * w, 0.6, -s * 6)
		end
		if ul then
			fiber(ul, s * 0.05 - 0.1, 0.02, -0.5 * w, 0.8, 4)
			fiber(ul, s * 0.05 + 0.1, 0.02, -0.5 * w, 0.8, -4)
		end
		if ll then
			post(m, ll, "AnkleBand", 0.76 * w, 0.1, V(0, -0.6, 0), TE)
			fiber(ll, 0, -0.06, -0.36 * w, 0.9)
		end
	end

	-- more striation: long dark fibre bundles down the chest, belly and back, and across the deltoids, so the
	-- skinless body reads as raw muscle from 100 studs away instead of a red mannequin
	for _, s in ipairs(SIDES) do
		for k = 1, 3 do
			add(m, ut, "ChestFiber", "block", V(0.035, 0.62, 0.04), CF(s * (0.12 + k * 0.17), 0.3, -0.62 + k * 0.02) * ANG(R(10), 0, R(-s * (6 + k * 6))), FI)
			add(m, ut, "BackFiber", "block", V(0.035, 0.9, 0.04), CF(s * (0.1 + k * 0.18), 0.15, 0.53) * ANG(0, 0, R(s * (4 + k * 5))), FI)
		end
		add(m, ut, "Oblique", "block", V(0.04, 0.55, 0.04), CF(s * 0.56, -0.45, -0.38) * ANG(0, R(s * 30), R(s * 18)), FI)
		local ua = L[(s < 0 and "Left" or "Right") .. "UpperArm"]
		if ua then
			for k = -1, 1 do
				add(m, ua, "DeltFiber", "block", V(0.035, 0.5, 0.04), CF(k * 0.18, 0.22, -0.43 * w) * ANG(0, 0, R(k * 14)), FI)
			end
		end
	end

	-- steam vents off the shoulders and the upper back: small and rising, never a fog bank
	local vents = 0
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Trap" or p.Name == "Blade" then
			vent(p, CF(0, p.Size.Y * 0.45, 0), scale, p.Name == "Trap" and 2 or 1.5, vents % 2 == 0 and P.SteamWarm or P.Steam, 1.5, 1.4)
			vents += 1
		end
	end
	m.Parent = char
	-- the avatar under it becomes raw muscle (matte fabric, darker in the limbs' hollows)
	dress(char, m, function(name)
		return (name:find("Lower") or name:find("Hand") or name:find("Foot")) and M2 or M1
	end, FAB)
	return m
end

---------------------------------------------------------------------------------------------------
-- the gear: a belt and harness, a blade case and gas tank on each hip, the twin hook launchers (attachments HookL /
-- HookR are where the cables leave), a gas motor on the back (GasPort), and a long blade in each hand (TrailA /
-- TrailB carry the trail clients switch on for the spinning strike)
function TitanSkins.gear(char, cfg)
	local P = cfg.Palette
	local L = limbs(char)
	local lt, ut = L.LowerTorso, L.UpperTorso
	if not lt then
		return nil
	end
	local METAL = Enum.Material.Metal
	local m = Instance.new("Model")
	m.Name = "ShifterGear"
	add(m, lt, "Belt", "block", V(2.06, 0.16, 1.06), CF(0, 0.1, 0), P.Leather)
	if ut then
		add(m, ut, "ChestBelt", "block", V(1.98, 0.1, 1.04), CF(0, 0.25, 0), P.Leather)
		for _, s in ipairs(SIDES) do
			add(m, ut, "Strap", "block", V(0.12, 1.9, 0.04), CF(s * 0.35, 0, -0.52) * ANG(0, 0, R(22 * s)), P.Leather)
			add(m, ut, "Strap", "block", V(0.12, 1.9, 0.04), CF(s * 0.35, 0, 0.52) * ANG(0, 0, R(-22 * s)), P.Leather)
		end
	end
	local motor = add(m, lt, "Motor", "block", V(0.72, 0.42, 0.34), CF(0, 0.22, 0.66), P.SteelDark, METAL)
	local port = Instance.new("Attachment")
	port.Name = "GasPort"
	port.Position = V(0, 0, motor.Size.Z / 2)
	port.Parent = motor
	for _, s in ipairs(SIDES) do
		add(m, lt, "Nozzle", "rod", V(0.5, 0.16, 0.16), CF(s * 0.22, 0.22, 0.95) * ANG(0, R(90), 0), P.Steel, METAL)
		add(m, lt, "BladeBox", "block", V(0.32, 0.62, 1.55), CF(s * 1.2, -0.36, 0.12) * ANG(R(-12), 0, 0), P.SteelDark, METAL)
		add(m, lt, "BoxTrim", "block", V(0.34, 0.08, 1.57), CF(s * 1.2, -0.08, 0.15) * ANG(R(-12), 0, 0), P.Steel, METAL)
		add(m, lt, "Tank", "rod", V(1.25, 0.32, 0.32), CF(s * 1.2, 0.14, 0.28) * ANG(0, R(90), 0), P.Steel, METAL)
		local launcher = add(m, lt, "Launcher", "rod", V(0.6, 0.24, 0.24), CF(s * 1.13, 0.34, -0.32) * ANG(0, R(90), 0), P.SteelDark, METAL)
		local hook = Instance.new("Attachment")
		hook.Name = s < 0 and "HookL" or "HookR"
		hook.Position = V(launcher.Size.X / 2, 0, 0)
		hook.Parent = launcher
	end
	for _, side in ipairs({ "Left", "Right" }) do
		local hand = L[side .. "Hand"]
		if hand then
			add(m, hand, "Hilt", "block", V(0.22, 0.24, 0.66), CF(0, -0.16, -0.04), P.SteelDark, METAL)
			add(m, hand, "Guard", "block", V(0.28, 0.44, 0.08), CF(0, -0.16, -0.4), P.Steel, METAL)
			local blade = add(m, hand, "Blade", "block", V(0.05, 0.32, 4.2), CF(0, -0.16, -2.52), P.Blade, METAL)
			blade.Reflectance = 0.25
			add(m, hand, "Edge", "block", V(0.06, 0.05, 4.2), CF(0, -0.33, -2.52), P.BladeGlow, NEON, 0.35)
			local a0 = Instance.new("Attachment")
			a0.Name = "TrailA"
			a0.Position = V(0, 0, -blade.Size.Z / 2)
			a0.Parent = blade
			local a1 = Instance.new("Attachment")
			a1.Name = "TrailB"
			a1.Position = V(0, 0, blade.Size.Z * 0.15)
			a1.Parent = blade
			local tr = Instance.new("Trail")
			tr.Name = "SpinTrail"
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = ColorSequence.new(P.BladeGlow, Color3.new(1, 1, 1))
			tr.LightEmission = 1
			tr.LightInfluence = 0
			tr.Lifetime = 0.2
			tr.MinLength = 0.05
			tr.Transparency = NumberSequence.new({ kp(0, 0.15), kp(1, 1) })
			tr.Enabled = false
			tr.Parent = blade
		end
	end
	m.Parent = char
	return m
end

---------------------------------------------------------------------------------------------------
-- the swarm: naked, mismatched giants with too-wide grins and staring eyes. `rig` is an R15 rig already scaled.
-- The rig's own mannequin parts are hidden and a cheap version of the titan body (a few big shapes per limb) is
-- welded over them in the giant's own skin tone, with a random face, hair, belly and build.
local HAIRS = {
	Color3.fromRGB(38, 28, 22), Color3.fromRGB(86, 58, 36), Color3.fromRGB(132, 100, 64), Color3.fromRGB(22, 20, 20),
	Color3.fromRGB(110, 104, 98),
}
function TitanSkins.swarmling(rig, cfg, rng)
	local P = cfg.Palette
	local head = rig:FindFirstChild("Head")
	if not head then
		return
	end
	local skin = head.Color
	-- the mannequin underneath goes invisible (its own face too); the welded body is what everyone sees
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Decal") then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Transparency = 1
			d.CastShadow = false
		end
	end
	local L = limbs(rig)
	local m = Instance.new("Model")
	m.Name = "SwarmFace"
	local S2 = skin:Lerp(Color3.new(0, 0, 0), 0.12)
	local st = { skin = skin, skin2 = S2, line = S2, joint = S2, mat = SMOOTH, lite = true, w = rng:NextNumber(0.85, 1.05), waist = rng:NextNumber(1.3, 1.6) }
	torso(m, L, st)
	arms(m, L, st)
	legs(m, L, st)
	local ut = L.UpperTorso
	if ut and rng:NextNumber() < 0.4 then
		-- a soft round belly on some of them
		add(m, ut, "Belly", "rod", V(1.05, 0.74, 0.74), CF(0, -0.42, -0.2), skin)
	end

	-- the face: one skull block, a dark grin with the teeth clenched in it, wide staring eyes with small pupils
	local grin = rng:NextNumber(0.5, 0.66)
	local eyeY = rng:NextNumber(-0.02, 0.06)
	add(m, head, "Skull", "block", V(0.8, 0.84, 0.84), CF(0, 0.04, 0), skin)
	add(m, head, "Jaw", "block", V(0.66, 0.16, 0.62), CF(0, -0.41, -0.08), S2)
	add(m, head, "Nose", "wedge", V(0.14, 0.22, 0.12), CF(0, -0.14, -0.48), skin)
	add(m, head, "Brow", "block", V(0.68, 0.07, 0.1), CF(0, eyeY + 0.09, -0.43), S2)
	add(m, head, "Mouth", "block", V(grin, 0.1, 0.04), CF(0, -0.29, -0.43), P.MouthDark)
	add(m, head, "Teeth", "block", V(grin * 0.9, 0.045, 0.04), CF(0, -0.29, -0.445), P.Teeth)
	for _, s in ipairs(SIDES) do
		-- the corners of the grin curl up into the cheeks
		add(m, head, "GrinCorner", "block", V(0.12, 0.06, 0.04), CF(s * (grin / 2 + 0.03), -0.25, -0.43) * ANG(0, 0, R(s * 40)), P.MouthDark)
		local e = rng:NextNumber(0.13, 0.19)
		add(m, head, "Eye", "block", V(e, e * 0.8, 0.04), CF(s * 0.17, eyeY, -0.43), Color3.fromRGB(240, 236, 226))
		add(m, head, "Pupil", "block", V(0.05, 0.05, 0.03), CF(s * 0.17 + rng:NextNumber(-0.03, 0.03), eyeY + rng:NextNumber(-0.02, 0.02), -0.455), Color3.fromRGB(18, 12, 10))
		add(m, head, "Ear", "block", V(0.07, 0.22, 0.15), CF(s * 0.42, -0.06, 0.02), S2)
	end
	-- hair: bald, cropped, or long down the back
	local style = rng:NextNumber()
	if style > 0.3 then
		local hc = HAIRS[rng:NextInteger(1, #HAIRS)]
		add(m, head, "Hair", "block", V(0.88, 0.18, 0.9), CF(0, 0.5, 0.03), hc)
		if style > 0.65 then
			add(m, head, "Hair", "block", V(0.9, 0.8, 0.16), CF(0, 0.1, 0.47) * ANG(R(-6), 0, 0), hc)
		end
	end
	local chest = m:FindFirstChild("Chest")
	if chest then
		vent(chest, CF(0, chest.Size.Y * 0.5, 0), rig:GetScale(), 1, P.Steam, 1.6, 1)
	end
	m.Parent = rig
	return m
end

return TitanSkins
