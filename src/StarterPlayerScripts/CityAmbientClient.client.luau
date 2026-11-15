-- StarterPlayer.StarterPlayerScripts.CityAmbientClient (outskirts builder, 2026-11-07) - NEON SHIBUYA ambient FX.
-- CONTRACT section 8. Client-only, never writes Lighting, every effect distance-gated and capped:
--   rain sheet around the camera (stops under roofs / decks) + rare far-off sky flashes
--   CitySteam attachments -> smoke puffs (<= 40 nearest within 220)
--   drones on lanes over the streets (y 64..100, drawn within 400)
--   the AOI LINE train (Plan.rail.train: 6 cars, 110 studs/s, alternating south / north every 25 s on a server-time
--     schedule so every client agrees; drawn while the camera is within 500 of x 328; a run fades out for good while
--     any player stands on the viaduct within 60 studs behind / 120 ahead of it - DECISIONS 5)
--   CityScreen faces -> animated SurfaceGui content (<= 8 nearest within 600, the rest keep their still Fallback);
--     faces whose Playlist starts with "board_" are leaderboards and belong to LeaderboardClient (2026-11-08)
--   CityFlicker neon -> short buzz-outs (<= 30 at once within 300; Color only, never Transparency)
--   CityHolo -> spin (attribute Spin, degrees / s) + transparency pulse (attribute Pulse) within 400
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
local rng = Random.new()

local FX = Instance.new("Folder")
FX.Name = "CityAmbientFX"
FX.Parent = workspace

local function camPos()
	local c = workspace.CurrentCamera
	return c and c.CFrame.Position or Vector3.zero
end

local function ghost(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function tracked(tag)
	local set = {}
	for _, i in ipairs(CollectionService:GetTagged(tag)) do
		set[i] = true
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(i)
		set[i] = true
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(i)
		set[i] = nil
	end)
	return set
end

local function isBroken(inst)
	return inst:GetAttribute("Broken") == true or (inst.Parent ~= nil and inst.Parent:GetAttribute("Broken") == true)
end

---------------------------------------------------------------------------------------------------------------------
-- RAIN
---------------------------------------------------------------------------------------------------------------------
local rain = ghost({ Name = "RainSheet", Size = Vector3.new(160, 1, 160), Transparency = 1 })
local rainPE = Instance.new("ParticleEmitter")
rainPE.Name = "Rain"
rainPE.Texture = "rbxasset://textures/particles/sparkles_main.dds"
rainPE.Color = ColorSequence.new(Color3.fromRGB(176, 192, 238))
rainPE.LightEmission = 0.3
rainPE.LightInfluence = 0.35
rainPE.Transparency = NumberSequence.new(0.5)
rainPE.Size = NumberSequence.new(0.13)
rainPE.Squash = NumberSequence.new(2.6)
rainPE.Orientation = Enum.ParticleOrientation.VelocityParallel
rainPE.Shape = Enum.ParticleEmitterShape.Box
rainPE.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
rainPE.EmissionDirection = Enum.NormalId.Bottom
rainPE.Speed = NumberRange.new(125, 150)
rainPE.Lifetime = NumberRange.new(0.55, 0.7)
rainPE.Acceleration = Vector3.new(6, -20, 2)
rainPE.Rate = 0
rainPE.Parent = rain
rain.Parent = FX
local RAIN_RATE = 420
local rainTarget, rainRate = RAIN_RATE, 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	local list = { FX }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(list, npcs)
	end
	rayParams.FilterDescendantsInstances = list
end

local flash = ghost({ Name = "SkyFlash", Shape = Enum.PartType.Ball, Size = Vector3.new(900, 900, 900), Material = Enum.Material.Neon,
	Color = Color3.fromRGB(196, 184, 255), Transparency = 1 })
