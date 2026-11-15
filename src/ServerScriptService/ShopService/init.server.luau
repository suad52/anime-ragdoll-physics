-- ServerScriptService.ShopService (orchestrator 2026-11-07): the anime SHOP's server. Cosmetics only.
-- Wallet + ownership live on the player as attributes the client reads live: Yen (number), ShopOwned (JSON array),
-- ShopAura / ShopTitle (equipped item ids, "" = none). Saved to a DataStore when one is available (pcall: Studio
-- without API access just plays in memory). Remote: HudShared.ShopRequest (RemoteFunction) ("buy" | "equip", id).
--
-- Fighters (2026-11-07): the roster is locked per player. KitsOwned (JSON array, attribute) = the free starter picks +
-- the ones bought with Yen (both saved) + the ones whose game pass the player owns (asked of Roblox on join and on
-- purchase, never saved). StarterPicked (bool; nil while loading) opens the first-join pick screen (StarterSelect).
-- Requests: ("pickStarters", {ids}) once, ("buyKit", id) for Yen. VulpineServer.KitServer refuses a switch to a
-- fighter that is not in KitsOwned. A load that fails never saves, so a DataStore outage can't wipe a player.
-- Premium fighters (Catalog.KITS.PREMIUM) are Robux-only: never a starter pick, never sold for Yen.
--
-- Robux PERKS (2026-11-07, economy): every item in HudShared.PerkCatalog is a developer product handled by the same
-- ProcessReceipt. Perks are saved forever in the profile (perks, a set that only grows - the merge unions it like kits)
-- with the inventory's choices (equip). Consumables add Yen or fire ServerStorage.PerkHooks (MeteorShower / UltReset)
-- AFTER their receipt is saved. Everything other systems need is a player attribute written ONLY here (publishPerks):
-- Perks, Perk_<Id>, CooldownMul, UltChargeMul, SpeedMul, JumpMul, EquipTrail, EquipKO, EquipSkins, Skin, VIPAura.
-- Inventory request: ("perkEquip", {slot, value}). Studio: ShopService.PerkGrantTest:Invoke(player, itemId).
-- Bundles (2026-11-07): a perk with `contents` (the Starter Pack) also grants those perks + Yen - grantBundle.
-- Random rolls (2026-11-07): emotes, KO effects and fighter skins are owned ONE BY ONE and bought as equal-odds rolls
-- among the ones not owned yet (Robux product or Yen) - see the RANDOM ROLLS block. Request: ("roll", cat, n?) for Yen.
-- EXTENSIONS (2026-11-09, shop expansion): every ModuleScript in the child folder "Ext" is a shop feature with its own
-- saved data (profile.ext[name], loaded lazily through api.ext(d, name)), attributes (mod.publish), receipt kinds
-- (mod.grant[kind] -> undo) and ShopRequest actions (mod.request[action]). GIFTS: when the Gifting extension holds a
-- pending gift for the buyer (EXT.giftFor), a receipt grants its item to the RECIPIENT instead (the receipt stays the
-- buyer's). See the EXTENSIONS block at the bottom.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local shared = ReplicatedStorage:WaitForChild("HudShared")
local Catalog = require(shared:WaitForChild("ShopCatalog"))
local Kits = require(shared:WaitForChild("Kits"))
local Perks = require(shared:WaitForChild("PerkCatalog"))

local byId = {}
for _, it in ipairs(Catalog.items) do
	byId[it.id] = it
end

local KCFG = Catalog.KITS or {}
local PICKS = KCFG.STARTER_PICKS or 5
local KIT_YEN = KCFG.PRICE_YEN or 2000
-- (2026-11-10) Catalog.KITS.ALL_FREE does the same in live servers: everyone owns every fighter, nothing is saved
local STUDIO_ALL = KCFG.ALL_FREE == true or (RunService:IsStudio() and KCFG.STUDIO_ALL_KITS == true)
local PREMIUM = KCFG.PREMIUM or {}
local FREE = KCFG.FREE or {} -- (2026-11-08) fighters everyone owns for now (Catalog.KITS.FREE); never saved to a profile
-- (2026-11-09) fighters still in development (Catalog.KITS.EARLY): owned ONLY with the Early Access perk - never a
-- starter pick, never sold on their own
local EARLY = KCFG.EARLY or {}
local rosterSet = {}
for _, k in ipairs(Kits.list) do
	rosterSet[k.id] = true
end
local passToKit = {}
for kitId, passId in pairs(KCFG.PASSES or {}) do
	if type(passId) == "number" and passId > 0 and rosterSet[kitId] then
		passToKit[passId] = kitId
	end
end

-- developer products (2026-11-07): one Robux product per fighter (Catalog.KITS.PRODUCTS, kit id -> product id). A
-- product is consumable on Roblox's side, so the OWNERSHIP is ours to keep: ProcessReceipt adds the fighter to the
-- saved profile and only answers PurchaseGranted once that save went through. Every granted PurchaseId is kept in
-- the profile (receipts), so a retried receipt is never granted twice.
local productToKit = {}
for kitId, productId in pairs(KCFG.PRODUCTS or {}) do
	if type(productId) == "number" and productId > 0 and rosterSet[kitId] then
		productToKit[productId] = kitId
	end
end
local RECEIPTS_KEPT = 200

-- the premium price the game shows (Catalog.KITS.PREMIUM) must be what Roblox charges: say so loudly when the
-- fighter's developer product is set to anything else (fix it on the Creator Dashboard)
task.spawn(function()
	for kitId, price in pairs(PREMIUM) do
		local pid = (KCFG.PRODUCTS or {})[kitId]
		if type(pid) == "number" and pid > 0 then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pid, Enum.InfoType.Product)
			if ok and type(info) == "table" and info.PriceInRobux and info.PriceInRobux ~= price then
				warn(string.format("[ShopService] %s shows R$%d in the game (Catalog.KITS.PREMIUM) but its developer product %d (%s) "
					.. "charges R$%d - set the product to R$%d on the Creator Dashboard", kitId, price, pid, tostring(info.Name), info.PriceInRobux, price))
			end
		end
	end
end)

-- perks (PerkCatalog is the one source of truth: ids, prices, product ids, tuning) ----------------------------------
local TUNE = Perks.TUNING
local TRAIL_IDS, KO_IDS = {}, {}
for _, t in ipairs(Perks.TRAILS) do
	TRAIL_IDS[t.id] = true
end
for _, t in ipairs(Perks.KO) do
	KO_IDS[t.id] = true
end
-- what a perk switches on the first time it is owned ({equip field, value})
local FIRST_OWN = {
	SpeedX2 = { "speed", true },
	JumpX2 = { "jump", true },
	VIP = { "vipAura", true },
	Trails = { "trail", "Rainbow" },
	KOFX = { "ko", "Confetti" },
}
-- the inventory slot -> the perk that must be owned to use it
local SLOT_PERK = { Trail = "Trails", KO = "KOFX", Skin = "Skins", Speed = "SpeedX2", Jump = "JumpX2", VIPAura = "VIP" }
-- consumable -> the ServerStorage.PerkHooks event it fires once its receipt is saved
-- (2026-11-14, sandbox shop) + the server events: Nuke (ServerScriptService.PerkNuke), Moon Gravity and Dummy Rain
-- (ServerScriptService.PerkWorldEvents)
local HOOK_OF = { Meteor = "MeteorShower", UltNow = "UltReset", Nuke = "Nuke", MoonGravity = "MoonGravity", DummyRain = "DummyRain" }
-- GAME PASS perks (2026-11-07, PerkCatalog items with `pass`): Roblox keeps the ownership, so it is asked on join and on
-- purchase and held in d.passPerks (never saved). A pass perk counts as owned everywhere a perk does (hasPerk).
local passToPerk = {}
for _, it in ipairs(Perks.ITEMS) do
	if it.kind == "perk" and type(it.pass) == "number" and it.pass > 0 then
		passToPerk[it.pass] = it.id
	end
