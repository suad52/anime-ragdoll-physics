--!nocheck
-- StarterPlayerScripts.FloodView (2026-11-13): what the disaster box's flood looks like from INSIDE it.
-- A part has no inside faces, so the moment the camera goes under, the water stops being drawn at all - you would be
-- standing in a flood you cannot see. While the camera is inside any FloodWater part the screen is tinted and softened
-- instead.
-- (2026-11-15, owner: "fix the lag on the flooding event") this script now also DRAWS the water. Sandbox.Hazards
-- RUN.Flood only keeps a tiny invisible FloodRig (tag "FloodRig") at the centre of the box floor, with attributes
-- SpanX / SpanZ / Level; the water body and its lighter surface sheet are made here, on this screen only, and glide
-- to the Level every frame - smooth on any frame rate, and nothing big streams from the server. Visual only: the
-- server decides who floats and who drowns from the same Level.
-- NOT Material.Glass, and nothing between the water and the watcher may be Glass either (Roblox does not draw a
-- see-through part behind Glass).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "FloodTint"
tint.TintColor = Color3.fromRGB(96, 160, 255)
tint.Brightness, tint.Contrast, tint.Saturation = -0.05, -0.1, -0.15
tint.Enabled = false
tint.Parent = Lighting
local blur = Instance.new("BlurEffect")
blur.Name = "FloodBlur"
blur.Size = 8
blur.Enabled = false
blur.Parent = Lighting

local floods = {} -- [rig] = { water, surf, shown }
local function sheet(name, color, tr)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency = Enum.Material.SmoothPlastic, color, tr
	return p
end
local function add(rig)
	if floods[rig] or not rig:IsA("BasePart") then
		return
	end
	local water = sheet("FloodWater", Color3.fromRGB(34, 104, 190), 0.42)
	local surf = sheet("FloodSurface", Color3.fromRGB(130, 196, 242), 0.22)
	CollectionService:AddTag(water, "FloodWater") -- the under-water check below
	local f = { water = water, surf = surf, shown = tonumber(rig:GetAttribute("Level")) or 0.2 }
	floods[rig] = f
	water.Parent = workspace.CurrentCamera -- this screen only, never saved or streamed
	surf.Parent = workspace.CurrentCamera
end
local function remove(rig)
	local f = floods[rig]
	if f then
		floods[rig] = nil
		f.water:Destroy()
		f.surf:Destroy()
	end
end
CollectionService:GetInstanceAddedSignal("FloodRig"):Connect(add)
CollectionService:GetInstanceRemovedSignal("FloodRig"):Connect(remove)
for _, r in ipairs(CollectionService:GetTagged("FloodRig")) do
	add(r)
end
-- (2026-11-15) any other FloodWater body tints the screen too: the shop's map-wide Flood event
-- (PerkMapEventsClient.Flood) tags its own water part
local others = {}
CollectionService:GetInstanceAddedSignal("FloodWater"):Connect(function(p)
	others[p] = true
end)
CollectionService:GetInstanceRemovedSignal("FloodWater"):Connect(function(p)
	others[p] = nil
end)
for _, p in ipairs(CollectionService:GetTagged("FloodWater")) do
	others[p] = true
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for rig, f in pairs(floods) do
		if not rig.Parent then
			remove(rig)
		else
			local target = tonumber(rig:GetAttribute("Level")) or 0.2
			-- the server moves the level ten times a second; ease toward it so it rises and drains without steps
			f.shown += (target - f.shown) * math.min(1, dt * 12)
			local lv = math.max(0.2, f.shown)
			local sx, sz = rig:GetAttribute("SpanX") or 60, rig:GetAttribute("SpanZ") or 60
			local base = rig.CFrame
			f.water.Size = Vector3.new(sx, lv, sz)
			f.water.CFrame = base * CFrame.new(0, lv / 2, 0)
			f.surf.Size = Vector3.new(sx, 0.24, sz)
			f.surf.CFrame = base * CFrame.new(0, lv + 0.1 + math.sin(now * 2.4) * 0.06, 0)
		end
	end
	local cam = workspace.CurrentCamera
	local under = false
	if cam and next(others) then
		local pos = cam.CFrame.Position
		for w in pairs(others) do
			if not w.Parent then
				others[w] = nil
			elseif w.Transparency < 1 then
				local l = w.CFrame:PointToObjectSpace(pos)
				local h = w.Size / 2
				if math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z then
					under = true
					break
				end
			end
		end
	end
	if tint.Enabled ~= under then
		tint.Enabled = under
		blur.Enabled = under
	end
end)
