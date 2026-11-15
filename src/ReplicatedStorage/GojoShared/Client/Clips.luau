--!nocheck
-- Clips: procedural keyframes for Gojo's kit - Hollow Purple (Quick + Incantation), Reversal Red, Lapse Blue
-- (grab / hold / throw / fizzle), Domain Expansion - and the 4-hit M1 combo.
-- Signs (measured on the live rig): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X,
-- +Y turns left, right arm out RightShoulder Z+, left arm out LeftShoulder Z-, Neck +X lifts the chin.
-- Root pos is in the HumanoidRootPart's frame: -Y crouches, +Z slides back.
local Clips = {}

local function merge(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end

-- concatenate key lists
local function seq(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			table.insert(out, v)
		end
	end
	return out
end

-- a strain tremble: n keys over (t0, t1] alternating +/- amp degrees on the named joints, around `pose`
local function tremble(t0, t1, n, pose, joints, amp)
	local keys = {}
	for i = 1, n do
		local s = (i % 2 == 0) and 1 or -1
		local p = {}
		for name, v in pairs(pose) do
			if joints[name] then
				if typeof(v) == "CFrame" then
					p[name] = v * CFrame.Angles(math.rad(amp * s), math.rad(amp * 0.6 * s), 0)
				else
					p[name] = { (v[1] or 0) + amp * s, (v[2] or 0) + amp * 0.6 * s, v[3] or 0, pos = v.pos }
				end
			else
				p[name] = v
			end
		end
		table.insert(keys, { t = t0 + (t1 - t0) * i / n, ease = { "Sine", "InOut" }, pose = p })
	end
	return keys
end

local function root(y, z)
	return { Root = { 0, 0, 0, pos = Vector3.new(0, y or 0, z or 0) } }
end

local STAND = {
	Root = { 0, 0, 0, pos = Vector3.zero }, LeftHip = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 },
	RightKnee = { 0, 0, 0 }, LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
}
local PLANT = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.25, 0) }, LeftHip = { 20, 0, -5 }, RightHip = { 20, 0, 5 },
	LeftKnee = { -38, 0, 0 }, RightKnee = { -38, 0, 0 }, LeftAnkle = { 18, 0, 0 }, RightAnkle = { 18, 0, 0 },
}
local DEEP = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.6, 0) }, LeftHip = { 32, 0, -10 }, RightHip = { 32, 0, 10 },
	LeftKnee = { -60, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftAnkle = { 28, 0, 0 }, RightAnkle = { 28, 0, 0 },
}
local LUNGE = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, RightHip = { 34, 0, 5 }, RightKnee = { -46, 0, 0 },
	RightAnkle = { 12, 0, 0 }, LeftHip = { -6, 0, -5 }, LeftKnee = { -34, 0, 0 }, LeftAnkle = { 30, 0, 0 },
}
local LUNGE_DEEP = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.65, -0.3) }, RightHip = { 42, 0, 6 }, RightKnee = { -60, 0, 0 },
	RightAnkle = { 18, 0, 0 }, LeftHip = { -14, 0, -6 }, LeftKnee = { -30, 0, 0 }, LeftAnkle = { 38, 0, 0 },
}
local LOAD = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0.2) }, RightHip = { 14, 0, 8 }, RightKnee = { -36, 0, 0 },
	RightAnkle = { 22, 0, 0 }, LeftHip = { 26, 0, -10 }, LeftKnee = { -50, 0, 0 }, LeftAnkle = { 24, 0, 0 },
}
local RELAX_L = { LeftShoulder = { 10, 0, -14 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 0, 0, 0 } }
local RELAX_R = { RightShoulder = { 10, 0, 14 }, RightElbow = { 22, 0, 0 }, RightWrist = { 0, 0, 0 } }

