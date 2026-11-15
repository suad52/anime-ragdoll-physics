--!nocheck
-- GomuKit.Client.Elephant (owner: elephant): R, GEAR THIRD - GUM-GUM ELEPHANT GUN (CONTRACT.md 8.4 / 4.2 / 6 / 7.3).
-- require(this)(ctx) -> { ElephantCast, ElephantHit, ElephantImpact, ElephantCancel, __update, __reset }.
-- Casts are keyed "userId#id"; e = ctx.now() - t0. Every client draws every caster (gated by ctx.gate: full <= 160,
-- lite <= 260, nothing past that). NO cast text (the cast-text rule): only non-text flair. Beats (t after t0):
--   0.00  the clip (Clips.Elephant_Cast, caught up to e); local: rooted facing the aim, the view squeezes in
--   0.05  BITE: the chomp (Hit2 high)
--   InflateAt  S.giantFist("R") inflates over InflateTime (steam from Shared), Swell + Sizzle + Hum, a dust ring
--         at his feet, local tremble; +0.18 / +0.38 pump pulses (rings off the fist); the haki coat crackles in
--   CoilAt -> PunchAt  the fist is drawn further back behind him (its rest point slides), a low wind whoosh
--   PunchAt  h:punch(endPos): Cannon + Boom + Whoosh (+ Crackle with haki), a muzzle ring, a dust burst at his
--         feet, a cone of whoosh streaks, body afterimages, fist afterimages along the flight, air-pressure rings
--         and a dust wall along the path timed to the fist; local: a 2.2-stud lunge (ctx.move), speed lines, an
--         FOV kick, shake. Gear 5: a white cartoon fist + a boing on the body
--   HitAt  THE IMPACT (drawn here at once; ElephantImpact only draws it when this client missed it): two impact
--         stars, three shock rings (aim / ground / wide), rubble, a dust ring + cracks on the ground, Boom +
--         HitHeavy + Thunder (+ Shatter on a wall); local: impact frame, a big shake + FOV, vignette
--   DeflateAt  h:deflate with a steam burst + Sizzle; local: he staggers back a step (recoil root motion)
-- ElephantHit: an impact star + Hit / HitHeavy + dust on the body; local shake. ElephantCancel: deflate now, stop.
return function(ctx)
	local H = {}

	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")

	local CFG_ALL = ctx.CFG or {}
	local CFG = CFG_ALL.Elephant or {}
	local PALC = ctx.PAL or {}
	local C3 = Color3.fromRGB
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local UP = Vector3.yAxis
	local FLAT = Vector3.new(1, 0, 1)
	local TAU = math.pi * 2
	local rng = Random.new()

	local P = {
		Haki = PALC.Haki or C3(22, 16, 24), HakiBolt = PALC.HakiBolt or C3(220, 30, 50),
		Whoosh = PALC.Whoosh or C3(255, 250, 240), Impact = PALC.Impact or C3(255, 236, 160),
		Dust = PALC.Dust or C3(150, 140, 125), Steam = PALC.Steam or C3(245, 245, 245),
		Nika = PALC.Nika or C3(252, 252, 255), Sun = PALC.Sun or C3(255, 228, 140), SunHot = PALC.SunHot or C3(255, 190, 70),
	}

	local function num(v, d)
		return type(v) == "number" and v == v and v or d
	end
	local ROOT_TIME = num(CFG.RootTime, 2.05)
	local INFLATE_TIME = num(CFG.InflateTime, 0.55)
	local LUNGE, LUNGE_TIME = num(CFG.Lunge, 2.2), num(CFG.LungeTime, 0.16)
	local RECOIL, RECOIL_TIME = num(CFG.Recoil, 1.5), num(CFG.RecoilTime, 0.24)
	local COIL_AT = num(CFG.CoilAt, 0.78)
	local STREAKS = num(CFG.Streaks, 12)
	local RING_EVERY = math.max(num(CFG.RingEvery, 9), 3)
	local DUST_EVERY = math.max(num(CFG.DustEvery, 5), 2)
	local END = num(CFG.End, 2.6)

	local casts = {} -- "userId#id" -> cast
	local recent = {} -- "userId#id" -> os.clock() a finished cast drew its impact (a late ElephantImpact draws nothing)

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function report(tag, err)
		if warned[tag] then
			return
		end
		warned[tag] = true
		warn("[Gomu.Elephant] " .. tostring(tag) .. ": " .. tostring(err))
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

	-- a guarded method call on a handle
	local function hcall(h, method, ...)
		if type(h) ~= "table" or h.dead then
			return nil
		end
		local fn = h[method]
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, h, ...)
		if not ok then
			report("handle:" .. method, r)
			return nil
		end
		return r
	end

	local function kill(h)
		if h == nil then
			return
		end
		if typeof(h) == "Instance" then
			pcall(function()
				h:Destroy()
			end)
			return
		end
		if type(h) == "table" then
			pcall(function()
				local fn = h.destroy or h.Destroy or h.stop or h.Stop
				if type(fn) == "function" then
					fn(h)
				end
			end)
		end
	end

	local function now()
		local ok, t = pcall(ctx.now)
		return (ok and type(t) == "number") and t or workspace:GetServerTimeNow()
	end
	local function myId()
		return ctx.player and ctx.player.UserId or (Players.LocalPlayer and Players.LocalPlayer.UserId)
	end
	local function hrpOf(char)
		return typeof(char) == "Instance" and char.Parent and char:FindFirstChild("HumanoidRootPart") or nil
	end
	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function gateAt(pos, me)
		if me then
			return "full"
		end
		if typeof(pos) ~= "Vector3" then
			return nil
		end
		if type(ctx.gate) == "function" then
			local ok, g = pcall(ctx.gate, pos)
			if ok then
				return g
			end
		end
		local d = (camPos() - pos).Magnitude
		return d <= 160 and "full" or (d <= 260 and "lite" or nil)
	end
	local function flatDir(v, fallback)
		if typeof(v) == "Vector3" then
			local f = v * FLAT
			if f.Magnitude > 1e-3 then
				return f.Unit
			end
		end
		return fallback or Vector3.new(0, 0, -1)
	end
	local function perp(v)
		local a = v:Cross(UP)
		if a.Magnitude < 0.1 then
			a = v:Cross(Vector3.xAxis)
		end
		a = a.Unit
		local b = v:Cross(a).Unit
		local th = rng:NextNumber(0, TAU)
		return a * math.cos(th) + b * math.sin(th)
	end

	-- world-only rays (no characters / bodies / effects): root-motion wall checks + ground lookups
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local rpAt = -1
	local function refreshRay()
		if os.clock() - rpAt < 0.25 then
			return
		end
		rpAt = os.clock()
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
		for _, m in ipairs(CollectionService:GetTagged(CFG_ALL.TargetTag or "RagdollNPC")) do
			table.insert(list, m)
		end
		rp.FilterDescendantsInstances = list
	end
	local function groundBelow(pos, depth)
		refreshRay()
		local hit = workspace:Raycast(pos + UP * 2, Vector3.new(0, -((depth or 16) + 2), 0), rp)
		return hit and hit.Position or nil
	end
	local function clampStep(from, dir, dist)
		refreshRay()
		local hit = workspace:Raycast(from, dir * (dist + 1.6), rp)
		if hit then
			return math.max((hit.Position - from).Magnitude - 1.6, 0)
		end
		return dist
	end

	local function tipOf(h)
		if type(h) ~= "table" or h.dead then
			return nil
		end
		local v = hcall(h, "tip")
		if typeof(v) == "Vector3" then
			return v
		end
		local f = h.fist
		return (typeof(f) == "Instance" and f:IsA("BasePart")) and f.Position or nil
	end

	local function shoulderOf(cast)
		local r = sh("limbRoot", cast.char, "R")
		if typeof(r) == "CFrame" then
			return r.Position
		end
		if typeof(r) == "Vector3" then
			return r
		end
		local hrp = hrpOf(cast.char)
		return hrp and (hrp.Position + UP * 1.5) or cast.endPos
	end

	local function snd(id, parent, vol, speed)
		if typeof(parent) == "Instance" then
			cx("sound", id, parent, vol, speed)
		end
	end
	local function sndAt(id, pos, vol, speed)
		if typeof(pos) == "Vector3" then
			cx("soundAt", id, pos, vol, speed)
		end
	end

	-- a beat: fn(e) runs once when e >= t (skipped when more than `late` s late)
	local function at(cast, t, fn, late)
		table.insert(cast.beats, { t = t, fn = fn, late = late or 0.25 })
	end

	---------------------------------------------------------------------------------------------------
	-- the impact (shared by the cast's own HitAt beat and ElephantImpact)

	local function drawImpact(f, pos, dir, wall, radius, me, mode, haki)
		local g = gateAt(pos, me)
		if not g then
			return
		end
		dir = (typeof(dir) == "Vector3" and dir.Magnitude > 1e-3) and dir.Unit or Vector3.new(0, 0, -1)
		radius = num(radius, 20)
		local full = g == "full"
		local col = mode and P.Sun or P.Impact
		local col2 = mode and P.SunHot or (haki and P.HakiBolt or WHITE)
		sh("impactStar", f, pos, { size = radius * 0.9, color = col, folder = f })
		sh("shock", f, pos, -dir, { radius = radius * 1.5, life = 0.45, color = WHITE, folder = f })
		local gp = groundBelow(pos, 16)
		if full then
			task.delay(0.06, function()
				sh("impactStar", f, pos - dir * 1.5, { size = radius * 0.6, color = col2, folder = f })
			end)
			task.delay(0.07, function()
				sh("shock", f, gp or pos, UP, { radius = radius * 1.9, life = 0.55, color = col, folder = f })
			end)
			task.delay(0.15, function()
				sh("shock", f, pos, -dir, { radius = radius * 2.4, life = 0.6, color = P.Whoosh, alpha = 0.5, folder = f })
			end)
			sh("rubble", f, pos - dir * 1.5, 18, { speed = 70, dir = -dir, folder = f })
			if gp then
				sh("dustRing", f, gp, radius * 0.7, 18, 60, { color = P.Dust, folder = f })
				sh("cracks", f, gp, 9, radius * 0.8, P.Dust, 3.5, { folder = f })
			end
			cx("glowFor", pos, radius * 1.2)
		end
		sndAt("Boom", pos, 1, 0.85)
		sndAt("HitHeavy", pos, 1, 0.7)
		sndAt("Thunder", pos, 0.6, 1.1)
		if wall then
			sndAt("Shatter", pos, 0.7, 0.9)
		end
		if me then
			cx("impact", {
				tint = col, tint2 = col2, lineColor = WHITE, lineTime = 0.4, flash = col, flashAlpha = 0.18, flashLife = 0.2,
			})
			cx("shake", 1.0, 0.55, 22, 10)
			cx("vignette", 0.22, 0.5, col2)
		else
			local d = (camPos() - pos).Magnitude
			if d < 200 then
				cx("shake", 0.7 * math.clamp(1 - d / 200, 0.15, 1), 0.4, 24)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the cast

	local function finish(cast)
		if cast.finished then
			return
		end
		cast.finished = true
		if cast.impacted and cast.key then
			recent[cast.key] = os.clock()
		end
		kill(cast.fist)
		cast.fist = nil
		kill(cast.steam)
		cast.steam = nil
	end

	H.ElephantCast = function(d)
		if type(d) ~= "table" or d.userId == nil or d.id == nil then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			return
		end
		local char = cx("charOf", d.userId)
		local hrp = hrpOf(char)
		local me = d.userId == myId()
		local t0 = num(d.t0, now())
		local flat = flatDir(d.dir, hrp and flatDir(hrp.CFrame.LookVector) or nil)
		local aim = (typeof(d.aim) == "Vector3" and d.aim.Magnitude > 1e-3) and d.aim.Unit or flat
		local endPos = typeof(d.endPos) == "Vector3" and d.endPos
			or ((hrp and hrp.Position or Vector3.zero) + aim * num(d.reach, 40))
		local gate = gateAt(hrp and hrp.Position or endPos, me)
		local gateEnd = gateAt(endPos, me)
		if not gate and not gateEnd then
			return
		end
		local mode = d.mode == true
		local cast = {
			key = key, userId = d.userId, t0 = t0, char = char, hrp = hrp, me = me, gate = gate or "lite",
			flat = flat, aim = aim, endPos = endPos, wall = d.wall == true, mode = mode,
			haki = d.haki ~= false and not mode,
			inflateAt = num(d.inflateAt, 0.08), punchAt = num(d.punchAt, 0.95), hitAt = num(d.hitAt, 1.19),
			hold = num(d.hold, 0.25), back = num(d.back, 0.4), deflateAt = num(d.deflateAt, 1.75),
			fistScale = num(d.fistScale, 7), armScale = num(d.armScale, 3.2),
			beats = {}, f = cx("castFolder", "Elephant", END + 3),
		}
		casts[key] = cast
		local f = cast.f
		local S = cast.fistScale
		local full = cast.gate == "full"
		local function body()
			return hrpOf(cast.char)
		end

		-- the giant fist's rest point: above + behind the right shoulder, drawn further back through the coil
		local function rest()
			local r = body()
			if not r then
				return nil
			end
			local e = now() - t0
			local k = math.clamp((e - COIL_AT) / math.max(cast.punchAt - COIL_AT, 0.05), 0, 1)
			k = k * k * (3 - 2 * k)
			return (r.CFrame * CFrame.new(1.8 + S * 0.22 + k * 0.8, 2.4 + S * 0.5 - k * 0.7, 1.2 + S * 0.3 + k * S * 0.35)).Position
		end

		-- 0: the clip + the local root / lens
		at(cast, 0, function(e)
			if char then
				cast.track = cx("playClip", char, "Elephant_Cast", math.max(e, 0))
			end
			if me then
				cx("root", math.max(ROOT_TIME - e, 0.1), flat)
				cx("lean", { fov = -5, pitch = 3, attack = 0.2, hold = 0.45, release = 0.3 })
			end
		end, 9)

		-- the bite
		at(cast, 0.05, function()
			snd("Hit2", body(), 0.5, 1.8)
		end, 0.2)

		-- INFLATE: the giant fist swells up behind him
		at(cast, cast.inflateAt, function(e)
			if e >= cast.punchAt then
				return
			end
			local grow = math.max(INFLATE_TIME - (e - cast.inflateAt), 0.08)
			if char then
				cast.fist = sh("giantFist", char, "R", {
					grow = grow, scale = S, armScale = cast.armScale, haki = cast.haki, white = mode, rest = rest,
					folder = f, keep = true,
				})
			end
			local r = body()
			snd("Swell", r, 0.9, 0.85)
			snd("Sizzle", r, 0.55, 1)
			snd("Hum", r, 0.45, 0.8)
			if r and full then
				local g = groundBelow(r.Position, 8)
				if g then
					sh("dustRing", f, g, 5, 10, 22, { color = P.Dust, folder = f })
				end
			end
			if me then
				cx("shake", 0.1, grow + 0.15, 32)
			end
		end, 9)

		-- pump pulses off the swelling fist
		for i, dt in ipairs({ 0.18, 0.38 }) do
			at(cast, cast.inflateAt + dt, function()
				local tp = tipOf(cast.fist)
				if tp and full then
					sh("shock", f, tp, UP, { radius = S * (0.7 + i * 0.25), life = 0.3, color = P.Steam, alpha = 0.45, folder = f })
				end
				snd("Hum", body(), 0.35, 0.9 + i * 0.15)
				if me then
					cx("shake", 0.16, 0.12, 30)
				end
			end, 0.2)
		end

		-- the haki coat (or Nika's glow) floods the fist as it finishes swelling
		at(cast, cast.inflateAt + INFLATE_TIME, function()
			local tp = tipOf(cast.fist)
			if cast.haki then
				snd("Crackle", body(), 0.7, 1)
			end
			if tp then
				sh("shock", f, tp, flatDir(camPos() - tp), {
					radius = S * 1.3, life = 0.25, color = cast.haki and P.HakiBolt or P.Sun, folder = f,
				})
			end
			if me then
				cx("flash", cast.haki and P.HakiBolt or P.Sun, 0.06, 0.15)
			end
		end, 0.2)

		-- the coil: a low wind
		at(cast, COIL_AT, function()
			snd("Whoosh", body(), 0.6, 0.55)
			if me then
				cx("lean", { fov = 5, pitch = -2, attack = 0.15, hold = 0.02, release = 0.1 })
			end
		end, 0.2)

		-- THE PUNCH
		at(cast, cast.punchAt, function(e)
			local left = cast.hitAt - e
			if left <= 0.02 then
				return
			end
			if cast.fist then
				hcall(cast.fist, "punch", cast.endPos, left, cast.hold, cast.back)
			end
			local r = body()
			snd("Cannon", r, 1, 0.95)
			snd("Boom", r, 0.6, 1.25)
			snd("Whoosh", r, 1, 0.7)
			if cast.haki then
				snd("Crackle", r, 0.7, 1.2)
			end
			local s0 = shoulderOf(cast)
			local len = (cast.endPos - s0).Magnitude
			sh("shock", f, s0 + aim * 3, aim, { radius = 7, life = 0.3, color = P.Whoosh, folder = f })
			if r then
				local g = groundBelow(r.Position, 8)
				if g then
					sh("dustRing", f, g, 6, 14, 45, { color = P.Dust, folder = f })
				end
			end
			if full then
				for _ = 1, STREAKS do
					local a = s0 + perp(aim) * rng:NextNumber(0.6, S * 0.6)
					local b = a + aim * rng:NextNumber(len * 0.45, len * 0.95)
					sh("whoosh", f, a, b, {
						color = P.Whoosh, width = rng:NextNumber(0.25, 0.6), life = rng:NextNumber(0.2, 0.35), folder = f,
					})
				end
				if char then
					sh("ghost", char, P.Whoosh, 0.55, 0.25)
				end
			end
			if mode and char then
				sh("boing", char, {})
			end
			if me then
				if r then
					local step = clampStep(r.Position, flat, LUNGE)
					if step > 0.2 then
						cx("move", {
							char = char, t0 = t0 + cast.punchAt, dur = LUNGE_TIME, from = r.Position, to = r.Position + flat * step,
							face = flat, ease = { "Quad", "Out" }, exitVel = Vector3.zero,
						})
					end
				end
				cx("speedLines", 0.5, 0.5, P.Whoosh)
				cx("lean", { fov = 12, pitch = 1, attack = 0.05, hold = 0.25, release = 0.45 })
				cx("shake", 0.4, 0.3, 26)
			else
				local dd = r and (camPos() - r.Position).Magnitude or 999
				if dd < 120 then
					cx("shake", 0.25 * (1 - dd / 120), 0.25, 26)
				end
			end

			-- the path, timed to the fist: air-pressure rings + a dust wall where the ground is near
			local span = math.max(cast.hitAt - cast.punchAt, 0.05)
			local side = flat:Cross(UP)
			local s = RING_EVERY
			while s < len do
				local at_s, ss = cast.punchAt + span * (s / len), s
				at(cast, at_s, function()
					if gateAt(s0 + aim * ss, me) == "full" then
						sh("shock", f, s0 + aim * ss, aim, {
							radius = S * 0.8 + ss * 0.03, life = 0.35, color = P.Whoosh, alpha = 0.45, folder = f,
						})
					end
				end, 0.2)
				s += RING_EVERY
			end
			s = DUST_EVERY
			while s < len do
				local at_s, pt = cast.punchAt + span * (s / len), s0 + aim * s
				at(cast, at_s, function()
					if gateAt(pt, me) ~= "full" then
						return
					end
					local g = groundBelow(pt, 10)
					if g then
						for _, sg in ipairs({ -1, 1 }) do
							sh("dust", f, g + side * sg * S * 0.4, side * sg * 22 + UP * 16 + flat * 10, { color = P.Dust, folder = f })
						end
					end
				end, 0.2)
				s += DUST_EVERY
			end
		end, 9)

		-- THE IMPACT (drawn here at once; the server's ElephantImpact only fills in for a client that missed it)
		at(cast, cast.hitAt, function()
			if cast.impacted then
				return
			end
			cast.impacted = true
			local pos = cast.wall and (cast.endPos + aim * 1.5) or cast.endPos
			local radius = num(CFG.EndBlastRadius, 20)
			if mode and type(CFG_ALL.Mode) == "table" and type(CFG_ALL.Mode.Elephant) == "table" then
				radius = num(CFG_ALL.Mode.Elephant.EndBlastRadius, radius)
			end
			drawImpact(f, pos, aim, cast.wall, radius, me, mode, cast.haki)
		end, 9)

		-- DEFLATE: steam, and he staggers back a step
		at(cast, cast.deflateAt, function()
			if cast.fist then
				hcall(cast.fist, "deflate", 0.35)
			end
			local r = body()
			snd("Sizzle", r, 0.8, 0.9)
			snd("Hit2", r, 0.5, 0.7)
			if r and full then
				cast.steam = sh("steam", r, 30, { color = P.Steam, folder = f })
				local stm = cast.steam
				task.delay(0.6, function()
					kill(stm)
				end)
			end
			if me and r then
				local step = clampStep(r.Position, -flat, RECOIL)
				if step > 0.2 then
					cx("move", {
						char = char, t0 = now(), dur = RECOIL_TIME, from = r.Position, to = r.Position - flat * step,
						face = flat, ease = { "Quad", "Out" }, exitVel = Vector3.zero,
					})
				end
				cx("shake", 0.15, 0.2, 24)
			end
		end, 0.4)
	end

	H.ElephantHit = function(d)
		if type(d) ~= "table" then
			return
		end
		local pos = d.pos
		if typeof(pos) ~= "Vector3" then
			local m = d.model
			local tp = typeof(m) == "Instance" and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart"))
			pos = tp and tp:IsA("BasePart") and tp.Position or nil
		end
		if not pos then
			return
		end
		local me = d.userId == myId()
		local g = gateAt(pos, me)
		if not g then
			return
		end
		local cast = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		local f = cast and cast.f or cx("castFolder", "ElephantHit", 3)
		local dir = cast and cast.aim or Vector3.new(0, 0, -1)
		local mode = cast and cast.mode
		sh("impactStar", f, pos, { size = 6, color = mode and P.Sun or P.Impact, folder = f })
		sndAt("Hit", pos, 1, 0.8)
		sndAt("HitHeavy", pos, 0.7, 0.95)
		if g == "full" then
			sh("dust", f, pos, dir * 40 + UP * 12, { color = P.Dust, folder = f })
		end
		if me then
			cx("shake", 0.45, 0.22, 30)
		end
	end

	H.ElephantImpact = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		local cast = casts[key]
		if (cast and cast.impacted) or (recent[key] and os.clock() - recent[key] < 6) then
			return
		end
		if cast then
			cast.impacted = true
		end
		local f = cast and cast.f or cx("castFolder", "ElephantImpact", 5)
		drawImpact(f, d.pos, d.dir, d.wall == true, d.radius, d.userId == myId(), cast and cast.mode, cast == nil or cast.haki)
	end

	H.ElephantCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		local cast = casts[key]
		if not cast then
			return
		end
		casts[key] = nil
		cast.dead = true
		if cast.fist then
			hcall(cast.fist, "deflate", 0.2)
			local h = cast.fist
			cast.fist = nil
			task.delay(0.5, function()
				kill(h)
			end)
		end
		if type(cast.track) == "table" then
			hcall(cast.track, "stop")
			hcall(cast.track, "Stop")
		end
		if cast.me then
			cx("stopMove")
			cx("unroot")
		end
		finish(cast)
	end

	-- beats + the fist's afterimage trail in flight
	local ghostAt = 0
	H.__update = function(clock, dt)
		local t = now()
		for key, at0 in pairs(recent) do
			if os.clock() - at0 > 6 then
				recent[key] = nil
			end
		end
		for key, cast in pairs(casts) do
			local e = t - cast.t0
			if cast.dead or e > END then
				casts[key] = nil
				finish(cast)
			else
				for _, b in ipairs(cast.beats) do
					if not b.done and e >= b.t then
						b.done = true
						if e - b.t <= b.late then
							local ok, err = pcall(b.fn, e)
							if not ok then
								report("beat " .. tostring(b.t), err)
							end
						end
					end
				end
				-- afterimage fists streaming off the flying fist
				if cast.gate == "full" and e >= cast.punchAt and e <= cast.hitAt + 0.05 and os.clock() - ghostAt >= 0.03 then
					local fp = cast.fist and cast.fist.fist
					if typeof(fp) == "Instance" and fp:IsA("BasePart") and fp.Parent then
						ghostAt = os.clock()
						sh("fistGhost", fp.CFrame, cast.fistScale, {
							life = 0.14, drift = 1.5, white = cast.mode, haki = cast.haki, folder = cast.f,
						})
					end
				end
			end
		end
	end

	H.__reset = function()
		for key, cast in pairs(casts) do
			casts[key] = nil
			cast.dead = true
			finish(cast)
		end
	end

	return H
end
