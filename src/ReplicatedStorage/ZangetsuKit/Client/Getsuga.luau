--!nocheck
-- ZangetsuKit.Client.Getsuga (owner: getsuga): Q, GETSUGA TENSHO 月牙天衝 (DESIGN.md section 6.4, CONTRACT.md 5 / 7.3).
-- require(this)(ctx) -> { GetsugaCast, GetsugaHit, GetsugaEnd, GetsugaCancel, __reset }.
-- Casts are keyed "userId#id". e = ctx.now() - t0; W = windup (0.80, the server's release = Clips.Getsuga strikeAt).
-- Tensa Zangetsu (payload mode = true) draws the black Getsuga: black (non-additive) cores, crimson additive edges,
-- red-black flames, a bigger moon and two crimson echoes. FLAIR pass beats (t after t0; [clip key]):
--   0.00  GRIP: callout, root, the view squeezes in and tilts up (lean FOV -7, pitch 4) and trembles; Swell + Hum; the
--         blade glow (0.2)
--   0.05-0.78 CHARGE: glow 0.2 -> 1, aura 20 -> 60; 0.10 rocks tear loose (a wider ring at 0.42), dust drawn IN;
--         inward streaks every 0.12 (0.10-0.70); collapsing tip rings 0.15 / 0.30 / 0.45 / 0.60; flame licks every
--         0.06 from 0.20; reiatsu POURS up the blade from 0.20 (streaks riding base -> tip); arcs crackle round the
--         blade every 0.09 from 0.30; Crackle 0.25, Sizzle 0.40
--   0.36  THE FLARE [0.42 OVERHEAD]: a sky-high column of reiatsu bursts up off the tip (FlareHeight 80, mode 95) with
--         flames streaming up it, pressure rings climbing it, a halo + bloom at its crown, a ground ring + a gust of
--         dust at his feet, Rise + Thunder; 0.48 the tremble (camera shiver, sparks off the tip)
--   0.70  COLLAPSE: the column is sucked back down into the blade: a collapsing ring + inward streaks at the tip, Zap
--   0.73  GATHER [COCK]: a glow + a camera-facing ring at the tip, Whoosh; 0.74 the blade trail; 0.765 / 0.785 ghosts
--   W     RELEASE [SWING, held 0.10 on every client]: Boom / Thunder / Whoosh / Cannon; the cut's slash arc (Shikai:
--         + a wider echo arc) and a flash down the blade; muzzle glows + a light; shock rings in three planes (out
--         along the aim W / +0.05 / +0.11, the plane of the cut, a chest-high halo) + a ground ring; a streak cone and a gout
--         of flame; rocks flung; the ground splits at his feet (cracks, a trench, a dust wall); caster: impact frame
--         (flash 0.16), shake + FOV kick, speed lines, vignette; others: a distance-scaled shake
--   W -> arrival THE WAVE: the moon (span = width * SpanMul, yawed 55 deg to the lens, its lower
--         tip skimming the ground), an echo moon EchoLag behind (mode: a second, smaller crimson echo), a flame wake hanging in the air behind it, distortion
--         rings every RingEvery studs, the ground split under the whole path (a trench every WakeEvery studs, slabs
--         torn up either side every SlabEvery), wake dust / licks / sparks every DustEvery, trench smoke wisps; each
--         station: rubble, a ring standing in the trench, HitHeavy
--   arrival THE DETONATION (a wall or full range): glows, a light, a burning shell, rings in three planes, radial
--         streaks + sparks, a flame burst, cracks + rubble + a dust ring where the ground is near, Boom + Thunder, a
--         rising smoke plume; the moons split (open air) or fade into the wall
--   AFTERMATH: the blade steams and its glow cools; arcs linger on the blade (W + 0.25 / 0.5 / 0.8); embers; a
--         residual ring; 1.48 CHIBURI [FLICK]: a flick arc + reiatsu droplets flung off the blade, a ting; 1.58 the
--         twirl ribbon; 1.90 [REST] a glint on the tip
-- GetsugaHit: a lingering diagonal slash line, two glows + a light flash, a camera-facing ring, reiatsu flames bursting
--   off the body, sparks + streaks along the wave, a comet trail; Hit2 + HitHeavy; caster tally + shake. Only the
--   first 2 bodies within 30 studs of the camera bloom full size.
-- GetsugaEnd: ends the wave if this client has not drawn the arrival yet; with no cast record it draws the detonation
--   alone. GetsugaCancel: the moons split, everything stops.
-- Gating (other casters): <= 160 studs everything; 160-250 no inward streaks / licks / pour / wake dust / slabs /
--   embers / ghosts; > 250 the moon's core, the flare's core beam, hit glows + sounds. A part governor skips optional
--   layers past PartBudget parts; the local caster's lens-facing rings and the moons' haze are drawn fainter.
return function(ctx)
	local H = {}

	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")

	local FX = ctx.FX
	local PALC = ctx.PAL or {}
	local CFG_ALL = ctx.CFG or {}
	local CFG = CFG_ALL.Getsuga or {}
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local BLACK = Color3.new(0, 0, 0)
	local UP = Vector3.yAxis
	local TAU = math.pi * 2
	local rng = Random.new()
	local NEON, PLASTIC = Enum.Material.Neon, Enum.Material.SmoothPlastic
	local BLOCK = Enum.PartType.Block
	local TEX = (FX and FX.TEX) or {}
	local C3 = Color3.fromRGB

	local P = {
		Core = PALC.Core or C3(240, 250, 255), Reiatsu = PALC.Reiatsu or C3(150, 215, 255),
		Ice = PALC.Ice or C3(80, 160, 255), Frost = PALC.Frost or C3(205, 235, 255),
		Black = PALC.Black or C3(14, 10, 14), Crimson = PALC.Crimson or C3(220, 20, 40),
		Ember = PALC.Ember or C3(255, 90, 60), Blood = PALC.Blood or C3(110, 0, 18), Smoke = PALC.Smoke or C3(36, 30, 34),
		Dust = PALC.Dust or C3(150, 140, 125),
	}

	local MCFG = (type(CFG_ALL.Mode) == "table" and type(CFG_ALL.Mode.Getsuga) == "table") and CFG_ALL.Mode.Getsuga or {}
	-- a tuning number for this cast (the mode's value first)
	local function tune(mode, key, default)
		local v = mode and MCFG[key] or nil
		if type(v) ~= "number" then
			v = CFG[key]
		end
		return type(v) == "number" and v or default
	end
	local W_DEFAULT = CFG.Windup or 0.80
	local ROOT_TIME = CFG.RootTime or 1.94
	local FREEZE = CFG.ReleaseFreeze or 0.10
	local GATE_FULL = CFG.GateFull or 160
	local GATE_MID = CFG.GateMid or 250
	local WAKE_EVERY = CFG.WakeEvery or 4
	local DUST_EVERY = CFG.DustEvery or 6
	local SLAB_EVERY = CFG.SlabEvery or 8
	local RING_EVERY = CFG.RingEvery or 12
	local SKIM = CFG.GroundSkim or 6
	local BUDGET = CFG.PartBudget or 360
	local FLARE_AT = CFG.FlareAt or 0.36
	local COLLAPSE_AT = CFG.CollapseAt or 0.70
	local FLICK_AT = 1.38 -- the chiburi flick key (Clips.Getsuga flickAt, clip time); the cast clock adds FREEZE
	local AFTER = 2.5 -- the aftermath runs to W + AFTER

	local casts = {} -- "userId#id" -> cast

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function report(tag, err)
		if warned[tag] then
			return
		end
		warned[tag] = true
		warn("[Zangetsu.Getsuga] " .. tostring(tag) .. ": " .. tostring(err))
	end

	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end

	-- a guarded Shared builder call (one broken builder never kills a beat; each failure warns once)
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

	-- a guarded method call on a handle a builder returned
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
				local fn = h.Destroy or h.destroy or h.stop
				if type(fn) == "function" then
					fn(h)
				end
			end)
		end
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

	local function nsk(list)
		local k = {}
		for i, v in ipairs(list) do
			k[i] = NumberSequenceKeypoint.new(v[1], v[2])
		end
		return NumberSequence.new(k)
	end
	local function cs(a, b)
		return ColorSequence.new(a, b or a)
	end

	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function dist(p)
		return (camPos() - p).Magnitude
	end
	local function segDist(a, b)
		local c = camPos()
		local ab = b - a
		local l2 = ab:Dot(ab)
		local t = l2 > 1e-6 and math.clamp((c - a):Dot(ab) / l2, 0, 1) or 0
		return (a + ab * t - c).Magnitude
	end
	local function camFacing(p)
		local d = camPos() - p
		return d.Magnitude > 1e-3 and d.Unit or UP
	end
	local function glowFor(pos, size)
		local S = ctx.S
		if S and type(S.glowFor) == "function" then
			local ok, v = pcall(S.glowFor, pos, size)
			if ok and type(v) == "number" then
				return v
			end
		end
		return size * math.clamp(dist(pos) / 30, 0.45, 1)
	end
	-- camera-facing rings shrink near the lens (no white-out)
	local function ringK(pos)
		return math.clamp(dist(pos) / 30, 0.45, 1)
	end

	local function yAlong(dir)
		if FX and FX.yAlong then
			return FX.yAlong(dir)
		end
		return CFrame.identity
	end

	local function groundHit(pos, depth)
		if FX and FX.groundHit then
			local ok, r = pcall(FX.groundHit, pos, depth)
			if ok then
				return r
			end
		end
		return nil
	end

	local function groundColor(hit)
		local S = ctx.S
		if hit and S and type(S.groundColor) == "function" then
			local ok, c = pcall(S.groundColor, hit)
			if ok and typeof(c) == "Color3" then
				return c
			end
		end
		return P.Dust
	end

	local function torsoOf(m)
		if typeof(m) ~= "Instance" or not m.Parent then
			return nil
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	end

	local function tween(inst, t, props, style, dir)
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end

	-- a sound riding an existing part (it follows it)
	local function snd(key, part, vol, pitch)
		if live(part) and type(ctx.sound) == "function" then
			local ok, s = pcall(ctx.sound, key, part, vol, pitch)
			return ok and s or nil
		end
	end
	-- a sound at a point: a short-lived anchor in the cast folder (no 8 s anchor per sound)
	local function sndAt(f, key, pos, vol, pitch, life)
		if not live(f) or not (FX and FX.anchor) then
			if type(ctx.soundAt) == "function" then
				pcall(ctx.soundAt, key, pos, vol, pitch)
			end
			return
		end
		local a = FX.anchor(f, pos, life or 3)
		a.Name = "GetsugaSound"
		return snd(key, a, vol, pitch)
	end

	-- the sword: world points along the blade (k = 0 base .. 1 tip), with fallbacks when it is missing
	local function swordOf(char)
		if not char or type(ctx.sword) ~= "function" then
			return nil
		end
		local ok, info = pcall(ctx.sword, char)
		return ok and type(info) == "table" and info or nil
	end
	local function attPos(a)
		if typeof(a) == "Instance" and a:IsA("Attachment") and a.Parent then
			return a.WorldPosition
		end
		return nil
	end
	local function bladeEnds(char)
		local info = swordOf(char)
		local b, t = info and attPos(info.base), info and attPos(info.tip)
		if b and t then
			return b, t, info
		end
		local h = char and char:FindFirstChild("RightHand")
		if h then
			return h.Position, h.Position + UP * 4.5, info
		end
		local r = char and char:FindFirstChild("HumanoidRootPart")
		local p = r and r.Position or Vector3.zero
		return p + UP * 2, p + UP * 6.5, info
	end
	local function bladeAt(char, k)
		local b, t = bladeEnds(char)
		return b:Lerp(t, k), (t - b).Magnitude > 1e-3 and (t - b).Unit or UP
	end
	local function bladePart(char)
		local info = swordOf(char)
		if info and live(info.blade) then
			return info.blade
		end
		return char and (char:FindFirstChild("RightHand") or char:FindFirstChild("HumanoidRootPart")) or nil
	end

	---------------------------------------------------------------------------------------------------
	-- pooled emitters: `hosts` invisible hosts each fire at most once per frame (a host moved and fired twice in one
	-- frame puts both bursts at its last position), so bursts queue and a per-frame pump drains them

	local function newPool(f, props, hosts)
		local pl = { hosts = {}, ems = {}, q = {} }
		if not live(f) or not FX then
			return pl
		end
		for i = 1, hosts or 1 do
			local h = FX.part("GetsugaPool", BLOCK, PLASTIC, WHITE, nil)
			h.Transparency = 1
			h.Size = Vector3.one * 0.2
			h.Parent = f
			local em = FX.emitter(h, props)
			em.EmissionDirection = Enum.NormalId.Top
			pl.hosts[i], pl.ems[i] = h, em
		end
		return pl
	end
	local function push(pl, pos, dir, n, speed)
		if pl and #pl.hosts > 0 and #pl.q < 64 then
			table.insert(pl.q, { pos, dir, n or 1, speed })
		end
	end
	local function pump(pl)
		if not pl then
			return
		end
		for i, h in ipairs(pl.hosts) do
			local item = table.remove(pl.q, 1)
			if not item then
				return
			end
			if h.Parent then
				local dir = item[2]
				h.CFrame = CFrame.new(item[1]) * ((typeof(dir) == "Vector3" and dir.Magnitude > 1e-3) and yAlong(dir.Unit) or CFrame.identity)
				if item[4] then
					local sp = item[4]
					pl.ems[i].Speed = NumberRange.new(sp * 0.8, sp * 1.2) -- spawn-time: only this burst takes it
				end
				pl.ems[i]:Emit(item[3])
			end
		end
	end

	-- ground dust (lit like the ground, never glowing)
	local function dustPool(f, color)
		return newPool(f, {
			Texture = TEX.smoke, Color = cs(color, color:Lerp(BLACK, 0.25)), LightEmission = 0, LightInfluence = 1,
			Size = nsk({ { 0, 3.2 }, { 0.35, 7.5 }, { 1, 10 } }), Transparency = nsk({ { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(8, 14), SpreadAngle = Vector2.new(18, 18),
			Drag = 1.6, Acceleration = Vector3.new(0, 3, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		}, 3)
	end
	-- flame licks along the trench (Shikai: additive blue-white; mode: dark smoke licks, never additive black)
	local function lickPool(f, mode)
		if mode then
			return newPool(f, {
				Texture = TEX.smoke, Color = cs(P.Smoke, P.Black), LightEmission = 0, LightInfluence = 0.3,
				Size = nsk({ { 0, 0.9 }, { 0.4, 2 }, { 1, 2.6 } }), Transparency = nsk({ { 0, 0.3 }, { 0.6, 0.55 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(14, 14),
				Acceleration = Vector3.new(0, 6, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
			}, 2)
		end
		local fire = ctx.S and type(ctx.S.TEX) == "table" and ctx.S.TEX.fire -- Shared's flame sheet; else a stretched glow
		return newPool(f, {
			Texture = fire or TEX.glow, Color = cs(P.Core, P.Reiatsu), LightEmission = 1,
			Squash = NumberSequence.new(fire and 0 or 1.5),
			Size = nsk({ { 0, 0.9 }, { 0.3, 1.4 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.2 }, { 0.6, 0.45 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(0, 10, 0), Brightness = 2, ZOffset = 0.3,
		}, 2)
	end
	-- sparks over the wake (Shikai: frost glints; mode: crimson, the additive half of a black flame)
	local function sparkPool(f, c0, c1)
		return newPool(f, {
			Texture = TEX.star, Color = cs(c0 or P.Ember, c1 or P.Crimson), LightEmission = 1,
			Size = nsk({ { 0, 0.45 }, { 1, 0 } }), Transparency = nsk({ { 0, 0 }, { 0.8, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(0, 8, 0), Drag = 1.5, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
			Brightness = 2,
		}, 2)
	end

	-- smoke wisps rising off a stretch of the trench for `secs` (one box emitter per stretch)
	local function wisps(cast, a, b, mode, secs)
		local f = cast.folder
		if not live(f) or not FX then
			return
		end
		local len = (b - a).Magnitude
		if len < 1 then
			return
		end
		local host = FX.part("GetsugaWisps", BLOCK, PLASTIC, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.new(2.2, 0.3, len)
		host.CFrame = CFrame.lookAt((a + b) / 2 + UP * 0.3, b + UP * 0.3)
		host.Parent = f
		local em = FX.emitter(host, {
			Texture = TEX.smoke, Color = mode and cs(P.Smoke, P.Black) or cs(P.Frost, C3(150, 160, 175)),
			LightEmission = mode and 0 or 0.15, LightInfluence = mode and 0.3 or 0.6,
			Size = nsk({ { 0, 0.8 }, { 0.4, 1.8 }, { 1, 2.6 } }), Transparency = nsk({ { 0, 0.6 }, { 0.5, 0.72 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.9, 1.4), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(15, 15),
			Acceleration = Vector3.new(0, 4, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
			Rate = math.clamp(len * 0.6, 6, 18),
		})
		task.delay(secs, function()
			if em.Parent then
				em.Rate = 0
			end
		end)
		Debris:AddItem(host, secs + 1.6)
	end

	-- the diagonal of the cut: the crescent's tip axis (up, rolled by `tilt` about the travel axis)
	-- the moon is a flat sheet: yawed 55 deg off the travel line so the caster's camera sees its face, not its edge
	local FACE_YAW = CFrame.Angles(0, math.rad(55), 0)

	local function cutAxis(flat, tilt)
		local right = flat:Cross(UP)
		local a = math.rad(-(tilt or -30))
		return (UP * math.cos(a) + right * math.sin(a)).Unit
	end

	-- an expanding ball that burns out (a0 = its starting transparency)
	local function shell(f, pos, r0, r1, color, life, mat, a0)
		if not live(f) or not FX then
			return
		end
		local b = FX.part("GetsugaShell", Enum.PartType.Ball, mat or NEON, color, nil)
		b.Size = Vector3.one * r0 * 2
		b.CFrame = CFrame.new(pos)
		b.Transparency = a0 or 0.2
		b.Parent = f
		tween(b, life, { Size = Vector3.one * r1 * 2, Transparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		Debris:AddItem(b, life + 0.1)
		return b
	end

	-- a flash of light down the blade (the glint of the cut)
	local function bladeFlash(f, char, color, life)
		local b, t = bladeEnds(char)
		local len = (t - b).Magnitude
		if not live(f) or not FX or len < 0.5 then
			return
		end
		local p = FX.part("GetsugaEdgeFlash", BLOCK, NEON, color, nil)
		p.Size = Vector3.new(0.22, 0.22, len + 0.6)
		p.CFrame = CFrame.lookAt((b + t) / 2, t)
		p.Parent = f
		tween(p, life, { Transparency = 1, Size = Vector3.new(0.04, 0.04, len + 1.4) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(p, life + 0.1)
		fx("glow", f, t, glowFor(t, 2.2), color, 0.14, { brightness = 3 })
	end

	-- reiatsu POURING up the blade: streaks riding base -> tip, re-laid along the blade every frame (:step(k))
	local function newPour(f, char, mode)
		local h = { dead = false }
		function h:step() end
		function h:Destroy()
			self.dead = true
		end
		if not live(f) or not FX then
			return h
		end
		local host = FX.part("GetsugaPour", BLOCK, PLASTIC, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.new(0.7, 3, 0.7)
		host.Parent = f
		local em = FX.emitter(host, {
			Texture = TEX.glow, Color = cs(mode and P.Ember or P.Core, mode and P.Crimson or P.Reiatsu), LightEmission = 1,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			EmissionDirection = Enum.NormalId.Top, Orientation = Enum.ParticleOrientation.VelocityParallel,
			Squash = NumberSequence.new(-2.4), Size = nsk({ { 0, 0.25 }, { 0.3, 0.45 }, { 1, 0 } }),
			Transparency = nsk({ { 0, 0.3 }, { 0.3, 0.05 }, { 1, 1 } }), Lifetime = NumberRange.new(0.18, 0.3),
			Speed = NumberRange.new(14, 24), SpreadAngle = Vector2.new(4, 4), Brightness = 2.5, Rate = 30, ZOffset = 0.4,
		})
		function h:step(k)
			if self.dead or not host.Parent then
				return
			end
			local b, t = bladeEnds(char)
			local d = t - b
			if d.Magnitude < 0.3 then
				return
			end
			host.Size = Vector3.new(0.7, d.Magnitude * 0.8, 0.7)
			host.CFrame = CFrame.new(b + d * 0.4) * yAlong(d.Unit)
			em.Rate = 30 + 50 * (tonumber(k) or 1)
		end
		function h:Destroy()
			if self.dead then
				return
			end
			self.dead = true
			em.Enabled = false
			Debris:AddItem(host, 0.4)
		end
		return h
	end

	-- THE FLARE: a sky-high column of reiatsu off the raised blade. It rides the tip every frame (:step()), shoots up in
	-- 0.14 s, is sucked back down into the blade by :collapse() (0.1 s) and then destroys itself. Black: a black core, a
	-- crimson rim, red-black flames (smoke + crimson licks, never additive black). tier 1: the core beam alone.
	local function newFlare(f, char, mode, height, tier, isLocal)
		local h = { parts = {}, ems = {}, born = os.clock(), dead = false, height = height }
		function h:step() end
		function h:collapse() end
		function h:Destroy()
			self.dead = true
		end
		if not live(f) or not FX then
			h.dead = true
			return h
		end
		local edge = mode and P.Crimson or P.Reiatsu
		local layers = { { "FlareCore", mode and PLASTIC or NEON, mode and P.Black or P.Core, mode and 1.3 or 0.9, mode and 0.05 or 0 } }
		if tier >= 2 then
			table.insert(layers, { "FlareRim", NEON, edge, mode and 2.1 or 2.2, mode and 0.3 or 0.45 })
			table.insert(layers, { "FlareHaze", Enum.Material.ForceField, edge, 4.6, isLocal and 0.78 or 0.62 })
		end
		for _, L in ipairs(layers) do
			local p = FX.part("Getsuga" .. L[1], Enum.PartType.Cylinder, L[2], L[3], nil)
			p.Transparency = L[5]
			p.Size = Vector3.new(0.1, L[4], L[4])
			p.Parent = f
			table.insert(h.parts, { p = p, w = L[4] })
		end
		if tier >= 2 then
			-- flames streaming up the column off a box host along it
			local host = FX.part("GetsugaFlareHost", BLOCK, PLASTIC, WHITE, nil)
			host.Transparency = 1
			host.Size = Vector3.new(2.4, 1, 2.4)
			host.Parent = f
			h.host = host
			local fire = ctx.S and type(ctx.S.TEX) == "table" and ctx.S.TEX.fire or TEX.glow
			local function em(props, rate)
				local common = {
					Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
					EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
					SpreadAngle = Vector2.new(8, 8), Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(30, 55), Drag = 0.5,
				}
				for k, v in pairs(common) do
					if props[k] == nil then
						props[k] = v
					end
				end
				table.insert(h.ems, { e = FX.emitter(host, props), rate = rate })
			end
			if mode then
				em({ Texture = TEX.smoke, Color = cs(P.Smoke, P.Black), LightEmission = 0, LightInfluence = 0.3,
					Size = nsk({ { 0, 1.4 }, { 0.5, 3 }, { 1, 4 } }), Transparency = nsk({ { 0, 0.35 }, { 0.6, 0.6 }, { 1, 1 } }) }, 26)
				em({ Texture = fire, Color = cs(P.Ember, P.Crimson), Brightness = 2.4,
					Size = nsk({ { 0, 1.2 }, { 0.4, 2.4 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.15 }, { 0.6, 0.4 }, { 1, 1 } }) }, 34)
			else
				em({ Texture = fire, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, P.Core), ColorSequenceKeypoint.new(0.4, P.Reiatsu),
					ColorSequenceKeypoint.new(1, P.Ice) }), Brightness = 2,
					Size = nsk({ { 0, 1.4 }, { 0.4, 2.8 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.2 }, { 0.6, 0.45 }, { 1, 1 } }) }, 48)
			end
			local l = Instance.new("PointLight")
			l.Color = edge
			l.Brightness = 3
			l.Range = 28
			l.Shadows = false
			l.Parent = host
			h.light = l
		end
		function h:step()
			if self.dead then
				return
			end
			if not (char and char.Parent) then
				self:Destroy()
				return
			end
			local t = os.clock() - self.born
			local hh = self.height * (1 - (1 - math.clamp(t / 0.14, 0, 1)) ^ 3)
			if self.collapsing then
				local kc = math.clamp((os.clock() - self.collapsing) / 0.1, 0, 1)
				if kc >= 1 then
					self:Destroy()
					return
				end
				hh *= 1 - kc ^ 0.7
			end
			hh = math.max(hh, 0.1)
			local tip = bladeAt(char, 1)
			local wob = 1 + 0.12 * math.sin(t * 38)
			local cf = CFrame.new(tip + UP * (hh / 2)) * CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis is X: stand it up
			for i, it in ipairs(self.parts) do
				local w = it.w * (i == 1 and 1 or wob)
				it.p.Size = Vector3.new(hh, w, w)
				it.p.CFrame = cf
			end
			if self.host then
				self.host.Size = Vector3.new(2.4, math.max(hh * 0.9, 0.2), 2.4)
				self.host.CFrame = CFrame.new(tip + UP * (hh * 0.45))
				for _, it in ipairs(self.ems) do
					it.e.Rate = self.collapsing and 0 or it.rate * math.clamp(hh / 40, 0.3, 1)
				end
			end
		end
		function h:collapse()
			if self.dead or self.collapsing then
				return
			end
			self.collapsing = os.clock()
			for _, it in ipairs(self.ems) do
				it.e.Rate = 0
			end
			if self.light then
				tween(self.light, 0.1, { Brightness = 0 })
			end
		end
		function h:Destroy()
			if self.dead then
				return
			end
			self.dead = true
			for _, it in ipairs(self.parts) do
				pcall(function()
					it.p:Destroy()
				end)
			end
			if self.host then
				for _, it in ipairs(self.ems) do
					it.e.Enabled = false
				end
				Debris:AddItem(self.host, 0.7) -- the last flames finish rising
			end
		end
		return h
	end

	-- the flame wake: flames shed behind the moon that hang in the air and rise (a burning corridor down the path)
	local function newWake(f, mode, span)
		local h = { dead = false, ems = {} }
		function h:place() end
		function h:Destroy()
			self.dead = true
		end
		if not live(f) or not FX then
			return h
		end
		local host = FX.part("GetsugaWake", BLOCK, PLASTIC, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.new(3, span * 0.55, 2)
		host.Parent = f
		local fire = ctx.S and type(ctx.S.TEX) == "table" and ctx.S.TEX.fire or TEX.glow
		local function em(props, rate)
			local common = {
				Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Speed = NumberRange.new(1, 4),
				Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-70, 70), Drag = 1,
			}
			for k, v in pairs(common) do
				if props[k] == nil then
					props[k] = v
				end
			end
			table.insert(h.ems, { e = FX.emitter(host, props), rate = rate, smoke = props.LightEmission == 0 })
		end
		if mode then
			em({ Texture = TEX.smoke, Color = cs(P.Smoke, P.Black), LightEmission = 0, LightInfluence = 0.3,
				Size = nsk({ { 0, 1.6 }, { 0.4, 3.2 }, { 1, 4.2 } }), Transparency = nsk({ { 0, 0.35 }, { 0.6, 0.6 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.7, 1.1), Acceleration = Vector3.new(0, 6, 0) }, 40)
			em({ Texture = fire, Color = cs(P.Ember, P.Crimson), Brightness = 2.2,
				Size = nsk({ { 0, 1.1 }, { 0.4, 2 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.2 }, { 0.6, 0.45 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.4, 0.7), Acceleration = Vector3.new(0, 9, 0) }, 50)
		else
			em({ Texture = fire, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, P.Core), ColorSequenceKeypoint.new(0.4, P.Reiatsu),
				ColorSequenceKeypoint.new(1, P.Ice) }), Brightness = 1.8,
				Size = nsk({ { 0, 1.3 }, { 0.4, 2.4 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.25 }, { 0.6, 0.5 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.45, 0.8), Acceleration = Vector3.new(0, 9, 0) }, 70)
		end
		function h:place(cf)
			if self.dead or not host.Parent then
				return
			end
			host.CFrame = cf
			local d = dist(cf.Position)
			local k = math.clamp(d / 30, 0.3, 1) -- thin it for a near / on-axis camera; dark smoke never at the lens
			for _, it in ipairs(self.ems) do
				it.e.Rate = (it.smoke and d < 14) and 0 or it.rate * k
			end
		end
		function h:Destroy()
			if self.dead then
				return
			end
			self.dead = true
			for _, it in ipairs(self.ems) do
				it.e.Enabled = false
			end
			Debris:AddItem(host, 1.2)
		end
		return h
	end

	-- a slab of the ground torn up beside the split: it bursts up tilted, hangs, then sinks back and fades
	local function slab(f, hit, flat, side, w)
		if not live(f) or not FX or not hit then
			return
		end
		local col, mat = P.Dust, Enum.Material.Slate
		local S = ctx.S
		if S and type(S.groundColor) == "function" then
			pcall(function()
				local c, m = S.groundColor(hit)
				if typeof(c) == "Color3" then
					col = c
				end
				if typeof(m) == "EnumItem" then
					mat = m
				end
			end)
		end
		local right = flat:Cross(UP)
		local sz = Vector3.new(rng:NextNumber(1.6, 2.6), rng:NextNumber(0.5, 0.8), rng:NextNumber(2.4, 3.6))
		local at = hit.Position + right * side * (w * 0.5 + sz.X * 0.45) + flat * rng:NextNumber(-1.5, 1.5)
		local frame = CFrame.lookAt(at, at + flat) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, -side * math.rad(rng:NextNumber(28, 46)))
		local p = FX.part("GetsugaSlab", BLOCK, PLASTIC, col:Lerp(BLACK, rng:NextNumber(0.05, 0.25)), nil)
		pcall(function()
			p.Material = mat
		end)
		p.Size = sz
		p.CFrame = frame - UP * 1.2
		p.Parent = f
		tween(p, 0.14, { CFrame = frame + UP * (sz.Y * 0.3) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.delay(1.4 + rng:NextNumber(0, 0.4), function()
			if p.Parent then
				tween(p, 0.6, { CFrame = frame - UP * 1.4, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		Debris:AddItem(p, 2.8)
	end

	---------------------------------------------------------------------------------------------------
	-- a cast's life

	local function partCount(cast)
		local now = os.clock()
		if cast.countAt and now - cast.countAt < 0.05 then
			return cast.count
		end
		local n = 0
		if live(cast.folder) then
			for _, x in ipairs(cast.folder:GetDescendants()) do
				if x:IsA("BasePart") then
					n += 1
				end
			end
		end
		for _, g in ipairs(cast.ghosts) do
			if live(g) then
				for _, x in ipairs(g:GetDescendants()) do
					if x:IsA("BasePart") then
						n += 1
					end
				end
			end
		end
		cast.count, cast.countAt = n, now
		return n
	end
	local function roomy(cast)
		return partCount(cast) < BUDGET
	end

	-- a beat at cast time T (skipped when long past, cancelled when the cast dies); errors warn once per beat name
	local function at(cast, e, T, name, fn)
		if T < e - 0.05 then
			return
		end
		task.delay(math.max(T - e, 0), function()
			if cast.dead then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				report("beat " .. name, err)
			end
		end)
	end

	local function endCast(cast)
		if cast.closed then
			return
		end
		cast.closed = true
		for _, c in ipairs(cast.conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		table.clear(cast.conns)
		for _, h in ipairs(cast.handles) do
			kill(h)
		end
		table.clear(cast.handles)
		for _, key in ipairs({ "rocks", "rocks2" }) do
			if cast[key] then
				hcall(cast[key], "drop")
				cast[key] = nil
			end
		end
		if casts[cast.key] == cast then
			casts[cast.key] = nil
		end
	end

	-- the crescent's exit: split in open air (two halves fly apart), fade into a wall; destroyed either way
	local function retireCrescent(c, flat, intoWall)
		if c == nil then
			return
		end
		if intoWall then
			hcall(c, "fade", 0.12)
		else
			hcall(c, "split", flat)
		end
		task.delay(0.6, function()
			kill(c)
		end)
	end

	-- THE DETONATION where the wave ends (a wall, or its full range); also drawn alone by GetsugaEnd for a client that
	-- never saw the cast
	local function detonate(f, cast, pos, flat, mode, tier, isLocal, wall, tilt)
		local hot = mode and P.Ember or P.Core
		local edge = mode and P.Crimson or P.Reiatsu
		local pale = mode and P.Crimson or P.Frost
		local p = wall and (pos + flat * 1.2) or pos
		local d = dist(p)
		local nk = math.clamp(d / 40, 0.45, 1) -- point-blank: the blast blooms small (no white-out)
		local near = d < 40
		fx("glow", f, p, glowFor(p, 12) * nk, hot, 0.35, { brightness = 2.6 })
		sndAt(f, "Boom", p, 0.8, wall and 1.1 or 0.95, 3)
		sndAt(f, "Thunder", p, 0.45, 1.25, 3)
		if tier >= 2 then
			fx("glow", f, p, glowFor(p, 22) * nk, edge, 0.6, { alpha = near and 0.65 or 0.4, brightness = 1.3 })
			fx("light", f, p - flat * 1.5, edge, 8, 40, 0.6)
			shell(f, p, 1, (mode and 8 or 7) * nk, hot, 0.35, NEON, near and 0.6 or 0.25)
			shell(f, p, 1.5, (mode and 13 or 11) * nk, edge, 0.55, Enum.Material.ForceField, near and 0.6 or 0.2)
			-- rings in three planes: facing back along the wave, flat on the ground, and in the plane of the cut
			fx("ring", f, p - flat * 0.5, -flat, 2, 24 * ringK(p) * nk, edge, 0.5, { alpha = (isLocal or near) and 0.6 or 0.25 })
			local g = groundHit(p + UP * 2, 14)
			local gp = g and g.Position or nil
			task.delay(0.05, function()
				if live(f) then
					fx("ring", f, (gp or p) + UP * 0.3, UP, 2, 30 * nk, pale, 0.6, { alpha = 0.3 })
				end
			end)
			task.delay(0.1, function()
				if live(f) then
					fx("ring", f, p, cutAxis(flat, tilt):Cross(flat), 2, 20 * nk, hot, 0.45, { alpha = 0.35 })
				end
			end)
			fx("streaks", f, p, { count = 44, color = hot, color2 = edge, speed = { 50, 120 }, size = 0.55, life = 0.4 })
			fx("sparks", f, p, { dir = wall and -flat or UP, spread = 80, count = 26, color = hot, color2 = pale, speed = { 25, 60 } })
			sh("reiatsuFlame", f, p, mode and { black = true, color = P.Smoke, color2 = P.Crimson, count = 16, height = 9, size = 2.2, spread = 40 }
				or { color = P.Core, color2 = P.Reiatsu, count = 16, height = 9, size = 2.2, spread = 40 })
			if gp then
				sh("cracks", f, gp, 8, 9, edge, 1.6, { black = mode })
				if tier >= 3 and (not cast or roomy(cast)) then
					fx("rubble", f, gp, { count = wall and 12 or 10, dir = wall and -flat or nil, out = { 12, 28 }, up = { 18, 40 } })
				end
				if cast and cast.dust then
					for i = 1, 8 do
						local a = (i / 8) * TAU
						local radial = Vector3.new(math.cos(a), 0, math.sin(a))
						push(cast.dust, gp + radial * 2 + UP * 0.6, radial * 14 + UP * 4, 2, 16)
					end
				elseif not cast then
					sh("dust", f, gp + UP * 0.6, UP * 6, { count = 3 })
				end
			end
			-- a smoke plume rising off the blast for a second
			if tier >= 3 and cast then
				wisps(cast, (gp or p) - flat * 2, (gp or p) + flat * 2, mode, 1.2)
			end
		end
		if isLocal and d < 120 then
			ctx.shake(0.55 * math.clamp(1 - d / 140, 0.25, 1), 0.35, 24)
		end
	end

	-- the wave arrives (the client's own clock, or GetsugaEnd if that comes first)
	local function arrive(cast)
		if cast.ended then
			return
		end
		cast.ended = true
		local f, flat = cast.folder, cast.flat
		retireCrescent(cast.cres, flat, cast.wall)
		retireCrescent(cast.cres2, flat, cast.wall)
		retireCrescent(cast.cres3, flat, cast.wall)
		cast.cres, cast.cres2, cast.cres3 = nil, nil, nil
		if cast.wake then
			kill(cast.wake)
			cast.wake = nil
		end
		if live(f) then
			detonate(f, cast, cast.endPt, flat, cast.mode, cast.tierW, cast.isLocal, cast.wall, cast.tilt)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- GetsugaCast (every client)

	H.GetsugaCast = function(d)
		if type(d) ~= "table" or typeof(d.origin) ~= "Vector3" or typeof(d.dir) ~= "Vector3" or type(d.t0) ~= "number" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			endCast(casts[key])
		end
		local char, caster = ctx.charOf(d.userId)
		if char and not char.Parent then
			char = nil
		end
		local isLocal = caster ~= nil and caster == ctx.player
		local e = ctx.now() - d.t0
		local W = tonumber(d.windup) or W_DEFAULT
		local speed = math.max(tonumber(d.speed) or CFG.Speed or 160, 1)
		local stop = math.max(tonumber(d.stop) or 0, 0)
		local flat = ctx.flat(d.dir, Vector3.new(0, 0, -1))
		local origin = d.origin
		local endPt = origin + flat * stop
		local tArrive = W + stop / speed
		local mode = d.mode == true
		local tilt = tonumber(d.tilt) or CFG.Tilt or -30
		local width = tonumber(d.width) or CFG.Width or 16
		if e > math.max(tArrive, W) + AFTER then
			return -- stale: the whole performance is over
		end

		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local form = char and type(ctx.form) == "function" and ctx.form(char) or nil
		local clip = ctx.Clips and ((form == "Bankai" and ctx.Clips.GetsugaBankai) or ctx.Clips.Getsuga)
		local track = nil
		if char and clip then
			local ok, tr = pcall(ctx.playClip, char, clip, math.max(e, 0))
			track = ok and tr or nil
		end

		local life = math.min(math.max(tArrive + 3.3, W + AFTER + 0.5) - math.max(e, 0), 8)
		local f = ctx.castFolder("Getsuga", life)
		local cast = {
			key = key, folder = f, isLocal = isLocal, dead = false, closed = false, ended = false, conns = {}, handles = {},
			ghosts = {}, track = track, d = d, mode = mode, flat = flat, origin = origin, endPt = endPt, W = W,
			speed = speed, stop = stop, tArrive = tArrive, wall = d.wall == true, tilt = tilt, width = width, nearHits = 0,
		}
		casts[key] = cast
		task.delay(life, function()
			endCast(cast)
		end)

		local function tierAt(dd)
			if isLocal or dd <= GATE_FULL then
				return 3
			elseif dd <= GATE_MID then
				return 2
			end
			return 1
		end
		local tierC = tierAt(dist(origin))
		cast.tierW = tierAt(segDist(origin, endPt))
		local tierW = cast.tierW

		-- colours: additive accents are never black
		local hot = mode and P.Ember or P.Core
		local edge = mode and P.Crimson or P.Reiatsu
		local pale = mode and P.Crimson or P.Frost
		local white = mode and P.Ember or WHITE

		local function feet()
			local p = (hrp and hrp.Parent) and hrp.Position or (origin - flat * 2.5)
			local g = groundHit(p, 8)
			return g and g.Position or (p - UP * 3.19), g
		end
		local function shoulder()
			local rua = char and char:FindFirstChild("RightUpperArm")
			local att = rua and rua:FindFirstChild("RightShoulderRigAttachment")
			if att then
				return att.WorldPosition
			end
			local p = (hrp and hrp.Parent) and hrp.Position or origin
			return p + UP * 1.3 + flat:Cross(UP) * 1
		end

		-- pooled dust in the ground's colour (charge ring, flare gust, release wall, wake, blast), wake licks + sparks
		local fp0, fg0 = feet()
		if tierC >= 2 or tierW >= 2 then
			cast.dust = dustPool(f, groundColor(fg0))
		end
		if tierW >= 3 then
			cast.licks = lickPool(f, mode)
			cast.sparks = mode and sparkPool(f) or sparkPool(f, P.Core, P.Frost)
		end

		-- this cast's numbers (the mode's first). The charge beats are timed for W = 0.80 (Clips.Getsuga strikeAt); a
		-- different windup stretches them to fit
		local q = W / 0.8
		local function ct(t)
			return t * q
		end
		local flareH = tune(mode, "FlareHeight", 80)
		local span = width * tune(mode, "SpanMul", 1.85)
		local depth = span * tune(mode, "DepthK", 0.25)
		local thick = tune(mode, "Thick", 1.8)
		local trenchW = tune(mode, "TrenchWidth", 3.2)
		local echoLag = tune(mode, "EchoLag", 0.07)
		local echoK = tune(mode, "EchoScale", 0.8)
		local flickT = ((clip and tonumber(clip.flickAt)) or FLICK_AT) + FREEZE
		local right = flat:Cross(UP)
		-- the moon floats so its lower tip skims the ground under him (Lift studs above it; < 0 drags it through, splitting
		-- the ground) at every size as it grows
		local g0 = groundHit(origin, 12)
		local clear = g0 and math.clamp(origin.Y - g0.Position.Y, 0, 12) or 3.5
		-- the echoes fan out behind the moon, each rolled ECHO_FAN degrees further, so the caster's view shows them apart
		local ECHO_FAN = -18
		local function dropOf(sp, roll)
			return sp * 0.5 * math.abs(math.cos(math.rad(roll)))
		end
		local tipDrop = dropOf(span, tilt)
		local liftCfg = tune(mode, "Lift", -0.4)
		local function liftAt(k, drop)
			return math.max((drop or tipDrop) * k - clear + liftCfg, 0)
		end
		local lift = liftAt(1)

		---------------------------------------------------------------------------------------------
		-- 0.00 GRIP
		if isLocal and char and char == ctx.player.Character then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title
			-- (the Getsuga / BlackGetsuga callout used to fire here; Q is not the ult, in or out of Tensa Zangetsu)
			local left = ROOT_TIME - math.max(e, 0)
			if left > 0.02 then
				ctx.root(left, flat)
			end
			if e < ct(0.5) then
				-- the view squeezes in and tilts up to the flare, holds, and lets go into the release
				ctx.lean({ fov = -7, pitch = 4, attack = math.max(ct(0.42) - math.max(e, 0), 0.05), hold = ct(0.28), release = 0.12 })
				ctx.shake(0.08, math.max(ct(0.8) - math.max(e, 0), 0.1), 30)
			end
		end
		if char and e < W then
			if e < 0.2 then
				snd("Swell", hrp, 0.7, 1.1)
				snd("Hum", hrp, 0.5, 0.9)
			end
			if tierC >= 2 then
				cast.glow = sh("bladeGlow", char, mode and { black = true, color = P.Black, color2 = P.Crimson } or { color = P.Core, color2 = P.Reiatsu })
				if cast.glow then
					table.insert(cast.handles, cast.glow)
					hcall(cast.glow, "set", 0.2)
				end
			end
		end

		---------------------------------------------------------------------------------------------
		-- 0.05 -> 0.78 CHARGE
		if char and tierC >= 2 and e < W then
			at(cast, e, ct(0.05), "aura", function()
				cast.aura = sh("aura", char, mode and { black = true, color = P.Black, color2 = P.Crimson, rate = 20 } or { color = P.Core, color2 = P.Reiatsu, rate = 20 })
				if cast.aura then
					table.insert(cast.handles, cast.aura)
				end
			end)
			at(cast, e, ct(0.10), "rocks", function()
				local fp = feet()
				if tierC >= 3 then
					cast.rocks = fx("liftRocks", f, fp, 7, 6)
				end
				if cast.dust then
					local off = rng:NextNumber(0, TAU)
					for i = 1, 8 do
						local a = off + (i / 8) * TAU
						local radial = Vector3.new(math.cos(a), 0, math.sin(a))
						push(cast.dust, fp + radial * 6 + UP * 0.5, -radial * 10 + UP * 2, 1, 10) -- rolling IN to his feet
					end
				end
			end)
			if tierC >= 3 then
				for T = 0.10, 0.71, 0.12 do
					at(cast, e, ct(T), "inward", function()
						fx("streaks", f, bladeAt(char, 0.5), { inward = 6 + 4 * T, color = hot, color2 = edge, count = 24, life = 0.32, size = 0.35 })
					end)
				end
				-- 0.20 the reiatsu starts pouring up the blade
				at(cast, e, ct(0.20), "pour", function()
					cast.pour = newPour(f, char, mode)
					table.insert(cast.handles, cast.pour)
				end)
				local T = 0.20
				while T <= 0.741 do
					local k = (T - 0.20) / 0.54
					at(cast, e, ct(T), "lick", function()
						fx("light", f, bladeAt(char, 0.7), edge, 1.5 + 2 * k, 10, 0.12)
						sh("reiatsuFlame", f, bladeAt(char, rng:NextNumber(0.15, 1)), mode
							and { black = true, color = P.Black, color2 = P.Crimson, count = 3, height = 2.5 + 2 * k, size = 1.1 }
							or { color = P.Core, color2 = P.Reiatsu, count = 3, height = 2.5 + 2 * k, size = 1.1 })
					end)
					T += 0.06
				end
			end
			for _, T in ipairs({ 0.15, 0.30, 0.45, 0.60 }) do
				at(cast, e, ct(T), "tipRing", function()
					local tip, dir = bladeAt(char, 1)
					fx("ring", f, tip, dir, 8 + 4 * T, 0.6, edge, 0.3, { ease = "in", alpha = 0.35 })
				end)
			end
			at(cast, e, ct(0.25), "crackle", function()
				snd("Crackle", bladePart(char), 0.5, 0.9)
			end)
			at(cast, e, ct(0.40), "sizzle", function()
				snd("Sizzle", bladePart(char), 0.4, 1.1)
			end)
			-- 0.36 THE FLARE: the column bursts up off the raised blade
			at(cast, e, ct(FLARE_AT), "flare", function()
				cast.flare = newFlare(f, char, mode, flareH, tierC, isLocal)
				table.insert(cast.handles, cast.flare)
				local tip = bladeAt(char, 1)
				local top = tip + UP * flareH
				local fp = feet()
				fx("glow", f, tip, glowFor(tip, 5), hot, 0.25, { brightness = 2.6 })
				fx("glow", f, top, glowFor(top, 14), edge, 0.7, { alpha = 0.3, brightness = 1.6 })
				fx("ring", f, top, UP, 3, 30, edge, 0.7, { alpha = 0.35 })
				fx("ring", f, fp + UP * 0.25, UP, 2, 22, pale, 0.5, { alpha = 0.3 })
				for i, hk in ipairs({ 0.2, 0.45, 0.7 }) do
					task.delay(0.04 * i, function()
						if not cast.dead and live(f) then
							fx("ring", f, tip + UP * (flareH * hk), UP, 1, 9 - 2 * hk, i == 2 and white or edge, 0.35, { alpha = 0.25 })
						end
					end)
				end
				fx("light", f, tip + UP * 4, edge, 5, 40, 0.5)
				if cast.dust then
					local off = rng:NextNumber(0, TAU)
					for i = 1, 8 do
						local a = off + (i / 8) * TAU
						local radial = Vector3.new(math.cos(a), 0, math.sin(a))
						push(cast.dust, fp + radial * 1.5 + UP * 0.4, radial * 18 + UP * 3, 1, 18) -- the pressure blows OUT
					end
				end
				snd("Rise", bladePart(char), 0.7, 0.8)
				snd("Thunder", hrp, 0.35, 1.6)
				if isLocal then
					ctx.shake(0.3, 0.3, 30)
				end
			end)
			-- 0.42 the blade is overhead: a second, wider ring of debris tears loose
			if tierC >= 3 then
				at(cast, e, ct(0.42), "rocks2", function()
					if roomy(cast) and not isLocal then -- (that ring would sweep rocks through the caster's own lens)
						cast.rocks2 = fx("liftRocks", f, feet(), 11, 5)
					end
				end)
			end
			-- 0.48 the tremble
			at(cast, e, ct(0.48), "tremble", function()
				if isLocal then
					ctx.shake(0.18, ct(0.22), 44)
				end
				local tip = bladeAt(char, 1)
				fx("sparks", f, tip, { dir = UP, spread = 50, count = 10, color = hot, color2 = edge, speed = { 10, 25 }, size = 0.4 })
			end)
			-- 0.70 COLLAPSE: the column is sucked back down into the blade
			at(cast, e, ct(COLLAPSE_AT), "collapse", function()
				if cast.flare then
					hcall(cast.flare, "collapse")
				end
				local tip = bladeAt(char, 1)
				fx("ring", f, tip, camFacing(tip), 7, 0.6, edge, 0.14, { ease = "in", alpha = isLocal and 0.5 or 0.25 })
				if tierC >= 3 then
					fx("streaks", f, tip, { inward = 7, color = hot, color2 = edge, count = 26, life = 0.12, size = 0.4 })
				end
				snd("Zap", bladePart(char), 0.5, 0.7)
			end)
			-- 0.73 GATHER [COCK]: the blade cocked behind his head
			at(cast, e, ct(0.73), "gather", function()
				local tip = bladeAt(char, 1)
				fx("glow", f, tip, glowFor(tip, 4.5), hot, 0.12, { brightness = 2.6 })
				fx("ring", f, tip, camFacing(tip), 1, 6 * ringK(tip), white, 0.2, { alpha = isLocal and 0.45 or 0 })
				snd("Whoosh", hrp, 0.8, 0.7)
			end)
			at(cast, e, ct(0.74), "trail", function()
				local tr = sh("bladeTrail", char, hot, edge, 0.22, 0.34, { black = mode, width = 1.2 })
				if tr then
					table.insert(cast.handles, tr)
				end
			end)
			if tierC >= 3 then
				for i, T in ipairs({ 0.765, 0.785 }) do
					at(cast, e, ct(T), "ghost", function()
						if not roomy(cast) then
							return
						end
						local g = sh("ghost", char, edge, i == 1 and 0.55 or 0.65, 0.24)
						if typeof(g) == "Instance" then
							table.insert(cast.ghosts, g)
						end
					end)
				end
			end
		elseif char and e < ct(0.73) then
			-- a far caster: the flare's core beam alone still marks the sky
			at(cast, e, ct(FLARE_AT), "flareFar", function()
				cast.flare = newFlare(f, char, mode, flareH, 1, false)
				table.insert(cast.handles, cast.flare)
			end)
			at(cast, e, ct(COLLAPSE_AT), "collapseFar", function()
				if cast.flare then
					hcall(cast.flare, "collapse")
				end
			end)
			at(cast, e, ct(0.73), "gatherFar", function()
				snd("Whoosh", hrp, 0.8, 0.7)
			end)
		end

		---------------------------------------------------------------------------------------------
		-- W RELEASE (the money frame)
		if e < W + 0.05 then
			at(cast, e, W, "release", function()
				if track then
					pcall(ctx.freeze, track, FREEZE) -- the cut hangs on every client
				end
				for _, key in ipairs({ "pour", "flare" }) do
					if cast[key] then
						kill(cast[key])
						cast[key] = nil
					end
				end
				local bp = char and bladePart(char)
				if bp then
					snd("Boom", bp, 0.9, 1.1)
				else
					sndAt(f, "Boom", origin, 0.9, 1.1)
				end
				local sp = (hrp and hrp.Parent) and hrp or nil
				if sp then
					snd("Thunder", sp, 0.6, 1.3)
					snd("Whoosh", sp, 1.0, 0.6)
					snd("Cannon", sp, 0.5, 0.9)
				else
					sndAt(f, "Thunder", origin, 0.6, 1.3)
				end
				-- the muzzle (core layer: every tier)
				fx("glow", f, origin, glowFor(origin, 6), hot, 0.15, { brightness = 3 })
				if tierC >= 2 then
					fx("glow", f, origin, glowFor(origin, 14), edge, 0.4, { alpha = isLocal and 0.5 or 0.3, brightness = 1.4 })
					fx("light", f, origin, edge, 7, 28, 0.4)
					if char then
						bladeFlash(f, char, mode and P.Ember or WHITE, 0.22) -- the edge flashes as it bites the air
					end
					-- the cut: a slash arc from up-right-back down across to low-left-front, centred on the shoulder, and a
					-- wider, fainter echo of it
					local sh0 = shoulder()
					local axis = cutAxis(flat, tilt)
					local xAxis = -axis
					local zAxis = -flat
					local yAxis = zAxis:Cross(xAxis)
					local arcCF = CFrame.fromMatrix(sh0, xAxis, yAxis, zAxis)
					sh("slashArc", f, arcCF, 7.5, {
						sweep = 150, width = 1.1, core = mode and P.Black or P.Core, edge = edge, draw = 0.05, life = 0.45,
						black = mode,
					})
					task.delay(0.03, function()
						if not cast.dead and not mode then -- (Shikai only: the mode's three moons spend those parts)
							sh("slashArc", f, arcCF, 9.5, { sweep = 130, width = 0.5, thick = 0.08, core = hot, edge = edge, draw = 0.05, life = 0.3, layers = 1 })
						end
					end)
					-- shock rings in three planes: stepping out along the aim (they face the caster's lens: faint for him),
					-- standing in the plane of the cut, and a chest-high halo; plus a ground ring
					fx("ring", f, origin, flat, 1, 14 * ringK(origin), pale, 0.4, { alpha = isLocal and 0.6 or 0.2 }) -- faces the caster's lens
					task.delay(0.05, function()
						if not cast.dead then
							local p = origin + flat * math.min(2, stop + 0.5)
							fx("ring", f, p, flat, 1, 10 * ringK(p), white, 0.3, { alpha = isLocal and 0.55 or 0 })
						end
					end)
					task.delay(0.11, function()
						if not cast.dead then
							local p = origin + flat * math.min(5, stop + 0.5)
							fx("ring", f, p, flat, 1, 18 * ringK(p), edge, 0.45, { alpha = isLocal and 0.65 or 0.4 })
						end
					end)
					fx("ring", f, origin + flat * 1.5, axis:Cross(flat), 1, 16, hot, 0.35, { alpha = 0.3 })
					local fp = feet()
					task.delay(0.04, function()
						if not cast.dead then
							fx("ring", f, fp + UP * 2.6, UP, 2, 20, edge, 0.4, { alpha = 0.4 })
						end
					end)
					fx("ring", f, fp + UP * 0.2, UP, 2, 18, pale, 0.4, { alpha = 0.3 })
					fx("streaks", f, origin, { dir = flat, spread = 25, color = hot, color2 = pale, count = 60, speed = { 140, 240 }, size = 0.6, life = 0.35 })
					-- a gout of flame thrown after the wave
					sh("reiatsuFlame", f, origin + flat * 1.5, mode
						and { black = true, color = P.Smoke, color2 = P.Crimson, count = 12, height = 7, size = 1.8, dir = (flat + UP * 0.3).Unit, spread = 25 }
						or { color = P.Core, color2 = P.Reiatsu, count = 12, height = 7, size = 1.8, dir = (flat + UP * 0.3).Unit, spread = 25 })
					for _, key in ipairs({ "rocks", "rocks2" }) do
						if cast[key] then
							hcall(cast[key], "drop", flat * 50 + UP * 8)
							cast[key] = nil
						end
					end
					if tierC >= 3 then
						-- the ground splits at his feet
						sh("cracks", f, fp + flat * 3, 7, 8, edge, 1.4, { black = mode })
						sh("trench", f, fp + flat * 0.5, fp + flat * 5, { width = trenchW * 1.2, seam = edge, life = 2.4, black = mode })
						if cast.dust then
							for i = 1, 4 do
								local k = (i - 1) / 3 - 0.5
								local p = fp + flat * 3 + right * (k * 8) + UP * 0.5
								push(cast.dust, p, flat * 50 + UP * 6, 2, 50)
							end
						end
					end
				end
				if cast.glow then
					hcall(cast.glow, "set", 0.55)
				end
				if cast.aura then
					hcall(cast.aura, "set", 10)
				end
				if isLocal then
					pcall(ctx.impact, {
						tint = mode and P.Crimson or P.Frost, tint2 = mode and P.Ember or P.Core, lineColor = pale, lineTime = 0.4,
						flash = mode and P.Crimson or P.Frost, flashAlpha = 0.16, flashLife = 0.2,
					})
					ctx.shake(0.9, 0.5, 24, 9)
					fx("speedLines", 0.45, { color = pale, alpha = 0.55, inner = 0.38 })
					if type(ctx.vignette) == "function" then
						pcall(ctx.vignette, 0.16, 0.5, mode and P.Crimson or P.Ice)
					end
				else
					local k = math.clamp(1 - dist(origin) / 200, 0, 1)
					if k > 0.02 then
						ctx.shake(0.7 * k, 0.4, 24)
					end
				end
			end)
		end

		---------------------------------------------------------------------------------------------
		-- the master loop: charge ramps, the pour + flare, the wave, the wake, stations, aftermath ramps, the pumps
		local stations = type(d.stations) == "table" and d.stations or {}
		local nextStation = 1
		while stations[nextStation] and type(stations[nextStation].t) == "number" and stations[nextStation].t < e - 0.1 do
			nextStation += 1 -- a late joiner skips the craters already past
		end
		local nextWake = WAKE_EVERY
		local nextDust = DUST_EVERY * 0.5
		local nextSlab = SLAB_EVERY * 0.75
		local nextRing = RING_EVERY
		local prevG = nil
		local chunkLen = math.max(stop / 3, 12)
		local nextChunk = chunkLen
		local chunkStart = origin
		local chunkGround = false
		local nextArc = ct(0.30)
		local waveStarted = false
		local loopEnd = math.max(tArrive, W) + AFTER + 0.1
		-- a moon's frame after s studs (lifted, yawed to the lens) and its growth over the first 14 studs
		local function moonCF(s, drop)
			local k = 0.5 + 0.5 * math.clamp(s / 14, 0, 1)
			local c = origin + flat * s + UP * liftAt(k, drop)
			return CFrame.lookAt(c, c + flat) * FACE_YAW, k
		end
		-- the caster's lens: the moons' haze is drawn fainter (no translucent sheet over his view)
		local function lensFaint(cres)
			if not isLocal or type(cres) ~= "table" or type(cres.items) ~= "table" then
				return
			end
			for _, it in ipairs(cres.items) do
				if typeof(it.p) == "Instance" and it.p.Name == "CresHaze" and type(it.base) == "number" then
					it.base = math.max(it.base, 0.8)
					it.p.Transparency = it.base
				end
			end
		end
		if e > tArrive then
			cast.ended = true -- a late joiner after the arrival: no wave
		end

		local conn
		conn = RunService.Heartbeat:Connect(function()
			local ok, err = pcall(function()
				if cast.dead or cast.closed then
					conn:Disconnect()
					return
				end
				local el = ctx.now() - d.t0

				-- charge ramps, the pour, crackling arcs, the flare
				if el < W + 0.02 then
					local k = math.clamp((el - ct(0.05)) / ct(0.71), 0, 1)
					if cast.glow then
						hcall(cast.glow, "set", 0.2 + 0.8 * k)
					end
					if cast.aura then
						hcall(cast.aura, "set", 20 + 40 * k)
					end
					if cast.pour then
						hcall(cast.pour, "step", k)
					end
					if char and tierC >= 2 and el >= nextArc and el <= ct(0.76) then
						nextArc = el + ct(0.09)
						fx("arcs", f, bladeAt(char, rng:NextNumber(0.35, 0.85)), 1.6 + 0.6 * k, {
							colors = mode and { P.Crimson, P.Ember } or { P.Frost, P.Reiatsu }, count = 1, width = 0.06,
						})
					end
				end
				if cast.flare then
					hcall(cast.flare, "step")
					if cast.flare and cast.flare.dead then
						cast.flare = nil
					end
				end

				-- THE WAVE
				if el >= W and not cast.ended then
					if not waveStarted then
						waveStarted = true
						cast.cres = sh("crescent", f, {
							span = span, depth = depth, thick = thick, tilt = tilt,
							core = mode and P.Black or P.Core, edge = edge, black = mode,
							flames = tierW >= 2, trails = tierW >= 2,
						})
						lensFaint(cast.cres)
						if tierW >= 2 then
							-- the echo moon EchoLag behind (mode: a second, smaller crimson echo behind that)
							cast.cres2 = sh("crescent", f, {
								span = span * echoK, depth = depth * echoK, thick = thick * 0.7, tilt = tilt + ECHO_FAN,
								core = mode and P.Crimson or P.Reiatsu, edge = mode and P.Ember or P.Ice, alpha = mode and 0.35 or 0.45,
								flames = false, trails = tierW >= 3,
							})
							lensFaint(cast.cres2)
							if mode and roomy(cast) then
								cast.cres3 = sh("crescent", f, {
									span = span * echoK * echoK, depth = depth * echoK * echoK, thick = thick * 0.55, tilt = tilt + ECHO_FAN * 2,
									core = P.Blood, edge = P.Crimson, alpha = 0.55, flames = false, trails = false,
								})
								lensFaint(cast.cres3)
							end
							cast.wake = newWake(f, mode, span)
							table.insert(cast.handles, cast.wake)
						end
						local host = cast.cres and cast.cres.host -- (the crescent carries its own PointLight)
						if live(host) then
							snd("Hum", host, 0.6, 1.4)
							snd("Whoosh", host, 0.5, 0.5)
						end
					end
					local s = math.clamp((el - W) * speed, 0, stop)
					local mcf, scale = moonCF(s)
					hcall(cast.cres, "place", mcf, scale)
					if cast.cres2 then
						local cf2, k2 = moonCF(math.clamp((el - W - echoLag) * speed, 0, stop), dropOf(span * echoK, tilt + ECHO_FAN))
						hcall(cast.cres2, "place", cf2, k2)
					end
					if cast.cres3 then
						local cf3, k3 = moonCF(math.clamp((el - W - echoLag * 2) * speed, 0, stop), dropOf(span * echoK * echoK, tilt + ECHO_FAN * 2))
						hcall(cast.cres3, "place", cf3, k3)
					end
					if cast.wake then
						local wc = origin + flat * math.max(s - 3, 0) + UP * lift
						hcall(cast.wake, "place", CFrame.lookAt(wc, wc + flat) * CFrame.Angles(0, 0, math.rad(tilt)))
					end
					-- distortion rings standing in the path (they face the caster's lens: faint for him)
					while nextRing <= s + 1e-3 and nextRing < stop - 2 do
						local p = origin + flat * nextRing + UP * lift
						if tierW >= 2 then
							fx("ring", f, p, flat, 2, math.min(span * 0.55, 16) * ringK(p), edge, 0.35, { alpha = isLocal and 0.75 or 0.45 })
						end
						nextRing += RING_EVERY
					end
					-- the ground splits under the whole path: trench pieces + torn-up slabs (several per frame is fine)
					while nextWake <= s + 1e-3 do
						local p = origin + flat * nextWake
						local g = groundHit(p, SKIM)
						if g then
							local gp = g.Position
							if prevG and tierW >= 2 and roomy(cast) then
								sh("trench", f, prevG, gp, { width = trenchW, seam = edge, life = 2.4, black = mode })
							end
							prevG = gp
							chunkGround = true
						else
							prevG = nil
						end
						nextWake += WAKE_EVERY
					end
					while nextSlab <= s + 1e-3 do
						if tierW >= 3 and roomy(cast) then
							local g = groundHit(origin + flat * nextSlab, SKIM)
							if g then
								slab(f, g, flat, 1, trenchW)
								slab(f, g, flat, -1, trenchW)
							end
						end
						nextSlab += SLAB_EVERY
					end
					while nextDust <= s + 1e-3 do
						local p = origin + flat * nextDust
						if tierW >= 3 then
							local g = groundHit(p, SKIM)
							if g then
								push(cast.dust, g.Position + UP * 0.5, -flat * 8 + UP * 10, 2, 12)
								push(cast.licks, g.Position + UP * 0.3, UP + flat * 0.15, 3, 6)
								push(cast.sparks, g.Position + UP * 0.5, UP + flat * 0.4, 4, 14)
							end
						end
						nextDust += DUST_EVERY
					end
					-- smoke wisps off each finished stretch of the trench
					while chunkStart and (nextChunk <= s + 1e-3 or s >= stop - 1e-3) do
						local stopAt = math.min(nextChunk, stop)
						local b = origin + flat * stopAt
						if tierW >= 3 and chunkGround then
							local ga = groundHit(chunkStart, SKIM)
							local gb = groundHit(b, SKIM)
							if ga and gb then
								wisps(cast, ga.Position, gb.Position, mode, 1.5)
							end
						end
						chunkGround = false
						chunkStart = b
						nextChunk += chunkLen
						if stopAt >= stop - 1e-3 then
							chunkStart = nil
						end
					end
					-- stations (server crater points), at their times
					while stations[nextStation] and (tonumber(stations[nextStation].t) or math.huge) <= el do
						local stn = stations[nextStation]
						local i = nextStation
						nextStation += 1
						local pos = stn.pos
						if typeof(pos) == "Vector3" then
							if tierW >= 2 then
								fx("ring", f, pos + UP * 2, flat, 2, 10 * ringK(pos + UP * 2), edge, 0.35, { alpha = 0.3 })
								if roomy(cast) then
									fx("rubble", f, pos, { count = 6, out = { 10, 20 }, up = { 20, 40 } })
								end
							end
							if tierW >= 3 then
								push(cast.dust, pos + UP * 0.5, UP * 12 + flat * 4, 2, 12)
							end
							sndAt(f, "HitHeavy", pos, 0.4, 0.9 + 0.05 * i, 2.5)
						end
					end
					if el >= tArrive then
						arrive(cast)
					end
				end

				-- aftermath ramps
				if el >= W + 0.1 then
					local k = math.clamp((el - W - 0.1) / 1.2, 0, 1)
					if cast.glow then
						if k >= 1 then
							hcall(cast.glow, "stop")
							cast.glow = nil
						else
							hcall(cast.glow, "set", 0.55 * (1 - k))
						end
					end
					if cast.steam then
						local ks = math.clamp((el - W - 0.1) / 1.6, 0, 1)
						if ks >= 1 then
							hcall(cast.steam, "stop")
							cast.steam = nil
						else
							hcall(cast.steam, "setRate", 18 * (1 - ks))
						end
					end
				end
				if cast.aura and el >= W + 0.4 then
					local ka = math.clamp((el - W - 0.4) / 0.8, 0, 1)
					if ka >= 1 then
						kill(cast.aura)
						cast.aura = nil
					else
						hcall(cast.aura, "set", 10 * (1 - ka))
					end
				end

				pump(cast.dust)
				pump(cast.licks)
				pump(cast.sparks)

				if el >= loopEnd then
					conn:Disconnect()
				end
			end)
			if not ok then
				report("loop", err)
				pcall(function()
					conn:Disconnect()
				end)
			end
		end)
		table.insert(cast.conns, conn)

		---------------------------------------------------------------------------------------------
		-- AFTERMATH beats
		if char and tierC >= 2 then
			at(cast, e, W + 0.1, "steam", function()
				if tierC < 3 then
					return
				end
				local h = sh("steam", bladePart(char), 18, { black = mode })
				if h then
					cast.steam = h
					table.insert(cast.handles, h)
				end
			end)
			at(cast, e, W + 0.4, "residual", function()
				local fp = feet()
				fx("ring", f, fp + UP * 0.2, UP, 2, 12, edge, 0.6, { alpha = 0.6 })
			end)
			if tierC >= 3 then
				for _, T in ipairs({ 0.3, 0.7, 1.1 }) do
					at(cast, e, W + T, "embers", function()
						fx("sparks", f, bladeAt(char, rng:NextNumber(0.3, 0.9)), {
							dir = UP, spread = 60, count = 6, color = edge, color2 = pale, speed = { 2, 6 },
							accel = Vector3.new(0, 4, 0), drag = 1.5, life = 1.1, size = 0.32,
						})
					end)
				end
			end
			at(cast, e, W + 0.5, "sizzle2", function()
				snd("Sizzle", bladePart(char), 0.35, 0.8)
			end)
			-- arcs linger, crawling on the blade
			if tierC >= 3 then
				for _, T in ipairs({ 0.25, 0.5, 0.8 }) do
					at(cast, e, W + T, "lingerArc", function()
						fx("arcs", f, bladeAt(char, rng:NextNumber(0.3, 0.9)), 1.2, {
							colors = mode and { P.Crimson, P.Ember } or { P.Frost, P.Reiatsu }, count = 1, width = 0.05,
						})
					end)
				end
			end
			-- CHIBURI [FLICK]: the blade is flicked clean: a flick arc, reiatsu droplets flung off it, a ting
			at(cast, e, flickT, "chiburi", function()
				if cast.glow then
					hcall(cast.glow, "stop")
					cast.glow = nil
				end
				local b, t = bladeEnds(char)
				local dir = (t - b).Magnitude > 1e-3 and (t - b).Unit or -UP
				local fling = dir * 0.4 + right * 0.8 - UP * 0.2
				fling = fling.Magnitude > 1e-3 and fling.Unit or right
				fx("sparks", f, t, {
					dir = fling, spread = 25, count = 12, color = hot, color2 = edge, speed = { 18, 34 },
					accel = Vector3.new(0, -45, 0), drag = 1, life = 0.6, size = 0.35,
				})
				if tierC >= 3 then
					local m = (right + flat * 0.35 - UP * 0.25).Unit
					local x = (-UP - m * (-UP):Dot(m)).Unit
					local z = -m
					sh("slashArc", f, CFrame.fromMatrix(shoulder(), x, z:Cross(x), z), 4.6, {
						sweep = 80, width = 0.35, thick = 0.06, core = hot, edge = edge, draw = 0.04, life = 0.22, layers = 1,
					})
				end
				snd("Whoosh", bladePart(char), 0.45, 1.7)
				snd("Shatter", bladePart(char), 0.12, 1.9)
			end)
			-- the twirl back onto the shoulder leaves a ribbon; REST lands with a glint on the tip
			at(cast, e, flickT + 0.1, "twirl", function()
				local tr = sh("bladeTrail", char, hot, edge, 0.14, 0.26, { black = mode, width = 0.6 })
				if tr then
					table.insert(cast.handles, tr)
				end
			end)
			at(cast, e, flickT + 0.42, "glint", function()
				local _, t = bladeEnds(char)
				fx("glow", f, t, glowFor(t, 1.8), hot, 0.18, { brightness = 3 })
				fx("sparks", f, t, { count = 4, color = hot, color2 = edge, speed = { 2, 5 }, accel = Vector3.zero, life = 0.4, size = 0.3 })
			end)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- GetsugaHit (every client): the wave passes through a body

	H.GetsugaHit = function(d)
		if type(d) ~= "table" then
			return
		end
		local tp = torsoOf(d.model)
		local pos = typeof(d.pos) == "Vector3" and d.pos or (tp and tp.Position)
		if not pos then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		local cast = casts[key]
		local mode = d.mode == true
		local flat = ctx.flat(typeof(d.dir) == "Vector3" and d.dir or (cast and cast.flat) or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
		local f = (cast and live(cast.folder)) and cast.folder or ctx.castFolder("GetsugaHit", 4)
		local dd = dist(pos)
		local tier = (dd <= GATE_FULL) and 3 or ((dd <= GATE_MID) and 2 or 1)
		local isMine = ctx.player and d.userId == ctx.player.UserId
		local hot = mode and P.Ember or P.Core
		local edge = mode and P.Crimson or P.Reiatsu
		local pale = mode and P.Crimson or P.Frost

		-- point-blank crowds: only the first 2 bodies near the lens bloom full size
		local scale = 1
		if dd < 30 then
			local n = 1
			if cast then
				cast.nearHits += 1
				n = cast.nearHits
			end
			if n > 2 then
				scale = 0.5
			end
		end

		fx("glow", f, pos, glowFor(pos, 6) * scale, hot, 0.16, { brightness = 2.4 })
		if tier >= 2 then
			fx("glow", f, pos, glowFor(pos, 11) * scale, edge, 0.4, { alpha = dd < 30 and 0.6 or 0.35, brightness = 1.3 })
			fx("light", f, pos, edge, 4, 18, 0.25)
			local axis = cutAxis(flat, (cast and cast.tilt) or CFG.Tilt or -30)
			-- the slash mark lingers on the body a beat before it fades
			sh("slashLine", f, pos + axis * 2.6 - flat * 0.6, pos - axis * 2.6 - flat * 0.6, {
				width = 0.2, core = mode and P.Black or WHITE, edge = edge, draw = 0, hold = 0.2, life = 0.5, black = mode,
			})
			fx("ring", f, pos, camFacing(pos), 1, 9 * scale * ringK(pos), pale, 0.3, { alpha = 0.2 })
			if scale >= 1 or not cast or roomy(cast) then
				-- reiatsu flames burst off the body
				sh("reiatsuFlame", f, pos, mode and { black = true, color = P.Smoke, color2 = P.Crimson, count = 8, height = 5, size = 1.5 }
					or { color = P.Core, color2 = P.Reiatsu, count = 8, height = 5, size = 1.5 })
			end
			fx("sparks", f, pos, { dir = flat, count = math.floor(14 * scale + 0.5), color = hot, color2 = pale, speed = { 30, 60 } })
			fx("streaks", f, pos, { dir = flat, spread = 20, count = math.floor(16 * scale + 0.5), color = hot, color2 = edge })
			if tp and FX and FX.trail then
				local ok, tr = pcall(FX.trail, tp, pale, 1.2, 0.25)
				if ok and typeof(tr) == "Instance" then
					local a0, a1 = tr.Attachment0, tr.Attachment1
					task.delay(0.5, function()
						if tr.Parent then
							tr.Enabled = false
						end
					end)
					Debris:AddItem(tr, 0.8)
					if a0 then
						Debris:AddItem(a0, 0.8)
					end
					if a1 then
						Debris:AddItem(a1, 0.8)
					end
				end
			end
		end
		if live(tp) then
			snd("Hit2", tp, 0.8, 1.0)
			snd("HitHeavy", tp, 0.5, 1.1)
		else
			sndAt(f, "Hit2", pos, 0.8, 1.0, 2)
		end
		if isMine then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the "×n" hit tally
			-- under the title card is no longer bumped here)
			ctx.shake(0.25, 0.12, 30)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- GetsugaEnd (every client): the server's arrival

	H.GetsugaEnd = function(d)
		if type(d) ~= "table" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		local cast = casts[key]
		if cast then
			if not cast.ended and not cast.dead then
				arrive(cast)
			end
			return
		end
		-- no record of the cast (joined mid-flight): the end burst alone
		local pos = typeof(d.pos) == "Vector3" and d.pos or nil
		if not pos then
			return
		end
		local dd = dist(pos)
		local tier = (dd <= GATE_FULL) and 3 or ((dd <= GATE_MID) and 2 or 1)
		local flat = ctx.flat(typeof(d.dir) == "Vector3" and d.dir or (camFacing(pos) * -1), Vector3.new(0, 0, -1))
		local f = ctx.castFolder("GetsugaEnd", 4)
		detonate(f, nil, pos, flat, d.mode == true, tier, false, d.wall == true, CFG.Tilt or -30)
	end

	---------------------------------------------------------------------------------------------------
	-- GetsugaCancel (every client): the caster went invalid; the crescent breaks up, everything stops

	H.GetsugaCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		local cast = casts[key]
		if not cast then
			return
		end
		cast.dead = true
		retireCrescent(cast.cres, cast.flat, false)
		retireCrescent(cast.cres2, cast.flat, false)
		retireCrescent(cast.cres3, cast.flat, false)
		cast.cres, cast.cres2, cast.cres3 = nil, nil, nil
		if cast.glow then
			hcall(cast.glow, "stop")
		end
		if cast.track then
			pcall(function()
				cast.track:stop(0.2)
			end)
		end
		if cast.isLocal then
			pcall(ctx.unroot)
		end
		endCast(cast)
	end

	---------------------------------------------------------------------------------------------------
	-- the local character died / the kit was unequipped: end the local caster's casts and their leftovers

	H.__reset = function()
		for _, c in pairs(casts) do
			if c.isLocal then
				c.dead = true
				kill(c.cres)
				kill(c.cres2)
				kill(c.cres3)
				c.cres, c.cres2, c.cres3 = nil, nil, nil
				endCast(c)
				if live(c.folder) then
					c.folder:Destroy()
				end
				for _, g in ipairs(c.ghosts) do
					kill(g)
				end
			end
		end
	end

	return H
end
