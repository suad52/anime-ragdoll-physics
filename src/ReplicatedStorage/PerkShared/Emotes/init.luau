--!nocheck
-- ReplicatedStorage.PerkShared.Emotes (owner: emotes, 2026-11-07) - the EMOTE PACK perk (PerkCatalog id "Emotes").
-- CLIENT module (required on the server it only exposes LIST / Clips, and play() refuses). Booted on every client by
-- StarterPlayerScripts.PerkEmotesClient; CharacterSelect's inventory calls Emotes.play(id) too.
--   Emotes.play(id) -> ok, message   id = a PerkCatalog.EMOTES id (Taunt / Laugh / Victory). Checks the local player
--       owns the pack (attribute Perk_Emotes), is alive, standing still on the ground and not busy (KitLocked, ragdolled,
--       a giant form, grabbed ...), plays the clip at once on the local body and fires PerkShared.Remotes.Emote
--       ("play", id). The relay (ServerScriptService.PerkEmotes) re-validates + rate-limits and sends
--       ("play", player, id, serverStamp) to every OTHER client, which plays the same clip on that character through
--       GojoShared.Client.ProceduralAnimator, with the clip's flair (Clips.FX) within FX_DIST of the camera.
--   Emotes.stop() -> bool          cancels the local emote (and tells the others)
--   Emotes.toggleWheel(open?)      the emote wheel (the B key, or the round EMOTE button on a touch screen): PAGES of 4 / 8
--                                  SLOTS (the EmoteWheel attribute, ShopService.Ext.EmoteWheel); 1-8 play the current page,
--                                  Left / Right or the hub arrows turn it, EDIT fills a slot from the owned emotes, a bought
--                                  page adds a SEARCH box. B, Esc or a click outside closes it.
--   Emotes.isPlaying(character?)   -> id | nil (default: the local character)
-- An emote is cancelled on every client when the body moves / jumps / is knocked, when ANY other ProceduralAnimator
-- clip starts on it (a cast, a punch, a hit flinch: see installHook - persistent overlays such as Zangetsu's sword carry
-- (length >= 60) and Gear 5's idle bounce do not count), when it is hurt, ragdolled, dies, grabbed, or its player turns
-- KitLocked. The owner's own client also cancels on an ability key / M1 and relays the stop.
-- A second require of this module inside one client (a command-bar require gets its OWN copy) never double-plays: the
-- first copy owns the client and publishes a BindableFunction "ClientApi" under this script; later copies forward.
-- Studio debug: ReplicatedStorage.PerkShared.EmoteDebug:Fire(cmd, ...) with cmd "play" id | "force" id (no
-- ownership, no server: a visual check on the local body) | "dummy" id model | "stop" | "wheel" | "state".
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clips = require(script:WaitForChild("Clips"))

local Emotes = {}
Emotes.Clips = Clips

-- the emote list, in PerkCatalog.EMOTES order (only ids that have a clip)
local LIST = {}
do
	local ok, P = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("PerkCatalog"))
	end)
	if ok and type(P) == "table" then
		Emotes.Catalog = P
		if type(P.EMOTES) == "table" then
			for _, e in ipairs(P.EMOTES) do
				if type(e) == "table" and type(e.id) == "string" and type(Clips[e.id]) == "table" and Clips[e.id].keys then
					table.insert(LIST, { id = e.id, name = tostring(e.name or string.upper(e.id)) })
				end
			end
		end
	end
	if #LIST == 0 then
		LIST = { { id = "Taunt", name = "TAUNT" }, { id = "Laugh", name = "LAUGH" }, { id = "Victory", name = "VICTORY" } }
	end
end
local VALID = {}
for _, e in ipairs(LIST) do
	VALID[e.id] = true
end
Emotes.LIST = LIST

function Emotes.isValid(id)
	return type(id) == "string" and VALID[id] == true
end

if not RunService:IsClient() then
	function Emotes.play()
		return false, "client only"
	end
	function Emotes.stop()
		return false
	end
	function Emotes.toggleWheel()
		return false
	end
	function Emotes.isPlaying()
		return nil
	end
	return Emotes
end

-- another copy of this module already runs the emote client: forward to it
do
	local api = script:FindFirstChild("ClientApi")
	if api and api:IsA("BindableFunction") then
		function Emotes.play(id)
			return api:Invoke("play", id)
		end
		function Emotes.stop()
			return api:Invoke("stop")
		end
		function Emotes.toggleWheel(open)
			return api:Invoke("wheel", open)
		end
		-- (2026-11-09) other scripts (GadgetBar) leave the number keys to the wheel while it is open
		-- (2026-11-11) this used to sit here unindented reading `Wheel` - a global that is nil in this forwarding copy -
		-- and the copy that actually owns the client never defined isWheelOpen at all, so GadgetBar's guard was always
		-- false and a 1-5 press with the wheel open played the emote AND spent a gadget. It forwards now; the owning copy
		-- defines it in the public API below.
		function Emotes.isWheelOpen(input)
			return api:Invoke("isWheelOpen", input) == true
		end
		function Emotes.isPlaying(character)
			return api:Invoke("isPlaying", character)
		end
		return Emotes
	end
end
local ClientApi = Instance.new("BindableFunction")
ClientApi.Name = "ClientApi"
ClientApi.Archivable = false
ClientApi.Parent = script

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
-- (2026-11-11, "have the option to have keybinds") B (the EMOTES action) and the ability keys that cancel an emote are
-- read through Keybinds.logical, and the hub's "B TO CLOSE" draws Keybinds.label. The wheel's OWN keys while it is
-- open (1-8 / keypad, Left / Right, Escape) stay raw: they are not rebindable actions. With no rebinds every check
-- is the same key as before. (Client-only, so it is required below the server return above.)
local Keybinds = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Keybinds"))
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local PerkShared = script.Parent
local PA = require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
local Remote = nil -- PerkShared.Remotes.Emote, hooked up at the bottom

local MIN_GAP = 1.2       -- seconds between two of your own emotes (the server allows 0.8 + a 4-token bucket at this rate)
local FX_DIST = 160       -- flair (words, sparkles, whooshes) only for bodies this close to the camera
local REMOTE_DIST = 450   -- other players' emotes are not played at all past this camera distance
local OVERLAY_LEN = 60    -- a clip at least this long is a persistent overlay (a sword carry), not a cast
-- character attributes that make a body unable to emote (and cancel a running emote when they turn on)
local CHAR_BLOCK = { "Ragdolled", "Morphed", "TitanForm", "Guardian", "FoxBeast", "Flying", "GrabbedBy", "InDomain", "Dead" }
-- the owner's keys that cancel: every kit's ability keys + jump
local CANCEL_KEYS = {}
for _, k in ipairs({ "Q", "E", "R", "F", "G", "X", "C", "Z", "T", "V", "LeftControl", "LeftShift", "Space" }) do
	CANCEL_KEYS[Enum.KeyCode[k]] = true
end
local EMOTE_CLIP = {}
for _, e in ipairs(LIST) do
	EMOTE_CLIP[Clips[e.id]] = true
end
-- (2026-11-07) emotes are owned one by one (random rolls): OwnedEmotes is the JSON id list ShopService writes (the old
-- pack, Perk_Emotes, owns them all)
local HttpService = game:GetService("HttpService")
local function ownedEmotes()
	local set = {}
	if player:GetAttribute("Perk_Emotes") == true then
		for _, e in ipairs(LIST) do
			set[e.id] = true
		end
		return set
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("OwnedEmotes") or "[]")
	for _, id in ipairs(ok and type(list) == "table" and list or {}) do
		set[id] = true
	end
	return set
end
Emotes.owned = ownedEmotes

local MESSAGES = {
	locked = "ROLL FOR THIS EMOTE IN THE SHOP",
	busy = "CAN'T EMOTE RIGHT NOW",
	dead = "CAN'T EMOTE RIGHT NOW",
	moving = "STAND STILL TO EMOTE",
	airborne = "LAND FIRST",
	seated = "STAND UP FIRST",
	cooldown = "ONE AT A TIME",
	slow = "ONE AT A TIME",
	offline = "EMOTES ARE OFFLINE",
	unknown = "UNKNOWN EMOTE",
	nobody = "STAND NEXT TO A KNOCKED-OUT FIGHTER", -- (2026-11-11) PAY RESPECTS / FLAG PLANT
}
Emotes.MESSAGES = MESSAGES

local active = {} -- [character] = entry { id, char, player, isLocal, hum, hrp, track, conns, fx, t0, hp, done }
local lastLocal = 0
local watchConn = nil
local hooked = false
local IGNORE = {} -- clip tables that never cancel an emote (idle overlays)

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

-- why this body cannot emote right now (nil = it can)
local function blocked(plr, char)
	if not char or not char.Parent then
		return "dead"
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
		return "dead"
	end
	if plr and plr:GetAttribute("KitLocked") then
		return "busy"
	end
	for _, a in ipairs(CHAR_BLOCK) do
		if char:GetAttribute(a) then
			return "busy"
		end
	end
	return nil
end

