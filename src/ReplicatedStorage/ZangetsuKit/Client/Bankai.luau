--!nocheck
-- ZangetsuKit.Client.Bankai (owner bankai): G, BANKAI -> TENSA ZANGETSU (DESIGN.md §9.4 + §9.M), played on every client.
-- Broadcast kinds: BankaiCast, BankaiErupt, BankaiCancel (Moves.Bankai) and BankaiEnd (Core). Casts are keyed
-- userId#id. Beat times come from the payload (Config.Bankai, FLAIR PASS): e = ctx.now() - t0.
--   0.00 BAN...   callout; the cleaver sweeps out, the arm locks out at 0.22 (a glint runs the blade, the dust flattens);
--                 a blue-white aura ramps 30 -> 90, the blade glow 0.3 -> 1; THE TORNADO starts: ice-blue wind streaks
--                 spiralling up a funnel round him; rocks lift (0.10); pebbles start spiralling up into it (0.30);
--                 the ground cracks (0.22 / 0.50); dust is sucked in (0.15 / 0.45); streaks pour into him every 0.15 s;
--                 flat rings collapse onto him (0.15 / 0.40); reiatsu arcs crawl round him every 0.08 s from 0.30.
--                 Caster: shot A (0.12, low front-right on the sword hand, pushing in)
--   0.62 ...KAI!  callout; shot B (a close profile on his face, the eyes flash crimson); the colours flip: a black aura
--                 with crimson licks, the blade glow black, the tornado turns BLACK-RED (dark ribbons join, two of them
--                 drag black smoke) and climbs 4 -> 14 studs, spinning faster; six black flame bursts round him, a
--                 crimson shock ring + bloom + light; crimson lightning forks strike the ground round him (0.62 / 0.78 /
--                 0.90); collapsing crimson rings (0.72 / 0.98); crimson cracks + dust ripped inward (0.90); Thunder +
--                 Boom + Crackle; 0.98 shot C (pulled back low and wide), the core of light swells in his chest; 1.06
--                 the funnel is sucked in tight (the brace)
--   1.18 ERUPTION the black-crimson pillar (Shared) erupts 120 studs into the sky; the tornado is sucked up it (its
--                 ribbons become the runners spiralling up the skin); crimson LIGHTNING crawls up the column; a DOME
--                 shockwave (two ForceField shells + a wavefront ring) races 46 studs across the ground; ground rings
--                 (60 / 45 / 40, staggered), a camera-facing ring, a dust + dark smoke doughnut, rubble, the lifted rocks
--                 and pebbles hurled outward, crimson cracks, a fountain of streaks; the sky reddens (a local colour
--                 grade, <= 250 studs); 1.40 the CROWN: rings and a dark cloud ring rolling out off the top of the column;
--                 every body hit becomes a crimson comet; the caster's camera shakes on the hand-back (1.32)
--   1.18-2.15     the pillar rages: ribbons race up its skin, lightning crawls, ash and black flakes fall off it, a low
--                 hum; the dust cloud hangs round its foot (1.30 / 1.70)
--   1.42 FORM     (the server swaps the sword + coat) a crimson burst at the blade, the cleaver's steel shards fly off,
--                 the black coat WHIPS round him (a black + crimson ribbon twice round him); the glow moves to Tensa
--   2.06          caster: the reveal shot (low front three-quarter, pushing in, until 2.76)
--   2.15 REVEAL   the pillar dissolves into black feathers, ash and embers; the dust cloud is blown flat outward (the
--                 reveal); the coat tails FLARE back and settle on a spring; a final crimson ring; a crimson bloom and
--                 arcs; crimson eyes; 2.20 TENSA ZANGETSU + a glint racing up the black blade, 2.27 a star glints off
--                 its tip; a scorched crater (dark disc with a cooling crimson rim) smoulders
--   2.58 / 2.68   CHIBURI: the blade lifts, then flicks clean - a red-black blade trail and a spray of crimson drops
--   2.2-5.0       aftermath: embers and smoke wisps rise off the crater; the cast's aura hands over to the mode
--   2.75 MODE     (attribute BankaiUntil) - drawn by __update on EVERY character in the mode (§9.M): black aura with
--                 crimson licks (14 standing -> 44 running), a crimson rim Highlight (<= 140 studs), black-crimson
--                 afterimages at a run (<= 4 alive, <= 120 studs), burning scorch footprints with a crimson rim, a
--                 black-wisped blade with a crimson edge that BLEEDS crimson drops, crimson eyes dragging long trails
--                 (<= 60 studs), the coat tails trailing crimson + black flame and streaming back at a run (<= 100-120),
--                 crimson arcs crawling over the body (<= 80); the last 3 s it all sputters; it ignites when first seen
--   BankaiEnd     "expired": the aura implodes, the coat burns away hem-first with embers and ash, black flames burst
--                 off the blade and crimson cracks open along it, black wisps rise off him; 0.45 the black blade
--                 SHATTERS into black shards and the cleaver reforms in a blue-white flash (clip BankaiExit). Other
--                 reasons: gone at once.
-- No white-outs / black-outs (DESIGN §11): every bloom through a distance scaler that assumes the caster's camera is
-- back at ~14 studs once the shot hands back, at most 2 full blooms near the lens, camera-facing rings scaled
-- clamp(d/30, 0.6, 1) and thinned inside 40 studs, dark smoke / dust / flame puffs skipped within 8-9 studs of the lens
-- (and the dust doughnut leaves a gap on the camera's bearing; the caster's hanging cloud also leaves his front open for
-- the reveal shot), tornado ribbons fade inside 4.5 studs of the lens and its smoke stops inside 9, lightning never
-- strikes toward the lens, the dome is drawn >= 0.8 transparent for a camera within 40 studs, the pillar always asked to
-- fade for a near camera, the black aura thinned while the close-up shot is on. Remote casters: <= 160 studs full,
-- <= 250 reduced, beyond that the pillar, its crown, the dome, one ring and the sounds.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

