-- AscendantKit config: every tunable number, colour, key, label and asset slot for the ki-fighter kit: a passive
-- flight, a charged energy beam, an instant-transmission strike, a golden power form and a silver evasion form, plus
-- the kit's own M1 combo (both forms upgrade it). Visuals are original designs built from parts and particles; re-skin
-- by editing values here or filling the optional asset slots, not the code.
local C = Color3.fromRGB

return {
	KitId = "Ascendant",          -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are hit too (their own client applies the knockback)
	PlayerRagdollMax = 3,         -- seconds a knocked-back player tumbles at most

	Keys = { Beam = Enum.KeyCode.Q, Warp = Enum.KeyCode.E, Surge = Enum.KeyCode.R, Instinct = Enum.KeyCode.G },
	FlightKey = Enum.KeyCode.F,   -- toggles flight (double-tapping Space does too)
	AscendKeys = { Enum.KeyCode.Space },
	DescendKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl, Enum.KeyCode.C },

	-- names shown on the ability bar / in the callouts only (the code stays generic). Private-test names: swap for
	-- original names before publishing.
	Labels = { Beam = "KAMEHAMEHA", Warp = "TRANSMISSION", Surge = "SUPER SAIYAN", Instinct = "ULTRA INSTINCT", Flurry = "SILVER FLASH", Strike = "PUNCH", Flight = "FLIGHT" },
	Titles = { Beam = "KAMEHAMEHA", Warp = "INSTANT TRANSMISSION", Surge = "SUPER SAIYAN", Instinct = "ULTRA INSTINCT", Flurry = "SILVER FLASH" },

	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Beam = { kanji = "かめはめ波", glyph = "波", hint = "charge: cursor", c0 = C(236, 252, 255), c1 = C(30, 140, 255) },
		Warp = { kanji = "瞬間移動", glyph = "瞬", hint = "cursor / enemy", c0 = C(240, 250, 255), c1 = C(90, 190, 255) },
		Surge = { kanji = "超サイヤ人", glyph = "超", hint = "30 s form", c0 = C(255, 252, 215), c1 = C(255, 170, 20) },
		Instinct = { kanji = "身勝手の極意", glyph = "極", sub = "ULTRA INSTINCT", c0 = C(252, 252, 255), c1 = C(120, 120, 255) },
		Flurry = { kanji = "銀閃", glyph = "閃", sub = "BLINK STRIKES", c0 = C(252, 252, 255), c1 = C(150, 110, 255) },
		Flight = { c0 = C(240, 248, 255), c1 = C(140, 200, 255) },
	},

	Palette = {
		Ki = C(70, 185, 255),          -- the beam and its charge
		KiCore = C(238, 252, 255),
		KiDeep = C(20, 85, 255),
		KiPale = C(160, 225, 255),
		Gold = C(255, 205, 45),        -- the golden form
		GoldCore = C(255, 250, 215),
		GoldDeep = C(255, 135, 10),
		Bolt = C(150, 225, 255),       -- the golden form's lightning
		Silver = C(228, 234, 255),     -- the silver form
		SilverCore = C(255, 255, 255),
		SilverBlue = C(60, 100, 255),
		SilverPurple = C(150, 75, 255),
		Wind = C(236, 246, 255),       -- flight
		Hit = C(255, 236, 190),
		Numbers = C(255, 214, 90),     -- floating damage numbers
	},

	-- Fighter Skins perk (2026-11-07): "GOD BLUE" (PerkCatalog.SKINS.Ascendant). Used for a cast when the CASTER's player
	-- has Skin == "Alt" (ShopService writes it): these keys replace Palette's (anything not listed keeps its normal
	-- colour) and AltForms replaces the forms' hair / eye colours. The golden form burns blue, the beam runs cyan into
	-- indigo, and the silver form turns a cold divine blue.
	AltPalette = {
		Ki = C(40, 215, 255), KiCore = C(232, 255, 255), KiDeep = C(70, 50, 255), KiPale = C(150, 240, 255),
		Gold = C(45, 170, 255), GoldCore = C(210, 245, 255), GoldDeep = C(25, 90, 235), Bolt = C(175, 245, 255),
		Silver = C(190, 228, 255), SilverCore = C(240, 252, 255), SilverBlue = C(0, 150, 255), SilverPurple = C(35, 75, 235),
		Hit = C(185, 240, 255),
	},
	AltForms = {
		Surge = { HairColor = C(70, 200, 255), EyeColor = C(140, 235, 255) },
		Instinct = { HairColor = C(205, 232, 255), HairColor2 = C(140, 200, 255), EyeColor = C(150, 225, 255) },
	},

	Sounds = {
		Charge = "rbxassetid://110983945171856",
		Crackle = "rbxassetid://135281137796217",
		Zap = "rbxassetid://138830245023509",
		Thunder = "rbxassetid://9126050116",
		Boom = "rbxassetid://138533090376585",
		Whoosh = "rbxassetid://119573908217733",
		Hit = "rbxassetid://101232234433592",
		HitHeavy = "rbxassetid://79476956608476",
		Rise = "rbxassetid://122439012218772",
		Hum = "rbxassetid://9119415101",
	},

	-- Passive: omnidirectional flight. A LinearVelocity on the root (gravity cancelled by a VectorForce) carries the body
	-- wherever the input points - WASD along the camera (look up or down to climb or dive), Space / Shift straight up or
	-- down - at the same speed in every direction. The body lines up with its path: upright in a hover, flat out in level
	-- flight, head-first in a dive, banking into turns. Sinking onto the ground lands.
	Flight = {
		Speed = 62,             -- studs/s in any direction at full input (the golden form multiplies it)
		Response = 6,           -- how fast the velocity follows the input (higher = snappier)
		DoubleTap = 0.32,       -- seconds between two Space presses that toggle flight
		LandDistance = 4.2,     -- sinking this close to the ground lands
		LevelBand = 25,         -- a camera this many degrees up / down of level still flies W level (more = climb / dive later)
		Align = 1,              -- how far the body lines up with its path at speed (1 = fully, head-first; 0 = upright)
		Roll = 35,              -- degrees it banks into turns at most
		AuraRate = 18,          -- wind particles per second at rest (more when moving)
	},

	-- Skill 1: the charged beam. 1.5 s charge (cursor-aimed, rotation follows the cursor), then 1.5 s of continuous fire
	-- (rotation locked): raycast every Tick, multi-tick damage and a continuous push along the beam, then a final burst
	Beam = {
		Cooldown = 12,
		ChargeTime = 1.5,
		FireTime = 1.5,
		Tick = 0.1,
		Range = 220,
		Radius = 4.6,           -- the beam's thickness (bodies this close to its axis are caught)
		HeadSpeed = 520,        -- how fast the beam's head races out to full length
		MaxPitch = 40,          -- degrees the beam may aim up / down from the ground (flying: 80)
		TickDamage = 4.5,       -- per tick per body (15 ticks)
		PushSpeed = 58,         -- studs/s every caught body is carried along the beam
		PushKeep = 0.35,
		TickRagdoll = 1.4,
		FinalDamage = 40,       -- the closing burst on everything the beam carried
		FinalImpulse = 245,
		FinalUpBias = 0.35,
		FinalRagdoll = 4.5,
		BlastRadius = 22,       -- the explosion where the beam ends
		BlastDamage = 30,
		BlastImpulse = 200,
		Chant = { "KA...", "ME...", "HA...", "ME..." }, -- the charge, one syllable at each ChantAt (seconds)
		ChantAt = { 0.1, 0.45, 0.8, 1.15 },
		FireCall = "HAAAAAAAA!",
		FormScale = { Surge = 1.3, Instinct = 1.15 }, -- thicker beam in a form
	},

	-- Skill 2: instant transmission. A two-finger gesture, then a jump along the cursor ray (MaxDistance): 3 studs
	-- behind the enemy the ray passes, else to where it lands. On an enemy, an automatic turn kick follows.
	Warp = {
		Cooldown = 6,
		Gesture = 0.28,
		MaxDistance = 50,
		TargetRadius = 7,       -- an enemy this close to the cursor ray is the target
		Behind = 3,
		KickDelay = 0.12,
		KickDamage = 12,        -- minor damage; breaks blocks
		KickImpulse = 150,      -- lateral launch speed
		KickUpBias = 0.3,
		KickRagdoll = 2.4,
		GuardBreakTime = 1.5,   -- sets "GuardBrokenUntil" (and clears "Blocking") for block systems
	},

	-- Skill 3: the golden form. A ground-shaking burst, then 30 s of: walk / flight speed x1.5, jump x1.4, damage x1.2,
	-- stagger resistance, and M1 hits that throw small energy shockwaves. R again powers down early.
	Surge = {
		Cooldown = 40,          -- counted from when it ends
		Duration = 30,
		BurstTime = 1.4,        -- the power-up; the form arrives at BurstAt of it
		BurstAt = 0.85,
		WalkMul = 1.5,
		JumpMul = 1.4,
		FlightMul = 1.5,
		DamageMul = 1.2,
		StaggerResist = 0.5,    -- share of incoming knockback / tumble time shrugged off
		BurstRadius = 24,
		BurstImpulse = 150,
		BurstDamage = 10,
		ShockRadius = 9,        -- the M1 shockwave
		ShockDamage = 6,
		ShockImpulse = 70,
		HairColor = C(255, 214, 60),
		EyeColor = C(90, 255, 205),
		AddSpikes = true,       -- a spiked crown of glowing hair is added on top of (recoloured) hair
		HairTemplate = "",      -- optional: name of an Accessory in ReplicatedStorage.AscendantKit worn instead of the crown
	},

	-- Skill 4: the silver form. A cutscene (breath, eyes, shockwave), then 12 s of auto-evasion: any enemy body or
	-- projectile closing inside DodgeRadius, any hit, any knockdown -> an instant blink behind the attacker. M1 deals
	-- true damage, ignores blocks and launches with double impulse. G again: the blink-strike flurry.
	Instinct = {
		Cooldown = 120,          -- counted from when it ends [2026-11-10: was 60, ults ~2 min]
		Duration = 12,          -- counted from the end of the cutscene
		CutTime = 4.6,          -- the cutscene (the caster is untouchable through it)
		EyesAt = 2.1,           -- the eyes open: the form's look and the evasion switch on
		BurstAt = 2.7,          -- the shockwave
		BurstRadius = 42,
		BurstImpulse = 230,
		BurstDamage = 25,
		BurstRagdoll = 4,
		DodgeRadius = 6,
		ClosingSpeed = 12,      -- studs/s an enemy body must be closing at to set the dodge off
		ProjectileSpeed = 25,   -- likewise for loose projectiles
		DodgeBehind = 4,
		DodgeInterval = 0.3,    -- at most one blink per this many seconds (everything in between is still evaded)
		StrikeImpulseMul = 2,   -- M1 knockback multiplier
		HairColor = C(232, 236, 255),
		HairTransparency = 0.12,
		EyeColor = C(214, 222, 255),
		AddSpikes = true,       -- the swept-back crown of glowing silver spikes over (recoloured) hair
		HairTemplate = "",
		Flurry = { Cooldown = 5, Range = 70, Targets = 5, Step = 0.13, Damage = 16, Impulse = 185, UpBias = 0.45, Ragdoll = 3.5 },
	},

	-- M1: the kit's own four-hit combo (OwnM1). Hits 1-3 shove and stun, hit 4 launches.
	Strike = {
		Combo = 4,
		SwingInterval = 0.3,
		ComboReset = 1.1,
		FinalCooldown = 0.8,
		HitDelay = 0.1,
		Range = 5,              -- hitbox centre in front of the root
		HitboxSize = Vector3.new(5.5, 8, 6.5),
		Damage = 9,
		FinalDamage = 18,
		Push = 24,
		StunTime = 0.45,
		LightLaunch = Vector2.new(34, 18),  -- hits 1-3 in the silver form (x StrikeImpulseMul)
		LightRagdoll = 1.3,
		FinalLaunch = Vector2.new(75, 40),
		FinalRagdoll = 2.6,
	},
}
