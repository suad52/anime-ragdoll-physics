--!nocheck
-- ZangetsuKit.Config.Getsuga (owner: getsuga): Q, Getsuga Tensho tuning, deep-merged over the base Config by its footer.
-- Only Getsuga keys live here (Mode.Getsuga keeps the base values: Range 140, Width 20, HalfWidth 9, Damage 55,
-- Knock 170, CraterRadius 4.2).
-- FLAIR pass: the release moves 0.62 -> 0.80 (the blade is drawn up overhead and pours a sky-high reiatsu flare
-- before the cut) and the performance grows 1.42 -> 1.95 (a longer held money pose, a chiburi flick and a twirl back
-- onto the shoulder). Damage / range / cooldown / speed are unchanged.
return {
	Getsuga = {
		-- the server's release (the wave leaves the blade) = Clips.Getsuga strikeAt 0.80
		Windup = 0.80,
		-- every client freezes the clip ReleaseFreeze s at the release, which pushes its REST key from 1.80 to 1.90, so
		-- the busy lock and the root cover 1.95 / 1.94
		Lock = 1.95, RootTime = 1.94,
		ReleaseFreeze = 0.10,         -- client: the hit-stop on the release key
		EscapeMargin = 10,            -- server: a body swept at the release is still hit if it strayed this far off the corridor
		GateFull = 160, GateMid = 250, -- client: other casters' layers by camera distance (full / reduced / core only)
		WakeEvery = 4, DustEvery = 6, -- client: trench segment / wake puff spacing (studs travelled)
		SlabEvery = 8, RingEvery = 12, -- client: torn-up ground slabs / air distortion rings along the path
		PartBudget = 360,             -- client: optional layers are skipped once the cast folder holds this many parts
		Speed = 115,                  -- orchestrator (playtest): was 160 - the wave left the readable range in 0.3 s; the
		                              -- server's hit clock and the client's travel both read this
		-- client: the drawn crescent (span = payload width * SpanMul, so the mode's width 20 draws bigger)
		SpanMul = 1.85, DepthK = 0.3, Thick = 1.8,
		Lift = -0.4, -- the moon floats so its lower tip rides this far above the ground under him (< 0 drags it through)
		EchoLag = 0.07, EchoScale = 0.8, -- the trailing echo crescent
		FlareAt = 0.36, CollapseAt = 0.70, FlareHeight = 80, -- the sky-high flare off the raised blade
		TrenchWidth = 3.2,
		-- server: the open-air end detonation crater (a wall end keeps WallRadius)
		EndRadius = 5, EndRocks = 5, EndSpeed = 50,
	},
	Mode = { Getsuga = { Speed = 150, Thick = 2.2, Lift = -0.6, FlareHeight = 95, TrenchWidth = 3.8 } }, -- Speed was 210 (playtest)
}
