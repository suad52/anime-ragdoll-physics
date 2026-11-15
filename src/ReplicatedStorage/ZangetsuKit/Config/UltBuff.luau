--!nocheck
-- ZangetsuKit.Config child "UltBuff" (2026-11-08, "make ichigo's ult stronger, it is kind of underwhelming right now").
-- Deep-merged LAST (children apply in name order, and "UltBuff" sorts after Bankai / Getsuga / Hollow / M1 / Shunpo /
-- Skin), so these numbers win over every other child. Tune Bankai's power HERE. Previous values in brackets.
-- Damage against players still goes through ServerScriptService.PvP.dmg (x0.5, at most 25% of max health a hit).
return {
	Bankai = {
		-- the eruption that opens the transformation
		Damage = 55,        -- [35]
		Radius = 36,        -- [30]
		FarMul = 0.75,      -- [0.6]  damage at the edge of the radius
		ThreatRadius = 56,  -- [50]   dummies flee from this far
	},
	Mode = {
		Time = 22,          -- [15]   seconds of Tensa Zangetsu (Bankai's cooldown is still 40 s from the cast)
		DamageMul = 1.5,    -- [1.25] every move's damage the mode doesn't set explicitly below
		DamageTakenMul = 0.75, -- [none] takes 25% less damage from players while in the mode
		CooldownMul = { Getsuga = 0.35, Shunpo = 0.3, Hollow = 0.4 }, -- [0.5 / 0.45 / 0.6]
		-- explicit mode damage numbers are final (not x DamageMul)
		M1 = { WaveDamage = 10, FinalWaveDamage = 25 },        -- [7.5 / 17.5]
		Getsuga = { Damage = 70 },                             -- [55]
		Shunpo = { Damage = 55, SecondDamage = 15 },           -- [42 / 10]
		Hollow = { FinisherDamage = 50 },                      -- [38]
	},
}
