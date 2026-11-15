--!nocheck
-- Clips: procedural keyframes for the One For All kit, played by GojoShared.Client.ProceduralAnimator.
-- Signs (measured on the live rig): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X,
-- +Y turns left, right limb out Z+, left limb out Z-, Neck +X lifts the chin. Root pos: -Y crouches, +Z slides back.
-- Root rotation: -X pitches forward, +Y yaws left, +Z rolls the right side up.
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
-- root(x, y, z [, rx, ry, rz]): root offset (studs, root frame) and optional root rotation (degrees)
local function root(x, y, z, rx, ry, rz)
	return { Root = { rx or 0, ry or 0, rz or 0, pos = Vector3.new(x or 0, y or 0, z or 0) } }
end
local function tremble(t0, t1, n, pose, joints, amp) -- identical to GodspeedKit.Clips' tremble
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
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.7, 0) }, LeftHip = { 55, 0, -10 }, RightHip = { 55, 0, 10 },
	LeftKnee = { -102, 0, 0 }, RightKnee = { -102, 0, 0 }, LeftAnkle = { 43, 0, 0 }, RightAnkle = { 43, 0, 0 },
}
local LOW = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, LeftHip = { 43, 0, -12 }, RightHip = { 42, 0, 12 },
	LeftKnee = { -82, 0, 0 }, RightKnee = { -83, 0, 0 }, LeftAnkle = { 39, 0, 0 }, RightAnkle = { 39, 0, 0 },
}
local RELAX = { -- Deku's arms at rest: fists loose, not Killua's claws
	RightShoulder = { 10, 0, 14 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 10, 0, -14 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local WIDE = { -- planted split stance: left foot forward, right leg braced back
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.65, 0.15) },
	LeftHip = { 58, 0, -16 }, LeftKnee = { -101, 0, 0 }, LeftAnkle = { 43, 0, 0 },
	RightHip = { -39, 0, 16 }, RightKnee = { -21, 0, 0 }, RightAnkle = { 64, 0, 0 },
}
local REST = merge(STAND, RELAX, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } })

---------------------------------------------------------------------------------------------------
-- Q: Delaware Smash: Air Force. Side-on brace (left hand on the right forearm), finger flick at 0.22, recoil
local BRACE = merge(root(0, -0.3, 0.05), {
	Waist = { -8, 22, 0 }, Neck = { 4, -18, 0 },
	RightShoulder = { 88, 0, 16 }, RightElbow = { 6, 0, 0 }, RightWrist = { -24, 0, 0 },
	LeftShoulder = { 96, -30, 90 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 },
	LeftHip = { 36, 0, -8 }, LeftKnee = { -63, 0, 0 }, LeftAnkle = { 27, 0, 0 },
	RightHip = { -8, 0, 10 }, RightKnee = { -46, 0, 0 }, RightAnkle = { 38, 0, 0 },
})
Clips.AirForce = {
	length = 0.62, fadeIn = 0.05, fadeOut = 0.2,
	keys = seq({
		{ t = 0.12, ease = { "Back", "Out" }, pose = BRACE },
	}, tremble(0.12, 0.2, 2, BRACE, { RightShoulder = true, RightWrist = true }, 1.8), {
		{ t = 0.235, ease = { "Exponential", "Out" }, pose = merge(BRACE, root(0, -0.3, 0.38), {
			Waist = { 4, 16, 0 }, Neck = { 10, -14, 0 },
			RightShoulder = { 106, 0, 12 }, RightElbow = { 14, 0, 0 }, RightWrist = { 34, 0, 0 },
			LeftShoulder = { 114, -30, 90 }, LeftElbow = { 50, 0, 0 },
		}) },
		{ t = 0.36, ease = { "Sine", "Out" }, pose = merge(BRACE, root(0, -0.25, 0.45), {
			Waist = { 0, 14, 0 }, Neck = { 6, -12, 0 },
			RightShoulder = { 98, 0, 10 }, RightElbow = { 22, 0, 0 }, RightWrist = { 22, 0, 0 },
			LeftShoulder = { 108, -30, 90 }, LeftElbow = { 50, 0, 0 },
		}) },
		{ t = 0.58, ease = { "Sine", "InOut" }, pose = REST },
	}),
}

