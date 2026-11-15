--!nocheck
-- StarterPlayerScripts.DeathScreen (2026-11-10, "some kind of screen colour change or some small indication that you died"):
-- when the LOCAL player's character dies, the world drains to a red-tinted grey (a ColorCorrectionEffect under the
-- camera - local only), red edges close in, and a comic "K.O.!" slams in with who knocked you out (the victim's
-- LastHitBy attribute, set by every kit server) and a respawn countdown. All of it clears when the new character spawns.
-- Humanoid.Died fires up to 3 times on this game's ragdoll rigs, so one death = one screen (a per-character flag).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local FONT = Font.fromEnum(Enum.Font.GothamBlack)
local LABEL = Font.fromEnum(Enum.Font.GothamBold)
do
	local ok, Kits = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudShared", 10):WaitForChild("Kits", 10))
	end)
	if ok and type(Kits) == "table" then
		FONT = Kits.FONT_PUNCH or FONT
		LABEL = Kits.FONT_LABEL or LABEL
	end
end
local INK = Color3.fromRGB(14, 12, 24)
local RED = Color3.fromRGB(235, 40, 50)

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function tween(o, t, goal, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local current -- { gui, cc, alive }

local function clear()
	local c = current
	current = nil
	if not c then
		return
	end
	c.alive = false
	if c.cc and c.cc.Parent then
		local tw = tween(c.cc, 0.4, { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) })
		tw.Completed:Connect(function()
			c.cc:Destroy()
		end)
	end
	if c.gui then
		for _, d in ipairs(c.gui:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, 0.3, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.3, { Transparency = 1 })
			elseif d:IsA("Frame") then
				tween(d, 0.3, { BackgroundTransparency = 1 })
			end
		end
		task.delay(0.35, function()
			c.gui:Destroy()
		end)
	end
end

local function killerName(char)
	local uid = tonumber(char and char:GetAttribute("LastHitBy"))
	if not uid or uid == player.UserId then
		return nil
	end
	local p = Players:GetPlayerByUserId(uid)
	return p and p.DisplayName or nil
end

local function show(char)
	clear()
	local c = { alive = true }
	current = c
	-- the world: drained to grey with a red tint
	local cam = workspace.CurrentCamera
	if cam then
		c.cc = new("ColorCorrectionEffect", { Name = "DeathTint" }, cam)
		tween(c.cc, 0.35, { Saturation = -0.85, Contrast = 0.12, Brightness = -0.06, TintColor = Color3.fromRGB(255, 150, 150) })
	end
	local gui = new("ScreenGui", { Name = "DeathScreen", DisplayOrder = 90, IgnoreGuiInset = true, ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
	c.gui = gui
	-- red edges closing in (four gradient bars)
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		local horiz = side == "top" or side == "bottom"
		local f = new("Frame", { BackgroundColor3 = RED, BorderSizePixel = 0, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(side == "right" and 1 or 0, side == "bottom" and 1 or 0),
			Position = UDim2.fromScale(side == "right" and 1 or 0, side == "bottom" and 1 or 0),
			Size = horiz and UDim2.fromScale(1, 0.22) or UDim2.fromScale(0.16, 1) }, gui)
		new("UIGradient", { Rotation = ({ top = 90, bottom = 270, left = 0, right = 180 })[side], Transparency = NumberSequence.new(0, 1) }, f)
		tween(f, 0.5, { BackgroundTransparency = 0.35 })
	end
	-- K.O.! slams in
	local ko = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(0.5, 0.17),
		BackgroundTransparency = 1, Text = "K.O.!", FontFace = FONT, TextScaled = true, TextColor3 = Color3.fromRGB(255, 230, 60), Rotation = -6 }, gui)
	new("UITextSizeConstraint", { MaxTextSize = 120 }, ko)
	new("UIStroke", { Color = INK, Thickness = 5 }, ko)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 245, 160), Color3.fromRGB(255, 120, 40)) }, ko)
	local ks = new("UIScale", { Scale = 2.6 }, ko)
	tween(ks, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local by = killerName(char)
	local sub = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.49), Size = UDim2.fromScale(0.6, 0.05),
		BackgroundTransparency = 1, Text = by and ("KNOCKED OUT BY " .. string.upper(by)) or "YOU WERE KNOCKED OUT", FontFace = FONT, TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1 }, gui)
	new("UITextSizeConstraint", { MaxTextSize = 36 }, sub)
	local subStroke = new("UIStroke", { Color = INK, Thickness = 3, Transparency = 1 }, sub)
	tween(sub, 0.4, { TextTransparency = 0 })
	tween(subStroke, 0.4, { Transparency = 0 })
	local timer = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.fromScale(0.4, 0.035),
		BackgroundTransparency = 1, Text = "", FontFace = LABEL, TextScaled = true, TextColor3 = Color3.fromRGB(255, 205, 70) }, gui)
	new("UITextSizeConstraint", { MaxTextSize = 24 }, timer)
	new("UIStroke", { Color = INK, Thickness = 2 }, timer)
	-- respawn countdown (Players.RespawnTime; the screen clears itself on the next spawn whatever the timer says)
	task.spawn(function()
		local left = math.max(0, Players.RespawnTime)
		local t0 = os.clock()
		while c.alive and gui.Parent do
			local r = math.max(0, math.ceil(left - (os.clock() - t0)))
			timer.Text = r > 0 and ("RESPAWNING IN " .. r .. "...") or "RESPAWNING..."
			task.wait(0.1)
		end
	end)
end

local function hook(char)
	clear() -- a new body: the old death screen goes
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local shown = false
	hum.Died:Connect(function()
		if shown or player.Character ~= char then
			return
		end
		shown = true
		show(char)
	end)
end

player.CharacterAdded:Connect(hook)
if player.Character then
	task.spawn(hook, player.Character)
end
