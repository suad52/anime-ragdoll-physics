--!nocheck
-- StarterPlayerScripts.DuelMenu (2026-11-11, "wiki extras"): DUELS on the client (ServerScriptService.DuelService).
--   * a crossed-swords pill in the top strip -> a panel listing everyone in the server with a CHALLENGE button
--   * an incoming challenge: a card at the top with ACCEPT / DECLINE and a shrinking timer
--   * in a duel: a banner (YOU vs THEM + the clock), the 3-2-1-FIGHT countdown and a GIVE UP button
--   * at the end: the winner's VICTORY FLASH (HudShared.VictoryFlash) for both fighters, then a result line
-- Studio: script.Control:Invoke("open") / ("close") / ("challenge", userId) / ("respond", userId, accept) / ("state").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("HudShared")
local Kits = require(shared:WaitForChild("Kits"))
local V = require(shared:WaitForChild("VictoryCatalog"))
local VictoryFlash = require(shared:WaitForChild("VictoryFlash"))
local remote = shared:WaitForChild("Duel", 30)

local WHITE, INK = Kits.WHITE, Kits.INK
local GOLD = Color3.fromRGB(255, 214, 70)
local RED = Color3.fromRGB(255, 70, 100)
local GREEN = Color3.fromRGB(90, 230, 140)
local DIM = Color3.fromRGB(170, 170, 195)
local OFFC = Color3.fromRGB(62, 62, 82)
local C0, C1 = Color3.fromRGB(255, 90, 120), Color3.fromRGB(120, 80, 255)
local PILL_BG = Color3.fromRGB(18, 18, 28)
local PILL_H = 40

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
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function button(parent, text, color, props)
	local b = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do
		b[k] = v
	end
	corner(b, 8)
	stroke(b, INK, 1.5)
	local t = label(b, { Name = "Label", Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), Text = text, TextColor3 = INK })
	return b, t
end

local gui = new("ScreenGui", { Name = "DuelMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

-- toast line (top middle)
local toast = inkText(label(gui, { Name = "Toast", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(520, 24),
	Visible = false }), 2)
local toastToken = 0
local function say(text, color, secs)
	toastToken += 1
	local my = toastToken
	toast.Text, toast.TextColor3, toast.Visible = text, color or WHITE, true
	task.delay(secs or 3, function()
		if my == toastToken then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- THE PANEL: everyone in the server
local root = new("Frame", { Name = "DuelRoot", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
local shade = new("TextButton", { Name = "DuelShade", AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5 }, root)
local W, H = 520, 440
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
inkText(label(hd, { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(200, 38), Text = "DUELS", TextXAlignment = Enum.TextXAlignment.Left }), 2.5)
local closeBtn = new("TextButton", { Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(36, 36),
	AutoButtonColor = false, Text = "", BackgroundColor3 = WHITE, BorderSizePixel = 0 }, hd)
corner(closeBtn)
stroke(closeBtn, INK, 2)
label(closeBtn, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.fromOffset(7, 7), Text = "X", TextColor3 = INK })
local info = label(panel, { Position = UDim2.fromOffset(18, 66), Size = UDim2.new(1, -36, 0, 30), TextWrapped = true, FontFace = Kits.FONT_LABEL, TextColor3 = DIM,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
new("UITextSizeConstraint", { MaxTextSize = 14 }, info)
local list = new("ScrollingFrame", { Name = "Players", Position = UDim2.fromOffset(14, 102), Size = UDim2.new(1, -20, 1, -114), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = WHITE, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
new("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)
local empty = label(panel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.new(1, -60, 0, 40), TextWrapped = true,
	FontFace = Kits.FONT_LABEL, TextColor3 = DIM, Text = "NOBODY ELSE IS IN THIS SERVER YET - DUELS NEED ANOTHER PLAYER" })

local function challenge(uid)
	if remote then
		remote:FireServer("challenge", uid)
	end
end

local function rebuild()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local f = V.byId[player:GetAttribute("VictoryFlash") or ""] or V.byId[V.DEFAULT]
	info.Text = "WIN A 1V1 IN A PRIVATE ARENA (3 MIN). YOUR VICTORY FLASH: " .. string.upper(f.name) .. " - MORE IN SHOP > VICTORY"
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			n += 1
			local r = new("Frame", { Name = "P_" .. p.UserId, LayoutOrder = n, Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = WHITE, BackgroundTransparency = 0.94,
				BorderSizePixel = 0 }, list)
			corner(r, 10)
			local pic = new("ImageLabel", { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = OFFC, BorderSizePixel = 0,
				Image = "rbxthumb://type=AvatarHeadShot&id=" .. p.UserId .. "&w=150&h=150" }, r)
			corner(pic)
			inkText(label(r, { Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -220, 0, 22), Text = string.upper(p.DisplayName), TextXAlignment = Enum.TextXAlignment.Left }))
			label(r, { Position = UDim2.fromOffset(62, 32), Size = UDim2.new(1, -220, 0, 14), Text = "@" .. p.Name, FontFace = Kits.FONT_LABEL, TextColor3 = DIM,
				TextXAlignment = Enum.TextXAlignment.Left })
			local busy = p:GetAttribute("InDuel") ~= nil
			local b = button(r, busy and "IN A DUEL" or "CHALLENGE", busy and OFFC or GOLD, { Name = "Challenge", AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 34) })
			b.Activated:Connect(function()
				if p:GetAttribute("InDuel") == nil then
					challenge(p.UserId)
				end
			end)
		end
	end
	empty.Visible = n == 0
end

local function open()
	fit()
	rebuild()
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
Players.PlayerAdded:Connect(function()
	if root.Visible then
		rebuild()
	end
end)
Players.PlayerRemoving:Connect(function()
	task.defer(function()
		if root.Visible then
			rebuild()
		end
	end)
end)

---------------------------------------------------------------------------------------------------------------------
-- AN INCOMING CHALLENGE
local card = new("Frame", { Name = "Invite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.fromOffset(440, 104),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false }, gui)
corner(card, 14)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(44, 30, 64), Color3.fromRGB(16, 12, 26)) }, card)
stroke(card, C0, 2.5)
local cardText = inkText(label(card, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 26), Text = "" }), 1.5)
local accept = button(card, "ACCEPT", GREEN, { Name = "Accept", Position = UDim2.new(0, 16, 0, 46), Size = UDim2.new(0.5, -22, 0, 38) })
local decline = button(card, "DECLINE", OFFC, { Name = "Decline", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 46), Size = UDim2.new(0.5, -22, 0, 38) })
decline.Label.TextColor3 = WHITE
local timerBar = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -6), Size = UDim2.new(1, -28, 0, 4), BackgroundColor3 = C0,
	BorderSizePixel = 0 }, card)
