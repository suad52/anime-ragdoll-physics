--!nocheck
-- SPIKE PIT: a 44-stud pit of steel spikes (the SpikeZone part is what hurts), a bridge with a trapdoor (tag Trapdoor,
-- opened from the button), a diving plank and a fence.
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
	local pad = model:FindFirstChild("Pad")
	if pad then
		pad:Destroy()
	end
	local PZ, D = 6, 17 -- pit centre z, depth
	local padC, padM = A.padColor, A.padMat
	for _, s in ipairs({ { 0, PZ - 25.2, 56, 4 }, { 0, PZ + 25.2, 56, 4 }, { -25.2, PZ, 4, 46.4 }, { 25.2, PZ, 4, 46.4 } }) do -- (2026-11-13) just a rim: the square pad went with the ring map
		K.part(model, "Pad", Vector3.new(s[3], 0.4, s[4]), L(s[1], 0.2, s[2]), padC, padM)
	end
	workspace.Terrain:FillBlock(L(0, -D / 2 - 1, PZ), Vector3.new(52, D + 4, 52), Enum.Material.Air) -- (2026-11-13) 52: terrain walls ride 2 studs inside a carve
	local stone = C(84, 80, 78)
	for _, s in ipairs({ { 0, -22.6, 46.4, 1.2 }, { 0, 22.6, 46.4, 1.2 }, { -22.6, 0, 1.2, 46.4 }, { 22.6, 0, 1.2, 46.4 } }) do
		K.part(model, "PitWall", Vector3.new(s[3], D + 0.4, s[4]), L(s[1], -D / 2 + 0.2, PZ + s[2]), stone, Enum.Material.Slate)
	end
	K.part(model, "PitFloor", Vector3.new(46, 1, 46), L(0, -D - 0.5, PZ), C(52, 48, 48), Enum.Material.Slate)
	-- (2026-11-14, owner: "add a ladder for the spike bit") the way out. The SpikeZone only hurts dummies, so a player who
	-- dropped in stood on the spikes 17 studs down with no way up. A truss on the open entry-side wall (the other three have
	-- fences along the rim, and the bridge meets the side walls), between spike columns x = -6 and 0, flush to the wall's
	-- inner face, from the floor to 3 studs over the rim so you climb past the lip.
	K.truss(model, "Ladder", Vector3.new(2, D + 3, 2), L(-3, -D + (D + 3) / 2, PZ - 21), PAL.steel)
	local rng = Random.new(31)
	local spikes = K.model(model, "Spikes")
	for ix = -3, 3 do
		for iz = -3, 3 do
			local h = rng:NextNumber(5.5, 9)
			local b = rng:NextNumber(1.3, 1.9)
			local c = L(ix * 6 + rng:NextNumber(-1, 1), -D + h / 2, PZ + iz * 6 + rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2 + rng:NextNumber(-0.3, 0.3), 0)
			local col = C(150, 154, 162):Lerp(C(110, 40, 40), rng:NextNumber(0, 0.35))
			K.wedge(spikes, "Spike", Vector3.new(1.1, h, b), c * CFrame.new(0, 0, -b / 2), col, Enum.Material.Metal)
			K.wedge(spikes, "Spike", Vector3.new(1.1, h, b), c * CFrame.new(0, 0, b / 2) * CFrame.Angles(0, math.pi, 0), col, Enum.Material.Metal)
		end
	end
	K.part(model, "SpikeZone", Vector3.new(43, 10, 43), L(0, -D + 5, PZ), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "SpikeZone" })
	-- bridge with a trapdoor
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Bridge", Vector3.new(16.6, 0.6, 6), L(sx * 14.3, 0.3, PZ), PAL.steel, Enum.Material.DiamondPlate)
		K.part(model, "Trapdoor", Vector3.new(6, 0.5, 6), L(sx * 3, 0.35, PZ), PAL.hazard, Enum.Material.DiamondPlate, { tag = "Trapdoor", attrs = { Side = sx } })
		for _, z in ipairs({ -3, 3 }) do
			K.part(model, "BridgeRail", Vector3.new(16.6, 0.3, 0.3), L(sx * 14.3, 3.6, PZ + z), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			for _, x in ipairs({ 6.2, 14, 22 }) do
				K.cyl(model, "BridgePost", 0.3, 3.4, L(sx * x, 1.9, PZ + z), PAL.hazard, Enum.Material.Metal, { CastShadow = false })
			end
		end
	end
	K.part(model, "Plank", Vector3.new(4, 0.5, 14), L(-12, 0.45, -20), PAL.wood, Enum.Material.WoodPlanks)
	K.part(model, "Plank", Vector3.new(4, 0.5, 14), L(12, 0.45, -20), PAL.wood, Enum.Material.WoodPlanks)
	local edge = 23.4
	K.fence(model, L(-edge, 0.4, PZ + edge).Position, L(edge, 0.4, PZ + edge).Position, 5)
	K.fence(model, L(-edge, 0.4, PZ - edge + 9).Position, L(-edge, 0.4, PZ + edge).Position, 5)
	K.fence(model, L(edge, 0.4, PZ - edge + 9).Position, L(edge, 0.4, PZ + edge).Position, 5)
	-- the button
	K.part(model, "ButtonPost", Vector3.new(1.4, 3.6, 1.4), L(0, 2.2, -24), PAL.steelDark, Enum.Material.Metal)
	local b = K.cyl(model, "TrapdoorButton", 2, 0.8, L(0, 4.3, -24), PAL.red, Enum.Material.Neon, { tag = "TrapdoorButton" })
	K.new("ProximityPrompt", { ActionText = "Open the trapdoor", ObjectText = "Spike pit", HoldDuration = 0, MaxActivationDistance = 12, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, b)
	K.sign(model, "MIND THE GAP", L(0, 7, -26), Vector2.new(11, 2.2), { trim = PAL.red, pps = 26 })
	station(K, model, L(-3, 0.9, PZ) * CFrame.Angles(0, math.rad(90), 0), "stand", 6, 1)
	station(K, model, L(3, 0.9, PZ) * CFrame.Angles(0, math.rad(-90), 0), "stand", 6, 1)
	station(K, model, L(-12, 0.9, -15), "stand", 8, 1)
	station(K, model, L(12, 0.9, -15), "stand", 8, 1)
end
