-- ServerScriptService.PlayerHealth (2026-11-09): every player spawns with PvPShared.Balance.PLAYER_MAX_HEALTH (250)
-- instead of Roblox's 100. Nothing else in the game sets a player's MaxHealth (the kits' forms use attributes).
-- (2026-11-14, sandbox shop) the HEALTH SLIDER: the player attribute HealthMax (ShopService.Ext.Sliders; 250 for anyone
-- without the slider) is the MaxHealth, applied on spawn and live - moving it keeps the same share of health. GOD MODE
-- (attribute GodMode): an invisible ForceField named GodField (Humanoid:TakeDamage does nothing through one - every
-- weapon, power and hazard in the game uses it) and, should anything set Health directly, an instant refill.
local Players = game:GetService("Players")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local MAX = tonumber(BAL.PLAYER_MAX_HEALTH) or 250
local LO, HI = 25, 5000

local function wanted(p)
	local v = p:GetAttribute("HealthMax")
	if type(v) ~= "number" or v ~= v then
		return MAX
	end
	return math.clamp(math.floor(v + 0.5), LO, HI)
end

local function applyMax(p, hum, fresh)
	local want = wanted(p)
	if fresh then
		hum.MaxHealth = want
		hum.Health = want
	elseif hum.MaxHealth ~= want and hum.Health > 0 then
		local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		hum.MaxHealth = want
		hum.Health = math.max(1, want * frac)
	end
end

local function applyGod(p, char, hum)
	local on = p:GetAttribute("GodMode") == true
	local ff = char:FindFirstChild("GodField")
	if on and not ff then
		ff = Instance.new("ForceField")
		ff.Name = "GodField"
		ff.Visible = false
		ff.Parent = char
	elseif not on and ff then
		ff:Destroy()
	end
	if on and hum.Health > 0 and hum.Health < hum.MaxHealth then
		hum.Health = hum.MaxHealth
	end
end

local function onCharacter(p, char)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	applyMax(p, hum, true)
	applyGod(p, char, hum)
	hum.HealthChanged:Connect(function(h)
		if h > 0 and h < hum.MaxHealth and p:GetAttribute("GodMode") == true then
			hum.Health = hum.MaxHealth
		end
	end)
end

local function onPlayer(p)
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
	p:GetAttributeChangedSignal("HealthMax"):Connect(function()
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			applyMax(p, hum, false)
		end
	end)
	p:GetAttributeChangedSignal("GodMode"):Connect(function()
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			applyGod(p, char, hum)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
