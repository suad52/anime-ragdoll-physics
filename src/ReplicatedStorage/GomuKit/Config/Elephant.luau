--!nocheck
-- GomuKit.Config.Elephant (owner: elephant): R, Gear Third ELEPHANT GUN extras, deep-merged over Config.Elephant
-- and Config.Mode.Elephant by the Config footer. The base numbers (timings, damage, blasts) live in the base module.
return {
	Elephant = {
		-- server
		EndHitRadius = 9,      -- bodies this close to the fist's end are struck too (the fist is ~7 studs across)
		GroundSkim = 9,        -- the end point craters the street when it is within this above the ground
		CasterClear = 7,       -- ... and never within this (flat) of the caster's own feet
		-- client: root motion + flair
		RootTime = 2.05,       -- the caster is rooted (facing the aim) this long from t0
		Lunge = 2.2, LungeTime = 0.16,   -- the whole body lunges into the punch at PunchAt
		Recoil = 1.5, RecoilTime = 0.24, -- and staggers back a step as the arm deflates (DeflateAt)
		CoilAt = 0.78,         -- the fist is pulled further back behind him (the windup) from here to PunchAt
		Streaks = 12,          -- whoosh streaks in the cone behind the fist on the release
		RingEvery = 9,         -- air-pressure rings along the fist's path (studs)
		DustEvery = 5,         -- the dust wall kicked up along the path (studs; only where the ground is near)
		End = 2.6,             -- every client drops the cast record after this (s)
	},
	Mode = {
		Elephant = { ArmScale = 4.4, EndHitRadius = 13 },
	},
}
