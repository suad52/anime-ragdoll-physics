--!nocheck
-- OneForAllKit.Client.AirForce: Q, DELAWARE SMASH: AIR FORCE (design_A §5) - the flair pass.
-- require(this)(ctx) -> handler table. Broadcast kinds (unchanged):
--   AirForceCast { id, userId, t0, origin, dir, stop, windup, speed, wall, target, mode }
--   AirForceHit  { id, userId, pos, model, dir, mode }
-- Timing comes from Config.AirForce (Config.Flair_AirForce): W = Windup 0.36 is the flick, when the server fires the
-- bullet. The pose is Clips.AirForce (Clips.Flair_AirForce): DRAW 0.07, AIM 0.17, STRAIN 0.20-0.31, COCK 0.345,
-- FLICK 0.372, HOLD 0.50-0.60, SHAKE 0.68-0.85 (three flaps), SETTLE 0.92, REST 1.04. Its aim keys are bent to the
-- cast's aim pitch (5 degree buckets, cached).
-- Beats (t = 0 at cast):
--   0.00   callout + root (caster); the view squeezes in (lean FOV -5) and trembles; dust rolls IN to his feet;
--          crackle + a rising swell on the hand
--   0.06-W energy pools at the fingertip: a growing green orb with a light, a stream of streaks sucked into it,
--          converging bolts every 0.045 s; air rings collapse into the finger at 0.10 / 0.17 / 0.24 / 0.30
--   0.10   veins of light crawl up the arm (green; crimson in Full Cowl 100%) and arcs crackle along it; 0.12 zap,
--          0.24 sizzle
--   W      FLICK: the pose hit-stops 0.07 s on every client; the orb pops; core + green glows and a light; the sonic
--          boom = rings in three planes at W, +0.02, +0.045, +0.08 stepping out along the aim, a Mach cone of 10
--          slats, a ForceField pop, streaks forward + back-blast, sparks; 3 afterimages of the arm along the snap and
--          a body echo; dust blown off the ground ahead and round his feet; caster camera kick (shake + FOV +6),
--          speed lines, vignette; cannon pop + crack + whoosh
--   W-hit  the bullet: a white core in an air shell inside a spinning ForceField bubble, a light, two trails, a
--          3-strand helix, a tunnel of spiralling rings every 5 studs, wake turbulence + wind streaks every 1.6 studs,
--          crackling arcs, ground dust and a pebble scour under it. It leaves the real fingertip and settles onto
--          the server's line within 9 studs, homes onto the target's live torso, and leaves a fading tracer line
--   hit    (AirForceHit, every client; past 400 studs only its core flash): glows + light, rings in three planes
--          (shrunk x0.6-1 when the camera is within 30 studs: they face the shooter) over 0.12 s plus a slow
--          residual ring, a ForceField air pop, streak cone + radial burst, arcs at 0 / 0.08 / 0.16, sparks +
--          embers, a cloud of displaced air, a ground ring + dust + rubble under the body, comet trail + lightning on
--          the body; the caster's pose hit-stops 0.05; caster impact frame (flash 0.15) + shake + tally
--   wall   (no body, a wall) rings off the wall, chips of the wall's own material, ground rubble, dust, streaks,
--          sparks, arcs; (open air) a double air pop
--   after  W+0.04-1.4 the finger smokes (steam, a puff on each flap), embers rise, arcs linger on the arm, the veins
--          fade (W+0.4, 1.0 s), sizzle; the dust settles over ~2 s
-- Gating (other casters): <= 160 studs everything, <= 220 no veins / ghosts / dust / rubble, <= 250 core only (the
-- bullet's head + trails, the flick's core glow); the hit layer to 400. A camera on the shot's axis (the caster) gets
-- a thin wake (every 4.8 studs from 10 studs out, fainter): end-on, every puff would stack on the crosshair.
-- Timing (verified against OneForAllServer.castAirForce): the server fires at Windup and strikes at Windup +
-- stop / Speed, the same t0-relative times this module draws on; Lock 1.15 / RootTime 1.15 cover the clip to REST.
return function(ctx)
	local H = {}

	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local Players = game:GetService("Players")

	local FX, S, PAL, SND = ctx.FX, ctx.S, ctx.PAL, ctx.SND
	local CFG = (ctx.CFG and ctx.CFG.AirForce) or {}
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local BLACK = Color3.new(0, 0, 0)
	local UP = Vector3.yAxis
	local TAU = math.pi * 2
	local rng = Random.new()
	local NEON, FIELD, PLASTIC = Enum.Material.Neon, Enum.Material.ForceField, Enum.Material.SmoothPlastic
	local BALL, BLOCK = Enum.PartType.Ball, Enum.PartType.Block
	local TEX = FX.TEX or {}

	local GATE_FULL = CFG.GateFull or 160
	local GATE_MID = CFG.GateMid or 220
	local GATE_CORE = CFG.Gate or 250
	local OTHER_SHAKE = 90
	local ROOT_TIME = CFG.RootTime or 1.15
	local HITSTOP = CFG.HitStop or 0.07
	local HIT_FREEZE = CFG.HitFreeze or 0.05
	local CONVERGE = CFG.ConvergeDist or 9
	local ESCAPE = CFG.Escape or 13
	local HIT_FAR = CFG.HitGate or 400 -- someone else's hit further than this: only its core glow + light
	-- the chest is twisted ~33 degrees and leaning, so a shoulder bend reaches the arm at ~0.85: over-bend to aim true
	local AIM_GAIN = 1.15
	local RING_EVERY = 5
	local WAKE_EVERY = 1.6
	local DUST_EVERY = 4
	local SCOUR_EVERY = 9

	local casts = {} -- "userId:id" -> cast { folder, isLocal, dead, conns, handles, track, ... }
	local hits = {} -- "userId:id" -> true once that cast's AirForceHit arrived (so no air pop is drawn over a hit)

	---------------------------------------------------------------------------------------------------
	-- small helpers

	local function report(err)
		warn("[OneForAll.AirForce] " .. tostring(err))
	end

	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end

	local function kill(h)
		if h == nil then
			return
		end
		pcall(function()
			if typeof(h) == "Instance" then
				h:Destroy()
			elseif type(h) == "table" then
				local fn = h.destroy or h.Destroy or h.stop
				if type(fn) == "function" then
					fn(h)
				end
			end
		end)
	end

	local function cs(a, b)
		if typeof(a) == "ColorSequence" then
			return a
		end
		return ColorSequence.new(a, b or a)
	end

	local function nsk(list)
		local kp = {}
		for _, p in ipairs(list) do
			table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2]))
		end
		return NumberSequence.new(kp)
	end

	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end

	local function dist(p)
		return (camPos() - p).Magnitude
	end

	-- distance from the camera to the segment a..b (the bullet's whole flight line)
	local function segDist(a, b)
		local c = camPos()
		local ab = b - a
		local l2 = ab:Dot(ab)
		local t = l2 > 1e-6 and math.clamp((c - a):Dot(ab) / l2, 0, 1) or 0
		return (a + ab * t - c).Magnitude
	end

	local function glowFor(pos, size)
		if S and type(S.glowFor) == "function" then
			return S.glowFor(pos, size)
		end
		return size * math.clamp(dist(pos) / 30, 0.45, 1)
	end

	-- two unit vectors perpendicular to dir and to each other
	local function perp(dir)
		local r = dir:Cross(math.abs(dir.Y) > 0.95 and Vector3.xAxis or UP)
		r = r.Magnitude > 1e-4 and r.Unit or Vector3.xAxis
		return r, r:Cross(dir).Unit
	end

	-- a rotation-only CFrame whose +Y runs along dir (an emitter firing Top then fires along dir)
	local function yAlong(dir)
		if FX.yAlong then
			return FX.yAlong(dir)
		end
		local r, u = perp(dir)
		return CFrame.fromMatrix(Vector3.zero, r, dir, u)
	end

	local function torsoOf(m)
		if typeof(m) ~= "Instance" or not m.Parent then
			return nil
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	end

	local function mk(name, shape, mat, color, size, cf, parent, alpha)
		local p = FX.part(name, shape, mat, color, nil)
		p.Size = size
		p.CFrame = cf
		p.Transparency = alpha or 0
		p.Parent = parent
		return p
	end

	local function tween(inst, t, props, style, dir)
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end

	-- a sound on a part (it follows the hand), or at a point when the part is gone
	local function snd(id, part, pos, vol, pitch)
		if live(part) then
			return ctx.sound(id, part, vol, pitch)
		elseif typeof(pos) == "Vector3" then
			return ctx.soundAt(id, pos, vol, pitch)
		end
	end

	local function pick(list)
		return list[rng:NextInteger(1, #list)]
	end

	-- the ground (or a wall) without characters, NPCs or effects in the way
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	local function rayWorld(from, vec)
		local list = {}
		for _, n in ipairs({ "LocalFX", "NPCs", "FX", "KitFX", "KitDebris" }) do
			local f = workspace:FindFirstChild(n)
			if f then
				table.insert(list, f)
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(list, p.Character)
			end
		end
		castParams.FilterDescendantsInstances = list
		return workspace:Raycast(from, vec, castParams)
	end

	local function groundColor(hit)
		if S and type(S.groundColor) == "function" then
			return S.groundColor(hit)
		end
		return Color3.fromRGB(110, 104, 98), Enum.Material.Slate
	end

	---------------------------------------------------------------------------------------------------
	-- builders (local to this move)

	-- a pooled one-shot emitter on a tiny host that is moved before each Emit, so one emitter draws a whole path
	local function pool(f, props)
		local host = FX.part("AirForcePool", BLOCK, PLASTIC, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.one * 0.2
		host.Parent = f
		local e = FX.emitter(host, props)
		e.EmissionDirection = Enum.NormalId.Top
		return { host = host, e = e }
	end
	local function emitAt(pl, pos, dir, n)
		if not pl or not pl.host.Parent then
			return
		end
		pl.host.CFrame = CFrame.new(pos) * ((dir and dir.Magnitude > 1e-3) and yAlong(dir.Unit) or CFrame.identity)
		pl.e:Emit(n or 1)
	end
	local function retire(pl, after)
		if pl and pl.host then
			Debris:AddItem(pl.host, after)
		end
	end

	-- the air ring tunnel (VelocityPerpendicular rings, each lies across its emit direction)
	local function ringPool(f, color, color2, size, life, alpha)
		return pool(f, {
			Texture = TEX.ring, Color = cs(color, color2), Lifetime = NumberRange.new(life * 0.85, life), Speed = NumberRange.new(0.01),
			SpreadAngle = Vector2.zero, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = nsk({ { 0, size * 0.16 }, { 0.15, size * 0.62 }, { 0.45, size * 0.86 }, { 1, size } }),
			Transparency = nsk({ { 0, alpha }, { 0.5, alpha + (1 - alpha) * 0.4 }, { 1, 1 } }),
			Brightness = 1.8, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-140, 140),
		})
	end
	-- wake turbulence behind the bullet. `faint` for a camera looking down the line (the caster): seen end-on the
	-- puffs all stack on the crosshair, so that view gets thin, barely-glowing ones
	local function wakePool(f, faint)
		return pool(f, {
			Texture = TEX.smoke, Color = cs(PAL.Air, PAL.Steam), LightEmission = faint and 0.12 or 0.35, LightInfluence = 0.4,
			Size = nsk({ { 0, 0.9 }, { 0.3, 2.2 }, { 1, 3.3 } }),
			Transparency = faint and nsk({ { 0, 0.8 }, { 0.4, 0.88 }, { 1, 1 } }) or nsk({ { 0, 0.6 }, { 0.4, 0.74 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.85), Speed = NumberRange.new(2, 7), SpreadAngle = Vector2.new(180, 180),
			Drag = 3, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), ZOffset = -0.5,
		})
	end
	-- wind shearing off the bullet (thin stretched streaks)
	local function windPool(f)
		return pool(f, {
			Texture = TEX.glow, Color = cs(WHITE, PAL.Air), Orientation = Enum.ParticleOrientation.VelocityParallel,
			Squash = NumberSequence.new(-2.4), Size = nsk({ { 0, 0.18 }, { 0.2, 0.34 }, { 1, 0 } }),
			Transparency = nsk({ { 0, 0.15 }, { 0.7, 0.4 }, { 1, 1 } }), Lifetime = NumberRange.new(0.18, 0.3),
			Speed = NumberRange.new(25, 60), SpreadAngle = Vector2.new(28, 28), Brightness = 2.2, Drag = 2,
		})
	end
	-- ground dust (lit like the ground, not glowing)
	local function dustPool(f, color)
		color = color or Color3.fromRGB(150, 140, 125)
		return pool(f, {
			Texture = TEX.smoke, Color = cs(color, color:Lerp(BLACK, 0.25)), LightEmission = 0, LightInfluence = 1,
			Size = nsk({ { 0, 1 }, { 0.35, 3.2 }, { 1, 4.6 } }), Transparency = nsk({ { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.1, 1.9), Speed = NumberRange.new(9, 16), SpreadAngle = Vector2.new(30, 30),
			Drag = 2.2, Acceleration = Vector3.new(0, 2.5, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		})
	end
	local function emitDust(pl, pos, vel, n)
		if not pl or not pl.host.Parent then
			return
		end
		local sp = vel.Magnitude
		pl.e.Speed = NumberRange.new(sp * 0.75, sp * 1.2) -- spawn-time property: only these puffs take it
		emitAt(pl, pos, vel, n)
	end
	-- a ring of dust puffs rolling outward (speed > 0) or inward (speed < 0) round a ground point
	local function dustRing(pl, center, radius, n, speed)
		local off = rng:NextNumber(0, TAU)
		for i = 1, n do
			local a = off + (i / n) * TAU + rng:NextNumber(-0.15, 0.15)
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			emitDust(pl, center + radial * radius + UP * 0.4, radial * speed + UP * math.abs(speed) * 0.2, 1)
		end
	end

	-- a thin neon tracer a -> b that fades (the line the shot leaves in the air)
	local function beam(f, a, b, width, color, alpha, life)
		local len = (b - a).Magnitude
		if len < 0.3 then
			return
		end
		local p = mk("Tracer", BLOCK, NEON, color, Vector3.new(width, width, len), CFrame.lookAt((a + b) / 2, b), f, alpha)
		tween(p, life, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, len) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(p, life + 0.1)
	end

	-- the sonic boom's Mach cone: n slats from the fingertip flaring forward and fading
	local function machCone(f, tip, dir, len, radius, n, life, colors)
		local r, u = perp(dir)
		local off = rng:NextNumber(0, TAU)
		local function slat(radial, L, R)
			local e = tip + dir * L + radial * R
			return CFrame.lookAt((tip + e) / 2, e), (e - tip).Magnitude
		end
		for i = 1, n do
			local a = off + (i / n) * TAU
			local radial = r * math.cos(a) + u * math.sin(a)
			local w = (i % 2 == 0) and 0.1 or 0.065
			local cf0, l0 = slat(radial, len * 0.15, radius * 0.15)
			local p = mk("Mach", BLOCK, NEON, colors[(i % #colors) + 1], Vector3.new(w, w, l0), cf0, f, 0.12)
			local cf1, l1 = slat(radial, len, radius)
			tween(p, life, { CFrame = cf1, Size = Vector3.new(w * 0.35, w * 0.35, l1), Transparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
			Debris:AddItem(p, life + 0.1)
		end
	end

	-- an afterimage of the right arm only (3 neon copies that fade where the arm was)
	local ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }
	local function armGhost(f, char, color, alpha, life)
		if not live(char) then
			return
		end
		for _, n in ipairs(ARM) do
			local src = char:FindFirstChild(n)
			if src and src:IsA("BasePart") then
				local ok, c = pcall(function()
					return src:Clone()
				end)
				if ok and c then
					for _, ch in ipairs(c:GetChildren()) do
						if not ch:IsA("DataModelMesh") then
							ch:Destroy()
						end
					end
					pcall(function()
						c.TextureID = ""
					end)
					c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
					c.CastShadow, c.Massless = false, true
					c.Material = NEON
					c.Color = color
					c.Transparency = alpha
					c.CFrame = src.CFrame
					c.Parent = f
					tween(c, life, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					Debris:AddItem(c, life + 0.1)
				end
			end
		end
	end

	-- chips of a wall (its own material and colour) blown back out along its normal
	local function wallChips(f, p, n, hit, count)
		local col, mat = groundColor(hit)
		local r, u = perp(n)
		for _ = 1, count do
			local s = rng:NextNumber(0.3, 0.85)
			local c = Instance.new("Part")
			c.Name = "WallChip"
			c.Size = Vector3.new(s, s * rng:NextNumber(0.45, 0.8), s * rng:NextNumber(0.6, 1))
			pcall(function()
				c.Material = mat
			end)
			c.Color = col:Lerp(BLACK, rng:NextNumber(0, 0.25))
			c.CFrame = CFrame.new(p + n * 0.5 + (r * rng:NextNumber(-1, 1) + u * rng:NextNumber(-1, 1)) * 0.9)
				* CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
			c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false
			pcall(function()
				c.CollisionGroup = "Debris"
			end)
			c.Parent = f
			c.AssemblyLinearVelocity = n * rng:NextNumber(18, 38) + (r * rng:NextNumber(-1, 1) + u * rng:NextNumber(-1, 1)) * 14
				+ UP * rng:NextNumber(4, 12)
			c.AssemblyAngularVelocity = FX.randUnit() * rng:NextNumber(8, 18)
			task.delay(rng:NextNumber(1.3, 2), function()
				if c.Parent then
					tween(c, 0.45, { Transparency = 1, Size = c.Size * 0.4 })
					Debris:AddItem(c, 0.5)
				end
			end)
		end
	end

	-- the veins builder draws crimson; the normal cast recolours its parts green (100% keeps the crimson)
	local function greenVeins(v)
		if type(v) ~= "table" or type(v.list) ~= "table" then
			return
		end
		for _, s in ipairs(v.list) do
			if s.core then
				s.core.Color = PAL.Core:Lerp(PAL.Cowl, 0.35)
			end
			if s.sheath then
				s.sheath.Color = PAL.Cowl
			end
		end
		for _, l in ipairs(v.lights or {}) do
			if l.light then
				l.light.Color = PAL.Cowl
			end
		end
	end

	-- the clip, with its aim keys bent to the cast's pitch (5 degree buckets, cached per base clip)
	local variants = setmetatable({}, { __mode = "k" })
	local function clipFor(base, dir)
		if type(base) ~= "table" or type(base.keys) ~= "table" then
			return base
		end
		local pitch = math.deg(math.asin(math.clamp(dir.Y, -1, 1)))
		local b = math.floor(math.clamp(pitch, -20, 25) / 5 + 0.5) * 5
		if b == 0 then
			return base
		end
		local per = variants[base]
		if not per then
			per = {}
			variants[base] = per
		end
		if per[b] then
			return per[b]
		end
		local keys = {}
		for i, k in ipairs(base.keys) do
			local w = tonumber(k.aim) or 0
			if w > 0 and type(k.pose) == "table" then
				local pose = table.clone(k.pose)
				local rs, nk = pose.RightShoulder, pose.Neck
				if type(rs) == "table" then
					pose.RightShoulder = { (rs[1] or 0) + b * w * AIM_GAIN, rs[2] or 0, rs[3] or 0 }
				end
				if type(nk) == "table" then
					pose.Neck = { (nk[1] or 0) + b * 0.5 * w, nk[2] or 0, nk[3] or 0 }
				end
				keys[i] = { t = k.t, ease = k.ease, pose = pose, aim = k.aim }
			else
				keys[i] = k
			end
		end
		local v = { length = base.length, fadeIn = base.fadeIn, fadeOut = base.fadeOut, flick = base.flick, keys = keys }
		per[b] = v
		return v
	end

	---------------------------------------------------------------------------------------------------
	-- a cast's life: beats, loops and handles it owns

	-- a timeline beat at cast time T: skipped when long past, cancelled when the cast is reset
	local function at(cast, e, T, fn)
		if T < e - 0.05 then
			return
		end
		task.delay(math.max(T - e, 0), function()
			if cast.dead then
				return
			end
			local ok, err = pcall(fn)
			if not ok then
				report(err)
			end
		end)
	end

	local function endCast(key, cast)
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
		if casts[key] == cast then
			casts[key] = nil
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the bullet: on the server timeline, from the fingertip onto the server line, homing on the live torso

	local function flyBullet(cast, d, f, tier, tip0)
		local origin = d.origin
		local dir0 = d.dir.Unit
		local stop = math.max(d.stop or 0, 0)
		local speed = math.max(d.speed or CFG.Speed or 260, 1)
		local tFly = d.t0 + (d.windup or CFG.Windup or 0.36)
		local endPt = origin + dir0 * stop
		local mode = d.mode == true
		local off0 = Vector3.zero
		if typeof(tip0) == "Vector3" and (tip0 - origin).Magnitude < 5 then
			off0 = tip0 - origin
		end
		local tt = (not d.wall) and torsoOf(d.target) or nil
		local function aimEnd()
			if tt and tt.Parent and (tt.Position - endPt).Magnitude <= ESCAPE then
				return tt.Position
			end
			return endPt
		end
		local function posAt(s, e)
			local k = stop > 0.01 and math.clamp(s / stop, 0, 1) or 1
			local c = math.clamp(1 - s / CONVERGE, 0, 1)
			return origin:Lerp(e, k) + off0 * (c * c * (3 - 2 * c))
		end

		local start = posAt(0, endPt)
		local shell = mk("AirShell", BALL, NEON, PAL.Air, Vector3.one * 1.7, CFrame.new(start), f, 0.25)
		local core = mk("AirCore", BALL, NEON, PAL.Core, Vector3.one * 0.85, CFrame.new(start), f, 0)
		local light = Instance.new("PointLight")
		light.Color = PAL.Cowl
		light.Brightness = 3
		light.Range = 14
		light.Shadows = false
		light.Parent = core
		FX.trail(shell, cs(PAL.Air, PAL.Cowl), 1.8, 0.3, { tail = 0, alpha = 0.2, brightness = 2 })
		FX.trail(core, cs(PAL.Core, PAL.Cowl), 0.7, 0.42, { tail = 0.15, alpha = 0.05, brightness = 3 })
		local bubble, strands = nil, {}
		local ringA, wake, wind, dust, ownDust
		if tier >= 2 then
			bubble = mk("AirBubble", BALL, FIELD, PAL.Air, Vector3.one * 2.9, CFrame.new(start), f, 0.1)
			local cols = mode and { PAL.Cowl, PAL.Crimson, PAL.Core } or { PAL.Cowl, PAL.Core, PAL.Air }
			for i, c in ipairs(cols) do
				local p = mk("Helix", BALL, NEON, c, Vector3.one * 0.34, CFrame.new(start), f, 0)
				FX.trail(p, cs(WHITE, c), 0.42, 0.5, { tail = 0, brightness = 3, alpha = 0.05 })
				strands[i] = { part = p, phase = (i - 1) * TAU / #cols }
			end
			ringA = ringPool(f, PAL.Air, PAL.Air:Lerp(mode and PAL.Crimson or PAL.Cowl, 0.65), 4.4, 0.6, 0.3)
			wind = windPool(f)
		end
		-- a camera on the line's axis (behind the caster, or in front of the target) sees the wake end-on
		local toO = origin - camPos()
		local endOn = toO.Magnitude > 1e-3 and math.abs(dir0:Dot(toO.Unit)) > 0.9
		if tier >= 3 then
			wake = wakePool(f, endOn)
			dust = cast.dust -- the cast's own ground dust when it has one
			if not dust then
				dust = dustPool(f)
				ownDust = true
			end
		end

		-- a late joiner starts part-way along and skips the rings / dust already long gone
		local s0 = math.clamp((ctx.now() - tFly) * speed, 0, stop)
		local skipTo = math.max(s0 - speed * 0.25, 0)
		local nextRing = math.max(RING_EVERY * 0.8, math.ceil(skipTo / RING_EVERY) * RING_EVERY)
		local ringN = 0
		local nextWake = math.max(1, skipTo)
		local wakeN = 0
		local nextDust = math.max(3, math.ceil(skipTo / DUST_EVERY) * DUST_EVERY)
		local nextScour = math.max(6, math.ceil(skipTo / SCOUR_EVERY) * SCOUR_EVERY)
		local dustColored = false
		local nextArc = 0
		local spin = rng:NextNumber(0, TAU)
		local born = os.clock()
		local maxLife = math.max(tFly - ctx.now(), 0) + stop / speed + 2
		local conn
		local done = false
		local last = start

		local function finish(arrived)
			if done then
				return
			end
			done = true
			if conn then
				conn:Disconnect()
				conn = nil
			end
			shell.Transparency, core.Transparency = 1, 1
			light.Enabled = false
			Debris:AddItem(shell, 0.6)
			Debris:AddItem(core, 0.6)
			if bubble then
				bubble:Destroy()
			end
			for _, st in ipairs(strands) do
				st.part.Transparency = 1
				Debris:AddItem(st.part, 0.7)
			end
			retire(ringA, 0.8)
			retire(wind, 0.5)
			retire(wake, 1)
			if ownDust then
				retire(dust, 2.1)
			end
			if arrived and tier >= 1 then
				local a = origin + off0
				beam(f, a, last, 0.16, PAL.Air, 0.45, 0.5)
				beam(f, a, last, 0.06, PAL.Core, 0.2, 0.32)
			end
		end

		conn = RunService.Heartbeat:Connect(function(dt)
			if cast.dead or not shell.Parent or os.clock() - born > maxLife then
				finish(false)
				return
			end
			local ok, err = pcall(function()
				local s = math.clamp((ctx.now() - tFly) * speed, 0, stop)
				local e = aimEnd()
				local dirNow = (e - origin).Magnitude > 0.1 and (e - origin).Unit or dir0
				local r, u = perp(dirNow)
				local p = posAt(s, e)
				last = p
				spin += dt
				shell.CFrame = CFrame.new(p)
				core.CFrame = shell.CFrame
				if bubble then
					bubble.CFrame = CFrame.new(p) * CFrame.Angles(spin * 9, spin * 13, 0)
					bubble.Size = Vector3.one * (2.7 + 0.35 * math.sin(spin * 40))
				end
				for _, st in ipairs(strands) do
					local a = spin * 45 + st.phase
					local rad = 1.15 + 0.25 * math.sin(spin * 30 + st.phase)
					st.part.CFrame = CFrame.new(p + (r * math.cos(a) + u * math.sin(a)) * rad)
				end
				if ctx.now() < tFly then
					return -- (not `s <= 0`: a point-blank wall has stop = 0 and must still finish)
				end
				-- the ring tunnel: every 5 studs, pale rings that tint green as they spread, twisting round the line
				while nextRing <= s do
					ringN += 1
					local a = ringN * 1.3 + spin
					if ringA then
						emitAt(ringA, posAt(nextRing, e) + (r * math.cos(a) + u * math.sin(a)) * 0.3, dirNow, 1)
					end
					nextRing += RING_EVERY
				end
				-- wake turbulence + wind streaks, laid continuously along the segment walked this frame
				local n = 0
				while nextWake <= s do
					n += 1
					local wp = posAt(nextWake, e)
					wakeN += 1
					if wake and (not endOn or (wakeN % 3 == 0 and nextWake >= 10)) then
						emitAt(wake, wp, nil, 1) -- end-on: every 4.8 studs, none in the first 10
					end
					if wind and n % 2 == 1 then
						emitAt(wind, wp, -dirNow + (r * rng:NextNumber(-1, 1) + u * rng:NextNumber(-1, 1)) * 0.35, 1)
					end
					nextWake += WAKE_EVERY
				end
				-- dust ploughed up from the ground under it (only when it skims low)
				while nextDust <= s do
					local dp = posAt(nextDust, e)
					if dust then
						local hit = FX.groundHit(dp, 8)
						if hit then
							if not dustColored then
								dustColored = true
								local col = groundColor(hit)
								dust.e.Color = cs(col, col:Lerp(BLACK, 0.25))
							end
							local fl = Vector3.new(dirNow.X, 0, dirNow.Z)
							fl = fl.Magnitude > 0.05 and fl.Unit or Vector3.zero
							emitDust(dust, hit.Position + UP * 0.4, fl * 14 + UP * 6, 2)
						end
					end
					nextDust += DUST_EVERY
				end
				while nextScour <= s do
					if tier >= 3 then
						local sp = posAt(nextScour, e)
						local hit = FX.groundHit(sp, 6)
						if hit then
							FX.rubble(f, hit.Position, { count = 2, radius = 0.8, up = { 8, 20 }, out = { 3, 9 }, min = 0.25, max = 0.6, dir = dirNow })
						end
					end
					nextScour += SCOUR_EVERY
				end
				local clock = os.clock()
				if tier >= 2 and clock >= nextArc then
					nextArc = clock + 0.035
					FX.arcs(f, p, 1.1, { count = 1, colors = mode and { PAL.Crimson, PAL.Core } or { PAL.Cowl, PAL.Core }, width = 0.05, life = 0.07 })
				end
				if s >= stop then
					finish(true)
				end
			end)
			if not ok then
				report(err)
				finish(false)
			end
		end)
		table.insert(cast.conns, conn)
		return {
			destroy = function()
				finish(false)
			end,
		}
	end

	---------------------------------------------------------------------------------------------------
	-- impacts drawn from the cast payload (no body struck)

	local function wallBurst(f, endPt, dir, tier, mode, isLocal)
		local hit = rayWorld(endPt - dir * 3, dir * 6)
		local n = hit and hit.Normal or -dir
		local p = hit and hit.Position or endPt
		local accent = mode and PAL.Crimson or PAL.Cowl
		local near = math.clamp(dist(p) / 30, 0.6, 1) -- the wall faces the shooter: its rings shrink close to the camera
		FX.glow(f, p + n * 0.5, glowFor(p, 5), PAL.Core, 0.15, { brightness = 3 })
		FX.glow(f, p + n * 0.5, glowFor(p, 9), accent, 0.3, { alpha = 0.3, brightness = 1.4 })
		FX.ring(f, p + n * 0.3, n, 1, 10 * near, PAL.Air, 0.3, { alpha = 0.15 })
		FX.streaks(f, p, { dir = n, spread = 50, color = WHITE, color2 = PAL.Air, count = 22, speed = { 50, 110 }, size = 0.45, life = 0.3 })
		FX.sparks(f, p, { dir = n, spread = 70, color = PAL.Spark, color2 = accent, count = 16, speed = { 20, 45 } })
		FX.light(f, p + n, PAL.Air, 6, 20, 0.3)
		task.delay(0.05, function()
			FX.ring(f, p + n * 0.3, n, 2, 14 * near, PAL.Air, 0.5, { alpha = 0.4 })
		end)
		if tier >= 2 then
			FX.arcs(f, p + n * 0.4, 2.5, { outward = true, count = 3, colors = { accent, PAL.Core }, width = 0.06 })
		end
		if tier >= 3 then
			wallChips(f, p, n, hit, 9)
			FX.rubble(f, p, { count = 5, radius = 1.5, up = { 15, 35 }, out = { 10, 25 }, dir = n })
			if S.dust then
				S.dust(f, p + n * 0.6, n * 18, { s0 = 2.5, s1 = 7, count = 3 })
			end
		end
		ctx.soundAt(SND.HitHeavy, p, 0.7, 1.3)
		ctx.soundAt("AirPop", p, 0.45, 1.5)
		if isLocal then
			ctx.shake(0.3, 0.22, 26)
		end
	end

	local function airPop(f, endPt, dir, tier)
		FX.ring(f, endPt, dir, 1, 7, PAL.Air, 0.25)
		FX.glow(f, endPt, glowFor(endPt, 4), PAL.Air, 0.2, { alpha = 0.3 })
		if tier >= 2 then
			FX.streaks(f, endPt, { dir = dir, spread = 25, color = WHITE, color2 = PAL.Air, count = 14, speed = { 60, 120 }, size = 0.35, life = 0.25 })
			task.delay(0.05, function()
				FX.ring(f, endPt + dir * 2, dir, 1.5, 10, PAL.Air, 0.4, { alpha = 0.4 })
			end)
		end
		ctx.soundAt(SND.Whoosh, endPt, 0.4, 2)
	end

	---------------------------------------------------------------------------------------------------
	-- AirForceCast (every client)

	H.AirForceCast = function(d)
		if typeof(d.origin) ~= "Vector3" or typeof(d.dir) ~= "Vector3" or type(d.t0) ~= "number" then
			return
		end
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster ~= nil and caster == ctx.player
		local e = ctx.now() - d.t0
		local dir = d.dir.Magnitude > 1e-3 and d.dir.Unit or Vector3.new(0, 0, -1)
		local origin = d.origin
		local W = d.windup or CFG.Windup or 0.36
		local speed = math.max(d.speed or CFG.Speed or 260, 1)
		local stop = math.max(d.stop or 0, 0)
		local endPt = origin + dir * stop
		local tImp = W + stop / speed
		local mode = d.mode == true
		local base = ctx.Clips and ctx.Clips.AirForce
		local clipLen = (type(base) == "table" and base.length) or 0
		if e > tImp + 0.4 and e > clipLen + 0.3 then
			return -- a stale broadcast: the whole cast is over
		end

		local track = ctx.playClip(char, clipFor(base, dir), e)
		local life = math.max(tImp, clipLen + 0.3, W + 1.6) - math.max(e, 0) + 2.6
		local f = ctx.castFolder("AirForce", life)
		local cast = { folder = f, isLocal = isLocal, dead = false, conns = {}, handles = {}, track = track }
		local key = d.id ~= nil and (tostring(d.userId) .. ":" .. tostring(d.id)) or f
		casts[key] = cast
		task.delay(life, function()
			endCast(key, cast)
		end)

		-- tiers: 3 everything, 2 no veins / ghosts / dust / rubble, 1 the core only, 0 nothing (the hit layer still draws)
		local function tierAt(dd)
			if isLocal or dd <= GATE_FULL then
				return 3
			elseif dd <= GATE_MID then
				return 2
			elseif dd <= GATE_CORE then
				return 1
			end
			return 0
		end
		local tierC = tierAt(dist(origin)) -- layers on the caster
		local tierB = tierAt(segDist(origin, endPt)) -- the bullet and its line
		local flatAim = ctx.flat(dir, Vector3.new(0, 0, -1))
		local accent = mode and PAL.Crimson or PAL.Cowl
		local boltCols = mode and { PAL.Cowl, PAL.Crimson, PAL.Core } or { PAL.Cowl, PAL.Core }
		local hand = char and char:FindFirstChild("RightHand")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")

		-- the fingertip (the hand's -Y end), or the server origin when the hand is gone or far off
		local function tipPos()
			if hand and hand.Parent then
				local p = hand.CFrame * Vector3.new(0, -0.38, 0)
				if (p - origin).Magnitude < 8 then
					return p
				end
			end
			return origin - dir * 0.4
		end
		local function feetHit()
			local p = (hrp and hrp.Parent) and hrp.Position or (origin - flatAim * 1.6 - UP)
			return FX.groundHit(p, 8)
		end

		-- the cast's pooled ground dust (in the ground's colour)
		local dust
		if tierC >= 3 then
			local g = feetHit()
			dust = dustPool(f, g and groundColor(g) or nil)
			retire(dust, life)
			cast.dust = dust
		end

		if isLocal and char == ctx.player.Character then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the AIR FORCE callout is gone)
			local left = ROOT_TIME - math.max(e, 0)
			if left > 0.02 then
				ctx.root(left, flatAim)
			end
			if e < W * 0.5 then
				local lead = math.max(W - math.max(e, 0), 0.05)
				ctx.lean({ pitch = 0, drop = 0.12, fov = -5, attack = lead * 0.9, hold = 0.04, release = 0.3 })
				ctx.shake(0.05, lead, 34, 0)
			end
		end

		---------------------------------------------------------------------------------------------
		-- WIND-UP (0 -> W)
		if tierC >= 1 and e < W then
			at(cast, e, 0, function()
				local p = tipPos()
				snd(SND.Crackle, hand, p, 0.45, 1.5)
				snd(SND.Swell, hand, p, 0.42, 1.3)
				FX.glow(f, p, glowFor(p, 2.4), PAL.Cowl, 0.25, { alpha = 0.3 })
			end)
		end
		if dust and e < W then
			at(cast, e, 0.02, function()
				local g = feetHit()
				if g then
					dustRing(dust, g.Position, 3.6, 7, -8) -- dust rolls in toward his feet
				end
			end)
		end

		-- the energy pool at the fingertip: orb + light + an inward stream + converging bolts + arm arcs (one loop)
		if tierC >= 2 and e < W - 0.05 then
			at(cast, e, math.max(0.06, e), function()
				local p = tipPos()
				local orb = mk("PoolOrb", BALL, NEON, PAL.Cowl, Vector3.one * 0.25, CFrame.new(p), f, 0.45)
				local orbCore = mk("PoolCore", BALL, NEON, PAL.Core, Vector3.one * 0.12, CFrame.new(p), f, 0)
				local light = Instance.new("PointLight")
				light.Color = PAL.Cowl
				light.Brightness = 0
				light.Range = 10
				light.Shadows = false
				light.Parent = orbCore
				local inHost = FX.part("PoolIn", BALL, PLASTIC, WHITE, nil)
				inHost.Transparency = 1
				inHost.Size = Vector3.one * 5.2
				inHost.CFrame = CFrame.new(p)
				inHost.Parent = f
				local inE = FX.emitter(inHost, {
					Texture = TEX.glow, Color = cs(PAL.Core, PAL.Cowl), Lifetime = NumberRange.new(0.2),
					Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
					ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, Speed = NumberRange.new(12, 15),
					Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2),
					Size = nsk({ { 0, 0.1 }, { 0.6, 0.22 }, { 1, 0.05 } }), Transparency = nsk({ { 0, 1 }, { 0.25, 0.15 }, { 1, 0.3 } }),
					LockedToPart = true, Brightness = 2.4, Rate = 30,
				})
				cast.pool = { orb = orb, core = orbCore, inHost = inHost, inE = inE }
				local nextBolt, nextLimb = 0, 0
				local conn
				conn = RunService.Heartbeat:Connect(function()
					local t = ctx.now() - d.t0
					if cast.dead or t >= W or not orb.Parent then
						conn:Disconnect()
						return
					end
					local k = math.clamp((t - 0.06) / math.max(W - 0.06, 0.05), 0, 1)
					local q = tipPos()
					local fl = 1 + 0.14 * math.sin(t * 70)
					orb.Size = Vector3.one * (0.25 + 0.9 * k) * fl
					orb.CFrame = CFrame.new(q)
					orb.Transparency = 0.45 - 0.25 * k
					orbCore.Size = Vector3.one * (0.12 + 0.42 * k)
					orbCore.CFrame = orb.CFrame
					light.Brightness = 3.5 * k
					inHost.CFrame = orb.CFrame
					inE.Rate = 30 + 90 * k
					local c = os.clock()
					if t >= 0.08 and c >= nextBolt then
						nextBolt = c + 0.045
						FX.bolt(f, q + FX.randUnit() * rng:NextNumber(1.6, 2.6), q, {
							color = pick(boltCols), width = 0.045, segments = 4, jag = 0.3, life = 0.07, restrike = 0,
						})
					end
					if t >= 0.1 and c >= nextLimb and live(char) and S.limbArc then
						nextLimb = c + 0.05
						S.limbArc(f, char, S.ARM_R, pick(boltCols), 0.05)
					end
				end)
				table.insert(cast.conns, conn)
			end)
			-- air rings collapsing into the finger, the last one the biggest
			for i, t in ipairs({ 0.1, 0.17, 0.24, 0.3 }) do
				at(cast, e, t, function()
					local big = i == 4
					FX.ring(f, tipPos(), dir, big and 7 or 5.5, 0.3, PAL.Air, big and 0.24 or 0.2, { ease = "in", alpha = big and 0.25 or 0.35 })
				end)
			end
			at(cast, e, 0.12, function()
				snd(SND.Zap, hand, tipPos(), 0.3, 1.5)
			end)
			at(cast, e, 0.24, function()
				snd(SND.Sizzle, hand, tipPos(), 0.22, 1.9)
				FX.arcs(f, tipPos(), 0.9, { count = 2, colors = boltCols, width = 0.04 })
			end)
		end

		-- veins of light crawling up the arm (they fade through the follow-through)
		if tierC >= 3 and e < W and S.Veins and live(char) then
			at(cast, e, 0.1, function()
				if not live(char) then
					return
				end
				local v = S.Veins.new(f, char, S.ARM_R, {
					perLimb = isLocal and 3 or 2, segs = 3, width = 0.07, crawl = math.max(W - 0.12, 0.1), pulseHz = 9,
					t0 = d.t0 + 0.1,
				})
				if not mode then
					greenVeins(v)
				end
				table.insert(cast.handles, v)
				cast.veins = v
			end)
			at(cast, e, W + 0.4, function()
				if cast.veins then
					cast.veins:fade(1)
				end
			end)
		end

		---------------------------------------------------------------------------------------------
		-- THE FLICK (W)
		if track and e < W then
			task.delay(math.max(W + 0.012 - e, 0), function()
				if not cast.dead then
					ctx.freeze(track, HITSTOP) -- the money frame hangs on every client
				end
			end)
		end
		at(cast, e, W, function()
			local tip = tipPos()
			cast.tip0 = tip
			local pl = cast.pool
			if pl then
				cast.pool = nil
				pl.orb:Destroy()
				pl.core:Destroy()
				pl.inE.Rate = 0
				Debris:AddItem(pl.inHost, 0.22)
			end
			if tierC >= 1 or tierB >= 1 then
				FX.glow(f, tip, glowFor(tip, 4.5), PAL.Core, 0.12, { brightness = 3 })
				FX.glow(f, tip, glowFor(tip, 8), accent, 0.25, { alpha = 0.25, brightness = 1.5 })
				FX.light(f, tip, PAL.Cowl, 7, 20, 0.3)
				-- every ring of the sonic boom comes off one pooled emitter (11 studs, 0.32 s)
				cast.boom = ringPool(f, WHITE, PAL.Air, 11, 0.32, 0.18)
				retire(cast.boom, 0.62)
				emitAt(cast.boom, tip, dir, 1)
			end
			if tierC >= 2 then
				FX.shell(f, tip, 0.3, 2, PAL.Air, 0.2, FIELD)
				machCone(f, tip, dir, 6, 2.6, 10, 0.22, { PAL.Air, PAL.Core })
				FX.streaks(f, tip, { dir = dir, spread = 8, color = WHITE, color2 = PAL.Air, count = 22, speed = { 200, 300 }, size = 0.4, life = 0.22, stretch = 3 })
				FX.streaks(f, tip, { dir = -dir, spread = 45, color = PAL.Air, count = 14, speed = { 30, 70 }, size = 0.3, life = 0.25 })
				FX.sparks(f, tip, { color = PAL.Spark, color2 = accent, count = 12, speed = { 15, 40 } })
				armGhost(f, char, PAL.Core, 0.45, 0.24)
			end
			if tierC >= 3 then
				local g = FX.groundHit(tip, 9)
				if g and dust then
					emitDust(dust, g.Position + UP * 0.4, flatAim * 26 + UP * 4, 3) -- blown off the ground ahead
				end
				local fh = feetHit()
				if fh then
					if dust then
						dustRing(dust, fh.Position, 1.6, 8, 20) -- and flattened out round his feet
					end
					FX.rubble(f, fh.Position, { count = 3, radius = 1.2, up = { 8, 16 }, out = { 6, 12 }, min = 0.25, max = 0.55 })
				end
				if S.ghost then
					S.ghost(char, PAL.Cowl, 0.75, 0.38, -flatAim * 0.45) -- the recoil's echo of the body
				end
			end
			ctx.soundAt("AirPop", tip, 0.8, 1.3)
			ctx.soundAt(SND.Hit2, tip, 0.55, 1.5)
			ctx.soundAt(SND.Thunder, tip, 0.3, 2.2)
			ctx.soundAt(SND.Whoosh, tip, 0.6, 1.9)
			if isLocal then
				ctx.shake(0.38, 0.24, 30, 6)
				pcall(FX.speedLines, 0.26, { color = PAL.Spark, alpha = 0.4, count = 40, inner = 0.45, thick = 4 })
				if type(ctx.vignette) == "function" then
					ctx.vignette(0.16, 0.4)
				end
			end
		end)
		-- the sonic boom, staggered: a flat ring round the finger, two more stepping out along the aim, one upright
		if tierC >= 2 then
			at(cast, e, W + 0.02, function()
				emitAt(cast.boom, cast.tip0 or tipPos(), UP, 1)
			end)
			at(cast, e, W + 0.045, function()
				local tip = cast.tip0 or tipPos()
				emitAt(cast.boom, tip + dir * 3, dir, 1)
				local side = dir:Cross(UP)
				FX.ring(f, tip, side.Magnitude > 0.05 and side.Unit or Vector3.xAxis, 0.5, 6.5, accent, 0.26, { alpha = 0.35 })
			end)
			at(cast, e, W + 0.08, function()
				emitAt(cast.boom, (cast.tip0 or tipPos()) + dir * 6.5, dir, 1)
			end)
			-- the arm's afterimages along the snap
			at(cast, e, W + 0.03, function()
				armGhost(f, char, PAL.Cowl, 0.6, 0.24)
			end)
			at(cast, e, W + 0.06, function()
				armGhost(f, char, PAL.Air, 0.72, 0.22)
			end)
		end

		-- the bullet
		if tierB >= 1 and e < tImp then
			at(cast, e, math.max(W, e), function()
				local ok, res = pcall(flyBullet, cast, d, f, tierB, cast.tip0 or tipPos())
				if ok then
					table.insert(cast.handles, res)
				else
					report(res)
				end
			end)
		end

		---------------------------------------------------------------------------------------------
		-- IMPACT from the payload: a wall burst, or an air pop when nothing was struck
		at(cast, e, tImp, function()
			local tierE = isLocal and 3 or tierAt(dist(endPt))
			if d.wall then
				wallBurst(f, endPt, dir, tierE, mode, isLocal)
				return
			end
			if hits[key] then
				return
			end
			local tt = torsoOf(d.target)
			local function pop()
				if cast.dead or hits[key] then
					return
				end
				airPop(f, endPt, dir, tierE)
			end
			if tt and (tt.Position - endPt).Magnitude <= ESCAPE then
				task.delay(0.3, pop) -- the server should strike now; pop only if its AirForceHit never comes
			else
				pop()
			end
		end)

		---------------------------------------------------------------------------------------------
		-- AFTERMATH: the smoking finger, embers, lingering arcs, the sizzle
		if tierC >= 2 then
			at(cast, e, W + 0.04, function()
				if not (live(hand) and S.steam) then
					return
				end
				local st = S.steam(hand, 16)
				table.insert(cast.handles, st)
				cast.steam = st
				st:Emit(6)
			end)
			at(cast, e, W + 0.6, function()
				if cast.steam then
					cast.steam:setRate(7)
				end
			end)
			at(cast, e, W + 1.3, function()
				if cast.steam then
					cast.steam:stop()
				end
			end)
			-- a puff (and a few sparks) shaken off on each flap of the hand (clip 0.735 / 0.79 / 0.845 + the hit-stop)
			for _, t in ipairs({ 0.735, 0.79, 0.845 }) do
				at(cast, e, t + HITSTOP, function()
					if cast.steam then
						cast.steam:Emit(5)
					end
					local p = tipPos()
					FX.sparks(f, p, { color = PAL.Spark, color2 = accent, count = 3, speed = { 6, 14 }, life = 0.4, size = 0.3 })
				end)
			end
			for _, t in ipairs({ 0.2, 0.45, 0.75 }) do
				at(cast, e, W + t, function()
					FX.sparks(f, tipPos(), { color = accent, color2 = PAL.Core, count = 4, speed = { 3, 9 }, life = 0.9, accel = Vector3.new(0, 5, 0), drag = 2, size = 0.3 })
				end)
			end
			for _, t in ipairs({ 0.12, 0.22, 0.34, 0.48, 0.64, 0.82 }) do
				at(cast, e, W + t, function()
					if live(char) and S.limbArc then
						S.limbArc(f, char, S.ARM_R, pick(boltCols), 0.045)
					end
				end)
			end
			at(cast, e, W + 0.42, function()
				snd(SND.Sizzle, hand, tipPos(), 0.28, 1.25)
			end)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- AirForceHit (every client): the impact layer, never distance-gated (its heavy parts are)

	H.AirForceHit = function(d)
		local key = d.id ~= nil and (tostring(d.userId) .. ":" .. tostring(d.id)) or nil
		if key then
			hits[key] = true
			task.delay(6, function()
				hits[key] = nil
			end)
		end
		local pos = d.pos
		if typeof(pos) ~= "Vector3" then
			return
		end
		local dir = (typeof(d.dir) == "Vector3" and d.dir.Magnitude > 1e-3) and d.dir.Unit or Vector3.new(0, 0, -1)
		local mode = d.mode == true
		local accent = mode and PAL.Crimson or PAL.Cowl
		local isMine = d.userId == ctx.player.UserId
		local dd = dist(pos)
		local tier = (isMine or dd <= GATE_FULL) and 3 or (dd <= GATE_MID and 2 or (dd <= HIT_FAR and 1 or 0))
		local f = ctx.castFolder("AirForceHit", 5)
		local cast = key and casts[key] or nil
		if cast and cast.track and not cast.dead then
			ctx.freeze(cast.track, HIT_FREEZE) -- the caster's pose hangs on the hit too
		end
		local arcCols = mode and { PAL.Crimson, PAL.Core } or { PAL.Cowl, PAL.Core }
		-- the shot's rings face back along it, i.e. at the shooter's camera: close to the lens they shrink (x0.6 at
		-- 18 studs) so two 16-19 stud rings never stack over the impact frame's contrast boost
		local near = math.clamp(dd / 30, 0.6, 1)

		FX.glow(f, pos, glowFor(pos, 8), PAL.Core, 0.18, { brightness = 3.5 })
		FX.light(f, pos, PAL.Cowl, 9, 26, 0.35)
		if tier < 1 then
			return -- far away: the core flash is all that reads
		end
		FX.glow(f, pos, glowFor(pos, 14), accent, 0.38, { brightness = 1.6, alpha = 0.22 })
		local fast = ringPool(f, WHITE, PAL.Air, 16 * near, 0.42, 0.12) -- the burst's rings (along the shot, then flat)
		local slow = ringPool(f, PAL.Air, PAL.Air, 19 * near, 1, 0.6) -- the slow residual rings
		retire(fast, 0.6)
		retire(slow, 1.4)
		emitAt(fast, pos, dir, 1)
		FX.ring(f, pos, ctx.camFacing(pos), 1, 9 * near, WHITE, 0.2)
		FX.shell(f, pos, 0.5, 4.2, PAL.Air, 0.25, FIELD)
		FX.streaks(f, pos, { dir = dir, spread = 35, color = WHITE, color2 = PAL.Air, count = 34, speed = { 80, 170 }, size = 0.55, life = 0.32 })
		FX.sparks(f, pos, { color = PAL.Spark, color2 = accent, count = 26, speed = { 12, 55 }, life = 0.85 }) -- glints + falling embers
		if tier >= 2 then
			FX.arcs(f, pos, 3.5, { outward = true, count = 4, colors = arcCols, width = 0.08 })
			FX.streaks(f, pos, { color = accent, color2 = PAL.Core, count = 18, speed = { 40, 90 }, size = 0.4, life = 0.3 })
		end
		task.delay(0.03, function()
			emitAt(fast, pos, UP, 1)
		end)
		task.delay(0.06, function()
			FX.ring(f, pos + dir * 2.5, dir, 2, 18 * near, accent, 0.4, { alpha = 0.35 })
			if tier >= 2 then
				FX.arcs(f, pos, 3, { outward = true, count = 2, colors = arcCols, width = 0.07 })
			end
		end)
		task.delay(0.12, function()
			emitAt(slow, pos, dir, 1) -- the slow residual ring
		end)
		if tier >= 2 then
			task.delay(0.16, function()
				FX.arcs(f, pos, 2.5, { outward = true, count = 2, colors = arcCols, width = 0.06 })
			end)
			if S.dust then
				S.dust(f, pos, dir * 14, { color = PAL.Steam, s0 = 2, s1 = 7, count = 3, life = 1.4 }) -- the displaced air
			end
		end
		if tier >= 3 then
			local g = FX.groundHit(pos, 9)
			if g then
				emitAt(slow, g.Position + UP * 0.3, UP, 1)
				local pl = cast and cast.dust and cast.dust.host.Parent and cast.dust or nil
				if not pl then
					pl = dustPool(f, (groundColor(g)))
					retire(pl, 2.2)
				end
				dustRing(pl, g.Position, 2, 8, 34)
				FX.rubble(f, g.Position, { count = 6, radius = 1.5, up = { 18, 38 }, out = { 10, 24 }, dir = dir })
			end
		end
		if typeof(d.model) == "Instance" and d.model.Parent then
			local m = d.model
			if S.bodyTrail then
				S.bodyTrail(m, cs(PAL.Air, accent), 1.6, 0.8)
			end
			if tier >= 2 then
				for _, t in ipairs({ 0, 0.07, 0.14, 0.21, 0.3 }) do
					task.delay(t, function()
						if m.Parent then
							ctx.bodyArc(f, m, pick(arcCols), 0.07)
						end
					end)
				end
			end
		end
		if mode then
			FX.ring(f, pos, dir, 1, 10 * near, PAL.Crimson, 0.3, { alpha = 0.3 })
			FX.arcs(f, pos, 3.5, { outward = true, count = 2, color = PAL.Crimson, width = 0.08 })
		end

		ctx.soundAt(SND.Hit, pos, 0.9, 0.9)
		ctx.soundAt("AirPop", pos, 0.5, 1.6)
		ctx.soundAt(SND.HitHeavy, pos, 0.5, 1.35)
		ctx.soundAt(SND.Boom, pos, 0.22, 1.9)

		if isMine then
			FX.impact({ tint = PAL.Spark, lines = false, flashAlpha = 0.15, flashLife = 0.15 })
			ctx.shake(0.5, 0.3, 26, -3)
			if type(ctx.tally) == "function" then
				ctx.tally(d.id, 1) -- the HUD hit tally pops "×1" (§10.2)
			end
		elseif dd < OTHER_SHAKE then
			ctx.shake(0.2, 0.2, 26)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- local character died / kit unequipped: end the local caster's running casts (beats, loops, bullet, leftovers)

	H.__reset = function()
		for key, c in pairs(casts) do
			if c.isLocal then
				c.dead = true
				if c.pool then
					kill(c.pool.inHost)
					c.pool = nil
				end
				endCast(key, c)
				if c.folder then
					c.folder:Destroy()
				end
			end
		end
	end

	return H
end
