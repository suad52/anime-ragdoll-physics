--!nocheck
local SfxBank = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("SfxBank")) -- (2026-11-12)
-- GomuKit.Client.M1 (owner m1): the Gum-Gum string on every client (CONTRACT 8.1). require(this)(ctx) ->
-- { M1Swing, M1Hit, M1Cancel, __reset }. Casts keyed "userId#id"; e = ctx.now() - t0; W = d.hitAt (fist arrival).
--   0.00   the swing clip (M1_Jab1/2/3, M1_Whip, M1_Pistol / M1_Rifle / M1_Axe; legs + Root dropped while running);
--          anticipation streaks sucked into the shoulder (the finisher: a bigger gather + a glow); Gear 5: S.boing
--   Delay  the rubber limb leaves the shoulder (hip): S.stretchArm / S.stretchLeg homing onto d.target's torso (else
--          the wall-clamped end of the aim line), out = W - Delay, trail on, ghosts on the finisher, white in the
--          mode (giant cartoon fists x Mode.M1.FistScale), corkscrew spiral on the Rifle. Whoosh (pitch ~1.45) + a speed
--          streak down the line. Local caster: a root-motion step (Step, stops StopShort short of the body, a wall ray),
--          the finisher roots him (the Axe hangs him in the air and drives him down after), finisher speed lines
--   W      the fist lands: an air-pressure ring + forward streaks off the fist; into a wall: dust + cracks; the
--          finisher: shock ring + comic impact star + a light + Cannon (Rifle: an upward burst; Axe: the street
--          splits - shock + cracks + dust ring + rubble + HitHeavy/Boom)
--   W+hold the rubber snaps back (Hit2 pitch 1.3)
-- M1Hit (per body): a comic impact star, sparks + dust along the push, Hit / HitHeavy; the fist squashes on impact
--   (h:setScale); once per swing: the caster's clip hit-stops; the local caster shakes (finisher: impact frame +
--   speed lines). M1Cancel: the limb snaps back. NO cast text anywhere (CONTRACT 0.5).
-- Gating (other casters, ctx.gate): "full" everything, "lite" clip + stretch + sounds, nil nothing.
return function(ctx)
	local H = {}

	local Players = game:GetService("Players")

	local FX = ctx.FX
	local CFG = ctx.CFG or {}
	local M1 = CFG.M1 or {}
	local MODE_M1 = (CFG.Mode and CFG.Mode.M1) or {}
	local PAL = ctx.PAL or CFG.Palette or {}
	local UP = Vector3.yAxis
	local FLATV = Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local rng = Random.new()

	-- PERKS (2026-11-07, kitsE): the Trail Pack perk restyles the fist's whoosh trail with the CASTER's EquipTrail
	-- (PerkShared.TrailStyle; local and remote casters alike)
	local TrailStyle = nil
	do
		local ps = game:GetService("ReplicatedStorage"):FindFirstChild("PerkShared")
		local mod = ps and ps:FindFirstChild("TrailStyle")
		if mod and mod:IsA("ModuleScript") then
			local ok, res = pcall(require, mod)
			if ok and type(res) == "table" and type(res.apply) == "function" then
				TrailStyle = res
			end
		end
	end
	local function perkTrail(char, tr)
		if not TrailStyle or typeof(tr) ~= "Instance" or not tr:IsA("Trail") then
			return
		end
		local p = typeof(char) == "Instance" and Players:GetPlayerFromCharacter(char)
		local id = p and p:GetAttribute("EquipTrail") or ""
		pcall(TrailStyle.apply, tr, type(id) == "string" and id or "")
	end

	local WHOOSH = PAL.Whoosh or WHITE
	local IMPACT = PAL.Impact or Color3.fromRGB(255, 236, 160)
	local STAR = PAL.M1Star or IMPACT
	local RING = PAL.M1Ring or WHOOSH
	local PISTOL = PAL.M1Pistol or Color3.fromRGB(255, 214, 120)
	local VEST = PAL.Vest or Color3.fromRGB(205, 28, 36)
	local DUST = PAL.Dust or Color3.fromRGB(150, 140, 125)
	local SUN = PAL.Sun or Color3.fromRGB(255, 228, 140)
	local NIKA = PAL.Nika or WHITE

	local DELAY = M1.Delay or { 0.02, 0.02, 0.025, 0.035, 0.07 }
	local STOP_SHORT = M1.StopShort or 3.4
	local WALL_PAD = M1.WallPad or 1.6
	local HOME_INSET = M1.HomeInset or 0.9
	local FINAL_ROOT = M1.FinalRoot or 0.34
	local AXE_HANG = M1.AxeHang or 0.05
	local AXE_DROP = M1.AxeDrop or 55
	local GATE_RICH = M1.GateRich or 120
	local CLIP = { "M1_Jab1", "M1_Jab2", "M1_Jab3", "M1_Whip" }
	local FIN_CLIP = { Pistol = "M1_Pistol", Rifle = "M1_Rifle", Axe = "M1_Axe" }

	local casts = {} -- "userId#id" -> cast
	local lastTrack = setmetatable({}, { __mode = "k" }) -- [char] = the latest swing track
	local warned = {}
	H._stats = { casts = 0, hits = 0 }

	---------------------------------------------------------------------------------------------------
	-- helpers

	local function warnOnce(tag, msg)
		if not warned[tag] then
			warned[tag] = true
			warn("[Gomu.M1] " .. tag .. ": " .. tostring(msg))
		end
	end

	local function try(tag, fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, res = pcall(fn, ...)
		if not ok then
			warnOnce(tag, res)
			return nil
		end
		return res
	end

	-- a Shared builder, guarded (Shared may be missing or one builder broken)
	local function shared(name, ...)
		local S = ctx.S
		local fn = S and S[name]
		if type(fn) ~= "function" then
			return nil
		end
		return try("Shared." .. name, fn, ...)
	end
	local function has(name)
		return ctx.S ~= nil and type(ctx.S[name]) == "function"
	end
	local function fx(name, ...)
		local fn = FX and FX[name]
		return try("FX." .. name, fn, ...)
	end
	local function call(name, ...)
		return try("ctx." .. name, ctx[name], ...)
	end

	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end

	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	local function pick(v, i)
		if type(v) == "table" then
			return v[i] or v[#v]
		end
		return v
	end

	local function torsoOf(m)
		if typeof(m) ~= "Instance" or not m.Parent then
			return nil
		end
		if m:IsA("BasePart") then
			return m
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	end

	local modeCfg = nil
	local function cfgOf(mode)
		if not mode then
			return M1
		end
		if not modeCfg then
			modeCfg = {}
			for k, v in pairs(M1) do
				modeCfg[k] = v
			end
			for k, v in pairs(MODE_M1) do
				modeCfg[k] = v
			end
		end
		return modeCfg
	end

	-- the world point a stretched limb starts from (Shared.limbRoot: the shoulder / hip rig attachment)
	local LIMB_OFF = { R = Vector3.new(1, 0.5, 0), L = Vector3.new(-1, 0.5, 0), RL = Vector3.new(0.5, -1, 0), LL = Vector3.new(-0.5, -1, 0) }
	local function rootPos(char, limb, hrp)
		local cf = shared("limbRoot", char, limb)
		if typeof(cf) == "CFrame" then
			return cf.Position
		elseif typeof(cf) == "Vector3" then
			return cf
		end
		if hrp and hrp.Parent then
			return (hrp.CFrame * CFrame.new(LIMB_OFF[limb] or LIMB_OFF.R)).Position
		end
		return nil
	end

	-- distance gate for this cast: "full" | "lite" | nil (the local caster is always full)
	local function gateOf(isLocal, pos)
		if isLocal then
			return "full"
		end
		if type(ctx.gate) == "function" then
			local ok, g = pcall(ctx.gate, pos)
			if ok then
				return g
			end
		end
		local d = (type(ctx.camDist) == "function" and ctx.camDist(pos)) or 0
		return (d <= 160 and "full") or (d <= 260 and "lite") or nil
	end

	local function snd(id, parent, vol, speed)
		if type(ctx.sound) == "function" then
			try("sound", ctx.sound, id, parent, vol, speed)
		end
	end
	local function sndAt(id, pos, vol, speed)
		if type(ctx.soundAt) == "function" then
			try("soundAt", ctx.soundAt, id, pos, vol, speed)
		end
	end

	-- a beat at t seconds after the cast (skipped when the late joiner is long past it)
	local function at(cast, t, fn)
		local delay = t - (ctx.now() - cast.T0)
		if delay < -0.08 then
			return
		end
		task.delay(math.max(delay, 0), function()
			if not cast.dead then
				try("beat", fn)
			end
		end)
	end

	local function finish(cast)
		if cast.dead then
			return
		end
		cast.dead = true
		if casts[cast.key] == cast then
			casts[cast.key] = nil
		end
	end

	local function stopTrack(tr, fade)
		if tr and type(tr.stop) == "function" then
			pcall(tr.stop, tr, fade or 0.08)
		end
	end

	local function retract(cast, secs)
		local h = cast and cast.handle
		if type(h) == "table" and not h.dead and type(h.retract) == "function" then
			pcall(h.retract, h, secs)
		end
	end

	-- clips: swings 1-4 without the legs / Root while the caster is running (cached per clip)
	local LEGS = { Root = true, LeftHip = true, RightHip = true, LeftKnee = true, RightKnee = true, LeftAnkle = true, RightAnkle = true }
	local legless = {}
	local function clipFor(name, moving)
		local clips = ctx.Clips or {}
		local clip = clips[name]
		if type(clip) ~= "table" then
			return nil
		end
		if not moving then
			return clip
		end
		local c = legless[name]
		if c then
			return c
		end
		c = { length = clip.length, fadeIn = clip.fadeIn, fadeOut = clip.fadeOut, strikeAt = clip.strikeAt, keys = {} }
		for i, kf in ipairs(clip.keys or {}) do
			local pose = {}
			for j, v in pairs(kf.pose or {}) do
				if not LEGS[j] then
					pose[j] = v
				end
			end
			c.keys[i] = { t = kf.t, ease = kf.ease, pose = pose }
		end
		legless[name] = c
		return c
	end

	-- the world only, for the local caster's step ray
	local function worldRay(from, vec, char)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local list = { char }
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
		params.FilterDescendantsInstances = list
		return workspace:Raycast(from, vec, params)
	end

	local function groundBelow(pos, depth)
		local hit = FX and type(FX.groundHit) == "function" and try("groundHit", FX.groundHit, pos, depth or 12)
		return hit and hit.Position or nil, hit
	end

	---------------------------------------------------------------------------------------------------
	-- the fist's target: the homed body's torso (stopping HomeInset in front of it) while it stays within reach + 3
	-- of the shoulder, else the end of the aim line (re-read every frame, so it follows the body as he steps)
	local function aimFn(cast)
		local char, limb, aim, reach, hrp = cast.char, cast.limb, cast.aim, cast.reach, cast.hrp
		local tgt = cast.target
		local last = nil
		return function()
			local o = rootPos(char, limb, hrp)
			if not o then
				return last
			end
			local tp = tgt and torsoOf(tgt)
			if tp then
				local off = tp.Position - o
				local dist = off.Magnitude
				if dist > 0.5 and dist <= reach + 3 then
					last = tp.Position - off.Unit * math.min(HOME_INSET, dist * 0.5)
					return last
				end
			end
			last = o + aim * reach
			return last
		end
	end

	local function tipOf(cast)
		local h = cast.handle
		if type(h) == "table" and not h.dead and type(h.tip) == "function" then
			local ok, p = pcall(h.tip, h)
			if ok and typeof(p) == "Vector3" then
				return p
			end
		end
		return cast.aimAt and cast.aimAt() or nil
	end

	-- throw the limb
	local function throw(cast)
		local side = cast.limb:sub(1, 1)
		local isLeg = #cast.limb == 2
		local idx = cast.combo
		local c = cast.c
		local delay = cast.delay
		local out = math.max(cast.W - delay, 0.05)
		local into = math.max(0, (ctx.now() - cast.T0) - delay)
		local fs = tonumber(pick(c.FistScale, idx)) or 1.15
		local as = tonumber(pick(M1.ArmScale, idx)) or 1
		if cast.mode then
			as = M1.ModeArmScale or 1.7
		end
		cast.fistScale, cast.armScale = fs, as
		local fin = cast.finCfg
		local o = {
			t0 = os.clock() - into,
			out = out,
			hold = tonumber(pick(M1.Hold, idx)) or 0.05,
			back = tonumber(pick(M1.Back, idx)) or 0.16,
			fistScale = fs,
			armScale = as,
			overshoot = cast.final and 0.16 or nil,
			wobble = cast.final and 0.5 or nil,
			spiral = (cast.fin == "Rifle" and fin and fin.spiral) or nil,
			white = cast.mode or nil,
			trail = true,
			ghosts = cast.final or cast.mode or nil,
		}
		cast.handle = shared(isLeg and "stretchLeg" or "stretchArm", cast.char, side, cast.aimAt, o)
		local h = cast.handle
		if type(h) == "table" then
			perkTrail(cast.char, rawget(h, "trail"))
		end
	end

	-- the local caster's root motion (the scaffold already slows swings 1-4 on this echo)
	local function localMove(cast)
		local hrp, dir, char = cast.hrp, cast.dir, cast.char
		local W, idx = cast.W, cast.combo
		local step = tonumber(pick(M1.Step, idx)) or 0.6
		if cast.mode then
			step *= (M1.ModeStepMul or 1.35)
		end
		local vel = hrp.AssemblyLinearVelocity * FLATV
		local moving = vel.Magnitude > 3 and not cast.final
		local dur = math.max(W + 0.03, 0.08)
		if moving then
			step = math.max(step, vel.Magnitude * 0.5 * dur) -- keep a run flowing through the jab
		end
		local tp = cast.target and torsoOf(cast.target)
		if tp then
			local fd = ((tp.Position - hrp.Position) * FLATV).Magnitude
			step = math.min(step, math.max(fd - STOP_SHORT, 0))
		end
		local hit = worldRay(hrp.Position, dir * (step + WALL_PAD), char)
		if hit then
			step = math.max(0, ((hit.Position - hrp.Position) * FLATV).Magnitude - WALL_PAD)
		end
		local e0 = ctx.now() - cast.T0
		if cast.final and cast.fin ~= "Axe" then
			call("root", math.max(W + FINAL_ROOT - e0, 0.1), dir)
		end
		if cast.fin == "Axe" then
			-- the Battle Axe: hang in the air while the leg rises, then the heel drives him down after it
			local from = hrp.Position
			call("move", {
				char = char, t0 = cast.T0, dur = W + AXE_HANG, from = from, to = from + dir * step + UP * 0.5, face = dir,
				ease = { "Quad", "Out" }, exitVel = dir * 6 - UP * AXE_DROP,
			})
			return
		end
		if step > 0.12 then
			local from = hrp.Position
			call("move", {
				char = char, t0 = cast.T0, dur = dur, from = from, to = from + dir * step, face = dir,
				ease = { "Quad", "Out" }, exitVel = moving and vel * 0.6 or dir * 3,
			})
		end
	end

	---------------------------------------------------------------------------------------------------
	-- M1Swing { id, userId, t0, combo, limb, dir, aim, reach, hitAt, target, finisher, mode }
	H.M1Swing = function(d)
		local char = ctx.charOf(d.userId)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local combo = math.clamp(math.floor(tonumber(d.combo) or 1), 1, 5)
		local W = tonumber(d.hitAt) or 0.14
		local T0 = tonumber(d.t0) or ctx.now()
		local e0 = ctx.now() - T0
		if e0 > W + 0.5 then
			return -- a late joiner: the swing is over
		end
		local isLocal = ctx.player ~= nil and d.userId == ctx.player.UserId
		local g = gateOf(isLocal, hrp.Position)
		if not g then
			return
		end
		local key = keyOf(d)
		if casts[key] then
			finish(casts[key])
		end
		local look = hrp.CFrame.LookVector
		local dir = ctx.flat(typeof(d.dir) == "Vector3" and d.dir or look, look)
		local aim = (typeof(d.aim) == "Vector3" and d.aim.Magnitude > 1e-3) and d.aim.Unit or dir
		local mode = d.mode == true
		local c = cfgOf(mode)
		local final = combo >= 5 or d.finisher ~= nil
		local finName = final and (FIN_CLIP[d.finisher] and d.finisher or "Pistol") or nil
		local finCfg = finName and M1.Finishers and M1.Finishers[finName] or nil
		local limb = (d.limb == "L" or d.limb == "R" or d.limb == "LL" or d.limb == "RL") and d.limb
			or (finCfg and finCfg.limb) or pick(M1.Limb, combo) or "R"
		local reach = tonumber(d.reach) or tonumber(pick(c.Reach, combo)) or 11
		-- did the line stop on a wall? (no body, and shorter than the swing's full reach)
		local full = tonumber(pick(c.Reach, combo)) or reach
		if finCfg and finCfg.reach then
			local baseR = tonumber(pick(M1.Reach, 5)) or full
			full = finCfg.reach * (baseR > 0 and math.clamp(full / baseR, 1, 2) or 1)
		end
		local target = typeof(d.target) == "Instance" and d.target or nil
		local cast = {
			key = key, char = char, hrp = hrp, isLocal = isLocal, combo = combo, final = final, fin = finName,
			finCfg = finCfg, W = W, T0 = T0, dir = dir, aim = aim, reach = reach, limb = limb, mode = mode, c = c,
			target = target, wall = target == nil and finName ~= "Axe" and reach + 0.6 < full, gate = g,
			rich = isLocal or (ctx.camDist and ctx.camDist(hrp.Position) or 0) <= GATE_RICH,
			delay = tonumber(DELAY[combo]) or 0.02, hits = 0,
		}
		cast.aimAt = aimFn(cast)
		casts[key] = cast
		H._stats.casts += 1
		task.delay(math.max(W - e0, 0) + 2, function()
			finish(cast)
		end)

		-- the clip
		local moving = not final and (hrp.AssemblyLinearVelocity * FLATV).Magnitude > 3
		local clip = clipFor(final and FIN_CLIP[finName] or CLIP[combo], moving)
		stopTrack(lastTrack[char], 0.06)
		cast.track = clip and call("playClip", char, clip, math.max(e0, 0)) or nil
		lastTrack[char] = cast.track

		-- the local caster's root motion
		if isLocal then
			try("localMove", localMove, cast)
		end

		-- the limb flies
		at(cast, cast.delay, function()
			throw(cast)
			SfxBank.play(final and "SWING_HEAVY" or "SWING", hrp, final and 0.9 or 0.75, final and 1.05 or 1.15) -- (2026-11-12) shared swing pools (evened loudness, no repeats)
			if isLocal and final then
				call("speedLines", 0.3, 0.45, mode and SUN or WHITE)
			end
		end)
		-- the snap-back
		at(cast, W + (tonumber(pick(M1.Hold, combo)) or 0.05), function()
			snd("Hit2", hrp, 0.32, 1.3 + rng:NextNumber(-0.05, 0.05))
		end)
		if g ~= "full" then
			return
		end

		cast.folder = call("castFolder", "GomuM1_" .. key, 3)
		local f = cast.folder
		local ringCol = mode and SUN or RING

		-- 0.00 anticipation: streaks sucked into the shoulder (the finisher: a big gather and a glow); Gear 5 bounces
		at(cast, 0, function()
			local o = rootPos(char, limb, hrp) or hrp.Position
			if final then
				fx("streaks", f, o, { inward = 3.2, count = 14, color = mode and NIKA or WHOOSH, color2 = mode and SUN or PISTOL, life = 0.12, size = 0.35 })
				fx("glow", f, o + aim * 0.8, mode and 4 or 2.6, mode and SUN or PISTOL, 0.18, { brightness = 2.5 })
			else
				fx("streaks", f, o, { inward = 1.6, count = 5, color = WHOOSH, color2 = mode and SUN or WHITE, life = 0.08, size = 0.22 })
			end
			if mode then
				shared("boing", char, { amp = final and 1 or 0.6 })
			end
		end)
		-- the speed streak down the line while the limb is out
		at(cast, cast.delay + math.max(W - cast.delay, 0.05) * 0.35, function()
			local o = rootPos(char, limb, hrp)
			local tip = cast.aimAt()
			if o and tip then
				if has("whoosh") then
					shared("whoosh", f, o, tip, { color = mode and NIKA or WHOOSH, width = final and 1.4 or 0.7, life = final and 0.2 or 0.12 })
				else
					local v = tip - o
					if v.Magnitude > 1 then
						fx("streaks", f, o, { dir = v.Unit, spread = 4, count = final and 8 or 3, speed = { v.Magnitude * 6, v.Magnitude * 9 }, life = 0.12, size = 0.3, color = WHOOSH })
					end
				end
			end
		end)

		-- W: the fist lands
		at(cast, W, function()
			local tip = tipOf(cast)
			if not tip then
				return
			end
			local ring = final and (mode and 9 or 6) or (mode and 4.5 or 2.8)
			fx("ring", f, tip, aim, 0.4, ring, ringCol, final and 0.28 or 0.18, { brightness = 2 })
			fx("streaks", f, tip, {
				dir = aim, spread = 26, count = final and 16 or 5, speed = { 40, 90 }, life = 0.14, size = 0.28,
				color = mode and NIKA or WHOOSH, color2 = ringCol,
			})
			if cast.wall then
				shared("dust", f, tip, -aim * 8, { count = final and 10 or 4, color = DUST })
				shared("cracks", f, tip, final and 7 or 4, final and 4 or 2, nil, final and 1.6 or 0.8, { normal = -aim })
				sndAt("Hit", tip, 0.45, 0.85)
			end
			if combo == 4 and cast.rich then
				-- the whip's heel skims the street: a scuff of dust under it
				local gpos = groundBelow(tip, 6)
				if gpos then
					shared("dust", f, gpos, -dir * 6 + UP * 4, { count = 5, color = DUST })
				end
			end
			if not final then
				return
			end
			local big = mode and 1.6 or 1
			if finName == "Axe" then
				-- the street splits under the heel
				local gpos = groundBelow(tip, 10) or tip
				shared("shock", f, gpos, UP, { size = 16 * big, color = ringCol })
				shared("cracks", f, gpos, 9, 6 * big, nil, 1.8, { normal = UP })
				shared("dustRing", f, gpos, 4 * big, 12, 34, { color = DUST })
				if cast.rich then
					shared("rubble", f, gpos, 8, { dir = dir })
				end
				shared("impactStar", f, gpos + UP * 1.5, { size = 7 * big, color = mode and SUN or STAR })
				sndAt("HitHeavy", gpos, 0.95, 0.8)
				sndAt("Boom", gpos, 0.55, 1.15)
				if isLocal then
					call("shake", 0.9 * big, 0.35)
				end
				return
			end
			local axis = finName == "Rifle" and UP or aim
			shared("shock", f, tip, axis, { size = 11 * big, color = ringCol })
			shared("impactStar", f, tip, { size = 6 * big, color = mode and SUN or PISTOL })
			fx("light", f, tip, mode and SUN or PISTOL, 7, 24, 0.25)
			fx("streaks", f, tip, {
				dir = axis, spread = finName == "Rifle" and 18 or 34, count = 20, speed = { 60, 130 }, life = 0.2, size = 0.4,
				color = mode and NIKA or WHITE, color2 = mode and SUN or PISTOL,
			})
			sndAt("Cannon", tip, 0.8, finName == "Rifle" and 1.15 or 1)
			if isLocal then
				call("shake", 0.45 * big, 0.22)
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- M1Hit { id, userId, combo, model, pos, dir, final, finisher, mode }
	H.M1Hit = function(d)
		local pos = typeof(d.pos) == "Vector3" and d.pos or nil
		if not pos then
			return
		end
		local cast = casts[keyOf(d)]
		local isLocal = ctx.player ~= nil and d.userId == ctx.player.UserId
		local final = d.final == true
		local mode = d.mode == true
		local combo = math.clamp(math.floor(tonumber(d.combo) or 1), 1, 5)
		H._stats.hits += 1
		sndAt(final and "HitHeavy" or "Hit", pos, final and 0.9 or 0.6, (final and 0.95 or 1.05) + rng:NextNumber(-0.06, 0.06))
		local g = gateOf(isLocal, pos)
		if not g then
			return
		end
		local dir = typeof(d.dir) == "Vector3" and d.dir.Magnitude > 1e-3 and d.dir.Unit or (cast and cast.dir) or Vector3.zAxis
		local f = (cast and live(cast.folder) and cast.folder) or call("castFolder", "GomuM1Hit_" .. keyOf(d), 2)
		local big = mode and 1.6 or 1
		shared("impactStar", f, pos, { size = (final and 6.5 or 2.6) * big, color = mode and SUN or STAR })
		if g == "full" then
			fx("sparks", f, pos, {
				dir = dir, spread = 40, count = final and 18 or 7, speed = { 18, 48 }, size = 0.4, life = 0.35,
				color = mode and NIKA or STAR, color2 = mode and SUN or WHITE, brightness = 2.5,
			})
			shared("dust", f, pos, dir * (final and 18 or 9), { count = final and 8 or 3, color = DUST })
			if final then
				shared("shock", f, pos, dir, { size = 12 * big, color = mode and SUN or WHITE })
				fx("ring", f, pos, dir, 1, 10 * big, mode and SUN or VEST, 0.3, { brightness = 1.6 })
				fx("light", f, pos, mode and SUN or IMPACT, 6, 20, 0.25)
			end
		end
		if not cast or cast.dead then
			return
		end
		cast.hits += 1
		-- the fist squashes onto the body, then springs back
		local h = cast.handle
		if cast.hits == 1 and type(h) == "table" and not h.dead and type(h.setScale) == "function" then
			local fs, as = cast.fistScale or 1.15, cast.armScale or 1
			pcall(h.setScale, h, fs * 1.35, as * 1.1, 0.05)
			task.delay(0.07, function()
				if not h.dead then
					pcall(h.setScale, h, fs, as, 0.14)
				end
			end)
		end
		-- once per swing: the hit-stop on the caster's clip; the local caster's screen
		if cast.hits == 1 then
			if cast.track then
				call("freeze", cast.track, final and 0.07 or 0.035)
			end
			if isLocal then
				call("shake", (tonumber(pick(M1.Shake, combo)) or 0.2) * big, final and 0.3 or 0.12)
				if final then
					call("impact", { tint = mode and SUN or nil })
					call("speedLines", 0.35, 0.6, mode and SUN or WHITE)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- M1Cancel { id, userId }: the caster died / unequipped before the swing landed
	H.M1Cancel = function(d)
		local cast = casts[keyOf(d)]
		if not cast then
			return
		end
		retract(cast, 0.08)
		if cast.track and lastTrack[cast.char] == cast.track then
			stopTrack(cast.track, 0.1)
		end
		finish(cast)
	end

	H.__reset = function()
		for _, cast in pairs(casts) do
			retract(cast, 0.05)
			finish(cast)
		end
		table.clear(casts)
	end

	return H
end
