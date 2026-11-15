--!nocheck
-- ZangetsuKit.Clips: procedural keyframes for the Zangetsu kit (Ichigo), played by GojoShared.Client.ProceduralAnimator.
-- This base module holds the shared helpers, the validated stances and the two idle CARRY overlays the scaffold plays;
-- every move's clips live in a CHILD ModuleScript (Clips.M1 / Getsuga / Shunpo / Hollow / Bankai) that returns
-- function(H) -> { ClipName = clip, ... } (merged by name over these by the footer).
-- Signs (measured on the live rig): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X,
-- +Y turns left, right limb out Z+, left limb out Z-, Neck +X lifts the chin. Root pos: -Y crouches, +Z slides back,
-- +X slides right. Root rotation: -X pitches forward, +Y yaws left, +Z rolls the right side up.
-- SwordGrip (the sword's Motor6D, RightHand -> Handle; ProceduralAnimator poses it like any joint):
--   {0,0,0}  the blade continues the forearm line (elbow -> wrist -> tip)
--   +X       tilts the blade the way flexion goes (toward the palm side; {90,0,0} on a hanging arm = blade forward)
--   Y        rolls the blade about its own axis: which way the EDGE faces (H.EDGE):
--            RISE = 0 (edge leads a rising / flexing swing), CHOP = 180 (edge leads a downward chop),
--            FORE = -90 (edge leads a forehand sweep right -> left), BACK = 90 (edge leads a backhand left -> right)
--   +Z       tilts the blade toward the hand's -X (for the right hand: inward, toward his left)
-- Rules for every kit clip: a clip that names RightShoulder names SwordGrip in EVERY key (the idle carry overlay
-- underneath also poses SwordGrip); every clip's LAST key returns the right arm + SwordGrip to H.CARRY_SK (Shikai
-- clips) or H.CARRY_BK (Bankai-form clips) so the hand-back to the carry overlay is seamless; the sword tip stays
-- >= 0.3 above the floor on every key (FK-check: floor = HRP.Y - (HipHeight + HRP.Size.Y/2) on the preview rig).
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
-- grip(x, y, z): the SwordGrip pose (see the header)
local function grip(x, y, z)
	return { SwordGrip = { x or 0, y or 0, z or 0 } }
end
-- n strain-shake keys between t0 and t1 on the named joints (identical to OneForAllKit.Clips' tremble)
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

local EDGE = { RISE = 0, CHOP = 180, FORE = -90, BACK = 90 }

---------------------------------------------------------------------------------------------------
-- stances (legs from the Deku kit, FK-verified there; arms + sword checked on the preview rig by the architect)
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
-- planted split stance: left foot forward, right leg braced back (soles within 0.01 of the floor)
local WIDE = {
	Root = { 0, 0, 0, pos = Vector3.new(0, -0.65, 0.15) },
	LeftHip = { 58, 0, -16 }, LeftKnee = { -101, 0, 0 }, LeftAnkle = { 43, 0, 0 },
	RightHip = { -39, 0, 16 }, RightKnee = { -21, 0, 0 }, RightAnkle = { 64, 0, 0 },
}
-- the free (left) arm at rest
local RELAX = { LeftShoulder = { 10, 0, -14 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 } }

-- the idle carries (right arm + sword only; the default walk/idle animates everything else)
-- Shikai: the cleaver rests on his right shoulder, edge up, tip behind him (hand at chin height, 0.46 in front,
-- blade 0.07 above the shoulder top, 1.38 from the head centre; tip 5.4 above the floor in REST)
local CARRY_SK = {
	RightShoulder = { 55, 0, 12 }, RightElbow = { 130, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { 80, EDGE.CHOP, 0 },
}
-- Bankai: Tensa Zangetsu held low at his side, trailing back 12 deg below horizontal, edge down, slightly out
-- (tip 1.9 above the floor in REST_BK, 1.7 clear of the right thigh)
local CARRY_BK = {
	RightShoulder = { 8, 0, 16 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 }, SwordGrip = { -101, 0, -10 },
}

local REST = merge(STAND, RELAX, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }, CARRY_SK)
local REST_BK = merge(STAND, RELAX, { Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 } }, CARRY_BK)

