--!nocheck
-- PerkMapEvents.IceWorld (2026-11-15): the buyer's map freezes over for 60 s (+60 s each time it is bought again
-- while it runs, up to 180 ahead). The ground (and ONLY the ground: terrain, workspace.Map.Baseplate, the spawn plaza,
-- the Ruins' Floor - never a machine, so the trampoline, the press and the trapdoors keep working) gets a sheet of real
-- ice: TILE-stud tiles laid where a ray down meets it, frictionless (FrictionWeight 100 wins over whatever touches it),
-- so a body or a prop that is pushed slides on and on. Standing dummies slip and fall now and then. Players slide on
-- their own client (PerkMapEventsClient.IceWorld: it keys on standing on Material.Ice). Tiles fade in and out.
local TILE = 24
local ICE = Color3.fromRGB(196, 232, 255)

return function(ctx, ev)
	local A = ev.area
	local rng = ctx.rng
	local include = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	local plates = map and map:FindFirstChild("Baseplate")
	if plates then
		table.insert(include, plates)
	end
	-- (playtest 2026-11-15) the spawn plaza too: everyone stands there first, and it was the one dry patch
	local plaza = map and map:FindFirstChild("Spawn")
	if plaza then
		table.insert(include, plaza)
	end
	local ruins = workspace:FindFirstChild("Arenas") and workspace.Arenas:FindFirstChild("Ruins")
	local floor = ruins and ruins:FindFirstChild("Floor")
	if floor then
		table.insert(include, floor)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = false
	local sheet = Instance.new("Folder")
	sheet.Name = "IceSheet_" .. ev.id
	local phys = PhysicalProperties.new(0.92, 0, 0.05, 100, 1)
	local tiles = {}
	local nx, nz = math.ceil(A.h.X * 2 / TILE), math.ceil(A.h.Z * 2 / TILE)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = A.c.X - A.h.X + (ix + 0.5) * TILE
			local z = A.c.Z - A.h.Z + (iz + 0.5) * TILE
			local hit = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -420, 0), params)
			if hit and hit.Normal.Y > 0.9 then
				local water = hit.Material == Enum.Material.Water
				local t = Instance.new("Part")
				t.Name = "Ice"
				t.Anchored, t.CanCollide, t.CanTouch, t.CastShadow = true, true, false, false
				t.Material = Enum.Material.Ice
				t.Color = ICE
				t.Reflectance = 0.12
				t.Transparency = 1
				t.Size = Vector3.new(TILE + 0.1, water and 1 or 0.25, TILE + 0.1)
				t.CFrame = CFrame.new(x, hit.Position.Y + t.Size.Y / 2 - (water and 0.3 or 0.08), z)
				t.CustomPhysicalProperties = phys
				t.TopSurface, t.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				t.Parent = sheet
				table.insert(tiles, t)
			end
		end
	end
	sheet.Parent = ctx.folder
	ev.marker:SetAttribute("Tiles", #tiles)
	ev.cleanup = function()
		sheet:Destroy()
	end
	local function fade(a, b, secs)
		for i = 1, 5 do
			local tr = a + (b - a) * i / 5
			for _, t in ipairs(tiles) do
				t.Transparency = tr
			end
			task.wait(secs / 5)
		end
	end
	fade(1, 0.3, 2)
	local nextSlip = 0
	while not ev.stop and ctx.now() < ev.ends do
		task.wait(0.25)
		local now = os.clock()
		if now >= nextSlip then
			nextSlip = now + 1
			for _, m in ipairs(ctx.dummies(A, 0)) do
				if not ctx.isRagdolled(m) and not m:GetAttribute("Boss") and rng:NextNumber() < 0.07 then
					local a = rng:NextNumber() * math.pi * 2
					ctx.blame(m, ev.by)
					ctx.fling(m, Vector3.new(math.cos(a), 0.25, math.sin(a)) * rng:NextNumber(14, 26), 2.2)
				end
			end
		end
		ev.info = { tiles = #tiles }
	end
	fade(0.3, 1, 1.5)
end
