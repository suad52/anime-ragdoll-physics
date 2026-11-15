--!nocheck
-- StarterPlayerScripts.PlayerMarkers (2026-11-08): makes OTHER PLAYERS easy to find in the city - they used to read like the
-- 36 dummies (same rigs, no nameplate beyond Roblox's grey 100-stud name, a faint outline only after dark).
-- Client-only, BillboardGuis + one ScreenGui, no Highlights (the 31-Highlight budget belongs to the kits and
-- NightOutlines). For every other living player:
--   PLATE  above the head (depth-tested like the world): display name in the fighter's accent colour + a slim HP bar.
--          Shown while the body is in view and within PLATE_MAX. Sits above a ShopTitle when the player wears one.
--   PIP    a kit-coloured chevron with the name and distance, drawn THROUGH walls (AlwaysOnTop) when the player is
--          further than PLATE_MAX, or hidden behind a building / wall and further than PIP_MIN. Fades out to PIP_MAX.
--   ARROW  a screen-edge arrow (name + distance) pointing at players within ARROW_RANGE that are off screen
--          (nearest ARROW_MAX). The bottom edge keeps clear of the MoveDock bar.
--   Roblox's default name / health display is switched off on other players' humanoids (locally) - the plate
--   replaces it. Nothing shows for a dead player, or while the body is vanished (Shunpo / any move that sets its
--   torso + head LocalTransparencyModifier or Transparency to ~1), so stealth / teleport moves keep working.
-- Studio: script.PlayerMarkersDebug:Invoke("fake", model) treats a model (e.g. an NPC) as a player for testing;
--   ("clear") removes the fakes; ("state") -> { [name] = mode }.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = {
	PLATE_MAX = 220, -- studs: the plate is drawn up to here while the body is in view
	PIP_MIN = 300, -- (2026-11-11) "make the player marker come up when others are >300 studs away, not <300" (was 24)
	-- (2026-11-08) "only have marker for 300 meters of distance": no pip or edge arrow past 300 (the number the pip shows)
	PIP_MAX = 2000, -- ...the whole city (~1600 across); was 300 when markers were for NEARBY players
	ARROW_RANGE = 300, -- (2026-11-11) the edge arrow now shows for players FARTHER than this (it was: nearer)
	ARROW_MAX = 6,
	EDGE_PAD = 44, -- px from the screen edge
	EDGE_PAD_BOTTOM = 150, -- px: the MoveDock bar lives at the bottom
	LOS_TICK = 0.12, -- s between line-of-sight checks per target
}

local player = Players.LocalPlayer
local pgui = player:WaitForChild("PlayerGui")
local Kits
pcall(function()
	Kits = require(ReplicatedStorage:WaitForChild("HudShared", 10):WaitForChild("Kits", 10))
end)
local FONT = (Kits and Kits.FONT_PUNCH) or Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(10, 8, 18)

local function accentOf(p)
	local id = p and p:GetAttribute("Kit")
	local k = Kits and Kits.byId and id and Kits.byId[id]
	return (k and k.accent) or Color3.fromRGB(255, 214, 90)
end

local function stroke(parent, th)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = th or 2
	s.Parent = parent
	return s
end

local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = FONT
	t.TextColor3 = WHITE
	t.TextScaled = true
	for k, v in pairs(props) do
		t[k] = v
	end
	t.Parent = parent
	return t
end

-- screen layer for the edge arrows
local screen = Instance.new("ScreenGui")
screen.Name = "PlayerMarkersEdge"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 2
screen.Parent = pgui

---------------------------------------------------------------------------------------------------
-- per target
local recs = {} -- [key (Player | fake Model)] = rec
local fakes = {} -- [model] = name

local function build(key, name)
	local r = { key = key, name = name, mode = "none", nextLos = 0, visible = true }
	-- plate
	local plate = Instance.new("BillboardGui")
	plate.Name = "PlayerPlate_" .. name
	plate.Size = UDim2.fromOffset(180, 36)
	plate.LightInfluence = 0
	plate.AlwaysOnTop = false
	plate.ResetOnSpawn = false
	plate.Enabled = false
	r.plateName = label(plate, { Size = UDim2.new(1, 0, 0, 22), Text = name })
	r.plateStroke = stroke(r.plateName, 2)
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 25)
	back.Size = UDim2.fromOffset(96, 6)
	back.BackgroundColor3 = INK
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = plate
	Instance.new("UICorner", back).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromRGB(110, 235, 130)
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	r.hpFill = fill
	plate.Parent = pgui
	r.plate = plate
	-- pip (through walls)
	local pip = Instance.new("BillboardGui")
	pip.Name = "PlayerPip_" .. name
	pip.Size = UDim2.fromOffset(120, 54)
	pip.LightInfluence = 0
	pip.AlwaysOnTop = true
	pip.ResetOnSpawn = false
	pip.Enabled = false
	pip.MaxDistance = CFG.PIP_MAX + 50
	r.pipName = label(pip, { Size = UDim2.new(1, 0, 0, 15), Text = name })
	stroke(r.pipName, 1.5)
	r.pipChev = label(pip, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 24), Text = "\u{25BC}" })
	stroke(r.pipChev, 2)
	r.pipDist = label(pip, { Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 13), Text = "" })
	stroke(r.pipDist, 1.5)
	pip.Parent = pgui
	r.pip = pip
	-- edge arrow
	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow_" .. name
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(110, 58)
	arrow.BackgroundTransparency = 1
	arrow.Visible = false
	arrow.Parent = screen
	r.arrowHead = label(arrow, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromOffset(30, 30), Text = "\u{25B2}" })
	stroke(r.arrowHead, 2)
	r.arrowText = label(arrow, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.32, 16), Size = UDim2.new(1, 0, 0, 14), Text = name })
	stroke(r.arrowText, 1.5)
	r.arrow = arrow
	return r