end

local function perkItem(id)
	local it = type(id) == "string" and Perks.byId[id]
	return (it and it.kind == "perk") and it or nil
end

-- a product id -> its PerkCatalog item (byProduct, or a scan in case an id changed without P.reindex())
local function perkByProduct(productId)
	local it = Perks.byProduct[productId]
	if it then
		return it
	end
	for _, x in ipairs(Perks.ITEMS) do
		if type(x.product) == "number" and x.product > 0 and x.product == productId then
			return x
		end
	end
	return nil
end

-- trail/ko nil = never chosen (reads as the default while owned); the toggles are ON unless switched off
local function newEquip()
	return { trail = nil, ko = nil, skins = {}, speed = true, jump = true, vipAura = true }
end

local remote = shared:FindFirstChild("ShopRequest")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "ShopRequest"
	remote.Parent = shared
end

local store
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("NeonShop_v1")
	end)
	store = ok and s or nil
end

-- [player] = { yen, owned = {id = true}, aura, title, kits = {ordered kit ids: picks, then Yen buys}, picked,
--   passKits = {id = true}, dirty, noSave }
local data = {}

-- the extensions (filled by the EXTENSIONS block at the bottom; empty until then, so every hook is a no-op)
local EXT = { list = {}, byName = {}, grant = {}, request = {}, giftFor = nil, giftDone = nil }
-- an extension's data in a profile, loaded on first use from what was saved
local function extData(d, name)
	if d.ext[name] == nil then
		local mod = EXT.byName[name]
		local raw = type(d.extSaved) == "table" and d.extSaved[name] or nil
		d.ext[name] = (mod and mod.load) and mod.load(raw) or raw or {}
	end
	return d.ext[name]
end

local function ownsKit(d, id)
	if not rosterSet[id] then
		return false
	end
	-- (2026-11-12) an early-access fighter needs the Early Access perk even while KITS.ALL_FREE gives every other
	-- fighter away ("make him only available to the early access gamepass"); only the Studio-only STUDIO_ALL_KITS
	-- switch still unlocks it for testing
	if EARLY[id] then
		return (RunService:IsStudio() and KCFG.STUDIO_ALL_KITS == true) or d.perks.EarlyAccess == true or d.passPerks.EarlyAccess == true
	end
	if STUDIO_ALL or FREE[id] or d.passKits[id] or d.perks.AllFighters then
		return true
	end
	return table.find(d.kits, id) ~= nil
end

-- RANDOM ROLLS (2026-11-07): emotes, KO effects and fighter skins are owned one by one (d.items[cat][id] = true, saved
-- as items = { emote = {...}, ko = {...}, skin = {...} }, a set that only grows - the merge unions it like perks). A
-- roll (its Robux developer product, or Perks.ROLL_YEN Yen through ("roll", cat)) picks with EQUAL odds among the
-- items the player does not own yet - never a duplicate; a Robux roll with nothing left refunds Yen. The retired packs
-- (Perks.LEGACY: Emotes / KOFX / Skins) still own their whole category. Attributes (this script is the only writer):
-- OwnedEmotes / OwnedKO / OwnedSkins (JSON id lists, packs included) and LastRoll (JSON {cat, id, ids, n}, the reveal:
-- ids = every item that buy gave, id = the first).
-- BULK (2026-11-08): ("roll", cat, n) with n in Perks.ROLL_SIZES (1 / 5 / 10) costs ROLL_YEN x n and needs at least n
-- items left; a bulk Robux product (item.count) grants up to count rolls and returns any it can't give (all owned
-- meanwhile) as Yen at the per-roll price. One save, one LastRoll for the whole buy.
-- Players whose region restricts paid random items (PolicyService ArePaidRandomItemsRestricted) cannot roll for Yen;
-- the client hides the Robux roll from them too.
local CATS = { "emote", "ko", "skin" }
local ATTR_OF = { emote = "OwnedEmotes", ko = "OwnedKO", skin = "OwnedSkins" }
local POOL, POOLSET = {}, {}
for _, cat in ipairs(CATS) do
	POOL[cat], POOLSET[cat] = {}, {}
	for _, o in ipairs(Perks.pool(cat, true)) do -- (2026-11-11) exclusive (code-only) items too: they can be owned
		if cat ~= "skin" or rosterSet[o.id] then
			table.insert(POOL[cat], o.id)
			POOLSET[cat][o.id] = true
		end
	end
end
local ROLL_YEN = Perks.ROLL_YEN or 500
local rng = Random.new()

local function newItems()
	return { emote = {}, ko = {}, skin = {} }
end

local function ownsItem(d, cat, id)
	if not (POOLSET[cat] and POOLSET[cat][id]) then
		return false
	end
	-- (2026-11-14, sandbox shop) the Kill Effects Pack owns every kill effect, now and future ones
	if cat == "ko" and Perks.KO_PACK and (d.perks[Perks.KO_PACK] == true or d.passPerks[Perks.KO_PACK] == true) then
		return true
	end
	local pack = Perks.LEGACY[cat]
	-- a retired pack owns its category minus the items it was never sold with (PerkCatalog.packIncludes)
	local packHas = pack ~= nil and d.perks[pack] == true and (not Perks.packIncludes or Perks.packIncludes(cat, id))
	return packHas or d.items[cat][id] == true
		or (d.testItems ~= nil and d.testItems[cat] ~= nil and d.testItems[cat][id] == true) -- Studio ShopDebug grants (never saved)
end

local function ownedList(d, cat)
	local out = {}
	for _, id in ipairs(POOL[cat]) do
		if ownsItem(d, cat, id) then
			table.insert(out, id)
		end
	end
	return out
end

local function notOwned(d, cat)
	local out = {}
	for _, id in ipairs(POOL[cat]) do
		if not ownsItem(d, cat, id) and not (Perks.isExclusive and Perks.isExclusive(cat, id)) then -- (2026-11-11) exclusives are never rolled
			table.insert(out, id)
		end
	end
	return out
end

local PolicyService = game:GetService("PolicyService")
local restrictedCache = setmetatable({}, { __mode = "k" })
-- true when this player's region does not allow paid random items (a failed lookup counts as restricted, uncached)
local function rollsRestricted(p)
	local c = restrictedCache[p]
	if c ~= nil then
		return c
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, p)
	if not ok or type(info) ~= "table" then
		return true
	end
	c = info.ArePaidRandomItemsRestricted == true
	restrictedCache[p] = c
	return c
end

local function hasPerk(d, id)
	return d.perks[id] == true or d.passPerks[id] == true
end

-- the perk attributes (contract section 1). Other systems only READ these; this is the one writer.
local function trailOf(d)
	if not d.perks.Trails then
		return ""
	end
	local t = d.equip.trail
	if t == nil then
		return "Rainbow"
	end
	return TRAIL_IDS[t] and t or ""
end

-- the equipped KO effect: "" = switched off; never chosen (nil) or not owned -> the first one owned ("" with none)
local function koOf(d)
	local k = d.equip.ko
	if k == "" then
		return ""
	end
	if type(k) == "string" and KO_IDS[k] and ownsItem(d, "ko", k) then
		return k
	end
	return ownedList(d, "ko")[1] or ""
end

-- "Alt" while the CURRENT fighter's alternate skin is switched on (recomputed on every Kit change)
local function skinOf(p, d)
	local kit = p:GetAttribute("Kit")
	return (type(kit) == "string" and d.equip.skins[kit] and ownsItem(d, "skin", kit)) and "Alt" or ""
end

