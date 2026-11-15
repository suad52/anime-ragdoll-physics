--!nocheck
-- StarterPlayerScripts.SettingsEffects (2026-11-11, "wiki extras"): the settings that are EFFECTS, not menu rows.
-- SettingsMenu mirrors every setting to a LOCAL player attribute Opt_<key>; this script reads them:
--   camFollow  the camera's subject is the head (not while shift lock or headcam is on)
--   headcam    (Fun Filters) LockFirstPerson with the camera on the head and the body left visible
--   sens       UserInputService.MouseDeltaSensitivity
--   region     a label top right: the server's region (workspace attribute ServerRegion) and your ping
--   blood      a red burst and splats where any body is KO'd; bloodbath (Fun Filters) keeps them for minutes
--   ragdollSfx thuds when a ragdolled body's limbs slam into something (velocity drops sharply)
--   heavyFx    off = new ParticleEmitters keep 35% of their rate and 60% of their lifetime
--   voice      SoundService.SettingsVoice volume (emote sounds, text-to-speech)
--   tts        nearby players' chat read aloud (AudioTextToSpeech, a random voice per player per life)
--   music      SoundService.SettingsMusic: a city playlist, a duel playlist while the player attribute InDuel is set,
--              a winter track with the JOLLY weather. Roblox-licensed tracks only (DistroKid / APM catalogues).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Kits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))

local function opt(key, default)
	local v = player:GetAttribute("Opt_" .. key)
	if v == nil then
		return default
	end
	return v
end
local function fun()
	return player:GetAttribute("Perk_FunFilters") == true
end
local function group(name, vol)
	local g = SoundService:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = vol or 1
		g.Parent = SoundService
	end
	return g
end
local SFX = group("SettingsSFX")
local VOICE = group("SettingsVoice")
local MUSIC = group("SettingsMusic")

local fxFolder = Instance.new("Folder")
fxFolder.Name = "SettingsEffectsFX"
fxFolder.Parent = workspace

---------------------------------------------------------------------------------------------------------------------
-- HUD: the region / ping label
local hud = Instance.new("ScreenGui")
hud.Name = "SettingsHud"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 8
hud.Parent = playerGui
local regionLbl = Instance.new("TextLabel")
regionLbl.Name = "Region"
regionLbl.AnchorPoint = Vector2.new(1, 0)
regionLbl.Position = UDim2.new(1, -14, 0, 86)
regionLbl.Size = UDim2.fromOffset(320, 18)
regionLbl.BackgroundTransparency = 1
regionLbl.TextXAlignment = Enum.TextXAlignment.Right
regionLbl.TextScaled = true
regionLbl.FontFace = Kits.FONT_PUNCH
regionLbl.TextColor3 = Color3.new(1, 1, 1)
regionLbl.Visible = false
regionLbl.Parent = hud
local rs = Instance.new("UIStroke")
rs.Color = Kits.INK
rs.Thickness = 1.5
rs.Parent = regionLbl

task.spawn(function()
	while true do
		local on = opt("region", false) == true
		regionLbl.Visible = on
		if on then
			local ping = 0
			pcall(function()
				ping = math.floor(player:GetNetworkPing() * 1000 + 0.5)
			end)
			local reg = workspace:GetAttribute("ServerRegion")
			regionLbl.Text = (reg and ("SERVER: " .. string.upper(tostring(reg)) .. "  -  ") or "") .. "PING " .. ping .. " MS"
		end
		task.wait(1)
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- CAMERA: follow the head / headcam / sensitivity
local followSet = false
local headcamWas = false
local HEAD_ATTS = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }
local function isHeadPart(p)
	if p.Name == "Head" then
		return true
	end
	if p.Parent and p.Parent:IsA("Accessory") then
		for _, a in ipairs(p:GetChildren()) do
			if a:IsA("Attachment") and HEAD_ATTS[a.Name] then
				return true
			end
		end
	end
	return false
end

