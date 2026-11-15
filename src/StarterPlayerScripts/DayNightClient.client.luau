--!nocheck
-- StarterPlayerScripts.DayNightClient (2026-11-07): paints the day/night cycle. The clock comes from the server's
-- workspace "DayNightEpoch" (ServerScriptService.DayNightService), so every player sees the same hour; the look and the
-- timing live in ReplicatedStorage.CityShared.DayNight. 20 times a second it sets Lighting (ClockTime, brightness,
-- ambient, exposure), the Atmosphere, the ArenaGrade colour correction, Bloom, SunRays, swaps the night skybox for
-- Roblox's default sky in daylight, dims the city's lamps by day, and shows a DAYBREAK / NIGHTFALL banner.
--
-- SHARING LIGHTING. Two moves take Lighting over for a few seconds and put it back themselves: Gojo's Unlimited Void
-- (GojoClient applyVoid) and Sukuna's domain sky (CarverClient). Both SNAPSHOT Lighting when they start and RESTORE that
-- snapshot when they end. So this script never fights them: if Lighting no longer holds what it wrote last, someone
-- else is driving it - it stops writing, remembers its last values (= their snapshot), and resumes once Lighting is back
-- to those values and has stopped changing, easing over 2.5 s from there to the current hour (the sun moved meanwhile).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local DN = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("DayNight"))
local Kits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))

local TICK = 1 / 20
local BLEND_BACK = 2.5 -- seconds to ease back to the live hour after a domain hands Lighting back
local FACES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }

-- the effects this script drives, found by NAME (the moves add their own ColorCorrection / Atmosphere and must be left be)
local function child(name, class)
	local c = Lighting:FindFirstChild(name)
	return (c and c:IsA(class)) and c or nil
end

-- the night skybox = the textures the map was built with
local nightSky = {}
do
	local s = Lighting:FindFirstChildOfClass("Sky")
	for _, f in ipairs(FACES) do
		nightSky[f] = s and s[f] or ""
	end
end
local skyMode -- "day" | "night" as last set
local function setSky(day)
	local mode = day and "day" or "night"
	local s = Lighting:FindFirstChildOfClass("Sky")
	if not s or skyMode == mode then
		return
	end
	skyMode = mode
	for _, f in ipairs(FACES) do
		s[f] = day and "" or nightSky[f] -- "" = Roblox's default sky, which the Atmosphere turns into a clear blue day
	end
end

-- the city's lamps / sign lights: scaled from their built brightness
-- (a plain table: Roblox can drop Instance keys from a weak table while the instance still exists; destroyed lights
-- are removed in setLamps)
local lamps = {}
local lampMul
local function track(l)
	if l:IsA("Light") and lamps[l] == nil then
		lamps[l] = l.Brightness
		if lampMul then
			l.Brightness = lamps[l] * lampMul
		end
	end
end
task.spawn(function()
	local city = workspace:WaitForChild(DN.LIGHTS_ROOT, 60)
	if not city then
		return
	end
	for _, d in ipairs(city:GetDescendants()) do
		track(d)
	end
	city.DescendantAdded:Connect(track)
end)
local function setLamps(m)
	if lampMul and math.abs(m - lampMul) < 0.01 then
		return
	end
	lampMul = m
	for l, base in pairs(lamps) do
		if l.Parent then
			l.Brightness = base * m
		else
			lamps[l] = nil -- destroyed (a smashed lamp)
		end
	end
end

-- the clock -----------------------------------------------------------------------------------------------------------
local clockNow = DN.clockNow -- the shared clock (NightOutlines reads the same one)

-- reading / writing Lighting ---------------------------------------------------------------------------------------
local WATCH = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation" }
local function readWatched()
	local t = {}
	for _, k in ipairs(WATCH) do
		t[k] = Lighting[k]
	end
	return t
