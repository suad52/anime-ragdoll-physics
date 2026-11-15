--!nocheck
-- BEAR PIT: a round pit sunk into the ground with a bear at the bottom. A plank over the edge and a drop button feed
-- it; a ladder on the wall is the way back out.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local T = workspace.Terrain
	local c = cf.Position
	local R = 21
	T:FillCylinder(CFrame.new(c.X, -12.1, c.Z), 15.8, R + 7, M.Mud) -- lining, kept under the top cell so the rim stays level
	T:FillCylinder(CFrame.new(c.X, -4, c.Z), 12, R, M.Air)
	task.wait(0.5)
	local D = -(K.surface(c) or -10) -- wherever the floor really ended up
	for i = 2, 22 do -- posts and rope round the rim, open at the plank
		local a = i / 24 * math.pi * 2
		local p = L(math.sin(a) * (R + 2.6), 0, -math.cos(a) * (R + 2.6))
		K.cyl(model, "Post", 0.7, 3.6, p * CFrame.new(0, 1.8, 0), PAL.woodDark, M.Wood)
		if i < 22 then
			local a2 = (i + 1) / 24 * math.pi * 2
			local q = L(math.sin(a2) * (R + 2.6), 3, -math.cos(a2) * (R + 2.6)).Position
			local p3 = (p * CFrame.new(0, 3, 0)).Position
			K.part(model, "Rope", Vector3.new(0.25, 0.25, (q - p3).Magnitude), CFrame.lookAt((p3 + q) / 2, q), C(170, 150, 110), M.Fabric, { CanCollide = false, CastShadow = false })
		end
	end
	K.part(model, "Plank", Vector3.new(4, 0.5, 11), L(0, 0.35, -(R - 2.5)), PAL.wood, M.WoodPlanks)
	K.station(model, L(0, 0.7, -(R - 5)), "stand", 9, 1)
	K.button(model, L(9, 0, -(R + 8)), "Dispenser", "Feed the bear", "Bear Pit", { Drop = L(0, 9, 0), Cap = 4, Life = 60 })
	K.danger(model, L(-9, 0, -(R + 7)) * CFrame.Angles(0, math.rad(-12), 0), "BEAR")
	K.truss(model, "WayOut", Vector3.new(2, 12, 2), L(R - 1.2, -D + 5.6, 0), PAL.steel)
	-- the den
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "DenRock", Vector3.new(4, 7, 5), L(sx * 4.6, -D + 3, R - 3) * CFrame.Angles(0, sx * 0.3, sx * 0.14), C(104, 100, 94), M.Slate)
	end
	K.part(model, "DenRock", Vector3.new(13, 3.4, 5.6), L(0, -D + 7.4, R - 3) * CFrame.Angles(0, 0.1, 0.05), C(96, 92, 88), M.Slate)
	K.part(model, "DenDark", Vector3.new(6, 6, 1), L(0, -D + 3, R - 1.4), C(10, 10, 12), M.SmoothPlastic, { CastShadow = false })
	local rng = Random.new(5)
	for _ = 1, 5 do
		local a, r = rng:NextNumber(0, 6.28), rng:NextNumber(4, R - 5)
		K.cyl(model, "Bone", 0.5, rng:NextNumber(1.6, 3), L(math.sin(a) * r, -D + 0.3, math.cos(a) * r - 2) * CFrame.Angles(math.rad(90), rng:NextNumber(0, 6), 0), C(236, 230, 212), M.SmoothPlastic, { CanCollide = false })
	end
	local bear = require(script.Parent.Beasts).bear(K, model, L(4, -D, 2) * CFrame.Angles(0, 2, 0))
	bear:SetAttribute("Pen", L(0, -D, 0))
	bear:SetAttribute("Roam", Vector3.new(R - 6.5, 9, 0))
end
