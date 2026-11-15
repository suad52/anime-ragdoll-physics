--!nocheck
-- ServerStorage.ArenaGen (2026-11-14): builds the second map, THE RUINS - a walled stone arena far east of the sandbox
-- (owner: "make another map using that heavily as inspiration" - a reference screenshot of another game's arena; this
-- one has its own layout). Everything is anchored parts (no terrain), under workspace.Arenas.Ruins.
--   require(clone).build() -> the model (any old one is destroyed first)
-- Plan (local x east, z south, spawn on the south side facing north; floor top y 0):
--   green baseplate floor in 8-stud cells (same Texture as the sandbox field) with dark slate rock patches and sunk
--   water (a plunge pool, a river, a pond, small rock pools) | a cliff plateau in the north-east with steps and a
--   waterfall | a sparring ring of ruined columns in the middle + loose columns over the field | a training yard with
--   dummy stations in the south-west | a grove along the walls | a spawn plaza with an arch in the south | stone walls
--   with buttresses and corner towers, plus invisible bounds to y 390 like the sandbox's.
local CS = game:GetService("CollectionService")
local Gen = {}
local C = Color3.fromRGB
local CENTRE = Vector3.new(1600, 0, 0)
local HALF = 184 -- floor runs -184..184 (multiples of 8: the baseplate texture runs on across plates)
local CELL = 8
Gen.CENTRE, Gen.HALF = CENTRE, HALF

local GRASS = C(38, 94, 58) -- (2026-11-14) toned down from (60,140,50): the colour grade (Lighting.Grade, saturation +0.18) made it near neon
local ROCK = C(70, 74, 84)
local WATER = C(54, 128, 214)
local WALL = C(150, 132, 146)
local BUTTRESS = C(86, 90, 112)
local CLIFF = C(92, 100, 128)
local PILLAR = C(204, 202, 196)
local TRUNK = C(98, 64, 40)
local LEAF = { C(30, 84, 44), C(36, 94, 50), C(26, 74, 40) }

local rng
local function W(x, y, z)
	return CENTRE + Vector3.new(x, y, z)
end
local function part(parent, name, size, cf, color, mat, o)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if o then
		for k, v in pairs(o) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end
local function box(parent, name, x0, y0, z0, x1, y1, z1, color, mat, o)
	return part(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), CFrame.new(W((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)), color, mat, o)
end
local function grid(p)
	local t = Instance.new("Texture")
	t.Texture = "rbxassetid://6372755229"
	t.Face = Enum.NormalId.Top
	t.StudsPerTileU, t.StudsPerTileV = 8, 8
	t.Color3 = Color3.new(0, 0, 0)
	t.Transparency = 0.8
	-- a texture's tiles start at the face's +X / +Z edge: line them up with the world's 8-stud grid
	local maxX, maxZ = p.Position.X + p.Size.X / 2, p.Position.Z + p.Size.Z / 2
	t.OffsetStudsU = maxX % 8
	t.OffsetStudsV = maxZ % 8
	t.Parent = p
	return t
end
local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-------------------------------------------------------------------------------------------------------------- layout
local N = (HALF * 2) / CELL -- 46 cells a side
local function cellCentre(i, k)
	return -HALF + (i - 0.5) * CELL, -HALF + (k - 0.5) * CELL
