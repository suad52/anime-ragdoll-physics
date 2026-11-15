--!nocheck
-- THE GRINDER: a concrete-rimmed funnel in the ground with two toothed rollers turning into each other at the bottom
-- (tag Rotor hinge motors; the GrindZone is what chews). A dummy waits on the plank over it; the button's ram shoves it
-- in (tag PlankPush). There is deliberately no way out.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	workspace.Terrain:FillBlock(L(0, -10, 0), Vector3.new(28, 20, 28), Enum.Material.Air)
	local conc, darkc = C(196, 194, 188), C(96, 98, 104)
	for _, s in ipairs({ { 0, -11.5, 26, 3 }, { 0, 11.5, 26, 3 }, { -11.5, 0, 3, 20 }, { 11.5, 0, 3, 20 } }) do
		K.part(model, "Rim", Vector3.new(s[3], 2, s[4]), L(s[1], 0.6, s[2]), conc, Enum.Material.Concrete)
	end
	-- (2026-11-14, owner: "the edge of the ground of the grinder isnt filled in properly, i can see through it") the
	-- carve's smooth edge left a crater round the rim, ~3 studs deep at its outer face, and through it you saw under the
	-- rim: the funnels' undersides, the chamber walls, the red glow. So: grass back up to the rim (top at -2 lands the
	-- surface on 0, like the field), the pit's inside carved clean again (the fill had crept onto the end walls' inner
	-- faces), and a concrete skirt under the rim, flush with its outer face, for wherever the grass still sits low.
	for _, b in ipairs({ { 0, 14.75, 35, 5.5 }, { 0, -14.75, 35, 5.5 }, { 14.75, 0, 5.5, 24 }, { -14.75, 0, 5.5, 24 } }) do
		workspace.Terrain:FillBlock(L(b[1], -6, b[2]), Vector3.new(b[3], 8, b[4]), Enum.Material.Grass)
	end
	workspace.Terrain:FillBlock(L(0, -10.2, 0), Vector3.new(21.6, 19.5, 22), Enum.Material.Air)
	for _, s in ipairs({ { 0, 12.05, 26, 1.9 }, { 0, -12.05, 26, 1.9 }, { 11.8, 0, 2.4, 22.2 }, { -11.8, 0, 2.4, 22.2 } }) do
		K.part(model, "GrinderSkirt", Vector3.new(s[3], 5.6, s[4]), L(s[1], -3.2, s[2]), conc, Enum.Material.Concrete)
	end
	local ang = math.atan2(8.5, 5.8)
	local len = math.sqrt(8.5 ^ 2 + 5.8 ^ 2) + 0.6
	local slick = PhysicalProperties.new(0.7, 0.03, 0.1, 100, 1)
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Funnel", Vector3.new(len, 0.8, 20), L(sx * 7.1, -4.25, 0) * CFrame.Angles(0, 0, sx * ang), darkc, Enum.Material.Metal, { CustomPhysicalProperties = slick })
		K.part(model, "ChamberWall", Vector3.new(1, 8, 20), L(sx * 5.2, -12.4, 0), C(60, 62, 68), Enum.Material.CorrodedMetal)
	end
	for _, sz in ipairs({ -1, 1 }) do
		K.part(model, "EndWall", Vector3.new(21, 17, 1), L(0, -8, sz * 10.5), darkc, Enum.Material.Metal, { CustomPhysicalProperties = slick })
	end
	K.part(model, "PitFloor", Vector3.new(11, 1, 21), L(0, -16.4, 0), C(40, 40, 44), Enum.Material.Metal)
	local glow = K.part(model, "Glow", Vector3.new(8.6, 0.3, 19), L(0, -15.7, 0), PAL.red, Enum.Material.Neon, { CastShadow = false })
	K.new("PointLight", { Range = 26, Brightness = 2.6, Color = C(255, 80, 50), Shadows = false }, glow)
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * 2.35
		local mount = K.part(model, "RollerMount", Vector3.new(1.4, 1.4, 0.6), L(x, -10.6, 10.1), C(40, 40, 44), Enum.Material.Metal)
		local roller = K.cyl(model, "Roller", 4.2, 19, L(x, -10.6, 0) * CFrame.Angles(math.rad(90), 0, 0), C(128, 132, 140), Enum.Material.DiamondPlate, { Anchored = false, tag = "Rotor", attrs = { Spin = sx * 7, Group = "grinder" } })
		roller.CustomPhysicalProperties = PhysicalProperties.new(4, 1.5, 0, 100, 1)
		for k = 0, 5 do
			for j = -2, 2 do
				local tooth = K.part(roller, "Tooth", Vector3.new(0.7, 0.9, 1.6), roller.CFrame * CFrame.Angles(k * math.pi / 3 + j * 0.5, 0, 0) * CFrame.new(j * 3.6, 2.3, 0), C(70, 72, 80), Enum.Material.Metal, { Anchored = false, Massless = true, CanCollide = false, CastShadow = false })
				K.weld(roller, tooth)
			end
		end
		local function att(part, name)
			local a = K.new("Attachment", { Name = name }, part)
			a.WorldCFrame = CFrame.fromMatrix(roller.Position, roller.CFrame.RightVector, Vector3.yAxis)
			return a
		end
		K.new("HingeConstraint", { Attachment0 = att(mount, "A0"), Attachment1 = att(roller, "A1"), ActuatorType = Enum.ActuatorType.Motor, AngularVelocity = sx * 7, MotorMaxTorque = 1e9, MotorMaxAcceleration = 8 }, roller)
	end
	K.zone(model, "GrindZone", Vector3.new(9.4, 6, 19.4), L(0, -9.6, 0), "GrindZone", { Damage = 26, Group = "grinder", On = true })
	-- (2026-11-13) THE PUSHER, not a drop chute: the owner wanted the button to shove the body standing on the plank in
	-- rather than spawn one in mid-air. A ram behind the plank does it (tag PlankPush on the button: Spot = where the
	-- body stands, facing the way it goes; the part named Ram is what moves, attribute Travel).
	local spot = L(0, 2.1, -6.5) * CFrame.Angles(0, math.pi, 0)
	K.part(model, "Step", Vector3.new(6, 0.8, 3), L(0, 0.4, -15.6), conc, Enum.Material.Concrete)
	K.part(model, "Plank", Vector3.new(4, 0.5, 11), L(0, 1.85, -8.5), PAL.wood, Enum.Material.WoodPlanks)
	K.part(model, "RamHousing", Vector3.new(3.6, 3.8, 2.6), L(0, 4, -13.2), C(48, 52, 60), Enum.Material.Metal)
	K.part(model, "RamCap", Vector3.new(4, 0.5, 3), L(0, 6.15, -13.2), PAL.hazard, Enum.Material.Metal)
	local ram = K.part(model, "Ram", Vector3.new(3.2, 3.2, 0.5), L(0, 4, -11.6), PAL.hazard, Enum.Material.Metal, { CanCollide = false, attrs = { Travel = 4.4 } })
	local face = K.part(ram, "RamFace", Vector3.new(2.2, 2.2, 0.56), L(0, 4, -11.6), C(30, 30, 34), Enum.Material.Metal, { Anchored = false, Massless = true, CanCollide = false })
	K.weld(ram, face)
	local rod = K.cyl(ram, "RamRod", 0.9, 4.6, L(0, 4, -14.15) * CFrame.Angles(math.rad(90), 0, 0), C(200, 204, 210), Enum.Material.Metal, { Anchored = false, Massless = true, CanCollide = false })
	K.weld(ram, rod)
	K.button(model, L(-9, 0, -19), "PlankPush", "Push him in", "The Grinder", { Spot = spot })
	K.button(model, L(9, 0, -19), "Switch", "Turn off the grinder", "The Grinder", { Group = "grinder", On = true, Label = "the grinder" })
	K.danger(model, L(-17, 0, 6) * CFrame.Angles(0, math.rad(70), 0))
	K.station(model, spot * CFrame.new(0, 0.1, 0), "stand", 4, 1)
end
