--!nocheck
-- PlaygroundService: the ragdoll playground's interactive props (trampolines, launch pads, conveyor + cannon,
-- spinner, wrecking ball, merry-go-round, wind fan, lava, explosive barrels, bowling pins, swings) and impact damage.
-- Each prop is found by CollectionService tag and tuned with attributes on the instance, so stations can be
-- duplicated or retuned in Studio without touching code.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("GojoShared")
local NPCCFG = require(Shared:WaitForChild("Config"):WaitForChild("NPC"))
local AbilityEvent = Shared:WaitForChild("Remotes"):WaitForChild("AbilityEvent")
local GojoServer = ServerScriptService:WaitForChild("GojoServer")
local RagdollService = require(GojoServer:WaitForChild("RagdollService"))
local WorldBlast = GojoServer:WaitForChild("WorldBlast", 10)
RagdollService.Init()

local NPC_TAG = NPCCFG.Tag
local IMPACT_THRESHOLD = 150 -- studs/s of speed lost in one tick before a landing starts to hurt
local IMPACT_DAMAGE = 0.9    -- damage per stud/s above the threshold

local function now()
	return os.clock()
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function flatRandom(mag)
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a)) * mag
end

local function alive(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model:GetAttribute("Dead") ~= true, hum
end

local function torso(model)
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso") or model:FindFirstChild("HumanoidRootPart")
end

local function bodyPoints(model)
	local pts = {}
	for _, n in ipairs({ "UpperTorso", "LowerTorso", "Head", "LeftLowerLeg", "RightLowerLeg" }) do
		local p = model:FindFirstChild(n)
		if p then
			table.insert(pts, p.Position)
		end
	end
	return pts
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.MaxParts = 500
-- every NPC model (alive or corpse) with a part inside the box
local function npcsInBox(cf, size)
	local folder = workspace:FindFirstChild("NPCs")
	if not folder then
		return {}
	end
	overlap.FilterDescendantsInstances = { folder }
	local found, seen = {}, {}
	for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size, overlap)) do
		local m = p:FindFirstAncestorOfClass("Model")
		while m and not CollectionService:HasTag(m, NPC_TAG) do
			m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
		end
		if m and not seen[m] then
			seen[m] = true
			table.insert(found, m)
		end
	end
	return found
end

-- per-prop, per-model cooldowns so a body is not re-triggered every frame
local stores = {}
local function ready(key, model, cd)
	local st = stores[key]
	if not st then
		st = {}
		stores[key] = st
	end
	local t = st[model]
	if t and now() - t < cd then
		return false
	end
	st[model] = now()
	return true
end

-- every launch goes through here: telekinesis (Blue grab) always wins over a prop
local function launch(model, v, spin, duration)
	if model:GetAttribute("GrabbedBy") or model:GetAttribute("InDomain") then
		return false
	end
	return RagdollService.Fling(model, v, spin, duration or 3)
end

local lastFx = {}
local function fx(kind, data, throttleKey, gap)
	if throttleKey then
		local t = lastFx[throttleKey]
		if t and now() - t < gap then
			return
		end
		lastFx[throttleKey] = now()
	end
	AbilityEvent:FireAllClients(kind, data)
end

local function claimServer(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				if d:CanSetNetworkOwnership() then
					d:SetNetworkOwner(nil)
				end
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- trampolines: bounce anything that lands on the pad (60 Hz so fast fallers never skip the zone)
local bouncedAt = {}
local function updateTrampolines()
	for _, pad in ipairs(CollectionService:GetTagged("Trampoline")) do
		if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) then
			local d = pad:GetAttribute("Diameter") or 12
			local bounce = pad:GetAttribute("Bounce") or 150
			for _, m in ipairs(npcsInBox(CFrame.new(pad.Position + Vector3.new(0, 4, 0)), Vector3.new(d * 0.92, 8, d * 0.92))) do
				local t = torso(m)
				if t and t.AssemblyLinearVelocity.Y < 25 and ready(pad, m, 0.3) then
					local v = t.AssemblyLinearVelocity
					local h = Vector3.new(v.X, 0, v.Z) * 0.55 + flatRandom(math.random(3, 9))
					bouncedAt[m] = now()
					launch(m, h + Vector3.yAxis * bounce, randomUnit() * math.random(4, 12), 3)
					fx("PropBoing", { pos = pad.Position, size = d, pad = pad }, pad, 0.12)
				end
			end
		end
	end
