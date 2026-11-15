--!nocheck
-- ShopService.Ext.Gadgets (2026-11-09, shop expansion): one-use GADGETS (HudShared.GadgetCatalog).
--   data { counts = { [id] = n } }  -> player attribute Gadgets (JSON)
--   request "buyGadget" id  - one for its Yen price
--   request "useGadget" id  - spends one and makes the effect (per-gadget cooldown + G.GLOBAL_CD; the attribute
--                             GadgetReady_<id> = server time it is usable again, for the bar's cooldown)
--   receipt kind "gadgetCrate" - item.count random gadgets (attribute GadgetCrate = JSON {ids, n} for the reveal)
-- Effects live here (server): SMOKE a cloud (tag GadgetSmoke + Radius / Until attributes: PlayerMarkers hides
-- anyone inside), DECOY an anchored, untagged copy of the body, PAD a pad part (tag GadgetPad; every client flings its
-- OWN character when it stands on it, since the client owns its physics), BUBBLE a hidden ForceField (PvP.hittable
-- skips bodies with one) + a bubble, SNACK heals over a few seconds. Everything goes in workspace.GadgetFX.
-- Studio: ShopService.GadgetTest:Invoke(player, "give", id, n) / (player, "use", id).
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local G = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("GadgetCatalog"))

local M = { name = "Gadgets", request = {}, grant = {} }
local api
local cd = setmetatable({}, { __mode = "k" }) -- [player] = { any = t, [id] = t }

function M.load(raw)
	local counts = {}
	if type(raw) == "table" and type(raw.counts) == "table" then
		for id, n in pairs(raw.counts) do
			n = tonumber(n)
			if G.byId[id] and n and n >= 1 then
				counts[id] = math.clamp(math.floor(n), 0, G.MAX)
			end
		end
	end
	return { counts = counts }
end

function M.publish(p, d, dat)
	p:SetAttribute("Gadgets", api.HttpService:JSONEncode(dat.counts))
end

---------------------------------------------------------------------------------------------------------------------
-- effects
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local WHOOSH = "rbxassetid://9120972444" -- the game's own whoosh (Pro Sound Effects)

