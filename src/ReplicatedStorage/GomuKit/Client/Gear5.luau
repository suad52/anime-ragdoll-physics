--!nocheck
-- GomuKit.Client.Gear5 (owner gear5): G - GEAR FIFTH (the ultimate, CONTRACT §8.5), BAJRANG GUN (G inside the mode)
-- and the mode's look on EVERY character whose Gear5Until is in the future (local and remote, distance-gated).
-- Broadcast kinds: Gear5Cast, Gear5Burst, Gear5On, Gear5End, BajrangCast, BajrangImpact, BajrangCancel.
-- CAST TEXT: the ONLY Gomu module that calls ctx.callout - "Drums" (0), "Laugh" (LaughAt), "Bajrang" (0) - and only for
-- the local caster. The "HA HA HA" comic letters round his head are the ult's in-world flair (everyone in range).
-- Awakening (Config.Gear5): 0 the drums begin (callout, an orbit shot <= ShotEnd 1.15 s, Gear5_Awaken); every DrumAt a
--   HitHeavy thump at pitch .55, a lavender pulse ring off his chest, a screen thump; BurstAt - .12 the inhale; BurstAt
--   a white flash, a white shock dome, clouds bursting out, hair + clothes turn white (the look starts here and the
--   Gear5Until attribute takes over at ModeAt); LaughAt the laugh; ModeAt the mode (a boing).
-- The mode look (__update): white hair (hair accessories' textures cleared, Color Nika, SurfaceAppearance parked), white
--   clothes (Shirt / Pants parked, torso + legs Nika), a cartoon outline (Highlight), S.sunAura (FX.aura fallback) + a
--   sun light, a cloud scarf round the shoulders, the idle bounce (Clips.Gear5_Bounce), a boing on every landing,
--   whoosh trails on every limb when fast. Every change is client-local and restored exactly on Gear5End / expiry.
-- Bajrang (Config.Bajrang): 0 callout + the hop (local ctx.move up, then ctx.float) + Gear5_Bajrang; RiseAt his right arm
--   shoots up into the sky (S.stretchArm, keep) while clouds gather above the target; FormAt a titanic white fist
--   (S.fistModel; a local fallback model) swells out of the cloud bank with a forearm into the clouds and a shadow on the
--   ground; DropAt -> ImpactAt it falls (cubic ease in) with whoosh streaks and a collapsing wind ring; ImpactAt the
--   biggest hit in the game: flash, three shock rings, a flash + dust dome, debris, a sun flare, a glowing crater.
-- S.fistModel's knuckles face the pivot's LookVector (-Z) and its pivot is the palm (checked against Shared).
return function(ctx)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")

	local H = {}
	local function num(v, d)
		return type(v) == "number" and v or d
	end
	local CFG = ctx.CFG or {}
	local PAL = ctx.PAL or CFG.Palette or {}
	local FX = ctx.FX or {}
	local S = ctx.S or {}
	local G5, BJ = CFG.Gear5 or {}, CFG.Bajrang or {}
	local PASSIVE = CFG.Passive or {}
	local C = Color3.fromRGB
	local UP = Vector3.yAxis
	local TAU = math.pi * 2
	local WHITE = Color3.new(1, 1, 1)
	local NIKA = PAL.Nika or C(252, 252, 255)
	local CLOUD = PAL.Cloud or C(236, 240, 255)
	local SUN = PAL.Sun or C(255, 228, 140)
	local SUNHOT = PAL.SunHot or C(255, 190, 70)
	local TOON = PAL.Toon or C(40, 30, 60)
	local LAV = PAL.Lavender or C(214, 196, 255)
	local DUST = PAL.Dust or C(150, 140, 125)
	local SHADOW = PAL.Gear5Shadow or C(18, 14, 30)
	local CRATER = PAL.Gear5Crater or SUNHOT
	local SMOOTH, NEON = Enum.Material.SmoothPlastic, Enum.Material.Neon
	local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local FULL, LITE = num(G5.FullDist, 160), num(G5.LiteDist, 260)

	---------------------------------------------------------------------------------------------------
	-- helpers
	local warned = {}
	local function safe(tag, fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, a, b, c = pcall(fn, ...)
		if not ok then
			local t = os.clock()
			if not warned[tag] or t - warned[tag] > 5 then
				warned[tag] = t
				warn("[Gomu.Gear5] " .. tostring(tag) .. ": " .. tostring(a))
			end
			return nil
		end
		return a, b, c
	end
	local function SH(name, ...)
		return safe("S." .. name, S[name], ...)
	end
	local function snd(name, parent, vol, speed)
		if typeof(parent) == "Instance" and parent.Parent then
			safe("sound", ctx.sound, name, parent, vol, speed)
		end
	end
	local function sndAt(name, pos, vol, speed)
		if typeof(pos) == "Vector3" then
			safe("soundAt", ctx.soundAt, name, pos, vol, speed)
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
			for _, k in ipairs({ "stop", "destroy", "Destroy" }) do
				if type(h[k]) == "function" then
					pcall(h[k], h)
					return
				end
			end
		end
	end
	local function live(f)
		return typeof(f) == "Instance" and f.Parent ~= nil
	end
	local function mk(parent, shape, size, color, material, alpha, cf, name)
		local p = Instance.new("Part")
		p.Name = name or "Gear5FX"
		p.Shape = shape or BALL
		p.Material = material or SMOOTH
		p.Color = color or WHITE
		p.Transparency = alpha or 0
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = size or Vector3.one
		p.CFrame = cf or CFrame.new()
		p.Parent = parent
		return p
	end
	local function tw(inst, t, props, style, dir)
		local ok, tr = pcall(function()
			return TweenService:Create(inst, TweenInfo.new(math.max(t, 0.01), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		end)
		if ok and tr then
			tr:Play()
			return tr
		end
		return nil
	end
	local function fadeOut(p, secs, grow)
		if typeof(p) == "Instance" and p:IsA("BasePart") and p.Parent then
			local props = { Transparency = 1 }
			if grow then
				props.Size = p.Size * grow
			end
			tw(p, secs, props, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(p, secs + 0.05)
		end
	end
	local function randUnit()
		local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		return v.Magnitude > 1e-3 and v.Unit or UP
	end
	local function smooth(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	local function backOut(x)
		x = math.clamp(x, 0, 1)
		local c1 = 1.70158
		return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
	end
	local function flatOf(v, fallback)
		if type(ctx.flat) == "function" then
			local ok, r = pcall(ctx.flat, v, fallback)
			if ok and typeof(r) == "Vector3" then
				return r
			end
		end
		local f = typeof(v) == "Vector3" and Vector3.new(v.X, 0, v.Z) or Vector3.zero
		return f.Magnitude > 1e-3 and f.Unit or (fallback or Vector3.new(0, 0, -1))
	end
	local function partPos(char, name)
		local p = char and char:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p.Position or nil
	end
	local function camPos()
		local cam = workspace.CurrentCamera
		return cam and cam.CFrame.Position or Vector3.zero
	end
	local function ground(pos, depth)
		if typeof(pos) ~= "Vector3" or type(FX.groundHit) ~= "function" then
			return nil
		end
		local ok, hit = pcall(FX.groundHit, pos, depth or 20)
		return ok and hit and hit.Position or nil
	end
	-- 1 = full, 2 = lite, nil = too far (the local caster is always full)
	local function tierOf(pos, isLocal)
		if isLocal then
			return 1
		end
		if typeof(pos) ~= "Vector3" then
			return nil
		end
		if type(ctx.gate) == "function" then
			local ok, g = pcall(ctx.gate, pos)
			if ok and (g == "full" or g == "lite" or g == nil) then
				return g == "full" and 1 or (g == "lite" and 2 or nil)
			end
		end
		local d = (camPos() - pos).Magnitude
		return d <= FULL and 1 or (d <= LITE and 2 or nil)
	end
	local function castFolder(name, life)
		local f = safe("castFolder", ctx.castFolder, name, life)
		if typeof(f) == "Instance" then
			return f
		end
		f = Instance.new("Folder")
		f.Name = name or "Gear5"
		f.Parent = ctx.Folder or workspace
		Debris:AddItem(f, life or 8)
		return f
	end
	local modeFolder = nil
	local function modeFolderGet()
		if not live(modeFolder) then
			modeFolder = Instance.new("Folder")
			modeFolder.Name = "Gear5Mode"
			modeFolder.Parent = ctx.Folder or workspace
		end
		return modeFolder
	end
	local function charInfo(userId)
		local plr = Players:GetPlayerByUserId(tonumber(userId) or 0)
		local char = nil
		if type(ctx.charOf) == "function" then
			local ok, c = pcall(ctx.charOf, userId)
			if ok and typeof(c) == "Instance" then
				char = c
			end
		end
		char = char or (plr and plr.Character)
		return char, plr, plr ~= nil and plr == ctx.player
	end
	local function aliveChar(char)
		local hum = char and char.Parent and char:FindFirstChildOfClass("Humanoid")
		return hum ~= nil and hum.Health > 0
	end
	-- one soft cloud puff: a white ball that swells s0 -> s1 drifting by vel * life, fading out over life
	local function puff(f, pos, s0, s1, life, vel, alpha, color)
		if not live(f) then
			return nil
		end
		local p = mk(f, BALL, Vector3.one * s0, color or CLOUD, SMOOTH, alpha or 0.12, CFrame.new(pos), "Cloud")
		tw(p, life, { Size = Vector3.one * s1, CFrame = CFrame.new(pos + (vel or Vector3.zero) * life) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tw(p, life, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(p, life + 0.1)
		return p
	end
	-- a flat disc lying on the ground (a Cylinder's axis is its X)
	local function disc(f, pos, d, color, alpha, material)
		return mk(f, CYL, Vector3.new(0.2, d, d), color, material or SMOOTH, alpha, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), "Disc")
	end
	local function cylBetween(p, a, b, w)
		local len = (b - a).Magnitude
		if len < 0.05 then
			return
		end
		p.Size = Vector3.new(len, w, w)
		p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	end

	---------------------------------------------------------------------------------------------------
	-- casts
	local casts = {} -- ["userId#id"] = st
	local looks = {} -- [char] = the mode look
	local forced = setmetatable({}, { __mode = "k" }) -- [char] = os.clock() until which the look shows before / without the attribute
	local endedAt = setmetatable({}, { __mode = "k" }) -- [char] = os.clock() until which a just-ended look is not re-applied

	local function endCast(st, why)
		if st.ended then
			return
		end
		st.ended = true
		if casts[st.key] == st then
			casts[st.key] = nil
		end
		if st.conn then
			st.conn:Disconnect()
			st.conn = nil
		end
		local cancel = why ~= "done"
		if cancel then
			for _, tr in pairs(st.tracks or {}) do
				pcall(function()
					tr:stop(0.2)
				end)
			end
			if st.isLocal then
				safe("stopShot", ctx.stopShot)
				safe("stopMove", ctx.stopMove)
				safe("unroot", ctx.unroot)
			end
		end
		if type(st.arm) == "table" and not st.arm.dead then
			pcall(function()
				st.arm:retract(0.3)
			end)
		end
		st.arm = nil
		kill(st.float)
		st.float = nil
		for _, p in ipairs(st.clouds or {}) do
			fadeOut(p, 0.9, 1.35)
		end
		st.clouds = {}
		if st.fist and st.fist.Parent then
			for _, p in ipairs(st.fist:GetDescendants()) do
				fadeOut(p, 0.35)
			end
			Debris:AddItem(st.fist, 0.45)
		end
		fadeOut(st.forearm, 0.35)
		fadeOut(st.shadow, 0.35)
	end

	-- beat(st, at, tag, fn[, keepUntil]): fn at cast time `at` (skipped when long past, unless before keepUntil)
	local function beat(st, at, tag, fn, keepUntil)
		local e = ctx.now() - st.t0
		local late = e - at
		if late > 0.05 and not (keepUntil and e < keepUntil) then
			return
		end
		task.delay(math.max(at - e, 0), function()
			if st.ended then
				return
			end
			if st.needAlive and not aliveChar(st.char) then
				endCast(st, "died")
				return
			end
			safe(tag, fn, late > 0.05)
		end)
	end
	local function clipAt(st, at, name)
		if not st.char or not st.tier then
			return
		end
		local function go()
			if st.ended then
				return
			end
			local tr = safe("playClip", ctx.playClip, st.char, name, math.max(ctx.now() - st.t0 - at, 0))
			if tr then
				st.tracks[name] = tr
			end
		end
		local e = ctx.now() - st.t0
		if e >= at then
			go()
		else
			task.delay(at - e, go)
		end
	end
	local function chestOf(st)
		return partPos(st.char, "UpperTorso") or partPos(st.char, "Torso") or (st.hrp and st.hrp.Parent and st.hrp.Position) or st.pos
	end
	local function feetOf(st)
		local c = chestOf(st)
		return ground(c, 12) or (c - UP * 3.2)
	end
	-- the screen hit for everyone near (the caster's own client gets the big one)
	local function nearShake(pos, amp, dur, reach)
		local k = math.clamp(1 - (camPos() - pos).Magnitude / (reach or 200), 0, 1)
		if k > 0.02 then
			safe("shake", ctx.shake, amp * k, dur, 16, 0)
		end
		return k
	end

	---------------------------------------------------------------------------------------------------
	-- GEAR FIFTH: the awakening
	local function startShot(st, face)
		local sweep = math.rad(num(G5.ShotSweep, 110))
		local dist0 = num(G5.ShotDist, 11)
		local h0 = num(G5.ShotHeight, 2.2)
		local drums = st.T.drums
		safe("shot", ctx.shot, {
			char = st.char, t0 = st.t0, dur = math.min(st.T.shot, 1.2), face = face,
			path = function(e, a, base, head)
				local hp = head.Position
				local k = smooth(a)
				local ang = -sweep * 0.5 + sweep * k
				local dir = base.LookVector * math.cos(ang) + base.RightVector * math.sin(ang)
				-- every drum punches the lens in a little
				local kick = 0
				for _, at in ipairs(drums) do
					local x = e - at
					if x >= 0 and x < 0.2 then
						kick = math.max(kick, (1 - x / 0.2) * 1.2)
					end
				end
				local dist = dist0 - 3 * k - kick
				return hp + dir * dist + UP * (h0 - 1.6 * k), hp - UP * 0.4, 62 - 6 * k + kick * 3
			end,
		})
	end

	local function drum(st, i)
		local c = chestOf(st)
		local n = #st.T.drums
		snd("HitHeavy", st.hrp, 0.9 + i * 0.12, 0.55)
		if i % 2 == 0 then
			snd("Hit", st.hrp, 0.35, 0.5)
		end
		if st.isLocal then
			safe("shake", ctx.shake, 0.25 + 0.1 * i, 0.22, 14, 0)
			safe("lean", ctx.lean, { fov = -2.5 - i * 0.6, attack = 0.03, hold = 0.02, release = 0.22 })
			safe("vignette", ctx.vignette, 0.12 + 0.03 * i, 0.3, LAV)
		else
			nearShake(c, 0.25, 0.2, 90)
		end
		if not st.tier or not live(st.f) or not c then
			return
		end
		local look = (st.hrp and st.hrp.Parent) and st.hrp.CFrame.LookVector or Vector3.new(0, 0, -1)
		safe("ring", FX.ring, st.f, c, UP, 2, 14 + i * 3, LAV, 0.45, { alpha = 0.15 })
		safe("ring", FX.ring, st.f, c + look * 0.6, look, 1, 8 + i * 2, WHITE, 0.35, { alpha = 0.3 })
		safe("glow", FX.glow, st.f, c, 5 + i, LAV, 0.3, { alpha = 0.2 })
		if st.tier == 1 then
			local fp = feetOf(st)
			safe("ring", FX.ring, st.f, fp + UP * 0.2, UP, 3, 10 + i * 2, LAV, 0.5, { alpha = 0.4 })
			SH("dustRing", st.f, fp, 6, 8, 18, {})
			if i == n then
				SH("cracks", st.f, fp, 8, 9, LAV, 1.2)
			end
		end
	end

	local function burst(st, c, g)
		if st.burst then
			return
		end
		st.burst = true
		c = c or chestOf(st)
		g = g or (c and (ground(c, 12) or c - UP * 3.2))
		if not c then
			return
		end
		local R = num(G5.Radius, 28)
		if st.char then
			forced[st.char] = os.clock() + math.max(num(st.T.mode, 1.9) - num(st.T.burst, 1.15), 0) + 1.5
		end
		sndAt("Boom", c, 1.2, 0.8)
		sndAt("Thunder", c, 0.9, 0.9)
		snd("Rise", st.hrp, 0.7, 1.4)
		if st.isLocal then
			safe("flash", ctx.flash, WHITE, 0.25, 0.45)
			safe("impact", ctx.impact, { tint = WHITE, tint2 = SUN, flashAlpha = 0.2, lineTime = 0.45 })
			safe("shake", ctx.shake, 1.0, 0.7, 18, 6)
		else
			local k = nearShake(c, 0.9, 0.6, 150)
			if k > 0.3 then
				safe("flash", ctx.flash, WHITE, 0.15 * k, 0.35)
			end
		end
		if not st.tier or not live(st.f) then
			return
		end
		local f, full = st.f, st.tier == 1
		-- the white shock dome
		safe("shell", FX.shell, f, c, 3, R * 0.9, NIKA, 0.45, NEON)
		safe("shell", FX.shell, f, c, 2, R * 0.5, SUN, 0.3, NEON)
		safe("glow", FX.glow, f, c, R * 1.2, WHITE, 0.5, { alpha = 0.1 })
		safe("light", FX.light, f, c, SUN, 6, 40, 0.8)
		-- the ground rings
		safe("ring", FX.ring, f, g + UP * 0.3, UP, 4, R * 1.5, WHITE, 0.55, { alpha = 0.05 })
		task.delay(0.08, function()
			safe("ring", FX.ring, f, g + UP * 0.5, UP, 4, R * 2, CLOUD, 0.7, { alpha = 0.2 })
		end)
		-- the clouds bursting out round him + a column shooting up
		local n = full and num(G5.BurstClouds, 16) or 8
		for i = 1, n do
			local a = (i / n) * TAU + math.random() * 0.3
			local dir = Vector3.new(math.cos(a), 0.15 + math.random() * 0.55, math.sin(a)).Unit
			puff(f, c + dir * 2, 2.5, 6 + math.random() * 6, 1.0 + math.random() * 0.6, dir * (14 + math.random() * 14), 0.08)
		end
		for i = 1, (full and 6 or 3) do
			puff(f, c + UP * i * 1.5, 3, 8, 1.2, UP * (12 + i * 4), 0.1)
		end
		safe("streaks", FX.streaks, f, c, { color = WHITE, color2 = SUN, count = full and 50 or 20, speed = { 80, 160 }, size = 1.2, life = 0.45 })
		if full then
			SH("shock", f, g + UP * 0.2, UP, { radius = R, color = WHITE })
			SH("dustRing", f, g, R * 0.5, 22, 70, {})
			SH("rubble", f, g, 12, {})
			SH("impactStar", f, c, { size = 14, color = NIKA })
		end
		if st.char then
			SH("boing", st.char, { power = 1.8, color = NIKA, force = true })
		end
	end

	local function haLetters(st)
		local head = st.char and st.char:FindFirstChild("Head")
		if not head or not live(st.f) then
			return
		end
		local bb = Instance.new("BillboardGui")
		bb.Name = "Gear5Laugh"
		bb.Adornee = head
		bb.Size = UDim2.fromScale(11, 7)
		bb.StudsOffset = Vector3.new(0, 1.6, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = LITE
		bb.Parent = st.f
		Debris:AddItem(bb, 1.9)
		local n = num(G5.LaughLetters, 7)
		for i = 1, n do
			task.delay((i - 1) * 0.09, function()
				if not bb.Parent then
					return
				end
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 1
				t.AnchorPoint = Vector2.new(0.5, 0.5)
				local ang = (i / n) * TAU + math.random() * 0.4
				local pos = UDim2.fromScale(0.5 + math.cos(ang) * 0.36, 0.5 + math.sin(ang) * 0.34)
				t.Position = pos
				t.Size = UDim2.fromScale(0.05, 0.04)
				t.Text = (i % 3 == 0) and "HA!" or "HA"
				t.Font = Enum.Font.GothamBlack
				t.TextScaled = true
				t.TextColor3 = (i % 2 == 0) and WHITE or SUN
				t.TextStrokeTransparency = 0
				t.TextStrokeColor3 = TOON
				t.Rotation = math.random(-24, 24)
				t.Parent = bb
				local s = 0.26 + math.random() * 0.1
				tw(t, 0.2, { Size = UDim2.fromScale(s, s * 0.8) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				task.delay(0.75, function()
					if t.Parent then
						tw(t, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1, Position = pos + UDim2.fromScale(0, -0.12) })
					end
				end)
			end)
		end
	end

	local function laugh(st)
		if st.isLocal then
			safe("callout", ctx.callout, "Laugh")
		end
		snd("Rise", st.hrp, 0.6, 1.8)
		task.delay(0.18, function()
			snd("Rise", st.hrp, 0.5, 2.0)
		end)
		task.delay(0.36, function()
			snd("Rise", st.hrp, 0.45, 1.7)
		end)
		if st.tier then
			haLetters(st)
		end
	end

	H.Gear5Cast = function(d)
		if type(d) ~= "table" or type(d.t0) ~= "number" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			return
		end
		local T = {
			drums = type(d.drumAt) == "table" and d.drumAt or G5.DrumAt or { 0, 0.32, 0.64, 0.9 },
			burst = num(d.burstAt, num(G5.BurstAt, 1.15)), laugh = num(d.laughAt, num(G5.LaughAt, 1.5)),
			mode = num(d.modeAt, num(G5.ModeAt, 1.9)), shot = num(d.shotEnd, num(G5.ShotEnd, 1.15)),
			lock = num(G5.Lock, 2.4),
		}
		local e = ctx.now() - d.t0
		if e > T.mode + 0.5 then
			return -- long past: the mode look comes from the attribute
		end
		local char, _, isLocal = charInfo(d.userId)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local pos = typeof(d.pos) == "Vector3" and d.pos or (hrp and hrp.Position)
		if not pos then
			return
		end
		local st = {
			key = key, kind = "Gear5", userId = d.userId, id = d.id, t0 = d.t0, T = T, char = char, hrp = hrp,
			isLocal = isLocal, tier = tierOf(pos, isLocal), pos = pos, tracks = {}, needAlive = char ~= nil,
		}
		st.f = castFolder("Gear5", 8)
		casts[key] = st
		local face = flatOf(hrp and hrp.CFrame.LookVector, Vector3.new(0, 0, -1))

		-- 0.00 the drums begin
		if isLocal then
			safe("root", ctx.root, math.max(T.lock - e, 0.05), face)
			if e < 0.4 then
				safe("callout", ctx.callout, "Drums")
			end
			safe("vignette", ctx.vignette, 0.2, 1.2, LAV)
			if e < T.shot - 0.15 then
				startShot(st, face)
			end
		end
		if e < T.lock - 0.1 then
			clipAt(st, 0, "Gear5_Awaken")
		end
		if hrp and e < T.burst then
			snd("Drone", hrp, 0.6, 0.8)
			snd("Swell", hrp, 0.5, 0.7)
		end
		for i, at in ipairs(T.drums) do
			if type(at) == "number" then
				beat(st, at, "drum", function()
					drum(st, i)
				end)
			end
		end
		-- the inhale: streaks sucked into his chest
		beat(st, T.burst - 0.12, "inhale", function()
			if st.tier == 1 then
				safe("streaks", FX.streaks, st.f, chestOf(st), { inward = 14, color = WHITE, color2 = LAV, count = 40, life = 0.14, size = 0.6 })
			end
			snd("Swell", st.hrp, 0.6, 1.3)
		end)
		beat(st, T.burst, "burst", function()
			burst(st)
		end)
		beat(st, T.laugh, "laugh", function()
			laugh(st)
		end)
		beat(st, T.mode, "modeOn", function()
			if st.char then
				forced[st.char] = math.max(forced[st.char] or 0, os.clock() + 1.0)
			end
			if st.isLocal then
				safe("shake", ctx.shake, 0.4, 0.35, 20, 3)
			end
		end)
		beat(st, T.lock + 0.05, "done", function()
			endCast(st, "done")
		end, T.lock + 1)
	end

	H.Gear5Burst = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local st = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if st then
			if not st.burst then
				safe("burst", burst, st, nil, nil) -- the server got there before our beat
			end
			return
		end
		-- no cast seen (joined late): the burst alone
		local char, _, isLocal = charInfo(d.userId)
		local lone = {
			key = "", kind = "burst", char = char, hrp = char and char:FindFirstChild("HumanoidRootPart"), isLocal = isLocal,
			tier = tierOf(d.pos, isLocal), pos = d.pos, T = { mode = 1.9, burst = 1.15 }, tracks = {},
		}
		lone.f = castFolder("Gear5Burst", 5)
		safe("burst", burst, lone, d.pos, ground(d.pos, 12))
	end

	H.Gear5On = function(d)
		if type(d) ~= "table" then
			return
		end
		local char, _, isLocal = charInfo(d.userId)
		if not char then
			return
		end
		endedAt[char] = nil
		forced[char] = math.max(forced[char] or 0, os.clock() + 1.0)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		snd("Rise", hrp, 0.7, 2.1)
		if isLocal or tierOf(hrp and hrp.Position, false) == 1 then
			SH("boing", char, { power = 1.2, color = NIKA })
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the mode look
	local CLOTH_TYPES = { Shirt = true, TShirt = true, Pants = true, Jacket = true, Sweater = true, Shorts = true, DressSkirt = true }
	local BODY_WHITE = {
		UpperTorso = true, LowerTorso = true, LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true,
		RightLowerLeg = true, Torso = true, ["Left Leg"] = true, ["Right Leg"] = true,
	}
	local function accKind(acc)
		local h = acc:FindFirstChild("Handle")
		if not (h and h:IsA("BasePart")) then
			return nil, nil
		end
		local ok, t = pcall(function()
			return acc.AccessoryType
		end)
		local name = (ok and typeof(t) == "EnumItem") and t.Name or ""
		if name == "Hair" or h:FindFirstChild("HairAttachment") then
			return "hair", h
		end
		if CLOTH_TYPES[name] then
			return "cloth", h
		end
		return nil, h
	end
	local function whiten(L, part)
		if not part:IsA("BasePart") then
			return
		end
		table.insert(L.colors, { part, part.Color })
		part.Color = NIKA
		if part:IsA("MeshPart") then
			local tid = part.TextureID
			if tid ~= "" and pcall(function()
				part.TextureID = ""
			end) then
				table.insert(L.props, { part, "TextureID", tid })
			end
		end
		for _, ch in ipairs(part:GetChildren()) do
			if ch:IsA("SpecialMesh") then
				local tex, vc = ch.TextureId, ch.VertexColor
				if pcall(function()
					ch.TextureId = ""
					ch.VertexColor = Vector3.one
				end) then
					table.insert(L.props, { ch, "TextureId", tex })
					table.insert(L.props, { ch, "VertexColor", vc })
				end
			elseif ch:IsA("SurfaceAppearance") then
				if pcall(function()
					ch.Parent = nil
				end) then
					table.insert(L.parked, { ch, part })
				end
			end
		end
	end
	local function applyLook(char)
		local L = { colors = {}, props = {}, parked = {}, extras = false, nextBounce = os.clock() + 0.6 }
		looks[char] = L
		for _, d in ipairs(char:GetChildren()) do
			if d:IsA("Accessory") then
				local kind, h = accKind(d)
				if kind and h then
					whiten(L, h)
				end
			elseif d:IsA("BasePart") and BODY_WHITE[d.Name] then
				whiten(L, d)
			elseif d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") then
				if pcall(function()
					d.Parent = nil
				end) then
					table.insert(L.parked, { d, char })
				end
			end
		end
		local hl = Instance.new("Highlight")
		hl.Name = "Gear5Toon"
		hl.Adornee = char
		hl.FillColor = NIKA
		hl.FillTransparency = num(G5.OutlineFill, 0.88)
		hl.OutlineColor = TOON
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = modeFolderGet()
		L.hl = hl
		return L
	end
	local function addExtras(char, L)
		if L.extras then
			return
		end
		L.extras = true
		local hrp = char:FindFirstChild("HumanoidRootPart")
		-- S.sunAura brings its own sun light; the FX.aura fallback gets one of ours
		L.aura = SH("sunAura", char, { k = 1 })
		local fallback = L.aura == nil
		if fallback and hrp and type(FX.aura) == "function" then
			L.aura = safe("aura", FX.aura, hrp, NIKA, SUN, 14)
		end
		if hrp and fallback then
			local light = Instance.new("PointLight")
			light.Name = "Gear5Sun"
			light.Color = SUN
			light.Brightness = 1.6
			light.Range = 14
			light.Shadows = false
			light.Parent = hrp
			L.light = light
		end
		L.scarf = {}
		local cf = hrp and hrp.CFrame or CFrame.new()
		for i = 1, num(G5.ScarfPuffs, 9) do
			local s = 0.75 + (i % 3) * 0.22
			local p = mk(modeFolderGet(), BALL, Vector3.one * s, CLOUD, SMOOTH, 0.08, cf, "Scarf")
			table.insert(L.scarf, { p = p, s = s, pos = cf.Position })
		end
	end
	local function dropExtras(L, soft)
		kill(L.aura)
		L.aura = nil
		kill(L.light)
		L.light = nil
		for _, r in ipairs(L.scarf or {}) do
			if soft then
				fadeOut(r.p, 0.45, 2.2)
			else
				kill(r.p)
			end
		end
		L.scarf = nil
		if L.bounce then
			pcall(function()
				L.bounce:stop(0.15)
			end)
			L.bounce = nil
		end
		L.extras = false
	end
	local function restore(char, L, soft)
		if looks[char] == L then
			looks[char] = nil
		end
		local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		local hadExtras = L.extras
		dropExtras(L, soft)
		kill(L.hl)
		for i = #L.props, 1, -1 do
			local r = L.props[i]
			pcall(function()
				r[1][r[2]] = r[3]
			end)
		end
		for i = #L.colors, 1, -1 do
			local r = L.colors[i]
			pcall(function()
				r[1].Color = r[2]
			end)
		end
		for i = #L.parked, 1, -1 do
			local r = L.parked[i]
			pcall(function()
				if r[2] and r[2].Parent then
					r[1].Parent = r[2]
				end
			end)
		end
		L.props, L.colors, L.parked = {}, {}, {}
		-- the mode ends in a puff of cloud
		if soft and hadExtras and torso and torso.Parent then
			local f = modeFolderGet()
			for _ = 1, 8 do
				local dir = randUnit()
				puff(f, torso.Position + dir * 1.5, 1.5, 4, 0.7, dir * 8, 0.15)
			end
			snd("Sizzle", torso, 0.4, 1.2)
		end
	end

	local function updateLook(char, L, tier, clock, dt)
		if tier == 1 then
			addExtras(char, L)
		elseif L.extras then
			dropExtras(L, false)
		end
		if type(L.aura) == "table" and type(L.aura.keep) == "function" and clock >= (L.nextKeep or 0) then
			L.nextKeep = clock + 1
			pcall(L.aura.keep, L.aura)
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then
			return
		end
		local vel = hrp.AssemblyLinearVelocity
		-- the cloud scarf: a ring round the neck swirling slowly + three puffs streaming behind him
		local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
		if L.scarf and torso then
			local head = char:FindFirstChild("Head")
			local hideFP = char == ctx.player.Character and head ~= nil and (camPos() - head.Position).Magnitude < 1.6
			local neck = torso.CFrame * CFrame.new(0, torso.Size.Y * 0.45, 0)
			local back = -torso.CFrame.LookVector
			local right = torso.CFrame.RightVector
			local n = #L.scarf
			local ringN = math.max(n - 3, 3)
			local k = 1 - math.exp(-dt * 12)
			for i, r in ipairs(L.scarf) do
				if r.p.Parent then
					if i <= ringN then
						local a = (i / ringN) * TAU + clock * 0.9
						r.pos = (neck * CFrame.new(math.cos(a) * 1.1, math.sin(clock * 3 + i) * 0.12, math.sin(a) * 0.85)).Position
					else
						local j = i - ringN
						local target = neck.Position + back * (0.9 + j * 0.95) + UP * (0.15 - j * 0.3)
							+ right * math.sin(clock * 4 + j) * 0.3 - vel * 0.02 * j
						r.pos = r.pos and r.pos:Lerp(target, k) or target
					end
					r.p.Size = Vector3.one * r.s * (1 + math.sin(clock * 5 + i * 1.3) * 0.08)
					r.p.CFrame = CFrame.new(r.pos)
					r.p.Transparency = hideFP and 1 or 0.08
				end
			end
		end
		-- a boing on every landing (the passive already squashes the hard ones, > BoingFall)
		local air = hum.FloorMaterial == Enum.Material.Air
		if air then
			L.air = true
			L.minVy = math.min(L.minVy or 0, vel.Y)
		else
			if L.air and tier == 1 then
				local fall = -(L.minVy or 0)
				if fall > num(G5.LandBoing, 14) and fall < num(PASSIVE.BoingFall, 38) then
					SH("boing", char, { power = math.clamp(fall / 30, 0.5, 1.2), color = NIKA })
				end
			end
			L.air = false
			L.minVy = 0
		end
		if tier ~= 1 then
			return
		end
		-- the bouncy idle (an overlay clip only while he stands still and no move clip covers him)
		local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moving = hum.MoveDirection.Magnitude > 0.1 or flatSpeed > num(G5.BounceSpeed, 2.5)
		if L.bounce and (moving or air) then
			pcall(function()
				L.bounce:stop(0.12)
			end)
			L.bounce = nil
			L.nextBounce = clock + 0.4
		end
		if not moving and not air and clock >= (L.nextBounce or 0) then
			local covered = type(ctx.clipActive) == "function" and safe("clipActive", ctx.clipActive, char)
			local clip = ctx.Clips and ctx.Clips.Gear5_Bounce
			if covered then
				L.nextBounce = clock + 0.25
			elseif type(clip) == "table" then
				L.bounce = safe("playClip", ctx.playClip, char, clip, 0)
				L.nextBounce = clock + num(clip.length, 0.8) + 0.25
			else
				L.nextBounce = clock + 5
			end
		end
		-- whoosh trails on every limb while he is fast
		if vel.Magnitude > num(G5.TrailSpeed, 30) and clock >= (L.nextTrail or 0) then
			L.nextTrail = clock + 0.5
			SH("limbTrail", char, "All", NIKA, SUN, 0.16, 0.6)
		end
	end

	H.Gear5End = function(d)
		if type(d) ~= "table" then
			return
		end
		local char = (typeof(d.char) == "Instance" and d.char) or charInfo(d.userId)
		if char then
			forced[char] = nil
			endedAt[char] = os.clock() + 0.6
			local L = looks[char]
			if L then
				restore(char, L, d.why ~= "died" and d.why ~= "left")
			end
		end
		-- an awakening still running for that caster (he died in it) stops drawing
		for _, st in pairs(casts) do
			if st.userId == d.userId and st.kind == "Gear5" then
				endCast(st, d.why or "ended")
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- BAJRANG GUN
	local function localFist(size)
		local m = Instance.new("Model")
		m.Name = "BajrangFist"
		local s = size
		local palm = mk(m, BLOCK, Vector3.new(s * 0.86, s * 0.7, s * 0.74), NIKA, SMOOTH, 0, CFrame.new(), "Palm")
		mk(m, BALL, Vector3.one * s * 0.8, NIKA, SMOOTH, 0, CFrame.new(0, s * 0.02, s * 0.06), "Back")
		for i = 1, 4 do
			local x = (i - 2.5) * s * 0.205
			mk(m, BALL, Vector3.one * s * 0.27, NIKA, SMOOTH, 0, CFrame.new(x, s * 0.2, -s * 0.34), "Knuckle")
			mk(m, BALL, Vector3.one * s * 0.24, NIKA, SMOOTH, 0, CFrame.new(x, -s * 0.08, -s * 0.37), "Finger")
		end
		mk(m, CYL, Vector3.new(s * 0.5, s * 0.26, s * 0.26), NIKA, SMOOTH, 0, CFrame.new(s * 0.45, -s * 0.12, -s * 0.12) * CFrame.Angles(0, math.rad(90), 0), "Thumb")
		m.PrimaryPart = palm
		return m
	end

	local function hop(st)
		local char, hrp = st.char, st.hrp
		if not (hrp and hrp.Parent) then
			return
		end
		local up = num(BJ.HopUp, 7)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ex = { char }
		local lfx = workspace:FindFirstChild("LocalFX")
		if lfx then
			table.insert(ex, lfx)
		end
		params.FilterDescendantsInstances = ex
		local hit = workspace:Raycast(hrp.Position, UP * (up + 3), params)
		if hit then
			up = math.max(0, (hit.Position - hrp.Position).Magnitude - 3)
		end
		if up > 0.5 then
			safe("move", ctx.move, {
				char = char, t0 = st.t0 + st.T.leap, dur = num(BJ.HopTime, 0.3), from = hrp.Position,
				to = hrp.Position + UP * up, face = st.fwd, ease = { "Quad", "Out" }, exitVel = UP * 2,
			})
		end
		st.float = safe("float", ctx.float, hrp, num(BJ.Float, 0.12), st.T.impact - st.T.leap + 0.25)
	end

	local function armUp(st)
		if not st.char or not st.tier then
			return
		end
		-- his arm vanishes into the near edge of the cloud bank above the target
		local entry = st.sky - st.fwd * (st.size * 0.6) - UP * st.size * 0.2
		local late = math.max(ctx.now() - st.t0 - st.T.rise, 0)
		st.arm = SH("stretchArm", st.char, "R", entry, {
			t0 = os.clock() - late, out = math.max(st.T.form - st.T.rise - 0.05, 0.15), keep = true, white = true,
			trail = true, ghosts = st.tier == 1, fistScale = num(BJ.ArmFist, 2.6), armScale = num(BJ.ArmScale, 1.7),
			maxLen = 600, overshoot = 0.04,
		})
		snd("Whoosh", st.hrp, 0.9, 0.6)
		snd("Rise", st.hrp, 0.6, 1.2)
		if st.tier == 1 and live(st.f) then
			local c = chestOf(st)
			safe("streaks", FX.streaks, st.f, c, { dir = (entry - c).Unit, spread = 8, color = WHITE, color2 = SUN, count = 24, speed = { 120, 220 }, size = 0.8, life = 0.35 })
		end
	end

	local function gatherClouds(st)
		if not st.tier or not live(st.f) then
			return
		end
		local n = st.tier == 1 and num(BJ.CloudPuffs, 18) or 9
		local R = st.size * 0.95
		local dur = math.max(st.T.form - (ctx.now() - st.t0), 0.15)
		for i = 1, n do
			local a = (i / n) * TAU + math.random() * 0.4
			local r = R * (0.45 + math.random() * 0.6)
			local off = Vector3.new(math.cos(a) * r, (math.random() - 0.5) * st.size * 0.35, math.sin(a) * r)
			local s = st.size * (0.45 + math.random() * 0.4)
			local p = mk(st.f, BALL, Vector3.one * s * 0.5, (i % 4 == 0) and C(214, 218, 236) or CLOUD, SMOOTH, 1, CFrame.new(st.sky + off * 1.9), "Cloud")
			tw(p, dur, { CFrame = CFrame.new(st.sky + off), Size = Vector3.one * s, Transparency = (i % 3 == 0) and 0.25 or 0.08 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			table.insert(st.clouds, p)
		end
		safe("glow", FX.glow, st.f, st.sky, st.size * 2.2, SUN, 1.2, { alpha = 0.3 })
		safe("ring", FX.ring, st.f, st.sky - UP * st.size * 0.2, UP, R * 2.4, R * 0.6, CLOUD, dur, { ease = "in", alpha = 0.3 })
		sndAt("Hum", st.g, 0.9, 0.6)
		sndAt("Drone", st.g, 0.7, 0.7)
	end

	local function formFist(st)
		if not st.tier or not live(st.f) then
			return
		end
		local m = SH("fistModel", st.size, { white = true, folder = st.f, life = 8 })
		if typeof(m) ~= "Instance" or not m:IsA("Model") then
			kill(m)
			m = localFist(st.size)
		end
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
			end
		end
		m.Parent = st.f
		st.fist = m
		st.formClock = os.clock()
		st.scaled = 1
		if pcall(function()
			m:ScaleTo(0.3)
		end) then
			st.scaled = 0.3
		end
		st.forearm = mk(st.f, CYL, Vector3.one, NIKA, SMOOTH, 0, CFrame.new(st.sky), "Forearm")
		st.shadow = disc(st.f, st.g + UP * 0.12, st.size * 0.5, SHADOW, 0.85)
		safe("glow", FX.glow, st.f, st.sky - UP * st.size * 0.3, st.size * 1.6, SUN, 0.6, { alpha = 0.15 })
		safe("light", FX.light, st.f, st.sky - UP * st.size * 0.5, SUN, 8, 60, 1.0)
		sndAt("Thunder", st.g, 1.0, 0.8)
		sndAt("Swell", st.g, 0.9, 0.6)
		if st.isLocal then
			safe("lean", ctx.lean, { pitch = 5, fov = 3, attack = 0.25, hold = 0.25, release = 0.4 })
		end
	end

	local function dropStart(st)
		sndAt("Whoosh", st.g, 1.4, 0.45)
		sndAt("Thunder", st.g, 0.8, 0.6)
		local fall = math.max(st.T.impact - st.T.drop, 0.1)
		if st.isLocal then
			safe("shake", ctx.shake, 0.35, fall + 0.1, 20, 2)
			safe("vignette", ctx.vignette, 0.22, fall + 0.3, SUNHOT)
		else
			nearShake(st.g, 0.3, fall, 200)
		end
		if not st.tier or not live(st.f) then
			return
		end
		local R = st.radius
		-- the wind ring collapsing onto the target + dust blown flat
		safe("ring", FX.ring, st.f, st.g + UP * 0.6, UP, R * 1.6, R * 0.4, WHITE, fall, { ease = "in", alpha = 0.4 })
		safe("ring", FX.ring, st.f, st.g + UP * 0.4, UP, R * 1.2, R * 0.2, CLOUD, fall, { ease = "in", alpha = 0.55 })
		if st.tier == 1 then
			SH("dustRing", st.f, st.g, R * 0.7, 16, 40, {})
		end
	end

	local function bajrangImpact(st, g, radius, tier, isLocal)
		local f = (st and live(st.f) and st.f) or castFolder("BajrangImpact", 6)
		radius = num(radius, num(BJ.Radius, 46))
		if isLocal then
			safe("impact", ctx.impact, { tint = WHITE, tint2 = SUN, flashAlpha = 0.25, lineTime = 0.6 })
			safe("shake", ctx.shake, 1.8, 1.4, 15, 9)
			safe("lean", ctx.lean, { pitch = 3, drop = 0.5, fov = 6, attack = 0.05, hold = 0.2, release = 0.7 })
			safe("vignette", ctx.vignette, 0.3, 1.0, SUNHOT)
		else
			local k = nearShake(g, 1.5, 1.1, 240)
			if k > 0.1 then
				safe("flash", ctx.flash, WHITE, 0.22 * k, 0.45)
			end
		end
		sndAt("Boom", g, 2, 0.55)
		sndAt("Thunder", g, 1.4, 0.5)
		sndAt("Cannon", g, 1.2, 0.45)
		sndAt("HitHeavy", g, 1.5, 0.4)
		sndAt("Shatter", g, 0.8, 0.6)
		if not tier or not live(f) then
			return
		end
		local full = tier == 1
		-- three shock rings racing out across the ground
		for i = 1, 3 do
			task.delay((i - 1) * 0.09, function()
				safe("ring", FX.ring, f, g + UP * (0.3 + i * 0.35), UP, 6, radius * (1.0 + i * 0.5), i == 1 and WHITE or (i == 2 and SUN or CLOUD), 0.5 + i * 0.15, { alpha = 0.05 })
			end)
		end
		-- the flash dome + the dust dome
		safe("shell", FX.shell, f, g, 6, radius * 0.8, WHITE, 0.35, NEON)
		local dome = mk(f, BALL, Vector3.one * 8, DUST, SMOOTH, 0.3, CFrame.new(g), "DustDome")
		tw(dome, 1.6, { Size = Vector3.one * radius * 1.7 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		tw(dome, 1.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(dome, 1.7)
		-- the sun flare + the glowing crater
		safe("glow", FX.glow, f, g + UP * 8, radius * 1.7, SUN, 0.9, { alpha = 0.05 })
		safe("light", FX.light, f, g + UP * 10, SUN, 10, 60, 1.4)
		local crater = disc(f, g + UP * 0.1, num(BJ.CraterRadius, 16) * 2.3, CRATER, 0.2, NEON)
		tw(crater, 2.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(crater, 2.7)
		-- debris + dust
		safe("streaks", FX.streaks, f, g + UP * 3, { color = WHITE, color2 = SUN, count = full and 60 or 24, speed = { 140, 260 }, size = 2.6, life = 0.6 })
		safe("rubble", FX.rubble, f, g, { count = full and 26 or 10, min = 1.4, max = 4.2, life = 3.5 })
		if full then
			SH("rubble", f, g, 18, { speed = 120 })
			SH("dustRing", f, g, radius * 0.45, 28, 95, {})
			SH("cracks", f, g, 16, radius * 0.6, SUNHOT, 2.6)
			SH("impactStar", f, g + UP * 6, { size = radius * 0.8, color = NIKA })
		end
		-- dust off the ring craters (the server cuts the craters themselves)
		local rc = BJ.RingCraters or {}
		local n, r = num(rc.n, 8), num(rc.r, 30)
		for i = 1, n do
			task.delay(i * num(rc.delay, 0.08), function()
				local a = i / n * TAU
				local pt = g + Vector3.new(math.cos(a), 0, math.sin(a)) * r
				local gp = ground(pt + UP * 6, 30) or pt
				puff(f, gp + UP * 2, 4, full and 16 or 10, 1.3, UP * 7, 0.25, DUST)
			end)
		end
	end

	local function impactBeat(st)
		if st.impact then
			return
		end
		st.impact = true
		bajrangImpact(st, st.g, st.radius, st.tier, st.isLocal)
		-- the fist hangs in the crater, then everything in the sky dissolves and his arm snaps home
		task.delay(0.35, function()
			if type(st.arm) == "table" and not st.arm.dead then
				pcall(function()
					st.arm:retract(0.35)
				end)
			end
			st.arm = nil
			snd("Hit2", st.hrp, 0.6, 1.3)
		end)
		task.delay(0.45, function()
			if st.fist and st.fist.Parent then
				for _, p in ipairs(st.fist:GetDescendants()) do
					fadeOut(p, 0.6)
				end
				Debris:AddItem(st.fist, 0.7)
			end
			fadeOut(st.forearm, 0.6)
			fadeOut(st.shadow, 0.4)
			for _, p in ipairs(st.clouds) do
				fadeOut(p, 1.4, 1.4)
			end
			st.clouds = {}
			if st.fistPos and live(st.f) then
				for _ = 1, (st.tier == 1 and 10 or 4) do
					local dir = randUnit()
					puff(st.f, st.fistPos + dir * st.size * 0.3, st.size * 0.2, st.size * 0.45, 0.9, dir * 14 + UP * 6, 0.15)
				end
			end
		end)
	end

	-- every frame of a Bajrang cast: the fist swelling, hovering, falling, the forearm, the shadow, the streaks
	local function frame(st)
		if st.ended then
			return
		end
		local m = st.fist
		if not (m and m.Parent) then
			return
		end
		local e = ctx.now() - st.t0
		local T = st.T
		local size = st.size
		local clock = os.clock()
		local ge = (clock - (st.formClock or clock)) / 0.28
		local sc = ge >= 1 and 1 or (0.3 + 0.7 * backOut(ge))
		if math.abs(sc - (st.scaled or 1)) > 0.01 then
			if pcall(function()
				m:ScaleTo(math.max(sc, 0.05))
			end) then
				st.scaled = sc
			end
		end
		local top = st.sky - UP * size * 0.55 -- hanging out of the bottom of the cloud bank
		local bottom = st.g + UP * size * 0.42
		local pos
		if e < T.drop then
			pos = top + UP * math.sin(clock * 4) * 0.8
		elseif e < T.impact then
			local a = (e - T.drop) / math.max(T.impact - T.drop, 0.05)
			pos = top:Lerp(bottom, a * a * a)
		else
			pos = bottom - UP * size * 0.12 * smooth((e - T.impact) / 0.35)
		end
		st.fistPos = pos
		pcall(function()
			m:PivotTo(CFrame.lookAt(pos, pos - UP, st.fwd))
		end)
		if st.forearm and st.forearm.Parent then
			cylBetween(st.forearm, pos + UP * size * 0.4, st.sky + UP * size * 0.1, size * 0.55 * math.max(st.scaled or 1, 0.3))
		end
		if st.shadow and st.shadow.Parent and e < T.impact + 0.05 then
			local a = math.clamp((e - T.form) / math.max(T.impact - T.form, 0.1), 0, 1)
			local dd = size * (0.5 + a * a)
			st.shadow.Size = Vector3.new(0.2, dd, dd)
			st.shadow.Transparency = 0.85 - 0.45 * a
		end
		-- the fall: speed streaks and cloud shreds dragged off the top of the fist
		if e >= T.drop and e < T.impact and st.tier == 1 and clock >= (st.nextStreak or 0) then
			st.nextStreak = clock + 0.05
			local side = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * size * 0.8
			local a = pos + UP * size * 0.5 + side
			SH("whoosh", st.f, a, a + UP * size * 1.6, { color = WHITE, width = size * 0.04, life = 0.18, alpha = 0.3 })
			puff(st.f, a, size * 0.18, size * 0.32, 0.45, UP * 12, 0.2)
		end
	end

	H.BajrangCast = function(d)
		if type(d) ~= "table" or type(d.t0) ~= "number" or typeof(d.target) ~= "Vector3" then
			return
		end
		local key = tostring(d.userId) .. "#" .. tostring(d.id)
		if casts[key] then
			return
		end
		local T = {
			leap = num(d.leapAt, num(BJ.LeapAt, 0)), rise = num(d.riseAt, num(BJ.RiseAt, 0.15)),
			form = num(d.formAt, num(BJ.FormAt, 0.55)), drop = num(d.dropAt, num(BJ.DropAt, 0.95)),
			impact = num(d.impactAt, num(BJ.ImpactAt, 1.45)), lock = num(BJ.Lock, 1.9),
		}
		local e = ctx.now() - d.t0
		if e > T.impact + 0.6 then
			return
		end
		local char, _, isLocal = charInfo(d.userId)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local g = d.target
		local from = typeof(d.from) == "Vector3" and d.from or (hrp and hrp.Position) or g
		local size = num(d.fistSize, num(BJ.FistSize, 46))
		-- the biggest hit in the game is drawn by everyone: full within LITE of either end, lite beyond
		local near = math.min((camPos() - g).Magnitude, (camPos() - from).Magnitude)
		local tier = (isLocal or near <= LITE) and 1 or 2
		local st = {
			key = key, kind = "Bajrang", userId = d.userId, id = d.id, t0 = d.t0, T = T, char = char, hrp = hrp,
			isLocal = isLocal, tier = tier, pos = from, g = g, size = size, radius = num(BJ.Radius, 46),
			sky = g + UP * num(d.height, num(BJ.Height, 170)), fwd = flatOf(g - from, flatOf(hrp and hrp.CFrame.LookVector)),
			tracks = {}, clouds = {}, needAlive = char ~= nil,
		}
		st.f = castFolder("Bajrang", 7)
		casts[key] = st

		if isLocal then
			safe("root", ctx.root, math.max(T.lock - e, 0.05), st.fwd)
			if e < 0.4 then
				safe("callout", ctx.callout, "Bajrang")
			end
			safe("vignette", ctx.vignette, 0.18, 1.0, SUNHOT)
			if e < T.leap + 0.1 then
				hop(st)
			end
		end
		if e < T.lock - 0.1 then
			clipAt(st, 0, "Gear5_Bajrang")
		end
		if hrp and e < T.rise then
			snd("Swell", hrp, 0.8, 0.9)
			snd("Rise", hrp, 0.6, 1.8)
		end
		beat(st, T.rise, "arm", function()
			armUp(st)
		end, T.impact)
		beat(st, T.rise, "gather", function()
			gatherClouds(st)
		end, T.form)
		beat(st, T.form, "form", function()
			formFist(st)
		end, T.impact)
		beat(st, T.drop, "drop", function()
			dropStart(st)
		end)
		beat(st, T.impact, "impact", function()
			impactBeat(st)
		end, T.impact + 0.3)
		beat(st, T.impact + 1.6, "done", function()
			endCast(st, "done")
		end, T.impact + 3)
		st.conn = RunService.RenderStepped:Connect(function()
			safe("bajrangFrame", frame, st)
		end)
	end

	H.BajrangImpact = function(d)
		if type(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
			return
		end
		local st = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if st then
			if not st.impact then
				st.g = d.pos
				safe("impactBeat", impactBeat, st)
			end
			return
		end
		-- no cast seen (joined late): the impact alone
		local _, _, isLocal = charInfo(d.userId)
		local near = (camPos() - d.pos).Magnitude
		safe("bajrangImpact", bajrangImpact, nil, d.pos, d.radius, (isLocal or near <= LITE) and 1 or 2, isLocal)
	end

	H.BajrangCancel = function(d)
		if type(d) ~= "table" then
			return
		end
		local st = casts[tostring(d.userId) .. "#" .. tostring(d.id)]
		if st and not st.impact then
			endCast(st, "cancel")
		end
	end

	---------------------------------------------------------------------------------------------------
	-- every frame: the mode look on every character in the mode
	-- PERKS (2026-11-07, kitsE): ctx.players (set by GomuClient when the CRIMSON GEAR copy exists) lists the players THIS
	-- copy of the module draws - the normal copy everyone without the alt skin, the alt copy everyone with it
	local function playerList()
		if type(ctx.players) == "function" then
			local ok, l = pcall(ctx.players)
			if ok and type(l) == "table" then
				return l
			end
		end
		return Players:GetPlayers()
	end
	H.__update = function(clock, dt)
		clock = clock or os.clock()
		dt = dt or 1 / 60
		local now = ctx.now()
		local seen = {}
		for _, plr in ipairs(playerList()) do
			local char = plr.Character
			if char and char.Parent then
				local untilT = char:GetAttribute("Gear5Until")
				local on = (type(untilT) == "number" and untilT > now and not (endedAt[char] and clock < endedAt[char]))
					or (forced[char] ~= nil and clock < forced[char])
				if on and not aliveChar(char) then
					on = false
				end
				local tier = nil
				if on then
					local hrp = char:FindFirstChild("HumanoidRootPart")
					tier = hrp and tierOf(hrp.Position, plr == ctx.player) or nil
				end
				local L = looks[char]
				if on and tier then
					seen[char] = true
					if not L then
						L = applyLook(char)
					end
					updateLook(char, L, tier, clock, dt)
				elseif L then
					restore(char, L, not on)
				end
			end
		end
		for char, L in pairs(looks) do
			if not seen[char] then
				restore(char, L, false)
			end
		end
	end

	-- the local character reset / unequip: the local caster's casts stop drawing (the looks follow the attribute)
	H.__reset = function()
		for _, st in pairs(casts) do
			if st.isLocal then
				endCast(st, "reset")
			end
		end
	end

	return H
end
