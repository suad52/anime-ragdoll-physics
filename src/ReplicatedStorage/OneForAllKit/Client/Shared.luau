--!nocheck
-- OneForAllKit.Client.Shared: the pure effect builders of the One For All (Deku) kit (design A section 3).
-- No input, HUD, camera or movement state lives here: every function draws something in the world (or on the
-- terrain wind / the storm grade) and cleans itself up. One-shots die through Debris / tweens; persistent pieces
-- (Veins, Tendril, StormDeck, steam, eyeGlow, airColumn, airBullet, pressureFront, sunShafts) return a handle with
-- :Destroy() (alias :destroy()). Everything is client-side, anchored (rubble aside), non-colliding, non-querying,
-- and parented under the caller's folder (or workspace.LocalFX.OneForAll when the caller gives none).
-- Angles: halfAngle / cone arguments are DEGREES (a value <= pi/2 is taken as radians); windBend's maxDeg is degrees.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = ReplicatedStorage:WaitForChild("OneForAllKit")
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
-- design section 2 palette; Config.Palette overrides every entry it has
local PAL = {
	Core = C(240, 255, 246), Cowl = C(64, 255, 140), CowlDeep = C(16, 176, 96), Emerald = C(0, 110, 70),
	Spark = C(205, 255, 220), Air = C(215, 240, 255), Crimson = C(255, 40, 66), Blood = C(128, 0, 22),
	Ember = C(255, 128, 96), Whip = C(14, 16, 18), Steam = C(236, 236, 236), Sun = C(255, 238, 196),
	Storm = C(58, 62, 66), StormDark = C(34, 38, 42), Suit = C(24, 64, 56),
}
if type(CFG.Palette) == "table" then
	for k, v in pairs(CFG.Palette) do
		PAL[k] = v
	end
end
-- (2026-11-07 perks) the CRIMSON COWL skin: OneForAllClient also requires a CLONE of this module flagged with the
-- attribute "AltSkin"; that copy draws everything with Config.AltPalette laid over the palette above
if script:GetAttribute("AltSkin") == true and type(CFG.AltPalette) == "table" then
	for k, v in pairs(CFG.AltPalette) do
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

local S = {}
S.FX, S.CFG, S.PAL = FX, CFG, PAL
S.LIMBS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
S.ARM_R = { "RightHand", "RightLowerArm", "RightUpperArm" } -- hand -> shoulder (the order Veins wants)
S.ARM_L = { "LeftHand", "LeftLowerArm", "LeftUpperArm" }
S.WHIP_SOURCES = { "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm" } -- R's tendril sources, cycled
S.OFA_SOURCES = { "RightHand", "LeftHand", "BackRight", "BackLeft", "RightLowerArm", "LeftLowerArm" } -- G's

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
	end
	return nil
end
local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end
local function camDist(p)
	p = vec(p)
	return p and (camPos() - p).Magnitude or math.huge
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
-- a hole / centre given as Vector2 (X, Z), Vector3 or CFrame -> x, z
local function xz(v, fallback)
	local t = typeof(v)
	if t == "Vector2" then
		return v.X, v.Y
	elseif t == "Vector3" then
		return v.X, v.Z
	elseif t == "CFrame" then
		return v.Position.X, v.Position.Z
	elseif typeof(fallback) == "Vector3" then
		return fallback.X, fallback.Z
	end
	return 0, 0
end
-- a CFrame at p whose -Z (LookVector) runs along dir, safe for vertical dirs
local WHIP_TURN = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's X axis onto a lookAt's -Z
local function lookAlong(p, dir)
	dir = unit(dir)
	return CFrame.lookAt(p, p + dir, math.abs(dir.Y) > 0.98 and Vector3.xAxis or UP)
end
local function angle(a, default)
	a = a or default
	if a <= math.pi / 2 then
		return a
	end
	return math.rad(a)
end
local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function torsoOf(model)
	if typeof(model) ~= "Instance" then
		return nil
	end
	if model:IsA("BasePart") then
		return model
	end
	return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
end
local function bez(a, b, c, d, u)
	local v = 1 - u
	return a * (v * v * v) + b * (3 * v * v * u) + c * (3 * v * u * u) + d * (u * u * u)
end

-- the kit's own FX folder (OneForAllClient makes workspace.LocalFX.OneForAll; it may also set S.Folder)
local function kitFolder()
	if live(S.Folder) then
		return S.Folder
	end
	local lfx = workspace:FindFirstChild("LocalFX")
	local f = lfx and lfx:FindFirstChild("OneForAll")
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

-- a handle with :Destroy() / :destroy() that runs `fn` once
local function handle(fn, fields)
	local h = fields or {}
	local done = false
	function h:Destroy()
		if done then
			return
		end
		done = true
		fn()
	end
	h.destroy = h.Destroy
	return h
end

S.now, S.camDist, S.flat, S.torsoOf, S.folder = now, camDist, flat, torsoOf, kitFolder

---------------------------------------------------------------------------------------------------
-- 3C: copied from GodspeedClient

-- no white-outs: a glow is never bigger than its effect and shrinks when the camera is close to it
function S.glowFor(pos, size)
	return (size or 1) * math.clamp(camDist(pos) / 30, 0.45, 1)
end

