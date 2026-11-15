--!nocheck
-- HudShared.SkinOutfits (2026-11-10): what an equipped fighter skin DRESSES the player's avatar in - Roblox catalog
-- (marketplace) asset ids, applied on the server by ServerScriptService.FighterSkinLook through a HumanoidDescription.
-- The player's face, skin colour and body stay; everything listed replaces that slot (an empty list strips the slot).
-- Per kit id:
--   hair / hat / face / neck / shoulders / front / back / waist = { assetId, ... }  (rigid accessories)
--   shirt / pants = classic clothing asset id (or nil)
--   layered = { { id = assetId, type = "Jacket" | "Shirt" | "Pants" | "Shorts" | "Sweater" | "TShirt" | "DressSkirt" }, ... }
-- Players can wear any catalog item inside an experience without owning it. A kit with no entry keeps the old
-- colour tint + trim. Pick ids with the catalog search API (scratchpad skins/search2.py) and check them in Play.
-- Picked 2026-11-10 from the catalog (most-favourited matches; descriptive names preferred over character-named ones).
-- Gomu keeps the kit's own server-built straw hat (GomuKit.Hat) and Zangetsu its sword, so neither adds one here.
return {
	Limitless = { -- white spiky hair, black blindfold, black high-collar uniform
		hair = { 7855160231 }, face = { 5858810459 },
		layered = { { id = 13735030550, type = "Jacket" }, { id = 132883506091269, type = "Pants" } },
	},
	Vulpine = { -- spiky blonde hair, ninja headband, orange hoodie + orange track pants
		hair = { 7963410253 }, hat = { 12588298681 },
		-- (the first pick 12642101164 was mostly black with a "YSX-G 2023" logo - read as streetwear, not the ninja)
		layered = { { id = 13366542200, type = "Jacket" }, { id = 17798217742, type = "Pants" } },
	},
	Godspeed = { -- white messy hair, purple long sleeve, white shorts
		hair = { 6564213921 },
		layered = { { id = 9512629956, type = "Shirt" }, { id = 9496377521, type = "Shorts" } },
	},
	OneForAll = { -- green messy hair, green jumpsuit
		hair = { 17344438373 },
		layered = { { id = 9040341624, type = "Jacket" }, { id = 111826403497857, type = "Pants" } },
	},
	Tempest = { -- black spiky hair, white open shirt, purple waist rope, black ninja pants
		hair = { 14892977317 }, waist = { 13006613218 },
		layered = { { id = 9349657525, type = "Shirt" }, { id = 9179180050, type = "Pants" } },
	},
	Carver = { -- pink spiky hair, white kimono, white hakama
		hair = { 8780245366 },
		layered = { { id = 9184024526, type = "Jacket" }, { id = 13470218992, type = "Pants" } },
	},
	Shifter = { -- short messy brown hair, brown military jacket, white uniform pants, green cape
		hair = { 13645323371 }, back = { 5764084831 },
		layered = { { id = 106041285542682, type = "Jacket" }, { id = 105528352694481, type = "Pants" } },
	},
	Zangetsu = { -- spiky orange hair, black kimono, black hakama
		hair = { 8859470868 },
		layered = { { id = 9498358241, type = "Jacket" }, { id = 12472522420, type = "Pants" } },
	},
	Ascendant = { -- black spiky hair with bangs, orange gi top + bottom
		hair = { 11139160810 },
		layered = { { id = 18687394020, type = "Jacket" }, { id = 18687407053, type = "Pants" } },
	},
	Gomu = { -- black messy hair, red open shirt, blue denim shorts (the kit adds the straw hat)
		hair = { 6564177190 },
		layered = { { id = 9066375070, type = "Jacket" }, { id = 138326599269804, type = "Shorts" } },
	},
}
