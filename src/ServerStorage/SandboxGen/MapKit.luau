--!nocheck
-- ServerStorage.SandboxGen.MapKit: the part helpers every area builder uses. Everything is anchored; cylinders take a
-- CFrame whose Y axis is the cylinder's axis. Runtime behaviour is declared with CollectionService tags + attributes
-- (ServerScriptService.Sandbox reads them), never with scripts inside the map.
local CollectionService = game:GetService("CollectionService")
local K = {}
K.C = Color3.fromRGB
K.PAL = {
	concrete = K.C(176, 172, 164), concreteDark = K.C(120, 118, 114), pave = K.C(148, 144, 138), curb = K.C(206, 200, 190),
	asphalt = K.C(52, 52, 56), steel = K.C(92, 98, 108), steelDark = K.C(48, 52, 60), wood = K.C(128, 92, 58),
	woodDark = K.C(88, 62, 40), hazard = K.C(245, 196, 40), orange = K.C(236, 118, 32), red = K.C(196, 44, 40),
	blue = K.C(44, 96, 190), navy = K.C(22, 26, 38), white = K.C(238, 236, 230), glass = K.C(170, 205, 220),
	leaf = K.C(72, 122, 60), leaf2 = K.C(94, 140, 66), leaf3 = K.C(58, 104, 58), bark = K.C(92, 68, 48),
}
function K.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function base(p, parent, name, color, mat, extra)
	p.Name = name
	p.Anchored = true
	p.Color = color or K.PAL.concrete
	p.Material = mat or Enum.Material.Concrete
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(extra or {}) do
		if k == "tag" then
			CollectionService:AddTag(p, v)
		elseif k == "attrs" then
			for a, av in pairs(v) do
				p:SetAttribute(a, av)
			end
		else
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end
function K.part(parent, name, size, cf, color, mat, extra)
	local p = Instance.new("Part")
	p.Size, p.CFrame = size, cf
	return base(p, parent, name, color, mat, extra)
end
function K.wedge(parent, name, size, cf, color, mat, extra)
	local p = Instance.new("WedgePart")
	p.Size, p.CFrame = size, cf
	return base(p, parent, name, color, mat, extra)
end
function K.corner(parent, name, size, cf, color, mat, extra)
	local p = Instance.new("CornerWedgePart")
	p.Size, p.CFrame = size, cf
	return base(p, parent, name, color, mat, extra)
end
function K.cyl(parent, name, dia, len, cf, color, mat, extra)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size, p.CFrame = Vector3.new(len, dia, dia), cf * CFrame.Angles(0, 0, math.pi / 2)
	return base(p, parent, name, color, mat, extra)
end
function K.ball(parent, name, dia, pos, color, mat, extra)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size, p.CFrame = Vector3.new(dia, dia, dia), CFrame.new(pos)
	return base(p, parent, name, color, mat, extra)
end
function K.truss(parent, name, size, cf, color)
	local p = Instance.new("TrussPart")
	p.Size, p.CFrame = size, cf
	return base(p, parent, name, color or K.PAL.steel, Enum.Material.Metal)
end
function K.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
function K.tag(inst, tag, attrs)
	CollectionService:AddTag(inst, tag)
	for a, v in pairs(attrs or {}) do
		inst:SetAttribute(a, v)
	end
	return inst
