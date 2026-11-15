--!nocheck
-- GomuKit.Client.Shared: the STRETCH library and the pure effect builders of the Gomu kit (LUFFY), luffy/CONTRACT.md
-- section 6. No input, HUD, camera or movement state lives here: every function draws something in the world and
-- cleans itself up. Everything is client-side, anchored (the copied dust / rubble aside), non-colliding, non-querying,
-- CastShadow false, parented under the caller's folder (nil -> S.Folder -> workspace.LocalFX.Gomu). Nothing errors on
-- a missing character / limb / ground: a builder returns nil or a dummy handle whose methods are no-ops (h.dead).
-- Every handle dies by itself within 8 s; a keep handle dies 6.8 s after its last :keep(). "alpha" = Transparency.
-- THE STRETCH (6.2): a rubber limb = SEGMENTS anchored Cylinders (+ ball joints) on a quadratic bezier from the
-- shoulder / hip rig attachment to a clone of the real Hand / Foot (the fist), drawn every RenderStepped at
-- Stretch.RenderPriority (Camera + 2, AFTER the camera module rewrites the local body's LocalTransparencyModifier),
-- with the real UpperArm / LowerArm / Hand hidden in that same step. One live handle per (character, limb). Every
-- client draws every caster's stretches (o.t0 catches a remote cast up), so remote casters look identical.
-- The helpers, ghosts, cracks, ground colour, dust and steam are copied from the Ichigo kit's Shared.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("GomuKit")
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
-- a copy of the base Config.Palette (Config.Palette overrides every entry it has), plus the template's colour names
-- that the copied builders read (Reiatsu / Frost / Crimson / Black / Smoke)
local PAL = {
	Skin = C(234, 184, 146), Vest = C(205, 28, 36), VestDark = C(130, 14, 22), Straw = C(244, 206, 92),
	StrawDark = C(190, 146, 52), Band = C(196, 22, 30), Denim = C(54, 96, 168), Rubber = C(255, 222, 200),
	Whoosh = C(255, 250, 240), Impact = C(255, 236, 160), Dust = C(150, 140, 125), Steam = C(245, 245, 245),
	Haki = C(22, 16, 24), HakiSheen = C(120, 70, 160), HakiBolt = C(220, 30, 50), HakiBolt2 = C(20, 0, 8),
	Nika = C(252, 252, 255), Cloud = C(236, 240, 255), Sun = C(255, 228, 140), SunHot = C(255, 190, 70),
	Toon = C(40, 30, 60), Lavender = C(214, 196, 255), Ink = C(18, 14, 18),
	Reiatsu = C(255, 250, 240), Frost = C(255, 250, 240), Crimson = C(205, 28, 36), Black = C(18, 14, 18),
	Smoke = C(70, 64, 66),
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
S.Folder = nil -- the scaffold sets it (workspace.LocalFX.Gomu)
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

-- the kit's own FX folder (the scaffold makes workspace.LocalFX.Gomu and sets S.Folder)
local function kitFolder()
	if live(S.Folder) then
		return S.Folder
	end
	local lfx = workspace:FindFirstChild("LocalFX")
	local f = lfx and lfx:FindFirstChild("Gomu")
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

S.now, S.camDist, S.flat, S.torsoOf, S.folder, S.camFacing = now, camDist, flat, torsoOf, kitFolder, camFacing

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
	f.Name = "GomuGhost"
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
-- cracks(f, pos, n, len, color, life, o?): glowing ground cracks spreading from pos (copied from the Ichigo kit)
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

local function steamOn(part, rate, o)
	local h = setmetatable({}, SteamMT)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		rawset(h, "dead", true)
		return h
	end
	o = o or {}
	local black = o.black == true
	local col = o.color or (black and PAL.Smoke or PAL.Steam)
	local att = Instance.new("Attachment")
	att.Name = "GomuSteam"
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
-- S.steam(partOrPos, rate, o?) -> handle: steam off a part, or off a point (an invisible host there)
function S.steam(target, rate, o)
	if typeof(target) == "Vector3" or typeof(target) == "CFrame" then
		local host = FX.anchor(kitFolder(), typeof(target) == "CFrame" and target or CFrame.new(target), MAX_LIFE)
		host.Name = "GomuSteamHost"
		return steamOn(host, rate, o)
	end
	return steamOn(target, rate, o)
end

---------------------------------------------------------------------------------------------------
-- THE STRETCH LIBRARY (CONTRACT 6.1 - 6.3)
local STR = type(CFG.Stretch) == "table" and CFG.Stretch or {}
local function snum(k, d)
	local v = STR[k]
	return type(v) == "number" and v or d
end
local SEGMENTS = math.clamp(math.floor(snum("Segments", 7)), 2, 16)
local KEEP_LIFE = MAX_LIFE - 1.2
local ROT90 = CFrame.Angles(0, math.rad(90), 0)

local Animator = nil
pcall(function()
	Animator = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
end)
local ClipsMod = nil
local function clipsTable()
	if ClipsMod == nil then
		ClipsMod = false
		local m = Kit:FindFirstChild("Clips")
		if m then
			local ok, c = pcall(require, m)
			if ok and type(c) == "table" then
				ClipsMod = c
			end
		end
	end
	return ClipsMod or nil
end

-- a positional one-shot sound on a part: id = a Config.Sounds key or an asset id string
local function sfx(id, parent, vol, speed)
	if typeof(parent) ~= "Instance" or not parent.Parent then
		return nil
	end
	local sid = id
	if type(id) == "string" and type(CFG.Sounds) == "table" and type(CFG.Sounds[id]) == "string" then
		sid = CFG.Sounds[id]
	end
	if type(sid) ~= "string" or sid == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = sid
	s.Volume = tonumber(vol) or 0.6
	s.PlaybackSpeed = tonumber(speed) or 1
	s.RollOffMinDistance = 20
	s.RollOffMaxDistance = 300
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 6)
	return s
end
S.sfx = sfx

-- a dot-style handle method may be called with a colon too (h:set(x) as well as h.set(x))
local function arg1(h, a, b)
	if a == h then
		return b
	end
	return a
end

-- 6.1 limbs ---------------------------------------------------------------------------------------
local LIMB_PARTS = {
	R = { "RightUpperArm", "RightLowerArm", "RightHand", r6 = "Right Arm" },
	L = { "LeftUpperArm", "LeftLowerArm", "LeftHand", r6 = "Left Arm" },
	RL = { "RightUpperLeg", "RightLowerLeg", "RightFoot", r6 = "Right Leg" },
	LL = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", r6 = "Left Leg" },
}
local function normLimb(limb)
	if LIMB_PARTS[limb] then
		return limb
	end
	if limb == "Right" or limb == "RA" then
		return "R"
	elseif limb == "Left" or limb == "LA" then
		return "L"
	end
	return nil
end
local function isLeg(limb)
	return limb == "RL" or limb == "LL"
end
S.normLimb = normLimb

-- S.limbParts(char, limb) -> upper, lower, tip (R6: the single limb part as all three) | nil
function S.limbParts(char, limb)
	limb = normLimb(limb)
	if typeof(char) ~= "Instance" or not limb then
		return nil
	end
	local names = LIMB_PARTS[limb]
	local u, l, t = char:FindFirstChild(names[1]), char:FindFirstChild(names[2]), char:FindFirstChild(names[3])
	if u and l and t and u:IsA("BasePart") and l:IsA("BasePart") and t:IsA("BasePart") then
		return u, l, t
	end
	local r6 = char:FindFirstChild(names.r6)
	if r6 and r6:IsA("BasePart") then
		return r6, r6, r6
	end
	return nil
end

-- S.limbRoot(char, limb) -> CFrame: the shoulder / hip rig attachment's world CFrame (the server's S.limbRoot points)
function S.limbRoot(char, limb)
	limb = normLimb(limb) or "R"
	if typeof(char) ~= "Instance" then
		return nil
	end
	local leg = isLeg(limb)
	local right = (limb == "R" or limb == "RL")
	local torso = char:FindFirstChild(leg and "LowerTorso" or "UpperTorso")
	if torso and torso:IsA("BasePart") then
		local a = torso:FindFirstChild((right and "Right" or "Left") .. (leg and "HipRigAttachment" or "ShoulderRigAttachment"))
		if a and a:IsA("Attachment") then
			return a.WorldCFrame
		end
	end
	local sx = right and 1 or -1
	local t6 = char:FindFirstChild("Torso")
	if t6 and t6:IsA("BasePart") then
		return t6.CFrame * (leg and CFrame.new(0.5 * sx, -1, 0) or CFrame.new(sx, 0.5, 0))
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.CFrame * (leg and CFrame.new(0.5 * sx, -1, 0) or CFrame.new(1.5 * sx, 0.5, 0))
	end
	return nil
