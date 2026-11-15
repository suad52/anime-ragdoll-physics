--!nocheck
-- ShopService.Ext.Settings (2026-11-09, shop expansion): every player's SETTINGS, saved with their profile so they
-- follow them to any server / device. The menu is StarterPlayerScripts.SettingsMenu; it applies everything locally.
--   attribute Settings (JSON) = the whole table below (validated)
--   attribute KillSoundId / DeathSoundId (numbers, 0 = none) - only with the KillSound perk (PerkKillSounds reads them)
--   attribute UltOutfitId (number, 0 = none) - only with the UltOutfit perk (PerkUltOutfit reads it)
-- The FUN filters (weather / time / look / flip) only switch on with the FunFilters perk.
-- keys (2026-11-11, owner: "have the option to have keybinds"): the player's rebound keys as HudShared.Keybinds
-- serializes them, "Q=Z;LeftShift=V" (only the actions that were moved; "" = all defaults). SETTINGS > CONTROLS sends
-- it and the client's Keybinds module loads it back from the Settings attribute. Checked here only for shape (at most
-- 400 chars / 20 "Name=Name" pairs, every name a real Enum.KeyCode) - the client decides which actions and keys are
-- allowed, and a bad string is ignored rather than saved.
-- (2026-11-11, "wiki extras") more keys from the reference game's settings list: combo counter, camera follow, server
-- region label, hide my kills (published as the PUBLIC player attribute HideKills - ServerScriptService.KillsPrivacy
-- shows "-" on the player list), blood; UI / menu scale, sensitivity, toolbar offset ("range" kind: { min, max, step });
-- voice volume, text-to-speech, ragdoll sounds; destruction smoke, heavy effects; FUN invert / bloodbath / headcam and
-- the "jolly" weather. Most are applied by StarterPlayerScripts.SettingsEffects from the Settings attribute.
-- Request ("settings", { key = value, ... }) -> ok: changes any of the keys; anything invalid is ignored.
local M = { name = "Settings", request = {} }
local api

-- key -> { kind, default, extra }
local SCHEMA = {
	-- general
	damage = { "bool", true },   -- damage numbers
	shake = { "bool", true },    -- camera shake
	flash = { "bool", true },    -- screen flashes / impact frames
	npcChat = { "bool", true },  -- (2026-11-15) speech bubbles over the sandbox's NPCs
	-- audio (volume multipliers 0..2)
	sfx = { "vol", 1 },
	music = { "vol", 1 },
	taunts = { "vol", 1 },
	custom = { "bool", true },   -- hear other players' kill / death sounds
	killId = { "asset", 0 },     -- Custom Kill Sound perk
	deathId = { "asset", 0 },
	-- performance
	fps = { "bool", false },
	shadows = { "bool", true },
	debris = { "bool", true },   -- flying rubble, rocks and debris chunks
	-- fun (FunFilters perk)
	weather = { "enum", "", { "", "rain", "snow", "petals", "jolly" } },
	time = { "enum", "", { "", "night", "sunset", "dark" } },
	look = { "enum", "", { "", "bloom", "retro", "mono" } },
	flip = { "bool", false },
	-- Ultimate Outfit perk
	outfit = { "asset", 0 },
	-- controls (2026-11-11): rebound keys, HudShared.Keybinds.serialize()
	keys = { "keys", "" },
	-- (2026-11-11, wiki extras) general
	combo = { "bool", true },      -- the combo counter (ComboCounter)
	camFollow = { "bool", false }, -- camera focuses on the head
	region = { "bool", false },    -- server region + ping label
	hideKills = { "bool", false },  -- "-" instead of my kills on the player list (public attribute HideKills)
	blood = { "bool", true },       -- cartoon blood on KO'd bodies
	-- controls
	uiScale = { "range", 1, { 0.6, 1.4, 0.05 } },    -- HUD size
	menuScale = { "range", 1, { 0.7, 1.3, 0.05 } },  -- shop / settings / taunt / duel / quest panel size
	sens = { "range", 1, { 0.2, 3, 0.05 } },         -- camera sensitivity multiplier
	toolbar = { "range", 0, { -400, 400, 10 } },     -- move bar horizontal offset (px)
	-- audio
	voice = { "vol", 1 },            -- emote sounds
	tts = { "bool", false },         -- read nearby players' chat aloud
	ragdollSfx = { "bool", true },   -- thuds when ragdolled limbs hit things
	-- performance
	smoke = { "bool", true },        -- smoke puffs when buildings break
	heavyFx = { "bool", true },      -- off = far fewer particles from moves
	-- fun (FunFilters perk)
	invert = { "bool", false },
	bloodbath = { "bool", false },   -- blood stays much longer
	headcam = { "bool", false },     -- first person from your head, body visible
}