-- natural: the clip ran to its end (its flair finishes on its own); otherwise the flair is removed at once
local function endEntry(e, fade, natural)
	if e.done then
		return
	end
	e.done = true
	if active[e.char] == e then
		active[e.char] = nil
	end
	if not natural and e.track then
		pcall(function()
			e.track:stop(fade or 0.2)
		end)
	end
	for _, c in ipairs(e.conns) do
		c:Disconnect()
	end
	table.clear(e.conns)
	if not natural then
		for _, inst in ipairs(e.fx) do
			pcall(function()
				inst:Destroy()
			end)
		end
	end
	table.clear(e.fx)
end

-- cancel an emote; the owner's own cancel is relayed so the other clients stop it too
local function cancel(e, fade)
	if not e or e.done then
		return
	end
	endEntry(e, fade or 0.15, false)
	if e.isLocal and Remote then
		Remote:FireServer("stop")
	end
end

-- Any ProceduralAnimator clip that starts on an emoting body (a cast, a punch, a hit flinch - on the caster's client and
-- on every client that renders that caster) ends the emote first, so a move never plays half-blended over a taunt.
-- This wraps ProceduralAnimator.play in this client's memory only (the module's source is untouched); everything else
-- passes straight through to the original.
local function installHook()
	if hooked then
		return
	end
	hooked = true
	pcall(function()
		local g = ReplicatedStorage:FindFirstChild("GomuKit")
		local m = g and g:FindFirstChild("Clips")
		if m and m:IsA("ModuleScript") then
			local t = require(m)
			if type(t) == "table" and type(t.Gear5_Bounce) == "table" then
				IGNORE[t.Gear5_Bounce] = true -- Gear 5's idle bounce overlay
			end
		end
	end)
	-- the wrapper is installed once per ProceduralAnimator instance and calls whatever check the newest owning copy of
	-- this module published, so a re-initialised copy is never left out
	PA.__perkEmoteCheck = function(character, clip)
		local e = character ~= nil and active[character] or nil
		if e and not e.done and type(clip) == "table" and not EMOTE_CLIP[clip] and not IGNORE[clip]
			and (tonumber(clip.length) or 0) < OVERLAY_LEN then
			cancel(e, 0.1)
		end
	end
	if type(PA.play) ~= "function" or PA.__perkEmoteHook then
		return
	end
	local orig = PA.play
	PA.__perkEmoteHook = true
	PA.play = function(character, clip, opts)
		local check = PA.__perkEmoteCheck
		if check then
			pcall(check, character, clip)
		end
		return orig(character, clip, opts)
	end
end

---------------------------------------------------------------------------------------------------
-- flair (every instance is client-only, tracked on the entry and on Debris)
local FONT = Enum.Font.GothamBlack
local INK = Color3.fromRGB(24, 14, 34)
local WHITE = Color3.new(1, 1, 1)
local SUN = Color3.fromRGB(255, 240, 150)
local GOLD = Color3.fromRGB(255, 205, 60)
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local RING_TEX = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local GLOW_TEX = "rbxasset://textures/particles/explosion01_implosion_main.dds"
local WHOOSH = "rbxassetid://9120972444" -- PlaygroundClient's whoosh
local Back, Out = Enum.EasingStyle.Back, Enum.EasingDirection.Out

local function tw(inst, t, props, style, dir, reps, reverses)
	local ok, tween = pcall(function()
		return TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Out, reps or 0, reverses or false), props)
	end)
	if ok and tween then
		tween:Play()
	end
	return tween
end

local fxFolder = nil
local function fxRoot()
	local cam = workspace.CurrentCamera
	if fxFolder and fxFolder.Parent and fxFolder.Parent == cam then
		return fxFolder
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "PerkEmoteFX"
	fxFolder.Archivable = false
	fxFolder.Parent = cam or workspace
	return fxFolder
end

local function keep(e, inst, life)
	table.insert(e.fx, inst)
	Debris:AddItem(inst, life)
	return inst
end

local function billboard(e, name, w, h, up, life)
	local head = e.char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Adornee = head
	bb.Size = UDim2.fromScale(w, h) -- studs
	bb.StudsOffsetWorldSpace = Vector3.new(0, up, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = FX_DIST
	bb.ResetOnSpawn = false
	bb.Parent = fxRoot()
	return keep(e, bb, life)
end

-- a comic word beside the head (camera-relative, like a speech burst - the title / VIP tags own the space ABOVE the
-- head): pops in past full size, wobbles while it holds, then floats up and fades
local function fxText(e, b)
	local size = tonumber(b.size) or 6
	local hold = tonumber(b.hold) or 1
	local bb = billboard(e, "EmoteWord", size, size * 0.4, 0, hold + 1)
	if not bb then
		return
	end
	local side = size * 0.45 + 0.6
	bb.StudsOffset = Vector3.new(side, 1.1, 0)
	local rot = tonumber(b.rot) or 0
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Rotation = rot
	holder.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0.25
	scale.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.Text = tostring(b.text or "")
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Parent = holder
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(b.c0 or WHITE, b.c1 or b.c0 or WHITE)
	grad.Rotation = 90
	grad.Parent = label
	local hrp = e.char:FindFirstChild("HumanoidRootPart")
	local dist = hrp and (hrp.Position - camPos()).Magnitude or 30
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = math.clamp(110 / math.max(dist, 1), 1.2, 3.5) -- pixels: thinner as the word shrinks with distance
	stroke.Parent = label
	tw(scale, 0.16, { Scale = 1.18 }, Back, Out)
	task.delay(0.16, function()
		if bb.Parent then
			tw(scale, 0.12, { Scale = 1 })
		end
	end)
	local swings = math.max(math.floor(hold / 0.44), 1)
	tw(holder, 0.22, { Rotation = -rot * 0.5 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, swings, true)
	task.delay(hold, function()
		if not bb.Parent then
			return
		end
		tw(label, 0.25, { TextTransparency = 1 })
		tw(stroke, 0.25, { Transparency = 1 })
		tw(bb, 0.25, { StudsOffset = Vector3.new(side, 2.1, 0) })
		Debris:AddItem(bb, 0.3)
	end)
end

-- a ring of "HA" letters bursting round the head (the Gear 5 laugh's lettering)
local function fxHa(e, b)
	local n = math.clamp(tonumber(b.n) or 6, 1, 10)
	local bb = billboard(e, "EmoteHa", 10, 7, 1.5, 2.2)
	if not bb then
		return
	end
	for i = 1, n do
		task.delay((i - 1) * 0.08, function()
			if not bb.Parent then
				return
			end
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			local ang = (i / n) * math.pi * 2 + math.random() * 0.5
			local pos = UDim2.fromScale(0.5 + math.cos(ang) * 0.36, 0.45 + math.sin(ang) * 0.32)
			t.Position = pos
			t.Size = UDim2.fromScale(0.05, 0.04)
			t.Text = (i % 3 == 0) and "HA!" or "HA"
			t.Font = FONT
			t.TextScaled = true
			t.TextColor3 = (i % 2 == 0) and WHITE or SUN
			t.TextStrokeTransparency = 0
			t.TextStrokeColor3 = INK
			t.Rotation = math.random(-26, 26)
			t.Parent = bb
			local s = 0.24 + math.random() * 0.1
			tw(t, 0.2, { Size = UDim2.fromScale(s, s * 0.8) }, Back, Out)
			task.delay(0.7, function()
				if t.Parent then
					tw(t, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1, Position = pos + UDim2.fromScale(0, -0.14) })
				end
			end)
		end)
	end
end

local function attachAt(e, partName, life)
	local part = e.char:FindFirstChild(partName or "UpperTorso") or e.char:FindFirstChild("HumanoidRootPart")
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "PerkEmoteFX"
	a.Archivable = false
	a.Parent = part
	return keep(e, a, life)
end

-- a burst of sparkles from a body part
local function fxSpark(e, b)
	local a = attachAt(e, b.part, 1.6)
	if not a then
		return
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SPARK_TEX
	pe.Color = ColorSequence.new(b.color or GOLD, WHITE)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.45, 0.9)
	pe.Speed = NumberRange.new(10, 22)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 5
	pe.Acceleration = Vector3.new(0, -14, 0)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-200, 200)
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(math.clamp(math.floor(tonumber(b.n) or 16), 1, 60))
end

-- a shockwave ring + glow flash at a body part
local function fxFlash(e, b)
	local a = attachAt(e, b.part, 1)
	if not a then
		return
	end
	local size = tonumber(b.size) or 8
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = RING_TEX
	ring.Color = ColorSequence.new(b.color or WHITE)
	ring.LightEmission = 1
	ring.LightInfluence = 0
	ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.15), NumberSequenceKeypoint.new(1, size) })
	ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	ring.Lifetime = NumberRange.new(0.35)
	ring.Speed = NumberRange.new(0)
	ring.LockedToPart = true
	ring.ZOffset = 1
	ring.Rate = 0
	ring.Parent = a
	ring:Emit(1)
	local glow = Instance.new("ParticleEmitter")
	glow.Texture = GLOW_TEX
	glow.Color = ColorSequence.new(b.color or WHITE)
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.45), NumberSequenceKeypoint.new(1, size * 0.15) })
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	glow.Lifetime = NumberRange.new(0.22)
	glow.Speed = NumberRange.new(0)
	glow.LockedToPart = true
	glow.Rate = 0
	glow.Parent = a
	glow:Emit(1)
end

