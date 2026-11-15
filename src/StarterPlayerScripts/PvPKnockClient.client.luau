--!nocheck
-- PvPKnockClient (2026-11-07): applies PvP knockback to MY character (the server cannot move a client-owned body).
-- Fired by ServerScriptService.PvP.knock for every kit that hits through RagdollService. (vel, ragTime, keep):
-- ragTime 0 = a shove; > 0 = a tumble (PlatformStand) for that long, then get up.
-- BREAKOUT (2026-11-11): when the server grants a breakout it stamps BreakoutAt on my character; any tumble ends at
-- once (here and the kits' own tumbles: PlatformStand off, velocity calmed, GettingUp).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("PvPShared"):WaitForChild("Knockback")
local tumbleUntil = 0

local function eachAssembly(char, fn)
	local seen = {}
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and not p.Anchored then
			local r = p.AssemblyRootPart
			if r and not seen[r] then
				seen[r] = true
				fn(r)
			end
		end
	end
end

remote.OnClientEvent:Connect(function(vel, ragTime, keep)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 or typeof(vel) ~= "Vector3" or vel ~= vel then
		return
	end
	-- forms that are immune to being thrown around (same rules as the kits' own knockback handlers)
	if char:GetAttribute("SuperArmor") or char:GetAttribute("Guardian") or char:GetAttribute("AscForm") == "Instinct" then
		return
	end
	local k = math.clamp(tonumber(keep) or 0, 0, 1)
	ragTime = tonumber(ragTime) or 0
	if ragTime <= 0 then
		hrp:ApplyImpulse((vel - hrp.AssemblyLinearVelocity * (1 - k)) * hrp.AssemblyMass)
		return
	end
	tumbleUntil = math.max(tumbleUntil, os.clock() + ragTime)
	hum.PlatformStand = true
	eachAssembly(char, function(r)
		r:ApplyImpulse((vel - r.AssemblyLinearVelocity * (1 - k)) * r.AssemblyMass)
		r:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 8 * r.AssemblyMass)
	end)
end)

RunService.Heartbeat:Connect(function()
	if tumbleUntil > 0 and os.clock() >= tumbleUntil then
		tumbleUntil = 0
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end)

local function hookBreakout(char)
	char:GetAttributeChangedSignal("BreakoutAt"):Connect(function()
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or char:GetAttribute("BreakoutAt") == nil then
			return
		end
		tumbleUntil = 0
		hum.PlatformStand = false
		if hrp then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.2, math.max(v.Y * 0.2, 14), v.Z * 0.2) -- a little hop up
			hrp.AssemblyAngularVelocity = Vector3.zero
			local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude < 0.2 then
				look = Vector3.new(0, 0, -1)
			end
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look.Unit) -- upright
		end
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
end
player.CharacterAdded:Connect(function(c)
	tumbleUntil = 0
	hookBreakout(c)
end)
if player.Character then
	hookBreakout(player.Character)
end
