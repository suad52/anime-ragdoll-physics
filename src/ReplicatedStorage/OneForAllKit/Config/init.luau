-- OneForAllKit config: every tunable number, colour, key, label and sound for the One For All kit (Deku):
-- Delaware Smash: Air Force, Detroit Smash, Blackwhip -> St. Louis Smash and the One For All ultimate.
-- Re-skin it here, not in code.
local C = Color3.fromRGB

local CONFIG = {
	KitId = "OneForAll",
	TargetTag = "RagdollNPC",

	Keys = { AirForce = Enum.KeyCode.Q, Detroit = Enum.KeyCode.E, Blackwhip = Enum.KeyCode.R, OFA = Enum.KeyCode.G },

	-- names shown on the ability bar and in the callouts only. Private-test names: swap for original names before
	-- publishing.
	Labels = { AirForce = "AIR FORCE", Detroit = "DETROIT SMASH", Blackwhip = "BLACKWHIP", OFA = "ONE FOR ALL" },

	Callouts = {
		AirForce  = { kanji = "空圧弾", glyph = "弾", hint = "aim: camera", c0 = C(236, 255, 244), c1 = C(60, 230, 140) },
		Detroit   = { kanji = "拳圧",   glyph = "拳", hint = "wide cone",   c0 = C(240, 255, 246), c1 = C(30, 205, 115) },
		Blackwhip = { kanji = "黒鞭",   glyph = "鞭", hint = "pull + kick", c0 = C(205, 255, 222), c1 = C(24, 110, 72) },
		OFA       = { kanji = "百万%",  glyph = "全", sub = "1,000,000%",   c0 = C(255, 248, 240), c1 = C(255, 44, 72) },
		-- titles that replace the callout mid-cast
		StLouis         = { text = "ST. LOUIS SMASH",          kanji = "蹴撃",                 c0 = C(240, 255, 246), c1 = C(64, 255, 140) },
		Million         = { text = "1,000,000% DETROIT SMASH", kanji = "デトロイト・スマッシュ", c0 = C(255, 255, 255), c1 = C(255, 40, 66) },
		DelawareDetroit = { text = "DELAWARE DETROIT SMASH",   kanji = "百%",                  c0 = C(255, 236, 228), c1 = C(255, 40, 66) },
		Cowl100         = { text = "FULL COWL · 100%",         kanji = "全身強化",              c0 = C(220, 255, 232), c1 = C(255, 40, 66) },
	},

	Palette = {
		Core      = C(240, 255, 246), -- white-hot heart of every bolt and flash
		Cowl      = C(64, 255, 140),  -- Full Cowl green lightning (the signature)
		CowlDeep  = C(16, 176, 96),   -- second green: sheaths, rings, deep glows
		Emerald   = C(0, 110, 70),    -- darkest green: tendril halos, HUD shading
		Spark     = C(205, 255, 220), -- glints, screen-space lines, impact tints
		Air       = C(215, 240, 255), -- AIR PRESSURE (wind is pale and cool, never green, so it reads as air)
		Crimson   = C(255, 40, 66),   -- 100%: veins, crimson lightning, ultimate UI
		Blood     = C(128, 0, 22),    -- vein sheath, dark crimson
		Ember     = C(255, 128, 96),  -- hot sparks off a 100% arm
		Whip      = C(14, 16, 18),    -- Blackwhip body
		Steam     = C(236, 236, 236),
		Sun       = C(255, 238, 196), -- the sunlight through the torn clouds
		Storm     = C(58, 62, 66),    -- cloud deck (top colour)
		StormDark = C(34, 38, 42),    -- cloud deck (bottom colour)
		Suit      = C(24, 64, 56),    -- Deku's costume teal: HUD button bases
	},

	Sounds = {
		Boom = "rbxassetid://138533090376585", HitHeavy = "rbxassetid://79476956608476",
		Hit = "rbxassetid://74041775202019", Hit2 = "rbxassetid://132555084427990", Whoosh = "rbxassetid://119573908217733",
		Thunder = "rbxassetid://104471217536585", Crackle = "rbxassetid://138132512434499",
		Zap = "rbxassetid://103012429197748", Shatter = "rbxassetid://9114592102", Swell = "rbxassetid://9043337370",
		Cannon = "rbxassetid://72411732778781", Sizzle = "rbxassetid://8927189937", Drone = "rbxassetid://9114353273",
		-- requested extras (search the library; until found, the client uses the fallback in brackets)
		SubBoom = "",   -- "deep cinematic sub-bass boom with a long rumble tail"   [Boom @ pitch 0.6]
		Choir = "",     -- "short heavenly choir swell, ~2 s"                       [Swell @ pitch 1.5, vol 0.4]
		WhipCrack = "", -- "sharp leather whip crack"                               [Hit2 @ pitch 1.8]
		WindRoar = "",  -- "powerful wind gust roar, 1-2 s"                         [Whoosh @ pitch 0.6]
		AirPop = "",    -- "compressed-air cannon pop"                              [Cannon @ pitch 1.35]
	},

	-- PASSIVE: Full Cowl. Always on while this kit is equipped
	Passive = {
		WalkSpeedMul = 1.2, JumpMul = 1.12,       -- JumpPower x mul, JumpHeight x mul^2 (Godspeed's rule)
		AirStep = {
			Cooldown = 0.9, ModeCooldown = 0.45,  -- server-side spam guard for the broadcast
			Steps = 1, ModeSteps = 2,             -- per airtime; refilled on landing
			MinAirTime = 0.18,                    -- s after leaving the ground before a step is allowed
			Up = 62, Push = 28, Keep = 0.6,       -- new vel = old horizontal * Keep + UP*Up + MoveDirection*Push
		},
		ArcEvery = 0.16, SkidEvery = 0.12, SkidSpeed = 12, GateDist = 160,
	},

	-- Q: one compressed-air bullet from a finger flick; the first living body on the line takes it
	AirForce = {
		Cooldown = 3.5, Lock = 0.45, Windup = 0.22,
		Speed = 260, Range = 95, HitRadius = 4, PitchMin = -20, PitchMax = 25,
		Damage = 16, Knockback = 120, UpKnock = 28, RagTime = 2.4,
		Splash = 7, SplashMul = 0.5, SplashDamage = 6, -- air burst round the impact point
		Escape = 10,                                   -- the body must still be this near the planned impact
	},

	-- E: coil, punch; the wind pressure races out along a cone, flinging bodies in order of distance and
	-- carving a trench of craters
	Detroit = {
		Cooldown = 8, Lock = 1.0, Charge = 0.42,
		Range = 80, HalfAngle = 24, FrontSpeed = 260, MaxY = 20,
		CoreRadius = 8, CoreAngle = 100,               -- point-blank ball round the fist, wider than the cone
		Damage = 46, FarMul = 0.6,                     -- 46 near, 27.6 at max range
		FlingNear = 175, FlingFar = 120, UpBias = 0.32, AimBlend = 0.7,
		CoreFling = 200, CoreUp = 0.25, HitStop = 0.07, RagTime = 3,
		Stations = { 8, 20, 34, 50, 68 },              -- distances of the trench craters along the aim
		ModeStations = { 8, 20, 34, 50, 68, 88, 106 },
		CraterBase = 3.5, CraterPerStud = 0.045, Rocks = 4, RockSpeed = 55,
		PushRadius = 12, PushSpeed = 140, PushUp = 0.35,
		LungeDist = 2.5, LungeTime = 0.09,
	},

	-- R: tendrils latch up to MaxTargets bodies in a cone, reel them in, then a spinning roundhouse kick
	Blackwhip = {
		Cooldown = 7, Lock = 1.05, LashAt = 0.14, Speed = 220,
		Range = 48, Cone = 55, MaxTargets = 5, ModeMaxTargets = 7,
		LatchDamage = 6, GatherForward = 4.5, GatherUp = 1.0, SlotSpacing = 1.6,
		PullGain = 9, PullMax = 190, PullUntil = 0.62,
		KickAt = 0.66, KickRadius = 8, KickDamage = 30, KickFling = 165, KickUp = 0.5, KickFan = 0.45,
		HitStop = 0.06, Spin = 14, RagTime = 3,
	},

	-- G: the ultimate
	OFA = {
		Cooldown = 120, Lock = 2.6, Charge = 1.0, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 32)
		WhipAt = 0.5, WhipRange = 90, WhipSpeed = 300, MaxTargets = 8, LatchDamage = 8,
		ClusterForward = 7, ClusterUp = 20, ClusterRing = 3.5, PullGain = 7, PullMax = 230,
		LeapAt = 1.10, LeapTime = 0.30, LeapRise = 16, LeapForward = 4,
		SmashAt = 1.40, HangUntil = 1.62, HitStop = 0.09,
		SmashRadius = 12, SmashDamage = 60, SmashFling = 260, SmashSpread = 0.22, SmashForward = 0.12,
		QuakeDelay = 0.06, QuakeRadius = 75, QuakeDamage = 22, QuakeFarMul = 0.5,
		QuakeFlingNear = 130, QuakeFlingFar = 70, QuakeUp = 0.45,
		CraterRadius = 8,
		RingCraters = {
			{ r = 22, n = 8, size = 4.5, rocks = 3, speed = 60, delay = 0.04 },
			{ r = 42, n = 10, size = 3.5, rocks = 2, speed = 45, delay = 0.18 },
		},
		DeckHeight = 170, MinCeiling = 26,
		FloatGravity = 0.28, FloatMax = 1.4,           -- the float-down: effective gravity x0.28, at most 1.4 s
		ModeAt = 2.5, RagTime = 4,
	},

	-- Full Cowl 100%: the mode after the ultimate (character attribute "OFAMode" = end server time)
	Mode = {
		Time = 12, WalkSpeedMul = 1.9, JumpMul = 1.35, DamageMul = 1.3,
		CooldownMul = { AirForce = 0.5, Detroit = 0.55, Blackwhip = 0.5 },
		Detroit = { Range = 110, HalfAngle = 30, Damage = 60, FlingMul = 1.3 },
		BurnoutRoot = 0.4,
	},
}
-- per-move override passes: every ModuleScript child of this module returns a table that is deep-merged over this one
-- (children applied in name order; a list - a table with [1] - replaces wholesale instead of merging index by index)
local function deepMerge(into, from)
	for k, v in pairs(from) do
		if type(v) == "table" and type(into[k]) == "table" and v[1] == nil then
			deepMerge(into[k], v)
		else
			into[k] = v
		end
	end
end
do
	local kids = script:GetChildren()
	table.sort(kids, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in ipairs(kids) do
		if child:IsA("ModuleScript") then
			local ok, t = pcall(require, child)
			if ok and type(t) == "table" then
				deepMerge(CONFIG, t)
			else
				warn("[OneForAllKit.Config] override " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return CONFIG
