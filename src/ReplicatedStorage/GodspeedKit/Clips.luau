--!nocheck
-- Clips: procedural keyframes for the Godspeed kit, played by GojoShared.Client.ProceduralAnimator.
-- Signs (measured on the live rig): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X,
-- +Y turns left, right arm out RightShoulder Z+, left arm out LeftShoulder Z-, Neck +X lifts the chin.
-- Root pos is in the HumanoidRootPart's frame: -Y crouches, +Z slides back, +X slides right.
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

local function seq(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			table.insert(out, v)
		end
	end
	return out
end

local function root(x, y, z)
	return { Root = { 0, 0, 0, pos = Vector3.new(x or 0, y or 0, z or 0) } }
end

-- a strain tremble: n keys over (t0, t1] alternating +/- amp degrees on the named joints, around `pose`
local function tremble(t0, t1, n, pose, joints, amp)
	local keys = {}
	for i = 1, n do
		local s = (i % 2 == 0) and 1 or -1
		local p = {}
		for name, v in pairs(pose) do
			if joints[name] then
				p[name] = { (v[1] or 0) + amp * s, (v[2] or 0) + amp * 0.6 * s, v[3] or 0, pos = v.pos }
			else
				p[name] = v
			end
		end
		table.insert(keys, { t = t0 + (t1 - t0) * i / n, ease = { "Sine", "InOut" }, pose = p })
	end
	return keys
end

local STAND = {
	Root = { 0, 0, 0, pos = Vector3.zero }, LeftHip = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 },
	RightKnee = { 0, 0, 0 }, LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
}
local CROUCH = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.7, 0) }, LeftHip = { 42, 0, -10 }, RightHip = { 42, 0, 10 },
	LeftKnee = { -78, 0, 0 }, RightKnee = { -78, 0, 0 }, LeftAnkle = { 32, 0, 0 }, RightAnkle = { 32, 0, 0 },
}
local LOW = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, LeftHip = { 28, 0, -12 }, RightHip = { 24, 0, 12 },
	LeftKnee = { -52, 0, 0 }, RightKnee = { -48, 0, 0 }, LeftAnkle = { 24, 0, 0 }, RightAnkle = { 22, 0, 0 },
}
local RUN = { -- a sprinting lunge: right leg driving forward, left trailing
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.6, 0) }, RightHip = { 50, 0, 6 }, RightKnee = { -70, 0, 0 }, RightAnkle = { 20, 0, 0 },
	LeftHip = { -28, 0, -6 }, LeftKnee = { -30, 0, 0 }, LeftAnkle = { 30, 0, 0 },
}
local LOOSE = { -- arms hanging loose, hands curled like claws
	RightShoulder = { 12, 0, 26 }, RightElbow = { 40, 0, 0 }, RightWrist = { 30, 0, 0 },
	LeftShoulder = { 12, 0, -26 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 30, 0, 0 },
}

---------------------------------------------------------------------------------------------------
-- Q: Lightning Palm. Coil low with the striking palm drawn back, then a sprinting lunge with the palm driven out
Clips.Palm = {
	length = 0.62, fadeIn = 0.05, fadeOut = 0.22,
	keys = {
		{ t = 0.1, ease = { "Quad", "Out" }, pose = merge(root(0, -0.5, 0.15), {
			Waist = { -14, -24, 0 }, Neck = { 6, 20, 0 },
			RightShoulder = { -28, 0, 26 }, RightElbow = { 100, 0, 0 }, RightWrist = { -30, 0, 0 },
			LeftShoulder = { 78, 0, 14 }, LeftElbow = { 34, 0, 0 }, LeftWrist = { -20, 0, 0 },
			LeftHip = { 30, 0, -6 }, LeftKnee = { -50, 0, 0 }, LeftAnkle = { 22, 0, 0 },
			RightHip = { -10, 0, 6 }, RightKnee = { -32, 0, 0 }, RightAnkle = { 30, 0, 0 },
		}) },
		{ t = 0.17, ease = { "Exponential", "Out" }, pose = merge(RUN, {
			Waist = { -30, 16, 0 }, Neck = { 18, -14, 0 },
			RightShoulder = { 100, 0, -6 }, RightElbow = { 4, 0, 0 }, RightWrist = { -75, 0, 0 },
			LeftShoulder = { -46, 0, -22 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { 0, 0, 0 },
		}) },
		{ t = 0.36, ease = { "Back", "Out" }, pose = merge(RUN, root(0, -0.55, -0.15), {
			Waist = { -22, 22, 0 }, Neck = { 12, -18, 0 },
			RightShoulder = { 96, 0, -10 }, RightElbow = { 2, 0, 0 }, RightWrist = { -80, 0, 0 },
			LeftShoulder = { -40, 0, -26 }, LeftElbow = { 30, 0, 0 },
		}) },
		{ t = 0.46, ease = { "Sine", "Out" }, pose = merge(LOW, {
			Waist = { -16, 16, 0 }, Neck = { 8, -12, 0 },
			RightShoulder = { 88, 0, -8 }, RightElbow = { 12, 0, 0 }, RightWrist = { -60, 0, 0 },
			LeftShoulder = { -20, 0, -24 }, LeftElbow = { 34, 0, 0 },
		}) },
		{ t = 0.6, ease = { "Sine", "InOut" }, pose = merge(STAND, LOOSE, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }) },
	},
}

