--!nocheck
-- GomuKit config: every tunable number, colour, key, label and sound of the Gomu kit (LUFFY, a rubber-bodied brawler):
-- the stretch-punch M1 string, Gatling (Q), Rocket (E), Gear Third Elephant Gun (R) and Gear Fifth (G, the ultimate:
-- 15 s sun-god mode in which G again = Bajrang Gun and the M1 becomes giant cartoon punches).
-- Re-skin and re-time it here, not in code. Each move's owner tunes its own numbers in a CHILD ModuleScript of this module
-- (Config.M1 / Gatling / Rocket / Elephant / Gear5 / Scaffold / Core), deep-merged over this table by the footer.
-- Contract: scratchpad luffy/CONTRACT.md. Names are private-test labels; swap them for originals before publishing.
-- CAST TEXT RULE (2026-11-07): ONLY the ultimate (Gear5 and the moves that exist only inside it: Bajrang) ever shows a
-- cast title / kanji. Q / E / R / M1 draw NO cast text - their Callouts rows only feed the ability bar (glyph + hint).
local C = Color3.fromRGB

local CONFIG = {
	KitId = "Gomu",
	TargetTag = "RagdollNPC",
	AffectPlayers = true,     -- PvP: other players' characters are hit too (their OWN client applies it: Remotes.Knockback)
	PlayerRagdollMax = 2.2,   -- the longest tumble a player victim is ever put in (s)
	OwnM1Kits = { Zangetsu = true, Ascendant = true }, -- kits that keep OwnM1 when you switch to them (Core leaves it set)

	-- M1 is the left mouse button (Enum.UserInputType.MouseButton1), sent as skill "M1". G sends "Gear5" always: the
	-- server routes it to Bajrang Gun while the mode is on (Bajrang has its own cooldown, shown on the G button in mode)
	Keys = { Gatling = Enum.KeyCode.Q, Rocket = Enum.KeyCode.E, Elephant = Enum.KeyCode.R, Gear5 = Enum.KeyCode.G },
	Skills = { "M1", "Gatling", "Rocket", "Elephant", "Gear5", "Bajrang" },

	-- names on the ability bar (MoveDock reads the first upper-case label; for the wide G button it shows `sub`)
	Labels = {
		M1 = "GUM-GUM PUNCH", Gatling = "GATLING", Rocket = "ROCKET", Elephant = "ELEPHANT GUN", Gear5 = "GEAR FIFTH",
		Bajrang = "BAJRANG GUN",
	},

	-- glyph + hint feed the ability bar. text / kanji are drawn ONLY for Gear5 / Drums / Laugh / Bajrang (the ultimate)
	Callouts = {
		M1       = { glyph = "拳", hint = "5-hit stretch combo", c0 = C(255, 246, 230), c1 = C(220, 40, 44) },
		Gatling  = { glyph = "連", hint = "barrage: aim",        c0 = C(255, 244, 220), c1 = C(235, 60, 50) },
		Rocket   = { glyph = "飛", hint = "slingshot: cursor",   c0 = C(255, 248, 225), c1 = C(240, 150, 40) },
		Elephant = { glyph = "象", hint = "giant fist: aim",     c0 = C(245, 235, 240), c1 = C(150, 30, 50) },
		Gear5    = { text = "GEAR FIFTH", kanji = "太陽神", glyph = "陽", sub = "SUN GOD NIKA", c0 = C(255, 255, 255), c1 = C(255, 205, 90) },
		-- ult-only mid-cast titles
		Drums    = { text = "DRUMS OF LIBERATION", kanji = "解放", c0 = C(255, 255, 255), c1 = C(200, 170, 255) },
		Laugh    = { text = "HA HA HA HA!",        kanji = "笑",   c0 = C(255, 255, 255), c1 = C(255, 215, 110) },
		Bajrang  = { text = "BAJRANG GUN",         kanji = "猿神銃", glyph = "猿", sub = "BAJRANG GUN", c0 = C(255, 255, 255), c1 = C(255, 190, 70) },
	},

	Palette = {
		-- the straw hat pirate
		Skin      = C(234, 184, 146), -- fallback rubber colour when the rig's own limb colour cannot be read
		Vest      = C(205, 28, 36),   -- the red vest: HUD bases, M1 accents
		VestDark  = C(130, 14, 22),
		Straw     = C(244, 206, 92),  -- the hat; the kit's accent gold
		StrawDark = C(190, 146, 52),
		Band      = C(196, 22, 30),   -- the hat band
		Denim     = C(54, 96, 168),   -- shorts blue (sparing accents)
		Rubber    = C(255, 222, 200), -- the sheen line along a stretched limb
		Whoosh    = C(255, 250, 240), -- whoosh trails, speed streaks, afterimage fists (additive white)
		Impact    = C(255, 236, 160), -- impact flashes / comic bursts (gold-white)
		Dust      = C(150, 140, 125),
		Steam     = C(245, 245, 245), -- Gear Third inflate / deflate steam
		-- armament haki (the Elephant Gun fist) + conqueror's lightning
		Haki      = C(22, 16, 24),    -- NEVER additive: SmoothPlastic / Glass parts, LightEmission 0 particles
		HakiSheen = C(120, 70, 160),  -- the dull purple sheen on a haki fist
		HakiBolt  = C(220, 30, 50),   -- red-black lightning crackling over the haki fist
		HakiBolt2 = C(20, 0, 8),
		-- Gear Fifth (Nika)
		Nika      = C(252, 252, 255), -- white rubber, white hair, white clothes tint
		Cloud     = C(236, 240, 255), -- the cloud scarf / sky clouds
		Sun       = C(255, 228, 140), -- the soft sun glow (lights, aura core)
		SunHot    = C(255, 190, 70),  -- sun flare accents
		Toon      = C(40, 30, 60),    -- cartoon outline ink (Highlight OutlineColor)
		Lavender  = C(214, 196, 255), -- the drum-beat pulse rings
		-- HUD
		Ink       = C(18, 14, 18),
	},

	-- every id below already exists in this place's kit configs (ZangetsuKit / OneForAllKit). Pitch suggestions:
	-- stretch = Whoosh at 1.35-1.6, snap-back = Hit2 at 1.3, drum beat = HitHeavy at 0.55, rubber boing = Rise at 1.8
	Sounds = {
		Boom = "rbxassetid://3444652484",     -- big explosion
		HitHeavy = "rbxassetid://101232234433592",  -- heavy hit (low pitch = a Drums of Liberation thump)
		Hit = "rbxassetid://126976659766267",      -- smack
		Hit2 = "rbxassetid://96359585058783",          -- sharp hit (the rubber snap-back at a higher pitch)
		Whoosh = "rbxassetid://9120718279",        -- swing / stretch / dash
		Thunder = "rbxassetid://104471217536585",   -- huge launch boom
		Crackle = "rbxassetid://168586586",  -- energy crackle (haki lightning)
		Zap = "rbxassetid://1842430129",           -- sting / flicker
		Shatter = "rbxassetid://9114592102",       -- glass shatter / ting
		Swell = "rbxassetid://9043337370",         -- rising swell (inflate, awakening)
		Cannon = "rbxassetid://72411732778781",    -- compressed blast (Pistol / Elephant Gun release)
		Sizzle = "rbxassetid://8927189937",        -- steam hiss
		Drone = "rbxassetid://9114353273",         -- low drone
		Void = "rbxassetid://9119392328",          -- deep tone
		Rise = "rbxassetid://102313023652420",     -- energy rise (a high pitch reads as a rubber boing)
		Hum = "rbxassetid://96359585058783",       -- hum / pressure
	},

	-- the straw hat (built on the SERVER by GomuKit.Hat, welded to the Head while this kit is equipped; owner: core).
	-- Studs, scaled by the head's height / 1.2. Hat-type accessories (HatAttachment) are hidden while it is on.
	Hat = {
		BrimDiameter = 3.0, BrimThick = 0.1, CrownDiameter = 1.45, CrownHeight = 0.62, BandHeight = 0.2,
		Lift = 0.36,   -- brim height above the head centre, x head height
		Back = 0.05,   -- the hat sits this far back (x head depth)
		Tilt = -9,     -- degrees: the brim tipped up at the front
		HideHats = true,
	},

	-- PASSIVE: rubber body (scaffold). Always on while this kit is equipped
	Passive = {
		WalkSpeedMul = 1.06, JumpMul = 1.12,   -- JumpPower x mul, JumpHeight x mul^2
		GateDist = 140,                         -- remote characters' passive visuals only within this camera distance
		BoingFall = 38,                         -- landing faster than this (studs/s down) plays the rubber squash (S.boing)
	},

	-- the client HUD / input knobs (scaffold)
	HUD = { M1Throttle = 0.08, M1Buffer = 0.12, M1SlowMul = 0.45, M1SlowExtra = 0.1, LateAt = 3 },

	-- the arm / leg STRETCH library (GomuKit.Client.Shared; owner: client). Defaults for every stretch handle
	Stretch = {
		Segments = 7,          -- cylinder segments from the shoulder (hip) to the wrist (ankle)
		ArmWidth = 0.78,       -- rubber thickness at the shoulder (studs, x armScale); tapers to WristWidth
		WristWidth = 0.6,
		LegWidth = 0.95, AnkleWidth = 0.7,
		Sag = 0.05,            -- droop at mid-length = Sag * length (studs) while extended (rubber hangs a little)
		Overshoot = 0.1,       -- the fist flies this fraction past the target, then snaps back to it
		Wobble = 0.35,         -- a decaying lateral sine (studs) along the limb right after the snap / on retract
		WobbleHz = 9,
		Out = 0.12, Hold = 0.05, Back = 0.16, -- default timings (s)
		MaxLength = 140,
		TrailLife = 0.14,      -- the whoosh Trail on the fist
		GhostEvery = 0.025,    -- afterimage fists dropped along the path while o.ghosts is on
		GhostLife = 0.12,
		FistScale = 1.15,      -- the fist (a clone of the Hand) is this much bigger than the hand by default
		RenderPriority = 202,  -- BindToRenderStep priority (Camera.Value + 2): AFTER the camera rewrites LocalTransparencyModifier
	},

	-- M1: the 5-hit stretch-punch string (server: Moves.M1; client: Client.M1; clips Clips.M1). The fist ARRIVES at
	-- HitAt (the client's stretch `out` = HitAt - (now - t0)), the server resolves the hit at the same moment
	M1 = {
		Cooldown = 0, ComboLength = 5, SwingInterval = 0.30, ComboResetTime = 1.1, FinalCooldown = 0.9,
		HitAt = { 0.12, 0.12, 0.14, 0.15, 0.22 },
		Lock = { 0.14, 0.14, 0.16, 0.16, 0.45 },   -- busy per swing (blocks Q/E/R/G only that long)
		Limb = { "L", "R", "L", "RL", "R" },      -- L / R arm, LL / RL leg (4 = the Gum-Gum Whip, a stretched leg sweep)
		Reach = { 11, 11, 12, 13, 26 },            -- studs from the shoulder (hip), wall-clamped; 5 = Gum-Gum PISTOL
		Radius = { 3, 3, 3.2, 3.6, 4 },             -- hit corridor around the shoulder -> fist line
		AimPitch = 35,                              -- the fist line's pitch is clamped to +-this (degrees)
		Damage = { 7, 7, 8, 9, 22 },
		StunTime = 0.45, HitSlide = 1.0,            -- swings 1-4 on a standing body (GojoShared.HitReact mark + slide)
		Juggle = Vector2.new(22, 30),               -- swings 1-4 on a ragdolled body / corpse: flat x, up y
		FinalLaunch = Vector2.new(110, 40),         -- the Pistol: flat, up
		FinalHitStop = 0.07, RagTime = 2.6,
		BlastRadius = 4.5,                          -- WorldBlast at the fist (glass only: < 6 punches no hole)
		FinalBlastRadius = 7,                       -- the finisher dents walls (>= 6 = Structure holes)
		-- the finisher on hit 5: the client picks it (Space held = Rifle, airborne = Axe, else Pistol); the server only
		-- whitelists the name. ComboCounter callouts: Pistol = "blast" (SMASH!), Rifle = "launch", Axe = "slam"
		Finishers = {
			Pistol = { combo = "blast" },
			Rifle = { combo = "launch", limb = "R", reach = 16, launch = Vector2.new(12, 92), spiral = 3 },  -- corkscrew uppercut
			Axe = { combo = "slam", limb = "RL", reach = 15, slam = Vector2.new(24, -80), crater = 8 },      -- Gum-Gum Battle Axe
		},
		Hold = { 0.04, 0.04, 0.05, 0.05, 0.08 },   -- client stretch timings after arrival
		Back = { 0.14, 0.14, 0.15, 0.17, 0.26 },
		FistScale = { 1.15, 1.15, 1.2, 1.2, 1.6 },
		Step = { 0.6, 0.6, 0.8, 1.0, 1.6 },        -- client root motion per swing (studs; stops 3.4 short of a body)
	},

	-- Q: Gum-Gum GATLING. Both arms blur into a storm of stretched fists down a forward cone; the last fist is a heavy one
	Gatling = {
		Cooldown = 8, Lock = 2.0,
		Windup = 0.28,                  -- arms drawn back, cheeks puffed
		Duration = 1.5,                 -- the barrage (from t0 + Windup)
		Tick = 0.075,                   -- server hit tick (20 ticks)
		Range = 22, HalfAngle = 26, MaxDY = 10,
		TickDamage = 2.2, TickStun = 0.3, TickSlide = 0.35, -- each tick on a standing body: hurt + HitReact flinch + slide
		FinalAt = 1.86,                 -- t0 + this: the heavy last fist
		FinalDamage = 12, FinalFling = 95, FinalUp = 30, RagTime = 2.4, FinalHitStop = 0.06,
		ChipEvery = 0.2,                -- facade chipping: a world raycast down the cone every ChipEvery s ...
		ChipRadius = 6.5, ChipSpeed = 70, -- ... WorldBlast + BreakBlast there (>= 6: small holes)
		Steer = true, TurnRate = 110,   -- deg/s: the cone follows the streamed camera aim (Request "Aim")
		FistsPerSecond = 28, FistScale = 1.1, FistLife = 0.12, -- client afterimage fists
	},

	-- E: Gum-Gum ROCKET. Both arms shoot out and grab the cursor point, the body is pulled back like a slingshot, then flies
	-- there (CLIENT-side movement on the caster's client) and slams into whatever is there
	Rocket = {
		Cooldown = 7, Lock = 1.2,
		Range = 75, MinRange = 12,
		Windup = 0.36,                  -- the arms fly out and grip the anchor
		Tension = 0.16,                 -- the body sinks back PullBack studs, the arms taut
		PullBack = 2.5,
		Speed = 150, MinTravel = 0.18, MaxTravel = 0.55, -- flight time = clamp(dist / Speed, Min, Max)
		ArriveBack = 3,                 -- stop this far short of the anchor surface
		PathRadius = 4, PathDamage = 10, PathFling = 80, PathUp = 30,
		SlamRadius = 13, SlamDamage = 26, SlamFling = 120, SlamUp = 45, RagTime = 2.8, HitStop = 0.06,
		BlastRadius = 14, BreakSpeed = 150, CraterRadius = 6, CraterRocks = 10, CraterSpeed = 70,
		Tolerance = 14,                 -- server: the HRP must be within this of the planned arrival, or no slam
	},

	-- R: Gear Third ELEPHANT GUN. Bite the thumb, the arm inflates into a giant haki fist, wind back, punch a long way
	Elephant = {
		Cooldown = 12, Lock = 1.9,
		InflateAt = 0.08, InflateTime = 0.55, -- the arm swells (steam) 0.08 -> 0.63
		PunchAt = 0.95,                 -- release (the windup holds the giant fist up behind him until here)
		Travel = 0.24,                  -- fist flight; HitAt = PunchAt + Travel
		HitAt = 1.19, Hold = 0.25, Back = 0.4, DeflateAt = 1.75,
		Range = 60, Width = 7, AimPitch = 20,
		Damage = 46, Fling = 185, Up = 50, RagTime = 3.2, HitStop = 0.1,
		FistScale = 7, ArmScale = 3.2, Haki = true,
		EndBlastRadius = 20, EndBreakSpeed = 230, -- the fist's end point: a big building hole / crater
		PathBlastEvery = 12, PathBlastRadius = 8, -- glass + small holes along the fist's path
		CraterRadius = 9, CraterRocks = 14, CraterSpeed = 90,
		ThreatRadius = 30, ThreatTime = 1.5,
	},

	-- G: GEAR FIFTH (the ultimate, the wide button). The Drums of Liberation, a white burst, laughter, then the mode
	Gear5 = {
		Cooldown = 120, Lock = 2.4, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 55)
		DrumAt = { 0.0, 0.32, 0.64, 0.9 }, -- heartbeat thumps (callout "Drums" at 0)
		BurstAt = 1.15,                 -- the white eruption: damage + knockback round him
		LaughAt = 1.5,                  -- callout "Laugh"
		ModeAt = 1.9,                   -- S.startMode
		ShotEnd = 1.15,                 -- a cinematic camera hands back here (<= 1.2 s of lost control)
		Radius = 28, Damage = 32, FarMul = 0.55, FlingNear = 150, FlingFar = 90, Up = 0.6, RagTime = 3.4,
		BlastRadius = 24, CraterRadius = 8, CraterRocks = 14, CraterSpeed = 80,
		ThreatRadius = 55, ThreatTime = 2.5,
		CloudRadius = 30,
	},

	-- G inside the mode: BAJRANG GUN. A titanic fist falls out of the clouds onto the cursor point
	Bajrang = {
		Cooldown = 8, Lock = 1.9,
		Range = 140, MinRange = 15,
		LeapAt = 0.0, RiseAt = 0.15,    -- he hops up, his arm shoots up into the sky
		FormAt = 0.55,                  -- the titanic fist forms in the clouds Height above the target
		DropAt = 0.95, ImpactAt = 1.45,
		FistSize = 46, Height = 170,
		Radius = 46, Damage = 70, FarMul = 0.45, FlingNear = 230, FlingFar = 120, Up = 0.5, RagTime = 4, HitStop = 0.12,
		BlastRadius = 48, BreakSpeed = 260,
		CraterRadius = 16, CraterRocks = 30, CraterSpeed = 150,
		RingCraters = { r = 30, n = 8, size = 6, rocks = 4, speed = 90, delay = 0.08 },
		RingBlasts = { r = 32, n = 6, radius = 22 }, -- mass building destruction round the crater
		ThreatRadius = 80, ThreatTime = 2.5,
	},

	-- the Gear Fifth mode (character attribute "Gear5Until" = end server time). Per-move tables are merged over that
	-- move's config while the mode is on (S.cfgFor); damage fields not set here are multiplied by DamageMul
	Mode = {
		Time = 15, WalkSpeedMul = 1.35, JumpMul = 1.45, DamageMul = 1.3,
		CooldownMul = { Gatling = 0.5, Rocket = 0.5, Elephant = 0.55 },
		ExitRoot = 0.3,
		M1 = {
			SwingInterval = 0.28, Reach = { 16, 16, 18, 19, 34 }, Radius = { 4.5, 4.5, 4.5, 5, 6 },
			FistScale = { 3, 3, 3, 3.4, 5 }, BlastRadius = 6.5, FinalBlastRadius = 12, FinalLaunch = Vector2.new(150, 60),
		},
		Gatling = { Range = 28, HalfAngle = 32, FistScale = 2.4, ChipRadius = 8 },
		Rocket = { Range = 95, Speed = 190, SlamRadius = 17, BlastRadius = 18 },
		Elephant = { FistScale = 11, Range = 75, Width = 10, EndBlastRadius = 26 },
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
				warn("[GomuKit.Config] override " .. child.Name .. " failed: " .. tostring(t))
			end
		end
	end
end

return CONFIG
