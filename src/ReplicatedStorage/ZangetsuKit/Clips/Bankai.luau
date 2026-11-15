--!nocheck
-- ZangetsuKit.Clips pass "Bankai" (owner bankai): G, BANKAI -> TENSA ZANGETSU (DESIGN.md §9.3). Cast times come from
-- Config.Bankai (FLAIR PASS: KaiAt 0.62, EruptAt 1.18, FormAt 1.42, RevealAt 2.15, ModeAt 2.75, Lock 3.15):
--   BankaiCharge  played at cast 0.00 (length 1.20)
--     0.10 the cleaver sweeps off the shoulder out to his right; 0.22 BANKAI_POSE (Back overshoot): sword arm straight
--     out, blade level, the left hand clamping the forearm; 0.22-0.58 straining (5 tremble keys); 0.62 KAI: a jolt -
--     chest drops, chin up, the knees sink (root -0.8, feet re-solved to stay planted); 0.62-1.08 shaking harder inside
--     the tornado (8 keys, amp 2.2 -> 3.5, the blade itself shuddering in the grip); 1.15 the brace before the burst
--     (shoulders up, head down, root -0.9)
--   BankaiReveal  played at cast 1.18 (length 1.97, ends 3.15 = Lock)
--     0.02 the blast pose (Exponential Out): arms flung wide, head back, the blade out wide; 0.24 (= FormAt) / 0.50
--     drifting inside the pillar while the coat and Tensa Zangetsu appear; 0.84 the gather (the blade drawn up across his
--     body); 0.97 REVEAL (Back Out, cast 2.15): Tensa Zangetsu held out low at his side pointing down-out, chin up, the
--     left hand loose; 1.12 / 1.28 breathing in the held reveal (0.31 s money pose); 1.40 the blade lifts; 1.50 CHIBURI
--     (Back Out): the flick that shakes the blade clean; 1.72 the blade settles back; 1.97 REST_BK
--   BankaiExit    played when the mode expires (length 1.05; upper body only, so he can walk through it)
--     0.10 he exhales, shoulders drop, head bows; 0.24 / 0.36 the black blade swings up before his face; 0.43 he looks at
--     it as it cracks; 0.50 the reform flash: a flinch (the server swaps back to Shikai at 0.45); 0.74 the cleaver lands on
--     his shoulder (overshoot); 0.88 a shrug; 1.05 the carry (CARRY_SK)
-- BankaiCharge ends on the brace instead of CARRY_SK on purpose: BankaiReveal always takes over at 1.18 (a carry key
-- there would yank the arm for two frames); a cancelled charge is stopped with a 0.2 s fade back to the carry.
-- Every key FK-checked on the preview rig (Zangetsu_bankai_Rig at x 7700): sword tip >= 0.3 above the floor on every key
-- and between keys (easing overshoot included), planted soles within 0.25, no arm/leg through the torso or head, elbows
-- 0..150, knees -150..0.
return function(H)
	local merge, seq, root, tremble, EDGE = H.merge, H.seq, H.root, H.tremble, H.EDGE
	local WIDE, STAND, RELAX = H.WIDE, H.STAND, H.RELAX
	local CARRY_SK, CARRY_BK, REST, REST_BK = H.CARRY_SK, H.CARRY_BK, H.REST, H.REST_BK
	local BANKAI_POSE = H.BANKAI_POSE

	-- WIDE with the root sunk deeper / raised, legs re-solved so both soles stay where WIDE plants them
	local WIDE_K = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.8, 0.15) },
		LeftHip = { 64, 0, -16 }, LeftKnee = { -111.5, 0, 0 }, LeftAnkle = { 48, 0, 0 },
		RightHip = { -41, 0, 16 }, RightKnee = { -24.5, 0, 0 }, RightAnkle = { 72, 0, 0 },
	}
	local WIDE_B = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.9, 0.15) },
		LeftHip = { 68, 0, -16 }, LeftKnee = { -117.6, 0, 0 }, LeftAnkle = { 51, 0, 0 },
		RightHip = { -34, 0, 16 }, RightKnee = { -42, 0, 0 }, RightAnkle = { 82, 0, 0 },
	}
	local WIDE_U = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0.15) },
		LeftHip = { 52, 0, -16 }, LeftKnee = { -90.6, 0, 0 }, LeftAnkle = { 38, 0, 0 },
		RightHip = { -36, 0, 16 }, RightKnee = { -19.5, 0, 0 }, RightAnkle = { 58, 0, 0 },
	}

	---------------------------------------------------------------------------------------------------
	-- BankaiCharge
	-- 0.10: the cleaver leaves the shoulder, swept out to his right, edge forward, the chest opening right
	local SWEEP = merge(WIDE, {
		Waist = { -4, -22, 0 }, Neck = { 2, 16, 0 },
		RightShoulder = { 40, 0, 70 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, -24 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 30, EDGE.FORE, 0 },
	})
	-- 0.62 KAI: the jolt - chest drops 4 deg, chin up 14, the knees sink
	local KAI = merge(BANKAI_POSE, WIDE_K, {
		Waist = { -8, -14, 0 }, Neck = { 18, 10, 0 },
		RightShoulder = { 88, 0, -2 }, RightElbow = { 4, 0, 0 },
	})
	-- 1.15: the brace before the burst - shoulders hunched up, head down, sunk lower still
	local BRACE = merge(BANKAI_POSE, WIDE_B, {
		Waist = { -14, -12, 0 }, Neck = { -6, 8, 0 },
		RightShoulder = { 96, 0, -4 }, RightElbow = { 6, 0, 0 },
		LeftShoulder = { 114, -40, 72 }, LeftElbow = { 34, 0, 0 },
	})
	local STRAIN = { Waist = true, Neck = true, RightShoulder = true, LeftShoulder = true }
	-- (the blade shudders in the grip too: SwordGrip is in the KAI shake set)
	local SHAKE = { Waist = true, Neck = true, RightShoulder = true, RightElbow = true, LeftShoulder = true, SwordGrip = true }
	local BankaiCharge = {
		length = 1.20, fadeIn = 0.1, fadeOut = 0.02, strikeAt = 1.18, -- the eruption (no strike key: it is radial)
		keys = seq(
			{
				{ t = 0.10, ease = { "Quad", "Out" }, pose = SWEEP },
				{ t = 0.22, ease = { "Back", "Out" }, pose = BANKAI_POSE },
			},
			tremble(0.22, 0.58, 5, BANKAI_POSE, STRAIN, 1.5),
			{ { t = 0.62, ease = { "Back", "Out" }, pose = KAI } },
			tremble(0.62, 0.86, 4, KAI, SHAKE, 2.2),
			tremble(0.86, 1.08, 4, KAI, SHAKE, 3.5),
			{ { t = 1.15, ease = { "Quad", "In" }, pose = BRACE } }
		),
	}

	---------------------------------------------------------------------------------------------------
	-- BankaiReveal (cast 1.18 -> 3.15)
	-- 0.02: the blast - arms flung wide and up, chest thrown back, head back, the blade out wide continuing the arm
	local BLAST = merge(WIDE_U, {
		Waist = { 14, 0, 0 }, Neck = { 28, 0, 0 },
		RightShoulder = { 30, 0, 100 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, -100 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -20, 0, 0 },
		SwordGrip = { 10, EDGE.FORE, 0 },
	})
	-- 0.24 / 0.50: hanging in the column while it rages (the coat and the black blade appear at 0.24)
	local DRIFT1 = merge(BLAST, {
		Waist = { 12, 4, 0 }, Neck = { 24, 4, 0 },
		RightShoulder = { 26, 0, 96 }, LeftShoulder = { 26, 0, -94 }, LeftWrist = { -24, 0, 0 },
		SwordGrip = { 6, EDGE.FORE, 0 },
	})
	local DRIFT2 = merge(WIDE, {
		Waist = { 6, 0, 0 }, Neck = { 14, 0, 0 },
		RightShoulder = { 22, 0, 84 }, RightElbow = { 14, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -80 }, LeftElbow = { 16, 0, 0 }, LeftWrist = { -14, 0, 0 },
		SwordGrip = { 0, -60, 0 },
	})
	-- 0.84: the gather - the blade drawn up across in front of him, the chest turning in (anticipation for the cut down)
	local GATHER = merge(WIDE, {
		Waist = { -2, 14, 0 }, Neck = { 2, -10, 0 },
		RightShoulder = { 70, 0, 30 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 18, 0, -20 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 30, -30, 14 },
	})
	-- 0.97 REVEAL: Tensa Zangetsu held out low at his side pointing down-out, chin up, the left hand loose
	-- (the arm out 55 deg and the blade 20 deg below level: as steep as a 4.3-stud blade can point from a waist-high
	-- hand without touching the floor; tip 1.4 above it)
	local REVEAL = merge(WIDE_U, RELAX, {
		Waist = { -6, -10, 0 }, Neck = { 8, 8, 0 },
		RightShoulder = { 15, 0, 55 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 18, 0, -6 },
	})
	local BREATH1 = merge(REVEAL, {
		Waist = { -4, -10, 0 }, Neck = { 10, 8, 0 }, RightShoulder = { 16, 0, 56 }, LeftShoulder = { 12, 0, -16 },
	})
	local BREATH2 = merge(REVEAL, {
		Waist = { -6, -11, 0 }, Neck = { 9, 9, 0 }, RightShoulder = { 15, 0, 54 },
	})
	-- 1.40 / 1.50: the chiburi - the blade lifts, then flicks down-out hard (Back overshoot) to shake it clean
	local CHIBURI_UP = merge(REVEAL, {
		Waist = { -4, -14, 0 }, Neck = { 6, 10, 0 },
		RightShoulder = { 34, 0, 48 }, RightElbow = { 44, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 46, 0, -6 },
	})
	local CHIBURI = merge(REVEAL, {
		Waist = { -7, -8, 0 }, Neck = { 8, 6, 0 },
		RightShoulder = { 14, 0, 58 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 16, 0, -6 },
	})
	-- 1.72: the blade settles back toward the low trailing carry (out and back, level)
	local SETTLE = merge(WIDE_U, RELAX, {
		Waist = { -5, -4, 0 }, Neck = { 4, 4, 0 },
		RightShoulder = { 10, 0, 30 }, RightElbow = { 14, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { -75, 0, -27 },
	})
	local BankaiReveal = {
		length = 1.97, fadeIn = 0.02, fadeOut = 0.12, strikeAt = 0.97, -- the reveal pose (no hit); chiburi at 1.50
		keys = {
			{ t = 0.02, ease = { "Exponential", "Out" }, pose = BLAST },
			{ t = 0.24, ease = { "Sine", "Out" }, pose = DRIFT1 },
			{ t = 0.50, ease = { "Sine", "InOut" }, pose = DRIFT2 },
			{ t = 0.84, ease = { "Quad", "InOut" }, pose = GATHER },
			{ t = 0.97, ease = { "Back", "Out" }, pose = REVEAL },
			{ t = 1.12, ease = { "Sine", "InOut" }, pose = BREATH1 },
			{ t = 1.28, ease = { "Sine", "InOut" }, pose = BREATH2 },
			{ t = 1.40, ease = { "Quad", "Out" }, pose = CHIBURI_UP },
			{ t = 1.50, ease = { "Back", "Out" }, pose = CHIBURI },
			{ t = 1.72, ease = { "Quad", "InOut" }, pose = SETTLE },
			{ t = 1.97, ease = { "Sine", "Out" }, pose = REST_BK },
		},
	}

	---------------------------------------------------------------------------------------------------
	-- BankaiExit (mode end): upper body + sword only, so the walk keeps animating the legs
	local function upper(t)
		return merge({ Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }, RELAX, t)
	end
	local EXHALE = upper(merge(CARRY_BK, {
		Waist = { -10, 0, 0 }, Neck = { -16, 0, 0 },
		RightShoulder = { 4, 0, 14 }, LeftShoulder = { 4, 0, -10 }, LeftElbow = { 18, 0, 0 },
	}))
	-- the blade stays level behind him while the hand comes up (a straight lerp from the low carry would drag the tip
	-- through the floor), then sweeps up over his shoulder
	local LIFT = upper({
		Waist = { -6, -4, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { 30, 0, 20 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { -152, EDGE.RISE, -14 },
	})
	local SWING = upper({
		Waist = { -2, -10, 0 }, Neck = { 6, 10, 0 },
		RightShoulder = { 80, 0, 22 }, RightElbow = { 60, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 58, EDGE.RISE, -14 },
	})
	-- 0.43: he looks at the blade as it cracks (head turned to it, the blade held up before him)
	local LOOK = upper({
		Waist = { -2, -12, 0 }, Neck = { 10, 14, 0 },
		RightShoulder = { 84, 0, 22 }, RightElbow = { 66, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 54, EDGE.RISE, -16 },
	})
	local FLINCH = upper({
		Waist = { 6, -6, 0 }, Neck = { -8, 4, 0 },
		RightShoulder = { 110, 0, 18 }, RightElbow = { 80, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -30 }, LeftElbow = { 40, 0, 0 },
		SwordGrip = { 26, EDGE.BACK, 14 },
	})
	local LAND = upper({
		Waist = { -6, 0, 0 }, Neck = { 2, 0, 0 },
		RightShoulder = { 60, 0, 12 }, RightElbow = { 132, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 86, EDGE.CHOP, 0 },
	})
	-- 0.88: the shrug - the cleaver settles on the shoulder, chin up again
	local SHRUG = upper({
		Waist = { -3, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 57, 0, 12 }, RightElbow = { 131, 0, 0 }, RightWrist = { 0, 0, 0 },
		SwordGrip = { 82, EDGE.CHOP, 0 },
	})
	local BankaiExit = {
		length = 1.05, fadeIn = 0.1, fadeOut = 0.15,
		keys = {
			{ t = 0.10, ease = { "Sine", "Out" }, pose = EXHALE },
			{ t = 0.24, ease = { "Sine", "InOut" }, pose = LIFT },
			{ t = 0.36, ease = { "Quad", "Out" }, pose = SWING },
			{ t = 0.43, ease = { "Sine", "InOut" }, pose = LOOK },
			{ t = 0.50, ease = { "Back", "Out" }, pose = FLINCH },
			{ t = 0.74, ease = { "Back", "Out" }, pose = LAND },
			{ t = 0.88, ease = { "Sine", "InOut" }, pose = SHRUG },
			{ t = 1.05, ease = { "Sine", "InOut" }, pose = upper(CARRY_SK) },
		},
	}

	return { BankaiCharge = BankaiCharge, BankaiReveal = BankaiReveal, BankaiExit = BankaiExit }
end
