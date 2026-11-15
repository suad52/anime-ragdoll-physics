--!nocheck
-- GomuKit.Client.Rocket (owner: rocket): E - Gum-Gum ROCKET (CONTRACT §8.3). Every client plays every cast from the
-- server broadcasts on the server timeline (e = ctx.now() - t0):
--   RocketCast   { id, userId, t0, from, anchor, to, normal?, wall, windup, tension, pullBack, travel, dir, mode, ground }
--   RocketHit    { id, userId, model, pos, path }
--   RocketSlam   { id, userId, pos, dir, radius, wall, normal?, ground }
--   RocketCancel { id, userId, why }
-- Beats (W = windup 0.36, L = W + tension 0.52, A = L + travel):
--   0    THROW   both arms shoot out (Whoosh 1.45 + a rubber Rise) and grip the anchor +- GripSpread sideways (keep);
--                Rocket_Reach flings the chest after them; whoosh streaks from the shoulders to the grips
--   W    GRIP    a star + sparks + grit at the fists, a slap (Hit2); TENSION (Rocket_Tension): the body is dragged back
--                PullBack (caster mover, never into a wall behind him), heels dig in (dust), the rubber creaks (Rise
--                0.55); the caster's camera trembles and squeezes in
--   L    LAUNCH  a sonic ring + a crack of streaks + a dust ring where he stood; Thunder / Whoosh / Cannon; caster: mover
--                to `to` (Quad In), speed lines, FOV +LeanFov, a kick. The arms stay pinned to the anchor, so they
--                shorten as he flies
--   L..A FLY     Rocket_Fly (horizontal corkscrew), whoosh trails on all four limbs, body afterimages every GhostEvery,
--                pressure streaks peeling off him, a whoosh streak along the path
--   A    SLAM    the arms snap home, Rocket_Slam, an impact star + a shock ring + dust; caster: impact frame + shake
--   RocketSlam   (server-confirmed) the city hit: a second shock wave, a light flash, rubble / debris, cracks, a dust
--                burst, Boom + Shatter
-- NO cast text (only the ultimate shows a title). Remote casters (ctx.gate): "full" = everything; "lite" = the arms,
-- trails and the slam; nil = nothing. The body motion of a remote caster replicates by itself.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

