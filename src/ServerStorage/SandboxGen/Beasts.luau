--!nocheck
-- SandboxGen.Beasts: the three animals, built from blocks. Root = the collision body (anchored here; Sandbox.Beasts
-- unanchors it and drives it with AlignPosition / AlignOrientation). Everything else is massless and rides it:
-- plain parts on WeldConstraints, jointed parts on Welds named J_<joint> that the CLIENT animates through C0
-- (StarterPlayerScripts.SandboxWorld). An Attachment named Mouth marks where prey is held. Forward is -Z.
local Beasts = {}
local V, N, A = Vector3.new, CFrame.new, CFrame.Angles
local function kit(K, parent, name, rootCF, rootSize, color)
	local m = K.model(parent, name)
	local root = K.part(m, "Root", rootSize, rootCF, color, Enum.Material.SmoothPlastic)
	m.PrimaryPart = root
	local B = { model = m, root = root }
	local function make(pname, size, off, col, shape)
		local fn = (shape == "wedge") and K.wedge or K.part
		return fn(m, pname, size, rootCF * off, col, Enum.Material.SmoothPlastic, { Anchored = false, Massless = true })
	end
	function B.P(pname, size, off, col, on, shape)
		local p = make(pname, size, off, col, shape)
		K.weld(on or root, p)
		return p
	end
	function B.J(jname, pname, size, off, col, pivot, on, shape)
		local p = make(pname, size, off, col, shape)
		local w = Instance.new("Weld")
		w.Name = jname
		w.Part0, w.Part1 = on or root, p
		local pw = rootCF * pivot
		w.C0, w.C1 = (on or root).CFrame:ToObjectSpace(pw), p.CFrame:ToObjectSpace(pw)
		w.Parent = p
		return p
	end
	function B.mouth(part, off)
		local a = Instance.new("Attachment")
		a.Name = "Mouth"
		a.Parent = part
		a.WorldCFrame = rootCF * off
	end
	function B.finish(kind)
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and math.max(p.Size.X, p.Size.Y, p.Size.Z) < 1.8 then
				p.CanCollide = false
				p.CastShadow = false
			end
		end
		K.tag(m, "Beast", { Kind = kind })
		return m
	end
	return B
end
function Beasts.rex(K, parent, cf)
	local C = K.C
	local skin, dark, belly, bone = C(98, 114, 64), C(68, 82, 48), C(186, 174, 122), C(240, 236, 220)
	local B = kit(K, parent, "Rex", cf * N(0, 12, 0), V(8, 9, 16), skin)
	B.P("Belly", V(6.6, 3, 13), N(0, -4.4, 0.4), belly)
	B.P("Back", V(5, 2, 13), N(0, 5, 0.5), dark)
	B.P("Chest", V(6.6, 8, 8), N(0, 2.6, -9.5) * A(math.rad(32), 0, 0), skin)
	local head = B.J("J_Head", "Head", V(6, 5.2, 11), N(0, 8.4, -17.5), skin, N(0, 7.5, -12.5))
	B.P("Snout", V(5, 3.6, 5), N(0, 7.9, -24.6), skin, head)
	for _, sx in ipairs({ -1, 1 }) do
		B.P("Brow", V(1, 1.2, 3.6), N(sx * 2.9, 11.3, -14.6), dark, head)
		B.P("Eye", V(0.5, 0.9, 1.1), N(sx * 3.05, 10.1, -15), C(255, 210, 60), head).Material = Enum.Material.Neon
		B.P("Arm", V(1.2, 3.2, 1.2), N(sx * 3.7, -1.6, -8.8) * A(math.rad(-40), 0, 0), skin)
		for i = 0, 5 do
			B.P("Tooth", V(0.5, 1.2, 0.7), N(sx * 2.5, 5.5, -15.5 - i * 2), bone, head)
		end
	end
	local jaw = B.J("J_Jaw", "Jaw", V(5, 1.7, 12.6), N(0, 4.3, -19.6), dark, N(0, 5.2, -13), head)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 4 do
			B.P("Tooth", V(0.45, 1, 0.6), N(sx * 2.2, 5.5, -16.5 - i * 2.1), bone, jaw)
		end
	end
	B.mouth(head, N(0, 5.2, -23))
	local t1 = B.J("J_Tail1", "Tail1", V(6.2, 6.4, 10), N(0, 0.4, 12.5), skin, N(0, 0.4, 8))
	local t2 = B.J("J_Tail2", "Tail2", V(4.4, 4.6, 10), N(0, 0.8, 22), skin, N(0, 0.8, 17.5), t1)
	B.J("J_Tail3", "Tail3", V(2.6, 2.8, 10), N(0, 1.1, 31.5), dark, N(0, 1.1, 27), t2)
	for _, sx in ipairs({ -1, 1 }) do
		local thigh = B.J(sx < 0 and "J_LegL" or "J_LegR", "Thigh", V(3.6, 8.4, 5.8), N(sx * 5, -3.4, 1.2) * A(math.rad(-14), 0, 0), skin, N(sx * 5, 0, 1.2))
		B.P("Shin", V(2.6, 6.6, 2.8), N(sx * 5, -8, 3) * A(math.rad(20), 0, 0), skin, thigh)
		B.P("Foot", V(3.8, 1.5, 7.4), N(sx * 5, -11.25, -0.4), dark, thigh)
		for i = -1, 1 do
			B.P("Claw", V(0.8, 0.9, 1.6), N(sx * 5 + i * 1.2, -11.5, -4.6), bone, thigh)
		end
	end
	for i = 0, 5 do
		B.P("Spine", V(0.8, 1.4, 1.8), N(0, 6.4, -5 + i * 2.6), dark)
	end
	return B.finish("rex")
