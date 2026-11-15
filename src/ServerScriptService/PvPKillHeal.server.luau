-- ServerScriptService.PvPKillHeal (2026-11-08): "take away regen - if you kill a player get 50 health back".
-- Natural regen is off (StarterCharacterScripts.Health is an empty stand-in). Every player-on-player kill
-- (ServerStorage.PvPKill, fired by LeaderboardService: Fire(killerUserId, victimUserId)) heals the killer by
-- PvPShared.Balance.KILL_HEAL, up to their max health. NPC kills don't heal.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BAL = require(ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Balance"))
local killEvent = ServerStorage:WaitForChild("PvPKill")

killEvent.Event:Connect(function(killerId, victimId)
	killerId, victimId = tonumber(killerId), tonumber(victimId)
	if not killerId or killerId == victimId then
		return
	end
	local killer = Players:GetPlayerByUserId(killerId)
	local char = killer and killer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.min(hum.MaxHealth, hum.Health + (tonumber(BAL.KILL_HEAL) or 50))
	end
end)
