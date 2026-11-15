--!nocheck
-- StormdrawKit.Client.Poses: every body pose and clip of the kit, in GojoShared.Client.ProceduralAnimator's format:
--   clip = { length, fadeIn, fadeOut, keys = { { t, ease = { style, direction }, pose = { Joint = { x, y, z, pos? } } } } }
-- Angles are degrees. Signs: shoulder / elbow / hip / wrist flexion +X, knee flexion -X, lean forward Waist -X, chin up
-- Neck +X, right arm out Z+ (across the body Z-), Root pos -Y crouches and -Z steps forward. The sword sits in the
-- right fist pointing out of the knuckles, so the blade's elevation is about shoulder + elbow + wrist flexion. The
-- sword-arm angles were solved against an R15 rig (blade direction / hand on the sheathed grip), not eyeballed.
-- Re-pose a move here; the client only ever plays what this module returns.
local V = Vector3.new
local P = {}

local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftWrist", "RightWrist",
	"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" }

local function merge(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end

-- every joint named, so a clip that moves between two poses never leaves a joint at whatever a later key says
local function full(pose)
	for _, n in ipairs(JOINTS) do
		if pose[n] == nil then
			pose[n] = { 0, 0, 0 }
		end
	end
	return pose
end

local CAP = { Elbow = { 0, 155 }, Knee = { -155, 0 }, Wrist = { -80, 60 } }
-- pose a -> b by k (k > 1 overshoots past b), kept inside what an elbow / knee / wrist can do
local function toward(a, b, k)
	local out = {}
	local names = {}
	for n in pairs(a) do
		names[n] = true
	end
	for n in pairs(b) do
		names[n] = true
	end
	for n in pairs(names) do
		local va, vb = a[n] or { 0, 0, 0 }, b[n] or { 0, 0, 0 }
		local v = {}
		for i = 1, 3 do
			v[i] = (va[i] or 0) + ((vb[i] or 0) - (va[i] or 0)) * k
		end
		for suffix, lim in pairs(CAP) do
			if n:sub(-#suffix) == suffix then
				v[1] = math.clamp(v[1], lim[1], lim[2])
			end
		end
		if va.pos or vb.pos then
			v.pos = (va.pos or V()):Lerp(vb.pos or V(), k)
		end
		out[n] = v
	end
	return out
end

-- a pose that drops the Root bends both legs to match, so the feet stay on the floor
local function ground(pose)
	local r = pose.Root
	local y = r and r.pos and r.pos.Y or 0
	if y < -0.05 then
		local th = math.deg(math.acos(math.clamp(1 + y / 2.1, -1, 1)))
		for _, side in ipairs({ "Right", "Left" }) do
			local hip, knee = pose[side .. "Hip"], pose[side .. "Knee"]
			pose[side .. "Hip"] = { math.max(hip and hip[1] or 0, th), 0, hip and hip[3] or (side == "Right" and 6 or -6) }
			pose[side .. "Knee"] = { math.min(knee and knee[1] or 0, -2 * th), 0, 0 }
			pose[side .. "Ankle"] = { th * 0.9, 0, 0 }
		end
	end
	return pose
end

---------------------------------------------------------------------------------------------------
-- stances
-- a deep lunge: right foot forward and bent, left leg trailing with the knee near the floor
local LUNGE = {
	RightHip = { 80, 0, 6 }, RightKnee = { -100, 0, 0 }, RightAnkle = { 20, 0, 0 },
	LeftHip = { -15, 0, -8 }, LeftKnee = { -75, 0, 0 }, LeftAnkle = { 35, 0, 0 },
}
local BENT = { RightHip = { 14, 0, 8 }, RightKnee = { -24, 0, 0 }, LeftHip = { -6, 0, -8 }, LeftKnee = { -18, 0, 0 } }

-- the iaido draw stance: low, coiled, the right hand over the grip at the left hip, the left hand on the scabbard
P.Iai = full(merge(LUNGE, {
	Root = { 0, 0, 0, pos = V(0, -1.0, 0) },
	Waist = { -30, -20, 0 }, Neck = { 24, 16, 0 },
	RightShoulder = { 90, 30, -90 }, RightElbow = { 20, 0, 0 },
	LeftShoulder = { -35, 0, 15 }, LeftElbow = { 40, 0, 0 },
}))
-- the cut's follow-through: still low, the sword arm out to the side with the blade trailing out, back and down
P.Zanshin = full(merge(LUNGE, {
	Root = { 0, 0, 0, pos = V(0, -0.9, 0) },
	Waist = { -24, 24, 0 }, Neck = { 16, -16, 0 },
	RightShoulder = { -135, 0, 85 }, RightElbow = { 6, 0, 0 }, RightWrist = { -70, 0, 0 },
	LeftShoulder = { -30, 0, 15 }, LeftElbow = { 45, 0, 0 },
}))
-- the sword going home: upright, the right hand back at the left hip
P.Sheathe = full(ground(merge(BENT, {
	Root = { 0, 0, 0, pos = V(0, -0.25, 0) },
	Waist = { -8, -14, 0 }, Neck = { 6, 10, 0 },
	RightShoulder = { 90, 45, -90 }, RightElbow = { 20, 0, 0 },
	LeftShoulder = { -40, 0, 15 }, LeftElbow = { 50, 0, 0 },
})))
-- asleep on his feet: the head hangs, the arms are limp
P.Slumber = full({
	Root = { 0, 0, 0, pos = V(0, -0.12, 0) },
	Waist = { -14, 0, 3 }, Neck = { -34, 0, 6 },
	RightShoulder = { 8, 0, 4 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 8, 0, -4 }, LeftElbow = { 12, 0, 0 },
	RightHip = { 18, 0, 4 }, RightKnee = { -36, 0, 0 }, RightAnkle = { 16, 0, 0 },
	LeftHip = { 18, 0, -4 }, LeftKnee = { -36, 0, 0 }, LeftAnkle = { 16, 0, 0 },
})
P.SlumberDeep = full({
	Root = { 0, 0, 0, pos = V(0, -0.2, 0) },
	Waist = { -22, 0, -4 }, Neck = { -46, 0, -8 },
	RightShoulder = { 12, 0, 3 }, RightElbow = { 16, 0, 0 }, LeftShoulder = { 12, 0, -3 }, LeftElbow = { 16, 0, 0 },
	RightHip = { 24, 0, 4 }, RightKnee = { -48, 0, 0 }, RightAnkle = { 22, 0, 0 },
	LeftHip = { 24, 0, -4 }, LeftKnee = { -48, 0, 0 }, LeftAnkle = { 22, 0, 0 },
})
-- flying inside the dragon: the body level, the sword thrust out ahead, the legs trailing, the eyes on the path
P.Thrust = full({
	Root = { -58, 0, 0, pos = V(0, -0.2, 0) },
	Waist = { -12, 18, 0 }, Neck = { 72, -12, 0 },
	RightShoulder = { 150, 0, 6 }, RightElbow = { 4, 0, 0 }, RightWrist = { -78, 0, 0 },
	LeftShoulder = { -28, 0, -22 }, LeftElbow = { 30, 0, 0 },
	RightHip = { -12, 0, 6 }, RightKnee = { -28, 0, 0 }, LeftHip = { 18, 0, -6 }, LeftKnee = { -62, 0, 0 },
})
-- the breath: chest out and head back, then both fists drawn in
P.BreathIn = full({
	Root = { 0, 0, 0, pos = V(0, 0.08, 0) },
	Waist = { 12, 0, 0 }, Neck = { 16, 0, 0 },
	RightShoulder = { -22, 0, 40 }, RightElbow = { 22, 0, 0 }, LeftShoulder = { -22, 0, -40 }, LeftElbow = { 22, 0, 0 },
})
P.BreathOut = full(ground(merge(BENT, {
	Root = { 0, 0, 0, pos = V(0, -0.3, 0) },
	Waist = { -14, 0, 0 }, Neck = { 10, 0, 0 },
	RightShoulder = { 30, 0, 22 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 30, 0, -22 }, LeftElbow = { 100, 0, 0 },
})))

---------------------------------------------------------------------------------------------------
-- clips
function P.hold(pose, length, fadeIn, fadeOut)
	return { length = length, fadeIn = fadeIn or 0.08, fadeOut = fadeOut or 0.25, keys = { { t = 0, pose = pose }, { t = length, pose = pose } } }
end

-- after a dash: the follow-through held for `hold` seconds, then the sword goes home (sheatheAt = when it clicks in)
function P.zanshin(hold)
	return { length = hold + 0.6, fadeIn = 0.03, fadeOut = 0.25, sheatheAt = hold + 0.2, keys = {
		{ t = 0.05, ease = { "Exponential", "Out" }, pose = P.Zanshin },
		{ t = hold, ease = { "Sine", "InOut" }, pose = P.Zanshin },
		{ t = hold + 0.2, ease = { "Sine", "InOut" }, pose = P.Sheathe },
		{ t = hold + 0.45, ease = { "Sine", "InOut" }, pose = P.Sheathe },
	} }
end

-- the ultimate's charge: asleep, sinking deeper, then snapped awake into the draw stance for the last beat
function P.dragonCharge(time)
	return { length = time + 0.2, fadeIn = 0.22, fadeOut = 0.05, wakeAt = time * 0.74, keys = {
		{ t = 0, pose = P.Slumber },
		{ t = time * 0.3, ease = { "Sine", "InOut" }, pose = P.Slumber },
		{ t = time * 0.72, ease = { "Sine", "InOut" }, pose = P.SlumberDeep },
		{ t = time * 0.84, ease = { "Exponential", "Out" }, pose = P.Iai },
		{ t = time + 0.2, pose = P.Iai },
	} }
end

function P.inhale(time)
	return { length = time + 0.55, fadeIn = 0.15, fadeOut = 0.3, keys = {
		{ t = time * 0.45, ease = { "Sine", "Out" }, pose = P.BreathIn },
		{ t = time, ease = { "Sine", "InOut" }, pose = P.BreathIn },
		{ t = time + 0.12, ease = { "Exponential", "Out" }, pose = P.BreathOut },
		{ t = time + 0.55, pose = P.BreathOut },
	} }
end

---------------------------------------------------------------------------------------------------
-- the M1 string: wind-up -> strike -> overshoot -> settle on top of a sword-ready stance
local GUARD = merge(BENT, {
	Root = { 0, 0, 0, pos = V(0, -0.15, 0) }, Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 },
	RightShoulder = { 28, 0, 14 }, RightElbow = { 38, 0, 0 }, RightWrist = { -10, 0, 0 },
	LeftShoulder = { 16, 0, -16 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
})

local function cut(length, tWind, tHit, tSettle, wind, hit, spin)
	wind, hit = merge(GUARD, wind), merge(GUARD, hit)
	local over = toward(wind, hit, 1.12)
	local settle = toward(hit, GUARD, 0.55)
	local poses = { wind, hit, over, settle }
	for _, p in ipairs(poses) do
		full(ground(p))
	end
	if spin then
		-- a full turn of the Root through the cut; the keys stay under 180 degrees apart so each lerp goes the long way
		for i, share in ipairs({ 0.22, 0.55, 0.8, 1 }) do
			local r = poses[i].Root
			poses[i].Root = { r[1] or 0, (r[2] or 0) + spin * share, r[3] or 0, pos = r.pos }
		end
	end
	return { length = length, fadeIn = 0.05, fadeOut = 0.16, hitAt = tHit, keys = {
		{ t = tWind, ease = { "Sine", "Out" }, pose = wind },
		{ t = tHit, ease = { "Exponential", "Out" }, pose = hit },
		{ t = tHit + 0.05, ease = { "Quad", "Out" }, pose = over },
		{ t = tSettle, ease = { "Back", "Out" }, pose = settle },
	} }
end

P.Slash = {
	-- 1: the draw cut - out of the scabbard, rising from the left hip to the upper right
	cut(0.42, 0.06, 0.12, 0.28,
		{ RightShoulder = { 90, 45, -90 }, RightElbow = { 30, 0, 0 }, RightWrist = { 0, 0, 0 }, LeftShoulder = { -40, 0, 20 }, LeftElbow = { 40, 0, 0 },
			Waist = { -12, -30, 0 }, Neck = { 6, 20, 0 }, Root = { 0, 0, 0, pos = V(0, -0.4, 0) } },
		{ RightShoulder = { 90, 0, 80 }, RightElbow = { 6, 0, 0 }, RightWrist = { -60, 0, 0 }, LeftShoulder = { -20, 0, -30 }, LeftElbow = { 40, 0, 0 },
			Waist = { -6, 32, 0 }, Neck = { 4, -22, 0 }, Root = { 0, 0, 0, pos = V(0, -0.2, -0.3) } }),
	-- 2: the return cut - a forehand diagonal, high right to low left
	cut(0.42, 0.06, 0.12, 0.28,
		{ RightShoulder = { 55, 0, -10 }, RightElbow = { 60, 0, 0 }, RightWrist = { 10, 0, 0 }, Waist = { 4, 28, 0 }, Neck = { 0, -18, 0 },
			Root = { 0, 0, 0, pos = V(0, 0.05, 0.1) } },
		{ RightShoulder = { -25, 0, -90 }, RightElbow = { 8, 0, 0 }, RightWrist = { -60, 0, 0 }, Waist = { -12, -30, 0 }, Neck = { 8, 20, 0 },
			Root = { 0, 0, 0, pos = V(0, -0.2, -0.25) } }),
	-- 3: the spinning cut - a full turn with the blade level
	cut(0.5, 0.08, 0.15, 0.36,
		{ RightShoulder = { 70, 0, -60 }, RightElbow = { 70, 0, 0 }, RightWrist = { -30, 0, 0 }, Waist = { -4, -30, 0 },
			Root = { 0, 0, 0, pos = V(0, -0.25, 0) } },
		{ RightShoulder = { 84, 0, 74 }, RightElbow = { 5, 0, 0 }, RightWrist = { -72, 0, 0 }, LeftShoulder = { 30, 0, -70 }, LeftElbow = { 20, 0, 0 },
			Waist = { -8, 26, 0 }, Root = { 0, 0, 0, pos = V(0, -0.3, -0.2) } }, 360),
	-- 4: the leaping cleave - both hands overhead, driven down through the target
	cut(0.66, 0.11, 0.2, 0.46,
		{ RightShoulder = { 10, 0, 0 }, LeftShoulder = { 40, 0, -30 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 80, 0, 0 }, RightWrist = { 30, 0, 0 },
			Waist = { 16, 0, 0 }, Neck = { -8, 0, 0 }, RightHip = { 40, 0, 6 }, RightKnee = { -70, 0, 0 }, LeftHip = { 20, 0, -6 }, LeftKnee = { -60, 0, 0 },
			Root = { 0, 0, 0, pos = V(0, 1.0, 0.1) } },
		{ RightShoulder = { 60, 0, 0 }, LeftShoulder = { 46, 0, 8 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 }, RightWrist = { -60, 0, 0 },
			Waist = { -28, 0, 0 }, Neck = { 14, 0, 0 }, Root = { 0, 0, 0, pos = V(0, -0.5, -0.35) } }),
}

P.merge, P.toward, P.full = merge, toward, full
return P
