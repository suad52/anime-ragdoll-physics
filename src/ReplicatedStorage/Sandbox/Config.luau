--!nocheck
-- ReplicatedStorage.Sandbox.Config: the arsenal, the gun ladder and the spawn menu (server rules + client HUD).
return {
	SLOTS = { "fists", "grab", "bat", "axe", "katana", "sledge", "gun", "bow" }, -- (2026-11-15) + the bow (key 8)
	WEAPONS = {
		fists = { name = "POWERS", hint = "YOUR FIGHTER'S MOVES" },
		grab = { name = "GRAB", hint = "HOLD CLICK TO DRAG  -  F TO THROW" },
		bat = { name = "BAT", type = "blunt", dmg = 26, range = 7.5, cd = 0.5, wind = 0.16, knock = 34, lift = 12, rag = 1.6, hint = "BREAKS BONES" },
		axe = { name = "AXE", type = "slash", dmg = 56, range = 7.5, cd = 0.95, wind = 0.26, knock = 22, lift = 6, rag = 2, hint = "TAKES LIMBS OFF" },
		katana = { name = "KATANA", type = "slash", dmg = 40, range = 9, cd = 0.45, wind = 0.12, knock = 14, lift = 4, rag = 1.4, hint = "FAST, DEEP CUTS" },
		sledge = { name = "SLEDGEHAMMER", type = "crush", dmg = 84, range = 8, cd = 1.3, wind = 0.36, knock = 58, lift = 30, rag = 3, hint = "CRUSHES ANYTHING" },
		gun = { name = "GUN", hint = "UPGRADES WITH KILLS" },
		-- (2026-11-15, owner: "add a bow item when playing in normal mode") hold to draw, let go to shoot: a real arrow that
		-- flies on an arc (gravity) and sticks in whatever it hits. The longer the draw (up to `draw` s), the faster and harder:
		-- speed / damage run from min* at a tap to the full value. No `dmg` at the top level: that would make it a melee weapon.
		bow = { name = "BOW", hint = "HOLD TO DRAW - LET GO TO SHOOT",
			bow = { draw = 0.85, cd = 0.35, speed = 300, minSpeed = 75, dmg = 72, minDmg = 16, gravity = 60, life = 4, headMul = 1.6, stuckLife = 25, maxStuck = 80 } },
	},
	-- the gun slot upgrades itself as your all-time kills climb
	GUNS = {
		{ id = "pistol", name = "PISTOL", kills = 0, dmg = 30, cd = 0.3, spread = 1, pellets = 1, range = 400 },
		{ id = "revolver", name = "REVOLVER", kills = 10, dmg = 56, cd = 0.5, spread = 0.5, pellets = 1, range = 450 },
		-- (2026-11-14) SMG spread 3 -> 1 and minigun 3.4 -> 2: at 3 degrees most rounds missed a body 60 studs out
		{ id = "smg", name = "SMG", kills = 30, dmg = 18, cd = 0.075, spread = 1, pellets = 1, range = 300, auto = true },
		{ id = "shotgun", name = "SHOTGUN", kills = 60, dmg = 17, cd = 0.8, spread = 6.5, pellets = 8, range = 120 },
		{ id = "rifle", name = "ASSAULT RIFLE", kills = 120, dmg = 34, cd = 0.1, spread = 1.5, pellets = 1, range = 500, auto = true },
		{ id = "sniper", name = "SNIPER", kills = 220, dmg = 150, cd = 1.2, spread = 0.05, pellets = 1, range = 900 },
		{ id = "minigun", name = "MINIGUN", kills = 400, dmg = 22, cd = 0.045, spread = 2, pellets = 1, range = 350, auto = true },
		{ id = "launcher", name = "ROCKET LAUNCHER", kills = 700, dmg = 120, cd = 1.4, spread = 0.3, pellets = 1, range = 500, explosive = 15 },
	},
	-- (2026-11-14) how much blood (ServerScriptService.Sandbox.Gore). Amount scales the drops that land, the scraps and
	-- the drips (0 = wounds, stumps and puddles only; 1 = as tuned). The rest are caps on what is in the world at once.
	-- Roblox: realistic heavy blood and dismemberment need the RESTRICTED maturity label (age-verified adults only).
	GORE = { Amount = 1, Splats = 220, Pools = 90, Gibs = 36, Life = 90, Range = 150 }, -- Range: blood is only drawn this near a player
	SPAWN = {
		{ id = "dummy", name = "DUMMY", cap = 8, hint = "A FRESH BODY" },
		{ id = "gascan", name = "GAS CAN", cap = 12, hint = "EXPLODES WHEN HIT" },
		{ id = "barrel", name = "FUEL DRUM", cap = 6, hint = "A MUCH BIGGER BANG" },
		{ id = "crate", name = "CRATE", cap = 10, hint = "SOMETHING TO THROW" },
	},
}
