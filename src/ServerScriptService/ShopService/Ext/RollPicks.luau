--!nocheck
-- ShopService.Ext.RollPicks (2026-11-09, shop expansion): a 10-roll gives 9 random items + ONE PICK - the player chooses
-- the 10th from everything they don't own yet (now, or later: "PICK LATER" keeps it; it is saved).
--   data { emote = n, ko = n, skin = n } (no merge: a pick is spent, so the last write wins)
--   attribute RollPicks (JSON) = the same counts - written only here
--   M.add(d, cat, n) -> undo   (ShopService's roll paths call it for a 10-roll)
-- Request ("rollPick", { cat, id }): spends a pick on that item. With nothing left to pick (all owned meanwhile) the
-- pick is returned as ROLL_YEN Yen instead.
local M = { name = "RollPicks", request = {} }
local CATS = { "emote", "ko", "skin" }
local api

function M.load(raw)
	local dat = {}
	for _, c in ipairs(CATS) do
		dat[c] = math.clamp(math.floor(tonumber(type(raw) == "table" and raw[c] or 0) or 0), 0, 99)
	end
	return dat
end

function M.publish(p, d, dat)
	p:SetAttribute("RollPicks", api.HttpService:JSONEncode(dat))
end

function M.add(d, cat, n)
	local dat = api.ext(d, M.name)
	dat[cat] = (dat[cat] or 0) + n
	d.dirty = true
	return function()
		dat[cat] = math.max(0, (dat[cat] or 0) - n)
	end
end

M.request.rollPick = function(p, d, arg)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	local cat, id = type(arg) == "table" and arg.cat, type(arg) == "table" and arg.id
	if type(cat) ~= "string" or not api.POOL[cat] then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	if (dat[cat] or 0) < 1 then
		return false, "NO PICK WAITING"
	end
	if #api.notOwned(d, cat) == 0 then
		dat[cat] -= 1
		d.yen += api.ROLL_YEN
		d.dirty = true
		api.publish(p)
		task.spawn(api.save, p)
		return true, "YOU OWN THEM ALL - REFUNDED " .. api.ROLL_YEN .. " " .. api.Catalog.CURRENCY
	end
	if type(id) ~= "string" or not api.POOLSET[cat][id] or (api.Perks.isExclusive and api.Perks.isExclusive(cat, id)) then -- (2026-11-11) exclusives can't be picked
		return false, "?"
	end
	if api.ownsItem(d, cat, id) then
		return false, "YOU ALREADY OWN IT"
	end
	dat[cat] -= 1
	d.items[cat][id] = true
	if cat == "skin" then
		d.equip.skins[id] = true -- a new skin goes on, like a rolled one
	end
	d.dirty = true
	api.publish(p)
	api.announceRoll(p, d, cat, { id })
	task.spawn(api.save, p)
	return true, "YOU PICKED IT!"
end

function M.init(a)
	api = a
end

return M
