-- ServerScriptService.LeaderboardService (2026-11-08) - the two Crossing leaderboards, PLAYER kills only:
--   SKYCAST screen (CR7, Playlist "board_kills")          MOST KILLS       lifetime PvP kills
--   HIKARI VISION screen (CR1, Playlist "board_streak")   BEST KILLSTREAK  most PvP kills in one life
-- A PvP kill: a player's Humanoid dies and ANOTHER player hurt that body within KILL_WINDOW seconds before (every kit
-- stamps the victim's LastHitBy before it deals damage; the last damaging hit counts). NPC KOs never count here (they
-- still tick leaderstats.Kills and earn Yen through NPCService / ShopService). Each kill is announced on
-- ServerStorage.PvPKill (BindableEvent, Fire(killerUserId, victimUserId)) and credited from that event, so a kill feed
-- or bounties can listen to the same thing. A streak is the kills since the player last died.
-- All-time numbers live in two OrderedDataStores keyed by UserId: LB_PvPKills_v1 gains each kill through IncrementAsync
-- and LB_PvPStreak_v1 only ever rises (UpdateAsync keeps the max). Writes are batched every CYCLE seconds and on leave /
-- shutdown. Every CYCLE the top TOP of each store is read and merged with the live numbers of everyone in this server,
-- then published as JSON on ReplicatedStorage.Leaderboards (attributes Kills / Streak = [{u, d, n, v}], Scope =
-- "global" | "server"); StarterPlayerScripts.LeaderboardClient draws the screens. Each player also carries LBKills
-- (lifetime PvP kills), LBBest (best streak) and KillStreak (current streak) attributes.
-- Studio: playtests READ the live boards but never WRITE to them (STUDIO_WRITES), so test KOs stay off the real
-- boards. With no DataStore access at all the boards fall back to this server only (Scope "server").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local ServerStorage = game:GetService("ServerStorage")

local TOP = 10 -- rows per board
local CYCLE = 60 -- seconds between store writes / top reads (far inside the ordered-store request budgets)
local STUDIO_WRITES = false -- true lets Studio playtests write their KOs to the live boards
local CAN_WRITE = STUDIO_WRITES or not RunService:IsStudio()
local BOARDS = { "Kills", "Streak" }
local KILL_WINDOW = 10 -- a death is a kill for the last player who damaged the body within this many seconds

local killEvent = ServerStorage:FindFirstChild("PvPKill")
if not killEvent then
	killEvent = Instance.new("BindableEvent")
	killEvent.Name = "PvPKill"
	killEvent.Parent = ServerStorage
end

local folder = ReplicatedStorage:FindFirstChild("Leaderboards")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = ReplicatedStorage
end
folder:SetAttribute("Scope", "server")
folder:SetAttribute("Kills", "[]")
folder:SetAttribute("Streak", "[]")

local function ordered(name)
	local ok, s = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	return ok and s or nil
end
local stores = { Kills = ordered("LB_PvPKills_v1"), Streak = ordered("LB_PvPStreak_v1") }
local top = { Kills = {}, Streak = {} } -- [userId] = value, the last read of each store's top TOP
local storeOk = false -- the last top read worked

-- [player] = { pending = KOs not saved yet, streak, best = best streak this session, stored = { Kills, Streak }, flushing }
local state = {}
local gone = {} -- [userId] = { Kills, Streak }: players who left this server (keeps them on a server-only board)
local names = {} -- [userId] = { d = DisplayName, n = Username }
local dirty = true

-- a player's numbers right now: what the store holds plus what this server hasn't written yet
local function live(p, s, board)
	if board == "Kills" then
		return (s.stored.Kills or top.Kills[p.UserId] or 0) + s.pending
	end
	return math.max(s.stored.Streak or top.Streak[p.UserId] or 0, s.best)
end

local function setAttrs(p, s)
	p:SetAttribute("LBKills", live(p, s, "Kills"))
	p:SetAttribute("LBBest", live(p, s, "Streak"))
	p:SetAttribute("KillStreak", s.streak)
end

