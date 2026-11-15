--!nocheck
-- ReplicatedStorage.HudShared.PerkCatalog (2026-11-07): every Robux item that is not a fighter unlock - ONE source of
-- truth for names, prices, product ids and tuning. Everything is a DEVELOPER PRODUCT (the owner asked for products):
--   kind "perk"       -> bought once, saved forever in the profile (ShopService d.perks), shown in the INVENTORY
--   kind "consumable" -> fires once per purchase (Yen packs, the server-wide Meteor Shower, an instant ult charge)
-- product = the Creator Dashboard "Product ID" (0 = not created yet: the buy button says COMING SOON). All 17 were
-- created on 2026-11-07 (managed pricing OFF; change prices on the dashboard AND here so the labels match).
-- GAME PASS perks (2026-11-07): an item with `pass` (instead of `product`) is a Roblox GAME PASS - pass = the pass ID
-- from Creator Dashboard > Monetization > Passes (0 = not created yet: the buy button says COMING SOON). Roblox keeps
-- the ownership: ShopService asks on every join and on purchase (never saved in the profile, never a receipt).
-- Keep `name` free of franchise names: it is what the Roblox purchase prompt shows.
-- SHOP EXPANSION (2026-11-09): new perks (Early Access, emote-wheel slots, kill sounds, ultimate outfit, fun filters,
-- taunt packs) and two repeatable kinds handled by ShopService extensions (ServerScriptService.ShopService.Ext):
--   kind "emotePage"   -> +1 emote-wheel page per purchase (Ext.EmoteWheel)
--   kind "gadgetCrate" -> `count` random gadgets per purchase (Ext.Gadgets)
-- manage = what the ROBUX tab's MANAGE button opens for an owned perk: "settings" | "emotes" | "taunts" (nil = the
-- inventory). ribbon = the card's tag text (default FOREVER / ONE-TIME).
local C = Color3.fromRGB
local P = {}

P.YEN_PER_ROBUX = 80 -- the fighter rate (¥2,000 or R$25); a re-bought perk refunds price * this in Yen

