--!nocheck
-- GomuKit.Config.Rocket (owner: rocket): E - Gum-Gum ROCKET extras, deep-merged over Config.Rocket and
-- Config.Mode.Rocket by the Config footer. The base numbers (Range, Windup, Tension, Speed, Slam*, Blast*, Crater*,
-- Tolerance ...) live in the base Config; this child only ADDS the knobs Moves.Rocket / Client.Rocket read.
return {
	Rocket = {
		-- server (GomuServer.Moves.Rocket)
		ArriveGrace = 0.35,   -- the server waits up to this long past the planned arrival for the replicated root to get there
		PathKeepOut = 0.6,    -- bodies within SlamRadius * this of the arrival are left for the slam (no sideways path hit)
		PathCorridor = 4,     -- a path body must also lie within PathRadius + this of the PLANNED from -> to line
		SlamFarMul = 0.6,     -- the slam's edge: damage x this ...
		SlamFarFling = 0.55,  -- ... and fling x this
		CraterAhead = 1.5,    -- ground slams: the GroundFX crater's near edge sits this far in front of his feet (never under them)
		ThreatPad = 6,        -- NPCs within SlamRadius + this of the anchor flinch while he winds up
		-- client (GomuKit.Client.Rocket)
		GripSpread = 1.2,     -- the two fists grip the anchor this far either side of it
		FistScale = 1.35,
		ExitSpeed = 30,       -- velocity handed back at the arrival when the anchor was in the air
		LeanFov = 12,         -- the caster's FOV kick through the flight
		GhostEvery = 0.035, GhostAlpha = 0.45, GhostLife = 0.28, -- body afterimages through the flight
		SlamShake = 0.75,
		Recover = 0.45,       -- the caster stays rooted this long after the arrival (Rocket_Slam's landing)
	},
	Mode = {
		Rocket = { FistScale = 2.6, CraterRadius = 8, CraterRocks = 14 },
	},
}
