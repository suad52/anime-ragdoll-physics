--!nocheck
-- REX PADDOCK: a fenced paddock with a T-rex in it (SandboxGen.Beasts; Sandbox.Beasts hunts whatever is inside Pen).
-- A ramp climbs to a deck that hangs over the fence so bodies can be thrown in; a button drops one in from above.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local HX, HZ, FH = 40, 30, 14
	local cs = { L(-HX, 0, -HZ).Position, L(HX, 0, -HZ).Position, L(HX, 0, HZ).Position, L(-HX, 0, HZ).Position }
	for i = 1, 4 do
		K.fence(model, cs[i], cs[i % 4 + 1], FH, C(70, 78, 70))
	end
	-- the deck (hangs 4 studs over the pen) and its ramp
	local DY = 15
	K.part(model, "Deck", Vector3.new(16, 0.6, 14), L(-22, DY - 0.3, -HZ - 3), PAL.wood, M.WoodPlanks)
	for _, c in ipairs({ { -29, -9 }, { -15, -9 }, { -29, -1 }, { -15, -1 } }) do
		K.part(model, "DeckLeg", Vector3.new(1.2, DY - 0.6, 1.2), L(c[1], (DY - 0.6) / 2, -HZ + c[2]), PAL.woodDark, M.Wood)
	end
	K.part(model, "DeckRail", Vector3.new(16, 0.4, 0.4), L(-22, DY + 3, -HZ - 9.8), PAL.woodDark, M.Wood)
	K.part(model, "DeckRail", Vector3.new(0.4, 0.4, 10), L(-29.8, DY + 3, -HZ - 5), PAL.woodDark, M.Wood)
	for _, c in ipairs({ { -29.8, -9.8 }, { -22, -9.8 }, { -14.2, -9.8 }, { -29.8, -0.2 } }) do
		K.part(model, "RailPost", Vector3.new(0.5, 3.2, 0.5), L(c[1], DY + 1.6, -HZ + c[2]), PAL.woodDark, M.Wood)
	end
	local run = 30
	K.part(model, "Ramp", Vector3.new(math.sqrt(run ^ 2 + DY ^ 2) + 0.6, 0.6, 6), L(-14 + run / 2, DY / 2 - 0.3, -HZ - 7) * CFrame.Angles(0, 0, -math.atan2(DY, run)), PAL.wood, M.WoodPlanks)
	K.station(model, L(-22, DY + 0.3, -HZ + 0.2), "stand", 9, 1)
	K.button(model, L(2, 0, -HZ - 7), "Dispenser", "Throw the rex a dummy", "Rex Paddock", { Drop = L(6, 17, -8), Cap = 4, Life = 60 })
	K.danger(model, L(14, 0, -HZ - 4), "KEEP OUT")
	K.danger(model, L(HX + 4, 0, 6) * CFrame.Angles(0, math.rad(90), 0), "T-REX")
	K.truss(model, "WayOut", Vector3.new(2, 16, 2), L(HX - 2, 8, -HZ + 2), PAL.steel)
	-- dressing
	local rng = Random.new(41)
	for _ = 1, 7 do
		local s = rng:NextNumber(3, 8)
		K.part(model, "Rock", Vector3.new(s, s * 0.7, s * 0.9), L(rng:NextNumber(-HX + 5, HX - 5), s * 0.2, rng:NextNumber(-HZ + 5, HZ - 5)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), rng:NextNumber(0, 1)), C(112, 110, 104), M.Slate)
	end
	for _ = 1, 9 do
		local p = L(rng:NextNumber(-HX + 4, HX - 4), 0.35, rng:NextNumber(-HZ + 4, HZ - 4))
		K.cyl(model, "Bone", 0.6, rng:NextNumber(2, 4), p * CFrame.Angles(math.rad(90), rng:NextNumber(0, 6), 0), C(236, 230, 212), M.SmoothPlastic, { CanCollide = false })
	end
	local dt = L(-HX + 9, 0, HZ - 8)
	K.cyl(model, "DeadTree", 2.2, 16, dt * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(6)), C(84, 70, 56), M.Wood)
	K.cyl(model, "DeadBranch", 1, 8, dt * CFrame.new(2.6, 13, 0) * CFrame.Angles(0, 0, math.rad(-52)), C(84, 70, 56), M.Wood)
	K.cyl(model, "DeadBranch", 0.9, 7, dt * CFrame.new(-2, 15, 1) * CFrame.Angles(math.rad(20), 0, math.rad(44)), C(84, 70, 56), M.Wood)
	local rex = require(script.Parent.Beasts).rex(K, model, L(10, 0, 6) * CFrame.Angles(0, math.rad(150), 0))
	rex:SetAttribute("Pen", L(0, 0, 0))
	rex:SetAttribute("Roam", Vector3.new(HX - 10, 18, HZ - 10))
end
