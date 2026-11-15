--!nocheck
-- HudShared.VictoryFlash (2026-11-11, "wiki extras", CLIENT only): draws a VICTORY FLASH (HudShared.VictoryCatalog).
-- VictoryFlash.play(winner: Player, flashId, opts?) -> the ScreenGui (gone after VictoryCatalog.DURATION)
--   opts.sub   a line under the flash name ("+¥ 50", "PREVIEW", "YOU LOST")
-- A full-screen backdrop in the flash's colours, a slowly orbiting copy of the winner's body (as it stood when the duel
-- ended) in a ViewportFrame, their name + WINS!, the style's own effect layer and a sting (APM library).
-- Styles: crown (turning rays), thunder (bolts + flashes), petals (falling sakura), shatter (glass shards fly out),
-- spotlight (a stage light + confetti), flames (flickering fire along the bottom), void (rings + stars).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local V = require(script.Parent:WaitForChild("VictoryCatalog"))
local Kits = require(script.Parent:WaitForChild("Kits"))

local VF = {}
local WHITE, INK = Color3.new(1, 1, 1), Kits.INK
local STING = "rbxassetid://9047100306" -- APM "Hustler Sting 2" (sports hype end sting)

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
local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local function circle(parent, props)
	local f = new("Frame", props, parent)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end
local rng = Random.new()

---------------------------------------------------------------------------------------------------------------------
-- STYLE LAYERS (fx = a full-screen Frame, f = the catalog entry, dur = seconds)
local STYLES = {}

STYLES.crown = function(fx, f, dur)
	local hub = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1 }, fx)
	for i = 0, 11 do
		local ray = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 1400),
			Rotation = i * 30, BackgroundColor3 = f.c0, BackgroundTransparency = 0.72, BorderSizePixel = 0 }, hub)
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }, ray)
		local _ = ray
	end
	tween(hub, dur, { Rotation = 40 }, Enum.EasingStyle.Linear)
end

STYLES.thunder = function(fx, f, dur)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur - 0.5 and fx.Parent do
			local x = rng:NextNumber(0.08, 0.92)
			local y = 0
			local bolt = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, fx)
			for _ = 1, 5 do
				local len = rng:NextNumber(0.12, 0.22)
				local ang = rng:NextNumber(-35, 35)
				new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, y), Size = UDim2.new(0, 7, len, 0), Rotation = ang,
					BackgroundColor3 = f.c0, BorderSizePixel = 0 }, bolt)
				x += math.sin(math.rad(-ang)) * len * 0.5
				y += len * 0.9
			end
			local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, fx)
			tween(flash, 0.25, { BackgroundTransparency = 1 })
			task.delay(0.22, function()
				bolt:Destroy()
				flash:Destroy()
			end)
			task.wait(rng:NextNumber(0.28, 0.5))
		end
	end)
end

STYLES.petals = function(fx, f, dur)
	for _ = 1, 46 do
		local s = rng:NextInteger(10, 20)
		local p = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(rng:NextNumber(-0.1, 1.1), 0, rng:NextNumber(-0.6, -0.05), 0),
			Size = UDim2.fromOffset(s, math.floor(s * 0.6)), Rotation = rng:NextNumber(0, 360), BackgroundColor3 = f.c0:Lerp(WHITE, rng:NextNumber(0, 0.4)),
			BorderSizePixel = 0 }, fx)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
		local x = p.Position.X.Scale + rng:NextNumber(0.1, 0.35)
		tween(p, dur * rng:NextNumber(0.8, 1.1), { Position = UDim2.fromScale(x, 1.15), Rotation = p.Rotation + rng:NextNumber(200, 600) },
			Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end

STYLES.shatter = function(fx, f, dur)
	for i = 1, 18 do
		local ang = math.rad(i * 20 + rng:NextNumber(-8, 8))
		local w, h = rng:NextInteger(40, 110), rng:NextInteger(14, 40)
		local s = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h),
			Rotation = math.deg(ang) + rng:NextNumber(-30, 30), BackgroundColor3 = f.c0:Lerp(WHITE, 0.4), BackgroundTransparency = 0.15, BorderSizePixel = 0 }, fx)
		new("UIStroke", { Color = WHITE, Thickness = 2 }, s)
		local r = rng:NextNumber(0.45, 0.8)
		tween(s, 0.9, { Position = UDim2.fromScale(0.5 + math.cos(ang) * r, 0.5 + math.sin(ang) * r * 1.3), Rotation = s.Rotation + rng:NextNumber(-180, 180),
			BackgroundTransparency = 0.6 }, Enum.EasingStyle.Quart)
	end
	for i = 1, 7 do -- the cracks that stay
		new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.7, 0, 0, 3),
			Rotation = i * 51 + rng:NextNumber(-10, 10), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, fx)
	end
	local _ = dur
