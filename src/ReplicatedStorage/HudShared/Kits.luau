-- ReplicatedStorage.HudShared.Kits: the character roster + the HUD's fonts, shared by CharacterSelect (top-left
-- dropdown) and MoveDock (bottom move bar). Names are private-test labels; swap them for originals before publishing.
-- (2026-11-15, owner: "change the names in the game to be non copyrighted") original fighter names; the ids stay as the
-- code's keys. Move names are renamed on screen by HudShared.Theme.RENAME.
local C = Color3.fromRGB
local M = {}

M.list = {
	{ id = "Limitless", name = "SORA", sub = "INFINITE VOID", title = "Infinite Void", glyph = "∞", c0 = C(240, 232, 255), c1 = C(116, 74, 255), accent = C(176, 148, 255) },
	{ id = "Vulpine", name = "KIT", sub = "FOX SAGE", title = "Fox Sage", glyph = "狐", c0 = C(220, 245, 255), c1 = C(70, 150, 255), accent = C(255, 160, 60) },
	{ id = "Godspeed", name = "VOLT", sub = "LIGHTNING STEP", title = "Lightning Step", glyph = "雷", c0 = C(245, 250, 255), c1 = C(95, 200, 255), accent = C(160, 225, 255) },
	{ id = "OneForAll", name = "MAX", sub = "FULL POWER", title = "Full Power", glyph = "全", c0 = C(230, 255, 240), c1 = C(30, 200, 110), accent = C(90, 240, 150) },
	{ id = "Tempest", name = "RAIKO", sub = "STORM EYE", title = "Storm Eye", glyph = "瞳", c0 = C(240, 235, 255), c1 = C(130, 70, 255), accent = C(175, 140, 255) },
	{ id = "Carver", name = "ONI", sub = "CURSED BLADES", title = "Cursed Blades", glyph = "廟", c0 = C(255, 226, 226), c1 = C(210, 22, 42), accent = C(255, 90, 100) },
	{ id = "Shifter", name = "TITUS", sub = "GIANT FORM", title = "Giant Form", glyph = "巨", c0 = C(220, 255, 230), c1 = C(40, 170, 100), accent = C(110, 225, 160) },
	{ id = "Zangetsu", name = "REN", sub = "SOUL BLADE", title = "Soul Blade", glyph = "斬", c0 = C(255, 244, 232), c1 = C(255, 128, 30), accent = C(255, 160, 80) },
	{ id = "Ascendant", name = "KAI", sub = "KI MASTER", title = "Ki Master", glyph = "気", c0 = C(236, 250, 255), c1 = C(255, 160, 30), accent = C(255, 205, 80) },
	{ id = "Gomu", name = "BOING", sub = "RUBBER FIST", title = "Rubber Fist", glyph = "麦", c0 = C(255, 246, 228), c1 = C(220, 32, 40), accent = C(255, 204, 60) },
	{ id = "Stormdraw", name = "ZAP", sub = "THUNDER STEP", title = "Thunder Step", glyph = "閃", c0 = C(255, 250, 215), c1 = C(255, 186, 20), accent = C(255, 214, 64) },
	-- (2026-11-13) NOT an anime fighter. The owner: "make it to where normal weapons are one of the options". No kit script
	-- answers to this id, so there are no moves at all - only the shared punch (which every kit has) and the sandbox's
	-- bat / axe / katana / sledgehammer / gun. noPowers is what the HUD reads: MoveDock shows the name and health bar
	-- alone, SandboxClient turns hotbar slot 1 into plain FISTS, CharacterSelect lists it first, StarterSelect and the
	-- skin list leave it out. Free for everyone (ShopCatalog.KITS.FREE). It is LAST here on purpose: ShopService gives
	-- a player the first fighter they own in this order, and Kits.list[1] is the fallback look.
	{ id = "Normal", name = "NORMAL", sub = "WEAPONS ONLY", title = "Weapons Only", glyph = "拳", noPowers = true, c0 = C(246, 246, 250), c1 = C(104, 110, 128), accent = C(206, 210, 222) },
}
M.byId = {}
for i, k in ipairs(M.list) do
	k.order = i
	M.byId[k.id] = k
end
M.default = "Limitless"

function M.current(player)
	return M.byId[player:GetAttribute("Kit") or M.default] or M.list[1]
end

-- fonts (2026-11-13): ONE clean sans everywhere. These were a brush title (PermanentMarker), comic numerals (Bangers)
-- and a condensed label face (Oswald); the owner sent a reference HUD and asked for the anime UI to keep its colours
-- but take "the same font as the rest - it doesn't have to be the odd cursive". Gotham is wider than all three, so
-- every label that reads these is TextScaled or was checked after the change.
local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"
M.FONT_TITLE = Font.new(GOTHAM, Enum.FontWeight.Bold)
M.FONT_PUNCH = Font.new(GOTHAM, Enum.FontWeight.Bold)
M.FONT_LABEL = Font.new(GOTHAM, Enum.FontWeight.Bold)
M.FONT_SMALL = Font.new(GOTHAM, Enum.FontWeight.Medium)

M.INK = C(10, 10, 16)
M.PANEL = C(16, 15, 26)
M.PANEL2 = C(26, 24, 42)
M.WHITE = C(255, 255, 255)
M.HP = C(70, 230, 120)
M.HP2 = C(20, 170, 90)

return M