end
local function segDist(px, pz, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
	local qx, qz = ax + dx * t, az + dz * t
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
end
local PLATEAU = { 40, -184, 184, -104 } -- x0, z0, x1, z1 (its south face is broken up by terraces below)
local POOL = { 80, -104, 128, -72 }
local RIVER = { { 104, -76 }, { 112, -40 }, { 136, -4 }, { 140, 40 }, { 128, 76 } }
local POND = { 124, 96, 40, 30 } -- centre x, z, radius x, z
local ROCKS = { { 96, -24, 44 }, { 150, 30, 30 }, { 124, 120, 50 }, { 64, 48, 22 }, { -150, -150, 26 }, { -120, -60, 16 } } -- x, z, radius
local SMALL_POOLS = { { 72, -8, 12, 10 }, { 150, -60, 14, 10 }, { 84, 116, 10, 14 } } -- x, z, half sizes
local RING = { -32, 8, 34 }
local PLAZA = { -48, 128, 48, 184 }

local function kindOf(x, z)
	if x >= PLATEAU[1] and z <= PLATEAU[4] then
		return "none"
	end
	if x >= POOL[1] and x <= POOL[3] and z >= POOL[2] and z <= POOL[4] then
		return "water"
	end
	for i = 1, #RIVER - 1 do
		local a, b = RIVER[i], RIVER[i + 1]
		if segDist(x, z, a[1], a[2], b[1], b[2]) < 8 then
			return "water"
		end
	end
	if ((x - POND[1]) / POND[3]) ^ 2 + ((z - POND[2]) / POND[4]) ^ 2 < 1 then
		return "water"
	end
	for _, s in ipairs(SMALL_POOLS) do
		if math.abs(x - s[1]) < s[3] and math.abs(z - s[2]) < s[4] then
			return "water"
		end
	end
	for _, r in ipairs(ROCKS) do
		local wob = 0.85 + 0.15 * math.sin(x * 0.21 + z * 0.13)
		if (x - r[1]) ^ 2 + (z - r[2]) ^ 2 < (r[3] * wob) ^ 2 then
			return "rock"
		end
	end
	return "grass"
end

-- greedy rectangles of one kind over the cell grid
local function rects(kinds, want)
	local used = {}
	for i = 1, N do
		used[i] = {}
	end
	local out = {}
	for k = 1, N do
		for i = 1, N do
			if kinds[i][k] == want and not used[i][k] then
				local w = 1
				while i + w <= N and kinds[i + w][k] == want and not used[i + w][k] do
					w += 1
				end
				local h = 1
				while k + h <= N do
					local ok = true
					for ii = i, i + w - 1 do
						if kinds[ii][k + h] ~= want or used[ii][k + h] then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					h += 1
				end
				for ii = i, i + w - 1 do
					for kk = k, k + h - 1 do
						used[ii][kk] = true
					end
				end
				table.insert(out, { -HALF + (i - 1) * CELL, -HALF + (k - 1) * CELL, -HALF + (i - 1 + w) * CELL, -HALF + (k - 1 + h) * CELL })
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------------------------------------- pieces
local function column(parent, x, z, h, o)
	o = o or {}
	local m = Instance.new("Model")
	m.Name = "Column"
	local base = o.y or 0
	part(m, "Plinth", Vector3.new(6, 1.2, 6), CFrame.new(W(x, base + 0.6, z)), PILLAR:Lerp(C(0, 0, 0), 0.12), Enum.Material.Concrete)
	local shaft = part(m, "Shaft", Vector3.new(4, h, 4), CFrame.new(W(x, base + 1.2 + h / 2, z)), PILLAR, Enum.Material.Concrete)
	if o.broken then
		-- a jagged top: two chunks of what is left, at different heights
		part(m, "Chunk", Vector3.new(2.2, 1.6, 4), CFrame.new(W(x - 0.9, base + 1.2 + h + 0.8, z)) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-12, 12))), PILLAR, Enum.Material.Concrete)
		part(m, "Chunk", Vector3.new(1.8, 0.9, 2.4), CFrame.new(W(x + 1, base + 1.2 + h + 0.45, z + 0.8)), PILLAR, Enum.Material.Concrete)
	else
		part(m, "Cap", Vector3.new(5.6, 1, 5.6), CFrame.new(W(x, base + 1.2 + h + 0.5, z)), PILLAR:Lerp(C(0, 0, 0), 0.12), Enum.Material.Concrete)
	end
	CS:AddTag(m, "CityProp") -- (2026-11-14) breakable: ServerScriptService.CityDestruction knocks it over and regrows it
	if o.tilt then
		m:PivotTo(CFrame.new(W(x, base, z)) * CFrame.Angles(math.rad(o.tilt[1]), 0, math.rad(o.tilt[2])) * CFrame.new(-W(x, base, z)) * m:GetPivot())
	end
	m.Parent = parent
	return m