local function publishPerks(p, d)
	local list = {}
	for _, it in ipairs(Perks.ITEMS) do
		if it.kind == "perk" then
			local has = hasPerk(d, it.id)
			if has then
				table.insert(list, it.id)
			end
			p:SetAttribute("Perk_" .. it.id, has or nil)
		end
	end
	local e = d.equip
	p:SetAttribute("Perks", HttpService:JSONEncode(list))
	-- (2026-11-10) NON-ULT cooldowns are doubled for everyone. Every kit computes base * CooldownMul (* UltChargeMul for
	-- the ultimate), so the ult's share is divided back out: ults keep their old cooldowns.
	local NONULT_SCALE = 2
	p:SetAttribute("CooldownMul", NONULT_SCALE * (d.perks.Cooldowns and TUNE.COOLDOWN_MUL or 1))
	p:SetAttribute("UltChargeMul", (d.perks.UltCharge and TUNE.ULT_CHARGE_MUL or 1) / NONULT_SCALE)
	p:SetAttribute("SpeedMul", (d.perks.SpeedX2 and e.speed ~= false) and TUNE.SPEED_MUL or 1)
	p:SetAttribute("JumpMul", (d.perks.JumpX2 and e.jump ~= false) and TUNE.JUMP_HEIGHT_MUL or 1)
	-- Dash Master (game pass): the Shift dash cooldown multiplier (StarterPlayerScripts.Dash + DashService read it)
	p:SetAttribute("DashCooldownMul", hasPerk(d, "DashPass") and (TUNE.DASH_COOLDOWN_MUL or 0.5) or 1)
	p:SetAttribute("EquipTrail", trailOf(d))
	p:SetAttribute("EquipKO", koOf(d))
	local skins = {}
	for _, k in ipairs(Kits.list) do
		if e.skins[k.id] then
			table.insert(skins, k.id)
		end
	end
	p:SetAttribute("EquipSkins", HttpService:JSONEncode(skins))
	for _, cat in ipairs(CATS) do
		p:SetAttribute(ATTR_OF[cat], HttpService:JSONEncode(ownedList(d, cat)))
	end
	p:SetAttribute("Skin", skinOf(p, d))
	p:SetAttribute("VIPAura", d.perks.VIP == true and e.vipAura ~= false)
	for _, mod in ipairs(EXT.list) do
		if mod.publish then
			local ok, err = pcall(mod.publish, p, d, extData(d, mod.name))
			if not ok then
				warn("[ShopService] " .. mod.name .. ".publish: " .. tostring(err))
			end
		end
	end
end

local function publish(p)
	local d = data[p]
	if not d then
		return
	end
	local list = {}
	for id in pairs(d.owned) do
		table.insert(list, id)
	end
	local kitList = table.clone(d.kits)
	for _, k in ipairs(Kits.list) do
		if not table.find(kitList, k.id) and ownsKit(d, k.id) then
			table.insert(kitList, k.id)
		end
	end
	p:SetAttribute("Yen", d.yen)
	p:SetAttribute("ShopOwned", HttpService:JSONEncode(list))
	p:SetAttribute("ShopAura", d.aura or "")
	p:SetAttribute("ShopTitle", d.title or "")
	p:SetAttribute("KitsOwned", HttpService:JSONEncode(kitList))
	-- offline (the profile failed to load in a live server): no pick screen, no buying - the client says REJOIN
	p:SetAttribute("StarterPicked", d.picked or STUDIO_ALL or d.offline)
	p:SetAttribute("ShopOffline", d.offline == true)
	publishPerks(p, d)
end

-- the equipped fighter must be one the player owns (a new player's default, a pass refunded since last time)
local function ensureKit(p)
	local d = data[p]
	if not d then
		return
	end
	-- (2026-11-13) Catalog.KITS.DEFAULT: what everyone joins as - the no-powers NORMAL choice, weapons only. Only a
	-- fighter everyone owns anyway (FREE) can be it. This runs again after purchases and refunds, but `cur` is owned
	-- by then, so it never pulls a player off the fighter they switched to.
	local start = KCFG.DEFAULT
	if not (type(start) == "string" and rosterSet[start] and FREE[start]) then
		start = nil
	end
	if not (d.picked or STUDIO_ALL) then
		-- no ANIME fighter until the starters are picked (otherwise the default Gojo would be free to anyone who skips
		-- the pick screen); every kit's moves ignore an unknown Kit, only the shared punch still works
		p:SetAttribute("Kit", start or "None")
		return
	end
	local cur = p:GetAttribute("Kit")
	if cur and ownsKit(d, cur) then
		return
	end
	local first = start or d.kits[1]
	if not first then
		for _, k in ipairs(Kits.list) do
			if ownsKit(d, k.id) then
				first = k.id
				break
			end
		end
	end
	if first then
		p:SetAttribute("Kit", first)
	end
end

-- cosmetics on the body ------------------------------------------------------------------------------------
local function clearCosmetics(char)
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "ShopAura" or d.Name == "ShopTitle" then
			d:Destroy()
		end
	end
end

local function applyCosmetics(p)
	local d, char = data[p], p.Character
	if not d or not char then
		return
	end
	clearCosmetics(char)
	local root = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	local aura = d.aura and byId[d.aura]
	if aura and root then
		local at = Instance.new("Attachment")
		at.Name = "ShopAura"
		at.Position = Vector3.new(0, -1.2, 0)
		local flame = Instance.new("ParticleEmitter")
		flame.Texture = "rbxasset://textures/particles/fire_main.dds"
		flame.Color = ColorSequence.new(aura.c0, aura.c1)
		flame.LightEmission = aura.id == "aura_shadow" and 0 or 1
		flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.4) })
		flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.4, 0.2), NumberSequenceKeypoint.new(1, 1) })
		flame.Lifetime = NumberRange.new(0.6, 1.1)
		flame.Rate = 40
		flame.Speed = NumberRange.new(3, 6)
		flame.SpreadAngle = Vector2.new(18, 18)
		flame.Acceleration = Vector3.new(0, 7, 0)
		flame.EmissionDirection = Enum.NormalId.Top
		flame.Shape = Enum.ParticleEmitterShape.Cylinder
		flame.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		flame.Parent = at
		local spark = Instance.new("ParticleEmitter")
		spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		spark.Color = ColorSequence.new(aura.c0)
		spark.LightEmission = 1
		spark.Size = NumberSequence.new(0.35, 0)
		spark.Lifetime = NumberRange.new(0.5, 0.9)
		spark.Rate = 10
		spark.Speed = NumberRange.new(4, 8)
		spark.SpreadAngle = Vector2.new(40, 40)
		spark.EmissionDirection = Enum.NormalId.Top
		spark.Parent = at
		local light = Instance.new("PointLight")
		light.Color = aura.c1
		light.Range = 11
		light.Brightness = aura.id == "aura_shadow" and 0.4 or 2
		light.Shadows = false
		light.Parent = at
		at.Parent = root
	end
	local title = d.title and byId[d.title]
	if title and head then
		local bb = Instance.new("BillboardGui")
		bb.Name = "ShopTitle"
		bb.Size = UDim2.fromOffset(220, 34)
		bb.StudsOffset = Vector3.new(0, 2.7, 0)
		bb.MaxDistance = 110
		bb.LightInfluence = 0
		bb.ResetOnSpawn = false
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.FontFace = Kits.FONT_PUNCH
		t.Text = string.upper(title.name)
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = bb
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(title.c0, title.c1)
		g.Rotation = 90
		g.Parent = t
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.fromRGB(12, 10, 20)
		st.Parent = t
		bb.Parent = head
	end
end

