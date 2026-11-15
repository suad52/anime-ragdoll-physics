--!nocheck
-- GomuKit.Config.M1 (owner m1): extra knobs for the Gum-Gum string (deep-merged over Config.M1 by the footer).
-- Server numbers stay in the base Config.M1; these are the CLIENT's feel knobs (Client.M1) + one server knob.
local C = Color3.fromRGB
return {
	M1 = {
		FinalBreakSpeed = 140,                     -- server: the finisher's BreakBlast speed at the fist end
		-- client
		Delay = { 0.02, 0.02, 0.025, 0.035, 0.07 }, -- the arm (leg) leaves the shoulder this long after t0: the wind-up
		StopShort = 3.4,                           -- the root-motion step stops this far (flat) short of the homed body
		WallPad = 1.6,                             -- ... and this far short of a wall
		ModeStepMul = 1.35,                        -- Gear Fifth: bigger, bouncier steps
		HomeInset = 0.9,                           -- the fist stops this far in front of the homed torso
		FinalRoot = 0.34,                          -- the local caster is rooted to hitAt + this on the finisher
		AxeHang = 0.05,                            -- the Axe: he hangs in the air to hitAt + this, then drops
		AxeDrop = 55,                              -- ... with this much downward speed
		GateRich = 120,                            -- other casters: dust / rubble / afterimages only this close
		ArmScale = { 1, 1, 1.05, 1.1, 1.2 },       -- rubber thickness per swing
		ModeArmScale = 1.7,                        -- Gear Fifth: thick cartoon rubber
		Shake = { 0.18, 0.18, 0.22, 0.3, 0.9 },    -- the local caster's shake when the swing connects
	},
	Palette = {
		M1Star = C(255, 240, 170),   -- comic impact stars
		M1Ring = C(255, 250, 235),   -- air-pressure rings off the fist
		M1Pistol = C(255, 214, 120), -- the Pistol's flare
	},
}
