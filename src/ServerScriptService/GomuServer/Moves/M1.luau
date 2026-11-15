--!nocheck
-- GomuServer.Moves.M1 (owner m1): the Gum-Gum string, authoritative (CONTRACT 8.1, 4.2).
--   swings 1-4: L jab, R jab, L jab, the Gum-Gum WHIP (a stretched right-leg sweep). The fist (foot) flies from the
--               shoulder (hip) rig attachment down the pitched aim, wall-clamped, homing onto the first body in the
--               corridor. It lands at HitAt: the FIRST body on the line + anything within ~2.5 of the fist. Standing
--               bodies are hurt + HitReact-thrown in place (S.react), corpses are juggled. (2026-11-08) a living body
--               that was flung and is still down (PvP.isDown) is passed over: no homing onto it, no hit.
--               (2026-11-10) lag compensation: the lock-on and the landing also test a PLAYER where the attacker saw
--               it (PvP.lagOffsets + PvP.MELEE_PAD, see LAG COMPENSATION below). NPC hits are exactly as before.
--   swing 5:    the finisher the client picked (whitelisted): PISTOL (default: a 26-stud straight right that
--               launches), RIFLE (Space held: a corkscrew uppercut that launches straight up), AXE (airborne: the
--               leg comes down like an axe - slams the body into the street and craters it). The first body takes
--               it full, the rest of the corridor half. The finisher BreakBlasts the fist end (walls dent).
--   Gear Fifth: S.cfgFor merges Mode.M1 (giant cartoon fists, longer reach, wider corridor, blast 6.5 = jabs dent walls)
-- Broadcasts: M1Swing { id, userId, t0, combo, limb, dir, aim, reach, hitAt, target, finisher, mode }
--             M1Hit { id, userId, combo, model, pos, dir, final, finisher, mode }
--             M1Cancel { id, userId }
-- st.M1 = { combo, last, lockUntil, gen } (gen bumps on __reset so a pending swing never lands after a death)
local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP"))

