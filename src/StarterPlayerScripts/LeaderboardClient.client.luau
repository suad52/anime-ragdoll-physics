-- StarterPlayer.StarterPlayerScripts.LeaderboardClient (2026-11-08) - draws the Crossing leaderboards on the CityScreen
-- faces whose Playlist is "board_kills" (SKYCAST) or "board_streak" (HIKARI VISION); CityAmbientClient leaves those
-- screens alone. Both count PLAYER kills only (2026-11-08). Data: ServerScriptService.LeaderboardService publishes ReplicatedStorage.Leaderboards (JSON attributes
-- Kills / Streak = [{u = userId, d = display name, n = username, v = value}], Scope = "global" | "server").
-- The local player's row is outlined in the board's colour and the footer shows their own numbers (player attributes
-- LBKills / LBBest / KillStreak). Sizes are worked out from each screen's CanvasSize: anything wider than 1.2 : 1 shows
-- two columns of five (rows stay tall enough to read from the street), a narrow screen one column of ten.
-- (2026-11-14, owner: "remove the kanji") the boards' Japanese subtitle lines go (HudShared.Theme.strip)
local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Theme"))
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local data = ReplicatedStorage:WaitForChild("Leaderboards")

local TOP = 10
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(6, 8, 16)
local DIM = Color3.fromRGB(150, 160, 186)
local MEDAL = { Color3.fromRGB(255, 206, 64), Color3.fromRGB(206, 218, 236), Color3.fromRGB(232, 140, 72) }
local FONT_TITLE, FONT_BOLD, FONT_TECH, FONT_CODE = Enum.Font.GothamBlack, Enum.Font.GothamBold, Enum.Font.Michroma, Enum.Font.Code

