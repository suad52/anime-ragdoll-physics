--!nocheck
-- LEAP TOWER: a 64-stud stone tower with a ladder inside and a plank off the top. A dummy waits on the plank.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local W, HT, TH = 16, 64, 1.6
	local stone, stone2 = C(198, 188, 162), C(176, 166, 142)
	local h = W / 2 - TH / 2
	K.part(model, "Wall", Vector3.new(W, HT, TH), L(0, HT / 2, h), stone, M.Sandstone)
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Wall", Vector3.new(TH, HT, W - TH * 2), L(sx * h, HT / 2, 0), stone, M.Sandstone)
		K.part(model, "Wall", Vector3.new(5, HT, TH), L(sx * 5.5, HT / 2, -h), stone, M.Sandstone)
	end
	K.part(model, "Wall", Vector3.new(6, HT - 9, TH), L(0, 9 + (HT - 9) / 2, -h), stone, M.Sandstone)
	K.part(model, "Floor", Vector3.new(W - TH * 2, 0.4, W - TH * 2), L(0, 0.2, 0), stone2, M.Sandstone)
	-- (2026-11-14, owner: "i cant get to the top of the leap tower, the hatch at the top is blocked off") the old roof left
	-- 0.4 studs between the ladder and the slab, where the climber's body is. Now the ladder stands 2 studs off the back
	-- wall and the hatch (x -2..2, z -0.6..2.4) opens IN FRONT of it: you climb up through the hole and step forward
	-- off the ladder's top onto the landing behind it, not back over the hole.
	K.truss(model, "Ladder", Vector3.new(2, HT + 2, 2), L(0, (HT + 2) / 2, h - 3.8), PAL.steel)
	K.part(model, "Top", Vector3.new(W + 2, 1, 8.4), L(0, HT + 0.5, -4.8), stone2, M.Sandstone) -- in front of the hatch
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Top", Vector3.new(7, 1, 9.6), L(sx * 5.5, HT + 0.5, 4.2), stone2, M.Sandstone) -- either side
		K.part(model, "Top", Vector3.new(1, 1, 2), L(sx * 1.5, HT + 0.5, 3.4), stone2, M.Sandstone) -- beside the ladder
	end
	K.part(model, "Top", Vector3.new(4, 1, 4.6), L(0, HT + 0.5, 6.7), stone2, M.Sandstone) -- the landing behind it
	-- a low parapet round the hatch's front and sides, so walking from the landing to the plank is not a fall down the
	-- shaft (the climber comes up inside it and steps off forward, clear of all three)
	K.part(model, "HatchRail", Vector3.new(4.6, 2.2, 0.3), L(0, HT + 2.1, -0.75), stone, M.Sandstone)
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "HatchRail", Vector3.new(0.3, 2.2, 3.15), L(sx * 2.15, HT + 2.1, 0.825), stone, M.Sandstone)
	end
	for i = 0, 3 do
		for _, s in ipairs({ { -8.3, -7 + i * 4.6, 1.4, 2.6 }, { 8.3, -7 + i * 4.6, 1.4, 2.6 }, { -7 + i * 4.6, 8.3, 2.6, 1.4 } }) do
			K.part(model, "Crenel", Vector3.new(s[3], 2.6, s[4]), L(s[1], HT + 2.3, s[2]), stone, M.Sandstone)
		end
	end
	for _, x in ipairs({ -6.6, 6.6 }) do
		K.part(model, "Crenel", Vector3.new(2.6, 2.6, 1.4), L(x, HT + 2.3, -8.3), stone, M.Sandstone)
	end
	K.part(model, "Plank", Vector3.new(4, 0.5, 13), L(0, HT + 1.25, -W / 2 - 5), PAL.wood, M.WoodPlanks)
	K.station(model, L(0, HT + 1.7, -W / 2 - 8), "stand", 7, 1)
	local lamp = K.part(model, "Lantern", Vector3.new(1, 1, 1), L(0, 12, 0), C(255, 220, 160), M.Neon, { CanCollide = false, CastShadow = false })
	K.new("PointLight", { Range = 30, Brightness = 1.4, Color = C(255, 214, 160), Shadows = false }, lamp)
	local tc = L(0, 0, -W / 2 - 10)
	for i, d in ipairs({ { 20, PAL.red }, { 14, PAL.white }, { 8, PAL.red }, { 3, PAL.white } }) do
		K.cyl(model, "Target", d[1], 0.1 + i * 0.03, tc * CFrame.new(0, 0.05 + i * 0.015, 0), d[2], M.SmoothPlastic, { CastShadow = false })
	end
end
