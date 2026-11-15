--!nocheck
-- StarterPlayerScripts.Onboarding (2026-11-14, owner: "add this small onboarding thing at the beginning where when users
-- spawn in, the screen is dimmed and its pointed towards first the normal button where u can switch characters ...
-- somewhere else on the screen it should say click to continue ... then second it should point to the map switching
-- part ... click to start and then they start"). Two steps over a dimmed screen with a lit hole round the tile:
--   1. the FIGHTER tile (CharacterSelect's FighterPill - "Normal" until they pick one)  -> "Click to continue"
--   2. the MAPS tile (MapMenu's MapsPill)                                               -> "Click to start"
-- A click anywhere moves on (the clicks never reach the game while it shows). Shown once per account: the server sets
-- player attribute OnboardSeen and saves it when ReplicatedStorage.OnboardingDone fires (ServerScriptService.Onboarding).
-- Studio: script.Control:Invoke("show") runs it again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("OnboardingDone", 30)
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local CLICK = TOUCH and "Tap" or "Click"

local FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local FONT_BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 214, 70)
local TILE = Color3.fromRGB(22, 23, 28)

local STEPS = {
	-- (2026-11-15, owner: "in the first step ... also show all the characters that u can choose from like the dropdown")
	{ target = "FighterPill", list = "Characters", title = "CHOOSE YOUR FIGHTER", body = CLICK .. " the gold-ringed button to open this list, then pick whatever character you want.",
		prompt = CLICK .. " to continue" },
	{ target = "MapsPill", title = "SWITCH MAPS", body = "This is how you switch maps.", prompt = CLICK .. " to start" },
}

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
local function tween(o, t, props, style)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function findTile(name)
	local cs = playerGui:FindFirstChild("CharacterSelect")
	local b = cs and cs:FindFirstChild(name, true)
	if b and b:IsA("GuiObject") and b.Visible and b.AbsoluteSize.X > 8 then
		return b
	end
	local mm = playerGui:FindFirstChild("MapMenu") -- (with no top strip MapMenu keeps its own pill)
	b = mm and mm:FindFirstChild(name, true)
	if b and b:IsA("GuiObject") and b.Visible and b.AbsoluteSize.X > 8 then
		return b
	end
	return nil
end

local OpenPanel = ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("OpenPanel", 10)
local function fighterList(on)
	if OpenPanel then
		OpenPanel:Fire(on and "fighters" or "fightersClose")
	end
end
local function listFrame(name)
	local cs = playerGui:FindFirstChild("CharacterSelect")
	local f = cs and cs:FindFirstChild(name)
	return (f and f:IsA("GuiObject") and f.Visible and f.AbsoluteSize.X > 8) and f or nil
end

local running = false
local function run()
	if running then
		return
	end
	running = true
	-- wait for the game to be on screen: a character, the first-join fighter pick done, both tiles laid out
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	local t0 = os.clock()
	while os.clock() - t0 < 30 do
		local picking = player:GetAttribute("StarterPicked") == false
		local ss = playerGui:FindFirstChild("StarterSelect")
		if ss and ss:IsA("ScreenGui") and ss.Enabled and #ss:GetChildren() > 0 then
			local anyVisible = false
			for _, c in ipairs(ss:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible then
					anyVisible = true
				end
			end
			picking = picking or anyVisible
		end
		if not picking and findTile("FighterPill") and findTile("MapsPill") then
			break
		end
		task.wait(0.25)
	end
	task.wait(1.2) -- the rails re-centre as the last tiles arrive

	local gui = new("ScreenGui", { Name = "Onboarding", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	local shades = {}
	for i = 1, 4 do
		shades[i] = new("Frame", { Name = "Dim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, gui)
	end
	local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, ZIndex = 3 }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, ring)
	local ringStroke = new("UIStroke", { Color = GOLD, Thickness = 3, Transparency = 1 }, ring)
	for i = 5, 6 do
		shades[i] = new("Frame", { Name = "Dim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Size = UDim2.new() }, gui)
	end
	local listRing = new("Frame", { Name = "ListRing", BackgroundTransparency = 1, ZIndex = 3, Visible = false }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, listRing)
	local listStroke = new("UIStroke", { Color = WHITE, Thickness = 2, Transparency = 0.35 }, listRing)
	-- the arrow, drawn pointing LEFT; its CanvasGroup turns it to point up when the tile is along the top
	local arrow = new("CanvasGroup", { Name = "Arrow", Size = UDim2.fromOffset(64, 44), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, GroupTransparency = 1, ZIndex = 4 }, gui)
	local function bar(x, y, w, h, rot)
		local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 5 }, arrow)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, f)
		new("UIStroke", { Color = Color3.fromRGB(16, 16, 22), Thickness = 2 }, f)
		return f
	end
	bar(38, 22, 40, 10)
	bar(17, 14, 24, 10, -42)
	bar(17, 30, 24, 10, 42)
	-- the card
	-- (2026-11-15) the card grows with its text (the body wraps to two or three lines)
	local card = new("Frame", { Name = "Card", Size = UDim2.fromOffset(330, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = TILE, BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 4 }, gui)
	new("UIPadding", { PaddingBottom = UDim.new(0, 14) }, card)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	local cardStroke = new("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 1 }, card)
	local stepLbl = new("TextLabel", { Position = UDim2.new(1, -66, 0, 12), Size = UDim2.fromOffset(52, 16), BackgroundTransparency = 1, FontFace = FONT_BODY, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true, TextTransparency = 1, Text = "", ZIndex = 5 }, card)
	local title = new("TextLabel", { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -90, 0, 26), BackgroundTransparency = 1, FontFace = FONT, TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left, TextScaled = true, TextTransparency = 1, Text = "", ZIndex = 5 }, card)
	local body = new("TextLabel", { Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, FontFace = FONT_BODY, TextColor3 = Color3.fromRGB(220, 222, 232),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextSize = 20, TextTransparency = 1, Text = "", ZIndex = 5 }, card)
	-- "Click to continue", somewhere else: low in the middle of the screen
	local prompt = new("TextLabel", { Name = "Prompt", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(420, 40), BackgroundTransparency = 1,
		FontFace = FONT, TextColor3 = WHITE, TextScaled = true, TextTransparency = 1, Text = "", ZIndex = 4 }, gui)
	local promptStroke = new("UIStroke", { Color = Color3.fromRGB(16, 16, 22), Thickness = 2.5, Transparency = 1 }, prompt)
	-- every click lands here while it shows, so nothing else in the game takes it
	local catcher = new("TextButton", { Name = "Catcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Modal = true, ZIndex = 10 }, gui)

	local step, target, readyAt = 0, nil, 0
	local function show(i)
		step = i
		local S = STEPS[i]
		target = findTile(S.target)
		readyAt = os.clock() + 0.6 -- a click already on its way does not skip the step
		stepLbl.Text = i .. " / " .. #STEPS
		title.Text = S.title
		body.Text = S.body
		prompt.Text = S.prompt
		fighterList(S.list ~= nil)

		for _, l in ipairs({ stepLbl, title, body }) do
			l.TextTransparency = 1
			tween(l, 0.35, { TextTransparency = 0 })
		end
	end
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		fighterList(false)
		listRing.Visible = false
		for _, f in ipairs(shades) do
			tween(f, 0.3, { BackgroundTransparency = 1 })
		end
		tween(ringStroke, 0.3, { Transparency = 1 })
		tween(arrow, 0.3, { GroupTransparency = 1 })
		tween(card, 0.3, { BackgroundTransparency = 1 })
		tween(cardStroke, 0.3, { Transparency = 1 })
		for _, l in ipairs({ stepLbl, title, body, prompt }) do
			tween(l, 0.3, { TextTransparency = 1 })
		end
		tween(promptStroke, 0.3, { Transparency = 1 })
		catcher:Destroy()
		if remote then
			remote:FireServer()
		end
		task.delay(0.35, function()
			gui:Destroy()
			running = false
		end)
	end
	catcher.Activated:Connect(function()
		if os.clock() < readyAt then
			return
		end
		if step < #STEPS then
			show(step + 1)
		else
			finish()
		end
	end)

	-- fade in
	for _, f in ipairs(shades) do
		tween(f, 0.35, { BackgroundTransparency = 0.38 })
	end
	tween(ringStroke, 0.35, { Transparency = 0 })
	tween(arrow, 0.35, { GroupTransparency = 0 })
	tween(card, 0.35, { BackgroundTransparency = 0.04 })
	tween(cardStroke, 0.35, { Transparency = 0.7 })
	tween(promptStroke, 0.35, { Transparency = 0 })
	show(1)

	-- follow the tile every frame (the rails move as the window changes size)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if finished or not gui.Parent then
			conn:Disconnect()
			return
		end
		if not (target and target.Parent and target.Visible) then
			target = findTile(STEPS[step].target)
			if not target then
				return
			end
		end
		local vp = gui.AbsoluteSize
		local pad = 7
		-- AbsolutePosition is measured from a point 58 px above the top of an IgnoreGuiInset gui (its own
		-- AbsolutePosition reads 0, -58): take the tile's position relative to THIS gui before using it as an offset
		local p, s = target.AbsolutePosition - gui.AbsolutePosition, target.AbsoluteSize
		local x0, y0, x1, y1 = p.X - pad, p.Y - pad, p.X + s.X + pad, p.Y + s.Y + pad
		ring.Position, ring.Size = UDim2.fromOffset(x0, y0), UDim2.fromOffset(x1 - x0, y1 - y0)
		-- the hole: the tile, or the tile AND its open fighter list (the list opens beside a rail tile, under a pill)
		local hx0, hy0, hx1, hy1 = x0, y0, x1, y1
		local lst = STEPS[step].list and listFrame(STEPS[step].list)
		local lx0, ly0, lx1, ly1
		local beside, under = false, false
		if lst then
			local lp, ls = lst.AbsolutePosition - gui.AbsolutePosition, lst.AbsoluteSize
			beside = lp.X >= p.X + s.X - 1 -- (raw edges: the two padded rings overlap by a few px)
			under = not beside and lp.Y >= p.Y + s.Y - 1
			lx0, ly0, lx1, ly1 = lp.X - pad, lp.Y - pad, lp.X + ls.X + pad, lp.Y + ls.Y + pad
			hx0, hy0, hx1, hy1 = math.min(x0, lx0), math.min(y0, ly0), math.max(x1, lx1), math.max(y1, ly1)
			listRing.Visible = true
			listRing.Position, listRing.Size = UDim2.fromOffset(lx0, ly0), UDim2.fromOffset(lx1 - lx0, ly1 - ly0)
		else
			listRing.Visible = false
		end
		shades[1].Position, shades[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(vp.X, math.max(0, hy0))
		shades[2].Position, shades[2].Size = UDim2.fromOffset(0, hy1), UDim2.fromOffset(vp.X, math.max(0, vp.Y - hy1))
		shades[3].Position, shades[3].Size = UDim2.fromOffset(0, hy0), UDim2.fromOffset(math.max(0, hx0), hy1 - hy0)
		shades[4].Position, shades[4].Size = UDim2.fromOffset(hx1, hy0), UDim2.fromOffset(math.max(0, vp.X - hx1), hy1 - hy0)
		-- inside that box, dim what is neither the tile nor the list: the strip the tile stands in, above and below it
		if lst and beside then
			shades[5].Position, shades[5].Size = UDim2.fromOffset(hx0, hy0), UDim2.fromOffset(math.max(0, lx0 - hx0), math.max(0, y0 - hy0))
			shades[6].Position, shades[6].Size = UDim2.fromOffset(hx0, y1), UDim2.fromOffset(math.max(0, lx0 - hx0), math.max(0, hy1 - y1))
		elseif lst and under then -- the list hangs under a pill: dim beside the pill, above the list
			shades[5].Position, shades[5].Size = UDim2.fromOffset(hx0, hy0), UDim2.fromOffset(math.max(0, x0 - hx0), math.max(0, ly0 - hy0))
			shades[6].Position, shades[6].Size = UDim2.fromOffset(x1, hy0), UDim2.fromOffset(math.max(0, hx1 - x1), math.max(0, ly0 - hy0))
		else
			shades[5].Size, shades[6].Size = UDim2.new(), UDim2.new()
		end
		ringStroke.Transparency = finished and 1 or (0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 4)))
		local bob = 7 * math.sin(os.clock() * 5)
		local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
		local cw, ch = card.AbsoluteSize.X, card.AbsoluteSize.Y
		if lst and beside then -- the list beside the tile: the card goes beyond the list, the arrow points back at it
			local ay = math.clamp(cy, ly0 + 40, ly1 - 40)
			arrow.Rotation = 0
			arrow.Position = UDim2.fromOffset(lx1 + 44 + bob, ay)
			card.Position = UDim2.fromOffset(math.min(lx1 + 84, vp.X - cw - 8), math.clamp(ay - ch / 2, 8, vp.Y - ch - 8))
		elseif lst then -- the list under a pill: the card beside the list
			arrow.Rotation = 0
			arrow.Position = UDim2.fromOffset(lx1 + 44 + bob, (ly0 + ly1) / 2)
			card.Position = UDim2.fromOffset(math.min(lx1 + 84, vp.X - cw - 8), math.clamp((ly0 + ly1) / 2 - ch / 2, 8, vp.Y - ch - 8))
		elseif cx < vp.X * 0.35 then -- a tile on the left rail: the arrow to its right points left, the card beyond it
			arrow.Rotation = 0
			arrow.Position = UDim2.fromOffset(x1 + 44 + bob, cy)
			card.Position = UDim2.fromOffset(x1 + 84, math.clamp(cy - ch / 2, 8, vp.Y - ch - 8))
		else -- a pill in the top strip (phones): the arrow under it points up, the card under that
			arrow.Rotation = 90
			arrow.Position = UDim2.fromOffset(cx, y1 + 40 + bob)
			card.Position = UDim2.fromOffset(math.clamp(cx - cw / 2, 8, vp.X - cw - 8), y1 + 72)
		end
		-- the prompt sits low in the middle of the screen, or high when the card is down there (the MAPS tile is low)
		local cp = card.AbsolutePosition - gui.AbsolutePosition
		local py = vp.Y * 0.6 -- (clear of a fighter's move bar, which sits higher than the weapons hotbar)
		local pw, ph = prompt.AbsoluteSize.X, prompt.AbsoluteSize.Y
		local overlapX = cp.X < vp.X / 2 + pw / 2 + 12 and cp.X + cw > vp.X / 2 - pw / 2 - 12
		local overlapY = py + ph / 2 + 12 > cp.Y and py - ph / 2 - 12 < cp.Y + ch
		if overlapX and overlapY then
			py = vp.Y * 0.3
		end
		prompt.Position = UDim2.fromOffset(vp.X / 2, py)
		prompt.TextTransparency = 0.05 + 0.45 * (0.5 + 0.5 * math.sin(os.clock() * 3))
	end)
end

task.spawn(function()
	local t0 = os.clock()
	while player:GetAttribute("OnboardSeen") == nil and os.clock() - t0 < 20 do
		task.wait(0.2)
	end
	if player:GetAttribute("OnboardSeen") ~= true then
		run()
	end
end)

-- (2026-11-15) Settings > GENERAL > REPLAY INTRO sets OnboardReplay (the settings panel closes itself on the same signal)
player:GetAttributeChangedSignal("OnboardReplay"):Connect(function()
	task.wait(0.15)
	task.spawn(run)
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd)
		if cmd == "show" then
			task.spawn(run)
			return true
		elseif cmd == "state" then
			local g = playerGui:FindFirstChild("Onboarding")
			return { running = running, shown = g ~= nil, seen = player:GetAttribute("OnboardSeen") }
		end
	end
	ctl.Parent = script
end
