--!nocheck
-- ZangetsuKit.Clips.BankaiGrab (2026-11-08): TENSA GRAB, G again inside Tensa Zangetsu (Moves.BankaiGrab /
-- Client.BankaiGrab). Returns function(H) -> clips. Bankai-form clips: the sword arm trails Tensa Zangetsu low behind
-- him in every key and the last key hands back to H.CARRY_BK.
--   BankaiGrab       0.95, played at the cast: the reach (0.08), the hand CLOSES on the collar at GrabAt 0.16 (Back Out,
--                    lunging low in WIDE), he straightens up and LIFTS (0.30, STAND legs, arm high), the crush - a
--                    straining tremble through the three pulses (0.30 -> 0.72) -, the SLAM driving it down and forward
--                    onto its feet (0.83, Quad In, back into WIDE), the settle
-- Left-hand positions (FK-measured on the R15 rig, HRP-relative, x right / y up / z ahead): CLUTCH (-1.0, +1.0, 1.3),
-- LIFT (-0.9, +1.9, 1.1) - Config.BankaiGrab HoldDist / Side / LiftDist / Lift put the victim's collar there.
--   BankaiGrabWhiff  0.45: the reach, the clutch at the air, the settle
return function(H)
	local merge, tremble = H.merge, H.tremble
	local WIDE, STAND, CARRY_BK = H.WIDE, H.STAND, H.CARRY_BK

	local function key(t, ease, pose)
		return { t = t, ease = ease, pose = pose }
	end
	local QO, QI, BO, SIO = { "Quad", "Out" }, { "Quad", "In" }, { "Back", "Out" }, { "Sine", "InOut" }

	-- the sword arm low, Tensa Zangetsu trailing behind him (as in Clips.Hollow's TRAIL)
	local TRAIL = { RightShoulder = { 10, 0, 18 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -95, 0, -10 } }

	local REACH = merge(WIDE, TRAIL, {
		Waist = { -14, -12, 0 }, Neck = { 4, 10, 0 },
		LeftShoulder = { 110, 0, 4 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	-- the hand on the collar of a standing body HoldDist ahead
	local CLUTCH = merge(WIDE, TRAIL, {
		Waist = { -4, -10, 0 }, Neck = { 6, 8, 0 },
		LeftShoulder = { 130, 0, 6 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- standing tall, the arm high: the body hangs from his fist, feet off the ground
	local LIFT = merge(STAND, TRAIL, {
		Waist = { 4, -14, 0 }, Neck = { 12, 8, 0 },
		LeftShoulder = { 140, 0, 8 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	-- driven down and forward: palm out low in front, lunging
	local SLAM = merge(WIDE, TRAIL, {
		Waist = { -16, -18, 0 }, Neck = { 2, 12, 0 },
		LeftShoulder = { 100, 0, -4 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { -50, 0, 0 },
	})
	local SETTLE = merge(WIDE, CARRY_BK, {
		Waist = { -6, -8, 0 }, Neck = { 0, 4, 0 },
		LeftShoulder = { 40, 0, -22 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})

	local keys = {
		key(0.08, QO, REACH),
		key(0.16, BO, CLUTCH),
		key(0.30, QO, LIFT),
	}
	-- the crush: straining against the grip through the three pulses
	for _, k in ipairs(tremble(0.30, 0.72, 6, LIFT, { LeftShoulder = true, LeftElbow = true, Waist = true }, 3)) do
		table.insert(keys, k)
	end
	table.insert(keys, key(0.83, QI, SLAM))
	table.insert(keys, key(0.95, SIO, SETTLE))

	local whiff = {
		key(0.08, QO, REACH),
		key(0.16, BO, CLUTCH),
		key(0.28, QO, merge(CLUTCH, { LeftElbow = { 40, 0, 0 }, Waist = { -6, -6, 0 } })),
		key(0.45, SIO, SETTLE),
	}

	return {
		BankaiGrab = { length = 0.95, fadeIn = 0.06, fadeOut = 0.12, grabAt = 0.16, releaseAt = 0.84, keys = keys },
		BankaiGrabWhiff = { length = 0.45, fadeIn = 0.06, fadeOut = 0.1, keys = whiff },
	}
end
