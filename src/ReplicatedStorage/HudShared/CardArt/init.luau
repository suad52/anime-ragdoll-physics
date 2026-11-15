--!nocheck
-- ReplicatedStorage.HudShared.CardArt (2026-11-10, owner: the card-art FIGURE pass): comic-style item art for every
-- shop / inventory card. API (CharacterSelect and CardArt.Icons code against it):
--   CardArt.draw(container: GuiObject, item: table, opts: { live: boolean? }?) -> boolean
-- Draws art filling `container`, adding ONLY children named "CardArt_*" (a re-draw first removes the old CardArt_*
-- children). Returns false when it has no art for the item - the caller then keeps its glyph orb. Never errors.
--   CardArt.handles(item) -> true when THIS file (not Icons) draws the item.
--   CardArt.avatarAura(container, auraItem, opts?) = CardArt.draw(container, { kind = "avatarAura", aura = auraItem }, opts):
--     the LOCAL PLAYER'S OWN avatar (a stripped clone of their character: clothes, accessories, face) posed in the aura,
--     filling the container edge to edge (a wide banner is fine). Cached snapshot, re-rendered on respawn / appearance
--     load; the comic dummy stands in while there is no character. opts.source = a Model to use instead (Studio tests).
-- THE SPLIT with CardArt.Icons (child module, drawn 2D icons): this file draws everything best shown with a FIGURE -
--   kind "aura" (ShopCatalog), {kind="skin", kit, id}, {kind="emote", id}, {kind="ko", id}, {kind="trail", id},
--   {kind="fighter", kit}, and the perks SpeedX2, JumpX2, DashPass, VIP, UltCharge, UltOutfit, AllFighters,
--   EarlyAccess, TauntHype, TauntTrash, StarterPack (+ the retired Trails / KOFX / Skins / Emotes packs, which legacy
--   owners still see in the inventory). Every other item goes to Icons.draw(container, item, opts).
-- HOW THE COMIC LOOK IS MADE (static: one ViewportFrame per card, rendered once, no per-frame code anywhere):
--   * FIGURE: a blocky R15 (part sizes + joint offsets measured off the game's stock R15 rig; head x1.16, hands x1.12)
--     posed by forward kinematics with the SAME {x, y, z, pos} joint angles ProceduralAnimator clips use
--     (Part1 = Part0 * C0 * CFrame.Angles(rad x, rad y, rad z) * C1:Inverse()), so emote art samples the real
--     PerkShared.Emotes.Clips keys. One cached template Model (body + face + hair) is cloned per figure.
--   * FLAT LIGHT (Ambient 220, LightColor 70): colours read as flat fills with a soft two-tone.
--   * INK: an inverted hull - a black copy of every figure part grown by `t` studs and pushed 0.62 studs AWAY from
--     the camera (scaled up by the push so it covers the same screen area). It shows round the silhouette and
--     wherever a limb is in front of the body, and never covers the part it outlines (t stays well under the push).
--   * ONE ViewportFrame per card (hard rule: with 15-30+ cards on screen the engine stops drawing some viewports -
--     cards came out blank or half drawn). Everything 3D shares it, ordered by DEPTH SLABS along the camera axis:
--     figure < ink < inner halo band < outer halo band < flames. A halo band = grown copies of the figure's parts in
--     the aura colours, each slid along its own camera ray (and scaled by the same factor, so it keeps its screen
--     footprint) until its FRONT sits on the slab's front plane - so no copy of one band can poke in front of the
--     other (a fixed per-part push let an arm's outer band land in front of the torso's inner band). Flame and
--     starburst "teeth" (two WedgePart halves = a triangle facing the camera) are laid out in SCREEN space.
--   * Outline widths (3D ink, UI ink, strokes) follow the container's REAL size: a card built while its page is hidden
--     (AbsoluteSize 0) is drawn for 64 px and re-fitted when the container first gets a size (and on a >15% resize).
--   * 2D backdrop in UI: gradient panel, sunburst rays, halftone dot corners, posterized glow, comic stickers /
--     speech bubbles / arrows (union-outlined: black copies first, fills on top, so overlaps have no inner line).
--   opts.live = true (a big preview) slowly spins the sunburst (one engine-driven TweenService tween).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CardArt = {}

local C = Color3.fromRGB
local V3 = Vector3.new
local V2 = Vector2.new
local CFn = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local clamp = math.clamp
local sin, cos = math.sin, math.cos

local INK = C(14, 12, 20)
local WHITE = C(255, 255, 255)
local BLACK = C(0, 0, 0)
local SKIN = C(255, 214, 180)
local GOLD = C(255, 205, 60)
local FONT = Font.fromEnum(Enum.Font.GothamBold)

local function mix(a, b, t)
	return a:Lerp(b, t)
end
local function darken(c, t)
	return c:Lerp(BLACK, t)
end
local function lighten(c, t)
	return c:Lerp(WHITE, t)
end
local function lum(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end
local function col(c, default)
	return typeof(c) == "Color3" and c or default
end
local function merge(...)
	local out = {}
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if type(t) == "table" then
			for k, v in pairs(t) do
				out[k] = v
			end
		end
	end
	return out
end

-- lazily required modules (cached; a missing one is cached as false, except Icons which may be added later)
local loaded = {}
local function load(key, find)
	local v = loaded[key]
	if v == nil then
		local ok, res = pcall(function()
			local inst = find()
			return inst and require(inst) or nil
		end)
		v = (ok and type(res) == "table") and res or false
		loaded[key] = v
	end
	return v or nil
end
local function sibling(name)
	return function()
		return script.Parent and script.Parent:FindFirstChild(name)
	end
end
local function perkShared(a, b)
	return function()
		local o = ReplicatedStorage:FindFirstChild("PerkShared")
		o = o and o:FindFirstChild(a)
		if b then
			o = o and o:FindFirstChild(b)
		end
		return o
	end
end
local function Kits()
	return load("Kits", sibling("Kits"))
end
local function Perks()
	return load("PerkCatalog", sibling("PerkCatalog"))
end
local function TrailStyle()
	return load("TrailStyle", perkShared("TrailStyle"))
end
local function EmoteClips()
	return load("Clips", perkShared("Emotes", "Clips"))
end
local function Icons()
	if loaded.Icons then
		return loaded.Icons
	end
	local inst = script:FindFirstChild("Icons")
	if not inst then
		return nil
	end
	local ok, res = pcall(require, inst)
	if ok and type(res) == "table" then
		loaded.Icons = res
		return res
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- the rig (measured off the stock R15: part sizes, joint C0 / C1 offsets; every joint has identity rotation)
local HEAD_K, HAND_K = 1.16, 1.12
local SIZES = {
	LowerTorso = V3(1.99, 0.4, 1.0),
	UpperTorso = V3(1.94, 1.7, 1.0),
	Head = V3(1.16, 1.18, 1.16) * HEAD_K,
	RightUpperArm = V3(1.0, 1.24, 1.0),
	RightLowerArm = V3(1.0, 1.12, 1.0),
	RightHand = V3(0.98, 0.32, 1.03) * HAND_K,
	LeftUpperArm = V3(1.0, 1.24, 1.0),
	LeftLowerArm = V3(1.0, 1.12, 1.0),
	LeftHand = V3(0.98, 0.32, 1.03) * HAND_K,
	RightUpperLeg = V3(0.99, 1.36, 0.97),
	RightLowerLeg = V3(0.99, 1.3, 0.97),
	RightFoot = V3(1.01, 0.31, 1.0),
	LeftUpperLeg = V3(0.99, 1.36, 0.97),
	LeftLowerLeg = V3(0.99, 1.3, 0.97),
	LeftFoot = V3(1.01, 0.31, 1.0),
}
local JOINTS = { -- FK order: joint, Part0, Part1, C0 offset, C1 offset
	{ "Root", "HumanoidRootPart", "LowerTorso", V3(0, -1, 0), V3(0, -0.2, 0) },
	{ "Waist", "LowerTorso", "UpperTorso", V3(0, 0.2, 0), V3(0, -0.849, 0) },
	{ "Neck", "UpperTorso", "Head", V3(0, 0.849, 0), V3(0, -0.576 * HEAD_K, 0) },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", V3(0.972, 0.598, 0), V3(-0.501, 0.419, 0) },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", V3(0, -0.355, 0), V3(0, 0.275, 0) },
	{ "RightWrist", "RightLowerArm", "RightHand", V3(0, -0.532, 0), V3(0, 0.132 * HAND_K, 0) },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", V3(-0.972, 0.598, 0), V3(0.501, 0.419, 0) },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", V3(0, -0.355, 0), V3(0, 0.275, 0) },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", V3(0, -0.532, 0), V3(0, 0.132 * HAND_K, 0) },
	{ "RightHip", "LowerTorso", "RightUpperLeg", V3(0.498, -0.2, 0), V3(0, 0.471, 0) },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", V3(0, -0.449, 0), V3(0, 0.413, 0) },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", V3(0, -0.596, 0), V3(0, 0.106, 0) },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", V3(-0.498, -0.2, 0), V3(0, 0.471, 0) },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", V3(0, -0.449, 0), V3(0, 0.413, 0) },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", V3(0, -0.596, 0), V3(0, 0.106, 0) },
}
local BODY = {}
for _, j in ipairs(JOINTS) do
	table.insert(BODY, j[3])
end

-- forward kinematics: pose = { Joint = { x, y, z, pos = Vector3? } } (degrees) -> part name -> CFrame (root at origin,
-- facing -Z). stretch = { PartName = k } lengthens a part along its Y (Gum-Gum arms).
local function solve(pose, stretch)
	local cfs = { HumanoidRootPart = CFrame.identity }
	for _, j in ipairs(JOINTS) do
		local p0, p1, c0, c1 = j[2], j[3], j[4], j[5]
		local k0 = stretch and stretch[p0] or 1
		local k1 = stretch and stretch[p1] or 1
		local v = pose and pose[j[1]]
		local t = CFrame.identity
		if type(v) == "table" then
			t = ANG(rad(v[1] or 0), rad(v[2] or 0), rad(v[3] or 0))
			if typeof(v.pos) == "Vector3" then
				t = CFn(v.pos) * t
			end
		end
		cfs[p1] = cfs[p0] * CFn(c0.X, c0.Y * k0, c0.Z) * t * CFn(c1.X, c1.Y * k1, c1.Z):Inverse()
	end
	return cfs
end

---------------------------------------------------------------------------------------------------------------------
-- poses (signs as in the Emotes.Clips header: shoulder / hip flexion +X, knee flexion -X, Waist -X leans forward,
-- +Y turns left, right limb out +Z, left limb out -Z, Neck +X lifts the chin, Root pos -Y crouches)
local V = V3
local STAND = { Root = { 0, 0, 0, pos = V(0, 0, 0) }, LeftHip = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 },
	RightKnee = { 0, 0, 0 }, LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 } }
local LOW = { Root = { 0, 0, 0, pos = V(0, -0.5, 0) }, LeftHip = { 43, 0, -12 }, RightHip = { 42, 0, 12 }, LeftKnee = { -82, 0, 0 },
	RightKnee = { -83, 0, 0 }, LeftAnkle = { 39, 0, 0 }, RightAnkle = { 39, 0, 0 } }
local WIDE = { Root = { 0, 0, 0, pos = V(0, -0.65, 0.15) }, LeftHip = { 58, 0, -16 }, LeftKnee = { -101, 0, 0 }, LeftAnkle = { 43, 0, 0 },
	RightHip = { -39, 0, 16 }, RightKnee = { -21, 0, 0 }, RightAnkle = { 64, 0, 0 } }
