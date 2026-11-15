-- ServerStorage.CityGen.Kit - the shared helper kit every NEON SHIBUYA builder uses (city architect, 2026-11-06).
-- Read CONTRACT.md first. The kit is FROZEN for builders: never edit it; ask the orchestrator if something is missing.
--
-- Usage inside a generator ModuleScript (ServerStorage.CityGen.<District>):
--   local Kit = require(script.Parent.Kit)
--   local M = {}
--   function M.build(root)              -- root = workspace.City.<District>
--       Kit.clear(root)                 -- idempotence: wipe only what this district built
--       local B = Kit.new(root, { seed = 7 })
--       B:shell(root, { x0 = .., z0 = .., x1 = .., z1 = .., h = 60, style = "tile" })
--       ...
--       print((select(2, B:audit())))
--   end
--   return M
--
-- Conventions every helper follows:
--   * "cf" for anything mounted on a wall / facing something: Position = centre (or bottom-centre where noted),
--     LookVector = OUTWARD, toward the viewer. Text goes on the part's Front face, which faces cf.LookVector.
--   * "cf" for a floor object (prop, stairs, ladder): Position = the floor contact point (bottom centre),
--     LookVector = the object's front.
--   * Parts are Anchored, CanTouch false, smooth surfaces; CanQuery follows CanCollide; CastShadow only for parts
--     >= 10 studs that are not Neon / see-through. Decor (neon, trim, window bands) is CanCollide + CanQuery false.
--   * Every helper counts what it makes (parts, lights, SurfaceGuis) and yields with task.wait() every 250 parts.

local CollectionService = game:GetService("CollectionService")
local Plan = require(script.Parent:WaitForChild("Plan"))

local Kit = {}
Kit.VERSION = "1.0 (2026-11-06)"
Kit.Plan = Plan
Kit.C = Plan.palette
Kit.M = Plan.materials
Kit.Y = Plan.Y
Kit.FONT = Plan.fonts
Kit.R = Plan.R

-- destruction tagging contract (see CONTRACT.md section 4)
Kit.TAG = {
	GLASS = "CityGlass", -- single BasePart: window / storefront / screen face -> shatters (hidden + client shards)
	PANEL = "CityPanel", -- single BasePart or Model+PrimaryPart: cladding, signs, railings, interior wall chunks -> flies off
	PROP = "CityProp", -- Model+PrimaryPart: cars, vending, lamps, signals, benches, AC units -> physics assembly, flung
	MARK = "CityMark", -- thin non-colliding part: road markings, curbs, manholes, puddles -> hidden only
	SCREEN = "CityScreen", -- screen face with SurfaceGui "Screen" (client animates; attrs Playlist, Brand)
	SIGNAL = "CitySignal", -- signal lamp part (attrs Group, Lamp) - Streets' Signals script drives every one of them
	FLICKER = "CityFlicker", -- neon part the client flickers now and then
	STEAM = "CitySteam", -- Attachment where the client puffs steam (attrs Rate, Size)
	HOLO = "CityHolo", -- hologram part the client spins / pulses (attrs Spin, Pulse)
	LIFT = "CityLift", -- lift pad (Towers) - attrs LiftId, To
}
Kit.HP = { GLASS = 8, PANEL = 30, PROP = 50, MARK = 1 } -- defaults the destruction service assumes when no HP attribute
Kit.REGEN = { GLASS = 20, PANEL = 30, PROP = 40, MARK = 15 } -- seconds before a broken piece tries to come back
Kit.LIMIT = { GLASS = 40, PANEL = 64, PROP = 30 } -- largest dimension a breakable may have (studs)
Kit.CHUNK = 24 -- B:wall cuts tagged (breakable) walls into pieces no taller / longer than this unless o.Chunk is smaller
Kit.STEP = { rise = 1.0, maxRise = 1.2, going = 1.5, maxSlope = 40 } -- walkable stair / ramp rule
Kit.FACES = { N = Vector3.new(0, 0, -1), S = Vector3.new(0, 0, 1), E = Vector3.new(1, 0, 0), W = Vector3.new(-1, 0, 0) }

local C = Kit.C
local V3 = Vector3.new
local CF = CFrame.new
local MAT = Enum.Material
local R = Plan.R

local function color(c)
	if c == nil then
		return nil
	end
	if typeof(c) == "Color3" then
		return c
	end
	if type(c) == "string" then
		local v = C[c]
		if not v then
			error("Kit: unknown palette colour " .. c, 3)
		end
		return v
	end
	error("Kit: bad colour " .. tostring(c), 3)
end
Kit.color = color

local function merge(base, extra)
	if extra then
		for k, v in pairs(extra) do
			base[k] = v
		end
	end
	return base
end

-- "ネオン" -> "ネ\nオ\nン" (tategaki: one glyph per line)
function Kit.vertical(s)
	local t = {}
	for _, code in utf8.codes(s) do
		table.insert(t, utf8.char(code))
	end
	return table.concat(t, "\n")
end

function Kit.folder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function Kit.city()
	return Kit.folder(workspace, "City")
end

function Kit.district(name)
	return Kit.folder(Kit.city(), name)
end

function Kit.snap4(v)
	return Plan.snap4(v)
end

function Kit.ownerAt(x, z, y)
	return Plan.ownerAt(x, z, y)
end

-- CFrame on one face of rect r ("N"/"S"/"E"/"W") at height y: Position = middle of that face at y,
-- LookVector = outward. Returns cf, face width.
function Kit.faceCF(r, face, y)
	y = y or Kit.Y
	local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	local n = Kit.FACES[face] or error("Kit.faceCF: bad face " .. tostring(face))
	local p, w
	if face == "N" then
		p, w = V3(cx, y, r.z0), r.x1 - r.x0
	elseif face == "S" then
		p, w = V3(cx, y, r.z1), r.x1 - r.x0
	elseif face == "E" then
		p, w = V3(r.x1, y, cz), r.z1 - r.z0
	else
		p, w = V3(r.x0, y, cz), r.z1 - r.z0
	end
	return CFrame.lookAt(p, p + n), w
end

-- rect minus a list of rect holes -> list of rects (for slabs with stair wells, lots minus courtyards, ...)
function Kit.subtract(r, holes)
	local out = { r }
	for _, h in ipairs(holes or {}) do
		local nxt = {}
		for _, a in ipairs(out) do
			if not Plan.overlap(a, h) then
				table.insert(nxt, a)
			else
				if h.z0 > a.z0 then
					table.insert(nxt, R(a.x0, a.z0, a.x1, h.z0))
				end
				if h.z1 < a.z1 then
					table.insert(nxt, R(a.x0, h.z1, a.x1, a.z1))
				end
				local z0, z1 = math.max(a.z0, h.z0), math.min(a.z1, h.z1)
				if h.x0 > a.x0 then
					table.insert(nxt, R(a.x0, z0, h.x0, z1))
				end
				if h.x1 < a.x1 then
					table.insert(nxt, R(h.x1, z0, a.x1, z1))
				end
			end
		end
		out = nxt
	end
	return out
end

local function shuffle(t, rng)
	for i = #t, 2, -1 do
		local j = rng:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end
Kit.shuffle = shuffle

function Kit.countParts(inst)
	local n = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- the container street trees go into: workspace.Arena.Decor once the new city Arena exists (attribute CityArena),
-- otherwise the district's own "Decor" folder (re-run the generator after integration to move them)
function Kit.decorFolder(root)
	local arena = workspace:FindFirstChild("Arena")
	if arena and arena:GetAttribute("CityArena") then
		return Kit.folder(arena, "Decor")
	end
	return Kit.folder(root, "Decor")
end

-- idempotence: destroys everything under root (in slices, yielding) plus this district's items in Arena.Decor
function Kit.clear(root, district)
	district = district or root.Name
	local count = 0
	local function kill(inst)
		local kids = inst:GetChildren()
		if #kids > 0 and #inst:GetDescendants() > 400 then
			for _, c in ipairs(kids) do
				kill(c)
			end
		end
		count += 1 + #inst:GetDescendants()
		inst:Destroy()
		if count > 1500 then
			count = 0
			task.wait()
		end
	end
	for _, c in ipairs(root:GetChildren()) do
		kill(c)
	end
	local arena = workspace:FindFirstChild("Arena")
	local decor = arena and arena:FindFirstChild("Decor")
	if decor then
		for _, c in ipairs(decor:GetChildren()) do
			if c:GetAttribute("CityDistrict") == district then
				kill(c)
			end
		end
	end
end

-- runs ServerStorage.CityGen(.copy).<District>.build(root) on its own thread and reports through attributes on
-- workspace.City.<District>: BuildState ("building"/"done"/"error"), BuildError, BuildSeconds, BuildParts.
-- opts.cleanup = an Instance destroyed when the build ends (the fresh CityGen copy). Returns the root at once.
function Kit.runBuild(district, moduleScript, opts)
	opts = opts or {}
	local root = Kit.district(district)
	root:SetAttribute("BuildState", "building")
	root:SetAttribute("BuildError", "")
	root:SetAttribute("BuildStarted", os.time())
	task.spawn(function()
		local t0 = os.clock()
		local ok, err = xpcall(function()
			local gen = require(moduleScript)
			assert(type(gen) == "table" and type(gen.build) == "function", "generator must return { build = function(root) }")
			gen.build(root)
		end, debug.traceback)
		root:SetAttribute("BuildSeconds", math.floor((os.clock() - t0) * 10) / 10)
		root:SetAttribute("BuildParts", Kit.countParts(root))
		root:SetAttribute("BuildState", ok and "done" or "error")
		if not ok then
			root:SetAttribute("BuildError", string.sub(tostring(err), 1, 1500))
			warn("[CityGen] " .. district .. " build failed: " .. tostring(err))
		end
		if opts.cleanup then
			opts.cleanup:Destroy()
		end
	end)
	return root
end

-- a fresh copy of ServerStorage.CityGen (so require() compiles the CURRENT sources, not the cached ones)
function Kit.fresh(tagName)
	local SS = game:GetService("ServerStorage")
	local copy = SS:WaitForChild("CityGen"):Clone()
	copy.Name = "CityGen_run_" .. (tagName or tostring(math.floor(os.clock() * 1000) % 1000000))
	copy.Parent = SS
	return copy
end

-- samples a walking path (list of floor-level Vector3 points) every o.Step studs: raycasts down to the surface a
-- humanoid would stand on (CanQuery parts + terrain), reports the largest height jump between samples and the
-- smallest headroom. ok = no misses, maxStep <= 1.25, minHeadroom >= 6.5. Works in Edit.
function Kit.walkCheck(points, o)
	o = o or {}
	local step = o.Step or 0.5
	local probe = o.Probe or 6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = o.Ignore or {}
	local prevY, maxJump, minHead, misses, n = nil, 0, math.huge, 0, 0
	local worst
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local cnt = math.max(1, math.ceil((b - a).Magnitude / step))
		for k = (i == 1) and 0 or 1, cnt do
			local p = a:Lerp(b, k / cnt)
			local hit = workspace:Raycast(p + V3(0, probe, 0), V3(0, -probe - 8, 0), params)
			n += 1
			if hit then
				local y = hit.Position.Y
				if prevY and math.abs(y - prevY) > maxJump then
					maxJump = math.abs(y - prevY)
					worst = p
				end
				prevY = y
				local up = workspace:Raycast(hit.Position + V3(0, 0.1, 0), V3(0, 8, 0), params)
				minHead = math.min(minHead, up and (up.Position.Y - y) or 8)
			else
				misses += 1
			end
		end
	end
	local ok = misses == 0 and maxJump <= (o.MaxStep or 1.25) and minHead >= (o.MinHead or 6.5)
	return { ok = ok, maxStep = maxJump, minHeadroom = minHead, misses = misses, samples = n, worstAt = worst }
