--!nocheck
-- ZangetsuKit.Config.Skin (PERKS 2026-11-07, owner kitsE): the Fighter Skins perk's alternate colourway for this kit,
-- "WHITE BANKAI" (HudShared.PerkCatalog.SKINS.Zangetsu). Deep-merged into Config as Config.SkinAlt.
-- A caster whose player has the attribute Skin == "Alt" (ShopService writes it) is drawn with Palette below merged over
-- Config.Palette, on every client, by a second copy of every move module (ZangetsuClient builds it). The server-built
-- Bankai sword + coat (ZangetsuKit.Sword) read the Sword* / Coat* keys when the form is shown.
-- The look: the Bankai's black turns WHITE (still non-additive parts and LightEmission-0 smoke), its crimson turns
-- electric blue, the Shikai reiatsu goes white-hot with royal-blue edges, the Hollow mask's stripes turn blue.
local C = Color3.fromRGB

return {
	SkinAlt = {
		Name = "WHITE BANKAI",
		Palette = {
			-- Shikai reiatsu (Getsuga / Shunpo / the M1 slashes): white-hot heart, royal-blue edges
			Core = C(255, 255, 255),
			Reiatsu = C(115, 140, 255),
			Ice = C(55, 75, 255),
			Frost = C(226, 232, 255),
			-- Bankai / Tensa Zangetsu: a white body (never additive), electric-blue edges, navy depths, white smoke
			Black = C(236, 238, 245),
			Crimson = C(35, 115, 255),
			Ember = C(130, 205, 255),
			Blood = C(14, 30, 95),
			Smoke = C(206, 212, 226),
			-- Hollow Mask: blue stripes, a white swirl (the bone and the gold eyes stay)
			Hollow = C(40, 120, 255),
			HollowDark = C(226, 230, 240),
			-- the Bankai sword + coat (ZangetsuKit.Sword applies these on the server when Tensa Zangetsu is shown)
			Tensa = C(238, 240, 246),     -- a white blade
			TensaEdge = C(30, 44, 90),    -- a dark navy edge
			Guard = C(214, 218, 228),     -- silver-white manji guard + pommel
			Chain = C(176, 182, 198),
			BkHilt = C(232, 234, 240),    -- the hilt
			Coat = C(242, 243, 248),      -- the WHITE Bankai coat
			Lining = C(28, 58, 160),      -- royal-blue lining
		},
	},
}
