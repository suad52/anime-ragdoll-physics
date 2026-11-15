--!nocheck
-- StarterPlayerScripts.QuestMenu (2026-11-11, "wiki extras"): the QUESTS panel - 3 daily + 3 weekly quests that pay
-- Yen (HudShared.QuestCatalog; progress and claims are server-side in ShopService.Ext.Quests, published as the player
-- attribute Quests). A scroll pill in the top strip opens it and shows a red dot while a reward is waiting.
-- Studio: script.Control:Invoke("open") / ("close") / ("claim", "daily" | "weekly", n) / ("state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local Q = require(shared:WaitForChild("QuestCatalog"))
local ShopRequest = shared:WaitForChild("ShopRequest", 30)

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local RED = Color3.fromRGB(255, 70, 100)
local GREEN = Color3.fromRGB(90, 230, 140)
local DIM = Color3.fromRGB(170, 170, 195)
local OFFC = Color3.fromRGB(62, 62, 82)
local C0, C1 = Color3.fromRGB(90, 230, 160), Color3.fromRGB(60, 150, 255)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local PILL_H = 40
local CUR = "¥"
pcall(function()
	CUR = require(shared:WaitForChild("ShopCatalog")).CURRENCY or CUR
end)

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
local function stroke(p, color, th, tr)
	return new("UIStroke", { Color = color or INK, Thickness = th or 1.5, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function label(parent, props)
	local t = new("TextLabel", { BackgroundTransparency = 1, TextColor3 = WHITE, TextScaled = true, Text = "", FontFace = Kits.FONT_PUNCH }, parent)
	for k, v in pairs(props) do
		t[k] = v
	end
	return t
end
local function inkText(t, th)
	new("UIStroke", { Color = INK, Thickness = th or 1.5 }, t)
	return t
end
local function tween(o, t, props)
	local tw = TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function data()
	local ok, t = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Quests") or "")
	return (ok and type(t) == "table") and t or nil
end
local function claimable(t)
	t = t or data()
	if not t then
		return false
	end
	for _, pair in ipairs({ { t.daily, Q.DAILY }, { t.weekly, Q.WEEKLY } }) do
		for _, q in ipairs(pair[1] or {}) do
			local def = pair[2][q.i]
			if def and not q.c and q.n >= def.target then
				return true
			end
		end
	end
	return false
end
local function left(t)
	local s = math.max(0, math.floor(t - workspace:GetServerTimeNow()))
	local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
	if d > 0 then
		return d .. "D " .. h .. "H"
	end
	return h .. "H " .. m .. "M"
end

---------------------------------------------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "QuestMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
local root = new("Frame", { Name = "QuestRoot", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local shade = new("TextButton", { Name = "QuestShade", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5 }, root)
local W, H = 560, 512
local panel = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Active = true }, root)
corner(panel, 16)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(24, 20, 40), Color3.fromRGB(10, 9, 18)) }, panel)
stroke(panel, INK, 3)
local pscale = new("UIScale", {}, panel)
local function fit()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	pscale.Scale = math.clamp(math.min((vp.X - 20) / W, (vp.Y - 20) / H), 0.4, 1) * (tonumber(player:GetAttribute("Opt_menuScale")) or 1)
end
player:GetAttributeChangedSignal("Opt_menuScale"):Connect(fit)

local hd = new("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, panel)
corner(hd, 16)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hd)
local hsq = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = WHITE,
	BorderSizePixel = 0 }, hd)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, hsq)
inkText(label(hd, { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(200, 38), Text = "QUESTS", TextXAlignment = Enum.TextXAlignment.Left }), 2.5)
local status = inkText(label(hd, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.fromOffset(240, 18), Text = "",
	TextXAlignment = Enum.TextXAlignment.Right }), 1.5)
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(36, 36),
	AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
corner(closeBtn)
stroke(closeBtn, INK, 2)
label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", TextColor3 = INK })

local statusToken = 0
local function say(text, color)
	statusToken += 1
	local my = statusToken
	status.Text, status.TextColor3 = text, color or WHITE
	task.delay(2.5, function()
		if my == statusToken then
			status.Text = ""
		end
	end)
end

-- two sections, 3 rows each
local rows = { daily = {}, weekly = {} }
local heads = {}
local y = 70
local busy = false
local claim -- forward
for _, list in ipairs({ "daily", "weekly" }) do
	local head = inkText(label(panel, { Name = "Head_" .. list, Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 20), Text = "",
		TextColor3 = GOLD, FontFace = Kits.FONT_LABEL, TextXAlignment = Enum.TextXAlignment.Left }), 1)
	heads[list] = head
	y += 26
	for n = 1, 3 do
		local r = new("Frame", { Name = list .. "_" .. n, Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 56), BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.94, BorderSizePixel = 0 }, panel)
		corner(r, 10)
		local name = inkText(label(r, { Name = "Name", Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -200, 0, 20), Text = "",
			TextXAlignment = Enum.TextXAlignment.Left }))
		local track = new("Frame", { Name = "Track", Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -200, 0, 10), BackgroundColor3 = OFFC,
			BorderSizePixel = 0 }, r)
		corner(track)
		local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C0, BorderSizePixel = 0 }, track)
		corner(fill)
		local prog = label(r, { Name = "Progress", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -182, 0, 8), Size = UDim2.fromOffset(90, 18),
			Text = "", TextColor3 = DIM, FontFace = Kits.FONT_LABEL, TextXAlignment = Enum.TextXAlignment.Right })
		local btn = new("TextButton", { Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(150, 34),
			AutoButtonColor = false, Text = "", BackgroundColor3 = OFFC, BorderSizePixel = 0 }, r)
		corner(btn, 8)
		stroke(btn, INK, 1.5)
		local bt = label(btn, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), Text = "" })
		btn.Activated:Connect(function()
			claim(list, n)
		end)
		rows[list][n] = { frame = r, name = name, fill = fill, prog = prog, btn = btn, bt = bt }
		y += 60
	end
	y += 8
