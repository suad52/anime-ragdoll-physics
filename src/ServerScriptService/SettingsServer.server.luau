--!nocheck
-- ServerScriptService.SettingsServer (2026-11-11, "wiki extras"): the two settings that need the server.
-- HIDE MY KILLS: while a player's PUBLIC attribute HideKills is true (ShopService.Ext.Settings publishes it), the real
--   leaderstats.Kills IntValue moves into player.HiddenStats and a StringValue "Kills" = "-" takes its place, so
--   Roblox's player list shows "-". Switching it off moves the IntValue back. Code that counts kills finds the IntValue
--   in either place (NPCService, ShopService, CharacterSelect) - see killsOf below for the rule.
-- SERVER REGION: when the game may make HTTP requests (Game Settings > Security > Allow HTTP Requests), one lookup of
--   this server's location at start (ipinfo.io) -> workspace attribute ServerRegion ("Ashburn, Virginia, US").
--   Without HTTP the label shows only the ping (StarterPlayerScripts.SettingsEffects draws it).
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- the real kill counter (an IntValue) wherever it is right now
local function killsOf(p)
	local hs = p:FindFirstChild("HiddenStats")
	local k = hs and hs:FindFirstChild("Kills")
	if k and k:IsA("IntValue") then
		return k
	end
	local ls = p:FindFirstChild("leaderstats")
	k = ls and ls:FindFirstChild("Kills")
	if k and k:IsA("IntValue") then
		return k
	end
	return nil
end

local function applyHide(p)
	local ls = p:FindFirstChild("leaderstats")
	local real = killsOf(p)
	if not (ls and real) then
		return
	end
	local hide = p:GetAttribute("HideKills") == true
	if hide and real.Parent == ls then
		local hs = p:FindFirstChild("HiddenStats")
		if not hs then
			hs = Instance.new("Folder")
			hs.Name = "HiddenStats"
			hs.Parent = p
		end
		real.Parent = hs
		local shown = Instance.new("StringValue")
		shown.Name = "Kills"
		shown.Value = "-"
		shown.Parent = ls
	elseif not hide and real.Parent ~= ls then
		for _, c in ipairs(ls:GetChildren()) do
			if c.Name == "Kills" and c:IsA("StringValue") then
				c:Destroy()
			end
		end
		real.Parent = ls
	end
end

local function watch(p)
	p:GetAttributeChangedSignal("HideKills"):Connect(function()
		applyHide(p)
	end)
	task.spawn(function()
		p:WaitForChild("leaderstats", 60)
		task.wait(1)
		applyHide(p)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end
Players.PlayerAdded:Connect(watch)

-- SERVER REGION
task.spawn(function()
	if not HttpService.HttpEnabled then
		return
	end
	local ok, body = pcall(HttpService.GetAsync, HttpService, "https://ipinfo.io/json")
	if not ok then
		warn("[SettingsServer] region lookup failed: " .. tostring(body))
		return
	end
	local ok2, t = pcall(HttpService.JSONDecode, HttpService, body)
	if ok2 and type(t) == "table" then
		local parts = {}
		for _, k in ipairs({ "city", "region", "country" }) do
			if type(t[k]) == "string" and t[k] ~= "" and not table.find(parts, t[k]) then
				table.insert(parts, t[k])
			end
		end
		if #parts > 0 then
			workspace:SetAttribute("ServerRegion", table.concat(parts, ", "))
		end
	end
end)

local ctl = Instance.new("BindableFunction")
ctl.Name = "Control"
ctl.OnInvoke = function(cmd, p)
	if cmd == "kills" and p then
		local k = killsOf(p)
		local ls = p:FindFirstChild("leaderstats")
		local shown = ls and ls:FindFirstChild("Kills")
		return { real = k and k.Value, realIn = k and k.Parent.Name, shown = shown and tostring(shown.Value), shownClass = shown and shown.ClassName }
	end
	return nil
end
ctl.Parent = script
