--!nocheck
-- ServerScriptService.Sandbox.Mutations (2026-11-13): the Mutation Lab. Each chamber (a Model holding the tagged
-- ChamberDoor button) keeps one test subject on its SubjectSpot. The console's MutateButtons (attribute Mut, a
-- ClickDetector each) change the body: wings / legs / arms / head / tentacles / diamond / giant / tiny - they stack.
-- Opening the door walks the subject out (InnerSpot, ExitSpot) and it ROAMS the map with what it was given: wings fly,
-- long legs and tiny run, giants and long arms knock other bodies about, diamond cannot be hurt. Up to 6 roam at once.
-- Extra parts (wings, tentacles) are children of UpperTorso, so RagdollService and Injury leave them alone.
-- (2026-11-13) the owner asked for three things here:
--   * "an animation that shows the mutation being applied": a press no longer swaps the body in one frame. For
--     about 2.5 s the subject glows the button's colour under a ray from the ceiling, takes a pose (the shock
--     poses StarterPlayerScripts.SandboxReactions already draws), and the change itself happens GRADUALLY (GROW:
--     limbs lengthen, the body swells or shrinks, crystal creeps up from the feet, wings snap open and beat twice,
--     tentacles sprout a segment at a time) before a white flash. All of it is made on the server, so everyone
--     sees the same thing.
--   * "if u make the npc big, they cant get out the door": measured - a giant alone walked out, a giant on LONG
--     LEGS did not. The legs code added the growth of the two leg PARTS to HipHeight; R15 leg parts overlap at the
--     knee, so the body floated 1.6 studs (3.2 as a giant) and its torso met the top of the doorway. settle() now
--     MEASURES the feet against the floor. The door is also 10.5 x 17.6 (was 7.5 x 13.4), the building is 4 studs
--     taller, the way out runs down the door's centre line, and a roamer that still makes no progress for 1.6 s
--     is carried to its next mark.
--   * the door is on the right of the window (SandboxGen.Area_Lab).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local C = Color3.fromRGB
local Mu = {}
local ORDER = { "wings", "legs", "arms", "head", "tentacles", "diamond", "giant", "tiny" }
local LABEL = { wings = "WINGS", legs = "LONG LEGS", arms = "LONG ARMS", head = "BIG HEAD", tentacles = "TENTACLES", diamond = "DIAMOND", giant = "GIANT", tiny = "TINY" }
local WALK = "rbxassetid://507777826"
local MAX_ROAMERS = 6
-- what the subject does with its body while each change takes hold (SandboxReactions' poses)
local POSE = { wings = "pant", tentacles = "pant", legs = "shockHead", arms = "shockMouth", head = "shockFace", diamond = "shield", giant = "shockHead", tiny = "cower" }
local CHARGE, GROW_T, STEPS = 0.6, 1.5, 24 -- seconds of build-up, seconds the change takes, steps it is cut into

function Mu.init(ctx)
	local H, Injury, Dummies, Ragdoll = ctx.Hazards, ctx.Injury, ctx.Dummies, ctx.Ragdoll
	local hurt, sfx, onPrompt = H.hurt, H.sfx, H.onPrompt
	local function onClick(cd, fn)
		cd.MouseClick:Connect(fn)
		if RunService:IsStudio() then
			local ev = Instance.new("BindableEvent")
			ev.Name = "DebugTrigger"
			ev.Parent = cd.Parent
			ev.Event:Connect(fn)
		end
	end
	local function scalePart(p, f)
		p.Size = p.Size * f
		for _, a in ipairs(p:GetChildren()) do
			if a:IsA("Attachment") then
				a.Position = a.Position * f
			end
		end
	end
	local function legLen(m)
		local n = 0
		for _, name in ipairs({ "LeftUpperLeg", "LeftLowerLeg" }) do
			local p = m:FindFirstChild(name)
			if p then
				n += p.Size.Y
			end
		end
		return n
	end
	local function rider(on, name, size, cf, color)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.Parent = on
		return p
	end
	local function rescale(m, hum, s)
		local before, old = hum.HipHeight, m:GetScale()
		m:ScaleTo(s)
		if math.abs(hum.HipHeight - before) < 0.01 then
			hum.HipHeight = before * (s / old)
		end
	end

	local footRay = RaycastParams.new()
	footRay.FilterType = Enum.RaycastFilterType.Exclude
	-- put the feet on the floor by measuring them (see the note at the top)
	local function settle(m, hum)
		local hrp = m:FindFirstChild("HumanoidRootPart")
		if not hrp or m:GetAttribute("Ragdolled") then
			return
		end
		footRay.FilterDescendantsInstances = { m }
		local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -80, 0), footRay)
		if not hit then
			return
		end
		local low
		for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
			local f = m:FindFirstChild(n)
			if f then
				local y = f.Position.Y - f.Size.Y / 2
				low = low and math.min(low, y) or y
			end
		end
		if low then
			local gap = low - hit.Position.Y
			if math.abs(gap) > 0.03 then
				hum.HipHeight = math.max(0.1, hum.HipHeight - gap)
			end
		end
	end

	local APPLY = {}
	function APPLY.wings(m, hum, st)
		local torso = m:FindFirstChild("UpperTorso")
		if not torso then
			return
		end
		local s = m:GetScale()
		local white = C(246, 246, 250)
		st.wingJoints = {}
		for _, sx in ipairs({ -1, 1 }) do
			local pivot = rider(torso, "Wing", Vector3.new(0.3, 0.3, 0.3) * s, torso.CFrame * CFrame.new(sx * 0.4 * s, 0.5 * s, 0.6 * s), white)
			for i, d in ipairs({ { 4.8, 34 }, { 4.2, 8 }, { 3.4, -18 } }) do
				local f = rider(torso, "Feather", Vector3.new(d[1], 1.15 - i * 0.1, 0.14) * s, pivot.CFrame * CFrame.Angles(0, 0, math.rad(sx * d[2])) * CFrame.new(sx * d[1] / 2 * s, 0, 0), (i == 2) and C(226, 230, 240) or white)
				local wc = Instance.new("WeldConstraint")
				wc.Part0, wc.Part1 = pivot, f
				wc.Parent = f
			end
			local w = Instance.new("Weld")
			w.Name = "WingJoint"
			w.Part0, w.Part1 = torso, pivot
			w.C0 = torso.CFrame:ToObjectSpace(pivot.CFrame)
			w.Parent = pivot
			table.insert(st.wingJoints, { w, w.C0, sx })
		end
	end
	---------------------------------------------------------------------------------------------- the change, gradually
	-- GROW[id](m, hum, st, T): the same result the old instant code gave, spread over T seconds
	local LEGS = { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }
	local ARMS = { "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }
	local function stretch(m, names, total, T, each)
		local f = Vector3.new(total.X ^ (1 / STEPS), total.Y ^ (1 / STEPS), total.Z ^ (1 / STEPS))
		for _ = 1, STEPS do
			if not m.Parent then
				return
			end
			for _, name in ipairs(names) do
				local p = m:FindFirstChild(name)
				if p then
					scalePart(p, f)
				end
			end
			if each then
				each()
			end
			task.wait(T / STEPS)
		end
	end
	local function scaleOver(m, hum, target, T)
		local from = m:GetScale()
		for i = 1, STEPS do
			if not m.Parent then
				return
			end
			rescale(m, hum, from * (target / from) ^ (i / STEPS))
			task.wait(T / STEPS)
		end
	end
	local GROW = {}
	function GROW.legs(m, hum, st, T)
		local last = legLen(m)
		stretch(m, LEGS, Vector3.new(1, 2.3, 1), T, function()
			-- the hips rise with the legs. 0.49 of the two parts' growth is what the standing height really gains
			-- (measured); settle() makes it exact once the growing stops
			local now = legLen(m)
			hum.HipHeight += (now - last) * 0.49
			last = now
		end)
	end
	function GROW.arms(m, hum, st, T)
		stretch(m, ARMS, Vector3.new(1, 2.5, 1), T)
	end
	function GROW.head(m, hum, st, T)
		stretch(m, { "Head" }, Vector3.new(2.6, 2.6, 2.6), T)
	end
	function GROW.giant(m, hum, st, T)
		scaleOver(m, hum, 1.75, T)
		st.tiny = nil
	end
	function GROW.tiny(m, hum, st, T)
		scaleOver(m, hum, 0.45, T)
		st.giant = nil
	end
	function GROW.diamond(m, hum, st, T)
		local parts = {}
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				table.insert(parts, p)
			end
		end
		table.sort(parts, function(a, b) -- the crystal creeps up from the feet
			return a.Position.Y < b.Position.Y
		end)
		for _, p in ipairs(parts) do
			if not m.Parent then
				return
			end
			if p.Parent then
				p.Material, p.Color, p.Reflectance, p.Transparency = Enum.Material.Glass, C(150, 230, 255), 0.35, 0.18
			end
			task.wait(T / math.max(#parts, 1))
		end
		m:SetAttribute("Invuln", true)
		hum.MaxHealth = 1e7
		hum.Health = 1e7
		local torso = m:FindFirstChild("UpperTorso")
		if torso then
			local e = Instance.new("ParticleEmitter")
			e.Name = "Glint"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Rate, e.Lifetime, e.Speed = 7, NumberRange.new(0.5, 1.1), NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.5, 0)
			e.LightEmission = 1
			e.Color = ColorSequence.new(C(190, 240, 255))
			e.Parent = torso
		end
	end
	function GROW.wings(m, hum, st, T)
		APPLY.wings(m, hum, st) -- built open, at rest ...
		local torso = m:FindFirstChild("UpperTorso")
		local joints = st.wingJoints
		if not torso or not joints then
			return
		end
		local feathers = {}
		for _, f in ipairs(torso:GetChildren()) do
			if f.Name == "Feather" or f.Name == "Wing" then
				f.Transparency = 1
				table.insert(feathers, f)
			end
		end
		-- ... then shown folded flat against the back, snapping open, and beating twice
		local open = T * 0.5
		local t0 = os.clock()
		while m.Parent do
			local t = os.clock() - t0
			if t >= T then
				break
			end
			local fold, beat = 0, 0
			if t < open then
				fold = (1 - t / open) ^ 3 * math.rad(84)
			else
				local u = (t - open) / (T - open)
				beat = math.sin(u * math.pi * 4) * 0.5 * (1 - u * 0.4)
			end
			for _, j in ipairs(joints) do
				if j[1].Parent then
					j[1].C0 = j[2] * CFrame.Angles(0, -j[3] * fold, j[3] * beat)
				end
			end
			local tr = math.clamp(1 - t / (open * 0.45), 0, 1)
			for _, f in ipairs(feathers) do
				f.Transparency = tr
			end
			task.wait(0.03)
		end
		for _, j in ipairs(joints) do
			if j[1].Parent then
				j[1].C0 = j[2]
			end
		end
		for _, f in ipairs(feathers) do
			f.Transparency = 0
		end
	end
	function GROW.tentacles(m, hum, st, T)
		local torso = m:FindFirstChild("UpperTorso")
		if not torso then
			return
		end
		local s = m:GetScale()
		local SEGS = 5
		local roots = {}
		for i = 1, 4 do
			roots[i] = { sx = (i % 2 == 0) and 1 or -1, sy = (i > 2) and 1 or -1, prev = torso }
		end
		for k = 1, SEGS do -- all four grow one more segment at a time
			if not m.Parent or not torso.Parent then
				break
			end
			for _, r in ipairs(roots) do
				local len, dia = 1.5 * s, (0.8 - k * 0.11) * s
				local at, dir
				if k == 1 then
					dir = -(torso.CFrame * CFrame.Angles(math.rad(r.sy * -28), math.rad(r.sx * -38), 0)).LookVector
					at = (torso.CFrame * CFrame.new(r.sx * 0.55 * s, r.sy * 0.45 * s, 0.45 * s)).Position
				else -- a cylinder lies along its own X: carry on from where the last one has drooped to
					dir = r.prev.CFrame.RightVector
					at = r.prev.Position + dir * (r.prev.Size.X / 2)
				end
				local seg = Instance.new("Part")
				seg.Name = "Tentacle"
				seg.Shape = Enum.PartType.Cylinder
				seg.Size = Vector3.new(len, dia, dia)
				local c = at + dir * (len / 2)
				local up = (math.abs(dir.Y) > 0.95) and torso.CFrame.LookVector or Vector3.yAxis
				seg.CFrame = CFrame.lookAt(c, c + dir, up) * CFrame.Angles(0, math.rad(90), 0)
				seg.Color = (k % 2 == 0) and C(150, 70, 190) or C(112, 50, 150)
				seg.Material = Enum.Material.SmoothPlastic
				seg.TopSurface, seg.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				seg.CanCollide, seg.CanQuery, seg.CanTouch = false, false, false
				seg.CustomPhysicalProperties = PhysicalProperties.new(0.12, 0.3, 0)
				seg.Parent = torso
				local jcf = CFrame.new(at) * seg.CFrame.Rotation
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Parent, a1.Parent = r.prev, seg
				a0.WorldCFrame, a1.WorldCFrame = jcf, jcf
				local bs = Instance.new("BallSocketConstraint")
				bs.Name = "TentacleJoint"
				bs.Attachment0, bs.Attachment1 = a0, a1
				bs.LimitsEnabled, bs.UpperAngle = true, 34
				bs.TwistLimitsEnabled, bs.TwistLowerAngle, bs.TwistUpperAngle = true, -20, 20
				bs.Parent = seg
				pcall(function()
					seg:SetNetworkOwner(nil)
				end)
				r.prev = seg
			end
			task.wait(T / SEGS)
		end
		st.tips = {}
		for _, r in ipairs(roots) do
			if r.prev ~= torso then
				table.insert(st.tips, r.prev)
			end
		end
	end

	---------------------------------------------------------------------------------------------- what you see around it
	-- everything the chamber does while a change takes hold; finishFx undoes all of it, whatever happened to the body
	local function startFx(ch, m, color, id)
		local fx = { on = true, m = m, made = {}, rays = {}, lit = {} }
		local torso = m:FindFirstChild("UpperTorso")
		local hl = Instance.new("Highlight") -- the subject glows the button's colour
		hl.Name = "MutationGlow"
		hl.FillColor, hl.OutlineColor = color, Color3.new(1, 1, 1)
		hl.FillTransparency, hl.OutlineTransparency = 0.55, 0.1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded -- not through the walls
		hl.Parent = m
		fx.hl = hl
		local roofY
		for _, p in ipairs(ch:GetChildren()) do
			if p.Name == "LightPanel" then -- the chamber's own lights take the colour
				roofY = p.Position.Y - 0.3
				local pl = p:FindFirstChildOfClass("PointLight")
				table.insert(fx.lit, { p, p.Color, pl, pl and pl.Color })
				p.Color = color
				if pl then
					pl.Color = color
				end
			end
		end
		local mark = ch:FindFirstChild("Mark")
		if mark then -- and the ring it stands on, which sends motes up round it (a K.cyl's +X face is its top)
			fx.mark = { mark, mark.Color, mark.Transparency }
			mark.Color, mark.Transparency = color, 0.05
			local e = Instance.new("ParticleEmitter")
			e.Name = "MutationMotes"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.EmissionDirection = Enum.NormalId.Right
			e.Rate, e.Lifetime, e.Speed = 55, NumberRange.new(0.7, 1.3), NumberRange.new(7, 13)
			e.SpreadAngle = Vector2.new(6, 6)
			e.Size = NumberSequence.new(0.7, 0)
			e.LightEmission, e.LightInfluence = 1, 0
			e.Color = ColorSequence.new(color)
			e.Parent = mark
			fx.motes = e
		end
		if torso then
			local top = Instance.new("Attachment") -- a ray from the ceiling onto it
			top.Name = "MutagenFrom"
			top.Parent = workspace.Terrain
			top.WorldPosition = Vector3.new(torso.Position.X, roofY or (torso.Position.Y + 12), torso.Position.Z)
			local on = Instance.new("Attachment")
			on.Name = "MutagenTo"
			on.Parent = torso
			fx.top = top
			table.insert(fx.made, top)
			table.insert(fx.made, on)
			for _, spec in ipairs({ { 3.2, 0.6 }, { 1, 0.1 } }) do -- a wide glow round a bright core
				local b = Instance.new("Beam")
				b.Name = "MutagenRay"
				b.Attachment0, b.Attachment1 = top, on
				b.Width0, b.Width1 = spec[1], spec[1] * 1.3
				b.FaceCamera = true
				b.LightEmission, b.LightInfluence = 1, 0
				b.Color = ColorSequence.new(color)
				b.Transparency = NumberSequence.new(spec[2])
				b.Segments = 1
				b.Parent = torso
				table.insert(fx.rays, { b, spec[1] })
				table.insert(fx.made, b)
			end
			local sp = Instance.new("ParticleEmitter")
			sp.Name = "MutationSparks"
			sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sp.Rate, sp.Lifetime, sp.Speed = 30, NumberRange.new(0.3, 0.7), NumberRange.new(6, 14)
			sp.SpreadAngle = Vector2.new(180, 180)
			sp.Size = NumberSequence.new(0.6, 0)
			sp.LightEmission, sp.LightInfluence = 1, 0
			sp.Color = ColorSequence.new(color)
			sp.Parent = torso
			fx.sparks = sp
			local gl = Instance.new("PointLight")
			gl.Name = "MutationLight"
			gl.Color, gl.Range, gl.Brightness, gl.Shadows = color, 16, 2.5, false
			gl.Parent = torso
			fx.light = gl
			sfx("rise", torso.Position, 0.6, 1.25)
		end
		-- the pose: it looks at whoever is at the console
		local panel = ch:FindFirstChild("Panel")
		m:SetAttribute("ReactBy", nil)
		m:SetAttribute("ReactAt", panel and panel.Position or nil)
		m:SetAttribute("React", POSE[id] or "shockHead")
		CollectionService:AddTag(m, "Reacting")
		task.spawn(function() -- it all throbs, faster as it goes
			local t0 = os.clock()
			while fx.on and m.Parent do
				local t = os.clock() - t0
				local w = 0.5 + 0.5 * math.sin(t * (9 + t * 5))
				hl.FillTransparency = 0.3 + 0.4 * w
				for _, r in ipairs(fx.rays) do
					r[1].Width0, r[1].Width1 = r[2] * (0.8 + 0.4 * w), r[2] * 1.3 * (0.8 + 0.4 * w)
				end
				if fx.light then
					fx.light.Brightness = 1.5 + 2.5 * (1 - w)
				end
				local tor = m:FindFirstChild("UpperTorso")
				if tor and fx.top and roofY then
					fx.top.WorldPosition = Vector3.new(tor.Position.X, roofY, tor.Position.Z)
				end
				task.wait(0.05)
			end
		end)
		return fx
	end
	local function finishFx(fx)
		fx.on = false
		local m = fx.m
		for _, o in ipairs(fx.made) do
			o:Destroy()
		end
		if fx.hl.Parent then -- one white flash, then it is just a body again
			fx.hl.FillColor = Color3.new(1, 1, 1)
			fx.hl.FillTransparency = 0.05
			TweenService:Create(fx.hl, TweenInfo.new(0.45), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
			Debris:AddItem(fx.hl, 0.5)
		end
		if fx.sparks and fx.sparks.Parent then
			fx.sparks.Rate = 0
			fx.sparks:Emit(45)
			Debris:AddItem(fx.sparks, 1.2)
		end
		if fx.motes and fx.motes.Parent then
			fx.motes.Enabled = false
			Debris:AddItem(fx.motes, 1.6)
		end
		if fx.light and fx.light.Parent then
			fx.light.Color, fx.light.Brightness, fx.light.Range = Color3.new(1, 1, 1), 7, 26
			Debris:AddItem(fx.light, 0.22)
		end
		local back = TweenInfo.new(0.5)
		for _, l in ipairs(fx.lit) do
			if l[1].Parent then
				TweenService:Create(l[1], back, { Color = l[2] }):Play()
				if l[3] and l[3].Parent then
					TweenService:Create(l[3], back, { Color = l[4] }):Play()
				end
			end
		end
		if fx.mark and fx.mark[1].Parent then
			TweenService:Create(fx.mark[1], back, { Color = fx.mark[2], Transparency = fx.mark[3] }):Play()
		end
		if m.Parent then
			m:SetAttribute("React", nil)
			m:SetAttribute("ReactAt", nil)
			CollectionService:RemoveTag(m, "Reacting")
			local torso = m:FindFirstChild("UpperTorso")
			if torso then
				sfx("zap", torso.Position, 0.8, 1.3)
				sfx("whoosh", torso.Position, 0.5, 1.5)
			end
		end
	end

	local function setText(screen, text, color)
		local g = screen and screen:FindFirstChild("Label")
		local l = g and g:FindFirstChildOfClass("TextLabel")
		if l then
			l.Text = text
			l.TextColor3 = color or C(90, 255, 190)
		end
	end

	------------------------------------------------------------------------------------------------ roamers
	local roamers = {}
	local function release(m, st, path)
		local hum, hrp = m:FindFirstChildOfClass("Humanoid"), m:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then
			return
		end
		m:SetAttribute("Roamer", true)
		local rec = Dummies.records[m]
		if rec then
			rec.life, rec.born = 170, os.clock()
		end
		local speed = 9
		if st.legs then
			speed = 20
		end
		if st.tiny then
			speed = 24
		end
		if st.giant then
			speed = math.max(speed, 12)
		end
		if st.head and not st.legs then
			speed = 6.5
		end
		local R = { m = m, st = st, hum = hum, hrp = hrp, path = path, goal = nil, nextAt = 0, speed = speed }
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = WALK
			local ok, tr = pcall(function()
				return animator:LoadAnimation(a)
			end)
			if ok and tr then
				tr.Looped = true
				tr.Priority = Enum.AnimationPriority.Movement
				R.track = tr
			end
		end
		table.insert(roamers, R)
		while #roamers > MAX_ROAMERS do
			local old = table.remove(roamers, 1)
			Dummies.remove(old.m, true)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local acc, flap = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		flap += dt
		local now = os.clock()
		if flap >= 0.066 then
			flap = 0
			for _, R in ipairs(roamers) do
				if R.st.wingJoints and R.flying then
					for _, j in ipairs(R.st.wingJoints) do
						if j[1].Parent then
							j[1].C0 = j[2] * CFrame.Angles(0, 0, j[3] * math.sin(now * 11) * 0.55)
						end
					end
				end
			end
		end
		if acc < 0.25 then
			return
		end
		acc = 0
		for i = #roamers, 1, -1 do
			local R = roamers[i]
			local m = R.m
			if not m.Parent or not Dummies.is(m) or m:GetAttribute("Dead") then
				if R.lv then
					R.lv:Destroy()
				end
				table.remove(roamers, i)
			else
				local down = m:GetAttribute("Ragdolled") == true or m:GetAttribute("GrabbedBy") ~= nil or m:GetAttribute("Strapped") == true
				local pos = R.hrp.Position
				if down then
					R.flying = false
					if R.lv then
						R.lv.Enabled = false
					end
				else
					R.hum.WalkSpeed = R.speed
					-- where to
					if R.path and #R.path > 0 then
						R.goal = R.path[1]
						local flat = ((R.goal - pos) * Vector3.new(1, 0, 1)).Magnitude
						if flat < 3.5 then
							table.remove(R.path, 1)
							R.best, R.bestAt = nil, nil
						elseif not R.best or flat < R.best - 0.75 then
							R.best, R.bestAt = flat, now -- still getting closer
						elseif now - R.bestAt > 1.6 then
							-- wedged on the way out (whatever it has been turned into does not fit): carry it to the mark
							m:PivotTo(m:GetPivot() + (R.goal - pos) * Vector3.new(1, 0, 1))
							table.remove(R.path, 1)
							R.best, R.bestAt = nil, nil
						end
					elseif not R.goal or now >= R.nextAt or ((R.goal - pos) * Vector3.new(1, 0, 1)).Magnitude < 5 then
						local a, r = math.random() * 6.28, 40 + math.random() * 90
						local fmap = workspace:FindFirstChild("Map") -- (2026-11-14) the packed field: Map's FieldMin / FieldMax
						local fmin, fmax = fmap and fmap:GetAttribute("FieldMin") or Vector3.new(-352, 0, -352), fmap and fmap:GetAttribute("FieldMax") or Vector3.new(352, 0, 352)
						R.goal = Vector3.new(math.clamp(pos.X + math.sin(a) * r, fmin.X + 32, fmax.X - 32), 0, math.clamp(pos.Z + math.cos(a) * r, fmin.Z + 32, fmax.Z - 32))
						R.nextAt = now + 9
					end
					R.hum:MoveTo(Vector3.new(R.goal.X, pos.Y, R.goal.Z))
					-- wings: once clear of the lab it flies
					local fly = R.st.wings ~= nil and (not R.path or #R.path == 0)
					R.flying = fly
					if fly then
						if not R.lv or not R.lv.Parent then
							local a = Instance.new("Attachment")
							a.Name = "FlyAtt"
							a.Parent = R.hrp
							local lv = Instance.new("LinearVelocity")
							lv.Attachment0 = a
							lv.MaxForce = 1e6
							lv.RelativeTo = Enum.ActuatorRelativeTo.World
							lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
							lv.Parent = R.hrp
							R.lv = lv
						end
						R.lv.Enabled = true
						rayParams.FilterDescendantsInstances = { m }
						local hit = workspace:Raycast(pos, Vector3.new(0, -120, 0), rayParams)
						local alt = hit and (pos.Y - hit.Position.Y) or 120
						local to = (R.goal - pos) * Vector3.new(1, 0, 1)
						R.lv.VectorVelocity = (to.Magnitude > 2 and to.Unit * 18 or Vector3.zero) + Vector3.new(0, math.clamp((17 * m:GetScale() - alt) * 1.6, -10, 12), 0)
					elseif R.lv then
						R.lv.Enabled = false
					end
					if R.track then
						local moving = (not fly) and R.hum.MoveDirection.Magnitude > 0.1
						if moving and not R.track.IsPlaying then
							R.track:Play(0.2)
							R.track:AdjustSpeed(math.clamp(R.speed / 11, 0.7, 2.2))
						elseif not moving and R.track.IsPlaying then
							R.track:Stop(0.2)
						end
					end
					-- giants and long arms knock other bodies about
					if R.st.giant or R.st.arms then
						local reach = (R.st.giant and 8 or 6.5) * m:GetScale() ^ 0.5
						for other in pairs(Dummies.records) do
							if other ~= m and not other:GetAttribute("Roamer") and not other:GetAttribute("Subject") and not other:GetAttribute("Strapped") then
								local t = other:FindFirstChild("UpperTorso")
								if t and (t.Position - pos).Magnitude < reach and (R.hitAt or 0) < now then
									R.hitAt = now + 0.8
									local away = (t.Position - pos) * Vector3.new(1, 0, 1)
									away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
									hurt(other, t, "blunt", R.st.giant and 34 or 14, nil, away, t.Position)
									Ragdoll.Fling(other, away * (R.st.giant and 52 or 30) + Vector3.new(0, R.st.giant and 40 or 22, 0), nil, 2.4)
									sfx("hit", t.Position, 0.8, R.st.giant and 0.7 or 1.1)
								end
							end
						end
					end
				end
				if R.st.tips then
					for _, tip in ipairs(R.st.tips) do
						if tip.Parent then
							tip.AssemblyLinearVelocity += Vector3.new(math.random(-7, 7), math.random(-4, 8), math.random(-7, 7))
						end
					end
				end
			end
		end
	end)

	------------------------------------------------------------------------------------------------ chambers
	for _, doorB in ipairs(CollectionService:GetTagged("ChamberDoor")) do
		local ch = doorB.Parent
		local spot, inner, exit = ch:FindFirstChild("SubjectSpot"), ch:FindFirstChild("InnerSpot"), ch:FindFirstChild("ExitSpot")
		local door, screen = ch:FindFirstChild("Door"), ch:FindFirstChild("ChamberScreen")
		local pp = doorB:FindFirstChildOfClass("ProximityPrompt")
		if spot and inner and exit and door and pp then
			local subject, st, open, busy = nil, {}, false, false
			local doorHome = door.CFrame
			local idle = string.upper(ch.Name:gsub("Chamber", "Chamber 0"))
			local function alive()
				return subject ~= nil and subject.Parent ~= nil and Dummies.is(subject) and not subject:GetAttribute("Dead")
			end
			local function show()
				if not alive() then
					setText(screen, idle .. " - EMPTY", C(255, 200, 90))
					return
				end
				local names = {}
				for _, id in ipairs(ORDER) do
					if st[id] then
						table.insert(names, LABEL[id])
					end
				end
				setText(screen, #names > 0 and table.concat(names, " + ") or (idle .. " - READY"))
			end
			local function fresh()
				if alive() then
					return
				end
				if subject and subject.Parent then
					Dummies.remove(subject, true)
				end
				st = {}
				subject = Dummies.spawn(spot.CFrame, {})
				if subject then
					subject:SetAttribute("Subject", true)
				end
				show()
			end
			for _, b in ipairs(ch:GetDescendants()) do
				if CollectionService:HasTag(b, "MutateButton") then
					local cd = b:FindFirstChildOfClass("ClickDetector")
					local id = b:GetAttribute("Mut")
					if cd and GROW[id] then
						onClick(cd, function(player)
							if busy or open or not alive() or st[id] or subject:GetAttribute("Ragdolled") then
								sfx("zap", b.Position, 0.3, 0.5)
								return
							end
							busy = true
							local m = subject
							local hum = m:FindFirstChildOfClass("Humanoid")
							local color = b.Color
							local old = b.Size
							b.Size = old * Vector3.new(1, 0.5, 1)
							task.delay(0.15, function()
								b.Size = old
							end)
							st[id] = true
							setText(screen, "MUTATING - " .. LABEL[id], color)
							local okFx, fx = pcall(startFx, ch, m, color, id)
							task.wait(CHARGE)
							local ok, err = pcall(GROW[id], m, hum, st, GROW_T)
							if not ok then
								warn("[Mutations] " .. tostring(id) .. ": " .. tostring(err))
							end
							if player and m.Parent then
								m:SetAttribute("LastHitBy", nil)
							end
							if okFx and fx then
								pcall(finishFx, fx)
							else
								warn("[Mutations] fx: " .. tostring(fx))
							end
							for _ = 1, 3 do -- feet on the floor, whatever it is now
								if m.Parent and hum then
									settle(m, hum)
								end
								task.wait(0.15)
							end
							show()
							busy = false
						end)
					end
				elseif CollectionService:HasTag(b, "ChamberReset") then
					local rp = b:FindFirstChildOfClass("ProximityPrompt")
					if rp then
						onPrompt(rp, function()
							if open or busy then
								return
							end
							busy = true
							if subject and subject.Parent and Dummies.is(subject) then
								Dummies.remove(subject, true)
							end
							subject = nil
							show()
							task.wait(1.2)
							fresh()
							busy = false
						end)
					end
				end
			end
			onPrompt(pp, function()
				if open or busy then
					return
				end
				open = true
				sfx("heavy", door.Position, 0.6, 1.3)
				TweenService:Create(door, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = doorHome * CFrame.new(0, door:GetAttribute("Slide") or -13.6, 0) }):Play()
				if alive() then
					subject:SetAttribute("Subject", nil)
										-- straight down the door's centre line: the old two marks let it cut the corner into the mullion
					local dp = doorHome.Position
					release(subject, st, { inner.Position, Vector3.new(dp.X, inner.Position.Y, dp.Z), Vector3.new(dp.X, inner.Position.Y, dp.Z):Lerp(exit.Position, 0.35), exit.Position })
					setText(screen, "SUBJECT RELEASED", C(255, 120, 90))
				end
				subject, st = nil, {}
				task.wait(8)
				TweenService:Create(door, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = doorHome }):Play()
				task.wait(1.2)
				open = false
				fresh()
			end)
			task.spawn(function()
				task.wait(2 + math.random() * 2)
				while ch.Parent do
					if not open and not busy and not alive() then
						pcall(fresh)
					end
					task.wait(5)
				end
			end)
		end
	end
end

return Mu
