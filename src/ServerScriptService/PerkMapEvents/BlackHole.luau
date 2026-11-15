--!nocheck
-- PerkMapEvents.BlackHole (2026-11-15): a black hole opens HEIGHT studs over the buyer's map (24 s). It grows for
-- GROW s, pulls every dummy and loose prop within its reach harder and harder, and SWALLOWS what reaches its core:
-- a dummy dies (credited to the buyer) and is drawn in and gone, a prop is gone. In its last COLLAPSE s it shrinks to
-- a point, then bursts: everything near is thrown away from it and players are knocked down. Players are pulled by
-- their own client (PerkMapEventsClient.BlackHole: marker attributes Reach, Core, Power).
local HEIGHT, GROW, COLLAPSE, CORE = 62, 3, 1.6, 9

return function(ctx, ev)
	local A = ev.area
	local UP, FLAT = ctx.UP, ctx.FLAT
	local reach = math.max(A.h.X, A.h.Z) * 0.9 + 40
	-- over the middle of the map, pulled a little toward the buyer
	local base = A.c
	if typeof(ev.byPos) == "Vector3" then
		base = base:Lerp(Vector3.new(ev.byPos.X, 0, ev.byPos.Z), 0.35)
	end
	local g = ctx.ground(base.X, base.Z)
	local pos = Vector3.new(base.X, g.Y + HEIGHT, base.Z)
	ev.marker.CFrame = CFrame.new(pos)
	ev.marker:SetAttribute("Reach", reach)
	ev.marker:SetAttribute("Core", CORE)
	ctx.threat(pos, reach, 6)
	local gone = {}
	local swallowed = 0
	local function swallow(m)
		gone[m] = true
		swallowed += 1
		ctx.blame(m, ev.by)
		local hum = m:FindFirstChildOfClass("Humanoid")
		if ctx.Injury and ctx.Injury.kill and ctx.alive(m) then
			pcall(ctx.Injury.kill, m, "Swallowed by a black hole")
		end
		if hum and hum.Health > 0 then
			hum.Health = 0
		end
		ctx.fx("bhSwallow", { pos = pos, id = ev.id })
		task.delay(0.1, function()
			-- drawn in: every part is pinned and slides into the core as it shrinks away
			local parts = {}
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
					p.CanCollide = false
					table.insert(parts, { p = p, cf = p.CFrame, size = p.Size })
				end
			end
			for i = 1, 8 do
				local a = i / 8
				for _, e in ipairs(parts) do
					if e.p.Parent then
						e.p.CFrame = e.cf:Lerp(CFrame.new(pos), a * a) * CFrame.Angles(0, a * 6, a * 3)
						e.p.Size = e.size * math.max(1 - a, 0.05)
					end
				end
				task.wait(0.05)
			end
			if ctx.Dummies and ctx.Dummies.remove then
				pcall(ctx.Dummies.remove, m, false)
			elseif m.Parent then
				m:Destroy()
			end
		end)
	end
	local last = os.clock()
	local collapsing = false
	while not ev.stop and ctx.now() < ev.ends do
		task.wait(0.05)
		local now = os.clock()
		local dt = math.min(now - last, 0.2)
		last = now
		local t, left = ctx.now() - ev.t0, ev.ends - ctx.now()
		local power = math.clamp(t / GROW, 0, 1)
		if left < COLLAPSE then
			power *= math.clamp(left / COLLAPSE, 0, 1) * 0.6
			if not collapsing then
				collapsing = true
				ctx.fx("bhCollapse", { pos = pos, id = ev.id, t = COLLAPSE })
			end
		end
		ev.marker:SetAttribute("Power", power)
		for _, m in ipairs(ctx.dummies(A, 60)) do
			if not gone[m] and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") then
				local torso = ctx.torso(m)
				local off = pos - torso.Position
				local d = off.Magnitude
				if d < CORE and power > 0.5 and not m:GetAttribute("Boss") then
					swallow(m)
				elseif d < reach then
					local k = (1 - d / reach) ^ 0.6 * power
					if m:GetAttribute("Boss") then
						k *= 0.15
					end
					if k > 0.06 then
						if not m:GetAttribute("Boss") then
							ctx.ragdoll(m, 2.5)
						end
						ctx.blame(m, ev.by)
						local dir = off / math.max(d, 0.1)
						local tang = UP:Cross(dir * FLAT)
						if tang.Magnitude > 0.01 then
							tang = tang.Unit
						end
						local want = dir * (22 + 150 * k) + tang * 30 * k
						ctx.steer(m, function()
							return want
						end, 1.5 + 7 * k, dt)
					end
				end
			end
		end
		for _, p in ipairs(ctx.props(A)) do
			local off = pos - p.Position
			local d = off.Magnitude
			if d < CORE + 2 and power > 0.5 then
				ctx.fx("bhSwallow", { pos = pos, id = ev.id, small = true })
				local model = p.Parent and p.Parent:IsA("Model") and p.Parent ~= workspace and p.Parent.Name ~= "Gore" and p.Parent or p
				model:Destroy()
			elseif d < reach then
				local k = (1 - d / reach) ^ 0.6 * power
				if k > 0.06 then
					pcall(function()
						p.AssemblyLinearVelocity = p.AssemblyLinearVelocity:Lerp(off.Unit * (25 + 160 * k), math.min(1, dt * (1.5 + 7 * k)))
					end)
				end
			end
		end
		ev.info = { swallowed = swallowed, power = power }
	end
	if ev.stop then
		return
	end
	-- the burst
	ctx.fx("bhBurst", { pos = pos, id = ev.id })
	ctx.sfx("boom", pos, 1.2, 0.6)
	for _, m in ipairs(ctx.dummies(A, 60)) do
		if not gone[m] and not m:GetAttribute("Boss") then
			local torso = ctx.torso(m)
			local off = torso.Position - pos
			if off.Magnitude < 170 then
				local k = 1 - off.Magnitude / 170
				ctx.fling(m, (off.Unit + UP * 0.3).Unit * (40 + 110 * k), 3)
			end
		end
	end
	for _, e in ipairs(ctx.players(A, 20)) do
		local off = e.hrp.Position - pos
		if off.Magnitude < 150 then
			local k = 1 - off.Magnitude / 150
			ctx.knock(e.player, ((off * FLAT).Unit + UP * 0.6).Unit * (40 + 70 * k), 1 + k)
		end
	end
	ev.info = { swallowed = swallowed, burst = true }
end
