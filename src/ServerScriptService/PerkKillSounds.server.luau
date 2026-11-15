--!nocheck
-- ServerScriptService.PerkKillSounds (2026-11-09, shop expansion): the Custom Kill Sound perk (PerkCatalog "KillSound").
-- When a body dies (a RagdollNPC dummy or a player), its LastHitBy (the attacker's UserId, stamped by every kit before
-- the killing damage) is looked up: if that player's KillSoundId is set (ShopService.Ext.Settings writes it only with
-- the perk), every client is told to play it at the body. A player who dies with a DeathSoundId plays that one too.
--   HudShared.CustomSound:FireAllClients(soundId, position, kind = "kill" | "death", userId)
-- StarterPlayerScripts.SettingsMenu plays it (unless that client switched custom sounds off), 3D at the body.
-- Retired bodies (knocked off the map by the game) are skipped. One sound per body.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("CustomSound")
local NPC_TAG = "RagdollNPC"
pcall(function()
	NPC_TAG = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC")).Tag or NPC_TAG
end)

local done = setmetatable({}, { __mode = "k" })
local stats = { kill = 0, death = 0 }

local function bodyPos(model)
	local part = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return part and part.Position
end

local function onDeath(model, victim)
	if done[model] or model:GetAttribute("Retired") then
		return
	end
	done[model] = true
	local pos = bodyPos(model)
	if not pos then
		return
	end
	local killer = Players:GetPlayerByUserId(tonumber(model:GetAttribute("LastHitBy")) or 0)
	local kid = killer and killer ~= victim and tonumber(killer:GetAttribute("KillSoundId")) or 0
	if kid > 0 then
		stats.kill += 1
		remote:FireAllClients(kid, pos, "kill", killer.UserId)
	end
	local did = victim and tonumber(victim:GetAttribute("DeathSoundId")) or 0
	if did > 0 then
		stats.death += 1
		remote:FireAllClients(did, pos, "death", victim.UserId)
	end
end

local function watch(model, victim)
	local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		onDeath(model, victim)
	end)
end

for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
	task.spawn(watch, m, nil)
end
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(m)
	task.spawn(watch, m, nil)
end)
local function onPlayer(p)
	p.CharacterAdded:Connect(function(c)
		watch(c, p)
	end)
	if p.Character then
		task.spawn(watch, p.Character, p)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end

-- Studio: script.Control:Invoke("stats") | ("test", soundId, kind?) plays one at the first player
local ctl = Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, a, b)
	if cmd == "test" then
		local p = Players:GetPlayers()[1]
		local pos = p and p.Character and bodyPos(p.Character)
		if pos then
			remote:FireAllClients(tonumber(a) or 0, pos, b or "kill", p.UserId)
			return true
		end
		return false
	end
	return stats
end
ctl.Parent = script
