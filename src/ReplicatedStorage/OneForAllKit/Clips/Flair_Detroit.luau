--!nocheck
-- Clips pass "Flair_Detroit": DETROIT SMASH, the flair cut (replaces Clips.Detroit).
-- Keyed to Config Detroit.Charge = 0.66: the STRIKE key sits exactly on it, and every client then holds the pose for
-- Detroit.FreezeTime (0.14 s), so every later key plays 0.14 s later in server time (REST lands ~1.54, Lock is 1.6).
--   0.08 TELL      a breath in: he rises a touch, both fists come up
--   0.20 PLANT     Back Out: he slams into the split stance, chest wrenched right, fist to the hip, left palm aiming
--   0.20-0.52      the strain: six tremble keys that sink him deeper while the shake grows (1.2 -> 3.0 deg)
--   0.585 COCK     the last pull back (the anticipation runs opposite to the punch)
--   0.635 FIRE     the breakdown: the hips whip left first, the fist trails low past the hip
--   0.66 STRIKE    Expo Out: the arm straight down the aim, chest whipped left, left fist ripped back, back leg driven
--   0.72 OVER      Back Out overshoot, sinking into the lunge
--   0.80-0.93      the HELD arm: still out, smoking, shaking a little from the strain
--   1.06 EXHALE / 1.22 RECOVER (arm hanging, wrist limp) / 1.40 REST
-- FK-checked on an R15 preview rig (signs as in the base Clips header): every key and a 0.01 s sweep keep the planted
-- feet within 0.08 of the floor and flat, nothing passes through the torso or head, and at STRIKE / OVER / HOLD the
-- shoulder -> fist line points down the aim to within 2 degrees.
return function(H)
	local merge = H.merge
	local V = Vector3.new

	local function R(x, y, z, ry)
		return { Root = { 0, ry or 0, 0, pos = V(x, y, z) } }
	end

	local TELL = merge(R(0, -0.08, 0.05), {
		Waist = { 6, -6, 0 }, Neck = { 6, 4, 0 },
		RightShoulder = { 40, 0, 12 }, RightElbow = { 96, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { 44, 0, -12 }, LeftElbow = { 92, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 21, 0, 0 }, LeftKnee = { -36, 0, 0 }, LeftAnkle = { 15, 0, 0 },
		RightHip = { 21, 0, 0 }, RightKnee = { -36, 0, 0 }, RightAnkle = { 15, 0, 0 },
	})
	local PLANT = merge(R(0, -0.72, 0.2, -8), {
		Waist = { -10, -30, 0 }, Neck = { 6, 36, 0 },
		RightShoulder = { -44, 0, 32 }, RightElbow = { 112, 0, 0 }, RightWrist = { -10, 0, 0 },
		LeftShoulder = { 84, -7, -19 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -34, 0, 0 },
		LeftHip = { 73, -11, -14 }, LeftKnee = { -72, 0, 0 }, LeftAnkle = { -1, 0, 11 },
		RightHip = { -28, 22, 14 }, RightKnee = { -41, 0, 0 }, RightAnkle = { 67, 0, 0 },
	})
	local DEEP = merge(R(0, -0.84, 0.26, -12), {
		Waist = { -14, -40, 0 }, Neck = { 4, 48, 0 },
		RightShoulder = { -56, 0, 38 }, RightElbow = { 124, 0, 0 }, RightWrist = { -16, 0, 0 },
		LeftShoulder = { 98, 0, -32 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -38, 0, 0 },
		LeftHip = { 80, -6, -23 }, LeftKnee = { -78, 0, 0 }, LeftAnkle = { -5, 0, 7 },
		RightHip = { -18, 27, 13 }, RightKnee = { -63, 0, 0 }, RightAnkle = { 78, 0, -1 },
	})
	local COCK = merge(R(0, -0.88, 0.3, -14), {
		Waist = { -16, -46, 0 }, Neck = { 2, 54, 0 },
		RightShoulder = { -62, 0, 42 }, RightElbow = { 128, 0, 0 }, RightWrist = { -18, 0, 0 },
		LeftShoulder = { 106, 0, -39 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { -40, 0, 0 },
		LeftHip = { 85, -2, -30 }, LeftKnee = { -80, 0, 0 }, LeftAnkle = { -6, 0, 1 },
		RightHip = { -16, 30, 13 }, RightKnee = { -66, 0, 0 }, RightAnkle = { 82, 0, -1 },
	})
	local FIRE = merge(R(0, -0.8, 0.05, 10), {
		Waist = { -16, -22, 0 }, Neck = { 6, 14, 0 },
		RightShoulder = { 14, 0, 10 }, RightElbow = { 98, 0, 0 }, RightWrist = { -6, 0, 0 },
		LeftShoulder = { 34, 0, -34 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 77, 1, -5 }, LeftKnee = { -53, 0, 0 }, LeftAnkle = { -24, 0, 0 },
		RightHip = { -28, -2, 9 }, RightKnee = { -42, 0, 0 }, RightAnkle = { 68, 0, -6 },
	})
	local STRIKE = merge(R(0, -0.62, -0.5, 14), {
		Waist = { -18, 26, 0 }, Neck = { 10, -38, 0 },
		RightShoulder = { 117, -8, 23 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
		LeftShoulder = { -48, 0, -28 }, LeftElbow = { 46, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 69, -17, 6 }, LeftKnee = { -50, 0, 0 }, LeftAnkle = { -14, 0, 11 },
		RightHip = { -41, -14, 7 }, RightKnee = { -9, 0, 0 }, RightAnkle = { 48, 0, -11 },
	})
	local OVER = merge(R(0, -0.68, -0.56, 16), {
		Waist = { -21, 30, 0 }, Neck = { 12, -44, 0 },
		RightShoulder = { 103, 13, 29 }, RightElbow = { 0, 0, 0 }, RightWrist = { 4, 0, 0 },
		LeftShoulder = { -54, 0, -30 }, LeftElbow = { 52, 0, 0 }, LeftWrist = { 6, 0, 0 },
		LeftHip = { 73, -14, 6 }, LeftKnee = { -57, 0, 0 }, LeftAnkle = { -13, 0, 10 },
		RightHip = { -45, -11, 4 }, RightKnee = { -9, 0, 0 }, RightAnkle = { 52, 0, -7 },
	})
	local HOLD = merge(R(0, -0.64, -0.52, 14), {
		Waist = { -17, 28, 0 }, Neck = { 12, -40, 0 },
		RightShoulder = { 103, 0, 25 }, RightElbow = { 4, 0, 0 }, RightWrist = { 6, 0, 0 },
		LeftShoulder = { -46, 0, -28 }, LeftElbow = { 56, 0, 0 }, LeftWrist = { 4, 0, 0 },
		LeftHip = { 71, -16, 6 }, LeftKnee = { -54, 0, 0 }, LeftAnkle = { -13, 0, 10 },
		RightHip = { -37, -14, 8 }, RightKnee = { -18, 0, 0 }, RightAnkle = { 52, 0, -11 },
	})
	-- the held arm shaking from the strain (secondary motion while it smokes)
	local HOLD_A = merge(HOLD, { RightShoulder = { 104.5, 0, 26 }, Neck = { 13, -41, 0 }, Waist = { -18, 29, 0 } })
	local HOLD_B = merge(HOLD, { RightShoulder = { 102, 0, 24.5 }, Neck = { 11, -39, 0 } })
	local EXHALE = merge(R(0, -0.56, -0.3, 6), {
		Waist = { -10, 14, 0 }, Neck = { 4, -16, 0 },
		RightShoulder = { 66, 0, 24 }, RightElbow = { 22, 0, 0 }, RightWrist = { 12, 0, 0 },
		LeftShoulder = { 4, 0, -24 }, LeftElbow = { 52, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 59, -6, -5 }, LeftKnee = { -31, 0, 0 }, LeftAnkle = { -27, 0, 5 },
		RightHip = { -18, 8, 10 }, RightKnee = { -42, 0, 0 }, RightAnkle = { 58, 0, -4 },
	})
	local RECOVER = merge(R(0, -0.45, -0.05), {
		Waist = { -8, 4, 0 }, Neck = { 2, -4, 0 },
		RightShoulder = { 28, 0, 22 }, RightElbow = { 48, 0, 0 }, RightWrist = { 20, 0, 0 },
		LeftShoulder = { 16, 0, -18 }, LeftElbow = { 48, 0, 0 }, LeftWrist = { 0, 0, 0 },
		LeftHip = { 54, 2, -10 }, LeftKnee = { -75, 0, 0 }, LeftAnkle = { 22, 0, 2 },
		RightHip = { 21, 3, 8 }, RightKnee = { -72, 0, 0 }, RightAnkle = { 51, 0, -5 },
	})

	-- the strain: n keys that carry pose a towards pose b while a tremble grows from amp0 to amp1 degrees
	local function strain(t0, t1, n, a, b, joints, amp0, amp1)
		local keys = {}
		for i = 1, n do
			local u = i / n
			local s = (i % 2 == 0) and 1 or -1
			local amp = amp0 + (amp1 - amp0) * u
			local p = {}
			for name, va in pairs(a) do
				local vb = b[name] or va
				local x = (va[1] or 0) + ((vb[1] or 0) - (va[1] or 0)) * u
				local y = (va[2] or 0) + ((vb[2] or 0) - (va[2] or 0)) * u
				local z = (va[3] or 0) + ((vb[3] or 0) - (va[3] or 0)) * u
				if joints[name] then
					x += amp * s
					y += amp * 0.6 * s
				end
				local pos = va.pos
				if va.pos and vb.pos then
					pos = va.pos:Lerp(vb.pos, u)
				end
				p[name] = { x, y, z, pos = pos }
			end
			table.insert(keys, { t = t0 + (t1 - t0) * u, ease = { "Sine", "InOut" }, pose = p })
		end
		return keys
	end

	local keys = {
		{ t = 0.08, ease = { "Sine", "Out" }, pose = TELL },
		{ t = 0.2, ease = { "Back", "Out" }, pose = PLANT },
	}
	for _, k in ipairs(strain(0.2, 0.52, 6, PLANT, DEEP,
		{ Waist = true, Neck = true, RightShoulder = true, RightElbow = true, LeftShoulder = true }, 1.2, 3.0)) do
		table.insert(keys, k)
	end
	for _, k in ipairs({
		{ t = 0.585, ease = { "Quad", "Out" }, pose = COCK },
		{ t = 0.635, ease = { "Quad", "In" }, pose = FIRE },
		{ t = 0.66, ease = { "Exponential", "Out" }, pose = STRIKE }, -- = Detroit.Charge: the money frame, held 0.14
		{ t = 0.72, ease = { "Back", "Out" }, pose = OVER },
		{ t = 0.8, ease = { "Sine", "InOut" }, pose = HOLD_A },
		{ t = 0.87, ease = { "Sine", "InOut" }, pose = HOLD_B },
		{ t = 0.93, ease = { "Sine", "InOut" }, pose = HOLD },
		{ t = 1.06, ease = { "Sine", "InOut" }, pose = EXHALE },
		{ t = 1.22, ease = { "Quad", "InOut" }, pose = RECOVER },
		{ t = 1.4, ease = { "Sine", "InOut" }, pose = H.REST },
	}) do
		table.insert(keys, k)
	end

	return {
		Detroit = { length = 1.48, fadeIn = 0.06, fadeOut = 0.18, keys = keys, strikeAt = 0.66 },
	}
end
