-- GodspeedKit config: every tunable number, colour, key, label and sound for the Godspeed kit (a lightning
-- assassin: Lightning Palm, Thunderbolt, Rhythm Echo and the Godspeed ultimate). Re-skin it here, not in code.
local C = Color3.fromRGB

return {
	KitId = "Godspeed",           -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies

	Keys = { Palm = Enum.KeyCode.Q, Thunder = Enum.KeyCode.E, Echo = Enum.KeyCode.R, Godspeed = Enum.KeyCode.G },

	-- names shown on the ability bar and in the callouts only. Private-test names: swap for original names before
	-- publishing.
	Labels = { Palm = "LIGHTNING PALM", Thunder = "THUNDERBOLT", Echo = "RHYTHM ECHO", Godspeed = "GODSPEED" },

	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Palm = { kanji = "雷掌", glyph = "掌", hint = "dash", c0 = C(240, 250, 255), c1 = C(70, 170, 255) },
		Thunder = { kanji = "落雷", glyph = "雷", hint = "aim: cursor", c0 = C(245, 250, 255), c1 = C(110, 130, 255) },
		Echo = { kanji = "肢曲", glyph = "影", hint = "blink behind", c0 = C(240, 238, 255), c1 = C(150, 110, 255) },
		Godspeed = { kanji = "神速", glyph = "神", sub = "WHIRLWIND", c0 = C(255, 255, 255), c1 = C(80, 195, 255) },
	},

	Palette = {
		Core = C(245, 250, 255),  -- the white-hot heart of a bolt
		Bolt = C(110, 195, 255),  -- the electric blue sheath
		Violet = C(170, 150, 255), -- the second colour in his lightning
		Spark = C(205, 235, 255),
		Deep = C(40, 90, 230),
	},

	-- (2026-11-07 perks) VIOLET STORM, the alt skin (PerkCatalog.SKINS.Godspeed): used for a cast whose caster's player
	-- has Skin == "Alt". Laid over Palette key by key; the extra keys replace a few colours the normal look hard-codes
	AltPalette = {
		Core = C(252, 242, 255),   -- white-hot, faintly lilac
		Bolt = C(176, 92, 255),    -- the violet sheath
		Violet = C(255, 84, 214),  -- the second colour: hot magenta
		Spark = C(232, 206, 255),
		Deep = C(96, 28, 200),
		Flash = C(236, 220, 255),  -- the screen flash for onlookers (Thunderbolt, Godspeed finale)
		EchoTint = C(255, 214, 246), -- Rhythm Echo's impact frame and speed lines
	},
	-- the ultimate's title gradient in the alt skin (c0 top -> c1 bottom)
	AltCallout = { c0 = C(255, 250, 255), c1 = C(186, 96, 255) },

	Sounds = {
		Zap = "rbxassetid://103012429197748",
		Crackle = "rbxassetid://138132512434499",
		Thunder = "rbxassetid://168586586",
		Boom = "rbxassetid://3444652484",
		Whoosh = "rbxassetid://9120714365",
		Hit = "rbxassetid://74041775202019",
		HitHeavy = "rbxassetid://124871115622073",
	},

	-- electrocuted bodies: kept ragdolled and twitching while the attribute "Shocked" (a server time) is in the future
	Shock = { TwitchEvery = 0.09, Spin = 3.5, LimbKick = 5 },

	-- Q: a lightning-streak dash; the first body on the line takes a palm strike
	Palm = {
		Cooldown = 3,
		Windup = 0.14,        -- s before the dash leaves
		Speed = 150,          -- studs/s along the dash
		Distance = 30,        -- dash length (cut short by walls or the body it hits)
		HitRadius = 4.5,      -- how far off the line a body can be and still be struck
		Damage = 18,
		Knockback = 70,       -- studs/s along the dash
		UpKnock = 22,
		ShockTime = 2.2,
		Lock = 0.5,           -- s before another move can start
	},

	-- E: he leaps, and a bolt from the sky hits the cursor point
	Thunder = {
		Cooldown = 6,
		StrikeTime = 0.58,    -- s after the cast when the bolt lands
		MinRange = 8,
		MaxRange = 75,
		Radius = 16,
		Damage = 40,          -- at the centre (60% of it at the edge)
		Fling = 115,
		UpBias = 0.9,
		ShockTime = 2.8,
		LeapSpeed = 52,       -- upward speed of his jump
		Lock = 0.95,
	},

	-- R: he weaves, leaving afterimages, then blinks behind the nearest body in front of him and slashes it
	Echo = {
		Cooldown = 5,
		SwayTime = 0.36,      -- s of weaving before the blink
		SlashTime = 0.46,     -- s after the cast when the slash lands
		Range = 55,
		Cone = 80,            -- degrees either side of the aim a target may be
		BehindDist = 3.6,     -- he lands this far past the target
		NoTargetDist = 24,    -- with nobody in reach he just blinks this far forward
		Damage = 28,
		Knockback = 95,
		UpKnock = 40,
		ShockTime = 1.2,
		Lock = 0.85,
	},

	-- G: the ultimate. Charge, then blink through up to MaxTargets bodies striking each, then the sky answers every
	-- one he touched at once, then Godspeed mode (faster, an electric aura, shorter cooldowns) for ModeTime seconds
	Godspeed = {
		Cooldown = 120, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 30)
		Charge = 0.95,
		Range = 170,
		MaxTargets = 10,
		HopEvery = 0.16,      -- s between blinks
		HopDamage = 14,
		HopPop = 38,          -- upward speed each struck body is popped with
		FinaleDelay = 0.32,   -- s after the last blink
		FinaleDamage = 55,
		FinaleFling = 150,
		FinaleUp = 0.65,
		ShockTime = 3,
		ModeTime = 12,
		WalkSpeedMul = 2.1,
		JumpMul = 1.3,
		CooldownMul = { Palm = 0.4, Echo = 0.5, Thunder = 0.6 }, -- while Godspeed mode lasts
		PalmDistanceMul = 1.5,
		DamageMul = 1.3,      -- Palm and Echo hit this much harder in Godspeed mode
	},
}