end

---------------------------------------------------------------------------------------------------------------------
-- BUILDER
---------------------------------------------------------------------------------------------------------------------
local B = {}
B.__index = B
Kit.Builder = B

function Kit.new(root, opts)
	opts = opts or {}
	assert(typeof(root) == "Instance", "Kit.new(root): pass workspace.City.<District>")
	local self = setmetatable({}, B)
	self.root = root
	self.district = opts.district or root.Name
	self.rng = Random.new(opts.seed or 20261106)
	self.yieldEvery = opts.yieldEvery or 250
	self.parts, self.lights, self.guis, self.since, self.wpN = 0, 0, 0, 0, 0
	self.t0 = os.clock()
	self.warnings = {}
	self._wp = {}
	self.budget = Plan.budget[self.district] or { parts = 99999, lights = 999, guis = 999 }
	return self
end

function B:warn(msg)
	if #self.warnings < 200 then
		table.insert(self.warnings, msg)
	end
end

function B:tick(k)
	self.since += (k or 1)
	if self.since >= self.yieldEvery then
		self.since = 0
		task.wait()
	end
end

-- the one part factory. p: Name, Class ("Part"/"WedgePart"/"CornerWedgePart"/"TrussPart"/"SpawnLocation"), Shape
-- ("Ball"/"Cylinder"/"Block"), Size, CFrame | Position, Color (Color3 or palette key), Material, Transparency,
-- Reflectance, CanCollide (default true), CanQuery (default = CanCollide), CanTouch (default false), CastShadow
-- (default auto), Anchored (default true), Attributes, Parent (default root)
local SHAPES = { Ball = Enum.PartType.Ball, Cylinder = Enum.PartType.Cylinder, Block = Enum.PartType.Block }
function B:part(p)
	local class = p.Class or "Part"
	local part = Instance.new(class)
	if p.Shape and class == "Part" then
		part.Shape = SHAPES[p.Shape] or p.Shape
	end
	part.Anchored = p.Anchored ~= false
	part.Size = p.Size or Vector3.one
	part.CFrame = p.CFrame or CF(p.Position or Vector3.zero)
	part.Color = color(p.Color) or C.CONCRETE
	part.Material = p.Material or MAT.SmoothPlastic
	part.Transparency = p.Transparency or 0
	part.Reflectance = p.Reflectance or 0
	local collide = p.CanCollide ~= false
	part.CanCollide = collide
	if p.CanQuery ~= nil then
		part.CanQuery = p.CanQuery
	else
		part.CanQuery = collide
	end
	part.CanTouch = p.CanTouch == true
	if p.CastShadow ~= nil then
		part.CastShadow = p.CastShadow
	else
		local s = part.Size
		part.CastShadow = math.max(s.X, s.Y, s.Z) >= 10 and part.Material ~= MAT.Neon and part.Transparency < 0.3
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Name = p.Name or class
	if p.Attributes then
		for k, v in pairs(p.Attributes) do
			part:SetAttribute(k, v)
		end
	end
	part.Parent = p.Parent or self.root
	self.parts += 1
	if self.parts == self.budget.parts + 1 then
		self:warn("PART BUDGET EXCEEDED (" .. self.budget.parts .. ")")
	end
	self:tick()
	return part
end

function B:box(parent, size, cf, col, mat, extra)
	return self:part(merge({ Parent = parent, Size = size, CFrame = cf, Color = col, Material = mat }, extra))
end

function B:wedge(parent, size, cf, col, mat, extra)
	return self:part(merge({ Class = "WedgePart", Parent = parent, Size = size, CFrame = cf, Color = col, Material = mat }, extra))
end

-- vertical cylinder: cf = centre, axis = cf.UpVector
function B:cyl(parent, height, diameter, cf, col, mat, extra)
	return self:part(merge({ Shape = "Cylinder", Parent = parent, Size = V3(height, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, 0, math.pi / 2), Color = col, Material = mat }, extra))
end

function B:ball(parent, d, cf, col, mat, extra)
	return self:part(merge({ Shape = "Ball", Parent = parent, Size = V3(d, d, d), CFrame = cf, Color = col, Material = mat }, extra))
end

-- glowing decor (never collides, never blocks raycasts, no shadow)
function B:neon(parent, size, cf, col, extra)
	return self:part(merge({ Parent = parent, Size = size, CFrame = cf, Color = col or C.NEON_CYAN, Material = MAT.Neon,
		CanCollide = false, CanQuery = false, CastShadow = false, Name = "Neon" }, extra))
end

-- a square-section bar from point a to point b (pipes, struts, neon tubes)
function B:tube(parent, a, b, thick, col, mat, extra)
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local up = (math.abs(d.Unit.Y) > 0.98) and Vector3.xAxis or Vector3.yAxis
	return self:part(merge({ Parent = parent, Size = V3(thick, thick, len), CFrame = CFrame.lookAt((a + b) / 2, b, up),
		Color = col, Material = mat or MAT.Metal, Name = "Tube" }, extra))
end

function B:neonTube(parent, a, b, thick, col, extra)
	return self:tube(parent, a, b, thick, col or C.NEON_CYAN, MAT.Neon,
		merge({ CanCollide = false, CanQuery = false, CastShadow = false, Name = "NeonTube" }, extra))
end

function B:model(parent, name, attrs)
	local m = Instance.new("Model")
	m.Name = name or "Model"
	if attrs then
		for k, v in pairs(attrs) do
			m:SetAttribute(k, v)
		end
	end
	m.Parent = parent or self.root
	return m
end

-- kind: "point" | "spot" | "surface". o: Color, Brightness (1.5), Range (16, max 60), Face, Angle, Shadows (false)
function B:light(part, kind, o)
	o = o or {}
	local cls = (kind == "spot" and "SpotLight") or (kind == "surface" and "SurfaceLight") or "PointLight"
	local l = Instance.new(cls)
	l.Color = color(o.Color) or C.NEON_WHITE
	l.Brightness = o.Brightness or 1.5
	l.Range = math.min(o.Range or 16, 60)
	l.Shadows = o.Shadows == true
	if cls ~= "PointLight" then
		l.Face = o.Face or Enum.NormalId.Bottom
		l.Angle = o.Angle or 90
	end
	l.Parent = part
	self.lights += 1
	if self.lights == self.budget.lights + 1 then
		self:warn("LIGHT BUDGET EXCEEDED (" .. self.budget.lights .. ")")
	end
	return l
end

-- glowing text on one face of a part. o: Font, Color, Background, Brightness (2), LightInfluence (0), MaxDistance (320),
-- PixelsPerStud (20), Stroke, StrokeColor, Pad (0.06), Wrap, LineHeight, Name ("Sign")
function B:text(part, face, text, o)
	o = o or {}
	local g = Instance.new("SurfaceGui")
	g.Name = o.Name or "Sign"
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = o.PixelsPerStud or 20
	g.LightInfluence = o.LightInfluence or 0
	g.Brightness = o.Brightness or 2
	g.MaxDistance = o.MaxDistance or 320
	g.ClipsDescendants = true
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = o.Background and 0 or 1
	if o.Background then
		t.BackgroundColor3 = color(o.Background)
	end
	t.BorderSizePixel = 0
	t.Font = o.Font or Plan.fonts.sign
	t.Text = text
	t.TextColor3 = color(o.Color) or Color3.new(1, 1, 1)
	t.TextScaled = true
	t.TextWrapped = o.Wrap ~= false
	t.LineHeight = o.LineHeight or 1
	t.TextStrokeTransparency = o.Stroke and 0.35 or 1
	t.TextStrokeColor3 = color(o.StrokeColor) or Color3.new(0, 0, 0)
	local pad = Instance.new("UIPadding")
	local px = UDim.new(o.Pad or 0.06, 0)
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = px, px, px, px
	pad.Parent = t
	t.Parent = g
	g.Parent = part
	self.guis += 1
	if self.guis == self.budget.guis + 1 then
		self:warn("SURFACEGUI BUDGET EXCEEDED (" .. self.budget.guis .. ")")
	end
	return g, t
end

---------------------------------------------------------------------------------------------------------------------
-- TAGGING (destruction contract) + client FX tags
---------------------------------------------------------------------------------------------------------------------
local CATS = { GLASS = true, PANEL = true, PROP = true, MARK = true }
function B:tag(inst, cat, attrs)
	assert(CATS[cat], "Kit:tag unknown category " .. tostring(cat))
	local lim = Kit.LIMIT[cat]
	if inst:IsA("Model") then
		if cat == "GLASS" or cat == "MARK" then
			self:warn(cat .. " must be a single BasePart: " .. inst:GetFullName())
		end
		if not inst.PrimaryPart then
			inst.PrimaryPart = inst:FindFirstChildWhichIsA("BasePart", true)
		end
		if not inst.PrimaryPart then
			self:warn(cat .. " model without parts: " .. inst:GetFullName())
		end
		if lim then
			local s = inst:GetExtentsSize()
			if math.max(s.X, s.Y, s.Z) > lim + 0.05 then
				self:warn(string.format("%s oversize %.1f > %d: %s", cat, math.max(s.X, s.Y, s.Z), lim, inst:GetFullName()))
			end
		end
	elseif inst:IsA("BasePart") then
		if cat == "PROP" then
			self:warn("PROP should be a Model with a PrimaryPart: " .. inst:GetFullName())
		end
		if lim then
			local s = inst.Size
			if math.max(s.X, s.Y, s.Z) > lim + 0.05 then
				self:warn(string.format("%s oversize %.1f > %d: %s", cat, math.max(s.X, s.Y, s.Z), lim, inst:GetFullName()))
			end
		end
	end
	CollectionService:AddTag(inst, Kit.TAG[cat])
	inst:SetAttribute("CityDistrict", self.district)
	if attrs then
		for k, v in pairs(attrs) do
			inst:SetAttribute(k, v)
		end
	end
	return inst
end

-- a thin non-colliding marking (road paint, curb, manhole, puddle): tagged MARK
function B:mark(parent, size, cf, col, extra)
	local p = self:part(merge({ Parent = parent, Size = size, CFrame = cf, Color = col or C.MARK_WHITE, Material = MAT.SmoothPlastic,
		CanCollide = false, CanQuery = false, CastShadow = false, Name = "Mark" }, extra))
	self:tag(p, "MARK")
	return p
end

function B:signalLamp(part, group, lamp)
	CollectionService:AddTag(part, Kit.TAG.SIGNAL)
	part:SetAttribute("Group", group)
	part:SetAttribute("Lamp", lamp)
	return part
end

function B:flicker(part, rate)
	CollectionService:AddTag(part, Kit.TAG.FLICKER)
	if rate then
		part:SetAttribute("Rate", rate)
	end
	return part
end

function B:holo(parent, size, cf, col, o)
	o = o or {}
	local p = self:neon(parent, size, cf, col or C.NEON_CYAN, { Name = o.Name or "Holo", Transparency = o.Transparency or 0.45, Shape = o.Shape })
	CollectionService:AddTag(p, Kit.TAG.HOLO)
	p:SetAttribute("Spin", o.Spin or 0)
	p:SetAttribute("Pulse", o.Pulse or 0.3)
	return p
end

-- an invisible anchor part at the origin for attachments (cables, steam points). One per district.
function B:anchor()
	local a = self.root:FindFirstChild("Anchors")
	if not a then
		a = self:part({ Parent = self.root, Name = "Anchors", Size = Vector3.one, CFrame = CF(), Transparency = 1,
			CanCollide = false, CanQuery = false, CastShadow = false })
	end
	return a