flash.Parent = FX
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(35, 90))
		local a = rng:NextNumber(0, math.pi * 2)
		flash.CFrame = CFrame.new(camPos() * Vector3.new(1, 0, 1) + Vector3.new(math.cos(a) * 2600, 1100, math.sin(a) * 2600))
		for _, t in ipairs({ 0.86, 1, 0.9, 1 }) do
			flash.Transparency = t
			task.wait(rng:NextNumber(0.05, 0.12))
		end
		flash.Transparency = 1
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- STEAM
---------------------------------------------------------------------------------------------------------------------
local steamSet = tracked("CitySteam")
local steamFX = {}
local function makeSteam(a)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "CitySteamFX"
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	local sz = a:GetAttribute("Size") or 4
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz * 0.4), NumberSequenceKeypoint.new(1, sz * 1.7) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.62),
		NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(204, 198, 226))
	pe.LightInfluence = 0.7
	pe.LightEmission = 0.05
	pe.Rate = a:GetAttribute("Rate") or 6
	pe.Lifetime = NumberRange.new(2.2, 3.6)
	pe.Speed = NumberRange.new(3, 6)
	pe.SpreadAngle = Vector2.new(14, 14)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(1.2, 1.4, 0.4)
	pe.Drag = 0.6
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-20, 20)
	pe.Parent = a
	return pe
