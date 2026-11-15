--!nocheck
-- StormdrawKit.Client.StormFX: the kit's own visual builders, on top of the game's shared libraries (GojoFX: bolts,
-- rings, streaks, sparks; FxLib: parts, tweens, cracks, shockwaves). Client-only and purely cosmetic. Every colour
-- comes in through a palette table (Config.Palette / AltPalette), so nothing here needs touching for a re-skin.
--   StormFX.init(folder)                         the workspace folder every effect is parented under
--   StormFX.thunderTrail(a, b, pal, opts)        the jagged lightning beam a dash leaves between two points
--   StormFX.ghost(char, seconds)                 the character is invisible for that long
--   StormFX.afterimage(char, color, opts)        a glowing frozen copy of the character's current pose
--   StormFX.slashArc(cf, radius, a0, a1, pal, opts)   a sword cut hanging in the air
--   StormFX.crossSlash(pos, dir, pal, size, single)   the cut(s) flashing across a struck body
--   StormFX.skyBolt(pos, pal, opts)              a bolt out of the sky onto a point, with the ground breaking under it
--   StormFX.crackle(getPos, pal, seconds, radius)     static snapping around a moving point
--   StormFX.windIn(getPos, pal, seconds, radius)      wind ribbons spiralling in onto a moving point
--   StormFX.breath(head, pal) -> attachment, emitter  vapour from the mouth (emitter:Emit(n) per breath)
--   StormFX.pillar(pos, pal, width, height, life)     a column of light
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FX = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("GojoFX"))
local Fx2 = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib"))

local StormFX = {}
local UP = Vector3.yAxis
local rng = Random.new()
local root = workspace

function StormFX.init(folder)
	root = folder
end

local function castFolder(name, life)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = root
	Debris:AddItem(f, life or 6)
	return f
end
StormFX.folder = castFolder

local function neon(name, color, parent)
	return Fx2.part(name, Enum.PartType.Block, Enum.Material.Neon, color, parent)
end

