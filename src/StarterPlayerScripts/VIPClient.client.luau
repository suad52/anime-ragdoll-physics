--!nocheck
-- StarterPlayerScripts.VIPClient (2026-11-07, owner: cosmetics) - the VIP perk, drawn by EVERY client for every VIP:
--   * a gold VIP pill over the head (a BillboardGui in PlayerGui adorned to the Head). ShopService's ShopTitle billboard
--     is 220x34 px centred 2.7 studs over the head; the pill shares that anchor and sits in PIXELS just above the title
--     when one is equipped (so the two can never overlap at any distance), or in the title's spot when there is none.
--   * the exclusive gold aura while the player's VIPAura attribute is true: an invisible local core part that follows
--     the HumanoidRootPart every frame and carries flame / spike / spark / glow emitters, a pulsing ground ring,
--     crackling lightning arcs and a light. Any ShopAura (ShopService's Yen aura) on that character is switched off
--     LOCALLY while it shows and switched back on after. Hidden while the character is Morphed (giant forms).
--   * a gold [VIP] chat prefix (TextChatService.OnIncomingMessage).
-- Reads only: Perk_VIP, VIPAura (player attributes written by ShopService) and Morphed (character attribute).
-- Debug: PlayerScripts.VIPClient.Debug (BindableFunction):
--   :Invoke("state") -> { [playerName] = {vip, vipAura, tag, stacked, aura, shopAuraHidden} }
--   :Invoke("prefix", userId) -> the chat prefix that player's messages get (nil = not VIP)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Font.fromEnum(Enum.Font.GothamBold)
pcall(function()
	local Kits = require(ReplicatedStorage:WaitForChild("HudShared", 10):WaitForChild("Kits", 10))
	FONT = Kits.FONT_PUNCH or FONT
end)

local C = Color3.fromRGB
local GOLD_HI = C(255, 248, 205)
local GOLD = C(255, 205, 55)
local GOLD_DEEP = C(215, 130, 15)
local INK = C(12, 10, 20)
local WHITE = Color3.new(1, 1, 1)

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"

local rng = Random.new()
local function ns(points)
	local k = {}
	for i, p in ipairs(points) do
		k[i] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(k)
end
local function cs(points)
	local k = {}
	for i, p in ipairs(points) do
		k[i] = ColorSequenceKeypoint.new(p[1], p[2])
	end
	return ColorSequence.new(k)
end

local fxFolder = Instance.new("Folder")
fxFolder.Name = "VIPFX_Local"
fxFolder.Parent = workspace

local entries = {} -- [Player] = entry
local auras = {} -- [aura] = true (live and fading)

---------------------------------------------------------------------------------------------------
-- the tag
local TITLE_W, TITLE_H, TAG_W, TAG_H, GAP = 220, 34, 108, 28, 4

local function buildTag(head)
	local bb = Instance.new("BillboardGui")
	bb.Name = "VIPTag"
	bb.ResetOnSpawn = false
	bb.LightInfluence = 0
	bb.MaxDistance = 110
	bb.AlwaysOnTop = false
	bb.ClipsDescendants = false
	bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bb.StudsOffset = Vector3.new(0, 2.7, 0)
	bb.Size = UDim2.fromOffset(TITLE_W, TAG_H + 8)
	bb.Adornee = head

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromOffset(TAG_W, TAG_H)
	pill.BackgroundColor3 = WHITE
	pill.BorderSizePixel = 0
	pill.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pill
	local bg = Instance.new("UIGradient")
	bg.Color = cs({ { 0, C(70, 48, 12) }, { 0.55, C(26, 18, 14) }, { 1, INK } })
	bg.Rotation = 90
	bg.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Thickness = 2
	rim.Color = WHITE
	rim.Parent = pill
	local rimGrad = Instance.new("UIGradient")
	rimGrad.Color = cs({ { 0, GOLD_HI }, { 0.25, GOLD }, { 0.5, GOLD_DEEP }, { 0.75, GOLD }, { 1, GOLD_HI } })
	rimGrad.Parent = rim

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.52)
	label.Size = UDim2.new(1, -34, 1, -2)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.Text = "VIP"
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.ZIndex = 2
	label.Parent = pill
	local shine = Instance.new("UIGradient")
	shine.Color = cs({ { 0, GOLD }, { 0.4, GOLD }, { 0.5, WHITE }, { 0.6, GOLD }, { 1, GOLD } })
	shine.Rotation = 20
	shine.Offset = Vector2.new(1.2, 0)
	shine.Parent = label
	local ink = Instance.new("UIStroke")
	ink.Thickness = 1.5
	ink.Color = INK
	ink.Parent = label

	for i, x in ipairs({ 13, TAG_W - 13 }) do
		local gem = Instance.new("Frame")
		gem.Name = i == 1 and "GemL" or "GemR"
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.new(0, x, 0.5, 0)
		gem.Size = UDim2.fromOffset(8, 8)
		gem.Rotation = 45
		gem.BackgroundColor3 = GOLD
		gem.BorderSizePixel = 0
		gem.ZIndex = 2
		gem.Parent = pill
		local gs = Instance.new("UIStroke")
		gs.Thickness = 1
		gs.Color = GOLD_HI
		gs.Parent = gem
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 0.01
	scale.Parent = pill
	bb.Parent = playerGui
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return bb, { pill = pill, rimGrad = rimGrad, shine = shine }
end

