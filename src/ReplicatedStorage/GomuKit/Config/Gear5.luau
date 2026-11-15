--!nocheck
-- GomuKit.Config pass "Gear5" (owner gear5): the extra knobs of G - GEAR FIFTH, BAJRANG GUN and the mode's look.
-- Deep-merged over the base Config by its footer (the base already holds every number the CONTRACT lists; this file
-- only ADDS keys the gear5 code reads, so the base numbers stay the source of truth).
local C = Color3.fromRGB

return {
	Gear5 = {
		-- server: the burst never cuts a street crater under his own feet (CONTRACT §0.7): the centre WorldBlast is raised
		-- above the crater threshold, and the building damage round him is a ring of outward BreakBlasts + GroundFX craters
		RingBlasts = { r = 18, n = 6, radius = 12, speed = 140 },
		RingCraters = { r = 14, n = 8, size = 3, rocks = 2, speed = 60, delay = 0.05 },
		-- client: the awakening's orbit shot (ShotEnd <= 1.2 s), comic laugh letters, burst clouds
		ShotDist = 11, ShotHeight = 2.2, ShotSweep = 110, -- studs in front of his face, lens height, degrees swept
		LaughLetters = 7, BurstClouds = 16,
		-- client: the mode's look (every character with Gear5Until in the future)
		FullDist = 160, LiteDist = 260,  -- aura / scarf / bounce / trails within FullDist; white hair + outline to LiteDist
		OutlineFill = 0.88,              -- Highlight FillTransparency (the white cartoon outline is the OutlineColor)
		ScarfPuffs = 9,                  -- cloud puffs round his shoulders (the last 3 stream behind him)
		BounceSpeed = 2.5,               -- below this flat speed (and no move input) the idle bounce overlay plays
		LandBoing = 14,                  -- a landing faster than this (studs/s down) squashes him (the passive takes > BoingFall)
		TrailSpeed = 30,                 -- moving faster than this: whoosh trails on every limb
	},
	Bajrang = {
		MinFlat = 22,       -- server: the impact point is pushed at least this far from him (flat), crater off his feet
		AvoidRadius = 14,   -- server: ring blasts / ring craters within this of him (flat) are skipped
		HopUp = 7, HopTime = 0.3, Float = 0.12, -- client: the hop (ctx.move up) then a slow fall (ctx.float gravity x)
		CloudPuffs = 18,    -- the cloud bank that gathers above the target
		ArmScale = 1.7, ArmFist = 2.6, -- his own stretched arm shooting up into the clouds
	},
	Palette = {
		Gear5Shadow = C(18, 14, 30),  -- the falling fist's shadow on the ground
		Gear5Crater = C(255, 176, 70), -- the glowing crater floor after the impact
	},
}
