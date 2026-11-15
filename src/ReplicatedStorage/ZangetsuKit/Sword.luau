--!nocheck
-- ZangetsuKit.Sword: Ichigo's sword, both forms, and the Bankai coat, built INTO the character by the server
-- (CONTRACT.md section 3, DESIGN.md section 1). A plain module: no remotes, no player state; safe on server + clients.
--   Sword.attach(char, form?) -> Model?  SERVER. Idempotent (returns the live sword when Sword.get is valid), else
--                                        destroys stale ZangetsuSword / ZangetsuCoat and builds both; Shikai shown
--                                        (form = "Bankai" is an optional extra: build with Tensa Zangetsu shown)
--   Sword.detach(char)                   SERVER. Destroys ZangetsuSword + ZangetsuCoat; clears SwordForm
--   Sword.setForm(char, form)            shows one form (Transparency = BaseT), hides the other, the coat with Bankai,
--                                        moves the Handle attachments, sets SwordForm. Never touches Handle / Motor6D
--   Sword.get(char) -> info?             { model, handle, motor, form, blade, parts, base, mid, tip, trailA, trailB, coat }
--   Sword.form(char), Sword.tip(char), Sword.base(char), Sword.dir(char), Sword.build(form?) -> unparented model
-- Handle frame: +Y toward the tip, +Z the cutting-edge side, X the flats. s = studs from the grip point G (the fist
-- centre) along the blade; Handle y = s - 0.30. The Motor6D "SwordGrip" (Part0 RightHand, Part1 Handle, C0/C1 =
-- Sword.GRIP) is made once per attach and never replaced (ProceduralAnimator caches joints per character).
-- The hilt runs from the pommel (s -0.62, just out of the little-finger side of the fist) to the blade root (0.75),
-- so a fist holding it at 80-100 degrees (every clip's grip) shows hilt on BOTH sides of the hand.
local Sword = {}

Sword.FORMS = { "Shikai", "Bankai" }
Sword.GRIP = {
	point = Vector3.new(0, -0.12, 0), handleY = -0.30,
	c0 = CFrame.new(0, -0.12, 0) * CFrame.Angles(math.pi, 0, 0), c1 = CFrame.new(0, -0.30, 0),
}
Sword.LEN = { Shikai = { root = 0.75, tip = 4.95 }, Bankai = { root = 0.74, tip = 4.34 } }
Sword.POMMEL = { Shikai = -0.62, Bankai = -0.64 }

-- Handle-local attachment positions per form (DESIGN 1.5)
local ATT = {
	Shikai = {
		Base = Vector3.new(0, 0.55, 0), Mid = Vector3.new(0, 2.40, 0), Tip = Vector3.new(0, 4.65, 0),
		TrailA = Vector3.new(0, 0.70, 0.30), TrailB = Vector3.new(0, 4.50, 0.30),
	},
	Bankai = {
		Base = Vector3.new(0, 0.50, 0), Mid = Vector3.new(0, 2.25, 0), Tip = Vector3.new(0, 4.04, 0),
		TrailA = Vector3.new(0, 0.60, 0.08), TrailB = Vector3.new(0, 3.95, 0.08),
	},
}
Sword.ATT = ATT

local C = Color3.fromRGB
local PAL = {
	Steel = C(52, 54, 60), SteelDark = C(30, 32, 36), Edge = C(225, 230, 240), Cloth = C(238, 234, 224),
	ClothShade = C(205, 200, 190), Tensa = C(16, 14, 18), TensaEdge = C(200, 205, 215), Guard = C(35, 35, 40),
	Chain = C(92, 94, 102), Coat = C(18, 16, 20), Lining = C(150, 10, 24), Blood = C(110, 0, 18),
}
local COLLAR = C(70, 72, 78)
local BK_HILT = C(20, 18, 22)
PAL.BkHilt = BK_HILT
-- PERKS (2026-11-07, kitsE): the Fighter Skins perk's "WHITE BANKAI" - Config.SkinAlt.Palette (Config.Skin) over PAL.
-- Every Bankai-form / coat part built from a PAL colour is tagged PalKey = that key; Sword.applySkin recolours them
local ALT = {}
local SKIN_KEYS = {
	Bankai = { "Tensa", "TensaEdge", "Guard", "Chain", "Blood", "BkHilt" },
	Coat = { "Coat", "Lining" },
}
do
	local mod = script.Parent and script.Parent:FindFirstChild("Config")
	if mod and mod:IsA("ModuleScript") then
		local ok, cfg = pcall(require, mod)
		if ok and type(cfg) == "table" and type(cfg.Palette) == "table" then
			for k, v in pairs(cfg.Palette) do
				if PAL[k] and typeof(v) == "Color3" then
					PAL[k] = v
				end
			end
		end
		for k, v in pairs(PAL) do
			ALT[k] = v
		end
		local alt = ok and type(cfg) == "table" and type(cfg.SkinAlt) == "table" and cfg.SkinAlt.Palette
		if type(alt) == "table" then
			for k, v in pairs(alt) do
				if PAL[k] and typeof(v) == "Color3" then
					ALT[k] = v
				end
			end
		end
	end
end
Sword.PAL, Sword.ALT = PAL, ALT
-- the PAL key whose colour this is, out of one builder's keys (nil for anything else)
local function keyOf(color, keys)
	for _, k in ipairs(keys) do
		if PAL[k] == color then
			return k
		end
	end
	return nil
end

local rad = math.rad
local V = Vector3.new
local FABRIC, METAL, PLASTIC = Enum.Material.Fabric, Enum.Material.Metal, Enum.Material.SmoothPlastic
local GRIP_Y = Sword.GRIP.handleY
local function Y(s)
	return s + GRIP_Y
end

local function newPart(class, name, size, mat, color, refl)
	local p = Instance.new(class)
	p.Name = name
	p.Size = size
	p.Material = mat
	p.Color = color
	p.Reflectance = refl or 0
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- a part welded to `to` at `cf` (to-local). BaseT = its shown transparency; hidden parts sit at 1
local function weldPart(parent, to, class, name, size, cf, mat, color, refl, hidden)
	local p = newPart(class, name, size, mat, color, refl)
	p:SetAttribute("BaseT", 0)
	p.Transparency = hidden and 1 or 0
	p.CFrame = to.CFrame * cf
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = cf
	w.Parent = p
	p.Parent = parent
	return p
end

-- a strip lying along the line a -> b in the Handle's YZ plane (a sloped tip edge)
local function along(a, b)
	local d = b - a
	return CFrame.fromMatrix((a + b) / 2, Vector3.xAxis, Vector3.xAxis:Cross(d.Unit)), d.Magnitude
end

---------------------------------------------------------------------------------------------------
-- Shikai: ZANGETSU - a man-sized cleaver, no guard, white cloth hilt with a trailing tail
local function buildShikai(fm, h, hidden)
	local function add(class, name, size, cf, mat, color, refl)
		return weldPart(fm, h, class, name, size, cf, mat, color, refl, hidden)
	end
	local PY = Sword.POMMEL.Shikai
	add("Part", "Hilt", V(0.24, 0.75 - PY, 0.24), CFrame.new(0, Y((0.75 + PY) / 2), 0), FABRIC, PAL.Cloth)
	for i, s in ipairs({ -0.50, 0.05, 0.30, 0.55 }) do
		local roll = (i % 2 == 0) and 25 or -25
		add("Part", "Wrap" .. i, V(0.27, 0.07, 0.27), CFrame.new(0, Y(s), 0) * CFrame.Angles(rad(roll), 0, 0), FABRIC, PAL.ClothShade)
	end
	add("Part", "Cap", V(0.27, 0.06, 0.27), CFrame.new(0, Y(PY - 0.01), 0), FABRIC, PAL.ClothShade)
	-- the cloth tail off the pommel: down-back toward the spine side, angled out
	local top = V(0, Y(PY), 0)
	local r1 = CFrame.Angles(rad(35), 0, rad(15))
	local d1 = r1:VectorToWorldSpace(V(0, -1, 0))
	add("Part", "Tail1", V(0.05, 0.85, 0.16), CFrame.new(top + d1 * 0.425) * r1, FABRIC, PAL.Cloth)
	local top2 = top + d1 * 0.82
	local r2 = CFrame.Angles(rad(55), 0, rad(15))
	local d2 = r2:VectorToWorldSpace(V(0, -1, 0))
	add("Part", "Tail2", V(0.05, 0.70, 0.14), CFrame.new(top2 + d2 * 0.35) * r2, FABRIC, PAL.Cloth)
	add("Part", "Collar", V(0.20, 0.10, 1.00), CFrame.new(0, Y(0.78), 0), METAL, COLLAR)
	add("Part", "Blade", V(0.12, 3.70, 0.98), CFrame.new(0, Y(2.60), 0.02), METAL, PAL.Steel, 0.15)
	-- the point is on the spine side: a wedge turned 180 degrees about Y (its full-height face to -Z)
	add("WedgePart", "Tip", V(0.12, 0.50, 0.98), CFrame.new(0, Y(4.70), 0.02) * CFrame.Angles(0, math.pi, 0), METAL, PAL.Steel, 0.15)
	-- the silver edge, a hair thicker than the blade so it reads on both flats, and its run up the slope to the point
	add("Part", "Edge", V(0.13, 3.60, 0.12), CFrame.new(0, Y(2.62), 0.50), METAL, PAL.Edge, 0.35)
	local cf, len = along(V(0, Y(4.45), 0.51), V(0, Y(4.95), -0.47))
	add("Part", "TipEdge", V(0.13, 0.08, len), cf, METAL, PAL.Edge, 0.35)
	add("Part", "Spine", V(0.15, 3.90, 0.06), CFrame.new(0, Y(2.70), -0.47), METAL, PAL.SteelDark)
end

---------------------------------------------------------------------------------------------------
-- Bankai: TENSA ZANGETSU - a slim black daikatana, manji guard, a short chain off the pommel
local function buildBankai(fm, h, hidden)
	local function add(class, name, size, cf, mat, color, refl)
		local p = weldPart(fm, h, class, name, size, cf, mat, color, refl, hidden)
		local key = keyOf(color, SKIN_KEYS.Bankai)
		if key then
			p:SetAttribute("PalKey", key)
		end
		return p
	end
	local PY = Sword.POMMEL.Bankai
	add("Part", "Hilt", V(0.20, 0.67 - (PY + 0.04), 0.20), CFrame.new(0, Y((0.67 + PY + 0.04) / 2), 0), FABRIC, PAL.BkHilt)
	for i, s in ipairs({ -0.42, 0.02, 0.26, 0.50 }) do
		local roll = (i % 2 == 0) and 25 or -25
		add("Part", "Wrap" .. i, V(0.23, 0.06, 0.23), CFrame.new(0, Y(s), 0) * CFrame.Angles(rad(roll), 0, 0), FABRIC, PAL.Blood)
	end
	add("Part", "Pommel", V(0.26, 0.08, 0.26), CFrame.new(0, Y(PY), 0), METAL, PAL.Guard, 0.2)
	-- the manji guard in the Handle XZ plane at s 0.70: a centre, four arms, four hooks turning the same way
	local gy = Y(0.70)
	add("Part", "GuardCore", V(0.16, 0.10, 0.16), CFrame.new(0, gy, 0), METAL, PAL.Guard, 0.2)
	for i = 0, 3 do
		local turn = CFrame.Angles(0, -i * math.pi / 2, 0) -- +X, +Z, -X, -Z
		local arm = turn:VectorToWorldSpace(Vector3.xAxis)
		local hook = turn:VectorToWorldSpace(Vector3.zAxis) -- 90 degrees on from the arm, the same way round each time
		add("Part", "GuardArm" .. (i + 1), V(0.42, 0.08, 0.10), CFrame.new(V(0, gy, 0) + arm * 0.21) * turn, METAL, PAL.Guard, 0.2)
		add("Part", "GuardHook" .. (i + 1), V(0.10, 0.08, 0.24), CFrame.new(V(0, gy, 0) + arm * 0.37 + hook * 0.12) * turn, METAL, PAL.Guard, 0.2)
	end
	add("Part", "Blade", V(0.06, 3.40, 0.26), CFrame.new(0, Y(2.44), 0), METAL, PAL.Tensa, 0.25)
	add("Part", "Edge", V(0.065, 3.35, 0.06), CFrame.new(0, Y(2.42), 0.13), METAL, PAL.TensaEdge, 0.3)
	add("WedgePart", "Tip", V(0.06, 0.20, 0.26), CFrame.new(0, Y(4.24), 0) * CFrame.Angles(0, math.pi, 0), METAL, PAL.Tensa, 0.25)
	local cf, len = along(V(0, Y(4.14), 0.13), V(0, Y(4.34), -0.13))
	add("Part", "TipEdge", V(0.065, 0.04, len), cf, METAL, PAL.TensaEdge, 0.3)
	-- the chain: rigid links off the pommel, curling toward the EDGE side (the carry holds the edge down, so it hangs)
	local p = V(0, Y(PY - 0.05), 0)
	local ang = 0
	for i = 1, 6 do
		ang += rad(13)
		local d = V(0, -math.cos(ang), math.sin(ang))
		local c = p + d * 0.065
		local link = CFrame.fromMatrix(c, Vector3.xAxis, d)
		if i % 2 == 0 then
			link = link * CFrame.Angles(0, math.pi / 2, 0)
		end
		add("Part", "Chain" .. i, V(0.07, 0.16, 0.12), link, METAL, PAL.Chain, 0.2)
		p += d * 0.13
	end
end

---------------------------------------------------------------------------------------------------
-- the Bankai coat: long black open coat, crimson lining, back tails (no front flaps). Sized off the live torso
local function buildCoat(ut, lt, hidden)
	local coat = Instance.new("Model")
	coat.Name = "ZangetsuCoat"
	local function add(to, class, name, size, cf, color)
		local p = weldPart(coat, to, class, name, size, cf, FABRIC, color, 0, hidden)
		local key = keyOf(color, SKIN_KEYS.Coat)
		if key then
			p:SetAttribute("PalKey", key)
		end
		return p
	end
	local ux, uy, uz = ut.Size.X, ut.Size.Y, ut.Size.Z
	add(ut, "Part", "Back", V(ux * 1.057, uy * 1.03, 0.08), CFrame.new(0, 0, uz / 2 + 0.04), PAL.Coat)
	add(ut, "Part", "NeckCollar", V(ux * 0.55, 0.36, 0.08), CFrame.new(0, uy / 2 + 0.12, uz / 2 + 0.02) * CFrame.Angles(rad(-14), 0, 0), PAL.Coat)
	for _, sx in ipairs({ 1, -1 }) do
		local side = sx > 0 and "R" or "L"
		add(ut, "Part", "Shoulder" .. side, V(ux * 0.49, 0.10, uz * 1.10), CFrame.new(sx * ux * 0.258, uy / 2 + 0.03, 0), PAL.Coat)
		add(ut, "Part", "Lapel" .. side, V(ux * 0.216, uy, 0.08), CFrame.new(sx * ux * 0.402, 0, -(uz / 2 + 0.04)), PAL.Coat)
		add(ut, "Part", "Lining" .. side, V(0.10, uy * 0.988, 0.09), CFrame.new(sx * ux * 0.309, 0, -(uz / 2 + 0.05)), PAL.Lining)
	end
	local lx, ly, lz = lt.Size.X, lt.Size.Y, lt.Size.Z
	-- tails hang from the LowerTorso top, flared back so a rear leg clears them; short enough to clear a crouch
	local function tail(name, w, hgt, top, rx, rz)
		local cf = CFrame.new(top) * CFrame.Angles(rad(rx), 0, rad(rz)) * CFrame.new(0, -hgt / 2, 0)
		add(lt, "Part", name, V(w, hgt, 0.07), cf, PAL.Coat)
		add(lt, "Part", name .. "Lining", V(w - 0.1, hgt - 0.1, 0.02), cf * CFrame.new(0, 0.03, -0.045), PAL.Lining)
		for i = 1, 3 do
			local hh = 0.12 + ((i * 37) % 10) / 100
			local x = -w / 2 + w * (i - 0.5) / 3
			local vx = (i % 2 == 0) and Vector3.zAxis or -Vector3.zAxis
			local wcf = cf * CFrame.fromMatrix(V(x, -hgt / 2 - hh / 2 + 0.01, 0), vx, -Vector3.yAxis)
			add(lt, "WedgePart", name .. "Hem" .. i, V(0.07, hh, w / 3 * 0.95), wcf, PAL.Coat)
		end
	end
	tail("TailBack", lx * 0.60, 1.95, V(0, ly / 2, lz / 2 + 0.06), -12, 0)
	tail("TailR", lx * 0.35, 1.85, V(lx * 0.427, ly / 2, lz * 0.30), -14, 12)
	tail("TailL", lx * 0.35, 1.85, V(-lx * 0.427, ly / 2, lz * 0.30), -14, -12)
	return coat
end

---------------------------------------------------------------------------------------------------
-- API

local partsCache = setmetatable({}, { __mode = "k" }) -- [form Model] = { visible BaseParts }

function Sword.form(char)
	local f = typeof(char) == "Instance" and char:GetAttribute("SwordForm")
	if f == "Shikai" or f == "Bankai" then
		return f
	end
	return nil
end

function Sword.build(form)
	form = (form == "Bankai") and "Bankai" or "Shikai"
	local model = Instance.new("Model")
	model.Name = "ZangetsuSword"
	local h = newPart("Part", "Handle", Vector3.one * 0.2, PLASTIC, Color3.new(1, 1, 1))
	h.Transparency = 1
	h:SetAttribute("BaseT", 1)
	h.CFrame = CFrame.identity
	h.Parent = model
	model.PrimaryPart = h
	for name, pos in pairs(ATT[form]) do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = h
	end
	local sk = Instance.new("Model")
	sk.Name = "Shikai"
	sk.Parent = model
	buildShikai(sk, h, form ~= "Shikai")
	local bk = Instance.new("Model")
	bk.Name = "Bankai"
	bk.Parent = model
	buildBankai(bk, h, form ~= "Bankai")
	return model
end

function Sword.get(char)
	if typeof(char) ~= "Instance" then
		return nil
	end
	local model = char:FindFirstChild("ZangetsuSword")
	local h = model and model:FindFirstChild("Handle")
	local motor = h and h:FindFirstChild("SwordGrip")
	local rh = char:FindFirstChild("RightHand")
	if not motor or not rh or motor.Part0 ~= rh then
		return nil
	end
	local form = Sword.form(char) or "Shikai"
	local fm = model:FindFirstChild(form)
	local parts = fm and partsCache[fm]
	if fm and not parts then
		parts = {}
		for _, d in ipairs(fm:GetDescendants()) do
			if d:IsA("BasePart") and (d:GetAttribute("BaseT") or 0) < 1 then
				table.insert(parts, d)
			end
		end
		partsCache[fm] = parts
	end
	return {
		model = model, handle = h, motor = motor, form = form,
		blade = fm and fm:FindFirstChild("Blade"), parts = parts or {},
		base = h:FindFirstChild("Base"), mid = h:FindFirstChild("Mid"), tip = h:FindFirstChild("Tip"),
		trailA = h:FindFirstChild("TrailA"), trailB = h:FindFirstChild("TrailB"),
		coat = char:FindFirstChild("ZangetsuCoat"),
	}
end

function Sword.tip(char)
	local i = Sword.get(char)
	return i and i.tip and i.tip.WorldPosition or nil
end

function Sword.base(char)
	local i = Sword.get(char)
	return i and i.base and i.base.WorldPosition or nil
end

function Sword.dir(char)
	local i = Sword.get(char)
	if not (i and i.tip and i.base) then
		return nil
	end
	local d = i.tip.WorldPosition - i.base.WorldPosition
	return d.Magnitude > 1e-4 and d.Unit or nil
end

-- PERKS: does this character's player wear the alt skin (attribute Skin == "Alt", written by ShopService)?
function Sword.skinAlt(char)
	local p = typeof(char) == "Instance" and game:GetService("Players"):GetPlayerFromCharacter(char)
	return p ~= nil and p:GetAttribute("Skin") == "Alt"
end

-- PERKS: recolour the Bankai blade + the coat for the skin (alt = nil -> read the player's Skin now). Cheap and
-- idempotent; setForm / attach call it, so the skin is read each time Tensa Zangetsu is shown
function Sword.applySkin(char, alt)
	if typeof(char) ~= "Instance" then
		return
	end
	if alt == nil then
		alt = Sword.skinAlt(char)
	end
	local pal = alt and ALT or PAL
	local model = char:FindFirstChild("ZangetsuSword")
	for _, root in ipairs({ model and model:FindFirstChild("Bankai"), char:FindFirstChild("ZangetsuCoat") }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				local key = d:IsA("BasePart") and d:GetAttribute("PalKey")
				local c = key and (pal[key] or PAL[key])
				if c and d.Color ~= c then
					d.Color = c
				end
			end
		end
	end
end

function Sword.setForm(char, form)
	if typeof(char) ~= "Instance" or (form ~= "Shikai" and form ~= "Bankai") then
		return
	end
	pcall(Sword.applySkin, char)
	local model = char:FindFirstChild("ZangetsuSword")
	if model then
		for _, name in ipairs(Sword.FORMS) do
			local fm = model:FindFirstChild(name)
			if fm then
				for _, d in ipairs(fm:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Transparency = (name == form) and (d:GetAttribute("BaseT") or 0) or 1
					end
				end
			end
		end
		local h = model:FindFirstChild("Handle")
		if h then
			for name, pos in pairs(ATT[form]) do
				local a = h:FindFirstChild(name)
				if a and a:IsA("Attachment") then
					a.Position = pos
				end
			end
		end
	end
	local coat = char:FindFirstChild("ZangetsuCoat")
	if coat then
		for _, d in ipairs(coat:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = (form == "Bankai") and (d:GetAttribute("BaseT") or 0) or 1
			end
		end
	end
	char:SetAttribute("SwordForm", form)
end

function Sword.attach(char, form)
	if typeof(char) ~= "Instance" then
		return nil
	end
	local live = Sword.get(char)
	if live then
		return live.model
	end
	local rh, ut, lt = char:FindFirstChild("RightHand"), char:FindFirstChild("UpperTorso"), char:FindFirstChild("LowerTorso")
	if not (rh and rh:IsA("BasePart") and ut and ut:IsA("BasePart") and lt and lt:IsA("BasePart")) then
		return nil
	end
	for _, c in ipairs(char:GetChildren()) do
		if c.Name == "ZangetsuSword" or c.Name == "ZangetsuCoat" then
			c:Destroy()
		end
	end
	form = (form == "Bankai") and "Bankai" or "Shikai"
	local model = Sword.build(form)
	local h = model.PrimaryPart
	model:PivotTo(rh.CFrame * Sword.GRIP.c0 * Sword.GRIP.c1:Inverse())
	local m = Instance.new("Motor6D")
	m.Name = "SwordGrip"
	m.Part0 = rh
	m.Part1 = h
	m.C0 = Sword.GRIP.c0
	m.C1 = Sword.GRIP.c1
	m.Parent = h
	model.Parent = char
	local coat = buildCoat(ut, lt, form ~= "Bankai")
	coat.Parent = char
	pcall(Sword.applySkin, char)
	char:SetAttribute("SwordForm", form)
	return model
end

function Sword.detach(char)
	if typeof(char) ~= "Instance" then
		return
	end
	for _, c in ipairs(char:GetChildren()) do
		if c.Name == "ZangetsuSword" or c.Name == "ZangetsuCoat" then
			c:Destroy()
		end
	end
	char:SetAttribute("SwordForm", nil)
end

return Sword
