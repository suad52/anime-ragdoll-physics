--!nocheck
-- ServerScriptService.Sandbox.Gore (2026-11-14, owner: "make the injuries and blood spill and such on the npcs a lot
-- more realistic and gore-y"): the blood that LEAVES a body. Sandbox.Injury decides what happened, Sandbox.Wounds
-- draws it on the body, this draws it in the world. All of it is cosmetic - nothing here collides or is queried,
-- except the thrown scraps (Gore.gibs) - and all of it is capped by Config.GORE.
--   Gore.spray(pos, dir, o)  a burst: particles in the air, plus DROPLETS that fly on real arcs (raycast here, so
--                            every player sees the same stains) and leave a mark where each lands - stretched along
--                            its path, running down a wall, darkening as it dries. o = { n = droplets, particles,
--                            speed, spread (degrees), size, mist }
--   Gore.spurt(pos, dir, count, speed)   the old call (Hazards / Machines / Beasts): the same burst
--   Gore.pool(pos, size)     a puddle with an uneven edge
--   Gore.feed(rec, pos, amount) -> rec   the puddle UNDER a bleeding body: it grows with the blood actually lost
--   Gore.drop(pos, size, vel)  one drip (the trail under a bleeding body that is being moved)
--   Gore.gibs(pos, dir, n)   torn scraps and bone chips, thrown; each leaves a stain where it comes down
--   Gore.emitter(parent, speed, spread) -> the droplet ParticleEmitter (Injury's pulsing arteries use it)
--   Gore.sfx(key, pos, vol, speed)
-- Part names Blood / Splat / Gib and the emitter name BloodFx are what SandboxClient hides for a player with BLOOD off.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Sandbox"):WaitForChild("Config"))

local Gore = {}
local CFG = Config.GORE or {}
local AMOUNT = tonumber(CFG.Amount) or 1
local MAX_SPLATS, MAX_POOLS, MAX_GIBS, LIFE = CFG.Splats or 220, CFG.Pools or 90, CFG.Gibs or 36, CFG.Life or 90
local RANGE = CFG.Range or 150 -- blood is only drawn where a player is this near: the machines never stop, all over the map
local C = Color3.fromRGB
-- fresh arterial blood is bright, pooled blood is dark, dried blood is nearly brown
-- (dark on purpose: the map is lit bright, and anything lighter reads as red paint. No Reflectance anywhere either -
-- a glossy dark red mirrors the sky and turns purple.)
local FRESH, BLOOD, DARK, DRY = C(112, 5, 9), C(90, 4, 8), C(54, 3, 6), C(38, 10, 8)
local MUSCLE, FLESH, BONE = C(142, 24, 28), C(98, 14, 18), C(232, 224, 204)
Gore.COLORS = { FRESH = FRESH, BLOOD = BLOOD, DARK = DARK, DRY = DRY, MUSCLE = MUSCLE, FLESH = FLESH, BONE = BONE,
	FAT = C(216, 180, 122), MARROW = C(150, 62, 52), PIT = C(24, 2, 4) }
local GRAV = Vector3.new(0, -90, 0) -- what a drop falls at (the particles use the same, so they land together)
local SND = { wet = 9125703162, slash = 125132253621935 }
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local folder
function Gore.folder()
	if not folder or not folder.Parent then
		folder = workspace:FindFirstChild("Gore") or Instance.new("Folder")
		folder.Name = "Gore"
		folder.Parent = workspace
	end
	return folder
end
local function tween(o, t, props, style)
	TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end
local function fxPart(size, color, mat)
	local p = Instance.new("Part")
	p.Size, p.Color, p.Material = size, color, mat or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	return p
end
Gore.fxPart = fxPart
-- a squashed sphere: a stain with a round edge that can be stretched into a streak
local function blob(size, color)
	local p = fxPart(size, color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end
Gore.blob = blob
-- a random direction lying in the surface whose normal is n
local function tangent(n)
	local t = n:Cross(math.abs(n.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
	return CFrame.fromAxisAngle(n, math.random() * math.pi * 2):VectorToWorldSpace(t)
end
-- a frame lying on a surface: Y out of it, Z (the length) along `along`
local function lay(pos, n, along)
	return CFrame.fromMatrix(pos, n:Cross(-along), n, -along)
end

function Gore.sfx(key, pos, vol, speed)
	local a = Instance.new("Attachment")
	a.Position = pos -- (Terrain sits at the origin, so this is world space)
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. string.format("%d", SND[key] or SND.wet)
	s.Volume, s.PlaybackSpeed = vol or 0.6, (speed or 1) * (0.92 + math.random() * 0.16)
	s.RollOffMinDistance, s.RollOffMaxDistance, s.RollOffMode = 10, 160, Enum.RollOffMode.InverseTapered
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 4)
end

-------------------------------------------------------------------------------------------------- where blood lands
local eyes, eyesAt = {}, 0
local function near(pos)
	local t = os.clock()
	if t - eyesAt > 0.5 then
		eyesAt = t
		table.clear(eyes)
		for _, p in ipairs(Players:GetPlayers()) do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if r then
				table.insert(eyes, r.Position)
			end
		end
	end
	for _, e in ipairs(eyes) do
		if (e - pos).Magnitude <= RANGE then
			return true
		end
	end
	return false
end
Gore.near = near
local rayP = RaycastParams.new()
rayP.FilterType = Enum.RaycastFilterType.Exclude
rayP.IgnoreWater = true
local filterAt = 0
local function aimRays() -- drops fly through bodies, players and other gore: they land on the world
	local t = os.clock()
	if t - filterAt < 1 then
		return
	end
	filterAt = t
	local list = { Gore.folder() }
	for _, n in ipairs({ "NPCs", "FX", "LocalFX" }) do
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
	rayP.FilterDescendantsInstances = list
end
-- a budget of stains a second, so a minigun into a crowd cannot run the server into the ground
local tokens, tokenAt = 60, os.clock()
local function take()
	local t = os.clock()
	tokens = math.min(80, tokens + (t - tokenAt) * 60)
	tokenAt = t
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

local splats = {} -- { part (its second lobe and specks are its children), run?, host?, hostCF?, born, dryAt, dry }
local function stain(hit, vel, size)
	local inst = hit.Instance
	if not inst or not inst.Parent or size <= 0 then
		return
	end
	local host
	if inst ~= workspace.Terrain then
		local m = inst:FindFirstAncestorWhichIsA("Model")
		if m and m:FindFirstChildOfClass("Humanoid") then
			return -- never on a character
		end
		host = inst
	end
	local n = hit.Normal
	local vt = vel - n * vel:Dot(n)
	local graze = vt.Magnitude / math.max(vel.Magnitude, 1e-3) -- 0 = straight in, 1 = skimming the surface
	local along = vt.Magnitude > 0.5 and vt.Unit or tangent(n)
	local w = size * (1 - graze * 0.35)
	local len = w * (1 + graze * 2.3)
	local color = FRESH:Lerp(DARK, math.random() * 0.6)
	local p = blob(Vector3.new(w, 0.04, len), color)
	p.Name = "Splat"
	p.Transparency = 0.06
	local at = hit.Position + n * (0.016 + math.random() * 0.02)
	p.CFrame = lay(at + along * ((len - w) / 2), n, along) -- the round end where it hit, the tail the way it was going
	local rec = { part = p, born = os.clock(), dryAt = 16 + math.random() * 14 }
	if host and not host.Anchored then
		-- a crate, a gas can, the train: the stain rides it (and goes when it goes)
		local wc = Instance.new("WeldConstraint")
		wc.Part0, wc.Part1 = host, p
		wc.Parent = p
		p.Parent = host
	else
		p.Anchored = true
		p.Parent = Gore.folder()
		if host then
			rec.host, rec.hostCF = host, host.CFrame -- a door, a press, a trapdoor: the sweep below drops the stain if it moves
		end
		-- no stain is a clean oval: a bigger one gets a second lobe across it, and most throw a speck or two on ahead
		local side = n:Cross(along)
		local function extra(sz, pos, dir)
			local b = blob(sz, color)
			b.Name = "Splat"
			b.Transparency = 0.06
			b.Anchored = true
			b.CFrame = lay(pos, n, dir)
			b.Parent = p
		end
		if w >= 0.42 then
			extra(Vector3.new(w * (0.5 + math.random() * 0.3), 0.038, w * (0.6 + math.random() * 0.4)),
				at + side * ((math.random() - 0.5) * w * 0.5) + along * (math.random() * w * 0.3), (along + side * ((math.random() - 0.5) * 1.6)).Unit)
		end
		if w >= 0.2 then
			for _ = 1, math.random(0, 2) do
				local s = w * (0.12 + math.random() * 0.2)
				local dirS = (along + side * ((math.random() - 0.5) * 1.4)).Unit
				extra(Vector3.new(s, 0.03, s * (1 + graze * 1.5 + math.random() * 0.5)), at + dirS * (len * 0.5 + w * (0.25 + math.random() * 0.7)), dirS)
			end
		end
		-- on a wall it runs
		if n.Y < 0.45 and w >= 0.24 and math.random() < 0.7 then
			local d = Vector3.new(0, -1, 0)
			d = d - n * d:Dot(n)
			if d.Magnitude > 0.3 then
				d = d.Unit
				local runLen = (0.5 + math.random() * 1.7) * math.clamp(w / 0.5, 0.6, 1.5)
				if not workspace:Raycast(at + n * 0.3 + d * runLen, -n * 0.7, rayP) then
					runLen *= 0.35 -- the wall ends below it
				end
				local rw = w * (0.22 + math.random() * 0.14)
				local run = blob(Vector3.new(rw, 0.04, 0.12), color)
				run.Name = "Splat"
				run.Transparency = 0.06
				run.Anchored = true
				run.CFrame = lay(at, n, d)
				run.Parent = Gore.folder()
				tween(run, 1.4 + runLen * 1.3, { Size = Vector3.new(rw, 0.04, runLen), CFrame = lay(at + d * (runLen / 2), n, d) }, Enum.EasingStyle.Sine)
				rec.run = run
			end
		end
	end
	table.insert(splats, rec)
	while #splats > MAX_SPLATS do
		local old = table.remove(splats, 1)
		old.part:Destroy()
		if old.run then
			old.run:Destroy()
		end
	end
end
-- one drop's flight: nine short steps of a real arc, then straight down. Returns where it lands, how fast, and when.
local function fly(pos, vel)
	local p, v, t = pos, vel, 0
	for _ = 1, 9 do
		local step = v * 0.06 + GRAV * 0.0018
		local hit = workspace:Raycast(p, step, rayP)
		if hit then
			local f = (hit.Position - p).Magnitude / math.max(step.Magnitude, 1e-3)
			return hit, v + GRAV * (0.06 * f), t + 0.06 * f
		end
		p += step
		v += GRAV * 0.06
		t += 0.06
	end
	local hit = workspace:Raycast(p, Vector3.new(v.X * 0.3, -70, v.Z * 0.3), rayP)
	if hit then
		local fall = math.max(p.Y - hit.Position.Y, 0.1)
		return hit, Vector3.new(v.X * 0.4, -math.sqrt(180 * fall), v.Z * 0.4), t + math.sqrt(fall / 45)
	end
	return nil
end

------------------------------------------------------------------------------------------------------- in the air
function Gore.emitter(parent, speed, spread)
	local e = Instance.new("ParticleEmitter")
	e.Name = "BloodFx"
	e.Texture = SMOKE
	e.Color = ColorSequence.new(FRESH, DARK)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.26), NumberSequenceKeypoint.new(1, 0.09) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.35, 0.75)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = GRAV
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = 0
	e.LightInfluence = 1
	e.Parent = parent
	return e
end
local function emit(pos, dir, count, speed, spread, mist)
	local a = Instance.new("Attachment")
	a.CFrame = CFrame.lookAt(pos, pos + dir)
	local e = Gore.emitter(a, speed, spread)
	local m
	if mist and count >= 6 then -- the fine red haze round a hard hit
		m = Instance.new("ParticleEmitter")
		m.Name = "BloodFx"
		m.Texture = SMOKE
		m.Color = ColorSequence.new(FRESH)
		m.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.7) })
		m.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		m.Lifetime = NumberRange.new(0.25, 0.5)
		m.Speed = NumberRange.new(2, math.max(3, speed * 0.35))
		m.SpreadAngle = Vector2.new(spread + 20, spread + 20)
		m.Acceleration = Vector3.new(0, -12, 0)
		m.EmissionDirection = Enum.NormalId.Front
		m.Rate = 0
		m.LightInfluence = 1
		m.Parent = a
	end
	a.Parent = workspace.Terrain
	e:Emit(math.ceil(count * 1.4))
	if m then
		m:Emit(math.ceil(count / 4))
	end
	Debris:AddItem(a, 1.6)
	return a, e
