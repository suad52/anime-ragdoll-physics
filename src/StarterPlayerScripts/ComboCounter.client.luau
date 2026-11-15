--!nocheck
-- ComboCounter (orchestrator 2026-11-07): the hit counter for YOUR combos. Big comic numerals at the right edge, a
-- rank word as the chain grows, and a callout for the finisher (LAUNCHED! / SPIKED! / SMASH!).
-- Counting (2026-11-07, every fighter): a hit is any damage the server's DamageFeed credits to you (u == your
-- UserId) - every kit's M1 (the shared punch, Ichigo's sword, Goku's strikes, Luffy's rubber punches) and every
-- ability alike. One count per feed batch, so one swing through three bodies is one hit; damage over time counts at
-- most ~8 times a second. A chain keeps going as long as the next hit lands within CHAIN seconds. PunchHit (the
-- shared punch / Luffy's M1) now only drives the finisher callout.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local AbilityEvent = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Remotes"):WaitForChild("AbilityEvent")
local DamageFeed = ReplicatedStorage:WaitForChild("DamageFeed", 30)
local Kits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))

local CHAIN = 1.9
local RANKS = { { 3, "NICE" }, { 5, "GREAT!" }, { 8, "BRUTAL!!" }, { 12, "UNSTOPPABLE" }, { 18, "GODLIKE" } }
local CALLOUT = { launch = "LAUNCHED!", slam = "SPIKED!", blast = "SMASH!" }
local INK = Kits.INK

local gui = Instance.new("ScreenGui")
gui.Name = "ComboCounter"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(1, 0.5)
root.Position = UDim2.new(1, -40, 0.52, 0) -- (2026-11-13) below the top-right tiles
root.Size = UDim2.fromOffset(240, 150)
root.BackgroundTransparency = 1
root.Rotation = -6
root.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = root

local function label(props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.FontFace = Kits.FONT_PUNCH
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Right
	for k, v in pairs(props) do
		t[k] = v
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = INK
	s.Parent = t
	t.Parent = root
	return t, s
end
local num, numStroke = label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, -70, 0, 92) })
local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Parent = num
local hits, hitsStroke = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 44), Size = UDim2.fromOffset(66, 40), Text = "HITS" })
local rank, rankStroke = label({ Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 30) })
local call, callStroke = label({ Position = UDim2.fromOffset(0, 122), Size = UDim2.new(1, 0, 0, 26) })

local count, lastHit, shownAlpha = 0, -math.huge, 0
local callToken

local function setAlpha(a)
	for _, pair in ipairs({ { num, numStroke }, { hits, hitsStroke }, { rank, rankStroke } }) do
		pair[1].TextTransparency = 1 - a
		pair[2].Transparency = 1 - a -- the outline fades with the text
	end
end
setAlpha(0)
call.TextTransparency, callStroke.Transparency = 1, 1

local function bump()
	if player:GetAttribute("Opt_combo") == false then
		return -- (2026-11-11) SETTINGS > GENERAL > COMBO COUNTER off
	end
	local t = os.clock()
	if t - lastHit > CHAIN then
		count = 0
	end
	if t - lastHit < 0.05 then
		return -- the same blow reported a frame apart counts once
	end
	count += 1
	lastHit = t
	local kit = Kits.current(player)
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), kit.accent)
	num.Text = tostring(count)
	local r = ""
	for _, pair in ipairs(RANKS) do
		if count >= pair[1] then
			r = pair[2]
		end
	end
	rank.Text = r
	rank.TextColor3 = kit.accent
	setAlpha(1)
	shownAlpha = 1
	scale.Scale = 1.35
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

if DamageFeed then
	DamageFeed.OnClientEvent:Connect(function(list)
		if type(list) ~= "table" then
			return
		end
		for _, h in ipairs(list) do
			if type(h) == "table" and h.u == player.UserId and h.v ~= player.UserId and type(h.d) == "number" and h.d >= 0.5 then
				bump()
				return -- one per batch
			end
		end
	end)
else
	warn("[ComboCounter] DamageFeed missing - the hit counter is off")
end

-- the finisher callout of an M1 string
AbilityEvent.OnClientEvent:Connect(function(kind, data)
	if kind ~= "PunchHit" or type(data) ~= "table" or data.by ~= player.UserId then
		return
	end
	if data.final and data.finisher and player:GetAttribute("Opt_combo") ~= false then
		local tok = {}
		callToken = tok
		call.Text = CALLOUT[data.finisher] or "SMASH!"
		call.TextColor3 = Color3.fromRGB(255, 214, 70)
		call.TextTransparency, callStroke.Transparency = 0, 0
		task.delay(1.1, function()
			if callToken == tok then
				TweenService:Create(call, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				TweenService:Create(callStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	root.Size = UDim2.fromOffset(240, 150)
	if shownAlpha > 0 and os.clock() - lastHit > CHAIN then
		shownAlpha = math.max(0, shownAlpha - dt * 3)
		setAlpha(shownAlpha)
	end
	local s = math.clamp(vp.Y / 900, 0.6, 1.1) * (tonumber(player:GetAttribute("Opt_uiScale")) or 1) -- SETTINGS > CONTROLS > UI SIZE
	if scale.Scale < s * 0.99 or scale.Scale > s * 1.4 then
		scale.Scale = s
	end
end)
