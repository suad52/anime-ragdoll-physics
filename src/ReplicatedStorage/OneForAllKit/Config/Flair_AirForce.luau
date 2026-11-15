-- Config pass: Q, DELAWARE SMASH: AIR FORCE (flair). Deep-merged over OneForAllKit.Config; only AirForce.* fields.
-- The server reads Windup / Lock / Escape from here (castAirForce); the rest are client-only
-- (OneForAllKit.Client.AirForce). Damage, range, speed and cooldown are unchanged.
return {
	AirForce = {
		Windup = 0.36, -- was 0.22. A real wind-up before the flick (clip: draw 0.07, aim 0.17, strain, cock 0.345);
		--                the server fires the bullet at this time and the clip's FLICK key sits at 0.372
		Lock = 1.15,   -- was 0.45. Busy through the whole performance: the clip reaches REST at 1.04, which lands at
		--                1.11 on screen after the 0.07 flick hit-stop (1.16 when a hit adds its 0.05), and fades out by 1.1
		Escape = 13,   -- was 10. A target fleeing the cast's Threat at 20 studs/s drifts ~10 studs in the longer
		--                wind-up + flight (0.36 + 40/260 s); the client bullet homes onto the live torso to match
		-- client-only
		RootTime = 1.15,   -- rooted from the cast (the old client hard-coded 0.40) as long as the lock: the clip's planted
		--                    legs hold full weight to ~1.0 on screen, so walking off any sooner skates the feet
		HitStop = 0.07,    -- the caster's pose hangs this long on the flick (every client)
		HitFreeze = 0.05,  -- and again when the bullet strikes
		ConvergeDist = 9,  -- studs over which the drawn bullet slides from the real fingertip onto the server line
		GateFull = 160, GateMid = 220, Gate = 250, -- other casters: everything / no veins, ghosts, dust / core only
	},
}