end

local function refresh()
	local t = data()
	for _, list in ipairs({ "daily", "weekly" }) do
		local pool = list == "daily" and Q.DAILY or Q.WEEKLY
		local ends = t and (list == "daily" and t.dayEnds or t.weekEnds)
		heads[list].Text = (list == "daily" and "DAILY" or "WEEKLY") .. (ends and ("  -  NEW QUESTS IN " .. left(ends)) or "")
		for n = 1, 3 do
			local row = rows[list][n]
			local q = t and t[list] and t[list][n]
			local def = q and pool[q.i]
			row.frame.Visible = def ~= nil
			if def then
				local done = q.n >= def.target
				row.name.Text = Q.label(def)
				row.prog.Text = Q.comma(math.min(q.n, def.target)) .. " / " .. Q.comma(def.target)
				row.fill.Size = UDim2.fromScale(math.clamp(q.n / def.target, 0, 1), 1)
				row.fill.BackgroundColor3 = done and GREEN or C0
				if q.c then
					row.btn.BackgroundColor3, row.bt.Text, row.bt.TextColor3 = OFFC, "CLAIMED", DIM
				elseif done then
					row.btn.BackgroundColor3, row.bt.Text, row.bt.TextColor3 = GREEN, "CLAIM " .. CUR .. " " .. def.reward, INK
				else
					row.btn.BackgroundColor3, row.bt.Text, row.bt.TextColor3 = OFFC, CUR .. " " .. def.reward, WHITE
				end
			end
		end
	end
end

claim = function(list, n)
	if busy or not ShopRequest then
		return
	end
	busy = true
	local ok, a, b = pcall(ShopRequest.InvokeServer, ShopRequest, "questClaim", { list = list, n = n })
	busy = false
	if ok and a then
		say(tostring(b or "CLAIMED"), GREEN)
	else
		say(ok and tostring(b or "NOT YET") or "TRY AGAIN", ok and GOLD or RED)
	end
	refresh()
	return ok and a, b
end

local function open()
	fit()
	refresh()
	root.Visible = true
	panel.Position = UDim2.fromScale(0.5, 0.56)
	tween(panel, 0.18, { Position = UDim2.fromScale(0.5, 0.52) })
end
local function close()
	root.Visible = false
end
closeBtn.Activated:Connect(close)
shade.Activated:Connect(function(io)
	if io and io.Position then
		local a, s = panel.AbsolutePosition, panel.AbsoluteSize
		if io.Position.X >= a.X and io.Position.X <= a.X + s.X and io.Position.Y >= a.Y and io.Position.Y <= a.Y + s.Y then
			return
		end
	end
	close()
end)

-- the pill: a scroll with two lines of text and a red dot while a reward waits
local dot
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b
	if strip then
		b = new("TextButton", { Name = "QuestPill", LayoutOrder = 7, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(PILL_H, PILL_H),
			BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, strip)
	else
		b = new("TextButton", { Name = "QuestPill", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -110, 0, 8), AutoButtonColor = false, Text = "",
			Size = UDim2.fromOffset(PILL_H, PILL_H), BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, gui)
	end
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	local scroll = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 22),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, b)
	corner(scroll, 3)
	for i, w in ipairs({ 10, 12, 8 }) do
		new("Frame", { Position = UDim2.fromOffset(4, 4 + (i - 1) * 5), Size = UDim2.fromOffset(w, 2), BackgroundColor3 = PILL_BG, BorderSizePixel = 0 }, scroll)
	end
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(22, 4), BackgroundColor3 = C0,
		BorderSizePixel = 0 }, scroll)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(22, 4), BackgroundColor3 = C0,
		BorderSizePixel = 0 }, scroll)
	dot = new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 1, 0, -1), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = RED,
		BorderSizePixel = 0, Visible = claimable() }, b)
	corner(dot)
	stroke(dot, WHITE, 1.5)
	b.MouseEnter:Connect(function()
		tween(st, 0.12, { Transparency = 0 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.12, { Transparency = 0.55 })
	end)
	b.Activated:Connect(function()
		if root.Visible then
			close()
		else
			open()
		end
	end)
end)

player:GetAttributeChangedSignal("Quests"):Connect(function()
	if dot then
		dot.Visible = claimable()
	end
	if root.Visible then
		refresh()
	end
end)
task.spawn(function()
	while true do
		task.wait(1)
		if root.Visible then
			refresh() -- the countdowns
		end
	end
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			open()
		elseif cmd == "close" then
			close()
		elseif cmd == "claim" then
			return claim(a, b)
		elseif cmd == "state" then
			return { open = root.Visible, dot = dot and dot.Visible, quests = player:GetAttribute("Quests") }
		end
		return true
	end
	ctl.Parent = script
end
