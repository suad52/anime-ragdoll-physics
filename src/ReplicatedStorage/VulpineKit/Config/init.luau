-- VulpineKit config: every tunable number, colour, key and asset id for the four-skill kit lives here so the kit
-- can be re-skinned without touching code. Colours are defaults for an original "spirit fox" look.
local C = Color3.fromRGB

return {
	KitId = "Vulpine",           -- value of the player's "Kit" attribute while this kit is equipped
	TargetTag = "RagdollNPC",     -- CollectionService tag of ragdollable NPC bodies
	AffectPlayers = true,         -- other players are knocked back too (their own client applies the impulse)
	PlayerRagdollMax = 3,         -- seconds a knocked-back player tumbles at most

	Keys = { Sphere = Enum.KeyCode.Q, Disc = Enum.KeyCode.E, Power = Enum.KeyCode.R, Morph = Enum.KeyCode.F },

	-- names shown on the ability bar only (code stays generic). Private-test names: swap for original names
	-- before publishing.
	Labels = { Sphere = "RASENGAN", Disc = "RASENSHURIKEN", Power = "SAGE MODE", Morph = "KURAMA", Bomb = "BEAST BOMB", Claw = "CLAW", Release = "RELEASE" },

	-- the big move-name callout and the ability button for each skill: small kanji line above the name, the
	-- name's gradient (c0 top -> c1 bottom), the button glyph and the hint under the button
	Callouts = {
		Sphere = { kanji = "螺旋", glyph = "螺", hint = "dash", c0 = C(235, 250, 255), c1 = C(70, 160, 255) },
		Disc = { kanji = "風遁", glyph = "風", hint = "steer: cursor", c0 = C(240, 252, 255), c1 = C(90, 200, 230) },
		Power = { kanji = "仙術", glyph = "仙", hint = "toggle", c0 = C(255, 244, 200), c1 = C(255, 140, 40) },
		Morph = { kanji = "九尾", glyph = "狐", hint = "transform", sub = "NINE-TAILS FORM", subForm = "F: BOMB   X: RELEASE", c0 = C(255, 236, 190), c1 = C(235, 70, 25) },
		Bomb = { kanji = "尾獣玉", glyph = "玉", hint = "", sub = "TAILED BEAST BOMB", c0 = C(255, 244, 210), c1 = C(255, 70, 20) },
		Claw = { kanji = "裂爪", glyph = "爪", hint = "", c0 = C(255, 240, 200), c1 = C(255, 110, 30) },
	},

	Palette = {
		SphereCore = C(235, 250, 255), SphereShell = C(70, 160, 255), SphereAura = C(150, 215, 255),
		Disc = C(215, 245, 255), DiscRim = C(110, 190, 255), Vortex = C(200, 240, 255),
		PowerEye = C(255, 196, 64), PowerEmber = C(255, 170, 60), PowerAura = C(255, 225, 140),
		BeastBody = C(235, 78, 12), BeastAccent = C(190, 22, 18), BeastCore = C(255, 225, 170),
		BeastBone = C(255, 214, 150), BeastEye = C(255, 230, 140), Shockwave = C(255, 140, 60),
	},

	-- Skill 1: Energy Sphere (charge in the palm, then thrust forward)
	Sphere = {
		Cooldown = 4,
		AnchorTime = 0.55,     -- caster is anchored while the sphere grows
		SphereSize = 2.4,      -- final diameter (studs)
		LaunchDistance = 20,   -- studs travelled by the thrust
		LaunchTime = 0.25,
		HitRadius = 6,         -- enemy root parts this close to the caster's front are struck
		Damage = 30,           -- at the centre, falling off across HitRadius
		Impulse = 165,         -- speed (studs/s) given to the main target
		UpImpulse = 45,
		RagdollTime = 3,
	},

	-- Skill 2: Expanding Vortex Disc (channel, throw, swell into a vortex, detonate)
	Disc = {
		Cooldown = 9,
		ChannelTime = 1.5,
		DiscSize = 5,          -- diameter while held / in flight
		ExpandScale = 3,       -- visual swell on impact
		Speed = 115,           -- AssemblyLinearVelocity of the thrown disc
		Range = 180,           -- studs of flight (curving included) before it bursts on its own
		TurnRate = 200,        -- degrees per second the thrown disc can curve toward the cursor
		SteerInterval = 0.08,  -- how often the caster's client sends the cursor point while it flies
		VortexRadius = 22,
		VortexTime = 2,
		PullSpeed = 40,        -- inward drag (studs/s) applied every tick
		SwirlSpeed = 26,
		Tick = 0.1,
		Damage = 55,           -- spread over the vortex, plus the detonation
		ExplosionImpulse = 215,
		ExplosionUpBias = 0.55,
		RagdollTime = 4,
	},

	-- Skill 3: Enhanced Power Mode (stat + visual override)
	Power = {
		Duration = 30,
		Cooldown = 15,         -- counted from when it ends
		WalkSpeedMul = 1.6,
		JumpPowerMul = 1.5,    -- applied to JumpPower, or as the equivalent JumpHeight (x mul^2)
		KnockbackMul = 1.25,
		SenseRadius = 50,      -- enemies within this get an outline on the caster's screen
		MarkingDecal = "",     -- optional rbxassetid:// face-marking decal laid over the face
	},

	-- Skill 4: the nine-tailed fox form. F transforms; while the form stands F fires the bomb and X (or the HUD's
	-- RELEASE chip) ends it early through the normal exit (shrink back, cooldown from that moment).
	Morph = {
		Duration = 30,         -- of the beast form itself, after the cinematic entrance
		Cooldown = 45,         -- counted from when it ends (a release starts it too, no penalty)
		ReleaseKey = Enum.KeyCode.X,
		ReleaseLock = 1.3,     -- seconds after the form is up before a release is accepted (its opening bomb is in the air)
		GatherTime = 1.3,      -- the caster rises and the chakra gathers before the form bursts out
		Levitate = 4,          -- studs the caster floats up while gathering
		BurstRadius = 60,      -- the transformation burst
		BurstImpulse = 240,
		BurstDamage = 35,
		-- your own beast model: put a Model with this name in ServerStorage (PrimaryPart = its hips, facing -Z) and
		-- the morph uses it instead of the built-in construct. Joints named BeastLegFL/FR/BL/BR, BeastHead,
		-- BeastBody and Tail<i>_<k> (Motor6D) get the walk / sway / tail animation automatically.
		TemplateName = "BeastTemplate",
		Scale = 5,             -- character rig / hitbox scale while morphed (the construct is designed at 5: ~50 studs tall)
		GrowTime = 0.8,        -- seconds for the smooth scale in / out
		WalkSpeedPerScale = 0.5, -- WalkSpeed = base * Scale * this (16 * 5 * 0.5 = 40: a heavy lope)
		JumpHeightMul = 2.2,
		CameraLift = 13,       -- Humanoid.CameraOffset.Y while morphed (lifts the focus to the beast's head)
		CameraZoom = 72,       -- the camera is eased out to this distance as the beast grows
		CameraMinZoom = 42,    -- and can't be scrolled in closer than this (inside the tails) while in form
		CameraMaxZoom = 170,
		ShockRadius = 40,      -- trigger shockwave
		ShockImpulse = 190,
		ShockDamage = 20,
		StepShakeRadius = 120, -- cameras this close feel each footstep (the caster's own steps are lighter)
		StepShake = 0.5,
		StepFxRadius = 320,    -- footstep dust is only drawn for beasts this close to the camera
	},

	-- the form's signature move: a giant ball of condensed chakra spat from the beast's mouth. Fired once automatically
	-- when the transformation completes, and again on F (the key toggles nothing while in form).
	Bomb = {
		Cooldown = 10,
		ChargeTime = 1.0,      -- manual casts
		AutoChargeTime = 0.7,  -- the one fired by the transformation itself
		Size = 16,             -- ball diameter
		Speed = 200,
		Range = 260,
		SweepRadius = 9,       -- a body this close to the flight line detonates it
		BrushRadius = 15,      -- bodies this close are shoved aside as it passes
		BlastRadius = 54,
		Damage = 95,
		Impulse = 290,
		UpBias = 0.7,
		RagdollTime = 5,
	},

	-- M1 while in form: a rearing three-claw swipe that rakes the ground in front of the forepaws
	Claw = {
		Cooldown = 0.85,
		Windup = 0.26,
		Range = 56,            -- from the beast's root; its nose is ~31 studs ahead at Scale 5 (was 34 at Scale 3)
		Inner = 16,            -- anything this close (under the chest) is struck whatever the angle
		Arc = 130,
		Damage = 42,
		Impulse = 215,
		FissureStart = 18,     -- the furrows start just past the forepaws...
		FissureLength = 54,    -- ...and run this far from the root
	},
}
