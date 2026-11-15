--!nocheck
-- RagdollService: physical ragdolls for R15 constraint rigs (AnimationConstraint + BallSocketConstraint).
-- Ragdolling = disable every AnimationConstraint except Root; the rig's own BallSocketConstraints become the joints.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config")
local CFG = require(ConfigFolder:WaitForChild("Ragdoll"))

-- PvP (2026-11-07): a PLAYER body is never ragdolled here - the server cannot simulate a client-owned character.
-- Ragdoll/Fling on one hand it to ServerScriptService.PvP, which tells the victim's client to tumble.
local PvPMod
local function pvp()
	if PvPMod == nil then
		local ok, m = pcall(function()
			return require(game:GetService("ServerScriptService"):WaitForChild("PvP", 5))
		end)
		PvPMod = ok and m or false
	end
	return PvPMod or nil
end
local function playerBody(model)
	return model and Players:GetPlayerFromCharacter(model) ~= nil
end
-- BLOCK (2026-11-11): a hit PvP.dmg just soaked with a block (or a breakout's dodge) leaves the body standing:
-- Ragdoll refuses, Fling only gives a small pushback along the ground (see ServerScriptService.PvP, section BLOCK)
local function absorbed(model)
	local P = pvp()
	return P ~= nil and P.absorbed ~= nil and P.absorbed(model)
end
local COL = require(ConfigFolder:WaitForChild("Collision"))

local RagdollService = {}

-- [model] = { props = {[part] = PhysicalProperties?}, lastHit = os.clock(), getUpAt = number?, permanent = bool }
local states = {}
local standing = setmetatable({}, { __mode = "k" }) -- [model] = heartbeats left to re-claim a body that has just got up
local inited = false
local WHIP -- per-part share of a fling's speed (set below Fling's helpers)

-- (2026-11-14, owner: "some npcs do random circles while theyre ragdolled") measured: downed bodies whose Humanoid
-- had left Physics for Running - a limp body with a live humanoid steering it (a wanderer's unfinished MoveTo, a
-- client's copy while the body was lent) drags round in circles. So while a body is down nothing but Physics (or
-- Dead) is allowed: the moving states are locked too, and the Heartbeat below puts it back if it gets out anyway.
-- Players never come through here (PvP.knock), so this only ever touches NPCs.
local LOCKED_STATES = {
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Landed,
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.StrafingNoPhysics,
}
local STANDING_COLLIDE = { HumanoidRootPart = true, UpperTorso = true, LowerTorso = true, Head = true }

local function bodyParts(model)
	local list = {}
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("BasePart") then
			table.insert(list, c)
		end
	end
	return list
end

local function setGroup(model, group)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

-- ownership is per assembly; once limbs are separate assemblies each needs claiming again.
-- (2026-11-14) only the limbs and whatever hangs off them as an assembly of its own: a body can carry 200 welded
-- wound parts, and they ride with their limb.
local function setOwner(model, player)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored and (d.Parent == model or d.AssemblyRootPart == d) then
			pcall(function()
				if d:CanSetNetworkOwnership() then
					d:SetNetworkOwner(player)
				end
			end)
		end
	end
end
local function claimServer(model)
	setOwner(model, nil)
end

-- LEND (2026-11-13, measured in the ragdoll sandbox): a body the SERVER simulates reaches a client 0.23 s late (physics
-- interpolation) - "I hit it, a beat, then it reacts". Handing the body to the attacker's client at the moment of the
-- hit shows the reaction within 2 frames (0.04 s measured) and simulates it at THEIR frame rate, which is also why it
-- looks smoother. The server cannot push a body a client owns, so every Ragdoll / Jolt / Unragdoll takes it back
-- first; it also comes back once it has settled, when it is grabbed or strapped, or when the lender leaves.
local function lendParts(model, player)
	setOwner(model, player)
end
local function reclaim(model, st)
	if st and st.lend then
		st.lend = nil
		claimServer(model)
	end
end

