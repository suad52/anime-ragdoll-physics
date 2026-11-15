--!nocheck
-- ZangetsuKit.Config.M1 (owner sword-m1): the sword combo's extra tuning, deep-merged over the base Config.
-- Keys written here: M1 (additions + the FLAIR pass's Lock / RootExtra4), Mode.M1, Sword (geometry only).
-- FLAIR pass: swing 4 ends in a twirl over his head (Clips.M1 Slash4 0.50-0.80, on his shoulder at 0.87), so it roots
-- through the twirl (RootExtra4 0.27 -> 0.50) and its lock covers the money hold + hit-stop (Lock[4] 0.50 -> 0.55);
-- the twirl itself stays cancellable (Client.M1 drops it when another move starts). Swings 1-3 are unchanged.
return {
	M1 = {
		MoveMul = 0.45,      -- swings 1-3 do not root: the caster walks at WalkSpeed x this through the swing (DECISIONS 2)
		SlowExtra = 0.12,    -- ...for HitAt + this (+ the hit-stop), turned to face the aim
		RootExtra4 = 0.50,   -- swing 4 roots for HitAt + this (+ its 0.07 hit-stop) = 0.87: the money hold AND the twirl
		Lock = { 0.16, 0.16, 0.2, 0.55 }, -- busy per swing (a list replaces the base one wholesale; only [4] changed)
		Freeze = { 0.04, 0.04, 0.04, 0.07 }, -- the caster's clip hit-stop per swing (once per swing that hits)
		GateFull = 160, GateMid = 250,       -- remote casters: full layers / the clip only / beyond: hit sounds only
		GateRich = 120,                      -- remote casters: sheets, afterimages, the crescent burst, lifted rocks
		PartCap = 360, EmitCap = 24,         -- the per-cast governor: optional layers are skipped past these
		FinalFlingRadial = 0.6,              -- swing 4 flings each body (radial x 0.6 + aim x 0.4): a spin throws outward
		BlastRadius = 4.5,                   -- WorldBlast per swing
		RingRadius = 4, RingCount = 4, RingUp = 25, -- swing 4: GroundFX.ring under his feet
		WaveTravel = 0.12, FinalWaveTravel = 0.2,   -- mode slash waves: seconds to cover their range
		-- hit reactions (2026-11-06, the user: swings 1-3 throw the body around, only the final hit throws it away):
		-- swings 1-3 shove a standing body only a stud or so along the swing (it stays in reach) and play a
		-- GojoShared.HitReact flinch (forehand / backhand twist, chop fold); a downed body is juggled in place
		Knockback = 6,                 -- was 20 (studs/s on the HRP; only used if GojoShared.HitReact is missing)
		HitSlide = 1.1,                -- studs a standing body is slid along swings 1-3 (HitReact.slide)
		StunTime = 0.8,                -- was 0.45: outlasts the gap between swings so it never walks out of the combo
		Juggle = Vector2.new(6, 20),   -- was 30 / 32: a hop and a jerk, not a throw
	},
	Mode = {
		M1 = {
			-- explicit mode numbers are final (DECISIONS 9), so these are DESIGN's 6 x1.25 and 14 x1.25
			WaveDamage = 7.5, FinalWaveDamage = 17.5, FinalWaveUp = 30,
		},
	},
	Sword = {
		-- the pommel moved out of the fist (s -0.15 -> -0.62 / -0.64) so the hilt shows on both sides of the hand
		Shikai = { Pommel = -0.62 },
		Bankai = { Pommel = -0.64 },
	},
}