local function fxWhoosh(e, b)
	local hrp = e.char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local s = Instance.new("Sound")
	s.Name = "PerkEmoteWhoosh"
	s.SoundId = WHOOSH
	s.Volume = math.clamp(tonumber(b.volume) or 0.4, 0, 1)
	s.PlaybackSpeed = tonumber(b.pitch) or 1
	s.SoundGroup = game:GetService("SoundService"):FindFirstChild("SettingsVoice") -- (2026-11-11) SETTINGS > AUDIO > VOICE & EMOTES
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = 90
	s.Parent = hrp
	keep(e, s, 2)
	s:Play()
end

---------------------------------------------------------------------------------------------------
-- (2026-11-11, wiki extras) PROPS - flair beat { kind = "prop", prop, life, launch? } (Clips.PackD): the interactive and
-- KO'd-body emotes leave something in the world. Client-side like all flair; flowers / flags / fireworks outlive the
-- clip (Debris only), the SIGN board is held (welded to the torso) and goes with the emote.
local KitsMod = nil
pcall(function()
	KitsMod = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))
end)
local signs = setmetatable({}, { __mode = "k" }) -- [player] = the TextLabel on their board
local pendingSign = setmetatable({}, { __mode = "k" }) -- [player] = text that arrived before the board
local BOOM = "rbxassetid://127224055692526" -- the kits' big explosion (Pro Sound Effects)
local function propPart(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end
local propRay = RaycastParams.new()
propRay.FilterType = Enum.RaycastFilterType.Exclude
local function groundAhead(e, dist)
	local hrp = e.hrp
	local at = hrp.Position + hrp.CFrame.LookVector * dist
	propRay.FilterDescendantsInstances = { e.char, fxRoot() }
	local r = workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), propRay)
	return r and r.Position or (at - Vector3.new(0, 3, 0)), hrp.CFrame.LookVector
end
local function accentOf(e)
	local c = Color3.fromRGB(255, 80, 120)
	if KitsMod and e.player then
		pcall(function()
			c = KitsMod.current(e.player).accent or c
		end)
	end
	return c
