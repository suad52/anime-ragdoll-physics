-- Limitless alternate colourway "CRIMSON VOID" (HudShared.PerkCatalog.SKINS.Limitless; PERKS 2026-11-07, owner kits-A).
-- GojoClient turns it on per cast when the CASTER's player has Skin == "Alt": every world VFX of that cast is built
-- under LocalFX.LimitlessAltFX, which GojoShared.SkinTint recolours with these hue bands (degrees, wrapping), and the
-- screen-space colours (titles, impact frames, grades) go through the same mapper. Tune freely.
local C = Color3.fromRGB
return {
	Name = "CRIMSON VOID",
	Gray = 0.06, -- whites, greys and blacks stay as they are (the hot white cores keep reading as light)
	SatFloor = 0.3, -- pale tints (a cold white-blue) only turn their hue (to a pale rose); stronger colours also take sat/val
	Bands = {
		{ from = 165, to = 250, hue = 342, sat = 1.1, val = 0.82 }, -- blues / cyans (Lapse Blue, the void's light) -> deep rose-crimson
		{ from = 250, to = 330, hue = 350, sat = 1.15, val = 1 }, -- violets / purples (Hollow Purple) -> crimson
		{ from = 330, to = 45, hue = 4, sat = 1.05, val = 1 }, -- reds / oranges (Reversal Red) -> scarlet
		{ from = 45, to = 165, hue = 350, sat = 1, val = 1 }, -- anything else -> crimson
	},
	-- the void's world lighting while a CRIMSON VOID stands (the normal void is a cold blue night)
	Void = {
		Tint = C(255, 192, 200), -- the colour grade inside
		Ambient = C(40, 8, 14),
		OutdoorAmbient = C(24, 4, 9),
		Ground = C(16, 3, 6), -- the terrain is darkened toward this
	},
}
