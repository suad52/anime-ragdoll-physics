--!nocheck
-- ShopService.Ext.Quests (2026-11-11, "wiki extras"): DAILY and WEEKLY quests (HudShared.QuestCatalog).
--   data { day, week, daily = { { i = pool index, n = progress, c = claimed } x3 }, weekly = { ... } }
--   attribute Quests (JSON) = { day, week, dayEnds, weekEnds, daily = {{i, n, c}}, weekly = {{i, n, c}} }
--   request "questClaim" { list = "daily" | "weekly", n = 1..3 } -> pays the quest's Yen once it is complete
-- Progress: ShopService.QuestEvent (BindableEvent, created here) :Fire(player, kind, amount) - DamageFeed, PerkEmotes,
-- TauntService, Ext.Gadgets and DuelService fire it. Watched here directly: ServerStorage.PvPKill (player KOs),
-- RagdollNPC deaths with a LastHitBy (dummy KOs) and a minute clock.
-- Studio: ShopService.QuestTest:Invoke(player, kind, amount) adds progress; (player, "reset") deals a fresh set.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Q = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("QuestCatalog"))

local M = { name = "Quests", request = {} }
local api

local function pick(pool, n, seed)
	local rng = Random.new(seed)
	local idx = {}
	for i = 1, #pool do
		idx[i] = i
	end
	for i = #idx, 2, -1 do
		local j = rng:NextInteger(1, i)
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out = {}
	for i = 1, math.min(n, #idx) do
		out[i] = { i = idx[i], n = 0, c = false }
	end
	return out
end

-- deal today's / this week's set when the day / week changed
local function fresh(p, dat)
	local now = os.time()
	local day, week = Q.dayIndex(now), Q.weekIndex(now)
	local changed = false
	if dat.day ~= day or type(dat.daily) ~= "table" or #dat.daily == 0 then
		dat.day = day
		dat.daily = pick(Q.DAILY, Q.PER_DAY, p.UserId * 31 + day)
		changed = true
	end
	if dat.week ~= week or type(dat.weekly) ~= "table" or #dat.weekly == 0 then
		dat.week = week
		dat.weekly = pick(Q.WEEKLY, Q.PER_WEEK, p.UserId * 17 + week * 7)
		changed = true
	end
	return changed
end

local function cleanList(list, pool)
	local out = {}
	if type(list) == "table" then
		for _, q in ipairs(list) do
			local i = type(q) == "table" and tonumber(q.i)
			if i and pool[i] and #out < 3 then
				table.insert(out, { i = i, n = math.clamp(tonumber(q.n) or 0, 0, pool[i].target), c = q.c == true })
			end
		end
	end
	return out
end

function M.load(raw)
	raw = type(raw) == "table" and raw or {}
	return {
		day = tonumber(raw.day),
		week = tonumber(raw.week),
		daily = cleanList(raw.daily, Q.DAILY),
		weekly = cleanList(raw.weekly, Q.WEEKLY),
	}
end

local function pub(p, dat)
	p:SetAttribute("Quests", api.HttpService:JSONEncode({
		day = dat.day, week = dat.week, dayEnds = Q.dayEnds(dat.day), weekEnds = Q.weekEnds(dat.week),
		daily = dat.daily, weekly = dat.weekly,
	}))
end

function M.publish(p, d, dat)
	if fresh(p, dat) then
		d.dirty = true
	end
	pub(p, dat)
end

local function progress(p, kind, amount)
	local d = api.data[p]
	if not d or type(kind) ~= "string" then
		return
	end
	amount = tonumber(amount) or 1
	if amount <= 0 then
		return
	end
	local dat = api.ext(d, M.name)
	local changed = fresh(p, dat)
	for _, pair in ipairs({ { dat.daily, Q.DAILY }, { dat.weekly, Q.WEEKLY } }) do
		for _, q in ipairs(pair[1]) do
			local def = pair[2][q.i]
			if def and def.kind == kind and q.n < def.target then
				q.n = math.min(def.target, q.n + amount)
				changed = true
			end
		end
	end
	if changed then
		d.dirty = true
		pub(p, dat)
	end
end
M.progress = progress

M.request.questClaim = function(p, d, arg)
	if type(arg) ~= "table" then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	fresh(p, dat)
	local list, pool = dat.daily, Q.DAILY
	if arg.list == "weekly" then
		list, pool = dat.weekly, Q.WEEKLY
	elseif arg.list ~= "daily" then
		return false, "?"
	end
	local q = list[tonumber(arg.n) or 0]
	local def = q and pool[q.i]
	if not def then
		return false, "?"
	end
	if q.c then
		return false, "ALREADY CLAIMED"
	end
	if q.n < def.target then
		return false, "NOT DONE YET"
	end
	q.c = true
	d.yen += def.reward
	d.dirty = true
	api.publish(p)
	task.spawn(api.save, p)
	return true, "+" .. api.Catalog.CURRENCY .. " " .. def.reward
end

function M.init(a)
	api = a
	local shop = script.Parent.Parent
	local ev = shop:FindFirstChild("QuestEvent")
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = "QuestEvent"
		ev.Parent = shop
	end
	ev.Event:Connect(function(p, kind, amount)
		if typeof(p) == "Instance" and p:IsA("Player") then
			progress(p, kind, amount)
		end
	end)
	-- player KOs
	task.spawn(function()
		local pk = ServerStorage:WaitForChild("PvPKill", 60)
		if pk then
			pk.Event:Connect(function(killerUid)
				local p = Players:GetPlayerByUserId(tonumber(killerUid) or 0)
				if p then
					progress(p, "ko_players", 1)
				end
			end)
		end
	end)
	-- dummy KOs
	local counted = setmetatable({}, { __mode = "k" })
	local function watch(m)
		local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		hum.Died:Connect(function()
			if counted[m] then
				return
			end
			counted[m] = true
			local p = Players:GetPlayerByUserId(tonumber(m:GetAttribute("LastHitBy")) or 0)
			if p then
				progress(p, "ko_npcs", 1)
			end
		end)
	end
	for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
		task.spawn(watch, m)
	end
	CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(function(m)
		task.spawn(watch, m)
	end)
	-- minutes played
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(Players:GetPlayers()) do
				progress(p, "minutes", 1)
			end
		end
	end)
	if api.isStudio then
		local f = Instance.new("BindableFunction")
		f.Name = "QuestTest"
		f.OnInvoke = function(p, kind, amount)
			local d = api.data[p]
			if not d then
				return false
			end
			local dat = api.ext(d, M.name)
			if kind == "reset" then
				dat.day, dat.week = nil, nil
				fresh(p, dat)
				pub(p, dat)
				return true
			end
			progress(p, kind, amount)
			return api.HttpService:JSONEncode(dat)
		end
		f.Parent = shop
	end
end

return M
