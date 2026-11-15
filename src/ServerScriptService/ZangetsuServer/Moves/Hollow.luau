--!nocheck
-- ZangetsuServer.Moves.Hollow (owner: hollow): R, HOLLOW MASK (DESIGN 8.2). Called by Core with the server API S.
--   0.00  commit (Lock covers the landing clip + chiburi), the victim marked SlashedBy = caster's userId and frozen in
--         terror (StunnedUntil to FinisherAt + StunVictim), HollowCast broadcast
--   0.95  ROAR (RoarAt): everyone within RoarRadius but the victim is blown back (8 dmg), Threat + loose props shoved,
--         pebbles hop off the ground round him (GroundFX ring)
--   RoarAt -> FinisherAt  the victim is reeled to the hover point H (dropped if it escapes Escape studs or gets held)
--   BlitzAt + i*SlashEvery  a cut on the victim (6 / 8 slashes), HollowSlash per landed cut
--   FinisherAt  the point-blank Getsuga (after a WindUp charge at F): the victim flung (hit-stop 0.16), the wave runs on
--               (wall-clamped) and hits every body near its line, a crater + rocks under H, WorldBlast; SlashedBy cleared
-- Every mid-air spot (H, the slash ring, the finisher spot F) is clamped against walls, ceilings and the ground here,
-- so the clients only ever play positions the server checked. The victim is released on every exit path: the finisher,
-- a cancel (caster dead / unequipped / kit changed), __reset, a timeline error, an escape.
-- Broadcast: HollowCast { id, userId, t0, origin, aim, target, hover, roarAt, blitzAt, slashes = { { t, pos, face, tilt } },
--   finisherAt, finisherPos, crackAt, shatterAt, mode, + lock, landAt, hitStop, waveRange, slashEvery, windup },
--   HollowRoar { id, userId, pos, models }, HollowSlash { id, userId, i, model, pos },
--   HollowFinisher { id, userId, pos, dir, model, others, + range }, HollowCancel { id, userId }
return function(S)
	local M = {}
	local UP, FLAT = S.UP or Vector3.yAxis, S.FLAT or Vector3.new(1, 0, 1)
	local GOLDEN = math.rad(137.5)
	local TILTS = { -35, 40, -70, 10, 60, -20, 30, -50 }

	local function num(v, d)
		return type(v) == "number" and v or d
	end

	-- the victim stops being ours (only if WE marked it)
	local function unmark(m, uid)
		if typeof(m) == "Instance" and m.Parent and m:GetAttribute("SlashedBy") == uid then
			m:SetAttribute("SlashedBy", nil)
		end
	end

	local function stopCast(p, c, fireCancel)
		if not c or c.over then
			return
		end
		c.over = true
		unmark(c.target, p.UserId)
		c.held = false
		if fireCancel then
			S.fire("HollowCancel", { id = c.id, userId = p.UserId })
			S.release(p, c.id)
		end
	end

	-- the point a body should hover at: a standing torso's height over the ground under it, + HoverUp (ceiling-clamped)
	local function hoverOf(tpPos, hoverUp)
		local g = S.groundAt(tpPos, 40)
		local base = Vector3.new(tpPos.X, g and (g.Y + 3) or tpPos.Y, tpPos.Z)
		local up = S.clampPath(base, UP, hoverUp + 3) -- distance to a ceiling minus 2 (or the full ask)
		return base + UP * math.clamp(up - 1, 0, hoverUp)
	end

	-- a root position for the caster near `pos`: never under the ground, never through the floor
	local function airRoot(hrp, pos)
		local st = S.standAt(hrp, pos)
		if typeof(st) == "Vector3" and S.finite(st) and st.Y > pos.Y and st.Y - pos.Y < 12 then
			return Vector3.new(pos.X, st.Y, pos.Z)
		end
		return pos
	end

	-- one spot on the slash ring round H, pulled in by walls (the far side is tried when the near one is blocked)
	local function ringSpot(hrp, Hp, a, ring, dy)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = S.clampPath(Hp, dir, ring)
		if r < 2 then
			local r2 = S.clampPath(Hp, -dir, ring)
			if r2 > r then
				dir, r = -dir, r2
			end
		end
		r = math.max(r, 0.5)
		local up = dy
		if dy > 0 then
			up = math.min(dy, math.max(S.clampPath(Hp, UP, dy + 2.5) - 0.5, 0))
		end
		local pos = airRoot(hrp, Hp + dir * r + UP * up)
		return pos, S.flatDir(Hp - pos, -dir)
	end

	function M.Hollow(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Hollow")
		if not char then
			return
		end
		local C = S.cfgFor(p, char, "Hollow")
		local mode = S.inMode(p, char)
		local uid = p.UserId
		local _, flat = S.aimOf(payload or {}, hrp, -30, 30)
		local origin = hrp.Position
		local chest = origin + UP * 1.5

		-- the victim: nearest living body in reach (LOS), scored by distance + 0.15 * angle off the aim
		local best, bestScore
		for _, h in ipairs(S.inRadius(origin, num(C.Range, 45), { alive = true, los = chest, skipHeld = true, maxDY = num(C.MaxDY, 18) })) do
			local m = h.m
			local by = m:GetAttribute("SlashedBy")
			if (by == nil or by == uid) and not S.held(m) then
				local ang = S.angleTo((h.tp - origin) * FLAT, flat)
				local score = h.d + ang * 0.15
				if not bestScore or score < bestScore then
					best, bestScore = h, score
				end
			end
		end
		local target = best and best.m or nil
		local hoverUp = num(C.HoverUp, 4.5)
		local Hp
		if target then
			Hp = hoverOf(best.tp, hoverUp)
		else
			-- no victim: the blitz cuts the air in front of him
			local ahead = S.clampPath(chest, flat, num(C.WhiffAhead, 9))
			local base = origin + flat * ahead
			local up = S.clampPath(base, UP, num(C.WhiffUp, 3) + 3)
			Hp = base + UP * math.clamp(up - 1, 0, num(C.WhiffUp, 3))
		end

		-- the slash ring (golden angle: every cut from a new side), then the finisher spot behind H
		local n = math.max(math.floor(num(C.Slashes, 6)), 1)
		local every = num(C.SlashEvery, 0.13)
		local blitzAt = num(C.BlitzAt, 1.05)
		local ring = num(C.SlashRing, 4.2)
		local a0 = math.atan2(-flat.Z, -flat.X)
		local slashes = {}
		for i = 1, n do
			local dy = ((i % 2 == 1) and 1.0 or -0.6) - 1.2
			local pos, face = ringSpot(hrp, Hp, a0 + i * GOLDEN, ring, dy)
			slashes[i] = { t = blitzAt + (i - 1) * every, pos = pos, face = face, tilt = TILTS[(i - 1) % #TILTS + 1] }
		end
		local back = math.max(S.clampPath(Hp, -flat, num(C.FinisherBack, 5.5)), 1.5)
		local F = airRoot(hrp, Hp - flat * back - UP * 1.2)
		local waveRange = math.max(S.clampPath(Hp, flat, num(C.FinisherRange, 40)), 0)

		local lock = num(C.Lock, 3.9)
		local id = S.commit(p, "Hollow", t, lock, char)
		local roarAt, finAt = num(C.RoarAt, 0.95), num(C.FinisherAt, 2.3)
		local hitStop = num(C.FinisherHitStop, 0.16)
		local shatterAt = num(C.ShatterAt, 3.19)
		local c = { id = id, t0 = t, target = target, held = target ~= nil, over = false, shatterAt = shatterAt }
		st.Hollow = c
		if target then
			target:SetAttribute("SlashedBy", uid)
			-- frozen in terror while the mask forms (the reel takes over at the roar; the AI waits out the finisher)
			if S.alive(target) then
				pcall(S.stun, target, finAt + num(C.StunVictim, 0.5))
			end
		end
		S.fire("HollowCast", {
			id = id, userId = uid, t0 = t, origin = origin, aim = flat, target = target, hover = Hp,
			roarAt = roarAt, blitzAt = blitzAt, slashes = slashes, finisherAt = finAt, finisherPos = F,
			crackAt = num(C.CrackAt, 2.74), shatterAt = shatterAt, mode = mode,
			lock = lock, landAt = num(C.LandAt, shatterAt - 0.55), hitStop = hitStop, waveRange = waveRange,
			slashEvery = every, windup = num(C.WindUp, 0.3),
		})

		local rag = num(C.RagTime, 3.5)
		local function valid()
			return st.Hollow == c and not c.over and S.valid(p, char)
		end

		local function roar()
			local models = {}
			for _, h in ipairs(S.inRadius(origin, num(C.RoarRadius, 18), { los = chest })) do
				local m = h.m
				if m ~= target then
					local out = S.flatDir(h.tp - origin, S.randomFlat())
					S.strike(p, m, out * num(C.RoarPush, 75) + UP * num(C.RoarUp, 25), num(C.RoarDamage, 8), rag * 0.6)
					table.insert(models, m)
				end
			end
			S.hook("Threat", origin, 30, 1.5)
			S.pushLoose(origin, 18, 90, 0.3)
			if num(C.RoarRocks, 0) > 0 then
				S.ground("ring", origin, num(C.RoarRockRadius, 8), num(C.RoarRocks, 8), num(C.RoarRockUp, 30))
			end
			S.fire("HollowRoar", { id = id, userId = uid, pos = origin, models = models })
		end

		local function finisher()
			local others, hitTarget = {}, nil
			if target and c.held and target.Parent and not S.held(target) then
				hitTarget = target
				local spin = flat:Cross(UP) * 14
				S.strike(p, target, flat * num(C.FinisherFling, 210) + UP * num(C.FinisherUp, 55), num(C.FinisherDamage, 30), rag,
					{ hitStop = hitStop, spin = spin })
			end
			local exclude = {}
			if target then
				exclude[target] = true
			end
			local stop = Hp + flat * math.max(waveRange, 0.5)
			for _, h in ipairs(S.nearSegment(Hp, stop, num(C.FinisherWidth, 6), { los = Hp, exclude = exclude })) do
				S.strike(p, h.m, flat * num(C.WaveFling, 120) + UP * num(C.WaveUp, 30), num(C.WaveDamage, 18), rag)
				table.insert(others, h.m)
			end
			local g = S.groundAt(Hp, 40)
			if g and Hp.Y - g.Y < 14 then
				S.ground("impact", g, num(C.FinisherCrater, 4.4), num(C.FinisherRocks, 10), num(C.FinisherRockSpeed, 70))
			end
			S.hook("WorldBlast", Hp, 6, uid)
			unmark(target, uid)
			c.held = false
			S.fire("HollowFinisher", { id = id, userId = uid, pos = Hp, dir = flat, model = hitTarget, others = others, range = waveRange })
		end

		local roared, nextSlash, escapeAfter = false, 1, roarAt + 0.35
		S.timeline("Hollow", t, function(e)
			if st.Hollow ~= c or c.over then
				return true
			end
			if not valid() then
				stopCast(p, c, true)
				return true
			end
			if not roared and e >= roarAt then
				roared = true
				roar()
			end
			-- the hover: reel the victim to H until the finisher
			if c.held and e >= roarAt and e < finAt then
				local tp = target.Parent and S.torsoOf(target)
				local ok = tp ~= nil and not S.held(target) and S.reel(target, Hp, num(C.PullGain, 8), num(C.PullMax, 120), rag)
				if ok and e > escapeAfter and (tp.Position - Hp).Magnitude > num(C.Escape, 14) then
					ok = false
				end
				if not ok then
					unmark(target, uid)
					c.held = false
				end
			end
			while nextSlash <= #slashes and e >= slashes[nextSlash].t do
				local i = nextSlash
				nextSlash += 1
				if c.held and target.Parent then
					S.strike(p, target, nil, num(C.SlashDamage, 6), rag)
					local tp = S.torsoOf(target)
					S.fire("HollowSlash", { id = id, userId = uid, i = i, model = target, pos = tp and tp.Position or Hp })
				end
			end
			if e >= finAt then
				finisher()
				c.over = true
				return true
			end
			return false
		end, function()
			stopCast(p, c, true)
		end)
	end

	-- died / respawn / unequip / left: let the victim go and tell every client to break the mask now
	function M.__reset(p, st, why)
		local c = st and st.Hollow
		if not c then
			return
		end
		local live = not c.over
		local masked = S.now() < c.t0 + (c.shatterAt or 3.19) + 0.15
		if live then
			stopCast(p, c, true)
		elseif masked then
			S.fire("HollowCancel", { id = c.id, userId = p.UserId })
		end
		unmark(c.target, p.UserId)
		st.Hollow = nil
	end

	return M
end