end

function B:steam(pos, o)
	o = o or {}
	local a = Instance.new("Attachment")
	a.Name = "Steam"
	a.Position = pos
	a:SetAttribute("Rate", o.Rate or 6)
	a:SetAttribute("Size", o.Size or 4)
	CollectionService:AddTag(a, Kit.TAG.STEAM)
	a.Parent = self:anchor()
	return a
end

-- an overhead cable as a Beam (0 BaseParts). o: Sag (6% of span), Width (0.15), Color, Glow (neon string light)
function B:cable(a, b, o)
	o = o or {}
	local anchor = self:anchor()
	local sag = o.Sag or ((b - a).Magnitude * 0.06)
	local a0 = Instance.new("Attachment")
	a0.Name = "CableA"
	a0.CFrame = CFrame.fromMatrix(a, V3(0, -1, 0), V3(1, 0, 0))
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "CableB"
	a1.CFrame = CFrame.fromMatrix(b, V3(0, 1, 0), V3(1, 0, 0))
	a1.Parent = anchor
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.CurveSize0, beam.CurveSize1 = sag / 0.75, sag / 0.75
	beam.Width0, beam.Width1 = o.Width or 0.15, o.Width or 0.15
	beam.Color = ColorSequence.new(color(o.Color) or C.PLASTIC_BLACK)
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = o.Glow and 1 or 0
	beam.LightInfluence = o.Glow and 0 or 1
	beam.Segments = o.Segments or 12
	beam.FaceCamera = true
	beam.Parent = anchor
	return beam
end

