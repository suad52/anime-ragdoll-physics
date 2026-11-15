--!nocheck
-- GomuServer.Moves.Gatling (owner: gatling): Q, Gum-Gum GATLING (CONTRACT.md 8.2 / 4.2 / 5.5).
-- require(this)(S) -> { Gatling = handler, __reset = reset }. S = GomuServer.Core's API (CONTRACT 5.2).
-- The cast (seconds after t0): 0 .. Windup the PUFF (the client roots him); Windup .. Windup + Duration the storm: every
-- Tick the cone (S.inCone from the chest along the steered flat dir, Range / HalfAngle / MaxDY, line of sight from the
-- chest) is hit: standing bodies S.hurt(TickDamage) + S.react("flinch", TickSlide, TickStun); ragdolled bodies / corpses
-- are juggled (S.strike dir*JuggleVel.X + UP*JuggleVel.Y, JuggleRag) so they stay airborne in the storm. GatlingHit is
-- throttled to one per body per HitEvery. Every ChipEvery a world ray down a random line of the cone (yaw +-HalfAngle,
-- pitch ChipPitch) chips the facade / street it meets (S.blast ChipRadius + BreakBlast ChipSpeed) + GatlingChip.
-- The dir follows the streamed camera aim (S.liveAim) at TurnRate deg/s until FinalAt; GatlingAim is rebroadcast when
-- it moved > 3 deg (<= 10 Hz). At FinalAt the heavy last fist: the cone (+FinalRangeBonus, +FinalHalfBonus) is struck
-- (dir*FinalFling + UP*FinalUp, FinalDamage, RagTime, FinalHitStop) and the end point (the first wall down the dir, or
-- Range) is blasted (FinalBlastRadius + BreakBlast FinalBreakSpeed) -> GatlingEnd { why = "done", pos }.
-- The caster is re-checked every frame (S.valid): invalid -> GatlingEnd { why = "cancel" } + S.release. __reset bumps
-- st.Gatling.gen and cancels a live cast.
return function(S)
	local M = {}
	local UP = S.UP or Vector3.yAxis
	local rng = Random.new()

	local function num(v, d)
		return type(v) == "number" and v == v and v or d
	end
	local function v2(v, x, y)
		if typeof(v) == "Vector2" then
			return v.X, v.Y
		end
		return x, y
	end
	local function range2(v, a, b)
		if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then
			return v[1], v[2]
		end
		return a, b
	end

	-- the flat angle (deg) between two flat unit vectors
	local function angle(a, b)
		return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
	end
	-- turn flat unit a toward flat unit b by at most maxDeg (about UP)
	local function turnToward(a, b, maxDeg)
		local ang = angle(a, b)
		if ang <= maxDeg or ang < 1e-3 then
			return b
		end
		local s = a:Cross(b).Y >= 0 and 1 or -1
		local r = CFrame.fromAxisAngle(UP, math.rad(maxDeg) * s):VectorToWorldSpace(a)
		return S.flatDir(r, a)
	end

	local function cancel(p, cast, why)
		if cast.dead then
			return
		end
		cast.dead = true
		if cast.conn then
			pcall(function()
				cast.conn:Disconnect()
			end)
			cast.conn = nil
		end
		pcall(S.fire, "GatlingEnd", { id = cast.id, userId = cast.userId, why = why or "cancel" })
		pcall(S.release, p, cast.id)
	end

	function M.Gatling(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Gatling")
		if not char then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local mode = S.inMode(p, char) == true
		local c = S.cfgFor(p, char, "Gatling") or {}
		local W = num(c.Windup, 0.28)
		local dur = num(c.Duration, 1.5)
		local B = W + dur
		local tick = math.max(num(c.Tick, 0.075), 0.03)
		local range = num(c.Range, 22)
		local half = num(c.HalfAngle, 26)
		local maxDY = num(c.MaxDY, 10)
		local finalAt = math.max(num(c.FinalAt, B + 0.08), W)
		local steer = c.Steer ~= false
		local turnRate = num(c.TurnRate, 110)
		local chipEvery = math.max(num(c.ChipEvery, 0.2), 0.05)
		local chipR = num(c.ChipRadius, 6.5)
		local chipSpeed = num(c.ChipSpeed, 70)
		local chipP0, chipP1 = range2(c.ChipPitch, -5, 20)
		local tickDmg = num(c.TickDamage, 2.2)
		local tickStun = num(c.TickStun, 0.3)
		local tickSlide = num(c.TickSlide, 0.35)
		local power = num(c.ReactPower, 0.55)
		local jx, jy = v2(c.JuggleVel, 14, 10)
		local jRag = num(c.JuggleRag, 1.5)
		local hitEvery = num(c.HitEvery, 0.15)
		local chestUp = num(c.ChestUp, 1.2)

		-- the flat camera aim, falling back to where he faces
		local look = S.flatDir(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
		local aim = payload.aim
		if typeof(aim) ~= "Vector3" or not S.finite(aim) or aim.Magnitude < 1e-3 then
			aim = look
		end
		local dir = S.flatDir(aim, look)

		local id = S.commit(p, "Gatling", t, num(c.Lock, 2.0), char)
		local uid = p.UserId
		st.Gatling = type(st.Gatling) == "table" and st.Gatling or { gen = 0 }
		local G = st.Gatling
		if type(G.cast) == "table" then
			cancel(p, G.cast, "cancel")
		end
		G.gen = (G.gen or 0) + 1
		local cast = { id = id, userId = uid, dead = false, gen = G.gen }
		G.cast = cast

		S.fire("GatlingStart", {
			id = id, userId = uid, t0 = t, windup = W, dur = dur, finalAt = finalAt, dir = dir, range = range,
			half = half, steer = steer, mode = mode,
		})
		-- (integration) the crowd Threat fires with the final fist: a cast-time Threat sent bodies running out of the cone

		local finalDmg = num(c.FinalDamage, 12)
		local finalFling = num(c.FinalFling, 95)
		local finalUp = num(c.FinalUp, 30)
		local rag = num(c.RagTime, 2.4)
		local finalHS = num(c.FinalHitStop, 0.06)
		local finalBlastR = num(c.FinalBlastRadius, 8)
		local finalBreak = num(c.FinalBreakSpeed, 130)
		local finalRange = range + num(c.FinalRangeBonus, 2)
		local finalHalf = half + num(c.FinalHalfBonus, 4)

		local nextTick = W
		local nextChip = W + 0.04
		local lastE = 0
		local sentDir, sentAt = dir, -1
		local lastHit = {} -- [model] = e of its last GatlingHit
		local exclude = { [char] = true }

		local function hitMsg(m, pos, e)
			if not lastHit[m] or e - lastHit[m] >= hitEvery then
				lastHit[m] = e
				S.fire("GatlingHit", { id = id, userId = uid, model = m, pos = pos })
			end
		end

		cast.conn = S.timeline("Gatling", t, function(e)
			if cast.dead or G.gen ~= cast.gen then
				return true
			end
			local dt = math.clamp(e - lastE, 0, 0.25)
			lastE = e
			if not S.valid(p, char) then
				cancel(p, cast, "cancel")
				return true
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then
				cancel(p, cast, "cancel")
				return true
			end

			-- steering: the cone follows the streamed camera aim
			if steer and e < finalAt then
				local la = S.liveAim(p, id)
				if typeof(la) == "Vector3" and S.finite(la) and la.Magnitude > 1e-3 then
					dir = turnToward(dir, S.flatDir(la, dir), turnRate * dt)
					if angle(dir, sentDir) > 3 and e - sentAt >= 0.1 then
						sentDir, sentAt = dir, e
						S.fire("GatlingAim", { id = id, userId = uid, dir = dir })
					end
				end
			end
			if e < W then
				return false
			end
			local chest = root.Position + UP * chestUp

			-- the storm ticks (at most 3 per frame after a hitch)
			local n = 0
			while nextTick <= e and nextTick < B - 1e-4 and n < 3 do
				nextTick += tick
				n += 1
				local rows = S.inCone(chest, dir, range, half, { los = chest, maxDY = maxDY, exclude = exclude, caster = p })
				for _, r in ipairs(rows) do
					local m = r.m
					if m ~= char then
						if S.isRagdolled(m) or not S.alive(m) then
							-- juggled: kept airborne in the storm
							S.strike(p, m, dir * jx + UP * jy, tickDmg, jRag)
						else
							S.hurt(p, m, tickDmg)
							local push = S.flatDir(dir + S.randomFlat() * 0.3, dir)
							S.react(p, m, push, power, "flinch", tickSlide, tickStun)
						end
						hitMsg(m, r.tp, e)
					end
				end
			end
			if nextTick <= e and nextTick < B - 1e-4 then
				nextTick = e + tick -- hitched badly: skip the backlog rather than burst it
			end

			-- facade chipping down random lines of the cone
			if nextChip <= e and nextChip < B then
				nextChip = math.max(nextChip + chipEvery, e)
				local rd = CFrame.fromAxisAngle(UP, math.rad(rng:NextNumber(-half, half))):VectorToWorldSpace(dir)
				local right = rd:Cross(UP)
				if right.Magnitude > 1e-3 then
					rd = CFrame.fromAxisAngle(right.Unit, math.rad(rng:NextNumber(chipP0, chipP1))):VectorToWorldSpace(rd)
				end
				rd = rd.Unit
				local d = S.clampPath(chest, rd, range)
				if d < range - 1e-3 then
					local hitPos = chest + rd * (d + 2)
					S.blast(p, hitPos, chipR, { dir = rd, speed = chipSpeed })
					S.fire("GatlingChip", { id = id, userId = uid, pos = hitPos, normal = -rd })
				end
			end

			-- the heavy last fist
			if e >= finalAt then
				local rows = S.inCone(chest, dir, finalRange, finalHalf, { los = chest, maxDY = maxDY, exclude = exclude, caster = p })
				local spin = dir:Cross(UP) * 10
				for _, r in ipairs(rows) do
					if r.m ~= char then
						S.strike(p, r.m, dir * finalFling + UP * finalUp, finalDmg, rag, { hitStop = finalHS, spin = spin })
						S.fire("GatlingHit", { id = id, userId = uid, model = r.m, pos = r.tp })
					end
				end
				local d = S.clampPath(chest, dir, range)
				local wall = d < range - 1e-3
				local endPos = chest + dir * (wall and (d + 2) or range)
				S.blast(p, endPos, finalBlastR, { dir = dir, speed = finalBreak })
				pcall(S.pushLoose, endPos, finalBlastR + 4, 90, 0.3)
				pcall(S.hook, "Threat", endPos, num(c.ThreatRadius, range * 0.75), 1.5)
				cast.dead = true
				cast.conn = nil
				S.fire("GatlingEnd", { id = id, userId = uid, why = "done", pos = endPos })
				return true
			end
			return false
		end, function()
			cancel(p, cast, "cancel")
		end)
	end

	-- died / respawn / unequip / left: a storm still running is called off
	function M.__reset(p, st, why)
		local G = type(st) == "table" and st.Gatling
		if type(G) == "table" then
			G.gen = (G.gen or 0) + 1
			if type(G.cast) == "table" then
				cancel(p, G.cast, "cancel")
				G.cast = nil
			end
		end
	end

	return M
end
