--!nocheck
-- GAS YARD: a fenced fuel depot. GasCanSpawn / BarrelSpawn markers are where the runtime keeps explosive cans and drums
-- stocked; everything else is dressing.
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
	local function P(x, z)
		return L(x, 0.4, z).Position
	end
	local e = 41
	K.fence(model, P(-e, -e), P(-10, -e), 7)
	K.fence(model, P(10, -e), P(e, -e), 7)
	K.fence(model, P(-e, -e), P(-e, e), 7)
	K.fence(model, P(e, -e), P(e, e), 7)
	K.fence(model, P(-e, e), P(e, e), 7)
	-- the tank
	local tank = K.model(model, "Tank")
	local tcf = L(12, 8, 26) * CFrame.Angles(0, 0, math.rad(90))
	K.cyl(tank, "Body", 11, 28, tcf, C(226, 224, 216), Enum.Material.Metal)
	K.cyl(tank, "Stripe", 11.2, 2.4, tcf, PAL.red, Enum.Material.Metal, { CastShadow = false })
	for _, o in ipairs({ -14.4, 14.4 }) do
		K.cyl(tank, "Cap", 9.4, 1.2, tcf * CFrame.new(0, o, 0), C(190, 188, 180), Enum.Material.Metal)
	end
	for _, x in ipairs({ 3, 21 }) do
		K.part(tank, "Cradle", Vector3.new(3, 3.4, 9), L(x, 2.1, 26), PAL.concreteDark, Enum.Material.Concrete)
	end
	K.sign(tank, "FLAMMABLE", L(12, 8, 20.2), Vector2.new(12, 2.6), { back = PAL.red, trim = PAL.white })
	K.cyl(tank, "Pipe", 0.9, 12, L(-2.6, 4.4, 26) * CFrame.Angles(0, 0, 0), PAL.steelDark, Enum.Material.Metal)
	K.cyl(tank, "Valve", 2.2, 0.5, L(-2.6, 6, 25.2) * CFrame.Angles(math.rad(90), 0, 0), PAL.red, Enum.Material.Metal)
	-- pallets, stains, signs
	local function pallets(x, z, n)
		for i = 1, n do
			K.part(model, "Pallet", Vector3.new(6, 0.5, 6), L(x, 0.4 + (i - 0.5) * 0.6, z) * CFrame.Angles(0, (i % 2) * 0.12, 0), (i % 2 == 0) and PAL.wood or PAL.woodDark, Enum.Material.WoodPlanks)
		end
		return 0.4 + n * 0.6
	end
	local rng = Random.new(5)
	for i = 1, 9 do
		K.cyl(model, "Stain", rng:NextNumber(4, 9), 0.05, L(rng:NextNumber(-34, 34), 0.43, rng:NextNumber(-34, 34)), C(34, 30, 28), Enum.Material.SmoothPlastic, { Transparency = 0.35, CastShadow = false })
	end
	K.sign(model, "NO SMOKING", L(-24, 9.15, -e + 0.2), Vector2.new(13, 2.6), { back = PAL.hazard, color = C(20, 20, 24), stroke = PAL.hazard, strokeW = 0, trim = C(20, 20, 24) })
	K.sign(model, "DANGER  -  FUEL", L(24, 9.15, -e + 0.2), Vector2.new(13, 2.6), { back = PAL.red, trim = PAL.white })
	local function can(x, y, z)
		K.part(model, "GasCanSpawn", Vector3.new(1, 0.2, 1), L(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "GasCanSpawn" })
	end
	local h1 = pallets(-24, -10, 2)
	for ix = -1, 1 do
		for iz = 0, 1 do
			can(-24 + ix * 2, h1, -11 + iz * 2.2)
		end
	end
	local h2 = pallets(22, -16, 3)
	for ix = -1, 1 do
		can(22 + ix * 2, h2, -16)
	end
	for i = 0, 4 do
		can(-16 + i * 2.4, 0.4, 20)
	end
	can(-6, 0.4, -4); can(-3.6, 0.4, -4.6); can(4, 0.4, 2); can(30, 0.4, 6); can(31.8, 0.4, 7.6)
	for _, b in ipairs({ { -32, 28 }, { -28.6, 30 }, { 32, 30 }, { 0, 12 }, { -30, -28 }, { 33, -30 } }) do
		K.part(model, "BarrelSpawn", Vector3.new(1, 0.2, 1), L(b[1], 0.4, b[2]), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "BarrelSpawn" })
	end
	K.lamp(model, P(-36, -36), 0)
	K.lamp(model, P(36, 36), math.pi)
	station(K, model, L(-18, 0.6, -6), "stand", 7, 1)
	station(K, model, L(6, 0.6, -2), "stand", 7, 1)
	station(K, model, L(-10, 0.6, 16), "stand", 9, 1)
	station(K, model, L(26, 0.6, 2), "stand", 9, 1)
end
