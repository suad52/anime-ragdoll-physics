--!nocheck
-- CharacterSelect (rewritten 2026-11-07): the top-left strip that starts right of Roblox's own buttons (mic), in
-- GuiService.TopbarInset - a CHARACTER dropdown pill and a SHOP pill (wallet) that opens the anime-styled 2D shop.
-- The server owns the choice (player attribute "Kit", switched through VulpineKit.Remotes.Request "SetKit") and
-- the wallet (ServerScriptService.ShopService; attributes Yen / ShopOwned / ShopAura / ShopTitle).
-- The old card strip is in ServerStorage.UIBackup_2026-11-07.CharacterSelect.
-- Locked fighters (2026-11-07): rows for fighters not in KitsOwned show a padlock and two unlock buttons - Yen
-- (ShopRequest "buyKit") and Robux (the fighter's game pass, Catalog.KITS.PASSES). The first-join pick is StarterSelect.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local KitRequest = ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("Remotes"):WaitForChild("Request")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local Catalog = require(shared:WaitForChild("ShopCatalog"))
local ShopRequest = shared:WaitForChild("ShopRequest", 20)
-- Robux perks (2026-11-07): PerkCatalog is the one source of truth (names, prices, product ids read at runtime)
local PerkCatalog = require(shared:WaitForChild("PerkCatalog"))
local PerkShared = ReplicatedStorage:WaitForChild("PerkShared", 10)

local WHITE, INK, PANEL, PANEL2 = Kits.WHITE, Kits.INK, Kits.PANEL, Kits.PANEL2
local GOLD, GOLD2 = Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 150, 20)
local RED, RED2 = Color3.fromRGB(255, 50, 90), Color3.fromRGB(150, 20, 90)
local PILL_H = 40
local MarketplaceService = game:GetService("MarketplaceService")
local KCFG = Catalog.KITS or {}
local KIT_YEN = KCFG.PRICE_YEN or 2000
local PREMIUM = KCFG.PREMIUM or {} -- Robux-only fighters: a PREMIUM tag and the Robux button, no Yen price
-- (2026-11-09) fighters in development (KITS.EARLY): an EARLY ACCESS tag, no Yen price, and the Robux button sells the
-- Early Access pass (PerkCatalog "EarlyAccess"), which unlocks every one of them
local EARLY = KCFG.EARLY or {}
local function ownedKits()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("KitsOwned") or "[]")
	end)
	local set = {}
	for _, id in ipairs(ok and type(list) == "table" and list or {}) do
		set[id] = true
	end
	return set
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, p)
end
local function stroke(p, color, th, tr)
	return new("UIStroke", { Color = color or INK, Thickness = th or 1.5, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, Text = "", FontFace = Kits.FONT_PUNCH }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function inkText(t, th)
	new("UIStroke", { Color = INK, Thickness = th or 1.5 }, t)
	return t
end
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function fmtYen(n)
	local s = tostring(math.floor(n or 0))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return Catalog.CURRENCY .. " " .. s
end
-- (2026-11-14) the fighter emblem, for the bright theme and with no kanji (owner: "remove the kanji"): a medallion -
-- the kit's colours as the rim, a sunken face in the same colours, and on it the fighter's POWER drawn from HudShared.Icons (kit_<id>: a
-- void orb, a fox, a bolt...). Callers still get (disc, gradient, glyph) and still write kit.glyph into the glyph label
-- when the fighter changes: the label is never shown, and the drawing follows whichever kit that glyph belongs to.
-- The root is named "Emblem" so the theme pass leaves it alone; artOrb hides the face (EmblemDeco) when it draws art.
local Icons
pcall(function()
	Icons = require(shared:WaitForChild("Icons", 10))
end)
local GLYPH_KIT = {}
for _, k in ipairs(Kits.list) do
	GLYPH_KIT[k.glyph] = k.id
end
local function emblem(parent, size, kit, pos)
	local e = new("Frame", { Name = "Emblem", Size = UDim2.fromOffset(size, size), Position = pos or UDim2.new(0, 4, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, parent)
	corner(e)
	local g = new("UIGradient", { Color = ColorSequence.new(kit.c0, kit.c1), Rotation = 45 }, e)
	stroke(e, INK, math.max(1.5, size / 30))
	local face = new("Frame", { Name = "EmblemDeco", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.78, 0.78),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, e)
	corner(face)
	-- (2026-11-14, owner: back to the old colours) the face is the sunken one again: the kit's colours lit from the other
	-- side, a light ring, a gloss - and the power drawn over it
	local fg = new("UIGradient", { Rotation = 225 }, face)
	new("UIStroke", { Color = WHITE, Thickness = 1.2, Transparency = 0.3 }, face)
	local function follow()
		local k = g.Color.Keypoints
		local a, b = k[1].Value, k[#k].Value
		fg.Color = ColorSequence.new(a:Lerp(b, 0.3), b:Lerp(INK, 0.18))
	end
	follow()
	g:GetPropertyChangedSignal("Color"):Connect(follow)
	local gloss = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromScale(0.7, 0.34),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, face)
	corner(gloss)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }, gloss)
	local box = new("Frame", { Name = "EmblemIcon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.66, 0.66),
		BackgroundTransparency = 1 }, face)
	local gl = label(e, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), Text = kit.glyph, TextTransparency = 1 })
	local function draw()
		box:ClearAllChildren()
		if Icons then
			pcall(Icons.draw, "kit_" .. (GLYPH_KIT[gl.Text] or kit.id), box, { stroke = (size >= 60) and 1.1 or 0.7 })
		end
	end
	draw()
	gl:GetPropertyChangedSignal("Text"):Connect(draw)
	return e, g, gl
end

-- CardArt (2026-11-10): HudShared.CardArt draws item art (what the item IS, not a kanji) for the shop + inventory.
-- CardArt.draw(container, item, opts) -> true when it drew into container (children named CardArt_*); false = no
-- art, and the old glyph orb stays exactly as it was. A failed require keeps every glyph.
local CardArt
pcall(function()
	local m = require(shared:WaitForChild("CardArt", 10))
	if type(m) == "table" and type(m.draw) == "function" then
		CardArt = m
	end
end)
local function drawArt(container, item, opts)
	if not (CardArt and container and type(item) == "table") then
		return false
	end
	local ok, drew = pcall(CardArt.draw, container, item, opts)
	if ok and drew == true then
		return true
	end
	for _, c in ipairs(container:GetChildren()) do -- a draw that failed half way leaves nothing behind
		if string.sub(c.Name, 1, 8) == "CardArt_" then
			c:Destroy()
		end
	end
	return false
end
-- art in place of a glyph orb / emblem `o`: a clear square slot centred on it (`scale` x its size). Drew -> the orb's
-- disc, ring and glyph hide; no art -> the orb is left as it was. Safe to call again (it redraws; item nil = the orb).
local function artOrb(o, item, scale, opts)
	local old = o:FindFirstChild("ArtSlot")
	if old then
		old:Destroy()
	end
	if o:GetAttribute("OrbBgT") == nil then
		o:SetAttribute("OrbBgT", o.BackgroundTransparency)
	end
	local slot = new("Frame", { Name = "ArtSlot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale or 1, scale or 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = o.ZIndex + 1 }, o)
	local drew = drawArt(slot, item, opts)
	if not drew then
		slot:Destroy()
	end
	o.BackgroundTransparency = drew and 1 or o:GetAttribute("OrbBgT")
	for _, c in ipairs(o:GetChildren()) do
		if c:IsA("UIStroke") then
			c.Enabled = not drew
		elseif c:IsA("TextLabel") or c.Name == "EmblemDeco" then -- (2026-11-14) and the medallion's face / gloss
			c.Visible = not drew
		end
	end
	return drew
end

local gui = new("ScreenGui", { Name = "CharacterSelect", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- ZIndex 35: the pills sit ABOVE the shop / inventory shades (30), so SHOP <-> INVENTORY switch with one tap
local strip = new("Frame", { Name = "TopStrip", BackgroundTransparency = 1, Size = UDim2.fromOffset(600, PILL_H), ZIndex = 35 }, gui)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Center }, strip)

local function pill(order, width)
	local b = new("TextButton", { LayoutOrder = order, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(width, PILL_H),
		BackgroundColor3 = Color3.fromRGB(18, 18, 28), BackgroundTransparency = 0.22, BorderSizePixel = 0 }, strip)
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	local sc = new("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		tween(sc, 0.12, { Scale = 1.04 })
		tween(st, 0.12, { Transparency = 0 })
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.12, { Scale = 1 })
		tween(st, 0.12, { Transparency = 0.55 })
	end)
	return b, st, sc
end

-- CHARACTER pill ---------------------------------------------------------------------------------------
local charPill, charStroke = pill(1, 156)
charPill.Name = "FighterPill" -- HudRails files the pills by name
local charEmblem, charGrad, charGlyph = emblem(charPill, PILL_H - 8, Kits.list[1])
local charArtKit -- (2026-11-10) the fighter the pill's CardArt was last drawn for
local charName = inkText(label(charPill, { Position = UDim2.fromOffset(PILL_H + 2, 6), Size = UDim2.new(1, -PILL_H - 26, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Left }))
local charSub = label(charPill, { Position = UDim2.fromOffset(PILL_H + 2, 25), Size = UDim2.new(1, -PILL_H - 26, 0, 10),
	TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kits.FONT_LABEL })
-- a drawn chevron (fonts here have no reliable arrow glyph)
local chev = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(12, 12),
	BackgroundTransparency = 1 }, charPill)
for i, r in ipairs({ 45, -45 }) do
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(i == 1 and 0.32 or 0.68, 0, 0.5, 0), Size = UDim2.fromOffset(7, 2.5),
		Rotation = r, BackgroundColor3 = WHITE, BorderSizePixel = 0 }, chev)
end

-- SHOP pill ----------------------------------------------------------------------------------------------
local shopPill, shopStroke = pill(2, 138)
shopPill.Name = "ShopPill"
local coin = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(PILL_H - 8, PILL_H - 8),
	BackgroundColor3 = WHITE, BorderSizePixel = 0 }, shopPill)
corner(coin)
new("UIGradient", { Color = ColorSequence.new(GOLD, GOLD2), Rotation = 60 }, coin)
stroke(coin, INK, 1.5)
inkText(label(coin, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.17), Text = Catalog.CURRENCY }))
inkText(label(shopPill, { Position = UDim2.fromOffset(PILL_H + 2, 6), Size = UDim2.new(1, -PILL_H - 10, 0, 18), Text = "SHOP",
	TextXAlignment = Enum.TextXAlignment.Left }))
local walletText = label(shopPill, { Position = UDim2.fromOffset(PILL_H + 2, 24), Size = UDim2.new(1, -PILL_H - 10, 0, 11),
	TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kits.FONT_LABEL, TextColor3 = GOLD })

-- toast under the strip
local toast = inkText(label(gui, { Size = UDim2.fromOffset(360, 20), TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 }), 2)
toast:FindFirstChildOfClass("UIStroke").Transparency = 1
local toastToken
local function showToast(text, color)
	local token = {}
	toastToken = token
	toast.Text = text
	toast.TextColor3 = color or WHITE
	toast.TextTransparency = 0
	local st = toast:FindFirstChildOfClass("UIStroke")
	st.Transparency = 0
	task.delay(1.6, function()
		if toastToken == token then
			tween(toast, 0.4, { TextTransparency = 1 })
			tween(st, 0.4, { Transparency = 1 }) -- the outline fades too, or it lingers as a dark ghost
		end
	end)
end

-- Robux perks (2026-11-07) ------------------------------------------------------------------------------------------
-- Ownership is read from the attributes ShopService writes (Perks JSON + Perk_<Id>); buying is a developer-product
-- prompt (PerkCatalog product ids, 0 = COMING SOON); the INVENTORY (below the shop) equips through ShopRequest "perkEquip".
local PK = { priceText = {}, actions = {} } -- actions: named click handlers (Studio ClientDebug "InvClick")
function PK.set()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Perks") or "[]")
	end)
	local s = {}
	for _, id in ipairs(ok and type(list) == "table" and list or {}) do
		s[id] = true
	end
	return s
end
function PK.has(id)
	return player:GetAttribute("Perk_" .. id) == true or PK.set()[id] == true
end
function PK.product(it)
	return type(it.product) == "number" and it.product > 0 and it.product or nil
end
-- (2026-11-07) game-pass perks (PerkCatalog `pass`, e.g. Dash Master): bought with PromptGamePassPurchase
function PK.pass(it)
	return type(it.pass) == "number" and it.pass > 0 and it.pass or nil
end
function PK.buyable(it) -- a developer product or a game pass that exists (else the button says COMING SOON)
	return PK.product(it) or PK.pass(it)
end
function PK.price(it)
	return "R$ " .. tostring(PK.priceText[it.id] or it.price)
end
function PK.buy(it, say)
	say = say or showToast
	if it.retired then -- (2026-11-14) the retired PvP perks: owners keep them, nobody can buy them
		say(string.upper(it.name) .. " IS NO LONGER SOLD", GOLD)
		return
	end
	local pid = PK.product(it)
	local passId = PK.pass(it)
	if passId and not pid then
		if it.kind == "perk" and PK.has(it.id) then
			say("YOU ALREADY OWN " .. string.upper(it.name), GOLD)
		elseif not pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, passId) then
			say("PURCHASE UNAVAILABLE - TRY AGAIN", RED)
		end
		return
	end
	if not pid then
		say(string.upper(it.name) .. " - COMING SOON", GOLD)
	elseif player:GetAttribute("ShopOffline") then
		say("SHOP OFFLINE - REJOIN TO BUY", RED)
	elseif player:GetAttribute("KitsOwned") == nil then
		say("LOADING YOUR SAVE...", GOLD)
	elseif it.kind == "perk" and PK.has(it.id) then
		say("YOU ALREADY OWN " .. string.upper(it.name), GOLD)
	elseif not pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, pid) then
		say("PURCHASE UNAVAILABLE - TRY AGAIN", RED)
	end
end

-- (2026-11-07) emotes / KO effects / skins are owned one at a time (random rolls): the JSON id lists ShopService writes
local OWNED_ATTR = { emote = "OwnedEmotes", ko = "OwnedKO", skin = "OwnedSkins" }
function PK.owned(cat)
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute(OWNED_ATTR[cat]) or "[]")
	end)
	local s = {}
	for _, id in ipairs(ok and type(list) == "table" and list or {}) do
		s[id] = true
	end
	return s
end
function PK.owns(cat, id)
	return PK.owned(cat)[id] == true
end

-- INVENTORY pill: a drawn treasure chest, the owned-perk count, and a red "!" when a new perk arrives
local invPill = pill(3, 150)
invPill.Name = "InventoryPill"
-- (2026-11-14, ragdoll sandbox) owner: "remove the inventory stuff on the left side". The button is still built (the
-- code below writes its count and its "!" dot) but never shown: HudRails' left rail and the phone's top strip both skip
-- a hidden button. The inventory PANEL is untouched - tapping a perk you own in the shop still opens it.
invPill.Visible = false
local chest = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(PILL_H - 8, PILL_H - 8),
	BackgroundColor3 = WHITE, BorderSizePixel = 0 }, invPill)
corner(chest)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(90, 40, 200)), Rotation = 60 }, chest)
stroke(chest, INK, 1.5)
for _, part in ipairs({
	{ Vector2.new(0.5, 1), UDim2.new(0.5, 0, 0, 14), UDim2.fromOffset(20, 7), GOLD2 }, -- lid
	{ Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 14), UDim2.fromOffset(18, 10), GOLD }, -- box
}) do
	local f = new("Frame", { AnchorPoint = part[1], Position = part[2], Size = part[3], BackgroundColor3 = part[4], BorderSizePixel = 0 }, chest)
	corner(f, 3)
	stroke(f, INK, 1.5)
end
new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 15), Size = UDim2.fromOffset(4, 6), BackgroundColor3 = INK,
	BorderSizePixel = 0, ZIndex = 2 }, chest) -- the clasp
inkText(label(invPill, { Position = UDim2.fromOffset(PILL_H + 2, 6), Size = UDim2.new(1, -PILL_H - 10, 0, 18), Text = "INVENTORY",
	TextXAlignment = Enum.TextXAlignment.Left }))
local invSub = label(invPill, { Position = UDim2.fromOffset(PILL_H + 2, 24), Size = UDim2.new(1, -PILL_H - 10, 0, 11), Text = "MY PERKS",
	TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kits.FONT_LABEL, TextColor3 = Color3.fromRGB(205, 165, 255) })
local invDot = new("Frame", { Name = "NewDot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = RED, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, invPill)
corner(invDot)
stroke(invDot, WHITE, 1.5)
inkText(label(invDot, { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), Text = "!", ZIndex = 6 }), 1)

-- placement: right after Roblox's buttons, centred in the topbar row
local stripScale = new("UIScale", {}, strip)
local function place()
	local inset = GuiService.TopbarInset
	local h = math.max(inset.Height, 44)
	local x = (inset.Width > 0 and inset.Min.X or 104) + 8
	strip.Position = UDim2.fromOffset(x, inset.Min.Y + (h - PILL_H) / 2)
	toast.Position = UDim2.fromOffset(x + 4, inset.Min.Y + h + 6)
end
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
place()

-- CHARACTER dropdown --------------------------------------------------------------------------------------
local drop = new("Frame", { Name = "Characters", Visible = false, Size = UDim2.fromOffset(304, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(14, 13, 22), BackgroundTransparency = 0.06, BorderSizePixel = 0, ZIndex = 20 }, gui)
corner(drop, 14)
stroke(drop, WHITE, 1.5, 0.7)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, drop)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, drop)
local dropScale = new("UIScale", {}, drop)
local dropHeader = new("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, ZIndex = 21 }, drop)
inkText(label(dropHeader, { Size = UDim2.new(0.66, 0, 1, 0), Text = "CHOOSE YOUR FIGHTER", TextColor3 = Color3.fromRGB(200, 200, 220),
	TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 }))
local dropCount = label(dropHeader, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 3), Size = UDim2.new(0.34, 0, 1, -5), Text = "",
	FontFace = Kits.FONT_LABEL, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21 })

local rows = {}
local pending, pendingAt
local function currentKit()
	return player:GetAttribute("Kit") or Kits.default
