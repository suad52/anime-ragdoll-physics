--!nocheck
-- ZangetsuKit config: every tunable number, colour, key, label and sound for the Zangetsu kit (Ichigo): the sword
-- M1 combo, Getsuga Tensho (Q), Shunpo (E), Hollow Mask (R) and Bankai (G) -> the Tensa Zangetsu mode.
-- Re-skin and re-time it here, not in code. Each move's owner tunes its own numbers in a CHILD ModuleScript of this
-- module (Config.M1 / Getsuga / Shunpo / Hollow / Bankai / Scaffold), deep-merged over this table by the footer.
-- Design: scratchpad ichigo/DESIGN.md. Contract: ichigo/CONTRACT.md.
local C = Color3.fromRGB

local CONFIG = {
	KitId = "Zangetsu",
	TargetTag = "RagdollNPC",

	-- M1 is the left mouse button (Enum.UserInputType.MouseButton1), sent as skill "M1"
	Keys = { Getsuga = Enum.KeyCode.Q, Shunpo = Enum.KeyCode.E, Hollow = Enum.KeyCode.R, Bankai = Enum.KeyCode.G },
	Skills = { "M1", "Getsuga", "Shunpo", "Hollow", "Bankai" },

	-- names shown on the ability bar and in the callouts only. Private-test names: swap for original names before
	-- publishing.
	Labels = { M1 = "SLASH", Getsuga = "GETSUGA TENSHO", Shunpo = "SHUNPO", Hollow = "HOLLOW MASK", Bankai = "BANKAI" },

	Callouts = {
		M1      = { kanji = "斬",       glyph = "斬", hint = "4-hit combo",    c0 = C(240, 246, 255), c1 = C(150, 170, 200) },
		Getsuga = { kanji = "月牙天衝", glyph = "月", hint = "wave: aim",      c0 = C(240, 250, 255), c1 = C(110, 190, 255) },
		Shunpo  = { kanji = "瞬歩",     glyph = "瞬", hint = "dash: cursor",   c0 = C(236, 244, 255), c1 = C(140, 165, 210) },
		Hollow  = { kanji = "虚化",     glyph = "虚", hint = "nearest target", c0 = C(255, 240, 232), c1 = C(225, 20, 40) },
		Bankai  = { kanji = "卍解",     glyph = "卍", sub = "TENSA ZANGETSU",  c0 = C(255, 246, 246), c1 = C(200, 16, 36) },
		-- titles that replace the callout mid-cast
		Ban           = { text = "BAN...",         kanji = "卍",       c0 = C(255, 255, 255), c1 = C(170, 205, 255) },
		Kai           = { text = "...KAI!",        kanji = "卍解",     c0 = C(255, 240, 240), c1 = C(210, 18, 40) },
		Tensa         = { text = "TENSA ZANGETSU", kanji = "天鎖斬月", c0 = C(255, 250, 250), c1 = C(160, 0, 24) },
		BlackGetsuga  = { text = "GETSUGA TENSHO", kanji = "黒月牙",   c0 = C(255, 232, 232), c1 = C(200, 10, 30) },
		HollowGetsuga = { text = "GETSUGA TENSHO", kanji = "虚月牙",   c0 = C(255, 240, 205), c1 = C(230, 20, 30) },
		Zan           = { text = "ZAN",            kanji = "斬",       c0 = C(255, 255, 255), c1 = C(150, 200, 255) },
	},

	Palette = {
		-- Shikai reiatsu: cold blue-white
		Core      = C(240, 250, 255), -- white-hot heart of every Getsuga / slash
		Reiatsu   = C(150, 215, 255), -- ice-blue edges, flames, rings
		Ice       = C(80, 160, 255),  -- deeper blue: sheaths, deep glows
		Frost     = C(205, 235, 255), -- pale: air, wind, sparks, slash lines
		-- Bankai: black core, crimson edge, red-black flames
		Black     = C(14, 10, 14),    -- NEVER additive: SmoothPlastic/Glass parts and LightEmission 0 particles
		Crimson   = C(220, 20, 40),   -- the Bankai edge, rims, sparks
		Ember     = C(255, 90, 60),   -- hot crimson sparks
		Blood     = C(110, 0, 18),    -- dark crimson: sheaths, coat lining glow
		Smoke     = C(36, 30, 34),    -- black reiatsu smoke (LightEmission 0)
		-- Hollow
		Hollow     = C(255, 34, 34),  -- mask stripes, hollow reiatsu glow
		HollowDark = C(28, 0, 6),     -- the swirl that forms the mask (LightEmission 0)
		Bone       = C(245, 242, 232),-- the mask
		EyeGold    = C(255, 214, 40), -- hollow iris
		-- the sword and costume
		Steel     = C(52, 54, 60),    -- Shikai blade
		SteelDark = C(30, 32, 36),    -- Shikai spine
		Edge      = C(225, 230, 240), -- Shikai cutting edge (silver)
		Cloth     = C(238, 234, 224), -- Shikai hilt wrap + trailing cloth
		ClothShade= C(205, 200, 190),
		Tensa     = C(16, 14, 18),    -- Bankai blade
		TensaEdge = C(200, 205, 215), -- Bankai edge
		Guard     = C(35, 35, 40),    -- manji guard, pommel
		Chain     = C(92, 94, 102),
		Coat      = C(18, 16, 20),    -- Bankai coat
		Lining    = C(150, 10, 24),   -- Bankai coat lining
		-- HUD
		Robe      = C(20, 20, 26),    -- shihakusho black: button bases
		Dust      = C(150, 140, 125),
	},

	-- every id below already exists in this place's kit configs (see DESIGN.md §0 for where each was found)
	Sounds = {
		Boom = "rbxassetid://9126050116",     -- big explosion
		HitHeavy = "rbxassetid://72942854786548",  -- heavy hit
		Hit = "rbxassetid://140277245983305",      -- smack
		Hit2 = "rbxassetid://7118966167",          -- sharp hit (blade bite)
		Whoosh = "rbxassetid://125132253621935",        -- swing / dash
		Thunder = "rbxassetid://104471217536585",   -- huge launch boom
		Crackle = "rbxassetid://90859028474173",  -- energy crackle
		Zap = "rbxassetid://137628815514180",           -- sting / flicker
		Shatter = "rbxassetid://9114592102",       -- glass / mask shatter, the Shunpo "ting"
		Swell = "rbxassetid://9043337370",         -- rising energy swell
		Cannon = "rbxassetid://72411732778781",    -- compressed blast
		Sizzle = "rbxassetid://8927189937",        -- flame sizzle
		Drone = "rbxassetid://9114353273",         -- low drone (silent beats, mask)
		Void = "rbxassetid://9119392328",          -- deep void tone (hollow)
		Rise = "rbxassetid://102313023652420",     -- energy rise / orb birth
		Hum = "rbxassetid://96359585058783",       -- chant / hum (reiatsu pressure)
	},

	-- the sword (ReplicatedStorage.ZangetsuKit.Sword builds it). Distances are along the blade axis from the GRIP point
	-- (the centre of the fist). Motor6D "SwordGrip": Part0 = RightHand, Part1 = Handle,
	-- C0 = CFrame.new(GripPoint) * CFrame.Angles(math.pi, 0, 0), C1 = CFrame.new(0, HandleGripY, 0).
	-- SwordGrip.Transform = identity -> the blade continues the FOREARM line (elbow -> wrist -> tip).
	Sword = {
		GripPoint = Vector3.new(0, -0.12, 0), -- in RightHand space
		HandleGripY = -0.30,                  -- the grip point in Handle space (Handle +Y = toward the tip, +Z = edge side)
		Shikai = { Pommel = -0.15, Root = 0.75, Tip = 4.95, Width = 0.98 },
		Bankai = { Pommel = -0.15, Root = 0.74, Tip = 4.34, Width = 0.26 },
		ExitFormDelay = 0.45, -- the mode ends -> the server swaps back to Shikai this much later (the dissolve plays first)
	},

	-- PASSIVE: reiatsu flicker while moving (scaffold). Always on while this kit is equipped, outside Bankai mode
	Passive = {
		WalkSpeedMul = 1.1, JumpMul = 1.05,  -- JumpPower x mul, JumpHeight x mul^2
		GateDist = 140,                      -- remote characters' passive visuals only within this camera distance
		FullSpeed = 22,                      -- studs/s at which the flicker is at full strength
		GlintEvery = { 3, 6 },               -- s between blade glints while standing still
	},

	-- M1: the 4-hit sword combo (server: Moves.M1; client: Client.M1; clips Slash1..Slash4)
	M1 = {
		Cooldown = 0, ComboLength = 4, SwingInterval = 0.34, ComboResetTime = 1.1, FinalCooldown = 0.85,
		HitAt = { 0.14, 0.14, 0.18, 0.30 },   -- server seconds after the swing's t0
		Lock = { 0.16, 0.16, 0.2, 0.5 },      -- busy per swing (blocks Q/E/R/G only that long)
		Range = 6, HitboxSize = Vector3.new(9, 7, 8), -- swings 1-3: oriented box centred Range ahead of the HRP
		FinalRadius = 11, FinalHalfAngle = 80,         -- swing 4: the spinning cleave's cone
		Damage = { 9, 9, 11, 24 },
		Knockback = 20, StunTime = 0.45,      -- swings 1-3 on a standing body (like the shared punch)
		Juggle = Vector2.new(30, 32),         -- swings 1-3 on a ragdolled body / corpse: flat x, up y
		FinalLaunch = Vector2.new(85, 45),    -- swing 4: flat x, up y
		FinalHitStop = 0.06, RagTime = 2.6,
	},

	-- Q: Getsuga Tensho. A crescent of reiatsu travels along the flat aim, piercing every body in its path
	Getsuga = {
		Cooldown = 6, Lock = 1.3, RootTime = 1.25, Windup = 0.62,
		Speed = 160, Range = 110, StartAhead = 2.5, Height = 0.5, -- the wave centre: hrp + UP*Height + flat*StartAhead
		Width = 16, HalfWidth = 7, HalfHeight = 9, Tilt = -30,       -- crescent span / hit corridor / roll (deg)
		Damage = 40, Knock = 130, Up = 45, HitStop = 0.06, RagTime = 3,
		StationEvery = 14, CraterRadius = 3.2, CraterRocks = 3, CraterSpeed = 45, GroundSkim = 6,
		WallRadius = 6,
	},

	-- E: Shunpo. Vanish, cut through everything on the path, arrive behind them back-turned, a silent beat, then the cut
	Shunpo = {
		Cooldown = 7, Lock = 1.25, DepartAt = 0.20, ArriveAt = 0.34, CutAt = 0.95,
		Range = 46, MinRange = 14, Overshoot = 7, PathRadius = 6, MaxDY = 8, MaxTargets = 8,
		Damage = 34, Fling = 120, ForwardMix = 0.45, Lateral = 15, HitStop = 0.08, RagTime = 3,
	},

	-- R: Hollow Mask. The mask forms, a roar, a blitz of slashes round the nearest body in the air, a point-blank
	-- Getsuga, the mask shatters
	Hollow = {
		Cooldown = 14, Lock = 3.3, Range = 45,
		RoarAt = 0.80, RoarRadius = 18, RoarDamage = 8, RoarPush = 75, RoarUp = 25,
		BlitzAt = 1.05, Slashes = 6, SlashEvery = 0.13, SlashDamage = 6, SlashRing = 4.2,
		HoverUp = 4.5, PullGain = 8, PullMax = 120, Escape = 14,
		FinisherAt = 2.00, FinisherDamage = 30, FinisherFling = 210, FinisherUp = 55, FinisherHitStop = 0.12,
		FinisherBack = 5.5, FinisherRange = 40, FinisherWidth = 6, WaveDamage = 18, WaveFling = 120, WaveUp = 30,
		CrackAt = 2.40, ShatterAt = 2.85, RagTime = 3.5,
		WhiffAhead = 9, WhiffUp = 3,
	},

	-- G: Bankai. BAN...KAI, the pillar erupts (damage + knockback), the sword and coat transform, then the mode
	Bankai = {
		Cooldown = 120, Lock = 2.7, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 40)
		KaiAt = 0.55, EruptAt = 1.10, FormAt = 1.30, RevealAt = 1.85, ModeAt = 2.40,
		ShotEnd = 1.15,                       -- the cinematic camera hands back here (<= 1.2 s of lost control)
		Radius = 30, Damage = 35, FarMul = 0.6, FlingNear = 165, FlingFar = 100, Up = 0.55, RagTime = 3.5,
		CraterRadius = 9, CraterRocks = 12, CraterSpeed = 70,
		RingCraters = { r = 16, n = 8, size = 3, rocks = 2, speed = 50, delay = 0.05 },
		PillarRadius = 7, PillarHeight = 120,
		ThreatRadius = 50, ThreatTime = 2.5,
	},

	-- Tensa Zangetsu: the mode after Bankai (character attribute "BankaiUntil" = end server time)
	Mode = {
		Time = 15, WalkSpeedMul = 1.6, JumpMul = 1.2, DamageMul = 1.25,
		CooldownMul = { Getsuga = 0.5, Shunpo = 0.45, Hollow = 0.6 },
		ExitRoot = 0.35,
		M1 = { SwingInterval = 0.26, WaveRange = 14, WaveHalfWidth = 2.5, WaveDamage = 6,
			FinalWaveRange = 30, FinalWaveDamage = 14, FinalWaveFling = 120 },
		Getsuga = { Speed = 210, Range = 140, Width = 20, HalfWidth = 9, Damage = 55, Knock = 170, CraterRadius = 4.2 },
		Shunpo = { Range = 60, MaxTargets = 10, Damage = 42, SecondCut = 0.12, SecondDamage = 10 },
		Hollow = { Slashes = 8, SlashEvery = 0.11, FinisherAt = 2.05, FinisherDamage = 38, FinisherRange = 60 },
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
				warn("[ZangetsuKit.Config] override " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return CONFIG
