--!nocheck
-- ServerScriptService.PerkWorldEvents (2026-11-14, sandbox shop): two of the server events sold in the shop
-- (HudShared.PerkCatalog consumables; ShopService fires ServerStorage.PerkHooks.<Name>(player) once a purchase is saved).
--   MOON GRAVITY  workspace.Gravity = STD x MOON.FRACTION for MOON.DURATION s for the whole server. Buying it again while it
--                 runs adds MOON.DURATION (up to MOON.MAX ahead). Workspace attributes: WorldGravity (the world's gravity
--                 right now - StarterPlayerScripts.SandboxSliders scales a player's own Gravity slider from it) and
--                 MoonUntil (server time; StarterPlayerScripts.PerkEventsClient shows the timer and the moon look).
--   DUMMY RAIN    RAIN.COUNT dummies (Sandbox.Dummies) appear high over random spots of the map across RAIN.OVER s and fall
--                 limp - the landings do the rest. Never more than the dummy cap allows.
-- Studio test hook: script.Control:Invoke("moon", player?) | ("rain", player?) | ("stopMoon") | ("stats").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local STD = 196.2
local MOON = { FRACTION = 0.17, DURATION = 90, MAX = 600 }
local RAIN = { COUNT = 24, OVER = 6, HEIGHT = 140, SPREAD = 300, KEEP_FREE = 6, LIFE = 60 }

local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")
local Announce = Remotes:WaitForChild("Announce")

local function nameOf(p)
	return (typeof(p) == "Instance" and p:IsA("Player")) and string.upper(p.DisplayName) or "SOMEONE"
end
local function banner(title, sub, c0, c1)
	Announce:FireAllClients({ kind = "Event", title = title, sub = sub, time = 4, color = c0, accent = c1 })
end

-- the world's gravity when nothing is changing it
local BASE = workspace.Gravity
if BASE < 1 then
	BASE = STD
end
workspace:SetAttribute("WorldGravity", BASE)
workspace:SetAttribute("MoonUntil", 0)

---------------------------------------------------------------------------------------------------------------------
-- moon gravity
local moonUntil, moonRunning = 0, false
local function setGravity(g)
	workspace:SetAttribute("WorldGravity", g)
	workspace.Gravity = g
end
local function moon(p)
	local now = workspace:GetServerTimeNow()
	if moonRunning and moonUntil > now then
		moonUntil = math.min(moonUntil + MOON.DURATION, now + MOON.MAX)
		workspace:SetAttribute("MoonUntil", moonUntil)
		banner(nameOf(p) .. " ADDED MORE MOON GRAVITY!", "+" .. MOON.DURATION .. " SECONDS OF LOW GRAVITY", Color3.fromRGB(110, 140, 255), Color3.fromRGB(210, 225, 255))
		return
	end
	moonUntil = now + MOON.DURATION
	workspace:SetAttribute("MoonUntil", moonUntil)
	moonRunning = true
	setGravity(BASE * MOON.FRACTION)
	banner(nameOf(p) .. " TURNED ON MOON GRAVITY!", MOON.DURATION .. " SECONDS OF LOW GRAVITY FOR EVERYONE", Color3.fromRGB(110, 140, 255), Color3.fromRGB(210, 225, 255))
	task.spawn(function()
		while workspace:GetServerTimeNow() < moonUntil do
			task.wait(0.25)
		end
		setGravity(BASE)
		workspace:SetAttribute("MoonUntil", 0)
		moonRunning = false
		banner("MOON GRAVITY IS OVER", "BACK TO EARTH", Color3.fromRGB(110, 140, 255), Color3.fromRGB(210, 225, 255))
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- dummy rain
local Dummies, RagdollService
do
	local sb = ServerScriptService:WaitForChild("Sandbox", 30)
	local m = sb and sb:FindFirstChild("Dummies")
	if m then
		local ok, r = pcall(require, m)
		Dummies = ok and r or nil
	end
	local g = ServerScriptService:FindFirstChild("GojoServer")
	local rs = g and g:FindFirstChild("RagdollService")
	if rs then
		local ok, r = pcall(require, rs)
		RagdollService = ok and r or nil
	end
end
local rng = Random.new()
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function groundAt(x, z)
	local list = {}
	for _, n in ipairs({ "NPCs", "Gore", "FX" }) do
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
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(x, 380, z), Vector3.new(0, -500, 0), groundParams)
	return hit and hit.Position.Y or 1
end
local raining = false
local rained = 0
local function rain(p)
	if not Dummies then
		warn("[PerkWorldEvents] no Sandbox.Dummies - nothing to rain")
		return
	end
	banner(nameOf(p) .. " MADE IT RAIN DUMMIES!", "LOOK UP", Color3.fromRGB(150, 150, 170), Color3.fromRGB(245, 245, 255))
	task.spawn(function()
		while raining do -- one rain at a time; the next one starts when it is done
			task.wait(0.5)
		end
		raining = true
		local n = math.min(RAIN.COUNT, (Dummies.CAP or 64) - Dummies.count() - RAIN.KEEP_FREE)
		for i = 1, math.max(0, n) do
			local x, z = rng:NextNumber(-RAIN.SPREAD, RAIN.SPREAD), rng:NextNumber(-RAIN.SPREAD, RAIN.SPREAD)
			local y = groundAt(x, z) + RAIN.HEIGHT + rng:NextNumber(0, 40)
			local ok, m = pcall(Dummies.spawn, CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), { ragdoll = 8, life = RAIN.LIFE })
			if ok and m then
				rained += 1
				if RagdollService then
					pcall(RagdollService.Fling, m, Vector3.new(rng:NextNumber(-14, 14), -30, rng:NextNumber(-14, 14)), nil, 8)
				end
			end
			task.wait(RAIN.OVER / math.max(n, 1))
		end
		raining = false
	end)
end

---------------------------------------------------------------------------------------------------------------------
local hooks = ServerStorage:WaitForChild("PerkHooks", 30)
local function listen(name, fn)
	local h = hooks and hooks:WaitForChild(name, 30)
	if h then
		h.Event:Connect(function(p)
			local ok, err = pcall(fn, p)
			if not ok then
				warn("[PerkWorldEvents] " .. name .. ": " .. tostring(err))
			end
		end)
	else
		warn("[PerkWorldEvents] ServerStorage.PerkHooks." .. name .. " missing")
	end
end
listen("MoonGravity", moon)
listen("DummyRain", rain)

local ctl = script:FindFirstChild("Control") or Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, a)
	if cmd == "moon" then
		moon(a or Players:GetPlayers()[1])
		return true
	elseif cmd == "stopMoon" then
		moonUntil = 0
		return true
	elseif cmd == "rain" then
		rain(a or Players:GetPlayers()[1])
		return true
	elseif cmd == "stats" then
		return { gravity = workspace.Gravity, moonUntil = moonUntil, moonRunning = moonRunning, raining = raining, rained = rained }
	end
	return nil
end
ctl.Parent = script
