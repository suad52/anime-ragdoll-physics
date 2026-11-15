-- Collision groups (read-only for builders; orchestrator owns this file)
return {
	Groups = { "Players", "NPCs", "Ragdolls", "Debris" },
	-- pairs that must NOT collide; every other pair collides
	NonColliding = {
		{ "Players", "Ragdolls" },
		{ "Players", "Debris" },
		{ "NPCs", "Debris" },
	},
}
