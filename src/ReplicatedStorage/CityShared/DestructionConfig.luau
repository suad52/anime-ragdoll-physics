-- ReplicatedStorage.CityShared.DestructionConfig (owner: destruction)
-- Numbers for the NEON SHIBUYA destruction + regen service (ServerScriptService.CityDestruction) and its client FX
-- (StarterPlayerScripts.CityShatterClient -> CityShared.ShatterFX). Per-piece attributes always win:
-- HP, Regen, BreakGroup, Debris ("shatter" | "fling" | "none"), Fling (multiplier), NoRegen.
-- GROUND + FALL_GUARD (2026-11-07.3) are read by CityShared.GroundGuard: the walkable ground never opens, and any body
-- that still ends up under the map is put back on the street (ServerScriptService.FallGuard + StarterPlayerScripts.FallGuardClient).
return {
	VERSION = "2026-11-07.3",

	-- GROUND: every ability terrain carve - CityDestruction.Structure craters, VulpineServer.GroundFX craters (used by
	-- Vulpine, Deku, Ichigo, Luffy, the Titans, Tempest, Carver, Ascendant) and Gojo's CombatService carve (Hollow
	-- Purple's trench, Red's crater) - goes through GroundGuard.clampBall: the air ball is lifted so it never reaches
	-- below SURFACE_Y - MAX_DEPTH. Impacts still crack, scorch and dish the street and throw rubble, but there is always
	-- solid ground under them (the terrain is solid from SURFACE_Y down to y -60; before this a big carve dug 10-46
	-- stud pits). Lower MAX_DEPTH for flatter craters; 0 = abilities never lower the ground at all.
	GROUND = {
		SURFACE_Y = 2, -- the city's street level (terrain top; same as STRUCTURE.GROUND_Y)
		MAX_DEPTH = 4, -- deepest any ability may dig below SURFACE_Y (one 4-stud terrain voxel: a shallow dish)
	},

	-- FALL_GUARD: a living player / dummy whose torso is below SAFE_Y, or BURIED studs under the terrain surface straight
	-- above it for BURIED_TIME, is moved back onto open street near where it went under (spiral search out to
	-- SEARCH_MAX if that spot is inside a building, then its last grounded spot, then the nearest SpawnLocation),
	-- velocities zeroed, ragdoll state left alone. A player's own client does it at once (it owns the body); the server
	-- steps in after SERVER_GRACE if the client did not. A character with attribute NoFallGuard = true is skipped.
	FALL_GUARD = {
		ENABLED = true,
		SAFE_Y = -34, -- (2026-11-13, ragdoll sandbox) was -10, the fighting game's "nothing walkable is below the street": here that yanked every LIVING body (and a swimming player) out of the 22-deep shark lake, the spike pit (-18) and the grinder (-17) the moment it sank past -10. -34 is under every pit and above the bottom of the ground (-42)
		BURIED = 3.5,
		BURIED_TIME = 0.2,
		HZ = 15, -- buried (raycast) test rate; the SAFE_Y test runs every Heartbeat
		SEARCH_STEP = 8,
		SEARCH_MAX = 96,
		SERVER_GRACE = 0.8,
		NPC = true, -- also rescue living NPC dummies (NPCService still retires anything below -150 as a last resort)
	},

	-- destruction tags (= CityGen.Kit.TAG) -> category
	TAGS = { CityGlass = "GLASS", CityPanel = "PANEL", CityProp = "PROP", CityMark = "MARK" },

	-- default HP (= Kit.HP). dmg = (DMG_BASE + DMG_PER_RADIUS * radius) * (1 - (d / (radius + pieceRadius)) ^ FALLOFF_POW)
	-- Ichigo M1 (radius 4.5) = 21 at the centre: glass in one hit, panels in two, props in three (the contract's
	-- breakpoints). The contract's 1.2 / linear falloff left a radius-40 blast breaking props only within 7 studs of
	-- its centre, so the per-radius term and the falloff exponent are raised (orchestrator: numbers are ours).
	-- radius 16: panels within ~0.55 of its reach; radius 40: props within ~0.68, panels ~0.82, glass ~0.96.
	HP = { GLASS = 8, PANEL = 30, PROP = 50, MARK = 1 },
	DMG_BASE = 12,
	DMG_PER_RADIUS = 2.0,
	FALLOFF_POW = 2,
	MAX_RADIUS = 220, -- impacts are clamped to this radius (a Founding Titan stomp stays bounded)
	HEAL_AFTER = 25, -- a damaged but unbroken piece is back to full HP this long after its last hit

	-- markings (road paint, zebras, manholes) only go when the blast is big enough to crater the ground under them
	MARK_MIN_RADIUS = 5.5,
	MARK_MAX_HEIGHT = 0.8, -- ...and the blast centre is no higher above the mark than radius * this

	-- default regen delay in seconds (orchestrator: 45-60 s; marks come back sooner because terrain craters heal in ~9 s)
	REGEN = { GLASS = 45, PANEL = 50, PROP = 60, MARK = 20 },
	REGEN_CLEAR = 6, -- no player / NPC root within pieceRadius + this
	REGEN_RETRY = 2, -- seconds between retries while someone is too close
	REGEN_FADE = 0.5, -- fade-in time; collisions come back at the end
	REGEN_CHECK = 0.5, -- how often the broken list is scanned

	-- what a broken piece leaves behind by default
	DEBRIS_MODE = { GLASS = "shatter", PANEL = "fling", PROP = "fling", MARK = "none" },

	-- spatial index + work budget
	CELL = 32, -- grid bucket size (3D buckets)
	MERGE_TIME = 0.1, -- a WorldBlast and a BreakBlast this close in time ...
	MERGE_DIST = 2, -- ... and space are one impact (the BreakBlast's direction wins)
	MAX_QUEUE = 300, -- impacts waiting; the oldest are dropped beyond this
	MAX_IMPACTS_PER_STEP = 32,
	MAX_BREAKS_PER_STEP = 40, -- glass / panel / prop breaks per Heartbeat
	BREAK_BUDGET_MS = 4, -- ...and no more once this much time went into breaking this step (at least 4 always go)
	MAX_MARKS_PER_STEP = 160, -- markings are just hidden, so they get their own larger budget

	-- debris clones (PANEL / PROP)
	DEBRIS_CAP = 240, -- BaseParts alive in workspace.CityDebris, oldest removed first
	DEBRIS_LIFE_MIN = 6,
	DEBRIS_LIFE_MAX = 10,
	DEBRIS_FADE = 1.0,
	DEBRIS_GROUP = "Debris", -- does not collide with Players / NPCs (GojoShared.Config.Collision)
	DEBRIS_KILL_Y = -120,
	FLING = { GLASS = 0.8, PANEL = 1.0, PROP = 1.35, MARK = 0 }, -- category speed multipliers
	FLING_MIN = 14,
	FLING_MAX = 160,
	FLING_UP = 0.35, -- upward bias added to the throw direction
	DIR_WEIGHT = 0.65, -- BreakBlast direction vs radial push

	-- STRUCTURE (ServerScriptService.CityDestruction.Structure): abilities damage the buildings and the ground too.
	-- Walls, facades, pillars and building masses get jagged HOLES punched in them (the part is split around the
	-- blast, rim rubble + flying chunks); floors / roofs / decks / stairs never break (nobody falls through a level).
	-- Street-level blasts leave a scorched CRATER in the terrain + asphalt chunks. Both heal on their own.
	-- Crater depth is capped by GROUND.MAX_DEPTH (the bowl is lifted, CRATER_MAX is its width).
	STRUCTURE = {
		ENABLED = true,
		MIN_RADIUS = 6, -- blasts smaller than this (M1 swings at 4.5) never punch holes or craters
		HOLE_SCALE = 0.55, -- hole half-size = radius * this ...
		HOLE_MIN = 2.2,
		HOLE_MAX = 22,
		PARTS_PER_IMPACT = 10, -- closest structural parts a single blast cuts (+1 per 4 studs of blast radius)
		CUTS_PER_STEP = 12, -- part cuts per Heartbeat (the rest wait; each makes ~16 instances)
		FLOOR_THICK = 4.8, -- a part this thin whose thin side faces up is a floor / roof / deck / step: unbreakable
		-- (was 4: the Highway DeckSlab / ShoulderSlab are 4.6 thick, so blasts punched holes through the walkable deck)
		MAX_PIECES = 3500, -- live hole pieces before the oldest damage is rebuilt early
		REGEN = 60, -- seconds after a building part's LAST hit before it is rebuilt (when nobody is in the way)
		CHUNKS = 5, -- flying debris chunks per cut (capped by MAX_CHUNKS alive)
		MAX_CHUNKS = 160,
		CRASH_SPACING = 6, -- giant-form crash impacts closer than this within 0.25 s are folded together
		-- terrain
		CRATER_SCALE = 0.42, -- crater radius = blast radius * this, clamped:
		CRATER_MIN = 2.5,
		CRATER_MAX = 16,
		CRATERS_PER_STEP = 2,
		MAX_CRATERS = 120,
		CRATER_HEAL = 50, -- seconds before the street is repaved (when nobody stands in it)
		SCORCH = "Rock", -- the broken ring round a crater (light against the night asphalt; Basalt read as nothing)
		HOT_RADIUS = 18, -- blasts at least this big leave a glowing molten core in the crater
		HOT = "CrackedLava",
		GROUND_Y = 2, -- the city's street level (terrain top)
	},

	-- CRASH (ServerScriptService.CityDestruction.Crash): utility / movement breaks things too. Any player or dummy
	-- moving faster than it can run (dash, blink-dash, flight, grapple, being flung or pulled) smashes the breakables
	-- along its path; giant forms (titan, Susanoo, Kurama - a character taller than BIG_HEIGHT) smash them just by
	-- walking. Impacts are kind "crash": they never erase road markings and never merge with kit blasts.
	CRASH = {
		ENABLED = true,
		HZ = 20, -- sweeps per second (positions are read every Heartbeat for teleport detection)
		SPEED = 42, -- studs/s a normal-size body needs ...
		WALK_MULT = 1.35, -- ... and more than its Humanoid.WalkSpeed * this + WALK_PAD (fast run modes stay harmless)
		WALK_PAD = 8,
		VERTICAL_WEIGHT = 0.35, -- vertical speed counts this much (a jump landing is ~53 studs/s and must not break glass)
		BODY_R = 3, -- impact radius around a normal-size body
		MULT_PER = 55, -- damage multiplier = speed / this, clamped to [1, MULT_MAX] (radius 3: 18 dmg at the centre x mult)
		MULT_MAX = 5, -- ~110 studs/s breaks panels, ~280 breaks props (cars, vending machines) in one pass
		BIG_HEIGHT = 13, -- a body this tall is a giant form
		BIG_SPEED = 4, -- ... and breaks things whenever it moves faster than this
		BIG_MULT = 1.5, -- + speed / 60
		BIG_R_MAX = 40,
		TELEPORT_FRAME = 36, -- a jump this far in ONE Heartbeat is a teleport (lift pads, Transmission, kit switch): no sweep
		-- a CLIENT-side teleport (PivotTo on the owner's client) reaches the server INTERPOLATED - a glide at 400-1300
		-- studs/s that would plough a line through every building on the way. Faster than this = a teleport: no sweep,
		-- and nothing for TELEPORT_HOLD s (the glide's eased tail). Real flings top out at 320, dashes well below.
		MAX_SPEED = 480,
		TELEPORT_HOLD = 0.35,
		MAX_STEPS = 8, -- sweep points per body per tick
		MAX_PER_TICK = 48, -- impacts per tick for everyone together
		NPC = true, -- dummies being flung / dragged break things too
	},

	-- replication (one CityShatter:FireAllClients per Heartbeat at most)
	BATCH_MAX = 80,

	-- client FX (CityShatterClient)
	CLIENT = {
		MAX_SHARDS = 60,
		MAX_DIST = 400,
		SHARD_LIFE_MIN = 1.8,
		SHARD_LIFE_MAX = 3.2,
		SHARD_FADE = 0.6,
		SHARDS_MIN = 4,
		SHARDS_MAX = 12,
		GRAVITY = 110,
		MAX_DUST = 14,
		DUST_LIFE = 3.5,
	},
}
