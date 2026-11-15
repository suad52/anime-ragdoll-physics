-- Domain Expansion: Unlimited Void (G)
return {
	Cooldown = 120, -- (2026-11-10, "make the ults have longer cooldowns, something like 2 mins"; was 25)
	Start = 0.7,           -- s after cast start when the dome begins to expand (after the hand sign)
	ExpandTime = 0.55,     -- dome grows from nothing to Radius over this (Clips.Domain's arms open at Start + this)
	LockTime = 2.9,        -- caster rooted while the cinematic plays
	Duration = 10,         -- s the domain stands once fully expanded
	Radius = 80,           -- (2026-11-08) only bodies inside this are caught
	HoverMin = 7,          -- frozen bodies float this high above the ground...
	HoverMax = 16,         -- ...up to this
	Reach = 0,             -- UNUSED since 2026-11-08 (was 2000: a capture wave that swept the whole map after the dome
	                       -- formed, so bodies far outside it floated too). CombatService now stops at Radius.
	WaveTime = 1.5,        -- UNUSED (went with Reach)
	OverloadDPS = 0,       -- chip damage while frozen (0 keeps the void clean: no health bars popping up)
	TwitchEvery = 0.35,    -- s between overload twitches
	CollapsePower = 200,   -- fling speed when the domain shatters
	CollapseUp = 0.55,
	CollapseDamage = 100,
	Sounds = {
		Swell = "rbxassetid://9043337370",
		Sting = "rbxassetid://1842430129",
		Hit = "rbxassetid://1842433104",
		Void = "rbxassetid://9119392328",
		Drone = "rbxassetid://9114353273",
		Shatter = "rbxassetid://9114592102",
	},
}
