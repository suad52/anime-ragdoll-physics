--!nocheck
-- GomuKit.Hat (server; owner: core): LUFFY's straw hat. GomuServer.Core builds it on the character while the Gomu kit
-- is equipped (Hat.attach on equip / spawn, a 1 s watchdog re-attaches it after an avatar reload) and removes it on
-- unequip (Hat.detach). Built from plain parts so it needs no asset: a two-tone brim (a straw disc riding on a darker
-- rim), a cylinder crown with a flattened dome on top, and the red band. Every part is Massless, CanCollide /
-- CanQuery / CanTouch false, CastShadow false and WELDED to the Head (never anchored), so it rides the body on every
-- client with no client code. Sizes are in studs for a 1.2-stud head and scale with the real head's height.
-- While it is on, every Hat-type accessory (its Handle carries a "HatAttachment") is hidden: Handle.Transparency 1,
-- the original kept in the attribute "GomuHatHid"; detach puts every one back exactly.
-- API: Hat.attach(char, H) -> Model "StrawHat" | nil, Hat.detach(char), Hat.get(char) -> Model | nil.
-- H = Config.Hat { BrimDiameter, BrimThick, CrownDiameter, CrownHeight, BandHeight, Lift (brim height above the head
-- centre, x head height), Back (x head depth), Tilt (degrees; NEGATIVE tips the front of the brim UP - the hat pushed
-- back on the head), HideHats }.
local Hat = {}

local HAT_NAME = "StrawHat"
local HID_ATTR = "GomuHatHid"
local DEFAULT = {
	BrimDiameter = 3.0, BrimThick = 0.1, CrownDiameter = 1.45, CrownHeight = 0.62, BandHeight = 0.2,
	Lift = 0.36, Back = 0.05, Tilt = -9, HideHats = true,
}
local STAND = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is its X: stand it up

local conns = setmetatable({}, { __mode = "k" }) -- [char] = ChildAdded connection (late accessories get hidden too)

local palette
local function colors()
	if palette then
		return palette
	end
	local P = {}
	local cfg = script.Parent:FindFirstChild("Config")
	if cfg then
		local ok, CFG = pcall(require, cfg)
		if ok and type(CFG) == "table" and type(CFG.Palette) == "table" then
			P = CFG.Palette
		end
	end
	palette = {
		Straw = P.Straw or Color3.fromRGB(244, 206, 92),
		StrawDark = P.StrawDark or Color3.fromRGB(190, 146, 52),
		Band = P.Band or Color3.fromRGB(196, 22, 30),
	}
	return palette
end

local function num(H, k)
	local v = type(H) == "table" and tonumber(H[k]) or nil
	return v or DEFAULT[k]
end

---------------------------------------------------------------------------------------------------
-- hiding the avatar's own hats

local function hideAccessory(acc)
	if not acc:IsA("Accessory") then
		return
	end
	local h = acc:FindFirstChild("Handle")
	if not (h and h:IsA("BasePart") and h:FindFirstChild("HatAttachment")) then
		return
	end
	if h:GetAttribute(HID_ATTR) == nil then
		h:SetAttribute(HID_ATTR, h.Transparency)
		h.Transparency = 1
	end
	for _, d in ipairs(h:GetChildren()) do -- a decal on a hidden handle would still draw
		if (d:IsA("Decal") or d:IsA("Texture")) and d:GetAttribute(HID_ATTR) == nil then
			d:SetAttribute(HID_ATTR, d.Transparency)
			d.Transparency = 1
		end
	end
end

local function restoreAccessories(char)
	for _, acc in ipairs(char:GetChildren()) do
		if acc:IsA("Accessory") then
			local h = acc:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then
				local t = h:GetAttribute(HID_ATTR)
				if type(t) == "number" then
					h.Transparency = t
				end
				h:SetAttribute(HID_ATTR, nil)
				for _, d in ipairs(h:GetChildren()) do
					local dt = d:GetAttribute(HID_ATTR)
					if type(dt) == "number" and (d:IsA("Decal") or d:IsA("Texture")) then
						d.Transparency = dt
						d:SetAttribute(HID_ATTR, nil)
					end
				end
			end
		end
	end
end

