--!nocheck
-- StarterPlayerScripts.GadgetBar (2026-11-09, shop expansion): the GADGET bar - a column of slots on the right edge,
-- one per gadget you hold (HudShared.GadgetCatalog; counts = player attribute Gadgets). Tap a slot or press its key
-- (1-5, not while the emote wheel is open) -> ShopRequest "useGadget"; the server spends one and makes the effect.
-- A slot shows the count and a cooldown sweep (attribute GadgetReady_<id> = server time it is ready again).
-- Also: BOOST PADS (tag GadgetPad) fling THIS player's character when it stands on one (the client owns its physics),
-- and a toast for a Gadget Crate's contents (attribute GadgetCrate).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local G = require(shared:WaitForChild("GadgetCatalog"))
-- (2026-11-14) each slot shows the gadget's drawn icon (HudShared.CardArt) instead of its kanji (kept if there is no art)
local CardArt
pcall(function()
	CardArt = require(shared:WaitForChild("CardArt", 10))
end)
local ShopRequest = shared:WaitForChild("ShopRequest", 30)
local InputMode, Emotes = nil, nil
pcall(function()
	InputMode = require(shared:WaitForChild("InputMode", 10))
end)
-- (2026-11-11, "have the option to have keybinds") the slot keys are the GADGET 1-5 actions (defaults 1-5): presses go
-- through Keybinds.logical and each slot's corner number draws Keybinds.label (redrawn on Keybinds.Changed). With no
-- rebinds both are the plain 1-5, exactly as before.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))
task.spawn(function()
	pcall(function()
		Emotes = require(ReplicatedStorage:WaitForChild("PerkShared", 20):WaitForChild("Emotes", 20))
	end)
end)

local WHITE, INK = Kits.WHITE, Kits.INK
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
local SLOT = 50

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local function corner(p, r)
	return new("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, p)
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, Text = "", FontFace = Kits.FONT_PUNCH }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function ink(t, th)
	new("UIStroke", { Color = INK, Thickness = th or 1.5 }, t)
	return t
end

local gui = new("ScreenGui", { Name = "GadgetBar", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local bar = new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 20), Size = UDim2.fromOffset(SLOT, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, bar)
local barScale = new("UIScale", {}, bar) -- (2026-11-11) SETTINGS > CONTROLS > UI SIZE
local toast = ink(label(gui, { Name = "Toast", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SLOT - 24, 0.5, 20), Size = UDim2.fromOffset(320, 22),
	TextXAlignment = Enum.TextXAlignment.Right, Visible = false }), 2)

local toastToken = 0
local function say(text, color, secs)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.TextColor3 = color or WHITE
	toast.Visible = true
	task.delay(secs or 2, function()
		if my == toastToken then
			toast.Visible = false
		end
	end)
end

local counts = {}
local slots = {}
local busy = false

