--!nocheck
-- StarterPlayerScripts.SandboxWorld (2026-11-13): the client half of the open test ground's toys.
--   * Beasts (tag Beast): the server moves the body; legs, jaw and tail are animated HERE through the J_<joint> Welds'
--     C0, from the model's Gait (0..1) and Jaw (0/1) attributes. The server never writes those C0s.
--   * FanZone: the wind on YOUR character (the server only owns the dummies and the loose props).
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local A = CFrame.Angles
local beasts = {}
local function scan(model, S)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") and d.Name:sub(1, 2) == "J_" and not S.joints[d.Name] then
			S.joints[d.Name] = { d, d.C0 }
			S.count += 1
		end
	end
end
local function addBeast(model)
	local S = { joints = {}, count = 0, kind = model:GetAttribute("Kind"), phase = math.random() * 6, jaw = 0, gait = 0, nextScan = 0 }
	beasts[model] = S
end
for _, m in ipairs(CollectionService:GetTagged("Beast")) do
	addBeast(m)
end
CollectionService:GetInstanceAddedSignal("Beast"):Connect(addBeast)
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for model, S in pairs(beasts) do
		if not model.Parent then
			beasts[model] = nil
		else
			if S.count < 3 and t > S.nextScan then
				S.nextScan = t + 1
				S.kind = model:GetAttribute("Kind")
				scan(model, S)
			end
			S.gait += ((model:GetAttribute("Gait") or 0) - S.gait) * math.min(1, dt * 6)
			S.jaw += ((model:GetAttribute("Jaw") or 0) - S.jaw) * math.min(1, dt * 14)
			S.phase += dt * (2 + S.gait * 9)
			local J, ph, g, jaw = S.joints, S.phase, S.gait, S.jaw
			local function set(name, rot)
				local j = J[name]
				if j and j[1].Parent then
					j[1].C0 = j[2] * rot
				end
			end
			if S.kind == "rex" then
				local sw = math.sin(ph) * 0.55 * g
				set("J_LegL", A(sw, 0, 0))
				set("J_LegR", A(-sw, 0, 0))
				set("J_Head", A(math.sin(ph * 2) * 0.05 * g + jaw * 0.12, math.sin(t * 0.7) * 0.06, 0))
				set("J_Jaw", A(-jaw * 0.6, 0, 0))
				local tw = math.sin(t * 1.5) * 0.1 + math.sin(ph) * 0.12 * g
				set("J_Tail1", A(0, tw, 0))
				set("J_Tail2", A(0, tw * 1.3, 0))
				set("J_Tail3", A(0, tw * 1.6, 0))
			elseif S.kind == "bear" then
				local sw = math.sin(ph) * 0.6 * g
				set("J_LegFL", A(sw, 0, 0))
				set("J_LegBR", A(sw, 0, 0))
				set("J_LegFR", A(-sw, 0, 0))
				set("J_LegBL", A(-sw, 0, 0))
				set("J_Head", A(math.sin(ph * 2) * 0.06 * g + jaw * 0.2, math.sin(t * 0.9) * 0.1, 0))
				set("J_Jaw", A(-jaw * 0.7, 0, 0))
			else
				set("J_Tail1", A(0, math.sin(t * (3 + g * 7)) * 0.4, 0))
			end
		end
	end
end)
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	for _, Z in ipairs(CollectionService:GetTagged("FanZone")) do
		if Z:GetAttribute("On") then
			local l = Z.CFrame:PointToObjectSpace(hrp.Position)
			local half = Z.Size / 2
			if math.abs(l.X) < half.X and math.abs(l.Y) < half.Y and math.abs(l.Z) < half.Z then
				local fanAt = Z:GetAttribute("FanAt") or half.Z
				local d = fanAt - l.Z
				local s = (d >= 0) and math.clamp(1 - d / (half.Z + fanAt), 0, 1) ^ 0.7 or math.clamp(1 + d / (half.Z - fanAt), 0, 1) * 0.85
				local v = hrp.AssemblyLinearVelocity
				local want = Z.CFrame.LookVector * (Z:GetAttribute("Power") or 140) * 0.75 * s
				hrp.AssemblyLinearVelocity = v:Lerp(Vector3.new(want.X, v.Y + 60 * dt * s, want.Z), math.min(1, dt * 4 * s))
			end
		end
	end
