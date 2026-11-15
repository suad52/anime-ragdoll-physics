--!nocheck
-- StormdrawKit.Client.Katana: the sword every Stormdraw fighter carries, built on each client for each fighter (it is
-- only ever looked at: hits are decided on the server from positions and directions, never from the blade).
--   Katana.attach(char, pal) -> rig     a scabbard on the left hip and the sword inside it (idempotent)
--   Katana.detach(char)
--   Katana.get(char) -> rig | nil
--   Katana.setDrawn(char, drawn)        in the right fist (Motor6D "SwordGrip", animatable) / back in the scabbard
--   Katana.swing(char, seconds)         lights the blade's trail for that long
--   Katana.points(char) -> base, tip    world positions of the two ends of the blade
--   Katana.mouth(char) -> Vector3       the scabbard's mouth (where the draw sparks come from)
-- rig = { model, handle, scabbard, grip, sheath, baseAtt, tipAtt, mouthAtt, trail, light, drawn }
-- The Handle's -Z runs to the tip, -Y is the cutting edge. Re-skin: Config.Katana.Colors, or put your own Models named
-- Config.Katana.SwordTemplate / ScabbardTemplate in ReplicatedStorage.StormdrawKit (see Config).
local Kit = script.Parent.Parent
local CFG = require(Kit:WaitForChild("Config"))
local K = CFG.Katana

local Katana = {}
local rigs = setmetatable({}, { __mode = "k" }) -- [character] = rig
local R = math.rad

-- where the sheathed Handle sits, in the LowerTorso's space: in front of the left hip, the grip forward and a little
-- inward, the scabbard running back, down and out, edge up
local HIP = CFrame.new(-0.82, 0.52, -1.06) * CFrame.Angles(0, R(166), 0) * CFrame.Angles(R(-20), 0, 0) * CFrame.Angles(0, 0, R(180))
local GRIP_AT = CFrame.new(0, 0, -0.25) -- the point of the Handle the fist closes on (toward the guard)

