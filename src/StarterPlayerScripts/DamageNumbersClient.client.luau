-- DamageNumbersClient (2026-11-07): pops a damage number for every hit the server's DamageFeed reports - every kit,
-- every ability, anyone who loses health. Colour and merging live in ReplicatedStorage.KitFeedback.numbers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Feedback = require(ReplicatedStorage:WaitForChild("KitFeedback"))
local Feed = ReplicatedStorage:WaitForChild("DamageFeed")

Feed.OnClientEvent:Connect(function(list)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoDamage") then
		return -- Settings menu: switched off
	end
	local ok, err = pcall(Feedback.numbers, list)
	if not ok then
		warn("[DamageNumbers] " .. tostring(err))
	end
end)
