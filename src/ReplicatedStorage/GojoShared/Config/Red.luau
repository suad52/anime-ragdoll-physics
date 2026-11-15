-- Reversal: Red (R) - a repulsive orb fired from the fingertip that detonates on contact and blasts everything away
return {
	Cooldown = 4,
	LaunchTime = 0.6,      -- s after cast start when the orb leaves the fingertip
	LockTime = 0.95,       -- s the caster is rooted
	Speed = 175,           -- studs/s
	Range = 150,           -- detonates at the end of its range if it hits nothing
	ProjectileRadius = 3,  -- contact radius against bodies
	OriginForward = 3,     -- launch point relative to the caster (roughly the pointing fingertip)
	OriginRight = 1.1,
	OriginUp = 1.3,
	BlastRadius = 30,
	Power = 200,           -- fling speed at the centre of the blast
	MinPower = 70,         -- fling speed at the edge
	UpBias = 0.45,         -- how much the blast lifts as well as pushes
	Damage = 45,           -- at the centre, falling off to 0 at the edge
	RagdollTime = 3,
	BreakRadiusScale = 0.7,
	BreakPower = 110,
	CraterRadius = 7,
}