end

-- S.limbColor(char, limb) -> skin, sleeve|nil (sleeve = the upper part's colour when it clearly differs)
function S.limbColor(char, limb)
	local u, l = S.limbParts(char, limb)
	if not l then
		return PAL.Skin, nil
	end
	local skin = l.Color
	local sleeve = nil
	if u ~= l then
		local c = u.Color
		if math.abs(c.R - skin.R) + math.abs(c.G - skin.G) + math.abs(c.B - skin.B) > 0.08 then
			sleeve = c
		end
	end
	return skin, sleeve
end

-- the fist: a clone of the real Hand (Foot) stripped to its mesh, or a ball on R6 / when it cannot be cloned
local KEEP_KIDS = { SpecialMesh = true, SurfaceAppearance = true }
local function makeFist(tip, o)
	local fist
	if tip and tip.Size.Y <= 1.6 then
		local ok, c = pcall(function()
			local was = tip.Archivable
			tip.Archivable = true
			local cl = tip:Clone()
			tip.Archivable = was
			return cl
		end)
		if ok and c then
			for _, ch in ipairs(c:GetChildren()) do
				if not KEEP_KIDS[ch.ClassName] then
					ch:Destroy()
				end
			end
			fist = c
		end
	end
	if not fist then
		fist = FX.part("GomuFist", BALL, PLASTIC, (tip and tip.Color) or PAL.Skin, nil)
		fist.Size = Vector3.one * 1.05
	end
	fist.Name = "GomuFist"
	fist.Anchored = true
	fist.CanCollide = false
	fist.CanQuery = false
	fist.CanTouch = false
	fist.CastShadow = false
	fist.Massless = true
	fist.Transparency = 0
	fist.LocalTransparencyModifier = 0
	local recolor = (o.white and PAL.Nika) or (o.haki and PAL.Haki) or o.color
	local mesh = fist:FindFirstChildOfClass("SpecialMesh")
	if recolor then
		fist.Color = recolor
		pcall(function()
			fist.Material = PLASTIC
		end)
		pcall(function()
			if fist:IsA("MeshPart") then
				fist.TextureID = ""
			end
		end)
		local sa = fist:FindFirstChildOfClass("SurfaceAppearance")
		if sa then
			sa:Destroy()
		end
		if mesh then
			pcall(function()
				mesh.TextureId = ""
			end)
		end
		if o.haki then
			fist.Reflectance = 0.18
		end
	end
	local s = fist.Size
	local base = Vector3.new(math.max(s.X, 0.85), math.max(s.Y, 0.85), math.max(s.Z, 0.85))
	return fist, base, mesh, mesh and mesh.Scale or nil
end

local function easeBackOut(k, s)
	local x = k - 1
	return 1 + (s + 1) * x * x * x + s * x * x
end
local function elasticOut(k)
	if k <= 0 then
		return 0
	elseif k >= 1 then
		return 1
	end
	return 2 ^ (-10 * k) * math.sin((k * 10 - 0.75) * (TAU / 3)) + 1
end

-- a stretch target: Vector3 | CFrame | BasePart | Attachment | Model (its torso) | function() -> any of those
local function resolve(t, depth)
	local ty = typeof(t)
	if ty == "Vector3" then
		return t
	elseif ty == "CFrame" then
		return t.Position
	elseif ty == "Instance" then
		if not t.Parent then
			return nil
		end
		if t:IsA("BasePart") then
			return t.Position
		elseif t:IsA("Attachment") then
			return t.WorldPosition
		elseif t:IsA("Model") then
			local tp = torsoOf(t)
			return (tp and tp.Parent) and tp.Position or nil
		end
		return nil
	elseif ty == "function" and (depth or 0) < 2 then
		local ok, v = pcall(t)
		if ok then
			return resolve(v, (depth or 0) + 1)
		end
	end
	return nil
end
S.resolveTarget = resolve

-- 6.2 the stretch handle ---------------------------------------------------------------------------
local handles = {} -- [h] = true: every live stretch
local byLimb = setmetatable({}, { __mode = "k" }) -- [char] = { [limb] = h }: one live handle per limb
local Stretch = {}
Stretch.__index = Stretch

local function deadStretch()
	return setmetatable({ dead = true, parts = {} }, Stretch)
end
S.deadStretch = deadStretch

local function newStretch(char, limb, target, o)
	o = type(o) == "table" and o or {}
	limb = normLimb(limb)
	if typeof(char) ~= "Instance" or not char.Parent or not limb then
		return deadStretch()
	end
	local upper, lower, tip = S.limbParts(char, limb)
	local rootCF = S.limbRoot(char, limb)
	if not upper or not rootCF then
		return deadStretch()
	end
	local clock = os.clock()
	local out = math.max(tonumber(o.out) or snum("Out", 0.12), 0.01)
	local hold = math.max(tonumber(o.hold) or snum("Hold", 0.05), 0)
	local back = math.max(tonumber(o.back) or snum("Back", 0.16), 0.01)
	local t0 = tonumber(o.t0) or clock
	if t0 > clock + 1 or t0 < clock - 60 then
		t0 = clock -- a server-time value passed by mistake: start now
	end
	if not o.keep and clock - t0 >= out + hold + back then
		return deadStretch() -- a remote cast that is already over
	end
	local per = byLimb[char]
	if not per then
		per = {}
		byLimb[char] = per
	end
	local old = per[limb]
	if old and not old.dead then
		old:destroy() -- instantly, no snap-back (fast jabs / the Gatling alternate L / R); restores the real limb first
	end
	local leg = isLeg(limb)
	local skin, sleeve = S.limbColor(char, limb)
	local color = o.color or (o.white and PAL.Nika) or skin or PAL.Skin
	if o.sleeve == false or o.white or o.color then
		sleeve = nil
	end
	local model = Instance.new("Model")
	model.Name = "GomuStretch_" .. limb
	local segs, joints = {}, {}
	local function colourAt(u)
		if o.haki and u > 0.55 then
			return PAL.Haki
		end
		return (sleeve and u < 1 / 3) and sleeve or color
	end
	for i = 1, SEGMENTS do
		local u = (i - 0.5) / SEGMENTS
		local p = newPart("Rubber", PLASTIC, colourAt(u), Vector3.new(1, 0.6, 0.6), nil, 0, model, CYL)
		if o.haki and u > 0.55 then
			p.Reflectance = 0.15
		end
		segs[i] = p
		if i < SEGMENTS then
			joints[i] = newPart("RubberJoint", PLASTIC, colourAt(i / SEGMENTS), Vector3.one * 0.6, nil, 0, model, BALL)
		end
	end
	local fist, fbase, fmesh, fmeshBase = makeFist(tip, o)
	fist.Parent = model
	local hidden = {}
	for _, p in ipairs({ upper, lower, tip }) do
		if hidden[p] == nil then
			hidden[p] = p.LocalTransparencyModifier
		end
	end
	local fs = tonumber(o.fistScale) or snum("FistScale", 1.15)
	local h = setmetatable({
		dead = false, char = char, limb = limb, leg = leg, upper = upper, lower = lower, tipPart = tip,
		hrp = char:FindFirstChild("HumanoidRootPart"), model = model, segs = segs, joints = joints, fist = fist,
		fistBase = fbase, fistMesh = fmesh, fistMeshBase = fmeshBase, hidden = hidden,
		target = target, lastT = nil, from = tip.Position, P = tip.Position,
		state = "out", sT0 = t0, sDur = out, holdDur = hold, backDur = back, keepHold = o.keep == true,
		afterBack = "destroy", home = nil, restTarget = nil,
		backS = math.max(tonumber(o.overshoot) or snum("Overshoot", 0.1), 0) * 17,
		wobble = tonumber(o.wobble) or snum("Wobble", 0.35), wobHz = snum("WobbleHz", 9),
		sag = tonumber(o.sag) or snum("Sag", 0.05), spiral = tonumber(o.spiral) or 0,
		fs = fs, as = tonumber(o.armScale) or 1,
		w0 = leg and snum("LegWidth", 0.95) or snum("ArmWidth", 0.78),
		w1 = leg and snum("AnkleWidth", 0.7) or snum("WristWidth", 0.6),
		maxLen = tonumber(o.maxLen) or snum("MaxLength", 140),
		onReach = type(o.onReach) == "function" and o.onReach or nil,
		onDone = type(o.onDone) == "function" and o.onDone or nil,
		reached = false, born = clock, keptAt = clock,
		ghosts = o.ghosts == true, nextGhost = 0,
		ghostColor = o.ghostColor or (o.white and PAL.Nika) or (o.haki and PAL.Haki) or color,
		haki = o.haki == true, nextBolt = 0, white = o.white == true,
		pts = {}, list = {}, cfs = {}, parts = {},
	}, Stretch)
	for _, p in ipairs(segs) do
		table.insert(h.parts, p)
	end
	for _, p in ipairs(joints) do
		table.insert(h.parts, p)
	end
	table.insert(h.parts, fist)
	if o.trail then
		-- the whoosh trail: its two attachments sit across the fist (its X), never along the flight
		local w = math.max(fbase.X, 0.8) * fs * 0.9
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position = Vector3.new(w / 2, 0, 0)
		a1.Position = Vector3.new(-w / 2, 0, 0)
		a0.Parent, a1.Parent = fist, fist
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = cs(o.trailColor or PAL.Whoosh)
		tr.Lifetime = snum("TrailLife", 0.14)
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.MinLength = 0.05
		tr.Transparency = tseq({ { 0, 0.25 }, { 1, 1 } })
		tr.WidthScale = nsk({ { 0, 1 }, { 1, 0.1 } })
		tr.Parent = fist
		h.trail = tr
	end
	if h.white then
		-- Gear 5: white rubber, a cartoon outline and a soft sun glow on the fist
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = PAL.Toon
		hl.OutlineTransparency = 0.1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = model
		hl.Parent = model
		local l = Instance.new("PointLight")
		l.Color = PAL.Sun
		l.Brightness = 1.2
		l.Range = 10
		l.Shadows = false
		l.Parent = fist
	end
	model.Parent = parentOf(o.folder)
	per[limb] = h
	handles[h] = true
	return h
end

-- S.stretchArm(char, side "R"|"L", target, o) / S.stretchLeg(char, side, target, o) -> handle (CONTRACT 6.2)
function S.stretchArm(char, side, target, o)
	local limb = (side == "RL" or side == "LL") and side or ((side == "L" or side == "Left") and "L" or "R")
	return newStretch(char, limb, target, o)
end
function S.stretchLeg(char, side, target, o)
	local limb = (side == "L" or side == "LL" or side == "Left") and "LL" or "RL"
	return newStretch(char, limb, target, o)
end
-- the live handle on a limb (or nil)
function S.liveStretch(char, limb)
	local per = byLimb[char]
	local h = per and per[normLimb(limb) or ""]
	return (h and not h.dead) and h or nil
end

function Stretch:tip()
	return self.P or Vector3.zero
end
function Stretch:length()
	if self.dead or not self.P then
		return 0
	end
	local r = S.limbRoot(self.char, self.limb)
	return r and (self.P - r.Position).Magnitude or 0
end
function Stretch:setTarget(t)
	if not self.dead then
		self.target = t
	end
end
-- elastic tween of the fist / arm thickness (ease "quad" for a plain ease-out)
function Stretch:setScale(fistScale, armScale, secs, ease)
	if self.dead then
		return
	end
	self.fs0, self.as0 = self.fs, self.as
	self.fs1 = tonumber(fistScale) or self.fs
	self.as1 = tonumber(armScale) or self.as
	self.scaleDur = math.max(tonumber(secs) or 0.3, 0.01)
	self.scaleT0 = os.clock()
	self.scaleEase = ease
end
function Stretch:keep()
	if not self.dead then
		self.keptAt = os.clock()
	end
end
-- snap back to the real hand now (over secs), then gone
function Stretch:retract(secs)
	if self.dead then
		return
	end
	self.state = "back"
	self.sT0 = os.clock()
	self.sDur = math.max(tonumber(secs) or self.backDur or 0.16, 0.01)
	self.from = self.P or self.from
	self.keepHold = false
	self.afterBack = "destroy"
	self.home = nil
	self.keptAt = os.clock()
end
function Stretch:destroy()
	if self.dead then
		return
	end
	self.dead = true
	handles[self] = nil
	local per = byLimb[self.char]
	if per and per[self.limb] == self then
		per[self.limb] = nil
	end
	local lp = Players.LocalPlayer
	local mine = lp and lp.Character == self.char
	for p, v in pairs(self.hidden) do
		if p.Parent then
			-- never hand a remote body a hidden limb back (only the local camera module rewrites ours)
			p.LocalTransparencyModifier = (mine or v < 1) and v or 0
		end
	end
	if self.steamH then
		pcall(function()
			self.steamH:stop()
		end)
	end
	if self.model then
		self.model:Destroy()
	end
	local f = self.onDone
	self.onDone = nil
	if f then
		task.spawn(pcall, f)
	end
end
Stretch.Destroy = Stretch.destroy
Stretch.stop = Stretch.destroy
-- giant fists (6.3): fly out to `target`, hold, come back to the rest point (no-op on a plain stretch's rest)
function Stretch:punch(target, out, hold, back)
	if self.dead then
		return
	end
	self.target = target
	self.lastT = nil
	self.from = self.P or self.from
	self.state = "out"
	self.sT0 = os.clock()
	self.sDur = math.max(tonumber(out) or 0.24, 0.01)
	self.holdDur = math.max(tonumber(hold) or 0.25, 0)
	self.backDur = math.max(tonumber(back) or 0.4, 0.01)
	self.keepHold = false
	self.afterBack = self.restTarget and "rest" or "destroy"
	self.home = self.restTarget
	self.reached = false
	self.keptAt = os.clock()
end
-- shrink back to hand size with a steam burst, then snap home and go
function Stretch:deflate(secs)
	if self.dead then
		return
	end
	secs = math.max(tonumber(secs) or 0.4, 0.05)
	self:setScale(1, 1, secs, "quad")
	self.keptAt = os.clock()
	local pos = self.fist and self.fist.Position
	if pos then
		local st = S.steam(pos, 0, {})
		pcall(function()
			st:Emit(math.floor(20 + 4 * (self.fs or 1)))
		end)
	end
	if self.steamE then
		self.steamE.Rate = 0
	end
	task.delay(secs, function()
		if not self.dead then
			self:retract(0.18)
		end
	end)
end

local function homeOf(h)
	if h.home then
		local v = resolve(h.home)
		if v then
			return v
		end
	end
	local t = h.tipPart
	return (t and t.Parent) and t.Position or nil
end

local function fire(fn, ...)
	if fn then
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[GomuKit.Client.Shared] stretch callback: " .. tostring(err))
		end
	end
end

local function stepHandle(h, c)
	local char = h.char
	if not char.Parent or not h.upper.Parent or not h.model.Parent then
		h:destroy()
		return
	end
	if h.keepHold or h.afterBack == "rest" then
		if c - h.keptAt > KEEP_LIFE then
			h:destroy()
			return
		end
	elseif c - h.born > MAX_LIFE then
		h:destroy()
		return
	end
	local rootCF = S.limbRoot(char, h.limb)
	if not rootCF then
		h:destroy()
		return
	end
	local A = rootCF.Position
	local T = resolve(h.target)
	if T then
		h.lastT = T
	else
		T = h.lastT or homeOf(h) or A
	end
	local off = T - A
	if off.Magnitude > h.maxLen then
		T = A + off.Unit * h.maxLen
	end
	if h.scaleT0 then
		local k = math.clamp((c - h.scaleT0) / h.scaleDur, 0, 1)
		local e = (h.scaleEase == "quad") and (1 - (1 - k) * (1 - k)) or elasticOut(k)
		h.fs = h.fs0 + (h.fs1 - h.fs0) * e
		h.as = h.as0 + (h.as1 - h.as0) * e
		if k >= 1 then
			h.scaleT0 = nil
			h.fs, h.as = h.fs1, h.as1
		end
	end
	-- the timeline: OUT (Back-Out past the target, onto it) -> HOLD (wobbling) -> BACK (Quad-In home)
	local P
	local wob = 0
	if h.state == "out" then
		local k = (c - h.sT0) / h.sDur
		if k >= 1 then
			h.state = "hold"
			h.sT0 = h.sT0 + h.sDur
			h.wobT0 = c
		else
			P = h.from:Lerp(T, easeBackOut(math.max(k, 0), h.backS))
		end
	end
	if h.state == "hold" then
		P = T
		local e = c - (h.wobT0 or c)
		wob = h.wobble * math.exp(-7 * e) * math.sin(TAU * h.wobHz * e)
		if not h.reached then
			h.reached = true
			fire(h.onReach, P)
		end
		if not h.keepHold and c >= h.sT0 + h.holdDur then
			h.state = "back"
			h.sT0 = c
			h.sDur = h.backDur
			h.from = P
		end
	end
	if h.state == "back" then
		local k = (c - h.sT0) / h.sDur
		local home = homeOf(h) or A
		if k >= 1 then
			if h.afterBack == "rest" and h.restTarget then
				h.state = "hold"
				h.target = h.restTarget
				h.keepHold = true
				h.sT0 = c
				h.wobT0 = c
				P = home
			else
				h:destroy()
				return
			end
		else
			k = math.max(k, 0)
			P = h.from:Lerp(home, k * k)
			wob = h.wobble * 0.6 * (1 - k) * math.sin(TAU * h.wobHz * (c - h.sT0))
		end
	end
	local d = P - A
	local L = d.Magnitude
	local dir = (L > 1e-3) and d / L or (h.lastDir or -UP)
	h.lastDir = dir
	h.P = P
	-- the fist: knuckles at P, its -Y down the limb (a hand hangs along its Y)
	local fs = h.fs
	local fsize = h.fistBase * fs
	if (h.fist.Size - fsize).Magnitude > 1e-3 then
		h.fist.Size = fsize
		if h.fistMesh and h.fistMeshBase then
			h.fistMesh.Scale = h.fistMeshBase * fs
		end
	end
	local half = fsize.Y * 0.5
	local F = P - dir * half
	local W = P - dir * (half * 2)
	if (W - A):Dot(dir) < 0.2 then
		W = A + dir * 0.2
	end
	local LL = (W - A).Magnitude
	local ref = (math.abs(dir.Y) < 0.95) and UP or ((h.hrp and h.hrp.Parent) and h.hrp.CFrame.LookVector or Vector3.xAxis)
	local z = ref - dir * ref:Dot(dir)
	z = (z.Magnitude > 1e-4) and z.Unit or Vector3.xAxis
	local y = -dir
	local fistCF = CFrame.fromMatrix(F, y:Cross(z), y, z)
	-- the rubber: a quadratic bezier shoulder -> wrist, sagging, wobbling, corkscrewing (Rifle) while out
	local side = dir:Cross(UP)
	side = (side.Magnitude > 1e-3) and side.Unit or Vector3.xAxis
	local up2 = side:Cross(dir).Unit
	local mid = (A + W) * 0.5 - UP * (h.sag * LL)
	local spiralR = 0
	if h.spiral > 0 then
		if h.state == "out" then
			spiralR = h.w0 * 0.9 * h.as
		elseif h.state == "hold" and c - h.sT0 < 0.12 then
			spiralR = h.w0 * 0.9 * h.as * (1 - (c - h.sT0) / 0.12)
		end
	end
	local pts, N = h.pts, SEGMENTS
	for i = 0, N do
		local u = i / N
		local iu = 1 - u
		local p = A * (iu * iu) + mid * (2 * u * iu) + W * (u * u)
		local s = math.sin(math.pi * u)
		if wob ~= 0 then
			p += side * (wob * s)
		end
		if spiralR > 0 then
			local th = TAU * h.spiral * u - c * 30
			p += (side * math.cos(th) + up2 * math.sin(th)) * (spiralR * s)
		end
		pts[i] = p
	end
	local list, cfs = h.list, h.cfs
	local n = 0
	for i = 1, N do
		local a, b = pts[i - 1], pts[i]
		local seg = b - a
		local sl = seg.Magnitude
		local u = (i - 0.5) / N
		local w = (h.w0 + (h.w1 - h.w0) * u) * h.as
		local part = h.segs[i]
		local sz = Vector3.new(sl + w * 0.4, w, w)
		if (part.Size - sz).Magnitude > 1e-3 then
			part.Size = sz
		end
		n += 1
		list[n] = part
		cfs[n] = lookAlong((a + b) * 0.5, (sl > 1e-4) and seg or dir) * ROT90
		if i < N then
			local j = h.joints[i]
			local jw = (h.w0 + (h.w1 - h.w0) * (i / N)) * h.as
			if math.abs(j.Size.X - jw) > 1e-3 then
				j.Size = Vector3.one * jw
			end
			n += 1
			list[n] = j
			cfs[n] = CFrame.new(b)
		end
	end
	n += 1
	list[n] = h.fist
	cfs[n] = fistCF
	for i = #list, n + 1, -1 do
		list[i], cfs[i] = nil, nil
	end
	workspace:BulkMoveTo(list, cfs, BULK)
	-- the real limb stays hidden (re-applied after the camera module every frame)
	for p in pairs(h.hidden) do
		if p.Parent and p.LocalTransparencyModifier ~= 1 then
			p.LocalTransparencyModifier = 1
		end
	end
	-- afterimage fists while it flies, haki lightning crackling over the fist
	if h.ghosts and h.state == "out" and c >= h.nextGhost then
		h.nextGhost = c + snum("GhostEvery", 0.025)
		S.fistGhost(lookAlong(F, dir), fs * 0.9, { color = h.ghostColor, life = snum("GhostLife", 0.12), alpha = 0.45 })
	end
	if h.haki and c >= h.nextBolt then
		h.nextBolt = c + rng:NextNumber(0.05, 0.11)
		local r = fsize.Magnitude * 0.4
		pcall(FX.bolt, h.model, F + FX.randUnit() * r, F + FX.randUnit() * r * 1.7, {
			color = (rng:NextNumber() < 0.6) and PAL.HakiBolt or PAL.HakiBolt2, width = 0.06 + 0.02 * fs, jag = 0.4,
			segments = 4, life = 0.08, restrike = 1,
		})
	end
end

-- 6.3 big fists ----------------------------------------------------------------------------------
-- S.giantFist(char, side, o) -> handle (Gear Third): a keep stretch whose fist / arm INFLATE from 1 to o.scale /
-- o.armScale over o.grow s (elastic, steam pouring off it), held at o.rest (function | point; default above and behind
-- the shoulder). h:punch(target, out, hold, back) flies out and back to rest; h:deflate(secs) shrinks it and ends it.
-- o = { scale = 6, armScale = scale * 0.45, grow = 0.5, rest, haki, white, color, t0, trail, ghosts, onReach, folder }
function S.giantFist(char, side, o)
	o = type(o) == "table" and o or {}
	local limb = (side == "L" or side == "Left") and "L" or "R"
	local scale = math.max(tonumber(o.scale) or 6, 1)
	local function rest()
		if o.rest ~= nil then
			local v = resolve(o.rest)
			if v then
				return v
			end
		end
		local r = S.limbRoot(char, limb)
		local hrp = typeof(char) == "Instance" and char:FindFirstChild("HumanoidRootPart")
		if not r or not hrp then
			return nil
		end
		local cf = hrp.CFrame
		local sx = (limb == "R") and 1 or -1
		return r.Position + UP * (2.2 + scale * 0.5) - cf.LookVector * (1.5 + scale * 0.3) + cf.RightVector * (sx * (1 + scale * 0.25))
	end
	local grow = math.max(tonumber(o.grow) or 0.5, 0.05)
	local h = newStretch(char, limb, rest, {
		keep = true, t0 = o.t0, out = o.out or 0.2, hold = 0, back = o.back or 0.2, fistScale = 1, armScale = 1,
		white = o.white, haki = o.haki, color = o.color, sag = o.sag or 0.02, wobble = o.wobble or 0.25,
		overshoot = o.overshoot or 0.15, folder = o.folder, trail = o.trail, ghosts = o.ghosts, onReach = o.onReach,
		onDone = o.onDone,
	})
	if h.dead then
		return h
	end
	h.giant = true
	h.restTarget = rest
	h.home = rest
	h.reached = true -- arriving at the rest pose is not a landing: onReach waits for :punch
	h:setScale(scale, tonumber(o.armScale) or math.max(scale * 0.45, 1), grow)
	-- steam pours off the swelling fist (from its whole surface), then simmers
	local e = FX.emitter(h.fist, {
		Texture = TEX.smoke, Color = cs(PAL.Steam, C(190, 190, 190)), LightInfluence = 1, LightEmission = 0,
		Size = nsk({ { 0, 1 }, { 0.4, 2.6 }, { 1, 4 } }), Transparency = nsk({ { 0, 0.45 }, { 0.5, 0.7 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.7, 1.2), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, 7, 0), Drag = 1, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		Rate = 60,
	})
	h.steamE = e
	task.delay(grow, function()
		if not h.dead and e.Parent then
			e.Rate = 6
		end
	end)
	return h
end

-- S.fistModel(size, o) -> Model: a stylised giant fist (block + four knuckles + curled fingers + a thumb + a wrist
-- stub). Knuckles face the model's -Z (LookVector): PivotTo(CFrame.lookAt(pos, pos + punchDir)). o = { white, haki,
-- color, left (mirror the thumb), cf, folder, life = 8, outline = white }
function S.fistModel(size, o)
	o = type(o) == "table" and o or {}
	size = math.max(tonumber(size) or 6, 0.5)
	local color = o.color or (o.white and PAL.Nika) or (o.haki and PAL.Haki) or PAL.Skin
	local m = Instance.new("Model")
	m.Name = "GomuGiantFist"
	local function piece(name, shape, sz, cf)
		local p = newPart(name, PLASTIC, color, sz * size, cf, 0, m, shape)
		if o.haki then
			p.Reflectance = 0.18
		end
		return p
	end
	local palm = piece("Palm", BLOCK, Vector3.new(1, 0.8, 0.86), CFrame.new())
	for i = 1, 4 do
		local x = (-0.375 + (i - 1) * 0.25) * size
		piece("Knuckle", BALL, Vector3.one * 0.3, CFrame.new(x, 0.16 * size, -0.4 * size))
		piece("Finger", BLOCK, Vector3.new(0.23, 0.46, 0.3), CFrame.new(x, -0.1 * size, -0.48 * size))
	end
	local tx = (o.left and 1 or -1) * 0.18 * size
	piece("Thumb", BLOCK, Vector3.new(0.56, 0.24, 0.26), CFrame.new(tx, -0.3 * size, -0.52 * size) * CFrame.Angles(0, 0, math.rad(o.left and 8 or -8)))
	piece("Wrist", CYL, Vector3.new(0.7, 0.68, 0.68), CFrame.new(0, -0.02 * size, 0.6 * size) * ROT90)
	m.PrimaryPart = palm
	if o.white or o.outline then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = PAL.Toon
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = m
		hl.Parent = m
	end
	if typeof(o.cf) == "CFrame" then
		m:PivotTo(o.cf)
	end
	m.Parent = parentOf(o.folder)
	Debris:AddItem(m, math.clamp(tonumber(o.life) or MAX_LIFE, 0.1, MAX_LIFE))
	return m
end

-- S.fistGhost(cf, scale, o) -> nil: a one-shot afterimage fist at cf (LookVector = the punch), drifting o.drift studs
-- forward while it fades over o.life; o.stub = length adds a short arm behind it. Pooled, <= 60 alive.
-- o = { color = skin, alpha = 0.35, life = Stretch.GhostLife, drift = 0, stub, white, neon }
local ghostPool, ghostLive = {}, {}
local GHOST_MAX = 60
function S.fistGhost(cf, scale, o)
	if typeof(cf) ~= "CFrame" then
		return nil
	end
	o = type(o) == "table" and o or {}
	if #ghostLive >= GHOST_MAX then
		return nil
	end
	local f = kitFolder()
	local g = table.remove(ghostPool)
	if not g or not g.fist.Parent then
		g = {
			fist = newPart("FistGhost", PLASTIC, WHITE, Vector3.one, nil, 1, f, BALL),
			stub = newPart("FistGhostArm", PLASTIC, WHITE, Vector3.one, nil, 1, f, CYL),
		}
	end
	scale = math.max(tonumber(scale) or 1, 0.1)
	local color = o.color or (o.white and PAL.Nika) or PAL.Skin
	g.fist.Color = color
	g.fist.Material = o.neon and NEON or PLASTIC
	g.fist.Size = Vector3.one * 1.1 * scale
	g.stubLen = math.max(tonumber(o.stub) or 0, 0)
	g.stub.Color = color
	g.stub.Material = g.fist.Material
	g.stub.Size = Vector3.new(math.max(g.stubLen, 0.05), 0.55 * scale, 0.55 * scale)
	g.scale = scale
	g.cf = cf
	g.t0 = os.clock()
	g.life = math.max(tonumber(o.life) or snum("GhostLife", 0.12), 0.02)
	g.alpha = math.clamp(tonumber(o.alpha) or 0.35, 0, 1)
	g.drift = tonumber(o.drift) or 0
	table.insert(ghostLive, g)
	return nil
end
local function stepGhosts(c)
	local i = 1
	while i <= #ghostLive do
		local g = ghostLive[i]
		local k = (c - g.t0) / g.life
		if k >= 1 or not g.fist.Parent then
			g.fist.Transparency = 1
			g.stub.Transparency = 1
			table.remove(ghostLive, i)
			if g.fist.Parent and #ghostPool < GHOST_MAX then
				table.insert(ghostPool, g)
			end
		else
			local cf = g.cf * CFrame.new(0, 0, -g.drift * k)
			g.fist.CFrame = cf
			g.fist.Transparency = g.alpha + (1 - g.alpha) * k
			if g.stubLen > 0 then
				g.stub.CFrame = cf * CFrame.new(0, 0, g.scale * 0.5 + g.stubLen * 0.5) * ROT90
				g.stub.Transparency = g.alpha + (1 - g.alpha) * k
			else
				g.stub.Transparency = 1
			end
			i += 1
		end
	end
end

-- one render step for every stretch and ghost: after the camera module (Stretch.RenderPriority = Camera + 2)
local warnedStep = 0
-- (PERKS kitsE: GomuClient requires a private copy of this module for the CRIMSON GEAR skin; it binds its own step)
RunService:BindToRenderStep(script.Name == "Shared" and "GomuStretch" or ("GomuStretch_" .. script.Name), math.floor(snum("RenderPriority", Enum.RenderPriority.Camera.Value + 2)), function()
	local c = os.clock()
	for h in pairs(handles) do
		local ok, err = pcall(stepHandle, h, c)
		if not ok then
			if c - warnedStep > 5 then
				warnedStep = c
				warn("[GomuKit.Client.Shared] stretch step: " .. tostring(err))
			end
			pcall(function()
				h:destroy()
			end)
		end
	end
	if #ghostLive > 0 then
		pcall(stepGhosts, c)
	end
end)

---------------------------------------------------------------------------------------------------
-- 6.4 effects

-- S.whoosh(f, a, b, o): a speed streak a -> b that thins, stretches and fades. o = { color = Whoosh, width = 0.16,
-- life = 0.14, alpha = 0.25, stretch = 1.25 }
function S.whoosh(f, a, b, o)
	a, b = vec(a), vec(b)
	if not a or not b then
		return nil
	end
	o = type(o) == "table" and o or {}
	local d = b - a
	local L = d.Magnitude
	if L < 0.05 then
		return nil
	end
	local fp = parentOf(f)
	local w = tonumber(o.width) or 0.16
	local life = math.clamp(tonumber(o.life) or 0.14, 0.03, 2)
	local p = newPart("Whoosh", NEON, o.color or PAL.Whoosh, Vector3.new(w, w, L), lookAlong(a + d * 0.5, d), tonumber(o.alpha) or 0.25, fp)
	tween(p, life, { Transparency = 1, Size = Vector3.new(w * 0.15, w * 0.15, L * (tonumber(o.stretch) or 1.25)), CFrame = lookAlong(a + d * 0.62, d) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Debris:AddItem(p, life + 0.05)
	return p
end

-- S.limbTrail(char, limbs, c0, c1, life, secs) -> handle { stop() }: whoosh Trails on the hands / feet. limbs =
-- { "R", "L", "RL", "LL" } (any of) or "All"
function S.limbTrail(char, limbs, c0, c1, life, secs)
	if typeof(char) ~= "Instance" or not char.Parent then
		return dummy()
	end
	if limbs == nil or limbs == "All" then
		limbs = { "R", "L", "RL", "LL" }
	elseif type(limbs) == "string" then
		limbs = { limbs }
	end
	life = math.clamp(tonumber(life) or 0.2, 0.03, 2)
	local made = {}
	for _, limb in ipairs(limbs) do
		local _, _, tip = S.limbParts(char, limb)
		if tip then
			local w = 0.9
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Name, a1.Name = "GomuTrail0", "GomuTrail1"
			a0.Position = Vector3.new(w / 2, 0, 0)
			a1.Position = Vector3.new(-w / 2, 0, 0)
			a0.Parent, a1.Parent = tip, tip
			local t = Instance.new("Trail")
			t.Name = "GomuLimbTrail"
			t.Attachment0, t.Attachment1 = a0, a1
			t.Color = cs(c0 or PAL.Whoosh, c1 or c0 or PAL.Whoosh)
			t.Lifetime = life
			t.LightEmission = 1
			t.LightInfluence = 0
			t.FaceCamera = true
			t.MinLength = 0.05
			t.Transparency = tseq({ { 0, 0.2 }, { 1, 1 } })
			t.WidthScale = nsk({ { 0, 1 }, { 1, 0.1 } })
			t.Parent = tip
			table.insert(made, t)
			table.insert(made, a0)
			table.insert(made, a1)
		end
	end
	local h = { dead = false, parts = {} }
	function h.stop()
		if h.dead then
			return
		end
		h.dead = true
		for _, x in ipairs(made) do
			if x:IsA("Trail") then
				x.Enabled = false
			end
		end
		task.delay(life + 0.1, function()
			for _, x in ipairs(made) do
				x:Destroy()
			end
		end)
	end
	h.Destroy, h.destroy = h.stop, h.stop
	task.delay(math.clamp(tonumber(secs) or 1, 0.05, MAX_LIFE), h.stop)
	return h
end

-- S.impactStar(f, pos, o): a comic impact burst - star shards in the camera plane, a flash glow, a ring and sparks.
-- NO text. o = { size = 4, color = Impact, color2 = white, n = 9, life = 0.2, sparks = true, sparkCount = 14 }
function S.impactStar(f, pos, o)
	pos = vec(pos)
	if not pos then
		return
	end
	o = type(o) == "table" and o or {}
	local fp = parentOf(f)
	local size = tonumber(o.size) or 4
	local c0 = o.color or PAL.Impact
	local c1 = o.color2 or WHITE
	local n = math.clamp(math.floor(tonumber(o.n) or 9), 3, 24)
	local life = math.clamp(tonumber(o.life) or 0.2, 0.05, 1)
	local cam = camCF()
	local right, up = cam.RightVector, cam.UpVector
	local toCam = camFacing(pos)
	local base = pos + toCam * 0.6
	local k = S.ringScale(pos)
	local off = rng:NextNumber(0, TAU)
	for i = 1, n do
		local a = off + (i / n) * TAU + rng:NextNumber(-0.18, 0.18)
		local dir = right * math.cos(a) + up * math.sin(a)
		local len = size * rng:NextNumber(0.6, 1.15) * ((i % 2 == 0) and 0.6 or 1)
		local w = size * 0.1 * k
		local p0 = base + dir * size * 0.15
		local shard = newPart("Star", NEON, (i % 2 == 0) and c1 or c0, Vector3.new(w, w * 0.35, len * 0.3), CFrame.lookAt(p0 + dir * len * 0.15, p0 + dir * len, toCam), 0, fp)
		tween(shard, life, { Size = Vector3.new(w * 0.2, w * 0.1, len), CFrame = CFrame.lookAt(p0 + dir * len * 0.7, p0 + dir * len * 1.3, toCam), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(shard, life + 0.05)
	end
	FX.glow(fp, base, S.glowFor(pos, size * 1.6), c0, 0.22, { brightness = 2 })
	FX.ring(fp, base, toCam, size * 0.3, size * 2.2 * k, c1, 0.25, {})
	if o.sparks ~= false then
		FX.sparks(fp, pos, { color = c0, color2 = c1, count = tonumber(o.sparkCount) or 14, speed = { 25, 60 }, life = 0.4, size = 0.5 })
	end
end

-- S.shock(f, pos, normal, o): an expanding shock ring (a particle ring + a thin disc of light). o = { from = 1,
-- to = 14 (radius), life = 0.35, color = Whoosh, alpha = 0.6, brightness = 2 }
function S.shock(f, pos, normal, o)
	pos = vec(pos)
	if not pos then
		return nil
	end
	o = type(o) == "table" and o or {}
	local fp = parentOf(f)
	normal = unit(normal, UP)
	local from = tonumber(o.from) or 1
	local to = tonumber(o.to) or tonumber(o.radius) or 14
	local life = math.clamp(tonumber(o.life) or 0.35, 0.05, 3)
	local color = o.color or PAL.Whoosh
	FX.ring(fp, pos, normal, from * 2, to * 2, color, life, { brightness = o.brightness or 2 })
	local disc = newPart("ShockDisc", NEON, color, Vector3.new(0.15, from * 2, from * 2), lookAlong(pos, normal) * ROT90, tonumber(o.alpha) or 0.6, fp, CYL)
	tween(disc, life, { Size = Vector3.new(0.05, to * 2, to * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(disc, life + 0.05)
	return disc
end

-- S.rubble(f, pos, n, o): chunks of the ground torn up and thrown (GojoFX.rubble). o = { radius, up = {a, b},
-- out = {a, b}, dir, min, max, life, depth }
function S.rubble(f, pos, n, o)
	pos = vec(pos)
	if not pos then
		return
	end
	o = type(o) == "table" and o or {}
	local fp = parentOf(f)
	if crowded(fp, 320) then
		n = math.max(2, math.floor((n or 8) / 2))
	end
	pcall(FX.rubble, fp, pos, {
		count = math.clamp(math.floor(tonumber(n) or 8), 1, 40), radius = o.radius, up = o.up, out = o.out, dir = o.dir,
		min = o.min, max = o.max, life = o.life, depth = o.depth,
	})
end

-- S.cloud(f, cf, o) -> handle { set(cf), keep(), dissolve(secs), stop() }: a soft white cloud of puffs (the Gear 5
-- scarf, the Bajrang sky). o = { size = 6, n = 7, color = Cloud, alpha = 0.12, flat = 0.7, grow = 0.35, life }
function S.cloud(f, cf, o)
	if typeof(cf) == "Vector3" then
		cf = CFrame.new(cf)
	end
	if typeof(cf) ~= "CFrame" then
		return dummy()
	end
	o = type(o) == "table" and o or {}
	local fp = parentOf(f)
	local size = tonumber(o.size) or 6
	local n = math.clamp(math.floor(tonumber(o.n) or 7), 1, 24)
	local color = o.color or PAL.Cloud
	local model = Instance.new("Model")
	model.Name = "GomuCloud"
	local puffs = {}
	for i = 1, n do
		local a = (i / n) * TAU + rng:NextNumber(-0.3, 0.3)
		local r = size * rng:NextNumber(0.15, 0.55)
		local offv = Vector3.new(math.cos(a) * r, rng:NextNumber(-0.15, 0.25) * size, math.sin(a) * r * (tonumber(o.flat) or 0.7))
		local s = size * rng:NextNumber(0.45, 0.8)
		local p = newPart("Puff", PLASTIC, color:Lerp(WHITE, rng:NextNumber(0, 0.3)), Vector3.one * s, cf * CFrame.new(offv), tonumber(o.alpha) or 0.12, model, BALL)
		puffs[i] = { p = p, off = CFrame.new(offv), full = p.Size }
	end
	model.Parent = fp
	local life = lifeClock(o.life)
	local h = { dead = false, model = model, parts = {}, cf = cf }
	for i, pf in ipairs(puffs) do
		h.parts[i] = pf.p
		pf.p.Size = pf.full * 0.3
		tween(pf.p, tonumber(o.grow) or 0.35, { Size = pf.full }, Enum.EasingStyle.Back)
	end
	function h.set(a, b)
		local cf2 = arg1(h, a, b)
		if h.dead then
			return
		end
		if typeof(cf2) == "Vector3" then
			cf2 = CFrame.new(cf2)
		end
		if typeof(cf2) ~= "CFrame" then
			return
		end
		h.cf = cf2
		life.keep()
		local list, cfs = {}, {}
		for i, pf in ipairs(puffs) do
			list[i] = pf.p
			cfs[i] = cf2 * pf.off
		end
		workspace:BulkMoveTo(list, cfs, BULK)
	end
	h.place = h.set
	function h.keep()
		life.keep()
	end
	function h.dissolve(a, b)
		local secs = tonumber(arg1(h, a, b)) or 0.6
		if h.dead then
			return
		end
		h.dead = true
		for _, pf in ipairs(puffs) do
			if pf.p.Parent then
				tween(pf.p, secs, { Transparency = 1, Size = pf.p.Size * 1.5 })
			end
		end
		Debris:AddItem(model, secs + 0.05)
	end
	h.stop, h.Destroy, h.destroy, h.fade = h.dissolve, h.dissolve, h.dissolve, h.dissolve
	task.spawn(function()
		while not h.dead do
			task.wait(0.5)
			if not h.dead and (life.expired() or not model.Parent) then
				h.dissolve(0.8)
			end
		end
	end)
	return h
end

-- S.sunAura(char, o) -> handle { set(k), keep(), stop() }: the Gear 5 white flame aura (white fire off the torso,
-- sparkles, a soft sun light). k = intensity 0..2. o = { k = 1, life }
function S.sunAura(char, o)
	local torso = typeof(char) == "Instance" and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart"))
	if not torso then
		return dummy()
	end
	o = type(o) == "table" and o or {}
	local flame = FX.emitter(torso, {
		Texture = FIRE, Color = cs(PAL.Nika, PAL.Sun), LightEmission = 1, LightInfluence = 0,
		Size = nsk({ { 0, 2.2 }, { 0.4, 1.6 }, { 1, 0 } }), Transparency = nsk({ { 0, 0.6 }, { 0.3, 0.45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.45, 0.85), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 12, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		EmissionDirection = Enum.NormalId.Top, Rate = 0,
	})
	flame.Name = "GomuSunFlame"
	local motes = FX.emitter(torso, {
		Texture = TEX.star, Color = cs(PAL.Sun, WHITE), LightEmission = 1, Size = nsk({ { 0, 0.5 }, { 1, 0 } }),
		Transparency = nsk({ { 0, 0.1 }, { 1, 1 } }), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 4, 0), Rate = 0,
	})
	motes.Name = "GomuSunMotes"
	local light = Instance.new("PointLight")
	light.Name = "GomuSunLight"
	light.Color = PAL.Sun
	light.Range = 16
	light.Brightness = 0
	light.Shadows = false
	light.Parent = torso
	local life = lifeClock(o.life)
	local h = { dead = false, k = 0, parts = {} }
	local function apply(k)
		flame.Rate = 40 * k
		motes.Rate = 12 * k
		light.Brightness = 1.6 * k
	end
	function h.set(a, b)
		if h.dead then
			return
		end
		h.k = math.clamp(tonumber(arg1(h, a, b)) or 1, 0, 2)
		apply(h.k)
		life.keep()
	end
	function h.keep()
		life.keep()
	end
	function h.stop()
		if h.dead then
			return
		end
		h.dead = true
		flame.Rate, motes.Rate = 0, 0
		tween(light, 0.5, { Brightness = 0 })
		Debris:AddItem(flame, 1.2)
		Debris:AddItem(motes, 1.3)
		Debris:AddItem(light, 0.6)
	end
	h.Destroy, h.destroy, h.dissolve = h.stop, h.stop, h.stop
	h.set(tonumber(o.k) or 1)
	task.spawn(function()
		while not h.dead do
			task.wait(0.4)
			if not h.dead and (life.expired() or not torso.Parent) then
				h.stop()
			end
		end
	end)
	return h
end

-- S.boing(char, o): the rubber squash & stretch. A short pose clip (Clips.Scaffold_Boing: crouch-squash, a stretched
-- rebound, settle - Root / legs / a little arm fling; the rig is NEVER scaled) + a flat squash ring and dust under the
-- feet + a rubbery "boing". Debounced 0.25 s per character. o = { power = 1 (0.2 - 2), clip = true, clipName,
-- ring = true, dust = true, sound = true, color, folder, force }
local lastBoing = setmetatable({}, { __mode = "k" })
function S.boing(char, o)
	if typeof(char) ~= "Instance" or not char.Parent then
		return
	end
	o = type(o) == "table" and o or {}
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return
	end
	local c = os.clock()
	if not o.force and c - (lastBoing[char] or -1e9) < 0.25 then
		return
	end
	lastBoing[char] = c
	local power = math.clamp(tonumber(o.power) or 1, 0.2, 2)
	if o.clip ~= false and Animator then
		local clips = clipsTable()
		local clip = clips and clips[o.clipName or "Scaffold_Boing"]
		if type(clip) == "table" then
			pcall(Animator.play, char, clip, { startAt = 0 })
		end
	end
	local fp = parentOf(o.folder)
	local legH = (hum.RigType == Enum.HumanoidRigType.R6) and 3 or (hum.HipHeight + hrp.Size.Y * 0.5)
	local hit = FX.groundHit(hrp.Position, legH + 2)
	local g = hit and hit.Position or (hrp.Position - UP * legH)
	local nrm = hit and hit.Normal or UP
	local color = o.color or PAL.Whoosh
	if o.ring ~= false then
		local r = 2.2 + 2.2 * power
		local disc = newPart("BoingRing", NEON, color, Vector3.new(0.12, 1.2, 1.2), lookAlong(g + nrm * 0.08, nrm) * ROT90, 0.5, fp, CYL)
		tween(disc, 0.28, { Size = Vector3.new(0.04, r * 2, r * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(disc, 0.32)
		FX.ring(fp, g + nrm * 0.1, nrm, 1, r * 2.4, color, 0.3, {})
	end
	if o.dust ~= false and hit then
		S.dustRing(fp, g, 1.2, 6, 14 * power, { s0 = 1.2, s1 = 3.4, life = 0.7 })
	end
	if o.sound ~= false then
		sfx("Rise", hrp, 0.35 + 0.15 * power, 1.8 + rng:NextNumber(-0.08, 0.08))
	end
end

return S
