-- CarverKit config: every tunable number, colour, key, label and asset slot for the four-skill slicing kit (a triple
-- slash projection, a fire arrow, a world-wide cut, and a zone of cutting lines). Visual defaults are original
-- designs built from parts; re-skin by editing values here or by filling the optional asset slots, not the code.
local C = Color3.fromRGB

return {
	KitId = "Carver",            -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are hit too (their own client applies knockback / locks)
	PlayerRagdollMax = 3,         -- seconds a knocked-back player tumbles at most

	Keys = { Cleave = Enum.KeyCode.Q, Fuga = Enum.KeyCode.E, Sever = Enum.KeyCode.R, Shrine = Enum.KeyCode.G },

	-- names shown on the ability bar / in the callouts only (the code stays generic). Private-test names: swap for
	-- original names before publishing.
	Labels = { Cleave = "DISMANTLE", Fuga = "FUGA", Sever = "WORLD CUT", Shrine = "DOMAIN" },
	Titles = { Cleave = "DISMANTLE & CLEAVE", Fuga = "FUGA", Sever = "WORLD CUTTING SLASH", Shrine = "MALEVOLENT SHRINE", Expansion = "DOMAIN EXPANSION" },

	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Cleave = { kanji = "解", glyph = "解", hint = "3 cuts: cursor", c0 = C(255, 236, 238), c1 = C(235, 38, 62) },
		Fuga = { kanji = "炎", glyph = "炎", hint = "charge: cursor", c0 = C(255, 246, 205), c1 = C(255, 108, 20) },
		Sever = { kanji = "空間断", glyph = "断", hint = "ignores defense", c0 = C(236, 220, 255), c1 = C(112, 36, 210) },
		Shrine = { kanji = "魔廟", glyph = "廟", sub = "MALEVOLENT SHRINE", c0 = C(255, 226, 226), c1 = C(210, 22, 42) },
		Expansion = { kanji = "領域展開", c0 = C(255, 244, 244), c1 = C(200, 28, 48) },
	},

	Palette = {
		Slash = C(255, 60, 75),        -- cleave crescents
		SlashCore = C(255, 238, 240),
		Steel = C(215, 228, 255),      -- metal sparks
		FireCore = C(255, 248, 205),   -- fuga arrow
		Fire = C(255, 128, 28),
		FireDeep = C(205, 30, 22),
		RiftBlack = C(8, 0, 16),       -- world cut
		Rift = C(95, 25, 175),
		RiftEdge = C(205, 130, 255),
		Shrine = C(225, 35, 50),       -- domain
		ShrineDark = C(30, 6, 12),
		ShrineBone = C(235, 215, 205),
		LineRed = C(255, 40, 55),
		LineBlack = C(10, 2, 6),
		Fog = C(40, 4, 10),
		SkyAmbient = C(70, 6, 14),     -- the world under an open domain (any client near it)
		SkyOutdoor = C(60, 4, 12),
		SkyAtmosphere = C(110, 8, 22),
		SkyDecay = C(70, 0, 12),
	},

	-- (2026-11-07 perks) the alt skin "BONE KING" (HudShared.PerkCatalog.SKINS.Carver): every cast by a player whose Skin
	-- attribute is "Alt" draws with this palette instead - bone-white cuts, ivory soul-fire, a gold-lit rift, a shrine of
	-- bone and black under an ash sky. Same keys as Palette; any key left out falls back to Palette.
	AltPalette = {
		Slash = C(236, 222, 190),
		SlashCore = C(255, 253, 244),
		Steel = C(255, 228, 160),
		FireCore = C(255, 252, 238),
		Fire = C(236, 214, 160),
		FireDeep = C(150, 110, 58),
		RiftBlack = C(6, 4, 2),
		Rift = C(196, 160, 92),
		RiftEdge = C(255, 240, 205),
		Shrine = C(232, 218, 186),
		ShrineDark = C(16, 12, 8),
		ShrineBone = C(255, 250, 236),
		LineRed = C(244, 232, 200),
		LineBlack = C(10, 7, 4),
		Fog = C(46, 40, 32),
		SkyAmbient = C(58, 52, 42),
		SkyOutdoor = C(48, 43, 35),
		SkyAtmosphere = C(122, 110, 88),
		SkyDecay = C(64, 52, 34),
	},

	Sounds = {
		Crackle = "rbxassetid://90859028474173",
		Zap = "rbxassetid://7118966167",
		Thunder = "rbxassetid://2741718865",
		Boom = "rbxassetid://104471217536585",
		Whoosh = "rbxassetid://137628815514180",
		Hit = "rbxassetid://110594287267319",
		HitHeavy = "rbxassetid://72942854786548",
		Rise = "rbxassetid://85699884807201",
		Hum = "rbxassetid://9119415101",
	},

	-- Skill 1: three rapid cutting lines raycast along the aim; each projects a translucent crescent
	Cleave = {
		Cooldown = 5.5, -- 2026-11-11: was 4 ("increase his cooldowns")
		WindUp = 0.2,
		Lines = 3,
		LineInterval = 0.1,
		Range = 80,
		Thickness = 4,          -- bodies this close to a line are cut (measured to the body's nearest part)
		LockRadius = 7,         -- a body this close to the cursor / aim line is locked: every line re-aims at it
		LockAngle = 9,          -- ...or within this many degrees of the aim line (far targets)
		LockSlack = 10,         -- a locked body may be this far past Range and still be cut
		Fan = { -7, 7, 0 },     -- degrees of yaw each line is offset from the aim (only when nothing is locked)
		Tilts = { -38, 36, 4 }, -- roll of each crescent, so the three cuts cross
		Damage = 22,            -- per line; the last line hits harder
		FinalMul = 1.5,         -- the last line hits and launches harder
		EarlyMul = 0.2,         -- the earlier lines only shove, so the target is still there for the next cut
		Impulse = 150,
		UpBias = 0.3,
		RagdollTime = 3,
		GuardBreakTime = 0.8,   -- sets "GuardBrokenUntil" (and clears "Blocking") for block systems
		MarkLife = 2.6,         -- seconds the slash lines stay on the target's torso
		MarkDecal = "",         -- optional rbxassetid:// texture laid on the torso as well
	},

	-- Skill 2: a charged fire arrow, loosed as a physical projectile (AssemblyLinearVelocity) that bursts on contact
	Fuga = {
		Cooldown = 16, -- 2026-11-11: was 12
		ChargeTime = 1.4,
		ArrowSpeed = 300,
		Range = 420,
		HitRadius = 6,          -- a body this close to the flight line sets it off
		BlastRadius = 25,
		BlastDamage = 75,
		Impulse = 270,
		UpBias = 0.55,
		RagdollTime = 4.5,
		BurnTime = 3.2,         -- the scorched zone keeps burning everything inside
		BurnTick = 0.25,
		BurnDamage = 4.5,       -- per tick per body inside the zone
	},

	-- Skill 3: a spatial cut. Ignores blocks, force fields and invincibility: damage is written straight to Health
	Sever = {
		Cooldown = 24, -- 2026-11-11: was 18
		WindUp = 1.5,
		Range = 150,
		Width = 24,             -- total width of the cut
		Height = 30,            -- visual height of the tear
		Speed = 700,            -- how fast the visible cut races along its path
		Damage = 65,            -- true damage (2026-11-11: was 130, "nerf to half")
		Impulse = 220,
		UpBias = 0.55,
		RagdollTime = 5,
		FissureStep = 8,        -- a ground crater every this many studs along the path
	},

	-- Skill 4: the zone. Everything inside is locked, cut by lines and jolted for the duration, then thrown down
	Shrine = {
		Cooldown = 120,          -- counted from when it ends [2026-11-10: was 45, ults ~2 min]
		SealTime = 3.2,         -- the two-handed seal, the incantation and the shrine rising
		-- the incantation, one subtitle line every ChantGap seconds from ChantStart; "DOMAIN EXPANSION" at ExpansionAt,
		-- the domain's own name the moment it opens. Original placeholder lines: rewrite them freely.
		ChantLines = { "Bow before the shrine.", "Ten thousand blades, one hunger.", "No wall can stop the cut.", "Nothing within leaves whole." },
		ChantStart = 0.15,
		ChantGap = 0.6,
		ExpansionAt = 2.55,
		Duration = 5,
		Radius = 40,
		LockTime = 1.5,         -- targets inside when it opens cannot move for this long
		Tick = 0.1,
		TickDamage = 1.0,       -- minor damage every tick (about 50 over the full duration)
		TickImpulse = 5,        -- micro-impulse (studs/s) on every body each tick
		FinalDamage = 35,
		FinalImpulse = 240,
		FinalUpBias = 0.6,
		FinalRagdoll = 4.5,
		Lines = 240,            -- cutting lines drawn around the user
		TemplateName = "ShrineTemplate", -- your own model in ReplicatedStorage.CarverKit replaces the built-in shrine
	},
}