end

STYLES.spotlight = function(fx, f, dur)
	local light = circle(fx, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromScale(0.75, 1.3),
		BackgroundColor3 = f.c0, BackgroundTransparency = 0.55, BorderSizePixel = 0 })
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, light)
	local cols = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 214, 70), Color3.fromRGB(120, 230, 140) }
	for _ = 1, 60 do
		local c = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(rng:NextNumber(0, 1), 0, rng:NextNumber(-0.5, -0.02), 0),
			Size = UDim2.fromOffset(rng:NextInteger(6, 11), rng:NextInteger(10, 16)), Rotation = rng:NextNumber(0, 360), BackgroundColor3 = cols[rng:NextInteger(1, 4)],
			BorderSizePixel = 0 }, fx)
		tween(c, dur * rng:NextNumber(0.7, 1), { Position = UDim2.fromScale(c.Position.X.Scale + rng:NextNumber(-0.08, 0.08), 1.1),
			Rotation = c.Rotation + rng:NextNumber(300, 900) }, Enum.EasingStyle.Linear)
	end
end

STYLES.flames = function(fx, f, dur)
	for i = 0, 19 do
		local fl = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(i / 19, 1.02), Size = UDim2.new(0.09, 0, rng:NextNumber(0.25, 0.45), 0),
			BackgroundColor3 = WHITE, BorderSizePixel = 0 }, fx)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fl)
		new("UIGradient", { Rotation = -90, Color = ColorSequence.new(f.c1, f.c0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.7, 0.4), NumberSequenceKeypoint.new(1, 1) }) }, fl)
		local base = fl.Size.Y.Scale
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < dur and fl.Parent do
				tween(fl, 0.18, { Size = UDim2.new(0.09, 0, base * rng:NextNumber(0.75, 1.35), 0) }, Enum.EasingStyle.Sine)
				task.wait(0.18)
			end
		end)
	end
end

