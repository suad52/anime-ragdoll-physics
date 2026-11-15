--!nocheck
-- ServerScriptService.Onboarding (2026-11-14, owner: "add this small onboarding thing at the beginning where when users
-- spawn in, the screen is dimmed and its pointed towards ..."): remembers who has been through the two-step intro
-- (StarterPlayerScripts.Onboarding) so it shows once per account, not on every join.
--   player attribute OnboardSeen: true / false (set as the player joins; false when the store cannot be read - e.g.
--   in Studio without API access - so the intro shows rather than never)
--   ReplicatedStorage.OnboardingDone (client -> server): they finished it -> saved in DataStore Onboarding_v1
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("OnboardingDone")
local okS, store = pcall(function()
	return DataStoreService:GetDataStore("Onboarding_v1")
end)
local function key(p)
	return "u" .. p.UserId
end
local function hook(p)
	local seen = false
	if okS and store then
		local ok, v = pcall(function()
			return store:GetAsync(key(p))
		end)
		seen = ok and v == true
	end
	if p.Parent then
		p:SetAttribute("OnboardSeen", seen)
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(hook, p)
end
Players.PlayerAdded:Connect(hook)
remote.OnServerEvent:Connect(function(p)
	if p:GetAttribute("OnboardSeen") == true then
		return
	end
	p:SetAttribute("OnboardSeen", true)
	if okS and store then
		task.spawn(function()
			pcall(function()
				store:SetAsync(key(p), true)
			end)
		end)
	end
end)