end
local function fxProp(e, b)
	local kind, life = b.prop, tonumber(b.life) or 10
	if kind == "sign" then
		local torso = e.char:FindFirstChild("UpperTorso") or e.char:FindFirstChild("Torso")
		if not torso then
			return
		end
		local board = Instance.new("Part")
		board.Name = "EmoteSign"
		board.Size = Vector3.new(3.6, 2.2, 0.16)
		board.Material = Enum.Material.SmoothPlastic
		board.Color = Color3.fromRGB(250, 248, 240)
		board.CanCollide, board.CanQuery, board.CanTouch, board.CastShadow, board.Massless = false, false, false, false, true
		board.CFrame = torso.CFrame * CFrame.new(0, 1.05, -1.75)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = board, torso
		w.Parent = board
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.LightInfluence = 0.3
		sg.Parent = board
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = sg
		local st = Instance.new("UIStroke")
		st.Thickness = 8
		st.Color = Color3.fromRGB(20, 20, 30)
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = frame
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -24, 1, -24)
		t.Position = UDim2.fromOffset(12, 12)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.TextWrapped = true
		t.FontFace = (KitsMod and KitsMod.FONT_PUNCH) or Font.fromEnum(Enum.Font.GothamBlack)
		t.TextColor3 = Color3.fromRGB(20, 20, 30)
		t.Text = (e.player and pendingSign[e.player]) or "..."
		t.Parent = frame
		board.Parent = fxRoot()
		if e.player then
			signs[e.player] = t
			pendingSign[e.player] = nil
		end
		keep(e, board, life)
		return
	end
	if not e.hrp then
		return
	end
	local at, look = groundAhead(e, kind == "firework" and 3 or 2.4)
	local root = fxRoot()
	if kind == "flowers" then
		local m = Instance.new("Model")
		m.Name = "EmoteFlowers"
		local cols = { Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 240, 140), Color3.fromRGB(190, 150, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 160, 90) }
		for i = 1, 5 do
			local off = Vector3.new(math.cos(i * 1.3) * 0.35, 0, math.sin(i * 1.3) * 0.35)
			local h = 0.9 + (i % 3) * 0.2
			propPart({ Name = "Stem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 0.08, 0.08), Color = Color3.fromRGB(70, 160, 80), Material = Enum.Material.SmoothPlastic,
				CFrame = CFrame.new(at + off + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, m)
			propPart({ Name = "Bloom", Shape = Enum.PartType.Ball, Size = Vector3.new(0.38, 0.38, 0.38), Color = cols[i], Material = Enum.Material.SmoothPlastic,
				CFrame = CFrame.new(at + off + Vector3.new(0, h + 0.1, 0)) }, m)
		end
		local side = look:Cross(Vector3.yAxis)
		local cpos = at + (side.Magnitude > 0.01 and side.Unit or Vector3.xAxis) * 0.8
		propPart({ Name = "Candle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.3, 0.3), Color = Color3.fromRGB(250, 245, 230), Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.new(cpos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, m)
		local flame = propPart({ Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.24, 0.16), Color = Color3.fromRGB(255, 200, 90), Material = Enum.Material.Neon,
			CFrame = CFrame.new(cpos + Vector3.new(0, 0.72, 0)) }, m)
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = Color3.fromRGB(255, 190, 110), 7, 1.2, false
		l.Parent = flame
		m.Parent = root
		Debris:AddItem(m, life)
	elseif kind == "flag" then
		local m = Instance.new("Model")
		m.Name = "EmoteFlag"
		propPart({ Name = "Pole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.5, 0.18, 0.18), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal,
			CFrame = CFrame.new(at + Vector3.new(0, 3.25, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, m)
		local side = look:Cross(Vector3.yAxis)
		side = side.Magnitude > 0.01 and side.Unit or Vector3.xAxis
		local mid = at + Vector3.new(0, 5.55, 0) + side * 1.35
		local cloth = propPart({ Name = "Cloth", Size = Vector3.new(2.6, 1.6, 0.06), Color = accentOf(e), Material = Enum.Material.Fabric,
			CFrame = CFrame.lookAt(mid, mid + look) }, m)
		propPart({ Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Color = Color3.fromRGB(255, 214, 70), Material = Enum.Material.Neon,
			CFrame = CFrame.new(at + Vector3.new(0, 6.55, 0)) }, m)
		m.Parent = root
		Debris:AddItem(m, life)
		task.spawn(function() -- a little flutter
			local base = cloth.CFrame
			local t0 = os.clock()
			while cloth.Parent and os.clock() - t0 < life do
				cloth.CFrame = base * CFrame.Angles(0, math.rad(math.sin((os.clock() - t0) * 4) * 8), 0)
				task.wait(0.05)
			end
		end)
	elseif kind == "firework" then
		local rocket = propPart({ Name = "Firework", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 0.45, 0.45), Color = Color3.fromRGB(230, 50, 60),
			Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, root)
		local fuse = Instance.new("Attachment")
		fuse.Position = Vector3.new(-0.75, 0, 0)
		fuse.Parent = rocket
		local sp = Instance.new("ParticleEmitter")
		sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
		sp.LightEmission = 1
		sp.Size = NumberSequence.new(0.3, 0)
		sp.Lifetime = NumberRange.new(0.3, 0.6)
		sp.Speed = NumberRange.new(2, 5)
		sp.SpreadAngle = Vector2.new(30, 30)
		sp.Rate = 30
		sp.EmissionDirection = Enum.NormalId.Left
		sp.Parent = fuse
		Debris:AddItem(rocket, life)
		task.delay(tonumber(b.launch) or 2.5, function()
			if not rocket.Parent then
				return
			end
			local apex = rocket.Position + Vector3.new(math.random(-4, 4), 70, math.random(-4, 4))
			sp.Rate = 90
			local up = TweenService:Create(rocket, TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(apex) * CFrame.Angles(0, 0, math.rad(90)) })
			up:Play()
			up.Completed:Wait()
			if not rocket.Parent then
				return
			end
			local a = Instance.new("Attachment")
			a.Position = apex
			a.Parent = workspace.Terrain
			local palette = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 214, 70), Color3.fromRGB(120, 230, 140), Color3.fromRGB(190, 120, 255) }
			local c1, c2 = palette[math.random(#palette)], palette[math.random(#palette)]
			local burst = Instance.new("ParticleEmitter")
			burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			burst.LightEmission = 1
			burst.Color = ColorSequence.new(c1, c2)
			burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
			burst.Lifetime = NumberRange.new(1.2, 1.8)
			burst.Speed = NumberRange.new(28, 42)
			burst.Drag = 2.5
			burst.SpreadAngle = Vector2.new(180, 180)
			burst.Acceleration = Vector3.new(0, -9, 0)
			burst.Rate = 0
			burst.Parent = a
			burst:Emit(150)
			local l = Instance.new("PointLight")
			l.Color, l.Range, l.Brightness, l.Shadows = c1, 60, 6, false
			l.Parent = a
			TweenService:Create(l, TweenInfo.new(1.2), { Brightness = 0 }):Play()
			local s = Instance.new("Sound")
			s.SoundId = BOOM
			s.Volume = 0.5
			s.PlaybackSpeed = 1.3
			s.RollOffMinDistance = 30
			s.RollOffMaxDistance = 500
			s.SoundGroup = game:GetService("SoundService"):FindFirstChild("SettingsSFX")
			s.Parent = a
			s:Play()
			rocket:Destroy()
			Debris:AddItem(a, 3)
		end)
	end
end

local FX = { text = fxText, ha = fxHa, spark = fxSpark, flash = fxFlash, whoosh = fxWhoosh, prop = fxProp }

local function scheduleFx(e, startAt)
	local beats = type(Clips.FX) == "table" and Clips.FX[e.id]
	if type(beats) ~= "table" then
		return
	end
	if not e.isLocal and e.hrp and (e.hrp.Position - camPos()).Magnitude > FX_DIST then
		return
	end
	for _, b in ipairs(beats) do
		local f = FX[b.kind]
		local d = (tonumber(b.t) or 0) - (startAt or 0)
		if f and d >= -0.05 then
			task.delay(math.max(d, 0), function()
				if e.done or not e.char.Parent then
					return
				end
				local ok, err = pcall(f, e, b)
				if not ok then
					warn("[Emotes] flair " .. tostring(b.kind) .. ": " .. tostring(err))
				end
			end)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- playback
local function watch()
	if watchConn then
		return
	end
	watchConn = RunService.Heartbeat:Connect(function()
		if next(active) == nil then
			watchConn:Disconnect()
			watchConn = nil
			return
		end
		local now = os.clock()
		for _, e in pairs(active) do
			local hrp, hum = e.hrp, e.hum
			if not (hrp and hrp.Parent and hum and hum.Parent) then
				endEntry(e, 0.1, false)
			else
				local v = hrp.AssemblyLinearVelocity
				local flat = Vector3.new(v.X, 0, v.Z).Magnitude
				local trav = type(Clips[e.id]) == "table" and Clips[e.id].traversal -- (2026-11-11) walking emotes keep going
				if e.isLocal then
					if trav then
						if hum.Jump or (now - e.t0 > 0.2 and (flat > 60 or math.abs(v.Y) > 30)) then
							cancel(e, 0.15)
						end
					-- walking / jumping input, or knocked about
					elseif hum.MoveDirection.Magnitude > 0.1 or hum.Jump or (now - e.t0 > 0.2 and (flat > 9 or math.abs(v.Y) > 18)) then
						cancel(e, 0.15)
					end
				elseif not trav and now - e.t0 > 0.3 and (flat > 7 or math.abs(v.Y) > 16) then
					endEntry(e, 0.15, false) -- another player's body started moving (its own stop is on the way too)
				end
			end
		end
	end)
end

local STOP_STATES = {
	[Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true, [Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

-- play emote `id` on `char` (plr may be nil for a test dummy). startAt catches a relayed emote up by its network delay.
local function startOn(char, plr, id, startAt, isLocal)
	if not VALID[id] or typeof(char) ~= "Instance" then
		return nil
	end
	local clip = Clips[id]
	local hum = char:FindFirstChildOfClass("Humanoid")
	if type(clip) ~= "table" or not hum or hum.Health <= 0 then
		return nil
	end
	installHook()
	local old = active[char]
	if old then
		endEntry(old, 0.12, false)
	end
	startAt = math.max(tonumber(startAt) or 0, 0)
	local e = {
		id = id, char = char, player = plr, isLocal = isLocal == true, hum = hum,
		hrp = char:FindFirstChild("HumanoidRootPart"), conns = {}, fx = {}, t0 = os.clock() - startAt, hp = hum.Health,
	}
	active[char] = e
	local ok, tr = pcall(PA.play, char, clip, {
		startAt = startAt,
		onEnd = function()
			-- ran out by itself (natural: the flair finishes on its own) or was stopped by someone else's stopAll
			if not e.done then
				endEntry(e, nil, not (e.track and e.track.stopping))
			end
		end,
	})
	if not ok or type(tr) ~= "table" then
		if active[char] == e then
			active[char] = nil
		end
		e.done = true
		warn("[Emotes] could not play " .. tostring(id) .. ": " .. tostring(tr))
		return nil
	end
	e.track = tr
	local function add(c)
		table.insert(e.conns, c)
	end
	add(hum.Died:Connect(function()
		endEntry(e, 0.1, false)
	end))
	add(hum.HealthChanged:Connect(function(h)
		if h < e.hp - 0.5 then
			cancel(e, 0.1) -- hit
		else
			e.hp = h
		end
	end))
	add(char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(workspace) then
			endEntry(e, 0, false)
		end
	end))
	for _, a in ipairs(CHAR_BLOCK) do
		add(char:GetAttributeChangedSignal(a):Connect(function()
			if char:GetAttribute(a) then
				cancel(e, 0.1)
			end
		end))
	end
	if typeof(plr) == "Instance" and plr:IsA("Player") then
		add(plr:GetAttributeChangedSignal("KitLocked"):Connect(function()
			if plr:GetAttribute("KitLocked") then
				cancel(e, 0.1)
			end
		end))
	end
	if e.isLocal then
		add(hum.StateChanged:Connect(function(_, new)
			if STOP_STATES[new] then
				cancel(e, 0.12)
			end
		end))
	end
	scheduleFx(e, startAt)
	watch()
	return e
end

---------------------------------------------------------------------------------------------------
-- (2026-11-11, wiki extras) emote KINDS on the owner's client: PAY RESPECTS / FLAG PLANT need a KO'd body within reach,
-- SIGN asks for its line (sent as ("sign", text); the server filters it), a joined PARTNER emote may be played unowned
local CollectionService = game:GetService("CollectionService")
local joinedOk = {} -- [id] = os.clock() deadline: the server let us join someone's partner emote
local function nearKO(char)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local function check(m)
		if m == char then
			return false
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("UpperTorso")
		return h ~= nil and r ~= nil and (h.Health <= 0 or m:GetAttribute("Dead") == true) and (r.Position - root.Position).Magnitude < 12
	end
	for _, m in ipairs(CollectionService:GetTagged("RagdollNPC")) do
		if check(m) then
			return true
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and check(p.Character) then
			return true
		end
	end
	return false
end
local signGui = nil
local function askSign()
	if signGui then
		signGui:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "EmoteSignInput"
	g.ResetOnSpawn = false
	g.DisplayOrder = 12
	g.Parent = player:WaitForChild("PlayerGui")
	signGui = g
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -175)
	f.Size = UDim2.fromOffset(440, 60)
	f.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 2
	st.Parent = f
	local box = Instance.new("TextBox")
	box.Name = "Text"
	box.Size = UDim2.new(1, -124, 1, -16)
	box.Position = UDim2.fromOffset(10, 8)
	box.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
	box.PlaceholderText = "WRITE YOUR SIGN (40 LETTERS)"
	box.PlaceholderColor3 = Color3.fromRGB(150, 150, 175)
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextScaled = true
	box.TextColor3 = Color3.new(1, 1, 1)
	box.FontFace = (KitsMod and KitsMod.FONT_LABEL) or Font.fromEnum(Enum.Font.GothamBold)
	box.Parent = f
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = box
	local ok = Instance.new("TextButton")
	ok.Name = "Show"
	ok.AnchorPoint = Vector2.new(1, 0.5)
	ok.Position = UDim2.new(1, -10, 0.5, 0)
	ok.Size = UDim2.fromOffset(96, 40)
	ok.BackgroundColor3 = Color3.fromRGB(255, 214, 70)
	ok.Text = "SHOW"
	ok.TextScaled = true
	ok.FontFace = (KitsMod and KitsMod.FONT_PUNCH) or Font.fromEnum(Enum.Font.GothamBlack)
	ok.TextColor3 = Color3.fromRGB(20, 20, 30)
	ok.Parent = f
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, 8)
	oc.Parent = ok
	local sent = false
	local function send()
		if sent then
			return
		end
		sent = true
		local text = box.Text:sub(1, 40)
		if text:match("%S") and Remote then
			Remote:FireServer("sign", text)
		end
		g:Destroy()
		if signGui == g then
			signGui = nil
		end
	end
	ok.Activated:Connect(send)
	box.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)
	pcall(function()
		box:CaptureFocus()
	end)
	task.delay(6, function()
		if g.Parent then
			g:Destroy()
		end
	end)
	Emotes._signBox = box -- Studio tests type into it
	Emotes._signSend = send
end

local function localPlay(id)
	if not VALID[id] then
		return false, MESSAGES.unknown
	end
	local clip = type(Clips[id]) == "table" and Clips[id] or {}
	if not ownedEmotes()[id] and not (joinedOk[id] and os.clock() < joinedOk[id]) then
		return false, MESSAGES.locked
	end
	local char = player.Character
	local why = blocked(player, char)
	if why then
		return false, MESSAGES[why] or MESSAGES.busy
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum.Sit then
		return false, MESSAGES.seated
	end
	if hum.FloorMaterial == Enum.Material.Air then
		return false, MESSAGES.airborne
	end
	if hum.MoveDirection.Magnitude > 0.1 and not clip.traversal then -- (2026-11-11) walking emotes start on the move
		return false, MESSAGES.moving
	end
	if clip.needsBody and not nearKO(char) then
		return false, MESSAGES.nobody
	end
	if os.clock() - lastLocal < MIN_GAP then
		return false, MESSAGES.cooldown
	end
	if not Remote then
		return false, MESSAGES.offline
	end
	if not startOn(char, player, id, 0, true) then
		return false, MESSAGES.busy
	end
	lastLocal = os.clock()
	Remote:FireServer("play", id)
	joinedOk[id] = nil
	if clip.sign then
		task.spawn(askSign)
	end
	if clip.partner then -- the JOIN prompt the server puts on us is for the others, not us
		task.spawn(function()
			local r = char:FindFirstChild("HumanoidRootPart")
			local pp = r and r:WaitForChild("EmoteJoin", 2)
			if pp then
				pp.Enabled = false
			end
		end)
	end
	return true, nil
end

---------------------------------------------------------------------------------------------------
-- the emote wheel (B, or the emote button on a touch screen)
-- (2026-11-09 shop expansion) PAGES of SLOTS. The layout is the EmoteWheel attribute ShopService writes
-- ({ perPage = 4 | 8, pages = n, search = bool, slots = { { id | "" } } } - ShopService.Ext.EmoteWheel): every player has
-- one page of 4; the More Emote Slots perk makes pages 8, every +1 Emote Page adds a page and a SEARCH box (plays any
-- owned emote without equipping it). 1-4 / 1-8 play the current page, the arrows (or Left / Right) turn it, EDIT turns
-- a slot into a picker of the owned emotes (ShopRequest "emoteSlot"). Touch screens get a round emote button.
local Wheel = { open = false, slices = {}, msgToken = 0, page = 1, editing = false }
local GOLD_UI = Color3.fromRGB(255, 230, 120)
local LOCK_UI = Color3.fromRGB(120, 112, 140)
local EDIT_UI = Color3.fromRGB(120, 220, 255)
local GLYPH = { Taunt = "挑", Laugh = "笑", Victory = "勝" }
local MAX_SLOTS = 8
local NUM_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
	Enum.KeyCode.Seven, Enum.KeyCode.Eight }
local PAD_KEYS = { Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadFour, Enum.KeyCode.KeypadFive,
	Enum.KeyCode.KeypadSix, Enum.KeyCode.KeypadSeven, Enum.KeyCode.KeypadEight }
local NAME_OF = {}
for _, e in ipairs(LIST) do
	NAME_OF[e.id] = e.name
end
local function glyphOf(id)
	return GLYPH[id] or (Clips.GLYPH and Clips.GLYPH[id]) or "舞"
end
local InputMode
pcall(function()
	InputMode = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("InputMode", 10))
end)
local function isTouch()
	if InputMode then
		return InputMode.isTouch()
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
-- the hub's close hint names whatever key the EMOTES action is bound to ("B TO CLOSE" by default)
local function closeHint()
	return Keybinds.label(Enum.KeyCode.B) .. " TO CLOSE"
end

-- the layout ShopService published (or, while it loads, one page of the owned emotes)
local function wheelData()
	local ok, w = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("EmoteWheel") or "")
	if ok and type(w) == "table" and type(w.slots) == "table" and #w.slots > 0 then
		w.perPage = math.clamp(math.floor(tonumber(w.perPage) or 4), 1, MAX_SLOTS)
		w.pages = #w.slots
		return w
	end
	local own, row = ownedEmotes(), {}
	for _, e in ipairs(LIST) do
		if own[e.id] and #row < 4 then
			table.insert(row, e.id)
		end
	end
	while #row < 4 do
		table.insert(row, "")
	end
	return { perPage = 4, pages = 1, search = false, slots = { row } }
end

local function newLabel(parent, text, font, color, size, pos)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Text = text
	l.Font = font
	l.TextColor3 = color
	l.TextScaled = true
	l.Size = size
	l.Position = pos
	l.Parent = parent
	return l
end

local function round(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(1, 0)
	c.Parent = p
end

local function newStroke(p, color, th)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = th
	s.Parent = p
	return s
end

local function newButton(parent, text, color, size, pos, anchor)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = color
	b.Size = size
	b.Position = pos
	b.Font = FONT
	b.Text = text
	b.TextScaled = true
	b.TextColor3 = INK
	b.Parent = parent
	round(b, UDim.new(0, 8))
	newStroke(b, INK, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = b
	return b
end

local function shopRequest(...)
	local r = ReplicatedStorage:FindFirstChild("HudShared") and ReplicatedStorage.HudShared:FindFirstChild("ShopRequest")
	if not r then
		return false, "SHOP OFFLINE"
	end
	local ok, a, b = pcall(r.InvokeServer, r, ...)
	if not ok then
		return false, "TRY AGAIN"
	end
	return a, b
end

function Wheel.footerText(w)
	if next(ownedEmotes()) == nil then
		local P = Emotes.Catalog
		local item = P and P.ROLLS and P.ROLLS.emote
		local price = item and tonumber(item.price)
		return price and ("RANDOM EMOTE  R$" .. price .. " OR ¥" .. tostring(P.ROLL_YEN or 500) .. "  -  IN THE SHOP") or "RANDOM EMOTE  -  IN THE SHOP"
	end
	if Wheel.editing then
		return isTouch() and "TAP A SLOT TO CHANGE IT" or "CLICK A SLOT TO CHANGE IT"
	end
	if isTouch() then
		return "TAP AN EMOTE"
	end
	return "PRESS 1 - " .. w.perPage .. " OR CLICK" .. (w.pages > 1 and "   ・   ← → PAGES" or "")
end

function Wheel.build()
	if Wheel.gui and Wheel.gui.Parent then
		return true
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return false
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "PerkEmoteWheel"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 60
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Enabled = false

	-- the dim backdrop: a click outside closes; Modal frees a locked mouse (shift-lock / first person)
	local back = Instance.new("TextButton")
	back.Name = "Backdrop"
	back.Text = ""
	back.AutoButtonColor = false
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 1
	back.Size = UDim2.fromScale(1, 1)
	back.Modal = true
	back.Parent = sg
	back.Activated:Connect(function()
		if Wheel.picker and Wheel.picker.Visible then
			Wheel.closePicker()
		else
			Wheel.close()
		end
	end)

	local root = Instance.new("Frame")
	root.Name = "Wheel"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Parent = sg
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Parent = root
	round(ring)
	local ringStroke = newStroke(ring, GOLD_UI, 2)
	ringStroke.Transparency = 0.55
	local ring2 = Instance.new("Frame")
	ring2.Name = "Ring2"
	ring2.BackgroundTransparency = 1
	ring2.AnchorPoint = Vector2.new(0.5, 0.5)
	ring2.Position = UDim2.fromScale(0.5, 0.5)
	ring2.Visible = false
	ring2.Parent = root
	round(ring2)
	newStroke(ring2, GOLD_UI, 2).Transparency = 0.68

	local hub = Instance.new("Frame")
	hub.Name = "Hub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	hub.BackgroundTransparency = 0.05
	hub.Parent = root
	round(hub)
	newStroke(hub, GOLD_UI, 2.5)
	local hubGlyph = newLabel(hub, "舞", Enum.Font.GothamBlack, GOLD_UI, UDim2.fromScale(0.36, 0.28), UDim2.fromScale(0.5, 0.28))
	hubGlyph.Name = "Glyph"
	local hubTitle = newLabel(hub, "EMOTES", FONT, WHITE, UDim2.fromScale(0.5, 0.18), UDim2.fromScale(0.5, 0.55))
	hubTitle.Name = "Title"
	local hubHint = newLabel(hub, closeHint(), Enum.Font.GothamBold, Color3.fromRGB(200, 190, 220), UDim2.fromScale(0.62, 0.1), UDim2.fromScale(0.5, 0.78))
	hubHint.Name = "Hint"
	-- page arrows either side of the title (only with more than one page)
	local prevB = newButton(hub, "◀", GOLD_UI, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.16, 0.55))
	prevB.Name = "PrevPage"
	local nextB = newButton(hub, "▶", GOLD_UI, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.84, 0.55))
	nextB.Name = "NextPage"
	prevB.Activated:Connect(function()
		Wheel.turn(-1)
	end)
	nextB.Activated:Connect(function()
		Wheel.turn(1)
	end)

	Wheel.slices = {}
	for i = 1, MAX_SLOTS do
		local b = Instance.new("TextButton")
		b.Name = "Slot" .. i
		b.Text = ""
		b.AutoButtonColor = false
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BackgroundColor3 = Color3.fromRGB(28, 22, 44)
		b.BackgroundTransparency = 0.05
		b.Parent = root
		round(b)
		local st = newStroke(b, GOLD_UI, 2)
		local sc = Instance.new("UIScale")
		sc.Parent = b
		local glyph = newLabel(b, "+", Enum.Font.GothamBlack, GOLD_UI, UDim2.fromScale(0.46, 0.36), UDim2.fromScale(0.5, 0.36))
		local name = newLabel(b, "EMPTY", FONT, WHITE, UDim2.fromScale(0.84, 0.2), UDim2.fromScale(0.5, 0.68))
		local badge = Instance.new("TextLabel")
		badge.Name = "Key"
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromScale(0.84, 0.16)
		badge.Size = UDim2.fromScale(0.26, 0.26)
		badge.BackgroundColor3 = GOLD_UI
		badge.Text = tostring(i)
		badge.Font = FONT
		badge.TextScaled = true
		badge.TextColor3 = INK
		badge.Parent = b
		round(badge)
		local slice = { button = b, stroke = st, scale = sc, glyph = glyph, name = name, badge = badge, index = i, id = "" }
		b.MouseEnter:Connect(function()
			tw(sc, 0.12, { Scale = 1.12 }, Back, Out)
			st.Thickness = 3.5
		end)
		b.MouseLeave:Connect(function()
			tw(sc, 0.12, { Scale = 1 })
			st.Thickness = 2
		end)
		b.Activated:Connect(function()
			Wheel.pickSlot(i)
		end)
		Wheel.slices[i] = slice
	end

	local footer = Instance.new("TextLabel")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0.5, 0)
	footer.Font = Enum.Font.GothamBlack
	footer.TextScaled = true
	footer.TextColor3 = WHITE
	footer.TextStrokeTransparency = 0.4
	footer.Text = ""
	footer.Parent = root
	-- EDIT: swap what is on the wheel
	local editB = newButton(root, "EDIT", EDIT_UI, UDim2.fromOffset(84, 26), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 0))
	editB.Name = "Edit"
	editB.Activated:Connect(function()
		Wheel.editing = not Wheel.editing
		Wheel.refresh()
	end)

	-- SEARCH (a bought emote page): any owned emote, played straight from the list
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.AnchorPoint = Vector2.new(0.5, 1)
	search.Size = UDim2.fromOffset(240, 30)
	search.BackgroundColor3 = Color3.fromRGB(24, 20, 38)
	search.TextColor3 = WHITE
	search.PlaceholderText = "SEARCH YOUR EMOTES"
	search.PlaceholderColor3 = Color3.fromRGB(160, 150, 185)
	search.Font = Enum.Font.GothamBold
	search.TextSize = 15
	search.ClearTextOnFocus = false
	search.Text = ""
	search.Visible = false
	search.Parent = root
	round(search, UDim.new(0, 8))
	newStroke(search, GOLD_UI, 2)
	local results = Instance.new("ScrollingFrame")
	results.Name = "Results"
	results.AnchorPoint = Vector2.new(0.5, 0)
	results.Size = UDim2.fromOffset(240, 0)
	results.AutomaticSize = Enum.AutomaticSize.Y
	results.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	results.BorderSizePixel = 0
	results.ScrollBarThickness = 0
	results.CanvasSize = UDim2.new()
	results.Visible = false
	results.ZIndex = 5
	results.Parent = root
	round(results, UDim.new(0, 8))
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 2)
	rl.Parent = results
	search:GetPropertyChangedSignal("Text"):Connect(function()
		Wheel.showResults()
	end)

	-- the picker EDIT opens for one slot: every owned emote (+ EMPTY), with its own filter box
	local picker = Instance.new("Frame")
	picker.Name = "Picker"
	picker.AnchorPoint = Vector2.new(0.5, 0.5)
	picker.Position = UDim2.fromScale(0.5, 0.5)
	picker.Size = UDim2.fromOffset(340, 300)
	picker.BackgroundColor3 = Color3.fromRGB(18, 14, 30)
	picker.Visible = false
	picker.ZIndex = 10
	picker.Active = true
	picker.Parent = sg
	round(picker, UDim.new(0, 14))
	newStroke(picker, EDIT_UI, 2.5)
	local pTitle = Instance.new("TextLabel")
	pTitle.BackgroundTransparency = 1
	pTitle.Position = UDim2.fromOffset(14, 10)
	pTitle.Size = UDim2.new(1, -60, 0, 24)
	pTitle.Font = FONT
	pTitle.TextScaled = true
	pTitle.TextXAlignment = Enum.TextXAlignment.Left
	pTitle.TextColor3 = WHITE
	pTitle.ZIndex = 11
	pTitle.Parent = picker
	local pClose = newButton(picker, "X", Color3.fromRGB(255, 120, 120), UDim2.fromOffset(30, 26), UDim2.new(1, -12, 0, 10), Vector2.new(1, 0))
	pClose.ZIndex = 11
	pClose.Activated:Connect(function()
		Wheel.closePicker()
	end)
	local pFilter = search:Clone()
	pFilter.Name = "Filter"
	pFilter.AnchorPoint = Vector2.new(0, 0)
	pFilter.Position = UDim2.fromOffset(14, 42)
	pFilter.Size = UDim2.new(1, -28, 0, 28)
	pFilter.PlaceholderText = "FILTER"
	pFilter.Visible = true
	pFilter.ZIndex = 11
	pFilter.Parent = picker
	local pList = Instance.new("ScrollingFrame")
	pList.Position = UDim2.fromOffset(14, 78)
	pList.Size = UDim2.new(1, -28, 1, -90)
	pList.BackgroundTransparency = 1
	pList.BorderSizePixel = 0
	pList.ScrollBarThickness = 4
	pList.ScrollBarImageColor3 = EDIT_UI
	pList.CanvasSize = UDim2.new()
	pList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pList.ZIndex = 11
	pList.Parent = picker
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(98, 34)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = pList
	pFilter:GetPropertyChangedSignal("Text"):Connect(function()
		Wheel.fillPicker()
	end)

	sg.Parent = pg
	Wheel.gui, Wheel.back, Wheel.root, Wheel.scale, Wheel.ring, Wheel.hub, Wheel.hint, Wheel.footer =
		sg, back, root, scale, ring, hub, hubHint, footer
	Wheel.ring2, Wheel.title, Wheel.prevB, Wheel.nextB, Wheel.editB = ring2, hubTitle, prevB, nextB, editB
	Wheel.search, Wheel.results = search, results
	Wheel.picker, Wheel.pTitle, Wheel.pFilter, Wheel.pList = picker, pTitle, pFilter, pList
	return true
