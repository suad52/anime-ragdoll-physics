--!nocheck
-- ServerScriptService.PerkEmotes (owner: emotes, 2026-11-07): the EMOTE PACK relay.
-- Client -> server  PerkShared.Remotes.Emote:FireServer("play", id) | ("stop")
-- Server -> clients ("play", player, id, workspace:GetServerTimeNow()) and ("stop", player) to every OTHER client;
--                   ("deny", player, id, reason) back to the sender when a play is refused (its client stops the
--                   predicted clip). reason: "locked" | "slow" | "busy".
-- A play needs that emote in OwnedEmotes (2026-11-07: emotes are owned one by one; ShopService writes the attribute,
-- the old pack included), a known PerkCatalog.EMOTES id with a clip, a living body
-- that is not ragdolled and a player that is not KitLocked; it is rate-limited (MIN_GAP between plays plus a token
-- bucket of BUCKET tokens refilled one per REFILL seconds - the client's own gap is 1.2 s, so a real player never hits
-- it). A stop is only relayed while that player's last emote is still running, so stops cannot be spammed either.
-- Nothing here moves or animates a character: every client plays the clip itself (PerkShared.Emotes).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkShared = ReplicatedStorage:WaitForChild("PerkShared")
local remotes = PerkShared:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = PerkShared
end
local Remote = remotes:FindFirstChild("Emote")
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "Emote"
	Remote.Parent = remotes
end

local MIN_GAP = 0.8   -- seconds between two relayed plays of one player
local BUCKET = 4      -- burst allowance
local REFILL = 1.2    -- seconds per token

-- valid ids -> clip length (seconds)
local LENGTH = {}
local META = {} -- (2026-11-11) id -> { partner, cosmetic, sign, name } (the clip's KIND flags)
do
	local okC, Clips = pcall(function()
		return require(PerkShared:WaitForChild("Emotes"):WaitForChild("Clips"))
	end)
	local okP, P = pcall(function()
		return require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("PerkCatalog"))
	end)
	if okC and type(Clips) == "table" then
		local list = (okP and type(P) == "table" and type(P.EMOTES) == "table") and P.EMOTES or nil
		if list then
			for _, e in ipairs(list) do
				local c = type(e) == "table" and Clips[e.id]
				if type(c) == "table" and c.keys then
					LENGTH[e.id] = tonumber(c.length) or 3
					if c.partner or c.cosmetic or c.sign then
						META[e.id] = { partner = c.partner, cosmetic = c.cosmetic, sign = c.sign, name = e.name }
					end
				end
			end
		else
			for _, id in ipairs({ "Taunt", "Laugh", "Victory" }) do
				if type(Clips[id]) == "table" then
					LENGTH[id] = tonumber(Clips[id].length) or 3
				end
			end
		end
	else
		warn("[PerkEmotes] PerkShared.Emotes.Clips failed to load: " .. tostring(Clips))
	end
end

local state = {} -- [player] = { tokens, at, last, untilT }

local function stateOf(p)
	local s = state[p]
	if not s then
		s = { tokens = BUCKET, at = os.clock(), last = -math.huge, untilT = 0 }
		state[p] = s
	end
	local now = os.clock()
	s.tokens = math.min(BUCKET, s.tokens + (now - s.at) / REFILL)
	s.at = now
	return s
end

local function others(p, ...)
	for _, o in ipairs(Players:GetPlayers()) do
		if o ~= p then
			Remote:FireClient(o, ...)
		end
	end
end

local HttpService = game:GetService("HttpService")
local function ownsEmote(p, id)
	if p:GetAttribute("Perk_Emotes") == true then
		return true
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, p:GetAttribute("OwnedEmotes") or "[]")
	return ok and type(list) == "table" and table.find(list, id) ~= nil
end

local function deny(p, id, reason)
	Remote:FireClient(p, "deny", p, id, reason)
end

---------------------------------------------------------------------------------------------------
-- (2026-11-11, wiki extras) emote KINDS (PerkShared.Emotes.Clips.PackD flags, META[id]):
--   partner "duo" | "group": a JOIN prompt (key J, or tap) on the emoter for the clip's length; a joiner may play that
--     emote without owning it (joinOk, 3 s) and is told ("join", host, id) so their client lines up and plays it
--   cosmetic: when the clip ends on a living body, a glow (Attachment "EmoteAura" on the root) is switched on - or off
--     if it is already there; it goes with the body
--   sign: ("sign", text) right after playing it -> filtered (TextService) -> ("sign", player, text) to everyone
local TextService = game:GetService("TextService")
local joinOk = {} -- [player] = { id, untilT }
local prompts = {} -- [host] = ProximityPrompt
local function joinAllowed(p, id)
	local j = joinOk[p]
	return j ~= nil and j.id == id and os.clock() < j.untilT
