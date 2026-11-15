--!nocheck
-- PerkMapEvents.Earthquake (2026-11-15): 20 s of shaking on the buyer's map (+20 s each time it is bought again while
-- it runs, up to 60 ahead). Every JOLT s the dummies and props are bounced - a standing dummy is often knocked off
-- its feet - and every FISSURE s the ground splits along a line near a player: whatever stands on it is thrown up and
-- hurt. Clients shake the camera, rumble, hop their own character and draw the cracks (MapEventFX "fissure").
local JOLT, FISSURE = 0.35, 1.5

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local UP, FLAT = ctx.UP, ctx.FLAT
	ctx.threat(A.c, 600, 4)
	local nextJolt, nextCrack = 0, os.clock() + 1.2
	local cracks = 0
	while not ev.stop and ctx.now() < ev.ends do
		task.wait(0.05)
		local now = os.clock()
		-- strength: builds over 1.5 s, eases off over the last 2 s
		local k = math.clamp((ctx.now() - ev.t0) / 1.5, 0, 1) * math.clamp((ev.ends - ctx.now()) / 2, 0, 1)
		if now >= nextJolt then
			nextJolt = now + JOLT
			for _, m in ipairs(ctx.dummies(A, 0)) do
				if not m:GetAttribute("Boss") and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped") then
					local down = ctx.isRagdolled(m)
					if down then
						if rng:NextNumber() < 0.6 * k then
							ctx.fling(m, Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(10, 22), rng:NextNumber(-14, 14)) * k, 2)
						end
					elseif rng:NextNumber() < 0.28 * k then -- knocked off its feet
						ctx.blame(m, ev.by)
						ctx.fling(m, Vector3.new(rng:NextNumber(-20, 20), rng:NextNumber(14, 30), rng:NextNumber(-20, 20)), 2.2)
					end
					if rng:NextNumber() < 0.06 * k and ctx.alive(m) then
						local part = ctx.anyPart(m)
						if part then
							ctx.blame(m, ev.by)
							ctx.hurt(m, part, "blunt", rng:NextInteger(5, 11), ev.by, -UP, part.Position)
						end
					end
				end
			end
			for _, p in ipairs(ctx.props(A)) do
				if rng:NextNumber() < 0.5 * k then
					pcall(function()
						p.AssemblyLinearVelocity += Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(8, 20), rng:NextNumber(-8, 8)) * k
						p.AssemblyAngularVelocity += Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)) * k
					end)
				end
			end
		end
		if now >= nextCrack and k > 0.5 then
			nextCrack = now + FISSURE * rng:NextNumber(0.7, 1.3)
			-- a split near someone on this map (else anywhere on it)
			local ps = ctx.players(A, 0)
			local at = (#ps > 0 and rng:NextNumber() < 0.75) and ctx.pointNear(ps[rng:NextInteger(1, #ps)].hrp.Position, 12, 40, A, 15)
			at = at or ctx.randomPoint(A, 20)
			local a = rng:NextNumber() * math.pi * 2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local len = rng:NextNumber(26, 44)
			cracks += 1
			ctx.fx("fissure", { pos = at, dir = dir, len = len, id = ev.id, n = cracks, seed = rng:NextInteger(1, 1e6) })
			ctx.sfx("boom", at, 0.9, 0.55)
			for _, m in ipairs(ctx.dummies(A, 0)) do
				local t = ctx.torso(m)
				local rel = (t.Position - at) * FLAT
				local along = rel:Dot(dir)
				local side = (rel - dir * along).Magnitude
				if math.abs(along) <= len / 2 + 3 and side < 7 and not m:GetAttribute("Boss") then
					ctx.blame(m, ev.by)
					ctx.fling(m, Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(48, 70), rng:NextNumber(-12, 12)), 3)
					if ctx.alive(m) then
						local part = m:FindFirstChild(rng:NextNumber() < 0.5 and "LeftLowerLeg" or "RightLowerLeg") or ctx.anyPart(m)
						if part then
							ctx.hurt(m, part, "blunt", rng:NextInteger(14, 24), ev.by, UP, part.Position)
						end
					end
				end
			end
			for _, e in ipairs(ps) do
				local rel = (e.hrp.Position - at) * FLAT
				local along = rel:Dot(dir)
				local side = (rel - dir * along).Magnitude
				if math.abs(along) <= len / 2 + 3 and side < 7 then
					ctx.knock(e.player, Vector3.new(rng:NextNumber(-10, 10), 55, rng:NextNumber(-10, 10)), 1.2)
				end
			end
		end
		ev.info = { cracks = cracks, k = k }
	end
end
