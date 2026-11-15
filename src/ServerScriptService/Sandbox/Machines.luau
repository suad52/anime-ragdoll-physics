--!nocheck
-- ServerScriptService.Sandbox.Machines (2026-11-13): the open test ground's toys. Like Hazards, the map only carries
-- tags + attributes (ServerStorage.SandboxGen builds them) and this gives them behaviour:
--   Switch (Group, On, Label)  every instance in the same site with that Group gets On; Rotor hinge motors follow it
--   FanZone (Power, FanAt)     wind along the zone's LookVector, suction behind the fan
--   ChopZone (Damage, Sever, Fling | Arms, Radius)  blades: a flat zone, or only where a rotor arm is passing
--   GrindZone (Damage)         chews what falls between the rollers, then it is gone
--   Dispenser (Drop, Cap, Rag, Life)  a button that drops a fresh dummy
--   BigPress + PressButton - Train - CraneHook + CraneLower + CraneDrop - CannonLoad + CannonFire (Breech, Muzzle)
--   WreckSwing (WreckBall) - BrickWall - Mine - Tesla - CrateSpawn
-- M.init(ctx): ctx = { Hazards, Injury, Dummies, Ragdoll, net, credit }
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local C = Color3.fromRGB
local M = {}
local LIMBS = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "Head" }
M.LIMBS = LIMBS

