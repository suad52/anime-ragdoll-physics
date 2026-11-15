--!nocheck
-- THE WORKSHOP: dummies drop onto a conveyor (tag Conveyor) that carries them through twin saws (tag Saw), under a
-- hydraulic press (tag Press) and into the fire pit (rollers = Saw; the DummyDrain zone, Mode "fire", burns what
-- lands in it - Sandbox.Hazards). A test bay by the entrance has three dummies to work on by hand.
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
	local BZ, BY = 12, 4
	local xdir = cf.RightVector
	-- conveyor
	for i = 0, 8 do
		local x = -32 + i * 8
		local c = L(x, BY, BZ)
		K.part(model, "Belt", Vector3.new(7.2, 0.6, 8.1), CFrame.lookAt(c.Position, c.Position + xdir), (i % 2 == 0) and C(34, 34, 38) or C(44, 44, 50), Enum.Material.Fabric, { tag = "Conveyor", attrs = { Conveyor = 9 } })
	end
	for _, z in ipairs({ -4.1, 4.1 }) do
		K.part(model, "BeltRail", Vector3.new(73, 1.2, 1), L(0, BY, BZ + z), PAL.steel, Enum.Material.Metal)
	end
	for x = -34, 34, 17 do
		for _, z in ipairs({ -4.1, 4.1 }) do
			K.part(model, "BeltLeg", Vector3.new(1, BY - 0.6, 1), L(x, (BY - 0.6) / 2 + 0.4, BZ + z), PAL.steelDark, Enum.Material.Metal)
		end
	end
	for _, z in ipairs({ -7.5, 7.5 }) do
		for i = 0, 17 do
			K.part(model, "Stripe", Vector3.new(4, 0.06, 1.2), L(-34 + i * 4, 0.43, BZ + z), (i % 2 == 0) and PAL.hazard or C(24, 24, 28), Enum.Material.SmoothPlastic, { CastShadow = false })
		end
	end
	-- loader deck
	K.part(model, "LoaderDeck", Vector3.new(10, 0.6, 10), L(-41, 9.6, BZ), PAL.steel, Enum.Material.DiamondPlate)
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		K.part(model, "LoaderLeg", Vector3.new(0.8, 9, 0.8), L(-41 + c[1] * 4.4, 4.9, BZ + c[2] * 4.4), PAL.steelDark, Enum.Material.Metal)
	end
	K.part(model, "Chute", Vector3.new(8, 0.5, 9), L(-36.4, 7.2, BZ) * CFrame.Angles(0, 0, math.rad(-38)) * CFrame.Angles(0, math.rad(90), 0), PAL.hazard, Enum.Material.SmoothPlastic, { CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0.1, 100, 1) })
	-- twin saws
	local SX = -12
	for _, z in ipairs({ -6.4, 6.4 }) do
		K.part(model, "SawColumn", Vector3.new(1.4, 14, 1.4), L(SX, 7.4, BZ + z), PAL.hazard, Enum.Material.Metal)
	end
	K.part(model, "SawBeam", Vector3.new(1.6, 1.6, 14.2), L(SX, 14.6, BZ), PAL.hazard, Enum.Material.Metal)
	K.cyl(model, "SawShaft", 0.9, 12.6, L(SX, BY + 5.6, BZ) * CFrame.Angles(math.rad(90), 0, 0), PAL.steelDark, Enum.Material.Metal)
	for _, z in ipairs({ -2.1, 2.1 }) do
		local blade = K.cyl(model, "Saw", 9, 0.35, L(SX, BY + 5.6, BZ + z) * CFrame.Angles(math.rad(90), 0, 0), C(188, 192, 200), Enum.Material.Metal, { tag = "Saw", attrs = { Spin = 20, Damage = 42 } })
		K.new("ParticleEmitter", { Name = "Sparks", Enabled = false, Rate = 0, Lifetime = NumberRange.new(0.2, 0.5), Speed = NumberRange.new(20, 40), SpreadAngle = Vector2.new(40, 40),
			Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1, Color = ColorSequence.new(C(255, 220, 140)), Size = NumberSequence.new(0.5, 0) }, blade)
		for k = 0, 3 do -- slots so the spin reads
			local slot = K.part(model, "SawSlot", Vector3.new(0.4, 2.4, 0.5), blade.CFrame * CFrame.Angles(k * math.pi / 2, 0, 0) * CFrame.new(0, 2.6, 0), C(40, 42, 48), Enum.Material.Metal, { Anchored = false, CanCollide = false, Massless = true, CastShadow = false })
			K.new("WeldConstraint", { Part0 = blade, Part1 = slot }, slot)
		end
		K.cyl(model, "SawHub", 2, 0.5, blade.CFrame * CFrame.Angles(0, 0, -math.pi / 2), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
	end
	-- hydraulic press
	local PX = 12
	for _, z in ipairs({ -7, 7 }) do
		K.part(model, "PressColumn", Vector3.new(2.4, 18, 2.4), L(PX, 9.4, BZ + z), C(60, 90, 150), Enum.Material.Metal)
	end
	K.part(model, "PressBeam", Vector3.new(4, 3, 17), L(PX, 19.6, BZ), C(60, 90, 150), Enum.Material.Metal)
	K.cyl(model, "PressRod", 2, 9, L(PX, 15, BZ), C(200, 204, 210), Enum.Material.Metal)
	K.part(model, "Press", Vector3.new(9, 3, 7.4), L(PX, 11.5, BZ), PAL.steelDark, Enum.Material.Metal, { tag = "Press", attrs = { Travel = 6.5, Period = 3.4, Damage = 90 } })
	K.sign(model, "CRUSH ZONE", L(PX, 22.6, BZ - 8.6), Vector2.new(12, 2.2), { back = PAL.hazard, color = C(20, 20, 24), strokeW = 0, trim = C(20, 20, 24), pps = 26 })
	-- grinder bin
	local GX = 40
	for _, s in ipairs({ { 0, -4.6, 10, 1 }, { 0, 4.6, 10, 1 }, { 4.6, 0, 1, 10 } }) do
		K.part(model, "BinWall", Vector3.new(s[3], 5, s[4]), L(GX + s[1], 2.9, BZ + s[2]), PAL.steelDark, Enum.Material.CorrodedMetal)
	end
	K.part(model, "BinGlow", Vector3.new(8.4, 0.4, 8.4), L(GX, 0.7, BZ), PAL.orange, Enum.Material.Neon, { CastShadow = false })
	-- (2026-11-14, owner: the npcs "dont end up making there way inside of it, they get jammed right before") the rollers
	-- stood 0.8 above the belt's surface at its very end and were solid: every body stopped against the first one. Now
	-- they are sunk into the coal bed (tops at 1.9, belt 4.3) and are not solid - bodies tip off the belt onto the
	-- coals, where the rollers still slash them and the drain (Mode "fire") burns them in plain view.
	for _, x in ipairs({ -1.9, 1.9 }) do
		local roller = K.cyl(model, "Saw", 3.4, 8.2, L(GX + x, 0.2, BZ) * CFrame.Angles(math.rad(90), 0, 0), C(120, 124, 132), Enum.Material.DiamondPlate, { CanCollide = false, tag = "Saw", attrs = { Spin = (x < 0) and 9 or -9, Damage = 34 } })
	end
	K.part(model, "DummyDrain", Vector3.new(8.4, 2, 8.4), L(GX, 1.4, BZ), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "DummyDrain", attrs = { Mode = "fire" } })
	local coals = model:FindFirstChild("BinGlow")
	local gl = K.new("PointLight", { Range = 22, Brightness = 2.5, Color = PAL.orange, Shadows = false }, coals)
	-- (LightEmission under 0.5: an additive flame is invisible against the orange-lit walls of the pit)
	K.new("ParticleEmitter", { Name = "PitFlames", Texture = "rbxasset://textures/particles/fire_main.dds", EmissionDirection = Enum.NormalId.Top, Rate = 55,
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(5, 10), SpreadAngle = Vector2.new(14, 14), Acceleration = Vector3.new(0, 4, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), LightEmission = 0.45, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(0.35, 3.2), NumberSequenceKeypoint.new(1, 0.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.3, 0.05), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C(255, 244, 170)), ColorSequenceKeypoint.new(0.3, C(255, 150, 40)), ColorSequenceKeypoint.new(0.75, C(200, 50, 16)), ColorSequenceKeypoint.new(1, C(70, 20, 12)) }) }, coals)
	K.new("ParticleEmitter", { Name = "PitEmbers", Texture = "rbxasset://textures/particles/sparkles_main.dds", EmissionDirection = Enum.NormalId.Top, Rate = 14,
		Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, -2, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }), Color = ColorSequence.new(C(255, 180, 70)), LightEmission = 1, LightInfluence = 0 }, coals)
	-- (2026-11-14, owner: "the workshop shouldnt have npcs auto spawning on it") no stations here any more: the loader's
	-- drop over the belt and the test bay's three standing dummies are gone. Players bring their own (spawn menu, grab).
	-- test bay
	K.part(model, "BayWall", Vector3.new(30, 12, 1), L(-24, 6.4, -38), C(70, 74, 84), Enum.Material.Concrete)
	K.sign(model, "TEST BAY", L(-24, 10.6, -37.2), Vector2.new(14, 2.6), { trim = PAL.hazard })
	K.part(model, "Pegboard", Vector3.new(12, 5, 0.3), L(-24, 5, -37.3), PAL.wood, Enum.Material.WoodPlanks)
	K.cyl(model, "RackBat", 0.7, 4.6, L(-27.5, 5, -37) * CFrame.Angles(0, 0, math.rad(20)), PAL.woodDark, Enum.Material.Wood)
	K.part(model, "RackHammerHandle", Vector3.new(0.5, 4.6, 0.5), L(-24, 5, -37), PAL.woodDark, Enum.Material.Wood)
	K.part(model, "RackHammerHead", Vector3.new(2.6, 1.4, 1.4), L(-24, 7, -37), PAL.steelDark, Enum.Material.Metal)
	K.part(model, "RackBlade", Vector3.new(0.25, 4.8, 0.6), L(-20.5, 5.2, -37) * CFrame.Angles(0, 0, math.rad(-12)), C(206, 210, 216), Enum.Material.Metal)
	for i = -1, 1 do
		K.cyl(model, "BayMark", 5, 0.05, L(-24 + i * 9, 0.43, -30), PAL.hazard, Enum.Material.SmoothPlastic, { CastShadow = false, Transparency = 0.2 })
	end
	K.lamp(model, L(30, 0.4, -34).Position, math.pi)
end
