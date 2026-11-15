-- StormdrawKit.Config: every tunable number, colour, key, label, sound and asset slot of the lightning-katana kit
-- (an M1 sword string, a lock-on flash dash, a six-dash ricochet, a 20 s focus state and a dragon-dash ultimate).
-- The code never names a skill by anything but the generic ids below (Slash / Flash / Chain / Focus / Dragon), so a
-- re-skin is done here: rename the labels, recolour the palettes, swap the sounds, or drop your own models into the
-- asset slots (Katana.SwordTemplate / ScabbardTemplate, Dragon.TemplateName). Visual defaults are built from parts.
local C = Color3.fromRGB

return {
	KitId = "Stormdraw",          -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are hit too (their own client applies the knockback)
	PlayerRagdollMax = 3,         -- seconds a knocked-back player tumbles at most

	Keys = { Flash = Enum.KeyCode.Q, Chain = Enum.KeyCode.E, Focus = Enum.KeyCode.R, Dragon = Enum.KeyCode.G },

	-- names shown on the ability bar / in the callouts only. Private-test names: swap for originals before publishing.
	Labels = { Slash = "SLASH", Flash = "FLASH", Chain = "SIXFOLD", Focus = "FOCUS", Dragon = "THUNDER GOD" },
	Titles = {
		Flash = "THUNDERCLAP AND FLASH", Chain = "THUNDERCLAP AND FLASH: SIXFOLD",
		Focus = "TOTAL CONCENTRATION", Dragon = "FLAMING THUNDER GOD",
	},
	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Slash = { glyph = "斬", c0 = C(255, 248, 225), c1 = C(255, 190, 60) },
		Flash = { kanji = "霹靂一閃", glyph = "閃", hint = "auto lock-on", c0 = C(255, 252, 220), c1 = C(255, 200, 30) },
		Chain = { kanji = "霹靂一閃・六連", glyph = "六", hint = "6 dashes", c0 = C(255, 250, 210), c1 = C(255, 150, 20) },
		Focus = { kanji = "全集中", glyph = "息", hint = "speed + cooldowns", c0 = C(236, 248, 255), c1 = C(110, 190, 255) },
		Dragon = { kanji = "火雷神", glyph = "龍", sub = "FLAMING THUNDER GOD", c0 = C(255, 252, 220), c1 = C(255, 165, 10) },
	},

	-- LOCK-ON: every ability aims itself. Bodies are tried class by class in Priority order - a player in range always
	-- outranks an NPC - and with nothing in range the move simply goes the way the character faces.
	Lock = {
		Priority = { "Player", "NPC" },
		CursorRadius = 9,     -- a body this close to the cursor's world point wins inside its class
		AngleWeight = 0.25,   -- otherwise the lowest (distance + degrees off the facing x this) wins
		NeedSight = true,     -- bodies behind a wall are never locked
	},

	Palette = {
		Bolt = C(255, 214, 64),        -- golden-yellow lightning
		BoltCore = C(255, 252, 226),   -- its white-hot core
		BoltDeep = C(255, 150, 20),    -- orange-gold accents (forks, fins, embers)
		Spark = C(255, 236, 130),
		Ghost = C(255, 222, 96),       -- afterimage clones
		Slash = C(255, 226, 110),      -- sword arcs
		Steel = C(226, 232, 246),      -- metal sparks
		Calm = C(120, 190, 255),       -- the calm blue of the breath / the slumber aura
		Mist = C(236, 246, 255),       -- breath vapour, wind lines
		Scorch = C(34, 28, 24),
		DragonEye = C(150, 220, 255),
	},
	-- an alternate colourway ("Skin" attribute = "Alt"): same keys, anything left out falls back to Palette
	AltPalette = {
		Bolt = C(120, 200, 255), BoltCore = C(240, 250, 255), BoltDeep = C(60, 110, 255), Spark = C(190, 230, 255),
		Ghost = C(140, 205, 255), Slash = C(170, 220, 255), Calm = C(255, 214, 110), DragonEye = C(255, 226, 120),
	},

	Sounds = {
		Crackle = "rbxassetid://135281137796217",
		Zap = "rbxassetid://1842430129",
		Thunder = "rbxassetid://93530870983093",
		Boom = "rbxassetid://127224055692526",
		Whoosh = "rbxassetid://9120972444",
		Hit = "rbxassetid://126976659766267",
		HitHeavy = "rbxassetid://79476956608476",
		Rise = "rbxassetid://102313023652420",
		Hum = "rbxassetid://96359585058783",
	},

	-- the sword. Built on every client from parts; SwordTemplate / ScabbardTemplate name optional Models placed in
	-- ReplicatedStorage.StormdrawKit that replace the built-in ones (a part named "Handle" with the blade along its
	-- -Z; a part named "ScabbardRoot" at the spot the sheathed Handle sits).
	Katana = {
		HandleLength = 1.15,
		BladeLength = 3.1,
		BladeSegments = 5,
		Curve = 2.2,            -- degrees each blade segment bends (the sori)
		SheatheAfter = 1.3,     -- seconds after the last swing before the sword goes back in by itself
		SwordTemplate = "KatanaTemplate",
		ScabbardTemplate = "ScabbardTemplate",
		Colors = {
			Blade = C(228, 234, 246), Edge = C(255, 226, 120), Guard = C(232, 184, 60), Wrap = C(34, 36, 58),
			Scabbard = C(22, 26, 48), Band = C(232, 184, 60), Cord = C(255, 150, 40),
		},
	},

	-- M1: a four-cut sword string (draw cut, return cut, spinning cut, leaping cleave). The last cut launches.
	Slash = {
		ComboLength = 4,
		SwingInterval = 0.36,
		ComboResetTime = 1.1,
		FinalCooldown = 0.8,          -- lockout after the 4th cut
		HitAt = { 0.12, 0.12, 0.15, 0.2 }, -- seconds into each swing that it lands
		Range = 5,                    -- hitbox centre distance in front of the root
		HitboxSize = Vector3.new(8, 7, 9),
		Damage = { 10, 10, 12, 20 },
		StunTime = 0.45,
		HitSlide = 1,                 -- studs cuts 1-3 shove a standing body
		FinalLaunch = Vector2.new(70, 36), -- X along the aim, Y up (studs/s) on the 4th cut
		RagdollTime = 2.4,
		-- inside the Focus state (Skill 3):
		FocusSpeedMul = 0.68,         -- swing interval / hit delay x this (about 1.5x swing speed)
		FocusBonus = Vector2.new(90, 44), -- extra launch (studs/s along the aim, up) added to every 4th cut
		FocusBonusRagdoll = 3,
	},

	-- Skill 1: the iaido stance, then one instant dash through the locked body; the cut lands a beat later
	Flash = {
		Cooldown = 4,                 -- x PvPShared.Balance.NON_ULT_COOLDOWN_MUL, like every non-ultimate move
		WindUp = 0.38,                -- the crouched draw stance
		Range = 45,
		DashTime = 0.08,
		PassThrough = 7,              -- the dash ends this far beyond a locked body
		Thickness = 4.5,              -- bodies this close to the dash line are cut
		HitDelay = 0.3,               -- the cut lands this long after the dash ends
		Damage = 15,
		Impulse = 115,                -- launch speed (studs/s)
		UpBias = 0.42,
		RagdollTime = 2.6,
		GuardBreakTime = 1.0,         -- clears "Blocking" and stamps "GuardBrokenUntil" for block systems
		GhostTime = 0.2,              -- seconds the dasher is invisible
		IFrames = 0.3,
	},

	-- Skill 2: six dashes in 1.2 s through up to six bodies (or six angles around one), ending in a sky bolt
	Chain = {
		Cooldown = 9,
		WindUp = 0.25,
		Radius = 35,                  -- bodies this close are woven into the web
		MaxTargets = 6,
		Strikes = 6,
		Duration = 1.2,               -- all six dashes
		DashTime = 0.08,
		Overshoot = 9,                -- each dash ends this far past the body it cuts (the web's radius round one body)
		Deflect = 35,                 -- degrees each exit is turned, alternating sides, so the path zig-zags
		Thickness = 4.5,
		Damage = 25,                  -- per body over the whole move, split across the cuts that land on it
		FinalShare = 0.4,             -- share of that carried by the slam
		StunTime = 0.5,
		LiftSpeed = 46,               -- the 6th cut pops its body up (studs/s)...
		SlamDelay = 0.22,             -- ...and this much later the bolt comes down on it
		Slam = Vector2.new(18, -88),  -- X outward, Y down (studs/s)
		SlamRagdoll = 3.2,
		SlamCrater = 6,
		GhostTime = 0.1,
	},

	-- Skill 3: a breath, then 20 s of speed
	Focus = {
		Cooldown = 12,                -- counted from when the state ends
		Inhale = 0.7,
		Duration = 20,
		WalkMul = 1.6,
		JumpMul = 1.3,
		CooldownMul = 0.6,            -- Flash and Chain recharge 40% faster (running cooldowns are cut as it starts)
		TrailSpeed = 24,              -- studs/s above which afterimages trail the runner
		TrailEvery = 0.085,
	},

	-- Skill 4 (the ultimate): a 1 s slumber, then a 70-stud dash inside a coiling lightning dragon
	Dragon = {
		Cooldown = 110,
		Charge = 1.0,
		Range = 70,
		DashTime = 0.5,
		Width = 7,                    -- bodies this close to the dash line are bored through
		Damage = 75,                  -- TRUE damage: written straight to Health
		Launch = Vector2.new(28, 150),-- X along the dash, Y up (studs/s)
		RagdollTime = 4,
		BlastRadius = 20,             -- the explosion at the end catches everything this close too
		TrenchStep = 9,               -- a ground crater every this many studs along the path
		BodyLength = 54,              -- the built-in dragon: studs of body behind the head
		Scale = 1,
		TemplateName = "DragonTemplate", -- your own Model (with a PrimaryPart facing -Z) in ReplicatedStorage.StormdrawKit
	},
}
