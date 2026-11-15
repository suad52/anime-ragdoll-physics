--!nocheck
-- HitReactServer (2026-11-06): the physical half of GojoShared.HitReact, for every kit's hits on RagdollNPC bodies.
-- A health drop on a body still on its feet and not held by a move shoves it back a little along the blow (unless the
-- kit already knocked it that way this frame) and pauses its AI for a beat; a body already ragdolled (a juggle, a
-- slash on a held ragdoll in a cinematic) gets a RagdollService.Jolt so it bends and jerks. Bodies an explicit
-- HitReact.mark just named are left to that caller.
-- PLAYERS (2026-11-08, "make the attacks stun people like they do the npcs in pvp"): a real hit on a standing,
-- unheld player stuns them for PvP.HIT_STUN (StunnedUntil; PvPStunClient + every kit's gate enforce it). No shove from
-- here - the kits knock players around themselves, on the player's own client.
-- BLOCK (2026-11-11): a hit soaked by a block / a breakout's dodge (PvP.absorbed) stuns nobody; an NPC still gets the
-- little slide (it reads as the guard being pushed back).
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local RagdollService = require(script.Parent:WaitForChild("RagdollService"))
local HitReact = require(game:GetService("ReplicatedStorage"):WaitForChild("GojoShared"):WaitForChild("HitReact"))
local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP"))

local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.yAxis
local HELD = { "GrabbedBy", "InDomain", "WhippedBy", "SlashedBy" }

local function held(m)
	for _, a in ipairs(HELD) do
		if m:GetAttribute(a) then
			return true
		end
	end
	return false
end

local function attackerPos(model, pos)
	local uid = model:GetAttribute("LastHitBy")
	local p = uid and Players:GetPlayerByUserId(uid)
	local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if r then
		return r.Position
	end
	local best, bd
	for _, pl in ipairs(Players:GetPlayers()) do
		local rr = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if rr then
			local d = (rr.Position - pos).Magnitude
			if d < 90 and (not bd or d < bd) then
				best, bd = rr.Position, d
			end
		end
	end
	return best
end

local hooked = setmetatable({}, { __mode = "k" })

local function hook(model)
	if hooked[model] or not model:IsA("Model") then
		return
	end
	hooked[model] = true
	task.spawn(function()
		local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
		if not hum then
			return
		end
		local last = hum.Health
		local markAt = -1
		model:GetAttributeChangedSignal("HitSeq"):Connect(function()
			markAt = os.clock()
		end)
		hum.HealthChanged:Connect(function(h)
			local dmg = last - h
			last = h
			if dmg <= 0.5 or h <= 0 then
				return
			end
			-- after the kit's own push / fling for this hit (same frame)
			task.defer(function()
				task.defer(function()
					if not model.Parent or os.clock() - markAt < 0.1 then
						return
					end
					local hrp = model:FindFirstChild("HumanoidRootPart")
					if not hrp or hrp.Anchored then
						return
					end
					local ap = attackerPos(model, hrp.Position)
					local push = ap and (hrp.Position - ap) * FLAT
					if not push or push.Magnitude < 1e-3 then
						return
					end
					push = push.Unit
					if model:GetAttribute("Ragdolled") then
						RagdollService.Jolt(model, push * math.clamp(3 + dmg * 0.35, 3, 12) + UP * 2)
					elseif not held(model) then
						if hrp.AssemblyLinearVelocity:Dot(push) < 8 then -- the kit did not already knock it this way
							HitReact.slide(model, push, math.clamp(0.6 + dmg * 0.045, 0.6, 2.4), 0.14) -- (smaller since M1 strings plant the attacker)
						end
						local t = workspace:GetServerTimeNow() + 0.3
						local cur = model:GetAttribute("StunnedUntil")
						if not PvP.absorbed(model) and (type(cur) ~= "number" or cur < t) then
							model:SetAttribute("StunnedUntil", t)
						end
					end
				end)
			end)
		end)
	end)
end

for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
	hook(m)
end
CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(hook)

-- players: the hit-stun only
local function hookPlayerChar(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		local dmg = last - h
		last = h
		if dmg < PvP.HIT_STUN_MIN or h <= 0 or char:GetAttribute("Ragdolled") or held(char) or PvP.absorbed(char) then
			return
		end
		local by = char:GetAttribute("LastHitBy")
		local p = Players:GetPlayerFromCharacter(char)
		if by and p and by ~= p.UserId then -- hurt by someone else, not a fall or their own blast
			PvP.stun(char, PvP.HIT_STUN)
		end
	end)
end
local function hookPlayer(p)
	p.CharacterAdded:Connect(function(c)
		task.spawn(hookPlayerChar, c)
	end)
	if p.Character then
		task.spawn(hookPlayerChar, p.Character)
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)