return function(S)
	local M = {}
	local CFG = S.CFG or {}
	local UP = S.UP or Vector3.yAxis
	local FLAT = S.FLAT or Vector3.new(1, 0, 1)
	local BASE = CFG.M1 or {}

	local function pick(v, i)
		if type(v) == "table" then
			return v[i] or v[#v]
		end
		return v
	end
	local function num(v, d)
		v = tonumber(v)
		if v == nil or v ~= v then
			return d
		end
		return v
	end

	local function state(st)
		local m = st.M1
		if type(m) ~= "table" then
			m = { combo = 0, last = -1e9, lockUntil = 0, gen = 0 }
			st.M1 = m
		end
		m.gen = m.gen or 0
		return m
	end

	-- the body's torso position (S.torsoOf returns a Part; query rows carry tp as a Vector3)
	local function torsoPos(mdl)
		if typeof(mdl) ~= "Instance" or not mdl.Parent then
			return nil
		end
		local tp = S.torsoOf(mdl)
		if typeof(tp) == "Instance" and tp:IsA("BasePart") then
			return tp.Position
		end
		if typeof(tp) == "Vector3" then
			return tp
		end
		return nil
	end

	-- LAG COMPENSATION (2026-11-10, "it's hard to hit people with the normal attack, especially when they're just
	-- running around"). The string locks on when the server gets the swing and lands HitAt later, and both ask where the
	-- server has the bodies NOW - but the attacker aimed at where his screen showed them, a network trip + the
	-- interpolation buffer earlier, and a runner has left the corridor by then. So a PLAYER is also tested where it stood
	-- through that window (PvP.lagOffsets: offsets to add to its points, [1] = now) with PvP.MELEE_PAD more room on every
	-- side. These passes only ever look at OTHER PLAYERS' characters: NPC hits are exactly as before.
	local PAD = tonumber(PvP.MELEE_PAD) or 1
	local TAG = CFG.TargetTag or "RagdollNPC"

	local function lagOffs(mdl, p, delay)
		local ok, offs = pcall(PvP.lagOffsets, mdl, p, delay)
		if ok and type(offs) == "table" and #offs > 0 then
			return offs
		end
		return { Vector3.zero }
	end

	-- the other living, standing players (only with CFG.AffectPlayers, like Core's queries) not in `skip`
	local function lagPlayers(p, char, skip)
		local out = {}
		if not CFG.AffectPlayers then
			return out
		end
		for _, mdl in ipairs(PvP.bodies(TAG, p)) do
			if mdl ~= char and not skip[mdl] and mdl.Parent and PvP.playerOf(mdl) and S.alive(mdl) and not PvP.isDown(mdl) then
				table.insert(out, mdl)
			end
		end
		return out
	end

	-- the points tested on a player: torso + head (R6: Torso + Head), and a giant form's body point nearest `from`
	local function lagPoints(mdl, from)
		local pts = {}
		if PvP.isForm(mdl) then
			local fp = PvP.formPoint(mdl, from)
			if fp then
				table.insert(pts, fp)
			end
		end
		for _, n in ipairs({ "UpperTorso", "Torso", "Head" }) do
			local part = mdl:FindFirstChild(n)
			if part and part:IsA("BasePart") then
				table.insert(pts, part.Position)
			end
		end
		return pts
	end

	-- S.nearSegment's test (within r of the segment a->b, `along` in [-1, len + 2], a clear line from `los`) widened by
	-- PAD and tried at every offset: the smallest `along` that passes, else nil
	local function lagSeg(mdl, offs, a, b, r, los)
		local d = b - a
		local len = d.Magnitude
		local u = len > 1e-3 and d / len or nil
		local from = a
		local fc = PvP.isForm(mdl) and PvP.formCenter(mdl)
		if fc and u then
			from = a + u * math.clamp((fc - a):Dot(u), 0, len)
		end
		local best = nil
		for _, pt in ipairs(lagPoints(mdl, from)) do
			for _, off in ipairs(offs) do
				local q = pt + off
				local along = u and (q - a):Dot(u) or 0
				local near = u and (a + u * math.clamp(along, 0, len)) or a
				if along >= -1 - PAD and along <= len + 2 + PAD and (q - near).Magnitude <= r + PAD
					and (best == nil or along < best) and (not los or S.clearLine(los, q)) then
					best = along
				end
			end
		end
		return best
	end

	-- S.inRadius's test (the torso within r of pos) widened by PAD and tried at every offset
	local function lagNear(mdl, offs, pos, r)
		for _, pt in ipairs(lagPoints(mdl, pos)) do
			for _, off in ipairs(offs) do
				if (pt + off - pos).Magnitude <= r + PAD then
					return true
				end
			end
		end
		return false
	end

	-- swings 1-4 throw the body around IN PLACE: the left jabs twist it to his left, the right jab to his right and a
	-- little up, the third jab folds it straight back, the leg whip (right leg sweeping right -> left) knocks it to his
	-- left. Returns push direction, HitReact style, power
	local function pushFor(combo, dir)
		local right = dir:Cross(UP)
		right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
		if combo == 1 then
			return (dir * 0.85 - right * 0.45).Unit, "twist", 1
		elseif combo == 2 then
			return (dir * 0.85 + right * 0.45 + UP * 0.2).Unit, "twist", 1
		elseif combo == 3 then
			return (dir + UP * 0.15).Unit, "flinch", 1.15
		end
		return (dir * 0.5 - right * 0.75 + UP * 0.35).Unit, "fold", 1.3
	end

	local function resolve(p, st, char, id, gen, sw)
		local m = st.M1
		if type(m) ~= "table" or m.gen ~= gen then
			return
		end
		local uid = p.UserId
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not S.valid(p, char) or not hrp then
			S.fire("M1Cancel", { id = id, userId = uid })
			S.release(p, id)
			return
		end
		local c, combo, final, aim, flat, fin = sw.c, sw.combo, sw.final, sw.aim, sw.flat, sw.fin
		local origin = S.limbRoot(char, sw.limb) or (hrp.Position + UP)
		local len = sw.len
		-- where the fist landed: on the homed body while it is still in reach, else the end of the (clamped) line
		local fistEnd = origin + aim * len
		local homed = nil
		local lagDelay = math.max(S.now() - (sw.t0 or S.now()), 0) -- the hit delay: the swing reached the server -> now
		if sw.target and not PvP.isDown(sw.target) then
			local tp = torsoPos(sw.target)
			if tp and (tp - origin).Magnitude <= len + 3 then
				fistEnd = tp
				homed = sw.target
			elseif tp and PvP.playerOf(sw.target) then
				-- (lag compensation) a player still in reach where the attacker saw him: the fist lands there
				for _, off in ipairs(lagOffs(sw.target, p, lagDelay)) do
					if (tp + off - origin).Magnitude <= len + 3 + PAD then
						fistEnd = tp + off
						homed = sw.target
						break
					end
				end
			end
		end
		local radius = num(pick(c.Radius, combo), 3)
		local exclude = { [char] = true }
		local list = {}
		local function add(mdl, tp, full)
			if typeof(mdl) == "Instance" and mdl.Parent and not exclude[mdl] and not PvP.isDown(mdl) then
				exclude[mdl] = true
				table.insert(list, { m = mdl, tp = tp, full = full })
			end
		end
		if homed then
			add(homed, fistEnd, true)
		end
		local rows = S.nearSegment(origin, fistEnd, radius, { los = origin, exclude = { [char] = true } }) or {}
		-- (lag compensation) the players the corridor / the fist miss NOW, tested where the attacker saw them
		local offsCache = {}
		local function offsOf(mdl)
			local o = offsCache[mdl]
			if not o then
				o = lagOffs(mdl, p, lagDelay)
				offsCache[mdl] = o
			end
			return o
		end
		-- adds them to the corridor rows at the `along` they were seen at (rows stay sorted by along)
		local function lagRows()
			local skip = {}
			for mdl in pairs(exclude) do
				skip[mdl] = true
			end
			for _, r in ipairs(rows) do
				if r.m then
					skip[r.m] = true
				end
			end
			local added = false
			for _, mdl in ipairs(lagPlayers(p, char, skip)) do
				local along = lagSeg(mdl, offsOf(mdl), origin, fistEnd, radius, origin)
				if along then
					table.insert(rows, { m = mdl, tp = torsoPos(mdl), along = along })
					added = true
				end
			end
			if added then
				table.sort(rows, function(x, y)
					return x.along < y.along
				end)
			end
		end
		if final then
			-- the finisher: the first body full, the rest of the corridor at half
			lagRows()
			for _, r in ipairs(rows) do
				add(r.m, r.tp, #list == 0)
			end
		else
			if #list == 0 then
				lagRows()
				if rows[1] then
					add(rows[1].m, rows[1].tp, true)
				end
			end
			local nearR = 2.5 * math.max(radius / 3, 1)
			local near = S.inRadius(fistEnd, nearR, { exclude = { [char] = true } }) or {}
			for _, r in ipairs(near) do
				add(r.m, r.tp, true)
			end
			for _, mdl in ipairs(lagPlayers(p, char, exclude)) do
				if lagNear(mdl, offsOf(mdl), fistEnd, nearR) then
					add(mdl, torsoPos(mdl), true)
				end
			end
		end

		local dmgFull = num(pick(c.Damage, combo), 7)
		local rag = num(c.RagTime, 2.6)
		local hitStop = num(c.FinalHitStop, 0.07)
		local any = false
		PvP.m1Begin(final) -- (2026-11-09) M1 hits: full damage on players, and they break a cast; (2026-11-11) the finisher breaks a block
		for _, h in ipairs(list) do
			local mdl = h.m
			local tp = torsoPos(mdl) or (typeof(h.tp) == "Vector3" and h.tp) or fistEnd
			local landed
			local fl = flat
			if final then
				local dmg = dmgFull * (h.full and 1 or 0.5)
				local vel
				local o = { hitStop = h.full and hitStop or nil }
				if sw.finisher == "Rifle" then
					local L = fin.launch or Vector2.new(12, 92)
					vel = flat * L.X * sw.launchMul + UP * L.Y * sw.launchMul
					o.spin = flat * 18 -- the corkscrew: spun about the punch line
				elseif sw.finisher == "Axe" then
					local L = fin.slam or Vector2.new(24, -80)
					vel = flat * L.X * sw.launchMul + UP * L.Y
					o.spin = flat:Cross(UP) * -10 -- folded face-first into the street
				else
					local L = c.FinalLaunch or Vector2.new(110, 40)
					local off = (tp - origin) * FLAT
					fl = off.Magnitude > 0.5 and (off.Unit * 0.4 + flat * 0.6).Unit or flat
					vel = fl * L.X + UP * L.Y
					vel, o.softRag = PvP.m1Finish(mdl, vel, rag) -- (2026-11-09) the Pistol blast keeps a player within reach
				end
				if not h.full then
					vel *= 0.7
				end
				landed = S.strike(p, mdl, vel, dmg, o.softRag or rag, o) ~= false
			elseif S.held(mdl) then
				landed = S.hurt(p, mdl, dmgFull) ~= false
			elseif S.alive(mdl) and not S.isRagdolled(mdl) then
				local push, style, power = pushFor(combo, flat)
				landed = S.hurt(p, mdl, dmgFull) ~= false
				if landed then
					S.react(p, mdl, push, power, style, num(c.HitSlide, 1), num(c.StunTime, 0.45))
				end
				fl = push
			else
				local J = c.Juggle or Vector2.new(22, 30)
				local push = pushFor(combo, flat) * FLAT
				push = push.Magnitude > 1e-3 and push.Unit or flat
				landed = S.strike(p, mdl, push * J.X + UP * J.Y, dmgFull, rag, { spin = push:Cross(UP) * 8 }) ~= false
				fl = push
			end
			if landed then
				any = true
				S.fire("M1Hit", {
					id = id, userId = uid, combo = combo, model = mdl, pos = tp, dir = fl, final = final,
					finisher = sw.finisher, mode = sw.mode,
				})
			end
		end

		PvP.m1End()
		-- the city: every fist breaks glass / panels where it lands (in the mode, 6.5 = the jabs dent walls too); the
		-- finisher BreakBlasts the fist end (>= 6: a Structure hole / crater)
		if final then
			local o = { dir = aim, speed = num(c.FinalBreakSpeed, 140) }
			if sw.finisher == "Rifle" then
				o.dir = (flat + UP * 1.4).Unit
			elseif sw.finisher == "Axe" then
				o.dir = (flat * 0.5 - UP).Unit
				-- the axe kick craters the street where the heel lands - never under his own feet
				local fd = ((fistEnd - hrp.Position) * FLAT).Magnitude
				local r = math.min(num(fin.crater, 8) * (sw.mode and 1.3 or 1), fd - 3)
				if r >= 3 then
					o.crater = { r = r, rocks = sw.mode and 12 or 8, speed = sw.mode and 85 or 60 }
				end
			end
			S.blast(p, fistEnd, num(c.FinalBlastRadius, 7), o)
		else
			S.blast(p, fistEnd, num(c.BlastRadius, 4.5), {})
		end
		if any then
			S.punchHit(p, combo, final, fin and fin.combo or nil)
		end
	end

	function M.M1(p, st, payload)
		local char, _, hrp, t = S.gate(p, "M1")
		if not char then
			return
		end
		local c = S.cfgFor(p, char, "M1")
		local m = state(st)
		if t - m.last < num(c.SwingInterval, 0.3) - 0.04 or t < (m.lockUntil or 0) then
			return
		end
		if t - m.last > num(c.ComboResetTime, 1.1) then
			m.combo = 0
		end
		local n = math.max(1, math.floor(num(c.ComboLength, 5)))
		local combo = (m.combo or 0) % n + 1
		local final = combo == n
		payload = type(payload) == "table" and payload or {}
		-- the finisher (hit 5 only): the client's pick, whitelisted against Config.M1.Finishers; default Pistol
		local finName, fin = nil, nil
		if final then
			local fins = type(c.Finishers) == "table" and c.Finishers or {}
			local want = payload.finisher
			finName = (type(want) == "string" and type(fins[want]) == "table") and want or "Pistol"
			fin = type(fins[finName]) == "table" and fins[finName] or {}
		end
		m.combo, m.last = combo, t
		if final then
			m.lockUntil = t + num(c.FinalCooldown, 0.9)
		end
		local mode = S.inMode(p, char) == true
		local limb = (fin and fin.limb) or pick(c.Limb, combo) or "R"
		local reach = num(pick(c.Reach, combo), 11)
		-- a finisher with its own reach grows with the mode like the Pistol does (Mode.M1.Reach[5] / base Reach[5])
		local modeScale = 1
		if final then
			local baseR = num(pick(BASE.Reach, n), reach)
			modeScale = baseR > 0 and math.clamp(reach / baseR, 1, 2) or 1
			if fin.reach then
				reach = num(fin.reach, reach) * modeScale
			end
		end
		local pitch = num(c.AimPitch, 35)
		local aim, flat = S.aimOf(payload, hrp, -pitch, pitch)
		local isLeg = limb == "RL" or limb == "LL"
		local origin = S.limbRoot(char, limb) or (hrp.Position + UP)
		local len
		if finName == "Axe" then
			-- the Battle Axe: the leg comes DOWN onto the street ahead of him
			local g = S.groundAt(hrp.Position + flat * reach * 0.6, 60)
			if g then
				local off = (g + UP * 0.5) - origin
				aim = off.Magnitude > 1e-3 and off.Unit or (flat * 0.75 - UP * 0.66).Unit
				len = math.min(S.clampPath(origin, aim, reach), reach)
				if off.Magnitude <= reach + 0.5 then
					len = math.max(len, math.min(off.Magnitude, reach))
				end
			else
				aim = (flat * 0.75 - UP * 0.66).Unit
				len = S.clampPath(origin, aim, reach)
			end
		else
			if isLeg then
				aim = flat
			end
			len = S.clampPath(origin, aim, reach)
		end
		len = math.max(num(len, reach), 0.5)
		-- lock-on: the first (living, else any) body in the corridor - the fist homes to it
		local radius = num(pick(c.Radius, combo), 3)
		local rows = S.nearSegment(origin, origin + aim * len, radius + 1.5, { los = origin, exclude = { [char] = true } }) or {}
		local target, targetAlong = nil, nil
		for _, r in ipairs(rows) do
			if r.m and S.alive(r.m) and not PvP.isDown(r.m) then
				target, targetAlong = r.m, r.along
				break
			end
		end
		-- (lag compensation) a player the attacker saw in the corridor (where it stood over the last network trip +
		-- interpolation buffer) counts too: the nearer of it and the first living row is the one the fist homes to
		do
			local inRows = {}
			for _, r in ipairs(rows) do
				if r.m then
					inRows[r.m] = true
				end
			end
			for _, mdl in ipairs(lagPlayers(p, char, inRows)) do
				local along = lagSeg(mdl, lagOffs(mdl, p, 0), origin, origin + aim * len, radius + 1.5, origin)
				if along and (targetAlong == nil or along < targetAlong) then
					target, targetAlong = mdl, along
				end
			end
		end
		if not target then
			for _, r in ipairs(rows) do
				if r.m and not PvP.isDown(r.m) then -- else a corpse; a body lying down after a fling is never homed onto
					target = r.m
					break
				end
			end
		end
		local hitAt = num(pick(c.HitAt, combo), 0.14)
		local id = S.commit(p, "M1", t, num(pick(c.Lock, combo), 0.16), char)
		local gen = m.gen
		S.fire("M1Swing", {
			id = id, userId = p.UserId, t0 = t, combo = combo, limb = limb, dir = flat, aim = aim, reach = len,
			hitAt = hitAt, target = target, finisher = finName, mode = mode,
		})
		local sw = {
			c = c, combo = combo, final = final, aim = aim, flat = flat, limb = limb, len = len, target = target,
			finisher = finName, fin = fin, mode = mode, launchMul = mode and 1.25 or 1, t0 = t,
		}
		S.at(t, hitAt, function()
			local ok, err = pcall(resolve, p, st, char, id, gen, sw)
			if not ok then
				S.warn("M1", tostring(err))
				S.release(p, id)
			end
		end)
	end

	function M.__reset(p, st, why)
		local m = st and st.M1
		if type(m) == "table" then
			m.gen = (m.gen or 0) + 1
			m.combo, m.last, m.lockUntil = 0, -1e9, 0
		end
	end

	return M
end
