-- NPC population tuning (read-only for builders; orchestrator owns this file)
return {
	Tag = "RagdollNPC",
	Count = 36, -- (2026-11-10) removed at the owner's request, then brought back at the owner's request
	MaxHealth = 250, -- (2026-11-09) 100 -> 250, same as players (PvPShared.Balance.PLAYER_MAX_HEALTH)
	WalkSpeedMin = 7,
	WalkSpeedMax = 11,
	RunSpeed = 20,          -- flee speed
	IdleTimeMin = 1,
	IdleTimeMax = 4,
	WanderStepMin = 12,
	WanderStepMax = 40,
	CorpseTime = 9,         -- seconds a dead body stays before fading
	FadeTime = 1.2,
	RespawnDelay = 3,
	-- a LIVING body knocked out of play is retired like a death (the kill goes to whoever hit it last) and replaced.
	-- Bodies held by a move (GrabbedBy / InDomain) are never judged; the clock starts when they are let go.
	LostMargin = 40,        -- studs beyond the arena's edge that count as out of play...
	LostTime = 12,          -- ...once it has stayed out there this long (room to stand up and walk back in)
	FarMargin = 150,        -- this far beyond the edge it has plainly been launched away...
	FarTime = 1.5,          -- ...and goes almost at once
	SkyHeight = 600,        -- a body hanging above this height...
	SkyTime = 8,            -- ...for this long is stuck up there
	-- city life (npc-life, 2026-11-07; GojoServer.CityNav): the waypoint graph replaces the open-field wander
	CityNav = true,         -- false = the original random wander (no graph)
	CityPoiChance = 0.4,    -- a new trip goes to a POI (browse / sit / stand / play / eat ...) this often...
	CityCrossChance = 0.45, -- ...across the scramble this often (only within CityCrossRadius of it), else somewhere 40-260 away
	CityCrossRadius = 520,  -- NPCs this close to the scramble may route across it (wider = bigger crowds on the zebras)
	StrandDist = 60,        -- a standing body with no graph node within this (and 14 vertically)...
	StrandTime = 30,        -- ...for this long (knocked onto a sealed roof) is retired like checkLost does
}