---------------------------------------------------------------------------------------------------
-- E: Thunderbolt. Drop into a crouch with the arms swung back, spring up tucked, raise the right hand at the top of
-- the leap, then drive it down at the strike point as the bolt lands, and land in a crouch
Clips.Thunder = {
	length = 1.15, fadeIn = 0.05, fadeOut = 0.25,
	keys = {
		{ t = 0.1, ease = { "Quad", "Out" }, pose = merge(CROUCH, {
			Waist = { -22, 0, 0 }, Neck = { 10, 0, 0 },
			RightShoulder = { -52, 0, 22 }, RightElbow = { 20, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { -52, 0, -22 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
		}) },
		{ t = 0.24, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.2, 0), {
			LeftHip = { 78, 0, -8 }, RightHip = { 70, 0, 8 }, LeftKnee = { -112, 0, 0 }, RightKnee = { -104, 0, 0 },
			LeftAnkle = { -20, 0, 0 }, RightAnkle = { -20, 0, 0 },
			Waist = { 10, 0, 0 }, Neck = { 12, 0, 0 },
			RightShoulder = { 160, 0, 16 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 150, 0, -24 }, LeftElbow = { 12, 0, 0 },
		}) },
		{ t = 0.46, ease = { "Sine", "Out" }, pose = merge(root(0, 0.2, 0), {
			LeftHip = { 62, 0, -8 }, LeftKnee = { -96, 0, 0 }, RightHip = { 22, 0, 8 }, RightKnee = { -44, 0, 0 },
			Waist = { -8, 0, 0 }, Neck = { -24, 0, 0 },
			RightShoulder = { 174, 0, 6 }, RightElbow = { 4, 0, 0 }, RightWrist = { -10, 0, 0 },
			LeftShoulder = { 36, 0, -78 }, LeftElbow = { 20, 0, 0 },
		}) },
		{ t = 0.59, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.1, 0), {
			LeftHip = { 50, 0, -8 }, LeftKnee = { -80, 0, 0 }, RightHip = { 30, 0, 8 }, RightKnee = { -50, 0, 0 },
			Waist = { -30, 0, 0 }, Neck = { -28, 0, 0 },
			RightShoulder = { 72, 0, -6 }, RightElbow = { 0, 0, 0 }, RightWrist = { -24, 0, 0 },
			LeftShoulder = { -32, 0, -40 }, LeftElbow = { 26, 0, 0 },
		}) },
		{ t = 0.9, ease = { "Quad", "Out" }, pose = merge(CROUCH, {
			Waist = { -22, 6, 0 }, Neck = { 12, 0, 0 },
			RightShoulder = { 40, 0, 30 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { 20, 0, -42 }, LeftElbow = { 30, 0, 0 },
		}) },
		{ t = 1.1, ease = { "Sine", "InOut" }, pose = merge(STAND, LOOSE, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }) },
	},
}