end
-- a text face on a part (both big faces by default)
-- SIGNS (2026-11-13): the owner - "change the font to make it look less ai and make it all just black with no colours
-- except for the text which should be white ... just make it look normal". Every sign had its own look: a cartoon
-- face (LuckiestGuy) with a thick ink outline, navy / red / yellow boards, orange and hazard trims, tilted danger
-- plates, tinted lettering. Now there is ONE: a black board, black trim and post, white Gotham Bold, no outline, hung
-- straight. K.sign and K.danger ignore the back / trim / color / stroke a caller passes, so an area cannot opt out by
-- accident. The only lettering that keeps a colour is a machine's status SCREEN (opts.screen): scripts recolour
-- those as the machine's state changes.
K.SIGN_BLACK = K.C(14, 14, 16)
K.SIGN_INK = K.C(255, 255, 255)
function K.label(part, text, opts)
	opts = opts or {}
	for _, face in ipairs(opts.faces or { Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = K.new("SurfaceGui", { Name = "Label", Face = face, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = opts.pps or 30,
			-- (2026-11-13) sign lettering ignores the scene's light: measured on a board's shaded side, white on black at
			-- LightInfluence 0.6 was all but invisible. Only a screen keeps the old lit / glowing behaviour.
			LightInfluence = (opts.screen and not opts.glow) and 0.6 or 0, Brightness = (opts.screen and opts.glow) and 2 or 1 }, part)
		local t = K.new("TextLabel", { Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), BackgroundTransparency = 1,
			Text = text, TextScaled = true, TextWrapped = false, Font = opts.font or Enum.Font.GothamBold, TextColor3 = (opts.screen and opts.color) or K.SIGN_INK,
			RichText = true }, g)
		if opts.screen and (opts.strokeW or 3) > 0 then -- a screen keeps its outline; a sign is plain white on black
			K.new("UIStroke", { Color = opts.stroke or K.C(12, 14, 20), Thickness = opts.strokeW or 3 }, t)
		end
	end
	return part
end
function K.sign(parent, text, cf, size, opts)
	opts = opts or {}
	local p = K.part(parent, "Sign", Vector3.new(size.X, size.Y, 0.5), cf, K.SIGN_BLACK, Enum.Material.SmoothPlastic)
	K.part(parent, "SignTrim", Vector3.new(size.X + 0.6, 0.5, 0.7), cf * CFrame.new(0, -size.Y / 2 - 0.2, 0), K.SIGN_BLACK, Enum.Material.SmoothPlastic)
	K.label(p, text, opts)
	return p
end
function K.lamp(parent, pos, yaw)
	local m = K.model(parent, "Lamp")
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
	K.cyl(m, "Base", 1.4, 0.8, cf * CFrame.new(0, 0.4, 0), K.PAL.steelDark, Enum.Material.Metal)
	K.cyl(m, "Pole", 0.5, 13, cf * CFrame.new(0, 6.9, 0), K.PAL.steelDark, Enum.Material.Metal)
	K.part(m, "Arm", Vector3.new(0.4, 0.4, 3.4), cf * CFrame.new(0, 13.2, -1.5), K.PAL.steelDark, Enum.Material.Metal)
	local head = K.part(m, "Head", Vector3.new(1.6, 0.5, 2.2), cf * CFrame.new(0, 13, -2.8), K.PAL.steelDark, Enum.Material.Metal)
	local glow = K.part(m, "Glow", Vector3.new(1.2, 0.2, 1.8), cf * CFrame.new(0, 12.7, -2.8), K.C(255, 226, 170), Enum.Material.Neon, { CastShadow = false })
	K.new("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 110, Range = 34, Brightness = 1.6, Color = K.C(255, 220, 170), Shadows = false }, glow)
	return m
end
function K.tree(parent, pos, s, rng)
	s = s or 1
	local m = K.model(parent, "Tree")
	local h = 9 * s
	K.cyl(m, "Trunk", 1.7 * s, h, CFrame.new(pos + Vector3.new(0, h / 2, 0)), K.PAL.bark, Enum.Material.Wood)
	local greens = { K.PAL.leaf, K.PAL.leaf2, K.PAL.leaf3 }
	local r = rng or Random.new()
	for i = 1, 3 do
		local off = Vector3.new(r:NextNumber(-2.2, 2.2), h + r:NextNumber(0.5, 4.5), r:NextNumber(-2.2, 2.2)) * Vector3.new(s, 1, s)
		K.ball(m, "Leaves", r:NextNumber(8, 11.5) * s, pos + off, greens[i], Enum.Material.Grass, { CastShadow = i == 1 })
	end
	return m
end
function K.bench(parent, cf)
	local m = K.model(parent, "Bench")
	K.part(m, "Seat", Vector3.new(7, 0.4, 2), cf * CFrame.new(0, 1.6, 0), K.PAL.wood, Enum.Material.WoodPlanks)
	K.part(m, "Back", Vector3.new(7, 1.6, 0.4), cf * CFrame.new(0, 2.7, 0.9) * CFrame.Angles(math.rad(-8), 0, 0), K.PAL.wood, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -3, 3 }) do
		K.part(m, "Leg", Vector3.new(0.4, 1.6, 1.8), cf * CFrame.new(x, 0.8, 0), K.PAL.steelDark, Enum.Material.Metal)
	end
	return m
end
-- a chain-link style fence run from a to b (posts + two rails + a see-through panel)
function K.fence(parent, a, b, h, color)
	h = h or 5
	local d = b - a
	local n = math.max(1, math.floor(d.Magnitude / 8 + 0.5))
	local dir = d.Unit
	local cf = CFrame.lookAt((a + b) / 2, b) 
	for i = 0, n do
		K.cyl(parent, "Post", 0.5, h, CFrame.new(a + dir * (d.Magnitude * i / n) + Vector3.new(0, h / 2, 0)), color or K.PAL.steel, Enum.Material.Metal)
	end
	K.part(parent, "Rail", Vector3.new(0.25, 0.25, d.Magnitude), cf * CFrame.new(0, h - 0.2, 0), color or K.PAL.steel, Enum.Material.Metal)
	K.part(parent, "Mesh", Vector3.new(0.1, h - 0.6, d.Magnitude), cf * CFrame.new(0, h / 2, 0), K.C(150, 156, 166), Enum.Material.DiamondPlate, { Transparency = 0.55, CastShadow = false })
end
-- (2026-11-13) open test ground helpers ---------------------------------------------------------------------------
function K.station(model, cf, kind, every, max, extra)
	local attrs = { Kind = kind or "stand", Every = every or 8, Max = max or 1 }
	for k, v in pairs(extra or {}) do
		attrs[k] = v
	end
	return K.part(model, "Station", Vector3.new(2, 0.2, 2), cf, nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = "DummyStation", attrs = attrs })
