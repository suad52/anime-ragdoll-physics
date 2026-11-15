--!nocheck
-- ServerStorage.ShopCodes (2026-11-09): the codes players can redeem in the shop's CODES tab (ShopService.Ext.Codes).
-- Server-only (players can't read this list). Keys are the code in CAPITALS; players can type it in any case.
-- Each code, once per player:
--   yen = n          adds n Yen (never multiplied by 2x Yen / VIP)
--   rolls = { emote = n, skin = n, ko = n }   free random rolls (equal odds, never a duplicate)
--   picks = { emote = n, ... }                free "choose it yourself" picks (used in the RANDOM tab)
--   expires = os.time({ year = 2026, month = 12, day = 31, hour = 23 })   (nil = never)
--   active = false   switches a code off without deleting it
--   emotes = { "Id", ... }   those exact emotes - the only way to get EXCLUSIVE ones (PerkCatalog.EMOTES exclusive)
return {
	-- Real codes removed from the public repo.
	EXAMPLECODE = { yen = 100 },
}