end

-- launch pads: one-shot fling along the pad's facing (Power) plus straight up (Up)
local function updateLaunchPads()
	for _, pad in ipairs(CollectionService:GetTagged("LaunchPad")) do
		if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) then
			for _, m in ipairs(npcsInBox(pad.CFrame * CFrame.new(0, 3, 0), Vector3.new(pad.Size.X, 6, pad.Size.Z))) do
				if ready(pad, m, 1) then
					local look = pad.CFrame.LookVector * Vector3.new(1, 0, 1)
					local dir = look.Magnitude > 0.01 and look.Unit or Vector3.zero
					local power, up = pad:GetAttribute("Power") or 100, pad:GetAttribute("Up") or 100
					launch(m, dir * power + Vector3.yAxis * up + flatRandom(3), randomUnit() * 10, 4)
					fx("PropLaunch", { pos = pad.Position, up = up }, pad, 0.2)
				end
			end
		end
	end
end

-- conveyors: an anchored part's velocity carries whatever lies on it; NPCs who step on lose their footing, and
-- bodies riding it are kept down and nudged up to belt speed so they always arrive at the end (the cannon)
local function updateConveyors()
	for _, belt in ipairs(CollectionService:GetTagged("Conveyor")) do
		if belt:IsA("BasePart") and belt:IsDescendantOf(workspace) then
			local dir = belt.CFrame.LookVector
			local speed = belt:GetAttribute("Speed") or 16
			for _, m in ipairs(npcsInBox(belt.CFrame * CFrame.new(0, 3, 0), Vector3.new(belt.Size.X, 6, belt.Size.Z))) do
				if not m:GetAttribute("GrabbedBy") then
					if not m:GetAttribute("Ragdolled") then
						launch(m, dir * speed + Vector3.yAxis * 8, randomUnit() * 4, 5)
					else
						RagdollService.Ragdoll(m, 2)
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") then
								local v = p.AssemblyLinearVelocity
								local along = v:Dot(dir)
								if along < speed then
									p.AssemblyLinearVelocity = v + dir * (speed - along) * 0.3
								end
							end
						end
					end
				end
			end
		end
	end
end

local function setupConveyor(belt)
	local function apply()
		belt.AssemblyLinearVelocity = belt.CFrame.LookVector * (belt:GetAttribute("Speed") or 16)
	end
	apply()
	belt:GetAttributeChangedSignal("Speed"):Connect(apply)
end

---------------------------------------------------------------------------------------------------
-- cannon: whatever reaches the LoadZone is stuffed in the barrel, the fuse burns, and it is fired on a ballistic
-- arc that lands on the cannon's Target
local cannonState = {}

local function ballisticSpeed(from, to, dir)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		return 200
	end
	flat = flat.Unit
	local theta = math.asin(math.clamp(dir.Y, -0.99, 0.99))
	local R = (to - from):Dot(flat)
	local dy = to.Y - from.Y
	local denom = 2 * math.cos(theta) ^ 2 * (R * math.tan(theta) - dy)
	if R <= 0 or denom <= 0 then
		return 200
	end
	return math.clamp(math.sqrt(workspace.Gravity * R * R / denom), 60, 310)
end