function M.init(ctx)
	local H, Injury, Dummies, Ragdoll, net = ctx.Hazards, ctx.Injury, ctx.Dummies, ctx.Ragdoll, ctx.net
	local hurt, sfx, onPrompt = H.hurt, H.sfx, H.onPrompt
	H.SND.roar, H.SND.roar2, H.SND.growl, H.SND.splash = 9113980319, 9113980644, 9114628818, 9125703162
	Dummies.CAP = 215 -- (2026-11-15) 63 posted at the sandbox's machines + 15 in the Ruins + 30 + 75 wanderers = 183; stations stop 12 short of the cap, ~20 left for player spawns
	local map = workspace:WaitForChild("Map")
	local function tagged(tag)
		return CollectionService:GetTagged(tag)
	end
	local function siteOf(inst)
		local m = inst
		while m and m.Parent ~= map do
			m = m.Parent
		end
		return m
	end
	local function promptOf(b)
		return b:FindFirstChildOfClass("ProximityPrompt")
	end
	local function lamp(b, color)
		local l = b:FindFirstChild("Lamp")
		if l then
			l.Color = color
			l.Material = Enum.Material.Neon
		end
	end
	local function lastBy(m)
		local uid = m:GetAttribute("LastHitBy")
		return uid and Players:GetPlayerByUserId(uid) or nil
	end
	local npc = OverlapParams.new()
	npc.FilterType = Enum.RaycastFilterType.Include
	local loose = OverlapParams.new()
	loose.FilterType = Enum.RaycastFilterType.Include
	-- dummies with a part in the box: list of models, and [model] = its parts in there
	local MOVER_LAG = 0.14 -- (2026-11-14) how late a client sees a mover the server simulates, less the time a lent body takes to react
	local function dummiesIn(cf, size)
		npc.FilterDescendantsInstances = { Dummies.folder }
		local list, parts = {}, {}
		for _, part in ipairs(workspace:GetPartBoundsInBox(cf, size, npc)) do
			local m = Dummies.of(part)
			if m then
				if not parts[m] then
					parts[m] = {}
					table.insert(list, m)
				end
				table.insert(parts[m], part)
			end
		end
		return list, parts
	end
	M.dummiesIn = dummiesIn
	-- loose props and severed limbs (everything unanchored in workspace.Gore)
	local function looseIn(cf, size)
		loose.FilterDescendantsInstances = { Injury.gore() }
		local out = {}
		for _, p in ipairs(workspace:GetPartBoundsInBox(cf, size, loose)) do
			if not p.Anchored then
				table.insert(out, p)
			end
		end
		return out
	end
	local function charsIn(cf, size)
		local out = {}
		local half = size / 2
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then
				local l = cf:PointToObjectSpace(hrp.Position)
				if math.abs(l.X) < half.X and math.abs(l.Y) < half.Y and math.abs(l.Z) < half.Z then
					table.insert(out, { plr = plr, char = char, hrp = hrp, hum = hum })
				end
			end
		end
		return out
	end
	M.charsIn = charsIn
	local function flatten(m)
		if m:GetAttribute("Flat") then
			return
		end
		m:SetAttribute("Flat", true)
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				local up = p.CFrame:VectorToObjectSpace(Vector3.yAxis)
				local ax, ay, az = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
				local f
				if ax >= ay and ax >= az then
					f = Vector3.new(0.3, 1.25, 1.25)
				elseif ay >= az then
					f = Vector3.new(1.25, 0.3, 1.25)
				else
					f = Vector3.new(1.25, 1.25, 0.3)
				end
				p.Size = p.Size * f
				for _, a in ipairs(p:GetChildren()) do
					if a:IsA("Attachment") then
						a.Position = a.Position * f
					end
				end
			end
		end
	end

	------------------------------------------------------------------------------------------------ switches
	local groups = {}
	local function groupOf(inst)
		local site, g = siteOf(inst), inst:GetAttribute("Group")
		if not site or not g then
			return nil
		end
		groups[site] = groups[site] or {}
		local G = groups[site][g]
		if not G then
			G = { on = true, members = {}, rotors = {} }
			groups[site][g] = G
			for _, d in ipairs(site:GetDescendants()) do
				if d:GetAttribute("Group") == g then
					table.insert(G.members, d)
					if CollectionService:HasTag(d, "Rotor") then
						table.insert(G.rotors, d)
						pcall(function()
							d:SetNetworkOwner(nil)
						end)
					end
				end
			end
		end
		return G
	end
	local function setGroup(G, on)
		G.on = on
		for _, d in ipairs(G.members) do
			d:SetAttribute("On", on)
		end
		for _, r in ipairs(G.rotors) do
			local h = r:FindFirstChildOfClass("HingeConstraint")
			if h then
				h.AngularVelocity = on and (r:GetAttribute("Spin") or 6) or 0
			end
		end
	end
	for _, b in ipairs(tagged("Switch")) do
		local G = groupOf(b)
		local pp = promptOf(b)
		if G and pp then
			local name = b:GetAttribute("Label") or "it"
			local function show()
				pp.ActionText = (G.on and "Turn off " or "Turn on ") .. name
				lamp(b, G.on and C(80, 230, 120) or C(230, 70, 60))
			end
			setGroup(G, b:GetAttribute("On") ~= false)
			show()
			onPrompt(pp, function(player)
				setGroup(G, not G.on)
				G.by = player -- whoever threw the switch gets the credit for what the machine does
				show()
				sfx("zap", b.Position, 0.5, G.on and 1.2 or 0.7)
			end)
		end
	end

	------------------------------------------------------------------------------------------------ dispensers
	for _, b in ipairs(tagged("Dispenser")) do
		local pp = promptOf(b)
		local mine = {}
		if pp then
			onPrompt(pp, function(player)
				for i = #mine, 1, -1 do
					if not Dummies.is(mine[i]) then
						table.remove(mine, i)
					end
				end
				if #mine >= (b:GetAttribute("Cap") or 4) then
					Dummies.remove(table.remove(mine, 1), true)
				end
				local cf = b:GetAttribute("Drop")
				if typeof(cf) ~= "CFrame" then
					return
				end
				local m = Dummies.spawn(cf * CFrame.new(math.random(-2, 2), 0, math.random(-2, 2)), { ragdoll = b:GetAttribute("Rag") or 2.5, life = b:GetAttribute("Life") or 45 })
				if m then
					table.insert(mine, m)
					if player then
						m:SetAttribute("LastHitBy", player.UserId)
					end
					sfx("whoosh", cf.Position, 0.5, 1.2)
				end
			end)
		end
	end

	------------------------------------------------------------------------------------------------ plank pushers
	-- (2026-11-13) the grinder's button shoves in whoever is standing on the plank (it used to drop a fresh dummy
	-- from a chute). Spot = where the body stands, LookVector = the way it goes; the part named Ram punches out.
	for _, b in ipairs(tagged("PlankPush")) do
		local site = siteOf(b)
		local pp = promptOf(b)
		local spot = b:GetAttribute("Spot")
		local ram = site and site:FindFirstChild("Ram", true)
		if pp and typeof(spot) == "CFrame" then
			local busy = false
			local home = ram and ram.CFrame
			onPrompt(pp, function(player)
				if busy then
					return
				end
				busy = true
				lamp(b, C(255, 200, 60))
				local dir = spot.LookVector
				-- EVERY body on the plank goes (tested: pushing only the nearest left one that had flopped onto the plank
				-- standing in the next one's way, and they piled up)
				local function onPlank(m)
					local t = m:FindFirstChild("UpperTorso") or m:FindFirstChild("LowerTorso")
					if not t or m:GetAttribute("Strapped") or m:GetAttribute("GrabbedBy") then
						return false
					end
					local l = spot:PointToObjectSpace(t.Position)
					return math.abs(l.X) < 3.5 and l.Z > -5 and l.Z < 6.5 and l.Y > -1.5 and l.Y < 7, t
				end
				local list = {}
				for m in pairs(Dummies.records) do
					if onPlank(m) then
						table.insert(list, m)
					end
				end
				if ram then
					TweenService:Create(ram, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = home + dir * (ram:GetAttribute("Travel") or 4) }):Play()
				end
				task.wait(0.08)
				sfx("heavy", spot.Position, 0.8, 1.3)
				local push = dir * 22 + Vector3.new(0, 8, 0)
				for _, m in ipairs(list) do
					if Dummies.is(m) then
						if player then
							m:SetAttribute("LastHitBy", player.UserId)
						end
						hurt(m, "LowerTorso", "blunt", 8, player, dir)
						if m:GetAttribute("Dead") or Ragdoll.IsRagdolled(m) then
							Ragdoll.Jolt(m, push, true)
						else
							Ragdoll.Fling(m, push, nil, 3)
						end
						if Ragdoll.LendNearest then
							Ragdoll.LendNearest(m, 120)
						end
					end
				end
				-- follow through: a body pushed the moment it spawned has been seen to drop onto the plank instead of
				-- leaving it, so anything still up there and barely moving gets shoved again
				for _ = 1, 2 do
					task.wait(0.16)
					for _, m in ipairs(list) do
						if Dummies.is(m) then
							local on, t = onPlank(m)
							if on and t.AssemblyLinearVelocity:Dot(dir) < 8 then
								Ragdoll.Ragdoll(m, 3)
								Ragdoll.Jolt(m, push, true)
							end
						end
					end
				end
				task.wait(0.1)
				if ram then
					local back = TweenService:Create(ram, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = home })
					back:Play()
					back.Completed:Wait()
				end
				lamp(b, C(60, 62, 70))
				busy = false
			end)
		end
	end

	------------------------------------------------------------------------------------------------ the crusher
	for _, b in ipairs(tagged("PressButton")) do
		local site = siteOf(b)
		local platen
		for _, d in ipairs(site:GetDescendants()) do
			if CollectionService:HasTag(d, "BigPress") then
				platen = d
			end
		end
		local pp = promptOf(b)
		local light = site:FindFirstChild("PressLight", true)
		if platen and pp then
			local home, travel, busy = platen.CFrame, platen:GetAttribute("Travel") or 12, false
			platen.CanCollide = false
			onPrompt(pp, function(player)
				if busy then
					return
				end
				busy = true
				lamp(b, C(255, 200, 60))
				if light then
					light.Color = C(255, 60, 50)
				end
				sfx("zap", platen.Position, 0.6, 0.6)
				task.wait(0.55)
				local down = home * CFrame.new(0, -travel, 0)
				local tw = TweenService:Create(platen, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = down })
				tw:Play()
				tw.Completed:Wait()
				sfx("heavy", down.Position, 1, 0.6)
				if net then
					net("boom", down.Position, 34)
				end
				local box = down * CFrame.new(0, -0.6, 0) -- the platen itself (it does not collide) and the gap under it
				local bsize = Vector3.new(platen.Size.X, platen.Size.Y + 3.4, platen.Size.Z)
				local list, parts = dummiesIn(box, bsize)
				for _, m in ipairs(list) do
					if player then
						m:SetAttribute("LastHitBy", player.UserId)
					end
					Ragdoll.Ragdoll(m, nil)
					for i = 1, math.min(5, #parts[m]) do
						hurt(m, parts[m][i], "crush", (platen:GetAttribute("Damage") or 140) * (i == 1 and 1 or 0.5), player, -Vector3.yAxis)
					end
					if not m:GetAttribute("Invuln") then
						flatten(m)
					end
					Injury.spurt(parts[m][1].Position, Vector3.yAxis, 20, 24)
				end
				for _, p in ipairs(looseIn(box, bsize)) do
					if not H.damageProp(p, 999, player) and p:GetAttribute("Kind") == "crate" then
						p:Destroy()
					end
				end
				for _, c in ipairs(charsIn(box, bsize + Vector3.new(0, 4, 0))) do
					c.hum.Health = 0
				end
				task.wait(0.9)
				local up = TweenService:Create(platen, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = home })
				up:Play()
				up.Completed:Wait()
				lamp(b, C(60, 62, 70))
				if light then
					light.Color = C(60, 62, 70)
				end
				busy = false
			end)
		end
	end

	------------------------------------------------------------------------------------------------ the train
	-- (2026-11-14) a mover the SERVER simulates is seen ~0.2 s late on a client, and a body handed to a client reacts
	-- there ~0.05-0.08 s after the server throws it. The train's blow is found 7.5 studs ahead of its nose (0.06 s at
	-- 120 studs/s), so it lands this much later - the body goes as the nose is SEEN to reach it. Tuned by measurement:
	-- at 0.235 the nose was 3.5-9.4 studs past the body when it was seen to move (before any of this: 8-26 past).
	local TRAIN_BODY_LAG = 0.19
	local TRAIN_VIEW_LAG = 0.225 -- the same for a player the train hits (their own client knocks them over)
	for _, train in ipairs(tagged("Train")) do
		task.spawn(function()
			local root = train.PrimaryPart
			local pc = root and root:FindFirstChildOfClass("PrismaticConstraint")
			if not pc then
				return
			end
			-- (2026-11-14) measured: the train kept going back to AUTOMATIC ownership - within 2-3 frames of every body it
			-- hit (a body a client simulates, overlapping it, takes the train with it) - so a nearby player's client drove
			-- it ~0.15 s ahead of the server, whose hit then landed after the nose was 8-26 studs past the body on that
			-- screen. One SetNetworkOwner(nil) does not hold: it is checked every step.
			local function own()
				pcall(function()
					if root:GetNetworkOwnershipAuto() or root:GetNetworkOwner() ~= nil then
						root:SetNetworkOwner(nil)
					end
				end)
			end
			own()
			game:GetService("RunService").Heartbeat:Connect(own)
			-- the blow is the script's (and waits TRAIN_BODY_LAG): the train must not also plough into the dummy bodily in
			-- the meantime, so it does not collide with them at all (players and loose props it still does)
			pcall(function()
				local PS = game:GetService("PhysicsService")
				if not PS:IsCollisionGroupRegistered("Movers") then
					PS:RegisterCollisionGroup("Movers")
				end
				PS:CollisionGroupSetCollidable("Movers", "NPCs", false)
				PS:CollisionGroupSetCollidable("Movers", "Ragdolls", false)
				for _, d in ipairs(train:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CollisionGroup = "Movers"
					end
				end
			end)
			local site = siteOf(train)
			local lights = {}
			for _, d in ipairs(site:GetDescendants()) do
				if d.Name == "TrainLight" then
					table.insert(lights, d)
				end
			end
			local function setLights(k)
				for i, l in ipairs(lights) do
					l.Color = (k and ((i + k) % 2 == 0)) and C(255, 40, 30) or C(70, 20, 20)
				end
			end
			local speed, every, len = train:GetAttribute("Speed") or 120, train:GetAttribute("Every") or 16, train:GetAttribute("Length") or 66
			local half = pc.UpperLimit
			local axis = pc.Attachment0.WorldCFrame.RightVector
			local dirSign = -1
			local hitAt = setmetatable({}, { __mode = "k" })
			while train.Parent do
				task.wait(every)
				for i = 1, 6 do
					setLights(i)
					sfx("zap", pc.Attachment0.WorldPosition, 0.35, 1.6)
					task.wait(0.3)
				end
				sfx("rise", root.Position, 1, 0.5)
				own()
				pc.Velocity = speed * dirSign
				local v = axis * speed * dirSign
				local t0 = os.clock()
				local blink = 0
				while os.clock() - t0 < 9 do
					task.wait()
					local pos = pc.CurrentPosition
					if (dirSign < 0 and pos <= -half + 1.5) or (dirSign > 0 and pos >= half - 1.5) then
						break
					end
					blink += 1
					if blink % 12 == 0 then
						setLights(blink / 12)
						own()
					end
					local now = os.clock()
					local nose = root.Position + axis * dirSign * (len / 2 + 2)
					local ncf = CFrame.lookAt(nose, nose + axis)
					local size = Vector3.new(11, 12, 11)
					local list, parts = dummiesIn(ncf, size)
					for _, m in ipairs(list) do
						if (hitAt[m] or 0) < now then
							hitAt[m] = now + 1.2
							local part, last = parts[m][1], parts[m][#parts[m]]
							task.delay(TRAIN_BODY_LAG, function()
							if not m.Parent then
								return
							end
							if part.Parent ~= m then
								part = m:FindFirstChild("UpperTorso") or part
							end
							local by = lastBy(m)
							hurt(m, part, "crush", 120, by, v.Unit, part.Position)
							hurt(m, (last.Parent == m) and last or part, "blunt", 60, by, v.Unit)
							local st = Injury.get(m)
							if st then
								st.fatal = "Hit by a train"
							end
							local side = axis:Cross(Vector3.yAxis) * (math.random() - 0.5) * 60
							Ragdoll.Fling(m, v * 1.05 + side + Vector3.new(0, 46, 0), nil, 4)
							for _, p in ipairs(m:GetChildren()) do -- past the fling clamp: a train does not slow down
								if p:IsA("BasePart") and not p.Anchored then
									p.AssemblyLinearVelocity = v * 1.05 + side + Vector3.new(0, 46, 0)
								end
							end
							if Ragdoll.LendNearest then
								Ragdoll.LendNearest(m, 160)
							end
							Injury.spurt(part.Position, v.Unit, 24, 40)
							sfx("heavy", part.Position, 1, 0.9)
							end)
						end
					end
					for _, p in ipairs(looseIn(ncf, size)) do
						if not H.damageProp(p, 999, nil) then
							p.AssemblyLinearVelocity = v + Vector3.new(math.random(-30, 30), 40, math.random(-30, 30))
						end
					end
					for _, c in ipairs(charsIn(ncf, size)) do
						if (hitAt[c.char] or 0) < now then
							hitAt[c.char] = now + 1.5
							-- (2026-11-14) a player sees the server's train a moment behind where it is, and is hit by
							-- it where the SERVER has it: the blow waits that moment, so it lands as the nose arrives
							local char, hum, hrp = c.char, c.hum, c.hrp
							task.delay(TRAIN_VIEW_LAG, function()
								if char.Parent and hum.Health > 0 then
									hum:TakeDamage(70)
									pcall(Ragdoll.Fling, char, v * 0.8 + Vector3.new(0, 50, 0), nil, 2.5)
									sfx("heavy", hrp.Position, 1, 0.9)
								end
							end)
						end
					end
				end
				pc.Velocity = 0
				dirSign = -dirSign
				setLights(nil)
			end
		end)
	end

	------------------------------------------------------------------------------------------------ the crane
	for _, hook in ipairs(tagged("CraneHook")) do
		local site = siteOf(hook)
		local cable = site:FindFirstChild("CraneCable", true)
		local topY, botY, cableTop, speed = hook:GetAttribute("Top"), hook:GetAttribute("Bottom"), hook:GetAttribute("CableTop"), hook:GetAttribute("Speed") or 8
		local home = hook.CFrame
		local lowered, moving, body, rope = false, false, nil, nil
		local lowerB, dropB
		for _, b in ipairs(tagged("CraneLower")) do
			if siteOf(b) == site then
				lowerB = b
			end
		end
		for _, b in ipairs(tagged("CraneDrop")) do
			if siteOf(b) == site then
				dropB = b
			end
		end
		local function place(y)
			hook.CFrame = CFrame.new(home.X, y, home.Z) * home.Rotation
			if cable and cableTop then
				local len = math.max(0.5, cableTop - (y + 0.8))
				cable.Size = Vector3.new(len, cable.Size.Y, cable.Size.Z)
				cable.CFrame = CFrame.new(home.X, y + 0.8 + len / 2, home.Z) * CFrame.Angles(0, 0, math.pi / 2)
			end
		end
		local function hang()
			if body and body.Parent and Dummies.is(body) and rope and rope.Parent then
				return
			end
			body, rope = nil, nil
			if lowered or moving then
				return
			end
			local m = Dummies.spawn(CFrame.new(hook.Position - Vector3.new(0, 8, 0)), {})
			if not m then
				return
			end
			Ragdoll.Ragdoll(m, nil)
			m:SetAttribute("Strapped", true)
			local foot = m:FindFirstChild("LeftFoot") or m:FindFirstChild("LeftLowerLeg")
			local a0 = hook:FindFirstChild("HookPoint")
			if not foot or not a0 then
				return
			end
			m:PivotTo(CFrame.new(hook.Position - Vector3.new(0, 4.6, 0)) * CFrame.Angles(math.pi, 0, 0))
			local a1 = Instance.new("Attachment")
			a1.Name = "HookGrip"
			a1.Parent = foot
			rope = Instance.new("RopeConstraint")
			rope.Name = "HookRope"
			rope.Attachment0, rope.Attachment1 = a0, a1
			rope.Length = 1.4
			rope.Visible = true
			rope.Thickness = 0.2
			rope.Color = BrickColor.new("Dark stone grey")
			rope.Parent = foot
			body = m
		end
		if lowerB and promptOf(lowerB) then
			local pp = promptOf(lowerB)
			onPrompt(pp, function(player)
				if moving then
					return
				end
				moving = true
				if body and body.Parent and player then
					body:SetAttribute("LastHitBy", player.UserId)
				end
				lamp(lowerB, C(255, 200, 60))
				local from, to = hook.Position.Y, lowered and topY or botY
				local dur = math.abs(to - from) / speed
				local t0 = os.clock()
				while true do
					local k = math.min(1, (os.clock() - t0) / dur)
					place(from + (to - from) * (k * k * (3 - 2 * k)))
					if k >= 1 then
						break
					end
					task.wait()
				end
				lowered = not lowered
				moving = false
				pp.ActionText = lowered and "Raise the hook" or "Lower the hook"
				lamp(lowerB, lowered and C(80, 160, 255) or C(60, 62, 70))
				if lowered then
					sfx("splash", hook.Position, 0.9, 1)
				end
			end)
		end
		if dropB and promptOf(dropB) then
			onPrompt(promptOf(dropB), function(player)
				if rope then
					rope:Destroy()
					rope = nil
				end
				if body and body.Parent then
					body:SetAttribute("Strapped", nil)
					if player then
						body:SetAttribute("LastHitBy", player.UserId)
					end
					sfx("whoosh", hook.Position, 0.5, 1)
				end
				body = nil
			end)
		end
		task.spawn(function()
			while hook.Parent do
				task.wait(5)
				if not lowered and not moving then
					pcall(hang)
				end
			end
		end)
	end

	------------------------------------------------------------------------------------------------ the cannon
	for _, fireB in ipairs(tagged("CannonFire")) do
		local site = siteOf(fireB)
		local loadB
		for _, b in ipairs(tagged("CannonLoad")) do
			if siteOf(b) == site then
				loadB = b
			end
		end
		local breech, muzzle = site:FindFirstChild("Breech", true), site:FindFirstChild("Muzzle", true)
		local loaded, busy = nil, false
		if breech and muzzle and loadB and promptOf(loadB) and promptOf(fireB) then
			onPrompt(promptOf(loadB), function(player)
				if loaded and Dummies.is(loaded) then
					return
				end
				loaded = nil
				local best, bd
				for m in pairs(Dummies.records) do
					local t = m:FindFirstChild("UpperTorso")
					if t and not m:GetAttribute("Strapped") and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Roamer") then
						local d = (t.Position - breech.Position).Magnitude
						if d < 55 and (not bd or d < bd) then
							best, bd = m, d
						end
					end
				end
				if not best then
					sfx("zap", breech.Position, 0.4, 0.5)
					return
				end
				loaded = best
				best:SetAttribute("Strapped", true)
				if player then
					best:SetAttribute("LastHitBy", player.UserId)
				end
				Ragdoll.Ragdoll(best, 600)
				best:PivotTo(breech.CFrame)
				for _, p in ipairs(best:GetDescendants()) do
					if p:IsA("BasePart") then
						p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
						p.Anchored = true
					end
				end
				sfx("hit", breech.Position, 0.7, 0.7)
				lamp(loadB, C(80, 230, 120))
			end)
			onPrompt(promptOf(fireB), function(player)
				if busy then
					return
				end
				busy = true
				local dir = muzzle.CFrame.LookVector
				local power = fireB:GetAttribute("Power") or 138
				sfx("boom", muzzle.Position, 1, 1.1)
				if net then
					net("boom", muzzle.Position, 40)
				end
				local smoke = muzzle:FindFirstChild("Smoke")
				if smoke then
					smoke:Emit(34)
				end
				if loaded and Dummies.is(loaded) then
					local m = loaded
					m:SetAttribute("Strapped", nil)
					if player then
						m:SetAttribute("LastHitBy", player.UserId)
					end
					Ragdoll.Ragdoll(m, 4)
					m:PivotTo(CFrame.lookAt(muzzle.Position + dir * 3, muzzle.Position + dir * 9) * CFrame.Angles(-math.pi / 2, 0, 0))
					for _, p in ipairs(m:GetDescendants()) do
						if p:IsA("BasePart") then
							p.Anchored = false
						end
					end
					for _, p in ipairs(m:GetDescendants()) do
						if p:IsA("BasePart") then
							pcall(function()
								p:SetNetworkOwner(nil)
							end)
							p.AssemblyLinearVelocity = dir * power
							p.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
						end
					end
					hurt(m, "UpperTorso", "blast", 16, player)
					-- a ragdoll weighs next to nothing, so the brick wall gets a shove of its own where the body lands
					local wall, torso = site:FindFirstChild("BrickWall"), m:FindFirstChild("UpperTorso")
					if wall and torso then
						task.spawn(function()
							local flat = dir * Vector3.new(1, 0, 1)
							flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis
							local t0 = os.clock()
							while os.clock() - t0 < 2.2 and torso.Parent do
								task.wait()
								local at
								for _, b in ipairs(wall:GetChildren()) do
									if b:IsA("BasePart") and (b.Position - torso.Position).Magnitude < 5 then
										at = torso.Position
										break
									end
								end
								if at then
									for _, b in ipairs(wall:GetChildren()) do
										if b:IsA("BasePart") and not b.Anchored then
											local d = (b.Position - at).Magnitude
											if d < 10 then
												b.AssemblyLinearVelocity = flat * (62 * (1 - d / 10) + 10) + Vector3.new(math.random(-8, 8), math.random(6, 22), math.random(-8, 8))
												b.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
											end
										end
									end
									hurt(m, torso, "blunt", 70, player, flat, at)
									sfx("heavy", at, 1, 0.9)
									if net then
										net("boom", at, 30)
									end
									break
								end
							end
						end)
					end
				end
				loaded = nil
				lamp(loadB, C(60, 62, 70))
				task.wait(1.2)
				busy = false
			end)
		end
	end

	------------------------------------------------------------------------------------------------ wrecking ball
	local wreckers = {}
	for _, b in ipairs(tagged("WreckSwing")) do
		local site = siteOf(b)
		local ball = site:FindFirstChild("WreckBall", true)
		local pp = promptOf(b)
		local rope = ball and ball:FindFirstChildOfClass("RopeConstraint")
		if ball and pp and rope then
			pcall(function()
				ball:SetNetworkOwner(nil)
			end)
			local W = { ball = ball, busy = false, by = nil }
			table.insert(wreckers, W)
			local back = b:GetAttribute("Back") or Vector3.zAxis
			local hitAt = setmetatable({}, { __mode = "k" })
			ball.Touched:Connect(function(hit)
				local sp = ball.AssemblyLinearVelocity
				if sp.Magnitude < 20 then
					return
				end
				local m = Dummies.of(hit)
				if m then
					if (hitAt[m] or 0) < os.clock() then
						hitAt[m] = os.clock() + 0.8
						if W.by then
							m:SetAttribute("LastHitBy", W.by.UserId)
						end
						-- (2026-11-14) the ball is the server's, seen ~0.2 s late on a client: the blow lands that much late and
						-- the body goes to the nearest player, so it flies as the ball is SEEN to reach it
						task.delay(MOVER_LAG, function()
							if not m.Parent then
								return
							end
							local at = (hit.Parent and hit:IsDescendantOf(m)) and hit or m:FindFirstChild("UpperTorso")
							if not at then
								return
							end
							hurt(m, at, "blunt", math.clamp(sp.Magnitude * 1.3, 24, 130), W.by, sp.Unit, at.Position)
							Ragdoll.Fling(m, sp * 1.15 + Vector3.new(0, 24, 0), nil, 3)
							if Ragdoll.LendNearest then
								Ragdoll.LendNearest(m, 140)
							end
							sfx("heavy", at.Position, 1, 0.8)
						end)
					end
				elseif not hit.Anchored then
					H.damageProp(hit, sp.Magnitude, W.by)
				end
			end)
			onPrompt(pp, function(player)
				if W.busy then
					return
				end
				W.busy = true
				W.by = player
				lamp(b, C(255, 200, 60))
				local pivot = rope.Attachment0.WorldPosition
				local reach = rope.Length + ball.Size.Y / 2
				local ang = math.rad(66)
				local pos = pivot - Vector3.new(0, math.cos(ang) * reach, 0) + back.Unit * math.sin(ang) * reach
				ball.Anchored = true
				local from = ball.Position
				for i = 1, 24 do
					ball.CFrame = CFrame.new(from:Lerp(pos, i / 24))
					task.wait(0.05)
				end
				task.wait(0.35)
				ball.Anchored = false
				ball.AssemblyLinearVelocity = Vector3.zero
				pcall(function()
					ball:SetNetworkOwner(nil)
				end)
				sfx("whoosh", pos, 0.8, 0.6)
				task.wait(6)
				lamp(b, C(60, 62, 70))
				W.busy = false
			end)
		end
	end

	------------------------------------------------------------------------------------------------ brick walls
	for _, wall in ipairs(tagged("BrickWall")) do
		local bricks = {}
		for _, p in ipairs(wall:GetChildren()) do
			if p:IsA("BasePart") then
				bricks[p] = p.CFrame
				pcall(function()
					p:SetNetworkOwner(nil)
				end)
			end
		end
		task.spawn(function()
			local rest = 0
			while wall.Parent do
				task.wait(5)
				local moved, moving = 0, false
				for p, home in pairs(bricks) do
					if (p.Position - home.Position).Magnitude > 1.5 then
						moved += 1
					end
					if p.AssemblyLinearVelocity.Magnitude > 1.5 then
						moving = true
					end
				end
				if moved > 0 and not moving then
					rest += 5
					if rest >= 15 then
						rest = 0
						for p, home in pairs(bricks) do
							p.Anchored = true
							TweenService:Create(p, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { CFrame = home }):Play()
						end
						task.wait(0.95)
						for p in pairs(bricks) do
							p.Anchored = false
							p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
						end
					end
				else
					rest = 0
				end
			end
		end)
	end

	------------------------------------------------------------------------------------------------ mines
	for _, mine in ipairs(tagged("Mine")) do
		local armed = true
		local lampPart = mine:FindFirstChild("Lamp")
		mine.Touched:Connect(function(hit)
			if not armed or hit.Anchored or hit:IsDescendantOf(map) then
				return
			end
			armed = false
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			local m = Dummies.of(hit)
			local by = plr or (m and lastBy(m)) or nil
			mine.Transparency = 1
			if lampPart then
				lampPart.Transparency = 1
			end
			H.blastAt(mine.Position + Vector3.new(0, 1, 0), mine:GetAttribute("Radius") or 13, mine:GetAttribute("Power") or 80, by)
			task.delay(10, function()
				mine.Transparency = 0
				if lampPart then
					lampPart.Transparency = 0
				end
				armed = true
			end)
		end)
	end

	------------------------------------------------------------------------------------------------ crates
	local crates = {}
	for _, mk in ipairs(tagged("CrateSpawn")) do
		crates[mk] = H.makeProp("crate", mk.CFrame)
	end
	task.spawn(function()
		while true do
			task.wait(45)
			for mk, p in pairs(crates) do
				if not p.Parent or (p.Position - mk.Position).Magnitude > 70 or p.Position.Y < -30 then
					if p.Parent then
						p:Destroy()
					end
					crates[mk] = H.makeProp("crate", mk.CFrame)
				end
			end
		end
	end)

	------------------------------------------------------------------------------------------------ zones: one loop
	local fans, chops, grinds, teslas = tagged("FanZone"), {}, {}, {}
	for _, Z in ipairs(tagged("ChopZone")) do
		local G = groupOf(Z)
		table.insert(chops, { part = Z, rotor = G and G.rotors[1], hitAt = setmetatable({}, { __mode = "k" }) })
	end
	for _, Z in ipairs(tagged("GrindZone")) do
		groupOf(Z)
		table.insert(grinds, { part = Z, t = setmetatable({}, { __mode = "k" }) })
	end
	for _, T in ipairs(tagged("Tesla")) do
		table.insert(teslas, { part = T, nextAt = 0, G = groupOf(T), victims = {} })
	end
	local function bolt(from, to)
		local model = Instance.new("Model")
		local last = from
		for i = 1, 6 do
			local nxt = (i == 6) and to or (from:Lerp(to, i / 6) + Vector3.new(math.random(-3, 3), math.random(-2, 2), math.random(-3, 3)))
			local seg = Instance.new("Part")
			seg.Anchored, seg.CanCollide, seg.CanQuery, seg.CanTouch, seg.CastShadow = true, false, false, false, false
			seg.Material, seg.Color = Enum.Material.Neon, C(190, 215, 255)
			seg.Size = Vector3.new(0.6, 0.6, (nxt - last).Magnitude)
			seg.CFrame = CFrame.lookAt((last + nxt) / 2, nxt)
			seg.Parent = model
			last = nxt
		end
		model.Parent = Injury.gore()
		Debris:AddItem(model, 0.14)
	end
	-- (2026-11-13) THE COIL COOKS, it does not swat. The owner wanted to "see the npcs getting electrocuted and dying
	-- away progressively rather than being shocked and knocked back": an arc now LATCHES onto each body in range
	-- (the nearest four) and stays on it - the body is held where it is, convulsing, its skin chars a little more
	-- every tick (Injury's own burn tint), burn marks and smoke build up, and its health drains over about six
	-- seconds. Switch the coil off, or drag the body out of range, and it lives - scorched.
	local CHAR, BRUISE = C(34, 28, 26), C(120, 70, 110)
	-- (2026-11-13) the cartoon x-ray the owner asked for: while a body is on the arc it turns see-through black and a
	-- glowing blue skeleton shows inside it. The bones are neon parts welded inside each limb (children of the limb,
	-- so the ragdoll and injury code never see them); the look comes off again the moment the arc lets go.
	local XRAY, XRAY_T, BONE, SOCKET = C(16, 18, 26), 0.62, C(80, 196, 255), C(8, 10, 16)
	local ZAP_PARTS = { "UpperTorso", "LowerTorso", "Head", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
	-- (2026-11-13) the disaster box's lightning borrows this arc (H.zap, below). One body, one arc: a second latch
	-- would save the x-ray look as the body's "original" and leave it see-through for good.
	local zapped = setmetatable({}, { __mode = "k" })
	local function zapStart(T, m)
		local torso = m:FindFirstChild("UpperTorso")
		if not torso or zapped[m] then
			return nil
		end
		zapped[m] = true
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = "ZapFrom", "ZapTo"
		a0.Parent, a1.Parent = T.part, torso
		local function beam(w, tr)
			local b = Instance.new("Beam")
			b.Name = "ZapArc"
			b.Attachment0, b.Attachment1 = a0, a1
			b.Width0, b.Width1 = w, w * 0.75
			b.FaceCamera = true
			b.LightEmission, b.LightInfluence = 1, 0
			b.Color = ColorSequence.new(C(170, 215, 255))
			b.Transparency = NumberSequence.new(tr)
			b.Segments = 14
			b.Parent = torso
			return b
		end
		local V = { a0 = a0, a1 = a1, core = beam(0.34, 0), glow = beam(1.3, 0.62), acc = 0, sndAt = 0 }
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Shadows = C(150, 190, 255), 14, 3, false
		light.Parent = torso
		V.light = light
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "ZapSparks"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Rate, sparks.Lifetime, sparks.Speed = 26, NumberRange.new(0.2, 0.5), NumberRange.new(8, 20)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new(0.6, 0)
		sparks.LightEmission = 1
		sparks.Color = ColorSequence.new(C(190, 225, 255))
		sparks.Parent = torso
		V.sparks = sparks
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "ZapSmoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Rate, smoke.Lifetime, smoke.Speed = 0, NumberRange.new(1.2, 2.2), NumberRange.new(1, 3)
		smoke.SpreadAngle = Vector2.new(180, 180)
		smoke.Acceleration = Vector3.new(0, 7, 0)
		smoke.Size = NumberSequence.new(1.2, 3.4)
		smoke.Transparency = NumberSequence.new(0.55, 1)
		smoke.Color = ColorSequence.new(C(70, 70, 74))
		smoke.Parent = torso
		V.smoke = smoke
		V.orig, V.bones = {}, {}
		local s = 1
		pcall(function()
			s = m:GetScale()
		end)
		local function bone(parent, size, cf, shape, color, mat)
			local b = Instance.new("Part")
			b.Name = "ZapBone"
			if shape then
				b.Shape = shape
			end
			b.Size, b.CFrame = size, cf
			b.Material, b.Color = mat or Enum.Material.Neon, color or BONE
			b.CanCollide, b.CanQuery, b.CanTouch, b.Massless, b.CastShadow = false, false, false, true, false
			b.TopSurface, b.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = parent, b
			w.Parent = b
			b.Parent = parent
			table.insert(V.bones, b)
			return b
		end
		local along = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis (its X) laid along the limb's Y
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				V.orig[p] = p.Transparency
				p.Transparency = XRAY_T
				p.Color = XRAY
				local sz, n = p.Size, p.Name
				if n == "Head" then
					local d = math.min(sz.X, sz.Y, sz.Z) * 0.84
					bone(p, Vector3.new(d, d, d), p.CFrame * CFrame.new(0, sz.Y * 0.04, 0), Enum.PartType.Ball)
					bone(p, Vector3.new(d * 0.56, d * 0.22, d * 0.5), p.CFrame * CFrame.new(0, -d * 0.46, -d * 0.1))
					for _, sx in ipairs({ -1, 1 }) do
						bone(p, Vector3.new(d * 0.27, d * 0.27, d * 0.27), p.CFrame * CFrame.new(sx * d * 0.2, sz.Y * 0.08, -d * 0.38), Enum.PartType.Ball, SOCKET, Enum.Material.SmoothPlastic)
					end
				elseif n == "UpperTorso" then
					bone(p, Vector3.new(0.24 * s, sz.Y * 0.98, 0.24 * s), p.CFrame * CFrame.new(0, 0, sz.Z * 0.16))
					bone(p, Vector3.new(sz.X * 0.9, 0.17 * s, 0.17 * s), p.CFrame * CFrame.new(0, sz.Y * 0.4, 0))
					for i = 0, 3 do
						bone(p, Vector3.new(sz.X * (0.8 - i * 0.07), 0.13 * s, sz.Z * 0.62), p.CFrame * CFrame.new(0, sz.Y * (0.24 - i * 0.17), 0))
					end
				elseif n == "LowerTorso" then
					bone(p, Vector3.new(0.24 * s, sz.Y, 0.24 * s), p.CFrame * CFrame.new(0, 0, sz.Z * 0.16))
					bone(p, Vector3.new(sz.X * 0.82, sz.Y * 0.5, sz.Z * 0.5), p.CFrame * CFrame.new(0, -sz.Y * 0.18, 0))
				elseif string.find(n, "Hand", 1, true) or string.find(n, "Foot", 1, true) then
					bone(p, sz * Vector3.new(0.55, 0.55, 0.62), p.CFrame)
				else -- an arm or leg segment: a long bone with a knuckle at its lower end
					local dia = math.min(sz.X, sz.Z) * 0.32
					bone(p, Vector3.new(sz.Y * 0.92, dia, dia), p.CFrame * along, Enum.PartType.Cylinder)
					bone(p, Vector3.new(dia * 1.7, dia * 1.7, dia * 1.7), p.CFrame * CFrame.new(0, -sz.Y * 0.46, 0), Enum.PartType.Ball)
				end
			end
		end
		local head = m:FindFirstChild("Head")
		local face = head and head:FindFirstChildOfClass("Decal")
		if face then
			V.face, V.faceT = face, face.Transparency
			face.Transparency = 0.6
		end
		return V
	end
	local function charAll(m, st, add, burnOnly)
		for name, r in pairs(st.regions) do
			local p = m:FindFirstChild(name)
			local base = st.base and st.base[name]
			if p and base and not r.sev then
				r.burn = math.min(110, (r.burn or 0) + add)
				if not burnOnly then -- the same mix as Injury.tint (skipped while the x-ray look is on)
					p.Color = base:Lerp(BRUISE, math.clamp((100 - r.hp) / 100, 0, 1) * 0.45):Lerp(CHAR, math.clamp(r.burn / 110, 0, 0.85))
				end
			end
		end
		st.dirty = true
	end
	local function zapTick(T, m, V, step, now)
		local hum = m:FindFirstChildOfClass("Humanoid")
		local torso = m:FindFirstChild("UpperTorso")
		local st = Injury.get(m)
		local by = (T.G and T.G.by and T.G.by.Parent and T.G.by) or lastBy(m)
		-- the arc writhes: new control points every tick
		V.a0.CFrame = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		V.a1.CFrame = CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		local c0, c1 = (math.random() - 0.5) * 14, (math.random() - 0.5) * 14
		V.core.CurveSize0, V.core.CurveSize1 = c0, c1
		V.glow.CurveSize0, V.glow.CurveSize1 = c0, c1
		V.light.Brightness = 2 + math.random() * 3
		-- held where it is, convulsing: no knock-back
		local frac = hum and math.clamp(1 - hum.Health / math.max(hum.MaxHealth, 1), 0, 1) or 0
		Ragdoll.Ragdoll(m, 1.5)
		local amp = 9 - 4 * frac -- the jerks weaken as it goes
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and not p.Anchored then
				local v = p.AssemblyLinearVelocity
				p.AssemblyLinearVelocity = Vector3.new(v.X * 0.45, math.min(v.Y, 6), v.Z * 0.45) + Vector3.new((math.random() - 0.5) * 2 * amp, math.random() * amp, (math.random() - 0.5) * 2 * amp)
				p.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
			end
		end
		if st then
			st.fatal = st.fatal or "Electrocuted"
			charAll(m, st, 15 * step, true) -- the burn builds up unseen; it shows when the arc lets go
		end
		V.acc += (T.part:GetAttribute("Damage") or 55) * step
		if V.acc >= 9 then
			if by then
				m:SetAttribute("LastHitBy", by.UserId)
			end
			-- HitReactServer shoves every body that loses health; a bumped HitSeq tells it this hit is spoken for
			m:SetAttribute("HitSeq", (m:GetAttribute("HitSeq") or 0) + 1)
			hurt(m, ZAP_PARTS[math.random(#ZAP_PARTS)], "shock", V.acc, by)
			V.acc = 0
		end
		V.smoke.Rate = 3 + 26 * frac
		if torso and now >= V.sndAt then
			V.sndAt = now + 0.3 + math.random() * 0.2
			sfx("zap", torso.Position, 0.45, 0.9 + math.random() * 0.5)
		end
		-- each hit makes Injury re-tint the limb it landed on: put the x-ray black back
		for p in pairs(V.orig) do
			if p.Parent and p.Color ~= XRAY then
				p.Color = XRAY
			end
		end
	end
	local function zapStop(m, V)
		zapped[m] = nil
		for _, k in ipairs({ "core", "glow", "a0", "a1", "light", "sparks" }) do
			if V[k] then
				V[k]:Destroy()
			end
		end
		for _, b in ipairs(V.bones or {}) do
			b:Destroy()
		end
		for p, t in pairs(V.orig or {}) do
			if p.Parent then
				p.Transparency = t
			end
		end
		if V.face and V.face.Parent then
			V.face.Transparency = V.faceT or 0
		end
		local dead = m.Parent ~= nil and m:GetAttribute("Dead") == true
		local st = m.Parent and Injury.get(m)
		if st then
			charAll(m, st, dead and 110 or 0) -- solid again: charcoal if it died, scorched as far as it got if not
			if not dead and st.fatal == "Electrocuted" then
				st.fatal = nil -- it got away
			end
		end
		if V.smoke and V.smoke.Parent then
			if dead then
				V.smoke.Rate = 22
				task.delay(5, function()
					if V.smoke.Parent then
						V.smoke.Enabled = false
					end
				end)
				Debris:AddItem(V.smoke, 8)
			else
				V.smoke.Enabled = false
				Debris:AddItem(V.smoke, 2.5)
			end
		end
	end
	H.zap = { start = zapStart, tick = zapTick, stop = zapStop } -- T = { part = <source part, attribute Damage>, G = { by = player } }

	local fast, slow = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		fast += dt
		slow += dt
		if fast >= 0.05 then
			local step = fast
			fast = 0
			-- wind
			for _, Z in ipairs(fans) do
				if Z:GetAttribute("On") then
					local power, dir, len = Z:GetAttribute("Power") or 140, Z.CFrame.LookVector, Z.Size.Z
					local fanAt = Z:GetAttribute("FanAt") or (len / 2)
					local front, behind = len / 2 + fanAt, len / 2 - fanAt
					local function blow(p)
						local d = fanAt - Z.CFrame:PointToObjectSpace(p.Position).Z -- in front of the blades > 0
						local s = (d >= 0) and math.clamp(1 - d / front, 0, 1) ^ 0.7 or math.clamp(1 + d / behind, 0, 1) * 0.85
						if s > 0.02 then
							local v = p.AssemblyLinearVelocity
							p.AssemblyLinearVelocity = v:Lerp(dir * power * s + Vector3.new(0, 10 * s, 0), math.min(1, step * 3.2 * s)) + Vector3.new(0, workspace.Gravity * step * 0.55 * s, 0)
						end
						return s
					end
					local list = dummiesIn(Z.CFrame, Z.Size)
					for _, m in ipairs(list) do
						Ragdoll.Ragdoll(m, 1.6)
						for _, p in ipairs(m:GetChildren()) do
							if p:IsA("BasePart") and not p.Anchored then
								blow(p)
							end
						end
					end
					for _, p in ipairs(looseIn(Z.CFrame, Z.Size)) do
						blow(p)
					end
				end
			end
			-- blades
			for _, Zc in ipairs(chops) do
				local Z = Zc.part
				if Z:GetAttribute("On") ~= false then
					local list, parts = dummiesIn(Z.CFrame, Z.Size)
					local arms = Z:GetAttribute("Arms")
					local rotor = Zc.rotor
					local armAtt = rotor and rotor:FindFirstChild("ArmDir")
					for _, m in ipairs(list) do
						if (Zc.hitAt[m] or 0) < now then
							local part = parts[m][1]
							local vel = Z.CFrame.LookVector * (Z:GetAttribute("Fling") or 60) + Vector3.new(0, 18, 0)
							local ok = true
							if arms and armAtt then
								ok = false
								local axis = Vector3.yAxis
								local armDir = armAtt.WorldCFrame.LookVector
								local side = axis:Cross(armDir)
								local spin = rotor:GetAttribute("Spin") or 5
								local period = math.pi * 2 / arms
								for _, p in ipairs(parts[m]) do
									local rel = (p.Position - rotor.Position) * Vector3.new(1, 0, 1)
									local r = rel.Magnitude
									if r > 2.6 and r < (Z:GetAttribute("Radius") or 18) then
										local a = math.atan2(rel:Dot(side), rel:Dot(armDir)) % period
										if math.min(a, period - a) < 0.34 then
											ok, part = true, p
											vel = axis:Cross(rel).Unit * spin * r * 1.25 + Vector3.new(0, 30, 0)
											break
										end
									end
								end
							end
							if ok then
								Zc.hitAt[m] = now + (arms and 0.5 or 0.4)
								local function blow()
									if not m.Parent then
										return
									end
									local at = (part.Parent == m) and part or m:FindFirstChild("UpperTorso")
									if not at then
										return
									end
									local by = lastBy(m)
									hurt(m, at, Z:GetAttribute("Type") or "slash", Z:GetAttribute("Damage") or 30, by, vel.Unit, at.Position)
									if (Z:GetAttribute("Sever") or 0) > math.random() then
										Injury.sever(m, LIMBS[math.random(#LIMBS)], by, vel.Unit)
									end
									Ragdoll.Fling(m, vel, nil, 2.6)
									if arms and Ragdoll.LendNearest then
										Ragdoll.LendNearest(m, 140)
									end
									sfx(arms and "heavy" or "slash", at.Position, 0.8, 1.1)
								end
								-- (2026-11-14) the rotor's arms are the server's, seen ~0.2 s late on a client: their blow waits
								if arms then
									task.delay(MOVER_LAG, blow)
								else
									blow()
								end
							end
						end
					end
				end
			end
		end
		if slow < 0.14 then
			return
		end
		local step = slow
		slow = 0
		for _, G in ipairs(grinds) do
			local Z = G.part
			if Z:GetAttribute("On") ~= false then
				local list, parts = dummiesIn(Z.CFrame, Z.Size)
				for _, m in ipairs(list) do
					local g = (G.t[m] or 0) + step
					G.t[m] = g
					local ps = parts[m]
					local part = ps[math.random(#ps)]
					local by = lastBy(m)
					hurt(m, part, "slash", (Z:GetAttribute("Damage") or 26) * 0.5, by, -Vector3.yAxis, part.Position)
					Injury.spurt(part.Position, Vector3.yAxis, 8, 22)
					Ragdoll.Ragdoll(m, 3)
					for _, p in ipairs(ps) do
						p.AssemblyLinearVelocity = p.AssemblyLinearVelocity * 0.6 + Vector3.new(0, -14, 0)
					end
					if math.random() < 0.2 then
						Injury.sever(m, LIMBS[math.random(#LIMBS)], by, Vector3.yAxis)
					end
					if g > 1.5 and not m:GetAttribute("Invuln") then
						G.t[m] = nil
						local st = Injury.get(m)
						if st then
							st.fatal = "Fed to the grinder"
						end
						local hum = m:FindFirstChildOfClass("Humanoid")
						if hum and hum.Health > 0 then
							hum.Health = 0
						end
						Injury.spurt(part.Position, Vector3.yAxis, 30, 30)
						sfx("slash", part.Position, 0.9, 0.7)
						task.delay(0.25, Dummies.remove, m, false)
					end
				end
				for _, p in ipairs(looseIn(Z.CFrame, Z.Size)) do
					if not H.damageProp(p, 999, nil) then
						Injury.spurt(p.Position, Vector3.yAxis, 6, 18)
						p:Destroy()
					end
				end
				for _, c in ipairs(charsIn(Z.CFrame, Z.Size + Vector3.new(0, 3, 0))) do
					c.hum.Health = 0
				end
			end
		end
		for _, T in ipairs(teslas) do
			local part = T.part
			local on = part:GetAttribute("On") == true
			local pl = part:FindFirstChildOfClass("PointLight")
			if pl then
				pl.Brightness = on and (1.5 + math.random()) or 0
			end
			part.Material = on and Enum.Material.Neon or Enum.Material.Metal
			local seen = {}
			if on then
				local range = part:GetAttribute("Range") or 36
				local near = {}
				for m, rec in pairs(Dummies.records) do
					local t = m:FindFirstChild("UpperTorso")
					if t and not rec.dead and not m:GetAttribute("Invuln") then
						local d = (t.Position - part.Position).Magnitude
						if d < range then
							table.insert(near, { m, d })
						end
					end
				end
				table.sort(near, function(a, b)
					return a[2] < b[2]
				end)
				for i = 1, math.min(4, #near) do
					seen[near[i][1]] = true
				end
			end
			for m in pairs(seen) do
				local V = T.victims[m]
				if not V then
					V = zapStart(T, m)
					T.victims[m] = V
				end
				if V then
					zapTick(T, m, V, step, now)
				end
			end
			for m, V in pairs(T.victims) do
				if not seen[m] or not m.Parent then
					zapStop(m, V)
					T.victims[m] = nil
				end
			end
			if on and next(seen) == nil and now >= T.nextAt then -- nothing to bite: it spits at the air
				T.nextAt = now + 0.9 + math.random() * 0.5
				bolt(part.Position, part.Position + Vector3.new(math.random(-9, 9), math.random(-10, 2), math.random(-9, 9)))
			end
		end
		for _, W in ipairs(wreckers) do
			if not W.busy and not W.ball.Anchored then
				W.ball.AssemblyLinearVelocity = W.ball.AssemblyLinearVelocity * (1 - math.min(0.5, step * 0.5))
			end
		end
	end)
end

return M
