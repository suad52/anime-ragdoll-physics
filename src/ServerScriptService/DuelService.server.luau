--!nocheck
-- ServerScriptService.DuelService (2026-11-11, "wiki extras"): 1v1 DUELS in a private arena + the VICTORY FLASH.
-- RemoteEvent HudShared.Duel (created here)
--   client -> server  ("challenge", targetUserId)  ("respond", challengerUserId, accept)  ("forfeit")
--   server -> client  ("incoming", fromPlayer, expiresAt)  ("status", text)  ("declined", byPlayer)
--                     ("start", { opponent = Player, fightAt = server time the fight starts, endsAt = time limit })
--                     ("end", { winner = Player?, loser = Player?, flash = id, reason = "ko" | "left" | "time" | "forfeit" | "draw" })
-- A duel: both fighters healed and teleported into a free ARENA (built on demand far outside the city, slot n at
-- ARENA_ORIGIN + n * ARENA_STEP; walled, so nobody falls out), frozen for COUNTDOWN s, then fight. It ends on a KO
-- (the other one wins), a leave / forfeit, or TIME_LIMIT (more health % wins; equal = draw). Everyone in it gets the
-- winner's equipped flash (player attribute VictoryFlash, ShopService.Ext.Victory). Then the winner goes back to where
-- they were and both lose the InDuel attribute (it also switches SettingsEffects to duel music).
-- Quests: "duels" for both, "duel_wins" for the winner (ShopService.QuestEvent); ShopService.DuelResult pays the winner.
-- Studio: script.Control:Invoke("start", a, b) / ("end", player, "ko") / ("state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("HudShared")
local remote = shared:FindFirstChild("Duel")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Duel"
	remote.Parent = shared
end

local INVITE_TIME = 20
local COUNTDOWN = 3
local TIME_LIMIT = 180
local AFTER = 4.2 -- the flash plays, then the winner goes home
local ARENA_ORIGIN = Vector3.new(0, 520, 2900)
local ARENA_STEP = Vector3.new(420, 0, 0)
local SIZE = 120

local invites = {} -- [target] = { from = Player, at = os.clock() }
local duelOf = {} -- [player] = duel
local arenas = {} -- [slot] = Model
local busySlot = {}
local lastChallenge = {}

local function now()
	return workspace:GetServerTimeNow()
end
local function questEvent()
	local shop = ServerScriptService:FindFirstChild("ShopService")
	return shop and shop:FindFirstChild("QuestEvent"), shop and shop:FindFirstChild("DuelResult")
end
local function alive(p)
	local char = p and p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0 and char:FindFirstChild("HumanoidRootPart") and hum or nil
end

---------------------------------------------------------------------------------------------------------------------
-- ARENAS
local folder = workspace:FindFirstChild("DuelArenas") or Instance.new("Folder")
folder.Name = "DuelArenas"
folder.Parent = workspace

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function buildArena(slot)
	if arenas[slot] then
		return arenas[slot]
	end
	local c = ARENA_ORIGIN + ARENA_STEP * (slot - 1)
	local m = Instance.new("Model")
	m.Name = "DuelArena_" .. slot
	local floor = part({ Name = "Floor", Size = Vector3.new(SIZE, 6, SIZE), CFrame = CFrame.new(c - Vector3.new(0, 3, 0)), Material = Enum.Material.Slate,
		Color = Color3.fromRGB(38, 36, 52) }, m)
	part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, SIZE * 0.7, SIZE * 0.7), CFrame = CFrame.new(c + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 80, 140), CanCollide = false, CanQuery = false }, m)
	part({ Name = "RingInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.32, SIZE * 0.66, SIZE * 0.66), CFrame = CFrame.new(c + Vector3.new(0, 0.11, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Slate, Color = Color3.fromRGB(30, 28, 44), CanCollide = false, CanQuery = false }, m)
	local H = 90
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local pos = c + Vector3.new(side[1] * (SIZE / 2 + 1), H / 2, side[2] * (SIZE / 2 + 1))
		local size = side[1] ~= 0 and Vector3.new(2, H, SIZE + 4) or Vector3.new(SIZE + 4, H, 2)
		part({ Name = "Wall", Size = size, CFrame = CFrame.new(pos), Material = Enum.Material.ForceField, Color = Color3.fromRGB(120, 200, 255),
			Transparency = 0.55, CastShadow = false }, m)
		part({ Name = "Edge", Size = side[1] ~= 0 and Vector3.new(1, 1, SIZE) or Vector3.new(SIZE, 1, 1),
			CFrame = CFrame.new(c + Vector3.new(side[1] * (SIZE / 2 - 0.5), 0.5, side[2] * (SIZE / 2 - 0.5))), Material = Enum.Material.Neon,
			Color = Color3.fromRGB(90, 200, 255), CanCollide = false }, m)
	end
	part({ Name = "Ceiling", Size = Vector3.new(SIZE + 4, 2, SIZE + 4), CFrame = CFrame.new(c + Vector3.new(0, H, 0)), Transparency = 1, CastShadow = false }, m)
	for i, x in ipairs({ -1, 1 }) do
		local sp = part({ Name = "Spawn" .. i, Size = Vector3.new(6, 0.4, 6), CFrame = CFrame.new(c + Vector3.new(x * 38, 0.2, 0)),
			Material = Enum.Material.Neon, Color = i == 1 and Color3.fromRGB(255, 90, 120) or Color3.fromRGB(90, 170, 255), CanCollide = false }, m)
		local _ = sp
	end
	m.PrimaryPart = floor
	m:SetAttribute("Center", c)
	m.Parent = folder
	arenas[slot] = m
	return m
end

local function freeSlot()
	for i = 1, 12 do
		if not busySlot[i] then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- DUELS
local endDuel -- forward

local function setIn(p, opponent)
	p:SetAttribute("InDuel", opponent and opponent.UserId or nil)
end

local function startDuel(a, b)
	if duelOf[a] or duelOf[b] or a == b then
		return false, "BUSY"
	end
	local ha, hb = alive(a), alive(b)
	if not (ha and hb) then
		return false, "BOTH FIGHTERS MUST BE ALIVE"
	end
	local slot = freeSlot()
	if not slot then
		return false, "ALL ARENAS ARE BUSY - TRY AGAIN SOON"
	end
	busySlot[slot] = true
	local arena = buildArena(slot)
	local c = arena:GetAttribute("Center")
	local duel = { a = a, b = b, slot = slot, home = {}, conns = {}, over = false, fightAt = now() + COUNTDOWN, endsAt = now() + COUNTDOWN + TIME_LIMIT }
	duelOf[a], duelOf[b] = duel, duel
	for i, p in ipairs({ a, b }) do
		local char = p.Character
		local root = char.HumanoidRootPart
		local hum = char:FindFirstChildOfClass("Humanoid")
		duel.home[p] = root.CFrame
		setIn(p, i == 1 and b or a)
		char:SetAttribute("LastHitBy", nil)
		hum.Health = hum.MaxHealth
		local x = i == 1 and -38 or 38
		local at = c + Vector3.new(x, 4, 0)
		char:PivotTo(CFrame.lookAt(at, c + Vector3.new(0, 4, 0)))
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		table.insert(duel.conns, hum.Died:Connect(function()
			if not duel.over then
				endDuel(duel, i == 1 and b or a, p, "ko")
			end
		end))
	end
	for _, p in ipairs({ a, b }) do
		remote:FireClient(p, "start", { opponent = p == a and b or a, fightAt = duel.fightAt, endsAt = duel.endsAt })
	end
	task.delay(COUNTDOWN, function()
		if duel.over then
			return
		end
		for _, p in ipairs({ a, b }) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.Anchored = false
			end
		end
	end)
	task.delay(COUNTDOWN + TIME_LIMIT, function()
		if duel.over then
			return
		end
		local function pct(p)
			local hum = alive(p)
			return hum and hum.Health / math.max(hum.MaxHealth, 1) or 0
		end
		local pa, pb = pct(a), pct(b)
		if math.abs(pa - pb) < 0.01 then
			endDuel(duel, nil, nil, "draw")
		elseif pa > pb then
			endDuel(duel, a, b, "time")
		else
			endDuel(duel, b, a, "time")
		end
	end)
	return true
end

endDuel = function(duel, winner, loser, reason)
	if duel.over then
		return
	end
	duel.over = true
	for _, c in ipairs(duel.conns) do
		c:Disconnect()
	end
	local flash = winner and winner:GetAttribute("VictoryFlash") or "Crown"
	for _, p in ipairs({ duel.a, duel.b }) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = false
		end
		if p.Parent then
			remote:FireClient(p, "end", { winner = winner, loser = loser, flash = flash, reason = reason })
		end
	end
	local qe, result = questEvent()
	if qe then
		for _, p in ipairs({ duel.a, duel.b }) do
			if p.Parent then
				qe:Fire(p, "duels", 1)
			end
		end
		if winner and winner.Parent then
			qe:Fire(winner, "duel_wins", 1)
		end
	end
	if result and winner and winner.Parent then
		result:Fire(winner, loser)
	end
	task.delay(AFTER, function()
		for _, p in ipairs({ duel.a, duel.b }) do
			if duelOf[p] == duel then
				duelOf[p] = nil
			end
			if p.Parent then
				setIn(p, nil)
				local hum = alive(p)
				if hum then -- still standing in the arena: home, healed
					local char = p.Character
					char:SetAttribute("LastHitBy", nil)
					if duel.home[p] then
						char:PivotTo(duel.home[p] + Vector3.new(0, 3, 0))
					end
					char.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
					hum.Health = hum.MaxHealth
				end
			end
		end
		busySlot[duel.slot] = nil
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- REQUESTS
remote.OnServerEvent:Connect(function(p, kind, a, b)
	if kind == "challenge" then
		local target = Players:GetPlayerByUserId(tonumber(a) or 0)
		if not target or target == p then
			return
		end
		local t = os.clock()
		if lastChallenge[p] and t - lastChallenge[p] < 3 then
			remote:FireClient(p, "status", "WAIT A MOMENT")
			return
		end
		lastChallenge[p] = t
		if duelOf[p] then
			remote:FireClient(p, "status", "YOU'RE ALREADY IN A DUEL")
			return
		end
		if duelOf[target] then
			remote:FireClient(p, "status", string.upper(target.DisplayName) .. " IS IN A DUEL")
			return
		end
		if not alive(p) or not alive(target) then
			remote:FireClient(p, "status", "BOTH FIGHTERS MUST BE ALIVE")
			return
		end
		invites[target] = { from = p, at = t }
		remote:FireClient(target, "incoming", p, now() + INVITE_TIME)
		remote:FireClient(p, "status", "CHALLENGE SENT TO " .. string.upper(target.DisplayName))
	elseif kind == "respond" then
		local inv = invites[p]
		if not inv or inv.from.UserId ~= tonumber(a) then
			return
		end
		invites[p] = nil
		if os.clock() - inv.at > INVITE_TIME or not inv.from.Parent then
			remote:FireClient(p, "status", "THAT CHALLENGE EXPIRED")
			return
		end
		if b == true then
			local ok, why = startDuel(inv.from, p)
			if not ok then
				remote:FireClient(p, "status", why)
				remote:FireClient(inv.from, "status", why)
			end
		else
			remote:FireClient(inv.from, "declined", p)
		end
	elseif kind == "forfeit" then
		local duel = duelOf[p]
		if duel and not duel.over then
			endDuel(duel, duel.a == p and duel.b or duel.a, p, "forfeit")
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	invites[p] = nil
	lastChallenge[p] = nil
	local duel = duelOf[p]
	if duel and not duel.over then
		endDuel(duel, duel.a == p and duel.b or duel.a, p, "left")
	end
	duelOf[p] = nil
end)

-- Studio test hook
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "start" then
			return startDuel(a, b)
		elseif cmd == "practice" then -- one player, against themself: the arena, countdown, flash and trip home
			local slot = freeSlot()
			busySlot[slot] = true
			local c = buildArena(slot):GetAttribute("Center")
			local duel = { a = a, b = a, slot = slot, home = {}, conns = {}, over = false, fightAt = now() + COUNTDOWN, endsAt = now() + COUNTDOWN + TIME_LIMIT }
			duelOf[a] = duel
			local char = a.Character
			duel.home[a] = char.HumanoidRootPart.CFrame
			setIn(a, a)
			char:PivotTo(CFrame.lookAt(c + Vector3.new(-38, 4, 0), c + Vector3.new(0, 4, 0)))
			char.HumanoidRootPart.Anchored = true
			remote:FireClient(a, "start", { opponent = a, fightAt = duel.fightAt, endsAt = duel.endsAt })
			task.delay(COUNTDOWN, function()
				char.HumanoidRootPart.Anchored = false
			end)
			return slot
		elseif cmd == "end" then
			local duel = duelOf[a]
			if duel then
				endDuel(duel, duel.a == a and duel.b or duel.a, a, b or "ko")
				return true
			end
			return false
		elseif cmd == "state" then
			local list = {}
			for p, d in pairs(duelOf) do
				list[#list + 1] = p.Name .. " in slot " .. d.slot .. (d.over and " (over)" or "")
			end
			return list
		end
		return nil
	end
	ctl.Parent = script
end
