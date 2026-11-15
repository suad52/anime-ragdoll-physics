--!nocheck
-- ServerScriptService.PerkNuke (2026-11-14, sandbox shop): the NUKE (HudShared.PerkCatalog consumable "Nuke").
-- ShopService fires ServerStorage.PerkHooks.Nuke(player) once the purchase is saved. Nukes are QUEUED: one at a time,
-- the next one GAP s after the last detonation.
-- Timeline (server time; every client draws it from PerkShared.Remotes.Nuke "launch" - StarterPlayerScripts.PerkEventsClient):
--   t0              banner, siren, a red target on GROUND ZERO (a random spot near the middle of the map)
--   t0 + WARN - 3   the warhead appears high above it and falls
--   t0 + WARN       DETONATION: flash, fireball, mushroom cloud, and a shockwave that crosses the map at WAVE_SPEED.
-- As the wave reaches each thing (server side):
--   * dummies: blast + burn injuries (Sandbox.Injury / Hazards) scaled by distance - nothing inside about KILL_R lives -
--     thrown away from ground zero; kills are credited to the buyer while they are in the server
--   * explosive props (gas cans, fuel drums) go off; loose props and severed parts in workspace.Gore are thrown
--   * players: knocked flat (PerkFX "Knock") and DAMAGED by distance - PLAYER_DMG at ground zero, nothing past
--     PLAYER_R. Humanoid:TakeDamage, so GOD MODE (an invisible ForceField) and a big Health slider survive it.
-- Studio test hook: script.Control:Invoke("start", player?) | ("at", Vector3, player?) | ("stats").
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CFG = {
	WARN = 8, -- banner -> detonation
	FALL = 3, -- the warhead's fall (the last FALL s of WARN)
	GAP = 12, -- between queued nukes (after the detonation)
	CENTER_R = 140, -- ground zero is picked within this of the map's middle
	WAVE_SPEED = 230, -- studs/s
	R = 640, -- the wave's reach (every corner of the 720-stud map is inside it)
	KILL_R = 120, -- dummies inside this burn as well
	DUMMY_POWER = 420, -- blast injury at ground zero (falls off with distance)
	PLAYER_R = 420,
	PLAYER_DMG = 1400, -- at ground zero; x (1 - d / PLAYER_R)^1.3
	FLING = 230, -- body throw speed at ground zero (+ a base)
	PLAYER_KNOCK = 140,
}

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
local NukeRemote = remote("Nuke")
local PerkFX = remote("PerkFX")
local Announce = remote("Announce")

-- the sandbox's modules (the same instances Sandbox.Main set up); nil if this place has no sandbox
local Sandbox = ServerScriptService:WaitForChild("Sandbox", 30)
local function mod(name)
	local m = Sandbox and Sandbox:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, r = pcall(require, m)
	return ok and type(r) == "table" and r or nil
end
local Injury, Hazards = mod("Injury"), mod("Hazards")
local RagdollService
do
	local g = ServerScriptService:FindFirstChild("GojoServer")
	local m = g and g:FindFirstChild("RagdollService")
	if m then
		local ok, r = pcall(require, m)
		RagdollService = ok and r or nil
	end
end

local NPC_TAG = "RagdollNPC"
pcall(function()
	local cfg = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC"))
	if type(cfg.Tag) == "string" then
		NPC_TAG = cfg.Tag
	end
end)

local UP = Vector3.yAxis
local rng = Random.new()

