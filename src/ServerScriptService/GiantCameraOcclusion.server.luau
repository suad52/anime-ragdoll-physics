-- GiantCameraOcclusion (2026-11-07): while a titan form stands (character attribute TitanForm, set by
-- ShifterServer.ShifterService), the owner's camera uses Invisicam so buildings between the lens and a 60-stud body
-- turn see-through instead of snapping the camera into the titan's back. Player.DevCameraOcclusionMode can ONLY be
-- set by the server (a LocalScript gets "Insufficient permissions"), which is why ShifterClient's old attempt never
-- took effect. Restores the StarterPlayer default when the form ends, the character dies or respawns.
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local function apply(p, char)
	if p.Character ~= char then
		return
	end
	local giant = char:GetAttribute("TitanForm") ~= nil and char:GetAttribute("TitanForm") ~= false
	local want = giant and Enum.DevCameraOcclusionMode.Invisicam or StarterPlayer.DevCameraOcclusionMode
	if p.DevCameraOcclusionMode ~= want then
		p.DevCameraOcclusionMode = want
	end
end

local function onCharacter(p, char)
	apply(p, char)
	char:GetAttributeChangedSignal("TitanForm"):Connect(function()
		apply(p, char)
	end)
end

local function onPlayer(p)
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	p.CharacterRemoving:Connect(function()
		p.DevCameraOcclusionMode = StarterPlayer.DevCameraOcclusionMode
	end)
	if p.Character then
		onCharacter(p, p.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end