STYLES.void = function(fx, f, dur)
	for _ = 1, 40 do
		local s = rng:NextInteger(2, 5)
		local st = circle(fx, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0, 1)),
			Size = UDim2.fromOffset(s, s), BackgroundColor3 = WHITE, BackgroundTransparency = rng:NextNumber(0, 0.5), BorderSizePixel = 0 })
		tween(st, rng:NextNumber(0.3, 0.8), { BackgroundTransparency = 0.9 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Connect(function()
			if st.Parent then
				tween(st, 0.5, { BackgroundTransparency = 0.1 }, Enum.EasingStyle.Sine)
			end
		end)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur - 0.6 and fx.Parent do
			local ring = circle(fx, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1 })
			local sk = new("UIStroke", { Color = f.c0, Thickness = 5 }, ring)
			tween(ring, 1.2, { Size = UDim2.fromOffset(1400, 1400) }, Enum.EasingStyle.Quad)
			tween(sk, 1.2, { Transparency = 1 })
			task.delay(1.25, function()
				ring:Destroy()
			end)
			task.wait(0.4)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- a still copy of the winner's body for the ViewportFrame
local STRIP = { "LuaSourceContainer", "Sound", "BillboardGui", "SurfaceGui", "ForceField", "Highlight", "ParticleEmitter", "Trail", "Beam",
	"BodyMover", "Constraint", "Light" }
local function cloneBody(winner)
	local char = winner and winner.Character
	if not char then
		return nil
	end
	local was = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(char.Clone, char)
	char.Archivable = was
	if not ok or not copy then
		return nil
	end
	for _, d in ipairs(copy:GetDescendants()) do
		for _, c in ipairs(STRIP) do
			if d:IsA(c) then
				d:Destroy()
				break
			end
		end
	end
	for _, d in ipairs(copy:GetDescendants()) do
		if d.Parent and d:IsA("BasePart") then
			d.Anchored = true
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = copy:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	return copy
end

local active = nil

function VF.play(winner, id, opts)
	opts = opts or {}
	local f = V.byId[id] or V.byId[V.DEFAULT]
	if active then
		active:Destroy()
	end
	local dur = V.DURATION
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = new("ScreenGui", { Name = "VictoryFlash", IgnoreGuiInset = true, DisplayOrder = 30, ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	active = gui
	-- (a plain Frame, not a CanvasGroup: a ViewportFrame inside a CanvasGroup isn't drawn)
	local group = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0 }, gui)
	new("UIGradient", { Color = ColorSequence.new(f.c1, f.c0), Rotation = -60 }, group)
	local fx = new("Frame", { Name = "FX", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true }, group)
	-- the big glyph behind everything
	new("TextLabel", { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1,
		Text = f.glyph or "", TextScaled = true, TextColor3 = f.c1, TextTransparency = 0.6, FontFace = Font.fromEnum(Enum.Font.GothamBlack) }, group)
	local stage = new("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1 }, group)
	local pop = new("UIScale", { Scale = 1.25 }, stage)
	-- the winner
	local body = cloneBody(winner)
	local cam, vpf
	if body then
		vpf = new("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.6, 0.86),
			BackgroundTransparency = 1, Ambient = Color3.fromRGB(190, 190, 205), LightColor = WHITE, LightDirection = Vector3.new(-0.6, -1, -0.8) }, stage)
		local world = new("WorldModel", {}, vpf)
		body:PivotTo(CFrame.new())
		body.Parent = world
		cam = new("Camera", { FieldOfView = 30 }, vpf)
		vpf.CurrentCamera = cam
	end
	local name = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.05), Size = UDim2.fromScale(0.9, 0.15), BackgroundTransparency = 1,
		Text = string.upper(winner and winner.DisplayName or "?"), TextScaled = true, TextColor3 = WHITE, FontFace = Kits.FONT_PUNCH }, stage)
	new("UIStroke", { Color = INK, Thickness = 5 }, name)
	local wins = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.19), Size = UDim2.fromScale(0.5, 0.09), BackgroundTransparency = 1,
		Text = "WINS!", TextScaled = true, TextColor3 = f.c0, FontFace = Kits.FONT_PUNCH, Rotation = -4 }, stage)
	new("UIStroke", { Color = INK, Thickness = 4 }, wins)
	local tag = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.97), Size = UDim2.fromScale(0.6, 0.05), BackgroundTransparency = 1,
		Text = string.upper(f.name) .. (opts.sub and ("   -   " .. opts.sub) or ""), TextScaled = true, TextColor3 = WHITE, FontFace = Kits.FONT_LABEL }, stage)
	new("UIStroke", { Color = INK, Thickness = 2 }, tag)
	gui.Parent = pg
	-- in
	tween(group, 0.18, { BackgroundTransparency = 0 })
	tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	pcall(STYLES[f.style] or STYLES.crown, fx, f, dur)
	local s = new("Sound", { SoundId = STING, Volume = 0.8, SoundGroup = SoundService:FindFirstChild("SettingsSFX") }, gui)
	s:Play()
	-- the camera slowly swings round the winner
	local conn
	if cam and body then
		local head = body:FindFirstChild("Head")
		local focus = head and head.Position or Vector3.new(0, 1.5, 0)
		local t0 = os.clock()
		conn = RunService.RenderStepped:Connect(function()
			local a = math.rad(-28 + (os.clock() - t0) / dur * 56)
			local at = focus + Vector3.new(math.sin(a) * 9, -0.6, -math.cos(a) * 9)
			cam.CFrame = CFrame.lookAt(at, focus - Vector3.new(0, 1.1, 0))
		end)
	end
	task.delay(dur - 0.4, function() -- out: everything fades on its own (no CanvasGroup)
		if not gui.Parent then
			return
		end
		fx:Destroy()
		tween(group, 0.4, { BackgroundTransparency = 1 })
		if vpf then
			tween(vpf, 0.4, { ImageTransparency = 1 })
		end
		for _, d in ipairs(group:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, 0.4, { TextTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, 0.4, { Transparency = 1 })
			end
		end
	end)
	task.delay(dur, function()
		if conn then
			conn:Disconnect()
		end
		if active == gui then
			active = nil
		end
		gui:Destroy()
	end)
	return gui
end

return VF
