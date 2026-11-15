--!nocheck
-- ShopService.Ext.EmoteWheel (2026-11-09, shop expansion): the emote wheel's PAGES and SLOTS.
--   * every player has 1 page of 4 slots; the EmoteSlots perk (or the retired Emote Pack) makes every page 8 slots;
--     every EmotePage purchase (kind "emotePage", repeatable) adds a page - and a search box on the wheel
--   * the layout is saved: slots[page][slot] = emote id. Empty slots are filled with owned emotes that are not on the
--     wheel yet (in the order they were rolled), so a new emote always shows up somewhere while there is room
--   * attribute EmoteWheel (JSON) = { perPage, pages, search, slots = { { id | "", ... }, ... } } - written only here
-- Request ("emoteSlot", { page, slot, id }): puts an owned emote in that slot (it swaps places if it was on the
-- wheel already; id "" clears the slot - the next refill puts an unplaced emote there).
local M = { name = "EmoteWheel", grant = {}, request = {} }

local BASE_SLOTS, BIG_SLOTS = 4, 8
local MAX_PAGES = 20
local api

function M.load(raw)
	local dat = { pages = 0, slots = {} }
	if type(raw) ~= "table" then
		return dat
	end
	dat.pages = math.clamp(math.floor(tonumber(raw.pages) or 0), 0, MAX_PAGES)
	if type(raw.slots) == "table" then
		for pg = 1, math.min(#raw.slots, MAX_PAGES + 1) do
			local row = raw.slots[pg]
			local out = {}
			if type(row) == "table" then
				for s = 1, BIG_SLOTS do
					out[s] = type(row[s]) == "string" and row[s] or ""
				end
			end
			dat.slots[pg] = out
		end
	end
	return dat
end

-- bought pages only ever grow (another server's purchase is kept); the layout is last-write-wins
function M.merge(dat, other)
	local op = type(other) == "table" and math.floor(tonumber(other.pages) or 0) or 0
	if op > dat.pages then
		dat.pages = math.min(op, MAX_PAGES)
		return true
	end
	return false
end

local function perPage(d)
	return (api.hasPerk(d, "EmoteSlots") or d.perks.Emotes == true) and BIG_SLOTS or BASE_SLOTS
end

-- the layout as the wheel shows it: owned emotes only, empty slots refilled with unplaced owned emotes
local function layout(d, dat)
	local owned = api.ownedList(d, "emote")
	local own = {}
	for _, id in ipairs(owned) do
		own[id] = true
	end
	local per, pages = perPage(d), 1 + dat.pages
	local out, placed = {}, {}
	for pg = 1, pages do
		local row = dat.slots[pg] or {}
		out[pg] = {}
		for s = 1, per do
			local id = row[s]
			if type(id) == "string" and own[id] and not placed[id] then
				out[pg][s] = id
				placed[id] = true
			else
				out[pg][s] = ""
			end
		end
	end
	local i = 1
	for pg = 1, pages do
		for s = 1, per do
			if out[pg][s] == "" then
				while owned[i] and placed[owned[i]] do
					i += 1
				end
				if owned[i] then
					out[pg][s] = owned[i]
					placed[owned[i]] = true
				end
			end
		end
	end
	return out, per, pages
end

function M.publish(p, d, dat)
	local slots, per, pages = layout(d, dat)
	p:SetAttribute("EmoteWheel", api.HttpService:JSONEncode({ perPage = per, pages = pages, search = dat.pages > 0, slots = slots }))
end

-- +1 page per purchase
M.grant.emotePage = function(p, d, item)
	local dat = api.ext(d, M.name)
	if dat.pages >= MAX_PAGES then
		-- the cap (20 extra pages): the Robux comes back as Yen
		local refund = math.floor(item.price * api.Perks.YEN_PER_ROBUX)
		d.yen += refund
		return function()
			d.yen -= refund
		end
	end
	dat.pages += 1
	return function()
		dat.pages -= 1
	end
end

M.request.emoteSlot = function(p, d, arg)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	if type(arg) ~= "table" then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	local pg, s, id = tonumber(arg.page), tonumber(arg.slot), arg.id
	local per, pages = perPage(d), 1 + dat.pages
	if not pg or not s or pg % 1 ~= 0 or s % 1 ~= 0 or pg < 1 or pg > pages or s < 1 or s > per then
		return false, "?"
	end
	if id ~= "" and (type(id) ~= "string" or not api.ownsItem(d, "emote", id)) then
		return false, "YOU DON'T OWN THAT EMOTE"
	end
	-- start from what the wheel shows right now, so a swap keeps everything else where the player sees it
	local cur = layout(d, dat)
	for q = 1, pages do
		dat.slots[q] = table.clone(cur[q])
	end
	if id ~= "" then
		for q = 1, pages do
			for t = 1, per do
				if dat.slots[q][t] == id then
					dat.slots[q][t] = dat.slots[pg][s] -- swap with what was there
				end
			end
		end
	end
	dat.slots[pg][s] = id
	d.dirty = true
	api.publish(p)
	return true, id == "" and "CLEARED" or "EQUIPPED"
end

function M.init(a)
	api = a
end

return M