end
-- an invisible marker / zone
function K.zone(model, name, size, cf, tag, attrs)
	return K.part(model, name, size, cf, nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, tag = tag, attrs = attrs })
end
-- the big red floor button every machine uses: a ProximityPrompt on the dome, a Lamp ring the server can light.
-- cf sits on the ground. Returns the dome (it carries the tag + attributes).
function K.button(model, cf, tag, action, object, attrs, color)
	K.cyl(model, "ButtonBase", 5.2, 0.7, cf * CFrame.new(0, 0.35, 0), K.C(198, 196, 190), Enum.Material.Concrete)
	K.cyl(model, "ButtonRing", 4, 0.5, cf * CFrame.new(0, 0.95, 0), K.C(112, 114, 122), Enum.Material.Metal)
	local dome = K.cyl(model, "Button", 3.3, 0.9, cf * CFrame.new(0, 1.5, 0), color or K.C(214, 40, 36), Enum.Material.SmoothPlastic, { tag = tag, attrs = attrs })
	K.cyl(dome, "Lamp", 4.5, 0.22, cf * CFrame.new(0, 0.82, 0), K.C(60, 62, 70), Enum.Material.SmoothPlastic, { CastShadow = false, CanCollide = false })
	K.new("ProximityPrompt", { ActionText = action, ObjectText = object or "", HoldDuration = 0, MaxActivationDistance = 10, RequiresLineOfSight = false, KeyboardKeyCode = Enum.KeyCode.K }, dome)
	return dome
end
function K.danger(model, cf, text)
	-- (2026-11-13) the owner: "make sure that the legs dont go through the actual sign". The post was 4.4 tall under a
	-- plate whose underside is at 3.8, so it stood 0.6 up through the lettering. It stops at the underside now.
	K.cyl(model, "DangerPost", 0.35, 3.82, cf * CFrame.new(0, 1.91, 0), K.SIGN_BLACK, Enum.Material.Metal)
	local p = K.part(model, "DangerSign", Vector3.new(6, 1.8, 0.25), cf * CFrame.new(0, 4.7, 0), K.SIGN_BLACK, Enum.Material.SmoothPlastic)
	K.label(p, text or "DANGER", { pps = 30, strokeW = 0 })
	return p
end
function K.pine(parent, pos, s, rng)
	s = s or 1
	local m = K.model(parent, "Pine")
	K.cyl(m, "Trunk", 1.3 * s, 6 * s, CFrame.new(pos + Vector3.new(0, 3 * s, 0)), K.PAL.bark, Enum.Material.Wood)
	local greens = { K.C(46, 92, 60), K.C(54, 104, 66), K.C(40, 84, 56) }
	for i = 0, 4 do
		K.cyl(m, "Tier", (10 - i * 2) * s, 3.2 * s, CFrame.new(pos + Vector3.new(0, (5 + i * 2.9) * s, 0)), greens[i % 3 + 1], Enum.Material.Grass, { CastShadow = i == 0 })
	end
	return m
end
-- GROUND LEVEL (2026-11-13, measured): smooth terrain's surface rides HALF A CELL (2 studs) above a FillBlock whose top
-- is on the 4-stud grid, so a slab filled up to y 0 puts the ground at y 2 and buries the bottom of every part (the
-- first map had exactly that). The base slab is therefore filled up to y -2 (surface at 0.0) and a paint may only
-- touch y -6 .. -2. Use FillBlock for paint: FillCylinder fills the top cell completely and raises a 2-stud plateau.
function K.ground(cf, size, mat)
	workspace.Terrain:FillBlock(cf * CFrame.new(0, -4, 0), Vector3.new(size.X, 4, size.Z), mat or Enum.Material.Pavement)
end
function K.groundDisc(pos, radius, mat) -- three crossed slabs = a hexagon
	for i = 0, 2 do
		workspace.Terrain:FillBlock(CFrame.new(pos.X, -4, pos.Z) * CFrame.Angles(0, i * math.pi / 3, 0), Vector3.new(radius * 1.74, 4, radius), mat or Enum.Material.Pavement)
	end
end
-- where the terrain (or water) surface really is under a point
function K.surface(pos)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(pos.X, 80, pos.Z), Vector3.new(0, -200, 0), rp)
	return hit and hit.Position.Y or nil
end
function K.weld(a, b)
	return K.new("WeldConstraint", { Part0 = a, Part1 = b }, b)
end
return K