end

-- where the slices sit, for any count, in units of ONE SLICE DIAMETER: one ring while that is the compact choice,
-- then an inner + an outer ring staggered into the inner one's gaps. Slice i is shape.pts[i] (clockwise from the top).
local WHEEL_GAP = 0.14   -- clear space between two slices (x the slice diameter)
local HUB_R = 1.09       -- the smallest ring radius that leaves the hub its room
local FOOT_H = 66        -- the footer + the EDIT pill under the lowest slice
local TOP_H = 44         -- the search box over the top slice (only with a bought page)
local SCREEN_PAD = 12    -- kept clear at every screen edge
local wheelShapes = {}

local function ringNeed(k) -- the ring radius at which k slices stand WHEEL_GAP apart
	if k < 2 then
		return 0
	end
	return (1 + WHEEL_GAP) / (2 * math.sin(math.pi / k))
end

local function placeRings(rings)
	local pts = {}
	for _, rg in ipairs(rings) do
		for j = 0, rg.k - 1 do
			local a = math.rad(-90 + (j + rg.phase) * 360 / rg.k)
			table.insert(pts, Vector2.new(math.cos(a), math.sin(a)) * rg.r)
		end
	end
	return pts
end

function Wheel.shape(n)
	if wheelShapes[n] then
		return wheelShapes[n]
	end
	local rings = { { k = n, r = math.max(HUB_R, ringNeed(n)), phase = 0 } }
	local pts = placeRings(rings)
	local up, down, half = 0, 0, 0
	for _, p in ipairs(pts) do
		up = math.max(up, -p.Y)
		down = math.max(down, p.Y)
		half = math.max(half, math.abs(p.X))
	end
	local s = { pts = pts, rings = rings, up = up + 0.5, down = down + 0.5, half = half + 0.5 }
	wheelShapes[n] = s
	return s
