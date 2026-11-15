--!nocheck
-- ServerStorage.SandboxGen.Build: generates workspace.Map. Run in EDIT from a FRESH CLONE of this folder (the plugin
-- require cache keeps old sources): tmp = Gen:Clone(); tmp.Parent = ServerStorage; require(tmp.Build).all(); then save.
-- (2026-11-13) OPEN TEST GROUND - the hub with eight identical pads on a ring was "too structured". Sites now sit
-- wherever this table puts them, at any angle, straight on the grass, and World scatters loose things between them.
--   x east / z south; the spawn deck is at 0,0 looking north (-z). yaw = compass bearing the site's FRONT (-Z) faces.
--   r = keep-out radius for trails and scenery; ahead / behind stretch it into a capsule along the site's own Z.
--   ground = terrain painted under it (an irregular blob). legacy = one of the first eight builders, which expect a
--   pad top at y 0.4, so their cf is sunk by that much.
-- Area builders are the sibling modules Area_<name>:  return function(K, model, cf, S)
local Gen = script.Parent
local K = require(Gen.MapKit)
local C = K.C
local M = Enum.Material
-- (2026-11-14) PACKED IN. The owner: "move everything in to be closer to each other, things are too far away", then
-- "bring everything at the top and the left sides of the map even closer in". Every site kept its angle and was
-- pulled in until the lanes between the sites are about 10 studs wide (a packing search over the measured
-- footprints, the north and west weighted hardest; each move a multiple of 4 studs, so a site's terrain cuts land
-- on the voxel grid exactly as they did). Furthest reach: west 341 -> 233, north 319 -> 263. That is close to the
-- limit - the footprints themselves fill most of the field. New per-site fields:
--   box   = the footprint of everything the site's builder makes, in the site's own frame { x0, x1, z0, z1 }.
--           World keeps trails, scenery and ground paint off it (it used the circle r, which now overlaps everything).
--   also  = more keep-out rectangles in the same frame (terrain the builder makes: the lake, the pit, the berms).
--   signX / signZ = where the name board stands (at the front edge of the box; it stood r + 3 out in the grass).
--   patch = radius of the painted blob (so it stays under its own site).
-- SITES.field is the walled field (it was +-352 square), SITES.trails the footpaths: a shortest-path search from the
-- deck down the lanes to the front of every site (w / mat = a paved one).
local SITES = {
	{ name = "Slide", title = "MEGA SLIDE", x = 32, z = -206, yaw = 165, r = 60, half = 56, ground = M.Pavement, legacy = true, accent = C(245, 196, 40), box = { -50, 34, -45, 46 }, signX = 27.3, signZ = -47.5, patch = 40 },
	{ name = "Ring", title = "BOXING RING", x = 132, z = -50, yaw = 250, r = 60, ground = M.Grass, legacy = true, accent = C(196, 44, 40), box = { -45, 45, -36, 25 }, signX = 33.9, signZ = -38.1, patch = 29 },
	{ name = "Rocket", title = "ROCKET PAD", x = 100, z = 48, yaw = 285, r = 40, ground = M.Asphalt, legacy = true, accent = C(236, 118, 32), box = { -31, 31, -29, 37 }, signX = 23.9, signZ = -30.8, patch = 29 },
	{ name = "Trampoline", title = "BOUNCE PARK", x = 72, z = 138, yaw = 335, r = 52, ground = M.Grass, legacy = true, accent = C(44, 96, 190), box = { -39, 40, -31, 34 }, signX = 30, signZ = -32.7, patch = 31 },
	{ name = "SpikePit", title = "SPIKE PIT", x = -8, z = 96, yaw = 30, r = 40, ground = M.Rock, legacy = true, accent = C(150, 40, 46), box = { -28, 28, -27, 34 }, signX = 21.5, signZ = -29.5, patch = 27 },
	{ name = "GasYard", title = "GAS YARD", x = 182, z = 136, yaw = 350, r = 58, ground = M.Ground, legacy = true, accent = C(232, 60, 40), box = { -42, 42, -42, 42 }, signX = 33, signZ = -43.8, patch = 40 },
	{ name = "Disaster", title = "DISASTER BOX", x = 130, z = 227, yaw = 300, r = 56, half = 50, ground = M.Concrete, legacy = true, accent = C(120, 80, 200), box = { -32, 32, -45, 36 }, signX = 25.5, signZ = -46.8, patch = 30 },
	{ name = "Factory", title = "THE WORKSHOP", x = 26, z = 279, yaw = 10, r = 56, half = 52, ground = M.Concrete, legacy = true, accent = C(245, 196, 40), box = { -46, 46, -39, 21 }, signX = 32, signZ = -41, patch = 28 },
	{ name = "Lab", title = "MUTATION LAB", x = -90, z = -34, yaw = 120, r = 52, ground = M.Concrete, accent = C(60, 220, 170), noSign = true, box = { -48, 48, -18, 33 }, patch = 24 },
	{ name = "Shark", title = "SHARK BAIT", x = 178, z = -151, yaw = 225, r = 50, accent = C(40, 130, 190), box = { -27, 54, -49, 33 }, signX = 28.9, signZ = -51.1, also = { { -43, 43, -43, 43 } } },
	{ name = "Fan", title = "THE BIG FAN", x = -92, z = -126, yaw = 0, r = 30, ahead = 96, behind = 10, accent = C(120, 200, 230), box = { -25, 25, -125, 25 }, signX = 28, signZ = -6 },
	{ name = "Press", title = "THE CRUSHER", x = 74, z = -124, yaw = 200, r = 30, ground = M.Concrete, accent = C(245, 196, 40), box = { -24, 24, -19, 18 }, signX = 32.8, signZ = -19.7, patch = 18 },
	{ name = "Grinder", title = "THE GRINDER", x = 48, z = -76, yaw = 170, r = 26, accent = C(196, 44, 40), box = { -19, 13, -22, 13 }, signX = 6.5, signZ = -24.1 },
	{ name = "Propeller", title = "THE BLENDER", x = 244, z = 42, yaw = 215, r = 31, accent = C(236, 118, 32), box = { -25, 25, -32, 25 }, signX = 17.7, signZ = -34.1 },
	{ name = "Cannon", title = "HUMAN CANNON", x = -66, z = 80, yaw = 300, r = 18, ahead = 112, behind = 4, accent = C(196, 44, 40), box = { -19, 20, -101, 18 }, signX = 16, signZ = -6 },
	{ name = "Wrecker", title = "WRECKING BALL", x = 178, z = 50, yaw = 280, r = 22, ahead = 34, behind = 34, accent = C(245, 196, 40), box = { -25, 26, -27, 15 }, signX = 20, signZ = -6 },
	{ name = "Train", title = "THE EXPRESS", x = -184, z = -4, yaw = 5, r = 26, ahead = 215, behind = 215, accent = C(196, 44, 40), box = { -15, 15, -212, 212 }, signX = 24, signZ = -6, also = { { -29, 29, 104, 232 }, { -29, 29, -232, -104 } } },
	{ name = "Rex", title = "REX PADDOCK", x = -108, z = 150, yaw = 45, r = 56, ground = M.Ground, accent = C(96, 150, 70), box = { -41, 45, -41, 31 }, signX = 32.1, signZ = -42.6, patch = 34 },
	{ name = "Bear", title = "BEAR PIT", x = -70, z = 234, yaw = 57, r = 36, accent = C(150, 104, 60), box = { -24, 24, -32, 24 }, signX = 17.5, signZ = -34.1, also = { { -28, 28, -28, 28 } } },
	{ name = "Tower", title = "LEAP TOWER", x = -33, z = -167, yaw = 135, r = 28, ground = M.Cobblestone, accent = C(200, 190, 160), box = { -10, 10, -28, 9 }, signX = 3.5, signZ = -30.5, patch = 10 },
	{ name = "Mines", title = "MINEFIELD", x = -6, z = 180, yaw = 0, r = 30, ground = M.Ground, accent = C(232, 60, 40), box = { -25, 28, -28, 25 }, signX = 19, signZ = -29.7, patch = 25 },
	{ name = "Tesla", title = "TESLA COIL", x = 212, z = -36, yaw = 270, r = 24, ground = M.Slate, accent = C(140, 170, 255), box = { -14, 13, -20, 16 }, signX = 6.5, signZ = -22.1, patch = 13 },
}
-- (2026-11-13) NO TREES INSIDE THIS CIRCLE - the owner asked for the smallest circle that takes in every activity to be
-- cleared of trees, and everything outside it left as it was. Measured from the built map (every corner of every part
-- of every site model, Badoiu-Clarkson): if a site is added or moved outside it, measure again.
SITES.treeFree = { x = -18.8, z = 14.3, r = 308.1 } -- (2026-11-14) measured again from the packed layout
SITES.field = { x0 = -264, x1 = 308, z0 = -296, z1 = 340 }
SITES.trails = {
	{ { 53, -35 }, { 53, -47 } }, -- Grinder
	{ { -51, -23 }, { -71, -23 } }, -- Lab
	{ { 9, 43 }, { 9, 65 } }, -- SpikePit
	{ { -51, 43 }, { -55, 49 } }, -- Cannon
	{ { 59, 39 }, { 65, 39 } }, -- Rocket
	{ { 59, -35 }, { 91, -35 } }, -- Ring
	{ { 23, -97 }, { 63, -97 }, { 65, -99 }, w = 8, mat = M.Pavement }, -- Press
	{ { 55, 43 }, { 55, 103 } }, -- Trampoline
	{ { -23, -125 }, { -45, -125 }, { -51, -131 }, { -55, -131 }, w = 8, mat = M.Pavement }, -- Fan
	{ { -7, -125 }, { -7, -141 }, w = 8, mat = M.Pavement }, -- Tower
	{ { 55, 103 }, { 39, 103 }, { 27, 115 }, { 23, 115 }, { 17, 121 }, { 17, 129 }, { 5, 141 }, { -5, 145 } }, -- Mines
	{ { -51, 23 }, { -101, 23 }, { -105, 19 }, { -113, 17 }, { -119, 11 }, { -123, 11 }, { -129, 5 }, { -137, 3 }, { -141, -1 }, { -155, -1 }, { -165, -9 } }, -- Train (the crossing)
	{ { -5, 145 }, { -15, 143 }, { -29, 129 }, { -59, 129 }, { -73, 115 } }, -- Rex
	{ { 59, 3 }, { 87, 3 }, { 91, 7 }, { 103, 7 }, { 107, 11 }, { 153, 9 }, { 155, 7 }, { 175, 7 }, { 179, 11 } }, -- Wrecker
	{ { 23, -125 }, { 27, -129 }, { 29, -137 }, { 45, -155 }, w = 8, mat = M.Pavement }, -- Slide
	{ { 175, 7 }, { 175, -11 }, { 181, -21 }, { 181, -31 }, { 185, -35 } }, -- Tesla
	{ { 149, 9 }, { 149, 33 }, { 141, 73 }, { 151, 77 }, { 159, 77 }, { 173, 87 } }, -- GasYard
	{ { 65, -99 }, { 73, -93 }, { 91, -89 }, { 125, -101 }, { 137, -111 } }, -- Shark
	{ { -35, 129 }, { -35, 211 }, { -37, 213 } }, -- Bear
	{ { 173, 87 }, { 183, 83 }, { 193, 83 }, { 201, 79 }, { 215, 79 }, { 221, 75 } }, -- Propeller
	{ { 13, 133 }, { 27, 147 }, { 29, 171 }, { 49, 191 }, { 73, 191 }, { 85, 201 } }, -- Disaster
	{ { 49, 191 }, { 49, 207 }, { 37, 219 }, { 35, 233 } }, -- Factory
}
local Build = { SITES = SITES }
local function areaBuild(S)
	local m = Gen:FindFirstChild("Area_" .. S.name)
	if not m then
		return false
	end
	require(m)(K, S.model, S.cf, S)
	return true
