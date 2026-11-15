--!nocheck
-- GroundFX: terrain craters that heal themselves, and debris rocks torn out of the ground.
-- Before carving, a crater snapshots the voxels of every 32-stud chunk it touches. When the last crater in a chunk
-- expires, only cells that are now emptier than the snapshot are filled back in, so it never re-adds or undoes
-- terrain damage made by other systems (the Limitless kit keeps its own restore cache).
-- (2026-11-07 ground pass) Shared by Vulpine, Deku, Ichigo, Luffy, the Titans, Tempest, Carver and Ascendant: every crater
-- ball goes through ReplicatedStorage.CityShared.GroundGuard.clampBall first, so no crater is ever deeper than
-- DestructionConfig.GROUND.MAX_DEPTH below the street (it used to dig down to y -44: pits nobody could climb out of).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local GroundFX = {}

local Terrain = workspace.Terrain
local CHUNK, RES = 32, 4
local FLOOR_Y = -44        -- never dig through the bottom of the map (fallback when GroundGuard is missing)
local GroundGuard
do
	local ok, res = pcall(function()
		return require(game:GetService("ReplicatedStorage"):WaitForChild("CityShared", 10):WaitForChild("GroundGuard", 10))
	end)
	GroundGuard = ok and res or nil
	if not ok then
		warn("[GroundFX] GroundGuard unavailable, craters are not depth-capped: " .. tostring(res))
	end
end
local RESTORE_AFTER = 45   -- seconds a crater stays open (2026-11-07: was 9; ability damage to the ground stays noticeable)
local ROCK_CAP = 120
local ROCK_LIFE = 6
local NPC_TAG = "RagdollNPC"

local folder = workspace:FindFirstChild("KitDebris") or Instance.new("Folder")
folder.Name = "KitDebris"
folder.Parent = workspace
GroundFX.folder = folder -- not ignored by the vortex/blast pushes, so rocks get sucked in and blown out too

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Terrain }
terrainOnly.IgnoreWater = true

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local MAT_SWAP = {
	[Enum.Material.Grass] = Enum.Material.Ground,
	[Enum.Material.LeafyGrass] = Enum.Material.Ground,
	[Enum.Material.Water] = Enum.Material.Slate,
	[Enum.Material.Air] = Enum.Material.Ground,
}

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

---------------------------------------------------------------------------------------------------
-- craters
local chunks = {} -- key -> { region, mats, occs, refs }
local queue = {}

local function holdChunk(cx, cy, cz, held)
	local key = cx .. "," .. cy .. "," .. cz
	if held[key] then
		return
	end
	local c = chunks[key]
	if not c then
		local min = Vector3.new(cx, cy, cz) * CHUNK
		local region = Region3.new(min, min + Vector3.one * CHUNK)
		local ok, mats, occs = pcall(function()
			return Terrain:ReadVoxels(region, RES)
		end)
		if not ok then
			return
		end
		c = { region = region, mats = mats, occs = occs, refs = 0 }
		chunks[key] = c
	end
	c.refs += 1
	held[key] = true
end

-- carves a ball of air at `center`; it heals itself after RESTORE_AFTER seconds
function GroundFX.crater(center, radius)
	if GroundGuard then
		center, radius = GroundGuard.clampBall(center, radius)
		if not center then
			return false
		end
	elseif center.Y - radius < FLOOR_Y then
		radius = center.Y - FLOOR_Y
	end
	if radius < 1.5 then
		return false
	end
	local held = {}
	local lo, hi = center - Vector3.one * radius, center + Vector3.one * radius
	for cx = math.floor(lo.X / CHUNK), math.floor(hi.X / CHUNK) do
		for cy = math.floor(lo.Y / CHUNK), math.floor(hi.Y / CHUNK) do
			for cz = math.floor(lo.Z / CHUNK), math.floor(hi.Z / CHUNK) do
				holdChunk(cx, cy, cz, held)
			end
		end
	end
	Terrain:FillBall(center, radius, Enum.Material.Air)
	task.delay(RESTORE_AFTER, function()
		for key in pairs(held) do
			local c = chunks[key]
			if c then
				c.refs -= 1
				if c.refs <= 0 then
					table.insert(queue, key)
				end
			end
		end
	end)
	return true
end

-- after a chunk refills, anyone standing in the hole is lifted back on top instead of being buried
local function liftBodies(region)
	local cpos, half = region.CFrame.Position, region.Size / 2
	local bodies = CollectionService:GetTagged(NPC_TAG)
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(bodies, pl.Character)
		end
	end
	for _, m in ipairs(bodies) do
		local torso = m:FindFirstChild("LowerTorso") or m:FindFirstChild("HumanoidRootPart")
		if torso and m.Parent then
			local d = torso.Position - cpos
			if math.abs(d.X) <= half.X + 2 and math.abs(d.Z) <= half.Z + 2 and math.abs(d.Y) <= half.Y + 6 then
				local top = workspace:Raycast(Vector3.new(torso.Position.X, cpos.Y + half.Y + 150, torso.Position.Z), Vector3.new(0, -400, 0), terrainOnly)
				if top and torso.Position.Y < top.Position.Y + 0.5 then
					m:PivotTo(m:GetPivot() + Vector3.new(0, top.Position.Y + 3 - torso.Position.Y, 0))
				end
			end
		end
	end
