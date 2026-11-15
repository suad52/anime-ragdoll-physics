--!nocheck
-- PerkShared.Emotes.Clips.PackC (owner: emotes PackC, 2026-11-07): an emote PACK - PowerUp, Pose and Facepalm for
-- GojoShared.Client.ProceduralAnimator, with their flair beats and wheel glyphs. Clips requires every ModuleScript child
-- and calls it with its kit (helpers + the FK-verified stances), so nothing here requires Clips back.
-- Same clip format, joint signs and <180-degree rule as the Clips header; legs only ever use STAND / CROUCH / LOW / WIDE
-- (feet planted - no hops in this pack). Arm angles were fitted by FK on the blocky R15 preview rig (UpperArm 1.24,
-- LowerArm 1.12, Hand a 0.32 cap - the arm is a 1-stud beam, so contact poses sit ~1 stud off the face):
--   fists at the hips    Shoulder {-30, +-10, +-12}, Elbow 70 -> fists beside the hips, elbows drawn back
--   forearm across face  RightShoulder {120, 10, -66}, Elbow 18 -> the arm a bar across the nose, 1 stud out
--   palm on the face     RightShoulder {105, 40, -50}, Elbow 78, Wrist {0,-51,0} (Neck -18) -> hand over the eyes
--   hand at the chin     RightShoulder {77, 59, -43}, Elbow 103, Wrist {0,-36,0} (Neck -6) -> on the chin
--   (2026-11-08: both re-solved by IK - the old ones left the hand floating ~1 stud in front of the face)
--   arm flung out        LeftShoulder {-10, 0, -82} (Waist Y -34) -> out left, a little forward, 20 deg up
--   point at the viewer  LeftShoulder {98, 0, -14} (Waist Y -20) -> straight ahead, 10 deg up
return function(K)
	local C, key, seq, merge, tremble = K.C, K.key, K.seq, K.merge, K.tremble
	local STAND, CROUCH, LOW, WIDE, RELAX, RELAX_R = K.STAND, K.CROUCH, K.LOW, K.WIDE, K.RELAX, K.RELAX_R
	local GOLD, SUN, WHITE, EMBER, RED = K.GOLD, K.SUN, K.WHITE, K.EMBER, K.RED
	local PINK, VIOLET = C(255, 110, 200), C(170, 110, 255)
	local GLOOM, GLOOM_DK, SWEAT = C(170, 190, 255), C(95, 115, 190), C(120, 190, 255)
	local REST = merge(STAND, RELAX, RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })
	local clips, fx = {}, {}

	-----------------------------------------------------------------------------------------------
	-- POWER UP (3.0 s): gathered into a deep crouch with the arms crossed, then wide and low with the fists clenched at
	-- the hips, trembling as it builds - bearing down deeper, shaking harder - and then the roar: chest flung up, head
	-- back, arms thrown out, still shaking with it while the aura bursts, and a cocky powered-up settle.
	local PU_GATHER = merge(CROUCH, {
		Waist = { -24, 0, 0 }, Neck = { -16, 0, 0 },
		RightShoulder = { 70, 0, -28 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 70, 0, 28 }, LeftElbow = { 120, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local PU_CLENCH = merge(LOW, {
		Waist = { -4, 0, 0 }, Neck = { -6, 0, 0 }, -- chest up, glaring from under the brow
		RightShoulder = { -30, 10, 12 }, RightElbow = { 70, 0, 0 }, RightWrist = { 15, 0, 0 }, -- fists at the hips
		LeftShoulder = { -30, -10, -12 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 15, 0, 0 },
	})
	local PU_STRAIN = merge(CROUCH, {
		Waist = { -14, 0, 0 }, Neck = { -12, 0, 0 },
		RightShoulder = { -38, 10, 18 }, RightElbow = { 82, 0, 0 }, RightWrist = { 22, 0, 0 },
		LeftShoulder = { -38, -10, -18 }, LeftElbow = { 82, 0, 0 }, LeftWrist = { 22, 0, 0 },
	})
	local PU_ROAR = merge(LOW, {
		Waist = { 22, 0, 0 }, Neck = { 32, 0, 0 },
		RightShoulder = { -14, 0, 58 }, RightElbow = { 34, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { -14, 0, -58 }, LeftElbow = { 34, 0, 0 }, LeftWrist = { 10, 0, 0 },
	})
	local PU_ROAR2 = merge(PU_ROAR, {
		Waist = { 27, 0, 0 }, Neck = { 40, 0, 0 },
		RightShoulder = { -16, 0, 66 }, LeftShoulder = { -16, 0, -66 },
	})
	local PU_SETTLE = merge(STAND, {
		Waist = { 4, 0, 0 }, Neck = { 8, 0, 0 },
		RightShoulder = { 6, 0, 22 }, RightElbow = { 24, 0, 0 }, RightWrist = { 8, 0, 0 },
		LeftShoulder = { 6, 0, -22 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 8, 0, 0 },
	})
	-- (2026-11-08) the strain tremor is in the torso and head only (shaking the shoulders made both arms jitter on their
	-- own); it still builds - clench < strain > roar - just smaller
	local SHAKE = { Waist = true, Neck = true }

	clips.PowerUp = {
		length = 3.0, fadeIn = 0.08, fadeOut = 0.3,
		keys = seq(
			{
				key(0.18, PU_GATHER, "Quad", "Out"),
				key(0.46, PU_CLENCH, "Quart", "Out"),
			},
			tremble(0.46, 1.06, 8, PU_CLENCH, SHAKE, 0.8, 0),
			{ key(1.2, PU_STRAIN, "Quad", "InOut") },
			tremble(1.2, 1.5, 6, PU_STRAIN, SHAKE, 1.6, 0),
			{
				key(1.62, PU_ROAR, "Quart", "Out"),
				key(1.74, PU_ROAR2, "Sine", "Out"),
			},
			tremble(1.74, 2.32, 9, PU_ROAR2, SHAKE, 1.2, 0),
			{
				key(2.56, PU_SETTLE, "Sine", "InOut"),
				key(2.84, REST, "Sine", "InOut"),
			}
		),
	}
	fx.PowerUp = {
		{ t = 0.16, kind = "whoosh", pitch = 0.75, volume = 0.4 },
		{ t = 0.46, kind = "flash", part = "LowerTorso", color = EMBER, size = 5 },
		{ t = 0.5, kind = "text", text = "HNNNGH...", c0 = WHITE, c1 = EMBER, size = 6, hold = 0.9, rot = -6 },
		{ t = 0.55, kind = "spark", part = "RightHand", n = 8, color = EMBER },
		{ t = 0.55, kind = "spark", part = "LeftHand", n = 8, color = EMBER },
		{ t = 0.85, kind = "spark", part = "LowerTorso", n = 12, color = GOLD },
		{ t = 1.1, kind = "spark", part = "RightHand", n = 10, color = SUN },
		{ t = 1.1, kind = "spark", part = "LeftHand", n = 10, color = SUN },
		{ t = 1.2, kind = "flash", part = "UpperTorso", color = GOLD, size = 6 },
		{ t = 1.35, kind = "spark", part = "LowerTorso", n = 16, color = GOLD },
		{ t = 1.35, kind = "spark", part = "UpperTorso", n = 12, color = EMBER },
		{ t = 1.48, kind = "whoosh", pitch = 0.55, volume = 0.5 },
		-- the burst
		{ t = 1.62, kind = "flash", part = "UpperTorso", color = SUN, size = 15 },
		{ t = 1.62, kind = "flash", part = "LowerTorso", color = GOLD, size = 11 },
		{ t = 1.62, kind = "flash", part = "Head", color = WHITE, size = 7 },
		{ t = 1.62, kind = "spark", part = "UpperTorso", n = 50, color = GOLD },
		{ t = 1.62, kind = "spark", part = "Head", n = 24, color = SUN },
		{ t = 1.62, kind = "spark", part = "LowerTorso", n = 30, color = EMBER },
		{ t = 1.62, kind = "whoosh", pitch = 0.8, volume = 0.6 },
		{ t = 1.62, kind = "text", text = "HAAAAAA!!", c0 = SUN, c1 = RED, size = 9, hold = 1.0, rot = 7 },
		{ t = 1.9, kind = "flash", part = "UpperTorso", color = GOLD, size = 11 },
		{ t = 1.9, kind = "spark", part = "UpperTorso", n = 24, color = SUN },
		{ t = 2.15, kind = "flash", part = "LowerTorso", color = EMBER, size = 9 },
		{ t = 2.15, kind = "spark", part = "RightHand", n = 14, color = GOLD },
		{ t = 2.15, kind = "spark", part = "LeftHand", n = 14, color = GOLD },
		{ t = 2.5, kind = "spark", part = "UpperTorso", n = 14, color = SUN },
	}

	-----------------------------------------------------------------------------------------------
	-- POSE (2.4 s): a coiled wind-up the other way, then SNAP - split stance, torso wrenched round, the right forearm
	-- thrown across the face and the left arm flung out with the wrist cocked, chin down, head tilted; a still, menacing
	-- hold; then the left hand draws in and fires a point straight at you, head tilting the other way.
	local ACROSS = { RightShoulder = { 120, 10, -66 }, RightElbow = { 18, 0, 0 }, RightWrist = { -15, 0, 0 } }
	local PO_COIL = merge(LOW, {
		Waist = { -12, 24, 6 }, Neck = { -14, -14, 0 },
		RightShoulder = { 60, 0, -30 }, RightElbow = { 110, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 60, 0, 30 }, LeftElbow = { 110, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local PO_STRIKE = merge(WIDE, ACROSS, {
		Waist = { 10, -34, -8 }, Neck = { -8, 28, 12 },
		LeftShoulder = { -10, 0, -82 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -35, 0, 0 },
	})
	local PO_HOLD = merge(PO_STRIKE, { Waist = { 8, -32, -8 }, Neck = { -6, 26, 10 }, LeftShoulder = { -8, 0, -80 } })
	local PO_HOLD2 = merge(PO_HOLD, { Waist = { 9, -33, -9 }, Neck = { -7, 27, 12 }, LeftShoulder = { -9, 0, -81 } })
	local PO_DRAW = merge(PO_HOLD, {
		Waist = { 6, -28, -4 }, Neck = { -8, 22, 0 },
		LeftShoulder = { 40, 0, -40 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local PO_POINT = merge(WIDE, ACROSS, {
		Waist = { 6, -20, 6 }, Neck = { -4, 16, -10 },
		LeftShoulder = { 98, 0, -14 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { -10, 0, 0 },
	})
	local PO_POINT2 = merge(PO_POINT, { Neck = { -3, 16, -8 }, LeftShoulder = { 94, 0, -13 } })
	local PO_POINT3 = merge(PO_POINT2, { Waist = { 7, -21, 7 }, Neck = { -4, 17, -9 } })

	clips.Pose = {
		length = 2.4, fadeIn = 0.06, fadeOut = 0.3,
		keys = {
			key(0.14, PO_COIL, "Quad", "Out"),
			key(0.36, PO_STRIKE, "Quart", "Out"),
			key(0.52, PO_HOLD, "Sine", "InOut"),
			key(1.06, PO_HOLD2, "Sine", "InOut"),
			key(1.2, PO_DRAW, "Quad", "In"),
			key(1.34, PO_POINT, "Quart", "Out"),
			key(1.5, PO_POINT2, "Sine", "InOut"),
			key(1.96, PO_POINT3, "Sine", "InOut"),
			key(2.18, REST, "Sine", "InOut"),
		},
	}
	fx.Pose = {
		{ t = 0.34, kind = "whoosh", pitch = 1.3, volume = 0.4 },
		{ t = 0.36, kind = "flash", part = "UpperTorso", color = VIOLET, size = 10 },
		{ t = 0.38, kind = "spark", part = "LeftHand", n = 18, color = PINK },
		{ t = 0.4, kind = "text", text = "BEHOLD!", c0 = WHITE, c1 = VIOLET, size = 7, hold = 0.75, rot = -10 },
		{ t = 1.32, kind = "whoosh", pitch = 1.5, volume = 0.35 },
		{ t = 1.36, kind = "flash", part = "LeftHand", color = SUN, size = 6 },
		{ t = 1.36, kind = "spark", part = "LeftHand", n = 16, color = GOLD },
		{ t = 1.4, kind = "text", text = "FLAWLESS!", c0 = SUN, c1 = PINK, size = 8, hold = 0.65, rot = 8 },
		{ t = 1.7, kind = "spark", part = "Head", n = 10, color = WHITE },
	}

	-----------------------------------------------------------------------------------------------
	-- FACEPALM (2.2 s): a deadpan beat with the head cocked ("really?"), the hand rising slowly... and the face dropping
	-- into it; the head shakes in the palm while the whole body sags, the hand drags down the face to the chin, and the
	-- arm flops, defeated.
	local LIMP_L = { LeftShoulder = { 2, 0, -6 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { 0, 0, 0 } }
	local PALM = { RightShoulder = { 105, 40, -50 }, RightElbow = { 78, 0, 0 }, RightWrist = { 0, -51, 0 } }
	local FP_LOOK = merge(STAND, {
		Waist = { 3, 0, 0 }, Neck = { 6, -8, -12 },
		RightShoulder = { 12, 0, 16 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 8, 0, -14 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local FP_RISE = merge(FP_LOOK, { Waist = { 0, 0, 0 }, Neck = { 0, -4, -6 }, RightShoulder = { 58, 0, -32 }, RightElbow = { 88, 0, 0 } })
	local FP_SMACK = merge(STAND, PALM, LIMP_L, { Waist = { -8, 0, 0 }, Neck = { -18, 0, 0 } })
	local FP_SHAKE_A = merge(FP_SMACK, { Waist = { -10, 0, 0 }, Neck = { -19, 14, 0 } })
	local FP_SHAKE_B = merge(FP_SMACK, { Waist = { -12, 0, 0 }, Neck = { -20, -14, 0 } })
	local FP_SHAKE_C = merge(FP_SMACK, { Waist = { -14, 0, 0 }, Neck = { -21, 10, 0 } })
	local FP_SHAKE_D = merge(FP_SMACK, { Waist = { -16, 0, 0 }, Neck = { -22, -5, 0 } })
	local FP_DRAG = merge(STAND, LIMP_L, {
		Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { 77, 59, -43 }, RightElbow = { 103, 0, 0 }, RightWrist = { 0, -36, 0 }, -- palm dragged to the chin
	})
	local FP_DROP = merge(STAND, LIMP_L, {
		Waist = { -14, 0, 0 }, Neck = { -14, 0, 0 },
		RightShoulder = { 4, 0, 6 }, RightElbow = { 12, 0, 0 }, RightWrist = { 0, 0, 0 },
	})

	clips.Facepalm = {
		length = 2.2, fadeIn = 0.16, fadeOut = 0.28,
		keys = {
			key(0.22, FP_LOOK, "Sine", "Out"),
			key(0.56, FP_RISE, "Sine", "InOut"),
			key(0.72, FP_SMACK, "Quart", "Out"),
			key(0.9, FP_SHAKE_A, "Sine", "InOut"),
			key(1.06, FP_SHAKE_B, "Sine", "InOut"),
			key(1.22, FP_SHAKE_C, "Sine", "InOut"),
			key(1.38, FP_SHAKE_D, "Sine", "InOut"),
			key(1.62, FP_DRAG, "Sine", "InOut"),
			key(1.84, FP_DROP, "Quad", "In"),
			key(2.06, REST, "Sine", "InOut"),
		},
	}
	fx.Facepalm = {
		{ t = 0.66, kind = "whoosh", pitch = 1.5, volume = 0.22 },
		{ t = 0.72, kind = "flash", part = "Head", color = WHITE, size = 3.5 },
		{ t = 0.74, kind = "text", text = "UGH...", c0 = WHITE, c1 = GLOOM, size = 6, hold = 0.8, rot = -6 },
		{ t = 0.95, kind = "spark", part = "Head", n = 6, color = SWEAT },
		{ t = 1.3, kind = "spark", part = "Head", n = 4, color = SWEAT },
		{ t = 1.66, kind = "text", text = "*SIGH*", c0 = GLOOM, c1 = GLOOM_DK, size = 5, hold = 0.45, rot = 5 },
	}

	return {
		clips = clips,
		fx = fx,
		glyph = { PowerUp = "気", Pose = "決", Facepalm = "呆" },
	}
end