end
local function updateSteam(cp)
	local near = {}
	for a in pairs(steamSet) do
		if a:IsA("Attachment") and a.Parent then
			local d = (a.WorldPosition - cp).Magnitude
			if d < 220 then
				table.insert(near, { a, d })
			elseif steamFX[a] and d > 320 then
				steamFX[a]:Destroy()
				steamFX[a] = nil
			end
		end
	end
	table.sort(near, function(x, y)
		return x[2] < y[2]
	end)
	local on = {}
	for i = 1, math.min(40, #near) do
		local a = near[i][1]
		on[a] = true
		if not steamFX[a] then
			steamFX[a] = makeSteam(a)
		end
		steamFX[a].Enabled = true
	end
	for a, pe in pairs(steamFX) do
		if not on[a] then
			pe.Enabled = false
		end
		if not a.Parent then
			pe:Destroy()
			steamFX[a] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- DRONES (lanes over the street centre lines; E-W lanes stay above the rail at 60, N-S lanes above SKYWAY 9)
---------------------------------------------------------------------------------------------------------------------
local V3 = Vector3.new
local LANES = {
	{ V3(-760, 70, 0), V3(760, 70, 0) }, -- Hikari-dori
	{ V3(0, 94, -760), V3(0, 94, 760) }, -- Kumo-dori
	{ V3(-760, 102, 336), V3(760, 102, 336) }, -- Tetsu-dori (over the deck)
	{ V3(-760, 66, -336), V3(760, 66, -336) }, -- Kita-dori
	{ V3(-328, 92, -760), V3(-328, 92, 760) }, -- Nishi-dori
	{ V3(-660, 66, -640), V3(660, 66, -640) }, -- Kanjo-dori N
	{ V3(-660, 66, 640), V3(660, 66, 640) }, -- Kanjo-dori S
	{ V3(-640, 92, -660), V3(-640, 92, 660) }, -- Kanjo-dori W
	{ V3(640, 92, -660), V3(640, 92, 660) }, -- Kanjo-dori E
}
local drones = {}
local function makeDrone(i)
	local m = Instance.new("Model")
	m.Name = "Drone" .. i
	local body = ghost({ Name = "Body", Size = V3(2.2, 0.5, 2.2), Color = Color3.fromRGB(42, 46, 54), Material = Enum.Material.Metal })
	local red = ghost({ Name = "NavRed", Shape = Enum.PartType.Ball, Size = V3(0.4, 0.4, 0.4), Color = Color3.fromRGB(255, 36, 36),
		Material = Enum.Material.Neon })
	local grn = ghost({ Name = "NavGreen", Shape = Enum.PartType.Ball, Size = V3(0.4, 0.4, 0.4), Color = Color3.fromRGB(40, 255, 160),
		Material = Enum.Material.Neon })
	local glow = ghost({ Name = "Under", Size = V3(1.4, 0.12, 1.4), Color = (i % 2 == 0) and Color3.fromRGB(0, 230, 255) or Color3.fromRGB(255, 40, 170),
		Material = Enum.Material.Neon })
	for _, p in ipairs({ body, red, grn, glow }) do
		p.Parent = m
	end
	local lane = LANES[(i - 1) % #LANES + 1]
	return { model = m, parts = { body, red, grn, glow }, offs = { CFrame.new(), CFrame.new(-1.3, 0.1, 0), CFrame.new(1.3, 0.1, 0), CFrame.new(0, -0.32, 0) },
		a = lane[1] + V3(rng:NextNumber(-10, 10), rng:NextNumber(-4, 6), rng:NextNumber(-10, 10)),
		b = lane[2] + V3(rng:NextNumber(-10, 10), rng:NextNumber(-4, 6), rng:NextNumber(-10, 10)),
		speed = rng:NextNumber(18, 32), phase = rng:NextNumber(0, 3000), bob = rng:NextNumber(0, 6), shown = false, cf = CFrame.new() }
end
for i = 1, 14 do
	drones[i] = makeDrone(i)
end
local function droneCF(d, t)
	local L = (d.b - d.a).Magnitude
	local s = (t * d.speed + d.phase) % (2 * L)
	local fwd = 1
	if s > L then
		s = 2 * L - s
		fwd = -1
	end
	local dir = (d.b - d.a).Unit
	local p = d.a + dir * s + V3(0, math.sin(t * 1.3 + d.bob) * 1.2, 0)
	return CFrame.lookAt(p, p + dir * fwd) * CFrame.Angles(math.rad(-6), 0, math.sin(t * 0.8 + d.bob) * 0.08)
end

---------------------------------------------------------------------------------------------------------------------
-- AOI LINE TRAIN (Plan.rail.train)
---------------------------------------------------------------------------------------------------------------------
local TR = { cars = 6, carLen = 60, gap = 2, width = 10, height = 13, floorY = 46.4, speed = 110, period = 25, zMin = -1016, zMax = 1016,
	south = 316, north = 340, deck = { 304, 352, 43, 64 }, platform = { 321, 335, -276, -64 } }
local TRAIN_LEN = TR.cars * TR.carLen + (TR.cars - 1) * TR.gap
local function makeTrain(dirName)
	local m = Instance.new("Model")
	m.Name = "AoiTrain_" .. dirName
	local parts, offs, base = {}, {}, {}
	local fwd = (dirName == "south") and 1 or -1 -- +Z is the front for the southbound train
	local function add(car, props, off)
		local p = ghost(props)
		p.Parent = m
		table.insert(parts, p)
		table.insert(offs, { car = car, cf = off })
		base[p] = props.Transparency or 0
	end
	local y0 = TR.floorY
	for c = 0, TR.cars - 1 do
		add(c, { Name = "Body", Size = V3(TR.width, 11.2, TR.carLen - 1), Color = Color3.fromRGB(214, 220, 230), Reflectance = 0.05 }, CFrame.new(0, y0 + 0.6 + 5.6, 0))
		add(c, { Name = "Windows", Size = V3(TR.width + 0.15, 2.2, TR.carLen - 5), Color = Color3.fromRGB(150, 205, 255), Material = Enum.Material.Neon,
			Transparency = 0.15 }, CFrame.new(0, y0 + 7.2, 0))
		add(c, { Name = "Stripe", Size = V3(TR.width + 0.2, 0.9, TR.carLen - 0.8), Color = Color3.fromRGB(40, 110, 255), Material = Enum.Material.Neon },
			CFrame.new(0, y0 + 3.4, 0))
		add(c, { Name = "Roof", Size = V3(TR.width - 1.6, 0.8, TR.carLen - 4), Color = Color3.fromRGB(42, 46, 54), Material = Enum.Material.Metal },
			CFrame.new(0, y0 + 12.2, 0))
		add(c, { Name = "Under", Size = V3(TR.width - 2, 1.1, TR.carLen - 8), Color = Color3.fromRGB(24, 24, 28) }, CFrame.new(0, y0 - 0.45, 0))
	end
	add(0, { Name = "HeadLight", Size = V3(6, 1, 0.3), Color = Color3.fromRGB(225, 236, 255), Material = Enum.Material.Neon },
		CFrame.new(0, y0 + 4.6, fwd * (TR.carLen / 2 - 0.3)))
	add(TR.cars - 1, { Name = "TailLight", Size = V3(6, 0.8, 0.3), Color = Color3.fromRGB(255, 36, 36), Material = Enum.Material.Neon },
		CFrame.new(0, y0 + 4.6, -fwd * (TR.carLen / 2 - 0.3)))
	return { model = m, parts = parts, offs = offs, base = base, dir = dirName, x = TR[dirName], fwd = fwd, shown = false }
end
local trains = { south = makeTrain("south"), north = makeTrain("north") }
local trainRun, trainFaded, trainAlpha = -1, false, 0
local cfBuf = {}

local function playerNearTrack(trainX, zTail, zHead, fwd)
	local P = TR.platform
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local q = hrp.Position
			local onDeck = q.X >= TR.deck[1] and q.X <= TR.deck[2] and q.Y >= TR.deck[3] and q.Y <= TR.deck[4]
			local onPlatform = q.X >= P[1] and q.X <= P[2] and q.Z >= P[3] and q.Z <= P[4]
			if onDeck and not onPlatform and math.abs(q.X - trainX) < 14 then
				local lo, hi = math.min(zTail, zHead), math.max(zTail, zHead)
				local ahead = (q.Z - zHead) * fwd -- > 0 when the player is in front of the train
				if (q.Z >= lo - 60 and q.Z <= hi + 60) or (ahead > 0 and ahead < 120) then
					return true
				end
			end
		end
	end
	return false
end

local function updateTrain(now, cp, dt)
	local run = math.floor(now / TR.period)
	local tRun = now - run * TR.period
	local dirName = (run % 2 == 0) and "south" or "north"
	local tr = trains[dirName]
	local other = trains[dirName == "south" and "north" or "south"]
	if other.shown then
		other.model.Parent = nil
		other.shown = false
	end
	if run ~= trainRun then
		trainRun, trainFaded, trainAlpha = run, false, 0
	end
	local zHead = (tr.fwd > 0) and (TR.zMin + TR.speed * tRun) or (TR.zMax - TR.speed * tRun)
	local zTail = zHead - tr.fwd * TRAIN_LEN
	local active = (tr.fwd > 0 and zTail < TR.zMax) or (tr.fwd < 0 and zTail > TR.zMin)
	local nearCam = math.abs(cp.X - 328) < 500 and math.abs(cp.Z) < 1400
	if not active or not nearCam then
		if tr.shown then
			tr.model.Parent = nil
			tr.shown = false
		end
		return
	end
	if not trainFaded and playerNearTrack(tr.x, zTail, zHead, tr.fwd) then
		trainFaded = true
	end
	trainAlpha = math.clamp(trainAlpha + (trainFaded and -dt or dt) / 0.35, 0, 1)
	if trainFaded and trainAlpha <= 0 then
		if tr.shown then
			tr.model.Parent = nil
			tr.shown = false
		end
		return
	end
	if not tr.shown then
		tr.model.Parent = FX
		tr.shown = true
	end
	table.clear(cfBuf)
	for i, p in ipairs(tr.parts) do
		local o = tr.offs[i]
		local cz = zHead - tr.fwd * (o.car * (TR.carLen + TR.gap) + TR.carLen / 2)
		cfBuf[i] = CFrame.new(tr.x, 0, cz) * o.cf
		local want = 1 - (1 - tr.base[p]) * trainAlpha
		if math.abs(p.Transparency - want) > 0.01 then
			p.Transparency = want
		end
	end
	workspace:BulkMoveTo(tr.parts, cfBuf, Enum.BulkMoveMode.FireCFrameChanged)
end

local function nextTrains(now)
	-- seconds until the next southbound / northbound run starts passing the station (z ~ -170)
	local out = {}
	for _, dirName in ipairs({ "south", "north" }) do
		local fwd = (dirName == "south") and 1 or -1
		local reach = (fwd > 0) and (-170 - TR.zMin) / TR.speed or (TR.zMax + 170) / TR.speed
		local best = math.huge
		local base = math.floor(now / TR.period) - 2
		for k = base, base + 6 do
			local isDir = ((k % 2 == 0) and "south" or "north") == dirName
			if isDir then
				local at = k * TR.period + reach
				if at >= now and at - now < best then
					best = at - now
				end
			end
		end
		out[dirName] = best
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- SCREENS
---------------------------------------------------------------------------------------------------------------------
local ADS = {
	{ "ZAP COLA", "ザップコーラ", "ZAP! 弾けろ", Color3.fromRGB(176, 24, 40) },
	{ "GENKI-X", "元気X", "ENERGY 120%", Color3.fromRGB(28, 30, 34) },
	{ "MATCHA FIZZ", "抹茶フィズ", "GREEN & SPARKLING", Color3.fromRGB(36, 112, 70) },
	{ "NEON SODA", "ネオンソーダ", "DRINK THE NIGHT", Color3.fromRGB(36, 56, 160) },
	{ "KAGAMI CORP", "鏡コーポ", "SEE YOURSELF TOMORROW", Color3.fromRGB(60, 40, 110) },
	{ "HELIX DYNAMICS", "ヘリックス", "ROBOTICS FOR LIFE", Color3.fromRGB(20, 70, 90) },
	{ "TENGU AIR", "天狗航空", "FLY ABOVE THE RAIN", Color3.fromRGB(150, 30, 40) },
	{ "KUMO CLOUD", "雲クラウド", "YOUR DATA, ABOVE", Color3.fromRGB(30, 60, 120) },
	{ "PIXEL PAW", "ピクセルパウ", "A FRIEND WHO NEVER SLEEPS", Color3.fromRGB(120, 50, 130) },
	{ "RYU MOTORS", "龍モーターズ", "DRIVE THE DRAGON", Color3.fromRGB(110, 62, 40) },
	{ "SHOJO STAR", "少女スター", "LIVE TONIGHT ★", Color3.fromRGB(200, 60, 140) },
	{ "AOBA PHARMA", "青葉製薬", "FEEL NEW", Color3.fromRGB(30, 110, 100) },
	{ "CHROME LOTUS", "クロームロータス", "SHINE BRIGHTER", Color3.fromRGB(80, 80, 100) },
	{ "BOLT BURGER", "ボルトバーガー", "FAST. LOUD. HOT.", Color3.fromRGB(200, 120, 20) },
	{ "CURRY MECH", "カレーメカ", "SPICE UNIT ONLINE", Color3.fromRGB(170, 100, 20) },
}
local WORDS = { "営業中", "24時間", "電脳", "ネオン", "ラーメン", "カラオケ", "ゲーム", "居酒屋", "夜", "未来", "喫茶", "寿司", "焼肉", "ホテル",
	"バー", "クラブ", "注意", "止まれ" }
local NEWS = { "雨 RAIN ALL NIGHT - 降水確率 90%", "新街道 SHIN-KAIDO 夜 NIGHT", "TRAINS ON SCHEDULE のりば", "NIGHT MARKET OPEN 営業中",
	"DRONE DELIVERY ZONE ACTIVE", "TEMP 14°C  WIND 3m/s", "STREET FIGHT ALERT 注意 - STAY CLEAR" }
local NEONS = { Color3.fromRGB(255, 40, 170), Color3.fromRGB(0, 230, 255), Color3.fromRGB(255, 168, 28), Color3.fromRGB(170, 255, 40),
	Color3.fromRGB(150, 72, 255), Color3.fromRGB(255, 48, 64) }
local FONT_TECH, FONT_SIGN, FONT_CODE, FONT_ARC = Enum.Font.Michroma, Enum.Font.GothamBlack, Enum.Font.Code, Enum.Font.Arcade

local screenSet = tracked("CityScreen")
local screenState = {}

local function label(parent, name, size, pos, font, color)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextColor3 = color
	t.TextScaled = true
	t.Text = ""
	t.Parent = parent
	return t
end

local function startScreen(face)
	local gui = face:FindFirstChild("Screen")
	local content = gui and gui:FindFirstChild("Content")
	if not content then
		return nil
	end
	local fb = content:FindFirstChild("Fallback")
	if fb then
		fb.Visible = false
	end
	local root = Instance.new("Frame")
	root.Name = "AmbientAnim"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	local grad = Instance.new("UIGradient")
	grad.Rotation = 35
	grad.Parent = root
	local st = { face = face, root = root, grad = grad, fb = fb, playlist = face:GetAttribute("Playlist") or "ads", slide = 0, nextAt = 0,
		phase = rng:NextNumber(0, 10) }
	st.title = label(root, "Title", UDim2.fromScale(0.92, 0.42), UDim2.fromScale(0.04, 0.1), FONT_SIGN, Color3.new(1, 1, 1))
	st.sub = label(root, "Sub", UDim2.fromScale(0.92, 0.22), UDim2.fromScale(0.04, 0.54), FONT_TECH, Color3.fromRGB(225, 236, 255))
	local bar = Instance.new("Frame")
	bar.Name = "TickerBar"
	bar.Size = UDim2.fromScale(1, 0.15)
	bar.Position = UDim2.fromScale(0, 0.85)
	bar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Parent = root
	st.ticker = label(bar, "Ticker", UDim2.fromScale(3, 1), UDim2.fromScale(1, 0), FONT_CODE, Color3.fromRGB(255, 168, 28))
	st.ticker.TextXAlignment = Enum.TextXAlignment.Left
	st.ticker.Text = table.concat(NEWS, "   ◆   ")
	root.Parent = content
	return st
end

local function stopScreen(st)
	if st.root then
		st.root:Destroy()
	end
	if st.fb and st.fb.Parent then
		st.fb.Visible = true
	end
end

local function setSlide(st, now)
	st.slide += 1
	local pl = st.playlist
	local c1, c2
	if pl == "news" then
		st.title.Font = FONT_TECH
		st.title.Text = "速報 NEWS"
		st.sub.Text = NEWS[(st.slide % #NEWS) + 1]
		c1, c2 = Color3.fromRGB(120, 10, 20), Color3.fromRGB(20, 8, 12)
	elseif pl == "idol" then
		st.title.Font = FONT_SIGN
		st.title.Text = (st.slide % 2 == 0) and "少女スター" or "SHOJO STAR ★"
		st.sub.Text = ({ "LIVE TONIGHT ★", "NEW SINGLE 「ネオン」", "♥ ♥ ♥" })[(st.slide % 3) + 1]
		c1, c2 = Color3.fromRGB(220, 60, 150), Color3.fromRGB(60, 20, 90)
	elseif pl == "glitch" or pl == "kanji" then
		st.title.Font = (pl == "glitch") and FONT_ARC or FONT_SIGN
		st.title.Text = WORDS[rng:NextInteger(1, #WORDS)]
		st.sub.Text = (pl == "glitch") and "ERR_0x" .. string.format("%04X", rng:NextInteger(0, 65535)) or ""
		local n = NEONS[rng:NextInteger(1, #NEONS)]
		c1, c2 = n:Lerp(Color3.new(0, 0, 0), 0.55), Color3.fromRGB(6, 6, 12)
		st.title.TextColor3 = n:Lerp(Color3.new(1, 1, 1), 0.4)
	elseif pl == "station" then
		local nt = nextTrains(now)
		st.title.Font = FONT_TECH
		st.title.Text = "青井線 AOI LINE"
		st.sub.Text = string.format("南行 SOUTH %d:%02d   北行 NORTH %d:%02d", nt.south // 60, math.floor(nt.south % 60), nt.north // 60,
			math.floor(nt.north % 60))
		c1, c2 = Color3.fromRGB(20, 60, 160), Color3.fromRGB(6, 12, 30)
	else
		local ad = ADS[((st.slide + math.floor(st.phase)) % #ADS) + 1]
		st.title.Font = FONT_SIGN
		st.title.Text = ad[1]
		st.sub.Text = ad[2] .. "  " .. ad[3]
		c1, c2 = ad[4], Color3.fromRGB(8, 8, 14)
		st.title.TextColor3 = Color3.new(1, 1, 1)
	end
	st.grad.Color = ColorSequence.new(c1, c2)
	st.nextAt = now + ((pl == "glitch") and rng:NextNumber(0.6, 1.6) or ((pl == "station") and 1 or rng:NextNumber(4.5, 6.5)))
end

local function animateScreen(st, now)
	if now >= st.nextAt then
		setSlide(st, now)
	end
	local u = (now * 0.06 + st.phase) % 1
	st.ticker.Position = UDim2.fromScale(1 - u * 4, 0)
	st.grad.Offset = Vector2.new(math.sin(now * 0.5 + st.phase) * 0.25, 0)
	if st.playlist == "glitch" then
		st.title.Position = UDim2.fromScale(0.04 + (rng:NextNumber() < 0.1 and rng:NextNumber(-0.03, 0.03) or 0), 0.1)
	elseif st.playlist == "idol" then
		st.title.Rotation = math.sin(now * 3) * 2
	end
end

local function updateScreens(cp, now)
	local near = {}
	for face in pairs(screenSet) do
		if face:IsA("BasePart") and face.Parent then
			local d = (face.Position - cp).Magnitude
			local gui = face:FindFirstChild("Screen")
			local pl = face:GetAttribute("Playlist")
			local board = type(pl) == "string" and string.sub(pl, 1, 6) == "board_"
			if d < 600 and gui and gui.Enabled and not isBroken(face) and not board then
				table.insert(near, { face, d })
			end
		end
	end
	table.sort(near, function(a, b)
		return a[2] < b[2]
	end)
	local keep = {}
	for i = 1, math.min(8, #near) do
		keep[near[i][1]] = true
	end
	for face, st in pairs(screenState) do
		if not keep[face] or not face.Parent then
			stopScreen(st)
			screenState[face] = nil
		end
	end
	for face in pairs(keep) do
		if not screenState[face] then
			local st = startScreen(face)
			if st then
				screenState[face] = st
				setSlide(st, now)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- FLICKER + HOLO
---------------------------------------------------------------------------------------------------------------------
local flickSet = tracked("CityFlicker")
local flickBusy, flickCount = {}, 0
local function flicker(p)
	flickBusy[p] = true
	flickCount += 1
	task.spawn(function()
		local orig = p.Color
		local dim = orig:Lerp(Color3.new(0, 0, 0), 0.85)
		for _ = 1, rng:NextInteger(2, 5) do
			if not p.Parent then
				break
			end
			p.Color = dim
			task.wait(rng:NextNumber(0.04, 0.14))
			p.Color = orig
			task.wait(rng:NextNumber(0.03, 0.16))
		end
		if p.Parent then
			p.Color = orig
		end
		flickBusy[p] = nil
		flickCount -= 1
	end)
end
local function updateFlicker(cp, dt)
	for p in pairs(flickSet) do
		if flickCount >= 30 then
			break
		end
		if not flickBusy[p] and p:IsA("BasePart") and p.Parent and (p.Position - cp).Magnitude < 300 then
			local rate = p:GetAttribute("Rate") or 0.3
			if rng:NextNumber() < rate * dt * 0.5 then
				flicker(p)
			end
		end
	end
end

local holoSet = tracked("CityHolo")
local holoBase, holoNear = {}, {}
local function updateHoloNear(cp)
	local list = {}
	for p in pairs(holoSet) do
		if p:IsA("BasePart") and p.Parent and (p.Position - cp).Magnitude < 400 then
			table.insert(list, p)
			if not holoBase[p] then
				holoBase[p] = { cf = p.CFrame, tr = p.Transparency, ph = rng:NextNumber(0, 6) }
			end
		end
	end
	local nowSet = {}
	for i = 1, math.min(60, #list) do
		nowSet[list[i]] = true
	end
	for p in pairs(holoNear) do
		if not nowSet[p] and holoBase[p] and p.Parent and not isBroken(p) then
			p.CFrame = holoBase[p].cf
			p.Transparency = holoBase[p].tr
		end
	end
	holoNear = nowSet
end
local function animateHolos(t)
	for p in pairs(holoNear) do
		local b = holoBase[p]
		if b and p.Parent and not isBroken(p) then
			local spin = p:GetAttribute("Spin") or 0
			local pulse = p:GetAttribute("Pulse") or 0
			if spin ~= 0 then
				p.CFrame = b.cf * CFrame.Angles(0, math.rad(spin) * t, 0)
			end
			if pulse > 0 then
				p.Transparency = math.clamp(b.tr + pulse * 0.5 * (1 + math.sin(t * 2.4 + b.ph)), 0, 0.95)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- LOOPS
---------------------------------------------------------------------------------------------------------------------
local slow, mid = 0, 0
RunService.RenderStepped:Connect(function(dt)
	local cp = camPos()
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	-- rain follows the camera
	rain.CFrame = CFrame.new(cp + V3(0, 55, 0))
	rainRate += (rainTarget - rainRate) * math.min(1, dt * 2)
	rainPE.Rate = rainRate
	-- drones
	for _, d in ipairs(drones) do
		if d.shown then
			local cf = droneCF(d, now)
			local cfs = {}
			for i, o in ipairs(d.offs) do
				cfs[i] = cf * o
			end
			workspace:BulkMoveTo(d.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			local blink = (t * 1.6 + d.bob) % 1 < 0.5
			d.parts[2].Transparency = blink and 0 or 0.85
			d.parts[3].Transparency = blink and 0.85 or 0
		end
	end
	updateTrain(now, cp, dt)
	for _, st in pairs(screenState) do
		animateScreen(st, now)
	end
	animateHolos(t)
	mid += dt
	if mid >= 0.3 then
		updateFlicker(cp, mid)
		mid = 0
		local hit = workspace:Raycast(cp + V3(0, 1, 0), V3(0, 150, 0), rayParams)
		rainTarget = hit and 0 or RAIN_RATE
		for _, d in ipairs(drones) do
			local show = (droneCF(d, now).Position - cp).Magnitude < 400
			if show ~= d.shown then
				d.model.Parent = show and FX or nil
				d.shown = show
			end
		end
	end
	slow += dt
	if slow >= 1 then
		slow = 0
		refreshRayFilter()
		updateSteam(cp)
		updateScreens(cp, now)
		updateHoloNear(cp)
	end
end)
refreshRayFilter()
