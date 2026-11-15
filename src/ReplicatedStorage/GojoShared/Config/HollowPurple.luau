-- Hollow Purple tuning. Owner: Choreography judge (keep every key and its meaning).
-- Server (CombatService) reads: HoldThreshold, MinPitch, MaxPitch, Cooldown, Variants.*.{LaunchTime, LockTime,
-- Speed, Radius, Range}, OriginForward, OriginUp, Damage, ForwardFling, RadialFling, UpFling, Spin,
-- PullRadiusScale, PullLeadDistance, PullSpeed, CarveStep, CarveRadiusScale, EraseRadiusScale, BreakRadiusScale,
-- MaxDebrisPerCast, DebrisLifetime, BreakableRestoreTime, TerrainRestoreDelay, ThreatRadius.
return {
	HoldThreshold = 0.35,   -- hold E at least this long => "Incantation" variant
	MinPitch = -20,         -- degrees, aim pitch clamp
	MaxPitch = 25,
	Cooldown = 7,           -- seconds from cast accept
	Variants = {
		Quick = {
			LaunchTime = 1.8,   -- s after cast start when the orb leaves
			LockTime = 2.4,     -- s the caster is rooted
			Speed = 190,        -- studs/s
			Radius = 11,        -- orb radius in studs
			Range = 420,        -- studs travelled before it ends
		},
		Incantation = {
			LaunchTime = 4.6,
			LockTime = 5.2,
			Speed = 230,
			Radius = 18,
			Range = 620,
			ChantLines = { "Nine Ropes.", "Polarized Light.", "Crow and Declaration.", "Between Front and Back." },
		},
	},
	OriginForward = 4,      -- orb launch origin offset from the HRP along the flat aim
	OriginUp = 1.5,
	Damage = 1000,
	ForwardFling = 170,     -- studs/s along the orb direction
	RadialFling = 90,       -- studs/s away from the orb's axis line
	UpFling = 70,
	Spin = 22,              -- rad/s random spin on hit
	PullRadiusScale = 2.6,  -- pull field radius = Radius * this
	PullLeadDistance = 60,  -- pull NPCs up to this far ahead of the orb centre
	PullSpeed = 55,
	CarveStep = 6,          -- carve terrain every N studs travelled
	CarveRadiusScale = 0.9,
	EraseRadiusScale = 0.75,
	BreakRadiusScale = 1.35,
	MaxDebrisPerCast = 60,
	DebrisLifetime = 6,
	BreakableRestoreTime = 14,
	TerrainRestoreDelay = 45, -- 2026-11-07: ability damage to the ground stays noticeable (was 10); matches the city's craters
	ThreatRadius = 70,      -- NPCs within this of the caster flee while it charges
}