end
function Gore.spray(pos, dir, o)
	o = o or {}
	dir = (typeof(dir) == "Vector3" and dir.Magnitude > 0.01) and dir.Unit or Vector3.yAxis
	local speed, spread = o.speed or 16, o.spread or 30
	if not near(pos) then
		return nil -- nobody is close enough to see it
	end
	local count = (o.particles == nil) and 10 or o.particles
	local a, e
	if count > 0 then
		a, e = emit(pos, dir, count, speed, spread, o.mist)
	end
	local n = math.floor((o.n or 3) * AMOUNT + 0.5)
	if n > 0 then
		aimRays()
		local base = CFrame.lookAt(pos, pos + dir)
		for _ = 1, n do
			if not take() then
				break
			end
			local d = (base * CFrame.Angles(math.rad((math.random() - 0.5) * 2 * spread), math.rad((math.random() - 0.5) * 2 * spread), 0)).LookVector
			local hit, v, t = fly(pos, d * speed * (0.45 + math.random() * 0.6))
			if hit then
				task.delay(t, stain, hit, v, (o.size or 0.5) * (0.3 + math.random() ^ 2 * 1.1)) -- mostly small, now and then a big one
			end
		end
	end
	return a, e
end
function Gore.spurt(pos, dir, count, speed)
	count = count or 10
	return Gore.spray(pos, dir, { particles = count, n = math.ceil(count / 6), speed = speed or 14, spread = 34, size = 0.55, mist = count >= 16 })
