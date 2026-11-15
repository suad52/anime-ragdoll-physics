--!nocheck
-- ZangetsuServer.Moves.Bankai (owner bankai): G, BANKAI -> TENSA ZANGETSU (DESIGN.md §9.2, CONTRACT §4.3 / §5).
-- Authoritative timeline from t = the cast's server time (every number from Config.Bankai via S.cfgFor; FLAIR PASS
-- times, +17% so the tornado can build and the reveal can hold - damage, range and cooldown unchanged):
--   0.00 gate + commit (Lock 3.15 covers the whole performance, to the end of the reveal clip) -> BankaiCast to
--        everyone (the dummies' Threat moved to the eruption, 2026-11-08)
--   0.62 KAI (client only: the colours flip, the tornado turns black-red)
--   1.18 ERUPT: every body within Radius 30 of the ground under him (LOS from the ground) takes 35 -> 21 (FarMul 0.6)
--        and is flung 165 -> 100 along (radial + UP * 0.55), rag 3.5 (held bodies: damage + ragdoll, never moved);
--        GroundFX impact (r 9, 12 rocks, 70) + a ring of 8 craters at r 16 staggered 0.05 (counted from this beat);
--        pushLoose(40, 150, 0.5); WorldBlast(22) -> BankaiErupt { id, userId, pos, models }
--   1.42 FORM: S.setForm(char, "Bankai") (Tensa Zangetsu + the coat)
--   2.15 REVEAL (client only: the column dissolves, the dust-cloud reveal)
--   2.75 MODE: S.startMode(p, char, Mode.Time) - Core writes BankaiUntil; clients draw the mode from that attribute
-- The caster dying / unequipping / leaving mid-cast -> BankaiCancel { id, userId } + S.release; a cast cancelled after
-- FORM but before MODE puts the cleaver back (no mode ever starts on a Bankai blade it did not earn).
-- BankaiCast's added fields (read only by Client.Bankai): lock, modeTime, shotStart, revealShot.
return function(S)
	local M = {}
	local UP = S.UP or Vector3.yAxis
	local TAU = math.pi * 2
	local casts = {} -- [Player] = the running cast

	local function num(v, d)
		return type(v) == "number" and v or d
	end
	local function cfgOf(p, char)
		local ok, B = pcall(S.cfgFor, p, char, "Bankai")
		if ok and type(B) == "table" then
			return B
		end
		return S.CFG.Bankai or {}
	end

	local function finish(p, cast)
		cast.done = true
		if casts[p] == cast then
			casts[p] = nil
		end
	end
	local function cancel(p, cast, why)
		if cast.done then
			return
		end
		finish(p, cast)
		S.fire("BankaiCancel", { id = cast.id, userId = p.UserId, why = why })
		S.release(p, cast.id)
		if cast.formed and not cast.moded and cast.char.Parent then
			S.setForm(cast.char, "Shikai")
		end
	end

	-- 1.18: the pillar erupts
	local function erupt(p, cast)
		local B, g, uid = cast.B, cast.g, p.UserId
		local center = g + UP * 2
		local R = num(B.Radius, 30)
		local hits = S.inRadius(center, R, { los = g + UP * 2.5, exclude = { [cast.char] = true } }) or {}
		local models = {}
		for _, h in ipairs(hits) do
			local m, tp, d = h.m, h.tp, h.d or 0
			if m and m.Parent and m ~= cast.char then
				local k = math.clamp(d / math.max(R, 1), 0, 1)
				local dmg = num(B.Damage, 35) * (1 - k * (1 - num(B.FarMul, 0.6)))
				local speed = num(B.FlingNear, 165) + (num(B.FlingFar, 100) - num(B.FlingNear, 165)) * k
				local radial = S.flatDir((tp or g) - g, S.randomFlat())
				local vel = (radial + UP * num(B.Up, 0.55)).Unit * speed
				S.strike(p, m, vel, dmg, num(B.RagTime, 3.5), { spin = S.randomUnit() * 14 })
				table.insert(models, m)
			end
		end
		S.ground("impact", g, num(B.CraterRadius, 9), num(B.CraterRocks, 12), num(B.CraterSpeed, 70))
		local rc = type(B.RingCraters) == "table" and B.RingCraters or {}
		local n, r = num(rc.n, 8), num(rc.r, 16)
		local phase = math.random() * TAU
		for i = 1, n do
			local a = phase + (i - 1) / n * TAU
			-- staggered from THIS beat (never from the cast)
			task.delay((i - 1) * num(rc.delay, 0.05), function()
				local gp = S.groundAt(g + Vector3.new(math.cos(a), 0, math.sin(a)) * r + UP * 2, 20)
				if gp then
					S.ground("impact", gp, num(rc.size, 3), num(rc.rocks, 2), num(rc.speed, 50))
				end
			end)
		end
		S.pushLoose(g, 40, 150, 0.5, 1)
		-- (2026-11-08) the dummies flee from the eruption, not from the cast: warned at the cast they ran out of the
		-- radius during the 1.18 s wind-up and the ult hit nobody
		S.hook("Threat", g, num(B.ThreatRadius, 50), num(B.ThreatTime, 3.0))
		S.hook("WorldBlast", g, 22, uid)
		S.fire("BankaiErupt", { id = cast.id, userId = uid, pos = g, models = models })
		S.log("Bankai erupt: %d bodies", #models)
	end

	function M.Bankai(p, st, payload)
		local char, hum, hrp, t = S.gate(p, "Bankai")
		if not char then
			return
		end
		if S.inMode(p, char) then
			return -- already Tensa Zangetsu
		end
		local B = cfgOf(p, char)
		local MODE = S.CFG.Mode or {}
		local origin = hrp.Position
		local _, flat = S.aimOf(payload, hrp, -20, 20)
		flat = S.flatDir(flat or hrp.CFrame.LookVector, hrp.CFrame.LookVector)
		-- the floor straight under the root first (S.groundAt starts 6 studs up, which lands on the roof under a low
		-- ceiling); Core's floorBelow takes a position (CONTRACT §4.2 says p): pcall'd so either reading is safe
		local okF, fb = pcall(S.floorBelow, origin, 40)
		local g = (okF and typeof(fb) == "Vector3" and fb) or S.groundAt(origin, 40) or (origin - UP * 3.19)
		local lock = num(B.Lock, 3.15)
		local id = S.commit(p, "Bankai", t, lock, char)
		local T = {
			kai = num(B.KaiAt, 0.62), erupt = num(B.EruptAt, 1.18), form = num(B.FormAt, 1.42),
			reveal = num(B.RevealAt, 2.15), mode = num(B.ModeAt, 2.75),
		}
		local prev = casts[p]
		if prev then
			finish(p, prev)
		end
		local cast = { id = id, char = char, B = B, g = g, done = false }
		casts[p] = cast
		S.fire("BankaiCast", {
			id = id, userId = p.UserId, t0 = t, origin = origin, aim = flat, groundY = g.Y,
			kaiAt = T.kai, eruptAt = T.erupt, formAt = T.form, revealAt = T.reveal, modeAt = T.mode,
			shotEnd = num(B.ShotEnd, 1.32), radius = num(B.Radius, 30),
			pillarRadius = num(B.PillarRadius, 7), pillarHeight = num(B.PillarHeight, 120),
			lock = lock, modeTime = num(MODE.Time, 15), -- added fields (this kind's owner may add)
			shotStart = num(B.ShotStart, 0), revealShot = type(B.RevealShot) == "table" and B.RevealShot or nil,
		})
		S.timeline("Bankai", t, function(e)
			if cast.done then
				return true
			end
			if not S.valid(p, char) then
				cancel(p, cast, "invalid")
				return true
			end
			if not cast.erupted and e >= T.erupt then
				cast.erupted = true
				erupt(p, cast)
			end
			if not cast.formed and e >= T.form then
				cast.formed = true
				S.setForm(char, "Bankai")
			end
			if not cast.moded and e >= T.mode then
				cast.moded = true
				S.startMode(p, char, num(MODE.Time, 15))
				finish(p, cast)
				return true
			end
			return false
		end, function()
			cancel(p, cast, "error")
		end)
	end

	-- died / respawn / unequip / left: a cast still running is cancelled for every client
	function M.__reset(p, st, why)
		local cast = casts[p]
		if cast then
			cancel(p, cast, why or "reset")
		end
	end

	return M
end
