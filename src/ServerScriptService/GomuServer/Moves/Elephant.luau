--!nocheck
-- GomuServer.Moves.Elephant (owner: elephant): R, GEAR THIRD - GUM-GUM ELEPHANT GUN (CONTRACT.md 8.4 / 4.2 / 5.5).
-- require(this)(S) -> { Elephant = handler, __reset = reset }. S is GomuServer.Core's API (CONTRACT 5.2).
-- The cast (times after t0, Config.Elephant via S.cfgFor so Gear Fifth's Mode.Elephant and DamageMul apply):
--   0 .. PunchAt   the bite, the arm inflates into a giant haki fist held up behind him (client only; we just watch
--                  that the caster stays valid - a death / unequip fires ElephantCancel + S.release)
--   PunchAt .. HitAt  the fist flies the shoulder -> endPos line: S.blast every PathBlastEvery studs as the fist
--                  passes (PathBlastRadius 8 >= 6: glass + small Structure holes along the path)
--   HitAt          every body in the Width corridor (no LOS: it plows) and within EndHitRadius of the end point:
--                  S.strike(fling along the aim - flat when the aim points down - + UP*Up, Damage, RagTime, hitStop)
--                  + ElephantHit; then S.blast(end, EndBlastRadius, BreakBlast along the aim, a crater when the end
--                  is near the ground and not under the caster) + S.pushLoose + ElephantImpact.
-- Broadcasts: ElephantCast / ElephantHit / ElephantImpact / ElephantCancel, fields exactly CONTRACT 4.2.
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
		if cast.conn then
			pcall(function()
				cast.conn:Disconnect()
			end)
		end
		pcall(S.fire, "ElephantCancel", { id = cast.id, userId = cast.userId })
		pcall(S.release, p, cast.id)
	end

	function M.Elephant(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Elephant")
		if not char then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local mode = S.inMode(p, char) == true
		local c = S.cfgFor(p, char, "Elephant") or {}

		local range = math.max(num(c.Range, 60), 4)
		local pitch = num(c.AimPitch, 20)
		local origin = S.limbRoot(char, "R")
		if typeof(origin) ~= "Vector3" or not S.finite(origin) then
			origin = hrp.Position + UP * 1.5
		end
		-- (2026-11-08) "luffy elephant gun aim": the fist flew along the camera's LookVector, which in third person points
		-- down at the character (-15..-25 deg), so it drove into the street a dozen studs out and ignored the cursor. Now
		-- it follows the point under the cursor (payload.target): a living body within 8 studs of it is punched straight
		-- at (torso height); a wall / rooftop above the shoulder is aimed at directly; the ground you point at sets the
		-- direction but the fist flies LEVEL toward it, never into the street. No cursor point: level along the camera's
		-- heading. The pitch clamp (AimPitch) still applies.
		local aimPayload = { aim = payload.aim }
		local tgt = payload.target
		if S.finite(tgt) then
			local near = S.inRadius(tgt, 8, { alive = true, exclude = { [char] = true } }) or {}
			local body = near[1] and S.finite(near[1].tp) and near[1].tp or nil
			local d = (body or tgt) - origin
			if not body and d.Y < 0 then
				d = Vector3.new(d.X, 0, d.Z)
			end
			if d.Magnitude > 3 then
				aimPayload = { aim = d.Unit }
			elseif S.finite(payload.aim) then -- pointing at his own feet: level along the camera's heading
				aimPayload = { aim = Vector3.new(payload.aim.X, 0, payload.aim.Z) }
			end
		elseif S.finite(payload.aim) and payload.aim.Y < 0 then
			aimPayload = { aim = Vector3.new(payload.aim.X, 0, payload.aim.Z) }
		end
		local aim, flat = S.aimOf(aimPayload, hrp, -pitch, pitch)
		local len = math.clamp(num(S.clampPath(origin, aim, range), range), 0, range)
		local wall = len < range - 0.5
		local endPos = origin + aim * len
		-- the blast sits ON the surface the fist met (clampPath stops 2 short of it)
		local blastPos = wall and (origin + aim * (len + 1.5)) or endPos

		local punchAt = num(c.PunchAt, 0.95)
		local travel = math.max(num(c.Travel, 0.24), 0.05)
		local hitAt = num(c.HitAt, punchAt + travel)
		local uid = p.UserId

		local id = S.commit(p, "Elephant", t, num(c.Lock, 1.9), char)
		st.Elephant = st.Elephant or { gen = 0 }
		local E = st.Elephant
		E.gen = (E.gen or 0) + 1
		local gen = E.gen
		local cast = { id = id, userId = uid, dead = false }
		E.cast = cast

		S.fire("ElephantCast", {
			id = id, userId = uid, t0 = t, side = "R", dir = flat, aim = aim, reach = len, endPos = endPos, wall = wall,
			inflateAt = num(c.InflateAt, 0.08), punchAt = punchAt, hitAt = hitAt, hold = num(c.Hold, 0.25),
			back = num(c.Back, 0.4), deflateAt = num(c.DeflateAt, 1.75), fistScale = num(c.FistScale, 7),
			armScale = num(c.ArmScale, 3.2), haki = c.Haki ~= false, mode = mode,
		})
		-- (integration) the crowd Threat fires at the impact, not here: a cast-time Threat sent the NPCs in the corridor
		-- running for 1.2 s and the fist whiffed

		-- path stations: blasts as the fist passes (the end blast covers the last stretch)
		local stations = {}
		local every = math.max(num(c.PathBlastEvery, 12), 3)
		local s = every
		while s < len - every * 0.5 do
			table.insert(stations, { pos = origin + aim * s, t = punchAt + travel * (s / math.max(len, 1)) })
			s += every
		end
		local pathR = num(c.PathBlastRadius, 8)
		local nextStation = 1

		local function resolve()
			local width = num(c.Width, 7)
			local dirF = aim.Y < 0 and flat or aim -- a downward punch throws bodies along the street, not into it
			local vel = dirF * num(c.Fling, 185) + UP * num(c.Up, 50)
			local damage = num(c.Damage, 46)
			local rag = num(c.RagTime, 3.2)
			local hitO = { hitStop = num(c.HitStop, 0.1), spin = flat:Cross(UP) * 18 }
			local done = { [char] = true }
			local function take(rows)
				for _, row in ipairs(rows or {}) do
					local m = row.m
					if m and not done[m] then
						done[m] = true
						local tp = typeof(row.tp) == "Vector3" and row.tp or endPos
						local ok, err = pcall(S.strike, p, m, vel, damage, rag, hitO)
						if not ok then
							S.warn("Elephant.strike", err, 5)
						end
						S.fire("ElephantHit", { id = id, userId = uid, model = m, pos = tp })
					end
				end
			end
			local ex = { [char] = true }
			take(S.nearSegment(origin, endPos, width, { exclude = ex }))
			take(S.inRadius(endPos, num(c.EndHitRadius, width + 2), { exclude = ex }))

			-- the end: a big building hole / a street crater (never under his own feet)
			local radius = num(c.EndBlastRadius, 20)
			local o = { dir = aim, speed = num(c.EndBreakSpeed, 230) }
			local g = S.groundAt(blastPos, 14)
			if typeof(g) == "Vector3" and blastPos.Y - g.Y < num(c.GroundSkim, 9) then
				local off = (g - hrp.Position) * Vector3.new(1, 0, 1)
				if off.Magnitude >= num(c.CasterClear, 7) then
					o.crater = { r = num(c.CraterRadius, 9), rocks = num(c.CraterRocks, 14), speed = num(c.CraterSpeed, 90) }
				end
			end
			local ok, err = pcall(S.blast, p, blastPos, radius, o)
			if not ok then
				S.warn("Elephant.blast", err, 5)
			end
			pcall(S.pushLoose, blastPos, radius + 6, 150, 0.35)
			pcall(S.hook, "Threat", blastPos, num(c.ThreatRadius, 30), num(c.ThreatTime, 1.5))
			S.fire("ElephantImpact", { id = id, userId = uid, pos = blastPos, dir = aim, wall = wall, radius = radius })
		end

		cast.conn = S.timeline("Elephant", t, function(e)
			if cast.dead then
				return true
			end
			if E.gen ~= gen or not S.valid(p, char) then
				cancel(p, cast)
				return true
			end
			if e < punchAt then
				return false
			end
			while stations[nextStation] and stations[nextStation].t <= e do
				local stn = stations[nextStation]
				nextStation += 1
				local ok, err = pcall(S.blast, p, stn.pos, pathR, { dir = aim, speed = 120 })
				if not ok then
					S.warn("Elephant.path", err, 5)
				end
			end
			if e >= hitAt then
				cast.dead = true
				resolve()
				return true
			end
			return false
		end, function()
			cancel(p, cast)
		end)
	end

	-- died / respawn / unequip / left: a fist still winding up or in flight is called off
	function M.__reset(p, st, why)
		local E = type(st) == "table" and st.Elephant
		if type(E) == "table" then
			E.gen = (E.gen or 0) + 1
			if type(E.cast) == "table" then
				cancel(p, E.cast)
				E.cast = nil
			end
		end
	end

	return M
end
