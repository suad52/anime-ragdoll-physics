--!nocheck
-- HudShared.GadgetCatalog (2026-11-09, shop expansion): one-use GADGETS - the shop's consumables. Bought one at a time
-- for Yen (shop GADGETS tab -> ShopRequest "buyGadget") or 6 random ones in the Robux Gadget Crate (PerkCatalog
-- "GadgetCrate"). Counts are saved in the profile (ShopService.Ext.Gadgets, player attribute Gadgets = JSON {id = n}).
-- Used from the gadget bar (StarterPlayerScripts.GadgetBar: keys 1-5 or tap) -> ShopRequest "useGadget"; the server
-- spends one and makes the effect (Ext.Gadgets).
local C = Color3.fromRGB
local G = {}

G.MAX = 99          -- most of one gadget a player can hold
G.GLOBAL_CD = 1     -- seconds between any two gadgets

G.LIST = {
	{ id = "Smoke", name = "Smoke Bomb", glyph = "煙", yen = 250, cooldown = 12, color = C(170, 170, 190),
		desc = "A thick smoke cloud bursts at your feet and hangs for 6 seconds.", secs = 6, radius = 14 },
	{ id = "Decoy", name = "Decoy", glyph = "影", yen = 300, cooldown = 15, color = C(150, 120, 255),
		desc = "A frozen copy of you stands where you were for 8 seconds.", secs = 8 },
	{ id = "Pad", name = "Boost Pad", glyph = "跳", yen = 200, cooldown = 12, color = C(80, 220, 255),
		desc = "A pad that flings anyone who steps on it forward. Lasts 15 seconds.", secs = 15, push = 85, lift = 38 },
	{ id = "Bubble", name = "Bubble Shield", glyph = "泡", yen = 400, cooldown = 30, color = C(120, 230, 255),
		desc = "Nothing can hit you for 2.5 seconds.", secs = 2.5 },
	{ id = "Snack", name = "Snack", glyph = "食", yen = 150, cooldown = 20, color = C(255, 170, 90),
		desc = "Heals 30 health over 3 seconds.", secs = 3, heal = 30 },
}
G.byId = {}
for i, g in ipairs(G.LIST) do
	g.order = i
	G.byId[g.id] = g
end

return G