end

-- sized from the viewport every time it opens (a phone gets a smaller wheel), wheel + footer centred together
function Wheel.layout(w)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local m = math.min(vp.X, vp.Y)
	local sh = Wheel.shape(w.perPage)
	local top = w.search and TOP_H or 0
	local tall, wide = sh.up + sh.down, 2 * sh.half
	local R0 = math.clamp(m * 0.17, 74, 130)
	local D = math.clamp(R0 * 0.92, 66, 116)
	D = math.min(D, math.max(66, m * 0.62 / tall))
	D = math.min(D, (vp.Y - 2 * SCREEN_PAD - FOOT_H - top) / tall, (vp.X - 2 * SCREEN_PAD) / wide)
	D = math.max(math.floor(D), 24)
	local r1 = sh.rings[1].r
	local H = math.min(math.clamp(2 * (r1 - 0.65), 0.88, 1.5) * D, 150)
	local box = math.ceil(2 * math.max(sh.up, sh.down, sh.half) * D)
	Wheel.root.Size = UDim2.fromOffset(box, box)
	Wheel.root.Position = UDim2.new(0.5, 0, 0.5, math.floor(((sh.up - sh.down) * D - FOOT_H + top) / 2 + 0.5))
	Wheel.ring.Size = UDim2.fromOffset(2 * r1 * D, 2 * r1 * D)
	Wheel.ring2.Visible = false
	Wheel.hub.Size = UDim2.fromOffset(H, H)
	for i, s in ipairs(Wheel.slices) do
		local p = (sh.pts[i] or Vector2.zero) * D
		s.button.Size = UDim2.fromOffset(D, D)
		s.button.Position = UDim2.new(0.5, math.floor(p.X + 0.5), 0.5, math.floor(p.Y + 0.5))
		s.button.Visible = i <= w.perPage
	end
	Wheel.footerPos = UDim2.new(0.5, 0, 0.5, math.floor(sh.down * D + 12 + 0.5))
	Wheel.footer.Position = Wheel.footerPos
	Wheel.footer.Size = UDim2.fromOffset(math.min(vp.X - 32, 440), 20)
	Wheel.editB.Position = Wheel.footerPos + UDim2.fromOffset(0, 28)
	local searchPos = UDim2.new(0.5, 0, 0.5, -math.floor(sh.up * D + 10))
	Wheel.search.Position = searchPos
	Wheel.results.Position = searchPos + UDim2.fromOffset(0, 4)
	Wheel.laidOut = w.perPage