---------------------------------------------------------------------------------------------------
-- R: Rhythm Echo. A rhythmic weave side to side with the arms loose, then (after the blink) a coiled claw stance and
-- one sweeping slash across the body
local function sway(x, yaw)
	return merge(LOOSE, root(x, -0.25, 0), {
		Waist = { -6, yaw, 0 }, Neck = { 0, -yaw * 0.7, 0 },
		LeftHip = { 14, 0, -8 }, RightHip = { 14, 0, 8 }, LeftKnee = { -28, 0, 0 }, RightKnee = { -28, 0, 0 },
		LeftAnkle = { 14, 0, 0 }, RightAnkle = { 14, 0, 0 },
	})
end
Clips.Echo = {
	length = 0.95, fadeIn = 0.04, fadeOut = 0.22,
	keys = {
		{ t = 0.07, ease = { "Sine", "InOut" }, pose = sway(-0.8, 16) },
		{ t = 0.15, ease = { "Sine", "InOut" }, pose = sway(0.8, -16) },
		{ t = 0.23, ease = { "Sine", "InOut" }, pose = sway(-0.9, 18) },
		{ t = 0.31, ease = { "Sine", "InOut" }, pose = sway(0.9, -18) },
		{ t = 0.37, ease = { "Exponential", "Out" }, pose = merge(LOW, root(0, -0.55, 0.1), {
			Waist = { -16, -32, 0 }, Neck = { 0, 24, 0 },
			RightShoulder = { 56, 0, 86 }, RightElbow = { 76, 0, 0 }, RightWrist = { 40, 0, 0 },
			LeftShoulder = { 46, 0, -30 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 30, 0, 0 },
		}) },
		{ t = 0.47, ease = { "Exponential", "Out" }, pose = merge(LOW, root(0, -0.6, -0.25), {
			Waist = { -22, 38, 0 }, Neck = { -4, -22, 0 },
			RightShoulder = { 86, 0, -56 }, RightElbow = { 10, 0, 0 }, RightWrist = { 30, 0, 0 },
			LeftShoulder = { -36, 0, -30 }, LeftElbow = { 30, 0, 0 },
		}) },
		{ t = 0.66, ease = { "Sine", "Out" }, pose = merge(LOW, root(0, -0.55, -0.2), {
			Waist = { -18, 32, 0 }, Neck = { -2, -20, 0 },
			RightShoulder = { 80, 0, -50 }, RightElbow = { 16, 0, 0 }, RightWrist = { 26, 0, 0 },
			LeftShoulder = { -28, 0, -28 }, LeftElbow = { 34, 0, 0 },
		}) },
		{ t = 0.9, ease = { "Sine", "InOut" }, pose = merge(STAND, LOOSE, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }) },
	},
}