end
local function clearPrompt(p)
	if prompts[p] then
		prompts[p]:Destroy()
		prompts[p] = nil
	end
end
local function partnerPrompt(host, id, meta)
	clearPrompt(host)
	local root = host.Character and host.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "EmoteJoin"
	pp.ActionText = "JOIN " .. tostring(meta.name or id)
	pp.ObjectText = host.DisplayName
	pp.KeyboardKeyCode = Enum.KeyCode.J -- not E: E is an ability key
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.Parent = root
	prompts[host] = pp
	local joined = 0
	pp.Triggered:Connect(function(joiner)
		if joiner == host or (meta.partner == "duo" and joined >= 1) then
			return
		end
		local jc = joiner.Character
		local jh = jc and jc:FindFirstChildOfClass("Humanoid")
		if not jh or jh.Health <= 0 or joiner:GetAttribute("KitLocked") then
			return
		end
		joined += 1
		joinOk[joiner] = { id = id, untilT = os.clock() + 3 }
		Remote:FireClient(joiner, "join", host, id)
		if meta.partner == "duo" then
			pp.Enabled = false
		end
	end)
	task.delay(math.max((LENGTH[id] or 3) - 0.3, 0.5), function()
		if prompts[host] == pp then
			clearPrompt(host)
		end
	end)
end
local function glowToggle(p)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return
	end
	local old = root:FindFirstChild("EmoteAura")
	if old then
		old:Destroy()
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "EmoteAura"
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 170, 60))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.8, 1.3)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 16
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = a
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255, 210, 110)
	l.Range = 10
	l.Brightness = 1.4
	l.Shadows = false
	l.Parent = a
	a.Parent = root
end
local function onPlayed(p, id)
	local meta = META[id]
	if not meta then
		return
	end
	if meta.partner then
		partnerPrompt(p, id, meta)
	end
	if meta.cosmetic then
		local char = p.Character
		task.delay(LENGTH[id] or 3, function()
			local s = state[p]
			-- only if it ran to the end (not stopped / replaced) on the same body
			if s and s.lastId == id and p.Character == char and os.clock() >= s.untilT - 0.1 and s.untilT > 0 then
				glowToggle(p)
			end
		end)
	end
end

Remote.OnServerEvent:Connect(function(p, kind, id)
	if kind == "play" then
		if type(id) ~= "string" or not LENGTH[id] then
			return
		end
		if not ownsEmote(p, id) and not joinAllowed(p, id) then -- (2026-11-11) a partner emote's joiner needn't own it
			deny(p, id, "locked")
			return
		end
		local s = stateOf(p)
		local now = os.clock()
		if now - s.last < MIN_GAP or s.tokens < 1 then
			deny(p, id, "slow")
			return
		end
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or char:GetAttribute("Ragdolled") or p:GetAttribute("KitLocked") then
			deny(p, id, "busy")
			return
		end
		s.tokens -= 1
		s.last = now
		s.untilT = now + LENGTH[id]
		s.lastId, s.signed = id, false
		joinOk[p] = nil
		others(p, "play", p, id, workspace:GetServerTimeNow())
		onPlayed(p, id)
		local qe = game:GetService("ServerScriptService"):FindFirstChild("ShopService") and game:GetService("ServerScriptService").ShopService:FindFirstChild("QuestEvent") -- (2026-11-11) quests
		if qe then
			qe:Fire(p, "emotes", 1)
		end
	elseif kind == "stop" then
		local s = state[p]
		if s and os.clock() < s.untilT then
			s.untilT = 0
			others(p, "stop", p)
		end
		clearPrompt(p)
	elseif kind == "sign" then -- (2026-11-11) the SIGN emote's text: once per play, filtered for everyone
		local s = state[p]
		if type(id) ~= "string" or not s or s.signed or not (META[s.lastId] and META[s.lastId].sign) or os.clock() > s.untilT then
			return
		end
		s.signed = true
		local text = id:gsub("[%c]", " "):sub(1, 40)
		local ok, filtered = pcall(function()
			local res = TextService:FilterStringAsync(text, p.UserId, Enum.TextFilterContext.PublicChat)
			return res:GetNonChatStringForBroadcastAsync()
		end)
		Remote:FireAllClients("sign", p, ok and filtered or "...")
	end
end)

Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
	joinOk[p] = nil
	clearPrompt(p)
end)