return function(ctx)
	local H = {}

	local S, FX = ctx.S, ctx.FX
	local CFG = ctx.CFG or {}
	local PAL = ctx.PAL or CFG.Palette or {}
	local RC = type(CFG.Rocket) == "table" and CFG.Rocket or {}
	local RM = (type(CFG.Mode) == "table" and type(CFG.Mode.Rocket) == "table") and CFG.Mode.Rocket or {}
	local UP = ctx.UP or Vector3.yAxis
	local FLAT = ctx.FLAT or Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local C3 = Color3.fromRGB
	local rng = Random.new()
	local WHOOSH = PAL.Whoosh or C3(255, 250, 240)
	local IMPACT = PAL.Impact or C3(255, 236, 160)
	local DUST = PAL.Dust or C3(150, 140, 125)
	local STRAW = PAL.Straw or C3(244, 206, 92)
	local NIKA = PAL.Nika or C3(252, 252, 255)
	local SUN = PAL.Sun or C3(255, 228, 140)

	local function num(k, d, mode)
		local v = mode and RM[k]
		if type(v) == "number" then
			return v
		end
		v = RC[k]
		return type(v) == "number" and v or d
	end
	local SPREAD = num("GripSpread", 1.2)
	local EXIT = num("ExitSpeed", 30)
	local LEAN = num("LeanFov", 12)
	local GHOST_EVERY = num("GhostEvery", 0.035)
	local GHOST_ALPHA = num("GhostAlpha", 0.45)
	local GHOST_LIFE = num("GhostLife", 0.28)
	local SLAM_SHAKE = num("SlamShake", 0.75)
	local RECOVER = num("Recover", 0.45)

	local casts = {} -- "userId#id" -> live cast
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function warnOnce(key, msg)
		if not warned[key] then
			warned[key] = true
			warn("[Gomu.Rocket] " .. msg)
		end
	end
	-- a Shared builder, guarded: one missing or failing builder never takes a beat down with it
	local function S_(name, ...)
		local fn = S and S[name]
		if type(fn) ~= "function" then
			warnOnce(name, "Shared." .. name .. " is missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnOnce(name .. "!", "Shared." .. name .. " failed: " .. tostring(r))
			return nil
		end
		return r
	end
	-- a GojoFX primitive, guarded the same way
	local function FX_(name, ...)
		local fn = FX and FX[name]
		if type(fn) ~= "function" then
			warnOnce("FX." .. name, "GojoFX." .. name .. " is missing")
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnOnce("FX." .. name .. "!", "GojoFX." .. name .. " failed: " .. tostring(r))
			return nil
		end
		return r
	end
	local function call(obj, method, ...)
		if type(obj) == "table" then
			local fn = obj[method]
			if type(fn) == "function" then
				local ok, err = pcall(fn, obj, ...)
				if not ok then
					warnOnce("m." .. method, method .. " failed: " .. tostring(err))
				end
				return ok
			end
		end
		return false
	end
	local function snd(key, parent, vol, pitch)
		if typeof(parent) == "Instance" and parent.Parent then
			pcall(ctx.sound, key, parent, vol, pitch)
		end
	end
	local function sndAt(key, pos, vol, pitch)
		if typeof(pos) == "Vector3" then
			pcall(ctx.soundAt, key, pos, vol, pitch)
		end
	end
	local function glowFor(pos, size)
		for _, fn in ipairs({ S and S.glowFor, ctx.glowFor }) do
			if type(fn) == "function" then
				local ok, v = pcall(fn, pos, size)
				if ok and type(v) == "number" then
					return v
				end
			end
		end
		local ok, d = pcall(ctx.camDist, pos)
		return size * math.clamp((ok and type(d) == "number" and d or 30) / 30, 0.45, 1)
	end
	local function feetOf(pos)
		local ok, y = pcall(ctx.groundY, pos)
		if ok and type(y) == "number" and pos.Y - y < 12 then
			return Vector3.new(pos.X, y + 0.1, pos.Z), true
		end
		return pos - UP * 3, false
	end
	local function flat(v, fb)
		local ok, r = pcall(ctx.flat, v, fb)
		if ok and typeof(r) == "Vector3" and r.Magnitude > 0.5 then
			return r.Unit
		end
		local f = typeof(v) == "Vector3" and v * FLAT or Vector3.zero
		return f.Magnitude > 1e-3 and f.Unit or fb
	end
	local function gateOf(pos)
		if type(ctx.gate) ~= "function" then
			return "full"
		end
		local ok, g = pcall(ctx.gate, pos)
		if not ok then
			return "full"
		end
		return g
	end
	local function isMe(userId)
		return ctx.player ~= nil and userId == ctx.player.UserId
	end

	-- colliding world only (the pull-back must never drag him into a wall behind him)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true
	local function worldRay(a, v)
		local list = {}
		for _, n in ipairs({ "LocalFX", "FX", "KitFX", "KitDebris", "NPCs" }) do
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
		for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag or "RagdollNPC")) do
			table.insert(list, m)
		end
		rayParams.FilterDescendantsInstances = list
		return workspace:Raycast(a, v, rayParams)
	end

	-- run fn at cast time t (s after t0) unless the cast died; `late` = skip it when it is already that far past
	local function at(c, t, fn, late)
		local delay = c.t0 + t - ctx.now()
		if late and delay < -late then
			return
		end
		local function run()
			if c.dead then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				warnOnce("beat" .. tostring(t), "beat " .. tostring(t) .. " failed: " .. tostring(err))
			end
		end
		if delay <= 0 then
			task.spawn(run)
		else
			task.delay(delay, run)
		end
	end

	-- one clip at a time per cast: the new one fades in over the last, which is stopped
	local function clip(c, name, startAt)
		if not c.char or not c.char.Parent then
			return
		end
		for _, tr in ipairs(c.tracks) do
			call(tr, "stop", 0.07)
		end
		c.tracks = {}
		local ok, tr = pcall(ctx.playClip, c.char, name, math.max(startAt or 0, 0))
		if ok and type(tr) == "table" then
			table.insert(c.tracks, tr)
		end
	end

	local function releaseArms(c, secs)
		for side, h in pairs(c.arms) do
			if not call(h, "retract", secs) then
				call(h, "destroy")
			end
			c.arms[side] = nil
		end
	end

	local function stopCast(c, hard)
		if c.dead then
			return
		end
		c.dead = true
		if hard then
			for side, h in pairs(c.arms) do
				call(h, "destroy")
				c.arms[side] = nil
			end
		else
			releaseArms(c, 0.1)
		end
		if not c.landed then
			for _, tr in ipairs(c.tracks) do
				call(tr, "stop", 0.12)
			end
		end
		if c.trail then
			call(c.trail, "stop")
			c.trail = nil
		end
		if c.ghostConn then
			c.ghostConn:Disconnect()
			c.ghostConn = nil
		end
		if c.isLocal and (hard or not c.landed) then
			pcall(ctx.stopMove)
			pcall(ctx.unroot)
		end
		if casts[c.key] == c then
			casts[c.key] = nil
		end
	end

	---------------------------------------------------------------------------------------------------
	-- RocketCast

	H.RocketCast = function(d)
		if type(d) ~= "table" or typeof(d.from) ~= "Vector3" or typeof(d.anchor) ~= "Vector3" or typeof(d.to) ~= "Vector3" then
			return
		end
		local W = tonumber(d.windup) or num("Windup", 0.36)
		local T = tonumber(d.tension) or num("Tension", 0.16)
		local TR = tonumber(d.travel) or 0.3
		local L, A = W + T, W + T + TR
		local t0 = tonumber(d.t0) or ctx.now()
		local e0 = math.max(ctx.now() - t0, 0)
		if e0 > A + 1 then
			return -- long past
		end
		local key = keyOf(d)
		if casts[key] then
			stopCast(casts[key], true)
		end
		local isLocal = isMe(d.userId)
		local from, anchor, to = d.from, d.anchor, d.to
		local tier = isLocal and "full" or gateOf((from + to) / 2)
		if tier == nil then
			return
		end
		local full = tier == "full"
		local char = ctx.charOf(d.userId)
		if typeof(char) ~= "Instance" then
			char = nil
		end
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local mode = d.mode == true
		local dir = (typeof(d.dir) == "Vector3" and d.dir.Magnitude > 0.5) and d.dir.Unit
			or ((to - from).Magnitude > 0.5 and (to - from).Unit or Vector3.new(0, 0, -1))
		local flatD = flat(dir, hrp and flat(hrp.CFrame.LookVector, Vector3.new(0, 0, -1)) or Vector3.new(0, 0, -1))
		local nrm = typeof(d.normal) == "Vector3" and d.normal.Magnitude > 0.5 and d.normal.Unit or nil
		local f = ctx.castFolder("Rocket", math.max(A + 3 - e0, 3))
		local c = {
			key = key, t0 = t0, f = f, char = char, hrp = hrp, isLocal = isLocal, full = full, mode = mode, arms = {},
			tracks = {}, dead = false, landed = false, W = W, L = L, A = A, dir = dir, flatD = flatD, nrm = nrm,
			wall = d.wall == true, ground = d.ground == true, to = to,
		}
		casts[key] = c
		task.delay(A + 2.5 - e0, function()
			if casts[key] == c then
				casts[key] = nil
			end
			if c.ghostConn then
				c.ghostConn:Disconnect()
				c.ghostConn = nil
			end
		end)
		local accent = mode and NIKA or STRAW
		local fs = num("FistScale", 1.35, mode)

		-- the two grip points: either side of the anchor, in the surface's plane, a hair off it
		local side = dir:Cross(UP)
		if side.Magnitude < 0.1 then
			side = flatD:Cross(UP)
		end
		side = side.Magnitude > 0.1 and side.Unit or Vector3.xAxis
		if nrm then
			local s2 = side - nrm * side:Dot(nrm)
			if s2.Magnitude > 0.1 then
				side = s2.Unit
			end
		end
		local lift = nrm and nrm * 0.3 or Vector3.zero
		local grips = { R = anchor + side * SPREAD + lift, L = anchor - side * SPREAD + lift }

		-- 0 THROW: the clip for wherever the cast is now, both arms out to the grips (kept until the arrival)
		if char then
			if e0 < W then
				clip(c, "Rocket_Reach", e0)
			elseif e0 < L then
				clip(c, "Rocket_Tension", e0 - W)
			elseif e0 < A then
				clip(c, "Rocket_Fly", e0 - L)
			end
			if e0 < A then
				for _, sn in ipairs({ "R", "L" }) do
					local h = S_("stretchArm", char, sn, grips[sn], {
						t0 = os.clock() - e0, out = W, hold = 0.05, keep = true, trail = true, ghosts = full and e0 < W,
						white = mode, fistScale = fs, overshoot = 0.06, wobble = 0.25,
					})
					if type(h) == "table" and not h.dead then
						c.arms[sn] = h
					end
				end
			end
		end
		if e0 < W * 0.5 and hrp then
			snd("Whoosh", hrp, 0.85, 1.45)
			snd("Rise", hrp, 0.35, 1.6)
			if full then
				local sh = hrp.Position + UP * 1.2
				S_("whoosh", f, sh + side, grips.R, { life = W + 0.08, color = WHOOSH })
				S_("whoosh", f, sh - side, grips.L, { life = W + 0.08, color = WHOOSH })
			end
		end
		if isLocal then
			pcall(ctx.root, A + RECOVER - e0, flatD)
			if e0 < L then
				pcall(ctx.lean, { fov = -5, attack = math.max(L - e0, 0.1), hold = 0.02, release = 0.12 })
			end
		end

		-- W GRIP + TENSION
		at(c, W, function()
			clip(c, "Rocket_Tension", ctx.now() - t0 - W)
			for _, g in pairs(grips) do
				FX_("glow", f, g, glowFor(g, 4), accent, 0.2, { brightness = 2 })
				if full then
					FX_("sparks", f, g, { count = 8, color = WHITE, color2 = accent, speed = { 8, 22 }, size = 0.35, life = 0.35, dir = nrm })
				end
			end
			S_("impactStar", f, anchor + lift, { size = 3.2, color = accent, life = 0.22 })
			if full and nrm then
				FX_("ring", f, anchor + nrm * 0.2, nrm, 0.5, 5.5, accent, 0.3, { alpha = 0.3 })
				S_("dust", f, anchor + nrm * 0.4, nrm * 8, { count = 6 })
				if c.ground then
					S_("cracks", f, anchor, 5, 2.4, DUST, 1.2, {})
				end
			end
			sndAt("Hit2", anchor, 0.7, 1.3)
			sndAt("Hit", anchor, 0.4, 1.6)
			if hrp then
				snd("Rise", hrp, 0.5, 0.55) -- the rubber creak
				snd("Hum", hrp, 0.3, 1.4)
			end
			if isLocal then
				local _, _, me = ctx.myChar()
				local base = me and me.Position or from
				local pull = tonumber(d.pullBack) or num("PullBack", 2.5)
				local back = worldRay(base, -flatD * (pull + 1.5))
				if back then
					pull = math.max(0, (back.Position - base).Magnitude - 1.5)
				end
				c.pulled = base - flatD * pull
				pcall(ctx.move, {
					t0 = t0 + W, dur = T, from = base, to = c.pulled, face = flatD, ease = { "Quad", "Out" },
					hold = T + 0.3, exitVel = Vector3.zero,
				})
				pcall(ctx.shake, 0.14, T + 0.05, 45, 0)
			end
			if full and hrp then
				local feet = feetOf(hrp.Position)
				S_("dust", f, feet, -flatD * 10 + UP * 3, { count = 8 })
				FX_("streaks", f, feet + UP * 0.3, { dir = -flatD, spread = 25, count = 8, color = DUST, speed = { 10, 22 }, size = 0.5, life = 0.3 })
			end
		end, 0.3)

		-- L LAUNCH + the flight
		at(c, L, function()
			clip(c, "Rocket_Fly", ctx.now() - t0 - L)
			local start = (hrp and hrp.Parent and hrp.Position) or from
			local feet, grounded = feetOf(start)
			FX_("ring", f, start + dir * 1.5, dir, 1.5, full and 12 or 8, WHOOSH, 0.32, { alpha = 0.15 })
			if full then
				FX_("ring", f, start + dir * 4, dir, 1, 7, accent, 0.25, { alpha = 0.35 })
				FX_("streaks", f, start + UP * 0.5, { dir = -dir, spread = 35, count = 18, color = WHOOSH, color2 = accent,
					speed = { 50, 90 }, size = 0.4, life = 0.25 })
				if grounded then
					S_("dustRing", f, feet, 2.5, 10, 30, {})
					FX_("ring", f, feet + UP * 0.2, UP, 2, 11, DUST, 0.5, { alpha = 0.3 })
				end
			end
			if hrp then
				snd("Thunder", hrp, 0.45, 1.7)
				snd("Whoosh", hrp, 1, 1.1)
				snd("Cannon", hrp, 0.4, 1.5)
			end
			if isLocal then
				local _, _, me = ctx.myChar()
				local base = c.pulled or (me and me.Position) or from
				local exitVel
				if c.wall and nrm then
					exitVel = nrm * 10 + UP * 14 -- bounces off the wall (boing)
				elseif c.ground then
					exitVel = flatD * 12 -- a skid
				else
					exitVel = dir * EXIT
				end
				pcall(ctx.move, { t0 = t0 + L, dur = TR, from = base, to = to, face = flatD, ease = { "Quad", "In" }, exitVel = exitVel })
				pcall(ctx.speedLines, TR + 0.2, 0.6, WHOOSH)
				pcall(ctx.lean, { fov = LEAN, attack = TR * 0.7, hold = 0.06, release = 0.3 })
				pcall(ctx.shake, 0.35, 0.18, 32, 0)
			end
			if c.char then
				c.trail = S_("limbTrail", c.char, "All", WHOOSH, accent, 0.18, TR + 0.25)
			end
			if full then
				S_("whoosh", f, start + UP * 0.5, to + UP * 0.5, { life = TR + 0.25, color = WHOOSH })
			end
			-- afterimages + pressure streaks peeling off him through the flight
			if c.char and hrp and full then
				local lastG, lastS = 0, 0
				c.ghostConn = RunService.Heartbeat:Connect(function()
					if c.dead or ctx.now() - t0 > A + 0.02 or not hrp.Parent then
						if c.ghostConn then
							c.ghostConn:Disconnect()
							c.ghostConn = nil
						end
						return
					end
					local clock = os.clock()
					if clock - lastG >= GHOST_EVERY then
						lastG = clock
						S_("ghost", c.char, mode and NIKA or WHOOSH, GHOST_ALPHA, GHOST_LIFE, nil, {})
					end
					if clock - lastS >= 0.07 then
						lastS = clock
						FX_("streaks", f, hrp.Position, { dir = -dir, spread = 30, count = 4, color = WHOOSH, speed = { 30, 60 },
							size = 0.35, life = 0.18 })
					end
				end)
			end
		end, 0.25)

		-- A SLAM (on the timeline; the server's RocketSlam adds the city hit)
		at(c, A, function()
			c.landed = true
			releaseArms(c, 0.09)
			clip(c, "Rocket_Slam", ctx.now() - t0 - A)
			if c.trail then
				local tr = c.trail
				c.trail = nil
				task.delay(0.12, function()
					call(tr, "stop")
				end)
			end
			local at0 = (hrp and hrp.Parent and hrp.Position) or to
			local p = at0 + dir * 1.5
			local ringN = (c.wall and nrm) or (c.ground and UP) or dir
			S_("impactStar", f, p, { size = full and 7 or 5, color = IMPACT, life = 0.3 })
			FX_("ring", f, p, ringN, 1.5, full and 16 or 10, WHITE, 0.4, { alpha = 0.1 })
			FX_("glow", f, p, glowFor(p, 9), IMPACT, 0.25, { brightness = 2.2 })
			if full then
				FX_("sparks", f, p, { count = 18, color = WHITE, color2 = accent, speed = { 20, 50 }, size = 0.45, life = 0.5 })
				local fe, grounded = feetOf(at0)
				if grounded then
					S_("dustRing", f, fe, 3, 14, 36, {})
				end
			end
			sndAt("HitHeavy", p, 0.9, 1.0)
			sndAt("Hit2", p, 0.6, 1.25) -- the arms snapping home
			if isLocal then
				pcall(ctx.impact, { tint = IMPACT, flashAlpha = 0.16, lines = true, lineTime = 0.25, lineColor = WHOOSH })
				pcall(ctx.shake, SLAM_SHAKE, 0.35, 28, 6)
			end
		end, 0.6)
	end

	---------------------------------------------------------------------------------------------------
	-- RocketHit / RocketSlam / RocketCancel

	H.RocketHit = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local c = casts[keyOf(d)]
		local isLocal = isMe(d.userId)
		local tier = isLocal and "full" or gateOf(d.pos)
		if tier == nil then
			return
		end
		local f = (c and c.f and c.f.Parent and c.f) or ctx.castFolder("RocketHit", 2)
		local accent = (c and c.mode) and NIKA or IMPACT
		S_("impactStar", f, d.pos, { size = d.path and 3.5 or 4.5, color = accent, life = 0.2 })
		if tier == "full" then
			FX_("sparks", f, d.pos, { count = 10, color = WHITE, color2 = accent, speed = { 15, 35 }, size = 0.35, life = 0.35 })
			if d.path and c then
				FX_("streaks", f, d.pos, { dir = c.dir, spread = 40, count = 8, color = WHOOSH, speed = { 30, 60 }, size = 0.35, life = 0.2 })
			end
		end
		sndAt(d.path and "Hit" or "HitHeavy", d.pos, 0.7, 0.9 + rng:NextNumber() * 0.3)
		if isLocal then
			pcall(ctx.shake, 0.2, 0.12, 40, 0)
		end
	end

	H.RocketSlam = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local c = casts[keyOf(d)]
		local isLocal = isMe(d.userId)
		local tier = isLocal and "full" or gateOf(d.pos)
		if tier == nil then
			return
		end
		local full = tier == "full"
		local f = (c and c.f and c.f.Parent and c.f) or ctx.castFolder("RocketSlam", 4)
		local pos = d.pos
		local R = tonumber(d.radius) or 13
		local nrm = typeof(d.normal) == "Vector3" and d.normal.Magnitude > 0.5 and d.normal.Unit or UP
		local dir = typeof(d.dir) == "Vector3" and d.dir.Magnitude > 0.5 and d.dir.Unit or nrm
		local mode = c and c.mode
		local tint = mode and NIKA or IMPACT
		-- the shock wave across the surface he hit, and a ground wave when there is ground under it
		FX_("ring", f, pos + nrm * 0.3, nrm, 2, R * 1.6, tint, 0.5, { alpha = 0.15 })
		FX_("light", f, pos + nrm * 2, mode and SUN or IMPACT, 8, 30, 0.3)
		local g, grounded = feetOf(pos + nrm * 1)
		if grounded then
			FX_("ring", f, g + UP * 0.2, UP, 3, R * 1.3, DUST, 0.7, { alpha = 0.25 })
		end
		if full then
			FX_("glow", f, pos + nrm, glowFor(pos, R * 0.9), tint, 0.3, { brightness = 2 })
			FX_("streaks", f, pos + nrm * 0.5, { dir = nrm, spread = 60, count = 22, color = WHITE, color2 = DUST,
				speed = { 40, 90 }, size = 0.45, life = 0.3 })
			FX_("sparks", f, pos + nrm * 0.5, { dir = nrm, spread = 70, count = 16, color = DUST, color2 = WHITE,
				speed = { 20, 45 }, size = 0.6, life = 0.8, accel = Vector3.new(0, -60, 0) })
			S_("dust", f, pos + nrm * 0.5, nrm * 14 + dir * 6, { count = 14 })
			if grounded then
				FX_("rubble", f, g + UP * 1, { count = 10, radius = R * 0.35, dir = dir, depth = 12 })
				S_("cracks", f, g, 8, R * 0.5, DUST, 2.5, {})
				S_("dustRing", f, g, R * 0.4, 16, 40, {})
			end
		end
		sndAt("Boom", pos, 0.8, 1.15)
		sndAt("Shatter", pos, 0.5, 1.0)
		if isLocal then
			pcall(ctx.shake, 0.4, 0.3, 24, 3)
		end
	end

	H.RocketCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local c = casts[keyOf(d)]
		if c and not c.dead then
			stopCast(c, false)
		end
	end

	-- the local character died / respawned / unequipped: drop his casts (and give the body back)
	H.__reset = function()
		for _, c in pairs(casts) do
			if c.isLocal then
				stopCast(c, true)
			end
		end
	end

	return H
end