return function(ctx)
	local H = {}
	local CFG = ctx.CFG
	local PAL = ctx.PAL or CFG.Palette
	local FX = ctx.FX
	local S = ctx.S or {}
	local B = CFG.Bankai or {}
	local MODE = CFG.Mode or {}
	local MFX = type(MODE.FX) == "table" and MODE.FX or {}
	local GATE = type(B.Gate) == "table" and B.Gate or {}
	local DOME = type(B.Dome) == "table" and B.Dome or {}
	local UP = ctx.UP or Vector3.yAxis
	local FLAT = ctx.FLAT or Vector3.new(1, 0, 1)
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local BLACK = ctx.BLACK or Color3.new(0, 0, 0)
	local TAU = ctx.TAU or math.pi * 2
	local TEX = FX.TEX or {}
	local FIRE = (type(S.TEX) == "table" and S.TEX.fire) or TEX.smoke
	local NEON = Enum.Material.Neon
	local PLASTIC = Enum.Material.SmoothPlastic
	local rng = Random.new()

	local FULL, REDUCED = GATE.Full or 160, GATE.Reduced or 250
	local CRIMSON, EMBER, CORE, REI, FROST = PAL.Crimson, PAL.Ember, PAL.Core, PAL.Reiatsu, PAL.Frost
	local SMOKE, BLK = PAL.Smoke, PAL.Black
	local BLOOD = PAL.Blood or Color3.fromRGB(110, 0, 18)
	local TENSA = PAL.Tensa or BLK
	local BOLT_CORE = Color3.fromRGB(255, 196, 186) -- the hot core of a crimson bolt

	local casts = {} -- [userId#id] = cast state
	local byUser = {} -- [userId] = that player's latest cast
	local modeFx = {} -- [character] = the mode's visuals
	local exits = {} -- [character] = the exit performance in progress
	local endedUntil = {} -- [character] = the BankaiUntil a BankaiEnd already closed (never rebuilt from it)
	local coats = {} -- [character] = the coat-tail controller (flare + stream; welds restored when idle)

	---------------------------------------------------------------------------------------------------
	-- small helpers
	local warned = {}
	local function warnOnce(tag, err)
		if not warned[tag] then
			warned[tag] = true
			warn("[Zangetsu.Bankai] " .. tostring(tag) .. ": " .. tostring(err))
		end
	end
	local function safe(tag, fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnOnce(tag, r)
			return nil
		end
		return r
	end
	-- a Shared builder by name (nil-safe: Shared may be missing a builder)
	local function SH(name, ...)
		return safe("S." .. name, S[name], ...)
	end
	-- the first of a handle's methods that exists (handles may be tables or Instances)
	local function try(obj, names, ...)
		if obj == nil then
			return false
		end
		for _, n in ipairs(names) do
			local ok, fn = pcall(function()
				return obj[n]
			end)
			if ok and type(fn) == "function" then
				local ok2, err = pcall(fn, obj, ...)
				if not ok2 then
					warnOnce("handle:" .. n, err)
				end
				return true
			end
		end
		return false
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
		try(h, { "Destroy", "destroy" })
	end
	local function rand(a, b)
		return rng:NextNumber(a, b)
	end
	local function cs(a, b)
		return ColorSequence.new(a, b or a)
	end
	local function nsk(list)
		local k = {}
		for i, v in ipairs(list) do
			k[i] = NumberSequenceKeypoint.new(v[1], v[2])
		end
		return NumberSequence.new(k)
	end
	local function NR(a, b)
		return NumberRange.new(a, b or a)
	end
	local function live(x)
		return typeof(x) == "Instance" and x.Parent ~= nil
	end
	local function tw(obj, t, props, style, dir)
		if not live(obj) then
			return
		end
		local ok, tn = pcall(function()
			return TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		end)
		if ok and tn then
			tn:Play()
		end
	end
	local function partPos(char, name)
		local p = char and char:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p.Position or nil
	end
	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function camDist(pos)
		local ok, d = pcall(ctx.camDist, pos)
		if ok and type(d) == "number" then
			return d
		end
		return (pos - camPos()).Magnitude
	end
	local function camFacing(pos)
		local ok, v = pcall(ctx.camFacing, pos)
		if ok and typeof(v) == "Vector3" then
			return v
		end
		local d = camPos() - pos
		return d.Magnitude > 1e-3 and d.Unit or UP
	end
	-- dark / dusty puffs never start inside the lens' first 8-9 studs
	local function clearOfLens(pos, r)
		return (pos - camPos()).Magnitude > (r or 8.5)
	end
	-- glow size by distance; the local caster's camera is assumed back at ~14 studs (the shot hands back mid-bloom)
	local function bloom(st, pos, size)
		local d = camDist(pos)
		if st and st.isLocal then
			d = math.min(d, 14)
		end
		return size * math.clamp(d / 30, 0.45, 1)
	end
	local function ringScale(st, pos)
		local d = camDist(pos)
		if st and st.isLocal then
			d = math.min(d, 14)
		end
		return math.clamp(d / 30, 0.6, 1), d
	end
	local function groundAt(pos, fallbackY)
		local hit = FX.groundHit and FX.groundHit(pos, 20)
		if hit then
			return hit.Position
		end
		return Vector3.new(pos.X, fallbackY or (pos.Y - 3.19), pos.Z)
	end
	local function partCount(f)
		if not live(f) then
			return 0
		end
		local n = 0
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	local function stillPart(name, color, material, size, cf, parent, t)
		local p = (FX.part and FX.part(name, Enum.PartType.Block, material or NEON, color, nil)) or Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = material or NEON
		p.Color = color
		p.Size = size
		p.CFrame = cf
		p.Transparency = t or 0
		p.Parent = parent
		return p
	end
	-- a flat disc on the ground (a Cylinder's X axis onto world Y)
	local function disc(name, color, material, dia, pos, parent, t)
		local p = stillPart(name, color, material, Vector3.new(0.05, dia, dia), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), parent, t)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function bolt(f, a, b, o)
		if live(f) and FX.bolt then
			safe("bolt", FX.bolt, f, a, b, o)
		end
	end

	-- sounds: Config.Sounds keys through ctx; several at one point share one host part
	local function snd(key, parent, vol, pitch)
		if live(parent) then
			safe("sound", ctx.sound, key, parent, vol or 1, pitch or 1)
		end
	end
	-- every sound rides a part that already exists (the body, the cast's one ground host): no 8 s anchor per call
	local function sndOn(part, list)
		for _, s in ipairs(list) do
			snd(s[1], part, s[2], s[3])
		end
	end

	-- dust doughnut that never rolls a puff through the lens: puffs on the camera's bearing (within 40 deg, for a
	-- camera inside 45 studs) and puffs starting within 9 studs of it are skipped; `avoid` (a flat direction) also
	-- keeps a gap on that bearing (the caster's front, where the reveal shot looks in)
	local function dustRingSafe(f, center, radius, n, speed, o, avoid)
		if type(S.dust) ~= "function" then
			return SH("dustRing", f, center, radius, n, speed, o)
		end
		local cp = camPos()
		local toCam = (cp - center) * FLAT
		local camNear = toCam.Magnitude < 45 and toCam.Magnitude > 0.5
		local camDir = camNear and toCam.Unit or nil
		local off = rand(0, TAU)
		for i = 1, n do
			local a = off + (i / n) * TAU
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			local p = center + radial * radius
			local skip = false
			if camDir then
				local dirTravel = speed >= 0 and radial or -radial
				if radial:Dot(camDir) > 0.766 or dirTravel:Dot(camDir) > 0.766 then
					skip = true
				end
			end
			if avoid and radial:Dot(avoid) > 0.6 then
				skip = true
			end
			if not skip and clearOfLens(p, 9) then
				local gp = groundAt(p + UP * 2, center.Y)
				SH("dust", f, gp + UP * 0.5, radial * speed + UP * 5, o)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the coat tails (DESIGN §1.4: TailBack / TailR / TailL, each with its lining and 3 hem wedges, all welded to the
	-- LowerTorso). Flared / streamed LOCALLY by turning every weld's C0 about the tail's top edge; the original C0s are
	-- written back the moment nothing drives them (and when the coat is rebuilt, the old welds are simply gone).
	local TAIL_NAMES = { "TailBack", "TailR", "TailL" }
	local function coatRig(coat)
		local rig = { coat = coat, tails = {} }
		for _, name in ipairs(TAIL_NAMES) do
			local tp = coat:FindFirstChild(name)
			local w = tp and tp:FindFirstChildOfClass("Weld")
			if tp and tp:IsA("BasePart") and w then
				local pivot = (w.C0 * CFrame.new(0, tp.Size.Y / 2, 0)).Position
				local list = {}
				for _, d in ipairs(coat:GetChildren()) do
					local n = d.Name
					if d:IsA("BasePart") and (n == name or n == name .. "Lining" or n:sub(1, #name + 3) == name .. "Hem") then
						local dw = d:FindFirstChildOfClass("Weld")
						if dw then
							table.insert(list, { w = dw, c0 = dw.C0 })
						end
					end
				end
				local sx = (name == "TailR" and 1) or (name == "TailL" and -1) or 0
				table.insert(rig.tails, { name = name, part = tp, pivot = pivot, list = list, sx = sx })
			end
		end
		return #rig.tails > 0 and rig or nil
	end
	-- back: degrees the tails swing up/back (positive = back); side: extra outward spread of the side tails
	local function poseTails(rig, back, side)
		for _, t in ipairs(rig.tails) do
			local R = CFrame.new(t.pivot) * CFrame.Angles(math.rad(-back), 0, math.rad(side * t.sx)) * CFrame.new(-t.pivot)
			for _, it in ipairs(t.list) do
				if it.w.Parent then
					it.w.C0 = R * it.c0
				end
			end
		end
	end
	local function restoreTails(rig)
		for _, t in ipairs(rig.tails) do
			for _, it in ipairs(t.list) do
				if it.w.Parent then
					it.w.C0 = it.c0
				end
			end
		end
	end
	local function coatCtl(char)
		if typeof(char) ~= "Instance" then
			return nil
		end
		local coat = char:FindFirstChild("ZangetsuCoat")
		local c = coats[char]
		if c and c.rig.coat ~= coat then
			restoreTails(c.rig)
			coats[char] = nil
			c = nil
		end
		if not c and coat then
			local rig = coatRig(coat)
			if rig then
				c = { rig = rig, back = 0, side = 0, streamAt = 0 }
				coats[char] = c
			end
		end
		return c
	end
	-- the reveal / ignite: the tails whip back, then settle on a damped spring
	local function flareCoat(char, amp, dur)
		local c = coatCtl(char)
		if c then
			c.flareT, c.flareAmp, c.flareDur = os.clock(), amp, dur or 0.9
		end
	end
	local function releaseCoat(char)
		local c = coats[char]
		if c then
			restoreTails(c.rig)
			coats[char] = nil
		end
	end
	local function stepCoats(clock)
		for char, c in pairs(coats) do
			if not char.Parent or not live(c.rig.coat) then
				coats[char] = nil
			else
				local streaming = clock - c.streamAt < 0.25
				if not streaming then
					c.back, c.side = c.back * 0.85, c.side * 0.85
				end
				local fl = 0
				if c.flareT then
					local t = clock - c.flareT
					if t > c.flareDur then
						c.flareT = nil
					else
						local k = math.clamp(t / 0.07, 0, 1)
						fl = c.flareAmp * k * math.exp(-3.4 * t) * math.cos(9.5 * math.max(t - 0.07, 0))
					end
				end
				local b = math.clamp(c.back + fl, -5, 75)
				local sd = math.clamp(c.side + math.max(fl, 0) * 0.3, -4, 30)
				if not streaming and not c.flareT and math.abs(c.back) < 0.3 and math.abs(c.side) < 0.3 then
					restoreTails(c.rig)
					coats[char] = nil
				else
					poseTails(c.rig, b, sd)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the caster's cinematic (ctx.shot raycasts every lens against walls and hands back facing the saved look). Two
	-- windows, each <= 1.2 s: BAN / KAI / the eruption, and the reveal.
	local function ease(x)
		return TweenService:GetValue(math.clamp(x, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	local function startShot(st)
		if type(ctx.shot) ~= "function" or not (st.hrp and st.hrp.Parent) then
			return
		end
		local hrp, char = st.hrp, st.char
		local base = CFrame.lookAt(hrp.Position, hrp.Position + st.aim)
		local s0 = st.T.shotStart
		local cuts = type(B.ShotCuts) == "table" and B.ShotCuts or { 0.62, 0.98 }
		local c1, c2 = cuts[1] or st.T.kai, cuts[2] or 0.98
		local dur = math.min(st.T.shot - s0, 1.2)
		st.shotOn = true
		safe("shot", ctx.shot, {
			char = char, t0 = st.t0 + s0, dur = dur, base = base, face = st.aim, cuts = { c1 - s0, c2 - s0 }, cutColor = CRIMSON, fov = 62,
			path = function(es, _, bs, head)
				bs = bs or base
				local e = es + s0 -- cast time
				local hp = (head and head.Parent) and head.Position or (hrp.Position + UP * 1.5)
				if e < c1 then
					-- A: low front-right, looking at the sword hand as the arm locks out; pushing in a stud
					local k = ease((e - s0) / math.max(c1 - s0, 0.05))
					local hand = partPos(char, "RightHand") or hp
					local from = (bs * CFrame.new(6, -0.5, -3.5)).Position
					local dir = hand - from
					local pos = from + (dir.Magnitude > 1e-3 and dir.Unit or Vector3.zero) * k
					return pos, hand:Lerp(hp, 0.25), 62 - 3 * k
				elseif e < c2 then
					-- B: KAI - a close profile on the face and the blade from his left, creeping in (pulled out to 7 studs
					-- and narrowed so the tornado's ribbons swing round inside the lens, not through it)
					local k = ease((e - c1) / (c2 - c1))
					local pos = (bs * CFrame.new(-6.5 + 0.4 * k, 1.7 - 0.2 * k, -2.2 - 0.3 * k)).Position
					local info = ctx.sword and safe("sword", ctx.sword, char)
					local mid = info and live(info.mid) and info.mid.WorldPosition or (hp + st.aim * 2)
					return pos, hp:Lerp(mid, 0.3), 50 - 3 * k
				end
				-- C: pulled back low and wide behind him; tilting up as the column erupts into the sky
				local k = ease((e - c2) / math.max(st.T.shot - c2, 0.05))
				local pos = (bs * CFrame.new(0, 4 + 0.8 * k, 24 - 1.5 * k)).Position
				return pos, (bs * CFrame.new(0, 3 + 15 * k, 0)).Position, 70 + 12 * k
			end,
		})
	end
	-- the reveal: low front three-quarter on him as the column breaks, pushing in through the chiburi
	local function startRevealShot(st)
		if type(ctx.shot) ~= "function" or not (st.hrp and st.hrp.Parent) then
			return
		end
		local hrp, char = st.hrp, st.char
		local base = CFrame.lookAt(hrp.Position, hrp.Position + st.aim)
		local rs = st.T.revealShot
		st.revealOn = true
		safe("shot", ctx.shot, {
			char = char, t0 = st.t0 + rs[1], dur = math.min(rs[2] - rs[1], 1.2), base = base, face = st.aim, fov = 50,
			path = function(_, a, bs, head)
				bs = bs or base
				local k = ease(a)
				local hp = (head and head.Parent) and head.Position or (hrp.Position + UP * 1.5)
				local ch = partPos(char, "UpperTorso") or hp
				local pos = (bs * CFrame.new(4.4 - 0.6 * k, -0.9 + 0.3 * k, -9.6 + 1.5 * k)).Position
				return pos, ch:Lerp(hp, 0.35) + UP * 0.2, 50 - 5 * k
			end,
		})
	end

	---------------------------------------------------------------------------------------------------
	-- layers
	local function streaksIn(st, color2)
		local chest = partPos(st.char, "UpperTorso") or (st.hrp and st.hrp.Position)
		if not chest then
			return
		end
		-- the sphere never reaches the lens (an inward streak born at the camera is a blob on the screen)
		local r = math.clamp(camDist(chest) - 3, 3, 12)
		FX.streaks(st.f, chest, { inward = r, color = WHITE, color2 = color2, count = st.tier == 1 and 22 or 12, life = 0.35, size = 0.4 })
	end
	local function arcsRound(st, crimson)
		local chest = partPos(st.char, "UpperTorso")
		if not chest then
			return
		end
		FX.arcs(st.f, chest, 2.5, {
			count = st.tier == 1 and 2 or 1, width = 0.06, life = 0.12,
			colors = crimson and { CRIMSON, EMBER, CRIMSON } or { CORE, REI },
		})
	end
	-- a white sliver racing up the blade's edge, then a star at the tip
	local function bladeGlint(st, color)
		local info = st.char and safe("sword", ctx.sword, st.char)
		if not (info and live(info.base) and live(info.tip)) then
			return
		end
		local a, b = info.base.WorldPosition, info.tip.WorldPosition
		local len = (b - a).Magnitude
		if len < 0.5 then
			return
		end
		local sl = stillPart("BankaiGlint", color or WHITE, NEON, Vector3.new(0.08, 0.08, 0.7), CFrame.lookAt(a, b), st.f, 0)
		local t0 = os.clock()
		task.spawn(function()
			while sl.Parent and os.clock() - t0 < 0.22 do
				local info2 = safe("sword", ctx.sword, st.char)
				if info2 and live(info2.base) and live(info2.tip) then
					a, b = info2.base.WorldPosition, info2.tip.WorldPosition
				end
				local k = (os.clock() - t0) / 0.22
				sl.CFrame = CFrame.lookAt(a:Lerp(b, k), b + (b - a).Unit)
				task.wait()
			end
			if sl.Parent then
				sl:Destroy()
				FX.sparks(st.f, b, { color = WHITE, color2 = color or CRIMSON, count = 1, size = 0.9, speed = { 0, 1 }, life = 0.35, accel = Vector3.zero })
				FX.glow(st.f, b, bloom(st, b, 2.2), color or WHITE, 0.25, { alpha = 0.3 })
			end
		end)
	end
	-- a four-point star glinting off Tensa Zangetsu's tip, square to the lens (scaled by distance)
	local function starGlint(st, color)
		local info = st.char and safe("sword", ctx.sword, st.char)
		if not (info and live(info.tip)) or not live(st.f) then
			return
		end
		local tip = info.tip.WorldPosition
		local s = bloom(st, tip, 1)
		local cf = CFrame.lookAt(tip, camPos()) * CFrame.Angles(0, 0, math.rad(rand(-12, 12)))
		local bars = {
			stillPart("BankaiStar", WHITE, NEON, Vector3.new(0.05, 0.05, 0.02), cf, st.f, 0),
			stillPart("BankaiStar", color or CRIMSON, NEON, Vector3.new(0.05, 0.05, 0.02), cf, st.f, 0.2),
		}
		local peak = { Vector3.new(3.0 * s, 0.07, 0.02), Vector3.new(0.07, 1.9 * s, 0.02) }
		for i, p in ipairs(bars) do
			tw(p, 0.07, { Size = peak[i] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.09, function()
				tw(p, 0.22, { Size = Vector3.new(0.02, 0.02, 0.02), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
			Debris:AddItem(p, 0.4)
		end
		FX.glow(st.f, tip, bloom(st, tip, 1.8), color or CRIMSON, 0.3, { alpha = 0.25 })
		snd("Zap", st.hrp, 0.25, 1.8)
	end
	local function setAura(st, rate)
		if st.aura then
			try(st.aura, { "set" }, rate)
		end
	end
	local function setGlow(st, k)
		if st.glow then
			try(st.glow, { "set" }, k)
		end
	end
	local function swapGlow(st, black)
		if st.glow then
			if not try(st.glow, { "stop" }) then
				kill(st.glow)
			end
			st.glow = nil
		end
		if st.char and st.tier <= 2 then
			st.glow = SH("bladeGlow", st.char, black and { black = true, color2 = CRIMSON } or { color = CORE, color2 = REI })
			st.glowForm = safe("form", ctx.form, st.char)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- THE TORNADO: reiatsu ribbons (trail runners) orbiting him on a rising funnel. Ice-blue wind at BAN; from KAI the
	-- dark ribbons join (black, unlit) and the light ones burn crimson, two dark ones drag black smoke; the funnel climbs
	-- and spins faster, is sucked in tight on the brace, then sucked up the column at the eruption, where the very same
	-- ribbons race up its skin until the reveal.
	local function makeTornado(st)
		st.tor = {}
		local n = st.tier == 1 and 10 or 4
		for i = 1, n do
			local thin = st.tier == 1 and i > 8 -- two hot hairline streaks on the outside of the funnel
			local dark = not thin and (i % 2 == 0)
			local w = (thin and 0.18) or (dark and 0.95) or 0.45
			local p = stillPart("BankaiWind", WHITE, NEON, Vector3.one * 0.15, CFrame.new(st.g + UP), st.f, 1)
			local tr = FX.trail(p, thin and cs(WHITE, REI) or cs(FROST, REI), w, dark and 0.34 or 0.28, { tail = 0.2, brightness = thin and 3 or 1.8, alpha = thin and 0.1 or 0.3 })
			local r = {
				part = p, trail = tr, dark = dark, thin = thin, phase = (i - 1) / n, u = rand(0, 1), spd = rand(0.85, 1.15), lastH = 0,
				ang = (i - 1) / n * TAU, rad = 2.3, near = false, seq = tr and tr.Transparency,
			}
			if tr then
				tr.Enabled = not dark -- the dark ribbons join at KAI
			end
			table.insert(st.tor, r)
		end
	end
	local function tornadoKai(st)
		if st.torKai then
			return
		end
		st.torKai = true
		for i, r in ipairs(st.tor or {}) do
			local tr = r.trail
			if tr then
				if r.dark then
					tr.Color = cs(BLK, SMOKE)
					tr.LightEmission = 0
					tr.LightInfluence = 0
					tr.Transparency = nsk({ { 0, 0.18 }, { 0.6, 0.45 }, { 1, 1 } })
					r.seq = tr.Transparency
					tr.Enabled = true
				else
					tr.Color = r.thin and cs(Color3.fromRGB(255, 170, 160), CRIMSON) or cs(EMBER, CRIMSON)
					pcall(function()
						tr.Brightness = r.thin and 3 or 2.4
					end)
				end
			end
			if r.dark and i <= 4 and st.tier == 1 then
				r.smoke = FX.emitter(r.part, {
					Texture = TEX.smoke, Color = cs(SMOKE, BLK), LightEmission = 0, LightInfluence = 0.3,
					Size = nsk({ { 0, 1.1 }, { 0.5, 2.2 }, { 1, 3 } }), Transparency = nsk({ { 0, 0.62 }, { 0.4, 0.5 }, { 1, 1 } }),
					Lifetime = NR(0.45, 0.7), Speed = NR(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Drag = 2,
					Acceleration = Vector3.new(0, 4, 0), Rotation = NR(0, 360), RotSpeed = NR(-90, 90),
				})
			end
		end
	end
	local function stepTornado(st, e, dt)
		local T = st.T
		local cp = camPos()
		local g = st.g
		local onPillar = e >= T.erupt
		local r0, top, spin
		if e < T.kai then
			local u = math.clamp(e / math.max(T.kai, 0.05), 0, 1)
			r0, top, spin = 2.3 + 0.5 * u, 2 + 2.5 * u, 1.3 + 0.5 * u
		elseif not onPillar then
			local v = math.clamp((e - T.kai) / math.max(T.erupt - T.kai, 0.05), 0, 1)
			r0, top, spin = 2.8 + 0.6 * v, 4.5 + 10 * v, 1.8 + 1.6 * v
			-- the brace: the funnel is sucked in tight before the burst
			local b = math.clamp((e - (T.erupt - 0.12)) / 0.12, 0, 1)
			r0 -= 1.4 * b
		end
		local Hh = st.pillarH * 0.8
		local Rp = st.pillarR + 0.45
		for _, r in ipairs(st.tor or {}) do
			if live(r.part) then
				local h, rad
				if not onPillar then
					-- rising spiral streaks: each ribbon climbs the funnel as it orbits and is reborn at his feet (its
					-- trail cleared on the wrap, so the jump is never drawn)
					r.u += dt * (st.kaiDone and 1.35 or 0.95) * r.spd
					if r.u >= 1 then
						r.u %= 1
						if r.trail then
							pcall(function()
								r.trail:Clear()
							end)
						end
					end
					h = top * r.u
					rad = r0 + h * 0.22 + (r.dark and 0.4 or 0) + (r.thin and 0.8 or 0)
					r.ang += dt * spin * TAU * r.spd
				else
					-- sucked up the column: racing up its skin, wrapping back to the foot (trail cleared on the wrap)
					if not r.climb0 then
						r.climb0 = r.lastH / Hh
						r.te = e
					end
					local u = (r.climb0 + (e - r.te) * 1.35 * r.spd) % 1
					h = u * Hh
					if h < r.lastH - 0.5 and r.trail then
						pcall(function()
							r.trail:Clear()
						end)
					end
					rad = r.rad + (Rp - r.rad) * math.clamp((e - r.te) / 0.12, 0, 1)
					r.ang += dt * TAU * (0.85 + 1.4 * 1.35 * r.spd)
					if r.smoke then
						r.smoke.Rate = 0
					end
				end
				if not onPillar then
					r.rad = rad
				end
				r.lastH = h
				local pos = g + Vector3.new(math.cos(r.ang) * rad, h + 0.4, math.sin(r.ang) * rad)
				r.part.CFrame = CFrame.new(pos)
				local dc = (pos - cp).Magnitude
				local near = dc < 4.5
				if near ~= r.near and r.trail then
					r.near = near
					r.trail.Transparency = near and nsk({ { 0, 0.85 }, { 1, 1 } }) or r.seq
				end
				if r.smoke and not onPillar then
					r.smoke.Rate = dc > 9 and 16 or 0
				end
			end
		end
	end
	local function dropTornado(st)
		for _, r in ipairs(st.tor or {}) do
			if r.trail then
				r.trail.Enabled = false
			end
			if r.smoke then
				r.smoke.Rate = 0
			end
			if live(r.part) then
				Debris:AddItem(r.part, 0.6)
			end
		end
		st.tor = {}
	end

	-- pebbles torn off the ground, spiralling up into the funnel, hurled outward by the eruption
	local function makePebbles(st, n)
		st.pebbles = {}
		local col, mat = Color3.fromRGB(110, 104, 98), Enum.Material.Slate
		local hit = FX.groundHit and FX.groundHit(st.g + UP * 2, 8)
		if hit and type(S.groundColor) == "function" then
			local ok, c, m = pcall(S.groundColor, hit)
			if ok and typeof(c) == "Color3" then
				col = c
				if typeof(m) == "EnumItem" then
					mat = m
				end
			end
		end
		for _ = 1, n do
			local s = rand(0.22, 0.55)
			local p = stillPart("BankaiPebble", col:Lerp(BLACK, rand(0, 0.35)), mat, Vector3.new(s, s * rand(0.6, 1), s * rand(0.7, 1.1)), CFrame.new(st.g), st.f, 0)
			table.insert(st.pebbles, {
				part = p, a = rand(0, TAU), r = rand(2.6, 5), h = 0.1, rise = rand(2, 5), w = rand(1.4, 2.4),
				axis = FX.randUnit and FX.randUnit() or UP, spin = rand(3, 8), delay = rand(0, 0.3), t = 0,
			})
		end
	end
	local function stepPebbles(st, e, dt)
		local top = st.kaiDone and 12 or 4
		local wMul = st.kaiDone and 2 or 1
		for _, pb in ipairs(st.pebbles or {}) do
			if live(pb.part) then
				pb.t += dt
				if pb.t > pb.delay then
					pb.h = math.min(pb.h + pb.rise * dt * wMul, top)
					pb.a += pb.w * dt * wMul
					pb.r = math.max(pb.r - dt * 0.4, 2.2)
				end
				local pos = st.g + Vector3.new(math.cos(pb.a) * pb.r, pb.h + 0.2, math.sin(pb.a) * pb.r)
				pb.part.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(pb.axis, pb.t * pb.spin)
			end
		end
	end
	local function flingPebbles(st)
		for _, pb in ipairs(st.pebbles or {}) do
			local p = pb.part
			if live(p) then
				local out = Vector3.new(math.cos(pb.a), 0, math.sin(pb.a))
				local to = p.Position + out * rand(14, 24) + UP * rand(4, 12)
				tw(p, 0.55, { Position = to, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				Debris:AddItem(p, 0.6)
			end
		end
		st.pebbles = {}
	end

	-- crimson lightning forks striking the ground round him (never toward the lens)
	local function groundStrikes(st, n, chestPos)
		local cp = camPos()
		local toCam = (cp - st.g) * FLAT
		local camA = toCam.Magnitude > 0.5 and math.atan2(toCam.Z, toCam.X) or nil
		for _ = 1, n do
			local a = rand(0, TAU)
			if camA then
				local da = math.abs(((a - camA + math.pi) % TAU) - math.pi)
				if da < math.rad(60) then
					a += math.pi
				end
			end
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local gp = groundAt(st.g + dir * rand(4.5, 8) + UP * 2, st.g.Y)
			local from = chestPos + dir * 1.2 + UP * rand(-0.3, 0.8)
			if clearOfLens((from + gp) / 2, 4) and clearOfLens(gp, 3) then
				bolt(st.f, from, gp, { color = CRIMSON, core = BOLT_CORE, width = 0.12, segments = 5, jag = 0.3, life = 0.12, restrike = 2 })
				FX.glow(st.f, gp + UP * 0.3, bloom(st, gp, 2.2), CRIMSON, 0.22, { alpha = 0.4 })
				FX.sparks(st.f, gp, { color = EMBER, color2 = CRIMSON, count = 5, speed = { 6, 14 }, size = 0.25, life = 0.35, dir = UP, spread = 60 })
			end
		end
		snd("Zap", st.hrp, 0.35, rand(0.85, 1.15))
	end

	-- crimson lightning crawling up the column's skin: two climbing chains of short bolts, re-struck every 0.06 s
	local function stepCrawl(st, e)
		if (st.crawlers or 0) <= 0 or e < st.nextCrawl then
			return
		end
		st.nextCrawl = e + 0.06
		local te = e - st.T.erupt
		local R = st.pillarR * 1.06
		local Hh = st.pillarH * 0.85
		for c = 1, st.crawlers do
			local cyc = (te * 1.45 + (c - 1) / st.crawlers) % 1
			local h = cyc * Hh
			local a0 = st.crawlA[c] + cyc * TAU * 0.6
			local a1 = a0 + rand(-0.55, 0.55)
			local p0 = st.g + Vector3.new(math.cos(a0) * R, h + 0.5, math.sin(a0) * R)
			local p1 = st.g + Vector3.new(math.cos(a1) * R, h + rand(7, 12), math.sin(a1) * R)
			if clearOfLens(p0, 5) and clearOfLens(p1, 5) then
				bolt(st.f, p0, p1, { color = CRIMSON, core = BOLT_CORE, width = 0.16, segments = 4, jag = 0.24, life = 0.1, restrike = 1 })
				-- now and then a fork leaps off the column
				if st.tier == 1 and rng:NextNumber() < 0.22 then
					local out = Vector3.new(math.cos(a1), 0, math.sin(a1))
					local p2 = p1 + out * rand(4, 8) + UP * rand(-3, 3)
					if clearOfLens(p2, 6) then
						bolt(st.f, p1, p2, { color = CRIMSON, core = BOLT_CORE, width = 0.1, segments = 3, jag = 0.35, life = 0.09, restrike = 1 })
					end
				end
			end
		end
	end

	-- the dome shockwave racing across the ground: two ForceField shells (crimson, ember) + a wavefront at their foot
	local function dome(st)
		local near = st.isLocal or camDist(st.g) < 40
		local R1, R2, T1 = DOME.Radius or 46, DOME.Radius2 or 34, DOME.Time or 0.8
		for _, spec in ipairs({ { R1, CRIMSON, 0, T1 }, { R2, EMBER, 0.07, T1 * 0.85 } }) do
			task.delay(spec[3], function()
				if not live(st.f) then
					return
				end
				local b = stillPart("BankaiDome", spec[2], Enum.Material.ForceField, Vector3.one * 4, CFrame.new(st.g), st.f, near and 0.8 or 0.4)
				b.Shape = Enum.PartType.Ball
				tw(b, spec[4], { Size = Vector3.one * spec[1] * 2, Transparency = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
				Debris:AddItem(b, spec[4] + 0.1)
			end)
		end
		FX.ring(st.f, st.g + UP * 0.25, UP, 2, R1, CRIMSON, T1, { alpha = 0.25 })
	end

	-- the crown: rings and a dark cloud rolling out off the top of the column
	local function crown(st)
		local top = st.g + UP * st.pillarH
		FX.ring(st.f, top, UP, 4, 48, CRIMSON, 1.1, { alpha = 0.3 })
		FX.ring(st.f, top + UP * 2, UP, 3, 34, EMBER, 0.8, { alpha = 0.45 })
		if st.tier <= 2 then
			FX.light(st.f, top, CRIMSON, 6, 60, 1)
			FX.streaks(st.f, top, { dir = UP, spread = 35, color = EMBER, color2 = CRIMSON, count = st.tier == 1 and 16 or 8, speed = { 60, 110 }, size = 0.8, life = 0.5 })
			if type(S.dust) == "function" then
				local n = st.tier == 1 and 8 or 4
				local a0 = rand(0, TAU)
				for i = 1, n do
					local a = a0 + (i - 1) / n * TAU
					local dir = Vector3.new(math.cos(a), 0, math.sin(a))
					SH("dust", st.f, top + dir * 6, dir * 32 + UP * 2, { color = SMOKE, s0 = 8, s1 = 20, life = { 1.1, 1.6 }, count = 1 })
				end
			end
		end
	end

	-- the reddened sky: a local colour grade (cameras within Gate.Grade), faded out after the reveal
	local function gradeOn(st)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local d = st.isLocal and 0 or camDist(st.g)
		local k = 1 - math.clamp(d / (GATE.Grade or 250), 0, 1)
		if k <= 0.05 then
			return
		end
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ZangetsuBankaiGrade"
		cc.Parent = cam
		st.grade = cc
		Debris:AddItem(cc, 4)
		tw(cc, 0.12, {
			TintColor = WHITE:Lerp(Color3.fromRGB(255, 208, 205), k), Contrast = 0.12 * k, Saturation = 0.15 * k, Brightness = -0.03 * k,
		})
	end
	local function gradeOff(st, t)
		local cc = st.grade
		st.grade = nil
		if live(cc) then
			tw(cc, t or 0.8, { TintColor = WHITE, Contrast = 0, Saturation = 0, Brightness = 0 })
			Debris:AddItem(cc, (t or 0.8) + 0.1)
		end
	end

	-- the coat whipping round him as it appears: a black ribbon and its crimson lining, twice round, hip to shoulder
	local function coatWhip(st, e)
		if not live(st.hrp) then
			return
		end
		st.whip = {}
		st.whipAt = e
		for _, spec in ipairs({ { BLK, 1.3, 0 }, { CRIMSON, 0.35, 0.55 } }) do
			local p = stillPart("BankaiWhip", WHITE, NEON, Vector3.one * 0.15, st.hrp.CFrame, st.f, 1)
			local tr = FX.trail(p, cs(spec[1]), spec[2], 0.28, { tail = 0.3, alpha = 0.2, brightness = 2 })
			if tr and spec[1] == BLK then
				tr.LightEmission = 0
			end
			table.insert(st.whip, { part = p, trail = tr, off = spec[3] })
		end
	end
	local function stepWhip(st, e)
		if not st.whip then
			return
		end
		local k = (e - st.whipAt) / 0.4
		if k >= 1 or not live(st.hrp) then
			for _, w in ipairs(st.whip) do
				if w.trail then
					w.trail.Enabled = false
				end
				if live(w.part) then
					Debris:AddItem(w.part, 0.4)
				end
			end
			st.whip = nil
			return
		end
		local hp = st.hrp.Position
		for _, w in ipairs(st.whip) do
			local a = w.off * math.pi + k * 2.1 * TAU
			local r = 2.1 - 0.4 * k
			w.part.CFrame = CFrame.new(hp + Vector3.new(math.cos(a) * r, -1.7 + 3.4 * k, math.sin(a) * r))
		end
	end

	-- the chiburi: the flick that shakes the blade clean - a spray of crimson drops and black wisps off the tip
	local function chiburiSpray(st)
		local info = st.char and safe("sword", ctx.sword, st.char)
		if not (info and live(info.tip) and live(info.mid)) then
			return
		end
		local tip, mid = info.tip.WorldPosition, info.mid.WorldPosition
		local along = (tip - mid)
		along = along.Magnitude > 1e-3 and along.Unit or -UP
		local dir = (along + (along * FLAT) * 0.6 - UP * 0.3)
		dir = dir.Magnitude > 1e-3 and dir.Unit or along
		FX.sparks(st.f, tip, { color = CRIMSON, color2 = BLOOD, count = st.tier == 1 and 16 or 8, speed = { 16, 30 }, size = 0.28, life = 0.6, dir = dir, spread = 22, accel = Vector3.new(0, -45, 0), drag = 1 })
		FX.sparks(st.f, tip, { color = EMBER, color2 = CRIMSON, count = 6, speed = { 8, 16 }, size = 0.35, life = 0.35, dir = dir, spread = 35 })
		if st.tier == 1 and clearOfLens(mid, 5) then
			SH("ash", st.f, mid, { count = 10, radius = 0.8, life = 0.9, rise = 3 })
		end
		snd("Whoosh", st.hrp, 0.5, 1.4)
	end

	---------------------------------------------------------------------------------------------------
	-- the lifted rocks hurled outward (Rocks:drop takes one push for all of them, so each gets its own radial)
	local function hurlRocks(st)
		local rk = st.rocks
		st.rocks = nil
		if type(rk) ~= "table" then
			return
		end
		try(rk, { "drop" })
		for _, r in ipairs(rk.list or {}) do
			local p = r.part
			if live(p) then
				local radial = ((p.Position - st.g) * FLAT)
				radial = radial.Magnitude > 0.1 and radial.Unit or Vector3.new(math.cos(rand(0, TAU)), 0, math.sin(rand(0, TAU)))
				p.AssemblyLinearVelocity = radial * rand(45, 80) + UP * rand(25, 50)
				p.AssemblyAngularVelocity = FX.randUnit() * rand(8, 16)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the end of a cast
	local function sweep(st, pillarSecs)
		dropTornado(st)
		for _, pb in ipairs(st.pebbles or {}) do
			if live(pb.part) then
				pb.part:Destroy()
			end
		end
		st.pebbles = {}
		if st.whip then
			for _, w in ipairs(st.whip) do
				if live(w.part) then
					w.part:Destroy()
				end
			end
			st.whip = nil
		end
		st.crawlers = 0
		for _, k in ipairs({ "aftEmbers", "aftSmoke" }) do
			local h = st[k]
			if live(h) then
				for _, em in ipairs(h:GetDescendants()) do
					if em:IsA("ParticleEmitter") then
						em.Rate = 0
					end
				end
				Debris:AddItem(h, 2)
			end
			st[k] = nil
		end
		if st.pillar and pillarSecs then
			if not try(st.pillar, { "dissolve" }, pillarSecs) then
				kill(st.pillar)
			end
		end
		st.pillar = nil
		if st.rocks then
			try(st.rocks, { "drop" })
			st.rocks = nil
		end
		kill(st.eyes)
		st.eyes = nil
		kill(st.kaiEyes)
		st.kaiEyes = nil
	end
	local function finishCast(st)
		if st.ended then
			return
		end
		st.ended = true
		sweep(st, nil)
		gradeOff(st, 0.6)
		kill(st.aura)
		st.aura = nil
		if st.glow and not try(st.glow, { "stop" }) then
			kill(st.glow)
		end
		st.glow = nil
		casts[st.key] = nil
		if byUser[st.userId] == st then
			byUser[st.userId] = nil
		end
	end
	local function cancelCast(st)
		if st.ended then
			return
		end
		if st.isLocal then
			if st.shotOn or st.revealOn then
				st.shotOn, st.revealOn = false, false
				safe("stopShot", ctx.stopShot)
			end
			safe("unroot", ctx.unroot)
		end
		for _, tr in pairs(st.tracks) do
			pcall(function()
				tr:stop(0.2)
			end)
		end
		local c = st.char and coats[st.char]
		if c then
			c.flareT = nil
		end
		sweep(st, 0.3) -- the column collapses
		gradeOff(st, 0.3)
		finishCast(st)
	end

	---------------------------------------------------------------------------------------------------
	-- BankaiCast: the whole client timeline
	H.BankaiCast = function(d)
		if type(d) ~= "table" or type(d.t0) ~= "number" or typeof(d.origin) ~= "Vector3" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			return
		end
		local e = ctx.now() - d.t0
		local rsh = (type(d.revealShot) == "table" and d.revealShot) or (type(B.RevealShot) == "table" and B.RevealShot) or { 2.06, 2.76 }
		local T = {
			kai = d.kaiAt or B.KaiAt or 0.62, erupt = d.eruptAt or B.EruptAt or 1.18, form = d.formAt or B.FormAt or 1.42,
			reveal = d.revealAt or B.RevealAt or 2.15, mode = d.modeAt or B.ModeAt or 2.75, shot = d.shotEnd or B.ShotEnd or 1.32,
			lock = d.lock or B.Lock or 3.15, shotStart = d.shotStart or B.ShotStart or 0.12,
			revealShot = { tonumber(rsh[1]) or 2.06, tonumber(rsh[2]) or 2.76 },
		}
		if e > T.mode + 0.5 then
			return -- long past: the mode visuals come from the attribute
		end
		local old = byUser[d.userId]
		if old then
			cancelCast(old)
		end
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster ~= nil and caster == ctx.player
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local origin = d.origin
		local aim = ctx.flat(d.aim or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
		local g = Vector3.new(origin.X, d.groundY or (origin.Y - 3.19), origin.Z)
		local dist = isLocal and 0 or camDist(origin)
		local tier = (isLocal or dist <= FULL) and 1 or ((dist <= REDUCED) and 2 or 3)
		local f = ctx.castFolder("Bankai", 8)
		local sndHost = FX.anchor(f, g + UP * 2, 7.5) -- the cast's ground sounds all ride this one part
		local st = {
			key = key, id = d.id, userId = d.userId, t0 = d.t0, T = T, f = f, char = char, hrp = hrp, isLocal = isLocal,
			origin = origin, aim = aim, g = g, tier = tier, dist = dist, tracks = {}, tor = {}, pebbles = {},
			pillarR = d.pillarRadius or B.PillarRadius or 7, pillarH = d.pillarHeight or B.PillarHeight or 120,
			radius = d.radius or B.Radius or 30, sndHost = sndHost, crawlers = 0, crawlA = {}, nextCrawl = 0,
			nextStreak = 0, nextArc = 0.3, nextAsh = T.erupt + 0.1, nextPC = 0, pc = 0, kaiDone = e >= T.kai,
		}
		casts[key] = st
		byUser[d.userId] = st
		local budget = B.Budget or 340

		-- beat(at, tag, fn[, keepUntil]): skipped when long past; a long-lived layer runs late until keepUntil
		local function beat(at, tag, fn, keepUntil)
			local late = e - at
			if late > 0.05 and not (keepUntil and e < keepUntil) then
				return
			end
			task.delay(math.max(at - e, 0), function()
				if not st.ended then
					safe(tag, fn, late > 0.05)
				end
			end)
		end
		local function clipAt(at, name)
			local clip = ctx.Clips and ctx.Clips[name]
			if not (clip and char) or tier > 2 then
				return
			end
			local function go()
				if st.ended then
					return
				end
				local tr = safe("playClip", ctx.playClip, char, clip, ctx.now() - d.t0 - at)
				if tr then
					st.tracks[name] = tr
				end
			end
			if e >= at then
				go()
			else
				task.delay(at - e, go)
			end
		end
		if e < T.erupt - 0.02 then
			clipAt(0, "BankaiCharge")
		end
		clipAt(T.erupt, "BankaiReveal")

		local function feet()
			local p = st.hrp and st.hrp.Parent and st.hrp.Position
			return p and Vector3.new(p.X, g.Y, p.Z) or g
		end
		local function chest()
			return partPos(st.char, "UpperTorso") or (st.hrp and st.hrp.Parent and st.hrp.Position) or (g + UP * 3)
		end
		local function roomy()
			return partCount(f) < budget
		end

		-------------------------------------------------------------------------------------------------
		-- 0.00 BAN...
		if isLocal then
			safe("root", ctx.root, math.max(T.lock - e, 0.05), aim)
			if e < 0.4 then
				safe("callout", ctx.callout, "Ban")
			end
		end
		beat(T.shotStart, "shotA", function()
			if isLocal and ctx.now() - d.t0 < T.shot - 0.15 then
				startShot(st)
			end
		end)
		if e < T.kai and hrp then
			snd("Swell", hrp, 0.9, 0.8)
			snd("Hum", hrp, 0.6, 0.7)
			snd("Drone", hrp, 0.5, 0.9)
			if tier <= 2 and char then
				st.aura = SH("aura", char, { color = CORE, color2 = REI, rate = 30 })
				swapGlow(st, false)
				setGlow(st, 0.3)
			end
		end
		if tier <= 2 and e < T.erupt - 0.1 then
			safe("tornado", makeTornado, st)
			if e >= T.kai then
				safe("tornadoKai", tornadoKai, st)
			end
		end
		beat(0.10, "rocks", function()
			if tier <= 2 then
				st.rocks = FX.liftRocks(f, feet(), 12, tier == 1 and 14 or 8)
			end
		end)
		beat(0.30, "pebbles", function()
			if tier == 1 then
				makePebbles(st, 12)
			end
		end)
		for i, at in ipairs({ 0.22, 0.5 }) do
			beat(at, "cracks", function()
				if tier <= 2 then
					SH("cracks", f, feet(), i == 1 and 8 or 4, i == 1 and 10 or 9, REI, i == 1 and 1.0 or 0.8)
				end
				sndOn(st.hrp, { { "HitHeavy", 0.25, 0.5 } })
			end)
		end
		for _, at in ipairs({ 0.15, 0.45 }) do
			beat(at, "dustIn", function()
				if tier == 1 then
					dustRingSafe(f, feet(), 10, 8, -15, { s0 = 2, s1 = 5, life = { 0.7, 1.0 } })
				end
			end)
		end
		for _, at in ipairs({ 0.15, 0.40 }) do
			beat(at, "ringsIn", function()
				FX.ring(f, feet() + UP * 0.2, UP, 20, 3, REI, 0.5, { ease = "in", alpha = 0.4 })
			end)
		end
		-- 0.22: the arm locks out - a glint runs the cleaver, the pressure flattens the dust under him
		beat(0.22, "lockout", function()
			if tier <= 2 then
				bladeGlint(st, WHITE)
				local fp = feet()
				FX.ring(f, fp + UP * 0.15, UP, 1, 9, REI, 0.35, { alpha = 0.35 })
				FX.glow(f, fp + UP * 0.6, bloom(st, fp, 6), REI, 0.5, { alpha = 0.55 })
				snd("Zap", st.hrp, 0.35, 1.4)
				snd("Whoosh", st.hrp, 0.4, 0.6)
			end
		end)

		-------------------------------------------------------------------------------------------------
		-- 0.62 ...KAI!
		beat(T.kai, "kai", function()
			st.kaiDone = true
			if isLocal then
				safe("callout", ctx.callout, "Kai")
				safe("shake", ctx.shake, 0.4, 0.5, 26)
				safe("vignette", ctx.vignette, 0.18, 0.5, CRIMSON)
			end
			if st.hrp then
				snd("Thunder", st.hrp, 0.9, 0.7)
				snd("Boom", st.hrp, 0.5, 0.6)
				snd("Crackle", st.hrp, 0.6, 0.8)
			end
			if tier <= 2 and st.char then
				kill(st.aura)
				-- (the close-up shot B sits ~7 studs from his body: the black aura stays thin while it is on)
				st.aura = SH("aura", st.char, { black = true, color2 = CRIMSON, rate = isLocal and 30 or 80 })
				swapGlow(st, true)
				setGlow(st, 1)
				safe("tornadoKai", tornadoKai, st)
				-- the eyes flash crimson for the close-up
				if camDist(chest()) < 60 then
					st.kaiEyes = SH("eyes", st.char, { color = CRIMSON })
					local h = st.kaiEyes
					task.delay(0.5, function()
						if st.kaiEyes == h then
							kill(h)
							st.kaiEyes = nil
						end
					end)
				end
			end
			local fp, c = feet(), chest()
			if tier <= 2 then
				local a0 = rand(0, TAU)
				for i = 1, 6 do
					local a = a0 + (i - 1) / 6 * TAU
					local p = fp + Vector3.new(math.cos(a), 0, math.sin(a)) * 4
					if clearOfLens(p + UP * 2, 8) then
						SH("reiatsuFlame", f, p, { black = true, color2 = CRIMSON, count = 12, height = 6, size = 1.3, life = 0.7 })
					end
				end
				FX.glow(f, c, bloom(st, c, 7), CRIMSON, 0.35, { alpha = 0.35 })
				FX.light(f, c, CRIMSON, 5, 22, 0.5)
				FX.sparks(f, c, { color = EMBER, color2 = CRIMSON, count = tier == 1 and 18 or 8, speed = { 18, 40 }, size = 0.4, life = 0.6 })
				groundStrikes(st, tier == 1 and 3 or 1, c)
			end
			FX.ring(f, fp + UP * 0.3, UP, 2, 16, CRIMSON, 0.45, { alpha = 0.3 })
		end)
		for _, dt in ipairs({ 0.16, 0.28 }) do
			beat(T.kai + dt, "strikes", function()
				if tier == 1 and roomy() then
					groundStrikes(st, 2, chest())
				end
			end)
		end
		for _, dt in ipairs({ 0.10, 0.36 }) do
			beat(T.kai + dt, "ringsInRed", function()
				FX.ring(f, feet() + UP * 0.2, UP, 20, 3, CRIMSON, 0.5, { ease = "in", alpha = 0.35 })
			end)
		end
		-- 0.90: the ground gives under the pressure - crimson cracks, dust ripped inward
		beat(T.kai + 0.28, "kaiCracks", function()
			if tier <= 2 then
				SH("cracks", f, feet(), 6, 14, CRIMSON, 1.0)
				sndOn(st.hrp, { { "HitHeavy", 0.35, 0.45 } })
			end
			if tier == 1 then
				dustRingSafe(f, feet(), 12, 10, -22, { s0 = 2, s1 = 6, life = { 0.6, 0.9 } })
			end
		end)
		-- 0.98: the core of light swells in his chest; the column's roar rises
		beat(T.erupt - 0.2, "swell", function()
			if tier <= 2 then
				local c = chest()
				FX.glow(f, c, bloom(st, c, 4.5), CRIMSON, 0.25, { alpha = 0.45, from = 0.2, to = 1.6 })
				FX.light(f, c, CRIMSON, 4, 18, 0.25)
			end
			sndOn(st.hrp or st.sndHost, { { "Rise", 0.6, 1.1 } })
		end)
		-- the black aura thickens once the close-up is over; the caster's big shake lands on the hand-back frame
		beat(T.shot, "auraUp", function()
			st.shotOn = false -- handed back
			if isLocal then
				setAura(st, 80)
				if st.erupted and not st.shook then
					st.shook = true
					safe("shake", ctx.shake, 1.4, 1.0, 18, 12)
				end
			end
		end)

		-------------------------------------------------------------------------------------------------
		-- 1.18 ERUPTION
		beat(T.erupt, "erupt", function(late)
			st.erupted = true
			-- the column always asks Shared to fade for a near camera (it is camera-based, so it costs a far viewer
			-- nothing, and a bystander standing next to it is spared the black-out too)
			st.pillar = SH("pillar", f, g, { radius = st.pillarR, height = st.pillarH, localFade = true })
			if st.pillar then
				try(st.pillar, { "erupt" })
			end
			st.crawlers = tier == 1 and 2 or (tier == 2 and 1 or 0)
			for c = 1, 2 do
				st.crawlA[c] = rand(0, TAU)
			end
			st.nextCrawl = 0
			if late then
				return -- a late joiner gets the raging column, not the blast
			end
			local c = chest()
			sndOn(st.sndHost, {
				{ "Boom", 1.0, 0.6 }, { "Thunder", 1.0, 0.5 }, { "Cannon", 0.8, 0.5 }, { "Rise", 0.8, 0.8 }, { "HitHeavy", 0.7, 0.6 },
			})
			-- rings race out across the ground, staggered; the dome shockwave rides over them
			FX.ring(f, g + UP * 0.3, UP, 2, 60, CRIMSON, 0.9, { alpha = 0.3 })
			safe("dome", dome, st)
			gradeOn(st)
			if tier <= 2 then
				FX.ring(f, g + UP * 0.4, UP, 2, 40, CORE, 0.7, { alpha = 0.5 })
				task.delay(0.08, function()
					FX.ring(f, g + UP * 0.35, UP, 2, 45, EMBER, 0.75, { alpha = 0.45 })
				end)
				-- the vertical ring, facing the camera (scaled and thinned for a near lens)
				local sc, dd = ringScale(st, c)
				FX.ring(f, c, camFacing(c), 4 * sc, 30 * sc, CRIMSON, 0.45, { alpha = (dd < (B.NearRingFrom or 40)) and 0.8 or 0.5 })
				FX.glow(f, g + UP * 2, bloom(st, g, 14), CRIMSON, 0.45, { alpha = 0.35 })
				FX.light(f, g + UP * 4, CRIMSON, 8, 60, 1.2)
				FX.streaks(f, g + UP, { dir = UP, spread = 22, color = EMBER, color2 = CRIMSON, count = tier == 1 and 30 or 14, speed = { 80, 140 }, size = 0.6, life = 0.5 })
				FX.sparks(f, g + UP * 2, { color = EMBER, color2 = CRIMSON, count = tier == 1 and 26 or 12, speed = { 30, 70 }, size = 0.5, life = 0.9 })
				hurlRocks(st)
				flingPebbles(st)
				SH("cracks", f, g, 9, 18, CRIMSON, 2.4)
				-- lightning bursts off the foot of the column
				for _ = 1, tier == 1 and 2 or 1 do
					local a = rand(0, TAU)
					local p1 = g + UP * rand(1, 4) + Vector3.new(math.cos(a), 0, math.sin(a)) * (st.pillarR + 1)
					local p2 = groundAt(g + Vector3.new(math.cos(a), 0, math.sin(a)) * rand(12, 18) + UP * 2, g.Y)
					if clearOfLens((p1 + p2) / 2, 5) then
						bolt(f, p1, p2, { color = CRIMSON, core = BOLT_CORE, width = 0.18, segments = 5, jag = 0.3, life = 0.14, restrike = 2 })
					end
				end
			end
			if tier == 1 then
				dustRingSafe(f, g, 6, 12, 90, { s1 = 22 })
				dustRingSafe(f, g, 5, 6, 70, { s0 = 3, s1 = 14, color = SMOKE }) -- the dark smoke ring
				FX.rubble(f, g, { count = 20, radius = 6, up = { 30, 60 }, out = { 20, 45 } })
			elseif tier == 2 then
				FX.rubble(f, g, { count = 10, radius = 6, up = { 30, 55 }, out = { 20, 40 } })
			end
			if tier <= 2 then
				sndOn(st.sndHost, { { "Hum", 0.6, 0.6 } })
			end
			-- the camera
			if isLocal then
				safe("impact", ctx.impact, { tint = CRIMSON, tint2 = WHITE, flashAlpha = 0.2 })
				safe("vignette", ctx.vignette, 0.3, 1.0, CRIMSON)
				if not st.shotOn then
					st.shook = true
					safe("shake", ctx.shake, 1.4, 1.0, 18, 12) -- no shot running: the shake lands now
				end
			else
				local dd = camDist(g)
				local kk = 1 - dd / (GATE.Shake or 200)
				if kk > 0 then
					safe("shake", ctx.shake, 1.2 * kk, 0.8, 18)
					safe("flash", ctx.flash, CRIMSON, 0.12 * kk, 0.3)
				end
			end
		end, T.reveal)
		-- 1.40: the column reaches the sky - its crown
		beat(T.erupt + 0.22, "crown", function()
			safe("crown", crown, st)
			snd("Thunder", st.sndHost, 0.5, 0.4)
		end)
		-- 1.30 / 1.70: the dust cloud hangs round the column's foot (the caster's front stays open for the reveal shot)
		for i, dt in ipairs({ 0.12, 0.52 }) do
			beat(T.erupt + dt, "cloud", function()
				if tier == 1 and roomy() then
					dustRingSafe(f, g, i == 1 and 7 or 9, i == 1 and 10 or 8, 3, { s0 = 5, s1 = 13, life = { 1.1, 1.5 }, count = 1 }, isLocal and aim or nil)
				end
			end)
		end

		-------------------------------------------------------------------------------------------------
		-- 1.42 FORM: the server swapped the blade and the coat
		beat(T.form, "form", function()
			if tier > 2 then
				return
			end
			local info = st.char and safe("sword", ctx.sword, st.char)
			local mid = info and live(info.mid) and info.mid.WorldPosition or (chest() + st.aim * 2)
			FX.glow(f, mid, bloom(st, mid, 4), CRIMSON, 0.3, { alpha = 0.2 })
			local sc = ringScale(st, mid)
			FX.ring(f, mid, camFacing(mid), 1, 6 * sc, CRIMSON, 0.3, { alpha = 0.3 })
			SH("shards", f, mid, { count = 8, color = PAL.Steel, material = Enum.Material.Metal, size = 0.45, speed = { 18, 38 }, life = 0.9 })
			FX.sparks(f, mid, { color = EMBER, color2 = CRIMSON, count = 10, speed = { 10, 28 }, size = 0.35, life = 0.5 })
			sndOn(st.hrp or st.sndHost, { { "Shatter", 0.8, 0.8 }, { "Zap", 0.5, 1.2 }, { "Whoosh", 0.5, 0.8 } })
			-- the coat whips round him
			coatWhip(st, ctx.now() - st.t0)
			local c = chest()
			FX.ring(f, c - UP * 1.2, UP, 1.5, 7, CRIMSON, 0.35, { alpha = 0.35 })
		end)

		-------------------------------------------------------------------------------------------------
		-- 2.06 the reveal shot (caster)
		beat(T.revealShot[1], "revealShot", function()
			if isLocal then
				startRevealShot(st)
			end
		end)
		beat(T.revealShot[2], "revealBack", function()
			st.revealOn = false
			if isLocal then
				safe("shake", ctx.shake, 0.35, 0.45, 20)
			end
		end)
		-- 2.12: the coat tails flare back as the blast clears
		beat(T.reveal - 0.03, "flare", function()
			if st.char and tier <= 2 and (isLocal or st.dist < (MFX.CoatGate or 100)) then
				flareCoat(st.char, 50, 1.0) -- (+ the tails' own 12 deg: past ~60 the rigid tails read as planks)
			end
		end)

		-------------------------------------------------------------------------------------------------
		-- 2.15 REVEAL
		beat(T.reveal, "reveal", function()
			if st.pillar then
				if not try(st.pillar, { "dissolve" }, 0.6) then
					kill(st.pillar)
				end
				st.pillar = nil
			end
			dropTornado(st)
			st.crawlers = 0
			gradeOff(st, 0.9)
			sndOn(st.sndHost, { { "Shatter", 0.5, 0.6 }, { "Swell", 0.6, 1.4 }, { "Hum", 0.5, 1.2 } })
			FX.ring(f, g + UP * 0.3, UP, 4, 30, CRIMSON, 0.6, { alpha = 0.3 })
			if tier <= 2 then
				-- black feathers and ash off the breaking column, crimson embers rising
				for _, hgt in ipairs(tier == 1 and { 6, 18 } or { 8 }) do
					local p = g + UP * hgt
					if clearOfLens(p, 9) then
						SH("ash", f, p, { count = hgt == 6 and 60 or 26, radius = st.pillarR, life = 2.2, rise = 2 })
					end
				end
				local room = partCount(f) < 280 -- the governor: the dissolving column is still in the folder
				if room then
					SH("shards", f, g + UP * 10, { count = tier == 1 and 14 or 6, color = BLK, size = 0.5, speed = { 8, 20 }, life = 1.4 })
				end
				FX.sparks(f, g + UP * 4, { color = EMBER, color2 = CRIMSON, count = tier == 1 and 30 or 12, speed = { 10, 30 }, size = 0.4, life = 1.2, accel = Vector3.new(0, 4, 0), drag = 1 })
				-- the dust cloud blown flat outward: the reveal
				if tier == 1 then
					dustRingSafe(f, g, 5, room and 14 or 8, 70, { s0 = 3, s1 = 16, life = { 0.9, 1.4 } })
				end
				local c = chest()
				FX.glow(f, c - st.aim * 1.5, bloom(st, c, 6), CRIMSON, 0.5, { alpha = 0.45 })
				FX.arcs(f, c, 3.2, { outward = true, count = (tier == 1 and room) and 4 or 2, colors = { CRIMSON, EMBER }, width = 0.06, life = 0.12 })
				if st.char and camDist(c) < 60 then
					st.eyes = SH("eyes", st.char, { color = CRIMSON })
				end
				-- the scorched crater: a dark disc with a crimson rim that cools, embers and smoke wisps (gone by ~5)
				local sc = disc("BankaiCrater", BLK, PLASTIC, 18, g + UP * 0.04, f, 0.3)
				tw(sc, 3.2, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(sc, 3.3)
				local rim = disc("BankaiCraterRim", CRIMSON, NEON, 19.6, g + UP * 0.025, f, 0.35)
				tw(rim, 1.4, { Transparency = 1, Color = BLOOD }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				Debris:AddItem(rim, 1.5)
				local eh = FX.anchor(f, g + UP * 0.3, 3.4)
				eh.Size = Vector3.new(st.pillarR * 1.6, 0.2, st.pillarR * 1.6)
				st.aftEmbers = eh
				FX.emitter(eh, {
					Texture = TEX.star, Color = cs(EMBER, CRIMSON), Rate = tier == 1 and 12 or 6, Lifetime = NR(0.8, 1.4),
					Speed = NR(3, 8), SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Top,
					Acceleration = Vector3.new(0, 4, 0), Size = nsk({ { 0, 0.3 }, { 1, 0 } }), Brightness = 2,
					Rotation = NR(0, 360), RotSpeed = NR(-200, 200),
				})
				if tier == 1 then
					local sh = FX.anchor(f, g + UP * 0.3, 3.6)
					sh.Size = Vector3.new(st.pillarR, 0.2, st.pillarR)
					st.aftSmoke = sh
					FX.emitter(sh, {
						Texture = TEX.smoke, Color = cs(SMOKE), LightEmission = 0, LightInfluence = 0.5, Rate = 5,
						Lifetime = NR(1.4, 2), Speed = NR(2, 5), EmissionDirection = Enum.NormalId.Top,
						SpreadAngle = Vector2.new(15, 15), Size = nsk({ { 0, 2 }, { 1, 5 } }),
						Transparency = nsk({ { 0, 0.75 }, { 0.4, 0.65 }, { 1, 1 } }), Rotation = NR(0, 360), RotSpeed = NR(-20, 20),
					})
				end
			end
			if isLocal then
				safe("vignette", ctx.vignette, 0.22, 0.8, CRIMSON)
				if not st.revealOn then
					safe("shake", ctx.shake, 0.3, 0.4, 20)
				end
			end
		end)
		beat(T.reveal + 0.05, "tensa", function()
			if isLocal then
				safe("callout", ctx.callout, "Tensa")
			end
			if tier <= 2 then
				bladeGlint(st, CRIMSON)
			end
		end)
		beat(T.reveal + 0.12, "star", function()
			if tier <= 2 then
				starGlint(st, CRIMSON)
			end
		end)
		-- 2.58 / 2.68: the chiburi (BankaiReveal keys 1.40 / 1.50)
		beat(T.erupt + 1.40, "chiburiUp", function()
			if tier <= 2 and st.char then
				local tr = SH("bladeTrail", st.char, CRIMSON, BLK, 0.18, 0.24, { black = true })
				if tr then
					st.chiburiTrail = tr
				end
			end
		end)
		beat(T.erupt + 1.50, "chiburi", function()
			if tier <= 2 then
				chiburiSpray(st)
			end
		end)
		beat(T.mode + 0.1, "handover", function()
			-- the mode's own aura / glow / eyes have taken over
			kill(st.aura)
			st.aura = nil
			if st.glow and not try(st.glow, { "stop" }) then
				kill(st.glow)
			end
			st.glow = nil
			kill(st.eyes)
			st.eyes = nil
		end)
	end

	-- every Heartbeat, per running cast
	local function stepCast(st, e, dt)
		local char = st.char
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and (not char.Parent or not hum or hum.Health <= 0) then
			cancelCast(st)
			return
		end
		local T = st.T
		if e > T.mode + 2.2 then
			finishCast(st)
			return
		end
		-- the part governor: optional layers stop past Budget (340) parts in the cast folder
		if e >= st.nextPC then
			st.nextPC = e + 0.1
			st.pc = partCount(st.f)
		end
		local roomy = st.pc < (B.Budget or 340)
		-- the aura and the blade glow
		if not st.kaiDone then
			local k = math.clamp(e / 1.0, 0, 1)
			setAura(st, 30 + 60 * k)
			setGlow(st, 0.3 + 0.7 * k)
		elseif e > T.reveal and e < T.mode + 0.1 then
			local k = math.clamp((e - T.reveal) / (T.mode - T.reveal), 0, 1)
			setAura(st, 80 - 60 * k)
			setGlow(st, 1 - 0.75 * k)
		end
		-- the blade glow follows the blade onto Tensa Zangetsu once the server swaps it
		if st.glow and st.kaiDone and st.glowForm ~= "Bankai" and safe("form", ctx.form, char) == "Bankai" then
			swapGlow(st, true)
			setGlow(st, 1)
		end
		-- the gathering
		if e < T.erupt - 0.05 and st.tier <= 2 and roomy then
			if e >= st.nextStreak then
				st.nextStreak = e + 0.15
				streaksIn(st, st.kaiDone and CRIMSON or REI)
			end
			if e >= 0.3 and e >= st.nextArc then
				st.nextArc = e + (st.tier == 1 and 0.08 or 0.16)
				arcsRound(st, st.kaiDone)
			end
		end
		-- the tornado (then the ribbons racing up the column), the pebbles, the coat whip
		if st.tor and #st.tor > 0 and e < T.reveal then
			stepTornado(st, e, dt)
		end
		if st.pebbles and #st.pebbles > 0 and e < T.erupt then
			stepPebbles(st, e, dt)
		end
		stepWhip(st, e)
		-- the pillar rages
		if e >= T.erupt and e < T.reveal then
			if roomy then
				stepCrawl(st, e)
			end
			if st.tier == 1 and e >= st.nextAsh and roomy then
				st.nextAsh = e + 0.2
				local a = rand(0, TAU)
				local p = st.g + Vector3.new(math.cos(a), 0, math.sin(a)) * (st.pillarR + 0.3) + UP * rand(4, 32)
				if clearOfLens(p, 10) then
					SH("ash", st.f, p, { count = 8, radius = 1.5, life = 1.6 })
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	H.BankaiErupt = function(d)
		if type(d) ~= "table" then
			return
		end
		local st = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		local f = (st and live(st.f) and st.f) or ctx.castFolder("BankaiErupt", 3)
		local models = type(d.models) == "table" and d.models or {}
		if st and st.isLocal then
			safe("tally", ctx.tally, d.id, #models)
		end
		local list = {}
		for _, m in ipairs(models) do
			local tp = typeof(m) == "Instance" and m.Parent and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart"))
			if tp and tp:IsA("BasePart") then
				table.insert(list, { m = m, tp = tp, d = camDist(tp.Position) })
			end
		end
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		local full = 0
		for i, h in ipairs(list) do
			if i > 12 or h.d > REDUCED then
				break
			end
			local pos = h.tp.Position
			-- the first 2 bodies near the lens bloom full size, the rest small
			local big = h.d >= 30 or full < (B.FullBlooms or 2)
			if h.d < 30 and big then
				full += 1
			end
			FX.glow(f, pos, big and bloom(st, pos, 5) or 2, CRIMSON, 0.3, { alpha = 0.35 })
			FX.sparks(f, pos, { color = EMBER, color2 = CRIMSON, count = 10, speed = { 15, 35 }, size = 0.35, life = 0.5 })
			local tr = FX.trail(h.tp, cs(EMBER, CRIMSON), 1.4, 0.45, { tail = 0, brightness = 2.2 })
			if tr then
				Debris:AddItem(tr, 1.6)
				Debris:AddItem(tr.Attachment0, 1.6)
				Debris:AddItem(tr.Attachment1, 1.6)
			end
			-- reiatsu flames bursting off the body, a crimson fork across it
			if i <= 6 and h.d < FULL and clearOfLens(pos, 8) then
				SH("reiatsuFlame", f, pos, { black = true, color2 = CRIMSON, count = 6, height = 3, size = 0.9, life = 0.45 })
				SH("bodyArc", f, h.m, CRIMSON, 0.07)
			end
			if i == 1 then
				sndOn(h.tp, { { "HitHeavy", 0.7, 0.8 }, { "Hit2", 0.5, 0.9 } })
			end
		end
	end

	H.BankaiCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local st = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if st then
			cancelCast(st)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- §9.M THE MODE: Tensa Zangetsu on every character with BankaiUntil > now
	local function newModeFolder(char)
		local f = Instance.new("Folder")
		f.Name = "BankaiMode_" .. char.Name
		f.Parent = ctx.Folder or workspace
		return f
	end
	local function buildGlow(m, char)
		if m.glow then
			if not try(m.glow, { "stop" }) then
				kill(m.glow)
			end
		end
		m.glow = SH("bladeGlow", char, { black = true, color2 = CRIMSON, light = false })
		local info = safe("sword", ctx.sword, char)
		m.glowBlade = info and info.blade
		try(m.glow, { "set" }, MFX.BladeK or 0.25)
	end
	-- the blade bleeds: crimson drops falling off Tensa Zangetsu (the glow's own black wisps rise off it)
	local function buildBleed(m, char)
		if m.bleed then
			kill(m.bleed)
			m.bleed = nil
		end
		local info = safe("sword", ctx.sword, char)
		local blade = info and info.form == "Bankai" and info.blade
		m.bleedBlade = blade
		if live(blade) then
			m.bleed = FX.emitter(blade, {
				Texture = TEX.glow, Color = cs(CRIMSON, BLOOD), LightEmission = 0.5, Brightness = 2,
				Size = nsk({ { 0, 0.16 }, { 0.6, 0.12 }, { 1, 0.04 } }), Transparency = nsk({ { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } }),
				Lifetime = NR(0.35, 0.6), Speed = NR(0.2, 0.8), SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -24, 0), Drag = 0.5, Rotation = NR(0, 360),
			})
			m.bleed.Name = "BankaiBleed"
		end
	end
	-- the coat tails trail flame: crimson licks off every tail, black smoke-flame off the back tail
	local function buildTails(m, char)
		for _, it in ipairs(m.tailEms or {}) do
			kill(it.e)
		end
		m.tailEms = {}
		local coat = char:FindFirstChild("ZangetsuCoat")
		m.tailCoat = coat
		if not coat then
			return
		end
		local lick = Enum.ParticleOrientation.VelocityParallel
		for _, name in ipairs(TAIL_NAMES) do
			local tp = coat:FindFirstChild(name)
			if tp and tp:IsA("BasePart") then
				local em = FX.emitter(tp, {
					Texture = FIRE, Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, EMBER), ColorSequenceKeypoint.new(0.4, CRIMSON), ColorSequenceKeypoint.new(1, BLOOD),
					}),
					LightEmission = 0.8, Brightness = 1.8, Size = nsk({ { 0, 0.3 }, { 0.4, 0.55 }, { 1, 0 } }),
					Transparency = nsk({ { 0, 0.5 }, { 0.25, 0.2 }, { 1, 1 } }), Lifetime = NR(0.22, 0.4), Speed = NR(0.5, 2),
					SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, 7, 0), Drag = 1, Orientation = lick,
					Squash = nsk({ { 0, -0.4 }, { 1, -0.1 } }), Rotation = NR(-15, 15), ZOffset = 0.2,
				})
				em.Name = "BankaiTailFlame"
				table.insert(m.tailEms, { e = em, dark = false })
				if name == "TailBack" then
					local em2 = FX.emitter(tp, {
						Texture = FIRE, Color = cs(SMOKE, BLK), LightEmission = 0, LightInfluence = 0.3,
						Size = nsk({ { 0, 0.45 }, { 0.4, 0.85 }, { 1, 0.4 } }), Transparency = nsk({ { 0, 0.55 }, { 0.3, 0.35 }, { 1, 1 } }),
						Lifetime = NR(0.3, 0.5), Speed = NR(0.5, 2), SpreadAngle = Vector2.new(30, 30),
						Acceleration = Vector3.new(0, 8, 0), Drag = 1, Orientation = lick, Squash = nsk({ { 0, -0.4 }, { 1, -0.1 } }),
						Rotation = NR(-15, 15),
					})
					em2.Name = "BankaiTailSmoke"
					table.insert(m.tailEms, { e = em2, dark = true })
				end
			end
		end
	end
	local function dropFlair(m)
		for _, it in ipairs(m.tailEms or {}) do
			pcall(function()
				it.e.Enabled = false
			end)
			Debris:AddItem(it.e, 0.6)
		end
		m.tailEms = nil
		m.tailCoat = nil
		if m.bleed then
			pcall(function()
				m.bleed.Enabled = false
			end)
			Debris:AddItem(m.bleed, 0.7)
		end
		m.bleed, m.bleedBlade = nil, nil
		m.flair = false
	end
	local function clearMode(m)
		kill(m.aura)
		if m.glow and not try(m.glow, { "stop" }) then
			kill(m.glow)
		end
		kill(m.eyes)
		kill(m.highlight)
		dropFlair(m)
		if live(m.folder) then
			Debris:AddItem(m.folder, 1.5)
		end
		m.aura, m.glow, m.eyes, m.highlight, m.folder, m.glowBlade = nil, nil, nil, nil, nil, nil
		m.built = false
	end
	local function ignite(m, char, hrp, isLocal)
		local p = hrp.Position
		local fp = groundAt(p, p.Y - 3.19)
		local f = m.folder
		FX.ring(f, fp + UP * 0.2, UP, 2, 18, CRIMSON, 0.5, { alpha = 0.25 })
		FX.ring(f, p, camFacing(p), 1, 8 * math.clamp(camDist(p) / 30, 0.6, 1), CRIMSON, 0.35, { alpha = 0.45 })
		if clearOfLens(fp + UP, 8) then
			SH("reiatsuFlame", f, fp, { black = true, color2 = CRIMSON, count = 14, height = 5, size = 1.2, life = 0.6 })
			SH("reiatsuFlame", f, fp, { black = true, color2 = CRIMSON, count = 10, height = 8, size = 0.9, life = 0.7, spread = 6 })
		end
		FX.sparks(f, p, { color = EMBER, color2 = CRIMSON, count = 16, speed = { 15, 35 }, size = 0.35, life = 0.6 })
		FX.arcs(f, p, 4, { outward = true, count = 3, colors = { CRIMSON, EMBER }, width = 0.06, life = 0.12 })
		sndOn(hrp, { { "Crackle", 0.5, 0.9 }, { "Sizzle", 0.35, 1 } })
		if isLocal then
			safe("vignette", ctx.vignette, 0.2, 0.8, CRIMSON)
		end
	end
	-- a burning footprint: a black flame lick, 3 crimson embers, a dark scorch with a crimson rim (rim 0.45 s, scorch 1.4 s)
	local function footfall(m, foot)
		local f = m.folder
		local hit = FX.groundHit and FX.groundHit(foot.Position, 3)
		if not hit then
			return
		end
		local p = hit.Position
		SH("reiatsuFlame", f, p, { black = true, color2 = CRIMSON, count = 4, height = 1.8, size = 0.6, life = 0.4 })
		FX.sparks(f, p + UP * 0.2, { color = EMBER, color2 = CRIMSON, count = 3, speed = { 4, 10 }, size = 0.25, life = 0.4, dir = UP, spread = 50 })
		local rim = disc("BankaiScorchRim", CRIMSON, NEON, 2.3, p + UP * 0.02, f, 0.2)
		tw(rim, 0.45, { Transparency = 1, Color = BLOOD })
		Debris:AddItem(rim, 0.5)
		local sc = disc("BankaiScorch", BLK, PLASTIC, 1.9, p + UP * 0.035, f, 0.25)
		tw(sc, 1.4, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(sc, 1.5)
	end

	-- ctx.players is an Edit-mode harness hook (the scaffold never sets it): a list of stand-in players
	local function playerList()
		if type(ctx.players) == "function" then
			local ok, l = pcall(ctx.players)
			if ok and type(l) == "table" then
				return l
			end
		end
		return Players:GetPlayers()
	end
	local function updateMode(clock, dt)
		local t = ctx.now()
		local seen = {}
		for _, p in ipairs(playerList()) do
			local char = p.Character
			local untilT = char and char:GetAttribute("BankaiUntil")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 and type(untilT) == "number" and untilT > t and endedUntil[char] ~= untilT then
				seen[char] = true
				local isLocal = p == ctx.player
				local dist = isLocal and 0 or camDist(hrp.Position)
				local m = modeFx[char]
				if not m then
					m = {
						player = p, ghosts = {}, nextGhost = 0, lastPrint = 0, nextArc = 0, phase = rand(0, TAU),
						fresh = untilT - t > (MODE.Time or 15) - (MFX.IgniteWindow or 1.5),
					}
					modeFx[char] = m
					-- a new mode: the coat must be visible again (an earlier exit may have left a modifier on it)
					local info = safe("sword", ctx.sword, char)
					if info and info.coat then
						for _, d in ipairs(info.coat:GetDescendants()) do
							if d:IsA("BasePart") then
								d.LocalTransparencyModifier = 0
							end
						end
					end
				end
				m.untilT = untilT
				if not m.built and dist < 220 then
					m.built = true
					m.folder = newModeFolder(char)
					m.aura = SH("aura", char, { black = true, color2 = CRIMSON, rate = MFX.AuraStand or 14 })
					buildGlow(m, char)
					if m.fresh and dist < 160 then
						m.fresh = false
						safe("ignite", ignite, m, char, hrp, isLocal)
						local cc = coats[char]
						if (isLocal or dist < (MFX.CoatGate or 100)) and not (cc and cc.flareT) then
							flareCoat(char, 40, 0.8) -- (never on top of the reveal's own flare)
						end
					end
				elseif m.built and dist > 280 then
					clearMode(m)
				end
				if m.built then
					local left = untilT - t
					local late = left < (MFX.LateAt or 3)
					local ut = char:FindFirstChild("UpperTorso")
					local hidden = ut and ut.LocalTransparencyModifier > 0.9 -- vanished (Shunpo) or first person
					local vel = hrp.AssemblyLinearVelocity * FLAT
					local speed = vel.Magnitude
					local run = math.clamp((speed - 2) / ((MFX.RunSpeed or 18) - 2), 0, 1)
					local sputter = late and not ((math.sin(clock * 21) > 0) and rng:NextNumber() > 0.25)
					-- aura: calm standing, roaring at a run; the last seconds it sputters
					local rate = (MFX.AuraStand or 14) + ((MFX.AuraRun or 44) - (MFX.AuraStand or 14)) * run
					if late then
						rate = sputter and 0 or 30
					end
					if hidden then
						rate = 0
					end
					try(m.aura, { "set" }, rate)
					-- the blade: re-glued if the sword was rebuilt; flickers at the end
					local info = safe("sword", ctx.sword, char)
					if info and info.blade ~= m.glowBlade and info.form == "Bankai" then
						buildGlow(m, char)
					end
					local k = MFX.BladeK or 0.35
					if late and rng:NextNumber() < 0.35 then
						k = 0.04
					end
					if hidden then
						k = 0
					end
					try(m.glow, { "set" }, k)
					-- the flair layers (<= FlairGate): flaming coat tails, the bleeding blade
					local wantFlair = isLocal or dist < (MFX.FlairGate or 120)
					if wantFlair and not m.flair then
						m.flair = true
						buildTails(m, char)
						buildBleed(m, char)
					elseif not wantFlair and m.flair and dist > (MFX.FlairGate or 120) + 20 then
						dropFlair(m)
					end
					if m.flair then
						if m.tailCoat ~= char:FindFirstChild("ZangetsuCoat") then
							buildTails(m, char)
						end
						if info and info.form == "Bankai" and info.blade ~= m.bleedBlade then
							buildBleed(m, char)
						end
						local off = hidden or sputter
						local trail = UP * 7 - vel * 0.6 -- the flames stream back off the tails at a run
						for _, it in ipairs(m.tailEms or {}) do
							if it.e.Parent then
								it.e.Rate = off and 0 or (it.dark and (4 + 12 * run) or (6 + 20 * run))
								it.e.Acceleration = trail
							end
						end
						if m.bleed and m.bleed.Parent then
							m.bleed.Rate = off and 0 or (9 + 8 * run)
						end
					end
					-- the coat tails stream back at a run and lift in the aura's updraft standing
					if (isLocal or dist < (MFX.CoatGate or 100)) and not hidden then
						local c = coatCtl(char)
						if c then
							c.back = 2 + 2.5 * math.sin(clock * 2.2 + m.phase) + run * (30 + 5 * math.sin(clock * 11 + m.phase))
							c.side = 1.5 + run * (5 + 3 * math.sin(clock * 7.3 + m.phase))
							c.streamAt = clock
						end
					end
					-- the crimson rim (the engine draws at most 31 Highlights: only near ones)
					local wantHl = (isLocal or dist < (MFX.HighlightGate or 140)) and not hidden
					if wantHl and not live(m.highlight) then
						local hl = Instance.new("Highlight")
						hl.Name = "BankaiRim"
						hl.Adornee = char
						hl.DepthMode = Enum.HighlightDepthMode.Occluded
						hl.FillTransparency = 1
						hl.OutlineColor = CRIMSON
						hl.OutlineTransparency = 0.35
						hl.Parent = m.folder
						m.highlight = hl
					elseif not wantHl and m.highlight then
						kill(m.highlight)
						m.highlight = nil
					end
					if m.highlight then
						m.highlight.OutlineTransparency = late and (0.35 + 0.5 * rng:NextNumber()) or 0.35
					end
					-- crimson eyes dragging long trails, near only (never in first person: the head is see-through)
					local head = char:FindFirstChild("Head")
					local wantEyes = dist < (MFX.EyeGate or 60) and head and head.LocalTransparencyModifier < 0.5 and not hidden
					if wantEyes and not m.eyes then
						m.eyes = SH("eyes", char, { color = CRIMSON })
						local irises = type(m.eyes) == "table" and m.eyes.irises
						if type(irises) == "table" and head then
							local kk = head.Size.Y / 1.2
							for _, iris in ipairs(irises) do
								if live(iris) then
									local tr = FX.trail(iris, cs(CRIMSON, BLOOD), 0.1 * kk, 0.45, { tail = 0, alpha = 0.1, brightness = 2.5 })
									if tr then
										tr.Name = "BankaiEyeTrail"
									end
								end
							end
						end
					elseif not wantEyes and m.eyes then
						kill(m.eyes)
						m.eyes = nil
					end
					try(m.eyes, { "keep" }) -- Shared's character handles die 8 s after their last :set / :keep
					-- crimson arcs crawling over the body
					if dist < (MFX.ArcGate or 80) and not hidden and clock >= m.nextArc then
						m.nextArc = clock + (late and 0.15 or rand(0.3, 0.5))
						SH("bodyArc", m.folder, char, rng:NextNumber() < 0.7 and CRIMSON or EMBER, 0.05)
					end
					-- afterimages at a run: black and crimson in turn, at most 4 alive
					if speed > (MFX.RunSpeed or 18) and (isLocal or dist < (MFX.GhostGate or 120)) and not hidden and clock >= m.nextGhost then
						local alive = {}
						for _, gh in ipairs(m.ghosts) do
							if live(gh.f) and clock < gh.t then
								table.insert(alive, gh)
							end
						end
						m.ghosts = alive
						if #alive < (MFX.GhostMax or 4) then
							m.nextGhost = clock + (MFX.GhostEvery or 0.22)
							m.flip = not m.flip
							local life = MFX.GhostLife or 0.3
							local gh
							if m.flip then
								gh = SH("ghostAt", char, hrp.CFrame, BLK, MFX.GhostAlpha or 0.55, life, { black = true })
							else
								gh = SH("ghost", char, CRIMSON, MFX.GhostAlpha or 0.55, life)
							end
							if typeof(gh) == "Instance" then
								table.insert(m.ghosts, { f = gh, t = clock + life + 0.1 })
							end
						end
					end
					-- burning footprints: each time the lower foot swaps at a run
					if speed > 12 and dist < (MFX.FootGate or 100) and not hidden and hum.FloorMaterial ~= Enum.Material.Air then
						local lf, rf = char:FindFirstChild("LeftFoot"), char:FindFirstChild("RightFoot")
						if lf and rf then
							local dy = lf.Position.Y - rf.Position.Y
							local low = (dy < -0.12) and lf or ((dy > 0.12) and rf or nil)
							local gap = clock - m.lastPrint
							if ((low and low ~= m.lowFoot) or gap > 0.45) and gap > 0.14 then
								m.lastPrint = clock
								safe("footfall", footfall, m, low or ((dy < 0) and lf or rf))
							end
							if low then
								m.lowFoot = low
							end
						end
					end
				end
			end
		end
		for char, m in pairs(modeFx) do
			if not seen[char] then
				clearMode(m)
				modeFx[char] = nil
			end
		end
		for char in pairs(endedUntil) do
			if not char.Parent then
				endedUntil[char] = nil
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- BankaiEnd: "expired" plays the exit on that character; anything else just ends the visuals (the mode loop
	-- clears them the moment the attribute goes)
	local function coatParts(char)
		local info = safe("sword", ctx.sword, char)
		local coat = info and info.coat
		if not coat then
			coat = char:FindFirstChild("ZangetsuCoat")
		end
		local list = {}
		if coat then
			for _, d in ipairs(coat:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 0.95 then
					table.insert(list, d)
				end
			end
		end
		table.sort(list, function(a, b)
			return a.Position.Y < b.Position.Y
		end)
		return list
	end
	local function restoreCoat(x)
		for _, p in ipairs(x.coat or {}) do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end
		x.coat = {}
	end
	local function dropCracks(x)
		for _, c in ipairs(x.cracks or {}) do
			if live(c.part) then
				c.part:Destroy()
			end
		end
		x.cracks = {}
	end
	local function endExit(char)
		local x = exits[char]
		if not x then
			return
		end
		exits[char] = nil
		x.done = true
		for _, em in ipairs(x.emitters or {}) do
			pcall(function()
				em.Rate = 0
			end)
			Debris:AddItem(em, 0.8)
		end
		if x.shikaiGlow and not try(x.shikaiGlow, { "stop" }) then
			kill(x.shikaiGlow)
		end
		dropCracks(x)
		restoreCoat(x)
	end
	-- crimson cracks opening along the black blade before it shatters (they ride the blade every frame)
	local function crackBlade(x, char)
		local info = safe("sword", ctx.sword, char)
		local blade = info and info.form == "Bankai" and info.blade
		if not live(blade) then
			return
		end
		x.crackBlade = blade
		x.cracks = {}
		local sz = blade.Size
		for i = 1, 6 do
			local off = CFrame.new(0, rand(-0.45, 0.45) * sz.Y, rand(-0.2, 0.25) * sz.Z) * CFrame.Angles(rand(-0.9, 0.9), 0, 0)
			table.insert(x.cracks, { at = 0.1 + (i - 1) * 0.05, off = off, size = Vector3.new(sz.X + 0.04, 0.05, sz.Z * rand(0.45, 0.9)) })
		end
	end
	local function stepCracks(x, e)
		if not x.cracks or #x.cracks == 0 then
			return
		end
		local blade = x.crackBlade
		if not live(blade) or e >= x.swapAt then
			dropCracks(x)
			return
		end
		for _, c in ipairs(x.cracks) do
			if e >= c.at then
				if not c.part then
					c.part = stillPart("BankaiCrack", CRIMSON, NEON, c.size, blade.CFrame * c.off, x.f, 0)
				end
				if live(c.part) then
					c.part.CFrame = blade.CFrame * c.off
					c.part.Transparency = rand(0, 0.35)
				end
			end
		end
	end

	H.BankaiEnd = function(d)
		if type(d) ~= "table" then
			return
		end
		local char, p = ctx.charOf(d.userId)
		if typeof(d.char) == "Instance" then
			char = d.char -- Core adds the mode's own character
		end
		if not char then
			return
		end
		local m = modeFx[char]
		if m then
			clearMode(m)
			modeFx[char] = nil
		end
		endedUntil[char] = char:GetAttribute("BankaiUntil")
		endExit(char)
		if d.why ~= "expired" then
			releaseCoat(char)
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local isLocal = p == ctx.player
		if not hrp then
			return
		end
		local dist = isLocal and 0 or camDist(hrp.Position)
		if dist > REDUCED then
			return
		end
		local e = ctx.now() - (d.t0 or ctx.now())
		if e > 1.2 then
			return
		end
		local burn = MFX.ExitBurn or 0.45
		local swapAt = tonumber(d.formDelay) or (CFG.Sword and CFG.Sword.ExitFormDelay) or 0.45
		local f = ctx.castFolder("BankaiExit", 4)
		local x = { t0 = d.t0 or ctx.now(), char = char, f = f, coat = {}, emitters = {}, burn = burn, swapAt = swapAt, isLocal = isLocal, cracks = {} }
		exits[char] = x
		if isLocal then
			safe("root", ctx.root, MODE.ExitRoot or 0.5)
			safe("vignette", ctx.vignette, 0.16, 0.7, CRIMSON)
		end
		if ctx.Clips and ctx.Clips.BankaiExit then
			safe("playClip", ctx.playClip, char, ctx.Clips.BankaiExit, math.max(e, 0))
		end
		local ut = char:FindFirstChild("UpperTorso")
		local cpos = ut and ut.Position or hrp.Position
		local fp = groundAt(hrp.Position, hrp.Position.Y - 3.19)
		-- 0.00: the aura implodes - a ring collapsing onto his feet, streaks sucked into his chest
		if e < 0.2 then
			FX.ring(f, fp + UP * 0.2, UP, 12, 1.5, CRIMSON, 0.4, { ease = "in", alpha = 0.3 })
			if dist < FULL then
				FX.streaks(f, cpos, { inward = math.clamp(camDist(cpos) - 3, 2.5, 6), color = CRIMSON, color2 = EMBER, count = 14, life = 0.3, size = 0.35 })
			end
			sndOn(hrp, { { "Whoosh", 0.4, 0.6 } })
		end
		-- 0.00: the coat burns away from the hem up, embers along it, black ash off it
		if e < burn then
			local parts = coatParts(char)
			x.coat = parts
			local n = #parts
			for i, part in ipairs(parts) do
				local at = (i - 1) / math.max(n, 1) * burn * 0.8
				task.delay(math.max(at - e, 0), function()
					if x.done or not part.Parent then
						return
					end
					local v = Instance.new("NumberValue")
					v.Value = part.LocalTransparencyModifier
					v.Changed:Connect(function(val)
						if not x.done and part.Parent then
							part.LocalTransparencyModifier = val
						end
					end)
					TweenService:Create(v, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 }):Play()
					Debris:AddItem(v, 0.3)
				end)
				if i <= 5 and dist < FULL then
					local em = FX.emitter(part, {
						Texture = TEX.star, Color = cs(EMBER, CRIMSON), Rate = 26, Lifetime = NR(0.3, 0.6), Speed = NR(2, 5),
						SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 5, 0), Size = nsk({ { 0, 0.28 }, { 1, 0 } }),
						Brightness = 2, Rotation = NR(0, 360), RotSpeed = NR(-200, 200),
					})
					table.insert(x.emitters, em)
				end
			end
			task.delay(math.max(burn - e, 0), function()
				for _, em in ipairs(x.emitters) do
					pcall(function()
						em.Rate = 0
					end)
					Debris:AddItem(em, 0.8)
				end
				x.emitters = {}
			end)
			if dist < FULL then
				SH("ash", f, cpos - UP * 0.5, { count = 20, radius = 1.5, life = 1.2, rise = 3 })
			end
			-- black flames off the blade, a crimson flash ring; the blade starts to crack
			local info = safe("sword", ctx.sword, char)
			local mid = info and live(info.mid) and info.mid.WorldPosition or cpos
			if clearOfLens(mid, 6) then
				SH("reiatsuFlame", f, mid, { black = true, color2 = CRIMSON, count = 14, height = 3.5, size = 1, life = 0.5 })
			end
			FX.ring(f, cpos, camFacing(cpos), 1, 8 * math.clamp(camDist(cpos) / 30, 0.6, 1), CRIMSON, 0.35, { alpha = 0.3 })
			FX.glow(f, cpos, bloom(nil, cpos, 4), CRIMSON, 0.3, { alpha = 0.35 })
			sndOn(hrp, { { "Sizzle", 0.5, 0.9 }, { "Crackle", 0.3, 0.7 } })
			if dist < FULL then
				crackBlade(x, char)
			end
		end
		-- 0.05 / 0.30: black wisps rising off him as the Bankai leaves his body
		for _, at in ipairs({ 0.05, 0.3 }) do
			if e < at + 0.05 and dist < FULL then
				task.delay(math.max(at - e, 0), function()
					if x.done or not char.Parent then
						return
					end
					local u = char:FindFirstChild("UpperTorso")
					local c = u and u.Position or hrp.Position
					if clearOfLens(c, 5) then
						SH("ash", f, c, { count = 22, radius = 1.4, life = 1.4, rise = 6 })
					end
				end)
			end
		end
		-- 0.45: the black blade shatters and the cleaver reforms in a blue-white flash
		task.delay(math.max(swapAt - e, 0), function()
			if x.done or not char.Parent then
				return
			end
			dropCracks(x)
			local info = safe("sword", ctx.sword, char)
			local mid = info and live(info.mid) and info.mid.WorldPosition or hrp.Position
			if dist < FULL then
				SH("shards", f, mid, { count = 14, color = TENSA, material = PLASTIC, size = 0.38, speed = { 14, 30 }, life = 0.9 })
				FX.sparks(f, mid, { color = EMBER, color2 = CRIMSON, count = 10, speed = { 12, 26 }, size = 0.3, life = 0.45 })
			end
			FX.glow(f, mid, bloom(nil, mid, 3), CORE, 0.3, { alpha = 0.3 })
			FX.ring(f, mid, camFacing(mid), 1, 6 * math.clamp(camDist(mid) / 30, 0.6, 1), FROST, 0.3, { alpha = 0.3 })
			FX.sparks(f, mid, { color = FROST, color2 = CORE, count = 14, speed = { 10, 25 }, size = 0.35, life = 0.5 })
			sndOn(hrp, { { "Shatter", 0.5, 1.3 }, { "Swell", 0.4, 1.8 } })
			if isLocal then
				safe("shake", ctx.shake, 0.25, 0.3, 24)
			end
		end)
		-- the coat's modifier is handed back once the server has hidden it (or after 3 s regardless)
		task.delay(3, function()
			if exits[char] == x then
				endExit(char)
			end
		end)
	end

	-- the exit's per-frame part: the blade cracks ride the blade; hand the coat back once hidden; a brief blue-white
	-- glow once the cleaver is back
	local function stepExits(clock)
		local t = ctx.now()
		for char, x in pairs(exits) do
			if not char.Parent then
				endExit(char)
			else
				local e = t - x.t0
				stepCracks(x, e)
				if #x.coat > 0 and e > x.burn + 0.1 then
					local allHidden = true
					for _, p in ipairs(x.coat) do
						if p.Parent and p.Transparency < 0.99 then
							allHidden = false
						end
					end
					if allHidden then
						restoreCoat(x)
					end
				end
				if not x.shikaiGlow and not x.glowTried and e >= x.swapAt and safe("form", ctx.form, char) == "Shikai" then
					x.glowTried = true
					x.shikaiGlow = SH("bladeGlow", char, { color = CORE, color2 = REI, light = false })
					try(x.shikaiGlow, { "set" }, 0.6)
					local h = x.shikaiGlow
					task.delay(0.6, function()
						if x.shikaiGlow == h then
							if not try(h, { "stop" }) then
								kill(h)
							end
							x.shikaiGlow = nil
						end
					end)
				end
				if e > 2.5 and #x.coat == 0 and not x.shikaiGlow then
					exits[char] = nil
					x.done = true
					dropCracks(x)
				end
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	H.__update = function(clock, dt)
		local now = ctx.now()
		for _, st in pairs(casts) do
			if not st.ended then
				local ok, err = pcall(stepCast, st, now - st.t0, dt or 0)
				if not ok then
					warnOnce("stepCast", err)
					cancelCast(st)
				end
			end
		end
		local ok, err = pcall(updateMode, clock or os.clock(), dt or 0)
		if not ok then
			warnOnce("updateMode", err)
		end
		ok, err = pcall(stepExits, clock or os.clock())
		if not ok then
			warnOnce("stepExits", err)
		end
		ok, err = pcall(stepCoats, os.clock())
		if not ok then
			warnOnce("stepCoats", err)
		end
	end

	-- the local character died / the kit was unequipped: stop the local caster's cast, shot, root and mode visuals
	H.__reset = function()
		local uid = ctx.player and ctx.player.UserId
		for _, st in pairs(casts) do
			if st.userId == uid then
				cancelCast(st)
			end
		end
		local char = ctx.player and ctx.player.Character
		for c, m in pairs(modeFx) do
			if c == char or not c.Parent then
				clearMode(m)
				modeFx[c] = nil
			end
		end
		for c in pairs(exits) do
			if c == char or not c.Parent then
				endExit(c)
			end
		end
		for c in pairs(coats) do
			if c == char or not c.Parent then
				releaseCoat(c)
			end
		end
	end

	return H
end
