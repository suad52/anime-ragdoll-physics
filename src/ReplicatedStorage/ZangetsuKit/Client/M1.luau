--!nocheck
-- ZangetsuKit.Client.M1 (owner sword-m1, FLAIR pass): the sword combo on every client (DESIGN.md 5.4 + flair/m1).
-- require(this)(ctx) -> { M1Swing, M1Hit, M1Cancel, __reset }. Keyed by userId#id. W = hitAt (0.14/0.14/0.18/0.30).
-- Clip: Slash<combo> (Shikai) / Slash<combo>BK (Tensa Zangetsu form: the recovery ends in the low carry); swings 1-3
-- drop the legs + Root while the caster moves. "late" beats run on CLIP time: they slip by the swing's hit-stop.
-- Beats per M1Swing (e = now - t0):
--   0.00   clip; local caster: swings 1-3 slowed x0.45 to W + 0.12 (+ hit-stop), swing 4 rooted to W + 0.50 (+ hit-stop:
--          the money hold AND the twirl). The blade starts to burn (bladeGlow 0.3 -> 1 at W), reiatsu licks off it
--   0.02   (swing 4: 0.06) streaks pulled INTO the blade; the wind-up star glint at the tip (swing 4 also crackles)
--   0.04   the blade trail (wide, Core -> Reiatsu; mode black + crimson) to W + 0.12 (swing 4: W + 0.16)
--   W-0.08 whoosh. W-0.03 the edge flash: a sheen races base -> tip along the cutting edge (a Beam on the sword)
--   W      the slash: the arc (3 layers, pitched / yawed so its face shows to the caster's camera), an echo arc inside
--          it, the swept SHEET (a two-band fan of light filling the cut), air-cut streaks, a release ring in the swing
--          plane, two afterimages; ground scuffs (1-2: a dust kick + a wind ring at the lead foot; 3: the chop bites -
--          a gouge, cracks, a ring, chips and sparks, plus a white vertical slit in the air); mode: the slash wave
--   W..    the blade flares to 1 and cools by W + 0.34; chiburi on the clip's FLICK key (0.455 / 0.515): droplets of
--          light flicked off the tip + a tick of a whoosh
--   swing 4 (the mini-finisher): 0.04 ground dust drawn IN + 4 rocks lift, camera squeeze; 0.06 inward streaks +
--          crackling arcs; 0.12 dust ring + 4 flame licks; 0.17/0.215/0.26 spin afterimages, spin whooshes, a wind
--          ring at the feet; W: the 340-degree arc + its annulus sheet, the CRESCENT BURST (4 flat crescents flung out
--          of the spin), shock rings in 3 planes (flat, +25, -25 deg) + a ground ring, a flame ring, rubble and the
--          lifted rocks flung, radial cracks, a dust doughnut, a light, boom, caster shake + FOV punch + speed lines;
--          aftermath to ~W+1.6: a residual ring, reiatsu wisps out of the cracks, frost motes, a slow dust settle,
--          rising embers; THE TWIRL (clip 0.50-0.80): a short blade trail drawing the spin over his head, a glint
--          each half turn, two whooshes, a ring over his head; 0.87 the cleaver drops onto his shoulder (glint)
--   mode wave: the black crescent (bigger, face turned to the camera) races the wall-clamped `wave` studs trailing a
--          crimson cut line and a scorched scar on the ground, then splits in a crimson burst (swing 4: + cracks)
-- M1Hit (per body): 2 glows (first 2 bodies full size), the X of two cuts + a lingering cut mark along the swing,
--   white + ice sparks, rings in two planes (camera-facing, scaled near the lens; the swing plane), reiatsu flames
--   bursting off the body, a light; swing 4: an energy shell on the first body, radial streaks, a comet trail, and
--   for the local caster one impact frame. Once per swing: every client hit-stops the caster's clip; caster kick.
-- A newer swing (or, during swing 4's twirl, another of his moves: KitLocked going true again) stops the older
-- swing's blade effects and drops the flourish. Gating (other casters): <= 160 studs everything (rich layers -
-- sheets, afterimages, the burst, rocks - within 120); <= 250 the clip only; beyond that only the hit sounds.
return function(ctx)
	local H = {}

	local RunService = game:GetService("RunService")
	local Debris = game:GetService("Debris")

	local FX = ctx.FX
	local CFG = ctx.CFG or {}
	local M1 = CFG.M1 or {}
	local PAL = ctx.PAL or CFG.Palette or {}
	local UP = Vector3.yAxis
	local FLATV = Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local rng = Random.new()
	local rad = math.rad

	-- PERKS (2026-11-07, kitsE): the Trail Pack perk restyles the blade trail with the CASTER's EquipTrail
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
		local p = typeof(char) == "Instance" and game:GetService("Players"):GetPlayerFromCharacter(char)
		local id = p and p:GetAttribute("EquipTrail") or ""
		pcall(TrailStyle.apply, tr, type(id) == "string" and id or "")
	end

	local CORE = PAL.Core or Color3.fromRGB(240, 250, 255)
	local REI = PAL.Reiatsu or Color3.fromRGB(150, 215, 255)
	local ICE = PAL.Ice or Color3.fromRGB(80, 160, 255)
	local FROST = PAL.Frost or Color3.fromRGB(205, 235, 255)
	local BLACK = PAL.Black or Color3.fromRGB(14, 10, 14)
	local CRIMSON = PAL.Crimson or Color3.fromRGB(220, 20, 40)
	local EMBER = PAL.Ember or Color3.fromRGB(255, 90, 60)
	local SMOKE = PAL.Smoke or Color3.fromRGB(36, 30, 34)

	local NEON = Enum.Material.Neon
	local PLASTIC = Enum.Material.SmoothPlastic

	local GATE_FULL = M1.GateFull or 160
	local GATE_MID = M1.GateMid or 250
	local GATE_RICH = M1.GateRich or 120
	local MOVE_MUL = M1.MoveMul or 0.45
	local SLOW_EXTRA = M1.SlowExtra or 0.12
	local ROOT4 = M1.RootExtra4 or 0.50
	local FREEZE = M1.Freeze or { 0.04, 0.04, 0.04, 0.07 }
	local PART_CAP, EMIT_CAP = M1.PartCap or 360, M1.EmitCap or 24
	-- clip-time keys the effects follow (Clips.M1): the chiburi flick, the twirl, the drop on the shoulder
	local FLICK_AT = { 0.455, 0.455, 0.515 }
	local TWIRL0, TWIRL1, DROP_AT = 0.50, 0.80, 0.87

	local casts = {} -- "userId#id" -> cast
	local lastTrack = setmetatable({}, { __mode = "k" }) -- [char] = the latest swing track
	local lastCast = setmetatable({}, { __mode = "k" }) -- [char] = the latest swing cast
	local warned = {}
	H._stats = { peakParts = 0, peakEmitters = 0, casts = 0 } -- read by the Edit-mode harness

	---------------------------------------------------------------------------------------------------
	-- helpers

	local function warnOnce(tag, msg)
		if not warned[tag] then
			warned[tag] = true
			warn("[Zangetsu.M1] " .. tag .. ": " .. tostring(msg))
		end
	end

	local function try(tag, fn, ...)
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

	local function kill(h)
		if h == nil then
			return
		end
		pcall(function()
			if typeof(h) == "Instance" then
				h:Destroy()
			elseif typeof(h) == "RBXScriptConnection" then
				h:Disconnect()
			elseif type(h) == "table" then
				local fn = h.Destroy or h.destroy or h.stop
				if type(fn) == "function" then
					fn(h)
				end
			end
		end)
	end

	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end

	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	local function camCF()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame or CFrame.identity
	end

	local function glowFor(pos, size)
		local S = ctx.S
		if S and type(S.glowFor) == "function" then
			local ok, v = pcall(S.glowFor, pos, size)
			if ok and type(v) == "number" then
				return v
			end
		end
		return size * math.clamp(ctx.camDist(pos) / 30, 0.45, 1)
	end

	-- camera-facing rings shrink near the lens (no white-outs)
	local function ringScale(pos)
		return math.clamp(ctx.camDist(pos) / 30, 0.6, 1)
	end

	-- a translucent surface thins out as the lens gets close to it (gone within 3 studs, untouched past `far`, 14)
	local function camFade(pos, base, far)
		local k = math.clamp(1 - (ctx.camDist(pos) - 3) / ((far or 14) - 3), 0, 1)
		return base + (1 - base) * k
	end

	local function rotY(v, deg)
		return CFrame.Angles(0, rad(deg), 0):VectorToWorldSpace(v)
	end

	local function torsoOf(m)
		if not live(m) then
			return nil
		end
		local S = ctx.S
		if S and type(S.torsoOf) == "function" then
			local ok, t = pcall(S.torsoOf, m)
			if ok and typeof(t) == "Instance" then
				return t
			end
		end
		return m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
	end

	local function swordOf(char)
		if ctx.sword then
			local ok, i = pcall(ctx.sword, char)
			if ok then
				return i
			end
		end
		local Sw = ctx.Sword
		return Sw and Sw.get and Sw.get(char) or nil
	end

	local function formOf(char)
		if type(ctx.form) == "function" then
			local ok, f = pcall(ctx.form, char)
			if ok then
				return f
			end
		end
		local i = swordOf(char)
		return i and i.form
	end

	local function wpos(att, fallback)
		return (typeof(att) == "Instance" and att.Parent and att.WorldPosition) or fallback
	end

	local function newPart(name, mat, color, size, cf, t, parent)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = mat
		p.Color = color
		p.Size = size
		p.CFrame = cf
		p.Transparency = t or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		return p
	end

	-- live part / emitter count of a cast (its folder + its afterimages), recorded for the harness
	local function budget(cast)
		local parts, em = 0, 0
		if live(cast.folder) then
			for _, d in ipairs(cast.folder:GetDescendants()) do
				if d:IsA("BasePart") then
					parts += 1
				elseif d:IsA("ParticleEmitter") then
					em += 1
				end
			end
		end
		for _, g in ipairs(cast.ghosts) do
			if live(g) then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("BasePart") then
						parts += 1
					end
				end
			end
		end
		H._stats.peakParts = math.max(H._stats.peakParts, parts)
		H._stats.peakEmitters = math.max(H._stats.peakEmitters, em)
		return parts, em
	end

	local function room(cast, parts, emitters)
		local p, e = budget(cast)
		return p + (parts or 0) <= PART_CAP and e + (emitters or 0) <= EMIT_CAP
	end

	-- a beat at t seconds after the cast (skipped when the late joiner is long past it)
	local function at(cast, t, fn)
		local delay = t - cast.e0
		if delay < -0.06 then
			return
		end
		task.delay(math.max(delay, 0), function()
			if not cast.dead then
				try("beat", fn)
			end
		end)
	end

	-- a beat on CLIP time: it slips by the hit-stop the clip took (cast.shift), so it lands on its key
	local function late(cast, t, fn)
		at(cast, t, function()
			local s = cast.shift or 0
			if s > 0.005 then
				task.delay(s, function()
					if not cast.dead then
						try("beat", fn)
					end
				end)
			else
				fn()
			end
		end)
	end

	local function colours(mode)
		if mode then
			return { core = BLACK, edge = CRIMSON, spark = CRIMSON, spark2 = EMBER, glow = EMBER, ring = CRIMSON, sheen = EMBER, black = true }
		end
		return { core = CORE, edge = REI, spark = FROST, spark2 = REI, glow = CORE, ring = FROST, sheen = WHITE, black = false }
	end

	---------------------------------------------------------------------------------------------------
	-- the local caster's movement through swings 1-3 when the scaffold has no ctx.slow: walk at x0.45 and turn to the
	-- aim (written in Stepped, before physics, so it wins over the scaffold's per-frame movement write)
	local slow = { conn = nil, untilClock = 0, dir = nil, written = nil, base = nil, rotOff = false }

	local function endSlow()
		if slow.conn then
			slow.conn:Disconnect()
			slow.conn = nil
		end
		local _, hum = ctx.myChar()
		if hum then
			if slow.written and slow.base and math.abs(hum.WalkSpeed - slow.written) < 1e-3 then
				hum.WalkSpeed = slow.base
			end
			if slow.rotOff and hum.WalkSpeed > 0 then
				hum.AutoRotate = true
			end
		end
		slow.written, slow.base, slow.rotOff, slow.untilClock = nil, nil, false, 0
	end

	local function startSlow(dir, secs)
		slow.dir = dir
		slow.untilClock = math.max(slow.untilClock, os.clock() + secs)
		if slow.conn then
			return
		end
		slow.conn = RunService.Stepped:Connect(function(_, dt)
			local _, hum, hrp = ctx.myChar()
			if not hum or not hrp or os.clock() > slow.untilClock then
				endSlow()
				return
			end
			local ws = hum.WalkSpeed
			if slow.written and slow.base and math.abs(ws - slow.written) < 1e-3 then
				ws = slow.base
			end
			if ws > 0.01 then
				slow.base = ws
				slow.written = ws * MOVE_MUL
				hum.WalkSpeed = slow.written
			end
			if slow.dir then
				hum.AutoRotate = false
				slow.rotOff = true
				local want = CFrame.lookAt(Vector3.zero, slow.dir)
				local cur = hrp.CFrame - hrp.Position
				hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-28 * math.min(dt, 0.1)))
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- clips: Slash<n> / Slash<n>BK; swings 1-3 without the legs / Root while the caster is moving (cached per clip)
	local LEGS = { Root = true, LeftHip = true, RightHip = true, LeftKnee = true, RightKnee = true, LeftAnkle = true, RightAnkle = true }
	local legless = {}
	local function clipFor(combo, bankai, moving)
		local C = ctx.Clips or {}
		local clip = (bankai and C["Slash" .. combo .. "BK"]) or C["Slash" .. combo]
		if type(clip) ~= "table" or not moving then
			return clip
		end
		local v = legless[clip]
		if not v then
			v = { length = clip.length, fadeIn = clip.fadeIn, fadeOut = clip.fadeOut, strikeAt = clip.strikeAt, keys = {} }
			for _, k in ipairs(clip.keys) do
				local p = {}
				for j, val in pairs(k.pose) do
					if not LEGS[j] then
						p[j] = val
					end
				end
				if next(p) then
					table.insert(v.keys, { t = k.t, ease = k.ease, pose = p })
				end
			end
			legless[clip] = v
		end
		return v
	end

	---------------------------------------------------------------------------------------------------
	-- cast lifetime

	-- the blade-bound layers of a swing (glow, trails, sheen) and its flourish: dropped when a newer swing or another
	-- move takes the sword
	local function stopBlade(cast)
		cast.flourishOff = true
		for _, h in ipairs(cast.blade) do
			if type(h) == "table" and type(h.stop) == "function" then
				pcall(h.stop, h) -- trails and the glow fade out rather than vanish
			else
				kill(h)
			end
		end
		cast.blade = {}
	end

	local function finish(cast, now)
		if cast.dead then
			return
		end
		cast.dead = true
		for _, c in ipairs(cast.conns) do
			kill(c)
		end
		for _, h in ipairs(cast.handles) do
			kill(h)
		end
		for _, h in ipairs(cast.blade) do
			kill(h)
		end
		if now then
			for _, g in ipairs(cast.ghosts) do
				kill(g)
			end
			kill(cast.folder)
		end
		if casts[cast.key] == cast then
			casts[cast.key] = nil
		end
	end

	local function addGhost(cast, color, alpha, life)
		if not room(cast, 32, 0) then
			return
		end
		local g = shared("ghost", cast.char, color, alpha, life)
		if typeof(g) == "Instance" then
			table.insert(cast.ghosts, g)
		end
	end

	-- a blade-trail fallback when Shared has none: a Trail between the sword's TrailA / TrailB
	local function localTrail(info, c0, c1, life)
		if not (info and info.trailA and info.trailB) then
			return nil
		end
		local t = Instance.new("Trail")
		t.Attachment0, t.Attachment1 = info.trailA, info.trailB
		t.Color = ColorSequence.new(c0, c1)
		t.Lifetime = life
		t.LightEmission = 1
		t.LightInfluence = 0
		t.FaceCamera = false
		t.Transparency = NumberSequence.new(0.15, 1)
		t.WidthScale = NumberSequence.new(1, 0.2)
		t.Parent = info.handle
		return t
	end

	local function trail(cast, c0, c1, life, secs, width)
		local h = shared("bladeTrail", cast.char, c0, c1, life, secs, { black = cast.mode, width = width or 1 })
		if h == nil then
			h = localTrail(swordOf(cast.char), cast.mode and CRIMSON or c0, c1, life)
			if h then
				task.delay(secs, function()
					if h.Parent then
						h.Enabled = false
						Debris:AddItem(h, life + 0.05)
					end
				end)
			end
		end
		if h then
			table.insert(cast.blade, h)
			-- PERKS: the Trail Pack look on the main ribbon (the tip streak keeps the kit's colours)
			local main = (type(h) == "table" and type(h.trails) == "table" and h.trails[1]) or (typeof(h) == "Instance" and h) or nil
			perkTrail(cast.char, main)
		end
		return h
	end

	---------------------------------------------------------------------------------------------------
	-- geometry of each swing

	-- the slash arc frame (DESIGN 5.4), in the plane the blade sweeps - tipped so its face shows to the caster's
	-- camera (behind + above, looking along the aim): 1 and 2 pitch their far side up 16 / 12 deg (a flat arc seen
	-- from 20 deg above reads as a sliver), the vertical chop yaws 25 deg (a plane containing the aim is edge-on)
	local function arcFor(cast)
		local hrp, dir, combo = cast.hrp, cast.dir, cast.combo
		local right = dir:Cross(UP)
		local p = hrp.Position
		if combo == 1 then
			local c = p + right * 0.75 + UP * 0.3
			return CFrame.lookAt(c, c + dir) * CFrame.Angles(rad(16), 0, 0) * CFrame.Angles(0, 0, math.pi), 6.5, 150 -- R -> L
		elseif combo == 2 then
			local c = p + right * 0.75 + UP * 1.2
			return CFrame.lookAt(c, c + dir) * CFrame.Angles(rad(12), 0, 0) * CFrame.Angles(0, 0, rad(35)), 6.5, 150 -- low L -> high R
		elseif combo == 3 then
			local c = p + right * 0.35 + UP * 1.6
			local look = rotY(dir, -25)
			return CFrame.lookAt(c, c + look) * CFrame.Angles(0, 0, -math.pi / 2), 7, 140 -- overhead -> down front
		end
		-- swing 4: the whole turn, drawn the way he spins (left), ending out front-left where the blade stops
		local c = p + UP * 0.1
		local look = rotY(dir, -140)
		return CFrame.lookAt(c, c + look) * CFrame.Angles(0, 0, math.pi), 9, 340
	end

	-- the direction the blade travels through the strike (for streaks / sparks / the cut marks)
	local function sweepOf(dir, combo)
		local right = dir:Cross(UP)
		if combo == 1 then
			return (-right + dir * 0.3).Unit
		elseif combo == 2 then
			return (right + UP * 0.7 + dir * 0.3).Unit
		elseif combo == 3 then
			return (-UP + dir * 0.5).Unit
		end
		return (-right + dir * 0.4).Unit
	end

	---------------------------------------------------------------------------------------------------
	-- local effect builders

	-- the swept SHEET: a fan of light filling the cut between r0 and r1 in the arc's frame (same parametrisation and
	-- draw order as Shared.slashArc: from cf's -X side through its look to +X; the newest end is the densest). Two
	-- bands (outer brighter), each wedge fades tail-first; anything near the lens thins out (camFade). Black: dark
	-- SmoothPlastic smoke (never additive). o = { draw, hold, life, alpha, alpha2, step }
	local function sheet(cast, cf, r0, r1, sweepDeg, o)
		o = o or {}
		local n = math.clamp(math.ceil(sweepDeg / (o.step or 13)), 6, 26)
		if not room(cast, n * 2, 0) then
			n = math.max(6, math.floor(n / 2))
			if not room(cast, n * 2, 0) then
				return nil
			end
		end
		local black = cast.mode
		local sweep = rad(sweepDeg)
		local da = sweep / n
		local split = r0 + (r1 - r0) * 0.55
		local draw, hold, life = o.draw or 0.06, o.hold or 0.03, o.life or 0.3
		local a0, a1 = o.alpha or 0.62, o.alpha2 or 0.84
		if cast.isLocal then
			a0, a1 = a0 + 0.08, a1 + 0.05
		end
		local folder = Instance.new("Folder")
		folder.Name = "M1Sheet"
		local items = {}
		for i = 1, n do
			local u = (i - 0.5) / n
			local a = -sweep / 2 + da * (i - 0.5)
			local radial = Vector3.new(math.sin(a), 0, -math.cos(a))
			local tangent = Vector3.new(math.cos(a), 0, math.sin(a))
			for band = 1, 2 do
				local ra, rb = r0, split
				if band == 1 then
					ra, rb = split, r1
				end
				local rm = (ra + rb) / 2
				local len = 2 * rm * math.sin(da / 2) + 0.06
				local wcf = cf * CFrame.fromMatrix(radial * rm, tangent, UP)
				local base
				local c
				if band == 1 then
					base = a0 + (1 - a0) * 0.45 * (1 - u)
					c = black and SMOKE or cast.col.edge:Lerp(CORE, 0.35)
				else
					base = a1 + (1 - a1) * 0.4 * (1 - u)
					c = black and BLACK or FROST
				end
				local p = newPart("M1Sheet", black and PLASTIC or NEON, c, Vector3.new(len, 0.04, rb - ra + 0.04), wcf, 1, folder)
				table.insert(items, {
					p = p, base = camFade(p.Position, base, o.far), on = draw * (i - 1) / math.max(n - 1, 1),
					off = draw + hold + life * 0.4 * u, dur = life * (0.5 + 0.5 * u), st = 0,
				})
			end
		end
		folder.Parent = cast.folder
		local t0 = os.clock()
		local total = draw + hold + life * 1.4 + 0.05
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			if t > total or not folder.Parent then
				conn:Disconnect()
				folder:Destroy()
				return
			end
			for _, it in ipairs(items) do
				if t >= it.on then
					if t < it.off then
						if it.st == 0 then
							it.st = 1
							it.p.Transparency = it.base
						end
					else
						local k = math.clamp((t - it.off) / it.dur, 0, 1)
						it.p.Transparency = it.base + (1 - it.base) * k * k
					end
				end
			end
		end)
		table.insert(cast.conns, conn)
		Debris:AddItem(folder, total + 0.5)
		return folder
	end

	-- the edge flash: a bright sheen racing base -> tip along the cutting edge (a Beam on TrailA -> TrailB, which sit on
	-- the edge side of the blade, so it rides the swing for free)
	local function edgeSheen(cast, dur)
		local info = swordOf(cast.char)
		if not (info and info.trailA and info.trailB and live(info.handle)) then
			return
		end
		local bk = info.form == "Bankai"
		local b = Instance.new("Beam")
		b.Name = "M1EdgeSheen"
		b.Attachment0, b.Attachment1 = info.trailA, info.trailB
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 10
		b.Width0, b.Width1 = bk and 0.24 or 0.36, bk and 0.14 or 0.22
		b.Color = ColorSequence.new(cast.col.sheen, cast.col.edge)
		b.Transparency = NumberSequence.new(1)
		b.ZOffset = 0.2
		pcall(function()
			b.Brightness = 3
		end)
		b.Parent = info.handle
		table.insert(cast.blade, b)
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local k = (os.clock() - t0) / dur
			if k >= 1 or not b.Parent then
				conn:Disconnect()
				b:Destroy()
				return
			end
			local pk = -0.25 + 1.5 * k
			local glowAll = 0.8 + 0.2 * k -- the whole edge lit faintly while the sheen runs
			local kp = {}
			for i = 0, 8 do
				local x = i / 8
				local w = math.max(0, 1 - math.abs(x - pk) / 0.24)
				kp[#kp + 1] = NumberSequenceKeypoint.new(x, math.min(glowAll, 1 - 0.95 * w))
			end
			b.Transparency = NumberSequence.new(kp)
		end)
		table.insert(cast.conns, conn)
	end

	-- a small flat crescent of light for the swing-4 burst: CR_N segments along the crescent's mid-curve (tips along
	-- +/-Y, the convex side leading along -Z, thickness along X), each a core inside a wider sheath, fat in the middle
	-- and pointed at the tips. Black: a dark core with a crimson rim on the leading side. :place(cf, scale, fade)
	local CR_N = 7
	local function miniCrescent(cast, span, depth, thick)
		local black = cast.mode
		local folder = Instance.new("Folder")
		folder.Name = "M1Crescent"
		local h = span / 2
		local Ro = (h * h + depth * depth) / (2 * depth)
		local th = math.asin(math.clamp(h / Ro, -1, 1))
		local function at(u)
			local ang = th * u
			return Vector3.new(0, Ro * math.sin(ang), -depth + Ro * (1 - math.cos(ang)))
		end
		local band = depth * 0.5
		local segs = {}
		for i = 1, CR_N do
			local u0, u1 = -1 + 2 * (i - 1) / CR_N, -1 + 2 * i / CR_N
			local pa, pb = at(u0), at(u1)
			local mid = (pa + pb) / 2
			local tdir = (pb - pa).Unit
			local vY = Vector3.new(0, tdir.Z, -tdir.Y) -- across the band, toward the leading side at the middle
			local rot = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, vY)
			local w = math.max(1 - math.abs((u0 + u1) / 2) ^ 1.6, 0.14)
			local L = (pb - pa).Magnitude + 0.06
			local cSize = Vector3.new(thick * w, band * w, L)
			local core = newPart("CrCore", black and PLASTIC or NEON, black and BLACK or CORE, cSize, CFrame.identity, 1, folder)
			table.insert(segs, { p = core, pos = mid, rot = rot, size = cSize, base = black and 0.05 or 0.02 })
			local sSize, sPos
			if black then
				sSize = Vector3.new(thick * w * 1.25, math.max(band * w * 0.28, 0.06), L)
				sPos = mid + vY * band * w * 0.5
			else
				sSize = Vector3.new(thick * w * 1.7, band * w * 1.9, L)
				sPos = mid
			end
			local sheath = newPart("CrEdge", NEON, black and CRIMSON or cast.col.edge, sSize, CFrame.identity, 1, folder)
			table.insert(segs, { p = sheath, pos = sPos, rot = rot, size = sSize, base = black and 0.1 or 0.5 })
		end
		folder.Parent = cast.folder
		local self = { folder = folder }
		function self.place(_, cf, scale, fade)
			for _, s in ipairs(segs) do
				local p = s.p
				p.Size = s.size * scale
				p.CFrame = cf * CFrame.new(s.pos * scale) * s.rot
				local t = s.base + (1 - s.base) * fade
				p.Transparency = camFade(p.Position, t)
			end
		end
		function self.Destroy()
			folder:Destroy()
		end
		Debris:AddItem(folder, 2)
		return self
	end

	-- the crescent burst: flat crescents flung out of the spin at hip height (the lens-ward ones fainter and smaller)
	local function crescentBurst(cast, hip)
		local look = camCF().LookVector * FLATV
		look = look.Magnitude > 0.1 and look.Unit or cast.dir
		local list = {}
		for _, yaw in ipairs(cast.mode and { -40, 80, 200 } or { -40, 50, 140, 230 }) do -- mode: 3 (the wave flies too)
			if not room(cast, CR_N * 2 + 2, 1) then
				break
			end
			local tdir = rotY(cast.dir, yaw)
			local toward = cast.isLocal and tdir:Dot(look) < -0.4 -- flying back at the caster's camera
			local cr = miniCrescent(cast, 7, 1.7, 0.45)
			table.insert(cast.handles, cr)
			table.insert(list, { cr = cr, dir = tdir, s1 = toward and 0.85 or 1.3, a0 = toward and 0.45 or 0 })
		end
		if #list == 0 then
			return
		end
		local T = 0.28
		local t0 = os.clock()
		local tilt = CFrame.Angles(rad(30), 0, 0) * CFrame.Angles(0, 0, rad(90)) -- tips level, the face tipped up to the camera
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - t0) / T, 0, 1)
			local e = 1 - (1 - a) * (1 - a)
			for _, it in ipairs(list) do
				local pos = hip + it.dir * (3 + 12 * e) + UP * (0.4 + 1.4 * e) -- clears the 9-stud ring, rising
				local fade = math.clamp(it.a0 + (a - 0.5) / 0.5, it.a0, 1)
				pcall(it.cr.place, it.cr, CFrame.lookAt(pos, pos + it.dir) * tilt, 0.6 + (it.s1 - 0.6) * e, fade)
			end
			if a >= 1 then
				conn:Disconnect()
				for _, it in ipairs(list) do
					local pos = hip + it.dir * 15 + UP * 1.8
					if room(cast, 1, 1) then
						FX.sparks(cast.folder, pos, {
							count = 4, color = cast.col.spark, color2 = cast.col.edge, dir = it.dir, spread = 40,
							speed = { 10, 22 }, life = 0.3, size = 0.3,
						})
					end
					kill(it.cr)
				end
			end
		end)
		table.insert(cast.conns, conn)
	end

	-- the black slash wave (mode): a crescent racing out along the aim, its face turned to the caster's camera, a
	-- crimson cut line drawn behind it and a scorched scar under it, then a crimson split-burst where it stops
	local WAVE_TILT = { 90, 55, 0, 90 }
	local WAVE_FACE = {
		CFrame.Angles(rad(28), 0, 0), -- flat: the leading side lifted
		CFrame.Angles(0, rad(-28), 0) * CFrame.Angles(rad(14), 0, 0),
		CFrame.Angles(0, rad(-48), 0), -- the vertical chop's wave: yawed like Getsuga's FACE_YAW
		CFrame.Angles(rad(26), 0, 0),
	}
	local function slashWave(cast, range)
		local final = cast.combo >= 4
		local travel = final and (M1.FinalWaveTravel or 0.2) or (M1.WaveTravel or 0.12)
		local cr = shared("crescent", cast.folder, {
			span = final and 12 or 7, depth = final and 2.8 or 1.8, thick = final and 0.9 or 0.6,
			tilt = WAVE_TILT[cast.combo] or 90, black = true, core = BLACK, edge = CRIMSON,
			flames = room(cast, 45, final and 12 or 8), trails = true,
		})
		if type(cr) ~= "table" then
			return
		end
		table.insert(cast.handles, cr)
		local f = cast.folder
		local dir = cast.dir
		local origin = cast.hrp.Position + UP * 0.8 + dir * 1.5
		local dist = math.max(range - 1.5, 0)
		local endP = origin + dir * dist
		local face = WAVE_FACE[cast.combo] or WAVE_FACE[1]
		local host = cr.host
		if live(host) then
			ctx.sound("Whoosh", host, final and 0.75 or 0.55, final and 1.15 or 1.75)
		end
		-- the launch: a crimson flare at the blade + a dark ring pushed out along the aim
		FX.glow(f, origin, glowFor(origin, final and 3.4 or 2.4), EMBER, 0.14, { brightness = 2.4 })
		FX.ring(f, origin, dir, 0.6, (final and 6 or 4) * ringScale(origin), CRIMSON, 0.25, { alpha = cast.isLocal and 0.6 or 0.4 })
		-- the cut through the air, drawn as fast as the wave flies
		if dist > 1 and room(cast, 4, 0) then
			shared("slashLine", f, origin, endP, {
				width = final and 0.2 or 0.14, core = BLACK, edge = CRIMSON, draw = travel, hold = 0.04, life = 0.35, black = true,
			})
		end
		local t0 = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if cast.dead then
				conn:Disconnect()
				return
			end
			local a = dist > 0.1 and math.clamp((os.clock() - t0) / travel, 0, 1) or 1
			local pos = origin + dir * (dist * a)
			pcall(cr.place, cr, CFrame.lookAt(pos, pos + dir) * face, 0.65 + 0.45 * a)
			if a >= 1 then
				conn:Disconnect()
				pcall(cr.split, cr, dir)
				if room(cast, 2, 2) then
					FX.sparks(f, pos, { count = final and 12 or 6, color = CRIMSON, color2 = EMBER, dir = dir, spread = 45, speed = { 15, 38 }, life = 0.4, size = 0.38 })
					FX.glow(f, pos, glowFor(pos, final and 4 or 2.6), EMBER, 0.16, { brightness = 2.2 })
				end
				if room(cast, 1, 2) then
					shared("reiatsuFlame", f, pos, { count = final and 7 or 4, height = final and 3.4 or 2.2, size = final and 1 or 0.7,
						life = 0.5, color = BLACK, color2 = CRIMSON, black = true })
				end
				FX.ring(f, pos, dir, 1, (final and 8 or 5) * ringScale(pos), CRIMSON, 0.3, { alpha = 0.35 })
				if final and room(cast, 30, 2) then
					FX.ring(f, pos, UP, 1, 9, EMBER, 0.4, { alpha = 0.45 })
					shared("cracks", f, pos, 4, 2.8, CRIMSON, 1.1)
					FX.light(f, pos, CRIMSON, 3, 14, 0.3)
				end
			end
		end)
		table.insert(cast.conns, conn)
		-- the scorched scar along the wave's path
		if dist > 2 and room(cast, 4, 0) then
			shared("trench", f, origin - UP * 0.5, endP - UP * 0.5, {
				width = final and 1.5 or 0.7, black = true, seam = CRIMSON, life = final and 1.8 or 1.0, lips = final, depth = 8,
			})
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the blade burns through the swing: 0.3 -> 1 over the wind-up, held, then cools (swing 4: smoulders through the
	-- money hold, flares again with the twirl, out once the cleaver is back on his shoulder)
	local function glowLevel(cast, e)
		local W = cast.W
		if e < W then
			local a = math.clamp(e / W, 0, 1)
			return 0.3 + 0.7 * a * a
		end
		local t = e - (cast.shift or 0) -- clip time
		if t < W + 0.06 then
			return 1
		end
		if cast.combo < 4 then
			return math.max(1 - (t - W - 0.06) / 0.28, 0)
		end
		if t < TWIRL0 then
			return 1 - 0.5 * math.clamp((t - W - 0.06) / (TWIRL0 - W - 0.06), 0, 1)
		end
		if t < DROP_AT then
			return 0.55 + 0.12 * math.sin((t - TWIRL0) * 40)
		end
		return math.max(0.55 * (1 - (t - DROP_AT) / 0.28), 0)
	end

	local function startGlow(cast)
		local glow = shared("bladeGlow", cast.char, {
			color = cast.mode and BLACK or CORE, color2 = cast.col.edge, black = cast.mode, rate = 34, light = true,
		})
		if type(glow) ~= "table" then
			return
		end
		table.insert(cast.blade, glow)
		local peaked = false
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if cast.dead or cast.flourishOff then
				conn:Disconnect()
				return
			end
			local e = ctx.now() - cast.T0
			local k = glowLevel(cast, e)
			if e >= cast.W then
				peaked = true
			end
			if peaked and k <= 0 then
				conn:Disconnect()
				pcall(glow.stop, glow)
				return
			end
			pcall(glow.set, glow, k)
		end)
		table.insert(cast.conns, conn)
	end

	---------------------------------------------------------------------------------------------------
	-- the swing

	H.M1Swing = function(d)
		local char, player = ctx.charOf(d.userId)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		local combo = math.clamp(tonumber(d.combo) or 1, 1, 4)
		local W = tonumber(d.hitAt) or 0.14
		local T0 = tonumber(d.t0) or ctx.now()
		local e0 = ctx.now() - T0
		if e0 > W + 0.6 then
			return -- a late joiner: the swing is over
		end
		local isLocal = player == ctx.player
		local dist = ctx.camDist(hrp.Position)
		local dir = ctx.flat(typeof(d.dir) == "Vector3" and d.dir or hrp.CFrame.LookVector, hrp.CFrame.LookVector)
		local key = keyOf(d)
		if casts[key] then
			finish(casts[key], true)
		end
		-- a newer swing takes the sword: the older one's glow / trails / flourish stop
		local prev = lastCast[char]
		if prev and not prev.dead then
			stopBlade(prev)
		end
		local mode = d.mode == true
		local cast = {
			key = key, char = char, hrp = hrp, isLocal = isLocal, combo = combo, W = W, e0 = e0, T0 = T0, dir = dir,
			mode = mode, col = colours(mode), hits = 0, conns = {}, handles = {}, ghosts = {}, blade = {}, shift = 0,
		}
		casts[key] = cast
		lastCast[char] = cast
		H._stats.casts += 1
		local bankai = formOf(char) == "Bankai"

		-- the clip
		if isLocal or dist <= GATE_MID then
			local vel = hrp.AssemblyLinearVelocity * FLATV
			local moving = combo < 4 and vel.Magnitude > 3
			local clip = clipFor(combo, bankai, moving)
			local pt = lastTrack[char]
			if pt and type(pt.stop) == "function" then
				pcall(pt.stop, pt, 0.08)
			end
			cast.track = clip and ctx.playClip(char, clip, e0) or nil
			cast.clipLen = type(clip) == "table" and clip.length or 0.6
			lastTrack[char] = cast.track
		end
		-- the local caster's movement
		if isLocal then
			local fr = FREEZE[combo] or 0.04
			if combo >= 4 then
				endSlow()
				ctx.root(math.max(W + ROOT4 + fr - e0, 0.05), dir)
			else
				local secs = math.max(W + SLOW_EXTRA + fr - e0, 0.05)
				if type(ctx.slow) == "function" then
					ctx.slow(secs, MOVE_MUL, dir) -- the scaffold's own slow (it also applies it on this echo): no double x0.45
				else
					startSlow(dir, secs)
				end
			end
		end
		-- swing 4: another of his moves starting during the flourish (KitLocked true again after the swing's own lock
		-- let go) drops the twirl and the blade effects
		if combo >= 4 and typeof(player) == "Instance" then
			local sawFree = false
			table.insert(cast.conns, player:GetAttributeChangedSignal("KitLocked"):Connect(function()
				if player:GetAttribute("KitLocked") then
					if sawFree and not cast.flourishOff and ctx.now() - T0 > W + 0.12 then
						stopBlade(cast)
						local tr = cast.track
						if tr and lastTrack[char] == tr and type(tr.stop) == "function" then
							pcall(tr.stop, tr, 0.12)
						end
					end
				else
					sawFree = true
				end
			end))
		end
		if not isLocal and dist > GATE_FULL then
			task.delay(math.max(W - e0, 0) + 1.5, function()
				finish(cast, true)
			end)
			return
		end
		local rich = isLocal or dist <= GATE_RICH

		cast.folder = ctx.castFolder("M1_" .. key, 4)
		local f = cast.folder
		local col = cast.col
		local final = combo >= 4

		-- 0.00 the blade starts to burn; reiatsu licks rise off it
		at(cast, 0, function()
			startGlow(cast)
			local info = swordOf(char)
			if info and not final and room(cast, 1, 2) then
				shared("reiatsuFlame", f, wpos(info.mid, hrp.Position), {
					count = 4, height = 1.6, size = 0.55, life = 0.35,
					color = mode and BLACK or CORE, color2 = mode and CRIMSON or REI, black = mode,
				})
			end
		end)
		-- anticipation: streaks pulled into the blade, the wind-up glint at the tip
		if not final then
			at(cast, 0.02, function()
				local info = swordOf(char)
				if room(cast, 1, 1) then
					FX.streaks(f, wpos(info and info.mid, hrp.Position + dir * 2), {
						inward = 2.2, count = 7, color = mode and CRIMSON or FROST, color2 = col.edge, life = 0.1, size = 0.28,
					})
				end
			end)
		end
		at(cast, final and 0.06 or 0.05, function()
			local info = swordOf(char)
			local tip = info and wpos(info.tip)
			if tip then
				FX.sparks(f, tip, {
					count = 1, size = glowFor(tip, final and 1.6 or 1.3), life = 0.2, speed = { 0, 0.5 }, accel = Vector3.zero,
					drag = 0, color = mode and CRIMSON or WHITE, color2 = mode and EMBER or FROST, brightness = 3,
				})
			end
		end)
		-- 0.04 the blade trail: wide, and long enough to draw the whole cut
		at(cast, 0.04, function()
			local life = final and 0.32 or 0.22
			local secs = (W + (final and 0.16 or 0.12)) - 0.04
			trail(cast, mode and BLACK or CORE, col.edge, life, secs, final and 1.35 or 1.2)
		end)
		-- W - 0.08 the whoosh; W - 0.03 the edge flash
		at(cast, W - 0.08, function()
			ctx.sound("Whoosh", hrp, 0.6, 1.4 + 0.1 * combo)
		end)
		at(cast, W - 0.03, function()
			edgeSheen(cast, final and 0.11 or 0.08)
		end)

		-- swing 4: the gather, the coil, the spin
		if final then
			at(cast, 0.04, function()
				local g = FX.groundHit(hrp.Position, 6)
				local gp = g and g.Position or (hrp.Position - UP * 3)
				if rich and room(cast, 4, 4) then
					shared("dustRing", f, gp, 4.2, 3, -12, { life = 0.45, count = 1, s0 = 1.5, s1 = 4 }) -- dust drawn IN
				end
				if rich and room(cast, 4, 0) then
					local rocks = FX.liftRocks(f, gp, 3.6, 4)
					if type(rocks) == "table" then
						cast.rocks = rocks
						table.insert(cast.handles, { Destroy = function()
							pcall(rocks.drop, rocks)
						end })
					end
				end
				if isLocal then
					ctx.lean({ fov = -3, attack = 0.12, hold = 0.06, release = 0.1 }) -- the squeeze before the cleave
				end
			end)
			at(cast, 0.06, function()
				local info = swordOf(char)
				local mid = wpos(info and info.mid, hrp.Position)
				FX.streaks(f, mid, {
					inward = 3.4, count = 16, color = mode and CRIMSON or FROST, color2 = col.edge, life = 0.14, size = 0.36,
				})
				FX.arcs(f, mid, 1.4, { count = 2, color = mode and CRIMSON or REI, life = 0.08, width = 0.07 })
				ctx.sound("Whoosh", hrp, 0.45, 0.85)
			end)
			at(cast, 0.11, function()
				local info = swordOf(char)
				FX.arcs(f, wpos(info and info.mid, hrp.Position), 1.2, { count = 2, color = mode and EMBER or FROST, life = 0.07, width = 0.06 })
			end)
			at(cast, 0.12, function()
				local g = FX.groundHit(hrp.Position, 6)
				local gp = g and g.Position or (hrp.Position - UP * 3)
				if room(cast, 4, 4) then
					shared("dustRing", f, gp, 2, 4, 30, { life = 0.7, count = 1, s0 = 1.5, s1 = 4.5 })
				end
				local licks = mode and 2 or 3 -- a black lick is two emitters (smoke + crimson)
				for i = 0, licks - 1 do
					local a = i / licks * math.pi * 2 + math.pi / 4
					if room(cast, 1, mode and 2 or 1) then
						shared("reiatsuFlame", f, gp + Vector3.new(math.cos(a) * 1.6, 0.2, math.sin(a) * 1.6), {
							count = 3, height = 2.8, size = 0.75, life = 0.45, color = mode and BLACK or CORE,
							color2 = mode and CRIMSON or REI, black = mode,
						})
					end
				end
			end)
			for i, t in ipairs({ 0.17, 0.215, 0.26 }) do
				at(cast, t, function()
					if rich then
						addGhost(cast, mode and CRIMSON or FROST, 0.74, 0.13)
					end
					if i ~= 2 then
						ctx.sound("Whoosh", hrp, 0.35, 1.6 + 0.2 * i)
					end
					if i == 2 then
						local g = FX.groundHit(hrp.Position, 6)
						local gp = g and g.Position or (hrp.Position - UP * 3)
						FX.ring(f, gp + UP * 0.15, UP, 1, 6, col.edge, 0.25, { alpha = 0.5 }) -- the spin's wind ring
					end
				end)
			end
		end

		-- W the strike
		at(cast, W, function()
			local info = swordOf(char)
			local mid = wpos(info and info.mid, hrp.Position + dir * 3)
			local tip = wpos(info and info.tip, hrp.Position + dir * 5)
			local cf, radius, sweep = arcFor(cast)
			if final and isLocal then
				radius = 8.2 -- the ring passes between his camera and him: a little tighter and slimmer for the caster
			end
			cast.arcN = cf.UpVector
			local sw = sweepOf(dir, combo)
			-- the arc: hot core, coloured sheath, haze, smear; then an echo inside it
			shared("slashArc", f, cf, radius, {
				sweep = sweep, width = final and (isLocal and 1.15 or 1.4) or 1.0, thick = 0.14, core = col.core, edge = col.edge,
				draw = final and 0.08 or 0.06, life = final and 0.55 or 0.38, layers = 3, black = mode,
			})
			if not final then
				task.delay(0.025, function()
					if not cast.dead and room(cast, 16, 0) then
						shared("slashArc", f, cf * CFrame.new(0, 0.25, 0), radius * 0.8, {
							sweep = sweep * 0.9, width = 0.42, thick = 0.06, core = col.edge, edge = col.edge, draw = 0.07,
							life = 0.24, layers = 1, glint = false, smear = false, black = mode,
						})
					end
				end)
			end
			-- the swept sheet of light filling the cut
			if rich then
				if final then
					sheet(cast, cf, 4.4, radius - 0.2, sweep, { draw = 0.08, hold = 0.03, life = 0.36, alpha = 0.66, alpha2 = 0.86, step = 18, far = 20 })
				else
					sheet(cast, cf, radius * 0.35, radius * 0.98, sweep, { draw = 0.06, hold = 0.02, life = 0.26 })
				end
			end
			-- air cut along the swing
			if room(cast, 1, 1) then
				FX.streaks(f, mid, {
					dir = sw, spread = 14, count = final and 12 or 9, speed = { 45, 85 }, life = 0.2, size = 0.36,
					color = col.spark, color2 = col.edge,
				})
			end
			if not final then
				-- the release ring in the swing plane, two afterimages
				if room(cast, 1, 1) then
					local n = cast.arcN
					FX.ring(f, mid, n, 0.5, 4.5 * ringScale(mid), col.ring, 0.25, { alpha = cast.isLocal and 0.55 or 0.4 })
				end
				if rich then
					addGhost(cast, mode and CRIMSON or FROST, 0.78, 0.16)
					task.delay(0.05, function()
						if not cast.dead then
							addGhost(cast, mode and CRIMSON or ICE, 0.86, 0.14)
						end
					end)
				end
			end
			local g = FX.groundHit(hrp.Position, 6)
			local gp = g and g.Position or nil
			-- swings 1-2: the lead foot scuffs the ground
			if combo <= 2 and gp then
				if room(cast, 1, 1) then
					shared("dust", f, gp + dir * 1.2 + UP * 0.3, dir * 6 - sw * 3 + UP * 3, { count = 2, life = 0.9, s0 = 1.5, s1 = 4.5 })
				end
				if room(cast, 1, 1) then
					FX.ring(f, gp + dir * 1.2 + UP * 0.12, UP, 0.5, 3.6, col.edge, 0.25, { alpha = 0.55 })
				end
			end
			-- swing 3: the chop bites the ground under the tip, and splits the air in front of him
			if combo == 3 then
				local tg = FX.groundHit(tip, 3)
				if tg and tip.Y - tg.Position.Y < 3 then
					local tp = tg.Position
					shared("cracks", f, tp, 5, 3, mode and CRIMSON or REI, 0.9)
					shared("trench", f, tp - dir * 0.6, tp + dir * 3.2, { width = 1.1, seam = mode and CRIMSON or REI, black = mode, life = 1.4, lips = false })
					FX.ring(f, tp + UP * 0.05, UP, 0.5, 4.5, col.edge, 0.3, { alpha = 0.4 })
					if room(cast, 1, 2) then
						shared("dust", f, tp, dir * 8 + UP * 5, { count = 2, life = 1.0, s0 = 2, s1 = 6 })
						FX.sparks(f, tp + UP * 0.2, { count = 8, color = col.spark, color2 = col.spark2, dir = (UP + dir).Unit, spread = 30, speed = { 12, 28 }, life = 0.38, size = 0.36 })
					end
					if rich and room(cast, 3, 0) then
						FX.rubble(f, tp, { count = 3, out = { 4, 10 }, up = { 10, 18 }, radius = 1, life = 1.1, min = 0.3, max = 0.7, dir = dir })
					end
				end
				if room(cast, 3, 0) then
					local slit = hrp.Position + dir * 4.5
					shared("slashLine", f, slit + UP * 4.2, slit - UP * 2.8, {
						width = 0.18, core = mode and BLACK or WHITE, edge = col.edge, draw = 0.04, hold = 0.05, life = 0.3, black = mode,
					})
				end
				if isLocal then
					ctx.lean({ fov = 2, attack = 0.03, release = 0.2 })
				end
			end
			-- mode: the slash wave
			if mode and type(d.wave) == "number" then
				slashWave(cast, d.wave)
			end
			-- swing 4: the cleave lands
			if final then
				local gpos = gp or (hrp.Position - UP * 3)
				local hip = hrp.Position - UP * 0.4
				local right = dir:Cross(UP)
				-- shock rings in three planes + one on the ground
				FX.ring(f, hip, UP, 2, 16, col.edge, 0.4, { alpha = 0.3 })
				task.delay(0.03, function()
					if not cast.dead and room(cast, 1, 1) then
						FX.ring(f, hip + UP * 0.2, (UP * math.cos(rad(25)) + right * math.sin(rad(25))).Unit, 1.5, 12, mode and EMBER or FROST, 0.35, { alpha = 0.42 })
					end
				end)
				task.delay(0.05, function()
					if not cast.dead and room(cast, 1, 1) then
						FX.ring(f, gpos + UP * 0.2, UP, 1, 11, mode and EMBER or FROST, 0.35, { alpha = 0.45 })
					end
				end)
				task.delay(0.07, function()
					if not cast.dead and room(cast, 1, 1) then
						FX.ring(f, hip + UP * 0.4, (UP * math.cos(rad(25)) - right * math.sin(rad(25))).Unit, 1.5, 10, col.edge, 0.35, { alpha = 0.5 })
					end
				end)
				-- the crescent burst flung out of the spin
				if rich then
					crescentBurst(cast, hip)
				end
				-- a ring of flame off the cleave
				if room(cast, 1, mode and 2 or 1) then
					shared("reiatsuFlame", f, gpos + UP * 0.3, { count = 10, height = 3.6, size = 0.9, life = 0.5, spread = 40,
						color = mode and BLACK or CORE, color2 = mode and CRIMSON or REI, black = mode })
				end
				FX.light(f, hip, col.edge, 5, 20, 0.35)
				FX.rubble(f, gpos, { count = 8, out = { 8, 20 }, up = { 14, 28 }, radius = 2, life = 1.6 })
				if cast.rocks then
					pcall(cast.rocks.drop, cast.rocks, dir * 22)
					cast.rocks = nil
				end
				if room(cast, 40, 0) then
					shared("cracks", f, gpos, 6, 4.5, mode and CRIMSON or REI, 1.4)
				end
				if rich and room(cast, 4, 4) then
					shared("dustRing", f, gpos, 2.5, 4, 26, { life = 0.8, count = 1, s0 = 2, s1 = 5.5 })
				end
				ctx.sound("Boom", hrp, 0.5, 1.4)
				if cast.isLocal then
					ctx.shake(0.6, 0.32, 24, 5)
					ctx.lean({ fov = 6, attack = 0.03, hold = 0.05, release = 0.35 })
					pcall(FX.speedLines, 0.26, { alpha = 0.3, count = 40, inner = 0.55, color = mode and CRIMSON or WHITE })
				end
			end
		end)

		-- swings 1-3: the chiburi, on the clip's FLICK key - droplets of light flicked off the tip
		if not final then
			late(cast, FLICK_AT[combo] or 0.455, function()
				if cast.flourishOff then
					return
				end
				local info = swordOf(char)
				local tip = info and wpos(info.tip)
				if tip and room(cast, 2, 2) then
					local right = dir:Cross(UP)
					FX.sparks(f, tip, {
						count = 6, color = col.spark, color2 = col.edge, dir = (right * 0.8 - UP * 0.5 + dir * 0.2).Unit, spread = 25,
						speed = { 12, 22 }, life = 0.35, size = 0.24, accel = Vector3.new(0, -40, 0),
					})
					FX.sparks(f, tip, { count = 1, size = glowFor(tip, 0.9), life = 0.12, speed = { 0, 0.3 }, accel = Vector3.zero,
						drag = 0, color = mode and CRIMSON or WHITE, color2 = col.edge, brightness = 2.5 })
				end
				ctx.sound("Whoosh", hrp, 0.22, 2.3)
			end)
		end

		-- swing 4: the aftermath and THE TWIRL
		if final then
			late(cast, W + 0.15, function()
				local g = FX.groundHit(hrp.Position, 6)
				local gp = g and g.Position or (hrp.Position - UP * 3)
				if room(cast, 1, 1) then
					FX.ring(f, gp + UP * 0.1, UP, 8, 12, col.edge, 1.2, { alpha = 0.72 }) -- the residual ring
				end
			end)
			for i, t in ipairs({ W + 0.1, W + 0.35 }) do
				at(cast, t, function()
					local i2 = swordOf(char)
					if i2 and room(cast, 1, 1) then
						FX.sparks(f, wpos(i2.mid, hrp.Position), {
							count = 6, speed = { 2, 6 }, accel = UP * 3, drag = 1, life = 0.8, size = 0.25,
							color = col.spark, color2 = col.edge, spread = 60, dir = UP,
						})
					end
					if i == 2 and room(cast, 2, 2) then
						local g = FX.groundHit(hrp.Position, 6)
						local gp = g and g.Position or (hrp.Position - UP * 3)
						shared("dust", f, gp + dir * 1.5, UP * 1.5 + dir * 1.5, { count = 2, life = 1.8, s0 = 3, s1 = 7 }) -- the settle
					end
				end)
			end
			at(cast, W + 0.25, function()
				local g = FX.groundHit(hrp.Position, 6)
				local gp = g and g.Position or (hrp.Position - UP * 3)
				local wisps = mode and 2 or 3
				for i = 1, wisps do
					local a = i / wisps * math.pi * 2 + 0.6
					if room(cast, 1, mode and 2 or 1) then
						shared("reiatsuFlame", f, gp + Vector3.new(math.cos(a) * 3, 0.1, math.sin(a) * 3), {
							count = 3, height = 2.6, size = 0.55, life = 0.9, color = mode and BLACK or CORE,
							color2 = mode and CRIMSON or REI, black = mode,
						})
					end
				end
			end)
			at(cast, W + 0.6, function()
				if room(cast, 1, 1) then
					FX.sparks(f, hrp.Position - UP * 1.5, {
						count = 8, speed = { 1, 4 }, accel = UP * 4, drag = 1.2, life = 1.2, size = 0.2, spread = 80, dir = UP,
						color = mode and EMBER or FROST, color2 = col.edge,
					})
				end
			end)
			-- the twirl: the cleaver spins flat over his head (clip 0.50-0.80)
			late(cast, TWIRL0, function()
				if cast.flourishOff then
					return
				end
				trail(cast, mode and BLACK or CORE, col.edge, 0.09, TWIRL1 - TWIRL0 + 0.02, 0.9)
			end)
			for i, t in ipairs({ 0.53, 0.69 }) do
				late(cast, t, function()
					if not cast.flourishOff then
						ctx.sound("Whoosh", hrp, 0.32, 1.85 + 0.15 * i)
					end
				end)
			end
			for _, t in ipairs({ 0.555, 0.665, 0.775 }) do
				late(cast, t, function()
					if cast.flourishOff then
						return
					end
					local info = swordOf(char)
					local tip = info and wpos(info.tip)
					if tip and room(cast, 2, 2) then
						FX.sparks(f, tip, { count = 1, size = glowFor(tip, 1.1), life = 0.14, speed = { 0, 0.3 }, accel = Vector3.zero,
							drag = 0, color = mode and CRIMSON or WHITE, color2 = col.edge, brightness = 2.6 })
						FX.sparks(f, tip, { count = 4, color = col.spark, color2 = col.edge, speed = { 6, 14 }, life = 0.35,
							size = 0.2, accel = Vector3.new(0, -20, 0) })
					end
				end)
			end
			late(cast, 0.62, function()
				if cast.flourishOff then
					return
				end
				local head = char:FindFirstChild("Head")
				local p = (head and head.Position or hrp.Position + UP * 1.5) + UP * 2.2
				if room(cast, 1, 1) then
					FX.ring(f, p, UP, 1, 7 * ringScale(p), col.edge, 0.3, { alpha = 0.55 })
				end
			end)
			late(cast, DROP_AT, function()
				if cast.flourishOff then
					return
				end
				local info = swordOf(char)
				local m = info and wpos(info.base)
				if m and room(cast, 1, 1) then
					FX.sparks(f, m, { count = 1, size = glowFor(m, 1.0), life = 0.14, speed = { 0, 0.3 }, accel = Vector3.zero,
						drag = 0, color = mode and CRIMSON or WHITE, color2 = col.edge, brightness = 2.4 })
				end
			end)
		end

		task.delay(math.max(W - e0, 0) + 2.4, function()
			finish(cast, false)
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- a body is cut

	H.M1Hit = function(d)
		local model = d.model
		local tor = torsoOf(model)
		local pos = typeof(d.pos) == "Vector3" and d.pos or (tor and tor.Position)
		if not pos then
			return
		end
		local cast = casts[keyOf(d)]
		local _, player = ctx.charOf(d.userId)
		local isLocal = player == ctx.player
		local combo = math.clamp(tonumber(d.combo) or (cast and cast.combo) or 1, 1, 4)
		local final = d.final == true
		local wave = d.wave == true
		local mode = d.mode == true
		local col = colours(mode)

		-- the bite, riding the body (no anchor parts per hit)
		if tor then
			if final and not wave then
				ctx.sound("HitHeavy", tor, 0.9, 1.0)
				ctx.sound("Hit", tor, 0.6, 1.2)
			else
				ctx.sound("Hit2", tor, wave and 0.55 or 0.75, 1.0 + 0.08 * combo)
			end
		else
			ctx.soundAt(final and "HitHeavy" or "Hit2", pos, 0.75, 1.0 + 0.08 * combo)
		end
		-- once per swing: the hit-stop on every client (later clip beats slip with it), the caster's camera kick
		if cast and not wave then
			if not cast.froze then
				cast.froze = true
				if cast.track then
					ctx.freeze(cast.track, FREEZE[combo] or 0.04)
					cast.shift = FREEZE[combo] or 0.04
				end
			end
			if isLocal and not cast.shook then
				cast.shook = true
				ctx.shake(final and 0.3 or 0.2, 0.12, 30, 0)
				if false and final and type(ctx.impact) == "function" then -- orchestrator: off (every-combo impact frame washed the screen)
					-- the money frame: one impact frame (the flash is capped at 0.25 by the scaffold)
					pcall(ctx.impact, { lines = false, flash = mode and CRIMSON or WHITE, flashAlpha = 0.12, flashLife = 0.14 })
				end
			end
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the finisher's "×1" hit tally
		-- under the title card is gone; the separate ComboCounter HUD is untouched)
		if not isLocal and ctx.camDist(pos) > GATE_FULL then
			return
		end
		local f = (cast and live(cast.folder)) and cast.folder or ctx.castFolder("M1Hit", 2)
		local n = 1
		if cast then
			cast.hits += 1
			n = cast.hits
		end
		local full = n <= 2
		local dir = typeof(d.dir) == "Vector3" and d.dir or (cast and cast.dir) or Vector3.zAxis
		local fdir = ctx.flat(dir, Vector3.zAxis)
		if full or not cast or room(cast, 1, 1) then
			FX.glow(f, pos, glowFor(pos, (full and 3.2 or 1.6) * (wave and 0.75 or 1)), col.glow, 0.14, { brightness = 2.5 })
		end
		-- the rest is budgeted per layer: a crowd of bodies falls back to the light set (glow, one cut, sparks)
		if cast and not room(cast, 6, 1) then
			return
		end
		if full and cast and not room(cast, 16, 7) then
			full = false
		end
		if full then
			FX.glow(f, pos, glowFor(pos, final and 6 or 4.6), col.edge, 0.22, { alpha = 0.5, brightness = 1.6 })
		end
		local cam = camCF()
		local r, u = cam.RightVector, cam.UpVector
		if wave then
			-- the wave's cut: one crimson slash + black flames bursting off the body
			local k = 1.5
			shared("slashLine", f, pos - (r + u * 0.4) * k, pos + (r + u * 0.4) * k, {
				width = 0.14, core = BLACK, edge = CRIMSON, draw = 0.03, hold = 0.04, life = 0.3, black = true,
			})
			if full and (not cast or room(cast, 1, 2)) then
				shared("reiatsuFlame", f, pos, { count = 4, height = 2.2, size = 0.7, life = 0.4, color = BLACK, color2 = CRIMSON, black = true })
			end
			FX.sparks(f, pos, { count = 6, color = CRIMSON, color2 = EMBER, dir = fdir, spread = 40, speed = { 18, 40 }, life = 0.35, size = 0.36 })
			return
		end
		-- the X across the torso, facing the camera, and a lingering cut mark along the swing
		local k = 1.7 / math.sqrt(2)
		local lineO = { width = 0.15, core = mode and BLACK or WHITE, edge = col.edge, draw = 0.03, hold = 0.04, life = 0.3, black = mode }
		local l1 = shared("slashLine", f, pos - (r + u) * k, pos + (r + u) * k, lineO)
		if full then
			task.delay(0.03, function()
				shared("slashLine", f, pos - (r - u) * k, pos + (r - u) * k, lineO)
			end)
		end
		if full then
			local sw = sweepOf(fdir, combo)
			local L = final and 2.8 or 2.2
			shared("slashLine", f, pos - sw * L, pos + sw * L, {
				width = 0.11, core = mode and BLACK or CORE, edge = col.edge, draw = 0.05, hold = 0.14, life = 0.5, black = mode,
			})
		end
		if final and n == 1 then
			-- the first body's cut shatters into glints
			task.delay(0.12, function()
				if type(l1) == "table" and type(l1.shatter) == "function" then
					pcall(l1.shatter, l1)
				end
			end)
		end
		-- sparks: white stars along the cut + an ice spray across it
		FX.sparks(f, pos, {
			count = full and 9 or 4, color = col.spark, color2 = col.spark2, dir = fdir, spread = 35, speed = { 20, 48 },
			life = 0.4, size = 0.45,
		})
		if full then
			FX.sparks(f, pos, {
				count = 6, color = mode and EMBER or WHITE, color2 = mode and CRIMSON or ICE, dir = (fdir:Cross(UP) + UP * 0.4).Unit,
				spread = 70, speed = { 14, 30 }, life = 0.32, size = 0.3,
			})
			-- rings in two planes: facing the camera (scaled near the lens) and in the swing plane
			local toCam = cam.Position - pos
			local normal = toCam.Magnitude > 0.1 and toCam.Unit or UP
			FX.ring(f, pos, normal, 1, 6 * ringScale(pos), col.ring, 0.25, { alpha = isLocal and 0.4 or 0.25 })
			FX.ring(f, pos, (cast and cast.arcN) or UP, 0.8, 5.5, col.edge, 0.3, { alpha = 0.35 })
			-- reiatsu bursting off the body
			if not cast or room(cast, 1, mode and 2 or 1) then
				shared("reiatsuFlame", f, pos, { count = 5, height = 2.6, size = 0.7, life = 0.45, dir = (UP + fdir * 0.6).Unit,
					spread = 30, color = mode and BLACK or CORE, color2 = mode and CRIMSON or REI, black = mode })
			end
			if n == 1 then
				FX.light(f, pos, col.edge, 3.5, 14, 0.18)
			end
		end
		-- swing 4: an energy shell bursts on the first body, streaks fly off it, and the body drags a comet trail
		if final then
			if n == 1 then
				FX.shell(f, pos, 0.4, 2.4, mode and CRIMSON or CORE, 0.16)
			end
			if full then
				FX.streaks(f, pos, { count = 10, color = col.spark, color2 = col.edge, speed = { 40, 70 }, life = 0.22, size = 0.32 })
			end
			if tor then
				local t = FX.trail(tor, mode and CRIMSON or FROST, 1.3, 0.32, { alpha = 0.1 })
				if t then
					local a0, a1 = t.Attachment0, t.Attachment1
					task.delay(0.55, function()
						if t.Parent then
							t.Enabled = false
						end
						task.delay(0.35, function()
							kill(t)
							kill(a0)
							kill(a1)
						end)
					end)
				end
			end
		end
	end

	H.M1Cancel = function(d)
		local cast = casts[keyOf(d)]
		if not cast then
			return
		end
		if cast.track and type(cast.track.stop) == "function" then
			pcall(cast.track.stop, cast.track, 0.1)
		end
		if cast.isLocal then
			endSlow()
		end
		finish(cast, true)
	end

	H.__reset = function()
		endSlow()
		for _, cast in pairs(casts) do
			if cast.isLocal then
				finish(cast, true)
			end
		end
	end

	return H
end
