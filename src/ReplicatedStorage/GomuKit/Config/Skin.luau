--!nocheck
-- GomuKit.Config.Skin (PERKS 2026-11-07, owner kitsE): the Fighter Skins perk's alternate colourway for this kit,
-- "CRIMSON GEAR" (HudShared.PerkCatalog.SKINS.Gomu). Deep-merged into Config as Config.SkinAlt.
-- A caster whose player has the attribute Skin == "Alt" (ShopService writes it) is drawn with Palette below merged over
-- Config.Palette, on every client, by a second copy of every move module (GomuClient builds it).
-- The look: Gear Fifth burns CRIMSON instead of white - red rubber, red hair and clothes, a red sun, rose clouds and a
-- dark-red cartoon outline - and every move's whooshes, impacts, stars and steam run crimson / red-gold.
local C = Color3.fromRGB

return {
	SkinAlt = {
		Name = "CRIMSON GEAR",
		Palette = {
			-- Gear Fifth (the ultimate + the mode look on the body)
			Nika = C(245, 62, 70),        -- crimson rubber, hair and clothes tint
			Cloud = C(255, 150, 155),     -- rose clouds / the cloud scarf
			Sun = C(255, 118, 80),        -- a red sun: lights, the aura core
			SunHot = C(255, 50, 38),      -- flare accents
			Toon = C(72, 0, 14),          -- dark-red cartoon outline
			Lavender = C(255, 92, 124),   -- the drum-beat pulse rings
			Gear5Crater = C(255, 60, 40),
			-- the moves
			Whoosh = C(255, 128, 118),    -- whoosh trails, speed streaks, afterimage fists (additive)
			Impact = C(255, 150, 90),     -- impact flashes / comic bursts (red-gold)
			M1Star = C(255, 120, 86),
			M1Ring = C(255, 140, 130),
			M1Pistol = C(255, 92, 60),
			Rubber = C(255, 176, 166),    -- the sheen along a stretched limb
			Steam = C(255, 182, 176),     -- Gear-Second pink steam on the inflate / deflate
			HakiSheen = C(210, 30, 56),   -- a crimson sheen on the haki fist (the fist itself stays black)
			HakiBolt = C(255, 36, 36),
		},
	},
}
