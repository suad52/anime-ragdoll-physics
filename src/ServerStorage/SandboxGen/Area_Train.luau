--!nocheck
-- THE EXPRESS: a short straight of track between two tunnelled berms. The train is one unanchored assembly on a
-- PrismaticConstraint motor (tag Train: Speed, Every, Length); Sandbox.Machines runs it back and forth and hits
-- whatever is in front of it. It hides inside a berm between runs.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local T = workspace.Terrain
	local HALF = 112
	K.ground(L(0, 0, 0), Vector3.new(15, 0, HALF * 2 + 210), M.Slate)
	for _, sz in ipairs({ -1, 1 }) do
		for k = 0, 3 do
			T:FillBall(L(0, -1, sz * (HALF + 20 + k * 24)).Position, 28, (k % 2 == 0) and M.Grass or M.Rock)
		end
		T:FillBall(L(0, 0, sz * (HALF + 12)).Position, 21, M.Grass) -- a steep face for the portal to sit in
		T:FillBlock(L(0, 8.5, sz * (HALF + 44)), Vector3.new(22, 17, 120), M.Air) -- 22 wide: terrain walls ride 2 studs inside a carve, and a tight bore jammed the train
		for _, x in ipairs({ -12.5, 12.5 }) do
			K.part(model, "Portal", Vector3.new(3, 19, 4), L(x, 9.5, sz * (HALF - 6)), C(150, 146, 138), M.Slate)
		end
		K.part(model, "PortalLintel", Vector3.new(29, 4, 4), L(0, 20.5, sz * (HALF - 6)), C(150, 146, 138), M.Slate)
	end
	local TL = HALF + 100
	for _, x in ipairs({ -3, 3 }) do
		K.part(model, "Rail", Vector3.new(0.6, 0.6, TL * 2), L(x, 0.75, 0), C(120, 124, 132), M.Metal)
	end
	for z = -HALF, HALF, 5 do
		K.part(model, "Sleeper", Vector3.new(11, 0.45, 1.7), L(0, 0.22, z), PAL.woodDark, M.Wood)
	end
	K.part(model, "Crossing", Vector3.new(14, 0.5, 12), L(0, 0.55, 0), PAL.woodDark, M.WoodPlanks)
	-- the train: parked in the +Z berm
	local train = K.model(model, "Train")
	local red, cream, glass, under = C(186, 44, 40), C(232, 224, 204), C(30, 40, 52), C(34, 36, 42)
	local startZ = HALF + 46
	local base = L(0, 0, startZ)
	local root
	local function TP(name, size, off, color, mat, collide, wedge)
		local fn = wedge and K.wedge or K.part
		local p = fn(train, name, size, base * off, color, mat or M.Metal, { Anchored = false, Massless = root ~= nil, CanCollide = collide == true })
		if root then
			K.weld(root, p)
		end
		return p
	end
	root = TP("Root", Vector3.new(8.6, 8.4, 58), CFrame.new(0, 6.6, 0), red, M.Metal, true)
	root.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0)
	TP("Band", Vector3.new(8.8, 2.6, 58.2), CFrame.new(0, 7.6, 0), cream)
	TP("Windows", Vector3.new(8.9, 1.8, 24), CFrame.new(0, 7.9, -15.5), glass, M.Glass)
	TP("Windows", Vector3.new(8.9, 1.8, 24), CFrame.new(0, 7.9, 15.5), glass, M.Glass)
	TP("Gangway", Vector3.new(8.9, 8.6, 1.6), CFrame.new(0, 6.6, 0), under)
	TP("Roof", Vector3.new(7.4, 0.8, 56), CFrame.new(0, 11.2, 0), C(120, 124, 132))
	for _, sz in ipairs({ -1, 1 }) do
		local turn = (sz > 0) and CFrame.Angles(0, math.pi, 0) or CFrame.new()
		TP("Nose", Vector3.new(8.6, 8.4, 5), CFrame.new(0, 6.6, sz * 31.5) * turn, red, M.Metal, true, true)
		TP("NoseGlass", Vector3.new(7, 2.6, 0.3), CFrame.new(0, 8.6, sz * 30.2) * turn * CFrame.Angles(math.rad(-31), 0, 0) * CFrame.new(0, 0.6, -1.2), glass, M.Glass)
		TP("Plow", Vector3.new(8.4, 2, 3), CFrame.new(0, 1.7, sz * 32.4) * turn, under, M.Metal, false, true)
		for _, x in ipairs({ -2.6, 2.6 }) do
			local lamp = TP("Headlight", Vector3.new(1.2, 1, 0.4), CFrame.new(x, 3.3, sz * 33.8), C(255, 244, 200), M.Neon)
			K.new("SpotLight", { Face = (sz < 0) and Enum.NormalId.Front or Enum.NormalId.Back, Angle = 60, Range = 60, Brightness = 3, Color = C(255, 240, 200), Shadows = false }, lamp)
		end
		TP("Bogie", Vector3.new(7, 1.5, 12), CFrame.new(0, 1.75, sz * 17), under)
		for _, x in ipairs({ -3, 3 }) do
			for _, o in ipairs({ -3.6, 3.6 }) do
				local w = K.cyl(train, "Wheel", 2.4, 0.6, base * CFrame.new(x, 1.6, sz * 17 + o) * CFrame.Angles(0, 0, math.rad(90)), C(60, 62, 70), M.Metal, { Anchored = false, Massless = true, CanCollide = false, CastShadow = false })
				K.weld(root, w)
			end
		end
	end
	local zdir = -cf.LookVector
	local anchor = K.zone(model, "TrackAnchor", Vector3.new(1, 1, 1), L(0, 6.6, 0))
	local a0 = K.new("Attachment", { Name = "A0" }, anchor)
	a0.WorldCFrame = CFrame.fromMatrix(anchor.Position, zdir, Vector3.yAxis)
	local a1 = K.new("Attachment", { Name = "A1" }, root)
	a1.WorldCFrame = CFrame.fromMatrix(root.Position, zdir, Vector3.yAxis)
	K.new("PrismaticConstraint", { Attachment0 = a0, Attachment1 = a1, ActuatorType = Enum.ActuatorType.Motor, Velocity = 0, MotorMaxForce = 1e10, MotorMaxAcceleration = 500, LimitsEnabled = true, LowerLimit = -startZ, UpperLimit = startZ, Restitution = 0 }, root)
	train.PrimaryPart = root
	K.tag(train, "Train", { Speed = 120, Every = 16, Length = 68 })
	for _, sz in ipairs({ -1, 1 }) do
		local p = L(sz * 11, 0, sz * 16)
		K.cyl(model, "SignalPost", 0.6, 9, p * CFrame.new(0, 4.5, 0), PAL.steelDark, M.Metal)
		local head = p * CFrame.new(0, 8.6, 0) * CFrame.Angles(0, math.rad(90), 0)
		K.part(model, "SignalHead", Vector3.new(4.6, 1.8, 0.8), head, C(24, 24, 28), M.Metal)
		for _, o in ipairs({ -1.2, 1.2 }) do
			for _, f in ipairs({ -0.45, 0.45 }) do
				K.cyl(model, "TrainLight", 1.3, 0.2, head * CFrame.new(o, 0, f) * CFrame.Angles(math.rad(90), 0, 0), C(70, 20, 20), M.Neon, { CastShadow = false })
			end
		end
	end
	K.danger(model, L(13, 0, -30) * CFrame.Angles(0, math.rad(90), 0), "KEEP OFF")
	K.station(model, L(0, 0.9, -24) * CFrame.Angles(0, math.rad(90), 0), "stand", 10, 1)
	K.station(model, L(0, 0.9, 36) * CFrame.Angles(0, math.rad(-90), 0), "stand", 10, 1)
end
