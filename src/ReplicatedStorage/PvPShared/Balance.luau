-- ReplicatedStorage.PvPShared.Balance (2026-11-08): game-wide balance knobs read by every kit, on the server AND the
-- client (so the cooldown bars count what the server enforces).
return {
	-- "double the cooldown on non ult abilities": every kit's cooldown helper multiplies each move's cooldown by this,
	-- except its ultimate (and the moves that only exist inside the ultimate) and plain M1 swings - including the giant
	-- forms' M1s (the Attack Titan's punch, the Colossal's stomp). 1 = the old cooldowns.
	NON_ULT_COOLDOWN_MUL = 2,

	-- "take away regen, if you kill a player get 50 health back": a player's health never regenerates on its own
	-- (StarterCharacterScripts.Health is an empty stand-in); a player-on-player kill heals the killer by this much
	-- (ServerScriptService.LeaderboardService, on ServerStorage.PvPKill).
	KILL_HEAL = 100, -- 2026-11-11: 50 -> 100 ("gain 100 health per kill")

	-- (2026-11-09) every player spawns with this much health (ServerScriptService.PlayerHealth). NPCs: GojoShared.Config.NPC.MaxHealth.
	PLAYER_MAX_HEALTH = 250,

	-- MELEE PASS (2026-11-09, "pivot towards more melee combat"), all read by ServerScriptService.PvP:
	-- an M1 hit on a PLAYER does this much of its listed damage (every other hit on a player does PvP.DAMAGE_MUL, 0.5).
	-- Covers the shared punch string, Ichigo's sword, Luffy's string and Goku's combo - not the giant forms' M1s.
	M1_PLAYER_DAMAGE_MUL = 1,
	-- the M1 finisher's normal blast on a PLAYER: its launch speed x this, so they land within reach instead of across
	-- the street (the hold-Space launcher and the in-air slam keep their full throw; NPCs still fly)...
	M1_FINISHER_KNOCK_MUL = 0.4,
	-- ...and they stay down at most this long (it was up to 2.2 s + the get-up, all of it immune to M1)
	M1_FINISHER_RAGDOLL = 1.0,
	-- an M1 that lands on a player who is winding up Hollow Purple, Fuga, World Cut or the Kamehameha cancels the cast;
	-- the move then comes back after this many seconds instead of its full cooldown
	CAST_BREAK_COOLDOWN = 3,

	-- (2026-11-10) per-kit damage, on top of everything above ("buff Killua's damage a bit", "reduce Gojo's damage a bit").
	-- Read by the kit servers where their hits land (Gojo: CombatService; Killua: GodspeedServer; the shared punch string
	-- uses the PUNCHER's kit). A buff (> 1) scales the hit BEFORE the PvP caps (so an ult still can't one-shot); a nerf (< 1)
	-- scales what is left AFTER them (so even a capped hit like Hollow Purple gets lighter). A kit not listed = 1.
	KIT_DAMAGE_MUL = { Godspeed = 1.3, Limitless = 0.85, Carver = 0.88 }, -- 2026-11-11: Killua 1.15 -> 1.3 ("a medium bit"), Sukuna 0.88 ("a little bit")

	-- (2026-11-11, "tone down the knockback for abilities, increase the knockback for the basic M1 combo") PvP.knockMul():
	-- a player knocked from inside an M1 string (PvP.m1Begin .. m1End, same thread) gets M1_KNOCK_MUL, anything else
	-- ABILITY_KNOCK_MUL. Was one PvP.KNOCK_MUL = 0.6 for both. NPC knockback is untouched.
	ABILITY_KNOCK_MUL = 0.45,
	M1_KNOCK_MUL = 1.0,

	-- (2026-11-11, "character swap cooldown") seconds after switching fighters before you can switch again (VulpineServer
	-- KitServer.setKit enforces it; player attribute KitSwapReadyAt = the server time it ends, for the menus)
	-- (2026-11-13) 0 = OFF. The owner: "remove the switching cooldown" (it was 20). With weapons and powers now separate
	-- modes (Normal <-> an anime fighter), switching is how you change loadout, so it cannot be rationed.
	KIT_SWAP_COOLDOWN = 0,

	-- (2026-11-11, "increase movement speed, and make movement speed relative to health") read by
	-- StarterPlayerScripts.PerkMovement: every player's walk speed x MOVE_SPEED_MUL, then x a health factor that runs from
	-- 1 at full health down to HEALTH_SPEED_MIN at (nearly) none
	-- (2026-11-11, "add Luffy's aimbot to the other characters") M1 LOCK-ON for every non-stretch M1 (the shared punch,
	-- Ichigo's sword, Goku's combo): when a swing starts, the first living body (player or NPC) in a corridor along the aim
	-- (M1_LOCK_REACH studs from the chest, M1_LOCK_RADIUS wide, line of sight) becomes the swing's target - the swing
	-- turns to it, the attacker's own client steps in up to M1_LUNGE_MAX studs (stopping M1_LUNGE_STOP short), and the
	-- server lands it on that target. Luffy's own stretch M1 already homes this way (GomuServer.Moves.M1).
	M1_LOCK_REACH = 12,
	M1_LOCK_RADIUS = 3.5,
	M1_LUNGE_MAX = 5,
	M1_LUNGE_STOP = 3,

	MOVE_SPEED_MUL = 1.875, -- 2026-11-11: 1.25 -> 1.875 ("increase movement speed by like 1.5x": base 16 -> 30)
	HEALTH_SPEED_MIN = 0.7,

	-- COMBAT REWORK (2026-11-11, "make the combat like" a reference fighting game's controls & mechanics page; mechanics
	-- only). Read by ServerScriptService.PvP (the block itself, in PvP.dmg), ServerScriptService.GuardService (the BLOCK /
	-- BREAKOUT remote), DashService and the clients (StarterPlayerScripts.GuardClient, Dash).
	-- BLOCK: hold the BLOCK action (HudShared.Keybinds, Z by default). Only hits from the FRONT are blocked: the attacker
	-- (or the blast centre) must be within BLOCK_ARC degrees of where the blocker faces. A blocked M1 does no damage and
	-- no stun / knockback; a blocked ability does BLOCK_ABILITY_TAKEN of its damage and no stun / tumble.
	BLOCK_ARC = 80,
	BLOCK_ABILITY_TAKEN = 0.4,
	BLOCK_MOVE_MUL = 0.35, -- walk input x this while blocking (the client scales it)
	BLOCK_MIN_HOLD = 0.15, -- a released block stays up at least this long after it started (no frame-perfect taps)
	-- GUARD: every blocker has GUARD_MAX guard. A blocked hit drains its (NPC-scale) damage x GUARD_M1_MUL (M1) or
	-- x GUARD_ABILITY_MUL (abilities). Empty guard = GUARD BREAK: the block drops, the blocker is stunned
	-- GUARD_BREAK_STUN s and can't block again until GuardBrokenUntil. An M1 FINISHER that lands on a block breaks it at
	-- once (and does no damage itself). Guard refills GUARD_REGEN per second once GUARD_REGEN_DELAY s pass without a
	-- blocked hit. Character attributes: Blocking, Guard, GuardBrokenUntil (server time).
	GUARD_MAX = 100,
	GUARD_M1_MUL = 1.6,
	GUARD_ABILITY_MUL = 1.0,
	GUARD_BREAK_STUN = 1.5,
	GUARD_BREAK_LOCK = 2.5, -- no blocking for this long after a break (counts from the break)
	GUARD_REGEN = 25,
	GUARD_REGEN_DELAY = 1.2,
	-- BREAKOUT: press DASH while stunned, tumbling or guard-broken (not while held by a grab / domain): you get up at
	-- once, everything within BREAKOUT_RADIUS is shoved away (no damage), and hits miss you for BREAKOUT_IFRAMES s.
	-- Once every BREAKOUT_COOLDOWN s (player attribute BreakoutReadyAt = the server time it is back).
	BREAKOUT_COOLDOWN = 12,
	BREAKOUT_RADIUS = 12,
	BREAKOUT_PUSH = 70,
	BREAKOUT_IFRAMES = 0.5,
	-- DASH STRIKE: a FRONT dash that ends with an enemy right in front (DASH_STRIKE_REACH studs) bumps them: a short
	-- stun and a light hit that is not part of the M1 string (blockable like any hit). DashService checks it.
	DASH_STRIKE_REACH = 6,
	DASH_STRIKE_STUN = 0.6,
	DASH_STRIKE_DAMAGE = 4,
}
