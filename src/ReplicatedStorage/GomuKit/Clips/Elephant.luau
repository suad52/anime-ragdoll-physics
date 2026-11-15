--!nocheck
-- GomuKit.Clips.Elephant (owner: elephant): R, Gear Third ELEPHANT GUN. Returns function(H) -> clips (merged by name
-- over the base Clips). One clip covers the whole cast, keyed to Config.Elephant (t after t0):
--   0.06 BITE (thumb to the teeth, H.BITE) | 0.12 CHOMP (the head jerks, the wrist snaps) | 0.30 SWELL (Back Out:
--   chest thrown back, head up, the free arm braced out while the right arm inflates - it is hidden from InflateAt,
--   the stretch library draws it) | 0.30-0.62 tremble | 0.80 COIL / 0.93 COIL2 (torso wound far right, weight back,
--   the left hand pointing down the aim) | 0.99 PUNCH (Exponential Out: chest whipped left, lunging - the client adds
--   2.2 studs of real root motion) | 1.07 OVER (Back Out) | 1.19-1.44 the impact shudder | 1.78 RECOIL (Back Out: he
--   staggers back as the arm deflates) | 1.94 SETTLE | 2.12 REST.
-- Legs: COIL / LUNGE are the Ichigo kit's FK-solved legs (both soles on the floor). Poses NOT FK-checked on a rig.
return function(H)
	local merge, tremble, key = H.merge, H.tremble, H.key
	local V = Vector3.new

	local COIL_LEGS = {
		Root = { 0, -14, 0, pos = V(0, -0.75, 0.3) },
		LeftHip = { 66.9, 0, -16.2 }, LeftKnee = { -105, 0, 0 }, LeftAnkle = { 38.5, 0, 0 },
		RightHip = { -38, 0, 17.1 }, RightKnee = { -22.9, 0, 0 }, RightAnkle = { 65.1, 0, 0 },
	}
	local LUNGE_LEGS = {
		Root = { -6, 16, 0, pos = V(0, -0.75, -0.6) },
		LeftHip = { 23.6, 0, -13.7 }, LeftKnee = { -97.8, 0, 0 }, LeftAnkle = { 73.1, 0, 0 },
		RightHip = { -45.6, 0, 15.9 }, RightKnee = { -16.6, 0, 0 }, RightAnkle = { 65.9, 0, 0 },
	}
	local ARM_R_UP = { RightShoulder = { 150, 0, 30 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 } } -- hidden

	local BITE = H.BITE
	local CHOMP = merge(BITE, {
		Neck = { -2, -10, 0 }, RightWrist = { -34, 0, 0 }, Root = { 0, 0, 0, pos = V(0, -0.72, 0.15) },
	})
	local SWELL = merge(H.WIDE, ARM_R_UP, {
		Root = { 4, -6, 0, pos = V(0, -0.55, 0.25) },
		Waist = { 14, -10, 0 }, Neck = { 16, 4, 0 },
		LeftShoulder = { 22, 0, -58 }, LeftElbow = { 72, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local COIL = merge(COIL_LEGS, ARM_R_UP, {
		Waist = { 6, -42, 0 }, Neck = { -4, 34, 0 },
		LeftShoulder = { 86, 30, -6 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local COIL2 = merge(COIL, {
		Root = { 2, -18, 0, pos = V(0, -0.8, 0.45) }, Waist = { 9, -50, 0 }, Neck = { -6, 40, 0 },
	})
	local PUNCH = merge(LUNGE_LEGS, ARM_R_UP, {
		Waist = { -20, 34, 0 }, Neck = { -8, -26, 0 },
		LeftShoulder = { -35, 0, -30 }, LeftElbow = { 105, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local OVER = merge(PUNCH, {
		Root = { -9, 20, 0, pos = V(0, -0.82, -0.8) }, Waist = { -25, 40, 0 }, Neck = { -10, -30, 0 },
	})
	local HOLD2 = merge(OVER, {
		Root = { -6, 18, 0, pos = V(0, -0.78, -0.7) }, Waist = { -20, 36, 0 },
	})
	local RECOIL = merge(H.LOW, ARM_R_UP, {
		Root = { 7, 6, 0, pos = V(0, -0.4, 0.7) },
		Waist = { 15, 10, 0 }, Neck = { 14, 0, 0 },
		LeftShoulder = { 46, 0, -62 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SETTLE = merge(H.GUARD, { Root = { 0, 0, 0, pos = V(0, -0.6, 0.15) } })
	local REST = H.REST

	local keys = {
		key(0.06, BITE, "Back", "Out"),
		key(0.12, CHOMP, "Quad", "Out"),
		key(0.30, SWELL, "Back", "Out"),
	}
	for _, k in ipairs(tremble(0.30, 0.62, 5, SWELL, { Waist = true, Neck = true, LeftShoulder = true }, 2.2)) do
		table.insert(keys, k)
	end
	table.insert(keys, key(0.80, COIL, "Sine", "InOut"))
	table.insert(keys, key(0.93, COIL2, "Quad", "Out"))
	table.insert(keys, key(0.99, PUNCH, "Exponential", "Out"))
	table.insert(keys, key(1.07, OVER, "Back", "Out"))
	for _, k in ipairs(tremble(1.19, 1.44, 3, OVER, { Waist = true, Neck = true }, 1.6)) do
		table.insert(keys, k)
	end
	table.insert(keys, key(1.52, HOLD2, "Sine", "InOut"))
	table.insert(keys, key(1.78, RECOIL, "Back", "Out"))
	table.insert(keys, key(1.94, SETTLE, "Sine", "InOut"))
	table.insert(keys, key(2.12, REST, "Sine", "Out"))

	return {
		Elephant_Cast = { length = 2.15, fadeIn = 0.06, fadeOut = 0.18, keys = keys },
	}
end