local function setParts(model, fn)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function fireCannon(cm, st, m)
	local dir = cm:GetAttribute("AimDir") or Vector3.new(0, 0.6, -0.8).Unit
	local muzzle = cm:GetAttribute("Muzzle") or cm:GetPivot().Position
	local target = cm:GetAttribute("Target") or (muzzle + dir * 200)
	local fuse = cm:GetAttribute("FuseTime") or 0.8
	-- load: freeze the body inside the barrel while the fuse burns
	RagdollService.Ragdoll(m, fuse + 4)
	setParts(m, function(p)
		p.Anchored = true
	end)
	m:PivotTo(CFrame.lookAt(muzzle - dir * 9, muzzle - dir * 9 + dir) * CFrame.Angles(math.rad(-90), 0, 0))
	fx("PropFuse", { pos = muzzle - dir * 12, cannon = cm })
	task.wait(fuse)
	if m.Parent then
		m:PivotTo(CFrame.new(muzzle + dir * 2.5))
		setParts(m, function(p)
			p.Anchored = false
		end)
		claimServer(m)
		launch(m, dir * ballisticSpeed(muzzle, target, dir), randomUnit() * 14, 6)
		fx("PropCannon", { pos = muzzle, dir = dir })
	end
	st.busy = false
	st.readyAt = now() + (cm:GetAttribute("Cooldown") or 1.6)
end

local function updateCannons()
	for _, cm in ipairs(CollectionService:GetTagged("Cannon")) do
		local st = cannonState[cm]
		if not st then
			st = { busy = false, readyAt = 0 }
			cannonState[cm] = st
		end
		local zone = cm:FindFirstChild("LoadZone")
		if zone and not st.busy and now() >= st.readyAt then
			for _, m in ipairs(npcsInBox(zone.CFrame, zone.Size)) do
				if not m:GetAttribute("GrabbedBy") then
					st.busy = true
					task.spawn(fireCannon, cm, st, m)
					break
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- spinner: a real motor-driven bar; on top of the physical contact we make every hit a clean, readable smack
local function updateSpinners()
	for _, sm in ipairs(CollectionService:GetTagged("Spinner")) do
		local bar, hub = sm:FindFirstChild("Bar"), sm:FindFirstChild("Hub")
		if bar and hub then
			local center = hub.Position
			local half = bar.Size.X / 2
			local axis = bar.CFrame.RightVector
			local a, b = bar.Position - axis * half, bar.Position + axis * half
			local w = hub.AssemblyAngularVelocity
			for _, m in ipairs(npcsInBox(CFrame.new(center), Vector3.new(half * 2 + 6, 10, half * 2 + 6))) do
				for _, p in ipairs(bodyPoints(m)) do
					local ab = b - a
					local tt = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
					local closest = a + ab * tt
					local off = p - closest
					if math.abs(off.Y) <= 2.8 and (off * Vector3.new(1, 0, 1)).Magnitude <= 2.6 then
						if ready(sm, m, 0.6) then
							local r = (closest - center) * Vector3.new(1, 0, 1)
							local tangential = w:Cross(r)
							local dirT = tangential.Magnitude > 0.1 and tangential.Unit or flatRandom(1)
							local speed = math.max(tangential.Magnitude * (sm:GetAttribute("HitPower") or 1.5), 55)
							local outward = r.Magnitude > 0.1 and r.Unit or Vector3.zero
							launch(m, dirT * speed + outward * 15 + Vector3.yAxis * 38, randomUnit() * 16, 3)
							fx("PropSmack", { pos = closest }, m, 0.1)
						end
						break
					end
				end
			end
		end
	end
end

-- wrecking ball: a scripted pendulum (anchored, so it never loses energy) with clean hits
local t0 = now()
local function updateWreckingBalls()
	local t = now() - t0
	for _, wm in ipairs(CollectionService:GetTagged("WreckingBall")) do
		local ball, chain = wm:FindFirstChild("Ball"), wm:FindFirstChild("Chain")
		local pivot = wm:GetAttribute("Pivot")
		if ball and chain and pivot then
			local L = wm:GetAttribute("Length") or 26
			local A = math.rad(wm:GetAttribute("Amplitude") or 55)
			local omega = 2 * math.pi / (wm:GetAttribute("Period") or 4)
			local ang = A * math.sin(t * omega)
			local angVel = A * omega * math.cos(t * omega)
			local down = Vector3.new(math.sin(ang), -math.cos(ang), 0)
			local pos = pivot + down * L
			ball.CFrame = CFrame.new(pos)
			local up = -down
			local len = L - ball.Size.X / 2
			chain.Size = Vector3.new(chain.Size.X, len, chain.Size.Z)
			chain.CFrame = CFrame.fromMatrix(pivot + down * (len / 2), up:Cross(Vector3.zAxis).Unit, up)
			local vel = Vector3.new(math.cos(ang), math.sin(ang), 0) * angVel * L
			local reach = ball.Size.X / 2 + 1.3
			for _, m in ipairs(npcsInBox(CFrame.new(pos), Vector3.one * (reach * 2 + 2))) do
				for _, p in ipairs(bodyPoints(m)) do
					if (p - pos).Magnitude <= reach then
						if ready(wm, m, 0.7) then
							local dir = vel.Magnitude > 1 and vel.Unit or (p - pos).Unit
							launch(m, dir * math.max(vel.Magnitude * 2.2, 95) + Vector3.yAxis * 40, randomUnit() * 18, 3)
							fx("PropSmack", { pos = p, big = true }, m, 0.1)
						end
						break
					end
				end
			end
		end
	end