-- a block stretched from a to b (its Z runs along the line)
local function seg(part, a, b, thick)
	part.Size = Vector3.new(thick, thick, math.max((b - a).Magnitude, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end
StormFX.seg = seg

---------------------------------------------------------------------------------------------------
-- the mark a dash leaves: a white-hot beam that collapses to a hair, a thick jagged bolt struck over it and re-struck,
-- wandering forks, sparks and light along its length, then little arcs that keep snapping where it was.
-- opts: width (studs), life (seconds the main bolt stands), linger (seconds of after-crackle; 0 = none), forks
function StormFX.thunderTrail(a, b, pal, opts)
	opts = opts or {}
	local span = b - a
	local len = span.Magnitude
	if len < 1 then
		return nil
	end
	local dir = span / len
	local life = opts.life or 0.4
	local linger = opts.linger or 0.5
	local w = opts.width or 1.1
	local f = castFolder("ThunderTrail", life * 2 + linger + 1.5)
	local core = neon("TrailCore", pal.BoltCore, f)
	seg(core, a, b, w * 0.6)
	Fx2.tween(core, life * 0.6, { Size = Vector3.new(0.04, 0.04, len), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local sheath = neon("TrailGlow", pal.Bolt, f)
	sheath.Transparency = 0.5
	seg(sheath, a, b, w * 1.7)
	Fx2.tween(sheath, life, { Size = Vector3.new(0.06, 0.06, len), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- the jag is a share of the length inside FX.bolt: keep its real size about the same for a short hop and a long dash
	local jag = math.clamp(2.6 / len, 0.04, 0.3)
	local segs = math.clamp(math.floor(len / 3.2), 4, 18)
	FX.bolt(f, a, b, { color = pal.Bolt, core = pal.BoltCore, width = w * 0.45, segments = segs, jag = jag, life = life, restrike = 3, light = true })
	local r, u = FX.perp(dir)
	for i = 1, opts.forks or 2 do
		local off = (r * rng:NextNumber(-1, 1) + u * rng:NextNumber(-0.4, 1)).Unit * w * rng:NextNumber(0.8, 1.8)
		FX.bolt(f, a + off * 0.4, b + off * 0.4, {
			color = i == 1 and pal.BoltDeep or pal.Bolt, core = pal.BoltCore, width = w * 0.16, segments = segs, jag = jag * 1.6,
			life = life * 0.8, restrike = 2,
		})
	end
	local n = math.clamp(math.floor(len / 8), 1, 7)
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		FX.light(f, p, pal.Bolt, 6, 28, life + 0.1)
		FX.sparks(f, p, { color = pal.BoltCore, color2 = pal.Bolt, count = 7, speed = { 12, 46 }, size = 0.5, life = 0.45 })
	end
	FX.streaks(f, a, { dir = dir, spread = 10, speed = { len * 2.2, len * 4 }, count = 16, color = pal.BoltCore, color2 = pal.Bolt, size = 0.8, life = 0.22 })
	if linger > 0 then
		task.spawn(function()
			task.wait(life * 0.5)
			local untilT = os.clock() + linger
			while os.clock() < untilT and f.Parent do
				local p = a:Lerp(b, rng:NextNumber())
				FX.arcs(f, p, rng:NextNumber(1, 2.6), { count = 1, color = pal.Bolt, width = 0.08, life = 0.08, jag = 0.35 })
				task.wait(0.04)
			end
		end)
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- invisibility + afterimages
local ghosts = setmetatable({}, { __mode = "k" }) -- [character] = { untilT, items = { [part or decal] = its own transparency } }

-- the character (every part and decal, the sword included) is invisible for `seconds`; calls overlap safely
function StormFX.ghost(char, seconds)
	local untilT = os.clock() + seconds
	local g = ghosts[char]
	if g then
		g.untilT = math.max(g.untilT, untilT)
		return
	end
	g = { untilT = untilT, items = {} }
	ghosts[char] = g
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			g.items[d] = d.Transparency
			d.Transparency = 1
		end
	end
	task.spawn(function()
		while os.clock() < g.untilT and char.Parent do
			task.wait()
		end
		ghosts[char] = nil
		for inst, tr in pairs(g.items) do
			if inst.Parent then
				inst.Transparency = tr
			end
		end
	end)
end

-- a frozen, glowing copy of the character as it stands now (taken from its real look even while it is ghosted).
-- opts: life, alpha (starting transparency), offset (a CFrame that moves the whole image), material, noSword
function StormFX.afterimage(char, color, opts)
	opts = opts or {}
	local life = opts.life or 0.35
	local g = ghosts[char]
	local model = Instance.new("Model")
	model.Name = "Afterimage"
	local parts = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local tr = g and g.items[d]
			if tr == nil then
				tr = d.Transparency
			end
			-- layered clothing only fits through its WrapLayer; a bare clone would hang wrong, so the body under it shows
			local skip = tr >= 0.9 or d:FindFirstChildOfClass("WrapLayer") ~= nil
				or (opts.noSword and d:FindFirstAncestor("StormKatana") ~= nil)
			local c = not skip and d:Clone() or nil
			if c then
				for _, ch in ipairs(c:GetChildren()) do
					if ch:IsA("SpecialMesh") then
						ch.TextureId = ""
					else
						ch:Destroy()
					end
				end
				c.Anchored = true
				c.CanCollide, c.CanQuery, c.CanTouch = false, false, false
				c.CastShadow = false
				c.Material = opts.material or Enum.Material.Neon
				c.Color = color
				c.Transparency = opts.alpha or 0.35
				if c:IsA("MeshPart") then
					c.TextureID = ""
				end
				c.CFrame = opts.offset and opts.offset * d.CFrame or d.CFrame
				c.Parent = model
				table.insert(parts, c)
			end
		end
	end
	model.Parent = root
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, c in ipairs(parts) do
		TweenService:Create(c, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(model, life + 0.1)
	return model
end

---------------------------------------------------------------------------------------------------
-- sword cuts

-- a cut hanging in the air: a crescent in the XZ plane of `cf`, from angle a0 to a1 (degrees: 0 = straight ahead of
-- cf, + = toward its right), `radius` out, fading tip to tip in the order the blade travelled. Roll cf for a diagonal.
-- opts: width, life, segments
function StormFX.slashArc(cf, radius, a0, a1, pal, opts)
	opts = opts or {}
	local n = opts.segments or 12
	local life = opts.life or 0.2
	local width = opts.width or 1.5
	local f = castFolder("SlashArc", life * 1.5 + 0.4)
	local pts = {}
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		pts[i] = cf * Vector3.new(math.sin(a) * radius, 0, -math.cos(a) * radius)
	end
	local upv = cf.UpVector
	local centre = cf.Position
	for layer = 1, 2 do
		for i = 1, n do
			local mid = 1 - math.abs(((i - 0.5) / n) * 2 - 1) -- 0 at the tips, 1 in the middle
			local p0, p1 = pts[i - 1], pts[i]
			local w = (layer == 1 and 0.4 or 1) * width * (0.1 + 0.9 * mid)
			local m = (p0 + p1) / 2
			local out = (m - centre)
			out = out.Magnitude > 1e-3 and out.Unit or cf.LookVector
			local shift = layer == 1 and 0 or -w * 0.22 -- the glow trails inside the bright edge
			local p = neon("Arc", layer == 1 and pal.BoltCore or pal.Slash, f)
			p.Size = Vector3.new(w, layer == 1 and 0.08 or 0.05, (p1 - p0).Magnitude * 1.1)
			p.CFrame = CFrame.lookAt(m + out * shift, p1 + out * shift, upv)
			p.Transparency = layer == 1 and 0.05 or 0.4
			TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, (i / n) * life * 0.3),
				{ Size = Vector3.new(0.03, 0.03, p.Size.Z), Transparency = 1 }):Play()
		end
	end
	FX.light(f, centre + cf.LookVector * radius * 0.8, pal.Slash, 3, 16, life)
	return f
end

-- the cut flashing across a struck body: two crossing blades of light (one, at a random tilt, when single)
function StormFX.crossSlash(pos, dir, pal, size, single)
	local f = castFolder("CrossSlash", 0.7)
	local r, u = FX.perp(dir)
	local tilts = single and { rng:NextNumber(-55, 55) } or { 38, -38 }
	for _, tilt in ipairs(tilts) do
		local a = math.rad(tilt + rng:NextNumber(-8, 8))
		local axis = r * math.cos(a) + u * math.sin(a)
		for layer = 1, 2 do
			local w = layer == 1 and 0.16 or 0.5
			local p = neon("Cut", layer == 1 and pal.BoltCore or pal.Slash, f)
			p.Size = Vector3.new(w, w, size * 0.3)
			p.CFrame = CFrame.lookAt(pos, pos + axis)
			p.Transparency = layer == 1 and 0 or 0.45
			Fx2.tween(p, 0.07, { Size = Vector3.new(w, w, size) }, Enum.EasingStyle.Quart)
			task.delay(0.07, function()
				if p.Parent then
					Fx2.tween(p, 0.2, { Size = Vector3.new(0.02, 0.02, size * 1.25), Transparency = 1 })
				end
			end)
		end
	end
	FX.glow(f, pos, size * 0.9, pal.Slash, 0.22)
	return f
end

---------------------------------------------------------------------------------------------------
-- a bolt out of the sky onto `pos`: the stroke and its column of light, forks, and the ground breaking where it lands.
-- opts: power (scales everything), height, width, forks, cracks (false = no ground damage look)
function StormFX.skyBolt(pos, pal, opts)
	opts = opts or {}
	local k = opts.power or 1
	local f = castFolder("SkyBolt", 7.5)
	local top = pos + UP * (opts.height or 140) + Vector3.new(rng:NextNumber(-18, 18), 0, rng:NextNumber(-18, 18))
	local w = (opts.width or 1.6) * k
	FX.bolt(f, top, pos, { color = pal.Bolt, core = pal.BoltCore, width = w, segments = 14, jag = 0.07, life = 0.3, restrike = 3, light = true })
	local h = (top - pos).Magnitude
	local beam = Fx2.part("BoltColumn", Enum.PartType.Cylinder, Enum.Material.Neon, pal.BoltCore, f)
	beam.Size = Vector3.new(h, w * 2.6, w * 2.6)
	beam.CFrame = CFrame.lookAt((top + pos) / 2, top) * CFrame.Angles(0, math.rad(90), 0)
	beam.Transparency = 0.25
	Fx2.tween(beam, 0.28, { Size = Vector3.new(h, 0.05, 0.05), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _ = 1, opts.forks or 3 do
		local from = pos:Lerp(top, rng:NextNumber(0.15, 0.6))
		local out = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.9, -0.2), rng:NextNumber(-1, 1)).Unit
		FX.bolt(f, from, from + out * rng:NextNumber(14, 34) * k, { color = pal.BoltDeep, core = pal.BoltCore, width = w * 0.3, jag = 0.16, life = 0.22, restrike = 1 })
	end
	FX.glow(f, pos + UP * 2, 34 * k, pal.BoltCore, 0.35)
	FX.glow(f, pos + UP * 2, 60 * k, pal.Bolt, 0.5, { alpha = 0.35 })
	FX.ring(f, pos + UP * 0.4, UP, 4, 46 * k, pal.Bolt, 0.5)
	FX.ring(f, pos + UP * 0.4, UP, 2, 26 * k, pal.BoltCore, 0.35)
	Fx2.shockwave(f, pos + UP, UP, 4, 40 * k, pal.Bolt, 0.5)
	FX.shell(f, pos + UP * 2, 2, 11 * k, pal.BoltCore, 0.3)
	FX.sparks(f, pos + UP, { color = pal.BoltCore, color2 = pal.Bolt, count = math.floor(46 * k), speed = { 30, 110 }, size = 0.8, life = 0.9 })
	FX.streaks(f, pos + UP, { dir = UP, spread = 70, speed = { 60, 170 }, count = math.floor(30 * k), color = pal.BoltCore, color2 = pal.Bolt, size = 1.1 })
	FX.arcs(f, pos + UP * 2, 9 * k, { count = 6, outward = true, colors = { pal.Bolt, pal.BoltDeep, pal.BoltCore }, width = 0.22, life = 0.18 })
	if opts.cracks ~= false then
		Fx2.cracks(f, pos, UP, 9 * k, pal.Bolt, 5)
		FX.rubble(f, pos, { count = math.floor(12 * k), radius = 4, up = { 30, 60 }, out = { 14, 36 } })
		Fx2.dust(f, pos, 8 * k, 8)
	end
	return f
end

-- a column of light that thins away
function StormFX.pillar(pos, pal, width, height, life)
	local f = castFolder("Pillar", life + 0.5)
	for layer = 1, 2 do
		local p = Fx2.part("Pillar", Enum.PartType.Cylinder, Enum.Material.Neon, layer == 1 and pal.BoltCore or pal.Bolt, f)
		local w = width * (layer == 1 and 0.5 or 1)
		p.Size = Vector3.new(height, w, w)
		p.CFrame = CFrame.new(pos + UP * height / 2) * CFrame.Angles(0, 0, math.rad(90))
		p.Transparency = layer == 1 and 0.1 or 0.55
		Fx2.tween(p, life, { Size = Vector3.new(height, 0.05, 0.05), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	return f
end

---------------------------------------------------------------------------------------------------
-- static snapping around a moving point for `seconds` (getPos() -> Vector3 | nil each tick)
function StormFX.crackle(getPos, pal, seconds, radius, every)
	local f = castFolder("Crackle", seconds + 1)
	task.spawn(function()
		local untilT = os.clock() + seconds
		while os.clock() < untilT and f.Parent do
			local p = getPos()
			if p then
				FX.arcs(f, p, radius * rng:NextNumber(0.6, 1.2), { count = 1, colors = { pal.Bolt, pal.BoltCore, pal.BoltDeep }, width = 0.07, life = 0.07, jag = 0.4 })
				if rng:NextNumber() < 0.5 then
					FX.sparks(f, p, { color = pal.BoltCore, color2 = pal.Bolt, count = 3, speed = { 6, 22 }, size = 0.35, life = 0.35 })
				end
			end
			task.wait(every or 0.04)
		end
	end)
	return f
end

-- wind drawn in: ribbons spiral down onto getPos() over `seconds`, from `radius` studs out
function StormFX.windIn(getPos, pal, seconds, radius)
	local f = castFolder("WindIn", seconds + 1.2)
	local ribbons = {}
	local count = 14
	for i = 1, count do
		local p = Fx2.part("Wind", Enum.PartType.Ball, Enum.Material.Neon, pal.Mist, f)
		p.Transparency = 1
		p.Size = Vector3.one * 0.2
		local trail = FX.trail(p, ColorSequence.new(pal.Mist, i % 3 == 0 and pal.Bolt or pal.Calm), 0.55, 0.3, { tail = 0, alpha = 0.25 })
		ribbons[i] = { part = p, trail = trail, ang = rng:NextNumber(0, math.pi * 2), y = rng:NextNumber(-2.5, 3),
			t0 = (i / count) * seconds * 0.5, spin = rng:NextNumber(7, 11) }
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local c = getPos()
		if t >= seconds or not c or not f.Parent then
			conn:Disconnect()
			for _, r in ipairs(ribbons) do
				r.trail.Enabled = false
			end
			return
		end
		for _, r in ipairs(ribbons) do
			local k = math.clamp((t - r.t0) / (seconds * 0.45), 0, 1) -- 0 at the rim -> 1 at the chest
			local rad = radius * (1 - k) ^ 1.4 + 0.3
			local a = r.ang + k * r.spin
			r.part.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * rad, r.y * (1 - k), math.sin(a) * rad))
		end
	end)
	return f
end

-- vapour from the mouth: returns the attachment (destroy it to stop) and its emitter (Emit(n) once per breath)
function StormFX.breath(head, pal)
	local a = Instance.new("Attachment")
	a.Name = "StormBreath"
	a.CFrame = CFrame.new(0, -0.22, -head.Size.Z / 2 - 0.05)
	a.Parent = head
	local e = FX.emitter(a, {
		Texture = FX.TEX.smoke, Color = ColorSequence.new(pal.Mist), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(14, 14), EmissionDirection = Enum.NormalId.Front, Drag = 3, Acceleration = Vector3.new(0, 1.5, 0),
		Size = FX.nsk({ { 0, 0.25 }, { 1, 1.5 } }), Transparency = FX.nsk({ { 0, 0.45 }, { 1, 1 } }), Rotation = NumberRange.new(0, 360),
		LightEmission = 0.6, Brightness = 1.2,
	})
	return a, e
end

return StormFX
