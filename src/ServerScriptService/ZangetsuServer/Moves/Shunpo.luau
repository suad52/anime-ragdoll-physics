--!nocheck
-- (2026-11-10) a giant form's stand-in (S.torsoOf -> PvP.formRoot) is re-aimed at the body's mark before each check
local FORM_AIM = require(game:GetService("ServerScriptService"):WaitForChild("PvP")).aimAt
-- ZangetsuServer.Moves.Shunpo (owner: shunpo): E - SHUNPO, the flash-step cut (DESIGN §7.2, CONTRACT §4.3 / §5).
-- He vanishes, flashes along the flat aim to the cursor point (wall-clamped, ground-following), marks every body he
-- passed, stands back-turned through a silent beat, then everything he passed is cut at once.
--   ShunpoCast   { id, userId, t0, from, to, face, departAt, arriveAt, cutAt, targets = { { model, along, pos } }, mode,
--                  len (path length, added), secondAt (mode only, added) }
--   ShunpoCut    { id, userId, models, dirs, wave (1 | 2), mode, poses (torso positions, added) }
--   ShunpoCancel { id, userId }
-- The PATH (never inside geometry, never below the ground): the dash walks the ground in PathStep samples along the
-- flat direction. Each sample is snapped onto the ground under it (a ledge taller than MaxRise or a drop deeper than
-- MaxDrop ends the walk before it), and each segment between two standing positions is swept with a body-sized box
-- (Blockcast, colliding geometry only, its bottom StepClear above the feet) - the first sample whose sweep hits
-- anything ends the walk too. `to` is the last standing position that passed, at his own hip height above its ground;
-- a wall at 0 studs leaves `to` = where he stands (the dash plays in place, nothing hangs).
-- The CASTER's client moves itself from `from` to `to` (ctx.move); the server never moves him.
return function(S)
	local M = {}
	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local UP, FLAT = S.UP or Vector3.yAxis, S.FLAT or Vector3.new(1, 0, 1)
	local SKILL = "Shunpo"

	-- colliding world geometry only (no characters, NPC bodies or effects) - the same exclusions as S.refreshIgnore,
	-- plus RespectCanCollide so walk-through decorations / trigger volumes neither block nor floor the dash
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local function refresh()
		local list = {}
		for _, n in ipairs({ "NPCs", "FX", "KitFX", "KitDebris", "LocalFX" }) do
			local f = workspace:FindFirstChild(n)
			if f then
				table.insert(list, f)
			end
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(list, pl.Character)
			end
		end
		local tag = (S.CFG and S.CFG.TargetTag) or "RagdollNPC"
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			table.insert(list, m)
		end
		params.FilterDescendantsInstances = list
	end
	local function floorAt(pos, depth)
		local hit = workspace:Raycast(pos, Vector3.new(0, -depth, 0), params)
		return hit and hit.Position or nil
	end

	-- the standing body's swept box between two root positions (feet = root.Y - hip). Three centre-line rays (knee /
	-- hip / chest, reaching the box's front face) back it up: a shapecast ignores anything its START box already
	-- touches, so a wall he is pressed against would otherwise be swept straight through.
	local function sweepClear(fromRoot, toRoot, hip, dir, C)
		local step = toRoot - fromRoot
		if step.Magnitude < 1e-3 then
			return true
		end
		local reach = step + dir * (C.BodyDepth / 2)
		for _, y in ipairs({ C.StepClear + 0.2 - hip, 0, 1.2 }) do
			if workspace:Raycast(fromRoot + UP * y, reach, params) then
				return false
			end
		end
		local h = C.BodyTop - C.StepClear
		local a = fromRoot + UP * (C.StepClear + h / 2 - hip) -- box centre relative to the root
		local ok, hit = pcall(function()
			return workspace:Blockcast(CFrame.lookAt(a, a + dir), Vector3.new(C.BodyWidth, h, C.BodyDepth), step, params)
		end)
		return not ok or hit == nil
	end

	-- the dash end: returns (to, len) - see the header
	local function plan(hrp, hum, dir, want, C)
		refresh()
		local origin = hrp.Position
		local hip = (hum and hum.HipHeight or 2.19) + hrp.Size.Y / 2
		local own = floorAt(origin + UP * 0.5, hip + 30)
		local prevG = own and own.Y or (origin.Y - hip)
		local prevRoot, best, bestRoot = origin, 0, origin
		local s = 0
		local guard = 0
		while s < want - 1e-3 and guard < 64 do
			guard += 1
			local ns = math.min(s + C.PathStep, want)
			local q = origin + dir * ns
			local top = prevG + C.MaxRise + 0.5
			local g = floorAt(Vector3.new(q.X, top, q.Z), C.MaxRise + 0.5 + C.MaxDrop)
			if not g then
				break -- a cliff deeper than MaxDrop, the void, or a ledge whose top is above `top` (the ray starts inside it)
			end
			local root = Vector3.new(q.X, g.Y + hip, q.Z)
			if not sweepClear(prevRoot, root, hip, dir, C) then
				break
			end
			best, bestRoot, prevG, prevRoot, s = ns, root, g.Y, root, ns
		end
		return bestRoot, best
	end

	local function finiteV(v)
		if S.finite then
			return S.finite(v)
		end
		return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
	end

	local function liveCast(st, id)
		local c = st[SKILL]
		return c ~= nil and c.id == id and not c.cancelled
	end

	function M.Shunpo(p, st, payload)
		local char, hum, hrp, t = S.gate(p, SKILL)
		if not char then
			return
		end
		payload = type(payload) == "table" and payload or {}
		local C = S.cfgFor(p, char, SKILL)
		local mode = S.inMode(p, char) and true or false
		local uid = p.UserId
		local origin = hrp.Position

		-- 1. direction + wanted distance: the cursor point if it is a finite point within TargetRange, else the camera
		local dir, want
		local tgt = payload.target
		if finiteV(tgt) and (tgt - origin).Magnitude <= C.TargetRange then
			local fl = (tgt - origin) * FLAT
			if fl.Magnitude > 0.5 then
				dir = fl.Unit
				want = math.clamp(fl.Magnitude + C.Overshoot, C.MinRange, C.Range)
			end
		end
		if not dir then
			dir = S.flatDir(payload.aim, hrp.CFrame.LookVector)
			want = C.Range
		end
		local to, len = plan(hrp, hum, dir, want, C)

		-- 2. the bodies on the path (chest line, LOS from his chest), living first when over MaxTargets
		local chest = origin + UP * 1.2
		local b = len >= 1 and (to + UP * 1.2) or (chest + dir)
		local segLen = (b - chest).Magnitude
		local hits = S.nearSegment(chest, b, C.PathRadius, { los = chest, maxDY = C.MaxDY }) or {}
		if #hits > C.MaxTargets then
			local living, dead = {}, {}
			for _, h in ipairs(hits) do
				table.insert(S.alive(h.m) and living or dead, h)
			end
			hits = {}
			for _, list in ipairs({ living, dead }) do
				for _, h in ipairs(list) do
					if #hits < C.MaxTargets then
						table.insert(hits, h)
					end
				end
			end
			table.sort(hits, function(x, y)
				return x.along < y.along
			end)
		end
		local marked, targets = {}, {}
		for _, h in ipairs(hits) do
			local frac = math.clamp(h.along / math.max(segLen, 1e-3), 0, 1)
			local tpos = typeof(h.tp) == "Vector3" and h.tp or (typeof(h.tp) == "Instance" and h.tp.Position) or nil
			if tpos then -- Core's nearSegment hands back tp = the torso POSITION (a Vector3)
				table.insert(marked, { m = h.m, along = h.along, frac = frac, mark = tpos })
				table.insert(targets, { model = h.m, along = h.along, pos = tpos })
			end
		end

		-- 3. commit + broadcast
		local id = S.commit(p, SKILL, t, C.Lock, char)
		st[SKILL] = { id = id, cancelled = false, cut = false }
		local D, A, CUT = C.DepartAt, C.ArriveAt, C.CutAt
		S.fire("ShunpoCast", {
			id = id, userId = uid, t0 = t, from = origin, to = to, face = dir, departAt = D, arriveAt = A, cutAt = CUT,
			targets = targets, mode = mode, len = len, secondAt = mode and C.SecondCut and (CUT + C.SecondCut) or nil,
		})

		-- 4. each body is held still from the moment he passes it until the cut
		for _, tg in ipairs(marked) do
			S.at(t, D + tg.frac * (A - D), function()
				if not liveCast(st, id) then
					return
				end
				local m = tg.m
				FORM_AIM(tg.mark) -- (2026-11-10) a giant form: measured at its body point nearest the mark, every time
				local tp = m.Parent and S.torsoOf(m)
				if not tp then
					return
				end
				tg.mark = tp.Position
				if S.held(m) then
					return -- held by another kit: damaged at the cut, never moved
				end
				if S.alive(m) and not S.isRagdolled(m) then
					S.stun(m, math.max(t + CUT + C.HoldPad - S.now(), 0.05))
					S.push(m, Vector3.zero)
				else
					S.freezeBody(m, math.max(t + CUT - S.now(), 0.05), function() end)
				end
			end)
		end

		-- 5. the cut
		S.at(t, CUT, function()
			if not liveCast(st, id) then
				return
			end
			if not S.valid(p, char) then
				st[SKILL].cancelled = true
				S.fire("ShunpoCancel", { id = id, userId = uid })
				S.release(p, id)
				return
			end
			st[SKILL].cut = true
			local models, dirs, poses = {}, {}, {}
			local side = dir:Cross(UP)
			for _, tg in ipairs(marked) do
				local m = tg.m
				FORM_AIM(tg.mark)
				local tp = m.Parent and S.torsoOf(m)
				if tp and (tp.Position - tg.mark).Magnitude <= C.Escape then
					local vel = (dir * C.ForwardMix + UP).Unit * C.Fling + side * ((math.random() * 2 - 1) * C.Lateral)
					S.strike(p, m, vel, C.Damage, C.RagTime, { hitStop = C.HitStop, spin = S.randomUnit() * 14 })
					S.hook("WorldBlast", tp.Position, C.BlastRadius, uid)
					table.insert(models, m)
					table.insert(dirs, vel.Unit)
					table.insert(poses, tp.Position)
				end
			end
			S.fire("ShunpoCut", { id = id, userId = uid, models = models, dirs = dirs, wave = 1, mode = mode, poses = poses })
			if #models > 0 then
				S.log("Shunpo #%d cut %d bodies (%.1f studs)", id, #models, len)
			end

			-- Tensa Zangetsu: the second cut, SecondCut after the first (an absolute cast time, scheduled from t0)
			if mode and C.SecondCut and #models > 0 then
				S.at(t, CUT + C.SecondCut, function()
					local c = st[SKILL]
					if not c or c.id ~= id or not S.valid(p, char) then
						return
					end
					local m2, d2, p2 = {}, {}, {}
					for i, m in ipairs(models) do
						local tp = m.Parent and S.torsoOf(m)
						if tp then
							S.strike(p, m, nil, C.SecondDamage, C.RagTime)
							table.insert(m2, m)
							table.insert(d2, dirs[i])
							table.insert(p2, tp.Position)
						end
					end
					S.fire("ShunpoCut", { id = id, userId = uid, models = m2, dirs = d2, wave = 2, mode = mode, poses = p2 })
				end)
			end
		end)
	end

	-- died / respawn / unequip / left: the cast in flight never cuts; every client drops its leftovers
	function M.__reset(p, st, why)
		local c = st and st[SKILL]
		if c and not c.cancelled and not c.cut then
			c.cancelled = true
			S.fire("ShunpoCancel", { id = c.id, userId = p.UserId })
		end
		if why == "left" and st then
			st[SKILL] = nil
		end
	end

	return M
end
