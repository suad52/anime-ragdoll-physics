--!nocheck
-- OneForAllKit.Config pass "Flair_OFA": G, ONE FOR ALL 1,000,000% made longer and grander (only OFA.* fields).
-- The server reads WhipAt / SmashAt / QuakeDelay / ModeAt / Lock / HitStop from here; LeapAt / LeapTime / HangUntil /
-- Charge ride the OFACast payload to every client. Damage, ranges, fling and cooldown are unchanged.
--   old: whip 0.50, leap 1.10 (0.30), smash 1.40, hang 1.62, mode 2.50, lock 2.60
--   new: whip 0.80, leap 1.85 (0.38), smash 2.35, hang 2.70, mode 3.85, lock 4.25 (+63%)
-- Camera control lost: the charge shot 0.00-1.20 + the smash cut 2.27-2.60 (each under the kit's 1.2 s cap).
-- Touchdown is ~3.70 on flat ground; OFAFlairLand reaches its power stance at ~4.08 and settles by ~4.20.
return {
	OFA = {
		Lock = 4.25, -- busy + rooted until here (covers the landing and the power stance)
		Charge = 1.2, -- the charge cinematic's length (shot A 0-0.40, B 0.40-0.80, C 0.80-1.20)
		WhipAt = 0.8,
		LeapAt = 1.85, LeapTime = 0.38, LeapForward = 6.8, -- 6.8: the uppercut lands in the middle of the ring
		SmashAt = 2.35, HangUntil = 2.7, HitStop = 0.12,
		QuakeDelay = 0.08,
		FloatGravity = 0.22, FloatMax = 1.9,
		ModeAt = 3.85,
		-- client-only beat times (cast seconds unless named as an offset)
		Flair = {
			ShotCuts = { 0.4, 0.8 }, -- shot A -> B -> C
			Shot2Lead = 0.08, Shot2Dur = 0.33, -- the smash cut: SmashAt - 0.08 for 0.33 s
			OverloadAt = 0.35, -- 100%: the veins, the fist core, the arm arcs
			Strikes = { 0.2, 0.42, 0.62, 0.95, 1.3, 1.6 }, -- sky bolts round him
			Fractures = { 0.1, 0.55, 1.5 }, -- the ground cracking in rings under him
			Inhale = 0.13, -- the fist draws the air in, SmashAt - 0.13
			ColumnDelay = 0.09, ColumnSpeed = 430, ColumnHold = 0.55, ColumnFade = 1.0,
			TearFallback = 0.55, ShaftsDelay = 0.65, LeanDelay = 0.25, -- after SmashAt
			RainFrom = 0.6, RainUntil = 2.15, -- debris raining back, after SmashAt
			Residual = { 0.95, 1.65 }, -- slow rings over the crater, after SmashAt
			DissolveAfterMode = 0.15, -- the sky clears (its last hosts go 4.5 s later, ~8.5)
			FinishAt = 8.2,
			TendrilSegs = 5, -- a latched whip is taut, so 5 segments read as smooth as 7
			TendrilCrackle = 2, -- only the first 2 whips run Shared's crackle bolts (the ring hum arcs every body)
			VeinsPerLimb = 2, -- crimson veins per arm segment (Shared's default is 4 on the local character)
		},
	},
}
