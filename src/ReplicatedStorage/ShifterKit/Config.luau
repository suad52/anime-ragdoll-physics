-- ShifterKit config: every tunable number, colour, key, label and asset slot for the four-skill shifter kit (grapple
-- mobility with twin blades, and three giant transformations). Visual defaults are original designs built from parts;
-- re-skin by editing values here or by dropping your own models into the template slots, not by editing code.
local C = Color3.fromRGB

return {
	KitId = "Shifter",           -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are hit too (their own client applies knockback)
	PlayerRagdollMax = 3,         -- seconds a knocked-back player tumbles at most

	-- Release: leaves a standing form early (its normal end and cooldown); refused while the entrance still plays
	Keys = { Tether = Enum.KeyCode.Q, Warrior = Enum.KeyCode.E, Colossus = Enum.KeyCode.R, Founder = Enum.KeyCode.G, Release = Enum.KeyCode.X },

	-- names shown on the ability bar / in the callouts only (the code stays generic). Private-test names: swap for
	-- original names before publishing.
	Labels = { Tether = "ODM GEAR", Warrior = "ATTACK TITAN", Colossus = "COLOSSAL", Founder = "FOUNDING TITAN", Release = "RELEASE" },
	Titles = {
		Tether = "ODM GEAR", Spin = "SPINNING SLASH",
		Warrior = "ATTACK TITAN", WarriorSlam = "TITAN HAMMER SLAM", WarriorPunch = "TITAN PUNCH",
		Colossus = "COLOSSAL TITAN", ColossusBurst = "STEAM RELEASE",
		Founder = "FOUNDING TITAN", Rumble = "THE RUMBLING",
	},

	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Tether = { kanji = "立体機動", glyph = "刃", hint = "hook: cursor", c0 = C(235, 245, 255), c1 = C(90, 150, 210) },
		Spin = { kanji = "回転斬り", c0 = C(240, 250, 255), c1 = C(120, 200, 255) },
		Warrior = { kanji = "進撃の巨人", glyph = "進", hint = "E again: slam", c0 = C(220, 255, 230), c1 = C(40, 190, 110) },
		WarriorSlam = { kanji = "鉄槌", c0 = C(230, 255, 235), c1 = C(40, 190, 110) },
		WarriorPunch = { kanji = "巨人の拳", c0 = C(230, 255, 235), c1 = C(40, 190, 110) },
		Colossus = { kanji = "超大型巨人", glyph = "超", hint = "R again: steam", c0 = C(255, 235, 200), c1 = C(225, 70, 30) },
		ColossusBurst = { kanji = "蒸気爆発", c0 = C(255, 250, 240), c1 = C(255, 120, 50) },
		Founder = { kanji = "始祖の巨人", glyph = "祖", sub = "FOUNDING TITAN", c0 = C(245, 250, 255), c1 = C(150, 190, 235) },
		Rumble = { kanji = "地鳴らし", c0 = C(255, 245, 230), c1 = C(200, 150, 110) },
	},

	Palette = {
		-- gear
		Steel = C(196, 204, 214), SteelDark = C(64, 68, 76), Blade = C(228, 236, 246), BladeGlow = C(175, 230, 255),
		Cable = C(34, 34, 40), Leather = C(96, 64, 42), Gas = C(240, 242, 245),
		-- shared transformation fx
		Bolt = C(255, 210, 80), BoltCore = C(255, 252, 232), BoltDeep = C(255, 140, 35),
		Steam = C(236, 236, 236), SteamWarm = C(255, 228, 205),
		Fireball = C(255, 165, 55), FireCore = C(255, 246, 215), Smoke = C(72, 64, 60), Ember = C(255, 118, 30),
		-- attack titan
		WarriorSkin = C(198, 156, 126), WarriorShade = C(150, 104, 84), WarriorMuscle = C(176, 62, 62),
		WarriorHair = C(24, 19, 17), WarriorEye = C(70, 255, 110), Teeth = C(242, 236, 214), Gums = C(124, 32, 38), MouthDark = C(26, 8, 8),
		-- colossal titan
		ColossusMuscle = C(170, 44, 34), ColossusFiber = C(118, 22, 18), ColossusTendon = C(230, 216, 190), ColossusEye = C(255, 240, 205), ColossusHeat = C(255, 120, 40),
		-- founding titan
		Bone = C(232, 226, 208), BoneShade = C(176, 166, 146), FounderEye = C(215, 240, 255), FounderGlow = C(185, 222, 255), FounderHair = C(30, 26, 26),
		Tint = C(255, 238, 212),
		-- the swarm's skin tones (picked at random per giant)
		Flesh = { C(214, 170, 140), C(196, 150, 120), C(232, 192, 162), C(172, 122, 96), C(150, 104, 80) },
	},

	-- Fighter Skins perk (2026-11-07): "CRYSTAL TITAN" (PerkCatalog.SKINS.Shifter). Used for a cast when the CASTER's
	-- player has Skin == "Alt" (ShopService writes it): these keys replace Palette's (anything not listed keeps its
	-- normal colour), and the titan bodies, the founding skeleton and the bone spears take AltMaterial. Hardened
	-- crystal skin, cold blue lightning, a blue-white blast and a crystal skeleton instead of bone.
	AltPalette = {
		BladeGlow = C(120, 240, 255),
		Bolt = C(120, 210, 255), BoltCore = C(236, 250, 255), BoltDeep = C(70, 110, 255),
		Steam = C(226, 240, 252), SteamWarm = C(200, 228, 255),
		Fireball = C(95, 185, 255), FireCore = C(226, 248, 255), Smoke = C(48, 60, 86), Ember = C(80, 200, 255),
		WarriorSkin = C(176, 222, 245), WarriorShade = C(104, 160, 210), WarriorMuscle = C(60, 110, 200),
		WarriorHair = C(26, 34, 62), WarriorEye = C(110, 245, 255), Teeth = C(236, 248, 255), Gums = C(40, 70, 150), MouthDark = C(8, 14, 34),
		ColossusMuscle = C(64, 120, 205), ColossusFiber = C(30, 62, 140), ColossusTendon = C(205, 238, 255), ColossusEye = C(200, 250, 255), ColossusHeat = C(90, 210, 255),
		Bone = C(196, 232, 255), BoneShade = C(120, 178, 230), FounderEye = C(130, 245, 255), FounderGlow = C(110, 215, 255), FounderHair = C(20, 30, 58),
		Tint = C(214, 236, 255),
		Flesh = { C(170, 215, 240), C(140, 196, 232), C(196, 228, 248), C(120, 172, 220), C(100, 150, 205) },
	},
	AltMaterial = Enum.Material.Glass,

	Sounds = {
		Crackle = "rbxassetid://138132512434499",
		Zap = "rbxassetid://7118966167",
		Thunder = "rbxassetid://103012429197748",
		Boom = "rbxassetid://138533090376585",
		Whoosh = "rbxassetid://9120718689",
		Hit = "rbxassetid://132555084427990",
		HitHeavy = "rbxassetid://79476956608476",
		Rise = "rbxassetid://73853387149127",
		Hum = "rbxassetid://9119415101",
	},

	-- Skill 1: twin-hook grapple (cursor raycast within Range, pulled at PullSpeed by a LinearVelocity). Pressed again
	-- in the air with an enemy within SpinRange: a spinning dash strike with both blades instead.
	Tether = {
		Cooldown = 0.35,
		Range = 150,
		HookSpeed = 650,        -- studs/s the hooks fly out before the pull starts
		PullSpeed = 125,
		UpBias = 14,            -- extra lift (studs/s) while reeling in, so arcs clear the ground
		MaxPull = 1.6,          -- seconds a pull lasts at most (Space releases early)
		ReleaseDist = 9,        -- the pull lets go this close to the anchor
		Spread = 2.4,           -- the two hooks land this far either side of the cursor point
		SpinRange = 45,
		SpinCooldown = 3,
		SpinSpeed = 175,
		SpinTime = 0.55,
		SpinReach = 9,          -- the strike lands when the dash gets this close
		SpinDamage = 48,
		SpinImpulse = 210,
		SpinUpBias = 0.45,
		SpinRagdoll = 3.5,
	},

	-- Skill 2: the 15-metre form. Lightning, a steam explosion, the rig grows 4x and a muscular giant is welded over it.
	-- M1 punches, the key again leaps and hammers the ground. Super-armour: no knockback / ragdoll while it stands.
	Warrior = {
		Cooldown = 30,          -- counted from when the form ends
		GatherTime = 1.1,
		GrowTime = 0.9,
		Scale = 4,
		Duration = 15, -- 2026-11-11: was 30 ("half")
		SpeedMul = 1.4,         -- WalkSpeed = base * (1 + (Scale - 1) * 0.35) * SpeedMul
		BurstRadius = 34, BurstDamage = 40, BurstImpulse = 210,
		RoarRadius = 48, RoarDamage = 10, RoarImpulse = 130,
		PunchCooldown = 0.55, PunchWindup = 0.2, PunchRange = 26, PunchArc = 110, PunchDamage = 30, PunchImpulse = 210,
		PunchReach = 3.1,       -- the fist lands this x scale ahead of the root (FK of the client's punch pose)
		-- the camera while it stands, in multiples of the giant's height: focus height, default / closest / furthest zoom
		Camera = { Focus = 0.86, Zoom = 1.45, MinZoom = 0.8, MaxZoom = 3.2, Side = 0.14 },
		SlamCooldown = 6, SlamAir = 0.8, SlamRadius = 40, SlamDamage = 55, SlamImpulse = 250,
		TemplateName = "WarriorTemplate", -- optional Model in ServerStorage: replaces the built-in body (welded to LowerTorso)
	},

	-- Skill 3: the 60-metre form. Golden lightning, a thermal blast that levels everything within BlastRadius, the rig
	-- grows 14x. While it stands, a steam field scalds and repels everything within SteamRadius.
	Colossus = {
		Cooldown = 45,
		GatherTime = 1.5,
		GrowTime = 2.4,
		Scale = 14,
		Duration = 12.5, -- 2026-11-11: was 25 ("half")
		WalkSpeed = 30,
		BlastRadius = 60, BlastDamage = 85, BlastImpulse = 300,
		SteamRadius = 30, SteamTick = 0.4, SteamDamage = 5, SteamImpulse = 75,
		StompCooldown = 1.1, StompWindup = 0.45, StompRadius = 30, StompDamage = 45, StompImpulse = 230,
		BurstCooldown = 10, BurstCharge = 1.0, BurstRadius = 80, BurstDamage = 60, BurstImpulse = 290,
		TemplateName = "ColossusTemplate",
		-- 2026-11-07 POV fix: over the right shoulder (Side x height), closer (Zoom 1.75 -> 0.95 heights) and focused
		-- at the chest so the head never fills the frame; the city's towers go see-through (Invisicam) while giant
		Camera = { Focus = 0.8, Zoom = 0.95, MinZoom = 0.55, MaxZoom = 2.6, Side = 0.17 },
	},

	-- Skill 4: the skeletal colossus. Rises over the cast point and stays there; the caster's body waits hidden at its
	-- heart and the camera orbits the colossus (WASD slides it round the territory). A roar every RoarEvery seconds
	-- flattens everything within Radius; giants spawn in waves and hunt; M1 raises a bone spear at the cursor; the key
	-- again sends a wall of marching giants along the aim.
	Founder = {
		Cooldown = 120, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 70)
		GatherTime = 2.0,
		RiseTime = 3.0,
		Duration = 26,
		Radius = 100,           -- the territory / roar radius
		RiseRadius = 60, RiseDamage = 50, RiseImpulse = 220,
		RoarEvery = 5, RoarDamage = 12, RoarImpulse = 55, RoarRagdoll = 3.5,
		SpawnEvery = 3.5, SpawnCount = 2, MaxFollowers = 6, -- (server humanoids: was 3 a wave up to 10)
		FollowerScale = { 2.3, 3.6 },
		FollowerDamage = 18, FollowerImpulse = 150, FollowerHunt = 260, FollowerSpeed = 22,
		RumbleCooldown = 9, RumbleCount = 11, RumbleWidth = 130, RumbleSpeed = 60, RumbleLength = 280,
		RumbleDamage = 45, RumbleImpulse = 240,
		SpearCooldown = 0.9, SpearDelay = 0.45, SpearRange = 170, SpearRadius = 10, SpearDamage = 40, SpearImpulse = 230,
		-- the orbit camera: focus at Focus x the colossus's height, zoom Zoom x height (Min / MaxZoom x that), Pitch
		-- degrees down from behind it, a Glide-second glide in; WASD slides it PanSpeed studs/s up to PanRange out
		Camera = { Focus = 0.45, Zoom = 1.9, MinZoom = 0.45, MaxZoom = 1.8, Pitch = 38, Glide = 1.3, PanSpeed = 120, PanRange = 160 },
	},
}
