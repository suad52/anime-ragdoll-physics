-- Fox Sage kit tuning (original character: spiral orb, wind shuriken, nature-sage mode, nine-tailed fox beast)
return {
	DefaultWalkSpeed = 16,
	DefaultJumpHeight = 7.2,
	MinPitch = -40,
	MaxPitch = 35,

	-- Q: Spiral Orb - form a spinning orb in the palm, then dash and drive it into the first body you meet
	Orb = {
		Cooldown = 4,
		ChargeTime = 0.5,
		DashTime = 0.34,
		DashSpeed = 95,
		HitRadius = 5.5,
		Damage = 35,
		Power = 175,        -- launch speed of the body you hit
		Up = 45,
		Spin = 30,
		SplashRadius = 11,  -- bystanders get blown out too
		SplashPower = 95,
		RagdollTime = 3,
	},

	-- E: Spiral Shuriken - charge a whirling wind orb overhead and throw it; it swells into a blade storm that
	-- traps everything inside, then pops and blasts it all out
	Shuriken = {
		Cooldown = 9,
		ChargeTime = 1.0,
		Speed = 115,
		Range = 170,
		ProjectileRadius = 3,
		BurstRadius = 20,
		HoldTime = 1.2,
		Damage = 60,         -- spread over the hold, plus the pop
		Power = 215,
		UpBias = 0.55,
		RagdollTime = 4,
	},

	-- R: Sage Mode - meditate briefly to draw in nature energy; everything hits harder and bigger while it lasts
	Sage = {
		TransformTime = 1.6,
		Duration = 35,
		Cooldown = 20,       -- counted from when it ends
		WalkSpeed = 24,
		JumpHeight = 12,
		Scale = 1.6,         -- radius / orb size multiplier
		PowerMul = 1.35,
		DamageMul = 1.4,
	},

	-- F: Nine-Tailed Fox - become a giant fox beast for a while
	Beast = {
		TransformTime = 1.8,
		Duration = 25,
		Cooldown = 120,       -- counted from when it ends [2026-11-10: was 45, ults ~2 min]
		WalkSpeed = 34,
		JumpHeight = 20,
		StompRadius = 11,
		StompPower = 75,
		StompDamage = 5,
		Swipe = { Cooldown = 0.75, Windup = 0.18, Reach = 16, Radius = 15, Damage = 30, Power = 165, Up = 70 },
		Roar = { Cooldown = 5, Windup = 0.35, Radius = 45, Damage = 15, Power = 175, UpBias = 0.5 },
		Bomb = { Cooldown = 7, ChargeTime = 1.1, Speed = 150, Range = 230, ProjectileRadius = 5, Radius = 48, Damage = 90, Power = 260, UpBias = 0.5 },
	},
}