end
function Gore.drop(pos, size, vel)
	if not near(pos) or not take() then
		return
	end
	aimRays()
	local hit = workspace:Raycast(pos, Vector3.new(0, -16, 0), rayP)
	if hit then
		local v = Vector3.new(0, -24, 0)
		if typeof(vel) == "Vector3" then
			v += vel * Vector3.new(1, 0, 1)
		end
		stain(hit, v, size or 0.5)
	end
end

------------------------------------------------------------------------------------------------------------ pools
local pools = {} -- { part, born, dryAt, dry }
local function disc(pos, n, size, grow)
	local d = Instance.new("Part")
	d.Name = "Blood"
	d.Shape = Enum.PartType.Cylinder
	d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
	d.Material, d.Color = Enum.Material.SmoothPlastic, BLOOD:Lerp(DARK, math.random() * 0.7)
	d.Size = Vector3.new(0.05, 0.3, 0.3)
	local t = tangent(n)
	d.CFrame = CFrame.fromMatrix(pos + n * (0.028 + math.random() * 0.02), n, t, n:Cross(t)) -- (a cylinder's axis is X)
	d.Parent = Gore.folder()
	tween(d, grow or 5, { Size = Vector3.new(0.05, size, size) })
	local rec = { part = d, born = os.clock(), dryAt = 40 + math.random() * 15 }
	table.insert(pools, rec)
	while #pools > MAX_POOLS do
		table.remove(pools, 1).part:Destroy()
	end
	return rec
end
local function floorAt(pos, reach)
	aimRays()
	local hit = workspace:Raycast(pos + Vector3.new(0, 1.2, 0), Vector3.new(0, -(reach or 14), 0), rayP)
	if hit and hit.Normal.Y >= 0.6 and (hit.Instance == workspace.Terrain or hit.Instance.Anchored) then
		return hit
	end
	return nil
end
-- an arm of a puddle: only where there is floor at about the same height, so nothing hangs over an edge
local function lobe(hit, size, grow)
	local off = tangent(hit.Normal) * size * (0.3 + math.random() * 0.22)
	local h2 = workspace:Raycast(hit.Position + off + hit.Normal * 1.2, -hit.Normal * 2, rayP)
	if h2 and h2.Normal.Y >= 0.6 and math.abs(h2.Position.Y - hit.Position.Y) < 0.6 and (h2.Instance == workspace.Terrain or h2.Instance.Anchored) then
		disc(h2.Position, h2.Normal, size * (0.32 + math.random() * 0.3), grow)
	end
end
function Gore.pool(pos, size)
	if not near(pos) then
		return
	end
	local hit = floorAt(pos)
	if not hit then
		return
	end
	size = math.min(size or (2 + math.random() * 1.5), 4) -- (a body's worth of blood is a puddle four or five studs across)
	disc(hit.Position, hit.Normal, size, 5)
	for _ = 1, math.random(2, 4) do
		lobe(hit, size, 6)
	end
end
function Gore.feed(rec, pos, amount)
	if not near(pos) then
		return rec
	end
	if rec and (not rec.main.part.Parent or ((rec.c - pos) * Vector3.new(1, 0, 1)).Magnitude > 3.2 or math.abs(rec.c.Y - pos.Y) > 5) then
		rec = nil -- the body has moved on: that puddle stays where it is and a new one starts
	end
	if not rec then
		local hit = floorAt(pos, 7)
		if not hit then
			return nil
		end
		rec = { hit = hit, c = hit.Position, vol = 0, size = 0.6, lobes = 0, main = disc(hit.Position, hit.Normal, 0.6, 0.6) }
	end
	rec.vol += amount
	rec.main.born = os.clock() -- still being fed: it does not dry or fade yet
	local target = math.min(3.8, 0.8 + math.sqrt(rec.vol) * 0.42) -- (vol = % of its blood on the floor so far)
	if target > rec.size + 0.12 then
		rec.size = target
		tween(rec.main.part, 1, { Size = Vector3.new(0.05, target, target) }, Enum.EasingStyle.Linear)
		if rec.lobes < 5 and target > 1.3 + rec.lobes * 0.5 then
			rec.lobes += 1
			lobe(rec.hit, target, 8)
		end
	end
	return rec
end

----------------------------------------------------------------------------------------------------------- scraps
local liveGibs = 0
function Gore.gibs(pos, dir, n)
	if not near(pos) then
		return
	end
	n = math.floor((n or 3) * AMOUNT + 0.5)
	dir = (typeof(dir) == "Vector3" and dir.Magnitude > 0.01) and dir.Unit or Vector3.yAxis
	for i = 1, n do
		if liveGibs >= MAX_GIBS then
			break
		end
		liveGibs += 1
		local bone = i % 3 == 0
		local s = 0.2 + math.random() * 0.3
		local p = Instance.new("Part")
		p.Name = "Gib"
		p.Size = bone and Vector3.new(0.1 + math.random() * 0.05, 0.3 + math.random() * 0.3, 0.1) or Vector3.new(s, s * (0.5 + math.random() * 0.4), s * (0.7 + math.random() * 0.6))
		p.Color = bone and BONE or (math.random() < 0.5 and MUSCLE or FLESH)
		p.Material = Enum.Material.SmoothPlastic
				p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CanTouch, p.CastShadow = false, false
		p.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.8, 0.02) -- wet: it lands and stays, no bounce
		pcall(function()
			p.CollisionGroup = "Ragdolls"
		end)
		if not bone then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		p.CFrame = CFrame.new(pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.6) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = Gore.folder()
		p.AssemblyLinearVelocity = dir * (5 + math.random() * 15) + Vector3.new((math.random() - 0.5) * 16, 7 + math.random() * 14, (math.random() - 0.5) * 16)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 40
		for _, t in ipairs({ 0.55 + math.random() * 0.4, 1.5 + math.random() }) do
			task.delay(t, function()
				if p.Parent then
					Gore.drop(p.Position, bone and 0.25 or (0.4 + math.random() * 0.5), p.AssemblyLinearVelocity)
				end
			end)
		end
		task.delay(11 + math.random() * 6, function()
			liveGibs -= 1
			if p.Parent then
				tween(p, 2, { Transparency = 1 })
				Debris:AddItem(p, 2.1)
			end
		end)
	end
end

------------------------------------------------------------------------------------------- drying, fading, moving
local function fade(p)
	if p and p.Parent then
		tween(p, 2.5, { Transparency = 1 })
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("BasePart") then
				tween(c, 2.5, { Transparency = 1 })
			end
		end
		Debris:AddItem(p, 2.6)
	end
end
local function paint(p, c)
	if p and p.Parent then
		p.Color = c
		for _, k in ipairs(p:GetChildren()) do
			if k:IsA("BasePart") then
				k.Color = c
			end
		end
	end
end
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.5 then
		return
	end
	acc = 0
	local now = os.clock()
	for i = #splats, 1, -1 do
		local r = splats[i]
		local p = r.part
		local age = now - r.born
		if not p.Parent then
			if r.run then
				r.run:Destroy()
			end
			table.remove(splats, i)
		elseif r.host and (not r.host.Parent or r.host.CFrame ~= r.hostCF) then
			p:Destroy() -- what it landed on has moved away from under it
			if r.run then
				r.run:Destroy()
			end
			table.remove(splats, i)
		elseif age > LIFE then
			table.remove(splats, i)
			fade(p)
			fade(r.run)
		elseif age > r.dryAt and (r.dry or 0) < 2 then
			-- drying: two steps darker. Not a tween - hundreds of colour tweens would be hundreds of updates a frame.
			r.dry = (r.dry or 0) + 1
			r.dryAt += 12
			local c = p.Color:Lerp(DRY, 0.55)
			paint(p, c)
			paint(r.run, c)
		end
	end
	for i = #pools, 1, -1 do
		local r = pools[i]
		local p = r.part
		local age = now - r.born
		if not p.Parent then
			table.remove(pools, i)
		elseif age > LIFE then
			table.remove(pools, i)
			fade(p)
		elseif age > r.dryAt and (r.dry or 0) < 2 then
			r.dry = (r.dry or 0) + 1
			r.dryAt += 14
			p.Color = p.Color:Lerp(DRY, 0.5)
		end
	end
end)

return Gore
