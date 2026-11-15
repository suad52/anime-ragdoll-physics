--!nocheck
-- OneForAllKit.Clips pass "Flair_OFA": G, ONE FOR ALL 1,000,000% - the flair pass. Replaces OFACharge, OFASmash and
-- OFAFloat and adds OFAFlairLand (played by Client.Ultimate on touchdown). Cast times match Config's Flair_OFA:
--   OFACharge at 0      bow over the fists 0.10 (shaking) -> 100%: the overloading arm thrust out in front of him, its
--                       wrist clamped by the left hand 0.42 (shaking harder) -> BLACKWHIP roar 0.84 -> re-chamber,
--                       reaching for the ring 1.22 -> the deepest wind-up of the kit 1.58 (shaking) -> 1.85
--   OFASmash  at 1.85   launch 1.90 -> rise 2.05 -> the air coil 2.21 / 2.28 -> the fist drives up 2.315 ->
--                       1,000,000% DETROIT SMASH 2.35 (Back overshoot) held to 2.63 -> the arm gives 2.79
--   OFAFloat  at 2.70   the broken arm hanging, head up at the hole, legs loose -> legs reach for the ground
--   OFAFlairLand        touchdown crouch (left hand braced at the ground) -> power stance by +0.38 (Lock 4.25 covers it)
-- Signs: shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X, +Y turns left, right limb out
-- Z+, left limb out Z-, Neck +X lifts the chin; Root pos -Y crouches, +Z slides back. Every clip was FK-checked at 30 Hz
-- on the default R15 constraint rig (blocky 1-stud limbs): planted soles within 0.1 of the floor, no box overlap deeper
-- than ~0.15 between a hand / forearm / shin / foot and the head or torso (the verify pass re-posed GRIP, which put the
-- left forearm 0.54 through the face, and WIND, which folded the chest 0.46 into the left thigh), the uppercut 0.99 UP.
-- No single joint turns more than ~150 degrees between two keys (a quaternion lerp takes the SHORT way round, so the
-- uppercut gets a "drive" key in front of the chest instead of swinging back over the shoulder).
return function(H)
	local merge, seq, root, tremble = H.merge, H.seq, H.root, H.tremble
	local CROUCH, LOW = H.CROUCH, H.LOW

	-- planted horse stance: feet wide, knees deep, soles flat (hip + knee + ankle ~ 0)
	local HORSE = merge(root(0, -0.9, 0.1), {
		LeftHip = { 62, 0, -20 }, LeftKnee = { -114, 0, 0 }, LeftAnkle = { 52, 0, 14 },
		RightHip = { 62, 0, 20 }, RightKnee = { -114, 0, 0 }, RightAnkle = { 52, 0, -14 },
	})
	-- 0.10: hunched over clenched fists chambered at the hips, head bowed - the power gathering into him
	local BOW = merge(HORSE, {
		Waist = { -20, 0, 0 }, Neck = { -22, 0, 0 },
		RightShoulder = { -18, 0, 26 }, RightElbow = { 96, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { -18, 0, -26 }, LeftElbow = { 96, 0, 0 }, LeftWrist = { 10, 0, 0 },
	})
	-- 0.42: 100% - the overloading right arm thrust out at chest height, the left hand clamped against its wrist,
	-- head dropped glaring at the fist (both arms stay a hand's width in front of the chest: no crossing through it)
	local GRIP = merge(HORSE, {
		Waist = { -8, 14, 0 }, Neck = { -14, -12, 0 },
		RightShoulder = { 88, 0, -28 }, RightElbow = { 14, 0, 0 }, RightWrist = { -10, 0, 0 },
		LeftShoulder = { 74, 32, 42 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	-- 0.84: BLACKWHIP - chest thrown back, chin up roaring, arms flung wide (the tendrils leave both forearms)
	local LASH = merge(HORSE, root(0, -0.8, 0.25), {
		Waist = { 16, 0, 0 }, Neck = { 28, 0, 0 },
		RightShoulder = { 70, 0, 92 }, RightElbow = { 10, 0, 0 }, RightWrist = { -40, 0, 0 },
		LeftShoulder = { 70, 0, -92 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -40, 0, 0 },
	})
	-- 1.22: re-chamber - right fist back at the hip, left arm reaching up at the hanging ring, eyes up
	local RECHAMBER = merge(HORSE, {
		Waist = { -6, -20, 0 }, Neck = { 32, 14, 0 },
		RightShoulder = { -30, 0, 26 }, RightElbow = { 125, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 160, 0, -18 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	-- 1.58: the deepest wind-up in the kit - sunk to the floor, chest coiled right, the fist cocked low and back
	-- (hips 72 / knees -120 / ankles 48 keep the soles flat; the lean stays at -18 so the chest clears the left thigh)
	local WIND = merge(root(0, -0.93, 0.05), {
		LeftHip = { 72, 0, -12 }, LeftKnee = { -120, 0, 0 }, LeftAnkle = { 48, 0, 8 },
		RightHip = { 72, 0, 12 }, RightKnee = { -120, 0, 0 }, RightAnkle = { 48, 0, -8 },
		Waist = { -18, -24, 0 }, Neck = { 34, 18, 0 },
		RightShoulder = { -50, 0, 34 }, RightElbow = { 118, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 40, 0, -30 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})

	local OFACharge = {
		length = 1.9, fadeIn = 0.1, fadeOut = 0.05,
		keys = seq(
			{ { t = 0.1, ease = { "Back", "Out" }, pose = BOW } },
			tremble(0.1, 0.36, 4, BOW, { Waist = true, Neck = true, RightShoulder = true, LeftShoulder = true }, 2.2),
			{ -- the fists come up out of the chamber in front of him, so neither forearm sweeps through the chest
				{ t = 0.385, ease = { "Quad", "Out" }, pose = {
					RightShoulder = { 55, -10, 0 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 55, 10, 0 }, LeftElbow = { 50, 0, 0 },
				} },
				{ t = 0.42, ease = { "Exponential", "Out" }, pose = GRIP },
			},
			tremble(0.42, 0.78, 6, GRIP, { Waist = true, Neck = true, RightShoulder = true, RightElbow = true }, 3.2),
			{
				{ t = 0.84, ease = { "Back", "Out" }, pose = LASH },
				{ t = 1.0, ease = { "Sine", "Out" }, pose = merge(LASH, { -- the roar carries on
					Waist = { 19, 0, 0 }, Neck = { 32, 0, 0 },
					RightShoulder = { 74, 0, 96 }, LeftShoulder = { 74, 0, -96 },
				}) },
				{ t = 1.22, ease = { "Quad", "InOut" }, pose = RECHAMBER },
				{ t = 1.4, ease = { "Sine", "InOut" }, pose = merge(RECHAMBER, {
					Neck = { 36, 12, 0 }, LeftShoulder = { 166, 0, -14 }, Waist = { -8, -24, 0 },
				}) },
				{ t = 1.58, ease = { "Quad", "Out" }, pose = WIND },
			},
			tremble(1.58, 1.84, 4, WIND, { Waist = true, Neck = true, RightShoulder = true, RightElbow = true }, 2.0)
		),
	}

	-- G: the leap and the upward smash (played at cast 1.85)
	local LAUNCH = merge(root(0, 0.2, 0), {
		LeftHip = { 4, 0, -6 }, LeftKnee = { -18, 0, 0 }, LeftAnkle = { -36, 0, 0 },
		RightHip = { -14, 0, 8 }, RightKnee = { -30, 0, 0 }, RightAnkle = { -32, 0, 0 },
		Waist = { 10, -20, 0 }, Neck = { 34, 10, 0 },
		RightShoulder = { -28, 0, 32 }, RightElbow = { 116, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 160, 0, -20 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local COIL = merge(root(0, 0.2, 0), {
		LeftHip = { 70, 0, -10 }, LeftKnee = { -100, 0, 0 }, LeftAnkle = { -10, 0, 0 },
		RightHip = { 46, 0, 10 }, RightKnee = { -84, 0, 0 }, RightAnkle = { -10, 0, 0 },
		Waist = { -14, -38, 0 }, Neck = { 36, 24, 0 },
		RightShoulder = { -58, 0, 40 }, RightElbow = { 128, 0, 0 }, RightWrist = { 20, 0, 0 },
		LeftShoulder = { 120, 0, -26 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SMASH = merge(root(0, 0.5, 0), {
		Waist = { 16, 32, 0 }, Neck = { 42, -16, 0 },
		RightShoulder = { 174, 0, 6 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -36, 0, -56 }, LeftElbow = { 46, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 34, 0, -12 }, LeftKnee = { -76, 0, 0 }, LeftAnkle = { -10, 0, 0 },
		RightHip = { -26, 0, 12 }, RightKnee = { -30, 0, 0 }, RightAnkle = { -26, 0, 0 },
	})
	local OFASmash = {
		length = 1.0, fadeIn = 0.03, fadeOut = 0.12,
		keys = {
			{ t = 0.05, ease = { "Exponential", "Out" }, pose = LAUNCH }, -- 1.90: body stretched up, left arm leading
			{ t = 0.2, ease = { "Sine", "Out" }, pose = merge(LAUNCH, { -- 2.05: still rising
				Waist = { 12, -24, 0 }, LeftShoulder = { 166, 0, -16 }, LeftKnee = { -24, 0, 0 }, RightKnee = { -40, 0, 0 },
			}) },
			{ t = 0.36, ease = { "Quad", "Out" }, pose = COIL }, -- 2.21: knees tuck, the fist cocked DOWN and back
			{ t = 0.43, ease = { "Sine", "InOut" }, pose = merge(COIL, { -- 2.28: the coil strains
				Waist = { -18, -42, 0 }, Neck = { 38, 26, 0 },
				RightShoulder = { -62, 0, 42 }, RightElbow = { 124, 0, 0 },
			}) },
			{ t = 0.465, ease = { "Quad", "In" }, pose = { -- 2.315: the fist drives up past the chest
				RightShoulder = { 70, 0, 20 }, RightElbow = { 60, 0, 0 },
			} },
			{ t = 0.5, ease = { "Back", "Out" }, pose = SMASH }, -- 2.35: 1,000,000% DETROIT SMASH
			{ t = 0.56, ease = { "Sine", "Out" }, pose = merge(SMASH, { -- the hero pose, held
				Waist = { 14, 30, 0 }, Neck = { 42, -14, 0 },
				RightShoulder = { 172, 0, 8 }, RightElbow = { 2, 0, 0 },
			}) },
			{ t = 0.78, ease = { "Sine", "InOut" }, pose = merge(SMASH, { -- 2.63: still held, the body easing
				Waist = { 12, 26, 0 }, Neck = { 40, -12, 0 },
				RightShoulder = { 168, 0, 10 }, RightElbow = { 5, 0, 0 },
				LeftShoulder = { -30, 0, -50 }, LeftKnee = { -70, 0, 0 }, RightKnee = { -34, 0, 0 },
			}) },
			{ t = 0.94, ease = { "Sine", "Out" }, pose = { -- 2.79: the arm starts to give
				Waist = { 10, 18, 0 }, Neck = { 34, -6, 0 },
				RightShoulder = { 146, 0, 18 }, RightElbow = { 16, 0, 0 }, RightWrist = { 24, 0, 0 },
			} },
		},
	}

	-- G: the float down on the broken, smoking arm (played at cast 2.70); OFAFlairLand takes over on touchdown.
	-- A long fade-in, so the spent arm sinks out of the held uppercut over ~0.4 s instead of snapping down
	local OFAFloat = {
		length = 2.0, fadeIn = 0.4, fadeOut = 0.2,
		keys = {
			{ t = 0.18, ease = { "Sine", "Out" }, pose = merge(root(0, 0, 0), {
				Waist = { 10, 6, 0 }, Neck = { 30, 8, 0 },
				RightShoulder = { 22, 0, 34 }, RightElbow = { 24, 0, 0 }, RightWrist = { 34, 0, 0 }, -- limp, smoking
				LeftShoulder = { 46, 0, -64 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { -10, 0, 0 },
				LeftHip = { 24, 0, -8 }, LeftKnee = { -46, 0, 0 }, LeftAnkle = { -24, 0, 0 },
				RightHip = { 8, 0, 6 }, RightKnee = { -24, 0, 0 }, RightAnkle = { -32, 0, 0 },
			}) },
			{ t = 0.62, ease = { "Sine", "InOut" }, pose = { -- drifting: the dead arm sways, the head follows the light
				Waist = { 8, 10, 0 }, Neck = { 26, 12, 0 },
				RightShoulder = { 18, 0, 28 }, RightElbow = { 20, 0, 0 },
				LeftShoulder = { 52, 0, -70 }, LeftKnee = { -52, 0, 0 }, RightKnee = { -30, 0, 0 },
			} },
			{ t = 1.0, ease = { "Sine", "InOut" }, pose = { -- legs reach for the ground
				Waist = { 4, 0, 0 }, Neck = { 12, 0, 0 },
				LeftHip = { 30, 0, -10 }, LeftKnee = { -50, 0, 0 }, LeftAnkle = { -12, 0, 0 },
				RightHip = { 28, 0, 10 }, RightKnee = { -46, 0, 0 }, RightAnkle = { -12, 0, 0 },
			} },
			{ t = 1.5, ease = { "Sine", "InOut" }, pose = {
				LeftHip = { 32, 0, -10 }, RightHip = { 30, 0, 10 }, LeftShoulder = { 48, 0, -66 },
			} },
		},
	}

	-- G: touchdown (played by Client.Ultimate when the float lands): a braced crouch, then the power stance
	local LANDED = merge(root(0, -0.95, 0), {
		LeftHip = { 66, 0, -12 }, LeftKnee = { -118, 0, 0 }, LeftAnkle = { 50, 0, 6 },
		RightHip = { 66, 0, 12 }, RightKnee = { -118, 0, 0 }, RightAnkle = { 50, 0, -6 },
		Waist = { -28, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 14, 0, 26 }, RightElbow = { 30, 0, 0 }, RightWrist = { 30, 0, 0 },
		LeftShoulder = { 58, 0, -24 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { -30, 0, 0 },
	})
	local STANCE = merge(LOW, {
		Waist = { 6, 0, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 22, 0, 40 }, RightElbow = { 100, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 22, 0, -40 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local OFAFlairLand = {
		length = 0.62, fadeIn = 0.05, fadeOut = 0.2,
		keys = {
			{ t = 0.06, ease = { "Quad", "Out" }, pose = LANDED },
			{ t = 0.2, ease = { "Sine", "Out" }, pose = merge(LANDED, root(0, -1.0, 0), { Waist = { -30, 0, 0 } }) },
			{ t = 0.38, ease = { "Back", "Out" }, pose = STANCE },
			{ t = 0.5, ease = { "Sine", "InOut" }, pose = merge(STANCE, { Waist = { 8, 0, 0 }, Neck = { 14, 0, 0 } }) },
		},
	}

	return { OFACharge = OFACharge, OFASmash = OFASmash, OFAFloat = OFAFloat, OFAFlairLand = OFAFlairLand }
end
