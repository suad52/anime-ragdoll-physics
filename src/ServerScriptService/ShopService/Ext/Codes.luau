--!nocheck
-- ShopService.Ext.Codes (2026-11-09, shop expansion): redeemable codes (the shop's CODES tab). The list lives in
-- ServerStorage.ShopCodes (server-only). data { redeemed = { CODE = os.time } } - grow-only (merge unions it), so a code
-- can never be redeemed twice, even across servers.
-- Request ("redeem", text) -> ok, message.
local ServerStorage = game:GetService("ServerStorage")
local M = { name = "Codes", request = {} }
local api
local attempts = setmetatable({}, { __mode = "k" }) -- [player] = { times } (5 wrong codes a minute at most)

local function codes()
	local m = ServerStorage:FindFirstChild("ShopCodes")
	local ok, t = pcall(require, m)
	return (ok and type(t) == "table") and t or {}
end

function M.load(raw)
	local dat = { redeemed = {} }
	if type(raw) == "table" and type(raw.redeemed) == "table" then
		for k, v in pairs(raw.redeemed) do
			if type(k) == "string" then
				dat.redeemed[k] = tonumber(v) or 0
			end
		end
	end
	return dat
end

function M.merge(dat, other)
	local grew = false
	if type(other) == "table" and type(other.redeemed) == "table" then
		for k, v in pairs(other.redeemed) do
			if type(k) == "string" and not dat.redeemed[k] then
				dat.redeemed[k] = tonumber(v) or 0
				grew = true
			end
		end
	end
	return grew
end

M.request.redeem = function(p, d, text)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	if type(text) ~= "string" then
		return false, "TYPE A CODE"
	end
	local key = string.upper((text:gsub("%s+", "")))
	if key == "" or #key > 40 then
		return false, "TYPE A CODE"
	end
	local now = os.clock()
	local a = attempts[p] or {}
	attempts[p] = a
	for i = #a, 1, -1 do
		if now - a[i] > 60 then
			table.remove(a, i)
		end
	end
	if #a >= 5 then
		return false, "TOO MANY TRIES - WAIT A MINUTE"
	end
	local c = codes()[key]
	if type(c) ~= "table" or c.active == false then
		table.insert(a, now)
		return false, "THAT CODE DOESN'T EXIST"
	end
	if type(c.expires) == "number" and os.time() > c.expires then
		return false, "THAT CODE HAS EXPIRED"
	end
	local dat = api.ext(d, M.name)
	if dat.redeemed[key] then
		return false, "ALREADY REDEEMED"
	end
	dat.redeemed[key] = os.time()
	local got = {}
	local yen = math.max(0, math.floor(tonumber(c.yen) or 0))
	if yen > 0 then
		d.yen += yen
		table.insert(got, yen .. " " .. api.Catalog.CURRENCY)
	end
	for cat, n in pairs(type(c.rolls) == "table" and c.rolls or {}) do
		if api.POOL[cat] then
			local ids = api.grantRolls(d, cat, math.clamp(math.floor(tonumber(n) or 0), 0, 10))
			if #ids > 0 then
				api.announceRoll(p, d, cat, ids)
				table.insert(got, #ids .. " " .. string.upper(cat) .. (#ids > 1 and "S" or ""))
			end
		end
	end
	local picks = api.ext(d, "RollPicks")
	for cat, n in pairs(type(c.picks) == "table" and c.picks or {}) do
		n = math.clamp(math.floor(tonumber(n) or 0), 0, 10)
		if api.POOL[cat] and n > 0 and type(picks) == "table" then
			picks[cat] = (picks[cat] or 0) + n
			table.insert(got, n .. " FREE " .. string.upper(cat) .. " PICK" .. (n > 1 and "S" or ""))
		end
	end
	-- (2026-11-11) emotes = { id, ... }: those exact emotes (the way to get EXCLUSIVE ones, e.g. NeonSalute)
	for _, id in ipairs(type(c.emotes) == "table" and c.emotes or {}) do
		local set = api.POOLSET.emote
		if set and set[id] and type(d.items) == "table" and type(d.items.emote) == "table" and not d.items.emote[id] then
			d.items.emote[id] = true
			local name = id
			for _, e in ipairs(api.Perks.EMOTES or {}) do
				if e.id == id then
					name = e.name
				end
			end
			table.insert(got, "THE " .. string.upper(name) .. " EMOTE")
		end
	end
	d.dirty = true
	api.publish(p)
	task.spawn(api.save, p)
	return true, #got > 0 and ("REDEEMED: " .. table.concat(got, " + ")) or "REDEEMED!"
end

function M.init(a)
	api = a
end

return M
