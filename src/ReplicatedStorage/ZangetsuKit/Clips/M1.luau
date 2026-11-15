--!nocheck
-- ZangetsuKit.Clips.M1 (owner sword-m1, FLAIR pass): the 4-hit sword combo, Slash1..Slash4 (DESIGN.md 5.3), plus
-- Slash1BK..Slash4BK - the same swings ending in the Tensa Zangetsu low carry (CARRY_BK) for the Bankai form.
-- clip.strikeAt = the server hit time (Config.M1.HitAt): Slash1 0.14, Slash2 0.14, Slash3 0.18, Slash4 0.30.
-- Every key names the whole right arm + SwordGrip; the last key returns them to CARRY_SK (BK: CARRY_BK), STAND legs.
-- FLAIR: every swing coils AGAINST the cut first (anticipation key), whips through on Exponential Out, overshoots on
-- Back Out, holds the follow-through, then snaps a chiburi FLICK (the blade flicked out low to his right, clean) before
-- the cleaver goes back on the shoulder. Swing 4 (1.10): gather, coil + tremble, the full Linear spin, the cleave,
-- the held money pose, then the FLOURISH - the arm rises and the cleaver twirls 495 degrees flat over his head
-- (SwordGrip CFrame keys every 90 degrees, Linear, the edge leading the spin) before it drops onto his shoulder with
-- a bounce. Lengths: 0.52 -> 0.56, 0.52 -> 0.56, 0.58 -> 0.62 (+7%), 0.92 -> 1.10.
-- FK-verified on the preview rig at x 7300 (flair m1 report): every key and a 1/60 s sweep - sword tip >= 0.3 above
-- the floor, planted soles within 0.25 on the keys, elbows/knees in range, no limb or blade through the torso/head,
-- the edge leading at the strike, the blade through the server's hitbox.
-- Client.M1 strips the leg joints + Root when the caster is moving (swings 1-3 do not root), so the run keeps going.
return function(H)
	local merge, tremble, EDGE = H.merge, H.tremble, H.EDGE
	local WIDE, STAND, LOW, RELAX = H.WIDE, H.STAND, H.LOW, H.RELAX
	local CARRY_SK, CARRY_BK, READY, RAISE = H.CARRY_SK, H.CARRY_BK, H.READY, H.RAISE
	local FORE, BACK, CHOP = EDGE.FORE, EDGE.BACK, EDGE.CHOP
	local V = Vector3.new
	local rad = math.rad

	local function key(t, ease, ...)
		return { t = t, ease = ease, pose = merge(...) }
	end
	local function arm(sh, el, gr, wr)
		return { RightShoulder = sh, RightElbow = { el, 0, 0 }, RightWrist = wr or { 0, 0, 0 }, SwordGrip = gr }
	end
	local function left(sh, el)
		return { LeftShoulder = sh, LeftElbow = { el, 0, 0 }, LeftWrist = { 0, 0, 0 } }
	end
	local function torso(w, n)
		return { Waist = w, Neck = n }
	end
	local QO, QI, QIO = { "Quad", "Out" }, { "Quad", "In" }, { "Quad", "InOut" }
	local EXP, BK, SO, SIO, LIN = { "Exponential", "Out" }, { "Back", "Out" }, { "Sine", "Out" }, { "Sine", "InOut" }, { "Linear", "Out" }

	-- back to the idle carry (the scaffold's CarryShikai overlay takes over seamlessly)
	local END = merge(STAND, RELAX, torso({ -4, 0, 0 }, { 0, 0, 0 }), CARRY_SK)
	-- lifting the cleaver back toward the shoulder
	local LIFT = merge(STAND, RELAX, torso({ -5, -4, 0 }, { 1, 4, 0 }), arm({ 58, 0, 13 }, 100, { 72, CHOP, 0 }))
	-- the chiburi: the blade flicked out low to his right, edge down (tip 1.5 above the floor, 17 deg below level)
	local FLICK = merge(READY, torso({ -10, -24, 0 }, { 2, 4, 0 }), arm({ 20, 10, 52 }, 6, { 60, FORE, 20 }, { -6, 0, 0 }))
	-- Bankai form: Tensa Zangetsu swung round his right side and down into the low trailing carry
	local END_BK = merge(STAND, RELAX, torso({ -4, 0, 0 }, { 0, 0, 0 }), CARRY_BK)
	local LIFT_BK = merge(STAND, RELAX, torso({ -5, -6, 0 }, { 1, 4, 0 }), arm({ 14, 0, 30 }, 14, { -70, 0, -14 }))
	-- the chop's lunge: the body drops 0.2 and slides 0.25 forward over planted feet (leg angles solved on the rig)
	local LUNGE = {
		Root = { 0, 0, 0, pos = V(0, -0.85, -0.1) },
		LeftHip = { 54, 0, -16 }, LeftKnee = { -117, 0, 0 }, LeftAnkle = { 63, 0, 0 },
		RightHip = { -58, 0, 16 }, RightKnee = { 0, 0, 0 }, RightAnkle = { 62, 0, 0 },
	}

	---------------------------------------------------------------------------------------------------
	-- Slash1: forehand, right -> left, edge leading (FORE). Coil right, whip, overshoot, hold, chiburi, shoulder
	local Slash1 = {
		length = 0.56, fadeIn = 0.05, fadeOut = 0.12, strikeAt = 0.14,
		keys = {
			key(0.04, SO, WIDE, torso({ -6, -28, 0 }, { 2, 22, 0 }), arm({ 72, 0, 64 }, 26, { -6, FORE, 0 }), left({ 46, 0, -28 }, 44)),
			key(0.075, QO, WIDE, torso({ -9, -40, 0 }, { 2, 32, 0 }), arm({ 82, 0, 76 }, 20, { -2, FORE, 0 }), left({ 46, 0, -32 }, 42)),
			key(0.105, QI, WIDE, torso({ -10, -6, 0 }, { 3, 6, 0 }), arm({ 87, 0, 32 }, 12, { 0, FORE, 0 }), left({ 16, 0, -32 }, 34)),
			key(0.14, EXP, WIDE, torso({ -10, 28, 0 }, { 4, -22, 0 }), arm({ 88, 0, -20 }, 8, { 0, FORE, 0 }), left({ -20, 0, -30 }, 30)),
			key(0.185, BK, WIDE, torso({ -13, 40, 0 }, { 4, -30, 0 }), arm({ 86, 0, -38 }, 10, { 5, FORE, 0 }), left({ -34, 0, -44 }, 30)),
			key(0.27, SO, WIDE, torso({ -12, 36, 0 }, { 4, -27, 0 }), arm({ 84, 0, -34 }, 12, { 7, FORE, 0 }), left({ -30, 0, -40 }, 32)),
			key(0.34, SIO, WIDE, torso({ -10, 10, 0 }, { 3, -6, 0 }), arm({ 62, 8, -6 }, 26, { 28, FORE, 3 }), left({ 20, 0, -32 }, 30)),
			key(0.40, QIO, READY),
			key(0.455, BK, FLICK),
			key(0.505, SIO, LIFT),
			key(0.56, SO, END),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- Slash2: backhand rising, low left -> high right, edge leading (BACK)
	local Slash2 = {
		length = 0.56, fadeIn = 0.05, fadeOut = 0.12, strikeAt = 0.14,
		keys = {
			key(0.035, SO, WIDE, torso({ -10, 20, 0 }, { 3, -14, 0 }), arm({ 68, 0, -12 }, 30, { 18, BACK, 0 }), left({ -4, 0, -28 }, 30)),
			key(0.065, QO, WIDE, torso({ -12, 30, 0 }, { 4, -24, 0 }), arm({ 60, 0, -24 }, 34, { 24, BACK, 0 }), left({ -12, 0, -30 }, 30)),
			key(0.10, QI, WIDE, torso({ -9, 4, 0 }, { 3, -2, 0 }), arm({ 80, 0, 4 }, 16, { 8, BACK, 0 }), left({ 10, 0, -35 }, 35)),
			key(0.14, EXP, WIDE, torso({ -6, -12, 0 }, { 3, 10, 0 }), arm({ 98, 0, 10 }, 8, { 10, BACK, 0 }), left({ 30, 0, -40 }, 40)),
			key(0.185, BK, WIDE, torso({ -3, -30, 0 }, { 6, 22, 0 }), arm({ 128, 0, 46 }, 8, { 14, BACK, 0 }), left({ 36, 0, -44 }, 42)),
			key(0.28, SO, WIDE, torso({ -3, -29, 0 }, { 5, 21, 0 }), arm({ 126, 0, 45 }, 10, { 13, BACK, 0 }), left({ 34, 0, -42 }, 40)),
			key(0.34, SIO, WIDE, torso({ -6, -20, 0 }, { 3, 14, 0 }), arm({ 90, 10, 30 }, 24, { 30, BACK, 4 }), left({ 40, 0, -34 }, 34)),
			key(0.40, QIO, READY),
			key(0.455, BK, FLICK),
			key(0.505, SIO, LIFT),
			key(0.56, SO, END),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- Slash3: overhead chop with a lunge, edge leading down (CHOP): gather, raise, cock, chop, bite, rebound, hold
	local GATHER = merge(WIDE, torso({ 4, -14, 0 }, { 4, 10, 0 }), arm({ 120, 0, 14 }, 70, { 40, CHOP, 0 }), left({ 50, 0, -30 }, 40))
	local Slash3 = {
		length = 0.62, fadeIn = 0.05, fadeOut = 0.12, strikeAt = 0.18,
		keys = {
			key(0.045, SO, GATHER),
			key(0.085, BK, RAISE),
			key(0.125, SO, RAISE, torso({ 10, -24, 0 }, { 10, 18, 0 }), arm({ 172, 0, 12 }, 35, { 25, CHOP, 0 })),
			key(0.152, QI, WIDE, torso({ -4, -10, 0 }, { 6, 8, 0 }), arm({ 130, 0, 8 }, 18, { 15, CHOP, 0 }), left({ 40, 0, -30 }, 40)),
			key(0.18, EXP, LUNGE, torso({ -16, 6, 0 }, { 8, -4, 0 }), arm({ 72, 0, 4 }, 6, { 14, CHOP, 0 }), left({ -20, 0, -30 }, 30)),
			key(0.215, QO, LUNGE, torso({ -18, 8, 0 }, { 8, -5, 0 }), arm({ 69, 0, 4 }, 6, { 13, CHOP, 0 }), left({ -26, 0, -34 }, 30)),
			key(0.26, BK, LUNGE, torso({ -17, 7, 0 }, { 9, -4, 0 }), arm({ 74, 0, 4 }, 8, { 17, CHOP, 0 }), left({ -24, 0, -32 }, 30)),
			key(0.36, SO, LUNGE, torso({ -16, 6, 0 }, { 7, -4, 0 }), arm({ 72, 0, 4 }, 8, { 15, CHOP, 0 }), left({ -22, 0, -30 }, 30)),
			key(0.46, QIO, READY),
			key(0.515, BK, FLICK),
			key(0.565, SIO, LIFT),
			key(0.62, SO, END),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- Slash4: the spinning cleave + the flourish. Gather, coil right (tremble), a full turn to the left (Root yaw,
	-- Linear), the arm whips across at the strike, the money pose holds blade out front-left; then the arm rises and
	-- the cleaver twirls flat over his head (CCW from above like the spin, edge leading) and drops onto his shoulder.
	local PRE = merge(WIDE, torso({ -6, -24, 0 }, { 3, 20, 0 }), arm({ 64, 0, 46 }, 34, { -4, FORE, 0 }), left({ 56, 0, -24 }, 46))
	local COIL = merge(WIDE, torso({ -10, -40, 0 }, { 4, 32, 0 }), arm({ 60, 0, 60 }, 30, { 0, FORE, 0 }), left({ 70, 0, -20 }, 50))
	local function SPIN(yaw)
		return merge(LOW, { Root = { 0, yaw, 0, pos = LOW.Root.pos } }, torso({ -6, 0, 0 }, { 2, 0, 0 }),
			arm({ 90, 0, 78 }, 4, { 0, FORE, 0 }), left({ 20, 0, -60 }, 20))
	end
	local HIT4 = merge(WIDE, torso({ -10, 30, 0 }, { 4, -24, 0 }), arm({ 88, 0, -30 }, 4, { 0, FORE, 0 }), left({ -30, 0, -40 }, 30))
	HIT4.Root = nil -- the root finishes its turn on its own (Linear) key at the same time
	local HELD = merge(WIDE, torso({ -12, 36, 0 }, { 4, -28, 0 }), arm({ 86, 0, -40 }, 6, { 4, FORE, 0 }), left({ -36, 0, -46 }, 28))
	-- the twirl: the forearm points up, the blade lies flat across it (SwordGrip X 90) and spins about the forearm;
	-- theta 0 = blade back, 90 = right, 180 = front, 270 = left (CCW seen from above), roll 90 = the edge leads
	local function heli(theta)
		return CFrame.Angles(rad(90), 0, rad(-theta)) * CFrame.Angles(0, rad(90), 0)
	end
	local function TWIRL(theta, sway)
		return merge(WIDE, torso({ -2, sway, 0 }, { 14, -10 - sway * 0.5, 0 }), arm({ 170, 0, 6 }, 15, heli(theta)),
			left({ 34, 0, -64 }, 18))
	end
	local RISE = merge(WIDE, torso({ -4, 16, 0 }, { 10, -12, 0 }), arm({ 150, 0, 4 }, 26, heli(225)), left({ 20, 0, -60 }, 22))
	-- the drop: the arm on Back Out (the cleaver bounces on the shoulder), the legs step in on their own Sine key
	-- (a Back Out on the legs would hyperextend the knees as they straighten)
	local DROP = merge(RELAX, torso({ -7, -4, 0 }, { 3, 4, 0 }), arm({ 50, 0, 12 }, 136, { 86, CHOP, 0 }))
	local BOUNCE = merge(STAND, RELAX, torso({ -5, -2, 0 }, { 1, 2, 0 }), arm({ 57, 0, 12 }, 127, { 77, CHOP, 0 }))
	local SETTLE = merge(STAND, RELAX, torso({ -4, 0, 0 }, { 0, 0, 0 }), arm({ 55, 0, 12 }, 131, { 81, CHOP, 0 }))
	local S4 = { key(0.035, SO, PRE), key(0.075, BK, COIL) }
	for _, k in ipairs(tremble(0.075, 0.12, 2, COIL, { Waist = true, RightShoulder = true, SwordGrip = true }, 2)) do
		table.insert(S4, k)
	end
	table.insert(S4, key(0.165, LIN, SPIN(90)))
	table.insert(S4, key(0.21, LIN, SPIN(180)))
	table.insert(S4, key(0.255, LIN, SPIN(270)))
	table.insert(S4, { t = 0.30, ease = LIN, pose = { Root = WIDE.Root } }) -- 270 -> 360 (written as 0)
	table.insert(S4, { t = 0.30, ease = EXP, pose = HIT4 })
	table.insert(S4, key(0.33, BK, HELD))
	for _, k in ipairs(tremble(0.33, 0.45, 2, HELD, { Waist = true, RightShoulder = true, SwordGrip = true }, 1.5)) do
		table.insert(S4, k)
	end
	table.insert(S4, key(0.50, QO, RISE))
	-- 495 degrees of twirl, a quarter turn every 0.055 s (Linear: constant spin)
	local th = { { 0.555, 315, 5 }, { 0.61, 45, -5 }, { 0.665, 135, 5 }, { 0.72, 225, -5 }, { 0.775, 315, 5 }, { 0.8025, 0, 0 } }
	for _, v in ipairs(th) do
		table.insert(S4, key(v[1], LIN, TWIRL(v[2], v[3])))
	end
	local S4tail = {
		key(0.87, BK, DROP),
		{ t = 0.87, ease = SIO, pose = STAND },
		key(0.95, SO, BOUNCE),
		key(1.02, SIO, SETTLE),
		key(1.10, SO, END),
	}
	local Slash4 = { length = 1.10, fadeIn = 0.05, fadeOut = 0.14, strikeAt = 0.30, keys = {} }
	for _, k in ipairs(S4) do
		table.insert(Slash4.keys, k)
	end
	for _, k in ipairs(S4tail) do
		table.insert(Slash4.keys, k)
	end

	---------------------------------------------------------------------------------------------------
	-- the Bankai-form copies: same swing, the recovery ends in Tensa Zangetsu's low trailing carry
	local function bk(clip, swaps)
		local out = { length = clip.length, fadeIn = clip.fadeIn, fadeOut = clip.fadeOut, strikeAt = clip.strikeAt, keys = {} }
		for _, k in ipairs(clip.keys) do
			local p = swaps[k.pose] or k.pose
			table.insert(out.keys, { t = k.t, ease = k.ease, pose = p })
		end
		return out
	end
	local function findPose(clip, t)
		for _, k in ipairs(clip.keys) do
			if math.abs(k.t - t) < 1e-6 then
				return k.pose
			end
		end
	end
	local DROP_BK = merge(RELAX, torso({ -7, -4, 0 }, { 3, 4, 0 }), arm({ 16, 0, 26 }, 14, { -96, 0, -12 }))
	local BOUNCE_BK = merge(STAND, RELAX, torso({ -5, -2, 0 }, { 1, 2, 0 }), arm({ 5, 0, 15 }, 20, { -104, 0, -9 }))
	local SETTLE_BK = merge(STAND, RELAX, torso({ -4, 0, 0 }, { 0, 0, 0 }), arm({ 9, 0, 16 }, 18, { -100, 0, -10 }))
	local Slash1BK = bk(Slash1, { [findPose(Slash1, 0.505)] = LIFT_BK, [findPose(Slash1, 0.56)] = END_BK })
	local Slash2BK = bk(Slash2, { [findPose(Slash2, 0.505)] = LIFT_BK, [findPose(Slash2, 0.56)] = END_BK })
	local Slash3BK = bk(Slash3, { [findPose(Slash3, 0.565)] = LIFT_BK, [findPose(Slash3, 0.62)] = END_BK })
	local Slash4BK = bk(Slash4, {
		[findPose(Slash4, 0.87)] = DROP_BK, [findPose(Slash4, 0.95)] = BOUNCE_BK, [findPose(Slash4, 1.02)] = SETTLE_BK,
		[findPose(Slash4, 1.10)] = END_BK,
	})

	return {
		Slash1 = Slash1, Slash2 = Slash2, Slash3 = Slash3, Slash4 = Slash4,
		Slash1BK = Slash1BK, Slash2BK = Slash2BK, Slash3BK = Slash3BK, Slash4BK = Slash4BK,
	}
end