---------------------------------------------------------------------------------------------------
-- G: Godspeed. The charge: crouched, fists clenched and pulled back, head bowed and shaking with the current, then
-- the release - chest up, chin up, arms flung out and down
local CLENCH = merge(LOW, {
	Waist = { -18, 0, 0 }, Neck = { -22, 0, 0 },
	RightShoulder = { -20, 0, 32 }, RightElbow = { 115, 0, 0 }, RightWrist = { 20, 0, 0 },
	LeftShoulder = { -20, 0, -32 }, LeftElbow = { 115, 0, 0 }, LeftWrist = { 20, 0, 0 },
})
Clips.GodCharge = {
	length = 1.1, fadeIn = 0.06, fadeOut = 0.15,
	keys = seq({
		{ t = 0.12, ease = { "Back", "Out" }, pose = CLENCH },
	}, tremble(0.12, 0.72, 8, CLENCH, { Waist = true, RightShoulder = true, LeftShoulder = true, Neck = true }, 2.5), {
		{ t = 0.84, ease = { "Exponential", "Out" }, pose = merge(LOW, root(0, -0.35, 0), {
			Waist = { 10, 0, 0 }, Neck = { 14, 0, 0 },
			RightShoulder = { 20, 0, 58 }, RightElbow = { 20, 0, 0 }, RightWrist = { -20, 0, 0 },
			LeftShoulder = { 20, 0, -58 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { -20, 0, 0 },
		}) },
		{ t = 1.05, ease = { "Sine", "Out" }, pose = merge(LOW, root(0, -0.4, 0), {
			Waist = { 4, 0, 0 }, Neck = { 8, 0, 0 },
			RightShoulder = { 16, 0, 50 }, RightElbow = { 24, 0, 0 }, LeftShoulder = { 16, 0, -50 }, LeftElbow = { 24, 0, 0 },
		}) },
	}),
}

-- one strike per blink of the barrage, cycled: a claw slash, a snap kick, a palm
Clips.HopA = {
	length = 0.26, fadeIn = 0.02, fadeOut = 0.1,
	keys = {
		{ t = 0.04, pose = merge(LOW, { Waist = { -12, -30, 0 }, RightShoulder = { 60, 0, 82 }, RightElbow = { 70, 0, 0 }, RightWrist = { 40, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 60, 0, 0 } }) },
		{ t = 0.1, ease = { "Exponential", "Out" }, pose = merge(LOW, { Waist = { -18, 36, 0 }, RightShoulder = { 86, 0, -52 }, RightElbow = { 10, 0, 0 }, RightWrist = { 30, 0, 0 }, LeftShoulder = { -30, 0, -30 }, LeftElbow = { 30, 0, 0 } }) },
	},
}
Clips.HopB = {
	length = 0.26, fadeIn = 0.02, fadeOut = 0.1,
	keys = {
		{ t = 0.05, pose = merge(root(0, 0, 0.1), { RightHip = { 40, 0, 10 }, RightKnee = { -92, 0, 0 }, LeftHip = { -6, 0, -6 }, LeftKnee = { -16, 0, 0 }, Waist = { 6, 0, 0 }, RightShoulder = { 30, 0, 60 }, LeftShoulder = { 30, 0, -60 } }) },
		{ t = 0.11, ease = { "Exponential", "Out" }, pose = merge(root(0, 0, 0.25), { RightHip = { 96, 0, 6 }, RightKnee = { -6, 0, 0 }, RightAnkle = { -30, 0, 0 }, LeftHip = { -10, 0, -6 }, LeftKnee = { -20, 0, 0 }, Waist = { 14, 0, 0 }, RightShoulder = { 20, 0, 70 }, LeftShoulder = { 20, 0, -70 } }) },
	},
}
Clips.HopC = {
	length = 0.26, fadeIn = 0.02, fadeOut = 0.1,
	keys = {
		{ t = 0.05, pose = merge(LOW, { Waist = { -10, 22, 0 }, LeftShoulder = { -24, 0, -30 }, LeftElbow = { 96, 0, 0 }, RightShoulder = { 40, 0, 20 }, RightElbow = { 60, 0, 0 } }) },
		{ t = 0.1, ease = { "Exponential", "Out" }, pose = merge(LOW, { Waist = { -22, -18, 0 }, LeftShoulder = { 96, 0, 8 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -72, 0, 0 }, RightShoulder = { -36, 0, 24 }, RightElbow = { 30, 0, 0 } }) },
	},
}

-- the finale: dropped into a crouch, the striking arm swept back, as every bolt lands at once
Clips.GodFinale = {
	length = 0.95, fadeIn = 0.04, fadeOut = 0.3,
	keys = {
		{ t = 0.08, ease = { "Exponential", "Out" }, pose = merge(CROUCH, {
			Waist = { -26, -14, 0 }, Neck = { 12, 14, 0 },
			RightShoulder = { -42, 0, 42 }, RightElbow = { 30, 0, 0 }, RightWrist = { 20, 0, 0 },
			LeftShoulder = { 62, 0, -18 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 30, 0, 0 },
		}) },
		{ t = 0.6, ease = { "Sine", "InOut" }, pose = merge(CROUCH, {
			Waist = { -22, -12, 0 }, Neck = { 10, 12, 0 },
			RightShoulder = { -36, 0, 40 }, RightElbow = { 34, 0, 0 }, LeftShoulder = { 56, 0, -18 }, LeftElbow = { 54, 0, 0 },
		}) },
		{ t = 0.9, ease = { "Sine", "InOut" }, pose = merge(STAND, LOOSE, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }) },
	},
}

return Clips