corner(timerBar)
local inviteFrom, inviteUntil = nil, 0
local function respond(yes)
	if inviteFrom and remote then
		remote:FireServer("respond", inviteFrom.UserId, yes == true)
	end
	inviteFrom = nil
	card.Visible = false
end
accept.Activated:Connect(function()
	respond(true)
end)
decline.Activated:Connect(function()
	respond(false)
end)

---------------------------------------------------------------------------------------------------------------------
-- IN A DUEL
local banner = new("Frame", { Name = "DuelBanner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(420, 52),
	BackgroundColor3 = WHITE, BorderSizePixel = 0, Visible = false }, gui)
corner(banner, 12)
new("UIGradient", { Color = ColorSequence.new(C0, C1) }, banner)
stroke(banner, INK, 2.5)
local vsText = inkText(label(banner, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -130, 0, 24), Text = "", TextXAlignment = Enum.TextXAlignment.Left }), 2)
local clock = inkText(label(banner, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -130, 0, 16), Text = "", FontFace = Kits.FONT_LABEL,
	TextXAlignment = Enum.TextXAlignment.Left }), 1)
local giveUp = button(banner, "GIVE UP", WHITE, { Name = "GiveUp", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 32) })
giveUp.Activated:Connect(function()
	if remote then
		remote:FireServer("forfeit")
	end
end)
local big = inkText(label(gui, { Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(400, 140),
	Text = "", Visible = false }), 5)
local bigScale = new("UIScale", {}, big)

local duel = nil -- { opponent, fightAt, endsAt }
local lastBig = nil
RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow()
	if inviteFrom then
		local left = inviteUntil - t
		timerBar.Size = UDim2.new(math.clamp(left / 20, 0, 1), -28, 0, 4)
		if left <= 0 then
			inviteFrom = nil
			card.Visible = false
		end
	end
	if duel then
		local toFight = duel.fightAt - t
		local txt
		if toFight > 0 then
			txt = tostring(math.ceil(toFight))
		elseif toFight > -0.8 then
			txt = "FIGHT!"
		end
		big.Visible = txt ~= nil
		if txt and txt ~= lastBig then
			lastBig = txt
			big.Text = txt
			big.TextColor3 = txt == "FIGHT!" and GOLD or WHITE
			bigScale.Scale = 1.6
			tween(bigScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		local left = math.max(0, math.floor(duel.endsAt - t))
		clock.Text = toFight > 0 and "GET READY" or string.format("TIME %d:%02d", math.floor(left / 60), left % 60)
	end
end)

