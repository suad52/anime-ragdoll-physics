--!nocheck
-- ShopService.Ext.Victory (2026-11-11, "wiki extras"): VICTORY FLASHES (HudShared.VictoryCatalog) and the duel reward.
--   data { owned = { [id] = true }, equip = id }
--   attributes VictoryOwned (JSON list, the free one included) and VictoryFlash (equipped id) - DuelService reads it
--   request "victoryBuy" id  - for VictoryCatalog.YEN       request "victoryEquip" id
--   receipt kind "victory" (PerkCatalog VF_* items, item.flash) - owned + equipped
--   ShopService.DuelResult (BindableEvent, created here) :Fire(winner, loser) from DuelService -> the winner earns
--   DUEL_YEN (fixed, no multipliers) and the result is announced to both (attribute DuelReward on the winner)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local V = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("VictoryCatalog"))

local M = { name = "Victory", request = {}, grant = {} }
local api
local DUEL_YEN = 50

function M.load(raw)
	raw = type(raw) == "table" and raw or {}
	local owned = {}
	if type(raw.owned) == "table" then
		for id, v in pairs(raw.owned) do
			if v == true and V.byId[id] then
				owned[id] = true
			end
		end
	end
	local equip = type(raw.equip) == "string" and V.byId[raw.equip] and raw.equip or V.DEFAULT
	return { owned = owned, equip = equip }
end

function M.merge(mine, theirs) -- another server's save: owning is grow-only
	if type(theirs) == "table" and type(theirs.owned) == "table" then
		for id, v in pairs(theirs.owned) do
			if v == true and V.byId[id] then
				mine.owned[id] = true
			end
		end
	end
end

local function owns(dat, id)
	local f = V.byId[id]
	return f and (f.free or dat.owned[id] == true) or false
end

function M.publish(p, d, dat)
	local list = {}
	for _, f in ipairs(V.LIST) do
		if owns(dat, f.id) then
			table.insert(list, f.id)
		end
	end
	if not owns(dat, dat.equip) then
		dat.equip = V.DEFAULT
	end
	p:SetAttribute("VictoryOwned", api.HttpService:JSONEncode(list))
	p:SetAttribute("VictoryFlash", dat.equip)
end

M.request.victoryBuy = function(p, d, id)
	local f = type(id) == "string" and V.byId[id]
	if not f then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	if owns(dat, id) then
		return false, "ALREADY OWNED"
	end
	if (d.yen or 0) < V.YEN then
		return false, "NOT ENOUGH " .. api.Catalog.CURRENCY
	end
	d.yen -= V.YEN
	dat.owned[id] = true
	dat.equip = id
	d.dirty = true
	api.publish(p)
	task.spawn(api.save, p)
	return true, string.upper(f.name) .. " UNLOCKED"
end

M.request.victoryEquip = function(p, d, id)
	local dat = api.ext(d, M.name)
	if type(id) ~= "string" or not owns(dat, id) then
		return false, "NOT OWNED"
	end
	dat.equip = id
	d.dirty = true
	api.publish(p)
	return true, "EQUIPPED"
end

M.grant.victory = function(p, d, item)
	local id = item.flash
	if not V.byId[id] then
		return nil
	end
	local dat = api.ext(d, M.name)
	local had, wasEquip = dat.owned[id], dat.equip
	dat.owned[id] = true
	dat.equip = id
	d.dirty = true
	api.publish(p)
	return function()
		dat.owned[id] = had
		dat.equip = wasEquip
		d.dirty = true
	end
end

function M.init(a)
	api = a
	local shop = script.Parent.Parent
	local ev = shop:FindFirstChild("DuelResult")
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = "DuelResult"
		ev.Parent = shop
	end
	ev.Event:Connect(function(winner)
		local d = typeof(winner) == "Instance" and api.data[winner]
		if d then
			d.yen += DUEL_YEN
			d.dirty = true
			api.publish(winner)
			winner:SetAttribute("DuelReward", DUEL_YEN)
		end
	end)
end

return M
