-- Vulpine alternate colourway "CRIMSON FOX" (HudShared.PerkCatalog.SKINS.Vulpine; PERKS 2026-11-07, owner kits-A).
-- Used when the CASTER's player has Skin == "Alt" (read at cast time):
--   Palette   replaces Config.Palette for that cast on every client (same keys, plus the bomb's three balls)
--   Callouts  the ultimate's title gradient (only c0 / c1 are overridden)
--   Beast     the server recolours the nine-tailed fox construct (and its flames) through GojoShared.SkinTint:
--             Exact swaps BeastConstruct's fixed colours, Bands catch anything else (e.g. a ServerStorage template)
-- Tune freely; every key of Config.Palette must stay present.
local C = Color3.fromRGB
return {
	Name = "CRIMSON FOX",
	Palette = {
		SphereCore = C(255, 236, 240), SphereShell = C(225, 24, 56), SphereAura = C(255, 120, 140),
		Disc = C(255, 228, 232), DiscRim = C(235, 50, 80), Vortex = C(255, 165, 180),
		PowerEye = C(255, 40, 70), PowerEmber = C(230, 30, 60), PowerAura = C(255, 150, 165),
		BeastBody = C(210, 18, 52), BeastAccent = C(150, 8, 36), BeastCore = C(255, 214, 222),
		BeastBone = C(255, 214, 220), BeastEye = C(255, 226, 110), Shockwave = C(255, 60, 90),
		-- the Tailed Beast Bomb (the default look uses the fixed colours noted)
		BombCore = C(12, 0, 4), -- default (24, 5, 5)
		BombMid = C(215, 20, 55), -- default (255, 118, 22)
		BombHalo = C(255, 130, 150), -- default (255, 186, 90)
	},
	Callouts = {
		Morph = { c0 = C(255, 228, 232), c1 = C(205, 18, 50) },
		Bomb = { c0 = C(255, 232, 236), c1 = C(215, 20, 55) },
	},
	Beast = {
		Gray = 0.12,
		SatFloor = 0.3,
		Exact = {
			["236,100,30"] = C(196, 20, 48), -- fur
			["190,64,22"] = C(132, 10, 32), -- dark fur (forearms, shanks, paws)
			["248,132,46"] = C(232, 44, 72), -- tail fur
			["22,14,14"] = C(14, 8, 10), -- markings, nose, claws
			["86,10,14"] = C(40, 4, 10), -- mouth
			["246,238,220"] = C(246, 238, 226), -- fangs
			["255,62,28"] = C(255, 226, 110), -- glowing eyes (and their light) turn gold
			["255,196,120"] = C(255, 180, 192), -- chakra flame licks
			["255,84,24"] = C(215, 16, 52),
		},
		Bands = {
			{ from = 330, to = 15, hue = 345, sat = 1, val = 0.8 },
			{ from = 15, to = 70, hue = 350, sat = 1.05, val = 0.85 },
		},
	},
}
