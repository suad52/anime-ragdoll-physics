--!nocheck
-- StarterPlayerScripts.SandboxReactions (2026-11-13): the body language of a frightened dummy.
-- The owner: NPCs that see harm should show it - "putting their hands to their face and ... behind their head to show
-- shock", legs "into something of a horse stance from karate" - and then panic and run, "not fast but ... really trying
-- to make an effort to escape".
-- The SERVER only says what a dummy feels (ServerScriptService.Sandbox.Wanderers): the tag Reacting on its model, and
--   React    "shockFace" | "shockHead" | "shockMouth" | "cower" | "shield" | "pant" | "panic"   (nil = nothing)
--   ReactBy  the UserId it is afraid of, or ReactAt, the place it happened (where the head turns)
-- The pose is drawn HERE. These rigs have no Motor6Ds - every joint is an AnimationConstraint - and a script cannot
-- upload an animation, so each frame the pose is blended over whatever the animator wrote into joint.Transform.
-- That write has to happen in RunService.Stepped: anywhere else the animator overwrites it within the same frame.
-- The numbers were FITTED on the mannequin rig with forward kinematics (hand centre within 0.07 studs of the cheek,
-- the back of the head, the mouth, the crown), and every leg pose carries the pelvis drop that keeps the feet on the
-- floor - so change a hip or a knee and the Root offset beside it has to be worked out again.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TAG = "Reacting"
local E = CFrame.fromEulerAnglesYXZ
local rad, sin, cos, clamp, noise = math.rad, math.sin, math.cos, math.clamp, math.noise

-- arm = { shoulder x, y, z, elbow, wrist? } for the RIGHT arm (the left is its mirror image)
-- leg = { hip flex, hip turn-out, knee, ankle flex, ankle turn, pelvis drop, pelvis forward }
local function build(waist, neck, arm, leg)
	local t = { Waist = E(rad(waist), 0, 0), Neck = E(rad(neck), 0, 0) }
	if arm then
		t.RightShoulder, t.LeftShoulder = E(rad(arm[1]), rad(arm[2]), rad(arm[3])), E(rad(arm[1]), -rad(arm[2]), -rad(arm[3]))
		t.RightElbow, t.LeftElbow = E(rad(arm[4]), 0, 0), E(rad(arm[4]), 0, 0)
		if arm[5] then
			t.RightWrist, t.LeftWrist = E(rad(arm[5]), 0, 0), E(rad(arm[5]), 0, 0)
		end
	end
	if leg then
		t.RightHip, t.LeftHip = E(rad(leg[1]), -rad(leg[2]), 0), E(rad(leg[1]), rad(leg[2]), 0)
		t.RightKnee, t.LeftKnee = E(rad(leg[3]), 0, 0), E(rad(leg[3]), 0, 0)
		t.RightAnkle, t.LeftAnkle = E(rad(leg[4]), rad(leg[5]), 0), E(rad(leg[4]), -rad(leg[5]), 0)
		t.Root = CFrame.new(0, leg[6], leg[7])
	end
	return t
