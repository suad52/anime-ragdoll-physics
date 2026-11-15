--!nocheck
-- ServerScriptService.PerkUltOutfit (2026-11-09, shop expansion): the Ultimate Outfit perk (PerkCatalog "UltOutfit").
-- While a fighter's ultimate FORM is active, the player wears one of their saved Roblox outfits (picked in Settings ->
-- General; ShopService.Ext.Settings writes UltOutfitId only with the perk). When the form ends, their own look returns.
-- Ultimate forms = a character attribute that is truthy (FORMS) or a server-time deadline still ahead (UNTIL).
-- ONLY the outfit's clothing, accessories and face are worn - never its body parts or scale (the fighters' ragdoll
-- rigs are built on the player's own body parts) and never its skin colours (forms tint the body themselves, e.g.
-- Gear 5 whitens it on the client, and a server colour change would fight that). Giant forms (model scale ~= 1: the Titans) are
-- skipped - an outfit doesn't fit a 15-stud body. Checked every POLL seconds.
-- Studio: script.Control:Invoke("testUser", player, userId) wears that user's avatar look as if it were the outfit.
local Players = game:GetService("Players")

local POLL = 0.4
local FORMS = { "Morphed", "FoxBeast", "OFAMode", "Guardian", "Domain", "TitanForm", "AscForm" }
local UNTIL = { "BankaiUntil", "Gear5Until" }
local COPY = { "Shirt", "Pants", "GraphicTShirt", "Face" }

local cache = {} -- outfit id -> HumanoidDescription
local state = setmetatable({}, { __mode = "k" }) -- [player] = { char, on, original, busy }
local testDesc = setmetatable({}, { __mode = "k" }) -- Studio: [player] = description to wear

local function formActive(char)
	for _, a in ipairs(FORMS) do
		local v = char:GetAttribute(a)
		if v ~= nil and v ~= false and v ~= "" then
			return true
		end
	end
	local t = workspace:GetServerTimeNow()
	for _, a in ipairs(UNTIL) do
		local v = tonumber(char:GetAttribute(a))
		if v and v > t then
			return true
		end
	end
	return false
end

local function outfitDesc(p)
	if testDesc[p] then
		return testDesc[p]
	end
	local id = tonumber(p:GetAttribute("UltOutfitId")) or 0
	if id <= 0 then
		return nil
	end
	if cache[id] == nil then
		local ok, d = pcall(Players.GetHumanoidDescriptionFromOutfitId, Players, id)
		cache[id] = ok and d or false
	end
	return cache[id] or nil
end

-- the player's current look with the outfit's clothes / accessories / face on top
local function blend(current, outfit)
	local d = current:Clone()
	for _, prop in ipairs(COPY) do
		pcall(function()
			d[prop] = outfit[prop]
		end)
	end
	pcall(function()
		d:SetAccessories(outfit:GetAccessories(true), true)
	end)
	return d
end

local function apply(p, st, hum)
	local out = outfitDesc(p)
	if not out then
		return
	end
	st.busy = true
	local ok, err = pcall(function()
		st.original = hum:GetAppliedDescription()
		hum:ApplyDescription(blend(st.original, out))
	end)
	st.busy = false
	if ok then
		st.on = true
	else
		warn("[PerkUltOutfit] apply: " .. tostring(err))
		st.failedAt = os.clock()
	end
end

local function restore(st, hum)
	st.busy = true
	pcall(function()
		if st.original then
			hum:ApplyDescription(st.original)
		end
	end)
	st.busy = false
	st.on = false
end

task.spawn(function()
	while true do
		task.wait(POLL)
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local st = state[p]
			if not st or st.char ~= char then
				st = { char = char, on = false }
				state[p] = st
			end
			if hum and hum.Health > 0 and not st.busy then
				local wants = (testDesc[p] ~= nil or (tonumber(p:GetAttribute("UltOutfitId")) or 0) > 0) and formActive(char)
				local scaleOk = true
				pcall(function()
					scaleOk = math.abs(char:GetScale() - 1) < 0.05
				end)
				if wants and scaleOk and not st.on and (not st.failedAt or os.clock() - st.failedAt > 10) then
					task.spawn(apply, p, st, hum)
				elseif st.on and (not wants or not scaleOk) then
					task.spawn(restore, st, hum)
				end
			end
		end
	end
end)

local ctl = Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, p, a)
	if cmd == "testUser" and p then
		local ok, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, tonumber(a) or 1)
		testDesc[p] = ok and d or nil
		return ok
	elseif cmd == "clearTest" and p then
		testDesc[p] = nil
		return true
	elseif cmd == "state" and p then
		local st = state[p]
		return { on = st and st.on or false, active = p.Character and formActive(p.Character) or false }
	end
	return nil
end
ctl.Parent = script
