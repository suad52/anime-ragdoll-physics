--!nocheck
-- ServerScriptService.PerkMeteorShower (owner: fx, perks 2026-11-07): the server-wide Meteor Shower (PerkCatalog
-- consumable "Meteor"). ShopService fires ServerStorage.PerkHooks.MeteorShower(player) after the purchase is saved.
-- Showers are QUEUED: one at a time, the next starts GAP s after the last one ends.
-- A shower: a banner on every client (PerkShared.Remotes.Announce), LEAD s of warning, then COUNT meteors over
-- DURATION s, all from one sky direction, aimed near living players, at the scramble crossing (the origin) and across
-- the city core; every 8th one and the finale (at the crossing) are BIG. Each impact, on the server:
--   * GojoServer.WorldBlast(pos, r, uid) + BreakBlast(pos, r, travelDir, speed, uid): the real city destruction
--     (glass, panels, props, holes in walls, and a street crater with a molten core for r >= 18 - CityDestruction)
--   * GojoServer.Threat at the IMPACT (never at launch) so the crowd flees
--   * NPC bodies in reach: damaged (credited to the buyer while they are in the server) and flung ragdolls
--   * players in reach: knocked - PerkFX:FireClient(p, "Knock", vel, ragTime) - and never damaged
-- Clients draw the meteors from PerkFX:FireAllClients("Meteor", { id, a, b, n, t0, d, s, r, big }) on server time,
-- and tint the sky while PerkFX's attribute MeteorUntil (server time) is in the future.
-- SANDBOX (2026-11-14, sandbox shop): with no workspace.City (the ragdoll sandbox) the shower is aimed at the sandbox map
-- (720 studs across, walls at +-352): targets inside +-EDGE, the "crossing" is the middle of the map, the invisible edge
-- walls (Map.Bounds) never stop a meteor, and an impact hurts dummies through the sandbox's own blast (Sandbox.Hazards:
-- burns, broken bones, chain-reacting gas cans) instead of plain damage.
-- Studio test hook: script.Control:Invoke("start", player?) | ("meteor", pos?, big?) | ("stop") | ("stats").
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CFG = {
	DURATION = 20, -- seconds of meteors
	COUNT = 40,
	LEAD = 2.5, -- banner -> first meteor
	GAP = 3, -- between queued showers
	HEIGHT = 300, -- launch height above the target...
	CEILING = 520, -- ...and never below this altitude (the tallest solid roof is ~344: a meteor must not pop in
	-- just over a tower and land 0.2 s later)
	TILT = 30, -- degrees from vertical (+-6 per meteor), every meteor of a shower from the same side of the sky
	SPEED = 270, -- studs/s along the path (~2.2 s of flight; ~0.8 s when a tower top is in the way)
	RADIUS_MIN = 15, -- blast radius of a normal meteor (CityDestruction: >= 18 leaves a molten crater core)
	RADIUS_MAX = 20,
	SIZE_MIN = 5.5, -- rock diameter
	SIZE_MAX = 8,
	BIG_EVERY = 8,
	BIG_RADIUS = 28,
	BIG_SIZE = 15,
	-- where they land
	NEAR_PLAYER = 0.5, -- share aimed near a living player...
	PLAYER_MIN = 10, -- ...this far from them...
	PLAYER_MAX = 60,
	CROSSING = 0.32, -- ...share on the scramble crossing (origin)...
	CROSSING_R = 110,
	CITY_R = 380, -- ...the rest anywhere in the core
	EDGE = 700, -- targets are kept inside +-EDGE (the boundary walls stand at +-804)
	-- what an impact does to bodies
	NPC_REACH = 1.6, -- x radius
	NPC_DAMAGE = 130, -- at the centre; x (0.3 + 0.7 k) - kills within about a third of the reach
	NPC_FLING = 150,
	NPC_RAG = 2.6,
	PLAYER_REACH = 1.8,
	PLAYER_FLING = 95, -- knock speed at the centre (no damage)
	PLAYER_RAG = 1.4,
	BREAK_SPEED = 130,
}

local SANDBOX = workspace:FindFirstChild("City") == nil
if SANDBOX then
	CFG.EDGE = 325
	CFG.CITY_R = 320
	CFG.CROSSING = 0.25
	CFG.CROSSING_R = 130
	CFG.HEIGHT = 260
	CFG.CEILING = 420
	CFG.PLAYER_MIN = 14