---------------------------------------------------------------------------------------------------
-- E: Detroit Smash. Coil (chest twisted right, fist at the hip, left palm aiming), strain, punch at 0.42
local COIL = merge(WIDE, root(0, -0.7, 0.22), {
	Waist = { -12, -38, 0 }, Neck = { 6, 30, 0 },
	RightShoulder = { -48, 0, 34 }, RightElbow = { 118, 0, 0 }, RightWrist = { -10, 0, 0 },
	LeftShoulder = { 96, 0, -38 }, LeftElbow = { 14, 0, 0 }, LeftWrist = { -30, 0, 0 },
})
Clips.Detroit = {
	length = 1.05, fadeIn = 0.05, fadeOut = 0.22,
	keys = seq({
		{ t = 0.1, ease = { "Back", "Out" }, pose = COIL },
	}, tremble(0.1, 0.4, 6, COIL, { Waist = true, Neck = true, RightShoulder = true, RightElbow = true }, 2.2), {
		{ t = 0.44, ease = { "Exponential", "Out" }, pose = merge(root(0, -0.55, -0.45), {
			Waist = { -20, 34, 0 }, Neck = { 10, -26, 0 },
			RightShoulder = { 110, 0, 26 }, RightElbow = { 2, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { -44, 0, -24 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
			LeftHip = { 61, 0, -10 }, LeftKnee = { -89, 0, 0 }, LeftAnkle = { 36, 0, 0 },
			RightHip = { -21, 0, 10 }, RightKnee = { -43, 0, 0 }, RightAnkle = { 54, 0, 0 },
		}) },
		{ t = 0.62, ease = { "Sine", "Out" }, pose = merge(root(0, -0.5, -0.55), {
			Waist = { -16, 30, 0 }, Neck = { 8, -24, 0 },
			RightShoulder = { 102, 0, 24 }, RightElbow = { 4, 0, 0 },
			LeftShoulder = { -40, 0, -24 }, LeftElbow = { 44, 0, 0 },
		}) },
		{ t = 0.82, ease = { "Quad", "InOut" }, pose = merge(LOW, root(0, -0.45, -0.2), {
			Waist = { -8, 10, 0 }, Neck = { 2, -6, 0 },
			RightShoulder = { 40, 0, 18 }, RightElbow = { 50, 0, 0 }, RightWrist = { 10, 0, 0 },
			LeftShoulder = { 10, 0, -20 }, LeftElbow = { 40, 0, 0 },
		}) },
		{ t = 1.0, ease = { "Sine", "InOut" }, pose = REST },
	}),
}

---------------------------------------------------------------------------------------------------
-- R: Blackwhip -> St. Louis Smash. Reach, lash (0.14), reel (0.38), chamber (0.52), roundhouse (0.66), full spin
Clips.Blackwhip = {
	length = 1.12, fadeIn = 0.04, fadeOut = 0.2,
	keys = {
		{ t = 0.08, ease = { "Quad", "Out" }, pose = merge(LOW, root(0, -0.45, 0.1), {
			Waist = { -14, 0, 0 }, Neck = { 8, 0, 0 },
			RightShoulder = { 70, 0, 22 }, RightElbow = { 30, 0, 0 }, RightWrist = { -30, 0, 0 },
			LeftShoulder = { 70, 0, -22 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { -30, 0, 0 },
		}) },
		{ t = 0.16, ease = { "Exponential", "Out" }, pose = merge(LOW, root(0, -0.45, 0), {
			Waist = { -18, 0, 0 }, Neck = { 10, 0, 0 },
			RightShoulder = { 96, 0, 30 }, RightElbow = { 4, 0, 0 }, RightWrist = { -50, 0, 0 },
			LeftShoulder = { 96, 0, -30 }, LeftElbow = { 4, 0, 0 }, LeftWrist = { -50, 0, 0 },
		}) },
		{ t = 0.38, ease = { "Back", "Out" }, pose = merge(root(0, -0.5, 0.35), {
			Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 },
			RightShoulder = { -30, 0, 30 }, RightElbow = { 120, 0, 0 }, RightWrist = { 10, 0, 0 },
			LeftShoulder = { -30, 0, -30 }, LeftElbow = { 120, 0, 0 }, LeftWrist = { 10, 0, 0 },
			LeftHip = { 54, 0, -14 }, LeftKnee = { -86, 0, 0 }, LeftAnkle = { 36, 0, 0 },
			RightHip = { 37, 0, 14 }, RightKnee = { -86, 0, 0 }, RightAnkle = { 51, 0, 0 },
		}) },
		{ t = 0.52, ease = { "Quad", "InOut" }, pose = merge(root(0, -0.35, 0.1, 0, -30, 0), {
			Waist = { -10, -50, 0 }, Neck = { 4, 40, 0 },
			RightShoulder = { 20, 0, 70 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { 50, 0, -40 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 },
			RightHip = { 95, 0, 30 }, RightKnee = { -130, 0, 0 }, RightAnkle = { -10, 0, 0 },
			LeftHip = { 29, 0, -6 }, LeftKnee = { -67, 0, 0 }, LeftAnkle = { 38, 0, 0 },
		}) },
		{ t = 0.67, ease = { "Exponential", "Out" }, pose = merge(root(0, -0.1, 0, 0, 70, 22), { -- ST. LOUIS SMASH
			Waist = { -6, 20, 0 }, Neck = { 0, -40, 0 },
			RightShoulder = { 30, 0, 80 }, RightElbow = { 30, 0, 0 },
			LeftShoulder = { 40, 0, -95 }, LeftElbow = { 20, 0, 0 },
			RightHip = { 80, 0, 75 }, RightKnee = { -8, 0, 0 }, RightAnkle = { -25, 0, 0 },
			LeftHip = { 10, 0, -6 }, LeftKnee = { -61, 0, 0 }, LeftAnkle = { 39, 0, 0 },
		}) },
		{ t = 0.8, ease = { "Sine", "Out" }, pose = merge(root(0, -0.15, 0, 0, 105, 12), {
			Waist = { -8, 14, 0 }, Neck = { 0, -36, 0 },
			RightHip = { 50, 0, 50 }, RightKnee = { -40, 0, 0 },
		}) },
		{ t = 0.88, ease = { "Linear", "Out" }, pose = merge(root(0, -0.3, 0, 0, 190, 4), {
			RightHip = { 30, 0, 24 }, RightKnee = { -50, 0, 0 },
		}) },
		{ t = 0.95, ease = { "Linear", "Out" }, pose = merge(LOW, root(0, -0.45, 0, 0, 280, 0), {
			Waist = { -12, 0, 0 }, Neck = { 4, 0, 0 },
			RightShoulder = { 30, 0, 30 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 50, 0, 0 },
		}) },
		{ t = 1.02, ease = { "Quad", "Out" }, pose = merge(LOW, root(0, -0.45, 0, 0, 0, 0)) }, -- 280 -> 360 (= 0)
		{ t = 1.1, ease = { "Sine", "InOut" }, pose = REST },
	},
}

---------------------------------------------------------------------------------------------------
-- G: the charge (0 -> 1.12): plant + strain, whip lash with a roar (0.50), re-chamber looking up (0.82), pre-leap
local PLANT = merge(root(0, -0.8, 0.1), {
	Waist = { -16, -30, 0 }, Neck = { -4, 24, 0 },
	RightShoulder = { -40, 0, 30 }, RightElbow = { 120, 0, 0 }, RightWrist = { 10, 0, 0 },
	LeftShoulder = { 40, 0, -34 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { -20, 0, 0 },
	LeftHip = { 53, 0, -18 }, LeftKnee = { -102, 0, 0 }, LeftAnkle = { 47, 0, 0 },
	RightHip = { 14, 0, 20 }, RightKnee = { -92, 0, 0 }, RightAnkle = { 66, 0, 0 },
})
Clips.OFACharge = {
	length = 1.12, fadeIn = 0.06, fadeOut = 0.05,
	keys = seq({
		{ t = 0.1, ease = { "Back", "Out" }, pose = PLANT },
	}, tremble(0.12, 0.46, 7, PLANT, { Waist = true, Neck = true, RightShoulder = true, RightElbow = true }, 2.8), {
		{ t = 0.5, ease = { "Exponential", "Out" }, pose = merge(PLANT, root(0, -0.6, 0.15), { -- LASH: the roar
			Waist = { 12, 0, 0 }, Neck = { 22, 0, 0 },
			RightShoulder = { 60, 0, 80 }, RightElbow = { 10, 0, 0 }, RightWrist = { -40, 0, 0 },
			LeftShoulder = { 60, 0, -80 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -40, 0, 0 },
		}) },
		{ t = 0.62, ease = { "Sine", "Out" }, pose = merge(PLANT, root(0, -0.6, 0.15), {
			Waist = { 14, 0, 0 }, Neck = { 26, 0, 0 },
			RightShoulder = { 64, 0, 84 }, RightElbow = { 8, 0, 0 }, RightWrist = { -40, 0, 0 },
			LeftShoulder = { 64, 0, -84 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -40, 0, 0 },
		}) },
		{ t = 0.82, ease = { "Quad", "InOut" }, pose = merge(PLANT, { -- re-chamber, eyes on the cluster
			Waist = { -6, -20, 0 }, Neck = { 30, 14, 0 },
			RightShoulder = { -30, 0, 26 }, RightElbow = { 125, 0, 0 }, RightWrist = { 10, 0, 0 },
			LeftShoulder = { 150, 0, -20 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -10, 0, 0 },
		}) },
		{ t = 1.02, ease = { "Quad", "Out" }, pose = merge(root(0, -1.1, 0), { -- pre-leap crouch
			LeftHip = { 80, 0, -10 }, RightHip = { 80, 0, 10 }, LeftKnee = { -125, 0, 0 }, RightKnee = { -125, 0, 0 },
			LeftAnkle = { 45, 0, 0 }, RightAnkle = { 45, 0, 0 },
			Waist = { -26, -10, 0 }, Neck = { 34, 0, 0 },
			RightShoulder = { -40, 0, 30 }, RightElbow = { 125, 0, 0 },
			LeftShoulder = { -30, 0, -30 }, LeftElbow = { 40, 0, 0 },
		}) },
	}),
}

-- G: the leap and the upward smash (played at cast 1.10; clip 0.32 = cast 1.42, the fist arrives ~1.39-1.40)
Clips.OFASmash = {
	length = 0.6, fadeIn = 0.03, fadeOut = 0.06,
	keys = {
		{ t = 0.06, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.2, 0), { -- launch: body extended up
			LeftHip = { 10, 0, -6 }, RightHip = { -6, 0, 6 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -10, 0, 0 },
			LeftAnkle = { -30, 0, 0 }, RightAnkle = { -30, 0, 0 },
			Waist = { 8, -24, 0 }, Neck = { 30, 10, 0 },
			RightShoulder = { -20, 0, 30 }, RightElbow = { 120, 0, 0 }, RightWrist = { 10, 0, 0 },
			LeftShoulder = { 120, 0, -30 }, LeftElbow = { 20, 0, 0 },
		}) },
		{ t = 0.27, ease = { "Quad", "Out" }, pose = merge(root(0, 0.2, 0), { -- coil in the air
			LeftHip = { 50, 0, -10 }, LeftKnee = { -80, 0, 0 }, RightHip = { 30, 0, 10 }, RightKnee = { -60, 0, 0 },
			Waist = { -4, -34, 0 }, Neck = { 34, 20, 0 },
			RightShoulder = { -50, 0, 40 }, RightElbow = { 130, 0, 0 }, RightWrist = { 20, 0, 0 },
			LeftShoulder = { 100, 0, -30 }, LeftElbow = { 20, 0, 0 },
		}) },
		{ t = 0.32, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.4, 0), { -- 1,000,000% DETROIT SMASH
			Waist = { 14, 30, 0 }, Neck = { 40, -16, 0 },
			RightShoulder = { 172, 0, 6 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { -30, 0, -50 }, LeftElbow = { 50, 0, 0 },
			LeftHip = { 30, 0, -10 }, LeftKnee = { -70, 0, 0 }, RightHip = { -20, 0, 10 }, RightKnee = { -30, 0, 0 },
			RightAnkle = { -20, 0, 0 },
		}) },
		{ t = 0.55, ease = { "Sine", "Out" }, pose = merge(root(0, 0.4, 0), {
			Waist = { 12, 26, 0 }, Neck = { 38, -14, 0 },
			RightShoulder = { 170, 0, 8 }, RightElbow = { 2, 0, 0 },
		}) },
	},
}

-- G: the float down on the broken arm (played at cast 1.62), the landing, the power stance
Clips.OFAFloat = {
	length = 1.15, fadeIn = 0.08, fadeOut = 0.15,
	keys = {
		{ t = 0.15, ease = { "Sine", "Out" }, pose = merge(root(0, 0, 0), {
			Waist = { 10, 0, 0 }, Neck = { 28, 0, 0 },
			RightShoulder = { 20, 0, 30 }, RightElbow = { 20, 0, 0 }, RightWrist = { 30, 0, 0 }, -- limp, smoking
			LeftShoulder = { 40, 0, -60 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { -10, 0, 0 },
			LeftHip = { 20, 0, -8 }, LeftKnee = { -40, 0, 0 }, LeftAnkle = { -20, 0, 0 },
			RightHip = { 6, 0, 6 }, RightKnee = { -20, 0, 0 }, RightAnkle = { -30, 0, 0 },
		}) },
		{ t = 0.75, ease = { "Sine", "InOut" }, pose = merge(root(0, 0, 0), { -- legs reach for the ground; the root drops only on landing
			LeftHip = { 30, 0, -10 }, LeftKnee = { -50, 0, 0 }, RightHip = { 30, 0, 10 }, RightKnee = { -50, 0, 0 },
			Neck = { 10, 0, 0 },
		}) },
		{ t = 0.9, ease = { "Quad", "Out" }, pose = merge(CROUCH, {
			Waist = { -24, 0, 0 }, Neck = { 6, 0, 0 },
			RightShoulder = { 10, 0, 24 }, RightElbow = { 30, 0, 0 }, RightWrist = { 30, 0, 0 },
			LeftShoulder = { 20, 0, -40 }, LeftElbow = { 40, 0, 0 },
		}) },
		{ t = 1.0, ease = { "Back", "Out" }, pose = merge(LOW, { -- power stance: fists clenched, chin up
			Waist = { 6, 0, 0 }, Neck = { 10, 0, 0 },
			RightShoulder = { 20, 0, 40 }, RightElbow = { 100, 0, 0 }, RightWrist = { 0, 0, 0 },
			LeftShoulder = { 20, 0, -40 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
		}) },
	},
}

---------------------------------------------------------------------------------------------------
-- passive: the air step (tuck + a downward flick)
Clips.AirStep = {
	length = 0.42, fadeIn = 0.03, fadeOut = 0.12,
	keys = {
		{ t = 0.06, ease = { "Exponential", "Out" }, pose = merge(root(0, 0.15, 0), {
			LeftHip = { 80, 0, -8 }, LeftKnee = { -110, 0, 0 }, RightHip = { 64, 0, 8 }, RightKnee = { -96, 0, 0 },
			LeftAnkle = { -10, 0, 0 }, RightAnkle = { -10, 0, 0 }, Waist = { -10, 0, 0 },
			RightShoulder = { 20, 0, 22 }, RightElbow = { 0, 0, 0 }, RightWrist = { 50, 0, 0 },
			LeftShoulder = { 30, 0, -50 }, LeftElbow = { 20, 0, 0 },
		}) },
		{ t = 0.22, ease = { "Sine", "Out" }, pose = {
			LeftHip = { 40, 0, -8 }, LeftKnee = { -60, 0, 0 }, RightHip = { 30, 0, 8 }, RightKnee = { -50, 0, 0 },
			RightShoulder = { 10, 0, 30 }, RightWrist = { 10, 0, 0 },
		} },
		{ t = 0.4, ease = { "Sine", "InOut" }, pose = merge(root(0, 0, 0), {
			Waist = { 0, 0, 0 }, LeftHip = { 10, 0, -6 }, RightHip = { 10, 0, 6 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -20, 0, 0 },
		}) },
	},
}

-- the mode's end: he clutches the broken right arm and slumps
Clips.Burnout = {
	length = 0.8, fadeIn = 0.06, fadeOut = 0.2,
	keys = {
		{ t = 0.12, ease = { "Quad", "Out" }, pose = merge(LOW, {
			Waist = { -20, 10, 0 }, Neck = { -14, -10, 0 },
			RightShoulder = { 25, 0, -35 }, RightElbow = { 90, 0, 0 }, RightWrist = { 20, 0, 0 },
			LeftShoulder = { 62, 0, 80 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
		}) },
		{ t = 0.55, ease = { "Sine", "InOut" }, pose = merge(LOW, { -- still clutching the arm
			Waist = { -24, 8, 0 }, Neck = { -18, -8, 0 },
			RightShoulder = { 25, 0, -35 }, RightElbow = { 90, 0, 0 }, RightWrist = { 20, 0, 0 },
			LeftShoulder = { 62, 0, 80 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
		}) },
		{ t = 0.78, ease = { "Sine", "InOut" }, pose = REST },
	},
}

-- per-move clip passes: every ModuleScript child of this module returns function(H) -> { ClipName = clip, ... }; its
-- clips replace (or add to) these by name. H carries this file's helpers and stances.
do
	local H = {
		merge = merge, seq = seq, root = root, tremble = tremble, Clips = Clips,
		STAND = STAND, CROUCH = CROUCH, LOW = LOW, RELAX = RELAX, WIDE = WIDE, REST = REST, BRACE = BRACE, COIL = COIL,
		PLANT = PLANT,
	}
	local kids = script:GetChildren()
	table.sort(kids, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in ipairs(kids) do
		if child:IsA("ModuleScript") then
			local ok, f = pcall(require, child)
			local ok2, t = false, f
			if ok and type(f) == "function" then
				ok2, t = pcall(f, H)
			end
			if ok2 and type(t) == "table" then
				for name, clip in pairs(t) do
					Clips[name] = clip
				end
			else
				warn("[OneForAllKit.Clips] pass " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return Clips