local function flatOut(off)
	local f = Vector3.new(off.X, 0, off.Z)
	if f.Magnitude < 0.5 then
		local a = rng:NextNumber() * math.pi * 2
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return f.Unit
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = true
local function groundAt(x, z)
	local list = {}
	for _, n in ipairs({ "NPCs", "Gore", "FX", "PerkFXLocal" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	local map = workspace:FindFirstChild("Map")
	local b = map and map:FindFirstChild("Bounds")
	if b then
		table.insert(list, b)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(x, 380, z), Vector3.new(0, -500, 0), groundParams)
	return hit and hit.Position or Vector3.new(x, 1, z)
end

---------------------------------------------------------------------------------------------------------------------
-- the wave
local function hitDummy(m, gz, d, by)
	if not m.Parent or m:GetAttribute("Retired") then
		return
	end
	local torso = m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
	if not torso then
		return
	end
	local k = 1 - math.clamp(d / CFG.R, 0, 1)
	local off = torso.Position - gz
	local dir = off.Magnitude > 0.1 and off.Unit or UP
	if by then
		m:SetAttribute("LastHitBy", by.UserId)
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if Injury then
		-- the blast lands on the side facing ground zero (centre 4 studs out that way: the near parts take most of it)
		local best = Injury.blast(m, torso.Position - dir * 4, 12, 30 + CFG.DUMMY_POWER * k ^ 1.4, by)
		if hum and hum.Health > 0 then
			hum:TakeDamage(best * 1.1)
		end
		if d < CFG.KILL_R and Hazards and Hazards.hurt then
			Hazards.hurt(m, torso, "burn", 140, by, dir, torso.Position)
		end
	elseif hum and hum.Health > 0 then
		hum:TakeDamage(400 * k ^ 1.4)
	end
	if RagdollService and not m:GetAttribute("GrabbedBy") then
		local vel = (flatOut(off) + UP * (0.55 + 0.5 * k)).Unit * (50 + CFG.FLING * k)
		pcall(RagdollService.Fling, m, vel, nil, 3.5)
		if RagdollService.LendNearest then
			pcall(RagdollService.LendNearest, m, 140)
		end
	end
end

local function hitPlayer(p, gz, d)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return
	end
	local k = 1 - math.clamp(d / CFG.R, 0, 1)
	local vel = (flatOut(hrp.Position - gz) + UP * (0.6 + 0.4 * k)).Unit * (40 + CFG.PLAYER_KNOCK * k)
	if char:GetAttribute("Morphed") then
		vel *= 0.2 -- giants barely budge
	end
	PerkFX:FireClient(p, "Knock", vel, 1 + 1.5 * k)
	if d < CFG.PLAYER_R then
		local dmg = CFG.PLAYER_DMG * (1 - d / CFG.PLAYER_R) ^ 1.3
		if dmg >= 1 then
			hum:TakeDamage(dmg) -- nothing through a ForceField (God Mode)
		end
	end
end

local function hitProps(gz, by, t0)
	for _, p in ipairs(CollectionService:GetTagged("Explosive")) do
		if p:IsA("BasePart") and p.Parent and not p:GetAttribute("Boom") then
			local d = (p.Position - gz).Magnitude
			if d < CFG.R then
				task.delay(math.max(0, t0 + d / CFG.WAVE_SPEED - os.clock()) + rng:NextNumber(0, 0.3), function()
					if p.Parent and Hazards and Hazards.explode then
						pcall(Hazards.explode, p, by)
					end
				end)
			end
		end
	end
	local gore = workspace:FindFirstChild("Gore")
	if gore then
		for _, p in ipairs(gore:GetDescendants()) do
			if p:IsA("BasePart") and not p.Anchored and p.Parent and not CollectionService:HasTag(p, "Explosive") then
				local off = p.Position - gz
				local d = off.Magnitude
				if d < CFG.R then
					local k = 1 - d / CFG.R
					task.delay(math.max(0, t0 + d / CFG.WAVE_SPEED - os.clock()), function()
						if p.Parent and not p.Anchored then
							pcall(function()
								p.AssemblyLinearVelocity = (flatOut(off) + UP * 0.8).Unit * (40 + 200 * k)
							end)
						end
					end)
				end
			end
		end
	end
end

local function detonate(gz, entry)
	local by = entry.player and entry.player.Parent == Players and entry.player or nil
	local t0 = os.clock()
	if Hazards and Hazards.onBlast then
		pcall(Hazards.onBlast, gz, 300, by) -- the wanderers hear it
	end
	local gojo = ServerScriptService:FindFirstChild("GojoServer")
	local threat = gojo and gojo:FindFirstChild("Threat")
	if threat and threat:IsA("BindableEvent") then
		threat:Fire(gz, 400, 4)
	end
	-- everything inside the reach, in the order the wave meets it
	local jobs = {}
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		local torso = m:IsA("Model") and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart"))
		if torso and not m:GetAttribute("InDomain") then
			local d = (torso.Position - gz).Magnitude
			if d < CFG.R then
				table.insert(jobs, { d = d, fn = hitDummy, a = m })
			end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - gz).Magnitude
			if d < CFG.R then
				table.insert(jobs, { d = d, fn = hitPlayer, a = p })
			end
		end
	end
	table.sort(jobs, function(x, y)
		return x.d < y.d
	end)
	hitProps(gz, by, t0)
	for _, j in ipairs(jobs) do
		local due = t0 + j.d / CFG.WAVE_SPEED
		if due > os.clock() then
			task.wait(due - os.clock())
		end
		local ok, err = pcall(j.fn, j.a, gz, j.d, by)
		if not ok then
			warn("[PerkNuke] " .. tostring(err))
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- queue
local queue, running, launched = {}, false, 0

