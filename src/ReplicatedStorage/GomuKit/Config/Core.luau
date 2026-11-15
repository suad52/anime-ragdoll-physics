--!nocheck
-- GomuKit.Config.Core (owner: core): GomuServer.Core's own knobs, deep-merged over GomuKit.Config as CFG.Core.
-- Only the Core key lives here (the hat's sizes, PlayerRagdollMax and OwnM1Kits stay in the base Config).
return {
	Core = {
		Rate = { M1 = 0.05, Aim = 0.033 }, -- per-action request limit (s); Aim = the steering stream, ~30/s cap
		RateDefault = 0.08,                -- every other action
		AimMaxAge = 0.4,                   -- S.liveAim ignores a steering packet older than this (s)
		KnockMax = 320,                    -- the fastest knockback a player victim is ever sent (studs/s)
		EvadeGrace = 0.35,                 -- after a player dodges, shoves on them are dropped this long (s)
		WatchEvery = 1,                    -- the hat watchdog's period (s)
	},
}
