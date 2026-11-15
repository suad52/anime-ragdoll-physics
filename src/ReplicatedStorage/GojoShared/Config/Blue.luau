-- Lapse Blue (hold Q): telekinetic grab-and-throw for ragdolls
return {
	Range = 112,         -- 2026-11-11: was 150 ("cut it into 3/4");          -- max distance from the caster to grab something
	HoldDistance = 17,    -- the body floats this far along the camera look from the caster
	HoldHeight = 4,       -- and this high above the caster's root
	MaxHoldRange = 70,    -- server clamp of the hold point around the caster
	ThrowSpeed = 165,     -- release velocity along the camera look
	RagdollTime = 3,      -- get-up delay after a throw (if it survives the landing)
	MaxHold = 2.5,        -- (2026-11-10, "only held for 2-3 seconds before they're auto thrown"; was a 15 s drop) the hold
	                      -- runs out after this many seconds and the body is THROWN (CombatService.autoThrowDir)
	Cooldown = 6,         -- (2026-11-10) counted from the RELEASE, x the non-ult multiplier (2) = 12 s (was 0.5, then 4 = 8 s:
	                      -- "add a cooldown to Gojo's blue", then "increase the cooldown")
	Responsiveness = 40,  -- AlignPosition tuning
	MaxVelocity = 260,
	MaxForce = 1e6,
}