local function run(entry)
	local gz = entry.at
	if typeof(gz) ~= "Vector3" then
		local a, r = rng:NextNumber() * math.pi * 2, math.sqrt(rng:NextNumber()) * CFG.CENTER_R
		gz = groundAt(math.cos(a) * r, math.sin(a) * r)
	end
	launched += 1
	local now = workspace:GetServerTimeNow()
	NukeRemote:FireAllClients("launch", { id = launched, gz = gz, t0 = now, boom = now + CFG.WARN, fall = CFG.FALL, by = entry.name,
		wave = CFG.WAVE_SPEED, r = CFG.R })
	Announce:FireAllClients({ kind = "Nuke", title = string.upper(entry.name) .. " LAUNCHED A NUKE!", sub = "TAKE COVER - IMPACT IN " .. CFG.WARN .. " SECONDS",
		time = 4.5, color = Color3.fromRGB(255, 70, 40), accent = Color3.fromRGB(255, 235, 90) })
	workspace:SetAttribute("NukeAt", now + CFG.WARN)
	task.wait(CFG.WARN)
	detonate(gz, entry)
end

local function pump()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local entry = table.remove(queue, 1)
			local ok, err = pcall(run, entry)
			if not ok then
				warn("[PerkNuke] nuke failed: " .. tostring(err))
			end
			if #queue > 0 then
				task.wait(CFG.GAP)
			end
		end
		running = false
	end)
end

local function request(player, at)
	local entry
	if typeof(player) == "Instance" and player:IsA("Player") then
		entry = { name = player.DisplayName, player = player, at = at }
	else
		entry = { name = "SOMEONE", at = at }
	end
	if running then
		Announce:FireAllClients({ kind = "Nuke", title = string.upper(entry.name) .. " LAUNCHED A NUKE!",
			sub = "#" .. (#queue + 1) .. " IN LINE - IT FALLS RIGHT AFTER THIS ONE", time = 4,
			color = Color3.fromRGB(255, 70, 40), accent = Color3.fromRGB(255, 235, 90) })
	end
	table.insert(queue, entry)
	pump()
end

local hooks = ServerStorage:WaitForChild("PerkHooks", 30)
local hook = hooks and hooks:WaitForChild("Nuke", 30)
if hook then
	hook.Event:Connect(function(p)
		request(p)
	end)
else
	warn("[PerkNuke] ServerStorage.PerkHooks.Nuke missing - nukes can only be started from Control")
end

local ctl = script:FindFirstChild("Control") or Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, a, b)
	if cmd == "start" then
		request(a or Players:GetPlayers()[1])
		return true
	elseif cmd == "at" then
		request(b or Players:GetPlayers()[1], typeof(a) == "Vector3" and a or nil)
		return true
	elseif cmd == "stats" then
		return { running = running, queued = #queue, launched = launched }
	end
	return nil
end
ctl.Parent = script
