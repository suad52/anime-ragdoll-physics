--!nocheck
-- PerkMapEvents.Tornado (2026-11-15): a funnel that wanders the buyer's map for 35 s. Within RADIUS it drags every
-- dummy and loose prop into a spiral, carries them up to about TOP studs and throws them out of the top; things it
-- carries are battered. Players are pulled by their own client (PerkMapEventsClient.Tornado, marker attribute Radius).
local RADIUS, TOP, SPEED = 60, 58, 15

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local UP, FLAT = ctx.UP, ctx.FLAT
	ev.marker:SetAttribute("Radius", RADIUS)
	ev.marker:SetAttribute("Top", TOP)
	-- it touches down 45-80 studs from the buyer, so they see it come for them
	local pos = ctx.pointNear(ev.byPos, 45, 80, A, 30) or ctx.randomPoint(A, 40)
	local target = ctx.randomPoint(A, 40)
	ev.marker.CFrame = CFrame.new(pos)
	ctx.threat(pos, 120, 4)
	local batter = {}
	local nextTarget = 0
	local last = os.clock()
	local carried = 0
	while not ev.stop and ctx.now() < ev.ends do
		task.wait(0.05)
		local now = os.clock()
		local dt = math.min(now - last, 0.2)
		last = now
		-- wander: toward a spot, now and then toward a player on this map
		if ((target - pos) * FLAT).Magnitude < 8 or now > nextTarget then
			nextTarget = now + rng:NextNumber(5, 9)
			local ps = ctx.players(A, 0)
			if #ps > 0 and rng:NextNumber() < 0.45 then
				local pp = ps[rng:NextInteger(1, #ps)].hrp.Position
				target = ctx.pointNear(pp, 0, 25, A, 30) or ctx.randomPoint(A, 40)
			else
				target = ctx.randomPoint(A, 40)
			end
		end
		local step = (target - pos) * FLAT
		if step.Magnitude > 0.1 then
			local np = ctx.clampIn(A, pos + step.Unit * math.min(step.Magnitude, SPEED * dt), 30)
			local g = ctx.ground(np.X, np.Z, pos.Y + 60)
			pos = Vector3.new(np.X, g.Y, np.Z)
		end
		ev.marker.CFrame = CFrame.new(pos)
		carried = 0
		for _, m in ipairs(ctx.dummies(A, 0)) do
			local torso = ctx.torso(m)
			local off = (torso.Position - pos) * FLAT
			local dist = math.max(off.Magnitude, 1)
			local h = torso.Position.Y - pos.Y
			if dist < RADIUS and h < TOP + 25 and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") and not m:GetAttribute("Boss") then
				local pull = math.clamp(1 - dist / RADIUS, 0, 1)
				if pull > 0.12 then
					carried += 1
					ctx.ragdoll(m, 2.5)
					ctx.blame(m, ev.by)
					local radial = off / dist
					local tang = UP:Cross(radial)
					local want
					if h > TOP then -- thrown out of the top
						want = radial * 75 + tang * 30 + UP * 12
					else
						want = tang * (40 + 55 * pull) - radial * 26 * pull + UP * (18 + 42 * pull)
					end
					ctx.steer(m, function()
						return want
					end, 3 + 12 * pull, dt)
					if pull > 0.45 and now > (batter[m] or 0) then
						batter[m] = now + rng:NextNumber(0.6, 1.2)
						local part = ctx.anyPart(m)
						if part and ctx.alive(m) then
							ctx.hurt(m, part, "blunt", rng:NextInteger(6, 13), ev.by, nil, part.Position)
						end
					end
				end
			end
		end
		for _, p in ipairs(ctx.props(A)) do
			local off = (p.Position - pos) * FLAT
			local dist = math.max(off.Magnitude, 1)
			local h = p.Position.Y - pos.Y
			if dist < RADIUS and h < TOP + 25 then
				local pull = math.clamp(1 - dist / RADIUS, 0, 1)
				if pull > 0.12 then
					local radial = off / dist
					local want = h > TOP and (radial * 80 + UP * 15) or (UP:Cross(radial) * (45 + 55 * pull) - radial * 26 * pull + UP * (20 + 40 * pull))
					pcall(function()
						p.AssemblyLinearVelocity = p.AssemblyLinearVelocity:Lerp(want, math.min(1, dt * (3 + 10 * pull)))
						p.AssemblyAngularVelocity = p.AssemblyAngularVelocity:Lerp(Vector3.new(rng:NextNumber(-8, 8), 10, rng:NextNumber(-8, 8)), dt * 2)
					end)
				end
			end
		end
		ev.info = { pos = pos, carried = carried }
	end
end
