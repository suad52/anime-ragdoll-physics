--!nocheck
-- Flair pass, passive + mode clips (OneForAllKit.Clips child). Replaces AirStep and Burnout; adds AirStepSpin (the
-- second step of the 100% mode) and BurnoutArm (the upper body of the burnout, which outlives the legs so he can walk
-- out of it while still shaking the arm). Signs: flexion +X, knee flexion -X, forward lean Waist -X, +Y turns left,
-- right limb out Z+, left limb out Z-, Neck +X lifts the chin; Root -X pitches forward, +Y yaws left, +Z rolls.
-- Root pos -Y crouches, +Z slides back.
return function(H)
	local merge, seq, root, tremble = H.merge, H.seq, H.root, H.tremble
	local LOW, RELAX = H.LOW, H.RELAX
	local out = {}

	-- the flip turns about the body's middle, not the hip pivot: a root pitch of `deg` is paired with the offset
	-- that holds a point C studs above the pivot still (+ `lift`, so the inverted body never dips under the feet)
	local C = 0.7
	local function flip(deg, lift, extra)
		local a = math.rad(deg)
		local y = C * (1 - math.cos(a)) + (lift or 0)
		local z = -C * math.sin(a)
		return merge({ Root = { deg, 0, 0, pos = Vector3.new(0, y, z) } }, extra or {})
	end
	local TUCK = {
		Waist = { -28, 0, 0 }, Neck = { -22, 0, 0 },
		RightShoulder = { 78, 0, 22 }, RightElbow = { 96, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 78, 0, -22 }, LeftElbow = { 96, 0, 0 }, LeftWrist = { 10, 0, 0 },
		LeftHip = { 100, 0, -8 }, LeftKnee = { -134, 0, 0 }, LeftAnkle = { 24, 0, 0 },
		RightHip = { 98, 0, 8 }, RightKnee = { -130, 0, 0 }, RightAnkle = { 24, 0, 0 },
	}

	-- AIR STEP: he stamps the air flat (legs drive down, arms throw up), tucks and front-flips once, and opens out
	-- into a landing-ready spread. 0.70 s (was a 0.42 s tuck)
	out.AirStep = {
		length = 0.7, fadeIn = 0.03, fadeOut = 0.14,
		keys = {
			-- the stamp: the flick that slaps the air disc under him; chest arched back, arms flung overhead
			{ t = 0.05, ease = { "Exponential", "Out" }, pose = flip(12, 0.1, {
				Waist = { 10, 0, 0 }, Neck = { 12, 0, 0 },
				RightShoulder = { 150, 0, 24 }, RightElbow = { 16, 0, 0 }, RightWrist = { -10, 0, 0 },
				LeftShoulder = { 150, 0, -24 }, LeftElbow = { 16, 0, 0 }, LeftWrist = { -10, 0, 0 },
				LeftHip = { -6, 0, -6 }, LeftKnee = { -8, 0, 0 }, LeftAnkle = { 34, 0, 0 },
				RightHip = { 18, 0, 6 }, RightKnee = { -30, 0, 0 }, RightAnkle = { 30, 0, 0 },
			}) },
			-- snaps into the tuck as the spin starts
			{ t = 0.15, ease = { "Quad", "In" }, pose = flip(-75, 0.2, merge(TUCK, {
				LeftHip = { 92, 0, -8 }, LeftKnee = { -112, 0, 0 }, RightHip = { 88, 0, 8 }, RightKnee = { -108, 0, 0 },
				RightShoulder = { 96, 0, 26 }, LeftShoulder = { 96, 0, -26 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 },
			})) },
			-- inverted, balled up tight (fastest part of the spin)
			{ t = 0.26, ease = { "Linear", "InOut" }, pose = flip(-185, 0.25, TUCK) },
			{ t = 0.37, ease = { "Linear", "InOut" }, pose = flip(-292, 0.2, merge(TUCK, {
				Neck = { -14, 0, 0 }, Waist = { -24, 0, 0 },
			})) },
			-- opening out of the flip: legs unfold under him, arms spread for balance (the follow-through)
			{ t = 0.48, ease = { "Quad", "Out" }, pose = flip(-352, 0.08, {
				Waist = { -10, 0, 0 }, Neck = { 6, 0, 0 },
				RightShoulder = { 46, 0, 64 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 40, 0, -70 }, LeftElbow = { 34, 0, 0 }, LeftWrist = { 0, 0, 0 },
				LeftHip = { 56, 0, -8 }, LeftKnee = { -70, 0, 0 }, LeftAnkle = { 14, 0, 0 },
				RightHip = { 30, 0, 8 }, RightKnee = { -48, 0, 0 }, RightAnkle = { 18, 0, 0 },
			}) },
			-- settles (overshoots the arms down a touch) into a ready fall
			{ t = 0.6, ease = { "Back", "Out" }, pose = merge(root(0, 0, 0), {
				Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 },
				RightShoulder = { 22, 0, 40 }, RightElbow = { 26, 0, 0 },
				LeftShoulder = { 18, 0, -44 }, LeftElbow = { 28, 0, 0 },
				LeftHip = { 26, 0, -6 }, LeftKnee = { -36, 0, 0 }, LeftAnkle = { 10, 0, 0 },
				RightHip = { 16, 0, 6 }, RightKnee = { -28, 0, 0 }, RightAnkle = { 10, 0, 0 },
			}) },
			{ t = 0.69, ease = { "Sine", "InOut" }, pose = merge(root(0, 0, 0), {
				Waist = { -2, 0, 0 }, LeftHip = { 14, 0, -6 }, RightHip = { 10, 0, 6 }, LeftKnee = { -22, 0, 0 }, RightKnee = { -18, 0, 0 },
				RightShoulder = { 14, 0, 30 }, LeftShoulder = { 12, 0, -32 },
			}) },
		},
	}

	-- AIR STEP 2 (100% mode only): a corkscrew. He winds the opposite way, pulls the arms across his chest and
	-- whips a full turn about his own axis with one leg tucked and one extended, then opens out. 0.66 s
	local SPIN = {
		Waist = { -6, 0, 0 }, Neck = { 4, 0, 0 },
		RightShoulder = { 30, 0, -45 }, RightElbow = { 110, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, 45 }, LeftElbow = { 110, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 92, 0, -6 }, LeftKnee = { -118, 0, 0 }, LeftAnkle = { 20, 0, 0 },
		RightHip = { 12, 0, 10 }, RightKnee = { -12, 0, 0 }, RightAnkle = { 34, 0, 0 },
	}
	out.AirStepSpin = {
		length = 0.66, fadeIn = 0.03, fadeOut = 0.14,
		keys = {
			-- wind-up: twists right, arms thrown wide, both legs stamp down
			{ t = 0.05, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.1, 0, 0, -24, 0), {
				Waist = { 6, -20, 0 }, Neck = { 8, 14, 0 },
				RightShoulder = { 70, 0, 80 }, RightElbow = { 12, 0, 0 },
				LeftShoulder = { 96, 0, -70 }, LeftElbow = { 20, 0, 0 },
				LeftHip = { -4, 0, -8 }, LeftKnee = { -10, 0, 0 }, LeftAnkle = { 34, 0, 0 },
				RightHip = { 10, 0, 8 }, RightKnee = { -22, 0, 0 }, RightAnkle = { 30, 0, 0 },
			}) },
			{ t = 0.16, ease = { "Quad", "In" }, pose = merge(root(0, 0.3, 0, 0, 96, 14), SPIN) },
			{ t = 0.27, ease = { "Linear", "InOut" }, pose = merge(root(0, 0.35, 0, 0, 212, 16), SPIN) },
			{ t = 0.38, ease = { "Linear", "InOut" }, pose = merge(root(0, 0.3, 0, 0, 318, 10), SPIN) },
			-- opens out of the turn, arms flung wide
			{ t = 0.48, ease = { "Quad", "Out" }, pose = merge(root(0, 0.1, 0, 0, 356, 0), {
				Waist = { -6, 6, 0 }, Neck = { 4, -6, 0 },
				RightShoulder = { 40, 0, 76 }, RightElbow = { 24, 0, 0 },
				LeftShoulder = { 40, 0, -76 }, LeftElbow = { 24, 0, 0 },
				LeftHip = { 48, 0, -8 }, LeftKnee = { -64, 0, 0 }, LeftAnkle = { 14, 0, 0 },
				RightHip = { 24, 0, 8 }, RightKnee = { -36, 0, 0 }, RightAnkle = { 16, 0, 0 },
			}) },
			{ t = 0.6, ease = { "Back", "Out" }, pose = merge(root(0, 0, 0), {
				Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 },
				RightShoulder = { 20, 0, 38 }, RightElbow = { 26, 0, 0 },
				LeftShoulder = { 20, 0, -38 }, LeftElbow = { 26, 0, 0 },
				LeftHip = { 22, 0, -6 }, LeftKnee = { -32, 0, 0 }, LeftAnkle = { 10, 0, 0 },
				RightHip = { 14, 0, 6 }, RightKnee = { -24, 0, 0 }, RightAnkle = { 10, 0, 0 },
			}) },
			{ t = 0.65, ease = { "Sine", "InOut" }, pose = merge(root(0, 0, 0), {
				Waist = { -2, 0, 0 }, LeftHip = { 12, 0, -6 }, RightHip = { 10, 0, 6 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -18, 0, 0 },
			}) },
		},
	}

	-- BURNOUT: the arm gives out. A jolt (the arm spasms out, head snaps back, knees buckle), he doubles over clutching
	-- the right forearm and trembles, then rises. Legs + root: 0.85 s. The upper body (BurnoutArm, played on top) runs
	-- on to 1.45 s: still clutching as he straightens, lets go, inspects the arm and shakes it out.
	local JOLT_UP = {
		Waist = { 10, -16, 0 }, Neck = { 18, 12, 0 },
		RightShoulder = { -24, 0, 42 }, RightElbow = { 18, 0, 0 }, RightWrist = { -34, 0, 0 },
		LeftShoulder = { 34, 0, -34 }, LeftElbow = { 44, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}
	local JOLT_LEGS = merge(root(0, -0.09, 0.02), { -- the knees buckle (FK: soles stay on the floor)
		LeftHip = { 24, 0, -8 }, LeftKnee = { -44, 0, 0 }, LeftAnkle = { 20, 0, 0 },
		RightHip = { 24, 0, 8 }, RightKnee = { -44, 0, 0 }, RightAnkle = { 20, 0, 0 },
	})
	local CLUTCH = { -- doubled over, the left hand locked round the right forearm held to his chest
		Waist = { -30, 12, 0 }, Neck = { -20, -14, 0 },
		RightShoulder = { 30, 0, -30 }, RightElbow = { 100, 0, 0 }, RightWrist = { 24, 0, 0 },
		LeftShoulder = { 65, 0, 80 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}
	-- the kit's LOW crouch with the root raised 0.08 so the soles sit on the floor instead of 0.09 under it
	local LOW2 = merge(LOW, root(0, -0.42, 0))
	local RISE_LEGS = merge(root(0, -0.03, 0.02), {
		LeftHip = { 16, 0, -8 }, LeftKnee = { -30, 0, 0 }, LeftAnkle = { 14, 0, 0 },
		RightHip = { 16, 0, 8 }, RightKnee = { -30, 0, 0 }, RightAnkle = { 14, 0, 0 },
	})
	local trem = tremble(0.2, 0.5, 4, CLUTCH, { Waist = true, RightShoulder = true, RightElbow = true }, 2.6)
	local function legsWith(list, legs)
		local keys = {}
		for _, k in ipairs(list) do
			table.insert(keys, { t = k.t, ease = k.ease, pose = merge(k.pose, legs) })
		end
		return keys
	end
	out.Burnout = {
		length = 0.85, fadeIn = 0.04, fadeOut = 0.22,
		keys = seq({
			{ t = 0.06, ease = { "Exponential", "Out" }, pose = merge(JOLT_LEGS, JOLT_UP) },
			{ t = 0.2, ease = { "Quad", "Out" }, pose = merge(LOW2, CLUTCH) },
		}, legsWith(trem, LOW2), {
			{ t = 0.62, ease = { "Sine", "InOut" }, pose = merge(LOW2, CLUTCH, { Waist = { -26, 10, 0 } }) },
			{ t = 0.8, ease = { "Sine", "InOut" }, pose = merge(RISE_LEGS, CLUTCH, { Waist = { -16, 8, 0 } }) },
		}),
	}
	out.BurnoutArm = {
		length = 1.45, fadeIn = 0.04, fadeOut = 0.26,
		keys = seq({
			{ t = 0.06, ease = { "Exponential", "Out" }, pose = JOLT_UP },
			{ t = 0.2, ease = { "Quad", "Out" }, pose = CLUTCH },
		}, trem, {
			{ t = 0.62, ease = { "Sine", "InOut" }, pose = merge(CLUTCH, { Waist = { -26, 10, 0 } }) },
			-- straightening, still holding it, eyes on the arm
			{ t = 0.78, ease = { "Sine", "InOut" }, pose = merge(CLUTCH, { Waist = { -14, 8, 0 }, Neck = { -12, -18, 0 } }) },
			-- lets go: the right arm lifts in front of him, the left drops away
			{ t = 0.9, ease = { "Back", "Out" }, pose = {
				Waist = { -8, 4, 0 }, Neck = { -10, -12, 0 },
				RightShoulder = { 56, 0, 10 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 18, 0, -22 }, LeftElbow = { 32, 0, 0 }, LeftWrist = { 0, 0, 0 },
			} },
			-- shakes it out (three flicks, each smaller)
			{ t = 0.98, ease = { "Quad", "Out" }, pose = { RightShoulder = { 46, 0, 24 }, RightElbow = { 38, 0, 0 }, RightWrist = { -36, 0, 0 } } },
			{ t = 1.06, ease = { "Quad", "Out" }, pose = { RightShoulder = { 58, 0, 6 }, RightElbow = { 76, 0, 0 }, RightWrist = { 30, 0, 0 } } },
			{ t = 1.14, ease = { "Quad", "Out" }, pose = { RightShoulder = { 48, 0, 20 }, RightElbow = { 46, 0, 0 }, RightWrist = { -22, 0, 0 } } },
			{ t = 1.24, ease = { "Sine", "Out" }, pose = {
				Neck = { -4, -8, 0 }, RightShoulder = { 34, 0, 16 }, RightElbow = { 44, 0, 0 }, RightWrist = { 0, 0, 0 },
			} },
			{ t = 1.42, ease = { "Sine", "InOut" }, pose = merge(RELAX, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }) },
		}),
	}
	return out
end
