--!nocheck
-- HeightLimit (2026-11-10): nobody flies off above the city (mainly Goku's flight). The tallest tower top is ~y 479 and
-- the boundary walls (City.Outskirts.Boundary) stop at ~y 1000, so above CEILING a flyer could leave the map over them.
-- The client owns its body: within SOFT of the ceiling upward speed is eased off, and the root is never above CEILING.
-- Runs before and after physics so it wins against any flight mover (BodyVelocity / LinearVelocity / CFrame writes).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- (2026-11-14, sandbox shop) the ragdoll sandbox's edge walls (workspace.Map.Bounds) stand from y -10 to y 390: with the
-- jump / gravity sliders a player can get that high, so the ceiling sits under their top when there is no city
local CEILING = workspace:FindFirstChild("City") and 520 or 365
local SOFT = 40
local player = Players.LocalPlayer

local function clamp()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local y = hrp.Position.Y
	if y < CEILING - SOFT then
		return
	end
	local v = hrp.AssemblyLinearVelocity
	if v.Y > 0 then
		local k = math.clamp((CEILING - y) / SOFT, 0, 1)
		hrp.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * k, v.Z)
	end
	if y > CEILING then
		hrp.CFrame = hrp.CFrame - Vector3.new(0, y - CEILING, 0)
	end
end

RunService.PreSimulation:Connect(clamp)
RunService.PostSimulation:Connect(clamp)
