--!nocheck
-- (2026-11-10) S.targets() sets no aim, so a giant form's stand-in (S.torsoOf -> PvP.formRoot) is re-aimed at the line
local FORM_AIM = require(game:GetService("ServerScriptService"):WaitForChild("PvP")).aimSeg
-- ZangetsuServer.Moves.Getsuga (owner: getsuga): Q, GETSUGA TENSHO (DESIGN.md section 6.2, CONTRACT.md 4.3 / 5).
-- require(this)(S) -> { Getsuga = handler, __reset = reset }. S is the Core's server API (CONTRACT 4.2).
-- FLAIR pass: Windup 0.62 -> 0.80 (the blade is drawn up overhead into a sky-high reiatsu flare before the cut), Lock
-- 1.42 -> 1.95 (the held money pose, the chiburi flick and the twirl back onto the shoulder), the Threat lasts the whole
-- windup, and an OPEN-AIR end now detonates too (a crater + WorldBlast under the end point when the ground is near).
-- The cast: he raises Zangetsu (Windup 0.80 s, rooted by the client), then one diagonal cut hurls a crescent along the
-- FLAT camera aim from origin = hrp + UP*Height + flat*StartAhead at Speed, to the first wall (S.clampPath) or Range.
-- Broadcasts (every client; times are seconds after t0):
--   GetsugaCast   { id, userId, t0, origin, dir, stop, wall, speed, width, tilt, windup, stations = { { pos, t, s } },
--                   mode, range, halfWidth }   (range / halfWidth are additions)
--   GetsugaHit    { id, userId, model, pos, dir, mode }       one per body the wave passes through
--   GetsugaEnd    { id, userId, pos, wall, mode }             the wave arrives (pos = origin + dir*stop)
--   GetsugaCancel { id, userId }                              the caster died / unequipped before the wave arrived
-- Hits: one server timeline from t. At Windup the corridor is swept (every tagged body with its torso along the line in
-- [-1.5, stop + 2], within HalfWidth sideways and HalfHeight vertically, with a clear line from the wave): those are the
-- candidates. Then every frame the wave front s = (e - Windup) * Speed advances; a body is struck when the front
-- reaches its CURRENT torso, if it is still inside the corridor, or (a candidate) within EscapeMargin of it. Bodies
-- that step into the corridor ahead of the front are struck too; bodies it has already passed are not. Each body once.
-- Stations (ground points every StationEvery studs where the ground lies within GroundSkim + 3 below the wave) crater
-- as the wave passes them; a wall end craters the wall. Dead bodies fly without damage, held bodies take damage and are
-- never moved (S.strike). The caster is re-checked (S.valid) every frame from Windup: invalid -> GetsugaCancel +
-- S.release.
return function(S)
	local M = {}
	local UP = S.UP or Vector3.yAxis

	local function num(v, d)
		return type(v) == "number" and v == v and v or d
	end

	local function cancel(p, cast)
		if cast.dead then
			return
		end
		cast.dead = true
		pcall(S.fire, "GetsugaCancel", { id = cast.id, userId = cast.userId })
		pcall(S.release, p, cast.id)
	end

	function M.Getsuga(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Getsuga")
		if not char then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local mode = S.inMode(p, char) == true
		local G = S.cfgFor(p, char, "Getsuga") or {}
		local W = num(G.Windup, 0.62)
		local speed = math.max(num(G.Speed, 160), 1)
		local range = math.max(num(G.Range, 110), 0)
		local half = num(G.HalfWidth, 7)
		local halfH = num(G.HalfHeight, 9)
		local margin = num(G.EscapeMargin, 10)

		-- the flat aim (camera look), falling back to where he faces
		local look = S.flatDir(hrp.CFrame.LookVector, Vector3.new(0, 0, -1))
		local aim = payload.aim
		if typeof(aim) ~= "Vector3" or not S.finite(aim) or aim.Magnitude < 1e-3 then
			aim = look
		end
		local flat = S.flatDir(aim, look)

		-- the wave's start, kept on this side of a wall he is standing against
		local base = hrp.Position + UP * num(G.Height, 0.5)
		local ahead = num(G.StartAhead, 2.5)
		local clear0 = S.clampPath(base, flat, ahead + 2) or (ahead + 2)
		if clear0 < ahead then
			ahead = math.max(clear0, 0)
		end
		local origin = base + flat * ahead
		local stop = math.clamp(S.clampPath(origin, flat, range) or range, 0, range)
		local wall = stop < range - 0.01

		-- the trench stations: ground points under the wave's path
		local stations = {}
		local every = math.max(num(G.StationEvery, 14), 2)
		local skim = num(G.GroundSkim, 6) + 3
		local s = every
		while s <= stop do
			local g = S.groundAt(origin + flat * s, 14)
			if typeof(g) == "Vector3" and origin.Y - g.Y < skim then
				table.insert(stations, { pos = g, t = W + s / speed, s = s })
			end
			s += every
		end

		local id = S.commit(p, "Getsuga", t, num(G.Lock, 1.95), char)
		local uid = p.UserId
		local cast = { id = id, userId = uid, dead = false }
		st.Getsuga = st.Getsuga or {}
		st.Getsuga.cast = cast

		S.fire("GetsugaCast", {
			id = id, userId = uid, t0 = t, origin = origin, dir = flat, stop = stop, wall = wall, speed = speed,
			width = num(G.Width, 16), tilt = num(G.Tilt, -30), windup = W, stations = stations, mode = mode,
			range = range, halfWidth = half,
		})
		S.hook("Threat", origin + flat * math.min(40, math.max(stop, 10)), 30, W + 0.6)

		local damage = num(G.Damage, 40)
		local vel = flat * num(G.Knock, 130) + UP * num(G.Up, 45)
		local rag = num(G.RagTime, 3)
		local hitO = { hitStop = num(G.HitStop, 0.06), spin = flat:Cross(UP) * 14 }
		local craterR = num(G.CraterRadius, 3.2)
		local craterN = num(G.CraterRocks, 3)
		local craterV = num(G.CraterSpeed, 45)
		local wallR = num(G.WallRadius, 6)

		local hit = { [char] = true }
		local cand = nil
		local nextStation = 1
		local prevFront = -1.5

		-- where a body's torso sits relative to the line: along, sideways, vertical
		local function measure(tp)
			local rel = tp.Position - origin
			local along = rel:Dot(flat)
			local side = rel - flat * along
			return along, Vector3.new(side.X, 0, side.Z).Magnitude, math.abs(rel.Y)
		end

		local function strike(m, tp)
			hit[m] = true
			S.strike(p, m, vel, damage, rag, hitO)
			S.fire("GetsugaHit", { id = id, userId = uid, model = m, pos = tp.Position, dir = flat, mode = mode })
		end

		S.timeline("Getsuga", t, function(e)
			if cast.dead then
				return true
			end
			if e < W then
				return false
			end
			if not S.valid(p, char) then
				cancel(p, cast)
				return true
			end
			local front = math.min((e - W) * speed, stop)
			local arrived = front >= stop - 1e-3

			-- the release: sweep the corridor once
			if not cand then
				cand = {}
				S.refreshIgnore()
				for _, m in ipairs(S.targets()) do
					if not hit[m] then
						FORM_AIM(m, origin, origin + flat * stop) -- (2026-11-10) a giant form: its body point nearest the wave's line
						local tp = S.torsoOf(m)
						if tp then
							local along, side, dy = measure(tp)
							if along >= -1.5 and along <= stop + 2 and side <= half and dy <= halfH
								and S.clearLine(origin + flat * math.clamp(along, 0, stop), tp.Position) then
								cand[m] = true
							end
						end
					end
				end
			end

			-- craters under the wave
			while stations[nextStation] and stations[nextStation].t <= e do
				local stn = stations[nextStation]
				nextStation += 1
				S.ground("impact", stn.pos, craterR, craterN, craterV)
				S.pushLoose(stn.pos, 10, 120, 0.35)
				S.hook("WorldBlast", stn.pos, craterR + 3, uid)
			end

			-- bodies the front has reached this frame
			local reach = front + (arrived and 2 or 1.5)
			for _, m in ipairs(S.targets()) do
				if not hit[m] then
					FORM_AIM(m, origin, origin + flat * stop)
					local tp = S.torsoOf(m)
					if tp then
						local along, side, dy = measure(tp)
						if along <= reach and along <= stop + 2 then
							if cand[m] then
								if along >= -4 and side <= half + margin and dy <= halfH + margin then
									strike(m, tp)
								end
							elseif along >= math.max(prevFront - 4, -1.5) and side <= half and dy <= halfH
								and S.clearLine(origin + flat * math.clamp(along, 0, stop), tp.Position) then
								strike(m, tp)
							end
						end
					end
				end
			end
			prevFront = front

			if arrived then
				local endPos = origin + flat * stop
				if wall then
					local wp = origin + flat * (stop + 1.5)
					S.ground("impact", wp, wallR, 6, 55)
					S.hook("WorldBlast", wp, 8, uid)
					S.hook("BreakBlast", wp, wallR, flat, num(G.Knock, 130), uid)
					S.pushLoose(wp, 12, 90, 0.3)
				else
					-- the open-air end detonates: a crater under the end point when the ground is near (no damage)
					local g = S.groundAt(endPos, 14)
					if typeof(g) == "Vector3" and endPos.Y - g.Y < skim then
						local r = num(G.EndRadius, 5)
						S.ground("impact", g, r, num(G.EndRocks, 5), num(G.EndSpeed, 50))
						S.hook("WorldBlast", g, r + 3, uid)
						S.pushLoose(g, 12, 90, 0.3)
					end
				end
				cast.dead = true
				S.fire("GetsugaEnd", { id = id, userId = uid, pos = endPos, wall = wall, mode = mode })
				return true
			end
			return false
		end, function()
			cancel(p, cast)
		end)
	end

	-- died / respawn / unequip / left: a wave still in flight is called off
	function M.__reset(p, st, why)
		local g = type(st) == "table" and st.Getsuga
		if type(g) == "table" and type(g.cast) == "table" then
			cancel(p, g.cast)
			g.cast = nil
		end
	end

	return M
end