local function piece(name, size, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function attach(root, part, offset)
	part.CFrame = root.CFrame * offset
	local w = Instance.new("Weld")
	w.Name = "KatanaWeld"
	w.Part0, w.Part1 = root, part
	w.C0 = offset
	w.Parent = part
	return w
end

-- the curve the blade and the scabbard share: the frame at the start of each segment (in the Handle's space), the
-- frame at the far end, and one segment's length
local function curveFrames(startZ, length, segs)
	local frames = {}
	local f = CFrame.new(0, 0, startZ)
	local len = length / segs
	for i = 1, segs do
		frames[i] = f
		f = f * CFrame.new(0, 0, -len) * CFrame.Angles(R(K.Curve), 0, 0)
	end
	return frames, f, len
end

local function namedAttachment(part, name, cf)
	local a = part:FindFirstChild(name)
	if not a or not a:IsA("Attachment") then
		a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = cf
		a.Parent = part
	end
	return a
end

-- a Model from the kit folder used in place of a built-in piece (every part welded to its root part)
local function fromTemplate(name, rootName)
	local t = Kit:FindFirstChild(name)
	if not t or not t:IsA("Model") then
		return nil
	end
	local m = t:Clone()
	local root = m:FindFirstChild(rootName, true)
	if not root or not root:IsA("BasePart") then
		m:Destroy()
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			d.Massless = true
			if d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = root, d
				w.Parent = d
			end
		end
	end
	return m, root
end

local function buildSword(model, col, frames, tipFrame, len)
	local hl = K.HandleLength
	local handle = piece("Handle", Vector3.new(0.22, 0.3, hl), col.Wrap, Enum.Material.Fabric, model)
	local function add(name, size, color, material, offset)
		local p = piece(name, size, color, material, model)
		attach(handle, p, offset)
		return p
	end
	add("Pommel", Vector3.new(0.28, 0.36, 0.14), col.Guard, Enum.Material.Metal, CFrame.new(0, 0, hl / 2 + 0.04))
	add("Collar", Vector3.new(0.28, 0.36, 0.1), col.Guard, Enum.Material.Metal, CFrame.new(0, 0, -hl / 2 + 0.02))
	for i = -1, 1 do -- the wrap's diamonds
		add("Diamond", Vector3.new(0.235, 0.12, 0.12), col.Guard, Enum.Material.Metal, CFrame.new(0, 0, i * hl * 0.26) * CFrame.Angles(R(45), 0, 0))
	end
	local guard = add("Guard", Vector3.new(0.08, 0.86, 0.86), col.Guard, Enum.Material.Metal, CFrame.new(0, 0, -hl / 2 - 0.07) * CFrame.Angles(0, R(90), 0))
	guard.Shape = Enum.PartType.Cylinder
	add("Habaki", Vector3.new(0.13, 0.3, 0.16), col.Guard, Enum.Material.Metal, frames[1] * CFrame.new(0, 0, 0.06))
	for i, f in ipairs(frames) do
		local h = 0.27 * (1 - 0.28 * (i - 1) / #frames)
		local blade = add("Blade", Vector3.new(0.06, h, len * 1.06), col.Blade, Enum.Material.Metal, f * CFrame.new(0, 0, -len / 2))
		blade.Reflectance = 0.35
		add("Edge", Vector3.new(0.068, 0.05, len * 1.06), col.Edge, Enum.Material.Neon, f * CFrame.new(0, -h / 2 + 0.02, -len / 2))
	end
	local tip = add("Tip", Vector3.new(0.06, 0.15, 0.36), col.Blade, Enum.Material.Metal, tipFrame * CFrame.new(0, 0.03, -0.13) * CFrame.Angles(R(16), 0, 0))
	tip.Reflectance = 0.35
	return handle
end

local function buildScabbard(model, col, frames, tipFrame, len)
	local root = piece("ScabbardRoot", Vector3.new(0.2, 0.2, 0.2), col.Scabbard, nil, model)
	root.Transparency = 1
	local function add(name, size, color, material, offset)
		local p = piece(name, size, color, material, model)
		attach(root, p, offset)
		return p
	end
	for _, f in ipairs(frames) do
		add("Saya", Vector3.new(0.2, 0.42, len * 1.08), col.Scabbard, Enum.Material.SmoothPlastic, f * CFrame.new(0, 0, -len / 2)).Reflectance = 0.12
	end
	add("SayaEnd", Vector3.new(0.2, 0.4, 0.4), col.Scabbard, Enum.Material.SmoothPlastic, tipFrame * CFrame.new(0, 0, -0.16))
	add("Mouth", Vector3.new(0.25, 0.48, 0.16), col.Band, Enum.Material.Metal, frames[1] * CFrame.new(0, 0, -0.06))
	add("Band", Vector3.new(0.25, 0.48, 0.12), col.Band, Enum.Material.Metal, frames[math.min(3, #frames)])
	add("Cap", Vector3.new(0.25, 0.46, 0.14), col.Band, Enum.Material.Metal, tipFrame * CFrame.new(0, 0, -0.34))
	add("Cord", Vector3.new(0.14, 0.2, 0.3), col.Cord, Enum.Material.Fabric, frames[1] * CFrame.new(0.14, 0, -0.55))
	return root
end

function Katana.get(char)
	local rig = rigs[char]
	if rig and rig.model.Parent then
		return rig
	end
	return nil
end

function Katana.attach(char, pal)
	local rig = Katana.get(char)
	if rig then
		return rig
	end
	local hand = char:FindFirstChild("RightHand")
	local hip = char:FindFirstChild("LowerTorso")
	if not hand or not hip then
		return nil -- not an R15 body
	end
	pal = pal or CFG.Palette
	local col = K.Colors
	local model = Instance.new("Model")
	model.Name = "StormKatana"
	local z0 = -(K.HandleLength / 2 + 0.2)
	local frames, tipFrame, len = curveFrames(z0, K.BladeLength, K.BladeSegments)

	-- the scabbard (your own model, or the built-in one)
	local scabbard
	local sModel, sRoot = fromTemplate(K.ScabbardTemplate, "ScabbardRoot")
	if sModel then
		sModel.Parent = model
		scabbard = sRoot
	else
		scabbard = buildScabbard(model, col, frames, tipFrame, len)
	end
	local mouthAtt = namedAttachment(scabbard, "Mouth", frames[1])
	local hipWeld = Instance.new("Weld")
	hipWeld.Name = "ScabbardHip"
	hipWeld.Part0, hipWeld.Part1 = hip, scabbard
	hipWeld.C0 = HIP
	hipWeld.Parent = scabbard

	-- the sword
	local handle
	local kModel, kRoot = fromTemplate(K.SwordTemplate, "Handle")
	if kModel then
		kModel.Parent = model
		handle = kRoot
	else
		handle = buildSword(model, col, frames, tipFrame, len)
	end
	local baseAtt = namedAttachment(handle, "BladeBase", frames[1])
	local tipAtt = namedAttachment(handle, "BladeTip", tipFrame * CFrame.new(0, 0, -0.28))

	-- two homes: in the scabbard (a weld), or in the right fist (a Motor6D the animator can turn). One is on at a time.
	local sheath = Instance.new("Weld")
	sheath.Name = "Sheath"
	sheath.Part0, sheath.Part1 = scabbard, handle
	sheath.Parent = handle
	local gripAtt = hand:FindFirstChild("RightGripAttachment")
	local grip = Instance.new("Motor6D")
	grip.Name = "SwordGrip"
	grip.Part0, grip.Part1 = hand, handle
	grip.C0 = CFrame.new(gripAtt and gripAtt.Position or Vector3.new(0, -0.15, 0))
	grip.C1 = GRIP_AT
	grip.Enabled = false
	grip.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "BladeTrail"
	trail.Attachment0, trail.Attachment1 = baseAtt, tipAtt
	trail.Color = ColorSequence.new(pal.BoltCore, pal.Slash)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.16
	trail.MinLength = 0.03
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = handle

	local light = Instance.new("PointLight")
	light.Name = "BladeGlow"
	light.Color = pal.Bolt
	light.Range = 9
	light.Brightness = 0
	light.Shadows = false
	light.Parent = handle

	model.Parent = char
	rig = { model = model, handle = handle, scabbard = scabbard, grip = grip, sheath = sheath, baseAtt = baseAtt, tipAtt = tipAtt,
		mouthAtt = mouthAtt, trail = trail, light = light, drawn = false, swingUntil = 0 }
	rigs[char] = rig
	return rig
end

function Katana.detach(char)
	local rig = rigs[char]
	rigs[char] = nil
	if rig and rig.model then
		rig.model:Destroy()
	end
end

function Katana.setDrawn(char, drawn)
	local rig = Katana.get(char)
	if not rig or rig.drawn == drawn then
		return rig
	end
	rig.drawn = drawn
	-- the outgoing joint goes off first, so the Handle is never held by both for a frame
	if drawn then
		rig.sheath.Enabled = false
		rig.grip.Enabled = true
	else
		rig.grip.Enabled = false
		rig.sheath.Enabled = true
	end
	return rig
end

function Katana.swing(char, seconds)
	local rig = Katana.get(char)
	if not rig then
		return
	end
	local untilT = os.clock() + seconds
	rig.swingUntil = math.max(rig.swingUntil, untilT)
	rig.trail.Enabled = true
	task.delay(seconds + 0.02, function()
		if rig.model.Parent and os.clock() >= rig.swingUntil then
			rig.trail.Enabled = false
		end
	end)
end

function Katana.points(char)
	local rig = Katana.get(char)
	if rig then
		return rig.baseAtt.WorldPosition, rig.tipAtt.WorldPosition
	end
	return nil
end

function Katana.mouth(char)
	local rig = Katana.get(char)
	return rig and rig.mouthAtt.WorldPosition or nil
end

return Katana
