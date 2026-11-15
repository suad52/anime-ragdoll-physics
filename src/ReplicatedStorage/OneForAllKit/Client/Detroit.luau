--!nocheck
-- OneForAllKit.Client.Detroit: E - DETROIT SMASH, the flair cut (design A §6 + the flair pass). Every client plays
-- every cast from the server's broadcasts, on the server timeline (e = now - t0):
--   DetroitCast   { id, userId, t0, origin, aim, charge, range, halfAngle, frontSpeed, stations = { {pos, t, r, sd} }, mode }
--   DetroitHit    { id, userId, pos, model, dir, k, core }
--   DetroitCancel { id, userId }
-- Beats (server time; C = Detroit.Charge = 0.66, the timings live in Config pass "Flair_Detroit"):
--   0.00  TELL - a breath in: swell + drone + crackle, the caster's slow punch-in starts, the aura lights.
--   0.20  PLANT - he stamps into the split stance: a ring and a dust doughnut off the stamp, glowing cracks race out
--         from his feet, pebbles tear loose and float, fine dust starts lifting round his feet, a charge orb lights
--         on the knuckles.
--   0.20-0.60 the SURGE - lightning races down the arm (chest -> shoulder -> elbow -> fist, every 0.09 s) on top of
--         the limb arcs, arcs crackle round the cocked fist while the orb swells, rings collapse into it in three
--         planes with inward light streaks, and the AIR INTAKE: grass blades and grit are torn off the ground round
--         him and sucked INTO the fist while the grass and the trees lean in towards him; a second crack wave at 0.42;
--         the tremble (clip) and the shake grow.
--   C-0.08 COCK - the last pull back: a whoosh, and an afterimage of the coil left behind as he fires.
--   C     RELEASE (the money frame) - every client holds the pose FreezeTime (0.14 s); the caster gets the impact
--         frame, an FOV punch, speed lines, a heavy shake and a short lunge. Muzzle glows, a fan of cracks under the
--         fist, shock rings in three planes then staggered ones marching down the aim (+0.05/+0.10/+0.16), the
--         pressure front, wind streaks, lightning down the cone, a forward echo of the punch, the floating rocks
--         blasted away, the grass flattened and the trees whipped back.
--   C..   the FRONT tears the ground: a gouged scar with a glowing seam and a kicked chunk + dust every 5 studs.
--   st.t  each server station: the rolling dust wall and the cloud it leaves to settle, flying rubble, a lit scar
--         ring, cracks, a shock ring standing in the trench, lightning skipping down it, rising thuds.
--   C+0.12 .. C+TailTime the TAIL: steam off the fist, embers, lingering arcs on the arm that thin out, smoke wisps
--         and embers rising off the trench, a backdraft that pulls the grass back, two slow residual rings.
-- Full Cowl 100% (payload `mode`) is DELAWARE DETROIT SMASH and wilder: crimson through every layer, a wind swirl
-- round him in the charge, more intake and rocks, a double pressure front, extra crimson bolts, lightning at every
-- station, a thunder echo, the ground shattering, crimson embers.
-- Distance tiers: the local caster and anyone within 160 studs see everything; 160-250 drop the fine layers
-- (intake, arm lightning, ghosts, tears, trench smoke, lingering arcs); beyond 250 only the fist glow, one ring and
-- the sounds. A part governor keeps this cast's folder plus its afterimages under BUDGET parts, and a body hit right
-- in front of the camera only blooms at full strength for the first two (no white-out from a point-blank crowd).
-- The last wisps clear ~6.5 s after the cast (the folder goes at 7.5 s); the three Heartbeat loops (charge, tear,
-- dust pump) end on their own. Local-caster-only layers (root, lunge, callout, camera) check caster == ctx.player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