end

function Wheel.refresh()
	if not Wheel.gui then
		return
	end
	local w = wheelData()
	Wheel.data = w
	Wheel.page = math.clamp(Wheel.page, 1, w.pages)
	if Wheel.laidOut ~= w.perPage or Wheel.laidSearch ~= (w.search == true) then
		Wheel.laidSearch = w.search == true
		Wheel.layout(w)
	end
	local row = w.slots[Wheel.page] or {}
	local keys = not isTouch()
	for i, s in ipairs(Wheel.slices) do
		local id = row[i] or ""
		local has = id ~= "" and NAME_OF[id] ~= nil
		s.id = has and id or ""
		s.glyph.Text = has and glyphOf(id) or "+"
		s.name.Text = has and NAME_OF[id] or "EMPTY"
		s.name.TextTransparency = has and 0 or 0.45
		local col = Wheel.editing and EDIT_UI or (has and GOLD_UI or LOCK_UI)
		s.stroke.Color = col
		s.glyph.TextColor3 = has and GOLD_UI or LOCK_UI
		s.badge.Visible = keys and has and not Wheel.editing and i <= w.perPage
	end
	local paged = w.pages > 1
	Wheel.prevB.Visible, Wheel.nextB.Visible = paged, paged
	Wheel.title.Text = paged and (Wheel.page .. " / " .. w.pages) or "EMOTES"
	Wheel.hint.Text = isTouch() and "TAP OUTSIDE" or closeHint()
	Wheel.editB.Text = Wheel.editing and "DONE" or "EDIT"
	Wheel.editB.Visible = next(ownedEmotes()) ~= nil
	Wheel.search.Visible = w.search == true and not Wheel.editing
	if not Wheel.search.Visible then
		Wheel.results.Visible = false
	end
	Wheel.footer.Text = Wheel.footerText(w)
	Wheel.footer.TextColor3 = (next(ownedEmotes()) ~= nil) and (Wheel.editing and EDIT_UI or WHITE) or GOLD_UI
end

function Wheel.turn(dir)
	local w = Wheel.data or wheelData()
	if w.pages <= 1 then
		return
	end
	Wheel.page = (Wheel.page - 1 + dir) % w.pages + 1
	Wheel.refresh()
end

-- search results: owned emotes whose name contains the text (6 at most), click plays it
function Wheel.showResults()
	local box, list = Wheel.search, Wheel.results
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local q = string.upper(box.Text or "")
	if q == "" then
		list.Visible = false
		return
	end
	local own, n = ownedEmotes(), 0
	for _, e in ipairs(LIST) do
		if own[e.id] and string.find(string.upper(e.name), q, 1, true) and n < 6 then
			n += 1
			local b = newButton(list, e.name, GOLD_UI, UDim2.new(1, 0, 0, 28), UDim2.new())
			b.LayoutOrder = n
			b.ZIndex = 6
			b.Activated:Connect(function()
				box.Text = ""
				Wheel.pick(e.id)
			end)
		end
	end
	list.Visible = n > 0
end

function Wheel.fillPicker()
	local list = Wheel.pList
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local q = string.upper(Wheel.pFilter.Text or "")
	local own, n = ownedEmotes(), 0
	local function add(text, id, color)
		n += 1
		local b = newButton(list, text, color, UDim2.fromOffset(98, 34), UDim2.new())
		b.LayoutOrder = n
		b.ZIndex = 12
		b.Activated:Connect(function()
			Wheel.assign(id)
		end)
	end
	if q == "" then
		add("EMPTY", "", Color3.fromRGB(150, 145, 170))
	end
	for _, e in ipairs(LIST) do
		if own[e.id] and (q == "" or string.find(string.upper(e.name), q, 1, true)) then
			add(e.name, e.id, GOLD_UI)
		end
	end
end

function Wheel.openPicker(slot)
	Wheel.editSlot = slot
	Wheel.pTitle.Text = "SLOT " .. slot .. ((Wheel.data and Wheel.data.pages > 1) and ("  ・  PAGE " .. Wheel.page) or "") .. "  -  PICK AN EMOTE"
	Wheel.pFilter.Text = ""
	Wheel.fillPicker()
	Wheel.picker.Visible = true
end

function Wheel.closePicker()
	if Wheel.picker then
		Wheel.picker.Visible = false
	end
end

function Wheel.assign(id)
	local slot = Wheel.editSlot
	if not slot then
		return
	end
	local ok, msg = shopRequest("emoteSlot", { page = Wheel.page, slot = slot, id = id })
	Wheel.closePicker()
	if not ok then
		Wheel.flash(msg or "TRY AGAIN")
	end
	task.delay(0.1, Wheel.refresh) -- the new layout arrives as the EmoteWheel attribute
end

