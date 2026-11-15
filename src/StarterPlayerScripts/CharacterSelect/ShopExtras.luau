--!nocheck
-- CharacterSelect.ShopExtras (2026-11-09, shop expansion): the shop tabs added after AURAS / TITLES / ROBUX / RANDOM.
-- CharacterSelect calls this with its helpers (ctx) and adds the returned tabs; each page sits where the card grid does
-- and is shown by refreshCards (pages[id].frame.Visible + pages[id].refresh()).
--   GADGETS  one-use tools for Yen (ShopRequest "buyGadget") - ShopService.Ext.Gadgets, StarterPlayerScripts.GadgetBar
--   GIFTS    pick a player in the server, pick a Robux item -> ShopRequest "giftSetup", then the item's normal prompt
--            (ShopService.Ext.Gifting grants it to them)
--   CODES    a text box -> ShopRequest "redeem" (ShopService.Ext.Codes; the list is ServerStorage.ShopCodes)
return function(ctx)
	local Players = game:GetService("Players")
	local player, PK, P, HttpService = ctx.player, ctx.PK, ctx.PerkCatalog, ctx.HttpService
	local new, corner, stroke, label, inkText, tween = ctx.new, ctx.corner, ctx.stroke, ctx.label, ctx.inkText, ctx.tween
	local WHITE, INK, GOLD, RED, PANEL2 = ctx.WHITE, ctx.INK, ctx.GOLD, ctx.RED, ctx.PANEL2
	local GREEN, GREY, SOFT = Color3.fromRGB(70, 220, 130), Color3.fromRGB(90, 88, 110), Color3.fromRGB(200, 200, 222)
	local Kits = ctx.Kits
	local out = { tabs = {}, pages = {} }

	local function page(name)
		return new("Frame", { Name = name, Position = UDim2.fromOffset(20, 132), Size = UDim2.new(1, -40, 1, -150), BackgroundTransparency = 1,
			Visible = false, ZIndex = 32 }, ctx.panel)
	end
	local function heading(parent, text, pos, size)
		return inkText(label(parent, { Position = pos, Size = size, Text = text, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 34 }), 1.5)
	end
	local function button(parent, text, color, pos, size, anchor)
		local b = new("TextButton", { AnchorPoint = anchor or Vector2.zero, Position = pos, Size = size, Text = "", AutoButtonColor = true,
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 35 }, parent)
		corner(b, 8)
		stroke(b, INK, 2)
		local t = inkText(label(b, { Size = UDim2.new(1, -10, 1, -8), Position = UDim2.fromOffset(5, 4), Text = text, ZIndex = 36 }), 1.2)
		return b, t
	end
	local function request(...)
		if not ctx.ShopRequest then
			return false, "SHOP OFFLINE"
		end
		local ok, a, b = pcall(ctx.ShopRequest.InvokeServer, ctx.ShopRequest, ...)
		if not ok then
			return false, "TRY AGAIN"
		end
		return a, b
	end

	---------------------------------------------------------------------------------------------------------------
	-- GADGETS: one card per gadget (Yen, one at a time) + the Robux Gadget Crate
	local GadgetCatalog
	pcall(function()
		GadgetCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("GadgetCatalog", 10))
	end)
	if GadgetCatalog then
		local frame = page("GadgetsPage")
		local grid = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 33 }, frame)
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 136), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		new("UIPadding", { PaddingRight = UDim.new(0, 8) }, grid)
		local cur = ctx.Catalog.CURRENCY or "¥"
		local counters = {}
		local function card(order, name, glyph, color, desc, art)
			local c = new("Frame", { LayoutOrder = order, BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 34 }, grid)
			corner(c, 12)
			stroke(c, INK, 2)
			local orb = new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 35 }, c)
			corner(orb)
			stroke(orb, INK, 1.5)
			inkText(label(orb, { Size = UDim2.fromScale(0.68, 0.68), Position = UDim2.fromScale(0.16, 0.16), Text = glyph, FontFace = Font.fromEnum(Enum.Font.GothamBlack),
				ZIndex = 36 }), 1)
			if art and ctx.artOrb then -- (2026-11-14) the item's drawn icon (HudShared.CardArt), not its kanji
				ctx.artOrb(orb, art, 1.2)
			end
			heading(c, string.upper(name), UDim2.fromOffset(58, 10), UDim2.new(1, -66, 0, 20))
			local have = label(c, { Position = UDim2.fromOffset(58, 32), Size = UDim2.new(1, -66, 0, 14), Text = "", FontFace = Kits.FONT_LABEL, TextColor3 = GREEN,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
			local d = label(c, { Position = UDim2.fromOffset(10, 56), Size = UDim2.new(1, -20, 0, 34), Text = string.upper(desc), TextWrapped = true,
				FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 35 })
			new("UITextSizeConstraint", { MaxTextSize = 13 }, d)
			return c, have
		end
		local function counts()
			local ok, t = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Gadgets") or "{}")
			return (ok and type(t) == "table") and t or {}
		end
		for i, g in ipairs(GadgetCatalog.LIST) do
			local c, have = card(i, g.name, g.glyph, g.color, g.desc, g)
			c.Name = "Gadget_" .. g.id
			local busy = false
			local function buy()
				if busy then
					return
				end
				busy = true
				local ok, msg = request("buyGadget", g.id)
				busy = false
				ctx.panelSay(tostring(msg or (ok and "BOUGHT" or "TRY AGAIN")), ok and GREEN or RED)
				return ok, msg
			end
			local b = button(c, cur .. " " .. g.yen, GOLD, UDim2.new(1, -10, 1, -10), UDim2.fromOffset(96, 30), Vector2.new(1, 1))
			b.Name = "Buy"
			b.Activated:Connect(buy)
			PK.actions["BuyGadget:" .. g.id] = buy
			label(c, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -14), Size = UDim2.fromOffset(110, 14), Text = "KEY " .. i .. "  /  TAP",
				FontFace = Kits.FONT_LABEL, TextColor3 = Color3.fromRGB(150, 145, 175), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
			counters[g.id] = have
		end
		-- the Robux crate
		local crate = P.byId and P.byId.GadgetCrate
		local cratePrice
		if crate then
			local c = card(#GadgetCatalog.LIST + 1, crate.name, crate.glyph or "?", crate.color or GREEN,
				(tonumber(crate.count) or 6) .. " random gadgets in one box.", crate)
			c.Name = "Gadget_Crate"
			local b, bt = button(c, PK.price(crate), GREEN, UDim2.new(1, -10, 1, -10), UDim2.fromOffset(96, 30), Vector2.new(1, 1))
			b.Name = "Buy"
			cratePrice = bt
			local function buyCrate()
				if not PK.product(crate) then
					ctx.panelSay(string.upper(crate.name) .. " - COMING SOON", GOLD)
					return
				end
				PK.buy(crate, ctx.panelSay)
			end
			b.Activated:Connect(buyCrate)
			PK.actions["BuyGadget:Crate"] = buyCrate
		end
		local function refresh()
			local t = counts()
			for id, lbl in pairs(counters) do
				local n = tonumber(t[id]) or 0
				lbl.Text = n > 0 and ("YOU HAVE " .. n) or "NONE YET"
				lbl.TextColor3 = n > 0 and GREEN or SOFT
			end
			if cratePrice and crate then
				cratePrice.Text = PK.product(crate) and PK.price(crate) or "SOON"
			end
		end
		player:GetAttributeChangedSignal("Gadgets"):Connect(function()
			if frame.Visible then
				refresh()
			end
		end)
		table.insert(out.tabs, { id = "gadgets", label = "GADGETS", jp = "道具", color = Color3.fromRGB(60, 190, 110) })
		out.pages.gadgets = { frame = frame, refresh = refresh, tip = "one-use tools - use them with your gadget keys (1-5 by default) or tap them on the right of the screen" }
	end

	---------------------------------------------------------------------------------------------------------------
	-- VICTORY (2026-11-11, wiki extras): Victory Flashes - preview, buy for Yen ("victoryBuy") or Robux (PerkCatalog
	-- kind "victory"), equip ("victoryEquip"). Owned / equipped: player attributes VictoryOwned / VictoryFlash.
	local VC, VFX
	pcall(function()
		local hs = game:GetService("ReplicatedStorage"):WaitForChild("HudShared")
		VC = require(hs:WaitForChild("VictoryCatalog", 10))
		VFX = require(hs:WaitForChild("VictoryFlash", 10))
	end)
	-- (2026-11-14, sandbox shop) hidden while PerkCatalog.HIDE_TABS.victory is set: victory flashes play after a duel
	if VC and VFX and not (P.HIDE_TABS and P.HIDE_TABS.victory) then
		local frame = page("VictoryPage")
		local grid = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 33 }, frame)
		new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		new("UIPadding", { PaddingRight = UDim.new(0, 8) }, grid)
		local cur = ctx.Catalog.CURRENCY or "¥"
		local itemOf = {}
		for _, it in ipairs(P.ITEMS) do
			if it.kind == "victory" and it.flash then
				itemOf[it.flash] = it
			end
		end
		local cards = {}
		local function ownedSet()
			local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("VictoryOwned") or "[]")
			local set = {}
			for _, id in ipairs(ok and type(list) == "table" and list or {}) do
				set[id] = true
			end
			return set
		end
		for i, f in ipairs(VC.LIST) do
			local c = new("Frame", { Name = "Flash_" .. f.id, LayoutOrder = i, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 34 }, grid)
			corner(c, 12)
			local st = stroke(c, INK, 2)
			new("UIGradient", { Rotation = -60, Color = ColorSequence.new(f.c1, f.c0) }, c)
			inkText(label(c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(60, 60), Text = f.glyph,
				FontFace = Font.fromEnum(Enum.Font.GothamBlack), TextTransparency = 0.25, ZIndex = 35 }), 2)
			heading(c, string.upper(f.name), UDim2.fromOffset(10, 10), UDim2.new(1, -76, 0, 22))
			local state = inkText(label(c, { Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -76, 0, 14), Text = "", FontFace = Kits.FONT_LABEL,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 }), 1)
			local prev = button(c, "PREVIEW", WHITE, UDim2.fromOffset(10, 66), UDim2.new(1, -20, 0, 30))
			prev.Name = "Preview"
			prev.Activated:Connect(function()
				VFX.play(player, f.id, { sub = "PREVIEW" })
			end)
			local yenB, yenT = button(c, cur .. " " .. VC.YEN, GOLD, UDim2.new(0, 10, 1, -10), UDim2.new(0.5, -15, 0, 34), Vector2.new(0, 1))
			yenB.Name = "BuyYen"
			local rbxB, rbxT = button(c, "R$", GREEN, UDim2.new(1, -10, 1, -10), UDim2.new(0.5, -15, 0, 34), Vector2.new(1, 1))
			rbxB.Name = "BuyRobux"
			local busy = false
			local function act(which)
				if busy then
					return
				end
				local owned = ownedSet()[f.id] or f.free
				if owned then
					busy = true
					local ok, msg = request("victoryEquip", f.id)
					busy = false
					ctx.panelSay(tostring(msg or (ok and "EQUIPPED" or "TRY AGAIN")), ok and GREEN or RED)
				elseif which == "yen" then
					busy = true
					local ok, msg = request("victoryBuy", f.id)
					busy = false
					ctx.panelSay(tostring(msg or (ok and "UNLOCKED" or "TRY AGAIN")), ok and GREEN or RED)
				else
					local it = itemOf[f.id]
					if not it or not PK.product(it) then
						ctx.panelSay(string.upper(f.name) .. " - ROBUX COMING SOON", GOLD)
						return
					end
					PK.buy(it, ctx.panelSay)
				end
			end
			yenB.Activated:Connect(function()
				act("yen")
			end)
			rbxB.Activated:Connect(function()
				act("robux")
			end)
			PK.actions["Victory:" .. f.id] = act
			cards[f.id] = { f = f, state = state, stroke = st, yenB = yenB, yenT = yenT, rbxB = rbxB, rbxT = rbxT }
		end
		local function refresh()
			local owned = ownedSet()
			local equip = player:GetAttribute("VictoryFlash") or VC.DEFAULT
			for id, c in pairs(cards) do
				local has = owned[id] or c.f.free
				local on = id == equip
				c.state.Text = on and "EQUIPPED" or (has and "OWNED" or (c.f.free and "FREE" or "PLAYS WHEN YOU WIN A DUEL"))
				c.state.TextColor3 = on and GOLD or WHITE
				c.stroke.Color = on and GOLD or INK
				c.stroke.Thickness = on and 3 or 2
				if has then
					-- one wide EQUIP button
					c.rbxB.Visible = false
					c.yenB.Size = UDim2.new(1, -20, 0, 34)
					c.yenT.Text = on and "EQUIPPED" or "EQUIP"
					c.yenB.BackgroundColor3 = on and GREY or GREEN
				else
					c.rbxB.Visible = true
					c.yenB.Size = UDim2.new(0.5, -15, 0, 34)
					c.yenT.Text = cur .. " " .. VC.YEN
					c.yenB.BackgroundColor3 = GOLD
					local it = itemOf[id]
					c.rbxT.Text = (it and PK.product(it)) and PK.price(it) or "SOON"
					c.rbxB.BackgroundColor3 = (it and PK.product(it)) and GREEN or GREY
				end
			end
		end
		for _, a in ipairs({ "VictoryOwned", "VictoryFlash" }) do
			player:GetAttributeChangedSignal(a):Connect(function()
				if frame.Visible then
					refresh()
				end
			end)
		end
		table.insert(out.tabs, { id = "victory", label = "VICTORY", jp = "勝利", color = Color3.fromRGB(255, 120, 60) })
		out.pages.victory = { frame = frame, refresh = refresh, tip = "plays for both fighters when you win a duel - preview them here" }
	end

	---------------------------------------------------------------------------------------------------------------
	-- GIFTS
	do
		local frame = page("GiftsPage")
		heading(frame, "1  PICK A PLAYER", UDim2.fromOffset(0, 0), UDim2.fromOffset(200, 22))
		local people = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(0, 200, 1, -30), BackgroundColor3 = PANEL2,
			BackgroundTransparency = 0.2, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 33 }, frame)
		corner(people, 10)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, people)
		new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, people)
		local giftHead = heading(frame, "2  PICK A GIFT", UDim2.fromOffset(214, 0), UDim2.new(1, -214, 0, 22))
		local gifts = new("ScrollingFrame", { Position = UDim2.fromOffset(214, 28), Size = UDim2.new(1, -214, 1, -30), BackgroundTransparency = 1,
			BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = GOLD, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 33 }, frame)
		new("UIGridLayout", { CellSize = UDim2.fromOffset(148, 96), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gifts)
		local empty = label(frame, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 107, 0.5, 0), Size = UDim2.new(1, -240, 0, 40),
			TextWrapped = true, FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, ZIndex = 34,
			Text = "NOBODY ELSE IS IN THIS SERVER YET - GIFTS GO TO A PLAYER WHO IS HERE WITH YOU" })

		local target -- the chosen Player
		local rows, cards = {}, {}
		local refresh

		-- does `who` already have it? (their own attributes replicate to every client)
		local function theyHave(who, it)
			if it.kind == "perk" then
				return who:GetAttribute("Perk_" .. it.id) == true
			end
			if it.kind == "roll" then
				local ok, list = pcall(HttpService.JSONDecode, HttpService,
					who:GetAttribute(({ emote = "OwnedEmotes", ko = "OwnedKO", skin = "OwnedSkins" })[it.cat]) or "[]")
				local left = #P.pool(it.cat) - ((ok and type(list) == "table") and #list or 0)
				return left < (tonumber(it.count) or 1)
			end
			return false
		end

		local order = 0
		local noEarly = next((ctx.Catalog.KITS or {}).EARLY or {}) == nil
		for _, it in ipairs(P.ITEMS) do
			if P.giftable(it) and not (it.id == "EarlyAccess" and noEarly) then
				order += 1
				local c0 = it.color or GOLD
				local card = new("Frame", { Name = "Gift_" .. it.id, LayoutOrder = order, BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 34 }, gifts)
				corner(card, 10)
				local st = stroke(card, INK, 2)
				local orb = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = c0, BorderSizePixel = 0,
					ZIndex = 35 }, card)
				corner(orb)
				stroke(orb, INK, 1.5)
				inkText(label(orb, { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = it.glyph or "?",
					FontFace = Font.fromEnum(Enum.Font.GothamBlack), ZIndex = 36 }), 1)
				if ctx.artOrb then -- (2026-11-14) the item's drawn icon, not its kanji
					ctx.artOrb(orb, it, 1.2)
				end
				label(card, { Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -54, 0, 36), Text = string.upper(it.name), TextWrapped = true,
					FontFace = Kits.FONT_LABEL, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
				local price = label(card, { Position = UDim2.fromOffset(8, 66), Size = UDim2.fromOffset(60, 20), Text = PK.price(it), FontFace = Kits.FONT_LABEL,
					TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
				local b, bt = button(card, "GIFT", GREEN, UDim2.new(1, -8, 0, 62), UDim2.fromOffset(66, 26), Vector2.new(1, 0))
				local function press()
					if not target or not target.Parent then
						ctx.panelSay("PICK A PLAYER FIRST", GOLD)
						return
					end
					if theyHave(target, it) then
						ctx.panelSay(string.upper(target.DisplayName) .. " ALREADY HAS IT", GOLD)
						return
					end
					if not PK.product(it) then
						ctx.panelSay(string.upper(it.name) .. " - COMING SOON", GOLD)
						return
					end
					local ok, msg = request("giftSetup", { to = target.UserId, item = it.id })
					if not ok then
						ctx.panelSay(tostring(msg or "TRY AGAIN"), RED)
						return
					end
					ctx.panelSay(msg, GREEN)
					PK.buy(it, ctx.panelSay)
				end
				b.Activated:Connect(press)
				PK.actions["Gift:" .. it.id] = press
				cards[it.id] = { card = card, item = it, button = b, text = bt, stroke = st, price = price }
			end
		end

		local function rebuildPeople()
			for _, r in pairs(rows) do
				r.button:Destroy()
			end
			table.clear(rows)
			local n = 0
			for _, who in ipairs(Players:GetPlayers()) do
				if who ~= player then
					n += 1
					local b = new("TextButton", { Name = "P_" .. who.UserId, LayoutOrder = n, Size = UDim2.new(1, 0, 0, 40), Text = "", AutoButtonColor = true,
						BackgroundColor3 = Color3.fromRGB(40, 36, 64), BorderSizePixel = 0, ZIndex = 34 }, people)
					corner(b, 8)
					local st = stroke(b, INK, 2)
					inkText(label(b, { Position = UDim2.fromOffset(8, 3), Size = UDim2.new(1, -16, 0, 20), Text = who.DisplayName,
						TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 }), 1)
					label(b, { Position = UDim2.fromOffset(8, 23), Size = UDim2.new(1, -16, 0, 13), Text = "@" .. who.Name, FontFace = Kits.FONT_SMALL,
						TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 35 })
					b.Activated:Connect(function()
						target = who
						refresh()
					end)
					rows[who] = { button = b, stroke = st }
				end
			end
			if target and not rows[target] then
				target = nil
			end
			if not target then
				target = next(rows)
			end
		end

		refresh = function()
			local any = next(rows) ~= nil
			empty.Visible = not any
			gifts.Visible = any
			giftHead.Text = target and ("2  PICK A GIFT FOR " .. string.upper(target.DisplayName)) or "2  PICK A GIFT"
			for who, r in pairs(rows) do
				local on = who == target
				r.stroke.Color = on and GOLD or INK
				r.button.BackgroundColor3 = on and Color3.fromRGB(70, 60, 110) or Color3.fromRGB(40, 36, 64)
			end
			for _, c in pairs(cards) do
				local has = target ~= nil and theyHave(target, c.item)
				local live = PK.product(c.item) ~= nil
				c.text.Text = has and "OWNED" or (live and "GIFT" or "SOON")
				c.button.BackgroundColor3 = (has or not live) and GREY or GREEN
				c.price.Text = PK.price(c.item)
			end
		end
		Players.PlayerAdded:Connect(function()
			rebuildPeople()
			if frame.Visible then
				refresh()
			end
		end)
		Players.PlayerRemoving:Connect(function(who)
			task.defer(function()
				rebuildPeople()
				if frame.Visible then
					refresh()
				end
			end)
		end)
		rebuildPeople()
		table.insert(out.tabs, { id = "gifts", label = "GIFTS", jp = "贈", color = Color3.fromRGB(255, 120, 170) })
		out.pages.gifts = { frame = frame, refresh = refresh, tip = "gifts go to a player in this server" }

		-- a gift arrived / was delivered (ShopService.Ext.Gifting writes GiftNote on both players)
		local seen
		player:GetAttributeChangedSignal("GiftNote"):Connect(function()
			local ok, g = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("GiftNote") or "")
			if not ok or type(g) ~= "table" or g.n == seen then
				return
			end
			seen = g.n
			if g.from then
				ctx.showToast(string.upper(tostring(g.from)) .. " GIFTED YOU " .. string.upper(tostring(g.item)) .. "!", GOLD)
			elseif g.to then
				ctx.showToast("GIFT SENT TO " .. string.upper(tostring(g.to)) .. "!", GREEN)
			end
		end)
	end

	---------------------------------------------------------------------------------------------------------------
	-- CODES
	do
		local frame = page("CodesPage")
		local card = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(420, 190),
			BackgroundColor3 = PANEL2, BorderSizePixel = 0, ZIndex = 33 }, frame)
		corner(card, 14)
		stroke(card, INK, 2)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(44, 38, 72), Color3.fromRGB(20, 18, 32)) }, card)
		inkText(label(card, { Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -40, 0, 30), Text = "REDEEM A CODE", ZIndex = 34 }), 2)
		label(card, { Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 16), FontFace = Kits.FONT_LABEL, TextColor3 = SOFT, ZIndex = 34,
			Text = "new codes come with updates - each one works once per player" })
		local box = new("TextBox", { Position = UDim2.fromOffset(20, 82), Size = UDim2.new(1, -150, 0, 40), BackgroundColor3 = INK, BorderSizePixel = 0,
			Text = "", PlaceholderText = "ENTER CODE", PlaceholderColor3 = Color3.fromRGB(150, 145, 175), TextColor3 = WHITE, ClearTextOnFocus = false,
			FontFace = Kits.FONT_PUNCH, TextSize = 22, ZIndex = 34 }, card)
		corner(box, 8)
		stroke(box, GOLD, 2)
		local go = button(card, "REDEEM", GOLD, UDim2.new(1, -20, 0, 82), UDim2.fromOffset(110, 40), Vector2.new(1, 0))
		local result = label(card, { Position = UDim2.fromOffset(20, 136), Size = UDim2.new(1, -40, 0, 22), Text = "", TextWrapped = true,
			FontFace = Kits.FONT_LABEL, TextColor3 = GREEN, ZIndex = 34 })
		local busy = false
		local function redeem()
			if busy then
				return
			end
			busy = true
			local ok, msg = request("redeem", box.Text)
			busy = false
			result.Text = tostring(msg or (ok and "REDEEMED!" or "TRY AGAIN"))
			result.TextColor3 = ok and GREEN or RED
			if ok then
				box.Text = ""
			end
		end
		go.Activated:Connect(redeem)
		box.FocusLost:Connect(function(enter)
			if enter then
				redeem()
			end
		end)
		PK.actions.RedeemCode = function(text)
			box.Text = tostring(text or "")
			redeem()
			return result.Text
		end
		table.insert(out.tabs, { id = "codes", label = "CODES", jp = "券", color = Color3.fromRGB(255, 190, 60) })
		out.pages.codes = { frame = frame, refresh = function() end, tip = "type a code, press redeem" }
	end

	return out
end
