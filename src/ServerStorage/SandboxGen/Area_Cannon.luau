--!nocheck
-- HUMAN CANNON: CannonLoad packs the nearest dummy into the barrel (the invisible Breech part), CannonFire (attribute
-- Power) shoots it out of the Muzzle at a wall of loose bricks (tag BrickWall - the server restacks it).
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	K.groundDisc(cf.Position, 19, M.Concrete)
	K.cyl(model, "Pad", 32, 0.6, L(0, 0.3, 0), PAL.concrete, M.Concrete)
	for i = 3, 21 do
		local a = i / 24 * math.pi * 2
		K.part(model, "Kerb", Vector3.new(4.4, 1.2, 1.4), L(math.sin(a) * 16.4, 0.9, -math.cos(a) * 16.4) * CFrame.Angles(0, -a, 0), PAL.curb, M.Concrete)
	end
	local steel = C(48, 52, 60)
	K.cyl(model, "Turret", 9, 2.6, L(0, 1.9, 0), steel, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Yoke", Vector3.new(1.4, 6, 5), L(sx * 3.8, 5.6, 0), steel, M.Metal)
	end
	local bcf = L(0, 6.8, 0) * CFrame.Angles(math.rad(33), 0, 0)
	local along = CFrame.Angles(math.rad(90), 0, 0)
	K.cyl(model, "Barrel", 5.6, 20, bcf * CFrame.new(0, 0, -7) * along, C(226, 226, 222), M.Metal, { CanCollide = false })
	K.cyl(model, "BreechCap", 6.2, 2.4, bcf * CFrame.new(0, 0, 3.6) * along, steel, M.Metal)
	K.cyl(model, "MuzzleRing", 6.4, 2, bcf * CFrame.new(0, 0, -16.4) * along, steel, M.Metal, { CanCollide = false })
	K.cyl(model, "Bore", 4.2, 0.2, bcf * CFrame.new(0, 0, -17.45) * along, C(8, 8, 10), M.SmoothPlastic, { CastShadow = false, CanCollide = false })
	K.zone(model, "Breech", Vector3.new(1, 1, 1), bcf * CFrame.new(0, 0, -5) * CFrame.Angles(math.rad(-90), 0, 0))
	local muzzle = K.zone(model, "Muzzle", Vector3.new(1, 1, 1), bcf * CFrame.new(0, 0, -18.5))
	K.new("ParticleEmitter", { Name = "Smoke", Enabled = false, Rate = 0, Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(14, 30), SpreadAngle = Vector2.new(24, 24),
		Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(C(230, 230, 230)), Size = NumberSequence.new(2.5, 7), Transparency = NumberSequence.new(0.3, 1),
		EmissionDirection = Enum.NormalId.Front }, muzzle)
	K.button(model, L(-11, 0, 9), "CannonLoad", "Load the nearest dummy", "Human Cannon")
	K.button(model, L(11, 0, 9), "CannonFire", "FIRE", "Human Cannon", { Power = 116 })
	K.station(model, L(-9, 0.7, -8), "stand", 8, 1)
	K.station(model, L(8, 0.7, -10), "stand", 8, 1)
	K.danger(model, L(17, 0, -13) * CFrame.Angles(0, math.rad(40), 0))
	local WZ = -96
	K.ground(L(0, 0, WZ), Vector3.new(42, 0, 14), M.Concrete)
	K.part(model, "Footing", Vector3.new(38, 0.6, 9), L(0, 0.3, WZ), PAL.concrete, M.Concrete)
	local wallM = K.model(model, "BrickWall")
	K.tag(wallM, "BrickWall")
	local rng = Random.new(8)
	for row = 0, 6 do
		for i = 0, 7 do
			local x = -15 + i * 4 + ((row % 2 == 1) and 2 or 0)
			local t = rng:NextNumber(-10, 10)
			K.part(wallM, "Brick", Vector3.new(4, 2, 2.4), L(x, 1.6 + row * 2, WZ), C(170 + t, 84 + t * 0.5, 66 + t * 0.4), M.Brick, { Anchored = false })
		end
	end
end
