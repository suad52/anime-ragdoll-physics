--!nocheck
-- GomuServer.Moves.Gear5 (owner gear5): G - GEAR FIFTH (the ultimate) and BAJRANG GUN (G while the mode is on).
-- CONTRACT §8.5. G always arrives as "Gear5"; while S.inMode it is routed to bajrang() (own cooldown "Bajrang").
-- Gear Fifth (Config.Gear5, seconds after the cast's server time t0):
--   0.00 gate + commit (Lock 2.4) + S.shield for the cinematic -> Gear5Cast; Threat(pos, 55, 2.5)
--   1.15 BURST: S.radial round him (28: 32 -> 17.6 dmg, fling 150 -> 90, up .6, rag 3.4) + a RAISED WorldBlast (24: glass
--        and facades, but no street crater under his own feet) + 6 outward BreakBlasts on a ring at r 18 (holes) + 8
--        GroundFX craters at r 14 -> Gear5Burst
--   1.90 MODE: S.startMode(p, char, Mode.Time) -> Gear5On { untilT }
-- Bajrang Gun (Config.Bajrang; raw numbers - it only exists inside the mode, so its Damage is NOT x DamageMul again):
--   0.00 the cursor point -> the ground under it, pushed >= MinFlat 22 from him (flat) -> commit "Bajrang" (Lock 1.9)
--        -> BajrangCast
--   0.55 Threat(g, 80, 2.5)
--   1.45 IMPACT: S.radial (46: 70 -> 31.5, fling 230 -> 120, LOS from 6 up) + S.blast(48, BreakBlast down, crater 16)
--        + 8 GroundFX craters at r 30 + 6 outward BreakBlasts (22) at r 32 (ring pieces within AvoidRadius of him are
--        skipped) -> BajrangImpact. Lands even if the mode ended meanwhile; a dead / unequipped caster -> BajrangCancel.
-- Gear Fifth has no cancel kind: a caster who dies mid-awakening just never gets the burst / mode (clients see the
-- death and stop drawing).
return function(S)
	local M = {}
	local UP = S.UP or Vector3.yAxis
	local TAU = math.pi * 2

	local function num(v, d)
		return type(v) == "number" and v or d
	end
	local function call(name, ...)
		local fn = S[name]
		if type(fn) ~= "function" then
			if type(S.warn) == "function" then
				S.warn("Gear5", "S." .. tostring(name) .. " is missing", 10)
			end
			return nil
		end
		local ok, a, b, c = pcall(fn, ...)
		if not ok then
			if type(S.warn) == "function" then
				S.warn("Gear5", tostring(name) .. ": " .. tostring(a), 5)
			end
			return nil
		end
		return a, b, c
	end
	local function log(...)
		if type(S.log) == "function" then
			pcall(S.log, ...)
		end
	end
	local function mine(st)
		st.Gear5 = st.Gear5 or { gen = 0 }
		return st.Gear5
	end
	local function cfgFor(p, char, move)
		local ok, c = pcall(S.cfgFor, p, char, move)
		if ok and type(c) == "table" then
			return c
		end
		return S.CFG[move] or {}
	end
	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end

	-- every body within `radius` of `pos` flung straight out (S.radial; a hand-rolled copy if Core does not have it)
	local function radial(p, char, pos, radius, c, los)
		local o = {
			damage = num(c.Damage, 30), farMul = num(c.FarMul, 0.5), flingNear = num(c.FlingNear, 150),
			flingFar = num(c.FlingFar, 90), up = num(c.Up, 0.5), rag = num(c.RagTime, 3), hitStop = c.HitStop,
			exclude = { [char] = true }, los = los,
		}
		if type(S.radial) == "function" then
			return call("radial", p, pos, radius, o) or {}
		 end
		local rows = call("inRadius", pos, radius, { exclude = o.exclude, los = (los == true) and pos or los }) or {}
		for _, h in ipairs(rows) do
			local m = h.m
			if m and m.Parent and m ~= char then
				local tp = h.tp or pos
				local d = h.d or (tp - pos).Magnitude
				local k = 1 - math.clamp(d / math.max(radius, 1), 0, 1)
				local dmg = o.damage * (o.farMul + (1 - o.farMul) * k)
				local speed = o.flingFar + (o.flingNear - o.flingFar) * k
				local out = S.flatDir(tp - pos, S.randomFlat())
				call("strike", p, m, (out + UP * o.up).Unit * speed, dmg, o.rag, { hitStop = o.hitStop, spin = S.randomUnit() * 12 })
			end
		end
		call("pushLoose", pos, radius + 8, o.flingFar, 0.5, 1)
		return rows
	end

	-- the ONE destruction call (S.blast); a hook-level copy if Core does not have it
	local function blast(p, pos, radius, o)
		o = o or {}
		if type(S.blast) == "function" then
			return call("blast", p, pos, radius, o)
		end
		call("hook", "WorldBlast", pos, radius, p.UserId)
		if o.dir then
			call("hook", "BreakBlast", pos, radius, o.dir, o.speed or 120, p.UserId)
		end
		if type(o.crater) == "table" then
			local g = call("groundAt", pos, o.crater.depth or 14)
			if g then
				call("ground", "impact", g, num(o.crater.r, 8), num(o.crater.rocks, 10), num(o.crater.speed, 70))
			end
		end
	end

	-- the n points of a ring round `center` at radius r (a random phase), each dropped onto the ground under it; points
	-- within `avoid.r` (flat) of `avoid.pos` are left out (the caster's own feet)
	local function ringPoints(center, n, r, avoid)
		local out = {}
		local phase = math.random() * TAU
		for i = 1, n do
			local a = phase + (i - 1) / n * TAU
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local pt = center + dir * r
			local skip = avoid and flat(pt - avoid.pos).Magnitude < avoid.r
			if not skip then
				local g = call("groundAt", pt + UP * 4, 40)
				table.insert(out, { pos = g or pt, dir = dir, ground = g ~= nil, i = i })
			end
		end
		return out
	end
	local function ringCraters(center, rc, avoid)
		local pts = ringPoints(center, num(rc.n, 8), num(rc.r, 14), avoid)
		for _, pt in ipairs(pts) do
			if pt.ground then
				task.delay((pt.i - 1) * num(rc.delay, 0.06), function()
					call("ground", "impact", pt.pos, num(rc.size, 3), num(rc.rocks, 2), num(rc.speed, 60))
				end)
			end
		end
	end
	local function ringBlasts(p, center, rb, speed, avoid)
		local pts = ringPoints(center, num(rb.n, 6), num(rb.r, 18), avoid)
		for _, pt in ipairs(pts) do
			blast(p, pt.pos + UP * 2, num(rb.radius, 12), { dir = (pt.dir + UP * 0.35).Unit, speed = num(rb.speed, speed or 140) })
		end
		return #pts
	end

	---------------------------------------------------------------------------------------------------
	-- GEAR FIFTH: the awakening
	local function awaken(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Gear5")
		if not char then
			return
		end
		local c = cfgFor(p, char, "Gear5")
		local lock = num(c.Lock, 2.4)
		local id = S.commit(p, "Gear5", t, lock, char)
		local me = mine(st)
		me.gen += 1
		local gen = me.gen
		call("shield", char, lock + 0.1)
		local pos = hrp.Position
		local T = {
			burst = num(c.BurstAt, 1.15), laugh = num(c.LaughAt, 1.5), mode = num(c.ModeAt, 1.9), shot = num(c.ShotEnd, 1.15),
		}
		S.fire("Gear5Cast", {
			id = id, userId = p.UserId, t0 = t, pos = pos,
			drumAt = type(c.DrumAt) == "table" and c.DrumAt or { 0, 0.32, 0.64, 0.9 },
			burstAt = T.burst, laughAt = T.laugh, modeAt = T.mode, shotEnd = T.shot,
		})
		-- (integration) the crowd Threat fires at the burst: a cast-time Threat emptied the burst radius before 1.15 s
		local function ok()
			return me.gen == gen and S.valid(p, char)
		end

		S.at(t, T.burst, function()
			if not ok() then
				S.release(p, id)
				return
			end
			local center = hrp.Parent and hrp.Position or pos
			local g = call("floorBelow", center, 30) or call("groundAt", center, 30) or (center - UP * 3)
			local R = num(c.Radius, 28)
			local rows = radial(p, char, center, R, c, true)
			call("hook", "Threat", center, num(c.ThreatRadius, 55), num(c.ThreatTime, 2.5))
			-- raised above CityDestruction's crater threshold (pos.Y - 2 < radius * 0.7): no street crater under him
			local BR = num(c.BlastRadius, 24)
			blast(p, g + UP * (BR * 0.7 + 3), BR, {})
			local avoid = { pos = center, r = 8 }
			local rb = type(c.RingBlasts) == "table" and c.RingBlasts or { r = 18, n = 6, radius = 12, speed = 140 }
			ringBlasts(p, g, rb, 140, avoid)
			local rc = type(c.RingCraters) == "table" and c.RingCraters or { r = 14, n = 8, size = 3, rocks = 2, speed = 60, delay = 0.05 }
			ringCraters(g, rc, avoid)
			S.fire("Gear5Burst", { id = id, userId = p.UserId, pos = center, radius = R })
			log("Gear5 burst: %d bodies", #rows)
		end)

		S.at(t, T.mode, function()
			if not ok() then
				S.release(p, id)
				return
			end
			local secs = num((S.CFG.Mode or {}).Time, 15)
			S.startMode(p, char, secs)
			local untilT = char:GetAttribute("Gear5Until")
			S.fire("Gear5On", { id = id, userId = p.UserId, untilT = type(untilT) == "number" and untilT or (S.now() + secs) })
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- BAJRANG GUN: the titanic fist out of the clouds
	local function cancelBajrang(p, me, id)
		if me.bajrang == id then
			me.bajrang = nil
			S.fire("BajrangCancel", { id = id, userId = p.UserId })
		end
		S.release(p, id)
	end

	local function bajrang(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Bajrang")
		if not char then
			return
		end
		local c = S.CFG.Bajrang or {}
		local chest = hrp.Position + UP * 1.5
		local look = S.flatDir(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
		local point, normal = call("cursorPoint", payload, chest, num(c.Range, 140), num(c.MinRange, 15))
		if typeof(point) ~= "Vector3" then
			point = chest + look * num(c.Range, 140)
		end
		local probe = point + ((typeof(normal) == "Vector3") and normal * 1.5 or Vector3.zero)
		local g = call("groundAt", probe, 300) or point
		-- never on top of himself: the crater and the ring blasts stay off his feet
		local off = flat(g - hrp.Position)
		local minFlat = num(c.MinFlat, 22)
		if off.Magnitude < minFlat then
			local dir = S.flatDir(off, look)
			local pt = hrp.Position + dir * minFlat
			g = call("groundAt", pt + UP * 4, 80) or (pt - UP * 3)
		end
		local T = {
			leap = num(c.LeapAt, 0), rise = num(c.RiseAt, 0.15), form = num(c.FormAt, 0.55), drop = num(c.DropAt, 0.95),
			impact = num(c.ImpactAt, 1.45),
		}
		local id = S.commit(p, "Bajrang", t, num(c.Lock, 1.9), char)
		local me = mine(st)
		me.gen += 1
		local gen = me.gen
		me.bajrang = id
		S.fire("BajrangCast", {
			id = id, userId = p.UserId, t0 = t, from = hrp.Position, target = g, height = num(c.Height, 170),
			fistSize = num(c.FistSize, 46), leapAt = T.leap, riseAt = T.rise, formAt = T.form, dropAt = T.drop,
			impactAt = T.impact,
		})
		local function ok()
			return me.gen == gen and S.valid(p, char)
		end

		S.at(t, T.form, function()
			if not ok() then
				cancelBajrang(p, me, id)
				return
			end
			-- (integration) the crowd Threat moved to the impact so the drop zone is not emptied before the fist lands
		end)

		S.at(t, T.impact, function()
			if not ok() then
				cancelBajrang(p, me, id)
				return
			end
			me.bajrang = nil
			local R = num(c.Radius, 46)
			local rows = radial(p, char, g + UP * 2, R, c, g + UP * 6)
			call("hook", "Threat", g, num(c.ThreatRadius, 80), num(c.ThreatTime, 2.5))
			blast(p, g, num(c.BlastRadius, 48), {
				dir = -UP, speed = num(c.BreakSpeed, 260),
				crater = { r = num(c.CraterRadius, 16), rocks = num(c.CraterRocks, 30), speed = num(c.CraterSpeed, 150) },
			})
			local avoid = { pos = hrp.Parent and hrp.Position or g, r = num(c.AvoidRadius, 14) }
			local rc = type(c.RingCraters) == "table" and c.RingCraters or { r = 30, n = 8, size = 6, rocks = 4, speed = 90, delay = 0.08 }
			ringCraters(g, rc, avoid)
			local rb = type(c.RingBlasts) == "table" and c.RingBlasts or { r = 32, n = 6, radius = 22 }
			ringBlasts(p, g, rb, num(c.BreakSpeed, 260) * 0.6, avoid)
			S.fire("BajrangImpact", { id = id, userId = p.UserId, pos = g, radius = R })
			log("Bajrang impact: %d bodies", #rows)
		end)
	end

	---------------------------------------------------------------------------------------------------
	function M.Gear5(p, st, payload)
		st = st or S.state(p)
		local char = S.liveChar(p)
		if char and S.inMode(p, char) then
			return bajrang(p, st, payload)
		end
		return awaken(p, st, payload)
	end

	-- died / unequip / left: pending beats see the new gen and stand down; a Bajrang in flight is cancelled now
	function M.__reset(p, st, why)
		st = st or S.state(p)
		local me = mine(st)
		if me.bajrang then
			cancelBajrang(p, me, me.bajrang)
		end
		me.gen += 1
	end

	return M
end
