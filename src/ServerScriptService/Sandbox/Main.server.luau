--!nocheck
-- ServerScriptService.Sandbox.Main: the ragdoll sandbox's server. Wires the pieces together:
--   * the ten fighters -> injuries: every kit hit passes ServerScriptService.PvP.dmg, whose onBodyHit hook lands here
--     (which body part, what kind of wound - a blade fighter cuts, a lightning fighter burns, a ki blast blasts)
--   * the arsenal (ReplicatedStorage.Sandbox.Config): bat / axe / katana / sledgehammer swings and the gun ladder,
--     resolved here from the player's aim ray so the limb under the crosshair is the limb that gets hit
--   * grab (drag bodies, limbs and props about), the spawn menu, kill / time / damage stats and the three leaderboards
-- Client: StarterPlayerScripts.SandboxClient. Remotes: ReplicatedStorage.Sandbox.Net (+ GrabAim, unreliable).
-- SANDBOX SHOP (2026-11-14): the attacker's Strength slider (player attribute DamageMul) scales weapon and power damage on
-- dummies, the Fling Power slider (FlingMul) how far weapons, throws and powers send them (RagdollService.flingScale), and
-- Spawn Limit x3 (SpawnCapMul) the spawn menu caps. Every kill credited here also fires ServerStorage.PerkHooks.KO
-- (player, model) so the killer's kill effect plays (ServerScriptService.PerkKOFX).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Sandbox")
local Net, GrabAim = Shared:WaitForChild("Net"), Shared:WaitForChild("GrabAim")
local Config = require(Shared:WaitForChild("Config"))
local RagdollService = require(ServerScriptService:WaitForChild("GojoServer"):WaitForChild("RagdollService"))
local PvP = require(ServerScriptService:WaitForChild("PvP"))
local Injury = require(script.Parent:WaitForChild("Injury"))
local Dummies = require(script.Parent:WaitForChild("Dummies"))
local Hazards = require(script.Parent:WaitForChild("Hazards"))
local GunModels = require(script.Parent:WaitForChild("GunModels")) -- (2026-11-14) one real-looking model per gun tier
local Powers = require(script.Parent:WaitForChild("Powers")) -- (2026-11-14) each fighter's MOVE leaves its own wound
local C = Color3.fromRGB

-- (2026-11-14, sandbox shop) a player's slider multiplier (HudShared.SliderCatalog; ShopService.Ext.Sliders writes it)
local function attrMul(p, attr, lo, hi)
	local v = typeof(p) == "Instance" and p:GetAttribute(attr)
	if type(v) ~= "number" or v ~= v then
		return 1
	end
	return math.clamp(v, lo, hi)
end
local function dmgMul(p)
	return attrMul(p, "DamageMul", 0.25, 10)
end
local function flingMul(p)
	return attrMul(p, "FlingMul", 0.25, 6)
end
-- whose Fling Power a ragdoll fling uses: the player this script is resolving a weapon for (flingBy, set around its own
-- Fling / Jolt calls), else the fighter whose power is landing right now (PvP's aim, fresh)
local flingBy = nil
RagdollService.flingScale = function(model)
	local p = flingBy
	if not p and PvP.aimCaster and os.clock() - (PvP.aimT or -1) < 0.3 then
		p = PvP.aimCaster
	end
	return p and flingMul(p) or 1
end
local function withFling(p, fn, ...)
	flingBy = p
	local ok, a = pcall(fn, ...)
	flingBy = nil
	if not ok then
		warn("[Sandbox] " .. tostring(a))
	end
	return a
end
local koHook = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 10)
koHook = koHook and koHook:WaitForChild("KO", 10)

RagdollService.clientJolt = function(player, model, vel) -- a body that player's client is simulating was hit again
	Net:FireClient(player, "jolt", model, vel)
end
Injury.ragdoll = function(model, duration)
	-- (2026-11-14) Stay, not Ragdoll: a wound that puts a body down brings no push of its own, so it must not take the
	-- body back from the client that is simulating it (in mid-flight that was a jump backwards on their screen)
	if RagdollService.Stay then
		RagdollService.Stay(model, duration)
	else
		RagdollService.Ragdoll(model, duration)
	end