-- WHO SIMULATES A BODY THAT IS DOWN (2026-11-14, owner: "make all the npc movement like falling and stuff smoother
-- and more reactive to everything (there are some things that have delays and such, i.e. the train hit)").
-- Measured: when a body goes limp its limbs become assemblies of their own, and the engine starts those on AUTOMATIC
-- ownership - so bodies the code believed the server had were handed to a nearby client a moment later, in mid-flight
-- (a jump on that screen), and a client-owned body ignored the server's next push. 9 of 21 downed bodies were out on
-- automatic. Now ownership is always set, and by one rule:
--   * a blow from a PLAYER (RagdollService.lendFor names them; the weapons call Lend themselves) -> that player's
--     client simulates the body from the next step: it reacts on their screen at once.
--   * a push nobody is behind (a machine's one blow, a body going limp, a drop) -> the NEAREST player's client, also
--     from the next step. Measured why not the server: a body the server simulates starts moving on a client 0.35-0.4 s
--     late and then jumps up to 17 studs to catch up - that was the "delay", and the jump was the stutter.
--   * a STREAM of server pushes (a fan, a vortex, a barrage: 3 claims inside 0.6 s), RagdollService.Hold (a trampoline,
--     a beast's jaws) or a body something holds -> the server's, until that stops and it has lain calm for half a
--     second; then the nearest player takes it (walking into a body, a second blow - all immediate).
--   A mover the SERVER simulates (the train, the wrecking ball, the blender's arms) is seen ~0.2 s late on a client,
--   so Sandbox.Machines lands its blow that much late: the body goes as the mover is SEEN to arrive.
local OWN = { CALM_SPEED = 8, CALM_FRAMES = 30, NEAR = 140, HINT_RANGE = 320, FAR = 360, BURST_T = 0.6, BURST_HOLD = 0.6 }
RagdollService.lendFor = nil -- (model) -> Player | nil: set by the sandbox's Main - who is behind the push being resolved now
local HELD_ATTRS = { "GrabbedBy", "InDomain", "WhippedBy", "SlashedBy" }
local function held(model)
	if model:GetAttribute("Strapped") == true then
		return true
	end
	for _, a in ipairs(HELD_ATTRS) do
		if model:GetAttribute(a) ~= nil then
			return true
		end
	end
	return false
end
local function autoOwned(part)
	local ok, auto = pcall(part.GetNetworkOwnershipAuto, part)
	return ok and auto == true
end
-- the server is about to move this body (every Ragdoll / Fling / forced Jolt): what happens to it next
local function noteClaim(model, st, t)
	st.calm = 0
	local c = st.claims
	if not c[1] or t - c[1] >= 0.03 then -- (one blow can call in twice - the damage hook, then the kit's knock: one claim)
		c[3], c[2], c[1] = c[2], c[1], t
	end
	if c[3] and t - c[3] <= OWN.BURST_T then
		st.serverUntil = math.max(st.serverUntil or 0, t + OWN.BURST_HOLD)
		st.want, st.calmOnly = nil, true
		return
	end
	local f = RagdollService.lendFor
	local pl = nil
	if f then
		local ok, res = pcall(f, model)
		pl = ok and res or nil
	end
	st.want, st.calmOnly = pl or "near", false
	st.serverUntil = math.max(st.serverUntil or 0, t)
end
local function densityFor(name)
	local D = CFG.Density
	if not D then
		return CFG.LimbDensity
	end
	if name == "UpperTorso" or name == "LowerTorso" then
		return D.torso
	elseif name == "Head" then
		return D.head
	elseif string.find(name, "Upper", 1, true) then
		return D.upper
	elseif string.find(name, "Lower", 1, true) then
		return D.lower
	elseif string.find(name, "Hand", 1, true) or string.find(name, "Foot", 1, true) then
		return D.tip
	end
	return CFG.LimbDensity
end

local function isAlive(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model:GetAttribute("Dead") ~= true
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	if v.Magnitude < 1e-3 then
		return Vector3.xAxis
	end
	return v.Unit
end

local function torsoSpeed(model)
	local s = 0
	for _, n in ipairs({ "UpperTorso", "LowerTorso" }) do
		local p = model:FindFirstChild(n)
		if p then
			s = math.max(s, p.AssemblyLinearVelocity.Magnitude)
		end
	end
	return s
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(model, dist)
	local lt = model:FindFirstChild("LowerTorso")
	if not lt then
		return nil
	end
	groundParams.FilterDescendantsInstances = { model }
	return workspace:Raycast(lt.Position + Vector3.new(0, 2, 0), Vector3.new(0, -(dist + 2), 0), groundParams)
end

function RagdollService.Init()
	if inited then
		return
	end
	inited = true
	for _, g in ipairs(COL.Groups) do
		pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(g) then
				PhysicsService:RegisterCollisionGroup(g)
			end
		end)
	end
	for _, pair in ipairs(COL.NonColliding) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
		end)
	end
	local function hookCharacter(char)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end)
	end
	local function hookPlayer(p)
		if p.Character then
			hookCharacter(p.Character)
		end
		p.CharacterAdded:Connect(hookCharacter)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

function RagdollService.Setup(model)
	if model:GetAttribute("RagdollSetup") then
		return
	end
	model:SetAttribute("RagdollSetup", true)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
	end
	-- jointed neighbours must not fight at the joint; non-adjacent self-collision stays on (arms vs torso)
	local folder = Instance.new("Folder")
	folder.Name = "RagdollNoCollide"
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			local p0, p1 = d.Attachment0.Parent, d.Attachment1.Parent
			if p0 and p1 and p0 ~= p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local nc = Instance.new("NoCollisionConstraint")
				nc.Part0 = p0
				nc.Part1 = p1
				nc.Parent = folder
			end
		end
	end
	folder.Parent = model
	setGroup(model, "NPCs")
	claimServer(model)
end

function RagdollService.IsRagdolled(model)
	return states[model] ~= nil
end

local function enter(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return nil
	end
	local st = { props = {}, lastHit = os.clock(), getUpAt = nil, permanent = false, hum = hum, claims = {}, assert = 2 }
	for _, s in ipairs(LOCKED_STATES) do
		hum:SetStateEnabled(s, false)
	end
	-- (2026-11-14) whatever it was walking to is off: no steering left for a limp body
	hum.Jump = false
	hum:Move(Vector3.zero)
	hum:MoveTo(hrp.Position)
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0.1)
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") and d.Name ~= "Root" then
			d.Enabled = false
		end
	end
	-- death disables EVERY AnimationConstraint (Root included); a weld keeps the massless, non-colliding root
	-- part riding with the pelvis instead of dropping through the world on its own
	local lt = model:FindFirstChild("LowerTorso")
	if lt and not hrp:FindFirstChild("RagdollRootWeld") then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "RagdollRootWeld"
		weld.Part0 = lt
		weld.Part1 = hrp
		weld.Parent = hrp
	end
	-- loose joints while down (the rig's friction torques made ragdolls fly like planks); restored on get-up
	st.sockets = {}
	local loose = CFG.JointLooseness or 1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BallSocketConstraint") and d.Name ~= "TentacleJoint" then
			st.sockets[d] = { d.MaxFrictionTorque, d.UpperAngle, d.TwistLowerAngle, d.TwistUpperAngle }
			d.MaxFrictionTorque = d.MaxFrictionTorque * loose
			local L = CFG.Loose and CFG.Loose[(d.Name:gsub("^Left", ""):gsub("^Right", ""):gsub("BallSocket$", ""))]
			if L then
				d.UpperAngle = math.max(d.UpperAngle, L[1])
				d.TwistLowerAngle = math.min(d.TwistLowerAngle, L[2])
				d.TwistUpperAngle = math.max(d.TwistUpperAngle, L[3])
			elseif d.Name == "WaistBallSocket" and CFG.WaistSwing then
				d.UpperAngle = math.max(d.UpperAngle, CFG.WaistSwing)
			elseif d.Name == "NeckBallSocket" and CFG.NeckSwing then
				d.UpperAngle = math.max(d.UpperAngle, CFG.NeckSwing)
			end
		end
	end
	for _, p in ipairs(bodyParts(model)) do
		st.props[p] = p.CustomPhysicalProperties
		if p == hrp then
			p.CanCollide = false
			p.Massless = true
		else
			p.CanCollide = true
			p.CustomPhysicalProperties = PhysicalProperties.new(densityFor(p.Name), CFG.LimbFriction, CFG.LimbElasticity)
		end
	end
	setGroup(model, "Ragdolls")
	states[model] = st
	model:SetAttribute("Ragdolled", true)
	claimServer(model)
	return st
end

-- (2026-11-15, shop EVENTS) a living body with the attribute Unstoppable (the giant boss dummy, ServerScriptService
-- PerkMapEvents.BossDummy) is never knocked over or flung: it takes the damage and keeps walking. Once Dead it falls.
local function unstoppable(model)
	return model:GetAttribute("Unstoppable") == true and model:GetAttribute("Dead") ~= true
end

-- duration nil = stay down (until Unragdoll, or forever once dead); number = auto get-up after it
function RagdollService.Ragdoll(model, duration)
	if not model or not model.Parent then
		return false
	end
	if playerBody(model) then
		local P = pvp()
		return P ~= nil and P.knock(model, Vector3.zero, duration or 1.2) or false
	end
	if not states[model] and (absorbed(model) or unstoppable(model)) then
		return false -- blocked (or the boss): stays on its feet
	end
	local st = states[model] or enter(model)
	if not st then
		return false
	end
	reclaim(model, st) -- whoever is calling means to move it from the server
	local t = os.clock()
	noteClaim(model, st, t)
	st.lastHit = t
	if duration == nil then
		st.permanent = true
		st.getUpAt = nil
	elseif not st.permanent then
		st.getUpAt = math.max(st.getUpAt or 0, t + duration)
	end
	return true
end

function RagdollService.Unragdoll(model)
	local st = states[model]
	if not st or not isAlive(model) then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	local lt = model:FindFirstChild("LowerTorso")
	if not hum or not hrp or not lt then
		return false
	end
	states[model] = nil
	if st.lend then -- the get-up below changes Humanoid state: that only takes on a body the server owns
		st.lend = nil
		claimServer(model)
	end
	-- face along the torso; a face-down body's look points at the ground, so fall back to the head direction
	local look = lt.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.25 then
		look = lt.CFrame.UpVector * Vector3.new(1, 0, 1)
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local pos = lt.Position
	local hit = groundBelow(model, 10)
	local groundY = hit and hit.Position.Y or (pos.Y - 0.6)
	local standPos = Vector3.new(pos.X, groundY + hum.HipHeight + hrp.Size.Y / 2 + CFG.GetUpLift, pos.Z)
	local rootWeld = hrp:FindFirstChild("RagdollRootWeld")
	if rootWeld then
		rootWeld:Destroy()
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") then
			d.Enabled = true
		end
	end
	for sock, v in pairs(st.sockets or {}) do
		if sock.Parent then
			sock.MaxFrictionTorque, sock.UpperAngle = v[1], v[2]
			if v[3] then
				sock.TwistLowerAngle, sock.TwistUpperAngle = v[3], v[4]
			end
		end
	end
	for _, p in ipairs(bodyParts(model)) do
		p.CanCollide = STANDING_COLLIDE[p.Name] == true
		if p == hrp then
			p.Massless = false
		end
		p.CustomPhysicalProperties = st.props[p]
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end
	hrp.CFrame = CFrame.lookAt(standPos, standPos + look)
	setGroup(model, "NPCs")
	for _, s in ipairs(LOCKED_STATES) do
		hum:SetStateEnabled(s, true)
	end
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	model:SetAttribute("Ragdolled", false)
	claimServer(model)
	standing[model] = 3 -- (2026-11-14) the limbs rejoin over the next step: claimed again then
	return true
end

WHIP = {
	UpperTorso = CFG.WhipTorso or 1, LowerTorso = CFG.WhipPelvis or 1, HumanoidRootPart = CFG.WhipPelvis or 1,
	Head = CFG.WhipHead or 1,
	LeftUpperArm = CFG.WhipLimb or 1, RightUpperArm = CFG.WhipLimb or 1,
	LeftUpperLeg = CFG.WhipLimb or 1, RightUpperLeg = CFG.WhipLimb or 1,
	LeftLowerArm = CFG.WhipEnd or 1, RightLowerArm = CFG.WhipEnd or 1, LeftHand = CFG.WhipEnd or 1, RightHand = CFG.WhipEnd or 1,
	LeftLowerLeg = CFG.WhipEnd or 1, RightLowerLeg = CFG.WhipEnd or 1, LeftFoot = CFG.WhipEnd or 1, RightFoot = CFG.WhipEnd or 1,
}

-- a jolt for a body that is ALREADY down (a juggle hit, a slash on a held ragdoll): the torso is knocked by `vel`
-- relative to its current motion and the limbs trail, so it bends and jerks without resetting its flight
RagdollService.clientJolt = nil -- (player, model, vel): set by the sandbox's Main (a remote to that client)
-- (2026-11-14, sandbox shop) flingScale(model) -> number: set by the sandbox's Main - the attacker's Fling Power slider.
-- Jolt and Fling multiply an NPC body's push by it (never a player's: their knock goes through PvP).
RagdollService.flingScale = nil
local function scaledPush(model, v)
	local f = RagdollService.flingScale
	if f and typeof(v) == "Vector3" then
		local ok, k = pcall(f, model)
		if ok and type(k) == "number" and k == k and k > 0 and k ~= 1 then
			return v * k
		end
	end
	return v
end
function RagdollService.Jolt(model, vel, force)
	if not states[model] or typeof(vel) ~= "Vector3" or vel.X ~= vel.X then
		return false
	end
	vel = scaledPush(model, vel)
	local st = states[model]
	if st.lend then
		-- HitReactServer nudges every body that just lost health, two defers after the blow - which took a body back
		-- the frame after it had been lent (measured: lent for exactly one frame). The blow already threw it.
		if not force and os.clock() - st.lend.at < 0.3 then
			return false
		end
		-- the lender's client is simulating it, so the push is applied THERE. (2026-11-14) an unforced nudge too: it
		-- used to take the body back to the server in mid-flight, which that client saw as a jump backwards
		if RagdollService.clientJolt and st.lend.player.Parent then
			RagdollService.clientJolt(st.lend.player, model, vel)
			if force then
				st.lastHit = os.clock()
			end
			return true
		end
		reclaim(model, st)
	elseif force then
		noteClaim(model, st, os.clock())
	end
	if vel.Magnitude > CFG.MaxFlingSpeed then
		vel = vel.Unit * CFG.MaxFlingSpeed
	end
	for _, p in ipairs(bodyParts(model)) do
		if not p.Anchored then
			p.AssemblyLinearVelocity += vel * (WHIP[p.Name] or 1)
		end
	end
	return true
end

function RagdollService.Fling(model, linearVelocity, angularVelocity, duration)
	if playerBody(model) then
		local P = pvp()
		return P ~= nil and P.knock(model, linearVelocity, duration or 1.2) or false
	end
	if not states[model] and unstoppable(model) then
		return false
	end
	if not states[model] and absorbed(model) then
		local hrp = model:FindFirstChild("HumanoidRootPart")
		local lv = typeof(linearVelocity) == "Vector3" and Vector3.new(linearVelocity.X, 0, linearVelocity.Z) or Vector3.zero
		if hrp and not hrp.Anchored and lv.Magnitude > 1 then
			hrp.AssemblyLinearVelocity = lv.Unit * math.min(lv.Magnitude * 0.15, 14)
		end
		return false
	end
	if not RagdollService.Ragdoll(model, duration) then
		return false
	end
	local v = scaledPush(model, linearVelocity or Vector3.zero)
	if v.Magnitude > CFG.MaxFlingSpeed then
		v = v.Unit * CFG.MaxFlingSpeed
	end
	local w = angularVelocity or randomUnit() * CFG.DefaultSpin
	if w.Magnitude > CFG.MaxSpin then
		w = w.Unit * CFG.MaxSpin
	end
	-- every limb is its own assembly now. The hit lands on the chest: the torso leads and the head and limbs trail,
	-- so the loose joints fold the body into a C around the push (a whiplash) instead of it flying as one rigid piece
	for _, p in ipairs(bodyParts(model)) do
		p.AssemblyLinearVelocity = v * (WHIP[p.Name] or 1)
	end
	-- and it tips back over the push (head first along it), on top of whatever spin the caller asked for
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude > 1 then
		local tip = Vector3.yAxis:Cross(flat.Unit) * math.min(flat.Magnitude * (CFG.TipBack or 0), CFG.TipMax or 0)
		w += tip
		if w.Magnitude > CFG.MaxSpin then
			w = w.Unit * CFG.MaxSpin
		end
	end
	for _, n in ipairs({ "UpperTorso", "LowerTorso" }) do
		local p = model:FindFirstChild(n)
		if p then
			p.AssemblyAngularVelocity = w
		end
	end
	return true
end

-- hand a ragdolled body to a player's client (see LEND above). Call it AFTER the server has set the velocities.
function RagdollService.Lend(model, player, seconds)
	local st = states[model]
	if not st or not player or not player.Parent or playerBody(model) then
		return false
	end
	if held(model) then
		return false
	end
	local t = os.clock()
	st.want = nil
	if st.lend and st.lend.player.Parent then -- already out on loan: keep it where it is, just restart the clock
		st.lend.at, st.lend.maxT = t, seconds and (t + seconds) or nil
		return true
	end
	-- (2026-11-14) no time limit unless one is asked for: it stays with them until the server needs it or they leave
	st.lend = { player = player, at = t, maxT = seconds and (t + seconds) or nil }
	lendParts(model, player)
	return true
end
-- (2026-11-14) "it is down / keep it down for this long" with NO push to follow: unlike Ragdoll() it does not take a
-- body back from the client that is simulating it (Sandbox.Injury calls this when a wound puts a body down - in
-- mid-flight, that take-back was a visible jump backwards)
function RagdollService.Stay(model, duration)
	local st = states[model]
	if not st then
		return RagdollService.Ragdoll(model, duration)
	end
	local t = os.clock()
	if duration == nil then
		st.permanent = true
		st.getUpAt = nil
	elseif not st.permanent then
		st.getUpAt = math.max(st.getUpAt or 0, t + duration)
	end
	return true
end
-- the server is about to push this body with its own code (a kit's impulse): make sure the push will land
function RagdollService.Claim(model)
	local st = states[model]
	if st then
		reclaim(model, st)
		noteClaim(model, st, os.clock())
	end
end
-- keep it on the server for `seconds`, and after that until it is calm: something the server moves (a train, a
-- wrecking ball) threw it, and it has to stay in step with that on every screen
function RagdollService.Hold(model, seconds)
	local st = states[model]
	if st then
		reclaim(model, st)
		st.serverUntil = math.max(st.serverUntil or 0, os.clock() + (seconds or 1))
		st.want, st.calmOnly, st.calm = nil, true, 0
	end
end
function RagdollService.LendNearest(model, maxDist, seconds)
	local root = model:FindFirstChild("UpperTorso") or model.PrimaryPart
	if not root then
		return false
	end
	local best, bd
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - root.Position).Magnitude
			if d <= (maxDist or 90) and (not bd or d < bd) then
				best, bd = p, d
			end
		end
	end
	return best ~= nil and RagdollService.Lend(model, best, seconds)
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for model, n in pairs(standing) do
		if n <= 0 or not model.Parent or states[model] then
			standing[model] = nil
		else
			standing[model] = n - 1
			claimServer(model)
		end
	end
	for model, st in pairs(states) do
		if model.Parent then
			local root = model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso")
			local isHeld = held(model)
			if st.lend then
				local L = st.lend
				if not L.again then
					L.again = true
					lendParts(model, L.player)
				end
				local back = not L.player.Parent or isHeld or (L.maxT ~= nil and t >= L.maxT)
				if not back and t >= (L.checkAt or 0) then
					L.checkAt = t + ((t - L.at < 1) and 0.1 or 1) -- (often at first: the limbs come apart over the first steps)
					local hrp = L.player.Character and L.player.Character:FindFirstChild("HumanoidRootPart")
					back = not hrp or not root or (hrp.Position - root.Position).Magnitude > OWN.FAR
					if not back and autoOwned(root) then
						lendParts(model, L.player) -- a limb came loose since: its new assembly started on automatic
					end
				end
				if back then
					reclaim(model, st)
					st.want, st.calmOnly, st.calm, st.assert = nil, true, 0, 2
				end
			else
				if (st.assert or 0) > 0 then
					st.assert -= 1
					claimServer(model)
				elseif root and t >= (st.autoAt or 0) then
					st.autoAt = t + 0.5
					if autoOwned(root) then
						claimServer(model)
					end
				end
				if not isHeld and t >= (st.serverUntil or 0) then
					local target = nil
					local function nearest()
						local best, bd
						for _, p in ipairs(Players:GetPlayers()) do
							local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
							local d = hrp and root and (hrp.Position - root.Position).Magnitude
							if d and d <= OWN.NEAR and (not bd or d < bd) then
								best, bd = p, d
							end
						end
						return best
					end
					if st.want then
						if st.want == "near" then
							target = nearest()
						else
							local hrp = st.want.Parent and st.want.Character and st.want.Character:FindFirstChild("HumanoidRootPart")
							if hrp and root and (hrp.Position - root.Position).Magnitude <= OWN.HINT_RANGE then
								target = st.want
							else
								target = nearest()
							end
						end
						st.want = nil
						if not target then
							st.calmOnly = true -- nobody near enough: the server's, until someone is and it is calm
						end
					end
					if not target and st.calmOnly ~= false then
						st.calm = (torsoSpeed(model) < OWN.CALM_SPEED) and ((st.calm or 0) + 1) or 0
						if st.calm >= OWN.CALM_FRAMES and t >= (st.seekAt or 0) then
							target = nearest()
							if not target then
								st.seekAt = t + 1
							end
						end
					end
					if target then
						st.lend = { player = target, at = t }
						lendParts(model, target)
					end
				end
			end
		end
		-- (2026-11-14) down means Physics: a body that has slipped out of it (it comes back from a client that owned it
		-- in Running) is put straight back, before its humanoid can steer it round in circles
		local h = st.hum
		if model.Parent and h and h.Parent and not st.lend and h.Health > 0 then
			local s = h:GetState()
			if s ~= Enum.HumanoidStateType.Physics and s ~= Enum.HumanoidStateType.Dead then
				h:Move(Vector3.zero)
				h:ChangeState(Enum.HumanoidStateType.Physics)
				RagdollService.stateFixes = (RagdollService.stateFixes or 0) + 1
			end
		end
		if not model.Parent then
			states[model] = nil
		elseif st.getUpAt and t >= st.getUpAt and isAlive(model) and not model:GetAttribute("GrabbedBy") and not model:GetAttribute("Hurt") then -- Hurt: Sandbox.Injury, a wounded body stays down
			local since = t - st.lastHit
			if since >= CFG.MinRagdollTime then
				local settled = torsoSpeed(model) < CFG.SettleSpeed
				local forced = since >= CFG.MaxRagdollTime and (groundBelow(model, 4) ~= nil or since >= CFG.MaxRagdollTime + 4)
				if settled or forced then
					RagdollService.Unragdoll(model)
				end
			end
		end
	end
end)

return RagdollService