-- load / save ---------------------------------------------------------------------------------------------
local function load(p)
	local saved, failed, apiBlocked = nil, false, false
	if store then
		failed = true
		for attempt = 1, 3 do
			local ok, v = pcall(function()
				return store:GetAsync("u" .. p.UserId)
			end)
			if ok then
				saved, failed = v, false
				break
			end
			-- (Studio's real message is "... Error code: 7 Reason: Studio access to APIs is not allowed.")
			local msg = tostring(v)
			if msg:find("StudioAccessToApisNotAllowed", 1, true) or msg:lower():find("studio access to apis", 1, true) then
				apiBlocked = true
				break -- Studio without API access: play in memory
			end
			if attempt == 3 then
				break
			end
			task.wait(attempt)
		end
	else
		apiBlocked = true
	end
	-- noSave: the load failed, so this session's empty profile must never overwrite the real one
	-- studioMemory: a Studio test with no DataStore access, where a purchase may be granted in memory only
	-- offline: a real load failure (not Studio's blocked API) - the session is read-only and the shop is shut
	-- inflight: PurchaseIds whose grant is still being saved (a second delivery must wait, not be told "granted")
	local studioMemory = apiBlocked and RunService:IsStudio()
	local d = { yen = Catalog.START, owned = {}, aura = nil, title = nil, kits = {}, picked = false, passKits = {}, noSave = failed,
		receipts = {}, inflight = {}, studioMemory = studioMemory, offline = failed and not studioMemory,
		perks = {}, passPerks = {}, equip = newEquip(), items = newItems(), rolls = 0, ext = {}, extSaved = nil }
	if type(saved) == "table" then
		d.extSaved = type(saved.ext) == "table" and saved.ext or nil
		local si = type(saved.items) == "table" and saved.items or {}
		for _, cat in ipairs(CATS) do
			for _, id in ipairs(type(si[cat]) == "table" and si[cat] or {}) do
				if POOLSET[cat][id] then
					d.items[cat][id] = true
				end
			end
		end
		d.yen = tonumber(saved.yen) or d.yen
		for _, id in ipairs(saved.owned or {}) do
			if byId[id] then
				d.owned[id] = true
			end
		end
		d.aura = byId[saved.aura or ""] and d.owned[saved.aura] and saved.aura or nil
		d.title = byId[saved.title or ""] and d.owned[saved.title] and saved.title or nil
		for _, id in ipairs(type(saved.kits) == "table" and saved.kits or {}) do
			if rosterSet[id] and not table.find(d.kits, id) then
				table.insert(d.kits, id)
			end
		end
		for _, id in ipairs(type(saved.perks) == "table" and saved.perks or {}) do
			if perkItem(id) then
				d.perks[id] = true
			end
		end
		local e = type(saved.equip) == "table" and saved.equip or {}
		if type(e.trail) == "string" and (e.trail == "" or TRAIL_IDS[e.trail]) then
			d.equip.trail = e.trail
		end
		if type(e.ko) == "string" and (e.ko == "" or KO_IDS[e.ko]) then
			d.equip.ko = e.ko
		end
		for _, k in ipairs(type(e.skins) == "table" and e.skins or {}) do
			if type(k) == "string" and rosterSet[k] then
				d.equip.skins[k] = true
			end
		end
		for _, f in ipairs({ "speed", "jump", "vipAura" }) do
			if type(e[f]) == "boolean" then
				d.equip[f] = e[f]
			end
		end
		-- the All Fighters bundle counts as the starter pick (it unlocks the whole roster)
		d.picked = (saved.picked == true and #d.kits > 0) or d.perks.AllFighters == true
		for _, r in ipairs(type(saved.receipts) == "table" and saved.receipts or {}) do
			if type(r) == "table" and type(r[1]) == "string" then
				d.receipts[r[1]] = tonumber(r[2]) or 0
			end
		end
	end
	return d
end

-- the granted PurchaseIds, newest first, capped (a retry of anything older than this is long settled)
local function receiptList(d)
	local list = {}
	for id, t in pairs(d.receipts) do
		table.insert(list, { id, t })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	for i = #list, RECEIPTS_KEPT + 1, -1 do
		list[i] = nil
	end
	return list
end

local function profileOf(d)
	local list = {}
	for id in pairs(d.owned) do
		table.insert(list, id)
	end
	local perks = {}
	for id in pairs(d.perks) do
		table.insert(perks, id)
	end
	local e = d.equip
	local skins = {}
	for k in pairs(e.skins) do
		table.insert(skins, k)
	end
	local items = {}
	for _, cat in ipairs(CATS) do
		local l = {}
		for id in pairs(d.items[cat]) do
			table.insert(l, id)
		end
		items[cat] = l
	end
	-- extensions: what was saved (a module not loaded yet keeps its data) + every loaded module's current data
	local ext = {}
	if type(d.extSaved) == "table" then
		for k, v in pairs(d.extSaved) do
			ext[k] = v
		end
	end
	for name, v in pairs(d.ext) do
		local mod = EXT.byName[name]
		ext[name] = (mod and mod.save) and mod.save(v) or v
	end
	return { yen = d.yen, owned = list, aura = d.aura, title = d.title, kits = d.kits, picked = d.picked, receipts = receiptList(d),
		perks = perks, items = items, ext = ext,
		equip = { trail = e.trail, ko = e.ko, skins = skins, speed = e.speed, jump = e.jump, vipAura = e.vipAura } }
end

-- every write MERGES into what is stored: paid fighters, receipts and the starter pick only ever grow, so a stale
-- server (a ghost session, or a slow save racing a rejoin) can never delete a Robux unlock another server granted.
-- (Yen is last-write-wins; it is soft currency.) The callback may run more than once - the unions are idempotent.
local function writeProfile(p, d)
	local before = #d.kits
	local grew = false
	store:UpdateAsync("u" .. p.UserId, function(old)
		if type(old) == "table" then
			for _, id in ipairs(type(old.perks) == "table" and old.perks or {}) do
				if perkItem(id) and not d.perks[id] then
					d.perks[id] = true
					grew = true
				end
			end
			for _, id in ipairs(type(old.kits) == "table" and old.kits or {}) do
				if rosterSet[id] and not table.find(d.kits, id) then
					table.insert(d.kits, id)
				end
			end
			local oi = type(old.items) == "table" and old.items or {}
			for _, cat in ipairs(CATS) do
				for _, id in ipairs(type(oi[cat]) == "table" and oi[cat] or {}) do
					if POOLSET[cat][id] and not d.items[cat][id] then
						d.items[cat][id] = true -- a roll another server granted
						grew = true
					end
				end
			end
			for _, r in ipairs(type(old.receipts) == "table" and old.receipts or {}) do
				if type(r) == "table" and type(r[1]) == "string" and not d.receipts[r[1]] then
					d.receipts[r[1]] = tonumber(r[2]) or 0
				end
			end
			if old.picked == true and (#d.kits > 0 or d.perks.AllFighters) then
				d.picked = true
			end
			if d.perks.AllFighters then
				d.picked = true
			end
			-- extensions with grow-only data (bought emote pages, redeemed codes, gadgets) merge what another server wrote
			local oe = type(old.ext) == "table" and old.ext or {}
			for _, mod in ipairs(EXT.list) do
				if mod.merge and oe[mod.name] ~= nil and mod.merge(extData(d, mod.name), oe[mod.name]) then
					grew = true
				end
			end
		end
		return profileOf(d)
	end)
	if #d.kits > before and p.Parent then
		task.defer(publish, p) -- another server's unlock just reached this one
	end
	if grew and p.Parent then
		task.defer(function() -- another server's perk (All Fighters may also hand out a first fighter)
			if p.Parent and data[p] == d then
				publish(p)
				ensureKit(p)
			end
		end)
	end
end

local function save(p)
	local d = data[p]
	if not d or not store or not d.dirty or d.noSave then
		return
	end
	local ok = pcall(writeProfile, p, d)
	if ok then
		d.dirty = false
	end
end

-- a save that MUST land (a Robux purchase): retried, and reports whether it did
local function saveNow(p)
	local d = data[p]
	if not d then
		return false
	end
	if not store or d.noSave then
		return d.studioMemory == true -- a Studio test without DataStore access: the grant lives in memory
	end
	for attempt = 1, 3 do
		local ok = pcall(writeProfile, p, d)
		if ok then
			d.dirty = false
			return true
		end
		task.wait(attempt)
	end
	return false
end

-- Yen multiplier from perks: 2x Yen and VIP stack (2 * 1.25 = 2.5x); Yen packs and refunds are never multiplied
local function yenMul(d)
	return (d.perks.YenX2 and TUNE.YEN_MUL or 1) * (d.perks.VIP and TUNE.VIP_YEN_MUL or 1)
end

local function earn(p, amount)
	local d = data[p]
	if d and amount > 0 then
		amount = math.floor(amount * yenMul(d) + 0.5)
		d.yen += amount
		d.dirty = true
		p:SetAttribute("Yen", d.yen)
	end
end

local function onPlayer(p)
	-- no fighter until the profile says which ones are owned (kit scripts only default Kit when it is nil)
	p:SetAttribute("Kit", "None")
	local d = load(p)
	if not p.Parent then
		return -- left while loading
	end
	data[p] = d
	-- Skin follows the CURRENT fighter: recompute it on every Kit change. (2026-11-10 skins fix) Connected BEFORE
	-- publish/ensureKit and recomputed after them: it used to be connected after ensureKit, so the Kit that ensureKit
	-- picks on join ("None" -> the first owned fighter) never reached it and Skin stayed "" for the fighter you
	-- spawn as - an equipped skin did nothing after a rejoin until you switched fighters away and back.
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		local dd = data[p]
		if dd then
			p:SetAttribute("Skin", skinOf(p, dd))
		end
	end)
	publish(p)
	ensureKit(p)
	p:SetAttribute("Skin", skinOf(p, d))
	-- (2026-11-07) Studio without DataStore access: everything bought in this playtest is gone when it stops - say so
	if d.studioMemory then
		p:SetAttribute("ShopStudioMemory", true)
		warn("[ShopService] Studio has no DataStore access, so picks, Yen and purchases in this playtest are kept in memory "
			.. "and RESET when you press Stop. To keep them between playtests: Game Settings > Security > "
			.. "Enable Studio Access to API Services (live servers always save).")
	end
	-- game-pass perks (Dash Master): asked of Roblox on every join; never saved
	for passId, perkId in pairs(passToPerk) do
		task.spawn(function()
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, passId)
			if ok and has and data[p] == d and not d.passPerks[perkId] then
				d.passPerks[perkId] = true
				publish(p)
			end
		end)
	end
	-- game passes: a fighter bought with Robux (asked of Roblox on every join; never saved)
	for passId, kitId in pairs(passToKit) do
		task.spawn(function()
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, passId)
			if ok and has and data[p] == d and not d.passKits[kitId] then
				d.passKits[kitId] = true
				publish(p)
			end
		end)
	end
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 10)
		char:WaitForChild("Head", 10)
		task.wait(0.5) -- after the kit's own spawn setup
		if p.Parent then
			applyCosmetics(p)
		end
	end)
	if p.Character then
		task.defer(applyCosmetics, p)
	end
	-- yen per KO: NPCService credits LastHitBy's leaderstats.Kills
	task.spawn(function()
		local ls = p:WaitForChild("leaderstats", 30)
		local kills = ls and ls:WaitForChild("Kills", 30)
		if kills and not kills:IsA("IntValue") then -- (2026-11-11) HIDE MY KILLS: the real counter is in HiddenStats
			local hs = p:FindFirstChild("HiddenStats")
			kills = hs and hs:FindFirstChild("Kills")
		end
		if not kills then
			return
		end
		local last = kills.Value
		kills.Changed:Connect(function(v)
			if v > last then
				earn(p, (v - last) * Catalog.PER_KILL)
			end
			last = v
		end)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	save(p)
	data[p] = nil
end)
game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do
		save(p)
	end