end

-- merry-go-round: a real spinning disk; anyone riding it loses their footing and is thrown off the rim
local riding = {}
local function updateMerryGoRounds()
	for _, mm in ipairs(CollectionService:GetTagged("MerryGoRound")) do
		local disk = mm:FindFirstChild("Disk")
		if disk then
			local c = disk.Position
			local R = mm:GetAttribute("Radius") or 15
			local w = disk.AssemblyAngularVelocity
			for _, m in ipairs(npcsInBox(CFrame.new(c + Vector3.new(0, 3, 0)), Vector3.new(R * 2, 6, R * 2))) do
				local t = torso(m)
				if t then
					local r = (t.Position - c) * Vector3.new(1, 0, 1)
					if r.Magnitude <= R then
						if not m:GetAttribute("Ragdolled") then
							launch(m, w:Cross(r) + Vector3.yAxis * 10, nil, 4)
							riding[m] = now()
						else
							riding[m] = riding[m] or now()
							if now() - riding[m] > 1.1 then
								riding[m] = nil
								local tangential = w:Cross(r)
								local out = r.Magnitude > 0.1 and r.Unit or flatRandom(1)
								launch(m, tangential * 1.7 + out * 40 + Vector3.yAxis * 34, randomUnit() * 14, 3)
								fx("PropLaunch", { pos = t.Position, up = 30, quiet = true }, m, 0.3)
							end
						end
					end
				end
			end
		end
	end
end

-- wind fan: continuous push along the zone's facing while inside the WindZone
local function updateFans(dt)
	for _, fm in ipairs(CollectionService:GetTagged("WindFan")) do
		local zone = fm:FindFirstChild("WindZone")
		if zone then
			local dir = zone.CFrame.LookVector
			local force = fm:GetAttribute("Force") or 300
			local lift = fm:GetAttribute("Lift") or 60
			for _, m in ipairs(npcsInBox(zone.CFrame, zone.Size)) do
				if not m:GetAttribute("GrabbedBy") then
					if not m:GetAttribute("Ragdolled") then
						launch(m, dir * 30 + Vector3.yAxis * 25, nil, 3)
					else
						RagdollService.Ragdoll(m, 2.5) -- stay down while the wind has you
						local add = (dir * force + Vector3.yAxis * lift) * dt
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") then
								local v = p.AssemblyLinearVelocity + add
								if v:Dot(dir) > 140 then
									v -= dir * (v:Dot(dir) - 140)
								end
								p.AssemblyLinearVelocity = v
							end
						end
					end
				end
			end
		end
	end
end

