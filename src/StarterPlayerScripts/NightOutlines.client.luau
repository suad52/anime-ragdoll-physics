--!nocheck
-- StarterPlayerScripts.NightOutlines (2026-11-07): after dark, a faint outline round people so they are easier to
-- spot against the neon city - not a glow, just a thin line (tuning: ReplicatedStorage.CityShared.DayNight OUTLINES).
--   * every city NPC: ONE Highlight over the workspace.NPCs model (NPCService keeps the bodies in a Model for exactly
--     this - a Model adornee outlines everything inside it with a single Highlight)
--   * other players: one Highlight each, nearest first, tinted with their fighter's colour
--   * DepthMode Occluded: the line only shows where the body itself is visible - nobody is seen through walls
--   * it fades in with the dusk (DayNight.nightness of the shared clock) and is gone by day
--   * BUDGET: the engine draws at most 31 Highlights and the kits use plenty (the Unlimited Void up to 28, Sage
--     sensing up to 25, rims, Gear Fifth...). Every other Highlight in the workspace is counted; these only take what
--     is left, minus a margin, and vanish entirely when a move needs the room.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local DN = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("DayNight"))
local Kits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))
local O = DN.OUTLINES or {}

local ENGINE_CAP = 31
local MARGIN = 3
local TICK = 0.25
local NAME = "NightOutline"
local WHITE = Color3.new(1, 1, 1)

-- every OTHER Highlight in the workspace (theirs come and go with the moves)
local others = {}
local function watch(d)
	if d:IsA("Highlight") and d.Name ~= NAME then
		others[d] = true
	end
end
workspace.DescendantAdded:Connect(watch)
workspace.DescendantRemoving:Connect(function(d)
	others[d] = nil
end)
for _, d in ipairs(workspace:GetDescendants()) do
	watch(d)
end
local function othersOn()
	local n = 0
	for h in pairs(others) do
		if h.Parent and h.Enabled then
			n += 1
		elseif not h.Parent then
			others[h] = nil
		end
	end
	return n
end

-- our Highlights live under the camera (client-only, out of every model's children)
local folder = Instance.new("Folder")
folder.Name = "NightOutlines"
local function home()
	local cam = workspace.CurrentCamera
	if cam and folder.Parent ~= cam then
		folder.Parent = cam
	end
end
home()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(home)

local function newOutline()
	local h = Instance.new("Highlight")
	h.Name = NAME
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Enabled = false
	h.Parent = folder
	return h
end
local npcLine = newOutline()
local playerLines = {}
for i = 1, (O.MAX_PLAYERS or 8) do
	playerLines[i] = newOutline()
end

local function off(h)
	if h.Enabled then
		h.Enabled = false
	end
	if h.Adornee then
		h.Adornee = nil
	end
end

local state = { strength = 0, used = 0, budget = 0 } -- (Studio debug)

local function step()
	home()
	local clock = O.ENABLED ~= false and DN.clockNow() or nil
	local night = clock and DN.nightness(clock) or 0
	local from = O.FADE_FROM or 0.3
	local k = math.clamp((night - from) / (1 - from), 0, 1)
	k = k * k * (3 - 2 * k)
	local budget = ENGINE_CAP - MARGIN - othersOn()
	state.strength, state.budget, state.used = k, budget, 0
	if k <= 0.01 or budget < 1 then
		off(npcLine)
		for _, h in ipairs(playerLines) do
			off(h)
		end
		return
	end
	-- the city's NPCs, all at once
	local npcs = workspace:FindFirstChild("NPCs")
	if npcs and npcs:IsA("Model") then
		npcLine.Adornee = npcs
		npcLine.OutlineColor = O.NPC_COLOR or WHITE
		npcLine.OutlineTransparency = 1 - (1 - (O.NPC or 0.62)) * k
		npcLine.Enabled = true
		budget -= 1
		state.used += 1
	else
		off(npcLine)
	end
	-- other players, nearest first
	local cam = workspace.CurrentCamera
	local from3 = cam and cam.CFrame.Position or Vector3.zero
	local near = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if p ~= player and char and char.Parent then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				local d = (hrp.Position - from3).Magnitude
				if d <= (O.RANGE or 320) then
					table.insert(near, { p = p, char = char, d = d })
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	for i, h in ipairs(playerLines) do
		local e = near[i]
		if e and i <= budget then
			local kit = Kits.byId[e.p:GetAttribute("Kit") or ""]
			h.Adornee = e.char
			h.OutlineColor = (kit and kit.accent or WHITE):Lerp(WHITE, 0.45)
			h.OutlineTransparency = 1 - (1 - (O.PLAYER or 0.5)) * k
			h.Enabled = true
			state.used += 1
		else
			off(h)
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then
		return
	end
	acc = 0
	local ok, err = pcall(step)
	if not ok then
		state.err = tostring(err)
	end
end)

-- Studio: script.NightOutlinesDebug:Invoke() -> { strength, used, budget, err }
if RunService:IsStudio() then
	local f = Instance.new("BindableFunction")
	f.Name = "NightOutlinesDebug"
	f.OnInvoke = function()
		local s = table.clone(state)
		s.others = othersOn()
		return s
	end
	f.Parent = script
end
