--!nocheck
-- ServerScriptService.PerkKOFX (owner: fx, perks 2026-11-07): the KO Effects perk (PerkCatalog id "KOFX").
-- Every RagdollNPC body that dies is checked once: NPCService credits the KO to the player in its LastHitBy attribute
-- (written by every kit right before the killing damage). When that player has a style equipped (EquipKO = a
-- PerkCatalog.KO id - ShopService writes only owned ones), the KO is queued and sent once per Heartbeat to EVERY client:
--   PerkShared.Remotes.PerkFX:FireAllClients("KO", { { s = style, p = Vector3, u = userId }, ... })
-- StarterPlayerScripts.PerkFXClient draws it (Confetti / Explosion / Lightning, ~1.5 s, cleaned up).
-- Bodies the game RETIRES (knocked out of play: attribute Retired) are skipped - they are off the map.
-- (2026-11-14, sandbox shop) the sandbox counts a dummy that is put down for good as a kill before it dies, so
-- Sandbox.Main also fires ServerStorage.PerkHooks.KO(player, model) on every kill it credits; whichever comes first
-- plays the effect and a body never plays two (played).
-- Studio test hook: script.Control:Invoke("test", style, pos?) fires one effect (pos defaults to in front of the
-- first player); Control:Invoke("stats") -> { sent = n, queued = n }.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("PerkCatalog"))
local Remotes = ReplicatedStorage:WaitForChild("PerkShared"):WaitForChild("Remotes")
local PerkFX = Remotes:FindFirstChild("PerkFX")
if not PerkFX then
	PerkFX = Instance.new("RemoteEvent")
	PerkFX.Name = "PerkFX"
	PerkFX.Parent = Remotes
end

local NPC_TAG = "RagdollNPC"
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("GojoShared"):WaitForChild("Config"):WaitForChild("NPC"))
	end)
	if ok and type(cfg) == "table" and type(cfg.Tag) == "string" then
		NPC_TAG = cfg.Tag
	end
end

local MAX_PER_BATCH = 24 -- a domain wiping the street at once still sends one bounded batch per frame

local VALID = {}
for _, k in ipairs(Catalog.KO or {}) do
	VALID[k.id] = true
end

local pending = {}
local sent = 0

local function styleOf(uid)
	if type(uid) ~= "number" then
		return nil
	end
	local p = Players:GetPlayerByUserId(uid)
	if not p then
		return nil
	end
	-- (2026-11-07 random rolls) KO effects are owned one by one: ShopService only ever sets EquipKO to a style this
	-- player owns ("" = none / off), so a valid EquipKO IS the ownership check
	local s = p:GetAttribute("EquipKO")
	if type(s) ~= "string" or not VALID[s] then
		return nil
	end
	return s
end

local function bodyPos(model)
	local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("LowerTorso") or model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
	local pos = t and t.Position
	if not pos or pos ~= pos or pos.Magnitude > 5e4 then
		return nil
	end
	return pos
end

local function queue(style, pos, uid)
	if #pending < MAX_PER_BATCH then
		table.insert(pending, { s = style, p = pos, u = uid })
	end
end

local watched = setmetatable({}, { __mode = "k" })
local played = setmetatable({}, { __mode = "k" }) -- (2026-11-14) one kill effect per body, whichever path saw it first
-- (2026-11-07 integration) one KO = one effect: a ragdolled NPC goes Dead -> Physics -> Dead, and Humanoid.Died fired
-- 3 times for a single KO in a playtest (3 confettis). A body that already played its effect waits KO_GAP before another.
local KO_GAP = 4
local koAt = setmetatable({}, { __mode = "k" })
local function watch(model)
	if watched[model] or not model:IsA("Model") then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	watched[model] = true
	hum.Died:Connect(function()
		local now = os.clock()
		if koAt[model] and now - koAt[model] < KO_GAP then
			return
		end
		koAt[model] = now
		if model:GetAttribute("Retired") or played[model] then
			return
		end
		local uid = model:GetAttribute("LastHitBy")
		local style = styleOf(uid)
		if not style then
			return
		end
		local pos = bodyPos(model)
		if pos then
			played[model] = true
			queue(style, pos, uid)
		end
	end)
end

-- (2026-11-14) the sandbox's kill credit (Sandbox.Main -> ServerStorage.PerkHooks.KO)
do
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ev = hooks and hooks:WaitForChild("KO", 30)
	if ev then
		ev.Event:Connect(function(p, model)
			if typeof(p) ~= "Instance" or not p:IsA("Player") or typeof(model) ~= "Instance" or played[model] then
				return
			end
			local style = styleOf(p.UserId)
			local pos = style and bodyPos(model)
			if pos then
				played[model] = true
				queue(style, pos, p.UserId)
			end
		end)
	end
end

CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(m)
	task.defer(watch, m) -- the rig is fully built before it is tagged + parented; defer covers any other order
end)
for _, m in ipairs(CollectionService:GetTagged(NPC_TAG)) do
	watch(m)
end

RunService.Heartbeat:Connect(function()
	if #pending > 0 then
		local list = pending
		pending = {}
		sent += #list
		PerkFX:FireAllClients("KO", list)
	end
end)

-- Studio / playtest hook (server only)
local ctl = script:FindFirstChild("Control")
if not ctl then
	ctl = Instance.new("BindableFunction")
	ctl.Name = "Control"
	ctl.Parent = script
end
ctl.OnInvoke = function(cmd, a, b)
	if cmd == "test" then
		local style = VALID[a] and a or "Explosion"
		local pos = typeof(b) == "Vector3" and b or nil
		if not pos then
			for _, p in ipairs(Players:GetPlayers()) do
				local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					pos = hrp.Position + hrp.CFrame.LookVector * 14
					break
				end
			end
		end
		queue(style, pos or Vector3.new(0, 5, 0), 0)
		return true
	elseif cmd == "stats" then
		return { sent = sent, queued = #pending }
	end
	return nil
end