local POSES = {
	STANCE = merge(LOW, { Waist = { -6, 28, 0 }, Neck = { 2, -24, 0 }, RightShoulder = { 45, 0, 22 }, RightElbow = { 120, 0, 0 },
		LeftShoulder = { 75, -10, -12 }, LeftElbow = { 85, 0, 0 } }),
	PUNCH = merge(WIDE, { Waist = { -10, 30, 0 }, Neck = { 6, -24, 0 }, RightShoulder = { 92, 0, 8 }, RightElbow = { 4, 0, 0 },
		LeftShoulder = { 55, 0, -18 }, LeftElbow = { 120, 0, 0 } }),
	PALM = merge(WIDE, { Waist = { -8, 26, 0 }, Neck = { 4, -22, 0 }, RightShoulder = { 86, 0, 6 }, RightElbow = { 10, 0, 0 },
		LeftShoulder = { -25, 0, -30 }, LeftElbow = { 40, 0, 0 } }),
	CHIDORI = merge(LOW, { Waist = { -16, -24, 0 }, Neck = { 6, 22, 0 }, LeftShoulder = { 38, 0, -14 }, LeftElbow = { 18, 0, 0 },
		RightShoulder = { 30, 0, 35 }, RightElbow = { 95, 0, 0 } }),
	KAME = merge(WIDE, { Waist = { -8, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 82, 0, -16 }, RightElbow = { 8, 0, 0 },
		LeftShoulder = { 82, 0, 16 }, LeftElbow = { 8, 0, 0 } }),
	AURA = merge(LOW, { Root = { 0, 0, 0, pos = V(0, -0.55, 0) }, Waist = { -6, 0, 0 }, Neck = { -4, 0, 0 }, RightShoulder = { -30, 10, 14 },
		RightElbow = { 70, 0, 0 }, LeftShoulder = { -30, -10, -14 }, LeftElbow = { 70, 0, 0 } }),
	ROAR = merge(WIDE, { Waist = { 18, 0, 0 }, Neck = { 28, 0, 0 }, RightShoulder = { 35, 0, 75 }, RightElbow = { 30, 0, 0 },
		LeftShoulder = { 35, 0, -75 }, LeftElbow = { 30, 0, 0 } }),
	HERO = merge(STAND, { Waist = { 4, 12, 0 }, Neck = { 10, -8, 0 }, RightShoulder = { 168, 0, 10 }, RightElbow = { 15, 0, 0 },
		LeftShoulder = { -30, -10, -14 }, LeftElbow = { 70, 0, 0 }, LeftHip = { 0, 0, -8 }, RightHip = { 0, 0, 8 } }),
	RUN = { Root = { -16, 0, 0, pos = V(0, -0.15, 0) }, Waist = { -8, 12, 0 }, Neck = { 18, -12, 0 }, LeftHip = { 75, 0, -4 },
		LeftKnee = { -70, 0, 0 }, LeftAnkle = { 10, 0, 0 }, RightHip = { -30, 0, 4 }, RightKnee = { -100, 0, 0 }, RightAnkle = { -20, 0, 0 },
		RightShoulder = { 75, 0, 8 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { -55, 0, -8 }, LeftElbow = { 75, 0, 0 } },
	JUMP = { Root = { 8, 0, 0, pos = V(0, 1.4, 0) }, Waist = { 4, 0, 0 }, Neck = { 22, 0, 0 }, LeftHip = { 95, 0, -10 },
		LeftKnee = { -120, 0, 0 }, LeftAnkle = { 30, 0, 0 }, RightHip = { 35, 0, 10 }, RightKnee = { -105, 0, 0 }, RightAnkle = { 30, 0, 0 },
		RightShoulder = { 165, 0, 10 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 20, 0, -40 }, LeftElbow = { 60, 0, 0 } },
	DASH = { Root = { -28, 0, 0, pos = V(0, -0.8, 0) }, Waist = { -12, 0, 0 }, Neck = { 38, 0, 0 }, LeftHip = { 95, 0, -8 },
		LeftKnee = { -105, 0, 0 }, LeftAnkle = { 35, 0, 0 }, RightHip = { -10, 0, 8 }, RightKnee = { -35, 0, 0 }, RightAnkle = { 45, 0, 0 },
		RightShoulder = { -75, 0, 12 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { -75, 0, -12 }, LeftElbow = { 8, 0, 0 } },
	KO = { Root = { 48, 20, -10, pos = V(0, 0.9, 0.4) }, Waist = { 18, -10, 0 }, Neck = { 38, 15, 8 }, RightShoulder = { 140, 0, 55 },
		RightElbow = { 25, 0, 0 }, LeftShoulder = { 110, 0, -75 }, LeftElbow = { 35, 0, 0 }, LeftHip = { 75, 0, -18 },
		LeftKnee = { -45, 0, 0 }, RightHip = { 35, 0, 22 }, RightKnee = { -85, 0, 0 }, LeftAnkle = { -20, 0, 0 }, RightAnkle = { -10, 0, 0 } },
	-- fallbacks for the emote frames used by perks (the Taunt clip's BRING IT / COME ON keys)
	BRING = merge(WIDE, { Waist = { 20, 0, 0 }, Neck = { 26, 0, 0 }, RightShoulder = { 30, 0, 92 }, RightElbow = { 28, 0, 0 },
		RightWrist = { -20, 0, 0 }, LeftShoulder = { 30, 0, -92 }, LeftElbow = { 28, 0, 0 }, LeftWrist = { -20, 0, 0 } }),
	COMEON = merge(WIDE, { Waist = { 6, -24, 0 }, Neck = { 16, 20, 0 }, RightShoulder = { -62, 32, 26 }, RightElbow = { 88, 0, 0 },
		RightWrist = { 10, -6, 0 }, LeftShoulder = { 84, 0, -6 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -35, 0, 0 } }),
}
-- left <-> right
local function mirror(pose)
	local out = {}
	for name, v in pairs(pose) do
		local n2 = name
		if string.sub(name, 1, 4) == "Left" then
			n2 = "Right" .. string.sub(name, 5)
		elseif string.sub(name, 1, 5) == "Right" then
			n2 = "Left" .. string.sub(name, 6)
		end
		local m = { v[1] or 0, -(v[2] or 0), -(v[3] or 0) }
		if typeof(v.pos) == "Vector3" then
			m.pos = V3(-v.pos.X, v.pos.Y, v.pos.Z)
		end
		out[n2] = m
	end
	return out
end

-- one frame of an emote clip: every joint at its latest key at or before t (the clips' follow-through LAG moved the
-- elbow / wrist / neck keys a beat later, so those are read that much later)
local LAG = { LeftElbow = 0.035, RightElbow = 0.035, LeftWrist = 0.07, RightWrist = 0.07, Neck = 0.04 }
local function sampleClip(clip, t)
	if type(clip) ~= "table" or type(clip.keys) ~= "table" then
		return nil
	end
	local pose, at = {}, {}
	for _, k in ipairs(clip.keys) do
		if type(k) == "table" and type(k.pose) == "table" and type(k.t) == "number" then
			for name, v in pairs(k.pose) do
				if type(v) == "table" and k.t <= t + (LAG[name] or 0) + 0.002 and (at[name] == nil or k.t >= at[name]) then
					at[name] = k.t
					pose[name] = v
				end
			end
		end
	end
	return next(pose) and pose or nil
end
local function clipPose(id, t, fallback)
	local clips = EmoteClips()
	local clip = clips and clips[id]
	if type(clip) == "table" and type(clip.keys) == "table" then
		if not t then -- no chosen frame: the key nearest 35% of the clip
			local best, want = nil, (tonumber(clip.length) or 2) * 0.35
			for _, k in ipairs(clip.keys) do
				if type(k) == "table" and type(k.t) == "number" and (best == nil or math.abs(k.t - want) < math.abs(best - want)) then
					best = k.t
				end
			end
			t = best or 0
		end
		local p = sampleClip(clip, t)
		if p then
			return p
		end
	end
	return fallback
end

---------------------------------------------------------------------------------------------------------------------
-- looks: outfit colours per fighter (palette-led) + hair, plus a few accessories that make them read at 44 px
local LOOKS = {
	default = { top = C(60, 100, 225), pants = C(42, 42, 62), belt = C(255, 205, 60), shoes = C(245, 245, 250), hair = C(34, 30, 44), spike = 1 },
	Limitless = { top = C(52, 46, 88), pants = C(40, 36, 66), belt = C(40, 36, 66), shoes = C(116, 74, 255), hair = C(246, 246, 255), spike = 1.05,
		band = { color = C(24, 22, 32), y = 0.04, h = 0.36 } },
	Vulpine = { top = C(255, 145, 40), pants = C(240, 125, 30), belt = C(40, 64, 150), shoes = C(40, 64, 150), hair = C(255, 216, 60), spike = 1.2,
		band = { color = C(40, 64, 150), y = 0.38, h = 0.24, plate = C(205, 210, 222) } },
	Godspeed = { top = C(95, 175, 245), pants = C(52, 62, 104), belt = C(52, 62, 104), shoes = C(235, 240, 255), hair = C(236, 242, 255), spike = 1.15 },
	OneForAll = { top = C(34, 160, 96), pants = C(34, 160, 96), belt = C(70, 70, 80), shoes = C(225, 45, 45), hair = C(30, 84, 58), spike = 0.95,
		gloves = C(245, 245, 250) },
	Tempest = { top = C(236, 232, 248), pants = C(62, 50, 112), belt = C(130, 70, 255), shoes = C(42, 40, 58), hair = C(30, 30, 52), spike = 1.0 },
	Carver = { top = C(250, 242, 236), pants = C(74, 26, 36), belt = C(210, 22, 42), shoes = C(42, 30, 30), hair = C(255, 158, 175), spike = 0.85 },
	Shifter = { top = C(44, 140, 92), pants = C(236, 230, 214), belt = C(112, 80, 52), shoes = C(92, 62, 42), hair = C(96, 66, 46), spike = 0.55 },
	Zangetsu = { top = C(40, 38, 50), pants = C(40, 38, 50), belt = C(236, 236, 236), shoes = C(236, 236, 236), hair = C(255, 130, 30), spike = 1.05,
		sword = true },
	Ascendant = { top = C(255, 150, 30), pants = C(255, 150, 30), belt = C(40, 82, 205), shoes = C(40, 82, 205), hair = C(26, 26, 36), spike = 1.5,
		bare = true },
	Gomu = { top = C(222, 34, 42), pants = C(70, 122, 212), belt = C(255, 204, 60), shoes = C(205, 165, 105), hair = C(26, 26, 36), spike = 0.45,
		bareUpper = true, hat = true },
	Stormdraw = { top = C(255, 196, 50), pants = C(34, 34, 48), belt = C(236, 232, 220), shoes = C(34, 34, 48), hair = C(255, 214, 70), spike = 1.0,
		sword = true },
}
-- each fighter's signature pose (a function: emote clips load lazily) + camera + optional orb / stretch
local FIGHTER = {
	default = { pose = function() return POSES.STANCE end, cam = { yaw = 24 } },
	Limitless = { pose = function() return clipPose("Pose", 0.36, POSES.STANCE) end, cam = { yaw = 22, pitch = -6 } },
	Vulpine = { pose = function() return POSES.PALM end, cam = { yaw = 34 },
		orb = { d = 1.3, at = "RightHand", color = C(165, 220, 255), glow = C(70, 150, 255) } },
	Godspeed = { pose = function() return POSES.DASH end, cam = { yaw = 62, roll = -5 } },
	OneForAll = { pose = function() return POSES.PUNCH end, cam = { yaw = 68, roll = -4 } },
	Tempest = { pose = function() return POSES.CHIDORI end, cam = { yaw = -30 },
		orb = { d = 1.05, at = "LeftHand", color = C(215, 205, 255), glow = C(130, 70, 255) } },
	Carver = { pose = function() return clipPose("PowerUp", 0.46, POSES.AURA) end, cam = { yaw = 14, pitch = -8 } },
	Shifter = { pose = function() return clipPose("PowerUp", 1.62, POSES.ROAR) end, cam = { yaw = 10, pitch = -10 } },
	Zangetsu = { pose = function() return POSES.STANCE end, cam = { yaw = -32 } },
	Ascendant = { pose = function() return POSES.KAME end, cam = { yaw = 42 },
		orb = { d = 1.45, at = "between", color = C(200, 240, 255), glow = C(60, 150, 255) } },
	Gomu = { pose = function() return POSES.PUNCH end, cam = { yaw = 52 }, stretch = { RightLowerArm = 2.4 } },
	Stormdraw = { pose = function() return POSES.STANCE end, cam = { yaw = -30 } },
}

---------------------------------------------------------------------------------------------------------------------
-- parts
local BASE, BASE_WEDGE, TEMPLATE
local function basePart(wedge)
	if not BASE then
		for i = 1, 2 do
			local p = Instance.new(i == 1 and "Part" or "WedgePart")
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Size = V3(1, 1, 1)
			if i == 1 then
				BASE = p
			else
				BASE_WEDGE = p
			end
		end
	end
	return wedge and BASE_WEDGE or BASE
end
local function part(parent, size, cf, color, shape)
	local p = basePart(shape == "Wedge"):Clone()
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = parent
	return p
end

local HS = SIZES.Head
local FRONT = -HS.Z / 2
local FACE = { -- head space
	{ "EyeL", CFn(-0.27, 0, FRONT - 0.02), V3(0.2, 0.32, 0.05) },
	{ "EyeR", CFn(0.27, 0, FRONT - 0.02), V3(0.2, 0.32, 0.05) },
	{ "BrowL", CFn(-0.28, 0.27, FRONT - 0.03) * ANG(0, 0, rad(-20)), V3(0.4, 0.1, 0.05) },
	{ "BrowR", CFn(0.28, 0.27, FRONT - 0.03) * ANG(0, 0, rad(20)), V3(0.4, 0.1, 0.05) },
}
local HAIR = {
	{ "HairCap", CFn(0, HS.Y / 2 + 0.02, 0.06), V3(HS.X + 0.16, 0.5, HS.Z + 0.2) },
	{ "Fringe", CFn(0, HS.Y / 2 - 0.15, FRONT - 0.05) * ANG(rad(-12), 0, 0), V3(HS.X + 0.12, 0.32, 0.22) },
}
local SPIKES = { -- head-top space at spike = 1: position, lean X, lean Z, size (each a block twisted 45 = a pointy diamond)
	{ V3(0, 0.55, 0.05), -8, 0, V3(0.62, 1.0, 0.62) },
	{ V3(-0.52, 0.4, 0), 0, 40, V3(0.56, 0.92, 0.56) },
	{ V3(0.52, 0.4, 0), 0, -40, V3(0.56, 0.92, 0.56) },
	{ V3(-0.3, 0.32, 0.48), 42, 22, V3(0.56, 0.86, 0.56) },
	{ V3(0.3, 0.32, 0.48), 42, -22, V3(0.56, 0.86, 0.56) },
}
local function getTemplate()
	if TEMPLATE then
		return TEMPLATE
	end
	local m = Instance.new("Model")
	m.Name = "Figure"
	for _, name in ipairs(BODY) do
		part(m, SIZES[name], CFrame.identity, WHITE).Name = name
	end
	for _, f in ipairs(FACE) do
		part(m, f[3], CFrame.identity, INK).Name = f[1]
	end
	for _, h in ipairs(HAIR) do
		part(m, h[3], CFrame.identity, INK).Name = h[1]
	end
	for i, s in ipairs(SPIKES) do
		part(m, s[4], CFrame.identity, INK).Name = "Spike" .. i
	end
	TEMPLATE = m
	return m
end

local function colorFor(look, name)
	local skin = look.skin or SKIN
	if name == "Head" then
		return skin
	elseif name == "RightHand" or name == "LeftHand" then
		return look.gloves or skin
	elseif name == "UpperTorso" then
		return look.top
	elseif name == "LowerTorso" then
		return look.belt or look.top
	elseif name == "RightUpperArm" or name == "LeftUpperArm" then
		return look.bareUpper and skin or (look.sleeve or look.top)
	elseif name == "RightLowerArm" or name == "LeftLowerArm" then
		return (look.bare or look.bareUpper) and skin or (look.sleeve or look.top)
	elseif name == "RightFoot" or name == "LeftFoot" then
		return look.shoes or look.pants
	end
	return look.pants
end

-- a posed figure. o = { at = CFrame, stretch, ghost = transparency (no ink / halo / framing), ghostColor, koEyes,
-- eyeColor, crown, orb = { d, at = "RightHand" | "LeftHand" | "between", color } }
local function addFigure(S, look, pose, o)
	o = o or {}
	look = look or LOOKS.default
	local at = o.at or CFrame.identity
	local cfs = solve(pose, o.stretch)
	local m = getTemplate():Clone()
	local fig = { parts = {}, list = {}, cfs = cfs, at = at, model = m }
	local ghost = o.ghost
	local function reg(p, inkIt)
		table.insert(fig.list, p)
		if ghost then
			p.Transparency = math.max(p.Transparency, ghost)
			p.Color = o.ghostColor or p.Color
		else
			table.insert(S.frame, p)
			if inkIt ~= false then
				table.insert(S.ink, p)
			end
		end
	end
	for _, name in ipairs(BODY) do
		local p = m:FindFirstChild(name)
		local k = o.stretch and o.stretch[name]
		if k then
			p.Size = V3(p.Size.X, p.Size.Y * k, p.Size.Z)
		end
		p.CFrame = at * cfs[name]
		p.Color = colorFor(look, name)
		fig.parts[name] = p
		reg(p)
	end
	local head = at * cfs.Head
	for _, f in ipairs(FACE) do
		local p = m:FindFirstChild(f[1])
		p.CFrame = head * f[2]
		p.Color = o.eyeColor or INK
		if ghost then
			p.Transparency = 1
		end
	end
	if o.koEyes then -- X X
		for _, s in ipairs({ { "EyeL", "BrowL", -0.27 }, { "EyeR", "BrowR", 0.27 } }) do
			local e, b = m:FindFirstChild(s[1]), m:FindFirstChild(s[2])
			local base = head * CFn(s[3], 0.05, FRONT - 0.02)
			e.Size, e.CFrame = V3(0.09, 0.38, 0.05), base * ANG(0, 0, rad(45))
			b.Size, b.CFrame = V3(0.09, 0.38, 0.05), base * ANG(0, 0, rad(-45))
		end
	end
	local hair = look.hair or INK
	for _, h in ipairs(HAIR) do
		local p = m:FindFirstChild(h[1])
		p.CFrame = head * h[2]
		p.Color = hair
		reg(p)
	end
	local k = look.spike or 1
	if o.crown then
		k = math.min(k, 0.45)
	end
	for i, s in ipairs(SPIKES) do
		local p = m:FindFirstChild("Spike" .. i)
		if k <= 0.05 then
			p:Destroy()
		else
			p.Size = s[4] * k
			p.CFrame = head * CFn(s[1].X, HS.Y / 2 + s[1].Y * k - 0.1, s[1].Z) * ANG(rad(s[2]), 0, rad(s[3])) * ANG(0, rad(45), 0)
			p.Color = hair
			reg(p)
		end
	end
	-- accessories
	if look.band then
		local b = look.band
		reg(part(m, V3(HS.X + 0.1, b.h or 0.26, HS.Z + 0.1), head * CFn(0, b.y or 0.3, 0), b.color or INK))
		if b.plate then
			reg(part(m, V3(0.6, (b.h or 0.26) * 0.75, 0.06), head * CFn(0, b.y or 0.3, FRONT - 0.09), b.plate), false)
		end
	end
	if look.hat then
		local straw = C(255, 204, 60)
		local top = head * CFn(0, HS.Y / 2 + 0.06, 0.04) * ANG(rad(-10), 0, 0)
		reg(part(m, V3(0.12, 2.5, 2.5), top * ANG(0, 0, rad(90)), straw, "Cylinder"))
		reg(part(m, V3(0.62, 1.42, 1.42), top * CFn(0, 0.36, 0) * ANG(0, 0, rad(90)), straw, "Cylinder"))
		reg(part(m, V3(0.2, 1.46, 1.46), top * CFn(0, 0.16, 0) * ANG(0, 0, rad(90)), C(215, 30, 40), "Cylinder"), false)
	end
	if look.sword then
		local blade = at * cfs.UpperTorso * CFn(0.1, 0.2, 0.62) * ANG(0, 0, rad(-38))
		reg(part(m, V3(0.95, 4.8, 0.14), blade, C(32, 30, 38)))
		reg(part(m, V3(0.18, 4.8, 0.16), blade * CFn(0.42, 0, 0), C(210, 215, 225)), false)
		reg(part(m, V3(0.26, 1.1, 0.26), blade * CFn(0, 2.95, 0), C(235, 235, 240)))
	end
	if o.crown then
		local gold = C(255, 200, 40)
		local ctop = head * CFn(0, HS.Y / 2 + 0.16, 0) * ANG(0, 0, rad(-8))
		reg(part(m, V3(HS.X + 0.24, 0.4, HS.Z + 0.24), ctop, gold))
		for _, x in ipairs({ -0.48, 0, 0.48 }) do
			for _, z in ipairs({ FRONT - 0.05, -FRONT + 0.05 }) do
				reg(part(m, V3(0.36, 0.36, 0.14), ctop * CFn(x, x == 0 and 0.38 or 0.3, z) * ANG(0, 0, rad(45)), gold))
			end
		end
		reg(part(m, V3(0.2, 0.2, 0.06), ctop * CFn(0, 0, FRONT - 0.15) * ANG(0, 0, rad(45)), C(235, 40, 70)), false)
	end
	if o.orb then
		local ob = o.orb
		local d = ob.d or 1.2
		local pos
		if ob.at == "between" then
			local r, l = at * cfs.RightHand, at * cfs.LeftHand
			local fwd = -((at * cfs.RightLowerArm).UpVector + (at * cfs.LeftLowerArm).UpVector)
			fwd = fwd.Magnitude > 1e-3 and fwd.Unit or V3(0, 0, -1)
			pos = (r.Position + l.Position) / 2 + fwd * (d / 2 + 0.15)
		else
			local handName = ob.at or "RightHand"
			local armName = string.gsub(handName, "Hand", "LowerArm")
			local hand, arm = at * cfs[handName], at * cfs[armName]
			pos = hand.Position - arm.UpVector * (0.2 + d / 2)
		end
		local orb = part(m, V3(d, d, d), CFn(pos), ob.color or WHITE, "Ball")
		reg(orb)
		fig.orb = orb
	end
	m.Parent = S.world
	return fig
end

---------------------------------------------------------------------------------------------------------------------
-- camera: frames every non-ghost figure part; then the screen <-> world helpers for things laid out in screen space
local function frameCamera(S, cam)
	cam = cam or {}
	local yaw, pitch = rad(cam.yaw or 22), rad(cam.pitch or -6)
	local fov = cam.fov or 26
	local dir = V3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	local R = CFrame.lookAt(Vector3.zero, -dir) * ANG(0, 0, rad(cam.roll or 0))
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, p in ipairs(S.frame) do
		local cf, h = p.CFrame, p.Size / 2
		for ix = -1, 1, 2 do
			for iy = -1, 1, 2 do
				for iz = -1, 1, 2 do
					local c = R:PointToObjectSpace(cf:PointToWorldSpace(V3(h.X * ix, h.Y * iy, h.Z * iz)))
					x0, x1 = math.min(x0, c.X), math.max(x1, c.X)
					y0, y1 = math.min(y0, c.Y), math.max(y1, c.Y)
					z0, z1 = math.min(z0, c.Z), math.max(z1, c.Z)
				end
			end
		end
	end
	if x0 == math.huge then
		x0, x1, y0, y1, z0, z1 = -2, 2, -3, 3, -1, 1
	end
	local tanH = math.tan(rad(fov / 2))
	local fill = cam.fill or 0.78
	local hx, hy = (x1 - x0) / 2, (y1 - y0) / 2
	local asp = S.aspect or 1 -- viewport width / height
	local D = math.max(hx / asp, hy) / (tanH * fill) + (z1 - z0) / 2
	local unit = 2 * tanH * D
	local su, sv = cam.shiftU or 0, cam.shiftV or 0
	local camCF = CFn(R:PointToWorldSpace(V3((x0 + x1) / 2 - su * unit * asp, (y0 + y1) / 2 + sv * unit, (z0 + z1) / 2 + D))) * R.Rotation
	S.cam, S.D, S.tanH = camCF, D, tanH
	S.unit, S.zFar = unit, D + (z1 - z0) / 2 -- studs per frame height at the centre plane; depth of the figure's back
	S.camera.FieldOfView = fov
	S.camera.CFrame = camCF
	S.vp.LightDirection = R:VectorToWorldSpace(V3(0.55, -0.7, -0.6)).Unit
	S.pxPerStud = S.px / unit
	S.bb = { u0 = 0.5 + su - hx / (unit * asp), u1 = 0.5 + su + hx / (unit * asp), v0 = 0.5 + sv - hy / unit, v1 = 0.5 + sv + hy / unit }
	S.cu, S.cv = 0.5 + su, 0.5 + sv
end
local function camPoint(S, u, v, depth)
	return S.cam:PointToWorldSpace(V3((u - 0.5) * 2 * S.tanH * depth * (S.aspect or 1), (0.5 - v) * 2 * S.tanH * depth, -depth))
end
-- a camera-facing frame at screen (u, v); angle = degrees clockwise from screen-up
local function camFrame(S, u, v, depth, angle)
	return CFn(camPoint(S, u, v, depth)) * S.cam.Rotation * ANG(0, 0, rad(-(angle or 0)))
end
local function unitAt(S, depth)
	return 2 * S.tanH * depth
end

-- INK = a black copy of each part grown by t and pushed INK_PUSH studs away from the camera (scaled by the push so it
-- covers the same screen area). HALO bands are built in DEPTH SLABS behind the ink (see the header); both are made in
-- finish() (resolve), once every part of the scene exists.
local INK_PUSH, INK_TMAX = 0.62, 0.26
local function inkWidth(S)
	return clamp((1.3 + S.px / 90) / math.max(S.px / (S.unit or 8), 1), 0.08, INK_TMAX)
end
local function halfDepth(cf, half, look) -- half-extent of an oriented box along `look`
	return math.abs(look:Dot(cf.RightVector)) * half.X + math.abs(look:Dot(cf.UpVector)) * half.Y + math.abs(look:Dot(cf.LookVector)) * half.Z
end
-- a flat-coloured copy of `p` (an avatar's MeshPart / SpecialMesh accessory too): textures, decals, surface
-- appearances and layered-clothing wraps are dropped, and a FileMesh's Scale / Offset grow with the copy's Size (a
-- SpecialMesh ignores its part's Size). Returns the copy and its file mesh (nil for a plain part / MeshPart).
local function isFileMesh(m)
	return m.ClassName == "FileMesh" or (m:IsA("SpecialMesh") and m.MeshType == Enum.MeshType.FileMesh)
end
local function fitMesh(h, mesh, base, size)
	if mesh then
		local k = V3(size.X / base.X, size.Y / base.Y, size.Z / base.Z)
		mesh.Scale = h:GetAttribute("CA_MS") * k
		mesh.Offset = h:GetAttribute("CA_MO") * k
	end
end
local function hullCopy(p, color, size, cf, parent)
	local h = p:Clone()
	local mesh
	for _, ch in ipairs(h:GetChildren()) do
		if ch:IsA("DataModelMesh") then
			if ch:IsA("FileMesh") then
				ch.TextureId = ""
				ch.VertexColor = Vector3.one
			end
			if isFileMesh(ch) then
				mesh = ch
				h:SetAttribute("CA_MS", ch.Scale)
				h:SetAttribute("CA_MO", ch.Offset)
			end
		else
			ch:Destroy()
		end
	end
	if h:IsA("MeshPart") then
		pcall(function()
			h.TextureID = ""
		end)
	end
	h.Color = color
	h.Transparency = 0
	h.Material = Enum.Material.SmoothPlastic
	h.Size = size
	fitMesh(h, mesh, p.Size, size)
	h.CFrame = cf
	h.Parent = parent
	return h, mesh
end
-- the black ink copies; returns the depth (along the camera axis) of their back, measured at the widest ink a later
-- resize can give (INK_TMAX), so a halo slab never covers the outline
local function makeInk(S)
	local camPos, look = S.cam.Position, S.cam.LookVector
	local t = inkWidth(S)
	local tm = V3(INK_TMAX, INK_TMAX, INK_TMAX)
	local back = 0
	S.inkHulls = {}
	for _, p in ipairs(S.ink) do
		if p.Parent then
			local pos = p.Position
			local toward = pos - camPos
			local s = (toward.Magnitude + INK_PUSH) / toward.Magnitude
			local h, mesh = hullCopy(p, INK, (p.Size + V3(2 * t, 2 * t, 2 * t)) * s, CFn(pos + toward.Unit * INK_PUSH) * p.CFrame.Rotation, S.world)
			table.insert(S.inkHulls, { h, p, s, mesh })
			back = math.max(back, (h.Position - camPos):Dot(look) + halfDepth(h.CFrame, (p.Size / 2 + tm) * s, look))
		end
	end
	return back
end
-- one halo band: copies of `list` grown by `grow` with their FRONTS on the plane `front`; returns the band's back
local function makeBand(S, list, color, grow, front)
	local camPos, look = S.cam.Position, S.cam.LookVector
	local g = V3(grow, grow, grow)
	local back = front
	for _, p in ipairs(list) do
		if p.Parent then
			local pos = p.Position
			local dp = (pos - camPos):Dot(look)
			if dp > 0.5 then
				local half = p.Size / 2 + g
				local hd = halfDepth(p.CFrame, half, look)
				-- the copy is scaled by k = dc / dp about the camera, so its front is dc * (1 - hd / dp) = front
				local denom = 1 - hd / dp
				local dc = denom > 0.05 and front / denom or front + 2 * hd
				local k = dc / dp
				hullCopy(p, color, half * 2 * k, CFn(camPos + (pos - camPos) * k) * p.CFrame.Rotation, S.world)
				back = math.max(back, dc + hd * k)
			end
		end
	end
	return back
end
-- a band of colour hugging the figure: which = "inner" (in front) | "outer". Recorded now, built in finish().
local function haloPass(S, color, grow, which, list)
	table.insert(S.halos, { color = color, grow = grow, which = which or "outer", list = list or S.frame })
end
local function inkPass(S)
	S.wantInk = true
end

-- a triangle facing the camera: base centre at cf, apex at cf * (0, h, 0), base half-width w
local function tooth(S, cf, w, h, color)
	part(S.world, V3(0.05, h, w), cf * CFn(-w / 2, h / 2, 0) * ANG(0, rad(90), 0), color, "Wedge")
	part(S.world, V3(0.05, h, w), cf * CFn(w / 2, h / 2, 0) * ANG(0, rad(-90), 0), color, "Wedge")
end
-- flame tongues behind the figure (two layers), fanned round its screen box and leaning upward. Recorded now, drawn
-- in finish() in the slab behind the halo bands (`base` = that slab's front depth).
local FLAME_K = { 0.8, 1.0, 0.62, 0.92, 0.7, 1.0, 0.66, 0.95, 0.78, 0.7, 1.0, 0.85, 0.6 }
local function flames(S, outer, inner, n, scale)
	table.insert(S.flameReqs, { outer = outer, inner = inner, n = n, scale = scale })
end
local function drawFlames(S, r, base)
	local bb = S.bb
	local cu, cv = (bb.u0 + bb.u1) / 2, (bb.v0 + bb.v1) / 2
	local ru, rv = (bb.u1 - bb.u0) / 2, (bb.v1 - bb.v0) / 2
	for ly = 1, 2 do
		local depth = base + (ly == 1 and 0.9 or 0.5)
		local unit = unitAt(S, depth)
		local cnt = ly == 1 and r.n or math.max(3, r.n - 2)
		for i = 1, cnt do
			local f = (i - 1) / math.max(cnt - 1, 1)
			local th = rad(-118 + 236 * f)
			local k = FLAME_K[(i + ly * 4) % #FLAME_K + 1]
			local bu = cu + sin(th) * ru * 0.78
			local bv = cv - cos(th) * rv * 0.74
			local h = (ly == 1 and 0.3 or 0.2) * k * r.scale
			local w = (ly == 1 and 0.07 or 0.05) * r.scale
			tooth(S, camFrame(S, bu, bv, depth, math.deg(th) * 0.55), w * unit, h * unit, ly == 1 and r.outer or r.inner)
		end
	end
end
-- a jagged starburst (disc + alternating long / short teeth), in screen units
local function burst(S, u, v, rIn, rOut, n, color, depth, rot)
	local unit = unitAt(S, depth)
	part(S.world, V3(0.05, 2 * rIn * unit, 2 * rIn * unit), CFn(camPoint(S, u, v, depth)) * S.cam.Rotation * ANG(0, rad(90), 0), color, "Cylinder")
	for i = 1, n do
		local ang = (rot or 0) + 360 * (i - 1) / n
		local th = rad(ang)
		local len = (i % 2 == 0) and rOut or (rIn + (rOut - rIn) * 0.55)
		local b = rIn * 0.8
		tooth(S, camFrame(S, u + sin(th) * b, v - cos(th) * b, depth, ang), rIn * 0.42 * unit, (len - b) * unit, color)
	end
end
-- a zig-zag bolt through screen points (inked)
local function bolt(S, pts, color, width, depth)
	local unit = unitAt(S, depth)
	local up = -S.cam.LookVector
	for i = 1, #pts - 1 do
		local a = camPoint(S, pts[i][1], pts[i][2], depth)
		local b = camPoint(S, pts[i + 1][1], pts[i + 1][2], depth)
		local len = (b - a).Magnitude
		table.insert(S.ink, part(S.world, V3(width * unit, 0.05, len + width * unit * 0.6), CFrame.lookAt((a + b) / 2, b, up), color))
	end
end
-- a camera-facing ribbon along a quadratic bezier (world space); colorAt(t) with t = 0 at p0, 1 at p2
local function bez(a, b, c, t)
	local u = 1 - t
	return a * (u * u) + b * (2 * u * t) + c * (t * t)
end
local function ribbon(S, p0, p1, p2, w0, w1, colorAt, n, push, inkIt)
	local camPos = S.cam.Position
	for i = 1, n do
		local t0, t1 = (i - 1) / n, i / n
		local a, b = bez(p0, p1, p2, t0), bez(p0, p1, p2, t1)
		local mid, d = (a + b) / 2, b - a
		local len = d.Magnitude
		if len > 1e-3 then
			local view = (mid - camPos).Unit
			local side = d.Unit:Cross(view)
			if side.Magnitude > 1e-3 then
				side = side.Unit
				local tm = (t0 + t1) / 2
				local p = part(S.world, V3(w0 + (w1 - w0) * tm, 0.05, len * 1.18), CFrame.fromMatrix(mid + view * (push or 0), side, side:Cross(d.Unit)), colorAt(tm))
				if inkIt then
					table.insert(S.ink, p)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- UI
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function frame(parent, props)
	props.BorderSizePixel = 0
	return new("Frame", props, parent)
end
local function round(o, s, px)
	new("UICorner", { CornerRadius = UDim.new(s or 0, px or 0) }, o)
end

local function begin(container, top, bottom, wide)
	local z = container.ZIndex
	local a = container.AbsoluteSize
	local px = math.min(a.X, a.Y)
	if px < 4 then
		local ox, oy = container.Size.X.Offset, container.Size.Y.Offset
		px = (ox > 0 and oy > 0) and math.min(ox, oy) or 0
	end
	local known = px >= 4
	if not known then
		px = 64
	end
	local S = { z = z, px = px, known = known, container = container, ink = {}, frame = {}, strokes = {}, halos = {}, flameReqs = {}, inkFrames = {} }
	S.stroke = clamp(px / 36, 1, 4)
	S.inkPx = math.max(1, math.floor(px / 34 + 0.5))
	if wide then
		local w, h = a.X, a.Y
		if w < 4 or h < 4 then
			w, h = container.Size.X.Offset, container.Size.Y.Offset
		end
		S.wide = true
		S.aspect = (w >= 4 and h >= 4) and clamp(w / h, 1, 5) or 2.8 -- the shop's aura banner is about 2.8:1
	end
	S.root = frame(nil, { Name = "CardArt_Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ClipsDescendants = true, ZIndex = z + 1 })
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }, S.root)
	-- the panel copies the container's rounding (default: a comic panel's slight one) and gets an ink border. A ROUND
	-- container (an orb) would let the corners' rays / dots / stickers show past its circle (ClipsDescendants clips a
	-- rectangle), so there the art square is inset, the rays stop at the rim and the corner dots are left out.
	local uc = container:FindFirstChildOfClass("UICorner")
	local radius = uc and uc.CornerRadius or UDim.new(0.14, 0)
	new("UICorner", { CornerRadius = radius }, S.root)
	S.round = not wide and (radius.Scale >= 0.3 or (known and radius.Offset >= 0.3 * px))
	S.panelStroke = new("UIStroke", { Color = INK, Thickness = math.max(1, S.inkPx * 0.75), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, S.root)
	S.art = frame(S.root, { Name = "Art", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(S.round and 0.8 or 1, S.round and 0.8 or 1), BackgroundTransparency = 1, ZIndex = z + 3 }) -- over a round panel's rays
	if not wide then
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, S.art)
	end
	S.vp = new("ViewportFrame", { Name = "View", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z + 6,
		Ambient = C(220, 220, 220), LightColor = C(70, 70, 70) })
	S.camera = new("Camera", { FieldOfView = 26 }, S.vp)
	S.vp.CurrentCamera = S.camera
	S.world = new("Model", { Name = "Scene" })
	return S
end
-- the 3D work that has to wait for the whole scene: ink, then the halo slabs, then the flames behind them
local function resolve(S)
	if not S.cam then
		return
	end
	local front = S.zFar or S.D
	if S.wantInk then
		front = math.max(front, makeInk(S))
	end
	front += 0.12
	for _, which in ipairs({ "inner", "outer" }) do
		local back = front
		for _, r in ipairs(S.halos) do
			if r.which == which then
				back = math.max(back, makeBand(S, r.list, r.color, r.grow, front))
			end
		end
		front = back + 0.12
	end
	for _, r in ipairs(S.flameReqs) do
		drawFlames(S, r, front)
	end
end
-- re-fit every outline width to a container size of `px`
local function applySize(S, px)
	S.px = px
	S.stroke = clamp(px / 36, 1, 4)
	S.inkPx = math.max(1, math.floor(px / 34 + 0.5))
	for _, s in ipairs(S.strokes) do
		s[1].Thickness = S.stroke * s[2]
	end
	local o = S.inkPx
	for _, f in ipairs(S.inkFrames) do
		f[1].Size = UDim2.new(f[2], o * 2, f[3], o * 2)
	end
	if S.panelStroke then
		S.panelStroke.Thickness = math.max(1, o * 0.75)
	end
	if S.inkHulls and S.cam then
		local t = inkWidth(S)
		local g = V3(2 * t, 2 * t, 2 * t)
		for _, e in ipairs(S.inkHulls) do
			local size = (e[2].Size + g) * e[3]
			e[1].Size = size
			fitMesh(e[1], e[4], e[2].Size, size)
		end
	end
end
-- VIEWPORT CULLING (2026-11-10, measured in Play): Roblox stops rendering ViewportFrames once too many are visible at
-- once - the inventory holds ~45 cards in ONE ScrollingFrame and the later ones came out blank (Clap / Dance / Flex /
-- Power Up), even at one viewport per card. A card's viewport is therefore switched off while it lies outside the
-- visible window of its nearest ScrollingFrame (hidden tabs/panels already cost nothing). One deferred re-check per
-- ScrollingFrame on scroll / resize, plus one per card when its own position changes - no per-frame work.
local cullSets = setmetatable({}, { __mode = "k" }) -- [ScrollingFrame] = { [ViewportFrame] = true }
local function inView(sf, g)
	local a, s = sf.AbsolutePosition, sf.AbsoluteSize
	local p, z = g.AbsolutePosition, g.AbsoluteSize
	return p.X + z.X >= a.X - 8 and p.X <= a.X + s.X + 8 and p.Y + z.Y >= a.Y - 8 and p.Y <= a.Y + s.Y + 8
end
-- (measured in Play) a ViewportFrame that is switched back on - or whose panel opens - is sometimes never redrawn until
-- something inside it changes: the card stays blank. A one-frame FOV twitch on the camera forces the redraw.
local function nudge(vp)
	local cam = vp.CurrentCamera
	if not cam then
		return
	end
	local fov = cam:GetAttribute("BaseFov")
	if not fov then
		fov = cam.FieldOfView
		cam:SetAttribute("BaseFov", fov)
	end
	-- one twitch right away isn't always enough (many cards come into view in the same frames); repeat it after the
	-- scroll / panel has settled, each held ~0.1 s like the manual nudge that was verified to restore every card
	local token = (cam:GetAttribute("NudgeToken") or 0) + 1
	cam:SetAttribute("NudgeToken", token)
	for k, at in ipairs({ 0, 0.4, 1.0 }) do
		task.delay(at, function()
			if not cam.Parent or cam:GetAttribute("NudgeToken") ~= token then
				return
			end
			cam.FieldOfView = fov + 0.02 * k
			task.delay(0.1, function()
				if cam.Parent then
					cam.FieldOfView = fov
				end
			end)
		end)
	end
end
local function cullOne(sf, vp)
	if vp.Parent and sf.Parent then
		local want = inView(sf, vp.Parent)
		if want and not vp.Visible then
			vp.Visible = true
			nudge(vp)
		elseif not want then
			vp.Visible = false
		end
	end
end
-- every hideable ancestor of a card (tabs, panels, the shop shade): when one becomes visible, its cards' viewports are
-- re-culled and nudged. One connection per ancestor instance, shared by all the cards under it.
local watched = setmetatable({}, { __mode = "k" }) -- [GuiObject ancestor] = { [ViewportFrame] = sf or false }
local function watchAncestors(vp, container, sf)
	local a = container
	while a and not a:IsA("LayerCollector") do
		if a:IsA("GuiObject") then
			local set = watched[a]
			if not set then
				set = setmetatable({}, { __mode = "k" })
				watched[a] = set
				local anc = a
				anc:GetPropertyChangedSignal("Visible"):Connect(function()
					if anc.Visible then
						task.delay(0.03, function()
							for v, s in pairs(set) do
								if v.Parent then
									if s then
										cullOne(s, v)
									end
									if v.Visible then
										nudge(v)
									end
								end
							end
						end)
					end
				end)
			end
			set[vp] = sf or false
		end
		a = a.Parent
	end
	if a and a:IsA("ScreenGui") then
		local set = watched[a]
		if not set then
			set = setmetatable({}, { __mode = "k" })
			watched[a] = set
			local sg = a
			sg:GetPropertyChangedSignal("Enabled"):Connect(function()
				if sg.Enabled then
					task.delay(0.03, function()
						for v in pairs(set) do
							if v.Parent and v.Visible then
								nudge(v)
							end
						end
					end)
				end
			end)
		end
		set[vp] = sf or false
	end
end
local function cullSet(sf)
	local set = cullSets[sf]
	if set then
		set.pending = false
		for vp in pairs(set.vps) do
			if vp.Parent then
				cullOne(sf, vp)
			else
				set.vps[vp] = nil
			end
		end
	end
end
local function cullRegister(vp, container)
	local function attach()
		local sf = container:FindFirstAncestorWhichIsA("ScrollingFrame")
		if not sf then
			return false
		end
		local set = cullSets[sf]
		if not set then
			set = { vps = setmetatable({}, { __mode = "k" }), pending = false }
			cullSets[sf] = set
			local function schedule()
				if not set.pending then
					set.pending = true
					task.defer(cullSet, sf)
				end
			end
			sf:GetPropertyChangedSignal("CanvasPosition"):Connect(schedule)
			sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(schedule)
			sf:GetPropertyChangedSignal("AbsolutePosition"):Connect(schedule)
		end
		set.vps[vp] = true
		watchAncestors(vp, container, sf)
		local c = container:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			task.defer(cullOne, sf, vp)
		end)
		vp.Destroying:Connect(function()
			c:Disconnect()
		end)
		task.defer(cullOne, sf, vp)
		return true
	end
	if not attach() then
		-- built before the card was placed (or it is not in a list): attach when it lands in one, and watch its panels
		local conn
		conn = container.AncestryChanged:Connect(function()
			if not vp.Parent then
				conn:Disconnect()
			elseif attach() then
				conn:Disconnect()
			elseif container:FindFirstAncestorWhichIsA("LayerCollector") then
				watchAncestors(vp, container, nil)
			end
		end)
		if container:FindFirstAncestorWhichIsA("LayerCollector") then
			watchAncestors(vp, container, nil)
		end
		task.defer(nudge, vp)
	end
end

local function finish(S, opts)
	resolve(S)
	S.world.Parent = S.vp
	S.vp.Parent = S.art
	pcall(cullRegister, S.vp, S.container)
	S.root.Parent = S.container
	-- outline widths follow the container's real size (a card built while hidden has AbsoluteSize 0): re-fit the first
	-- time it gets one, and on a >15% resize. One property signal per card - no per-frame work.
	local applied = S.px
	local function check()
		local a = S.container.AbsoluteSize
		local px = math.min(a.X, a.Y)
		if px >= 4 and (not S.known or math.abs(px - applied) > applied * 0.15) then
			S.known, applied = true, px
			applySize(S, px)
		end
	end
	local conn = S.container:GetPropertyChangedSignal("AbsoluteSize"):Connect(check)
	S.root.Destroying:Connect(function()
		conn:Disconnect()
	end)
	check()
	if opts and opts.live and S.spin then
		TweenService:Create(S.spin, TweenInfo.new(60, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	end
	return true
end

local RAY_FADE = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(0.46, 0.85),
	NumberSequenceKeypoint.new(0.54, 0.85), NumberSequenceKeypoint.new(0.7, 0), NumberSequenceKeypoint.new(1, 0) })
local function rays(S, color, alpha, n, width, u, v)
	local holder = frame(S.round and S.root or S.art, { Name = "Rays", AnchorPoint = V2(0.5, 0.5),
		Position = UDim2.fromScale(S.round and 0.5 or u or 0.5, S.round and 0.5 or v or 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, ZIndex = S.z + 2 })
	for i = 1, n do
		local r = frame(holder, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(width, S.round and 1 or 2.6),
			Rotation = (i - 1) * 180 / n + 7, BackgroundColor3 = color, BackgroundTransparency = alpha, ZIndex = S.z + 2 })
		if S.wide then -- sized off the banner's width so every ray reaches both ends
			r.SizeConstraint = Enum.SizeConstraint.RelativeXX
			r.Size = UDim2.fromScale(width * 0.5, 1.15)
		end
		new("UIGradient", { Rotation = 90, Transparency = RAY_FADE }, r)
	end
	S.spin = holder
end
local function dots(S, color, alpha)
	if S.round then
		return
	end
	for _, corner in ipairs({ "tl", "br" }) do
		for r = 0, 3 do
			for c = 0, 3 - r do
				local d = (4 - r - c) / 4
				local s = 0.022 + 0.062 * d
				local asp = S.aspect or 1
				local u = corner == "tl" and (0.07 + c * 0.095) / asp or 1 - (0.07 + c * 0.095) / asp
				local v = corner == "tl" and 0.07 + r * 0.095 or 0.93 - r * 0.095
				round(frame(S.art, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(u, v), Size = UDim2.fromScale(s, s), BackgroundColor3 = color,
					BackgroundTransparency = alpha, SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = S.z + 3 }), 0.5)
			end
		end
	end
end
local function glow(S, color, size, u, v)
	for i = 1, 3 do
		local k = 1 - (i - 1) * 0.2
		round(frame(S.art, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(u or 0.5, v or 0.52), Size = UDim2.fromScale(size * k, size * k),
			BackgroundColor3 = color, BackgroundTransparency = 0.8 - 0.16 * (i - 1), SizeConstraint = Enum.SizeConstraint.RelativeYY, ZIndex = S.z + 3 }), 0.5)
	end
end
-- one union-outlined shape: shapes = { { u, v, w, h, rotation?, cornerScale? } } in art scale units
local function inkShape(S, shapes, fill, z)
	local o = S.inkPx
	for pass = 1, 2 do
		for _, s in ipairs(shapes) do
			local f = frame(S.art, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(s[1], s[2]),
				Size = pass == 1 and UDim2.new(s[3], o * 2, s[4], o * 2) or UDim2.fromScale(s[3], s[4]), Rotation = s[5] or 0,
				BackgroundColor3 = pass == 1 and INK or fill, ZIndex = z + pass - 1 })
			if pass == 1 then
				table.insert(S.inkFrames, { f, s[3], s[4] })
			end
			if s[6] then
				round(f, s[6])
			end
		end
	end
end
-- comic lettering (k = stroke weight; 0 = no stroke)
local function word(S, text, u, v, w, h, rot, fill, z, k)
	local t = new("TextLabel", { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(u, v), Size = UDim2.fromScale(w, h), BackgroundTransparency = 1,
		Text = text, TextScaled = true, FontFace = FONT, TextColor3 = fill or WHITE, Rotation = rot or 0, ZIndex = z or S.z + 9 }, S.art)
	k = k or 1
	if k > 0 then
		local st = new("UIStroke", { Color = INK, Thickness = S.stroke * k, LineJoinMode = Enum.LineJoinMode.Round }, t)
		table.insert(S.strokes, { st, k })
	end
	return t
end
local function bubble(S, text, u, v, w, h, tu, tv, fill, textColor)
	local tw = w * 0.22
	inkShape(S, { { u, v, w, h, 0, 0.5 }, { tu, tv, tw, tw, 45, 0.12 } }, fill or WHITE, S.z + 7)
	word(S, text, u, v, w * 0.84, h * 0.66, -5, textColor or INK, S.z + 9, 0)
end
local function starUI(S, u, v, s, fill, text, textColor)
	inkShape(S, { { u, v, s, s, 0 }, { u, v, s, s, 30 }, { u, v, s, s, 60 } }, fill, S.z + 7)
	if text then
		word(S, text, u, v, s * 0.8, s * 0.44, -10, textColor or INK, S.z + 9, 0)
	end
end
local function upArrow(S, u, v, len, color)
	local w, b = 0.1, 0.27
	local d = b / 2 * 0.7071
	inkShape(S, { { u, v + len / 2, w, len, 0, 0.2 }, { u - d, v + d, w, b, 45, 0.3 }, { u + d, v + d, w, b, -45, 0.3 } }, color, S.z + 7)
end
local SPEED = { { 0.3, 0.02, 0.46, 0.022 }, { 0.4, 0.08, 0.36, 0.03 }, { 0.5, 0.0, 0.5, 0.02 }, { 0.58, 0.1, 0.3, 0.035 }, { 0.66, 0.03, 0.42, 0.022 },
	{ 0.74, 0.12, 0.28, 0.028 }, { 0.82, 0.05, 0.36, 0.02 }, { 0.22, 0.12, 0.26, 0.018 } }
local SPEED_FADE = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0), NumberSequenceKeypoint.new(1, 0) })
local function speedLines(S, color, color2, alpha, z)
	for i, l in ipairs(SPEED) do
		local f = frame(S.art, { AnchorPoint = V2(0, 0.5), Position = UDim2.fromScale(l[2], l[1]), Size = UDim2.fromScale(l[3], l[4]),
			BackgroundColor3 = (i % 3 == 0) and color2 or color, BackgroundTransparency = alpha, ZIndex = z or S.z + 3 })
		round(f, 0.5)
		new("UIGradient", { Transparency = SPEED_FADE }, f)
	end