return function(ctx)
	local H = {}

	local FX, S, CFG = ctx.FX, ctx.S, ctx.CFG
	local PAL, SND = ctx.PAL, ctx.SND
	local UP, FLAT, WHITE = ctx.UP, ctx.FLAT, ctx.WHITE
	local TAU = ctx.TAU or math.pi * 2
	local DC = CFG.Detroit
	local rng = Random.new()
	local cs, nsk, TEX = FX.cs, FX.nsk, FX.TEX
	local BLACK = Color3.new(0, 0, 0)
	local BLOCK, BALL = Enum.PartType.Block, Enum.PartType.Ball
	local NEON, PLASTIC = Enum.Material.Neon, Enum.Material.SmoothPlastic
	local QUAD, SINE, LINEAR = Enum.EasingStyle.Quad, Enum.EasingStyle.Sine, Enum.EasingStyle.Linear
	local IN, OUT = Enum.EasingDirection.In, Enum.EasingDirection.Out

	local ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }
	local NEAR = 160 -- the full detail layer for other players' casts
	local FULL_DIST = 250 -- §6.5 / §11: beyond it only the fist glow, one ring and the sounds
	local WIND_DIST = 220 -- §3.7: clients this near the cast run their own gust
	local OTHERS_SHAKE = 200 -- others' shake + flash fall off to nothing at 200 studs
	local BUDGET = 310 -- parts in one cast's folder + its live afterimages; optional layers skip past it (peak ~350 in all)
	local NEAR_CAM = 30 -- a body hit closer than this to the camera counts towards the point-blank bloom limit
	local STRIKE_KEY = 0.66 -- Clips.Detroit's STRIKE key, when the clip does not say (clip.strikeAt)
	local TEAR_STEP = 5 -- studs between the front's ground tears

	local casts = {} -- "userId#id" -> live cast state (cast ids are per-player counters)
	local hitCount = {} -- "userId#id" -> DetroitHit count seen on this client
	local nearCount = {} -- "userId#id" -> how many of those bodies were within NEAR_CAM of this client's camera
	local function keyOf(d)
		return tostring(d.userId) .. "#" .. tostring(d.id)
	end

	---------------------------------------------------------------------------------------------------
	-- helpers

	local warned = {}
	local function warnOnce(key, msg)
		if not warned[key] then
			warned[key] = true
			warn("[OneForAll.Detroit] " .. msg)
		end
	end

	-- a Shared builder, guarded: one missing or failing builder never takes the rest of a beat down with it
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

	-- §3C glow-size safety rule (no white-outs): through Shared's glowFor, or the same formula if it is absent
	local function glowFor(pos, size)
		if S and type(S.glowFor) == "function" then
			local ok, v = pcall(S.glowFor, pos, size)
			if ok and type(v) == "number" then
				return v
			end
		end
		return size * math.clamp(ctx.camDist(pos) / 30, 0.45, 1)
	end

	-- Config.Sounds' bracketed fallbacks for the requested extras that may still be ""
	local FALLBACK = {
		SubBoom = { "Boom", 0.6, 1 },
		Choir = { "Swell", 1.5, 0.4 },
		WhipCrack = { "Hit2", 1.8, 1 },
		WindRoar = { "Whoosh", 0.6, 1 },
		AirPop = { "Cannon", 1.35, 1 },
	}
	local function resolve(key, vol, pitch)
		local id = SND[key]
		if (id == nil or id == "") and FALLBACK[key] then
			local fb = FALLBACK[key]
			return SND[fb[1]], (vol or 1) * fb[3], fb[2]
		end
		return id, vol, pitch
	end
	local function sndAt(key, pos, vol, pitch)
		local id, v, p = resolve(key, vol, pitch)
		if id and id ~= "" and typeof(pos) == "Vector3" then
			pcall(ctx.soundAt, id, pos, v, p)
		end
	end
	local function sndOn(key, parent, vol, pitch)
		local id, v, p = resolve(key, vol, pitch)
		if id and id ~= "" and parent then
			pcall(ctx.sound, id, parent, v, p)
		end
	end

	local function tw(inst, t, props, style, dir, delay)
		pcall(function()
			TweenService:Create(inst, TweenInfo.new(t, style or QUAD, dir or OUT, 0, false, delay or 0), props):Play()
		end)
	end

	-- the lunge (and the tears) are wall-clamped like the server's clampPath
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Exclude
	local function wallDist(from, dir, want)
		local list = {}
		for _, n in ipairs({ "LocalFX", "NPCs", "FX" }) do
			local x = workspace:FindFirstChild(n)
			if x then
				table.insert(list, x)
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(list, p.Character)
			end
		end
		wallParams.FilterDescendantsInstances = list
		local hit = workspace:Raycast(from, dir * (want + 1.5), wallParams)
		if hit then
			return math.max(hit.Distance - 1.5, 0)
		end
		return want
	end

	local function groundAt(p, depth)
		local hit = FX.groundHit(p, depth or 10)
		return hit and hit.Position, hit
	end
	local function lookOf(hit) -- the ground's colour + material (Shared.groundColor: turf tears up as dirt)
		if hit and S and type(S.groundColor) == "function" then
			local ok, c, m = pcall(S.groundColor, hit)
			if ok and typeof(c) == "Color3" then
				return c, m
			end
		end
		return Color3.fromRGB(110, 104, 98), Enum.Material.Slate
	end
	local function grassOf(hit) -- the live grass colour when the ground is turf, else nil
		if hit and hit.Instance and hit.Instance:IsA("Terrain")
			and (hit.Material == Enum.Material.Grass or hit.Material == Enum.Material.LeafyGrass) then
			local ok, c = pcall(function()
				return workspace.Terrain:GetMaterialColor(hit.Material)
			end)
			if ok and typeof(c) == "Color3" then
				return c
			end
		end
		return nil
	end

	local function countParts(f)
		local n = 0
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	-- the part governor: an optional layer that would push this cast past BUDGET parts is skipped
	local function room(st, n)
		return st.f ~= nil and st.f.Parent ~= nil and countParts(st.f) + (st.extra or 0) + (n or 1) <= BUDGET
	end
	-- an afterimage (Shared.ghost parents it outside the cast folder): its parts count against the governor while it
	-- lives; `force` (the punch's forward echo, a money-frame layer) skips the governor's check but is still counted
	local function ghostOf(st, char, color, alpha, life, offset, force)
		if not force and not room(st, 18) then
			return nil
		end
		local g = S_("ghost", char, color, alpha, life, offset)
		if typeof(g) == "Instance" then
			local n = #g:GetChildren()
			st.extra = (st.extra or 0) + n
			task.delay((life or 0.3) + 0.1, function()
				st.extra = math.max((st.extra or 0) - n, 0)
			end)
		end
		return g
	end

	-- two moving dust hosts per cast, one smoke emitter each (fine dust / big clouds): every puff moves its host to
	-- where it is wanted, sets the speed and life, and emits - so the whole cast costs two emitters, not thirty.
	-- An emitter spawns a burst from where its host is (with the Speed / Lifetime it has) when the frame renders, so
	-- two puffs moved and fired in one frame would both come out at the second spot: puff() only queues, and the
	-- cast's dust pump fires at most ONE queued puff per emitter per frame
	local function makeDust(f, color)
		local function host(name)
			local h = FX.part(name, BLOCK, PLASTIC, WHITE, nil)
			h.Transparency = 1
			h.Size = Vector3.one
			h.Parent = f
			return h
		end
		local host, cloudHost = host("DetroitDust"), host("DetroitCloud")
		local base = {
			Texture = TEX.smoke, Color = cs(color, color:Lerp(BLACK, 0.28)), LightInfluence = 1, LightEmission = 0,
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(16, 16), Drag = 1.5,
			Acceleration = Vector3.new(0, 2.5, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		}
		local small, big = table.clone(base), table.clone(base)
		small.Size = nsk({ { 0, 1.1 }, { 0.4, 2.8 }, { 1, 4 } })
		small.Transparency = nsk({ { 0, 0.5 }, { 0.5, 0.68 }, { 1, 1 } })
		big.Size = nsk({ { 0, 4 }, { 0.35, 11 }, { 1, 16 } })
		big.Transparency = nsk({ { 0, 0.32 }, { 0.5, 0.56 }, { 1, 1 } })
		return { host = host, small = FX.emitter(host, small), big = FX.emitter(cloudHost, big), q = {} }
	end
	local function puff(D, e, cf, size, speed, life, n)
		if D and e and e.Parent then
			table.insert(D.q, { e = e, cf = cf, size = size, speed = speed, life = life, n = n })
		end
	end
	local function startDustPump(st)
		local D = st.dust
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if st.dead or not D.host.Parent then
				conn:Disconnect()
				return
			end
			local fired = {}
			local i = 1
			while i <= #D.q do
				local p = D.q[i]
				if fired[p.e] then
					i += 1
				else
					fired[p.e] = true
					table.remove(D.q, i)
					local h = p.e.Parent
					if h and h.Parent then
						h.CFrame, h.Size = p.cf, p.size
						p.e.Speed = NumberRange.new(p.speed[1], p.speed[2])
						p.e.Lifetime = NumberRange.new(p.life[1], p.life[2])
						p.e:Emit(p.n)
					end
				end
			end
			if #D.q == 0 and ctx.now() - st.t0 > st.C + 1.5 then
				conn:Disconnect() -- the last station is long past: nothing more will be queued
			end
		end)
		table.insert(st.conns, conn)
	end

	-- glowing fissures racing out over the ground from `center`, then cooling dark and fading: n cracks of o.segs
	-- jagged Neon slabs, `len` studs long, grown over o.grow s; o.dir + o.fan (radians) draw a fan instead of a ring
	local function cracks(st, center, n, len, o)
		o = o or {}
		local segs = o.segs or 3
		if not room(st, n * segs) then
			return
		end
		local g, hit = groundAt(center + UP, 8)
		if not g then
			return
		end
		local f = st.f
		local dark = lookOf(hit):Lerp(BLACK, 0.6)
		local grow, life = o.grow or 0.22, o.life or 2.4
		local width = o.width or 0.24
		local color = o.color or PAL.Cowl
		local fdir = o.dir and ctx.flat(o.dir)
		local base = fdir and math.atan2(fdir.Z, fdir.X) or rng:NextNumber(0, TAU)
		local fan = o.fan or math.rad(70)
		for i = 1, n do
			local ang
			if fdir then
				ang = base + ((i - 0.5) / n - 0.5) * fan + rng:NextNumber(-0.12, 0.12)
			else
				ang = base + (i / n) * TAU + rng:NextNumber(-0.3, 0.3)
			end
			local p = g + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (o.start or 0.6)
			local total = len * rng:NextNumber(0.7, 1.15)
			for s = 1, segs do
				local a2 = ang + rng:NextNumber(-0.5, 0.5)
				local q = p + Vector3.new(math.cos(a2), 0, math.sin(a2)) * (total / segs)
				q = groundAt(q + UP * 1.5, 5) or Vector3.new(q.X, p.Y, q.Z)
				local seg = (q - p).Magnitude
				if seg > 0.15 then
					local w = width * (1 - (s - 1) / segs * 0.6)
					local c = FX.part("Crack", BLOCK, NEON, color, nil)
					local at0 = CFrame.lookAt(p + UP * 0.05, q + UP * 0.05)
					c.Size = Vector3.new(w, 0.07, 0.05)
					c.CFrame = at0 * CFrame.new(0, 0, -0.025)
					c.Parent = f
					local delay = (o.delay or 0) + (s - 1) * grow / segs
					tw(c, grow / segs, { Size = Vector3.new(w, 0.07, seg), CFrame = at0 * CFrame.new(0, 0, -seg / 2) }, LINEAR, OUT, delay)
					tw(c, o.cool or 0.7, { Color = dark }, QUAD, IN, delay + grow / segs + (o.hot or 0.15))
					tw(c, 0.6, { Transparency = 1 }, QUAD, IN, life - 0.6)
					Debris:AddItem(c, life + 0.05)
				end
				p = q
			end
		end
	end

	-- lightning racing down the arm: chest -> shoulder -> elbow -> fist -> past the knuckles, one hop every 0.018 s
	local function armRace(st, color)
		local c = st.char
		local ut = c and c:FindFirstChild("UpperTorso")
		local ua, la, hd = c and c:FindFirstChild("RightUpperArm"), c and c:FindFirstChild("RightLowerArm"), c and c:FindFirstChild("RightHand")
		if not (ut and ua and la and hd) or not room(st, 24) then
			return
		end
		local tip = hd.Position + (hd.Position - la.Position).Unit * 1.1
		local pts = { ut.Position + ut.CFrame.RightVector * 0.5 + UP * 0.4, ua.Position + ua.CFrame.UpVector * 0.4, la.Position, hd.Position, tip }
		for i = 1, #pts - 1 do
			task.delay((i - 1) * 0.018, function()
				if not st.dead then
					FX.bolt(st.f, pts[i] + FX.randUnit() * 0.12, pts[i + 1] + FX.randUnit() * 0.12, {
						color = color, core = PAL.Core, width = 0.07, jag = 0.32, segments = 3, life = 0.08, restrike = 1,
					})
				end
			end)
		end
	end

	-- the air intake: grass blades and grit torn off the ground round him (mostly from the way he faces) that
	-- curl in and are sucked into the fist; the charge loop flies them
	local function spawnIntake(st, n)
		if not st.char or not room(st, n) then
			return
		end
		local _, hit = groundAt(st.feet + UP, 8)
		local grit, gritMat = lookOf(hit)
		local blade = grassOf(hit)
		local t = os.clock()
		for _ = 1, n do
			local ang = rng:NextNumber(-2.3, 2.3)
			local dir = st.aim * math.cos(ang) + st.right * math.sin(ang)
			local p = st.feet + dir * rng:NextNumber(4.5, 11)
			local gp = groundAt(p + UP * 3, 8) or p
			local isBlade = blade ~= nil and rng:NextNumber() < 0.6
			local size = isBlade and Vector3.new(0.12, rng:NextNumber(0.6, 1), 0.05) or Vector3.one * rng:NextNumber(0.22, 0.45)
			local part = FX.part(isBlade and "Blade" or "Grit", BLOCK, PLASTIC, WHITE, nil)
			if isBlade then
				part.Color = blade:Lerp(WHITE, rng:NextNumber(0, 0.15))
			else
				part.Color = grit:Lerp(BLACK, rng:NextNumber(0, 0.3))
				pcall(function()
					part.Material = gritMat
				end)
			end
			part.Size = size
			part.CFrame = CFrame.new(gp + UP * size.Y * 0.5)
			part.Parent = st.f
			Debris:AddItem(part, 1.6)
			local side = (rng:NextNumber() < 0.5) and -1 or 1
			table.insert(st.intake, {
				part = part, size = size, from = gp + UP * 0.3,
				ctrl = gp:Lerp(st.feet, 0.45) + UP * rng:NextNumber(2.5, 5) + st.right * side * rng:NextNumber(1, 3),
				t0 = t + rng:NextNumber(0, 0.12), dur = rng:NextNumber(0.3, 0.45),
				spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			})
		end
	end

	-- the charge loop (cast start -> C): the orb rides the knuckles and swells, the intake flies into the fist
	local function startCharge(st)
		local hand0 = st.char and st.char:FindFirstChild("RightHand")
		if not hand0 then
			return
		end
		local orb = FX.part("FistCharge", BALL, NEON, st.accent, nil)
		orb.Size = Vector3.one * 0.9
		orb.Transparency = 0.5
		orb.CFrame = CFrame.new(hand0.Position)
		orb.Parent = st.f
		local core = FX.part("FistCore", BALL, NEON, PAL.Core, nil)
		core.Size = Vector3.one * 0.5
		core.Transparency = 0.25
		core.CFrame = orb.CFrame
		core.Parent = st.f
		local light = Instance.new("PointLight")
		light.Color = st.accent
		light.Brightness = 1
		light.Range = 6
		light.Shadows = false
		light.Parent = orb
		st.orb = orb
		table.insert(st.cleanup, function()
			orb:Destroy()
			core:Destroy()
			for _, it in ipairs(st.intake) do
				it.part:Destroy()
			end
			table.clear(st.intake)
		end)
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local e = ctx.now() - st.t0
			if st.dead or e > st.C + 0.05 or not st.char.Parent then
				conn:Disconnect()
				orb:Destroy()
				core:Destroy()
				for _, it in ipairs(st.intake) do
					it.part:Destroy()
				end
				table.clear(st.intake)
				return
			end
			local hand = st.char:FindFirstChild("RightHand")
			local hp = hand and hand.Position
			if not hp then
				return
			end
			local u = math.clamp((e - 0.2) / math.max(st.C - 0.2, 0.05), 0, 1)
			local clock = os.clock()
			local d = 0.9 + 1.5 * u + math.sin(clock * 38) * 0.12 * (0.4 + u)
			local parts = { orb, core }
			local cfs = { CFrame.new(hp), CFrame.new(hp) }
			orb.Size = Vector3.one * d
			orb.Transparency = 0.5 - 0.22 * u
			core.Size = Vector3.one * d * 0.5
			light.Brightness = 1 + 5 * u
			light.Range = 6 + 9 * u
			for i = #st.intake, 1, -1 do
				local it = st.intake[i]
				local k = (clock - it.t0) / it.dur
				if k >= 1 or not it.part.Parent then
					it.part:Destroy()
					table.remove(st.intake, i)
				elseif k > 0 then
					local w = k ^ 1.7
					local a = it.from:Lerp(it.ctrl, w)
					local b = it.ctrl:Lerp(hp, w)
					it.part.Size = it.size * (1 - 0.75 * w)
					table.insert(parts, it.part)
					table.insert(cfs, CFrame.new(a:Lerp(b, w)) * CFrame.Angles(it.spin.X * clock, it.spin.Y * clock, it.spin.Z * clock))
				end
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end)
		table.insert(st.conns, conn)
	end

	-- the front tearing the ground (C -> the end of its run): every TEAR_STEP studs a gouged scar with a glowing
	-- seam down the centre line, and a chunk + dust kicked up somewhere across the front
	local function startTear(st)
		local reach = math.min(st.range, st.wall)
		if reach < 4 then
			return
		end
		local tEnd = st.C + reach / st.speed + 0.05
		local scarCol = st.groundCol:Lerp(BLACK, 0.45)
		local seamCol = st.accent
		local tanH = math.tan(math.rad(st.half))
		local nextD = 4
		local conn
		conn = RunService.Heartbeat:Connect(function()
			local e = ctx.now() - st.t0
			if st.dead or e > tEnd then
				conn:Disconnect()
				return
			end
			local d = math.min((e - st.C) * st.speed, reach)
			local steps = 0
			while nextD <= d and steps < 3 do
				steps += 1
				local sd = nextD
				nextD += TEAR_STEP
				local p = st.origin + st.aim * sd
				local g = groundAt(p, 12)
				if g and p.Y - g.Y < 9 and room(st, 3) then
					local scar = FX.part("Scar", BLOCK, PLASTIC, scarCol, nil)
					pcall(function()
						scar.Material = st.groundMat
					end)
					scar.Size = Vector3.new(1.6 + sd * 0.035, 0.2, TEAR_STEP + 0.8)
					scar.CFrame = CFrame.lookAt(g, g + st.aim) * CFrame.new(rng:NextNumber(-0.4, 0.4), 0.02, -TEAR_STEP * 0.5)
						* CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), math.rad(rng:NextNumber(-4, 4)))
					scar.Parent = st.f
					tw(scar, 0.8, { Transparency = 1 }, QUAD, IN, 3.1)
					Debris:AddItem(scar, 4)
					local seam = FX.part("Seam", BLOCK, NEON, seamCol, nil)
					seam.Size = Vector3.new(0.22, 0.06, TEAR_STEP + 0.6)
					seam.CFrame = scar.CFrame * CFrame.new(0, 0.12, 0)
					seam.Parent = st.f
					tw(seam, 0.6, { Color = scarCol:Lerp(BLACK, 0.4) }, QUAD, IN, 0.2)
					tw(seam, 0.5, { Transparency = 1 }, QUAD, IN, 1.5)
					Debris:AddItem(seam, 2.1)
					local kp = p + st.right * (rng:NextNumber(-0.8, 0.8) * (2 + sd * tanH))
					FX.rubble(st.f, kp, { count = 1, radius = 0.5, up = { 18, 34 }, out = { 6, 16 }, dir = st.aim, min = 0.5, max = 1.1, life = 1.8 })
					local kg = groundAt(kp, 12)
					if kg then
						puff(st.dust, st.dust and st.dust.small, CFrame.fromMatrix(kg + UP * 0.4, st.right, (st.aim + UP * 0.9).Unit),
							Vector3.new(1.5, 0.4, 1.5), { 8, 16 }, { 0.7, 1.1 }, 2)
					end
				end
			end
		end)
		table.insert(st.conns, conn)
	end

	local function endCast(st, hard)
		if st.ended then
			return
		end
		st.ended = true
		st.dead = true -- every pending beat of this cast is skipped from here on
		for _, c in ipairs(st.conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		for _, fn in ipairs(st.cleanup) do
			pcall(fn)
		end
		if st.rocks then
			pcall(function()
				st.rocks:drop() -- the floating pebbles just fall
			end)
			st.rocks = nil
		end
		if hard then
			if st.track then
				pcall(function()
					st.track:stop(0.15)
				end)
			end
			if st.isLocal then
				pcall(ctx.unroot)
				pcall(ctx.stopMove)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- DetroitCast: the charge, the release, the trench and the tail

	H.DetroitCast = function(d)
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster == ctx.player
		local e = ctx.now() - (d.t0 or ctx.now())
		local origin = d.origin
		local aim = ctx.flat(d.aim or Vector3.new(0, 0, -1))
		local C = d.charge or DC.Charge
		local range = d.range or DC.Range
		local half = d.halfAngle or DC.HalfAngle -- degrees
		local speed = d.frontSpeed or DC.FrontSpeed
		local mode = d.mode == true
		local FREEZE = DC.FreezeTime or 0.14
		local TAIL = DC.TailTime or 3.2
		if typeof(origin) ~= "Vector3" or e > C + TAIL then
			return -- long past: nothing left to show (the craters replicate on their own)
		end
		if char and not char.Parent then
			char = nil
		end

		local dist = ctx.camDist(origin)
		local tier = (isLocal or dist <= NEAR) and 2 or (dist <= FULL_DIST and 1 or 0)
		local f = ctx.castFolder("Detroit", 7.5)
		local right = aim:Cross(UP).Unit
		local accent = mode and PAL.Crimson or PAL.Cowl

		local feet, fhit = groundAt(origin, 8)
		feet = feet or (origin - UP * 3)
		local gcol, gmat = lookOf(fhit)

		local st = {
			id = d.id, t0 = d.t0 or ctx.now(), isLocal = isLocal, char = char, f = f, C = C, origin = origin, aim = aim,
			right = right, range = range, half = half, speed = speed, mode = mode, accent = accent, feet = feet,
			groundCol = gcol, groundMat = gmat, conns = {}, cleanup = {}, intake = {},
			wall = wallDist(origin + UP * 0.5, aim, range),
		}
		local key = keyOf(d)
		if casts[key] then
			endCast(casts[key], false)
		end
		casts[key] = st
		task.delay(math.max(C + TAIL + 0.6 - e, 0.5), function()
			endCast(st, false)
			if casts[key] == st then
				casts[key] = nil
			end
		end)

		-- the clip, lined up so its STRIKE key lands on the server's punch whatever Charge is
		local clip = ctx.Clips.Detroit
		local shift = ((clip and clip.strikeAt) or STRIKE_KEY) - C
		if char and clip then
			if e + shift >= 0 then
				st.track = ctx.playClip(char, clip, e + shift)
			else
				task.delay(-(e + shift), function()
					if not st.dead and char.Parent then
						st.track = ctx.playClip(char, clip, 0)
					end
				end)
			end
		end

		-- a timeline beat at cast time T; skipped once it is more than `late` seconds past
		local function at(T, late, fn)
			if T < e - late then
				return
			end
			task.delay(math.max(T - e, 0), function()
				if st.dead then
					return
				end
				local ok, err = pcall(fn)
				if not ok then
					warnOnce("beat" .. T, "beat " .. T .. ": " .. tostring(err))
				end
			end)
		end
		local function limb(name)
			return char and char.Parent and char:FindFirstChild(name)
		end
		-- the caster's live root while it is still near the cast origin (rooted), else the broadcast origin
		local function body()
			local hrp = limb("HumanoidRootPart")
			if hrp and (hrp.Position - origin).Magnitude < 8 then
				return hrp.Position
			end
			return origin
		end
		local function handPos(fallback)
			local hand = limb("RightHand")
			if hand and (hand.Position - fallback).Magnitude < 6 then
				return hand.Position
			end
			return fallback
		end
		local function arcColor(share)
			if mode and rng:NextNumber() < 0.45 then
				return PAL.Crimson
			end
			return (rng:NextNumber() < (share or 0.7)) and PAL.Cowl or PAL.Core
		end

		-- t 0.00 - TELL -------------------------------------------------------------------------------
		if isLocal then
			ctx.root(math.max((DC.RootTime or 1.55) - math.max(e, 0), 0.05), aim)
		end
		at(0, 0.2, function()
			local hrp, hand = limb("HumanoidRootPart"), limb("RightHand")
			sndOn("Swell", hrp, 0.85, 1.0)
			sndOn("Drone", hrp, 0.3, 1.6)
			sndOn("Crackle", hand, 0.5, 1.15)
			if isLocal then
				ctx.lean({ fov = -9, attack = math.max(C - 0.08, 0.1), hold = 0.06, release = 0.08 }) -- the slow punch-in
				ctx.shake(0.05, 0.25, 30, 0)
			end
		end)
		if tier >= 1 then
			at(0.06, 0.2, function()
				local hrp = limb("HumanoidRootPart")
				if hrp then
					st.aura = FX.aura(hrp, PAL.Core, accent, 45)
					table.insert(st.cleanup, function()
						if st.aura then
							st.aura:Destroy()
							st.aura = nil
						end
					end)
				end
			end)
			at(0.4, 0.2, function() -- the aura surges with the charge
				if st.aura then
					for _, em in ipairs(st.aura:GetChildren()) do
						if em:IsA("ParticleEmitter") then
							em.Rate *= 1.9
						end
					end
				end
			end)
			at(C + 0.12, 1, function()
				if st.aura then
					st.aura:Destroy()
					st.aura = nil
				end
			end)
		end
		if dist <= WIND_DIST then
			at(0.15, 0.3, function() -- the grass leans in toward him as he draws the air in
				S_("windGust", -aim * 30, 0.3, math.max(C - 0.5, 0.05), 0.08, origin)
				if mode then
					S_("swirl", 16, 0.9, math.max(C - 0.15, 0.2), origin) -- the 100% charge drags a vortex round him
				end
			end)
		end

		-- t 0.20 - PLANT ------------------------------------------------------------------------------
		at(0.2, 0.15, function()
			sndAt("HitHeavy", feet, 0.55, 0.6) -- the stamp
			if isLocal then
				ctx.shake(0.4, 0.22, 26, 0)
			end
			if tier >= 1 then
				FX.ring(f, feet + UP * 0.25, UP, 3, 14, PAL.CowlDeep, 0.38, { alpha = 0.3 })
				S_("dustRing", f, feet, 2.5, tier >= 2 and 5 or 3, 24, { s0 = 1.5, s1 = 5, life = { 0.8, 1.3 }, color = gcol })
				cracks(st, body(), 6, 6.5, { grow = 0.25, life = 2.8, color = accent })
				st.rocks = FX.liftRocks(f, body(), 9, mode and 14 or 10)
				st.dust = makeDust(f, gcol)
				startDustPump(st)
				st.dust.host.CFrame = CFrame.new(feet + UP * 0.3)
				st.dust.host.Size = Vector3.new(6, 0.3, 6)
				st.dust.small.Speed = NumberRange.new(1, 3)
				st.dust.small.Lifetime = NumberRange.new(0.9, 1.4)
				st.dust.small.Rate = tier >= 2 and 22 or 12 -- fine dust lifting round his feet while he charges
				table.insert(st.cleanup, function()
					if st.dust and st.dust.small.Parent then
						st.dust.small.Rate = 0
					end
				end)
				if char then
					startCharge(st)
				end
			end
		end)

		-- t 0.20 - 0.60 - the SURGE -------------------------------------------------------------------
		if tier >= 2 and char then
			local n = math.floor((C - 0.2) / 0.05)
			for i = 0, n - 1 do -- the limb arcs, thickening as it builds
				local u = i / math.max(n - 1, 1)
				at(0.2 + i * 0.05, 0.05, function()
					S_("limbArc", f, char, ARM, arcColor(0.7), 0.05 + 0.04 * u)
				end)
			end
			local t = 0.24
			while t < C - 0.03 do -- lightning racing down the arm
				at(t, 0.05, function()
					armRace(st, (mode and rng:NextNumber() < 0.5) and PAL.Crimson or PAL.Cowl)
				end)
				t += 0.09
			end
			t = 0.3
			while t < C - 0.02 do -- arcs crackling round the cocked fist, widening as it builds
				local u = (t - 0.3) / math.max(C - 0.3, 0.1)
				at(t, 0.05, function()
					local hp = handPos(body())
					FX.arcs(f, hp, 1.2 + 0.6 * u, {
						count = 2, colors = mode and { PAL.Crimson, PAL.Core, PAL.Cowl } or { PAL.Cowl, PAL.Core }, width = 0.05, life = 0.1, segments = 3,
					})
				end)
				t += 0.07
			end
			for i, tt in ipairs({ 0.24, 0.36, 0.48 }) do -- the intake
				at(tt, 0.08, function()
					spawnIntake(st, (mode and 12 or 8) + (i == 2 and 2 or 0))
				end)
			end
		end
		if tier >= 1 then
			local planes = { "aim", "right", "cam", "aim" }
			for i, tt in ipairs({ 0.2, 0.32, 0.44, 0.54 }) do -- rings collapse into the fist in three planes
				at(tt, 0.1, function()
					local hp = handPos(body() + aim * 0.5 - UP * 0.5)
					local pl = planes[i]
					local nrm = (pl == "aim" and aim) or (pl == "right" and right) or ctx.camFacing(hp)
					FX.ring(f, hp, nrm, 12 - 2 * i, 0.6, (i % 2 == 0) and PAL.Core or accent, 0.32, { ease = "in", alpha = 0.3 })
					FX.streaks(f, hp, { inward = 7, color = WHITE, color2 = accent, count = 18 + 4 * i, life = 0.36, size = 0.3 })
				end)
			end
			at(0.3, 0.2, function()
				sndOn("Sizzle", limb("RightHand"), 0.4, 1.3) -- the arm crackling
				if isLocal then
					ctx.shake(0.1, 0.3, 34, 0)
				end
				if dist <= WIND_DIST then -- the trees ahead twitch in towards him as the air is drawn in
					S_("windBend", origin + aim * (range * 0.75), -aim, range * 0.8, 4, 0.9, half)
				end
			end)
			at(0.42, 0.15, function() -- the second crack wave, longer
				cracks(st, body(), 5, 10, { grow = 0.3, life = 2.6, color = accent, start = 1.2 })
			end)
			at(0.45, 0.2, function()
				local hand = limb("RightHand")
				sndOn("Zap", hand, 0.35, 0.8)
				sndOn("Crackle", hand, 0.6, 1.3)
				if isLocal then
					ctx.shake(0.16, 0.25, 38, 0)
				end
			end)
		end

		-- C-0.08 - COCK: the last pull back ----------------------------------------------------------
		at(C - 0.08, 0.1, function()
			sndOn("Whoosh", limb("HumanoidRootPart"), 0.5, 1.6)
			if isLocal then
				ctx.shake(0.2, 0.1, 40, 0)
			end
			if tier >= 2 then
				local hp = handPos(body())
				FX.glow(f, hp, glowFor(hp, 4), PAL.Core, 0.12, { brightness = 3 }) -- the gathering flare
				if char then
					ghostOf(st, char, accent, 0.55, 0.4) -- the coil left behind as he fires
				end
			end
		end)
		-- (2026-11-07) no cast text for non-ult moves; only the ultimate keeps its title (the DETROIT SMASH /
		-- DELAWARE DETROIT SMASH callout that slammed in with the punch is gone)

		-- C - RELEASE ---------------------------------------------------------------------------------
		at(C, 0.12, function()
			if st.track then
				ctx.freeze(st.track, FREEZE) -- every client sees the punch hang
			end
			if st.dust and st.dust.small.Parent then
				st.dust.small.Rate = 0
			end
			local p = body()
			local fist = handPos(p + aim * 3 + UP * 0.3)
			local fg = groundAt(fist, 8) or (feet + aim * 3)

			-- caster: a short wall-clamped lunge behind the fist
			if isLocal and char and char == ctx.player.Character then
				local _, _, hrp = ctx.myChar()
				if hrp then
					local dur = DC.LungeTime or 0.1
					local dd = wallDist(hrp.Position, aim, DC.LungeDist or 3)
					ctx.move({
						char = char, t0 = ctx.now(), dur = dur, from = hrp.Position, to = hrp.Position + aim * dd, face = aim,
						vel = aim * (dd / dur), ease = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out }, exitVel = aim * 6,
					})
				end
			end

			-- seen from any distance: the fist glow and one ring
			FX.glow(f, fist, glowFor(fist, 7), PAL.Core, 0.18, { brightness = 4 })
			FX.ring(f, fist, aim, 0.5, 30, accent, 0.5, { alpha = 0.45, brightness = 1.2 })
			sndAt("Boom", fist, 1, 0.95)
			sndAt("Thunder", fist, 0.85, 1.05)
			sndAt("WindRoar", fist, 1, 0.72)
			sndAt("Cannon", fist, 0.6, 0.75)
			sndAt("SubBoom", fist, 0.75, 1)
			sndAt("Hit", fist, 0.8, 0.7)

			if tier >= 1 then
				FX.glow(f, fist, glowFor(fist, 16), PAL.Cowl, 0.45, { alpha = 0.3, brightness = 1.4 })
				if mode then
					FX.glow(f, fist + aim * 2, glowFor(fist, 12), PAL.Crimson, 0.4, { alpha = 0.35, brightness = 1.3 })
				end
				-- shock rings in three planes, then staggered ones marching down the aim
				FX.ring(f, fist + aim * 3, aim, 1, 14, WHITE, 0.28)
				FX.ring(f, fist, right, 0.5, 9, PAL.Core, 0.24, { alpha = 0.25 })
				FX.ring(f, feet + UP * 0.3, UP, 2, 24, PAL.Air, 0.5, { alpha = 0.25 }) -- the ground blast round him
				for _, sr in ipairs({ { 0.05, 6, 22, PAL.Air, 0.15 }, { 0.1, 10, 28, PAL.Air, 0.3 }, { 0.16, 15, 34, accent, 0.45 } }) do
					task.delay(sr[1], function()
						if not st.dead then
							FX.ring(f, fist + aim * sr[2], aim, sr[2] * 0.2, sr[3], sr[4], 0.42, { alpha = sr[5], brightness = 1.2 })
							if mode then
								FX.ring(f, fist + aim * (sr[2] + 2), aim, sr[2] * 0.15, sr[3] * 0.8, PAL.Crimson, 0.36, { alpha = 0.4 })
							end
						end
					end)
				end
				-- the wave: a shimmering front racing down the cone (a crimson-rimmed double front in mode)
				S_("pressureFront", f, fist, aim, range, half, speed, { rim = mode and PAL.Crimson or PAL.Air, rimEvery = 14 })
				if mode then
					task.delay(0.04, function()
						if not st.dead then
							-- the second disc stays faint: seen from behind, two stacked discs filling the view must stay under ~0.2
							S_("pressureFront", f, fist, aim, range, half, speed, { color = PAL.Cowl, rim = PAL.Cowl, alpha0 = 0.12, rimEvery = 14 })
						end
					end)
				end
				-- wind
				FX.streaks(f, fist, {
					dir = aim, spread = half, color = WHITE, color2 = PAL.Air, count = mode and 110 or 80, speed = { 160, 280 },
					size = 0.7, life = 0.45, stretch = 3, brightness = 1.6,
				})
				FX.streaks(f, fist, {
					dir = aim, spread = 14, color = PAL.Core, color2 = accent, count = mode and 44 or 30, speed = { 140, 240 }, size = 0.45,
					life = 0.35,
				})
				-- lightning down the line (mode: crimson bolts, two more, and longer)
				local nb = (tier >= 2) and (mode and 7 or 5) or 3
				for i = 1, nb do
					if room(st, 10) then
						local reach = (mode and i > 5) and rng:NextNumber(32, 45) or rng:NextNumber(18, 30)
						local to = fist + aim * reach + right * rng:NextNumber(-5, 5) + UP * rng:NextNumber(-1.5, 2)
						FX.bolt(f, fist, to, {
							color = (mode and i % 2 == 0) and PAL.Crimson or PAL.Cowl, core = PAL.Core, width = 0.22, jag = 0.15,
							life = 0.24, restrike = 2, light = (i == 1), segments = 5,
						})
					end
				end
				FX.light(f, fist, accent, 12, 40, 0.45)
				-- the earth splits in a fan under the fist
				cracks(st, fg, 6, 9, { dir = aim, fan = math.rad(half * 2 + 20), grow = 0.16, life = 2.8, color = accent, start = 0.8 })
				if dist <= WIND_DIST then
					S_("windBend", origin, aim, range + 60, mode and 14 or 11, 1.8, half) -- trees whip back, spring forward
				end
				if tier >= 2 then
					startTear(st)
					if char then
						task.delay(0.02, function() -- a forward echo of the punch: the pressure leaving his fist
							if not st.dead and char.Parent then
								ghostOf(st, char, mode and PAL.Crimson or PAL.Air, 0.72, 0.24, aim * 2.4, true)
							end
						end)
					end
				end
				if mode then
					task.delay(0.1, function()
						sndAt("Thunder", fist, 0.6, 0.8) -- the echo
						sndAt("Shatter", fg, 0.4, 0.7) -- the ground giving way
					end)
				end
			end
			if st.rocks then
				st.rocks:drop(aim * 45 + UP * 12) -- the floating pebbles are blasted forward
				st.rocks = nil
			end
			if dist <= WIND_DIST then
				S_("windGust", aim * 95, 0.05, 0.35, 1.2, origin) -- every blade of grass in front flattens away from him
			end

			-- camera
			if isLocal then
				FX.impact({ tint = PAL.Spark, tint2 = PAL.Core, lineColor = PAL.Spark, lineTime = 0.5, flashAlpha = 0.16, flashLife = 0.22 })
				ctx.shake(1.15, 0.65, 24, 11) -- FOV +11: the view opens up after the punch-in
				ctx.lean({ pitch = 1.2, fov = 3, attack = 0.04, hold = FREEZE, release = 0.5 }) -- the recoil, held through the freeze
				FX.speedLines(0.55, { color = mode and PAL.Crimson or PAL.Spark, alpha = 0.55, inner = 0.38 })
			else
				local k = math.clamp(1 - dist / OTHERS_SHAKE, 0, 1)
				if k > 0 then
					ctx.shake(0.9 * k, 0.5, 24)
					FX.flash(PAL.Air, 0.12 * k, 0.2)
				end
			end
		end)
		if isLocal then
			at(C + FREEZE, 0.2, function() -- the freeze lets go and the wave rolls on
				ctx.shake(0.5, 0.4, 20, 0)
			end)
		end

		-- the trench rolls out, one station at a time on the server's clock -------------------------------
		if tier >= 1 and type(d.stations) == "table" then
			local tanH = math.tan(math.rad(half))
			local prev = nil
			local nst = #d.stations
			for i, s in ipairs(d.stations) do
				if type(s) == "table" and typeof(s.pos) == "Vector3" and type(s.t) == "number" then
					local from = prev
					prev = s.pos
					at(s.t, 0.05, function()
						local pos, r = s.pos, s.r or 4
						local sd = s.sd or ((pos - origin) * FLAT).Magnitude
						if sd < 1 then
							sd = math.max((s.t - C) * speed, 1)
						end
						local width = math.max(2 * sd * tanH, 6)
						-- the rolling dust wall, and the cloud it leaves behind to settle
						if st.dust then
							puff(st.dust, st.dust.big, CFrame.fromMatrix(pos + UP * 0.8, right, (aim + UP * 0.15).Unit),
								Vector3.new(width, 0.6, 2), { 55, 80 }, { 1.2, 1.8 }, math.clamp(math.floor(sd / 10) + 4, 4, mode and 10 or 8))
							puff(st.dust, st.dust.big, CFrame.fromMatrix(pos + UP * 0.5, right, UP),
								Vector3.new(width * 0.8, 0.5, 3), { 1.5, 4 }, { 2.4, 3.2 }, tier >= 2 and 3 or 2)
						end
						if room(st, 8) then
							FX.rubble(f, pos, { count = mode and 7 or 6, radius = r, up = { 30, 60 }, out = { 15, 40 }, dir = aim })
						end
						FX.ring(f, pos + UP * 0.2, UP, r * 0.5, r * 2.2, accent, 0.35, { alpha = 0.3 }) -- the lit scar
						if i % 2 == 0 then -- a shock ring standing in the trench
							FX.ring(f, pos + UP * 3, aim, r, r * 3, PAL.Air, 0.35, { alpha = 0.35 })
						end
						if i % 2 == 1 then
							FX.sparks(f, pos, { dir = aim + UP, spread = 40, color = PAL.Spark, color2 = accent, count = 8 })
						end
						if tier >= 2 then
							cracks(st, pos, 3, r * 1.6, { grow = 0.14, life = 2.0, color = accent, segs = 2, start = r * 0.4 })
							if (mode or i % 2 == 0) and room(st, 12) then -- lightning skipping down the trench
								local a = (from or (groundAt(origin + aim * 3, 8) or (feet + aim * 3))) + UP * 0.4
								FX.bolt(f, a, pos + UP * 0.4, {
									color = mode and PAL.Crimson or PAL.Cowl, core = PAL.Core, width = 0.12, jag = 0.22, life = 0.18,
									restrike = 1, segments = 5,
								})
							end
						end
						sndAt("HitHeavy", pos, 0.55, 0.75 + 0.05 * (i - 1)) -- rising thuds rolling away
						if isLocal then
							ctx.shake(0.18 * (1 - (i - 1) / math.max(nst, 1)), 0.15, 22, 0)
						end
						if i == nst then
							task.delay(0.25, function() -- the run ends in a slow ring (at() here would count from the cast's arrival, not now)
								if not st.dead then
									FX.ring(f, pos + UP * 0.3, UP, 3, 14, PAL.Air, 0.9, { alpha = 0.6 })
								end
							end)
						end
					end)
				end
			end
		end

		-- C+0.12 .. C+TAIL - the TAIL --------------------------------------------------------------------
		if tier >= 1 then
			at(C + 0.12, 0.5, function() -- steam off the fist, embers drifting up off the arm
				local hand = limb("RightHand")
				if not hand then
					return
				end
				local sh = S_("steam", hand, mode and 30 or 20)
				if sh then
					st.steam = sh
					table.insert(st.cleanup, function()
						pcall(function()
							sh:stop()
						end)
					end)
				end
				local a = Instance.new("Attachment")
				a.Name = "DetroitEmbers"
				a.Parent = hand
				local em = FX.emitter(a, {
					Texture = TEX.star, Color = cs(mode and PAL.Ember or PAL.Spark, accent), Size = nsk({ { 0, 0.28 }, { 1, 0 } }),
					Transparency = nsk({ { 0, 0 }, { 0.8, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.1),
					Speed = NumberRange.new(1.5, 4), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top,
					Acceleration = Vector3.new(0, 4, 0), Drag = 1, Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-200, 200), Brightness = 2, Rate = mode and 22 or 12,
				})
				table.insert(st.cleanup, function()
					a:Destroy()
				end)
				task.delay(math.max(TAIL - 1, 0.5), function()
					if em.Parent then
						em.Rate = 0
					end
					Debris:AddItem(a, 1.2)
				end)
			end)
			at(C + 1.2, 0.5, function()
				if st.steam then
					st.steam.Rate = mode and 14 or 8 -- thinning out
				end
			end)
			at(C + TAIL, 0.5, function()
				if st.steam then
					st.steam:stop()
					st.steam = nil
				end
			end)
			at(C + 0.5, 0.3, function() -- residual rings round his feet
				FX.ring(f, feet + UP * 0.25, UP, 4, 16, accent, 1, { alpha = 0.6, brightness = 1 })
				sndOn("Sizzle", limb("RightHand"), 0.45, 0.8) -- the steam hiss
			end)
			at(C + 1.1, 0.3, function()
				FX.ring(f, feet + UP * 0.25, UP, 6, 22, PAL.Air, 1.2, { alpha = 0.75, brightness = 1 })
			end)
			if dist <= WIND_DIST then
				at(C + 0.45, 0.3, function() -- the backdraft pulls the grass back the other way
					S_("windGust", -aim * 22, 0.3, 0.2, 0.9, origin)
				end)
			end
		end
		if tier >= 2 then
			if char then -- lingering arcs on the arm, thinning out
				local t, gap = C + FREEZE + 0.06, 0.07
				while t < C + TAIL - 0.4 do
					local tt = t
					at(tt, 0.05, function()
						S_("limbArc", f, char, ARM, arcColor(0.6), 0.05)
						if rng:NextNumber() < 0.35 then
							local hp = handPos(body())
							FX.arcs(f, hp, 0.9, { count = 1, colors = mode and { PAL.Crimson, PAL.Cowl } or { PAL.Cowl, PAL.Core }, width = 0.04, life = 0.08, segments = 3 })
						end
					end)
					t += gap
					gap *= 1.12
				end
				at(C + 0.4, 0.3, function()
					sndOn("Crackle", limb("RightHand"), 0.35, 0.9)
				end)
			end
			at(C + 0.35, 0.3, function() -- smoke wisps and embers rising off the trench
				local reach = math.min(range, st.wall) * 0.92
				if reach < 8 then
					return
				end
				local mid = origin + aim * (reach * 0.5 + 2)
				local g = groundAt(mid, 14) or (mid - UP * 3)
				local host = FX.part("TrenchSmoke", BLOCK, PLASTIC, WHITE, nil)
				host.Transparency = 1
				host.Size = Vector3.new(4, 0.5, reach)
				host.CFrame = CFrame.lookAt(g + UP * 0.5, g + UP * 0.5 + aim)
				host.Parent = f
				local smoke = FX.emitter(host, {
					Texture = TEX.smoke, Color = cs(Color3.fromRGB(150, 146, 140), Color3.fromRGB(92, 90, 86)), LightInfluence = 1,
					LightEmission = 0, Size = nsk({ { 0, 1.5 }, { 0.5, 4.5 }, { 1, 7 } }),
					Transparency = nsk({ { 0, 1 }, { 0.15, 0.6 }, { 0.6, 0.75 }, { 1, 1 } }), Lifetime = NumberRange.new(1.6, 2.4),
					Speed = NumberRange.new(1.5, 3.5), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top,
					Acceleration = Vector3.new(0, 2, 0), Drag = 0.6, Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-25, 25), Rate = 14,
				})
				local embers = FX.emitter(host, {
					Texture = TEX.star, Color = cs(mode and PAL.Ember or accent, PAL.Spark), Size = nsk({ { 0, 0.35 }, { 1, 0 } }),
					Transparency = nsk({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.4),
					Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top,
					Acceleration = Vector3.new(0, 3, 0), Drag = 0.8, Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-200, 200), Brightness = 2, Rate = mode and 16 or 9,
				})
				task.delay(math.max(TAIL - 1.3, 0.6), function() -- stop feeding it; the last wisps clear ~2.4 s later
					smoke.Rate, embers.Rate = 0, 0
				end)
				Debris:AddItem(host, TAIL + 1.3)
			end)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- DetroitHit: the impact layer on each body as the front reaches it (every client)

	H.DetroitHit = function(d)
		local pos = d.pos
		if typeof(pos) ~= "Vector3" then
			return
		end
		local key = keyOf(d)
		local n = (hitCount[key] or 0) + 1
		if n == 1 then
			task.delay(6, function()
				hitCount[key] = nil
				nearCount[key] = nil
			end)
		end
		hitCount[key] = n
		if d.userId == ctx.player.UserId and type(ctx.tally) == "function" then
			pcall(ctx.tally, d.id) -- the caster's "xN" hit tally (§10.2)
		end
		if ctx.camDist(pos) > FULL_DIST then
			return
		end
		local st = casts[key]
		local mode = st and st.mode or false
		local accent = mode and PAL.Crimson or PAL.Cowl
		local f = (st and st.f and st.f.Parent) and st.f or ctx.castFolder("DetroitHit", 4) -- in the cast: the governor sees it
		local dir = (typeof(d.dir) == "Vector3" and d.dir.Magnitude > 1e-3) and d.dir.Unit or UP
		-- no white-outs: a crowd hit point-blank stacks additive blooms right in front of the lens (on top of the
		-- release's own), so only the first two bodies near this camera bloom at full strength, one of them coloured
		local nearN = 0
		if ctx.camDist(pos) < NEAR_CAM then
			nearN = (nearCount[key] or 0) + 1
			nearCount[key] = nearN
		end
		local loud = nearN <= 2
		FX.glow(f, pos, glowFor(pos, loud and 9 or 5), PAL.Core, 0.18, { brightness = loud and 3 or 1.6 })
		FX.ring(f, pos, dir, 1, 11, PAL.Air, 0.28, { alpha = 0.15 })
		if n <= 8 then
			FX.streaks(f, pos, {
				dir = dir, spread = 30, color = WHITE, color2 = accent, count = 20, speed = { 60, 140 }, size = 0.45, life = 0.3,
			})
		end
		FX.sparks(f, pos, { color = PAL.Spark, color2 = accent, count = 14 })
		if n <= 5 and nearN <= 1 and (not st or room(st, 2)) then -- the first bodies get a coloured bloom and a second, staggered ring
			FX.glow(f, pos, glowFor(pos, 14), accent, 0.32, { alpha = 0.4, brightness = 1.3 })
			task.delay(0.05, function()
				FX.ring(f, pos + dir * 2, dir, 0.5, 8, WHITE, 0.22, { alpha = 0.3 })
			end)
		end
		local m = d.model
		if typeof(m) == "Instance" and m.Parent and m:FindFirstChild("UpperTorso") then
			S_("bodyTrail", m, ColorSequence.new(PAL.Air, accent), 1.8, 0.9) -- the comet streak of the flight
			if n <= 6 and (not st or room(st, 8)) then -- lightning crawling over the body as it goes
				for _, dt in ipairs({ 0.06 }) do
					task.delay(dt, function()
						if m.Parent then
							S_("bodyArc", f, m, accent, 0.07)
						end
					end)
				end
			end
		end
		if d.core then
			if loud then
				FX.ring(f, pos, ctx.camFacing(pos), 1, 10, WHITE, 0.2)
			end
			FX.ring(f, pos, dir:Cross(UP).Magnitude > 1e-3 and dir:Cross(UP).Unit or Vector3.xAxis, 1, 8, accent, 0.26, { alpha = 0.3 })
			if not st or room(st, 24) then
				FX.arcs(f, pos, 3, { outward = true, count = 4, colors = mode and { PAL.Crimson, PAL.Core } or { PAL.Cowl, PAL.Core } })
			end
			if loud and n <= 3 then
				FX.light(f, pos, accent, 6, 18, 0.25)
			end
		end
		if n <= 4 then
			sndAt("HitHeavy", pos, 0.8, 0.9 + rng:NextNumber() * 0.2)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- DetroitCancel (the caster died or changed kit before the punch) and reset

	H.DetroitCancel = function(d)
		local key = keyOf(d)
		local st = casts[key]
		if st then
			endCast(st, true)
			casts[key] = nil
		end
	end

	H.__reset = function()
		for id, st in pairs(casts) do
			if st.isLocal then
				endCast(st, true)
				casts[id] = nil
			end
		end
	end

	return H
end
