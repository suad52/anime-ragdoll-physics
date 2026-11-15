--!nocheck
-- GomuKit.Client.Gatling (owner: gatling): Q, Gum-Gum GATLING (CONTRACT.md 8.2 / 4.2 / 6 / 7.3).
-- require(this)(ctx) -> { GatlingStart, GatlingAim, GatlingHit, GatlingChip, GatlingEnd, __update, __reset }.
-- Casts are keyed "userId#id"; e = ctx.now() - t0. W = windup (0.28), B = W + Duration (1.78), F = FinalAt (1.86).
--   0 .. W   PUFF: Clips.Gatling_Barrage (inhale, then the deep sit); air sucked into his mouth (inward streaks + a
--            collapsing ring), Swell; local caster: rooted facing the aim, the aim stream starts, the view squeezes in
--            (lean fov -5) and he sits back SitBack studs (ctx.move)
--   W        THE RELEASE: a shock ring + streak burst out ahead, a dust ring at his feet, Whoosh + Cannon (soft)
--   W .. B   THE STORM: alternating L / R stretched jabs every JabEvery (S.stretchArm, short out/hold/back) into random
--            points of the cone (HomeChance of them homing on bodies the server reported hit), FistsPerSecond
--            afterimage fists (S.fistGhost) from both shoulders, whoosh streaks, air-pressure rings ahead, dust kicked
--            back at his feet, a whoosh rattle; local caster: the cone follows the camera at TurnRate (as the server
--            does from the Aim stream), the storm's recoil slides him back SlideBack studs, a constant shudder shake,
--            FOV +8 and faint speed lines. Remote casters steer from GatlingAim
--   F - HeavyOut  the heavy last fist (R, x HeavyScale, ghosts + trail) flies to the cone's end point
--   F        THE FINAL: impact star + shock rings + a streak cone + a glow + dust at the end point, Cannon + HitHeavy +
--            Boom; local caster: impact frame, shake, speed lines and a Lunge-stud lunge (ctx.move)
-- GatlingHit: a small comic burst + sparks at the body (bigger after F), Hit rattle (throttled); local: a tick shake.
-- GatlingChip: rubble + dust + sparks where the storm chipped the facade, Hit2 / Shatter (throttled).
-- GatlingEnd: "done" draws the final where the server put it if this client has not drawn it yet; "cancel" retracts
-- every fist, stops the clip and (local) frees the body.
-- Gear 5 (d.mode): white rubber fists x Mode.Gatling.FistScale (2.4), a sun-tinted impact. No cast text: Q is not
-- the ultimate (no ctx.callout / showTitle / tally here).
-- Gating: the local caster and ctx.gate "full" draw everything; "lite" halves the jabs and drops ghosts / whooshes /
-- dust; nil draws nothing.
return function(ctx)
	local H = {}

	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")

	local FX = ctx.FX
	local PAL = ctx.PAL or {}
	local CFG_ALL = ctx.CFG or {}
	local CFG = CFG_ALL.Gatling or {}
	local MCFG = (type(CFG_ALL.Mode) == "table" and type(CFG_ALL.Mode.Gatling) == "table") and CFG_ALL.Mode.Gatling or {}
	local STRETCH = CFG_ALL.Stretch or {}
	local UP = Vector3.yAxis
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local C3 = Color3.fromRGB
	local rng = Random.new()

	local P = {
		Whoosh = PAL.Whoosh or C3(255, 250, 240), Impact = PAL.Impact or C3(255, 236, 160),
		Dust = PAL.Dust or C3(150, 140, 125), Vest = PAL.Vest or C3(205, 28, 36), Straw = PAL.Straw or C3(244, 206, 92),
		Nika = PAL.Nika or C3(252, 252, 255), Sun = PAL.Sun or C3(255, 228, 140), SunHot = PAL.SunHot or C3(255, 190, 70),
	}

	-- a tuning number for this cast (the mode's value first)
	local function tune(mode, k, default)
		local v = mode and MCFG[k] or nil
		if type(v) ~= "number" then
			v = CFG[k]
		end
		return type(v) == "number" and v or default
	end
	local function pair(v, a, b)
		if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then
			return v[1], v[2]
		end
		return a, b
	end
	local TURN = CFG.TurnRate or 110
	local JAB_P0, JAB_P1 = pair(CFG.JabPitch, -8, 14)
	local GHOST_LIFE = CFG.FistLife or STRETCH.GhostLife or 0.12

	local casts = {} -- "userId#id" -> cast

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function report(tag, err)
		if warned[tag] then
			return
		end
		warned[tag] = true
		warn("[Gomu.Gatling] " .. tostring(tag) .. ": " .. tostring(err))
	end
	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end
	-- a guarded Shared builder call (a missing / broken builder never kills a beat; each failure warns once)
	local function sh(name, ...)
		local S = ctx.S
		local fn = S and S[name]
		if type(fn) ~= "function" then
			report("Shared." .. name, "missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			report("Shared." .. name, r)
			return nil
		end
		return r
	end
	local function fx(name, ...)
		local fn = FX and FX[name]
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			report("FX." .. name, r)
			return nil
		end
		return r
	end
	-- a guarded ctx call
	local function cx(name, ...)
		local fn = ctx[name]
		if type(fn) ~= "function" then
			report("ctx." .. name, "missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			report("ctx." .. name, r)
			return nil
		end
		return r
	end
	local function hcall(h, method, ...)
		if h == nil then
			return
		end
		local ok, err = pcall(function(...)
			local fn = h[method]
			if type(fn) == "function" then
				fn(h, ...)
			end
		end, ...)
		if not ok then
			report("handle:" .. method, err)
		end
	end
	local function snd(k, part, vol, pitch)
		if live(part) then
			cx("sound", k, part, vol, pitch)
		end
	end
	local function sndAt(k, pos, vol, pitch)
		cx("soundAt", k, pos, vol, pitch)
	end

	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function flat(v, fallback)
		if type(ctx.flat) == "function" then
			local ok, r = pcall(ctx.flat, v, fallback)
			if ok and typeof(r) == "Vector3" then
				return r
			end
		end
		if typeof(v) == "Vector3" then
			local f = Vector3.new(v.X, 0, v.Z)
			if f.Magnitude > 1e-3 then
				return f.Unit
			end
		end
		return fallback or Vector3.new(0, 0, -1)
	end
	local function angle(a, b)
		return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
	end
	local function turnToward(a, b, maxDeg)
		local ang = angle(a, b)
		if ang <= maxDeg or ang < 1e-3 then
			return b
		end
		local s = a:Cross(b).Y >= 0 and 1 or -1
		return flat(CFrame.fromAxisAngle(UP, math.rad(maxDeg) * s):VectorToWorldSpace(a), a)
	end
	local function torsoOf(m)
		if typeof(m) ~= "Instance" or not m.Parent then
			return nil
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	end

	-- world-only rays (no characters, bodies or effects); the ignore list is refreshed at most 4x a second
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local rayFresh = 0
	local function refreshRay()
		local c = os.clock()
		if c - rayFresh < 0.25 then
			return
		end
		rayFresh = c
		local list = {}
		for _, n in ipairs({ "LocalFX", "NPCs", "FX", "KitFX", "KitDebris" }) do
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
		for _, m in ipairs(CollectionService:GetTagged(CFG_ALL.TargetTag or "RagdollNPC")) do
			table.insert(list, m)
		end
		rayParams.FilterDescendantsInstances = list
	end
	local function ray(a, dir, len)
		refreshRay()
		return workspace:Raycast(a, dir * len, rayParams)
	end
	-- how far he can travel from pos along dir (up to len) keeping `pad` off a wall
	local function room(pos, dir, len, pad)
		local hit = ray(pos, dir, len + pad)
		if hit then
			return math.clamp((hit.Position - pos).Magnitude - pad, 0, len)
		end
		return len
	end
	local function feetOf(hrp)
		local hit = ray(hrp.Position, -UP, 6)
		return hit and hit.Position or (hrp.Position - UP * 3), hit
	end
	local function groundColor(hit)
		if hit then
			local c = sh("groundColor", hit)
			if typeof(c) == "Color3" then
				return c
			end
		end
		return P.Dust
	end
	-- the shoulder (R / L) rig point, with fallbacks
	local function shoulder(char, hrp, side, dir)
		local cf = sh("limbRoot", char, side)
		if typeof(cf) == "CFrame" then
			return cf.Position
		elseif typeof(cf) == "Vector3" then
			return cf
		end
		local right = dir:Cross(UP)
		return hrp.Position + UP * 1.3 + right * (side == "R" and 1 or -1)
	end
	-- a random point of the cone: yaw +-half, pitch p0..p1, distance d0..d1 (a world ray stops it at a wall)
	local function conePoint(origin, dir, half, d0, d1, p0, p1, noRay)
		local d = CFrame.fromAxisAngle(UP, math.rad(rng:NextNumber(-half, half))):VectorToWorldSpace(dir)
		local right = d:Cross(UP)
		if right.Magnitude > 1e-3 then
			d = CFrame.fromAxisAngle(right.Unit, math.rad(rng:NextNumber(p0, p1))):VectorToWorldSpace(d)
		end
		d = d.Unit
		local len = rng:NextNumber(d0, math.max(d1, d0 + 0.1))
		if not noRay then
			local hit = ray(origin, d, len)
			if hit then
				len = math.max((hit.Position - origin).Magnitude - 0.4, 1)
			end
		end
		return origin + d * len, d
	end

	---------------------------------------------------------------------------------------------------
	-- the cast

	local function endCast(cast, cancelled)
		if cast.dead then
			return
		end
		cast.dead = true
		if casts[cast.key] == cast then
			casts[cast.key] = nil
		end
		if cancelled then
			for _, h in pairs(cast.limbs) do
				hcall(h, "retract", 0.1)
			end
			if cast.track then
				hcall(cast.track, "Stop", 0.15)
			end
			if cast.isLocal then
				if cast.mv then
					cx("stopMove")
				end
				cx("unroot")
			end
		end
		cast.mv = nil
	end

	-- the heavy last fist's end point: a recently hit body near the line, else the first wall down dir, else range
	local function heavyTarget(cast, chest)
		local best, bestD = nil, math.huge
		local c = os.clock()
		for m, at in pairs(cast.hits) do
			local tp = torsoOf(m)
			if tp and c - at < 0.6 then
				local rel = tp.Position - chest
				local along = rel:Dot(cast.dir)
				local off = (rel - cast.dir * along).Magnitude
				if along > 1 and along < cast.range + 2 and off < 6 and along < bestD then
					best, bestD = tp, along
				end
			end
		end
		if best then
			return best.Position, best
		end
		local hit = ray(chest, cast.dir, cast.range)
		return hit and hit.Position or (chest + cast.dir * cast.range), nil
	end

	local function drawFinal(cast, pos)
		if cast.finalDrawn then
			return
		end
		cast.finalDrawn = true
		local f = live(cast.f) and cast.f or cx("castFolder", "GatlingFinal", 3)
		local mode = cast.mode
		local dir = cast.dir
		local hot = mode and P.Sun or P.Impact
		local full = cast.tier == "full"
		pos = typeof(pos) == "Vector3" and pos or cast.endPt
		if typeof(pos) ~= "Vector3" then
			return
		end
		sh("impactStar", f, pos, { scale = mode and 2.6 or 1.8, color = hot, dir = dir })
		sh("shock", f, pos, -dir, { radius = mode and 14 or 10, color = P.Whoosh })
		fx("glow", f, pos, mode and 16 or 11, hot, 0.3)
		fx("light", f, pos, hot, 6, 30, 0.3)
		if full then
			fx("ring", f, pos, dir, 2, mode and 18 or 13, P.Whoosh, 0.35, { alpha = cast.isLocal and 0.35 or 0.1 })
			fx("streaks", f, pos, { dir = dir, spread = 32, count = 26, color = P.Whoosh, color2 = hot, speed = { 60, 130 }, life = 0.3, size = 0.5 })
			fx("sparks", f, pos, { dir = -dir, spread = 60, count = 18, color = hot, color2 = P.Whoosh, speed = { 25, 60 } })
			local g = ray(pos + UP * 2, -UP, 10)
			if g then
				sh("dustRing", f, g.Position, 5, 12, 28, { color = groundColor(g) })
				sh("cracks", f, g.Position, 6, 5, C3(58, 50, 44), 2.5, {})
			end
			sh("rubble", f, pos, 6, { dir = -dir })
		end
		sndAt("Cannon", pos, 0.8, 1.1)
		sndAt("HitHeavy", pos, 0.9, 1.0)
		sndAt("Boom", pos, 0.45, 1.35)
		if cast.isLocal then
			cx("impact", {
				tint = hot, tint2 = WHITE, lineColor = P.Whoosh, lineTime = 0.3, flash = hot, flashAlpha = 0.14,
				flashLife = 0.18,
			})
			cx("shake", 0.65, 0.35, 26, 6)
			cx("speedLines", 0.35, 0.5, P.Whoosh)
		else
			local k = math.clamp(1 - (camPos() - pos).Magnitude / 120, 0, 1)
			if k > 0.05 then
				cx("shake", 0.4 * k, 0.25, 26)
			end
		end
	end

	H.GatlingStart = function(d)
		if type(d) ~= "table" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			endCast(casts[key], true)
		end
		local char = cx("charOf", d.userId)
		if typeof(char) ~= "Instance" or not char.Parent then
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local isLocal = ctx.player ~= nil and d.userId == ctx.player.UserId
		local t0 = tonumber(d.t0) or ctx.now()
		local e = ctx.now() - t0
		local W = tonumber(d.windup) or CFG.Windup or 0.28
		local dur = tonumber(d.dur) or CFG.Duration or 1.5
		local F = tonumber(d.finalAt) or CFG.FinalAt or (W + dur + 0.08)
		if e > F + 0.6 then
			return -- stale: the storm is over
		end
		local tier = "full"
		if not isLocal then
			if type(ctx.gate) == "function" then
				local ok, g = pcall(ctx.gate, hrp.Position)
				if ok then
					tier = g
				end
			end
			if tier ~= "full" and tier ~= "lite" then
				return
			end
		end
		local mode = d.mode == true
		local dir = flat(d.dir, flat(hrp.CFrame.LookVector))
		local life = math.min(F + 1.4 - math.max(e, 0), 8)
		local f = cx("castFolder", "Gatling", life)
		local track = nil
		local clip = ctx.Clips and ctx.Clips.Gatling_Barrage
		if clip then
			track = cx("playClip", char, clip, math.max(e, 0))
		end
		local jabEvery = (CFG.JabEvery or 0.045) * (tier == "lite" and 2 or 1)
		local cast = {
			key = key, d = d, id = d.id, char = char, hrp = hrp, isLocal = isLocal, tier = tier, mode = mode, t0 = t0,
			dir = dir, want = dir, W = W, B = W + dur, F = F, range = tonumber(d.range) or CFG.Range or 22,
			half = tonumber(d.half) or CFG.HalfAngle or 26, steer = d.steer ~= false, f = f, track = track,
			jabEvery = jabEvery, nextJab = math.max(W - 0.03, e), side = "L", jabs = 0,
			nextGhost = W, nextWhoosh = W, nextRing = W, nextDust = W, nextShake = W, nextRattle = W,
			hits = {}, limbs = {}, lastStar = 0, lastHitSnd = 0, lastChipSnd = 0, lastTickShake = 0,
			fistScale = tune(mode, "FistScale", 1.1), released = e >= W, slid = false, heavy = false,
			finalDrawn = false, lunged = false, endAt = F + 0.7,
		}
		casts[key] = cast
		task.delay(math.max(life, 0.1), function()
			endCast(cast, false)
		end)

		-- 0.00 the PUFF
		if isLocal then
			local left = F + 0.28 - math.max(e, 0)
			if left > 0.02 then
				cx("root", left, dir)
			end
			cx("aimStream", d.id, math.max(F - math.max(e, 0), 0.05))
			if e < W then
				cx("lean", { fov = -5, attack = math.max(W - math.max(e, 0), 0.05), hold = 0.02, release = 0.1 })
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.FloorMaterial ~= Enum.Material.Air then
					local back = room(hrp.Position, -dir, tune(mode, "SitBack", 0.6), 1.6)
					if back > 0.05 then
						cast.mv = { char = char, t0 = t0, dur = math.max(W * 0.85, 0.05), from = hrp.Position,
							to = hrp.Position - dir * back, face = dir, ease = { "Quad", "Out" }, exitVel = Vector3.zero }
						cx("move", cast.mv)
					end
				end
			end
		end
		if e < W then
			local head = char:FindFirstChild("Head")
			snd("Swell", head or hrp, 0.55, 1.5)
			if head then
				local mouth = head.Position + flat(head.CFrame.LookVector, dir) * 0.7
				fx("streaks", f, mouth, { inward = 6, count = tier == "full" and 26 or 10, color = P.Whoosh, life = 0.24, size = 0.3 })
				fx("ring", f, mouth, dir, 6, 0.6, P.Whoosh, 0.24, { ease = "in", alpha = isLocal and 0.5 or 0.2 })
			end
		end
	end

	H.GatlingAim = function(d)
		if type(d) ~= "table" then
			return
		end
		local cast = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if cast and not cast.isLocal and typeof(d.dir) == "Vector3" then
			cast.want = flat(d.dir, cast.want)
		end
	end

	H.GatlingHit = function(d)
		if type(d) ~= "table" then
			return
		end
		local cast = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if not cast then
			return
		end
		if typeof(d.model) == "Instance" then
			cast.hits[d.model] = os.clock()
		end
		local tp = torsoOf(d.model)
		local pos = tp and tp.Position or d.pos
		if typeof(pos) ~= "Vector3" then
			return
		end
		local e = ctx.now() - cast.t0
		local final = e >= cast.F - 0.03
		local c = os.clock()
		local f = cast.f
		local hot = cast.mode and P.Sun or P.Impact
		if final or c - cast.lastStar >= (cast.tier == "full" and 0.05 or 0.12) then
			cast.lastStar = c
			local j = Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(-0.6, 0.9), rng:NextNumber(-0.8, 0.8))
			sh("impactStar", f, pos + j - cast.dir * 0.8, { scale = final and (cast.mode and 2 or 1.4) or (cast.mode and 0.9 or 0.6), color = hot, dir = cast.dir })
			if cast.tier == "full" then
				fx("sparks", f, pos, { dir = cast.dir, spread = 50, count = final and 16 or 5, color = hot, color2 = P.Whoosh, speed = { 15, 40 }, size = 0.4 })
			end
		end
		if final or c - cast.lastHitSnd >= 0.07 then
			cast.lastHitSnd = c
			sndAt(final and "HitHeavy" or "Hit", pos, final and 0.8 or 0.4, final and 1.1 or rng:NextNumber(1.1, 1.45))
		end
		if cast.isLocal and not final and c - cast.lastTickShake >= 0.09 then
			cast.lastTickShake = c
			cx("shake", 0.16, 0.1, 30)
		end
	end

	H.GatlingChip = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local cast = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		local tier = cast and cast.tier
		if not tier then
			if type(ctx.gate) == "function" then
				local ok, g = pcall(ctx.gate, d.pos)
				tier = ok and g or nil
			end
			if tier ~= "full" and tier ~= "lite" then
				return
			end
		end
		local f = (cast and live(cast.f)) and cast.f or cx("castFolder", "GatlingChip", 2.5)
		local n = typeof(d.normal) == "Vector3" and d.normal.Magnitude > 1e-3 and d.normal.Unit or UP
		local pos = d.pos + n * 0.6
		sh("dust", f, pos, n * 12 + UP * 3, { color = P.Dust, size = 3 })
		if tier == "full" then
			sh("rubble", f, pos, 3, { dir = n })
			fx("sparks", f, pos, { dir = n, spread = 45, count = 7, color = P.Impact, color2 = P.Whoosh, speed = { 18, 40 }, size = 0.35 })
		end
		local c = os.clock()
		if not cast or c - cast.lastChipSnd >= 0.12 then
			if cast then
				cast.lastChipSnd = c
			end
			sndAt(rng:NextNumber() < 0.35 and "Shatter" or "Hit2", pos, 0.35, rng:NextNumber(0.8, 1.05))
		end
	end

	H.GatlingEnd = function(d)
		if type(d) ~= "table" then
			return
		end
		local cast = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if d.why == "cancel" then
			if cast then
				endCast(cast, true)
			end
			return
		end
		if cast then
			if typeof(d.pos) == "Vector3" then
				cast.endPt = d.pos
			end
			if not cast.finalDrawn then
				drawFinal(cast, d.pos)
			end
		elseif typeof(d.pos) == "Vector3" and type(ctx.gate) == "function" then
			-- no cast record (joined late / was out of range then): the final hit alone
			local ok, g = pcall(ctx.gate, d.pos)
			if ok and (g == "full" or g == "lite") then
				drawFinal({ key = "", f = nil, mode = false, dir = Vector3.new(0, 0, -1), tier = g, isLocal = false, endPt = d.pos }, d.pos)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the storm, every frame

	local function jab(cast, e, chest)
		local char, hrp = cast.char, cast.hrp
		local side = cast.side
		if e >= cast.F - (CFG.HeavyOut or 0.1) - 0.08 then
			side = "L" -- the right fist is being drawn back for the heavy one
		else
			cast.side = (side == "L") and "R" or "L"
		end
		cast.jabs += 1
		local from = shoulder(char, hrp, side, cast.dir)
		local target = nil
		if rng:NextNumber() < (CFG.HomeChance or 0.55) then
			local list = {}
			local c = os.clock()
			for m, at in pairs(cast.hits) do
				if c - at < 0.5 then
					local tp = torsoOf(m)
					if tp and (tp.Position - chest).Magnitude < cast.range + 3 then
						table.insert(list, tp)
					end
				else
					cast.hits[m] = nil
				end
			end
			if #list > 0 then
				local tp = list[rng:NextInteger(1, #list)]
				target = tp.Position + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.8, 1.2), rng:NextNumber(-1, 1))
			end
		end
		if not target then
			target = conePoint(from, cast.dir, cast.half * 0.85, CFG.JabMin or 6, cast.range * 0.8, JAB_P0, JAB_P1)
		end
		local h = sh("stretchArm", char, side, target, {
			t0 = os.clock(), out = CFG.JabOut or 0.032, hold = CFG.JabHold or 0.008, back = CFG.JabBack or 0.04,
			fistScale = cast.fistScale * rng:NextNumber(0.95, 1.1), overshoot = 0.16, wobble = 0.12, sag = 0.02,
			trail = cast.tier == "full" and (cast.jabs % 2 == 0), white = cast.mode, folder = cast.f,
		})
		if h then
			cast.limbs[side] = h
		end
		if cast.tier == "full" and cast.jabs % 2 == 0 then
			sh("whoosh", cast.f, from, target, { color = P.Whoosh, life = 0.08, width = 0.3 })
		end
	end

	local function ghost(cast, chest)
		local side = rng:NextNumber() < 0.5 and "R" or "L"
		local from = shoulder(cast.char, cast.hrp, side, cast.dir)
		local pos, d = conePoint(from, cast.dir, cast.half, 2.5, cast.range * 0.75, JAB_P0 - 4, JAB_P1 + 4, true)
		local cf = CFrame.lookAt(pos, pos + d)
		sh("fistGhost", cf, cast.fistScale * rng:NextNumber(0.85, 1.15), {
			life = GHOST_LIFE, drift = 2.5, stub = rng:NextNumber(1.5, 4.5), white = cast.mode, folder = cast.f,
			alpha = rng:NextNumber(0.3, 0.55),
		})
	end

	local function stepCast(cast, clock, dt)
		local char, hrp = cast.char, cast.hrp
		if not live(char) or not live(hrp) then
			endCast(cast, true)
			return
		end
		local e = ctx.now() - cast.t0
		if e > cast.endAt then
			endCast(cast, false)
			return
		end
		local full = cast.tier == "full"

		-- steering (local: the camera; remote: the server's GatlingAim)
		if cast.steer and e < cast.F then
			local want = cast.want
			if cast.isLocal then
				local a = cx("camAim")
				if typeof(a) == "Vector3" then
					want = flat(a, cast.dir)
				end
			end
			if typeof(want) == "Vector3" then
				cast.dir = turnToward(cast.dir, want, TURN * math.clamp(dt, 0, 0.1))
			end
		end
		if cast.isLocal and e < cast.F + 0.25 then
			cx("setFace", cast.dir)
			if cast.mv then
				cast.mv.face = cast.dir -- the scaffold's mover keeps this table: its facing follows the steer
			end
		end
		local chest = hrp.Position + UP * 1.2

		-- W: the release
		if not cast.released and e >= cast.W then
			cast.released = true
			local ahead = chest + cast.dir * 3
			fx("ring", cast.f, ahead, cast.dir, 1.5, 10, P.Whoosh, 0.3, { alpha = cast.isLocal and 0.45 or 0.1 })
			if full then
				fx("streaks", cast.f, ahead, { dir = cast.dir, spread = 28, count = 20, color = P.Whoosh, speed = { 50, 100 }, life = 0.25, size = 0.35 })
				local fp, fh = feetOf(hrp)
				sh("dustRing", cast.f, fp, 3, 10, 22, { color = groundColor(fh) })
			end
			snd("Whoosh", hrp, 0.7, 1.15)
			snd("Cannon", hrp, 0.35, 1.6)
			if cast.isLocal then
				cx("lean", { fov = 8, attack = 0.12, hold = math.max(cast.B - e - 0.2, 0.1), release = 0.3 })
				cx("speedLines", math.max(cast.B - e, 0.2), 0.22, P.Whoosh)
				-- the storm's recoil slides him back
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.FloorMaterial ~= Enum.Material.Air then
					local back = room(hrp.Position, -cast.dir, tune(cast.mode, "SlideBack", 1.4), 1.6)
					if back > 0.05 then
						cast.mv = { char = char, t0 = cast.t0 + cast.W, dur = math.max(cast.B - cast.W, 0.1), from = hrp.Position,
							to = hrp.Position - cast.dir * back, face = cast.dir, ease = { "Sine", "InOut" }, exitVel = Vector3.zero }
						cx("move", cast.mv)
					end
				end
			end
		end

		-- W .. B: the storm
		if e >= cast.W - 0.03 and e < cast.B then
			local n = 0
			while cast.nextJab <= e and n < 2 do
				cast.nextJab += cast.jabEvery
				n += 1
				jab(cast, e, chest)
			end
			if cast.nextJab <= e then
				cast.nextJab = e + cast.jabEvery
			end
			if full then
				local every = 1 / math.max(CFG.FistsPerSecond or 28, 1)
				n = 0
				while cast.nextGhost <= e and n < 3 do
					cast.nextGhost += every
					n += 1
					ghost(cast, chest)
				end
				if cast.nextGhost <= e then
					cast.nextGhost = e + every
				end
				if cast.nextWhoosh <= e then
					cast.nextWhoosh = e + (CFG.WhooshEvery or 0.05)
					local side = rng:NextNumber() < 0.5 and "R" or "L"
					local a = shoulder(char, hrp, side, cast.dir)
					local b = conePoint(a, cast.dir, cast.half, 8, cast.range, JAB_P0, JAB_P1, true)
					sh("whoosh", cast.f, a + cast.dir * 1.5, b, { color = P.Whoosh, life = 0.07, width = 0.2 })
				end
				if cast.nextDust <= e then
					cast.nextDust = e + (CFG.DustEvery or 0.1)
					local fp, fh = feetOf(hrp)
					local right = cast.dir:Cross(UP)
					sh("dust", cast.f, fp + right * rng:NextNumber(-1, 1), -cast.dir * 10 + UP * 3, { color = groundColor(fh), size = 2.2 })
				end
			end
			if cast.nextRing <= e then
				cast.nextRing = e + (CFG.RingEvery or 0.12) * (full and 1 or 2)
				local at = chest + cast.dir * rng:NextNumber(4, 9) + UP * rng:NextNumber(-0.5, 0.8)
				fx("ring", cast.f, at, cast.dir, 1.2, rng:NextNumber(5, 8), P.Whoosh, 0.18, { alpha = cast.isLocal and 0.55 or 0.25 })
			end
			if cast.nextRattle <= e then
				cast.nextRattle = e + 0.09
				snd("Whoosh", hrp, full and 0.3 or 0.18, rng:NextNumber(1.35, 1.75))
			end
			if cast.isLocal and cast.nextShake <= e then
				cast.nextShake = e + (CFG.ShakeEvery or 0.1)
				cx("shake", 0.1, 0.14, 32)
			end
		end

		-- F - HeavyOut: the heavy last fist
		local heavyOut = CFG.HeavyOut or 0.1
		if not cast.heavy and e >= cast.F - heavyOut then
			cast.heavy = true
			local pt, part = heavyTarget(cast, chest)
			cast.endPt = cast.endPt or pt
			local late = math.max(e - (cast.F - heavyOut), 0)
			local h = sh("stretchArm", char, "R", part or pt, {
				t0 = os.clock() - late, out = heavyOut, hold = CFG.HeavyHold or 0.12, back = CFG.HeavyBack or 0.24,
				fistScale = cast.fistScale * tune(cast.mode, "HeavyScale", 1.9), armScale = CFG.HeavyArm or 1.25,
				overshoot = 0.12, ghosts = full, trail = true, white = cast.mode, folder = cast.f,
			})
			if h then
				cast.limbs.R = h
			end
			snd("Whoosh", hrp, 0.8, 0.95)
		end

		-- F: the final (the lunge, then the impact where the fist lands)
		if not cast.lunged and e >= cast.F - 0.04 then
			cast.lunged = true
			if cast.isLocal then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.FloorMaterial ~= Enum.Material.Air then
					local want = tune(cast.mode, "Lunge", 2.2)
					local go = room(hrp.Position, cast.dir, want, 1.6)
					if typeof(cast.endPt) == "Vector3" then
						local toBody = (cast.endPt - hrp.Position) * Vector3.new(1, 0, 1)
						go = math.min(go, math.max(toBody.Magnitude - 3.4, 0))
					end
					if go > 0.05 then
						cast.mv = { char = char, t0 = ctx.now(), dur = 0.12, from = hrp.Position, to = hrp.Position + cast.dir * go,
							face = cast.dir, ease = { "Quart", "Out" }, hold = 0.1, exitVel = Vector3.zero }
						cx("move", cast.mv)
					end
				end
			end
		end
		if not cast.finalDrawn and e >= cast.F then
			local h = cast.limbs.R
			local pos = nil
			if h and not h.dead and type(h.tip) == "function" then
				local ok, tp = pcall(h.tip, h)
				if ok and typeof(tp) == "Vector3" then
					pos = tp
				end
			end
			drawFinal(cast, pos or cast.endPt)
		end
	end

	H.__update = function(clock, dt)
		for _, cast in pairs(casts) do
			local ok, err = pcall(stepCast, cast, clock, tonumber(dt) or 1 / 60)
			if not ok then
				report("update", err)
				endCast(cast, true)
			end
		end
	end

	H.__reset = function()
		for _, cast in pairs(casts) do
			endCast(cast, true)
		end
		table.clear(casts)
	end

	return H
end