end
local function fallen(parent, x, z, len, yaw)
	local cf = CFrame.new(W(x, 2, z)) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(0, 0, math.rad(90 + rng:NextNumber(-4, 4)))
	local p = part(parent, "FallenColumn", Vector3.new(4, len, 4), cf, PILLAR, Enum.Material.Concrete)
	CS:AddTag(p, "CityProp")
	return p
end
local function tree(parent, x, z, s, base)
	s = s or 1
	base = base or 0
	local m = Instance.new("Model")
	m.Name = "Tree"
	local th = rng:NextNumber(7, 11) * s
	part(m, "Trunk", Vector3.new(2, th, 2) * Vector3.new(s, 1, s), CFrame.new(W(x, base + th / 2, z)), TRUNK, Enum.Material.Wood)
	local leaf = LEAF[rng:NextInteger(1, #LEAF)]
	local y = base + th
	local w = rng:NextNumber(9, 12) * s
	for i = 1, rng:NextInteger(2, 3) do
		local h = rng:NextNumber(3.5, 5) * s
		part(m, "Leaves", Vector3.new(w, h, w), CFrame.new(W(x + rng:NextNumber(-0.8, 0.8), y + h / 2 - 0.4, z + rng:NextNumber(-0.8, 0.8))) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0),
			leaf:Lerp(C(255, 255, 255), (i - 1) * 0.06), Enum.Material.SmoothPlastic)
		y += h - 0.6
		w *= 0.68
	end
	CS:AddTag(m, "CityProp")
	m.Parent = parent
	return m
end
local function boulder(parent, x, z, s)
	local p = part(parent, "Boulder", Vector3.new(rng:NextNumber(3, 6), rng:NextNumber(2.5, 4.5), rng:NextNumber(3, 6)) * s,
		CFrame.new(W(x, 1, z)) * CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-15, 15))), C(120, 126, 138), Enum.Material.Slate)
	CS:AddTag(p, "CityProp")
	return p
end
local function lantern(parent, x, z)
	local m = Instance.new("Model")
	m.Name = "Lantern"
	part(m, "Base", Vector3.new(3, 1, 3), CFrame.new(W(x, 0.5, z)), C(150, 150, 150), Enum.Material.Slate)
	part(m, "Post", Vector3.new(1.2, 4, 1.2), CFrame.new(W(x, 3, z)), C(150, 150, 150), Enum.Material.Slate)
	local lamp = part(m, "Lamp", Vector3.new(2.4, 2, 2.4), CFrame.new(W(x, 6, z)), C(255, 214, 140), Enum.Material.Neon)
	part(m, "Roof", Vector3.new(3.6, 0.8, 3.6), CFrame.new(W(x, 7.4, z)), C(120, 120, 124), Enum.Material.Slate)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = C(255, 200, 130), 14, 0.8
	l.Parent = lamp
	CS:AddTag(m, "CityProp")
	m.Parent = parent
