--!nocheck
-- PerkMapEvents.BossDummy (2026-11-15): a GIANT boss dummy (a sandbox dummy scaled x SCALE) drops onto the buyer's map
-- and hunts the nearest player for up to 150 s. Its health is a pool (HP + PER_PLAYER for every player on the map), shown
-- on a bar over its head; the sandbox's injuries leave it alone (attribute Boss: Sandbox.Injury turns a hit into plain
-- damage) and nothing knocks it over (attribute Unstoppable: RagdollService refuses until it is Dead).
--   STOMP  (a player within STOMP_R, every 4-6 s): a red warning ring, then a shockwave - players are thrown and hurt,
--          dummies flung
--   SWAT   (a player within SWAT_R): one big swipe that sends them flying
--   it shoves aside any dummy it walks into; at half and a quarter health it ROARS and speeds up
-- Killed: it crashes down as a giant ragdoll, a banner names the FINAL BLOW. Not killed in time: it sinks away.
local SCALE, HP, PER_PLAYER, MAX_HP = 5, 2500, 1500, 10000
local STOMP_R, SWAT_R = 42, 15
local SPEED = 15

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local UP, FLAT = ctx.UP, ctx.FLAT
	local D = ctx.Dummies
	if not D then
		return
	end
	local Players = game:GetService("Players")
	local at = ctx.pointNear(ev.byPos, 50, 90, A, 40) or ctx.randomPoint(A, 50)
	local m = D.spawn(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0), { life = (ev.ends - ctx.now()) + 120 })
	if not m then
		ctx.banner("THE BOSS COULDN'T SQUEEZE IN", "TOO MANY DUMMIES ON THE MAP - TRY AGAIN SOON", Color3.fromRGB(220, 40, 50), Color3.fromRGB(255, 210, 90))
		return
	end
	m.Name = "BossDummy"
	m:SetAttribute("Boss", true)
	m:SetAttribute("Unstoppable", true)
	local rec = D.records[m]
	if rec and rec.track then
		rec.track:Stop(0.2)
	end
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Color = (p.Name == "UpperTorso" or p.Name == "LowerTorso") and Color3.fromRGB(96, 26, 34) or Color3.fromRGB(56, 52, 64)
		end
	end
	local head = m:FindFirstChild("Head")
	if head then
		for _, sx in ipairs({ -1, 1 }) do
			local eye = Instance.new("Part")
			eye.Name = "BossEye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(0.24, 0.24, 0.24)
			eye.Material = Enum.Material.Neon
			eye.Color = Color3.fromRGB(255, 50, 40)
			eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless, eye.CastShadow = false, false, false, true, false
			eye.CFrame = head.CFrame * CFrame.new(sx * head.Size.X * 0.17, head.Size.Y * 0.08, -head.Size.Z * 0.46)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, eye
			w.Parent = eye
			eye.Parent = head
		end
	end
	pcall(function()
		m:ScaleTo(SCALE)
	end)
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = m:FindFirstChild("HumanoidRootPart")
	local maxHp = math.min(HP + PER_PLAYER * #ctx.players(A, 20), MAX_HP)
	hum.MaxHealth = maxHp
	hum.Health = maxHp
	hum.WalkSpeed = SPEED
	hum.JumpPower = 0
	m:SetAttribute("BossMax", maxHp)
	ev.marker:SetAttribute("BossMax", maxHp)

	-- the health bar over its head
	local bb = Instance.new("BillboardGui")
	bb.Name = "BossBar"
	bb.Size = UDim2.fromOffset(320, 58)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 900
	bb.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 220, 90)
	title.Text = "GIANT BOSS DUMMY"
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2
	ts.Parent = title
	title.Parent = bb
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(10, 32)
	back.Size = UDim2.new(1, -20, 0, 18)
	back.BackgroundColor3 = Color3.fromRGB(20, 16, 26)
	back.BorderSizePixel = 0
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local bs = Instance.new("UIStroke")
	bs.Thickness = 2
	bs.Color = Color3.fromRGB(255, 220, 90)
	bs.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(235, 50, 60)
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	fill.Parent = back
	back.Parent = bb
	bb.Parent = head or hrp
	local function bar()
		local k = math.clamp(hum.Health / maxHp, 0, 1)
		fill.Size = UDim2.fromScale(k, 1)
		ev.marker:SetAttribute("BossHp", hum.Health)
	end
	hum.HealthChanged:Connect(bar)
	bar()

	local dead, killer = false, nil
	hum.Died:Connect(function()
		dead = true
		local uid = m:GetAttribute("LastHitBy")
		killer = uid and Players:GetPlayerByUserId(uid)
	end)
	ev.cleanup = function()
		if m.Parent and not dead then
			pcall(D.remove, m, false)
		end
	end

	-- the drop: it falls out of the sky onto `at` and lands with a shockwave
	local home = hrp.CFrame
	hrp.Anchored = true
	ctx.fx("bossWarn", { pos = at, r = STOMP_R, t = 1.2, id = ev.id })
	local t0 = os.clock()
	while m.Parent and os.clock() - t0 < 1.2 do
		local a = (os.clock() - t0) / 1.2
		m:PivotTo(home * CFrame.new(0, 90 * (1 - a * a), 0))
		task.wait()
	end
	if not m.Parent then
		return
	end
	m:PivotTo(home)
	hrp.Anchored = false

	local function shock(center, r, power, dmg, rag)
		ctx.fx("bossStomp", { pos = center, r = r, id = ev.id })
		ctx.sfx("boom", center, 1.3, 0.55)
		ctx.threat(center, r * 2, 2)
		for _, e in ipairs(ctx.players(A, 30)) do
			local off = (e.hrp.Position - center) * FLAT
			local d = off.Magnitude
			if d < r then
				local k = 1 - d / r
				local dir = d > 0.5 and off.Unit or Vector3.xAxis
				ctx.knock(e.player, (dir * (35 + power * k) + UP * (30 + 25 * k)), rag)
				if dmg > 0 then
					e.hum:TakeDamage(dmg * (0.4 + 0.6 * k))
				end
			end
		end
		for _, o in ipairs(ctx.dummies(A, 20)) do
			if o ~= m then
				local t = ctx.torso(o)
				local off = (t.Position - center) * FLAT
				local d = off.Magnitude
				if d < r then
					local k = 1 - d / r
					local dir = d > 0.5 and off.Unit or Vector3.xAxis
					ctx.fling(o, dir * (40 + power * 1.2 * k) + UP * (35 + 30 * k), 3)
					if ctx.alive(o) and k > 0.4 then
						local part = ctx.anyPart(o)
						if part then
							ctx.hurt(o, part, "blunt", math.floor(10 + 22 * k), nil, UP, part.Position)
						end
					end
				end
			end
		end
	end
	shock(at, STOMP_R, 70, 0, 1.2)
	ctx.fx("bossRoar", { pos = hrp.Position, id = ev.id })

	local nextStomp, nextSwat = os.clock() + 3, os.clock() + 1.5
	local shoved = {}
	local roared = {}
	local lastPos, stuckFor = hrp.Position, 0
	while not ev.stop and not dead and m.Parent and ctx.now() < ev.ends do
		task.wait(0.15)
		if dead or not m.Parent then
			break
		end
		local now = os.clock()
		local pos = hrp.Position
		local feet = pos - UP * (hum.HipHeight + hrp.Size.Y / 2)
		local frac = hum.Health / maxHp
		for _, mark in ipairs({ 0.5, 0.25 }) do
			if frac <= mark and not roared[mark] then
				roared[mark] = true
				hum.WalkSpeed += 4
				ctx.fx("bossRoar", { pos = pos, id = ev.id })
				nextStomp = math.min(nextStomp, now + 0.6)
			end
		end
		local best, bd
		for _, e in ipairs(ctx.players(A, 30)) do
			local d = ((e.hrp.Position - pos) * FLAT).Magnitude
			if not bd or d < bd then
				best, bd = e, d
			end
		end
		local goal = best and best.hrp.Position
		if not goal then
			for _, o in ipairs(ctx.dummies(A, 0)) do
				if o ~= m and ctx.alive(o) then
					local d = ((ctx.torso(o).Position - pos) * FLAT).Magnitude
					if not bd or d < bd then
						goal, bd = ctx.torso(o).Position, d
					end
				end
			end
		end
		if goal then
			hum:MoveTo(goal)
		end
		if ((pos - lastPos) * FLAT).Magnitude < 0.4 and goal and bd and bd > 12 then
			stuckFor += 0.15
			if stuckFor > 2 then
				stuckFor = 0
				hrp.AssemblyLinearVelocity += UP * 70 + (((goal - pos) * FLAT).Unit * 20)
			end
		else
			stuckFor = 0
		end
		lastPos = pos
		if best and bd < STOMP_R * 0.85 and now >= nextStomp then
			nextStomp = now + rng:NextNumber(4, 6)
			hum:MoveTo(pos)
			ctx.fx("bossWarn", { pos = feet, r = STOMP_R, t = 0.7, id = ev.id })
			hrp.AssemblyLinearVelocity += UP * 45
			task.wait(0.7)
			if dead or not m.Parent then
				break
			end
			local f = hrp.Position - UP * (hum.HipHeight + hrp.Size.Y / 2)
			shock(f, STOMP_R, 75, 28, 1.4)
		elseif best and bd < SWAT_R and now >= nextSwat then
			nextSwat = now + 2.2
			local dir = ((best.hrp.Position - pos) * FLAT)
			dir = dir.Magnitude > 0.1 and dir.Unit or hrp.CFrame.LookVector
			ctx.fx("bossSwat", { pos = best.hrp.Position, dir = dir, id = ev.id })
			ctx.sfx("heavy", best.hrp.Position, 1.2, 0.7)
			ctx.knock(best.player, dir * 105 + UP * 45, 1.6)
			best.hum:TakeDamage(16)
		end
		for _, o in ipairs(ctx.dummies(A, 0)) do
			if o ~= m and (shoved[o] or 0) < now then
				local t = ctx.torso(o)
				local off = (t.Position - pos) * FLAT
				if off.Magnitude < 10 then
					shoved[o] = now + 1
					local dir = off.Magnitude > 0.3 and off.Unit or hrp.CFrame.RightVector
					ctx.fling(o, dir * 70 + UP * 40, 2.5)
					if ctx.alive(o) then
						local part = ctx.anyPart(o)
						if part then
							ctx.hurt(o, part, "blunt", 16, nil, dir, part.Position)
						end
					end
				end
			end
		end
		ev.info = { hp = hum.Health, max = maxHp, target = best and best.player.Name }
	end
	if dead then
		local pos = hrp.Position
		ctx.fx("bossDown", { pos = pos, id = ev.id })
		ctx.banner("THE GIANT BOSS IS DOWN!", killer and ("FINAL BLOW: " .. string.upper(killer.DisplayName)) or "THE MAP IS SAFE AGAIN",
			Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 245, 200), 5)
		bb.Enabled = false
		task.wait(2)
		return
	end
	if ev.stop or not m.Parent then
		return
	end
	ctx.banner("THE GIANT BOSS GOT AWAY", "NOBODY BROUGHT IT DOWN IN TIME", Color3.fromRGB(220, 40, 50), Color3.fromRGB(255, 210, 90))
	bb.Enabled = false
	m:SetAttribute("Invuln", true)
	hrp.Anchored = true
	local base = hrp.CFrame
	ctx.fx("bossSink", { pos = hrp.Position, id = ev.id })
	for i = 1, 40 do
		if not m.Parent then
			break
		end
		m:PivotTo(base * CFrame.new(math.sin(i * 2.1) * 0.6, -i * 1.1, 0))
		task.wait(0.05)
	end
	if m.Parent then
		pcall(D.remove, m, false)
	end
end