end
-- the horse stance: thighs turned out and dropped, shins upright, feet 2.6 studs apart (they stand 0.84 apart)
local HORSE, HORSE_DEEP = { 55, 62, -55, 0, 28, -0.46, -0.30 }, { 64, 66, -64, 0, 30, -0.60, -0.28 }
local POSES = {
	shockFace = { joints = build(6, 7, { 6, 69, 38, 144 }, HORSE), tremble = 0.035, look = 0.3, lookMax = 0.45, hop = 0.4, snap = 22 }, -- hands on the cheeks
	shockHead = { joints = build(9, 12, { 149, -72, -4, 90 }, HORSE_DEEP), tremble = 0.03, look = 0.3, lookMax = 0.45, hop = 0.48, snap = 22 }, -- hands behind the head
	shockMouth = { joints = build(4, 4, { 21, 76, 30, 102 }, HORSE), tremble = 0.04, look = 0.3, lookMax = 0.45, hop = 0.36, snap = 22 }, -- hands over the mouth
	cower = { joints = build(-42, -16, { 132, -24, -60, 48 }, { 82, 14, -118, 36, 6, -1.02, -0.52 }), tremble = 0.07, snap = 11 }, -- down, hands over the head
	shield = { joints = build(10, 3, { 45, 63, 41, 82, -50 }, { 22, 24, -30, 8, 10, -0.08, -0.21 }), tremble = 0.03, look = 0.7, lookMax = 1.0, snap = 20 }, -- hands up, palms out
	pant = { joints = build(-40, 16, { 26, -2, -28, 2 }, { 26, 8, -40, 14, 4, -0.12, -0.23 }), look = 0.5, lookMax = 0.9, snap = 6 }, -- bent over, out of breath
	panic = { joints = build(-18, 0, { 160, 0, 24, 40 }, nil), look = 1, lookMax = 1.45, lookPulse = true, snap = 14 }, -- arms up; the legs are the run
	-- (2026-11-15, shop EVENTS: ServerScriptService.PerkMapEvents.Zombies) arms out in front, head lolling; the legs are the walk
	zombie = { joints = build(14, -14, { 84, 0, 6, 12 }, nil), snap = 10 },
}
POSES.zombie.extra = function(T, tt)
	T.RightShoulder = E(rad(84 + 7 * sin(tt * 2.6)), rad(4), rad(6))
	T.LeftShoulder = E(rad(80 + 7 * sin(tt * 2.6 + 1.5)), rad(-4), rad(-6))
	T.RightElbow = E(rad(14 + 8 * sin(tt * 1.9)), 0, 0)
	T.LeftElbow = E(rad(10 + 8 * sin(tt * 1.7 + 1)), 0, 0)
	T.Neck = E(rad(-16 + 5 * sin(tt * 1.1)), rad(8 * sin(tt * 0.6)), rad(14 * sin(tt * 0.8)))
	T.Waist = E(rad(14), rad(6 * sin(tt * 1.3)), 0)
end
POSES.pant.extra = function(T, tt)
	local b = sin(tt * 5.4) -- heaving
	T.Waist = E(rad(-40 + 5 * b), 0, 0)
	T.Neck = E(rad(16 - 5 * b), 0, 0)
	T.Root = T.Root * CFrame.new(0, 0.035 * b, 0)
	T.RightShoulder = E(rad(26 - 4 * b), rad(-2), rad(-28))
	T.LeftShoulder = E(rad(26 - 4 * b), rad(2), rad(28))
end
POSES.panic.extra = function(T, tt)
	local ph = tt * 12 -- both arms thrown up and flailing, out of step with each other
	T.RightShoulder = E(rad(158 + 20 * sin(ph)), rad(12 * sin(ph * 0.5)), rad(24 + 14 * cos(ph * 1.3)))
	T.LeftShoulder = E(rad(150 + 22 * sin(ph + 2.2)), rad(-12 * sin(ph * 0.5 + 1)), -rad(26 + 14 * cos(ph * 1.1 + 0.8)))
	T.RightElbow = E(rad(40 + 26 * sin(ph * 1.7 + 0.4)), 0, 0)
	T.LeftElbow = E(rad(44 + 26 * sin(ph * 1.5 + 2)), 0, 0)
	T.Waist = E(rad(-18), rad(7 * sin(ph * 0.5)), rad(4 * sin(ph * 0.5 + 1)))
end

local active = {}
-- A model's tag can reach this client BEFORE all of its joints have (measured: a dummy tagged the moment it spawned
-- arrived with its legs and waist, and the arms came a beat later - so it stood in a horse stance with its hands at
-- its sides). So the joints are looked for again until all fifteen are in.
local function scan(model, S)
	S.hrp = S.hrp or model:FindFirstChild("HumanoidRootPart")
	for _, d in ipairs(model:GetDescendants()) do
		if (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) and not S.joints[d.Name] then
			S.joints[d.Name] = { j = d, w = 0, c = CFrame.identity }
			S.count += 1
		end
	end
end
local function add(model)
	if active[model] then
		return
	end
	local S = { joints = {}, count = 0, nextScan = 0, tmp = {}, seed = math.random() * 100, t0 = os.clock(), yaw = 0, pitch = 0 }
	scan(model, S)
	active[model] = S
end
for _, m in ipairs(CollectionService:GetTagged(TAG)) do
	add(m)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)

local function threatOf(model)
	local uid = model:GetAttribute("ReactBy")
	if uid then
		local p = Players:GetPlayerByUserId(uid)
		local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			return hrp.Position
		end
	end
	return model:GetAttribute("ReactAt")
end