end)

-- income while online + periodic saves
task.spawn(function()
	while true do
		task.wait(60)
		for _, p in ipairs(Players:GetPlayers()) do
			earn(p, Catalog.PER_MINUTE)
			save(p)
		end
	end
end)

-- a fighter bought with Robux: the developer product's receipt (the ONLY ProcessReceipt in the game - keep it so)
-- * not one of ours / player not here / profile still loading -> NotProcessedYet: Roblox retries later (next join)
-- * a PurchaseId already granted -> PurchaseGranted (a retry; nothing granted twice)
-- * a fighter already owned (unlocked with Yen meanwhile) -> refunded as PRICE_YEN, so the Robux is never wasted
-- * the grant is applied, saved, and only then confirmed; a failed save rolls it back and asks Roblox to retry
local function perkHook(name)
	local f = ServerStorage:FindFirstChild("PerkHooks")
	local h = f and f:FindFirstChild(name)
	return (h and h:IsA("BindableEvent")) and h or nil
end

-- a PERK or CONSUMABLE bought with Robux (PerkCatalog), under the fighters' rules: wait for the profile, one grant per
-- PurchaseId, the grant is saved BEFORE it is confirmed - and, for a consumable, before its hook fires. A failed save
-- rolls the grant back, fires nothing and answers NotProcessedYet so Roblox retries.
-- * a perk already owned -> refunded as price * YEN_PER_ROBUX Yen (the Robux is never wasted)
-- * a Yen pack -> + item.yen (never multiplied); Meteor / UltNow -> PerkHooks.MeteorShower / UltReset :Fire(player)
-- * a BUNDLE (a perk with `contents`, e.g. the Starter Pack) -> also every contents perk + contents.yen (see grantBundle)

-- a bundle's contents (2026-11-07, Starter Pack): each perk not owned yet is granted (with its first-own equip); one
-- already owned becomes its share of the bundle's price in Yen (price * perk.price / worth * YEN_PER_ROBUX) - never
-- its full price, or a cheap bundle would be a Yen voucher. contents.yen is added as is (never multiplied).
-- Returns the undo for a save that failed.
local function grantBundle(d, item)
	local c = item.contents
	local worth = math.max(Perks.worth(item), 1)
	local yen = math.floor(tonumber(c.yen) or 0)
	local undos = {}
	for _, id in ipairs(c.perks or {}) do
		local sub = perkItem(id)
		if sub and d.perks[id] then
			yen += math.floor(item.price * sub.price / worth * Perks.YEN_PER_ROBUX)
		elseif sub then
			d.perks[id] = true
			local first = FIRST_OWN[id]
			local prev = first and d.equip[first[1]]
			if first then
				d.equip[first[1]] = first[2]
			end
			table.insert(undos, function()
				d.perks[id] = nil
				if first then
					d.equip[first[1]] = prev
				end
			end)
		end
	end
	d.yen += yen
	return function()
		d.yen -= yen
		for _, u in ipairs(undos) do
			u()
		end
	end
end

