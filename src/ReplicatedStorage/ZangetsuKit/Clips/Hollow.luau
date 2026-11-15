--!nocheck
-- ZangetsuKit.Clips.Hollow (owner: hollow): the R HOLLOW MASK clips (DESIGN 8.3). Returns function(H) -> clips.
--   HollowMask      cast 0.00 -> 1.25 (16 keys): the palm claps onto his face, presses (the veins crawl), the claw drags
--                   the mask down, the hunched shudder while the plates crack into place (tremble), the inhale, the
--                   ROAR at 0.95 (roarAt, Back Out, the blade whipped out through the grip), tremble, the spring (1.20)
--   HollowSlashA/B/C  0.24 each, played at slash t - 0.05 (strikeAt 0.05): forehand / rising diagonal / overhead chop,
--                   in the air (AIR legs), each with a 0.05 overshoot and a 0.16 recoil
--   HollowFinisher  0.80, played at FinisherAt - 0.32 (strikeAt 0.32, 12 keys): he appears blade-high, cocks deep and
--                   trembles through the 0.30 s charge, the diagonal release (H.RELEASE), the overshoot, the held swing
--                   (the 0.16 hit-stop lands on top of it), the fall
--   HollowLand      1.25, played at LandAt (shatterAt 0.55, 12 keys): the landing crouch, the crack flinch, the shudder,
--                   the head snapping back as the mask bursts, shaking it off, then a CHIBURI (0.88 wind, 0.95 the flick
--                   down to his right, held) and the blade back onto the shoulder
-- Every clip also has a "<Name>_BK" twin for the Bankai form: identical except that every CARRY_SK arm (the hand-back)
-- becomes CARRY_BK, so a cast inside Tensa Zangetsu hands back to the Bankai carry seamlessly.
return function(H)
	local merge, tremble, EDGE = H.merge, H.tremble, H.EDGE
	local STAND, CROUCH, LOW, WIDE = H.STAND, H.CROUCH, H.LOW, H.WIDE
	local CARRY_SK, CARRY_BK, REST = H.CARRY_SK, H.CARRY_BK, H.REST
	local RELEASE, MASK_HAND = H.RELEASE, H.MASK_HAND

	local function key(t, ease, pose)
		return { t = t, ease = ease, pose = pose }
	end
	local QO, QI, SIO, BO, EO = { "Quad", "Out" }, { "Quad", "In" }, { "Sine", "InOut" }, { "Back", "Out" }, { "Exponential", "Out" }

	-- legs while he hangs in the air beside the victim (Root named so a planted clip underneath cannot sink him)
	local AIR = {
		Root = { 0, 0, 0, pos = Vector3.zero },
		LeftHip = { 48, 0, -10 }, LeftKnee = { -84, 0, 0 }, LeftAnkle = { 22, 0, 0 },
		RightHip = { 16, 0, 10 }, RightKnee = { -58, 0, 0 }, RightAnkle = { 26, 0, 0 },
	}
	-- the sword arm low, the cleaver trailing behind him (DESIGN: CARRY_BK-like, SwordGrip {-95,0,-10})
	local TRAIL = { RightShoulder = { 10, 0, 18 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -95, 0, -10 } }
	local function carry(pose)
		return merge(pose, CARRY_SK)
	end

	---------------------------------------------------------------------------------------------------
	-- HOLLOW MASK (0 -> 1.25; the roar at 0.95)
	local M1 = merge(STAND, TRAIL, {
		Waist = { -6, 0, 0 }, Neck = { -20, 0, 0 },
		LeftShoulder = { 68, -30, 30 }, LeftElbow = { 82, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	-- the palm claps over his face (H.MASK_HAND re-solved for the FK limb check: hand 1.18 in front of the face centre,
	-- 0.08 corner overlap)
	local M2 = merge(STAND, TRAIL, MASK_HAND, {
		Waist = { -8, 0, 0 }, Neck = { -10, 0, 0 },
		LeftShoulder = { 106, -40, 40 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- pressing the palm in (the veins crawl out from under it): head bowed into the hand
	local M2b = merge(STAND, TRAIL, {
		Waist = { -8, 0, 0 }, Neck = { -16, 0, 0 },
		LeftShoulder = { 106, -40, 50 }, LeftElbow = { 44, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local M3 = merge(STAND, TRAIL, {
		Waist = { -8, 0, 0 }, Neck = { -4, 0, 0 },
		LeftShoulder = { 80, -30, 45 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local M4 = merge(STAND, TRAIL, {
		Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 },
		LeftShoulder = { 55, -20, 30 }, LeftElbow = { 80, 0, 0 }, LeftWrist = { 30, 0, 0 },
	})
	local M5 = merge(STAND, {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.12, 0) },
		LeftHip = { 10, 0, -4 }, RightHip = { 10, 0, 4 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -20, 0, 0 },
		LeftAnkle = { 10, 0, 0 }, RightAnkle = { 10, 0, 0 },
		Waist = { 6, 0, 0 }, Neck = { 20, 0, 0 },
		LeftShoulder = { 25, 0, -15 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 10, 0, 0 },
		RightShoulder = { 25, 0, 15 }, RightElbow = { 80, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 90, 0, -25 },
	})
	local ROAR = merge(WIDE, {
		Waist = { -20, 0, 0 }, Neck = { 8, 0, 0 },
		LeftShoulder = { 30, 0, -80 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { 20, 0, 0 },
		RightShoulder = { 30, 0, 80 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -12, EDGE.FORE, 0 },
	})
	local SPRING = merge(LOW, {
		Waist = { -18, -10, 0 }, Neck = { 10, 10, 0 },
		LeftShoulder = { 40, 0, -30 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 },
		RightShoulder = { -20, 0, 25 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -70, 0, -10 },
	})
	local maskKeys = {
		key(0.06, QO, M1),
		key(0.18, BO, M2),
		key(0.30, SIO, M2b),
		key(0.44, SIO, M3),
		key(0.56, QO, M4),
	}
	-- the plates crack into place: a hunched shudder
	for _, k in ipairs(tremble(0.56, 0.72, 3, M4, { Waist = true, Neck = true, LeftShoulder = true }, 2)) do
		table.insert(maskKeys, k)
	end
	table.insert(maskKeys, key(0.84, QI, M5))
	table.insert(maskKeys, key(0.95, BO, ROAR))
	for _, k in ipairs(tremble(0.95, 1.15, 4, ROAR, { Waist = true, Neck = true, LeftShoulder = true, RightShoulder = true }, 2.5)) do
		table.insert(maskKeys, k)
	end
	table.insert(maskKeys, key(1.20, QO, SPRING))
	table.insert(maskKeys, key(1.25, QO, carry(SPRING)))
	local HollowMask = { length = 1.25, fadeIn = 0.1, fadeOut = 0.06, roarAt = 0.95, keys = maskKeys }

	---------------------------------------------------------------------------------------------------
	-- THE BLITZ: three mid-air cuts, each 0.24 long with the hit key at 0.05
	local function slash(wind, hit, over, recoil, settle)
		return {
			length = 0.24, fadeIn = 0.03, fadeOut = 0.04, strikeAt = 0.05,
			keys = {
				key(0.00, QO, merge(AIR, wind)),
				key(0.05, BO, merge(AIR, hit)),
				key(0.10, QO, merge(AIR, over)),
				key(0.16, SIO, merge(AIR, recoil)),
				key(0.24, QO, carry(merge(AIR, settle))),
			},
		}
	end
	-- A: forehand, horizontal, right -> left (edge FORE)
	local HollowSlashA = slash(
		{ Waist = { -6, -30, 0 }, Neck = { 4, 20, 0 }, RightShoulder = { 70, 0, 90 }, RightElbow = { 25, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 0, EDGE.FORE, 0 }, LeftShoulder = { 60, 0, -40 }, LeftElbow = { 50, 0, 0 } },
		{ Waist = { -10, 10, 0 }, Neck = { 0, -6, 0 }, RightShoulder = { 90, 0, 6 }, RightElbow = { 5, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 0, EDGE.FORE, 0 }, LeftShoulder = { 40, 0, -60 }, LeftElbow = { 30, 0, 0 } },
		{ Waist = { -12, 32, 0 }, Neck = { 0, -14, 0 }, RightShoulder = { 85, 0, -40 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 0, EDGE.FORE, 15 }, LeftShoulder = { 30, 0, -65 }, LeftElbow = { 30, 0, 0 } },
		{ Waist = { -10, 22, 0 }, Neck = { 0, -10, 0 }, RightShoulder = { 85, 0, -22 }, RightElbow = { 12, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 0, EDGE.FORE, 8 }, LeftShoulder = { 35, 0, -55 }, LeftElbow = { 35, 0, 0 } },
		{ Waist = { -6, 10, 0 }, Neck = { 0, -4, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 } }
	)
	-- B: rising diagonal, low-left -> high-right (edge RISE)
	local HollowSlashB = slash(
		{ Waist = { -14, 26, 0 }, Neck = { 0, -16, 0 }, RightShoulder = { 50, 0, -16 }, RightElbow = { 35, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { -30, EDGE.RISE, 20 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 40, 0, 0 } },
		{ Waist = { -6, 6, 0 }, Neck = { 4, 4, 0 }, RightShoulder = { 100, 0, -4 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 0, EDGE.RISE, 0 }, LeftShoulder = { 50, 0, -40 }, LeftElbow = { 40, 0, 0 } },
		{ Waist = { 0, -24, 0 }, Neck = { 10, 12, 0 }, RightShoulder = { 150, 0, 45 }, RightElbow = { 15, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 10, EDGE.RISE, 0 }, LeftShoulder = { 40, 0, -55 }, LeftElbow = { 35, 0, 0 } },
		{ Waist = { -2, -18, 0 }, Neck = { 8, 8, 0 }, RightShoulder = { 135, 0, 38 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 6, EDGE.RISE, 0 }, LeftShoulder = { 40, 0, -50 }, LeftElbow = { 35, 0, 0 } },
		{ Waist = { -4, -8, 0 }, Neck = { 4, 4, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 } }
	)
	-- C: overhead chop (edge CHOP; the tip may dip low - he is in the air)
	local HollowSlashC = slash(
		{ Waist = { 6, -14, 0 }, Neck = { 8, 10, 0 }, RightShoulder = { 170, 0, 10 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 25, EDGE.CHOP, 0 }, LeftShoulder = { 70, 0, -30 }, LeftElbow = { 40, 0, 0 } },
		{ Waist = { -22, 10, 0 }, Neck = { 0, 0, 0 }, RightShoulder = { 80, 0, -12 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 8, EDGE.CHOP, 0 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 30, 0, 0 } },
		{ Waist = { -28, 8, 0 }, Neck = { -4, 0, 0 }, RightShoulder = { 55, 0, -10 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 10, EDGE.CHOP, 0 }, LeftShoulder = { 20, 0, -55 }, LeftElbow = { 30, 0, 0 } },
		{ Waist = { -24, 6, 0 }, Neck = { -2, 0, 0 }, RightShoulder = { 66, 0, -6 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 },
			SwordGrip = { 8, EDGE.CHOP, 0 }, LeftShoulder = { 25, 0, -50 }, LeftElbow = { 30, 0, 0 } },
		{ Waist = { -10, 0, 0 }, Neck = { 0, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 } }
	)

	---------------------------------------------------------------------------------------------------
	-- THE FINISHER (0.80, played at FinisherAt - 0.32; the swing lands at 0.32 = FinisherAt)
	local F0 = merge(AIR, {
		Waist = { 4, -20, 0 }, Neck = { 6, 14, 0 },
		RightShoulder = { 150, 0, 14 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 20, EDGE.CHOP, 0 },
		LeftShoulder = { 70, 0, -30 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local COCK = merge(AIR, {
		Waist = { 12, -30, 0 }, Neck = { 10, 20, 0 },
		RightShoulder = { 175, 0, 12 }, RightElbow = { 45, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 30, EDGE.CHOP, 0 },
		LeftShoulder = { 85, 0, -20 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SWING = merge(RELEASE, { Root = { 0, 0, 0, pos = Vector3.zero } })
	local OVER = merge(SWING, {
		Waist = { -22, 38, 0 }, Neck = { 6, -30, 0 },
		RightShoulder = { 55, 18, -18 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 28, EDGE.CHOP, 0 },
	})
	local HELD = merge(OVER, { Waist = { -20, 36, 0 }, Neck = { 8, -28, 0 } })
	local FALL = merge(AIR, {
		Waist = { -8, 20, 0 }, Neck = { 4, -12, 0 },
		RightShoulder = { 20, 0, 30 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -95, 0, -10 },
		LeftShoulder = { 30, 0, -50 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local finKeys = { key(0.00, QO, F0), key(0.12, QO, COCK) }
	-- the charge: the cocked blade trembles while the Getsuga gathers on it
	for _, k in ipairs(tremble(0.12, 0.30, 4, COCK, { Waist = true, Neck = true, RightShoulder = true }, 2)) do
		table.insert(finKeys, k)
	end
	table.insert(finKeys, key(0.32, EO, SWING))
	table.insert(finKeys, key(0.37, BO, OVER))
	table.insert(finKeys, key(0.50, SIO, HELD))
	table.insert(finKeys, key(0.62, SIO, OVER))
	table.insert(finKeys, key(0.72, QO, FALL))
	table.insert(finKeys, key(0.80, QO, carry(FALL)))
	local HollowFinisher = { length = 0.80, fadeIn = 0.04, fadeOut = 0.06, strikeAt = 0.32, keys = finKeys }

	---------------------------------------------------------------------------------------------------
	-- THE LANDING, the mask breaking and the chiburi (1.25, played at LandAt = ShatterAt - 0.55; the head snaps back at
	-- 0.55, the blade is flicked clean at 0.95)
	local LARM = { RightShoulder = { 20, 0, 35 }, RightElbow = { 25, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -108, 0, -10 } }
	local L1 = merge(CROUCH, LARM, {
		Waist = { -22, 0, 0 }, Neck = { 10, 0, 0 },
		LeftShoulder = { 40, 0, -35 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local L2 = merge(L1, { Neck = { -10, 0, 0 }, LeftShoulder = { 75, -25, 30 }, LeftElbow = { 85, 0, 0 } })
	local L3 = merge(LOW, LARM, {
		Waist = { -14, 0, 0 }, Neck = { -12, 0, 0 },
		LeftShoulder = { 80, -28, 36 }, LeftElbow = { 90, 0, 0 }, LeftWrist = { 10, 0, 0 },
	})
	local L4 = merge(L3, { Waist = { -17, 0, 0 }, Neck = { -15, 0, 0 } })
	local SHATTER = merge(LOW, LARM, {
		Waist = { 8, 0, 0 }, Neck = { 25, 0, 0 },
		LeftShoulder = { 40, 0, -75 }, LeftElbow = { 15, 0, 0 }, LeftWrist = { 20, 0, 0 },
	})
	local SHAKE_STAND = merge(STAND, {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.12, 0) },
		LeftHip = { 10, 0, -4 }, RightHip = { 10, 0, 4 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -20, 0, 0 },
		LeftAnkle = { 10, 0, 0 }, RightAnkle = { 10, 0, 0 },
	})
	local L5 = merge(SHAKE_STAND, LARM, {
		Waist = { -4, 0, 0 }, Neck = { -8, 12, 0 },
		LeftShoulder = { 20, 0, -30 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local L6 = merge(L5, { Neck = { -6, -10, 0 } })
	-- the chiburi: the blade swung up and out to his right, then flicked sharply down-right (the blood flies off it)
	local CHI_UP = merge(SHAKE_STAND, {
		Waist = { -4, -14, 0 }, Neck = { -2, -14, 0 },
		RightShoulder = { 100, 0, 60 }, RightElbow = { 55, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 30, EDGE.CHOP, 0 },
		LeftShoulder = { 15, 0, -22 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local CHIBURI = merge(SHAKE_STAND, {
		Waist = { -6, 12, 0 }, Neck = { 0, -16, 0 },
		RightShoulder = { 20, 0, 62 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 22, EDGE.CHOP, 0 },
		LeftShoulder = { 10, 0, -20 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local CHI_HOLD = merge(CHIBURI, { Waist = { -5, 10, 0 }, Neck = { 2, -14, 0 }, RightShoulder = { 24, 0, 60 } })
	local HollowLand = {
		length = 1.25, fadeIn = 0.05, fadeOut = 0.2, shatterAt = 0.55, chiburiAt = 0.95,
		keys = {
			key(0.06, QO, L1),
			key(0.10, QO, L2),
			key(0.30, SIO, L3),
			key(0.50, QI, L4),
			key(0.55, BO, SHATTER),
			key(0.68, QO, L5),
			key(0.78, SIO, L6),
			key(0.88, QO, CHI_UP),
			key(0.95, BO, CHIBURI),
			key(1.06, SIO, CHI_HOLD),
			key(1.20, SIO, REST),
			key(1.25, QO, REST),
		},
	}

	---------------------------------------------------------------------------------------------------
	local out = {
		HollowMask = HollowMask, HollowSlashA = HollowSlashA, HollowSlashB = HollowSlashB, HollowSlashC = HollowSlashC,
		HollowFinisher = HollowFinisher, HollowLand = HollowLand,
	}
	-- the Bankai-form twins: every CARRY_SK hand-back becomes CARRY_BK
	local ARM = { "RightShoulder", "RightElbow", "RightWrist", "SwordGrip" }
	local function bankai(clip)
		local c = {}
		for k, v in pairs(clip) do
			if k ~= "keys" then
				c[k] = v
			end
		end
		c.keys = {}
		for i, kf in ipairs(clip.keys) do
			local pose = table.clone(kf.pose)
			if pose.RightShoulder == CARRY_SK.RightShoulder and pose.SwordGrip == CARRY_SK.SwordGrip then
				for _, j in ipairs(ARM) do
					pose[j] = CARRY_BK[j]
				end
			end
			c.keys[i] = { t = kf.t, ease = kf.ease, pose = pose }
		end
		return c
	end
	local names = {}
	for name in pairs(out) do
		table.insert(names, name)
	end
	for _, name in ipairs(names) do
		out[name .. "_BK"] = bankai(out[name])
	end
	return out
end
