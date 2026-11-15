-- Config pass "Flair_Blackwhip": R, BLACKWHIP -> ST. LOUIS SMASH, the flair cut (deep-merged over OneForAllKit.Config;
-- see its footer). A longer performance: a real gather before the lash, a longer haul (the bodies hang on the whips at
-- the gather point while he hops into a mid-air spin), the roundhouse lands later and hangs a beat longer, and the
-- lock covers the held extension, the landing and the rise. Damage, range, cone, targets, pull speeds, fling and
-- cooldown are unchanged. OneForAllServer reads LashAt / PullUntil / KickAt / HitStop / Lock straight from here;
-- Clips.Blackwhip (pass Flair_Blackwhip) and Client.Blackwhip key their beats off the same numbers.
return {
	Blackwhip = {
		LashAt = 0.24,     -- was 0.14: the tendrils leave after a 0.24 s gather (latch = 0.24 + d/220, at most ~0.46)
		PullUntil = 0.92,  -- was 0.62: the haul (the reel holds the bodies at their slots once they arrive)
		KickAt = 0.98,     -- was 0.66: ST. LOUIS SMASH, after the hop and a full mid-air turn (clip key 0.985)
		HitStop = 0.08,    -- was 0.06: the kicked bodies hang a beat longer (server freezeBody); the pose freezes with them
		Lock = 1.8,        -- was 1.05: busy / KitLocked through the held extension, the landing and the rise (the clip's
		                   -- RISE key 1.70 lands at 1.78 cast time once the 0.08 hit-stop has frozen it)
		-- client-only visual timing (OneForAllKit.Client.Blackwhip); the server never reads these
		Flair = {
			RootTime = 1.72,   -- clip time the local caster stays rooted (was a hard-coded 1.0); a hit adds HitStop, so
			                   -- a hit roots to 1.80 = Lock, a whiff (no freeze) to 1.72
			SproutAt = 0.06,   -- the wing tendrils start creeping out of his back
			LeanAt = 0.3,      -- the caster's camera leans in for the reel
			ReelAt = 0.5,      -- the YANK (clip key 0.50)
			LoadAt = 0.665,    -- the spin wind-up (clip key 0.665); the leg starts crackling 0.04 before
			LiftAt = 0.72,     -- the hop off the left toes (clip key 0.72)
			SpinAt = { 0.79, 0.86, 0.93 }, -- the three spin afterimages (clip keys)
			LandAt = 1.46,     -- the superhero landing, in clip time (a hit lands it HitStop later)
			TailTime = 3.2,    -- the aftermath (smoke, embers, arcs, dust, rings) runs this long after the kick
		},
	},
}