---------------------------------------------------------------------------------------------------
-- Hollow Purple
local BLUE_OUT = { LeftShoulder = { 70, 0, -40 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { -40, 0, 0 } }
local BLUE_OUT_WIDE = { LeftShoulder = { 100, 0, -80 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { -40, 0, 0 } } -- still out left while he turns to the red
local RED_OUT = { RightShoulder = { 75, 0, 40 }, RightElbow = { 40, 0, 0 }, RightWrist = { -40, 0, 0 } }
local BLUE_UP = { LeftShoulder = { 50, 0, -86 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { -30, 0, 0 } }
local RED_UP = { RightShoulder = { 50, 0, 86 }, RightElbow = { 26, 0, 0 }, RightWrist = { -30, 0, 0 } }
local HALF_R = { RightShoulder = { 22, 0, 22 }, RightElbow = { 55, 0, 0 }, RightWrist = { 0, 0, 0 } }
local MERGE_ARMS = {
	LeftShoulder = { 70, 0, 55 }, LeftElbow = { 65, 0, 0 }, LeftWrist = { -10, 0, 0 },
	RightShoulder = { 70, 0, -55 }, RightElbow = { 65, 0, 0 }, RightWrist = { -10, 0, 0 },
}
local CUP = {
	LeftShoulder = { 74, 0, -4 }, LeftElbow = { 38, 0, 0 }, LeftWrist = { -20, 0, 0 },
	RightShoulder = { 74, 0, 4 }, RightElbow = { 38, 0, 0 }, RightWrist = { -20, 0, 0 },
}
local ANTIC = {
	RightShoulder = { 25, 0, 18 }, RightElbow = { 140, 0, 0 }, RightWrist = { 10, 0, 0 },
	LeftShoulder = { 85, 0, 18 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -30, 0, 0 },
}
local THRUST = {
	RightShoulder = { 100, 0, -10 }, RightElbow = { 4, 0, 0 }, RightWrist = { -62, 0, 0 },
	LeftShoulder = { -30, 0, -28 }, LeftElbow = { 28, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CHANT = {
	RightShoulder = { 60, 0, -85 }, RightElbow = { 85, 0, 0 }, RightWrist = { 10, 0, 0 },
	LeftShoulder = { 5, 0, -12 }, LeftElbow = { 15, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local CHANT_PUSH = {
	RightShoulder = { 70, 0, -78 }, RightElbow = { 72, 0, 0 }, RightWrist = { 4, 0, 0 },
	LeftShoulder = { 8, 0, -18 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
}

-- the shared second half (blue -> red -> strain -> clap -> birth -> wind-up -> thrust), offset to start at `t0`
local function castKeys(t0)
	local held = merge(PLANT, BLUE_UP, RED_UP, { Waist = { -8, 0, 0 }, Neck = { -4, 0, 0 } })
	return seq({
		-- Lapse Blue blooms in the left hand: the arm flung out, palm up, and he turns to look at it
		{ t = t0 + 0.22, ease = { "Back", "Out" }, pose = merge(PLANT, BLUE_OUT, HALF_R, { Waist = { -4, 20, 0 }, Neck = { 4, 26, 0 } }) },
		{ t = t0 + 0.36, ease = { "Sine", "InOut" }, pose = merge(PLANT, BLUE_OUT, HALF_R, { Waist = { -6, 18, 0 }, Neck = { 2, 24, 0 } }) },
		-- Reversal Red in the right: both arms out wide, the two techniques held apart
		{ t = t0 + 0.62, ease = { "Back", "Out" }, pose = merge(PLANT, BLUE_OUT_WIDE, RED_OUT, { Waist = { -4, -18, 0 }, Neck = { 4, -26, 0 } }) },
		{ t = t0 + 0.78, ease = { "Sine", "InOut" }, pose = held },
	}, tremble(t0 + 0.78, t0 + 1.0, 4, held, { LeftShoulder = true, RightShoulder = true, Waist = true }, 2.5), {
		-- the clap: both hands driven together in front of the chest, the body crunched down over them
		{ t = t0 + 1.22, ease = { "Quad", "InOut" }, pose = merge(DEEP, MERGE_ARMS, { Waist = { -14, 0, 0 }, Neck = { -10, 0, 0 } }) },
		-- Hollow Purple is born: the hands spring apart around it and he rears back
		{ t = t0 + 1.32, ease = { "Exponential", "Out" }, pose = merge(PLANT, CUP, root(-0.3, 0.15), { Waist = { 9, 0, 0 }, Neck = { 12, 0, 0 } }) },
		-- wind-up: the left hand aims, the right cocks back by the ear, the hips load
		{ t = t0 + 1.5, ease = { "Quad", "Out" }, pose = merge(LOAD, ANTIC, { Waist = { 6, -24, 0 }, Neck = { -2, 22, 0 } }) },
		-- release: the right palm drives forward behind the orb into a deep lunge
		{ t = t0 + 1.62, ease = { "Exponential", "Out" }, pose = merge(LUNGE_DEEP, THRUST, { Waist = { -18, 14, 0 }, Neck = { -6, -12, 0 } }) },
		{ t = t0 + 1.85, ease = { "Sine", "Out" }, pose = merge(LUNGE_DEEP, THRUST, { Waist = { -14, 10, 0 }, Neck = { -3, -8, 0 } }) },
		{ t = t0 + 2.1, ease = { "Sine", "InOut" }, pose = merge(PLANT, {
			RightShoulder = { 70, 0, -8 }, RightElbow = { 20, 0, 0 }, RightWrist = { -30, 0, 0 },
			LeftShoulder = { 0, 0, -20 }, LeftElbow = { 25, 0, 0 }, LeftWrist = { 0, 0, 0 }, Waist = { -6, 6, 0 }, Neck = { -2, -4, 0 },
		}) },
	})
end

-- beats are seconds from cast start; launch must equal Config.HollowPurple.Variants.<v>.LaunchTime
Clips.PurpleQuick = {
	length = 2.4, fadeIn = 0.1, fadeOut = 0.35,
	beats = { blue = 0.15, red = 0.45, merge = 0.95, release = 1.05, birth = 1.45, launch = 1.8 },
	keys = seq({
		{ t = 0.15, ease = { "Quad", "Out" }, pose = merge(PLANT, RELAX_L, RELAX_R, { Waist = { -8, 0, 0 }, Neck = { 0, 0, 0 } }) },
	}, castKeys(0.15)),
}

-- the incantation: the seal held up at the face, one push (and a little more lift off the ground) per line
local function incantKeys()
	local keys = { { t = 0.3, ease = { "Quad", "Out" }, pose = merge(STAND, CHANT, { Waist = { 4, 0, 0 }, Neck = { -4, 0, 0 } }) } }
	for i, tc in ipairs({ 0.4, 1.2, 2.0, 2.8 }) do
		local lift = 0.1 * i
		table.insert(keys, { t = tc + (i < 4 and 0.1 or 0.06), ease = { "Back", "Out" }, pose = merge(STAND, CHANT_PUSH, root(lift), { Waist = { 7, 0, 0 }, Neck = { 9, 0, 0 } }) })
		if i < 4 then
			table.insert(keys, { t = tc + 0.55, ease = { "Sine", "InOut" }, pose = merge(STAND, CHANT, root(lift + 0.04), { Waist = { 3, 0, 0 }, Neck = { 0, 0, 0 } }) })
		end
	end
	return seq(keys, castKeys(2.95))
end

Clips.PurpleIncantation = {
	length = 5.2, fadeIn = 0.15, fadeOut = 0.35,
	beats = { chant = { 0.4, 1.2, 2.0, 2.8 }, blue = 3.0, red = 3.4, merge = 3.85, release = 3.85, birth = 4.2, launch = 4.6 },
	keys = incantKeys(),
}

---------------------------------------------------------------------------------------------------
-- M1 combo
local GUARD_L = { LeftShoulder = { 55, 0, 90 }, LeftElbow = { 95, 0, 0 } }
local GUARD_R = { RightShoulder = { 55, 0, -90 }, RightElbow = { 95, 0, 0 } }

Clips.Punch = {
	[1] = { length = 0.36, fadeIn = 0.04, fadeOut = 0.14, keys = {
		{ t = 0.06, pose = merge(GUARD_L, { RightShoulder = { 40, 0, 10 }, RightElbow = { 110, 0, 0 }, Waist = { 0, 12, 0 } }) },
		{ t = 0.13, ease = { "Exponential", "Out" }, pose = merge(GUARD_L, { RightShoulder = { 85, 0, -10 }, RightElbow = { 10, 0, 0 }, Waist = { -6, -16, 0 } }) },
		{ t = 0.24, pose = merge(GUARD_L, { RightShoulder = { 80, 0, -8 }, RightElbow = { 20, 0, 0 }, Waist = { -4, -12, 0 } }) },
	} },
	[2] = { length = 0.36, fadeIn = 0.04, fadeOut = 0.14, keys = {
		{ t = 0.06, pose = merge(GUARD_R, { LeftShoulder = { 40, 0, -10 }, LeftElbow = { 110, 0, 0 }, Waist = { 0, -12, 0 } }) },
		{ t = 0.13, ease = { "Exponential", "Out" }, pose = merge(GUARD_R, { LeftShoulder = { 85, 0, 10 }, LeftElbow = { 15, 0, 0 }, Waist = { -6, 16, 0 } }) },
		{ t = 0.24, pose = merge(GUARD_R, { LeftShoulder = { 80, 0, 8 }, LeftElbow = { 22, 0, 0 }, Waist = { -4, 12, 0 } }) },
	} },
	[3] = { length = 0.42, fadeIn = 0.05, fadeOut = 0.15, keys = {
		{ t = 0.08, pose = merge(GUARD_L, { RightShoulder = { 15, 0, 30 }, RightElbow = { 110, 0, 0 }, Waist = { 0, 18, 0 } }) },
		{ t = 0.17, ease = { "Exponential", "Out" }, pose = merge(GUARD_L, { RightShoulder = { 55, 0, -50 }, RightElbow = { 90, 0, 0 }, Waist = { -6, -28, 0 } }) },
		{ t = 0.30, pose = merge(GUARD_L, { RightShoulder = { 50, 0, -45 }, RightElbow = { 95, 0, 0 }, Waist = { -4, -22, 0 } }) },
	} },
	[4] = { length = 0.56, fadeIn = 0.05, fadeOut = 0.2, keys = {
		{ t = 0.10, ease = { "Quad", "Out" }, pose = merge(GUARD_R, PLANT, { LeftShoulder = { -30, 0, 90 }, LeftElbow = { 135, 0, 0 }, Waist = { -10, -14, 0 }, Root = { 0, 0, 0, pos = Vector3.new(0, -0.45, 0) } }) },
		{ t = 0.22, ease = { "Exponential", "Out" }, pose = merge(GUARD_R, STAND, { LeftShoulder = { 90, 0, 25 }, LeftElbow = { 45, 0, 0 }, Waist = { 8, 18, 0 }, Root = { 0, 0, 0, pos = Vector3.new(0, 0.15, 0) } }) },
		{ t = 0.38, ease = { "Quad", "Out" }, pose = merge(GUARD_R, STAND, { LeftShoulder = { 85, 0, 22 }, LeftElbow = { 50, 0, 0 }, Waist = { 6, 14, 0 } }) },
	} },
}

---------------------------------------------------------------------------------------------------
-- Reversal: Red - coil, snap the finger onto the target with the free hand clamping the forearm, shake with the
-- charge, then a recoil that kicks the arm up and the body back. The arm's yaw is applied AFTER its pitch
-- (fromEulerAnglesYXZ) so it cancels the waist turn and the finger stays on the aim line.
local function pointArm(pitch, yaw, elbow, wrist)
	return {
		RightShoulder = CFrame.fromEulerAnglesYXZ(math.rad(pitch), math.rad(yaw), 0),
		RightElbow = { elbow, 0, 0 },
		RightWrist = { wrist, 0, 0 },
	}
end
local RED_STANCE = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.38, -0.05) }, RightHip = { 22, 0, 8 }, RightKnee = { -32, 0, 0 },
	RightAnkle = { 10, 0, 0 }, LeftHip = { -10, 0, -10 }, LeftKnee = { -22, 0, 0 }, LeftAnkle = { 26, 0, 0 },
}
local BRACE = { LeftShoulder = { 50, 20, 90 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -10, 0, 0 } } -- the free arm across the chest
local RED_AIM = merge(RED_STANCE, pointArm(90, -18, 4, -14), BRACE, { Waist = { -7, 18, 0 }, Neck = { 0, -16, 0 } })

Clips.Red = {
	length = 1.05, fadeIn = 0.06, fadeOut = 0.3,
	keys = seq({
		{ t = 0.1, ease = { "Quad", "Out" }, pose = {
			RightShoulder = { 30, 0, -50 }, RightElbow = { 115, 0, 0 }, RightWrist = { 20, 0, 0 },
			LeftShoulder = { 42, 0, -28 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 },
			Waist = { -3, -26, 0 }, Neck = { 0, 22, 0 },
			Root = { 0, 0, 0, pos = Vector3.new(0, -0.3, 0.1) }, RightHip = { 14, 0, 10 }, RightKnee = { -28, 0, 0 }, RightAnkle = { 14, 0, 0 },
			LeftHip = { 2, 0, -12 }, LeftKnee = { -24, 0, 0 }, LeftAnkle = { 22, 0, 0 },
		} },
		{ t = 0.24, ease = { "Back", "Out" }, pose = RED_AIM },
	}, tremble(0.24, 0.56, 6, RED_AIM, { RightShoulder = true, Waist = true, LeftShoulder = true }, 1.6), {
		{ t = 0.585, ease = { "Quad", "In" }, pose = merge(RED_STANCE, pointArm(86, -17, 10, -6), BRACE, { Waist = { -9, 19, 0 }, Neck = { 0, -17, 0 } }) },
		{ t = 0.64, ease = { "Exponential", "Out" }, pose = merge(pointArm(108, -12, 18, -26), {
			LeftShoulder = { 22, 0, -42 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 }, Waist = { 10, 12, 0 }, Neck = { -6, -10, 0 },
			Root = { 0, 0, 0, pos = Vector3.new(0, -0.28, 0.5) }, RightHip = { 6, 0, 8 }, RightKnee = { -18, 0, 0 }, RightAnkle = { 14, 0, 0 },
			LeftHip = { -22, 0, -10 }, LeftKnee = { -30, 0, 0 }, LeftAnkle = { 30, 0, 0 },
		}) },
		{ t = 0.78, ease = { "Sine", "Out" }, pose = merge(pointArm(100, -12, 14, -18), root(-0.22, 0.55), { Waist = { 5, 10, 0 }, Neck = { -4, -8, 0 } }) },
		{ t = 0.98, ease = { "Quad", "InOut" }, pose = merge(STAND, pointArm(80, -10, 16, -8), { LeftShoulder = { 10, 0, -14 }, LeftElbow = { 22, 0, 0 }, LeftWrist = { 0, 0, 0 }, Waist = { -2, 8, 0 }, Neck = { 0, -6, 0 } }) },
	}),
}

---------------------------------------------------------------------------------------------------
-- Lapse Blue. The hold only names the arms, waist and neck (the caster can walk while holding); the legs get
-- their own short BlueGrabLegs track for the lunge-and-yank.
local BLUE_REACH = { LeftShoulder = { 94, 0, 12 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -55, 0, 0 } }
local BLUE_CLAW = { LeftShoulder = { 82, 0, 8 }, LeftElbow = { 52, 0, 0 }, LeftWrist = { 38, 0, 0 } }
local BLUE_HOLD_A = {
	LeftShoulder = { 88, 0, 10 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { -22, 0, 0 },
	RightShoulder = { 14, 0, 22 }, RightElbow = { 38, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { -4, -12, 0 }, Neck = { 0, 10, 0 },
}
local BLUE_HOLD_B = {
	LeftShoulder = { 91, 0, 8 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { -30, 0, 0 },
	RightShoulder = { 16, 0, 24 }, RightElbow = { 42, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { -6, -10, 0 }, Neck = { 0, 9, 0 },
}

-- reach out with an open palm, clench it into a claw and yank, then hold with the hand straining
Clips.BlueHold = {
	length = 60, fadeIn = 0.06, fadeOut = 0.2,
	keys = (function()
		local keys = {
			{ t = 0.07, ease = { "Quad", "Out" }, pose = merge(BLUE_REACH, { RightShoulder = { 20, 0, 30 }, RightElbow = { 45, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { -10, -16, 0 }, Neck = { 0, 14, 0 } }) },
			{ t = 0.2, ease = { "Back", "Out" }, pose = merge(BLUE_CLAW, { RightShoulder = { 14, 0, 22 }, RightElbow = { 38, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { 6, -6, 0 }, Neck = { 4, 8, 0 } }) },
			{ t = 0.45, ease = { "Sine", "Out" }, pose = BLUE_HOLD_A },
		}
		for i = 1, 36 do
			table.insert(keys, { t = 0.45 + i * 0.45, ease = { "Sine", "InOut" }, pose = (i % 2 == 1) and BLUE_HOLD_B or BLUE_HOLD_A })
		end
		return keys
	end)(),
}

Clips.BlueGrabLegs = {
	length = 0.6, fadeIn = 0.05, fadeOut = 0.3,
	keys = {
		{ t = 0.07, ease = { "Quad", "Out" }, pose = {
			Root = { 0, 0, 0, pos = Vector3.new(0, -0.4, -0.15) }, LeftHip = { 28, 0, -6 }, LeftKnee = { -36, 0, 0 }, LeftAnkle = { 10, 0, 0 },
			RightHip = { -8, 0, 6 }, RightKnee = { -22, 0, 0 }, RightAnkle = { 24, 0, 0 },
		} },
		{ t = 0.22, ease = { "Back", "Out" }, pose = {
			Root = { 0, 0, 0, pos = Vector3.new(0, -0.3, 0.3) }, LeftHip = { 14, 0, -6 }, LeftKnee = { -26, 0, 0 }, LeftAnkle = { 12, 0, 0 },
			RightHip = { -16, 0, 6 }, RightKnee = { -28, 0, 0 }, RightAnkle = { 30, 0, 0 },
		} },
	},
}

-- the throw: the left arm winds out wide, then whips forward across the body
Clips.BlueThrow = {
	length = 0.55, fadeIn = 0.04, fadeOut = 0.25,
	keys = {
		{ t = 0.07, ease = { "Quad", "Out" }, pose = {
			LeftShoulder = { 40, 0, -88 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
			RightShoulder = { 30, 0, 30 }, RightElbow = { 50, 0, 0 }, Waist = { 4, 22, 0 }, Neck = { 0, -18, 0 },
		} },
		{ t = 0.17, ease = { "Exponential", "Out" }, pose = {
			LeftShoulder = { 100, 0, 34 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -45, 0, 0 },
			RightShoulder = { -20, 0, 30 }, RightElbow = { 30, 0, 0 }, Waist = { -14, -26, 0 }, Neck = { -4, 20, 0 },
		} },
		{ t = 0.34, ease = { "Sine", "Out" }, pose = {
			LeftShoulder = { 86, 0, 40 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { -20, 0, 0 },
			RightShoulder = { -10, 0, 24 }, RightElbow = { 30, 0, 0 }, Waist = { -9, -20, 0 }, Neck = { -2, 16, 0 },
		} },
	},
}

-- Q with nothing to grab: a palm thrust that closes on empty air
Clips.BlueFizzle = {
	length = 0.45, fadeIn = 0.04, fadeOut = 0.2,
	keys = {
		{ t = 0.08, ease = { "Back", "Out" }, pose = { LeftShoulder = { 92, 0, 10 }, LeftElbow = { 6, 0, 0 }, LeftWrist = { -55, 0, 0 }, Waist = { -6, -12, 0 }, Neck = { 0, 10, 0 } } },
		{ t = 0.22, ease = { "Quad", "Out" }, pose = { LeftShoulder = { 80, 0, 8 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 35, 0, 0 }, Waist = { -2, -8, 0 }, Neck = { 0, 6, 0 } } },
	},
}

---------------------------------------------------------------------------------------------------
-- Domain Expansion: the seal raised before the face and held, thrust out as the void bursts from him, then the
-- arms flung wide, chin up ("welcome to my domain"), floating off the ground while the void forms around him.
-- The burst is keyed to Config.Domain.Start (0.7) and the arms to Start + ExpandTime (1.25).
local SEAL = {
	RightShoulder = { 64, 0, -80 }, RightElbow = { 100, 0, 0 }, RightWrist = { 14, 0, 0 },
	LeftShoulder = { 8, 0, -14 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local OPEN = {
	RightShoulder = { 22, 0, 70 }, RightElbow = { 14, 0, 0 }, RightWrist = { -24, 0, 0 },
	LeftShoulder = { 22, 0, -70 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { -24, 0, 0 },
}
local FLOAT_LEGS = {
	LeftHip = { 6, 0, -4 }, RightHip = { 14, 0, 4 }, LeftKnee = { -16, 0, 0 }, RightKnee = { -26, 0, 0 },
	LeftAnkle = { -14, 0, 0 }, RightAnkle = { -12, 0, 0 },
}
Clips.Domain = {
	length = 3.2, fadeIn = 0.12, fadeOut = 0.45,
	keys = {
		{ t = 0.18, ease = { "Back", "Out" }, pose = merge(STAND, SEAL, { Neck = { -8, 0, 0 }, Waist = { 3, 0, 0 } }) },
		{ t = 0.45, ease = { "Sine", "InOut" }, pose = merge(SEAL, { RightShoulder = { 72, 0, -82 }, RightElbow = { 108, 0, 0 }, Neck = { -12, 0, 0 }, Waist = { 6, 0, 0 } }) },
		{ t = 0.62, ease = { "Sine", "InOut" }, pose = merge(SEAL, { RightShoulder = { 70, 0, -82 }, RightElbow = { 106, 0, 0 }, Neck = { -9, 0, 0 }, Waist = { 8, 0, 0 } }) },
		{ t = 0.74, ease = { "Exponential", "Out" }, pose = merge(SEAL, root(-0.18), { RightShoulder = { 90, 0, -40 }, RightElbow = { 62, 0, 0 }, RightWrist = { 0, 0, 0 }, Neck = { -2, 0, 0 }, Waist = { -5, 0, 0 } }) },
		{ t = 0.95, ease = { "Sine", "InOut" }, pose = merge(SEAL, STAND, root(-0.12), { RightShoulder = { 88, 0, -42 }, RightElbow = { 66, 0, 0 }, RightWrist = { 0, 0, 0 }, Neck = { 0, 0, 0 }, Waist = { -3, 0, 0 } }) },
		{ t = 1.25, ease = { "Back", "Out" }, pose = merge(OPEN, FLOAT_LEGS, root(1.1), { Neck = { 16, 0, 0 }, Waist = { 10, 0, 0 } }) },
		{ t = 1.5, ease = { "Sine", "Out" }, pose = merge(OPEN, FLOAT_LEGS, root(1.35), { RightShoulder = { 18, 0, 62 }, LeftShoulder = { 18, 0, -62 }, Neck = { 13, 0, 0 }, Waist = { 8, 0, 0 } }) },
		{ t = 2.1, ease = { "Sine", "InOut" }, pose = merge(OPEN, FLOAT_LEGS, root(1.6), { RightShoulder = { 15, 0, 58 }, LeftShoulder = { 15, 0, -58 }, Neck = { 11, 0, 0 }, Waist = { 6, 0, 0 } }) },
		{ t = 2.7, ease = { "Sine", "InOut" }, pose = merge(OPEN, FLOAT_LEGS, root(1.4), { RightShoulder = { 19, 0, 61 }, LeftShoulder = { 19, 0, -61 }, Neck = { 12, 0, 0 }, Waist = { 7, 0, 0 } }) },
	},
}

return Clips