local function loadStored(p, s)
	local key = tostring(p.UserId)
	for _, board in ipairs(BOARDS) do
		local store = stores[board]
		if store then
			local ok, v = pcall(store.GetAsync, store, key)
			if ok then
				-- max: a flush (or a rejoin seed) may already have set a newer number; both boards only ever grow
				s.stored[board] = math.max(s.stored[board] or 0, tonumber(v) or 0)
			end
		end
	end
end

-- write what this server owes the stores (never in Studio unless STUDIO_WRITES)
local function flush(p, s)
	if not CAN_WRITE or s.flushing then
		return
	end
	s.flushing = true
	local key = tostring(p.UserId)
	local n = s.pending
	if n > 0 and stores.Kills then
		local ok, v = pcall(stores.Kills.IncrementAsync, stores.Kills, key, n)
		if ok then
			s.pending -= n -- KOs scored during the call stay pending for the next flush
			s.stored.Kills = tonumber(v) or ((s.stored.Kills or 0) + n)
		else
			warn("[Leaderboard] saving KOs for " .. p.Name .. " failed: " .. tostring(v))
		end
	end
	local best = s.best
	if best > 0 and best > (s.stored.Streak or 0) and stores.Streak then
		local seen = 0
		local ok, err = pcall(stores.Streak.UpdateAsync, stores.Streak, key, function(old)
			seen = tonumber(old) or 0
			if best > seen then
				return best
			end
			return nil -- the stored best is already higher: leave it
		end)
		if ok then
			s.stored.Streak = math.max(seen, best)
		else
			warn("[Leaderboard] saving the best streak for " .. p.Name .. " failed: " .. tostring(err))
		end
	end
	s.flushing = false
end

local function readTop(board)
	local store = stores[board]
	if not store then
		return false
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
	if not ok then
		return false
	end
	local fresh = {}
	for _, e in ipairs(pages:GetCurrentPage()) do
		local id, v = tonumber(e.key), tonumber(e.value)
		if id and v and v > 0 then
			fresh[id] = v
		end
	end
	top[board] = fresh
	return true
end

-- display names for ids that aren't in this server (cached for the server's life)
local function resolveNames(ids)
	local need, seen = {}, {}
	for _, id in ipairs(ids) do
		if not names[id] and not seen[id] then
			seen[id] = true
			local p = Players:GetPlayerByUserId(id)
			if p then
				names[id] = { d = p.DisplayName, n = p.Name }
			elseif id > 0 then
				table.insert(need, id)
			end
		end
	end
	if #need == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, need)
	if ok and type(infos) == "table" then
		for _, info in ipairs(infos) do
			names[info.Id] = { d = info.DisplayName, n = info.Username }
		end
	end
	for _, id in ipairs(need) do
		if not names[id] then
			local ok2, n = pcall(Players.GetNameFromUserIdAsync, Players, id)
			if ok2 and n then
				names[id] = { d = n, n = n }
			end
		end
	end
end

-- the store's top TOP + everyone in (or who left) this server, best first
local function rows(board)
	local merged = {}
	local function offer(id, v)
		if v and v > 0 and v > (merged[id] or 0) then
			merged[id] = v
		end
	end
	for id, v in pairs(top[board]) do
		offer(id, v)
	end
	for id, rec in pairs(gone) do
		offer(id, rec[board])
	end
	for p, s in pairs(state) do
		offer(p.UserId, live(p, s, board))
	end
	local list = {}
	for id, v in pairs(merged) do
		table.insert(list, { id = id, v = v })
	end
	table.sort(list, function(a, b)
		if a.v ~= b.v then
			return a.v > b.v
		end
		return a.id < b.id
	end)
	while #list > TOP do
		table.remove(list)
	end
	return list
end

local function publish()
	local lists, ids = {}, {}
	for _, board in ipairs(BOARDS) do
		lists[board] = rows(board)
		for _, r in ipairs(lists[board]) do
			table.insert(ids, r.id)
		end
	end
	resolveNames(ids)
	for _, board in ipairs(BOARDS) do
		local out = {}
		for i, r in ipairs(lists[board]) do
			local nm = names[r.id]
			out[i] = { u = r.id, d = nm and nm.d or ("Player " .. r.id), n = nm and nm.n or "", v = r.v }
		end
		folder:SetAttribute(board, HttpService:JSONEncode(out))
	end
	folder:SetAttribute("Scope", storeOk and "global" or "server")