end
-- the sandbox's blast (lazy: Sandbox.Main sets the module up)
local SandboxHazards = nil
local function sandboxHazards()
	if SandboxHazards == nil then
		SandboxHazards = false
		local sb = ServerScriptService:FindFirstChild("Sandbox")
		local m = sb and sb:FindFirstChild("Hazards")
		if m then
			local ok, r = pcall(require, m)
			if ok and type(r) == "table" and r.blastAt then
				SandboxHazards = r
			end
		end
	end
	return SandboxHazards or nil
end

local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")
local function remote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local PerkFX = remote("PerkFX")
local Announce = remote("Announce")
PerkFX:SetAttribute("MeteorUntil", 0)

local gojo = ServerScriptService:WaitForChild("GojoServer", 30)
local RagdollService
do
	local m = gojo and gojo:FindFirstChild("RagdollService")
	if m then
		local ok, res = pcall(require, m)
		if ok and type(res) == "table" then
			RagdollService = res
			pcall(res.Init)
		end
	end
end

local NPC_TAG = "RagdollNPC"
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC"))
	end)
	if ok and type(cfg) == "table" and type(cfg.Tag) == "string" then
		NPC_TAG = cfg.Tag
	end
end

-- GojoServer.<name> looked up per call (BreakBlast is created by CityDestruction at run time)
local function hook(name, ...)
	local b = gojo and gojo:FindFirstChild(name)
	if b and b:IsA("BindableEvent") then
		b:Fire(...)
	end
end

local UP = Vector3.yAxis
local TAU = math.pi * 2

local function rand(a, b)
	return a + math.random() * (b - a)
end

