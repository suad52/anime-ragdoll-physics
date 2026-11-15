--!nocheck
-- ServerScriptService.TauntService (2026-11-09, shop expansion): relays TAUNTS. A client fires HudShared.Taunt(id);
-- the server checks the taunt exists, that the player owns it (free, or Perk_TauntHype / Perk_TauntTrash), the
-- cooldown (TauntCatalog.COOLDOWN) and that they are alive, then tells every client (Taunt:FireAllClients(player, id)),
-- which play the sound and show the bubble over that player's head (StarterPlayerScripts.TauntMenu).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("HudShared")
local T = require(shared:WaitForChild("TauntCatalog"))

local remote = shared:FindFirstChild("Taunt")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Taunt"
	remote.Parent = shared
end

local last = {}
remote.OnServerEvent:Connect(function(p, id)
	local t = type(id) == "string" and T.byId[id]
	if not t or not T.owns(p, t) then
		return
	end
	local now = os.clock()
	if last[p] and now - last[p] < T.COOLDOWN - 0.15 then
		return
	end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not char:FindFirstChild("Head") then
		return
	end
	last[p] = now
	remote:FireAllClients(p, id)
	local qe = game:GetService("ServerScriptService"):FindFirstChild("ShopService") and game:GetService("ServerScriptService").ShopService:FindFirstChild("QuestEvent") -- (2026-11-11) quests
	if qe then
		qe:Fire(p, "taunts", 1)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)
