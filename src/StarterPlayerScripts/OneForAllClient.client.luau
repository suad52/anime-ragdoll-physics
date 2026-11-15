--!nocheck
-- OneForAllClient: input, ability bar, camera, local movement and the playback router of the One For All kit (Deku):
-- Delaware Smash: Air Force (Q), Detroit Smash (E), Blackwhip -> St. Louis Smash (R) and One For All: 1,000,000% (G),
-- which ends in the Full Cowl 100% mode. The server (ServerScriptService.OneForAllServer) is authoritative.
-- This script owns the HUD, the camera (shakes, lean, the scripted shot), the local body (root, mover, float,
-- Air Step), the passive and mode visuals, and hands every broadcast to the move modules in OneForAllKit.Client
-- (AirForce / Detroit / Blackwhip / Ultimate), which draw their own casts through the `ctx` table built below.
-- Flair pass: Full Cowl scales with speed (arcs, chest glow + sparks, footprints, eye trails, wind streaks), the Air
-- Step flips (a corkscrew for the mode's second step) over stacked shock discs, Full Cowl 100% reads dangerous (rim,
-- heat haze, heartbeat, crimson arcs, steam bursts, embers, cracked footfalls, an ignition burst, a longer burnout),
-- and every callout slams its kanji over an ink brush stroke with a two-tone starburst, edge speed lines and an
-- edge glow. Visual knobs: Config.Passive.FX / Passive.AirStepFX / Mode.FX (the Config child Flair_Mode).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
-- (2026-11-11 keybinds, owner: "have the option to have keybinds") every action key goes through HudShared.Keybinds:
-- logical() maps the physical key pressed back to the DEFAULT key its action is named by (CFG.Keys stays the
-- defaults), label() draws the key chips. With no rebinds it hands every key back unchanged, so default play is as
-- before. Movement / jump stay raw.
local Keybinds = require(game:GetService("ReplicatedStorage"):WaitForChild("HudShared"):WaitForChild("Keybinds"))

