--!nocheck
-- SHARK BAIT: a lake (terrain water) with a shark in it and a tower crane dangling a body over it by one foot.
-- CraneLower lowers / raises the hook (tag CraneHook: Top, Bottom, CableTop), CraneDrop cuts the body loose.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local T = workspace.Terrain
	local c = cf.Position
	local R, DEEP = 34, 22
	K.groundDisc(c, R + 9, M.Sand)
	T:FillCylinder(CFrame.new(c.X, -15.1, c.Z), 21.8, R + 8, M.Sand)
	T:FillCylinder(CFrame.new(c.X, (2 - DEEP) / 2, c.Z), DEEP + 2, R, M.Air)
	T:FillCylinder(CFrame.new(c.X, (-4 - DEEP) / 2, c.Z), DEEP - 4, R, M.Water)
	do -- water cells in the top layer, a little over half full, bring the surface up towards the bank
		local region = Region3.new(Vector3.new(c.X - R - 4, -4, c.Z - R - 4), Vector3.new(c.X + R + 4, 0, c.Z + R + 4)):ExpandToGrid(4)
		local mats, occ = T:ReadVoxels(region, 4)
		local min = region.CFrame.Position - region.Size / 2
		for x = 1, mats.Size.X do
			for z = 1, mats.Size.Z do
				local cx, cz = min.X + (x - 0.5) * 4, min.Z + (z - 0.5) * 4
				if math.sqrt((cx - c.X) ^ 2 + (cz - c.Z) ^ 2) < R - 2.5 and mats[x][1][z] == M.Air then
					mats[x][1][z] = M.Water
					occ[x][1][z] = 0.55
				end
			end
		end
		T:WriteVoxels(region, 4, mats, occ)
	end
	task.wait(0.5)
	local SURF = K.surface(c) or -4
	-- dock
	K.part(model, "Dock", Vector3.new(8, 0.6, 28), L(0, 0.9, -(R - 8)), PAL.wood, M.WoodPlanks)
	for _, z in ipairs({ -38, -28, -18 }) do
		for _, x in ipairs({ -3.6, 3.6 }) do
			K.cyl(model, "Pile", 0.9, 14, L(x, -5.6, z), PAL.woodDark, M.Wood)
		end
	end
	K.truss(model, "Ladder", Vector3.new(2, 12, 2), L(5, -4.6, -14), PAL.steel)
	K.station(model, L(0, 1.3, -15), "stand", 9, 1)
	-- tower crane
	local mx, mz, JY = R + 10, 6, 48
	K.part(model, "CraneBase", Vector3.new(10, 2, 10), L(mx, 1, mz), PAL.concrete, M.Concrete)
	for _, o in ipairs({ { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } }) do
		K.truss(model, "Mast", Vector3.new(2, 42, 2), L(mx + o[1], 23, mz + o[2]), PAL.hazard)
	end
	K.part(model, "Cab", Vector3.new(7, 5, 7), L(mx, 46.5, mz), PAL.hazard, M.Metal)
	K.part(model, "CabGlass", Vector3.new(4, 2.4, 7.2), L(mx - 1.7, 47.2, mz), C(30, 40, 52), M.Glass)
	K.truss(model, "Jib", Vector3.new(2, 2, 50), L(mx - 20, JY + 2, mz) * CFrame.Angles(0, math.rad(90), 0), PAL.hazard)
	K.part(model, "Counterweight", Vector3.new(6, 4, 6), L(mx + 7, JY + 1.4, mz), C(70, 72, 78), M.Concrete)
	K.part(model, "MastTop", Vector3.new(1.2, 10, 1.2), L(mx, JY + 8, mz), PAL.hazard, M.Metal)
	local hx = 2
	local tip, top = L(hx, JY + 3, mz).Position, L(mx, JY + 13, mz).Position
	K.part(model, "Stay", Vector3.new(0.3, 0.3, (tip - top).Magnitude), CFrame.lookAt((tip + top) / 2, tip), PAL.steelDark, M.Metal, { CanCollide = false })
	K.part(model, "Trolley", Vector3.new(3, 1.4, 3), L(hx, JY + 0.3, mz), PAL.steelDark, M.Metal)
	local TOPY, BOTY, CT = 15, SURF - 3, JY - 0.4
	local hook = K.part(model, "CraneHook", Vector3.new(1.6, 1.6, 1.6), L(hx, TOPY, mz), C(60, 62, 70), M.Metal, { tag = "CraneHook", attrs = { Top = TOPY, Bottom = BOTY, CableTop = CT, Speed = 8 } })
	K.new("Attachment", { Name = "HookPoint", Position = Vector3.new(0, -0.8, 0) }, hook)
	K.cyl(model, "CraneCable", 0.3, CT - (TOPY + 0.8), L(hx, (CT + TOPY + 0.8) / 2, mz), C(30, 30, 34), M.Metal, { CanCollide = false, CastShadow = false })
	K.button(model, L(-9, 0, -(R + 12)), "CraneLower", "Lower the hook", "Shark Bait")
	K.button(model, L(9, 0, -(R + 12)), "CraneDrop", "Cut him loose", "Shark Bait")
	K.danger(model, L(-17, 0, -(R + 9)) * CFrame.Angles(0, math.rad(-20), 0), "SHARK")
	local rng = Random.new(3)
	for _ = 1, 6 do
		local a, s = rng:NextNumber(0, 6.28), rng:NextNumber(3, 6)
		K.part(model, "Rock", Vector3.new(s, s * 0.7, s * 0.9), L(math.sin(a) * (R + 4), s * 0.15, math.cos(a) * (R + 4)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0), C(128, 124, 116), M.Slate)
	end
	local shark = require(script.Parent.Beasts).shark(K, model, L(-16, SURF - 5, 10) * CFrame.Angles(0, 1, 0))
	shark:SetAttribute("Pen", CFrame.new(c.X, SURF, c.Z))
	shark:SetAttribute("Roam", Vector3.new(R - 8, DEEP + SURF - 3, 0))
end