local function dropTag(e)
	if e.tag then
		pcall(function()
			e.tag:Destroy()
		end)
	end
	e.tag, e.tagParts, e.stacked = nil, nil, nil
end

-- sit just above ShopService's ShopTitle (same 3D anchor, pixel offset) or in its spot when there is none
local function relayout(e, instant)
	local bb, parts = e.tag, e.tagParts
	if not bb or not parts then
		return
	end
	local title = e.char and e.char:FindFirstChild("ShopTitle", true)
	if title and not (title:IsA("BillboardGui") and title.Enabled) then
		title = nil
	end
	local titleH = title and title.Size.Y.Offset > 0 and title.Size.Y.Offset or TITLE_H
	bb.StudsOffset = title and title.StudsOffset or Vector3.new(0, 2.7, 0)
	local y = title and -(titleH / 2 + GAP + TAG_H / 2) or 0
	bb.Size = UDim2.fromOffset(TITLE_W, 2 * (math.abs(y) + TAG_H / 2) + 8)
	e.stacked = title ~= nil
	local goal = UDim2.new(0.5, 0, 0.5, y)
	if instant then
		parts.pill.Position = goal
	else
		TweenService:Create(parts.pill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal }):Play()
	end
end

local function ensureTag(e, head)
	if e.tag and e.tag.Parent and e.tag.Adornee == head then
		relayout(e)
		return
	end
	dropTag(e)
	e.tag, e.tagParts = buildTag(head)
	relayout(e, true)
end

---------------------------------------------------------------------------------------------------
-- the aura
local function emitter(parent, props)
	local pe = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do
		pe[k] = v
	end
	pe.Parent = parent
	return pe
end

local ARCS, SEGS = 3, 4

