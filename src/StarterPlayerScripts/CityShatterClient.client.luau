-- StarterPlayer.StarterPlayerScripts.CityShatterClient (LocalScript, owner: destruction)
-- Plays the client half of the city destruction: glass shards, screen sparks and dust puffs for the batches the
-- server's CityDestruction sends over ReplicatedStorage.CityShared.Remotes.CityShatter (one batch per Heartbeat at
-- most). All FX are client-only, capped and distance-gated (CityShared.ShatterFX / DestructionConfig.CLIENT).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("CityShared", 60)
if not shared then
	return
end
local FX = require(shared:WaitForChild("ShatterFX"))
local remote = shared:WaitForChild("Remotes"):WaitForChild("CityShatter")

local fx = FX.new()
remote.OnClientEvent:Connect(function(batch)
	local ok, err = pcall(fx.handle, fx, batch)
	if not ok then
		warn("[CityShatterClient] " .. tostring(err))
	end
end)
RunService.Heartbeat:Connect(function(dt)
	fx:step(dt)
end)