local function hideAll(char)
	for _, acc in ipairs(char:GetChildren()) do
		hideAccessory(acc)
	end
	if not conns[char] then
		conns[char] = char.ChildAdded:Connect(function(c)
			if c:IsA("Accessory") then
				task.defer(function() -- the Handle and its attachment arrive with it, but give the avatar loader a frame
					if c.Parent == char and char:FindFirstChild(HAT_NAME) then
						hideAccessory(c)
					end
				end)
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- the hat

local function part(name, shape, size, color, material, model, head, c0)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Massless = true
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = head.CFrame * c0
	local w = Instance.new("Weld")
	w.Name = "HatWeld"
	w.Part0 = head
	w.Part1 = p
	w.C0 = c0
	w.C1 = CFrame.identity
	w.Parent = p
	p.Parent = model
	return p
end

-- the StrawHat model on this character's CURRENT head, or nil (missing, or left welded to a replaced head)
function Hat.get(char)
	if not char then
		return nil
	end
	local model = char:FindFirstChild(HAT_NAME)
	if not (model and model:IsA("Model")) then
		return nil
	end
	local head = char:FindFirstChild("Head")
	local brim = model:FindFirstChild("Brim")
	local w = brim and brim:FindFirstChild("HatWeld")
	if not head or not w or w.Part0 ~= head then
		return nil
	end
	return model
end

function Hat.attach(char, H)
	if not char or not char.Parent then
		return nil
	end
	local head = char:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return nil
	end
	local hide = not (type(H) == "table" and H.HideHats == false)
	local have = Hat.get(char)
	if have then
		if hide then
			hideAll(char)
		end
		return have
	end
	local stale = char:FindFirstChild(HAT_NAME)
	if stale then
		stale:Destroy() -- welded to a head the avatar loader replaced
	end

	local P = colors()
	local headH, headD = head.Size.Y, head.Size.Z
	local k = headH / 1.2
	local brimD, brimT = num(H, "BrimDiameter") * k, num(H, "BrimThick") * k
	local crownD, crownH = num(H, "CrownDiameter") * k, num(H, "CrownHeight") * k
	local bandH = num(H, "BandHeight") * k
	-- the hat's frame on the head: up Lift x head height, back Back x head depth (+Z is behind), tipped about X
	local base = CFrame.new(0, num(H, "Lift") * headH, num(H, "Back") * headD) * CFrame.Angles(math.rad(-num(H, "Tilt")), 0, 0)

	local model = Instance.new("Model")
	model.Name = HAT_NAME
	-- the rim: the full-width disc in the darker straw; the brim proper rides on it, a little narrower and thicker,
	-- so only a thin dark edge shows top and bottom
	part("BrimEdge", Enum.PartType.Cylinder, Vector3.new(brimT, brimD, brimD), P.StrawDark, Enum.Material.Fabric, model,
		head, base * STAND)
	local brim = part("Brim", Enum.PartType.Cylinder, Vector3.new(brimT * 1.3, brimD - 0.14 * k, brimD - 0.14 * k),
		P.Straw, Enum.Material.Fabric, model, head, base * STAND)
	part("Crown", Enum.PartType.Cylinder, Vector3.new(crownH, crownD, crownD), P.Straw, Enum.Material.Fabric, model,
		head, base * CFrame.new(0, brimT * 0.5 + crownH * 0.5, 0) * STAND)
	local top = part("Top", Enum.PartType.Block, Vector3.new(crownD, crownD * 0.3, crownD), P.Straw, Enum.Material.Fabric,
		model, head, base * CFrame.new(0, brimT * 0.5 + crownH, 0))
	local dome = Instance.new("SpecialMesh")
	dome.MeshType = Enum.MeshType.Sphere
	dome.Parent = top
	part("Band", Enum.PartType.Cylinder, Vector3.new(bandH, crownD + 0.06 * k, crownD + 0.06 * k), P.Band,
		Enum.Material.SmoothPlastic, model, head, base * CFrame.new(0, brimT * 0.65 + bandH * 0.5, 0) * STAND)
	model.PrimaryPart = brim
	model.Parent = char

	if hide then
		hideAll(char)
	end
	return model
end

function Hat.detach(char)
	if not char then
		return
	end
	local c = conns[char]
	if c then
		c:Disconnect()
		conns[char] = nil
	end
	for _, m in ipairs(char:GetChildren()) do
		if m.Name == HAT_NAME and m:IsA("Model") then
			m:Destroy()
		end
	end
	restoreAccessories(char)
end

return Hat
