--!nocheck
-- BOUNCE PARK: trampolines (tag Trampoline, attribute Power = launch speed), a mega one, dummies standing beside them, and a
-- foam pit of loose blocks.
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
	local function tramp(x, z, dia, power, color)
		local m = K.model(model, "Trampoline")
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			K.cyl(m, "Leg", 0.6, 3, L(x + math.sin(a) * dia * 0.48, 1.9, z + math.cos(a) * dia * 0.48), PAL.steelDark, Enum.Material.Metal)
		end
		K.cyl(m, "Frame", dia + 2.4, 0.9, L(x, 3.5, z), color, Enum.Material.Fabric)
		K.cyl(m, "Springs", dia + 0.6, 0.94, L(x, 3.5, z), C(200, 204, 210), Enum.Material.Metal, { CastShadow = false })
		K.cyl(m, "Mat", dia, 1, L(x, 3.52, z), C(22, 22, 26), Enum.Material.Fabric, { tag = "Trampoline", attrs = { Power = power } })
		K.cyl(m, "Mark", dia * 0.3, 1.02, L(x, 3.52, z), color, Enum.Material.Fabric, { CastShadow = false })
	end
	tramp(-25, -20, 18, 95, PAL.blue)
	tramp(25, -20, 18, 95, PAL.red)
	tramp(0, 14, 30, 150, PAL.hazard)
	tramp(-31, 24, 13, 75, C(60, 170, 110))
	K.sign(model, "MEGA BOUNCE", L(0, 12, 33), Vector2.new(16, 3), { trim = PAL.hazard })
	K.part(model, "SignPostA", Vector3.new(0.8, 9.87, 0.8), L(-7, 5.135, 33), K.SIGN_BLACK, Enum.Material.Metal) -- (2026-11-13) stops under the sign's trim at 10.05
	K.part(model, "SignPostB", Vector3.new(0.8, 9.87, 0.8), L(7, 5.135, 33), K.SIGN_BLACK, Enum.Material.Metal)
	-- foam pit
	local px, pz, w = 29, 22, 20
	for _, s in ipairs({ { 0, -w / 2, w + 1, 1 }, { 0, w / 2, w + 1, 1 }, { -w / 2, 0, 1, w + 1 }, { w / 2, 0, 1, w + 1 } }) do
		K.part(model, "PitWall", Vector3.new(s[3], 4, s[4]), L(px + s[1], 2.4, pz + s[2]), PAL.blue, Enum.Material.Fabric)
	end
	-- (2026-11-14, owner: "add a ladder to the trampoline pit too") a truss on the inside of the wall facing the park
	-- (open ground past it, clear of the trampolines), floor to 2 studs over the wall: climb it and step over the top
	K.truss(model, "Ladder", Vector3.new(2, 6, 2), L(px, 3.4, pz - w / 2 + 1.5), PAL.steel)
	local foam = { C(240, 120, 60), C(250, 200, 70), C(90, 170, 230), C(120, 200, 120), C(230, 110, 160) }
	local rng = Random.new(7)
	local blocks = K.model(model, "Foam")
	for i = 1, 34 do
		local s = rng:NextNumber(2.2, 3.2)
		K.part(blocks, "Foam", Vector3.new(s, s, s), L(px + rng:NextNumber(-7.5, 7.5), 1.6 + (i % 3) * 3, pz + rng:NextNumber(-7.5, 7.5)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			foam[i % #foam + 1], Enum.Material.Fabric, { Anchored = false, CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.6, 0.5) })
	end
	-- (2026-11-14, owner: "the npcs at the trampoline area spawn in ragdolled") the park's dummies used to rain down limp
	-- from 26-46 studs onto the mats ("drop") and one stood ON the red trampoline, which bounced it over at once. Now
	-- each trampoline and the foam pit has one standing on the ground beside it, facing it: throw them in yourself.
	local function beside(x, z, tx, tz, every)
		local pos = L(x, 1, z).Position
		local at = L(tx, 1, tz).Position
		station(K, model, CFrame.lookAt(pos, Vector3.new(at.X, pos.Y, at.Z)), "stand", every, 1)
	end
	beside(-25, -6, -25, -20, 9)
	beside(25, -6, 25, -20, 9)
	beside(0, -8, 0, 14, 7)
	beside(px, pz - 18, px, pz, 10)
end
