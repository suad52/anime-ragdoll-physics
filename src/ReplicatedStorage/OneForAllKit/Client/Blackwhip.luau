--!nocheck
-- OneForAllKit.Client.Blackwhip: playback of R, BLACKWHIP -> ST. LOUIS SMASH (design_A §7), FLAIR CUT, on every client.
-- Server beats (Config pass Flair_Blackwhip): tendrils leave 0.24, each body latches at 0.24 + d/220 (WhipLatch), the
-- reel runs to 0.92, the kick lands at 0.98 (WhipKick), busy until 1.80 (the clip's rise ends at 1.72 clip time, 1.80
-- cast time once the 0.08 hit-stop has frozen it). Everything else here is client-side, laid on the same server clock:
--   0.00 GATHER   forearms crossed, black smoke billowing off his back and forearms, green crackle up both arms,
--                 light sucked into his hands, a rising aura, pebbles lifting, dust drawn in, a collapsing ring
--   0.06          four smoke-black "wing" tendrils creep out of his back and writhe (they ride his torso all cast)
--   0.24 LASH     arms flung wide: a whip-crack, a pressure ring, a smoke burst, the whips race out to every body
--   latch         a whip-crack, a spark burst, a crack ring, green arcs and a black puff at every body (WhipLatch)
--   0.30 - 0.92   the DRAG: each body hauled in on a comet trail with dust kicked up under it, afterimages and
--                 lightning crawling over it; the yank (0.50) sucks light and air into the gather point
--   0.665 LOAD    wound right; the lightning drains into his right leg (it crackles until the kick)
--   0.72 HOP      off the left toes: a take-off ring, dust, speed lines; green foot trails draw the spin
--   0.79-0.93     the mid-air spin: three afterimages, whirl rings, rising whooshes, the wings whirling round him
--   0.98 ST. LOUIS SMASH: hit-stop, the title, an impact frame, four layered crescents (the foot's white-hot arc, the
--                 green kick arc, the pale air arc, the black whip arc), shock rings in three planes, glows, streaks,
--                 sparks off the foot, outward arcs, rubble, dust, the lifted pebbles blasted out, a wind gust; every
--                 tendril dissolves into black smoke; the bodies scatter on comet trails with sparks and afterimages
--   0.98-1.22     the held extension: residual rings off the foot, sparks, the leg still crackling and steaming
--   1.46 (+hit-stop = 1.54) LAND: a superhero crouch - dust ring, ground ring, rubble, crackle at his feet
--   to ~4.2 s     aftermath: smoke wisps where the whips were, embers drifting up, lingering arcs, a slow dust settle,
--                 residual rings, the leg's arcs and steam dying out
-- Broadcast kinds: WhipCast, WhipLatch, WhipKick, WhipCancel (payloads unchanged). Casts are keyed "userId#id" (the
-- server's cast ids are per-player counters, so two players' casts can share an id).
-- Part budget: a governor counts the cast's folder plus its afterimages; the core layers (the whips, the crescents,
-- rings, glows, streaks) always draw, the optional ones (lightning arcs, afterimages) ask room() first, so a 7-body
-- 100% cast or an avatar with a dozen accessories stays under BUDGET parts.
return function(ctx)
	local H = {}
	local Debris = game:GetService("Debris")

	local FX, S, PAL, SND = ctx.FX, ctx.S, ctx.PAL, ctx.SND
	local CFG = ctx.CFG or {}
	local B = CFG.Blackwhip or {}
	local FL = type(B.Flair) == "table" and B.Flair or {}
	local CALLOUTS = CFG.Callouts or {}
	local UP = ctx.UP or Vector3.yAxis
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local BLACK = Color3.new(0, 0, 0)
	local TEX = FX.TEX or {}
	local nsk = FX.nsk

	-- server beats (Config: Blackwhip.*)
	local LASH = B.LashAt or 0.24
	local KICK = B.KickAt or 0.98
	local SPEED = B.Speed or 220
	local HITSTOP = B.HitStop or 0.08
	local LOCK = B.Lock or 1.8
	-- client beats (Config: Blackwhip.Flair.*); clip times - a hit adds the hit-stop to everything after the kick
	local ROOT_T = FL.RootTime or (LOCK - HITSTOP)
	local SPROUT_AT = FL.SproutAt or 0.06
	local LEAN_AT = FL.LeanAt or 0.30
	local REEL_AT = FL.ReelAt or 0.50
	local LOAD_AT = FL.LoadAt or 0.665
	local LIFT_AT = FL.LiftAt or 0.72
	local SPIN_AT = type(FL.SpinAt) == "table" and FL.SpinAt or { 0.79, 0.86, 0.93 }
	local LAND_AT = FL.LandAt or 1.46 -- clip time; a hit adds the hit-stop (the clip is frozen for it)
	local TAIL = FL.TailTime or 3.2 -- the aftermath runs this long after the kick

	-- distance gating (camera distance to the caster / the gather point)
	local TENDRIL_DIST, CRACKLE_DIST = 250, 160
	local WING_DIST, SMOKE_DIST, GHOST_DIST, HEAVY_DIST = 160, 180, 120, 220
	local ARC_DIST, OTHERS_SHAKE = 160, 100
	local ARC_EVERY, GHOST_EVERY, MAX_GHOSTED = 0.2, 0.2, 2

	local SOURCES = S.OFA_SOURCES or { "RightHand", "LeftHand", "BackRight", "BackLeft", "RightLowerArm", "LeftLowerArm" }
	local LEG_R = { "RightFoot", "RightLowerLeg", "RightUpperLeg" }
	local ARM_R = S.ARM_R or { "RightHand", "RightLowerArm", "RightUpperArm" }
	local ARM_L = S.ARM_L or { "LeftHand", "LeftLowerArm", "LeftUpperArm" }
	-- the wings: { source, offset in the UpperTorso's frame (x right, y up, z back), sway phase }
	local WINGS = {
		{ "BackRight", Vector3.new(2.3, 2.7, 2.3), 0.4 },
		{ "BackLeft", Vector3.new(-2.3, 2.7, 2.3), 1.9 },
		{ "BackRight", Vector3.new(3.5, 0.5, 1.7), 3.1 },
		{ "BackLeft", Vector3.new(-3.5, 0.5, 1.7), 4.6 },
	}

	local casts = {} -- ["userId#id"] = the running cast
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	-- the part governor (FLAIR budget <= ~350 per cast). The optional layers stop at BUDGET, which leaves headroom for
	-- the core layers that can land after them (a latch's band + flash, the kick's crescents) and the sound anchors
	local BUDGET = 290
	local function partsNow(c)
		local n = 0
		if c.f and c.f.Parent then
			for _, d in ipairs(c.f:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
		end
		local gs = c.ghostFolders
		for i = #gs, 1, -1 do
			if gs[i].Parent then
				n += #gs[i]:GetChildren()
			else
				table.remove(gs, i)
			end
		end
		return n
	end
	local function room(c, need, cap)
		return c == nil or partsNow(c) + need <= (cap or BUDGET)
	end
	local HERO_CAP = 335 -- the spin's afterimages are the beat itself: they may use the headroom

	---------------------------------------------------------------------------------------------------
	-- helpers
	local function cs(a, b)
		return ColorSequence.new(a, b or a)
	end

	-- every call into a builder another module owns goes through here, so one bad layer never kills a beat
	local function try(fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warn("[OneForAll.Blackwhip] " .. tostring(r))
			return nil
		end
		return r
	end

	local function glowFor(pos, size)
		if type(S.glowFor) == "function" then
			return S.glowFor(pos, size)
		end
		return size * math.clamp(ctx.camDist(pos) / 30, 0.45, 1)
	end

	local ghostSize = setmetatable({}, { __mode = "k" })
	local function ghostOf(c, model, color, alpha, life, cap)
		if typeof(model) ~= "Instance" or not model.Parent then
			return nil
		end
		local need = ghostSize[model]
		if not need then
			need = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
					need += 1
				end
			end
			ghostSize[model] = need
		end
		if not room(c, need, cap) then
			return nil
		end
		local g = try(S.ghost or ctx.ghost, model, color, alpha, life)
		if c and typeof(g) == "Instance" then
			table.insert(c.ghostFolders, g)
		end
		return g
	end

	local function crackAt(pos, vol)
		ctx.soundAt("WhipCrack", pos, vol) -- Config.Sounds.WhipCrack, or its fallback Hit2 @ 1.8
	end
	-- a sound riding a part (no anchor part made for it), or at a point when the part is gone
	local function soundOn(part, id, vol, speed, pos)
		if part and part.Parent then
			ctx.sound(id, part, vol, speed)
		elseif pos then
			ctx.soundAt(id, pos, vol, speed)
		end
	end

	local function windGust(vec, attack, hold, release)
		local fn = (type(S.windGust) == "function" and S.windGust) or ctx.windGust
		try(fn, vec, attack, hold, release)
	end

	local function torsoOf(m)
		return m and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart"))
	end

	local function partOf(char, name)
		local p = char and char.Parent and char:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p or nil
	end

	local function groundAt(pos)
		local y = ctx.groundY(pos)
		return Vector3.new(pos.X, y or (pos.Y - 3), pos.Z), y ~= nil
	end

	local function bez(a, b, c, d, u)
		local v = 1 - u
		return a * (v * v * v) + b * (3 * v * v * u) + c * (3 * v * u * u) + d * (u * u * u)
	end

	-- the source a tendril grows from (Shared's handles "BackRight" / "BackLeft"); holds its last point
	local function sourceOf(char, name)
		if type(S.tendrilSource) == "function" then
			return S.tendrilSource(char, name)
		end
		return function()
			local p = partOf(char, name) or partOf(char, "HumanoidRootPart")
			return p and p.Position or nil
		end
	end

	-- Shared's Tendril (§3.5) and its phase switches
	local function newTendril(f, getSource, opts)
		local T = S.Tendril
		local new = T and (T.new or T.New)
		return try(new, f, getSource, opts)
	end
	local function phase(rec, name, ...)
		if not rec or rec.gone or not rec.t then
			return
		end
		if name == "snap" or name == "destroy" then
			rec.gone = true
		end
		local t = rec.t
		local fn = t[name == "latched" and "latch" or name]
		if type(fn) == "function" then
			try(fn, t, ...)
		end
	end

	-- dark smoke (the Blackwhip's own colour, not ground dust)
	local function smokeProps(rate, o)
		o = o or {}
		return {
			Texture = TEX.smoke, Color = cs(PAL.Whip, Color3.fromRGB(52, 56, 60)), LightEmission = 0, LightInfluence = 0.15,
			Size = nsk({ { 0, o.s0 or 0.5 }, { 0.4, (o.s1 or 1.8) * 0.8 }, { 1, o.s1 or 1.8 } }),
			Transparency = nsk({ { 0, 1 }, { 0.12, o.a or 0.3 }, { 0.6, 0.6 }, { 1, 1 } }),
			Lifetime = NumberRange.new(o.l0 or 0.5, o.l1 or 0.9), Speed = NumberRange.new(o.v0 or 1.5, o.v1 or 4),
			EmissionDirection = o.dir or Enum.NormalId.Top, SpreadAngle = Vector2.new(o.spread or 40, o.spread or 40),
			Drag = 2, Acceleration = Vector3.new(0, o.rise or 3, 0), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-70, 70), Rate = rate or 0,
		}
	end

	-- one invisible host with one emitter, moved along every tendril and burst there: the whips dissolve into smoke
	-- (one emitter for the whole cast instead of one per tendril; the particles stay where they were emitted)
	local function smokeAlong(f, recs)
		if #recs == 0 then
			return
		end
		local host = FX.part("WhipDissolve", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		host.Transparency = 1
		host.Parent = f
		local e = FX.emitter(host, smokeProps(0, { s0 = 0.7, s1 = 2.6, l0 = 0.7, l1 = 1.3, v0 = 0.5, v1 = 2.5, spread = 180, rise = 2.5, a = 0.25 }))
		local spark = FX.emitter(host, {
			Texture = TEX.star, Color = cs(PAL.Spark, PAL.Cowl), Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(4, 14), SpreadAngle = Vector2.new(180, 180), Size = nsk({ { 0, 0.35 }, { 1, 0 } }),
			Drag = 3, Acceleration = Vector3.new(0, -12, 0), Rotation = NumberRange.new(0, 360), Brightness = 2, Rate = 0,
		})
		for _, rec in ipairs(recs) do
			local t = rec.t
			if t and t.S0 and t.tip then
				local a, b = t.S0, t.tip
				local P1, P2 = t.P1 or a:Lerp(b, 0.33), t.P2 or a:Lerp(b, 0.66)
				local n = math.clamp(math.floor((b - a).Magnitude / 4), 1, 6)
				for i = 1, n do
					local p0, p1 = bez(a, P1, P2, b, (i - 1) / n), bez(a, P1, P2, b, i / n)
					local L = (p1 - p0).Magnitude
					if L > 0.05 then
						host.Size = Vector3.new(0.5, 0.5, L)
						host.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
						e:Emit(math.clamp(math.floor(L * 1.2), 2, 6))
						if i == n then
							spark:Emit(6)
						end
					end
				end
			end
			phase(rec, "destroy")
		end
		Debris:AddItem(host, 2)
	end

	-- black smoke billowing off his back and both forearms (4 emitters on the character, for the whole cast)
	local function smokeRig(char)
		local rig = { atts = {}, ems = {} }
		local ut = partOf(char, "UpperTorso")
		local spots = {
			{ ut, Vector3.new(0.45, 0.45, 0.5), Enum.NormalId.Back, 30 },
			{ ut, Vector3.new(-0.45, 0.45, 0.5), Enum.NormalId.Back, 30 },
			{ partOf(char, "RightLowerArm"), Vector3.zero, Enum.NormalId.Top, 180 },
			{ partOf(char, "LeftLowerArm"), Vector3.zero, Enum.NormalId.Top, 180 },
		}
		for _, s in ipairs(spots) do
			if s[1] then
				local a = Instance.new("Attachment")
				a.Name = "OFAWhipSmoke"
				a.Position = s[2]
				a.Parent = s[1]
				local e = FX.emitter(a, smokeProps(0, { s0 = 0.45, s1 = 1.9, dir = s[3], spread = s[4], v0 = 1.5, v1 = 4.5 }))
				table.insert(rig.atts, a)
				table.insert(rig.ems, e)
				Debris:AddItem(a, LOCK + 4)
			end
		end
		function rig.rate(_, r)
			for _, e in ipairs(rig.ems) do
				if e.Parent then
					e.Rate = r
				end
			end
		end
		function rig.emit(_, n)
			for _, e in ipairs(rig.ems) do
				if e.Parent then
					e:Emit(n)
				end
			end
		end
		function rig.stop(_, after)
			rig:rate(0)
			for _, a in ipairs(rig.atts) do
				Debris:AddItem(a, after or 1.2)
			end
		end
		return rig
	end

	-- a dragged body's dust: one host that rides the ground under it, one emitter, on while it is hauled low and fast
	local function dragRig(c, m, t)
		local g = groundAt(t.Position)
		local col = PAL.Steam
		if type(S.groundColor) == "function" then
			col = S.groundColor(FX.groundHit(t.Position, 12)) or col
		end
		local host = FX.part("WhipDrag", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		host.Transparency = 1
		host.Size = Vector3.new(1.6, 0.3, 1.6)
		host.CFrame = CFrame.new(g + UP * 0.3)
		local e = FX.emitter(host, {
			Texture = TEX.smoke, Color = cs(col, col:Lerp(BLACK, 0.25)), LightInfluence = 1, LightEmission = 0,
			Size = nsk({ { 0, 1.2 }, { 0.4, 3 }, { 1, 4.2 } }), Transparency = nsk({ { 0, 0.4 }, { 0.5, 0.62 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(55, 55),
			Drag = 2, Acceleration = Vector3.new(0, 2, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
			Rate = 0,
		})
		host.Parent = c.f
		Debris:AddItem(host, 6)
		local r = {
			host = host, em = e, last = t.Position, lastClock = os.clock(), nextGhost = 0, ghosts = false,
			trail = try(S.bodyTrail, m, cs(PAL.Core, PAL.Cowl), 1.1, 1.4),
		}
		if c.ghosted < MAX_GHOSTED and ctx.camDist(t.Position) <= GHOST_DIST then
			c.ghosted += 1
			r.ghosts = true
		end
		return r
	end
	local function dropDrag(r)
		if r.em and r.em.Parent then
			r.em.Rate = 0
		end
		if r.host then
			Debris:AddItem(r.host, 1.2)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- everything persistent this cast owns is let go (smoke = the whips dissolve into black smoke)
	local function release(c, smoke)
		local recs = {}
		for _, list in ipairs({ c.tendrils, c.wings }) do
			for _, rec in ipairs(list) do
				if rec.t and rec.t.dead then
					rec.gone = true -- it already retracted into his hand and destroyed itself
				elseif not rec.gone then
					table.insert(recs, rec)
				end
			end
		end
		if smoke and c.heavy then
			try(smokeAlong, c.f, recs) -- destroys each whip as it bursts it into smoke
		end
		for _, rec in ipairs(recs) do
			phase(rec, "snap") -- anything not dissolved (far away, or a failed burst) whips away and fades
		end
		c.latched = {}
		for m, r in pairs(c.drag) do
			dropDrag(r)
			c.drag[m] = nil
		end
		if c.smoke then
			c.smoke:stop(1.2)
			c.smoke = nil
		end
		if c.aura then
			for _, em in ipairs(c.aura:GetChildren()) do
				if em:IsA("ParticleEmitter") then
					em.Enabled = false
				end
			end
			Debris:AddItem(c.aura, 1)
			c.aura = nil
		end
		if c.rocks then
			try(c.rocks.drop, c.rocks, c.rockPush)
			c.rocks = nil
		end
	end

	local function dropFootTrails(c)
		for _, tr in ipairs(c.footTrails) do
			if tr.Parent then
				tr.Enabled = false
			end
			Debris:AddItem(tr, 0.4)
			if tr.Attachment0 then
				Debris:AddItem(tr.Attachment0, 0.4)
			end
			if tr.Attachment1 then
				Debris:AddItem(tr.Attachment1, 0.4)
			end
		end
		c.footTrails = {}
	end

	---------------------------------------------------------------------------------------------------
	-- t 0.98: ST. LOUIS SMASH, the money frame, its held extension and the aftermath
	local function kickFrame(c)
		if c.kicked or c.cancelled then
			return
		end
		c.kicked = true
		local f, G, aim, char = c.f, c.G, c.aim, c.char
		local accent = c.mode and PAL.Crimson or PAL.Cowl
		local ember = c.mode and PAL.Ember or PAL.Cowl
		local hrp = partOf(char, "HumanoidRootPart")
		local footP = partOf(char, "RightFoot")
		local foot = footP and footP.Position or (G - c.aim * 2)
		local pivot = (hrp and hrp.Position or (G - aim * 4.5 - UP)) + UP * 0.9 + aim * 0.3
		local gG = groundAt(G)
		local heavy = c.heavy
		-- no white-outs: within 40 studs of this camera the camera-facing rings and the white core glow are thinner,
		-- and the flat ring stops short of the lens (a ring whose rim sweeps under the camera floods the screen)
		local camG = ctx.camDist(G)
		local close = camG < 40
		local flatTo = math.clamp((camG - 4) * 2, 20, 36)
		c.legUntil, c.legEvery = os.clock() + 1.8, 0.11 -- the leg keeps crackling, sparser, through the aftermath

		local function after(dt, fn)
			task.delay(dt, function()
				if not c.cancelled then
					try(fn)
				end
			end)
		end

		if not c.whiff and c.track then
			try(ctx.freeze, c.track, HITSTOP)
		end
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the ST. LOUIS SMASH title is gone)
		c.rockPush = aim * 45 + UP * 8
		release(c, true) -- every whip (and wing) dissolves into black smoke as the kick lands
		dropFootTrails(c)

		-- the crescents, in layers: the foot's own white-hot arc, the green kick arc, the pale air arc, the black whip arc
		local first = c.mode and { core = PAL.Core, edge = PAL.Crimson, mid = PAL.Cowl } or nil
		try(S.kickArc, f, pivot, aim, 3.0, math.rad(-10), { core = WHITE, edge = accent, mid = PAL.Core })
		try(S.kickArc, f, G + UP * 0.6, aim, 6.5, math.rad(-12), first)
		if heavy then
			after(0.03, function()
				S.kickArc(f, G + UP * 0.3, aim, 9, math.rad(-6), { core = WHITE, edge = PAL.Air, mid = PAL.Air })
			end)
			after(0.07, function()
				S.kickArc(f, G + aim * 2.5, aim, 11.5, math.rad(4), { core = PAL.Whip, mid = PAL.Emerald, edge = accent })
			end)
		end
		-- shock rings in three planes
		try(FX.ring, f, G, UP, 2, 26, PAL.Air, 0.4, { alpha = 0.15 })
		try(FX.ring, f, G, ctx.camFacing(G), 1, close and 10 or 12, WHITE, 0.22, { alpha = close and 0.3 or 0 })
		after(0.07, function()
			FX.ring(f, G, UP, 3, flatTo, accent, 0.55, { alpha = 0.35 })
		end)
		if heavy then
			after(0.03, function()
				FX.ring(f, G + aim * 1.5, aim, 1, close and 11 or 14, PAL.Spark, 0.3, { alpha = close and 0.35 or 0.1 })
			end)
			after(0.14, function()
				FX.ring(f, G + aim * 3, (UP + aim * 0.7).Unit, 4, 20, PAL.Air, 0.5, { alpha = 0.55 })
			end)
			-- the debris layers (past HEAVY_DIST only the crescents, rings, glows and streaks play)
			if room(c, 36) then
				try(FX.arcs, f, G, 5, { outward = true, count = 6, colors = { accent, PAL.Core }, width = 0.12 })
			end
			try(FX.rubble, f, G, { count = c.whiff and 5 or 10, radius = 4, up = { 25, 45 }, out = { 20, 40 }, dir = aim })
			try(S.dustRing, f, gG, 3, 6, 40)
		end
		if camG <= HEAVY_DIST then
			windGust(aim * 50, 0.04, 0.15, 0.6)
		end

		if c.whiff then
			soundOn(hrp, SND.Whoosh, 0.8, 1.4, G) -- the kick cuts empty air
			soundOn(hrp, "WindRoar", 0.45, nil, G)
			if c.isLocal then
				ctx.shake(0.35, 0.3, 24, 4)
			end
		else
			try(FX.glow, f, G, glowFor(G, 10), PAL.Core, 0.2, { brightness = close and 2.6 or 3.5 })
			try(FX.glow, f, G, glowFor(G, 18), accent, 0.45, { alpha = 0.25 })
			try(FX.glow, f, foot, glowFor(foot, 5), PAL.Core, 0.16)
			try(FX.streaks, f, G, {
				dir = aim, spread = 60, color = WHITE, color2 = accent, count = 50, speed = { 80, 180 }, size = 0.55, life = 0.35,
			})
			try(FX.sparks, f, foot, { dir = aim, spread = 50, color = PAL.Spark, color2 = accent, count = 18, speed = { 30, 70 } })
			try(FX.light, f, G, accent, 10, 34, 0.35)
			if heavy then
				try(FX.streaks, f, G, { color = WHITE, color2 = PAL.Cowl, count = 24, speed = { 50, 120 }, size = 0.4, life = 0.3 })
			end
			-- on his root part (G is 4.5 studs off it, well inside the 30-stud roll-off): no 8-second anchor parts
			soundOn(hrp, SND.Hit, 1, 0.85, G)
			soundOn(hrp, SND.HitHeavy, 0.9, 0.8, G)
			soundOn(hrp, SND.Boom, 0.55, 1.3, G)
			soundOn(hrp, SND.Thunder, 0.3, 1.7, G)
			soundOn(hrp, "WhipCrack", 0.6, nil, G) -- the whips snapping away
			if c.isLocal then
				try(FX.impact, { tint = PAL.Spark, lineColor = PAL.Spark, lineTime = 0.3, flashAlpha = 0.18, flashLife = 0.18 })
				ctx.shake(0.9, 0.45, 26, 8)
			else
				local dd = ctx.camDist(G)
				if dd < OTHERS_SHAKE then
					ctx.shake(0.35 * (1 - dd / OTHERS_SHAKE), 0.3, 26)
				end
			end
		end

		-- the held extension (0.98 -> 1.22): rings peel off the foot, sparks drip, the leg crackles and steams
		local function footNow()
			local p = partOf(char, "RightFoot")
			return p and p.Position or foot
		end
		after(0.08, function()
			local p = footNow()
			FX.ring(f, p, aim, 0.8, 7, accent, 0.25, { alpha = 0.3 })
			FX.sparks(f, p, { color = PAL.Spark, color2 = accent, count = 8, speed = { 6, 16 }, size = 0.3 })
		end)
		if heavy then
			after(0.16, function()
				FX.ring(f, footNow(), aim, 0.8, 9, PAL.Air, 0.3, { alpha = 0.45 })
			end)
			after(0.05, function()
				local p = partOf(char, "RightFoot")
				if p and type(S.steam) == "function" then
					local st = S.steam(p, 14)
					c.steam = st
					task.delay(1.6, function()
						if st then
							try(st.stop, st)
						end
					end)
				end
			end)
			if c.isLocal then
				after(0.24, function()
					ctx.shake(0.18, 0.2, 18)
				end)
			end
		end

		-- the aftermath: smoke where the whips were, embers drifting up, lingering arcs, a slow dust settle, rings
		if not heavy then
			return
		end
		after(0.12, function()
			local host = FX.anchor(f, G, TAIL + 1.5)
			local e = FX.emitter(host, smokeProps(12, { s0 = 1, s1 = 3.2, l0 = 1, l1 = 1.6, v0 = 0.5, v1 = 2, spread = 70, rise = 4, a = 0.4 }))
			host.Size = Vector3.new(5, 1.5, 5)
			task.delay(1.4, function()
				if e.Parent then
					e.Rate = 0
				end
			end)
		end)
		after(0.15, function()
			FX.sparks(f, G + UP * 0.5, {
				color = ember, color2 = PAL.Spark, count = 16, speed = { 3, 10 }, accel = Vector3.new(0, 7, 0), drag = 1.5,
				life = 1.6, size = 0.32,
			})
			soundOn(partOf(char, "HumanoidRootPart"), SND.Sizzle, 0.25, 0.8, G)
		end)
		after(0.2, function()
			S.dust(f, gG + UP * 0.4, UP * 2.5, { s0 = 4, s1 = 10, count = 4, life = 2.6 })
		end)
		after(0.35, function()
			FX.ring(f, gG + UP * 0.15, UP, 5, 18, PAL.CowlDeep, 1.1, { alpha = 0.55 })
		end)
		after(0.6, function()
			FX.sparks(f, G + UP, {
				color = ember, color2 = PAL.Core, count = 10, speed = { 2, 7 }, accel = Vector3.new(0, 6, 0), drag = 1.5,
				life = 1.8, size = 0.28,
			})
			S.dust(f, gG + aim * 3 + UP * 0.4, UP * 1.5 + aim * 2, { s0 = 3, s1 = 8, count = 3, life = 2.4 })
		end)
		for i, dt in ipairs({ 0.25, 0.5, 0.85, 1.25 }) do
			after(dt, function()
				if room(c, (i < 3) and 12 or 6) then
					FX.arcs(f, G + FX.randUnit() * 0.8, 2.4 - i * 0.3, { count = (i < 3) and 2 or 1, colors = { accent, PAL.Core }, width = 0.05 })
				end
			end)
		end
		after(1.1, function()
			FX.ring(f, G, aim, 4, 11, PAL.Air, 0.9, { alpha = 0.7 })
		end)
	end

	local function cancel(c)
		if c.cancelled then
			return
		end
		c.cancelled = true
		release(c, false)
		dropFootTrails(c)
		if c.steam then
			try(c.steam.stop, c.steam)
		end
		c.legUntil, c.armUntil = nil, nil
		if c.track and not c.kicked then
			try(c.track.stop, c.track, 0.2)
		end
		if c.isLocal then
			try(ctx.unroot)
		end
	end

	-- the record stays a while so a late WhipKick never re-plays the frame
	local function finish(c)
		release(c, false)
		dropFootTrails(c)
		c.finished = true
		task.delay(1, function()
			if casts[c.key] == c then
				casts[c.key] = nil
			end
		end)
	end

	local function newRecord(d, char, isLocal, t0, aim, G, whiff)
		local hrp = partOf(char, "HumanoidRootPart")
		local near = ctx.camDist(hrp and hrp.Position or G)
		return {
			id = d.id, key = keyOf(d), userId = d.userId, char = char, isLocal = isLocal, f = ctx.castFolder("Blackwhip", KICK + TAIL + 3),
			ghostFolders = {},
			t0 = t0, aim = aim, G = G, mode = d.mode or (char and ctx.inMode(char)) or false, whiff = whiff,
			tendrils = {}, wings = {}, byModel = {}, latched = {}, pending = {}, arcNext = {}, drag = {}, footTrails = {},
			ghosted = 0, near = near, heavy = near <= HEAVY_DIST, kicked = false, cancelled = false,
		}
	end

	---------------------------------------------------------------------------------------------------
	-- WhipCast { id, userId, t0, origin, aim, gather, lash, speed, kick, targets = { {model, slot, latch, s} }, whiffEnds, mode }
	H.WhipCast = function(d)
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster ~= nil and caster == ctx.player
		local t0 = d.t0 or ctx.now()
		local e = ctx.now() - t0
		local lash = d.lash or LASH
		local kick = d.kick or KICK
		local speed = d.speed or SPEED
		if e > kick + 0.5 then
			return -- the whole cast is already over
		end
		local hrp0 = partOf(char, "HumanoidRootPart")
		local origin = d.origin or (hrp0 and hrp0.Position) or Vector3.zero
		local aim = ctx.flat(d.aim or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
		local G = d.gather or (origin + aim * (B.GatherForward or 4.5) + UP * (B.GatherUp or 1))
		local targets = d.targets or {}
		local c = newRecord(d, char, isLocal, t0, aim, G, #targets == 0)
		local f = c.f
		do
			local old = casts[c.key]
			if old and old ~= c then
				cancel(old)
			end
			casts[c.key] = c
		end
		c.track = char and ctx.playClip(char, ctx.Clips.Blackwhip, e) or nil
		local accent = c.mode and PAL.Crimson or PAL.Cowl
		local shift = c.whiff and 0 or HITSTOP -- the clip is frozen for the hit-stop, so its later keys land later

		-- one beat on the shared clock: skipped once it is more than `slack` past
		local function at(T, fn, slack)
			local en = ctx.now() - t0
			if T < en - (slack or 0.05) then
				return
			end
			task.delay(math.max(T - en, 0), function()
				if c.cancelled then
					return
				end
				try(fn)
			end)
		end
		local function hrpPos()
			local h = partOf(char, "HumanoidRootPart")
			return h and h.Position or origin
		end
		local function hrpPart()
			return partOf(char, "HumanoidRootPart")
		end

		-- t 0.00-0.24: GATHER. Forearms crossed, a dark hum rising, smoke off his back, light drawn into his hands
		if isLocal then
			-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the BLACKWHIP callout is gone)
			local rest = ROOT_T + shift - math.max(e, 0)
			if rest > 0 then
				try(ctx.root, rest, aim)
			end
		end
		if char and e < lash - 0.03 then
			local hrp = partOf(char, "HumanoidRootPart")
			if hrp then
				ctx.sound(SND.Drone, hrp, 0.4, 1.5)
				ctx.sound(SND.Swell, hrp, 0.45, 1.25)
				ctx.sound(SND.Crackle, hrp, 0.5, 0.9)
			end
			if isLocal then
				ctx.shake(0.1, 0.26, 32, 0)
				try(ctx.lean, { pitch = 0, drop = 0, fov = -3, attack = 0.2, hold = 0.04, release = 0.12 })
			end
			c.armUntil = os.clock() + (lash + 0.06 - e)
			c.armNext = 0
			local gp, onGround = groundAt(origin)
			if c.near <= SMOKE_DIST then
				c.smoke = try(smokeRig, char)
				if c.smoke then
					c.smoke:rate(26)
				end
			end
			if c.near <= WING_DIST and hrp then
				c.aura = try(FX.aura, hrp, accent, PAL.Emerald, 30)
			end
			if c.heavy and onGround then
				try(FX.ring, f, gp + UP * 0.2, UP, 10, 1.5, accent, 0.26, { ease = "in", alpha = 0.35 })
				try(S.dustRing, f, gp, 3.5, 6, -7, { s0 = 1.2, s1 = 3.5, life = 1.0 }) -- dust drawn IN to his feet
				if c.near <= WING_DIST and type(FX.liftRocks) == "function" then
					c.rocks = try(FX.liftRocks, f, gp, 6, 6) -- pebbles lift with the gather; the kick blasts them out
				end
			end
			-- light sucked into his hands, and a glow swelling where the wrists cross
			for i, dt in ipairs({ 0.02, 0.1, 0.17 }) do
				at(dt, function()
					local rh, lh = partOf(char, "RightHand"), partOf(char, "LeftHand")
					if not rh or not lh then
						return
					end
					local mid = (rh.Position + lh.Position) / 2
					FX.glow(f, mid, glowFor(mid, 1.6 + i * 0.9), (i == 3) and PAL.Core or accent, 0.24, { alpha = 0.15 })
					if i < 3 and c.heavy then
						FX.streaks(f, mid, { inward = 5, count = 12, color = accent, color2 = PAL.Core, life = 0.22, size = 0.28 })
					end
				end)
			end
		end

		-- t 0.06: the wings - black tendrils creep out of his back and writhe there for the whole cast
		at(SPROUT_AT, function()
			if not char or c.near > WING_DIST then
				return
			end
			local n = (#targets <= 3) and 4 or 2
			local ut = partOf(char, "UpperTorso")
			for i = 1, n do
				local w = WINGS[i]
				local o = {
					segs = 5, w0 = 0.34, w1 = 0.08, speed = 30, wobble = 2.2, crackle = false, lashT = ctx.now(),
					endPoint = ut and (ut.CFrame * (w[2] * 0.6)) or (hrpPos() + UP * 2), maxLife = KICK + 2,
				}
				local rec = { t = newTendril(f, sourceOf(char, w[1]), o), off = w[2], ph = w[3] }
				if rec.t then
					table.insert(c.wings, rec)
				end
			end
		end, 0.4)

		-- t 0.24: LASH. Arms flung wide; every whip races out (whiff: three into the empty air)
		at(lash, function()
			local late = (ctx.now() - t0) - lash > 0.05
			local where = hrpPos()
			if not late then
				soundOn(hrpPart(), "WhipCrack", 0.8, nil, where)
				soundOn(hrpPart(), SND.Whoosh, 0.7, 1.7, where)
				soundOn(hrpPart(), SND.Zap, 0.35, 0.8, where)
				if isLocal then
					ctx.shake(0.3, 0.2, 28, 3)
				end
				if c.smoke then
					c.smoke:emit(14)
					c.smoke:rate(9)
				end
				local chest = partOf(char, "UpperTorso")
				local cp = chest and chest.Position or (where + UP)
				FX.ring(f, cp + aim * 1.2, aim, 1, 9, accent, 0.3, { alpha = 0.2 })
				if c.heavy then
					local gp, onGround = groundAt(where)
					if onGround then
						FX.ring(f, gp + UP * 0.2, UP, 2, 14, PAL.Emerald, 0.35, { alpha = 0.3 })
					end
					for _, n in ipairs({ "RightHand", "LeftHand" }) do
						local hand = partOf(char, n)
						if hand then
							FX.glow(f, hand.Position, glowFor(hand.Position, 3.5), accent, 0.18)
							FX.streaks(f, hand.Position, {
								dir = aim, spread = 25, count = 12, speed = { 50, 110 }, color = PAL.Core, color2 = accent, size = 0.35, life = 0.25,
							})
							if room(c, 12) then
								FX.arcs(f, hand.Position, 1.2, { count = 2, colors = { accent, PAL.Core }, width = 0.06 })
							end
						end
					end
				end
			end
			if not char or ctx.camDist(where) > TENDRIL_DIST then
				return
			end
			local base = { w0 = 0.5, w1 = 0.14, speed = speed, wobble = 1.8, lashT = t0 + lash }
			if c.whiff then
				for i, p in ipairs(d.whiffEnds or {}) do
					local src = sourceOf(char, SOURCES[(i - 1) % #SOURCES + 1])
					local o = table.clone(base)
					o.segs, o.endPoint, o.crackle = 10, p, ctx.camDist(where) <= CRACKLE_DIST
					local rec = { t = newTendril(f, src, o), endPoint = p }
					table.insert(c.tendrils, rec)
					local s0 = src() or where
					at(lash + (p - s0).Magnitude / speed, function()
						if c.kicked or rec.gone then
							return
						end
						FX.ring(f, p, ctx.camFacing(p), 0.5, 5, PAL.Spark, 0.15)
						FX.sparks(f, p, { color = PAL.Spark, color2 = accent, count = 8, speed = { 10, 25 }, size = 0.35 })
						crackAt(p, 0.45)
						phase(rec, "retract")
						rec.retracted = true
						task.delay(0.26, function()
							phase(rec, "destroy")
						end)
					end, 0.5)
				end
			else
				for i, tg in ipairs(targets) do
					local m = tg.model or tg[1]
					if typeof(m) == "Instance" and m.Parent then
						local o = table.clone(base)
						o.target = m
						o.segs = (#targets > 5) and 6 or (#targets > 3) and 8 or 10
						o.crackle = i <= ((#targets > 3) and 3 or 5) and ctx.camDist(where) <= CRACKLE_DIST
						local rec = { t = newTendril(f, sourceOf(char, SOURCES[(i - 1) % #SOURCES + 1]), o), model = m }
						table.insert(c.tendrils, rec)
						c.byModel[m] = rec
						if c.pending[m] then
							rec.latched = true
							phase(rec, "latched", m)
						end
						-- a body the server never latched (out of reach, or Gojo took it): the whip pulls back
						local latchT = tonumber(tg.latch) or (lash + (m:GetPivot().Position - where).Magnitude / speed)
						at(latchT + 0.3, function()
							if not rec.latched and not rec.gone and not c.kicked then
								phase(rec, "retract")
								rec.retracted = true
							end
						end, 1)
					end
				end
			end
		end, math.max(kick - lash - 0.05, 0.05))

		-- t 0.30: the caster's view leans in for the reel
		if isLocal then
			at(LEAN_AT, function()
				ctx.lean({ pitch = 0, drop = 0, fov = -4, attack = 0.18, hold = 0.12, release = 0.15 })
			end)
		end

		-- t 0.50: the YANK. Fists ripped back; light and air sucked into the gather point
		at(REEL_AT, function()
			local where = hrpPos()
			soundOn(hrpPart(), SND.Whoosh, 0.8, 0.85, where)
			soundOn(hrpPart(), SND.Sizzle, 0.3, 1, where)
			soundOn(hrpPart(), SND.Crackle, 0.35, 1.4, where)
			FX.streaks(f, G, { inward = 10, color = accent, color2 = PAL.Emerald, count = 24, life = 0.3, size = 0.35 })
			if c.heavy then
				FX.ring(f, G, ctx.camFacing(G), 10, 1, accent, 0.35, { ease = "in", alpha = 0.4 })
				if ctx.camDist(G) <= HEAVY_DIST then
					windGust(-aim * 30, 0.1, 0.25, 0.4)
				end
			end
			if isLocal then
				ctx.shake(0.25, 0.22, 22, 0)
			end
		end)

		-- t 0.665: the LOAD. Wound right; the lightning drains into the kicking leg (crackles until the kick)
		at(LOAD_AT - 0.04, function()
			c.legUntil, c.legEvery, c.legNext = os.clock() + (kick - LOAD_AT + 0.06), 0.045, 0
			local where = hrpPos()
			soundOn(hrpPart(), SND.Swell, 0.4, 1.7, where)
			soundOn(hrpPart(), SND.Whoosh, 0.7, 1.25, where)
			local footP = partOf(char, "RightFoot")
			if footP and c.heavy then
				FX.streaks(f, footP.Position, { inward = 4, count = 12, color = accent, color2 = PAL.Core, life = 0.2, size = 0.26 })
				FX.glow(f, footP.Position, glowFor(footP.Position, 3), accent, 0.3, { alpha = 0.2 })
			end
			local gp, onGround = groundAt(where)
			if onGround and c.heavy then
				FX.ring(f, gp + UP * 0.2, UP, 6, 1, accent, 0.2, { ease = "in", alpha = 0.3 })
			end
		end)

		-- t 0.72: the HOP. Off the left toes; green trails on both feet draw the spin
		at(LIFT_AT, function()
			local where = hrpPos()
			soundOn(hrpPart(), SND.Whoosh, 0.9, 1.0, where)
			soundOn(hrpPart(), SND.Hit2, 0.3, 0.6, where)
			local gp, onGround = groundAt(where)
			if onGround then
				FX.ring(f, gp + UP * 0.2, UP, 2, 12, PAL.Air, 0.35, { alpha = 0.2 })
				if c.heavy then
					S.dustRing(f, gp, 1.5, 6, 18, { s0 = 1.5, s1 = 5, life = 1 })
					FX.streaks(f, gp, { dir = UP, spread = 25, count = 12, speed = { 30, 70 }, color = PAL.Air, color2 = accent, size = 0.35, life = 0.25 })
				end
			end
			if c.near <= WING_DIST then
				local rf, lf = partOf(char, "RightFoot"), partOf(char, "LeftFoot")
				if rf then
					table.insert(c.footTrails, FX.trail(rf, cs(PAL.Core, accent), 0.6, 0.25, { tail = 0 }))
				end
				if lf then
					table.insert(c.footTrails, FX.trail(lf, cs(accent, PAL.Emerald), 0.45, 0.2, { tail = 0 }))
				end
			end
			if isLocal then
				ctx.shake(0.18, 0.2, 24, 2)
				try(FX.speedLines, 0.3, { color = PAL.Cowl, alpha = 0.28, inner = 0.55, count = 36 })
			end
		end)

		-- t 0.79 / 0.86 / 0.93: the mid-air spin - afterimages strobe behind him, whirl rings, rising whooshes
		for i, T in ipairs(SPIN_AT) do
			at(T, function()
				local where = hrpPos()
				soundOn(hrpPart(), SND.Whoosh, 0.45, 1.4 + i * 0.2, where)
				if char and c.near <= WING_DIST then
					ghostOf(c, char, (i == 3) and PAL.Core or accent, 0.6, 0.26, HERO_CAP)
					FX.ring(f, where + UP * 0.6, UP, 2, 6 + i, accent, 0.2, { alpha = 0.4 })
				end
			end)
		end

		-- t 0.98: ST. LOUIS SMASH (WhipKick lands the bodies' layer and the tally)
		at(kick, function()
			kickFrame(c)
		end, 0.3)

		-- the LAND (clip 1.46, + the hit-stop): the superhero crouch
		at(LAND_AT + shift, function()
			dropFootTrails(c)
			local where = hrpPos()
			local gp, onGround = groundAt(where)
			soundOn(hrpPart(), SND.HitHeavy, 0.45, 1.4, where)
			soundOn(hrpPart(), SND.Hit2, 0.3, 0.8, where)
			if onGround then
				FX.ring(f, gp + UP * 0.2, UP, 1.5, 12, PAL.Air, 0.35, { alpha = 0.25 })
				if c.heavy then
					S.dustRing(f, gp, 2, 8, 22, { s0 = 2, s1 = 6, life = 1.6 })
					FX.rubble(f, gp, { count = 5, radius = 1.5, up = { 10, 20 }, out = { 6, 14 }, max = 0.9 })
					if room(c, 18) then
						FX.arcs(f, gp + UP * 0.4, 2.5, { count = 3, colors = { accent, PAL.Core }, width = 0.06 })
					end
				end
			end
			if isLocal then
				ctx.shake(0.3, 0.25, 30, 0)
			end
		end, 0.3)

		-- the record (and anything left on it) goes once the aftermath is over
		task.delay(math.max(kick + TAIL - e, 0.1), function()
			finish(c)
		end)
	end

	-- WhipLatch { id, userId, model, pos }: the whip-crack and spark at the latch
	H.WhipLatch = function(d)
		local c = casts[keyOf(d)]
		if c and c.cancelled then
			return
		end
		local m = d.model
		local t = typeof(m) == "Instance" and torsoOf(m) or nil
		local pos = d.pos or (t and t.Position)
		if not pos then
			return
		end
		local f = c and c.f or ctx.castFolder("WhipLatch")
		local accent = (c and c.mode) and PAL.Crimson or PAL.Cowl
		try(FX.glow, f, pos, glowFor(pos, 5), accent, 0.2)
		try(FX.sparks, f, pos, { color = PAL.Spark, color2 = accent, count = 14, speed = { 15, 35 } })
		try(FX.ring, f, pos, ctx.camFacing(pos), 0.6, 6, PAL.Spark, 0.16) -- the crack
		if ctx.camDist(pos) <= ARC_DIST and room(c, 12) then
			try(FX.arcs, f, pos, 1.6, { count = 2, colors = { accent, PAL.Core }, width = 0.07 })
		end
		if ctx.camDist(pos) <= SMOKE_DIST then
			-- a black puff where the whip wraps the body
			local host = FX.anchor(f, pos, 1.8)
			local em = host and FX.emitter(host, smokeProps(0, { s0 = 0.6, s1 = 2.2, spread = 180, v0 = 2, v1 = 6, rise = 2 }))
			if em then
				em:Emit(8)
			end
		end
		soundOn(t, "WhipCrack", 0.65, nil, pos)
		soundOn(t, SND.Hit2, 0.45, 1.25, pos)
		soundOn(t, SND.Whoosh, 0.35, 2.2, pos) -- the zip
		if c and typeof(m) == "Instance" and not c.kicked then
			c.latched[m] = true
			local rec = c.byModel[m]
			if rec then
				if not rec.latched and not rec.gone then
					rec.latched = true
					phase(rec, "latched", m)
				end
			else
				c.pending[m] = true -- the tendril is not up yet: it latches as it is made
			end
			if t and c.heavy and not c.drag[m] then
				c.drag[m] = try(dragRig, c, m, t)
			end
		end
	end

	-- WhipKick { id, userId, center, aim, models, dirs, mode }: the bodies scatter on comet trails
	H.WhipKick = function(d)
		local c = casts[keyOf(d)]
		local models = d.models or {}
		if c and c.cancelled then
			return
		end
		if not c then
			-- the cast itself was missed (joined mid-cast): a minimal record so the kick still reads
			local char, caster = ctx.charOf(d.userId)
			local aim = ctx.flat(d.aim or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
			c = newRecord(d, char, caster ~= nil and caster == ctx.player, ctx.now() - KICK, aim, d.center or Vector3.zero, #models == 0)
			casts[c.key] = c
			kickFrame(c)
			task.delay(TAIL, function()
				finish(c)
			end)
		elseif not c.kicked then
			kickFrame(c)
		end
		local accent = c.mode and PAL.Crimson or PAL.Cowl
		local list = {}
		for _, m in ipairs(models) do
			local t = typeof(m) == "Instance" and m.Parent and torsoOf(m)
			if t then
				table.insert(list, { m = m, t = t, dd = ctx.camDist(t.Position) })
			end
		end
		table.sort(list, function(a, b)
			return a.dd < b.dd
		end)
		for i, b in ipairs(list) do
			local m, t = b.m, b.t
			try(S.bodyTrail, m, cs(accent, PAL.CowlDeep), 2, 1.4)
			try(FX.sparks, c.f, t.Position, { color = PAL.Spark, color2 = accent, count = 12 })
			if b.dd <= HEAVY_DIST then
				try(S.bodyTrail, m, cs(PAL.Core, PAL.Spark), 0.7, 0.9)
				if i <= 5 then
					-- a comet tail of green sparks streaming off the body as it flies
					local a = Instance.new("Attachment")
					a.Name = "OFAWhipComet"
					a.Parent = t
					local e = FX.emitter(a, {
						Texture = TEX.star, Color = cs(PAL.Spark, accent), Lifetime = NumberRange.new(0.25, 0.45),
						Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Size = nsk({ { 0, 0.5 }, { 1, 0 } }),
						Drag = 2, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Brightness = 2, Rate = 45,
					})
					task.delay(0.85, function()
						if e.Parent then
							e.Rate = 0
						end
					end)
					Debris:AddItem(a, 1.5)
				end
				for _, dt in ipairs({ 0.1, 0.25, 0.45 }) do
					task.delay(dt, function()
						if m.Parent and not c.cancelled and room(c, 8) then
							try(S.bodyArc, c.f, m, (math.random() < 0.7) and accent or PAL.Core, 0.07)
						end
					end)
				end
				if i <= 2 and b.dd <= GHOST_DIST then
					-- the afterimage it leaves where the kick caught it (after the hit-stop, as it launches)
					task.delay(HITSTOP + 0.02, function()
						if m.Parent then
							ghostOf(c, m, accent, 0.5, 0.3, (i == 1) and HERO_CAP or nil) -- the nearest one always reads
						end
					end)
				end
			end
		end
		if c.isLocal and #models > 0 and type(ctx.tally) == "function" then
			try(ctx.tally, d.id, #models) -- the HUD hit tally "xn" (§10.2)
		end
	end

	-- WhipCancel { id, userId }: the caster died or the kit changed before the kick
	H.WhipCancel = function(d)
		local key = keyOf(d)
		for k, c in pairs(casts) do
			if (d.id ~= nil and k == key) or (d.id == nil and c.userId == d.userId) then
				cancel(c)
			end
		end
	end

	-- every Heartbeat: the wings ride his torso, latched bodies crackle / kick up dust / leave afterimages as they are
	-- hauled in, and the arm (gather) and leg (load -> aftermath) lightning ticks
	H.__update = function(clock)
		for _, c in pairs(casts) do
			if not c.cancelled and not c.finished then
				local char = c.char
				local ut = partOf(char, "UpperTorso")
				-- wings
				if #c.wings > 0 and ut and not c.kicked then
					local e = ctx.now() - c.t0
					local k
					if e < LASH then
						k = 0.7 + 0.3 * math.clamp(e / LASH, 0, 1)
					elseif e < REEL_AT then
						k = 1.3
					elseif e < LIFT_AT then
						k = 1.08
					else
						k = 0.95
					end
					local cf = ut.CFrame
					for _, w in ipairs(c.wings) do
						if w.t and not w.gone and not w.t.dead then
							local ph = w.ph
							local sway = Vector3.new(math.sin(clock * 3.1 + ph) * 0.5, math.sin(clock * 2.3 + ph) * 0.6, math.cos(clock * 2.7 + ph) * 0.4)
							w.t.endPoint = cf * (w.off * k + sway)
						end
					end
				end
				-- the gather's crackle up both arms (fine detail: near casters only)
				if c.armUntil and char and c.near <= ARC_DIST then
					if clock >= c.armUntil then
						c.armUntil = nil
					elseif clock >= (c.armNext or 0) then
						c.armNext = clock + 0.05
						c.armSide = not c.armSide
						if room(c, 8) then
							try(S.limbArc, c.f, char, c.armSide and ARM_R or ARM_L, (math.random() < 0.7) and (c.mode and PAL.Crimson or PAL.Cowl) or PAL.Core, 0.05)
						end
					end
				end
				-- the kicking leg's lightning (charging, then lingering)
				if c.legUntil and char then
					if clock >= c.legUntil then
						c.legUntil = nil
					elseif clock >= (c.legNext or 0) then
						c.legNext = clock + (c.legEvery or 0.05)
						if c.near <= ARC_DIST and room(c, 8) then
							try(S.limbArc, c.f, char, LEG_R, (math.random() < 0.7) and (c.mode and PAL.Crimson or PAL.Cowl) or PAL.Core, 0.06)
						end
					end
				end
				-- the DRAG
				if not c.kicked then
					for m in pairs(c.latched) do
						local t = m.Parent and torsoOf(m)
						if not t then
							c.latched[m] = nil
							if c.drag[m] then
								dropDrag(c.drag[m])
								c.drag[m] = nil
							end
						else
							local pos = t.Position
							if clock >= (c.arcNext[m] or 0) then
								-- staggered, so bodies latched in the same frame do not all arc at once
								c.arcNext[m] = clock + ARC_EVERY * (0.75 + 0.5 * math.random())
								if ctx.camDist(pos) <= ARC_DIST and room(c, 8) then
									try(S.bodyArc, c.f, m, (math.random() < 0.75) and (c.mode and PAL.Crimson or PAL.Cowl) or PAL.Core, 0.06)
								end
							end
							local r = c.drag[m]
							if r then
								local dt = math.max(clock - r.lastClock, 1e-3)
								local spd = (pos - r.last).Magnitude / dt
								r.last, r.lastClock = pos, clock
								if clock >= (r.nextGround or 0) then
									r.nextGround = clock + 0.05
									local hit = FX.groundHit(pos, 10)
									r.low = hit ~= nil
									if hit and r.host.Parent then
										r.host.CFrame = CFrame.new(hit.Position + UP * 0.3)
									end
								end
								if r.em.Parent then
									r.em.Rate = (r.low and spd > 12) and 40 or 0
								end
								if r.ghosts and spd > 25 and clock >= r.nextGhost then
									r.nextGhost = clock + GHOST_EVERY
									r.flip = not r.flip
									ghostOf(c, m, r.flip and PAL.Cowl or PAL.Emerald, 0.55, 0.2)
								end
							end
						end
					end
				end
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
