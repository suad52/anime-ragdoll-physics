--!nocheck
-- StarterPlayerScripts.FallGuardClient (2026-11-07, owner: destruction): puts MY character back on the street the moment it
-- is under the map. The client owns its body (PvP knockback and tumbles are simulated here - PvPKnockClient), so this is
-- the primary rescue for players; ServerScriptService.FallGuard is the backstop (after FALL_GUARD.SERVER_GRACE).
-- Rules + numbers: CityShared.GroundGuard / DestructionConfig.FALL_GUARD - torso below SAFE_Y (fell through / tunnelled
-- through the floor on a fast knockback) -> at once; BURIED under the terrain surface for BURIED_TIME -> the same.
-- The tumble / PlatformStand state is left alone (PvPKnockClient ends it on its own timer); velocities are zeroed.
-- Skipped while the character has attribute NoFallGuard = true.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GG = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("GroundGuard"))
local F = GG.CFG
if F.ENABLED == false then
	return
end
local player = Players.LocalPlayer
local HZ = F.HZ or 15
local BURIED_TIME = F.BURIED_TIME or 0.2

local badSince, lastSafe, nextProbe, lastBad = nil, nil, 0, nil
player.CharacterAdded:Connect(function()
	badSince, lastSafe, lastBad = nil, nil, nil
end)

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local torso = char and (char:FindFirstChild("LowerTorso") or char:FindFirstChild("HumanoidRootPart"))
	if not hum or not torso or hum.Health <= 0 or char:GetAttribute("NoFallGuard") then
		return
	end
	local t = os.clock()
	local pos = torso.Position
	local bad
	if pos.Y < GG.SAFE_Y then
		bad = "below"
	elseif t >= nextProbe then
		nextProbe = t + 1 / HZ
		bad = GG.probe(pos)
		lastBad = bad
	else
		bad = lastBad
	end
	if not bad then
		badSince = nil
		lastSafe = pos
		return
	end
	badSince = badSince or t
	if bad == "buried" and t - badSince < BURIED_TIME then
		return
	end
	badSince, lastBad = nil, nil
	local ok, err = pcall(GG.rescue, char, lastSafe)
	if not ok then
		warn("[FallGuardClient] rescue failed: " .. tostring(err))
	end
end)
