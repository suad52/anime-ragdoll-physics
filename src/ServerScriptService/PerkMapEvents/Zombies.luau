--!nocheck
-- PerkMapEvents.Zombies (2026-11-15): COUNT zombie dummies claw their way out of the ground around the players on the
-- buyer's map and shamble after the nearest player (or, with nobody near, the nearest living dummy) for 75 s. They are
-- ordinary sandbox dummies underneath (Sandbox.Dummies: same rig, injuries, ragdoll, kill credit), with a rotten skin,
-- glowing eyes, the arms-out walk (the SandboxReactions pose "zombie": tag Reacting + attribute React) and a moan. A
-- zombie that is knocked down gets back up after a moment, so a player has to really put it down (legs gone or dead).
-- A bite: a player takes BITE damage (a ForceField - God Mode - blocks it) and a shove; a dummy is hurt and thrown.
local COUNT, BITE = 14, 8
local WALK = "rbxassetid://507777826"
local MOAN = "rbxassetid://9043337370"
local SKIN = { Color3.fromRGB(122, 148, 100), Color3.fromRGB(110, 136, 92), Color3.fromRGB(134, 154, 108) }
local RAGS = { UpperTorso = Color3.fromRGB(78, 70, 62), LowerTorso = Color3.fromRGB(58, 56, 70), LeftUpperLeg = Color3.fromRGB(58, 56, 70),
	RightUpperLeg = Color3.fromRGB(58, 56, 70), LeftLowerLeg = Color3.fromRGB(52, 50, 64), RightLowerLeg = Color3.fromRGB(52, 50, 64) }

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local UP, FLAT = ctx.UP, ctx.FLAT
	local D = ctx.Dummies
	if not D then
		return
	end
	local CS = game:GetService("CollectionService")
	local Debris = game:GetService("Debris")
	local list = {}
	local killed = 0

	local function moan(z, speed)
		local head = z.m:FindFirstChild("Head")
		if not head then
			return
		end
		local s = Instance.new("Sound")
		s.SoundId = MOAN
		s.Volume = 0.55
		s.PlaybackSpeed = speed or rng:NextNumber(0.27, 0.36)
		s.RollOffMinDistance, s.RollOffMaxDistance, s.RollOffMode = 8, 90, Enum.RollOffMode.InverseTapered
		s.Parent = head
		s:Play()
		Debris:AddItem(s, 5)
	end

	local function walkTrack(z)
		if z.walk then
			return z.walk
		end
		local animator = z.hum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = WALK
			local ok, tr = pcall(function()
				return animator:LoadAnimation(a)
			end)
			if ok and tr then
				tr.Looped = true
				tr.Priority = Enum.AnimationPriority.Movement
				z.walk = tr
			end
		end
		return z.walk
	end

	local function makeZombie(pos)
		local m = D.spawn(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0), { life = (ev.ends - ctx.now()) + 40 })
		if not m then
			return nil
		end
		m.Name = "Zombie"
		m:SetAttribute("Zombie", true)
		local skin = SKIN[rng:NextInteger(1, #SKIN)]
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				p.Color = RAGS[p.Name] or skin
			end
		end
		local head = m:FindFirstChild("Head")
		if head then
			for _, sx in ipairs({ -1, 1 }) do
				local eye = Instance.new("Part")
				eye.Name = "ZombieEye"
				eye.Shape = Enum.PartType.Ball
				eye.Size = Vector3.new(0.2, 0.2, 0.2)
				eye.Material = Enum.Material.Neon
				eye.Color = Color3.fromRGB(190, 255, 70)
				eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless, eye.CastShadow = false, false, false, true, false
				eye.CFrame = head.CFrame * CFrame.new(sx * head.Size.X * 0.17, head.Size.Y * 0.08, -head.Size.Z * 0.46)
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = head, eye
				w.Parent = eye
				eye.Parent = head
			end
		end
		local hum = m:FindFirstChildOfClass("Humanoid")
		local hrp = m:FindFirstChild("HumanoidRootPart")
		local rec = D.records[m]
		if rec and rec.track then
			rec.track:Stop(0.2)
		end
		hum.WalkSpeed = rng:NextNumber(8, 11.5)
		CS:AddTag(m, "Reacting")
		m:SetAttribute("React", "zombie")
		local z = { m = m, hum = hum, hrp = hrp, nextHit = 0, nextMoan = os.clock() + rng:NextNumber(1, 5), downAt = nil, speed = hum.WalkSpeed }
		-- out of the ground: sunk to the chest, pushed up over RISE s
		local RISE = 1.3
		local home = hrp.CFrame
		hrp.Anchored = true
		ctx.fx("zombieRise", { pos = pos, id = ev.id })
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent and os.clock() - t0 < RISE do
				local a = (os.clock() - t0) / RISE
				local sink = 6 * (1 - a) ^ 1.6
				m:PivotTo(home * CFrame.new(0, -sink, 0) * CFrame.Angles(math.sin(a * 20) * 0.08 * (1 - a), 0, 0))
				task.wait()
			end
			if m.Parent then
				m:PivotTo(home)
				hrp.Anchored = false
				z.ready = true
				local tr = walkTrack(z)
				if tr then
					tr:Play(0.3)
					tr:AdjustSpeed(0.7)
				end
				moan(z, 0.3)
			end
		end)
		table.insert(list, z)
		return z
	end

	-- the wave: spread over the players on this map, 16-38 studs from each
	local n = math.min(COUNT, (D.CAP or 64) - D.count() - 4)
	local ps = ctx.players(A, 0)
	for i = 1, math.max(n, 0) do
		local pos
		if #ps > 0 then
			pos = ctx.pointNear(ps[(i - 1) % #ps + 1].hrp.Position, 16, 38, A, 12)
		end
		pos = pos or ctx.randomPoint(A, 30)
		makeZombie(pos)
		task.wait(0.12)
	end
	ev.marker:SetAttribute("Count", #list)
	ev.cleanup = function()
		for _, z in ipairs(list) do
			if z.m.Parent then
				pcall(D.remove, z.m, true)
			end
		end
	end

	local function nearestPlayer(pos, maxD)
		local best, bd
		for _, e in ipairs(ctx.players(A, 30)) do
			local d = ((e.hrp.Position - pos) * FLAT).Magnitude
			if d < maxD and (not bd or d < bd) then
				best, bd = e, d
			end
		end
		return best, bd
	end
	local function nearestDummy(pos, maxD)
		local best, bd
		for m in pairs(D.records) do
			if not m:GetAttribute("Zombie") and not m:GetAttribute("Boss") and ctx.alive(m) then
				local t = ctx.torso(m)
				local d = t and ((t.Position - pos) * FLAT).Magnitude
				if d and d < maxD and (not bd or d < bd) then
					best, bd = m, d
				end
			end
		end
		return best, bd
	end

	while not ev.stop and ctx.now() < ev.ends do
		task.wait(0.2)
		local now = os.clock()
		local standing = 0
		for _, z in ipairs(list) do
			local m = z.m
			if not m.Parent or not z.ready then
				continue
			end
			if not ctx.alive(m) then
				if not z.dead then
					z.dead = true
					killed += 1
					CS:RemoveTag(m, "Reacting")
					m:SetAttribute("React", nil)
				end
				continue
			end
			if ctx.isRagdolled(m) then
				-- knocked down: back up after a moment, if it still has its legs
				z.downAt = z.downAt or now
				if now - z.downAt > 2.6 and m:FindFirstChild("LeftLowerLeg") and m:FindFirstChild("RightLowerLeg")
					and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") and ctx.Ragdoll and ctx.Ragdoll.Unragdoll then
					local ok = pcall(ctx.Ragdoll.Unragdoll, m)
					if ok then
						z.downAt = nil
						local tr = walkTrack(z)
						if tr and not tr.IsPlaying then
							tr:Play(0.3)
							tr:AdjustSpeed(0.7)
						end
					end
				end
				continue
			end
			z.downAt = nil
			standing += 1
			local pos = z.hrp.Position
			local e, dP = nearestPlayer(pos, 170)
			local goal, victim, dist
			if e then
				goal, dist = e.hrp.Position, dP
			else
				local vm, dD = nearestDummy(pos, 90)
				if vm then
					victim, goal, dist = vm, ctx.torso(vm).Position, dD
				end
			end
			if goal then
				z.hum.WalkSpeed = dist < 10 and z.speed * 1.45 or z.speed -- a lunge at the end
				z.hum:MoveTo(goal)
				if dist < 4.3 and now >= z.nextHit then
					z.nextHit = now + 1.1
					local dir = (goal - pos) * FLAT
					dir = dir.Magnitude > 0.1 and dir.Unit or z.hrp.CFrame.LookVector
					ctx.fx("zombieBite", { pos = goal, id = ev.id })
					if e then
						e.hum:TakeDamage(BITE)
						ctx.knock(e.player, dir * 26 + UP * 14, 0.6)
					elseif victim then
						ctx.blame(victim, ev.by)
						local part = victim:FindFirstChild(rng:NextNumber() < 0.5 and "LeftUpperArm" or "RightUpperArm") or ctx.anyPart(victim)
						if part then
							ctx.hurt(victim, part, "cut", rng:NextInteger(10, 18), ev.by, dir, part.Position)
						end
						ctx.fling(victim, dir * 22 + UP * 12, 2)
					end
				end
			else
				z.hum:MoveTo(pos) -- nobody to chase: stand and sway
			end
			if now >= z.nextMoan then
				z.nextMoan = now + rng:NextNumber(3.5, 8)
				moan(z)
			end
		end
		ev.info = { zombies = #list, standing = standing, killed = killed }
	end
	-- the end: what is left falls and crumbles
	for _, z in ipairs(list) do
		if z.m.Parent and ctx.alive(z.m) then
			ctx.fx("zombieDust", { pos = z.hrp.Position, id = ev.id })
			ctx.ragdoll(z.m, nil)
			task.delay(rng:NextNumber(0.5, 1.5), function()
				if z.m.Parent then
					pcall(D.remove, z.m, true)
				end
			end)
		end
	end
	task.wait(1.6)
end
