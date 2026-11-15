--!nocheck
-- ZangetsuKit.Config child "BankaiGrab" (2026-11-08, "give him a recast as a grab attack which he can use to string
-- into a combo"). G AGAIN while Tensa Zangetsu runs = TENSA GRAB: he flash-steps to the nearest body in front of him
-- (the one under the cursor first), seizes it by the collar, crushes it in a black-red reiatsu grip, then drops it ON
-- ITS FEET, stunned, right in front of him inside M1 reach - so the sword combo follows. Owners: Moves.BankaiGrab
-- (server), Client.BankaiGrab (visuals), Clips.BankaiGrab (his pose); ZangetsuClient sends "BankaiGrab" for G in the
-- mode and shows it on the Bankai button. Times are seconds after the cast (server time).
return {
	Labels = { BankaiGrab = "TENSA GRAB" },
	Callouts = {
		BankaiGrab = {
			kanji = "天鎖掴", glyph = "掴", sub = "GRAB > COMBO", hint = "G again",
			c0 = Color3.fromRGB(255, 236, 236), c1 = Color3.fromRGB(200, 16, 36),
		},
	},
	BankaiGrab = {
		Cooldown = 6,          -- from the cast. Part of the ultimate: NOT doubled by Balance.NON_ULT_COOLDOWN_MUL
		WhiffCooldown = 1.5,   -- nothing in reach: a clutch at the air, ready again sooner
		Range = 30,            -- studs to the body's torso, line of sight from his chest
		HalfAngle = 75,        -- degrees off his aim a body may stand (the body under the cursor is taken at any angle)
		CursorRadius = 7,      -- a body within this many studs (flat) of the cursor point is the pick
		MaxDY = 12,
		-- the hold follows his LEFT hand (FK-measured on the R15 rig against Clips.BankaiGrab, root-relative):
		--   CLUTCH (0.16) hand at (-1.0, +1.0, 1.3 ahead) = a standing victim's collar when it stands HoldDist ahead
		--   LIFT   (0.30) hand at (-0.9, +1.9, 1.1 ahead) = the collar of a victim LiftDist ahead and Lift up
		HoldDist = 1.8,        -- he arrives this far short of the victim...
		Side = 1.0,            -- ...and this far to its side, so it stands in front of his left hand
		LiftDist = 1.65,       -- lifted: the victim's root this far in front of his
		Lift = 0.7,            -- ...and this much higher than it stands (its feet dangle)
		DashAt = 0.10,         -- he vanishes and reappears in front of the victim
		GrabAt = 0.16,         -- the hand closes: the victim is held where it stands
		LiftAt = 0.30,         -- ...and raised into the lift by here
		Crush = { 0.36, 0.52, 0.68 }, CrushDamage = 4, -- crushing pulses in the grip
		SlamAt = 0.74,         -- the slam starts: the victim is driven down and forward onto its feet...
		ReleaseAt = 0.84,      -- ...and let go here, standing
		ReleaseDamage = 10,
		DropDist = 4.2,        -- where it stands after the release, in front of him (the M1 box reaches 2 - 10 studs)
		Stagger = 1.3,         -- stunned this long after the release, STANDING (each M1 swing then re-stuns it)
		Lock = 0.92,           -- he is busy until here: the M1 is free right after the shove
		WhiffLock = 0.45,
		Gate = 200,            -- other clients draw a cast within this camera distance
	},
}
