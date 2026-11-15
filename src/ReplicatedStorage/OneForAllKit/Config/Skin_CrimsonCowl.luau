-- (2026-11-07 perks) CRIMSON COWL, the One For All alt skin (PerkCatalog.SKINS.OneForAll). Deep-merged into Config
-- like the Flair_ passes. AltPalette is laid over Config.Palette key by key and is used for everything a caster draws
-- when that caster's player has Skin == "Alt" (read at cast time on every client): Full Cowl's lightning goes crimson,
-- and the 100% accents (veins, the ultimate's second colour, the mode rim) go molten gold so the two still read apart.
-- Keys the normal palette lacks (StormTint, ImpactTint2) replace colours the normal look hard-codes.
local C = Color3.fromRGB

return {
	AltPalette = {
		Core      = C(255, 242, 238), -- white-hot, warm
		Cowl      = C(255, 44, 72),   -- Full Cowl lightning: crimson (the signature)
		CowlDeep  = C(178, 12, 42),   -- sheaths, rings, deep glows
		Emerald   = C(104, 0, 22),    -- darkest: tendril halos
		Spark     = C(255, 208, 210), -- glints, screen lines, impact tints
		Crimson   = C(255, 178, 48),  -- the 100% colour: molten gold veins, rim and lightning
		Blood     = C(150, 64, 0),    -- vein sheath: dark amber
		Ember     = C(255, 226, 150), -- hot sparks off a 100% arm
		Storm     = C(66, 50, 54),    -- the ultimate's cloud deck, faintly red
		StormDark = C(40, 26, 30),
		Suit      = C(70, 16, 24),
		StormTint = C(242, 226, 226), -- the storm's colour grade (normal: a faint green)
		ImpactTint2 = C(255, 222, 196), -- the smash's second impact tint (normal: a pale green)
	},
}