local function reasonText(r, won)
	if r == "left" then
		return won and "THEY LEFT THE GAME" or ""
	elseif r == "forfeit" then
		return won and "THEY GAVE UP" or "YOU GAVE UP"
	elseif r == "time" then
		return "TIME! MORE HEALTH WINS"
	end
	return ""
end

if remote then
	remote.OnClientEvent:Connect(function(kind, a, b)
		if kind == "incoming" and typeof(a) == "Instance" then
			inviteFrom, inviteUntil = a, tonumber(b) or (workspace:GetServerTimeNow() + 20)
			cardText.Text = string.upper(a.DisplayName) .. " CHALLENGES YOU TO A DUEL!"
			card.Visible = true
		elseif kind == "status" then
			say(tostring(a), GOLD)
		elseif kind == "declined" and typeof(a) == "Instance" then
			say(string.upper(a.DisplayName) .. " DECLINED", DIM)
		elseif kind == "start" and type(a) == "table" then
			close()
			card.Visible = false
			inviteFrom = nil
			duel = { opponent = a.opponent, fightAt = a.fightAt, endsAt = a.endsAt }
			lastBig = nil
			vsText.Text = "YOU  VS  " .. string.upper(a.opponent and a.opponent.DisplayName or "?")
			banner.Visible = true
		elseif kind == "end" and type(a) == "table" then
			duel = nil
			banner.Visible = false
			big.Visible = false
			local won = a.winner == player
			local sub
			if a.winner then
				sub = won and "YOU WIN" or "YOU LOST"
				VictoryFlash.play(a.winner, a.flash, { sub = sub })
			end
			task.delay(V.DURATION, function()
				if a.reason == "draw" then
					say("DRAW! NOBODY WINS", WHITE, 4)
				elseif won then
					local yen = player:GetAttribute("DuelReward")
					say("YOU WON THE DUEL!" .. (yen and ("  +¥ " .. yen) or "") .. "  " .. reasonText(a.reason, true), GREEN, 4)
				else
					say("YOU LOST THE DUEL  " .. reasonText(a.reason, false), RED, 4)
				end
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- THE PILL: two crossed swords
task.spawn(function()
	local cs = playerGui:WaitForChild("CharacterSelect", 20)
	local strip = cs and cs:WaitForChild("TopStrip", 10)
	local b
	if strip then
		b = new("TextButton", { Name = "DuelPill", LayoutOrder = 6, AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(PILL_H, PILL_H),
			BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, strip)
	else
		b = new("TextButton", { Name = "DuelPill", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -158, 0, 8), AutoButtonColor = false, Text = "",
			Size = UDim2.fromOffset(PILL_H, PILL_H), BackgroundColor3 = PILL_BG, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, gui)
	end
	-- (2026-11-14, ragdoll sandbox) owner: "remove the starter the duels and the taunt buttons we dont need those". The
	-- button is still built (nothing else has to change) but never shown: the rail and the phone's top strip both skip
	-- a hidden button. Duels are off in this game anyway (DuelService is disabled).
	b.Visible = false
	corner(b)
	local st = stroke(b, WHITE, 1.5, 0.55)
	local icon = new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1 }, b)
	for _, rot in ipairs({ 45, -45 }) do
		local blade = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 26), Rotation = rot,
			BackgroundColor3 = WHITE, BorderSizePixel = 0 }, icon)
		corner(blade, 2)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.78), Size = UDim2.fromOffset(12, 3), BackgroundColor3 = C0,
			BorderSizePixel = 0 }, blade)
	end
	b.MouseEnter:Connect(function()
		tween(st, 0.12, { Transparency = 0 })
		tween(icon, 0.15, { Rotation = 12 })
	end)
	b.MouseLeave:Connect(function()
		tween(st, 0.12, { Transparency = 0.55 })
		tween(icon, 0.15, { Rotation = 0 })
	end)
	b.Activated:Connect(function()
		if root.Visible then
			close()
		else
			open()
		end
	end)
end)

if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a, b)
		if cmd == "open" then
			open()
		elseif cmd == "close" then
			close()
		elseif cmd == "challenge" then
			challenge(a)
		elseif cmd == "respond" then
			respond(b)
		elseif cmd == "flash" then
			VictoryFlash.play(player, a, { sub = "PREVIEW" })
		elseif cmd == "state" then
			return { open = root.Visible, invite = inviteFrom and inviteFrom.Name, duel = duel ~= nil, banner = banner.Visible, toast = toast.Visible and toast.Text or "" }
		end
		return true
	end
	ctl.Parent = script
end
