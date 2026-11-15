--!nocheck
-- HudShared.TauntCatalog (2026-11-09, shop expansion): every TAUNT - a sound plus a speech bubble over your head that
-- everyone nearby sees / hears. 6 are free; two packs of 6 are sold as perks (PerkCatalog TauntHype / TauntTrash).
-- Sounds come ONLY from Roblox's licensed libraries (Pro Sound Effects "(SFX)" and APM Music stings) - no voice clips
-- from shows or games. Lines are our own.
-- Played by StarterPlayerScripts.TauntMenu (T key / the speech-bubble pill) through ServerScriptService.TauntService.
local T = {}

T.COOLDOWN = 4      -- seconds between two taunts of one player (server enforced)
T.MAX_LEN = 4.5     -- a taunt sound is faded out after this long
T.BUBBLE_TIME = 2.8 -- seconds the speech bubble stays up

T.PACKS = {
	{ id = "free", name = "FREE" },
	{ id = "hype", name = "HYPE PACK", perk = "TauntHype" },
	{ id = "trash", name = "TRASH TALK PACK", perk = "TauntTrash" },
}

-- id, pack, name (button), line (bubble), sound (asset id; library + clip name in the comment)
T.LIST = {
	{ id = "GG", pack = "free", name = "GG", line = "GG!", sound = 9040476898 },                  -- APM "Early Bird - Hit1"
	{ id = "OverHere", pack = "free", name = "OVER HERE", line = "OVER HERE!", sound = 9120688888 },  -- PSE "Whistle Wolf 1"
	{ id = "Nice", pack = "free", name = "NICE", line = "NICE!", sound = 9114667991 },               -- PSE "Group Clapping Rhythmic 46"
	{ id = "HaHa", pack = "free", name = "HA HA", line = "HA HA HA!", sound = 9047214582 },          -- APM "Party In The Wild - Tag2"
	{ id = "TooEasy", pack = "free", name = "TOO EASY", line = "TOO EASY.", sound = 9042532779 },    -- APM "Upbeat Street - Tag2"
	{ id = "BringIt", pack = "free", name = "BRING IT", line = "BRING IT ON!", sound = 1841800152 }, -- APM "Hot Trot (sting b)"

	{ id = "AirHorn", pack = "hype", name = "AIR HORN", line = "BWAAAP!", sound = 9114075901 },      -- PSE "Diesel Truck Horn Air Horn 3"
	{ id = "Crowd", pack = "hype", name = "CROWD", line = "THE CROWD GOES WILD!", sound = 9114360647 }, -- PSE "Excited Crowd 5"
	{ id = "DrumRoll", pack = "hype", name = "DRUM ROLL", line = "DRUM ROLL...", sound = 9042819203 }, -- APM "Drumline (sting c)"
	{ id = "Fanfare", pack = "hype", name = "FANFARE", line = "CHAMPION!", sound = 9042409054 },     -- APM "Day Of The Election Sting 2"
	{ id = "Hype", pack = "hype", name = "HYPE", line = "HYPE HYPE HYPE!", sound = 9047100306 },     -- APM "Hustler Sting 2"
	{ id = "GoodTimes", pack = "hype", name = "GOOD TIMES", line = "GOOD TIMES!", sound = 9038578395 }, -- APM "Good Good Times (sting b)"

	{ id = "SlowClap", pack = "trash", name = "SLOW CLAP", line = "WOW. AMAZING.", sound = 9114762124 }, -- PSE "Hand Claps 2"
	{ id = "TooSlow", pack = "trash", name = "TOO SLOW", line = "TOO SLOW!", sound = 1837769261 },     -- APM "Time Attack (sting)"
	{ id = "Joke", pack = "trash", name = "WHAT A JOKE", line = "WHAT A JOKE.", sound = 9045129322 },  -- APM "It's All A Big Joke - Tag2"
	{ id = "SayAgain", pack = "trash", name = "SAY AGAIN", line = "SAY THAT AGAIN?", sound = 9042807094 }, -- APM "What Did You Just Say to Me?"
	{ id = "Weirdo", pack = "trash", name = "WEIRDO", line = "WEIRDO...", sound = 9113096848 },       -- PSE "Alien Whistles Wolf 2"
	{ id = "Dance", pack = "trash", name = "DANCE", line = "DANCE FOR ME!", sound = 1841439465 },     -- APM "Dance It Like Dali Sting b"
}

T.byId, T.packById = {}, {}
for _, p in ipairs(T.PACKS) do
	T.packById[p.id] = p
end
for i, t in ipairs(T.LIST) do
	t.order = i
	T.byId[t.id] = t
end

-- owned = free, or the pack's perk (the player attribute Perk_<id>, set only by ShopService)
function T.owns(player, t)
	local pack = t and T.packById[t.pack]
	if not pack then
		return false
	end
	return pack.perk == nil or player:GetAttribute("Perk_" .. pack.perk) == true
end

return T