end
-- (2026-11-11, owner: "character swap cooldown") after a switch the server refuses the next one until the player's
-- KitSwapReadyAt (server time; VulpineServer.KitServer.setKit writes it, PvPShared.Balance.KIT_SWAP_COOLDOWN long).
-- The menu counts it down ("SWAP IN 12s" on the pill and on the other fighters' rows, dimmed) and refuses locally with
-- a toast instead of sending a request that would only time out as "FINISH YOUR MOVE FIRST". SWAP_SLACK covers the
-- small drift between this client's GetServerTimeNow and the server's, so the menu never says ready a beat early.
local SWAP_SLACK = 0.15
local function swapLeft()
	if RunService:IsStudio() and player:GetAttribute("DevNoSwapCooldown") == true then
		return 0 -- the Studio test bypass KitServer honours too
	end
	local t = tonumber(player:GetAttribute("KitSwapReadyAt"))
	return t and math.max(0, t + SWAP_SLACK - workspace:GetServerTimeNow()) or 0
end
-- the whole seconds to SHOW (the slack is left out, so a 20 s cooldown reads 20, not 21)
local function swapSecs()
	return math.max(1, math.ceil(swapLeft() - SWAP_SLACK))
end
-- unlocked: the fighter just bought, whose auto-switch is what got refused (its toast keeps the UNLOCKED news)
-- returns false when the cooldown refused it
local function selectKit(id, unlocked)
	if id == currentKit() then
		return
	end
	if swapLeft() > 0 then
		local secs = swapSecs()
		showToast(unlocked and ("UNLOCKED: " .. unlocked.name .. "!  SWITCH TO IT IN " .. secs .. "s")
			or ("YOU CAN SWAP FIGHTERS AGAIN IN " .. secs .. "s"), unlocked and unlocked.accent or RED)
		for i = 1, 4 do
			task.delay(i * 0.04, function()
				charPill.Rotation = (i % 2 == 0) and -3 or 3
			end)
		end
		task.delay(0.2, function()
			charPill.Rotation = 0
		end)
		return false
	end
	pending, pendingAt = id, os.clock()
	KitRequest:FireServer("SetKit", { kit = id })
end

local setDrop
local buyKit, buyKitRobux -- unlocking, below
local paidPending = {} -- kit id -> true: Robux paid, unlock still on its way (its R$ button stays hidden)
local function shopReady() -- the profile has loaded (KitsOwned published) and did not fail (ShopOffline)
	return player:GetAttribute("KitsOwned") ~= nil and not player:GetAttribute("ShopOffline")
end
for i, kit in ipairs(Kits.list) do
	-- (2026-11-13) the no-powers NORMAL choice sits at the top of the list, above the anime fighters
	local r = new("TextButton", { LayoutOrder = kit.noPowers and 0 or i, AutoButtonColor = false, Text = "", Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.96, BorderSizePixel = 0, ZIndex = 21 }, drop)
	r.Name = "Row_" .. kit.id -- (so a test can click a row by path)
	corner(r, 10)
	local st = stroke(r, kit.accent, 1.5, 1)
	local inner = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 21 }, r)
	local e, eGrad = emblem(inner, 36, kit, UDim2.new(0, 5, 0.5, 0))
	e.ZIndex = 22
	for _, d in ipairs(e:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 23
		end
	end
	-- (2026-11-10) the owner asked for the dropdown to keep the kanji glyphs, so no CardArt here (it was
	-- artOrb(e, { kind = "fighter", kit = kit.id }, 1.15))
	local nameL = inkText(label(inner, { Position = UDim2.fromOffset(50, 6), Size = UDim2.new(1, -136, 0, 20), Text = kit.name,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 }))
	label(inner, { Position = UDim2.fromOffset(50, 27), Size = UDim2.new(1, -136, 0, 12), Text = kit.sub, FontFace = Kits.FONT_LABEL,
		TextColor3 = kit.accent, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local tag = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(62, 18),
		BackgroundColor3 = kit.accent, BorderSizePixel = 0, Visible = false, ZIndex = 22 }, inner)
	corner(tag)
	inkText(label(tag, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = "PLAYING", ZIndex = 23 }), 1)
	-- locked: a padlock on the emblem and the two ways to unlock it
	local lockIcon = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 35, 0, 33), Size = UDim2.fromOffset(16, 13),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, Visible = false, ZIndex = 24 }, inner)
	corner(lockIcon, 3)
	stroke(lockIcon, INK, 1.5)
	local shackle = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(10, 11),
		BackgroundTransparency = 1, ZIndex = 24 }, lockIcon)
	corner(shackle)
	new("UIStroke", { Color = GOLD, Thickness = 2.5 }, shackle)
	local function priceButton(top, text, color)
		local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, top), Size = UDim2.fromOffset(78, 18),
			AutoButtonColor = false, Text = "", BackgroundColor3 = color, BorderSizePixel = 0, Visible = false, ZIndex = 24 }, inner)
		corner(b, 6)
		stroke(b, INK, 1.5)
		local t = inkText(label(b, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = text, ZIndex = 25 }), 1)
		local sc = new("UIScale", {}, b)
		b.MouseEnter:Connect(function()
			tween(sc, 0.08, { Scale = 1.08 })
		end)
		b.MouseLeave:Connect(function()
			tween(sc, 0.08, { Scale = 1 })
		end)
		return b, t
	end
	local early = EARLY[kit.id] == true
	local premium = PREMIUM[kit.id] ~= nil or early
	local earlyItem = PerkCatalog.byId and PerkCatalog.byId.EarlyAccess
	local yenBtn = priceButton(4, fmtYen(KIT_YEN), GOLD)
	local rbxBtn, rbxText = priceButton(premium and 22 or 24, "R$ " .. tostring(early and (earlyItem and earlyItem.price or 345)
		or premium and PREMIUM[kit.id] or KCFG.PRICE_ROBUX or 25), Color3.fromRGB(70, 220, 130))
	local premTag
	if premium then
		premTag = inkText(label(inner, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5), Size = UDim2.fromOffset(78, 14),
			Text = early and "EARLY ACCESS" or "PREMIUM", TextColor3 = early and Color3.fromRGB(80, 230, 210) or GOLD, Visible = false, ZIndex = 24 }), 1)
	end
	rows[kit.id] = { button = r, stroke = st, inner = inner, tag = tag, kit = kit, eGrad = eGrad, nameL = nameL, lockIcon = lockIcon,
		yenBtn = yenBtn, rbxBtn = rbxBtn, rbxText = rbxText, premium = premium, premTag = premTag }
	yenBtn.Activated:Connect(function()
		buyKit(kit)
	end)
	rbxBtn.Activated:Connect(function()
		if early and earlyItem then
			PK.buy(earlyItem) -- the pass unlocks every fighter in development
			return
		end
		buyKitRobux(kit)
	end)
	r.MouseEnter:Connect(function()
		tween(r, 0.1, { BackgroundTransparency = 0.88 })
		tween(inner, 0.1, { Position = UDim2.fromOffset(4, 0) })
	end)
	r.MouseLeave:Connect(function()
		tween(r, 0.1, { BackgroundTransparency = (kit.id == currentKit()) and 0.9 or 0.96 })
		tween(inner, 0.1, { Position = UDim2.fromOffset(0, 0) })
	end)
	r.Activated:Connect(function()
		if not ownedKits()[kit.id] then
			showToast(early and (kit.name .. " IS IN EARLY ACCESS - GET THE EARLY ACCESS PASS TO PLAY IT")
				or PREMIUM[kit.id] and (kit.name .. " IS PREMIUM - R$" .. tostring(PREMIUM[kit.id]) .. ", ROBUX ONLY")
				or (kit.name .. " IS LOCKED - UNLOCK FOR " .. fmtYen(KIT_YEN) .. " OR ROBUX"), GOLD)
			for k = 1, 4 do
				task.delay(k * 0.04, function()
					inner.Position = UDim2.fromOffset((k % 2 == 0) and -3 or 3, 0)
				end)
			end
			task.delay(0.2, function()
				inner.Position = UDim2.fromOffset(0, 0)
			end)
			return
		end
		if selectKit(kit.id) == false then
			-- (2026-11-11) swap cooldown: the list stays open and the row shakes, like a locked one
			for k = 1, 4 do
				task.delay(k * 0.04, function()
					inner.Position = UDim2.fromOffset((k % 2 == 0) and -3 or 3, 0)
				end)
			end
			task.delay(0.2, function()
				inner.Position = UDim2.fromOffset(0, 0)
			end)
			return
		end
		setDrop(false)
	end)
end

-- (2026-11-11) the swap cooldown on screen: the pill's sub line and every OTHER owned fighter's row (dimmed, the
-- countdown where PLAYING sits on the current one) say "SWAP IN 12s" until KitSwapReadyAt passes. Locked rows keep
-- their unlock buttons - buying is never on cooldown. styleKit calls this last; the Heartbeat below redraws it only
-- when the whole seconds change.
local swapShown -- the whole seconds last drawn, nil = no cooldown on screen
local function styleSwap()
	local left = swapLeft()
	swapShown = left > 0 and swapSecs() or nil
	local kit = Kits.current(player)
	if swapShown then
		charSub.Text = "SWAP IN " .. swapShown .. "s"
		charSub.TextColor3 = Color3.fromRGB(175, 172, 200)
	else
		charSub.Text = kit.sub
		charSub.TextColor3 = kit.accent
	end
	local owned = ownedKits()
	for id, row in pairs(rows) do
		local waiting = swapShown ~= nil and owned[id] == true and id ~= kit.id
		if waiting and not row.swapDim then
			row.swapDim = new("Frame", { Name = "SwapDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 13, 22),
				BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 26 }, row.button)
			corner(row.swapDim, 10)
			row.swapText = inkText(label(row.button, { Name = "SwapWait", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(74, 16), TextColor3 = Color3.fromRGB(200, 198, 220), ZIndex = 27 }), 1)
		end
		if row.swapDim then
			row.swapDim.Visible = waiting
			row.swapText.Visible = waiting
			row.swapText.Text = waiting and ("SWAP IN " .. swapShown .. "s") or ""
		end
	end
end
RunService.Heartbeat:Connect(function()
	local left = swapLeft()
	if (left > 0 and swapSecs() or nil) ~= swapShown then
		styleSwap()
	end
end)

local function styleKit()
	local kit = Kits.current(player)
	charName.Text = kit.name
	charSub.Text = kit.sub
	charSub.TextColor3 = kit.accent
	charGrad.Color = ColorSequence.new(kit.c0, kit.c1)
	charGlyph.Text = kit.glyph
	-- (2026-11-10) the CHARACTER pill keeps its kanji glyph too (owner's request), so no CardArt redraw here
	charArtKit = kit.id
	charStroke.Color = kit.accent
	local owned = ownedKits()
	local yen = player:GetAttribute("Yen") or 0
	local count = 0
	for id, row in pairs(rows) do
		local have = owned[id] == true
		local on = id == kit.id and have
		if have then
			count += 1
		end
		row.tag.Visible = on
		row.stroke.Transparency = on and 0.1 or 1
		row.button.BackgroundTransparency = on and 0.9 or 0.96
		row.lockIcon.Visible = not have
		row.yenBtn.Visible = not have and shopReady() and not row.premium
		if row.premTag then
			row.premTag.Visible = not have
		end
		row.rbxBtn.Visible = not have and shopReady() and not paidPending[id]
		row.yenBtn.BackgroundColor3 = yen >= KIT_YEN and GOLD or Color3.fromRGB(110, 108, 130)
		row.eGrad.Color = have and ColorSequence.new(row.kit.c0, row.kit.c1)
			or ColorSequence.new(Color3.fromRGB(130, 128, 145), Color3.fromRGB(46, 44, 60))
		row.nameL.TextColor3 = have and WHITE or Color3.fromRGB(165, 163, 185)
	end
	dropCount.Text = count .. "/" .. #Kits.list .. " UNLOCKED"
	styleSwap() -- (2026-11-11) the swap cooldown draws over the pill / rows styled above
end

local dropOpen = false
-- (2026-11-14, phones) twelve rows do not fit under the top strip on a landscape phone: the list ran off the bottom
-- and the last five fighters could not be picked. When one column is too tall at the strip's scale the list flows
-- into TWO columns (UIListLayout.Wraps, filling down first, header at the top of the left one); if that is still too
-- big it scales down to fit. Returns the scale the list should open at. Rows keep their 288 px width either way.
local dropList = drop:FindFirstChildOfClass("UIListLayout")
local function fitDrop()
	local cam = workspace.CurrentCamera
	local s = stripScale.Scale
	if not cam or not dropList then
		return s
	end
	local n = 0
	for _, c in ipairs(drop:GetChildren()) do
		if c:IsA("GuiButton") and c.Visible and string.sub(c.Name, 1, 4) == "Row_" then
			n += 1
		end
	end
	local vp = cam.ViewportSize
	local availY = vp.Y - drop.Position.Y.Offset - 10 -- (this gui ignores the inset: offset 0 is the top of the screen)
	local availX = vp.X - drop.Position.X.Offset - 10
	local oneCol = 18 + n * 50 + 16 -- header + rows (46 + 4 gap) + padding
	local two = oneCol * s > availY and n > 1
	dropList.Wraps = two
	dropList.FillDirection = Enum.FillDirection.Vertical
	local rowW = two and UDim.new(0, 288) or UDim.new(1, 0)
	for _, c in ipairs(drop:GetChildren()) do
		if c:IsA("GuiObject") then
			c.Size = UDim2.new(rowW, c.Size.Y)
		end
	end
	local w, h = 304, oneCol
	if two then
		local inner = 18 + math.ceil(n / 2) * 50 -- the left column: header + half the rows
		w, h = 288 * 2 + 4 + 16, inner + 16
		drop.AutomaticSize = Enum.AutomaticSize.None
		drop.Size = UDim2.fromOffset(w, h)
	else
		drop.AutomaticSize = Enum.AutomaticSize.Y
		drop.Size = UDim2.fromOffset(304, 0)
	end
	if h * s > availY then
		s = math.max(0.45, availY / h)
	end
	if w * s > availX then
		s = math.max(0.45, availX / w)
	end
	return s
end
function setDrop(on)
	dropOpen = on
	if on then
		-- AbsolutePosition is measured below the topbar inset; this gui ignores the inset, so subtract its own origin
		local p = charPill.AbsolutePosition - gui.AbsolutePosition
		if charPill.Parent == strip then
			drop.Position = UDim2.fromOffset(p.X, p.Y + charPill.AbsoluteSize.Y + 8) -- still a pill in the top row (touch)
		else
			-- (2026-11-13) a tile in the left rail (StarterPlayerScripts.HudRails): the list opens to its right, from just
			-- under the topbar - twelve rows are most of the screen's height, so it cannot start level with the tile
			drop.Position = UDim2.fromOffset(p.X + charPill.AbsoluteSize.X + 10, math.max(8, GuiService.TopbarInset.Height + 6))
		end
		drop.Visible = true
		local target = fitDrop()
		dropScale.Scale = target * 0.92
		tween(dropScale, 0.18, { Scale = target }, Enum.EasingStyle.Back)
	else
		drop.Visible = false
	end
	tween(chev, 0.15, { Rotation = on and 180 or 0 })
end
charPill.Activated:Connect(function()
	if PK.closePanels then
		PK.closePanels() -- the pills sit above the shades now, so the fighter list must not open under a panel
	end
	setDrop(not dropOpen)
end)

player:GetAttributeChangedSignal("Kit"):Connect(function()
	pending = nil
	styleKit()
	if Kits.byId[player:GetAttribute("Kit") or ""] then -- not for "None" (no fighter until the starter pick)
		local kit = Kits.current(player)
		showToast("NOW PLAYING: " .. kit.name, kit.accent)
	end
end)
styleKit()

-- unlocking ----------------------------------------------------------------------------------------------
local wantRobux -- the fighter whose Robux prompt is open: switched to as soon as the pass lands
local function celebrate(kit)
	showToast("UNLOCKED: " .. kit.name .. "!", kit.accent)
	local row = rows[kit.id]
	if row then
		row.button.BackgroundColor3 = kit.accent
		row.button.BackgroundTransparency = 0.35
		tween(row.button, 0.6, { BackgroundTransparency = 0.96 })
		task.delay(0.6, function()
			row.button.BackgroundColor3 = WHITE
		end)
	end
end
function buyKit(kit)
	if not ShopRequest then
		showToast("SHOP OFFLINE", RED)
		return
	end
	local ok, a, b = pcall(function()
		return ShopRequest:InvokeServer("buyKit", kit.id)
	end)
	if ok and a then
		celebrate(kit)
		selectKit(kit.id, kit)
	else
		showToast(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
	end
end
function buyKitRobux(kit)
	-- a developer product (Catalog.KITS.PRODUCTS) wins; a game pass (PASSES) is the older fallback
	local productId = (KCFG.PRODUCTS or {})[kit.id]
	local passId = (KCFG.PASSES or {})[kit.id]
	local useProduct = type(productId) == "number" and productId > 0
	if player:GetAttribute("ShopOffline") then
		showToast("SHOP OFFLINE - REJOIN TO BUY", RED)
		return
	elseif player:GetAttribute("KitsOwned") == nil then
		showToast("LOADING YOUR FIGHTERS...", GOLD)
		return
	elseif ownedKits()[kit.id] or paidPending[kit.id] then
		return -- never sell a fighter twice
	end
	if not useProduct and (type(passId) ~= "number" or passId <= 0) then
		showToast("ROBUX UNLOCK FOR " .. kit.name .. " ISN'T SET UP YET", GOLD)
		return
	end
	wantRobux = kit.id
	local ok = pcall(function()
		if useProduct then
			MarketplaceService:PromptProductPurchase(player, productId)
		else
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end
	end)
	if not ok then
		showToast("PURCHASE UNAVAILABLE - TRY AGAIN", RED)
	end
end
-- a product purchase that went through but whose unlock is still saving shows a hint, not silence
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId ~= player.UserId or not purchased then
		return
	end
	for id, pid in pairs(KCFG.PRODUCTS or {}) do
		if pid == productId and not ownedKits()[id] then
			local name = (Kits.byId[id] and Kits.byId[id].name) or id
			showToast("UNLOCKING " .. name .. "...", GOLD)
			paidPending[id] = true
			styleKit()
			task.delay(10, function()
				if paidPending[id] and not ownedKits()[id] then
					-- Roblox redelivers an unconfirmed receipt, so the unlock is not lost - say so instead of going quiet
					showToast("PURCHASE RECEIVED - " .. name .. " UNLOCKS WHEN YOU REJOIN", GOLD)
				end
			end)
		end
	end
end)
player:GetAttributeChangedSignal("ShopOffline"):Connect(function()
	styleKit()
	if player:GetAttribute("ShopOffline") then
		showToast("YOUR SAVE DIDN'T LOAD - PLEASE REJOIN", RED)
	end
end)
-- (2026-11-07) a Studio playtest without DataStore access keeps purchases only until Stop (ShopService explains in Output)
do
	local told = false
	local function studioNote()
		if told or not player:GetAttribute("ShopStudioMemory") then
			return
		end
		told = true
		task.delay(4, function()
			showToast("STUDIO TEST: PURCHASES RESET ON STOP - ENABLE STUDIO API ACCESS TO SAVE", GOLD)
		end)
	end
	player:GetAttributeChangedSignal("ShopStudioMemory"):Connect(studioNote)
	studioNote()
end
-- a pass bought here (or on the website) arrives as a change to KitsOwned
local knownOwned = ownedKits()
player:GetAttributeChangedSignal("KitsOwned"):Connect(function()
	local now = ownedKits()
	if wantRobux and now[wantRobux] and not knownOwned[wantRobux] then
		local kit = Kits.byId[wantRobux]
		wantRobux = nil
		if kit then
			celebrate(kit)
			selectKit(kit.id, kit)
		end
	end
	knownOwned = now
	styleKit()
end)
player:GetAttributeChangedSignal("Yen"):Connect(styleKit)
-- the real Robux price, once a product (or pass) exists (the label shows Catalog.KITS.PRICE_ROBUX until then)
task.spawn(function()
	for _, kit in ipairs(Kits.list) do
		local id = kit.id
		local productId, passId = (KCFG.PRODUCTS or {})[id], (KCFG.PASSES or {})[id]
		local assetId, infoType
		if type(productId) == "number" and productId > 0 then
			assetId, infoType = productId, Enum.InfoType.Product
		elseif type(passId) == "number" and passId > 0 then
			assetId, infoType = passId, Enum.InfoType.GamePass
		end
		if assetId and rows[id] then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, infoType)
			-- premium fighters keep their PREMIUM price label (the same one the pick screen shows); ShopService warns in
			-- the output while the product on Roblox is set to a different price
			if ok and type(info) == "table" and info.PriceInRobux and not PREMIUM[id] then
				rows[id].rbxText.Text = "R$ " .. tostring(info.PriceInRobux)
			end
		end
	end
end)

-- SHOP panel ---------------------------------------------------------------------------------------------
local shade = new("TextButton", { Name = "ShopShade", Visible = false, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 30 }, gui)
-- (2026-11-11) 506 tall: the STYLE / BOOSTS sub-tab strip sits above the content, which still needs its 320 studs
local panel = new("Frame", { Name = "Shop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(720, 506),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 31, Active = true }, shade)
corner(panel, 16)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(24, 20, 40), Color3.fromRGB(10, 9, 18)) }, panel)
stroke(panel, INK, 3)
local panelScale = new("UIScale", {}, panel)
-- halftone dots in the lower-right corner (a manga screentone)
for gy = 0, 5 do
	for gx = 0, 9 do
		local s = 3 + (gx + gy) * 0.55
		local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -16 - gx * 16, 1, -16 - gy * 16),
			Size = UDim2.fromOffset(16 - s, 16 - s), BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 31 }, panel)
		corner(d)
	end
end

local header = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 32 }, panel)
corner(header, 16)
new("UIGradient", { Color = ColorSequence.new(RED, RED2), Rotation = 0 }, header)
new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = RED2,
	BorderSizePixel = 0, ZIndex = 32 }, header) -- squares off the header's lower corners
new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK,
	BorderSizePixel = 0, ZIndex = 33 }, header)
-- speed lines across the banner
for i = 1, 7 do
	new("Frame", { Position = UDim2.new(0.33 + i * 0.07, 0, 0, 8 + (i % 3) * 18), Size = UDim2.fromOffset(60 + (i % 4) * 30, 2),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 33 }, header)
end
-- comic burst behind the title: two squares at 0 and 45 degrees make an 8-point star
local burst = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(92, 36), Size = UDim2.fromOffset(116, 116),
	BackgroundTransparency = 1, ZIndex = 33 }, header)
for _, r in ipairs({ 0, 22.5, 45, 67.5 }) do
	local sq = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(74, 74), Rotation = r,
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 33 }, burst)
	stroke(sq, INK, 2.5)
end
local burstCore = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(76, 76),
	BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 34 }, burst)
corner(burstCore)
inkText(label(burst, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(98, 46), Text = "SHOP!",
	TextColor3 = WHITE, Rotation = -8, ZIndex = 35 }), 3)
inkText(label(header, { Position = UDim2.fromOffset(170, 12), Size = UDim2.fromOffset(240, 30), Text = "NEON BAZAAR", TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 34 }), 2)
label(header, { Position = UDim2.fromOffset(172, 44), Size = UDim2.fromOffset(240, 16), Text = "ネオン商店  ・  perks, style & boosts", FontFace = Kits.FONT_LABEL,
	TextColor3 = Color3.fromRGB(255, 220, 235), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
-- wallet badge
local wallet = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -70, 0.5, -2), Size = UDim2.fromOffset(150, 38),
	BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 34 }, header)
corner(wallet)
stroke(wallet, GOLD, 2)
local walletBig = label(wallet, { Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5), TextColor3 = GOLD, ZIndex = 35 })
-- close: a drawn X in an ink circle
local close = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, -2), Size = UDim2.fromOffset(40, 40),
	Text = "", AutoButtonColor = false, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 34 }, header)
corner(close)
stroke(close, WHITE, 2)
for _, r in ipairs({ 45, -45 }) do
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 4), Rotation = r,
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 35 }, close)
end

-- tabs
local tabsRow = new("Frame", { Position = UDim2.fromOffset(20, 86), Size = UDim2.new(1, -40, 0, 34), BackgroundTransparency = 1, ZIndex = 32 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabsRow)
-- (2026-11-09) the tip sits just under the tab bar (seven tabs fill its row now)
local tip = label(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 120), Size = UDim2.fromOffset(320, 12),
	FontFace = Kits.FONT_SMALL, TextColor3 = Color3.fromRGB(170, 170, 195), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 32,
	Text = string.format("earn %s: +%d per KO  ・  +%d a minute", Catalog.CURRENCY, Catalog.PER_KILL, Catalog.PER_MINUTE) })