end
function Beasts.bear(K, parent, cf)
	local C = K.C
	local fur, dark, muzzle = C(108, 76, 48), C(76, 52, 34), C(180, 144, 104)
	local B = kit(K, parent, "Bear", cf * N(0, 5.7, 0), V(6, 5.4, 11), fur)
	B.P("Hump", V(5, 2, 4.4), N(0, 3, -3), fur)
	B.P("Rump", V(5.4, 4.6, 3), N(0, -0.2, 6.2), fur)
	B.P("Tail", V(1.3, 1.3, 1.3), N(0, 1, 8), dark)
	local head = B.J("J_Head", "Head", V(4.2, 3.8, 4), N(0, 1.6, -7.2), fur, N(0, 1.4, -5.4))
	B.P("Snout", V(2.3, 1.7, 2.4), N(0, 1.1, -10.2), muzzle, head)
	B.P("Nose", V(1, 0.8, 0.6), N(0, 1.6, -11.5), C(20, 18, 18), head)
	for _, sx in ipairs({ -1, 1 }) do
		B.P("Ear", V(1.2, 1.2, 0.6), N(sx * 1.6, 3.8, -6.6), dark, head)
		B.P("Eye", V(0.4, 0.5, 0.4), N(sx * 1.2, 2.5, -9.25), C(16, 14, 14), head)
	end
	B.J("J_Jaw", "Jaw", V(2, 0.6, 2.2), N(0, 0, -10.1), dark, N(0, 0.3, -9), head)
	B.mouth(head, N(0, 0.4, -11.4))
	for _, d in ipairs({ { "J_LegFL", -1, -3.9 }, { "J_LegFR", 1, -3.9 }, { "J_LegBL", -1, 3.9 }, { "J_LegBR", 1, 3.9 } }) do
		local leg = B.J(d[1], "Leg", V(2.3, 4.8, 2.6), N(d[2] * 2.3, -3.3, d[3]), dark, N(d[2] * 2.3, -1.2, d[3]))
		B.P("Paw", V(2.5, 0.9, 3.2), N(d[2] * 2.3, -5.25, d[3] - 0.4), dark, leg)
	end
	return B.finish("bear")
end
function Beasts.shark(K, parent, cf)
	local C = K.C
	local top, belly = C(92, 110, 128), C(226, 230, 232)
	local B = kit(K, parent, "Shark", cf, V(4.8, 4.4, 11), top)
	B.P("Belly", V(4.2, 1.4, 10.4), N(0, -1.7, 0), belly)
	B.P("Nose", V(4.6, 3.8, 5.6), N(0, -0.3, -8.3), top, nil, "wedge")
	B.P("Chin", V(4, 1, 4.4), N(0, -1.8, -7.4), belly)
	B.P("Mouthline", V(3.4, 0.3, 3), N(0, -2.35, -7.6), C(120, 30, 34))
	B.P("Teeth", V(3.2, 0.5, 0.3), N(0, -2.5, -9.2), C(244, 244, 240))
	B.P("Dorsal", V(0.6, 4.6, 4.2), N(0, 4.4, 0.8), top, nil, "wedge")
	for _, sx in ipairs({ -1, 1 }) do
		B.P("Fin", V(3.8, 0.4, 2.6), N(sx * 3.9, -1.6, -2) * A(0, 0, math.rad(sx * -22)), top)
		B.P("Eye", V(0.3, 0.6, 0.6), N(sx * 2.25, 0.6, -7.2), C(10, 10, 12))
	end
	local tail = B.J("J_Tail1", "Tail", V(3, 3, 6), N(0, 0.1, 8.3), top, N(0, 0, 5.5))
	B.P("TailUp", V(0.5, 5.2, 3.6), N(0, 3.6, 12.2), top, tail, "wedge")
	B.P("TailDown", V(0.5, 3, 2.6), N(0, -2.4, 11.8) * A(0, 0, math.pi), top, tail, "wedge")
	B.mouth(B.root, N(0, -1.2, -9.4))
	return B.finish("shark")
end
return Beasts
