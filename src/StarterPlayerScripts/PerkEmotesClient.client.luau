--!nocheck
-- StarterPlayerScripts.PerkEmotesClient (owner: emotes, 2026-11-07): boots ReplicatedStorage.PerkShared.Emotes on
-- every client - the B-key emote wheel, the owner's own emotes and the playback of everyone else's (relayed by
-- ServerScriptService.PerkEmotes). All the logic lives in the module; CharacterSelect's inventory requires it too.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ok, err = pcall(function()
	return require(ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Emotes"))
end)
if not ok then
	warn("[PerkEmotesClient] PerkShared.Emotes failed to load: " .. tostring(err))
end
