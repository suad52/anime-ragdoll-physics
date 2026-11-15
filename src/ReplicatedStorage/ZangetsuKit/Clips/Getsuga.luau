--!nocheck
-- ZangetsuKit.Clips.Getsuga (owner: getsuga): Q, GETSUGA TENSHO (DESIGN.md section 6.3, FLAIR pass). Returns
-- function(H) -> clips, merged by name over the base Clips by its footer. Two clips with the same performance:
--   Getsuga       - Shikai (the cleaver); the last key returns the right arm + SwordGrip to H.CARRY_SK
--   GetsugaBankai - the same cut with Tensa Zangetsu in the hand (Bankai form); it ends in H.CARRY_BK
-- clip.strikeAt = 0.80 = Config.Getsuga.Windup, the server's release time: the SWING key lands exactly there and every
-- client freezes the track 0.10 s on it (Config.Getsuga.ReleaseFreeze), so every later key plays 0.10 s late:
-- REST lands at 1.90 and Lock 1.95 / RootTime 1.94 cover it.
-- Keys: 0.08 SETTLE (blade off the shoulder to ready-high) | 0.20 LIFT (blade vertical in front of the face, Back
-- overshoot) | 0.27 / 0.34 TWIRL (the blade spins a full turn about its own axis as it climbs) | 0.42 OVERHEAD (arm
-- straight up, the blade pointing at the sky, chin up, the free arm flung out: the reiatsu pours up the blade into a
-- sky-high flare) | 0.48-0.66 tremble x4 | 0.73 COCK (the blade drops back behind his head, chest wound right, weight
-- back and down) | 0.80 SWING (Exponential Out: the diagonal cut down across to his low left, lunging) | 0.85 OVERSHOOT
-- (Back Out) | 0.97 / 1.10 the HELD money pose (chest whipped left, head up along the aim, free arm thrown back) |
-- 1.22 RECOVER (the blade sweeps up to his right) | 1.30 CHIBURI wind | 1.38 FLICK (Exponential Out: the blade snaps
-- down-out to his right, flicking it clean) | 1.48 flick hold | 1.58 / 1.68 TWIRL back (a full turn as it climbs) |
-- 1.80 REST.
-- Legs: COIL and LUNGE were solved on the FK rig so both soles stay on the floor (LUNGE drags the right foot 0.65
-- forward, the front foot stays planted). FK-checked on the preview rig at x 7400 (every key + the midpoint of every
-- twirl segment: tip >= 0.3 above the floor, soles within 0.25, no limb through the torso/head, elbows 0..150,
-- knees -150..0, the edge leading the cut).
return function(H)
	local merge, tremble, EDGE = H.merge, H.tremble, H.EDGE
	local WIDE, REST, REST_BK = H.WIDE, H.REST, H.REST_BK
	local RAISE, RELEASE = H.RAISE, H.RELEASE
	local V = Vector3.new

	-- numeric blend of two poses (joint by joint; Root pos too). Twirl rolls are written explicitly after it.
	local function blend(a, b, k)
		local out = {}
		for name, va in pairs(a) do
			local vb = b[name] or va
			local p = {
				(va[1] or 0) + ((vb[1] or 0) - (va[1] or 0)) * k,
				(va[2] or 0) + ((vb[2] or 0) - (va[2] or 0)) * k,
				(va[3] or 0) + ((vb[3] or 0) - (va[3] or 0)) * k,
			}
			if va.pos or vb.pos then
				local pa, pb = va.pos or Vector3.zero, vb.pos or Vector3.zero
				p.pos = pa:Lerp(pb, k)
			end
			out[name] = p
		end
		for name, vb in pairs(b) do
			if out[name] == nil then
				out[name] = vb
			end
		end
		return out
	end
	local function withGrip(pose, x, y, z)
		return merge(pose, { SwordGrip = { x, y, z } })
	end

	-- solved legs (see the header)
	local COIL = {
		Root = { 0, 0, 0, pos = V(0, -0.75, 0.3) },
		LeftHip = { 66.9, 0, -16.2 }, LeftKnee = { -105, 0, 0 }, LeftAnkle = { 38.5, 0, 0 },
		RightHip = { -38, 0, 17.1 }, RightKnee = { -22.9, 0, 0 }, RightAnkle = { 65.1, 0, 0 },
	}
	local LUNGE = {
		Root = { 0, 0, 0, pos = V(0, -0.75, -0.6) },
		LeftHip = { 23.6, 0, -13.7 }, LeftKnee = { -97.8, 0, 0 }, LeftAnkle = { 73.1, 0, 0 },
		RightHip = { -45.6, 0, 15.9 }, RightKnee = { -16.6, 0, 0 }, RightAnkle = { 65.9, 0, 0 },
	}

	-- 0.08 the blade comes off the shoulder to ready-high (edge forward)
	local SETTLE = merge(WIDE, {
		Waist = { -6, -12, 0 }, Neck = { 2, 10, 0 },
		RightShoulder = { 90, 0, 20 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 40, 0, -24 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 40, EDGE.CHOP, 0 },
	})
	-- 0.20 the blade stands vertical in front of his face, chest square, eyes up the blade
	local LIFT = merge(WIDE, {
		Waist = { 0, -4, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 140, 0, 14 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 55, 0, -26 }, LeftElbow = { 45, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 0, EDGE.CHOP, 0 },
	})
	-- 0.42 drawn up overhead: the arm straight up, the blade pointing at the sky, chin up along it, the free arm flung
	-- out to the side (the sky flare pours off the tip here)
	local OVERHEAD = merge(WIDE, {
		Waist = { 6, -6, 0 }, Neck = { 22, 6, 0 },
		RightShoulder = { 172, 0, 8 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 24, 0, -72 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { -10, 0, 0 },
		SwordGrip = { 0, EDGE.CHOP, 0 },
	})
	-- the climb between them, spinning the blade a full turn about its own axis (CHOP 180 -> 300 -> 60 -> 180)
	local TW1 = withGrip(blend(LIFT, OVERHEAD, 0.35), 0, 300, 0)
	local TW2 = withGrip(blend(LIFT, OVERHEAD, 0.7), 0, 60, 0)
	-- 0.73 cocked: the blade drops back behind his head, chest wound right, weight back and down
	local COCK = merge(RAISE, COIL, {
		Waist = { 10, -26, 0 }, Neck = { 10, 20, 0 },
		RightShoulder = { 172, 0, 12 }, RightElbow = { 35, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 70, 0, -34 }, LeftElbow = { 46, 0, 0 },
		SwordGrip = { 22, EDGE.CHOP, 0 },
	})
	-- 0.80 THE CUT: H.RELEASE on the lunge
	-- (the edge is rolled to 140 so it leads the diagonal sweep: FK edge . sweep direction 0.90)
	local SWING = merge(RELEASE, LUNGE, { SwordGrip = { 24, 140, 0 } })
	-- 0.85 overshoot: the chest whips further left, the blade sweeps on across, the head comes up along the aim
	local OVER = merge(SWING, {
		Waist = { -24, 40, 0 }, Neck = { 10, -32, 0 },
		RightShoulder = { 56, 22, -20 }, RightElbow = { 8, 0, 0 },
		LeftShoulder = { -44, 0, -50 }, LeftElbow = { 30, 0, 0 },
		SwordGrip = { 29, 140, 0 },
	})
	-- the held money pose drifts (two keys)
	local HOLD1 = merge(OVER, {
		Waist = { -23, 39, 0 }, Neck = { 11, -31, 0 },
		RightShoulder = { 57, 22, -19 }, LeftShoulder = { -42, 0, -49 },
	})
	local HOLD2 = merge(OVER, {
		Waist = { -21, 36, 0 }, Neck = { 11, -28, 0 },
		RightShoulder = { 58, 21, -18 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -38, 0, -46 },
		SwordGrip = { 31, 145, 0 },
	})
	-- 1.22 recover: the blade sweeps up to his right, the chest comes back toward square
	local RECOVER = merge(WIDE, {
		Waist = { -8, 8, 0 }, Neck = { 4, -6, 0 },
		RightShoulder = { 84, 10, 26 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 10, 0, -30 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 40, EDGE.CHOP, 0 },
	})
	-- 1.30 chiburi wind: the blade raised up to his right
	local CHIBURI = merge(WIDE, {
		Waist = { -6, 2, 0 }, Neck = { 4, -10, 0 },
		RightShoulder = { 110, 0, 46 }, RightElbow = { 62, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 12, 0, -28 }, LeftElbow = { 28, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 46, EDGE.CHOP, 0 },
	})
	-- 1.38 the flick: the arm snaps out-down to his right, the blade along it (flicking the reiatsu off the edge)
	local FLICK = merge(WIDE, {
		Waist = { -8, -6, 0 }, Neck = { 2, -16, 0 },
		RightShoulder = { 26, 0, 70 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 14, 0, -24 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { 0, 0, 0 },
		SwordGrip = { 0, EDGE.CHOP, 0 },
	})
	local FLICK_HOLD = merge(FLICK, {
		Waist = { -7, -5, 0 }, RightShoulder = { 27, 0, 68 }, RightElbow = { 6, 0, 0 },
	})
	-- the twirl back onto the shoulder (CHOP 180 -> 300 -> 60 -> 180 at REST)
	local TWB1 = withGrip(blend(FLICK_HOLD, REST, 0.4), 30, 300, 0)
	local TWB2 = withGrip(blend(FLICK_HOLD, REST, 0.75), 58, 60, 0)

	-- Bankai form: Tensa Zangetsu rolls the other way and ends trailing low behind him (CARRY_BK: roll 0)
	local RECOVER_BK = merge(RECOVER, { SwordGrip = { 20, EDGE.CHOP, 0 } })
	local FLICK_BK = withGrip(FLICK, 0, 0, 0)
	local FLICK_HOLD_BK = withGrip(FLICK_HOLD, 0, 0, 0)
	-- (the arm stays out while the blade tilts back, so the long twirl never points it into the floor)
	local TWB1_BK = withGrip(blend(FLICK_HOLD, REST_BK, 0.15), -40, 120, 0)
	local TWB2_BK = withGrip(blend(FLICK_HOLD, REST_BK, 0.5), -95, 240, -6)

	local TREMBLE_J = { Waist = true, RightShoulder = true, SwordGrip = true }
	local function build(tail)
		local keys = {
			{ t = 0.08, ease = { "Quad", "Out" }, pose = SETTLE },
			{ t = 0.20, ease = { "Back", "Out" }, pose = LIFT },
			{ t = 0.27, ease = { "Linear", "InOut" }, pose = TW1 },
			{ t = 0.34, ease = { "Linear", "InOut" }, pose = TW2 },
			{ t = 0.42, ease = { "Back", "Out" }, pose = OVERHEAD },
		}
		for _, k in ipairs(tremble(0.42, 0.66, 4, OVERHEAD, TREMBLE_J, 1.8)) do
			table.insert(keys, k)
		end
		table.insert(keys, { t = 0.73, ease = { "Quad", "In" }, pose = COCK })
		table.insert(keys, { t = 0.80, ease = { "Exponential", "Out" }, pose = SWING })
		table.insert(keys, { t = 0.85, ease = { "Back", "Out" }, pose = OVER })
		table.insert(keys, { t = 0.97, ease = { "Sine", "InOut" }, pose = HOLD1 })
		table.insert(keys, { t = 1.10, ease = { "Sine", "InOut" }, pose = HOLD2 })
		for _, k in ipairs(tail) do
			table.insert(keys, k)
		end
		return { length = 1.82, fadeIn = 0.1, fadeOut = 0.16, strikeAt = 0.80, flickAt = 1.38, keys = keys }
	end

	return {
		Getsuga = build({
			{ t = 1.22, ease = { "Sine", "InOut" }, pose = RECOVER },
			{ t = 1.30, ease = { "Quad", "Out" }, pose = CHIBURI },
			{ t = 1.38, ease = { "Exponential", "Out" }, pose = FLICK },
			{ t = 1.48, ease = { "Sine", "InOut" }, pose = FLICK_HOLD },
			{ t = 1.58, ease = { "Linear", "InOut" }, pose = TWB1 },
			{ t = 1.68, ease = { "Linear", "InOut" }, pose = TWB2 },
			{ t = 1.80, ease = { "Sine", "Out" }, pose = REST },
		}),
		GetsugaBankai = build({
			{ t = 1.22, ease = { "Sine", "InOut" }, pose = RECOVER_BK },
			{ t = 1.30, ease = { "Quad", "Out" }, pose = CHIBURI },
			{ t = 1.38, ease = { "Exponential", "Out" }, pose = FLICK_BK },
			{ t = 1.48, ease = { "Sine", "InOut" }, pose = FLICK_HOLD_BK },
			{ t = 1.58, ease = { "Linear", "InOut" }, pose = TWB1_BK },
			{ t = 1.68, ease = { "Linear", "InOut" }, pose = TWB2_BK },
			{ t = 1.80, ease = { "Sine", "Out" }, pose = REST_BK },
		}),
	}
end