local grid = new("ScrollingFrame", { Position = UDim2.fromOffset(20, 132), Size = UDim2.new(1, -40, 1, -150), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 32 }, panel)
new("UIGridLayout", { CellSize = UDim2.fromOffset(212, 150), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, grid)

local panelToast = inkText(label(panel, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(400, 24),
	TextTransparency = 1, ZIndex = 40 }), 2)
local ptToken
local function panelSay(text, color)
	local tok = {}
	ptToken = tok
	panelToast.Text = text
	panelToast.TextColor3 = color or WHITE
	panelToast.TextTransparency = 0
	local st = panelToast:FindFirstChildOfClass("UIStroke")
	st.Transparency = 0
	task.delay(1.5, function()
		if ptToken == tok then
			tween(panelToast, 0.35, { TextTransparency = 1 })
			tween(st, 0.35, { Transparency = 1 })
		end
	end)
end

local function owned()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("ShopOwned") or "[]")
	end)
	local set = {}
	for _, id in ipairs(ok and list or {}) do
		set[id] = true
	end
	return set
end

local perkCards = {} -- ROBUX tab: PerkCatalog item id -> card (built after the Yen cards)
local yenTip = tip.Text
local cards = {}
local tabButtons = {}
local extras -- (2026-11-09) the tabs CharacterSelect.ShopExtras adds (GADGETS / GIFTS / CODES), built below
-- (2026-11-11) THE SHOP'S TABS, grouped by what a player shops for: PERKS / STYLE / BOOSTS (+ GIFTS / CODES from
-- ShopExtras). currentTab is always the VIEW on screen: a sub-tab id (aura / title / cosmetic / random under STYLE,
-- boost / gadgets under BOOSTS) or a main tab with no sub-tabs (perks / gifts / codes). MAIN_OF maps a view to its main
-- tab, subTab remembers each main tab's last sub-tab, subStrips holds the sub-tab chips (built with the tab bar).
local MAIN_TABS = {
	{ id = "perks", label = "PERKS", jp = "特典", color = Color3.fromRGB(40, 185, 110) },
	{ id = "style", label = "STYLE", jp = "装い", color = Color3.fromRGB(150, 80, 255), subs = {
		{ id = "aura", label = "AURAS" }, { id = "title", label = "TITLES" }, { id = "cosmetic", label = "COSMETICS" }, { id = "random", label = "RANDOM" } } },
	{ id = "boosts", label = "BOOSTS", jp = "強化", color = Color3.fromRGB(255, 140, 40), subs = {
		{ id = "boost", label = "BOOSTS" }, { id = "gadgets", label = "GADGETS" } } },
	-- (2026-11-15, owner: "Make the events as its own section here") the server events (PerkCatalog items with event = true)
	{ id = "events", label = "EVENTS", jp = "事件", color = Color3.fromRGB(230, 55, 75) },
}
local MAIN_OF, subTab, subStrips = {}, {}, {}
for _, m in ipairs(MAIN_TABS) do
	MAIN_OF[m.id] = m.id
	for _, s in ipairs(m.subs or {}) do
		MAIN_OF[s.id] = m.id
	end
	subTab[m.id] = m.subs and m.subs[1].id or m.id
end
local currentTab = "perks"
local TIP = {
	perks = "perks are yours forever  ・  switch them in your inventory",
	cosmetic = "cosmetics are yours forever  ・  equip them in your inventory",
	boost = "one-time buys  ・  buy as many as you like",
	events = "the whole server sees it  ・  it happens on your map, with your name on it",
	random = "equal odds  ・  never a duplicate",
}
-- the shelf (view) a PerkCatalog card sits on
local COSMETIC_PERKS = { Trails = true, EmoteSlots = true, KillSound = true, UltOutfit = true, FunFilters = true }
local function shelfOf(it)
	if it.event then -- (2026-11-15) the EVENTS tab
		return "events"
	end
	if it.kind == "perk" then
		return COSMETIC_PERKS[it.id] and "cosmetic" or "perks"
	elseif it.kind == "emotePage" then
		return "cosmetic"
	elseif it.kind == "gadgetCrate" then
		return not (extras and extras.pages.gadgets) and "boost" or nil -- the GADGETS page sells it
	end
	return "boost" -- Yen packs, Meteor Shower, Instant Ult
end

local function refreshCards()
	local yen = player:GetAttribute("Yen") or 0
	local have = owned()
	local wornAura, wornTitle = player:GetAttribute("ShopAura") or "", player:GetAttribute("ShopTitle") or ""
	for id, c in pairs(cards) do
		local it = c.item
		c.card.Visible = it.kind == currentTab
		local worn = (it.kind == "aura" and wornAura == id) or (it.kind == "title" and wornTitle == id)
		if worn then
			c.btnText.Text = "EQUIPPED"
			c.btn.BackgroundColor3 = Color3.fromRGB(70, 220, 130)
		elseif have[id] then
			c.btnText.Text = "EQUIP"
			c.btn.BackgroundColor3 = it.c1:Lerp(WHITE, 0.25)
		else
			c.btnText.Text = "BUY"
			c.btn.BackgroundColor3 = yen >= it.price and GOLD or Color3.fromRGB(90, 88, 110)
		end
		c.price.Visible = not have[id]
		c.ownedTag.Visible = have[id] == true
	end
	local pset = PK.set()
	for id, c in pairs(perkCards) do
		local it = c.item
		c.card.Visible = shelfOf(it) == currentTab
		local own = it.kind == "perk" and (pset[id] == true or player:GetAttribute("Perk_" .. id) == true)
		c.price.Visible = not own
		c.ownedTag.Visible = own
		c.priceText.Text = PK.price(it)
		c.stroke.Color = own and it.color or INK
		if own then
			c.btnText.Text = "MANAGE" -- opens the inventory
			c.btn.BackgroundColor3 = Color3.fromRGB(150, 90, 255)
		elseif PK.buyable(it) then
			c.btnText.Text = "BUY"
			c.btn.BackgroundColor3 = GOLD
		else
			c.btnText.Text = "COMING SOON"
			c.btn.BackgroundColor3 = Color3.fromRGB(90, 88, 110)
		end
	end
	tip.Text = TIP[currentTab] or yenTip
	-- (2026-11-11) the main tab of this view; with sub-tabs, their strip shows and the content starts below it
	local main = MAIN_OF[currentTab] or currentTab
	if main ~= currentTab then
		subTab[main] = currentTab
	end
	for mid, s in pairs(subStrips) do
		s.frame.Visible = mid == main
		for sid, ch in pairs(s.chips) do
			local on = sid == currentTab
			ch.button.BackgroundColor3 = on and s.color or PANEL2
			ch.stroke.Color = on and WHITE or INK
		end
	end
	local top = subStrips[main] and 166 or 132
	local cPos, cSize = UDim2.fromOffset(20, top), UDim2.new(1, -40, 1, -(top + 18))
	grid.Position, grid.Size = cPos, cSize
	if PK.rollPage then
		PK.rollPage.Position, PK.rollPage.Size = cPos, cSize
	end
	for _, pg in pairs(extras and extras.pages or {}) do
		pg.frame.Position, pg.frame.Size = cPos, cSize
	end
	-- (2026-11-07) the RANDOM tab is its own page (buildRollShop), not grid cards; (2026-11-09) so are the extras
	local extraPage = extras and extras.pages[currentTab]
	grid.Visible = currentTab ~= "random" and extraPage == nil
	for id, pg in pairs(extras and extras.pages or {}) do
		pg.frame.Visible = id == currentTab
	end
	if extraPage then
		tip.Text = extraPage.tip or ""
		pcall(extraPage.refresh)
	end
	if PK.rollPage then
		PK.rollPage.Visible = currentTab == "random"
		if currentTab == "random" and PK.refreshRolls then
			PK.refreshRolls()
		end
	end
	for id, t in pairs(tabButtons) do
		local on = id == main
		t.button.BackgroundColor3 = on and (t.color or RED) or PANEL2
		t.stroke.Color = on and WHITE or INK
	end
	walletBig.Text = fmtYen(yen)
	walletText.Text = fmtYen(yen)
end

-- a third tab, ROBUX (2026-11-07): the PerkCatalog cards built after the Yen cards
-- (2026-11-11) the main tabs (MAIN_TABS); the old AURAS / TITLES / ROBUX / RANDOM tabs are STYLE / PERKS / BOOSTS views now
local shopTabs = table.clone(MAIN_TABS)
-- (2026-11-09) GADGETS / GIFTS / CODES: CharacterSelect.ShopExtras builds their pages from these helpers
do
	local mod = script:FindFirstChild("ShopExtras")
	local ok, res = pcall(function()
		return require(mod)({
			panel = panel, PK = PK, player = player, PerkCatalog = PerkCatalog, Kits = Kits, Catalog = Catalog, HttpService = HttpService,
			ShopRequest = ShopRequest, new = new, corner = corner, stroke = stroke, label = label, inkText = inkText, tween = tween,
			panelSay = panelSay, showToast = showToast, fmtYen = fmtYen, WHITE = WHITE, INK = INK, GOLD = GOLD, RED = RED, PANEL2 = PANEL2,
			buildGadgets = PK.buildGadgets,
			drawArt = drawArt, artOrb = artOrb, -- (2026-11-10) HudShared.CardArt, for the extras' own glyph orbs
		})
	end)
	if ok and type(res) == "table" then
		extras = res
		for _, t in ipairs(res.tabs) do
			if not MAIN_OF[t.id] then -- GADGETS is a BOOSTS sub-tab; GIFTS / CODES stay main tabs
				MAIN_OF[t.id], subTab[t.id] = t.id, t.id
				table.insert(shopTabs, t)
			end
		end
	else
		warn("[CharacterSelect] shop extras: " .. tostring(res))
	end