-- one roll of `cat` (2026-11-07): an EQUAL pick among the items this player does not own yet, granted at once (a first
-- KO effect is equipped, a skin is switched on). Returns id, undo - or nil when they already own every item.
local function grantRoll(d, cat)
	local left = notOwned(d, cat)
	if #left == 0 then
		return nil
	end
	local id = left[rng:NextInteger(1, #left)]
	local hadKO = cat == "ko" and #ownedList(d, "ko") > 0
	local prevKO, prevSkin = d.equip.ko, d.equip.skins[id]
	d.items[cat][id] = true
	if cat == "ko" and not hadKO then
		d.equip.ko = id
	elseif cat == "skin" then
		d.equip.skins[id] = true
	end
	return id, function()
		d.items[cat][id] = nil
		if cat == "ko" then
			d.equip.ko = prevKO
		elseif cat == "skin" then
			d.equip.skins[id] = prevSkin
		end
	end
end

-- what a roll gave, for the shop's reveal (n changes every roll, so the same result twice still fires)
local function announceRoll(p, d, cat, ids, picks)
	if type(ids) ~= "table" then
		ids = { ids }
	end
	d.rolls += 1
	-- pick = how many "choose it yourself" picks this buy also gave (a 10-roll: Ext.RollPicks)
	p:SetAttribute("LastRoll", HttpService:JSONEncode({ cat = cat, id = ids[1], ids = ids, n = d.rolls, pick = picks or 0 }))
end

-- (2026-11-09) a 10-roll = 9 random + 1 pick of the player's choice (Ext.RollPicks; without it, 10 random)
local PICK_AT = 10
local function picksFor(n)
	return (n >= PICK_AT and EXT.byName.RollPicks) and 1 or 0
end

-- `n` rolls of `cat` in one go: (ids, undo) - fewer ids than n when the category runs out
local function grantRolls(d, cat, n)
	local ids, undos = {}, {}
	for _ = 1, n do
		local id, u = grantRoll(d, cat)
		if not id then
			break
		end
		table.insert(ids, id)
		table.insert(undos, u)
	end
	return ids, function()
		for i = #undos, 1, -1 do
			undos[i]()
		end
	end
end

local function processPerkReceipt(receipt, item)
	local p = Players:GetPlayerByUserId(receipt.PlayerId)
	local d = p and data[p]
	local t0 = os.clock()
	while p and p.Parent and not d and os.clock() - t0 < 20 do -- a receipt delivered at join, while the profile loads
		task.wait(0.25)
		d = data[p]
	end
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pid = tostring(receipt.PurchaseId)
	if d.inflight[pid] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- the first delivery is still saving; it decides
	end
	if d.receipts[pid] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local hook
	-- (2026-11-15) or the item's own `hook` (the EVENTS tab's events: ServerScriptService.PerkMapEvents)
	local hookName = item.kind == "consumable" and (HOOK_OF[item.id] or (type(item.hook) == "string" and item.hook)) or nil
	if hookName then
		hook = perkHook(hookName)
		if not hook then
			warn("[ShopService] PerkHooks." .. hookName .. " missing - receipt left for a retry")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	-- GIFT (2026-11-09): the buyer picked a recipient in the GIFTS tab before this prompt -> the item goes to the
	-- recipient (gp / gd) while the receipt stays the buyer's (d.receipts); both profiles are saved
	local gp, gd = p, d
	local gift = EXT.giftFor and EXT.giftFor(p, item) or nil
	if gift and gift.player and gift.player.Parent and data[gift.player] and gift.player ~= p then
		gp, gd = gift.player, data[gift.player]
	else
		gift = nil
	end
	local undo, rolled, rolledPicks
	if item.kind == "perk" then
		if gd.perks[item.id] then
			local refund = math.floor(item.price * Perks.YEN_PER_ROBUX)
			gd.yen += refund
			undo = function()
				gd.yen -= refund
			end
		else
			gd.perks[item.id] = true
			local first = FIRST_OWN[item.id]
			local prevVal = first and gd.equip[first[1]]
			if first then
				gd.equip[first[1]] = first[2]
			end
			local prevPicked = gd.picked
			if item.id == "AllFighters" then
				gd.picked = true
			end
			local undoBundle = type(item.contents) == "table" and grantBundle(gd, item) or nil
			undo = function()
				if undoBundle then
					undoBundle()
				end
				gd.perks[item.id] = nil
				if first then
					gd.equip[first[1]] = prevVal
				end
				if not prevPicked and #gd.kits == 0 then
					gd.picked = false
				end
			end
		end
	elseif item.kind == "roll" then
		-- up to item.count rolls (bulk products); any it can't give (everything owned - rolled on another server
		-- meanwhile) come back as Yen at the per-roll price
		local want = math.max(1, math.floor(tonumber(item.count) or 1))
		local picks = picksFor(want)
		local ids, undoRolls = grantRolls(gd, item.cat, want - picks)
		local undoPick = picks > 0 and EXT.byName.RollPicks.add(gd, item.cat, picks) or nil
		local short = want - picks - #ids
		local refund = short > 0 and math.floor(item.price / want * short * Perks.YEN_PER_ROBUX) or 0
		gd.yen += refund
		if #ids > 0 or picks > 0 then
			rolled = ids
			rolledPicks = picks
		end
		undo = function()
			undoRolls()
			if undoPick then
				undoPick()
			end
			gd.yen -= refund
		end
	elseif EXT.grant[item.kind] then
		-- an extension's own kind (an emote page, a gadget crate...): it returns the undo, or nil + reason to retry later
		local ok, u, why = pcall(EXT.grant[item.kind], gp, gd, item)
		if not ok or not u then
			warn("[ShopService] " .. tostring(item.id) .. " grant failed: " .. tostring(ok and why or u) .. " - receipt left for a retry")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		undo = u
	elseif type(item.yen) == "number" and item.yen > 0 then
		local amount = math.floor(item.yen)
		gd.yen += amount
		undo = function()
			gd.yen -= amount
		end
	elseif not hook then
		warn("[ShopService] consumable " .. tostring(item.id) .. " has no grant - receipt left for a retry")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	d.inflight[pid] = true
	d.receipts[pid] = os.time()
	d.dirty = true
	gd.dirty = true
	local saved = saveNow(p)
	d.inflight[pid] = nil
	if not saved then
		d.receipts[pid] = nil
		if undo then
			undo()
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if gift then
		task.spawn(saveNow, gp) -- the recipient's copy (their periodic save retries it if this one fails)
	end
	if gp.Parent then
		publish(gp)
		ensureKit(gp)
		if rolled then
			announceRoll(gp, gd, item.cat, rolled, rolledPicks)
		end
	end
	if gift and p.Parent then
		publish(p)
	end
	if gift and EXT.giftDone then
		pcall(EXT.giftDone, p, gp, item, rolled)
	end
	if hook then
		hook:Fire(gp) -- only now: the receipt is saved, so a retry can never fire it twice
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function processReceipt(receipt)
	local kitId = productToKit[receipt.ProductId]
	if not kitId then
		local item = perkByProduct(receipt.ProductId)
		if item then
			return processPerkReceipt(receipt, item)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Players:GetPlayerByUserId(receipt.PlayerId)
	local d = p and data[p]
	local t0 = os.clock()
	while p and p.Parent and not d and os.clock() - t0 < 20 do -- a receipt delivered at join, while the profile loads
		task.wait(0.25)
		d = data[p]
	end
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pid = tostring(receipt.PurchaseId)
	if d.inflight[pid] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- the first delivery is still saving; it decides
	end
	if d.receipts[pid] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	d.inflight[pid] = true
	local had = ownsKit(d, kitId)
	if had then
		d.yen += KIT_YEN
	else
		table.insert(d.kits, kitId)
	end
	d.receipts[pid] = os.time()
	d.dirty = true
	local saved = saveNow(p)
	d.inflight[pid] = nil
	if not saved then
		d.receipts[pid] = nil
		if had then
			d.yen -= KIT_YEN
		else
			local i = table.find(d.kits, kitId)
			if i then
				table.remove(d.kits, i)
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if p.Parent then
		publish(p)
		ensureKit(p)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end
MarketplaceService.ProcessReceipt = processReceipt