local function randomFlat()
	local a = math.random() * TAU
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function liveRoot(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- aiming
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true -- signs, glow strips and effects never stop a meteor

local function refreshFilter()
	local list = {}
	for _, n in ipairs({ "NPCs", "CityDebris", "KitDebris", "KitFX", "FX", "Gore" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	local arena = workspace:FindFirstChild("Arena")
	local bounds = arena and arena:FindFirstChild("ArenaBounds")
	if bounds then
		table.insert(list, bounds)
	end
	local city = workspace:FindFirstChild("City")
	local out = city and city:FindFirstChild("Outskirts")
	local wall = out and out:FindFirstChild("Boundary") -- the invisible edge walls (+-804, 1040 tall)
	if wall then
		table.insert(list, wall)
	end
	local map = workspace:FindFirstChild("Map")
	local bounds = map and map:FindFirstChild("Bounds") -- (2026-11-14) the sandbox's invisible edge walls
	if bounds then
		table.insert(list, bounds)
	end
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		table.insert(list, m)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function clampXZ(x, z)
	return math.clamp(x, -CFG.EDGE, CFG.EDGE), math.clamp(z, -CFG.EDGE, CFG.EDGE)
end

local function pickXZ(big, finale)
	if finale then
		local a, d = math.random() * TAU, math.random() * 30
		return math.cos(a) * d, math.sin(a) * d
	end
	local roots = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local _, _, hrp = liveRoot(p)
		if hrp then
			table.insert(roots, hrp.Position)
		end
	end
	local r = math.random()
	if #roots > 0 and r < (big and 0.4 or CFG.NEAR_PLAYER) then
		local at = roots[math.random(#roots)]
		local a, d = math.random() * TAU, rand(CFG.PLAYER_MIN, CFG.PLAYER_MAX) * (big and 1.4 or 1)
		return clampXZ(at.X + math.cos(a) * d, at.Z + math.sin(a) * d)
	elseif r < CFG.NEAR_PLAYER + CFG.CROSSING or #roots == 0 and r < 0.7 then
		local a, d = math.random() * TAU, math.sqrt(math.random()) * CFG.CROSSING_R
		return math.cos(a) * d, math.sin(a) * d
	end
	local a, d = math.random() * TAU, math.sqrt(math.random()) * CFG.CITY_R
	return clampXZ(math.cos(a) * d, math.sin(a) * d)
end

-- the first solid thing under (x, z): (point, normal)
local function groundAt(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 700, z), Vector3.new(0, -760, 0), rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return Vector3.new(x, 2, z), UP
end

---------------------------------------------------------------------------------------------------
-- impact
local function impact(pos, radius, dir, uid, credit)
	hook("WorldBlast", pos, radius, uid)
	hook("BreakBlast", pos, radius, dir, CFG.BREAK_SPEED, uid)
	hook("Threat", pos, radius * 2.5, 2.5)

	local reach = radius * CFG.NPC_REACH
	local H = SANDBOX and sandboxHazards()
	if H then
		-- (2026-11-14) the sandbox's own blast: injuries by distance, a throw, chain-reacting explosive props, kill credit
		local by = credit and credit.Parent == Players and credit or nil
		local ok, err = pcall(H.blastAt, pos, reach, radius >= CFG.BIG_RADIUS and 200 or CFG.NPC_DAMAGE, by, true)
		if not ok then
			warn("[PerkMeteorShower] sandbox blast failed: " .. tostring(err))
		end
		if H.onBlast then
			pcall(H.onBlast, pos, radius * 2.5, by)
		end
	end
	for _, m in ipairs(H and {} or CollectionService:GetTagged(NPC_TAG)) do
		if m.Parent and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("InDomain") then
			local root = m:FindFirstChild("LowerTorso") or m:FindFirstChild("HumanoidRootPart")
			if root then
				local off = root.Position - pos
				local d = off.Magnitude
				if d <= reach then
					local k = 1 - d / reach
					local hum = m:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						if credit and credit.Parent == Players then
							m:SetAttribute("LastHitBy", uid) -- the KO (and its Yen) goes to the buyer
						end
						hum:TakeDamage(CFG.NPC_DAMAGE * (0.3 + 0.7 * k))
					end
					local flat = Vector3.new(off.X, 0, off.Z)
					local out = flat.Magnitude > 0.5 and flat.Unit or randomFlat()
					local vel = (out + UP * (0.8 + 0.5 * k)).Unit * CFG.NPC_FLING * (0.45 + 0.55 * k)
					if RagdollService then
						pcall(RagdollService.Fling, m, vel, nil, CFG.NPC_RAG)
					end
				end
			end
		end
	end

	local preach = radius * CFG.PLAYER_REACH
	for _, p in ipairs(Players:GetPlayers()) do
		local char, _, hrp = liveRoot(p)
		if hrp then
			local off = hrp.Position - pos
			local d = off.Magnitude
			if d <= preach then
				local k = 1 - d / preach
				local flat = Vector3.new(off.X, 0, off.Z)
				local out = flat.Magnitude > 0.5 and flat.Unit or randomFlat()
				local vel = (out + UP * (1 + 0.4 * k)).Unit * CFG.PLAYER_FLING * (0.4 + 0.6 * k)
				if char:GetAttribute("Morphed") then
					vel *= 0.15 -- giants barely budge
				end
				PerkFX:FireClient(p, "Knock", vel, CFG.PLAYER_RAG * (0.5 + 0.5 * k))
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- one meteor
local meteorId = 0
local launched = 0

local function launch(entry, opts)
	opts = opts or {}
	local big = opts.big == true
	refreshFilter()
	local g, gn
	if typeof(opts.at) == "Vector3" then
		g, gn = groundAt(opts.at.X, opts.at.Z)
	else
		g, gn = groundAt(pickXZ(big, opts.finale))
	end
	local az = (entry.az or math.random() * TAU) + rand(-0.35, 0.35)
	local back = Vector3.new(math.cos(az), 0, math.sin(az))
	local tilt = math.rad(CFG.TILT + rand(-6, 6))
	local h = math.max(CFG.HEIGHT, CFG.CEILING - g.Y)
	local from = g + UP * h + back * h * math.tan(tilt)
	local path = g - from
	local b, n = g, gn
	local hit = workspace:Raycast(from, path + path.Unit * 4, rayParams)
	if hit then
		b, n = hit.Position, hit.Normal -- a tower in the way takes it on its facade
	end
	local dist = (b - from).Magnitude
	if dist < 5 then
		return
	end
	local dir = (b - from).Unit
	-- the debris throw: out of the struck surface (up off a street, back out of a facade) and on along the flight
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	local breakDir = n + (flatDir.Magnitude > 1e-3 and flatDir.Unit * 0.5 or Vector3.zero)
	breakDir = breakDir.Magnitude > 1e-3 and breakDir.Unit or UP
	local dur = dist / CFG.SPEED
	local radius = big and CFG.BIG_RADIUS or rand(CFG.RADIUS_MIN, CFG.RADIUS_MAX)
	local size = big and CFG.BIG_SIZE or rand(CFG.SIZE_MIN, CFG.SIZE_MAX)
	meteorId += 1
	launched += 1
	PerkFX:FireAllClients("Meteor", {
		id = meteorId, a = from, b = b, n = n, t0 = workspace:GetServerTimeNow(), d = dur, s = size, r = radius, big = big,
	})
	local uid, credit = entry.uid or 0, entry.player
	task.delay(dur, function()
		local ok, err = pcall(impact, b, radius, breakDir, uid, credit)
		if not ok then
			warn("[PerkMeteorShower] impact failed: " .. tostring(err))
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- showers + queue
local queue = {}
local running = false
local stopFlag = false
local current = nil

local function banner(title, sub, time)
	Announce:FireAllClients({
		kind = "Meteor", title = title, sub = sub, time = time or 5,
		color = Color3.fromRGB(255, 120, 40), accent = Color3.fromRGB(255, 220, 90),
	})
end

local function runShower(entry)
	current = entry
	stopFlag = false
	entry.az = math.random() * TAU
	PerkFX:SetAttribute("MeteorBy", entry.name)
	PerkFX:SetAttribute("MeteorUntil", workspace:GetServerTimeNow() + CFG.LEAD + CFG.DURATION + 3)
	banner(string.upper(entry.name) .. " CALLED A METEOR SHOWER!", "TAKE COVER!", 5)
	task.wait(CFG.LEAD)
	local t0 = os.clock()
	for i = 1, CFG.COUNT do
		if stopFlag then
			break
		end
		local finale = i == CFG.COUNT
		local ok, err = pcall(launch, entry, { big = finale or i % CFG.BIG_EVERY == 0, finale = finale })
		if not ok then
			warn("[PerkMeteorShower] launch failed: " .. tostring(err))
		end
		local due = t0 + CFG.DURATION * i / CFG.COUNT + rand(-0.15, 0.15)
		task.wait(math.max(0.05, due - os.clock()))
	end
	task.wait(2.5) -- the last ones land
	PerkFX:SetAttribute("MeteorUntil", 0)
	current = nil
end

local function pump()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local entry = table.remove(queue, 1)
			local ok, err = pcall(runShower, entry)
			if not ok then
				warn("[PerkMeteorShower] shower failed: " .. tostring(err))
				PerkFX:SetAttribute("MeteorUntil", 0)
				current = nil
			end
			if #queue > 0 then
				task.wait(CFG.GAP)
			end
		end
		running = false
	end)
end

local function request(player)
	local entry
	if typeof(player) == "Instance" and player:IsA("Player") then
		entry = { uid = player.UserId, name = player.DisplayName, player = player }
	else
		entry = { uid = 0, name = "SOMEONE", player = nil }
	end
	if running then
		banner(string.upper(entry.name) .. " CALLED A METEOR SHOWER!",
			"#" .. tostring(#queue + 1) .. " IN LINE - IT FALLS RIGHT AFTER THIS ONE", 4)
	end
	table.insert(queue, entry)
	pump()
end

local hooks = ServerStorage:WaitForChild("PerkHooks", 30)
local meteorHook = hooks and hooks:WaitForChild("MeteorShower", 30)
if meteorHook then
	meteorHook.Event:Connect(request)
else
	warn("[PerkMeteorShower] ServerStorage.PerkHooks.MeteorShower missing - showers can only be started from Control")
end

-- Studio / playtest hook (server only)
local ctl = script:FindFirstChild("Control")
if not ctl then
	ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.Parent = script
end
ctl.OnInvoke = function(cmd, a, b)
	if cmd == "start" then
		request(a or Players:GetPlayers()[1])
		return true
	elseif cmd == "meteor" then -- one meteor at pos (default: 25 studs in front of the first player)
		local pos = typeof(a) == "Vector3" and a or nil
		local p = Players:GetPlayers()[1]
		if not pos and p then
			local _, _, hrp = liveRoot(p)
			pos = hrp and hrp.Position + hrp.CFrame.LookVector * 25
		end
		local entry = { uid = p and p.UserId or 0, name = p and p.DisplayName or "TEST", player = p }
		launch(entry, { big = b == true, at = pos or Vector3.zero })
		return true
	elseif cmd == "stop" then
		stopFlag = true
		table.clear(queue)
		return true
	elseif cmd == "stats" then
		return { running = running, queued = #queue, launched = launched, current = current and current.name or nil }
	end
	return nil
end

print("[PerkMeteorShower] online")
