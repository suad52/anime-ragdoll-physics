-- TempestKit config: every tunable number, colour, key, label and asset slot for the lightning / spectral-guardian
-- kit (a hand-lightning dash, a lightning dragon called down from the sky, an evasive eye mode and a spectral guardian). Visual defaults
-- are original designs; re-skin here, not in code.
local C = Color3.fromRGB

return {
	KitId = "Tempest",           -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are hit too (their own client applies knockback / stun)
	PlayerRagdollMax = 3,

	Keys = { Lance = Enum.KeyCode.Q, Pulse = Enum.KeyCode.E, Eyes = Enum.KeyCode.R, Guardian = Enum.KeyCode.G },

	-- names shown on the ability bar and in the callouts only (code stays generic). Private-test names: swap for
	-- original names before publishing.
	Labels = { Lance = "CHIDORI", Pulse = "KIRIN", Eyes = "RINNESHARINGAN", Guardian = "SUSANOO", Slash = "SLASH", Arrow = "INDRA'S ARROW", Release = "RELEASE" },

	-- callout kanji over the name, the name's gradient (c0 top -> c1 bottom), the button glyph and the hint under it
	Callouts = {
		Lance = { kanji = "雷刃", glyph = "雷", hint = "dash: cursor", c0 = C(235, 252, 255), c1 = C(60, 190, 255) },
		Pulse = { kanji = "麒麟", glyph = "麟", hint = "sky strike: cursor", c0 = C(240, 236, 255), c1 = C(130, 90, 255) },
		Eyes = { kanji = "瞳術", glyph = "瞳", hint = "auto-dodge", c0 = C(255, 225, 235), c1 = C(200, 30, 60) },
		Guardian = { kanji = "守護霊", glyph = "霊", sub = "SUSANOO", subForm = "G AGAIN: ARROW", c0 = C(240, 225, 255), c1 = C(140, 60, 255) },
		Arrow = { kanji = "雷弓", glyph = "矢", sub = "LIGHTNING ARROW", c0 = C(248, 240, 255), c1 = C(150, 80, 255) },
	},

	Palette = {
		Core = C(245, 252, 255),     -- white-hot heart of every bolt
		Bolt = C(90, 200, 255),      -- hand lightning (cyan-blue)
		Deep = C(40, 110, 235),
		Pulse = C(150, 110, 255),    -- radial pulse arcs (purple-blue)
		PulseDeep = C(80, 60, 220),
		EyeRight = C(220, 25, 50),   -- eye-mode overlays
		EyeLeft = C(120, 60, 210),
		EyeTrail = C(170, 110, 255),
		Guard = C(150, 70, 255),     -- guardian shell
		GuardDeep = C(80, 30, 170),
		GuardBone = C(225, 200, 255),
		GuardEye = C(255, 215, 110),
		Blade = C(200, 150, 255),
	},

	-- (2026-11-07 perks) the alt skin "AZURE SUSANOO" (HudShared.PerkCatalog.SKINS.Tempest): every cast by a player whose
	-- Skin attribute is "Alt" draws with this palette instead (the guardian, its arrow and blade, the lance, the pulse,
	-- the eyes). Same keys as Palette; any key left out falls back to Palette.
	AltPalette = {
		Core = C(238, 250, 255),
		Bolt = C(55, 155, 255),
		Deep = C(12, 62, 205),
		Pulse = C(70, 175, 255),
		PulseDeep = C(18, 80, 215),
		EyeRight = C(220, 25, 50),
		EyeLeft = C(40, 140, 255),
		EyeTrail = C(120, 205, 255),
		Guard = C(40, 150, 255),
		GuardDeep = C(10, 52, 165),
		GuardBone = C(205, 240, 255),
		GuardEye = C(190, 250, 255),
		Blade = C(140, 220, 255),
	},

	Sounds = {
		Crackle = "rbxassetid://124871115622073",
		Zap = "rbxassetid://138132512434499",
		Thunder = "rbxassetid://168586586",
		Boom = "rbxassetid://9126050116",
		Whoosh = "rbxassetid://125132253621935",
		Hit = "rbxassetid://140277245983305",
		HitHeavy = "rbxassetid://72942854786548",
		Rise = "rbxassetid://122439012218772",
		Hum = "rbxassetid://9119415101",
	},

	-- Skill 1: lightning lance - lightning gathers in the dominant hand, then a 30-stud dash at the cursor
	Lance = {
		Cooldown = 5,
		WindUp = 0.35,         -- lightning gathers in the hand (rotation locked to the cursor)
		DashDistance = 30,
		DashTime = 0.3,
		HitRadius = 4.5,       -- swept along the dash path
		Damage = 38,
		Impulse = 200,         -- launch speed of the struck body
		UpImpulse = 55,
		RagdollTime = 3,
		GuardBreakTime = 1.5,  -- sets the target's "GuardBrokenUntil" (and clears "Blocking") for block systems
	},

	-- Skill 2: KIRIN (2026-11-08; was a radial pulse around the caster) - the caster raises a hand, storm clouds gather
	-- over the cursor point and a dragon of lightning dives out of them onto it. Everything within Radius of the landing
	-- is stunned, held, shocked and knocked down. The point is fixed at the call, so the telegraph can be dodged.
	Pulse = {
		Cooldown = 9,
		Range = 130,           -- the strike point is pulled in to this far (horizontally) from the caster
		StrikeDelay = 1.2,     -- the call -> the dragon lands
		SkyHeight = 150,       -- the storm and the dragon form this high above the strike point
		CastLock = 0.6,        -- the caster holds the call (no other skill) this long
		Radius = 18,
		StrikeDamage = 15,     -- on landing
		StunTime = 1.5,        -- WalkSpeed 0 + damage over time for this long
		AnchorTime = 0.6,      -- rig held in place, then knocked down
		Ticks = 6,
		Damage = 40,           -- total over the stun
		KnockSpeed = 110,
		UpBias = 0.6,
		RagdollTime = 3,
	},

	-- Skill 3: eye mode - the next melee hit inside the window is dodged by blinking behind the attacker
	Eyes = {
		Window = 10,
		Cooldown = 14,         -- counted from when the window ends (or the dodge fires)
		BlinkBehind = 5,       -- studs behind the attacker
		WalkSpeedMul = 1.35,
		SenseRadius = 60,      -- enemies within this get an outline on the caster's screen
		RightDecal = "",       -- optional rbxassetid:// eye art laid over each eye
		LeftDecal = "",
	},

	-- Skill 4: spectral guardian - a giant (~35 studs) spectral warrior the caster floats inside, a force shield, blade
	-- slashes on M1, arrows on G, X to release it
	Guardian = {
		Duration = 20,         -- of the guardian itself, after the cinematic entrance (2026-11-08: was 30, "reduce susanoo duration")
		Cooldown = 120,         -- counted from when it ends (a release starts the normal cooldown) [2026-11-10: was 40, ults ~2 min]
		GatherTime = 1.2,      -- the lightning storm gathers before the guardian bursts out
		SummonTime = 1.6,      -- the skeleton, then the armour, then helm, weapons and mantle take shape (client reveal)
		RiseTime = 1.4,        -- the caster is lifted into the guardian's chest over this long
		FaceCamIn = 0.55,      -- (2026-11-10) the face beat: as G is cast the caster is held still and their camera pans in to Sasuke's face over this long...
		FaceCamHold = 0.5,     -- ...holds until this fraction of SummonTime into the guardian's reveal...
		FaceCamOut = 0.7,      -- ...then hands back to the follow camera over this long (always over before the arrow is drawn)
		FaceCamFrame = 2.7,    -- head heights in view in the close-up (smaller = tighter)
		BurstRadius = 55,      -- the summoning burst
		BurstImpulse = 230,
		BurstDamage = 30,
		Scale = 1,             -- construct size multiplier (1 = ~35 studs tall)
		RootHeight = 16.5,     -- the caster's root rides this high above the ground inside it (x Scale)
		ReleaseKey = Enum.KeyCode.X, -- lets the guardian go (refused until the entrance has played out)
		FadeTime = 0.6,        -- the dissolve on release / timeout
		CameraLift = 6,        -- camera offset up while it stands (x Scale)
		CameraZoom = 46,       -- the camera is pulled back to this to frame it, then free between Min and Max
		CameraZoomMin = 30,
		CameraZoomMax = 120,
		JumpMul = 0.6,         -- jump power / height while it stands
		WalkSpeedMul = 0.9,
		ShieldRadius = 13,     -- continuous force shield
		ShieldTick = 0.35,
		ShieldDamage = 4,
		ShieldPush = 70,
		SlashCooldown = 0.9,
		SlashWindup = 0.22,
		SlashRange = 42,
		SlashArc = 140,        -- degrees swept in front
		SlashDamage = 45,
		SlashImpulse = 210,
		FissureLength = 36,    -- the ground split along the swing
		ShellMaterial = "SmoothPlastic", -- armour: translucent and lit, so it reads as a shape (outlined by the client)
		BodyTransparency = 0.45,
		BoneTransparency = 0,  -- the inner skeleton stays solid
		TemplateName = "GuardianTemplate", -- your own model in ServerStorage replaces the built-in construct
	},

	-- the guardian's signature move: a giant lightning arrow drawn on a spectral bow. One is loosed automatically at the end
	-- of the summoning, and another each time the key is pressed while the guardian stands. It pierces everything on its
	-- line, rakes a trench along the ground and detonates where it lands.
	Arrow = {
		Cooldown = 9,
		ChargeTime = 1.0,      -- manual casts
		AutoChargeTime = 0.75, -- the one loosed by the summoning itself
		Range = 170,
		Speed = 520,           -- studs/s of the visible arrow
		Width = 8,             -- bodies this close to the line are pierced
		Damage = 90,
		Impulse = 270,
		UpBias = 0.45,
		RagdollTime = 5,
		EndRadius = 38,        -- the detonation where it lands
		EndDamage = 55,
		EndImpulse = 250,
		TrenchSteps = 13,
	},
}
