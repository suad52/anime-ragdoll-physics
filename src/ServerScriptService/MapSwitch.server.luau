--!nocheck
-- ServerScriptService.MapSwitch (2026-11-14, owner: "add a button on the left that give people the option to switch
-- between maps"; then "make it to where the user starts off in the ruins map"): which map each player is on.
-- The MAPS tile (StarterPlayerScripts.MapMenu) fires ReplicatedStorage.MapSwitch(mapId).
--   Ruins   = workspace.Arenas.Ruins (ServerStorage.ArenaGen; SpawnLocations in Spawns)  <- everyone STARTS here
--   Sandbox = the open test ground (workspace.Map; SpawnLocations in Map.Spawn)
-- The choice is player attribute Map. Player.RespawnLocation always points at one of that map's SpawnLocations (a
-- different one each time), so a join or a respawn appears there directly - no hop from one map to the other.
-- A map may name a fighter (KIT): THE RUINS is Gojo's ("in the ruins, make it to where you're auto switched to gojo").
-- Arriving switches to it through VulpineServer.KitServer.ServerSetKit and keeps what they had in KitBeforeMap; going
-- to a map with no fighter of its own gives that back. On join it waits for ShopService to hand out the first fighter.
-- Studio: script.Control:Invoke("go", player, mapId)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local remote = ReplicatedStorage:WaitForChild("MapSwitch")

local DEFAULT_MAP = "Ruins"
local KIT = { Ruins = "Limitless" }

local function spawnsOf(mapId)
	local folder
	if mapId == "Ruins" then
		local arena = workspace:FindFirstChild("Arenas") and workspace.Arenas:FindFirstChild("Ruins")
		folder = arena and arena:FindFirstChild("Spawns")
	elseif mapId == "Sandbox" then
		folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Spawn")
	end
	local list = {}
	for _, d in ipairs(folder and folder:GetChildren() or {}) do
		if d:IsA("SpawnLocation") then
			table.insert(list, d)
		end
	end
	return list
end
local MAPS = { Ruins = true, Sandbox = true }
-- is this position on that map (else the character is put there by hand)
local function onMap(mapId, pos)
	if mapId == "Ruins" then
		local arena = workspace:FindFirstChild("Arenas") and workspace.Arenas:FindFirstChild("Ruins")
		local c, h = arena and arena:GetAttribute("Centre"), arena and arena:GetAttribute("Half")
		return c and h and math.abs(pos.X - c.X) < h + 20 and math.abs(pos.Z - c.Z) < h + 20
	end
	local map = workspace:FindFirstChild("Map")
	local fmin, fmax = map and map:GetAttribute("FieldMin"), map and map:GetAttribute("FieldMax")
	return fmin and fmax and pos.X > fmin.X - 20 and pos.X < fmax.X + 20 and pos.Z > fmin.Z - 20 and pos.Z < fmax.Z + 20
end

local turn = {}
local function aim(player, mapId)
	local list = spawnsOf(mapId)
	if #list == 0 then
		return nil
	end
	turn[player] = (turn[player] or math.random(#list)) % #list + 1
	local sp = list[turn[player]]
	player.RespawnLocation = sp
	return sp
end

local lastAt = {}
local function setKit(player, kitId)
	local ks = game:GetService("ServerScriptService"):FindFirstChild("VulpineServer")
	ks = ks and ks:FindFirstChild("KitServer")
	local f = ks and ks:FindFirstChild("ServerSetKit")
	if f then
		local ok, res = pcall(f.Invoke, f, player, kitId)
		return ok and res
	end
	player:SetAttribute("Kit", kitId)
	return true
end
local function applyKit(player, fromMap, toMap)
	local want = KIT[toMap]
	if want then
		if not KIT[fromMap] and player:GetAttribute("KitBeforeMap") == nil then
			player:SetAttribute("KitBeforeMap", player:GetAttribute("Kit") or "Normal")
		end
		setKit(player, want)
	elseif KIT[fromMap] then
		-- what they had before the map's fighter; someone who STARTED on this map had none, so the game's own
		-- default (ShopCatalog.KITS.DEFAULT, the weapons-only Normal) - not the map's fighter carried along
		local back = player:GetAttribute("KitBeforeMap")
		player:SetAttribute("KitBeforeMap", nil)
		if not back or back == "" then
			local ok, cat = pcall(function()
				return require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("ShopCatalog"))
			end)
			back = ok and cat.KITS and cat.KITS.DEFAULT or "Normal"
		end
		setKit(player, back)
	end
end

local function place(player, mapId)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	local sp = aim(player, mapId)
	if not sp then
		return false
	end
	-- let go of anything being carried first
	local main = game:GetService("ServerScriptService"):FindFirstChild("Sandbox")
	main = main and main:FindFirstChild("Main")
	local rg = main and main:FindFirstChild("ReleaseGrab")
	if rg then
		rg:Fire(player)
	end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local at = sp.Position + Vector3.new(0, 3.2, 0)
	char:PivotTo(CFrame.lookAt(at, at + sp.CFrame.LookVector * Vector3.new(1, 0, 1)))
	return true
end

local function go(player, mapId)
	if type(mapId) ~= "string" or not MAPS[mapId] then
		return false
	end
	local t = os.clock()
	if (lastAt[player] or 0) > t then
		return false
	end
	lastAt[player] = t + 1.5
	if place(player, mapId) then
		local from = player:GetAttribute("Map") or DEFAULT_MAP
		player:SetAttribute("Map", mapId)
		applyKit(player, from, mapId)
		return true
	end
	return false
end
remote.OnServerEvent:Connect(go)

local function hook(player)
	local mapId = player:GetAttribute("Map") or DEFAULT_MAP
	player:SetAttribute("Map", mapId)
	aim(player, mapId) -- before the first character loads: they appear on this map
	-- the map's fighter, once ShopService has given out the first one (it sets Kit right after KitsOwned)
	if KIT[mapId] then
		task.spawn(function()
			local t0 = os.clock()
			while player.Parent and player:GetAttribute("KitsOwned") == nil and os.clock() - t0 < 20 do
				task.wait(0.2)
			end
			task.wait(0.3)
			if player.Parent and player:GetAttribute("Map") == mapId and player:GetAttribute("Kit") ~= KIT[mapId] then
				applyKit(player, "Sandbox", mapId)
			end
		end)
	end
	player.CharacterAdded:Connect(function(char)
		local cur = player:GetAttribute("Map") or DEFAULT_MAP
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		aim(player, cur) -- the next respawn uses another pad of the same map
		task.wait(0.15)
		if player.Character ~= char or not hrp then
			return
		end
		if not onMap(cur, hrp.Position) then
			place(player, cur) -- (RespawnLocation did not take: put it there by hand)
		end
		if KIT[cur] and player:GetAttribute("KitsOwned") ~= nil and player:GetAttribute("Kit") ~= KIT[cur] then
			setKit(player, KIT[cur]) -- (respawned while on another fighter: the map's own again)
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end
Players.PlayerAdded:Connect(hook)
Players.PlayerRemoving:Connect(function(p)
	lastAt[p] = nil
	turn[p] = nil
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "go" then
			lastAt[a] = nil
			return go(a, b)
		end
	end
	ctl.Parent = script
end
