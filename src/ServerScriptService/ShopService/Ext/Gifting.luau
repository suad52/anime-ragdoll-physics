--!nocheck
-- ShopService.Ext.Gifting (2026-11-09, shop expansion): buy a Robux item FOR another player in the server.
-- Flow: the GIFTS tab asks ("giftSetup", { to = userId, item = itemId }) -> this checks the gift and remembers it for
-- GIFT_WINDOW s -> the client prompts the item's normal developer product -> ShopService's receipt asks giftFor(buyer,
-- item) and grants the item to the RECIPIENT (the receipt stays the buyer's). A cancelled prompt drops the pending
-- gift (PromptProductPurchaseFinished). Not allowed: yourself, someone whose profile isn't loaded, a perk they already
-- own, rolls in a category they own entirely (or when the buyer's region restricts paid random items).
-- Both players get attribute GiftNote (JSON { from | to, item, n }) for the shop's toast.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local M = { name = "Gifting", request = {} }
local GIFT_WINDOW = 300
local api
local pending = {} -- [buyer] = { player, itemId, t }
local notes = 0

local function why(p, target, it)
	if not api.Perks.giftable(it) then
		return "THAT CAN'T BE GIFTED"
	end
	if not target or not target.Parent or target == p then
		return "PICK ANOTHER PLAYER"
	end
	local td = api.data[target]
	if not td or td.offline then
		return "THEIR SAVE ISN'T LOADED"
	end
	if it.kind == "perk" and api.hasPerk(td, it.id) then
		return "THEY ALREADY OWN IT"
	end
	if it.kind == "roll" then
		local left = #api.notOwned(td, it.cat)
		if left == 0 then
			return "THEY OWN THEM ALL"
		end
		if left < (tonumber(it.count) or 1) then
			return "THEY ONLY HAVE " .. left .. " LEFT TO WIN"
		end
		if api.rollsRestricted(p) then
			return "NOT AVAILABLE IN YOUR REGION"
		end
	end
	return nil
end

M.request.giftSetup = function(p, d, arg)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	if type(arg) ~= "table" then
		return false, "?"
	end
	local target = Players:GetPlayerByUserId(tonumber(arg.to) or 0)
	local it = type(arg.item) == "string" and api.Perks.byId[arg.item]
	if not it then
		return false, "?"
	end
	local reason = why(p, target, it)
	if reason then
		return false, reason
	end
	if type(it.product) ~= "number" or it.product <= 0 then
		return false, "COMING SOON"
	end
	pending[p] = { player = target, itemId = it.id, t = os.clock() }
	return true, "GIFT FOR " .. string.upper(target.DisplayName)
end

M.request.giftCancel = function(p)
	pending[p] = nil
	return true
end

-- ShopService's receipt: the pending gift for this buyer + this item (spent here), or nil (a normal purchase)
function M.giftFor(buyer, item)
	local g = pending[buyer]
	if not g or g.itemId ~= item.id or os.clock() - g.t > GIFT_WINDOW then
		return nil
	end
	pending[buyer] = nil
	if why(buyer, g.player, item) then
		return nil -- no longer giftable (they left, or got it meanwhile): the buyer gets it themselves
	end
	return { player = g.player }
end

function M.giftDone(buyer, target, item)
	notes += 1
	local H = api.HttpService
	if target.Parent then
		target:SetAttribute("GiftNote", H:JSONEncode({ from = buyer.DisplayName, item = item.name, n = notes }))
	end
	if buyer.Parent then
		buyer:SetAttribute("GiftNote", H:JSONEncode({ to = target.DisplayName, item = item.name, n = notes }))
	end
end

function M.init(a)
	api = a
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if purchased then
			return
		end
		local p = Players:GetPlayerByUserId(userId)
		local g = p and pending[p]
		local it = g and api.Perks.byId[g.itemId]
		if it and it.product == productId then
			pending[p] = nil -- the prompt was closed without buying
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		pending[p] = nil
		for buyer, g in pairs(pending) do
			if g.player == p then
				pending[buyer] = nil
			end
		end
	end)
	-- Studio: ShopService.GiftTest:Invoke(buyer, recipient, itemId) -> the gift path end to end (fake receipt)
	if api.isStudio then
		local f = Instance.new("BindableFunction")
		f.Name = "GiftTest"
		f.OnInvoke = function(buyer, target, itemId)
			local it = api.Perks.byId[itemId]
			local reason = it and why(buyer, target, it)
			if not it or reason then
				return reason or "UNKNOWN ITEM"
			end
			pending[buyer] = { player = target, itemId = it.id, t = os.clock() }
			local pg = game.ServerScriptService.ShopService:FindFirstChild("PerkGrantTest")
			return pg and pg:Invoke(buyer, itemId) or "no PerkGrantTest"
		end
		f.Parent = game.ServerScriptService.ShopService
	end
end

return M