end
function Build.all()
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	for _, n in ipairs({ "Baseplate", "SpawnLocation" }) do
		local b = workspace:FindFirstChild(n)
		if b then
			b:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	require(Gen.World)(K, map, SITES)
	local built, failed = {}, {}
	for _, S in ipairs(SITES) do
		local ok, res = pcall(areaBuild, S)
		if ok and res then
			table.insert(built, S.name)
		elseif not ok then
			table.insert(failed, S.name .. ": " .. tostring(res))
		else
			table.insert(failed, S.name .. ": no builder")
		end
		task.wait()
	end
	return "built: " .. table.concat(built, ", ") .. (#failed > 0 and (" | FAILED " .. table.concat(failed, " ; ")) or "") .. " | instances " .. #map:GetDescendants()
end
-- (2026-11-13) rebuild ONE site where it stands: require(tmp.Build).site("Grinder"). The rest of the map, the ground
-- paint and the scatter are World's and are not touched; the signpost World stood in the site is kept.
function Build.site(name)
	local map = workspace:FindFirstChild("Map")
	for _, S in ipairs(SITES) do
		if S.name == name then
			local model = map and map:FindFirstChild(name)
			if not model then
				return "no model for " .. name
			end
			local keep = {}
			local posts = {}
			for _, c in ipairs(model:GetChildren()) do
				if c.Name == "SignPost" then
					keep[c] = true
					table.insert(posts, c)
				end
			end
			if #posts >= 2 then -- World's own sign is the Sign / SignTrim hanging between its two posts
				local mid = (posts[1].Position + posts[2].Position) / 2
				for _, c in ipairs(model:GetChildren()) do
					if (c.Name == "Sign" or c.Name == "SignTrim") and ((c.Position - mid) * Vector3.new(1, 0, 1)).Magnitude < 2 then
						keep[c] = true
					end
				end
			end
			for _, c in ipairs(model:GetChildren()) do
				if not keep[c] then
					c:Destroy()
				end
			end
			S.cf0 = CFrame.new(S.x, 0, S.z) * CFrame.Angles(0, -math.rad(S.yaw or 0), 0)
			S.cf = S.legacy and S.cf0 * CFrame.new(0, -0.4, 0) or S.cf0
			S.model = model
			areaBuild(S)
			return "rebuilt " .. name .. " (" .. #model:GetDescendants() .. " instances)"
		end
	end
	return "unknown site " .. tostring(name)
end

return Build
