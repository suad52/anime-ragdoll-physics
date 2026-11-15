--!nocheck
-- GomuServer.Moves.Rocket (owner: rocket): E - Gum-Gum ROCKET (CONTRACT §8.3). Both arms shoot out and grab the cursor
-- point, the body is pulled back like a slingshot, then flies there and slams into whatever is there.
--   RocketCast   { id, userId, t0, from, anchor, to, normal?, wall, windup, tension, pullBack, travel, dir, mode,
--                  ground (added: the anchor is a floor) }
--   RocketHit    { id, userId, model, pos, path }
--   RocketSlam   { id, userId, pos, dir, radius, wall, normal? (added), ground (added) }
--   RocketCancel { id, userId, why = "missed" | "invalid" | "error" | "died" | "unequip" | "left" }
-- The CASTER's client flies the body (ctx.move); the server never moves him. It follows the replicated root from the
-- launch: bodies the root passes (and that lie on the planned line) take a sideways path hit as he goes by, and once
-- the root is within Tolerance of `to` (from the planned arrival up to ArriveGrace after it) the slam lands there.
-- Never there in time = RocketCancel "missed", no slam.
-- Destruction: S.blast at the anchor surface (a wall = a Structure hole; a floor = a street crater in FRONT of him),
-- BreakBlast along the flight; a GroundFX crater whose near edge sits CraterAhead in front of his feet (never under
-- them). The flight itself (150 studs/s) is swept by CityDestruction.Crash for free.
return function(S)
	local M = {}
	local RunService = game:GetService("RunService")
	local UP = S.UP or Vector3.yAxis
	local FLAT = S.FLAT or Vector3.new(1, 0, 1)
	local SKILL = "Rocket"

	local function num(c, k, d)
		local v = c[k]
		return type(v) == "number" and v or d
	end
	local function finite(v)
		if S.finite then
			return S.finite(v)
		end
		return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
	end
	local function flatOf(v, fb)
		local f = typeof(v) == "Vector3" and v * FLAT or Vector3.zero
		if f.Magnitude < 1e-3 then
			return fb
		end
		return f.Unit
	end
	local function closestOn(p, a, b)
		local ab = b - a
		local l2 = ab:Dot(ab)
		if l2 < 1e-6 then
			return a
		end
		return a + ab * math.clamp((p - a):Dot(ab) / l2, 0, 1)
	end
	local function posOf(row)
		local tp = row.tp
		if typeof(tp) == "Vector3" then
			return tp
		end
		if typeof(tp) == "Instance" and tp:IsA("BasePart") then
			return tp.Position
		end
		local t = row.m and S.torsoOf(row.m)
		return t and t.Position or nil
	end

	local function stateOf(st)
		st.Rocket = st.Rocket or { gen = 0 }
		return st.Rocket
	end
	local function stopConn(r)
		if r.conn then
			pcall(function()
				r.conn:Disconnect()
			end)
			r.conn = nil
		end
	end

	-- step() every Heartbeat until it returns true (Core's S.timeline: it warns a failing step, stops and calls onError)
	local function timeline(t0, step, onError)
		if type(S.timeline) == "function" then
			local ok, conn = pcall(S.timeline, "Rocket", t0, step, onError)
			if ok and conn then
				return conn
			end
		end
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local ok, done = pcall(step)
			if not ok then
				warn("[GomuServer.Rocket] timeline step failed: " .. tostring(done))
				pcall(onError)
			end
			if not ok or done then
				conn:Disconnect()
			end
		end)
		return conn
	end

	function M.Rocket(p, st, payload)
		local char, hum, hrp, t = S.gate(p, SKILL)
		if not char then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local c = S.cfgFor(p, char, SKILL)
		local mode = S.inMode(p, char) and true or false
		local uid = p.UserId
		local from = hrp.Position
		local chest = from + UP * 1.2
		local look = flatOf(payload.aim, flatOf(hrp.CFrame.LookVector, Vector3.new(0, 0, -1)))

		-- 1. the anchor: the cursor point (range-clamped, pushed out to MinRange, snapped onto the first surface)
		local anchor, normal, onSurface = S.cursorPoint(payload, chest, c.Range, c.MinRange)
		if not finite(anchor) then
			anchor, normal, onSurface = chest + look * c.Range, nil, false
		end
		if not finite(normal) then
			normal = nil
		end
		local off = anchor - chest
		if off.Magnitude < 1 then
			anchor, normal, onSurface = chest + look * math.max(c.MinRange, 2), nil, false
			off = anchor - chest
		end
		local aimDir = off.Unit
		local wall = (onSurface and normal and math.abs(normal.Y) < 0.6) and true or false
		local ground = (onSurface and normal and normal.Y >= 0.6) and true or false

		-- 2. the arrival: ArriveBack short of the anchor (out from a wall along its normal; standing on a floor)
		local own = S.floorBelow(from + UP * 0.5, 30)
		local hip = own and math.max(from.Y - own.Y, 1.5) or 3
		local to
		if wall then
			to = anchor + normal * c.ArriveBack
		elseif ground then
			to = S.standAt(hrp, anchor - aimDir * c.ArriveBack)
		else
			to = anchor - aimDir * c.ArriveBack
		end
		if not ground then
			-- never arrive with the root under a floor
			local g = S.floorBelow(to + UP * hip, hip * 2)
			if g and to.Y < g.Y + hip then
				to = Vector3.new(to.X, g.Y + hip, to.Z)
			end
		end
		local path = to - from
		local dist = path.Magnitude
		local dir = dist > 0.5 and path.Unit or aimDir
		local flatD = flatOf(dir, look)
		local travel = math.clamp(dist / math.max(c.Speed, 1), c.MinTravel, c.MaxTravel)
		local W, T = c.Windup, c.Tension
		local launchAt = W + T
		local arrive = launchAt + travel

		-- 3. commit + broadcast
		local id = S.commit(p, SKILL, t, c.Lock, char)
		S.extendBusy(p, id, t + arrive + 0.35)
		local r = stateOf(st)
		r.gen += 1
		stopConn(r)
		local gen = r.gen
		r.id, r.live = id, true
		S.fire("RocketCast", {
			id = id, userId = uid, t0 = t, from = from, anchor = anchor, to = to, normal = normal, wall = wall,
			windup = W, tension = T, pullBack = c.PullBack, travel = travel, dir = dir, mode = mode, ground = ground,
		})
		-- (integration) the crowd Threat fires at the slam (see slam()), so the bodies at the anchor are still there
		S.log("Rocket #%d %s %.1f studs in %.2fs (%s)", id, p.Name, dist, travel, wall and "wall" or (ground and "floor" or "air"))

		local hit = { [char] = true }
		local keepOut = c.SlamRadius * num(c, "PathKeepOut", 0.6)
		local corridor = c.PathRadius + num(c, "PathCorridor", 4)
		local grace = num(c, "ArriveGrace", 0.35)
		local prev

		local function cancel(why)
			if r.gen ~= gen or not r.live then
				return
			end
			r.live = false
			S.fire("RocketCancel", { id = id, userId = uid, why = why })
			S.release(p, id)
		end

		-- the sideways path hit on a body he flies past
		local function pathHits(a, b)
			if (b - a).Magnitude < 0.05 then
				return
			end
			local rows = S.nearSegment(a, b, c.PathRadius, { exclude = hit }) or {}
			for _, row in ipairs(rows) do
				local m = row.m
				local tp = m and not hit[m] and posOf(row)
				if tp and (tp - to).Magnitude > keepOut and (tp - closestOn(tp, from, to)).Magnitude <= corridor then
					hit[m] = true
					local away = (tp - closestOn(tp, a, b)) * FLAT
					local side = away.Magnitude > 0.2 and away.Unit
						or flatD:Cross(UP).Unit * (math.random() < 0.5 and -1 or 1)
					local vel = side * c.PathFling + flatD * (c.PathFling * 0.35) + UP * c.PathUp
					local landed = S.strike(p, m, vel, c.PathDamage, c.RagTime, {
						hitStop = c.HitStop * 0.5, spin = S.randomUnit() * 10,
					})
					if landed ~= false then
						S.fire("RocketHit", { id = id, userId = uid, model = m, pos = tp, path = true })
					end
				end
			end
		end

		-- the slam where he actually arrived
		local function slam(pos)
			r.live = false
			local centre = pos + dir * 2
			pcall(S.hook, "Threat", centre, c.SlamRadius + num(c, "ThreatPad", 6), 1.5)
			local rows = S.radial(p, centre, c.SlamRadius, {
				damage = c.SlamDamage, farMul = num(c, "SlamFarMul", 0.6),
				flingNear = c.SlamFling, flingFar = c.SlamFling * num(c, "SlamFarFling", 0.55),
				up = c.SlamUp / math.max(c.SlamFling, 1), rag = c.RagTime, hitStop = c.HitStop,
				exclude = hit, los = true,
			}) or {}
			for _, row in ipairs(rows) do
				local tp = posOf(row)
				if row.m and tp and row.landed ~= false then
					S.fire("RocketHit", { id = id, userId = uid, model = row.m, pos = tp, path = false })
				end
			end

			-- the city: a wall takes the hole at the anchor; a floor the street crater in front of his feet
			local feet = Vector3.new(pos.X, pos.Y - hip, pos.Z)
			local bpos, bdir
			if wall then
				bpos, bdir = anchor, -normal
			elseif ground then
				bpos = feet + flatD * math.max(c.ArriveBack, c.BlastRadius * 0.42 + 1.5)
				bdir = (flatD - UP * 0.35).Unit
			else
				bpos, bdir = pos + dir * 3, dir
			end
			S.blast(p, bpos, c.BlastRadius, { dir = bdir, speed = c.BreakSpeed })
			-- GroundFX crater (self-healing) + rocks, its near edge CraterAhead in front of him, only near the ground
			-- (never for a wall: the crater centre would land inside / behind the building)
			local g = not wall and S.groundAt(feet + flatD * (c.CraterRadius + num(c, "CraterAhead", 1.5)), 14)
			if g and pos.Y - g.Y < hip + 6 then
				S.ground("impact", g, c.CraterRadius, c.CraterRocks, c.CraterSpeed)
			end
			S.fire("RocketSlam", {
				id = id, userId = uid, pos = bpos, dir = dir, radius = c.SlamRadius, wall = wall, normal = normal,
				ground = ground,
			})
			S.log("Rocket #%d slam: %d bodies", id, #rows)
		end

		r.conn = timeline(t, function()
			if r.gen ~= gen or not r.live then
				return true
			end
			if not S.valid(p, char) then
				cancel("invalid")
				return true
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then
				cancel("invalid")
				return true
			end
			local e = S.now() - t
			if e < launchAt - 0.02 then
				return false
			end
			local pos = root.Position
			if prev then
				pathHits(prev, pos)
			end
			prev = pos
			if e >= arrive - 0.03 then
				if (pos - to).Magnitude <= c.Tolerance then
					slam(pos)
					return true
				elseif e > arrive + grace then
					cancel("missed")
					return true
				end
			end
			return false
		end, function()
			cancel("error")
		end)
	end

	-- died / respawn / unequip / left: the flight in progress never slams; every client drops its arms
	function M.__reset(p, st, why)
		local r = st and st.Rocket
		if not r then
			return
		end
		r.gen += 1
		stopConn(r)
		if r.live then
			r.live = false
			S.fire("RocketCancel", { id = r.id, userId = p.UserId, why = why })
		end
		if why == "left" then
			st.Rocket = nil
		end
	end

	return M
end