end
local function close(a, b, tol)
	for k, v in pairs(a) do
		local w = b[k]
		if typeof(v) == "Color3" then
			if math.abs(v.R - w.R) > tol or math.abs(v.G - w.G) > tol or math.abs(v.B - w.B) > tol then
				return false
			end
		elseif k == "ClockTime" then
			local d = math.abs(v - w) % 24
			if math.min(d, 24 - d) > math.max(tol, 0.0005) * 2 then
				return false
			end
		elseif math.abs(v - w) > tol then
			return false
		end
	end
	return true
end

-- the whole current look, in DN.sample's shape (the start of an ease back)
local function readLook()
	local look = {
		Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		ExposureCompensation = Lighting.ExposureCompensation, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale, lights = lampMul or 1,
	}
	local ref = DN.sample(0)
	local function grab(inst, keys)
		local t = {}
		for k, v in pairs(keys) do
			t[k] = inst and inst[k] or v
		end
		return t
	end
	look.atm = grab(child("Atmosphere", "Atmosphere"), ref.atm)
	look.grade = grab(child("ArenaGrade", "ColorCorrectionEffect"), ref.grade)
	look.bloom = grab(child("Bloom", "BloomEffect"), ref.bloom)
	look.rays = grab(child("SunRays", "SunRaysEffect"), ref.rays)
	return look
end

local function apply(look, clock)
	Lighting.ClockTime = clock
	Lighting.Brightness = look.Brightness
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = look.OutdoorAmbient
	Lighting.ExposureCompensation = look.ExposureCompensation
	Lighting.EnvironmentDiffuseScale = look.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = look.EnvironmentSpecularScale
	for name, spec in pairs({ Atmosphere = { "Atmosphere", look.atm }, ArenaGrade = { "ColorCorrectionEffect", look.grade },
		Bloom = { "BloomEffect", look.bloom }, SunRays = { "SunRaysEffect", look.rays } }) do
		local inst = child(name, spec[1])
		if inst then
			for k, v in pairs(spec[2]) do
				inst[k] = v
			end
		end
	end
	setLamps(look.lights)
end