-- combat ready: WIDE legs, chest turned a little right, blade out in front pointing forward-up 17 deg, edge left
-- (tip 4.2 above the floor), left hand open forward
local READY = merge(WIDE, {
	Waist = { -8, -16, 0 }, Neck = { 2, 14, 0 },
	RightShoulder = { 42, 18, 14 }, RightElbow = { 38, 0, 0 }, RightWrist = { -6, 0, 0 },
	LeftShoulder = { 50, 0, -28 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	SwordGrip = { 48, EDGE.FORE, 6 },
})
-- overhead wind-up (Getsuga, chops): blade high, pointing up-back 38 deg above horizontal behind him
-- (2.38 from the head centre, tip 8.0 above the floor)
local RAISE = merge(WIDE, {
	Waist = { 6, -20, 0 }, Neck = { 8, 16, 0 },
	RightShoulder = { 165, 0, 12 }, RightElbow = { 35, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 60, 0, -30 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
	SwordGrip = { 25, EDGE.CHOP, 0 },
})
-- the diagonal release (Getsuga's money frame): blade swept down across to his low left (dir left-down-forward,
-- tip 1.07 above the floor), chest whipped left, left arm thrown back
local RELEASE = merge(WIDE, {
	Waist = { -18, 32, 0 }, Neck = { 6, -26, 0 },
	RightShoulder = { 62, 18, -12 }, RightElbow = { 8, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { -30, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 },
	SwordGrip = { 24, EDGE.CHOP, 0 },
})
-- the "already cut" pose (Shunpo's arrival): back to them, sword arm out to the right, blade level out to the side
-- pointing a little back (tip 2.7 above the floor)
local AFTERCUT = merge(WIDE, {
	Waist = { -6, 18, 0 }, Neck = { 4, -10, 0 },
	RightShoulder = { 6, -20, 82 }, RightElbow = { 6, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 20, 0, -20 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
	SwordGrip = { -10, EDGE.BACK, 0 },
})
-- the Bankai pose: sword arm straight out in front, blade level, left hand clamping the right forearm
-- (left hand 1.11 from the right forearm centre = in contact)
local BANKAI_POSE = merge(WIDE, {
	Waist = { -4, -14, 0 }, Neck = { 4, 10, 0 },
	RightShoulder = { 90, 0, -2 }, RightElbow = { 2, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 110, -40, 70 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { -10, 0, 0 },
	SwordGrip = { 0, EDGE.FORE, 0 },
})
-- the left palm over his face (the hollow mask is drawn on behind it): hand 0.96 in front of the face centre
local MASK_HAND = {
	Waist = { -6, 0, 0 }, Neck = { -12, 0, 0 },
	LeftShoulder = { 110, -40, 50 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { -10, 0, 0 },
}

---------------------------------------------------------------------------------------------------
-- the idle carry overlays: played by ZangetsuClient on every Zangetsu character under every move clip
-- (one key; a 10-hour length so the track never ends on its own; the scaffold stops / swaps it)
local CARRY_LEN = 36000
Clips.CarryShikai = { length = CARRY_LEN, fadeIn = 0.25, fadeOut = 0.2, keys = { { t = 0, ease = { "Sine", "Out" }, pose = CARRY_SK } } }
Clips.CarryBankai = { length = CARRY_LEN, fadeIn = 0.25, fadeOut = 0.2, keys = { { t = 0, ease = { "Sine", "Out" }, pose = CARRY_BK } } }

-- per-move clip passes: every ModuleScript child of this module returns function(H) -> { ClipName = clip, ... }; its
-- clips replace (or add to) these by name. H carries this file's helpers and stances.
do
	local H = {
		merge = merge, seq = seq, root = root, grip = grip, tremble = tremble, Clips = Clips, EDGE = EDGE,
		STAND = STAND, CROUCH = CROUCH, LOW = LOW, WIDE = WIDE, RELAX = RELAX, REST = REST, REST_BK = REST_BK,
		CARRY_SK = CARRY_SK, CARRY_BK = CARRY_BK, CARRY_LEN = CARRY_LEN,
		READY = READY, RAISE = RAISE, RELEASE = RELEASE, AFTERCUT = AFTERCUT, BANKAI_POSE = BANKAI_POSE,
		MASK_HAND = MASK_HAND,
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
				warn("[ZangetsuKit.Clips] pass " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return Clips