-- display order = the order of this list
-- SANDBOX SHOP (2026-11-14, owner: "this is a sandbox not a pvp game so you do not need the pvp gamepasses or perks,
-- rather create the following: Kill effects, Meteor Shower, Nuke, Run speed slider, Health slider, Gravity slider, and
-- other variables you can think of"). The sandbox items come first. product 0 = not created on the Creator Dashboard
-- yet (the buy button says COMING SOON): create each as a developer product at this price, managed pricing OFF, and
-- put its Product ID here. The PvP perks (Faster Cooldowns, Faster Ult Charge, Instant Ult Charge, Dash Master, 2x
-- Speed, 2x Jump, the duel Victory Flashes) are RETIRED: never sold or shown in the shop again, but everyone who bought
-- one keeps it (2x Speed / 2x Jump now unlock the matching slider - HudShared.SliderCatalog `legacy`).
-- PRODUCTS (2026-11-14): every item on sale has its own developer product in THIS game (universe 10775720562),
-- created with these names, prices and descriptions (managed pricing OFF: change a price on the Creator Dashboard AND
-- here so the labels match). The old ids left on the RETIRED items belong to Anime Duels (copied with the place);
-- they are never sold here. The id list is also kept in the owner's sandbox_products/product_ids.json.
P.ITEMS = {
	-- SLIDERS ------------------------------------------------------------------------------------------------------
	-- `slider` = the HudShared.SliderCatalog key the perk unlocks; manage "sliders" = the shop's MANAGE opens the
	-- sliders panel (StarterPlayerScripts.SandboxSliders). The pack is a bundle: its `contents` are granted one by one
	-- (one already owned comes back as its share of the pack price in Yen - ShopService.grantBundle).
	{ id = "SliderPack", kind = "perk", name = "Sandbox Sliders Pack", price = 399, product = 3731508107, glyph = "制", color = C(255, 150, 60),
		manage = "sliders", ribbon = "ALL SIX",
		contents = { perks = { "RunSlider", "JumpSlider", "GravitySlider", "HealthSlider", "StrengthSlider", "FlingSlider" } },
		desc = "All six sliders: run speed, jump height, gravity, max health + god mode, strength and fling power." },
	{ id = "RunSlider", kind = "perk", slider = "speed", name = "Run Speed Slider", price = 99, product = 3731508170, glyph = "走", color = C(110, 255, 160),
		manage = "sliders", desc = "Set your run speed anywhere from a crawl (x0.25) to a blur (x4)." },
	{ id = "JumpSlider", kind = "perk", slider = "jump", name = "Jump Height Slider", price = 99, product = 3731508184, glyph = "跳", color = C(150, 170, 255),
		manage = "sliders", desc = "Set your jump from a little hop (x0.25) to a launch (x6)." },
	{ id = "GravitySlider", kind = "perk", slider = "gravity", name = "Gravity Slider", price = 99, product = 3731508198, glyph = "重", color = C(190, 140, 255),
		manage = "sliders", desc = "Your own gravity, 5% to 250%: float like a feather or drop like a rock." },
	{ id = "HealthSlider", kind = "perk", slider = "health", name = "Health Slider + God Mode", price = 149, product = 3731508238, glyph = "命", color = C(90, 230, 140),
		manage = "sliders", desc = "Max health from 25 to 5,000 - plus a GOD MODE switch that shrugs off everything." },
	{ id = "StrengthSlider", kind = "perk", slider = "damage", name = "Strength Slider", price = 99, product = 3731508249, glyph = "力", color = C(255, 90, 90),
		manage = "sliders", desc = "Your weapons and powers hit dummies anywhere from x0.25 to x10 as hard." },
	{ id = "FlingSlider", kind = "perk", slider = "fling", name = "Fling Power Slider", price = 99, product = 3731509016, glyph = "飛", color = C(90, 200, 255),
		manage = "sliders", desc = "Your hits and throws send bodies flying x0.25 to x6 as far." },
	-- more sandbox perks -------------------------------------------------------------------------------------------
	-- Spawn Limit x3: the spawn menu's caps (ReplicatedStorage.Sandbox.Config SPAWN) x TUNING.SPAWN_CAP_MUL for this player
	{ id = "SpawnPlus", kind = "perk", name = "Spawn Limit x3", price = 99, product = 3731508278, glyph = "増", color = C(255, 205, 70),
		desc = "Three times as many dummies, gas cans, fuel drums and crates of your own out at once." },
	-- every kill effect in P.KO, now and future ones (ShopService.ownsItem "ko" is true for all of them)
	{ id = "KillFXPack", kind = "perk", name = "Kill Effects Pack", price = 249, product = 3731508297, glyph = "撃", color = C(255, 110, 60),
		desc = "Every kill effect - black hole, fireworks, ice, soul, pixels, mini nuke and the rest - plus every future one." },
	-- SERVER EVENTS: consumables the whole server sees, with the buyer's name. Each fires its ServerStorage.PerkHooks
	-- event (ShopService HOOK_OF, or the item's own `hook`) once the receipt is saved, and waits behind one of its kind
	-- that is still running. (2026-11-15) `event = true` puts the card in the shop's own EVENTS tab (CharacterSelect).
	{ id = "Nuke", kind = "consumable", event = true, name = "Nuke", price = 199, product = 3731508308, glyph = "核", color = C(255, 230, 90),
		desc = "A warhead hits the middle of the map - everything in the blast is thrown, burned or worse. God Mode survives it." },
	{ id = "Meteor", kind = "consumable", event = true, name = "Meteor Shower", price = 99, product = 3731508349, glyph = "星", color = C(255, 120, 40),
		desc = "Rain meteors on the whole map for everyone in the server - with your name on it." },
	{ id = "MoonGravity", kind = "consumable", event = true, name = "Moon Gravity", price = 49, product = 3731508364, glyph = "月", color = C(170, 200, 255),
		desc = "90 seconds of moon gravity for the whole server. Buy again to add more time." },
	{ id = "DummyRain", kind = "consumable", event = true, name = "Dummy Rain", price = 49, product = 3731508376, glyph = "雨", color = C(235, 235, 245),
		desc = "Two dozen dummies fall out of the sky all over the map." },
	-- (2026-11-15, owner: "Make the events as its own section here, and add all the events you mentioned") the new events,
	-- run by ServerScriptService.PerkMapEvents on the BUYER'S map (the Ruins or the open sandbox). hook = the PerkHooks
	-- event ShopService fires. Products created 2026-11-15 through Open Cloud (managed pricing OFF; ids also in the
	-- owner's sandbox_products/product_ids.json).
	{ id = "Tornado", kind = "consumable", event = true, hook = "Tornado", name = "Tornado", price = 99, product = 3731915300, glyph = "竜",
		color = C(160, 178, 200), ribbon = "SERVER EVENT", desc = "A tornado tears across your map for 35 seconds, sucking up dummies, props and players." },
	{ id = "Earthquake", kind = "consumable", event = true, hook = "Earthquake", name = "Earthquake", price = 79, product = 3731915362, glyph = "震",
		color = C(214, 150, 80), ribbon = "SERVER EVENT", desc = "20 seconds of shaking: the ground splits open and nobody stays on their feet." },
	{ id = "BlackHole", kind = "consumable", event = true, hook = "BlackHole", name = "Black Hole", price = 149, product = 3731915382, glyph = "穴",
		color = C(150, 90, 255), ribbon = "SERVER EVENT", desc = "A black hole opens over your map and swallows every dummy and prop it can reach." },
	{ id = "Flood", kind = "consumable", event = true, hook = "Flood", name = "Flood", price = 99, product = 3731915407, glyph = "洪",
		color = C(60, 150, 240), ribbon = "SERVER EVENT", desc = "The water rises over your whole map - bodies float off and you swim. Lasts a minute." },
	{ id = "IceWorld", kind = "consumable", event = true, hook = "IceWorld", name = "Ice World", price = 79, product = 3731915428, glyph = "氷",
		color = C(140, 210, 255), ribbon = "SERVER EVENT", desc = "60 seconds of ice: the ground freezes over and nobody can stop sliding." },
	{ id = "Zombies", kind = "consumable", event = true, hook = "Zombies", name = "Zombie Dummies", price = 129, product = 3731915467, glyph = "屍",
		color = C(130, 200, 90), ribbon = "SERVER EVENT", desc = "14 zombie dummies claw out of the ground and come for everyone. Lasts 75 seconds." },
	{ id = "BossDummy", kind = "consumable", event = true, hook = "BossDummy", name = "Giant Boss Dummy", price = 149, product = 3731915490, glyph = "巨",
		color = C(235, 70, 70), ribbon = "SERVER EVENT", desc = "A giant boss dummy stomps onto your map. It takes the whole server to bring it down." },
	{ id = "ChaosBundle", kind = "consumable", event = true, hook = "ChaosBundle", name = "Chaos Bundle", price = 399, product = 3731915652, glyph = "乱",
		color = C(255, 120, 50), ribbon = "8 EVENTS", desc = "3 Nukes and 5 Meteor Showers, one after another. Worth R$1,092." },
	-- (2026-11-15, owner picked them from the ideas list) two more sandbox perks
	-- Dummy of Anyone: the spawn menu's DUMMY OF ANYONE row - type a username, spawn a dummy wearing that avatar
	-- (StarterPlayerScripts.SandboxClient; ServerScriptService.Sandbox.Main spawnAnyone)
	{ id = "DummyAnyone", kind = "perk", name = "Dummy of Anyone", price = 149, product = 3731915533, glyph = "人", color = C(110, 200, 255),
		manage = "anyone", desc = "Spawn a dummy that looks like any Roblox player - yourself, a friend or any username." },
	-- Free Cam / Photo Mode: StarterPlayerScripts.PhotoMode (the PHOTO tile on the HUD rail, or P)
	{ id = "PhotoMode", kind = "perk", name = "Free Cam / Photo Mode", price = 99, product = 3731915548, glyph = "写", color = C(255, 196, 110),
		manage = "photo", desc = "Fly the camera anywhere, hide the HUD and line up the perfect shot." },
	-- everything else ----------------------------------------------------------------------------------------------
	{ id = "YenX2", kind = "perk", name = "2x Yen", price = 199, product = 3731508388, glyph = "¥", color = C(255, 205, 70),
		desc = "Double Yen from every kill and every minute played." },
	{ id = "VIP", kind = "perk", name = "VIP", price = 249, product = 3731508403, glyph = "王", color = C(255, 215, 0),
		desc = "Gold VIP tag over your head and in chat, an exclusive gold aura, and +25% Yen." },
	{ id = "Trails", kind = "perk", name = "Trail Pack", price = 99, product = 3731508414, glyph = "虚", color = C(255, 140, 255),
		desc = "Rainbow, Gold and Black Flame trails on your punches." },
	{ id = "AllFighters", kind = "perk", name = "All Fighters Bundle", price = 149, product = 3731508469, glyph = "全", color = C(255, 120, 90),
		desc = "Unlocks every fighter - including every future one." },
	-- Early Access: fighters flagged ShopCatalog.KITS.EARLY are playable only with this (now and every future one)
	{ id = "EarlyAccess", kind = "perk", name = "Early Access", price = 345, product = 3731508483, glyph = "先", color = C(80, 230, 210),
		desc = "Play fighters that are still in development - now and every future one." },
	-- 8 slots on every emote-wheel page instead of 4 (the retired Emote Pack includes it)
	{ id = "EmoteSlots", kind = "perk", name = "More Emote Slots", price = 150, product = 3731508499, glyph = "枠", color = C(255, 230, 120),
		manage = "emotes", desc = "+4 slots on every page of your emote wheel - 8 instead of 4." },
	-- the sounds a KO you land plays on the body, and the one your own KO plays (Settings > Audio: any Roblox audio ID)
	{ id = "KillSound", kind = "perk", name = "Custom Kill Sound", price = 100, product = 3731508512, glyph = "音", color = C(255, 120, 140),
		manage = "settings", desc = "Pick the sound that plays when you KO someone - and when you get KO'd." },
	-- switch to one of the player's saved Roblox outfits while an ultimate form is active (Settings > Outfit)
	{ id = "UltOutfit", kind = "perk", name = "Ultimate Outfit", price = 100, product = 3731508525, glyph = "装", color = C(190, 140, 255),
		manage = "settings", desc = "Wear one of your saved Roblox outfits while your ultimate is active." },
	-- screen filters for your own view only (Settings > Fun)
	{ id = "FunFilters", kind = "perk", name = "Fun Filters", price = 100, product = 3731508543, glyph = "遊", color = C(255, 160, 220),
		manage = "settings", desc = "Rain, snow, cherry petals, night, sunset, retro, upside-down and more - just for your screen." },
	-- taunt sound packs (the taunt menu: HudShared.TauntCatalog)
	{ id = "TauntHype", kind = "perk", retired = true, -- (2026-11-15) owner: "remove the taunts" - owners keep it, nobody can buy it
		 name = "Taunt Pack: Hype", price = 75, product = 3731508593, glyph = "叫", color = C(255, 190, 70),
		manage = "taunts", desc = "6 more taunts: air horn, roaring crowd, drum roll, fanfare and more." },
	{ id = "TauntTrash", kind = "perk", retired = true, name = "Taunt Pack: Trash Talk", price = 75, product = 3731508604, glyph = "嘲", color = C(140, 220, 255),
		manage = "taunts", desc = "6 more taunts: slow clap, TOO SLOW, WHAT A JOKE, WEIRDO and more." },
	-- RETIRED (2026-11-14, sandbox shop): the PvP perks. Owners keep every effect (ShopService still applies them;
	-- 2x Speed / 2x Jump owners get the run / jump slider instead of the old toggle); nobody can buy them any more.
	{ id = "UltCharge", kind = "perk", retired = true, name = "Faster Ult Charge", price = 149, product = 3729496405, glyph = "極", color = C(255, 90, 200),
		desc = "Your ultimate recharges 40% faster." },
	{ id = "Cooldowns", kind = "perk", retired = true, name = "Faster Cooldowns", price = 199, product = 3729496493, glyph = "速", color = C(90, 200, 255),
		desc = "Every ability recharges 30% faster." },
	{ id = "SpeedX2", kind = "perk", retired = true, name = "2x Speed", price = 129, product = 3729496688, glyph = "走", color = C(110, 255, 160),
		desc = "Run twice as fast - now the Run Speed Slider." },
	{ id = "JumpX2", kind = "perk", retired = true, name = "2x Jump", price = 99, product = 3729496800, glyph = "跳", color = C(150, 170, 255),
		desc = "Jump twice as high - now the Jump Height Slider." },
	-- (2026-11-07) was a GAME PASS, (2026-11-10) a developer product (pass stays 0); halves the Shift dash cooldown
	-- (TUNING.DASH_COOLDOWN_MUL). Keep glyph/color OUT of any comment: an inline comment here once swallowed them.
	{ id = "DashPass", kind = "perk", retired = true, name = "Dash Master", price = 99, pass = 0, product = 3730252721, glyph = "疾", color = C(110, 200, 255),
		desc = "Your dash recharges twice as fast - a 10s cooldown becomes 5s." },
	-- RETIRED (2026-11-07): the packs that sold a whole category (KOFX, Skins, Emotes). Emotes / KO effects / skins are now owned one
	-- at a time through the RANDOM rolls below; these stay so earlier buyers keep every item of their pack (LEGACY) and
	-- the Starter Pack can still include every KO effect. retired = never shown or sold in the shop. KOFX's price is
	-- what its three effects cost as rolls (3 x R$25), which is the value the Starter Pack popup shows for it.
	-- (2026-11-14) KOFX owns only the three effects it was sold with (P.KO items marked `nopack` are not in it).
	{ id = "KOFX", kind = "perk", retired = true, name = "KO Effects", price = 75, product = 3729497323, glyph = "爆", color = C(255, 110, 60),
		desc = "Confetti, Explosion or Lightning every time you KO someone." },
	{ id = "Skins", kind = "perk", retired = true, name = "Fighter Skins", price = 149, product = 3729497401, glyph = "色", color = C(200, 120, 255),
		desc = "An alternate colourway for every fighter." },
	{ id = "Emotes", kind = "perk", retired = true, name = "Emote Pack", price = 79, product = 3729497577, glyph = "舞", color = C(255, 230, 120),
		desc = "12 emotes: Taunt, Laugh, Victory, Wave, Bow, Clap, Dance, Flex, Shrug, Power Up, Pose and Facepalm (press B)." },
	-- STARTER PACK (2026-11-07): a one-time bundle. kind "perk" so it is owned forever and never sold twice; offer = true
	-- keeps it out of the ROBUX tab and the inventory count (it has its own pill + popup in CharacterSelect). On purchase
	-- ShopService grants every `contents` perk (one already owned becomes its share of the pack price in Yen) + the Yen.
	-- product 0 = not created yet: the offer only shows in Studio. Created 2026-11-07 on the Creator Dashboard (R$49,
	-- managed pricing OFF) - change the price there AND here.
	{ id = "StarterPack", kind = "perk", offer = true, name = "Starter Pack", price = 49, product = 3731508615, glyph = "初", color = C(255, 175, 60),
		contents = { perks = { "Trails", "KOFX" }, yen = 5000 },
		desc = "Trail Pack + KO Effects + ¥5,000 - one per player." },
	-- RANDOM ROLLS (2026-11-07): one roll = one emote / KO effect / fighter skin the player does NOT own yet, picked with
	-- equal odds (never a duplicate). Paid with Robux (this developer product) or with ROLL_YEN Yen (ShopRequest "roll").
	-- product 0 = not created yet: the Robux button says COMING SOON (the Yen roll works). Granted by ShopService.
	-- Products created 2026-11-07 on the Creator Dashboard (R$25 each, managed pricing OFF).
	{ id = "RollEmote", kind = "roll", cat = "emote", name = "Random Emote", price = 25, product = 3731508627, glyph = "舞", color = C(255, 230, 120),
		desc = "One emote you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollKO", kind = "roll", cat = "ko", name = "Random Kill Effect", price = 25, product = 3731508641, glyph = "爆", color = C(255, 110, 60),
		desc = "One kill effect you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollSkin", kind = "roll", cat = "skin", name = "Random Fighter Skin", price = 25, product = 3731508660, glyph = "色", color = C(200, 120, 255),
		desc = "One fighter skin you don't have yet. Equal odds, never a duplicate." },
	-- BULK ROLLS (2026-11-08): `count` rolls in one buy at the plain per-roll price (no discount: 5 x R$25, 10 x R$25).
	-- The shop offers a size only while at least that many items are left to win, so x10 appears for a category once it
	-- has 10+ items (more emotes are planned). With Yen they cost ROLL_YEN x count. Products created 2026-11-08 on the
	-- Creator Dashboard with exactly these names and prices (managed pricing OFF). Granted by ShopService (fewer left
	-- than `count` when a Robux receipt lands -> the missing rolls come back as Yen).
	{ id = "RollEmote5", kind = "roll", cat = "emote", count = 5, name = "5 Random Emotes", price = 125, product = 3731508713, glyph = "舞",
		color = C(255, 230, 120), desc = "Five emotes you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollEmote10", kind = "roll", cat = "emote", count = 10, name = "10 Random Emotes", price = 250, product = 3731508727, glyph = "舞",
		color = C(255, 230, 120), desc = "Ten emotes you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollKO5", kind = "roll", cat = "ko", count = 5, name = "5 Random Kill Effects", price = 125, product = 3731508742, glyph = "爆",
		color = C(255, 110, 60), desc = "Five kill effects you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollKO10", kind = "roll", cat = "ko", count = 10, name = "10 Random Kill Effects", price = 250, product = 3731508758, glyph = "爆",
		color = C(255, 110, 60), desc = "Ten kill effects you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollSkin5", kind = "roll", cat = "skin", count = 5, name = "5 Random Fighter Skins", price = 125, product = 3731508777, glyph = "色",
		color = C(200, 120, 255), desc = "Five fighter skins you don't have yet. Equal odds, never a duplicate." },
	{ id = "RollSkin10", kind = "roll", cat = "skin", count = 10, name = "10 Random Fighter Skins", price = 250, product = 3731508791, glyph = "色",
		color = C(200, 120, 255), desc = "Ten fighter skins you don't have yet. Equal odds, never a duplicate." },
	-- consumables -------------------------------------------------------------------------------------------------
	{ id = "Yen1", kind = "consumable", name = "Yen Pack - Small", price = 19, product = 3731508854, yen = 1500, glyph = "¥", color = C(255, 205, 70),
		desc = "+¥1,500" },
	{ id = "Yen2", kind = "consumable", name = "Yen Pack - Medium", price = 45, product = 3731508865, yen = 4000, glyph = "¥", color = C(255, 205, 70),
		desc = "+¥4,000" },
	{ id = "Yen3", kind = "consumable", name = "Yen Pack - Large", price = 99, product = 3731508881, yen = 10000, glyph = "¥", color = C(255, 205, 70),
		desc = "+¥10,000" },
	{ id = "Yen4", kind = "consumable", name = "Yen Pack - Huge", price = 219, product = 3731508894, yen = 25000, glyph = "¥", color = C(255, 205, 70),
		desc = "+¥25,000" },
	-- RETIRED (2026-11-14): a PvP boost (the UltReset hook still works for a receipt that is retried)
	{ id = "UltNow", kind = "consumable", retired = true, name = "Instant Ult Charge", price = 19, product = 3729498268, glyph = "雷", color = C(255, 90, 200),
		desc = "Your ultimate is ready right now." },
	-- (2026-11-09) repeatable: every purchase adds one more emote-wheel page (and the wheel gets a search box)
	{ id = "EmotePage", kind = "emotePage", name = "+1 Emote Page", price = 175, product = 3731508909, glyph = "頁", color = C(255, 230, 120),
		ribbon = "STACKS", manage = "emotes", desc = "One more page on your emote wheel, plus a search box. Buy again for another page." },
	-- (2026-11-09) gadgets: one-use tools fired from the gadget button (also sold one at a time for Yen: GADGETS tab)
	{ id = "GadgetCrate", kind = "gadgetCrate", count = 6, name = "Gadget Crate", price = 29, product = 3731508927, glyph = "箱", color = C(120, 230, 120),
		ribbon = "6 GADGETS", desc = "6 random gadgets: smoke bombs, decoys, boost pads, bubble shields and snacks." },
	-- (2026-11-11, wiki extras) VICTORY FLASHES for Robux (the shop's VICTORY tab sold them). flash = HudShared.VictoryCatalog
	-- id; ShopService.Ext.Victory grants it. (2026-11-14) RETIRED with the VICTORY tab (P.HIDE_TABS): they play after a DUEL.
	{ id = "VF_Thunder", kind = "victory", retired = true, flash = "Thunder", name = "Victory Flash: Thunderclap", price = 100, product = 0, glyph = "雷", color = C(255, 245, 140),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
	{ id = "VF_Sakura", kind = "victory", retired = true, flash = "Sakura", name = "Victory Flash: Sakura Storm", price = 100, product = 0, glyph = "桜", color = C(255, 170, 205),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
	{ id = "VF_Shatter", kind = "victory", retired = true, flash = "Shatter", name = "Victory Flash: Shattered", price = 100, product = 0, glyph = "破", color = C(140, 240, 255),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
	{ id = "VF_Spotlight", kind = "victory", retired = true, flash = "Spotlight", name = "Victory Flash: Spotlight", price = 100, product = 0, glyph = "星", color = C(255, 250, 230),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
	{ id = "VF_Inferno", kind = "victory", retired = true, flash = "Inferno", name = "Victory Flash: Inferno", price = 100, product = 0, glyph = "炎", color = C(255, 200, 60),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
	{ id = "VF_Void", kind = "victory", retired = true, flash = "Void", name = "Victory Flash: Void Walker", price = 100, product = 0, glyph = "虚", color = C(190, 120, 255),
		desc = "A victory cutscene that plays for both fighters when you win a duel." },
}
-- (2026-11-14) shop tabs the sandbox does not show (CharacterSelect.ShopExtras): the duel Victory Flashes
P.HIDE_TABS = { victory = true }
-- (2026-11-14) the perk that owns EVERY kill effect (ShopService.ownsItem)
P.KO_PACK = "KillFXPack"

P.byId, P.byProduct, P.byPass = {}, {}, {}
for i, it in ipairs(P.ITEMS) do
	it.order = i
	P.byId[it.id] = it
	-- every card builder indexes these (it.color:Lerp ...): an item without them used to crash the whole INVENTORY panel
	if typeof(it.color) ~= "Color3" then
		it.color = C(150, 148, 172)
		warn("[PerkCatalog] " .. tostring(it.id) .. " has no color - using grey")
	end
	if type(it.glyph) ~= "string" then
		it.glyph = "?"
	end
end
-- what a bundle is worth in Robux: its perks at their own prices + its Yen at the CHEAPEST Yen-pack rate (the honest
-- "value" the starter pack popup shows next to its price)
function P.worth(it)
	local c = it and it.contents
	if not c then
		return it and it.price or 0
	end
	local total = 0
	for _, id in ipairs(c.perks or {}) do
		local sub = P.byId[id]
		total += sub and sub.price or 0
	end
	if type(c.yen) == "number" and c.yen > 0 then
		local best
		for _, x in ipairs(P.ITEMS) do
			if type(x.yen) == "number" and x.yen > 0 then
				local rate = x.price / x.yen
				best = best and math.min(best, rate) or rate
			end
		end
		total += math.floor(c.yen * (best or 1 / P.YEN_PER_ROBUX) + 0.5)
	end
	return total
end

-- random rolls (2026-11-07) -----------------------------------------------------------------------------------------
P.ROLL_YEN = 500 -- one roll for Yen (¥500 = about 30 KOs)
P.LEGACY = { emote = "Emotes", ko = "KOFX", skin = "Skins" } -- the retired pack that owns a whole category
P.ROLL_SIZES = { 1, 5, 10 } -- (2026-11-08) the amounts the shop sells; ShopService accepts only these
P.ROLLS = {} -- cat -> its single-roll item
P.ROLL_BULK = {} -- cat -> { [count] = its bulk roll item }
for _, it in ipairs(P.ITEMS) do
	if it.kind == "roll" then
		local n = tonumber(it.count) or 1
		if n <= 1 then
			P.ROLLS[it.cat] = it
		else
			P.ROLL_BULK[it.cat] = P.ROLL_BULK[it.cat] or {}
			P.ROLL_BULK[it.cat][n] = it
		end
	end
end
-- (2026-11-09) GIFTS: what the GIFTS tab can buy for another player (ShopService.Ext.Gifting checks it too). Perks
-- (not retired / offers / game passes), rolls, emote pages, gadget crates and Yen packs; not the server-wide boosts.
function P.giftable(it)
	if type(it) ~= "table" or it.retired or it.offer or it.pass ~= nil then
		return false
	end
	if it.kind == "perk" or it.kind == "roll" or it.kind == "emotePage" or it.kind == "gadgetCrate" then
		return true
	end
	return it.kind == "consumable" and type(it.yen) == "number"
end

-- the roll item for `n` rolls of `cat` (nil when that size isn't sold)
function P.rollItem(cat, n)
	n = tonumber(n) or 1
	if n <= 1 then
		return P.ROLLS[cat]
	end
	return P.ROLL_BULK[cat] and P.ROLL_BULK[cat][n]
end
-- the skins in roster order (P.SKINS is kit id -> skin name)
P.SKIN_ORDER = { "Limitless", "Vulpine", "Godspeed", "OneForAll", "Tempest", "Carver", "Shifter", "Zangetsu", "Ascendant", "Gomu", "Stormdraw" }
-- what each skin turns a fighter's moves to (the shop's preview colours)
P.SKIN_COLORS = {
	Limitless = { C(255, 80, 100), C(70, 0, 25) },
	Vulpine = { C(255, 95, 70), C(130, 0, 25) },
	Godspeed = { C(205, 150, 255), C(80, 25, 185) },
	OneForAll = { C(255, 70, 70), C(95, 0, 15) },
	Tempest = { C(130, 220, 255), C(20, 75, 205) },
	Carver = { C(250, 240, 222), C(125, 105, 85) },
	Shifter = { C(205, 250, 255), C(60, 165, 225) },
	Zangetsu = { C(255, 255, 255), C(150, 160, 195) },
	Ascendant = { C(125, 205, 255), C(20, 60, 205) },
	Gomu = { C(255, 85, 75), C(145, 10, 25) },
	Stormdraw = { C(150, 215, 255), C(40, 90, 230) },
}
-- everything a roll of `cat` can give: { id, name } in display order
-- all = true includes EXCLUSIVE items (code-only); without it the pool is what rolls / odds / counts use
function P.isExclusive(cat, id)
	if cat == "emote" then
		for _, e in ipairs(P.EMOTES) do
			if e.id == id then
				return e.exclusive == true
			end
		end
	end
	return false
end
function P.pool(cat, all)
	local out = {}
	if cat == "emote" then
		for _, e in ipairs(P.EMOTES) do
			if all or not e.exclusive then
				table.insert(out, { id = e.id, name = e.name })
			end
		end
	elseif cat == "ko" then
		for _, k in ipairs(P.KO) do
			table.insert(out, { id = k.id, name = k.name })
		end
	elseif cat == "skin" then
		for _, kit in ipairs(P.SKIN_ORDER) do
			if P.SKINS[kit] then
				table.insert(out, { id = kit, name = P.SKINS[kit] })
			end
		end
	end
	return out
end

function P.reindex() -- call after product ids change at runtime (tests)
	table.clear(P.byProduct)
	table.clear(P.byPass)
	for _, it in ipairs(P.ITEMS) do
		if type(it.product) == "number" and it.product > 0 then
			P.byProduct[it.product] = it
		end
		if type(it.pass) == "number" and it.pass > 0 then
			P.byPass[it.pass] = it
		end
	end
end
P.reindex()

-- tuning (read by the systems that apply each perk) -----------------------------------------------------------------
P.TUNING = {
	YEN_MUL = 2,          -- YenX2
	VIP_YEN_MUL = 1.25,   -- VIP (stacks: both = 2.5x)
	COOLDOWN_MUL = 0.7,   -- Cooldowns: every ability cooldown x0.7
	ULT_CHARGE_MUL = 0.6, -- UltCharge: the ultimate's cooldown x0.6 (stacks with COOLDOWN_MUL)
	SPEED_MUL = 2,        -- SpeedX2: multiplies whatever WalkSpeed the kit sets
	JUMP_HEIGHT_MUL = 2,  -- JumpX2: jump HEIGHT x2, capped below the lowest building roof (movement system)
	DASH_COOLDOWN_MUL = 0.5, -- DashPass (game pass): the Shift dash cooldown x0.5 (player attribute DashCooldownMul)
	SPAWN_CAP_MUL = 3,    -- SpawnPlus (2026-11-14): the spawn menu caps x3 (player attribute SpawnCapMul)
}

-- cosmetic choices (ids are what the equip attributes hold) ---------------------------------------------------------
P.TRAILS = {
	{ id = "Rainbow", name = "RAINBOW" },
	{ id = "Gold", name = "GOLD" },
	{ id = "BlackFlame", name = "BLACK FLAME" },
}
P.KO = {
	{ id = "Confetti", name = "CONFETTI" },
	{ id = "Explosion", name = "EXPLOSION" },
	{ id = "Lightning", name = "LIGHTNING" },
	-- (2026-11-14, sandbox shop) six more, drawn by StarterPlayerScripts.PerkFXClient. nopack = the retired KO Effects
	-- pack (and the Starter Pack that holds it) does not include them: it was sold as the three above.
	{ id = "BlackHole", name = "BLACK HOLE", nopack = true },
	{ id = "Firework", name = "FIREWORK", nopack = true },
	{ id = "Frozen", name = "FROZEN", nopack = true },
	{ id = "Soul", name = "SOUL", nopack = true },
	{ id = "Pixel", name = "PIXELATE", nopack = true },
	{ id = "MiniNuke", name = "MINI NUKE", nopack = true },
}
-- does the retired pack of `cat` (P.LEGACY) include this item? (every item but the `nopack` ones)
function P.packIncludes(cat, id)
	if cat == "ko" then
		for _, k in ipairs(P.KO) do
			if k.id == id then
				return k.nopack ~= true
			end
		end
	end
	return true
end
P.EMOTES = {
	{ id = "Taunt", name = "TAUNT" },
	{ id = "Laugh", name = "LAUGH" },
	{ id = "Victory", name = "VICTORY" },
	-- (2026-11-07) nine more; their clips live in PerkShared.Emotes.Clips child packs (an id with no clip is hidden)
	{ id = "Wave", name = "WAVE" },
	{ id = "Bow", name = "BOW" },
	{ id = "Clap", name = "CLAP" },
	{ id = "Dance", name = "DANCE" },
	{ id = "Flex", name = "FLEX" },
	{ id = "Shrug", name = "SHRUG" },
	{ id = "PowerUp", name = "POWER UP" },
	{ id = "Pose", name = "POSE" },
	{ id = "Facepalm", name = "FACEPALM" },
	-- (2026-11-11, wiki extras) one of every emote KIND (PerkShared.Emotes.Clips.PackD): walking, partner, next to a KO'd
	-- body, interactive, lasting - and an EXCLUSIVE one (exclusive = true: never rolled or shown in the odds, only codes)
	{ id = "Strut", name = "STRUT" },
	{ id = "BunnyHop", name = "BUNNY HOP" },
	{ id = "HighFive", name = "HIGH FIVE" },
	{ id = "HypeCircle", name = "HYPE CIRCLE" },
	{ id = "PayRespects", name = "PAY RESPECTS" },
	{ id = "FlagPlant", name = "FLAG PLANT" },
	{ id = "Sign", name = "SIGN" },
	{ id = "Firework", name = "FIREWORK" },
	{ id = "GlowUp", name = "GLOW UP" },
	{ id = "NeonSalute", name = "NEON SALUTE", exclusive = true },
}
-- one alternate colourway per fighter (kit id -> skin name); each kit implements its own "Alt" look
P.SKINS = {
	Limitless = "CRIMSON VOID",
	Vulpine = "CRIMSON FOX",
	Godspeed = "VIOLET STORM",
	OneForAll = "CRIMSON COWL",
	Tempest = "AZURE SUSANOO",
	Carver = "BONE KING",
	Shifter = "CRYSTAL TITAN",
	Zangetsu = "WHITE BANKAI",
	Ascendant = "GOD BLUE",
	Gomu = "CRIMSON GEAR",
	Stormdraw = "AZURE THUNDER",
}

return P
