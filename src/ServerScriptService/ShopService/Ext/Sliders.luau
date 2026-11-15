--!nocheck
-- ShopService.Ext.Sliders (2026-11-14, sandbox shop): the SANDBOX SLIDERS' saved values (HudShared.SliderCatalog) and
-- the Spawn Limit x3 perk. Saved in the profile as ext.Sliders = { speed = n, jump = n, ..., god = bool } - only keys the
-- player has moved; the rest read as their default (a 2x Speed / 2x Jump owner from before the sliders starts at x2
-- while that old toggle was on).
-- publish (inside ShopService.publishPerks, AFTER it wrote SpeedMul / JumpMul for the old perks) writes for every
-- slider its attribute = the saved value while the player OWNS that slider (its perk, the Sandbox Sliders Pack, or the
-- retired perk it replaced), else the default. Also:
--   SliderVals  (JSON { key = value, god = bool }) what the panel shows
--   SliderOwned (JSON list of keys)                  which rows the panel unlocks
--   GodMode     (bool)                              Health slider owner with GOD MODE on (ServerScriptService.PlayerHealth)
--   SpawnCapMul (number)                            PerkCatalog.TUNING.SPAWN_CAP_MUL with Spawn Limit x3, else 1
-- Request ("sliders", { key = value, god = bool }) -> ok, message, SliderVals: keys not owned / not numbers are ignored.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local S = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("SliderCatalog"))

local M = { name = "Sliders", request = {} }
local api

function M.init(a)
	api = a
end

function M.load(raw)
	local data = {}
	if type(raw) == "table" then
		for _, def in ipairs(S.LIST) do
			local v = raw[def.key]
			if type(v) == "number" and v == v then
				data[def.key] = S.clamp(def, v)
			end
		end
		data.god = raw.god == true or nil
	end
	return data
end

local function owns(d, def)
	return api.hasPerk(d, def.perk) or api.hasPerk(d, S.PACK) or (def.legacy ~= nil and api.hasPerk(d, def.legacy))
end
M.owns = owns

local function valueOf(d, data, def)
	local v = data[def.key]
	if type(v) == "number" then
		return S.clamp(def, v)
	end
	if def.legacy and api.hasPerk(d, def.legacy) and d.equip[def.legacyEquip] ~= false then
		return def.legacyValue
	end
	return def.default
end

function M.publish(p, d, data)
	local vals, ownedKeys = {}, {}
	for _, def in ipairs(S.LIST) do
		local own = owns(d, def)
		local v = own and valueOf(d, data, def) or def.default
		vals[def.key] = v
		if own then
			table.insert(ownedKeys, def.key)
		end
		p:SetAttribute(def.attr, v)
	end
	local god = owns(d, S.byKey.health) and data.god == true
	vals.god = god
	p:SetAttribute("GodMode", god)
	p:SetAttribute("SliderVals", api.HttpService:JSONEncode(vals))
	p:SetAttribute("SliderOwned", api.HttpService:JSONEncode(ownedKeys))
	local capMul = (api.Perks.TUNING and api.Perks.TUNING.SPAWN_CAP_MUL) or 3
	p:SetAttribute("SpawnCapMul", api.hasPerk(d, "SpawnPlus") and capMul or 1)
end

M.request.sliders = function(p, d, arg)
	if type(arg) ~= "table" then
		return false, "?"
	end
	local data = api.ext(d, M.name)
	local changed, refused = false, false
	for k, v in pairs(arg) do
		if k == "god" then
			if type(v) == "boolean" and owns(d, S.byKey.health) then
				data.god = v or nil
				changed = true
			else
				refused = true
			end
		else
			local def = type(k) == "string" and S.byKey[k]
			if def and type(v) == "number" and v == v and math.abs(v) < 1e7 then
				if owns(d, def) then
					data[k] = S.snap(def, v)
					changed = true
				else
					refused = true
				end
			end
		end
	end
	if changed then
		d.dirty = true
		M.publish(p, d, data)
	end
	return changed, refused and "UNLOCK IT FIRST" or (changed and "SAVED" or "?"), p:GetAttribute("SliderVals")
end

return M