end

local function drop(key)
	local r = recs[key]
	if r then
		r.plate:Destroy()
		r.pip:Destroy()
		r.arrow:Destroy()
		recs[key] = nil
	end
end

-- the current targets: { key, name, char, accent }
local function targets()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			table.insert(list, { key = p, name = p.DisplayName, char = p.Character, accent = accentOf(p) })
		end
	end
	for m, name in pairs(fakes) do
		if m.Parent then
			table.insert(list, { key = m, name = name, char = m, accent = Color3.fromRGB(255, 160, 60) })
		else
			fakes[m] = nil
		end
	end
	return list
end

-- (2026-11-09) inside a Smoke Bomb cloud (ShopService.Ext.Gadgets: tag GadgetSmoke, Radius / Until attributes)
local CollectionService = game:GetService("CollectionService")
local function inSmoke(pos)
	local now = workspace:GetServerTimeNow()
	for _, c in ipairs(CollectionService:GetTagged("GadgetSmoke")) do
		local r, untilT = c:GetAttribute("Radius"), c:GetAttribute("Until")
		if r and untilT and untilT > now and c:IsA("BasePart") and (c.Position - pos).Magnitude < r then
			return true
		end
	end
	return false
end

local function vanished(char)
	local n, hidden = 0, 0
	for _, nm in ipairs({ "Head", "UpperTorso", "LowerTorso" }) do
		local p = char:FindFirstChild(nm)
		if p and p:IsA("BasePart") then
			n += 1
			if p.LocalTransparencyModifier > 0.9 or p.Transparency > 0.9 then
				hidden += 1
			end
		end
	end
	return n > 0 and hidden == n
end

