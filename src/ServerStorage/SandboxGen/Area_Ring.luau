--!nocheck
-- BOXING RING: a raised canvas with ropes, corner posts, a lighting truss, bleachers and a heavy bag on a rope.
local function station(K, model, cf, kind, every, max, extra)
	local attrs = { Kind = kind, Every = every or 8, Max = max or 1 }
	for k, v in pairs(extra or {}) do
		attrs[k] = v
	end
	return K.part(model, "Station", Vector3.new(2, 0.2, 2), cf, nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "DummyStation", attrs = attrs })
end
return function(K, model, cf, A)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local S, HGT = 40, 4
	K.part(model, "Skirt", Vector3.new(S, HGT - 0.4, S), L(0, (HGT - 0.4) / 2 + 0.4, 0), C(24, 40, 96), Enum.Material.Fabric)
	K.part(model, "Apron", Vector3.new(S + 3, 0.5, S + 3), L(0, HGT + 0.05, 0), C(30, 34, 46), Enum.Material.SmoothPlastic)
	K.part(model, "Canvas", Vector3.new(S, 0.5, S), L(0, HGT + 0.35, 0), C(208, 216, 224), Enum.Material.Fabric)
	K.cyl(model, "Logo", 14, 0.52, L(0, HGT + 0.36, 0), PAL.red, Enum.Material.Fabric, { CastShadow = false })
	K.cyl(model, "LogoIn", 10, 0.54, L(0, HGT + 0.36, 0), C(208, 216, 224), Enum.Material.Fabric, { CastShadow = false })
	local cols = { PAL.red, PAL.blue, PAL.white, PAL.white }
	local corners = { { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }
	local h = S / 2 - 1
	for i, c in ipairs(corners) do
		K.cyl(model, "Post", 1.5, 9.5, L(c[1] * h, HGT + 4.9, c[2] * h), cols[i], Enum.Material.Metal)
		K.part(model, "Pad", Vector3.new(2.2, 5.2, 2.2), L(c[1] * (h - 0.9), HGT + 5.6, c[2] * (h - 0.9)) * CFrame.Angles(0, math.rad(45), 0), cols[i], Enum.Material.Fabric)
	end
	local ropeCols = { PAL.red, PAL.white, PAL.blue }
	for lvl = 1, 3 do
		local y = HGT + 2.6 + lvl * 1.7
		for _, side in ipairs({ { 0, -h, 0 }, { 0, h, 0 }, { -h, 0, 90 }, { h, 0, 90 } }) do
			K.cyl(model, "Rope", 0.38, S - 2, L(side[1], y, side[2]) * CFrame.Angles(0, math.rad(side[3]), math.rad(90)), ropeCols[lvl], Enum.Material.Fabric, { CastShadow = false })
		end
	end
	for _, s in ipairs({ { -h - 3.4, -h + 3, 0 }, { h + 3.4, h - 3, 0 } }) do -- steps at two corners
		for k = 1, 3 do
			K.part(model, "Stair", Vector3.new(4, 1.4, 5), L(s[1] + (s[1] < 0 and (3 - k) * -1.6 or (3 - k) * 1.6) * -1 + (s[1] < 0 and 3.2 or -3.2), 0.4 + k * 1.3 - 0.7, s[2]), PAL.steelDark, Enum.Material.DiamondPlate)
		end
	end
	-- lighting truss
	local TY = 30
	for _, c in ipairs(corners) do
		K.truss(model, "TrussLeg", Vector3.new(2, TY, 2), L(c[1] * (h + 5), TY / 2 + 0.4, c[2] * (h + 5)), PAL.steelDark)
	end
	for _, side in ipairs({ { 0, -h - 5, 0 }, { 0, h + 5, 0 }, { -h - 5, 0, 90 }, { h + 5, 0, 90 } }) do
		K.truss(model, "Truss", Vector3.new(2, 2, S + 10), L(side[1], TY + 1.4, side[2]) * CFrame.Angles(0, math.rad(side[3] + 90), 0), PAL.steelDark)
	end
	for _, c in ipairs({ { -1, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }) do
		local can = K.cyl(model, "Spot", 2.4, 2.6, L(c[1] * 12, TY - 0.6, c[2] * 12), C(30, 30, 34), Enum.Material.Metal, { CastShadow = false })
		local lens = K.cyl(model, "Lens", 2, 0.2, L(c[1] * 12, TY - 2, c[2] * 12), C(255, 244, 214), Enum.Material.Neon, { CastShadow = false })
		K.new("SpotLight", { Face = Enum.NormalId.Left, Angle = 70, Range = 46, Brightness = 2.4, Color = C(255, 240, 214), Shadows = false }, lens)
	end
	-- bleachers either side
	for _, sx in ipairs({ -1, 1 }) do
		for tier = 1, 4 do
			K.part(model, "Bleacher", Vector3.new(4, 1.6 * tier, 34), L(sx * (h + 8 + tier * 4), 0.4 + 0.8 * tier, 0), (tier % 2 == 0) and PAL.wood or PAL.woodDark, Enum.Material.WoodPlanks)
		end
	end
	-- the heavy bag: a real body on a rope
	local fx, fz = -30, -34
	K.part(model, "BagPostA", Vector3.new(1, 13, 1), L(fx - 5, 6.9, fz), PAL.steelDark, Enum.Material.Metal)
	K.part(model, "BagPostB", Vector3.new(1, 13, 1), L(fx + 5, 6.9, fz), PAL.steelDark, Enum.Material.Metal)
	local beam = K.part(model, "BagBeam", Vector3.new(11, 1, 1), L(fx, 13.6, fz), PAL.steelDark, Enum.Material.Metal)
	local bag = K.cyl(model, "HeavyBag", 3.2, 7, L(fx, 6.4, fz), PAL.red, Enum.Material.Fabric, { Anchored = false })
	bag.CustomPhysicalProperties = PhysicalProperties.new(1.4, 0.6, 0.2)
	local a0 = K.new("Attachment", { Position = Vector3.new(0, -0.5, 0) }, beam)
	local a1 = K.new("Attachment", { Position = Vector3.new(3.5, 0, 0) }, bag)
	K.new("RopeConstraint", { Attachment0 = a0, Attachment1 = a1, Length = 3.2, Visible = true, Thickness = 0.25, Color = BrickColor.new("Dark stone grey") }, beam)
	station(K, model, L(-8, HGT + 0.7, 0) * CFrame.Angles(0, math.rad(-90), 0), "stand", 6, 1)
	station(K, model, L(8, HGT + 0.7, 0) * CFrame.Angles(0, math.rad(90), 0), "stand", 6, 1)
	station(K, model, L(0, HGT + 0.7, 9), "stand", 9, 1)
	K.sign(model, "FIGHT NIGHT", L(0, TY + 5, -h - 5), Vector2.new(22, 4), { trim = PAL.red, glow = true })
end
