--!nocheck
-- OneForAllKit.Client.Ultimate: G, ONE FOR ALL 1,000,000% (design A §8 + the flair pass), played on every client.
-- Broadcast kinds (server §8.2): OFACast, OFAWhip, OFALatch, OFASmash, OFAQuake, OFACancel.
-- This module owns the caster's two cinematic shots (through ctx.shot), every beat below, the distance gating, the
-- cancel and the storm's colour grade: its OWN ColorCorrectionEffect on the camera (Lighting is never written - Gojo's
-- void owns it). The Full Cowl 100% MODE visuals (§8M) are OneForAllClient's: at ModeAt the charge's veins and steam
-- cross-fade into them. Beat times come from Config.OFA (+ its Flair table, Config child "Flair_OFA"):
--   0.00  the storm gathers: shot A (worm's-eye), the deck + a turning cloud vortex, lightning crawling through it,
--         rocks lifting, converging rings, inward streaks, the body crackling; he bows over his fists, shaking
--   0.10  the ground cracks in a ring under him (again at 0.55 and 1.50, wider each time)
--   0.20 / 0.42 / 0.62 / 0.95 / 1.30 / 1.60  sky strikes round him (green, then crimson)
--   0.35  100%: shot B (the arm) - crimson veins race up the arm, a white-hot core in the fist, arcs and sparks off
--         the arm, steam, the crimson aura and outline; the arm thrust out, its wrist clamped by the left hand, shaking
--   0.55  a second rock ring tears loose, wider; the dust starts to turn
--   0.80  BLACKWHIP (server): shot C (the reveal) - the roar, a shock ring off his chest, tendrils to up to 8 bodies,
--         hauled into a ring over him; the ring hums (collapsing rings, inward streaks, arcs on every body)
--   1.20  the camera comes back. 1.50: the deepest wind-up - the floor glows crimson under him, rings collapse in
--   1.85  LEAP: staggered take-off rings, a dust burst, rubble, afterimages and air rings all the way up
--   2.22  the inhale: the air is sucked into the fist. 2.27: the smash cut (low, looking up the column)
--   2.35  1,000,000% DETROIT SMASH (server): hit-stop + held hero pose, impact frame, shock rings in three planes
--         (staggered), a starburst, an impact star, the rocks hurled skyward, every body a crimson-green comet
--   2.43  the quake (server): ground rings, the dust doughnut, the last and widest fracture, steam vents open
--   2.44  THE COLUMN rises through the storm; ~2.79 the sky tears - a sun ring + crimson and green shock rings race
--         across the deck, lightning splits the clouds outward
--   2.70  the float down on the broken, smoking arm. 2.95-4.5 debris rains back; embers; 3.00 sun shafts
--   ~3.7  touchdown (clip OFAFlairLand). 3.85 Full Cowl 100%. 4.25 unrooted. 4.00 the sky clears. 8.2 swept up.
-- Verify pass: no white-outs near the caster's lens (the smash's stacked body glows, the opaque white ring and the
-- column's walls are toned down inside ~45-60 studs), remote casters past 220 studs get the core layers only, two
-- whips crackle instead of eight, veins run 2 per arm segment, the ground cracks cool sooner, several sounds share
-- one host, and the smash cut is skipped when a wall or slope blocks its low lens.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

return function(ctx)
	local H = {}
	local CFG, PAL, SND, FX = ctx.CFG, ctx.PAL, ctx.SND, ctx.FX
	local S = ctx.S or {}
	local O = CFG.OFA
	local F = type(O.Flair) == "table" and O.Flair or {}
	local CO = CFG.Callouts
	local UP = ctx.UP or Vector3.yAxis
	local WHITE = ctx.WHITE or Color3.new(1, 1, 1)
	local TAU = ctx.TAU or math.pi * 2
	local C3 = Color3.fromRGB
	local rng = Random.new()
	local TEX = FX.TEX or {}
	local NEON = Enum.Material.Neon

	local casts = {} -- [userId] = the running ultimate
	local raysLive = {} -- the smash's starbursts: { rays, untilT }

	---------------------------------------------------------------------------------------------------
	-- small helpers
	local function fv(k, d)
		local v = F[k]
		if v == nil then
			return d
		end
		return v
	end
	local function warnf(where, err)
		warn("[OneForAll.Ultimate] " .. tostring(where) .. ": " .. tostring(err))
	end
	local function safe(where, fn, ...)
		if type(fn) ~= "function" then
			return
		end
		local ok, err = pcall(fn, ...)
		if not ok then
			warnf(where, err)
		end
	end
	local function call(fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, r = pcall(fn, ...)
		if not ok then
			warnf("call", r)
			return nil
		end
		return r
	end
	-- runs the first of obj's methods named in `names` (true if one existed)
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
					warnf(n, err)
				end
				return true
			end
		end
		return false
	end
	local function rand(a, b)
		return rng:NextNumber(a, b)
	end
	local function cs(a, b)
		return ColorSequence.new(a, b or a)
	end
	local function ns(list)
		local kps = {}
		for _, kp in ipairs(list) do
			table.insert(kps, NumberSequenceKeypoint.new(kp[1], kp[2]))
		end
		return NumberSequence.new(kps)
	end
	local function randFlat()
		local a = rand(0, TAU)
		return Vector3.new(math.cos(a), 0, math.sin(a))
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
	local function torsoOf(m)
		return m and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
	end
	local function partPos(char, name)
		local p = char and char:FindFirstChild(name)
		return (p and p:IsA("BasePart")) and p.Position or nil
	end
	local function groundBelow(pos, fallbackY)
		local hit = FX.groundHit(pos, 30)
		if hit then
			return hit.Position
		end
		return Vector3.new(pos.X, fallbackY or (pos.Y - 3), pos.Z)
	end
	local function windFn(name)
		local fn = S[name]
		if type(fn) ~= "function" then
			fn = ctx[name]
		end
		return type(fn) == "function" and fn or nil
	end
	local function ghostOf(c, color, alpha, life)
		local fn = ctx.ghost or S.ghost
		if c and c.Parent then
			call(fn, c, color, alpha, life)
		end
	end
	local function groundLook(pos)
		local hit = FX.groundHit(pos, 12)
		local col, mat = C3(96, 88, 80), Enum.Material.Slate
		if type(S.groundColor) == "function" then
			local ok, c, m = pcall(S.groundColor, hit)
			if ok and typeof(c) == "Color3" then
				col, mat = c, m or mat
			end
		end
		return col, mat, hit
	end

	-- sounds: an empty id in Config falls back to the bracketed stand-in of its comment
	local FALLBACK = {
		SubBoom = { "Boom", 0.6 }, Choir = { "Swell", 1.5, 0.4 }, WhipCrack = { "Hit2", 1.8 },
		WindRoar = { "Whoosh", 0.6 }, AirPop = { "Cannon", 1.35 },
	}
	local function resolve(name, vol, pitch)
		local id = SND[name]
		if type(id) == "string" and id ~= "" then
			return id, vol, pitch
		end
		local fb = FALLBACK[name]
		local alt = fb and SND[fb[1]]
		if type(alt) == "string" and alt ~= "" then
			return alt, fb[3] or vol, fb[2] * (pitch or 1)
		end
		return nil
	end
	local function snd(name, parent, vol, pitch)
		local id, v, p = resolve(name, vol, pitch)
		if id and parent and parent.Parent then
			safe("sound", ctx.sound, id, parent, v or 1, p or 1)
		end
	end
	local function sndAt(name, pos, vol, pitch)
		local id, v, p = resolve(name, vol, pitch)
		if id and typeof(pos) == "Vector3" then
			safe("soundAt", ctx.soundAt, id, pos, v or 1, p or 1)
		end
	end
	-- several sounds at one point share one host (ctx.soundAt leaves an 8 s anchor part per call)
	local function sndMany(pos, list)
		if typeof(pos) ~= "Vector3" then
			return
		end
		local host
		for _, s in ipairs(list) do
			local id, v, p = resolve(s[1], s[2], s[3])
			if id then
				if host and host.Parent then
					safe("sound", ctx.sound, id, host, v or 1, p or 1)
				else
					local ok, made = pcall(ctx.soundAt, id, pos, v or 1, p or 1)
					if not ok then
						warnf("soundAt", made)
					elseif typeof(made) == "Instance" then
						host = made.Parent
					end
				end
			end
		end
	end

	-- steam (§3.3): Shared's handle (:setRate, :stop = Rate 0 then gone after 1.5 s), or a bare Attachment
	local function steamRate(att, rate)
		if type(att) == "table" then
			if not try(att, { "setRate" }, rate) then
				pcall(function()
					att.Rate = rate
				end)
			end
			return
		end
		if typeof(att) ~= "Instance" or not att.Parent then
			return
		end
		if att:IsA("ParticleEmitter") then
			att.Rate = rate
		end
		for _, e in ipairs(att:GetDescendants()) do
			if e:IsA("ParticleEmitter") then
				e.Rate = rate
			end
		end
	end
	local function steamStop(att)
		if type(att) == "table" then
			if not try(att, { "stop", "Destroy" }) then
				steamRate(att, 0)
			end
			return
		end
		if typeof(att) == "Instance" and att.Parent then
			steamRate(att, 0)
			Debris:AddItem(att, 1.5)
		end
	end

	-- the storm grade: this module's own camera ColorCorrectionEffect
	local GRADE_STORM = { Brightness = -0.07, Contrast = 0.12, Saturation = -0.15, TintColor = C3(225, 240, 232) }
	local GRADE_DEEP = { Brightness = -0.09, Contrast = 0.16, Saturation = -0.2, TintColor = C3(238, 226, 228) } -- 100%: a red cast
	local GRADE_SUN = { Brightness = 0.03, Contrast = 0.06, Saturation = 0, TintColor = C3(255, 246, 225) }
	local GRADE_ZERO = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }
	local function gradeTo(st, secs, goal, destroyAfter)
		local cc = st.grade
		if typeof(cc) ~= "Instance" or not cc.Parent then
			return
		end
		st.gradeTok = (st.gradeTok or 0) + 1
		local tok = st.gradeTok
		TweenService:Create(cc, TweenInfo.new(secs, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
		if destroyAfter then
			task.delay(secs + 0.05, function()
				if st.gradeTok == tok and cc.Parent then
					cc:Destroy()
				end
			end)
		end
	end
	local function camGrades()
		local set = {}
		local cam = workspace.CurrentCamera
		if cam then
			for _, c in ipairs(cam:GetChildren()) do
				if c:IsA("ColorCorrectionEffect") then
					set[c] = true
				end
			end
		end
		return set
	end

	-- the crimson edge vignette (§10), for a scaffold without one: four gradient frames of our own
	local vgui
	local function vignette(a0, secs)
		local pg = ctx.player:FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		if not (vgui and vgui.Parent) then
			vgui = Instance.new("ScreenGui")
			vgui.Name = "OFAUltVignette"
			vgui.IgnoreGuiInset = true
			vgui.ResetOnSpawn = false
			vgui.DisplayOrder = -1
			vgui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			vgui.Parent = pg
		end
		local info = TweenInfo.new(secs, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, e in ipairs({
			{ UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0), 90 },
			{ UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.82), -90 },
			{ UDim2.fromScale(0.12, 1), UDim2.fromScale(0, 0), 0 },
			{ UDim2.fromScale(0.12, 1), UDim2.fromScale(0.88, 0), 180 },
		}) do
			local fr = Instance.new("Frame")
			fr.Name = "Edge"
			fr.BorderSizePixel = 0
			fr.BackgroundColor3 = PAL.Crimson
			fr.BackgroundTransparency = 1 - a0
			fr.Size, fr.Position = e[1], e[2]
			local g = Instance.new("UIGradient")
			g.Rotation = e[3]
			g.Transparency = NumberSequence.new(0, 1)
			g.Parent = fr
			fr.Parent = vgui
			TweenService:Create(fr, info, { BackgroundTransparency = 1 }):Play()
			Debris:AddItem(fr, secs + 0.1)
		end
	end

	-- world geometry only (ignores the kit folders, characters and NPCs)
	local function worldParams()
		local ignore = {}
		if ctx.Folder then
			table.insert(ignore, ctx.Folder)
		end
		for _, n in ipairs({ "LocalFX", "FX", "KitFX", "KitDebris", "NPCs" }) do
			local x = workspace:FindFirstChild(n)
			if x then
				table.insert(ignore, x)
			end
		end
		for _, p2 in ipairs(Players:GetPlayers()) do
			if p2.Character then
				table.insert(ignore, p2.Character)
			end
		end
		for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag or "RagdollNPC")) do
			table.insert(ignore, m) -- a body hanging in the ring beside his head is not a wall
		end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = ignore
		return rp
	end
	-- a clear-sky probe for the indoor column
	local function roomAbove(p, maxH)
		local hit = workspace:Raycast(p, UP * maxH, worldParams())
		return hit and math.max(hit.Distance - 0.5, 4) or maxH
	end

	---------------------------------------------------------------------------------------------------
	-- flair builders (local: Shared is not this module's)

	-- the ground cracking in a ring: n glowing seams race outward from r0 to r1, cool from `color` to scorched dark,
	-- then fade. One Neon part per crack.
	local function fractureRing(f, center, r0, r1, n, color, o)
		o = o or {}
		if not (f and f.Parent) then
			return
		end
		local col, _, hit = groundLook(center)
		local base = hit and hit.Position or center
		local dark = col:Lerp(Color3.new(0, 0, 0), 0.6)
		local life = o.life or 2.4
		local off = rand(0, TAU)
		local grow = TweenInfo.new(o.grow or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for i = 1, n do
			local a = off + i / n * TAU + rand(-0.2, 0.2)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local s0 = r0 * rand(0.8, 1.15)
			local len = math.max((r1 - r0) * rand(0.55, 1), 0.5)
			local gh = FX.groundHit(base + dir * (s0 + len * 0.5), 6)
			local y = (gh and gh.Position.Y or base.Y) + 0.05
			local start = Vector3.new(base.X, y, base.Z) + dir * s0
			local yaw = CFrame.lookAt(start, start + (dir + Vector3.new(-dir.Z, 0, dir.X) * rand(-0.12, 0.12)).Unit)
			local w = rand(0.22, 0.42) * (o.width or 1)
			local p = FX.part("OFAFracture", Enum.PartType.Block, NEON, color, nil)
			p.Size = Vector3.new(w, 0.12, 0.2)
			p.CFrame = yaw * CFrame.new(0, 0, -0.1)
			p.Parent = f
			TweenService:Create(p, grow, { Size = Vector3.new(w, 0.12, len), CFrame = yaw * CFrame.new(0, 0, -len / 2) }):Play()
			TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0.25), { Color = dark }):Play()
			task.delay(life - 0.6, function()
				if p.Parent then
					TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				end
			end)
			Debris:AddItem(p, life + 0.1)
		end
		if o.rubble ~= false then
			FX.rubble(f, base, { count = o.rubble or math.ceil(n / 2), radius = r1 * 0.8, up = { 14, 28 }, out = { 2, 8 }, min = 0.4, max = 1.1 })
		end
	end

	-- the storm forming: a turning annulus of dark cloud under the deck (one emitter, LockedToPart, spun every frame)
	local function cloudVortex(f, center, alt, radius)
		local p = FX.part("OFAVortex", Enum.PartType.Block, Enum.Material.SmoothPlastic, WHITE, nil)
		p.Transparency = 1
		p.Size = Vector3.new(radius * 2, 2, radius * 2)
		p.CFrame = CFrame.new(center.X, alt - 8, center.Z)
		local e = FX.emitter(p, {
			Texture = TEX.smoke, LockedToPart = true, Orientation = Enum.ParticleOrientation.FacingCamera,
			Color = cs(PAL.Storm:Lerp(WHITE, 0.06), PAL.StormDark), LightInfluence = 0.15, LightEmission = 0,
			Size = ns({ { 0, 24 }, { 0.5, 38 }, { 1, 44 } }), Transparency = ns({ { 0, 1 }, { 0.2, 0.08 }, { 0.8, 0.12 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2.6, 3.4), Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-10, 10), ZOffset = -2, Rate = 0, EmissionDirection = Enum.NormalId.Top,
		})
		pcall(function()
			e.Shape = Enum.ParticleEmitterShape.Disc
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.ShapePartial = 0.3 -- an annulus: the eye over him stays open
		end)
		p.Parent = f
		e:Emit(8)
		e.Rate = 6
		Debris:AddItem(p, 9)
		return { part = p, emitter = e, pos = p.Position, angle = 0 }
	end

	-- a white-hot core in the overloading fist (a Neon ball + a light, placed on the hand every frame)
	local function fistCore(f)
		local b = FX.part("OFAFistCore", Enum.PartType.Ball, NEON, PAL.Crimson, nil)
		b.Transparency = 0.25
		b.Size = Vector3.one * 0.6
		local l = Instance.new("PointLight")
		l.Color = PAL.Crimson
		l.Brightness = 3
		l.Range = 10
		l.Shadows = false
		l.Parent = b
		b.Parent = f
		Debris:AddItem(b, 6)
		return { ball = b, light = l }
	end

	-- the anime twinkle at the money frame: three thin Neon spars crossed at the fist, collapsing to nothing
	local function impactStar(f, pos, aim)
		local side = aim:Cross(UP)
		if side.Magnitude < 1e-3 then
			side = Vector3.xAxis
		end
		for i, spec in ipairs({ { UP, 44, PAL.Core }, { aim, 26, PAL.Crimson }, { side.Unit, 26, PAL.Cowl } }) do
			local p = FX.part("OFAStar", Enum.PartType.Block, NEON, spec[3], nil)
			p.Size = Vector3.new(0.34, 0.34, spec[2])
			p.CFrame = CFrame.lookAt(pos, pos + spec[1])
			p.Transparency = i == 1 and 0 or 0.15
			p.Parent = f
			TweenService:Create(p, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.02, 0.02, spec[2] * 1.3), Transparency = 1,
			}):Play()
			Debris:AddItem(p, 0.3)
		end
	end

	-- one chunk of the blasted ground coming back down out of the sky (client physics, the Debris collision group)
	local function rainChunk(st, puff)
		local f = st.folder
		if not (f and f.Parent) then
			return
		end
		local g = st.g0
		local d = randFlat() * rand(6, 48)
		local h = rand(45, 85)
		local s = rand(0.5, 1.6)
		local p = Instance.new("Part")
		p.Name = "OFADebris"
		p.Size = Vector3.new(s, s * rand(0.5, 0.9), s * rand(0.7, 1.1))
		pcall(function()
			p.Material = st.gMat or Enum.Material.Slate
		end)
		p.Color = (st.gCol or C3(96, 88, 80)):Lerp(Color3.new(0, 0, 0), rand(0, 0.3))
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		pcall(function()
			p.CollisionGroup = "Debris"
		end)
		p.CFrame = CFrame.new(g + d + UP * h) * CFrame.Angles(rand(0, TAU), rand(0, TAU), 0)
		local vy = rand(25, 45)
		p.AssemblyLinearVelocity = Vector3.new(rand(-6, 6), -vy, rand(-6, 6))
		p.AssemblyAngularVelocity = FX.randUnit() * rand(4, 12)
		p.Parent = f
		task.delay(rand(2.2, 2.8), function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1, Size = p.Size * 0.4 }):Play()
			end
		end)
		Debris:AddItem(p, 3.4)
		if puff and type(S.dust) == "function" then
			local gy = workspace.Gravity
			local fall = (math.sqrt(vy * vy + 2 * gy * h) - vy) / gy
			task.delay(fall, function()
				if f.Parent then
					local gp = FX.groundHit(g + d + UP * 4, 20)
					if gp then
						call(S.dust, f, gp.Position + UP * 0.3, UP * 5, { s0 = 1.5, s1 = 4.5, count = 1, life = { 0.8, 1.2 } })
					end
				end
			end)
		end
	end

	-- a steam vent in the crater (one emitter, rate tapered, gone with the cast)
	local function vent(f, pos, rate, life)
		if not (f and f.Parent) then
			return
		end
		local host = FX.anchor(f, pos, life + 3)
		local e = FX.emitter(host, {
			Texture = TEX.smoke, Color = cs(PAL.Steam, C3(150, 150, 150)), LightInfluence = 1, LightEmission = 0,
			Size = ns({ { 0, 1.5 }, { 0.5, 4.5 }, { 1, 7 } }), Transparency = ns({ { 0, 0.78 }, { 0.4, 0.74 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.8, 2.6), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(18, 18),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2, 0), Drag = 0.6,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30), Rate = rate,
		})
		task.delay(life * 0.6, function()
			if e.Parent then
				e.Rate = rate * 0.4
			end
		end)
		task.delay(life, function()
			if e.Parent then
				e.Rate = 0
			end
		end)
	end

	---------------------------------------------------------------------------------------------------
	-- Shared's Tendril (§3.5) and its phase switches
	local function newTendril(f, getSource, opts)
		local T = S.Tendril
		local new = T and (T.new or T.New)
		return call(new, f, getSource, opts)
	end
	local function latchTendril(tw, m)
		if not tw then
			return
		end
		if not try(tw, { "latch", "setLatched", "attach" }, m) then
			if not try(tw, { "setPhase" }, "latched") then
				tw.phase = "latched"
			end
		end
	end
	local function snapAll(st)
		for _, tw in pairs(st.tendrils) do
			if not try(tw, { "snap", "release" }) then
				try(tw, { "destroy", "Destroy" })
			end
		end
		st.tendrils = {}
	end
	-- tendril roots cycle RightHand, LeftHand, back-right, back-left, RightLowerArm, LeftLowerArm
	local BACK = { Vector3.new(0.6, 0.6, 0.6), Vector3.new(-0.6, 0.6, 0.6) }
	local SOURCES = { "RightHand", "LeftHand", 1, 2, "RightLowerArm", "LeftLowerArm" }
	local function sourceFn(st, i)
		local key = SOURCES[(i - 1) % #SOURCES + 1]
		local last = st.origin
		return function()
			local c = st.char
			local p
			if c and c.Parent then
				if type(key) == "number" then
					local ut = c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
					p = ut and (ut.CFrame * BACK[key])
				else
					p = partPos(c, key)
				end
			end
			if p then
				last = p
			end
			return last
		end
	end

	---------------------------------------------------------------------------------------------------
	-- state teardown
	local function dropAuras(st)
		for _, k in ipairs({ "aura1", "aura2" }) do
			local a = st[k]
			if typeof(a) == "Instance" then
				a:Destroy()
			end
			st[k] = nil
		end
	end
	local function dropCore(st)
		local core = st.core
		st.core = nil
		if core and core.ball and core.ball.Parent then
			TweenService:Create(core.ball, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.one * 2.2 }):Play()
			Debris:AddItem(core.ball, 0.15)
		end
	end
	local function dropVortex(st, secs)
		local v = st.vortex
		st.vortex = nil
		if v and v.part and v.part.Parent then
			v.emitter.Rate = 0
			Debris:AddItem(v.part, secs or 0)
		end
	end
	local function clearBody(st, veinFade)
		snapAll(st)
		if st.veins then
			try(st.veins, { "fade" }, veinFade)
			st.veins = nil
		end
		steamStop(st.steamA)
		steamStop(st.steamB)
		st.steamA, st.steamB = nil, nil
		if st.float then
			pcall(function()
				st.float:Destroy()
			end)
			st.float = nil
		end
		if st.highlight then
			st.highlight:Destroy()
			st.highlight = nil
		end
		for _, k in ipairs({ "rocks", "rocks2" }) do
			if st[k] then
				try(st[k], { "drop" })
				st[k] = nil
			end
		end
		dropCore(st)
		dropAuras(st)
		st.floating, st.crackle, st.sparks = false, false, false
	end

	-- §8.6: OFACancel, the caster dying, or this client's reset
	local function cancelCast(st)
		if st.ended then
			return
		end
		st.ended = true
		if st.isLocal then
			if st.shotOn then
				st.shotOn = false
				safe("stopShot", ctx.stopShot)
			end
			safe("stopMove", ctx.stopMove)
			safe("unroot", ctx.unroot)
		end
		for _, tr in pairs(st.tracks) do
			pcall(function()
				tr:stop(0.2)
			end)
		end
		clearBody(st, 0.4)
		dropVortex(st, 0)
		local hadCancel = false
		if st.storm then
			hadCancel = try(st.storm, { "cancel" })
			if not hadCancel then
				try(st.storm, { "dissolve" })
			end
		end
		if st.deckGrade and not hadCancel and not st.grade then
			st.grade = st.deckGrade
		end
		gradeTo(st, 0.6, GRADE_ZERO, true)
		if casts[st.userId] == st then
			casts[st.userId] = nil
		end
	end

	-- the cast ran its course: sweep up anything still attached to the body
	local function finishCast(st)
		if st.ended then
			return
		end
		st.ended = true
		clearBody(st, 0.5)
		dropVortex(st, 0)
		if casts[st.userId] == st then
			casts[st.userId] = nil
		end
	end

	---------------------------------------------------------------------------------------------------
	-- the caster's cinematics: the charge (0 -> Charge, three cuts) and the smash cut (SmashAt - 0.08, 0.33 s).
	-- ctx.shot raycasts every lens against walls, keeps the body visible and hands the camera back facing the saved look
	local function ease(x)
		return TweenService:GetValue(math.clamp(x, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
	local function startShot(st)
		if type(ctx.shot) ~= "function" then
			return
		end
		local hrp, char = st.hrp, st.char
		if not (workspace.CurrentCamera and hrp and char) then
			return
		end
		local base = CFrame.lookAt(hrp.Position, hrp.Position + st.aim)
		local C = st.C
		local cuts = fv("ShotCuts", { 0.4, 0.8 })
		local c1, c2 = cuts[1] or 0.4, cuts[2] or 0.8
		local dur = st.T.charge
		st.shotOn = true
		FX.flash(PAL.Cowl, 0.08, 0.08) -- the cut into shot A
		ctx.shot({
			char = char,
			t0 = st.t0,
			dur = dur,
			base = base,
			cuts = { c1, c2 }, -- the scaffold flashes Cowl 0.08 on each cut frame
			path = function(e, _, _, head)
				local hp = (head and head.Parent) and head.Position or (hrp.Position + UP * 1.5)
				if e < c1 then
					-- A, worm's-eye: low in front-right, the storm gathering over his bowed head
					local a = ease(e / c1)
					local pos = (base * CFrame.Angles(0, math.rad(-28 + 12 * a), 0) * CFrame.new(0, -2.2 + 0.5 * a, -(7.5 - 1.5 * a))).Position
					return pos, hp + UP * (1.6 - 0.8 * a), 62 - 6 * a
				elseif e < c2 then
					-- B, the arm: the raised fist, the veins racing up it, the core, the sparks; pushing in
					local a = ease((e - c1) / (c2 - c1))
					local pos = (base * CFrame.new(3.6 - 0.5 * a, 0.6, -(3.0 - 0.4 * a))).Position
					local fist = partPos(char, "RightHand") or partPos(char, "RightLowerArm") or hp
					return pos, fist:Lerp(hp, 0.25), 46 - 4 * a
				end
				-- C, the reveal: behind-right, rising and pulling back over the tendrils and the ring
				local a = ease((e - c2) / math.max(dur - c2, 0.05))
				local pos = (base * CFrame.new(2.6 + 0.6 * a, 3.2 + 3.4 * a, 9 + 5 * a)).Position
				return pos, hp:Lerp(C, 0.3 + 0.18 * a), 74
			end,
		})
	end
	local function startSmashShot(st)
		if type(ctx.shot) ~= "function" or st.ended then
			return
		end
		local char = st.char
		if not (char and char.Parent and st.hrp and st.hrp.Parent) then
			return
		end
		local at = st.T.smash - fv("Shot2Lead", 0.08)
		local dur = fv("Shot2Dur", 0.33)
		local base = CFrame.lookAt(st.origin, st.origin + st.aim)
		local top = st.C + UP * 16
		-- the lens sits low, 15 studs out: lift it over rising ground, and skip the cut (the player's own camera stays)
		-- when a wall, a slope or a prop stands between his head and either end of its path
		local head = char:FindFirstChild("Head")
		local hp0 = (head and head.Position) or st.hrp.Position
		local rp = worldParams()
		local lift = {}
		for k, off in ipairs({ CFrame.new(-7.5, -1.4, -15), CFrame.new(-6.3, -0.8, -13) }) do
			local lens = (base * off).Position
			local g = workspace:Raycast(lens + UP * 8, -UP * 16, rp)
			lift[k] = g and math.max(g.Position.Y + 1.3 - lens.Y, 0) or 0
			lens += UP * lift[k]
			local hit = workspace:Raycast(hp0, lens - hp0, rp)
			if hit and (hit.Position - hp0).Magnitude < 0.75 * (lens - hp0).Magnitude then
				return -- blocked: no cut
			end
		end
		st.shotOn = true
		st.shot2Until = at + dur
		FX.flash(PAL.Crimson, 0.06, 0.06)
		ctx.shot({
			char = char,
			t0 = st.t0 + at,
			dur = dur,
			base = base,
			path = function(e, _, _, head)
				local k = ease(e / dur)
				local hp = (head and head.Parent) and head.Position or (st.C - UP * 2)
				-- low on the ground in front-left of him, looking up past him into the column
				local pos = (base * CFrame.new(-7.5 + 1.2 * k, -1.4 + 0.6 * k, -(15 - 2 * k))).Position
					+ UP * (lift[1] + (lift[2] - lift[1]) * k)
				local look = hp:Lerp(top, 0.3 + 0.35 * k)
				local hitE = e - fv("Shot2Lead", 0.08)
				if hitE > 0 then -- the smash shakes the lens itself (the scaffold's shake waits for the hand-back)
					local amp = 0.9 * math.max(1 - hitE / 0.4, 0) ^ 2
					local n = os.clock() * 31
					local j = Vector3.new(math.noise(n, 0.3), math.noise(1.7, n), math.noise(n, 4.4)) * amp
					pos += j
					look += j * 0.5
				end
				return pos, look, 72 + 8 * k
			end,
		})
	end

	---------------------------------------------------------------------------------------------------
	-- beats shared by the timeline and late joiners
	local function holeArg(st)
		return Vector3.new(st.origin.X, st.deck, st.origin.Z)
	end

	-- ~SmashAt + 0.45 (the column's top): THE SKY TEARS, and the shock races across the storm deck
	local function tearNow(st, at)
		if st.torn or st.ended or st.indoor or not st.sky then
			return
		end
		st.torn = true
		st.crawl = false
		local f = st.folder
		local deckPoint = holeArg(st)
		if st.storm then
			try(st.storm, { "tear" }, deckPoint, at or ctx.now())
		end
		dropVortex(st, 0.12)
		local fresh = (ctx.now() - (at or ctx.now())) < 0.6
		FX.glow(f, deckPoint, glowFor(deckPoint, 60), PAL.Sun, 0.8, { alpha = 0.4, brightness = 1.3 }) -- 150 studs up
		if fresh then
			FX.light(f, deckPoint - UP * 20, PAL.Sun, 6, 60, 1.2)
			FX.streaks(f, deckPoint, {
				dir = UP, spread = 80, color = PAL.Sun, color2 = PAL.Air, count = 40, speed = { 180, 300 }, size = 2.2,
				life = 0.8, stretch = 3,
			})
			task.delay(0.1, function()
				FX.ring(f, deckPoint - UP * 2, -UP, 8, 360, PAL.Crimson, 1.1, { alpha = 0.35, brightness = 1.3 })
			end)
			task.delay(0.22, function()
				FX.ring(f, deckPoint - UP * 4, -UP, 6, 260, PAL.Cowl, 0.9, { alpha = 0.3 })
			end)
			-- lightning splits the clouds outward from the hole
			local off = rand(0, TAU)
			for i = 1, 3 do
				task.delay(0.04 * i, function()
					if not f.Parent then
						return
					end
					local a = off + i / 3 * TAU + rand(-0.4, 0.4)
					local dir = Vector3.new(math.cos(a), 0, math.sin(a))
					FX.bolt(f, deckPoint + dir * 12, deckPoint + dir * rand(110, 170) + UP * rand(-6, 6), {
						color = ({ PAL.Sun, PAL.Cowl, PAL.Crimson })[i], core = PAL.Core, width = 0.8, segments = 6,
						jag = 0.12, life = 0.3, restrike = 2, light = i == 1,
					})
				end)
			end
			sndMany(st.origin + UP * 50, { { "Shatter", 0.5, 0.7 }, { "Thunder", 0.6, 0.5 } })
		end
		if st.grade then
			gradeTo(st, 0.5, GRADE_SUN)
			local tok = st.gradeTok
			task.delay(2, function()
				if st.gradeTok == tok then
					gradeTo(st, 2.2, GRADE_ZERO, true)
				end
			end)
		end
	end

	-- sunbreak: god rays through the hole
	local function shafts(st)
		if st.shafts or st.indoor or not st.sky then
			return
		end
		local at = st.T.smash + fv("ShaftsDelay", 0.65)
		st.shafts = call(S.sunShafts, st.folder, holeArg(st), st.deck, st.gY, 6, {
			elapsed = math.max(ctx.now() - (st.t0 + at), 0),
		}) or true
		sndAt("Choir", st.origin + UP * 12, 0.7, 1)
	end

	-- touchdown: the landing clip, a ring, rubble and a dust burst
	local function land(st)
		if st.landed then
			return
		end
		st.landed, st.floating = true, false
		local hrp = st.hrp
		if not (hrp and hrp.Parent) then
			return
		end
		local f = st.folder
		local gp = groundBelow(hrp.Position, st.gY)
		local clip = ctx.Clips and ctx.Clips.OFAFlairLand
		if clip and st.char and st.char.Parent then
			local tr = ctx.playClip(st.char, clip, 0)
			if tr then
				st.tracks.land = tr
				if st.tracks.float then
					pcall(function()
						st.tracks.float:stop(0.15)
					end)
				end
			end
		end
		FX.ring(f, gp + UP * 0.2, UP, 2, 24, PAL.Cowl, 0.4)
		task.delay(0.05, function()
			FX.ring(f, gp + UP * 0.25, UP, 2, 14, PAL.Crimson, 0.35, { alpha = 0.2 })
		end)
		if st.mid then
			FX.rubble(f, gp, { count = 8, radius = 2.5, up = { 18, 34 }, out = { 8, 18 } })
			call(S.dustRing, f, gp, 3, 6, 26, { s0 = 3, s1 = 9, life = { 0.9, 1.4 } })
		end
		snd("HitHeavy", hrp, 0.7, 1.0)
		if st.isLocal then
			ctx.shake(0.5, 0.3, 24, 2)
		end
		task.delay(0.35, function()
			if st.highlight then
				st.highlight:Destroy()
				st.highlight = nil
			end
		end)
	end

	-- ModeAt: the mode's own veins / steam / aura take over (they crawl up in 0.35 s; ours fade under them)
	local function handOff(st)
		local v = st.veins
		st.veins = nil
		if v then
			task.delay(0.35, function()
				try(v, { "fade" }, 0.5)
			end)
		end
		steamStop(st.steamA)
		steamStop(st.steamB)
		st.steamA, st.steamB = nil, nil
		dropAuras(st)
		dropCore(st)
		st.sparks, st.linger = false, false
	end

	---------------------------------------------------------------------------------------------------
	-- OFACast: t 0, the whole client timeline
	H.OFACast = function(d)
		local char, caster = ctx.charOf(d.userId)
		local isLocal = caster == ctx.player
		local e = ctx.now() - d.t0
		local T = {
			charge = d.charge or O.Charge, whip = d.whipAt or O.WhipAt, leap = d.leapAt or O.LeapAt,
			leapTime = d.leapTime or O.LeapTime, rise = d.leapRise or O.LeapRise, smash = d.smashAt or O.SmashAt,
			hang = d.hangUntil or O.HangUntil, mode = d.modeAt or O.ModeAt,
		}
		if e > T.mode + 1 then
			return
		end
		if casts[d.userId] then
			cancelCast(casts[d.userId])
		end
		local f = ctx.castFolder("OFA", 10)
		local origin = d.origin
		local aim = ctx.flat(d.aim or Vector3.new(0, 0, -1), Vector3.new(0, 0, -1))
		local gY = d.groundY or (origin.Y - 3)
		local deck = d.deck or (gY + O.DeckHeight)
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local st = {
			id = d.id, userId = d.userId, t0 = d.t0, T = T, folder = f, char = char, hrp = hrp, hum = hum,
			isLocal = isLocal, origin = origin, aim = aim, gY = gY, deck = deck,
			C = d.C or (origin + aim * O.ClusterForward + UP * O.ClusterUp), indoor = d.indoor == true,
			tendrils = {}, latched = {}, latchList = {}, tracks = {},
			nextArc = 0, nextFork = 0, nextSpark = 0, nextBodyArc = 0, bodyArcI = 0, nextGhost = 0, nextCrawl = 0,
			nextArmArc = 0, nextFistIn = 0, nextGather = 0, nextRise = 0, nextRain = 0, nextEmber = 0,
		}
		casts[d.userId] = st
		local dist = ctx.camDist(origin)
		st.sky = isLocal or dist < 700 -- storm deck, vortex, column, sky tear, sun shafts (the sky is shared)
		st.whips = isLocal or dist < 250 -- tendrils
		st.near = isLocal or dist < 160 -- veins, steam, arm sparks, the fist core
		st.mid = isLocal or dist < 220 -- the heavy layers: cracks, ghosts, air rings, debris rain, vents, embers
		local g0 = groundBelow(hrp and hrp.Position or origin, gY)
		st.g0 = g0
		st.gCol, st.gMat = groundLook(g0)
		st.tearAt = T.smash + fv("TearFallback", 0.55)

		local function beat(at, name, fn)
			if at < e - 0.05 then
				return -- long past: skipped
			end
			task.delay(math.max(at - e, 0), function()
				if not st.ended then
					safe(name, fn)
				end
			end)
		end
		local function clipAt(at, clipName, key)
			local clip = ctx.Clips and ctx.Clips[clipName]
			if not clip then
				return
			end
			local function go()
				if st.ended then
					return
				end
				local tr = ctx.playClip(st.char, clip, ctx.now() - d.t0 - at)
				if tr then
					st.tracks[key] = tr
				end
			end
			if e >= at then
				safe(clipName, go)
			else
				task.delay(at - e, function()
					safe(clipName, go)
				end)
			end
		end
		clipAt(0, "OFACharge", "charge")
		clipAt(T.leap, "OFASmash", "smash")
		clipAt(T.hang, "OFAFloat", "float")

		-------------------------------------------------------------------------------------------------
		-- 0.00 - the storm gathers
		if isLocal then
			safe("root", ctx.root, math.max(O.Lock - e, 0.05), aim)
			if e < 0.3 then
				safe("shot", startShot, st)
			end
		end
		if e < 1.2 and (isLocal or (hrp and ctx.camDist(hrp.Position) < 150)) then
			safe("callout", ctx.callout, "OFA")
		end
		if st.sky and e < T.mode then
			local Deck = S.StormDeck
			if Deck and type(Deck.new) == "function" then
				safe("storm", function()
					local before = camGrades()
					-- grade = false: the grade is this module's own; elapsed skips the gathering for late joiners
					st.storm = Deck.new(f, origin, gY, deck - gY, { grade = false, elapsed = math.max(e, 0) })
					for c in pairs(camGrades()) do
						if not before[c] then
							st.deckGrade = c -- the deck brought its own grade: drive that one, never stack two
						end
					end
				end)
			end
			local cam = workspace.CurrentCamera
			if cam and not st.deckGrade then
				local cc = Instance.new("ColorCorrectionEffect")
				cc.Name = "OFAStorm"
				cc.Parent = cam
				st.grade = cc
				gradeTo(st, 0.8, GRADE_STORM)
			end
			if e < T.smash and not st.indoor then
				safe("vortex", function()
					st.vortex = cloudVortex(f, origin, deck, 130)
				end)
				st.crawl = dist < 400 or isLocal -- lightning walking the clouds
			end
		end
		if hrp and e < T.leap then
			if st.mid then
				safe("charge", function()
					st.aura1 = FX.aura(hrp, PAL.Core, PAL.Cowl, 90)
					st.rocks = FX.liftRocks(f, hrp.Position, 16, 12)
				end)
			end
			st.crackle = true
			if e < 0.3 then
				snd("Swell", hrp, 1, 0.8)
				snd("Drone", hrp, 0.6, 0.7)
				snd("Crackle", hrp, 0.9, 0.75)
			end
			if e < 0.4 and st.mid then
				call(S.dustRing, f, g0, 4, 8, 6, { s0 = 2, s1 = 6, life = { 1.2, 1.8 } }) -- the dust stirs
			end
		end
		if st.mid then
			for i = 0, 8 do -- converging ground rings
				beat(i * 0.22, "ring", function()
					FX.ring(f, g0 + UP * 0.2, UP, 30, 2, (i >= 2 and i % 2 == 1) and PAL.Crimson or PAL.Cowl, 0.4, { ease = "in", alpha = 0.25 })
				end)
			end
			for i = 0, 9 do -- inward streaks
				beat(i * 0.18, "inward", function()
					local p = partPos(st.char, "HumanoidRootPart") or origin
					FX.streaks(f, p, { inward = 14, color = WHITE, color2 = (i >= 2) and PAL.Crimson or PAL.Cowl, count = 26, life = 0.35, size = 0.4 })
				end)
			end
		end
		if e < 0.4 and dist < 220 then
			local swirl = windFn("swirl")
			if swirl then
				safe("swirl", swirl, 40, 1, T.leap, origin) -- the grass swirls round him
			end
		end

		-- the ground cracks in rings under him, wider each time
		local FR = fv("Fractures", { 0.1, 0.55, 1.5 })
		local FRSPEC = { { 2.5, 8, 8, PAL.Cowl }, { 5, 15, 10, PAL.Crimson }, { 8, 22, 10, PAL.Crimson } }
		for i, at in ipairs(FR) do
			local spec = FRSPEC[i] or FRSPEC[#FRSPEC]
			beat(at, "fracture", function()
				if st.mid then
					fractureRing(f, g0, spec[1], spec[2], spec[3], spec[4], { life = 1.7 + i * 0.25, rubble = i })
				end
				local sl = { { "HitHeavy", 0.35 + 0.1 * i, 0.55 } }
				if i >= 2 then
					table.insert(sl, { "Shatter", 0.25, 0.5 })
				end
				if st.hrp and st.hrp.Parent then
					for _, s in ipairs(sl) do
						snd(s[1], st.hrp, s[2], s[3]) -- the cracks are under his feet: no host part needed
					end
				else
					sndMany(g0, sl)
				end
				if isLocal then
					ctx.shake(0.25 + 0.1 * i, 0.3, 30, 0)
				end
			end)
		end

		-- sky strikes round him: green first, then crimson as the 100% takes hold
		for i, at in ipairs(fv("Strikes", { 0.2, 0.42, 0.62, 0.95, 1.3, 1.6 })) do
			beat(at, "strike", function()
				local dir = ctx.flat(Vector3.new(rand(-1, 1), 0, rand(-1, 1)), aim)
				local p = origin + dir * rand(10, 22)
				if ctx.camDist(p) < 12 then
					p = origin - dir * rand(14, 22) -- never beside the lens (shot A sits ~7 studs out in front of him)
				end
				local gh = FX.groundHit(p, 14)
				p = gh and gh.Position or Vector3.new(p.X, gY, p.Z)
				local col = (i > 2 and i % 2 == 1) and PAL.Crimson or PAL.Cowl
				if st.sky then
					FX.bolt(f, Vector3.new(p.X, deck, p.Z) + Vector3.new(rand(-9, 9), 0, rand(-9, 9)), p, {
						color = col, core = PAL.Core, width = 0.5, segments = 8, jag = 0.09, life = 0.3, restrike = 2, light = true,
					})
				end
				FX.glow(f, p, glowFor(p, 9), col, 0.3)
				FX.ring(f, p + UP * 0.2, UP, 1, 12, col, 0.35)
				if st.mid then
					FX.rubble(f, p, { count = (i % 2 == 1) and 2 or 1 })
					FX.sparks(f, p + UP * 0.5, { color = PAL.Spark, color2 = col, count = 10, dir = UP, spread = 60, speed = { 14, 30 }, size = 0.35 })
				end
				sndMany(p, { { "Thunder", 0.7, 1.15 + rand(-0.08, 0.08) }, { "Zap", 0.6, 1 } })
				if isLocal then
					ctx.shake(0.35, 0.25, 26, 0)
				end
			end)
		end

		-- 0.35 - 100%: the arm overloads
		beat(fv("OverloadAt", 0.35), "100%", function()
			local c = st.char
			local h = st.hrp
			if not (c and c.Parent and h) then
				return
			end
			local rla, rh = c:FindFirstChild("RightLowerArm"), c:FindFirstChild("RightHand")
			if st.near then
				if S.Veins and type(S.Veins.new) == "function" then
					st.veins = call(S.Veins.new, f, c, { "RightHand", "RightLowerArm", "RightUpperArm" }, {
						crawl = 0.5, perLimb = fv("VeinsPerLimb", 2),
					})
				end
				if type(S.steam) == "function" then
					st.steamA = rla and call(S.steam, rla, 18)
					st.steamB = rh and call(S.steam, rh, 12)
				end
				st.sparks = true
				if rh then
					st.core = fistCore(f)
					FX.ring(f, rh.Position, UP, 0.5, 5, PAL.Crimson, 0.3, { alpha = 0.3 }) -- radius 2.5: clear of shot B's lens
					FX.streaks(f, rh.Position, { color = PAL.Ember, color2 = PAL.Crimson, count = 18, speed = { 20, 40 }, size = 0.3, life = 0.3 })
				end
			end
			if st.mid then
				st.aura2 = FX.aura(h, PAL.Ember, PAL.Crimson, 60)
			end
			if st.isLocal or ctx.camDist(h.Position) < 250 then
				-- the only Highlight this kit makes (keeps the scene under 31 even with a void up)
				local hl = Instance.new("Highlight")
				hl.Name = "OFAHighlight"
				hl.FillColor = PAL.Crimson
				hl.FillTransparency = 0.88
				hl.OutlineColor = PAL.Cowl
				hl.OutlineTransparency = 0.2
				hl.DepthMode = Enum.HighlightDepthMode.Occluded
				hl.Adornee = c
				hl.Parent = f
				st.highlight = hl
			end
			if st.grade then
				gradeTo(st, 0.6, GRADE_DEEP)
			end
			snd("Sizzle", rh or h, 0.7, 1.1)
			snd("Crackle", h, 0.8, 0.8)
			snd("Swell", h, 0.5, 1.1)
		end)
		beat(T.mode + 0.35, "highlight", function()
			if st.highlight then
				st.highlight:Destroy()
				st.highlight = nil
			end
		end)

		-- 0.55 - a second, wider ring of rock tears loose
		beat(fv("Fractures", { 0.1, 0.55 })[2] or 0.55, "rocks2", function()
			if st.mid and T.leap > e then
				st.rocks2 = FX.liftRocks(f, g0 + UP * 2, 26, 8)
				call(S.dustRing, f, g0, 9, 6, 10, { s0 = 4, s1 = 11, life = { 1.4, 2 } })
			end
		end)

		-- the deepest wind-up: the floor glows crimson under him, rings collapse into his feet, the swell rises
		local wind = (FR[3] or (T.leap - 0.35))
		for k, at in ipairs({ wind, wind + 0.18 }) do
			beat(at, "wind", function()
				FX.glow(f, g0 + UP * 0.5, glowFor(g0, 10), PAL.Crimson, 0.45, { alpha = 0.45, brightness = 1.4 })
				FX.ring(f, g0 + UP * 0.25, UP, 26, 2, k == 1 and PAL.Crimson or PAL.Cowl, 0.3, { ease = "in", alpha = 0.2 })
				if k == 1 and st.hrp then
					snd("Swell", st.hrp, 0.7, 1.25)
				end
			end)
		end

		-- 1.85 - LEAP
		beat(T.leap, "leap", function()
			local c, h = st.char, st.hrp
			if not (c and h and h.Parent) then
				return
			end
			local gp = groundBelow(h.Position, gY)
			if isLocal then
				local from = h.Position
				safe("move", ctx.move, {
					char = c, t0 = st.t0 + T.leap, dur = T.leapTime, from = from,
					to = from + UP * T.rise + aim * O.LeapForward, face = aim,
					ease = { Enum.EasingStyle.Quart, Enum.EasingDirection.Out },
					hold = math.max(T.hang - T.leap - T.leapTime, 0), exitVel = UP * 5 + aim * 1.5,
				})
				ctx.shake(0.5, 0.35, 24, 5)
				pcall(FX.speedLines, 0.35, { color = PAL.Spark, alpha = 0.45, count = 40, inner = 0.45 })
			end
			if st.aura1 then
				st.aura1:Destroy()
				st.aura1 = nil
			end
			for k, spec in ipairs({ { 2, 28, PAL.Cowl, 0.4, 0 }, { 2, 18, PAL.Crimson, 0.35, 0.2 }, { 1, 36, PAL.Air, 0.5, 0.25 } }) do
				task.delay((k - 1) * 0.06, function()
					FX.ring(f, gp + UP * (0.2 + 0.05 * k), UP, spec[1], spec[2], spec[3], spec[4], { alpha = spec[5] })
				end)
			end
			FX.streaks(f, gp, { dir = UP, spread = 20, color = WHITE, color2 = PAL.Cowl, count = 30, speed = { 60, 130 }, size = 0.5, life = 0.35 })
			FX.glow(f, gp + UP, glowFor(gp, 8), PAL.Cowl, 0.25, { alpha = 0.3 })
			if st.mid then
				FX.rubble(f, gp, { count = 10, radius = 3, up = { 40, 70 }, out = { 10, 25 } })
				call(S.dustRing, f, gp, 3, 6, 34, { s0 = 4, s1 = 11, life = { 1, 1.5 } })
				ghostOf(c, PAL.Cowl, 0.5, 0.4)
				call(S.bodyTrail, c, cs(PAL.Core, PAL.Cowl), 1.3, T.leapTime + 0.15)
			end
			snd("Whoosh", h, 0.9, 0.9)
			snd("Cannon", h, 0.6, 1.2)
			snd("HitHeavy", h, 0.5, 0.8)
		end)

		-- the whips let go as he arrives in the ring (each snaps with a spark): the bodies hang on the server's reel
		-- for the last 0.2 s, and the tendril parts are gone before the smash burst lands
		beat(T.smash - 0.22, "release", function()
			for m, tw in pairs(st.tendrils) do
				local tor = typeof(m) == "Instance" and m.Parent and torsoOf(m)
				if tor and st.mid then
					FX.glow(f, tor.Position, glowFor(tor.Position, 4), PAL.Cowl, 0.15, { alpha = 0.3 })
				end
			end
			snapAll(st)
			if st.hrp then
				snd("WhipCrack", st.hrp, 0.6, 1.3)
			end
		end)

		-- the inhale: the air is dragged into the fist a beat before the smash
		beat(T.smash - fv("Inhale", 0.13), "inhale", function()
			if not st.mid then
				return
			end
			local fp = partPos(st.char, "RightHand") or (st.C - UP * 3)
			FX.streaks(f, fp, { inward = 12, color = WHITE, color2 = PAL.Crimson, count = 40, life = 0.13, size = 0.5 })
			FX.ring(f, st.C, UP, 22, 1, PAL.Crimson, 0.13, { ease = "in", alpha = 0.2 })
			FX.glow(f, fp, glowFor(fp, 6), PAL.Crimson, 0.15, { from = 1.2, to = 0.3, alpha = 0.2 })
			sndAt("Whoosh", fp, 0.6, 1.6)
		end)

		if isLocal then
			-- the smash cut (low, looking up into the column), then the view leans up for the sky event
			beat(T.smash - fv("Shot2Lead", 0.08), "shot2", function()
				startSmashShot(st)
			end)
			beat(T.smash + fv("LeanDelay", 0.25), "lean", function()
				safe("lean", ctx.lean, { pitch = 20, drop = 2.2, fov = 12, attack = 0.18, hold = 1.0, release = 0.8 })
			end)
		end

		-- SmashAt + 0.09 - THE COLUMN
		beat(T.smash + fv("ColumnDelay", 0.09), "column", function()
			if not st.sky then
				return
			end
			local fist = st.C - UP * 3
			local height = math.max(deck - fist.Y, 10)
			if st.indoor then
				height = roomAbove(fist, height) -- stops at the ceiling: no tear, no shafts
			end
			if type(S.airColumn) == "function" then
				st.column = call(S.airColumn, f, fist, height, {
					t0 = st.t0 + T.smash + fv("ColumnDelay", 0.09), speed = fv("ColumnSpeed", 430),
					hold = fv("ColumnHold", 0.55), fade = fv("ColumnFade", 1.0),
					onTop = function()
						safe("tear", tearNow, st)
					end,
				})
				-- a lens inside ~45 studs (the caster's smash cut sits ~20 out) sees the walls thinner: the ForceField
				-- tube and its white Neon core are 14-32 studs wide and fill the frame from there
				local colH = st.column
				if type(colH) == "table" and ctx.camDist(fist) < 45 then
					pcall(function()
						if colH.outer and colH.outer.Parent then
							colH.outer.Transparency = math.max(colH.outer.Transparency, 0.4)
						end
						if colH.inner and colH.inner.Parent then
							colH.inner.Transparency = math.max(colH.inner.Transparency, 0.72)
						end
					end)
				end
			end
			for i = 1, 3 do -- bolts spiralling up it
				task.delay((i - 1) * 0.05, function()
					if st.ended then
						return
					end
					local a = i * TAU / 3
					local side = Vector3.new(math.cos(a), 0, math.sin(a))
					FX.bolt(f, fist + FX.randUnit() * 2, fist + UP * rand(40, 90) + side * 6, {
						color = (i % 2 == 1) and PAL.Cowl or PAL.Crimson, core = PAL.Core, width = 0.45, jag = 0.12,
						segments = 6, life = 0.35, restrike = 3, light = (i == 1),
					})
				end)
			end
			FX.streaks(f, fist, {
				dir = UP, spread = 12, color = WHITE, color2 = PAL.Air, count = 90, speed = { 260, 420 }, size = 1.0,
				life = 0.6, stretch = 3, brightness = 1.6,
			})
			FX.streaks(f, fist, { dir = UP, spread = 8, color = PAL.Cowl, color2 = PAL.Crimson, count = 40, speed = { 240, 380 }, size = 0.6, life = 0.5 })
			for k = 1, 3 do -- comets spiralling up after it
				task.delay(0.1 * k, function()
					FX.streaks(f, fist + UP * (6 * k), {
						dir = UP, spread = 18, color = (k == 2) and PAL.Crimson or PAL.Cowl, color2 = PAL.Core, count = 18,
						speed = { 160, 260 }, size = 0.7, life = 0.55, stretch = 3,
					})
				end)
			end
			sndAt("WindRoar", fist, 1, 1)
		end)
		-- if the column never reports its top, the sky still tears on time
		beat(st.tearAt, "tear", function()
			tearNow(st)
		end)

		-- HangUntil - the float on the broken arm
		beat(T.hang, "float", function()
			local h = st.hrp
			if isLocal and h and h.Parent then
				st.float = ctx.float(h, O.FloatGravity, O.FloatMax)
			end
			steamRate(st.steamA, 36)
			steamRate(st.steamB, 24)
			st.floating = true
			st.nextGhost = os.clock() + 0.15
		end)

		-- sunbreak
		beat(T.smash + fv("ShaftsDelay", 0.65), "shafts", function()
			shafts(st)
		end)

		-- residual rings over the crater as the dust settles
		for _, k in ipairs(fv("Residual", { 0.95, 1.65 })) do
			beat(T.smash + k, "residual", function()
				if st.mid then
					FX.ring(f, g0 + UP * 0.25, UP, 12, 70, PAL.Cowl, 1.6, { alpha = 0.6, brightness = 1 })
				end
			end)
		end

		-- ModeAt - Full Cowl 100% begins
		beat(T.mode, "mode", function()
			local h = st.hrp
			if isLocal then
				local c = CO.Cowl100
				safe("title", ctx.showTitle, c.text, c.kanji, c.c0, c.c1)
				FX.flash(PAL.Cowl, 0.12, 0.3)
				ctx.shake(0.3, 0.3, 22, 3)
			end
			if h and h.Parent and st.mid then
				FX.ring(f, h.Position - UP * 2.6, UP, 2, 34, PAL.Crimson, 0.5, { alpha = 0.2 })
				FX.streaks(f, h.Position, { dir = UP, spread = 25, color = PAL.Crimson, color2 = PAL.Cowl, count = 24, speed = { 40, 80 }, size = 0.5, life = 0.4 })
				snd("Swell", h, 0.7, 1.4)
				snd("Zap", h, 0.6, 1)
			end
			handOff(st)
		end)

		-- the sky clears (the deck's hosts are gone ~4.5 s later; the folder at 10 s)
		beat(T.mode + fv("DissolveAfterMode", 1.05), "dissolve", function()
			if st.storm then
				try(st.storm, { "dissolve" })
			end
			if not st.torn then
				gradeTo(st, 2, GRADE_ZERO, true) -- indoors there was no sunbreak to lift it
			end
		end)
		beat(fv("FinishAt", 8.2), "finish", function()
			finishCast(st)
		end)

		-- late joiners skip straight to the sky state: the deck already torn, the shafts up
		if e > T.smash + 0.25 then
			safe("late tear", tearNow, st, st.t0 + T.smash + 0.45)
			local sa = T.smash + fv("ShaftsDelay", 0.65)
			if e > sa + 0.05 and e < sa + 2.5 then
				safe("late shafts", shafts, st)
			end
		end
	end

	---------------------------------------------------------------------------------------------------
	-- WhipAt - BLACKWHIP: the roar, one tendril per target, sources cycling round his arms and back
	H.OFAWhip = function(d)
		local st = casts[d.userId]
		if not st or st.ended or st.id ~= d.id then
			return
		end
		local e = ctx.now() - st.t0
		if e > st.T.smash - 0.25 then
			return -- late joiners draw no tendrils (they are released at SmashAt - 0.22)
		end
		local f = st.folder
		local h = st.hrp
		if h and h.Parent then
			snd("WhipCrack", h, 0.9, 1)
			snd("Whoosh", h, 0.8, 1.5)
			snd("Thunder", h, 0.4, 0.7) -- the roar
			if e < st.T.whip + 0.2 and st.mid then
				local chest = h.Position + UP * 0.8
				FX.ring(f, chest, UP, 2, 30, PAL.Air, 0.4, { alpha = 0.2 })
				FX.ring(f, chest, st.aim, 1, 14, PAL.Cowl, 0.3, { alpha = 0.45 }) -- faces shot C's lens 9 studs behind
				FX.streaks(f, chest, { color = PAL.Spark, color2 = PAL.Cowl, count = 30, speed = { 40, 90 }, size = 0.45, life = 0.3 })
				FX.glow(f, chest, glowFor(chest, 7), PAL.Cowl, 0.25, { alpha = 0.3 })
				if st.isLocal then
					ctx.shake(0.45, 0.3, 26, 0)
				end
			end
		end
		for i, t in ipairs(d.targets or {}) do
			local m = t.model
			if typeof(m) == "Instance" and m.Parent then
				if st.whips and st.char then
					local tw = newTendril(f, sourceFn(st, i), {
						target = m, speed = O.WhipSpeed, w0 = 0.55, w1 = 0.15, lashT = st.t0 + st.T.whip,
						segs = fv("TendrilSegs", 5), crackle = i <= fv("TendrilCrackle", 3),
					})
					if tw then
						st.tendrils[m] = tw
					end
				end
			end
		end
	end

	-- each body caught: the tendril goes taut and wraps it (R's latch VFX, with a higher Hit2)
	H.OFALatch = function(d)
		local st = casts[d.userId]
		if st and (st.ended or st.id ~= d.id) then
			st = nil
		end
		local m, pos = d.model, d.pos
		if st and typeof(m) == "Instance" then
			latchTendril(st.tendrils[m], m)
			if not st.latched[m] then
				st.latched[m] = true
				table.insert(st.latchList, m)
			end
		end
		if typeof(pos) ~= "Vector3" then
			local tor = typeof(m) == "Instance" and torsoOf(m)
			pos = tor and tor.Position
		end
		if not pos then
			return
		end
		if ctx.camDist(pos) < 250 then
			local f = st and st.folder or ctx.castFolder("OFA", 4)
			FX.glow(f, pos, glowFor(pos, 5), PAL.Cowl, 0.2)
			FX.sparks(f, pos, { color = PAL.Spark, color2 = PAL.Cowl, count = 10, speed = { 15, 35 } })
			local from = st and st.hrp and st.hrp.Parent and st.hrp.Position
			local n = from and (pos - from) or UP
			FX.ring(f, pos, n.Magnitude > 1e-3 and n.Unit or UP, 1, 6, PAL.Cowl, 0.25, { alpha = 0.2 })
		end
		local body = typeof(m) == "Instance" and m.Parent and torsoOf(m)
		if body then
			snd("Hit2", body, 0.6, 1.2)
			snd("Whoosh", body, 0.4, 2.2)
		else
			sndMany(pos, { { "Hit2", 0.6, 1.2 }, { "Whoosh", 0.4, 2.2 } })
		end
	end

	-- SmashAt - 1,000,000% DETROIT SMASH (the money frame)
	H.OFASmash = function(d)
		local st = casts[d.userId]
		if st and (st.id ~= d.id or st.ended) then
			st = nil
		end
		local _, caster = ctx.charOf(d.userId)
		local isLocal = caster == ctx.player
		local fist = d.fist or (st and st.C - UP * 3)
		if typeof(fist) ~= "Vector3" then
			return
		end
		-- draw the burst on his actual fist when it is where the server says
		local hand = st and partPos(st.char, "RightHand")
		if hand and (hand - fist).Magnitude < 10 then
			fist = hand
		end
		local aim = st and st.aim or Vector3.new(0, 0, -1)
		local f = st and st.folder or ctx.castFolder("OFA", 8)
		local models = d.models or {}
		local M = CO.Million
		if st then
			st.smashed, st.crackle = true, false
			st.linger = true -- arcs keep crawling over the spent arm until the mode takes over
			local e = ctx.now() - st.t0
			if st.tracks.smash and e < st.T.smash + O.HitStop then
				safe("freeze", ctx.freeze, st.tracks.smash, O.HitStop) -- every client: the punch hangs
			end
			snapAll(st)
			dropCore(st)
			if st.rocks then
				try(st.rocks, { "drop" }, UP * 60) -- the floating rocks hurled skyward
				st.rocks = nil
			end
			if st.rocks2 then
				try(st.rocks2, { "drop" }, UP * 42 + FX.randUnit() * 10)
				st.rocks2 = nil
			end
		end
		local dist = ctx.camDist(fist)
		if isLocal then
			safe("title", ctx.showTitle, M.text, M.kanji, M.c0, M.c1)
			FX.impact({
				tint = C3(255, 190, 190), tint2 = PAL.ImpactTint2 or C3(200, 255, 220), lineColor = PAL.Crimson, lineTime = 0.7,
				flashAlpha = 0.22, flashLife = 0.3,
			})
			if type(ctx.vignette) ~= "function" then
				safe("vignette", vignette, 0.3, 0.6) -- (OneForAllClient's hudHook draws it when it has one)
			end
			ctx.shake(1.6, 0.9, 20, 0) -- the FOV comes from the lean
		else
			local k = math.clamp(1 - dist / 320, 0, 1)
			if k > 0 then
				ctx.shake(1.4 * k, 0.8, 20)
				FX.flash(C3(255, 225, 225), 0.18 * k, 0.3)
			end
			if dist < 150 then
				safe("title", ctx.showTitle, M.text, M.kanji, M.c0, M.c1)
			end
		end
		if dist < 700 then
			-- the fist burst (no stacked opaque blooms: the caster's smash-cut lens is ~20 studs from here)
			local full = dist < 220
			FX.glow(f, fist, glowFor(fist, 8), PAL.Core, 0.2, { alpha = 0.1, brightness = 3 })
			FX.glow(f, fist, glowFor(fist, 18), PAL.Crimson, 0.5, { alpha = 0.35, brightness = 1.4 })
			FX.glow(f, fist, glowFor(fist, 26), PAL.Cowl, 0.7, { alpha = 0.55, brightness = 1.0 })
			FX.light(f, fist, PAL.Crimson, 14, 60, 0.8)
			FX.light(f, fist + UP * 20, PAL.Cowl, 10, 60, 1.0)
			-- shock rings in three planes, then three more racing out, staggered
			FX.ring(f, fist, UP, 2, 90, PAL.Air, 0.7, { alpha = 0.3, brightness = 1.2 })
			FX.ring(f, fist, UP, 1, 60, PAL.Crimson, 0.5, { alpha = 0.3, brightness = 2 })
			FX.ring(f, fist, UP, 1, 40, WHITE, 0.3, { alpha = 0.3, brightness = 1.8 })
			local side = aim:Cross(UP)
			side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
			task.delay(0.03, function()
				FX.ring(f, fist, aim, 1, 34, PAL.Cowl, 0.45, { alpha = 0.25 })
			end)
			task.delay(0.05, function()
				FX.ring(f, fist, side, 1, 30, PAL.Crimson, 0.45, { alpha = 0.3 })
			end)
			for k, spec in ipairs({ { 0.09, 120, PAL.Cowl, 0.8, 0.3 }, { 0.18, 150, PAL.Crimson, 0.9, 0.35 }, { 0.28, 190, PAL.Air, 1.1, 0.4 } }) do
				task.delay(spec[1], function()
					FX.ring(f, fist + UP * (k * 1.5), UP, 2, spec[2], spec[3], spec[4], { alpha = spec[5] })
				end)
			end
			if full then
				impactStar(f, fist, aim)
				FX.sparks(f, fist, { color = PAL.Ember, color2 = PAL.Crimson, count = 30, speed = { 30, 70 }, size = 0.5, life = 0.8 })
				local ok, rays = pcall(FX.rays, f, fist, 60, 20, { PAL.Core, PAL.Cowl, PAL.Crimson })
				if ok and rays then
					table.insert(raysLive, { rays = rays, untilT = os.clock() + 0.45 })
				end
			end
			-- every smashed body: a crimson-green comet streaking up into the hole
			for i, m in ipairs(models) do
				if typeof(m) == "Instance" and m.Parent then
					local tor = torsoOf(m)
					if tor then
						local pos = tor.Position
						-- up to 8 bodies ring the fist: near the lens only every other one blooms, and none opaque
						if i % 2 == 1 or ctx.camDist(pos) > 60 then
							FX.glow(f, pos, glowFor(pos, 10), PAL.Crimson, 0.25, { alpha = 0.3, brightness = 1.6 })
						end
						if i % 2 == 1 and full then
							FX.sparks(f, pos, { color = PAL.Ember, color2 = PAL.Cowl, count = 14 })
						end
					end
					call(S.bodyTrail, m, cs(PAL.Crimson, PAL.Cowl), 2.2, 1.8)
				end
			end
		end
		sndMany(fist, {
			{ "SubBoom", 1, 1 }, { "Boom", 1, 0.8 }, { "Thunder", 1, 0.75 }, { "Cannon", 0.8, 0.6 }, { "Shatter", 0.5, 0.9 },
		})
	end

	-- SmashAt + QuakeDelay - the quake (the server's crater flower opens with it)
	H.OFAQuake = function(d)
		local st = casts[d.userId]
		if st and (st.id ~= d.id or st.ended) then
			st = nil
		end
		local g = d.pos
		if typeof(g) ~= "Vector3" then
			return
		end
		local f = st and st.folder or ctx.castFolder("OFA", 8)
		if st then
			st.g0 = g
		end
		local cd = ctx.camDist(g)
		if cd < 400 then
			FX.ring(f, g + UP * 0.3, UP, 4, 150, PAL.Cowl, 0.9, { alpha = 0.25 })
			FX.ring(f, g + UP * 0.3, UP, 2, 110, PAL.Air, 0.7, { alpha = 0.15 })
			task.delay(0.08, function()
				FX.ring(f, g + UP * 0.35, UP, 3, 90, PAL.Crimson, 0.8, { alpha = 0.3 })
			end)
			call(S.dustRing, f, g, 8, 12, 70, { s0 = 13, s1 = 30, life = { 1.8, 2.6 } }) -- the dust doughnut
			FX.rubble(f, g, { count = 16, radius = 8, up = { 50, 90 }, out = { 30, 60 }, min = 0.8, max = 2.4 })
		end
		if cd < 220 then
			fractureRing(f, g, 6, 30, 12, PAL.Crimson, { life = 3.2, width = 1.4, grow = 0.22, rubble = false })
			for i = 1, 3 do -- steam out of the crater
				local p = g + randFlat() * rand(3, 9) + UP * 0.3
				vent(f, p, 4, 3.6)
			end
		end
		local bend = windFn("windBend")
		if bend then
			safe("windBend", bend, g, nil, 260, 14, 1.5) -- every tree in the arena whips away from him
		end
		sndMany(g, { { "HitHeavy", 1, 0.7 }, { "Boom", 0.7, 0.55 } })
	end

	H.OFACancel = function(d)
		local st = casts[d.userId]
		if st and (d.id == nil or st.id == d.id) then
			cancelCast(st)
		end
	end

	---------------------------------------------------------------------------------------------------
	-- every Heartbeat: the sky (vortex, crawling lightning), the crackle, the overloading arm, the hanging ring, the
	-- rise, the float's afterimages and landing, the debris rain and the embers
	local function stepCast(st, e, dt)
		local clock = os.clock()
		local c, f, hrp, hum = st.char, st.folder, st.hrp, st.hum
		local T = st.T
		local dead = c ~= nil and (c.Parent == nil or (hum ~= nil and hum.Health <= 0))
		if dead and e < T.mode then
			cancelCast(st) -- the caster died mid-cast
			return
		end
		-- the sky does not need the body
		local v = st.vortex
		if v then
			if v.part.Parent then
				local k = math.clamp(e / T.smash, 0, 1)
				v.angle += (dt or 1 / 60) * (0.25 + 0.9 * k)
				v.part.CFrame = CFrame.new(v.pos) * CFrame.Angles(0, v.angle, 0)
				v.emitter.Rate = 6 + 5 * k
			else
				st.vortex = nil
			end
		end
		if st.crawl and e < st.tearAt and clock >= st.nextCrawl then
			st.nextCrawl = clock + 0.4
			local a = rand(0, TAU)
			local p1 = Vector3.new(st.origin.X, st.deck - rand(2, 8), st.origin.Z) + Vector3.new(math.cos(a), 0, math.sin(a)) * rand(30, 140)
			local p2 = p1 + randFlat() * rand(30, 80) + UP * rand(-6, 6)
			FX.bolt(f, p1, p2, {
				color = (e > fv("OverloadAt", 0.35) and rng:NextNumber() < 0.35) and PAL.Crimson or PAL.Cowl, core = PAL.Core,
				width = 0.55, segments = 5, jag = 0.22, life = 0.22, restrike = 1,
			})
		end
		local alive = c ~= nil and not dead and hum ~= nil and hrp ~= nil and hrp.Parent ~= nil
		if st.isLocal and st.shotOn then
			if e >= T.charge and not (st.shot2Until and e < st.shot2Until) then
				st.shotOn = false -- the scaffold handed the camera back
			end
		end
		if not alive then
			if e > fv("FinishAt", 8.2) then
				finishCast(st)
			end
			return
		end
		local near = st.isLocal or ctx.camDist(hrp.Position) < 160
		local mid = st.isLocal or ctx.camDist(hrp.Position) < 220
		if st.crackle and e < T.smash and near then
			if clock >= st.nextArc then
				st.nextArc = clock + 0.14
				local r = rng:NextNumber()
				call(ctx.bodyArc or S.bodyArc, f, c, (r < 0.6 and PAL.Cowl) or (r < 0.85 and PAL.Crimson) or PAL.Core, 0.08)
			end
			if clock >= st.nextFork then
				st.nextFork = clock + 0.2
				FX.arcs(f, hrp.Position, 4, { outward = true, count = 1, colors = { PAL.Cowl, PAL.Crimson, PAL.Core } })
			end
		end
		-- the overloading arm: sparks, arcs up the arm, air sucked into the fist, the fist core pulsing
		local over = fv("OverloadAt", 0.35)
		if near and e >= over and e < T.mode then
			local arm = c:FindFirstChild("RightLowerArm")
			local rh = c:FindFirstChild("RightHand")
			if st.sparks and arm and clock >= st.nextSpark then
				st.nextSpark = clock + 0.16
				FX.sparks(f, arm.Position, { color = PAL.Ember, color2 = PAL.Crimson, count = 4, speed = { 6, 14 }, size = 0.3 })
			end
			if (st.crackle or st.linger) and clock >= st.nextArmArc then
				st.nextArmArc = clock + (st.smashed and 0.18 or 0.12)
				local r = rng:NextNumber()
				call(S.limbArc, f, c, S.ARM_R or { "RightHand", "RightLowerArm", "RightUpperArm" },
					(r < 0.55 and PAL.Crimson) or (r < 0.85 and PAL.Core) or PAL.Cowl, st.smashed and 0.05 or 0.07)
			end
			if not st.smashed and rh and e < T.smash - 0.15 and clock >= st.nextFistIn then
				st.nextFistIn = clock + 0.24
				FX.streaks(f, rh.Position, { inward = 5, color = PAL.Crimson, color2 = PAL.Core, count = 12, life = 0.3, size = 0.25 })
			end
			local core = st.core
			if core and core.ball.Parent and rh then
				local k = math.clamp((e - over) / math.max(T.smash - over, 0.1), 0, 1)
				local pulse = 0.5 + 0.5 * math.sin(clock * 40)
				core.ball.Size = Vector3.one * (0.55 + 0.6 * k + 0.25 * pulse)
				core.ball.CFrame = rh.CFrame
				core.ball.Color = PAL.Crimson:Lerp(PAL.Core, 0.25 * pulse + 0.35 * k)
				core.light.Brightness = 2 + 3 * k + 1.5 * pulse
				core.light.Range = 8 + 8 * k
			end
		end
		-- the hanging ring hums: one body arcs per tick, round robin; the ring itself collapses inward and glows
		if not st.smashed and #st.latchList > 0 then
			if clock >= st.nextBodyArc then
				st.nextBodyArc = clock + 0.15
				st.bodyArcI = st.bodyArcI % #st.latchList + 1
				local m = st.latchList[st.bodyArcI]
				local tor = m and m.Parent and torsoOf(m)
				if tor and ctx.camDist(tor.Position) < 200 then
					call(ctx.bodyArc or S.bodyArc, f, m, (rng:NextNumber() < 0.75) and PAL.Cowl or PAL.Crimson, 0.06)
				end
			end
			if mid and e < T.smash - 0.15 and clock >= st.nextGather then
				st.nextGather = clock + 0.4
				st.gatherN = (st.gatherN or 0) + 1
				FX.ring(f, st.C, UP, 9, 3, PAL.Cowl, 0.3, { ease = "in", alpha = 0.35 })
				if st.gatherN % 2 == 1 then
					FX.glow(f, st.C, glowFor(st.C, 7), PAL.Cowl, 0.35, { alpha = 0.45, brightness = 1.2 })
				end
				FX.streaks(f, st.C, { inward = 8, color = WHITE, color2 = PAL.Cowl, count = 14, life = 0.3, size = 0.35 })
			end
		end
		-- the rise: afterimages and air rings all the way up
		if mid and e >= T.leap and e < T.leap + T.leapTime then
			if clock >= st.nextRise then
				st.nextRise = clock + 0.08
				FX.ring(f, hrp.Position - UP * 1.5, UP, 1.2, 7, PAL.Air, 0.28, { alpha = 0.35 })
			end
			if clock >= st.nextGhost then
				st.nextGhost = clock + 0.13
				ghostOf(c, PAL.Cowl, 0.55, 0.3)
			end
		end
		if st.floating then
			if clock >= st.nextGhost then
				st.nextGhost = clock + 0.16
				if mid then
					ghostOf(c, PAL.Cowl, 0.6, 0.3)
				end
			end
			if e > T.hang + 0.2 then
				local grounded = hum.FloorMaterial ~= Enum.Material.Air or FX.groundHit(hrp.Position, 3.6) ~= nil
				if grounded or e > T.hang + O.FloatMax + 0.1 then
					land(st)
				end
			end
		end
		-- the aftermath: the ground comes back down, embers drift off the crater
		if mid and st.smashed then
			local s = T.smash
			if e >= s + fv("RainFrom", 0.6) and e < s + fv("RainUntil", 2.15) and clock >= st.nextRain then
				st.nextRain = clock + 0.12
				st.rainN = (st.rainN or 0) + 1
				rainChunk(st, st.rainN % 3 == 0)
				if st.isLocal or ctx.camDist(st.g0) < 120 then
					rainChunk(st, false)
				end
			end
			if e >= s + 0.15 and e < s + 1.7 and clock >= st.nextEmber then
				st.nextEmber = clock + 0.3
				local p = st.g0 + randFlat() * rand(2, 10) + UP * 0.5
				FX.sparks(f, p, {
					color = PAL.Ember, color2 = PAL.Sun, count = 6, dir = UP, spread = 30, speed = { 6, 16 }, size = 0.35,
					life = 1.2, accel = Vector3.new(0, -4, 0), drag = 1,
				})
			end
		end
	end

	H.__update = function(_, dt)
		local t = ctx.now()
		for _, st in pairs(casts) do
			if not st.ended then
				safe("update", stepCast, st, t - st.t0, dt)
			end
		end
		local clock = os.clock()
		local i = 1
		while i <= #raysLive do
			local r = raysLive[i]
			if clock >= r.untilT then
				for _, p in ipairs(r.rays.parts or {}) do
					p:Destroy()
				end
				table.remove(raysLive, i)
			else
				pcall(r.rays.update, r.rays, dt or 1 / 60, 1.6)
				i += 1
			end
		end
	end

	-- the local character died or the kit was unequipped: stop the shots, the float, the storm and the rest
	H.__reset = function()
		for _, st in pairs(casts) do
			if st.isLocal then
				cancelCast(st)
			end
		end
		if vgui then
			vgui:Destroy()
			vgui = nil
		end
	end

	return H
end
