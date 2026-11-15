--!nocheck
-- HitReactClient (2026-11-06): plays a GojoShared.HitReact flinch on every RagdollNPC-tagged body that is hit while
-- standing or held (a ragdoll reacts through physics instead). Generic for every kit: a health drop is pushed away
-- from the attacker (LastHitBy, else the nearest player) and sized by the damage; an explicit HitReact.mark from the
-- server (HitSeq) wins and carries its own direction, power and style.
-- PLAYERS (2026-11-08, "make it to where other players react when they are being hit so they don't look static"):
-- every player's character (yours too) gets the same flinch on every client. PvP damage is halved, so a player's
-- flinch is sized from double the health it lost; giant / guardian forms and ragdolls don't flinch.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local HitReact = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("HitReact"))

local GATE = 260 -- studs from the camera: farther bodies skip the clip
local hooked = setmetatable({}, { __mode = "k" })
local FORMS = { "Morphed", "TitanForm", "FoxBeast", "Guardian", "Flying" }

local function inForm(model)
	for _, a in ipairs(FORMS) do
		if model:GetAttribute(a) then
			return true
		end
	end
	return false
end

local function attackerPos(model, hrp)
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
			local d = (rr.Position - hrp.Position).Magnitude
			if d < 90 and (not bd or d < bd) then
				best, bd = rr.Position, d
			end
		end
	end
	return best
end

local function nearCamera(hrp)
	local cam = workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - hrp.Position).Magnitude < GATE
end

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
		local explicitAt = -1
		hum.HealthChanged:Connect(function(h)
			local dmg = last - h
			last = h
			if dmg <= 0.5 or h <= 0 then
				return -- healing, or death (the ragdoll takes over)
			end
			-- an explicit mark replicated with the same hit wins (it can arrive either side of the health change)
			task.delay(0.03, function()
				if os.clock() - explicitAt < 0.25 or not model.Parent then
					return
				end
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if not hrp or not nearCamera(hrp) or inForm(model) then
					return
				end
				local ap = attackerPos(model, hrp)
				local sized = Players:GetPlayerFromCharacter(model) and dmg * 2 or dmg
				HitReact.play(model, ap and (hrp.Position - ap) or nil, math.clamp(0.45 + sized / 22, 0.45, 1.5), nil)
			end)
		end)
		model:GetAttributeChangedSignal("HitSeq"):Connect(function()
			explicitAt = os.clock()
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if not hrp or not nearCamera(hrp) or inForm(model) then
				return
			end
			HitReact.play(model, model:GetAttribute("HitDir"), model:GetAttribute("HitPower") or 1, model:GetAttribute("HitStyle"))
		end)
	end)
end

for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
	hook(m)
end
CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(hook)

-- every player's character, the local one included
local function hookPlayer(p)
	p.CharacterAdded:Connect(hook)
	if p.Character then
		hook(p.Character)
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
Players.PlayerAdded:Connect(hookPlayer)
