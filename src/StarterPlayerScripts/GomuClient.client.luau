--!nocheck
local TITLE_Y = 0.185 -- move-name banner height (screen scale); see the HUD title block
-- GomuClient: input, ability bar, camera, local movement, the rubber passive and the playback router of the Gomu kit
-- (LUFFY): the M1 stretch-punch string, Gatling (Q), Rocket (E), Gear Third Elephant Gun (R) and Gear Fifth (G, the
-- ultimate; inside its 15 s mode G = Bajrang Gun). The server (ServerScriptService.GomuServer) is authoritative.
-- Built from a copy of the Ichigo kit's scaffold with the sword / idle carry / reiatsu passive removed: the helpers,
-- the camera (shakes, lean, the scripted shot), the title card (ULT ONLY here: Gear5 / Drums / Laugh / Bajrang), the
-- edge vignette and root / mover / float are the template's code. This script owns the HUD, the camera, the local
-- body (Passive + Mode movement multipliers), the PvP Knockback handler (it runs whatever kit the local player holds),
-- the rubber passive (S.boing on hard landings) and hands every broadcast to the move modules in GomuKit.Client
-- (M1 / Gatling / Rocket / Elephant / Gear5) through the `ctx` table built below (luffy/CONTRACT.md section 7.3).
-- CAST TEXT RULE: ctx.showTitle / ctx.callout / ctx.tally only draw for the ultimate (Gear5 / Drums / Laugh / Bajrang).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("GomuKit")
local CFG = require(Kit:WaitForChild("Config"))
local Clips = require(Kit:WaitForChild("Clips"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local GojoClientFolder = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local Animator = require(GojoClientFolder:WaitForChild("ProceduralAnimator"))
local FX = require(GojoClientFolder:WaitForChild("GojoFX"))
-- (2026-11-11) the owner: "have the option to have keybinds". Every key in CFG.Keys is the action's DEFAULT key;
-- Keybinds maps the physical key the player pressed back to it and labels the chips with the bound key
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

-- the kit palette, plus the template's colour names (the HUD code below was written against them)
local PAL = {}
for k, v in pairs(CFG.Palette or {}) do
	PAL[k] = v
end
do
	local C = Color3.fromRGB
	local function alias(name, src, fallback)
		if PAL[name] == nil then
			PAL[name] = PAL[src] or fallback
		end
	end
	alias("Straw", "Straw", C(244, 206, 92))
	alias("Vest", "Vest", C(205, 28, 36))
	alias("Ink", "Ink", C(18, 14, 18))
	alias("Reiatsu", "Straw", C(244, 206, 92)) -- accents: combo pips, button pings
	alias("Crimson", "SunHot", C(255, 190, 70)) -- the Gear Fifth mode's HUD colour (status, timer, G stroke, edge pulse)
	alias("Ember", "Sun", C(255, 228, 140))
	alias("Black", "Ink", C(18, 14, 18))
	alias("Blood", "StrawDark", C(190, 146, 52))
	alias("Core", "Nika", C(252, 252, 255))
	alias("Frost", "Impact", C(255, 236, 160))
	alias("Robe", "VestDark", C(130, 14, 22))
	alias("Ice", "Straw", C(244, 206, 92))
end
local SND = CFG.Sounds
local PASSIVE = type(CFG.Passive) == "table" and CFG.Passive or {}
local MODE = type(CFG.Mode) == "table" and CFG.Mode or {}
local HUDCFG = type(CFG.HUD) == "table" and CFG.HUD or {}
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local AIR = Enum.Material.Air
local SKILLS = { "M1", "Gatling", "Rocket", "Elephant", "Gear5", "Bajrang" }
local MOVES = { "M1", "Gatling", "Rocket", "Elephant", "Gear5" } -- the Client.<name> modules, loaded after Shared

-- everything this kit draws lives under the shared LocalFX folder, which every kit's raycasts already ignore
local Folder = Instance.new("Folder")
Folder.Name = "Gomu"
Folder.Parent = workspace:WaitForChild("LocalFX", 10) or workspace -- GojoClient makes LocalFX as it starts


-- Client.Shared, filled in once it loads (every use below reads the live table)
local S = {}

-- warnings rate-limited per source, so a broken per-frame layer cannot flood the output
local warnedAt = {}
local function warnLimited(tag, msg)
	local c = os.clock()
	if (warnedAt[tag] or -1e9) + 5 < c then
		warnedAt[tag] = c
		warn("[GomuClient] " .. tag .. ": " .. tostring(msg))
	end
end
local function safe(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		warnLimited(tag, err)
	end
	return ok, err
end

local function now()
	return workspace:GetServerTimeNow()
end

local function myChar()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

local function charOf(userId)
	local p = Players:GetPlayerByUserId(userId or 0)
	return p and p.Character, p
end

local function equipped()
	return player:GetAttribute("Kit") == CFG.KitId
end

local function flat(v, fallback)
	if typeof(v) ~= "Vector3" then
		return fallback or Vector3.new(0, 0, -1)
	end
	local f = v * FLAT
	if f.Magnitude > 1e-3 then
		return f.Unit
	end
	return fallback or Vector3.new(0, 0, -1)
end

local function camFacing(p)
	local d = workspace.CurrentCamera.CFrame.Position - p
	return d.Magnitude > 1e-3 and d.Unit or UP
end

local function camDist(p)
	return (workspace.CurrentCamera.CFrame.Position - p).Magnitude
end

local function cs(a, b)
	if typeof(a) == "ColorSequence" then
		return a
	end
	return ColorSequence.new(a, b or a)
end

-- Gear Fifth: the character attribute Gear5Until is the server time the mode ends (GomuServer.Core writes it)
local function modeLeft(char)
	if typeof(char) ~= "Instance" then
		return 0
	end
	local v = char:GetAttribute("Gear5Until")
	if type(v) ~= "number" then
		return 0
	end
	return math.max(v - now(), 0)
end
local function inMode(char)
	return modeLeft(char) > 0
end

-- `id` is a Config.Sounds key ("Boom", "Hit2" ...) or an asset id (a number, "123" or "rbxassetid://123")
local function resolveSound(id)
	if type(id) == "number" then
		return "rbxassetid://" .. tostring(math.floor(id))
	end
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local v = SND[id]
	if type(v) == "string" then
		return v ~= "" and v or nil
	end
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return string.find(id, "://", 1, true) and id or nil
end

local function sound(id, parent, vol, speed)
	if typeof(parent) ~= "Instance" or not parent.Parent then
		return nil
	end
	local sid = resolveSound(id)
	if not sid then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = sid
	s.Volume = tonumber(vol) or 1
	s.PlaybackSpeed = tonumber(speed) or 1
	s.RollOffMinDistance = 30
	s.RollOffMaxDistance = 400
	s.Parent = parent
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 10)
	return s
end

-- a sound at a point rides its own Attachment on ONE shared invisible anchored host: positional, and no part per
-- sound (the Deku verifiers found 8-second anchor parts piling up per hit)
local soundHost = nil
local function soundAt(id, pos, vol, speed)
	if typeof(pos) ~= "Vector3" or not resolveSound(id) then
		return nil
	end
	if not soundHost or not soundHost.Parent then
		soundHost = FX.anchor(Folder, CFrame.new(), nil)
		soundHost.Name = "GomuSoundHost"
	end
	local a = Instance.new("Attachment")
	a.Name = "SoundAt"
	a.Position = pos
	a.Parent = soundHost
	local s = sound(id, a, vol, speed)
	if not s then
		a:Destroy()
		return nil
	end
	s.Ended:Connect(function()
		a:Destroy()
	end)
	Debris:AddItem(a, 10)
	return s
end

local function castFolder(name, life)
	local f = Instance.new("Folder")
	f.Name = name or "Cast"
	f.Parent = Folder
	Debris:AddItem(f, life or 8)
	return f
end

-- move clips: each one records how long it covers the body (clipUntil), so the idle carry is never (re)started on
-- top of a move clip (a carry started after it would override the move's right arm). Carry-length clips (>= 600 s)
-- are not recorded
local clipUntil = setmetatable({}, { __mode = "k" }) -- [char] = os.clock() until which a move clip runs
local trackChar = setmetatable({}, { __mode = "k" }) -- [track] = char
local function playClip(char, clip, startAt)
	if type(clip) == "string" then
		local name = clip
		clip = Clips[name]
		if type(clip) ~= "table" then
			warnLimited("clip " .. name, "Clips." .. name .. " does not exist")
			return nil
		end
	end
	startAt = math.max(tonumber(startAt) or 0, 0)
	if typeof(char) ~= "Instance" or type(clip) ~= "table" or type(clip.length) ~= "number" or startAt >= clip.length then
		return nil
	end
	local ok, track = pcall(Animator.play, char, clip, { startAt = startAt })
	if not ok then
		warnLimited("playClip", track)
		return nil
	end
	if clip.length < 600 then
		clipUntil[char] = math.max(clipUntil[char] or 0, os.clock() + (clip.length - startAt) + 0.15)
	end
	if type(track) == "table" then
		trackChar[track] = char
	end
	return track
end

-- animation hit-stop: the pose hangs for `secs`, then plays on. Overlapping freezes hold until the last one ends, and
-- each pushes the carry guard (clipUntil) back by its length
local function freeze(track, secs)
	if type(track) ~= "table" then
		return
	end
	secs = math.max(tonumber(secs) or 0.07, 0)
	local clock = os.clock()
	if (track._zFrozenUntil or 0) <= clock then
		local prev = track.speed
		track._zSpeed = (type(prev) == "number" and prev ~= 0) and prev or 1
	end
	local untilT = math.max(track._zFrozenUntil or 0, clock + secs)
	track._zFrozenUntil = untilT
	track.speed = 0
	local char = trackChar[track]
	if char and clipUntil[char] then
		clipUntil[char] += secs
	end
	task.delay(untilT - clock, function()
		if track._zFrozenUntil == untilT then
			track._zFrozenUntil = nil
			track.speed = track._zSpeed or 1
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- body helpers (Shared's versions are used once it loads; these are the GodspeedClient originals)
local LIMBS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}
local function localBodyArc(f, model, color, width)
	local a = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	local b = model:FindFirstChild(LIMBS[math.random(#LIMBS)])
	if a and b and a ~= b and a:IsA("BasePart") and b:IsA("BasePart") then
		FX.bolt(f, a.Position + FX.randUnit() * 0.5, b.Position + FX.randUnit() * 0.5, {
			color = color or PAL.Reiatsu, width = width or 0.06, jag = 0.35, segments = 4, life = 0.09, restrike = 1,
		})
	end
end

local function localGhost(char, color, alpha, life, offset)
	if not char or not char.Parent then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Afterimage"
	local parts = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Archivable then
			local ok, c = pcall(function()
				return d:Clone()
			end)
			if ok and c then
				for _, ch in ipairs(c:GetChildren()) do
					if not ch:IsA("DataModelMesh") then
						ch:Destroy()
					end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Massless = true
				c.Material = Enum.Material.ForceField
				c.Color = color
				c.Transparency = alpha
				if typeof(offset) == "CFrame" then
					c.CFrame = offset * d.CFrame
				elseif typeof(offset) == "Vector3" then
					c.CFrame = CFrame.new(offset) * d.CFrame
				else
					c.CFrame = d.CFrame
				end
				c.LocalTransparencyModifier = 0 -- a vanished / first-person body must not hand its 1 to the copy
				c.Parent = f
				table.insert(parts, c)
			end
		end
	end
	f.Parent = Folder
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, c in ipairs(parts) do
		TweenService:Create(c, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(f, life + 0.1)
	return f
end

local function bodyArc(f, model, color, width)
	return (S.bodyArc or localBodyArc)(f, model, color, width)
end
local function ghost(char, color, alpha, life, offset)
	return (S.ghost or localGhost)(char, color, alpha, life, offset)
end

---------------------------------------------------------------------------------------------------
-- raycast filters: the cursor ignores characters and FX; the camera also ignores NPCs
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local camParams = RaycastParams.new()
camParams.FilterType = Enum.RaycastFilterType.Exclude
local ignoreAt = -1e9
local function refreshIgnore(force)
	local c = os.clock()
	if not force and c - ignoreAt < 0.5 then
		return
	end
	ignoreAt = c
	local base = { Folder }
	for _, n in ipairs({ "KitFX", "FX", "LocalFX", "KitDebris" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(base, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(base, p.Character)
		end
	end
	cursorParams.FilterDescendantsInstances = base
	local cam = table.clone(base)
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(cam, npcs)
	end
	camParams.FilterDescendantsInstances = cam
end

---------------------------------------------------------------------------------------------------
-- ctx.vanish (Shunpo's flash step): every BasePart + Decal of a character (the sword and coat included) drawn with
-- LocalTransparencyModifier 1 for `secs`, re-applied every frame after the camera module (which rewrites the local
-- body's modifiers; the scripted shot defers to it too), then each piece gets back the modifier it had before
local vanished = {} -- [char] = { untilT = os.clock() it reappears, orig = { [piece] = its modifier before } }
local SHOT_MAX = 1.2 -- no scripted shot holds the camera longer than this (CONTRACT §7.2)
local function hidePieces(char, rec)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if rec.orig[d] == nil then
				rec.orig[d] = d.LocalTransparencyModifier
			end
			d.LocalTransparencyModifier = 1
		end
	end
end
local function unvanish(char)
	local rec = char and vanished[char]
	if not rec then
		return
	end
	vanished[char] = nil
	for d, v in pairs(rec.orig) do
		if d.Parent then
			d.LocalTransparencyModifier = v
		end
	end
end
local function vanish(char, secs)
	if typeof(char) ~= "Instance" then
		return
	end
	local rec = vanished[char] or { untilT = 0, orig = {} }
	rec.untilT = math.max(rec.untilT, os.clock() + math.max(tonumber(secs) or 0.15, 0))
	vanished[char] = rec
	hidePieces(char, rec)
end
local function isVanished(char)
	local rec = char and vanished[char]
	return rec ~= nil and rec.untilT > os.clock()
end
local function applyVanish()
	if next(vanished) == nil then
		return
	end
	local clock = os.clock()
	for char, rec in pairs(vanished) do
		if not char.Parent or clock >= rec.untilT then
			unvanish(char)
		else
			hidePieces(char, rec)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- camera: shakes, FOV kicks and the lean, as short timed envelopes summed every frame
local shakes = {}
local leans = {}
local baseFOV, lastFOV -- the FOV underneath our kick, and the value we wrote last frame
local lastShake = nil -- the shake + lean offset applied last frame (undone before the camera module reads the camera)
local shotState = nil -- the running scripted shot (ctx.shot)

local function shake(amp, dur, freq, fov)
	if game:GetService("Players").LocalPlayer:GetAttribute("OptNoShake") then
		return -- Settings menu: switched off
	end
	if not equipped() then
		fov = 0 -- FOV kicks only for this kit's own player; anyone else just feels the shake
	end
	table.insert(shakes, { t0 = os.clock(), amp = amp or 0, dur = math.max(dur or 0.2, 0.01), freq = freq or 22, fov = fov or 0 })
end

local function smoothstep(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
-- up / hold / down weight; nil once the envelope is over
local function envelope(e, attack, hold, release)
	if e < 0 then
		return 0
	end
	if e < attack then
		return smoothstep(e / math.max(attack, 1e-3))
	end
	e -= attack
	if e < hold then
		return 1
	end
	e -= hold
	if e < release then
		return 1 - smoothstep(e / math.max(release, 1e-3))
	end
	return nil
end

-- the view leans (pitch up, drops, FOV) without the player losing control. Only the local caster's own casts
local function lean(o)
	if type(o) ~= "table" or not equipped() then
		return
	end
	table.insert(leans, {
		t0 = os.clock(), pitch = o.pitch or 0, drop = o.drop or 0, fov = o.fov or 0,
		attack = o.attack or 0.1, hold = o.hold or 0, release = o.release or 0.2,
	})
end

-- undo last frame's offset before the camera module runs: it builds each frame from the camera's current look
-- direction, so a rotation left in place would add up into a permanent drift of the player's aim
RunService:BindToRenderStep("GomuCameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = workspace.CurrentCamera
	if lastShake and cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = cam.CFrame * lastShake:Inverse()
	end
	lastShake = nil
end)
RunService:BindToRenderStep("GomuCamera", Enum.RenderPriority.Camera.Value + 2, function()
	pcall(applyVanish) -- after the camera module has rewritten the local body's modifiers this frame
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local t = os.clock()
	local amp, fov, freq, anyFov = 0, 0, 22, false
	local i = 1
	while i <= #shakes do
		local e = shakes[i]
		local x = (t - e.t0) / e.dur
		if x >= 1 then
			table.remove(shakes, i)
		else
			local w = (1 - x) ^ 2
			amp += e.amp * w
			fov += e.fov * w
			freq = e.freq
			anyFov = anyFov or e.fov ~= 0
			i += 1
		end
	end
	local P, D = 0, 0
	i = 1
	while i <= #leans do
		local L = leans[i]
		local w = envelope(t - L.t0, L.attack, L.hold, L.release)
		if not w then
			table.remove(leans, i)
		else
			P += L.pitch * w
			D += L.drop * w
			fov += L.fov * w
			anyFov = anyFov or L.fov ~= 0
			i += 1
		end
	end
	if shotState then
		-- the scripted shot owns the camera and its FOV; no kicks run under it
		baseFOV, lastFOV = nil, nil
		return
	end
	-- the kick rides on whatever FOV the camera has (another kit may be animating it), and is only taken back off if
	-- nobody else has written the FOV since
	if anyFov then
		local cur = cam.FieldOfView
		if not baseFOV or not lastFOV or math.abs(cur - lastFOV) > 1e-3 then
			baseFOV = cur
		end
		cam.FieldOfView = math.clamp(baseFOV + fov, 20, 110)
		lastFOV = cam.FieldOfView
	elseif baseFOV then
		if lastFOV and math.abs(cam.FieldOfView - lastFOV) < 1e-3 then
			cam.FieldOfView = baseFOV
		end
		baseFOV, lastFOV = nil, nil
	end
	if cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local off = nil
	if amp > 0.002 then
		local a, b, c = math.noise(t * freq, 0.3, 1.7), math.noise(1.9, t * freq, 4.1), math.noise(7.3, 2.2, t * freq)
		off = CFrame.new(a * amp, b * amp, 0) * CFrame.Angles(b * amp * 0.03, a * amp * 0.03, c * amp * 0.04)
	end
	if math.abs(P) > 0.01 or D > 0.01 then
		if D > 0.01 then
			-- never through the floor: the drop stops a stud above whatever is under the lens
			refreshIgnore()
			local origin = (cam.CFrame * (off or CFrame.identity)).Position
			local hit = workspace:Raycast(origin, -UP * (D + 1), camParams)
			if hit then
				D = math.max((origin - hit.Position).Magnitude - 1, 0)
			end
		end
		local l = CFrame.new(0, -D, 0) * CFrame.Angles(math.rad(P), 0, 0)
		off = (off or CFrame.identity) * l
	end
	if off then
		cam.CFrame = cam.CFrame * off
		lastShake = off
	end
end)

-- the scripted shot (ctx.shot): Scriptable for `dur` seconds from server time `t0`, then handed back facing the
-- player's own saved look and FOV. spec.path(e, a, base, head) -> camPos (Vector3 or CFrame), lookAt[, fov]
local function stopShot()
	local st = shotState
	if not st then
		return
	end
	shotState = nil
	if st.conn then
		st.conn:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		if st.saved then
			cam.CFrame = st.saved -- the camera module takes its look direction from here
		end
		cam.CameraType = Enum.CameraType.Custom
		if st.fov then
			cam.FieldOfView = st.fov
		end
	end
end

local function shot(spec)
	if type(spec) ~= "table" or type(spec.path) ~= "function" then
		return
	end
	local char = spec.char or player.Character
	if not char or char ~= player.Character then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not hrp or not head then
		return
	end
	local cam = workspace.CurrentCamera
	local saved, fov
	if shotState then
		-- a shot replacing a shot keeps the original hand-back
		saved, fov = shotState.saved, shotState.fov
		if shotState.conn then
			shotState.conn:Disconnect()
		end
		shotState = nil
	else
		saved = cam.CFrame
		if lastShake and cam.CameraType ~= Enum.CameraType.Scriptable then
			saved = saved * lastShake:Inverse()
		end
		fov = cam.FieldOfView
		if baseFOV and lastFOV and math.abs(fov - lastFOV) < 1e-3 then
			fov = baseFOV -- hand back the player's own FOV, not one with a kick on it
		end
	end
	lastShake = nil
	refreshIgnore(true)
	local face = flat(spec.face or hrp.CFrame.LookVector)
	local base = typeof(spec.base) == "CFrame" and spec.base or CFrame.lookAt(hrp.Position, hrp.Position + face)
	local t0 = tonumber(spec.t0) or now()
	local dur = math.clamp(tonumber(spec.dur) or 1, 0.05, SHOT_MAX)
	local cuts = type(spec.cuts) == "table" and spec.cuts or nil
	local st = { saved = saved, fov = fov, cut = 1 }
	if cuts then
		local e0 = now() - t0
		while cuts[st.cut] and cuts[st.cut] <= e0 do
			st.cut += 1
		end
	end
	shotState = st
	cam.CameraType = Enum.CameraType.Scriptable
	local function frame()
		if shotState ~= st then
			return
		end
		local e = now() - t0
		if e >= dur or not head.Parent or not hrp.Parent then
			stopShot()
			return
		end
		e = math.max(e, 0)
		local a = math.clamp(e / dur, 0, 1)
		local hidden = isVanished(char) -- ctx.vanish wins over the shot's un-hiding
		for _, p in ipairs(char:GetDescendants()) do
			if (p:IsA("BasePart") and p.Name ~= "HumanoidRootPart") or p:IsA("Decal") then
				p.LocalTransparencyModifier = hidden and 1 or 0
			end
		end
		local ok, pos, look, fv = pcall(spec.path, e, a, base, head)
		if not ok then
			warnLimited("shot", pos)
			stopShot()
			return
		end
		if typeof(pos) == "CFrame" then
			if typeof(look) ~= "Vector3" then
				look = pos.Position + pos.LookVector * 10
			end
			pos = pos.Position
		end
		if typeof(pos) ~= "Vector3" then
			return
		end
		if typeof(look) ~= "Vector3" then
			look = head.Position
		end
		-- the shot never goes through a wall (Scriptable switches off the camera module's own occlusion)
		local hp = head.Position
		local off = pos - hp
		if off.Magnitude > 0.05 then
			local hit = workspace:Raycast(hp, off, camParams)
			if hit then
				local room = (hit.Position - hp).Magnitude - 0.6
				if room < 4 then
					-- a low angle from inside a crater (or under a lip) would land the lens in his face: lift the shot
					-- over the obstruction instead, keeping its bearing
					local lifted = Vector3.new(off.X, math.max(off.Y, 1.5), off.Z)
					local hit2 = workspace:Raycast(hp, lifted, camParams)
					local room2 = hit2 and ((hit2.Position - hp).Magnitude - 0.6) or lifted.Magnitude
					if room2 > room then
						off, room = lifted, room2
					end
				end
				pos = hp + off.Unit * math.max(math.min(room, off.Magnitude), 1)
			end
		end
		if (look - pos).Magnitude < 1e-3 then
			look = pos + base.LookVector
		end
		cam.CFrame = CFrame.lookAt(pos, look)
		local want = tonumber(fv) or tonumber(spec.fov)
		if want then
			cam.FieldOfView = math.clamp(want, 20, 110)
		end
		if cuts then
			while cuts[st.cut] and e >= cuts[st.cut] do
				st.cut += 1
				FX.flash(typeof(spec.cutColor) == "Color3" and spec.cutColor or PAL.Reiatsu, 0.08, 0.08)
			end
		end
	end
	st.conn = RunService.RenderStepped:Connect(frame)
	frame()
end

---------------------------------------------------------------------------------------------------
-- HUD: the move-name callout (kanji slam, ink brush stroke, two-tone starburst, edge speed lines, a short edge glow,
-- hit tally), the edge vignette and the ability bar. Nothing here covers the middle of the screen: the title sits in
-- the upper third, the speed lines start 62% of the way out, and the vignette lives on the screen edges
local gui = Instance.new("ScreenGui")
gui.Name = "GomuHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- the edge vignette sits on its own layer under every other UI
local vgui = Instance.new("ScreenGui")
vgui.Name = "GomuVignette"
vgui.ResetOnSpawn = false
vgui.IgnoreGuiInset = true
vgui.DisplayOrder = -1
vgui.Parent = gui.Parent

local function uiCorner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 14)
	c.Parent = p
	return c
end
local function uiStroke(p, color, th, tr)
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = th
	st.Transparency = tr or 0
	st.Parent = p
	return st
end
local function uiText(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end
local function darken(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end
local function tween(o, secs, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(secs, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local edges = {}
do
	local function edge(pos, size, rot)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = PAL.Crimson
		f.BackgroundTransparency = 1
		f.Position = pos
		f.Size = size
		f.Parent = vgui
		local g = Instance.new("UIGradient")
		g.Rotation = rot
		g.Transparency = NumberSequence.new(0, 1) -- solid at the screen edge, gone inward
		g.Parent = f
		table.insert(edges, f)
	end
	edge(UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.18), 90)
	edge(UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.18), -90)
	edge(UDim2.fromScale(0, 0), UDim2.fromScale(0.12, 1), 0)
	edge(UDim2.fromScale(0.88, 0), UDim2.fromScale(0.12, 1), 180)
end
-- a pulse of the edge vignette: alpha a (capped at 0.35) fading over dur, in `color` (Crimson by default). A weaker
-- pulse never cuts a stronger one short
local vigFlash = nil -- { t0, a, dur, color }
local function vignette(a, dur, color)
	a = math.clamp(tonumber(a) or 0.3, 0, 0.35)
	dur = math.max(tonumber(dur) or 0.6, 0.05)
	if vigFlash then
		local x = (os.clock() - vigFlash.t0) / vigFlash.dur
		if x < 1 and vigFlash.a * (1 - x) > a then
			return
		end
	end
	vigFlash = { t0 = os.clock(), a = a, dur = dur, color = typeof(color) == "Color3" and color or PAL.Crimson }
end

-- the callout's pieces live in this block; the per-frame HUD reads the title state through TT.
-- FLAIR: every title is a small anime title card, in the move's own colours (Config.Callouts c0 / c1):
--   0.00  the name punches in (1.7 -> 1, Back) and slides home; cut-in bars slice in from both screen edges; the ink
--         brush sweeps under the name with a dry second pass and two bristles; a 32-ray three-tone starburst twists
--         out behind it with two pill-shaped shock rings; speed lines at the screen edges; an edge glow
--   0.02+ the kanji slam down ONE BY ONE (3 -> 0.86 -> 1, 0.045 s apart), each landing jolts the banner
--   land  an echo of the whole kanji blows off, a calligraphy slash sweeps in behind it, the kanji row thumps
--   0.14  ink splatters fly off both ends of the brush stroke
--   0.16  a blade cut slashes across the name: a white edge in a coloured glow, the name splits into two chroma copies
--         that snap back, star glints pop along the cut
--   0.28  a metal shine sweeps across the name
--   1.60  it all lifts and fades (0.45 s)
-- Nothing reaches the middle of the screen or the horizon strip (y 0.3 - 0.45, where the waves fly): the banner sits
-- at TITLE_Y, the starburst rays and rings are clipped above y 0.295, the speed lines start 62% of the way out
local showTitle, callout, bumpTally
local TT = { shakeUntil = 0, shaken = false, jolt = 0, fadeAt = 0, holder = nil }
do
	local function seq(list) -- a NumberSequence from { {t, v}, ... }
		local kp = {}
		for _, v in ipairs(list) do
			table.insert(kp, NumberSequenceKeypoint.new(v[1], v[2]))
		end
		return NumberSequence.new(kp)
	end
	local BURST_Y = TITLE_Y + 0.0225 -- the centre of the title line (holder y 0.65 of its 0.15 height)
	local HORIZON_TOP = 0.295 -- screen-space flair stays above this (the waves fly through y 0.3 - 0.45)

	local titleHolder = Instance.new("Frame")
	titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	-- 0.185, not 0.27: from the gameplay camera the horizon (where Getsuga and every wave fly) sits at ~0.33-0.38,
	-- and the banner at 0.27 hid the crescent for its whole readable flight
	titleHolder.Position = UDim2.fromScale(0.5, TITLE_Y)
	titleHolder.Size = UDim2.fromScale(0.86, 0.15)
	titleHolder.BackgroundTransparency = 1
	titleHolder.ZIndex = 40
	titleHolder.Parent = gui
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = titleHolder

	-- the cut-in bars: two slanted colour bars slicing in from the screen edges at the banner's height, a bright rim
	-- along each, fading toward the middle (they never reach the name)
	local bars = {}
	for i = 1, 2 do
		local b = Instance.new("Frame")
		b.Name = "CutInBar" .. i
		b.AnchorPoint = Vector2.new((i == 1) and 0 or 1, 0.5)
		b.BorderSizePixel = 0
		b.BackgroundTransparency = 1
		b.Rotation = -3
		b.ZIndex = 36
		b.Parent = gui
		local g = Instance.new("UIGradient")
		g.Rotation = (i == 1) and 0 or 180
		g.Transparency = seq({ { 0, 0 }, { 0.55, 0.3 }, { 1, 1 } })
		g.Parent = b
		local rim = Instance.new("Frame")
		rim.Name = "Rim"
		rim.AnchorPoint = Vector2.new(0, (i == 1) and 1 or 0)
		rim.Position = UDim2.fromScale(0, (i == 1) and 1 or 0)
		rim.Size = UDim2.new(1, 0, 0, 2)
		rim.BorderSizePixel = 0
		rim.BackgroundTransparency = 1
		rim.ZIndex = 37
		rim.Parent = b
		local rg = g:Clone()
		rg.Parent = rim
		bars[i] = { f = b, rim = rim }
	end

	-- the ink brush stroke swept under the move name, a dry second pass over it, and two thin bristle strokes
	local brush = Instance.new("Frame")
	brush.Name = "Brush"
	brush.AnchorPoint = Vector2.new(0, 0.5)
	brush.Position = UDim2.fromScale(0.5, 0.66)
	brush.Size = UDim2.fromScale(0, 0.6)
	brush.BorderSizePixel = 0
	brush.BackgroundColor3 = BLACK
	brush.BackgroundTransparency = 1
	brush.Rotation = -2
	brush.ZIndex = 38
	brush.Parent = titleHolder
	local brushGrad = Instance.new("UIGradient")
	brushGrad.Transparency = seq({ -- ragged dry-brush ends
		{ 0, 1 }, { 0.025, 0.6 }, { 0.05, 0.12 }, { 0.08, 0.3 }, { 0.12, 0 }, { 0.86, 0 }, { 0.91, 0.25 }, { 0.95, 0.1 },
		{ 0.98, 0.65 }, { 1, 1 },
	})
	brushGrad.Parent = brush
	local dry = Instance.new("Frame")
	dry.Name = "DryBrush"
	dry.AnchorPoint = Vector2.new(0, 0.5)
	dry.BorderSizePixel = 0
	dry.BackgroundTransparency = 1
	dry.Rotation = 1.5
	dry.ZIndex = 38
	dry.Parent = titleHolder
	local dryGrad = Instance.new("UIGradient")
	dryGrad.Rotation = 90 -- streaky across its height: a brush running out of ink
	dryGrad.Transparency = seq({
		{ 0, 1 }, { 0.1, 0.35 }, { 0.2, 0.85 }, { 0.32, 0.25 }, { 0.45, 0.7 }, { 0.58, 0.2 }, { 0.72, 0.8 }, { 0.84, 0.3 },
		{ 1, 1 },
	})
	dryGrad.Parent = dry
	local bristles = {}
	for i = 1, 2 do
		local b = Instance.new("Frame")
		b.Name = "Bristle" .. i
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.BorderSizePixel = 0
		b.BackgroundTransparency = 1
		b.Rotation = -2
		b.ZIndex = 39
		b.Parent = titleHolder
		local g = Instance.new("UIGradient")
		g.Transparency = seq({ { 0, 1 }, { 0.12, 0.2 }, { 0.75, 0.1 }, { 1, 1 } })
		g.Parent = b
		bristles[i] = b
	end
	-- ink droplets flicked off the ends of the stroke
	local drops = {}
	for i = 1, 12 do
		local d = Instance.new("Frame")
		d.Name = "Ink" .. i
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BorderSizePixel = 0
		d.BackgroundTransparency = 1
		d.ZIndex = 38
		d.Parent = titleHolder
		uiCorner(d, UDim.new(1, 0))
		drops[i] = d
	end

	-- the name, two chroma copies behind it (split apart by the blade cut) and a shine copy on top
	local title = uiText(titleHolder, { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 41 })
	local titleStroke = uiStroke(title, BLACK, 3, 1)
	local titleGrad = Instance.new("UIGradient")
	titleGrad.Rotation = 90
	titleGrad.Parent = title
	local titleA = uiText(titleHolder, { Name = "ChromaA", Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 40 })
	local titleB = uiText(titleHolder, { Name = "ChromaB", Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 40 })
	local shine = uiText(titleHolder, { Name = "Shine", Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 42 })
	local shineGrad = Instance.new("UIGradient")
	shineGrad.Rotation = 15
	shineGrad.Transparency = seq({ { 0, 1 }, { 0.4, 1 }, { 0.5, 0.05 }, { 0.6, 1 }, { 1, 1 } })
	shineGrad.Offset = Vector2.new(-1, 0)
	shineGrad.Parent = shine

	-- the blade cut across the name: a white edge inside a coloured glow, drawn left to right
	local cut = Instance.new("Frame")
	cut.Name = "BladeCut"
	cut.AnchorPoint = Vector2.new(0, 0.5)
	cut.Position = UDim2.fromScale(0.05, 0.64)
	cut.Size = UDim2.new(0, 0, 0, 3)
	cut.Rotation = -7
	cut.BorderSizePixel = 0
	cut.BackgroundColor3 = WHITE
	cut.BackgroundTransparency = 1
	cut.ZIndex = 44
	cut.Parent = titleHolder
	local cutGlow = Instance.new("Frame") -- a sibling under the edge (a child would draw over it)
	cutGlow.Name = "BladeCutGlow"
	cutGlow.AnchorPoint = Vector2.new(0, 0.5)
	cutGlow.Position = UDim2.fromScale(0.05, 0.64)
	cutGlow.Size = UDim2.new(0, 0, 0, 11)
	cutGlow.Rotation = -7
	cutGlow.BorderSizePixel = 0
	cutGlow.BackgroundTransparency = 1
	cutGlow.ZIndex = 43
	cutGlow.Parent = titleHolder
	for _, o in ipairs({ cut, cutGlow }) do
		local g = Instance.new("UIGradient")
		g.Transparency = seq({ { 0, 1 }, { 0.06, 0 }, { 0.82, 0 }, { 1, 1 } })
		g.Parent = o
	end

	-- the kanji: a row of cells that slam down one by one, a calligraphy slash of ink behind them and an echo of the
	-- whole word blown off them once they land
	local kanjiHolder = Instance.new("Frame")
	kanjiHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	kanjiHolder.Position = UDim2.fromScale(0.5, 0.13)
	kanjiHolder.Size = UDim2.fromScale(1, 0.4)
	kanjiHolder.BackgroundTransparency = 1
	kanjiHolder.ZIndex = 41
	kanjiHolder.Parent = titleHolder
	local kanjiScale = Instance.new("UIScale")
	kanjiScale.Parent = kanjiHolder
	local inkSlash = Instance.new("Frame")
	inkSlash.Name = "InkSlash"
	inkSlash.AnchorPoint = Vector2.new(0, 0.5)
	inkSlash.BorderSizePixel = 0
	inkSlash.BackgroundTransparency = 1
	inkSlash.Rotation = -14
	inkSlash.ZIndex = 39
	inkSlash.Parent = titleHolder
	local slashGrad = Instance.new("UIGradient")
	slashGrad.Transparency = seq({ { 0, 1 }, { 0.05, 0.4 }, { 0.14, 0 }, { 0.72, 0 }, { 0.88, 0.35 }, { 1, 1 } })
	slashGrad.Parent = inkSlash
	local slashRim = Instance.new("Frame")
	slashRim.Name = "Rim"
	slashRim.AnchorPoint = Vector2.new(0, 0)
	slashRim.Position = UDim2.fromScale(0, 0)
	slashRim.Size = UDim2.new(1, 0, 0, 2)
	slashRim.BorderSizePixel = 0
	slashRim.BackgroundTransparency = 1
	slashRim.ZIndex = 40
	slashRim.Parent = inkSlash
	slashGrad:Clone().Parent = slashRim
	local kanjiRow = Instance.new("Frame")
	kanjiRow.Name = "Row"
	kanjiRow.Size = UDim2.fromScale(1, 1)
	kanjiRow.BackgroundTransparency = 1
	kanjiRow.ZIndex = 42
	kanjiRow.Parent = kanjiHolder
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 3)
	rowLayout.Parent = kanjiRow
	local cells = {}
	for i = 1, 6 do
		local c = Instance.new("Frame") -- the layout slot (never scaled, so the row never shuffles)
		c.Name = "K" .. i
		c.Size = UDim2.fromScale(1, 1)
		c.BackgroundTransparency = 1
		c.LayoutOrder = i
		c.Visible = false
		c.ZIndex = 42
		c.Parent = kanjiRow
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.DominantAxis = Enum.DominantAxis.Height
		ar.Parent = c
		local inner = Instance.new("Frame") -- what slams: scaled, turned and lifted
		inner.Name = "Glyph"
		inner.AnchorPoint = Vector2.new(0.5, 0.5) -- a UIScale grows from the anchor: slam from the glyph's centre
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromScale(1, 1)
		inner.BackgroundTransparency = 1
		inner.ZIndex = 42
		inner.Parent = c
		local sc = Instance.new("UIScale")
		sc.Parent = inner
		local l = uiText(inner, { Size = UDim2.fromScale(1, 1), Text = "", TextTransparency = 1, ZIndex = 43 })
		local st = uiStroke(l, BLACK, 2, 1)
		cells[i] = { f = c, inner = inner, sc = sc, l = l, st = st }
	end
	local kanjiEcho = uiText(kanjiHolder, { Name = "Echo", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Text = "", TextTransparency = 1, ZIndex = 41 })
	local echoScale = Instance.new("UIScale")
	echoScale.Parent = kanjiEcho
	local titleToken

	-- the starburst: 32 rays in three tones behind the title, thrown out (and twisted) on every title; two pill-shaped
	-- shock rings. Rays that would reach down into the horizon strip are shortened or dropped
	local burst = Instance.new("Frame")
	burst.Name = "Starburst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, BURST_Y)
	burst.Size = UDim2.fromOffset(0, 0)
	burst.BackgroundTransparency = 1
	burst.ZIndex = 37
	burst.Parent = gui
	local burstScale = Instance.new("UIScale")
	burstScale.Parent = burst
	local rays = {}
	for i = 1, 32 do
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.BorderSizePixel = 0
		r.BackgroundTransparency = 1
		r.ZIndex = 37
		r.Parent = burst
		local g = Instance.new("UIGradient")
		g.Transparency = seq({ { 0, 1 }, { 0.3, 0.2 }, { 1, 1 } })
		g.Parent = r
		rays[i] = r
	end
	local rings = {}
	for i = 1, 2 do
		local r = Instance.new("Frame")
		r.Name = "ShockRing" .. i
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.5, BURST_Y)
		r.Size = UDim2.fromScale(0, 0)
		r.BackgroundTransparency = 1
		r.ZIndex = 36
		r.Parent = gui
		uiCorner(r, UDim.new(1, 0))
		rings[i] = { f = r, st = uiStroke(r, WHITE, 3, 1) }
	end
	-- four-point star glints popped along the cut
	local stars = {}
	for i = 1, 6 do
		local h = Instance.new("Frame")
		h.Name = "Glint" .. i
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Size = UDim2.fromOffset(0, 0)
		h.BackgroundTransparency = 1
		h.ZIndex = 45
		h.Parent = gui
		local sc = Instance.new("UIScale")
		sc.Scale = 0
		sc.Parent = h
		local arms = {}
		for j = 1, 2 do
			local a = Instance.new("Frame")
			a.AnchorPoint = Vector2.new(0.5, 0.5)
			a.Position = UDim2.fromScale(0.5, 0.5)
			a.Size = (j == 1) and UDim2.fromOffset(30, 3) or UDim2.fromOffset(3, 30)
			a.BorderSizePixel = 0
			a.BackgroundColor3 = WHITE
			a.ZIndex = 45
			a.Parent = h
			local g = Instance.new("UIGradient")
			g.Rotation = (j == 1) and 0 or 90
			g.Transparency = seq({ { 0, 1 }, { 0.4, 0.2 }, { 0.5, 0 }, { 0.6, 0.2 }, { 1, 1 } })
			g.Parent = a
			arms[j] = a
		end
		stars[i] = { h = h, sc = sc, arms = arms }
	end

	local function popBurst(color, color2, color3, big)
		local info = TweenInfo.new(big and 0.5 or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local final = big and 1.4 or 1.25
		local vpY = math.max(gui.AbsoluteSize.Y, 200)
		local maxDown = math.max(HORIZON_TOP - BURST_Y, 0.02) * vpY / final -- px (before the burst's UIScale)
		for i, r in ipairs(rays) do
			local a = (i - 1) / #rays * TAU + (math.random() - 0.5) * 0.2
			local tone = i % 4 -- 1, 3: long main colour; 2: short second colour; 0: a thin white needle
			local long = tone == 1 or tone == 3
			local base = long and 70 or (tone == 0 and 60 or 95)
			local len = (long and 150 or 90) + math.random() * (long and 150 or 70)
			if tone == 0 then
				len = 120 + math.random() * 160
			end
			if big then
				len *= 1.3
			end
			local sa = math.sin(a)
			-- pointing down the screen (the burst twists +/-7 deg, so take the worse side): keep its far end above
			-- the horizon strip
			local sDown = math.max(math.sin(a - 0.13), math.sin(a + 0.13))
			if sDown > 0.05 then
				len = math.min(len, maxDown / sDown - base)
			end
			if len < 24 then
				r.BackgroundTransparency = 1
				r.Size = UDim2.fromOffset(0, 0)
			else
				local th = long and (4 + math.random() * 4) or (tone == 0 and 1.5 or (2 + math.random() * 2))
				local c = base + len / 2
				r.Position = UDim2.fromOffset(math.cos(a) * c, sa * c)
				r.Size = UDim2.fromOffset(len, th)
				r.Rotation = math.deg(a)
				r.BackgroundColor3 = long and color or (tone == 0 and color3 or color2)
				r.BackgroundTransparency = long and 0 or (tone == 0 and 0.05 or 0.15)
				TweenService:Create(r, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		burst.Rotation = -7
		tween(burst, 0.55, { Rotation = 7 }, Enum.EasingStyle.Quart)
		burstScale.Scale = 0.4
		tween(burstScale, 0.25, { Scale = final }, Enum.EasingStyle.Quart)
		-- the pill rings: wide and short, so they stay above the horizon strip too
		local h = math.max(HORIZON_TOP - BURST_Y, 0.02) * 2
		for i, rg in ipairs(rings) do
			local w = (big and 0.56 or 0.46) * ((i == 1) and 1 or 0.78)
			local hh = h * ((i == 1) and 1 or 0.72)
			rg.f.Size = UDim2.fromScale(w * 0.25, hh * 0.25)
			rg.st.Color = (i == 1) and color or color3
			rg.st.Thickness = big and 5 or 4
			rg.st.Transparency = (i == 1) and 0.1 or 0.25
			local d = (i - 1) * 0.07
			task.delay(d, function()
				tween(rg.f, 0.36, { Size = UDim2.fromScale(w, hh) }, Enum.EasingStyle.Quart)
				tween(rg.st, 0.36, { Transparency = 1, Thickness = 1 })
			end)
		end
	end

	-- the hit tally under the title: "×n", or "×n CUT" (kept above the horizon strip)
	local tallyLabel = uiText(gui, {
		Name = "HitTally", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, TITLE_Y + 0.078), Size = UDim2.fromScale(0.3, 0.036),
		Text = "", TextTransparency = 1, TextColor3 = PAL.Frost, ZIndex = 41,
	})
	local tallyStroke = uiStroke(tallyLabel, Color3.fromRGB(8, 18, 34), 2, 1)
	local tallyScale = Instance.new("UIScale")
	tallyScale.Parent = tallyLabel
	local tally = { id = nil, n = 0, smashed = false }
	function bumpTally(id, add, setTo, smashed)
		if tally.id ~= id then
			tally = { id = id, n = 0, smashed = false }
		end
		tally.n = setTo or (tally.n + (add or 1))
		tally.smashed = tally.smashed or smashed == true
		if tally.n <= 0 then
			return
		end
		tallyLabel.Text = "×" .. tally.n .. (tally.smashed and " CUT" or "")
		tallyLabel.TextTransparency, tallyStroke.Transparency = 0, 0
		tallyLabel.TextColor3 = WHITE
		tween(tallyLabel, 0.25, { TextColor3 = PAL.Frost })
		tallyScale.Scale = 1.5
		tallyLabel.Rotation = (math.random() < 0.5) and -6 or 6
		tween(tallyScale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(tallyLabel, 0.14, { Rotation = 0 })
		local token = {}
		tally.token = token
		task.delay(math.max(TT.fadeAt - os.clock(), 1.2), function()
			if tally.token ~= token then
				return
			end
			local info = TweenInfo.new(0.45)
			TweenService:Create(tallyLabel, info, { TextTransparency = 1 }):Play()
			TweenService:Create(tallyStroke, info, { Transparency = 1 }):Play()
		end)
	end

	-- the ultimate's titles get the big treatment (a longer burst, a heavier brush, wider bars, a title shake)
	local ULT_TITLES = {}
	ULT_TITLES[CFG.Labels.Gear5 or "GEAR FIFTH"] = true
	ULT_TITLES[CFG.Labels.Bajrang or "BAJRANG GUN"] = true
	for _, k in ipairs({ "Gear5", "Drums", "Laugh", "Bajrang" }) do
		local co = CFG.Callouts[k]
		if co and co.text then
			ULT_TITLES[co.text] = true
		end
	end

	-- how much of the holder the brush covers: estimated from the text now, corrected from TextBounds a frame later
	local function brushWidth(text)
		return math.clamp(0.16 + #(text or "") * 0.034, 0.36, 0.96)
	end
	-- the kanji word as single characters (UTF-8 aware; at most 6 cells)
	local function splitChars(s)
		local out = {}
		if type(s) ~= "string" or s == "" then
			return out
		end
		local ok = pcall(function()
			for _, cp in utf8.codes(s) do
				table.insert(out, utf8.char(cp))
			end
		end)
		if not ok or #out == 0 then
			out = { s }
		end
		while #out > #cells do -- too long for the row: the tail rides in the last cell
			out[#out - 1] = out[#out - 1] .. out[#out]
			table.remove(out)
		end
		return out
	end

	local function splatter(token, w, ink, rim, big)
		local n = big and 12 or 8
		for i, d in ipairs(drops) do
			if i > n then
				d.BackgroundTransparency = 1
			else
				local right = i % 2 == 0
				local x0 = right and (0.5 + w / 2 - 0.015) or (0.5 - w / 2 + 0.015)
				local y0 = 0.66 + (math.random() - 0.5) * 0.3
				local sz = 3 + math.random() * (big and 12 or 9)
				local dx = (right and 1 or -1) * (18 + math.random() * (big and 130 or 85))
				local dy = -math.random() * 24 + math.random() * 8
				d.BackgroundColor3 = (math.random() < 0.3) and rim or ink
				d.BackgroundTransparency = 0.05
				d.Position = UDim2.fromScale(x0, y0)
				d.Size = UDim2.fromOffset(sz * 0.4, sz * 0.4)
				tween(d, 0.16 + math.random() * 0.12, {
					Position = UDim2.new(x0, dx, y0, dy), Size = UDim2.fromOffset(sz, sz * (0.7 + math.random() * 0.45)),
				}, Enum.EasingStyle.Quart)
				task.delay(0.55 + math.random() * 0.4, function()
					if titleToken == token then
						tween(d, 0.35, { BackgroundTransparency = 1 })
					end
				end)
			end
		end
	end

	local function popStars(token, c0)
		for i, s in ipairs(stars) do
			task.delay((i - 1) * 0.03, function()
				if titleToken ~= token then
					return
				end
				local x = 0.5 + (math.random() - 0.5) * 0.62
				local y = TITLE_Y + 0.015 + (math.random() - 0.5) * 0.09
				s.h.Position = UDim2.fromScale(x, y)
				s.h.Rotation = math.random(0, 45)
				for j, a in ipairs(s.arms) do
					a.BackgroundColor3 = (i % 2 == 0) and c0 or WHITE
					local L = 18 + math.random() * 22
					a.Size = (j == 1) and UDim2.fromOffset(L, 3) or UDim2.fromOffset(3, L)
				end
				s.sc.Scale = 0
				tween(s.sc, 0.1, { Scale = 1.15 }, Enum.EasingStyle.Back)
				tween(s.h, 0.32, { Rotation = s.h.Rotation + 90 }, Enum.EasingStyle.Quad)
				task.delay(0.12, function()
					tween(s.sc, 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end)
			end)
		end
	end

	function showTitle(text, kanjiText, c0, c1)
		c0 = typeof(c0) == "Color3" and c0 or WHITE
		c1 = typeof(c1) == "Color3" and c1 or PAL.Reiatsu
		text = tostring(text or "")
		local token = {}
		titleToken = token
		local big = ULT_TITLES[text] == true
		local clock = os.clock()
		local kText = type(kanjiText) == "string" and kanjiText or ""
		title.Text, titleA.Text, titleB.Text, shine.Text = text, text, text, text
		kanjiEcho.Text = kText
		kanjiEcho.TextColor3 = c1
		titleGrad.Color = ColorSequence.new(c0, c1)
		local dark = c1:Lerp(BLACK, 0.82)
		local ink = c1:Lerp(BLACK, big and 0.72 or 0.8)
		titleStroke.Color = dark
		-- the name punches in (scale 1.7 -> 1, Back) and slides home from the right
		title.TextTransparency, titleStroke.Transparency = 0, 0
		titleA.TextTransparency, titleB.TextTransparency, shine.TextTransparency = 1, 1, 1
		titleScale.Scale = 1.7
		titleHolder.Rotation = -5
		tween(titleScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(titleHolder, 0.16, { Rotation = 0 })
		title.Position = UDim2.new(0, 90, 0.3, 0)
		tween(title, 0.2, { Position = UDim2.fromScale(0, 0.3) }, Enum.EasingStyle.Quint)

		-- the cut-in bars slice in from the screen edges and hold beside the banner
		local barH = big and 0.05 or 0.034
		for i, b in ipairs(bars) do
			local y = (i == 1) and (TITLE_Y - 0.03) or (TITLE_Y + 0.036)
			local x1 = (i == 1) and 0 or 1
			local x0 = (i == 1) and -0.4 or 1.4
			b.f.BackgroundColor3 = (i == 1) and c1 or c1:Lerp(c0, 0.35)
			b.f.BackgroundTransparency = big and 0.22 or 0.38
			b.f.Size = UDim2.fromScale(big and 0.4 or 0.33, barH)
			b.f.Position = UDim2.fromScale(x0, y)
			b.rim.BackgroundColor3 = c0
			b.rim.BackgroundTransparency = 0.1
			task.delay((i - 1) * 0.05, function()
				if titleToken == token then
					tween(b.f, 0.2, { Position = UDim2.fromScale(x1, y) }, Enum.EasingStyle.Quint)
				end
			end)
		end

		-- the kanji slam down one by one (scale 2.8 -> 0.86, Quad In, then a Back settle), each landing jolts the banner
		local chars = splitChars(kText)
		local dark2 = c1:Lerp(BLACK, 0.7)
		for i, cell in ipairs(cells) do
			local ch = chars[i]
			cell.f.Visible = ch ~= nil
			cell.l.TextTransparency, cell.st.Transparency = 1, 1
			if ch then
				cell.l.Text = ch
				cell.l.TextColor3 = c0:Lerp(c1, 0.4)
				cell.st.Color = dark2
				cell.sc.Scale = 2.8
				cell.inner.Rotation = (i % 2 == 1) and -12 or 12
				cell.inner.Position = UDim2.fromScale(0.5, 0.25)
				task.delay(0.02 + (i - 1) * 0.045, function()
					if titleToken ~= token then
						return
					end
					tween(cell.l, 0.06, { TextTransparency = 0 })
					tween(cell.st, 0.06, { Transparency = 0 })
					tween(cell.sc, 0.08, { Scale = 0.86 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					tween(cell.inner, 0.08, { Rotation = 0, Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					task.delay(0.08, function()
						if titleToken ~= token then
							return
						end
						tween(cell.sc, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
						TT.jolt = math.max(TT.jolt, os.clock() + 0.05)
					end)
				end)
			end
		end
		kanjiEcho.TextTransparency = 1
		kanjiScale.Scale = 1
		kanjiHolder.Rotation = 0
		kanjiHolder.Position = UDim2.fromScale(0.5, 0.13)
		local landT = 0.1 + (math.max(#chars, 1) - 1) * 0.045
		-- the calligraphy slash behind the kanji: sized to the word, swept in as the last kanji lands
		local nC = math.max(#chars, 1)
		local cellW = (titleHolder.AbsoluteSize.Y > 1 and titleHolder.AbsoluteSize.X > 1)
				and (titleHolder.AbsoluteSize.Y * 0.4 / titleHolder.AbsoluteSize.X)
			or 0.06
		local ws = math.clamp(nC * cellW + 0.14, 0.16, 0.6)
		inkSlash.BackgroundColor3 = ink
		inkSlash.BackgroundTransparency = big and 0.08 or 0.16
		inkSlash.Position = UDim2.fromScale(0.5 - ws / 2, 0.14)
		inkSlash.Size = UDim2.fromScale(0, 0.26)
		slashRim.BackgroundColor3 = c1
		slashRim.BackgroundTransparency = 0.15
		task.delay(math.max(landT - 0.06, 0), function()
			if titleToken == token then
				tween(inkSlash, 0.1, { Size = UDim2.fromScale(ws, 0.26) }, Enum.EasingStyle.Quart)
			end
		end)
		task.delay(landT, function()
			if titleToken ~= token then
				return
			end
			kanjiEcho.TextTransparency = 0.3
			echoScale.Scale = 1
			tween(echoScale, 0.32, { Scale = 1.75 })
			tween(kanjiEcho, 0.32, { TextTransparency = 1 })
			kanjiScale.Scale = 1.12
			tween(kanjiScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
			TT.jolt = math.max(TT.jolt, os.clock() + 0.08)
		end)

		-- the ink stroke sweeps in under the name, left to right, a dry pass over it and a bristle above and below
		local w = brushWidth(text)
		local bh = big and 0.72 or 0.6
		brush.BackgroundColor3 = ink
		brush.BackgroundTransparency = big and 0.14 or 0.24
		brush.Position = UDim2.fromScale(0.5 - w / 2, 0.66)
		brush.Size = UDim2.fromScale(0, bh)
		tween(brush, 0.18, { Size = UDim2.fromScale(w, bh) }, Enum.EasingStyle.Quart)
		dry.BackgroundColor3 = c1:Lerp(BLACK, 0.55)
		dry.BackgroundTransparency = 0.3
		dry.Position = UDim2.fromScale(0.5 - w / 2 + 0.02, 0.7)
		dry.Size = UDim2.fromScale(0, bh * 0.75)
		task.delay(0.05, function()
			if titleToken == token then
				tween(dry, 0.2, { Size = UDim2.fromScale(w * 0.92, bh * 0.75) }, Enum.EasingStyle.Quart)
			end
		end)
		for i, b in ipairs(bristles) do
			local off = (i == 1) and -0.4 or 0.42
			local bw = w * (0.55 + math.random() * 0.35)
			b.BackgroundColor3 = (i == 1) and c1 or c0:Lerp(c1, 0.5)
			b.BackgroundTransparency = 0.1
			b.Position = UDim2.new(0.5 - w / 2 + w * math.random() * 0.12, 0, 0.66 + off, 0)
			b.Size = UDim2.new(0, 0, 0, big and 4 or 3)
			task.delay(0.04 * i, function()
				if titleToken == token then
					tween(b, 0.2, { Size = UDim2.new(bw, 0, 0, big and 4 or 3) }, Enum.EasingStyle.Quart)
				end
			end)
		end
		task.delay(0.03, function()
			if titleToken ~= token then
				return
			end
			local hx = titleHolder.AbsoluteSize.X
			local tb = title.TextBounds.X
			if hx > 1 and tb > 1 then
				local w2 = math.clamp(tb / hx + 0.12, 0.3, 1)
				if math.abs(w2 - w) > 0.03 then
					w = w2
					brush.Position = UDim2.fromScale(0.5 - w2 / 2, 0.66)
					tween(brush, 0.15, { Size = UDim2.fromScale(w2, bh) }, Enum.EasingStyle.Quart)
					dry.Position = UDim2.fromScale(0.5 - w2 / 2 + 0.02, 0.7)
					tween(dry, 0.15, { Size = UDim2.fromScale(w2 * 0.92, bh * 0.75) }, Enum.EasingStyle.Quart)
				end
			end
		end)
		-- ink flicked off both ends of the stroke
		task.delay(0.14, function()
			if titleToken == token then
				splatter(token, w, ink, c1, big)
			end
		end)

		-- the blade cut: a white edge slashes across the name, which splits into two chroma copies that snap back
		cut.BackgroundTransparency = 1
		cutGlow.BackgroundTransparency = 1
		cut.Size = UDim2.new(0, 0, 0, big and 4 or 3)
		cutGlow.Size = UDim2.new(0, 0, 0, big and 14 or 11)
		cutGlow.BackgroundColor3 = c1
		task.delay(0.16, function()
			if titleToken ~= token then
				return
			end
			cut.BackgroundTransparency = 0
			cutGlow.BackgroundTransparency = 0.45
			tween(cut, 0.07, { Size = UDim2.new(0.9, 0, 0, big and 4 or 3) }, Enum.EasingStyle.Quad)
			tween(cutGlow, 0.07, { Size = UDim2.new(0.9, 0, 0, big and 14 or 11) }, Enum.EasingStyle.Quad)
			titleA.TextColor3, titleB.TextColor3 = c1, c0:Lerp(WHITE, 0.5)
			titleA.TextTransparency, titleB.TextTransparency = 0.3, 0.45
			titleA.Position = UDim2.new(0, -12, 0.3, -5)
			titleB.Position = UDim2.new(0, 12, 0.3, 5)
			tween(titleA, 0.22, { Position = UDim2.fromScale(0, 0.3), TextTransparency = 1 }, Enum.EasingStyle.Quart)
			tween(titleB, 0.22, { Position = UDim2.fromScale(0, 0.3), TextTransparency = 1 }, Enum.EasingStyle.Quart)
			TT.jolt = math.max(TT.jolt, os.clock() + 0.07)
			popStars(token, c0)
			task.delay(0.13, function()
				if titleToken ~= token then
					return
				end
				tween(cut, 0.28, { BackgroundTransparency = 1, Size = UDim2.new(0.98, 0, 0, 1) })
				tween(cutGlow, 0.28, { BackgroundTransparency = 1 })
			end)
		end)
		-- a metal shine sweeps across the name
		task.delay(0.28, function()
			if titleToken ~= token then
				return
			end
			shine.TextTransparency = 0
			shineGrad.Offset = Vector2.new(-1, 0)
			tween(shineGrad, 0.42, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			task.delay(0.44, function()
				if titleToken == token then
					shine.TextTransparency = 1
				end
			end)
		end)

		popBurst(c1, c0:Lerp(c1, 0.3), c0:Lerp(WHITE, 0.6), big)
		if big then -- the ultimate's titles throw a second burst
			task.delay(0.12, function()
				if titleToken == token then
					popBurst(c0:Lerp(c1, 0.15), c1, WHITE, false)
				end
			end)
		end
		-- the caster's screen: anime speed lines round the EDGES (they start 62% of the way out) and a short edge glow
		pcall(FX.speedLines, big and 0.5 or 0.34, {
			count = big and 34 or 24, color = c1:Lerp(WHITE, 0.35), alpha = big and 0.4 or 0.3, inner = 0.62, thick = 4,
			release = 0.2,
		})
		vignette(big and 0.26 or 0.16, big and 0.7 or 0.45, c1)
		if big then
			TT.shakeUntil = clock + 0.2
		end
		TT.fadeAt = clock + 1.6
		task.delay(1.6, function()
			if titleToken ~= token then
				return
			end
			local info = TweenInfo.new(0.45)
			TweenService:Create(title, info, { TextTransparency = 1 }):Play()
			TweenService:Create(titleStroke, info, { Transparency = 1 }):Play()
			for i, cell in ipairs(cells) do
				if cell.f.Visible then
					TweenService:Create(cell.l, info, { TextTransparency = 1 }):Play()
					TweenService:Create(cell.st, info, { Transparency = 1 }):Play()
					tween(cell.inner, 0.45, { Position = UDim2.fromScale(0.5, 0.15 - 0.1 * (i % 2)), Rotation = (i % 2 == 1) and -6 or 6 })
				end
			end
			tween(titleScale, 0.45, { Scale = 1.06 })
			tween(title, 0.45, { Position = UDim2.new(0, 0, 0.3, -10) })
			tween(brush, 0.4, { BackgroundTransparency = 1 })
			tween(dry, 0.35, { BackgroundTransparency = 1 })
			tween(inkSlash, 0.4, { BackgroundTransparency = 1 })
			tween(slashRim, 0.3, { BackgroundTransparency = 1 })
			for _, b in ipairs(bristles) do
				tween(b, 0.3, { BackgroundTransparency = 1 })
			end
			for i, b in ipairs(bars) do
				local y = (i == 1) and (TITLE_Y - 0.03) or (TITLE_Y + 0.036)
				tween(b.f, 0.4, { BackgroundTransparency = 1, Position = UDim2.fromScale((i == 1) and -0.12 or 1.12, y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tween(b.rim, 0.3, { BackgroundTransparency = 1 })
			end
		end)
	end
	-- a move's callout; `skill` is a Config.Callouts key (Getsuga ... or the mid-cast titles Ban / Kai / Tensa / Zan ...)
	function callout(skill, sub)
		local co = CFG.Callouts[skill]
		if not co then
			if sub or CFG.Labels[skill] then
				showTitle(sub or CFG.Labels[skill], nil, WHITE, PAL.Reiatsu)
			end
			return
		end
		showTitle(sub or co.text or CFG.Labels[skill] or tostring(skill), co.kanji, co.c0, co.c1)
	end
	TT.holder = titleHolder
end

-- the screen flash and the impact frame, capped for the no-white-out rule (DESIGN §11: flash alpha <= 0.25)
local function flash(color, alpha, life)
	local ok, err = pcall(FX.flash, typeof(color) == "Color3" and color or WHITE, math.clamp(tonumber(alpha) or 0.15, 0, 0.25), tonumber(life) or 0.25)
	if not ok then
		warnLimited("flash", err)
	end
end
local function impact(opts)
	local o = {}
	if type(opts) == "table" then
		for k, v in pairs(opts) do
			o[k] = v
		end
	end
	o.flashAlpha = math.clamp(tonumber(o.flashAlpha) or 0.2, 0, 0.25)
	local ok, err = pcall(FX.impact, o)
	if not ok then
		warnLimited("impact", err)
	end
end

---------------------------------------------------------------------------------------------------
-- the ability bar (the template's geometry): [R ELEPHANT GUN] [E ROCKET] [M1 GUM-GUM PUNCH] [Q GATLING - the big
-- button, its stroke breathing while it is ready], G GEAR FIFTH as the wide button above (BAJRANG GUN inside the
-- mode), the mode status and its draining timer above that, and five combo pips over the M1 button
local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.AnchorPoint = Vector2.new(1, 1)
bar.Position = UDim2.new(1, -22, 1, -22)
bar.Size = UDim2.fromOffset(380, 112)
bar.BackgroundTransparency = 1
bar.Visible = false
bar.Parent = gui
local barScale = Instance.new("UIScale")
barScale.Parent = bar
local status = uiText(bar, {
	Name = "ModeStatus", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -175), Size = UDim2.new(0, 186, 0, 18),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack, TextColor3 = PAL.Crimson,
})
uiStroke(status, PAL.Black, 1.5, 0.1)
local statusScale = Instance.new("UIScale")
statusScale.Parent = status
-- the mode's timer: a thin bar between the status and the ultimate's button, hot crimson at its draining end fading
-- to black, with an ember riding that end
local modeBar = Instance.new("Frame")
modeBar.Name = "ModeTimer"
modeBar.AnchorPoint = Vector2.new(1, 1)
modeBar.Position = UDim2.new(1, 0, 1, -170)
modeBar.Size = UDim2.fromOffset(186, 4)
modeBar.BackgroundColor3 = PAL.Black
modeBar.BackgroundTransparency = 0.3
modeBar.BorderSizePixel = 0
modeBar.Visible = false
modeBar.Parent = bar
uiCorner(modeBar, UDim.new(1, 0))
uiStroke(modeBar, PAL.Blood, 1, 0.4)
local modeFill = Instance.new("Frame")
modeFill.Name = "Fill"
modeFill.AnchorPoint = Vector2.new(1, 0)
modeFill.Position = UDim2.fromScale(1, 0)
modeFill.Size = UDim2.fromScale(1, 1)
modeFill.BackgroundColor3 = WHITE
modeFill.BorderSizePixel = 0
modeFill.Parent = modeBar
uiCorner(modeFill, UDim.new(1, 0))
do
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PAL.Ember), ColorSequenceKeypoint.new(0.2, PAL.Crimson), ColorSequenceKeypoint.new(1, PAL.Black),
	})
	g.Parent = modeFill
end
local modeSpark = Instance.new("Frame")
modeSpark.Name = "Ember"
modeSpark.AnchorPoint = Vector2.new(0.5, 0.5)
modeSpark.Position = UDim2.fromScale(0, 0.5)
modeSpark.Size = UDim2.fromOffset(8, 8)
modeSpark.BackgroundColor3 = PAL.Ember
modeSpark.BorderSizePixel = 0
modeSpark.ZIndex = 2
modeSpark.Parent = modeFill
uiCorner(modeSpark, UDim.new(1, 0))
uiStroke(modeSpark, PAL.Crimson, 1.5, 0.2)

local cooldownEnd = { M1 = 0, Gatling = 0, Rocket = 0, Elephant = 0, Gear5 = 0, Bajrang = 0 }
local cooldownLen = {}
for _, k in ipairs(SKILLS) do
	local c = type(CFG[k]) == "table" and CFG[k] or {}
	local len = (k == "M1") and (c.FinalCooldown or 0.85) or (c.Cooldown or 1)
	cooldownLen[k] = math.max(tonumber(len) or 1, 0.1)
end
local buttons = {}

-- the world point under the cursor (the screen centre on touch-only devices, or when cast from a bar button)
local debugAim, debugTarget, debugFinisher
local function cursorTarget(fromButton)
	if debugTarget then
		return debugTarget
	end
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	if fromButton or (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) then
		m = cam.ViewportSize / 2
	end
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	refreshIgnore(true)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, cursorParams)
	return hit and hit.Position or ray.Origin + ray.Direction * 200
end

-- the camera look (Studio tests: debugAim stands in for it)
local function camAim()
	return debugAim or workspace.CurrentCamera.CFrame.LookVector
end
-- payload (CONTRACT 4.1): { aim, target } plus `extra` (the M1 finisher)
local function request(skill, fromButton, extra)
	if type(skill) ~= "string" or not equipped() or not myChar() then
		return
	end
	local payload = { aim = camAim(), target = cursorTarget(fromButton) }
	-- (2026-11-09) M1 punches toward the mouse (the world point under the cursor), not along the camera
	if skill == "M1" and not debugAim then
		local _, _, hrp = myChar()
		local off = hrp and (payload.target - (hrp.Position + Vector3.yAxis))
		if off and (off * Vector3.new(1, 0, 1)).Magnitude > 1.5 then
			payload.aim = off.Unit
		end
	end
	if type(extra) == "table" then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	Request:FireServer(skill, payload)
end

-- ctx.aimStream(id, secs): a cast's steering stream, Request("Aim", { id, aim, target }) at 15 Hz for secs (the
-- Gatling's cone follows it). aimStream(nil) stops it; a new one replaces the old
local aimStreamState = nil -- { id, untilT, nextAt }
local function aimStream(id, secs)
	if id == nil then
		aimStreamState = nil
		return
	end
	aimStreamState = { id = id, untilT = os.clock() + math.clamp(tonumber(secs) or 1, 0, 10), nextAt = 0 }
end
local function updateAimStream(clock)
	local st = aimStreamState
	if not st then
		return
	end
	if clock >= st.untilT or not equipped() or not myChar() then
		aimStreamState = nil
		return
	end
	if clock >= st.nextAt then
		st.nextAt = clock + 1 / 15
		Request:FireServer("Aim", { id = st.id, aim = camAim(), target = cursorTarget() })
	end
end

-- M1: the left mouse button swings the sword (the server sets OwnM1, so GojoClient's shared punch stays out of it).
-- Clicks closer than M1Throttle (0.08 s) apart are dropped; a click up to M1Buffer (0.12 s) before the next swing is
-- allowed is held and sent the moment it is; holding the button keeps the combo going
local M1_THROTTLE = tonumber(HUDCFG.M1Throttle) or 0.08
local M1_BUFFER = tonumber(HUDCFG.M1Buffer) or 0.12
local m1 = { lastReq = -1e9, readyT = -1e9, buffered = false, held = false, combo = 0, comboAt = -1e9 }
local function m1Interval(mode)
	if mode == nil then
		mode = inMode(player.Character)
	end
	if mode and type(MODE.M1) == "table" and type(MODE.M1.SwingInterval) == "number" then
		return MODE.M1.SwingInterval
	end
	return (CFG.M1 and CFG.M1.SwingInterval) or 0.34
end
-- the finisher the NEXT swing carries, only when it is hit 5 (the combo count comes from the M1Swing echo): Space
-- held -> "Rifle", airborne -> "Axe", else nil (the server's default, Pistol). Studio: debugFinisher forces it
local function nextFinisher()
	local len = (CFG.M1 and CFG.M1.ComboLength) or 5
	local reset = (CFG.M1 and CFG.M1.ComboResetTime) or 1.1
	local nextCombo = (os.clock() - m1.comboAt < reset) and (m1.combo % len + 1) or 1
	if nextCombo ~= len then
		return nil
	end
	if debugFinisher then
		return debugFinisher
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		return "Rifle"
	end
	local _, hum = myChar()
	local st = hum and hum:GetState()
	if st == Enum.HumanoidStateType.Freefall or st == Enum.HumanoidStateType.Jumping then
		return "Axe"
	end
	return nil
end
local function sendM1()
	m1.lastReq = os.clock()
	m1.readyT = now() + m1Interval() -- assume it lands; the M1Swing echo corrects it (a refused swing costs nothing)
	local fin = nextFinisher()
	request("M1", false, fin and { finisher = fin } or nil)
end
local function tryM1()
	if not equipped() or not myChar() then
		return
	end
	if os.clock() - m1.lastReq < M1_THROTTLE then
		return
	end
	local wait = m1.readyT - now()
	if wait <= 0.02 then
		sendM1()
	elseif wait <= M1_BUFFER and not m1.buffered then
		m1.buffered = true
		task.delay(wait, function()
			m1.buffered = false
			if equipped() and myChar() and os.clock() - m1.lastReq >= M1_THROTTLE then
				sendM1()
			end
		end)
	end
end
-- the server's M1Swing echo for the local caster: the real swing time, the combo step, the finisher's longer lock
local function m1Echo(d)
	local combo = tonumber(d.combo) or 1
	local gap = m1Interval(d.mode == true)
	if combo >= ((CFG.M1 and CFG.M1.ComboLength) or 4) then
		gap = math.max(gap, (CFG.M1 and CFG.M1.FinalCooldown) or 0.85)
	end
	m1.readyT = (tonumber(d.t0) or now()) + gap
	m1.combo, m1.comboAt = combo, os.clock()
end

local function skillButton(id, size, x)
	local co = CFG.Callouts[id] or { c0 = WHITE, c1 = PAL.Reiatsu }
	local big = size > 80
	local b = Instance.new("TextButton")
	b.Name = id
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.new(1, x, 1, -16)
	b.BackgroundColor3 = darken(co.c1:Lerp(PAL.Robe, 0.6), 0.76)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(140, 148, 168))
	shade.Rotation = 90
	shade.Parent = b
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.4), big and 2.5 or 2, 0.1)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.46, 0.46)
	orb.BackgroundColor3 = WHITE
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local og = Instance.new("UIGradient")
	og.Color = ColorSequence.new(co.c0, co.c1)
	og.Rotation = 45
	og.Parent = orb
	uiStroke(orb, co.c1:Lerp(WHITE, 0.5), 1.5, 0.3)
	local glyph = uiText(orb, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.11), Text = co.glyph or "", ZIndex = 2 })
	uiStroke(glyph, co.c1:Lerp(BLACK, 0.7), 1.5, 0)
	uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 11), Position = UDim2.new(0, 4, 1, big and -21 or -17), Text = CFG.Labels[id] or id, ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(BLACK, 0.86)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11, "have the option to have keybinds") the chip names the key the player bound the move to, not the
	-- Config default, and follows a rebind made mid-match
	local function keyName()
		return (id == "M1") and "M1" or ((CFG.Keys[id] and Keybinds.label(CFG.Keys[id])) or "")
	end
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = keyName(), Font = Enum.Font.GothamBold, ZIndex = 2 })
	if id ~= "M1" then
		Keybinds.Changed:Connect(function()
			keyText.Text = keyName()
		end)
	end
	uiText(b, { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, 4), Text = co.hint or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.35) })
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = BLACK
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	cd.Parent = b
	uiCorner(cd, UDim.new(0, 18))
	local cdText = uiText(b, { Size = UDim2.fromScale(1, 0.38), Position = UDim2.fromScale(0, 0.22), Text = "", ZIndex = 4 })
	buttons[id] = {
		cd = cd, cdText = cdText, scale = scale, stroke = st, baseStroke = st.Color, frame = b, color = co.c1, color2 = co.c0,
		ready = true, noText = id == "M1",
	}
	b.Activated:Connect(function()
		if id == "M1" then
			tryM1() -- the bar's M1 swings the sword (never GojoClient's SharedPunch)
		else
			request(id, true)
		end
	end)
	return b
end
-- the same slots as the other kits: R in the left slot, E next to it, the M1 string, Q (Gatling) on the big button
skillButton("Elephant", 72, -280)
skillButton("Rocket", 72, -198)
skillButton("M1", 72, -116)
skillButton("Gatling", 104, 0)

-- the M1 string: five diamonds over the M1 button light hit by hit (Nika white in the mode), dark once it resets
local pips, pipScales = {}, {}
local PIPS = math.max(math.floor(tonumber(CFG.M1 and CFG.M1.ComboLength) or 5), 1)
for i = 1, PIPS do
	local p = Instance.new("Frame")
	p.Name = "ComboPip" .. i
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(8, 8)
	p.Position = UDim2.new(1, -152 + (i - (PIPS + 1) / 2) * 12, 1, -99)
	p.Rotation = 45
	p.BackgroundColor3 = Color3.fromRGB(55, 58, 66)
	p.BorderSizePixel = 0
	p.Parent = bar
	uiCorner(p, UDim.new(0, 2))
	uiStroke(p, PAL.Straw, 1, 0.35)
	local ps = Instance.new("UIScale")
	ps.Parent = p
	pips[i], pipScales[i] = p, ps
end

-- Gear Fifth on its own wide button above the row. Inside the mode G is Bajrang Gun: updateHud swaps the sub label to
-- BAJRANG GUN, the glyph to Bajrang's and the cooldown to cooldownEnd.Bajrang
do
	local co = CFG.Callouts.Gear5 or { c0 = WHITE, c1 = PAL.Straw, glyph = "" }
	local bco = CFG.Callouts.Bajrang or {}
	local b = Instance.new("TextButton")
	b.Name = "Gear5"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, 0, 1, -132)
	b.Size = UDim2.fromOffset(186, 36)
	b.BackgroundColor3 = WHITE
	b.Parent = bar
	uiCorner(b, UDim.new(0, 12))
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.4), 2, 0.1)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(darken(PAL.Vest, 0.32), darken(PAL.Vest, 0.75))
	g.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c1:Lerp(BLACK, 0.9)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11, "have the option to have keybinds") the key the player bound the ultimate to, refreshed on a rebind
	local function ultKey()
		return (CFG.Keys.Gear5 and Keybinds.label(CFG.Keys.Gear5)) or "G"
	end
	local ultKeyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = ultKey(), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		ultKeyText.Text = ultKey()
	end)
	uiText(b, { Size = UDim2.new(1, -74, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.Gear5 or "GEAR FIFTH", TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 })
	local sub = uiText(b, { Size = UDim2.new(1, -74, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
	local glyph = uiText(b, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(26, 26), Text = co.glyph or "", TextColor3 = co.c0:Lerp(co.c1, 0.25), ZIndex = 2 })
	uiStroke(glyph, PAL.Black, 1.5, 0)
	local cd = Instance.new("Frame")
	cd.AnchorPoint = Vector2.new(1, 0)
	cd.Position = UDim2.fromScale(1, 0)
	cd.Size = UDim2.fromScale(0, 1)
	cd.BackgroundColor3 = BLACK
	cd.BackgroundTransparency = 0.35
	cd.ZIndex = 3
	cd.Parent = b
	uiCorner(cd, UDim.new(0, 12))
	local cdText = uiText(b, { Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 4 })
	buttons.Gear5 = {
		cd = cd, cdText = cdText, scale = scale, stroke = st, baseStroke = st.Color, frame = b, color = co.c1, color2 = co.c0,
		ready = true, horizontal = true, sub = sub, subText = co.sub or "", glyph = glyph, glyphText = co.glyph or "",
		modeGlyph = bco.glyph or co.glyph or "",
	}
	b.Activated:Connect(function()
		request("Gear5", true) -- G is always "Gear5": inside the mode the server routes it to Bajrang Gun
	end)
end

-- a ring that pings off a button (on a cast, and when it comes off cooldown)
local function pingButton(b, color)
	local host = b and b.frame
	if not host or not host.Parent then
		return
	end
	local r = Instance.new("Frame")
	r.Name = "Ping"
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.Size = UDim2.fromScale(1, 1)
	r.BackgroundTransparency = 1
	r.ZIndex = 6
	r.Parent = host
	uiCorner(r, UDim.new(0, b.horizontal and 12 or 18))
	local st = uiStroke(r, color or WHITE, 3, 0)
	tween(r, 0.4, { Size = b.horizontal and UDim2.new(1, 28, 1, 22) or UDim2.fromScale(1.55, 1.55) })
	tween(st, 0.4, { Transparency = 1, Thickness = 1 })
	Debris:AddItem(r, 0.45)
end
-- a metal shine sweeping across a button (when it comes off cooldown)
local function shineButton(b)
	local host = b and b.frame
	if not host or not host.Parent then
		return
	end
	local s = Instance.new("Frame")
	s.Name = "Shine"
	s.Size = UDim2.fromScale(1, 1)
	s.BackgroundColor3 = WHITE
	s.BackgroundTransparency = 0.25
	s.BorderSizePixel = 0
	s.ZIndex = 5
	s.Parent = host
	uiCorner(s, UDim.new(0, b.horizontal and 12 or 18))
	local g = Instance.new("UIGradient")
	g.Rotation = 25
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = s
	tween(g, 0.4, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	Debris:AddItem(s, 0.45)
end

-- (2026-11-09) TOUCH: a plain tap on the screen (not on a button or the thumbstick, not a camera drag) is an M1
UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
	if processedByUI or _G.SandboxArmed then -- (2026-11-14) not while a sandbox weapon / GRAB is out (SandboxClient's HIT button owns the tap then)
		return
	end
	if equipped() then
		safe("m1", tryM1)
	end
end)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		m1.held = true
		safe("m1", tryM1)
		return
	end
	-- (2026-11-11, "have the option to have keybinds") compare the ACTION the pressed key is bound to (its default
	-- key), so a rebound move fires from its new key and stops firing from the old one
	local key = Keybinds.logical(input.KeyCode)
	for skill, defaultKey in pairs(CFG.Keys) do
		if key == defaultKey then
			request(skill)
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 and not _G.SandboxArmed) then
		m1.held = false
	end
end)
UserInputService.WindowFocusReleased:Connect(function()
	m1.held = false
end)

---------------------------------------------------------------------------------------------------
-- the local body: rooting during moves, the passive / Tensa Gomu speed boost, the scripted mover, blinks and the float
local rootUntil = 0 -- os.clock() until which the local character can't walk or jump
local faceDir = nil -- the flat direction it is held facing while rooted
local mover = nil -- { char, t0 (server time), dur, from, to, face, vel?, ease?, hold?, exitVel? }
local wroteMovement = false
local baseMove = nil -- { ws, jp, jh } captured when the character spawns
local floats = {} -- [handle] = true

local function root(secs, face)
	rootUntil = math.max(rootUntil, os.clock() + (secs or 0))
	if typeof(face) == "Vector3" then
		faceDir = flat(face)
	end
end

local function unroot()
	rootUntil, faceDir = 0, nil
end

local function setFace(dir)
	if typeof(dir) == "Vector3" then
		faceDir = flat(dir)
	end
end

local function blinkTo(cf)
	local char, _, hrp = myChar()
	if not char or typeof(cf) ~= "CFrame" then
		return
	end
	char:PivotTo(cf)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

-- a swing that keeps him moving, slowed and held facing the swing (DECISIONS: M1 swings 1-3 do not root; he keeps
-- moving at WalkSpeed x0.45 through the swing's window). The scaffold applies it itself on the local caster's M1Swing
-- echo (updateMovement rewrites WalkSpeed every frame, so a module writing it directly would be overwritten);
-- ctx.slow(secs, mul, face) does the same for any module
local slowUntil, slowMul, slowFace = 0, 1, nil
local function slow(secs, mul, face)
	slowUntil = math.max(slowUntil, os.clock() + math.max(tonumber(secs) or 0, 0))
	slowMul = math.clamp(tonumber(mul) or 0.45, 0, 1)
	if typeof(face) == "Vector3" then
		slowFace = flat(face)
	end
end

-- WalkSpeed / jump / AutoRotate are derived from the kit's state every frame (never saved and restored), so a mode
-- that starts while rooted can't be lost to a restore. Passive x1.1 / x1.05 always; Tensa Gomu x1.6 / x1.2 (from
-- Gear5Until). The base walk speed is the character's KitWalkSpeed (KitServer writes it), read live
local function updateMovement(dt)
	local char, hum, hrp = myChar()
	if not char or not baseMove then
		return
	end
	if not equipped() then
		if wroteMovement then
			wroteMovement = false
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = baseMove.ws, baseMove.jp, baseMove.jh, true
		end
		return
	end
	wroteMovement = true
	local clock = os.clock()
	local rooted = clock < rootUntil
	local slowed = (not rooted) and clock < slowUntil
	if clock >= slowUntil then
		slowFace = nil
	end
	local mode = inMode(char)
	local kws = char:GetAttribute("KitWalkSpeed")
	local base = (type(kws) == "number" and kws > 0) and kws or baseMove.ws
	local ws = 0
	if not rooted then
		ws = base * (mode and (MODE.WalkSpeedMul or 1.6) or (PASSIVE.WalkSpeedMul or 1.1))
		if slowed then
			ws *= slowMul
		end
	end
	local jk = rooted and 0 or (mode and (MODE.JumpMul or 1.2) or (PASSIVE.JumpMul or 1.05))
	if hum.WalkSpeed ~= ws then
		hum.WalkSpeed = ws
	end
	if hum.JumpPower ~= baseMove.jp * jk then
		hum.JumpPower = baseMove.jp * jk
	end
	if hum.JumpHeight ~= baseMove.jh * jk * jk then
		hum.JumpHeight = baseMove.jh * jk * jk
	end
	local face = (rooted and faceDir) or (slowed and slowFace) or nil
	local hold = rooted or face ~= nil
	if hum.AutoRotate == hold then
		hum.AutoRotate = not hold
	end
	if hold and face and not mover then
		local want = CFrame.lookAt(Vector3.zero, face)
		local cur = hrp.CFrame - hrp.Position
		hrp.CFrame = CFrame.new(hrp.Position) * cur:Lerp(want, 1 - math.exp(-18 * dt))
	end
end

local function easeEnum(enumType, v, default)
	if typeof(v) == "EnumItem" then
		return v
	end
	if type(v) == "string" then
		local ok, item = pcall(function()
			return enumType[v]
		end)
		if ok and item then
			return item
		end
	end
	return default
end

-- the scripted move (ctx.move): m = { char, t0, dur, from, to, face, vel?, ease = {style, dir}?, hold?, exitVel? }
local function move(m)
	if type(m) ~= "table" or typeof(m.to) ~= "Vector3" then
		return
	end
	local char, _, hrp = myChar()
	m.char = m.char or char
	if not char or m.char ~= char then
		return
	end
	m.t0 = tonumber(m.t0) or now()
	m.dur = math.max(tonumber(m.dur) or 0.2, 0.01)
	m.from = typeof(m.from) == "Vector3" and m.from or hrp.Position
	m.face = flat(m.face or (m.to - m.from), flat(hrp.CFrame.LookVector))
	if type(m.ease) == "table" then
		m.ease = {
			style = easeEnum(Enum.EasingStyle, m.ease.style or m.ease[1], Enum.EasingStyle.Linear),
			dir = easeEnum(Enum.EasingDirection, m.ease.dir or m.ease.direction or m.ease[2], Enum.EasingDirection.Out),
		}
	elseif typeof(m.ease) == "EnumItem" or type(m.ease) == "string" then
		m.ease = { style = easeEnum(Enum.EasingStyle, m.ease, Enum.EasingStyle.Linear), dir = Enum.EasingDirection.Out }
	else
		m.ease = nil
	end
	m.hold = tonumber(m.hold) or 0
	mover = m
end

local function stopMove()
	mover = nil
end

local function moverPos(m, e)
	local k = math.clamp(e / m.dur, 0, 1)
	if m.ease then
		k = TweenService:GetValue(k, m.ease.style, m.ease.dir)
	end
	return m.from:Lerp(m.to, k)
end

-- written before physics every step, so the character's own simulation carries it along
RunService.Stepped:Connect(function()
	if not mover then
		return
	end
	local char, _, hrp = myChar()
	if not char or char ~= mover.char then
		mover = nil
		return
	end
	local m = mover
	local e = now() - m.t0
	if e < 0 then
		return
	end
	if e >= m.dur then
		hrp.CFrame = CFrame.lookAt(m.to, m.to + m.face)
		if e < m.dur + m.hold then
			hrp.AssemblyLinearVelocity = Vector3.zero -- held at the end of the move
			return
		end
		hrp.AssemblyLinearVelocity = typeof(m.exitVel) == "Vector3" and m.exitVel or m.face * 16
		mover = nil
		return
	end
	local pos = moverPos(m, e)
	hrp.CFrame = CFrame.lookAt(pos, pos + m.face)
	if typeof(m.vel) == "Vector3" then
		hrp.AssemblyLinearVelocity = m.vel
	else
		hrp.AssemblyLinearVelocity = (moverPos(m, e + 1 / 60) - pos) * 60
	end
end)

-- the float-down: a world-space VectorForce takes (1 - gravityMul) of gravity off the body, until it lands,
-- `maxSecs` pass, it dies, or the cast is cancelled
local function float(hrp, gravityMul, maxSecs)
	if not hrp or not hrp.Parent then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "GomuFloat"
	att.Parent = hrp
	local vf = Instance.new("VectorForce")
	vf.Name = "GomuFloat"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = UP * hrp.AssemblyMass * workspace.Gravity * (1 - (gravityMul or 0.3))
	vf.Parent = hrp
	local h = { hrp = hrp, att = att, vf = vf, mul = gravityMul or 0.3, t0 = os.clock(), max = maxSecs or 1.4 }
	function h:Destroy()
		floats[self] = nil
		if self.vf then
			self.vf:Destroy()
			self.vf = nil
		end
		if self.att then
			self.att:Destroy()
			self.att = nil
		end
	end
	h.destroy = h.Destroy
	floats[h] = true
	return h
end

local function updateFloats(clock)
	for h in pairs(floats) do
		local hrp = h.hrp
		local hum = hrp and hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
		local age = clock - h.t0
		if not hum or hum.Health <= 0 or not h.vf or not h.vf.Parent or age >= h.max or (age > 0.1 and hum.FloorMaterial ~= AIR) then
			h:Destroy()
		else
			h.vf.Force = UP * hrp.AssemblyMass * workspace.Gravity * (1 - h.mul)
		end
	end
end

local function groundY(pos)
	if typeof(pos) ~= "Vector3" then
		return nil
	end
	local hit = FX.groundHit(pos, 30)
	return hit and hit.Position.Y or nil
end

---------------------------------------------------------------------------------------------------
-- PvP knockback (CONTRACT 4.3): GomuServer.Core sends a hit on THIS player's body to this client, which owns it. It
-- runs whatever kit the local player holds. ragTime <= 0 = a shove (one impulse); > 0 = a tumble (PlatformStand) that
-- updateTumble stands back up once it passes. A tumble also stops any running ctx.move / float of the local caster
local Knockback = Remotes:WaitForChild("Knockback", 10)
local tumbleUntil = 0
local function eachAssembly(char, fn)
	local done = {}
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			local r = part.AssemblyRootPart
			if r and not done[r] then
				done[r] = true
				fn(r)
			end
		end
	end
end
if Knockback then
	Knockback.OnClientEvent:Connect(function(vel, ragTime, keepV)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 or typeof(vel) ~= "Vector3" then
			return
		end
		if char:GetAttribute("SuperArmor") or char:GetAttribute("AscForm") == "Instinct" then
			return
		end
		if vel ~= vel or vel.Magnitude > 320 then
			vel = (vel == vel and vel.Magnitude > 0) and vel.Unit * 320 or Vector3.zero
		end
		local keepK = math.clamp(tonumber(keepV) or 0, 0, 1)
		ragTime = tonumber(ragTime) or 0
		if ragTime <= 0 then
			hrp:ApplyImpulse((vel - hrp.AssemblyLinearVelocity * (1 - keepK)) * hrp.AssemblyMass)
			return
		end
		mover = nil
		for h in pairs(floats) do
			h:Destroy()
		end
		tumbleUntil = math.max(tumbleUntil, os.clock() + math.min(ragTime, tonumber(CFG.PlayerRagdollMax) or 2.2))
		hum.PlatformStand = true
		eachAssembly(char, function(r)
			r:ApplyImpulse((vel - r.AssemblyLinearVelocity * (1 - keepK)) * r.AssemblyMass)
		end)
	end)
else
	warn("[GomuClient] GomuKit.Remotes.Knockback is missing; PvP knockback from Luffy will not move this body")
end
local function updateTumble(clock)
	if tumbleUntil > 0 and clock >= tumbleUntil then
		tumbleUntil = 0
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- passive helpers
local function pnum(k, d)
	local v = PASSIVE[k]
	return type(v) == "number" and v or d
end
local function between(r, a, b)
	if type(r) == "table" and type(r[1]) == "number" then
		a, b = r[1], r[2] or r[1]
	end
	return a + math.random() * (b - a)
end
local NSK = FX.nsk or function(list)
	local kp = {}
	for _, v in ipairs(list) do
		table.insert(kp, NumberSequenceKeypoint.new(v[1], v[2]))
	end
	return NumberSequence.new(kp)
end
-- Studio's built-in fire sheet: local content (it never streams in), already used by PurpleVFX and VulpineKit.FxLib
local FIRE_TEX = type(PASSIVE.FlameTexture) == "string" and PASSIVE.FlameTexture or "rbxasset://textures/particles/fire_main.dds"
local function glowSize(pos, size)
	if type(S.glowFor) == "function" then
		local ok, v = pcall(S.glowFor, pos, size)
		if ok and type(v) == "number" then
			return v
		end
	end
	return size * math.clamp(camDist(pos) / 30, 0.45, 1)
end
-- PASSIVE: the rubber body. Every Gomu character landing hard (falling faster than Passive.BoingFall studs/s)
-- squashes and rebounds: S.boing (a short Root / legs pose clip + a flat squash ring + dust). The local character
-- always; remote ones within Passive.GateDist of the camera. Skipped while a move clip covers the body (the move owns
-- the pose) or while it tumbles. Landing is read from FloorMaterial locally and from a short ground ray for remote
-- bodies (their Humanoid does not simulate on this client)
local updatePassive
do
	local track = setmetatable({}, { __mode = "k" }) -- [char] = { air, minVy, boingAt }
	local function grounded(p, hum, hrp)
		if p == player then
			return hum.FloorMaterial ~= AIR
		end
		local depth = (hum.RigType == Enum.HumanoidRigType.R6) and 3.7 or (hum.HipHeight + hrp.Size.Y * 0.5 + 0.7)
		return FX.groundHit(hrp.Position, depth) ~= nil
	end
	function updatePassive(clock)
		local gateD = pnum("GateDist", 140)
		local fall = pnum("BoingFall", 38)
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and char.Parent and p:GetAttribute("Kit") == CFG.KitId then
				local hum = char:FindFirstChildOfClass("Humanoid")
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hum and hrp and hum.Health > 0 and (p == player or camDist(hrp.Position) <= gateD) then
					local st = track[char]
					if not st then
						st = { air = false, minVy = 0, boingAt = 0 }
						track[char] = st
					end
					local onGround = grounded(p, hum, hrp)
					if not onGround then
						st.minVy = math.min(st.minVy, hrp.AssemblyLinearVelocity.Y)
					else
						if st.air then
							local speed = -st.minVy
							if speed > fall and clock - st.boingAt > 0.35 and not hum.PlatformStand
								and clock >= (clipUntil[char] or 0) and type(S.boing) == "function" then
								st.boingAt = clock
								safe("boing", S.boing, char, { power = math.clamp(speed / (fall * 2), 0.5, 1.5) })
							end
						end
						st.minVy = 0
					end
					st.air = not onGround
				end
			end
		end
	end
end


---------------------------------------------------------------------------------------------------
-- the HUD every frame: cooldowns + ready pops, Q's breathing stroke, the Tensa Gomu status / draining timer / the
-- G stroke pulsing crimson / the slow crimson edge pulse (quicker in the last LateAt seconds), the M1 combo pips and
-- the title shakes
local hud = { modeWas = false, popAt = -1e9, pipWas = {} }
local function modePulse(clock, late)
	return 0.5 + 0.5 * math.sin(clock * TAU * (late and 2.4 or 0.5))
end
local function updateHud(clock)
	local on = equipped()
	bar.Visible = on
	-- the ultimate's titles shake the title holder for 0.2 s; every kanji slam jolts it for 0.08 s
	if clock < TT.shakeUntil or clock < TT.jolt then
		local a = (clock < TT.shakeUntil) and 4 or 3
		TT.holder.Position = UDim2.new(0.5, math.random(-a, a), TITLE_Y, math.random(-a, a))
		TT.shaken = true
	elseif TT.shaken then
		TT.shaken = false
		TT.holder.Position = UDim2.fromScale(0.5, TITLE_Y)
	end
	local t = now()
	local char = player.Character
	local left = on and modeLeft(char) or 0
	local mode = left > 0
	local late = mode and left < (tonumber(HUDCFG.LateAt) or 3)
	local beat = mode and modePulse(clock, late) or 0
	-- edge vignette: a pulse in its own colour; through the mode a slow crimson edge pulse (alpha 0.05 - 0.1)
	local va, vc = 0, PAL.Crimson
	if vigFlash then
		local x = (clock - vigFlash.t0) / vigFlash.dur
		if x >= 1 then
			vigFlash = nil
		else
			va = vigFlash.a * (1 - x)
			vc = vigFlash.color or PAL.Crimson
		end
	end
	if mode then
		local mv = 0.05 + 0.05 * beat
		if mv >= va then
			va, vc = mv, PAL.Crimson
		end
	end
	local vt = 1 - math.min(va, 0.35)
	for _, f in ipairs(edges) do
		if math.abs(f.BackgroundTransparency - vt) > 1e-3 then
			f.BackgroundTransparency = vt
		end
		if f.BackgroundColor3 ~= vc then
			f.BackgroundColor3 = vc
		end
	end
	if not on then
		hud.modeWas = false
		return
	end
	for skill, b in pairs(buttons) do
		-- inside Gear Fifth the G button is Bajrang Gun: it shows that cooldown
		local key = (skill == "Gear5" and mode) and "Bajrang" or skill
		local rem = (cooldownEnd[key] or 0) - t
		local k = math.clamp(rem / math.max(cooldownLen[key] or 1, 0.1), 0, 1)
		if b.horizontal then
			b.cd.Size = UDim2.fromScale(k, 1)
		else
			b.cd.Size = UDim2.fromScale(1, k)
		end
		b.cdText.Text = (rem > 0 and not b.noText) and string.format(rem >= 10 and "%.0f" or "%.1f", rem) or ""
		local ready = rem <= 0
		if ready and not b.ready then
			-- ready again: the button pops, its stroke flashes white and a ring pings off it
			b.scale.Scale = 1.14
			TweenService:Create(b.scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if b.stroke and b.baseStroke then
				b.stroke.Color = WHITE
				tween(b.stroke, 0.35, { Color = b.baseStroke })
			end
			pingButton(b, b.color2 or WHITE)
			shineButton(b)
		end
		b.ready = ready
	end
	-- the big move feels loaded: Q's stroke breathes while it is ready
	local q = buttons.Gatling
	if q then
		q.stroke.Transparency = q.ready and (0.3 + 0.2 * math.sin(clock * TAU * 1.2)) or 0.1
	end
	local u = buttons.Gear5
	if u then
		if mode then
			u.stroke.Color = PAL.Crimson:Lerp(WHITE, 0.5 + 0.5 * math.sin(clock * TAU * (late and 5 or 1.6)))
			u.modeTint = true
		elseif u.modeTint then
			u.modeTint = false
			u.stroke.Color = u.baseStroke
		end
		local wantSub = mode and (CFG.Labels.Bajrang or "BAJRANG GUN") or u.subText
		if u.sub and u.sub.Text ~= wantSub then
			u.sub.Text = wantSub
		end
		local wantGlyph = mode and u.modeGlyph or u.glyphText
		if u.glyph and u.glyph.Text ~= wantGlyph then
			u.glyph.Text = wantGlyph
		end
	end
	if mode ~= hud.modeWas then
		hud.modeWas = mode
		if mode then
			hud.popAt = clock -- the status slams in as the mode starts
			pingButton(u, PAL.Crimson)
		end
	end
	-- the mode status: the countdown breathes (beats quicker in the last seconds) over its draining timer
	status.Text = mode and string.format("GEAR FIFTH  %.1fs", left) or ""
	local pop = math.max(0.3 - (clock - hud.popAt), 0) / 0.3
	statusScale.Scale = 1 + (late and 0.1 or 0.04) * beat + 0.6 * pop * pop
	status.TextColor3 = late and PAL.Crimson:Lerp(PAL.Ember, beat) or PAL.Crimson
	modeBar.Visible = mode
	if mode then
		local k = math.clamp(left / math.max(MODE.Time or 15, 0.1), 0, 1)
		modeFill.Size = UDim2.fromScale(k, 1)
		modeFill.BackgroundTransparency = late and 0.35 * beat or 0
		local s = 7 + 3 * beat
		modeSpark.Size = UDim2.fromOffset(s, s)
		modeSpark.BackgroundColor3 = PAL.Ember:Lerp(WHITE, 0.35 * beat)
	end
	-- the M1 combo pips
	local lit = (clock - m1.comboAt < ((CFG.M1 and CFG.M1.ComboResetTime) or 1.1)) and m1.combo or 0
	for i, p in ipairs(pips) do
		local isLit = i <= lit
		p.BackgroundColor3 = isLit and (mode and PAL.Core or PAL.Reiatsu) or Color3.fromRGB(55, 58, 66)
		if isLit and hud.pipWas[i] == false then
			pipScales[i].Scale = (i == #pips) and 1.9 or 1.5
			tween(pipScales[i], 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		hud.pipWas[i] = isLit
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	barScale.Scale = math.clamp(vp.Y / 720, 0.75, 1.3)
end

---------------------------------------------------------------------------------------------------
-- playback: this script's own kind (Cooldown), plus every move module's
local handlers = {}
local updates = {} -- [moduleName] = __update(clock, dt)
local resets = {} -- [moduleName] = __reset()
-- PERKS (kitsE): the CRIMSON GEAR copies of the move modules (built below, once Client.Shared has loaded)
local Perk = { handlers = {}, updates = {}, resets = {}, S = nil, ctx = nil, PAL = nil }

handlers.Cooldown = function(d)
	local skill = d.skill
	if skill and cooldownEnd[skill] then
		local ends = tonumber(d.ends) or 0
		if math.abs(ends - cooldownEnd[skill]) > 0.05 then -- a new cast; a refused one resends the same end time
			local len = ends - now()
			if len > 0.2 then
				cooldownLen[skill] = math.max(len, 0.5)
				local b = buttons[skill] or (skill == "Bajrang" and buttons.Gear5) or nil
				if b then -- the cast pop: the button kicks and two rings ping off it
					b.scale.Scale = 1.12
					TweenService:Create(b.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
					pingButton(b, b.color or PAL.Reiatsu)
					task.delay(0.08, function()
						pingButton(b, b.color2 or WHITE)
					end)
				end
			end
		end
		cooldownEnd[skill] = ends
	end
end

-- HUD side of a broadcast, run before the move module draws it (local caster only): the M1 echo (swing timing, the
-- combo pips, the button kick, the slowed swing for 1-3, the finisher's lock on the M1 button) and the mode's end
local function hudHook(kind, d)
	if d.userId ~= player.UserId then
		return
	end
	if kind == "M1Swing" then
		m1Echo(d)
		local combo = tonumber(d.combo) or 1
		local len = (CFG.M1 and CFG.M1.ComboLength) or 5
		local t0 = tonumber(d.t0) or now()
		local b = buttons.M1
		if b then
			b.scale.Scale = (combo >= len) and 1.16 or 1.07
			TweenService:Create(b.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		if combo < len then
			local hitAt = tonumber(d.hitAt) or ((CFG.M1 and type(CFG.M1.HitAt) == "table" and CFG.M1.HitAt[combo]) or 0.14)
			local secs = hitAt + (tonumber(HUDCFG.M1SlowExtra) or 0.1) - math.max(now() - t0, 0)
			if secs > 0 then
				slow(secs, tonumber(HUDCFG.M1SlowMul) or 0.45, d.dir)
			end
		else
			local fc = (CFG.M1 and CFG.M1.FinalCooldown) or 0.9
			cooldownLen.M1 = math.max(fc, 0.1)
			cooldownEnd.M1 = t0 + fc
			if b then
				pingButton(b, d.mode and PAL.Core or PAL.Reiatsu)
			end
		end
	elseif kind == "Gear5On" then
		pingButton(buttons.Gear5, PAL.Crimson)
	elseif kind == "Gear5End" then
		if d.why == "expired" then
			pingButton(buttons.Gear5, PAL.Reiatsu)
			vignette(0.14, 0.6, PAL.Ember)
		end
	end
end

local function resetAll()
	rootUntil, faceDir, mover = 0, nil, nil
	slowUntil, slowFace = 0, nil
	m1.held = false
	aimStreamState = nil
	for h in pairs(floats) do
		h:Destroy()
	end
	stopShot()
	table.clear(leans)
	unvanish(player.Character)
	for name, fn in pairs(resets) do
		safe(name .. ".__reset", fn)
	end
	for name, fn in pairs(Perk.resets) do
		safe(name .. ".alt.__reset", fn)
	end
end

---------------------------------------------------------------------------------------------------
-- ctx extras: distance gating for remote casts and the non-ult screen flair
local function gate(pos, far)
	if typeof(pos) ~= "Vector3" then
		return "full"
	end
	local d = camDist(pos)
	if d <= 160 then
		return "full"
	elseif d <= (tonumber(far) or 260) then
		return "lite"
	end
	return nil
end
local function speedLines(dur, alpha, color)
	local ok, err = pcall(FX.speedLines, math.clamp(tonumber(dur) or 0.3, 0.05, 3), {
		count = 30, color = typeof(color) == "Color3" and color or WHITE, alpha = math.clamp(tonumber(alpha) or 0.35, 0, 0.8),
		inner = 0.6, thick = 4, release = 0.15,
	})
	if not ok then
		warnLimited("speedLines", err)
	end
end

-- CAST TEXT RULE: titles, callouts and the hit tally only for the ultimate (Gear5 / Drums / Laugh / Bajrang)
local ULT_KEYS = { Gear5 = true, Drums = true, Laugh = true, Bajrang = true }
local ULT_TEXT = {}
for k in pairs(ULT_KEYS) do
	local co = CFG.Callouts[k]
	if co and type(co.text) == "string" then
		ULT_TEXT[string.upper(co.text)] = true
	end
	if type(CFG.Labels[k]) == "string" then
		ULT_TEXT[string.upper(CFG.Labels[k])] = true
	end
end
local ultUntil = 0 -- os.clock() until which the ult's tally may draw (an allowed title / callout opens it)

-- ctx: everything a move module gets (CONTRACT 7.3)
local ctx = {
	player = player, CFG = CFG, PAL = PAL, SND = SND, Clips = Clips, FX = FX, S = S, Folder = Folder,
	UP = UP, FLAT = FLAT, WHITE = WHITE, BLACK = BLACK, TAU = TAU, TITLE_Y = TITLE_Y,
	now = now, myChar = myChar, charOf = charOf, equipped = equipped,
	flat = flat, camFacing = camFacing, camDist = camDist, cs = cs,
	sound = sound, soundAt = soundAt, castFolder = castFolder, playClip = playClip, freeze = freeze,
	shake = shake, lean = lean, flash = flash, impact = impact, vignette = vignette,
	showTitle = function(text, kanji, c0, c1, force)
		if force == true or (type(text) == "string" and ULT_TEXT[string.upper(text)]) then
			ultUntil = os.clock() + 4
			return showTitle(text, kanji, c0, c1)
		end
		warnLimited("title", "showTitle(" .. tostring(text) .. ") refused: only the ultimate shows cast text")
	end,
	callout = function(skill, sub)
		if ULT_KEYS[skill] then
			ultUntil = os.clock() + 4
			return callout(skill, sub)
		end
		warnLimited("callout", "callout(" .. tostring(skill) .. ") refused: only the ultimate shows cast text")
	end,
	tally = function(id, n)
		if os.clock() < ultUntil then
			bumpTally(id, tonumber(n) or 1)
		end
	end,
	root = root, unroot = unroot, setFace = setFace, slow = slow, move = move, stopMove = stopMove, blinkTo = blinkTo,
	float = float, groundY = groundY, shot = shot, stopShot = stopShot,
	inMode = inMode, modeLeft = modeLeft, vanish = vanish, unvanish = unvanish,
	request = function(skill)
		request(skill)
	end,
	cursorTarget = function()
		return cursorTarget()
	end,
	ghost = function(...)
		return ghost(...)
	end,
	bodyArc = function(...)
		return bodyArc(...)
	end,
	glowFor = glowSize,
	clipActive = function(char)
		return os.clock() < (clipUntil[char] or 0)
	end,
	aimStream = aimStream, camAim = camAim, speedLines = speedLines, gate = gate,
}

---------------------------------------------------------------------------------------------------
-- every frame: movement, the held M1, floats, the tumble, the aim stream, the passive, the move modules, the HUD
local function updateM1()
	if not m1.held then
		return
	end
	if not equipped() or not (UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and not _G.SandboxArmed) then
		m1.held = false
	elseif not m1.buffered and now() >= m1.readyT - 0.02 then
		tryM1()
	end
end
RunService.Heartbeat:Connect(function(dt)
	local clock = os.clock()
	safe("movement", updateMovement, dt)
	safe("m1", updateM1)
	safe("float", updateFloats, clock)
	safe("tumble", updateTumble, clock)
	safe("aim", updateAimStream, clock)
	safe("passive", updatePassive, clock)
	if type(S.__update) == "function" then
		safe("Shared.__update", S.__update, clock, dt)
	end
	for name, fn in pairs(updates) do
		safe(name .. ".__update", fn, clock, dt)
	end
	-- PERKS: the CRIMSON GEAR copies (after the normal ones)
	if Perk.S and type(Perk.S.__update) == "function" then
		safe("SharedAlt.__update", Perk.S.__update, clock, dt)
	end
	for name, fn in pairs(Perk.updates) do
		safe(name .. ".alt.__update", fn, clock, dt)
	end
	safe("hud", updateHud, clock)
end)

-- the local character: capture its own movement numbers, and drop everything if it dies mid-move
local function hookCharacter(char)
	resetAll()
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	local base = char:GetAttribute("KitWalkSpeed")
	baseMove = {
		ws = (type(base) == "number" and base > 0) and base or (hum.WalkSpeed > 0 and hum.WalkSpeed or 16),
		jp = hum.JumpPower, jh = hum.JumpHeight,
	}
	wroteMovement = false
	m1.readyT, m1.combo = -1e9, 0
	hum.Died:Connect(function()
		if player.Character == char then
			resetAll()
		end
	end)
end
if player.Character then
	task.spawn(hookCharacter, player.Character)
end
player.CharacterAdded:Connect(hookCharacter)

-- switching away from the kit ends whatever was running
player:GetAttributeChangedSignal("Kit"):Connect(function()
	if not equipped() then
		resetAll()
	end
	m1.readyT, m1.combo = -1e9, 0
end)

-- Studio test hooks (GojoShared.ClientDebug): ("Luffy", skill) casts (M1 / Gatling / Rocket / Elephant / Gear5);
-- ("LuffyAim", Vector3 | nil) stands in for the camera aim, ("LuffyTarget", Vector3 | nil) for the cursor point,
-- ("LuffyFinisher", "Rifle" | "Axe" | "Pistol" | nil) forces the next hit-5 finisher
if RunService:IsStudio() then
	local dbg = ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Luffy" and type(arg) == "string" then
				if arg == "M1" then
					if equipped() and myChar() then
						sendM1()
					end
				else
					request(arg)
				end
			elseif cmd == "LuffyAim" then
				debugAim = (typeof(arg) == "Vector3" and arg.Magnitude > 0) and arg.Unit or nil
			elseif cmd == "LuffyTarget" then
				debugTarget = typeof(arg) == "Vector3" and arg or nil
			elseif cmd == "LuffyFinisher" then
				debugFinisher = (arg == "Rifle" or arg == "Axe" or arg == "Pistol") and arg or nil
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- the modules: Client.Shared (ctx.S; its Folder is set to ours), then Client.M1 / Gatling / Rocket / Elephant / Gear5,
-- each a function(ctx) returning { [kind] = handler, __update?, __reset? }. A missing move module is waited for in the
-- background (its skill draws nothing until it shows); a broken one is warned and skipped
local loaded = {}
local function requireModule(mod, label)
	if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		return false, label .. " is not a ModuleScript"
	end
	local ok, res = pcall(require, mod)
	if not ok then
		return false, label .. " failed to load: " .. tostring(res)
	end
	return true, res
end


local clientFolder = Kit:FindFirstChild("Client") or Kit:WaitForChild("Client", 10)
if not clientFolder then
	warn("[GomuClient] GomuKit.Client is missing; no move playback")
end

do
	local mod = clientFolder and (clientFolder:FindFirstChild("Shared") or clientFolder:WaitForChild("Shared", 10))
	if mod then
		local ok, res = requireModule(mod, "Client.Shared")
		if ok and type(res) == "table" then
			S = res
		else
			warn("[GomuClient] " .. (ok and "Client.Shared did not return a table" or res))
		end
	else
		warn("[GomuClient] Client.Shared is missing; the move modules get an empty S")
	end
	pcall(function()
		S.Folder = Folder
	end)
	ctx.S = S
end

---------------------------------------------------------------------------------------------------
-- PERKS (2026-11-07, kitsE): the Fighter Skins perk's "CRIMSON GEAR" (Config.SkinAlt, from Config.Skin). A caster whose
-- player has Skin == "Alt" (ShopService writes it; read when his broadcast arrives) is drawn, on every client, by a
-- SECOND copy of every move module built on Perk.ctx: PAL = this script's palette + SkinAlt.Palette, S = a private copy
-- of Client.Shared repainted with that palette. The skin is latched per player while his Gear Fifth runs (and 1 s
-- after), so one copy owns a mode look; ctx.players / Perk.ctx.players split Gear5's every-character look loop.
-- No Config.SkinAlt or a broken Shared copy -> no alt copies at all (everyone draws normally).
do
	local alt = type(CFG.SkinAlt) == "table" and type(CFG.SkinAlt.Palette) == "table" and CFG.SkinAlt.Palette or {}
	local pal = {}
	for k, v in pairs(PAL) do
		pal[k] = v
	end
	for k, v in pairs(alt) do
		pal[k] = v
	end
	-- this script's template aliases (see the top of the script) follow their repainted sources
	local aliases = { Reiatsu = "Straw", Crimson = "SunHot", Ember = "Sun", Black = "Ink", Blood = "StrawDark", Core = "Nika",
		Frost = "Impact", Robe = "VestDark", Ice = "Straw" }
	local cfgPal = type(CFG.Palette) == "table" and CFG.Palette or {}
	for name, src in pairs(aliases) do
		if cfgPal[name] == nil and alt[name] == nil and alt[src] ~= nil then
			pal[name] = alt[src]
		end
	end
	Perk.PAL = pal
	local mod = clientFolder and clientFolder:FindFirstChild("Shared")
	if mod and next(alt) ~= nil and next(S) ~= nil then
		local ok, res = pcall(function()
			local copy = mod:Clone()
			copy.Name = "SharedAltSkin"
			copy.Parent = script
			return require(copy)
		end)
		if ok and type(res) == "table" and res ~= S then
			if type(res.PAL) == "table" then
				-- the copy already holds its own defaults + Config.Palette: lay only the skin over it (and its
				-- template whoosh names, Reiatsu / Frost, follow the repainted Whoosh)
				for k, v in pairs(alt) do
					res.PAL[k] = v
				end
				if alt.Whoosh then
					for _, k in ipairs({ "Reiatsu", "Frost" }) do
						if cfgPal[k] == nil and alt[k] == nil then
							res.PAL[k] = alt.Whoosh
						end
					end
				end
			end
			pcall(function()
				res.Folder = Folder
			end)
			Perk.S = res
		else
			warn("[GomuClient] the CRIMSON GEAR copy of Client.Shared failed: " .. tostring(res))
		end
	end
end
local skinLatch = setmetatable({}, { __mode = "k" })
function Perk.isAlt(p)
	if not Perk.S or typeof(p) ~= "Instance" or not p:IsA("Player") then
		return false
	end
	local char = p.Character
	local untilT = char and char:GetAttribute("Gear5Until")
	local held = type(untilT) == "number" and untilT > now() - 1
	local l = skinLatch[p]
	if l == nil or not held then
		l = p:GetAttribute("Skin") == "Alt"
		skinLatch[p] = l
	end
	return l
end
local function playersFor(alt)
	return function()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if Perk.isAlt(p) == alt then
				table.insert(list, p)
			end
		end
		return list
	end
end
if Perk.S then
	ctx.players = playersFor(false)
	Perk.ctx = setmetatable({ PAL = Perk.PAL, S = Perk.S, players = playersFor(true), skin = "Alt" }, { __index = ctx })
end

local function register(name, factory)
	if type(factory) ~= "function" then
		warn("[GomuClient] Client." .. name .. " did not return a function")
		return
	end
	local ok, H = pcall(factory, ctx)
	if not ok then
		warn("[GomuClient] Client." .. name .. " failed to start: " .. tostring(H))
		return
	elseif type(H) ~= "table" then
		warn("[GomuClient] Client." .. name .. " did not return a handler table")
		return
	end
	for kind, fn in pairs(H) do
		if type(fn) == "function" then
			if kind == "__update" then
				updates[name] = fn
			elseif kind == "__reset" then
				resets[name] = fn
			elseif handlers[kind] then
				warn("[GomuClient] duplicate handler for " .. tostring(kind) .. " in " .. name .. " (kept the first)")
			else
				handlers[kind] = fn
			end
		end
	end
	-- PERKS: the same module again on the CRIMSON GEAR ctx
	if Perk.ctx then
		local okA, HA = pcall(factory, Perk.ctx)
		if okA and type(HA) == "table" then
			for kind, fn in pairs(HA) do
				if type(fn) == "function" then
					if kind == "__update" then
						Perk.updates[name] = fn
					elseif kind == "__reset" then
						Perk.resets[name] = fn
					elseif not Perk.handlers[kind] then
						Perk.handlers[kind] = fn
					end
				end
			end
		else
			warn("[GomuClient] Client." .. name .. " (CRIMSON GEAR copy) failed to start: " .. tostring(HA))
		end
	end
	table.insert(loaded, name)
end
local function loadMove(name, mod)
	local ok, res = requireModule(mod, "Client." .. name)
	if ok then
		register(name, res)
	else
		warn("[GomuClient] " .. res)
	end
end
for _, name in ipairs(MOVES) do
	local mod = clientFolder and clientFolder:FindFirstChild(name)
	if mod then
		loadMove(name, mod)
	elseif clientFolder then
		task.spawn(function()
			local m = clientFolder:WaitForChild(name, 60)
			if m then
				loadMove(name, m)
			else
				warn("[GomuClient] Client." .. name .. " is missing; its skill draws nothing")
			end
		end)
	end
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	if type(kind) ~= "string" or type(d) ~= "table" then
		return
	end
	safe("hud " .. kind, hudHook, kind, d)
	local h = handlers[kind]
	-- PERKS: a CRIMSON GEAR caster's broadcast goes to the alt copy of its module
	local ha = Perk.handlers[kind]
	if ha and d.userId ~= nil then
		local caster = Players:GetPlayerByUserId(tonumber(d.userId) or 0)
		if caster and Perk.isAlt(caster) then
			h = ha
		end
	end
	if h then
		local ok, err = pcall(h, d)
		if not ok then
			warnLimited(kind, err)
		end
	end
end)

print("[GomuClient] ready - M1: Gum-Gum string, Q: Gatling, E: Rocket, R: Elephant Gun, G: Gear Fifth (modules: "
	.. (#loaded > 0 and table.concat(loaded, ", ") or "none yet") .. ")")