RunService:BindToRenderStep("SettingsCamBefore", Enum.RenderPriority.Camera.Value - 2, function()
	local cam = workspace.CurrentCamera
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (cam and hum and head and root) then
		return
	end
	local headcam = fun() and opt("headcam", false) == true
	-- HEADCAM
	if headcam then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		local want = (head.CFrame * CFrame.new(0, 0.25, -0.55)).Position
		local base = root.Position + Vector3.new(0, 1.5, 0)
		hum.CameraOffset = root.CFrame:VectorToObjectSpace(want - base)
		headcamWas = true
	elseif headcamWas then
		headcamWas = false
		player.CameraMode = Enum.CameraMode.Classic
		hum.CameraOffset = Vector3.zero
	end
	-- CAMERA FOLLOW
	local follow = opt("camFollow", false) == true and not headcam and player:GetAttribute("OptShiftLock") ~= true
	if follow then
		if cam.CameraSubject == hum then
			cam.CameraSubject = head
			followSet = true
		end
	elseif followSet then
		if cam.CameraSubject == head then
			cam.CameraSubject = hum
		end
		followSet = false
	end
end)
-- headcam: the camera module hides the body in first person; show everything but the head again
RunService:BindToRenderStep("SettingsCamAfter", Enum.RenderPriority.Camera.Value + 5, function()
	if not headcamWas then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.LocalTransparencyModifier > 0 and not isHeadPart(p) then
			p.LocalTransparencyModifier = 0
		end
	end
end)

local function applySens()
	UserInputService.MouseDeltaSensitivity = tonumber(opt("sens", 1)) or 1
end
player:GetAttributeChangedSignal("Opt_sens"):Connect(applySens)
applySens()

local function applyVoice()
	VOICE.Volume = tonumber(opt("voice", 1)) or 1
end
player:GetAttributeChangedSignal("Opt_voice"):Connect(applyVoice)
applyVoice()

---------------------------------------------------------------------------------------------------------------------
-- BLOOD: a red burst + splats on the ground where a body is KO'd
local SPLAT_LIFE, SPLAT_LIFE_BATH, MAX_SPLATS = 12, 150, 90
local splats = {}
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function dropSplat(pos, size, life)
	if #splats >= MAX_SPLATS then
		local old = table.remove(splats, 1)
		if old then
			old:Destroy()
		end
	end
	local p = Instance.new("Part")
	p.Name = "BloodSplat"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.06, size, size)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90))
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(math.random(70, 108), 5, 9) -- (2026-11-14) the same dark blood as Sandbox.Gore
	p.Transparency = 0.12
	p.Parent = fxFolder
	table.insert(splats, p)
	task.delay(life, function()
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			task.wait(1.6)
			p:Destroy()
			local i = table.find(splats, p)
			if i then
				table.remove(splats, i)
			end
		end
	end)
end

local bled = setmetatable({}, { __mode = "k" })
local function bleed(model)
	if bled[model] or opt("blood", true) ~= true then
		return
	end
	bled[model] = true
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - torso.Position).Magnitude > 220 then
		return
	end
	local life = (fun() and opt("bloodbath", false) == true) and SPLAT_LIFE_BATH or SPLAT_LIFE
	-- the burst
	local a = Instance.new("Attachment")
	a.Position = torso.Position -- (Terrain sits at the origin, so Position is world space)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(112, 5, 9), Color3.fromRGB(54, 3, 6))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(10, 18)
	e.SpreadAngle = Vector2.new(70, 70)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = a
	a.Parent = workspace.Terrain
	e:Emit(26)
	Debris:AddItem(a, 2)
	-- splats on whatever is below the body
	rayParams.FilterDescendantsInstances = { model, fxFolder }
	local hit = workspace:Raycast(torso.Position, Vector3.new(0, -14, 0), rayParams)
	if hit then
		dropSplat(hit.Position, math.random(30, 46) / 10, life)
		for _ = 1, math.random(3, 5) do
			local off = Vector3.new(math.random(-35, 35) / 10, 0, math.random(-35, 35) / 10)
			local h2 = workspace:Raycast(torso.Position + off + Vector3.new(0, 2, 0), Vector3.new(0, -16, 0), rayParams)
			if h2 then
				dropSplat(h2.Position, math.random(6, 16) / 10, life)
			end
		end
	end
end

local function watchHumanoid(hum)
	if not hum then
		return
	end
	local model = hum.Parent
	hum.Died:Connect(function()
		bleed(model)
	end)
	hum.HealthChanged:Connect(function(h)
		if h <= 0 then
			bleed(model)
		end
	end)