-- can the camera see this body? (ignores bodies, effects, debris and see-through parts)
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
local function lineOfSight(from, to, char)
	local ignore = { char }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	for _, n in ipairs({ "NPCs", "FX", "KitFX", "KitDebris", "CityDebris" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(ignore, cam)
	end
	for _ = 1, 5 do
		losParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(from, to - from, losParams)
		if not hit then
			return true
		end
		local inst = hit.Instance
		if inst:IsA("BasePart") and (inst.Transparency > 0.55 or inst.LocalTransparencyModifier > 0.55) then
			table.insert(ignore, inst) -- glass, invisible colliders: look through
		else
			return false
		end
	end
	return true
end

local function hideAll(r)
	r.plate.Enabled = false
	r.pip.Enabled = false
	r.arrow.Visible = false
	r.mode = "none"
end

---------------------------------------------------------------------------------------------------
local function step()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local t = os.clock()
	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local seen = {}
	local offscreen = {}
	for _, e in ipairs(targets()) do
		seen[e.key] = true
		local r = recs[e.key]
		if not r or r.name ~= e.name then
			drop(e.key)
			r = build(e.key, e.name)
			recs[e.key] = r
		end
		local char = e.char
		local hum = char:FindFirstChildOfClass("Humanoid")
		local head = char:FindFirstChild("Head")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not head or not head:IsA("BasePart") or not root or hum.Health <= 0 or char:GetAttribute("Dead") or vanished(char)
			or inSmoke(root.Position) then
			hideAll(r)
		else
			-- Roblox's own name tag goes: the plate replaces it (local change only)
			if hum.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None and not fakes[char] then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end
			local pos = head.Position
			local d = (pos - camPos).Magnitude
			if t >= r.nextLos then
				r.nextLos = t + CFG.LOS_TICK * (d > 300 and 2 or 1)
				r.visible = lineOfSight(camPos, pos, char)
			end
			local accent = e.accent
			-- plate: above the head (and above a ShopTitle if there is one)
			local titled = head:FindFirstChild("ShopTitle") ~= nil
			r.plate.Adornee = head
			r.plate.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + (titled and 3.4 or 1.7), 0)
			r.plateName.TextColor3 = accent:Lerp(WHITE, 0.25)
			local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			r.hpFill.Size = UDim2.fromScale(hp, 1)
			r.hpFill.BackgroundColor3 = Color3.fromRGB(235, 70, 70):Lerp(Color3.fromRGB(110, 235, 130), hp)
			local plateOn = r.visible and d <= CFG.PLATE_MAX
			local pipOn = not plateOn and d >= CFG.PIP_MIN and d <= CFG.PIP_MAX
			r.plate.Enabled = plateOn
			r.pip.Enabled = pipOn
			if pipOn then
				r.pip.Adornee = head
				r.pip.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y * 0.5 + 2.4, 0)
				local fade = math.clamp((d - CFG.PIP_MAX * 0.6) / (CFG.PIP_MAX * 0.4), 0, 0.7)
				r.pipChev.TextColor3 = accent
				r.pipName.TextColor3 = accent:Lerp(WHITE, 0.35)
				r.pipDist.Text = string.format("%d", math.floor(d + 0.5))
				for _, l in ipairs({ r.pipChev, r.pipName, r.pipDist }) do
					l.TextTransparency = fade
				end
			end
			r.mode = plateOn and "plate" or (pipOn and "pip" or "none")
			-- off screen?
			local sp, onScreen = cam:WorldToViewportPoint(pos)
			local inView = onScreen and sp.Z > 0 and sp.X >= 0 and sp.X <= vp.X and sp.Y >= 0 and sp.Y <= vp.Y
			if not inView and d > CFG.ARROW_RANGE then
				table.insert(offscreen, { r = r, d = d, sp = sp, accent = accent })
			else
				r.arrow.Visible = false
			end
		end
	end
	for key in pairs(recs) do
		if not seen[key] then
			drop(key)
		end
	end
	-- edge arrows, nearest first
	table.sort(offscreen, function(a, b)
		return a.d < b.d
	end)
	local cx, cy = vp.X / 2, vp.Y / 2
	for i, o in ipairs(offscreen) do
		local a = o.r.arrow
		if i > CFG.ARROW_MAX then
			a.Visible = false
		else
			local dx, dy = o.sp.X - cx, o.sp.Y - cy
			if o.sp.Z < 0 then -- behind the camera: the projection is mirrored
				dx, dy = -dx, -dy
			end
			if math.abs(dx) < 1e-3 and math.abs(dy) < 1e-3 then
				dy = 1
			end
			local left, right = CFG.EDGE_PAD, vp.X - CFG.EDGE_PAD
			local top, bottom = CFG.EDGE_PAD, vp.Y - CFG.EDGE_PAD_BOTTOM
			local hx, hy = (right - left) / 2, (bottom - top) / 2
			local ox, oy = (left + right) / 2, (top + bottom) / 2
			local k = math.min(hx / math.max(math.abs(dx), 1e-3), hy / math.max(math.abs(dy), 1e-3))
			a.Position = UDim2.fromOffset(ox + dx * k, oy + dy * k)
			o.r.arrowHead.Rotation = math.deg(math.atan2(dy, dx)) + 90
			o.r.arrowHead.TextColor3 = o.accent
			o.r.arrowText.Text = string.format("%s  %d", o.r.name, math.floor(o.d + 0.5))
			o.r.arrowText.TextColor3 = o.accent:Lerp(WHITE, 0.4)
			a.Visible = true
		end
	end
end

local lastErr
RunService:BindToRenderStep("PlayerMarkers", Enum.RenderPriority.Camera.Value + 5, function()
	local ok, err = pcall(step)
	if not ok and lastErr ~= err then
		lastErr = err
		warn("[PlayerMarkers] " .. tostring(err))
	end
end)

Players.PlayerRemoving:Connect(drop)

if RunService:IsStudio() then
	local f = Instance.new("BindableFunction")
	f.Name = "PlayerMarkersDebug"
	f.OnInvoke = function(cmd, arg, name)
		if cmd == "fake" and typeof(arg) == "Instance" then
			fakes[arg] = name or arg.Name
			return true
		elseif cmd == "clear" then
			fakes = {}
			return true
		end
		local s = {}
		for _, r in pairs(recs) do
			s[r.name] = { mode = r.mode, visible = r.visible, arrow = r.arrow.Visible }
		end
		return s
	end
	f.Parent = script
end
