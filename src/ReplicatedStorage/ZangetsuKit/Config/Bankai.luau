--!nocheck
-- ZangetsuKit.Config child "Bankai" (owner bankai): deep-merged over the base Config. Owns `Bankai` and `Mode` (except
-- Mode.M1 / Mode.Getsuga / Mode.Shunpo / Mode.Hollow, which their move owners write).
-- FLAIR PASS: the transformation is longer (+17%) so the black-red tornado has room to build before the eruption and
-- the dust-cloud reveal gets a held money pose and a chiburi flick. Damage, range, cooldown and the mode are unchanged.
--   KaiAt 0.55 -> 0.62, EruptAt 1.10 -> 1.18, FormAt 1.30 -> 1.42, RevealAt 1.85 -> 2.15, ModeAt 2.40 -> 2.75,
--   Lock 2.70 -> 3.15, ThreatTime 2.5 -> 3.0 (the dummies keep fleeing for the whole performance)
-- The caster's cinematic is two windows (each <= 1.2 s): 0.12 -> 1.32 (BAN / KAI / the eruption, cuts at 0.62 and
-- 0.98) and the reveal 2.06 -> 2.76.
return {
	Bankai = {
		Lock = 3.15,
		KaiAt = 0.62, EruptAt = 1.18, FormAt = 1.42, RevealAt = 2.15, ModeAt = 2.75,
		ThreatTime = 3.0,
		-- the caster's cinematic (Client.Bankai): ShotEnd is still sent in BankaiCast as `shotEnd`
		ShotStart = 0.12, ShotEnd = 1.32, ShotCuts = { 0.62, 0.98 },
		RevealShot = { 2.06, 2.76 },
		-- remote casters: full layers within Full, reduced within Reduced, beyond that the column, its crown, the dome,
		-- one ring and the sounds; Grade = the reddened sky reaches cameras this close
		Gate = { Full = 160, Reduced = 250, Shake = 200, Grade = 250 },
		-- the eruption's camera-facing rings and body blooms (no white-outs: DESIGN §11)
		NearRingFrom = 40, -- a camera this close sees the vertical rings thinner (transparency >= 0.7)
		FullBlooms = 2,    -- bodies within 30 studs of the lens that bloom full size; the rest bloom small
		PillarNear = 18,   -- radius + 11: Shared's localFade distance (the column is drawn >= 0.55 transparent)
		Budget = 340,      -- the part governor: optional layers stop while the cast folder holds more parts than this
		-- the dome shockwave racing across the ground (two ForceField shells + a Neon wavefront at their foot)
		Dome = { Radius = 46, Radius2 = 34, Time = 0.8 },
	},
	Mode = {
		ExitRoot = 0.5, -- 0.35 -> 0.5: he stands for the blade shattering and the cleaver reforming
		-- Tensa Zangetsu's look on every character in the mode (Client.Bankai __update, DESIGN §9.M)
		FX = {
			AuraStand = 14, AuraRun = 44, RunSpeed = 18,        -- aura rate standing -> at a run (studs/s)
			GhostEvery = 0.22, GhostAlpha = 0.55, GhostLife = 0.3, GhostMax = 4, GhostGate = 120,
			HighlightGate = 140, EyeGate = 60, FootGate = 100, BladeK = 0.35,
			FlairGate = 120,                                     -- shoulder flames, burning coat tails, bleeding blade
			CoatGate = 100,                                      -- the coat tails sway / stream back at a run
			ArcGate = 80,                                        -- crimson arcs crawling over the body
			LateAt = 3,                                          -- the last seconds: everything sputters
			ExitBurn = 0.45,                                     -- the coat burns away from the hem up over this long
			IgniteWindow = 1.5,                                  -- a mode seen within this long of its start ignites
		},
	},
}
