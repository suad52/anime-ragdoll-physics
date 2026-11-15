--!nocheck
-- ServerScriptService.FallGuard (Script, 2026-11-07, owner: destruction). Nobody stays under the map.
-- Numbers: ReplicatedStorage.CityShared.DestructionConfig.FALL_GUARD; logic: CityShared.GroundGuard (probe / rescue).
--  * NPC dummies (tag RagdollNPC, alive, not Retired): torso below SAFE_Y -> moved back onto open street near where
--    they went under at once; BURIED under the terrain surface for BURIED_TIME -> the same. Ragdolled dummies keep
--    their ragdoll (the whole model is moved, every part's velocity zeroed). NPCService still retires anything that
--    somehow gets below -150 (last resort), and the craters' own refill lifts (CombatService.liftOutOf,
--    GroundFX.liftBodies) still run - this complements them, it does not replace them.
--  * Players: their client owns the body, so StarterPlayerScripts.FallGuardClient rescues its own character at once;
--    this script is the BACKSTOP and only moves a player still under the map after SERVER_GRACE s.
--  * A character with attribute NoFallGuard = true is skipped (a cinematic that wants a body below the street).
--  * Each rescue stamps FallRescuedAt (server time) on the model.
-- Control (BindableFunction child): ("stats") -> counters; ("reset") clears them.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GG = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("GroundGuard"))
local F = GG.CFG
if F.ENABLED == false then
	return
end

local NPC_TAG = "RagdollNPC"
pcall(function()
	NPC_TAG = require(ReplicatedStorage.GojoShared.Config.NPC).Tag or NPC_TAG
end)

local HZ = F.HZ or 15
local BURIED_TIME = F.BURIED_TIME or 0.2
local GRACE = F.SERVER_GRACE or 0.8

local recs = setmetatable({}, { __mode = "k" }) -- [model] = { badSince, lastSafe, nextProbe, bad }
local stats = { npc = 0, player = 0, failed = 0, last = nil }

local function check(model, isPlayer, t)
	if model:GetAttribute("NoFallGuard") or model:GetAttribute("Retired") then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local torso = model:FindFirstChild("LowerTorso") or model:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not torso then
		return
	end
	local rec = recs[model]
	if not rec then
		rec = { nextProbe = 0 }
		recs[model] = rec
	end
	local pos = torso.Position
	local bad
	if pos.Y < GG.SAFE_Y then
		bad = "below"
	elseif t >= rec.nextProbe then
		rec.nextProbe = t + 1 / HZ
		bad = GG.probe(pos)
		rec.bad = bad
	else
		bad = rec.bad
	end
	if not bad then
		rec.badSince = nil
		rec.lastSafe = pos
		return
	end
	rec.badSince = rec.badSince or t
	local wait = bad == "buried" and BURIED_TIME or 0
	if isPlayer then
		wait = math.max(wait, GRACE)
	end
	if t - rec.badSince < wait then
		return
	end
	rec.badSince, rec.bad = nil, nil
	local ok, moved, spot = pcall(GG.rescue, model, rec.lastSafe)
	if ok and moved then
		if isPlayer then
			stats.player += 1
		else
			stats.npc += 1
		end
		stats.last = { model = model:GetFullName(), why = bad, from = pos, to = spot, at = os.clock() }
	else
		stats.failed += 1
		warn("[FallGuard] rescue failed for " .. model:GetFullName() .. ": " .. tostring(moved))
	end
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		if c and c.Parent then
			check(c, true, t)
		end
	end
	if F.NPC ~= false then
		for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
			if m:IsA("Model") and m:IsDescendantOf(workspace) and not Players:GetPlayerFromCharacter(m) then
				check(m, false, t)
			end
		end
	end
end)

local ctl = script:FindFirstChild("Control") or Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.Parent = script
ctl.OnInvoke = function(cmd)
	if cmd == "reset" then
		stats.npc, stats.player, stats.failed, stats.last = 0, 0, 0, nil
		return true
	end
	return stats
end
