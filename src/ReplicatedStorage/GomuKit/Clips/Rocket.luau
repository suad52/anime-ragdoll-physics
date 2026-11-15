--!nocheck
-- GomuKit.Clips.Rocket (owner: rocket): the E - Gum-Gum ROCKET clips. Returns function(H) -> {
--   Rocket_Reach    0 -> Windup (0.36): the double throw - chest flung at the anchor, both shoulders driven after it
--   Rocket_Tension  Windup -> launch (0.16): the slingshot sit - dragged back on his heels, chest up, a strain tremble
--   Rocket_Fly      launch -> arrival (0.18 - 0.55): body horizontal, chin up, legs trailing, a corkscrew roll
--   Rocket_Slam     arrival: shoulder-first contact, a deep crouch with a fist to the floor, then back to the guard }
-- Client.Rocket plays them in sequence (each new one fades in over the last; the old track is stopped).
-- The arms are stretched (hidden) through Reach / Tension / Fly, so those keys sell the BODY only; Slam poses the arms
-- because they have snapped home by then.
-- Signs (Clips header): flexion +X (knee -X), Waist -X leans forward, +Y turns left, right limb out Z+, left out Z-,
-- Root pos -Y crouches / +Z slides back, Root rx -X pitches forward. Root (x, y) = Rx * Ry: y rolls the body about its
-- own long axis AFTER the pitch, so the fly roll is a corkscrew round the flight line (keys 90 deg apart).
-- Not FK-checked on a rig (speed pass): grounded keys reuse the verified WIDE / CROUCH legs at their own root heights.
return function(H)
	local merge = H.merge
	local WIDE, CROUCH, GUARD, STAND = H.WIDE, H.CROUCH, H.GUARD, H.STAND
	local function lroot(x, y, z, rx, ry, rz)
		return { Root = { rx or 0, ry or 0, rz or 0, pos = Vector3.new(x or 0, y or 0, z or 0) } }
	end
	local function k(t, pose, style, dir)
		return { t = t, ease = { style or "Quad", dir or "Out" }, pose = pose }
	end
	-- both arms thrown at the anchor (hidden while stretched; posed so nothing pops when the stretch ends early)
	local ARMS_FWD = {
		RightShoulder = { 92, 0, 10 }, RightElbow = { 4, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 92, 0, -10 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { 0, 0, 0 },
	}

	-- REACH: 0.06 the snap (chest flung forward), 0.20 leaning after the fists, 0.36 the grip jolt
	local THROW = merge(WIDE, lroot(0, -0.6, -0.1, -6, 0, 0), ARMS_FWD, { Waist = { -20, 0, 0 }, Neck = { 16, 0, 0 } })
	local LEAN = merge(WIDE, lroot(0, -0.65, -0.05, -8, 0, 0), ARMS_FWD, { Waist = { -26, 0, 0 }, Neck = { 20, 0, 0 } })
	local GRIP = merge(WIDE, lroot(0, -0.65, 0.1, -4, 0, 0), ARMS_FWD, { Waist = { -18, 0, 0 }, Neck = { 14, 0, 0 } })

	-- TENSION: dragged back into a sit, heels digging in, chest up and back, the head still on the anchor
	local PULL = merge(CROUCH, lroot(0, -0.7, 0.45, 0, 0, 0), ARMS_FWD, { Waist = { 10, 0, 0 }, Neck = { -6, 0, 0 } })
	local STRAIN = merge(CROUCH, lroot(0, -0.7, 0.55, 0, 0, 0), ARMS_FWD, { Waist = { 14, 0, 0 }, Neck = { -8, 0, 0 } })
	local TREMBLE = H.tremble(0.06, 0.16, 3, STRAIN, { Waist = true, Neck = true }, 2)

	-- FLY: horizontal (pitched 80 forward), chin up, arms past the head, legs trailing with pointed toes
	local FLY = {
		Waist = { -4, 0, 0 }, Neck = { 42, 0, 0 },
		RightShoulder = { 172, 0, 8 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 172, 0, -8 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { -8, 0, -6 }, LeftKnee = { -26, 0, 0 }, LeftAnkle = { 34, 0, 0 },
		RightHip = { -14, 0, 8 }, RightKnee = { -10, 0, 0 }, RightAnkle = { 34, 0, 0 },
	}
	local function fly(pitch, roll)
		return merge(FLY, lroot(0, 0.3, 0, pitch, roll, 0))
	end

	-- SLAM: 0.05 shoulder first (twisted, the right shoulder leading), 0.12 IMPACT (deep crouch, right fist to the
	-- floor, left arm flung back), 0.30 the hold, 0.52 up into the guard
	local SHOULDER = merge(CROUCH, lroot(0, -0.6, -0.2, -18, 0, 0), {
		Waist = { -26, 22, 0 }, Neck = { 12, -14, 0 },
		RightShoulder = { 70, 0, 40 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 20, 0, -60 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local IMPACT = merge(CROUCH, {
		Waist = { -32, 0, 0 }, Neck = { 26, 0, 0 },
		RightShoulder = { 44, 0, 26 }, RightElbow = { 18, 0, 0 }, RightWrist = { 10, 0, 0 },
		LeftShoulder = { -34, 0, -52 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SETTLE = merge(IMPACT, { Waist = { -28, 4, 0 }, Neck = { 22, -4, 0 } })
	local RISE = merge(GUARD, { Waist = { -10, -12, 0 } })

	local tension = { k(0.06, PULL, "Back", "Out") }
	for _, key in ipairs(TREMBLE) do
		table.insert(tension, key)
	end

	local flyKeys = {
		k(0.05, fly(-45, 0), "Quad", "Out"),
		k(0.10, fly(-80, 0), "Quad", "Out"),
	}
	for i = 1, 8 do
		table.insert(flyKeys, k(0.10 + i * 0.06, fly(-80, i * 90), "Linear", "Out"))
	end

	return {
		Rocket_Reach = { length = 0.42, fadeIn = 0.05, fadeOut = 0.05, keys = {
			k(0.06, THROW, "Exponential", "Out"),
			k(0.20, LEAN, "Sine", "Out"),
			k(0.36, GRIP, "Back", "Out"),
		} },
		Rocket_Tension = { length = 0.34, fadeIn = 0.04, fadeOut = 0.05, keys = tension },
		Rocket_Fly = { length = 0.62, fadeIn = 0.04, fadeOut = 0.05, keys = flyKeys },
		Rocket_Slam = { length = 0.64, fadeIn = 0.04, fadeOut = 0.12, keys = {
			k(0.05, SHOULDER, "Quad", "Out"),
			k(0.12, IMPACT, "Exponential", "Out"),
			k(0.30, SETTLE, "Sine", "InOut"),
			k(0.52, RISE, "Back", "Out"),
		} },
	}
end
