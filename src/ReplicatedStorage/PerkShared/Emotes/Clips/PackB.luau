--!nocheck
-- PerkShared.Emotes.Clips.PackB (owner: emotes / PackB, 2026-11-07): the Dance, Flex and Shrug emotes. An emote PACK:
-- returns a function(K) (K = Clips.Kit: helpers + the FK-verified stances) -> { clips, fx, glyph }. See Clips' header for
-- the clip format and the joint signs. Every pose here names all 15 joints, so no joint ever interpolates across a key
-- that skips it. Arm poses were solved against the stock R15 constraint rig (UpperTorso frame; shoulder joint at the
-- upper arm's top INNER corner, so a twist about the arm swings the whole box - hence elbow-Z bends where a forearm has
-- to point up or out). Legs only use STAND / LOW / WIDE, `sway` of one (pelvis slid sideways, feet kept where they
-- were) or `bend` (a planted knee bend solved exactly); every key's soles were FK-checked on the floor (y -3.191 under
-- the root on the stock rig), and between keys they never dip deeper than the kits' own LOW/WIDE transitions do.
-- (2026-11-08) The elbow-Z bends are gone (Clips header ARMS note): HIP_L, the double biceps and the shrug arms were
-- re-solved by IK with a hinge elbow - the shoulder twist now turns the forearm up / out, the elbow only flexes.
return function(K)
	local V, C, key, seq, merge, tremble = K.V, K.C, K.key, K.seq, K.merge, K.tremble
	local STAND, LOW, WIDE = K.STAND, K.LOW, K.WIDE
	local GOLD, SUN, WHITE, EMBER = K.GOLD, K.SUN, K.WHITE, K.EMBER
	local PINK, CYAN, SKY = C(255, 95, 205), C(90, 225, 255), C(170, 205, 255)
	local REST = merge(STAND, K.RELAX, K.RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })
	local rad, deg = math.rad, math.deg

	-- the right arm's angles, mirrored onto the left (x -> -x: X keeps, Y and Z flip)
	local function flip(v)
		return { v[1] or 0, -(v[2] or 0), -(v[3] or 0), pos = v.pos }
	end
	local function arms(sh, el, wr, lsh, lel, lwr)
		return {
			RightShoulder = sh, RightElbow = el, RightWrist = wr or { 0, 0, 0 },
			LeftShoulder = lsh or flip(sh), LeftElbow = lel or flip(el), LeftWrist = lwr or flip(wr or { 0, 0, 0 }),
		}
	end
	local function ang(v)
		return CFrame.Angles(rad(v[1] or 0), rad(v[2] or 0), rad(v[3] or 0))
	end

	-- HIP SWAY with the feet planted: slide the pelvis `s` studs sideways (+ = right) and swing both thighs back under it
	-- (hip Z, solved exactly for the ankle's sideways offset), re-level each foot (ankle) and drop the pelvis by whatever
	-- the swing lifted the ankles. Thigh / shin lengths are the stock R15's hip->knee and knee->ankle (measured).
	local THIGH, SHIN = 0.92, 1.009
	local function ankleAt(hip, knee)
		return (ang(hip) * CFrame.new(0, -THIGH, 0) * ang(knee) * CFrame.new(0, -SHIN, 0)).Position
	end
	local function sway(st, s)
		local out = merge(st)
		local dy, dz = 0, 0
		for _, side in ipairs({ "Left", "Right" }) do
			local hip, knee, ankle = st[side .. "Hip"], st[side .. "Knee"], st[side .. "Ankle"]
			local h = THIGH + SHIN * math.cos(rad(knee[1] or 0))
			local hz2 = math.asin(math.clamp(math.sin(rad(hip[3] or 0)) - s / h, -0.9, 0.9))
			local hip2 = { hip[1] or 0, hip[2] or 0, deg(hz2) }
			local a2 = ang(knee):Inverse() * ang(hip2):Inverse() * ang(hip) * ang(knee) * ang(ankle)
			local ax, ay, az = a2:ToEulerAnglesXYZ()
			out[side .. "Hip"] = hip2
			out[side .. "Ankle"] = { deg(ax), deg(ay), deg(az) }
			local d = ankleAt(hip2, knee) - ankleAt(hip, knee)
			dy, dz = dy + d.Y / 2, dz + d.Z / 2
		end
		local r = st.Root
		local p = r.pos or V(0, 0, 0)
		out.Root = { r[1] or 0, r[2] or 0, r[3] or 0, pos = V(p.X + s, p.Y - dy, p.Z - dz) }
		return out
	end
	-- a PLANTED knee bend: knees straight ahead (feet stay at STAND's width), hips h, knees -k, ankles k - h (sole level),
	-- the pelvis dropped by exactly what the bend shortens the leg. SOFT (0.2 down) is the dance's bounce: STAND <-> SOFT
	-- keeps the soles within 0.05 of the floor all the way, where STAND <-> LOW dips them 0.2 through it half-way.
	local function bend(h, k)
		local drop = THIGH + SHIN - THIGH * math.cos(rad(h)) - SHIN * math.cos(rad(h - k))
		local fwd = -THIGH * math.sin(rad(h)) - SHIN * math.sin(rad(h - k))
		return {
			Root = { 0, 0, 0, pos = V(0, -drop, -fwd) }, LeftHip = { h, 0, 0 }, RightHip = { h, 0, 0 },
			LeftKnee = { -k, 0, 0 }, RightKnee = { -k, 0, 0 }, LeftAnkle = { k - h, 0, 0 }, RightAnkle = { k - h, 0, 0 },
		}
	end
	local SOFT = bend(28, 53)

	local clips, fx, glyph = {}, {}, {}

	-------------------------------------------------------------------------------------------------------------------
	-- DANCE (3.25 s): a head-down dip, then the disco point - the right finger flung at the sky with the hips popped the
	-- other way, then swept down across the body as the knees drop - three times, then four alternating fist pumps on a
	-- knee bounce (hips swaying into each punch), and a big arms-up "V" with a shoulder shimmy.
	local HIP_L = { LeftShoulder = { -62, -32, -26 }, LeftElbow = { 88, 0, 0 }, LeftWrist = { 10, 6, 0 } } -- fist on the hip (IK)
	local D_POINT_UP = { RightShoulder = { 150, 0, 40 }, RightElbow = { 5, 0, 0 }, RightWrist = { -10, 0, 0 } }
	local D_POINT_DN = { RightShoulder = { 30, 0, -38 }, RightElbow = { 5, 0, 0 }, RightWrist = { 10, 0, 0 } }
	local D_ANTIC = merge(sway(LOW, 0.12), HIP_L, D_POINT_DN, { Waist = { -18, 14, 6 }, Neck = { -16, 10, 0 } })
	local D_UP = merge(sway(STAND, -0.22), HIP_L, D_POINT_UP, { Waist = { 4, -2, -10 }, Neck = { 22, -22, -6 } })
	local D_DOWN = merge(sway(SOFT, 0.2), HIP_L, D_POINT_DN, { Waist = { -12, 14, 8 }, Neck = { -10, 18, 4 } })
	-- fist pumps: the punching fist straight up, the other pulled down to the chest, elbow out
	local PUMP_UP = { { 160, 0, 20 }, { 20, 0, 0 }, { -10, 0, 0 } }
	local PUMP_DN = { { 10, 0, 35 }, { 110, 0, 0 }, { 20, 0, 0 } }
	local D_MID = merge(SOFT, arms(PUMP_DN[1], PUMP_DN[2], PUMP_DN[3]), { Waist = { -8, 0, 0 }, Neck = { -6, 0, 0 } })
	local D_PUMP_R = merge(sway(STAND, 0.18), arms(PUMP_UP[1], PUMP_UP[2], PUMP_UP[3], flip(PUMP_DN[1]), flip(PUMP_DN[2]), flip(PUMP_DN[3])), {
		Waist = { 8, 12, 9 }, Neck = { 20, -12, -4 },
	})
	local D_PUMP_L = merge(sway(STAND, -0.18), arms(PUMP_DN[1], PUMP_DN[2], PUMP_DN[3], flip(PUMP_UP[1]), flip(PUMP_UP[2]), flip(PUMP_UP[3])), {
		Waist = { 8, -12, -9 }, Neck = { 20, 12, 4 },
	})
	local D_FINALE = merge(WIDE, arms({ 165, 0, 30 }, { 8, 0, 0 }, { -20, 0, 0 }), { Waist = { 8, 0, 0 }, Neck = { 18, 0, 0 } })
	local D_SHIM_A = merge(D_FINALE, { Waist = { 8, 12, 0 }, Neck = { 18, -10, 0 } })
	local D_SHIM_B = merge(D_FINALE, { Waist = { 8, -12, 0 }, Neck = { 18, 10, 0 } })

	clips.Dance = {
		length = 3.25, fadeIn = 0.08, fadeOut = 0.3,
		keys = {
			key(0.14, D_ANTIC, "Quad", "Out"),
			key(0.36, D_UP, "Quart", "Out"),
			key(0.58, D_DOWN, "Quart", "Out"),
			key(0.8, D_UP, "Quart", "Out"),
			key(1.02, D_DOWN, "Quart", "Out"),
			key(1.24, D_UP, "Quart", "Out"),
			key(1.42, D_MID, "Quad", "Out"),
			key(1.56, D_PUMP_R, "Quart", "Out"),
			key(1.7, D_MID, "Quad", "In"),
			key(1.84, D_PUMP_L, "Quart", "Out"),
			key(1.98, D_MID, "Quad", "In"),
			key(2.12, D_PUMP_R, "Quart", "Out"),
			key(2.26, D_MID, "Quad", "In"),
			key(2.4, D_PUMP_L, "Quart", "Out"),
			key(2.6, D_FINALE, "Quart", "Out"),
			key(2.68, D_SHIM_A, "Sine", "InOut"),
			key(2.76, D_SHIM_B, "Sine", "InOut"),
			key(2.84, D_SHIM_A, "Sine", "InOut"),
			key(2.92, D_SHIM_B, "Sine", "InOut"),
			key(2.98, D_FINALE, "Sine", "InOut"),
			key(3.08, REST, "Sine", "InOut"),
		},
	}
	fx.Dance = {
		{ t = 0.34, kind = "whoosh", pitch = 1.3, volume = 0.3 },
		{ t = 0.36, kind = "text", text = "FUNKY!", c0 = SUN, c1 = PINK, size = 6, hold = 1, rot = -8 },
		{ t = 0.36, kind = "spark", part = "RightHand", n = 10, color = PINK },
		{ t = 0.8, kind = "spark", part = "RightHand", n = 10, color = CYAN },
		{ t = 1.24, kind = "spark", part = "RightHand", n = 10, color = PINK },
		{ t = 1.54, kind = "whoosh", pitch = 1.1, volume = 0.3 },
		{ t = 1.56, kind = "spark", part = "RightHand", n = 8, color = GOLD },
		{ t = 1.84, kind = "spark", part = "LeftHand", n = 8, color = CYAN },
		{ t = 2.12, kind = "spark", part = "RightHand", n = 8, color = GOLD },
		{ t = 2.4, kind = "spark", part = "LeftHand", n = 8, color = CYAN },
		{ t = 2.58, kind = "whoosh", pitch = 0.9, volume = 0.45 },
		{ t = 2.6, kind = "flash", part = "UpperTorso", color = PINK, size = 10 },
		{ t = 2.6, kind = "spark", part = "RightHand", n = 24, color = CYAN },
		{ t = 2.6, kind = "spark", part = "LeftHand", n = 24, color = PINK },
		{ t = 2.6, kind = "text", text = "GROOVY!", c0 = WHITE, c1 = CYAN, size = 8, hold = 0.4, rot = 6 },
	}
	glyph.Dance = "踊"

	-------------------------------------------------------------------------------------------------------------------
	-- FLEX (2.6 s): hunched and gathered, fists together in front of the abs, then up into a double-biceps (upper arms
	-- level, forearms bent straight up by the head, chest out) that squeezes harder and shakes with it, re-hits, then
	-- swings side-on into the split stance for a side-chest (torso turned right, the left arm flexed across the belly,
	-- the right hand clamped on its wrist, chin up back at you), trembling.
	local F_ANTIC = merge(LOW, arms({ 28, 72, -16 }, { 52, 0, 0 }, { 30, 0, 0 }), { Waist = { -20, 0, 0 }, Neck = { -16, 0, 0 } })
	-- IK: upper arms level and out, hinge facing forward, fists beside the ears at (+-1.70, 1.40) / squeezed (+-1.60, 1.38)
	local F_DBL = merge(STAND, arms({ 83, 1, 60 }, { 105, 0, 0 }, { 20, -54, 0 }), { Waist = { 10, 0, 0 }, Neck = { 16, 0, 0 } })
	local F_DBL2 = merge(STAND, arms({ 80, 1, 63 }, { 113, 0, 0 }, { 30, -49, 0 }), { Waist = { 13, 0, 0 }, Neck = { 20, 0, 0 } })
	-- the swing between the two poses: arms dropped to a half-way so no joint turns >= 180 deg in one key
	local F_SWING = merge(SOFT, arms({ 40, 30, 30 }, { 70, 0, 0 }, { 10, 0, 0 }), { Waist = { -6, -16, 0 }, Neck = { 4, 16, 0 } })
	local F_SIDE = merge(WIDE, arms({ 52, 70, -40 }, { 72, 0, 0 }, { 10, 0, 0 }, { 4, -96, -32 }, { 68, 0, 0 }, { 25, 0, 0 }), {
		Waist = { 8, -32, 0 }, Neck = { 14, 34, 0 },
	})
	local F_SIDE2 = merge(F_SIDE, {
		Waist = { 12, -36, 0 }, Neck = { 20, 38, 0 },
		LeftShoulder = { 8, -96, -36 }, LeftElbow = { 78, 0, 0 }, RightShoulder = { 54, 70, -42 },
	})
	-- (2026-11-08) the strain tremor is in the torso and head only: shaking the shoulders made both arms jitter like
	-- they were twitching on their own. The arms hold the pose and only ride the body.
	local SHAKE_DBL = { Waist = true, Neck = true }
	local SHAKE_SIDE = { Waist = true, Neck = true }

	clips.Flex = {
		length = 2.6, fadeIn = 0.08, fadeOut = 0.3,
		keys = seq(
			{
				key(0.16, F_ANTIC, "Quad", "Out"),
				key(0.4, F_DBL, "Quart", "Out"),
				key(0.54, F_DBL2, "Quad", "Out"),
			},
			tremble(0.54, 0.94, 6, F_DBL2, SHAKE_DBL, 1.2, 0),
			{
				key(1.02, F_DBL, "Quad", "Out"),
				key(1.12, F_DBL2, "Quart", "Out"),
				key(1.24, F_SWING, "Quad", "In"),
				key(1.38, F_SIDE, "Quart", "Out"),
				key(1.52, F_SIDE2, "Quad", "Out"),
			},
			tremble(1.52, 2.08, 8, F_SIDE2, SHAKE_SIDE, 1.2, 0),
			{ key(2.4, REST, "Sine", "InOut") }
		),
	}
	fx.Flex = {
		{ t = 0.38, kind = "whoosh", pitch = 1.15, volume = 0.4 },
		{ t = 0.4, kind = "flash", part = "UpperTorso", color = GOLD, size = 9 },
		{ t = 0.4, kind = "spark", part = "RightHand", n = 12, color = SUN },
		{ t = 0.4, kind = "spark", part = "LeftHand", n = 12, color = SUN },
		{ t = 0.4, kind = "text", text = "FLEX!", c0 = SUN, c1 = GOLD, size = 7, hold = 0.68, rot = -6 },
		{ t = 1.12, kind = "spark", part = "RightHand", n = 10, color = WHITE },
		{ t = 1.12, kind = "spark", part = "LeftHand", n = 10, color = WHITE },
		{ t = 1.36, kind = "whoosh", pitch = 0.95, volume = 0.4 },
		{ t = 1.38, kind = "flash", part = "LeftHand", color = EMBER, size = 7 },
		{ t = 1.38, kind = "text", text = "PURE POWER!", c0 = SUN, c1 = EMBER, size = 7, hold = 0.85, rot = 6 },
		{ t = 1.6, kind = "spark", part = "UpperTorso", n = 18, color = GOLD },
	}
	glyph.Flex = "筋"

	-------------------------------------------------------------------------------------------------------------------
	-- SHRUG (1.8 s): a little dip, then the shoulders hiked up to the ears, forearms out with the palms turned up, the
	-- hip popped and the head tipped right - a beat, a half-drop and a second shrug with the head tipped left - then
	-- the whole body deflates and settles.
	-- IK: elbows tucked by the sides, forearms out and forward (wrist at (+-1.62, -0.42, -0.72)), palms turned up
	local S_ARMS = arms({ 22, -41, -6, pos = V(0, 0.24, 0) }, { 43, 0, 0 }, { 0, -67, 0 })
	local S_ARMS2 = arms({ 24, -43, -7, pos = V(0, 0.27, 0) }, { 48, 0, 0 }, { 0, -70, 0 })
	local S_ARMS_MID = arms({ 16, -30, -4, pos = V(0, 0.08, 0) }, { 35, 0, 0 }, { 0, -50, 0 })
	local S_ANTIC = merge(STAND, arms({ 6, 0, 10, pos = V(0, -0.05, 0) }, { 30, 0, 0 }, { 0, 0, 0 }), {
		Waist = { -5, 0, 0 }, Neck = { -6, 0, 0 },
	})
	local S_UP = merge(sway(STAND, 0.14), S_ARMS, { Waist = { 4, 0, 4 }, Neck = { -2, 6, -18 } })
	local S_UP2 = merge(sway(STAND, 0.14), S_ARMS2, { Waist = { 5, 0, 5 }, Neck = { -3, 8, -22 } })
	local S_MID = merge(STAND, S_ARMS_MID, { Waist = { 2, 0, 0 }, Neck = { -4, 0, -4 } })
	local S_UP_L = merge(sway(STAND, -0.14), S_ARMS, { Waist = { 4, 0, -4 }, Neck = { -2, -6, 18 } })
	local S_UP_L2 = merge(sway(STAND, -0.14), S_ARMS2, { Waist = { 5, 0, -5 }, Neck = { -3, -8, 22 } })
	local S_DROP = merge(STAND, arms({ 8, 0, 12, pos = V(0, -0.06, 0) }, { 20, 0, 0 }, { 0, 0, 0 }), {
		Waist = { -7, 0, 0 }, Neck = { -10, 0, 0 },
	})

	clips.Shrug = {
		length = 1.8, fadeIn = 0.06, fadeOut = 0.25,
		keys = {
			key(0.12, S_ANTIC, "Quad", "Out"),
			key(0.32, S_UP, "Quart", "Out"),
			key(0.5, S_UP2, "Sine", "InOut"),
			key(0.7, S_MID, "Quad", "InOut"),
			key(0.88, S_UP_L, "Quart", "Out"),
			key(1.06, S_UP_L2, "Sine", "InOut"),
			key(1.3, S_DROP, "Quad", "In"),
			key(1.6, REST, "Sine", "InOut"),
		},
	}
	fx.Shrug = {
		{ t = 0.3, kind = "whoosh", pitch = 1.5, volume = 0.22 },
		{ t = 0.32, kind = "text", text = "WHO KNOWS?", c0 = WHITE, c1 = SKY, size = 6, hold = 1, rot = 8 },
		{ t = 0.32, kind = "spark", part = "RightHand", n = 6, color = WHITE },
		{ t = 0.32, kind = "spark", part = "LeftHand", n = 6, color = WHITE },
		{ t = 0.86, kind = "whoosh", pitch = 1.7, volume = 0.18 },
		{ t = 0.88, kind = "spark", part = "RightHand", n = 5, color = SKY },
		{ t = 0.88, kind = "spark", part = "LeftHand", n = 5, color = SKY },
	}
	glyph.Shrug = "謎"

	return { clips = clips, fx = fx, glyph = glyph }
end