-- lava: burns, hops and eventually chars whatever stands in it
local function updateLava(dt)
	for _, lava in ipairs(CollectionService:GetTagged("Lava")) do
		if lava:IsA("BasePart") then
			local dps = lava:GetAttribute("DPS") or 35
			local hop = lava:GetAttribute("Hop") or 50
			for _, m in ipairs(npcsInBox(lava.CFrame * CFrame.new(0, 3, 0), Vector3.new(lava.Size.X, 6, lava.Size.Z))) do
				local isAlive, hum = alive(m)
				if isAlive then
					hum:TakeDamage(dps * dt)
				end
				m:SetAttribute("Burning", workspace:GetServerTimeNow() + 3)
				if ready(lava, m, 0.6) then
					launch(m, flatRandom(math.random(8, 16)) + Vector3.yAxis * hop, randomUnit() * 10, 3)
					local t = torso(m)
					fx("PropSizzle", { pos = t and t.Position or lava.Position }, lava, 0.25)
				end
				if not isAlive and not m:GetAttribute("Charred") then
					m:SetAttribute("Charred", true)
					setParts(m, function(p)
						if p.Name ~= "HumanoidRootPart" then
							p.Color = p.Color:Lerp(Color3.fromRGB(26, 22, 20), 0.75)
						end
					end)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- explosive barrels: pop on a hard hit, on purple/punch blasts, and chain into each other
local barrels = {}
local explode

local function registerBarrel(b)
	if barrels[b] or not b:IsA("BasePart") then
		return
	end
	local st = { alive = true, parts = {} }
	for _, p in ipairs({ b, table.unpack(b:GetDescendants()) }) do
		if p:IsA("BasePart") then
			st.parts[p] = { tr = p.Transparency, cc = p.CanCollide, cq = p.CanQuery }
		end
	end
	barrels[b] = st
	b.Touched:Connect(function(other)
		if not st.alive or other:IsDescendantOf(b) then
			return
		end
		local speed = (other.AssemblyLinearVelocity - b.AssemblyLinearVelocity).Magnitude
		if speed > 45 then
			local m = other:FindFirstAncestorOfClass("Model")
			explode(b, m and m:GetAttribute("LastHitBy"))
		end
	end)
end

explode = function(b, creditUserId)
	local st = barrels[b]
	if not st or not st.alive or not b.Parent then
		return
	end
	st.alive = false
	local pos = b.Position
	local radius = b:GetAttribute("Radius") or 22
	local power = b:GetAttribute("Power") or 150
	local damage = b:GetAttribute("Damage") or 70
	for p in pairs(st.parts) do
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
	end
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = radius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Parent = workspace
	fx("PropExplode", { pos = pos, radius = radius })
	for _, m in ipairs(npcsInBox(CFrame.new(pos), Vector3.one * radius * 2)) do
		local t = torso(m)
		if t then
			local off = t.Position - pos
			local d = off.Magnitude
			if d <= radius then
				local k = 1 - (d / radius) * 0.6
				local isAlive, hum = alive(m)
				if isAlive then
					if creditUserId then
						m:SetAttribute("LastHitBy", creditUserId)
					end
					hum:TakeDamage(damage * k)
				end
				local dir = ((d > 0.1 and off.Unit or flatRandom(1)) + Vector3.yAxis * 0.8).Unit
				launch(m, dir * power * k, randomUnit() * 20, 3)
			end
		end
	end
	for other, ost in pairs(barrels) do
		if ost.alive and other ~= b and (other.Position - pos).Magnitude <= radius * 0.75 then
			task.delay(0.12 + math.random() * 0.12, explode, other, creditUserId)
		end
	end
	task.delay(b:GetAttribute("Respawn") or 10, function()
		if not b.Parent then
			return
		end
		for p, o in pairs(st.parts) do
			p.Transparency = o.tr
			p.CanCollide = o.cc
			p.CanQuery = o.cq
		end
		st.alive = true
		fx("PropRespawn", { pos = pos })
	end)
end

