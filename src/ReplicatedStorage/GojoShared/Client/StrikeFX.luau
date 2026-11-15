--!nocheck
-- StrikeFX (orchestrator 2026-11-07): the flashy layer on every M1 strike, client-side and cheap (a handful of
-- anchored neon parts per strike, all tweened out and destroyed).
--   burst(pos, dir, color, power)  - the air-pressure pop at the fist / foot at full extension: a white flash, an
--                                    accent shock ring facing the strike, and speed shards flung along it
--   ground(pos, color, power)      - a finisher's shockwave ring + dust spikes on the floor
--   shake(strength, time)          - local camera shake (the caster's own camera only)
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local StrikeFX = {}
local folder
local function bin()
	if not folder or not folder.Parent then
		folder = workspace:FindFirstChild("LocalFX") or Instance.new("Folder")
		folder.Name = "LocalFX"
		folder.Parent = workspace
	end
	return folder
end

local function part(shape, size, cf, color, tr)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Transparency = tr or 0
	p.Parent = bin()
	return p
end

local function fade(p, t, props)
	props.Transparency = 1
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	Debris:AddItem(p, t + 0.05)
end

local function near(pos)
	local cam = workspace.CurrentCamera
	return cam and (cam.CFrame.Position - pos).Magnitude < 220
end

function StrikeFX.burst(pos, dir, color, power)
	if not near(pos) then
		return
	end
	power = power or 1
	dir = (dir and dir.Magnitude > 0.01) and dir.Unit or Vector3.zAxis
	local face = CFrame.lookAt(pos, pos + dir)
	-- white core flash
	local core = part(Enum.PartType.Ball, Vector3.one * 0.9 * power, face, Color3.new(1, 1, 1), 0.15)
	fade(core, 0.12, { Size = Vector3.one * 2.4 * power })
	-- shock ring facing the strike (a thin cylinder whose axis is the strike direction)
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.12, 1.4, 1.4) * Vector3.new(1, power, power), face * CFrame.Angles(0, math.rad(90), 0), color, 0.3)
	fade(ring, 0.22, { Size = Vector3.new(0.05, 5.5 * power, 5.5 * power) })
	-- a second, later ring further along
	local ring2 = part(Enum.PartType.Cylinder, Vector3.new(0.08, 1, 1) * Vector3.new(1, power, power), face * CFrame.new(0, 0, -1.2) * CFrame.Angles(0, math.rad(90), 0), Color3.new(1, 1, 1), 0.35)
	fade(ring2, 0.3, { Size = Vector3.new(0.04, 4.5 * power, 4.5 * power), CFrame = face * CFrame.new(0, 0, -3.5 * power) * CFrame.Angles(0, math.rad(90), 0) })
	-- speed shards flung forward in a cone
	local n = power > 1.5 and 9 or 5
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local spread = CFrame.Angles(math.cos(a) * 0.55, math.sin(a) * 0.55, 0)
		local cf = face * spread
		local shard = part(Enum.PartType.Block, Vector3.new(0.08, 0.08, 1.6 + math.random() * 1.2) * Vector3.new(1, 1, power), cf, i % 2 == 0 and color or Color3.new(1, 1, 1), 0.1)
		fade(shard, 0.2 + math.random() * 0.08, { CFrame = cf * CFrame.new(0, 0, -(4 + math.random() * 3) * power), Size = Vector3.new(0.03, 0.03, 0.4) })
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10 * power
	light.Brightness = 3
	light.Shadows = false
	light.Parent = core
end

function StrikeFX.ground(pos, color, power)
	if not near(pos) then
		return
	end
	power = power or 1
	local flat = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	local ring = part(Enum.PartType.Cylinder, Vector3.new(0.15, 2, 2), flat, color, 0.25)
	fade(ring, 0.45, { Size = Vector3.new(0.05, 20 * power, 20 * power) })
	local ring2 = part(Enum.PartType.Cylinder, Vector3.new(0.1, 1, 1), flat * CFrame.new(0.05, 0, 0), Color3.new(1, 1, 1), 0.2)
	fade(ring2, 0.3, { Size = Vector3.new(0.04, 13 * power, 13 * power) })
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + math.random() * 0.4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local cf = CFrame.lookAt(pos + out * 1.5, pos + out * 3 + Vector3.new(0, 1.2, 0))
		local spike = part(Enum.PartType.Block, Vector3.new(0.5, 0.5, 1.4), cf, color:Lerp(Color3.new(1, 1, 1), 0.3), 0.1)
		fade(spike, 0.35, { CFrame = cf * CFrame.new(0, 0, -(4 + math.random() * 3) * power), Size = Vector3.new(0.1, 0.1, 2.5) })
	end
end

local shakeUntil, shakeMag = 0, 0
local bound = false
function StrikeFX.shake(strength, time)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	shakeMag = math.max(shakeMag * (os.clock() < shakeUntil and 1 or 0), strength)
	shakeUntil = math.max(shakeUntil, os.clock() + time)
	if not bound then
		bound = true
		RunService:BindToRenderStep("StrikeShake", Enum.RenderPriority.Camera.Value + 2, function()
			local left = shakeUntil - os.clock()
			if left <= 0 then
				shakeMag = 0
				return
			end
			local cam = workspace.CurrentCamera
			local m = shakeMag * math.min(1, left * 6)
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * m * 2.2), math.rad((math.random() - 0.5) * m * 2.2), 0)
		end)
	end
end

return StrikeFX
