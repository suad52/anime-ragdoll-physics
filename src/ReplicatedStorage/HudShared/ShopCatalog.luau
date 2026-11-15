-- ReplicatedStorage.HudShared.ShopCatalog: what the top-left SHOP sells (cosmetics only - nothing changes a fight).
-- Yen is earned in play (ServerScriptService.ShopService): START on a first join, PER_KILL per KO (leaderstats.Kills),
-- PER_MINUTE while online. Auras: particles + light around the body. Titles: a name plate over the head.
local C = Color3.fromRGB
return {
	CURRENCY = "¥",
	START = 300,
	PER_KILL = 15,
	PER_MINUTE = 10,
	-- fighters (2026-11-07): a new player picks STARTER_PICKS of the roster (HudShared.Kits) for free on the first join
	-- (StarterSelect); every other fighter unlocks for PRICE_YEN, or for Robux through its own game pass. PASSES maps
	-- kit id -> game pass id (0 = not set up yet: the Robux button says so). PRICE_ROBUX is only the label shown until
	-- the pass exists; after that the client shows the price set on the pass itself (Creator Dashboard).
	-- STUDIO_ALL_KITS: true unlocks every fighter in Studio playtests (skips the pick screen while testing other things).
	KITS = {
		STARTER_PICKS = 5,
		PRICE_YEN = 2000,
		PRICE_ROBUX = 25,
		PASSES = { Limitless = 0, Vulpine = 0, Godspeed = 0, OneForAll = 0, Tempest = 0, Carver = 0, Shifter = 0, Zangetsu = 0, Ascendant = 0, Gomu = 0, Stormdraw = 0 },
		-- Robux unlocks as DEVELOPER PRODUCTS (2026-11-07): kit id -> developer product id (0 = not created yet). A
		-- product wins over a pass for the Robux button; ShopService.ProcessReceipt saves the unlock in the profile.
		-- Created on the Creator Dashboard 2026-11-07, all R$25, managed pricing OFF. Keep every normal fighter product at
		-- PRICE_ROBUX and the PREMIUM ones at their premium price (never below PRICE_ROBUX): re-buying an owned fighter
		-- refunds a flat KIT_YEN, so a cheaper product would be a voucher for any fighter. Use the Product ID column, not
		-- the DeveloperProductId.
		PRODUCTS = {
			Limitless = 3729438196, -- Unlock Fighter - Limitless
			Vulpine = 3729438388,   -- Unlock Fighter - Sage Arts
			Godspeed = 3729438565,  -- Unlock Fighter - Godspeed
			OneForAll = 3729439125, -- Unlock Fighter - One For All
			Tempest = 3729439344,   -- Unlock Fighter - Lightning Arts
			Carver = 3729439462,    -- Unlock Fighter - Cursed Shrine
			Shifter = 3729439584,   -- Unlock Fighter - Titan Shifter
			Zangetsu = 3729439741,  -- Unlock Fighter - Soul Reaper
			Ascendant = 3729439831, -- Unlock Fighter - Ki Master
			Gomu = 3730252672,               -- Unlock Fighter - Straw Hat (product not created yet: 0 = the Robux button says so)
			Stormdraw = 0,                   -- Unlock Fighter - Thunder Breathing (not created yet: 0 = the Robux button says so)
		},
		-- PREMIUM (2026-11-07): Robux-only fighters. Never a free starter (the pick screen shows them, locked), no Yen
		-- price. kit id -> the Robux price shown until the product's real price loads - set the SAME price on the
		-- fighter's developer product (Creator Dashboard), that is what the player is actually charged.
		PREMIUM = { Shifter = 50, Ascendant = 50 },
		-- FREE (2026-11-08, "unlock eren and goku for now so we can test them"): fighters EVERY player owns, in every
		-- server (Studio and live), without picking or buying them. They show as owned everywhere, so their buy buttons
		-- disappear. Empty this table to sell them again; nobody keeps a free fighter after that.
		FREE = { Shifter = true, Ascendant = true, Normal = true }, -- Normal (2026-11-13): the no-powers choice, always everyone's
		-- EARLY ACCESS (2026-11-09): fighters still in development. kit id -> true. Playable ONLY with the Early Access perk
		-- (PerkCatalog "EarlyAccess", R$345): never a starter pick, never sold on their own (Yen or Robux) - the roster's
		-- Robux button sells the pass instead. While this is empty the Early Access card is hidden in the shop. Take a
		-- fighter out of here when it is finished (it then unlocks like any other fighter).
		EARLY = { Stormdraw = true }, -- 2026-11-12: "make him only available to the early access gamepass" (Zenitsu)
		STUDIO_ALL_KITS = false,
		-- ALL_FREE (2026-11-10, "unlock all fighters for everyone for now"): true = EVERY player owns EVERY fighter, in
		-- every server (Studio and live). Nothing is saved: the pick screen is skipped WITHOUT using up a new player's
		-- starter picks, and bought / picked fighters stay in the profile. Set it to false to lock the roster again -
		-- everyone is then back to exactly what they picked or bought, and new players get the pick screen.
		ALL_FREE = true,
		-- DEFAULT (2026-11-13): the fighter a player has when they JOIN. The owner: "it should be just the normal at first and
		-- then u can switch to anime characters". Must be a FREE one (ShopService ignores it otherwise). A fighter picked
		-- later lasts for the session only - the next join starts as this again.
		DEFAULT = "Normal",
	},
	tabs = { { id = "aura", label = "AURAS", jp = "オーラ" }, { id = "title", label = "TITLES", jp = "称号" } },
	items = {
		{ id = "aura_violet", kind = "aura", name = "Void Violet", jp = "紫電", price = 200, c0 = C(220, 190, 255), c1 = C(120, 60, 255) },
		{ id = "aura_crimson", kind = "aura", name = "Crimson Curse", jp = "呪炎", price = 350, c0 = C(255, 150, 150), c1 = C(200, 10, 40) },
		{ id = "aura_azure", kind = "aura", name = "Azure Flash", jp = "蒼雷", price = 500, c0 = C(200, 245, 255), c1 = C(40, 150, 255) },
		{ id = "aura_jade", kind = "aura", name = "Jade Spirit", jp = "翠魂", price = 650, c0 = C(200, 255, 220), c1 = C(20, 190, 110) },
		{ id = "aura_gold", kind = "aura", name = "Golden Ki", jp = "金気", price = 900, c0 = C(255, 245, 180), c1 = C(255, 170, 20) },
		{ id = "aura_shadow", kind = "aura", name = "Shadow Flame", jp = "影炎", price = 1200, c0 = C(150, 140, 170), c1 = C(25, 15, 40) },
		{ id = "title_rookie", kind = "title", name = "Street Rookie", jp = "新人", price = 100, c0 = C(235, 235, 245), c1 = C(140, 150, 170) },
		{ id = "title_ronin", kind = "title", name = "Neon Ronin", jp = "浪人", price = 400, c0 = C(120, 255, 240), c1 = C(255, 60, 200) },
		{ id = "title_titan", kind = "title", name = "Titan Slayer", jp = "巨人殺し", price = 600, c0 = C(255, 220, 190), c1 = C(200, 70, 40) },
		{ id = "title_godspeed", kind = "title", name = "Godspeed", jp = "神速", price = 750, c0 = C(210, 240, 255), c1 = C(60, 170, 255) },
		{ id = "title_honored", kind = "title", name = "The Honored One", jp = "最強", price = 1000, c0 = C(235, 225, 255), c1 = C(120, 80, 255) },
		{ id = "title_king", kind = "title", name = "King of Curses", jp = "呪いの王", price = 1500, c0 = C(255, 200, 200), c1 = C(190, 0, 30) },
	},
}