end
local TAB_W = math.min(108, math.floor((680 - (#shopTabs - 1) * 8) / #shopTabs))
tabsRow:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 8)
for i, tab in ipairs(shopTabs) do
	local b = new("TextButton", { Name = "Tab_" .. tab.id, LayoutOrder = i, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(TAB_W, 34), BackgroundColor3 = PANEL2,
		BorderSizePixel = 0, ZIndex = 33 }, tabsRow)
	corner(b, 8)
	local st = stroke(b, INK, 2)
	inkText(label(b, { Position = UDim2.fromOffset(8, 5), Size = UDim2.new(0.66, -8, 1, -10), Text = tab.label, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 34 }))
	label(b, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 9), Size = UDim2.new(0.34, -4, 1, -18), Text = tab.jp,
		FontFace = Kits.FONT_LABEL, TextColor3 = Color3.fromRGB(255, 225, 235), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
	tabButtons[tab.id] = { button = b, stroke = st, color = tab.color }
	b.Activated:Connect(function()
		currentTab = subTab[tab.id] or tab.id -- a tab with sub-tabs reopens the one last used
		grid.CanvasPosition = Vector2.zero
		refreshCards()
	end)
end
-- (2026-11-11) the sub-tab strips (STYLE, BOOSTS): chips just under the tab bar. A sub-tab whose page doesn't exist
-- (GADGETS without HudShared.GadgetCatalog) is left out; a main tab left with one view gets no strip.
for _, m in ipairs(MAIN_TABS) do
	local subs = {}
	for _, s in ipairs(m.subs or {}) do
		if s.id ~= "gadgets" or (extras and extras.pages.gadgets) then
			table.insert(subs, s)
		end
	end
	if #subs >= 2 then
		local strip = new("Frame", { Name = "Sub_" .. m.id, Position = UDim2.fromOffset(20, 132), Size = UDim2.new(1, -40, 0, 26), BackgroundTransparency = 1,
			Visible = false, ZIndex = 33 }, panel)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center }, strip)
		local chips = {}
		for i, s in ipairs(subs) do
			local b = new("TextButton", { Name = "Sub_" .. s.id, LayoutOrder = i, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(112, 26),
				BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 34 }, strip)
			corner(b)
			local st = stroke(b, INK, 2)
			inkText(label(b, { Size = UDim2.new(1, -18, 1, -8), Position = UDim2.fromOffset(9, 4), Text = s.label, ZIndex = 35 }), 1.2)
			b.Activated:Connect(function()
				currentTab = s.id
				grid.CanvasPosition = Vector2.zero
				refreshCards()
			end)
			chips[s.id] = { button = b, stroke = st }
		end
		subStrips[m.id] = { frame = strip, chips = chips, color = m.color }
	else
		subTab[m.id] = subs[1] and subs[1].id or m.id
	end
end

for i, it in ipairs(Catalog.items) do
	local card = new("Frame", { LayoutOrder = i, BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 33 }, grid)
	corner(card, 12)
	stroke(card, INK, 2)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, card)
	local band = new("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 34 }, card)
	new("UIGradient", { Color = ColorSequence.new(it.c0, it.c1) }, band)
	-- preview
	local pv = new("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 0, 66), BackgroundColor3 = INK, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, ZIndex = 34, ClipsDescendants = true }, card)
	corner(pv, 8)
	local orb
	if it.kind == "aura" then
		for k = 3, 1, -1 do
			local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24 + k * 16, 24 + k * 16),
				BackgroundColor3 = it.c1, BackgroundTransparency = 0.55 + k * 0.12, BorderSizePixel = 0, ZIndex = 35 }, pv)
			corner(ring)
		end
		orb = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 36 }, pv)
		corner(orb)
		new("UIGradient", { Color = ColorSequence.new(it.c0, it.c1), Rotation = 90 }, orb)
		inkText(label(orb, { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Text = utf8.char(utf8.codepoint(it.jp, 1)),
			FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 37 }), 1.5)
	else
		local t = inkText(label(pv, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.new(1, -16, 0, 30),
			Text = string.upper(it.name), ZIndex = 36 }), 2)
		new("UIGradient", { Color = ColorSequence.new(it.c0, it.c1), Rotation = 90 }, t)
		label(pv, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.new(1, -16, 0, 14), Text = it.jp,
			FontFace = Kits.FONT_LABEL, TextColor3 = it.c0, ZIndex = 36 })
	end
	-- (2026-11-10) CardArt: an aura's art replaces its rings + glyph orb; a title's sits in the preview's left square and
	-- the name + kana move over into the room beside it. An AURA's art is the WHOLE preview banner: the player's OWN
	-- avatar posed inside the aura (CardArt "avatarAura" - it re-renders itself when the character respawns / its
	-- appearance loads, and shows the comic dummy until there is a character)
	do
		local aura = it.kind == "aura"
		local slot = new("Frame", { Name = "ArtSlot", AnchorPoint = Vector2.new(aura and 0.5 or 0, 0.5), Position = UDim2.new(aura and 0.5 or 0, aura and 0 or 2, 0.5, 0),
			Size = aura and UDim2.fromScale(1, 1) or UDim2.fromOffset(64, 64), BackgroundTransparency = 1, ZIndex = 36 }, pv)
		if aura then
			corner(slot, 8)
		end
		if drawArt(slot, aura and { kind = "avatarAura", aura = it } or it, { live = true }) then
			for _, c in ipairs(pv:GetChildren()) do
				if c ~= slot and c:IsA("GuiObject") then
					if aura then
						c.Visible = false
					else
						c.Position = c.Position + UDim2.fromOffset(31, 0)
						c.Size = c.Size - UDim2.fromOffset(62, 0)
					end
				end
			end
		else
			slot:Destroy()
		end
	end
	label(card, { Position = UDim2.fromOffset(12, 84), Size = UDim2.new(1, -24, 0, 18), Text = it.name, FontFace = Kits.FONT_LABEL,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	if it.kind == "aura" then
		label(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 86), Size = UDim2.fromOffset(60, 14), Text = it.jp,
			FontFace = Kits.FONT_SMALL, TextColor3 = it.c0, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 34 })
	end
	-- price tag: a tilted gold ticket
	local price = new("Frame", { Position = UDim2.fromOffset(10, 112), Size = UDim2.fromOffset(92, 26), Rotation = -4, BackgroundColor3 = GOLD,
		BorderSizePixel = 0, ZIndex = 35 }, card)
	corner(price, 6)
	stroke(price, INK, 2)
	inkText(label(price, { Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Text = fmtYen(it.price), ZIndex = 36 }), 1.5)
	local ownedTag = label(card, { Position = UDim2.fromOffset(12, 114), Size = UDim2.fromOffset(90, 20), Text = "OWNED", FontFace = Kits.FONT_LABEL,
		TextColor3 = Color3.fromRGB(120, 240, 160), TextXAlignment = Enum.TextXAlignment.Left, Visible = false, ZIndex = 35 })
	local btn = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 110), Size = UDim2.fromOffset(92, 30), Text = "",
		AutoButtonColor = false, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 35 }, card)
	corner(btn, 8)
	stroke(btn, INK, 2)
	local bsc = new("UIScale", {}, btn)
	local btnText = inkText(label(btn, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = "BUY", ZIndex = 36 }), 1.5)
	btn.MouseEnter:Connect(function()
		tween(bsc, 0.1, { Scale = 1.06 })
	end)
	btn.MouseLeave:Connect(function()
		tween(bsc, 0.1, { Scale = 1 })
	end)
	btn.Activated:Connect(function()
		if not ShopRequest then
			panelSay("SHOP OFFLINE", RED)
			return
		end
		local action = owned()[it.id] and "equip" or "buy"
		local ok, a, b = pcall(function()
			return ShopRequest:InvokeServer(action, it.id)
		end)
		local success, msg = ok and a, ok and b or "TRY AGAIN"
		panelSay(msg or "", success and Color3.fromRGB(120, 240, 160) or RED)
		bsc.Scale = success and 1.18 or 0.9
		tween(bsc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		refreshCards()
	end)
	cards[it.id] = { card = card, item = it, btn = btn, btnText = btnText, price = price, ownedTag = ownedTag, orb = orb }
end

-- ROBUX tab cards (2026-11-07): every PerkCatalog item in catalog order. Perks are bought once (OWNED; the button then
-- says MANAGE and opens the inventory); boosts (Yen packs, Meteor Shower, Instant Ult) are always buyable; product 0 =
-- COMING SOON. Buying = MarketplaceService:PromptProductPurchase (ShopService's ProcessReceipt grants).
-- offer = true items (the Starter Pack) are left out: they have their own pill + popup (buildStarterOffer).
-- (2026-11-07) retired packs (owned one by one now) and the random rolls (the RANDOM tab) are left out too
local robuxItems = {}
for _, it in ipairs(PerkCatalog.ITEMS) do
	-- (2026-11-09) Early Access is only sold while a fighter is in development (KITS.EARLY not empty)
	-- (2026-11-10) the All Fighters Bundle is not sold while KITS.ALL_FREE gives every fighter to everyone (it would
	-- take R$149 for nothing visible); the server still honours it, so it is back on sale the moment ALL_FREE is off
	-- (2026-11-11) victory flashes are sold in the VICTORY tab (ShopExtras), not here
	if not it.offer and not it.retired and it.kind ~= "roll" and it.kind ~= "victory" and not (it.id == "EarlyAccess" and next(EARLY) == nil)
		and not (it.id == "AllFighters" and KCFG.ALL_FREE == true) then
		table.insert(robuxItems, it)
	end
end
for i, it in ipairs(robuxItems) do
	local c0 = it.color or GOLD
	local c1 = c0:Lerp(INK, 0.45)
	local consumable = it.kind ~= "perk"
	local card = new("Frame", { Name = "Perk_" .. it.id, LayoutOrder = 1000 + i, Visible = false, BackgroundColor3 = PANEL2, BorderSizePixel = 0,
		ZIndex = 33 }, grid)
	corner(card, 12)
	local cst = stroke(card, INK, 2)
	local csc = new("UIScale", {}, card)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, card)
	local band = new("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 34 }, card)
	new("UIGradient", { Color = ColorSequence.new(c0, c1) }, band)
	local pv = new("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 0, 62), BackgroundColor3 = INK, BackgroundTransparency = 0.2,
		BorderSizePixel = 0, ZIndex = 34, ClipsDescendants = true }, card)
	corner(pv, 8)
	local rays = {}
	for k = 0, 5 do -- sunburst behind the glyph
		rays[k + 1] = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(31, 31), Size = UDim2.fromOffset(120, 3), Rotation = k * 30,
			BackgroundColor3 = c0, BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 35 }, pv)
	end
	local orb = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(31, 31), Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 36 }, pv)
	corner(orb)
	new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = 90 }, orb)
	stroke(orb, INK, 2)
	inkText(label(orb, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), Text = it.glyph or "?",
		FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 37 }), 1.5)
	-- (2026-11-10) CardArt: the item's art fills the preview's left square in place of the sunburst + glyph orb
	do
		local slot = new("Frame", { Name = "ArtSlot", Position = UDim2.fromOffset(0, 1), Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1, ZIndex = 36 }, pv)
		if drawArt(slot, it, { live = true }) then
			orb.Visible = false
			for _, r in ipairs(rays) do
				r.Visible = false
			end
		else
			slot:Destroy()
		end
	end
	inkText(label(pv, { Position = UDim2.fromOffset(60, 5), Size = UDim2.new(1, -66, 0, 30), Text = string.upper(it.name), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 }), 2)
	local rib = new("Frame", { Position = UDim2.fromOffset(60, 38), Size = UDim2.fromOffset(84, 18), BorderSizePixel = 0, ZIndex = 36,
		BackgroundColor3 = consumable and Color3.fromRGB(255, 150, 40) or Color3.fromRGB(70, 220, 130) }, pv)
	corner(rib, 5)
	stroke(rib, INK, 1.5)
	inkText(label(rib, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), ZIndex = 37,
		Text = it.ribbon or (it.yen and ("+" .. fmtYen(it.yen)) or (consumable and "ONE-TIME" or "FOREVER")) }), 1)
	local desc = label(card, { Position = UDim2.fromOffset(12, 79), Size = UDim2.new(1, -24, 0, 28), TextWrapped = true,
		Text = it.yen and ("Instantly adds " .. fmtYen(it.yen) .. " to your wallet - spend it on auras, titles and fighters.") or it.desc or "",
		FontFace = Kits.FONT_SMALL, TextColor3 = Color3.fromRGB(205, 205, 228), TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 34 })
	new("UITextSizeConstraint", { MaxTextSize = 13 }, desc)
	local price = new("Frame", { Position = UDim2.fromOffset(10, 114), Size = UDim2.fromOffset(84, 26), Rotation = -4,
		BackgroundColor3 = Color3.fromRGB(70, 220, 130), BorderSizePixel = 0, ZIndex = 35 }, card)
	corner(price, 6)
	stroke(price, INK, 2)
	local priceText = inkText(label(price, { Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Text = PK.price(it), ZIndex = 36 }), 1.5)
	local ownedTag = label(card, { Position = UDim2.fromOffset(12, 116), Size = UDim2.fromOffset(90, 20), Text = "OWNED", FontFace = Kits.FONT_LABEL,
		TextColor3 = Color3.fromRGB(120, 240, 160), TextXAlignment = Enum.TextXAlignment.Left, Visible = false, ZIndex = 35 })
	local btn = new("TextButton", { Name = "Buy", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 112), Size = UDim2.fromOffset(96, 30),
		Text = "", AutoButtonColor = false, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 35 }, card)
	corner(btn, 8)
	stroke(btn, INK, 2)
	local bsc = new("UIScale", {}, btn)
	local btnText = inkText(label(btn, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = "BUY", ZIndex = 36 }), 1.5)
	btn.MouseEnter:Connect(function()
		tween(bsc, 0.1, { Scale = 1.06 })
	end)
	btn.MouseLeave:Connect(function()
		tween(bsc, 0.1, { Scale = 1 })
	end)
	local function press()
		bsc.Scale = 0.9
		tween(bsc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if it.kind == "perk" and PK.has(it.id) then
			-- owned: manage it - (2026-11-09) where the perk lives (emote wheel, settings, taunts), else the inventory
			if it.manage and PK.manage and PK.manage[it.manage] then
				PK.manage[it.manage](it)
			elseif PK.setInv then
				PK.setInv(true)
			end
		else
			PK.buy(it, panelSay)
		end
	end
	btn.Activated:Connect(press)
	PK.actions["Shop:" .. it.id] = press
	perkCards[it.id] = { card = card, item = it, btn = btn, btnText = btnText, price = price, priceText = priceText, ownedTag = ownedTag,
		stroke = cst, scale = csc }
end

for _, a in ipairs({ "Yen", "ShopOwned", "ShopAura", "ShopTitle" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshCards)
end

local function setShop(on)
	if on then
		setDrop(false)
		if PK.setInv then
			PK.setInv(false) -- one panel at a time
		end
		refreshCards()
		shade.Visible = true
		shade.BackgroundTransparency = 1
		tween(shade, 0.2, { BackgroundTransparency = 0.45 })
		panel.Position = UDim2.fromScale(0.5, 0.58)
		tween(panel, 0.28, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
	else
		shade.Visible = false
	end
end
-- (2026-11-09) MANAGE targets outside this script: the emote wheel, and the Settings / Taunt menus (they listen on
-- HudShared.OpenPanel(name))
do -- (ragdoll sandbox) the hub's SHOP kiosk opens the shop
	local op = ReplicatedStorage:WaitForChild("HudShared"):FindFirstChild("OpenPanel")
	if op then
		op.Event:Connect(function(name)
			if name == "shop" then
				setShop(true)
			elseif name == "fighters" then -- (2026-11-15) StarterPlayerScripts.Onboarding shows the fighter list in its first step
				if PK.closePanels then
					PK.closePanels()
				end
				setDrop(true)
			elseif name == "fightersClose" then
				setDrop(false)
			end
		end)
	end
end
PK.manage = {
	emotes = function()
		setShop(false)
		local ok, E = pcall(function()
			return require(ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Emotes"))
		end)
		if ok and E and E.toggleWheel then
			E.toggleWheel(true)
		end
	end,
}
-- (2026-11-15) photo = StarterPlayerScripts.PhotoMode, anyone = StarterPlayerScripts.SandboxClient (the spawn menu)
for _, name in ipairs({ "settings", "taunts", "sliders", "photo", "anyone" }) do -- (2026-11-14) sliders = StarterPlayerScripts.SandboxSliders
	PK.manage[name] = function(it)
		setShop(false)
		local ev = ReplicatedStorage:FindFirstChild("HudShared") and ReplicatedStorage.HudShared:FindFirstChild("OpenPanel")
		if ev then
			ev:Fire(name, it and it.id) -- the item id lets the menu open on the right tab
		end
	end
end
shopPill.Activated:Connect(function()
	setShop(not shade.Visible)
end)
close.Activated:Connect(function()
	setShop(false)
end)
shade.Activated:Connect(function()
	setShop(false)
end)

-- RANDOM tab (2026-11-07) -------------------------------------------------------------------------------------------
-- Emotes, KO effects and fighter skins are owned one at a time. One card per category with a Yen roll (ShopRequest
-- "roll") and a Robux roll (the category's PerkCatalog "roll" developer product). A roll gives ONE item the player does
-- not own yet, each with the same chance - never a duplicate (ShopService picks + grants it and writes LastRoll, which
-- plays the reveal here). Right: a live PREVIEW of the selected item (an emote played on a copy of your avatar, a KO
-- effect drawn by PerkFXClient inside the viewport, a skin's before / after colours) and the ODDS (paid random items
-- must show them). A region that restricts paid random items (PolicyService) sees everything but cannot roll.
-- PK.openRolls(cat, id?) opens this tab on that category / item (the inventory's locked items use it).
local function buildRollShop()
	local CAT_ORDER = { "emote", "ko", "skin" }
	local CAT_INFO = {
		-- hintTouch (2026-11-08): phones / tablets have no B key - they play emotes from the INVENTORY's play buttons
		emote = { title = "RANDOM EMOTE", noun = "EMOTE", hint = "PLAYED ON YOUR AVATAR  -  PRESS B IN GAME",
			hintTouch = "PLAYED ON YOUR AVATAR  -  PLAY IT FROM YOUR INVENTORY" },
		ko = { title = "RANDOM KO EFFECT", noun = "KO EFFECT", hint = "BURSTS ON EVERY KO YOU LAND" },
		skin = { title = "RANDOM SKIN", noun = "SKIN", hint = "RECOLOURS EVERY MOVE OF ONE FIGHTER" },
	}
	local GREEN, GREY, SOFT = Color3.fromRGB(70, 220, 130), Color3.fromRGB(90, 88, 110), Color3.fromRGB(200, 200, 222)
	local ROLL_YEN = PerkCatalog.ROLL_YEN or 500
	-- BULK (2026-11-08): each card has x1 / x5 / x10 chips (PerkCatalog.ROLL_SIZES). A size is offered only while at least
	-- that many items are left to win; the Yen button costs ROLL_YEN x n, the Robux button buys that size's product
	-- (PerkCatalog.rollItem; COMING SOON while its product is 0). A bulk buy's reveal lists everything it gave.
	local ROLL_SIZES = PerkCatalog.ROLL_SIZES or { 1 }
	local amt = {} -- cat -> the chosen amount
	local KO_INK = {
		Confetti = { Color3.fromRGB(255, 240, 120), Color3.fromRGB(230, 40, 140) },
		Explosion = { Color3.fromRGB(255, 210, 90), Color3.fromRGB(170, 30, 10) },
		Lightning = { Color3.fromRGB(215, 245, 255), Color3.fromRGB(30, 90, 230) },
	}

	local page = new("Frame", { Name = "RandomPage", Position = UDim2.fromOffset(20, 132), Size = UDim2.new(1, -40, 1, -150),
		BackgroundTransparency = 1, Visible = false, ZIndex = 32 }, panel)
	PK.rollPage = page

	local selCat, selItem = "emote", nil
	local restricted = nil -- nil while Roblox is asked; true = this region restricts paid random items
	local cards, rows = {}, {}
	local refresh, preview, pickCat

	local function pool(cat)
		return PerkCatalog.pool(cat)
	end
	local function itemName(cat, id)
		for _, o in ipairs(pool(cat)) do
			if o.id == id then
				if cat == "skin" then
					local k = Kits.byId[id]
					return (k and (string.upper(k.name) .. "  -  ") or "") .. o.name
				end
				return o.name
			end
		end
		return tostring(id)
	end
	local function leftOf(cat)
		local own, n = PK.owned(cat), 0
		for _, o in ipairs(pool(cat)) do
			if not own[o.id] then
				n += 1
			end
		end
		return n
	end
	local function fmtPct(p)
		local s = string.format("%.1f", p)
		if string.sub(s, -2) == ".0" then
			s = string.sub(s, 1, -3)
		end
		return s .. "%"
	end

	-- may this player buy paid random items? (asked once; a failed lookup counts as no)
	task.spawn(function()
		local ok, info = pcall(function()
			return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
		end)
		restricted = not (ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false)
		if refresh then
			refresh()
		end
	end)

	-- rolling ----------------------------------------------------------------------------------------------------------
	local rolling = false
	local function canRoll(cat, n)
		n = n or 1
		if restricted == nil then
			panelSay("ONE MOMENT...", GOLD)
			return false
		elseif restricted then
			panelSay("RANDOM ITEMS AREN'T AVAILABLE IN YOUR REGION", RED)
			return false
		elseif player:GetAttribute("ShopOffline") then
			panelSay("SHOP OFFLINE - REJOIN TO BUY", RED)
			return false
		elseif leftOf(cat) == 0 then
			panelSay("YOU OWN EVERY " .. CAT_INFO[cat].noun .. "!", GOLD)
			return false
		elseif leftOf(cat) < n then
			panelSay("ONLY " .. leftOf(cat) .. " LEFT TO WIN  -  PICK A SMALLER AMOUNT", GOLD)
			return false
		end
		return true
	end
	local function rollYen(cat)
		if selCat ~= cat then
			pickCat(cat)
		end
		local n = amt[cat] or 1
		if rolling or not canRoll(cat, n) then
			return
		end
		if (player:GetAttribute("Yen") or 0) < ROLL_YEN * n then
			panelSay("NOT ENOUGH " .. Catalog.CURRENCY .. "  -  " .. (n > 1 and (n .. " ROLLS ARE ") or "A ROLL IS ") .. fmtYen(ROLL_YEN * n), RED)
			return
		end
		if not ShopRequest then
			panelSay("SHOP OFFLINE", RED)
			return
		end
		rolling = true
		local ok, a, b = pcall(function()
			return ShopRequest:InvokeServer("roll", cat, n)
		end)
		rolling = false
		if not (ok and a) then
			panelSay(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
		end -- a success plays the reveal (LastRoll)
	end
	local function rollRobux(cat)
		if selCat ~= cat then
			pickCat(cat)
		end
		local n = amt[cat] or 1
		local it = PerkCatalog.rollItem and PerkCatalog.rollItem(cat, n) or PerkCatalog.ROLLS[cat]
		if it and canRoll(cat, n) then
			PK.buy(it, panelSay)
		end
	end
	local function setAmount(cat, n)
		if selCat ~= cat then
			pickCat(cat)
		end
		local left = leftOf(cat)
		if n > 1 and left < n then
			panelSay(left == 0 and ("YOU OWN EVERY " .. CAT_INFO[cat].noun .. "!") or ("ONLY " .. left .. " LEFT TO WIN"), GOLD)
			return
		end
		amt[cat] = n
		refresh()
	end

	-- left: one card per category ---------------------------------------------------------------------------------------
	for i, cat in ipairs(CAT_ORDER) do
		local it = PerkCatalog.ROLLS[cat]
		if it then
			local info = CAT_INFO[cat]
			local c0 = it.color or GOLD
			local c1 = c0:Lerp(INK, 0.45)
			local card = new("TextButton", { Name = "Roll_" .. cat, AutoButtonColor = false, Text = "", Position = UDim2.fromOffset(0, (i - 1) * 110),
				Size = UDim2.fromOffset(404, 100), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 33 }, page)
			corner(card, 12)
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, card)
			local st = stroke(card, INK, 2)
			local band = new("Frame", { Position = UDim2.fromOffset(8, 10), Size = UDim2.new(0, 6, 1, -20), BackgroundColor3 = WHITE, BorderSizePixel = 0,
				ZIndex = 34 }, card)
			corner(band, 3)
			new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = 90 }, band)
			local o = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(56, 56),
				BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 34 }, card)
			corner(o)
			new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = 90 }, o)
			stroke(o, INK, 2)
			inkText(label(o, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = it.glyph or "?",
				FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 35 }), 1.5)
			artOrb(o, it, 1.15, { live = true }) -- (2026-11-10) the roll's CardArt over the glyph orb (the ? badge stays on top)
			local q = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(72, 26), Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 36 }, card)
			corner(q)
			stroke(q, INK, 1.5)
			inkText(label(q, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = "?", ZIndex = 37 }), 1)
			inkText(label(card, { Position = UDim2.fromOffset(90, 12), Size = UDim2.fromOffset(176, 26), Text = info.title,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 }), 2)
			local sub = label(card, { Position = UDim2.fromOffset(90, 42), Size = UDim2.fromOffset(176, 14), FontFace = Kits.FONT_LABEL, TextColor3 = c0,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
			local bar = new("Frame", { Position = UDim2.fromOffset(90, 62), Size = UDim2.fromOffset(170, 8), BackgroundColor3 = INK, BorderSizePixel = 0,
				ZIndex = 34 }, card)
			corner(bar, 4)
			stroke(bar, Color3.fromRGB(70, 66, 96), 1)
			local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 35 }, bar)
			corner(fill, 4)
			new("UIGradient", { Color = ColorSequence.new(c0, c1) }, fill)
			-- how many to buy: x1 / x5 / x10 (the page header already says equal odds, never a duplicate)
			local chips = {}
			for k, n in ipairs(ROLL_SIZES) do
				local chip = new("TextButton", { Name = "Amount_" .. n, Position = UDim2.fromOffset(90 + (k - 1) * 48, 75), Size = UDim2.fromOffset(44, 18),
					Text = "", AutoButtonColor = false, BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 36 }, card)
				corner(chip, 5)
				local cst = stroke(chip, INK, 1.5)
				local ct = label(chip, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = "x" .. n, FontFace = Kits.FONT_PUNCH, ZIndex = 37 })
				chip.Activated:Connect(function()
					setAmount(cat, n)
				end)
				PK.actions["RollAmount:" .. cat .. ":" .. n] = function()
					setAmount(cat, n)
				end
				chips[n] = { button = chip, stroke = cst, text = ct }
			end
			local function rollButton(y, color, onPress)
				local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.fromOffset(118, 36), Text = "",
					AutoButtonColor = false, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 36 }, card)
				corner(b, 8)
				stroke(b, INK, 2)
				local sc = new("UIScale", {}, b)
				local t = inkText(label(b, { Size = UDim2.new(1, -14, 1, -12), Position = UDim2.fromOffset(7, 6), ZIndex = 37 }), 1.5)
				b.MouseEnter:Connect(function()
					tween(sc, 0.08, { Scale = 1.06 })
				end)
				b.MouseLeave:Connect(function()
					tween(sc, 0.08, { Scale = 1 })
				end)
				b.Activated:Connect(function()
					sc.Scale = 0.9
					tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
					onPress()
				end)
				return b, t
			end
			local yenB, yenT = rollButton(12, GOLD, function()
				rollYen(cat)
			end)
			local rbxB, rbxT = rollButton(52, GREEN, function()
				rollRobux(cat)
			end)
			card.Activated:Connect(function()
				if selCat ~= cat then
					pickCat(cat)
				end
			end)
			PK.actions["RollYen:" .. cat] = function()
				rollYen(cat)
			end
			PK.actions["RollRobux:" .. cat] = function()
				rollRobux(cat)
			end
			cards[cat] = { card = card, item = it, stroke = st, sub = sub, fill = fill, yenB = yenB, yenT = yenT, rbxB = rbxB, rbxT = rbxT,
				chips = chips, c0 = c0 }
		end
	end

	-- right: the preview box ------------------------------------------------------------------------------------------
	local right = new("Frame", { Name = "Side", Position = UDim2.fromOffset(416, 0), Size = UDim2.new(1, -416, 1, 0), BackgroundTransparency = 1,
		ZIndex = 33 }, page)
	local box = new("Frame", { Name = "Preview", Size = UDim2.new(1, 0, 0, 172), BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true,
		ZIndex = 33 }, right)
	corner(box, 12)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(62, 50, 104), Color3.fromRGB(14, 12, 26)) }, box)
	local boxStroke = stroke(box, INK, 2)
	local vp = new("ViewportFrame", { Name = "View", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(190, 185, 205),
		LightColor = Color3.fromRGB(255, 248, 235), LightDirection = Vector3.new(-0.4, -1, 0.5), ZIndex = 34 }, box)
	local wm = new("WorldModel", {}, vp)
	local cam = new("Camera", { FieldOfView = 40 }, vp)
	vp.CurrentCamera = cam
	new("Part", { Name = "Stage", Anchored = true, CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 13, 13),
		CFrame = CFrame.new(0, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(52, 42, 88), Material = Enum.Material.SmoothPlastic }, wm)
	new("Part", { Name = "StageRim", Anchored = true, CanCollide = false, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 14, 14),
		CFrame = CFrame.new(0, -0.28, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(150, 80, 255), Material = Enum.Material.Neon }, wm)

	-- a copy of your avatar on the stage (rebuilt after a respawn): no scripts, sounds, guis, effects or movers
	local avatar, avatarOf, avatarH = nil, nil, 5
	local STRIP = { "LuaSourceContainer", "Sound", "BillboardGui", "ParticleEmitter", "Trail", "Beam", "Light", "ForceField", "BodyMover",
		"AlignPosition", "AlignOrientation", "LinearVelocity", "AngularVelocity", "VectorForce", "Torque", "Highlight" }
	local function buildAvatar()
		local char = player.Character
		if not char then
			return avatar
		end
		if avatar and avatarOf == char and avatar.Parent then
			return avatar
		end
		if avatar then
			avatar:Destroy()
			avatar = nil
		end
		local was = char.Archivable
		char.Archivable = true
		local ok, m = pcall(function()
			return char:Clone()
		end)
		char.Archivable = was
		if not ok or not m then
			return nil
		end
		for _, d in ipairs(m:GetDescendants()) do
			for _, cls in ipairs(STRIP) do
				if d:IsA(cls) then
					d:Destroy()
					break
				end
			end
		end
		-- this game's rigs are physics-driven (AnimationConstraint joints + ragdoll sockets), and nothing simulates physics
		-- inside a ViewportFrame: every AnimationConstraint becomes a Motor6D of the same name (ProceduralAnimator drives
		-- either kind by name), a RigidConstraint a Weld, and the other constraints go
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
				local a0, a1 = d.Attachment0, d.Attachment1
				if a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart") then
					local j = Instance.new(d:IsA("AnimationConstraint") and "Motor6D" or "Weld")
					j.Name = d.Name
					j.Part0, j.Part1 = a0.Parent, a1.Parent
					j.C0, j.C1 = a0.CFrame, a1.CFrame
					j.Parent = a1.Parent
				end
				d:Destroy()
			elseif d:IsA("Constraint") then
				d:Destroy()
			end
		end
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.CanCollide = false
			end
		end
		local hrp = m:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = true
		end
		m.Name = "PreviewAvatar"
		m:PivotTo(CFrame.new(0, 50, 0)) -- faces -Z, toward the camera
		local cf, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() - Vector3.new(0, cf.Position.Y - size.Y / 2, 0)) -- feet on the stage
		avatarH = math.clamp(size.Y, 3, 9)
		m.Parent = wm
		avatar, avatarOf = m, char
		return m
	end

	-- labels over the preview
	local boxTitle = inkText(label(box, { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -100, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41 }), 1.5)
	local boxTag = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(82, 20), BackgroundColor3 = GREY,
		BorderSizePixel = 0, ZIndex = 41 }, box)
	corner(boxTag, 6)
	stroke(boxTag, INK, 1.5)
	local boxTagT = inkText(label(boxTag, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), ZIndex = 42 }), 1)
	local boxHint = label(box, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -6), Size = UDim2.new(1, -20, 0, 12), FontFace = Kits.FONT_LABEL,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 })
	-- FREE PICK (2026-11-09): a 10-roll's 10th item is the player's choice (ShopService.Ext.RollPicks, attribute RollPicks):
	-- while one is waiting for this category, an item they don't own gets a PICK THIS ONE button (ShopRequest "rollPick")
	local function rollPicks()
		local ok, t = pcall(function()
			return HttpService:JSONDecode(player:GetAttribute("RollPicks") or "{}")
		end)
		return (ok and type(t) == "table") and t or {}
	end
	local pickBtn = new("TextButton", { Name = "PickThis", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -22), Size = UDim2.fromOffset(132, 30),
		Text = "", AutoButtonColor = true, BackgroundColor3 = GOLD, BorderSizePixel = 0, Visible = false, ZIndex = 43 }, box)
	corner(pickBtn, 8)
	stroke(pickBtn, INK, 2)
	inkText(label(pickBtn, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = "PICK THIS ONE", ZIndex = 44 }), 1.5)
	local picking = false
	local function doPick()
		if picking or not selItem or not ShopRequest then
			return
		end
		picking = true
		local ok, a, b = pcall(function()
			return ShopRequest:InvokeServer("rollPick", { cat = selCat, id = selItem })
		end)
		picking = false
		if not (ok and a) then
			panelSay(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
		end -- a pick plays the reveal (LastRoll) like a roll
	end
	pickBtn.Activated:Connect(doPick)
	PK.actions.RollPick = doPick
	-- the preview's footer hint, worded for the input device (HudShared.InputMode: no key names on touch screens)
	local InputMode
	pcall(function()
		InputMode = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("InputMode", 10))
	end)
	local hintCat
	local function hintFor(cat)
		local info = CAT_INFO[cat]
		if not info then
			return ""
		end
		-- (2026-11-11) the emote hint names the player's own EMOTES key (HudShared.Keybinds)
		local h = info.hint or ""
		local okK, KB = pcall(require, ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Keybinds"))
		if okK and KB then
			h = (string.gsub(h, "PRESS B", "PRESS " .. KB.label(Enum.KeyCode.B)))
		end
		return (InputMode and InputMode.isTouch() and info.hintTouch) or h
	end
	if InputMode then
		InputMode.changed(function()
			if hintCat then
				boxHint.Text = hintFor(hintCat)
			end
		end)
	end
	-- a KO's "K.O.!" (the real one is a BillboardGui, which a ViewportFrame cannot show)
	local koWord = inkText(label(box, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(150, 44),
		Text = "K.O.!", FontFace = Font.fromEnum(Enum.Font.GothamBlack), TextTransparency = 1, ZIndex = 40 }), 3)
	local koStroke = koWord:FindFirstChildOfClass("UIStroke")
	koStroke.Transparency = 1
	local koScale = new("UIScale", {}, koWord)

	-- a skin: the fighter's normal colours -> the skin's colours (skins recolour moves, not the avatar)
	local skinCard = new("Frame", { Name = "SkinPreview", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 36 }, box)
	local baseE, baseG, baseGl = emblem(skinCard, 64, Kits.list[1], UDim2.new(0.5, -104, 0.5, 2))
	local altE, altG, altGl = emblem(skinCard, 64, Kits.list[1], UDim2.new(0.5, 40, 0.5, 2))
	local arrow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 4, 0.5, 2), Size = UDim2.fromOffset(34, 20),
		BackgroundTransparency = 1 }, skinCard)
	new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(24, 5), BackgroundColor3 = GOLD,
		BorderSizePixel = 0 }, arrow)
	for _, r in ipairs({ 40, -40 }) do
		new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, r > 0 and -4 or 4), Size = UDim2.fromOffset(14, 5), Rotation = r,
			BackgroundColor3 = GOLD, BorderSizePixel = 0 }, arrow)
	end
	local baseName = label(skinCard, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -72, 0.5, 38), Size = UDim2.fromOffset(110, 13),
		FontFace = Kits.FONT_LABEL, TextColor3 = SOFT })
	local altName = inkText(label(skinCard, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 72, 0.5, 37), Size = UDim2.fromOffset(120, 15),
		TextColor3 = GOLD }), 1)
	local fighterNote = label(skinCard, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.new(1, -20, 0, 12),
		FontFace = Kits.FONT_LABEL, TextColor3 = Color3.fromRGB(255, 140, 120) })
	local function showSkin(id)
		local kit = Kits.byId[id] or Kits.list[1]
		local cols = (PerkCatalog.SKIN_COLORS or {})[id]
		baseG.Color = ColorSequence.new(kit.c0, kit.c1)
		altG.Color = cols and ColorSequence.new(cols[1], cols[2]) or ColorSequence.new(kit.c0, kit.c1)
		baseGl.Text, altGl.Text = kit.glyph, kit.glyph
		-- (2026-11-10) CardArt: the fighter -> the skin, both or neither (half art, half glyph would read as a bug)
		local drewSkin = artOrb(altE, { kind = "skin", kit = kit.id, id = id }, 1.1, { live = true })
		artOrb(baseE, drewSkin and { kind = "fighter", kit = kit.id } or nil, 1.1, { live = true })
		baseName.Text = "NORMAL"
		altName.Text = (PerkCatalog.SKINS or {})[id] or "SKIN"
		fighterNote.Text = ownedKits()[id] and "" or "YOU DON'T HAVE THIS FIGHTER YET"
	end

	-- the reveal after a roll
	local reveal = new("Frame", { Name = "Reveal", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.new(1, -16, 0, 50),
		BackgroundColor3 = INK, BackgroundTransparency = 0.12, BorderSizePixel = 0, Visible = false, ZIndex = 44 }, box)
	corner(reveal, 10)
	stroke(reveal, GOLD, 2)
	local revealScale = new("UIScale", {}, reveal)
	label(reveal, { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 14), Text = "YOU GOT", FontFace = Kits.FONT_LABEL, TextColor3 = GOLD, ZIndex = 45 })
	local revealName = inkText(label(reveal, { Position = UDim2.fromOffset(8, 19), Size = UDim2.new(1, -16, 0, 26), ZIndex = 45 }), 2)
	-- a bulk buy: every item it gave, under the count
	local revealList = label(reveal, { Position = UDim2.fromOffset(8, 48), Size = UDim2.new(1, -16, 0, 30), FontFace = Kits.FONT_LABEL, TextWrapped = true,
		TextColor3 = WHITE, Visible = false, ZIndex = 45 })
	local revealTok = 0
	local function showReveal(cat, id, ids)
		revealTok += 1
		local tok = revealTok
		local many = type(ids) == "table" and #ids > 1
		if many then
			local names = {}
			for _, x in ipairs(ids) do
				table.insert(names, itemName(cat, x))
			end
			revealName.Text = #ids .. " NEW " .. CAT_INFO[cat].noun .. "S!"
			revealList.Text = table.concat(names, "  ・  ")
			reveal.Size = UDim2.new(1, -16, 0, 84)
		else
			revealName.Text = itemName(cat, id) .. "!"
			reveal.Size = UDim2.new(1, -16, 0, 50)
		end
		revealList.Visible = many
		reveal.Visible = true
		revealScale.Scale = 0.3
		tween(revealScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		boxStroke.Color, boxStroke.Thickness = GOLD, 3
		task.delay(many and 5 or 3.2, function()
			if revealTok == tok then
				reveal.Visible = false
				boxStroke.Color, boxStroke.Thickness = INK, 2
			end
		end)
	end

	-- the odds list (click a row to preview it)
	local oddsHead = label(right, { Position = UDim2.fromOffset(2, 180), Size = UDim2.new(1, -4, 0, 14), FontFace = Kits.FONT_LABEL, TextColor3 = SOFT,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 33 })
	local list = new("ScrollingFrame", { Name = "Odds", Position = UDim2.fromOffset(0, 200), Size = UDim2.new(1, 0, 1, -200), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 33 }, right)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1) }, list)
	local function buildRows(cat)
		for _, r in pairs(rows) do
			r.button:Destroy()
		end
		table.clear(rows)
		for i, o in ipairs(pool(cat)) do
			local b = new("TextButton", { Name = "Odds_" .. o.id, LayoutOrder = i, AutoButtonColor = false, Text = "", Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 34 }, list)
			corner(b, 6)
			local st = stroke(b, INK, 1.5)
			local nm = label(b, { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -84, 1, -12), Text = itemName(cat, o.id), FontFace = Kits.FONT_LABEL,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
			local pc = label(b, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(66, 14), FontFace = Kits.FONT_LABEL,
				TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
			b.Activated:Connect(function()
				preview(cat, o.id)
			end)
			PK.actions["Preview:" .. o.id] = function()
				preview(cat, o.id)
			end
			rows[o.id] = { button = b, stroke = st, name = nm, pct = pc }
		end
		list.CanvasPosition = Vector2.zero
	end

	-- preview loops (one at a time: pvToken) -----------------------------------------------------------------------------
	local PA, EClips
	local function loadAnim()
		if PA and EClips then
			return true
		end
		local ok, err = pcall(function()
			PA = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
			EClips = require(ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Emotes"):WaitForChild("Clips"))
		end)
		if not ok then
			warn("[CharacterSelect] emote preview: " .. tostring(err))
		end
		return ok and PA ~= nil and EClips ~= nil
	end
	local pvToken, track = 0, nil
	local function stopTrack()
		local t = track
		track = nil
		if t then
			pcall(function()
				t:stop(0.1)
			end)
		end
	end
	local function live(tok)
		return pvToken == tok and page.Visible and shade.Visible
	end
	local function emoteLoop(id, tok)
		task.spawn(function()
			if not loadAnim() or type(EClips[id]) ~= "table" then
				return
			end
			while live(tok) and avatar do
				local done = false
				local ok, tr = pcall(PA.play, avatar, EClips[id], {
					onEnd = function()
						done = true
					end,
				})
				if not ok or type(tr) ~= "table" then
					warn("[CharacterSelect] emote preview: " .. tostring(tr))
					return
				end
				track = tr
				local t0 = os.clock()
				while not done and live(tok) and os.clock() - t0 < 15 do
					task.wait(0.1)
				end
				if not live(tok) then
					return
				end
				track = nil
				task.wait(0.8)
			end
		end)
	end
	local function koPreviewFn()
		local s = script.Parent and script.Parent:FindFirstChild("PerkFXClient")
		local bf = s and s:FindFirstChild("KOPreview")
		return (bf and bf:IsA("BindableFunction")) and bf or nil
	end
	local function koLoop(id, tok)
		task.spawn(function()
			while live(tok) do
				local root = avatar and (avatar:FindFirstChild("UpperTorso") or avatar:FindFirstChild("Torso") or avatar:FindFirstChild("HumanoidRootPart"))
				local pos = root and root.Position or Vector3.new(0, 3, 0)
				local bf = koPreviewFn()
				if bf then
					pcall(bf.Invoke, bf, id, wm, pos)
				end
				local ink = KO_INK[id] or KO_INK.Explosion
				koWord.TextColor3, koStroke.Color = ink[1], ink[2]
				koWord.TextTransparency, koStroke.Transparency = 0, 0
				koWord.Rotation = math.random(-8, 8)
				koScale.Scale = 0.2
				tween(koScale, 0.22, { Scale = 1.1 }, Enum.EasingStyle.Back)
				task.delay(1.1, function()
					tween(koWord, 0.4, { TextTransparency = 1 })
					tween(koStroke, 0.4, { Transparency = 1 })
				end)
				local t0 = os.clock()
				while live(tok) and os.clock() - t0 < 2.8 do
					task.wait(0.1)
				end
			end
		end)
	end

	preview = function(cat, id)
		pvToken += 1
		local tok = pvToken
		stopTrack()
		selCat, selItem = cat, id
		boxTitle.Text = id and itemName(cat, id) or ""
		hintCat = cat
		boxHint.Text = hintFor(cat)
		koWord.TextTransparency, koStroke.Transparency = 1, 1
		vp.Visible = cat ~= "skin"
		skinCard.Visible = cat == "skin"
		if id and page.Visible and shade.Visible then
			if cat == "skin" then
				showSkin(id)
			else
				buildAvatar()
				if cat == "emote" then
					cam.FieldOfView = 38
					cam.CFrame = CFrame.lookAt(Vector3.new(3, avatarH * 0.62, -10.5), Vector3.new(0, avatarH * 0.5, 0))
					emoteLoop(id, tok)
				else
					cam.FieldOfView = 55
					cam.CFrame = CFrame.lookAt(Vector3.new(7, 10, -28), Vector3.new(0, 6, 0))
					koLoop(id, tok)
				end
			end
		end
		refresh()
	end

	local builtCat = nil
	pickCat = function(cat, id)
		if builtCat ~= cat then
			buildRows(cat)
			builtCat = cat
		end
		if not id then -- the first one you don't own yet (else the first)
			local own = PK.owned(cat)
			for _, o in ipairs(pool(cat)) do
				if not own[o.id] then
					id = o.id
					break
				end
			end
			id = id or (pool(cat)[1] and pool(cat)[1].id)
		end
		preview(cat, id)
	end

	refresh = function()
		local yen = player:GetAttribute("Yen") or 0
		for cat, c in pairs(cards) do
			local total = #pool(cat)
			local left = leftOf(cat)
			local done, blocked = left == 0, restricted == true
			local waiting = tonumber(rollPicks()[cat]) or 0
			c.sub.Text = (total - left) .. " / " .. total .. " OWNED" .. (waiting > 0 and ("  ・  " .. waiting .. " FREE PICK" .. (waiting > 1 and "S" or "")) or "")
			c.fill.Size = UDim2.fromScale(total > 0 and (total - left) / total or 0, 1)
			-- the chosen amount, stepped down to the biggest size still available
			local n = amt[cat] or 1
			if n > 1 and left < n then
				n = 1
				for _, s in ipairs(ROLL_SIZES) do
					if s <= left and s > n then
						n = s
					end
				end
				amt[cat] = n
			end
			for s, ch in pairs(c.chips or {}) do
				local avail = s == 1 or left >= s
				local on = s == n
				ch.button.BackgroundColor3 = on and c.c0 or PANEL2
				ch.text.TextColor3 = on and INK or (avail and WHITE or GREY)
				ch.stroke.Color = on and WHITE or INK
				ch.button.BackgroundTransparency = avail and 0 or 0.5
			end
			local cost = ROLL_YEN * n
			c.yenT.Text = done and "ALL OWNED" or blocked and "UNAVAILABLE" or fmtYen(cost)
			c.yenB.BackgroundColor3 = (done or blocked or yen < cost) and GREY or GOLD
			local rit = PerkCatalog.rollItem and PerkCatalog.rollItem(cat, n) or c.item
			local pid = rit and PK.product(rit)
			c.rbxT.Text = done and "ALL OWNED" or blocked and "UNAVAILABLE" or (pid and PK.price(rit) or "COMING SOON")
			c.rbxB.BackgroundColor3 = (done or blocked or not pid) and GREY or GREEN
			local on = cat == selCat
			c.stroke.Color = on and c.item.color or INK
			c.stroke.Thickness = on and 3 or 2
		end
		local own = PK.owned(selCat)
		local left = leftOf(selCat)
		local each = left > 0 and fmtPct(100 / left) or ""
		local waiting = tonumber(rollPicks()[selCat]) or 0
		oddsHead.Text = (waiting > 0 and left > 0) and ("FREE PICK  ・  CHOOSE ANY " .. CAT_INFO[selCat].noun .. " YOU DON'T OWN")
			or left > 0 and ("ODDS  ・  " .. each .. " EACH  ・  NEVER A DUPLICATE")
			or ("YOU OWN EVERY " .. CAT_INFO[selCat].noun .. "!")
		oddsHead.TextColor3 = waiting > 0 and GOLD or SOFT
		for id, r in pairs(rows) do
			local mine = own[id] == true
			r.pct.Text = mine and "OWNED" or each
			r.pct.TextColor3 = mine and GREEN or GOLD
			r.name.TextTransparency = mine and 0.4 or 0
			local on = id == selItem
			r.stroke.Color = on and WHITE or INK
			r.button.BackgroundColor3 = on and Color3.fromRGB(64, 56, 100) or PANEL2
		end
		local mine = selItem ~= nil and own[selItem] == true
		boxTagT.Text = mine and "OWNED" or "NOT OWNED"
		boxTag.BackgroundColor3 = mine and GREEN or GREY
		pickBtn.Visible = waiting > 0 and selItem ~= nil and not mine
	end
	PK.refreshRolls = refresh
	PK.setRollPolicy = function(v) -- Studio test hook (ClientDebug "RollPolicy")
		restricted = v
		refresh()
	end

	-- showing / hiding the page starts / stops the preview
	local function onShown()
		if page.Visible and shade.Visible then
			pickCat(selCat, selItem)
		else
			pvToken += 1
			stopTrack()
		end
	end
	page:GetPropertyChangedSignal("Visible"):Connect(onShown)
	shade:GetPropertyChangedSignal("Visible"):Connect(onShown)
	for _, a in ipairs({ "Yen", "OwnedEmotes", "OwnedKO", "OwnedSkins", "ShopOffline", "KitsOwned", "RollPicks" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			if page.Visible then
				refresh()
			end
		end)
	end

	-- the reveal: ShopService writes LastRoll after every granted roll (Yen or Robux)
	local function lastRoll()
		local ok, r = pcall(function()
			return HttpService:JSONDecode(player:GetAttribute("LastRoll") or "")
		end)
		return (ok and type(r) == "table") and r or nil
	end
	local seen = (lastRoll() or {}).n
	-- (2026-11-10) the gacha reel (HudShared.RollReveal) plays first, full screen; the panel reveal below follows it
	local RollReveal
	do
		local okR, m = pcall(function()
			return require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("RollReveal", 5))
		end)
		RollReveal = okR and m or nil
	end
	player:GetAttributeChangedSignal("LastRoll"):Connect(function()
		local r = lastRoll()
		if not r or r.n == seen or not PerkCatalog.ROLLS[r.cat] then
			return
		end
		seen = r.n
		local ids = type(r.ids) == "table" and r.ids or { r.id }
		if RollReveal and #ids > 0 then
			local poolList = {}
			for _, x in ipairs(pool(r.cat)) do
				table.insert(poolList, { id = x.id })
			end
			RollReveal.play({ cat = r.cat, ids = ids, pool = poolList, color = PerkCatalog.ROLLS[r.cat].color, noun = CAT_INFO[r.cat].noun,
				pick = r.pick, nameOf = function(x)
					return itemName(r.cat, x)
				end })
		end
		local name = #ids > 1 and (#ids .. " NEW " .. CAT_INFO[r.cat].noun .. "S") or itemName(r.cat, r.id)
		if shade.Visible then
			if currentTab ~= "random" then
				currentTab = "random"
				refreshCards()
			end
			pickCat(r.cat, r.id)
			showReveal(r.cat, r.id, ids)
			if (tonumber(r.pick) or 0) > 0 then
				panelSay("YOU GOT " .. name .. " + 1 FREE PICK  -  CHOOSE YOUR 10TH ON THE RIGHT", GOLD)
			else
				panelSay("YOU GOT " .. name .. "!", GREEN)
			end
		else
			if (tonumber(r.pick) or 0) > 0 then
				showToast("YOU GOT " .. name .. " + 1 FREE PICK  -  CHOOSE IT IN THE SHOP'S ROLL TAB", GOLD)
			else
				showToast("YOU GOT " .. name .. "!  " .. (#ids > 1 and "THEY'RE" or "IT'S") .. " IN YOUR INVENTORY", PerkCatalog.ROLLS[r.cat].color)
			end
		end
	end)

	PK.openRolls = function(cat, id)
		if not PerkCatalog.ROLLS[cat] then
			return
		end
		if shade.Visible and currentTab == "random" then
			pickCat(cat, id)
			return
		end
		selCat, selItem = cat, id
		if builtCat ~= cat then
			buildRows(cat)
			builtCat = cat
		end
		currentTab = "random"
		setShop(true) -- (opening the page starts the preview: onShown)
		if not id then
			pickCat(cat)
		end
	end
end
buildRollShop()

-- INVENTORY panel (2026-11-07) ---------------------------------------------------------------------------------------
-- The shop's anime 2D recipe (ink panel, gradient banner, comic burst, screentone) in violet. Everything it shows is read
-- from the attributes ShopService writes (Perks / Perk_<Id> / SpeedMul / JumpMul / VIPAura / EquipTrail / EquipKO /
-- EquipSkins / KitsOwned) and redrawn when they change; every change goes back through ShopRequest "perkEquip".
-- Unowned items show a padlock and a Robux buy button (PromptProductPurchase).
do
	local GREEN, GREY, SOFT = Color3.fromRGB(70, 220, 130), Color3.fromRGB(90, 88, 110), Color3.fromRGB(200, 200, 222)
	local VIOLET, VIOLET2 = Color3.fromRGB(150, 80, 255), Color3.fromRGB(55, 20, 135)
	local byId = PerkCatalog.byId
	local TUNE = PerkCatalog.TUNING or {}

	local ishade = new("TextButton", { Name = "InventoryShade", Visible = false, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 30 }, gui)
	local ip = new("Frame", { Name = "Inventory", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(720, 470),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 31, Active = true }, ishade)
	corner(ip, 16)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(28, 20, 46), Color3.fromRGB(10, 9, 18)) }, ip)
	stroke(ip, INK, 3)
	PK.invScale = new("UIScale", {}, ip)
	for gy = 0, 5 do -- screentone, lower-left this time
		for gx = 0, 9 do
			local s = 3 + (gx + gy) * 0.55
			corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 16 + gx * 16, 1, -16 - gy * 16), Size = UDim2.fromOffset(16 - s, 16 - s),
				BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 31 }, ip))
		end
	end
	-- banner
	local hd = new("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 32 }, ip)
	corner(hd, 16)
	new("UIGradient", { Color = ColorSequence.new(VIOLET, VIOLET2) }, hd)
	local sqr = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ZIndex = 32 }, hd) -- squares off the banner's lower corners (same gradient, so no seam)
	new("UIGradient", { Color = ColorSequence.new(VIOLET, VIOLET2) }, sqr)
	new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK,
		BorderSizePixel = 0, ZIndex = 33 }, hd)
	for i = 1, 7 do -- speed lines
		new("Frame", { Position = UDim2.new(0.33 + i * 0.07, 0, 0, 8 + (i % 3) * 18), Size = UDim2.fromOffset(60 + (i % 4) * 30, 2),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 33 }, hd)
	end
	local bst = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(92, 36), Size = UDim2.fromOffset(116, 116),
		BackgroundTransparency = 1, ZIndex = 33 }, hd)
	for _, r in ipairs({ 0, 22.5, 45, 67.5 }) do -- comic burst
		stroke(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(74, 74), Rotation = r,
			BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 33 }, bst), INK, 2.5)
	end
	corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 34 }, bst))
	inkText(label(bst, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(98, 46), Text = "LOOT!",
		TextColor3 = WHITE, Rotation = -8, ZIndex = 35 }), 3)
	inkText(label(hd, { Position = UDim2.fromOffset(170, 12), Size = UDim2.fromOffset(240, 30), Text = "INVENTORY", TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 34 }), 2)
	label(hd, { Position = UDim2.fromOffset(172, 44), Size = UDim2.fromOffset(250, 16), Text = "持ち物  ・  your perks & cosmetics", FontFace = Kits.FONT_LABEL,
		TextColor3 = Color3.fromRGB(230, 215, 255), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 })
	local more = new("TextButton", { Name = "GetPerks", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -70, 0.5, -2), Size = UDim2.fromOffset(150, 38),
		Text = "", AutoButtonColor = false, BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 34 }, hd)
	corner(more)
	stroke(more, INK, 2.5)
	inkText(label(more, { Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), Text = "+ GET PERKS", ZIndex = 35 }), 1.5)
	local msc = new("UIScale", {}, more)
	more.MouseEnter:Connect(function()
		tween(msc, 0.1, { Scale = 1.06 })
	end)
	more.MouseLeave:Connect(function()
		tween(msc, 0.1, { Scale = 1 })
	end)
	local iclose = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, -2), Size = UDim2.fromOffset(40, 40),
		Text = "", AutoButtonColor = false, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 34 }, hd)
	corner(iclose)
	stroke(iclose, WHITE, 2)
	for _, r in ipairs({ 45, -45 }) do -- a drawn X
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 4), Rotation = r,
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 35 }, iclose)
	end

	-- body: one scrolling column of sections
	local body = new("ScrollingFrame", { Name = "Body", Position = UDim2.fromOffset(20, 86), Size = UDim2.new(1, -40, 1, -98), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = VIOLET, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 32 }, ip)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 34) }, body)

	local itoast = inkText(label(ip, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(460, 24),
		TextTransparency = 1, ZIndex = 40 }), 2)
	itoast:FindFirstChildOfClass("UIStroke").Transparency = 1
	local itok
	local function say(text, color)
		local tok = {}
		itok = tok
		itoast.Text = text
		itoast.TextColor3 = color or WHITE
		itoast.TextTransparency = 0
		local st = itoast:FindFirstChildOfClass("UIStroke")
		st.Transparency = 0
		task.delay(1.6, function()
			if itok == tok then
				tween(itoast, 0.35, { TextTransparency = 1 })
				tween(st, 0.35, { Transparency = 1 })
			end
		end)
	end

	-- widgets ------------------------------------------------------------------------------------------------------
	local order = 0
	local function addRow(h)
		order += 1
		return new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, ZIndex = 33 }, body)
	end
	local function padlock(parent, pos, z)
		local l = new("Frame", { Name = "Padlock", AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(16, 13),
			BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = z }, parent)
		corner(l, 3)
		stroke(l, INK, 1.5)
		local sh = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(10, 11),
			BackgroundTransparency = 1, ZIndex = z }, l)
		corner(sh)
		new("UIStroke", { Color = GOLD, Thickness = 2.5 }, sh)
		return l
	end
	local function orb(parent, it, size, pos, z, art) -- art (2026-11-10): the item table for CardArt
		local o = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = pos, Size = UDim2.fromOffset(size, size), BackgroundColor3 = WHITE,
			BorderSizePixel = 0, ZIndex = z }, parent)
		corner(o)
		local g = new("UIGradient", { Color = ColorSequence.new(it.color, it.color:Lerp(INK, 0.45)), Rotation = 90 }, o)
		stroke(o, INK, 2)
		inkText(label(o, { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), Text = it.glyph or "?",
			FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = z + 1 }), 1.5)
		if art then
			artOrb(o, art, 1.15)
		end
		return o, g
	end
	local buyButtons = {}
	local function buyButton(parent, it, pos, size, z)
		local b = new("TextButton", { Name = "Buy_" .. it.id, AnchorPoint = Vector2.new(1, 0.5), Position = pos, Size = size, Text = "",
			AutoButtonColor = false, BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = z }, parent)
		corner(b, 7)
		stroke(b, INK, 2)
		local t = inkText(label(b, { Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Text = PK.price(it), ZIndex = z + 1 }), 1.5)
		local sc = new("UIScale", {}, b)
		b.MouseEnter:Connect(function()
			tween(sc, 0.08, { Scale = 1.08 })
		end)
		b.MouseLeave:Connect(function()
			tween(sc, 0.08, { Scale = 1 })
		end)
		local function press()
			sc.Scale = 0.88
			tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			PK.buy(it, say)
		end
		b.Activated:Connect(press)
		PK.actions["Buy:" .. it.id] = press
		table.insert(buyButtons, { button = b, text = t, item = it })
		return b
	end
	local function switch(parent, pos, z, onFlip)
		local b = new("TextButton", { Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = pos, Size = UDim2.fromOffset(66, 28), Text = "",
			AutoButtonColor = false, BackgroundColor3 = GREY, BorderSizePixel = 0, ZIndex = z }, parent)
		corner(b)
		stroke(b, INK, 2)
		local txt = inkText(label(b, { Size = UDim2.fromOffset(30, 16), Position = UDim2.fromOffset(29, 6), Text = "OFF", ZIndex = z + 1 }), 1)
		local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z + 2 }, b)
		corner(knob)
		stroke(knob, INK, 1.5)
		local sw = { button = b }
		function sw.set(on)
			if sw.on == on then
				return
			end
			local first = sw.on == nil
			sw.on = on
			txt.Text = on and "ON" or "OFF"
			txt.Position = on and UDim2.fromOffset(7, 6) or UDim2.fromOffset(29, 6)
			local kp = on and UDim2.new(1, -24, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
			if first then
				knob.Position = kp
				b.BackgroundColor3 = on and GREEN or GREY
			else
				tween(knob, 0.18, { Position = kp }, Enum.EasingStyle.Back)
				tween(b, 0.18, { BackgroundColor3 = on and GREEN or GREY })
			end
		end
		b.Activated:Connect(function()
			onFlip(not sw.on)
		end)
		return sw
	end
	local statusList, overlays, catHeaders = {}, {}, {}
	local function header(title, jp, color, it, cat)
		local h = addRow(30)
		local left = new("Frame", { Size = UDim2.new(1, -210, 1, 0), BackgroundTransparency = 1, ZIndex = 33 }, h)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center }, left)
		local bar = new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(7, 22), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 34 }, left)
		corner(bar, 3)
		stroke(bar, INK, 1.5)
		inkText(label(left, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), TextScaled = false, TextSize = 24,
			Text = title, ZIndex = 34 }), 2)
		label(left, { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), TextScaled = false, TextSize = 13,
			Text = jp, FontFace = Kits.FONT_LABEL, TextColor3 = color, ZIndex = 34 })
		new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = color,
			BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 33 }, h)
		if cat then -- (2026-11-07) owned one item at a time: "n / total OWNED" + a button to that category's roll
			local rb = new("TextButton", { Name = "Roll_" .. cat, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, -2),
				Size = UDim2.fromOffset(118, 24), Text = "", AutoButtonColor = false, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 35 }, h)
			corner(rb, 7)
			stroke(rb, INK, 2)
			inkText(label(rb, { Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = "ROLL FOR MORE", ZIndex = 36 }), 1.5)
			rb.Activated:Connect(function()
				if PK.openRolls then
					PK.openRolls(cat)
				end
			end)
			local cnt = label(h, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -126, 0.5, -2), Size = UDim2.fromOffset(90, 15), FontFace = Kits.FONT_LABEL,
				TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 35 })
			table.insert(catHeaders, { cat = cat, count = cnt, more = rb })
		end
		if it then -- a section unlocked by ONE perk: OWNED, or a padlock + its Robux button
			local own = new("Frame", { Name = "Owned", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, -2), Size = UDim2.fromOffset(76, 20),
				BackgroundColor3 = GREEN, BorderSizePixel = 0, ZIndex = 34 }, h)
			corner(own, 6)
			stroke(own, INK, 1.5)
			inkText(label(own, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = "OWNED", ZIndex = 35 }), 1)
			local buy = buyButton(h, it, UDim2.new(1, 0, 0.5, -2), UDim2.fromOffset(96, 24), 35)
			local lk = padlock(h, UDim2.new(1, -112, 0.5, 0), 36)
			table.insert(statusList, { item = it, own = own, buy = buy, lock = lk })
		end
		return h
	end
	local function lockOverlay(parent, it) -- covers a locked section; tapping it opens the purchase prompt
		local o = new("TextButton", { Name = "Locked", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK,
			BackgroundTransparency = 0.18, BorderSizePixel = 0, ZIndex = 60 }, parent)
		corner(o, 10)
		stroke(o, GOLD, 1.5, 0.4)
		local tagPill = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 30),
			BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 61 }, o)
		corner(tagPill)
		stroke(tagPill, GOLD, 2)
		padlock(tagPill, UDim2.new(0, 22, 0.5, 3), 62)
		inkText(label(tagPill, { Position = UDim2.fromOffset(38, 6), Size = UDim2.new(1, -50, 1, -12),
			Text = "LOCKED  -  TAP TO UNLOCK " .. string.upper(it.name), TextColor3 = GOLD, ZIndex = 62 }), 1.5)
		o.Activated:Connect(function()
			PK.buy(it, say)
		end)
		table.insert(overlays, { overlay = o, item = it })
		return o
	end

	-- state: attributes, with a short optimistic override while a perkEquip call is in flight -------------------------
	local override, busy, skinOn, nextSend = {}, {}, {}, 0
	local refresh, flip, pick
	local function state(key)
		local o = override[key]
		if o then
			return o.v
		end
		if key == "Speed" then
			return (tonumber(player:GetAttribute("SpeedMul")) or 1) > 1
		elseif key == "Jump" then
			return (tonumber(player:GetAttribute("JumpMul")) or 1) > 1
		elseif key == "VIPAura" then
			return player:GetAttribute("VIPAura") == true
		elseif key == "Trail" then
			return player:GetAttribute("EquipTrail") or ""
		elseif key == "KO" then
			return player:GetAttribute("EquipKO") or ""
		end
		return skinOn[string.sub(key, 6)] == true -- "Skin:<kitId>"
	end
	local later = {} -- key -> the newest request made while one was in flight (the last tap wins)
	local function equip(key, slotName, value, shown, okText)
		if not ShopRequest then
			say("SHOP OFFLINE", RED)
			return
		end
		override[key] = { v = shown }
		refresh()
		if busy[key] then
			later[key] = { key, slotName, value, shown, okText }
			return
		end
		busy[key] = true
		task.spawn(function()
			-- the server refuses perkEquip calls closer than 0.15 s apart, so quick taps on different rows queue up
			local now = os.clock()
			local at = math.max(now, nextSend)
			nextSend = at + 0.2
			if at > now then
				task.wait(at - now)
			end
			local ok, a, b = pcall(function()
				return ShopRequest:InvokeServer("perkEquip", { slot = slotName, value = value })
			end)
			busy[key] = nil
			local q = later[key]
			later[key] = nil
			if q then
				if not (ok and a) then
					say(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
				end
				equip(table.unpack(q, 1, 5))
				return
			end
			if ok and a then
				say(okText, GREEN)
				task.delay(0.5, function()
					if not busy[key] then
						override[key] = nil
						refresh()
					end
				end)
			else
				override[key] = nil
				say(ok and tostring(b or "TRY AGAIN") or "TRY AGAIN", RED)
				refresh()
			end
		end)
	end
	local TOGGLE_PERK = { Speed = "SpeedX2", Jump = "JumpX2", VIPAura = "VIP" }
	local TOGGLE_NAME = { Speed = "2x SPEED", Jump = "2x JUMP", VIPAura = "VIP AURA" }
	flip = function(key, on)
		if string.sub(key, 1, 5) == "Skin:" then
			local kid = string.sub(key, 6)
			if on and not PK.owns("skin", kid) then -- (2026-11-07) skins are rolled one by one
				if PK.openRolls then
					PK.openRolls("skin", kid)
				end
				return
			end
			local k = Kits.byId[kid]
			equip(key, "Skin", { kit = kid, on = on }, on, ((k and k.name or kid) .. " SKIN " .. (on and "ON" or "OFF")))
			return
		end
		local need = byId[TOGGLE_PERK[key]]
		if need and not PK.has(need.id) then
			PK.buy(need, say)
			return
		end
		equip(key, key, on, on, TOGGLE_NAME[key] .. (on and " ON" or " OFF"))
	end
	pick = function(slotName, id, name, it, cat)
		if cat then -- (2026-11-07) owned one by one: a locked option opens its roll in the shop
			if id ~= "" and not PK.owns(cat, id) then
				if PK.openRolls then
					PK.openRolls(cat, id)
				end
				return
			end
		elseif not PK.has(it.id) then
			PK.buy(it, say)
			return
		end
		if state(slotName) == id then
			return
		end
		equip(slotName, slotName, id, id, (slotName == "Trail" and "TRAIL: " or "KO EFFECT: ") .. name)
	end

	-- 1+2. passive perks (ACTIVE badge) and toggles (switch) as tiles ---------------------------------------------------
	local tiles = {}
	local function tileRow(n, list, legacy) -- legacy (2026-11-14): a tile shows only while its perk is owned
		local row = addRow(100)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		for i, spec in ipairs(list) do
			local it = byId[spec[1]]
			if it then
				local t = new("Frame", { Name = "Tile_" .. it.id, LayoutOrder = i, Size = UDim2.new(1 / n, -10 * (n - 1) / n, 1, 0), BackgroundColor3 = PANEL2,
					BorderSizePixel = 0, ZIndex = 34 }, row)
				corner(t, 12)
				local st = stroke(t, INK, 2)
				new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, t)
				corner(new("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = it.color, BorderSizePixel = 0, ZIndex = 35 }, t), 2)
				local _, og = orb(t, it, 42, UDim2.new(0, 10, 0, 34), 35, it)
				inkText(label(t, { Position = UDim2.fromOffset(60, 12), Size = UDim2.new(1, -68, 0, 24), Text = string.upper(it.name), TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 }), 1.5)
				label(t, { Position = UDim2.fromOffset(60, 38), Size = UDim2.new(1, -68, 0, 14), Text = spec[2], FontFace = Kits.FONT_LABEL,
					TextColor3 = it.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
				local lockText = label(t, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 1, -21), Size = UDim2.fromOffset(50, 16),
					Text = "LOCKED", FontFace = Kits.FONT_LABEL, TextColor3 = Color3.fromRGB(150, 148, 172), TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 35 })
				local tl = { item = it, stroke = st, orbGrad = og, lockText = lockText, key = spec[3], frame = t, legacy = legacy,
					lock = padlock(t, UDim2.fromOffset(46, 50), 38),
					buy = buyButton(t, it, UDim2.new(1, -10, 1, -21), UDim2.fromOffset(84, 26), 36) }
				if spec[3] then -- a toggle: caption + switch
					local key = spec[3]
					tl.caption = label(t, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 1, -21), Size = UDim2.new(1, -100, 0, 16),
						Text = spec[4] or "", FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
					tl.switch = switch(t, UDim2.new(1, -10, 1, -21), 36, function(on)
						flip(key, on)
					end)
					PK.actions[key] = function()
						flip(key, not state(key))
					end
				else -- passive: an ACTIVE badge on a pulsing glow
					local glow = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 7, 1, -21), Size = UDim2.fromOffset(92, 32),
						BackgroundColor3 = GREEN, BackgroundTransparency = 0.7, BorderSizePixel = 0, Visible = false, ZIndex = 35 }, t)
					corner(glow, 10)
					TweenService:Create(glow, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ BackgroundTransparency = 0.95, Size = UDim2.fromOffset(100, 38), Position = UDim2.new(0, 3, 1, -21) }):Play()
					local badge = new("Frame", { Name = "Active", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 1, -21), Size = UDim2.fromOffset(86, 26),
						BackgroundColor3 = GREEN, BorderSizePixel = 0, Visible = false, ZIndex = 36 }, t)
					corner(badge, 8)
					stroke(badge, INK, 2)
					local led = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(9, 9),
						BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 37 }, badge)
					corner(led)
					stroke(led, INK, 1.5)
					inkText(label(badge, { Position = UDim2.fromOffset(22, 4), Size = UDim2.new(1, -28, 1, -8), Text = "ACTIVE", ZIndex = 37 }), 1.5)
					tl.badge, tl.glow = badge, glow
				end
				table.insert(tiles, tl)
			end
		end
		return row
	end
	local function pct(m)
		return tostring(math.floor((1 - (m or 1)) * 100 + 0.5))
	end
	-- (2026-11-14, sandbox shop) the sandbox's perks first, then the sliders (their own panel), then the retired PvP perks,
	-- which show only to a player who owns one (LEGACY PERKS)
	header("SANDBOX PERKS", "砂場  -  always on", Color3.fromRGB(255, 205, 70))
	local passiveTiles = {
		{ "SpawnPlus", "x" .. tostring(TUNE.SPAWN_CAP_MUL or 3) .. " SPAWN LIMITS" },
		{ "KillFXPack", "EVERY KILL EFFECT" },
		{ "YenX2", "x" .. tostring(TUNE.YEN_MUL or 2) .. " YEN" },
		{ "VIP", "GOLD TAG + AURA + " .. pct(2 - (TUNE.VIP_YEN_MUL or 1.25)) .. "% YEN", "VIPAura", "GOLD AURA" },
	}
	if KCFG.ALL_FREE ~= true then -- every fighter is free right now: no bundle tile (and no buy button) in the inventory
		table.insert(passiveTiles, 3, { "AllFighters", "EVERY FIGHTER" })
	end
	tileRow(#passiveTiles, passiveTiles)
	local slidersSub
	do -- the SANDBOX SLIDERS: one row that opens their panel
		header("SANDBOX SLIDERS", "調整  -  run, jump, gravity, health, strength, fling", Color3.fromRGB(90, 200, 255))
		local wrap = addRow(62)
		local b = new("TextButton", { Name = "OpenSliders", Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, BackgroundColor3 = PANEL2,
			BorderSizePixel = 0, ZIndex = 34 }, wrap)
		corner(b, 12)
		stroke(b, INK, 2)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, b)
		inkText(label(b, { Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -200, 0, 26), Text = "YOUR OWN PHYSICS", TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 35 }), 2)
		slidersSub = label(b, { Position = UDim2.fromOffset(18, 36), Size = UDim2.new(1, -200, 0, 16), Text = "", FontFace = Kits.FONT_LABEL, TextColor3 = SOFT,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
		local go = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 38),
			BackgroundColor3 = Color3.fromRGB(90, 200, 255), BorderSizePixel = 0, ZIndex = 35 }, b)
		corner(go, 9)
		stroke(go, INK, 2)
		inkText(label(go, { Size = UDim2.new(1, -14, 1, -12), Position = UDim2.fromOffset(7, 6), Text = "OPEN SLIDERS", ZIndex = 36 }), 1.5)
		local function openSliders()
			PK.setInv(false)
			local ev = ReplicatedStorage:FindFirstChild("HudShared") and ReplicatedStorage.HudShared:FindFirstChild("OpenPanel")
			if ev then
				ev:Fire("sliders")
			end
		end
		b.Activated:Connect(openSliders)
		PK.actions.OpenSliders = openSliders
	end
	local legacyHeader = header("LEGACY PERKS", "旧  -  no longer sold, still yours", Color3.fromRGB(150, 148, 172))
	local legacyRow = tileRow(5, {
		{ "Cooldowns", "-" .. pct(TUNE.COOLDOWN_MUL) .. "% COOLDOWNS" },
		{ "UltCharge", "-" .. pct(TUNE.ULT_CHARGE_MUL) .. "% ULT TIME" },
		{ "DashPass", "-" .. pct(TUNE.DASH_COOLDOWN_MUL or 0.5) .. "% DASH COOLDOWN" },
		{ "SpeedX2", "NOW THE RUN SLIDER" },
		{ "JumpX2", "NOW THE JUMP SLIDER" },
	}, true)

	-- 3+4. pickers: trail and KO effect (NONE + the catalog's options) ---------------------------------------------
	local function cs(points)
		local k = {}
		for i, p in ipairs(points) do
			k[i] = ColorSequenceKeypoint.new(p[1], Color3.fromRGB(p[2], p[3], p[4]))
		end
		return ColorSequence.new(k)
	end
	local SWATCH = {
		Rainbow = cs({ { 0, 255, 60, 60 }, { 0.2, 255, 170, 40 }, { 0.4, 255, 240, 60 }, { 0.6, 60, 230, 120 }, { 0.8, 60, 140, 255 }, { 1, 190, 80, 255 } }),
		Gold = cs({ { 0, 255, 245, 170 }, { 0.5, 255, 200, 50 }, { 1, 190, 110, 10 } }),
		BlackFlame = cs({ { 0, 15, 8, 25 }, { 0.5, 140, 50, 230 }, { 1, 15, 8, 25 } }),
		Confetti = cs({ { 0, 255, 90, 180 }, { 0.32, 255, 90, 180 }, { 0.34, 255, 230, 70 }, { 0.65, 255, 230, 70 }, { 0.67, 80, 220, 255 }, { 1, 80, 220, 255 } }),
		Explosion = cs({ { 0, 255, 245, 150 }, { 0.45, 255, 130, 30 }, { 1, 170, 25, 20 } }),
		Lightning = cs({ { 0, 255, 255, 255 }, { 0.5, 110, 220, 255 }, { 1, 60, 80, 255 } }),
	}
	local pickers = {}
	local function picker(title, jp, it, slotName, list, cat)
		if not it then
			return
		end
		header(title, jp, it.color, (not cat) and it or nil, cat)
		local opts = { { id = "", name = "NONE" } }
		for _, o in ipairs(list or {}) do
			table.insert(opts, o)
		end
		local n = #opts
		-- (2026-11-14) more than six options (the kill effects): a grid, five to a row
		local cols = n > 6 and 5 or n
		local lines = math.ceil(n / cols)
		local wrap = addRow(lines * 54 + (lines - 1) * 10)
		local row = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 34 }, wrap)
		if n > 6 then
			new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -8, 0, 54), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		else
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		end
		local chips = {}
		for i, o in ipairs(opts) do
			local tag = o.id == "" and "None" or o.id
			local b = new("TextButton", { Name = slotName .. "_" .. tag, LayoutOrder = i, AutoButtonColor = false, Text = "",
				Size = UDim2.new(1 / n, -10 * (n - 1) / n, 1, 0), BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 35 }, row)
			corner(b, 10)
			local st = stroke(b, INK, 2)
			local sw = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 12), BackgroundColor3 = WHITE, BorderSizePixel = 0,
				ZIndex = 36 }, b)
			corner(sw, 6)
			stroke(sw, INK, 1.5)
			new("UIGradient", { Color = SWATCH[o.id] or ColorSequence.new(Color3.fromRGB(70, 68, 92), Color3.fromRGB(45, 43, 62)) }, sw)
			local nameL = inkText(label(b, { Position = UDim2.fromOffset(8, 25), Size = UDim2.new(1, -16, 0, 22), Text = o.name, ZIndex = 36 }), 1.5)
			-- (2026-11-10) CardArt: a trail / KO effect's art in a square on the chip's left; the swatch + name move over beside it
			if o.id ~= "" then
				local slot = new("Frame", { Name = "ArtSlot", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 5, 0.5, 0), Size = UDim2.fromOffset(44, 44),
					BackgroundTransparency = 1, ZIndex = 36 }, b)
				if drawArt(slot, { kind = slotName == "Trail" and "trail" or "ko", id = o.id }) then
					sw.Position, sw.Size = UDim2.fromOffset(54, 8), UDim2.new(1, -62, 0, 12)
					nameL.Position, nameL.Size = UDim2.fromOffset(54, 25), UDim2.new(1, -62, 0, 22)
				else
					slot:Destroy()
				end
			end
			local chipLock = padlock(b, UDim2.new(1, -16, 0, 14), 38)
			chipLock.Visible = false
			local sc = new("UIScale", {}, b)
			local function press()
				sc.Scale = 0.9
				tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				pick(slotName, o.id, o.name, it, cat)
			end
			b.Activated:Connect(press)
			PK.actions[slotName .. ":" .. tag] = press
			chips[o.id] = { button = b, stroke = st, name = nameL, lock = chipLock }
		end
		table.insert(pickers, { item = it, slot = slotName, chips = chips, cat = cat })
		if not cat then
			lockOverlay(wrap, it)
		end
	end
	picker("TRAILS", "軌跡  -  on your punches", byId.Trails, "Trail", PerkCatalog.TRAILS)
	picker("KILL EFFECTS", "撃破  -  every time you kill a dummy", byId.KOFX, "KO", PerkCatalog.KO, "ko")

	-- 5. fighter skins: one switch per fighter the player owns ------------------------------------------------------
	local skinItem = byId.Skins
	local skinRows, skinWrap, skinEmpty = {}, nil, nil
	if skinItem then
		header("FIGHTER SKINS", "スキン  -  one colourway per fighter", skinItem.color, nil, "skin")
		skinWrap = addRow(48)
		local sg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 34 }, skinWrap)
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 48), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }, sg)
		skinEmpty = label(skinWrap, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 20), Text = "UNLOCK A FIGHTER TO SKIN IT",
			FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, Visible = false, ZIndex = 34 })
		for i, kit in ipairs(Kits.list) do
			if kit.noPowers then
				continue -- NORMAL has no colourway to switch
			end
			local r = new("Frame", { Name = "Skin_" .. kit.id, LayoutOrder = i, BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 35 }, sg)
			corner(r, 10)
			local st = stroke(r, INK, 2)
			local se = emblem(r, 36, kit, UDim2.new(0, 6, 0.5, 0))
			se.ZIndex = 36
			artOrb(se, { kind = "skin", kit = kit.id, id = kit.id }, 1.15) -- (2026-11-10) the skin's CardArt
			inkText(label(r, { Position = UDim2.fromOffset(50, 5), Size = UDim2.new(1, -134, 0, 20), Text = kit.name, TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 36 }), 1.5)
			label(r, { Position = UDim2.fromOffset(50, 27), Size = UDim2.new(1, -134, 0, 14), Text = (PerkCatalog.SKINS or {})[kit.id] or "ALT COLOURWAY",
				FontFace = Kits.FONT_LABEL, TextColor3 = kit.accent, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 })
			local key = "Skin:" .. kit.id
			local sw = switch(r, UDim2.new(1, -10, 0.5, 0), 37, function(on)
				flip(key, on)
			end)
			PK.actions[key] = function()
				flip(key, not state(key))
			end
			-- (2026-11-07) a skin not rolled yet: a padlock + ROLL (opens the RANDOM tab on it)
			local lk = padlock(r, UDim2.new(1, -84, 0.5, 0), 38)
			local rollTag = new("TextButton", { Name = "Roll", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(62, 26),
				Text = "", AutoButtonColor = false, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 37 }, r)
			corner(rollTag, 7)
			stroke(rollTag, INK, 2)
			inkText(label(rollTag, { Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4), Text = "ROLL", ZIndex = 38 }), 1.5)
			rollTag.Activated:Connect(function()
				if PK.openRolls then
					PK.openRolls("skin", kit.id)
				end
			end)
			skinRows[kit.id] = { row = r, stroke = st, switch = sw, kit = kit, lock = lk, rollTag = rollTag }
		end
	end

	-- 6. emotes: play buttons (PerkShared.Emotes.play; the B-key wheel is the emote system's) -----------------------
	local emoteItem = byId.Emotes
	local emoteBtns = {}
	local function playEmote(id)
		if not PK.owns("emote", id) then -- (2026-11-07) emotes are rolled one by one
			if PK.openRolls then
				PK.openRolls("emote", id)
			end
			return
		end
		local mod = PerkShared and PerkShared:FindFirstChild("Emotes")
		local okReq, E = false, nil
		if mod then
			okReq, E = pcall(require, mod)
		end
		if not okReq or type(E) ~= "table" or type(E.play) ~= "function" then
			say("EMOTES ARE STILL LOADING - TRY AGAIN", GOLD)
			return
		end
		local ok, res, msg = pcall(E.play, id)
		if not ok or res == false then
			say(type(msg) == "string" and msg or "CAN'T EMOTE RIGHT NOW", RED)
			return
		end
		PK.setInv(false) -- get out of the way so the emote is seen
	end
	if emoteItem then
		local okK, KB = pcall(require, ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Keybinds"))
		header("EMOTES", "エモート  -  or press " .. (okK and KB and KB.label(Enum.KeyCode.B) or "B"), emoteItem.color, nil, "emote")
		-- (2026-11-07 wheel) a GRID, not one row: up to 4 a row, 3 or 4 columns after that (12 emotes = 4 x 3), as many
		-- rows as the list needs. Glyphs come from the emote packs (Clips.GLYPH), and like the B wheel an id with no clip
		-- is left out (only when Clips loaded: a failed load shows the whole catalog rather than nothing)
		local GLYPH = { Taunt = "挑", Laugh = "笑", Victory = "勝" }
		local okClips, EC = pcall(function()
			local m = PerkShared and PerkShared:FindFirstChild("Emotes")
			local c = m and m:FindFirstChild("Clips")
			return c and require(c) or nil
		end)
		local clipSet = okClips and type(EC) == "table" and EC or nil
		local packGlyph = clipSet and type(clipSet.GLYPH) == "table" and clipSet.GLYPH or {}
		local list = {}
		for _, o in ipairs(PerkCatalog.EMOTES or {}) do
			if not clipSet or (type(clipSet[o.id]) == "table" and clipSet[o.id].keys) then
				table.insert(list, o)
			end
		end
		local n = math.max(#list, 1)
		local cols = n <= 4 and n or ((n <= 6 or n == 9) and 3 or 4)
		local rows = math.ceil(n / cols)
		local CELL_H, ROW_GAP = 56, 8
		local wrap = addRow(rows * CELL_H + (rows - 1) * ROW_GAP)
		local row = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 34 }, wrap)
		-- (2026-11-07 QA) a UDim offset is an INTEGER: -7.5 truncated to -7 left 4 cells 2 px wider than the row, so the
		-- grid wrapped 12 emotes into 3 columns x 4 rows and the 4th row hung out of `wrap`. floor(gap share) + 1 px always fits.
		new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -math.floor(10 * (cols - 1) / cols) - 1, 0, CELL_H), CellPadding = UDim2.fromOffset(10, ROW_GAP),
			FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local narrow = cols >= 4 -- a 4-wide cell has no room for the long locked caption
		for i, o in ipairs(list) do
			local b = new("TextButton", { Name = "Emote_" .. o.id, LayoutOrder = i, AutoButtonColor = false, Text = "",
				BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 35 }, row)
			corner(b, 12)
			stroke(b, INK, 2)
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(46, 40, 72), Color3.fromRGB(22, 20, 36)) }, b)
			orb(b, { color = emoteItem.color, glyph = packGlyph[o.id] or GLYPH[o.id] or emoteItem.glyph }, 38, UDim2.new(0, 10, 0.5, 0), 36,
				{ kind = "emote", id = o.id })
			inkText(label(b, { Position = UDim2.fromOffset(58, 9), Size = UDim2.new(1, -66, 0, 24), Text = o.name, TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 36 }), 2)
			local subL = label(b, { Position = UDim2.fromOffset(58, 35), Size = UDim2.new(1, -66, 0, 12), Text = "TAP TO PLAY", FontFace = Kits.FONT_LABEL,
				TextColor3 = emoteItem.color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 36 })
			-- the padlock sits on the orb's corner so a long name keeps the whole width of the cell
			emoteBtns[o.id] = { sub = subL, lock = padlock(b, UDim2.new(0, 45, 0.5, 13), 38), narrow = narrow }
			local sc = new("UIScale", {}, b)
			b.MouseEnter:Connect(function()
				tween(sc, 0.1, { Scale = 1.04 })
			end)
			b.MouseLeave:Connect(function()
				tween(sc, 0.1, { Scale = 1 })
			end)
			local function press()
				sc.Scale = 0.9
				tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				playEmote(o.id)
			end
			b.Activated:Connect(press)
			PK.actions["Emote:" .. o.id] = press
		end
	end

	-- redraw from the attributes ------------------------------------------------------------------------------------
	refresh = function()
		local perks = PK.set()
		local function has(id)
			return perks[id] == true or player:GetAttribute("Perk_" .. id) == true
		end
		table.clear(skinOn)
		local ok, l = pcall(function()
			return HttpService:JSONDecode(player:GetAttribute("EquipSkins") or "[]")
		end)
		for _, k in ipairs(ok and type(l) == "table" and l or {}) do
			skinOn[k] = true
		end
		local anyLegacy = false
		for _, t in ipairs(tiles) do
			local own = has(t.item.id)
			if t.legacy then -- (2026-11-14) retired perks: shown only while owned
				t.frame.Visible = own
				anyLegacy = anyLegacy or own
			end
			t.lock.Visible = not own
			t.lockText.Visible = not own
			t.buy.Visible = not own
			t.stroke.Color = own and t.item.color or INK
			t.orbGrad.Color = own and ColorSequence.new(t.item.color, t.item.color:Lerp(INK, 0.45))
				or ColorSequence.new(Color3.fromRGB(130, 128, 145), Color3.fromRGB(46, 44, 60))
			if t.badge then
				t.badge.Visible = own
				t.glow.Visible = own
			end
			if t.switch then
				t.switch.button.Visible = own
				t.caption.Visible = own
				t.switch.set(state(t.key))
			end
		end
		legacyHeader.Visible = anyLegacy
		legacyRow.Visible = anyLegacy
		if slidersSub then
			local okS, ownedS = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("SliderOwned") or "[]")
			local nS = okS and type(ownedS) == "table" and #ownedS or 0
			slidersSub.Text = nS .. " / 6 SLIDERS UNLOCKED  -  run speed, jump, gravity, health + god mode, strength, fling power"
		end
		for _, p in ipairs(pickers) do
			local cur = (p.cat or has(p.item.id)) and state(p.slot) or nil
			local ownSet = p.cat and PK.owned(p.cat) or nil
			for id, c in pairs(p.chips) do
				local on = id == cur
				c.stroke.Color = on and WHITE or INK
				c.stroke.Thickness = on and 3 or 2
				c.button.BackgroundColor3 = on and p.item.color:Lerp(INK, 0.5) or PANEL2
				local locked = ownSet ~= nil and id ~= "" and not ownSet[id]
				c.lock.Visible = locked
				c.name.TextTransparency = locked and 0.5 or 0
			end
		end
		for _, ch in ipairs(catHeaders) do
			local own, n, total = PK.owned(ch.cat), 0, #PerkCatalog.pool(ch.cat)
			for _ in pairs(own) do
				n += 1
			end
			ch.count.Text = n .. " / " .. total .. " OWNED"
			ch.more.Visible = n < total
		end
		local emOwned = PK.owned("emote")
		for id, e in pairs(emoteBtns) do
			local own = emOwned[id] == true
			e.lock.Visible = not own
			e.sub.Text = own and "TAP TO PLAY" or (e.narrow and "TAP TO ROLL" or "LOCKED  -  TAP TO ROLL")
		end
		for _, o in ipairs(overlays) do
			o.overlay.Visible = not has(o.item.id)
		end
		for _, s in ipairs(statusList) do
			local own = has(s.item.id)
			s.own.Visible = own
			s.buy.Visible = not own
			s.lock.Visible = not own
		end
		if skinWrap then -- only fighters the player owns (every roster fighter with All Fighters)
			local kitsOwned, all, n = ownedKits(), has("AllFighters"), 0
			local skinOwned = PK.owned("skin")
			for id, r in pairs(skinRows) do
				local vis = all or kitsOwned[id] == true or skinOwned[id] == true
				r.row.Visible = vis
				if vis then
					n += 1
				end
				local on = state("Skin:" .. id)
				r.switch.set(on)
				r.stroke.Color = on and r.kit.accent or INK
				local own = skinOwned[id] == true
				r.switch.button.Visible = own
				r.lock.Visible = not own
				r.rollTag.Visible = not own
			end
			skinWrap.Size = UDim2.new(1, 0, 0, n == 0 and 48 or math.ceil(n / 2) * 56 - 8)
			skinEmpty.Visible = n == 0
		end
		for _, b in ipairs(buyButtons) do
			local pid = PK.buyable(b.item)
			b.text.Text = pid and PK.price(b.item) or "COMING SOON"
			b.button.BackgroundColor3 = pid and GREEN or GREY
		end
		local count, total = 0, 0
		for _, it in ipairs(PerkCatalog.ITEMS) do
			if it.kind == "perk" and not it.offer and not it.retired then
				total += 1
				if has(it.id) then
					count += 1
				end
			end
		end
		invSub.Text = count .. "/" .. total .. " PERKS"
	end
	PK.refreshInv = refresh

	-- open / close ----------------------------------------------------------------------------------------------------
	PK.setInv = function(on)
		if on then
			setDrop(false)
			if shade.Visible then
				setShop(false)
			end
			refresh()
			invDot.Visible = false
			ishade.Visible = true
			ishade.BackgroundTransparency = 1
			tween(ishade, 0.2, { BackgroundTransparency = 0.45 })
			ip.Position = UDim2.fromScale(0.5, 0.58)
			tween(ip, 0.28, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
		else
			ishade.Visible = false
		end
	end
	PK.closePanels = function()
		if shade.Visible then
			setShop(false)
		end
		PK.setInv(false)
	end
	invPill.Activated:Connect(function()
		PK.setInv(not ishade.Visible)
	end)
	iclose.Activated:Connect(function()
		PK.setInv(false)
	end)
	ishade.Activated:Connect(function()
		PK.setInv(false)
	end)
	local function openRobuxTab()
		PK.setInv(false)
		currentTab = "perks" -- (2026-11-11) the PERKS tab (was ROBUX)
		grid.CanvasPosition = Vector2.zero
		setShop(true)
	end
	more.Activated:Connect(openRobuxTab)
	PK.actions.GetPerks = openRobuxTab

	-- live updates: any perk / equip attribute redraws both the inventory and the ROBUX tab (once per frame) ---------
	local WATCH = { Perks = true, SpeedMul = true, JumpMul = true, EquipTrail = true, EquipKO = true, EquipSkins = true, VIPAura = true,
		OwnedEmotes = true, OwnedKO = true, OwnedSkins = true,
		KitsOwned = true, ShopOffline = true }
	local queued = false
	player.AttributeChanged:Connect(function(name)
		if (WATCH[name] or string.sub(name, 1, 5) == "Perk_") and not queued then
			queued = true
			task.defer(function()
				queued = false
				refresh()
				refreshCards()
			end)
		end
	end)
	-- a perk that arrives (a purchase, or ShopService.PerkGrantTest in Studio) is announced; the first publish is not
	local known = player:GetAttribute("Perks") ~= nil and PK.set() or nil
	player:GetAttributeChangedSignal("Perks"):Connect(function()
		local now = PK.set()
		if known then
			for id in pairs(now) do
				local it = not known[id] and byId[id]
				if it and not it.offer then -- a bundle announces itself in its own popup; its contents get the toasts
					local msg = "UNLOCKED: " .. string.upper(it.name) .. "!"
					showToast(msg .. " TAP IT IN THE SHOP TO USE IT", it.color) -- (2026-11-14) was "OPEN YOUR INVENTORY": that button is gone
					if ishade.Visible then
						say(msg, GREEN)
					else
						invDot.Visible = true
					end
					local sc = invPill:FindFirstChildOfClass("UIScale")
					if sc then
						sc.Scale = 1.25
						tween(sc, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
					end
				end
			end
		end
		known = now
	end)
	-- the purchase itself: a success toast the moment Roblox confirms it (the grant follows once the server has saved)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= player.UserId or not purchased then
			return
		end
		local it = PerkCatalog.byProduct[productId]
		if not it then
			for _, x in ipairs(PerkCatalog.ITEMS) do
				if x.product == productId then
					it = x
					break
				end
			end
		end
		if not it then
			return -- a fighter product: the handler above owns that
		end
		local msg = it.kind == "perk" and ("PURCHASED " .. string.upper(it.name) .. "! UNLOCKING...")
			or it.yen and ("+" .. fmtYen(it.yen) .. " INCOMING - THANK YOU!")
			or it.id == "Meteor" and "METEOR SHOWER INCOMING!"
			or it.id == "UltNow" and "ULTIMATE CHARGED - UNLEASH IT!"
			or ("PURCHASED " .. string.upper(it.name) .. "!")
		showToast(msg, it.color or GOLD)
		if shade.Visible then
			panelSay(msg, GREEN)
		end
		if ishade.Visible then
			say(msg, GREEN)
		end
		local c = perkCards[it.id]
		if c then
			c.scale.Scale = 1.12
			tween(c.scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	-- the real Robux prices once products exist (labels show the catalog price until then)
	task.spawn(function()
		local any = false
		for _, it in ipairs(PerkCatalog.ITEMS) do
			local pid = PK.product(it) or PK.pass(it)
			if pid then
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pid,
					PK.product(it) and Enum.InfoType.Product or Enum.InfoType.GamePass)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					PK.priceText[it.id] = info.PriceInRobux
					any = true
				end
			end
		end
		if any then
			refresh()
			refreshCards()
		end
	end)
	refresh()
end

-- STARTER PACK offer (2026-11-07) ----------------------------------------------------------------------------------
-- PerkCatalog "StarterPack" (offer = true): a one-time Robux bundle (contents.perks + contents.yen; ShopService grants
-- them). While this player can buy it, a STARTER PACK pill sits at the end of the top strip, and the popup opens by
-- itself ONCE per session: 1.5 s after the 3rd KO this session, or after 5 minutes of play - never before the starter
-- pick, never over an open shop / inventory / dropdown (it retries on the next KO, and every 5 s after 5 minutes).
-- Only offered to players who own none of it (the pack, or any perk inside). The popup's VALUE is PerkCatalog.worth
-- (the perks at their own prices + the Yen at the cheapest Yen-pack rate), so the discount shown is real.
-- product 0 = not created yet: hidden in live servers, shown in Studio (the button says COMING SOON).
-- Studio: GojoShared.ClientDebug:Fire("StarterOffer", true | false).
local function buildStarterOffer()
	local it = PerkCatalog.byId.StarterPack
	if not (it and type(it.contents) == "table") then
		return
	end
	local AUTO_KOS, AUTO_SECONDS = 3, 300
	local C0 = it.color or GOLD
	local C1 = C0:Lerp(RED2, 0.6)
	local GREEN, GREY, SOFT = Color3.fromRGB(70, 220, 130), Color3.fromRGB(90, 88, 110), Color3.fromRGB(170, 170, 195)
	local worth = PerkCatalog.worth(it)
	local W, H = 460, 360

	local function priceNow()
		return tonumber(PK.priceText[it.id]) or it.price
	end
	local function eligible()
		if not PK.product(it) and not RunService:IsStudio() then
			return false
		end
		if player:GetAttribute("StarterPicked") ~= true or player:GetAttribute("ShopOffline") == true then
			return false
		end
		if PK.has(it.id) then
			return false
		end
		for _, id in ipairs(it.contents.perks or {}) do
			if PK.has(id) then
				return false
			end
		end
		return true
	end

	-- the pill (after INVENTORY): a gift badge that wiggles every few seconds
	strip.Size = UDim2.fromOffset(820, PILL_H)
	local spPill = pill(4, 172)
	spPill.Name = "StarterPackPill"
	spPill.Visible = false
	local badge = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0), Size = UDim2.fromOffset(PILL_H - 8, PILL_H - 8),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, spPill)
	corner(badge)
	new("UIGradient", { Color = ColorSequence.new(C0, C1), Rotation = 60 }, badge)
	stroke(badge, INK, 1.5)
	local badgeGlyph = inkText(label(badge, { Size = UDim2.fromScale(0.68, 0.68), Position = UDim2.fromScale(0.16, 0.16), Text = it.glyph or "!",
		FontFace = Font.fromEnum(Enum.Font.GothamBlack) }), 1.5)
	-- (2026-11-11) the Starter Pack's CardArt (the same art as its shop card) drawn inside a round CanvasGroup mask, so the
	-- square card scene is cut to the badge's circle like the CHARACTER / SHOP / INVENTORY icons; the ink ring stays on
	-- top. No art -> the mask goes and the glyph stays.
	local mask = new("CanvasGroup", { Name = "ArtMask", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = badge.ZIndex + 1 }, badge)
	corner(mask)
	if drawArt(mask, it) then
		badgeGlyph.Visible = false
	else
		mask:Destroy()
	end
	inkText(label(spPill, { Position = UDim2.fromOffset(PILL_H + 2, 6), Size = UDim2.new(1, -PILL_H - 10, 0, 18), Text = "STARTER PACK",
		TextXAlignment = Enum.TextXAlignment.Left }))
	local spSub = label(spPill, { Position = UDim2.fromOffset(PILL_H + 2, 24), Size = UDim2.new(1, -PILL_H - 10, 0, 11), Text = "ONE-TIME OFFER",
		TextXAlignment = Enum.TextXAlignment.Left, FontFace = Kits.FONT_LABEL, TextColor3 = C0 })

	-- the popup: the shop's anime recipe (ink panel, gradient banner, comic burst, screentone) in orange
	local oshade = new("TextButton", { Name = "StarterOfferShade", Visible = false, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, ZIndex = 50 }, gui)
	local op = new("Frame", { Name = "StarterOffer", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 51, Active = true }, oshade)
	corner(op, 16)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(24, 20, 40), Color3.fromRGB(10, 9, 18)) }, op)
	stroke(op, INK, 3)
	PK.offerScale = new("UIScale", {}, op)
	for gy = 0, 3 do
		for gx = 0, 7 do
			local s = 3 + (gx + gy) * 0.6
			corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -16 - gx * 16, 1, -16 - gy * 16), Size = UDim2.fromOffset(16 - s, 16 - s),
				BackgroundColor3 = WHITE, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 51 }, op))
		end
	end

	local hd = new("Frame", { Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 52 }, op)
	corner(hd, 16)
	new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hd)
	local hsq = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, ZIndex = 52 }, hd) -- squares off the banner's lower corners
	new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hsq)
	new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = INK,
		BorderSizePixel = 0, ZIndex = 53 }, hd)
	for i = 1, 6 do
		new("Frame", { Position = UDim2.new(0.38 + i * 0.055, 0, 0, 8 + (i % 3) * 18), Size = UDim2.fromOffset(36 + (i % 4) * 18, 2),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.72, BorderSizePixel = 0, ZIndex = 53 }, hd)
	end
	-- the discount burst: two squares at 0 and 45 degrees (+ two more) make a star
	local burst = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(68, 40), Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1, ZIndex = 54 }, hd)
	for _, r in ipairs({ 0, 22.5, 45, 67.5 }) do
		stroke(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64), Rotation = r,
			BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 54 }, burst), INK, 2.5)
	end
	corner(new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(66, 66), BackgroundColor3 = GOLD,
		BorderSizePixel = 0, ZIndex = 55 }, burst))
	local burstText = inkText(label(burst, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(74, 32),
		Rotation = -8, ZIndex = 56 }), 2.5)
	local burstSub = label(burst, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 2, 0.5, 8), Size = UDim2.fromOffset(44, 12), Text = "OFF",
		FontFace = Kits.FONT_LABEL, TextColor3 = INK, Rotation = -8, ZIndex = 56 })
	inkText(label(hd, { Position = UDim2.fromOffset(132, 12), Size = UDim2.fromOffset(250, 32), Text = "STARTER PACK",
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 54 }), 2)
	label(hd, { Position = UDim2.fromOffset(134, 46), Size = UDim2.fromOffset(250, 16), Text = "初心者パック  ・  one per player", FontFace = Kits.FONT_LABEL,
		TextColor3 = Color3.fromRGB(255, 238, 220), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 54 })
	local xBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, -2), Size = UDim2.fromOffset(36, 36),
		Text = "", AutoButtonColor = false, BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 54 }, hd)
	corner(xBtn)
	stroke(xBtn, WHITE, 2)
	for _, r in ipairs({ 45, -45 }) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 4), Rotation = r,
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 55 }, xBtn)
	end

	-- what is inside: one tile per perk + one for the Yen
	local tiles = {}
	for _, id in ipairs(it.contents.perks or {}) do
		local sub = PerkCatalog.byId[id]
		if sub then
			table.insert(tiles, { art = sub, glyph = sub.glyph, color = sub.color or GOLD, name = string.upper(sub.name), note = "WORTH R$ " .. sub.price .. "  -  FOREVER" })
		end
	end
	local packYen = math.floor(tonumber(it.contents.yen) or 0)
	if packYen > 0 then
		local n = math.floor(packYen / KIT_YEN)
		local yenArt -- (2026-11-10) CardArt: the Yen pack closest to this amount stands in for the pack's Yen
		for _, y in ipairs(PerkCatalog.ITEMS) do
			if y.kind == "consumable" and tonumber(y.yen) and (not yenArt or math.abs(y.yen - packYen) < math.abs(yenArt.yen - packYen)) then
				yenArt = y
			end
		end
		table.insert(tiles, { art = yenArt, glyph = Catalog.CURRENCY, color = GOLD, name = fmtYen(packYen),
			note = n >= 1 and ("UNLOCKS " .. n .. " FIGHTER" .. (n > 1 and "S" or "")) or "SPEND IN THE SHOP" })
	end
	local row = new("Frame", { Position = UDim2.fromOffset(20, 94), Size = UDim2.new(1, -40, 0, 124), BackgroundTransparency = 1, ZIndex = 52 }, op)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local tileW = math.floor((W - 40 - 14 * (#tiles - 1)) / math.max(#tiles, 1))
	for i, t in ipairs(tiles) do
		local tc1 = t.color:Lerp(INK, 0.45)
		local card = new("Frame", { Name = "Tile" .. i, LayoutOrder = i, Size = UDim2.fromOffset(tileW, 124), BackgroundColor3 = WHITE, BorderSizePixel = 0,
			ZIndex = 52 }, row)
		corner(card, 12)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 36, 64), Color3.fromRGB(20, 18, 32)) }, card)
		stroke(card, INK, 2)
		local band = new("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 53 }, card)
		new("UIGradient", { Color = ColorSequence.new(t.color, tc1) }, band)
		local orb = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(50, 50),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 53 }, card)
		corner(orb)
		new("UIGradient", { Color = ColorSequence.new(t.color, tc1), Rotation = 90 }, orb)
		stroke(orb, INK, 2)
		inkText(label(orb, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = t.glyph or "?",
			FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 54 }), 1.5)
		if t.art then
			artOrb(orb, t.art, 1.2, { live = true }) -- (2026-11-10) CardArt over the glyph orb
		end
		inkText(label(card, { Position = UDim2.fromOffset(6, 70), Size = UDim2.new(1, -12, 0, 20), Text = t.name, ZIndex = 53 }), 1.5)
		label(card, { Position = UDim2.fromOffset(6, 96), Size = UDim2.new(1, -12, 0, 13), Text = t.note, FontFace = Kits.FONT_LABEL,
			TextColor3 = Color3.fromRGB(205, 205, 228), ZIndex = 53 })
	end

	-- VALUE  R$ 242 (struck)   NOW  R$ 49
	local vrow = new("Frame", { Position = UDim2.fromOffset(20, 228), Size = UDim2.new(1, -40, 0, 30), BackgroundTransparency = 1, ZIndex = 52 }, op)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, vrow)
	local valueCap = label(vrow, { LayoutOrder = 1, Size = UDim2.fromOffset(52, 13), Text = "VALUE", FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, ZIndex = 53 })
	local wasText = label(vrow, { LayoutOrder = 2, Size = UDim2.fromOffset(84, 20), TextColor3 = SOFT, ZIndex = 53 })
	local strike = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 3), Rotation = -6,
		BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 54 }, wasText)
	wasText:GetPropertyChangedSignal("TextBounds"):Connect(function()
		strike.Size = UDim2.fromOffset(wasText.TextBounds.X + 8, 3)
	end)
	local nowCap = label(vrow, { LayoutOrder = 3, Size = UDim2.fromOffset(40, 13), Text = "NOW", FontFace = Kits.FONT_LABEL, TextColor3 = C0, ZIndex = 53 })
	local nowText = inkText(label(vrow, { LayoutOrder = 4, Size = UDim2.fromOffset(96, 30), TextColor3 = GOLD, ZIndex = 53 }), 2)

	local buy = new("TextButton", { Name = "Buy", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 266), Size = UDim2.fromOffset(260, 52),
		Text = "", AutoButtonColor = false, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 53 }, op)
	corner(buy, 12)
	stroke(buy, INK, 2.5)
	local bsc = new("UIScale", {}, buy)
	local buyText = inkText(label(buy, { Size = UDim2.new(1, -24, 1, -16), Position = UDim2.fromOffset(12, 8), Text = "BUY", ZIndex = 54 }), 2)
	buy.MouseEnter:Connect(function()
		tween(bsc, 0.1, { Scale = 1.05 })
	end)
	buy.MouseLeave:Connect(function()
		tween(bsc, 0.1, { Scale = 1 })
	end)
	local later = new("TextButton", { Name = "Later", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 326), Size = UDim2.fromOffset(150, 22),
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 53 }, op)
	label(later, { Size = UDim2.fromScale(1, 1), Text = "MAYBE LATER", FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, ZIndex = 54 })

	-- a status line just under the panel (COMING SOON, errors, the unlock)
	local sayLbl = inkText(label(op, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(420, 22),
		TextTransparency = 1, ZIndex = 55 }), 2)
	local sayStroke = sayLbl:FindFirstChildOfClass("UIStroke")
	sayStroke.Transparency = 1
	local sayTok
	local function say(text, color)
		local tok = {}
		sayTok = tok
		sayLbl.Text = text
		sayLbl.TextColor3 = color or WHITE
		sayLbl.TextTransparency = 0
		sayStroke.Transparency = 0
		task.delay(2, function()
			if sayTok == tok then
				tween(sayLbl, 0.35, { TextTransparency = 1 })
				tween(sayStroke, 0.35, { Transparency = 1 })
			end
		end)
	end

	local celebrating = false
	local autoDone = false
	-- Roblox's player list (top right) covers the popup's close button: hidden while the popup is open, then put back
	-- the way it was
	local StarterGui = game:GetService("StarterGui")
	local listWasOn
	local function hidePlayerList(hide)
		if hide and listWasOn == nil then
			local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList)
			listWasOn = ok and on or false
			if listWasOn then
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
			end
		elseif not hide and listWasOn ~= nil then
			if listWasOn then
				pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, true)
			end
			listWasOn = nil
		end
	end
	local setOffer
	local function refresh()
		local p = priceNow()
		local pct = worth > 0 and math.floor((1 - p / worth) * 100 + 0.5) or 0
		local deal = pct >= 10
		burstText.Text = deal and ("-" .. pct .. "%") or "NEW"
		burstSub.Visible = deal
		valueCap.Visible, wasText.Visible = deal, deal
		wasText.Text = "R$ " .. worth
		nowCap.Visible = deal
		nowText.Text = "R$ " .. p
		spSub.Text = deal and (pct .. "% OFF  ・  ONE-TIME") or "ONE-TIME OFFER"
		if not celebrating then
			local pid = PK.product(it)
			buyText.Text = pid and ("BUY FOR R$ " .. p) or "COMING SOON"
			buy.BackgroundColor3 = pid and GOLD or GREY
		end
		local ok = eligible()
		spPill.Visible = ok
		if not ok and oshade.Visible and not celebrating then
			setOffer(false)
		end
	end
	setOffer = function(on)
		if on then
			autoDone = true -- seen this session (opened by itself or from the pill)
			if PK.closePanels then
				PK.closePanels()
			end
			setDrop(false)
			oshade.Visible = true
			refresh()
			if not oshade.Visible then
				return
			end
			hidePlayerList(true)
			oshade.BackgroundTransparency = 1
			tween(oshade, 0.2, { BackgroundTransparency = 0.4 })
			op.Position = UDim2.fromScale(0.5, 0.6)
			tween(op, 0.3, { Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
		else
			oshade.Visible = false
			hidePlayerList(false)
		end
	end
	PK.refreshOffer = refresh
	PK.actions.StarterOffer = function(on)
		setOffer(on ~= false)
	end

	spPill.Activated:Connect(function()
		setOffer(not oshade.Visible)
	end)
	xBtn.Activated:Connect(function()
		setOffer(false)
	end)
	later.Activated:Connect(function()
		setOffer(false)
	end)
	oshade.Activated:Connect(function()
		setOffer(false)
	end)
	buy.Activated:Connect(function()
		bsc.Scale = 0.9
		tween(bsc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		if not celebrating then
			PK.buy(it, say)
		end
	end)

	-- the pack arriving while the popup is open: a short celebration, then it closes (the pill is gone for good)
	local hadPack = PK.has(it.id)
	local queued = false
	player.AttributeChanged:Connect(function(name)
		if queued or not (name == "Perks" or name == "StarterPicked" or name == "ShopOffline" or string.sub(name, 1, 5) == "Perk_") then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			local has = PK.has(it.id)
			if has and not hadPack and oshade.Visible then
				celebrating = true
				buyText.Text = "UNLOCKED!"
				buy.BackgroundColor3 = GREEN
				bsc.Scale = 1.15
				tween(bsc, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
				say("TRAILS + KO EFFECTS ARE IN YOUR INVENTORY", GREEN)
				task.delay(2.6, function()
					celebrating = false
					setOffer(false)
					refresh()
				end)
			end
			hadPack = has
			refresh()
		end)
	end)

	-- opening by itself, once per session
	local t0 = os.clock()
	local function tryAuto()
		if autoDone or oshade.Visible or not eligible() then
			return
		end
		local inv = gui:FindFirstChild("InventoryShade")
		if shade.Visible or (inv and inv.Visible) or dropOpen then
			return -- busy: the next KO / the 5 s check tries again
		end
		setOffer(true)
	end
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 60)
		local kills = ls and ls:WaitForChild("Kills", 60)
		if kills and not kills:IsA("IntValue") then -- (2026-11-11) HIDE MY KILLS: the real counter is in HiddenStats
			local hs = player:WaitForChild("HiddenStats", 10)
			kills = hs and hs:FindFirstChild("Kills")
		end
		if not kills then
			return
		end
		local base = kills.Value
		kills.Changed:Connect(function(v)
			if not autoDone and v - base >= AUTO_KOS then
				task.delay(1.5, tryAuto)
			end
		end)
	end)
	task.spawn(function()
		while not autoDone and gui.Parent do
			task.wait(5)
			if os.clock() - t0 >= AUTO_SECONDS then
				tryAuto()
			end
		end
	end)
	-- the gift wiggle on the pill, a nudge on the buy button while the popup is open
	task.spawn(function()
		while gui.Parent do
			task.wait(4)
			if spPill.Visible then
				for i, r in ipairs({ -14, 12, -8, 5, 0 }) do
					task.delay(i * 0.07, function()
						badge.Rotation = r
					end)
				end
			end
			if oshade.Visible and not celebrating then
				bsc.Scale = 1.07
				tween(bsc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
	end)
	task.delay(8, refresh) -- the real Robux price (GetProductInfo) has landed by then
	refresh()
end
-- (2026-11-14, owner: "remove ... the starter pack thing") not built: no STARTER PACK pill, no popup, no auto-open after
-- 3 KOs / 5 minutes. The bundle stays in PerkCatalog (offer = true keeps it out of the shop) and the server still
-- honours a purchase, so nobody who already bought it loses anything. Put the call back to bring it back.
-- buildStarterOffer()

-- clicking anywhere else closes the dropdown
UserInputService.InputBegan:Connect(function(input)
	if not dropOpen then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		task.defer(function()
			-- mouse location is screen space; AbsolutePosition is below the inset
			local p = UserInputService:GetMouseLocation() - (GuiService:GetGuiInset())
			local function inside(g)
				local a, s = g.AbsolutePosition, g.AbsoluteSize
				return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
			end
			if dropOpen and not inside(drop) and not inside(charPill) then
				setDrop(false)
			end
		end)
	end
end)

-- a switch the server refused (it refuses mid-move / mid-form) shakes the pill instead of silently doing nothing
RunService.Heartbeat:Connect(function()
	if pending and os.clock() - pendingAt > 1 then
		pending = nil
		-- (2026-11-11) a refusal inside the swap cooldown (clock drift past SWAP_SLACK) says so instead
		showToast(swapLeft() > 0 and ("YOU CAN SWAP FIGHTERS AGAIN IN " .. swapSecs() .. "s") or "FINISH YOUR MOVE FIRST", RED)
		for i = 1, 4 do
			task.delay(i * 0.04, function()
				charPill.Rotation = (i % 2 == 0) and -3 or 3
			end)
		end
		task.delay(0.2, function()
			charPill.Rotation = 0
		end)
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local s = math.clamp(vp.Y / 900, 0.75, 1.1)
	-- (2026-11-14, phones) the strip must also fit the WIDTH: on a landscape phone the pills ran 130 px past the right
	-- edge and DUEL / QUESTS / TAUNTS / SETTINGS could not be tapped at all. Natural width = each visible pill's drawn
	-- width / the current scale, + the 8 px gaps; shrink to the room right of the strip (floor 0.5).
	do
		local w, n, cur = 0, 0, math.max(stripScale.Scale, 0.01)
		for _, c in ipairs(strip:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then
				w += c.AbsoluteSize.X / cur
				n += 1
			end
		end
		local room = vp.X - strip.AbsolutePosition.X - 10
		if n > 0 and room > 0 then
			w += (n - 1) * 8
			if w * s > room then
				s = math.max(0.5, room / w)
			end
		end
	end
	stripScale.Scale = s
	if not dropOpen then
		dropScale.Scale = s
	end
	-- (2026-11-11) SETTINGS > CONTROLS > MENU SIZE multiplies the shop / inventory / offer panels
	local menuMul = tonumber(player:GetAttribute("Opt_menuScale")) or 1
	panelScale.Scale = math.clamp(math.min(vp.X / 820, vp.Y / 596), 0.55, 1.15) * menuMul -- (2026-11-11) the shop is 506 tall now
	if PK.invScale then
		PK.invScale.Scale = panelScale.Scale
	end
	if PK.offerScale then -- the starter pack popup (460 x 360, + its status line)
		PK.offerScale.Scale = math.clamp(math.min(vp.X / 520, vp.Y / 470), 0.55, 1.15) * menuMul
	end
end)

refreshCards()

if RunService:IsStudio() then
	local dbg = ReplicatedStorage:FindFirstChild("GojoShared") and ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Kit" and type(arg) == "string" then
				selectKit(arg)
			elseif cmd == "Inventory" and PK.setInv then -- Fire("Inventory", true|false)
				PK.setInv(arg ~= false)
			elseif cmd == "ShopTab" and type(arg) == "string" then -- Fire("ShopTab", a main tab or a view: "perks"|"style"|"aura"|"random"|"gadgets"|...)
				currentTab = arg == "robux" and "perks" or (MAIN_OF[arg] == arg and subTab[arg]) or arg
				grid.CanvasPosition = Vector2.zero
				setShop(true)
			elseif cmd == "InvClick" and type(arg) == "string" and PK.actions[arg] then -- Fire("InvClick", "Speed" | "Trail:Gold" | ...)
				PK.actions[arg]()
			elseif cmd == "StarterOffer" and PK.actions.StarterOffer then -- Fire("StarterOffer", true|false)
				PK.actions.StarterOffer(arg ~= false)
			elseif cmd == "Rolls" and PK.openRolls then -- Fire("Rolls", "emote"|"ko"|"skin") opens the RANDOM tab
				PK.openRolls(type(arg) == "string" and arg or "emote")
			elseif cmd == "RollPolicy" and PK.setRollPolicy then -- Fire("RollPolicy", true|false) pretends a region
				PK.setRollPolicy(arg == true)
			end
		end)
	end
end
