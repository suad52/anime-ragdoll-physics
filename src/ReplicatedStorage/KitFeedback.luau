-- KitFeedback (client): what makes a hit feel like a hit. Floating damage numbers over every body that takes damage,
-- and for the player who landed it a hit-confirm: a tick sound, a camera kick and a tiny view punch that grows with
-- the size of the hit.
--   * numbers(list): every damage number in the game (2026-11-07). ServerScriptService.DamageFeed watches the health
--     of every NPC body and player and broadcasts what was lost; DamageNumbersClient hands it here. The number is
--     coloured by the attacker's kit, and red over your own character.
--   * hits(list, color): the hit-confirm only. Kits' servers batch their hits once per frame and broadcast them as
--     "Hits": { { u = attackerUserId, p = Vector3 position, d = damage, big = bool? }, ... }. (These used to pop the
--     numbers too; DamageFeed owns that now, so a hit never shows two.)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fx = require(ReplicatedStorage:WaitForChild("VulpineKit"):WaitForChild("FxLib"))
local HudKits = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("Kits"))

local KitFeedback = {}
local player = Players.LocalPlayer

-- number colour per attacking kit: the five kits that had numbers keep their colours, the rest use their HUD accent
local KIT_COLORS = {
	Vulpine = Color3.fromRGB(255, 190, 90),
	Tempest = Color3.fromRGB(190, 150, 255),
	Carver = Color3.fromRGB(255, 105, 105),
	Shifter = Color3.fromRGB(120, 255, 170),
	Ascendant = Color3.fromRGB(255, 214, 90),
}
local DEFAULT_COLOR = Color3.fromRGB(255, 200, 120) -- no player behind it (the world, an NPC)
local HURT_COLOR = Color3.fromRGB(255, 70, 70) -- damage you take
local CULL = 320 -- studs from the camera: farther numbers are never built (the billboard hides past 260 anyway)

local function kitColor(kitId)
	if type(kitId) ~= "string" then
		return DEFAULT_COLOR
	end
	local c = KIT_COLORS[kitId]
	if c then
		return c
	end
	local k = HudKits.byId[kitId]
	return k and k.accent or DEFAULT_COLOR
end

-- (2026-11-12) hits draw from HudShared.SfxBank's variant pools (no two in a row the same, pitch nudged)
local SfxBank = require(ReplicatedStorage:WaitForChild("HudShared"):WaitForChild("SfxBank"))

local folder
local function host()
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "DamageNumbers"
		folder.Parent = workspace
	end
	return folder
end

local function tween(o, t, props, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- damage merges per body (key = the body's model; by spot when there is none) for a moment, so a flurry of ticks
-- reads as one climbing number - and the number moves along with a body that is running or flung away
local recent = {} -- { pos, key, att, gui, label, total, untilT }

local function popNumber(pos, amount, color, big, key)
	local clock = os.clock()
	for i = #recent, 1, -1 do
		local r = recent[i]
		if clock > r.untilT or not r.gui.Parent then
			table.remove(recent, i)
		elseif not big and not r.big and ((key ~= nil and r.key == key) or (key == nil and r.key == nil and (r.pos - pos).Magnitude < 6)) then
			r.total += amount
			r.label.Text = tostring(math.floor(r.total + 0.5))
			r.scale.Scale = 1.5
			tween(r.scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
			r.untilT = clock + 0.35
			if (r.pos - pos).Magnitude > 3 and r.att.Parent then
				r.att.WorldPosition += pos - r.pos
				r.pos = pos
			end
			return
		end
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = pos + Vector3.new((math.random() - 0.5) * 2.5, 2.5 + math.random(), (math.random() - 0.5) * 2.5)
	att.Parent = workspace.Terrain
	Debris:AddItem(att, 1.4)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(big and 170 or 110, big and 64 or 42)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = att
	gui.Parent = host()
	Debris:AddItem(gui, 1.4)
	local scale = Instance.new("UIScale")
	scale.Scale = big and 2.6 or 2
	scale.Parent = gui
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = tostring(math.floor(amount + 0.5))
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Rotation = (math.random() - 0.5) * 16
	label.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), big and color:Lerp(Color3.fromRGB(255, 60, 40), 0.35) or color)
	grad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = big and 3 or 2
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.85)
	stroke.Parent = label
	-- punch in, drift up, fade
	tween(scale, big and 0.28 or 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(gui, 1.1, { StudsOffsetWorldSpace = Vector3.new(0, big and 5 or 3.5, 0) }, Enum.EasingStyle.Quart)
	task.delay(0.55, function()
		tween(label, 0.5, { TextTransparency = 1 })
		tween(stroke, 0.5, { Transparency = 1 })
	end)
	table.insert(recent, { pos = pos, key = key, att = att, gui = gui, label = label, scale = scale, total = amount, big = big, untilT = clock + 0.35 })
end

local lastConfirm = 0
local lastHurt = 0
local function playTick(id, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Parent = workspace.CurrentCamera
	s:Play()
	Debris:AddItem(s, 3)
end

-- the attacker's side of a hit: a crunchy tick, the camera kicked toward the hit, the view punched in a touch
local function confirm(total, biggest)
	local clock = os.clock()
	if clock - lastConfirm < 0.05 then
		return
	end
	lastConfirm = clock
	local heavy = biggest or total >= 30
	SfxBank.play(heavy and "HIT_HEAVY" or "HIT", nil, heavy and 0.95 or 0.7, heavy and 0.95 or 1.05)
	local k = math.clamp(total / 60, 0.25, 1.6)
	Fx.shake(0.35 + 0.6 * k, 0.12 + 0.12 * k)
	Fx.envelope({ fov = -2.5 * k, contrast = 0.08 * k, attack = 0.02, release = 0.16 + 0.1 * k })
end

-- list: a DamageFeed batch { { p, d, u?, k?, v?, big }, ... } - one number per entry
function KitFeedback.numbers(list)
	if type(list) ~= "table" then
		return
	end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for _, h in ipairs(list) do
		if type(h) == "table" and typeof(h.p) == "Vector3" and type(h.d) == "number" and h.d >= 0.5 and h.d == h.d
			and (not camPos or (h.p - camPos).Magnitude < CULL) then
			local color = (h.v ~= nil and h.v == player.UserId) and HURT_COLOR or kitColor(h.k)
			popNumber(h.p, h.d, color, h.big == true, typeof(h.m) == "Instance" and h.m or nil)
			-- (2026-11-12) the one getting hit hears it too (it used to be the attacker only)
			if h.v ~= nil and h.v == player.UserId and h.u ~= player.UserId then
				local clock = os.clock()
				if clock - lastHurt > 0.08 then
					lastHurt = clock
					local heavy = h.big == true or h.d >= 30
					SfxBank.play(heavy and "HIT_HEAVY" or "HIT", nil, heavy and 0.7 or 0.45, heavy and 0.9 or 0.98)
				end
			end
		end
	end
end

-- list: a kit's "Hits" batch. Only the attacker's hit-confirm comes from it now (the numbers come from DamageFeed).
-- color: kept for the kits' existing calls; unused
function KitFeedback.hits(list, color)
	if type(list) ~= "table" then
		return
	end
	local mine, biggest = 0, false
	for _, h in ipairs(list) do
		if type(h) == "table" and typeof(h.p) == "Vector3" and type(h.d) == "number" and h.d >= 0.5 then
			if h.u == player.UserId then
				mine += h.d
				biggest = biggest or h.big == true
			end
		end
	end
	if mine > 0 then
		confirm(mine, biggest)
	end
end

return KitFeedback