-- Studio only: ShopService.ReceiptTest:Invoke(receipt) runs a fake receipt through the real handler
if RunService:IsStudio() then
	local rt = Instance.new("BindableFunction")
	rt.Name = "ReceiptTest"
	rt.OnInvoke = function(receipt)
		return processReceipt(receipt)
	end
	rt.Parent = script

	-- ShopService.PerkGrantTest:Invoke(player | name | nil, itemId) runs the receipt path for any PerkCatalog item
	-- (fresh fake PurchaseId each call) -> "PurchaseGranted" / "NotProcessedYet"
	local gt = Instance.new("BindableFunction")
	gt.Name = "PerkGrantTest"
	gt.OnInvoke = function(p, itemId)
		if type(p) == "string" then
			p = Players:FindFirstChild(p)
		end
		p = p or Players:GetPlayers()[1]
		local item = type(itemId) == "string" and Perks.byId[itemId]
		if not p or not item then
			return "UNKNOWN PLAYER OR ITEM"
		end
		if item.pass ~= nil then -- a game-pass perk: no receipt, just Roblox's ownership (pretend it said yes)
			local d = data[p]
			if not d then
				return "NotProcessedYet"
			end
			d.passPerks[item.id] = true
			publish(p)
			return "PurchaseGranted"
		end
		local receipt = { PlayerId = p.UserId, PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
			ProductId = item.product, CurrencySpent = item.price }
		return processPerkReceipt(receipt, item).Name
	end
	gt.Parent = script
end

-- a fighter (or a game-pass perk like Dash Master) bought with Robux while playing
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, passId, purchased)
	local kitId = passToKit[passId]
	local perkId = passToPerk[passId]
	local d = data[p]
	if purchased and kitId and d and not d.passKits[kitId] then
		d.passKits[kitId] = true
		publish(p)
	end
	if purchased and perkId and d and not d.passPerks[perkId] then
		d.passPerks[perkId] = true
		publish(p)
	end
end)

-- Studio only: ShopService.ShopDebug:Invoke("yen", player, amount) tops a test wallet up
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "ShopDebug"
	dbg.OnInvoke = function(cmd, p, amount)
		local d = data[p]
		if cmd == "yen" and d and type(amount) == "number" then
			d.yen += amount
			publish(p)
			return d.yen
		end
		-- ("perkRevoke", player, perkId): take a perk away again to re-test its first-own path (in memory; a
		-- DataStore-backed Studio session merges it back from the store on the next save)
		if cmd == "perkRevoke" and d and type(amount) == "string" and d.perks[amount] then
			d.perks[amount] = nil
			publish(p)
			return true
		end
		-- ("passGrant" | "passRevoke", player, perkId): pretend Roblox says the player owns / doesn't own a game-pass perk
		if (cmd == "passGrant" or cmd == "passRevoke") and d and type(amount) == "string" and Perks.byId[amount] then
			d.passPerks[amount] = (cmd == "passGrant") or nil
			publish(p)
			return true
		end
		-- ("itemsClear", player): forget every rolled emote / KO effect / skin (in memory) to re-test the rolls
		if cmd == "itemsClear" and d then
			d.items = newItems()
			d.testItems = nil
			publish(p)
			return true
		end
		-- (2026-11-10 skins fix) ("skinGrant" | "skinRevoke", player, kitId | "all"): own + switch ON (or take away +
		-- switch off) that fighter skin for THIS session only. It lives in d.testItems, which is never saved, so a Studio
		-- test can't leak a skin into a real profile even with DataStore access on. Returns the player's Skin attribute.
		if (cmd == "skinGrant" or cmd == "skinRevoke") and d and type(amount) == "string" then
			local give = cmd == "skinGrant"
			d.testItems = d.testItems or newItems()
			for _, id in ipairs(amount == "all" and POOL.skin or { amount }) do
				if POOLSET.skin[id] then
					d.testItems.skin[id] = give or nil
					d.equip.skins[id] = give or nil
				end
			end
			publish(p)
			return p:GetAttribute("Skin")
		end
		-- ("rollPolicy", player, true | false | nil): pretend the region restricts paid random items (nil = ask Roblox)
		if cmd == "rollPolicy" and p then
			restrictedCache[p] = amount
			return true
		end
		return nil
	end
	dbg.Parent = script
end

-- fighters: the one-time starter pick, and unlocking with Yen
local function kitRequest(p, d, action, arg)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	if action == "pickStarters" then
		if d.picked then
			return false, "ALREADY PICKED"
		end
		-- fighters already unlocked (a pass, or a Robux product bought before picking) don't take a slot
		local open = 0
		for _, k in ipairs(Kits.list) do
			if not d.passKits[k.id] and not table.find(d.kits, k.id) and not PREMIUM[k.id] and not FREE[k.id] and not EARLY[k.id] then
				open += 1
			end
		end
		local need = math.min(PICKS, open)
		-- a pick the client still showed as free but which got unlocked meanwhile (a retried receipt) counts as picked
		local chosen, skipped = {}, {}
		for _, id in ipairs(type(arg) == "table" and arg or {}) do
			if type(id) == "string" and rosterSet[id] then
				local ownedAlready = d.passKits[id] or table.find(d.kits, id) or FREE[id]
				if EARLY[id] then
					return false, "EARLY ACCESS ONLY - PICK ANOTHER FIGHTER"
				elseif PREMIUM[id] and not ownedAlready then
					return false, "ROBUX ONLY - PICK ANOTHER FIGHTER"
				elseif ownedAlready and not table.find(skipped, id) then
					table.insert(skipped, id)
				elseif not ownedAlready and not table.find(chosen, id) then
					table.insert(chosen, id)
				end
			end
		end
		if #chosen > need or #chosen + #skipped < need then
			return false, "PICK " .. need
		end
		for _, id in ipairs(chosen) do
			if not table.find(d.kits, id) then
				table.insert(d.kits, id)
			end
		end
		d.picked = true
		d.dirty = true
		publish(p)
		if chosen[1] then
			p:SetAttribute("Kit", chosen[1]) -- start as the first one picked
		end
		task.spawn(save, p)
		return true, "LOCKED IN!"
	elseif action == "buyKit" then
		if type(arg) ~= "string" or not rosterSet[arg] then
			return false, "UNKNOWN FIGHTER"
		end
		if not (d.picked or STUDIO_ALL) then
			return false, "PICK YOUR STARTERS FIRST"
		end
		if ownsKit(d, arg) then
			return false, "ALREADY UNLOCKED"
		end
		if EARLY[arg] then
			return false, "EARLY ACCESS ONLY - GET THE EARLY ACCESS PASS"
		end
		if PREMIUM[arg] then
			return false, "ROBUX ONLY"
		end
		if d.yen < KIT_YEN then
			return false, "NOT ENOUGH " .. Catalog.CURRENCY
		end
		d.yen -= KIT_YEN
		table.insert(d.kits, arg)
		d.dirty = true
		publish(p)
		task.spawn(save, p) -- a purchase is written at once
		return true, "UNLOCKED!"
	end
	return false, "?"
end

-- the INVENTORY: ("perkEquip", {slot, value}) switches what an owned perk does or shows
-- Trail / KO: value = an id or "" (off); Skin: value = {kit = kitId, on = bool}; Speed / Jump / VIPAura: value = bool
local function perkEquip(p, d, arg)
	if type(arg) ~= "table" then
		return false, "?"
	end
	local slot, value = arg.slot, arg.value
	local need = type(slot) == "string" and SLOT_PERK[slot]
	if not need then
		return false, "UNKNOWN SLOT"
	end
	-- KO effects and skins are owned one by one (random rolls); every other slot needs its perk
	if slot == "KO" then
		if value ~= "" and not ownsItem(d, "ko", value) then
			return false, "NOT OWNED"
		end
	elseif slot == "Skin" then
		if type(value) == "table" and value.on == true and not ownsItem(d, "skin", value.kit) then
			return false, "NOT OWNED"
		end
	elseif not d.perks[need] then
		return false, "NOT OWNED"
	end
	local msg
	if slot == "Trail" or slot == "KO" then
		local ids = slot == "Trail" and TRAIL_IDS or KO_IDS
		if type(value) ~= "string" or (value ~= "" and not ids[value]) then
			return false, "UNKNOWN " .. string.upper(slot)
		end
		d.equip[slot == "Trail" and "trail" or "ko"] = value
		msg = value == "" and "UNEQUIPPED" or "EQUIPPED"
	elseif slot == "Skin" then
		local kit = type(value) == "table" and value.kit
		if type(kit) ~= "string" or not rosterSet[kit] or type(value.on) ~= "boolean" then
			return false, "UNKNOWN FIGHTER"
		end
		d.equip.skins[kit] = value.on or nil
		msg = value.on and "SKIN ON" or "SKIN OFF"
	else
		if type(value) ~= "boolean" then
			return false, "?"
		end
		d.equip[slot == "Speed" and "speed" or slot == "Jump" and "jump" or "vipAura"] = value
		msg = value and "ON" or "OFF"
	end
	d.dirty = true
	publishPerks(p, d)
	return true, msg
