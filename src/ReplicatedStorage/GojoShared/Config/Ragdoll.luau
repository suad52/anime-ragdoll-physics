-- Ragdoll tuning (read-only for builders; orchestrator owns this file)
return {
	SettleSpeed = 3,        -- studs/s: below this (on every torso part) the body counts as settled
	MinRagdollTime = 1.2,   -- never get up sooner than this after the latest ragdoll/fling
	MaxRagdollTime = 6,     -- force a get-up attempt after this long if still alive
	MaxFlingSpeed = 320,    -- clamp for RagdollService.Fling linear speed
	MaxSpin = 40,           -- clamp for angular velocity magnitude (rad/s)
	DefaultSpin = 12,       -- random spin magnitude when Fling gets no angularVelocity
	GetUpLift = 0.3,        -- extra height when standing the HRP back up
	LimbFriction = 0.42,    -- CustomPhysicalProperties for ragdolled body parts
	LimbElasticity = 0.05,
	LimbDensity = 0.6,  -- below water's 1.0 so bodies float in the pool
	-- hit reactions (2026-11-06): the rig's BallSockets carry 16-67 friction torque on 0.6-density limbs, which made
	-- every ragdoll fly like a stiff plank. While ragdolled the joints run loose; Fling throws the torso ahead of the
	-- limbs and tips the body back over the push, so it folds into a C and whips instead of tumbling rigid.
	JointLooseness = 0.05, -- (2026-11-13) 0.18 -> 0.05: the owner wanted them "much more ragdoll like, fluid and loose"  -- ragdolled MaxFrictionTorque = rig value x this (restored on get-up)
	WaistSwing = 42,        -- ragdolled waist UpperAngle (rig: 20) - room to arch back / fold
	NeckSwing = 60,         -- ragdolled neck UpperAngle (rig: 45) - the head snaps back
	WhipTorso = 1.08,       -- Fling: UpperTorso speed x this (the hit lands on the chest)
	WhipPelvis = 0.95,      -- LowerTorso
	WhipHead = 0.8,         -- head, upper arms, upper legs trail a little
	WhipLimb = 0.82,
	WhipEnd = 0.62,         -- forearms, hands, shins, feet trail most
	TipBack = 0.045,        -- extra spin (rad/s per stud/s of push) tipping the head back along the push, max TipMax
	TipMax = 9,
	-- (2026-11-13) LOOSE: cone + twist limits WHILE RAGDOLLED, per joint { UpperAngle, TwistLower, TwistUpper } (the
	-- rig's standing limits come back on get-up). Rig values: hip 40 / -5..80, knee 5 / -120..-5, shoulder 110 / +-85,
	-- elbow 20 / 5..120, waist 20 / -40..20, neck 45 / +-40, wrist 30 / +-10, ankle 10 / +-10 - a body with those folds
	-- like a plank. Wider, but still short of joints bending the wrong way.
	Loose = {
		Neck = { 72, -62, 62 }, Waist = { 58, -58, 44 }, Shoulder = { 150, -115, 115 }, Elbow = { 30, -4, 142 },
		Wrist = { 52, -34, 34 }, Hip = { 70, -30, 104 }, Knee = { 14, -140, 2 }, Ankle = { 32, -28, 28 },
	},
	-- a heavy trunk and light limbs: the limbs whip and trail instead of steering the body (average stays under
	-- water's 1.0, so bodies still float). LimbDensity is the fallback.
	Density = { torso = 0.95, head = 0.55, upper = 0.5, lower = 0.42, tip = 0.34 },
}