-- banners ------------------------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DayNightBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 3
gui.Parent = player:WaitForChild("PlayerGui")
local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.2)
holder.Size = UDim2.fromOffset(520, 96)
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = gui
local bigText = Instance.new("TextLabel")
bigText.Size = UDim2.new(1, 0, 0, 62)
bigText.BackgroundTransparency = 1
bigText.TextScaled = true
bigText.FontFace = Kits.FONT_PUNCH
bigText.TextColor3 = Color3.new(1, 1, 1)
bigText.Parent = holder
local bigStroke = Instance.new("UIStroke")
bigStroke.Thickness = 3
bigStroke.Color = Kits.INK
bigStroke.Parent = bigText
local bigGrad = Instance.new("UIGradient")
bigGrad.Rotation = 90
bigGrad.Parent = bigText
local subText = Instance.new("TextLabel")
subText.Position = UDim2.fromOffset(0, 64)
subText.Size = UDim2.new(1, 0, 0, 24)
subText.BackgroundTransparency = 1
subText.TextScaled = true
subText.FontFace = Kits.FONT_LABEL
subText.Parent = holder
local subStroke = Instance.new("UIStroke")
subStroke.Thickness = 2
subStroke.Color = Kits.INK
subStroke.Parent = subText
local holderScale = Instance.new("UIScale")
holderScale.Parent = holder
local bannerToken = 0
local function banner(b)
	if player:GetAttribute("StarterPicked") == false then
		return -- not over the first-join pick screen
	end
	bannerToken += 1
	local my = bannerToken
	bigText.Text = b.text
	bigGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), b.color)
	subText.Text = b.jp
	subText.TextColor3 = b.color
	for _, o in ipairs({ bigText, subText }) do
		o.TextTransparency = 1
		TweenService:Create(o, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	end
	bigStroke.Transparency, subStroke.Transparency = 1, 1
	TweenService:Create(bigStroke, TweenInfo.new(0.5), { Transparency = 0 }):Play()
	TweenService:Create(subStroke, TweenInfo.new(0.5), { Transparency = 0 }):Play()
	holderScale.Scale = 1.25
	TweenService:Create(holderScale, TweenInfo.new(0.6, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	holder.Visible = true
	task.delay(3, function()
		if bannerToken ~= my then
			return
		end
		for _, o in ipairs({ bigText, subText }) do
			TweenService:Create(o, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		end
		TweenService:Create(bigStroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		TweenService:Create(subStroke, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		task.delay(0.85, function()
			if bannerToken == my then
				holder.Visible = false
			end
		end)
	end)
end
-- crossed `at` going from a to b (forward in time, wrapping at 24)?
local function crossed(a, b, at)
	if a == nil or a == b then
		return false
	end
	local span = (b - a) % 24
	if span > 2 then
		return false -- a jump (freeze / big lag): no banner
	end
	return ((at - a) % 24) > 0 and ((at - a) % 24) <= span
end

-- the loop ----------------------------------------------------------------------------------------------------------
local last -- what Lighting held right after this script's last write (WATCH props)
local override -- { snap, t0, prev, stableFor } while a move drives Lighting
local blend -- { from = look, clock = ClockTime, t0 } easing back after a move
local prevClock
local acc = 0
local state = { mode = "starting" } -- (Studio debug) what happened on the last tick

local function lerpClock(a, b, t)
	local d = ((b - a + 12) % 24) - 12
	return (a + d * t) % 24
end

local function step(dt)
	local clock = clockNow()
	if not clock then
		state.mode = "waiting"
		return
	end
	local now = os.clock()
	for _, b in ipairs(DN.BANNERS) do
		if crossed(prevClock, clock, b.at) then
			banner(b)
		end
	end
	prevClock = clock
	state.clock = clock

	if override then
		local cur = readWatched()
		if override.prev and close(cur, override.prev, 1e-4) then
			override.stableFor += dt
		else
			override.stableFor = 0
		end
		override.prev = cur
		local back = close(cur, override.snap, 0.03) and override.stableFor >= 0.25
		local stale = now - override.t0 > 90 and override.stableFor >= 8 -- a safety net: never paused for good
		if not (back or stale) then
			state.mode = "yielding"
			return
		end
		override = nil
		blend = { from = readLook(), clock = Lighting.ClockTime, t0 = now }
	elseif last and not close(readWatched(), last, 0.002) then
		override = { snap = last, t0 = now, stableFor = 0 }
		state.mode = "yielding"
		state.yields = (state.yields or 0) + 1
		return
	end

	local look = DN.sample(clock)
	local writeClock = clock
	if blend then
		local a = (now - blend.t0) / BLEND_BACK
		if a >= 1 then
			blend = nil
		else
			a = a * a * (3 - 2 * a)
			look = DN.mixTable(blend.from, look, a)
			writeClock = lerpClock(blend.clock, clock, a)
		end
	end
	apply(look, writeClock)
	setSky(DN.skyIsDay(clock))
	last = readWatched()
	state.mode = blend and "easing back" or "running"
	state.phase = DN.phaseAt(clock)
end

RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then
		return
	end
	local d = acc
	acc = 0
	local ok, err = pcall(step, d)
	if not ok then
		state.mode = "error"
		state.err = tostring(err)
	end
end)

-- Studio: script.DayNightDebug:Invoke("state") -> what the cycle is doing; ("banner", "DAYBREAK" | "NIGHTFALL") shows one
if RunService:IsStudio() then
	local f = Instance.new("BindableFunction")
	f.Name = "DayNightDebug"
	f.OnInvoke = function(cmd, arg)
		if cmd == "state" then
			local s = table.clone(state)
			s.overridden = override ~= nil
			s.sky = skyMode
			s.lampMul = lampMul
			local n = 0
			for _ in pairs(lamps) do
				n += 1
			end
			s.lamps = n
			return s
		elseif cmd == "banner" then
			for _, b in ipairs(DN.BANNERS) do
				if b.text == arg then
					banner(b)
				end
			end
			return true
		end
		return nil
	end
	f.Parent = script
end