local player = Players.LocalPlayer
local Kit = ReplicatedStorage:WaitForChild("OneForAllKit")
local CFG = require(Kit:WaitForChild("Config"))
local Clips = require(Kit:WaitForChild("Clips"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")
local GojoClientFolder = ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client")
local Animator = require(GojoClientFolder:WaitForChild("ProceduralAnimator"))
local FX = require(GojoClientFolder:WaitForChild("GojoFX"))

local PAL = CFG.Palette
local SND = CFG.Sounds
local PASSIVE = CFG.Passive
local AIRSTEP = PASSIVE.AirStep
local MODE = CFG.Mode
local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2
local AIR = Enum.Material.Air
local SKILLS = { "AirForce", "Detroit", "Blackwhip", "OFA" }

-- everything this kit draws lives under the shared LocalFX folder, which every kit's raycasts already ignore
local Folder = Instance.new("Folder")
Folder.Name = "OneForAll"
Folder.Parent = workspace:WaitForChild("LocalFX", 10) or workspace -- GojoClient makes LocalFX as it starts

-- Client.Shared, filled in once it loads (every use below reads the live table)
local S = {}

-- (2026-11-07 perks) CRIMSON COWL, the alt skin: Config.AltPalette (Config child Skin_CrimsonCowl) over Config.Palette.
-- Everything a caster draws uses it when the caster's player has Skin == "Alt" (read at cast time, every client).
-- The move modules run twice (the loader at the bottom builds a second instance on Skin.ctx and the broadcast picks
-- by caster); the passive, the Air Step and the 100% mode below pick per character with Skin.pal. One table, so the
-- main chunk spends a single local on it
local Skin = { alt = table.clone(PAL), shared = nil, ctx = nil, handlers = {}, latch = {} }
for k, v in pairs(type(CFG.AltPalette) == "table" and CFG.AltPalette or {}) do
	Skin.alt[k] = v
end
function Skin.playerOf(who)
	if type(who) == "number" then
		local ok, p = pcall(Players.GetPlayerByUserId, Players, who)
		return ok and p or nil
	elseif typeof(who) == "Instance" then
		if who:IsA("Player") then
			return who
		elseif who:IsA("Model") then
			return Players:GetPlayerFromCharacter(who)
		end
	end
	return nil
end
function Skin.isAlt(p)
	return typeof(p) == "Instance" and p:IsA("Player") and p:GetAttribute("Skin") == "Alt" and p:GetAttribute("Kit") == CFG.KitId
end
-- the palette for a userId, a Player or a character
function Skin.pal(who)
	return Skin.isAlt(Skin.playerOf(who)) and Skin.alt or PAL
end
-- the Client.Shared instance that draws in `pal`
function Skin.S(pal)
	return (pal == Skin.alt and Skin.shared) or S
end
Players.PlayerRemoving:Connect(function(p)
	Skin.latch[p.UserId] = nil
end)

-- warnings rate-limited per source, so a broken per-frame layer cannot flood the output
local warnedAt = {}
local function warnLimited(tag, msg)
	local c = os.clock()
	if (warnedAt[tag] or -1e9) + 5 < c then
		warnedAt[tag] = c
		warn("[OneForAllClient] " .. tag .. ": " .. tostring(msg))
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

-- Config.Sounds' requested extras ship empty; until they are filled these stand in (key, pitch, volume scale)
local FALLBACK = {
	SubBoom = { "Boom", 0.6, 1 },
	Choir = { "Swell", 1.5, 0.4 },
	WhipCrack = { "Hit2", 1.8, 1 },
	WindRoar = { "Whoosh", 0.6, 1 },
	AirPop = { "Cannon", 1.35, 1 },
}
-- `id` is an asset id, or a Config.Sounds key ("SubBoom", "Boom" ...). An empty extra resolves to its fallback.
local function resolveSound(id, vol, speed)
	if type(id) ~= "string" then
		return nil
	end
	local key = (SND[id] ~= nil) and id or nil
	if not key then
		for k, v in pairs(SND) do
			if v == id and v ~= "" then
				key = k
				break
			end
		end
		if key == nil and id ~= "" then
			return id, vol, speed
		end
	end
	if key then
		local v = SND[key]
		if v == "" then
			local fb = FALLBACK[key]
			if not fb or not SND[fb[1]] or SND[fb[1]] == "" then
				return nil
			end
			return SND[fb[1]], (vol or 1) * fb[3], (speed == nil or speed == 1) and fb[2] or speed
		end
		return v, vol, speed
	end
	return nil
end

local function sound(id, parent, vol, speed)
	if not parent or not parent.Parent then
		return
	end
	local sid, v, sp = resolveSound(id, vol, speed)
	if not sid then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = sid
	s.Volume = v or 1
	s.PlaybackSpeed = sp or 1
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

local function soundAt(id, pos, vol, speed)
	if not resolveSound(id, vol, speed) then
		return
	end
	return sound(id, FX.anchor(Folder, pos, 8), vol, speed)
end

local function castFolder(name, life)
	local f = Instance.new("Folder")
	f.Name = name or "Cast"
	f.Parent = Folder
	Debris:AddItem(f, life or 8)
	return f
end

local function playClip(char, clip, startAt)
	if type(clip) == "string" then
		clip = Clips[clip]
	end
	if char and clip and (startAt or 0) < clip.length then
		return Animator.play(char, clip, { startAt = math.max(startAt or 0, 0) })
	end
end

-- animation hit-stop: the pose hangs for `secs`, then plays on (§3.13)
local function freeze(track, secs)
	if not track then
		return
	end
	local prev = track.speed
	if not prev or prev == 0 then
		prev = 1
	end
	track.speed = 0
	task.delay(secs or 0.07, function()
		if track then
			track.speed = prev
		end
	end)
end

-- end-of-life for anything a Shared builder hands back (an Instance, or an object with destroy/Destroy)
local function kill(h)
	if h == nil then
		return
	end
	if typeof(h) == "Instance" then
		h:Destroy()
		return
	end
	if type(h) == "table" then
		local fn = h.destroy or h.Destroy
		if type(fn) == "function" then
			pcall(fn, h)
			return
		end
		for _, v in pairs(h) do
			if typeof(v) == "Instance" then
				v:Destroy()
			end
		end
	end
end

-- the emitters inside a steam attachment (§3.3)
local function emittersOf(h)
	local list = {}
	if typeof(h) == "Instance" then
		if h:IsA("ParticleEmitter") then
			table.insert(list, h)
		end
		for _, d in ipairs(h:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				table.insert(list, d)
			end
		end
	end
	return list
end
local function endSteam(h, after)
	if typeof(h) == "Instance" then
		for _, e in ipairs(emittersOf(h)) do
			e.Rate = 0
		end
		Debris:AddItem(h, after or 1.5)
	elseif type(h) == "table" and type(h.stop) == "function" then
		pcall(h.stop, h) -- Shared's steam handle: rate 0, cleaned up once the last puff is gone
	else
		kill(h)
	end
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
			color = color or PAL.Cowl, width = width or 0.06, jag = 0.35, segments = 4, life = 0.09, restrike = 1,
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
				c.CFrame = (offset and (CFrame.new(offset) * d.CFrame)) or d.CFrame
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
-- camera: shakes, FOV kicks and the lean, as short timed envelopes summed every frame (§3C, §3.14)
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
RunService:BindToRenderStep("OFACameraUndo", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = workspace.CurrentCamera
	if lastShake and cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = cam.CFrame * lastShake:Inverse()
	end
	lastShake = nil
end)
RunService:BindToRenderStep("OFACamera", Enum.RenderPriority.Camera.Value + 2, function()
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
	local dur = math.max(tonumber(spec.dur) or 1, 0.05)
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
		for _, p in ipairs(char:GetDescendants()) do
			if (p:IsA("BasePart") and p.Name ~= "HumanoidRootPart") or p:IsA("Decal") then
				p.LocalTransparencyModifier = 0
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
				FX.flash(PAL.Cowl, 0.08, 0.08)
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
gui.Name = "OneForAllHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- the edge vignette sits on its own layer under every other UI
local vgui = Instance.new("ScreenGui")
vgui.Name = "OneForAllVignette"
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

-- the callout's pieces live in this block; the per-frame HUD reads the title state through TT
local showTitle, callout, bumpTally
local TT = { shakeUntil = 0, shaken = false, jolt = 0, fadeAt = 0, holder = nil }
do
	local titleHolder = Instance.new("Frame")
	titleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	titleHolder.Position = UDim2.fromScale(0.5, 0.27)
	titleHolder.Size = UDim2.fromScale(0.86, 0.15)
	titleHolder.BackgroundTransparency = 1
	titleHolder.ZIndex = 40
	titleHolder.Parent = gui
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = titleHolder

	-- the ink brush stroke swept under the move name, with two thin bristle strokes
	local brush = Instance.new("Frame")
	brush.Name = "Brush"
	brush.AnchorPoint = Vector2.new(0, 0.5)
	brush.Position = UDim2.fromScale(0.5, 0.66)
	brush.Size = UDim2.fromScale(0, 0.6)
	brush.BorderSizePixel = 0
	brush.BackgroundColor3 = BLACK
	brush.BackgroundTransparency = 1
	brush.Rotation = -2
	brush.ZIndex = 39
	brush.Parent = titleHolder
	local brushGrad = Instance.new("UIGradient")
	brushGrad.Transparency = NumberSequence.new({ -- ragged dry-brush ends
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.025, 0.6), NumberSequenceKeypoint.new(0.05, 0.12),
		NumberSequenceKeypoint.new(0.08, 0.3), NumberSequenceKeypoint.new(0.12, 0), NumberSequenceKeypoint.new(0.86, 0),
		NumberSequenceKeypoint.new(0.91, 0.25), NumberSequenceKeypoint.new(0.95, 0.1), NumberSequenceKeypoint.new(0.98, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	brushGrad.Parent = brush
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
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.2), NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = b
		bristles[i] = b
	end

	local title = uiText(titleHolder, { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.3), Text = "", TextTransparency = 1, ZIndex = 41 })
	local titleStroke = uiStroke(title, BLACK, 3, 1)
	local titleGrad = Instance.new("UIGradient")
	titleGrad.Rotation = 90
	titleGrad.Parent = title
	-- the kanji rides its own holder so it can slam in (scale 3 -> 0.9 -> 1) with an echo blown off it
	local kanjiHolder = Instance.new("Frame")
	kanjiHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	kanjiHolder.Position = UDim2.fromScale(0.5, 0.16)
	kanjiHolder.Size = UDim2.fromScale(1, 0.32)
	kanjiHolder.BackgroundTransparency = 1
	kanjiHolder.ZIndex = 41
	kanjiHolder.Parent = titleHolder
	local kanjiScale = Instance.new("UIScale")
	kanjiScale.Parent = kanjiHolder
	local kanji = uiText(kanjiHolder, { Size = UDim2.fromScale(1, 1), Text = "", TextTransparency = 1, ZIndex = 42 })
	local kanjiStroke = uiStroke(kanji, BLACK, 2, 1)
	local kanjiEcho = uiText(kanjiHolder, { Name = "Echo", Size = UDim2.fromScale(1, 1), Text = "", TextTransparency = 1, ZIndex = 41 })
	local echoScale = Instance.new("UIScale")
	echoScale.Parent = kanjiEcho
	local titleToken

	-- the starburst: 24 rays in two colours behind the title, thrown out (and twisted) on every title (§10.2)
	local burst = Instance.new("Frame")
	burst.Name = "Starburst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.2925) -- the centre of the title line
	burst.Size = UDim2.fromOffset(0, 0)
	burst.BackgroundTransparency = 1
	burst.ZIndex = 38
	burst.Parent = gui
	local burstScale = Instance.new("UIScale")
	burstScale.Parent = burst
	local rays = {}
	for i = 1, 24 do
		local r = Instance.new("Frame")
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.BorderSizePixel = 0
		r.BackgroundTransparency = 1
		r.ZIndex = 38
		r.Parent = burst
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = r
		rays[i] = r
	end
	local function popBurst(color, color2, big)
		local info = TweenInfo.new(big and 0.5 or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for i, r in ipairs(rays) do
			local a = (i - 1) / #rays * TAU + (math.random() - 0.5) * 0.25
			local long = i % 2 == 1
			local len = (long and 150 or 90) + math.random() * (long and 140 or 70)
			if big then
				len *= 1.3
			end
			local th = long and (4 + math.random() * 4) or (2 + math.random() * 2)
			local c = (long and 70 or 95) + len / 2
			r.Position = UDim2.fromOffset(math.cos(a) * c, math.sin(a) * c)
			r.Size = UDim2.fromOffset(len, th)
			r.Rotation = math.deg(a)
			r.BackgroundColor3 = long and color or color2
			r.BackgroundTransparency = long and 0 or 0.15
			TweenService:Create(r, info, { BackgroundTransparency = 1 }):Play()
		end
		burst.Rotation = -6
		tween(burst, 0.5, { Rotation = 6 }, Enum.EasingStyle.Quart)
		burstScale.Scale = 0.4
		tween(burstScale, 0.25, { Scale = big and 1.4 or 1.25 }, Enum.EasingStyle.Quart)
	end

	-- the hit tally under the title: "×n", or "×n SMASHED" for the ultimate
	local tallyLabel = uiText(gui, {
		Name = "HitTally", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.352), Size = UDim2.fromScale(0.3, 0.045),
		Text = "", TextTransparency = 1, TextColor3 = PAL.Spark, ZIndex = 41,
	})
	local tallyStroke = uiStroke(tallyLabel, Color3.fromRGB(6, 26, 16), 2, 1)
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
		tallyLabel.Text = "×" .. tally.n .. (tally.smashed and " SMASHED" or "")
		tallyLabel.TextTransparency, tallyStroke.Transparency = 0, 0
		tallyLabel.TextColor3 = WHITE
		tween(tallyLabel, 0.25, { TextColor3 = PAL.Spark })
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

	local ULT_TITLES = {}
	ULT_TITLES[CFG.Labels.OFA or "ONE FOR ALL"] = true
	if CFG.Callouts.Million and CFG.Callouts.Million.text then
		ULT_TITLES[CFG.Callouts.Million.text] = true
	end

	-- how much of the holder the brush covers: estimated from the text now, corrected from TextBounds a frame later
	local function brushWidth(text)
		return math.clamp(0.16 + #(text or "") * 0.034, 0.36, 0.96)
	end

	function showTitle(text, kanjiText, c0, c1)
		c0 = c0 or WHITE
		c1 = c1 or PAL.Cowl
		local token = {}
		titleToken = token
		local big = ULT_TITLES[text] == true
		local clock = os.clock()
		title.Text = text or ""
		kanji.Text = kanjiText or ""
		kanjiEcho.Text = kanji.Text
		kanji.TextColor3 = c0:Lerp(c1, 0.45)
		kanjiEcho.TextColor3 = c1
		titleGrad.Color = ColorSequence.new(c0, c1)
		local dark = c1:Lerp(BLACK, 0.82)
		titleStroke.Color, kanjiStroke.Color = dark, dark
		-- the name punches in (scale 1.7 -> 1, Back) and slides home from the right
		title.TextTransparency, titleStroke.Transparency = 0, 0
		titleScale.Scale = 1.7
		titleHolder.Rotation = -5
		tween(titleScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(titleHolder, 0.16, { Rotation = 0 })
		title.Position = UDim2.new(0, 90, 0.3, 0)
		tween(title, 0.2, { Position = UDim2.fromScale(0, 0.3) }, Enum.EasingStyle.Quint)
		-- the kanji slams down onto it: scale 3 -> 0.9 (Quad In), then a Back settle with an echo blown off and a jolt
		kanji.TextTransparency, kanjiStroke.Transparency = 1, 1
		kanjiEcho.TextTransparency = 1
		kanjiScale.Scale = 3
		kanjiHolder.Rotation = -14
		kanjiHolder.Position = UDim2.fromScale(0.5, 0.16)
		tween(kanji, 0.07, { TextTransparency = 0 })
		tween(kanjiStroke, 0.07, { Transparency = 0 })
		tween(kanjiScale, 0.09, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(kanjiHolder, 0.09, { Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.09, function()
			if titleToken ~= token then
				return
			end
			tween(kanjiScale, 0.16, { Scale = 1 }, Enum.EasingStyle.Back)
			kanjiEcho.TextTransparency = 0.3
			echoScale.Scale = 1
			tween(echoScale, 0.32, { Scale = 1.75 })
			tween(kanjiEcho, 0.32, { TextTransparency = 1 })
			TT.jolt = os.clock() + 0.08
		end)
		-- the ink stroke sweeps in under the name, left to right, a bristle stroke above and below it
		local w = brushWidth(text)
		local bh = big and 0.72 or 0.6
		brush.BackgroundColor3 = c1:Lerp(BLACK, big and 0.72 or 0.8)
		brush.BackgroundTransparency = big and 0.14 or 0.24
		brush.Position = UDim2.fromScale(0.5 - w / 2, 0.66)
		brush.Size = UDim2.fromScale(0, bh)
		tween(brush, 0.18, { Size = UDim2.fromScale(w, bh) }, Enum.EasingStyle.Quart)
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
					brush.Position = UDim2.fromScale(0.5 - w2 / 2, 0.66)
					tween(brush, 0.15, { Size = UDim2.fromScale(w2, bh) }, Enum.EasingStyle.Quart)
				end
			end
		end)
		popBurst(c1, c0:Lerp(c1, 0.3), big)
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
			for _, o in ipairs({ title, kanji }) do
				TweenService:Create(o, info, { TextTransparency = 1 }):Play()
			end
			for _, o in ipairs({ titleStroke, kanjiStroke }) do
				TweenService:Create(o, info, { Transparency = 1 }):Play()
			end
			tween(titleScale, 0.45, { Scale = 1.06 })
			tween(kanjiHolder, 0.45, { Position = UDim2.fromScale(0.5, 0.1) })
			tween(brush, 0.4, { BackgroundTransparency = 1 })
			for _, b in ipairs(bristles) do
				tween(b, 0.3, { BackgroundTransparency = 1 })
			end
		end)
	end
	-- a move's callout; `skill` is a Config.Callouts key (AirForce ... or the mid-cast titles StLouis / Million ...)
	function callout(skill, sub)
		local co = CFG.Callouts[skill]
		if not co then
			if sub or CFG.Labels[skill] then
				showTitle(sub or CFG.Labels[skill], nil, WHITE, PAL.Cowl)
			end
			return
		end
		showTitle(sub or co.text or CFG.Labels[skill] or tostring(skill), co.kanji, co.c0, co.c1)
	end
	TT.holder = titleHolder
end

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
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -172), Size = UDim2.new(0, 186, 0, 18),
	Text = "", TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack, TextColor3 = PAL.Crimson,
})
uiStroke(status, PAL.Blood, 1.5, 0.2)
local statusScale = Instance.new("UIScale")
statusScale.Parent = status
-- the mode's timer: a thin crimson bar between the status and the ultimate's button, draining to nothing
local modeBar = Instance.new("Frame")
modeBar.Name = "ModeTimer"
modeBar.AnchorPoint = Vector2.new(1, 1)
modeBar.Position = UDim2.new(1, 0, 1, -169)
modeBar.Size = UDim2.fromOffset(186, 3)
modeBar.BackgroundColor3 = PAL.Blood
modeBar.BackgroundTransparency = 0.45
modeBar.BorderSizePixel = 0
modeBar.Visible = false
modeBar.Parent = bar
uiCorner(modeBar, UDim.new(1, 0))
local modeFill = Instance.new("Frame")
modeFill.Name = "Fill"
modeFill.AnchorPoint = Vector2.new(1, 0)
modeFill.Position = UDim2.fromScale(1, 0)
modeFill.Size = UDim2.fromScale(1, 1)
modeFill.BackgroundColor3 = PAL.Crimson
modeFill.BorderSizePixel = 0
modeFill.Parent = modeBar
uiCorner(modeFill, UDim.new(1, 0))

local cooldownEnd = { AirForce = 0, Detroit = 0, Blackwhip = 0, OFA = 0 }
local cooldownLen = {}
for _, k in ipairs(SKILLS) do
	cooldownLen[k] = (CFG[k] and CFG[k].Cooldown) or 1
end
local buttons = {}

-- the world point under the cursor (the screen centre on touch-only devices)
local debugAim, debugTarget
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

local function request(skill, fromButton)
	if not equipped() or not myChar() then
		return
	end
	local aim = debugAim or workspace.CurrentCamera.CFrame.LookVector
	Request:FireServer(skill, { aim = aim, target = cursorTarget(fromButton) })
end

local function skillButton(id, size, x)
	local co = CFG.Callouts[id]
	local big = size > 80
	local b = Instance.new("TextButton")
	b.Name = id
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.new(1, x, 1, -16)
	b.BackgroundColor3 = darken(co.c1:Lerp(PAL.Suit, 0.6), 0.76)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(140, 150, 146))
	shade.Rotation = 90
	shade.Parent = b
	local st = uiStroke(b, co.c1:Lerp(WHITE, 0.4), 2, 0.1)
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
	uiText(b, { Size = UDim2.new(1, -8, 0, big and 15 or 11), Position = UDim2.new(0, 4, 1, big and -21 or -17), Text = CFG.Labels[id], ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = co.c1:Lerp(BLACK, 0.86)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11 keybinds) the chip names the key the player bound to this action, and follows a rebind
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys[id]), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys[id])
	end)
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
	buttons[id] = { cd = cd, cdText = cdText, scale = scale, stroke = st, baseStroke = st.Color, frame = b, color = co.c1, color2 = co.c0, ready = true }
	b.Activated:Connect(function()
		request(id, true)
	end)