local function isKeyCodeName(n)
	local ok, k = pcall(function()
		return Enum.KeyCode[n]
	end)
	return ok and k ~= nil
end
local FUN = { weather = true, time = true, look = true, flip = true, invert = true, bloodbath = true, headcam = true }

local function valid(key, v)
	local s = SCHEMA[key]
	if not s then
		return nil
	end
	local kind = s[1]
	if kind == "bool" then
		if type(v) == "boolean" then
			return v
		end
		return nil
	elseif kind == "vol" then
		v = tonumber(v)
		return (v and v == v) and math.clamp(math.floor(v * 20 + 0.5) / 20, 0, 2) or nil
	elseif kind == "asset" then
		v = tonumber(v)
		if not v or v ~= v or v < 0 or v > 1e15 then
			return nil
		end
		return math.floor(v)
	elseif kind == "enum" then
		return (type(v) == "string" and table.find(s[3], v)) and v or nil
	elseif kind == "range" then
		v = tonumber(v)
		if not v or v ~= v then
			return nil
		end
		local lo, hi, step = s[3][1], s[3][2], s[3][3]
		v = math.clamp(v, lo, hi)
		return math.floor((v - lo) / step + 0.5) * step + lo
	elseif kind == "keys" then
		if type(v) ~= "string" or #v > 400 then
			return nil
		end
		if v == "" then
			return ""
		end
		local pairsList = string.split(v, ";")
		if #pairsList > 20 then
			return nil
		end
		for _, pair in ipairs(pairsList) do
			local a, b = string.match(pair, "^(%w+)=(%w+)$")
			if not a or not isKeyCodeName(a) or not isKeyCodeName(b) then
				return nil
			end
		end
		return v
	end
	return nil
end

function M.load(raw)
	local dat = {}
	for key, s in pairs(SCHEMA) do
		local v = nil
		if type(raw) == "table" then
			v = valid(key, raw[key])
		end
		if v == nil then
			v = s[2]
		end
		dat[key] = v
	end
	return dat
end

function M.publish(p, d, dat)
	local out = table.clone(dat)
	if not api.hasPerk(d, "FunFilters") then
		for k in pairs(FUN) do
			out[k] = SCHEMA[k][2]
		end
	end
	p:SetAttribute("Settings", api.HttpService:JSONEncode(out))
	local ks = api.hasPerk(d, "KillSound")
	p:SetAttribute("KillSoundId", ks and dat.killId or 0)
	p:SetAttribute("DeathSoundId", ks and dat.deathId or 0)
	p:SetAttribute("UltOutfitId", api.hasPerk(d, "UltOutfit") and dat.outfit or 0)
	p:SetAttribute("HideKills", dat.hideKills == true or nil) -- KillsPrivacy shows "-" on the player list
end

M.request.settings = function(p, d, changes)
	if type(changes) ~= "table" then
		return false, "?"
	end
	local dat = api.ext(d, M.name)
	local n = 0
	for key, v in pairs(changes) do
		if n >= 30 then
			break
		end
		local ok = valid(key, v)
		if ok ~= nil then
			dat[key] = ok
			n += 1
		end
	end
	if n > 0 then
		d.dirty = true
		api.publish(p)
	end
	return true, n > 0 and "SAVED" or "NOTHING CHANGED"
end

M.SCHEMA = SCHEMA

function M.init(a)
	api = a
end

return M