end
local function watchModel(m)
	local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 10)
	watchHumanoid(hum)
end
for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
	task.spawn(watchModel, m)
end
CollectionService:GetInstanceAddedSignal("RagdollNPC"):Connect(function(m)
	task.spawn(watchModel, m)
end)
local function watchPlayer(p)
	if p.Character then
		task.spawn(watchModel, p.Character)
	end
	p.CharacterAdded:Connect(function(c)
		task.spawn(watchModel, c)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	watchPlayer(p)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------------------------------------------------------
-- RAGDOLL SOUNDS: a ragdolled body's limb that was flying and suddenly stops made an impact
local THUDS = { "rbxassetid://9113480915", "rbxassetid://9113480917" } -- Pro Sound Effects "Body Fall Thud 1 / 2"
local LIMBS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerLeg", "RightLowerLeg", "Torso" }
local lastSpeed = setmetatable({}, { __mode = "k" })
local lastThud = setmetatable({}, { __mode = "k" })
local thudsLive = 0
local function thud(part, strength)
	if thudsLive >= 6 then
		return
	end
	thudsLive += 1
	local a = Instance.new("Attachment")
	a.Position = part.Position
	local s = Instance.new("Sound")
	s.SoundId = THUDS[math.random(#THUDS)]
	s.Volume = math.clamp(strength / 60, 0.25, 1)
	s.PlaybackSpeed = 0.9 + math.random() * 0.25
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 120
	s.SoundGroup = SFX
	s.Parent = a
	a.Parent = workspace.Terrain
	s:Play()
	task.delay(1.5, function()
		thudsLive -= 1
		a:Destroy()
	end)
end
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 / 20 then
		return
	end
	acc = 0
	if opt("ragdollSfx", true) ~= true then
		return
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	local now = os.clock()
	local bodies = CollectionService:GetTagged("RagdollNPC")
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(bodies, p.Character)
		end
	end
	for _, m in ipairs(bodies) do
		if m:GetAttribute("Ragdolled") == true then
			local rootPart = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("LowerTorso")
			if rootPart and (rootPart.Position - camPos).Magnitude < 150 then
				for _, n in ipairs(LIMBS) do
					local limb = m:FindFirstChild(n)
					if limb and limb:IsA("BasePart") then
						local sp = limb.AssemblyLinearVelocity.Magnitude
						local was = lastSpeed[limb] or 0
						lastSpeed[limb] = sp
						if was > 22 and sp < was * 0.35 and (not lastThud[m] or now - lastThud[m] > 0.22) then
							lastThud[m] = now
							thud(limb, was)
						end
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- HEAVY EFFECTS off: new particle emitters are thinned out
local function thin(e)
	if opt("heavyFx", true) ~= false or e:GetAttribute("SettingsThinned") then
		return
	end
	if e:IsDescendantOf(fxFolder) or (workspace.CurrentCamera and e:IsDescendantOf(workspace.CurrentCamera)) then
		return -- our own blood / weather
	end
	e:SetAttribute("SettingsThinned", true)
	e.Rate = e.Rate * 0.35
	local lt = e.Lifetime
	e.Lifetime = NumberRange.new(lt.Min * 0.6, lt.Max * 0.6)
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ParticleEmitter") then
		task.defer(thin, d) -- after the creating code set its rate / lifetime
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- TEXT TO SPEECH: nearby players' chat, read aloud
local VOICES = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }
local voiceOf = {} -- [userId] = { char = character, id = voice }
local ttsLive = 0
local function voiceFor(p)
	local v = voiceOf[p.UserId]
	if not v or v.char ~= p.Character then
		v = { char = p.Character, id = VOICES[math.random(#VOICES)], pitch = 0.85 + math.random() * 0.35 }
		voiceOf[p.UserId] = v
	end
	return v
end
local function speak(p, text)
	if ttsLive >= 3 then
		return
	end
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	local cam = workspace.CurrentCamera
	if not (head and cam) then
		return
	end
	local dist = (head.Position - cam.CFrame.Position).Magnitude
	if dist > 80 then
		return
	end
	text = text:gsub("<[^>]+>", ""):sub(1, 140)
	if text:match("^%s*$") then
		return
	end
	local v = voiceFor(p)
	local ok, err = pcall(function()
		local tts = Instance.new("AudioTextToSpeech")
		tts.Text = text
		tts.VoiceId = v.id
		tts.Pitch = v.pitch
		tts.Volume = math.clamp(1.4 - dist / 80, 0.3, 1.2) * VOICE.Volume
		local out = Instance.new("AudioDeviceOutput")
		local w = Instance.new("Wire")
		w.SourceInstance = tts
		w.TargetInstance = out
		tts.Parent = SoundService
		out.Parent = tts
		w.Parent = tts
		ttsLive += 1
		tts:Play()
		task.delay(math.clamp(#text * 0.09 + 1.5, 2, 15), function()
			ttsLive -= 1
			tts:Destroy()
		end)
	end)
	if not ok then
		warn("[SettingsEffects] text to speech: " .. tostring(err))
	end
end
TextChatService.MessageReceived:Connect(function(msg)
	if opt("tts", false) ~= true or not msg.TextSource then
		return
	end
	local p = Players:GetPlayerByUserId(msg.TextSource.UserId)
	if p then
		task.spawn(speak, p, msg.Text or "")
	end
end)

---------------------------------------------------------------------------------------------------------------------
-- MUSIC
local PLAYLISTS = {
	city = { 110131517191895, 79832040150112, 96705693945205, 89814418764617 }, -- DistroKid: Neural Link Established, Signal Under Load, Kintsugi Signal, Beyond the Train Tracks
	duel = { 9048541013, 97549415332187, 100302485669333 }, -- APM "Battleground", DistroKid "HUNTING", "City Center Lockdown"
	jolly = { 123206152218485 }, -- DistroKid "Midnight Snowdome"
}
local BASE_VOL = 0.3 -- (2026-11-12, owner: background audio that isn't overbearing) was 0.45
local track = Instance.new("Sound")
track.Name = "SettingsMusicTrack"
track.SoundGroup = MUSIC
track.Volume = BASE_VOL
track.Parent = SoundService
local mode, index = nil, 0
local function wantMode()
	if player:GetAttribute("InDuel") then
		return "duel"
	end
	if fun() and opt("weather", "") == "jolly" then
		return "jolly"
	end
	return "city"
end
local switching = false
local function playNext(newMode)
	if switching then
		return
	end
	switching = true
	if track.IsPlaying then
		TweenService:Create(track, TweenInfo.new(1), { Volume = 0 }):Play()
		task.wait(1)
	end
	if newMode ~= mode then
		mode = newMode
		index = math.random(#PLAYLISTS[mode])
	else
		index = index % #PLAYLISTS[mode] + 1
	end
	track:Stop()
	track.SoundId = "rbxassetid://" .. string.format("%d", PLAYLISTS[mode][index])
	track.TimePosition = 0
	track.Volume = 0
	track:Play()
	TweenService:Create(track, TweenInfo.new(1.5), { Volume = BASE_VOL }):Play()
	switching = false
end
track.Ended:Connect(function()
	task.spawn(playNext, wantMode())
end)
local function applyMusic()
	MUSIC.Volume = tonumber(opt("music", 1)) or 1
end
player:GetAttributeChangedSignal("Opt_music"):Connect(applyMusic)
applyMusic()
task.spawn(function()
	task.wait(3)
	while true do
		local want = wantMode()
		if want ~= mode or not track.IsPlaying then
			playNext(want)
		end
		task.wait(1)
	end
end)

-- Studio test hook
if RunService:IsStudio() then
	local ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.OnInvoke = function(cmd, a)
		if cmd == "bleed" and a then
			bled[a] = nil
			bleed(a)
			return #splats
		elseif cmd == "speak" then
			speak(player, tostring(a or "testing one two three"))
			return ttsLive
		elseif cmd == "state" then
			return { splats = #splats, music = mode, track = track.SoundId, playing = track.IsPlaying, loaded = track.IsLoaded,
				sens = UserInputService.MouseDeltaSensitivity, voice = VOICE.Volume, musicVol = MUSIC.Volume, region = regionLbl.Visible and regionLbl.Text or "",
				camSubject = workspace.CurrentCamera and workspace.CurrentCamera.CameraSubject and workspace.CurrentCamera.CameraSubject.Name or "",
				cameraMode = player.CameraMode.Name }
		end
		return nil
	end
	ctl.Parent = script
end
