--!nocheck
-- GomuKit.Clips.Scaffold (owner: client): the scaffold's own clips. Scaffold_Boing = the rubber landing squash that
-- GomuKit.Client.Shared.boing plays (the passive on every hard landing, and any move that wants a cartoon bounce):
-- a deep squash, a stretched rebound up onto the toes with the arms flung out, a small second squash, settle. Only
-- the Root / Waist / legs / shoulders are posed, so it layers over a run or a move clip for its 0.42 s and fades back.
-- The rig is NEVER scaled: the squash is all pose (Root drop + folded legs), the stretch is a Root lift onto the toes.
return function(H)
	local key = H.key
	local SQUASH = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.85, 0) }, Waist = { -12, 0, 0 },
		LeftHip = { 62, 0, -14 }, RightHip = { 62, 0, 14 }, LeftKnee = { -114, 0, 0 }, RightKnee = { -114, 0, 0 },
		LeftAnkle = { 50, 0, 0 }, RightAnkle = { 50, 0, 0 },
		LeftShoulder = { 20, 0, -58 }, RightShoulder = { 20, 0, 58 },
	}
	local STRETCH = {
		Root = { 0, 0, 0, pos = Vector3.new(0, 0.38, 0) }, Waist = { 8, 0, 0 },
		LeftHip = { -6, 0, -4 }, RightHip = { -6, 0, 4 }, LeftKnee = { -4, 0, 0 }, RightKnee = { -4, 0, 0 },
		LeftAnkle = { -24, 0, 0 }, RightAnkle = { -24, 0, 0 },
		LeftShoulder = { 34, 0, -26 }, RightShoulder = { 34, 0, 26 },
	}
	local SMALL = {
		Root = { 0, 0, 0, pos = Vector3.new(0, -0.25, 0) }, Waist = { -4, 0, 0 },
		LeftHip = { 20, 0, -8 }, RightHip = { 20, 0, 8 }, LeftKnee = { -36, 0, 0 }, RightKnee = { -36, 0, 0 },
		LeftAnkle = { 16, 0, 0 }, RightAnkle = { 16, 0, 0 },
		LeftShoulder = { 14, 0, -32 }, RightShoulder = { 14, 0, 32 },
	}
	local SETTLE = {
		Root = { 0, 0, 0, pos = Vector3.zero }, Waist = { 0, 0, 0 },
		LeftHip = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightKnee = { 0, 0, 0 },
		LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
		LeftShoulder = { 0, 0, -6 }, RightShoulder = { 0, 0, 6 },
	}
	return {
		Scaffold_Boing = {
			length = 0.42, fadeIn = 0.03, fadeOut = 0.12,
			keys = {
				key(0, SQUASH, "Quad", "Out"),
				key(0.07, SQUASH, "Quad", "Out"),
				key(0.19, STRETCH, "Back", "Out"),
				key(0.3, SMALL, "Quad", "InOut"),
				key(0.42, SETTLE, "Sine", "Out"),
			},
		},
	}
end
