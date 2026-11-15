--!nocheck
-- ZangetsuKit.Client.Hollow (owner: hollow): playback of R, HOLLOW MASK 虚化 (DESIGN 8.4, FLAIR pass) on every client.
-- Server beats come in the HollowCast payload (times are seconds after t0); everything else is laid on that clock
-- (normal; Tensa Zangetsu in brackets where it differs):
--   0.00        callout, root, clip HollowMask, a low Drone; the caster's camera squeezes in
--   0.06-0.44   THE VEINS: black-red reiatsu veins crawl out from under his palm across his face (8, drawn segment by
--               segment), dark reiatsu seeps off it, three dark ribbons start orbiting his head, black flames rise
--   0.22-0.38   the mask's SHAPE congeals on his face in dark reiatsu (a dark film where each plate will sit)
--   0.36-0.75   THE PLATES crack into place: 8 bone fragments fly in and slam onto the film (a crack, a bone glint and
--               crimson sparks as each lands); the ground trembles and pebbles lift round his feet
--   0.76-0.86   the red stripes BURN IN down his left side, top to bottom, a glowing tip leading each one
--   0.80        the inhale: reiatsu and ground dust are dragged IN to him, the ribbons tighten
--   0.86        the EYES IGNITE: gold on black, flickering on, a gold flare across each
--   0.95        THE ROAR (money frame 1): flat shock rings + dark smoke rings, vertical rings in 2 planes, a camera ring,
--               a distortion shell, a cone of streaks out of his mouth, ground shock lines, a black-red blast, the
--               lifted rocks hurled out + two rubble waves, glowing cracks, a black flame eruption, impact frame, shake
--   1.12-2.05   THE BLITZ CAMERA (caster only): an orbit round the victim, pushing in
--   each slash  he blinks to the next spot (a flickering afterimage + an echo along the path, flashes and a star glint
--               at both ends, a streak between), hangs there, cuts: a black arc whose edge is a NEW colour every cut
--               (crimson, bone, blood, gold, ember...) doubled by a thinner afterimage arc, a cut line in that colour, a
--               glow, sparks, a glint, a ring, a 0.03 hit-stop
--   2.00 [2.10] THE CHARGE at F (0.30 s): reiatsu streaks and slivers rush INTO the blade, a gathering glow on the edge
--               grows, crimson arcs crawl over it, black flames lick off him; the finisher camera pushes in, FOV squeezed
--   2.30 [2.40] THE FINISHER (money frame 2): 0.16 hit-stop; a black-red explosion (a crimson fireball round a black
--               core, two waves of dark smoke), rays, a burst of crescents round the impact, rings in 3 planes, the
--               point-blank crescent tearing down the line (yawed so its face reads from behind), the victim on a
--               crimson comet with black flames bursting off it, a ground crater (scorch, glowing core, cracks, rim
--               flames, dust, rubble), the trench; then a residual ring and rising embers; FOV kick + shake
--   ~2.52       he drops (exitVel) and lands at 2.64 [2.74]: HollowLand, a ring, dust, a thud; the camera swings round
--               to his face
--   2.74 [2.84] CRACK: 5 glowing cracks run across the mask, red light leaks out, flecks fall, the eyes flicker
--   3.19 [3.29] SHATTER: the mask bursts - its own pieces fly out, slow, drift and BURN away (bone -> ember -> char,
--               shedding embers, shrinking) over 1.7 s; shards, ash, a black-red puff; the eyes go out in two gold
--               streaks; the caster's camera hands back
--   3.59 [3.69] CHIBURI: the blade flicked clean - a blood spray off it, a splatter line on the ground, a small arc
--   -> ~5.4     black wisps trail off his face, reiatsu smoke rises off his shoulders, embers drift, the trench smokes
-- Bankai variant (payload mode / the Bankai form): the _BK clips, 8 slashes (payload), a black blade glow through the
-- blitz, two arcs and a second crimson ring every cut, a bigger roar (x1.25, an extra ring, a flame pillar), a bigger
-- finisher (x1.3: crescent span 18, 16 rays, 4 burst crescents, a wider crater), more shards at the shatter.
-- Gating (camera distance to the caster): <= Full (160) everything; <= Reduced (250) no veins / film / swirl ribbons /
-- flame licks / blitz streak lines / rays / converging slivers; beyond: the mask (formed at once), roar rings, slash
-- arcs, the crescent and the sounds only.
-- Budget: a part governor (cast folder + its afterimages) skips optional layers past PartBudget (360; hero layers to
-- HeroCap 400); repeated per-beat bursts (slash glow / sparks / rings, relocation flashes, swirl sparks, plate glints,
-- stripe tips, the burn embers) are one moved emitter each (one emit per frame) so the live emitter count stays low.
return function(ctx)
	local H = {}
	local Debris = game:GetService("Debris")

	local FX = ctx.FX
	local S = ctx.S or {}
	local PAL = ctx.PAL or {}
	local CFG = ctx.CFG or {}
	local HC = type(CFG.Hollow) == "table" and CFG.Hollow or {}
	local FL = type(HC.Flair) == "table" and HC.Flair or {}
	local SwordMod = ctx.Sword
	local UP = ctx.UP or Vector3.yAxis
	local FLATV = Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local TAU = math.pi * 2
	local TEX = FX.TEX or {}
	local nsk = FX.nsk
	local rng = Random.new()
	local C3 = Color3.fromRGB
	local NEON, PLASTIC = Enum.Material.Neon, Enum.Material.SmoothPlastic
	local BULK = Enum.BulkMoveMode.FireCFrameChanged

	local BONE = PAL.Bone or C3(245, 242, 232)
	local HOL = PAL.Hollow or C3(255, 34, 34)
	local HDARK = PAL.HollowDark or C3(28, 0, 6)
	local GOLD = PAL.EyeGold or C3(255, 214, 40)
	local CRIM = PAL.Crimson or C3(220, 20, 40)
	local EMBER = PAL.Ember or C3(255, 90, 60)
	local BLACK = PAL.Black or C3(14, 10, 14)
	local SMOKE = PAL.Smoke or C3(36, 30, 34)
	local CORE = PAL.Core or C3(240, 250, 255)
	local BLOOD = PAL.Blood or C3(110, 0, 18)

	local function num(v, d)
		return type(v) == "number" and v or d
	end
	local FULL, REDUCED = num(FL.Full, 160), num(FL.Reduced, 250)
	local BUDGET = num(FL.PartBudget, 360)
	local HERO_CAP = num(FL.HeroCap, 400)
	local CRAWL_FROM, VEIN_STAGGER, VEIN_DRAW = num(FL.CrawlFrom, 0.06), num(FL.VeinStagger, 0.035), num(FL.VeinDraw, 0.20)
	local FILM_AT, FILM_IN = num(FL.FilmAt, 0.22), num(FL.FilmIn, 0.16)
	local FORM_AT, STAGGER, FLY = num(FL.MaskFormAt, 0.36), num(FL.MaskStagger, 0.035), num(FL.MaskFly, 0.14)
	local STRIPES_AT, STRIPE_DRAW = num(FL.StripesAt, 0.76), math.max(num(FL.StripeDraw, 0.10), 0.02)
	local EYES_AT, INHALE_AT = num(FL.EyesAt, 0.86), num(FL.InhaleAt, 0.80)
	local SWIRL_FROM, SWIRL_TO = num(FL.SwirlFrom, 0.10), num(FL.SwirlTo, 0.82)
	local SHOT_LEAD = num(FL.ShotLead, 0.08)
	local SHOT_R, SHOT_R1, SHOT_H, SHOT_SWEEP = num(FL.ShotRadius, 15), num(FL.ShotRadiusEnd, 12.5), num(FL.ShotHeight, 5), num(FL.ShotSweep, 70)
	local WAVE_TIME = num(FL.WaveTime, 0.25)
	local BURN_LIFE = num(FL.BurnLife, 1.7)
	local CHIBURI_AT = num(FL.ChiburiAt, 0.95)
	local FACE_YAW = math.rad(-50) -- the finisher crescent turned so its face shows to the camera behind / right of him
	local TweenService = game:GetService("TweenService")
	-- a new edge colour every cut of the blitz (black core, this rim)
	local CUT_COLORS = { HOL, BONE, BLOOD, GOLD, EMBER, BONE, CRIM, GOLD }

	local casts = {} -- ["userId#id"] = cast record
	local frame = 0
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	---------------------------------------------------------------------------------------------------
	-- helpers
	local warned = {}
	local function try(tag, fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			if not warned[tag] then
				warned[tag] = true
				warn("[Zangetsu.Hollow] " .. tag .. ": " .. tostring(r))
			end
			return nil
		end
		return r
	end
	local function SH(name, ...)
		return try(name, S[name], ...)
	end
	local function call(obj, method, ...)
		if type(obj) == "table" and type(obj[method]) == "function" then
			return try(method, obj[method], obj, ...)
		elseif typeof(obj) == "Instance" and method == "Destroy" then
			obj:Destroy()
		end
	end

	local function partOf(char, name)
		local p = char and char.Parent and char:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p or nil
	end
	local function torsoOf(m)
		return typeof(m) == "Instance" and m.Parent and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")) or nil
	end
	local function flat(v, fb)
		return ctx.flat(v, fb or Vector3.new(0, 0, -1))
	end
	local function groundAt(pos)
		local y = ctx.groundY(pos)
		return Vector3.new(pos.X, y or (pos.Y - 3.2), pos.Z), y ~= nil
	end
	local function glowFor(pos, size)
		if type(S.glowFor) == "function" then
			local ok, v = pcall(S.glowFor, pos, size)
			if ok and type(v) == "number" then
				return v
			end
		end
		return size * math.clamp(ctx.camDist(pos) / 30, 0.45, 1)
	end
	-- camera-facing rings near the lens are drawn smaller (no white-outs)
	local function camK(pos)
		return math.clamp(ctx.camDist(pos) / 30, 0.6, 1)
	end
	local function tierOf(pos)
		local d = ctx.camDist(pos)
		return (d <= FULL and 1) or (d <= REDUCED and 2) or 3
	end
	local function cs(a, b)
		return ColorSequence.new(a, b or a)
	end
	local function hrpPos(c)
		local h = partOf(c.char, "HumanoidRootPart")
		return h and h.Position or c.origin
	end
	-- sounds ride a part that already exists (his root part by default): no 8-second anchor parts per hit
	local function snd(c, key, vol, pitch, part)
		local p = part or partOf(c.char, "HumanoidRootPart")
		if p then
			try("sound", ctx.sound, key, p, vol, pitch)
		else
			try("soundAt", ctx.soundAt, key, c.origin, vol, pitch)
		end
	end

	-- the part governor: the cast folder plus its live afterimages
	local function partsNow(c)
		local n = 0
		if c.f and c.f.Parent then
			for _, d in ipairs(c.f:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
		end
		for i = #c.ghosts, 1, -1 do
			local g = c.ghosts[i]
			if g.Parent then
				n += #g:GetChildren()
			else
				table.remove(c.ghosts, i)
			end
		end
		return n
	end
	local function room(c, need, cap)
		return partsNow(c) + (need or 0) <= (cap or BUDGET)
	end
	local ghostNeed = setmetatable({}, { __mode = "k" })
	local function ghostAt(c, rootCF, color, alpha, life, black, cap)
		local char = c.char
		if not char or not char.Parent or typeof(rootCF) ~= "CFrame" then
			return nil
		end
		local need = ghostNeed[char]
		if not need then
			need = 0
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
					need += 1
				end
			end
			ghostNeed[char] = need
		end
		if not room(c, need, cap) then
			return nil
		end
		local g = SH("ghostAt", char, rootCF, color, alpha, life, { black = black })
		if typeof(g) == "Instance" then
			table.insert(c.ghosts, g)
		end
		return g
	end

	-- a burst site that repeats (slash hits, relocation flashes, swirl sparks): one host + one emitter for the whole
	-- cast, moved and fired at most once a frame (a second fire in the same frame falls back to a fresh one-shot)
	local function pump(c, name, props)
		local p = c.pumps[name]
		if p and p.host.Parent then
			return p
		end
		local host = FX.anchor(c.f, c.origin, nil)
		host.Name = "HollowPump_" .. name
		local att = Instance.new("Attachment")
		att.Parent = host
		local e = FX.emitter(att, props)
		p = { host = host, att = att, e = e, frame = -1 }
		c.pumps[name] = p
		return p
	end
	local function fire(p, pos, n, dir, color)
		if not p or not p.host.Parent or p.frame == frame then
			return false
		end
		p.frame = frame
		p.host.CFrame = CFrame.new(pos)
		if dir then
			p.att.CFrame = FX.yAlong(dir)
		end
		if color and p.color ~= color then
			p.color = color
			p.e.Color = ColorSequence.new(color, color:Lerp(EMBER, 0.4))
		end
		p.e:Emit(n)
		return true
	end
	local function sparkPump(c)
		return pump(c, "spark", {
			Texture = TEX.star, Color = cs(HOL, EMBER), Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(14, 40),
			SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top, Size = nsk({ { 0, 0.45 }, { 1, 0 } }),
			Transparency = nsk({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }), Drag = 3, Acceleration = Vector3.new(0, -30, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300), Brightness = 2,
		})
	end
	local function swirlPump(c)
		return pump(c, "swirl", {
			Texture = TEX.star, Color = cs(HOL, CRIM), Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(2, 6),
			SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top, Size = nsk({ { 0, 0.28 }, { 1, 0 } }),
			Drag = 2, Acceleration = Vector3.new(0, -8, 0), Rotation = NumberRange.new(0, 360), Brightness = 2,
		})
	end
	local function glowPump(c, name, color)
		return pump(c, name, {
			Texture = TEX.glow, Color = cs(color), Lifetime = NumberRange.new(0.16), Speed = NumberRange.new(0),
			Size = nsk({ { 0, 1.4 }, { 0.1, 3.5 }, { 1, 4.4 } }), Transparency = nsk({ { 0, 0 }, { 0.3, 0.2 }, { 1, 1 } }),
			ZOffset = 1, Brightness = 2, Rotation = NumberRange.new(0, 360),
		})
	end
	local function setGlowSize(p, size)
		if p and p.e.Parent then
			p.e.Size = nsk({ { 0, size * 0.4 }, { 0.1, size }, { 1, size * 1.25 } })
		end
	end
	local function ringPump(c, name, color, to, life, a0)
		to, life, a0 = to or 4, life or 0.2, a0 or 0.15
		local from = to * 0.15
		local dd = to - from
		return pump(c, name, {
			Texture = TEX.ring, Color = cs(color), Lifetime = NumberRange.new(life), Speed = NumberRange.new(0.01),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.zero, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
			Size = nsk({ { 0, from }, { 0.12, from + dd * 0.55 }, { 0.4, from + dd * 0.86 }, { 1, to } }),
			Transparency = nsk({ { 0, a0 }, { 0.55, 0.3 + a0 * 0.6 }, { 1, 1 } }), Brightness = 2.5, Rotation = NumberRange.new(0, 360),
		})
	end
	-- a cast's repeating burst sites are let go once their phase is over (their last particles finish first)
	local function dropPumps(c, names, linger)
		for _, name in ipairs(names or {}) do
			local p = c.pumps and c.pumps[name]
			if p then
				c.pumps[name] = nil
				Debris:AddItem(p.host, linger or 0.6)
			end
		end
	end
	local function dropAllPumps(c)
		local names = {}
		for name in pairs(c.pumps or {}) do
			table.insert(names, name)
		end
		dropPumps(c, names)
	end
	local SLASH_PUMPS_HIT = { "hit", "ring", "ring2", "jolt", "spark" }

	-- dark (non-additive) smoke: a radial puff, kept out of the 8 studs in front of the viewer's lens
	local function darkPuff(c, pos, n, o)
		o = o or {}
		local drag = o.drag or 5
		local reach = math.clamp(ctx.camDist(pos) - 9, 1.5, o.reach or 7)
		local v1 = math.min((o.speed or 30), reach * drag)
		local life = o.life or 0.9
		local host = FX.anchor(c.f, pos, life + 0.2)
		host.Name = "HollowPuff"
		local e = FX.emitter(host, {
			Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3,
			Size = nsk({ { 0, (o.s0 or 1) }, { 0.4, (o.s1 or 2.6) * 0.8 }, { 1, o.s1 or 2.6 } }),
			Transparency = nsk({ { 0, 0.25 }, { 0.5, 0.55 }, { 1, 1 } }), Lifetime = NumberRange.new(life * 0.6, life),
			Speed = NumberRange.new(v1 * 0.4, v1), SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top,
			Drag = drag, Acceleration = Vector3.new(0, o.rise or 2.5, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		})
		e:Emit(n)
		return host
	end
	-- a host that fires a FLAT radial fan (emitter +Y horizontal, SpreadAngle (0, 360): checked on screen in Studio;
	-- the Cylinder emitter shape sprays off its caps instead)
	local FAN_CF = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis)
	local function flatFan(c, center, props, life)
		local host = FX.anchor(c.f, center, life)
		host.Name = "HollowFan"
		local att = Instance.new("Attachment")
		att.CFrame = FAN_CF
		att.Parent = host
		props.EmissionDirection = Enum.NormalId.Top
		props.SpreadAngle = Vector2.new(0, 360)
		return FX.emitter(att, props)
	end
	-- how far a ground-level burst at `center` may roll before it reaches a nearby lens
	local function reachOf(center, cap)
		local cam = workspace.CurrentCamera
		local horiz = cam and ((cam.CFrame.Position - center) * FLATV).Magnitude or 100
		return math.clamp(horiz - 6, 1.5, cap)
	end
	-- a dark smoke ring racing out across the ground; returns fire(speed): one emitter fired once per wave
	local function darkRing(c, center, r0)
		local drag = 3.5
		local reach = reachOf(center, 11)
		local e = flatFan(c, center, {
			Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3,
			Size = nsk({ { 0, 1.2 }, { 0.4, 2.4 }, { 1, 3.4 } }), Transparency = nsk({ { 0, 0.3 }, { 0.5, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.7), Speed = NumberRange.new(1), Drag = drag,
			Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		}, 1.0)
		return function(speed)
			if not e.Parent then
				return
			end
			local sp = math.min(speed, math.max(reach - r0, 1) * drag)
			e.Speed = NumberRange.new(sp * 0.75, sp)
			e:Emit(16)
		end
	end
	-- a ground-coloured dust doughnut rolling out (one emitter; Shared's dustRing makes one emitter per puff)
	local function dustRing(c, center, n, speed, o)
		o = o or {}
		local col = SH("groundColor", FX.groundHit(center, 8)) or C3(110, 104, 98)
		local life = o.life or 1.0
		local drag = 2.5
		local sp = math.min(speed, reachOf(center, 14) * drag)
		local e = flatFan(c, center + UP * 0.6, {
			Texture = TEX.smoke, Color = cs(col, col:Lerp(Color3.new(0, 0, 0), 0.25)), LightInfluence = 1, LightEmission = 0,
			Size = nsk({ { 0, o.s0 or 2 }, { 0.35, (o.s1 or 5) * 0.8 }, { 1, o.s1 or 5 } }), Transparency = nsk({ { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(life * 0.7, life), Speed = NumberRange.new(sp * 0.8, sp), Drag = drag,
			Acceleration = Vector3.new(0, 3, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		}, life + 0.1)
		e:Emit(n)
	end
	-- GojoFX one-shot hosts outlive their particles by 0.3-0.4 s: cut them at the particles' end
	local function T(host, secs)
		if typeof(host) == "Instance" then
			Debris:AddItem(host, secs)
		end
		return host
	end

	-- small part builders of my own (anchored, non-colliding, non-querying, no shadow, Debris'd)
	local function tween(p, secs, props, style, dir)
		local tw = TweenService:Create(p, TweenInfo.new(math.max(secs, 0.01), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end
	local function newPart(c, name, size, cf, color, mat, alpha, life, shape)
		local p = FX.part(name, shape or Enum.PartType.Block, mat or NEON, color, nil)
		p.Size = size
		p.CFrame = cf
		p.Transparency = alpha or 0
		p.Parent = c.f
		Debris:AddItem(p, life or 1)
		return p
	end
	-- energy drawn IN: slivers start on a shell round `center` (flat: a ring on the ground) and rush into it
	local function converge(c, center, n, radius, life, o)
		o = o or {}
		if not room(c, n) then
			n = math.floor(n / 2)
			if n < 2 or not room(c, n) then
				return
			end
		end
		for i = 1, n do
			local d = FX.randUnit()
			if o.flat then
				d = Vector3.new(d.X, 0, d.Z)
				d = d.Magnitude > 0.1 and d.Unit or Vector3.xAxis
			end
			local r = radius * rng:NextNumber(0.7, 1)
			local dark = (i % 2 == 0)
			local col = dark and (o.dark or BLACK) or (o.color or HOL)
			local L = rng:NextNumber(0.8, 1.7) * (o.len or 1)
			local w = o.width or 0.09
			local p0 = center + d * r
			local p = newPart(c, "HollowInward", Vector3.new(w, w * (o.flat and 0.5 or 1), L), CFrame.lookAt(p0, center), col,
				dark and PLASTIC or NEON, 1, life + 0.15)
			local delay = rng:NextNumber(0, life * 0.35)
			task.delay(delay, function()
				if not p.Parent then
					return
				end
				p.Transparency = dark and 0.1 or 0.05
				local p1 = center + d * 0.35
				tween(p, life - delay, { CFrame = CFrame.lookAt(p1, p1 - d), Size = Vector3.new(w * 0.4, w * 0.4, L * 0.25), Transparency = 0.85 },
					Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
	end
	-- a four-point star flash (two crossed slivers facing the lens) that pops open and closes
	local function glint(c, pos, size, color, life)
		if not room(c, 2) then
			return
		end
		life = life or 0.16
		size = size * camK(pos)
		local base = CFrame.lookAt(pos, pos + ctx.camFacing(pos)) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi))
		for j = 0, 1 do
			local s = (j == 0) and size or size * 0.65
			local p = newPart(c, "HollowGlint", Vector3.new(s * 0.04, s * 0.12, 0.02), base * CFrame.Angles(0, 0, j * math.pi / 2), color, NEON, 0.05, life + 0.1)
			tween(p, life * 0.3, { Size = Vector3.new(s * 0.07, s, 0.02) })
			task.delay(life * 0.3, function()
				if p.Parent then
					tween(p, life * 0.7, { Size = Vector3.new(0.01, s * 0.25, 0.02), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end
	end
	-- light rays bursting out of a point (never straight down the lens), shooting to length, then thinning away
	local function burstRays(c, center, n, len, colors, life, cap)
		local camF = ctx.camFacing(center)
		for i = 1, n do
			if not room(c, 1, cap) then
				return
			end
			local d = FX.randUnit()
			d = Vector3.new(d.X, d.Y * 0.6, d.Z).Unit
			if d:Dot(camF) > 0.6 then
				d = (d - camF * 1.4).Unit
			end
			local L = len * rng:NextNumber(0.55, 1.1)
			local w = rng:NextNumber(0.16, 0.36)
			local col = colors[(i - 1) % #colors + 1]
			local dark = col == BLACK
			local function cfAt(l, push)
				local m = center + d * ((push or 0.6) + l / 2)
				return CFrame.lookAt(m, m + d)
			end
			local p = newPart(c, "HollowRay", Vector3.new(w, w, 0.4), cfAt(0.4), col, dark and PLASTIC or NEON, dark and 0.1 or 0.05, life + 0.15)
			tween(p, 0.07, { Size = Vector3.new(w, w, L), CFrame = cfAt(L) })
			task.delay(0.07, function()
				if p.Parent then
					tween(p, life - 0.07, { Size = Vector3.new(0.02, 0.02, L * 1.2), CFrame = cfAt(L * 1.2, 2.2), Transparency = 1 },
						Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end
	end
	-- shock lines racing out across the ground from `center` (kept short of a nearby lens)
	local function shockLines(c, center, n, r0, r1, color, life)
		local reach = reachOf(center, r1)
		for i = 1, n do
			if not room(c, 1) then
				return
			end
			local a = (i / n) * TAU + rng:NextNumber(-0.2, 0.2)
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local L0 = rng:NextNumber(1.4, 2.4)
			local p0 = center + d * r0
			local p = newPart(c, "HollowShockLine", Vector3.new(0.16, 0.05, L0), CFrame.lookAt(p0, p0 + d), color, NEON, 0.1, life + 0.15)
			local r = math.max(reach * rng:NextNumber(0.7, 1), r0 + 1)
			local p1 = center + d * r
			tween(p, life, { CFrame = CFrame.lookAt(p1, p1 + d), Size = Vector3.new(0.04, 0.03, L0 * 2.6), Transparency = 1 }, Enum.EasingStyle.Quart)
		end
	end
	-- a flat disc on the ground (scorch / glowing crater core) that fades after `hold`
	local function groundDisc(c, center, radius, color, mat, alpha, hold, fade)
		local p = newPart(c, "HollowScorch", Vector3.new(0.06, radius * 2, radius * 2), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
			color, mat, alpha, hold + fade + 0.2, Enum.PartType.Cylinder)
		task.delay(hold, function()
			if p.Parent then
				tween(p, fade, { Transparency = 1, Size = Vector3.new(0.06, radius * 2.3, radius * 2.3) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
		return p
	end
	-- the blade's mid point / tip (nil-safe)
	local function bladeAt(c, which)
		local info = SwordMod and c.char and try("swordget", SwordMod.get, c.char)
		local a = info and info[which or "mid"]
		return a and a.WorldPosition or nil, info
	end

	---------------------------------------------------------------------------------------------------
	-- THE MASK. Head space for a 1.2-stud head (scaled per axis to the real Head.Size); the face is -Z, his left -X.
	local function cfAt(x, y, z, rx, ry, rz)
		return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
	end
	local FOREHEAD = cfAt(0, 0.38, -0.625, 12, 0, 0)
	local CHEEK_L = cfAt(-0.33, -0.11, -0.60, 0, 25, 0)
	local CHEEK_R = cfAt(0.33, -0.11, -0.60, 0, -25, 0)
	local JAW = cfAt(0, -0.42, -0.61, 10, 0, 0)
	-- the front surface of the mask at (x, y), for laying the cracks on it
	local function surf(x, y)
		if y > 0.22 then
			return -0.659 + 0.2126 * (y - 0.387)
		elseif y < -0.33 then
			return -0.6445 + 0.1763 * (y + 0.414)
		elseif x < -0.17 then
			return -0.6317 - 0.4226 * ((x + 0.3448) / 0.906)
		elseif x > 0.17 then
			return -0.6317 + 0.4226 * ((x - 0.3448) / 0.906)
		end
		return -0.66
	end
	-- the 5 cracks (CrackAt): polylines on the plates
	local CRACKS = {
		{ { 0.10, 0.52 }, { 0.18, 0.43 }, { 0.13, 0.34 }, { 0.24, 0.27 } },
		{ { -0.03, 0.53 }, { -0.09, 0.45 }, { -0.03, 0.37 }, { -0.08, 0.28 } },
		{ { 0.21, 0.00 }, { 0.30, -0.07 }, { 0.26, -0.15 }, { 0.36, -0.21 } },
		{ { -0.40, 0.00 }, { -0.31, -0.08 }, { -0.37, -0.16 }, { -0.27, -0.22 } },
		{ { 0.04, -0.40 }, { 0.14, -0.44 }, { 0.09, -0.47 }, { 0.21, -0.46 } },
	}
	-- fragments: { name, centroid, from (offset it flies in from), spin axis, parts = { name, size, cf, color, material,
	-- role } } (role "stripe" ignites at StripesAt, "crack" at CrackAt)
	local function layout()
		local frags = {}
		local function frag(name, centroid, from, parts)
			table.insert(frags, { name = name, centroid = centroid, from = from, parts = parts, spin = FX.randUnit() })
		end
		local function P(name, size, cf, color, material, role, shape)
			return { name = name, size = size, cf = cf, color = color or BONE, material = material or PLASTIC, role = role, shape = shape }
		end
		frag("Forehead", Vector3.new(0, 0.36, -0.62), Vector3.new(0, 1.2, -0.9), {
			P("Plate", Vector3.new(1.02, 0.30, 0.07), FOREHEAD),
			P("Crest", Vector3.new(0.08, 0.30, 0.05), FOREHEAD * CFrame.new(0, 0, -0.055)),
			P("BrowL", Vector3.new(0.30, 0.07, 0.08), cfAt(-0.21, 0.215, -0.66, 0, 0, -14)),
			P("BrowR", Vector3.new(0.30, 0.07, 0.08), cfAt(0.21, 0.215, -0.66, 0, 0, 14)),
			P("SocketL", Vector3.new(0.26, 0.14, 0.02), cfAt(-0.21, 0.10, -0.595), BLACK),
			P("SocketR", Vector3.new(0.26, 0.14, 0.02), cfAt(0.21, 0.10, -0.595), BLACK),
			P("StripeA1", Vector3.new(0.10, 0.27, 0.02), FOREHEAD * CFrame.new(-0.34, -0.005, -0.046), HOL, NEON, "stripe"),
			P("StripeB1", Vector3.new(0.10, 0.27, 0.02), FOREHEAD * CFrame.new(-0.19, -0.005, -0.046), HOL, NEON, "stripe"),
		})
		frag("CheekL", Vector3.new(-0.33, -0.11, -0.60), Vector3.new(-1.3, -0.2, -0.8), {
			P("Plate", Vector3.new(0.36, 0.30, 0.07), CHEEK_L),
			P("StripeA2", Vector3.new(0.10, 0.27, 0.02), CHEEK_L * CFrame.new(-0.005, -0.01, -0.046), HOL, NEON, "stripe"),
			P("StripeB2", Vector3.new(0.09, 0.27, 0.02), CHEEK_L * CFrame.new(0.13, -0.01, -0.046), HOL, NEON, "stripe"),
		})
		frag("CheekR", Vector3.new(0.33, -0.11, -0.60), Vector3.new(1.3, -0.2, -0.8), {
			P("Plate", Vector3.new(0.36, 0.30, 0.07), CHEEK_R),
		})
		frag("Nose", Vector3.new(0, 0.0, -0.66), Vector3.new(0.3, 0.4, -1.5), {
			P("Ridge", Vector3.new(0.14, 0.26, 0.12), cfAt(0, 0.0, -0.66), nil, nil, nil, "wedge"),
		})
		local grin = { P("Lip", Vector3.new(0.30, 0.13, 0.07), cfAt(0, -0.155, -0.625)) }
		for j = 1, 6 do
			table.insert(grin, P("ToothU" .. j, Vector3.new(0.07, 0.09, 0.05), cfAt(-0.225 + (j - 1) * 0.09, -0.24, -0.64)))
		end
		frag("Grin", Vector3.new(0, -0.21, -0.63), Vector3.new(-0.4, -0.6, -1.4), grin)
		local jaw = {
			P("Plate", Vector3.new(0.72, 0.12, 0.07), JAW),
			P("Slit", Vector3.new(0.56, 0.04, 0.02), cfAt(0, -0.305, -0.62), BLACK),
		}
		for j = 1, 6 do
			table.insert(jaw, P("ToothL" .. j, Vector3.new(0.07, 0.07, 0.05), cfAt(-0.225 + (j - 1) * 0.09, -0.36, -0.645)))
		end
		frag("Jaw", Vector3.new(0, -0.40, -0.61), Vector3.new(0, -1.3, -0.9), jaw)
		frag("HornL", Vector3.new(-0.42, 0.58, -0.48), Vector3.new(-1.0, 1.0, -0.4), {
			P("Horn", Vector3.new(0.10, 0.22, 0.16), cfAt(-0.42, 0.60, -0.48, 0, 0, 25), nil, nil, nil, "wedge"),
		})
		frag("HornR", Vector3.new(0.42, 0.58, -0.48), Vector3.new(1.0, 1.0, -0.4), {
			P("Horn", Vector3.new(0.10, 0.22, 0.16), cfAt(0.42, 0.60, -0.48, 0, 0, -25), nil, nil, nil, "wedge"),
		})
		-- the cracks ride the plates they run over (they leave with them at the shatter)
		local owner = { "Forehead", "Forehead", "CheekR", "CheekL", "Jaw" }
		for ci, pts in ipairs(CRACKS) do
			local f
			for _, fr in ipairs(frags) do
				if fr.name == owner[ci] then
					f = fr
				end
			end
			for s = 1, #pts - 1 do
				local a = Vector3.new(pts[s][1], pts[s][2], surf(pts[s][1], pts[s][2]) - 0.014)
				local b = Vector3.new(pts[s + 1][1], pts[s + 1][2], surf(pts[s + 1][1], pts[s + 1][2]) - 0.014)
				local len = (b - a).Magnitude
				local p = P("Crack" .. ci .. "_" .. s, Vector3.new(0.028, 0.028, len + 0.02), CFrame.lookAt((a + b) / 2, b), HOL, NEON, "crack")
				p.crackAt = (ci - 1) * 0.05 + (s - 1) * 0.04
				table.insert(f.parts, p)
			end
		end
		return frags
	end
	-- the veins that crawl out from under his palm (head space, on the face): polylines from near the centre out
	local VEINS = {
		{ { -0.05, 0.10 }, { -0.18, 0.22 }, { -0.30, 0.31 }, { -0.44, 0.47 } },
		{ { 0.05, 0.10 }, { 0.20, 0.20 }, { 0.28, 0.34 }, { 0.42, 0.49 } },
		{ { -0.08, 0.00 }, { -0.24, -0.04 }, { -0.36, 0.06 }, { -0.53, 0.02 } },
		{ { 0.08, 0.00 }, { 0.22, -0.06 }, { 0.38, 0.00 }, { 0.53, -0.06 } },
		{ { -0.06, -0.10 }, { -0.16, -0.24 }, { -0.30, -0.30 }, { -0.42, -0.47 } },
		{ { 0.06, -0.10 }, { 0.18, -0.22 }, { 0.30, -0.34 }, { 0.44, -0.45 } },
		{ { 0.00, 0.16 }, { 0.05, 0.32 }, { -0.04, 0.44 }, { 0.02, 0.57 } },
		{ { 0.00, -0.16 }, { -0.04, -0.30 }, { 0.04, -0.42 }, { 0.00, -0.57 } },
	}
	local VEIN_ORDER = { 3, 4, 1, 6, 7, 2, 5, 8 } -- the crawl spreads round the face, not in reading order
	local FILM_OF = { Forehead = true, CheekL = true, CheekR = true, Grin = true, Jaw = true }

	local function buildMask(c, head, formed)
		local sz = head.Size / 1.2
		local function scaled(cf)
			return CFrame.new(cf.Position * sz) * cf.Rotation
		end
		local m = { head = head, frags = layout(), list = {}, cfs = {}, alpha = {}, hidden = false, state = "forming", extra = {}, formedAtOnce = formed }
		local folder = Instance.new("Folder")
		folder.Name = "HollowMask"
		local k = math.min(sz.X, sz.Y, sz.Z)
		local layered = not formed and c.tier <= 2 -- veins + the dark film: only for a cast seen from its start
		for fi, fr in ipairs(m.frags) do
			fr.t0 = FORM_AT + (fi - 1) * STAGGER
			fr.centroidS = fr.centroid * sz
			fr.landed = formed
			if layered and FILM_OF[fr.name] then
				-- the dark film where this plate will sit (the mask's shape congealing before the bone arrives)
				local pd = fr.parts[1]
				local p = FX.part("MaskFilm", Enum.PartType.Block, PLASTIC, HDARK, nil)
				p.Massless = true
				p.Size = Vector3.new(pd.size.X * sz.X * 1.08, pd.size.Y * sz.Y * 1.1, pd.size.Z * math.max(k, 0.6) * 0.8)
				p.Transparency = 1
				p.Parent = folder
				table.insert(m.list, p)
				table.insert(m.cfs, head.CFrame * scaled(pd.cf))
				table.insert(m.extra, { part = p, seat = scaled(pd.cf), kind = "film", frag = fr, idx = #m.list })
			end
			for _, pd in ipairs(fr.parts) do
				if pd.role == "stripe" then
					pd.seg = (pd.name:sub(-1) == "1") and 1 or 2
				end
				local p
				if pd.shape == "wedge" then
					p = Instance.new("WedgePart")
					p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				else
					p = FX.part("Mask" .. pd.name, Enum.PartType.Block, pd.material, pd.color, nil)
				end
				p.Name = "Mask" .. pd.name
				p.Material = pd.material
				p.Color = pd.color
				p.Massless = true
				p.Size = Vector3.new(pd.size.X * sz.X, pd.size.Y * sz.Y, pd.size.Z * math.max(k, 0.6))
				local base = (pd.role and 1) or 0
				if pd.role == "stripe" and formed then
					base = 0
				end
				p.Transparency = formed and base or 1
				p.Parent = folder
				pd.part = p
				pd.seat = scaled(pd.cf)
				pd.full = p.Size
				table.insert(m.list, p)
				table.insert(m.cfs, head.CFrame * pd.seat)
				pd.idx = #m.list
			end
		end
		if layered then
			-- the veins: each drawn segment by segment from the palm outward, dim crimson neon, sitting just on the face
			for oi, vi in ipairs(VEIN_ORDER) do
				local pts = VEINS[vi]
				local t0 = CRAWL_FROM + (oi - 1) * VEIN_STAGGER
				for s = 1, #pts - 1 do
					local a = Vector3.new(pts[s][1], pts[s][2], -0.612)
					local b = Vector3.new(pts[s + 1][1], pts[s + 1][2], -0.612)
					local mid, len = (a + b) / 2, (b - a).Magnitude
					local seat = CFrame.lookAt(mid * sz, b * sz)
					local w = 0.05 - s * 0.008
					local p = FX.part("MaskVein", Enum.PartType.Block, NEON, (s == 1) and HOL:Lerp(BLACK, 0.25) or HOL:Lerp(BLACK, 0.5), nil)
					p.Massless = true
					p.Size = Vector3.new(w * sz.X, w * sz.Y, len * math.max(sz.X, sz.Y) + 0.02)
					p.Transparency = 1
					p.Parent = folder
					table.insert(m.list, p)
					table.insert(m.cfs, head.CFrame * seat)
					table.insert(m.extra, {
						part = p, seat = seat, kind = "vein", t = t0 + (s - 1) / (#pts - 1) * VEIN_DRAW, phase = rng:NextNumber(0, TAU), idx = #m.list,
					})
				end
			end
		end
		folder.Parent = c.f
		m.folder = folder
		c.mask = m
		return m
	end

	-- every frame: seat / fly / hide the mask on the head; the veins crawl and pulse, the film congeals, the stripes
	-- burn in top to bottom
	local function plateLanded(c, fi, wp)
		fire(sparkPump(c), wp, 6)
		local g = glowPump(c, "plate", BONE)
		if g and not g.sized then
			g.sized = true
			setGlowSize(g, glowFor(wp, 1.3))
		end
		fire(g, wp, 1)
		if fi % 2 == 1 then
			snd(c, "Shatter", 0.22, 1.9 + fi * 0.06, c.mask and c.mask.head)
		end
	end
	local function updateMask(c, e, clock)
		local m = c.mask
		if not m or m.state == "gone" or m.state == "shattered" then
			return
		end
		local head = m.head
		if not head or not head.Parent then
			m.state = "gone"
			m.folder:Destroy()
			return
		end
		local hcf = head.CFrame
		local tier3 = c.tier == 3
		local half = STRIPE_DRAW / 2
		local tipAt
		for fi, fr in ipairs(m.frags) do
			local k = 1
			if not fr.landed then
				k = tier3 and ((e >= STRIPES_AT) and 1 or 0) or math.clamp((e - fr.t0) / FLY, 0, 1)
				if k >= 1 then
					fr.landed = true
					if not tier3 and c.tier == 1 then
						plateLanded(c, fi, hcf * fr.centroidS)
					end
				end
			end
			local ease = 1 - (1 - k) ^ 3
			local off = CFrame.identity
			if k < 1 then
				local cen = fr.centroidS
				off = CFrame.new(cen + fr.from * (1 - ease)) * CFrame.fromAxisAngle(fr.spin, 2.2 * (1 - ease)) * CFrame.new(-cen)
			end
			for _, pd in ipairs(fr.parts) do
				local i = pd.idx
				local seat = pd.seat
				local p = pd.part
				local want
				if k <= 0 then
					want = 1
				elseif pd.role == "stripe" then
					-- burning in from the top: the part grows down from its top edge, a hot tip leading it
					local ks = m.formedAtOnce and 1 or math.clamp((e - STRIPES_AT - (pd.seg - 1) * half) / half, 0, 1)
					want = (ks > 0) and 0 or 1
					local full = pd.full
					if ks > 0 and ks < 1 then
						local ys = full.Y * ks
						p.Size = Vector3.new(full.X, ys, full.Z)
						seat = seat * CFrame.new(0, (full.Y - ys) / 2, 0)
						tipAt = hcf * off * seat * Vector3.new(0, -ys / 2, -0.01)
					elseif ks >= 1 and p.Size ~= full then
						p.Size = full
					end
				elseif pd.role == "crack" then
					want = (m.crackT and os.clock() - m.crackT >= pd.crackAt) and 0 or 1
				else
					want = 0
				end
				m.cfs[i] = hcf * off * seat
				if p.Transparency ~= want then
					p.Transparency = want
				end
				if k < 1 and k > 0 and not pd.role and pd.color ~= BLACK then
					p.Color = HDARK:Lerp(pd.color, ease)
				elseif k >= 1 and not pd.role and p.Color ~= pd.color then
					p.Color = pd.color
				end
			end
		end
		if tipAt and c.tier == 1 then
			local g = glowPump(c, "stripe", HOL)
			if g and not g.sized then
				g.sized = true
				setGlowSize(g, glowFor(tipAt, 0.9))
			end
			fire(g, tipAt, 1)
		end
		-- the veins and the film
		local veinsOut = math.clamp((e - (EYES_AT - 0.06)) / 0.12, 0, 1)
		for _, x in ipairs(m.extra) do
			m.cfs[x.idx] = hcf * x.seat
			local want = 1
			if x.kind == "vein" then
				if e >= x.t and veinsOut < 1 then
					local pulse = 0.5 + 0.5 * math.sin(clock * 26 + x.phase)
					want = 0.05 + 0.3 * pulse * math.clamp((e - x.t) / 0.15, 0, 1)
					want = want + (1 - want) * veinsOut
				end
			elseif x.kind == "film" then
				if not x.frag.landed then
					want = 1 - 0.72 * math.clamp((e - FILM_AT) / FILM_IN, 0, 1)
				end
			end
			if math.abs(x.part.Transparency - want) > 0.02 or (want == 1 and x.part.Transparency ~= 1) then
				x.part.Transparency = want
			end
		end
		if #m.extra > 0 and veinsOut >= 1 and e > FORM_AT + #m.frags * STAGGER + FLY then
			-- the veins and the film have done their work: drop them (and their slots) so the governor gets the room back
			for _, x in ipairs(m.extra) do
				x.part:Destroy()
			end
			m.extra = {}
			local list, cfs = {}, {}
			for _, fr in ipairs(m.frags) do
				for _, pd in ipairs(fr.parts) do
					table.insert(list, pd.part)
					table.insert(cfs, m.cfs[pd.idx])
					pd.idx = #list
				end
			end
			m.list, m.cfs = list, cfs
		end
		workspace:BulkMoveTo(m.list, m.cfs, BULK)
		-- first person: the mask must never sit in front of his own lens
		if c.isLocal then
			local cam = workspace.CurrentCamera
			local hide = cam and (cam.CFrame.Position - head.Position).Magnitude < 1.8
			if hide ~= m.hidden then
				m.hidden = hide
				for _, p in ipairs(m.list) do
					p.LocalTransparencyModifier = hide and 1 or 0
				end
				if c.seep and c.seep.Parent then
					c.seep.Enabled = not hide
				end
			end
		end
	end

	-- the mask bursts off his face: every piece is flung out, slows, then drifts and BURNS away (bone -> ember -> char,
	-- shrinking, shedding embers) over BURN_LIFE
	local function burnPump(c)
		return pump(c, "burn", {
			Texture = TEX.star, Color = cs(EMBER, CRIM), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(0.5, 2.5),
			SpreadAngle = Vector2.new(180, 180), EmissionDirection = Enum.NormalId.Top, Size = nsk({ { 0, 0.22 }, { 1, 0 } }),
			Transparency = nsk({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Drag = 1.5, Acceleration = Vector3.new(0, 5, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Brightness = 2.5,
		})
	end
	local CHAR = Color3.fromRGB(24, 14, 14)
	local function shatterMask(c, gentle)
		local m = c.mask
		if not m or m.state == "shattered" or m.state == "gone" then
			return
		end
		m.state = "shattered"
		for _, x in ipairs(m.extra or {}) do
			x.part:Destroy()
		end
		m.extra = {}
		local head = m.head
		local hcf = (head and head.Parent) and head.CFrame or (m.list[1] and m.list[1].CFrame) or CFrame.new(c.origin)
		local fwd = hcf.LookVector
		local deb = { parts = {}, cfs = {}, st = {}, t = 0, life = gentle and math.min(BURN_LIFE, 1.1) or BURN_LIFE }
		local mul = gentle and 0.45 or 1
		for _, fr in ipairs(m.frags) do
			local out = hcf:VectorToWorldSpace(fr.centroid.Magnitude > 1e-3 and fr.centroid.Unit or Vector3.zAxis * -1)
			local v = (out * rng:NextNumber(5, 10) + fwd * rng:NextNumber(7, 13) + UP * rng:NextNumber(3, 7)) * mul
			local spin = FX.randUnit() * rng:NextNumber(3, 9)
			local burnAt = rng:NextNumber(0.12, 0.3)
			for _, pd in ipairs(fr.parts) do
				local p = pd.part
				if p and p.Parent and p.Transparency < 1 then
					p.LocalTransparencyModifier = 0
					table.insert(deb.parts, p)
					table.insert(deb.cfs, p.CFrame)
					table.insert(deb.st, {
						v = v + FX.randUnit() * 1.5, spin = spin, base = p.Transparency, size = p.Size, role = pd.role,
						black = pd.color == BLACK, burnAt = burnAt, neon = false,
					})
				elseif p then
					p:Destroy()
				end
			end
		end
		c.debris = deb
		Debris:AddItem(m.folder, deb.life + 0.3)
	end
	local function updateDebris(c, dt)
		local deb = c.debris
		if not deb then
			return
		end
		deb.t += dt
		local t = deb.t
		local life = deb.life
		if t >= life then
			for _, p in ipairs(deb.parts) do
				p:Destroy()
			end
			c.debris = nil
			dropPumps(c, { "burn" }, 0.8)
			return
		end
		local n = #deb.parts
		for i, p in ipairs(deb.parts) do
			local s = deb.st[i]
			local bk = math.clamp((t - s.burnAt) / (life - s.burnAt - 0.1), 0, 1)
			-- flung, then caught by the air: it slows hard, then drifts (rising a little as it burns)
			local drag = t < 0.25 and 3.4 or 1.4
			s.v += Vector3.new(0, -16 + 22 * bk, 0) * dt
			s.v *= math.max(1 - drag * dt, 0)
			deb.cfs[i] = (deb.cfs[i] + s.v * dt) * CFrame.fromAxisAngle(s.spin.Unit, s.spin.Magnitude * dt * (1 - 0.5 * bk))
			local a
			if s.role then
				a = s.base + (1 - s.base) * math.clamp(t / 0.45, 0, 1) -- stripes and cracks die first
			else
				a = s.base + (1 - s.base) * math.clamp((bk - 0.55) / 0.45, 0, 1)
				if not s.black then
					local col
					if bk < 0.35 then
						col = BONE:Lerp(EMBER, bk / 0.35)
					elseif bk < 0.7 then
						col = EMBER:Lerp(CRIM:Lerp(CHAR, 0.55), (bk - 0.35) / 0.35)
					else
						col = CRIM:Lerp(CHAR, 0.55):Lerp(CHAR, (bk - 0.7) / 0.3)
					end
					if bk > 0.08 and not s.neon then
						s.neon = true
						p.Material = NEON -- the burning edge glows
					end
					p.Color = col
				end
				p.Size = s.size * (1 - 0.62 * bk ^ 1.4)
			end
			p.Transparency = a
		end
		workspace:BulkMoveTo(deb.parts, deb.cfs, BULK)
		-- embers shed off a burning piece (one emit a frame, from a different piece each time)
		if n > 0 and t > 0.15 and t < life - 0.2 and c.tier <= 2 then
			local p = deb.parts[(deb.k or 0) % n + 1]
			deb.k = (deb.k or 0) + 7
			if p and p.Parent then
				fire(burnPump(c), p.Position, 2)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- THE SWIRL (0.10 -> 0.82): three dark ribbons of 6 links orbiting the head, tightening as the mask completes
	local RIBBON_N = { Vector3.new(0, 1, 0.35).Unit, Vector3.new(0.55, 1, -0.2).Unit, Vector3.new(-0.55, 1, 0.1).Unit }
	local function buildSwirl(c)
		local sw = { parts = {}, cfs = {}, ribbons = {}, nextSpark = 0, which = 0 }
		for r = 1, 3 do
			local n = RIBBON_N[r]
			local u = n:Cross(Vector3.xAxis)
			if u.Magnitude < 1e-3 then
				u = n:Cross(Vector3.zAxis)
			end
			u = u.Unit
			local w = n:Cross(u).Unit
			local rb = { u = u, w = w, phase = (r - 1) * TAU / 3, links = {} }
			for j = 1, 6 do
				local s = 0.24 - (j - 1) * 0.03
				local p = FX.part("HollowSwirl", Enum.PartType.Block, PLASTIC, HDARK, nil)
				p.Size = Vector3.new(s, s, s * 2.4)
				p.Transparency = 1
				p.Parent = c.f
				table.insert(rb.links, { part = p, idx = #sw.parts + 1 })
				table.insert(sw.parts, p)
				table.insert(sw.cfs, CFrame.new(c.origin))
			end
			sw.ribbons[r] = rb
		end
		c.swirl = sw
	end
	local function updateSwirl(c, e, clock)
		local sw = c.swirl
		if not sw then
			return
		end
		local head = partOf(c.char, "Head")
		if not head or e > SWIRL_TO + 0.12 then
			for _, p in ipairs(sw.parts) do
				p:Destroy()
			end
			c.swirl = nil
			dropPumps(c, { "swirl" }, 0.45)
			return
		end
		local k = math.clamp((e - SWIRL_FROM) / (SWIRL_TO - SWIRL_FROM), 0, 1)
		local R = 1.2 + (0.6 - 1.2) * k
		local alphaIn = math.clamp((e - SWIRL_FROM) / 0.08, 0, 1)
		local alphaOut = math.clamp((e - (SWIRL_TO - 0.08)) / 0.16, 0, 1)
		local tr = 1 - 0.92 * alphaIn * (1 - alphaOut)
		local hp = head.Position
		for _, rb in ipairs(sw.ribbons) do
			local th0 = rb.phase + e * TAU * 2
			for j, ln in ipairs(rb.links) do
				local th = th0 - (j - 1) * 0.3
				local pos = hp + (rb.u * math.cos(th) + rb.w * math.sin(th)) * R
				local tan = -rb.u * math.sin(th) + rb.w * math.cos(th)
				sw.cfs[ln.idx] = CFrame.lookAt(pos, pos + tan)
				local want = math.min(tr + (j - 1) * 0.06, 1)
				if math.abs(ln.part.Transparency - want) > 0.01 then
					ln.part.Transparency = want
				end
			end
		end
		workspace:BulkMoveTo(sw.parts, sw.cfs, BULK)
		-- crimson sparks shed off the ribbon heads (3 every 0.08 s, one ribbon at a time)
		if clock >= sw.nextSpark and tr < 0.9 then
			sw.nextSpark = clock + 0.08
			sw.which = sw.which % 3 + 1
			local lead = sw.ribbons[sw.which].links[1].part
			fire(swirlPump(c), lead.Position, 3)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- persistent handles (aura, eyes, blade glow, face seep, lifted rocks) and the cleanup of everything the cast owns
	local function stopEmit(e)
		if typeof(e) == "Instance" and e.Parent then
			e.Rate = 0
		end
	end
	local function dropHandles(c)
		if c.aura then
			call(c.aura, "Destroy")
			c.aura = nil
		end
		if c.eyes then
			call(c.eyes, "Destroy")
			c.eyes = nil
		end
		if c.blade then
			call(c.blade, "stop")
			c.blade = nil
		end
		if c.swirl then
			for _, p in ipairs(c.swirl.parts) do
				p:Destroy()
			end
			c.swirl = nil
		end
		if c.seep then
			stopEmit(c.seep)
			c.seep = nil
		end
		if c.rocks then
			local rk = c.rocks
			c.rocks = nil
			call(rk, "drop")
		end
	end

	-- the eyes flicker as the mask cracks: whatever S.eyes built (an Instance, or a table holding parts) blinks
	local function flickerEyes(c)
		local h = c.eyes
		local list = {}
		local function collect(x)
			if typeof(x) == "Instance" then
				if x:IsA("BasePart") or x:IsA("Decal") then
					table.insert(list, x)
				end
				for _, d in ipairs(x:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("Decal") then
						table.insert(list, d)
					end
				end
			end
		end
		if typeof(h) == "Instance" then
			collect(h)
		elseif type(h) == "table" then
			for _, k in ipairs({ "folder", "model", "root", "part", "host" }) do
				collect(h[k])
			end
			if type(h.parts) == "table" then
				for _, p in ipairs(h.parts) do
					collect(p)
				end
			end
		end
		local head = partOf(c.char, "Head")
		for i, dt in ipairs({ 0, 0.06, 0.13, 0.2, 0.26 }) do
			task.delay(dt, function()
				if c.cancelled then
					return
				end
				local off = (i % 2 == 1)
				if type(h) == "table" and type(h.set) == "function" then
					call(h, "set", off and 0.12 or 1)
				else
					for _, p in ipairs(list) do
						if p.Parent then
							p.LocalTransparencyModifier = off and 1 or 0
						end
					end
				end
				if not off and head and head.Parent and c.tier == 1 and i == 5 then
					local eyeL = head.CFrame * Vector3.new(-0.21 * head.Size.X / 1.2, 0.1 * head.Size.Y / 1.2, -0.7 * head.Size.Z / 1.2)
					T(FX.glow(c.f, eyeL, glowFor(eyeL, 1.2), GOLD, 0.15), 0.2)
				end
			end)
		end
	end

	-- gold flares across the eyes as they ignite; at the shatter, two gold streaks dragged off them as they go out
	local function eyeStreaks(c, head, out)
		if not head or not head.Parent or c.tier > 2 then
			return
		end
		local cam = workspace.CurrentCamera
		if c.isLocal and cam and (cam.CFrame.Position - head.Position).Magnitude < 3 then
			return
		end
		local s = head.Size
		local hcf = head.CFrame
		for side = -1, 1, 2 do
			local pos = hcf * Vector3.new(0.21 * s.X * side, 0.09 * s.Y, -0.5 * s.Z - 0.2)
			local axis = out and (-hcf.LookVector * 0.7 + UP * 0.35 + hcf.RightVector * side * 0.45).Unit or hcf.RightVector
			local L = out and 1.8 or 1.5
			local p = newPart(c, "HollowEyeFlare", Vector3.new(0.05, 0.05, 0.1), CFrame.lookAt(pos, pos + axis), GOLD, NEON, 0, 0.6)
			local mid = out and (pos + axis * (L / 2)) or pos
			tween(p, 0.07, { Size = Vector3.new(0.05, 0.05, L), CFrame = CFrame.lookAt(mid, mid + axis) })
			task.delay(0.07, function()
				if p.Parent then
					tween(p, out and 0.32 or 0.2, { Size = Vector3.new(0.01, 0.01, L * (out and 1.3 or 0.4)), Transparency = 1 },
						Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
			T(FX.glow(c.f, pos, glowFor(pos, out and 0.8 or 1.1), GOLD, 0.2), 0.3)
		end
	end

	local function cancel(c)
		if c.cancelled then
			return
		end
		c.cancelled = true
		dropHandles(c)
		shatterMask(c, true)
		dropAllPumps(c)
		if c.wave then
			call(c.wave.cr, "Destroy")
			c.wave = nil
		end
		task.delay(1.5, function()
			if casts[c.key] == c then
				casts[c.key] = nil
			end
		end)
		if c.track then
			call(c.track, "stop", 0.15)
		end
		for _, tr in ipairs(c.tracks) do
			call(tr, "stop", 0.15)
		end
		if c.isLocal then
			try("stopShot", ctx.stopShot)
			try("stopMove", ctx.stopMove)
			try("unroot", ctx.unroot)
		end
	end

	local function finish(c)
		dropHandles(c)
		shatterMask(c, true) -- never left on a face (a skipped shatter beat)
		if not c.debris then
			dropAllPumps(c)
		end
		c.finished = true
		task.delay(1.5, function()
			if casts[c.key] == c then
				casts[c.key] = nil
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- the beat scheduler on the shared clock: a beat more than `slack` past is skipped (late joiners)
	local function at(c, T, fn, slack)
		local en = ctx.now() - c.t0
		if T < en - (slack or 0.06) then
			return
		end
		task.delay(math.max(T - en, 0), function()
			if not c.cancelled then
				try("beat", fn)
			end
		end)
	end
	-- a delay nested inside a beat: counts from that beat
	local function after(c, dt, fn)
		task.delay(dt, function()
			if not c.cancelled then
				try("after", fn)
			end
		end)
	end
	local function play(c, name, T)
		if not c.char then
			return nil
		end
		local clipName = c.bk and (name .. "_BK") or name
		local clip = ctx.Clips and (ctx.Clips[clipName] or ctx.Clips[name])
		if not clip then
			return nil
		end
		local tr = try("playClip", ctx.playClip, c.char, clip, math.max(ctx.now() - c.t0 - T, 0))
		if tr then
			table.insert(c.tracks, tr)
		end
		return tr
	end

	---------------------------------------------------------------------------------------------------
	-- INHALE_AT: reiatsu streaks and ground dust dragged IN to him before the roar
	local function inhale(c)
		local center = hrpPos(c)
		local chest = center + UP * 1.2
		local feet, onGround = groundAt(center)
		local lead = math.max(num(c.roarAt, 0.95) - INHALE_AT, 0.08)
		if c.tier == 1 then
			T(FX.streaks(c.f, chest, { inward = 8, count = 26, color = HOL, color2 = EMBER, life = lead, size = 0.35 }), lead + 0.4)
			converge(c, chest, 10, 6.5, lead, { color = CRIM, dark = BLACK })
			if onGround then
				local col = SH("groundColor", FX.groundHit(feet, 8)) or SMOKE
				converge(c, feet + UP * 0.25, 8, 7.5, lead, { flat = true, color = HOL:Lerp(BLACK, 0.3), dark = col, width = 0.14, len = 1.3 })
			end
		end
		snd(c, "Rise", 0.5, 1.4)
	end

	-- THE ROAR
	local function roarFrame(c)
		local f, char = c.f, c.char
		local center = hrpPos(c)
		local feet, onGround = groundAt(center)
		local chest = center + UP * 1.2
		local tier = tierOf(center)
		local camD = ctx.camDist(center)
		local MK = c.mode and 1.25 or 1
		local flatTo = math.clamp((camD - 4) * 2, 16, 36 * MK)
		local head = partOf(char, "Head")
		local look = head and flat(head.CFrame.LookVector, c.aim) or c.aim
		-- three flat shock rings, each paired with a dark smoke ring (one emitter each, fired three times)
		local rp = ringPump(c, "roarRing", HOL, flatTo, 0.5, 0.3)
		local dr = (tier <= 2 and onGround) and darkRing(c, feet + UP * 0.45, 1.6) or nil
		for k, dt in ipairs({ 0, 0.06, 0.12 }) do
			after(c, dt, function()
				fire(rp, feet + UP * (0.15 + k * 0.08), 1, UP, (k == 2) and EMBER or HOL)
				if dr then
					dr(28 + k * 5)
				end
			end)
		end
		dropPumps(c, { "plate", "stripe" }, 0.2)
		after(c, 0.2, function()
			dropPumps(c, { "roarRing" }, 0.5)
		end)
		snd(c, "Thunder", 1.0, 0.55)
		snd(c, "Boom", 0.8, 0.7)
		snd(c, "HitHeavy", 0.6, 0.5)
		if tier <= 2 then
			-- vertical rings: one facing the lens, one in the roar's own plane (along his look), one across it
			T(FX.ring(f, chest, ctx.camFacing(chest), 2, 14 * camK(chest) * MK, HOL, 0.35, { alpha = 0.4 }), 0.4)
			after(c, 0.05, function()
				local fp = chest + look * 1.5
				T(FX.ring(f, fp, look, 1.5, 15 * camK(fp) * MK, CRIM, 0.4, { alpha = 0.45 }), 0.45)
				T(FX.ring(f, chest, look:Cross(UP), 1.5, 13 * MK, EMBER, 0.35, { alpha = 0.3 }), 0.4)
			end)
			-- the distortion shell, the blast of dark smoke and red streaks, the cone of the roar out of his mouth
			FX.shell(f, chest, 1, 6 * MK, HOL, 0.35, Enum.Material.ForceField)
			darkPuff(c, chest, 30, { speed = 34, drag = 5, s0 = 1.2, s1 = 3.2, life = 0.85 })
			T(FX.streaks(f, chest, { color = HOL, color2 = EMBER, count = 60, speed = { 60, 130 }, size = 0.45, life = 0.32 }), 0.37)
			local mouth = head and (head.CFrame * Vector3.new(0, -0.3 * head.Size.Y / 1.2, -0.7 * head.Size.Z / 1.2)) or (chest + UP * 0.8)
			T(FX.streaks(f, mouth, {
				dir = (look + UP * 0.12).Unit, spread = 26, color = BONE, color2 = HOL, count = 34, speed = { 70, 140 }, size = 0.4, life = 0.3,
			}), 0.35)
			T(FX.glow(f, chest, glowFor(chest, 7), HOL, 0.35, { alpha = 0.3 }), 0.4)
			FX.light(f, chest, HOL, 8, 34, 0.55)
			SH("reiatsuFlame", f, feet + UP * 0.3, {
				black = true, color2 = HOL, count = c.mode and 14 or 10, height = c.mode and 9 or 6, size = 1.4, life = 0.6, spread = 30,
			})
			if onGround then
				dustRing(c, feet, 14, 60, { life = 1.2, s0 = 2, s1 = 6 })
				FX.rubble(f, feet, { count = 10, radius = 3.5, up = { 20, 40 }, out = { 18, 36 } })
				SH("cracks", f, feet, 9, 9 * MK, HOL, 2.0)
				if tier == 1 then
					shockLines(c, feet + UP * 0.12, c.mode and 18 or 14, 2, 15 * MK, CRIM, 0.32)
					after(c, 0.08, function()
						FX.rubble(f, feet, { count = 8, radius = 6, up = { 28, 55 }, out = { 26, 46 }, min = 0.4, max = 1.2 })
					end)
				end
			end
			if c.mode then
				after(c, 0.18, function()
					fire(rp, feet + UP * 0.45, 1, UP, CRIM) -- a fourth, crimson wave
				end)
			end
		end
		-- the rocks that rose while the mask formed are hurled out
		if c.rocks then
			local rk = c.rocks
			c.rocks = nil
			call(rk, "drop")
			for _, r in ipairs(rk.list or {}) do
				local p = r.part
				if p and p.Parent then
					local out = flat(p.Position - feet, FX.randUnit())
					p.AssemblyLinearVelocity = out * rng:NextNumber(30, 52) + UP * rng:NextNumber(16, 30)
					p.AssemblyAngularVelocity = FX.randUnit() * rng:NextNumber(8, 16)
				end
			end
		end
		if c.isLocal then
			try("impact", ctx.impact, { tint = HOL, tint2 = BONE, flashAlpha = 0.14 })
			try("vignette", ctx.vignette, 0.3, 0.9, HOL)
			try("shake", ctx.shake, 1.4, 0.8, 20, 10)
		elseif camD < 140 then
			try("shake", ctx.shake, 0.8 * (1 - camD / 140), 0.55, 20)
		end
		if c.aura then
			call(c.aura, "set", 60)
			after(c, 0.3, function()
				call(c.aura, "set", 30)
			end)
		end
	end

	-- the bodies the roar blew back: the 2 nearest the camera bloom full size, the rest only spark
	local function roarBodies(c, models)
		local f = c.f
		local list = {}
		for _, m in ipairs(models or {}) do
			local t = torsoOf(m)
			if t then
				table.insert(list, { m = m, t = t, dd = ctx.camDist(t.Position) })
			end
		end
		table.sort(list, function(a, b)
			return a.dd < b.dd
		end)
		for i, b in ipairs(list) do
			local p = b.t.Position
			if b.dd <= REDUCED then
				if i <= 2 then
					T(FX.sparks(f, p, { color = HOL, color2 = EMBER, count = 12, speed = { 15, 35 }, size = 0.4 }), 0.65)
					T(FX.glow(f, p, glowFor(p, 4), HOL, 0.25), 0.3)
				elseif i <= 6 then
					SH("bodyArc", f, b.m, HOL, 0.07)
				end
				if i == 1 then
					local g = groundAt(p)
					T(SH("dust", f, g + UP * 0.5, flat(p - c.origin) * 8 + UP * 3, { count = 2, s0 = 2, s1 = 5, life = 1.2 }), 1.25)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- THE BLITZ
	local SEQ = { "A", "B", "C", "A", "C", "B", "C", "A" } -- the chop only on the odd (higher) spots
	local ROLL = { A = 180, B = 45, C = -90 }
	local function rootCF(pos, face)
		return CFrame.lookAt(pos, pos + face)
	end
	local function cutColor(i)
		return CUT_COLORS[(i - 1) % #CUT_COLORS + 1]
	end

	-- he leaves one spot and appears at the next: a flickering afterimage where he was (and an echo half way), a flash
	-- and a star glint at both ends, a streak between
	local function relocate(c, i, fromCF, toPos, toFace)
		local f = c.f
		local a, b = fromCF.Position + UP * 1.0, toPos + UP * 1.0
		local tier = tierOf(b)
		local col = cutColor(i)
		if tier <= 2 then
			local g = ghostAt(c, fromCF, (i % 2 == 1) and BLACK or CRIM, (i % 2 == 1) and 0.35 or 0.45, 0.3, i % 2 == 1)
			if g then
				for j, dt in ipairs({ 0.05, 0.09, 0.14 }) do
					after(c, dt, function()
						if g.Parent then
							local hide = (j % 2 == 1)
							for _, p in ipairs(g:GetDescendants()) do
								if p:IsA("BasePart") then
									p.LocalTransparencyModifier = hide and 1 or 0
								end
							end
						end
					end)
				end
			end
			if tier == 1 and i > 1 then
				ghostAt(c, fromCF:Lerp(rootCF(toPos, toFace), 0.5), CRIM, 0.62, 0.12, false)
			end
		end
		local pa, pb = glowPump(c, "depart", CRIM), glowPump(c, "arrive", HOL)
		setGlowSize(pa, glowFor(a, 2.4))
		setGlowSize(pb, glowFor(b, 2.4))
		fire(pa, a, 1)
		fire(pb, b, 1, nil, col)
		if tier == 1 then
			glint(c, b, 3.2, col, 0.16)
			if room(c, 6) then
				SH("slashLine", f, a, b, { black = true, edge = col, width = 0.08, draw = 0, hold = 0.03, life = 0.2 })
			end
		end
		if c.mode and tier == 1 then
			fire(ringPump(c, "arriveRing", CRIM), b, 1, ctx.camFacing(b))
		end
		snd(c, "Whoosh", 0.35, 2.2)
	end

	local function slashFrame(c, i, s)
		local f = c.f
		local Hp = c.hover
		local chest = s.pos + UP * 1.2
		local typ = SEQ[(i - 1) % #SEQ + 1]
		local roll = ROLL[typ] + math.clamp(s.tilt or 0, -40, 40) * 0.4
		local cf = CFrame.lookAt(chest, Vector3.new(Hp.X, chest.Y * 0.4 + Hp.Y * 0.6, Hp.Z)) * CFrame.Angles(0, 0, math.rad(roll))
		local tier = tierOf(Hp)
		local col, col2 = cutColor(i), cutColor(i + 1)
		local R = c.mode and 5.1 or 4.5
		if room(c, 45, HERO_CAP) then
			SH("slashArc", f, cf, R, { sweep = 160, black = true, core = BLACK, edge = col, width = c.mode and 0.95 or 0.8, life = 0.28, draw = 0.05 })
		end
		-- the afterimage arc: thinner, a beat behind, the next colour (every cut in the mode)
		if tier == 1 and room(c, 40, c.mode and HERO_CAP or BUDGET) then
			after(c, 0.03, function()
				SH("slashArc", f, cf * CFrame.Angles(0, 0, math.rad(14)), R + 0.8, {
					sweep = 130, black = true, core = BLACK, edge = col2, width = 0.45, life = 0.2, draw = 0.06, glint = false,
				})
			end)
		end
		local hasBody = c.target ~= nil and not c.dropped
		if tier <= 2 then
			local right = cf.RightVector
			local mid = Hp + (chest - Hp).Unit * 0.4
			local line = SH("slashLine", f, mid - right * 2.6, mid + right * 2.6, {
				black = true, edge = col, width = 0.14, draw = 0.04, hold = 0.12, life = 0.25,
			})
			if line and i == c.nSlashes then
				after(c, 0.14, function()
					call(line, "shatter")
				end)
			end
			if hasBody then
				local g = glowPump(c, "hit", HOL)
				setGlowSize(g, glowFor(Hp, 3.5))
				fire(g, Hp, 1, nil, col)
				fire(sparkPump(c), Hp, 12, nil, col)
			end
			if tier == 1 then
				glint(c, Hp + (chest - Hp).Unit * 0.8, 4, col, 0.18)
			end
			fire(ringPump(c, "ring", HOL), Hp, 1, ctx.camFacing(Hp), hasBody and col or CRIM)
			if c.mode then
				after(c, 0.03, function()
					fire(ringPump(c, "ring2", CRIM), Hp, 1, (cf.LookVector + UP * 0.3).Unit)
				end)
			end
		end
		local tp = torsoOf(c.target)
		if hasBody then
			snd(c, "Hit2", 0.7, 1.1 + i * 0.05, tp)
		end
		snd(c, "Whoosh", 0.5, 1.8)
		if c.isLocal then
			try("shake", ctx.shake, 0.3, 0.08, 30)
		end
		local tr = c.slashTracks[i]
		if tr then
			try("freeze", ctx.freeze, tr, 0.03)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- THE CHARGE at F (finisherAt - windup): the Getsuga gathering on the blade
	local function chargeFrame(c, F, prevCF, nSl)
		local char, f = c.char, c.f
		local tier = c.tier
		relocate(c, nSl + 1, prevCF, F, c.aim)
		snd(c, "Swell", 0.7, 1.4)
		snd(c, "Crackle", 0.6, 1.0)
		snd(c, "Rise", 0.45, 0.9)
		dropPumps(c, SLASH_PUMPS_HIT, 0.2) -- the last cut's sparks finish, then the cut sites go
		if c.aura then
			-- the blade's black flames take over from the body aura for the finisher (emitter budget)
			call(c.aura, "Destroy")
			c.aura = nil
		end
		if tier > 2 then
			return
		end
		if not c.blade then
			c.blade = SH("bladeGlow", char, { black = true })
		end
		call(c.blade, "set", 1)
		local wind = c.windup
		local mid = bladeAt(c, "mid") or (F + UP * 1.4)
		if tier == 1 then
			T(FX.streaks(f, mid, { inward = 7, count = 30, color = HOL, color2 = EMBER, life = wind * 0.8, size = 0.4 }), wind + 0.4)
			converge(c, mid, c.mode and 16 or 12, 6.5, wind * 0.85, { color = CRIM, dark = BLACK })
			SH("reiatsuFlame", f, F - UP * 0.6, { black = true, color2 = HOL, count = 6, height = 4, size = 1.1, life = 0.5, spread = 35 })
		end
		-- a glow gathering on the edge, growing every step, with crimson arcs crawling over the blade
		local steps = 5
		for j = 0, steps - 1 do
			after(c, wind * j / steps, function()
				local m2 = bladeAt(c, "mid")
				if not m2 then
					return
				end
				local g = glowPump(c, "gather", HOL)
				setGlowSize(g, glowFor(m2, (1.0 + j * 0.55) * (c.mode and 1.2 or 1)))
				fire(g, m2, 1)
				if j % 2 == 0 and room(c, 12) then
					FX.arcs(f, m2, 1.3 + j * 0.15, { count = 2, colors = { CRIM, EMBER }, width = 0.06 })
				end
			end)
		end
	end

	-- the finisher camera (caster only): from behind his right shoulder through the charge and the release (FOV
	-- squeezed, then kicked wide), then swinging round to his face as he lands and the mask cracks; handed back at the
	-- shatter (<= 1.2 s)
	local function finisherShot(c)
		local aim, Hp, F = c.aim, c.hover, c.F
		local R = aim:Cross(UP)
		local wind, hs = c.windup, c.hitStop
		local camA = F - aim * 7 + R * 6 + UP * 2.4
		local lookA = Hp + aim * 3 + UP * 0.2
		local tA = wind + hs + 0.12
		local start = c.finAt - wind
		local dur = math.clamp(c.shatterAt + 0.02 - start, 0.3, 1.2)
		try("shot", ctx.shot, {
			char = c.char, t0 = c.t0 + start, dur = dur, cutColor = HOL, fov = 62,
			path = function(e, _, _, head)
				local push = math.clamp(e / wind, 0, 1)
				push = push * push
				local kick = math.clamp((e - wind) / 0.1, 0, 1)
				kick = 1 - (1 - kick) ^ 3
				local pos = F + (camA - F) * (1 - 0.16 * push + 0.12 * kick)
				local look = lookA
				local fov = 62 - 8 * push + 20 * kick - 6 * math.clamp((e - wind - 0.1) / 0.3, 0, 1)
				if e > tA and head and head.Parent then
					local b = math.clamp((e - tA) / 0.32, 0, 1)
					b = b * b * (3 - 2 * b)
					local hp = head.Position
					pos = pos:Lerp(hp + aim * 4.2 + R * 4 + UP * 0.7, b)
					look = look:Lerp(hp + UP * 0.05, b)
					fov = fov + (50 - fov) * b
				end
				return pos, look, fov
			end,
		})
	end

	---------------------------------------------------------------------------------------------------
	-- THE FINISHER money frame and its aftermath
	local function finisherFrame(c)
		if c.finished_ then
			return
		end
		c.finished_ = true
		local f = c.f
		local Hp, dir = c.hover, c.aim
		local tier = tierOf(Hp)
		local camD = ctx.camDist(Hp)
		local close = camD < 40
		local MK = c.mode and 1.3 or 1
		if c.finTrack then
			try("freeze", ctx.freeze, c.finTrack, c.hitStop)
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was callout "HollowGetsuga")
		dropPumps(c, { "depart", "arrive", "arriveRing", "gather" }, 0) -- the blitz and the charge are over
		-- the point-blank crescent: born at H, it tears down the line (wall-clamped range from the server), turned about
		-- UP so its face (not its edge) shows to the camera behind / right of him
		local span = c.mode and 18 or 14
		local cr = SH("crescent", f, { black = true, span = span, depth = c.mode and 4.2 or 3.5, tilt = -30 })
		if cr then
			local range = math.max(c.waveRange or 40, 2)
			c.wave = {
				cr = cr, t0 = os.clock(), from = Hp + dir * 1.0, to = Hp + dir * range, dir = dir, dur = WAVE_TIME * math.clamp(range / 40, 0.5, 1.5),
			}
			call(cr, "place", CFrame.lookAt(c.wave.from, c.wave.from + dir) * CFrame.Angles(0, FACE_YAW, 0), 0.6)
			if cr.host then
				try("sound", ctx.sound, "Whoosh", cr.host, 0.8, 0.7)
			end
		end
		-- the explosion: rings in three planes round a black core inside a crimson fireball
		local flatTo = math.clamp((camD - 4) * 2, 14, 26 * MK)
		T(FX.ring(f, Hp, UP, 2, flatTo, HOL, 0.45, { alpha = 0.25 }), 0.5)
		T(FX.ring(f, Hp + dir * 1.5, dir, 1, 12 * MK, HOL, 0.35, { alpha = 0.2 }), 0.4)
		T(FX.ring(f, Hp, ctx.camFacing(Hp), 1, (close and 9 or 11) * camK(Hp) * MK, EMBER, 0.25, { alpha = close and 0.35 or 0.1 }), 0.3)
		T(FX.glow(f, Hp, glowFor(Hp, 2.5), CORE, 0.18, { brightness = close and 2.4 or 3 }), 0.23)
		T(FX.glow(f, Hp, glowFor(Hp, 10 * MK), HOL, 0.4, { alpha = 0.3 }), 0.45)
		if tier <= 2 then
			FX.shell(f, Hp, 0.4, 2.6 * MK, BLACK, 0.22, PLASTIC)
			local fb = FX.shell(f, Hp, 0.8, 4.6 * MK, HOL, 0.3, NEON)
			if fb and close then
				fb.Transparency = 0.4
			end
			darkPuff(c, Hp, 40, { speed = 30, drag = 4.5, s0 = 1.4, s1 = 3.6, life = 1.0 })
			T(FX.streaks(f, Hp, { dir = dir, spread = 75, color = HOL, color2 = EMBER, count = 75, speed = { 70, 180 }, size = 0.5, life = 0.35 }), 0.4)
			FX.light(f, Hp, HOL, 12, 48, 0.5)
			-- the explosion's second wave: heavier dark smoke rolling up and out
			after(c, 0.07, function()
				darkPuff(c, Hp + UP * 0.5, 26, { speed = 22, drag = 3.5, s0 = 2, s1 = 4.6 * MK, life = 1.3, rise = 6 })
			end)
			if tier == 1 then
				burstRays(c, Hp, c.mode and 16 or 12, 13 * MK, { HOL, BONE, BLACK, CRIM }, 0.4, HERO_CAP)
				-- the crescent burst: crescents flaring round the impact in the plane across the line
				local nb = c.mode and 4 or 3
				local a0 = rng:NextNumber(0, TAU)
				local cols = { CRIM, BONE, HOL, GOLD }
				local across = dir:Cross(UP).Unit
				for j = 1, nb do
					local ang = a0 + (j - 1) * TAU / nb
					local u = (across * math.cos(ang) + UP * math.sin(ang)).Unit
					local cf = CFrame.fromMatrix(Hp, dir:Cross(u), dir)
					after(c, 0.015 * j, function()
						if room(c, 40, HERO_CAP) then
							SH("slashArc", f, cf, c.mode and 7 or 5.5, {
								sweep = 150, black = true, core = BLACK, edge = cols[j], width = c.mode and 1.1 or 0.9, life = 0.34, draw = 0.06, glint = false,
							})
						end
					end)
				end
			end
		end
		snd(c, "Boom", 1.0, 0.85)
		snd(c, "Thunder", 0.8, 0.9)
		snd(c, "HitHeavy", 0.9, 1)
		snd(c, "Cannon", 0.6, 0.7)
		after(c, 0.12, function()
			snd(c, "Thunder", 0.6, 0.6)
		end)
		if c.isLocal then
			try("impact", ctx.impact, { tint = HOL, tint2 = BONE, flashAlpha = 0.2 })
			try("shake", ctx.shake, 1.5, 0.7, 22, 12)
		elseif camD < 160 then
			try("shake", ctx.shake, 0.9 * (1 - camD / 160), 0.5, 22)
			if camD < 90 then
				try("flash", ctx.flash, HOL, 0.08 * (1 - camD / 90), 0.25)
			end
		end
		if c.blade then
			local b = c.blade
			c.blade = nil
			after(c, 0.15, function()
				call(b, "stop")
			end)
		end
		-- the crater under H (only when the ground is close under it, like the server's): a scorch, a glowing core,
		-- cracks, rim flames, dust and rubble; then a slow residual ring and embers rising
		after(c, 0.04, function()
			local g, ok = groundAt(Hp)
			if not ok or Hp.Y - g.Y > 14 or tier > 2 then
				return
			end
			local R = c.mode and 6.5 or 5
			-- the scorch discs only on part floors: on terrain the server carves a real crater under them
			local hit = FX.groundHit(Hp, 20)
			if room(c, 2, HERO_CAP) and not (hit and hit.Instance == workspace.Terrain) then
				groundDisc(c, g + UP * 0.05, R, CHAR, PLASTIC, 0.12, 1.4, 1.2)
				groundDisc(c, g + UP * 0.08, R * 0.42, HOL, NEON, 0.25, 0.25, 1.0)
			end
			SH("cracks", f, g, c.mode and 12 or 10, R * 1.7, HOL, 2.2)
			dustRing(c, g, 16, 70, { life = 1.4, s0 = 2.5, s1 = 7 })
			if tier == 1 then
				FX.rubble(f, g, { count = 8, radius = R * 0.6, up = { 30, 60 }, out = { 20, 40 } })
				after(c, 0.26, function()
					-- black flames licking up off the crater (one burst, fanned wide)
					SH("reiatsuFlame", f, g + UP * 0.2, { black = true, color2 = HOL, count = 10, height = 3.5, size = 1.2, life = 0.6, spread = 55 })
				end)
			end
			after(c, 0.35, function()
				T(FX.ring(f, g + UP * 0.25, UP, 3, math.min(R * 3.4, reachOf(g, 24) * 2), HOL, 1.2, { alpha = 0.55 }), 1.5)
				if tier == 1 then
					FX.sparks(f, Hp, {
						color = EMBER, color2 = CRIM, count = 16, speed = { 2, 6 }, accel = Vector3.new(0, 5, 0), drag = 1.5, life = 1.8, size = 0.25,
					})
				end
			end)
		end)
		-- the trench the wave's pressure gouges under it once it has passed, smoking black (ground close under H only)
		after(c, 0.12, function()
			local g1, ok1 = groundAt(Hp + dir * 1.5)
			local L = math.min(math.max(c.waveRange or 40, 2), 18)
			local g2, ok2 = groundAt(Hp + dir * L)
			if ok1 and ok2 and Hp.Y - g1.Y < 9 and tier <= 2 then
				SH("trench", f, g1, g2, { black = true, width = 2.4, life = 2.2 })
				local mid = (g1 + g2) / 2
				local host = FX.part("HollowTrenchSmoke", Enum.PartType.Block, PLASTIC, WHITE, nil)
				host.Transparency = 1
				host.Size = Vector3.new(1.6, 0.4, math.max((g2 - g1).Magnitude, 1))
				host.CFrame = CFrame.lookAt(mid + UP * 0.3, g2 + UP * 0.3)
				host.Parent = f
				local e = FX.emitter(host, {
					Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3, Rate = 18,
					Size = nsk({ { 0, 0.8 }, { 1, 2.6 } }), Transparency = nsk({ { 0, 0.5 }, { 0.6, 0.7 }, { 1, 1 } }),
					Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(1.5, 3.5), EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(15, 15), Drag = 1, Acceleration = Vector3.new(0, 1.5, 0), Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-40, 40),
				})
				task.delay(1.5, function()
					if e.Parent then
						e.Rate = 0
					end
				end)
				Debris:AddItem(host, 3)
			end
		end)
	end

	-- a body hit by the finisher: the victim rides a crimson comet with black flames bursting off it, the wave's others
	-- get a black-crimson hit layer
	local function cometOn(c, m, strong, rank)
		local t = torsoOf(m)
		if not t then
			return
		end
		local f = c.f
		local p = t.Position
		local dd = ctx.camDist(p)
		if strong or (rank or 1) <= 3 then
			T(FX.sparks(f, p, { color = HOL, color2 = EMBER, count = strong and 16 or 10, speed = { 20, 50 } }), 0.65)
		end
		if dd > REDUCED then
			return
		end
		local tr = FX.trail(t, cs(HOL, BLOOD), strong and 1.6 or 1.0, 0.35, { tail = 0, alpha = 0.1 })
		local a0, a1 = tr.Attachment0, tr.Attachment1
		task.delay(strong and 1.3 or 0.9, function()
			if tr.Parent then
				tr.Enabled = false
			end
		end)
		Debris:AddItem(tr, 2)
		Debris:AddItem(a0, 2)
		Debris:AddItem(a1, 2)
		if strong and dd <= FULL then
			SH("reiatsuFlame", f, p, { black = true, color2 = HOL, count = 6, height = 3, size = 1.2, life = 0.5, spread = 60 })
			local a = Instance.new("Attachment")
			a.Name = "HollowComet"
			a.Parent = t
			local e = FX.emitter(a, {
				Texture = TEX.star, Color = cs(HOL, EMBER), Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(1, 4),
				SpreadAngle = Vector2.new(180, 180), Size = nsk({ { 0, 0.5 }, { 1, 0 } }), Drag = 2, Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-200, 200), Brightness = 2, Rate = 45,
			})
			task.delay(0.9 + c.hitStop, function()
				if e.Parent then
					e.Rate = 0
				end
			end)
			Debris:AddItem(a, 1.8)
		else
			local right = flat(c.aim):Cross(UP)
			SH("slashLine", f, p - right * 2.2 + UP * 0.6, p + right * 2.2 - UP * 0.6, { black = true, width = 0.12, life = 0.25, hold = 0.04 })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the mask cracks (red light leaking out of the cracks), then bursts; the chiburi
	local function crackFrame(c)
		local m = c.mask
		if m and m.state ~= "shattered" then
			m.crackT = os.clock()
		end
		local head = partOf(c.char, "Head")
		if head and c.tier <= 2 then
			local face = head.CFrame * Vector3.new(0, 0, -0.7 * head.Size.Z / 1.2)
			SH("shards", c.f, face, { count = 5, color = BONE, size = 0.15, speed = { 2, 6 }, life = 0.7 })
			T(FX.glow(c.f, face, glowFor(face, 1.5), HOL, 0.15), 0.2)
			FX.light(c.f, face, HOL, 3, 8, 0.6)
			if c.tier == 1 then
				for j = 0, 5 do
					after(c, 0.05 + j * 0.06, function()
						local hd = partOf(c.char, "Head")
						if not hd then
							return
						end
						local pts = CRACKS[(j % #CRACKS) + 1]
						local pt = pts[#pts]
						local s = hd.Size / 1.2
						local wp = hd.CFrame * Vector3.new(pt[1] * s.X, pt[2] * s.Y, (surf(pt[1], pt[2]) - 0.03) * s.Z)
						local g = glowPump(c, "leak", HOL)
						setGlowSize(g, glowFor(wp, 0.8))
						fire(g, wp, 1)
					end)
				end
				after(c, 0.5, function()
					dropPumps(c, { "leak" }, 0.3)
				end)
			end
		end
		snd(c, "Shatter", 0.4, 1.6, head)
		snd(c, "Sizzle", 0.35, 1.4, head)
		flickerEyes(c)
		if c.aura then
			call(c.aura, "set", 15)
		end
	end

	local function shatterFrame(c)
		local head = partOf(c.char, "Head")
		local f = c.f
		local face = head and (head.CFrame * Vector3.new(0, 0, -0.7)) or (hrpPos(c) + UP * 1.6)
		local look = head and head.CFrame.LookVector or c.aim
		if head and c.eyes then
			eyeStreaks(c, head, true)
		end
		shatterMask(c, false)
		if c.eyes then
			call(c.eyes, "Destroy")
			c.eyes = nil
		end
		snd(c, "Shatter", 0.9, 1.0, head)
		snd(c, "Sizzle", 0.4, 1.0, head)
		if c.isLocal then
			try("shake", ctx.shake, 0.5, 0.3, 26)
		end
		if c.tier <= 2 then
			SH("shards", f, face, { count = c.mode and 18 or 14, color = BONE, size = 0.35, speed = { 12, 28 }, dir = look, gravity = 30, life = 1.2 })
			darkPuff(c, face, 20, { speed = 10, drag = 3.5, s0 = 0.6, s1 = 2.0, life = 0.8, reach = 3 })
			T(FX.sparks(f, face, { color = CRIM, color2 = EMBER, count = 14, speed = { 8, 22 }, size = 0.32 }), 0.65)
			T(FX.glow(f, face, glowFor(face, 2.2), HOL, 0.2), 0.25)
			T(FX.ring(f, face + look * 0.3, look, 0.5, 5 * camK(face), BONE, 0.25, { alpha = 0.35 }), 0.35)
			SH("ash", f, face + look * 0.6, { count = 24, radius = 1.5, life = 2.0, rise = 3 })
		end
		if c.aura then
			local a = c.aura
			c.aura = nil
			call(a, "set", 6)
			task.delay(0.5, function()
				call(a, "Destroy")
			end)
		end
		-- the aftermath: black wisps trail off his face for 1.2 s, embers drift up
		if head and c.tier == 1 then
			local att = Instance.new("Attachment")
			att.Name = "HollowWisps"
			att.Position = Vector3.new(0, 0, -0.5)
			att.Parent = head
			local e = FX.emitter(att, {
				Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3, Rate = 26,
				Size = nsk({ { 0, 0.35 }, { 0.5, 0.9 }, { 1, 1.3 } }), Transparency = nsk({ { 0, 0.45 }, { 0.6, 0.7 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.8, 2), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(35, 35), Drag = 1, Acceleration = Vector3.new(0, 2.5, 0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-50, 50),
			})
			task.delay(1.2, function()
				if e.Parent then
					e.Rate = 0
				end
			end)
			Debris:AddItem(att, 2.4)
			after(c, 0.15, function()
				FX.sparks(f, hrpPos(c) + UP * 1.2, {
					color = EMBER, color2 = CRIM, count = 12, speed = { 2, 7 }, accel = Vector3.new(0, 6, 0), drag = 1.5, life = 1.6, size = 0.26,
				})
			end)
		end
	end

	-- the chiburi: the blade flicked clean down to his right - a blood spray off it, a splatter on the ground, a small
	-- arc; reiatsu smoke rising off his shoulders as he settles
	local function chiburiFrame(c)
		local char, f = c.char, c.f
		snd(c, "Whoosh", 0.6, 1.6)
		if c.tier > 2 then
			return
		end
		local tip = bladeAt(c, "tip")
		local hrp = partOf(char, "HumanoidRootPart")
		local look = hrp and flat(hrp.CFrame.LookVector, c.aim) or c.aim
		local right = look:Cross(UP)
		local flick = (right * 0.8 - UP * 0.6 + look * 0.2).Unit
		if tip then
			FX.sparks(f, tip, {
				dir = flick, spread = 22, color = BLOOD, color2 = CRIM, count = 14, speed = { 16, 32 }, accel = Vector3.new(0, -60, 0), size = 0.28,
				life = 0.5, brightness = 1,
			})
			local g, ok = groundAt(tip)
			if ok and room(c, 4) then
				local a = g + right * 0.8 + look * 0.4 + UP * 0.06
				SH("slashLine", f, a, a + (right * 2.6 - look * 0.6), { black = true, edge = BLOOD, width = 0.1, draw = 0.06, hold = 0.9, life = 0.6 })
			end
		end
		if c.tier == 1 and hrp and room(c, 30) then
			local chest = hrp.Position + UP * 0.8
			SH("slashArc", f, CFrame.lookAt(chest, chest + flick) * CFrame.Angles(0, 0, math.rad(90)), 3.2, {
				sweep = 100, black = true, core = BLACK, edge = CRIM, width = 0.4, life = 0.16, draw = 0.04, glint = false,
			})
		end
		local ut = partOf(char, "UpperTorso")
		if ut and c.tier == 1 then
			local att = Instance.new("Attachment")
			att.Name = "HollowSettle"
			att.Position = Vector3.new(0, 0.6, 0)
			att.Parent = ut
			local e = FX.emitter(att, {
				Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3, Rate = 14,
				Size = nsk({ { 0, 0.5 }, { 0.5, 1.2 }, { 1, 1.8 } }), Transparency = nsk({ { 0, 0.55 }, { 0.6, 0.75 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(1, 2.5), EmissionDirection = Enum.NormalId.Top,
				SpreadAngle = Vector2.new(40, 40), Drag = 1, Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-40, 40),
			})
			task.delay(1.0, function()
				if e.Parent then
					e.Rate = 0
				end
			end)
			Debris:AddItem(att, 2.4)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- HollowCast { id, userId, t0, origin, aim, target, hover, roarAt, blitzAt, slashes = { { t, pos, face, tilt } },
	--   finisherAt, finisherPos, crackAt, shatterAt, mode, lock?, landAt?, hitStop?, waveRange?, slashEvery?, windup? }
	H.HollowCast = function(d)
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster ~= nil and caster == ctx.player
		local t0 = d.t0 or ctx.now()
		local e0 = ctx.now() - t0
		local shatterAt = num(d.shatterAt, num(HC.ShatterAt, 3.19))
		if e0 > shatterAt - 0.1 then
			return -- the mask is already breaking: nothing left worth joining
		end
		local hrp0 = partOf(char, "HumanoidRootPart")
		local origin = d.origin or (hrp0 and hrp0.Position) or Vector3.zero
		local aim = flat(d.aim or Vector3.new(0, 0, -1))
		local slashes = type(d.slashes) == "table" and d.slashes or {}
		local Hp = d.hover or (origin + aim * 9 + UP * 3)
		local finAt = num(d.finisherAt, num(HC.FinisherAt, 2.3))
		local wind = math.clamp(num(d.windup, num(HC.WindUp, 0.3)), 0.1, 0.5)
		local roarAt = num(d.roarAt, num(HC.RoarAt, 0.95))
		local c = {
			key = keyOf(d), id = d.id, userId = d.userId, char = char, isLocal = isLocal, t0 = t0, origin = origin, aim = aim,
			target = typeof(d.target) == "Instance" and d.target or nil, hover = Hp, f = ctx.castFolder("Hollow", 8),
			mode = d.mode == true or (char ~= nil and ctx.inMode(char)), ghosts = {}, pumps = {}, tracks = {}, slashTracks = {},
			nSlashes = #slashes, hitStop = num(d.hitStop, num(HC.FinisherHitStop, 0.16)), waveRange = d.waveRange, finisherAt = finAt,
			finAt = finAt, windup = wind, shatterAt = shatterAt, roarAt = roarAt,
			lock = num(d.lock, num(HC.Lock, 3.9)), cancelled = false, finished = false,
		}
		c.bk = char ~= nil and ctx.form(char) == "Bankai"
		c.tier = tierOf(origin)
		do
			local old = casts[c.key]
			if old and old ~= c then
				cancel(old)
			end
			casts[c.key] = c
		end
		local tier = c.tier
		local crackAt = num(d.crackAt, num(HC.CrackAt, 2.74))
		local landAt = num(d.landAt, shatterAt - 0.55)
		local blitzAt = num(d.blitzAt, num(HC.BlitzAt, 1.2))
		local every = num(d.slashEvery, num(HC.SlashEvery, 0.13))
		local F = d.finisherPos or (Hp - aim * 5.5 - UP * 1.2)
		c.F = F

		-- 0.00: callout, root, the mask clip, the drone; the caster's camera squeezes in
		c.track = play(c, "HollowMask", 0)
		if isLocal then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (was callout "Hollow")
			local rest = c.lock + c.hitStop - math.max(e0, 0)
			if rest > 0 then
				try("root", ctx.root, rest, aim)
			end
			if e0 < 0.5 then
				try("lean", ctx.lean, { fov = -7, drop = 0.3, attack = 0.7, hold = 0.15, release = 0.3 })
				try("vignette", ctx.vignette, 0.2, 0.9, HOL)
			end
		end
		if e0 < 0.3 then
			snd(c, "Drone", 0.6, 0.8)
		end

		-- THE MASK FORMS in layers (veins, film, plates, stripes, eyes: all driven per frame by updateMask)
		local head = partOf(char, "Head")
		if head then
			buildMask(c, head, e0 > STRIPES_AT)
		end
		if char and tier == 1 and e0 < SWIRL_TO - 0.1 then
			buildSwirl(c)
		end
		at(c, SWIRL_FROM, function()
			if tier <= 2 and char then
				c.aura = SH("aura", char, { black = true, color2 = HOL, rate = 40 })
			end
		end, 1.5)
		if tier == 1 then
			for i = 0, 4 do
				at(c, SWIRL_FROM + i * 0.15, function()
					local ut = partOf(char, "UpperTorso")
					if ut then
						local side = (i % 2 == 0) and 1 or -1
						SH("reiatsuFlame", c.f, ut.CFrame * Vector3.new(0.85 * side, 0.7, 0.1), {
							black = true, color2 = HOL, count = 4, height = 2.6 + i * 0.3, size = 0.9, life = 0.5,
						})
					end
				end)
			end
		end
		-- dark reiatsu seeping off his face while the veins crawl and the film congeals
		at(c, CRAWL_FROM, function()
			local hd = partOf(char, "Head")
			if hd and tier == 1 then
				local att = Instance.new("Attachment")
				att.Name = "HollowSeep"
				att.Position = Vector3.new(0, 0, -0.55 * hd.Size.Z / 1.2)
				att.Parent = hd
				c.seep = FX.emitter(att, {
					Texture = TEX.smoke, Color = cs(SMOKE, HDARK), LightEmission = 0, LightInfluence = 0.3, Rate = 34,
					Size = nsk({ { 0, 0.25 }, { 0.5, 0.6 }, { 1, 0.9 } }), Transparency = nsk({ { 0, 0.4 }, { 0.6, 0.65 }, { 1, 1 } }),
					Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(0.6, 1.8), EmissionDirection = Enum.NormalId.Front,
					SpreadAngle = Vector2.new(60, 60), Drag = 1.5, Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-60, 60),
				})
				local cam = workspace.CurrentCamera
				if not (isLocal and cam and (cam.CFrame.Position - hd.Position).Magnitude < 3) then
					c.seep:Emit(6)
				end
				Debris:AddItem(att, 2)
			end
		end, 0.3)
		at(c, STRIPES_AT + 0.05, function()
			stopEmit(c.seep)
			c.seep = nil
		end, 2)
		-- pebbles lift round his feet and tremble while the plates crack into place (hurled out by the roar)
		at(c, FORM_AT + 0.04, function()
			if tier == 1 and char then
				local feet, ok = groundAt(hrpPos(c))
				if ok and room(c, 8) then
					local rk = FX.liftRocks(c.f, feet, 7.5, c.mode and 8 or 6)
					for _, r in ipairs(rk.list or {}) do
						r.height = rng:NextNumber(1.0, 3.0)
						r.delay = rng:NextNumber(0, 0.2)
						r.rise = rng:NextNumber(0.45, 0.75)
					end
					c.rocks = rk
				end
			end
		end, 0.2)
		at(c, CRAWL_FROM + 0.1, function()
			snd(c, "Crackle", 0.5, 0.7)
		end)
		at(c, FILM_AT, function()
			snd(c, "Sizzle", 0.5, 0.8)
		end)
		at(c, FORM_AT + 0.2, function()
			snd(c, "Void", 0.6, 1.2)
		end)
		at(c, STRIPES_AT, function()
			local hd = partOf(char, "Head")
			if hd and tier <= 2 then
				local p = hd.CFrame * Vector3.new(-0.25 * hd.Size.X / 1.2, 0.4 * hd.Size.Y / 1.2, -0.7 * hd.Size.Z / 1.2)
				T(FX.glow(c.f, p, glowFor(p, 1.6), HOL, 0.18), 0.23)
				snd(c, "Zap", 0.35, 1.4, hd)
			end
		end)
		at(c, INHALE_AT, function()
			inhale(c)
		end, 0.1)
		-- the eyes ignite: gold on black, flickering on, a flare across each
		at(c, EYES_AT, function()
			if char and tier <= 2 then
				c.eyes = SH("eyes", char, { color = GOLD, sclera = true })
				call(c.eyes, "set", 0)
				for j, v in ipairs({ 0.7, 0.15, 1 }) do
					after(c, 0.025 * j, function()
						call(c.eyes, "set", v)
					end)
				end
				eyeStreaks(c, partOf(char, "Head"), false)
				snd(c, "Zap", 0.4, 2.0, partOf(char, "Head"))
			end
		end, 1.5)

		-- THE ROAR
		at(c, roarAt, function()
			roarFrame(c)
		end, 0.15)

		-- the blitz camera (the caster's own view orbits the victim, pushing in; the finisher shot takes over from it)
		if isLocal and e0 < blitzAt then
			local shotAt = blitzAt - SHOT_LEAD
			local shotDur = math.clamp(finAt - wind + 0.05 - shotAt, 0.2, 1.2)
			at(c, shotAt, function()
				local cam = workspace.CurrentCamera
				local off = cam and ((cam.CFrame.Position - Hp) * FLATV) or Vector3.zero
				if off.Magnitude < 1 then
					off = -aim
				end
				local th0 = math.atan2(off.Z, off.X)
				try("shot", ctx.shot, {
					char = char, t0 = t0 + shotAt, dur = shotDur, cutColor = HOL, fov = 66,
					path = function(_, a)
						local k = a * a * (3 - 2 * a)
						local th = th0 + math.rad(SHOT_SWEEP) * k
						local r = SHOT_R + (SHOT_R1 - SHOT_R) * k
						local pos = Hp + Vector3.new(math.cos(th), 0, math.sin(th)) * r + UP * (SHOT_H - k)
						return pos, Hp + UP * 0.4, 66 - 6 * k
					end,
				})
			end, 0.4)
		end

		-- the blitz: each slash's blink, hold, clip and cut (the mode's black blade glow rides the whole blitz)
		if c.mode and tier <= 2 then
			at(c, blitzAt - 0.05, function()
				c.blade = SH("bladeGlow", char, { black = true })
				call(c.blade, "set", 0.5)
				if c.aura then
					call(c.aura, "Destroy") -- the black blade takes over from the body aura (emitter budget)
					c.aura = nil
				end
			end, 0.6)
		end
		local prevCF = CFrame.lookAt(origin, origin + aim)
		for i, s in ipairs(slashes) do
			local fromCF = prevCF
			local T = num(s.t, blitzAt + (i - 1) * every)
			local nextT = slashes[i + 1] and num(slashes[i + 1].t, T + every) or (finAt - wind)
			local pos, face = s.pos, flat(s.face or (Hp - s.pos))
			prevCF = rootCF(pos, face)
			at(c, T - 0.05, function()
				c.slashTracks[i] = play(c, "HollowSlash" .. SEQ[(i - 1) % #SEQ + 1], T - 0.05)
			end, 0.04)
			at(c, T - 0.025, function()
				relocate(c, i, fromCF, pos, face)
				if isLocal then
					try("move", ctx.move, { t0 = t0 + T - 0.025, dur = 0.02, from = pos, to = pos, face = face, hold = (nextT - T) + 0.06 })
				end
			end, 0.04)
			at(c, T, function()
				slashFrame(c, i, s)
			end, 0.05)
		end

		-- the charge at F, then the point-blank Getsuga (HollowFinisher adds the bodies)
		at(c, finAt - 0.32, function()
			c.finTrack = play(c, "HollowFinisher", finAt - 0.32)
		end, 0.05)
		at(c, finAt - wind, function()
			if isLocal then
				try("move", ctx.move, {
					t0 = t0 + finAt - wind, dur = 0.02, from = F, to = F, face = aim, hold = wind + c.hitStop + 0.04, exitVel = UP * -20,
				})
			end
			chargeFrame(c, F, prevCF, #slashes)
			if isLocal and e0 < blitzAt + 0.3 then
				finisherShot(c)
			end
		end, 0.1)
		at(c, finAt, function()
			finisherFrame(c)
		end, 0.25)

		-- the landing, the lingering arcs on the blade, the crack, the shatter, the chiburi
		at(c, landAt, function()
			if c.finTrack then
				call(c.finTrack, "stop", 0.05)
			end
			c.landTrack = play(c, "HollowLand", landAt)
		end, 0.5)
		at(c, landAt + 0.06, function()
			local g, ok = groundAt(hrpPos(c))
			snd(c, "Hit", 0.5, 0.8)
			if ok and tier <= 2 then
				T(FX.ring(c.f, g + UP * 0.2, UP, 1.5, 12, HOL, 0.35, { alpha = 0.3 }), 0.4)
				dustRing(c, g, 10, 18, { s0 = 1.5, s1 = 4.5, life = 1.0 })
			end
			if isLocal then
				try("shake", ctx.shake, 0.3, 0.25, 30)
			end
		end, 0.3)
		for _, dt in ipairs({ 0.25, 0.62 }) do
			at(c, landAt + dt, function()
				local m2 = tier == 1 and bladeAt(c, "mid")
				if m2 and room(c, 8) then
					FX.arcs(c.f, m2, 0.9, { count = 1, colors = { CRIM, EMBER }, width = 0.05 })
				end
			end, 0.1)
		end
		at(c, crackAt, function()
			crackFrame(c)
		end, 0.3)
		at(c, shatterAt, function()
			shatterFrame(c)
		end, 0.5)
		at(c, landAt + CHIBURI_AT, function()
			chiburiFrame(c)
		end, 0.3)
		task.delay(math.max(shatterAt + BURN_LIFE + 0.5 - math.max(e0, 0), 0.1), function()
			if not c.cancelled then
				finish(c)
			end
		end)
	end

	-- a cast this client never saw start (joined mid-cast): a minimal record so the late beats still read
	local function stub(d, name, pos, aim, eAt)
		local c = {
			key = keyOf(d), id = d.id, userId = d.userId, t0 = ctx.now() - (eAt or 0), origin = pos, hover = pos, aim = aim,
			f = ctx.castFolder(name, 4), ghosts = {}, pumps = {}, tracks = {}, slashTracks = {}, hitStop = num(HC.FinisherHitStop, 0.16),
			tier = tierOf(pos), cancelled = false, finished = false,
		}
		c.isLocal = false -- a stub never drives the local camera
		casts[c.key] = c
		task.delay(3, function()
			if casts[c.key] == c then
				casts[c.key] = nil
			end
		end)
		return c
	end

	-- HollowRoar { id, userId, pos, models }
	H.HollowRoar = function(d)
		local c = casts[keyOf(d)]
		if c and c.cancelled then
			return
		end
		if not c then
			c = stub(d, "HollowRoar", d.pos or Vector3.zero, Vector3.new(0, 0, -1), num(HC.RoarAt, 0.95))
		end
		roarBodies(c, d.models)
	end

	-- HollowSlash { id, userId, i, model, pos }: a cut landed - the body jolts, the tally counts
	H.HollowSlash = function(d)
		local c = casts[keyOf(d)]
		if c and c.cancelled then
			return
		end
		local m = d.model
		local t = torsoOf(m)
		local pos = (t and t.Position) or d.pos
		if not pos then
			return
		end
		local f = c and c.f or ctx.castFolder("HollowSlash", 2)
		local col = cutColor(num(d.i, 1))
		if ctx.camDist(pos) <= REDUCED then
			if c then
				local j = glowPump(c, "jolt", CRIM)
				setGlowSize(j, glowFor(pos, 1.8))
				fire(j, pos + FX.randUnit() * 0.6, 1, nil, col)
			end
			if typeof(m) == "Instance" and (not c or room(c, 8)) then
				SH("bodyArc", f, m, (math.random() < 0.6) and col or HOL, 0.07)
			end
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (no "×n" hit tally per cut)
	end

	-- HollowFinisher { id, userId, pos, dir, model, others, range? }
	H.HollowFinisher = function(d)
		local c = casts[keyOf(d)]
		if c and c.cancelled then
			return
		end
		if not c then
			c = stub(d, "HollowFinisher", d.pos or Vector3.zero, flat(d.dir or Vector3.new(0, 0, -1)), num(HC.FinisherAt, 2.3))
			c.waveRange = d.range
			finisherFrame(c)
		elseif not c.finished_ then
			finisherFrame(c)
		end
		if typeof(d.model) == "Instance" then
			cometOn(c, d.model, true)
		end
		local others = type(d.others) == "table" and d.others or {}
		local list = {}
		for _, m in ipairs(others) do
			local t = torsoOf(m)
			if t then
				table.insert(list, { m = m, dd = ctx.camDist(t.Position) })
			end
		end
		table.sort(list, function(a, b)
			return a.dd < b.dd
		end)
		for i, b in ipairs(list) do
			if i <= 6 then
				cometOn(c, b.m, false, i)
			end
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (no "×n" finisher tally)
	end

	-- HollowCancel { id, userId }: the caster died / unequipped / the kit changed mid-cast
	H.HollowCancel = function(d)
		local key = keyOf(d)
		for k, c in pairs(casts) do
			if (d.id ~= nil and k == key) or (d.id == nil and c.userId == d.userId) then
				cancel(c)
			end
		end
	end

	-- every Heartbeat: the swirl, the mask, the crescent's flight, the mask debris; a dead caster loses his mask
	H.__update = function(clock, dt)
		frame += 1
		dt = math.min(dt or 1 / 60, 0.1)
		for _, c in pairs(casts) do
			if c.t0 then
				local e = ctx.now() - c.t0
				local hum = c.char and c.char:FindFirstChildOfClass("Humanoid")
				if not c.cancelled and not c.finished and c.char and (not c.char.Parent or not hum or hum.Health <= 0) then
					cancel(c)
				end
				if not c.cancelled then
					updateSwirl(c, e, clock)
					updateMask(c, e, clock)
				end
				local w = c.wave
				if w then
					local k = math.clamp((os.clock() - w.t0) / w.dur, 0, 1)
					local ease = 1 - (1 - k) ^ 2
					local pos = w.from:Lerp(w.to, ease)
					call(w.cr, "place", CFrame.lookAt(pos, pos + w.dir) * CFrame.Angles(0, FACE_YAW, 0), 0.6 + 0.4 * math.min(k * 4, 1))
					if k >= 1 then
						call(w.cr, "split", w.dir)
						c.wave = nil
					end
				end
				updateDebris(c, dt)
			end
		end
	end

	-- the local character died or the kit was unequipped: end the local caster's own casts
	H.__reset = function()
		for _, c in pairs(casts) do
			if c.isLocal and not c.finished then
				cancel(c)
			end
		end
	end

	return H
end
