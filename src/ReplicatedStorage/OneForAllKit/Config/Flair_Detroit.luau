-- Config pass "Flair_Detroit": DETROIT SMASH, the flair cut (deep-merged over OneForAllKit.Config; see its footer).
-- A longer performance: a real charge before the punch, a heavier hit-stop on the point-blank body, the pose held at
-- the money frame on every client, and a lock that covers the held arm and the recovery. Damage, range, cone,
-- cooldown and fling speeds are unchanged. Mode.Detroit (Delaware Detroit Smash) inherits these timings.
return {
	Detroit = {
		Charge = 0.66,      -- was 0.42: the punch. The server's hit clock and station clock both key off it, and
		                    -- Clips.Detroit (pass Flair_Detroit) puts its STRIKE key exactly here (strikeAt = 0.66)
		Lock = 1.6,         -- was 1.0: busy / KitLocked until the held arm and the recovery are done
		HitStop = 0.1,      -- was 0.07: the point-blank body hangs a beat longer (server freezeBody)
		LungeDist = 3, LungeTime = 0.1, -- was 2.5 / 0.09: the caster's wall-clamped lunge behind the fist
		-- client-only visual timing (OneForAllKit.Client.Detroit)
		FreezeTime = 0.14,  -- the pose hit-stop every client holds at the punch (the clip runs 0.14 late after it)
		RootTime = 1.55,    -- the local caster stays rooted this long from the cast (was a hard-coded 0.95)
		TailTime = 3.2,     -- the aftermath (steam, embers, lingering arcs, trench smoke) lasts this long after the punch
	},
}