local BOARDS = {
	board_kills = { key = "Kills", title = "MOST KILLS", jp = "PVP  対人撃破ランキング", unit = "KILLS", empty = "NO PVP KILLS YET",
		accent = Color3.fromRGB(0, 230, 255), accent2 = Color3.fromRGB(255, 40, 170) },
	board_streak = { key = "Streak", title = "BEST KILLSTREAK", jp = "PVP  最高連続撃破", unit = "STREAK", empty = "NO STREAKS YET",
		accent = Color3.fromRGB(255, 40, 170), accent2 = Color3.fromRGB(255, 168, 28) },
}

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function text(parent, name, pos, size, font, color, props)
	local t = new("TextLabel", { Name = name, Position = pos, Size = size, BackgroundTransparency = 1, Font = font, TextColor3 = color,
		TextScaled = true, Text = "", ZIndex = 3 }, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

local function comma(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

local function decode(raw)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	return (ok and type(t) == "table") and t or {}
end

---------------------------------------------------------------------------------------------------------------------
-- BUILD
---------------------------------------------------------------------------------------------------------------------
local function build(face, cfg, content, canvas)
	local old = content:FindFirstChild("Leaderboard")
	if old then
		old:Destroy()
	end
	local fb = content:FindFirstChild("Fallback")
	if fb then
		fb.Visible = false
	end
	local W, H = canvas.X, canvas.Y
	local wide = W / H >= 1.6
	local cols = (W / H >= 1.2) and 2 or 1
	local perCol = math.ceil(TOP / cols)
	local u = H / 100 -- 1% of the screen height, in pixels

	local root = new("Frame", { Name = "Leaderboard", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BorderSizePixel = 0,
		ClipsDescendants = true, ZIndex = 2 }, content)
	new("UIGradient", { Rotation = 28, Color = ColorSequence.new(cfg.accent:Lerp(INK, 0.8), INK) }, root)
	-- faint scanlines
	for i = 1, 33 do
		new("Frame", { Name = "Scan", Size = UDim2.new(1, 0, 0, math.max(1, math.floor(u * 0.18))), Position = UDim2.fromScale(0, i / 34),
			BackgroundColor3 = cfg.accent, BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = 2 }, root)
	end

	-- header: title + Japanese subtitle on the left, the scope chip on the right
	local HEAD = wide and 0.2 or 0.165
	local head = new("Frame", { Name = "Head", Size = UDim2.fromScale(1, HEAD), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		BorderSizePixel = 0, ZIndex = 3 }, root)
	local rule = new("Frame", { Name = "Rule", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, math.max(2, math.floor(u * 0.6))), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, head)
	new("UIGradient", { Color = ColorSequence.new(cfg.accent, cfg.accent2) }, rule)
	local title = text(head, "Title", UDim2.fromScale(0.03, 0.12), UDim2.fromScale(0.64, 0.52), FONT_TITLE, Color3.fromRGB(236, 242, 255),
		{ Text = cfg.title, TextXAlignment = Enum.TextXAlignment.Left })
	-- a thin neon edge only: the screen's Brightness already blooms white text, a thick stroke turns it into a blob
	local glow = new("UIStroke", { Color = cfg.accent, Thickness = math.max(1, u * 0.15), Transparency = 0.6 }, title)
	text(head, "Jp", UDim2.fromScale(0.03, 0.64), UDim2.fromScale(0.64, 0.26), FONT_TECH, cfg.accent,
		{ Text = Theme.strip(cfg.jp or ""), TextXAlignment = Enum.TextXAlignment.Left })
	local chip = new("Frame", { Name = "Scope", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.97, 0.46),
		Size = UDim2.fromScale(wide and 0.22 or 0.28, 0.42), BackgroundColor3 = cfg.accent2, BackgroundTransparency = 0.8, BorderSizePixel = 0,
		ZIndex = 3 }, head)
	new("UIStroke", { Color = cfg.accent2, Thickness = math.max(1, u * 0.3), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, chip)
	local scope = text(chip, "Label", UDim2.fromScale(0.06, 0.16), UDim2.fromScale(0.88, 0.68), FONT_TECH, WHITE)

	-- rows
	local FOOT = wide and 0.1 or 0.075
	local y0 = HEAD + 0.03
	local area = 1 - y0 - FOOT - 0.02
	local pitch = area / perCol
	local colW = (0.94 - (cols - 1) * 0.025) / cols
	local rowPx = pitch * 0.86 * H
	local rowW = colW * W
	local side = math.floor(rowPx * 0.8)
	local avX = math.floor(rowW * ((cols == 2) and 0.12 or 0.08))
	local nameX = avX + side + math.floor(rowPx * 0.28)
	local rows = {}
	for i = 1, TOP do
		local c = math.floor((i - 1) / perCol)
		local r = (i - 1) % perCol
		local medal = MEDAL[i]
		local base = medal and 0.84 or ((r % 2 == 0) and 0.93 or 0.96)
		local row = new("Frame", { Name = "Row" .. i, Position = UDim2.fromScale(0.03 + c * (colW + 0.025), y0 + r * pitch),
			Size = UDim2.fromScale(colW, pitch * 0.86), BackgroundColor3 = medal or WHITE, BackgroundTransparency = base, BorderSizePixel = 0,
			ClipsDescendants = true, Visible = false, ZIndex = 3 }, root)
		new("Frame", { Name = "Bar", Size = UDim2.new(0, math.max(3, math.floor(u * 0.7)), 1, 0), BackgroundColor3 = medal or cfg.accent,
			BackgroundTransparency = medal and 0 or 0.45, BorderSizePixel = 0, ZIndex = 4 }, row)
		text(row, "Rank", UDim2.new(0, math.floor(rowW * 0.015), 0.12, 0), UDim2.new(0, avX - math.floor(rowW * 0.02), 0.76, 0), FONT_TITLE,
			medal or DIM, { Text = tostring(i) })
		local av = new("Frame", { Name = "Avatar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, avX, 0.5, 0),
			Size = UDim2.fromOffset(side, side), BackgroundColor3 = cfg.accent:Lerp(INK, 0.55), BorderSizePixel = 0, ZIndex = 4 }, row)
		new("UICorner", { CornerRadius = UDim.new(0.22, 0) }, av)
		local letter = text(av, "Letter", UDim2.fromScale(0.15, 0.15), UDim2.fromScale(0.7, 0.7), FONT_TITLE, WHITE, { ZIndex = 4 })
		local img = new("ImageLabel", { Name = "Head", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, av)
		new("UICorner", { CornerRadius = UDim.new(0.22, 0) }, img)
		if medal then
			new("UIStroke", { Color = medal, Thickness = math.max(1, u * 0.3), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, av)
		end
		local valX = 0.76 -- numbers stay short ("2,841"), names get the room
		local name = new("TextLabel", { Name = "Name", Position = UDim2.new(0, nameX, 0.1, 0), Size = UDim2.new(valX, -nameX, 0.52, 0),
			BackgroundTransparency = 1, Font = FONT_BOLD, TextColor3 = WHITE, TextSize = math.floor(rowPx * 0.36),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 4 }, row)
		local user = new("TextLabel", { Name = "User", Position = UDim2.new(0, nameX, 0.6, 0), Size = UDim2.new(valX, -nameX, 0.3, 0),
			BackgroundTransparency = 1, Font = FONT_CODE, TextColor3 = DIM, TextSize = math.floor(rowPx * 0.24),
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "", ZIndex = 4 }, row)
		local value = text(row, "Value", UDim2.fromScale(valX, 0.08), UDim2.fromScale(0.97 - valX, 0.56), FONT_BOLD, Color3.fromRGB(236, 242, 255),
			{ TextXAlignment = Enum.TextXAlignment.Right })
		text(row, "Unit", UDim2.fromScale(valX, 0.66), UDim2.fromScale(0.97 - valX, 0.26), FONT_TECH, medal or cfg.accent,
			{ Text = cfg.unit, TextXAlignment = Enum.TextXAlignment.Right })
		local me = new("UIStroke", { Color = cfg.accent, Thickness = math.max(2, u * 0.45), ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Enabled = false }, row)
		local shine
		if i == 1 then -- a slow light sweep across first place
			shine = new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(-0.2, 0.5),
				Size = UDim2.fromScale(0.05, 2.4), Rotation = 20, BackgroundColor3 = WHITE, BackgroundTransparency = 0.9, BorderSizePixel = 0,
				ZIndex = 3 }, row)
		end
		rows[i] = { frame = row, base = base, name = name, user = user, value = value, letter = letter, img = img, me = me, shine = shine }
	end
	local empty = text(root, "Empty", UDim2.fromScale(0.1, y0 + area * 0.3), UDim2.fromScale(0.8, area * 0.32), FONT_TITLE, WHITE,
		{ Text = cfg.empty .. "\nBE THE FIRST", Visible = false }) -- (2026-11-14) no kanji
	new("UIStroke", { Color = cfg.accent, Thickness = math.max(1, u * 0.35), Transparency = 0.4 }, empty)

	-- footer: the local player's own numbers + a blinking LIVE tag
	local foot = new("Frame", { Name = "Foot", Position = UDim2.fromScale(0, 1 - FOOT), Size = UDim2.fromScale(1, FOOT),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3 }, root)
	new("Frame", { Name = "Rule", Size = UDim2.new(1, 0, 0, math.max(1, math.floor(u * 0.3))), BackgroundColor3 = cfg.accent2,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 4 }, foot)
	local you = text(foot, "You", UDim2.fromScale(0.03, 0.18), UDim2.fromScale(0.72, 0.64), FONT_TECH, WHITE,
		{ TextXAlignment = Enum.TextXAlignment.Left })
	local liveTag = text(foot, "Live", UDim2.fromScale(0.78, 0.2), UDim2.fromScale(0.19, 0.6), FONT_TECH, cfg.accent2,
		{ Text = "● LIVE", TextXAlignment = Enum.TextXAlignment.Right })

	return { face = face, cfg = cfg, root = root, rows = rows, empty = empty, scope = scope, you = you, live = liveTag, glow = glow,
		phase = math.random() * 10 }
end

---------------------------------------------------------------------------------------------------------------------
-- RENDER
---------------------------------------------------------------------------------------------------------------------
local function flash(row)
	row.frame.BackgroundTransparency = 0.45
	TweenService:Create(row.frame, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = row.base }):Play()
end

local function footer(b, myRank)
	if b.cfg.key == "Kills" then
		local k = player:GetAttribute("LBKills") or 0
		b.you.Text = string.format("YOU  ◆  %s KILLS%s", comma(k), myRank and ("  ◆  #" .. myRank) or "")
	else
		local best = player:GetAttribute("LBBest") or 0
		local now = player:GetAttribute("KillStreak") or 0
		b.you.Text = string.format("YOU  ◆  BEST %s  ◆  NOW %s%s", comma(best), comma(now), myRank and ("  ◆  #" .. myRank) or "")
	end
end

local function render(b)
	local list = decode(data:GetAttribute(b.cfg.key))
	local myRank
	for i, row in ipairs(b.rows) do
		local e = list[i]
		row.frame.Visible = e ~= nil
		if e then
			local uid = tonumber(e.u) or 0
			local v = tonumber(e.v) or 0
			local display = tostring(e.d or "?")
			local uname = tostring(e.n or "")
			row.name.Text = display
			row.user.Text = (uname ~= "" and uname ~= display) and ("@" .. uname) or ""
			row.value.Text = comma(v)
			row.letter.Text = string.upper(string.sub(display, 1, 1))
			if row.uid ~= uid then
				row.img.Image = (uid > 0) and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", uid) or ""
			elseif row.v and v > row.v then
				flash(row) -- same player, number went up
			end
			row.uid, row.v = uid, v
			local mine = uid == player.UserId
			row.me.Enabled = mine
			row.name.TextColor3 = mine and b.cfg.accent or WHITE
			if mine then
				myRank = i
			end
		else
			row.uid, row.v = nil, nil
		end
	end
	b.empty.Visible = #list == 0
	b.scope.Text = (data:GetAttribute("Scope") == "global") and "ALL-TIME 歴代" or "THIS SERVER"
	b.myRank = myRank
	footer(b, myRank)
end

---------------------------------------------------------------------------------------------------------------------
-- SCREENS
---------------------------------------------------------------------------------------------------------------------
local boards = {} -- [face] = board

local function attach(face)
	if boards[face] or not face:IsA("BasePart") then
		return
	end
	local cfg = BOARDS[face:GetAttribute("Playlist")]
	if not cfg then
		return
	end
	boards[face] = false -- claimed while the SurfaceGui arrives
	task.spawn(function()
		local gui = face:WaitForChild("Screen", 20)
		local content = gui and gui:WaitForChild("Content", 20)
		if not content or not face.Parent then
			boards[face] = nil
			return
		end
		local b = build(face, cfg, content, gui.CanvasSize)
		boards[face] = b
		render(b)
	end)
end

local function detach(face)
	local b = boards[face]
	boards[face] = nil
	if b then
		b.root:Destroy()
	end
end

for _, f in ipairs(CollectionService:GetTagged("CityScreen")) do
	attach(f)
end
CollectionService:GetInstanceAddedSignal("CityScreen"):Connect(attach)
CollectionService:GetInstanceRemovedSignal("CityScreen"):Connect(detach)

data.AttributeChanged:Connect(function()
	for _, b in pairs(boards) do
		if b then
			render(b)
		end
	end
end)
player.AttributeChanged:Connect(function(name)
	if name == "LBKills" or name == "LBBest" or name == "KillStreak" then
		for _, b in pairs(boards) do
			if b then
				footer(b, b.myRank)
			end
		end
	end
end)

-- light motion: the title glow breathes, LIVE blinks, a sweep crosses first place (only while someone's close enough)
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	local t = os.clock()
	for face, b in pairs(boards) do
		if b and (face.Position - cp).Magnitude < 700 then
			local k = t + b.phase
			b.glow.Transparency = 0.55 + 0.3 * (0.5 + 0.5 * math.sin(k * 2.2))
			b.live.TextTransparency = (k % 1.2 < 0.8) and 0 or 0.75
			local sh = b.rows[1].shine
			if sh then
				sh.Position = UDim2.fromScale(-0.2 + ((k * 0.35) % 1.8), 0.5)
			end
		end
	end
end)