end
-- (2026-11-14) who is behind the push the server is resolving right now: the player this script is resolving a weapon
-- for, else the fighter whose power is landing (PvP's aim, fresh). RagdollService hands the body to THAT player's
-- client from the next step, so it reacts on their screen at once; a push nobody is behind stays on the server.
RagdollService.lendFor = function(model)
	if flingBy then
		return flingBy
	end
	if PvP.aimCaster and os.clock() - (PvP.aimT or -1) < 0.3 then
		return PvP.aimCaster
	end
	return nil
end
Injury.onEvent = function(model, text, sev, uid)
	Net:FireAllClients("inj", model, text, sev, uid)
end

------------------------------------------------------------------------------------------------------------ stats
local stats = {} -- [player] = { kills, time, damage, session }
local okS, store = pcall(function() return DataStoreService:GetDataStore("RagdollStats_v1") end)
local boards = {}
for _, k in ipairs({ "Kills", "Time", "Damage" }) do
	local ok, ds = pcall(function() return DataStoreService:GetOrderedDataStore("RagdollLB_" .. k .. "_v1") end)
	boards[k] = ok and ds or nil
end
-- (2026-11-15, owner: "access old weapons after passing the quest") the gun in hand: GunPick, any tier already
-- unlocked (checked here, so a client cannot pick one it has not earned); without one, the newest.
local function gunOf(p)
	local top = p:GetAttribute("GunTier") or 1
	local pick = tonumber(p:GetAttribute("GunPick")) or top
	return Config.GUNS[math.clamp(math.floor(pick), 1, top)] or Config.GUNS[1]
end
local function gunTier(kills)
	local t = 1
	for i, g in ipairs(Config.GUNS) do
		if kills >= g.kills then
			t = i
		end
	end
	return t
end
local function killCounter(p)
	local ls = p:FindFirstChild("leaderstats")
	local kills = ls and ls:FindFirstChild("Kills")
	if kills and not kills:IsA("IntValue") then -- (the fighting game's HIDE MY KILLS setting keeps the real number here)
		local hs = p:FindFirstChild("HiddenStats")
		kills = hs and hs:FindFirstChild("Kills")
	end
	return kills
end
local function credit(p, amount)
	local s = stats[p]
	if s and amount == amount and amount > 0 then
		s.damage += amount
	end
end
local function onJoin(p)
	local s = { kills = 0, time = 0, damage = 0, session = 0 }
	stats[p] = s
	task.spawn(function()
		local ls = p:WaitForChild("leaderstats", 4)
		if not ls then
			ls = Instance.new("Folder")
			ls.Name = "leaderstats"
			ls.Parent = p
		end
		if not ls:FindFirstChild("Kills") then
			local v = Instance.new("IntValue")
			v.Name = "Kills"
			v.Parent = ls
		end
		local tv = ls:FindFirstChild("Minutes") or Instance.new("IntValue")
		tv.Name = "Minutes"
		tv.Parent = ls
	end)
	if okS and store then
		local ok, saved = pcall(function() return store:GetAsync("u" .. p.UserId) end)
		if ok and type(saved) == "table" then
			s.kills, s.time, s.damage = tonumber(saved.kills) or 0, tonumber(saved.time) or 0, tonumber(saved.damage) or 0
		end
	end
	p:SetAttribute("TotalKills", s.kills)
	p:SetAttribute("GunTier", gunTier(s.kills))
	p:SetAttribute("Weapon", "fists")
end
local function save(p)
	local s = stats[p]
	if not s or not okS or not store then
		return
	end
	pcall(function() store:SetAsync("u" .. p.UserId, { kills = s.kills, time = math.floor(s.time), damage = math.floor(s.damage) }) end)
	local vals = { Kills = s.kills, Time = math.floor(s.time), Damage = math.floor(s.damage) }
	for k, ds in pairs(boards) do
		if ds and vals[k] > 0 then
			pcall(function() ds:SetAsync(tostring(p.UserId), vals[k]) end)
		end
	end
end
Dummies.onKill = function(p, model, downOnly) -- downOnly: put down for good, not dead (Dummies counts both, once per body)
	if koHook then
		koHook:Fire(p, model) -- (2026-11-14) the killer's kill effect
	end
	local s = stats[p]
	if not s then
		return
	end
	s.kills += 1
	s.session += 1
	local kc = killCounter(p)
	if kc then
		kc.Value += 1
	end
	p:SetAttribute("TotalKills", s.kills)
	local before, now = p:GetAttribute("GunTier") or 1, gunTier(s.kills)
	if now > before then
		p:SetAttribute("GunTier", now)
		p:SetAttribute("GunPick", now) -- a new gun goes straight into your hand; the old ones stay pickable
		Net:FireClient(p, "tier", now)
	end
	if not downOnly then
		Net:FireClient(p, "kill", model:GetAttribute("Cause") or "") -- the KILL toast names a cause of death; a body that is only down has none
	end
end

-- leaderboards: three boards at the hub (tag Leaderboard, named LB_Kills / LB_Time / LB_Damage)
local nameCache = {}
local function nameOf(uid)
	if nameCache[uid] then
		return nameCache[uid]
	end
	local pl = Players:GetPlayerByUserId(uid)
	local ok, n = true, pl and pl.Name
	if not n then
		ok, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
	end
	nameCache[uid] = (ok and n) or ("Player " .. uid)
	return nameCache[uid]
end
local function fmt(kind, v)
	if kind == "Time" then
		local h, m = math.floor(v / 3600), math.floor(v % 3600 / 60)
		return (h > 0) and (h .. "h " .. m .. "m") or (m .. "m")
	elseif v >= 1e6 then
		return string.format("%.1fM", v / 1e6)
	elseif v >= 1e4 then
		return string.format("%.1fK", v / 1e3)
	end
	return tostring(math.floor(v))
end
local TITLES = { Kills = "MOST KILLS", Time = "MOST TIME PLAYED", Damage = "MOST DAMAGE DEALT" }
local function drawBoard(part, kind, rows)
	local g = part:FindFirstChild("Board")
	if not g then
		g = Instance.new("SurfaceGui")
		g.Name = "Board"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.LightInfluence = 0 -- (2026-11-13) like every sign: white lettering must read on the shaded side too
		g.Parent = part
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size, title.Position = UDim2.new(1, -24, 0, 62), UDim2.fromOffset(12, 8)
		title.BackgroundTransparency = 1
		title.Font, title.TextScaled, title.TextColor3 = Enum.Font.GothamBold, true, C(255, 255, 255) -- (2026-11-13) signs are white on black, in a plain face
		title.Text = TITLES[kind]
		title.Parent = g
		local bar = Instance.new("Frame")
		bar.Size, bar.Position = UDim2.new(1, -24, 0, 4), UDim2.fromOffset(12, 72)
		bar.BackgroundColor3, bar.BorderSizePixel = C(255, 255, 255), 0
		bar.Parent = g
		for i = 1, 10 do
			local row = Instance.new("TextLabel")
			row.Name = "Row" .. i
			row.Size, row.Position = UDim2.new(1, -40, 0, 26), UDim2.fromOffset(20, 80 + (i - 1) * 27)
			row.BackgroundTransparency = (i % 2 == 0) and 1 or 0.9
			row.BackgroundColor3 = C(255, 255, 255)
			row.BorderSizePixel = 0
			row.Font, row.TextSize, row.TextColor3 = Enum.Font.GothamBold, 20, C(236, 236, 240)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = ""
			row.Parent = g
			local val = Instance.new("TextLabel")
			val.Name = "Val"
			val.Size, val.BackgroundTransparency = UDim2.fromScale(1, 1), 1
			val.Font, val.TextSize, val.TextColor3 = Enum.Font.GothamBold, 20, C(255, 255, 255)
			val.TextXAlignment = Enum.TextXAlignment.Right
			val.Text = ""
			val.Parent = row
		end
	end
	for i = 1, 10 do
		local row = g:FindFirstChild("Row" .. i)
		local r = rows[i]
		row.Text = r and ("  " .. i .. ".  " .. r[1]) or ""
		row.Val.Text = r and (fmt(kind, r[2]) .. "  ") or ""
		row.TextColor3 = C(255, 255, 255) -- (2026-11-13) first place was gold: the boards are white on black like every sign
	end
end
local function refreshBoards()
	for _, kind in ipairs({ "Kills", "Time", "Damage" }) do
		local rows = {}
		local ds = boards[kind]
		local ok = false
		if ds then
			ok = pcall(function()
				local page = ds:GetSortedAsync(false, 10):GetCurrentPage()
				for _, e in ipairs(page) do
					table.insert(rows, { nameOf(tonumber(e.key)), e.value })
				end
			end)
		end
		-- the people here right now always count (and are all there is in a Studio test)
		local live = {}
		for p, s in pairs(stats) do
			live[p.Name] = ({ Kills = s.kills, Time = s.time, Damage = s.damage })[kind]
		end
		for _, r in ipairs(rows) do
			if live[r[1]] then
				r[2] = math.max(r[2], live[r[1]])
				live[r[1]] = nil
			end
		end
		for n, v in pairs(live) do
			if v > 0 or not ok then
				table.insert(rows, { n, v })
			end
		end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		for _, part in ipairs(CollectionService:GetTagged("Leaderboard")) do
			if part.Name == "LB_" .. kind then
				drawBoard(part, kind, rows)
			end
		end
	end
end
task.spawn(function()
	while true do
		refreshBoards()
		task.wait(45)
	end
end)
task.spawn(function()
	local n = 0
	while true do
		task.wait(10)
		n += 1
		for p, s in pairs(stats) do
			s.time += 10
			local ls = p:FindFirstChild("leaderstats")
			local tv = ls and ls:FindFirstChild("Minutes")
			if tv then
				tv.Value = math.floor(s.time / 60)
			end
			if n % 12 == 0 then
				task.spawn(save, p)
			end
		end
	end
end)
game:BindToClose(function()
	for p in pairs(stats) do
		save(p)
	end
end)

--------------------------------------------------------------------------------------------- fighters -> injuries
-- { M1 wound, ability wound } per fighter
local KIT = { Limitless = { "blunt", "blast" }, Vulpine = { "blunt", "blast" }, Godspeed = { "shock", "shock" }, OneForAll = { "blunt", "blast" },
	Tempest = { "slash", "shock" }, Carver = { "slash", "slash" }, Shifter = { "slash", "crush" }, Zangetsu = { "slash", "slash" },
	Ascendant = { "blunt", "burn" }, Gomu = { "blunt", "blunt" }, Stormdraw = { "slash", "shock" } }
local function pickPart(model, from)
	local list = {}
	for _, n in ipairs(Injury.ORDER) do
		local p = model:FindFirstChild(n)
		if p then
			table.insert(list, { p, from and (p.Position - from).Magnitude or math.random() })
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b) return a[2] < b[2] end)
	local r = math.random()
	local i = (r < 0.42) and 1 or ((r < 0.72) and 2 or ((r < 0.88) and 3 or 4))
	return list[math.min(i, #list)][1]
end
local function bodyHit(hum, amount, m1, base)
	local model = hum.Parent
	-- (2026-11-14) a fighter's hit is about to push this body with the kit's own code: if a client is simulating it,
	-- the server takes it back first so the push lands (RagdollService gives it to the attacker the step after)
	if RagdollService.Claim then
		RagdollService.Claim(model)
	end
	local st = Injury.get(model)
	if not st or amount < 0.5 then
		return
	end
	local by, from = PvP.aimCaster, PvP.aimFrom
	if by then
		credit(by, amount)
	end
	-- (2026-11-14) the move decides the wound (Sandbox.Powers: a Hollow Purple erases, a Rasenshuriken pricks the whole
	-- body through, a Chidori goes in one side and out the other ...). What it does not know falls through to the
	-- fighter's plain wound below. Every kit stamps LastHitBy just before its damage call, so that names the attacker
	-- when the attack was resolved away from them.
	local who = by
	if not who then
		local uid = model:GetAttribute("LastHitBy")
		who = uid and Players:GetPlayerByUserId(uid) or nil
	end
	local okP, handled = pcall(Powers.hit, hum, amount, base or amount, m1, who, from)
	if not okP then
		warn("[Sandbox] Powers: " .. tostring(handled))
	elseif handled then
		return
	end
	st.tick = (st.tick or 0) + amount -- domain / burn ticks gather into one wound
	if amount < 6 and st.tick < 12 then
		return
	end
	local amt = st.tick * 1.5
	st.tick = 0
	local kinds = KIT[by and by:GetAttribute("Kit") or ""] or { "blunt", "blunt" }
	local kind = m1 and kinds[1] or kinds[2]
	local part = pickPart(model, from)
	if not part then
		return
	end
	local dir = from and (part.Position - from) or Vector3.zero
	dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero
	if kind == "blast" and amt >= 45 then
		Injury.blast(model, part.Position - dir * 3, 10, amt, by)
	else
		Injury.hit(model, { part = part, pos = part.Position - dir * 0.6, type = kind, amount = amt, attacker = by, dir = dir })
	end
end

-- (2026-11-14) a power landing on a dummy: x the attacker's Strength slider, then the injury system reads it
PvP.onBodyHit = function(hum, amount, m1)
	local k = PvP.aimCaster and dmgMul(PvP.aimCaster) or 1
	local a = amount * k
	bodyHit(hum, a, m1, amount)
	return a
end

---------------------------------------------------------------------------------------------------- weapon models
-- parts in the hand's grip frame: melee weapons run along +Y, guns point along -Z (see RightGripAttachment)
local WOOD, STEEL, DARK, GOLD = C(186, 146, 96), C(206, 210, 218), C(40, 42, 48), C(214, 176, 80)
local MODELS = {
	bat = { { "cyl", 0.3, 1.3, 0, 0.35, 0, DARK }, { "cyl", 0.52, 2.7, 0, 2.3, 0, WOOD, Enum.Material.Wood } },
	axe = { { "box", 0.24, 3.6, 0.24, 0, 1.5, 0, C(110, 78, 50), Enum.Material.Wood }, { "box", 0.34, 0.9, 0.7, 0, 2.9, -0.25, DARK, Enum.Material.Metal },
		{ "box", 0.1, 1.4, 0.9, 0, 2.9, -0.95, STEEL, Enum.Material.Metal } },
	katana = { { "cyl", 0.22, 1.2, 0, 0.3, 0, DARK }, { "cyl", 0.72, 0.08, 0, 0.94, 0, GOLD, Enum.Material.Metal }, { "box", 0.07, 3.8, 0.32, 0, 2.86, 0, STEEL, Enum.Material.Metal } },
	sledge = { { "box", 0.26, 4, 0.26, 0, 1.7, 0, C(110, 78, 50), Enum.Material.Wood }, { "box", 1.1, 1.1, 1.7, 0, 3.7, 0, DARK, Enum.Material.Metal } },
	pistol = { { "box", 0.3, 0.42, 1.5, 0, 0.4, -0.5, DARK, Enum.Material.Metal }, { "box", 0.28, 0.85, 0.42, 0, -0.1, 0, C(60, 44, 34) } },
	revolver = { { "box", 0.26, 0.36, 1.9, 0, 0.42, -0.7, STEEL, Enum.Material.Metal }, { "cyl", 0.5, 0.5, 0, 0.36, -0.15, STEEL, Enum.Material.Metal, "z" }, { "box", 0.28, 0.9, 0.42, 0, -0.1, 0.05, C(96, 60, 40) } },
	smg = { { "box", 0.36, 0.55, 2, 0, 0.42, -0.6, DARK, Enum.Material.Metal }, { "box", 0.24, 1.1, 0.3, 0, -0.3, -0.7, DARK }, { "box", 0.28, 0.8, 0.4, 0, -0.1, 0, DARK } },
	shotgun = { { "cyl", 0.3, 3.2, 0, 0.44, -1.3, DARK, Enum.Material.Metal, "z" }, { "box", 0.34, 0.4, 1, 0, 0.2, -1.4, C(110, 78, 50), Enum.Material.Wood }, { "box", 0.3, 0.6, 1.3, 0, 0.2, 0.6, C(110, 78, 50), Enum.Material.Wood } },
	rifle = { { "box", 0.34, 0.5, 3, 0, 0.44, -1, DARK, Enum.Material.Metal }, { "box", 0.24, 1, 0.4, 0, -0.25, -0.7, DARK }, { "box", 0.3, 0.55, 1.3, 0, 0.3, 0.9, DARK }, { "box", 0.28, 0.8, 0.4, 0, -0.1, 0, DARK } },
	sniper = { { "cyl", 0.24, 4.6, 0, 0.44, -1.8, DARK, Enum.Material.Metal, "z" }, { "cyl", 0.4, 1.4, 0, 0.85, -0.6, DARK, Enum.Material.Metal, "z" }, { "box", 0.3, 0.6, 1.5, 0, 0.3, 0.9, C(70, 80, 60) }, { "box", 0.28, 0.8, 0.4, 0, -0.1, 0, DARK } },
	minigun = { { "cyl", 0.95, 3.2, 0, 0.2, -1.6, STEEL, Enum.Material.Metal, "z" }, { "box", 1, 1, 1.4, 0, 0.2, 0.3, DARK, Enum.Material.Metal }, { "box", 0.3, 0.3, 1.2, 0, 0.9, -0.2, DARK } },
	launcher = { { "cyl", 1, 4.4, 0, 0.6, -0.6, C(70, 86, 64), Enum.Material.Metal, "z" }, { "cyl", 1.2, 0.5, 0, 0.6, -2.9, DARK, Enum.Material.Metal, "z" }, { "box", 0.28, 0.8, 0.4, 0, -0.1, 0, DARK } },
}
-- (2026-11-15) THE BOW, built in the grip frame (Sandbox.GunModels' convention: the hand at the origin, +Y up, -Z ahead):
-- a leather grip, two wooden limbs curving back toward the archer to gold tips, and the string between the tips.
-- Named parts the clients use: BowGrip, TipTop, TipBottom, String (the drawn string and the nocked arrow follow them).
local function buildBow(base, m, hand)
	local WOOD, DARK, GOLD, STRING = Color3.fromRGB(122, 76, 42), Color3.fromRGB(62, 38, 24), Color3.fromRGB(222, 182, 92), Color3.fromRGB(236, 232, 220)
	local function add(name, size, cf, color, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color, p.Material = color, mat or Enum.Material.Wood
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CFrame = base * cf
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hand, p
		w.Parent = p
		p.Parent = m
		return p
	end
	add("BowGrip", Vector3.new(0.34, 1.1, 0.44), CFrame.identity, DARK, Enum.Material.Fabric)
	local pts = { { 0.5, 0 }, { 1.2, 0.1 }, { 1.9, 0.34 }, { 2.55, 0.78 } } -- (y, z) along a limb
	for _, s in ipairs({ 1, -1 }) do
		for i = 1, #pts - 1 do
			local a, b = Vector3.new(0, pts[i][1] * s, pts[i][2]), Vector3.new(0, pts[i + 1][1] * s, pts[i + 1][2])
			local d = b - a
			add("Limb", Vector3.new(0.2, d.Magnitude + 0.12, 0.3 - i * 0.04), CFrame.new((a + b) / 2) * CFrame.Angles(math.atan2(d.Z, d.Y), 0, 0), WOOD)
		end
		add(s == 1 and "TipTop" or "TipBottom", Vector3.new(0.24, 0.3, 0.24), CFrame.new(0, pts[#pts][1] * s, pts[#pts][2]), GOLD, Enum.Material.Metal)
	end
	local tip = pts[#pts]
	add("String", Vector3.new(0.05, tip[1] * 2, 0.05), CFrame.new(0, 0, tip[2]), STRING, Enum.Material.SmoothPlastic)
end

local function buildWeapon(char, id)
	local old = char:FindFirstChild("SandboxWeapon")
	if old then
		old:Destroy()
	end
	local spec = MODELS[id]
	local hand = char:FindFirstChild("RightHand")
	if not (spec or GunModels.PARTS[id] or id == "bow") or not hand then
		return
	end
	local grip = hand:FindFirstChild("RightGripAttachment")
	local base = grip and grip.WorldCFrame or (hand.CFrame * CFrame.Angles(math.rad(-90), 0, 0))
	local m = Instance.new("Model")
	m.Name = "SandboxWeapon"
	if id == "bow" then
		buildBow(base, m, hand)
		m.Parent = char
		return
	end
	if GunModels.PARTS[id] then -- (2026-11-14) the guns: Sandbox.GunModels (the old block guns below are unused)
		GunModels.build(id, base, m, hand)
		m.Parent = char
		return
	end
	for _, s in ipairs(spec) do
		local p = Instance.new("Part")
		local cf, color, mat, ax
		if s[1] == "cyl" then
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(s[3], s[2], s[2])
			cf, color, mat, ax = CFrame.new(s[4], s[5], s[6]), s[7], s[8], s[9]
			cf = cf * ((ax == "z") and CFrame.Angles(0, math.pi / 2, 0) or CFrame.Angles(0, 0, math.pi / 2))
		else
			p.Size = Vector3.new(s[2], s[3], s[4])
			cf, color, mat = CFrame.new(s[5], s[6], s[7]), s[8], s[9]
		end
		p.Color, p.Material = color, mat or Enum.Material.SmoothPlastic
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CFrame = base * cf
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hand, p
		w.Parent = p
		p.Parent = m
	end
	m.Parent = char
end

--------------------------------------------------------------------------------------------------------- attacks
local nextAt = setmetatable({}, { __mode = "k" })
local function body(p)
	local c = p.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		return c, hrp
	end
end
local function aim(p, origin, dir, hrp)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 or origin ~= origin or dir ~= dir then
		return nil
	end
	if (origin - hrp.Position).Magnitude > 45 then
		origin = hrp.Position + Vector3.new(0, 2, 0)
	end
	return origin, dir.Unit
end
local function rayDist(origin, dir, point)
	local t = math.max(0, (point - origin):Dot(dir))
	return (origin + dir * t - point).Magnitude, origin + dir * t
end
local function shove(part, impulse, p)
	if part and part.Parent and not part.Anchored then
		pcall(function()
			part:SetNetworkOwner(nil) -- an impulse from here only takes on a part the server owns
			part:ApplyImpulse(impulse * part.AssemblyMass)
			if p then -- ...then the hitter's client simulates it, so it moves at once on their screen
				part:SetNetworkOwner(p)
				task.delay(4, function()
					if part.Parent and not part.Anchored then
						pcall(function()
							part:SetNetworkOwnershipAuto()
						end)
					end
				end)
			end
		end)
	end
end
local function melee(p, id, origin, dir)
	local W = Config.WEAPONS[id]
	local char, hrp = body(p)
	if not W or not W.dmg or not char then
		return
	end
	origin, dir = aim(p, origin, dir, hrp)
	if not origin then
		return
	end
	Net:FireAllClients("swing", p, id)
	-- (2026-11-13) the wind-up is the swing reaching its strike on the attacker's screen; take the trip here off it so
	-- the blow lands AT the strike, not a ping after it
	task.wait(math.max(W.wind * 0.4, W.wind - (p:GetNetworkPing() + 0.03)))
	char, hrp = body(p)
	if not char then
		return
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") }
	local seen = workspace:Raycast(origin, dir * 250, rp)
	local aimPt = seen and seen.Position or (origin + dir * 60)
	local flat = (aimPt - hrp.Position) * Vector3.new(1, 0, 1)
	flat = flat.Magnitude > 0.5 and flat.Unit or hrp.CFrame.LookVector
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local found, propsHit = {}, {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(hrp.Position + flat * W.range * 0.55, W.range * 0.62 + 1, params)) do
		local m = Dummies.of(part)
		if m then
			if Injury.REG[part.Name] and (part.Position - hrp.Position):Dot(flat) > -1 then
				local d, at = rayDist(origin, dir, part.Position)
				if not found[m] or d < found[m][2] then
					found[m] = { part, d, at }
				end
			end
		elseif not part.Anchored and not Players:GetPlayerFromCharacter(part.Parent) and part.Name ~= "Wound" then
			propsHit[part.AssemblyRootPart or part] = part
		end
	end
	local list = {}
	for m, f in pairs(found) do
		table.insert(list, { m, f[1], f[2], f[3] })
	end
	table.sort(list, function(a, b) return a[3] < b[3] end)
	for i = 1, math.min(3, #list) do
		local m, part, _, at = list[i][1], list[i][2], list[i][3], list[i][4]
		local dmg = W.dmg * (0.9 + math.random() * 0.2) * (i == 1 and 1 or 0.7) * dmgMul(p)
		local wasDead = m:GetAttribute("Dead")
		Hazards.hurt(m, part, W.type, dmg, p, flat, at)
		local vel = flat * W.knock + Vector3.new(0, W.lift, 0)
		if wasDead or RagdollService.IsRagdolled(m) then
			withFling(p, RagdollService.Jolt, m, vel * 0.7, true)
		else
			withFling(p, RagdollService.Fling, m, vel, nil, W.rag)
		end
		RagdollService.Lend(m, p) -- the attacker's client simulates it from here: no 0.23 s wait to see it react
		if i == 1 then
			Net:FireClient(p, "hit", at, W.type, dmg)
		end
		Hazards.sfx((W.type == "slash") and "slash" or ((W.type == "crush") and "heavy" or "hit"), part.Position, 0.9, (W.type == "crush") and 0.8 or 1)
	end
	for root, part in pairs(propsHit) do
		if (part.Position - hrp.Position):Dot(flat) > 0 and not Hazards.damageProp(part, W.dmg * dmgMul(p), p) then
			shove(root, (flat * W.knock * 1.1 + Vector3.new(0, W.lift * 0.6, 0)) * flingMul(p), p)
		end
	end
end
local npcOnly = RaycastParams.new() -- (the near-miss sweep in shoot sees bodies only)
npcOnly.FilterType = Enum.RaycastFilterType.Include
local function shoot(p, origin, dir)
	local char, hrp = body(p)
	if not char then
		return
	end
	origin, dir = aim(p, origin, dir, hrp)
	if not origin then
		return
	end
	local G = gunOf(p)
	local gd = G.dmg * dmgMul(p) -- (2026-11-14) Strength slider; knockback below stays on the gun's own numbers
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") }
	local hand = char:FindFirstChild("RightHand")
	-- the gun's own barrel tip when it has one (each client re-aims the tracer at ITS view of the barrel - the server's
	-- arm is not in the held pose)
	local wm = char:FindFirstChild("SandboxWeapon")
	local mz = wm and wm:FindFirstChild("Muzzle")
	local muzzle = (mz and mz:IsA("BasePart") and mz.Position) or (hand and (hand.Position + dir * 2)) or origin
	-- (2026-11-14) fast guns fire many light rounds, so each pushes a downed body less: at 13 rounds a second the SMG
	-- skated bodies across the ground
	local rate = math.clamp(G.cd / 0.3, 0.25, 1)
	local npcs = Dummies.folder or workspace:FindFirstChild("NPCs")
	if npcs then
		npcOnly.FilterDescendantsInstances = { npcs }
	end
	local ends = {}
	for _ = 1, G.pellets do
		local d = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(math.rad((math.random() - 0.5) * 2 * G.spread), math.rad((math.random() - 0.5) * 2 * G.spread), 0)).LookVector
		local hit = workspace:Raycast(origin, d * G.range, params)
		-- (2026-11-14) a near miss on a body counts: a thin sphere swept down the same line, stopped where the ray hit
		-- something, so far-away shots land (a body is 2 studs wide) without anyone shooting through a wall
		if npcs and not (hit and Dummies.of(hit.Instance)) then
			local near = workspace:Spherecast(origin, 0.8, d * (hit and hit.Distance or G.range), npcOnly)
			if near and Dummies.of(near.Instance) then
				hit = near
			end
		end
		local at = hit and hit.Position or (origin + d * G.range)
		table.insert(ends, at)
		if hit then
			if G.explosive then
				withFling(p, Hazards.blastAt, at, G.explosive, gd, p)
			else
				local m = Dummies.of(hit.Instance)
				if m then
					local wasDead = m:GetAttribute("Dead")
					-- (2026-11-14) this hit's reaction is decided here: HitReactServer must not ALSO slide the body back. A
					-- standing body pushed back a step per round, and never falling, was the owner's SMG complaint.
					m:SetAttribute("HitSeq", (tonumber(m:GetAttribute("HitSeq")) or 0) + 1)
					Hazards.hurt(m, hit.Instance, "bullet", gd, p, d, at)
					if wasDead or RagdollService.IsRagdolled(m) then
						withFling(p, RagdollService.Jolt, m, d * math.min(40, G.dmg * 0.5) * rate, true)
					else -- (2026-11-14) EVERY gun drops a standing body (the SMG and minigun, under 25 damage, never did)
						withFling(p, RagdollService.Fling, m, d * math.clamp(G.dmg * 0.6, 14, 46) + Vector3.new(0, 6, 0), nil, 1.4)
					end
					if RagdollService.IsRagdolled(m) then
						RagdollService.Lend(m, p)
					end
				elseif not hit.Instance.Anchored then
					if not Hazards.damageProp(hit.Instance, gd, p) then
						shove(hit.Instance, d * math.min(60, G.dmg) * flingMul(p), p)
					end
				end
			end
		end
	end
	Net:FireAllClients("shot", p, muzzle, ends, G.id)
end

------------------------------------------------------------------------------------------------------------- bow
-- (2026-11-15) an arrow: the client sends ("arrow", from, dir, draw 0..1) when the draw is let go. It flies here on a
-- real arc - stepped every frame (raycast + a thin sweep for near misses on bodies, as the gun) - and every client draws
-- the same arc from the launch broadcast ("arrow", player, from, velocity, gravity). Players are not targets (it flies
-- through them). What it hits: a dummy is wounded like a gunshot (x headMul in the head), pushed, and the arrow stays
-- in the limb (welded: it rides along when the body falls or the limb comes off); a loose prop is hit / shoved and
-- keeps the arrow; the world keeps it where it struck. Stuck arrows live in workspace.Arrows, maxStuck at most.
local arrowsFolder = workspace:FindFirstChild("Arrows") or Instance.new("Folder")
arrowsFolder.Name = "Arrows"
arrowsFolder.Parent = workspace
local stuckList = {}
local function buildArrow(cf)
	local m = Instance.new("Model")
	m.Name = "Arrow"
	local function add(size, off, color, mat, shaft)
		local p = Instance.new("Part")
		p.Size = size
		p.Color, p.Material = color, mat
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless, p.CastShadow = false, false, false, true, false
		p.CFrame = cf * off
		p.Name = shaft and "Shaft" or "Bit"
		p.Parent = m
		return p
	end
	local shaft = add(Vector3.new(0.11, 0.11, 3), CFrame.identity, Color3.fromRGB(176, 132, 84), Enum.Material.Wood, true)
	local bits = {
		add(Vector3.new(0.2, 0.2, 0.42), CFrame.new(0, 0, -1.65) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(70, 72, 80), Enum.Material.Metal),
		add(Vector3.new(0.03, 0.34, 0.55), CFrame.new(0, 0, 1.2), Color3.fromRGB(220, 60, 60), Enum.Material.SmoothPlastic),
		add(Vector3.new(0.34, 0.03, 0.55), CFrame.new(0, 0, 1.2), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic),
	}
	for _, b in ipairs(bits) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = shaft, b
		w.Parent = b
	end
	m.PrimaryPart = shaft
	return m, shaft
end
local function stickArrow(at, dir, part)
	local B = Config.WEAPONS.bow.bow
	-- the head 0.6 studs in: the shaft's centre is 1.25 behind the tip
	local m, shaft = buildArrow(CFrame.lookAt(at - dir * 1.25, at - dir * 1.25 + dir))
	if part and not part.Anchored then
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = part, shaft
		w.Parent = shaft
	else
		shaft.Anchored = true
	end
	m.Parent = arrowsFolder
	table.insert(stuckList, m)
	while #stuckList > B.maxStuck do
		local old = table.remove(stuckList, 1)
		if old.Parent then
			old:Destroy()
		end
	end
	task.delay(B.stuckLife, function()
		local i = table.find(stuckList, m)
		if i then
			table.remove(stuckList, i)
		end
		if m.Parent then
			m:Destroy()
		end
	end)
end
local function fireArrow(p, from, dir, draw)
	local char, hrp = body(p)
	if not char or typeof(from) ~= "Vector3" or typeof(dir) ~= "Vector3" or from ~= from or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	if (from - hrp.Position).Magnitude > 9 then
		from = hrp.Position + Vector3.new(0, 1.5, 0)
	end
	dir = dir.Unit
	local B = Config.WEAPONS.bow.bow
	draw = math.clamp(tonumber(draw) or 0, 0.1, 1)
	local vel = dir * (B.minSpeed + (B.speed - B.minSpeed) * draw)
	local dmg = (B.minDmg + (B.dmg - B.minDmg) * draw) * dmgMul(p)
	Net:FireAllClients("arrow", p, from, vel, B.gravity)
	local ignore = { arrowsFolder, workspace:FindFirstChild("FX"), workspace:FindFirstChild("MapEventsFX") }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local npcs = Dummies.folder or workspace:FindFirstChild("NPCs")
	if npcs then
		npcOnly.FilterDescendantsInstances = { npcs }
	end
	local g = Vector3.new(0, -B.gravity, 0)
	local pos, t = from, 0
	while t < B.life do
		local dt = RunService.Heartbeat:Wait()
		t += dt
		local step = vel * dt + g * (0.5 * dt * dt)
		local hit = workspace:Raycast(pos, step, params)
		if npcs and not (hit and Dummies.of(hit.Instance)) then
			local near = workspace:Spherecast(pos, 0.45, hit and (step.Unit * hit.Distance) or step, npcOnly)
			if near and Dummies.of(near.Instance) then
				hit = near
			end
		end
		if hit then
			local at = hit.Position
			local d = (vel + g * dt).Unit
			local part = hit.Instance
			local m = Dummies.of(part)
			if m then
				local wasDead = m:GetAttribute("Dead")
				local hd = dmg * ((part.Name == "Head") and B.headMul or 1)
				m:SetAttribute("HitSeq", (tonumber(m:GetAttribute("HitSeq")) or 0) + 1)
				Hazards.hurt(m, part, "bullet", hd, p, d, at)
				if wasDead or RagdollService.IsRagdolled(m) then
					withFling(p, RagdollService.Jolt, m, d * (6 + 18 * draw), true)
				else
					withFling(p, RagdollService.Fling, m, d * (10 + 28 * draw) + Vector3.new(0, 4, 0), nil, 1.3)
				end
				if RagdollService.IsRagdolled(m) then
					RagdollService.Lend(m, p)
				end
				Net:FireClient(p, "hit", at, "bullet", hd)
				Hazards.sfx("hit", at, 0.8, 1.5)
				if part.Parent then
					stickArrow(at, d, part)
				end
			elseif not part.Anchored then
				if not Hazards.damageProp(part, dmg, p) then
					shove(part.AssemblyRootPart or part, d * (10 + 20 * draw) * flingMul(p), p)
					if part.Parent then
						stickArrow(at, d, part)
					end
				end
				Hazards.sfx("hit", at, 0.6, 1.7)
			else
				stickArrow(at, d, nil)
				Hazards.sfx("hit", at, 0.5, 1.9)
			end
			return
		end
		pos += step
		vel += g * dt
		if pos.Y < -150 then
			return
		end
	end
end

------------------------------------------------------------------------------------------------------------ grab
local grabs = {}
local function release(p, throw)
	local g = grabs[p]
	if not g then
		return
	end
	grabs[p] = nil
	if g.align then
		g.align:Destroy()
	end
	if g.att then
		g.att:Destroy()
	end
	if g.model and g.model.Parent then
		g.model:SetAttribute("GrabbedBy", nil)
		if not g.model:GetAttribute("Dead") then
			RagdollService.Ragdoll(g.model, 1.6)
		end
	end
	if g.part and g.part.Parent and typeof(throw) == "Vector3" and throw.Magnitude > 1 then
		local v = throw.Magnitude > 150 and throw.Unit * 150 or throw
		v *= flingMul(p) -- (2026-11-14) Fling Power slider
		if v.Magnitude > 320 then
			v = v.Unit * 320
		end
		if g.model then
			for _, part in ipairs(g.model:GetChildren()) do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = v
				end
			end
		else
			g.part.AssemblyLinearVelocity = v
		end
	end
end
local function grab(p, part, localPos)
	local char, hrp = body(p)
	if not char or typeof(part) ~= "Instance" or not part:IsA("BasePart") or part.Anchored or part:IsDescendantOf(char) then
		return
	end
	if Players:GetPlayerFromCharacter(part:FindFirstAncestorOfClass("Model")) or (part.Position - hrp.Position).Magnitude > 60 or part.AssemblyMass > 600 then
		return
	end
	release(p)
	local m = Dummies.of(part)
	if m then
		if m:GetAttribute("Strapped") then
			return
		end
		if m:GetAttribute("GrabbedBy") then
			return
		end
		m:SetAttribute("GrabbedBy", p.UserId)
		m:SetAttribute("LastHitBy", p.UserId)
		RagdollService.Ragdoll(m, 3)
	else
		part:SetAttribute("LastHitBy", p.UserId)
	end
	local att = Instance.new("Attachment")
	att.Name = "GrabAtt"
	att.Position = (typeof(localPos) == "Vector3" and localPos.Magnitude < 6) and localPos or Vector3.zero
	att.Parent = part
	local al = Instance.new("AlignPosition")
	al.Mode = Enum.PositionAlignmentMode.OneAttachment
	al.Attachment0 = att
	al.MaxForce = math.clamp(part.AssemblyMass * 900, 9000, 250000)
	al.MaxVelocity = 110
	al.Responsiveness = 32
	al.Position = att.WorldPosition
	al.Parent = part
	pcall(function() part:SetNetworkOwner(nil) end)
	grabs[p] = { part = part, att = att, align = al, model = m }
end
GrabAim.OnServerEvent:Connect(function(p, pos)
	local g = grabs[p]
	local _, hrp = body(p)
	if not g or not hrp or typeof(pos) ~= "Vector3" or pos ~= pos then
		return
	end
	if not g.part.Parent then
		release(p)
		return
	end
	local off = pos - hrp.Position
	if off.Magnitude > 55 then
		pos = hrp.Position + off.Unit * 55
	end
	g.align.Position = pos
	if g.model and not g.model:GetAttribute("Dead") then
		RagdollService.Ragdoll(g.model, 3)
	end
end)

----------------------------------------------------------------------------------------------------------- spawns
-- (2026-11-15, shop perk "Dummy of Anyone": HudShared.PerkCatalog DummyAnyone) a dummy wearing any Roblox user's avatar.
-- The spawn menu's ANYONE row sends ("spawn", "anyone", pos, username); an empty name or your own = you. It is one of
-- your dummies (Owner, the dummy cap). The answer goes back as Net ("anyone", ok, message) for the menu's toast.
local anyoneIds, anyoneDescs, anyoneNames = {}, {}, {}
local anyoneLast = {}
local function spawnAnyone(p, pos, name)
	if p:GetAttribute("Perk_DummyAnyone") ~= true then
		Net:FireClient(p, "anyone", false, "GET DUMMY OF ANYONE IN THE SHOP")
		return
	end
	local char, hrp = body(p)
	if not char or typeof(pos) ~= "Vector3" or pos ~= pos or (pos - hrp.Position).Magnitude > 90 then
		return
	end
	if os.clock() - (anyoneLast[p] or 0) < 1.2 then
		Net:FireClient(p, "anyone", false, "TOO FAST")
		return
	end
	anyoneLast[p] = os.clock()
	name = type(name) == "string" and string.sub(string.gsub(name, "[^%w_]", ""), 1, 20) or ""
	local uid
	if name == "" or string.lower(name) == string.lower(p.Name) then
		uid = p.UserId
	else
		uid = anyoneIds[string.lower(name)]
		if not uid then
			local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
			if not ok or type(id) ~= "number" then
				Net:FireClient(p, "anyone", false, "NOBODY IS CALLED " .. string.upper(name))
				return
			end
			uid = id
			anyoneIds[string.lower(name)] = uid
		end
	end
	local desc = anyoneDescs[uid]
	if not desc then
		local ok, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, uid)
		if not ok or not d then
			Net:FireClient(p, "anyone", false, "COULDN'T LOAD THAT AVATAR - TRY AGAIN")
			return
		end
		desc = d
		anyoneDescs[uid] = d
	end
	local real = anyoneNames[uid]
	if not real then
		local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, uid)
		real = ok and type(n) == "string" and n or name
		anyoneNames[uid] = real
	end
	local def
	for _, d in ipairs(Config.SPAWN) do
		if d.id == "dummy" then
			def = d
		end
	end
	local cap = math.floor((def and def.cap or 8) * attrMul(p, "SpawnCapMul", 1, 5) + 0.5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, Dummies.folder, workspace:FindFirstChild("Gore"), workspace:FindFirstChild("FX") }
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	local ground = hit and hit.Position or pos
	local n, oldest = Dummies.ownerCount(p)
	if n >= cap and oldest then
		Dummies.remove(oldest, true)
	end
	local m = Dummies.spawn(CFrame.lookAt(ground, Vector3.new(hrp.Position.X, ground.Y, hrp.Position.Z)), { owner = p, desc = desc:Clone(), lookOf = real })
	if m then
		Hazards.sfx("whoosh", ground, 0.5, 1.4)
		Net:FireClient(p, "anyone", true, "SPAWNED " .. string.upper(real))
	else
		Net:FireClient(p, "anyone", false, "COULDN'T BUILD THAT AVATAR")
	end
end

local function spawnThing(p, kind, pos, name)
	if kind == "anyone" then
		return spawnAnyone(p, pos, name)
	end
	local char, hrp = body(p)
	if not char or typeof(pos) ~= "Vector3" or pos ~= pos or (pos - hrp.Position).Magnitude > 90 then
		return
	end
	local def
	for _, d in ipairs(Config.SPAWN) do
		if d.id == kind then
			def = d
		end
	end
	if not def or math.abs(pos.X) > 340 or math.abs(pos.Z) > 340 then
		return
	end
	local cap = math.floor(def.cap * attrMul(p, "SpawnCapMul", 1, 5) + 0.5) -- (2026-11-14) Spawn Limit x3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, Dummies.folder, workspace:FindFirstChild("Gore"), workspace:FindFirstChild("FX") }
	local hit = workspace:Raycast(pos + Vector3.new(0, 12, 0), Vector3.new(0, -60, 0), params)
	local ground = hit and hit.Position or pos
	if kind == "dummy" then
		local n, oldest = Dummies.ownerCount(p)
		if n >= cap and oldest then
			Dummies.remove(oldest, true)
		end
		Dummies.spawn(CFrame.lookAt(ground, Vector3.new(hrp.Position.X, ground.Y, hrp.Position.Z)), { owner = p })
	else
		local n, oldest = Hazards.ownerProps(p, kind)
		if n >= cap and oldest then
			oldest:Destroy()
		end
		Hazards.makeProp(kind, CFrame.new(ground) * CFrame.Angles(0, math.random() * 6, 0), p)
	end
	Hazards.sfx("whoosh", ground, 0.5, 1.4)
end

-------------------------------------------------------------------------------------------------------------- net
local SLOT = {}
for _, s in ipairs(Config.SLOTS) do
	SLOT[s] = true
end
-- (2026-11-13) picking an anime fighter with a weapon in hand puts the weapon away
local function watchKit(p)
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		local w = p:GetAttribute("Weapon")
		if p:GetAttribute("Kit") ~= "Normal" and w ~= "fists" and w ~= "grab" then
			p:SetAttribute("Weapon", "fists")
			if p.Character then
				buildWeapon(p.Character, "fists")
			end
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	watchKit(p)
end
Players.PlayerAdded:Connect(watchKit)
Net.OnServerEvent:Connect(function(p, action, a, b, c)
	if action == "equip" then
		if type(a) ~= "string" or not SLOT[a] then
			return
		end
		-- (2026-11-13) the owner: weapons and powers are not both on offer. The bat / axe / katana / sledgehammer / gun
		-- belong to the no-powers NORMAL choice; an anime fighter has its powers and the grab.
		if a ~= "fists" and a ~= "grab" and p:GetAttribute("Kit") ~= "Normal" then
			return
		end
		release(p)
		if a == "gun" and type(b) == "number" and b == b then -- which unlocked gun (clamped to what is earned)
			p:SetAttribute("GunPick", math.clamp(math.floor(b), 1, p:GetAttribute("GunTier") or 1))
		end
		p:SetAttribute("Weapon", a)
		local char = p.Character
		if char then
			local id = a
			if a == "gun" then
				id = (gunOf(p)).id
			end
			buildWeapon(char, id)
		end
	elseif action == "swing" then
		local id = p:GetAttribute("Weapon")
		local W = Config.WEAPONS[id]
		local t = os.clock()
		if not W or not W.dmg or (nextAt[p] or 0) > t then
			return
		end
		nextAt[p] = t + W.cd * 0.9
		melee(p, id, a, b)
	elseif action == "shoot" then
		local t = os.clock()
		if p:GetAttribute("Weapon") ~= "gun" or (nextAt[p] or 0) > t then
			return
		end
		local G = gunOf(p)
		nextAt[p] = t + G.cd * 0.85
		shoot(p, a, b)
	elseif action == "arrow" then -- (2026-11-15) the bow
		local t = os.clock()
		if p:GetAttribute("Weapon") ~= "bow" or (nextAt[p] or 0) > t then
			return
		end
		nextAt[p] = t + Config.WEAPONS.bow.bow.cd * 0.8
		task.spawn(fireArrow, p, a, b, c)
	elseif action == "grab" then
		if p:GetAttribute("Weapon") == "grab" then
			grab(p, a, b)
		end
	elseif action == "release" then
		release(p, a)
	elseif action == "spawn" then
		spawnThing(p, a, b, c)
	elseif action == "clear" then
		Dummies.clearOwner(p)
		Hazards.clearOwner(p)
	end
end)
local function onCharacter(p, char)
	p:SetAttribute("Weapon", "fists")
	release(p)
end
local function hookPlayer(p)
	onJoin(p)
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(hookPlayer, p)
end
Players.PlayerAdded:Connect(hookPlayer)
-- (2026-11-14) ServerScriptService.MapSwitch fires this before it teleports a player to another map
do
	local rg = Instance.new("BindableEvent")
	rg.Name = "ReleaseGrab"
	rg.Event:Connect(function(p)
		pcall(release, p)
	end)
	rg.Parent = script
end
Players.PlayerRemoving:Connect(function(p)
	release(p)
	save(p)
	Dummies.clearOwner(p)
	Hazards.clearOwner(p)
	stats[p] = nil
end)
-- a new gun tier re-arms the hand
for _, p in ipairs(Players:GetPlayers()) do
end

-- Studio test hook: script.Debug:Invoke("hit", model, partName, type, amount, player?) / ("sever", model, partName) /
-- ("state", model) -> a summary string / ("nearest", position) -> the nearest dummy / ("melee" | "shoot", player, origin, dir)
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "Debug"
	dbg.OnInvoke = function(cmd, a1, a2, a3, a4, a5, a6)
		if cmd == "hit" then
			Hazards.hurt(a1, a2, a3, a4, a5)
			return true
		elseif cmd == "sever" then
			return Injury.sever(a1, a2, a3)
		elseif cmd == "state" then
			local st = Injury.get(a1)
			if not st then
				return "no state"
			end
			return string.format("blood %.0f bpm %.0f awake %.0f bleedA %.1f bleedM %.2f dead %s cause %s state %s last %s | %s", st.blood, st.bpm, st.awake, st.bleedA, st.bleedM,
				tostring(st.dead), tostring(st.cause), tostring(a1:GetAttribute("State")), tostring(st.lastEvent), tostring(a1:GetAttribute("Anat")))
		elseif cmd == "nearest" then
			local best, bd
			for m in pairs(Dummies.records) do
				local t = m:FindFirstChild("UpperTorso")
				if t and (not bd or (t.Position - a1).Magnitude < bd) and not m:GetAttribute("Dead") then
					best, bd = m, (t.Position - a1).Magnitude
				end
			end
			return best, bd
		elseif cmd == "count" then
			return Dummies.count()
		elseif cmd == "melee" then
			a1:SetAttribute("Weapon", a4 or "bat")
			melee(a1, a4 or "bat", a2, a3)
			return true
		elseif cmd == "shoot" then
			shoot(a1, a2, a3)
			return true
		elseif cmd == "spawn" then
			return Dummies.spawn(a1, { owner = a2 })
		elseif cmd == "power" then -- one move's wound on a body, without the fighter: (model, kit, move, damage, player?, from?)
			local hum = a1:FindFirstChildOfClass("Humanoid")
			return hum and Powers.hit(hum, a4 or 40, a4 or 40, false, a5, a6, a2, a3)
		elseif cmd == "powers" then -- the last a1 fighter hits: which move each was read as (Sandbox.Powers)
			if a1 == "seen" then
				local out = {}
				for k, n in pairs(Powers.seen) do
					table.insert(out, k .. " x" .. n)
				end
				table.sort(out)
				return table.concat(out, "\n")
			elseif a1 == "unknown" then
				local out = {}
				for k, n in pairs(Powers.unknown) do
					table.insert(out, n .. "x " .. k)
				end
				return table.concat(out, "\n")
			end
			return Powers.dump(a1)
		end
	end
	dbg.Parent = script
end

local ctx = { Hazards = Hazards, Injury = Injury, Dummies = Dummies, Ragdoll = RagdollService, credit = credit, net = function(...)
	Net:FireAllClients(...)
end, release = function(p) -- a machine taking a carried body out of the player's hand (the rocket)
	release(p)
end }
Hazards.init(ctx)
-- (2026-11-13) the open test ground's toys: machines, animals, the mutation lab
for _, n in ipairs({ "Machines", "Beasts", "Mutations", "Speech", "Wanderers" }) do
	local mod = script.Parent:FindFirstChild(n)
	if mod then
		local ok, err = pcall(function()
			require(mod).init(ctx)
		end)
		if not ok then
			warn("[Sandbox] " .. n .. " failed: " .. tostring(err))
		end
	end
end
print("[Sandbox] online - " .. #CollectionService:GetTagged("DummyStation") .. " dummy stations")
