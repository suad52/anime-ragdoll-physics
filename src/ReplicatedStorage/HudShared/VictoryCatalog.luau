--!nocheck
-- HudShared.VictoryCatalog (2026-11-11, "wiki extras"): VICTORY FLASHES - the short full-screen cutscene the WINNER of a
-- duel shows both fighters (HudShared.VictoryFlash draws them; ServerScriptService.DuelService plays the winner's
-- equipped one). Crown is free; the rest cost YEN (shop VICTORY tab -> ShopRequest "victoryBuy") or ROBUX (PerkCatalog
-- items of kind "victory", one developer product each). Owned / equipped live in ShopService.Ext.Victory (player
-- attributes VictoryOwned = JSON list, VictoryFlash = equipped id). All designs are our own.
local C = Color3.fromRGB
local V = {}

V.DURATION = 3.6 -- seconds on screen
V.DEFAULT = "Crown"
V.YEN = 1000

V.LIST = {
	{ id = "Crown", name = "Neon Crown", glyph = "王", style = "crown", c0 = C(255, 214, 70), c1 = C(255, 120, 40), free = true },
	{ id = "Thunder", name = "Thunderclap", glyph = "雷", style = "thunder", c0 = C(255, 245, 140), c1 = C(90, 120, 255) },
	{ id = "Sakura", name = "Sakura Storm", glyph = "桜", style = "petals", c0 = C(255, 170, 205), c1 = C(150, 60, 120) },
	{ id = "Shatter", name = "Shattered", glyph = "破", style = "shatter", c0 = C(140, 240, 255), c1 = C(30, 60, 120) },
	{ id = "Spotlight", name = "Spotlight", glyph = "星", style = "spotlight", c0 = C(255, 250, 230), c1 = C(20, 18, 30) },
	{ id = "Inferno", name = "Inferno", glyph = "炎", style = "flames", c0 = C(255, 200, 60), c1 = C(200, 30, 20) },
	{ id = "Void", name = "Void Walker", glyph = "虚", style = "void", c0 = C(190, 120, 255), c1 = C(15, 5, 40) },
}
V.byId = {}
for i, f in ipairs(V.LIST) do
	f.order = i
	V.byId[f.id] = f
end

return V
