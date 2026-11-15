--!nocheck
-- GomuKit.Config.Gatling (owner: gatling): Q, Gum-Gum GATLING overrides, deep-merged over Config.Gatling / Mode.Gatling
-- by the Config footer. The base numbers (Cooldown, Windup, Duration, Tick, Range, HalfAngle, damage ...) stay in the
-- base module; this child only ADDS the knobs the server move (Moves.Gatling) and the client (Client.Gatling) read.
return {
	Gatling = {
		-- server
		ReactPower = 0.55,                  -- HitReact.mark power of each storm tick on a standing body
		JuggleVel = Vector2.new(14, 10),    -- a ragdolled body / corpse in the storm: flat x along the dir, up y
		JuggleRag = 1.5,
		HitEvery = 0.15,                    -- GatlingHit throttle per body (s)
		ChipPitch = { -5, 20 },             -- the facade-chip rays' pitch range (deg; negative = into the street)
		ChestUp = 1.2,                      -- the cone's origin above the HRP
		ThreatRadius = 18,
		FinalBlastRadius = 8, FinalBreakSpeed = 130, -- the heavy last fist's end point (>= 6: a hole in the wall)
		FinalRangeBonus = 2, FinalHalfBonus = 4,      -- the heavy fist's cone is a little longer and wider
		-- client
		JabEvery = 0.045,                   -- one stretched jab, alternating L / R (lite tier: x2)
		JabOut = 0.032, JabHold = 0.008, JabBack = 0.04,
		JabMin = 6,                         -- studs: the closest a jab lands
		JabPitch = { -8, 14 },
		HomeChance = 0.55,                  -- this share of jabs homes on bodies the server reported hit
		HeavyOut = 0.1, HeavyHold = 0.12, HeavyBack = 0.24, HeavyScale = 1.9, HeavyArm = 1.25,
		SitBack = 0.6,                      -- local root motion: the windup sits back ...
		SlideBack = 1.4,                    -- ... the recoil of the storm slides him back ...
		Lunge = 2.2,                        -- ... and the heavy fist lunges him forward (wall ray 1.6, 3.4 short of a body)
		RingEvery = 0.12, WhooshEvery = 0.05, DustEvery = 0.1, ShakeEvery = 0.1,
	},
	Mode = {
		Gatling = { FinalBlastRadius = 11, Lunge = 3, HeavyScale = 1.6 },
	},
}
