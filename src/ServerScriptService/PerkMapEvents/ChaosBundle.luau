--!nocheck
-- PerkMapEvents.ChaosBundle (2026-11-15): 3 Nukes + 5 Meteor Showers bought in one go. Each is started through its
-- own PerkHooks event (ServerScriptService.PerkNuke / PerkMeteorShower), but only once that system is idle, so they
-- arrive one after another instead of eight banners at once - the nukes and the showers overlap each other.
local NUKES, SHOWERS = 3, 5

return function(ctx, ev)
	local SSS = game:GetService("ServerScriptService")
	local function busy(scriptName)
		local s = SSS:FindFirstChild(scriptName)
		local c = s and s:FindFirstChild("Control")
		if not c then
			return false
		end
		local ok, st = pcall(c.Invoke, c, "stats")
		return ok and type(st) == "table" and (st.running or (st.queued or 0) > 0) or false
	end
	local p = ev.by
	local function run(hookName, scriptName, n, gap)
		local fired = 0
		while fired < n and not ev.stop do
			if not busy(scriptName) then
				local h = ctx.hook(hookName)
				if not h then
					warn("[PerkMapEvents.ChaosBundle] no PerkHooks." .. hookName)
					return fired
				end
				h:Fire(p and p.Parent and p or nil)
				fired += 1
				ev.info = ev.info or {}
				ev.info[hookName] = fired
				task.wait(gap)
			else
				task.wait(0.5)
			end
		end
		return fired
	end
	local doneN = false
	task.spawn(function()
		run("Nuke", "PerkNuke", NUKES, 2)
		doneN = true
	end)
	task.wait(4)
	run("MeteorShower", "PerkMeteorShower", SHOWERS, 2)
	while not doneN and not ev.stop do
		task.wait(0.5)
	end
end