end

-- one character: remember which player last took health off it, and on death end its streak + announce the kill
local function hookCharacter(p, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local health = hum.Health
	local hitBy, hitAt = nil, -math.huge
	hum.HealthChanged:Connect(function(h)
		if h < health then
			local by = tonumber(char:GetAttribute("LastHitBy"))
			if by and by ~= p.UserId then
				hitBy, hitAt = by, os.clock()
			end
		end
		health = h
	end)
	hum.Died:Connect(function()
		local s = state[p]
		if s and s.streak > 0 then
			s.streak = 0
			setAttrs(p, s)
		end
		if hitBy and os.clock() - hitAt <= KILL_WINDOW then
			killEvent:Fire(hitBy, p.UserId)
		end
	end)
end

-- credit a PvP kill (the killer must be in this server)
killEvent.Event:Connect(function(killerId, victimId)
	killerId, victimId = tonumber(killerId), tonumber(victimId)
	local killer = killerId and Players:GetPlayerByUserId(killerId)
	local s = killer and state[killer]
	if not s or killerId == victimId then
		return
	end
	s.pending += 1
	s.streak += 1
	if s.streak > s.best then
		s.best = s.streak
	end
	setAttrs(killer, s)
	dirty = true
end)

local function onPlayer(p)
	if state[p] then
		return
	end
	local s = { pending = 0, streak = 0, best = 0, stored = {}, flushing = false }
	local back = gone[p.UserId]
	if back then -- rejoined this server: carry on from where they left (matters most on a server-only board)
		s.stored.Kills, s.stored.Streak = back.Kills, back.Streak
	end
	state[p] = s
	names[p.UserId] = { d = p.DisplayName, n = p.Name }
	setAttrs(p, s)
	task.spawn(function()
		loadStored(p, s)
		if state[p] == s then
			setAttrs(p, s)
			dirty = true
		end
	end)
	-- deaths end the streak and hand out the kill
	p.CharacterAdded:Connect(function(char)
		hookCharacter(p, char)
	end)
	if p.Character then
		task.spawn(hookCharacter, p, p.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end

Players.PlayerRemoving:Connect(function(p)
	local s = state[p]
	if not s then
		return
	end
	gone[p.UserId] = { Kills = live(p, s, "Kills"), Streak = live(p, s, "Streak") }
	state[p] = nil
	dirty = true
	while s.flushing do
		task.wait(0.1)
	end
	flush(p, s)
end)

game:BindToClose(function()
	if not CAN_WRITE then
		return
	end
	local waiting = 0
	for p, s in pairs(state) do
		waiting += 1
		task.spawn(function()
			while s.flushing do
				task.wait(0.1)
			end
			flush(p, s)
			waiting -= 1
		end)
	end
	local t0 = os.clock()
	while waiting > 0 and os.clock() - t0 < 20 do
		task.wait(0.1)
	end
end)

-- publish soon after anything changes (KOs, joins, leaves, store reads)
task.spawn(function()
	while true do
		if dirty then
			dirty = false
			local ok, err = pcall(publish)
			if not ok then
				warn("[Leaderboard] publish failed: " .. tostring(err))
			end
		end
		task.wait(0.5)
	end
end)

-- every CYCLE: write what's owed, then read both tops
task.spawn(function()
	local told = nil
	while true do
		for p, s in pairs(state) do
			task.spawn(flush, p, s)
		end
		local okK = readTop("Kills")
		local okS = readTop("Streak")
		storeOk = okK and okS
		if told ~= storeOk then
			told = storeOk
			if storeOk then
				print("[Leaderboard] boards show all-time numbers" .. (CAN_WRITE and "" or " (Studio playtest: reading only, KOs here are not saved to them)"))
			else
				warn("[Leaderboard] no DataStore access: the boards show this server only")
			end
		end
		dirty = true
		task.wait(CYCLE)
	end
end)
