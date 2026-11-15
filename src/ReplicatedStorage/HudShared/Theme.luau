--!nocheck
-- ReplicatedStorage.HudShared.Theme (2026-11-14): the BRIGHT CARTOON look and the no-kanji rule. The owner asked to
-- "change the theme of the ui" (picked: light panels, chunky rounded shapes, a bubbly bold font, saturated colours) and
-- to "remove the kanji" from all the UI. StarterPlayerScripts.ThemeApplier applies this to every screen GUI live;
-- scripts that draw their own pieces can read the palette and helpers here.
local Theme = {}
local C = Color3.fromRGB
-- (2026-11-14, owner: "make it the same colours" -> "back to the old colours", "black") the light recolouring is OFF:
-- the UI keeps its original dark colours. ThemeApplier still sets the font and strips the kanji. true = light again.
Theme.COLOURS = false
Theme.FONT = Font.fromEnum(Enum.Font.FredokaOne)
Theme.NAVY = C(36, 44, 78) -- text on light fills, every outline
Theme.WHITE = C(255, 255, 255)
Theme.GOLD = C(255, 206, 70) -- the "selected" colour
Theme.SKY = C(120, 196, 255)

function Theme.lum(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end
-- a dark fill -> its light counterpart: a pale tint of the same hue; darker ones stay a shade deeper, so a dark step
-- (a hover, a selected row) still reads as a step. Anything not dark is left as it is (buttons, accents, art).
-- A strong colour (a red button, a blue badge) is never "dark" however low its luminance: only greys and deep shades are.
function Theme.lightBg(c)
	local L = Theme.lum(c)
	if L >= 0.32 then
		return c
	end
	local h, s, v = c:ToHSV()
	if s >= 0.45 and v >= 0.45 then
		return c
	end
	return Color3.fromHSV(h, math.min(s, 0.7) * 0.22, 1 - L * 0.42)
end
-- text colour for a light fill: white-ish -> navy; a pale accent -> a deep shade of its hue; dark text stays
Theme.MUTED = C(98, 106, 134) -- secondary text on a light fill
function Theme.inkOnLight(c)
	local L = Theme.lum(c)
	local h, s = c:ToHSV()
	if s < 0.25 then
		if L > 0.72 then
			return Theme.NAVY
		elseif L > 0.42 then
			return Theme.MUTED -- the dim greys of captions / hints
		end
		return c
	end
	if L > 0.45 then
		return Color3.fromHSV(h, math.max(s, 0.65), 0.6)
	end
	return c
end

-- NO KANJI: hiragana, katakana, CJK ideographs, CJK punctuation and full-width forms are dropped; the katakana middle
-- dot (a separator here) becomes a dash; the rest is tidied, and if no letter or digit is left the result is "".
local function cjk(cp)
	return (cp >= 0x3000 and cp <= 0x30FF) or (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0xFF00 and cp <= 0xFFEF)
end
function Theme.hasCJK(s)
	if type(s) ~= "string" or s == "" then
		return false
	end
	local ok, res = pcall(function()
		for _, cp in utf8.codes(s) do
			if cjk(cp) then
				return true
			end
		end
		return false
	end)
	return ok and res
end
function Theme.strip(s)
	if not Theme.hasCJK(s) then
		return s
	end
	local out = {}
	for _, cp in utf8.codes(s) do
		if cp == 0x30FB then
			table.insert(out, "-")
		elseif not cjk(cp) then
			table.insert(out, utf8.char(cp))
		end
	end
	local r = table.concat(out)
	r = r:gsub("[ \t]+", " ")
	r = r:gsub(" ?%- ?%- ?", " - ")
	r = r:gsub("\n ", "\n")
	r = r:gsub(" \n", "\n")
	r = r:gsub("^[%s%-]+", "")
	r = r:gsub("[%s%-]+$", "")
	if not r:find("%w") then
		return ""
	end
	return r
end
-- RENAME (2026-11-15, owner: "change the names in the game to be non copyrighted"): move and form names from anime series,
-- swapped on screen for original ones. Whole words, any case (an all-caps label gets the caps version). Longer names
-- first, so RASENSHURIKEN wins over RASENGAN and DOMAIN EXPANSION over DOMAIN. Fighter names live in HudShared.Kits.
Theme.RENAME = {
	{ "Tensa Zangetsu", "True Blade" },
	{ "Sun God Nika", "Sun God" },
	{ "the rumbling", "the stampede" },
	{ "Titan Slayer", "Giant Slayer" },
	{ "Crystal Titan", "Crystal Giant" },
	{ "Zangetsu", "Soul Blade" },
	{ "Instant Transmission", "Teleport" }, { "Domain Expansion", "Infinite Zone" }, { "Unlimited Void", "Infinite Zone" },
	{ "Rasenshuriken", "Spiral Star" }, { "Rasengan", "Spiral Orb" }, { "Sage Mode", "Nature Mode" }, { "Kurama", "Fox Beast" },
	{ "Tailed Beast Bomb", "Beast Blast" }, { "Hollow Purple", "Void Blast" }, { "Lapse Blue", "Pull Orb" }, { "Reversal Red", "Push Orb" },
	{ "Getsuga Tensho", "Moon Slash" }, { "Getsuga", "Moon Slash" }, { "Shunpo", "Flash Step" }, { "Hollow Mask", "Demon Mask" }, { "Bankai", "Final Blade" },
	{ "Dismantle", "Slice" }, { "Fuga", "Flame Arrow" }, { "World Cut", "Rift Cut" }, { "Malevolent Shrine", "Cursed Zone" },
	{ "Founding Titan", "Elder Giant" }, { "Attack Titan", "Giant Form" }, { "Colossal Titan", "Colossus" }, { "Colossal", "Colossus" },
	{ "ODM Gear", "Grapple Gear" }, { "Thunder God", "Storm King" }, { "Sixfold", "Six Strike" }, { "Thunder Breathing", "Thunder Step" },
	{ "Gum-Gum", "Stretch" }, { "Gum Gum", "Stretch" }, { "Gatling", "Barrage" }, { "Elephant Gun", "Giant Fist" }, { "Gear Fifth", "Toon Mode" },
	{ "Gear 5", "Toon Mode" }, { "Bajrang Gun", "Mega Fist" }, { "Rhythm Echo", "Echo Step" }, { "Godspeed", "Lightning Rush" },
	{ "Chidori", "Lightning Blade" }, { "Kirin", "Sky Dragon" }, { "Rinnesharingan", "Storm Eye" }, { "Sharingan", "Storm Eye" },
	{ "Susanoo", "Spirit Giant" }, { "Indra's Arrow", "Spirit Arrow" }, { "Kamehameha", "Ki Wave" }, { "Super Saiyan", "Golden Form" },
	{ "Ultra Instinct", "Silver Sense" }, { "Detroit Smash", "Mega Smash" }, { "Blackwhip", "Shadow Whip" }, { "One For All", "Full Power" },
	{ "Limitless", "Infinite Void" }, { "Soul Reaper", "Soul Blade" }, { "Straw Hat", "Rubber Fist" }, { "Cursed Shrine", "Cursed Blades" },
	{ "Titan Shifter", "Giant Form" }, { "Sage Arts", "Fox Sage" },
}
table.sort(Theme.RENAME, function(a, b)
	return #a[1] > #b[1]
end)
local function isLetter(ch)
	return ch ~= "" and ch:match("%a") ~= nil
end
-- does any rename apply? (cheap check first: most labels have none)
function Theme.rename(s)
	if type(s) ~= "string" or s == "" then
		return s
	end
	local low = s:lower()
	for _, r in ipairs(Theme.RENAME) do
		local key = r[1]:lower()
		local from = 1
		while true do
			local a, b = low:find(key, from, true)
			if not a then
				break
			end
			if not isLetter(low:sub(a - 1, a - 1)) and not isLetter(low:sub(b + 1, b + 1)) then
				local orig = s:sub(a, b)
				local rep = (orig == orig:upper()) and r[2]:upper() or r[2]
				s = s:sub(1, a - 1) .. rep .. s:sub(b + 1)
				low = s:lower()
				from = a + #rep
			else
				from = b + 1
			end
		end
	end
	return s
end
return Theme
