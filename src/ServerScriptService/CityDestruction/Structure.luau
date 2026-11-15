--!nocheck
-- ServerScriptService.CityDestruction.Structure (orchestrator 2026-11-07): ability damage to the buildings and the
-- ground. Fed every impact by Service.impact (S.onImpact) - WorldBlast, BreakBlast and giant-form crashes.
--  HOLES: a structural block part (wall, facade, pillar, building mass) caught by a blast is split around a cut box
--    (<= 6 axis-aligned remainder slabs), with rubble teeth on the rim and debris chunks flung out of the hole. The
--    original part is parked in ServerStorage and comes back REGEN s after its last hit (nobody in the way). A piece
--    can be cut again. Floors / roofs / decks / steps (thin, thin side up), tagged breakables (the Service's job),
--    invisible colliders and the boundary are never cut.
--  CRATERS: a street-level blast scorches a ring (FillCylinder SCORCH) and blows out a bowl (FillBall Air) + asphalt
--    chunks. Healing writes back a snapshot of the region taken first and FLATTENED (solid below the street, half
--    the street layer, air above) - so the repave is always clean ground even where another kit's crater overlapped.
--    (2026-11-07 ground pass) Every air ball goes through CityShared.GroundGuard.clampBall: the bowl is lifted so it is
--    never deeper than DestructionConfig.GROUND.MAX_DEPTH below the street - a shallow scorched dish, never a pit. The
--    molten core lines the bottom of that dish. Floors / decks are anything up to STRUCTURE.FLOOR_THICK (4.8: the
--    Highway deck slabs are 4.6) thick with the thin side up.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local Structure = {}

local V3 = Vector3.new
local min, max, clamp, random = math.min, math.max, math.clamp, math.random
local TAGS = { "CityGlass", "CityPanel", "CityProp", "CityMark" }

function Structure.start(S, CFG)
	local C = CFG and CFG.STRUCTURE
	if not C or C.ENABLED == false then
		return nil
	end
	-- (2026-11-14, ragdoll sandbox) there is no city here: the walls, columns and cliff of the second maps
	-- (workspace.Arenas - THE RUINS) are what get holes punched in them. Craters stay off without the city: they are
	-- dug in TERRAIN and healed by flattening it to the city's street level (GROUND_Y 2) - on the sandbox field (grass
	-- at y -0.4 under its baseplate plates, hills) that would raise and level the ground. The Ruins have no terrain.
	local city = workspace:FindFirstChild("City") or workspace:WaitForChild("Arenas", 30)
	if not city then
		return nil
	end
	local cratersOn = city.Name == "City"
	local terrain = workspace.Terrain
	local GROUND = C.GROUND_Y or 2
	local GroundGuard = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("GroundGuard"))
	local function airBall(c, r) -- a depth-capped FillBall Air; returns the ball actually carved (or nil)
		local c2, r2 = GroundGuard.clampBall(c, r)
		if c2 then
			terrain:FillBall(c2, r2, Enum.Material.Air)
		end
		return c2, r2
	end
	local park = ServerStorage:FindFirstChild("CityFractured") or Instance.new("Folder")
	park.Name = "CityFractured"
	park.Parent = ServerStorage
	local debrisFolder = workspace:FindFirstChild("CityDebris") or Instance.new("Folder")
	debrisFolder.Name = "CityDebris"
	debrisFolder.Parent = workspace

	local counts = { holes = 0, cuts = 0, craters = 0, heals = 0, rebuilt = 0, pieces = 0, chunks = 0 }
	S.counts.structure = counts

	-- what may be cut ---------------------------------------------------------------------------------------
	local verdict = setmetatable({}, { __mode = "k" })
	local function tagged(inst)
		local x = inst
		while x and x ~= city do
			for _, t in ipairs(TAGS) do
				if CollectionService:HasTag(x, t) then
					return true
				end
			end
			-- (2026-11-14, owner: "for the ruins, make it to where u cant break the outer walls, only the stuff on the
			-- inside") a folder / model with attribute Unbreakable = true protects everything in it (THE RUINS' Walls)
			if x.Name == "Boundary" or x.Name == "Waypoints" or x.Name == "Spawns" or x.Name == "Water" or x:GetAttribute("Unbreakable") == true then
				return true
			end
			x = x.Parent
		end
		return false
	end
	local function structural(p)
		local v = verdict[p]
		if v ~= nil then
			return v
		end
		v = false
		if p:IsA("Part") and p.Shape == Enum.PartType.Block and p.Anchored and p.Transparency < 0.85 and not p:IsA("SpawnLocation")
			and p:IsDescendantOf(city) then
			local cf, s = p.CFrame, p.Size
			local upright = math.abs(cf.UpVector.Y) > 0.95 or math.abs(cf.RightVector.Y) > 0.95 or math.abs(cf.LookVector.Y) > 0.95
			if upright then
				local thin, axis = s.X, cf.RightVector
				if s.Y < thin then
					thin, axis = s.Y, cf.UpVector
				end
				if s.Z < thin then
					thin, axis = s.Z, cf.LookVector
				end
				local floor = thin <= (C.FLOOR_THICK or 4) and math.abs(axis.Y) > 0.8
				v = (not floor) and not tagged(p)
			end
		end
		verdict[p] = v
		return v
	end

	-- records: [original part] = { parent, pieces = {set}, lastHit, cf, size }; pieceOf[piece] = original
	local recs, pieceOf = {}, setmetatable({}, { __mode = "k" })
	local order = {} -- originals in first-hit order (oldest rebuilt first when over the cap)

	local function copyLook(from, to)
		to.Color = from.Color
		to.Material = from.Material
		to.MaterialVariant = from.MaterialVariant
		to.Reflectance = from.Reflectance
		to.Transparency = from.Transparency
		to.CastShadow = from.CastShadow and to.Size.Magnitude > 4
		to.CanCollide = from.CanCollide
		to.CanQuery = from.CanQuery
		to.CanTouch = false
		to.Anchored = true
		to.TopSurface, to.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		for _, t in ipairs(from:GetChildren()) do
			if t:IsA("Texture") then
				t:Clone().Parent = to
			end
		end
	end

	local liveChunks = 0
	local function chunk(pos, size, color, material, vel)
		if liveChunks >= (C.MAX_CHUNKS or 160) then
			return
		end
		local c = Instance.new("Part")
		c.Size = size
		c.CFrame = CFrame.new(pos) * CFrame.Angles(random() * 6.28, random() * 6.28, random() * 6.28)
		c.Color = color
		c.Material = material
		c.CanTouch = false
		c.CanQuery = false
		c.CastShadow = false
		c.CollisionGroup = CFG.DEBRIS_GROUP or "Debris"
		c.AssemblyLinearVelocity = vel
		c.AssemblyAngularVelocity = V3(random() - 0.5, random() - 0.5, random() - 0.5) * 30
		c.Parent = debrisFolder
		liveChunks += 1
		counts.chunks += 1
		task.delay(5 + random() * 3, function()
			liveChunks -= 1
			if c.Parent then
				c:Destroy()
			end
		end)
	end

	-- cut one part around a box of half-size hr centred on pos (in the part's own axes)
	local function cut(p, pos, hr, dir)
		local cf, s = p.CFrame, p.Size
		local lp = cf:PointToObjectSpace(pos)
		local h = s / 2
		-- a little irregularity so holes are not all perfect squares
		local jx, jy, jz = hr * (0.8 + random() * 0.4), hr * (0.8 + random() * 0.4), hr * (0.8 + random() * 0.4)
		local a = V3(max(lp.X - jx, -h.X), max(lp.Y - jy, -h.Y), max(lp.Z - jz, -h.Z))
		local b = V3(min(lp.X + jx, h.X), min(lp.Y + jy, h.Y), min(lp.Z + jz, h.Z))
		if a.X >= b.X or a.Y >= b.Y or a.Z >= b.Z then
			return false
		end
		local orig = pieceOf[p] or p
		local rec = recs[orig]
		if not rec then
			rec = { parent = orig.Parent, pieces = {}, cf = orig.CFrame, size = orig.Size }
			recs[orig] = rec
			table.insert(order, orig)
			counts.holes += 1
		end
		rec.lastHit = os.clock()
		local parent = rec.parent
		-- remainder slabs: below / above the cut, then front / back, then left / right
		local boxes = {}
		local function add(x0, x1, y0, y1, z0, z1)
			if x1 - x0 > 0.08 and y1 - y0 > 0.08 and z1 - z0 > 0.08 then
				table.insert(boxes, { x0, x1, y0, y1, z0, z1 })
			end
		end
		add(-h.X, h.X, -h.Y, a.Y, -h.Z, h.Z)
		add(-h.X, h.X, b.Y, h.Y, -h.Z, h.Z)
		add(-h.X, h.X, a.Y, b.Y, -h.Z, a.Z)
		add(-h.X, h.X, a.Y, b.Y, b.Z, h.Z)
		add(-h.X, a.X, a.Y, b.Y, a.Z, b.Z)
		add(b.X, h.X, a.Y, b.Y, a.Z, b.Z)
		for _, bx in ipairs(boxes) do
			local size = V3(bx[2] - bx[1], bx[4] - bx[3], bx[6] - bx[5])
			local centre = V3((bx[1] + bx[2]) / 2, (bx[3] + bx[4]) / 2, (bx[5] + bx[6]) / 2)
			local piece = Instance.new("Part")
			piece.Name = orig.Name
			piece.Size = size
			piece.CFrame = cf * CFrame.new(centre)
			copyLook(p, piece)
			piece:SetAttribute("FracPiece", true)
			piece.Parent = parent
			rec.pieces[piece] = true
			pieceOf[piece] = orig
			verdict[piece] = true
			counts.pieces += 1
		end
		-- rubble teeth on the rim (on the part's faces round the hole) - a darker, broken edge
		local dark = p.Color:Lerp(Color3.new(0.05, 0.05, 0.07), 0.45)
		local holeSize = b - a
		for _ = 1, 5 do
			local t = V3(a.X + random() * holeSize.X, a.Y + random() * holeSize.Y, a.Z + random() * holeSize.Z)
			-- push the tooth out to the rim of the hole along its widest in-plane axis
			local k = random(1, 2)
			if holeSize.X >= holeSize.Z then
				t = V3(k == 1 and a.X or b.X, t.Y, t.Z)
			else
				t = V3(t.X, t.Y, k == 1 and a.Z or b.Z)
			end
			if random() < 0.5 then
				t = V3(t.X, random() < 0.5 and a.Y or b.Y, t.Z)
			end
			local sz = 0.5 + random() * 1.1 * clamp(hr / 4, 0.6, 2.2)
			local tooth = Instance.new("Part")
			tooth.Size = V3(sz, sz * (0.6 + random() * 0.8), sz)
			tooth.CFrame = cf * CFrame.new(t) * CFrame.Angles(random() * 6.28, random() * 6.28, random() * 6.28)
			copyLook(p, tooth)
			tooth.Color = dark
			tooth.CanCollide = false
			tooth.CastShadow = false
			tooth:SetAttribute("FracPiece", false)
			verdict[tooth] = false -- rubble is never cut again (it goes when the wall is rebuilt)
			tooth.Parent = parent
			rec.pieces[tooth] = true
			counts.pieces += 1
		end
		-- debris out of the hole
		local out = (dir and dir.Magnitude > 0.01) and dir.Unit or (cf:PointToWorldSpace((a + b) / 2) - pos).Unit
		if out ~= out then
			out = V3(0, 1, 0)
		end
		local holeCentre = cf:PointToWorldSpace((a + b) / 2)
		local cs = clamp(hr * 0.35, 0.7, 3.2)
		for _ = 1, (C.CHUNKS or 5) do
			local v = (out * (25 + random() * 35) + V3((random() - 0.5) * 30, 12 + random() * 25, (random() - 0.5) * 30))
			chunk(holeCentre + V3((random() - 0.5) * hr, (random() - 0.5) * hr, (random() - 0.5) * hr),
				V3(cs * (0.5 + random()), cs * (0.5 + random()), cs * (0.5 + random())), p.Color, p.Material, v)
		end
		-- retire the cut part
		if p == orig then
			p.Parent = park
		else
			rec.pieces[p] = nil
			pieceOf[p] = nil
			p:Destroy()
			counts.pieces -= 1
		end
		counts.cuts += 1
		return true
	end

	local function rebuild(orig)
		local rec = recs[orig]
		if not rec then
			return
		end
		for piece in pairs(rec.pieces) do
			if piece.Parent then
				piece:Destroy()
			end
			counts.pieces -= 1
		end
		orig.Parent = rec.parent
		recs[orig] = nil
		local i = table.find(order, orig)
		if i then
			table.remove(order, i)
		end
		counts.rebuilt += 1
	end

	local function bodyIn(cf, size, pad)
		local h = size / 2 + V3(pad, pad, pad)
		local function inside(pos)
			local l = cf:PointToObjectSpace(pos)
			return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if r and inside(r.Position) then
				return true
			end
		end
		local npcs = workspace:FindFirstChild("NPCs")
		if npcs then
			for _, m in ipairs(npcs:GetChildren()) do
				local r = m:FindFirstChild("HumanoidRootPart")
				if r and inside(r.Position) then
					return true
				end
			end
		end
		return false
	end

	-- craters -----------------------------------------------------------------------------------------------
	local craters = {}
	-- the ground test looks at TERRAIN only: road paint, curbs and the kits' own rubble / FX parts sit right at the
	-- impact point and used to stop every street crater (upper floors are ruled out by the height check instead)
	local downParams = RaycastParams.new()
	downParams.FilterType = Enum.RaycastFilterType.Include
	downParams.FilterDescendantsInstances = { workspace.Terrain }
	local scorchMat = Enum.Material[C.SCORCH or "Basalt"] or Enum.Material.Basalt
	local function flatten(mats, occs, region)
		-- the city's street ground exactly as the Streets builder left it (read off an untouched column: in a
		-- region read from y -12, the cells are FULL up to the one whose nominal top is GROUND - 2 and AIR above -
		-- smooth terrain draws that as a surface at y = GROUND; a half-full layer on top raised the road a voxel)
		local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
		local y0 = region.CFrame.Position.Y - region.Size.Y / 2
		for x = 1, sx do
			for z = 1, sz do
				local below = Enum.Material.Asphalt
				for y = 1, sy do
					local top = y0 + y * 4
					local m = mats[x][y][z]
					if top <= GROUND - 2 then
						if m ~= Enum.Material.Air then
							below = m
						end
						mats[x][y][z] = (m ~= Enum.Material.Air) and m or below
						occs[x][y][z] = 1
					else
						mats[x][y][z] = Enum.Material.Air
						occs[x][y][z] = 0
					end
				end
			end
		end
	end
	local function crater(pos, radius, uid)
		if #craters >= (C.MAX_CRATERS or 120) then
			return
		end
		-- a big blast centred on its own caster (a titan transformation, a domain) never digs out the ground the
		-- caster stands on: it fires while the body is still person-sized, then the giant grew up inside the pit
		if uid and radius >= 16 then
			local pl = Players:GetPlayerByUserId(uid)
			local r = pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if r and (V3(r.Position.X, 0, r.Position.Z) - V3(pos.X, 0, pos.Z)).Magnitude < 10 + radius * 0.35 then
				return
			end
		end
		-- only at street level: the first thing straight below the blast must be the ground itself
		local hit = workspace:Raycast(pos + V3(0, 1, 0), V3(0, -(pos.Y - GROUND) - 18, 0), downParams)
		-- (a kit's own crater may already have been dug here this frame, so lower ground counts too)
		if not hit or hit.Instance ~= terrain or hit.Position.Y > GROUND + 1.5 or hit.Position.Y < GROUND - 14 then
			return
		end
		local R = clamp(radius * (C.CRATER_SCALE or 0.42), C.CRATER_MIN or 2.5, C.CRATER_MAX or 16)
		local x, z = hit.Position.X, hit.Position.Z
		-- never dig under a giant form's feet: a titan's transformation blast is centred on itself, and the pit left
		-- it standing 10-20 studs below the street (the kits' own crater rings go round it, not under it)
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if r and (ch:GetAttribute("TitanForm") or ch:GetAttribute("Morphed") or ch:GetAttribute("Guardian") or ch:GetScale() > 1.5) then
				local foot = 3 * ch:GetScale()
				if (V3(r.Position.X, 0, r.Position.Z) - V3(x, 0, z)).Magnitude < R + foot then
					return
				end
			end
		end
		local span = math.ceil((R * 1.5 + 2) / 4) * 4
		local x0, z0 = math.floor((x - span) / 4) * 4, math.floor((z - span) / 4) * 4
		local x1, z1 = math.ceil((x + span) / 4) * 4, math.ceil((z + span) / 4) * 4
		local region = Region3.new(V3(x0, GROUND - 14, z0), V3(x1, GROUND + 6, z1)):ExpandToGrid(4)
		local ok, mats, occs = pcall(function()
			return terrain:ReadVoxels(region, 4)
		end)
		if not ok then
			return
		end
		flatten(mats, occs, region)
		local surfaceColor = Color3.fromRGB(42, 42, 50)
		-- scorch ring, then the bowl
		terrain:FillCylinder(CFrame.new(x, GROUND - 1, z), 2, R * 1.45, scorchMat)
		local bc, br = airBall(V3(x, GROUND + R * 0.35, z), R)
		if bc and radius >= (C.HOT_RADIUS or 18) then
			-- a molten core lining the bottom of the (depth-capped) bowl (big hits only)
			local floorY = bc.Y - br
			terrain:FillBall(V3(x, floorY - R * 0.45, z), R * 0.55, Enum.Material[C.HOT or "CrackedLava"] or Enum.Material.CrackedLava)
			airBall(V3(x, GROUND + R * 0.35, z), R * 0.92)
		end
		for i = 1, clamp(math.floor(R / 2) + 3, 3, 9) do
			local a = random() * 6.28
			local outv = V3(math.cos(a), 0, math.sin(a))
			local s = clamp(R * 0.22, 0.6, 2.6) * (0.6 + random() * 0.8)
			chunk(V3(x, GROUND + 0.5, z) + outv * R * 0.5, V3(s, s * 0.6, s), surfaceColor, Enum.Material.Asphalt,
				outv * (15 + random() * 25) + V3(0, 30 + random() * 35, 0))
		end
		table.insert(craters, { region = region, mats = mats, occs = occs, x = x, z = z, R = R, at = os.clock() })
		counts.craters += 1
	end

	-- the queue ------------------------------------------------------------------------------------------------
	local queue, recentCrash = {}, {}
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { city }

	S.onImpact = function(pos, radius, dir, kind, mult, uid)
		if radius < (C.MIN_RADIUS or 6) then
			return
		end
		if kind == "crash" then
			local t = os.clock()
			for i = #recentCrash, 1, -1 do
				local r = recentCrash[i]
				if t - r.t > 0.25 then
					table.remove(recentCrash, i)
				elseif (r.pos - pos).Magnitude < (C.CRASH_SPACING or 6) then
					return
				end
			end
			table.insert(recentCrash, { pos = pos, t = t })
		end
		if #queue < 120 then
			table.insert(queue, { pos = pos, radius = radius, dir = dir, kind = kind, uid = uid })
		end
	end

	local pendingCuts = {}
	local lastScan = 0
	RunService.Heartbeat:Connect(function()
		-- 1) turn queued impacts into part cuts (+ a crater)
		local craterBudget = C.CRATERS_PER_STEP or 2
		for _ = 1, 3 do
			local im = table.remove(queue, 1)
			if not im then
				break
			end
			local hr = clamp(im.radius * (C.HOLE_SCALE or 0.55), C.HOLE_MIN or 2.2, C.HOLE_MAX or 22)
			-- big blasts reach further than the hole size: search out to 0.8 x the blast (<= 50 studs)
			local parts = workspace:GetPartBoundsInRadius(im.pos, clamp(im.radius * 0.8, hr * 1.2, 50), overlap)
			local list = {}
			for _, p in ipairs(parts) do
				if structural(p) then
					table.insert(list, p)
				end
			end
			table.sort(list, function(a, b)
				return (a.Position - im.pos).Magnitude < (b.Position - im.pos).Magnitude
			end)
			for i = 1, min(#list, (C.PARTS_PER_IMPACT or 10) + math.floor(im.radius / 4)) do
				table.insert(pendingCuts, { p = list[i], pos = im.pos, hr = hr, dir = im.dir })
			end
			if cratersOn and im.kind ~= "crash" and craterBudget > 0 and im.pos.Y - GROUND < im.radius * 0.7 then
				craterBudget -= 1
				local ok, e = pcall(crater, im.pos, im.radius, im.uid)
				if not ok then
					warn("[CityDestruction.Structure] crater failed: " .. tostring(e))
				end
			end
		end
		-- 2) cut (budgeted)
		local n = 0
		while #pendingCuts > 0 and n < (C.CUTS_PER_STEP or 24) do
			local c = table.remove(pendingCuts, 1)
			if c.p.Parent and (c.p.Parent ~= park) and counts.pieces < (C.MAX_PIECES or 3500) then
				local ok, e = pcall(cut, c.p, c.pos, c.hr, c.dir)
				if not ok then
					warn("[CityDestruction.Structure] cut failed: " .. tostring(e))
				end
				n += 1
			end
		end
		-- 3) every 2 s: rebuild walls and repave craters whose time is up (and that nobody is standing in)
		local t = os.clock()
		if t - lastScan < 2 then
			return
		end
		lastScan = t
		local over = counts.pieces > (C.MAX_PIECES or 3500) * 0.9
		for i = #order, 1, -1 do
			local orig = order[i]
			local rec = recs[orig]
			if rec and (t - rec.lastHit > (C.REGEN or 60) or (over and i == 1)) and not bodyIn(rec.cf, rec.size, 3) then
				rebuild(orig)
			end
		end
		for i = #craters, 1, -1 do
			local c = craters[i]
			if t - c.at > (C.CRATER_HEAL or 50) then
				local blocked = false
				for _, pl in ipairs(Players:GetPlayers()) do
					local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
					if r and (V3(r.Position.X, 0, r.Position.Z) - V3(c.x, 0, c.z)).Magnitude < c.R + 4 and r.Position.Y < GROUND + 8 then
						blocked = true
					end
				end
				if not blocked then
					local wrote = pcall(function()
						terrain:WriteVoxels(c.region, 4, c.mats, c.occs)
					end)
					-- (2026-11-07 ground fix) the repave fills the bowl - and any other kit's dish inside the square - up to
					-- the street: lift whoever lies in it (NPCs, ragdolls, players in another dish) back on top, or they
					-- are inside solid ground and drop through the map. A failed write keeps the record (retried in 2 s).
					if wrote then
						pcall(GroundGuard.liftOut, c.region)
						table.remove(craters, i)
						counts.heals += 1
					end
				end
			end
		end
	end)

	return {
		stats = function()
			return counts, #craters, #order
		end,
		rebuildAll = function()
			for i = #order, 1, -1 do
				rebuild(order[i])
			end
			for i = #craters, 1, -1 do
				pcall(function()
					terrain:WriteVoxels(craters[i].region, 4, craters[i].mats, craters[i].occs)
				end)
				pcall(GroundGuard.liftOut, craters[i].region)
				table.remove(craters, i)
			end
		end,
	}
end

return Structure