end)

---------------------------------------------------------------------------------------------- SPEECH BUBBLES
-- (2026-11-13) the dummies talk (ServerScriptService.Sandbox.Speech picks who says what and fires Net "say"). The
-- bubble is the one in the owner's reference: a black rounded slab, bold white text, sized in STUDS so it shrinks
-- with distance like theirs did. One bubble per body; a new line replaces the old one.
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = ReplicatedStorage:WaitForChild("Sandbox"):WaitForChild("Net")
local BUBBLE_FONT = Enum.Font.GothamBold
local LINE_H = 1.35 -- studs: the height of a one-line bubble
local holder = Instance.new("Folder")
holder.Name = "SpeechBubbles"
holder.Parent = player:WaitForChild("PlayerGui")
local bubbles = setmetatable({}, { __mode = "k" })
local function showBubble(model, text)
	if typeof(model) ~= "Instance" or type(text) ~= "string" or not model.Parent then
		return
	end
	if Players.LocalPlayer:GetAttribute("Opt_npcChat") == false then -- (2026-11-15) Settings > GENERAL > NPC CHATTER off
		return
	end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso")
	local cam = workspace.CurrentCamera
	if not head or not cam or (head.Position - cam.CFrame.Position).Magnitude > 130 then
		return
	end
	local old = bubbles[model]
	if old then
		old:Destroy()
	end
	-- the slab is as wide as the words need (measured at a 40 px line, then turned into studs)
	local size = TextService:GetTextSize(text, 44, BUBBLE_FONT, Vector2.new(4000, 100))
	local wide = size.X + 64 -- px at a 78 px tall slab: the words plus a margin either end
	local ratio = wide / 78
	local two = ratio > 12.5
	if two then
		ratio = ratio / 1.85 + 0.7
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Speech"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(LINE_H * ratio, LINE_H * (two and 1.8 or 1))
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + 1.25 + (two and 0.55 or 0), 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 130
	gui.DistanceLowerLimit = 9
	gui.ClipsDescendants = false
	local slab = Instance.new("Frame")
	slab.Name = "Slab"
	slab.AnchorPoint = Vector2.new(0.5, 0.5)
	slab.Position = UDim2.fromScale(0.5, 0.5)
	slab.Size = UDim2.fromScale(1, 1)
	slab.BackgroundColor3 = Color3.new(0, 0, 0)
	slab.BackgroundTransparency = 0.06
	slab.BorderSizePixel = 0
	slab.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(two and 0.16 or 0.24, 0)
	corner.Parent = slab
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = two and UDim2.fromScale(0.9, 0.78) or UDim2.fromScale(size.X / wide + 0.02, 0.6)
	label.BackgroundTransparency = 1
	label.Font = BUBBLE_FONT
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	-- ORDER MATTERS (measured): TextWrapped = false set AFTER TextScaled switches TextScaled back off and the line
	-- renders at the default 8 px. The slab is cut to the words, so a one-liner still stays on one line.
	label.TextWrapped = two
	label.TextScaled = true
	label.Parent = slab
	local scale = Instance.new("UIScale")
	scale.Scale = 0.55
	scale.Parent = slab
	gui.Parent = holder
	bubbles[model] = gui
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.3 + #text * 0.055, function()
		if gui.Parent then
			local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(slab, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.wait(0.24)
			gui:Destroy()
		end
		if bubbles[model] == gui then
			bubbles[model] = nil
		end
	end)
end
Net.OnClientEvent:Connect(function(action, a, b)
	if action == "say" then
		showBubble(a, b)
	end
end)
