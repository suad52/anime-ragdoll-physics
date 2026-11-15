--!nocheck
-- GomuKit.Clips.Gatling (owner: gatling): Q, Gum-Gum GATLING. Returns function(H) -> clips (merged by name by the base).
--   Gatling_Barrage - the whole cast on the cast clock (t = seconds after t0; Client.Gatling plays it with startAt = e)
--   Gatling_Windup / Gatling_Loop / Gatling_Final - the same keys split and re-timed from 0 (for previews / reuse)
-- Beats (Config.Gatling: Windup 0.28, storm to 1.78, FinalAt 1.86, Lock 2.0):
--   0.12 INHALE (chest up, head back, both elbows flung back) | 0.28 PUFF (Back Out: the deep sit, cheeks puffed,
--   elbows back) | 0.32 .. 1.70 THE STORM: the chest pumps L/R every 0.05 (Waist yaw +-16 with a forward lean, the
--   shoulders thrown forward in turn, the head held on the target), the root shuddering (+-0.05 bob, +-1.5 deg) and a
--   slow 0.25 slide back | 1.76 COCK (Quad In: chest wound right, the right fist drawn back, the left reaching out) |
--   1.86 THRUST (Exponential Out: the heavy right cross, chest whipped left, a lunge) | 1.93 OVER (Back Out) | 2.08 HOLD
--   | 2.40 REST. The stretched arms are drawn by Client.Shared (the real arms are hidden while out), so this sells the
--   BODY. Legs: LOW (storm) and WIDE (final) are the base's FK-verified stances.
return function(H)
	local merge, key = H.merge, H.key
	local LOW, WIDE, REST, PUFF = H.LOW, H.WIDE, H.REST, H.PUFF
	local V = Vector3.new

	local INHALE = merge(LOW, {
		Root = { 4, 0, 0, pos = V(0, -0.25, 0.15) },
		Waist = { 16, 0, 0 }, Neck = { 16, 0, 0 },
		RightShoulder = { -55, 0, 38 }, RightElbow = { 100, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -55, 0, -38 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local SIT = merge(PUFF, {
		Root = { -2, 0, 0, pos = V(0, -0.62, 0.2) },
		Waist = { 6, 0, 0 }, Neck = { 6, 0, 0 },
	})

	-- one storm beat: s = 1 right shoulder forward, -1 left; k = 0..1 through the storm
	local function pump(s, k, i)
		local bob = (i % 2 == 0) and -0.05 or 0.05
		local pose = merge(LOW, {
			Root = { (i % 2 == 0) and -1.5 or 1.5, 0, s * 1.2, pos = V(0, -0.58 + bob, 0.12 + 0.25 * k) },
			Waist = { -14, 16 * s, 0 }, Neck = { -4, -13 * s, 0 },
		})
		if s > 0 then
			pose.RightShoulder = { 88, 0, 12 }
			pose.RightElbow = { 10, 0, 0 }
			pose.LeftShoulder = { -25, 0, -28 }
			pose.LeftElbow = { 110, 0, 0 }
		else
			pose.LeftShoulder = { 88, 0, -12 }
			pose.LeftElbow = { 10, 0, 0 }
			pose.RightShoulder = { -25, 0, 28 }
			pose.RightElbow = { 110, 0, 0 }
		end
		pose.RightWrist = { 0, 0, 0 }
		pose.LeftWrist = { 0, 0, 0 }
		return pose
	end

	local COCK = merge(WIDE, {
		Root = { 0, 0, 0, pos = V(0, -0.62, 0.45) },
		Waist = { -6, -40, 0 }, Neck = { -4, 32, 0 },
		RightShoulder = { 20, 0, 42 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 82, 0, -18 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local THRUST = merge(WIDE, {
		Root = { -4, 0, 0, pos = V(0, -0.72, -0.5) },
		Waist = { -20, 46, 0 }, Neck = { -6, -32, 0 },
		RightShoulder = { 92, 0, 10 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -30, 0, -32 }, LeftElbow = { 104, 0, 0 }, LeftWrist = { 0, 0, 0 },
	})
	local OVER = merge(THRUST, {
		Root = { -6, 0, 0, pos = V(0, -0.75, -0.6) },
		Waist = { -24, 54, 0 }, Neck = { -8, -38, 0 },
	})
	local HOLD = merge(THRUST, {
		Root = { -3, 0, 0, pos = V(0, -0.7, -0.45) },
		Waist = { -16, 40, 0 }, Neck = { -4, -28, 0 },
	})

	local windup = {
		key(0.12, INHALE, "Quad", "Out"),
		key(0.28, SIT, "Back", "Out"),
	}
	local loop = {}
	local t, i, s = 0.32, 0, 1
	while t <= 1.70 + 1e-6 do
		local k = (t - 0.32) / (1.70 - 0.32)
		table.insert(loop, key(t, pump(s, k, i), "Sine", "InOut"))
		t += 0.05
		i += 1
		s = -s
	end
	local final = {
		key(1.76, COCK, "Quad", "In"),
		key(1.86, THRUST, "Exponential", "Out"),
		key(1.93, OVER, "Back", "Out"),
		key(2.08, HOLD, "Sine", "InOut"),
		key(2.40, REST, "Sine", "Out"),
	}

	local function shifted(list, dt)
		local out = {}
		for _, k in ipairs(list) do
			table.insert(out, { t = math.max(k.t - dt, 0), ease = k.ease, pose = k.pose })
		end
		return out
	end
	local all = {}
	for _, list in ipairs({ windup, loop, final }) do
		for _, k in ipairs(list) do
			table.insert(all, k)
		end
	end

	return {
		Gatling_Barrage = { length = 2.45, fadeIn = 0.06, fadeOut = 0.2, strikeAt = 1.86, keys = all },
		Gatling_Windup = { length = 0.34, fadeIn = 0.06, fadeOut = 0.1, keys = windup },
		Gatling_Loop = { length = 1.42, fadeIn = 0.05, fadeOut = 0.1, keys = shifted(loop, 0.3) },
		Gatling_Final = { length = 0.72, fadeIn = 0.05, fadeOut = 0.2, strikeAt = 0.12, keys = shifted(final, 1.74) },
	}
end