local function use(id)
	if busy or not ShopRequest then
		return
	end
	if (counts[id] or 0) <= 0 then
		return
	end
	busy = true
	local s = slots[id]
	if s then
		s.scale.Scale = 0.86
		TweenService:Create(s.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	local ok, a, b = pcall(ShopRequest.InvokeServer, ShopRequest, "useGadget", id)
	busy = false
	if not ok then
		say("TRY AGAIN", Color3.fromRGB(255, 120, 120))
	elseif not a then
		say(tostring(b or "NOT NOW"), Color3.fromRGB(255, 200, 90))
	end
end

local function makeSlot(g, key)
	local b = new("TextButton", { Name = g.id, LayoutOrder = g.order, Size = UDim2.fromOffset(SLOT, SLOT), AutoButtonColor = false, Text = "",
		BackgroundColor3 = Color3.fromRGB(18, 18, 28), BackgroundTransparency = 0.15, BorderSizePixel = 0, ClipsDescendants = false, Visible = false }, bar)
	corner(b, 12)
	new("UIStroke", { Color = g.color, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local scale = new("UIScale", {}, b)
	local glyph = ink(label(b, { Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.19, 0.17), Text = g.glyph, TextColor3 = g.color,
		FontFace = Font.fromEnum(Enum.Font.GothamBlack) }), 1.5)
	if CardArt then
		local art = new("Frame", { Name = "Art", Position = UDim2.fromScale(0.12, 0.08), Size = UDim2.fromScale(0.76, 0.76), BackgroundTransparency = 1 }, b)
		local ok, drew = pcall(CardArt.draw, art, g)
		if ok and drew then
			glyph.Visible = false
		else
			art:Destroy()
		end
	end
	local cdFrame = new("Frame", { Name = "Cooldown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0 }, b)
	corner(cdFrame, 12)
	local count = ink(label(b, { Name = "Count", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 4, 1, 4), Size = UDim2.fromOffset(26, 18),
		Text = "0", TextXAlignment = Enum.TextXAlignment.Right }), 2)
	local keyLbl = ink(label(b, { Name = "Key", Position = UDim2.fromOffset(-4, -6), Size = UDim2.fromOffset(16, 16),
		Text = KEYS[key] and Keybinds.label(KEYS[key]) or tostring(key), TextColor3 = Color3.fromRGB(255, 214, 70) }), 2)
	b.Activated:Connect(function()
		use(g.id)
	end)
	slots[g.id] = { button = b, scale = scale, count = count, key = keyLbl, cd = cdFrame, glyph = glyph, g = g, index = key }
end
for i, g in ipairs(G.LIST) do
	makeSlot(g, i)
end
Keybinds.Changed:Connect(function()
	for _, s in pairs(slots) do
		if KEYS[s.index] then
			s.key.Text = Keybinds.label(KEYS[s.index])
		end
	end
end)

local function refresh()
	local ok, t = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Gadgets") or "{}")
	counts = (ok and type(t) == "table") and t or {}
	local touch = InputMode and InputMode.isTouch() or false
	for id, s in pairs(slots) do
		local n = tonumber(counts[id]) or 0
		s.button.Visible = n > 0
		s.count.Text = "x" .. n
		s.key.Visible = not touch
	end
end
player:GetAttributeChangedSignal("Gadgets"):Connect(refresh)
if InputMode and InputMode.changed then
	InputMode.changed(refresh)
end
refresh()

-- cooldown sweeps
RunService.RenderStepped:Connect(function()
	barScale.Scale = tonumber(player:GetAttribute("Opt_uiScale")) or 1
	local now = workspace:GetServerTimeNow()
	for id, s in pairs(slots) do
		if s.button.Visible then
			local readyAt = tonumber(player:GetAttribute("GadgetReady_" .. id)) or 0
			local left = readyAt - now
			s.cd.Size = UDim2.fromScale(1, left > 0 and math.clamp(left / s.g.cooldown, 0, 1) or 0)
		end
	end
end)

UserInputService.InputBegan:Connect(function(io, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end
	-- (2026-11-11) io is passed so a press the wheel took counts even if the wheel's own handler ran first and shut it
	if Emotes and Emotes.isWheelOpen and Emotes.isWheelOpen(io) then
		return
	end
	local key = Keybinds.logical(io.KeyCode)
	for i, k in ipairs(KEYS) do
		if key == k then
			local g = G.LIST[i]
			if g then
				use(g.id)
			end
			return
		end
	end
end)

-- a Gadget Crate opened
local lastCrate = nil
player:GetAttributeChangedSignal("GadgetCrate"):Connect(function()
	local ok, t = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("GadgetCrate") or "")
	if not ok or type(t) ~= "table" or t.n == lastCrate then
		return
	end
	lastCrate = t.n
	local tally, order = {}, {}
	for _, id in ipairs(t.ids or {}) do
		if not tally[id] then
			table.insert(order, id)
		end
		tally[id] = (tally[id] or 0) + 1
	end
	local parts = {}
	for _, id in ipairs(order) do
		local g = G.byId[id]
		table.insert(parts, string.upper(g and g.name or id) .. " x" .. tally[id])
	end
	say("CRATE: " .. table.concat(parts, ", "), Color3.fromRGB(120, 230, 120), 5)
end)

-- BOOST PADS: fling my own character
local lastPad = setmetatable({}, { __mode = "k" })
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	for _, pad in ipairs(CollectionService:GetTagged("GadgetPad")) do
		if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) then
			local d = root.Position - pad.Position
			if Vector3.new(d.X, 0, d.Z).Magnitude < 3.8 and d.Y > -1 and d.Y < 5 and (not lastPad[pad] or now - lastPad[pad] > 0.8) then
				lastPad[pad] = now
				local dir = pad:GetAttribute("Dir")
				dir = typeof(dir) == "Vector3" and dir or Vector3.new(0, 0, -1)
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
				root.AssemblyLinearVelocity = dir * (tonumber(pad:GetAttribute("Push")) or 80) + Vector3.new(0, tonumber(pad:GetAttribute("Lift")) or 35, 0)
			end
		end
	end
end)
