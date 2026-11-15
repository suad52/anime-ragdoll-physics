-- ServerScriptService.CityDestruction (Script, owner: destruction)
-- (2026-11-14, ragdoll sandbox: owner "in the ruins, make it to where things can be broken and stuff from the abilities")
-- re-enabled for THE RUINS: ServerStorage.ArenaGen tags the arena's props CityProp (trees, columns, lanterns, fences,
-- boulders...: knocked over and flung, regrown after DestructionConfig.REGEN.PROP s) and Structure punches holes in its
-- walls / cliff / arch (rebuilt after STRUCTURE.REGEN s). Nothing in the sandbox field is tagged or under workspace.Arenas.
-- Boots the NEON SHIBUYA destruction + regen service (child ModuleScript "Service"; numbers in
-- ReplicatedStorage.CityShared.DestructionConfig). Listens to GojoServer.WorldBlast and creates + listens to
-- GojoServer.BreakBlast (Deku / Ichigo look it up per call, so its existence switches on directional breaking).
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gojo = ServerScriptService:WaitForChild("GojoServer", 30)
if not gojo then
	warn("[CityDestruction] GojoServer missing - destruction disabled")
	return
end

local worldBlast = gojo:WaitForChild("WorldBlast", 30)
local breakBlast = gojo:FindFirstChild("BreakBlast")
if not breakBlast then
	breakBlast = Instance.new("BindableEvent")
	breakBlast.Name = "BreakBlast"
	breakBlast.Parent = gojo
end

-- shared folder + remote (normally installed in Edit; recreated here if someone removed them)
local shared = ReplicatedStorage:FindFirstChild("CityShared")
if not shared then
	warn("[CityDestruction] ReplicatedStorage.CityShared missing - destruction disabled")
	return
end
local remotes = shared:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = shared
end
if not remotes:FindFirstChild("CityShatter") then
	local r = Instance.new("RemoteEvent")
	r.Name = "CityShatter"
	r.Parent = remotes
end

local Service = require(script:WaitForChild("Service"))
local handle = Service.start({ worldBlast = worldBlast, breakBlast = breakBlast })
_G.CityDestruction = handle -- debugging from the server command bar: _G.CityDestruction.stats()

-- building structure + terrain damage (holes in walls, street craters; both heal): child ModuleScript "Structure"
local structure
do
	local mod = script:FindFirstChild("Structure")
	if mod and handle then
		local ok, err = pcall(function()
			structure = require(mod).start(handle, require(shared:WaitForChild("DestructionConfig")))
		end)
		if not ok then
			warn("[CityDestruction] structure damage disabled: " .. tostring(err))
		end
	end
end

-- utility / movement breaking (dashes, flight, flung bodies, giant forms walking): child ModuleScript "Crash"
do
	local crashMod = script:FindFirstChild("Crash")
	if crashMod and handle then
		local ok, err = pcall(function()
			require(crashMod).start(handle, require(shared:WaitForChild("DestructionConfig")))
		end)
		if not ok then
			warn("[CityDestruction] crash breaking disabled: " .. tostring(err))
		end
	end
end

-- a server-side control for testing in Play (command bar requires get a separate module instance)
local ctl = script:FindFirstChild("Control")
if not ctl then
	ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.Parent = script
end
ctl.OnInvoke = function(cmd, ...)
	if cmd == "stats" then
		return handle.stats()
	elseif cmd == "impact" then
		handle.impact(...)
		return true
	elseif cmd == "restoreAll" then
		handle.restoreAll()
		return true
	elseif cmd == "structure" then -- holes / craters counters
		if structure then
			local c, nCraters, nHoles = structure.stats()
			return { counts = c, craters = nCraters, damagedParts = nHoles }
		end
		return nil
	elseif cmd == "rebuildAll" then
		handle.restoreAll()
		if structure then
			structure.rebuildAll()
		end
		return true
	elseif cmd == "crashlog" then -- ("crashlog", true) starts recording player sweeps; ("crashlog") returns + clears
		local on = ...
		local log = handle.crashLog or {}
		handle.crashLog = {}
		if on ~= nil then
			handle.crashDebug = on and true or nil
		end
		return log
	end
	return nil
end
