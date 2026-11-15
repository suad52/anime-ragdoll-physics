--!nocheck
-- ZangetsuKit.Client.Shared: the pure effect builders of the Zangetsu (Ichigo) kit (DESIGN.md section 3, CONTRACT.md
-- section 6). No input, HUD, camera or movement state lives here: every function draws something in the world and
-- cleans itself up. One-shots die through Debris / tweens / one short Heartbeat driver; persistent pieces (Crescent,
-- Line, Pillar, bladeTrail, bladeGlow, aura, eyes, steam) return a handle. Everything is client-side, anchored
-- (shards and the copied dust aside), non-colliding, non-querying, CastShadow false, parented under the caller's
-- folder (nil -> S.Folder -> workspace.LocalFX.Zangetsu). Nothing errors on a missing character / sword / ground: a
-- builder returns nil or a dummy handle whose methods are no-ops (h.dead == true).
-- Handle lifetimes: one-shots and cast pieces stop themselves after 8 s at most. The character-bound handles (aura,
-- bladeGlow, eyes) stop 6.8 s after they were made OR last given :set() / :keep() (o.life changes it; their fade-out
-- ends by 8 s), so a mode that re-sets them every frame keeps them alive and a forgotten one still dies.
-- Colours default to Config.Palette. o.black = true is the Bankai / hollow look: dark NON-additive parts
-- (SmoothPlastic Black) and LightEmission-0 smoke with Crimson additive accents (DESIGN section 2 BLACK RULE).
-- "alpha" in every signature here means TRANSPARENCY (0 = solid, 1 = gone), like GojoFX / the Deku kit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("ZangetsuKit")
local FX = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("GojoFX"))
local CFG = {}
do
	local m = Kit:WaitForChild("Config", 10)
	if m then
		local ok, c = pcall(require, m)
		if ok and type(c) == "table" then
			CFG = c
		end
	end
end

local C = Color3.fromRGB
-- DESIGN section 2 palette (a copy of the base Config.Palette); Config.Palette overrides every entry it has
local PAL = {
	Core = C(240, 250, 255), Reiatsu = C(150, 215, 255), Ice = C(80, 160, 255), Frost = C(205, 235, 255),
	Black = C(14, 10, 14), Crimson = C(220, 20, 40), Ember = C(255, 90, 60), Blood = C(110, 0, 18), Smoke = C(36, 30, 34),
	Hollow = C(255, 34, 34), HollowDark = C(28, 0, 6), Bone = C(245, 242, 232), EyeGold = C(255, 214, 40),
	Steel = C(52, 54, 60), SteelDark = C(30, 32, 36), Edge = C(225, 230, 240), Cloth = C(238, 234, 224),
	ClothShade = C(205, 200, 190), Tensa = C(16, 14, 18), TensaEdge = C(200, 205, 215), Guard = C(35, 35, 40),
	Chain = C(92, 94, 102), Coat = C(18, 16, 20), Lining = C(150, 10, 24), Robe = C(20, 20, 26), Dust = C(150, 140, 125),
	Steam = C(236, 236, 236),
}
if type(CFG.Palette) == "table" then
	for k, v in pairs(CFG.Palette) do
		PAL[k] = v
	end
end

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local rng = Random.new()
local cs, nsk, TEX = FX.cs, FX.nsk, FX.TEX
local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local NEON, PLASTIC, FIELD = Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.ForceField
local BULK = Enum.BulkMoveMode.FireCFrameChanged
-- Studio's built-in particle sheets (fire_main is already used by PurpleVFX / FxLib / KitServer in this place)
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local FLARE = "rbxasset://textures/particles/fire_sparks_main.dds"
local MAX_LIFE = 8

local S = {}
S.FX, S.CFG, S.PAL = FX, CFG, PAL
S.TEX = { fire = FIRE, flare = FLARE, glow = TEX.glow, ring = TEX.ring, star = TEX.star, smoke = TEX.smoke }
S.LIMBS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
S.Folder = nil -- the scaffold sets it (workspace.LocalFX.Zangetsu)

-- the Sword module (sword-m1): required without blocking the scaffold; picked up later if it appears late
S.Sword = nil
do
	local function load(m)
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" then
			S.Sword = mod
		end
	end
	local m = Kit:FindFirstChild("Sword")
	if m then
		load(m)
	else
		task.spawn(function()
			local m2 = Kit:WaitForChild("Sword", 60)
			if m2 and not S.Sword then
				load(m2)
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- small helpers

local function now()
	return workspace:GetServerTimeNow()
end
local function live(x)
	return typeof(x) == "Instance" and x.Parent ~= nil
end
local function vec(p)
	local t = typeof(p)
	if t == "Vector3" then
		return p
	elseif t == "CFrame" then
		return p.Position
	elseif t == "Instance" and p:IsA("BasePart") then
		return p.Position
	elseif t == "Instance" and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end
local function camCF()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame or CFrame.new()
end
local function camDist(p)
	p = vec(p)
	return p and (camCF().Position - p).Magnitude or math.huge
end
local function flat(v, fallback)
	if typeof(v) ~= "Vector3" then
		return fallback
	end
	local f = v * FLAT
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	return fallback
end
local function unit(v, fallback)
	if typeof(v) == "Vector3" and v.Magnitude > 1e-4 then
		return v.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end
local function lookAlong(p, dir)
	dir = unit(dir)
	return CFrame.lookAt(p, p + dir, math.abs(dir.Y) > 0.98 and Vector3.xAxis or UP)
end
local function camFacing(p)
	p = vec(p) or Vector3.zero
	return unit(camCF().Position - p, UP)
end
local function torsoOf(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	if model:IsA("BasePart") then
		return model
	end
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
end
local function tseq(list) -- a transparency NumberSequence from { {t, v}, ... } (values clamped 0..1)
	local k = {}
	for i, v in ipairs(list) do
		k[i] = NumberSequenceKeypoint.new(v[1], math.clamp(v[2], 0, 1))
	end
	return NumberSequence.new(k)
end
-- a flame colour ramp: hot c0 at birth, c1 through the body, a deeper c1 as it dies (reads as fire, not white smoke)
local function flameSeq(c0, c1)
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, c0), ColorSequenceKeypoint.new(0.35, c1),
		ColorSequenceKeypoint.new(1, c1:Lerp(Color3.new(0, 0.1, 0.35), 0.35)) })
end
local function lum(c)
	return c.R * 0.3 + c.G * 0.59 + c.B * 0.11
