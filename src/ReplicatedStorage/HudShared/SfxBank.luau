--!nocheck
-- ReplicatedStorage.HudShared.SfxBank (2026-11-12, owner: "make sure the normal swinging attacks have proper swooshing
-- sounds ... make sure impact sounds are fine as well ... everything should have something of like a satisfying sound").
-- Variant pools for the sounds every fighter shares. SfxBank.play never repeats the last variant of a pool and nudges the
-- pitch a few percent, so ten punches in a row never sound like one sample on a loop. All ids are Creator Store audio
-- that loads in this place (checked 2026-11-12): Pro Sound Effects swishes (Roblox-licensed) and the lorenzosaudiostash
-- hit pack the kits already used.
--   SfxBank.play(pool, at?, volume?, speed?) -> Sound
--     at: a BasePart / Attachment (the sound rides it), a Vector3 (a point in the world), or nil (2D, on the camera)
local Debris = game:GetService("Debris")
local SfxBank = {}

-- (2026-11-12, owner: "you didnt add the whooshing sound effects for the normal attacks") the first swing pool (Pro Sound
-- Effects ruler swishes) measured a PlaybackLoudness peak of 14-98 against the hits' 170-670: inaudible under a hit, and so
-- was the old shared whoosh (peak 55). These were picked by measured loudness and a fast attack:
SfxBank.SWING = { 99266120255392, 137466029708179, 9113942732, 74206544979422, 122522591098602 } -- SWOOSH, miss swing, PSE cord swish, whoosh, quick whosh
SfxBank.SWING_HEAVY = { 9120714365, 9120716870, 9120718689, 99266120255392 } -- fuller swish-bys for finishers
SfxBank.BLADE = { 125132253621935, 7118966167, 137628815514180 } -- sword whooshes
SfxBank.HIT = { 126976659766267, 74041775202019, 132555084427990, 96359585058783 } -- punchy blunt hits
SfxBank.HIT_HEAVY = { 79476956608476, 101232234433592 } -- heavy hits with a debris tail

-- GAIN: per-sample volume so every variant of a pool lands at about the same loudness (measured peak at Volume 1 ->
-- gain = target / peak; swings target ~350, hits ~400). Unlisted ids play at 1.
local GAIN = {
	[99266120255392] = 0.77, [137466029708179] = 1.7, [9113942732] = 2.0, [74206544979422] = 1.6, [122522591098602] = 2.4,
	[9120714365] = 1.2, [9120716870] = 1.1, [9120718689] = 1.07,
	[125132253621935] = 0.9, [137628815514180] = 0.88, [7118966167] = 2.0,
	[126976659766267] = 0.86, [74041775202019] = 0.97, [132555084427990] = 2.0, [96359585058783] = 0.6,
}
SfxBank.GAIN = GAIN
local lastId
local last = {}
function SfxBank.pick(pool)
	local list = type(pool) == "string" and SfxBank[pool] or pool
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local i = math.random(#list)
	if #list > 1 and i == last[list] then
		i = i % #list + 1
	end
	last[list] = i
	lastId = list[i]
	return "rbxassetid://" .. string.format("%d", list[i])
end

local anchors
function SfxBank.play(pool, at, volume, speed)
	local id = SfxBank.pick(pool)
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = (volume or 0.7) * (GAIN[lastId] or 1)
	s.PlaybackSpeed = (speed or 1) * (0.94 + math.random() * 0.12)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 160
	local parent
	if typeof(at) == "Instance" and (at:IsA("BasePart") or at:IsA("Attachment")) then
		parent = at
	elseif typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.Name = "SfxPoint"
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		Debris:AddItem(a, 4)
		parent = a
	else
		parent = workspace.CurrentCamera
	end
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
	return s
end

return SfxBank
