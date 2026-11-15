--!nocheck
-- ZangetsuKit.Config.Hollow (owner: hollow): R HOLLOW MASK numbers, deep-merged over the base Config (DESIGN 8.1).
-- Only keys that differ from / add to the base are here.
-- FLAIR pass: the mask now forms in layers (veins crawl, the dark shape congeals, the plates crack into place, the
-- stripes burn in, the eyes ignite), so the roar moves 0.80 -> 0.95; the point-blank finisher gets a 0.30 s charge at F
-- (the Getsuga forming on the blade), 2.00 -> 2.30 (Tensa 2.05 -> 2.40), and a longer hit-stop 0.12 -> 0.16; the
-- landing, the crack and the shatter shift with it and HollowLand ends in a chiburi, so Lock 3.4 -> 3.9 (Tensa 4.0).
-- Damage, range and cooldown are unchanged.
return {
	Hollow = {
		Lock = 3.9,             -- base 3.3 (build 3.4): HollowLand plays LandAt -> LandAt + 1.25, Lock covers it
		RoarAt = 0.95,          -- base 0.80
		BlitzAt = 1.20,         -- base 1.05 (6 cuts 1.20 -> 1.85)
		FinisherAt = 2.30,      -- base 2.00
		FinisherHitStop = 0.16, -- base 0.12
		WindUp = 0.30,          -- new: he reappears at F this long before the finisher and charges the blade
		LandAt = 2.64,          -- HollowLand starts here (its 0.55 shatter key = ShatterAt); build 2.30
		CrackAt = 2.74,         -- base 2.40
		ShatterAt = 3.19,       -- base 2.85
		MaxDY = 18,             -- victim search: |torso Y - his Y| at most this
		StunVictim = 0.5,       -- new: the victim's AI is paused from the cast until FinisherAt + this (frozen in terror)
		RoarRocks = 8, RoarRockRadius = 8, RoarRockUp = 30,          -- new: pebbles hop off the ground at the roar
		FinisherCrater = 4.4, FinisherRocks = 10, FinisherRockSpeed = 70, -- build 4 / 6 / 60 (a terrain crater wider than ~4.4 reaches F, where he lands)
		Flair = {
			Full = 160, Reduced = 250,   -- remote casters: full layers / reduced / core only (camera distance)
			PartBudget = 360, HeroCap = 400, -- optional layers stop at PartBudget, hero layers at HeroCap
			CrawlFrom = 0.06, VeinStagger = 0.035, VeinDraw = 0.20, -- black-red veins crawl over his face
			FilmAt = 0.22, FilmIn = 0.16,                           -- the mask's shape congeals in dark reiatsu
			MaskFormAt = 0.36, MaskStagger = 0.035, MaskFly = 0.14, -- the bone plates crack into place (last ~0.75)
			StripesAt = 0.76, StripeDraw = 0.10,                    -- the red stripes burn in, top to bottom
			EyesAt = 0.86, InhaleAt = 0.80,
			SwirlFrom = 0.10, SwirlTo = 0.82,
			ShotLead = 0.08, ShotRadius = 15, ShotRadiusEnd = 12.5, ShotHeight = 5, ShotSweep = 70,
			WaveTime = 0.25,             -- the finisher crescent covers its range in this long
			BurnLife = 1.7,              -- the shattered mask's pieces drift and burn away in this long
			ChiburiAt = 0.95,            -- HollowLand's chiburi flick (seconds into the clip)
		},
	},
	Mode = {
		Hollow = {
			Slashes = 8, SlashEvery = 0.11, FinisherAt = 2.40, FinisherDamage = 38, FinisherRange = 60,
			LandAt = 2.74, CrackAt = 2.84, ShatterAt = 3.29, Lock = 4.0,
		},
	},
}
