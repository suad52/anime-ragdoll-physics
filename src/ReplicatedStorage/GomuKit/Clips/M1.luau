--!nocheck
-- GomuKit.Clips.M1 (owner m1): the Gum-Gum string. The stretched limb is HIDDEN while it is out (Client.Shared), so
-- these clips sell the BODY: the coil against the punch, the torso whipping through it (Exponential Out), a Back-Out
-- overshoot, a held follow-through, then the guard. strikeAt = Config.M1.HitAt (the fist's arrival).
--   M1_Jab1 (L), M1_Jab2 (R), M1_Jab3 (L, heavier)  0.38 / 0.38 / 0.42 s  - WIDE legs + Root untouched (FK-safe)
--   M1_Whip  the Gum-Gum Whip: the right leg sweeps right -> left; he leans away from it, arms flung out  0.50 s
--   M1_Pistol  the right arm drawn back, the left arm sighting, the torso whips through  0.66 s
--   M1_Rifle   a huge coil (the arm corkscrews), an uppercut leaning back, chin up  0.70 s
--   M1_Axe     airborne: the right leg rises over his head, the whole body pitches forward with the drop  0.64 s
-- Legs + Root keep WIDE's verified values on every grounded key (Root pos Y is never changed: the feet would sink).
return function(H)
	local merge = H.merge
	local WIDE, STAND, GUARD, RELAX, RELAX_R = H.WIDE, H.STAND, H.GUARD, H.RELAX, H.RELAX_R
	local V = Vector3.new

	local function k(t, ease, ...)
		return { t = t, ease = ease, pose = merge(...) }
	end
	local function armR(sh, el, wr)
		return { RightShoulder = sh, RightElbow = { el, 0, 0 }, RightWrist = wr or { 0, 0, 0 } }
	end
	local function armL(sh, el, wr)
		return { LeftShoulder = sh, LeftElbow = { el, 0, 0 }, LeftWrist = wr or { 0, 0, 0 } }
	end
	local function torso(w, n)
		return { Waist = w, Neck = n }
	end
	local GUARD_R = armR({ 62, 0, 22 }, 112)
	local GUARD_L = armL({ 74, 0, -20 }, 118)
	local QI, QIO = { "Quad", "In" }, { "Quad", "InOut" }
	local EXP, BK, SO, SIO = { "Exponential", "Out" }, { "Back", "Out" }, { "Sine", "Out" }, { "Sine", "InOut" }

	---------------------------------------------------------------------------------------------------
	-- jabs: a short cock of the fist, the shoulder thrown through on a hard waist twist, the other fist kept up
	local M1_Jab1 = {
		length = 0.38, fadeIn = 0.04, fadeOut = 0.12, strikeAt = 0.12,
		keys = {
			k(0.035, SO, WIDE, torso({ -6, 12, 0 }, { -4, -6, 0 }), armL({ 60, 0, -24 }, 125), GUARD_R),
			k(0.09, QI, WIDE, torso({ -10, -18, 0 }, { -4, 14, 0 }), armL({ 88, 0, -6 }, 30), armR({ 58, 0, 24 }, 115)),
			k(0.12, EXP, WIDE, torso({ -14, -32, 0 }, { -5, 26, 0 }), armL({ 92, 0, -2 }, 4), armR({ 50, 0, 26 }, 118)),
			k(0.17, BK, WIDE, torso({ -16, -37, 0 }, { -5, 29, 0 }), armL({ 92, 0, -2 }, 4), armR({ 48, 0, 26 }, 120)),
			k(0.26, SO, WIDE, torso({ -12, -26, 0 }, { -4, 20, 0 }), armL({ 80, 0, -10 }, 40), armR({ 52, 0, 24 }, 116)),
			k(0.38, SIO, GUARD),
		},
	}
	local M1_Jab2 = {
		length = 0.38, fadeIn = 0.04, fadeOut = 0.12, strikeAt = 0.12,
		keys = {
			k(0.035, SO, WIDE, torso({ -6, -14, 0 }, { -4, 8, 0 }), armR({ 58, 0, 24 }, 125), GUARD_L),
			k(0.09, QI, WIDE, torso({ -10, 20, 0 }, { -4, -14, 0 }), armR({ 88, 0, 6 }, 30), armL({ 66, 0, -24 }, 115)),
			k(0.12, EXP, WIDE, torso({ -15, 36, 0 }, { -5, -28, 0 }), armR({ 92, 0, 2 }, 4), armL({ 52, 0, -26 }, 118)),
			k(0.17, BK, WIDE, torso({ -17, 41, 0 }, { -5, -32, 0 }), armR({ 92, 0, 2 }, 4), armL({ 50, 0, -26 }, 120)),
			k(0.26, SO, WIDE, torso({ -12, 28, 0 }, { -4, -22, 0 }), armR({ 80, 0, 10 }, 40), armL({ 56, 0, -24 }, 116)),
			k(0.38, SIO, GUARD),
		},
	}
	local M1_Jab3 = {
		length = 0.42, fadeIn = 0.04, fadeOut = 0.12, strikeAt = 0.14,
		keys = {
			k(0.04, SO, WIDE, torso({ -2, 22, 0 }, { -6, -14, 0 }), armL({ 40, 0, -30 }, 130), GUARD_R),
			k(0.1, QI, WIDE, torso({ -12, -16, 0 }, { -6, 12, 0 }), armL({ 86, 0, -6 }, 40), armR({ 56, 0, 26 }, 116)),
			k(0.14, EXP, WIDE, torso({ -20, -44, 0 }, { -8, 34, 0 }), armL({ 94, 0, 0 }, 2), armR({ 40, 0, 30 }, 122)),
			k(0.2, BK, WIDE, torso({ -22, -50, 0 }, { -8, 38, 0 }), armL({ 94, 0, 0 }, 2), armR({ 36, 0, 32 }, 124)),
			k(0.3, SO, WIDE, torso({ -16, -34, 0 }, { -6, 26, 0 }), armL({ 82, 0, -10 }, 36), armR({ 46, 0, 28 }, 118)),
			k(0.42, SIO, GUARD),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- the Gum-Gum WHIP: the right leg (hidden while stretched) sweeps right -> left; he leans away, arms out wide
	local WHIP_LEG0 = { RightHip = { 40, 0, 50 }, RightKnee = { -30, 0, 0 }, RightAnkle = { 10, 0, 0 } }
	local WHIP_LEG1 = { RightHip = { 60, 0, 30 }, RightKnee = { -6, 0, 0 }, RightAnkle = { 20, 0, 0 } }
	local M1_Whip = {
		length = 0.5, fadeIn = 0.04, fadeOut = 0.14, strikeAt = 0.15,
		keys = {
			k(0.035, SO, WIDE, WHIP_LEG0, torso({ 4, -26, -6 }, { 0, 16, 0 }), armL({ 24, 0, -62 }, 24), armR({ 24, 0, 66 }, 24)),
			k(0.1, QI, WIDE, WHIP_LEG1, torso({ 6, 6, 6 }, { 0, -4, 0 }), armL({ 26, 0, -80 }, 14), armR({ 6, 0, 64 }, 26)),
			k(0.15, EXP, WIDE, WHIP_LEG1, torso({ 8, 36, 12 }, { 0, -26, 0 }), armL({ 30, 0, -96 }, 10), armR({ -10, 0, 58 }, 32)),
			k(0.21, BK, WIDE, WHIP_LEG1, torso({ 8, 43, 14 }, { 0, -31, 0 }), armL({ 32, 0, -100 }, 10), armR({ -14, 0, 56 }, 34)),
			k(0.34, SO, WIDE, WHIP_LEG0, torso({ 4, 28, 8 }, { 0, -18, 0 }), armL({ 40, 0, -60 }, 40), armR({ 20, 0, 40 }, 60)),
			k(0.5, SIO, GUARD),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- the Gum-Gum PISTOL: the right fist drawn way back, the left arm sighting down the line; the torso whips through
	local M1_Pistol = {
		length = 0.66, fadeIn = 0.04, fadeOut = 0.14, strikeAt = 0.22,
		keys = {
			k(0.06, SO, WIDE, torso({ 2, -38, 0 }, { -6, 30, 0 }), armR({ -35, 0, 28 }, 105), armL({ 88, 0, -8 }, 12)),
			k(0.12, QI, WIDE, torso({ -6, -10, 0 }, { -6, 10, 0 }), armR({ 60, 0, 20 }, 60), armL({ 62, 0, -20 }, 60)),
			k(0.22, EXP, WIDE, torso({ -18, 40, 0 }, { -8, -30, 0 }), armR({ 92, 0, 0 }, 0), armL({ 30, 0, -35 }, 115)),
			k(0.28, BK, WIDE, torso({ -20, 46, 0 }, { -8, -34, 0 }), armR({ 92, 0, 0 }, 0), armL({ 26, 0, -36 }, 118)),
			k(0.42, SO, WIDE, torso({ -16, 38, 0 }, { -6, -28, 0 }), armR({ 90, 0, 2 }, 6), armL({ 30, 0, -34 }, 115)),
			k(0.52, SIO, WIDE, torso({ -10, 10, 0 }, { -4, -5, 0 }), armR({ 70, 0, 20 }, 90), armL({ 60, 0, -22 }, 110)),
			k(0.66, SO, GUARD),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- the Gum-Gum RIFLE: a huge coil (the arm corkscrews up), then the uppercut - leaning back, chin up
	local M1_Rifle = {
		length = 0.7, fadeIn = 0.04, fadeOut = 0.14, strikeAt = 0.22,
		keys = {
			k(0.07, SO, WIDE, torso({ 0, -60, 0 }, { -4, 45, 0 }), armR({ -20, 0, 40 }, 110), armL({ 70, 0, -30 }, 60)),
			k(0.14, QI, WIDE, torso({ -8, -20, 0 }, { 0, 15, 0 }), armR({ 50, 0, 30 }, 80), armL({ 60, 0, -30 }, 70)),
			k(0.22, EXP, WIDE, torso({ 6, 55, 0 }, { 14, -40, 0 }), armR({ 120, 0, 0 }, 0), armL({ 20, 0, -40 }, 100)),
			k(0.3, BK, WIDE, torso({ 8, 62, 0 }, { 16, -45, 0 }), armR({ 124, 0, 0 }, 0), armL({ 16, 0, -42 }, 104)),
			k(0.46, SO, WIDE, torso({ 4, 45, 0 }, { 10, -32, 0 }), armR({ 110, 0, 6 }, 10), armL({ 24, 0, -40 }, 100)),
			k(0.58, SIO, WIDE, torso({ -4, 10, 0 }, { 0, -5, 0 }), armR({ 70, 0, 20 }, 90), armL({ 60, 0, -22 }, 110)),
			k(0.7, SO, GUARD),
		},
	}

	---------------------------------------------------------------------------------------------------
	-- the Gum-Gum BATTLE AXE (airborne): the right leg rises over his head, then the whole body pitches forward with
	-- the drop, arms flung back. No floor contact until the landing crouch (Root rotation is free in the air)
	local M1_Axe = {
		length = 0.64, fadeIn = 0.04, fadeOut = 0.16, strikeAt = 0.22,
		keys = {
			k(0.06, SO, STAND, { Root = { 18, 0, 0, pos = V(0, 0, 0) } }, torso({ 10, 0, 0 }, { 10, 0, 0 }),
				armL({ 150, 0, -30 }, 30), armR({ 150, 0, 30 }, 30),
				{ RightHip = { 120, 0, 10 }, RightKnee = { -10, 0, 0 }, LeftHip = { 30, 0, -10 }, LeftKnee = { -60, 0, 0 }, LeftAnkle = { 20, 0, 0 } }),
			k(0.14, QI, STAND, { Root = { 4, 0, 0, pos = V(0, 0, 0) } }, torso({ 0, 0, 0 }, { 4, 0, 0 }),
				armL({ 90, 0, -40 }, 30), armR({ 90, 0, 40 }, 30),
				{ RightHip = { 80, 0, 6 }, RightKnee = { -6, 0, 0 }, LeftHip = { 10, 0, -10 }, LeftKnee = { -50, 0, 0 }, LeftAnkle = { 20, 0, 0 } }),
			k(0.22, EXP, STAND, { Root = { -28, 0, 0, pos = V(0, 0, 0) } }, torso({ -22, 0, 0 }, { -6, 0, 0 }),
				armL({ -50, 0, -40 }, 20), armR({ -50, 0, 40 }, 20),
				{ RightHip = { 20, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftHip = { -20, 0, -10 }, LeftKnee = { -40, 0, 0 }, LeftAnkle = { 10, 0, 0 } }),
			k(0.3, BK, STAND, { Root = { -32, 0, 0, pos = V(0, 0, 0) } }, torso({ -26, 0, 0 }, { -8, 0, 0 }),
				armL({ -56, 0, -42 }, 18), armR({ -56, 0, 42 }, 18),
				{ RightHip = { 16, 0, 0 }, RightKnee = { 0, 0, 0 }, LeftHip = { -24, 0, -10 }, LeftKnee = { -40, 0, 0 }, LeftAnkle = { 10, 0, 0 } }),
			k(0.45, SO, STAND, { Root = { -10, 0, 0, pos = V(0, 0, 0) } }, torso({ -10, 0, 0 }, { 0, 0, 0 }),
				armL({ 20, 0, -40 }, 40), armR({ 20, 0, 40 }, 40),
				{ RightHip = { 40, 0, 10 }, RightKnee = { -70, 0, 0 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -70, 0, 0 }, LeftAnkle = { 30, 0, 0 }, RightAnkle = { 30, 0, 0 } }),
			k(0.64, SIO, STAND, RELAX, RELAX_R, torso({ -2, 0, 0 }, { 0, 0, 0 })),
		},
	}

	return {
		M1_Jab1 = M1_Jab1, M1_Jab2 = M1_Jab2, M1_Jab3 = M1_Jab3, M1_Whip = M1_Whip,
		M1_Pistol = M1_Pistol, M1_Rifle = M1_Rifle, M1_Axe = M1_Axe,
	}
end
