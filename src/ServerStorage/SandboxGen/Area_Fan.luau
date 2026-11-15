--!nocheck
-- THE BIG FAN: a 31-stud fan on an A-frame. Its Switch turns the rotor (tag Rotor, a hinge motor), the wind (tag
-- FanZone: it also SUCKS from behind) and the blades (tag ChopZone) on and off - Sandbox.Machines runs all three.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local green, dark = C(104, 128, 112), C(64, 74, 70)
	local HY, R = 18, 15.5
	K.ground(L(0, 0, 5), Vector3.new(44, 0, 22), Enum.Material.Concrete)
	K.ground(L(0, 0, -52), Vector3.new(18, 0, 86), Enum.Material.Ground) -- the lane the wind has scoured bare
	K.part(model, "Plinth", Vector3.new(30, 1, 14), L(0, 0.5, 4), PAL.concrete, Enum.Material.Concrete)
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Leg", Vector3.new(2.6, 21, 4), L(sx * 15.6, 10.6, 3) * CFrame.Angles(0, 0, math.rad(sx * 9)), green, Enum.Material.Metal)
		K.part(model, "Brace", Vector3.new(2, 20, 2), L(sx * 15.2, 10, 8.6) * CFrame.Angles(math.rad(-24), 0, math.rad(sx * 9)), dark, Enum.Material.Metal)
		K.part(model, "Foot", Vector3.new(6, 1.2, 15), L(sx * 17.2, 1.6, 6), dark, Enum.Material.Metal)
	end
	for i = 0, 19 do
		local a = i / 20 * math.pi * 2
		K.part(model, "Hoop", Vector3.new(5.1, 1.6, 6), L(math.sin(a) * R, HY + math.cos(a) * R, 0) * CFrame.Angles(0, 0, -a), (i % 5 == 0) and PAL.hazard or green, Enum.Material.Metal)
	end
	local mount = K.cyl(model, "FanMount", 6, 5, L(0, HY, 3.8) * CFrame.Angles(math.rad(90), 0, 0), dark, Enum.Material.Metal)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + math.pi
		K.part(model, "Strut", Vector3.new(1, R - 2, 1), L(math.sin(a) * (R / 2 + 1), HY + math.cos(a) * (R / 2 + 1), 3.8) * CFrame.Angles(0, 0, -a), dark, Enum.Material.Metal)
	end
	local hub = K.cyl(model, "FanRotor", 5, 3, L(0, HY, -0.6) * CFrame.Angles(math.rad(90), 0, 0), PAL.hazard, Enum.Material.Metal, { Anchored = false, tag = "Rotor", attrs = { Spin = 15, Group = "fan" } })
	hub.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.1)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local blade = K.part(hub, "Blade", Vector3.new(4.4, 12.6, 0.5), L(math.sin(a) * 8, HY + math.cos(a) * 8, -0.6) * CFrame.Angles(0, 0, -a) * CFrame.Angles(0, math.rad(24), 0), C(206, 210, 214), Enum.Material.Metal, { Anchored = false, Massless = true })
		K.weld(hub, blade)
	end
	local at = L(0, HY, 1).Position
	local function att(part, name)
		local a = K.new("Attachment", { Name = name }, part)
		a.WorldCFrame = CFrame.fromMatrix(at, cf.LookVector, Vector3.yAxis)
		return a
	end
	K.new("HingeConstraint", { Attachment0 = att(mount, "A0"), Attachment1 = att(hub, "A1"), ActuatorType = Enum.ActuatorType.Motor, AngularVelocity = 0, MotorMaxTorque = 1e9, MotorMaxAcceleration = 14 }, hub)
	K.new("NoCollisionConstraint", { Part0 = mount, Part1 = hub }, hub)
	K.zone(model, "FanZone", Vector3.new(27, 30, 150), L(0, 15, -50), "FanZone", { Power = 150, FanAt = 50, Group = "fan", On = false })
	K.zone(model, "ChopZone", Vector3.new(27, 27, 3.4), L(0, HY, -0.6), "ChopZone", { Damage = 44, Sever = 0.55, Fling = 95, Group = "fan", On = false })
	K.button(model, L(22, 0, 13), "Switch", "Turn on the fan", "The Big Fan", { Group = "fan", On = false, Label = "the fan" })
	K.danger(model, L(-22, 0, -7) * CFrame.Angles(0, math.rad(20), 0))
	K.station(model, L(-4, 0.3, -24) * CFrame.Angles(0, math.pi, 0), "stand", 9, 1)
	K.station(model, L(5, 0.3, -38) * CFrame.Angles(0, math.pi, 0), "stand", 9, 1)
end
