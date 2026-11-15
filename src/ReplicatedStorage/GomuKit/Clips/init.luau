--!nocheck
-- GomuKit.Clips: procedural keyframes for the Gomu kit (LUFFY), played by GojoShared.Client.ProceduralAnimator.
-- This base module holds the shared helpers and stances; every move's clips live in a CHILD ModuleScript (Clips.M1 /
-- Gatling / Rocket / Elephant / Gear5 / Scaffold) that returns function(H) -> { ClipName = clip, ... } (merged by name
-- over these by the footer). Clip names are prefixed by their move (M1_Jab1, Gatling_Loop, Gear5_Awaken ...).
-- clip = { length, fadeIn?, fadeOut?, keys = { { t, ease = {"Quad","Out"}, pose = { Joint = {x,y,z, pos = Vector3?} } } } }
-- Signs (measured on the live rig for the Zangetsu kit): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward
-- lean Waist -X, +Y turns left, right limb out Z+, left limb out Z-, Neck +X lifts the chin. Root pos: -Y crouches,
-- +Z slides back, +X slides right. Root rotation: -X pitches forward, +Y yaws left, +Z rolls the right side up.
-- CFrame.Angles(x, y, z) applies Z first. Keys more than 180 deg apart on one axis lerp the SHORT way (spin backwards):
-- put a key every <= 166 deg on any spin / flip.
-- A STRETCHED limb is drawn by GomuKit.Client.Shared (the real UpperArm / LowerArm / Hand are hidden while it is out),
-- so a clip only has to sell the BODY: the torso twist + lean toward the target, the shoulder thrown forward, the
-- other arm's guard, the legs. The stretch starts at the shoulder rig attachment, so it follows the Waist twist.
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
-- n strain-shake keys between t0 and t1 on the named joints (the Deku / Ichigo tremble)
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
-- one key: key(t, pose [, style, dir])
local function key(t, pose, style, dir)
	return { t = t, ease = { style or "Quad", dir or "Out" }, pose = pose }
end

---------------------------------------------------------------------------------------------------
-- stances. STAND / CROUCH / LOW / WIDE / RELAX are the FK-verified ones from the Deku / Ichigo kits. GUARD / PUFF /
-- BITE / SKY are Luffy's and NOT yet FK-checked on a rig: check them (feet on the floor, no limb through the torso)
-- before relying on them for exact contact.
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
-- an arm at rest
local RELAX = { LeftShoulder = { 10, 0, -14 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 } }
local RELAX_R = { RightShoulder = { 10, 0, 14 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 } }

-- Luffy's loose brawler guard: WIDE legs, chest a little turned, both fists up near the chin, chin down, a grin
local GUARD = merge(WIDE, {
	Waist = { -8, -12, 0 }, Neck = { -4, 10, 0 },
	RightShoulder = { 62, 0, 22 }, RightElbow = { 112, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 74, 0, -20 }, LeftElbow = { 118, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
-- Gatling / Gear windups: chest puffed, both elbows drawn back, a deep sit
local PUFF = merge(LOW, {
	Waist = { 10, 0, 0 }, Neck = { 10, 0, 0 },
	RightShoulder = { -40, 0, 30 }, RightElbow = { 95, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { -40, 0, -30 }, LeftElbow = { 95, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
-- Gear Third: the right thumb to the teeth (the bite before the inflate)
local BITE = merge(WIDE, {
	Waist = { -6, 8, 0 }, Neck = { -10, -6, 0 },
	RightShoulder = { 110, -30, -35 }, RightElbow = { 140, 0, 0 }, RightWrist = { -20, 0, 0 },
	LeftShoulder = { 30, 0, -20 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
-- reaching for the sky (Bajrang Gun's raised arm, the Rocket's double grab when the anchor is high)
local SKY = merge(STAND, {
	Waist = { 14, 0, 0 }, Neck = { 30, 0, 0 },
	RightShoulder = { 175, 0, 10 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 40, 0, -40 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
})

local REST = merge(STAND, RELAX, RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })

-- per-move clip passes: every ModuleScript child of this module returns function(H) -> { ClipName = clip, ... }; its
-- clips replace (or add to) these by name. H carries this file's helpers and stances.
do
	local H = {
		merge = merge, seq = seq, root = root, tremble = tremble, key = key, Clips = Clips,
		STAND = STAND, CROUCH = CROUCH, LOW = LOW, WIDE = WIDE, RELAX = RELAX, RELAX_R = RELAX_R, REST = REST,
		GUARD = GUARD, PUFF = PUFF, BITE = BITE, SKY = SKY,
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
				warn("[GomuKit.Clips] pass " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return Clips
