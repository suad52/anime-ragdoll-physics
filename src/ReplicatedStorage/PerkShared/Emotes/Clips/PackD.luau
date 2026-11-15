--!nocheck
-- PerkShared.Emotes.Clips.PackD (2026-11-11, "wiki extras"): 10 emotes covering every emote KIND. Same clip format and
-- joint signs as the Clips header (elbows are hinges: X only, 0..140; legs only use the FK-verified stances). Each
-- clip may carry a KIND flag that PerkShared.Emotes / ServerScriptService.PerkEmotes act on:
--   traversal = true   WALKING emotes: the legs are left to the walk animation (no leg / Root-free keys except the hop's
--                      bob), moving does not cancel them (STRUT, BUNNY HOP)
--   partner = "duo" | "group"   others join through a JOIN prompt over the emoter (one / any number) and play the same
--                      clip (HIGH FIVE, HYPE CIRCLE)
--   needsBody = true   only next to a KO'd body (PAY RESPECTS leaves flowers, FLAG PLANT plants your colour)
--   sign = true        INTERACTIVE: the player types a line; the server filters it and every client shows it (SIGN)
--   (prop beats)       INTERACTIVE placement: FIREWORK sets a rocket down that launches and bursts after the emote
--   cosmetic = true    a glow stays on the body after the emote until death; playing it again removes it (GLOW UP)
--   NEON SALUTE is EXCLUSIVE (PerkCatalog.EMOTES exclusive = true): never rolled, only from the code <code redacted>.
-- New flair beat: { t, kind = "prop", prop = "flowers" | "flag" | "sign" | "firework", life, launch? } (PerkShared.Emotes).
return function(K)
	local V, key, merge, tremble = K.V, K.key, K.merge, K.tremble
	local STAND, LOW, CROUCH = K.STAND, K.LOW, K.CROUCH
	local GOLD, SUN, WHITE, EMBER, RED, C = K.GOLD, K.SUN, K.WHITE, K.EMBER, K.RED, K.C
	local CYAN = C(90, 220, 255)
	local REST = merge(STAND, K.RELAX, K.RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })
	local UP_REST = merge(K.RELAX, K.RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } }) -- upper body only (walking emotes)
	local HIP_R = { RightShoulder = { -62, 32, 26 }, RightElbow = { 88, 0, 0 }, RightWrist = { 10, -6, 0 } } -- the IK fist-on-hip
	local HIP_L = { LeftShoulder = { -62, -32, -26 }, LeftElbow = { 88, 0, 0 }, LeftWrist = { 10, 6, 0 } }

	local clips, fx = {}, {}
	local function alternate(t0, t1, step, a, b, style)
		local keys, t, flip = {}, t0, false
		while t <= t1 do
			table.insert(keys, key(t, flip and b or a, style or "Sine", "InOut"))
			flip = not flip
			t += step
		end
		return keys
	end
	local function cat(...)
		local out = {}
		for _, l in ipairs({ ... }) do
			for _, v in ipairs(l) do
				table.insert(out, v)
			end
		end
		return out
	end

	-----------------------------------------------------------------------------------------------
	-- STRUT (walking, 8 s): chest proud, chin up, big confident arm swings and a little head bob - walk anywhere.
	local S_A = { Waist = { 6, 9, 0 }, Neck = { 10, -5, 0 },
		RightShoulder = { 34, 0, 10 }, RightElbow = { 32, 0, 0 }, RightWrist = { 8, 0, 0 },
		LeftShoulder = { -26, 0, -10 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { 0, 0, 0 } }
	local S_B = { Waist = { 6, -9, 0 }, Neck = { 10, 5, 0 },
		RightShoulder = { -26, 0, 10 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 34, 0, -10 }, LeftElbow = { 32, 0, 0 }, LeftWrist = { 8, 0, 0 } }
	clips.Strut = { length = 8, fadeIn = 0.2, fadeOut = 0.3, traversal = true,
		keys = cat(alternate(0.25, 7.5, 0.45, S_A, S_B), { key(8, UP_REST, "Sine", "InOut") }) }
	fx.Strut = {
		{ t = 0.3, kind = "text", text = "STRUT", c0 = WHITE, c1 = GOLD, size = 4.5, hold = 1.1, rot = -6 },
		{ t = 2.5, kind = "spark", part = "UpperTorso", n = 6, color = GOLD },
		{ t = 5, kind = "spark", part = "UpperTorso", n = 6, color = GOLD },
	}

	-- BUNNY HOP (walking, 8 s): paws up at the chest, the whole body bouncing - hop around.
	local PAWS = { RightShoulder = { 62, 0, 12 }, RightElbow = { 118, 0, 0 }, RightWrist = { 50, 0, 0 },
		LeftShoulder = { 62, 0, -12 }, LeftElbow = { 118, 0, 0 }, LeftWrist = { 50, 0, 0 } }
	local H_UP = merge(PAWS, { Root = { 0, 0, 0, pos = V(0, 0.55, 0) }, Waist = { 4, 0, 0 }, Neck = { 8, 0, 0 } })
	local H_DOWN = merge(PAWS, { Root = { 0, 0, 0, pos = V(0, 0, 0) }, Waist = { -6, 0, 0 }, Neck = { -4, 0, 0 } })
	clips.BunnyHop = { length = 8, fadeIn = 0.15, fadeOut = 0.3, traversal = true,
		keys = cat(alternate(0.2, 7.6, 0.22, H_UP, H_DOWN, "Quad"), { key(8, merge(UP_REST, { Root = { 0, 0, 0, pos = V(0, 0, 0) } }), "Sine", "InOut") }) }
	fx.BunnyHop = {
		{ t = 0.3, kind = "text", text = "HOP HOP!", c0 = WHITE, c1 = C(255, 170, 205), size = 4.5, hold = 1, rot = 8 },
	}

	-----------------------------------------------------------------------------------------------
	-- HIGH FIVE (partner: one, 2.8 s): wind up, slap the hand high, then a pumped double fist. A friend joins through
	-- the JOIN prompt and does it back.
	local HF_WIND = merge(STAND, K.RELAX, { Waist = { -6, -14, 0 }, Neck = { 6, 10, 0 },
		RightShoulder = { 120, 0, 30 }, RightElbow = { 70, 0, 0 }, RightWrist = { -20, 0, 0 } })
	local HF_HIT = merge(STAND, K.RELAX, { Waist = { 4, -6, 0 }, Neck = { 12, 4, 0 },
		RightShoulder = { 150, 0, 18 }, RightElbow = { 12, 0, 0 }, RightWrist = { -25, 0, 0 } })
	local HF_YES = merge(LOW, { Waist = { -10, 0, 0 }, Neck = { 14, 0, 0 },
		RightShoulder = { 60, 0, 25 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 60, 0, -25 }, LeftElbow = { 120, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	clips.HighFive = { length = 2.8, fadeIn = 0.1, fadeOut = 0.3, partner = "duo", keys = {
		key(0.35, HF_WIND, "Quad", "Out"), key(0.75, HF_WIND, "Sine", "InOut"), key(0.9, HF_HIT, "Quart", "Out"),
		key(1.3, HF_HIT, "Sine", "InOut"), key(1.6, HF_YES, "Quart", "Out"), key(2.4, HF_YES, "Sine", "InOut"),
		key(2.8, REST, "Sine", "InOut"),
	} }
	fx.HighFive = {
		{ t = 0.9, kind = "flash", part = "RightHand", color = WHITE, size = 5 },
		{ t = 0.9, kind = "text", text = "HIGH FIVE!", c0 = WHITE, c1 = SUN, size = 6, hold = 0.9, rot = -8 },
		{ t = 0.9, kind = "whoosh", pitch = 1.3, volume = 0.4 },
		{ t = 1.6, kind = "spark", part = "RightHand", n = 14, color = GOLD },
	}

	-- HYPE CIRCLE (partner: anyone, 6 s): jumping with both arms up, crouching between - everyone can join in.
	local HC_UP = merge(STAND, { Root = { 0, 0, 0, pos = V(0, 0.45, 0) }, Waist = { 8, 0, 0 }, Neck = { 18, 0, 0 },
		RightShoulder = { 165, 0, 28 }, RightElbow = { 12, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 165, 0, -28 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local HC_DOWN = merge(LOW, { Waist = { -8, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 120, 0, 40 }, RightElbow = { 60, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 120, 0, -40 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	clips.HypeCircle = { length = 6, fadeIn = 0.1, fadeOut = 0.3, partner = "group",
		keys = cat(alternate(0.3, 5.6, 0.35, HC_DOWN, HC_UP, "Quad"), { key(6, REST, "Sine", "InOut") }) }
	fx.HypeCircle = {
		{ t = 0.4, kind = "text", text = "HYPE!", c0 = WHITE, c1 = EMBER, size = 6, hold = 0.9, rot = -6 },
		{ t = 2.4, kind = "text", text = "LET'S GO!", c0 = SUN, c1 = RED, size = 6, hold = 0.9, rot = 6 },
		{ t = 4.4, kind = "text", text = "WOOO!", c0 = WHITE, c1 = GOLD, size = 6, hold = 0.9, rot = -4 },
		{ t = 1, kind = "spark", part = "RightHand", n = 10, color = SUN },
		{ t = 3, kind = "spark", part = "LeftHand", n = 10, color = SUN },
		{ t = 5, kind = "spark", part = "RightHand", n = 10, color = GOLD },
	}

	-----------------------------------------------------------------------------------------------
	-- PAY RESPECTS (next to a KO'd body, 4 s): crouch to set flowers down, then a hand on the heart, head bowed.
	local PR_PLACE = merge(CROUCH, { Waist = { -36, 0, 0 }, Neck = { -18, 0, 0 },
		RightShoulder = { 75, 0, 10 }, RightElbow = { 30, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { 20, 0, -12 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local PR_KNEEL = merge(CROUCH, { Waist = { -14, 0, 0 }, Neck = { -28, 0, 0 },
		RightShoulder = { 48, 0, -18 }, RightElbow = { 118, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -12 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	clips.PayRespects = { length = 4, fadeIn = 0.15, fadeOut = 0.35, needsBody = true, keys = {
		key(0.5, PR_PLACE, "Quad", "Out"), key(1.2, PR_PLACE, "Sine", "InOut"), key(1.6, PR_KNEEL, "Quad", "InOut"),
		key(3.6, PR_KNEEL, "Sine", "InOut"), key(4, REST, "Sine", "InOut"),
	} }
	fx.PayRespects = {
		{ t = 1.2, kind = "prop", prop = "flowers", life = 25 },
		{ t = 1.2, kind = "spark", part = "RightHand", n = 10, color = WHITE },
		{ t = 1.7, kind = "text", text = "R.I.P.", c0 = WHITE, c1 = C(180, 180, 205), size = 5, hold = 1.6, rot = 0 },
	}

	-- FLAG PLANT (next to a KO'd body, 3 s): the flag up overhead, stabbed into the ground, then fists on the hips.
	local FP_RAISE = merge(STAND, { Waist = { 8, 10, 0 }, Neck = { 14, 0, 0 },
		RightShoulder = { 165, 0, 12 }, RightElbow = { 25, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 150, 0, -12 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local FP_STAB = merge(LOW, { Waist = { -28, 0, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { 70, 0, 8 }, RightElbow = { 15, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 62, 0, -8 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local FP_PROUD = merge(STAND, HIP_R, HIP_L, { Waist = { 8, 0, 0 }, Neck = { 18, 0, 0 } })
	clips.FlagPlant = { length = 3, fadeIn = 0.1, fadeOut = 0.3, needsBody = true, keys = {
		key(0.4, FP_RAISE, "Quad", "Out"), key(0.8, FP_RAISE, "Sine", "InOut"), key(1.0, FP_STAB, "Quart", "Out"),
		key(1.5, FP_STAB, "Sine", "InOut"), key(1.9, FP_PROUD, "Quart", "Out"), key(2.7, FP_PROUD, "Sine", "InOut"),
		key(3, REST, "Sine", "InOut"),
	} }
	fx.FlagPlant = {
		{ t = 1.0, kind = "prop", prop = "flag", life = 30 },
		{ t = 1.0, kind = "flash", part = "LowerTorso", color = WHITE, size = 7 },
		{ t = 1.0, kind = "whoosh", pitch = 0.8, volume = 0.45 },
		{ t = 1.9, kind = "text", text = "CLAIMED!", c0 = WHITE, c1 = RED, size = 6, hold = 0.9, rot = 6 },
	}

	-----------------------------------------------------------------------------------------------
	-- SIGN (interactive, 7 s): hold a board up in front - the player types what it says (filtered by the server).
	local SG_HOLD = merge(STAND, { Waist = { 2, 0, 0 }, Neck = { 6, 0, 0 },
		RightShoulder = { 100, 0, 14 }, RightElbow = { 70, 0, 0 }, RightWrist = { -10, 0, 0 },
		LeftShoulder = { 100, 0, -14 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { -10, 0, 0 } })
	local SG_A = merge(SG_HOLD, { Waist = { 2, 6, 0 } })
	local SG_B = merge(SG_HOLD, { Waist = { 2, -6, 0 } })
	clips.Sign = { length = 7, fadeIn = 0.15, fadeOut = 0.3, sign = true,
		keys = cat({ key(0.35, SG_HOLD, "Quad", "Out") }, alternate(1.1, 6.4, 0.8, SG_A, SG_B), { key(7, REST, "Sine", "InOut") }) }
	fx.Sign = {
		{ t = 0.3, kind = "prop", prop = "sign", life = 6.7 },
	}

	-- FIREWORK (interactive, 3.2 s): crouch, set a rocket down, light it, step up and point at the sky - it launches and
	-- bursts a moment after the emote (place several in a row for a show).
	local FW_REACH = merge(LOW, { Waist = { -40, 0, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 80, 0, 8 }, RightElbow = { 25, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 30, 0, -14 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local FW_LIGHT = merge(LOW, { Waist = { -30, 0, 0 }, Neck = { -6, 0, 0 },
		RightShoulder = { 70, 0, 8 }, RightElbow = { 45, 0, 0 }, RightWrist = { 20, 0, 0 },
		LeftShoulder = { 60, 0, -8 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local FW_POINT = merge(STAND, K.RELAX, { Waist = { 10, 0, 0 }, Neck = { 30, 0, 0 },
		RightShoulder = { 168, 0, 15 }, RightElbow = { 5, 0, 0 }, RightWrist = { 0, 0, 0 } })
	clips.Firework = { length = 3.2, fadeIn = 0.1, fadeOut = 0.3, keys = {
		key(0.45, FW_REACH, "Quad", "Out"), key(0.9, FW_REACH, "Sine", "InOut"), key(1.2, FW_LIGHT, "Quad", "InOut"),
		key(1.7, FW_LIGHT, "Sine", "InOut"), key(2.0, FW_POINT, "Quart", "Out"), key(2.9, FW_POINT, "Sine", "InOut"),
		key(3.2, REST, "Sine", "InOut"),
	} }
	fx.Firework = {
		{ t = 0.9, kind = "prop", prop = "firework", life = 7, launch = 2.6 },
		{ t = 1.3, kind = "spark", part = "RightHand", n = 8, color = EMBER },
		{ t = 2.0, kind = "text", text = "WATCH THIS!", c0 = WHITE, c1 = EMBER, size = 5, hold = 0.9, rot = -6 },
	}

	-----------------------------------------------------------------------------------------------
	-- GLOW UP (lasting, 3.2 s): arms crossed and gathering, then flung wide in a gold burst - and the glow stays on
	-- the body until it is KO'd (play it again to switch it off).
	local GU_CROSS = merge(LOW, { Waist = { -12, 0, 0 }, Neck = { -10, 0, 0 },
		RightShoulder = { 70, 0, -22 }, RightElbow = { 110, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 70, 0, 22 }, LeftElbow = { 110, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	local GU_FLING = merge(STAND, { Root = { 0, 0, 0, pos = V(0, 0.25, 0) }, Waist = { 12, 0, 0 }, Neck = { 24, 0, 0 },
		RightShoulder = { 40, 0, 95 }, RightElbow = { 10, 0, 0 }, RightWrist = { -20, 0, 0 },
		LeftShoulder = { 40, 0, -95 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -20, 0, 0 } })
	clips.GlowUp = { length = 3.2, fadeIn = 0.1, fadeOut = 0.35, cosmetic = true, keys = cat(
		{ key(0.5, GU_CROSS, "Quad", "Out") },
		tremble(0.5, 1.2, 4, GU_CROSS, { Waist = true, Neck = true }, 1.2, 0),
		{ key(1.4, GU_FLING, "Quart", "Out"), key(2.6, GU_FLING, "Sine", "InOut"), key(3.2, REST, "Sine", "InOut") }
	) }
	fx.GlowUp = {
		{ t = 0.5, kind = "spark", part = "UpperTorso", n = 10, color = SUN },
		{ t = 1.4, kind = "flash", part = "UpperTorso", color = GOLD, size = 12 },
		{ t = 1.4, kind = "spark", part = "UpperTorso", n = 40, color = SUN },
		{ t = 1.4, kind = "whoosh", pitch = 0.9, volume = 0.5 },
		{ t = 1.45, kind = "text", text = "GLOW UP!", c0 = SUN, c1 = GOLD, size = 7, hold = 1, rot = -5 },
	}

	-- NEON SALUTE (exclusive - the code <code redacted>, 2.4 s): a crisp salute at the brow with a neon burst.
	local SA_UP = merge(STAND, { Waist = { 6, 0, 0 }, Neck = { 10, 0, 0 },
		RightShoulder = { 95, -30, 60 }, RightElbow = { 135, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 0, 0, -4 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { 0, 0, 0 } })
	clips.NeonSalute = { length = 2.4, fadeIn = 0.1, fadeOut = 0.3, keys = {
		key(0.35, SA_UP, "Quart", "Out"), key(1.9, SA_UP, "Sine", "InOut"), key(2.4, REST, "Sine", "InOut"),
	} }
	fx.NeonSalute = {
		{ t = 0.35, kind = "flash", part = "RightHand", color = CYAN, size = 5 },
		{ t = 0.35, kind = "spark", part = "RightHand", n = 24, color = CYAN },
		{ t = 0.4, kind = "text", text = "SALUTE!", c0 = WHITE, c1 = CYAN, size = 5.5, hold = 1.1, rot = -4 },
	}

	return {
		clips = clips,
		fx = fx,
		glyph = { Strut = "闊", BunnyHop = "兔", HighFive = "掌", HypeCircle = "輪", PayRespects = "悼", FlagPlant = "旗",
			Sign = "札", Firework = "火", GlowUp = "輝", NeonSalute = "敬" },
	}
end