end
-- the same slots as the other kits: R in the left slot, Q next to it, the shared punch, E on the big button
skillButton("Blackwhip", 72, -280)
skillButton("AirForce", 72, -198)
skillButton("Detroit", 104, 0)

-- the shared M1 punch (thrown by GojoClient's combo), with the Air Step pips above it
local pips = {}
local pipScales = {}
do
	local b = Instance.new("TextButton")
	b.Name = "Punch"
	b.AutoButtonColor = false
	b.Text = ""
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromOffset(72, 72)
	b.Position = UDim2.new(1, -116, 1, -16)
	b.BackgroundColor3 = darken(PAL.Suit, 0.9)
	b.Parent = bar
	uiCorner(b, UDim.new(0, 18))
	uiStroke(b, PAL.Spark, 2, 0.2)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.42)
	orb.Size = UDim2.fromScale(0.42, 0.42)
	orb.BackgroundColor3 = WHITE
	orb.Parent = b
	uiCorner(orb, UDim.new(1, 0))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(PAL.Core, PAL.Cowl)
	g.Rotation = 45
	g.Parent = orb
	uiText(b, { Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -20), Text = "PUNCH", ZIndex = 2 })
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 20)
	chip.Position = UDim2.fromOffset(6, 6)
	chip.BackgroundColor3 = darken(PAL.Suit, 0.35)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	uiText(chip, { Size = UDim2.fromScale(1, 1), Text = "M1", Font = Enum.Font.GothamBold, ZIndex = 2 })
	b.Activated:Connect(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local gojo = scripts and scripts:FindFirstChild("GojoClient")
		local bind = gojo and gojo:FindFirstChild("SharedPunch")
		if bind then
			bind:Fire()
		end
	end)
	for i = 1, 2 do
		local p = Instance.new("Frame")
		p.Name = "AirStepPip" .. i
		p.AnchorPoint = Vector2.new(0.5, 1)
		p.Size = UDim2.fromOffset(8, 8)
		p.Position = UDim2.new(1, -152 + (i == 1 and -6 or 6), 1, -94)
		p.BackgroundColor3 = PAL.Cowl
		p.BorderSizePixel = 0
		p.Parent = bar
		uiCorner(p, UDim.new(1, 0))
		uiStroke(p, PAL.Emerald, 1, 0.3)
		pips[i] = p
		local ps = Instance.new("UIScale")
		ps.Parent = p
		pipScales[i] = ps
	end
end