if WorldBlast then
	WorldBlast.Event:Connect(function(pos, radius, userId)
		if typeof(pos) ~= "Vector3" then
			return
		end
		radius = tonumber(radius) or 6
		for b, st in pairs(barrels) do
			if st.alive and (b.Position - pos).Magnitude <= radius + 2 then
				explode(b, userId)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- bowling: pins reset themselves a few seconds after they are knocked
local bowling = {}
local function setupBowling(bm)
	local pins = bm:FindFirstChild("Pins")
	if not pins then
		return
	end
	local st = { pins = {}, knockedAt = nil, reported = false }
	for _, p in ipairs(pins:GetChildren()) do
		if p:IsA("BasePart") then
			st.pins[p] = p.CFrame
		end
	end
	bowling[bm] = st
	claimServer(pins)
end

local function updateBowling()
	for bm, st in pairs(bowling) do
		local down = 0
		for p, cf in pairs(st.pins) do
			if p.Parent and ((p.Position - cf.Position).Magnitude > 1.5 or p.CFrame.RightVector.Y < 0.8) then
				down += 1
			end
		end
		if down > 0 and not st.knockedAt then
			st.knockedAt = now()
			st.reported = false
		end
		if st.knockedAt and not st.reported and now() - st.knockedAt > 2.5 then
			st.reported = true
			local any = next(st.pins)
			fx("PropBowling", { pos = (any and st.pins[any].Position or bm:GetPivot().Position) + Vector3.new(0, 6, 0), count = down })
		end
		if st.knockedAt and now() - st.knockedAt > (bm:GetAttribute("ResetDelay") or 6) then
			st.knockedAt = nil
			for p, cf in pairs(st.pins) do
				if p.Parent then
					p.Anchored = true
					p.CFrame = cf
					p.AssemblyLinearVelocity = Vector3.zero
					p.AssemblyAngularVelocity = Vector3.zero
					p.Anchored = false
				end
			end
			claimServer(bm)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- impact damage: a ragdoll that loses a lot of speed in one tick hit something hard (falls, throws, cannon)
local lastSpeed = {}
local function updateImpacts()
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		local t = m:FindFirstChild("UpperTorso")
		if t and m:GetAttribute("Ragdolled") and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("InDomain") then
			local s = t.AssemblyLinearVelocity.Magnitude
			local prev = lastSpeed[m]
			local bounced = bouncedAt[m] and now() - bouncedAt[m] < 0.35
			if prev and not bounced and prev - s > IMPACT_THRESHOLD then
				local isAlive, hum = alive(m)
				if isAlive then
					hum:TakeDamage((prev - s - IMPACT_THRESHOLD) * IMPACT_DAMAGE)
				end
				fx("PropThud", { pos = t.Position, hard = prev - s > 220 }, m, 0.3)
			end
			lastSpeed[m] = s
		else
			lastSpeed[m] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- registration (existing + added later) and the update loops
for _, belt in ipairs(CollectionService:GetTagged("Conveyor")) do
	setupConveyor(belt)
end
CollectionService:GetInstanceAddedSignal("Conveyor"):Connect(setupConveyor)
for _, b in ipairs(CollectionService:GetTagged("ExplosiveBarrel")) do
	registerBarrel(b)
end
CollectionService:GetInstanceAddedSignal("ExplosiveBarrel"):Connect(registerBarrel)
for _, bm in ipairs(CollectionService:GetTagged("BowlingPins")) do
	setupBowling(bm)
end
task.defer(function()
	-- physical props run on the server so every client sees the same spin / swing
	local pg = workspace:FindFirstChild("Playground")
	if pg then
		claimServer(pg)
	end
end)

local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Playground] " .. tostring(err))
	end
end

local slowAcc = 0
RunService.Heartbeat:Connect(function(dt)
	safe(updateTrampolines)
	safe(updateWreckingBalls)
	safe(updateFans, dt)
	safe(updateSpinners)
	slowAcc += dt
	if slowAcc >= 1 / 30 then
		local step = slowAcc
		slowAcc = 0
		safe(updateLaunchPads)
		safe(updateConveyors)
		safe(updateCannons)
		safe(updateMerryGoRounds)
		safe(updateLava, step)
		safe(updateImpacts)
		safe(updateBowling)
	end
end)

-- forget models that no longer exist
task.spawn(function()
	while true do
		task.wait(5)
		for _, st in pairs(stores) do
			for m in pairs(st) do
				if typeof(m) == "Instance" and not m.Parent then
					st[m] = nil
				end
			end
		end
		for m in pairs(lastSpeed) do
			if not m.Parent then
				lastSpeed[m] = nil
			end
		end
		for m in pairs(riding) do
			if not m.Parent then
				riding[m] = nil
			end
		end
		for m in pairs(bouncedAt) do
			if not m.Parent then
				bouncedAt[m] = nil
			end
		end
	end
end)

print("[Playground] online")
