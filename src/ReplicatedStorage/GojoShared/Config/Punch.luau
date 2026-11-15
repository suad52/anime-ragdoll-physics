-- M1 punch combo tuning (read-only for builders; orchestrator owns this file)
return {
	ComboLength = 5, -- 2026-11-07: five-hit strings mixing punches and kicks (PunchStyles), hit 5 is the finisher
	SwingInterval = 0.32,   -- min seconds between swings
	ComboResetTime = 1.1,   -- combo restarts at 1 if no swing for this long
	FinalCooldown = 0.9,    -- extra lockout after the 4th hit
	HitDelay = 0.12,        -- hit resolves this long after the swing starts
	HitDelays = { 0.12, 0.12, 0.15, 0.15, 0.2 }, -- per combo hit (kicks and the finisher land later in their clips)
	-- the finisher changes with what you are doing on hit 5 (client sends it, server only accepts these):
	-- hold SPACE = "launch" (a rising kick sends them straight up for an air follow-up), in the air = "slam" (an
	-- axe kick spikes them into the ground with a crater), otherwise the normal blast (FinalLaunch)
	Finishers = {
		launch = { launch = Vector2.new(8, 92), damage = 18 },
		slam = { launch = Vector2.new(26, -80), damage = 24, crater = 9 },
	},
	Range = 6,              -- hitbox centre distance in front of the HRP
	HitboxSize = Vector3.new(5, 6, 7),
	Damage = 10,
	FinalDamage = 20,
	Knockback = 6,          -- studs/s push on hits 1-4 (small: the attacker is planted mid-string, so a big push
	                        -- used to carry the target out of reach before the finisher)
	StunTime = 0.45,        -- NPC AI pause on hits 1-3
	FinalLaunch = Vector2.new(70, 38), -- X = horizontal speed along aim, Y = upward speed on hit 4
	RagdollTime = 2.6,      -- get-up delay after hit 4
	CorpseJuggle = Vector2.new(30, 30),
}
