--!nocheck
-- ReplicatedStorage.CityShared.GroundGuard (2026-11-07, owner: destruction). Numbers: DestructionConfig.GROUND / .FALL_GUARD.
-- Shared by the server and the clients. Pure helpers, no state, no connections.
--  clampBall(center, r) -> center', r  | nil
--    EVERY ability terrain carve (FillBall Air) must pass through this first: CityDestruction.Structure (craters),
--    VulpineServer.GroundFX.crater (most kits), GojoServer.CombatService.carve (Hollow Purple / Red). A ball that would
--    reach below FLOOR_Y (= SURFACE_Y - MAX_DEPTH) is lifted until its bottom rests on FLOOR_Y (same radius, so the
--    crater keeps a sensible width but is a shallow dish); a ball that never reaches the surface carves nothing (nil).
--  probe(pos) -> "below" | "buried" | nil      is a torso at pos under the map?
--  findSpot(pos, ignore, group, standH, halfW) -> ground point (Vector3) | nil
--    open street-level ground near pos: straight above first, then rings every SEARCH_STEP out to SEARCH_MAX.
--  rescue(model, lastSafe) -> true when moved   (PivotTo + every part's velocity zeroed; the caller must own the body:
--    a player's client for its own character, the server for NPCs / as a backstop)
--  liftOut(region, pad) -> n lifted   (2026-11-07 ground fix, SERVER) call right after ANY WriteVoxels that refills ground
--    (CityDestruction.Structure crater heal, GojoServer.CombatService chunk restore). Every player / NPC whose torso the
--    refill closed over (inside the region's XZ square + pad, UNDER the terrain surface there by 0.25..LIFT_DEPTH) is put
--    back on top, the whole model by its pivot. Terrain only collides at its surface: a body left inside a refilled dish
--    drops through the whole 60-stud ground (reproduced in Play: a dummy lying in a healing crater fell to y -10).
local CFG = require(script.Parent:WaitForChild("DestructionConfig"))
local G = CFG.GROUND or {}
local F = CFG.FALL_GUARD or {}

local GroundGuard = {}
GroundGuard.SURFACE_Y = G.SURFACE_Y or 2
GroundGuard.FLOOR_Y = GroundGuard.SURFACE_Y - (G.MAX_DEPTH or 4)
GroundGuard.SAFE_Y = F.SAFE_Y or -10
GroundGuard.CFG = F

local V3 = Vector3.new

function GroundGuard.clampBall(center, r)
	if typeof(center) ~= "Vector3" or type(r) ~= "number" or r ~= r or r <= 0 then
		return nil
	end
	local floor = GroundGuard.FLOOR_Y
	if center.Y - r >= floor then
		return center, r
	end
	if center.Y + r < GroundGuard.SURFACE_Y - 1 then
		return nil -- wholly underground: it would only hollow out the inside of the ground
	end
	return V3(center.X, floor + r, center.Z), r
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

function GroundGuard.probe(pos)
	if pos.Y ~= pos.Y then
		return nil
	end
	if pos.Y < GroundGuard.SAFE_Y then
		return "below"
	end
	local depth = F.BURIED or 3.5
	if pos.Y < GroundGuard.SURFACE_Y - depth then
		local top = GroundGuard.SURFACE_Y + 30
		local hit = workspace:Raycast(V3(pos.X, top, pos.Z), V3(0, pos.Y - top, 0), terrainOnly)
		if hit and hit.Position.Y - pos.Y > depth then
			return "buried"
		end
	end
	return nil
end

-- folders of effects / debris that never count as ground or as something in the way
local FX_FOLDERS = { "FX", "KitFX", "KitDebris", "CityDebris" }
local function ignoreList(extra)
	local list = {}
	for _, n in ipairs(FX_FOLDERS) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, x in ipairs(extra or {}) do
		table.insert(list, x)
	end
	return list
end

local rayP = RaycastParams.new()
rayP.FilterType = Enum.RaycastFilterType.Exclude
rayP.IgnoreWater = true
rayP.RespectCanCollide = true
local boxP = OverlapParams.new()
boxP.FilterType = Enum.RaycastFilterType.Exclude
boxP.RespectCanCollide = true

-- street-level ground at (x, z) with room for a body standH tall and 2 * halfW wide, or nil
local function openAt(x, z, standH, halfW)
	local from = GroundGuard.SURFACE_Y + 8
	local hit = workspace:Raycast(V3(x, from, z), V3(0, -24, 0), rayP)
	if not hit then
		return nil
	end
	local y = hit.Position.Y
	if y < GroundGuard.FLOOR_Y - 2 or y > GroundGuard.SURFACE_Y + 6 or hit.Normal.Y < 0.6 then
		return nil
	end
	local parts = workspace:GetPartBoundsInBox(CFrame.new(x, y + 0.4 + standH / 2, z), V3(halfW * 2, standH, halfW * 2), boxP)
	if #parts > 0 then
		return nil
	end
	return V3(x, y, z)
end

function GroundGuard.findSpot(pos, ignore, group, standH, halfW)
	local list = ignoreList(ignore)
	rayP.FilterDescendantsInstances = list
	boxP.FilterDescendantsInstances = list
	pcall(function()
		rayP.CollisionGroup = group or "Default"
		boxP.CollisionGroup = group or "Default"
	end)
	standH = math.clamp(standH or 5, 2, 60)
	halfW = math.clamp(halfW or 1.5, 0.5, 20)
	local p = openAt(pos.X, pos.Z, standH, halfW)
	if p then
		return p
	end
	local step, maxR = F.SEARCH_STEP or 8, F.SEARCH_MAX or 96
	for r = step, maxR, step do
		local n = math.max(8, math.floor(2 * math.pi * r / step))
		local a0 = math.random() * math.pi * 2
		for i = 0, n - 1 do
			local a = a0 + i / n * math.pi * 2
			p = openAt(pos.X + math.cos(a) * r, pos.Z + math.sin(a) * r, standH, halfW)
			if p then
				return p
			end
		end
	end
	return nil
end

local function nearestSpawn(pos)
	local best, bd
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			local dd = (d.Position - pos).Magnitude
			if not bd or dd < bd then
				best, bd = d, dd
			end
		end
	end
	return best and (best.Position + V3(0, best.Size.Y / 2, 0)) or V3(0, GroundGuard.SURFACE_Y, 0)
end

-- how tall the body stands (root pivot above its feet) and how wide it is
function GroundGuard.bodySize(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local scale = 1
	pcall(function()
		scale = model:GetScale()
	end)
	local pivotH = ((hum and hum.HipHeight) or 2) + ((root and root.Size.Y / 2) or 1)
	return pivotH, math.max(pivotH * 2, 5 * scale), 1.5 * scale
end

function GroundGuard.rescue(model, lastSafe)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then
		return false
	end
	local torso = model:FindFirstChild("LowerTorso") or root
	local pivotH, standH, halfW = GroundGuard.bodySize(model)
	local group = root.CollisionGroup
	local at = torso.Position
	local spot = GroundGuard.findSpot(at, { model }, group, standH, halfW)
	if not spot and lastSafe then
		spot = GroundGuard.findSpot(lastSafe, { model }, group, standH, halfW) or lastSafe
	end
	spot = spot or nearestSpawn(at)
	-- keep the facing (yaw only), stand it upright on the spot
	local look = root.CFrame.LookVector
	local flat = V3(look.X, 0, look.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or V3(0, 0, -1)
	local target = CFrame.lookAt(spot + V3(0, pivotH + 0.5, 0), spot + V3(0, pivotH + 0.5, 0) + flat)
	-- a ragdoll's limbs are separate assemblies: move the whole model by the root's offset
	local pivot = model:GetPivot()
	local delta = target * root.CFrame:Inverse()
	model:PivotTo(delta * pivot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	model:SetAttribute("FallRescuedAt", workspace:GetServerTimeNow())
	return true, spot
end

local LIFT_DEPTH = 14 -- deeper than this is FallGuard's job (it is not something a refill just closed over)
local npcTag
local function bodiesNear()
	if not npcTag then
		npcTag = "RagdollNPC"
		pcall(function()
			npcTag = require(game:GetService("ReplicatedStorage").GojoShared.Config.NPC).Tag or npcTag
		end)
	end
	local seen, list = {}, {}
	local function add(m)
		if m and not seen[m] and m:IsA("Model") and m:IsDescendantOf(workspace) then
			seen[m] = true
			table.insert(list, m)
		end
	end
	for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
		add(pl.Character)
	end
	for _, m in ipairs(game:GetService("CollectionService"):GetTagged(npcTag)) do
		add(m)
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		for _, m in ipairs(npcs:GetChildren()) do
			add(m)
		end
	end
	return list
end

local function liftNow(region, pad)
	local cpos, half = region.CFrame.Position, region.Size / 2
	pad = pad or 2
	local from = math.max(cpos.Y + half.Y, GroundGuard.SURFACE_Y) + 30
	local n = 0
	for _, m in ipairs(bodiesNear()) do
		local torso = m:FindFirstChild("LowerTorso") or m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if torso and not m:GetAttribute("NoFallGuard") then
			local p = torso.Position
			if math.abs(p.X - cpos.X) <= half.X + pad and math.abs(p.Z - cpos.Z) <= half.Z + pad and p.Y < from then
				-- straight down onto the torso: any terrain surface on the way means it is now inside the ground
				local hit = workspace:Raycast(V3(p.X, from, p.Z), V3(0, p.Y - from, 0), terrainOnly)
				local depth = hit and hit.Position.Y - p.Y
				if depth and depth > 0.25 and depth < LIFT_DEPTH then
					local pivotH = GroundGuard.bodySize(m)
					m:PivotTo(m:GetPivot() + V3(0, depth + math.max(pivotH, 3), 0))
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("BasePart") and not d.Anchored then
							d.AssemblyLinearVelocity = Vector3.zero
							d.AssemblyAngularVelocity = Vector3.zero
						end
					end
					m:SetAttribute("GroundLiftedAt", workspace:GetServerTimeNow())
					n += 1
				end
			end
		end
	end
	return n
end

-- (2026-11-07, measured in Play) a raycast in the SAME frame as Terrain:WriteVoxels still sees the old hole - terrain
-- collision only updates by the next Heartbeat - so lifting synchronously found nobody and the sealed body then fell
-- through the map. liftOut therefore lifts one frame after the refill, and once more 0.25 s later as a safety net.
-- Returns at once (callers run inside Heartbeat loops and must not yield).
function GroundGuard.liftOut(region, pad)
	if typeof(region) ~= "Region3" then
		return 0
	end
	task.spawn(function()
		game:GetService("RunService").Heartbeat:Wait()
		pcall(liftNow, region, pad)
		task.wait(0.25)
		pcall(liftNow, region, pad)
	end)
	return 0
end

return GroundGuard
