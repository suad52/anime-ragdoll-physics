--!nocheck
-- ServerScriptService.GuardService (2026-11-11, combat rework): the server side of the BLOCK key and the BREAKOUT.
-- Remote ReplicatedStorage.PvPShared.Guard (client -> server):
--   ("block", on)   hold / release the guard. Granted while alive, not stunned / down (PvP.stunned) and not guard-broken
--                   (GuardBrokenUntil). Sets character attribute Blocking. A release lands no sooner than
--                   Balance.BLOCK_MIN_HOLD after the block went up.
--   ("breakout")    PvP.breakout(player): out of a stun / tumble / guard break, once per Balance.BREAKOUT_COOLDOWN.
--                   Answers the client with Guard:FireClient(player, "breakout", ok, reason).
-- The block itself (what it stops, the guard meter, guard break) is ServerScriptService.PvP, section BLOCK: every
-- kit's damage already passes through PvP.dmg, so all 10 fighters (and NPCs given a Blocking attribute) share it.
-- Swinging an M1 drops the guard (CombatService.requestPunch; GuardClient releases it before any attack key too).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PvP = require(ServerScriptService:WaitForChild("PvP"))
local shared = ReplicatedStorage:WaitForChild("PvPShared")
local BAL = require(shared:WaitForChild("Balance"))
local remote = shared:WaitForChild("Guard")

local since = {} -- [Player] = os.clock() the current block went up
local reqs = {} -- [Player] = { os.clock() } recent requests (rate limit)

local function rateOk(p)
	local t = os.clock()
	local r = reqs[p]
	if not r then
		r = {}
		reqs[p] = r
	end
	while #r > 0 and t - r[1] > 1 do
		table.remove(r, 1)
	end
	if #r >= 20 then
		return false
	end
	table.insert(r, t)
	return true
end

local function liveChar(p)
	local c = p.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") then
		return c
	end
	return nil
end

local function setBlock(p, on)
	local c = liveChar(p)
	if not c then
		return
	end
	if on then
		if c:GetAttribute("Blocking") == true or PvP.stunned(p) or PvP.guardBroken(c) then
			return
		end
		since[p] = os.clock()
		c:SetAttribute("Blocking", true)
	else
		local t0 = since[p] or 0
		local wait = (tonumber(BAL.BLOCK_MIN_HOLD) or 0.15) - (os.clock() - t0)
		local function drop()
			if since[p] == t0 and c.Parent then
				c:SetAttribute("Blocking", false)
			end
		end
		if wait > 0 then
			task.delay(wait, drop)
		else
			drop()
		end
	end
end

remote.OnServerEvent:Connect(function(p, kind, arg)
	if typeof(kind) ~= "string" or not rateOk(p) then
		return
	end
	if kind == "block" then
		setBlock(p, arg == true)
	elseif kind == "breakout" then
		local ok, why = PvP.breakout(p)
		remote:FireClient(p, "breakout", ok == true, why)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	since[p] = nil
	reqs[p] = nil
end)

print("[GuardService] online")