-- an afterimage: a ForceField copy of the body that fades where it stood
function S.ghost(char, color, alpha, life, offset)
	if not char or not char.Parent then
		return
	end
	color = color or PAL.Cowl
	alpha = alpha or 0.55
	life = life or 0.3
	local f = Instance.new("Folder")
	f.Name = "Afterimage"
	local parts = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Archivable then
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
				c.Material = FIELD
				c.Color = color
				c.Transparency = alpha
				c.CFrame = (offset and (CFrame.new(offset) * d.CFrame)) or d.CFrame
				c.Parent = f
				table.insert(parts, c)
			end
		end
	end
	f.Parent = kitFolder()
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, c in ipairs(parts) do
		TweenService:Create(c, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(f, life + 0.1)
	return f
end

-- a short arc jumping between two random parts of a body
function S.bodyArc(f, model, color, width)
	if not model then
		return
	end
	local LIMBS = S.LIMBS
	local a = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	local b = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	if a and b and a ~= b and a:IsA("BasePart") and b:IsA("BasePart") then
		FX.bolt(f, a.Position + FX.randUnit() * 0.5, b.Position + FX.randUnit() * 0.5, {
			color = color or PAL.Cowl, width = width or 0.06, jag = 0.35, segments = 4, life = 0.09, restrike = 1,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- 3.1 limbArc: Full Cowl concentrated in one limb chain
function S.limbArc(f, model, limbs, color, width)
	limbs = limbs or S.ARM_R
	if not model or #limbs == 0 then
		return
	end
	local a = model:FindFirstChild(limbs[rng:NextInteger(1, #limbs)])
	local b = model:FindFirstChild(limbs[rng:NextInteger(1, #limbs)])
	if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
		FX.bolt(f, a.Position + FX.randUnit() * 0.35, b.Position + FX.randUnit() * 0.35, {
			color = color or PAL.Cowl, width = width or 0.05, jag = 0.4, segments = 4, life = 0.08, restrike = 1,
		})
	end
end

-- 3.2 bodyTrail: a comet streak on a flung body's UpperTorso for `secs`, then it fades out
function S.bodyTrail(model, color, width, secs)
	local ut = torsoOf(model) or (model and model:FindFirstChild("HumanoidRootPart"))
	if not ut or not ut:IsA("BasePart") then
		return
	end
	secs = secs or 0.6
	local tr = FX.trail(ut, color or cs(PAL.Air, PAL.Cowl), width or 1.6, 0.3, { tail = 0, brightness = 2 })
	local a0, a1 = tr.Attachment0, tr.Attachment1
	task.delay(secs, function()
		if tr.Parent then
			tr.Enabled = false
		end
	end)
	Debris:AddItem(tr, secs + 0.35)
	Debris:AddItem(a0, secs + 0.35)
	Debris:AddItem(a1, secs + 0.35)
	return tr
end

---------------------------------------------------------------------------------------------------
-- 3.3 steam(part, rate) -> handle: h:Emit(n) (a puff), h.Rate / h:setRate(r), h:stop() / h:Destroy() (Rate 0, the
-- attachment Debris'd after 1.5 s), h:kill() (now), h.Attachment, h.Emitter. A handle made with rate 0 that is
-- never given a rate stops itself after 3 s, so steam(arm, 0):Emit(30) cleans up on its own.
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

function S.steam(part, rate)
	local h = setmetatable({}, SteamMT)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		rawset(h, "dead", true)
		return h
	end
	local att = Instance.new("Attachment")
	att.Name = "OFASteam"
	local e = FX.emitter(att, {
		Texture = TEX.smoke, Color = cs(PAL.Steam, C(170, 170, 170)), LightInfluence = 1, LightEmission = 0,
		Size = nsk({ { 0, 0.6 }, { 0.4, 1.6 }, { 1, 2.6 } }), Transparency = nsk({ { 0, 0.55 }, { 0.5, 0.7 }, { 1, 1 } }),
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
	return h
end

---------------------------------------------------------------------------------------------------
-- 3.4 Veins: crimson cracks crawling up an arm. Veins.new(f, char, limbNames, opts) with limbs hand -> shoulder.
-- opts: perLimb (4 on the local character, 2 on others), segs 4, width 0.09, crawl 0.35, pulseHz 6, t0 (server time
-- the crawl starts, default now). Methods :fade(secs), :destroy() / :Destroy(). Several arms in one list each crawl
-- from their own hand (limbs are chained by their Right / Left prefix).
local Veins = {}
Veins.__index = Veins
S.Veins = Veins

local function sideOf(name)
	if name:find("^Right") then
		return "R"
	elseif name:find("^Left") then
		return "L"
	end
	return "C"
end

function Veins.new(f, char, limbNames, opts)
	opts = opts or {}
	limbNames = limbNames or S.ARM_R
	local lp = Players.LocalPlayer
	local isLocal = lp ~= nil and char == lp.Character
	local perLimb = opts.perLimb or (isLocal and 4 or 2)
	local segs = math.max(opts.segs or 4, 1)
	local w = opts.width or 0.09
	local self = setmetatable({
		char = char, list = {}, parts = {}, cfs = {}, lights = {}, t0 = opts.t0 or now(),
		crawl = opts.crawl or 0.35, pulseHz = opts.pulseHz or 6, dead = false,
	}, Veins)
	local folder = Instance.new("Folder")
	folder.Name = "Veins"
	self.folder = folder
	if typeof(char) ~= "Instance" then
		self.dead = true
		return self
	end
	local rank, chainLen = {}, {}
	for _, name in ipairs(limbNames) do
		local sd = sideOf(name)
		chainLen[sd] = (chainLen[sd] or 0) + 1
		rank[name] = chainLen[sd]
	end
	local maxChain = 1
	for _, n in pairs(chainLen) do
		maxChain = math.max(maxChain, n)
	end
	local total = maxChain * segs

	local function addSeg(L, p0, p1, width, k, phase)
		local len = (p1 - p0).Magnitude
		if len < 1e-3 then
			return
		end
		local localCF = CFrame.lookAt((p0 + p1) / 2, p1, Vector3.xAxis)
		local core = FX.part("VeinCore", BLOCK, NEON, PAL.Crimson, folder)
		core.Size = Vector3.new(width, width, len + width * 0.5)
		core.Transparency = 1
		local sheath = FX.part("VeinSheath", BLOCK, NEON, PAL.Blood, folder)
		sheath.Size = Vector3.new(width * 2.4, width * 2.4, len)
		sheath.Transparency = 1
		local cf = L.CFrame * localCF
		core.CFrame, sheath.CFrame = cf, cf
		table.insert(self.list, {
			limb = L, localCF = localCF, core = core, sheath = sheath, showAt = self.crawl * k / total, phase = phase, shown = false,
		})
		table.insert(self.parts, core)
		table.insert(self.cfs, cf)
		table.insert(self.parts, sheath)
		table.insert(self.cfs, cf)
	end

	for _, name in ipairs(limbNames) do
		local L = char:FindFirstChild(name)
		if L and L:IsA("BasePart") then
			local hx, hz = math.max(L.Size.X / 2, 0.05), math.max(L.Size.Z / 2, 0.05)
			local hy = L.Size.Y / 2
			-- the point on the box surface in direction `ang` (round the limb's Y axis), pushed 0.015 out
			local function surf(ang, y)
				local x, z = math.cos(ang), math.sin(ang)
				local sc = 1 / math.max(math.abs(x) / hx, math.abs(z) / hz)
				return Vector3.new(x * (sc + 0.015), y, z * (sc + 0.015))
			end
			local jit = 0.08 / math.max(hx, hz) -- +-0.08 studs of tangential jitter, as an angle
			local base = (rank[name] - 1) * segs
			for v = 1, perLimb do
				local phi = (v / perLimb) * TAU + rng:NextNumber(-0.3, 0.3)
				local phase = rng:NextNumber(0, TAU)
				local pts, angs = {}, {}
				for i = 0, segs do
					angs[i] = phi + rng:NextNumber(-jit, jit)
					pts[i] = surf(angs[i], -hy + 2 * hy * i / segs)
				end
				for i = 1, segs do
					addSeg(L, pts[i - 1], pts[i], w, base + i, phase)
				end
				-- a 50% side branch off the 2nd point: one segment, 0.6 long, 35 degrees off the vein
				if segs >= 2 and rng:NextNumber() < 0.5 then
					local p = pts[1]
					local d = (pts[2] - pts[1]).Unit
					local sgn = rng:NextNumber() < 0.5 and 1 or -1
					local tang = Vector3.new(-math.sin(angs[1]), 0, math.cos(angs[1])) * sgn
					local e = p + (d * math.cos(math.rad(35)) + tang * math.sin(math.rad(35))) * 0.6
					addSeg(L, p, surf(math.atan2(e.Z, e.X), e.Y), w * 0.8, base + 2, phase + 1.3)
				end
			end
			if name:find("LowerArm") then
				local a = Instance.new("Attachment")
				a.Name = "OFAVeinLight"
				local l = Instance.new("PointLight")
				l.Color = PAL.Crimson
				l.Brightness = 0
				l.Range = 6
				l.Shadows = false
				l.Parent = a
				a.Parent = L
				table.insert(self.lights, { att = a, light = l })
			end
		end
	end
	folder.Parent = parentOf(f)
	if #self.list == 0 then
		self:destroy()
		return self
	end
	self.conn = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
	return self
end

function Veins:_step()
	if self.dead then
		return
	end
	if not self.char.Parent or not self.folder.Parent then
		self:destroy()
		return
	end
	local tn = now()
	local t = tn - self.t0
	local fadeK = 0
	if self.fadeAt then
		fadeK = math.clamp((tn - self.fadeAt) / self.fadeDur, 0, 1)
	end
	local cfs = self.cfs
	local w2 = TAU * self.pulseHz
	for i, s in ipairs(self.list) do
		local L = s.limb
		local cf = L.Parent and (L.CFrame * s.localCF) or cfs[i * 2 - 1]
		cfs[i * 2 - 1] = cf
		cfs[i * 2] = cf
		if t >= s.showAt then
			local a = 0.05 + 0.3 * (0.5 + 0.5 * math.sin(w2 * t + s.phase))
			s.core.Transparency = a + (1 - a) * fadeK
			if not s.shown or self.fadeAt then
				s.shown = true
				s.sheath.Transparency = 0.55 + 0.45 * fadeK
			end
		end
	end
	workspace:BulkMoveTo(self.parts, cfs, BULK)
	local lk = math.clamp(t / math.max(self.crawl, 0.05), 0, 1) * (1 - fadeK)
	for _, l in ipairs(self.lights) do
		l.light.Brightness = 1.5 * lk
	end
	if self.fadeAt and fadeK >= 1 then
		self:destroy()
	end
end

function Veins:fade(secs)
	if self.dead then
		return
	end
	secs = math.max(secs or 0.5, 0.02)
	local tn = now()
	if self.fadeAt then
		local k = math.clamp((tn - self.fadeAt) / self.fadeDur, 0, 1)
		if tn + secs * (1 - k) >= self.fadeAt + self.fadeDur then
			return -- the running fade already ends sooner
		end
		self.fadeAt, self.fadeDur = tn - k * secs, secs
		return
	end
	self.fadeAt, self.fadeDur = tn, secs
end

function Veins:destroy()
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	for _, l in ipairs(self.lights) do
		l.att:Destroy()
	end
	self.lights = {}
	self.folder:Destroy()
end
Veins.Destroy = Veins.destroy
S.veins = function(...)
	return Veins.new(...)
end

---------------------------------------------------------------------------------------------------
-- 3.5 Tendril: one Blackwhip lash. Tendril.new(f, getSource, opts); getSource() -> the live world point it grows
-- from (S.tendrilSource builds one). opts: segs 14, w0 0.5, w1 0.14, speed 220, wobble 1.6, target (a model; its
-- UpperTorso is the latch point) or endPoint (a whiff), lashT (server time the lash leaves, default now),
-- crackle (true), autoLatch (latch on arrival), autoRetract (whiff: retract on arrival), onArrive(self), maxLife 12.
-- Phases: extend -> :latch(model?) (taut + wrap band) | :retract() (0.22 s back to the source) | :snap() (fade,
-- sparks, gone at 0.2 s). :destroy() / :Destroy() at once. :tipPos(). Fields: state, target, arrived.
-- Auto-snaps if the target loses its UpperTorso or gains GrabbedBy / InDomain, or the source disappears.
local Tendril = {}
Tendril.__index = Tendril
S.Tendril = Tendril

local function grabbed(m)
	return typeof(m) == "Instance" and (m:GetAttribute("GrabbedBy") or m:GetAttribute("InDomain")) and true or false
end

-- a getSource for Tendril.new: a part name ("RightHand", "LeftLowerArm", ...) or "BackRight" / "BackLeft"
-- (UpperTorso.CFrame * (+-0.6, 0.6, 0.6): the two that burst from his back)
function S.tendrilSource(char, which)
	return function()
		if not char or not char.Parent then
			return nil
		end
		if which == "BackRight" or which == "BackLeft" then
			local ut = torsoOf(char)
			return ut and (ut.CFrame * Vector3.new(which == "BackRight" and 0.6 or -0.6, 0.6, 0.6)) or nil
		end
		local p = char:FindFirstChild(which or "RightHand")
		return p and p:IsA("BasePart") and p.Position or nil
	end
end

function Tendril.new(f, getSource, opts)
	opts = opts or {}
	local segs = math.max(opts.segs or 14, 2)
	local fp = parentOf(f)
	local self = setmetatable({
		f = fp, getSource = getSource, segs = segs, w0 = opts.w0 or 0.5, w1 = opts.w1 or 0.14,
		speed = opts.speed or 220, wobble = opts.wobble or 1.6, target = opts.target, endPoint = vec(opts.endPoint),
		lashT = opts.lashT or now(), phase = rng:NextNumber(0, TAU), state = "extend", tension = 0,
		crackle = opts.crackle ~= false, autoLatch = opts.autoLatch, autoRetract = opts.autoRetract, onArrive = opts.onArrive,
		cores = {}, halos = {}, widths = {}, lens = {}, band = {}, parts = {}, cfs = {}, nextCrackle = 0, dead = false,
		arrived = false,
	}, Tendril)
	local folder = Instance.new("Folder")
	folder.Name = "Tendril"
	self.folder = folder
	local src = self:_source() or vec(opts.endPoint) or Vector3.zero
	self.lastS, self.tip, self.S0, self.P1, self.P2 = src, src, src, src, src
	self.dir = unit((self:_goal() or (src + Vector3.new(0, 0, -1))) - src)
	for i = 1, segs do
		local wi = self.w0 + (self.w1 - self.w0) * (i - 1) / (segs - 1)
		-- round segments (a cylinder's axis is its X, turned onto the segment by WHIP_TURN) so the whip reads as a
		-- rope, not a chain of boxes; the green sheath kept slim so it never swells into a slab near the camera
		local core = FX.part("WhipCore", CYL, PLASTIC, PAL.Whip, folder)
		core.Size = Vector3.new(0.1, wi, wi)
		local halo = FX.part("WhipHalo", CYL, NEON, PAL.Cowl, folder)
		halo.Transparency = 0.82
		halo.Size = Vector3.new(0.1, wi * 1.55, wi * 1.55)
		self.cores[i], self.halos[i], self.widths[i], self.lens[i] = core, halo, wi, -1
		table.insert(self.parts, core)
		table.insert(self.parts, halo)
	end
	local tip = FX.part("WhipTip", BALL, NEON, PAL.Cowl, folder)
	tip.Size = Vector3.one * (self.w1 * 3)
	FX.trail(tip, cs(PAL.Cowl, PAL.Core), 0.4, 0.15)
	self.tipPart = tip
	table.insert(self.parts, tip)
	for i = 1, #self.parts do
		self.cfs[i] = CFrame.new(src)
		self.parts[i].CFrame = self.cfs[i]
	end
	folder.Parent = fp
	Debris:AddItem(folder, opts.maxLife or 12)
	self.conn = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
	return self
end

function Tendril:_source()
	local ok, p = pcall(self.getSource)
	p = ok and vec(p) or nil
	if p then
		self.lastS = p
	end
	return p
end

function Tendril:_goal()
	if self.target then
		local t = torsoOf(self.target)
		if t then
			return t.Position
		end
	end
	return self.endPoint
end

function Tendril:tipPos()
	return self.tip
end

function Tendril:_step()
	if self.dead or self.state == "snap" then
		return
	end
	if not self.folder.Parent then
		self:destroy()
		return
	end
	local S0 = self:_source()
	if not S0 then
		self:snap()
		return
	end
	local st = self.state
	if (st == "extend" or st == "latched") and self.target then
		local ut = self.target.Parent and torsoOf(self.target)
		if not ut or not ut.Parent or grabbed(self.target) then
			self:snap()
			return
		end
	end
	local tip
	if st == "extend" then
		local goal = self:_goal() or (S0 + self.dir * 10)
		local rel = goal - S0
		local dist = rel.Magnitude
		if dist > 1e-3 then
			self.dir = rel / dist
		end
		local reach = math.max(0, (now() - self.lashT) * self.speed)
		if reach >= dist then
			tip = goal
			if not self.arrived then
				self.arrived = true
				if self.onArrive then
					task.spawn(self.onArrive, self)
				end
				if self.autoLatch and self.target then
					self:latch()
				elseif self.autoRetract and not self.target then
					self:retract()
				end
			end
		else
			tip = S0 + self.dir * reach
		end
		self.tension = 0
	elseif st == "latched" then
		tip = self:_goal() or self.tip
		self.tension = 0.85
	else -- retract
		local u = math.clamp((os.clock() - self.rT0) / 0.22, 0, 1)
		tip = self.rFrom:Lerp(S0, 1 - (1 - u) * (1 - u))
		self.tension = 0.4
		if u >= 1 then
			self:destroy()
			return
		end
	end
	if self.state == "snap" or self.dead then
		return
	end
	self.tip = tip

	-- the cubic Bezier S -> P1 -> P2 -> tip
	local d = tip - S0
	local len = d.Magnitude
	local side, up = FX.perp(len > 1e-3 and d / len or self.dir)
	local clock = os.clock()
	local wob = self.wobble * (1 - self.tension) * math.clamp(len / 8, 0, 1)
	local buzz = self.tension > 0.5 and 0.06 or 0
	local P1 = S0 + d * 0.33 + side * (math.sin(17 * clock + self.phase) * wob + math.sin(97 * clock) * buzz)
	local P2 = S0 + d * 0.66 + up * (math.cos(13 * clock + self.phase) * wob + math.cos(89 * clock) * buzz)
	self.S0, self.P1, self.P2 = S0, P1, P2
	local n = self.segs
	local cfs = self.cfs
	local prev = S0
	for i = 1, n do
		local p = bez(S0, P1, P2, tip, i / n)
		local seg = p - prev
		local sl = seg.Magnitude
		local cf
		if sl > 1e-3 then
			cf = CFrame.lookAt((prev + p) / 2, p, math.abs(seg.Y / sl) > 0.98 and Vector3.xAxis or UP)
		else
			cf = CFrame.new(p)
		end
		if math.abs(sl - self.lens[i]) > 0.02 * math.max(sl, 0.5) then
			local wi = self.widths[i]
			self.lens[i] = sl
			self.cores[i].Size = Vector3.new(sl + wi * 0.5, wi, wi)
			self.halos[i].Size = Vector3.new(math.max(sl, 0.05), wi * 1.55, wi * 1.55)
		end
		cf = cf * WHIP_TURN
		cfs[2 * i - 1] = cf
		cfs[2 * i] = cf
		prev = p
	end
	cfs[2 * n + 1] = CFrame.new(tip)
	if self.bandOn then
		local ut = self.bandTorso
		if ut and ut.Parent then
			local bcf = ut.CFrame * CFrame.Angles(math.rad(18), 0, 0)
			for j, b in ipairs(self.band) do
				cfs[2 * n + 1 + j] = bcf * b.lcf
			end
		end
	end
	workspace:BulkMoveTo(self.parts, cfs, BULK)

	-- crackle: green arcs running along the whip
	if self.crackle and clock >= self.nextCrackle and len > 1 and camDist(tip) < 160 then
		self.nextCrackle = clock + 0.07
		local u = rng:NextNumber(0, 0.85)
		FX.bolt(self.f, bez(S0, P1, P2, tip, u), bez(S0, P1, P2, tip, u + 0.15) + FX.randUnit() * 0.3, {
			color = rng:NextNumber() < 0.75 and PAL.Cowl or PAL.Core, width = 0.04, jag = 0.35, segments = 3, life = 0.08,
		})
	end
end

-- taut on the body, with the black wrap band coiled round its chest
function Tendril:latch(model)
	if self.dead or self.state == "snap" then
		return
	end
	if model then
		self.target = model
	end
	local ut = torsoOf(self.target)
	if not ut then
		return
	end
	self.state = "latched"
	self.arrived = true
	if self.bandOn then
		return
	end
	self.bandOn = true
	self.bandTorso = ut
	-- 8 blocks in a ring round the torso's Y axis, tilted 18 degrees; radius 0.85, widened to clear the torso box
	local rx = math.max(0.85, ut.Size.X / 2 + 0.1)
	local rz = math.max(0.35, ut.Size.Z / 2 + 0.1)
	local bcf = ut.CFrame * CFrame.Angles(math.rad(18), 0, 0)
	for j = 1, 8 do
		local a0, a1 = (j - 1) / 8 * TAU, j / 8 * TAU
		local p0 = Vector3.new(math.cos(a0) * rx, 0, math.sin(a0) * rz)
		local p1 = Vector3.new(math.cos(a1) * rx, 0, math.sin(a1) * rz)
		local b = FX.part("WhipBand", BLOCK, PLASTIC, PAL.Whip, self.folder)
		b.Size = Vector3.new(0.18, 0.18, (p1 - p0).Magnitude + 0.12)
		local lcf = CFrame.lookAt((p0 + p1) / 2, p1)
		b.CFrame = bcf * lcf
		table.insert(self.band, { part = b, lcf = lcf })
		table.insert(self.parts, b)
		table.insert(self.cfs, b.CFrame)
	end
end

function Tendril:retract()
	if self.dead or self.state == "snap" or self.state == "retract" then
		return
	end
	self.state = "retract"
	self.rFrom = self.tip
	self.rT0 = os.clock()
	for _, b in ipairs(self.band) do
		b.part.Transparency = 1
	end
end

function Tendril:snap()
	if self.dead or self.state == "snap" then
		return
	end
	self.state = "snap"
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.tip and live(self.f) then
		FX.sparks(self.f, self.tip, { color = PAL.Spark, color2 = PAL.Cowl, count = 10, speed = { 12, 34 }, size = 0.4 })
	end
	local tr = self.tipPart:FindFirstChildOfClass("Trail")
	if tr then
		tr.Enabled = false
	end
	local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, p in ipairs(self.parts) do
		if p.Parent then
			TweenService:Create(p, info, { Transparency = 1, Size = p.Size * 0.4 }):Play()
		end
	end
	Debris:AddItem(self.folder, 0.2)
end

function Tendril:destroy()
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	self.folder:Destroy()
end
Tendril.Destroy = Tendril.destroy
S.tendril = function(...)
	return Tendril.new(...)
end

---------------------------------------------------------------------------------------------------
-- 3.6 pressureFront: a ForceField disc of shimmering air marching out along dir, leaving rings behind it.
-- opts: color Air, rim Air, rimEvery 8, thickness 0.5, alpha0 0.25, t0 (server time it leaves, default now).
function S.pressureFront(f, origin, dir, range, halfAngle, speed, opts)
	opts = opts or {}
	origin = vec(origin) or Vector3.zero
	dir = unit(dir)
	range = math.max(range or 80, 1)
	speed = math.max(speed or 260, 1)
	local fp = parentOf(f)
	local tanA = math.tan(angle(halfAngle, 24))
	local thickness = opts.thickness or 0.5
	local alpha0 = opts.alpha0 or 0.25
	local rimEvery = math.max(opts.rimEvery or 8, 1)
	local rim = opts.rim or PAL.Air
	local turn = CFrame.Angles(0, math.rad(90), 0) -- the cylinder's X axis along dir
	local disc = FX.part("PressureFront", CYL, FIELD, opts.color or PAL.Air, nil)
	disc.Transparency = 1 - math.min(alpha0, 0.22)
	disc.Size = Vector3.new(thickness, 4, 4)
	disc.CFrame = lookAlong(origin, dir) * turn
	disc.Parent = fp
	local tStart = opts.t0 or now()
	local d0 = (now() - tStart) * speed
	local nextRim = math.max(rimEvery, math.ceil((d0 - speed * 0.25) / rimEvery) * rimEvery)
	local conn
	local h = handle(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		disc:Destroy()
	end, { part = disc })
	conn = RunService.Heartbeat:Connect(function()
		if not disc.Parent then
			h:Destroy()
			return
		end
		local d = (now() - tStart) * speed
		if d > range then
			h:Destroy()
			return
		end
		d = math.max(d, 0)
		local p = origin + dir * d
		local r = 2 + d * tanA
		disc.CFrame = lookAlong(p, dir) * turn
		disc.Size = Vector3.new(thickness, 2 * r, 2 * r)
		-- alpha0 is the disc's starting OPACITY, capped so a front that fills the view reads as a shimmer and never
		-- washes the screen out; seen from behind (the camera looking through its face) it fades further the more of the
		-- view it covers
		local op = math.min(alpha0, 0.22) * (1 - (d / range) ^ 1.5)
		local cam = workspace.CurrentCamera
		if cam then
			local rel = p - cam.CFrame.Position
			if rel:Dot(dir) > 0 then
				op *= math.clamp(rel.Magnitude / (r * 4), 0.25, 1)
			end
		end
		disc.Transparency = 1 - op
		while d >= nextRim do
			local rr = 2 + nextRim * tanA
			FX.ring(fp, origin + dir * nextRim, dir, rr * 1.4, rr * 2.1, rim, 0.22, { alpha = 0.35, brightness = 1.2 })
			nextRim += rimEvery
		end
	end)
	Debris:AddItem(disc, math.max(tStart - now(), 0) + range / speed + 2)
	return h
end

---------------------------------------------------------------------------------------------------
-- 3.7 world wind. windGust(vec, attack, hold, release, at?) / swirl(mag, revPerSec, dur, at?) add to
-- workspace.GlobalWind (base captured at the first gust, written back when the last ends); `at` skips the gust when
-- the camera is more than 220 studs from it. windBend(origin, dir_or_nil, range, maxDeg, dur, halfAngle?) sways the
-- Arena.Decor trees on a damped spring (cone = halfAngle (default 24) + 30 degrees). windReset() ends all of it.
local gusts = {}
local windBase = nil
local windConn = nil

local function envelope(t, a, h, r)
	if t < 0 then
		return 0
	end
	if t < a then
		return smooth(t / a)
	end
	t -= a
	if t < h then
		return 1
	end
	t -= h
	if t < r then
		return 1 - smooth(t / r)
	end
	return nil
end

local function windStep()
	local clock = os.clock()
	local sum = Vector3.zero
	for i = #gusts, 1, -1 do
		local g = gusts[i]
		local t = clock - g.t0
		local w = envelope(t, g.a, g.h, g.r)
		if not w then
			table.remove(gusts, i)
		else
			local v = g.vec
			if g.swirl then
				local ang = t * g.rev * TAU
				v = Vector3.new(math.cos(ang), 0, math.sin(ang)) * g.mag
			end
			sum += v * w
		end
	end
	if #gusts == 0 then
		if windBase then
			workspace.GlobalWind = windBase
		end
		windBase = nil
		if windConn then
			windConn:Disconnect()
			windConn = nil
		end
	else
		workspace.GlobalWind = (windBase or Vector3.zero) + sum
	end
end

local function addGust(g)
	if not windBase then
		windBase = workspace.GlobalWind
	end
	g.t0 = os.clock()
	table.insert(gusts, g)
	if not windConn then
		windConn = RunService.Heartbeat:Connect(windStep)
	end
end

function S.windGust(v, attack, hold, release, at)
	if typeof(v) ~= "Vector3" then
		return
	end
	if at and camDist(at) > 220 then
		return
	end
	addGust({ vec = v, a = math.max(attack or 0.1, 0), h = math.max(hold or 0.2, 0), r = math.max(release or 0.5, 0) })
end

function S.swirl(mag, revPerSec, dur, at)
	if at and camDist(at) > 220 then
		return
	end
	dur = math.max(dur or 1.4, 0.1)
	local a, r = math.min(0.3, dur * 0.25), math.min(0.5, dur * 0.35)
	addGust({ swirl = true, vec = Vector3.zero, mag = mag or 40, rev = revPerSec or 1, a = a, h = math.max(dur - a - r, 0), r = r })
end

local bending = {}
local boxCache = setmetatable({}, { __mode = "k" })
local bendConn = nil

local function bendStep()
	local clock = os.clock()
	for m, st in pairs(bending) do
		local t = clock - st.t0
		if t >= st.dur or not m.Parent then
			if m.Parent then
				pcall(m.PivotTo, m, st.saved)
			end
			bending[m] = nil
		else
			local th = st.maxDeg * math.sin(11 * t) * math.exp(-3.2 * t) / 0.66
			pcall(m.PivotTo, m, CFrame.new(st.base) * CFrame.fromAxisAngle(st.axis, math.rad(th)) * CFrame.new(-st.base) * st.saved)
		end
	end
	if next(bending) == nil and bendConn then
		bendConn:Disconnect()
		bendConn = nil
	end
end

function S.windBend(origin, dir, range, maxDeg, dur, halfAngle)
	origin = vec(origin)
	if not origin then
		return
	end
	local arena = workspace:FindFirstChild("Arena")
	local decor = arena and arena:FindFirstChild("Decor")
	if not decor then
		return
	end
	range = range or 140
	maxDeg = maxDeg or 9
	dur = dur or 1.5
	local fdir = dir and flat(dir, nil)
	local cone = angle(halfAngle, 24) + math.rad(30)
	local lp = Players.LocalPlayer
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local me = hrp and hrp.Position
	for _, m in ipairs(decor:GetChildren()) do
		if m:IsA("PVInstance") then
			local st = bending[m]
			local saved = st and st.saved or m:GetPivot()
			local box = boxCache[m]
			if not box or (not st and box.pivot ~= saved) then
				local cf, size
				if m:IsA("Model") then
					cf, size = m:GetBoundingBox()
				elseif m:IsA("BasePart") then
					cf, size = m.CFrame, m.Size
				end
				if cf then
					box = { pivot = saved, center = cf.Position, base = cf.Position - UP * (size.Y / 2) }
					boxCache[m] = box
				end
			end
			if box then
				local rel = (box.center - origin) * FLAT
				local dist = rel.Magnitude
				local nearMe = me and ((box.center - me) * FLAT).Magnitude <= 12
				if dist <= range and not nearMe then
					local wind
					if fdir then
						if dist < 1e-3 or math.acos(math.clamp(rel.Unit:Dot(fdir), -1, 1)) <= cone then
							wind = fdir
						end
					elseif dist > 1e-3 then
						wind = rel.Unit
					end
					if wind then
						bending[m] = {
							saved = saved, base = box.base, axis = UP:Cross(wind).Unit, maxDeg = maxDeg * (1 - dist / range),
							t0 = os.clock(), dur = dur,
						}
					end
				end
			end
		end
	end
	if next(bending) ~= nil and not bendConn then
		bendConn = RunService.Heartbeat:Connect(bendStep)
	end
end

function S.windReset()
	table.clear(gusts)
	if windBase then
		workspace.GlobalWind = windBase
	end
	windBase = nil
	if windConn then
		windConn:Disconnect()
		windConn = nil
	end
	for m, st in pairs(bending) do
		if m.Parent then
			pcall(m.PivotTo, m, st.saved)
		end
	end
	table.clear(bending)
	if bendConn then
		bendConn:Disconnect()
		bendConn = nil
	end
end

---------------------------------------------------------------------------------------------------
-- 3.8 dust. groundColor(hit) -> colour, material (GojoFX's groundLook). dust(f, pos, vel, o) with o: s0 4, s1 12,
-- count 2, life {1.4, 2.2} (or a number), color (default: the ground under pos). dustLine / dustRing take the same
-- `o` as their last argument.
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

-- the dust doughnut: n puffs round a circle rolling outward
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
-- 3.9 StormDeck: the ultimate's sky. StormDeck.new(f, center, groundY, height = 170, o) with o: elapsed (seconds
-- already past since the cast, for late joiners: skips the gathering), grade (false = no ColorCorrection), maxLife 30.
-- :tear(holeXZ, t0) (holeXZ: Vector2 (X, Z) / Vector3 / CFrame; t0 server time), :dissolve(gradeSecs = 2),
-- :cancel() (dissolve now, grade back over 0.6 s), :destroy() / :Destroy() (everything now).
local StormDeck = {}
StormDeck.__index = StormDeck
S.StormDeck = StormDeck
local DECK_RINGS = { { 0, 1 }, { 50, 6 }, { 100, 9 }, { 150, 11 }, { 200, 13 } }
local NEUTRAL = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }

function StormDeck.new(f, center, groundY, height, o)
	o = o or {}
	center = vec(center) or Vector3.zero
	groundY = groundY or center.Y
	height = height or 170
	local fp = parentOf(f)
	local alt = groundY + height
	local self = setmetatable({
		f = fp, center = center, alt = alt, hosts = {}, parts = {}, cfs = {}, dead = false, dissolving = false,
		nextBolt = os.clock() + 0.25,
	}, StormDeck)
	local folder = Instance.new("Folder")
	folder.Name = "StormDeck"
	self.folder = folder
	local elapsed = o.elapsed or 0
	for _, ring in ipairs(DECK_RINGS) do
		local r, count = ring[1], ring[2]
		local off = rng:NextNumber(0, TAU)
		for j = 1, count do
			local ang = off + (j / count) * TAU + (r > 0 and rng:NextNumber(-0.15, 0.15) or 0)
			local rr = r > 0 and (r + rng:NextNumber(-8, 8)) or 0
			local pos = Vector3.new(center.X + math.cos(ang) * rr, alt + rng:NextNumber(-6, 6), center.Z + math.sin(ang) * rr)
			local host = FX.part("StormHost", BLOCK, PLASTIC, WHITE, folder)
			host.Transparency = 1
			host.Size = Vector3.one
			host.CFrame = CFrame.new(pos)
			local m = rng:NextNumber(0.8, 1.2)
			local e = FX.emitter(host, {
				Texture = TEX.smoke, LockedToPart = true, Orientation = Enum.ParticleOrientation.FacingCamera,
				Color = cs(PAL.Storm, PAL.StormDark), LightInfluence = 0.15, LightEmission = 0, -- dark: the sun must not lift it to sky blue
				Size = nsk({ { 0, 38 * m }, { 0.5, 58 * m }, { 1, 66 * m } }),
				Transparency = nsk({ { 0, 1 }, { 0.15, 0.02 }, { 0.85, 0.06 }, { 1, 1 } }), -- the soft smoke texture needs near-solid puffs to read as a deck
				Lifetime = NumberRange.new(3.5, 4.5), Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-6, 6), ZOffset = -3, Rate = 0,
			})
			local h = { part = host, emitter = e, pos = pos }
			table.insert(self.hosts, h)
			table.insert(self.parts, host)
			table.insert(self.cfs, host.CFrame)
			-- gathering: outer rings first
			task.delay(math.max((1 - rr / 200) * 0.6 - elapsed, 0), function()
				if not self.dead and not self.dissolving and host.Parent and not h.torn then
					e:Emit(4)
					e.Rate = 1.2
				end
			end)
		end
	end
	folder.Parent = fp
	if o.grade ~= false then
		local cam = workspace.CurrentCamera
		if cam then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "OFAStorm"
			cc.Parent = cam
			self.grade = cc
			TweenService:Create(cc, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				Brightness = -0.07, Contrast = 0.12, Saturation = -0.15, TintColor = PAL.StormTint or C(225, 240, 232),
			}):Play()
		end
	end
	self.conn = RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	task.delay(o.maxLife or 30, function()
		self:destroy()
	end)
	return self
end

function StormDeck:_step()
	if self.dead then
		return
	end
	if not self.folder.Parent then
		self:destroy()
		return
	end
	local clock = os.clock()
	if not self.dissolving and clock >= self.nextBolt then
		self.nextBolt = clock + 0.25
		self:_bolt()
	end
	if self.tearT0 and not self.tearDone then
		local u = math.clamp((now() - self.tearT0) / 1.1, 0, 1)
		local R = 210 * (1 - (1 - u) ^ 3)
		local hole = self.hole
		for i, h in ipairs(self.hosts) do
			if h.r0 < R + 20 then
				local nr = R + 20 + (h.r0 - R) * 0.3
				self.cfs[i] = CFrame.new(hole.X + h.radial.X * nr, h.pos.Y, hole.Z + h.radial.Z * nr)
				if not h.torn then
					h.torn = true
					h.emitter.Rate = 0
				end
			end
		end
		workspace:BulkMoveTo(self.parts, self.cfs, BULK)
		if u >= 1 then
			self.tearDone = true
		end
	end
end

-- inner lightning: a green bolt between two hosts less than 80 studs apart
function StormDeck:_bolt()
	local n = #self.cfs
	if n < 2 or not live(self.f) then
		return
	end
	local ia = rng:NextInteger(1, n)
	local pa = self.cfs[ia].Position
	local cands = {}
	for i = 1, n do
		if i ~= ia and (self.cfs[i].Position - pa).Magnitude < 80 then
			cands[#cands + 1] = i
		end
	end
	if #cands == 0 then
		return
	end
	local pb = self.cfs[cands[rng:NextInteger(1, #cands)]].Position
	FX.bolt(self.f, pa, pb, { color = PAL.Cowl, core = PAL.Core, width = 0.6, jag = 0.25, life = 0.2, restrike = 1 })
	FX.light(self.f, (pa + pb) / 2, PAL.Cowl, 6, 60, 0.25)
end

function StormDeck:_gradeOut(secs)
	local cc = self.grade
	if not cc or self.gradeOut then
		return
	end
	self.gradeOut = true
	if cc.Parent then
		TweenService:Create(cc, TweenInfo.new(secs, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), NEUTRAL):Play()
	end
	Debris:AddItem(cc, secs + 0.05)
end

-- the 100% smash shoves the clouds open from the centre
function StormDeck:tear(holeXZ, t0)
	if self.dead or self.tearT0 then
		return
	end
	local hx, hz = xz(holeXZ, self.center)
	self.hole = Vector3.new(hx, self.alt, hz)
	self.tearT0 = t0 or now()
	for _, h in ipairs(self.hosts) do
		local rel = Vector3.new(h.pos.X - hx, 0, h.pos.Z - hz)
		h.r0 = rel.Magnitude
		if h.r0 > 1e-2 then
			h.radial = rel / h.r0
		else
			local a = rng:NextNumber(0, TAU)
			h.radial = Vector3.new(math.cos(a), 0, math.sin(a))
		end
	end
	if now() - self.tearT0 < 0.6 and live(self.f) then
		FX.ring(self.f, self.hole, -UP, 10, 420, PAL.Sun, 1.1, { alpha = 0.35, brightness = 1.2 })
		FX.ring(self.f, self.hole, -UP, 5, 300, PAL.Air, 0.8, { alpha = 0.2 })
	end
	local cc = self.grade
	if cc and cc.Parent and not self.gradeOut then
		TweenService:Create(cc, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = C(255, 246, 225), Brightness = 0.03, Contrast = 0.06, Saturation = 0,
		}):Play()
		task.delay(math.max(self.tearT0 + 2 - now(), 0), function()
			self:_gradeOut(2)
		end)
	end
end

function StormDeck:dissolve(gradeSecs)
	if self.dead then
		return
	end
	if self.dissolving then
		if gradeSecs then
			self:_gradeOut(gradeSecs)
		end
		return
	end
	self.dissolving = true
	for _, h in ipairs(self.hosts) do
		h.emitter.Rate = 0
	end
	self:_gradeOut(gradeSecs or 2)
	task.delay(4.5, function()
		self:destroy()
	end)
end

function StormDeck:cancel()
	self:dissolve(0.6)
end

function StormDeck:destroy()
	if self.dead then
		return
	end
	self.dead = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.grade and not self.gradeOut then
		self.grade:Destroy()
	end
	self.folder:Destroy()
end
StormDeck.Destroy = StormDeck.destroy
S.stormDeck = function(...)
	return StormDeck.new(...)
end

---------------------------------------------------------------------------------------------------
-- 3.10 airColumn(f, base, height, o): the 100% smash's air pillar. o: speed 520, r0 7, r1 16, hold 0.4, fade 0.8,
-- onTop (called once when it reaches the top), t0 (server time it starts, default now).
-- Returns a handle: :Destroy() (now), :fadeOut() (the normal ending early), .outer, .inner.
function S.airColumn(f, base, height, o)
	o = o or {}
	base = vec(base) or Vector3.zero
	height = math.max(height or 150, 1)
	local fp = parentOf(f)
	local speed, r0, r1 = math.max(o.speed or 520, 1), o.r0 or 7, o.r1 or 16
	local hold, fade = o.hold or 0.4, o.fade or 0.8
	local vert = CFrame.Angles(0, 0, math.rad(90))
	local outer = FX.part("AirColumn", CYL, FIELD, PAL.Air, nil)
	outer.Transparency = 0.1
	outer.Size = Vector3.new(0.1, 2 * r0, 2 * r0)
	outer.CFrame = CFrame.new(base) * vert
	local inner = FX.part("AirColumnCore", CYL, NEON, PAL.Core, nil)
	inner.Transparency = 0.55
	inner.Size = Vector3.new(0.1, 5, 5)
	inner.CFrame = outer.CFrame
	outer.Parent, inner.Parent = fp, fp
	local helix = FX.helix(fp, { PAL.Cowl, PAL.Crimson, PAL.Core }, r0 * 0.9, 0.9)
	local ringCols = { PAL.Air, PAL.Cowl, PAL.Crimson }
	local tS = o.t0 or now()
	local nextRing, ringN, topped, faded = 10, 0, false, false
	local conn
	local function fadeOut()
		if faded then
			return
		end
		faded = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		helix:destroy()
		if outer.Parent then
			TweenService:Create(outer, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1, Size = outer.Size * Vector3.new(1, 1.25, 1.25),
			}):Play()
		end
		if inner.Parent then
			TweenService:Create(inner, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		Debris:AddItem(outer, fade + 0.1)
		Debris:AddItem(inner, 0.5)
	end
	local h = handle(function()
		faded = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
		helix:destroy()
		outer:Destroy()
		inner:Destroy()
	end, { outer = outer, inner = inner, fadeOut = fadeOut })
	conn = RunService.Heartbeat:Connect(function(dt)
		if not outer.Parent then
			h:Destroy()
			return
		end
		local L = math.clamp((now() - tS) * speed, 0.1, height)
		local r = r0 + (r1 - r0) * L / height
		local cf = CFrame.new(base + UP * (L / 2)) * vert
		outer.Size = Vector3.new(L, 2 * r, 2 * r)
		outer.CFrame = cf
		inner.Size = Vector3.new(L, 5, 5)
		inner.CFrame = cf
		while L >= nextRing do
			ringN += 1
			FX.ring(fp, base + UP * nextRing, UP, r * 1.3, r * 2.6, ringCols[(ringN - 1) % 3 + 1], 0.35, { alpha = 0.3 })
			nextRing += 10
		end
		helix.radius = r * 0.9
		helix:place(base + UP * L, UP, dt)
		if L >= height and not topped then
			topped = true
			if o.onTop then
				task.spawn(o.onTop)
			end
			task.delay(hold, fadeOut)
		end
	end)
	local safety = math.max(tS - now(), 0) + height / speed + hold + fade + 3
	Debris:AddItem(outer, safety)
	Debris:AddItem(inner, safety)
	return h
end

---------------------------------------------------------------------------------------------------
-- 3.11 sunShafts(f, holeXZ, altY, groundY, n = 5, o): god rays through the hole. o: fadeIn 0.6, holdUntil 2.7,
-- fadeOut 1.6 (seconds after the call: cast 1.90 -> 4.6 -> 6.2), elapsed (late joiners), tilt 8 (degrees).
function S.sunShafts(f, holeXZ, altY, groundY, n, o)
	o = o or {}
	n = n or 5
	local fp = parentOf(f)
	local hx, hz = xz(holeXZ)
	groundY = groundY or 0
	altY = altY or (groundY + 170)
	local tilt = math.rad(o.tilt or 8)
	local ok, sun = pcall(function()
		return Lighting:GetSunDirection()
	end)
	local toward = flat(ok and -sun or nil, nil) -- the way the sunlight travels, flattened
	local axis = toward and (-UP * math.cos(tilt) + toward * math.sin(tilt)).Unit or -UP
	local len = math.max(altY - groundY, 10) / math.max(-axis.Y, 0.2)
	local fadeIn, holdUntil, fadeOut = o.fadeIn or 0.6, o.holdUntil or 2.7, o.fadeOut or 1.6
	local el = o.elapsed or 0
	local shafts = {}
	local off = rng:NextNumber(0, TAU)
	for i = 1, n do
		local r = rng:NextNumber(10, 26)
		local ang = off + (i / n) * TAU + rng:NextNumber(-0.35, 0.35)
		local dist = math.max(rng:NextNumber(25, 70), 25 + r) -- in the 25-70 annulus, never within 25 of Deku
		local g = Vector3.new(hx + math.cos(ang) * dist, groundY, hz + math.sin(ang) * dist)
		local p = FX.part("SunShaft", CYL, NEON, PAL.Sun, nil)
		p.Size = Vector3.new(len, 2 * r, 2 * r)
		p.CFrame = lookAlong(g - axis * (len / 2), axis) * CFrame.Angles(0, math.rad(90), 0)
		p.Transparency = 1
		local e = FX.emitter(p, {
			Texture = TEX.star, Color = cs(PAL.Sun), Size = NumberSequence.new(0.25), Lifetime = NumberRange.new(2),
			Speed = NumberRange.new(1), Rate = 6, Transparency = NumberSequence.new(0.4), LightEmission = 1,
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		})
		p.Parent = fp
		table.insert(shafts, p)
		if el < holdUntil then
			local k = math.clamp(el / fadeIn, 0, 1)
			p.Transparency = 1 - 0.14 * k
			if k < 1 then
				TweenService:Create(p, TweenInfo.new(fadeIn * (1 - k), Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = 0.86 }):Play()
			end
		else
			e.Rate = 0
		end
		task.delay(math.max(holdUntil - el, 0), function()
			if p.Parent then
				e.Rate = 0
				TweenService:Create(p, TweenInfo.new(fadeOut, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(p, math.max(holdUntil + fadeOut - el, 0) + 0.3)
	end
	return handle(function()
		for _, p in ipairs(shafts) do
			p:Destroy()
		end
	end, { parts = shafts })
end

---------------------------------------------------------------------------------------------------
-- 3.12 airBullet(f, d, o?): Q's projectile on the server timeline. d = the AirForceCast payload
-- { t0, origin, dir, stop, windup, speed, mode }. o.scour = false turns the pebble scour off (it is gated to
-- 160 studs inside). Destroyed when it reaches `stop`; returns a handle (:Destroy(), .ball).
function S.airBullet(f, d, o)
	o = o or {}
	d = d or {}
	local fp = parentOf(f)
	local origin = vec(d.origin) or Vector3.zero
	local dir = unit(d.dir)
	local stop = math.max(d.stop or 95, 0)
	local speed = math.max(d.speed or 260, 1)
	local tFly = (d.t0 or now()) + (d.windup or 0.22)
	local mode = d.mode
	local ball = FX.part("AirBullet", BALL, NEON, PAL.Air, nil)
	ball.Size = Vector3.one * 1.1
	ball.Transparency = 0.35
	ball.CFrame = CFrame.new(origin)
	local core = FX.part("AirBulletCore", BALL, NEON, PAL.Core, nil)
	core.Size = Vector3.one * 0.5
	core.CFrame = ball.CFrame
	FX.trail(ball, cs(PAL.Air, PAL.Cowl), 1.2, 0.18, { tail = 0 })
	ball.Parent, core.Parent = fp, fp
	local helix = FX.helix(fp, mode and { PAL.Cowl, PAL.Crimson } or { PAL.Cowl, PAL.Core }, 0.8, 0.25)
	-- a late joiner starts part-way along and skips the rings / scour already long gone
	local d0 = math.clamp((now() - tFly) * speed, 0, stop)
	local nextRing = math.max(6, math.ceil((d0 - speed * 0.3) / 6) * 6)
	local ringN = math.floor(nextRing / 6) - 1
	local nextScour = math.max(8, math.ceil((d0 - speed * 0.3) / 8) * 8)
	local nextArc = 0
	local conn
	local h = handle(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		helix:destroy()
		ball.Transparency = 1
		core.Transparency = 1
		Debris:AddItem(ball, 0.3)
		Debris:AddItem(core, 0.05)
	end, { ball = ball })
	conn = RunService.Heartbeat:Connect(function(dt)
		if not ball.Parent then
			h:Destroy()
			return
		end
		local dist = math.clamp((now() - tFly) * speed, 0, stop)
		local p = origin + dir * dist
		ball.CFrame = CFrame.new(p)
		core.CFrame = ball.CFrame
		helix:place(p, dir, dt)
		while nextRing <= dist do
			ringN += 1
			local col = (mode and ringN % 3 == 0) and PAL.Crimson or PAL.Air
			FX.ring(fp, origin + dir * nextRing, dir, 0.6, 3.2, col, 0.3, { alpha = 0.45, brightness = 1 })
			nextRing += 6
		end
		local clock = os.clock()
		if dist > 0 and clock >= nextArc then
			nextArc = clock + 0.05
			FX.arcs(fp, p, 0.8, { count = 1, color = PAL.Cowl, width = 0.04 })
		end
		while nextScour <= dist do
			local sp = origin + dir * nextScour
			if o.scour ~= false and camDist(sp) < 160 then
				local hit = FX.groundHit(sp, 6)
				if hit then
					FX.rubble(fp, hit.Position, { count = 3, radius = 1, up = { 10, 25 }, out = { 4, 10 }, min = 0.3, max = 0.7, dir = dir })
				end
			end
			nextScour += 8
		end
		if dist >= stop then
			h:Destroy()
		end
	end)
	local safety = math.max(tFly - now(), 0) + stop / speed + 3
	Debris:AddItem(ball, safety)
	Debris:AddItem(core, safety)
	return h
end

---------------------------------------------------------------------------------------------------
-- 3.15 kickArc(f, pos, face, radius, tilt, colors): Killua's slashArc with colors { core, edge, mid } (default
-- Core / Cowl / CowlDeep). Sweeps from his right to his left, the way a right roundhouse travels.
function S.kickArc(f, pos, face, radius, tilt, colors)
	pos = vec(pos)
	if not pos then
		return
	end
	local fp = parentOf(f)
	colors = colors or {}
	local cCore, cEdge, cMid = colors.core or PAL.Core, colors.edge or PAL.Cowl, colors.mid or PAL.CowlDeep
	radius = radius or 6.5
	local frame = lookAlong(pos, flat(face, nil) or unit(face)) * CFrame.Angles(0, 0, tilt or math.rad(-26))
	local n = 14
	for layer = 1, 2 do
		local r = radius * (layer == 1 and 1 or 0.82)
		local pts = {}
		for i = 0, n do
			local a = math.rad(-82 + 164 * i / n)
			pts[i] = (frame * CFrame.new(math.sin(a) * r, (layer - 1) * 0.35, -math.cos(a) * r * 0.85)).Position
		end
		for i = 1, n do
			local mid = 1 - math.abs(((i - 0.5) / n) * 2 - 1) -- 0 at the tips, 1 in the middle
			local p0, p1 = pts[i - 1], pts[i]
			local w = (layer == 1 and 0.1 or 0.06) + (layer == 1 and 0.42 or 0.2) * mid
			local seg = FX.part("KickArc", BLOCK, NEON, (layer == 1 and cCore or cMid):Lerp(cEdge, 1 - mid), nil)
			seg.Size = Vector3.new(w, w * 0.35, (p1 - p0).Magnitude + w)
			seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
			seg.Transparency = 1
			seg.Parent = fp
			task.delay(0.085 * (n - i) / n, function()
				if seg.Parent then
					seg.Transparency = 0.02
					TweenService:Create(seg, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Transparency = 1, Size = seg.Size * Vector3.new(0.3, 0.3, 1),
					}):Play()
				end
			end)
			Debris:AddItem(seg, 0.5)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- 3.16 eyeGlow(char): two green eyes streaking light (mode only). Returns a handle (:Destroy()).
function S.eyeGlow(char)
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return handle(function() end, {})
	end
	local fp = kitFolder()
	local k = head.Size.Y / 1.2
	local eyes, trails = {}, {}
	for i = 1, 2 do
		local e = FX.part("OFAEye", BLOCK, NEON, PAL.Cowl, nil)
		e.Size = Vector3.new(0.26, 0.1, 0.05) * k
		e.CFrame = head.CFrame
		trails[i] = FX.trail(e, cs(PAL.Cowl, PAL.Crimson), 0.12, 0.3, { tail = 0 })
		e.Parent = fp
		eyes[i] = e
	end
	local conn
	local shown = true
	local tiltR, tiltL = CFrame.Angles(0, 0, math.rad(10)), CFrame.Angles(0, 0, -math.rad(10))
	local h = handle(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		for _, e in ipairs(eyes) do
			e:Destroy()
		end
	end, { eyes = eyes })
	conn = RunService.RenderStepped:Connect(function()
		if not head.Parent or not char.Parent or not eyes[1].Parent or not eyes[2].Parent then
			h:Destroy()
			return
		end
		local s = head.Size
		local cf = head.CFrame
		eyes[1].CFrame = cf * CFrame.new(0.2 * s.X, 0.08 * s.Y, -0.5 * s.Z - 0.02) * tiltR
		eyes[2].CFrame = cf * CFrame.new(-0.2 * s.X, 0.08 * s.Y, -0.5 * s.Z - 0.02) * tiltL
		-- hidden in first person (the head is local-transparent), so the eyes never float in front of the lens
		local want = head.LocalTransparencyModifier < 0.5 and head.Transparency < 0.9
		if want ~= shown then
			shown = want
			for i = 1, 2 do
				eyes[i].Transparency = want and 0 or 1
				trails[i].Enabled = want
			end
		end
	end)
	return h
end

return S
