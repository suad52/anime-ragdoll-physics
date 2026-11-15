--!nocheck
-- PerkShared.Emotes.Clips.PackA (owner: emotes PackA, 2026-11-07): WAVE / BOW / CLAP for the Emote Pack. An emote pack
-- (see Clips' MORE EMOTES note): returns function(K) -> { clips, fx, glyph }, same clip format and joint signs as the
-- Clips header. Every arm pose below was solved by FK against the game's R15 rig (positions quoted in HumanoidRootPart
-- space: +X the character's right, +Y up, -Z forward; the head centre sits at y 1.67, the chest front at z -0.5) and
-- swept at 60 Hz so the forearms and hands stay out of the torso and head through every transition, and every key
-- pair on a joint stays well under 180 deg. Legs only use STAND / LOW, except the Clap's deliberate hop.
-- (2026-11-08) HIP_L and the Wave's raised arm re-solved by IK with a hinge elbow (Clips header ARMS note): the wave
-- is now the upper arm out to the side, its hinge facing forward, and the forearm swinging in the frontal plane by
-- ELBOW flex (64 / 96 / 129) - the old one bent the elbow sideways with Z, which kinked the forearm.
return function(K)
	local V, key, seq, merge, tremble = K.V, K.key, K.seq, K.merge, K.tremble
	local STAND, LOW = K.STAND, K.LOW
	local GOLD, SUN, WHITE, EMBER = K.GOLD, K.SUN, K.WHITE, K.EMBER
	local REST = merge(STAND, K.RELAX, K.RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })

	local clips, fx = {}, {}

	-----------------------------------------------------------------------------------------------
	-- WAVE (2.25 s): a springy dip, then the right hand pops up beside the head (palm to the camera) and wags
	-- "HI!" with the left fist on the hip - then a second gather into the big one: the whole arm swept in huge arcs
	-- over the head, the left hand cupped at the mouth, the body swaying with every arc - "HEEEY!".
	local HIP_L = { LeftShoulder = { -62, -32, -26 }, LeftElbow = { 88, 0, 0 }, LeftWrist = { 10, 6, 0 } } -- Victory's fist on the hip (IK)
	local W_ANTIC = merge(LOW, HIP_L, {
		Waist = { -8, 14, 6 }, Neck = { -6, -10, 0 },
		RightShoulder = { 20, 45, 8 }, RightElbow = { 85, 0, 0 }, RightWrist = { 0, 0, 0 },  -- hand tucked in front of the chest
	})
	-- IK (UpperTorso space): elbow out at shoulder height, wrist at (1.89, 1.31, -0.15) upright / (1.53, 1.22) in /
	-- (2.25, 1.22) out, palm to the front
	local W_UP = merge(STAND, HIP_L, {
		Waist = { 4, -10, 8 }, Neck = { 12, 10, -6 },
		RightShoulder = { 76, -5, 56 }, RightElbow = { 96, 0, 0 }, RightWrist = { 0, 34, 0 },
	})
	local W_IN = merge(W_UP, { Waist = { 4, -10, 10 }, Neck = { 12, 13, -8 }, RightShoulder = { 54, -4, 54 }, RightElbow = { 129, 0, 0 }, RightWrist = { 0, 46, 0 } })
	local W_OUT = merge(W_UP, { Waist = { 4, -10, 6 }, Neck = { 12, 7, -4 }, RightShoulder = { 94, -5, 57 }, RightElbow = { 64, 0, 0 }, RightWrist = { 0, 32, 0 } })
	-- FK: left hand at (-0.56, 1.43, -1.05), beside the mouth with the palm turned in
	local MOUTH_L = { LeftShoulder = { 73, -35, 25 }, LeftElbow = { 95, 0, 0 }, LeftWrist = { 4, 0, 0 } }
	local W_GATHER = merge(LOW, {
		Waist = { -8, 0, 0 }, Neck = { 2, 0, 0 },
		RightShoulder = { 95, 0, 30 }, RightElbow = { 60, 0, 0 }, RightWrist = { 0, 30, 0 },
		LeftShoulder = { 45, -20, 10 }, LeftElbow = { 85, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- the arm raised by flexion (X) stays clear of the head; Z then sweeps it out (36) and back over the top (-10)
	local W_ARC_OUT = merge(STAND, MOUTH_L, {
		Waist = { 10, 0, -7 }, Neck = { 20, 0, -5 },
		RightShoulder = { 165, 0, 36 }, RightElbow = { 12, 0, 0 }, RightWrist = { 0, 90, 0 }, -- palm to the front
	})
	local W_ARC_IN = merge(W_ARC_OUT, { Waist = { 10, 0, 8 }, Neck = { 22, 0, 6 }, RightShoulder = { 165, 0, -10 } })
	local W_ARC_END = merge(W_ARC_OUT, { Waist = { 12, 0, -5 }, Neck = { 24, 0, -4 }, RightShoulder = { 165, 0, 30 } })

	clips.Wave = {
		length = 2.25, fadeIn = 0.06, fadeOut = 0.3,
		keys = {
			key(0.12, W_ANTIC, "Quad", "Out"),
			key(0.3, W_UP, "Cubic", "Out"), -- (Back would overshoot LOW -> STAND into hyperextended knees)
			key(0.43, W_IN, "Sine", "InOut"),
			key(0.56, W_OUT, "Sine", "InOut"),
			key(0.69, W_IN, "Sine", "InOut"),
			key(0.82, W_OUT, "Sine", "InOut"),
			key(0.94, W_IN, "Sine", "InOut"),
			key(1.06, W_GATHER, "Quad", "InOut"),
			key(1.2, W_ARC_OUT, "Cubic", "Out"),
			key(1.36, W_ARC_IN, "Sine", "InOut"),
			key(1.52, W_ARC_OUT, "Sine", "InOut"),
			key(1.68, W_ARC_IN, "Sine", "InOut"),
			key(1.84, W_ARC_END, "Quart", "Out"),
			key(2.1, REST, "Sine", "InOut"),
		},
	}

	-----------------------------------------------------------------------------------------------
	-- BOW (2.4 s): drawn up tall with a courtly flourish of the right hand, the hand lands on the chest as the left
	-- arm sweeps out and back, then a crisp, deep bow from the waist - head down, held - and back up proud.
	local B_TALL = merge(STAND, {
		Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 40, 0, 95 }, RightElbow = { 20, 0, 0 }, RightWrist = { -30, 0, 0 },
		LeftShoulder = { 10, 0, -35 }, LeftElbow = { 15, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- FK: right hand at (-0.11, 0.55, -0.95), the forearm folded flat across the chest
	local CHEST_R = { RightShoulder = { -14, 100, 62 }, RightElbow = { 72, 0, 0 }, RightWrist = { 0, 0, 0 } }
	local B_SET = merge(STAND, CHEST_R, {
		Waist = { 4, 0, 0 }, Neck = { 6, 0, 0 },
		LeftShoulder = { -25, 0, -60 }, LeftElbow = { 15, 0, 0 }, LeftWrist = { -20, 0, 0 },
	})
	local B_SET2 = merge(B_SET, { Neck = { 2, 0, 0 } })
	local B_DOWN = merge(STAND, CHEST_R, {
		Waist = { -58, 0, 0 }, Neck = { -14, 0, 0 },
		LeftShoulder = { -45, 0, -72 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -20, 0, 0 }, -- swept out and back
	})
	local B_HOLD = merge(B_DOWN, { Waist = { -55, 0, 0 }, Neck = { -12, 0, 0 } })
	local B_UP = merge(STAND, {
		Waist = { 6, 0, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 30, 0, 35 }, RightElbow = { 40, 0, 0 }, RightWrist = { -25, 0, 0 },
		LeftShoulder = { 10, 0, -22 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})

	clips.Bow = {
		length = 2.4, fadeIn = 0.06, fadeOut = 0.3,
		keys = {
			key(0.16, B_TALL, "Quad", "Out"),
			key(0.42, B_SET, "Quad", "Out"), -- (Back would overshoot the hand through the chest)
			key(0.56, B_SET2, "Sine", "InOut"),
			key(0.98, B_DOWN, "Quart", "Out"),
			key(1.5, B_HOLD, "Sine", "InOut"),
			key(1.84, B_UP, "Quart", "Out"),
			key(2.12, REST, "Sine", "InOut"),
		},
	}

	-----------------------------------------------------------------------------------------------
	-- CLAP (2.2 s): arms thrown wide, then a run of claps at chin height that speeds up (the body grooving side to
	-- side and leaning in harder each time), a coil with the arms swung back - and a hop with one huge clap overhead
	-- at the top of it, a squash landing, hands still pressed together up high.
	-- FK: hands at (+-0.51, 1.18, -1.57), palms flat together
	local SHUT = {
		RightShoulder = { 87, 41, -25 }, RightElbow = { 41, 0, 0 }, RightWrist = { 14, 0, 40 },
		LeftShoulder = { 87, -41, 25 }, LeftElbow = { 41, 0, 0 }, LeftWrist = { 14, 0, -40 },
	}
	-- FK: hands at (+-1.40, 1.10, -1.30), palms still facing each other
	local OPEN = {
		RightShoulder = { 55, 7, 2 }, RightElbow = { 73, 0, 0 }, RightWrist = { 45, 0, 5 },
		LeftShoulder = { 55, -7, -2 }, LeftElbow = { 73, 0, 0 }, LeftWrist = { 45, 0, -5 },
	}
	-- a pose a fraction `a` of the way from OPEN toward SHUT (the later, faster claps open less)
	local function between(a)
		local out = {}
		for name, o in pairs(OPEN) do
			local s = SHUT[name]
			out[name] = { o[1] + (s[1] - o[1]) * a, o[2] + (s[2] - o[2]) * a, o[3] + (s[3] - o[3]) * a }
		end
		return out
	end
	local C_ANTIC = merge(STAND, {
		Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 30, 0, 60 }, RightElbow = { 35, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, -60 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SHUT_T = { 0.24, 0.44, 0.61, 0.75, 0.87, 0.97, 1.06, 1.14 }
	local run = { key(0.1, C_ANTIC, "Quad", "Out") }
	for i, t in ipairs(SHUT_T) do
		local yaw = (i % 2 == 0) and 7 or -7
		if i > 1 then
			local arms = (i <= 3) and OPEN or between(math.min((i - 3) * 0.08, 0.35))
			table.insert(run, key((SHUT_T[i - 1] + t) / 2, merge(STAND, arms, {
				Waist = { 2, -yaw * 0.5, 0 }, Neck = { 10, yaw * 0.25, 0 },
			}), "Quad", "Out"))
		end
		table.insert(run, key(t, merge(STAND, SHUT, {
			Waist = { -5 - i, yaw, 0 }, Neck = { 6, -yaw * 0.5, 0 },
		}), "Quad", "In"))
	end
	local C_WIND = merge(LOW, {
		Waist = { -18, 0, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { -30, 0, 45 }, RightElbow = { 15, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -30, 0, -45 }, LeftElbow = { 15, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- the push-off (feet still planted), arms whipping forward and up
	local C_RISE = merge(STAND, {
		Waist = { 2, 0, 0 }, Neck = { 12, 0, 0 },
		RightShoulder = { 100, 0, 30 }, RightElbow = { 10, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 100, 0, -30 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	-- airborne, arms flung up wide: the slam follows from here
	local UP_WIDE = {
		RightShoulder = { 140, 0, 30 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 140, 0, -30 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}
	-- FK (with Waist 10 / Neck 28): hands at (+-0.51, 2.42, -0.42), pressed together above the head
	local OVER = {
		RightShoulder = { 147, 0, -33 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 24 },
		LeftShoulder = { 147, 0, 33 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 0, 0, -24 },
	}
	local HOP = {
		Root = { 0, 0, 0, pos = V(0, 0.55, 0) },
		LeftHip = { 22, 0, -5 }, RightHip = { 22, 0, 5 }, LeftKnee = { -40, 0, 0 }, RightKnee = { -40, 0, 0 },
		LeftAnkle = { -12, 0, 0 }, RightAnkle = { -12, 0, 0 },
	}
	local C_UP = merge(HOP, UP_WIDE, { Waist = { 8, 0, 0 }, Neck = { 24, 0, 0 } })
	local C_BIG = merge(HOP, OVER, { Waist = { 10, 0, 0 }, Neck = { 28, 0, 0 } })
	local C_LAND = merge(LOW, OVER, { Waist = { 4, 0, 0 }, Neck = { 22, 0, 0 } })
	local C_POSE = merge(STAND, OVER, { Waist = { 10, 0, 0 }, Neck = { 28, 0, 0 } })

	clips.Clap = {
		length = 2.2, fadeIn = 0.05, fadeOut = 0.26,
		keys = seq(
			run,
			{
				key(1.28, C_WIND, "Quad", "Out"),
				key(1.38, C_RISE, "Quad", "In"),
				key(1.46, C_UP, "Quad", "Out"),
				key(1.52, C_BIG, "Quad", "In"), -- the slam accelerates into the hands meeting at the top of the hop
				key(1.66, C_LAND, "Quad", "In"),
				key(1.82, C_POSE, "Quad", "Out"),
			},
			tremble(1.82, 1.96, 4, C_POSE, { Waist = true, Neck = true }, 2),
			{ key(2.1, REST, "Sine", "InOut") }
		),
	}

	-----------------------------------------------------------------------------------------------
	-- flair beats (the kinds PerkShared.Emotes draws: text / ha / spark / flash / whoosh)
	fx.Wave = {
		{ t = 0.28, kind = "whoosh", pitch = 1.35, volume = 0.3 },
		{ t = 0.3, kind = "text", text = "HI!", c0 = WHITE, c1 = SUN, size = 5, hold = 0.55, rot = -8 },
		{ t = 0.3, kind = "spark", part = "RightHand", n = 10, color = SUN },
		{ t = 1.18, kind = "whoosh", pitch = 1.0, volume = 0.42 },
		{ t = 1.2, kind = "text", text = "HEEEY!", c0 = SUN, c1 = EMBER, size = 7, hold = 0.7, rot = 6 },
		{ t = 1.2, kind = "flash", part = "RightHand", color = SUN, size = 6 },
		{ t = 1.2, kind = "spark", part = "RightHand", n = 16, color = GOLD },
		{ t = 1.52, kind = "spark", part = "RightHand", n = 10, color = SUN },
		{ t = 1.84, kind = "spark", part = "RightHand", n = 16, color = GOLD },
	}
	fx.Bow = {
		{ t = 0.14, kind = "whoosh", pitch = 1.45, volume = 0.25 },
		{ t = 0.42, kind = "spark", part = "RightHand", n = 14, color = GOLD },
		{ t = 0.6, kind = "whoosh", pitch = 0.75, volume = 0.38 },
		{ t = 0.95, kind = "text", text = "THANK YOU!", c0 = WHITE, c1 = GOLD, size = 6, hold = 1.0, rot = -6 },
		{ t = 0.95, kind = "flash", part = "UpperTorso", color = SUN, size = 8 },
		{ t = 1.84, kind = "spark", part = "Head", n = 16, color = SUN },
	}
	fx.Clap = {
		{ t = 0.24, kind = "text", text = "CLAP!", c0 = WHITE, c1 = SUN, size = 4.5, hold = 0.32, rot = -10 },
		{ t = 0.24, kind = "flash", part = "RightHand", color = WHITE, size = 3 },
		{ t = 0.61, kind = "flash", part = "RightHand", color = WHITE, size = 3 },
		{ t = 0.87, kind = "text", text = "CLAP CLAP!", c0 = WHITE, c1 = SUN, size = 5.5, hold = 0.3, rot = 8 },
		{ t = 0.87, kind = "flash", part = "RightHand", color = SUN, size = 3.5 },
		{ t = 1.06, kind = "flash", part = "RightHand", color = SUN, size = 4 },
		{ t = 1.14, kind = "spark", part = "RightHand", n = 8, color = WHITE },
		{ t = 1.36, kind = "whoosh", pitch = 1.15, volume = 0.45 },
		{ t = 1.52, kind = "flash", part = "RightHand", color = SUN, size = 12 },
		{ t = 1.52, kind = "spark", part = "RightHand", n = 36, color = GOLD },
		{ t = 1.52, kind = "spark", part = "LeftHand", n = 18, color = SUN },
		{ t = 1.52, kind = "text", text = "BRAVO!", c0 = SUN, c1 = GOLD, size = 8, hold = 0.55, rot = -6 },
		{ t = 1.66, kind = "flash", part = "LowerTorso", color = GOLD, size = 9 },
	}

	return { clips = clips, fx = fx, glyph = { Wave = "振", Bow = "礼", Clap = "拍" } }
end