local function fxFolder()
	local f = workspace:FindFirstChild("GadgetFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GadgetFX"
		f.Parent = workspace
	end
	return f
end

local function ground(pos, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, fxFolder() }
	params.IgnoreWater = true
	local r = workspace:Raycast(pos, Vector3.new(0, -14, 0), params)
	return r and r.Position or (pos - Vector3.new(0, 3, 0))
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function sound(parent, id, vol)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.RollOffMaxDistance = 160
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

local function puff(pos, color, n)
	local a = part({ Name = "Puff", Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE_TEX
	e.Color = ColorSequence.new(color or Color3.fromRGB(220, 220, 235))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	a.Parent = fxFolder()
	e:Emit(n or 20)
	Debris:AddItem(a, 2)
end

local EFFECT = {}

EFFECT.Smoke = function(p, char, hum, root, g)
	local at = ground(root.Position, char)
	local cloud = part({ Name = "SmokeBomb", Transparency = 1, Size = Vector3.new(g.radius * 1.5, 4, g.radius * 1.5),
		CFrame = CFrame.new(at + Vector3.new(0, 2, 0)) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE_TEX
	e.Color = ColorSequence.new(Color3.fromRGB(150, 150, 165), Color3.fromRGB(205, 205, 215))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 7), NumberSequenceKeypoint.new(1, 13) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.15, 0.08),
		NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(3, 4.5)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rotation = NumberRange.new(0, 360)
	e.Acceleration = Vector3.new(0, 0.8, 0)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.LightInfluence = 0.8
	e.Rate = 55
	e.Parent = cloud
	cloud:SetAttribute("Radius", g.radius)
	cloud:SetAttribute("Until", workspace:GetServerTimeNow() + g.secs + 1.5)
	CollectionService:AddTag(cloud, "GadgetSmoke")
	cloud.Parent = fxFolder()
	e:Emit(45)
	sound(cloud, WHOOSH, 1.2)
	task.delay(g.secs, function()
		e.Enabled = false
	end)
	Debris:AddItem(cloud, g.secs + 5)
end

EFFECT.Decoy = function(p, char, hum, root, g)
	local was = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(char.Clone, char)
	char.Archivable = was
	if not ok or not copy then
		error("couldn't copy the body")
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("ForceField")
			or d:IsA("BodyMover") or d:IsA("Constraint") and not d:IsA("BallSocketConstraint") then
			d:Destroy()
		end
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d.Parent then
			for _, t in ipairs(CollectionService:GetTags(d)) do
				CollectionService:RemoveTag(d, t)
			end
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
	end
	for _, t in ipairs(CollectionService:GetTags(copy)) do
		CollectionService:RemoveTag(copy, t)
	end
	for k in pairs(copy:GetAttributes()) do
		copy:SetAttribute(k, nil)
	end
	local h = copy:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		h.BreakJointsOnDeath = false
		h.EvaluateStateMachine = false
	end
	copy.Name = "Decoy"
	copy:SetAttribute("GadgetDecoy", p.UserId)
	copy.Parent = fxFolder()
	puff(root.Position, Color3.fromRGB(190, 170, 255), 18)
	sound(root, WHOOSH, 0.8)
	task.delay(g.secs, function()
		if copy.Parent then
			puff(copy:GetPivot().Position, Color3.fromRGB(190, 170, 255), 24)
			copy:Destroy()
		end
	end)
end

EFFECT.Pad = function(p, char, hum, root, g)
	local at = ground(root.Position, char)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local pad = part({ Name = "BoostPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7, 7), Material = Enum.Material.Neon, Color = g.color,
		Transparency = 0.15, CFrame = CFrame.new(at + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	local arrow = part({ Name = "Arrow", Size = Vector3.new(1.2, 0.2, 3.4), Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1),
		CFrame = CFrame.lookAt(at + Vector3.new(0, 0.55, 0), at + Vector3.new(0, 0.55, 0) + look) })
	arrow.Parent = pad
	for _, side in ipairs({ -1, 1 }) do -- the arrow head: two bars angled back from the tip
		local tipAt = at + Vector3.new(0, 0.55, 0) + look * 1.7
		local back = (CFrame.lookAt(tipAt, tipAt + look) * CFrame.Angles(0, math.rad(side * 140), 0)).LookVector
		local bar = part({ Name = "Head", Size = Vector3.new(0.5, 0.2, 1.8), Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1),
			CFrame = CFrame.lookAt(tipAt + back * 0.9, tipAt + back * 1.8) })
		bar.Parent = pad
	end
	pad:SetAttribute("Dir", look)
	pad:SetAttribute("Push", g.push)
	pad:SetAttribute("Lift", g.lift)
	pad:SetAttribute("Owner", p.UserId)
	CollectionService:AddTag(pad, "GadgetPad")
	pad.Parent = fxFolder()
	sound(pad, WHOOSH, 0.7)
	task.delay(g.secs, function()
		if pad.Parent then
			puff(pad.Position, g.color, 12)
			pad:Destroy()
		end
	end)
end

EFFECT.Bubble = function(p, char, hum, root, g)
	local ff = Instance.new("ForceField")
	ff.Name = "GadgetBubble"
	ff.Visible = false
	ff.Parent = char
	local ball = part({ Name = "BubbleShield", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Material = Enum.Material.ForceField,
		Color = g.color, Anchored = false, Massless = true, CFrame = root.CFrame })
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = ball, root
	w.Parent = ball
	ball.Parent = fxFolder()
	sound(root, WHOOSH, 0.9)
	Debris:AddItem(ff, g.secs)
	Debris:AddItem(ball, g.secs)
end

EFFECT.Snack = function(p, char, hum, root, g)
	local steps = 6
	local per = g.heal / steps
	task.spawn(function()
		for _ = 1, steps do
			task.wait(g.secs / steps)
			if hum.Parent and hum.Health > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + per)
			end
		end
	end)
	local a = Instance.new("Attachment")
	a.Name = "SnackFX"
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEX
	e.Color = ColorSequence.new(Color3.fromRGB(120, 255, 150))
	e.LightEmission = 1
	e.Size = NumberSequence.new(0.5, 0)
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(60, 60)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 25
	e.Parent = a
	a.Parent = root
	Debris:AddItem(a, g.secs)
end

---------------------------------------------------------------------------------------------------------------------
-- requests / receipts
M.request.buyGadget = function(p, d, id)
	local g = type(id) == "string" and G.byId[id]
	if not g then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	if (dat.counts[id] or 0) >= G.MAX then
		return false, "YOU CAN'T CARRY MORE"
	end
	if (d.yen or 0) < g.yen then
		return false, "NOT ENOUGH " .. api.Catalog.CURRENCY
	end
	d.yen -= g.yen
	dat.counts[id] = (dat.counts[id] or 0) + 1
	d.dirty = true
	api.publish(p)
	task.spawn(api.save, p)
	return true, string.upper(g.name) .. " +1"
end

local function use(p, d, id)
	local g = type(id) == "string" and G.byId[id]
	if not g then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	if (dat.counts[id] or 0) <= 0 then
		return false, "NONE LEFT - GET MORE IN THE SHOP"
	end
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then
		return false, "NOT NOW"
	end
	local now = os.clock()
	local c = cd[p] or {}
	cd[p] = c
	if (c.any or 0) > now then
		return false, "WAIT"
	end
	if (c[id] or 0) > now then
		return false, string.format("WAIT %ds", math.ceil(c[id] - now))
	end
	local ok, err = pcall(EFFECT[id], p, char, hum, root, g)
	if not ok then
		warn("[Gadgets] " .. id .. ": " .. tostring(err))
		return false, "TRY AGAIN"
	end
	c.any, c[id] = now + G.GLOBAL_CD, now + g.cooldown
	dat.counts[id] -= 1
	if dat.counts[id] <= 0 then
		dat.counts[id] = nil
	end
	d.dirty = true
	api.publish(p)
	p:SetAttribute("GadgetReady_" .. id, workspace:GetServerTimeNow() + g.cooldown)
	local qe = script.Parent.Parent:FindFirstChild("QuestEvent") -- (2026-11-11) quests
	if qe then
		qe:Fire(p, "gadgets", 1)
	end
	return true, string.upper(g.name) .. "!"
end
M.request.useGadget = use

M.grant.gadgetCrate = function(p, d, item)
	local dat = api.ext(d, M.name)
	local got = {}
	for _ = 1, tonumber(item.count) or 6 do
		local g = G.LIST[math.random(#G.LIST)]
		if (dat.counts[g.id] or 0) < G.MAX then
			dat.counts[g.id] = (dat.counts[g.id] or 0) + 1
			table.insert(got, g.id)
		end
	end
	d.dirty = true
	api.publish(p)
	p:SetAttribute("GadgetCrate", api.HttpService:JSONEncode({ ids = got, n = os.clock() }))
	return function()
		for _, id in ipairs(got) do
			dat.counts[id] = math.max(0, (dat.counts[id] or 0) - 1)
			if dat.counts[id] == 0 then
				dat.counts[id] = nil
			end
		end
		d.dirty = true
	end
end

function M.init(a)
	api = a
	if api.isStudio then
		local f = Instance.new("BindableFunction")
		f.Name = "GadgetTest"
		f.OnInvoke = function(p, cmd, id, n)
			local d = api.data[p]
			if not d then
				return false, "no data"
			end
			if cmd == "give" then
				local dat = api.ext(d, M.name)
				dat.counts[id] = math.clamp((dat.counts[id] or 0) + (n or 1), 0, G.MAX)
				api.publish(p)
				return true, dat.counts[id]
			elseif cmd == "use" then
				cd[p] = nil
				return use(p, d, id)
			end
			return false, "?"
		end
		f.Parent = script.Parent.Parent
	end
end

return M
