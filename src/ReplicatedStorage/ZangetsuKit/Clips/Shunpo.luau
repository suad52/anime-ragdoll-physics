--!nocheck
-- ZangetsuKit.Clips.Shunpo (owner: shunpo): the E - SHUNPO clips (DESIGN §7.3, FLAIR pass). Returns function(H) -> {
--   Shunpo / ShunpoBankai          the performance (ShunpoBankai = the same keys, played while the Bankai form shows)
--   ShunpoFlourish / ShunpoFlourishBankai   the overhead twirl + the hand-back to the carry: RIGHT ARM + SwordGrip
--                                  only, so he walks again while the blade spins over his head
--   ShunpoAfterimages              NOT played: one full-body slash pose per key; Client.Shunpo FK-poses each path
--                                  afterimage in a different one (the chain of cuts he left along the path) }
-- Server beats (Config.Shunpo): DepartAt 0.26 (he vanishes), ArriveAt 0.46 (he reappears behind them, back turned),
-- CutAt 1.12 (everything he passed bursts). clip.strikeAt = 1.12 = the CHIBURI SNAP key, on the server's cut.
-- Signs (Clips header): flexion +X (knee -X), Waist -X leans forward, +Y turns left, right limb out Z+, left out Z-,
-- Root pos -Y crouches / +Z back, Root rx -X pitches forward. SwordGrip {x, roll (H.EDGE), z}.
-- Every key names the whole right arm + SwordGrip. The main clip hands off at 1.52 to the flourish (the arm raised for
-- the twirl, legs at STAND); the flourish's last key is H.CARRY_SK / H.CARRY_BK (the carry overlay takes over).
-- FK-checked on the preview rig at x 7500: sword tip >= 0.3 above the floor on every key and between the flourish
-- keys, planted soles within 0.25 on every grounded key, no limb or blade through the torso/head, elbows 0..150,
-- knees -150..0.
return function(H)
	local merge, EDGE = H.merge, H.EDGE
	local WIDE, STAND, RELAX = H.WIDE, H.STAND, H.RELAX
	local function arm(sh, el, wr, grip)
		return { RightShoulder = sh, RightElbow = { el, 0, 0 }, RightWrist = wr or { 0, 0, 0 }, SwordGrip = grip }
	end
	local function lroot(x, y, z, rx, ry, rz)
		return { Root = { rx or 0, ry or 0, rz or 0, pos = Vector3.new(x, y, z) } }
	end

	-- 0.12 CROUCH-DRAW: split stance sunk low, chest forward and turned a touch right, the cleaver comes off the
	-- shoulder and is held low and back behind his right hip, the left hand reaching forward
	local DRAW = merge(WIDE, lroot(0, -0.78, 0.2, -4, 0, 0), {
		Waist = { -24, -10, 0 }, Neck = { 16, 8, 0 },
		LeftShoulder = { 62, 0, -8 }, LeftElbow = { 28, 0, 0 }, LeftWrist = { -10, 0, 0 },
	}, arm({ -20, 0, 30 }, 20, { 0, 0, 0 }, { -60, EDGE.BACK, 0 }))
	-- the coil trembles (power gathering into the blade) 0.147 / 0.173 / 0.20
	local COIL = H.tremble(0.12, 0.20, 3, DRAW, { Waist = true, Neck = true, RightShoulder = true, LeftShoulder = true }, 1.6)
	-- 0.225 the release sweep: the blade whips out level to his right on its way forward (a back -> forward swing
	-- straight from DRAW to LAUNCH would pass the tip through the floor). The edge stays BACK, like DRAW and LAUNCH,
	-- and the blade rides 10 deg below level: a roll change (or a lower blade) across this 0.025 s key pair slerped
	-- the tip under the floor at 0.230 (checked at 9 points between every key pair)
	local SWEEP = merge(DRAW, lroot(0, -0.78, 0, -10, 0, 0), { Waist = { -20, 0, 0 } },
		arm({ 4, -24, 80 }, 6, { 0, 0, 0 }, { -10, EDGE.BACK, 0 }))

	-- 0.25 LAUNCH: the lunge off the back foot (the pose the start afterimage keeps): pitched forward, front knee
	-- driving, back leg extended, the blade sweeping forward-low past his right knee
	local LAUNCH = merge(lroot(0, -0.78, -0.35, -16, 0, 0), {
		LeftHip = { 78, 0, -14 }, LeftKnee = { -96, 0, 0 }, LeftAnkle = { 30, 0, 0 },
		RightHip = { -44, 0, 14 }, RightKnee = { -14, 0, 0 }, RightAnkle = { 52, 0, 0 },
		Waist = { -18, 6, 0 }, Neck = { 24, 0, 0 },
		LeftShoulder = { -36, 0, -22 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}, arm({ 30, 0, 50 }, 10, { 0, 0, 0 }, { 70, EDGE.BACK, 0 }))

	-- (0.26 - 0.46 he is vanished: LAUNCH eases straight into ARRIVE; the start afterimage keeps LAUNCH)

	-- 0.46 ARRIVE (H.AFTERCUT + a skid crouch): back to them, sword arm out to the right, blade level and a little back
	local ARRIVE = merge(H.AFTERCUT, lroot(0, -0.75, 0.15, 0, 0, 0))
	local SETTLE = merge(H.AFTERCUT, lroot(0, -0.7, 0.15, 0, 0, 0))

	-- the silent breath (the money pose, held): tiny drift (chest rises and sinks, the blade dips 3 deg and back)
	local BREATH_A = merge(SETTLE, { Waist = { -4, 17, 0 }, Neck = { 5, -11, 0 } },
		arm({ 6, -20, 79 }, 6, { 0, 0, 0 }, { -13, EDGE.BACK, 0 }))
	local BREATH_B = merge(SETTLE, { Waist = { -7, 18, 0 }, Neck = { 3, -10, 0 } },
		arm({ 6, -20, 81 }, 6, { 0, 0, 0 }, { -10, EDGE.BACK, 0 }))

	-- 1.02 the chiburi lift: the blade rises 12 deg and the wrist turns over (edge forward), cocked to flick
	local LIFT = merge(SETTLE, { Waist = { -4, 20, 0 }, Neck = { 6, -12, 0 } },
		arm({ 10, -20, 92 }, 10, { 0, 0, 0 }, { 8, EDGE.RISE, 0 }))

	-- 1.12 CHIBURI SNAP (strikeAt, on the server cut): the blade flicks down and out to his right side (22 deg below
	-- level, edge DOWN = leading the flick; with the arm out sideways that roll is EDGE.FORE), shoulders drop
	local SNAP = merge(WIDE, lroot(0, -0.72, 0.15, 0, 0, 0), {
		Waist = { -10, 14, 0 }, Neck = { 2, -8, 0 },
		LeftShoulder = { 14, 0, -24 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}, arm({ 15, -10, 70 }, 8, { 0, 0, 0 }, { 0, EDGE.FORE, 0 }))
	local OVER = merge(SNAP, { Waist = { -12, 12, 0 } }, arm({ 13, -10, 66 }, 6, { 0, 0, 0 }, { -4, EDGE.FORE, 0 }))
	local HOLD = merge(SNAP, { Waist = { -11, 13, 0 } }, arm({ 14, -10, 68 }, 7, { 0, 0, 0 }, { -2, EDGE.FORE, 0 }))

	-- 1.44 straighten: chest square, the head turns back over his shoulder toward them
	local LOOK = merge(STAND, RELAX, { Waist = { -3, 6, 0 }, Neck = { 0, 30, 0 } },
		arm({ 15, -10, 60 }, 12, { 0, 0, 0 }, { 0, EDGE.FORE, 0 }))

	-- the overhead twirl: arm straight up, the blade level above his head; RightWrist Y spins it a full turn in 90-degree
	-- steps (each step is exactly 90 so the interpolation can only turn one way)
	local function tw(deg)
		return arm({ 170, 0, 6 }, 12, { 0, deg, 0 }, { 90, EDGE.FORE, 0 })
	end
	-- 1.52 HAND-OFF: standing, chin up toward the blade, the cleaver raised overhead for the twirl
	local HANDOFF = merge(STAND, RELAX, { Waist = { -2, 4, 0 }, Neck = { 10, 14, 0 } }, tw(0))
	-- Shikai: the blade comes down from overhead behind his head onto the shoulder
	local BEHIND = arm({ 118, 0, 14 }, 78, { 0, 0, 0 }, { 86, EDGE.CHOP, 0 })
	-- Bankai: the arm comes down out to his right side with the slim blade ALREADY trailing behind him, then lowers
	-- into the low trailing carry (any path where the blade points down on the way passes the tip through the floor:
	-- the old swing-down dipped 0.58 under it; this one stays >= 1.9 above it the whole way)
	local DOWN_BK = arm({ 20, 0, 70 }, 20, { 0, 0, 0 }, { -95, 0, -10 })

	local function main()
		local k = {
			{ t = 0.12, ease = { "Quad", "Out" }, pose = DRAW },
		}
		for _, key in ipairs(COIL) do
			table.insert(k, key)
		end
		for _, key in ipairs({
			{ t = 0.225, ease = { "Quad", "Out" }, pose = SWEEP },
			{ t = 0.25, ease = { "Exponential", "Out" }, pose = LAUNCH },
			{ t = 0.46, ease = { "Back", "Out" }, pose = ARRIVE },
			{ t = 0.56, ease = { "Sine", "Out" }, pose = SETTLE },
			{ t = 0.70, ease = { "Sine", "InOut" }, pose = BREATH_A },
			{ t = 0.88, ease = { "Sine", "InOut" }, pose = BREATH_B },
			{ t = 1.02, ease = { "Quad", "Out" }, pose = LIFT },
			{ t = 1.12, ease = { "Exponential", "Out" }, pose = SNAP },
			{ t = 1.18, ease = { "Back", "Out" }, pose = OVER },
			{ t = 1.34, ease = { "Sine", "InOut" }, pose = HOLD },
			{ t = 1.44, ease = { "Sine", "InOut" }, pose = LOOK },
			{ t = 1.52, ease = { "Quad", "Out" }, pose = HANDOFF },
		}) do
			table.insert(k, key)
		end
		return k
	end
	local function flourish(last, lastPose, lastEase)
		return {
			{ t = 0.02, ease = { "Quad", "Out" }, pose = tw(0) },
			{ t = 0.07, ease = { "Linear", "Out" }, pose = tw(90) },
			{ t = 0.12, ease = { "Linear", "Out" }, pose = tw(180) },
			{ t = 0.17, ease = { "Linear", "Out" }, pose = tw(270) },
			{ t = 0.22, ease = { "Quad", "Out" }, pose = tw(360) },
			{ t = 0.32, ease = { "Quad", "InOut" }, pose = last },
			{ t = 0.44, ease = lastEase, pose = lastPose },
		}
	end

	-- the afterimage poses (never played): each path afterimage is FK-posed in one of these, in order, so the chain he
	-- leaves along the path reads as a flurry of different cuts. All grounded (planted soles), tip >= 0.3.
	local RISE_HI = merge(WIDE, { -- the rising cut, finished high on his left: blade up-left, chest opened left
		Waist = { 4, 26, 0 }, Neck = { 6, -18, 0 },
		LeftShoulder = { -20, 0, -36 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}, arm({ 150, 0, -14 }, 10, { 0, 0, 0 }, { 14, EDGE.RISE, 0 }))
	local LOW_SWEEP = merge(WIDE, { -- a flat sweep finished low across his left
		Waist = { -20, 34, 0 }, Neck = { 10, -24, 0 },
		LeftShoulder = { -30, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}, arm({ 84, 20, -20 }, 6, { 0, 0, 0 }, { 16, EDGE.FORE, 0 }))
	local AFTERIMAGES = { H.RELEASE, H.AFTERCUT, H.RAISE, RISE_HI, H.BANKAI_POSE, LOW_SWEEP }
	local poseKeys = {}
	for i, p in ipairs(AFTERIMAGES) do
		table.insert(poseKeys, { t = i * 0.1, ease = { "Linear", "Out" }, pose = p })
	end

	return {
		Shunpo = { length = 1.58, fadeIn = 0.06, fadeOut = 0.08, strikeAt = 1.12, handoffAt = 1.52, keys = main() },
		ShunpoBankai = { length = 1.58, fadeIn = 0.06, fadeOut = 0.08, strikeAt = 1.12, handoffAt = 1.52, keys = main() },
		ShunpoFlourish = { length = 0.5, fadeIn = 0.04, fadeOut = 0.06, keys = flourish(BEHIND, H.CARRY_SK, { "Back", "Out" }) },
		ShunpoFlourishBankai = { length = 0.5, fadeIn = 0.04, fadeOut = 0.06, keys = flourish(DOWN_BK, H.CARRY_BK, { "Quad", "Out" }) },
		ShunpoAfterimages = { length = 0.7, poses = AFTERIMAGES, keys = poseKeys },
	}
end