end

local function restoreChunk(c)
	local ok, mats, occs = pcall(function()
		return Terrain:ReadVoxels(c.region, RES)
	end)
	if not ok then
		return
	end
	local changed = false
	for x = 1, #occs do
		local ox, sx, mx, nx = occs[x], c.occs[x], mats[x], c.mats[x]
		for y = 1, #ox do
			local oy, sy, my, ny = ox[y], sx[y], mx[y], nx[y]
			for z = 1, #oy do
				if sy[z] > oy[z] + 0.01 then
					oy[z] = sy[z]
					my[z] = ny[z]
					changed = true
				end
			end
		end
	end
	if changed then
		pcall(function()
			Terrain:WriteVoxels(c.region, RES, mats, occs)
		end)
		liftBodies(c.region)
	end
end

RunService.Heartbeat:Connect(function()
	local n = 0
	while #queue > 0 and n < 3 do
		local key = table.remove(queue, 1)
		local c = chunks[key]
		if c and c.refs <= 0 then
			chunks[key] = nil
			restoreChunk(c)
			n += 1
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- rocks
local rocks = {}

-- the ground under `pos`: (hitResult, material, colour) - terrain or a part, ignoring bodies and effects
local function groundUnder(pos, reach)
	local ignore = { folder }
	for _, n in ipairs({ "KitFX", "FX" }) do
		if workspace:FindFirstChild(n) then
			table.insert(ignore, workspace[n])
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
		table.insert(ignore, m)
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.yAxis * 3, Vector3.new(0, -(reach or 15) - 3, 0), groundParams)
	if not hit then
		return nil
	end
	if hit.Instance == Terrain then
		local mat = MAT_SWAP[hit.Material] or hit.Material
		local ok, color = pcall(function()
			return Terrain:GetMaterialColor(mat)
		end)
		if not ok then
			return hit, Enum.Material.Ground, Color3.fromRGB(102, 82, 60)
		end
		return hit, mat, color
	end
	return hit, hit.Instance.Material, hit.Instance.Color
end

function GroundFX.rock(pos, vel, size, mat, color)
	if #rocks >= ROCK_CAP then
		local old = table.remove(rocks, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	local p = Instance.new("Part")
	p.Name = "Rock"
	p.Size = size
	p.Material = mat
	p.Color = color
	p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	pcall(function()
		p.CollisionGroup = "Debris"
	end)
	p.Parent = folder
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	p.AssemblyLinearVelocity = vel
	p.AssemblyAngularVelocity = randomUnit() * (6 + math.random() * 10)
	table.insert(rocks, p)
	task.delay(ROCK_LIFE + math.random(), function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			task.wait(0.65)
			if p.Parent then
				p:Destroy()
			end
		end
		local i = table.find(rocks, p)
		if i then
			table.remove(rocks, i)
		end
	end)
	return p
end

-- a crater under `pos` (terrain only) with rocks flung out of its rim; parts floors just throw rocks
function GroundFX.impact(pos, radius, rockCount, rockSpeed)
	local hit, mat, color = groundUnder(pos, radius + 12)
	if not hit then
		return
	end
	local g = hit.Position
	if hit.Instance == Terrain then
		-- terrain is 4-stud voxels: a ball centred on the surface barely dents it, so sink the centre and grow it
		-- to get a bowl roughly `radius` wide and two-thirds as deep
		GroundFX.crater(g - Vector3.yAxis * radius * 0.35, radius * 1.2)
	end
	for i = 1, rockCount do
		local a = (i / rockCount) * math.pi * 2 + math.random() * 0.6
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local s = 0.7 + math.random() * (0.6 + radius * 0.12)
		GroundFX.rock(
			g + out * radius * (0.6 + math.random() * 0.4) + Vector3.yAxis * 1.5,
			out * rockSpeed * (0.5 + math.random() * 0.6) + Vector3.yAxis * rockSpeed * (0.7 + math.random() * 0.6),
			Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.5)),
			mat, color
		)
	end
end

-- pebbles torn up around a ring (power-ups, the vortex rim): they hop mostly straight up
function GroundFX.ring(center, radius, count, upSpeed)
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local at = center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * (0.5 + math.random() * 0.5)
		local hit, mat, color = groundUnder(at, 12)
		if hit then
			local s = 0.5 + math.random() * 0.9
			GroundFX.rock(hit.Position + Vector3.yAxis * 0.8, Vector3.yAxis * upSpeed * (0.6 + math.random() * 0.6) + randomUnit() * 4,
				Vector3.new(s, s * 0.7, s * 0.9), mat, color)
		end
	end
end

return GroundFX