local function buildAura(char, hrp)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local feet
	if hum and hum.RigType == Enum.HumanoidRigType.R6 then
		feet = -3
	else
		feet = -((hum and hum.HipHeight or 2) + hrp.Size.Y / 2)
	end
	local top = 2.6
	local height = math.max(top - feet, 3)
	local offset = CFrame.new(0, (top + feet) / 2, 0)

	local core = Instance.new("Part")
	core.Name = "VIPAuraCore"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Massless = true
	core.Transparency = 1
	core.Size = Vector3.new(2.3, height, 1.3)
	core.CFrame = hrp.CFrame * offset

	local box = { Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward, EmissionDirection = Enum.NormalId.Top }
	local function boxed(t)
		for k, v in pairs(box) do
			if t[k] == nil then
				t[k] = v
			end
		end
		return t
	end
	local flame = emitter(core, boxed({
		Name = "Flame", Texture = FIRE, LightEmission = 1, LightInfluence = 0, LockedToPart = true,
		Color = cs({ { 0, GOLD_HI }, { 0.35, GOLD }, { 1, C(255, 120, 10) } }),
		Size = ns({ { 0, 0.9 }, { 0.25, 2.1 }, { 1, 0.3 } }),
		Squash = ns({ { 0, 0.4 }, { 1, 0.9 } }),
		Transparency = ns({ { 0, 1 }, { 0.12, 0.4 }, { 0.7, 0.55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.5, 0.85), Rate = 55, Speed = NumberRange.new(1.5, 3.5),
		Acceleration = Vector3.new(0, 16, 0), SpreadAngle = Vector2.new(10, 10),
		Rotation = NumberRange.new(-15, 15), RotSpeed = NumberRange.new(-40, 40),
	}))
	local spikes = emitter(core, boxed({
		Name = "Spikes", Texture = FIRE, LightEmission = 1, LightInfluence = 0, LockedToPart = true,
		Color = cs({ { 0, WHITE }, { 0.5, GOLD_HI }, { 1, GOLD } }),
		Size = ns({ { 0, 0.6 }, { 0.4, 1.3 }, { 1, 0.2 } }),
		Squash = ns({ { 0, 2 }, { 1, 2.5 } }),
		Transparency = ns({ { 0, 0.25 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.22, 0.38), Rate = 34, Speed = NumberRange.new(7, 12),
		Acceleration = Vector3.new(0, 20, 0), SpreadAngle = Vector2.new(6, 6),
	}))
	local sparks = emitter(core, boxed({
		Name = "Sparks", Texture = SPARK, LightEmission = 1, LightInfluence = 0, LockedToPart = false,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = cs({ { 0, GOLD_HI }, { 1, GOLD } }),
		Size = ns({ { 0, 0.45 }, { 1, 0 } }),
		Lifetime = NumberRange.new(0.6, 1.1), Rate = 16, Speed = NumberRange.new(4, 9),
		Acceleration = Vector3.new(0, 3, 0), Drag = 1.5, SpreadAngle = Vector2.new(55, 55),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
	}))
	local mid = Instance.new("Attachment")
	mid.Name = "Mid"
	mid.Parent = core
	local glow = emitter(mid, {
		Name = "Glow", Texture = GLOW, LightEmission = 1, LightInfluence = 0, LockedToPart = true,
		Color = cs({ { 0, GOLD_HI }, { 1, GOLD } }),
		Size = ns({ { 0, 5.5 }, { 1, 7 } }),
		Transparency = ns({ { 0, 1 }, { 0.3, 0.84 }, { 1, 1 } }),
		Lifetime = NumberRange.new(0.6, 0.8), Rate = 6, Speed = NumberRange.new(0, 0),
	})
	local base = Instance.new("Attachment")
	base.Name = "Base"
	base.Position = Vector3.new(0, -height / 2 + 0.15, 0)
	base.Parent = core
	local ring = emitter(base, {
		Name = "Ring", Texture = RING, LightEmission = 1, LightInfluence = 0, LockedToPart = true,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular, EmissionDirection = Enum.NormalId.Top,
		Color = cs({ { 0, GOLD_HI }, { 1, GOLD } }),
		Size = ns({ { 0, 1.5 }, { 1, 9 } }),
		Transparency = ns({ { 0, 0.25 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.1, 1.1), Rate = 1.4, Speed = NumberRange.new(0.01, 0.01),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(40, 40),
	})
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 13
	light.Brightness = 6
	light.Shadows = false
	light.Parent = core

	-- crackling lightning (super-saiyan style): ARCS jagged arcs of SEGS beams, re-rolled ~14x a second
	local arcs, beams = {}, {}
	for i = 1, ARCS do
		local arc = { atts = {}, beams = {} }
		for j = 1, SEGS + 1 do
			local at = Instance.new("Attachment")
			at.Name = "Arc" .. i .. "_" .. j
			at.Parent = core
			arc.atts[j] = at
		end
		for j = 1, SEGS do
			local b = Instance.new("Beam")
			b.Attachment0, b.Attachment1 = arc.atts[j], arc.atts[j + 1]
			b.Color = cs({ { 0, WHITE }, { 1, GOLD_HI } })
			b.LightEmission = 1
			b.LightInfluence = 0
			b.FaceCamera = true
			b.Segments = 1
			b.Width0, b.Width1 = 0.15, 0.1
			b.Transparency = NumberSequence.new(0.05)
			b.Enabled = false
			b.Parent = core
			arc.beams[j] = b
			beams[#beams + 1] = b
		end
		arcs[i] = arc
	end

	core.Parent = fxFolder
	-- the switch-on burst
	sparks:Emit(30)
	ring:Emit(2)
	flame:Emit(16)
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 2.2 }):Play()

	local a = {
		core = core, hrp = hrp, offset = offset, light = light, arcs = arcs, beams = beams,
		emitters = { flame, spikes, sparks, glow, ring }, seed = rng:NextNumber(0, 100), nextZap = 0,
		lit = os.clock() + 0.5, zapping = false,
		hum = hum, height = height, -- the core is sized to the body it was built on (see hipStale)
	}
	auras[a] = true
	return a
end

local function killAura(a)
	auras[a] = nil
	pcall(function()
		a.core:Destroy()
	end)
end

local function dropAura(e, instant)
	local a = e.aura
	if not a then
		return
	end
	e.aura = nil
	if instant or not a.core.Parent or not a.hrp.Parent then
		killAura(a)
		return
	end
	for _, em in ipairs(a.emitters) do
		em.Enabled = false
	end
	for _, b in ipairs(a.beams) do
		b.Enabled = false
	end
	a.dying = os.clock() + 1.3
	TweenService:Create(a.light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
end

local function zap(a)
	for _, arc in ipairs(a.arcs) do
		if rng:NextNumber() < 0.5 then
			local half = a.core.Size * 0.5
			local p = Vector3.new(rng:NextNumber(-half.X, half.X), rng:NextNumber(-half.Y * 0.8, half.Y * 0.8), rng:NextNumber(-half.Z, half.Z))
			local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1.2), rng:NextNumber(-1, 1)).Unit
			arc.atts[1].Position = p
			for j = 2, #arc.atts do
				p = p + dir * 0.7 + Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(-0.3, 0.45), rng:NextNumber(-0.45, 0.45))
				arc.atts[j].Position = p
			end
			for _, b in ipairs(arc.beams) do
				b.Enabled = true
			end
		else
			for _, b in ipairs(arc.beams) do
				b.Enabled = false
			end
		end
	end
end

-- Yen auras from ShopService are switched off (locally) while the VIP aura shows, and only the ones this script
-- switched off are switched back on
local function setShopHidden(char, hidden)
	if not char then
		return
	end
	for _, root in ipairs(char:GetDescendants()) do
		if root.Name == "ShopAura" then
			local list = root:GetDescendants()
			table.insert(list, root)
			for _, x in ipairs(list) do
				if x:IsA("ParticleEmitter") or x:IsA("Light") or x:IsA("Beam") or x:IsA("Trail") then
					if hidden then
						if x.Enabled then
							x.Enabled = false
							x:SetAttribute("VIPHid", true)
							if x:IsA("ParticleEmitter") then
								x:Clear()
							end
						end
					elseif x:GetAttribute("VIPHid") then
						x:SetAttribute("VIPHid", nil)
						x.Enabled = true
					end
				end
			end
		end
	end
end

-- (2026-11-07 integration) the core box is sized from HipHeight when the aura is built, and a giant form restores its
-- HipHeight AFTER Morphed flips back, so an aura re-shown on leaving a form was built 15 studs tall (a flame pillar to
-- the ceiling) until the next respawn (the root part's size lags too). A body whose size moved since the build
-- (the same feet / height maths as buildAura) rebuilds it.
local function hipStale(a)
	local hum, hrp = a.hum, a.hrp
	if not (hum and hum.Parent and hrp and hrp.Parent) then
		return false
	end
	local feet = hum.RigType == Enum.HumanoidRigType.R6 and -3 or -(hum.HipHeight + hrp.Size.Y / 2)
	return math.abs(math.max(2.6 - feet, 3) - a.height) > 0.3
end

local function ensureAura(e, char, hrp)
	if e.aura and e.aura.hrp == hrp and e.aura.core.Parent and not hipStale(e.aura) then
		return
	end
	dropAura(e, true)
	e.aura = buildAura(char, hrp)
end

---------------------------------------------------------------------------------------------------
-- per player
local function refresh(e)
	if e.dead then
		return
	end
	local p, char = e.player, e.char
	if char and not char.Parent then
		char = nil
	end
	local head = char and char:FindFirstChild("Head")
	if p:GetAttribute("Perk_VIP") == true and head and head:IsA("BasePart") then
		ensureTag(e, head)
	else
		dropTag(e)
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local want = p:GetAttribute("VIPAura") == true and hrp ~= nil and hrp:IsA("BasePart") and char:GetAttribute("Morphed") ~= true
	if want then
		ensureAura(e, char, hrp)
	else
		dropAura(e)
	end
	setShopHidden(char, want)
end

local function setChar(e, char)
	for _, c in ipairs(e.charConns) do
		c:Disconnect()
	end
	table.clear(e.charConns)
	if e.char and e.char ~= char then
		setShopHidden(e.char, false)
	end
	dropTag(e)
	dropAura(e, true)
	e.char = char
	if char then
		table.insert(e.charConns, char.DescendantAdded:Connect(function(d)
			local n = d.Name
			if n == "ShopAura" then
				task.defer(function()
					if e.char == char and e.aura and not e.aura.dying then
						setShopHidden(char, true)
					end
				end)
			elseif n == "ShopTitle" or n == "Head" or n == "HumanoidRootPart" then
				task.defer(refresh, e)
			end
		end))
		table.insert(e.charConns, char.DescendantRemoving:Connect(function(d)
			local n = d.Name
			if n == "ShopTitle" or n == "Head" or n == "HumanoidRootPart" then
				task.defer(refresh, e)
			end
		end))
		table.insert(e.charConns, char:GetAttributeChangedSignal("Morphed"):Connect(function()
			refresh(e)
		end))
	end
	refresh(e)
end

local function track(p)
	if entries[p] then
		return
	end
	local e = { player = p, conns = {}, charConns = {}, seed = rng:NextNumber(0, 3) }
	entries[p] = e
	table.insert(e.conns, p.CharacterAdded:Connect(function(char)
		setChar(e, char)
	end))
	table.insert(e.conns, p.CharacterRemoving:Connect(function(char)
		if e.char == char then
			setChar(e, nil)
		end
	end))
	for _, name in ipairs({ "Perk_VIP", "VIPAura" }) do
		table.insert(e.conns, p:GetAttributeChangedSignal(name):Connect(function()
			refresh(e)
		end))
	end
	setChar(e, p.Character)
end

local function untrack(p)
	local e = entries[p]
	if not e then
		return
	end
	entries[p] = nil
	for _, c in ipairs(e.conns) do
		c:Disconnect()
	end
	setChar(e, nil)
	e.dead = true
end

Players.PlayerAdded:Connect(track)
Players.PlayerRemoving:Connect(untrack)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(track, p)
end

---------------------------------------------------------------------------------------------------
-- every frame: the tag shimmer, the aura following its body, the lightning and the light flicker
local ZAP_RANGE = 170
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, e in pairs(entries) do
		local ea = e.aura
		if ea and not ea.dying and t >= (ea.hipCheck or 0) then
			ea.hipCheck = t + 0.4
			if hipStale(ea) then
				task.defer(refresh, e)
			end
		end
		local parts = e.tagParts
		if parts then
			local ph = (t + e.seed) % 2.8
			parts.shine.Offset = Vector2.new(ph < 1 and (ph * 2.4 - 1.2) or 1.2, 0)
			parts.rimGrad.Rotation = (t * 140 + e.seed * 60) % 360
		end
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local moved, cframes = {}, {}
	for a in pairs(auras) do
		if not a.core.Parent or (a.dying and t > a.dying) then
			killAura(a)
		elseif not a.hrp.Parent then
			killAura(a)
		else
			local cf = a.hrp.CFrame * a.offset
			moved[#moved + 1] = a.core
			cframes[#cframes + 1] = cf
			if not a.dying then
				if t > a.lit then
					a.light.Brightness = 2.2 * (0.85 + 0.5 * math.noise(t * 9, a.seed))
				end
				if (cf.Position - camPos).Magnitude < ZAP_RANGE then
					if t >= a.nextZap then
						zap(a)
						a.zapping = true
						a.nextZap = t + 0.05 + rng:NextNumber() * 0.06
					end
				elseif a.zapping then
					a.zapping = false
					for _, b in ipairs(a.beams) do
						b.Enabled = false
					end
				end
			end
		end
	end
	if #moved > 0 then
		workspace:BulkMoveTo(moved, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

---------------------------------------------------------------------------------------------------
-- chat: a gold [VIP] in front of every VIP's name
local PREFIX = '<font color="#FFD23C"><b>[VIP]</b></font> '
local function prefixFor(userId, base)
	local p = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if p and p:GetAttribute("Perk_VIP") == true then
		base = base or ""
		if string.find(base, "[VIP]", 1, true) then
			return nil
		end
		return PREFIX .. base
	end
	return nil
end
pcall(function()
	TextChatService.OnIncomingMessage = function(message)
		local ok, props = pcall(function()
			local src = message.TextSource
			local text = src and prefixFor(src.UserId, message.PrefixText)
			if text then
				local pr = Instance.new("TextChatMessageProperties")
				pr.PrefixText = text
				return pr
			end
			return nil
		end)
		return ok and props or nil
	end
end)

---------------------------------------------------------------------------------------------------
-- debug hook for headless tests
local dbg = Instance.new("BindableFunction")
dbg.Name = "Debug"
dbg.OnInvoke = function(cmd, arg)
	if cmd == "state" then
		local out = {}
		for p, e in pairs(entries) do
			local hidden = 0
			if e.char then
				for _, d in ipairs(e.char:GetDescendants()) do
					if d:GetAttribute("VIPHid") then
						hidden += 1
					end
				end
			end
			out[p.Name] = {
				vip = p:GetAttribute("Perk_VIP") == true,
				vipAura = p:GetAttribute("VIPAura") == true,
				tag = e.tag ~= nil and e.tag.Parent ~= nil,
				stacked = e.stacked == true,
				aura = e.aura ~= nil and e.aura.core.Parent ~= nil,
				shopAuraHidden = hidden,
			}
		end
		return out
	elseif cmd == "prefix" then
		return prefixFor(tonumber(arg) or player.UserId, "Name: ")
	end
	return nil
end
dbg.Parent = script
