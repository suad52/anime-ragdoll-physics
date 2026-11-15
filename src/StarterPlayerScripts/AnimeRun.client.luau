--!nocheck
-- AnimeRun (orchestrator 2026-11-07): replaces Roblox's stock run with a procedural sprint - forward lean, chin up,
-- arms pumping bent at ~90 degrees, high knee drive, a heel kick on the recovery and a bounce on every step.
-- Written over the default animation in RunService.Stepped (the point where ProceduralAnimator writes too), blended
-- in by ground speed, faded out in the air / ragdolled / in a giant form, and it never touches a joint a
-- ProceduralAnimator clip is driving (punches, moves, hit flinches). Players and dummies alike, within 160 studs.
-- Signs (as in Clips): hip/shoulder/elbow flexion +X, knee flexion -X, Root pos -Y crouches.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animator = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))

local RUN_FROM, RUN_FULL = 11.5, 14.5 -- studs/s: blend in between these (players run at 16 = full sprint; dummies stroll at 7-11)
local MAX_DIST = 160
local STRIDE = 10.5 -- studs per full cycle (two steps)
local rad, sin, cos, max, clamp = math.rad, math.sin, math.cos, math.max, math.clamp
local NAMES = { "Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist",
	"RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" }
local AIR = { [Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true, [Enum.HumanoidStateType.Seated] = true, [Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true }

local rigs = setmetatable({}, { __mode = "k" }) -- [model] = { joints, phase, w }

local function A(x, y, z)
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function rigOf(model)
	local r = rigs[model]
	if r then
		return r
	end
	local joints = {}
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(NAMES, d.Name) then
			joints[d.Name] = d
		end
	end
	r = { joints = joints, phase = math.random() * 6.28, w = 0 }
	rigs[model] = r
	return r
end

-- the sprint pose at phase p (right leg forward at p = pi/2), intensity k (0..1, more lean/knee at full speed)
local function pose(p, k)
	local s, c = sin(p), cos(p)
	local sL, cL = -s, -c -- the left leg runs half a cycle behind
	local function leg(si, ci)
		-- hip swings forward/back; the knee drives up as the leg comes through (ci > 0) and kicks the heel up
		local hip = 12 + 48 * si * k + 10 * max(0, ci) * k
		local knee = -(18 + 100 * max(0, ci) ^ 1.3 * k + 22 * max(0, -si) * k)
		local ankle = 8 * si - 12 * max(0, -si) * k
		return A(hip, 0, 0), A(knee, 0, 0), A(ankle, 0, 0)
	end
	local rh, rk, ra = leg(s, c)
	local lh, lk, la = leg(sL, cL)
	-- arms pump opposite the legs, elbows ~90, hands driving up to chin height in front
	local function arm(si, side)
		local sh = 8 - 58 * si * k
		local el = 88 + 22 * max(0, -si)
		return A(sh, 0, side * (6 + 4 * k)), A(el, 0, 0)
	end
	local rsh, rel = arm(s, 1)
	local lsh, lel = arm(sL, -1)
	local bounce = -0.16 * k + 0.13 * k * cos(2 * p)
	return {
		Root = CFrame.new(0, bounce, 0) * A(-10 * k, 7 * s * k, 0),
		Waist = A(-7 * k, -11 * s * k, 0),
		Neck = A(14 * k, 5 * s * k, 0),
		RightHip = rh, RightKnee = rk, RightAnkle = ra,
		LeftHip = lh, LeftKnee = lk, LeftAnkle = la,
		RightShoulder = rsh, RightElbow = rel, LeftShoulder = lsh, LeftElbow = lel,
		RightWrist = A(-8, 0, 0), LeftWrist = A(-8, 0, 0),
	}
end

local function eligible(model)
	if model:GetAttribute("Ragdolled") or model:GetAttribute("Morphed") or model:GetAttribute("TitanForm") or model:GetAttribute("Guardian") then
		return false
	end
	return true
end

local function characters()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in ipairs(npcs:GetChildren()) do
			if m:IsA("Model") then
				table.insert(list, m)
			end
		end
	end
	return list
end

RunService.Stepped:Connect(function(_, dt)
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, model in ipairs(characters()) do
		local hum = model:FindFirstChildOfClass("Humanoid")
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hum and hrp and (hrp.Position - camPos).Magnitude < MAX_DIST then
			local r = rigOf(model)
			local v = hrp.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local want = 0
			if hum.Health > 0 and not AIR[hum:GetState()] and hum.MoveDirection.Magnitude > 0.1 and eligible(model) then
				want = clamp((speed - RUN_FROM) / (RUN_FULL - RUN_FROM), 0, 1)
			end
			-- quick in, quicker out (a jump or a stop must not drag the run pose along)
			r.w += (want - r.w) * clamp(dt * (want > r.w and 8 or 14), 0, 1)
			if r.w > 0.01 then
				r.phase = (r.phase + speed * dt / STRIDE * 2 * math.pi) % (2 * math.pi)
				local k = clamp(0.7 + speed / 80, 0.7, 1)
				local target = pose(r.phase, k)
				local busy = Animator.controlled(model)
				for name, cf in pairs(target) do
					local j = r.joints[name]
					if j and j.Parent and not (busy and busy[name]) then
						j.Transform = j.Transform:Lerp(cf, r.w)
					end
				end
			end
		end
	end
end)
