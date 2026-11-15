-- Flair pass: Full Cowl passive, Air Step and the Full Cowl 100% mode - VISUAL knobs only (OneForAllKit.Config
-- child, deep-merged over the config). No timings, multipliers, cooldowns or air-step physics live here.
return {
	Passive = {
		ArcEvery = 0.16, -- idle crawl cadence (unchanged); FX.ArcEveryFast is the cadence at full speed
		FX = {
			FullSpeed = 22,                       -- horizontal studs/s at which Full Cowl reads at full intensity
			ArcEveryFast = 0.07, LegArcAt = 0.55, -- above this intensity a third of the arcs run down the legs
			LightBase = 0.35, LightFast = 1.6, LightRange = 7, LightRangeFast = 12, -- the chest glow
			CrackleRate = 2, CrackleRateFast = 16, CrackleGate = 120,               -- sparks crawling over the chest
			TrailSpeed = 10,                      -- foot trails on above this speed
			TorsoTrailAt = 0.75,                  -- a green smear off the chest (other players only) above this
			StreakAt = 0.7, StreakEvery = 0.14, StreakGate = 120, -- wind streaks peeling off the shoulders
			PrintSpeed = 8, PrintGap = 0.13, PrintGate = 120,     -- lightning footprints (cracked ground in mode)
			EyeAt = 0.55, EyeGate = 90,           -- green eye trails at a sprint (the mode has its own eyes)
			SurgeEvery = { 1.4, 2.6 }, SurgeGate = 80, -- idle: One For All surges down an arm now and then
		},
		AirStepFX = {
			RingTo = 12, DiscTo = 8, HeavyGate = 90, TrailSecs = 0.5,
			FlipClip = "AirStep", SpinClip = "AirStepSpin", -- the second step of the mode corkscrews
		},
	},
	Mode = {
		FX = {
			Highlight = true, HighlightGate = 140, -- a crimson rim round the whole body
			HazeRate = 14, HazeRateLocal = 8,      -- the red heat haze (thinner on your own body: it sits mid-screen)
			CrimsonArcEvery = 0.11, ForkEvery = { 0.3, 0.55 }, SparkEvery = 0.12, -- (each spark burst is a 0.8 s emitter host)
			SteamBurstEvery = { 1.4, 2.4 }, TorsoSteam = 3,
			BeatPeriod = 1.05, BeatPeriodLate = 0.6, LateAt = 2, -- the heartbeat (faster in the last 2 s)
			VignetteBase = 0.06, VignetteBeat = 0.08,            -- caster edge vignette (max 0.14 + 0.03 late)
			IgniteWindow = 1.5,                     -- a mode seen within 1.5 s of its start ignites with a burst
			HumVolume = 0.12, HumGate = 70,         -- a low looping crackle near the body
		},
	},
}