end
local CONFETTI = { C(255, 80, 80), C(255, 220, 60), C(80, 220, 120), C(80, 180, 255), C(200, 110, 255), WHITE }
local function confetti(S, n, seed)
	local r = Random.new(seed or 7)
	for i = 1, n do
		frame(S.art, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(r:NextNumber(0.05, 0.95), r:NextNumber(0.05, 0.95)),
			Size = UDim2.fromScale(r:NextNumber(0.03, 0.05), r:NextNumber(0.05, 0.08)), Rotation = r:NextNumber(0, 180),
			BackgroundColor3 = CONFETTI[i % #CONFETTI + 1], ZIndex = (i % 3 == 0) and S.z + 7 or S.z + 3 })
	end
end
-- the usual panel: gradient + sunburst + halftone corners + a posterized glow
local function scene(container, o)
	local S = begin(container, o.top, o.bottom)
	if o.rays then
		rays(S, o.rays[1], o.rays[2] or 0.6, o.rays.n or 8, o.rays.w or 0.11, o.rays.u, o.rays.v)
	end
	if o.dots then
		dots(S, o.dots[1], o.dots[2] or 0.6)
	end
	if o.glow then
		glow(S, o.glow[1], o.glow.size or 0.9, o.glow.u, o.glow.v)
	end
	return S
end

---------------------------------------------------------------------------------------------------------------------
-- builders: (container, item, opts, extra?) -> true | false. extra(S) adds a sticker before finish.
local B = {}

function B.aura(container, item, opts)
	local c0, c1 = col(item.c0, C(230, 220, 255)), col(item.c1, C(120, 60, 255))
	local darkAura = lum(c1) < 0.2
	local S = scene(container, {
		top = darkAura and lighten(c0, 0.25) or darken(c1, 0.6),
		bottom = darkAura and mix(c0, c1, 0.45) or darken(c1, 0.9),
		rays = { darkAura and darken(c0, 0.2) or c1, darkAura and 0.55 or 0.8, n = 8 },
		dots = { darkAura and c1 or c0, 0.72 },
		glow = { c1, size = 0.95, v = 0.5 },
	})
	local top = darkAura and C(70, 62, 96) or darken(c1, 0.6)
	addFigure(S, { top = top, pants = darken(top, 0.35), belt = darken(top, 0.5), shoes = darken(top, 0.6), hair = C(30, 26, 40), spike = 1.1 }, POSES.AURA)
	frameCamera(S, { yaw = 16, pitch = -8, roll = -3, fill = 0.62, shiftV = 0.07 })
	flames(S, darkAura and c1 or lighten(c1, 0.12), c0, 13, 1.45)
	haloPass(S, c0, 0.42, "inner")
	haloPass(S, c1, 0.9, "outer")
	inkPass(S)
	return finish(S, opts)
end

function B.fighter(container, item, opts, extra)
	local K = Kits()
	local kd = type(item.kit) == "table" and item.kit or (K and K.byId and K.byId[item.kit or item.id])
	if type(kd) ~= "table" or not kd.id then
		return false
	end
	local kit = kd.id
	local c0, c1 = col(kd.c0, WHITE), col(kd.c1, C(120, 80, 255))
	local acc = col(kd.accent, c1)
	local S = scene(container, { top = lighten(c1, 0.05), bottom = darken(c1, 0.62), rays = { c0, 0.55, n = 9 }, dots = { darken(c1, 0.5), 0.55 },
		glow = { lighten(acc, 0.3), size = 0.86 } })
	local f = FIGHTER[kit] or FIGHTER.default
	local fig = addFigure(S, LOOKS[kit] or LOOKS.default, f.pose(), { stretch = f.stretch, orb = f.orb })
	frameCamera(S, merge({ fill = 0.74 }, f.cam))
	flames(S, acc, c0, 11, 1.0)
	haloPass(S, c0, 0.34, "inner")
	haloPass(S, acc, 0.7, "outer")
	if fig.orb and f.orb.glow then
		haloPass(S, f.orb.glow, 0.34, "inner", { fig.orb })
	end
	inkPass(S)
	if extra then
		extra(S)
	end
	return finish(S, opts)
end

function B.skin(container, item, opts, extra)
	local kit = item.kit or item.id
	local P, K = Perks(), Kits()
	local sc = P and P.SKIN_COLORS and P.SKIN_COLORS[kit]
	local kd = K and K.byId and K.byId[kit]
	if type(sc) ~= "table" and type(kd) ~= "table" then
		return false
	end
	local hi = col(type(sc) == "table" and sc[1], kd and kd.c0 or WHITE)
	local lo = col(type(sc) == "table" and sc[2], kd and kd.c1 or C(80, 80, 120))
	local look = table.clone(LOOKS[kit] or LOOKS.default)
	look.top, look.sleeve, look.pants = hi, nil, lo
	look.belt, look.shoes = darken(lo, 0.3), darken(lo, 0.45)
	if look.gloves then
		look.gloves = lighten(hi, 0.5)
	end
	local S = scene(container, { top = darken(lo, 0.15), bottom = darken(lo, 0.8), rays = { hi, 0.62, n = 9 }, dots = { hi, 0.7 }, glow = { hi, size = 0.9 } })
	local f = FIGHTER[kit] or FIGHTER.default
	addFigure(S, look, f.pose(), { stretch = f.stretch, orb = f.orb and { d = f.orb.d, at = f.orb.at, color = lighten(hi, 0.4) } })
	frameCamera(S, merge({ fill = 0.74 }, f.cam))
	haloPass(S, hi, 0.42, "outer")
	inkPass(S)
	if extra then
		extra(S)
	end
	return finish(S, opts)
end

local EMOTE_T = { Taunt = 1.92, Laugh = 0.3, Victory = 0.8, Wave = 0.3, Bow = 0.98, Clap = 1.52, Dance = 0.36, Flex = 0.4, Shrug = 0.32,
	PowerUp = 1.62, Pose = 0.36, Facepalm = 0.72 }
local EMOTE_CAM = { Bow = { yaw = 64, pitch = -2 }, Laugh = { yaw = 30 }, Facepalm = { yaw = 26 }, Flex = { yaw = 14 }, Clap = { yaw = 22, pitch = -10 } }
local EMOTE_WORD = { Taunt = "BRING IT!", Laugh = "HA HA!", Victory = "WIN!", Wave = "HEY!", Bow = "THANKS!", Clap = "CLAP!", Dance = "GROOVE!",
	Flex = "FLEX!", Shrug = "MEH", PowerUp = "HAAA!", Pose = "POSE!", Facepalm = "UGH..." }
function B.emote(container, item, opts, extra)
	local id = item.id
	local clips = EmoteClips()
	local clip = clips and clips[id]
	if type(clip) ~= "table" or type(clip.keys) ~= "table" then
		return false
	end
	local pose = clipPose(id, EMOTE_T[id])
	if not pose then
		return false
	end
	local S = scene(container, { top = C(255, 236, 130), bottom = C(255, 150, 50), rays = { WHITE, 0.45, n = 9 }, dots = { C(255, 120, 40), 0.55 },
		glow = { WHITE, size = 0.8 } })
	addFigure(S, LOOKS.default, pose)
	frameCamera(S, merge({ yaw = 22, pitch = -6, fill = 0.74, shiftV = 0.05 }, EMOTE_CAM[id]))
	haloPass(S, WHITE, 0.36, "outer")
	inkPass(S)
	word(S, EMOTE_WORD[id] or string.upper(tostring(item.name or id)), 0.3, 0.13, 0.52, 0.2, -8, C(255, 70, 60))
	if extra then
		extra(S)
	end
	return finish(S, opts)
end

local KO_STYLE = {
	Explosion = { top = C(255, 150, 50), bottom = C(170, 25, 25), c0 = C(255, 240, 120), c1 = C(255, 120, 30) },
	Lightning = { top = C(60, 80, 200), bottom = C(12, 12, 44), c0 = C(255, 250, 180), c1 = C(90, 205, 255), bolts = true },
	Confetti = { top = C(255, 130, 210), bottom = C(120, 50, 210), c0 = C(255, 255, 255), c1 = C(255, 215, 70), confetti = true },
}
function B.ko(container, item, opts, extra)
	local st = KO_STYLE[item.id] or KO_STYLE.Explosion
	local S = scene(container, { top = st.top, bottom = st.bottom, rays = { st.c0, 0.55, n = 10 } })
	addFigure(S, LOOKS.default, POSES.KO, { koEyes = true })
	frameCamera(S, { yaw = 52, pitch = -4, roll = 10, fill = 0.66, shiftU = -0.04, shiftV = 0.04 })
	local e = 1.6 * S.inkPx / S.px
	local cu, cv = (S.bb.u0 + S.bb.u1) / 2, (S.bb.v0 + S.bb.v1) / 2
	burst(S, cu, cv, 0.2 + e, 0.52 + e * 1.5, 12, INK, S.D + 4.6, 8)
	burst(S, cu, cv, 0.2, 0.52, 12, st.c1, S.D + 4.3, 8)
	burst(S, cu, cv, 0.12, 0.3, 10, st.c0, S.D + 4.0, 26)
	if st.bolts then
		bolt(S, { { 0.1, 0.04 }, { 0.25, 0.24 }, { 0.17, 0.28 }, { 0.31, 0.47 } }, st.c0, 0.035, S.D + 3.4)
		bolt(S, { { 0.93, 0.1 }, { 0.8, 0.29 }, { 0.87, 0.32 }, { 0.73, 0.52 } }, st.c0, 0.03, S.D + 3.4)
	end
	inkPass(S)
	if st.confetti then
		confetti(S, 16, 11)
	end
	word(S, "K.O.!", 0.72, 0.16, 0.5, 0.24, 8, C(255, 230, 60))
	if extra then
		extra(S)
	end
	return finish(S, opts)
end

function B.trail(container, item, opts, extra)
	local TS = TrailStyle()
	local st = TS and type(TS.get) == "function" and TS.get(item.id)
	if type(st) ~= "table" then
		return false
	end
	local sw = (type(st.swatch) == "table" and #st.swatch > 0) and st.swatch or { col(st.accent, WHITE) }
	local acc = col(st.accent, sw[1])
	local black = lum(sw[1]) < 0.1
	local S = scene(container, { top = darken(acc, 0.55), bottom = C(14, 12, 26), rays = { acc, 0.72, n = 8 }, dots = { acc, 0.72 } })
	local fig = addFigure(S, LOOKS.default, POSES.PUNCH)
	frameCamera(S, { yaw = 64, pitch = -6, roll = -6, fill = 0.58, shiftU = 0.06, shiftV = 0.07 })
	local hc = S.cam:PointToObjectSpace(fig.parts.RightHand.Position)
	local hd = -hc.Z
	local uf, vf = 0.5 + hc.X / (2 * S.tanH * hd * (S.aspect or 1)), 0.5 - hc.Y / (2 * S.tanH * hd)
	local p0 = camPoint(S, uf - 0.66, vf + 0.3, hd + 1.8)
	local p1 = camPoint(S, uf - 0.36, vf - 0.46, hd + 1.0)
	local p2 = camPoint(S, uf - 0.05, vf, hd + 0.3)
	local function colorAt(t)
		return sw[clamp(math.floor((1 - t) * #sw) + 1, 1, #sw)]
	end
	local glowC = black and (sw[3] or acc) or lighten(acc, 0.15)
	ribbon(S, p0, p1, p2, 0.3, 2.3, function()
		return glowC
	end, 14, 0.35, true)
	ribbon(S, p0, p1, p2, 0.14, 1.45, colorAt, 14, 0, false)
	if not black then
		ribbon(S, p0, p1, p2, 0.05, 0.45, function()
			return WHITE
		end, 14, -0.08, false)
	end
	inkPass(S)
	if extra then
		extra(S)
	end
	return finish(S, opts)
end

-- perks ---------------------------------------------------------------------------------------------------------------
local PERK = {}
local function sticker(text, u, v, w, h, rot, fill)
	return function(S)
		word(S, text, u, v, w, h, rot, fill)
	end
end
PERK.SpeedX2 = function(container, item, opts)
	local c = col(item.color, C(110, 255, 160))
	local S = scene(container, { top = lighten(c, 0.25), bottom = darken(c, 0.45), dots = { darken(c, 0.4), 0.6 } })
	speedLines(S, WHITE, darken(c, 0.45), 0.15)
	addFigure(S, LOOKS.default, POSES.RUN)
	frameCamera(S, { yaw = 78, pitch = -4, roll = -6, fill = 0.78, shiftU = 0.1 })
	haloPass(S, WHITE, 0.3, "outer")
	inkPass(S)
	word(S, "x2", 0.2, 0.16, 0.3, 0.24, -10, C(255, 235, 60))
	return finish(S, opts)
end
PERK.JumpX2 = function(container, item, opts)
	local c = col(item.color, C(150, 170, 255))
	local S = scene(container, { top = lighten(c, 0.2), bottom = darken(c, 0.5), rays = { WHITE, 0.6, n = 8, u = 0.45, v = 0.55 }, dots = { darken(c, 0.35), 0.6 } })
	addFigure(S, LOOKS.default, POSES.JUMP)
	frameCamera(S, { yaw = 24, pitch = -10, fill = 0.7, shiftU = -0.1, shiftV = -0.03 })
	haloPass(S, WHITE, 0.3, "outer")
	inkPass(S)
	upArrow(S, 0.8, 0.2, 0.42, C(255, 235, 60))
	inkShape(S, { { 0.32, 0.92, 0.16, 0.08, 0, 0.5 }, { 0.47, 0.94, 0.2, 0.09, 0, 0.5 }, { 0.62, 0.92, 0.13, 0.07, 0, 0.5 } }, C(245, 245, 250), S.z + 7)
	word(S, "x2", 0.2, 0.16, 0.3, 0.24, -10, C(255, 235, 60))
	return finish(S, opts)
end
PERK.DashPass = function(container, item, opts)
	local c = col(item.color, C(110, 200, 255))
	local S = scene(container, { top = lighten(c, 0.15), bottom = darken(c, 0.55), dots = { darken(c, 0.35), 0.6 } })
	speedLines(S, WHITE, lighten(c, 0.4), 0.25)
	addFigure(S, LOOKS.default, POSES.DASH)
	addFigure(S, LOOKS.default, POSES.DASH, { at = CFn(0, 0, 2.3), ghost = 0.3, ghostColor = lighten(c, 0.35) })
	addFigure(S, LOOKS.default, POSES.DASH, { at = CFn(0, 0, 4.6), ghost = 0.55, ghostColor = lighten(c, 0.6) })
	frameCamera(S, { yaw = 80, pitch = -4, roll = -4, fill = 0.62, shiftU = 0.17 })
	haloPass(S, WHITE, 0.28, "outer")
	inkPass(S)
	return finish(S, opts)
end
PERK.VIP = function(container, item, opts)
	local S = scene(container, { top = C(255, 232, 110), bottom = C(205, 120, 10), rays = { WHITE, 0.5, n = 10 }, dots = { C(255, 160, 20), 0.55 },
		glow = { WHITE, size = 0.85 } })
	local look = { top = C(34, 30, 44), pants = C(28, 24, 36), belt = GOLD, shoes = GOLD, hair = C(30, 26, 40), spike = 0.9, gloves = WHITE }
	addFigure(S, look, clipPose("Victory", 0.8, POSES.HERO), { crown = true })
	frameCamera(S, { yaw = 20, pitch = -8, fill = 0.72, shiftV = 0.04 })
	haloPass(S, C(255, 250, 200), 0.34, "inner")
	haloPass(S, C(255, 190, 20), 0.72, "outer")
	inkPass(S)
	word(S, "VIP", 0.2, 0.15, 0.32, 0.22, -10, WHITE)
	return finish(S, opts)
end
local function ultScene(container, item, opts, look, pose, label)
	local c = col(item.color, C(255, 90, 200))
	local S = scene(container, { top = darken(c, 0.35), bottom = darken(c, 0.85), rays = { c, 0.62, n = 9 }, dots = { c, 0.7 }, glow = { lighten(c, 0.3), size = 0.95 } })
	addFigure(S, look, pose)
	frameCamera(S, { yaw = 12, pitch = -10, fill = 0.64, shiftV = 0.05 })
	flames(S, c, lighten(c, 0.6), 13, 1.3)
	haloPass(S, lighten(c, 0.65), 0.38, "inner")
	haloPass(S, c, 0.8, "outer")
	bolt(S, { { 0.06, 0.26 }, { 0.17, 0.38 }, { 0.09, 0.42 }, { 0.2, 0.55 }, { 0.13, 0.58 }, { 0.22, 0.7 } }, C(255, 250, 190), 0.034, S.D - 0.5)
	bolt(S, { { 0.94, 0.3 }, { 0.83, 0.42 }, { 0.91, 0.46 }, { 0.8, 0.59 }, { 0.87, 0.62 }, { 0.78, 0.74 } }, C(255, 250, 190), 0.034, S.D - 0.5)
	inkPass(S)
	word(S, label, 0.2, 0.15, 0.3, 0.22, -10, C(255, 240, 90))
	return finish(S, opts)
end
PERK.UltCharge = function(container, item, opts)
	return ultScene(container, item, opts, LOOKS.default, clipPose("PowerUp", 1.62, POSES.ROAR), "ULT")
end
PERK.UltOutfit = function(container, item, opts)
	local c = col(item.color, C(190, 140, 255))
	local look = { top = c, pants = darken(c, 0.5), belt = GOLD, shoes = GOLD, hair = C(250, 250, 255), spike = 1.3, gloves = WHITE }
	return ultScene(container, item, opts, look, clipPose("Pose", 0.36, POSES.HERO), "ULT")
end
PERK.AllFighters = function(container, item, opts)
	local c = col(item.color, C(255, 120, 90))
	local S = scene(container, { top = lighten(c, 0.15), bottom = darken(c, 0.6), rays = { WHITE, 0.55, n = 10 }, dots = { darken(c, 0.4), 0.6 } })
	local figs = {
		addFigure(S, LOOKS.Vulpine, mirror(POSES.STANCE), { at = CFn(-2.7, 0, 1.4) * ANG(0, rad(18), 0) }),
		addFigure(S, LOOKS.Limitless, POSES.STANCE, { at = CFn(2.7, 0, 1.4) * ANG(0, rad(-18), 0) }),
		addFigure(S, LOOKS.Gomu, POSES.HERO, { at = CFn(0, 0, -1.2) }),
	}
	frameCamera(S, { yaw = 0, pitch = -6, fill = 0.86, shiftV = 0.02 })
	for _, f in ipairs(figs) do
		haloPass(S, WHITE, 0.3, "outer", f.list)
	end
	inkPass(S)
	return finish(S, opts)
end
PERK.EarlyAccess = function(container, item, opts)
	local c = col(item.color, C(80, 230, 210))
	local S = scene(container, { top = darken(c, 0.45), bottom = darken(c, 0.88), rays = { c, 0.7, n = 8 }, dots = { c, 0.75 } })
	local sil = C(20, 24, 32)
	addFigure(S, { top = sil, pants = sil, belt = sil, shoes = sil, hair = sil, skin = sil, spike = 1.1 }, POSES.STANCE, { eyeColor = c })
	frameCamera(S, { yaw = 24, pitch = -6, fill = 0.72, shiftU = -0.06 })
	haloPass(S, c, 0.38, "outer")
	inkPass(S)
	word(S, "?", 0.45, 0.46, 0.46, 0.46, 6, WHITE, S.z + 9, 1.3)
	starUI(S, 0.77, 0.8, 0.34, C(255, 230, 60), "NEW", C(225, 35, 45))
	return finish(S, opts)
end
local function tauntScene(container, item, opts, pose, text, cam)
	local c = col(item.color, C(255, 190, 70))
	local S = scene(container, { top = lighten(c, 0.2), bottom = darken(c, 0.5), rays = { WHITE, 0.55, n = 9, u = 0.62, v = 0.55 }, dots = { darken(c, 0.35), 0.6 } })
	addFigure(S, LOOKS.default, pose)
	frameCamera(S, cam)
	haloPass(S, WHITE, 0.3, "outer")
	inkPass(S)
	bubble(S, text, 0.3, 0.19, 0.56, 0.3, 0.42, 0.35)
	return finish(S, opts)
end
PERK.TauntHype = function(container, item, opts)
	return tauntScene(container, item, opts, clipPose("Taunt", 1.92, POSES.BRING), "HYPE!", { yaw = 18, pitch = -6, fill = 0.66, shiftU = 0.12, shiftV = 0.1 })
end
PERK.TauntTrash = function(container, item, opts)
	return tauntScene(container, item, opts, clipPose("Taunt", 0.32, POSES.COMEON), "GG EZ", { yaw = 26, pitch = -6, fill = 0.66, shiftU = 0.12, shiftV = 0.1 })
end
PERK.StarterPack = function(container, item, opts)
	local c = col(item.color, C(255, 175, 60))
	local S = scene(container, { top = lighten(c, 0.25), bottom = darken(c, 0.5), rays = { WHITE, 0.5, n = 10 }, dots = { darken(c, 0.3), 0.6 }, glow = { WHITE, size = 0.8 } })
	addFigure(S, LOOKS.default, clipPose("Victory", 0.8, POSES.HERO))
	frameCamera(S, { yaw = 22, pitch = -8, fill = 0.7, shiftU = 0.08, shiftV = 0.05 })
	haloPass(S, WHITE, 0.34, "outer")
	inkPass(S)
	starUI(S, 0.22, 0.2, 0.36, C(255, 60, 70), "NEW!", WHITE)
	return finish(S, opts)
end
-- the retired packs (legacy owners' inventories)
PERK.Trails = function(container, item, opts)
	return B.trail(container, { id = "Rainbow" }, opts, sticker("x3", 0.2, 0.16, 0.28, 0.22, -10, C(255, 235, 60)))
end
PERK.KOFX = function(container, item, opts)
	return B.ko(container, { id = "Explosion" }, opts)
end
PERK.Skins = function(container, item, opts)
	return B.skin(container, { kit = "Limitless" }, opts)
end
PERK.Emotes = function(container, item, opts)
	return B.emote(container, { id = "Dance" }, opts)
end

-- AVATAR AURA (2026-11-10, "a character preview of the PERSON'S character with the aura") -----------------------------
-- The snapshot: ONE stripped clone of the local character, cached until it respawns / its appearance loads. Body parts
-- are posed by the same FK as the dummy, with the character's own joints (AnimationConstraints on this game's rigs,
-- Motor6Ds on a stock one: Part0, Part1, C0, C1); every other visible part (accessories, a kit's hat / sword) hangs
-- off the body part it is welded to (multi-source search through the weld graph from the body parts) at the offset
-- it has on the live character. Scripts, sounds, guis, effects, tools and every joint / constraint are stripped; the
-- Humanoid stays (it is what draws shirts / pants). Giant or morphed bodies are never snapshotted (the last good one
-- is kept), nor anything that is not an R15 with all 15 joints (the comic dummy is used instead).
local Players = game:GetService("Players")
local BODYSET = {}
for _, n in ipairs(BODY) do
	BODYSET[n] = true
end
local AV_STRIP = { "LuaSourceContainer", "Sound", "LayerCollector", "ParticleEmitter", "Trail", "Beam", "Light", "Fire", "Smoke", "Sparkles",
	"ForceField", "Highlight", "Tool", "BodyMover", "Explosion", "ProximityPrompt", "ClickDetector", "SelectionBox", "Constraint", "JointInstance",
	"WeldConstraint", "NoCollisionConstraint", "AnimationController" }
local function buildSnapshot(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp and hrp:IsA("BasePart") and char:FindFirstChild("UpperTorso") and char:FindFirstChild("Head")) then
		return nil
	end
	if hrp.Size.Y > 3.6 or char:GetAttribute("TitanForm") or char:GetAttribute("Morphed") or char:GetAttribute("Guardian") then
		return nil -- a giant form: keep the last good snapshot
	end
	local was = char.Archivable
	char.Archivable = true
	local ok, m = pcall(function()
		return char:Clone()
	end)
	char.Archivable = was
	if not ok or not m then
		return nil
	end
	local function isBody(p)
		return p.Parent == m and (BODYSET[p.Name] or p.Name == "HumanoidRootPart")
	end
	-- the rig's joints (body part -> joint) and a link graph for everything else
	local joints, adj = {}, {}
	local function link(a, b)
		if a and b and a ~= b and a:IsA("BasePart") and b:IsA("BasePart") and a:IsDescendantOf(m) and b:IsDescendantOf(m) then
			adj[a] = adj[a] or {}
			adj[b] = adj[b] or {}
			table.insert(adj[a], b)
			table.insert(adj[b], a)
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if not d:IsA("NoCollisionConstraint") then
			local p0, p1, c0, c1
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				p0, p1 = d.Part0, d.Part1
				if d:IsA("JointInstance") then
					c0, c1 = d.C0, d.C1
				end
			elseif d:IsA("Constraint") then
				local a0, a1 = d.Attachment0, d.Attachment1
				if a0 and a1 then
					p0, p1, c0, c1 = a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
				end
			end
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local rig = (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and isBody(p0) and isBody(p1) and BODYSET[p1.Name]
				if rig and not joints[p1.Name] then
					joints[p1.Name] = { d.Name, p0.Name, c0, c1 }
				else
					link(p0, p1)
				end
			end
		end
	end
	local order, done = {}, { HumanoidRootPart = true }
	for _ = 1, #BODY do
		for _, n in ipairs(BODY) do
			local j = joints[n]
			if j and not done[n] and done[j[2]] then
				done[n] = true
				table.insert(order, n)
			end
		end
	end
	if #order ~= #BODY then
		m:Destroy()
		return nil
	end
	-- every other part -> the body part it hangs from (its offset is fixed, whatever the live pose was)
	local owner, queue = {}, {}
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and isBody(c) then
			owner[c] = c
			table.insert(queue, c)
		end
	end
	local qi = 1
	while qi <= #queue do
		local p = queue[qi]
		qi += 1
		for _, q in ipairs(adj[p] or {}) do
			if not owner[q] then
				owner[q] = owner[p]
				table.insert(queue, q)
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and not isBody(d) then
			local o = owner[d]
			if not o then -- loose: the nearest body part within 2.5 studs
				local bd = 2.5
				for _, n in ipairs(BODY) do
					local bp = m:FindFirstChild(n)
					local dist = bp and (bp.Position - d.Position).Magnitude or math.huge
					if dist < bd then
						o, bd = bp, dist
					end
				end
			end
			if o then
				d:SetAttribute("CA_Body", o.Name)
				d:SetAttribute("CA_Rel", o.CFrame:ToObjectSpace(d.CFrame))
			else
				d:SetAttribute("CA_Drop", true)
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d.Parent then
			local drop = d:GetAttribute("CA_Drop") == true
			if not drop then
				for _, cls in ipairs(AV_STRIP) do
					if d:IsA(cls) then
						drop = true
						break
					end
				end
			end
			if drop then
				d:Destroy()
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.LocalTransparencyModifier = 0
			if d.Parent == m and BODYSET[d.Name] then
				d.Transparency = 0 -- a kit may have hidden a limb for a moment
			end
		elseif d:IsA("Humanoid") then
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
	m.Name = "Avatar"
	return { model = m, joints = joints, order = order }
end
local AV = { snap = nil, char = nil, dirty = true }
local function avatarSnapshot(source)
	if typeof(source) == "Instance" and source:IsA("Model") then
		return buildSnapshot(source) -- a Studio test model (not cached)
	end
	local plr = Players.LocalPlayer
	local char = plr and plr.Character
	if char and (AV.dirty or AV.char ~= char or not AV.snap) then
		local s = buildSnapshot(char)
		if s then
			if AV.snap then
				AV.snap.model:Destroy()
			end
			AV.snap, AV.char, AV.dirty = s, char, false
		end
	end
	return AV.snap -- (between respawns: the last one)
end
-- a posed copy of the snapshot in the scene
local function addAvatar(S, snap, pose)
	local m = snap.model:Clone()
	local cfs = { HumanoidRootPart = CFrame.identity }
	for _, n in ipairs(snap.order) do
		local j = snap.joints[n]
		local v = pose and pose[j[1]]
		local t = CFrame.identity
		if type(v) == "table" then
			t = ANG(rad(v[1] or 0), rad(v[2] or 0), rad(v[3] or 0))
			if typeof(v.pos) == "Vector3" then
				t = CFn(v.pos) * t
			end
		end
		cfs[n] = cfs[j[2]] * j[3] * t * j[4]:Inverse()
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Parent == m and (BODYSET[d.Name] or d.Name == "HumanoidRootPart") then
				d.CFrame = cfs[d.Name]
				if d.Name ~= "HumanoidRootPart" then
					table.insert(S.frame, d)
					table.insert(S.ink, d)
				end
			else
				local bn, rel = d:GetAttribute("CA_Body"), d:GetAttribute("CA_Rel")
				if bn and typeof(rel) == "CFrame" then
					d.CFrame = (cfs[bn] or CFrame.identity) * rel
					if d.Transparency < 0.6 then
						table.insert(S.frame, d)
						table.insert(S.ink, d)
					end
				end
			end
		end
	end
	m.Parent = S.world
	return m
end
-- the cards to re-render when the character changes (weak: a destroyed card just drops out)
local avatarCards = setmetatable({}, { __mode = "k" })
local avatarHooked, redrawPending = false, false
local function scheduleAvatarRedraw(delay)
	AV.dirty = true
	if redrawPending then
		return
	end
	redrawPending = true
	task.delay(delay, function()
		redrawPending = false
		for container, rec in pairs(avatarCards) do
			if container.Parent then
				CardArt.draw(container, rec.item, rec.opts)
			else
				avatarCards[container] = nil
			end
		end
	end)
end
local function hookAvatar()
	if avatarHooked then
		return
	end
	avatarHooked = true
	local plr = Players.LocalPlayer
	if plr then
		plr.CharacterAdded:Connect(function()
			scheduleAvatarRedraw(2.5) -- the new body's accessories / kit hat land over the next moments
		end)
		plr.CharacterAppearanceLoaded:Connect(function()
			scheduleAvatarRedraw(0.4)
		end)
	end
end
function B.avatarAura(container, item, opts)
	local aura = type(item.aura) == "table" and item.aura or item
	local c0, c1 = col(aura.c0, C(230, 220, 255)), col(aura.c1, C(120, 60, 255))
	local darkAura = lum(c1) < 0.2
	local S = begin(container, darkAura and lighten(c0, 0.25) or darken(c1, 0.55), darkAura and mix(c0, c1, 0.45) or darken(c1, 0.9), true)
	rays(S, darkAura and darken(c0, 0.2) or c1, darkAura and 0.55 or 0.78, 12, 0.1)
	dots(S, darkAura and c1 or c0, 0.72)
	glow(S, c1, 1.25, 0.5, 0.55)
	local snap = avatarSnapshot(opts.source)
	if snap then
		addAvatar(S, snap, POSES.AURA)
	else
		local top = darkAura and C(70, 62, 96) or darken(c1, 0.6)
		addFigure(S, { top = top, pants = darken(top, 0.35), belt = darken(top, 0.5), shoes = darken(top, 0.6), hair = C(30, 26, 40), spike = 1.1 }, POSES.AURA)
	end
	frameCamera(S, { yaw = 16, pitch = -8, roll = -2, fill = 0.7, shiftV = 0.05 })
	flames(S, darkAura and c1 or lighten(c1, 0.12), c0, 15, 1.15)
	haloPass(S, c0, 0.32, "inner")
	haloPass(S, c1, 0.66, "outer")
	inkPass(S)
	if not opts.source then
		avatarCards[container] = { item = item, opts = opts }
		hookAvatar()
	end
	return finish(S, opts)
end
function CardArt.avatarAura(container, auraItem, opts)
	return CardArt.draw(container, { kind = "avatarAura", aura = auraItem }, opts)
end

local KIND = { aura = B.aura, skin = B.skin, emote = B.emote, ko = B.ko, trail = B.trail, fighter = B.fighter, avatarAura = B.avatarAura }
local function builderFor(item)
	local k = item.kind
	if KIND[k] then
		return KIND[k]
	end
	if k == "perk" and type(item.id) == "string" then
		return PERK[item.id]
	end
	return nil
end

function CardArt.handles(item)
	return type(item) == "table" and builderFor(item) ~= nil
end

local function clear(container)
	for _, ch in ipairs(container:GetChildren()) do
		if string.sub(ch.Name, 1, 8) == "CardArt_" then
			ch:Destroy()
		end
	end
end

local warned = {}
function CardArt.draw(container, item, opts)
	local ok, res = pcall(function()
		if typeof(container) ~= "Instance" or not container:IsA("GuiObject") or type(item) ~= "table" then
			return false
		end
		opts = type(opts) == "table" and opts or {}
		clear(container)
		local fn = builderFor(item)
		if fn then
			local ok2, r = pcall(fn, container, item, opts)
			if ok2 and r == true then
				return true
			end
			clear(container)
			if not ok2 then
				local key = tostring(item.kind) .. "/" .. tostring(item.id or item.kit)
				if RunService:IsStudio() and not warned[key] then
					warned[key] = true
					warn("[CardArt] " .. key .. ": " .. tostring(r))
				end
			end
		end
		local I = Icons()
		if I and type(I.draw) == "function" then
			local ok3, r3 = pcall(I.draw, container, item, opts)
			return ok3 and r3 == true
		end
		return false
	end)
	return ok and res == true
end

return CardArt