end
local function tween(inst, t, props, style, dir, delay)
	local tw = TweenService:Create(inst, TweenInfo.new(math.max(t, 0.01), style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tw:Play()
	return tw
end
local function newPart(name, material, color, size, cf, t, parent, shape)
	local p = FX.part(name, shape or BLOCK, material, color, nil)
	p.Size = size
	if cf then
		p.CFrame = cf
	end
	p.Transparency = t or 0
	if parent then
		p.Parent = parent
	end
	return p
end

-- the kit's own FX folder (the scaffold makes workspace.LocalFX.Zangetsu and sets S.Folder)
local function kitFolder()
	if live(S.Folder) then
		return S.Folder
	end
	local lfx = workspace:FindFirstChild("LocalFX")
	local f = lfx and lfx:FindFirstChild("Zangetsu")
	if f then
		S.Folder = f
		return f
	end
	return lfx or workspace
end
local function parentOf(f)
	if live(f) then
		return f
	end
	return kitFolder()
end

-- a handle whose methods are no-ops (every builder returns one of these when it has nothing to draw on)
local function noop() end
local function dummy(fields)
	local h = fields or {}
	h.dead = true
	h.parts = h.parts or {}
	for _, k in ipairs({ "Destroy", "destroy", "stop", "set", "keep", "fade", "setAlpha", "shatter", "place", "split",
		"erupt", "dissolve", "Emit", "emit", "setRate", "kill" }) do
		h[k] = noop
	end
	return h
end
S.dummy = dummy

-- the live sword of a character (Sword.get), or nil. Without the Sword module (a harness, or before it loads) it
-- reads the ZangetsuSword model by its contract names.
local function swordOf(char)
	if typeof(char) ~= "Instance" then
		return nil
	end
	local Sw = S.Sword
	if Sw and type(Sw.get) == "function" then
		local ok, info = pcall(Sw.get, char)
		if ok and type(info) == "table" and live(info.handle) then
			return info
		end
		return nil
	end
	local model = char:FindFirstChild("ZangetsuSword")
	local handle = model and model:FindFirstChild("Handle")
	if not handle then
		return nil
	end
	local form = char:GetAttribute("SwordForm") or "Shikai"
	local fm = model:FindFirstChild(form)
	local parts = {}
	if fm then
		for _, d in ipairs(fm:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 0.9 then
				table.insert(parts, d)
			end
		end
	end
	return {
		model = model, handle = handle, motor = handle:FindFirstChild("SwordGrip"), form = form,
		blade = fm and fm:FindFirstChild("Blade"), parts = parts, base = handle:FindFirstChild("Base"),
		mid = handle:FindFirstChild("Mid"), tip = handle:FindFirstChild("Tip"), trailA = handle:FindFirstChild("TrailA"),
		trailB = handle:FindFirstChild("TrailB"), coat = char:FindFirstChild("ZangetsuCoat"),
	}
end
local function edgeOf(info)
	for _, p in ipairs(info.parts or {}) do
		if p.Name == "Edge" and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end
local function hiddenPart(p) -- vanished (ctx.vanish / first person) or hidden by setForm
	return not live(p) or p.Transparency >= 0.9 or p.LocalTransparencyModifier > 0.5
end

S.now, S.camDist, S.flat, S.torsoOf, S.folder, S.camFacing = now, camDist, flat, torsoOf, kitFolder, camFacing
S.swordOf = swordOf

-- no white-outs: a glow is never bigger than its effect and shrinks when the camera is close to it
function S.glowFor(pos, size)
	return (size or 1) * math.clamp(camDist(pos) / 30, 0.45, 1)
end
-- camera-facing rings near the lens: clamp(dist / 30, 0.6, 1)
function S.ringScale(pos)
	return math.clamp(camDist(pos) / 30, 0.6, 1)
end

-- BaseParts under f (the part governor: optional layers are skipped past ~300)
function S.partCount(f)
	if not live(f) then
		return 0
	end
	local n = 0
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local function crowded(f, limit)
	return S.partCount(f) > (limit or 300)
end

-- a character-bound handle's life: dies `life` s after it was made or last kept
local function lifeClock(life)
	-- default 6.8 s: the fade-out after expiry (up to 1.2 s) still ends inside the 8 s budget
	local c = { life = math.clamp(life or (MAX_LIFE - 1.2), 0.1, 60) }
	c.untilT = os.clock() + c.life
	function c.keep()
		c.untilT = os.clock() + c.life
	end
	function c.expired()
		return os.clock() > c.untilT
	end
	return c
end

---------------------------------------------------------------------------------------------------
-- afterimages (Killua's ghost, via the Deku kit): a ForceField / dark copy of the current pose, the sword included.
-- Parts with Transparency >= 0.9 (the Handle, the hidden form, the hidden coat) are skipped; every clone gets
-- LocalTransparencyModifier 0 (a vanished / first-person body must not hand its LTM 1 to the copy). Parts smaller
-- than 0.3 on every axis (wrap bands, chain links, guard hooks) are skipped unless o.full - they never read at ghost
-- alpha and they are half the sword's part count.
local function ghostClones(char, full)
	local list = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Archivable then
			local s = d.Size
			if full or math.max(s.X, s.Y, s.Z) >= 0.3 then
				local ok, c = pcall(function()
					return d:Clone()
				end)
				if ok and c then
					for _, ch in ipairs(c:GetChildren()) do
						if not ch:IsA("DataModelMesh") then
							ch:Destroy()
						end
					end
					c.Anchored = true
					c.CanCollide = false
					c.CanQuery = false
					c.CanTouch = false
					c.CastShadow = false
					c.Massless = true
					c.LocalTransparencyModifier = 0
					table.insert(list, { c = c, d = d })
				end
			end
		end
	end
	return list
end
local function buildGhost(char, delta, color, alpha, life, black, full)
	local f = Instance.new("Folder")
	f.Name = "ZangetsuGhost"
	local list = ghostClones(char, full)
	if #list == 0 then
		return nil
	end
	local parts = {}
	for _, it in ipairs(list) do
		local c, d = it.c, it.d
		if black then
			if d.Name == "Edge" then
				-- the blade edge stays lit: a crimson rim on the dark copy
				c.Material = NEON
				c.Color = color
				c.Transparency = math.min(alpha * 0.6, 0.9)
			else
				c.Material = PLASTIC
				c.Color = PAL.Black
				c.Reflectance = 0
				c.Transparency = alpha
				pcall(function()
					if c:IsA("MeshPart") then
						c.TextureID = ""
					end
				end)
				local mesh = c:FindFirstChildWhichIsA("SpecialMesh")
				if mesh then
					pcall(function()
						mesh.TextureId = ""
						mesh.VertexColor = Vector3.new(0.06, 0.04, 0.06)
					end)
				end
			end
		else
			c.Material = FIELD
			c.Color = color
			c.Transparency = alpha
		end
		c.CFrame = delta and (delta * d.CFrame) or d.CFrame
		c.Parent = f
		table.insert(parts, c)
	end
	f.Parent = kitFolder()
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, c in ipairs(parts) do
		TweenService:Create(c, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(f, life + 0.1)
	return f
end

-- S.ghost(char, color, alpha, life, offset?, o?) -> Folder. offset: a Vector3 shifts the copy; a CFrame is applied
-- as a WORLD delta (copy.CFrame = offset * part.CFrame - build it as CFrame.new(p) * rot * CFrame.new(-p) to turn
-- it about p). o = { black = false, full = false } (black: the dark SmoothPlastic copy with a `color` edge).
function S.ghost(char, color, alpha, life, offset, o)
	if typeof(char) ~= "Instance" or not char.Parent then
		return nil
	end
	o = o or {}
	local black = o.black == true
	color = color or (black and PAL.Crimson or PAL.Frost)
	alpha = math.clamp(alpha or 0.5, 0, 1)
	life = math.clamp(life or 0.3, 0.05, MAX_LIFE)
	local delta
	if typeof(offset) == "Vector3" then
		delta = CFrame.new(offset)
	elseif typeof(offset) == "CFrame" then
		delta = offset
	end
	local ok, f = pcall(buildGhost, char, delta, color, alpha, life, black, o.full == true)
	return ok and f or nil
end

-- S.ghostAt(char, rootCF, color, alpha, life, o?) -> Folder: the current pose re-rooted so its HRP sits at rootCF
-- (a Vector3 keeps the current facing). o = { black = false, full = false }.
function S.ghostAt(char, rootCF, color, alpha, life, o)
	if typeof(char) ~= "Instance" or not char.Parent then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	if typeof(rootCF) == "Vector3" then
		rootCF = CFrame.new(rootCF) * hrp.CFrame.Rotation
	end
	if typeof(rootCF) ~= "CFrame" then
		return nil
	end
	return S.ghost(char, color, alpha, life, rootCF * hrp.CFrame:Inverse(), o)
end

-- a short reiatsu arc jumping between two random limbs (GodspeedClient's bodyArc)
function S.bodyArc(f, model, color, width)
	if typeof(model) ~= "Instance" then
		return
	end
	local fp = parentOf(f)
	local LIMBS = S.LIMBS
	local a = model:FindFirstChild(LIMBS[rng:NextInteger(1, #LIMBS)])
	local b = model:FindFirstChild(LIMBS[rng:NextInteger(1, #LIMBS)])
	if a and b and a ~= b and a:IsA("BasePart") and b:IsA("BasePart") then
		FX.bolt(fp, a.Position + FX.randUnit() * 0.5, b.Position + FX.randUnit() * 0.5, {
			color = color or PAL.Reiatsu, width = width or 0.06, jag = 0.35, segments = 4, life = 0.09, restrike = 1,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- slashArc(f, cf, radius, o) -> Folder: the arc a swing leaves. Points cf * (sin(a)*R, 0, -cos(a)*R) for a from
-- -sweep/2 to +sweep/2 (cf's -X side, through cf.LookVector, to its +X side). Drawn tip to tip over o.draw, then
-- thins and fades over o.life (the tail first). The band is widest about 60% along (just behind the blade) and
-- tapers to points at both ends. Layers: 1 hot core, 2 + a coloured sheath (black: a crimson rim on the outer
-- edge), 3 + a ForceField haze. A glint flares at the leading tip when the draw lands (o.glint = false: none).
-- o = { sweep = 150, width = 0.7, thick = 0.12, core, edge, draw = 0.06, life = 0.3, layers = 2, black = false,
--       glint = true, smear = true (a faint motion smear inside the tip path; black: a dark smoke smear) }
local function arcProfile(u)
	u = math.clamp(u, 0, 1)
	return math.max(math.sin(math.pi * u ^ 1.35), 0) ^ 0.75
end
function S.slashArc(f, cf, radius, o)
	if typeof(cf) ~= "CFrame" then
		return nil
	end
	o = o or {}
	local fp = parentOf(f)
	local R = math.max(tonumber(radius) or 6, 0.5)
	local sweepDeg = math.clamp(o.sweep or 150, 10, 360)
	local sweep = math.rad(sweepDeg)
	local width = math.max(o.width or 0.7, 0.05)
	local thick = math.max(o.thick or 0.12, 0.02)
	local black = o.black == true
	local core = o.core or (black and PAL.Black or PAL.Core)
	local edge = o.edge or (black and PAL.Crimson or PAL.Reiatsu)
	local draw = math.max(o.draw or 0.06, 0)
	local life = math.clamp(o.life or 0.3, 0.05, 3)
	local layers = math.clamp(math.floor(o.layers or 2), 1, 3)
	local n = math.clamp(math.ceil(sweepDeg / 11), 10, 26)
	if crowded(fp, 300) then
		n = math.max(8, math.floor(n * 0.6))
		layers = 1
	end
	local folder = Instance.new("Folder")
	folder.Name = "SlashArc"
	local items = {}
	local function add(p, base, on, off, dur, thin)
		p.Transparency = 1
		p.Parent = folder
		table.insert(items, { p = p, base = base, on = on, off = off, dur = dur, size = p.Size, thin = thin, st = 0 })
	end
	local da = sweep / n
	for i = 1, n do
		local u = (i - 0.5) / n
		local a = -sweep / 2 + da * (i - 0.5)
		local w = width * math.max(arcProfile(u), 0.1)
		local radial = Vector3.new(math.sin(a), 0, -math.cos(a))
		local function seg(r, sx, sy, extra)
			local len = 2 * r * math.sin(da / 2) + extra
			return CFrame.fromMatrix(radial * r, radial, Vector3.yAxis), Vector3.new(sx, sy, len)
		end
		local on = (n > 1) and draw * (i - 1) / (n - 1) or 0
		local off = draw + 0.02 + life * 0.35 * u
		local dur = life * (0.55 + 0.45 * u)
		-- 1: the hot core, riding the tip path
		local lcf, size = seg(R - w * 0.25, w * 0.42, thick, w * 0.3 + 0.04)
		local coreCol = black and core or core:Lerp(edge, (1 - u) * 0.55)
		local p1 = newPart("ArcCore", black and PLASTIC or NEON, coreCol, size, cf * lcf, 1)
		add(p1, black and 0.04 or 0, on, off, dur, Vector3.new(0.15, 0.5, 1))
		if layers >= 2 then
			if black then
				-- the crimson rim along the outer edge
				local lcf2, size2 = seg(R + w * 0.02, math.max(w * 0.2, 0.05), thick * 1.35, w * 0.3 + 0.04)
				local p2 = newPart("ArcRim", NEON, edge, size2, cf * lcf2, 1)
				add(p2, 0.08, on, off, dur, Vector3.new(0.3, 0.5, 1))
			else
				local lcf2, size2 = seg(R - w * 0.45, w, thick * 0.6, w * 0.35 + 0.05)
				local p2 = newPart("ArcEdge", NEON, edge, size2, cf * lcf2, 1)
				add(p2, 0.42, on, off, dur * 0.9, Vector3.new(0.2, 0.6, 1))
			end
		end
		if o.smear ~= false and not black and layers >= 2 then
			-- the motion smear the blade sweeps inside its tip path (the anime swoosh), faint and gone first
			local sw = math.min(R * 0.45, 3.2) * math.max(arcProfile(u), 0.15) ^ 0.6
			local lcf4, size4 = seg(R - w * 0.3 - sw / 2, sw, thick * 0.3, sw * 0.12 + 0.05)
			local p4 = newPart("ArcSmear", NEON, edge:Lerp(core, 0.3), size4, cf * lcf4, 1)
			-- thinner still when the lens is right next to it (a ring round the caster passes close to his camera)
			add(p4, 0.8 + 0.15 * math.clamp(1 - camDist(p4.Position) / 12, 0, 1), on, math.max(on + 0.03, off * 0.7),
				dur * 0.55, Vector3.new(0.5, 1, 1))
		elseif o.smear ~= false and black and layers >= 2 then
			local sw = math.min(R * 0.4, 2.8) * math.max(arcProfile(u), 0.15) ^ 0.6
			local lcf4, size4 = seg(R - w * 0.3 - sw / 2, sw, thick * 0.3, sw * 0.12 + 0.05)
			local p4 = newPart("ArcSmear", PLASTIC, PAL.Smoke, size4, cf * lcf4, 1)
			add(p4, 0.72, on, math.max(on + 0.03, off * 0.7), dur * 0.55, Vector3.new(0.5, 1, 1))
		end
		if layers >= 3 then
			local lcf3, size3 = seg(R - w * 0.45, w * 1.7, thick * 0.4, w * 0.4 + 0.06)
			local p3 = newPart("ArcHaze", FIELD, edge, size3, cf * lcf3, 1)
			add(p3, black and 0.62 or 0.6, on, off, dur * 0.8, Vector3.new(0.4, 1, 1))
		end
	end
	folder.Parent = fp
	local total = draw + 0.02 + life * 1.35 + 0.05
	local t0 = os.clock()
	local glinted = o.glint == false
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > total or not folder.Parent then
			conn:Disconnect()
			folder:Destroy()
			return
		end
		if not glinted and t >= draw then
			glinted = true
			local tipP = cf * Vector3.new(math.sin(sweep / 2) * R, 0, -math.cos(sweep / 2) * R)
			FX.glow(fp, tipP, S.glowFor(tipP, width * 3.4), black and PAL.Crimson or PAL.Core, 0.14, { brightness = 2.2 })
			local tangent = cf:VectorToWorldSpace(Vector3.new(math.cos(sweep / 2), 0, math.sin(sweep / 2)))
			FX.sparks(fp, tipP, { dir = tangent, spread = 30, count = 5, color = black and PAL.Ember or WHITE,
				color2 = edge, speed = { 18, 36 }, size = 0.35, life = 0.35 })
		end
		for _, it in ipairs(items) do
			if t < it.on then
				-- not drawn yet
			elseif t < it.off then
				if it.st == 0 then
					it.st = 1
					it.p.Transparency = it.base
				end
			else
				local k = math.clamp((t - it.off) / it.dur, 0, 1)
				local e = k * k
				it.st = 2
				it.p.Transparency = it.base + (1 - it.base) * e
				it.p.Size = it.size * (Vector3.one - (Vector3.one - it.thin) * e)
			end
		end
	end)
	Debris:AddItem(folder, math.min(total + 0.5, MAX_LIFE))
	return folder
end

---------------------------------------------------------------------------------------------------
-- slashLine(f, a, b, o) -> Line: a straight razor cut a -> b. A Neon core inside a 2.4x coloured sheath (black: a
-- dark core in a crimson sheath), drawn a -> b over o.draw (the front races, Quart Out), held lit o.hold, then thins
-- and fades over o.life. Line:setAlpha(k) sets the lit transparency (0 = full, 1 = gone; the sheath follows),
-- Line:shatter() splits it into glints along its length (0.2 s), Line:fade(t), Line:Destroy(), Line.parts.
-- o = { width = 0.14, core = WHITE, edge = Reiatsu, draw = 0, hold = 0, life = 0.3, black = false }
local Line = {}
Line.__index = Line
function S.slashLine(f, a, b, o)
	a, b = vec(a), vec(b)
	if not a or not b then
		return dummy({ parts = {} })
	end
	o = o or {}
	local fp = parentOf(f)
	if (b - a).Magnitude < 0.05 then
		b = a + Vector3.new(0, 0, -0.05)
	end
	local black = o.black == true
	local self = setmetatable({
		a = a, b = b, L = (b - a).Magnitude, w = math.max(o.width or 0.14, 0.02), black = black,
		coreC = o.core or (black and PAL.Black or WHITE), edgeC = o.edge or (black and PAL.Crimson or PAL.Reiatsu),
		draw = math.max(o.draw or 0, 0), hold = math.max(o.hold or 0, 0), life = math.clamp(o.life or 0.3, 0.03, MAX_LIFE),
		t0 = os.clock(), state = "draw", dead = false, ua = nil,
	}, Line)
	self.baseCore = black and 0.03 or 0
	self.baseSheath = black and 0.25 or 0.45
	self.dir = (b - a).Unit
	self.core = newPart("SlashCore", black and PLASTIC or NEON, self.coreC, Vector3.new(self.w, self.w, 0.01), nil, 1, nil)
	self.sheath = newPart("SlashEdge", NEON, self.edgeC, Vector3.new(self.w * 2.4, self.w * 2.4, 0.01), nil, 1, nil)
	self.parts = { self.core, self.sheath }
	self.folder = Instance.new("Folder")
	self.folder.Name = "SlashLine"
	self.core.Parent = self.folder
	self.sheath.Parent = self.folder
	self:_shape(self.draw <= 0 and 1 or 0, 1)
	self.folder.Parent = fp
	self.conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	task.delay(MAX_LIFE, function()
		self:Destroy()
	end)
	return self
end
-- k = drawn fraction (0..1), wk = width multiplier
function Line:_shape(k, wk)
	local L = math.max(self.L * k, 0.01)
	local mid = self.a + self.dir * (L / 2)
	local cf = lookAlong(mid, self.dir)
	local w = self.w * wk
	self.core.Size = Vector3.new(w, w, L)
	self.sheath.Size = Vector3.new(w * 2.4, w * 2.4, L + self.w * 1.2 * k)
	self.core.CFrame = cf
	self.sheath.CFrame = cf
end
function Line:_lit(fadeK)
	local cT = self.ua or self.baseCore
	local sT = self.ua and (self.baseSheath + (1 - self.baseSheath) * self.ua) or self.baseSheath
	self.core.Transparency = cT + (1 - cT) * fadeK
	self.sheath.Transparency = sT + (1 - sT) * fadeK
end
function Line:_step()
	if self.dead then
		return
	end
	if not self.folder.Parent then
		self:Destroy()
		return
	end
	local t = os.clock() - self.t0
	if self.state == "draw" then
		local k = self.draw > 0 and math.clamp(t / self.draw, 0, 1) or 1
		self:_shape(1 - (1 - k) ^ 4, 1)
		self:_lit(0)
		if k >= 1 then
			self.state = "hold"
			self.holdUntil = self.t0 + self.draw + self.hold
		end
	elseif self.state == "hold" then
		self:_lit(0)
		if os.clock() >= self.holdUntil then
			self.state = "fade"
			self.fadeT0, self.fadeDur = os.clock(), self.life
		end
	elseif self.state == "fade" then
		local k = math.clamp((os.clock() - self.fadeT0) / self.fadeDur, 0, 1)
		local e = k * k
		self:_shape(1, 1 - 0.8 * e)
		self:_lit(e)
		if k >= 1 then
			self:Destroy()
		end
	end
end
function Line:setAlpha(k)
	if self.dead then
		return
	end
	self.ua = math.clamp(tonumber(k) or 0, 0, 1)
end
function Line:fade(t)
	if self.dead then
		return
	end
	if self.state == "draw" then
		self:_shape(1, 1)
	end
	self.state = "fade"
	self.fadeT0, self.fadeDur = os.clock(), math.clamp(tonumber(t) or self.life, 0.02, MAX_LIFE)
end
function Line:shatter()
	if self.dead then
		return
	end
	local fp = self.folder.Parent or kitFolder()
	local a, dir, L, w = self.a, self.dir, self.L, self.w
	self:Destroy()
	local folder = Instance.new("Folder")
	folder.Name = "LineShatter"
	local r, u = FX.perp(dir)
	local n = math.clamp(math.floor(L / 2.2 + 0.5), 3, 14)
	local bits = {}
	local cfs, parts = {}, {}
	for i = 1, n do
		local s0 = (i - 1) / n * L
		local len = L / n * rng:NextNumber(0.45, 0.8)
		local p = a + dir * (s0 + L / n * 0.5)
		local cf = lookAlong(p, dir) * CFrame.Angles(0, 0, rng:NextNumber(0, TAU))
		local useEdge = i % 3 == 0
		local bit = newPart("Glint", (self.black and not useEdge) and PLASTIC or NEON, useEdge and self.edgeC or self.coreC,
			Vector3.new(w * 1.1, w * 0.5, len), cf, self.black and 0.05 or 0, folder)
		table.insert(bits, {
			p = bit, cf = cf, size = bit.Size, base = bit.Transparency,
			v = (r * rng:NextNumber(-1, 1) + u * rng:NextNumber(-1, 1)).Unit * rng:NextNumber(3, 9) + UP * rng:NextNumber(0, 3),
			spin = FX.randUnit() * rng:NextNumber(6, 16), life = rng:NextNumber(0.18, 0.3),
		})
		table.insert(parts, bit)
		table.insert(cfs, cf)
	end
	-- one star emitter over the whole length (a Box host along the line: one Emit, spread through its volume)
	local host = newPart("GlintHost", PLASTIC, WHITE, Vector3.new(w * 3, w * 3, L), lookAlong(a + dir * (L / 2), dir), 1, folder)
	local e = FX.emitter(host, {
		Texture = TEX.star, Color = cs(self.black and PAL.Ember or WHITE, self.edgeC), Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(1, 5),
		SpreadAngle = Vector2.new(180, 180), Size = nsk({ { 0, 0.55 }, { 0.3, 0.4 }, { 1, 0 } }),
		Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200), Drag = 4, Brightness = 2.2,
	})
	folder.Parent = fp
	e:Emit(math.clamp(math.floor(L * 1.4), 6, 36))
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - t0
		if t > 0.32 or not folder.Parent then
			conn:Disconnect()
			for _, bt in ipairs(bits) do
				bt.p:Destroy()
			end
			Debris:AddItem(folder, 0.5)
			return
		end
		for i, bt in ipairs(bits) do
			local k = math.clamp(t / bt.life, 0, 1)
			bt.cf = (bt.cf + bt.v * dt) * CFrame.fromAxisAngle(bt.spin.Unit, bt.spin.Magnitude * dt)
			cfs[i] = bt.cf
			bt.p.Transparency = bt.base + (1 - bt.base) * k
			bt.p.Size = bt.size * (1 - 0.6 * k)
		end
		workspace:BulkMoveTo(parts, cfs, BULK)
	end)
	Debris:AddItem(folder, 1.2)
end
function Line:Destroy()
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.folder then
		self.folder:Destroy()
	end
end
Line.destroy = Line.Destroy

---------------------------------------------------------------------------------------------------
-- crescent(f, o) -> Crescent: THE Getsuga (DESIGN section 3). A moon-crescent of reiatsu: outer and inner circular
-- arcs between the same two tips (span tip to tip; outer bulge = depth, inner = depth * 0.45), 14 segments, thick in
-- the middle and tapering to points. Frame: cf.LookVector = travel (the convex side leads), the tips along
-- +/-cf.UpVector before the roll by o.tilt (degrees about the travel axis), the sheet's thickness along cf.RightVector.
-- Layers per segment: CORE (Core Neon 0 / black: SmoothPlastic Black 0.05), MID (Reiatsu Neon 0.35, 1.25x / black: a
-- Crimson Neon rim strip along the outer arc), HAZE (ForceField, 1.6x, 0.65 / black 0.7). Three emitter hosts along
-- the arc stream flame wisps backward (Shikai: Core -> Reiatsu, rate 140 / black: dark smoke 90 + crimson sparks 60),
-- Trails at both tips and the centre, a PointLight on the centre host. o.alpha raises every layer's transparency.
-- Crescent:place(cf, scale?) every frame (the first place parents it); :split(dir?) - two halves fly apart and
-- dissolve into flame wisps in 0.3 s, then it destroys itself; :fade(t); :Destroy(); .parts; .host (the centre
-- emitter host: parent a travelling Sound to it). It destroys itself after 8 s.
-- o = { span = 16, depth = 3.5, thick = 1.1, tilt = -30, core, edge, black = false, alpha = 0, flames = true,
--       trails = true, light = true }
local Crescent = {}
Crescent.__index = Crescent
local CRES_N = 14
function S.crescent(f, o)
	o = o or {}
	local fp = parentOf(f)
	local black = o.black == true
	local span = math.max(o.span or 16, 0.5)
	local h = span / 2
	local depth = math.clamp(o.depth or 3.5, 0.1, h * 0.95)
	local thick = math.max(o.thick or 1.1, 0.05)
	local core = o.core or (black and PAL.Black or PAL.Core)
	local edge = o.edge or (black and PAL.Crimson or PAL.Reiatsu)
	local alpha = math.clamp(o.alpha or 0, 0, 1)
	local function A(t)
		return t + (1 - t) * alpha
	end
	local self = setmetatable({
		parts = {}, items = {}, all = {}, cfs = {}, emitters = {}, smoke = {}, trails = {}, scale = 1, dead = false,
		black = black, roll = CFrame.Angles(0, 0, math.rad(o.tilt or -30)), placed = false, lastGate = 0,
	}, Crescent)
	local folder = Instance.new("Folder")
	folder.Name = "Crescent"
	self.folder = folder
	local function arc(d, u)
		local Ro = (h * h + d * d) / (2 * d)
		local th = math.asin(math.clamp(h / Ro, -1, 1))
		local ang = th * u
		return Vector3.new(0, Ro * math.sin(ang), -d + Ro * (1 - math.cos(ang)))
	end
	local function midAt(u)
		return (arc(depth, u) + arc(depth * 0.45, u)) / 2
	end
	-- item = { p, lcf (unscaled local CFrame), size (unscaled), base, u }
	local function add(p, lcf, size, base, u, visible)
		p.Size = size
		p.Transparency = base
		p.Parent = folder
		local it = { p = p, lcf = lcf, size = size, base = base, u = u }
		table.insert(self.items, it)
		table.insert(self.all, p)
		table.insert(self.cfs, lcf)
		if visible then
			table.insert(self.parts, p)
		end
		return it
	end
	local coreItems = {}
	-- 14 segments on a Getsuga, fewer on the small M1 waves (8 at span 5-9): same look, half the parts
	local N = math.clamp(math.floor(span * 0.9 + 0.5), 8, CRES_N)
	for i = 1, N do
		local u0, u1 = -1 + 2 * (i - 1) / N, -1 + 2 * i / N
		local um = (u0 + u1) / 2
		local oM, iM = arc(depth, um), arc(depth * 0.45, um)
		local m0, m1 = midAt(u0), midAt(u1)
		local chord = m1 - m0
		local len = chord.Magnitude
		local t = chord.Unit
		local bw = math.max((oM - iM).Magnitude, 0.08)
		local thk = thick * (0.25 + 0.75 * (1 - um * um) ^ 0.7)
		local c = (oM + iM) / 2
		local rot = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, t:Cross(Vector3.xAxis))
		local lcf = CFrame.new(c) * rot
		local ov = math.min(bw * 0.35, 0.6) + 0.05
		local coreCol = black and core or core:Lerp(edge, math.abs(um) ^ 2 * 0.45)
		local tipSign = (i == 1 and -1) or (i == N and 1) or nil
		if tipSign then
			-- the two end segments are wedges: flat along the outer arc, the thin edge AT the tip (a real point)
			local tipP = arc(depth, tipSign)
			local uE = tipSign < 0 and u1 or u0
			local oE, iE = arc(depth, uE), arc(depth * 0.45, uE)
			local Zv = (oE - tipP).Unit
			local across = iE - oE
			local Yv = (across - Zv * across:Dot(Zv)).Unit
			local rotW = CFrame.fromMatrix(Vector3.zero, Yv:Cross(Zv), Yv, Zv)
			local Lz = (oE - tipP).Magnitude
			local Hh = math.max(across:Dot(Yv), 0.05)
			local function wedge(name, mat, col, fx, fy, fz, base, lift)
				local p = Instance.new("WedgePart")
				p.Name = name
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				p.Material, p.Color = mat, col
				local hY, lZ = Hh * fy, Lz * fz
				local c = tipP + Zv * (lZ / 2) + Yv * (hY / 2 - (lift or 0))
				return add(p, CFrame.new(c) * rotW, Vector3.new(thk * fx, hY, lZ), base, um, true)
			end
			if black then
				coreItems[i] = wedge("CresCore", PLASTIC, core, 1, 1, 1, A(0.05))
				wedge("CresRim", NEON, edge, 1.25, 0.35, 1.02, A(0.15), 0.02)
			else
				coreItems[i] = wedge("CresCore", NEON, coreCol, 0.75, 0.62, 1, A(0))
				wedge("CresMid", NEON, edge, 1.5, 1.12, 1.04, A(0.3), 0.06)
			end
			wedge("CresHaze", FIELD, edge, black and 2.2 or 2.4, 1.6, 1.08, A(black and 0.7 or 0.65), 0.25)
		else
			-- edge-aligned boxes: the core's outer face rides the outer-arc chord and the mid's inner face rides the
			-- inner-arc chord, so both silhouettes are smooth polylines (no stair steps where the band width changes)
			local o0, o1 = arc(depth, u0), arc(depth, u1)
			local i0, i1 = arc(depth * 0.45, u0), arc(depth * 0.45, u1)
			local tO, tI = (o1 - o0).Unit, (i1 - i0).Unit
			local inward = iM - oM
			inward = (inward - tO * inward:Dot(tO)).Unit
			local outward = oM - iM
			outward = (outward - tI * outward:Dot(tI)).Unit
			local rotO = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, tO:Cross(Vector3.xAxis))
			local rotI = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, tI:Cross(Vector3.xAxis))
			local lenO, lenI = (o1 - o0).Magnitude + 0.04, (i1 - i0).Magnitude + bw * 0.25 + 0.04
			local function outerBox(w)
				return CFrame.new((o0 + o1) / 2 + inward * (w / 2)) * rotO
			end
			local function innerBox(w)
				return CFrame.new((i0 + i1) / 2 + outward * (w / 2)) * rotI
			end
			if black then
				local cp = FX.part("CresCore", BLOCK, PLASTIC, coreCol, nil)
				-- two overlapping black boxes, one riding each edge: both silhouettes smooth, the steps hidden inside
				coreItems[i] = add(cp, outerBox(bw * 0.62), Vector3.new(thk, bw * 0.62, lenO), A(0.05), um, true)
				local cp2 = FX.part("CresCore", BLOCK, PLASTIC, coreCol, nil)
				add(cp2, innerBox(bw * 0.62), Vector3.new(thk * 0.96, bw * 0.62, lenI), A(0.05), um, true)
				-- the crimson rim along the outer (leading) arc
				local rimW = math.max(math.min(bw * 0.3, depth * 0.08), 0.1)
				local rp = FX.part("CresRim", BLOCK, NEON, edge, nil)
				add(rp, outerBox(rimW) + inward * -0.03, Vector3.new(thk * 1.25, rimW, lenO), A(0.15), um, true)
			else
				-- a white-hot heart riding the leading (outer) edge inside the ice-blue body
				local cp = FX.part("CresCore", BLOCK, NEON, coreCol, nil)
				local wC = math.min(bw * 0.7, depth * 0.16)
				coreItems[i] = add(cp, outerBox(wC), Vector3.new(thk * 0.75, wC, lenO), A(0), um, true)
				local mp = FX.part("CresMid", BLOCK, NEON, edge, nil)
				add(mp, innerBox(bw * 0.95), Vector3.new(thk * 1.5, bw * 0.95, lenI), A(0.3), um, true)
			end
			local hp = FX.part("CresHaze", BLOCK, FIELD, edge, nil)
			-- the haze is thick across the sheet too, so the wave has body from behind (the caster's view is edge-on)
			add(hp, lcf, Vector3.new(thk * (black and 2.2 or 2.4), bw * 1.6, (len + ov) * 1.05), A(black and 0.7 or 0.65), um, true)
		end
	end
	-- three emitter hosts along the arc (axis-aligned with the crescent frame: Back = +Z = behind the wave)
	if o.flames ~= false then
		-- a small or ghosted crescent (an M1 wave, the mode's trailing echo) gets one host: a third of the emitters
		local small = span < 13.5 or alpha >= 0.2
		local share = small and 0.6 or 1 / 3
		for j, um in ipairs(small and { 0 } or { -0.62, 0, 0.62 }) do
			local c = midAt(um)
			local hp = FX.part("CresHost", BLOCK, PLASTIC, WHITE, nil)
			local it = add(hp, CFrame.new(c), Vector3.new(thick * 1.1, span / (small and 1.6 or 3.2), depth * 0.55 + 0.3), 1, um, false)
			it.host = true
			local sz = math.clamp(span / 16, 0.3, 1.6)
			local common = {
				Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
				EmissionDirection = Enum.NormalId.Back, Rotation = NumberRange.new(0, 360), Enabled = false,
			}
			if black then
				local sm = FX.emitter(hp, {
					Texture = TEX.smoke, Color = cs(PAL.Smoke, PAL.Black), LightEmission = 0, LightInfluence = 0.3,
					Size = nsk({ { 0, 1.2 * sz }, { 0.4, 2.6 * sz }, { 1, 3.2 * sz } }),
					Transparency = tseq({ { 0, 0.25 }, { 0.5, 0.5 }, { 1, 1 } }), Lifetime = NumberRange.new(0.25, 0.42),
					Speed = NumberRange.new(4, 12), SpreadAngle = Vector2.new(25, 25), Drag = 2,
					Acceleration = Vector3.new(0, 5, 0), RotSpeed = NumberRange.new(-80, 80), Rate = 0,
				})
				for k, v in pairs(common) do
					sm[k] = v
				end
				table.insert(self.emitters, { e = sm, rate = 90 * share, smoke = true })
				local sp = FX.emitter(hp, {
					Texture = FLARE, Color = cs(PAL.Ember, edge), Size = nsk({ { 0, 0.45 * sz }, { 1, 0 } }),
					Transparency = tseq({ { 0, 0 }, { 0.7, 0.25 }, { 1, 1 } }), Lifetime = NumberRange.new(0.25, 0.45),
					Speed = NumberRange.new(10, 26), SpreadAngle = Vector2.new(45, 45), Drag = 2.5,
					Acceleration = Vector3.new(0, -10, 0), RotSpeed = NumberRange.new(-200, 200), Brightness = 2.5, Rate = 0,
				})
				for k, v in pairs(common) do
					sp[k] = v
				end
				table.insert(self.emitters, { e = sp, rate = 60 * share })
			else
				local fl = FX.emitter(hp, {
					Texture = FIRE, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, core), ColorSequenceKeypoint.new(0.35, edge),
						ColorSequenceKeypoint.new(1, PAL.Ice) }), Size = nsk({ { 0, 1.0 * sz }, { 0.35, 2.1 * sz }, { 1, 0.2 } }),
					Transparency = tseq({ { 0, 0.3 }, { 0.45, 0.45 }, { 1, 1 } }), Lifetime = NumberRange.new(0.2, 0.34),
					Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(30, 30), Drag = 2,
					Acceleration = Vector3.new(0, 7, 0), RotSpeed = NumberRange.new(-90, 90), Brightness = 2, Rate = 0,
					ZOffset = -0.5,
				})
				for k, v in pairs(common) do
					fl[k] = v
				end
				table.insert(self.emitters, { e = fl, rate = 140 * share })
			end
			if um == 0 then
				self.host = hp
				if o.light ~= false then
					local l = Instance.new("PointLight")
					l.Color = edge
					l.Brightness = black and 2 or 3
					l.Range = math.clamp(span * 1.1, 8, 24)
					l.Shadows = false
					l.Parent = hp
					self.light = l
				end
			end
		end
	end
	if not self.host then
		local hp = FX.part("CresHost", BLOCK, PLASTIC, WHITE, nil)
		local it = add(hp, CFrame.new(midAt(0)), Vector3.one * 0.2, 1, 0, false)
		it.host = true
		self.host = hp
	end
	-- trails at both tips and the centre (FaceCamera ribbons: the crescent sheet is edge-on to the caster)
	if o.trails ~= false then
		for _, spec in ipairs({ { 1, 0.32 }, { N, 0.32 }, { math.floor(N / 2), 0.9 } }) do
			local it = coreItems[spec[1]]
			if it then
				local w = spec[2] * math.clamp(span / 16, 0.4, 1.4)
				local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
				a0.Position = Vector3.new(0, w / 2, 0)
				a1.Position = Vector3.new(0, -w / 2, 0)
				a0.Parent, a1.Parent = it.p, it.p
				local tr = Instance.new("Trail")
				tr.Attachment0, tr.Attachment1 = a0, a1
				tr.Color = cs(black and PAL.Ember or core, edge)
				tr.Lifetime = 0.25
				tr.LightEmission = 1
				tr.LightInfluence = 0
				tr.FaceCamera = true
				tr.MinLength = 0.1
				tr.Transparency = tseq({ { 0, A(0.15) }, { 1, 1 } })
				tr.WidthScale = nsk({ { 0, 1 }, { 1, 0 } })
				tr.Enabled = false
				pcall(function()
					tr.Brightness = 2
				end)
				tr.Parent = it.p
				table.insert(self.trails, tr)
			end
		end
	end
	task.delay(MAX_LIFE, function()
		self:Destroy()
		folder:Destroy()
	end)
	self.fp = fp
	return self
end
function Crescent:_resize(scale)
	self.scale = scale
	for _, it in ipairs(self.items) do
		if not it.host then
			it.p.Size = it.size * scale
		end
	end
end
function Crescent:_gate()
	-- near / on-axis cameras: thin the flame wake (no white wall down the lens) and keep dark smoke out of the first
	-- 8 studs in front of the camera
	local d = camDist(self.cf.Position)
	local k = math.clamp(d / 30, 0.3, 1)
	for _, em in ipairs(self.emitters) do
		if em.smoke and d < 14 then
			em.e.Rate = 0
		else
			em.e.Rate = em.rate * k
		end
	end
end
function Crescent:place(cf, scale)
	if self.dead or self.splitting or typeof(cf) ~= "CFrame" then
		return
	end
	scale = math.clamp(tonumber(scale) or 1, 0.05, 10)
	self.cf = cf
	if math.abs(scale - self.scale) > 0.01 then
		self:_resize(scale)
	end
	local frame = cf * self.roll
	for i, it in ipairs(self.items) do
		local l = it.lcf
		self.cfs[i] = frame * (scale == 1 and l or (CFrame.new(l.Position * scale) * l.Rotation))
	end
	workspace:BulkMoveTo(self.all, self.cfs, BULK)
	if not self.placed then
		self.placed = true
		self.folder.Parent = self.fp
		for _, em in ipairs(self.emitters) do
			em.e.Enabled = true
		end
		for _, tr in ipairs(self.trails) do
			tr.Enabled = true
		end
	end
	if os.clock() - self.lastGate > 0.08 then
		self.lastGate = os.clock()
		self:_gate()
	end
end
function Crescent:split(dir)
	if self.dead or self.splitting then
		return
	end
	if not self.cf then
		self:Destroy()
		return
	end
	self.splitting = true
	local cf = self.cf
	local fwd = (typeof(dir) == "Vector3" and dir.Magnitude > 1e-3) and dir.Unit or cf.LookVector
	local frame = cf * self.roll
	local tips, normal = frame.UpVector, frame.RightVector
	local center = frame.Position
	local start = {}
	for i, it in ipairs(self.items) do
		start[i] = self.cfs[i]
	end
	for _, em in ipairs(self.emitters) do
		em.e.Rate = 0
		em.e:Emit(em.smoke and 6 or 12)
	end
	local t0 = os.clock()
	local burst2 = false
	self.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		local k = math.clamp(t / 0.3, 0, 1)
		if k >= 1 or not self.folder.Parent then
			for _, tr in ipairs(self.trails) do
				tr.Enabled = false
			end
			self:Destroy(0.3)
			return
		end
		if not burst2 and t > 0.12 then
			burst2 = true
			for _, em in ipairs(self.emitters) do
				if not em.smoke then
					em.e:Emit(8)
				end
			end
		end
		local e = 1 - (1 - k) ^ 2
		for i, it in ipairs(self.items) do
			local s = it.u < 0 and -1 or 1
			local off = fwd * (14 * e) + tips * (s * (2.5 + 9 * e) * e)
			local rot = CFrame.fromAxisAngle(normal, s * 0.55 * e)
			self.cfs[i] = CFrame.new(off) * CFrame.new(center) * rot * CFrame.new(-center) * start[i]
			if not it.host then
				it.p.Transparency = it.base + (1 - it.base) * (k ^ 1.2)
				it.p.Size = it.size * self.scale * Vector3.new(1 - 0.6 * k, 1 - 0.5 * k, 1)
			end
		end
		workspace:BulkMoveTo(self.all, self.cfs, BULK)
	end)
end
function Crescent:fade(t)
	if self.dead then
		return
	end
	t = math.clamp(tonumber(t) or 0.3, 0.02, MAX_LIFE)
	for _, em in ipairs(self.emitters) do
		em.e.Rate = 0
	end
	for _, tr in ipairs(self.trails) do
		tr.Enabled = false
	end
	for _, it in ipairs(self.items) do
		if not it.host then
			tween(it.p, t, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	if self.light then
		tween(self.light, t, { Brightness = 0 })
	end
	task.delay(t, function()
		self:Destroy(0.3)
	end)
end
-- linger: seconds to keep the (already faded) folder so the flame wisps / trails finish
function Crescent:Destroy(linger)
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if type(linger) == "number" and linger > 0 and self.folder.Parent then
		for _, it in ipairs(self.items) do
			if not it.host then
				it.p.Transparency = 1
			end
		end
		for _, em in ipairs(self.emitters) do
			em.e.Enabled = false
		end
		if self.light then
			self.light.Enabled = false
		end
		Debris:AddItem(self.folder, linger)
	else
		self.folder:Destroy()
	end
end
Crescent.destroy = Crescent.Destroy

---------------------------------------------------------------------------------------------------
-- bladeTrail(char, c0, c1, life?, secs?, o?) -> handle: the classic sword trail, a Trail TrailA -> TrailB along the
-- blade (FaceCamera false, LightEmission 1, WidthScale 1 -> 0.2) plus a hotter streak over the outer half of the
-- blade (the tip moves fastest). Black: a dark Smoke ribbon (LightEmission 0) plus a thin Crimson edge trail.
-- c0 = the colour at the blade (newest), c1 = the tail colour. secs = auto-stop. :stop() (the ribbon fades out over
-- its lifetime), :Destroy() (now). o = { black = false, width = 1 }
function S.bladeTrail(char, c0, c1, life, secs, o)
	o = o or {}
	local info = swordOf(char)
	if not info or not info.trailA or not info.trailB then
		return dummy()
	end
	local handle = info.handle
	local black = o.black == true
	life = math.clamp(tonumber(life) or 0.18, 0.04, 1.5)
	local wmul = math.clamp(o.width or 1, 0.1, 4)
	local trails, atts = {}, {}
	local function mk(a0, a1, color, lifeT, lightE, t0, w0, w1, name)
		local t = Instance.new("Trail")
		t.Name = name
		t.Attachment0, t.Attachment1 = a0, a1
		t.Color = color
		t.Lifetime = lifeT
		t.LightEmission = lightE
		t.LightInfluence = lightE > 0 and 0 or 0.5
		t.FaceCamera = false
		t.MinLength = 0.02
		t.Transparency = tseq({ { 0, t0 }, { 0.45, t0 + (1 - t0) * 0.45 }, { 1, 1 } })
		t.WidthScale = nsk({ { 0, w0 }, { 1, w1 } })
		pcall(function()
			t.Brightness = 2.2
		end)
		t.Parent = handle
		table.insert(trails, t)
		return t
	end
	local function att(pos, name)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = handle
		table.insert(atts, a)
		return a
	end
	local A, B = info.trailA.Position, info.trailB.Position
	local outer = att(A:Lerp(B, 0.5), "ZangetsuTrailMid")
	local tipX = att(B + (B - A).Unit * 0.25, "ZangetsuTrailTip")
	if black then
		local bright = (c0 and c1 and (lum(c0) >= lum(c1) and c0 or c1)) or c1 or c0 or PAL.Crimson
		if lum(bright) < 0.12 then
			bright = PAL.Crimson
		end
		mk(info.trailA, info.trailB, cs(PAL.Smoke, PAL.Black), life * 1.25, 0, 0.12, wmul, 0.35, "ZangetsuTrailSmoke")
		mk(outer, tipX, cs(bright, PAL.Blood), life * 0.85, 1, 0.05, wmul, 0.1, "ZangetsuTrailEdge")
	else
		local head, tail = c0 or PAL.Core, c1 or PAL.Reiatsu
		mk(info.trailA, info.trailB, cs(head, tail), life, 1, 0.06, wmul, 0.2, "ZangetsuTrail")
		mk(outer, tipX, cs(WHITE, head:Lerp(tail, 0.5)), life * 0.7, 1, 0.1, wmul, 0.05, "ZangetsuTrailTip")
	end
	local h = { dead = false, trails = trails }
	local function kill()
		for _, t in ipairs(trails) do
			t:Destroy()
		end
		for _, a in ipairs(atts) do
			a:Destroy()
		end
	end
	function h:stop()
		if h.dead then
			return
		end
		h.dead = true
		for _, t in ipairs(trails) do
			t.Enabled = false
		end
		task.delay(life * 1.3 + 0.05, kill)
	end
	function h:Destroy()
		h.dead = true
		kill()
	end
	h.destroy = h.Destroy
	h.set, h.keep = noop, noop
	if tonumber(secs) and secs > 0 then
		task.delay(math.min(secs, MAX_LIFE), function()
			h:stop()
		end)
	end
	task.delay(MAX_LIFE, function()
		h:stop()
	end)
	return h
end

---------------------------------------------------------------------------------------------------
-- bladeGlow(char, o?) -> handle: reiatsu wreathing the blade. Flame licks streaming off the blade's own box (the
-- emitter rides the blade part), a Neon sliver hugging the cutting edge (transparency 1 - 0.8k), a PointLight
-- (brightness 2k). Follows a form swap (the shown blade is re-read), hides while the sword is vanished.
-- :set(k 0..1) (also keeps it alive), :keep(), :stop() (fades out), :Destroy().
-- o = { color = Core, color2 = Reiatsu, black = false, rate = 40, light = true, life = 6.8 }
function S.bladeGlow(char, o)
	o = o or {}
	local info = swordOf(char)
	if not info then
		return dummy()
	end
	local black = o.black == true
	local color = o.color or (black and PAL.Smoke or PAL.Core)
	local color2 = o.color2 or (black and PAL.Crimson or PAL.Reiatsu)
	local baseRate = math.max(o.rate or 40, 0)
	local fp = kitFolder()
	local clock = lifeClock(o.life)
	local h = { dead = false, k = 0 }
	local ems = {}
	local blade, edgePart
	local function makeEmitters(part)
		for _, em in ipairs(ems) do
			em.e:Destroy()
		end
		ems = {}
		local wk = math.clamp(part.Size.Z / 0.98 * 1.5, 0.55, 1)
		local common = { Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(-25, 25), Rate = 0 }
		local function put(props, mul, smoke)
			for k, v in pairs(common) do
				if props[k] == nil then
					props[k] = v
				end
			end
			local e = FX.emitter(part, props)
			table.insert(ems, { e = e, mul = mul, smoke = smoke })
		end
		if black then
			put({ Texture = TEX.smoke, Color = cs(color, PAL.Black), LightEmission = 0, LightInfluence = 0.3,
				Size = nsk({ { 0, 0.45 * wk }, { 0.4, 1.0 * wk }, { 1, 1.4 * wk } }),
				Transparency = tseq({ { 0, 0.35 }, { 0.5, 0.55 }, { 1, 1 } }), Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, 6, 0),
				Drag = 1, RotSpeed = NumberRange.new(-60, 60) }, 0.8, true)
			put({ Texture = FIRE, Color = cs(PAL.Ember, color2), Size = nsk({ { 0, 0.3 * wk }, { 0.35, 0.6 * wk }, { 1, 0 } }),
				Transparency = tseq({ { 0, 0.35 }, { 0.3, 0.15 }, { 1, 1 } }), Lifetime = NumberRange.new(0.2, 0.36),
				Speed = NumberRange.new(1.5, 4), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 9, 0),
				Drag = 1, RotSpeed = NumberRange.new(-60, 60), Brightness = 2.2, ZOffset = 0.3 }, 0.6, false)
		else
			put({ Texture = FIRE, Color = flameSeq(color, color2), Size = nsk({ { 0, 0.35 * wk }, { 0.35, 0.85 * wk }, { 1, 0 } }),
				Transparency = tseq({ { 0, 0.45 }, { 0.3, 0.18 }, { 1, 1 } }), Lifetime = NumberRange.new(0.22, 0.42),
				Speed = NumberRange.new(1.5, 4), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 9, 0),
				Drag = 1, RotSpeed = NumberRange.new(-60, 60), Brightness = 1.5, ZOffset = 0.3 }, 1, false)
			put({ Texture = TEX.star, Color = cs(WHITE, color2), Size = nsk({ { 0, 0.28 }, { 1, 0 } }),
				Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.3, 0.5),
				Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, 4, 0),
				Drag = 2, RotSpeed = NumberRange.new(-200, 200), Brightness = 2.5 }, 0.25, false)
		end
	end
	local sliver = newPart("BladeSliver", NEON, black and color2 or color2:Lerp(WHITE, 0.35), Vector3.one * 0.1, nil, 1, nil)
	local light
	local function attach(i)
		blade = i.blade
		edgePart = edgeOf(i)
		if not live(blade) then
			return false
		end
		makeEmitters(blade)
		if o.light ~= false then
			if light then
				light:Destroy()
			end
			light = Instance.new("PointLight")
			light.Color = color2
			light.Range = 9
			light.Brightness = 0
			light.Shadows = false
			light.Parent = blade
		end
		return true
	end
	if not attach(info) then
		sliver:Destroy()
		return dummy()
	end
	sliver.Parent = fp
	local hidden = false
	local function apply()
		local k = h.k
		for _, em in ipairs(ems) do
			em.e.Rate = (hidden and 0 or baseRate * em.mul * k)
		end
		sliver.Transparency = hidden and 1 or (1 - 0.8 * k)
		if light then
			light.Brightness = hidden and 0 or 2 * k
		end
	end
	local conn
	local lastCheck = 0
	local function kill()
		h.dead = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, em in ipairs(ems) do
			em.e:Destroy()
		end
		if light then
			light:Destroy()
		end
		sliver:Destroy()
	end
	conn = RunService.Heartbeat:Connect(function()
		if clock.expired() or not live(char) then
			h:stop()
			return
		end
		local tnow = os.clock()
		if tnow - lastCheck > 0.1 then
			lastCheck = tnow
			local i = swordOf(char)
			if not i then
				hidden = true
				apply()
				return
			end
			local swapped = false
			if i.blade ~= blade then
				attach(i)
				swapped = true
			end
			local wasHidden = hidden
			hidden = hiddenPart(blade)
			if swapped or hidden ~= wasHidden then
				apply()
			end
		end
		if live(blade) then
			local ep = live(edgePart) and edgePart or nil
			if ep then
				sliver.CFrame = ep.CFrame
				sliver.Size = ep.Size + Vector3.new(0.035, 0.02, 0.05)
			else
				sliver.CFrame = blade.CFrame * CFrame.new(0, 0, blade.Size.Z / 2)
				sliver.Size = Vector3.new(blade.Size.X + 0.03, blade.Size.Y * 0.97, 0.09)
			end
		end
	end)
	function h:set(k)
		if h.dead then
			return
		end
		clock.keep()
		h.k = math.clamp(tonumber(k) or 0, 0, 1)
		apply()
	end
	function h:keep()
		clock.keep()
	end
	function h:stop()
		if h.dead then
			return
		end
		h.dead = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, em in ipairs(ems) do
			em.e.Rate = 0
		end
		tween(sliver, 0.3, { Transparency = 1 })
		if light then
			tween(light, 0.3, { Brightness = 0 })
		end
		task.delay(0.6, kill)
	end
	function h:Destroy()
		kill()
	end
	h.destroy = h.Destroy
	h.sliver = sliver
	h:set(0)
	return h
end

---------------------------------------------------------------------------------------------------
-- reiatsuFlame(f, pos, o?) -> host: a burst of rising flame licks (fire licks stretched along their motion).
-- Black: dark smoke licks (LightEmission 0) with crimson licks inside. Returns the host part (Debris'd).
-- o = { color = Core, color2 = Reiatsu, count = 12, height = 4, size = 1.2, life = 0.6, black = false, dir = UP,
--       spread = 15 }
function S.reiatsuFlame(f, pos, o)
	pos = vec(pos)
	if not pos then
		return nil
	end
	o = o or {}
	local fp = parentOf(f)
	local black = o.black == true
	local count = math.clamp(math.floor(o.count or 12), 1, 80)
	local height = math.max(o.height or 4, 0.2)
	local size = math.max(o.size or 1.2, 0.05)
	local life = math.clamp(o.life or 0.6, 0.1, 3)
	local dir = unit(o.dir, UP)
	local spread = o.spread or 15
	local host = FX.anchor(fp, pos, life + 0.15)
	local a = Instance.new("Attachment")
	a.CFrame = FX.yAlong(dir)
	a.Parent = host
	local sp = height / life * 1.5
	local common = {
		Lifetime = NumberRange.new(life * 0.55, life), Speed = NumberRange.new(sp * 0.6, sp),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(spread, spread), Drag = 1.6,
		Acceleration = dir * (height * 1.2), Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = nsk({ { 0, -0.6 }, { 1, -0.2 } }), Rotation = NumberRange.new(-8, 8),
	}
	local function burst(props, n)
		for k, v in pairs(common) do
			if props[k] == nil then
				props[k] = v
			end
		end
		local e = FX.emitter(a, props)
		e:Emit(n)
	end
	if black then
		burst({ Texture = FIRE, Color = cs(o.color or PAL.Smoke, PAL.Black), LightEmission = 0, LightInfluence = 0.3,
			Size = nsk({ { 0, size * 0.7 }, { 0.3, size * 1.15 }, { 1, size * 0.3 } }),
			Transparency = tseq({ { 0, 0.2 }, { 0.5, 0.4 }, { 1, 1 } }) }, count)
		burst({ Texture = FIRE, Color = cs(PAL.Ember, o.color2 or PAL.Crimson), Brightness = 2.4,
			Size = nsk({ { 0, size * 0.4 }, { 0.3, size * 0.75 }, { 1, 0 } }),
			Transparency = tseq({ { 0, 0.2 }, { 0.4, 0.15 }, { 1, 1 } }), ZOffset = 0.4 }, math.max(1, math.floor(count * 0.6)))
	else
		burst({ Texture = FIRE, Color = flameSeq(o.color or PAL.Core, o.color2 or PAL.Reiatsu), Brightness = 1.6,
			Size = nsk({ { 0, size * 0.55 }, { 0.3, size }, { 1, 0 } }),
			Transparency = tseq({ { 0, 0.25 }, { 0.4, 0.2 }, { 1, 1 } }) }, count)
	end
	return host
end

---------------------------------------------------------------------------------------------------
-- aura(char, o?) -> handle: flames rising off a body (emitters on the HRP's box, so they wrap the torso; a second
-- layer of licks and embers). Black: dark smoke flames (LightEmission 0) + crimson licks + embers. The local
-- character's aura dims when the camera is inside it (first person), and the dark smoke never reaches the lens.
-- :set(rate) (also keeps it alive), :keep(), :Destroy(). o = { color = Core, color2 = Reiatsu, rate = 30,
-- black = false, size = 1, life = 6.8 }
function S.aura(char, o)
	o = o or {}
	local hrp = typeof(char) == "Instance" and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return dummy()
	end
	local black = o.black == true
	local color = o.color or (black and PAL.Smoke or PAL.Core)
	local color2 = o.color2 or (black and PAL.Crimson or PAL.Reiatsu)
	local sz = math.clamp(o.size or 1, 0.2, 4)
	local clock = lifeClock(o.life)
	local h = { dead = false, rate = math.max(o.rate or 30, 0) }
	local ems = {}
	local base = {
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top, Rate = 0, Rotation = NumberRange.new(-10, 10),
	}
	local function put(props, mul, smoke)
		for k, v in pairs(base) do
			if props[k] == nil then
				props[k] = v
			end
		end
		local e = FX.emitter(hrp, props)
		e.Name = "ZangetsuAura"
		table.insert(ems, { e = e, mul = mul, smoke = smoke })
	end
	local lick = { Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = nsk({ { 0, -0.5 }, { 1, -0.1 } }) }
	if black then
		put({ Texture = FIRE, Color = cs(color, PAL.Black), LightEmission = 0, LightInfluence = 0.3,
			Size = nsk({ { 0, 0.9 * sz }, { 0.4, 1.6 * sz }, { 1, 0.6 * sz } }), Transparency = tseq({ { 0, 0.55 }, { 0.3, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.45, 0.8), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0, 10 * sz, 0), Drag = 0.8, Orientation = lick.Orientation, Squash = lick.Squash }, 1, true)
		put({ Texture = FIRE, Color = cs(PAL.Ember, color2), Brightness = 2.2,
			Size = nsk({ { 0, 0.5 * sz }, { 0.35, 1.0 * sz }, { 1, 0 } }), Transparency = tseq({ { 0, 0.5 }, { 0.3, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.3, 0.55), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0, 12 * sz, 0), Drag = 0.8, ZOffset = 0.2, Orientation = lick.Orientation,
			Squash = lick.Squash }, 0.6, false)
		put({ Texture = FLARE, Color = cs(PAL.Ember, color2), Brightness = 2.5, Size = nsk({ { 0, 0.3 * sz }, { 1, 0 } }),
			Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 5, 0), Drag = 1.2,
			RotSpeed = NumberRange.new(-200, 200) }, 0.2, false)
	else
		put({ Texture = FIRE, Color = flameSeq(color, color2), Brightness = 1.4,
			Size = nsk({ { 0, 0.8 * sz }, { 0.35, 1.45 * sz }, { 1, 0 } }), Transparency = tseq({ { 0, 0.6 }, { 0.25, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.4, 0.75), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(20, 20),
			Acceleration = Vector3.new(0, 11 * sz, 0), Drag = 0.8, ZOffset = -0.3, Orientation = lick.Orientation,
			Squash = lick.Squash }, 1, false)
		put({ Texture = TEX.star, Color = cs(WHITE, color2), Brightness = 2.5, Size = nsk({ { 0, 0.35 * sz }, { 1, 0 } }),
			Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 4, 0), Drag = 1.2,
			RotSpeed = NumberRange.new(-200, 200) }, 0.25, false)
	end
	local inside = false
	local function apply()
		for _, em in ipairs(ems) do
			local r = h.rate * em.mul
			if inside then
				r = em.smoke and 0 or r * 0.3
			end
			em.e.Rate = r
		end
	end
	local conn
	local last = 0
	local function kill()
		h.dead = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, em in ipairs(ems) do
			em.e.Enabled = false
			Debris:AddItem(em.e, 1.2)
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		if clock.expired() or not hrp.Parent then
			kill()
			return
		end
		local t = os.clock()
		if t - last > 0.1 then
			last = t
			local d = (camCF().Position - hrp.Position).Magnitude
			local want = d < 3.5
			if want ~= inside then
				inside = want
				apply()
			end
		end
	end)
	function h:set(rate)
		if h.dead then
			return
		end
		clock.keep()
		h.rate = math.max(tonumber(rate) or 0, 0)
		apply()
	end
	function h:keep()
		clock.keep()
	end
	h.stop = function()
		kill()
	end
	function h:Destroy()
		kill()
	end
	h.destroy = h.Destroy
	h.emitters = ems
	apply()
	return h
end

---------------------------------------------------------------------------------------------------
-- eyes(char, o?) -> handle: glowing eyes on the Head, slanted, each dragging a short streak. o.sclera puts black
-- discs behind the irises (hollow: gold on black). Hidden while the head is vanished / first person.
-- :set(k 0..1) brightness (flicker; also keeps it alive), :keep(), :Destroy().
-- o = { color = EyeGold, sclera = false, trail = true, forward (in front of the face; 0.05, sclera 0.15), life = 6.8 }
function S.eyes(char, o)
	o = o or {}
	local head = typeof(char) == "Instance" and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return dummy()
	end
	local fp = kitFolder()
	local color = o.color or PAL.EyeGold
	local sclera = o.sclera == true
	local fwd = o.forward or (sclera and 0.15 or 0.05)
	local clock = lifeClock(o.life)
	local k = head.Size.Y / 1.2
	local irises, discs, trails = {}, {}, {}
	for i = 1, 2 do
		local e = newPart("ZangetsuEye", NEON, color, Vector3.new(0.21, 0.075, 0.04) * k, head.CFrame, 0, nil)
		if o.trail ~= false then
			trails[i] = FX.trail(e, cs(color, color:Lerp(PAL.Crimson, 0.5)), 0.07 * k, 0.22, { tail = 0, alpha = 0.15 })
		end
		e.Parent = fp
		irises[i] = e
		if sclera then
			local d = newPart("ZangetsuSclera", PLASTIC, PAL.Black, Vector3.new(0.32, 0.17, 0.03) * k, head.CFrame, 0, fp)
			discs[i] = d
		end
	end
	local h = { dead = false, k = 1, irises = irises }
	local conn
	local shown = true
	local function kill()
		if h.dead then
			return
		end
		h.dead = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, e in ipairs(irises) do
			e:Destroy()
		end
		for _, d in ipairs(discs) do
			d:Destroy()
		end
	end
	local tiltR, tiltL = CFrame.Angles(0, 0, math.rad(14)), CFrame.Angles(0, 0, -math.rad(14))
	local function place()
		local s = head.Size
		local cf = head.CFrame
		local z = -0.5 * s.Z - fwd
		irises[1].CFrame = cf * CFrame.new(0.21 * s.X, 0.09 * s.Y, z - 0.012) * tiltR
		irises[2].CFrame = cf * CFrame.new(-0.21 * s.X, 0.09 * s.Y, z - 0.012) * tiltL
		if discs[1] then
			discs[1].CFrame = cf * CFrame.new(0.21 * s.X, 0.085 * s.Y, z + 0.01) * tiltR
			discs[2].CFrame = cf * CFrame.new(-0.21 * s.X, 0.085 * s.Y, z + 0.01) * tiltL
		end
	end
	local function show(want)
		shown = want
		for i = 1, 2 do
			irises[i].Transparency = want and (1 - h.k) or 1
			if trails[i] then
				trails[i].Enabled = want and h.k > 0.3
			end
			if discs[i] then
				discs[i].Transparency = want and 0 or 1
			end
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		if clock.expired() or not head.Parent or not char.Parent or not irises[1].Parent or not irises[2].Parent then
			kill()
			return
		end
		place()
		local want = head.LocalTransparencyModifier < 0.5 and head.Transparency < 0.9
		if want ~= shown then
			show(want)
		end
	end)
	place()
	function h:set(v)
		if h.dead then
			return
		end
		clock.keep()
		h.k = math.clamp(tonumber(v) or 1, 0, 1)
		show(shown)
	end
	function h:keep()
		clock.keep()
	end
	function h:Destroy()
		kill()
	end
	h.destroy, h.stop = h.Destroy, h.Destroy
	return h
end

---------------------------------------------------------------------------------------------------
-- cracks(f, pos, n, len, color, life?, o?): glowing cracks racing out over the ground under pos: n jagged 3-segment
-- seams (every other one forks), tapering, each over a dark gouge at its root; they glow, then cool toward black and
-- fade over life. o = { width = 0.22, grow = 0.14 (s to reach full length), depth = 10, branch = true }
function S.cracks(f, pos, n, len, color, life, o)
	pos = vec(pos)
	if not pos then
		return
	end
	o = o or {}
	local fp = parentOf(f)
	n = math.clamp(math.floor(n or 8), 1, 24)
	len = math.max(len or 6, 0.5)
	color = color or PAL.Reiatsu
	life = math.clamp(life or 1.4, 0.2, 6)
	if crowded(fp, 300) then
		n = math.max(2, math.floor(n / 2))
	end
	local hit = FX.groundHit(pos, o.depth or 10)
	if not hit then
		return
	end
	local g = hit.Position
	local gcol = S.groundColor(hit)
	local folder = Instance.new("Folder")
	folder.Name = "Cracks"
	local grow = math.max(o.grow or 0.14, 0)
	local w0 = o.width or 0.22
	local cool = color:Lerp(BLACK, 0.8)
	local function snap(p)
		local hh = FX.groundHit(p + UP * 1.5, 5)
		return hh and hh.Position or Vector3.new(p.X, g.Y, p.Z)
	end
	local function seg(p0, p1, w, delay, gouge)
		local d = p1 - p0
		local L = d.Magnitude
		if L < 0.05 then
			return
		end
		local cf = CFrame.lookAt((p0 + p1) / 2, p1)
		local seam = newPart("CrackSeam", NEON, color, Vector3.new(w, 0.07, L + w * 0.6), cf + UP * 0.05, 1, folder)
		local gp
		if gouge then
			gp = newPart("CrackGouge", PLASTIC, gcol:Lerp(BLACK, 0.7), Vector3.new(w * 2.8, 0.05, L + w), cf + UP * 0.025, 1, folder)
		end
		task.delay(delay, function()
			if not seam.Parent then
				return
			end
			seam.Transparency = 0
			tween(seam, life, { Color = cool, Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if gp then
				gp.Transparency = 0.15
				tween(gp, 0.5, { Transparency = 1 }, Enum.EasingStyle.Linear, Enum.EasingDirection.In, life)
			end
		end)
	end
	local off = rng:NextNumber(0, TAU)
	for i = 1, n do
		local ang = off + (i / n) * TAU + rng:NextNumber(-0.25, 0.25)
		local L = len * rng:NextNumber(0.6, 1)
		local prev = snap(g + Vector3.new(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(0.2, 0.6))
		local w = w0
		for j = 1, 3 do
			local a2 = ang + rng:NextNumber(-0.45, 0.45)
			local nxt = snap(prev + Vector3.new(math.cos(a2), 0, math.sin(a2)) * (L / 3))
			seg(prev, nxt, w, grow * (j - 1) / 3, j == 1)
			if j == 2 and o.branch ~= false and i % 2 == 0 then
				local a3 = a2 + (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(0.5, 0.9)
				seg(nxt, snap(nxt + Vector3.new(math.cos(a3), 0, math.sin(a3)) * L * 0.3), w * 0.6, grow * 0.8, false)
			end
			prev = nxt
			w *= 0.68
		end
	end
	folder.Parent = fp
	Debris:AddItem(folder, math.min(grow + life + 0.7, MAX_LIFE))
	return folder
end

---------------------------------------------------------------------------------------------------
-- trench(f, from, to, o?): a gouged scar from -> to on the ground: a dark gouge, a glowing seam down its middle that
-- cools toward black, and a churned lip of ground on one side (alternating call to call, dropped past ~260 parts).
-- Call it every few studs behind a wave. o = { width = 2.2, seam = Reiatsu, life = 2.2, black = false, depth = 8,
-- lips = true }
local trenchSide = 1
function S.trench(f, from, to, o)
	from, to = vec(from), vec(to)
	if not from or not to then
		return
	end
	o = o or {}
	local fp = parentOf(f)
	local width = math.max(o.width or 2.2, 0.2)
	local black = o.black == true
	local seamC = o.seam or (black and PAL.Crimson or PAL.Reiatsu)
	local life = math.clamp(o.life or 2.2, 0.3, 6)
	local h0, h1 = FX.groundHit(from, o.depth or 8), FX.groundHit(to, o.depth or 8)
	if not h0 or not h1 then
		return
	end
	local a, b = h0.Position, h1.Position
	local d = b - a
	local L = d.Magnitude
	if L < 0.1 or math.abs(d.Y) > L * 0.8 then
		return
	end
	local gcol, gmat = S.groundColor(h0)
	local cf = CFrame.lookAt((a + b) / 2, b)
	local folder = Instance.new("Folder")
	folder.Name = "Trench"
	local gouge = newPart("TrenchGouge", PLASTIC, black and PAL.Black or gcol:Lerp(BLACK, 0.62),
		Vector3.new(width, 0.1, L + width * 0.35), cf + UP * 0.03, 0.05, folder)
	local seam = newPart("TrenchSeam", NEON, seamC, Vector3.new(width * 0.24, 0.08, L + width * 0.3), cf + UP * 0.07, 0, folder)
	tween(seam, life * 0.82, { Color = seamC:Lerp(BLACK, 0.85), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(gouge, 0.6, { Transparency = 1 }, Enum.EasingStyle.Linear, Enum.EasingDirection.In, life * 0.85)
	if o.lips ~= false and not crowded(fp, 260) then
		trenchSide = -trenchSide
		local s = trenchSide
		local lip = newPart("TrenchLip", PLASTIC, gcol:Lerp(BLACK, 0.12), Vector3.new(width * 0.32, 0.45, L * 1.05),
			cf * CFrame.new(s * width * 0.62, 0.12, 0) * CFrame.Angles(0, 0, -s * math.rad(24)), 0, folder)
		pcall(function()
			lip.Material = gmat
		end)
		tween(lip, 0.6, { Transparency = 1, Size = lip.Size * Vector3.new(1, 0.3, 1) }, Enum.EasingStyle.Linear,
			Enum.EasingDirection.In, life * 0.85)
	end
	folder.Parent = fp
	Debris:AddItem(folder, math.min(life + 0.8, MAX_LIFE))
	return folder
end

---------------------------------------------------------------------------------------------------
-- ash(f, pos, o?) -> host: drifting black flakes (tumbling, LightEmission 0) + crimson embers, spread through a
-- sphere of o.radius. rise > 0 drifts up, < 0 falls. o = { count = 30, radius = 3, color = Black, color2 = Ember,
-- life = 2, rise = 4 }
function S.ash(f, pos, o)
	pos = vec(pos)
	if not pos then
		return nil
	end
	o = o or {}
	local fp = parentOf(f)
	local count = math.clamp(math.floor(o.count or 30), 1, 120)
	local radius = math.max(o.radius or 3, 0.1)
	local life = math.clamp(o.life or 2, 0.2, 6)
	local rise = o.rise or 4
	local host = FX.anchor(fp, pos, life + 0.15)
	host.Shape = BALL
	host.Size = Vector3.one * radius * 2
	local common = { Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Rotation = NumberRange.new(0, 360), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(180, 180) }
	local function burst(props, n)
		for k, v in pairs(common) do
			if props[k] == nil then
				props[k] = v
			end
		end
		local e = FX.emitter(host, props)
		e:Emit(n)
	end
	burst({ Texture = TEX.smoke, Color = cs(o.color or PAL.Black, PAL.Smoke), LightEmission = 0, LightInfluence = 0.4,
		Size = nsk({ { 0, 0.42 }, { 0.5, 0.34 }, { 1, 0.12 } }), Squash = nsk({ { 0, 0.7 }, { 0.5, -0.4 }, { 1, 0.6 } }),
		Transparency = tseq({ { 0, 0.05 }, { 0.75, 0.25 }, { 1, 1 } }), Lifetime = NumberRange.new(life * 0.6, life),
		Speed = NumberRange.new(0.5, 2.5), Drag = 1.2, Acceleration = Vector3.new(rng:NextNumber(-1, 1), rise * 0.9, rng:NextNumber(-1, 1)),
		RotSpeed = NumberRange.new(-320, 320) }, count)
	burst({ Texture = FLARE, Color = cs(o.color2 or PAL.Ember, PAL.Crimson), Brightness = 2.5,
		Size = nsk({ { 0, 0.3 }, { 1, 0 } }), Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(life * 0.4, life * 0.8), Speed = NumberRange.new(1, 4), Drag = 1.5,
		Acceleration = Vector3.new(0, rise * 1.4 + 2, 0), RotSpeed = NumberRange.new(-200, 200) }, math.max(1, math.floor(count * 0.4)))
	return host
end

---------------------------------------------------------------------------------------------------
-- shards(f, pos, o?): flying shards (the hollow mask's bone, the cleaver's steel) - thin tumbling wedges on a
-- simulated arc (anchored, one Heartbeat driver), a glint burst at the source. o = { count = 10, color = Bone,
-- material = SmoothPlastic, size = 0.4, speed = { 15, 35 }, life = 0.9, dir = nil (radial) or Vector3 (a 50 deg cone),
-- gravity = 60 }
function S.shards(f, pos, o)
	pos = vec(pos)
	if not pos then
		return
	end
	o = o or {}
	local fp = parentOf(f)
	local count = math.clamp(math.floor(o.count or 10), 1, 40)
	if crowded(fp, 300) then
		count = math.max(2, math.floor(count / 2))
	end
	local color = o.color or PAL.Bone
	local mat = o.material or PLASTIC
	local size = math.max(o.size or 0.4, 0.03)
	local spd = o.speed or { 15, 35 }
	local life = math.clamp(o.life or 0.9, 0.1, 4)
	local g = o.gravity or 60
	local dir = typeof(o.dir) == "Vector3" and o.dir.Magnitude > 1e-3 and o.dir.Unit or nil
	local folder = Instance.new("Folder")
	folder.Name = "Shards"
	local list, parts, cfs = {}, {}, {}
	for i = 1, count do
		local v
		if dir then
			local r, u = FX.perp(dir)
			local ang = rng:NextNumber(0, TAU)
			local off = math.tan(math.rad(rng:NextNumber(0, 50)))
			v = (dir + (r * math.cos(ang) + u * math.sin(ang)) * off).Unit
		else
			v = FX.randUnit()
			v = Vector3.new(v.X, math.abs(v.Y) * 0.8 + 0.2, v.Z).Unit
		end
		local s = size * rng:NextNumber(0.6, 1.3)
		local w = Instance.new("WedgePart")
		w.Name = "Shard"
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
		w.Material = mat
		w.Color = color:Lerp(i % 3 == 0 and WHITE or BLACK, rng:NextNumber(0, 0.12))
		w.Size = Vector3.new(s * 0.18, s * rng:NextNumber(0.8, 1.6), s)
		local cf = CFrame.new(pos + v * rng:NextNumber(0, size)) * CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
		w.CFrame = cf
		w.Parent = folder
		table.insert(list, { v = v * rng:NextNumber(spd[1], spd[2]), spin = FX.randUnit() * rng:NextNumber(8, 20),
			cf = cf, l = life * rng:NextNumber(0.7, 1) })
		table.insert(parts, w)
		table.insert(cfs, cf)
	end
	folder.Parent = fp
	FX.sparks(fp, pos, { dir = dir, count = math.min(count, 10), color = WHITE, color2 = color, speed = { 10, 25 },
		size = 0.4, life = 0.35 })
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - t0
		if t > life or not folder.Parent then
			conn:Disconnect()
			folder:Destroy()
			return
		end
		for i, st in ipairs(list) do
			st.v += Vector3.new(0, -g * dt, 0)
			st.v *= 1 - 0.6 * dt
			st.cf = (st.cf + st.v * dt) * CFrame.fromAxisAngle(st.spin.Unit, st.spin.Magnitude * dt)
			cfs[i] = st.cf
			local k = math.clamp((t / st.l - 0.6) / 0.4, 0, 1)
			parts[i].Transparency = k
		end
		workspace:BulkMoveTo(parts, cfs, BULK)
	end)
	Debris:AddItem(folder, life + 0.3)
	return folder
end

---------------------------------------------------------------------------------------------------
-- pillar(f, pos, o?) -> Pillar: the Bankai column (DESIGN section 9). A black core column inside a crimson
-- ForceField skin and a soft Neon glow shell (4 stacked sections, thinner toward the sky), four crimson rim strips
-- spiralling up it, black flame columns + crimson licks + embers streaming up inside, a scorch disc and a ring of
-- crimson fire at its foot, a crimson light. Built invisible; :erupt() raises it in 0.25 s with a radial pop;
-- :dissolve(t = 0.6) breaks it apart from the base up into black feathers and embers; :Destroy(); .parts.
-- White/black-out guards: any camera nearer than radius + 33 to its axis thins the Neon/ForceField layers, a camera
-- inside the core sees it at >= 0.7; with o.localFade every part is drawn at >= 0.55 while the camera is within
-- radius + 11 (and the inner smoke thins). It dissolves itself at 7.2 s and is gone by 8 s.
-- o = { radius = 7, height = 120, localFade = false }
local Pillar = {}
Pillar.__index = Pillar
local PILLAR_SECTIONS = 4
local STRIPS, STRIP_SEG = 4, 10
function S.pillar(f, pos, o)
	pos = vec(pos)
	if not pos then
		return dummy({ parts = {} })
	end
	o = o or {}
	local fp = parentOf(f)
	local R = math.max(o.radius or 7, 1)
	local H = math.max(o.height or 120, 10)
	local self = setmetatable({
		pos = pos, R = R, H = H, localFade = o.localFade == true, parts = {}, layers = {}, strips = {}, ems = {},
		state = "idle", t0 = os.clock(), dead = false, near = false, guard = 0, sizes = true,
	}, Pillar)
	local folder = Instance.new("Folder")
	folder.Name = "Pillar"
	self.folder = folder
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's X axis onto world Y
	self.upright = upright
	local hidden = Vector3.new(0.1, 0.1, 0.1)
	-- sections: { p, rMul (of R), base transparency, kind, s (1..4) }
	for s = 1, PILLAR_SECTIONS do
		local k = (s - 1) / (PILLAR_SECTIONS - 1)
		for _, spec in ipairs({
			{ "PillarCore", PLASTIC, PAL.Black, 0.62, 0.1 + 0.25 * k, "core" },
			{ "PillarSkin", FIELD, PAL.Crimson, 1.0, 0.3 + 0.25 * k, "skin" },
			{ "PillarGlow", NEON, PAL.Crimson, 1.07, 0.8 + 0.1 * k, "glow" },
		}) do
			local p = newPart(spec[1], spec[2], spec[3], hidden, CFrame.new(pos), 1, folder, CYL)
			table.insert(self.layers, { p = p, rMul = spec[4], base = spec[5], kind = spec[6], s = s })
			table.insert(self.parts, p)
		end
	end
	-- the foot: a dark scorch disc and a ring of crimson fire
	self.scorch = newPart("PillarScorch", PLASTIC, PAL.Black, Vector3.new(0.12, R * 3.4, R * 3.4),
		CFrame.new(pos + UP * 0.06) * upright, 1, folder, CYL)
	self.footRing = newPart("PillarFoot", NEON, PAL.Crimson, Vector3.new(0.2, R * 2.5, R * 2.5),
		CFrame.new(pos + UP * 0.12) * upright, 1, folder, CYL)
	table.insert(self.parts, self.scorch)
	table.insert(self.parts, self.footRing)
	-- rim strips: helices up the skin
	for i = 1, STRIPS do
		local st = { phase = (i - 1) / STRIPS * TAU, segs = {} }
		for j = 1, STRIP_SEG do
			local p = newPart("PillarStrip", NEON, j <= 3 and PAL.Ember or PAL.Crimson, hidden, CFrame.new(pos), 1, folder)
			table.insert(st.segs, { p = p, j = j, base = 0.05 + 0.6 * (j - 1) / (STRIP_SEG - 1) })
			table.insert(self.parts, p)
		end
		table.insert(self.strips, st)
	end
	self.stripParts, self.stripCFs = {}, {}
	for _, st in ipairs(self.strips) do
		for _, sg in ipairs(st.segs) do
			table.insert(self.stripParts, sg.p)
			table.insert(self.stripCFs, CFrame.new(pos))
		end
	end
	-- the flame columns streaming up inside, from a cylinder host at the foot
	local host = newPart("PillarHost", PLASTIC, WHITE, Vector3.new(R * 1.1, 2, R * 1.1), CFrame.new(pos + UP * 1), 1, folder)
	self.host = host
	local common = { Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360), Rate = 0 }
	local function put(props, rate, smoke)
		for k, v in pairs(common) do
			if props[k] == nil then
				props[k] = v
			end
		end
		local e = FX.emitter(host, props)
		table.insert(self.ems, { e = e, rate = rate, smoke = smoke, tr = props.Transparency })
	end
	local hk = H / 120
	put({ Texture = TEX.smoke, Color = cs(PAL.Smoke, PAL.Black), LightEmission = 0, LightInfluence = 0.25,
		Size = nsk({ { 0, R * 0.45 }, { 0.5, R * 0.75 }, { 1, R * 0.55 } }), Transparency = tseq({ { 0, 0.4 }, { 0.6, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.1, 1.5), Speed = NumberRange.new(70 * hk, 100 * hk), SpreadAngle = Vector2.new(5, 5),
		RotSpeed = NumberRange.new(-60, 60) }, 55, true)
	put({ Texture = FIRE, Color = cs(PAL.Ember, PAL.Crimson), Brightness = 2.4, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = nsk({ { 0, -1.2 }, { 1, -0.6 } }), Size = nsk({ { 0, R * 0.3 }, { 0.4, R * 0.5 }, { 1, 0 } }),
		Transparency = tseq({ { 0, 0.25 }, { 0.5, 0.35 }, { 1, 1 } }), Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(80 * hk, 120 * hk), SpreadAngle = Vector2.new(4, 4), ZOffset = 0.5 }, 60, false)
	put({ Texture = FLARE, Color = cs(PAL.Ember, PAL.Crimson), Brightness = 2.5, Size = nsk({ { 0, 0.8 }, { 1, 0 } }),
		Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(40 * hk, 90 * hk), SpreadAngle = Vector2.new(22, 22), RotSpeed = NumberRange.new(-200, 200) }, 35, false)
	-- feathers for the dissolve (one host, moved between bursts that land on different frames)
	local fh = newPart("PillarFeatherHost", PLASTIC, WHITE, Vector3.new(R * 2, H / PILLAR_SECTIONS, R * 2), CFrame.new(pos), 1, folder)
	self.featherHost = fh
	local fcommon = { Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward, Rotation = NumberRange.new(0, 360), Rate = 0 }
	local function fput(props)
		for k, v in pairs(fcommon) do
			if props[k] == nil then
				props[k] = v
			end
		end
		return FX.emitter(fh, props)
	end
	self.feathers = fput({ Texture = TEX.smoke, Color = cs(PAL.Black, PAL.Smoke), LightEmission = 0, LightInfluence = 0.4,
		Size = nsk({ { 0, 1.1 }, { 0.5, 0.8 }, { 1, 0.3 } }), Squash = nsk({ { 0, 0.8 }, { 0.5, -0.5 }, { 1, 0.7 } }),
		Transparency = tseq({ { 0, 0.05 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(1.0, 1.8),
		Speed = NumberRange.new(6, 18), Drag = 1.4, Acceleration = Vector3.new(0, -5, 0), RotSpeed = NumberRange.new(-300, 300) })
	self.featherEmbers = fput({ Texture = FLARE, Color = cs(PAL.Ember, PAL.Crimson), Brightness = 2.5,
		Size = nsk({ { 0, 0.6 }, { 1, 0 } }), Transparency = tseq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(8, 24), Drag = 1.5, Acceleration = Vector3.new(0, 6, 0),
		RotSpeed = NumberRange.new(-200, 200) })
	local l = Instance.new("PointLight")
	l.Color = PAL.Crimson
	l.Brightness = 0
	l.Range = 50
	l.Shadows = false
	l.Parent = host
	self.light = l
	folder.Parent = fp
	self.conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	task.delay(MAX_LIFE - 0.8, function()
		if not self.dead and self.state ~= "dissolve" then
			self:dissolve(0.5)
		end
	end)
	task.delay(MAX_LIFE, function()
		self:Destroy()
		self.folder:Destroy()
	end)
	return self
end
function Pillar:erupt()
	if self.dead or self.state ~= "idle" then
		return
	end
	self.state = "erupt"
	self.te = os.clock()
	for _, em in ipairs(self.ems) do
		em.e.Rate = em.rate
	end
	self.light.Brightness = 3
end
function Pillar:dissolve(t)
	if self.dead or self.state == "dissolve" then
		return
	end
	if self.state == "idle" then
		self:Destroy()
		return
	end
	self.state = "dissolve"
	self.td = os.clock()
	self.dur = math.clamp(tonumber(t) or 0.6, 0.05, 3)
	self.bursts = {}
	for s = 1, PILLAR_SECTIONS do
		table.insert(self.bursts, { at = self.dur * 0.6 * (s - 1) / PILLAR_SECTIONS, s = s })
	end
	for _, em in ipairs(self.ems) do
		em.e.Rate = 0
	end
	tween(self.light, self.dur, { Brightness = 0 })
end
function Pillar:_step()
	if self.dead then
		return
	end
	if not self.folder.Parent then
		self:Destroy()
		return
	end
	if self.state == "idle" then
		return
	end
	local R, H, pos = self.R, self.H, self.pos
	local tnow = os.clock()
	local t = tnow - self.te
	-- the column's live height and radius pop
	local rise = math.clamp(t / 0.25, 0, 1)
	local hc = H * (1 - (1 - rise) ^ 3)
	local pop = 1
	if t < 0.25 then
		pop = 0.35 + 0.65 * rise
	elseif t < 0.5 then
		local k = (t - 0.25) / 0.25
		pop = 1 + 0.16 * math.sin(k * math.pi) * (1 - k * 0.3)
	end
	-- the dissolve: each section fades and blows outward, bottom first
	local dk = {}
	if self.state == "dissolve" then
		local td = tnow - self.td
		for s = 1, PILLAR_SECTIONS do
			local start = self.dur * 0.6 * (s - 1) / PILLAR_SECTIONS
			dk[s] = math.clamp((td - start) / (self.dur * 0.5), 0, 1)
		end
		-- one feather burst per frame at most (one host, moved)
		local b = self.bursts[1]
		if b and td >= b.at then
			table.remove(self.bursts, 1)
			local y0 = (b.s - 0.5) / PILLAR_SECTIONS * H
			self.featherHost.CFrame = CFrame.new(pos + UP * y0)
			self.feathers:Emit(14)
			self.featherEmbers:Emit(10)
		end
		if td > self.dur + 0.2 and #self.bursts == 0 then
			self:Destroy(1.8)
			return
		end
	end
	-- camera guards
	local cam = camCF().Position
	local dxz = Vector3.new(cam.X - pos.X, 0, cam.Z - pos.Z).Magnitude
	local inHeight = cam.Y > pos.Y - 6 and cam.Y < pos.Y + hc + 6
	local near = self.localFade and inHeight and dxz < R + 11
	local guard = inHeight and math.clamp((R + 33 - dxz) / 26, 0, 1) or 0
	local inCore = inHeight and dxz < R * 0.62 + 3
	if near ~= self.near then
		self.near = near
		for _, em in ipairs(self.ems) do
			if em.smoke then
				em.e.Transparency = near and tseq({ { 0, 0.78 }, { 0.6, 0.85 }, { 1, 1 } }) or em.tr
				if self.state ~= "dissolve" then
					em.e.Rate = near and em.rate * 0.4 or em.rate
				end
			end
		end
	end
	local floorT = near and 0.55 or 0
	local secH = H / PILLAR_SECTIONS
	local breathe = 1 + 0.025 * math.sin(tnow * 9)
	for _, L in ipairs(self.layers) do
		local y0, y1 = (L.s - 1) * secH, math.min(L.s * secH, hc)
		local p = L.p
		local d = dk[L.s] or 0
		if y1 - y0 < 0.05 or d >= 1 then
			p.Transparency = 1
		else
			local r = R * L.rMul * pop * (1 + 0.3 * d) * (L.kind == "glow" and breathe or 1)
			local hgt = (y1 - y0) * (1 - 0.15 * d)
			p.Size = Vector3.new(hgt, r * 2, r * 2)
			p.CFrame = CFrame.new(pos + UP * ((y0 + y1) / 2 + (y1 - y0) * 0.1 * d)) * self.upright
			local tr = L.base
			if L.kind == "core" then
				if inCore then
					tr = math.max(tr, 0.7)
				end
			else
				tr = tr + (0.88 - tr) * guard * 0.8
			end
			tr = math.max(tr, floorT)
			p.Transparency = tr + (1 - tr) * d
		end
	end
	local d1 = dk[1] or 0
	self.scorch.Transparency = math.max(0.2 + 0.8 * d1, floorT)
	self.footRing.Transparency = math.max(0.35 + 0.65 * d1, floorT, 0.35 + 0.5 * guard)
	local fr = R * 2.5 * pop * (1 + 0.2 * math.sin(tnow * 14))
	self.footRing.Size = Vector3.new(0.2, fr, fr)
	-- the rim strips climb: phase advances, segments follow a helix two turns over the height
	local idx = 0
	local twist = 1.25 * TAU / H
	local spin = tnow * 2.6
	local sl = hc / STRIP_SEG
	local rr = R * 1.015 * pop
	for _, st in ipairs(self.strips) do
		for _, sg in ipairs(st.segs) do
			idx += 1
			local ya, yb = (sg.j - 1) * sl, sg.j * sl
			local aa, ab = st.phase + ya * twist + spin, st.phase + yb * twist + spin
			local pa = pos + Vector3.new(math.cos(aa) * rr, ya, math.sin(aa) * rr)
			local pb = pos + Vector3.new(math.cos(ab) * rr, yb, math.sin(ab) * rr)
			local seg = pb - pa
			local L = seg.Magnitude
			if L < 0.05 then
				self.stripCFs[idx] = CFrame.new(pa)
				sg.p.Transparency = 1
			else
				self.stripCFs[idx] = CFrame.lookAt((pa + pb) / 2, pb)
				sg.p.Size = Vector3.new(0.4, 0.4, L + 0.4)
				local sec = math.clamp(math.ceil((ya + yb) / 2 / secH), 1, PILLAR_SECTIONS)
				local d = dk[sec] or 0
				local tr = math.max(sg.base + (0.9 - sg.base) * guard * 0.6, floorT)
				sg.p.Transparency = tr + (1 - tr) * d
			end
		end
	end
	workspace:BulkMoveTo(self.stripParts, self.stripCFs, BULK)
end
function Pillar:Destroy(linger)
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if type(linger) == "number" and linger > 0 and self.folder.Parent then
		linger = math.min(linger, math.max(MAX_LIFE - (os.clock() - self.t0), 0.05))
		for _, p in ipairs(self.parts) do
			p.Transparency = 1
		end
		for _, em in ipairs(self.ems) do
			em.e.Enabled = false
		end
		Debris:AddItem(self.folder, linger)
	else
		self.folder:Destroy()
	end
end
Pillar.destroy = Pillar.Destroy

---------------------------------------------------------------------------------------------------
-- dust (copied from OneForAllKit.Client.Shared: same signatures and behaviour). groundColor(hit) -> colour,
-- material. dust(f, pos, vel, o) with o: s0 4, s1 12, count 2, life {1.4, 2.2} (or a number), color (default: the
-- ground under pos). dustLine / dustRing take the same `o` as their last argument; a negative speed rolls inward.
function S.groundColor(hit)
	local mat, col = Enum.Material.Slate, C(110, 104, 98)
	if not hit or not hit.Instance then
		return col, mat
	end
	if hit.Instance:IsA("Terrain") then
		local c = FX.terrainOriginals and FX.terrainOriginals[hit.Material]
		if not c then
			local ok, lc = pcall(function()
				return workspace.Terrain:GetMaterialColor(hit.Material)
			end)
			c = ok and lc or nil
		end
		if c then
			col = c
		end
		mat = hit.Material
		if mat == Enum.Material.Grass or mat == Enum.Material.LeafyGrass then
			mat, col = Enum.Material.Ground, C(104, 84, 62) -- turf tears up as dirt
		end
	elseif hit.Instance:IsA("BasePart") then
		mat, col = hit.Instance.Material, hit.Instance.Color
	end
	return col, mat
end

function S.dust(f, pos, vel, o)
	pos = vec(pos)
	if not pos then
		return
	end
	o = o or {}
	local fp = parentOf(f)
	vel = typeof(vel) == "Vector3" and vel or UP * 6
	local c = o.color or S.groundColor(FX.groundHit(pos, 8))
	local life = o.life or { 1.4, 2.2 }
	if type(life) == "number" then
		life = { life * 0.75, life }
	end
	local host = FX.anchor(fp, pos, life[2] + 0.6)
	local a = Instance.new("Attachment")
	a.CFrame = FX.yAlong(vel)
	a.Parent = host
	local spd = vel.Magnitude
	local s0, s1 = o.s0 or 4, o.s1 or 12
	local e = FX.emitter(a, {
		Texture = TEX.smoke, Color = cs(c, c:Lerp(BLACK, 0.25)), LightInfluence = 1, LightEmission = 0,
		Size = nsk({ { 0, s0 }, { 0.35, s1 * 0.8 }, { 1, s1 } }), Transparency = nsk({ { 0, 0.3 }, { 0.5, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(life[1], life[2]), Speed = NumberRange.new(spd * 0.8, spd * 1.2),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(18, 18), Drag = 1.6,
		Acceleration = Vector3.new(0, 3, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
	})
	e:Emit(o.count or 2)
	return host
end

-- the rolling dust wall: n puffs across `width`, perpendicular to dir, at ground level
function S.dustLine(f, center, dir, width, n, speed, o)
	center = vec(center)
	if not center then
		return
	end
	local fd = flat(dir, Vector3.new(0, 0, -1))
	local side = Vector3.new(-fd.Z, 0, fd.X)
	n = math.max(math.floor(n or 4), 1)
	width = width or 10
	speed = speed or 70
	for i = 1, n do
		local k = (n == 1) and 0 or ((i - 1) / (n - 1) - 0.5)
		local p = center + side * (k * width) + fd * rng:NextNumber(-1, 1)
		local hit = FX.groundHit(p, 12)
		S.dust(f, (hit and hit.Position or p) + UP * 0.5, fd * speed + UP * 6, o)
	end
end

-- the dust doughnut: n puffs round a circle rolling outward (a negative speed: inward)
function S.dustRing(f, center, radius, n, speed, o)
	center = vec(center)
	if not center then
		return
	end
	n = math.max(math.floor(n or 8), 1)
	radius = radius or 3
	speed = speed or 40
	local off = rng:NextNumber(0, TAU)
	for i = 1, n do
		local ang = off + (i / n) * TAU + rng:NextNumber(-0.15, 0.15)
		local radial = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p = center + radial * radius
		local hit = FX.groundHit(p, 12)
		S.dust(f, (hit and hit.Position or p) + UP * 0.5, radial * speed + UP * 5, o)
	end
end

---------------------------------------------------------------------------------------------------
-- steam(part, rate, o?) -> handle (copied from OneForAllKit.Client.Shared): h:Emit(n) (a puff), h.Rate /
-- h:setRate(r), h:stop() / h:Destroy() (Rate 0, the attachment Debris'd after 1.5 s), h:kill() (now), h.Attachment,
-- h.Emitter. A handle made with rate 0 that is never given a rate stops itself after 3 s. Added: o = { color,
-- black = false } (black: dark Smoke wisps for the Bankai look). Any handle stops itself after 8 s.
local Steam = {}
local SteamMT = {}
SteamMT.__index = function(t, k)
	if k == "Rate" then
		local e = rawget(t, "Emitter")
		return e and e.Rate or 0
	end
	return Steam[k]
end
SteamMT.__newindex = function(t, k, v)
	if k == "Rate" then
		Steam.setRate(t, v)
	else
		rawset(t, k, v)
	end
end
function Steam.Emit(self, n)
	local e = rawget(self, "Emitter")
	if e and e.Parent then
		e:Emit(n or 10)
	end
end
Steam.emit = Steam.Emit
function Steam.setRate(self, r)
	if rawget(self, "dead") then
		return
	end
	r = math.max(r or 0, 0)
	if r > 0 then
		rawset(self, "auto", false)
	end
	local e = rawget(self, "Emitter")
	if e then
		e.Rate = r
	end
end
function Steam.stop(self)
	if rawget(self, "dead") then
		return
	end
	rawset(self, "dead", true)
	local e, a = rawget(self, "Emitter"), rawget(self, "Attachment")
	if e then
		e.Rate = 0
	end
	if a then
		Debris:AddItem(a, 1.5)
	end
end
Steam.Destroy, Steam.destroy = Steam.stop, Steam.stop
function Steam.kill(self)
	rawset(self, "dead", true)
	local a = rawget(self, "Attachment")
	if a then
		a:Destroy()
	end
end

function S.steam(part, rate, o)
	local h = setmetatable({}, SteamMT)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		rawset(h, "dead", true)
		return h
	end
	o = o or {}
	local black = o.black == true
	local col = o.color or (black and PAL.Smoke or PAL.Steam)
	local att = Instance.new("Attachment")
	att.Name = "ZangetsuSteam"
	local e = FX.emitter(att, {
		Texture = TEX.smoke, Color = cs(col, black and PAL.Black or C(170, 170, 170)), LightInfluence = black and 0.4 or 1,
		LightEmission = 0, Size = nsk({ { 0, 0.6 }, { 0.4, 1.6 }, { 1, 2.6 } }),
		Transparency = nsk({ { 0, black and 0.45 or 0.55 }, { 0.5, 0.7 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 6, 0), Drag = 1, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		Rate = 0,
	})
	att.Parent = part
	rawset(h, "Attachment", att)
	rawset(h, "Emitter", e)
	rawset(h, "part", part)
	Steam.setRate(h, rate or 0)
	if (rate or 0) <= 0 then
		rawset(h, "auto", true)
		task.delay(3, function()
			if rawget(h, "auto") then
				Steam.stop(h)
			end
		end)
	end
	task.delay(MAX_LIFE - 1.6, function()
		Steam.stop(h)
	end)
	return h
end

return S
