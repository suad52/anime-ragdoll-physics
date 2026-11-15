--!nocheck
-- PerkMapEvents.Flood (2026-11-15): the water rises over the buyer's whole map. RISE s up to DEPTH studs over its
-- ground, it stays (60 s from the purchase; +30 s each time it is bought again while it runs, up to 150 ahead), then
-- DRAIN s back down. The surface (world Y) is the marker's attribute Level: every client draws the water from it and
-- floats / swims its own character (PerkMapEventsClient.Flood). Here: a dummy whose waist is under it is lifted off
-- its feet and drifts on a slow current; one whose head stays under too long drowns (as in the disaster box's flood).
-- Loose props bob up too.
-- (2026-11-15, owner: "Flood makes the game extremely laggy") measured in a playtest: server frames went from 17 ms to
-- 73-82 ms and the client to 4-5 fps, because EVERY submerged dummy on the map (100+ of the ~200) was ragdolled and
-- pushed ten times a second - each push re-claimed the body (RagdollService), and 100 server-simulated ragdolls
-- streamed to every screen. Now only the bodies near a player float: the ACTIVE_MAX nearest within ACTIVE_R of anyone
-- on the map, picked again every PICK_EVERY s. They are ragdolled once and then only kept down and held on the server
-- (RagdollService.Stay / Hold: no claim, no ownership change). The rest of the map is left alone - out of sight,
-- standing in the water, and they do not drown.
local DEPTH, RISE, DRAIN = 14, 10, 7
local ACTIVE_R, ACTIVE_MAX, PICK_EVERY = 130, 26, 0.5
local PROPS_MAX = 30

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local UP, FLAT = ctx.UP, ctx.FLAT
	local R = ctx.Ragdoll
	-- the ground level: the median of a few samples over the map
	local ys = {}
	for _ = 1, 9 do
		table.insert(ys, ctx.randomPoint(A, 30).Y)
	end
	table.sort(ys)
	local base = ys[5]
	ev.marker.CFrame = CFrame.new(A.c.X, base, A.c.Z)
	ev.marker:SetAttribute("Base", base)
	ev.marker:SetAttribute("Level", base)
	ev.marker:SetAttribute("Depth", DEPTH)
	local drown = {}
	local active, activeProps = {}, {}
	local downed = {} -- [model] = true once this flood has ragdolled it
	local level = base
	local heading = rng:NextNumber() * math.pi * 2
	local last = os.clock()
	local pickAt = 0
	local function nearestPlayer(pos, pl)
		local best = math.huge
		for _, P in ipairs(pl) do
			best = math.min(best, ((P.hrp.Position - pos) * FLAT).Magnitude)
		end
		return best
	end
	local function pick()
		local pl = ctx.players(A, 60)
		local cand = {}
		if #pl > 0 then
			for _, m in ipairs(ctx.dummies(A, 10)) do
				local t = ctx.torso(m)
				if t and t.Position.Y < level + 1 and not m:GetAttribute("Boss") then
					local d = nearestPlayer(t.Position, pl)
					if d <= ACTIVE_R then
						table.insert(cand, { m, d })
					end
				end
			end
			table.sort(cand, function(a, b)
				return a[2] < b[2]
			end)
		end
		local nextActive = {}
		for i = 1, math.min(#cand, ACTIVE_MAX) do
			nextActive[cand[i][1]] = true
		end
		active = nextActive
		local props = {}
		if #pl > 0 then
			for _, p in ipairs(ctx.props(A)) do
				if p.Position.Y < level + 1 and nearestPlayer(p.Position, pl) <= ACTIVE_R then
					table.insert(props, p)
					if #props >= PROPS_MAX then
						break
					end
				end
			end
		end
		activeProps = props
		for m in pairs(drown) do
			if not active[m] then
				drown[m] = nil
			end
		end
	end
	while not ev.stop do
		task.wait(0.1)
		local now = os.clock()
		local dt = math.min(now - last, 0.3)
		last = now
		local t, left = ctx.now() - ev.t0, ev.ends - ctx.now()
		local depth
		if left <= 0 then
			depth = DEPTH * math.clamp(1 + left / DRAIN, 0, 1)
			if left <= -DRAIN then
				break
			end
		else
			depth = DEPTH * math.clamp(t / RISE, 0, 1)
		end
		level = base + depth
		ev.marker:SetAttribute("Level", level)
		heading += dt * 0.05
		local current = Vector3.new(math.cos(heading), 0, math.sin(heading)) * 3
		if now >= pickAt then
			pickAt = now + PICK_EVERY
			pick()
		end
		local n = 0
		for m in pairs(active) do
			if not m.Parent then
				active[m] = nil
				continue
			end
			n += 1
			local waist = m:FindFirstChild("LowerTorso") or ctx.torso(m)
			local head = m:FindFirstChild("Head")
			if waist and waist.Position.Y < level and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") then
				if R and R.IsRagdolled and R.IsRagdolled(m) then
					-- already down: keep it down and on the server (the pushes below must land), without a re-claim
					pcall(R.Stay, m, 2.5)
					pcall(R.Hold, m, 0.6)
				elseif not downed[m] or now - downed[m] > 1 then
					downed[m] = now
					ctx.ragdoll(m, 2.5)
					if R and R.Hold then
						pcall(R.Hold, m, 0.6)
					end
				end
				for _, p in ipairs(m:GetChildren()) do
					if p:IsA("BasePart") and not p.Anchored and p.Position.Y < level then
						local under = math.clamp(level - p.Position.Y, 0, 4)
						p.AssemblyLinearVelocity = p.AssemblyLinearVelocity * 0.86 + current * 0.25 + UP * (2.2 + under * 1.6)
					end
				end
			end
			if head and head.Position.Y < level - 0.5 and ctx.alive(m) and ctx.Injury and ctx.Injury.get then
				drown[m] = (drown[m] or 0) + dt
				local st = ctx.Injury.get(m)
				if st and not st.dead then
					st.touched = true
					st.awakeCap = math.max(0, 100 - drown[m] * 12)
					if drown[m] > 9 then
						ctx.blame(m, ev.by)
						st.fatal = "Drowned"
						st.heartStopAt = st.heartStopAt or os.clock()
					end
				end
			elseif drown[m] then
				drown[m] = math.max(0, drown[m] - dt * 0.5)
			end
		end
		for _, p in ipairs(activeProps) do
			if p.Parent and not p.Anchored and p.Position.Y < level then
				pcall(function()
					local under = math.clamp(level - p.Position.Y, 0, 4)
					p.AssemblyLinearVelocity = p.AssemblyLinearVelocity * 0.88 + current * 0.3 + UP * (2.5 + under * 1.8)
				end)
			end
		end
		ev.info = { level = level, depth = depth, floating = n, props = #activeProps }
	end
	ev.marker:SetAttribute("Level", base)
end
