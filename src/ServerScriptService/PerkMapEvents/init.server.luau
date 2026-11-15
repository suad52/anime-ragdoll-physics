--!nocheck
-- ServerScriptService.PerkMapEvents (2026-11-15, owner: "Make the events as its own section here, and add all the events
-- you mentioned"): the server events of the shop's EVENTS tab that came after Nuke / Meteor Shower / Moon Gravity /
-- Dummy Rain:  Tornado | Earthquake | BlackHole | Flood | IceWorld | Zombies | BossDummy | ChaosBundle.
-- ShopService fires ServerStorage.PerkHooks.<hook>(player) once a purchase is saved (HudShared.PerkCatalog item `hook`).
-- Every one happens on the BUYER'S MAP: player attribute Map ("Ruins" = workspace.Arenas.Ruins, "Sandbox" =
-- workspace.Map), else wherever they stand. Each event's behaviour is a ModuleScript child of this script:
--   return function(ctx, ev)   -- runs (yielding) until the event is over; ev.stop = true asks it to end early
-- This script is the shared ctx, the queue / stacking rules (POLICY) and the MARKER every client draws from:
--   workspace.MapEvents.<Kind>_<id>: an invisible anchored Part at the event's focus. Attributes: Kind, Id, Area, By (a
--   display name), T0 / Ends (server time; Ends grows when the same event is bought again), AreaC / AreaH (the map's
--   centre and half size) and whatever the module adds (Radius, Level, ...).
-- One-shot effects go out on PerkShared.Remotes.MapEventFX:FireAllClients(kind, data). Players are client-owned, so a
-- push on a player is either a PerkFX "Knock" from here or done by StarterPlayerScripts.PerkMapEventsClient itself.
-- Studio: script.Control:Invoke("start", kind, player?) | ("stop", kind?) | ("stats").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local KINDS = { "Tornado", "Earthquake", "BlackHole", "Flood", "IceWorld", "Zombies", "BossDummy", "ChaosBundle" }
-- max = how many of the kind may run at once (more wait in line); extend = buying it again while it runs on the same
-- map adds this many seconds instead (never more than cap seconds ahead)
local POLICY = {
	Tornado = { max = 3 },
	Earthquake = { extend = 20, cap = 60 },
	BlackHole = { max = 1 },
	Flood = { extend = 30, cap = 150 },
	IceWorld = { extend = 60, cap = 180 },
	Zombies = { max = 3 },
	BossDummy = { max = 1 },
	ChaosBundle = { max = 1 },
}
local TITLE = {
	Tornado = { "SUMMONED A TORNADO!", "HOLD ON TO SOMETHING", Color3.fromRGB(150, 170, 190), Color3.fromRGB(235, 240, 250) },
	Earthquake = { "STARTED AN EARTHQUAKE!", "THE GROUND IS SPLITTING OPEN", Color3.fromRGB(190, 120, 60), Color3.fromRGB(255, 220, 160) },
	BlackHole = { "OPENED A BLACK HOLE!", "DON'T GET PULLED IN", Color3.fromRGB(120, 60, 220), Color3.fromRGB(255, 160, 255) },
	Flood = { "FLOODED THE MAP!", "GET TO HIGH GROUND", Color3.fromRGB(40, 120, 220), Color3.fromRGB(170, 225, 255) },
	IceWorld = { "FROZE THE WORLD!", "NOBODY CAN STOP SLIDING", Color3.fromRGB(110, 190, 255), Color3.fromRGB(235, 250, 255) },
	Zombies = { "RAISED THE DEAD!", "ZOMBIE DUMMIES ARE CLIMBING OUT", Color3.fromRGB(90, 170, 70), Color3.fromRGB(210, 255, 170) },
	BossDummy = { "SUMMONED A GIANT BOSS!", "TEAM UP AND TAKE IT DOWN", Color3.fromRGB(220, 40, 50), Color3.fromRGB(255, 210, 90) },
	ChaosBundle = { "UNLEASHED THE CHAOS BUNDLE!", "3 NUKES + 5 METEOR SHOWERS INCOMING", Color3.fromRGB(255, 70, 40), Color3.fromRGB(255, 235, 90) },
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
local FX = remote("MapEventFX")
local PerkFX = remote("PerkFX")
local Announce = remote("Announce")

-- the sandbox's modules (the same instances Sandbox.Main set up)
local Sandbox = ServerScriptService:WaitForChild("Sandbox", 30)
local function mod(name)
	local m = Sandbox and Sandbox:FindFirstChild(name)
	if not m then
		return nil
	end
	local ok, r = pcall(require, m)
	return ok and type(r) == "table" and r or nil
end
local Injury, Hazards, Dummies = mod("Injury"), mod("Hazards"), mod("Dummies")
local Ragdoll
do
	local g = ServerScriptService:FindFirstChild("GojoServer")
	local m = g and g:FindFirstChild("RagdollService")
	if m then
		local ok, r = pcall(require, m)
		Ragdoll = ok and r or nil
	end
end

local folder = workspace:FindFirstChild("MapEvents")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "MapEvents"
	folder.Parent = workspace
end

---------------------------------------------------------------------------------------------------------------------
-- ctx: what every event module gets
local ctx = { Injury = Injury, Hazards = Hazards, Dummies = Dummies, Ragdoll = Ragdoll, folder = folder, FX = FX }
local rng = Random.new()
ctx.rng = rng
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
ctx.UP, ctx.FLAT = UP, FLAT

function ctx.now()
	return workspace:GetServerTimeNow()
end

-- the two maps: { id, c = centre (y 0), h = half size (y 0) }
local function sandboxArea()
	local map = workspace:FindFirstChild("Map")
	local fmin = map and map:GetAttribute("FieldMin") or Vector3.new(-264, 0, -296)
	local fmax = map and map:GetAttribute("FieldMax") or Vector3.new(308, 0, 340)
	return { id = "Sandbox", c = Vector3.new((fmin.X + fmax.X) / 2, 0, (fmin.Z + fmax.Z) / 2), h = Vector3.new((fmax.X - fmin.X) / 2, 0, (fmax.Z - fmin.Z) / 2) }
end
local function ruinsArea()
	local ar = workspace:FindFirstChild("Arenas") and workspace.Arenas:FindFirstChild("Ruins")
	local c, h = ar and ar:GetAttribute("Centre"), ar and ar:GetAttribute("Half")
	if not c or not h then
		return nil
	end
	return { id = "Ruins", c = Vector3.new(c.X, 0, c.Z), h = Vector3.new(h, 0, h) }
end
function ctx.inArea(A, pos, margin)
	margin = margin or 0
	return math.abs(pos.X - A.c.X) <= A.h.X + margin and math.abs(pos.Z - A.c.Z) <= A.h.Z + margin
end
function ctx.areaById(id)
	if id == "Ruins" then
		return ruinsArea() or sandboxArea()
	end
	return sandboxArea()
end
function ctx.areaOf(p)
	local hrp = typeof(p) == "Instance" and p:IsA("Player") and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local ruins = ruinsArea()
	if hrp and ruins and ctx.inArea(ruins, hrp.Position, 60) then
		return ruins
	end
	if hrp then
		return sandboxArea()
	end
	local want = typeof(p) == "Instance" and p:IsA("Player") and p:GetAttribute("Map")
	return ctx.areaById(want)
end

-- the ground under (x, z): terrain and map geometry only (no bodies, props or effects)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
groundParams.IgnoreWater = true
function ctx.groundIgnore()
	local list = { folder }
	for _, n in ipairs({ "NPCs", "Gore", "FX", "PerkFXLocal", "GadgetFX", "MapEventsFX", "Arrows" }) do
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
	return list
end
function ctx.ground(x, z, fromY)
	groundParams.FilterDescendantsInstances = ctx.groundIgnore()
	local hit = workspace:Raycast(Vector3.new(x, fromY or 380, z), Vector3.new(0, -((fromY or 380) + 120), 0), groundParams)
	return hit and hit.Position or Vector3.new(x, 0, z), hit
end
function ctx.randomPoint(A, margin)
	margin = margin or 20
	local x = A.c.X + rng:NextNumber(-1, 1) * math.max(A.h.X - margin, 5)
	local z = A.c.Z + rng:NextNumber(-1, 1) * math.max(A.h.Z - margin, 5)
	return ctx.ground(x, z)
end
-- a point `minD`..`maxD` from `pos` (flat), inside the map
function ctx.pointNear(pos, minD, maxD, A, margin)
	if typeof(pos) ~= "Vector3" then
		return nil
	end
	for _ = 1, 12 do
		local a = rng:NextNumber() * math.pi * 2
		local d = rng:NextNumber(minD, maxD)
		local p = pos + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
		if ctx.inArea(A, p, -(margin or 20)) then
			return ctx.ground(p.X, p.Z)
		end
	end
	return nil
end
function ctx.clampIn(A, p, margin)
	margin = margin or 15
	return Vector3.new(math.clamp(p.X, A.c.X - A.h.X + margin, A.c.X + A.h.X - margin), p.Y, math.clamp(p.Z, A.c.Z - A.h.Z + margin, A.c.Z + A.h.Z - margin))
end

function ctx.torso(m)
	return m:FindFirstChild("UpperTorso") or m:FindFirstChild("LowerTorso") or m:FindFirstChild("HumanoidRootPart")
end
-- every dummy body (alive or dead) whose torso is on that map
function ctx.dummies(A, margin)
	local list = {}
	if not Dummies then
		return list
	end
	for m in pairs(Dummies.records) do
		local t = m.Parent and ctx.torso(m)
		if t and ctx.inArea(A, t.Position, margin or 40) and not m:GetAttribute("InDomain") then
			table.insert(list, m)
		end
	end
	return list
end
function ctx.alive(m)
	local rec = Dummies and Dummies.records[m]
	local hum = m:FindFirstChildOfClass("Humanoid")
	return rec ~= nil and not rec.dead and hum ~= nil and hum.Health > 0 and m:GetAttribute("Dead") ~= true
end
-- loose props and scraps (gas cans, fuel drums, crates, severed parts) on that map
function ctx.props(A)
	local list = {}
	local gore = workspace:FindFirstChild("Gore")
	for _, p in ipairs(gore and gore:GetChildren() or {}) do
		if p:IsA("BasePart") and not p.Anchored and ctx.inArea(A, p.Position, 30) then
			table.insert(list, p)
		elseif p:IsA("Model") then
			local pp = p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart")
			if pp and not pp.Anchored and ctx.inArea(A, pp.Position, 30) then
				table.insert(list, pp)
			end
		end
	end
	return list
end
-- living players standing on that map: { player, hrp, hum }
function ctx.players(A, margin)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local hrp = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and ctx.inArea(A, hrp.Position, margin or 40) then
			table.insert(list, { player = p, hrp = hrp, hum = hum, char = c })
		end
	end
	return list
end

function ctx.blame(m, by)
	if by and by.Parent then
		m:SetAttribute("LastHitBy", by.UserId)
	end
end
function ctx.hurt(m, part, kind, amount, by, dir, pos)
	if Hazards and Hazards.hurt then
		local p = typeof(part) == "string" and m:FindFirstChild(part) or part
		if p then
			pcall(Hazards.hurt, m, p, kind, amount, by and by.Parent and by or nil, dir, pos or p.Position)
		end
	end
end
local LIMBS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
function ctx.anyPart(m)
	for _ = 1, 4 do
		local p = m:FindFirstChild(LIMBS[rng:NextInteger(1, #LIMBS)])
		if p then
			return p
		end
	end
	return ctx.torso(m)
end
function ctx.ragdoll(m, secs)
	if Ragdoll and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") then
		pcall(Ragdoll.Ragdoll, m, secs)
	end
end
function ctx.fling(m, vel, secs)
	if Ragdoll and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") then
		pcall(Ragdoll.Fling, m, vel, nil, secs or 2.5)
	end
end
-- steer every loose part of a ragdolled body toward `want` (rate per second)
function ctx.steer(m, wantFn, rate, dt)
	local k = math.min(1, dt * rate)
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and not p.Anchored then
			local want = wantFn(p)
			if want then
				p.AssemblyLinearVelocity = p.AssemblyLinearVelocity:Lerp(want, k)
			end
		end
	end
end
function ctx.isRagdolled(m)
	return Ragdoll and Ragdoll.IsRagdolled and Ragdoll.IsRagdolled(m) or m:GetAttribute("Ragdolled") == true
end
-- a tumble on a player's own client (PerkFXClient "Knock")
function ctx.knock(p, vel, rag)
	if typeof(p) == "Instance" and p:IsA("Player") and p.Parent then
		local c = p.Character
		if c and c:GetAttribute("Morphed") then
			vel *= 0.2
		end
		PerkFX:FireClient(p, "Knock", vel, rag or 1)
	end
end
function ctx.fx(kind, data)
	FX:FireAllClients(kind, data)
end
function ctx.banner(title, sub, c0, c1, t)
	Announce:FireAllClients({ kind = "Event", title = title, sub = sub, time = t or 4, color = c0, accent = c1 })
end
function ctx.sfx(key, pos, vol, speed)
	if Hazards and Hazards.sfx then
		pcall(Hazards.sfx, key, pos, vol, speed)
	end
end
-- the wanderers and the fighting game's NPCs run from it
function ctx.threat(pos, radius, secs)
	if Hazards and Hazards.onBlast then
		pcall(Hazards.onBlast, pos, radius, nil)
	end
	local gojo = ServerScriptService:FindFirstChild("GojoServer")
	local th = gojo and gojo:FindFirstChild("Threat")
	if th and th:IsA("BindableEvent") then
		th:Fire(pos, radius, secs or 3)
	end
end
function ctx.hook(name)
	local f = ServerStorage:FindFirstChild("PerkHooks")
	local h = f and f:FindFirstChild(name)
	return (h and h:IsA("BindableEvent")) and h or nil
end

---------------------------------------------------------------------------------------------------------------------
-- running, waiting, stacking
local running = {} -- [ev] = true
local waiting = {} -- [kind] = { entry, ... }
local started = 0
local runners = {}
for _, k in ipairs(KINDS) do
	local m = script:FindFirstChild(k)
	if m and m:IsA("ModuleScript") then
		local ok, fn = pcall(require, m)
		if ok and type(fn) == "function" then
			runners[k] = fn
		else
			warn("[PerkMapEvents] " .. k .. " failed to load: " .. tostring(fn))
		end
	else
		warn("[PerkMapEvents] no module for " .. k)
	end
end

local function countOf(kind)
	local n = 0
	for ev in pairs(running) do
		if ev.kind == kind then
			n += 1
		end
	end
	return n
end

local pump
local function launch(entry)
	local kind = entry.kind
	local fn = runners[kind]
	if not fn then
		return
	end
	started += 1
	local A = entry.area
	local now = ctx.now()
	local marker = Instance.new("Part")
	marker.Name = kind .. "_" .. started
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
	marker.Transparency = 1
	marker.Size = Vector3.new(1, 1, 1)
	marker.CFrame = CFrame.new(A.c)
	local ev = { id = started, kind = kind, by = entry.player, name = entry.name, area = A, marker = marker, t0 = now,
		ends = now + (entry.secs or 30), stop = false, byPos = entry.pos }
	function ev.setEnds(t)
		ev.ends = t
		marker:SetAttribute("Ends", t)
	end
	for k, v in pairs({ Kind = kind, Id = started, Area = A.id, By = entry.name, T0 = now, Ends = ev.ends, AreaC = A.c, AreaH = A.h }) do
		marker:SetAttribute(k, v)
	end
	marker.Parent = folder
	running[ev] = true
	local t = TITLE[kind]
	if t then
		ctx.banner(string.upper(entry.name) .. " " .. t[1], t[2] .. (A.id == "Ruins" and "  -  THE RUINS" or "  -  THE SANDBOX"), t[3], t[4], 4.5)
	end
	task.spawn(function()
		local ok, err = pcall(fn, ctx, ev)
		if not ok then
			warn("[PerkMapEvents] " .. kind .. " #" .. ev.id .. ": " .. tostring(err))
		end
		if ev.cleanup then
			pcall(ev.cleanup)
		end
		running[ev] = nil
		marker:SetAttribute("Over", true)
		task.delay(3, function() -- clients fade it out first
			marker:Destroy()
		end)
		pump(kind)
	end)
end

pump = function(kind)
	local list = waiting[kind]
	local P = POLICY[kind] or {}
	while list and #list > 0 and countOf(kind) < (P.max or 1) do
		launch(table.remove(list, 1))
	end
end

local DEFAULT_SECS = { Tornado = 35, Earthquake = 20, BlackHole = 24, Flood = 60, IceWorld = 60, Zombies = 75, BossDummy = 150, ChaosBundle = 600 }
local function request(kind, p)
	if not runners[kind] then
		warn("[PerkMapEvents] unknown event " .. tostring(kind))
		return false
	end
	local isPlayer = typeof(p) == "Instance" and p:IsA("Player")
	local A = ctx.areaOf(isPlayer and p or nil)
	local hrp = isPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local entry = { kind = kind, player = isPlayer and p or nil, name = isPlayer and p.DisplayName or "SOMEONE", area = A,
		pos = hrp and hrp.Position or nil, secs = DEFAULT_SECS[kind] }
	local P = POLICY[kind] or {}
	if P.extend then -- the same event on the same map: more time
		for ev in pairs(running) do
			if ev.kind == kind and ev.area.id == A.id and not ev.stop then
				local now = ctx.now()
				ev.setEnds(math.min(ev.ends + P.extend, now + P.cap))
				local t = TITLE[kind]
				ctx.banner(string.upper(entry.name) .. " ADDED MORE " .. string.upper(kind == "IceWorld" and "ICE" or kind) .. "!",
					"+" .. P.extend .. " SECONDS", t[3], t[4], 3.5)
				return true
			end
		end
	end
	waiting[kind] = waiting[kind] or {}
	if countOf(kind) >= (P.max or 1) then
		local t = TITLE[kind]
		ctx.banner(string.upper(entry.name) .. " " .. t[1], "#" .. (#waiting[kind] + 1) .. " IN LINE - IT STARTS RIGHT AFTER THIS ONE", t[3], t[4], 3.5)
	end
	table.insert(waiting[kind], entry)
	pump(kind)
	return true
end

-- the hooks ShopService fires (made here if the place doesn't have them yet)
local hooks = ServerStorage:FindFirstChild("PerkHooks")
if not hooks then
	hooks = Instance.new("Folder")
	hooks.Name = "PerkHooks"
	hooks.Parent = ServerStorage
end
for _, kind in ipairs(KINDS) do
	local h = hooks:FindFirstChild(kind)
	if not h then
		h = Instance.new("BindableEvent")
		h.Name = kind
		h.Parent = hooks
	end
	h.Event:Connect(function(p)
		local ok, err = pcall(request, kind, p)
		if not ok then
			warn("[PerkMapEvents] " .. kind .. ": " .. tostring(err))
		end
	end)
end

local ctl = script:FindFirstChild("Control") or Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, a, b)
	if cmd == "start" then
		return request(a, b or Players:GetPlayers()[1])
	elseif cmd == "stop" then
		for ev in pairs(running) do
			if not a or ev.kind == a then
				ev.stop = true
			end
		end
		for k in pairs(waiting) do
			if not a or k == a then
				waiting[k] = {}
			end
		end
		return true
	elseif cmd == "stats" then
		local out = { running = {}, waiting = {} }
		for ev in pairs(running) do
			table.insert(out.running, { kind = ev.kind, id = ev.id, area = ev.area.id, left = ev.ends - ctx.now(), info = ev.info })
		end
		for k, l in pairs(waiting) do
			out.waiting[k] = #l
		end
		return out
	end
	return nil
end
ctl.Parent = script

print("[PerkMapEvents] online: " .. table.concat(KINDS, ", "))
