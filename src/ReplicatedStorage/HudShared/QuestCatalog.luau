--!nocheck
-- HudShared.QuestCatalog (2026-11-11, "wiki extras"): DAILY and WEEKLY quests that pay Yen.
-- Every player gets PER_DAY daily quests (new set at 00:00 UTC) and PER_WEEK weekly ones (new set Monday 00:00 UTC),
-- picked from the pools below with a seed of their UserId + the day / week number (so a rejoin keeps the same set).
-- Progress comes from game events (ShopService.Ext.Quests): kind =
--   ko_players  a player KO you land (ServerStorage.PvPKill)      ko_npcs   a dummy KO you land (LastHitBy)
--   damage      damage you deal (DamageFeed)                       minutes   minutes in the game
--   gadgets     gadgets used (Ext.Gadgets)                         taunts    taunts played (TauntService)
--   emotes      emotes played (PerkEmotes)                         duels     duels finished      duel_wins duels won
-- Rewards are fixed Yen (no perk multipliers). Wiki ratio kept: a daily ~ 5 dummy KOs, a weekly ~ 27.
local Q = {}

Q.PER_DAY, Q.PER_WEEK = 3, 3

-- (2026-11-15) the ragdoll sandbox has no PvP (PvP.NO_PVP) and no duels (DuelService disabled), so the player-KO and
-- duel quests could never be finished. They are REPLACED IN PLACE, not removed: a player's saved quests are positions in
-- these lists ("i"), so every entry keeps its position and a quest already in progress keeps its meaning.
Q.DAILY = {
	{ kind = "ko_npcs", target = 25, reward = 75, name = "KO %d DUMMIES" }, -- was KO 2 PLAYERS
	{ kind = "ko_npcs", target = 12, reward = 75, name = "KO %d DUMMIES" },
	{ kind = "damage", target = 1500, reward = 75, name = "DEAL %s DAMAGE" },
	{ kind = "minutes", target = 15, reward = 75, name = "PLAY FOR %d MINUTES" },
	{ kind = "gadgets", target = 3, reward = 75, name = "USE %d GADGETS" },
	{ kind = "damage", target = 4000, reward = 75, name = "DEAL %s DAMAGE" }, -- was TAUNT 5 TIMES (the taunt button is hidden)
	{ kind = "emotes", target = 5, reward = 75, name = "PLAY %d EMOTES" },
	{ kind = "minutes", target = 30, reward = 75, name = "PLAY FOR %d MINUTES" }, -- was FIGHT 1 DUEL
}
Q.WEEKLY = {
	{ kind = "ko_npcs", target = 250, reward = 400, name = "KO %d DUMMIES" }, -- was KO 15 PLAYERS
	{ kind = "ko_npcs", target = 100, reward = 400, name = "KO %d DUMMIES" },
	{ kind = "damage", target = 20000, reward = 400, name = "DEAL %s DAMAGE" },
	{ kind = "minutes", target = 120, reward = 400, name = "PLAY FOR %d MINUTES" },
	{ kind = "damage", target = 50000, reward = 400, name = "DEAL %s DAMAGE" }, -- was WIN 5 DUELS
	{ kind = "gadgets", target = 20, reward = 400, name = "USE %d GADGETS" },
	{ kind = "emotes", target = 30, reward = 400, name = "PLAY %d EMOTES" },
}
local DAY, WEEK = 86400, 604800
function Q.dayIndex(t)
	return math.floor(t / DAY)
end
function Q.weekIndex(t) -- weeks start Monday 00:00 UTC (the Unix epoch was a Thursday)
	return math.floor((t + 3 * DAY) / WEEK)
end
function Q.dayEnds(day)
	return (day + 1) * DAY
end
function Q.weekEnds(week)
	return (week + 1) * WEEK - 3 * DAY
end

local function comma(n)
	local s = tostring(math.floor(n))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return s
end
Q.comma = comma

-- "KO 2 PLAYERS" / "DEAL 1,500 DAMAGE" / "FIGHT 1 DUEL"
function Q.label(def)
	if def.name:find("%%s") then
		return string.format(def.name, comma(def.target))
	end
	return string.format(def.name, def.target)
end

return Q
