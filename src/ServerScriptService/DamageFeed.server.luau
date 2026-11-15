--!nocheck
-- DamageFeed (2026-11-07): one damage number for every hit - every kit, every ability, the shared M1, thrown bodies
-- slamming into walls, anything that takes health off someone.
--
-- Instead of each kit reporting its own hits, this watches the health of every body that can be hit (RagdollNPC bodies
-- and player characters) and reports what was actually lost. Hits on one body in one frame add up; small ticks
-- (domain overload, burns, damage over time) gather and go out at most ~8 times a second per body, and clients merge
-- them into one climbing number (ReplicatedStorage.KitFeedback.numbers). Broadcast on ReplicatedStorage.DamageFeed:
--   { { p = Vector3, d = damage, u = attackerUserId?, k = attacker's Kit?, v = victim player's UserId?, big = bool }, ... }
-- Accounting is by health LEVEL, not by event: each body keeps the level it has been reported down to, and a send
-- reports that level minus its health now, then moves the level. A health event only says "look at this body" (and
-- the look waits a frame). So no damage is ever counted twice or lost, whatever order the deferred health events
-- arrive in, and a hit undone on the spot (the Ascendant Instinct form puts the health straight back) nets to nothing.
-- Not counted: a script trimming Health down to a just-lowered MaxHealth (a form ending), and a body the game retires
-- (attribute Retired, set by NPCService / CityNav right before they zero an out-of-play body). Each entry also
-- carries the body (m) so clients merge its numbers per body, not per spot (a fleeing NPC keeps one number).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPC_TAG = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC")).Tag
local BIG = 35 -- a hit this size gets the big number (the line the kits already used)
local CHUNK = 4 -- a body's pending damage this size goes out at once...
local TICK = 0.12 -- ...smaller amounts at most this often per body
local MAX_BATCH = 80

local Feed = ReplicatedStorage:FindFirstChild("DamageFeed")
if not Feed then
	Feed = Instance.new("RemoteEvent")
	Feed.Name = "DamageFeed"
	Feed.Parent = ReplicatedStorage
end

-- [Humanoid] = { model, reported = health level already accounted for, f = frame it went dirty, t0, sent = os.clock() }
local tracked = setmetatable({}, { __mode = "k" })
local dirty = {} -- [Humanoid] = true while it may have unsent damage
local hookedModel = setmetatable({}, { __mode = "k" })
local frame = 0

local function hookHumanoid(model, hum)
	if tracked[hum] then
		return
	end
	local st = { model = model, reported = hum.Health, f = 0, t0 = 0 }
	tracked[hum] = st
	local last = hum.Health
	local max = hum.MaxHealth
	local maxCutAt = -math.huge
	hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if hum.MaxHealth < max - 0.01 then
			maxCutAt = os.clock()
		end
		max = hum.MaxHealth
	end)
	hum.HealthChanged:Connect(function(h)
		local prev = last
		last = h
		if h >= prev - 0.001 then
			-- healing raises the level nothing is owed below (while a hit is pending, the send-time look sorts it out:
			-- that is what makes an undone hit net to zero)
			if not dirty[hum] and h > st.reported then
				st.reported = h
			end
			return
		end
		if model:GetAttribute("Retired") then
			st.reported = h
			dirty[hum] = nil
			return
		end
		if os.clock() - maxCutAt < 0.5 and h >= hum.MaxHealth - 0.01 then
			st.reported -= prev - h -- trimmed down to a MaxHealth that was just lowered: absorb it, not a hit
			return
		end
		if not dirty[hum] then
			dirty[hum] = true
			st.f = frame
			st.t0 = os.clock()
		end
	end)
end

local function hookModel(model)
	if hookedModel[model] or not model:IsA("Model") then
		return
	end
	hookedModel[model] = true
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hookHumanoid(model, hum)
	end
	model.ChildAdded:Connect(function(c)
		if c:IsA("Humanoid") then
			hookHumanoid(model, c)
		end
	end)
end

for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
	hookModel(m)
end
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(hookModel)

local function hookPlayer(p)
	if p.Character then
		hookModel(p.Character)
	end
	p.CharacterAdded:Connect(hookModel)
	-- a kit that swaps the character model outright (a giant form) still gets watched
	p:GetPropertyChangedSignal("Character"):Connect(function()
		if p.Character then
			hookModel(p.Character)
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)

local function rootOf(model)
	return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
		or model:FindFirstChild("Head") or model.PrimaryPart
end

RunService.Heartbeat:Connect(function()
	frame += 1
	if not next(dirty) then
		return
	end
	local clock = os.clock()
	local list
	for hum in pairs(dirty) do
		local st = tracked[hum]
		local m = st and st.model
		if not st or not m.Parent or not hum.Parent then
			dirty[hum] = nil
		elseif m:GetAttribute("Retired") then
			st.reported = hum.Health
			dirty[hum] = nil
		elseif frame > st.f then -- a frame to settle: anything that undoes the hit has run by now
			local cur = math.max(hum.Health, 0)
			local net = st.reported - cur
			if net <= 0.001 then
				st.reported = cur -- undone, or healed back
				dirty[hum] = nil
			elseif net >= CHUNK or (net >= 0.5 and clock - (st.sent or -math.huge) >= TICK) then
				st.reported = cur
				st.sent = clock
				dirty[hum] = nil
				local r = rootOf(m)
				list = list or {}
				if r and #list < MAX_BATCH then
					local uid = m:GetAttribute("LastHitBy")
					local attacker = type(uid) == "number" and Players:GetPlayerByUserId(uid) or nil
					local victim = Players:GetPlayerFromCharacter(m)
					table.insert(list, {
						m = m,
						p = r.Position,
						d = net,
						u = attacker and uid or nil,
						k = attacker and attacker:GetAttribute("Kit") or nil,
						v = victim and victim.UserId or nil,
						big = net >= BIG,
					})
				end
			elseif clock - st.t0 > 1.5 then
				st.reported = cur -- a residue too small to show
				dirty[hum] = nil
			end
		end
	end
	if list and #list > 0 then
		Feed:FireAllClients(list)
		-- (2026-11-11) quests: damage dealt to someone else
		local qe = game:GetService("ServerScriptService"):FindFirstChild("ShopService") and game:GetService("ServerScriptService").ShopService:FindFirstChild("QuestEvent")
		if qe then
			for _, h in ipairs(list) do
				local ap = h.u and Players:GetPlayerByUserId(h.u)
				if ap and h.v ~= h.u then
					qe:Fire(ap, "damage", h.d)
				end
			end
		end
	end
end)

print("[DamageFeed] online - damage numbers for every hit")