end

-- a roll paid with Yen (2026-11-07): ("roll", cat) -> ok, message, cat, id
local ROLL_SIZE_OK = {}
for _, n in ipairs(Perks.ROLL_SIZES or { 1 }) do
	ROLL_SIZE_OK[n] = true
end
local function rollRequest(p, d, cat, n)
	if d.offline then
		return false, "DATA DIDN'T LOAD - REJOIN"
	end
	if type(cat) ~= "string" or not POOL[cat] then
		return false, "?"
	end
	n = n == nil and 1 or tonumber(n)
	if not n or not ROLL_SIZE_OK[n] then
		return false, "?"
	end
	local left = #notOwned(d, cat)
	if left == 0 then
		return false, "YOU OWN THEM ALL"
	end
	if left < n then
		return false, "ONLY " .. left .. " LEFT"
	end
	local cost = ROLL_YEN * n
	if d.yen < cost then
		return false, "NOT ENOUGH " .. Catalog.CURRENCY
	end
	if rollsRestricted(p) then
		return false, "NOT AVAILABLE IN YOUR REGION"
	end
	if d.yen < cost or #notOwned(d, cat) < n then -- (the policy lookup yields: check again)
		return false, "TRY AGAIN"
	end
	d.yen -= cost
	local picks = picksFor(n)
	local ids = grantRolls(d, cat, n - picks)
	if picks > 0 then
		EXT.byName.RollPicks.add(d, cat, picks)
	end
	d.dirty = true
	publish(p)
	announceRoll(p, d, cat, ids, picks)
	task.spawn(save, p) -- a purchase is written at once
	return true, "YOU GOT IT!", cat, ids[1], ids
end

-- requests --------------------------------------------------------------------------------------------------
local lastReq = {}
remote.OnServerInvoke = function(p, action, id, n)
	local d = data[p]
	local extReq = type(action) == "string" and EXT.request[action]
	if extReq then -- an extension's action (codes, gifting, emote slots, settings, gadgets...)
		if not d then
			return false, "LOADING"
		end
		local t = os.clock()
		if t - (lastReq[p] or 0) < 0.15 then
			return false, "TOO FAST"
		end
		lastReq[p] = t
		local ok, a, b, c, e = pcall(extReq, p, d, id, n)
		if not ok then
			warn("[ShopService] " .. action .. ": " .. tostring(a))
			return false, "TRY AGAIN"
		end
		return a, b, c, e
	end
	if action == "roll" then
		if not d then
			return false, "LOADING"
		end
		local t = os.clock()
		if t - (lastReq[p] or 0) < 0.5 then
			return false, "TOO FAST"
		end
		lastReq[p] = t
		return rollRequest(p, d, id, n)
	end
	if action == "pickStarters" or action == "buyKit" then
		if not d then
			return false, "LOADING"
		end
		local t = os.clock()
		if t - (lastReq[p] or 0) < 0.25 then
			return false, "TOO FAST"
		end
		lastReq[p] = t
		return kitRequest(p, d, action, id)
	end
	if action == "perkEquip" then
		if not d then
			return false, "LOADING"
		end
		local t = os.clock()
		if t - (lastReq[p] or 0) < 0.15 then
			return false, "TOO FAST"
		end
		lastReq[p] = t
		return perkEquip(p, d, id)
	end
	local it = type(id) == "string" and byId[id]
	if not d or not it then
		return false, "UNKNOWN ITEM"
	end
	local t = os.clock()
	if t - (lastReq[p] or 0) < 0.25 then
		return false, "TOO FAST"
	end
	lastReq[p] = t
	local slot = it.kind == "aura" and "aura" or "title"
	if action == "buy" then
		if d.owned[id] then
			return false, "ALREADY OWNED"
		end
		if d.yen < it.price then
			return false, "NOT ENOUGH " .. Catalog.CURRENCY
		end
		d.yen -= it.price
		d.owned[id] = true
		d[slot] = id -- a fresh purchase goes straight on
		d.dirty = true
		publish(p)
		applyCosmetics(p)
		return true, "PURCHASED!"
	elseif action == "equip" then
		if not d.owned[id] then
			return false, "NOT OWNED"
		end
		d[slot] = (d[slot] ~= id) and id or nil -- equipping the worn one takes it off
		d.dirty = true
		publish(p)
		applyCosmetics(p)
		return true, d[slot] and "EQUIPPED" or "UNEQUIPPED"
	end
	return false, "?"
end

-- EXTENSIONS (2026-11-09) ---------------------------------------------------------------------------------------
-- Each ModuleScript in script.Ext returns a table:
--   name (default: the module's name)  - its key in the profile (profile.ext[name])
--   load(raw) -> data                  - sanitise what was saved (raw may be nil: a new player / first use)
--   save(data) -> saved                - optional: what to write (default: data as is)
--   merge(data, other) -> grew         - optional: fold in another server's copy (grow-only data); true = changed
--   publish(p, d, data)                - optional: write its player attributes (runs inside publish)
--   grant = { [kind] = fn(p, d, item) -> undo | nil, reason }   - receipt kinds (PerkCatalog item.kind)
--   request = { [action] = fn(p, d, arg, arg2) -> ok, msg, ... } - ShopRequest actions
--   giftFor(buyer, item) -> { player = recipient } | nil, giftDone(buyer, recipient, item, rolled) (Gifting only)
--   init(api)                          - called once with the api below
do
	local api = {
		data = data, Perks = Perks, Catalog = Catalog, Kits = Kits, HttpService = HttpService, remote = remote,
		isStudio = RunService:IsStudio(), POOL = POOL, POOLSET = POOLSET, ROLL_YEN = ROLL_YEN,
		ext = extData, hasPerk = hasPerk, perkItem = perkItem, ownsItem = ownsItem, ownedList = ownedList,
		notOwned = notOwned, ownsKit = ownsKit, grantRolls = grantRolls, announceRoll = announceRoll, publish = publish,
		save = save, saveNow = saveNow, ensureKit = ensureKit, earn = earn, rollsRestricted = rollsRestricted,
		applyCosmetics = applyCosmetics,
	}
	local folder = script:FindFirstChild("Ext")
	local mods = folder and folder:GetChildren() or {}
	table.sort(mods, function(a, b)
		return a.Name < b.Name
	end)
	for _, m in ipairs(mods) do
		if m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" then
				mod.name = mod.name or m.Name
				EXT.byName[mod.name] = mod
				table.insert(EXT.list, mod)
				for kind, fn in pairs(mod.grant or {}) do
					EXT.grant[kind] = fn
				end
				for action, fn in pairs(mod.request or {}) do
					EXT.request[action] = fn
				end
				if mod.giftFor then
					EXT.giftFor, EXT.giftDone = mod.giftFor, mod.giftDone
				end
			else
				warn("[ShopService] extension " .. m.Name .. " failed to load: " .. tostring(mod))
			end
		end
	end
	for _, mod in ipairs(EXT.list) do
		if mod.init then
			local ok, err = pcall(mod.init, api)
			if not ok then
				warn("[ShopService] extension " .. mod.name .. ".init: " .. tostring(err))
			end
		end
	end
	-- profiles that loaded before the extensions came up get their attributes now
	for p in pairs(data) do
		if p.Parent then
			publish(p)
		end
	end
end
