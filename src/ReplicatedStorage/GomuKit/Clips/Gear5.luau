--!nocheck
-- GomuKit.Clips pass "Gear5" (owner gear5): G - GEAR FIFTH + BAJRANG GUN + the mode's idle bounce.
--   Gear5_Awaken  (cast 0 -> 2.4 = Gear5.Lock) four heartbeat jolts on DrumAt {0, .32, .64, .9}: each a Back-Out JOLT
--     (chest thrown out, chin up, shoulders back, the root popping up) and a SLUMP (head hanging, arms dangling, knees
--     giving); 1.05 the BRACE (deep crouch, arms crossed over the chest); 1.15 the BURST (Expo Out: arms flung wide and
--     up, head back, up on his toes); 1.5 the LAUGH (leaning back, hands on the belly) shaking; 2.0 a cartoon hop;
--     2.18 the squash landing; 2.4 rest
--   Gear5_Bajrang (cast 0 -> 1.9 = Bajrang.Lock) 0.06 the crouch; 0.18 the hop with the right arm thrown up at the sky,
--     legs tucked; 0.55 / 0.82 arching back under the forming fist; 0.98 the YANK: the arm hauled down and forward, the
--     body crunching, root pitched forward; 1.25 the slam; 1.45-1.65 impact tremble; 1.9 rest
--   Gear5_Bounce  (0.8, the mode's idle overlay) squash -> a cartoon pop up -> settle
-- Signs (base header): shoulder flexion +X, right limb out Z+, left out Z-, Waist -X = forward lean, Neck +X = chin up,
-- knee flexion -X, Root pos -Y = crouch, Root -X pitches forward. Every key pair on one axis stays < 180 deg apart.
-- Legs reuse the base's FK-verified STAND / LOW / CROUCH; the airborne keys tuck the legs freely. NOT FK-checked on a rig.
return function(H)
	local merge, seq, tremble, key = H.merge, H.seq, H.tremble, H.key
	local STAND, LOW, CROUCH, REST, SKY = H.STAND, H.LOW, H.CROUCH, H.REST, H.SKY
	local RELAX, RELAX_R = H.RELAX, H.RELAX_R
	local V = Vector3.new

	---------------------------------------------------------------------------------------------------
	-- Gear5_Awaken
	local JOLT = merge(STAND, {
		Root = { 0, 0, 0, pos = V(0, 0.3, 0) },
		Waist = { 16, 0, 0 }, Neck = { 22, 0, 0 },
		RightShoulder = { -25, 0, 28 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -25, 0, -28 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SLUMP = merge(LOW, {
		Waist = { -18, 0, 0 }, Neck = { -24, 0, 0 },
		RightShoulder = { 12, 0, 6 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 12, 0, -6 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local BRACE = merge(CROUCH, {
		Waist = { -24, 0, 0 }, Neck = { -14, 0, 0 },
		RightShoulder = { 80, 0, -30 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 80, 0, 30 }, LeftElbow = { 120, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local BURST = merge(STAND, {
		Root = { 0, 0, 0, pos = V(0, 0.35, 0) }, LeftHip = { 0, 0, -14 }, RightHip = { 0, 0, 14 },
		Waist = { 20, 0, 0 }, Neck = { 32, 0, 0 },
		RightShoulder = { 30, 0, 125 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, -125 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local BURST2 = merge(BURST, {
		Root = { 0, 0, 0, pos = V(0, 0.25, 0) }, Neck = { 28, 0, 0 },
		RightShoulder = { 26, 0, 118 }, LeftShoulder = { 26, 0, -118 },
	})
	local LAUGH = merge(STAND, {
		Root = { 0, 0, 0, pos = V(0, 0, 0.15) },
		Waist = { 24, 0, 0 }, Neck = { 34, 0, 0 },
		RightShoulder = { 35, 0, 25 }, RightElbow = { 95, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 35, 0, -25 }, LeftElbow = { 95, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local HOP = merge(STAND, {
		Root = { 0, 0, 0, pos = V(0, 0.8, 0) },
		LeftHip = { 40, 0, -8 }, RightHip = { 40, 0, 8 }, LeftKnee = { -70, 0, 0 }, RightKnee = { -70, 0, 0 },
		Waist = { 6, 0, 0 }, Neck = { 14, 0, 0 },
		RightShoulder = { 60, 0, 60 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 60, 0, -60 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SQUASH = merge(CROUCH, {
		Waist = { -10, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 20, 0, 50 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -50 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local REST_G = merge(REST, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })
	local LAUGH_SHAKE = { Waist = true, Neck = true, RightShoulder = true, LeftShoulder = true }

	local Gear5_Awaken = {
		length = 2.4, fadeIn = 0.05, fadeOut = 0.15,
		keys = seq(
			{
				key(0.04, JOLT, "Back", "Out"), key(0.20, SLUMP, "Quad", "Out"),
				key(0.36, JOLT, "Back", "Out"), key(0.52, SLUMP, "Quad", "Out"),
				key(0.68, JOLT, "Back", "Out"), key(0.82, SLUMP, "Quad", "Out"),
				key(0.94, JOLT, "Back", "Out"),
				key(1.05, BRACE, "Quad", "In"),
				key(1.17, BURST, "Exponential", "Out"),
				key(1.38, BURST2, "Sine", "InOut"),
				key(1.52, LAUGH, "Back", "Out"),
			},
			tremble(1.52, 1.9, 6, LAUGH, LAUGH_SHAKE, 4),
			{
				key(2.02, HOP, "Quad", "Out"),
				key(2.18, SQUASH, "Quad", "In"),
				key(2.4, REST_G, "Back", "Out"),
			}
		),
	}

	---------------------------------------------------------------------------------------------------
	-- Gear5_Bajrang
	local CROUCH_B = merge(CROUCH, {
		Waist = { -14, 0, 0 }, Neck = { 8, 0, 0 },
		RightShoulder = { 10, 0, 24 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -20, 0, -20 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local REACH = merge(SKY, {
		Root = { 0, 0, 0, pos = V(0, 0.2, 0) },
		LeftHip = { 45, 0, -8 }, RightHip = { 30, 0, 8 }, LeftKnee = { -80, 0, 0 }, RightKnee = { -50, 0, 0 },
		LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
	})
	local ARCH = merge(REACH, {
		Waist = { 22, 0, 0 }, Neck = { 36, 0, 0 },
		LeftShoulder = { 30, 0, -85 }, LeftElbow = { 20, 0, 0 },
	})
	local ARCH2 = merge(ARCH, {
		Waist = { 26, 0, 0 }, Neck = { 40, 0, 0 }, RightShoulder = { 172, 0, 4 },
		LeftHip = { 55, 0, -8 }, RightHip = { 50, 0, 8 }, LeftKnee = { -95, 0, 0 }, RightKnee = { -90, 0, 0 },
	})
	local YANK = merge(STAND, {
		Root = { -16, 0, 0, pos = V(0, 0.1, 0) },
		LeftHip = { 70, 0, -8 }, RightHip = { 70, 0, 8 }, LeftKnee = { -100, 0, 0 }, RightKnee = { -100, 0, 0 },
		Waist = { -28, 0, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { 115, 0, 12 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -70 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SLAM = merge(YANK, {
		Root = { -20, 0, 0, pos = V(0, 0, 0) }, Waist = { -34, 0, 0 }, RightShoulder = { 70, 0, 14 },
	})
	local SLAM_SHAKE = { Waist = true, Neck = true, RightShoulder = true }

	local Gear5_Bajrang = {
		length = 1.9, fadeIn = 0.06, fadeOut = 0.2,
		keys = seq(
			{
				key(0.06, CROUCH_B, "Quad", "Out"),
				key(0.18, REACH, "Back", "Out"),
				key(0.55, ARCH, "Sine", "InOut"),
				key(0.82, ARCH2, "Quad", "InOut"),
				key(0.98, YANK, "Back", "Out"),
				key(1.25, SLAM, "Quad", "In"),
				key(1.45, SLAM, "Quad", "Out"),
			},
			tremble(1.45, 1.65, 4, SLAM, SLAM_SHAKE, 3),
			{ key(1.9, REST_G, "Quad", "Out") }
		),
	}

	---------------------------------------------------------------------------------------------------
	-- Gear5_Bounce: the mode's idle overlay (played by Client.Gear5 while he stands still)
	local B_SQ = merge(LOW, RELAX, RELAX_R, { Waist = { -6, 0, 0 }, Neck = { 4, 0, 0 } })
	local B_POP = merge(STAND, {
		Root = { 0, 0, 0, pos = V(0, 0.5, 0) }, Waist = { 6, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 20, 0, 40 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local Gear5_Bounce = {
		length = 0.8, fadeIn = 0.12, fadeOut = 0.15,
		keys = {
			key(0.18, B_SQ, "Quad", "Out"),
			key(0.42, B_POP, "Back", "Out"),
			key(0.62, merge(STAND, RELAX, RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } }), "Quad", "In"),
			key(0.8, REST_G, "Sine", "Out"),
		},
	}

	return { Gear5_Awaken = Gear5_Awaken, Gear5_Bajrang = Gear5_Bajrang, Gear5_Bounce = Gear5_Bounce }
end
