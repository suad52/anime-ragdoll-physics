--!nocheck
-- ZangetsuKit.Config.Shunpo (owner: shunpo): E - SHUNPO numbers, deep-merged over the base Config (DESIGN §7.1).
-- Only the Shunpo and Mode.Shunpo keys. FLAIR pass timing (old -> new): DepartAt 0.20 -> 0.26 (a longer crouch-draw:
-- the coil trembles and the reiatsu gathers into the blade), ArriveAt 0.34 -> 0.46 (a longer flash-step, so the chain
-- of afterimages reads), CutAt 0.95 -> 1.12 (the silent beat 0.61 -> 0.66 s), Lock 1.45 -> 1.70 and RootEnd 1.5 ->
-- 1.66 (the clip's chiburi + look-back tail runs to 1.58 and plays the legs, + the 0.05 s client hit-stop). The
-- overhead twirl (ShunpoFlourish, right arm + SwordGrip only) plays HandoffAt 1.52 -> 2.02 while he can walk again.
-- Damage, range, radius and cooldown are the base values.
return {
	Shunpo = {
		DepartAt = 0.26,      -- he vanishes (base 0.20)
		ArriveAt = 0.46,      -- he reappears behind them (base 0.34)
		CutAt = 1.12,         -- everything he passed is cut (base 0.95) = Clips.Shunpo.strikeAt (the chiburi snap)
		Lock = 1.70,          -- busy (server): covers the whole main clip (1.58) + the client hit-stop (0.05)
		RootEnd = 1.66,       -- client: the caster is rooted until this many seconds after t0
		HandoffAt = 1.52,     -- client: the arm-only flourish clip takes over from the main clip here
		-- target point: payload.target within TargetRange studs of him, else the flat camera aim and the full Range
		TargetRange = 150,
		-- the path (server): ground-following segments, each swept with a body-sized box against colliding geometry
		PathStep = 2,         -- studs per ground sample
		MaxRise = 2.6,        -- a ledge taller than this between two samples stops the dash before it
		MaxDrop = 14,         -- a drop deeper than this (or no ground at all) stops the dash at the edge
		StepClear = 1.1,      -- the swept box's bottom sits this far above the feet (curbs/steps under it are walked onto)
		BodyWidth = 2.0, BodyTop = 5.3, BodyDepth = 1.0, -- swept box: width, top above the feet, depth along the dash
		HoldPad = 0.2,        -- living marked bodies: StunnedUntil = t0 + CutAt + HoldPad
		Escape = 12,          -- a marked body further than this from where he passed it at the cut has escaped
		BlastRadius = 3,      -- WorldBlast per cut body
		-- client visuals
		ClientHitStop = 0.05, -- every client holds the caster's pose this long at the cut (only when something was cut)
		GhostEvery = 5, MaxGhosts = 8, GhostAlpha = 0.3, GhostLife = 0.8, -- the path afterimages (slash poses)
		GhostYaw = 32,        -- each path afterimage turns this many degrees off the dash, alternating sides
		GlintEvery = 8,       -- one frost glint per this many studs of path, hanging through the silent beat
		FullBodies = 3,       -- bodies that get the full cut burst (nearest the camera first); the rest get a lean one
		WispBodies = 4,       -- bodies that shed rising wisps in the aftermath (2 in Tensa Zangetsu)
		NearDist = 160, MidDist = 250, -- remote casters: full / reduced / core-only tiers (camera distance)
		Budget = 400,         -- parts (cast folder incl. its afterimages): optional layers skip past this
		HushSat = -0.55,      -- the caster's silent beat: screen saturation (+ a cold edge vignette)
		Shot = true,          -- the caster's silent-beat money shot (false: keep the follow camera)
	},
	Mode = {
		Shunpo = {
			-- base Mode.Shunpo already has Range 60, MaxTargets 10, Damage 42, SecondCut 0.12, SecondDamage 10
			GhostEvery = 4, MaxGhosts = 10, -- Tensa Zangetsu: a denser chain (client only)
		},
	},
}