end
local function sign(parent, text, cf, size)
	local b = part(parent, "Sign", size, cf, C(14, 14, 16), Enum.Material.SmoothPlastic)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.PixelsPerStud = 30
	g.LightInfluence = 0
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.Parent = b
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(0.92, 0.8)
	t.Position = UDim2.fromScale(0.04, 0.1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextWrapped = false -- (before TextScaled: setting TextWrapped false afterwards switches TextScaled off - measured)
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	t.Parent = g
	return b
end

---------------------------------------------------------------------------------------------------------------- build
function Gen.build()
	rng = Random.new(20261114)
	local arenas = workspace:FindFirstChild("Arenas") or Instance.new("Folder")
	arenas.Name = "Arenas"
	arenas.Parent = workspace
	local old = arenas:FindFirstChild("Ruins")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Ruins"
	model:SetAttribute("Title", "THE RUINS")
	model:SetAttribute("Centre", CENTRE)
	model:SetAttribute("Half", HALF)
	local floorF = folder(model, "Floor")
	local water = folder(model, "Water")
	local cliff = folder(model, "Cliff")
	local walls = folder(model, "Walls")
	walls:SetAttribute("Unbreakable", true) -- (2026-11-14) the outer walls, buttresses and towers never get holes (CityDestruction.Structure)
	local ruins = folder(model, "Columns")
	local grove = folder(model, "Grove")
	local yard = folder(model, "Yard")
	local plaza = folder(model, "Plaza")
	local spawns = folder(model, "Spawns")

	-- FLOOR ---------------------------------------------------------------------------------------------------------
	local kinds = {}
	for i = 1, N do
		kinds[i] = {}
		for k = 1, N do
			local x, z = cellCentre(i, k)
			kinds[i][k] = kindOf(x, z)
		end
	end
	for _, r in ipairs(rects(kinds, "grass")) do
		local p = box(floorF, "Grass", r[1], -4, r[2], r[3], 0, r[4], GRASS, Enum.Material.Plastic)
		grid(p)
	end
	for _, r in ipairs(rects(kinds, "rock")) do
		box(floorF, "Rock", r[1], -4, r[2], r[3], 0, r[4], ROCK, Enum.Material.Slate)
	end
	for _, r in ipairs(rects(kinds, "water")) do
		local bed = box(floorF, "PoolBed", r[1], -6, r[2], r[3], -3, r[4], C(52, 60, 70), Enum.Material.Slate)
		-- (2026-11-15) the wandering NPCs' paths (Sandbox.Wanderers: Costs.Water = huge) go round the pools, not through
		local mod = Instance.new("PathfindingModifier")
		mod.Label = "Water"
		mod.Parent = bed
		box(water, "Water", r[1], -3, r[2], r[3], -0.7, r[4], WATER, Enum.Material.SmoothPlastic,
			{ Transparency = 0.35, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	-- footbridges over the river
	for _, b in ipairs({ { 124, -22, 30 }, { 138, 58, -20 } }) do
		local cf = CFrame.new(W(b[1], 0.35, b[2])) * CFrame.Angles(0, math.rad(b[3]), 0)
		part(floorF, "Bridge", Vector3.new(22, 0.7, 7), cf, C(140, 98, 60), Enum.Material.WoodPlanks)
		for _, s in ipairs({ -1, 1 }) do
			part(floorF, "Rail", Vector3.new(22, 0.5, 0.5), cf * CFrame.new(0, 2.4, s * 3.2), C(110, 74, 44), Enum.Material.Wood)
			for _, xo in ipairs({ -10, 0, 10 }) do
				part(floorF, "RailPost", Vector3.new(0.5, 2.4, 0.5), cf * CFrame.new(xo, 1.2, s * 3.2), C(110, 74, 44), Enum.Material.Wood)
			end
		end
	end

	-- CLIFF: a plateau in the north-east, terraced on its south and west faces, with steps and a waterfall --------------
	local P0, P1 = PLATEAU, nil
	box(cliff, "Cliff", P0[1], -4, P0[2], P0[3], 22, P0[4], CLIFF, Enum.Material.Slate)
	local cap = box(cliff, "CliffTop", P0[1], 22, P0[2], P0[3], 23, P0[4], GRASS, Enum.Material.Plastic)
	grid(cap)
	-- terraces (lower ledges standing out from the faces)
	for _, t in ipairs({ { 40, -112, 76, -96, 9 }, { 128, -104, 176, -92, 6 }, { 150, -110, 184, -100, 14 }, { 30, -150, 44, -118, 12 }, { 160, -98, 184, -86, 3 } }) do
		box(cliff, "Ledge", t[1], -4, t[2], t[3], t[5], t[4], CLIFF:Lerp(C(255, 255, 255), 0.06), Enum.Material.Slate)
		local top = box(cliff, "LedgeTop", t[1], t[5], t[2], t[3], t[5] + 0.6, t[4], GRASS, Enum.Material.Plastic)
		grid(top)
	end
	-- steps up the west face: 11 of them, from the ground at x 10 to the top at x 40
	for s = 0, 10 do
		local x0 = 10 + s * 2.73
		box(cliff, "Step", x0, -4, -172, x0 + 2.73, (s + 1) * 2.1, -152, CLIFF:Lerp(C(255, 255, 255), 0.12), Enum.Material.Slate)
	end
	-- the river on top, and the fall
	box(water, "Stream", 98, 23, -184, 110, 23.4, -104, WATER, Enum.Material.SmoothPlastic, { Transparency = 0.3, CanCollide = false, CanQuery = false })
	local fall = box(water, "Waterfall", 97, -0.7, -104.6, 111, 23.4, -103.2, C(120, 180, 240), Enum.Material.SmoothPlastic,
		{ Transparency = 0.25, CanCollide = false, CanQuery = false, CastShadow = false })
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, -fall.Size.Y / 2 + 0.5, 1.5)
	a.Parent = fall
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.new(1, 1, 1))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	mist.Lifetime = NumberRange.new(1.2, 2)
	mist.Rate = 26
	mist.Speed = NumberRange.new(3, 7)
	mist.SpreadAngle = Vector2.new(70, 30)
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	mist.Parent = a
	box(water, "Foam", 94, -0.75, -103, 114, -0.55, -94, C(235, 245, 255), Enum.Material.SmoothPlastic, { Transparency = 0.25, CanCollide = false, CanQuery = false })
	-- trees on the plateau
	for _ = 1, 9 do
		tree(grove, rng:NextNumber(60, 176), rng:NextNumber(-178, -116), rng:NextNumber(0.9, 1.15), 23)
	end

	-- WALLS: stone, with buttresses every 32 studs and towers at the corners ------------------------------------------
	local H, T = 28, 6
	box(walls, "Wall", -HALF - T, -4, -HALF - T, HALF + T, H, -HALF, WALL, Enum.Material.Sandstone)
	box(walls, "Wall", -HALF - T, -4, HALF, HALF + T, H, HALF + T, WALL, Enum.Material.Sandstone)
	box(walls, "Wall", -HALF - T, -4, -HALF, -HALF, H, HALF, WALL, Enum.Material.Sandstone)
	box(walls, "Wall", HALF, -4, -HALF, HALF + T, H, HALF, WALL, Enum.Material.Sandstone)
	-- a darker band along the top
	for _, s in ipairs({ { -HALF - T - 0.5, -HALF - T - 0.5, HALF + T + 0.5, -HALF + 0.5 }, { -HALF - T - 0.5, HALF - 0.5, HALF + T + 0.5, HALF + T + 0.5 },
		{ -HALF - T - 0.5, -HALF, -HALF + 0.5, HALF }, { HALF - 0.5, -HALF, HALF + T + 0.5, HALF } }) do
		box(walls, "Coping", s[1], H, s[2], s[3], H + 1.4, s[4], BUTTRESS, Enum.Material.Slate)
	end
	for v = -HALF + 16, HALF - 16, 32 do
		for _, side in ipairs({ { v, -HALF }, { v, HALF }, { -HALF, v }, { HALF, v } }) do
			local x, z = side[1], side[2]
			local alongX = (z == -HALF or z == HALF)
			local sx, sz = alongX and 6 or 9, alongX and 9 or 6
			box(walls, "Buttress", x - sx / 2, -4, z - sz / 2, x + sx / 2, H + 4, z + sz / 2, BUTTRESS, Enum.Material.Slate)
			box(walls, "ButtressCap", x - sx / 2 - 1, H + 4, z - sz / 2 - 1, x + sx / 2 + 1, H + 5.6, z + sz / 2 + 1, BUTTRESS:Lerp(C(255, 255, 255), 0.15), Enum.Material.Slate)
		end
	end
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local x, z = c[1] * (HALF + 1), c[2] * (HALF + 1)
		box(walls, "Tower", x - 9, -4, z - 9, x + 9, H + 10, z + 9, BUTTRESS, Enum.Material.Slate)
		box(walls, "TowerCap", x - 10.5, H + 10, z - 10.5, x + 10.5, H + 12, z + 10.5, BUTTRESS:Lerp(C(255, 255, 255), 0.15), Enum.Material.Slate)
	end
	-- invisible bounds above the walls (the jump / gravity sliders), the same height as the sandbox's
	for _, b in ipairs({ { -HALF - T, -HALF - T - 2, HALF + T, -HALF - T }, { -HALF - T, HALF + T, HALF + T, HALF + T + 2 }, { -HALF - T - 2, -HALF - T, -HALF - T, HALF + T },
		{ HALF + T, -HALF - T, HALF + T + 2, HALF + T } }) do
		box(walls, "Bounds", b[1], -10, b[2], b[3], 390, b[4], C(255, 255, 255), Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false, CastShadow = false })
	end

	-- RUINS: the sparring ring, columns over the field, fallen ones --------------------------------------------------
	local rx, rz, rr = RING[1], RING[2], RING[3]
	local disc = part(ruins, "RingFloor", Vector3.new(0.4, rr * 2, rr * 2), CFrame.new(W(rx, 0.2, rz)) * CFrame.Angles(0, 0, math.rad(90)), C(176, 172, 164), Enum.Material.Concrete)
	disc.Shape = Enum.PartType.Cylinder
	local inner = part(ruins, "RingInner", Vector3.new(0.5, rr * 1.2, rr * 1.2), CFrame.new(W(rx, 0.25, rz)) * CFrame.Angles(0, 0, math.rad(90)), C(150, 146, 140), Enum.Material.Concrete)
	inner.Shape = Enum.PartType.Cylinder
	for i = 0, 9 do
		local ang = i / 10 * math.pi * 2 + 0.2
		local x, z = rx + math.cos(ang) * (rr - 4), rz + math.sin(ang) * (rr - 4)
		if i == 3 or i == 7 then
			fallen(ruins, x + math.cos(ang) * 7, z + math.sin(ang) * 7, 16, math.deg(-ang) + rng:NextNumber(-25, 25))
			part(ruins, "Plinth", Vector3.new(6, 1.2, 6), CFrame.new(W(x, 0.6, z)), PILLAR:Lerp(C(0, 0, 0), 0.12), Enum.Material.Concrete)
		elseif i % 3 == 1 then
			column(ruins, x, z, rng:NextNumber(5, 10), { broken = true })
		else
			column(ruins, x, z, 18, { y = 0.4 })
		end
	end
	local spots = { { -120, -120 }, { -64, -150 }, { -10, -96 }, { 12, -40 }, { -110, -20 }, { -150, 30 }, { 40, 100 }, { 0, 70 }, { -80, 80 }, { 70, -48 }, { 168, -12 }, { 96, 60 },
		{ 160, 150 }, { -40, -60 }, { 20, 140 } }
	for i, s in ipairs(spots) do
		local k = kindOf(s[1], s[2])
		local broken = (i % 3 == 0)
		local h = broken and rng:NextNumber(6, 12) or rng:NextNumber(18, 24)
		local onPlaza = s[1] > PLAZA[1] - 6 and s[1] < PLAZA[3] + 6 and s[2] > PLAZA[2] - 6
		if (k == "rock" or k == "grass") and not onPlaza then
			column(ruins, s[1], s[2], h, { broken = broken, tilt = (i % 4 == 2) and { rng:NextNumber(-6, 6), rng:NextNumber(-6, 6) } or nil })
		end
	end
	for _, f in ipairs({ { 30, 20, 18, 30 }, { 110, 20, 14, -60 }, { -90, -100, 20, 10 }, { 150, 110, 12, 80 }, { 60, -60, 16, -15 } }) do
		fallen(ruins, f[1], f[2], f[3], f[4])
	end
	for _ = 1, 26 do
		local x, z = rng:NextNumber(40, 176), rng:NextNumber(-90, 176)
		if kindOf(x, z) == "rock" then
			boulder(ruins, x, z, rng:NextNumber(0.7, 1.4))
		end
	end

	-- GROVE: trees along the walls and a stand in the north-west ----------------------------------------------------
	for _ = 1, 70 do
		local side = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-HALF + 14, HALF - 14)
		local inset = rng:NextNumber(10, 26)
		local x, z
		if side == 1 then
			x, z = along, -HALF + inset
		elseif side == 2 then
			x, z = along, HALF - inset
		elseif side == 3 then
			x, z = -HALF + inset, along
		else
			x, z = HALF - inset, along
		end
		local clearOfPlaza = not (x > PLAZA[1] - 10 and x < PLAZA[3] + 10 and z > PLAZA[2] - 10)
		if kindOf(x, z) == "grass" and clearOfPlaza and not (x < -100 and z > 50) then
			tree(grove, x, z, rng:NextNumber(0.85, 1.2))
		end
	end
	for _ = 1, 16 do
		local x, z = rng:NextNumber(-170, -90), rng:NextNumber(-170, -90)
		if kindOf(x, z) == "grass" then
			tree(grove, x, z, rng:NextNumber(0.9, 1.3))
		end
	end
	for _ = 1, 40 do -- small bushes
		local x, z = rng:NextNumber(-176, 176), rng:NextNumber(-176, 176)
		if kindOf(x, z) == "grass" and ((x - rx) ^ 2 + (z - rz) ^ 2) > (rr + 8) ^ 2 and not (z > PLAZA[2] - 8 and math.abs(x) < 60) then
			local s = rng:NextNumber(2, 3.6)
			part(grove, "Bush", Vector3.new(s * 1.3, s, s * 1.3), CFrame.new(W(x, s / 2 - 0.2, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), LEAF[rng:NextInteger(1, 3)], Enum.Material.SmoothPlastic)
		end
	end

	-- TRAINING YARD (south-west): a fenced square, dummy stations, a rack of posts ------------------------------------
	local Y0, Y1 = { -168, 70 }, { -100, 150 }
	local yardFloor = box(yard, "YardFloor", Y0[1], 0, Y0[2], Y1[1], 0.3, Y1[2], C(180, 150, 110), Enum.Material.Sand)
	for x = Y0[1], Y1[1], 8.5 do
		for _, z in ipairs({ Y0[2], Y1[2] }) do
			box(yard, "FencePost", x - 0.5, 0, z - 0.5, x + 0.5, 4.5, z + 0.5, C(120, 84, 52), Enum.Material.Wood)
		end
	end
	for z = Y0[2], Y1[2], 8.75 do
		for _, x in ipairs({ Y0[1], Y1[1] }) do
			if not (x == Y1[1] and z > 95 and z < 125) then -- the gate, facing the plaza
				box(yard, "FencePost", x - 0.5, 0, z - 0.5, x + 0.5, 4.5, z + 0.5, C(120, 84, 52), Enum.Material.Wood)
			end
		end
	end
	for _, rail in ipairs({ { Y0[1], Y0[2], Y1[1], Y0[2] }, { Y0[1], Y1[2], Y1[1], Y1[2] }, { Y0[1], Y0[2], Y0[1], Y1[2] } }) do
		for _, h in ipairs({ 1.6, 3.4 }) do
			box(yard, "FenceRail", math.min(rail[1], rail[3]) - 0.3, h - 0.25, math.min(rail[2], rail[4]) - 0.3, math.max(rail[1], rail[3]) + 0.3, h + 0.25, math.max(rail[2], rail[4]) + 0.3,
				C(140, 100, 64), Enum.Material.Wood)
		end
	end
	local n = 0
	for _, x in ipairs({ -154, -134, -114 }) do
		for _, z in ipairs({ 88, 112, 136 }) do
			n += 1
			local s = part(yard, "Station", Vector3.new(2, 0.2, 2), CFrame.new(W(x, 0.4, z)) * CFrame.Angles(0, math.rad(0), 0), C(176, 172, 164), Enum.Material.SmoothPlastic,
				{ Transparency = 1, CanCollide = false })
			s:SetAttribute("Kind", "stand")
			s:SetAttribute("Every", 6)
			s:SetAttribute("Max", 1)
			CS:AddTag(s, "DummyStation")
			local mark = part(yard, "BayMark", Vector3.new(0.12, 5, 5), CFrame.new(W(x, 0.36, z)) * CFrame.Angles(0, 0, math.rad(90)), C(120, 90, 60), Enum.Material.SmoothPlastic)
			mark.Shape = Enum.PartType.Cylinder
		end
	end
	sign(yard, "TRAINING YARD", CFrame.new(W(-100, 7.5, 154)) * CFrame.Angles(0, math.rad(180 - 45), 0) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 2.6, 0.5))
	for _, x in ipairs({ -104, -96 }) do
		box(yard, "SignPost", x - 0.35, 0, 153.65, x + 0.35, 6.2, 154.35, C(14, 14, 16), Enum.Material.SmoothPlastic)
	end
	-- loose stations out on the field too, by the ring and in the quarry
	for _, s in ipairs({ { -32, 8 }, { -46, -6 }, { -18, 22 }, { 80, -30 }, { 150, 46 }, { 40, 60 } }) do
		local st = part(ruins, "Station", Vector3.new(2, 0.2, 2), CFrame.new(W(s[1], kindOf(s[1], s[2]) == "grass" and 0.1 or 0.5, s[2])), C(176, 172, 164), Enum.Material.SmoothPlastic,
			{ Transparency = 1, CanCollide = false })
		st:SetAttribute("Kind", "stand")
		st:SetAttribute("Every", 8)
		st:SetAttribute("Max", 1)
		CS:AddTag(st, "DummyStation")
	end

	-- PLAZA + ARCH + SPAWNS (south) ---------------------------------------------------------------------------------
	box(plaza, "Plaza", PLAZA[1], 0, PLAZA[2], PLAZA[3], 0.3, PLAZA[4], C(190, 186, 178), Enum.Material.Concrete)
	for x = PLAZA[1], PLAZA[3] - 8, 8 do
		for z = PLAZA[2], PLAZA[4] - 8, 8 do
			if ((x + z) / 8) % 2 == 0 then
				box(plaza, "Tile", x + 0.3, 0.3, z + 0.3, x + 7.7, 0.36, z + 7.7, C(170, 166, 158), Enum.Material.Concrete)
			end
		end
	end
	-- a path of stepping stones from the plaza to the ring
	for i = 0, 9 do
		local t = i / 9
		local x, z = 0 + (rx - 0) * t, PLAZA[2] - 4 + (rz + rr + 4 - (PLAZA[2] - 4)) * t
		part(plaza, "Stone", Vector3.new(5, 0.3, 4), CFrame.new(W(x + rng:NextNumber(-1, 1), 0.15, z)) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0), C(176, 172, 164), Enum.Material.Concrete)
	end
	-- (2026-11-15, owner: "remove that arc right infront of the player spawn") the stone arch with the THE RUINS boards
	-- that stood at the plaza's north edge, between the spawns and the arena, is gone (old code: Backup_2026-11-15_noarch.ArenaGen_before)
	for _, x in ipairs({ -30, -18, 18, 30 }) do
		lantern(plaza, x, PLAZA[2] - 6)
	end
	for i, s in ipairs({ { -10, 146 }, { 0, 150 }, { 10, 146 }, { -18, 158 }, { 18, 158 }, { 0, 162 } }) do
		-- (2026-11-14, owner: "make it to where the user starts off in the ruins map") real SpawnLocations: ServerScriptService
		-- MapSwitch points each player's RespawnLocation at one of these, so they appear here directly
		local pad = Instance.new("SpawnLocation")
		pad.Name = "Spawn"
		pad.Anchored = true
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.3, 5, 5)
		pad.CFrame = CFrame.new(W(s[1], 0.45, s[2])) * CFrame.Angles(0, 0, math.rad(90)) -- (LookVector stays north: they face into the arena)
		pad.Color, pad.Material, pad.Transparency = C(110, 200, 255), Enum.Material.Neon, 0.45
		pad.TopSurface, pad.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		pad.CanCollide = false
		pad.Neutral, pad.Enabled, pad.Duration, pad.AllowTeamChangeOnTouch = true, true, 2, false
		pad.Parent = spawns
	end

	-- the smaller pieces that break on their own
	local BREAK = { Bush = true, FencePost = true, FenceRail = true, Rail = true, RailPost = true, Sign = true, SignPost = true, Plinth = true }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and BREAK[d.Name] and not d.Parent:IsA("Model") and d.Parent.Name ~= "Plaza" then
			CS:AddTag(d, "CityProp")
		end
	end
	model.Parent = arenas
	return model
end

return Gen