-- a short message in the footer (a refusal), then back to the hint
function Wheel.flash(msg)
	if not (Wheel.footer and Wheel.open) then
		return
	end
	Wheel.msgToken += 1
	local token = Wheel.msgToken
	Wheel.footer.Text = tostring(msg)
	Wheel.footer.TextColor3 = Color3.fromRGB(255, 140, 120)
	local pos = Wheel.footerPos or Wheel.footer.Position
	Wheel.footer.Position = pos
	tw(Wheel.footer, 0.05, { Position = pos + UDim2.fromOffset(6, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
	task.delay(1.6, function()
		if Wheel.msgToken == token and Wheel.footer then
			Wheel.footer.Position = pos
			if Wheel.open then
				Wheel.refresh()
			end
		end
	end)
end

function Wheel.pick(id)
	local ok, msg = localPlay(id)
	if ok then
		Wheel.close()
	else
		Wheel.flash(msg or MESSAGES.busy)
	end
end

-- a slice was clicked / its number pressed: play it (or, while editing, open the picker for it)
function Wheel.pickSlot(i)
	local w = Wheel.data or wheelData()
	if i > w.perPage then
		return
	end
	if Wheel.editing then
		Wheel.openPicker(i)
		return
	end
	local s = Wheel.slices[i]
	if s and s.id ~= "" then
		Wheel.pick(s.id)
	elseif next(ownedEmotes()) ~= nil then
		Wheel.editing = true -- an empty slot: straight to filling it
		Wheel.refresh()
		Wheel.openPicker(i)
	else
		Wheel.flash(Wheel.footerText(w))
	end
end

function Wheel.openNow()
	if not Wheel.build() then
		return
	end
	Wheel.open = true
	Wheel.editing = false
	Wheel.msgToken += 1
	Wheel.laidOut = nil
	Wheel.closePicker()
	Wheel.search.Text = ""
	Wheel.refresh()
	for _, s in ipairs(Wheel.slices) do
		s.scale.Scale = 1
		s.stroke.Thickness = 2
	end
	Wheel.gui.Enabled = true
	Wheel.back.BackgroundTransparency = 1
	tw(Wheel.back, 0.15, { BackgroundTransparency = 0.6 })
	Wheel.scale.Scale = 0.55
	tw(Wheel.scale, 0.2, { Scale = 1 }, Back, Out)
end

function Wheel.close()
	if not Wheel.open then
		return
	end
	Wheel.open = false
	Wheel.editing = false
	Wheel.msgToken += 1
	if not (Wheel.gui and Wheel.gui.Parent) then
		return
	end
	Wheel.closePicker()
	if Wheel.search then
		Wheel.search:ReleaseFocus()
	end
	tw(Wheel.back, 0.1, { BackgroundTransparency = 1 })
	tw(Wheel.scale, 0.1, { Scale = 0.8 })
	task.delay(0.1, function()
		if not Wheel.open and Wheel.gui then
			Wheel.gui.Enabled = false
		end
	end)
end

for _, a in ipairs({ "Perk_Emotes", "OwnedEmotes", "EmoteWheel" }) do
	player:GetAttributeChangedSignal(a):Connect(function()
		if Wheel.open then
			Wheel.refresh()
		end
	end)
end

-- the round EMOTE button for touch screens (there is no B key): above the DASH button, bottom-right
do
	local pg = player:WaitForChild("PlayerGui", 30)
	if pg then
		local sg = Instance.new("ScreenGui")
		sg.Name = "EmoteButton"
		sg.ResetOnSpawn = false
		sg.DisplayOrder = 5
		sg.Parent = pg
		local b = Instance.new("TextButton")
		b.Name = "Open"
		b.AnchorPoint = Vector2.new(1, 1)
		b.Position = UDim2.new(1, -150, 1, -226)
		b.Size = UDim2.fromOffset(60, 60)
		b.BackgroundColor3 = Color3.fromRGB(28, 22, 44)
		b.BackgroundTransparency = 0.1
		b.Text = ""
		b.Parent = sg
		round(b)
		newStroke(b, GOLD_UI, 2.5)
		newLabel(b, "舞", Enum.Font.GothamBlack, GOLD_UI, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.5, 0.42))
		newLabel(b, "EMOTE", FONT, WHITE, UDim2.fromScale(0.8, 0.2), UDim2.fromScale(0.5, 0.8))
		b.Activated:Connect(function()
			Emotes.toggleWheel()
		end)
		-- (2026-11-14) never under the sandbox's top-right panel (PlayerGui.HudTopRightY = its bottom, real px from the top
		-- of the screen, published by SandboxClient): on a landscape phone this bottom-anchored spot is up at the top and
		-- the NEXT panel sat on the button. Pushed down just enough; tablets and PCs keep the old spot.
		local function clearTop()
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			local inset = game:GetService("GuiService"):GetGuiInset().Y
			local h = cam.ViewportSize.Y - inset
			local minTop = (tonumber(pg:GetAttribute("HudTopRightY")) or 0) - inset + 6
			local push = math.max(0, minTop - (h - 226 - 60))
			b.Position = UDim2.new(1, -150, 1, -226 + push)
		end
		clearTop()
		pg:GetAttributeChangedSignal("HudTopRightY"):Connect(clearTop)
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(clearTop)
		end
		local function show()
			b.Visible = isTouch()
		end
		show()
		if InputMode then
			InputMode.changed(show)
		end
		Wheel.touchButton = b
	end
end
---------------------------------------------------------------------------------------------------
-- public API
function Emotes.play(id)
	local ok, msg = localPlay(id)
	if not ok and Wheel.open then
		Wheel.flash(msg)
	end
	return ok, msg
end

function Emotes.stop()
	local c = player.Character
	local e = c and active[c]
	if e and e.isLocal and not e.done then
		cancel(e, 0.15)
		return true
	end
	return false
end

function Emotes.toggleWheel(open)
	if open == nil then
		open = not Wheel.open
	end
	if open then
		Wheel.openNow()
	else
		Wheel.close()
	end
	return Wheel.open
end

function Emotes.isPlaying(character)
	local c = character or player.Character
	local e = c and active[c]
	return (e and not e.done) and e.id or nil
end

-- (2026-11-11) GadgetBar asks this before it takes a 1-5 press (see the forwarding copy at the top). Pass the
-- InputObject: picking a slot closes the wheel INSIDE the input handler below, so a GadgetBar handler that happens to
-- run after it would see a shut wheel - the press that arrived while it was open still counts as the wheel's.
function Emotes.isWheelOpen(input)
	return Wheel.open == true or (input ~= nil and input == Wheel.pressWhileOpen)
end

ClientApi.OnInvoke = function(cmd, a)
	if cmd == "play" then
		return Emotes.play(a)
	elseif cmd == "stop" then
		return Emotes.stop()
	elseif cmd == "wheel" then
		return Emotes.toggleWheel(a)
	elseif cmd == "isPlaying" then
		return Emotes.isPlaying(a)
	elseif cmd == "isWheelOpen" then
		return Emotes.isWheelOpen(a)
	end
	return nil
end

-- a rebind of the EMOTES key redraws the open hub's close hint
Keybinds.Changed:Connect(function()
	if Wheel.hint and not isTouch() then
		Wheel.hint.Text = closeHint()
	end
end)

---------------------------------------------------------------------------------------------------
-- input: B toggles the wheel; 1..n pick while it is open; the owner's ability keys / M1 cancel a running emote
UserInputService.InputBegan:Connect(function(input, gpe)
	Wheel.pressWhileOpen = Wheel.open and input or nil -- see Emotes.isWheelOpen
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if Keybinds.logical(input.KeyCode) == Enum.KeyCode.B and not gpe then
			Emotes.toggleWheel()
			return
		end
		if Wheel.open then
			if input.KeyCode == Enum.KeyCode.Escape then
				if Wheel.picker and Wheel.picker.Visible then
					Wheel.closePicker()
				else
					Wheel.close()
				end
				return
			end
			if not gpe then
				if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right then
					Wheel.turn(input.KeyCode == Enum.KeyCode.Left and -1 or 1)
					return
				end
				for i, k in ipairs(NUM_KEYS) do
					if input.KeyCode == k or input.KeyCode == PAD_KEYS[i] then
						Wheel.pickSlot(i)
						return
					end
				end
			end
		end
	end
	if gpe then
		return
	end
	local c = player.Character
	local e = c and active[c]
	if e and e.isLocal and not e.done then
		if input.UserInputType == Enum.UserInputType.MouseButton1 or CANCEL_KEYS[Keybinds.logical(input.KeyCode)] then
			cancel(e, 0.12)
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- the relay: ("play", player, id, serverStamp) / ("stop", player) for other players; ("deny", player, id, reason)
-- when the server refused our own
local function onRemote(kind, who, id, extra)
	if kind == "play" then
		if typeof(who) ~= "Instance" or not who:IsA("Player") or who == player or not VALID[id] then
			return
		end
		local char = who.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - camPos()).Magnitude > REMOTE_DIST or blocked(who, char) then
			return
		end
		local startAt = 0
		if type(extra) == "number" then
			startAt = math.clamp(workspace:GetServerTimeNow() - extra, 0, 0.35)
		end
		startOn(char, who, id, startAt, false)
	elseif kind == "stop" then
		if typeof(who) ~= "Instance" or who == player then
			return
		end
		local char = who:IsA("Player") and who.Character
		local e = char and active[char]
		if e and not e.isLocal then
			endEntry(e, 0.15, false)
		end
	elseif kind == "join" then -- (2026-11-11) the server let us join `who`'s partner emote: line up and play it
		local hc = typeof(who) == "Instance" and who:IsA("Player") and who.Character
		local hr = hc and hc:FindFirstChild("HumanoidRootPart")
		local mc = player.Character
		local mr = mc and mc:FindFirstChild("HumanoidRootPart")
		if not (hr and mr and VALID[id]) then
			return
		end
		joinedOk[id] = os.clock() + 3
		local clip = Clips[id]
		if clip and clip.partner == "duo" then
			mr.CFrame = CFrame.lookAt(hr.Position + hr.CFrame.LookVector * 3.4, hr.Position)
		else
			mr.CFrame = CFrame.lookAt(mr.Position, Vector3.new(hr.Position.X, mr.Position.Y, hr.Position.Z))
		end
		task.wait(0.05)
		local ok, msg = localPlay(id)
		if not ok and Wheel.open then
			Wheel.flash(msg)
		end
	elseif kind == "sign" then -- (2026-11-11) a SIGN's filtered text, for whoever holds it
		if typeof(who) == "Instance" and who:IsA("Player") then
			local t = tostring(id or "")
			if signs[who] and signs[who].Parent then
				signs[who].Text = t
			else
				pendingSign[who] = t
			end
		end
	elseif kind == "deny" then
		local char = player.Character
		local e = char and active[char]
		if e and e.isLocal and (id == nil or e.id == id) then
			endEntry(e, 0.15, false)
		end
		if Wheel.open then
			Wheel.flash(MESSAGES[extra] or MESSAGES.busy)
		end
	end
end

task.spawn(function()
	local folder = PerkShared:WaitForChild("Remotes", 30)
	local r = folder and folder:WaitForChild("Emote", 30)
	if r and r:IsA("RemoteEvent") then
		Remote = r
		r.OnClientEvent:Connect(function(...)
			local ok, err = pcall(onRemote, ...)
			if not ok then
				warn("[Emotes] " .. tostring(err))
			end
		end)
	else
		warn("[Emotes] PerkShared.Remotes.Emote is missing; emotes are local-only")
	end
end)

---------------------------------------------------------------------------------------------------
-- Studio debug hooks (PerkShared.EmoteDebug:Fire(cmd, ...)) - results print as "[Emotes] ..."
if RunService:IsStudio() then
	local dbg = PerkShared:FindFirstChild("EmoteDebug")
	if dbg and dbg:IsA("BindableEvent") then
		dbg.Event:Connect(function(cmd, a, b)
			if cmd == "play" then
				print("[Emotes] play", a, Emotes.play(a))
			elseif cmd == "force" then
				local c = player.Character
				print("[Emotes] force", a, c ~= nil and startOn(c, player, a, 0, true) ~= nil)
			elseif cmd == "dummy" then
				print("[Emotes] dummy", a, typeof(b) == "Instance" and startOn(b, nil, a, 0, false) ~= nil)
			elseif cmd == "stop" then
				print("[Emotes] stop", Emotes.stop())
			elseif cmd == "wheel" then
				print("[Emotes] wheel open =", Emotes.toggleWheel())
			elseif cmd == "state" then
				local ids = {}
				for ch, e in pairs(active) do
					table.insert(ids, ch.Name .. "=" .. e.id)
				end
				print("[Emotes] state owned=" .. tostring(player:GetAttribute("OwnedEmotes")) .. " remote=" .. tostring(Remote ~= nil)
					.. " hook=" .. tostring(PA.__perkEmoteHook == true) .. " active={" .. table.concat(ids, ",") .. "}")
			end
		end)
	end
end

return Emotes