-- the One For All ultimate on its own wide button above the row
do
	local co = CFG.Callouts.OFA
	local b = Instance.new("TextButton")
	b.Name = "OFA"
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
	g.Color = ColorSequence.new(darken(PAL.Crimson, 0.16), darken(PAL.Crimson, 0.5))
	g.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromOffset(24, 22)
	chip.Position = UDim2.fromOffset(7, 7)
	chip.BackgroundColor3 = co.c1:Lerp(BLACK, 0.9)
	chip.Parent = b
	uiCorner(chip, UDim.new(0, 6))
	-- (2026-11-11 keybinds) the chip names the key the player bound to this action, and follows a rebind
	local keyText = uiText(chip, { Size = UDim2.fromScale(1, 1), Text = Keybinds.label(CFG.Keys.OFA), Font = Enum.Font.GothamBold, ZIndex = 2 })
	Keybinds.Changed:Connect(function()
		keyText.Text = Keybinds.label(CFG.Keys.OFA)
	end)
	uiText(b, { Size = UDim2.new(1, -44, 0, 16), Position = UDim2.fromOffset(38, 4), Text = CFG.Labels.OFA, ZIndex = 2 })
	uiText(b, { Size = UDim2.new(1, -44, 0, 11), Position = UDim2.fromOffset(38, 21), Text = co.sub or "", Font = Enum.Font.GothamBold, TextColor3 = co.c0:Lerp(co.c1, 0.3), ZIndex = 2 })
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
	buttons.OFA = {
		cd = cd, cdText = cdText, scale = scale, stroke = st, baseStroke = st.Color, frame = b, color = co.c1, color2 = co.c0,
		ready = true, horizontal = true,
	}
	b.Activated:Connect(function()
		request("OFA", true)
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

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or not equipped() then
		return
	end
	-- (2026-11-11 keybinds) match the ACTION the pressed key is bound to (its default key), not the raw key
	local key = Keybinds.logical(input.KeyCode)
	for skill, defaultKey in pairs(CFG.Keys) do
		if key == defaultKey then
			request(skill)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- the local body: rooting during moves, the Full Cowl speed boost, the scripted mover, blinks and the float
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

local function inMode(char)
	if not char then
		return false
	end
	local v = char:GetAttribute("OFAMode")
	return type(v) == "number" and v > now()
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

-- WalkSpeed / jump / AutoRotate are derived from the kit's state every frame (never saved and restored), so a
-- mode that starts while rooted can't be lost to a restore. Full Cowl x1.2 / x1.12 always; 100% mode x1.9 / x1.35
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
	local rooted = os.clock() < rootUntil
	local mode = inMode(char)
	local ws = rooted and 0 or baseMove.ws * (mode and MODE.WalkSpeedMul or PASSIVE.WalkSpeedMul)
	local jk = rooted and 0 or (mode and MODE.JumpMul or PASSIVE.JumpMul)
	if hum.WalkSpeed ~= ws then
		hum.WalkSpeed = ws
	end
	if hum.JumpPower ~= baseMove.jp * jk then
		hum.JumpPower = baseMove.jp * jk
	end
	if hum.JumpHeight ~= baseMove.jh * jk * jk then
		hum.JumpHeight = baseMove.jh * jk * jk
	end
	if hum.AutoRotate == rooted then
		hum.AutoRotate = not rooted
	end
	if rooted and faceDir and not mover then
		local want = CFrame.lookAt(Vector3.zero, faceDir)
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

-- the scripted move (§3.14 mover): m = { char, t0, dur, from, to, face, vel?, ease = {style, dir}?, hold?, exitVel? }
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
-- `maxSecs` pass, it dies, or the cast is cancelled (§3.14)
local function float(hrp, gravityMul, maxSecs)
	if not hrp or not hrp.Parent then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "OFAFloat"
	att.Parent = hrp
	local vf = Instance.new("VectorForce")
	vf.Name = "OFAFloat"
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
-- PASSIVE: Full Cowl (§4, flair pass). Air Step is client-owned and predicted; the server only relays it to everyone
-- else. Everything scales with an intensity k (0 standing still .. 1 at Passive.FX.FullSpeed): the crawl quickens and
-- runs down the legs, the chest glows and sheds sparks, the feet print lightning, the eyes streak green at a sprint,
-- wind peels off the shoulders. Standing still, One For All surges down an arm now and then
local PFX = type(PASSIVE.FX) == "table" and PASSIVE.FX or {}
local AFX = type(PASSIVE.AirStepFX) == "table" and PASSIVE.AirStepFX or {}
local function pnum(k, d)
	local v = PFX[k]
	return type(v) == "number" and v or d
end
local function anum(k, d)
	local v = AFX[k]
	return type(v) == "number" and v or d
end
local function between(r, a, b)
	if type(r) == "table" and type(r[1]) == "number" then
		a, b = r[1], r[2] or r[1]
	end
	return a + math.random() * (b - a)
end
local function lerp(a, b, k)
	return a + (b - a) * k
end
local NSK = FX.nsk or function(list)
	local kp = {}
	for _, v in ipairs(list) do
		table.insert(kp, NumberSequenceKeypoint.new(v[1], v[2]))
	end
	return NumberSequence.new(kp)
end
local TEX = FX.TEX or {}
local LIMB = { -- limb chains (hand -> shoulder, foot -> hip) for the crawling arcs, and the extremities
	ARM_R = { "RightHand", "RightLowerArm", "RightUpperArm" }, ARM_L = { "LeftHand", "LeftLowerArm", "LeftUpperArm" },
	LEG_R = { "RightFoot", "RightLowerLeg", "RightUpperLeg" }, LEG_L = { "LeftFoot", "LeftLowerLeg", "LeftUpperLeg" },
	EXTREMES = { "RightHand", "LeftHand", "RightFoot", "LeftFoot" },
}
LIMB.CHAINS = { LIMB.ARM_R, LIMB.ARM_L, LIMB.LEG_R, LIMB.LEG_L }

local function glowSize(pos, size)
	return (type(S.glowFor) == "function") and S.glowFor(pos, size) or size * math.clamp(camDist(pos) / 30, 0.45, 1)
end
local function limbArc(model, limbs, color, width)
	if type(S.limbArc) == "function" then
		S.limbArc(Folder, model, limbs, color, width)
	else
		local a = model:FindFirstChild(limbs[math.random(#limbs)])
		local b = model:FindFirstChild(limbs[math.random(#limbs)])
		if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
			FX.bolt(Folder, a.Position + FX.randUnit() * 0.35, b.Position + FX.randUnit() * 0.35, {
				color = color, width = width or 0.05, jag = 0.4, segments = 4, life = 0.08, restrike = 1,
			})
		end
	end
end

local air = { leftAt = nil, steps = 0, lastReq = 0, ready = 0 }
local passiveFx = {} -- [char] = { trails, torsoTrail, light, crackle, eyes, next*, lowFoot, lastPrint, boostUntil, mode }
local lastStepAt = {} -- [userId] = os.clock() of their last Air Step (the second one in mode corkscrews)

local function stepsMax(char)
	return inMode(char) and (AIRSTEP.ModeSteps or 2) or (AIRSTEP.Steps or 1)
end

-- the passive's builders live in this block; airStepFx and updatePassive are its entry points
local airStepFx, updatePassive
do
	local NEON = Enum.Material.Neon
	-- a flat neon sliver (footprints, ground cracks) that thins and fades where it lies
	local function neonBit(name, size, cf, color, tr, life, toSize)
		local p = FX.part(name, Enum.PartType.Block, NEON, color, nil)
		p.Size = size
		p.CFrame = cf
		p.Transparency = tr
		p.Parent = Folder
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1, Size = toSize or size,
		}):Play()
		Debris:AddItem(p, life + 0.1)
		return p
	end

	-- a thin disc of slapped air: a flat cylinder that spreads and fades (8 studs at most, so it never walls the view)
	local function shockDisc(pos, from, to, color, life, tr)
		local p = FX.part("ShockDisc", Enum.PartType.Cylinder, NEON, color, nil)
		p.Size = Vector3.new(0.1, from, from)
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2) -- the cylinder's axis (X) stood up
		p.Transparency = tr or 0.7
		p.Parent = Folder
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.04, to, to), Transparency = 1,
		}):Play()
		Debris:AddItem(p, life + 0.1)
	end

	-- the flip draws itself: the foot trails light up and the hands drag two more for `secs`
	local function boostTrails(char, secs)
		local PAL = Skin.pal(char)
		local st = passiveFx[char]
		if st then
			st.boostUntil = os.clock() + secs
		end
		for _, n in ipairs({ "RightHand", "LeftHand" }) do
			local hand = char:FindFirstChild(n)
			if hand and hand:IsA("BasePart") then
				local mode = inMode(char)
				local tr = FX.trail(hand, mode and cs(PAL.Crimson, PAL.Cowl) or cs(PAL.Cowl, PAL.Air), 0.3, 0.2, { alpha = 0.3, tail = 0 })
				local a0, a1 = tr.Attachment0, tr.Attachment1
				task.delay(secs, function()
					if tr.Parent then
						tr.Enabled = false
					end
				end)
				Debris:AddItem(tr, secs + 0.3)
				Debris:AddItem(a0, secs + 0.3)
				Debris:AddItem(a1, secs + 0.3)
			end
		end
	end

	-- the Air Step: three shock rings stacked down under his feet and staggered, a disc of slapped air, a down-blast of
	-- streaks, lightning forking off the soles, a distortion shell, falling sparks, two afterimages and the flip trails
	function airStepFx(char, pos, mode, spin)
		if not char or typeof(pos) ~= "Vector3" then
			return
		end
		local PAL = Skin.pal(char)
		local fp = pos - UP * 3
		local col = mode and PAL.Crimson or PAL.Cowl
		local heavy = camDist(fp) < anum("HeavyGate", 90)
		FX.ring(Folder, fp, UP, 1, anum("RingTo", 12), PAL.Air, 0.32, { alpha = 0.15 })
		FX.ring(Folder, fp, UP, 0.5, 7, col, 0.24)
		shockDisc(fp, 1.2, anum("DiscTo", 8), PAL.Air, 0.26, 0.72)
		task.delay(0.05, function()
			FX.ring(Folder, fp - UP * 0.7, UP, 0.6, 8, PAL.Air, 0.28, { alpha = 0.3 })
		end)
		task.delay(0.1, function()
			FX.ring(Folder, fp - UP * 1.5, UP, 0.4, 5, col, 0.22, { alpha = 0.35 })
		end)
		FX.streaks(Folder, fp, { dir = -UP, spread = 25, color = WHITE, color2 = PAL.Air, count = 16, speed = { 60, 110 }, size = 0.35, life = 0.25 })
		FX.glow(Folder, fp, glowSize(fp, 4.5), col, 0.2, { alpha = 0.4 })
		FX.light(Folder, fp, col, 3, 14, 0.25)
		ghost(char, col, 0.55, 0.32)
		if heavy then
			FX.streaks(Folder, fp, { dir = -UP, spread = 80, color = PAL.Air, color2 = col, count = 10, speed = { 35, 65 }, size = 0.22, life = 0.22 })
			FX.arcs(Folder, fp + UP * 0.4, 3, { outward = true, count = 3, colors = { col, PAL.Core }, width = 0.05, life = 0.1 })
			FX.shell(Folder, fp, 0.8, 4.2, PAL.Air, 0.24, Enum.Material.ForceField)
			FX.sparks(Folder, fp, { dir = -UP, spread = 65, color = PAL.Spark, color2 = col, count = 10, speed = { 14, 32 }, size = 0.3, life = 0.5 })
			for _ = 1, 2 do
				bodyArc(Folder, char, (math.random() < 0.6) and col or PAL.Core, 0.06)
			end
			task.delay(0.09, function()
				ghost(char, PAL.Air, 0.72, 0.28)
			end)
			if spin then
				-- the corkscrew throws a twist of air out sideways
				FX.streaks(Folder, pos, { color = PAL.Air, color2 = col, count = 12, speed = { 30, 50 }, size = 0.2, life = 0.2 })
				FX.ring(Folder, pos, UP, 1, 6, col, 0.3, { alpha = 0.3 })
			end
			boostTrails(char, anum("TrailSecs", 0.5))
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			sound("AirPop", hrp, 0.35, 1.8)
			sound("Whoosh", hrp, 0.4, spin and 1.3 or 1.6)
			sound("Zap", hrp, 0.18, mode and 1.2 or 1.7)
		end
	end

	-- two green eyes streaking light (a Trail and a glow on attachments on the head; the mode draws its own crimson ones)
	local function makeEyes(char)
		local PAL = Skin.pal(char)
		local head = char:FindFirstChild("Head")
		if not head or not head:IsA("BasePart") then
			return nil
		end
		local s = head.Size
		local e = { head = head, on = false, items = {}, trails = {}, glows = {} }
		for _, sx in ipairs({ 0.2, -0.2 }) do
			local p = Vector3.new(sx * s.X, 0.08 * s.Y, -0.5 * s.Z - 0.03)
			local a0 = Instance.new("Attachment")
			a0.Name = "OFAEyeTop"
			a0.Position = p + Vector3.new(0, 0.035, 0)
			a0.Parent = head
			local a1 = Instance.new("Attachment")
			a1.Name = "OFAEyeBottom"
			a1.Position = p - Vector3.new(0, 0.035, 0)
			a1.Parent = head
			local tr = Instance.new("Trail")
			tr.Name = "OFAEyeTrail"
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = cs(PAL.Core, PAL.Cowl)
			tr.Lifetime = 0.22
			tr.LightEmission = 1
			tr.LightInfluence = 0
			tr.FaceCamera = true
			tr.MinLength = 0.02
			tr.Transparency = NumberSequence.new(0.05, 1)
			tr.WidthScale = NumberSequence.new(1, 0.2)
			tr.Enabled = false
			tr.Parent = head
			local g = FX.emitter(a0, {
				Texture = TEX.glow, Color = cs(PAL.Cowl), Size = NumberSequence.new(0.34), Lifetime = NumberRange.new(0.1),
				Speed = NumberRange.new(0), Rate = 30, LockedToPart = true, Transparency = NumberSequence.new(0.25), ZOffset = 0.3,
				Brightness = 2,
			})
			g.Name = "OFAEyeGlow"
			g.Enabled = false
			table.insert(e.items, a0)
			table.insert(e.items, a1)
			table.insert(e.trails, tr)
			table.insert(e.glows, g)
		end
		function e.set(on)
			if e.on == on then
				return
			end
			e.on = on
			for _, tr in ipairs(e.trails) do
				tr.Enabled = on
			end
			for _, g in ipairs(e.glows) do
				g.Enabled = on
			end
		end
		function e.destroy()
			for _, tr in ipairs(e.trails) do
				tr:Destroy()
			end
			for _, x in ipairs(e.items) do
				x:Destroy() -- the attachments (each eye's glow emitter goes with its attachment)
			end
		end
		return e
	end

	-- a lightning footprint where a foot plants: a glowing print, a small ring, two short bolts across the ground. In
	-- 100% mode the print is crimson and the ground cracks: four glowing fissures, a puff of dust and embers
	local function footprint(char, foot, velDir, mode, k)
		local PAL = Skin.pal(char)
		local hit = FX.groundHit(foot.Position + UP * 0.5, 3)
		if not hit then
			return
		end
		local n = hit.Normal
		local p = hit.Position + n * 0.04
		local col = mode and PAL.Crimson or PAL.Cowl
		local fwd = velDir - n * velDir:Dot(n)
		fwd = fwd.Magnitude > 1e-3 and fwd.Unit or flat(foot.CFrame.LookVector)
		local side = fwd:Cross(n)
		neonBit("CowlPrint", Vector3.new(0.6, 0.05, 1.05), CFrame.lookAt(p, p + fwd, n), col, 0.3, mode and 1.1 or 0.7, Vector3.new(0.3, 0.02, 0.8))
		FX.ring(Folder, p + n * 0.05, n, 0.3, 2.4 + k, col, 0.22, { alpha = 0.45 })
		for i = 1, (mode and 3 or 2) do
			local d = (side * ((i % 2 == 0) and 1 or -1) + fwd * (math.random() - 0.4)).Unit
			local a = p + n * 0.08
			FX.bolt(Folder, a, a + d * (1.1 + math.random() * 1.3), { color = col, width = 0.035, segments = 3, jag = 0.35, life = 0.1, restrike = 0 })
		end
		if mode then
			for i = 1, 4 do
				local ang = math.random() * TAU
				local d = fwd * math.cos(ang) + side * math.sin(ang)
				local len = 0.9 + math.random() * 1.1
				local c = p + d * len * 0.5
				neonBit("CowlCrack", Vector3.new(0.09, 0.04, len), CFrame.lookAt(c, c + d, n), (i % 2 == 0) and PAL.Ember or PAL.Crimson, 0.15, 1.3, Vector3.new(0.03, 0.02, len))
			end
			if type(S.dust) == "function" then
				S.dust(Folder, p, n * 5 + velDir * 2, { count = 1, s0 = 1, s1 = 3.2, life = 0.9 })
			end
			FX.sparks(Folder, p, { dir = n, spread = 40, color = PAL.Ember, color2 = PAL.Crimson, count = 4, speed = { 8, 16 }, size = 0.25, life = 0.45 })
		end
	end

	-- standing still, One For All surges down an arm: three quick arcs, a spark spit and a soft glow at the hand
	local function surge(char, mode)
		local PAL = Skin.pal(char)
		local arm = (math.random() < 0.5) and LIMB.ARM_R or LIMB.ARM_L
		local col = mode and PAL.Crimson or PAL.Cowl
		limbArc(char, arm, col, 0.06)
		for i, dt in ipairs({ 0.07, 0.15 }) do
			task.delay(dt, function()
				if char.Parent then
					limbArc(char, arm, (i == 1) and PAL.Core or col, 0.045)
				end
			end)
		end
		local hand = char:FindFirstChild(arm[1])
		if hand and hand:IsA("BasePart") then
			FX.sparks(Folder, hand.Position, { color = PAL.Spark, color2 = col, count = 6, speed = { 6, 14 }, size = 0.25, life = 0.4 })
			FX.glow(Folder, hand.Position, glowSize(hand.Position, 2.2), col, 0.25, { alpha = 0.45 })
		end
	end

	local function dropTrail(tr)
		if not tr then
			return
		end
		local a0, a1 = tr.Attachment0, tr.Attachment1
		tr:Destroy()
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
	end
	local function dropPassive(st)
		for _, tr in ipairs(st.trails) do
			dropTrail(tr)
		end
		dropTrail(st.torsoTrail)
		if st.light then
			st.light:Destroy()
		end
		if st.crackle then
			st.crackle:Destroy()
		end
		if st.eyes then
			pcall(st.eyes.destroy)
		end
	end

	local function buildPassive(char)
		local PAL = Skin.pal(char)
		local st = { nextArc = 0, nextSkid = 0, nextStreak = 0, nextSurge = os.clock() + between(PFX.SurgeEvery, 1.4, 2.6), trails = {}, pal = PAL }
		for _, n in ipairs({ "LeftFoot", "RightFoot" }) do
			local foot = char:FindFirstChild(n)
			if foot and foot:IsA("BasePart") then
				local tr = FX.trail(foot, cs(PAL.Cowl, PAL.CowlDeep), 0.3, 0.18, { alpha = 0.4 })
				tr.Name = "OFAFootTrail"
				tr.Enabled = false
				table.insert(st.trails, tr)
			end
		end
		local ut = char:FindFirstChild("UpperTorso")
		if ut and ut:IsA("BasePart") then
			local l = Instance.new("PointLight")
			l.Name = "OFACowlLight"
			l.Color = PAL.Cowl
			l.Brightness = pnum("LightBase", 0.35)
			l.Range = pnum("LightRange", 7)
			l.Shadows = false
			l.Parent = ut
			st.light = l
			-- sparks crawling over the chest (emitted from the torso's volume)
			st.crackle = FX.emitter(ut, {
				Texture = TEX.star, Color = cs(PAL.Core, PAL.Cowl), Size = NSK({ { 0, 0.28 }, { 1, 0 } }),
				Transparency = NSK({ { 0, 0.05 }, { 0.7, 0.3 }, { 1, 1 } }), Lifetime = NumberRange.new(0.12, 0.28),
				Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-400, 400), Rate = 0, ZOffset = 0.4, Brightness = 2,
			})
			st.crackle.Name = "OFACowlCrackle"
			local tt = FX.trail(ut, cs(PAL.Cowl, PAL.CowlDeep), 1.3, 0.13, { alpha = 0.8, tail = 0 })
			tt.Name = "OFACowlSmear"
			tt.Enabled = false
			st.torsoTrail = tt
		end
		st.eyes = makeEyes(char)
		passiveFx[char] = st
		return st
	end

	-- always-on Full Cowl on every character holding this kit, scaled by how fast it moves
	function updatePassive(clock)
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			if char and p:GetAttribute("Kit") == CFG.KitId then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					seen[char] = true
					local PAL = Skin.pal(p)
					local st = passiveFx[char]
					if st and st.pal ~= PAL then -- the skin was switched: rebuild the always-on pieces in the new colours
						dropPassive(st)
						passiveFx[char] = nil
						st = nil
					end
					st = st or buildPassive(char)
					local isLocal = p == player
					local dist = camDist(hrp.Position)
					local near = dist < PASSIVE.GateDist
					local vel = hrp.AssemblyLinearVelocity * FLAT
					local speed = vel.Magnitude
					local velDir = speed > 0.5 and vel / speed or flat(hrp.CFrame.LookVector)
					local k = math.clamp((speed - 4) / math.max(pnum("FullSpeed", 22) - 4, 1), 0, 1)
					local mode = inMode(char)
					local grounded = hum.FloorMaterial ~= AIR
					-- the mode recolours the always-on pieces crimson
					if st.mode ~= mode then
						st.mode = mode
						local c = mode and cs(PAL.Crimson, PAL.Cowl) or cs(PAL.Cowl, PAL.CowlDeep)
						for _, tr in ipairs(st.trails) do
							tr.Color = c
						end
						if st.torsoTrail then
							st.torsoTrail.Color = mode and cs(PAL.Crimson, PAL.Blood) or cs(PAL.Cowl, PAL.CowlDeep)
						end
						if st.crackle then
							st.crackle.Color = mode and cs(PAL.Ember, PAL.Crimson) or cs(PAL.Core, PAL.Cowl)
						end
						if st.light then
							st.light.Color = mode and PAL.Crimson or PAL.Cowl
						end
					end
					-- foot trails while he runs, and through an Air Step's flip
					local trailsOn = near and (speed > pnum("TrailSpeed", 10) or clock < (st.boostUntil or 0))
					for _, tr in ipairs(st.trails) do
						if tr.Enabled ~= trailsOn then
							tr.Enabled = trailsOn
						end
					end
					if st.torsoTrail then
						local on = near and not isLocal and k >= pnum("TorsoTrailAt", 0.75)
						if st.torsoTrail.Enabled ~= on then
							st.torsoTrail.Enabled = on
						end
					end
					-- the chest glow: brighter and wider the faster he runs, flickering with the arcs
					if st.light then
						if near then
							st.light.Enabled = true
							st.light.Brightness = lerp(pnum("LightBase", 0.35), pnum("LightFast", 1.6), k) * (0.75 + math.random() * 0.4)
							st.light.Range = lerp(pnum("LightRange", 7), pnum("LightRangeFast", 12), k)
						elseif st.light.Enabled then
							st.light.Enabled = false
						end
					end
					if st.crackle then
						local rate = (dist < pnum("CrackleGate", 120)) and lerp(pnum("CrackleRate", 2), pnum("CrackleRateFast", 16), k) or 0
						if math.abs(st.crackle.Rate - rate) > 0.5 then
							st.crackle.Rate = rate
						end
					end
					-- the crawl: ArcEvery standing, ArcEveryFast flat out; at speed a third of the arcs run down the legs
					if near and clock >= st.nextArc then
						local every = lerp(PASSIVE.ArcEvery, pnum("ArcEveryFast", 0.07), k)
						if mode then
							every = math.max(every, 0.12) -- the mode's own crawl carries the body
						end
						st.nextArc = clock + every
						if k >= pnum("LegArcAt", 0.55) and math.random() < 0.35 then
							limbArc(char, (math.random() < 0.5) and LIMB.LEG_L or LIMB.LEG_R, (math.random() < 0.7) and PAL.Cowl or PAL.Core, 0.05)
						else
							bodyArc(Folder, char, (math.random() < 0.75) and PAL.Cowl or PAL.Core, 0.05 + 0.025 * k)
						end
					end
					local lf, rf = char:FindFirstChild("LeftFoot"), char:FindFirstChild("RightFoot")
					if speed > PASSIVE.SkidSpeed and dist < 120 and clock >= st.nextSkid and grounded then
						st.nextSkid = clock + PASSIVE.SkidEvery
						local foot = (lf and rf) and ((lf.Position.Y < rf.Position.Y) and lf or rf) or lf or rf
						if foot then
							FX.sparks(Folder, foot.Position, {
								dir = -velDir + UP * 0.4, spread = 35,
								color = mode and PAL.Ember or PAL.Spark, color2 = mode and PAL.Crimson or PAL.Cowl,
								count = (mode and 8 or 4) + math.floor(k * 3), speed = { 8, 18 }, size = 0.3, life = 0.35,
							})
						end
					end
					-- lightning footprints: one each time the planted foot changes (the lower foot swaps), with a fallback
					-- beat for gaits where the feet never part by much
					if grounded and speed > pnum("PrintSpeed", 8) and dist < pnum("PrintGate", 120) and lf and rf then
						local dy = lf.Position.Y - rf.Position.Y
						local low = (dy < -0.12) and lf or ((dy > 0.12) and rf or nil)
						local gap = clock - (st.lastPrint or 0)
						local due = (low and low ~= st.lowFoot) or gap > 0.42
						if low then
							st.lowFoot = low
						end
						if due and gap > pnum("PrintGap", 0.13) then
							st.lastPrint = clock
							local foot = low or ((dy < 0) and lf or rf)
							safe("footprint", footprint, char, foot, velDir, mode, k)
						end
					elseif not grounded then
						st.lowFoot = nil
					end
					-- wind streaks peel off his shoulders at a sprint (beside him, never straight at the lens)
					if k >= pnum("StreakAt", 0.7) and dist < pnum("StreakGate", 120) and clock >= st.nextStreak then
						st.nextStreak = clock + pnum("StreakEvery", 0.1)
						local side = Vector3.new(-velDir.Z, 0, velDir.X)
						local o = hrp.Position + side * ((math.random() < 0.5) and -1.7 or 1.7) + UP * (math.random() * 2 - 0.4) + velDir * 1.5
						FX.streaks(Folder, o, {
							dir = -velDir, spread = 8, color = PAL.Air, color2 = mode and PAL.Crimson or PAL.Cowl, count = 2,
							speed = { 45, 70 }, size = 0.16, life = 0.16, stretch = 3,
						})
					end
					-- standing still: now and then a surge down an arm
					if k < 0.15 and dist < pnum("SurgeGate", 80) and clock >= st.nextSurge then
						st.nextSurge = clock + between(PFX.SurgeEvery, 1.4, 2.6)
						safe("surge", surge, char, mode)
					end
					-- the eyes streak green at a sprint (never in first person, where the head is see-through)
					if st.eyes then
						local head = st.eyes.head
						local fp = isLocal and head and head.LocalTransparencyModifier > 0.5
						st.eyes.set((not mode) and k >= pnum("EyeAt", 0.55) and dist < pnum("EyeGate", 90) and not fp and head.Parent ~= nil)
					end
				end
			end
		end
		for char, st in pairs(passiveFx) do
			if not seen[char] then
				dropPassive(st)
				passiveFx[char] = nil
			end
		end
	end
end

local function stepClip(spin)
	local name = spin and (AFX.SpinClip or "AirStepSpin") or (AFX.FlipClip or "AirStep")
	return Clips[name] or Clips.AirStep
end

local STEP_STATES = { [Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true }
local function tryAirStep()
	if not equipped() then
		return
	end
	local char, hum, hrp = myChar()
	if not char then
		return
	end
	local clock = os.clock()
	if hum.FloorMaterial ~= AIR or not air.leftAt or clock - air.leftAt < AIRSTEP.MinAirTime then
		return
	end
	if air.steps <= 0 or clock < rootUntil or mover or clock < air.ready or shotState then
		return
	end
	if not STEP_STATES[hum:GetState()] then
		return
	end
	air.steps -= 1
	air.ready = clock + 0.22
	local mode = inMode(char)
	local spin = mode and air.steps <= 0 and stepsMax(char) > 1 -- the mode's second step corkscrews
	local v = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(v.X * AIRSTEP.Keep, 0, v.Z * AIRSTEP.Keep) + UP * AIRSTEP.Up + hum.MoveDirection * AIRSTEP.Push
	playClip(char, stepClip(spin), 0)
	airStepFx(char, hrp.Position, mode, spin)
	shake(0.12, 0.18, 20, 2) -- a small kick under the lens (the FOV part is the caster's alone)
	Request:FireServer("AirStep", { pos = hrp.Position })
end

-- a held jump key repeats JumpRequest every frame; only a fresh press (a gap since the last request) steps
UserInputService.JumpRequest:Connect(function()
	local c = os.clock()
	local gap = c - air.lastReq
	air.lastReq = c
	if gap > 0.12 then
		safe("airstep", tryAirStep)
	end
end)

local function updateAir(clock)
	local char, hum = myChar()
	if not char then
		air.leftAt = nil
		return
	end
	if hum.FloorMaterial ~= AIR then
		air.leftAt = nil
		air.steps = stepsMax(char)
	elseif not air.leftAt then
		air.leftAt = clock
	end
end


---------------------------------------------------------------------------------------------------
-- MODE: Full Cowl 100% on any character (§8M, flair pass). It has to look dangerous: a crimson rim on the whole body,
-- a red heat haze, the aura and chest light beating like a heart, veins on both arms, steam off the arms and back
-- (bursting now and then), green eyes, green AND crimson arcs crawling over every limb with forks reaching off the
-- body, embers off the legs, sparks shed off the hands and feet while running, afterimages, cracked-ground footfalls
-- (in the passive's footprints) and a low crackle. It ignites with a burst, and in its last 2 s the heart races and
-- the steam thickens before the arm gives out (Burnout)
local MFX = type(MODE.FX) == "table" and MODE.FX or {}
local function mnum(k, d)
	local v = MFX[k]
	return type(v) == "number" and v or d
end
-- the heartbeat: a lub-dub pulse (0..1), quicker in the mode's last seconds
local function heartbeat(clock, late)
	local period = late and mnum("BeatPeriodLate", 0.6) or mnum("BeatPeriod", 1.05)
	local ph = (clock % period) / period
	local a, b = (ph - 0.08) / 0.06, (ph - 0.3) / 0.06
	return math.min(math.exp(-a * a) + 0.6 * math.exp(-b * b), 1)
end

-- the mode's builders live in this block; updateMode is its entry point
local updateMode
do
	local modeFx = {} -- [char] = { player, untilT, built, folder, aura, light, veins, steam, eyes, highlight, haze, emitters, hum, next* }

	local function try(tag, fn, ...)
		if type(fn) ~= "function" then
			return nil
		end
		local ok, res = pcall(fn, ...)
		if not ok then
			warnLimited(tag, res)
			return nil
		end
		return res
	end

	local function steamEmit(s, n)
		if type(s) == "table" and type(s.Emit) == "function" then
			pcall(s.Emit, s, n)
		else
			for _, e in ipairs(emittersOf(s)) do
				e:Emit(n)
			end
		end
	end
	local function steamRate(s, r)
		if type(s) == "table" and type(s.setRate) == "function" then
			pcall(s.setRate, s, r)
		else
			for _, e in ipairs(emittersOf(s)) do
				e.Rate = r
			end
		end
	end

	local function buildMode(m, char, hrp, isLocal, dist)
		local PAL = Skin.pal(char)
		local S = Skin.S(PAL) -- the veins and eye glow come from Shared, so they need its alt copy too
		m.pal = PAL
		local f = Instance.new("Folder")
		f.Name = "Mode_" .. char.Name
		f.Parent = Folder
		m.folder = f
		m.aura = FX.aura(hrp, PAL.Crimson, PAL.Cowl, 40)
		local l = Instance.new("PointLight")
		l.Name = "OFAModeLight"
		l.Color = PAL.Cowl
		l.Brightness = 2.2
		l.Range = 14
		l.Shadows = false
		l.Parent = hrp
		m.light = l
		m.veins, m.steam, m.emitters = {}, {}, {}
		local per = isLocal and 3 or 2
		local V = S.Veins
		if type(V) == "table" and type(V.new) == "function" then
			for _, side in ipairs({ "Right", "Left" }) do
				local v = try("veins", V.new, f, char, { side .. "Hand", side .. "LowerArm", side .. "UpperArm" }, { perLimb = per })
				if v then
					table.insert(m.veins, v)
				end
			end
		end
		if type(S.steam) == "function" then
			for _, n in ipairs({ "RightLowerArm", "LeftLowerArm" }) do
				local arm = char:FindFirstChild(n)
				if arm then
					local s = try("steam", S.steam, arm, 10)
					if s then
						table.insert(m.steam, s)
					end
				end
			end
			local ut = char:FindFirstChild("UpperTorso")
			if ut and mnum("TorsoSteam", 3) > 0 then
				local s = try("steam", S.steam, ut, mnum("TorsoSteam", 3)) -- off his back and shoulders
				if s then
					table.insert(m.steam, s)
				end
			end
		end
		if type(S.eyeGlow) == "function" then
			m.eyes = try("eyeGlow", S.eyeGlow, char)
		end
		-- the crimson rim round the whole body (one Highlight; hidden behind walls)
		if MFX.Highlight ~= false and (isLocal or dist < mnum("HighlightGate", 140)) then
			local hl = Instance.new("Highlight")
			hl.Name = "OFAModeRim"
			hl.Adornee = char
			hl.DepthMode = Enum.HighlightDepthMode.Occluded
			hl.FillColor = PAL.Crimson
			hl.FillTransparency = 0.88
			hl.OutlineColor = PAL.Crimson
			hl.OutlineTransparency = 0.4
			hl.Parent = f
			m.highlight = hl
		end
		-- the red heat haze: faint, slow crimson blooms rising off the torso, drawn behind the body
		local ut = char:FindFirstChild("UpperTorso")
		if ut and ut:IsA("BasePart") then
			m.haze = FX.emitter(ut, {
				Texture = TEX.glow, Color = cs(PAL.Crimson, PAL.Blood), LightEmission = 0.4,
				Size = NSK({ { 0, 2.2 }, { 0.5, 4 }, { 1, 5.2 } }),
				Transparency = NSK({ { 0, 1 }, { 0.25, isLocal and 0.92 or 0.88 }, { 0.7, 0.94 }, { 1, 1 } }),
				Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 4, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
				Rate = isLocal and mnum("HazeRateLocal", 8) or mnum("HazeRate", 14), ZOffset = -1.5, Brightness = 1,
			})
			m.haze.Name = "OFAModeHaze"
		end
		-- embers crackling off both legs
		for _, n in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
			local leg = char:FindFirstChild(n)
			if leg and leg:IsA("BasePart") then
				local e = FX.emitter(leg, {
					Texture = TEX.star, Color = cs(PAL.Ember, PAL.Crimson), Size = NSK({ { 0, 0.3 }, { 1, 0 } }),
					Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180),
					Acceleration = Vector3.new(0, -10, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300),
					Rate = 5, ZOffset = 0.3, Brightness = 2,
				})
				e.Name = "OFAModeEmbers"
				table.insert(m.emitters, e)
			end
		end
		-- a low looping crackle near the body
		if (isLocal or dist < mnum("HumGate", 70)) and SND.Crackle and SND.Crackle ~= "" then
			local s = Instance.new("Sound")
			s.Name = "OFAModeHum"
			s.SoundId = SND.Crackle
			s.Looped = true
			s.Volume = mnum("HumVolume", 0.12)
			s.PlaybackSpeed = 0.75
			s.RollOffMinDistance = 10
			s.RollOffMaxDistance = 80
			s.Parent = hrp
			s:Play()
			m.hum = s
		end
		m.built = true
	end

	local function clearMode(m, fadeVeins)
		for _, v in ipairs(m.veins or {}) do
			if fadeVeins and type(v) == "table" and type(v.fade) == "function" then
				safe("veins.fade", v.fade, v, 0.5)
			else
				kill(v)
			end
		end
		for _, s in ipairs(m.steam or {}) do
			endSteam(s, 1.5)
		end
		kill(m.eyes)
		for _, x in ipairs({ m.aura, m.light, m.highlight, m.haze, m.hum }) do
			if typeof(x) == "Instance" then
				x:Destroy()
			end
		end
		for _, e in ipairs(m.emitters or {}) do
			e:Destroy()
		end
		if m.folder then
			Debris:AddItem(m.folder, 1.2) -- the veins fade out inside it first
		end
		m.veins, m.steam, m.emitters, m.eyes, m.aura, m.light, m.folder = {}, {}, {}, nil, nil, nil, nil
		m.highlight, m.haze, m.hum = nil, nil, nil
		m.built, m.late = false, false
	end

	-- the mode ignites: crimson and green rings off the feet and round the body, forks of lightning bursting out, embers,
	-- a steam blast off both arms and a crackling boom. The caster gets a small kick and a crimson edge pulse (no flash)
	local function modeIgnite(char, hrp, isLocal)
		local PAL = Skin.pal(char)
		local p = hrp.Position
		local fp = p - UP * 3
		local heavy = isLocal or camDist(p) < 160
		FX.ring(Folder, fp + UP * 0.2, UP, 2, 22, PAL.Crimson, 0.5, { alpha = 0.2 })
		task.delay(0.06, function()
			FX.ring(Folder, fp + UP * 0.3, UP, 1, 14, PAL.Cowl, 0.42, { alpha = 0.25 })
		end)
		FX.ring(Folder, p, camFacing(p), 1, 9, PAL.Crimson, 0.35, { alpha = 0.4 })
		FX.arcs(Folder, p, 7, { outward = true, count = heavy and 6 or 3, colors = { PAL.Crimson, PAL.Cowl, PAL.Core }, width = 0.08, life = 0.14 })
		FX.glow(Folder, p, glowSize(p, 9), PAL.Crimson, 0.35, { alpha = 0.45 })
		FX.light(Folder, p, PAL.Crimson, 5, 24, 0.5)
		if heavy then
			FX.streaks(Folder, p, { color = PAL.Ember, color2 = PAL.Crimson, count = 24, speed = { 40, 90 }, size = 0.35, life = 0.3 })
			FX.sparks(Folder, p, { color = PAL.Ember, color2 = PAL.Crimson, count = 24, speed = { 20, 50 }, size = 0.4, life = 0.8 })
			FX.shell(Folder, p, 1.5, 7, PAL.Crimson, 0.4, Enum.Material.ForceField)
			task.delay(0.12, function()
				FX.arcs(Folder, p, 5, { outward = true, count = 4, colors = { PAL.Crimson, PAL.Cowl }, width = 0.06, life = 0.12 })
			end)
			if type(S.dust) == "function" then
				for i = 1, 5 do
					local a = i / 5 * TAU
					S.dust(Folder, fp + Vector3.new(math.cos(a), 0, math.sin(a)) * 3, Vector3.new(math.cos(a), 0.3, math.sin(a)) * 14, { count = 1, s0 = 2, s1 = 6, life = 1.2 })
				end
			end
		end
		local m = modeFx[char]
		if m then
			for _, s in ipairs(m.steam or {}) do
				steamEmit(s, 18)
			end
		end
		soundAt("Crackle", p, 0.6, 0.9)
		soundAt("Zap", p, 0.4, 0.7)
		soundAt("Sizzle", p, 0.4, 1)
		if isLocal then
			shake(0.25, 0.4, 18, 3)
			vignette(0.24, 0.9, PAL.Crimson)
		end
	end

	-- the mode runs out on a living body: the arm gives out. Both arms vent a blast of steam, the right one sputters
	-- crimson arcs that die to dark red, embers drop off it, and he doubles over clutching it (Burnout + BurnoutArm)
	local function burnout(char)
		local PAL = Skin.pal(char)
		local isLocal = char == player.Character
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if isLocal or (hrp and camDist(hrp.Position) < 220) then
			playClip(char, Clips.Burnout, 0)
			if Clips.BurnoutArm then
				playClip(char, Clips.BurnoutArm, 0)
			end
			local arm = char:FindFirstChild("RightLowerArm")
			if type(S.steam) == "function" then
				for _, spec in ipairs({ { "RightLowerArm", 30, 6 }, { "LeftLowerArm", 10, 0 }, { "UpperTorso", 10, 0 } }) do
					local part = char:FindFirstChild(spec[1])
					if part then
						local puff = try("steam", S.steam, part, 0)
						if puff then
							steamEmit(puff, spec[2])
							if spec[3] > 0 then
								-- the right arm keeps smoking for a second
								steamRate(puff, spec[3])
								task.delay(1.2, function()
									endSteam(puff, 1.5)
								end)
							elseif typeof(puff) == "Instance" then
								endSteam(puff, 2.5)
							end
						end
					end
				end
			end
			if arm then
				for i, dt in ipairs({ 0, 0.12, 0.3, 0.55 }) do
					task.delay(dt, function()
						if arm.Parent then
							limbArc(char, LIMB.ARM_R, (i <= 2) and PAL.Crimson or PAL.Blood, 0.07 - i * 0.012)
						end
					end)
				end
				FX.sparks(Folder, arm.Position, { dir = -UP, spread = 50, color = PAL.Ember, color2 = PAL.Blood, count = 12, speed = { 4, 12 }, size = 0.3, life = 0.7 })
				FX.glow(Folder, arm.Position, glowSize(arm.Position, 3), PAL.Crimson, 0.6, { alpha = 0.5 })
			end
			sound("Sizzle", arm or hrp, 0.7, 0.9)
			sound("Crackle", arm or hrp, 0.3, 0.6)
		end
		if isLocal then
			root(MODE.BurnoutRoot or 0.4)
			shake(0.15, 0.3, 14, 0)
			vignette(0.18, 0.7, PAL.Blood)
		end
	end

	function updateMode(clock)
		local t = now()
		local seen = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local untilT = char and char:GetAttribute("OFAMode")
			if hrp and hum and hum.Health > 0 and type(untilT) == "number" and untilT > t then
				seen[char] = true
				local isLocal = p == player
				local PAL = Skin.pal(p)
				local dist = camDist(hrp.Position)
				local m = modeFx[char]
				if not m then
					m = { player = p, nextArc = 0, nextGhost = 0, nextCrimson = 0, nextFork = clock + 0.2, nextSteam = clock + 1, nextSpark = 0, veins = {}, steam = {}, emitters = {} }
					modeFx[char] = m
					if dist < 220 and untilT - t > (MODE.Time or 12) - mnum("IgniteWindow", 1.5) then
						m.igniteAt = clock -- drawn once the pieces exist (below), so the steam blast has arms to come off
					end
				end
				m.untilT = untilT
				if m.built and m.pal ~= PAL then
					clearMode(m, false) -- the skin was switched mid-mode: rebuilt just below in the new colours
				end
				if not m.built and dist < 220 then
					buildMode(m, char, hrp, isLocal, dist)
				elseif m.built and dist > 280 then
					clearMode(m, false)
				end
				if m.igniteAt then
					m.igniteAt = nil
					safe("ignite", modeIgnite, char, hrp, isLocal)
				end
				if m.built and dist < 220 then
					local late = untilT - t < mnum("LateAt", 2)
					if late and not m.late then
						m.late = true
						for _, s in ipairs(m.steam) do
							steamRate(s, 20) -- it is about to give out
						end
					end
					local beat = heartbeat(clock, late)
					if clock >= m.nextArc then
						m.nextArc = clock + 0.06
						if not late or math.random() > 0.3 then -- the arcs sputter near the end
							bodyArc(Folder, char, (math.random() < 0.7) and PAL.Cowl or PAL.Crimson, 0.07)
						end
					end
					if m.light then
						m.light.Brightness = 1.8 + math.random() * (late and 1.8 or 1.2) + beat * 1.2
						m.light.Color = (beat > 0.5) and PAL.Crimson or PAL.Cowl
					end
					if m.highlight then
						m.highlight.OutlineTransparency = 0.55 - 0.4 * beat
						m.highlight.FillTransparency = 0.9 - 0.08 * beat
					end
					-- the crimson channel: arcs racing down a random arm or leg
					if clock >= m.nextCrimson then
						m.nextCrimson = clock + mnum("CrimsonArcEvery", 0.11)
						limbArc(char, LIMB.CHAINS[math.random(#LIMB.CHAINS)], (math.random() < 0.75) and PAL.Crimson or PAL.Ember, 0.06)
					end
					-- forks of lightning reaching off the body
					if clock >= m.nextFork and dist < 160 then
						m.nextFork = clock + between(MFX.ForkEvery, 0.3, 0.55)
						local ut = char:FindFirstChild("UpperTorso")
						if ut then
							FX.arcs(Folder, ut.Position + FX.randUnit() * 0.5, 3.4, {
								outward = true, count = 2, colors = { PAL.Crimson, PAL.Cowl, PAL.Core }, width = 0.045, life = 0.1,
							})
						end
					end
					-- steam bursts off an arm or the back
					if clock >= m.nextSteam then
						m.nextSteam = clock + between(MFX.SteamBurstEvery, 1.4, 2.4) * (late and 0.5 or 1)
						local s = m.steam[math.random(math.max(#m.steam, 1))]
						if s then
							steamEmit(s, 10)
							if dist < 60 then
								sound("Sizzle", hrp, 0.12, 1.4)
							end
						end
					end
					local vel = hrp.AssemblyLinearVelocity * FLAT
					local speed = vel.Magnitude
					-- sparks shed off the hands and feet while running
					if speed > 12 and clock >= m.nextSpark and dist < 160 then
						m.nextSpark = clock + mnum("SparkEvery", 0.07)
						local limb = char:FindFirstChild(LIMB.EXTREMES[math.random(#LIMB.EXTREMES)])
						if limb then
							FX.sparks(Folder, limb.Position, {
								dir = -vel.Unit + UP * 0.35, spread = 30, color = PAL.Ember, color2 = PAL.Crimson, count = 3,
								speed = { 6, 16 }, size = 0.25, life = 0.4,
							})
						end
					end
					if speed > 12 and clock >= m.nextGhost then
						m.nextGhost = clock + (isLocal and 0.09 or 0.14)
						m.ghostFlip = not m.ghostFlip
						ghost(char, m.ghostFlip and PAL.Crimson or PAL.Cowl, 0.65, 0.25)
					end
				end
			end
		end
		for char, m in pairs(modeFx) do
			if not seen[char] then
				local hum = char.Parent and char:FindFirstChildOfClass("Humanoid")
				local p = m.player
				-- it ran out on a living body still holding the kit: the arm gives out. Death, respawn and a kit
				-- switch just clear it
				local natural = hum and hum.Health > 0 and p and p.Parent and p.Character == char
					and p:GetAttribute("Kit") == CFG.KitId and (m.untilT or 0) <= now() + 0.5
				clearMode(m, natural)
				if natural then
					safe("burnout", burnout, char)
				end
				modeFx[char] = nil
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- the HUD every frame: cooldowns, the ready shimmer on E, the mode status / timer bar / stroke pulse / heartbeat
-- vignette, the pips, the title shakes
local pipWas = {}
local function updateHud(clock)
	local on = equipped()
	bar.Visible = on
	-- the ultimate's two titles shake the title holder for 0.2 s; every kanji slam jolts it for 0.08 s
	if clock < TT.shakeUntil or clock < TT.jolt then
		local a = (clock < TT.shakeUntil) and 4 or 3
		TT.holder.Position = UDim2.new(0.5, math.random(-a, a), 0.27, math.random(-a, a))
		TT.shaken = true
	elseif TT.shaken then
		TT.shaken = false
		TT.holder.Position = UDim2.fromScale(0.5, 0.27)
	end
	local t = now()
	local char = player.Character
	local mode = on and inMode(char)
	local untilT = char and char:GetAttribute("OFAMode")
	local left = (mode and type(untilT) == "number") and (untilT - t) or 0
	local late = mode and left < mnum("LateAt", 2)
	-- edge vignette: a pulse (in its own colour), and through the mode a crimson heartbeat
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
	local beat = mode and heartbeat(clock, late) or 0
	if mode then
		local mv = mnum("VignetteBase", 0.06) + mnum("VignetteBeat", 0.08) * beat + (late and 0.03 or 0)
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
		return
	end
	for skill, b in pairs(buttons) do
		local rem = (cooldownEnd[skill] or 0) - t
		local k = math.clamp(rem / math.max(cooldownLen[skill] or 1, 0.1), 0, 1)
		if b.horizontal then
			b.cd.Size = UDim2.fromScale(k, 1)
		else
			b.cd.Size = UDim2.fromScale(1, k)
		end
		b.cdText.Text = rem > 0 and string.format(rem >= 10 and "%.0f" or "%.1f", rem) or ""
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
		end
		b.ready = ready
	end
	-- the main move feels loaded: E's stroke breathes while it is ready
	local e = buttons.Detroit
	if e then
		e.stroke.Transparency = e.ready and (0.3 + 0.2 * math.sin(clock * TAU * 1.2)) or 0.1
	end
	local u = buttons.OFA
	if u then
		if mode then
			u.stroke.Color = PAL.Crimson:Lerp(PAL.Cowl, 0.5 + 0.5 * math.sin(clock * TAU * 4))
			u.modeTint = true
		elseif u.modeTint then
			u.modeTint = false
			u.stroke.Color = u.baseStroke
		end
	end
	-- the mode status: the countdown beats with the heart, over a crimson bar draining to nothing
	status.Text = mode and string.format("FULL COWL 100%%  %.1fs", left) or ""
	statusScale.Scale = 1 + 0.07 * beat
	modeBar.Visible = mode
	if mode then
		local k = math.clamp(left / math.max(MODE.Time or 12, 0.1), 0, 1)
		modeFill.Size = UDim2.fromScale(k, 1)
		modeFill.BackgroundColor3 = late and PAL.Crimson:Lerp(WHITE, 0.35 * beat) or PAL.Crimson:Lerp(PAL.Ember, 0.4 * beat)
	end
	local maxSteps = char and stepsMax(char) or 1
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local leftSteps = (hum and hum.FloorMaterial ~= AIR) and maxSteps or air.steps
	for i, p in ipairs(pips) do
		local avail = i <= leftSteps
		p.Visible = i <= maxSteps
		p.BackgroundColor3 = avail and (mode and PAL.Crimson or PAL.Cowl) or Color3.new(0.25, 0.25, 0.25)
		if pipWas[i] ~= nil and pipWas[i] ~= avail and pipScales[i] then
			-- spent: a hard pop; refilled on landing: a softer one
			pipScales[i].Scale = avail and 1.35 or 1.8
			tween(pipScales[i], 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		pipWas[i] = avail
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	barScale.Scale = math.clamp(vp.Y / 720, 0.75, 1.3)
end

---------------------------------------------------------------------------------------------------
-- playback: this script's own kinds, plus every move module's
local handlers = {}
local updates = {} -- [moduleName] = __update(clock, dt)
local resets = {} -- [moduleName] = __reset()

handlers.Cooldown = function(d)
	local skill = d.skill
	if skill and cooldownEnd[skill] then
		local ends = tonumber(d.ends) or 0
		if math.abs(ends - cooldownEnd[skill]) > 0.05 then -- a new cast; a refused one resends the same end time
			local len = ends - now()
			if len > 0.2 then
				cooldownLen[skill] = math.max(len, 0.5)
				local b = buttons[skill]
				if b then -- the cast pop: the button kicks and two rings ping off it
					b.scale.Scale = 1.12
					TweenService:Create(b.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
					pingButton(b, b.color or PAL.Cowl)
					task.delay(0.08, function()
						pingButton(b, b.color2 or WHITE)
					end)
				end
			end
		end
		cooldownEnd[skill] = ends
	end
end

-- another player's Air Step (the caster drew its own when it stepped)
handlers.AirStep = function(d)
	if d.userId == player.UserId or typeof(d.pos) ~= "Vector3" then
		return
	end
	local char = charOf(d.userId)
	if not char or camDist(d.pos) > PASSIVE.GateDist then
		return
	end
	-- the mode's second step inside a second corkscrews (the server sends `mode`; the attribute backs it up)
	local c = os.clock()
	local mode = d.mode == true or inMode(char)
	local spin = mode and lastStepAt[d.userId] ~= nil and c - lastStepAt[d.userId] < 1
	lastStepAt[d.userId] = c
	playClip(char, stepClip(spin), d.t0 and math.max(now() - d.t0, 0) or 0)
	airStepFx(char, d.pos, mode, spin)
end

local function countOf(list)
	local n = 0
	if type(list) == "table" then
		for _ in pairs(list) do
			n += 1
		end
	end
	return n
end

-- HUD side of a broadcast, run before the move module draws it. Q / E / R count their own hits through
-- ctx.tally; the ultimate's "xN SMASHED" and its smash vignette are drawn here
local function hudHook(kind, d)
	if d.userId ~= player.UserId then
		return
	end
	if kind == "OFASmash" then
		vignette(0.3, 0.6)
		local n = countOf(d.models)
		if n > 0 then
			bumpTally(d.id, 0, n, true)
		end
	end
end

local function resetAll()
	rootUntil, faceDir, mover = 0, nil, nil
	for h in pairs(floats) do
		h:Destroy()
	end
	stopShot()
	table.clear(leans)
	for name, fn in pairs(resets) do
		safe(name .. ".__reset", fn)
	end
end

---------------------------------------------------------------------------------------------------
-- ctx: everything a move module gets (CONTRACT.md)
local ctx = {
	player = player, CFG = CFG, PAL = PAL, SND = SND, Clips = Clips, FX = FX, S = S, Folder = Folder,
	UP = UP, FLAT = FLAT, WHITE = WHITE, TAU = TAU,
	now = now, myChar = myChar, charOf = charOf, equipped = equipped,
	flat = flat, camFacing = camFacing, camDist = camDist,
	sound = sound, soundAt = soundAt, castFolder = castFolder, playClip = playClip, freeze = freeze,
	shake = shake, lean = lean, showTitle = showTitle, callout = callout,
	root = root, unroot = unroot, setFace = setFace, move = move, stopMove = stopMove, blinkTo = blinkTo,
	float = float, groundY = groundY, shot = shot, stopShot = stopShot, inMode = inMode,
	-- extras beyond the contract (safe to ignore)
	cs = cs, vignette = vignette, request = request, cursorTarget = cursorTarget, -- vignette(a, dur, color?)
	-- the local caster's hit tally: tally(castId, add = 1, smashed?)
	tally = function(id, n, smashed)
		bumpTally(id, tonumber(n) or 1, nil, smashed)
	end,
	windGust = function(...)
		if type(S.windGust) == "function" then
			return S.windGust(...)
		end
	end,
	ghost = function(...)
		return ghost(...)
	end,
	bodyArc = function(...)
		return bodyArc(...)
	end,
}

---------------------------------------------------------------------------------------------------
-- every frame: movement, Air Step, floats, passive, mode, the move modules, the HUD
RunService.Heartbeat:Connect(function(dt)
	local clock = os.clock()
	safe("movement", updateMovement, dt)
	safe("air", updateAir, clock)
	safe("float", updateFloats, clock)
	safe("passive", updatePassive, clock)
	safe("mode", updateMode, clock)
	if type(S.__update) == "function" then
		safe("Shared.__update", S.__update, clock, dt)
	end
	for name, fn in pairs(updates) do
		safe(name .. ".__update", fn, clock, dt)
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
	baseMove = { ws = base or (hum.WalkSpeed > 0 and hum.WalkSpeed or 16), jp = hum.JumpPower, jh = hum.JumpHeight }
	wroteMovement = false
	air.leftAt, air.steps = nil, 0
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
end)

-- Studio test hooks (GojoShared.ClientDebug): ("Deku", skill) casts (or "AirStep"), ("DekuAim", dir) /
-- ("DekuTarget", point) stand in for the camera and the cursor
if RunService:IsStudio() then
	local dbg = ReplicatedStorage.GojoShared:FindFirstChild("ClientDebug")
	if dbg then
		dbg.Event:Connect(function(cmd, arg)
			if cmd == "Deku" and type(arg) == "string" then
				if arg == "AirStep" then
					air.leftAt = math.min(air.leftAt or os.clock(), os.clock() - 1)
					safe("airstep", tryAirStep)
				else
					request(arg)
				end
			elseif cmd == "DekuAim" then
				debugAim = (typeof(arg) == "Vector3" and arg.Magnitude > 0) and arg.Unit or nil
			elseif cmd == "DekuTarget" then
				debugTarget = typeof(arg) == "Vector3" and arg or nil
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- the move modules: Client.Shared first (it is ctx.S), then AirForce / Detroit / Blackwhip / Ultimate, each a
-- function(ctx) returning { [kind] = handler, __update?, __reset? }. A missing or broken module is skipped.
local clientFolder = nil
do
	local ok, res = pcall(function()
		return Kit:WaitForChild("Client", 10)
	end)
	clientFolder = ok and res or nil
	if not clientFolder then
		warn("[OneForAllClient] OneForAllKit.Client is missing; no move playback")
	end
end

local function loadModule(name)
	if not clientFolder then
		return nil
	end
	local ok, mod = pcall(function()
		return clientFolder:WaitForChild(name, 10)
	end)
	if not ok or not mod or not mod:IsA("ModuleScript") then
		warn("[OneForAllClient] module " .. name .. " is missing")
		return nil
	end
	local ok2, res = pcall(require, mod)
	if not ok2 then
		warn("[OneForAllClient] module " .. name .. " failed to load: " .. tostring(res))
		return nil
	end
	return res
end

do
	local shared = loadModule("Shared")
	if type(shared) == "table" then
		S = shared
		ctx.S = S
	else
		if shared ~= nil then
			warn("[OneForAllClient] Shared did not return a table")
		end
		ctx.S = S
	end
end

-- (2026-11-07 perks) CRIMSON COWL: an alt-coloured Shared (a clone of the module flagged "AltSkin") and the alt ctx the
-- second instance of every move module is built on. World wind and tree sway are ONE shared state (a base captured at
-- the first gust), so the alt Shared borrows the normal one's functions for those
do
	local mod = clientFolder and clientFolder:FindFirstChild("Shared")
	if mod and mod:IsA("ModuleScript") and next(S) ~= nil then
		local ok, res = pcall(function()
			local c = mod:Clone()
			c.Name = "SharedAlt"
			c:SetAttribute("AltSkin", true)
			return require(c)
		end)
		if ok and type(res) == "table" then
			for _, k in ipairs({ "windGust", "swirl", "windBend", "windReset" }) do
				if type(S[k]) == "function" then
					res[k] = S[k]
				end
			end
			Skin.shared = res
		else
			warn("[OneForAllClient] alt Shared failed to load (the alt skin draws Shared's pieces in the normal colours): " .. tostring(res))
		end
	end
	Skin.ctx = table.clone(ctx)
	Skin.ctx.PAL = Skin.alt
	Skin.ctx.S = Skin.shared or S
end

for _, name in ipairs({ "AirForce", "Detroit", "Blackwhip", "Ultimate" }) do
	local factory = loadModule(name)
	if type(factory) == "function" then
		local ok, H = pcall(factory, ctx)
		if not ok then
			warn("[OneForAllClient] module " .. name .. " failed to start: " .. tostring(H))
		elseif type(H) ~= "table" then
			warn("[OneForAllClient] module " .. name .. " did not return a handler table")
		else
			for kind, fn in pairs(H) do
				if type(fn) == "function" then
					if kind == "__update" then
						updates[name] = fn
					elseif kind == "__reset" then
						resets[name] = fn
					elseif handlers[kind] then
						warn("[OneForAllClient] duplicate handler for " .. tostring(kind) .. " in " .. name .. " (kept the first)")
					else
						handlers[kind] = fn
					end
				end
			end
			-- (perks) the CRIMSON COWL instance of the same module: own state, alt palette, alt Shared
			local okA, HA = pcall(factory, Skin.ctx)
			if okA and type(HA) == "table" then
				for kind, fn in pairs(HA) do
					if type(fn) == "function" then
						if kind == "__update" then
							updates[name .. "Alt"] = fn
						elseif kind == "__reset" then
							resets[name .. "Alt"] = fn
						elseif Skin.handlers[kind] == nil then
							Skin.handlers[kind] = fn
						end
					end
				end
			else
				warn("[OneForAllClient] module " .. name .. " (alt skin) failed to start: " .. tostring(HA))
			end
		end
	elseif factory ~= nil then
		warn("[OneForAllClient] module " .. name .. " did not return a function")
	end
end

Broadcast.OnClientEvent:Connect(function(kind, d)
	if type(d) ~= "table" then
		return
	end
	safe("hud " .. tostring(kind), hudHook, kind, d)
	local h = handlers[kind]
	-- (perks) the caster's skin picks the instance; latched per caster at each "...Cast", so one cast never splits
	if h and Skin.handlers[kind] and type(d.userId) == "number" then
		local alt = Skin.latch[d.userId]
		if alt == nil or string.sub(tostring(kind), -4) == "Cast" then
			alt = Skin.isAlt(Skin.playerOf(d.userId))
			Skin.latch[d.userId] = alt
		end
		if alt then
			h = Skin.handlers[kind]
		end
	end
	if h then
		local ok, err = pcall(h, d)
		if not ok then
			warn("[OneForAllClient] " .. tostring(kind) .. " failed: " .. tostring(err))
		end
	end
end)

print("[OneForAllClient] ready - Q: Air Force, E: Detroit Smash, R: Blackwhip, G: One For All")