-- a cable with n small glowing lanterns hanging off it (n parts)
function B:lanternString(parent, a, b, n, col, o)
	o = o or {}
	local sag = o.Sag or ((b - a).Magnitude * 0.06)
	self:cable(a, b, { Sag = sag, Color = o.CableColor })
	local d = sag / 0.75
	local p1, p2 = a - V3(0, d, 0), b - V3(0, d, 0)
	for i = 1, n do
		local t = i / (n + 1)
		local u = 1 - t
		local p = a * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + b * (t * t * t)
		local lc = color(col) or C.NEON_RED
		if o.Chochin then
			self:part({ Parent = parent, Shape = "Cylinder", Size = V3(1.6, 1.2, 1.2), CFrame = CF(p - V3(0, 1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = lc, Material = MAT.Neon, CanCollide = false, CanQuery = false, CastShadow = false, Name = "Lantern", Transparency = 0.1 })
		else
			self:part({ Parent = parent, Shape = "Ball", Size = V3(0.7, 0.7, 0.7), CFrame = CF(p - V3(0, 0.4, 0)), Color = lc,
				Material = MAT.Neon, CanCollide = false, CanQuery = false, CastShadow = false, Name = "Bulb" })
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- SIGNS, SCREENS, BILLBOARDS
---------------------------------------------------------------------------------------------------------------------
-- cf = centre of the sign's face, LookVector toward readers. Returns model (PANEL-tagged), board.
-- o: Name, Depth (0.6), Board (colour), Neon (border + text colour), TextColor, Font, Border (true), BorderThick (0.3),
-- Vertical (tategaki), TwoSided, Glow (SurfaceLight brightness, counts as a light), MaxDistance, PixelsPerStud,
-- Background, Stroke, CanCollide (false), Tag (true), Attrs (destruction attrs e.g. { HP = 40 })
function B:sign(parent, cf, w, h, text, o)
	o = o or {}
	local m = self:model(parent, o.Name or "Sign")
	local depth = o.Depth or 0.6
	local neonCol = color(o.Neon) or C.NEON_CYAN
	local board = self:part({ Parent = m, Name = "Board", Size = V3(w, h, depth), CFrame = cf * CF(0, 0, depth / 2),
		Color = color(o.Board) or C.GUNMETAL, Material = MAT.SmoothPlastic, CanCollide = o.CanCollide == true, CastShadow = false })
	if o.Border ~= false then
		local t = o.BorderThick or 0.3
		self:neon(m, V3(w, t, t), cf * CF(0, h / 2 - t / 2, -t / 2), neonCol)
		self:neon(m, V3(w, t, t), cf * CF(0, -h / 2 + t / 2, -t / 2), neonCol)
		self:neon(m, V3(t, h - 2 * t, t), cf * CF(w / 2 - t / 2, 0, -t / 2), neonCol)
		self:neon(m, V3(t, h - 2 * t, t), cf * CF(-w / 2 + t / 2, 0, -t / 2), neonCol)
		if o.TwoSided then
			self:neon(m, V3(w, t, t), cf * CF(0, h / 2 - t / 2, depth + t / 2), neonCol)
			self:neon(m, V3(w, t, t), cf * CF(0, -h / 2 + t / 2, depth + t / 2), neonCol)
		end
	end
	local txt = o.Vertical and Kit.vertical(text) or text
	local to = { Font = o.Font, Color = o.TextColor or neonCol, Background = o.Background, MaxDistance = o.MaxDistance,
		Stroke = o.Stroke, PixelsPerStud = o.PixelsPerStud, Pad = o.Pad }
	self:text(board, Enum.NormalId.Front, txt, to)
	if o.TwoSided then
		self:text(board, Enum.NormalId.Back, txt, to)
	end
	if o.Glow then
		self:light(board, "surface", { Face = Enum.NormalId.Front, Color = neonCol, Brightness = o.Glow, Range = math.max(w, h) * 0.8, Angle = 120 })
	end
	m.PrimaryPart = board
	if o.Tag ~= false then
		self:tag(m, "PANEL", o.Attrs)
	end
	return m, board
end

-- a blade sign sticking out of a facade: cf = point on the wall where it mounts (centre height), LookVector = wall
-- outward normal. The board is perpendicular to the wall, text on both sides (tategaki by default). <= 4 out (overhang).
function B:bladeSign(parent, cf, out, h, text, o)
	o = o or {}
	out = math.min(out or 4, 4)
	local scf = cf * CF(0, 0, -out / 2) * CFrame.Angles(0, math.pi / 2, 0)
	return self:sign(parent, scf, out, h, text, merge({ Vertical = true, TwoSided = true, Depth = 0.5, Name = "BladeSign" }, o))
end

-- a big video screen: cf = centre of the face, LookVector toward viewers. The face is GLASS + CityScreen (SurfaceGui
-- "Screen" with a "Content" Frame the client animates, plus a static "Fallback" label). o: Name, Brand, Text,
-- Playlist ("ads"), PixelsPerStud (10), MaxDistance (1200), Brightness (2.5), HP (20), Glow
function B:screen(parent, cf, w, h, o)
	o = o or {}
	local m = self:model(parent, o.Name or "Screen")
	self:box(m, V3(w + 2, h + 2, 1.6), cf * CF(0, 0, 1.0), C.GUNMETAL, MAT.Metal, { Name = "Frame", CastShadow = false })
	local face = self:box(m, V3(w, h, 0.4), cf * CF(0, 0, 0.2), C.SCREEN_BLACK, MAT.SmoothPlastic, { Name = "Face", CastShadow = false })
	local ppu = o.PixelsPerStud or 10
	local g = Instance.new("SurfaceGui")
	g.Name = "Screen"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	g.CanvasSize = Vector2.new(math.floor(w * ppu), math.floor(h * ppu))
	g.LightInfluence = 0
	g.Brightness = o.Brightness or 2.5
	g.MaxDistance = o.MaxDistance or 1200
	g.ClipsDescendants = true
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
	content.BorderSizePixel = 0
	content.Parent = g
	local fb = Instance.new("TextLabel")
	fb.Name = "Fallback"
	fb.Size = UDim2.fromScale(1, 1)
	fb.BackgroundTransparency = 1
	fb.Font = Plan.fonts.tech
	fb.Text = o.Text or o.Brand or ""
	fb.TextScaled = true
	fb.TextColor3 = color(o.Neon) or C.NEON_CYAN
	fb.Parent = content
	g.Parent = face
	self.guis += 1
	m.PrimaryPart = face
	CollectionService:AddTag(face, Kit.TAG.SCREEN)
	face:SetAttribute("Playlist", o.Playlist or "ads")
	face:SetAttribute("Brand", o.Brand or "")
	self:tag(face, "GLASS", { HP = o.HP or 20 })
	if o.Glow then
		self:light(face, "surface", { Face = Enum.NormalId.Front, Color = color(o.Neon) or C.NEON_CYAN, Brightness = o.Glow, Range = 40, Angle = 120 })
	end
	return m, face
end

-- rooftop billboard on legs: cf = bottom-centre on the roof, LookVector toward readers. Returns the sign model.
function B:billboard(parent, cf, w, h, text, o)
	o = o or {}
	local legH = o.LegH or 4
	local m = self:model(parent, o.Name or "Billboard")
	local n = math.max(2, math.floor(w / 14) + 1)
	for i = 0, n - 1 do
		local x = -w / 2 + 1.5 + i * (w - 3) / (n - 1)
		self:box(m, V3(0.8, legH + h * 0.9, 0.8), cf * CF(x, (legH + h * 0.9) / 2, 1.4), C.STEEL, MAT.Metal, { Name = "Leg", CastShadow = false })
		self:tube(m, cf.Position + cf:VectorToWorldSpace(V3(x, 0.2, 4)), cf.Position + cf:VectorToWorldSpace(V3(x, legH + h * 0.6, 1.4)),
			0.4, C.STEEL, MAT.Metal, { CastShadow = false, CanCollide = false, CanQuery = false, Name = "Brace" })
	end
	self:box(m, V3(w, 0.4, 2.2), cf * CF(0, legH - 0.2, -0.4), C.GUNMETAL, MAT.DiamondPlate, { Name = "Catwalk", CastShadow = false })
	for i = 0, 2 do
		self:neon(m, V3(1.4, 0.5, 0.6), cf * CF(-w / 3 + i * w / 3, legH + 0.25, -1.2), C.NEON_WHITE, { Name = "Floodlamp" })
	end
	local sm = self:sign(m, cf * CF(0, legH + h / 2, 0), w, h, text, merge({ Name = "Board", MaxDistance = 1000, PixelsPerStud = 10,
		Neon = o.Neon or "NEON_MAGENTA", Depth = 0.8 }, o.Sign))
	return sm, m
end

---------------------------------------------------------------------------------------------------------------------
-- FACADES
---------------------------------------------------------------------------------------------------------------------
-- window grid for sealed floors: cf = bottom-centre of the facade area ON the wall surface, LookVector outward.
-- One glass band per floor + merged lit runs (Neon) + optional ledges / mullions. All decor (no collision).
-- o: Style (Plan.styles key), FloorH (12), Bay, Band (0.55), LitChance, Lit {Color3}, Glass, Frame, MaxRun (3),
-- Ledges (true), Mullions (true), Rng
function B:windowGrid(parent, cf, w, h, o)
	o = o or {}
	local st = (o.Style and Plan.styles[o.Style]) or {}
	local floorH = o.FloorH or 12
	local bay = o.Bay or st.bay or 8
	local band = o.Band or 0.55
	local litChance = o.LitChance or st.litChance or 0.3
	local lit = o.Lit or st.lit or { C.WINDOW_WARM, C.WINDOW_COOL }
	local glassCol = color(o.Glass) or st.glass or C.GLASS_DARK
	local frameCol = color(o.Frame) or st.trim or C.GUNMETAL
	local rng = o.Rng or self.rng
	local floors = math.max(1, math.floor(h / floorH + 0.001))
	local bays = math.max(1, math.floor(w / bay + 0.001))
	local bw = w / bays
	local bandH = floorH * band
	local deco = { CanCollide = false, CanQuery = false, CastShadow = false }
	for f = 0, floors - 1 do
		local yc = f * floorH + floorH * 0.5
		self:box(parent, V3(w, bandH, 0.2), cf * CF(0, yc, -0.1), glassCol, MAT.Glass, merge({ Name = "WinBand" }, deco))
		local b = 0
		while b < bays do
			if rng:NextNumber() < litChance then
				local run = 1
				while b + run < bays and run < (o.MaxRun or 3) and rng:NextNumber() < 0.55 do
					run += 1
				end
				local col = lit[rng:NextInteger(1, #lit)]
				local x = -w / 2 + (b + run / 2) * bw
				self:box(parent, V3(run * bw - 0.9, bandH - 0.7, 0.1), cf * CF(x, yc, -0.25), col, MAT.Neon, merge({ Name = "WinLit" }, deco))
				b += run + 1
			else
				b += 1
			end
		end
		if o.Ledges ~= false then
			self:box(parent, V3(w + 0.4, 0.5, 0.7), cf * CF(0, f * floorH + 0.25, -0.35), frameCol, MAT.Concrete, merge({ Name = "Ledge" }, deco))
		end
	end
	if o.Mullions ~= false and bays > 1 then
		local totalH = floors * floorH
		for i = 1, bays - 1 do
			self:box(parent, V3(0.4, totalH, 0.5), cf * CF(-w / 2 + i * bw, totalH / 2, -0.25), frameCol, MAT.Metal, merge({ Name = "Mullion" }, deco))
		end
	end
end

-- a ground-floor shopfront: cf = bottom-centre on the glass line, LookVector toward the street. w wide, h = glass zone
-- height (sign band sits above it). Panes <= PaneMax (10) wide, each tagged GLASS (CanCollide - smash to get in).
-- o: Name, Frame, Glass, GlassT (0.45), Door = { at = 0, width = 6 } (an open archway), Sign (text), SignH (2.6),
-- Neon, Font, Awning (Color3/key), AwningDepth (3), Depth (>0 builds a lit display box that deep behind the glass,
-- for shops you cannot enter), Interior (display colour), Props (3 silhouettes), MaxDistance
function B:storefront(parent, cf, w, h, o)
	o = o or {}
	local m = self:model(parent, o.Name or "Storefront")
	local frameCol = color(o.Frame) or C.GUNMETAL
	local glassCol = color(o.Glass) or C.GLASS_TINT
	local kick, head = 0.8, 1.0
	local paneH = h - kick - head
	local deco = { CanCollide = false, CanQuery = false, CastShadow = false }
	self:box(m, V3(0.8, h, 0.8), cf * CF(-w / 2 + 0.4, h / 2, 0), frameCol, MAT.Metal, { Name = "Post", CastShadow = false })
	self:box(m, V3(0.8, h, 0.8), cf * CF(w / 2 - 0.4, h / 2, 0), frameCol, MAT.Metal, { Name = "Post", CastShadow = false })
	self:box(m, V3(w, head, 0.9), cf * CF(0, h - head / 2, 0), frameCol, MAT.Metal, { Name = "Head", CastShadow = false })
	local spans = { { -w / 2 + 0.8, w / 2 - 0.8 } }
	if o.Door then
		local at, dw = o.Door.at or 0, o.Door.width or 6
		spans = { { -w / 2 + 0.8, at - dw / 2 }, { at + dw / 2, w / 2 - 0.8 } }
		self:box(m, V3(0.6, h, 0.9), cf * CF(at - dw / 2 - 0.3, h / 2, 0), frameCol, MAT.Metal, { Name = "DoorJamb", CastShadow = false })
		self:box(m, V3(0.6, h, 0.9), cf * CF(at + dw / 2 + 0.3, h / 2, 0), frameCol, MAT.Metal, { Name = "DoorJamb", CastShadow = false })
	end
	for _, s in ipairs(spans) do
		local a, b = s[1], s[2]
		local len = b - a
		if len > 0.6 then
			self:box(m, V3(len, kick, 0.7), cf * CF((a + b) / 2, kick / 2, 0), frameCol, MAT.Metal, { Name = "Kick", CastShadow = false })
			local n = math.max(1, math.ceil(len / (o.PaneMax or 10)))
			local pw = len / n
			for i = 0, n - 1 do
				local pane = self:box(m, V3(pw - 0.3, paneH, 0.3), cf * CF(a + (i + 0.5) * pw, kick + paneH / 2, 0), glassCol, MAT.Glass,
					{ Name = "Pane", Transparency = o.GlassT or 0.45, CastShadow = false })
				self:tag(pane, "GLASS")
				if i > 0 then
					self:box(m, V3(0.4, paneH, 0.5), cf * CF(a + i * pw, kick + paneH / 2, 0), frameCol, MAT.Metal, merge({ Name = "Mullion" }, deco))
				end
			end
		end
	end
	local signH = o.SignH or 2.6
	if o.Sign then
		self:sign(m, cf * CF(0, h + signH / 2 + 0.1, -0.45), w - 0.6, signH, o.Sign, { Neon = o.Neon, Font = o.Font, Name = "ShopSign",
			MaxDistance = o.MaxDistance or 260, Board = o.SignBoard })
	end
	if o.Awning then
		local ad = o.AwningDepth or 3
		local ya = h + (o.Sign and signH + 0.5 or 0.5)
		self:box(m, V3(w, 0.25, ad), cf * CF(0, ya, -ad / 2) * CFrame.Angles(math.rad(-14), 0, 0), color(o.Awning), MAT.Fabric,
			merge({ Name = "Awning" }, deco))
	end
	if (o.Depth or 0) > 0.5 then
		local d = o.Depth
		for _, s in ipairs(spans) do
			if s[2] - s[1] > 0.6 then
				self:box(m, V3(s[2] - s[1], paneH, 0.3), cf * CF((s[1] + s[2]) / 2, kick + paneH / 2, d - 0.15), color(o.Interior) or C.WINDOW_WARM,
					MAT.Neon, merge({ Name = "Display", Transparency = 0.3 }, deco))
			end
		end
		if o.Door then
			local at, dw = o.Door.at or 0, o.Door.width or 6
			self:box(m, V3(dw, h - head, 0.4), cf * CF(at, (h - head) / 2, d - 0.2), C.GLASS_DARK, MAT.Glass,
				{ Name = "DoorLeaf", Reflectance = 0.15, CastShadow = false })
		end
		self:box(m, V3(w - 1.6, 0.4, d), cf * CF(0, kick - 0.2, d / 2), C.CONCRETE_LIGHT, MAT.SmoothPlastic, merge({ Name = "DisplayFloor" }, deco))
		local np = o.Props or 3
		for i = 1, np do
			local x = -w / 2 + 1.5 + (i - 0.5) * (w - 3) / np
			local ph = paneH * (0.35 + 0.45 * self.rng:NextNumber())
			self:box(m, V3(math.min(2.2, (w - 3) / np * 0.6), ph, 1.0), cf * CF(x, kick + ph / 2, d * 0.55), C.PLASTIC_BLACK, MAT.SmoothPlastic,
				merge({ Name = "Silhouette" }, deco))
		end
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- WALKABLE GEOMETRY: stairs, ramps, ladders, railings, walls, slabs
---------------------------------------------------------------------------------------------------------------------
-- a sloped slab whose TOP surface runs from floor point a to floor point b (centre line). Warns above 40 degrees.
-- o: Thick (1), Color, Material, Name, Props (extra part props, e.g. { Transparency = 1 })
function B:ramp(parent, a, b, width, o)
	o = o or {}
	local t = o.Thick or 1
	local d = b - a
	local L = d.Magnitude
	local dir = d.Unit
	local right = dir:Cross(Vector3.yAxis)
	assert(right.Magnitude > 1e-3, "Kit:ramp cannot be vertical")
	right = right.Unit
	local up = right:Cross(dir).Unit
	local cfm = CFrame.fromMatrix((a + b) / 2 - up * (t / 2), right, up, -dir)
	local slope = math.deg(math.asin(math.min(1, math.abs(dir.Y))))
	if slope > (o.MaxSlope or Kit.STEP.maxSlope) then
		self:warn(string.format("ramp %.1f deg is steeper than %d: %s", slope, Kit.STEP.maxSlope, tostring(a)))
	end
	return self:part(merge({ Parent = parent, Name = o.Name or "Ramp", Size = V3(width, t, L), CFrame = cfm,
		Color = color(o.Color) or C.CONCRETE, Material = o.Material or MAT.Concrete }, o.Props))
end

-- a straight flight. cf = bottom-centre of the flight on the LOWER floor surface, LookVector = up-the-flight.
-- rise = total height. Builds visual steps (no collision) + an invisible collision ramp on the NOSING line (the rule
-- that makes a flight walkable instead of 20 ledges) + a collidable top tread. o: Rise (1.0, max 1.2), Going (1.5),
-- Solid (true: steps go down to the floor), Color, Material, Rails (true), RailColor, Name.
-- Returns { model, top = CFrame on the upper floor edge (same orientation), run, steps, riseEach, ramp }
function B:stairs(parent, cf, width, rise, o)
	o = o or {}
	local maxR = math.min(o.Rise or Kit.STEP.rise, Kit.STEP.maxRise)
	local going = o.Going or Kit.STEP.going
	local n = math.max(1, math.ceil(rise / maxR - 1e-6))
	local r = rise / n
	local m = self:model(parent, o.Name or "Stairs")
	local col = color(o.Color) or C.CONCRETE_LIGHT
	local mat = o.Material or MAT.Concrete
	local solid = o.Solid ~= false
	for i = 1, n do
		local top = i * r
		local hh = solid and top or math.min(top, r * 1.6)
		local last = (i == n)
		self:box(m, V3(width, hh, going), cf * CF(0, top - hh / 2, -((i - 0.5) * going)), col, mat,
			{ Name = last and "TopTread" or "Step", CanCollide = last, CanQuery = last, CastShadow = false })
	end
	local p0 = cf:PointToWorldSpace(V3(0, 0, going))
	local p1 = cf:PointToWorldSpace(V3(0, rise, -(n - 1) * going))
	local ramp = self:ramp(m, p0, p1, width, { Name = "StairRamp", MaxSlope = 45,
		Props = { Transparency = 1, CastShadow = false } })
	if o.Rails ~= false then
		local rc = color(o.RailColor) or C.STEEL
		for _, sx in ipairs({ -1, 1 }) do
			local x = sx * (width / 2 - 0.2)
			local a = cf:PointToWorldSpace(V3(x, r + 3, 0))
			local b = cf:PointToWorldSpace(V3(x, rise + 3, -(n - 1) * going))
			self:tube(m, a, b, 0.25, rc, MAT.Metal, { CanCollide = false, CanQuery = false, CastShadow = false, Name = "Handrail" })
			self:box(m, V3(0.3, 3, 0.3), CF(a - V3(0, 1.5, 0)), rc, MAT.Metal, { CanCollide = false, CanQuery = false, CastShadow = false, Name = "RailPost" })
			self:box(m, V3(0.3, 3, 0.3), CF(b - V3(0, 1.5, 0)), rc, MAT.Metal, { CanCollide = false, CanQuery = false, CastShadow = false, Name = "RailPost" })
		end
	end
	local run = n * going
	return { model = m, top = cf * CF(0, rise, -run), run = run, steps = n, riseEach = r, ramp = ramp }
end

-- a climbable ladder (TrussPart). cf = bottom-centre at the floor, 1 stud off the wall, LookVector away from the wall.
function B:ladder(parent, cf, height, o)
	o = o or {}
	local H = math.max(2, 2 * math.ceil(height / 2))
	local t = self:part({ Class = "TrussPart", Parent = parent, Name = "Ladder", Size = V3(2, H, 2), CFrame = cf * CF(0, H / 2, 0),
		Color = color(o.Color) or C.STEEL, Material = MAT.Metal, CastShadow = false })
	t.Style = Enum.Style.NoSupports
	if o.Light ~= false then
		self:neon(parent, V3(0.6, 0.6, 0.6), cf * CF(0, H + 0.4, 0), C.NEON_AMBER, { Name = "LadderLamp" })
	end
	return t
end

-- railing from floor point a to b; PANEL-tagged segments <= Seg (12) long so a blast takes a piece, not the run.
-- o: Height (3.5), Glass (true: glass infill; false: bars), Color, Seg, Tag (true), HP
function B:railing(parent, a, b, o)
	o = o or {}
	local h = o.Height or 3.5
	local d = b - a
	local L = d.Magnitude
	if L < 0.5 then
		return
	end
	local dir = d.Unit
	local rc = color(o.Color) or C.STEEL
	local segs = math.max(1, math.ceil(L / (o.Seg or 12)))
	for i = 0, segs - 1 do
		local pa = a + dir * (L * i / segs)
		local pb = a + dir * (L * (i + 1) / segs)
		local m = self:model(parent, "Railing")
		local top = self:tube(m, pa + V3(0, h, 0), pb + V3(0, h, 0), 0.3, rc, MAT.Metal, { Name = "Rail", CastShadow = false })
		local mid = (pa + pb) / 2 + V3(0, h / 2, 0)
		local seg = (pb - pa).Magnitude
		if o.Glass ~= false then
			self:box(m, V3(0.2, h - 0.6, seg - 0.3), CFrame.lookAt(mid, mid + dir), C.GLASS_TINT, MAT.Glass,
				{ Name = "Infill", Transparency = 0.5, CastShadow = false })
		else
			self:box(m, V3(0.2, 0.25, seg), CFrame.lookAt(mid - V3(0, h * 0.25, 0), mid - V3(0, h * 0.25, 0) + dir), rc, MAT.Metal,
				{ Name = "MidRail", CastShadow = false })
		end
		self:box(m, V3(0.35, h, 0.35), CF(pa + V3(0, h / 2, 0)), rc, MAT.Metal, { Name = "Post", CastShadow = false })
		m.PrimaryPart = top
		if o.Tag ~= false then
			self:tag(m, "PANEL", { HP = o.HP or 20 })
		end
	end
	self:box(parent, V3(0.35, h, 0.35), CF(b + V3(0, h / 2, 0)), rc, MAT.Metal, { Name = "Post", CastShadow = false })
end

-- a straight wall on floor point a -> b (base y = a.Y), height h, thickness t.
-- o.Openings = { { s0, s1, top }, ... } open archways from the floor (s measured from a, top default 8)
-- o.Windows = { { s0, s1, v0, v1, glass? }, ... } (glass panes tagged GLASS unless glass == false)
-- o.Chunk = split solid spans into pieces <= Chunk long; o.Tag = "PANEL" makes every piece breakable (interior walls)
-- o.Color, o.Material, o.Name, o.Attrs (tag attributes)
function B:wall(parent, a, b, h, t, o)
	o = o or {}
	local flat = V3(b.X - a.X, 0, b.Z - a.Z)
	local L = flat.Magnitude
	local dir = flat.Unit
	local frame = CFrame.lookAt(a, a + dir)
	local col = color(o.Color) or C.CONCRETE
	local mat = o.Material or MAT.Concrete
	local out = {}
	local function piece(s0, s1, y0, y1)
		if s1 - s0 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		local n = math.max(1, math.ceil((s1 - s0) / (o.Chunk or 1e9) - 1e-6))
		local w = (s1 - s0) / n
		local vn = math.max(1, math.ceil((y1 - y0) / ((o.Tag and Kit.CHUNK) or 1e9) - 1e-6))
		local vh = (y1 - y0) / vn
		for i = 0, n - 1 do
			for j = 0, vn - 1 do
				local p = self:box(parent, V3(t, vh, w), frame * CF(0, y0 + (j + 0.5) * vh, -(s0 + (i + 0.5) * w)), col, mat, { Name = o.Name or "Wall" })
				if o.Tag then
					self:tag(p, o.Tag, o.Attrs)
				end
				table.insert(out, p)
			end
		end
	end
	local cuts = {}
	for _, op in ipairs(o.Openings or {}) do
		table.insert(cuts, { s0 = op[1], s1 = op[2], door = true, top = op[3] or math.min(h, 8) })
	end
	for _, w in ipairs(o.Windows or {}) do
		table.insert(cuts, { s0 = w[1], s1 = w[2], v0 = w[3], v1 = w[4], glass = w[5] })
	end
	table.sort(cuts, function(x, y)
		return x.s0 < y.s0
	end)
	local s = 0
	for _, c in ipairs(cuts) do
		piece(s, c.s0, 0, h)
		if c.door then
			piece(c.s0, c.s1, c.top, h)
		else
			piece(c.s0, c.s1, 0, c.v0)
			piece(c.s0, c.s1, c.v1, h)
			if c.glass ~= false then
				local np = math.max(1, math.ceil((c.s1 - c.s0) / Kit.LIMIT.GLASS))
				local pw = (c.s1 - c.s0) / np
				for k = 0, np - 1 do
					local pane = self:box(parent, V3(0.3, c.v1 - c.v0, pw), frame * CF(0, (c.v0 + c.v1) / 2, -(c.s0 + (k + 0.5) * pw)),
						C.GLASS_TINT, MAT.Glass, { Name = "Pane", Transparency = 0.45, CastShadow = false })
					self:tag(pane, "GLASS")
				end
			end
		end
		s = math.max(s, c.s1)
	end
	piece(s, L, 0, h)
	return out
end

-- a floor / roof slab over rect r whose TOP is at yTop. o.Holes = { rects } (stair wells), Color, Material, Name
function B:slab(parent, r, yTop, thick, o)
	o = o or {}
	local out = {}
	for _, q in ipairs(Kit.subtract(r, o.Holes)) do
		if q.x1 - q.x0 > 0.05 and q.z1 - q.z0 > 0.05 then
			table.insert(out, self:box(parent, V3(q.x1 - q.x0, thick, q.z1 - q.z0), CF((q.x0 + q.x1) / 2, yTop - thick / 2, (q.z0 + q.z1) / 2),
				color(o.Color) or C.CONCRETE, o.Material or MAT.Concrete, { Name = o.Name or "Slab" }))
		end
	end
	return out
end

-- a glowing ceiling panel with (optionally) one light: cf = centre of the panel at ceiling height (panel hangs below)
function B:ceilingLight(parent, cf, w, d, o)
	o = o or {}
	local panel = self:neon(parent, V3(w, 0.2, d), cf * CF(0, -0.1, 0), color(o.Color) or C.NEON_WHITE, { Name = "CeilingLight", Transparency = o.Transparency or 0.1 })
	if o.Light ~= false then
		self:light(panel, "surface", { Face = Enum.NormalId.Bottom, Range = o.Range or 18, Brightness = o.Brightness or 1.2, Angle = 120,
			Color = color(o.LightColor) or color(o.Color) or C.NEON_WHITE })
	end
	return panel
end

---------------------------------------------------------------------------------------------------------------------
-- GENERIC BUILDINGS
---------------------------------------------------------------------------------------------------------------------
-- roof dressing inside rect r on a roof whose top is yTop: AC units (PROP), water tank (PROP), antenna, vents.
-- o: AC (count), Tank (true), TankChance (0.6), Antenna (true), Rng
function B:roofClutter(parent, r, yTop, o)
	o = o or {}
	local rng = o.Rng or self.rng
	local cells = {}
	for x = r.x0 + 5, r.x1 - 5, 10 do
		for z = r.z0 + 5, r.z1 - 5, 10 do
			table.insert(cells, V3(x, yTop, z))
		end
	end
	shuffle(cells, rng)
	local k = 0
	local function take()
		k += 1
		return cells[k]
	end
	local area = (r.x1 - r.x0) * (r.z1 - r.z0)
	local nAC = o.AC or math.clamp(math.floor(area / 900), 1, 6)
	for _ = 1, nAC do
		local p = take()
		if not p then
			break
		end
		self:prop("ac", parent, CF(p) * CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0))
	end
	if o.Tank ~= false and area > 1400 and rng:NextNumber() < (o.TankChance or 0.6) then
		local p = take()
		if p then
			self:prop("tank", parent, CF(p))
		end
	end
	if o.Antenna ~= false and rng:NextNumber() < 0.5 then
		local p = take()
		if p then
			local hh = 8 + rng:NextInteger(0, 10)
			self:box(parent, V3(0.4, hh, 0.4), CF(p + V3(0, hh / 2, 0)), C.STEEL, MAT.Metal, { Name = "Antenna", CastShadow = false, CanCollide = false, CanQuery = false })
			self:flicker(self:neon(parent, V3(0.7, 0.7, 0.7), CF(p + V3(0, hh + 0.3, 0)), C.SIGNAL_RED, { Name = "AviationLight" }), 0.5)
		end
	end
	local p = take()
	if p then
		self:box(parent, V3(3, 2, 3), CF(p + V3(0, 1, 0)), C.CONCRETE_DARK, MAT.Concrete, { Name = "Vent" })
		self:steam(p + V3(0, 2.2, 0), { Rate = 3, Size = 3 })
	end
end

-- a generic sealed building on a lot. spec = a Plan lot (or the same fields):
--   x0, z0, x1, z1, h, style, name|id, floorH (12), groundH (14), detail ("low"|"med"|"high", default "med"),
--   windows = { "N","S","E","W" } faces that get window grids (default all four),
--   storefront = { S = { sign = "..", neon = key, awning = key, door = true, interior = key }, ... } (recessed 4),
--   crown = palette key / Color3 (neon strip round the parapet), parapet (3),
--   roof = { clutter = true, billboard = { text = "..", face = "S", w, h }, ladder = { face = "W", at = 0 }, ac, tank },
--   vsign = { text = "..", face = "S", at = offset along the face, y = centre height above street, h = 20 }
-- Returns the building Model (structure: never tagged; its panes / signs / props are).
function B:shell(parent, spec)
	local st = Plan.styles[spec.style or "concrete"] or Plan.styles.concrete
	local r = R(spec.x0, spec.z0, spec.x1, spec.z1)
	local y0 = Kit.Y
	local H = spec.h
	local cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
	local m = self:model(parent, spec.name or spec.id or "Building", { Lot = spec.id or "" })
	local rng = spec.rng or self.rng
	local detail = spec.detail or "med"
	local groundH = spec.groundH or 14
	local wallCol = color(spec.color) or st.wall
	local mat = spec.material or st.mat
	local sf = spec.storefront or {}
	local inset = { N = 0, S = 0, E = 0, W = 0 }
	local anySf = false
	for f in pairs(sf) do
		inset[f] = spec.recess or 4
		anySf = true
	end
	if anySf then
		local core = R(r.x0 + inset.W, r.z0 + inset.N, r.x1 - inset.E, r.z1 - inset.S)
		self:box(m, V3(core.x1 - core.x0, groundH, core.z1 - core.z0), CF((core.x0 + core.x1) / 2, y0 + groundH / 2, (core.z0 + core.z1) / 2),
			st.trim, MAT.Concrete, { Name = "GroundCore" })
		self:box(m, V3(r.x1 - r.x0, H - groundH, r.z1 - r.z0), CF(cx, y0 + groundH + (H - groundH) / 2, cz), wallCol, mat, { Name = "Mass" })
		for f, so in pairs(sf) do
			local fcf, fw = Kit.faceCF(r, f, y0)
			self:storefront(m, fcf, fw - 1.6, groundH - 3.2, { Sign = so.sign, Neon = so.neon, Awning = so.awning,
				Door = so.door and { at = so.doorAt or 0, width = so.doorWidth or 6 } or nil, Depth = inset[f] - 0.6,
				Interior = so.interior, Name = "Storefront_" .. f })
		end
	else
		self:box(m, V3(r.x1 - r.x0, H, r.z1 - r.z0), CF(cx, y0 + H / 2, cz), wallCol, mat, { Name = "Mass" })
	end
	local wy = anySf and groundH or (spec.baseH or 4)
	for _, f in ipairs(spec.windows or { "N", "S", "E", "W" }) do
		local fcf, fw = Kit.faceCF(r, f, y0 + wy)
		if fw >= 10 and H - wy - 4 >= 8 then
			self:windowGrid(m, fcf, fw - 2, H - wy - 4, { Style = spec.style, FloorH = spec.floorH or 12, Rng = rng,
				Mullions = detail == "high", Ledges = detail ~= "low" })
		end
	end
	local top = y0 + H
	local ph, pt = spec.parapet or 3, 1
	local trim = st.trim
	self:box(m, V3(r.x1 - r.x0, ph, pt), CF(cx, top + ph / 2, r.z0 + pt / 2), trim, MAT.Concrete, { Name = "Parapet" })
	self:box(m, V3(r.x1 - r.x0, ph, pt), CF(cx, top + ph / 2, r.z1 - pt / 2), trim, MAT.Concrete, { Name = "Parapet" })
	self:box(m, V3(pt, ph, r.z1 - r.z0 - 2 * pt), CF(r.x0 + pt / 2, top + ph / 2, cz), trim, MAT.Concrete, { Name = "Parapet" })
	self:box(m, V3(pt, ph, r.z1 - r.z0 - 2 * pt), CF(r.x1 - pt / 2, top + ph / 2, cz), trim, MAT.Concrete, { Name = "Parapet" })
	if spec.crown then
		local nc = color(spec.crown == true and st.neon or spec.crown)
		local yy = top + ph + 0.2
		self:neon(m, V3(r.x1 - r.x0, 0.4, 0.4), CF(cx, yy, r.z0 + 0.5), nc, { Name = "Crown" })
		self:neon(m, V3(r.x1 - r.x0, 0.4, 0.4), CF(cx, yy, r.z1 - 0.5), nc, { Name = "Crown" })
		self:neon(m, V3(0.4, 0.4, r.z1 - r.z0), CF(r.x0 + 0.5, yy, cz), nc, { Name = "Crown" })
		self:neon(m, V3(0.4, 0.4, r.z1 - r.z0), CF(r.x1 - 0.5, yy, cz), nc, { Name = "Crown" })
	end
	local roof = spec.roof or {}
	if roof.clutter ~= false and (r.x1 - r.x0) >= 16 and (r.z1 - r.z0) >= 16 then
		self:roofClutter(m, R(r.x0 + 3, r.z0 + 3, r.x1 - 3, r.z1 - 3), top, { Rng = rng, AC = roof.ac, Tank = roof.tank })
	end
	if roof.billboard then
		local bb = roof.billboard
		local face = bb.face or "S"
		local fcf, fw = Kit.faceCF(r, face, top)
		local bw = math.min(bb.w or fw * 0.7, fw - 4)
		self:billboard(m, fcf * CF(0, 0, 4), bw, bb.h or math.max(10, bw * 0.35), bb.text, { Neon = bb.neon })
	end
	if roof.ladder then
		local fcf = Kit.faceCF(r, roof.ladder.face or "W", y0)
		self:ladder(m, fcf * CF(roof.ladder.at or 0, 0, -1), H + ph + 1)
	end
	if spec.vsign then
		local vs = spec.vsign
		local fcf, fw = Kit.faceCF(r, vs.face or "S", y0)
		local hh = vs.h or 20
		local at = vs.at or (fw / 2 - 3)
		self:bladeSign(m, fcf * CF(at, vs.y or (groundH + 2 + hh / 2), 0), 4, hh, vs.text, { Neon = vs.neon or st.neon, Font = vs.font })
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- PROPS (each one a Model with a PrimaryPart, tagged PROP unless o.Tag == false; cf = floor contact, LookVector front)
---------------------------------------------------------------------------------------------------------------------
local PROPS = {}
Kit.PROPS = PROPS
local DECO = { CanCollide = false, CanQuery = false, CastShadow = false }
local VEND = { ["ZAP COLA"] = Color3.fromRGB(176, 24, 40), ["GENKI-X"] = Color3.fromRGB(28, 30, 34), ["MATCHA FIZZ"] = Color3.fromRGB(36, 112, 70),
	["NEON SODA"] = Color3.fromRGB(36, 56, 160) }

PROPS.vending = function(self, m, cf, o)
	local brand = o.Brand or "ZAP COLA"
	local bc = color(o.Color) or VEND[brand] or C.CAR_RED
	local body = self:box(m, V3(4, 7, 3), cf * CF(0, 3.5, 0), bc, MAT.SmoothPlastic, { Name = "Body" })
	local panel = self:box(m, V3(3.2, 4.0, 0.2), cf * CF(0, 4.3, -1.55), C.PLASTIC_WHITE, MAT.Neon, merge({ Name = "Panel", Transparency = 0.2 }, DECO))
	for i = 0, 2 do
		self:box(m, V3(3.0, 0.22, 0.15), cf * CF(0, 3.1 + i * 1.3, -1.7), C.PLASTIC_BLACK, MAT.SmoothPlastic, merge({ Name = "Row" }, DECO))
	end
	self:box(m, V3(2.6, 0.8, 0.2), cf * CF(0, 1.2, -1.55), C.PLASTIC_BLACK, MAT.SmoothPlastic, merge({ Name = "Slot" }, DECO))
	local band = self:box(m, V3(4.05, 0.9, 3.05), cf * CF(0, 6.55, 0), bc, MAT.Neon, merge({ Name = "Band", Transparency = 0.35 }, DECO))
	if o.Text then
		self:text(band, Enum.NormalId.Front, brand, { MaxDistance = 90, PixelsPerStud = 16, Color = C.NEON_WHITE })
	end
	if o.Light then
		self:light(panel, "point", { Range = 9, Brightness = 1.1, Color = C.NEON_WHITE })
	end
	return body
end

PROPS.bench = function(self, m, cf, o)
	local w = o.Width or 6
	local seat = self:box(m, V3(w, 0.4, 1.8), cf * CF(0, 1.7, 0), color(o.Color) or C.WOOD_LIGHT, MAT.Wood, { Name = "Seat" })
	self:box(m, V3(w, 1.4, 0.3), cf * CF(0, 2.8, 0.85), color(o.Color) or C.WOOD_LIGHT, MAT.Wood, { Name = "Back" })
	self:box(m, V3(0.4, 1.5, 1.6), cf * CF(-w / 2 + 0.6, 0.75, 0), C.GUNMETAL, MAT.Metal, { Name = "Leg" })
	self:box(m, V3(0.4, 1.5, 1.6), cf * CF(w / 2 - 0.6, 0.75, 0), C.GUNMETAL, MAT.Metal, { Name = "Leg" })
	return seat
end

PROPS.lamp = function(self, m, cf, o)
	local H, arm = o.Height or 17, o.Arm or 4
	self:box(m, V3(1.2, 1, 1.2), cf * CF(0, 0.5, 0), C.GUNMETAL, MAT.Metal, { Name = "Base" })
	local pole = self:box(m, V3(0.6, H, 0.6), cf * CF(0, H / 2, 0), C.GUNMETAL, MAT.Metal, { Name = "Pole" })
	self:box(m, V3(0.4, 0.4, arm), cf * CF(0, H - 0.2, -arm / 2), C.GUNMETAL, MAT.Metal, { Name = "Arm", CastShadow = false })
	self:box(m, V3(1.6, 0.5, 2.4), cf * CF(0, H - 0.6, -arm + 0.6), C.GUNMETAL, MAT.Metal, { Name = "Head", CastShadow = false })
	local glow = self:neon(m, V3(1.3, 0.15, 2.0), cf * CF(0, H - 0.9, -arm + 0.6), color(o.LightColor) or C.NEON_WHITE, { Name = "Glow" })
	if o.Light then
		self:light(glow, "spot", { Face = Enum.NormalId.Bottom, Range = o.Range or 40, Angle = 100, Brightness = o.Brightness or 2.2,
			Color = color(o.LightColor) or Color3.fromRGB(255, 226, 190) })
	end
	return pole
end

-- vehicle signal on a mast arm. LookVector = the direction the arm reaches out over the road; the horizontal head
-- has lamps on both sides, facing traffic both ways (along cf.RightVector). Lamps tagged CitySignal (Group = o.Group).
PROPS.trafficLight = function(self, m, cf, o)
	local H, arm = o.Height or 15, o.Arm or 14
	local group = o.Group or "veh_x"
	local pole = self:box(m, V3(0.9, H, 0.9), cf * CF(0, H / 2, 0), C.GUNMETAL, MAT.Metal, { Name = "Pole" })
	self:box(m, V3(0.5, 0.5, arm), cf * CF(0, H - 0.6, -arm / 2), C.GUNMETAL, MAT.Metal, { Name = "Arm", CastShadow = false })
	local hz = -arm + 2.6
	self:box(m, V3(1.0, 1.6, 4.6), cf * CF(0, H - 1.8, hz), C.GUNMETAL, MAT.Metal, { Name = "Head", CastShadow = false })
	local lamps = { { "green", -1.5 }, { "amber", 0 }, { "red", 1.5 } }
	for _, sx in ipairs({ -1, 1 }) do
		for _, l in ipairs(lamps) do
			local p = self:box(m, V3(0.2, 1.1, 1.1), cf * CF(sx * 0.6, H - 1.8, hz + l[2]), C.SIGNAL_OFF, MAT.SmoothPlastic,
				merge({ Name = "Lamp_" .. l[1] }, DECO))
			self:signalLamp(p, group, l[1])
		end
	end
	return pole
end

-- pedestrian signal (red "stop" over green "walk") facing LookVector (put it on the FAR side of the crossing).
PROPS.pedSignal = function(self, m, cf, o)
	local H = o.Height or 9
	local group = o.Group or "x"
	local pole = self:box(m, V3(0.5, H, 0.5), cf * CF(0, H / 2, 0), C.GUNMETAL, MAT.Metal, { Name = "Pole" })
	self:box(m, V3(1.4, 2.8, 0.9), cf * CF(0, H - 1.6, -0.6), C.GUNMETAL, MAT.Metal, { Name = "Head", CastShadow = false })
	local sides = o.TwoSided and { -1, 1 } or { -1 }
	for _, sz in ipairs(sides) do
		local zz = -0.6 + sz * 0.5
		self:signalLamp(self:box(m, V3(1.0, 1.0, 0.12), cf * CF(0, H - 0.9, zz), C.SIGNAL_OFF, MAT.SmoothPlastic, merge({ Name = "Lamp_stop" }, DECO)), group, "stop")
		self:signalLamp(self:box(m, V3(1.0, 1.0, 0.12), cf * CF(0, H - 2.3, zz), C.SIGNAL_OFF, MAT.SmoothPlastic, merge({ Name = "Lamp_walk" }, DECO)), group, "walk")
	end
	return pole
end

-- o.Style: "sedan" | "van" | "taxi" | "kei"; o.Color. Front = LookVector. ~11 parts.
PROPS.car = function(self, m, cf, o)
	local style = o.Style or "sedan"
	local cols = { C.CAR_WHITE, C.CAR_BLACK, C.CAR_SILVER, C.CAR_RED, C.CAR_TEAL }
	local col = color(o.Color) or (style == "taxi" and C.CAR_TAXI) or cols[self.rng:NextInteger(1, #cols)]
	local L = (style == "kei") and 11 or 14
	local W = (style == "kei") and 5.2 or 6
	local bodyH = 2.4
	local cabH = (style == "van") and 4.0 or ((style == "kei") and 2.8 or 2.2)
	local cabL = (style == "van") and 10.5 or ((style == "kei") and 7 or 7.5)
	local cabZ = (style == "van") and 1.0 or 0.6
	local clear = 0.9
	local body = self:box(m, V3(W, bodyH, L), cf * CF(0, clear + bodyH / 2, 0), col, MAT.SmoothPlastic, { Name = "Body", Reflectance = 0.08 })
	self:box(m, V3(W - 0.6, cabH, cabL), cf * CF(0, clear + bodyH + cabH / 2, cabZ), C.GLASS_DARK, MAT.Glass, { Name = "Cabin", Reflectance = 0.2 })
	self:box(m, V3(W - 0.8, 0.3, cabL - 0.8), cf * CF(0, clear + bodyH + cabH + 0.15, cabZ), col, MAT.SmoothPlastic, { Name = "Roof", CastShadow = false })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			self:part({ Parent = m, Shape = "Cylinder", Size = V3(0.9, 2.0, 2.0), CFrame = cf * CF(sx * (W / 2 - 0.35), 1.0, sz * (L / 2 - 2.4)),
				Color = C.PLASTIC_BLACK, Material = MAT.SmoothPlastic, Name = "Wheel", CastShadow = false })
		end
		self:neon(m, V3(1.2, 0.5, 0.15), cf * CF(sx * (W / 2 - 1.1), clear + bodyH - 0.7, -L / 2 - 0.05), C.NEON_WHITE, { Name = "Headlight" })
		self:neon(m, V3(1.2, 0.4, 0.15), cf * CF(sx * (W / 2 - 1.1), clear + bodyH - 0.6, L / 2 + 0.05), C.SIGNAL_RED, { Name = "Taillight" })
	end
	if style == "taxi" then
		self:neon(m, V3(2.2, 0.7, 1.0), cf * CF(0, clear + bodyH + cabH + 0.65, cabZ), C.NEON_AMBER, { Name = "TaxiSign" })
	end
	return body
end

PROPS.ac = function(self, m, cf, o)
	local body = self:box(m, V3(4, 3, 2.6), cf * CF(0, 1.5, 0), Color3.fromRGB(176, 178, 184), MAT.SmoothPlastic, { Name = "Body" })
	self:part({ Parent = m, Shape = "Cylinder", Size = V3(0.2, 2.2, 2.2), CFrame = cf * CF(0.5, 1.5, -1.35) * CFrame.Angles(0, math.pi / 2, 0),
		Color = C.CONCRETE_DARK, Material = MAT.Metal, Name = "Fan", CanCollide = false, CanQuery = false, CastShadow = false })
	return body
end

PROPS.tank = function(self, m, cf, o)
	local d, h = o.D or 7, o.H or 6
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			self:box(m, V3(0.6, 3, 0.6), cf * CF(sx * d / 3, 1.5, sz * d / 3), C.STEEL, MAT.Metal, { Name = "Leg", CastShadow = false })
		end
	end
	self:box(m, V3(d, 0.4, d), cf * CF(0, 3.2, 0), C.STEEL, MAT.Metal, { Name = "Base", CastShadow = false })
	local body = self:cyl(m, h, d, cf * CF(0, 3.4 + h / 2, 0), Color3.fromRGB(150, 140, 128), MAT.Metal, { Name = "Tank" })
	self:cyl(m, 0.6, d * 0.4, cf * CF(0, 3.7 + h, 0), C.STEEL, MAT.Metal, { Name = "Cap", CastShadow = false })
	return body
end

PROPS.barrel = function(self, m, cf, o)
	local b = self:cyl(m, 3.6, 2.6, cf * CF(0, 1.8, 0), color(o.Color) or C.RUST, MAT.CorrodedMetal, { Name = "Barrel" })
	self:cyl(m, 0.4, 2.7, cf * CF(0, 2.6, 0), C.HAZARD_YELLOW, MAT.SmoothPlastic, merge({ Name = "Band" }, DECO))
	return b
end

PROPS.crate = function(self, m, cf, o)
	local s = o.Size or 3
	local b = self:box(m, V3(s, s, s), cf * CF(0, s / 2, 0), C.WOOD_LIGHT, MAT.WoodPlanks, { Name = "Crate" })
	self:box(m, V3(s + 0.1, 0.4, s + 0.1), cf * CF(0, s * 0.5, 0), C.WOOD_DARK, MAT.Wood, merge({ Name = "Slat" }, DECO))
	return b
end

PROPS.bin = function(self, m, cf, o)
	local b = self:box(m, V3(2.2, 3.2, 2.2), cf * CF(0, 1.6, 0), color(o.Color) or Color3.fromRGB(52, 64, 78), MAT.SmoothPlastic, { Name = "Bin" })
	self:box(m, V3(2.4, 0.4, 2.4), cf * CF(0, 3.4, 0), C.GUNMETAL, MAT.SmoothPlastic, { Name = "Lid" })
	return b
end

PROPS.bollard = function(self, m, cf, o)
	local b = self:cyl(m, 3, 0.9, cf * CF(0, 1.5, 0), C.GUNMETAL, MAT.Metal, { Name = "Bollard" })
	self:cyl(m, 0.3, 0.95, cf * CF(0, 2.6, 0), color(o.Neon) or C.NEON_AMBER, MAT.Neon, merge({ Name = "Ring" }, DECO))
	return b
end

-- a planter box with a bush (o.Tree = true puts a small tree in it instead). o.Size (6)
PROPS.planter = function(self, m, cf, o)
	local s = o.Size or 6
	local b = self:box(m, V3(s, 2.4, s), cf * CF(0, 1.2, 0), C.CONCRETE_LIGHT, MAT.Concrete, { Name = "Planter" })
	self:box(m, V3(s - 0.8, 0.2, s - 0.8), cf * CF(0, 2.45, 0), Color3.fromRGB(40, 32, 26), MAT.Ground, merge({ Name = "Soil" }, DECO))
	if o.Tree then
		self:cyl(m, 7, 0.8, cf * CF(0, 5.9, 0), C.WOOD_DARK, MAT.Wood, { Name = "Trunk", CanCollide = false })
		self:ball(m, 6, cf * CF(0, 10, 0), color(o.Foliage) or C.FOLIAGE, MAT.LeafyGrass, { Name = "Leaves", CanCollide = false, CanQuery = false })
	else
		self:ball(m, s * 0.75, cf * CF(0, 3.2, 0), color(o.Foliage) or C.FOLIAGE_DARK, MAT.LeafyGrass, { Name = "Bush", CanCollide = false, CanQuery = false, CastShadow = false })
	end
	return b
end

-- a street tree (put it in Kit.decorFolder with o.Decor = true so OneForAll's windBend can sway it). o.Height (12)
PROPS.tree = function(self, m, cf, o)
	local h = o.Height or 12
	local trunk = self:cyl(m, h, 1.2, cf * CF(0, h / 2, 0), C.WOOD_DARK, MAT.Wood, { Name = "Trunk" })
	local fol = color(o.Foliage) or C.FOLIAGE
	local offs = { V3(0, h, 0), V3(1.8, h - 1.5, 0.8), V3(-1.5, h - 1, -1.2) }
	for i, off in ipairs(offs) do
		self:ball(m, (i == 1) and 8 or 6, cf * CF(off), fol, MAT.LeafyGrass, { Name = "Leaves", CanCollide = false, CanQuery = false, CastShadow = i == 1 })
	end
	if o.Grate ~= false then
		self:box(m, V3(4, 0.15, 4), cf * CF(0, 0.08, 0), C.GUNMETAL, MAT.Metal, merge({ Name = "Grate" }, DECO))
	end
	return trunk
end

PROPS.cone = function(self, m, cf, o)
	local base = self:box(m, V3(1.6, 0.2, 1.6), cf * CF(0, 0.1, 0), Color3.fromRGB(255, 110, 20), MAT.SmoothPlastic, { Name = "Base" })
	self:cyl(m, 1.8, 1.0, cf * CF(0, 1.1, 0), Color3.fromRGB(255, 110, 20), MAT.SmoothPlastic, { Name = "Cone" })
	self:cyl(m, 0.3, 1.05, cf * CF(0, 1.3, 0), C.PLASTIC_WHITE, MAT.Neon, merge({ Name = "Band" }, DECO))
	return base
end

PROPS.barrier = function(self, m, cf, o)
	local b = self:box(m, V3(6, 3, 1.6), cf * CF(0, 1.5, 0), C.CONCRETE_LIGHT, MAT.Concrete, { Name = "Barrier" })
	self:box(m, V3(6.05, 0.6, 1.65), cf * CF(0, 2.4, 0), C.HAZARD_YELLOW, MAT.SmoothPlastic, merge({ Name = "Stripe" }, DECO))
	return b
end

PROPS.hydrant = function(self, m, cf, o)
	local b = self:cyl(m, 2.4, 1.2, cf * CF(0, 1.2, 0), C.SIGNAL_RED, MAT.SmoothPlastic, { Name = "Hydrant" })
	self:ball(m, 1.2, cf * CF(0, 2.4, 0), C.SIGNAL_RED, MAT.SmoothPlastic, { Name = "Cap", CastShadow = false })
	self:box(m, V3(0.5, 0.5, 1.8), cf * CF(0, 1.6, 0), C.STEEL, MAT.Metal, { Name = "Nozzle", CastShadow = false })
	return b
end

PROPS.stool = function(self, m, cf, o)
	local seat = self:cyl(m, 0.35, 1.8, cf * CF(0, 2.6, 0), color(o.Color) or C.FABRIC_RED, MAT.Fabric, { Name = "Seat" })
	self:cyl(m, 2.4, 0.35, cf * CF(0, 1.3, 0), C.STEEL, MAT.Metal, { Name = "Pole", CastShadow = false })
	self:cyl(m, 0.2, 1.4, cf * CF(0, 0.1, 0), C.STEEL, MAT.Metal, { Name = "Foot", CastShadow = false })
	return seat
end

PROPS.chair = function(self, m, cf, o)
	local seat = self:box(m, V3(2, 0.3, 2), cf * CF(0, 1.8, 0), color(o.Color) or C.PLASTIC_BLACK, MAT.SmoothPlastic, { Name = "Seat" })
	self:box(m, V3(2, 2.0, 0.3), cf * CF(0, 2.95, 0.85), color(o.Color) or C.PLASTIC_BLACK, MAT.SmoothPlastic, { Name = "Back" })
	self:box(m, V3(0.4, 1.65, 0.4), cf * CF(0, 0.83, 0), C.STEEL, MAT.Metal, { Name = "Stem", CastShadow = false })
	return seat
end

PROPS.table = function(self, m, cf, o)
	local w, d = o.Width or 4, o.Depth or 3
	local top = self:box(m, V3(w, 0.3, d), cf * CF(0, 2.85, 0), color(o.Color) or C.WOOD_LIGHT, MAT.Wood, { Name = "Top" })
	self:box(m, V3(0.5, 2.7, 0.5), cf * CF(0, 1.35, 0), C.STEEL, MAT.Metal, { Name = "Leg", CastShadow = false })
	self:box(m, V3(math.min(w, 2), 0.2, math.min(d, 2)), cf * CF(0, 0.1, 0), C.STEEL, MAT.Metal, { Name = "Foot", CastShadow = false })
	return top
end

PROPS.aframe = function(self, m, cf, o)
	local a = self:box(m, V3(2.2, 3.2, 0.2), cf * CF(0, 1.55, -0.45) * CFrame.Angles(math.rad(-12), 0, 0), C.PLASTIC_BLACK, MAT.SmoothPlastic, { Name = "Board" })
	self:box(m, V3(2.2, 3.2, 0.2), cf * CF(0, 1.55, 0.45) * CFrame.Angles(math.rad(12), 0, 0), C.PLASTIC_BLACK, MAT.SmoothPlastic, { Name = "Back" })
	if o.Text then
		self:text(a, Enum.NormalId.Front, o.Text, { MaxDistance = 60, PixelsPerStud = 24, Color = color(o.Neon) or C.NEON_AMBER, Font = Plan.fonts.cond })
	end
	return a
end

-- spawn any prop: B:prop(kind, parent, cf, o). o.Decor = true parents it into Kit.decorFolder (trees).
-- o.Tag = false leaves it untagged (structure); o.Attrs = destruction attrs ({ HP = 120 }); o.Name
function B:prop(kind, parent, cf, o)
	o = o or {}
	local fn = PROPS[kind] or error("Kit:prop unknown kind " .. tostring(kind))
	local target = parent
	if o.Decor then
		target = Kit.decorFolder(self.root)
	end
	local m = Instance.new("Model")
	m.Name = o.Name or ("Prop_" .. kind)
	m.Parent = target
	local primary = fn(self, m, cf, o)
	m.PrimaryPart = primary
	m:SetAttribute("CityDistrict", self.district)
	if o.Tag ~= false then
		self:tag(m, "PROP", o.Attrs)
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- SPAWNS + NPC WAYPOINTS
---------------------------------------------------------------------------------------------------------------------
-- a PvP SpawnLocation at floor point pos (invisible, non-colliding pad + a flush neon ring)
function B:spawn(pos, o)
	o = o or {}
	local parent = o.Parent or Kit.folder(self.root, "Spawns")
	local s = self:part({ Class = "SpawnLocation", Parent = parent, Name = o.Name or "CitySpawn", Size = V3(8, 1, 8),
		CFrame = CF(pos + V3(0, 0.5, 0)), Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	s.Neutral = true
	s.AllowTeamChangeOnTouch = false
	s.Duration = o.Duration or 3
	s.Enabled = true
	local col = color(o.Neon) or C.NEON_CYAN
	local y = pos.Y + 0.08
	self:neon(parent, V3(8, 0.12, 0.4), CF(pos.X, y, pos.Z - 4), col, { Name = "SpawnRing" })
	self:neon(parent, V3(8, 0.12, 0.4), CF(pos.X, y, pos.Z + 4), col, { Name = "SpawnRing" })
	self:neon(parent, V3(0.4, 0.12, 8), CF(pos.X - 4, y, pos.Z), col, { Name = "SpawnRing" })
	self:neon(parent, V3(0.4, 0.12, 8), CF(pos.X + 4, y, pos.Z), col, { Name = "SpawnRing" })
	return s
end

function B:waypointAnchor()
	local wp = self.root:FindFirstChild("Waypoints")
	if not wp then
		wp = self:part({ Parent = self.root, Name = "Waypoints", Size = Vector3.one, CFrame = CF(), Transparency = 1,
			CanCollide = false, CanQuery = false, CastShadow = false })
	end
	return wp
end

-- an NPC graph node at floor point pos (WORLD coordinates; the anchor sits at the origin). kind: "sidewalk",
-- "crosswalk", "plaza", "interior", "stairs", "door", "poi", "bench", "signal-wait", "spawn".
-- attrs: Links ("id,id" - or include "@auto"), Floor, Poi ("browse"/"sit"/"stand"/"wait"/"play"/"eat"/"shop"/
-- "dance"/"drink"/"view"), Face (Vector3 the NPC faces at a POI), Capacity, Signal. Returns the node id.
function B:waypoint(pos, kind, attrs)
	local wp = self:waypointAnchor()
	self.wpN += 1
	local id = self.district .. ":" .. self.wpN
	local a = Instance.new("Attachment")
	a.Name = id
	a.Position = pos
	a:SetAttribute("Kind", kind or "interior")
	a:SetAttribute("Links", "")
	for k, v in pairs(attrs or {}) do
		a:SetAttribute(k, v)
	end
	a.Parent = wp
	self._wp[id] = a
	return id
end

function B:link(a, b)
	local A = self._wp[a] or error("Kit:link unknown node " .. tostring(a))
	local cur = A:GetAttribute("Links") or ""
	A:SetAttribute("Links", cur == "" and b or (cur .. "," .. b))
end

function B:chain(ids, loop)
	for i = 1, #ids - 1 do
		self:link(ids[i], ids[i + 1])
	end
	if loop and #ids > 2 then
		self:link(ids[#ids], ids[1])
	end
end

---------------------------------------------------------------------------------------------------------------------
-- CHECKS
---------------------------------------------------------------------------------------------------------------------
-- true if rect r lies wholly in this district's ground (or at height y in its air rights)
function B:owns(r, y)
	return Plan.rectOwnedBy(r, self.district, y)
end

-- counts everything this district built (incl. its trees in Arena.Decor) and flags contract problems.
-- returns stats, one-line summary
function B:audit(o)
	o = o or {}
	local st = { parts = 0, byClass = {}, tagged = { GLASS = 0, PANEL = 0, PROP = 0, MARK = 0 }, lights = 0, guis = 0, beams = 0,
		waypoints = 0, unanchored = 0, touch = 0, invisibleColliders = 0, noPrimary = 0, outside = 0, outsideSamples = {}, spawns = 0 }
	local tagToCat = {}
	for k, v in pairs(Kit.TAG) do
		tagToCat[v] = k
	end
	local list = self.root:GetDescendants()
	local arena = workspace:FindFirstChild("Arena")
	local decor = arena and arena:FindFirstChild("Decor")
	if decor then
		for _, c in ipairs(decor:GetChildren()) do
			if c:GetAttribute("CityDistrict") == self.district then
				table.insert(list, c)
				for _, d in ipairs(c:GetDescendants()) do
					table.insert(list, d)
				end
			end
		end
	end
	for i, d in ipairs(list) do
		if d:IsA("BasePart") then
			st.parts += 1
			st.byClass[d.ClassName] = (st.byClass[d.ClassName] or 0) + 1
			if not d.Anchored then
				st.unanchored += 1
			end
			if d.CanTouch and not d:IsA("SpawnLocation") then
				st.touch += 1
			end
			if d.Transparency >= 1 and d.CanCollide then
				st.invisibleColliders += 1
			end
			if d:IsA("SpawnLocation") then
				st.spawns += 1
			end
			if o.Ownership ~= false and d.Name ~= "Waypoints" and d.Name ~= "Anchors" and i % (o.Every or 5) == 0 then
				local p = d.Position
				if Plan.ownerAt(p.X, p.Z, p.Y) ~= self.district then
					st.outside += 1
					if #st.outsideSamples < 8 then
						table.insert(st.outsideSamples, string.format("%s @ (%.0f, %.0f, %.0f) -> %s", d:GetFullName(), p.X, p.Y, p.Z,
							tostring(Plan.ownerAt(p.X, p.Z, p.Y))))
					end
				end
			end
		elseif d:IsA("Light") then
			st.lights += 1
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			st.guis += 1
		elseif d:IsA("Beam") then
			st.beams += 1
		elseif d:IsA("Attachment") and d.Parent and d.Parent.Name == "Waypoints" then
			st.waypoints += 1
		end
		for _, tg in ipairs(CollectionService:GetTags(d)) do
			local cat = tagToCat[tg]
			if cat and st.tagged[cat] then
				st.tagged[cat] += 1
				if d:IsA("Model") and not d.PrimaryPart then
					st.noPrimary += 1
				end
			end
		end
		if i % 3000 == 0 then
			task.wait()
		end
	end
	local bud = self.budget
	st.overBudget = st.parts > bud.parts or st.lights > bud.lights or st.guis > bud.guis
	local summary = string.format(
		"%s: %d parts (budget %d), %d lights (%d), %d SurfaceGuis (%d) | tags GLASS %d PANEL %d PROP %d MARK %d | %d beams, %d waypoints, %d spawns | unanchored %d, CanTouch %d, invisible colliders %d, models without PrimaryPart %d, parts outside district (sampled) %d | %d kit warnings",
		self.district, st.parts, bud.parts, st.lights, bud.lights, st.guis, bud.guis, st.tagged.GLASS, st.tagged.PANEL, st.tagged.PROP,
		st.tagged.MARK, st.beams, st.waypoints, st.spawns, st.unanchored, st.touch, st.invisibleColliders, st.noPrimary, st.outside, #self.warnings)
	return st, summary
end

-- every PROP model this district built: the gap between its bounding-box bottom and the surface under it. Props more
-- than o.Tolerance (0.35) above (floating) or below (buried) are returned. Wall-mounted props: set attribute Mounted.
function Kit.propCheck(root, o)
	o = o or {}
	local tol = o.Tolerance or 0.35
	local list = root:GetDescendants()
	local arena = workspace:FindFirstChild("Arena")
	local decor = arena and arena:FindFirstChild("Decor")
	if decor then
		for _, c in ipairs(decor:GetChildren()) do
			if c:GetAttribute("CityDistrict") == root.Name then
				table.insert(list, c)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bad, n = {}, 0
	for _, m in ipairs(list) do
		if m:IsA("Model") and CollectionService:HasTag(m, Kit.TAG.PROP) and not m:GetAttribute("Mounted") then
			n += 1
			-- world-axis box (GetBoundingBox follows the PrimaryPart's rotation, wrong for cylinder primaries)
			local minY, x0, x1, z0, z1 = math.huge, math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then
					local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
					local s = p.Size
					local hx = 0.5 * (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z)
					local hy = 0.5 * (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z)
					local hz = 0.5 * (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z)
					local q = p.Position
					minY = math.min(minY, q.Y - hy)
					x0, x1 = math.min(x0, q.X - hx), math.max(x1, q.X + hx)
					z0, z1 = math.min(z0, q.Z - hz), math.max(z1, q.Z + hz)
				end
			end
			local bottom = V3((x0 + x1) / 2, minY, (z0 + z1) / 2)
			params.FilterDescendantsInstances = { m }
			local hit = workspace:Raycast(bottom + V3(0, 0.6, 0), V3(0, -8, 0), params)
			local gap = hit and (bottom.Y - hit.Position.Y) or math.huge
			if math.abs(gap) > tol then
				table.insert(bad, { model = m, gap = gap })
			end
			if n % 200 == 0 then
				task.wait()
			end
		end
	end
	local lines = {}
	for i = 1, math.min(#bad, 8) do
		table.insert(lines, string.format("%s gap %.2f", bad[i].model:GetFullName(), bad[i].gap))
	end
	return bad, string.format("%d props checked, %d floating/buried%s", n, #bad, #lines > 0 and (": " .. table.concat(lines, "; ")) or "")
end

-- Kit.audit("Streets") - the same report without a build in progress
function Kit.audit(district, o)
	return Kit.new(Kit.district(district)):audit(o)
end

return Kit