-- this frame's joint targets for one dummy: the pose, then what moves on top of it
local function frame(S, pose, model, now, dt)
	local T = S.tmp
	table.clear(T)
	for n, cf in pairs(pose.joints) do
		T[n] = cf
	end
	local tt = now + S.seed
	if pose.extra then
		pose.extra(T, tt)
	end
	if pose.tremble then -- shaking: the trunk, the arms, the knees
		local a = pose.tremble
		local n1, n2, n3 = noise(tt * 9, 1.3), noise(tt * 9, 7.7), noise(tt * 11, 3.1)
		T.Waist = T.Waist * E(n1 * a, n2 * a, n3 * a * 0.5)
		if T.RightShoulder then
			T.RightShoulder = T.RightShoulder * E(n2 * a * 1.4, 0, n3 * a * 1.4)
			T.LeftShoulder = T.LeftShoulder * E(n3 * a * 1.4, 0, n1 * a * 1.4)
		end
		if T.RightKnee then
			T.RightKnee = T.RightKnee * E(n1 * a * 1.6, 0, 0)
			T.LeftKnee = T.LeftKnee * E(n2 * a * 1.6, 0, 0)
		end
	end
	-- the head goes to what frightened it (a runner looks back over its shoulder in glances)
	local wantYaw, wantPitch = 0, 0
	local threat = pose.look and S.hrp and threatOf(model)
	if threat then
		local l = S.hrp.CFrame:PointToObjectSpace(threat)
		local w = pose.look
		if pose.lookPulse then
			local ph = (tt % 2.6) / 2.6
			w = (ph < 0.34) and sin(ph / 0.34 * math.pi) or 0
		end
		wantYaw = clamp(math.atan2(-l.X, -l.Z), -pose.lookMax, pose.lookMax) * w
		wantPitch = clamp(math.atan2(l.Y - 1.5, math.sqrt(l.X * l.X + l.Z * l.Z)), -0.35, 0.35) * w
	end
	local k = 1 - math.exp(-dt * 9)
	S.yaw += (wantYaw - S.yaw) * k
	S.pitch += (wantPitch - S.pitch) * k
	if math.abs(S.yaw) > 0.005 or math.abs(S.pitch) > 0.005 then
		T.Neck = T.Neck * E(S.pitch, S.yaw * 0.75, 0)
		T.Waist = T.Waist * E(0, S.yaw * 0.25, 0)
	end
	-- the start of a shock: a jump out of its skin
	if pose.hop and T.Root then
		local tau = now - S.t0
		if tau < 0.7 then
			T.Root = T.Root * CFrame.new(0, pose.hop * math.exp(-5 * tau) * sin(tau * 15), 0)
		end
	end
	return T
end

RunService.Stepped:Connect(function(_, dt)
	local now = os.clock()
	for model, S in pairs(active) do
		if not model.Parent then
			active[model] = nil
			continue
		end
		if S.count < 15 and now >= S.nextScan then
			S.nextScan = now + 0.25
			scan(model, S)
		end
		local name = model:GetAttribute("React")
		local pose = name and POSES[name] or nil
		if pose and (model:GetAttribute("Ragdolled") or model:GetAttribute("Dead")) then
			pose = nil -- a ragdoll's joints are loose: nothing to pose
		end
		if pose ~= S.pose then
			S.pose, S.t0 = pose, now
		end
		local T = pose and frame(S, pose, model, now, dt) or nil
		local kIn, kOut = 1 - math.exp(-dt * (pose and pose.snap or 14)), 1 - math.exp(-dt * 8)
		local alive = false
		for jn, J in pairs(S.joints) do
			local goal = T and T[jn]
			if goal then
				J.c = (J.w < 0.02) and goal or J.c:Lerp(goal, kIn)
				J.w += (1 - J.w) * kIn
			else
				J.w -= J.w * kOut
			end
			if J.w > 0.004 then
				alive = true
				local j = J.j
				local base = j.Transform
				if J.last and base == J.last then
					base = J.base or CFrame.identity -- no animation wrote this joint this frame: that is our own last write
				else
					J.base = base
				end
				local out = base:Lerp(J.c, J.w)
				j.Transform = out
				J.last = out
			elseif J.last then
				J.j.Transform = J.base or CFrame.identity -- hand the joint back
				J.last, J.w = nil, 0
			end
		end
		if not alive and not pose and not CollectionService:HasTag(model, TAG) then
			active[model] = nil
		end
	end
end)
