--!nocheck
-- Clips pass: Q, DELAWARE SMASH: AIR FORCE (flair). Replaces Clips.AirForce. Cast time = clip time; the flick
-- (Config.AirForce.Windup) is 0.36. Every key was FK-checked on an R15 preview rig: both soles within 0.02 of the
-- floor through the planted keys (the feet never slide: each key's legs are IK'd to the same two footprints, right
-- foot 0.7 ahead, left 0.62 behind), no arm inside the body, no hyperextension, the right arm on the aim from AIM to
-- COCK. Keys marked aim = 1 take the cast's aim pitch on the right shoulder (x1.15: the twisted chest turns the
-- shoulder's axis, so only ~0.85 of a bend reaches the arm) and half of it on the neck - the AirForce client builds
-- that variant. Verifier pass: AIM / STRAIN / COCK shoulders raised 2 / 4 / 6 degrees (the arm sat 3-8 degrees under
-- the aim); the arm now stays within 5 degrees of the aim at pitch 0 and 6 at +25, the tremble included.
--   0.07 DRAW   weight back, chest coiled right, right hand cocked by the ear, left arm sighting the target
--   0.17 AIM    the chest whips side-on, the right arm shoots out at the target (Back overshoot), left fist yanked back
--   0.20-0.31   STRAIN tremble (finger drawn to the thumb, energy pooling), sinking
--   0.345 COCK  the last dip before the shot (Quad In)
--   0.372 FLICK the wrist snaps up, the recoil kicks the arm and hips back, chin up (the client hit-stops it here)
--   0.50 / 0.60 HOLD the hero pose, arm high, smoking
--   0.68-0.85   SHAKE the stinging hand is pulled in and flapped out three times while he looks at it
--   0.92 SETTLE, 1.04 REST
return function(H)
	local merge, tremble, REST = H.merge, H.tremble, H.REST
	-- legs IK'd to the same two footprints at each root height / slide
	local L_DRAW = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.40, 0.14) }, RightHip = { 58, 0, 12 }, RightKnee = { -55, 0, 0 }, RightAnkle = { -3, 0, 0 }, LeftHip = { 25, 0, -10 }, LeftKnee = { -83, 0, 0 }, LeftAnkle = { 45, 0, 0 } }
	local L_AIM = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.48, -0.04) }, RightHip = { 63, 0, 12 }, RightKnee = { -72, 0, 0 }, RightAnkle = { 9, 0, 0 }, LeftHip = { 17, 0, -10 }, LeftKnee = { -84, 0, 0 }, LeftAnkle = { 53, 0, 0 } }
	local L_STRAIN = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.52, -0.02) }, RightHip = { 66, 0, 12 }, RightKnee = { -75, 0, 0 }, RightAnkle = { 9, 0, 0 }, LeftHip = { 19, 0, -10 }, LeftKnee = { -88, 0, 0 }, LeftAnkle = { 55, 0, 0 } }
	local L_COCK = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.55, 0) }, RightHip = { 68, 0, 12 }, RightKnee = { -76, 0, 0 }, RightAnkle = { 9, 0, 0 }, LeftHip = { 21, 0, -10 }, LeftKnee = { -91, 0, 0 }, LeftAnkle = { 56, 0, 0 } }
	local L_FLICK = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.45, 0.22) }, RightHip = { 61, 0, 12 }, RightKnee = { -55, 0, 0 }, RightAnkle = { -6, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -90, 0, 0 }, LeftAnkle = { 45, 0, 0 } }
	local L_HOLD = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.43, 0.30) }, RightHip = { 59, 0, 12 }, RightKnee = { -47, 0, 0 }, RightAnkle = { -12, 0, 0 }, LeftHip = { 34, 0, -10 }, LeftKnee = { -90, 0, 0 }, LeftAnkle = { 42, 0, 0 } }
	local L_HOLD2 = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.42, 0.28) }, RightHip = { 59, 0, 12 }, RightKnee = { -47, 0, 0 }, RightAnkle = { -11, 0, 0 }, LeftHip = { 33, 0, -10 }, LeftKnee = { -88, 0, 0 }, LeftAnkle = { 42, 0, 0 } }
	local L_SHAKE = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.32, 0.18) }, RightHip = { 52, 0, 12 }, RightKnee = { -43, 0, 0 }, RightAnkle = { -9, 0, 0 }, LeftHip = { 24, 0, -10 }, LeftKnee = { -78, 0, 0 }, LeftAnkle = { 40, 0, 0 } }
	local L_SETTLE = { Root = { 0, 0, 0, pos = Vector3.new(0, -0.20, 0.08) }, RightHip = { 42, 0, 12 }, RightKnee = { -33, 0, 0 }, RightAnkle = { -9, 0, 0 }, LeftHip = { 14, 0, -10 }, LeftKnee = { -62, 0, 0 }, LeftAnkle = { 35, 0, 0 } }

	local DRAW = merge(L_DRAW, {
		Waist = { -4, -22, 0 }, Neck = { 2, 20, 0 },
		RightShoulder = { 18, 0, 106 }, RightElbow = { 139, 0, 0 }, RightWrist = { 24, 0, 0 },
		LeftShoulder = { 84, 0, -22 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -12, 0, 0 },
	})
	local AIM = merge(L_AIM, {
		Waist = { -8, 32, 0 }, Neck = { 0, -28, 0 },
		RightShoulder = { 103, 0, 16 }, RightElbow = { 4, 0, 0 }, RightWrist = { -30, 0, 0 },
		LeftShoulder = { -48, 0, -26 }, LeftElbow = { 84, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local STRAIN = merge(AIM, L_STRAIN, { Waist = { -10, 33, 0 }, Neck = { -2, -29, 0 }, RightShoulder = { 108, 0, 16 }, RightWrist = { -38, 0, 0 } })
	local COCK = merge(AIM, L_COCK, {
		Waist = { -11, 34, 0 }, Neck = { -3, -30, 0 },
		RightShoulder = { 109, 0, 17 }, RightElbow = { 6, 0, 0 }, RightWrist = { -48, 0, 0 },
		LeftShoulder = { -52, 0, -28 }, LeftElbow = { 88, 0, 0 },
	})
	local FLICK = merge(L_FLICK, {
		Waist = { 4, 24, 0 }, Neck = { 12, -20, 0 },
		RightShoulder = { 110, 0, 14 }, RightElbow = { 10, 0, 0 }, RightWrist = { 44, 0, 0 },
		LeftShoulder = { -62, 0, -40 }, LeftElbow = { 64, 0, 0 }, LeftWrist = { 10, 0, 0 },
	})
	local HOLD = merge(L_HOLD, {
		Waist = { 6, 21, 0 }, Neck = { 9, -17, 0 },
		RightShoulder = { 106, 0, 14 }, RightElbow = { 14, 0, 0 }, RightWrist = { 32, 0, 0 },
		LeftShoulder = { -56, 0, -36 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 6, 0, 0 },
	})
	local HOLD2 = merge(L_HOLD2, {
		Waist = { 4, 19, 0 }, Neck = { 7, -15, 0 },
		RightShoulder = { 102, 0, 14 }, RightElbow = { 18, 0, 0 }, RightWrist = { 26, 0, 0 },
		LeftShoulder = { -50, 0, -32 }, LeftElbow = { 72, 0, 0 }, LeftWrist = { 4, 0, 0 },
	})
	local SHAKE = merge(L_SHAKE, {
		Waist = { -6, 6, 0 }, Neck = { -14, -22, 0 },
		RightShoulder = { 52, 0, 18 }, RightElbow = { 96, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 18, 0, -20 }, LeftElbow = { 44, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local FLAP1 = merge(SHAKE, { RightShoulder = { 56, 0, 16 }, RightElbow = { 104, 0, 0 }, RightWrist = { 38, 0, 0 }, Neck = { -12, -24, 0 } })
	local FLAP2 = merge(SHAKE, { RightShoulder = { 48, 0, 20 }, RightElbow = { 90, 0, 0 }, RightWrist = { -32, 0, 0 }, Neck = { -15, -20, 0 } })
	local FLAP3 = merge(SHAKE, { RightShoulder = { 52, 0, 18 }, RightElbow = { 98, 0, 0 }, RightWrist = { 22, 0, 0 }, Neck = { -13, -22, 0 } })
	local SETTLE = merge(L_SETTLE, {
		Waist = { -4, 2, 0 }, Neck = { -4, -6, 0 },
		RightShoulder = { 28, 0, 18 }, RightElbow = { 56, 0, 0 }, RightWrist = { -8, 0, 0 },
		LeftShoulder = { 12, 0, -16 }, LeftElbow = { 32, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})

	local keys = {
		{ t = 0.07, ease = { "Quad", "Out" }, pose = DRAW },
		{ t = 0.17, ease = { "Back", "Out" }, pose = AIM, aim = 1 },
	}
	for _, k in ipairs(tremble(0.17, 0.31, 4, STRAIN, { RightShoulder = true, RightWrist = true, Waist = true, Neck = true }, 1.6)) do
		k.aim = 1
		table.insert(keys, k)
	end
	for _, k in ipairs({
		{ t = 0.345, ease = { "Quad", "In" }, pose = COCK, aim = 1 },
		{ t = 0.372, ease = { "Exponential", "Out" }, pose = FLICK, aim = 1 },
		{ t = 0.5, ease = { "Sine", "Out" }, pose = HOLD, aim = 1 },
		{ t = 0.6, ease = { "Sine", "InOut" }, pose = HOLD2, aim = 0.8 },
		{ t = 0.68, ease = { "Quad", "InOut" }, pose = SHAKE },
		{ t = 0.735, ease = { "Quad", "Out" }, pose = FLAP1 },
		{ t = 0.79, ease = { "Sine", "InOut" }, pose = FLAP2 },
		{ t = 0.845, ease = { "Sine", "InOut" }, pose = FLAP3 },
		{ t = 0.92, ease = { "Sine", "Out" }, pose = SETTLE },
		{ t = 1.04, ease = { "Sine", "InOut" }, pose = REST },
	}) do
		table.insert(keys, k)
	end
	return {
		AirForce = { length = 1.1, fadeIn = 0.05, fadeOut = 0.22, flick = 0.372, keys = keys },
	}
end
