--!nocheck
-- THE BLENDER: a two-armed propeller sweeping a round pad at shin height. The rotor is a hinge motor (tag Rotor); the
-- ChopZone (Arms = 2) only hurts what an arm is actually passing over. Switch = on / off.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	K.groundDisc(cf.Position, 26, Enum.Material.Concrete)
	K.cyl(model, "Pad", 46, 0.6, L(0, 0.3, 0), PAL.concrete, Enum.Material.Concrete)
	for i = 2, 22 do -- kerb, open at the front
		local a = i / 24 * math.pi * 2
		K.part(model, "Kerb", Vector3.new(6.2, 1.3, 1.6), L(math.sin(a) * 23.4, 0.95, -math.cos(a) * 23.4) * CFrame.Angles(0, -a, 0), PAL.curb, Enum.Material.Concrete)
	end
	local mount = K.cyl(model, "PropMount", 7, 0.5, L(0, 0.85, 0), C(48, 52, 60), Enum.Material.Metal)
	local hub = K.cyl(model, "PropRotor", 5, 3.6, L(0, 3, 0), C(40, 42, 48), Enum.Material.Metal, { Anchored = false, tag = "Rotor", attrs = { Spin = 5.5, Group = "prop" } })
	hub.CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0.1)
	local beam = K.part(hub, "Arm", Vector3.new(36, 2, 2.6), L(0, 2.3, 0), PAL.white, Enum.Material.Metal, { Anchored = false, Massless = true })
	K.weld(hub, beam)
	for _, sx in ipairs({ -1, 1 }) do
		local cap = K.part(hub, "ArmCap", Vector3.new(2.4, 2.3, 2.9), L(sx * 17.4, 2.3, 0), C(30, 30, 34), Enum.Material.Metal, { Anchored = false, Massless = true })
		K.weld(hub, cap)
	end
	local dirAtt = K.new("Attachment", { Name = "ArmDir" }, hub)
	dirAtt.WorldCFrame = CFrame.lookAt(hub.Position, hub.Position + cf.RightVector)
	local function att(part, name)
		local a = K.new("Attachment", { Name = name }, part)
		a.WorldCFrame = CFrame.fromMatrix(L(0, 1.4, 0).Position, Vector3.yAxis, cf.RightVector)
		return a
	end
	K.new("HingeConstraint", { Attachment0 = att(mount, "A0"), Attachment1 = att(hub, "A1"), ActuatorType = Enum.ActuatorType.Motor, AngularVelocity = 5.5, MotorMaxTorque = 1e9, MotorMaxAcceleration = 5 }, hub)
	K.new("NoCollisionConstraint", { Part0 = mount, Part1 = hub }, hub)
	K.zone(model, "ChopZone", Vector3.new(38, 3.6, 38), L(0, 2.3, 0), "ChopZone", { Damage = 30, Type = "blunt", Arms = 2, Radius = 18.6, Group = "prop", On = true })
	K.button(model, L(5, 0, -29), "Switch", "Turn off the blender", "The Blender", { Group = "prop", On = true, Label = "the blender" })
	K.danger(model, L(-12, 0, -27) * CFrame.Angles(0, math.rad(-14), 0))
	K.station(model, L(-9, 0.7, 6), "stand", 9, 1)
	K.station(model, L(10, 0.7, -5), "stand", 9, 1)
end
