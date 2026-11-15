--!nocheck
-- Clips pass "Flair_Blackwhip": R, BLACKWHIP -> ST. LOUIS SMASH, the flair cut. Replaces Clips.Blackwhip.
-- Server beats it lines up with (Config pass Flair_Blackwhip): tendrils leave 0.24, the reel runs to 0.92, the kick
-- lands at 0.98 (the clip key is 0.985, Exponential Out from 0.93, so the leg is ~99% out at 0.98), Lock 1.80 (the
-- 0.08 hit-stop freezes the clip, so the RISE key 1.70 lands at 1.78 cast time on a hit).
-- The performance: a GATHER (forearms crossed in front of the face, sunk, trembling) -> the LASH (arms flung out
-- wide, an overshoot, held out while the whips fly) -> the YANK (fists ripped to the ribs, leaning back, straining)
-- -> the LOAD (hips and chest wound right, eyes kept on the aim) -> a HOP off the left toes into a tucked mid-air
-- spin (120 / 230 / 332, the head spotting the target) -> the kicking knee cocked -> ST. LOUIS SMASH at 430 (a full
-- turn plus 70: the right leg out forward at chest height, still sweeping left, body rolled 24 away, arms
-- counter-flung) -> HELD to 1.22 (pushing 4 deg further, then sinking) -> the spin completes on the way down (540 / 630) -> a
-- superhero LAND at 720 (left foot flat, right knee low on its toes, right fingertips at the ground) -> settle,
-- rise, rest. Every root-yaw step is < 180 deg so CFrame:Lerp keeps turning LEFT; 720 is the identity again.
-- Every key names all 15 joints (a joint left out would glide straight between distant keys instead of holding).
-- FK-checked on a live R15 constraint rig: planted soles within 0.02 of the floor, nothing through the body, no
-- hyperextension; at the freeze (0.98) the kick leg points 0.95 along the aim (13 deg left of it, still sweeping:
-- it crossed the aim line at 0.95), the head faces straight down the aim (flat 1.00), pitched down at the bodies.
return function(H)
	return {
		Blackwhip = {
			length = 1.88, fadeIn = 0.07, fadeOut = 0.18,
			keys = {
			{ t = 0.1, ease = { "Quad", "Out" }, pose = { -- DRAW: the gather - forearms crossed, sunk, glaring
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.62, 0.12) }, Waist = { -22, 8, 0 }, Neck = { 16, -8, 0 },
				RightShoulder = { 95, 60, -40 }, RightElbow = { 90, 0, 0 }, RightWrist = { -10, 0, 0 },
				LeftShoulder = { 110, -60, 40 }, LeftElbow = { 90, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 31, -2, 12 }, RightKnee = { -89, 0, 0 }, RightAnkle = { 57, -4, -8 },
				LeftHip = { 69, 0, -10 }, LeftKnee = { -83, 0, 0 }, LeftAnkle = { 15, -1, 3 },
			} },
			{ t = 0.14, ease = { "Sine", "InOut" }, pose = { -- DRAW2 tremble 1/3
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.68, 0.14) }, Waist = { -27.6, 7.44, 0 }, Neck = { 13.4, -9.56, 0 },
				RightShoulder = { 94.4, 60.44, -42 }, RightElbow = { 93.4, 0, 0 }, RightWrist = { -10, 0, 0 },
				LeftShoulder = { 109.4, -63.56, 42 }, LeftElbow = { 93.4, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 34, -2, 12 }, RightKnee = { -94, 0, 0 }, RightAnkle = { 59, -3, -8 },
				LeftHip = { 72, 0, -11 }, LeftKnee = { -88, 0, 0 }, LeftAnkle = { 15, -2, 3 },
			} },
			{ t = 0.18, ease = { "Sine", "InOut" }, pose = { -- DRAW2 tremble 2/3
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.68, 0.14) }, Waist = { -22.4, 10.56, 0 }, Neck = { 18.6, -6.44, 0 },
				RightShoulder = { 99.6, 63.56, -42 }, RightElbow = { 98.6, 0, 0 }, RightWrist = { -10, 0, 0 },
				LeftShoulder = { 114.6, -60.44, 42 }, LeftElbow = { 98.6, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 34, -2, 12 }, RightKnee = { -94, 0, 0 }, RightAnkle = { 59, -3, -8 },
				LeftHip = { 72, 0, -11 }, LeftKnee = { -88, 0, 0 }, LeftAnkle = { 15, -2, 3 },
			} },
			{ t = 0.22, ease = { "Sine", "InOut" }, pose = { -- DRAW2 tremble 3/3
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.68, 0.14) }, Waist = { -27.6, 7.44, 0 }, Neck = { 13.4, -9.56, 0 },
				RightShoulder = { 94.4, 60.44, -42 }, RightElbow = { 93.4, 0, 0 }, RightWrist = { -10, 0, 0 },
				LeftShoulder = { 109.4, -63.56, 42 }, LeftElbow = { 93.4, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 34, -2, 12 }, RightKnee = { -94, 0, 0 }, RightAnkle = { 59, -3, -8 },
				LeftHip = { 72, 0, -11 }, LeftKnee = { -88, 0, 0 }, LeftAnkle = { 15, -2, 3 },
			} },
			{ t = 0.255, ease = { "Exponential", "Out" }, pose = { -- LASH: arms thrown out (tendrils leave at 0.24)
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.46, -0.06) }, Waist = { 4, 0, 0 }, Neck = { 12, 0, 0 },
				RightShoulder = { 98, 0, 34 }, RightElbow = { 2, 0, 0 }, RightWrist = { -55, 0, 0 },
				LeftShoulder = { 98, 0, -34 }, LeftElbow = { 2, 0, 0 }, LeftWrist = { -55, 0, 0 },
				RightHip = { 15, -3, 10 }, RightKnee = { -69, 0, 0 }, RightAnkle = { 53, -5, -8 },
				LeftHip = { 55, 1, -9 }, LeftKnee = { -75, 0, 0 }, LeftAnkle = { 20, 0, 4 },
			} },
			{ t = 0.31, ease = { "Sine", "Out" }, pose = { -- LASH overshoot
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.42, -0.1) }, Waist = { 8, 0, 0 }, Neck = { 15, 0, 0 },
				RightShoulder = { 104, 0, 41 }, RightElbow = { 0, 0, 0 }, RightWrist = { -62, 0, 0 },
				LeftShoulder = { 104, 0, -41 }, LeftElbow = { 0, 0, 0 }, LeftWrist = { -62, 0, 0 },
				RightHip = { 11, -3, 9 }, RightKnee = { -63, 0, 0 }, RightAnkle = { 51, -6, -8 },
				LeftHip = { 52, 1, -9 }, LeftKnee = { -72, 0, 0 }, LeftAnkle = { 20, 0, 4 },
			} },
			{ t = 0.42, ease = { "Sine", "InOut" }, pose = { -- arms held out while the whips fly
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.5, 0) }, Waist = { -6, 0, 0 }, Neck = { 9, 0, 0 },
				RightShoulder = { 90, 0, 27 }, RightElbow = { 10, 0, 0 }, RightWrist = { -38, 0, 0 },
				LeftShoulder = { 90, 0, -27 }, LeftElbow = { 10, 0, 0 }, LeftWrist = { -38, 0, 0 },
				RightHip = { 20, -3, 10 }, RightKnee = { -75, 0, 0 }, RightAnkle = { 54, -5, -8 },
				LeftHip = { 59, 1, -10 }, LeftKnee = { -77, 0, 0 }, LeftAnkle = { 18, 0, 4 },
			} },
			{ t = 0.5, ease = { "Back", "Out" }, pose = { -- YANK: the reel
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.56, 0.38) }, Waist = { 12, 0, 0 }, Neck = { 4, 0, 0 },
				RightShoulder = { -34, 0, 30 }, RightElbow = { 118, 0, 0 }, RightWrist = { 12, 0, 0 },
				LeftShoulder = { -34, 0, -30 }, LeftElbow = { 118, 0, 0 }, LeftWrist = { 12, 0, 0 },
				RightHip = { 42, -2, 14 }, RightKnee = { -88, 0, 0 }, RightAnkle = { 45, -2, -8 },
				LeftHip = { 67, 1, -9 }, LeftKnee = { -66, 0, 0 }, LeftAnkle = { 0, -1, 3 },
			} },
			{ t = 0.56, ease = { "Sine", "InOut" }, pose = { -- YANK2 strain tremble 1/2
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.6, 0.42) }, Waist = { 11.8, -1.32, 0 }, Neck = { 1.8, -1.32, 0 },
				RightShoulder = { -36.2, -1.32, 30 }, RightElbow = { 115.8, 0, 0 }, RightWrist = { 12, 0, 0 },
				LeftShoulder = { -36.2, -1.32, -30 }, LeftElbow = { 115.8, 0, 0 }, LeftWrist = { 12, 0, 0 },
				RightHip = { 45, -2, 14 }, RightKnee = { -92, 0, 0 }, RightAnkle = { 46, -2, -7 },
				LeftHip = { 70, 1, -9 }, LeftKnee = { -68, 0, 0 }, LeftAnkle = { -1, -1, 2 },
			} },
			{ t = 0.62, ease = { "Sine", "InOut" }, pose = { -- YANK2 strain tremble 2/2
				Root = { 0, 0, 0, pos = Vector3.new(0, -0.6, 0.42) }, Waist = { 16.2, 1.32, 0 }, Neck = { 6.2, 1.32, 0 },
				RightShoulder = { -31.8, 1.32, 30 }, RightElbow = { 120.2, 0, 0 }, RightWrist = { 12, 0, 0 },
				LeftShoulder = { -31.8, 1.32, -30 }, LeftElbow = { 120.2, 0, 0 }, LeftWrist = { 12, 0, 0 },
				RightHip = { 45, -2, 14 }, RightKnee = { -92, 0, 0 }, RightAnkle = { 46, -2, -7 },
				LeftHip = { 70, 1, -9 }, LeftKnee = { -68, 0, 0 }, LeftAnkle = { -1, -1, 2 },
			} },
			{ t = 0.665, ease = { "Quad", "InOut" }, pose = { -- LOAD: wound right, deep
				Root = { 0, -40, 0, pos = Vector3.new(0, -0.78, 0.15) }, Waist = { -14, -30, 0 }, Neck = { 8, 62, 0 },
				RightShoulder = { -42, 0, 44 }, RightElbow = { 58, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 62, 0, 48 }, LeftElbow = { 72, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 68, 1, 16 }, RightKnee = { -104, 0, 0 }, RightAnkle = { 36, 2, -6 },
				LeftHip = { 59, -2, -16 }, LeftKnee = { -106, 0, 0 }, LeftAnkle = { 46, -2, 9 },
			} },
			{ t = 0.72, ease = { "Exponential", "Out" }, pose = { -- TAKE-OFF: left toes last on the ground
				Root = { 0, 18, 0, pos = Vector3.new(0, 0.4, 0) }, Waist = { -6, 10, 0 }, Neck = { 8, -16, 0 },
				RightShoulder = { 122, 0, 28 }, RightElbow = { 42, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 88, 0, -62 }, LeftElbow = { 50, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 96, 0, 14 }, RightKnee = { -116, 0, 0 }, RightAnkle = { -20, 0, 0 },
				LeftHip = { -4, 0, -6 }, LeftKnee = { -14, 0, 0 }, LeftAnkle = { -38, 0, 0 },
			} },
			{ t = 0.79, ease = { "Linear", "Out" }, pose = { -- SPIN 120
				Root = { 0, 120, 6, pos = Vector3.new(0, 1.25, 0) }, Waist = { -8, 0, 0 }, Neck = { 6, -42, 0 },
				RightShoulder = { 52, 0, 16 }, RightElbow = { 122, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 52, 0, -16 }, LeftElbow = { 122, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 88, 0, 18 }, RightKnee = { -128, 0, 0 }, RightAnkle = { -20, 0, 0 },
				LeftHip = { 70, 0, -8 }, LeftKnee = { -116, 0, 0 }, LeftAnkle = { -24, 0, 0 },
			} },
			{ t = 0.86, ease = { "Linear", "Out" }, pose = { -- SPIN 230
				Root = { 0, 230, 8, pos = Vector3.new(0, 1.4, 0) }, Waist = { -8, 0, 0 }, Neck = { 6, -58, 0 },
				RightShoulder = { 52, 0, 16 }, RightElbow = { 122, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 52, 0, -16 }, LeftElbow = { 122, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 88, 0, 18 }, RightKnee = { -128, 0, 0 }, RightAnkle = { -20, 0, 0 },
				LeftHip = { 70, 0, -8 }, LeftKnee = { -116, 0, 0 }, LeftAnkle = { -24, 0, 0 },
			} },
			{ t = 0.93, ease = { "Quad", "Out" }, pose = { -- CHAMBER 332
				Root = { 0, 332, 14, pos = Vector3.new(0, 1.36, 0) }, Waist = { -6, -12, 0 }, Neck = { 4, 34, 0 },
				RightShoulder = { 22, 0, 60 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 40, 0, -62 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 74, 0, 62 }, RightKnee = { -126, 0, 0 }, RightAnkle = { -26, 0, 0 },
				LeftHip = { 56, 0, -8 }, LeftKnee = { -104, 0, 0 }, LeftAnkle = { -20, 0, 0 },
			} },
			{ t = 0.985, ease = { "Exponential", "Out" }, pose = { -- ST. LOUIS SMASH (server kick 0.98)
				Root = { 0, 430, 24, pos = Vector3.new(0, 1.2, 0) }, Waist = { -26, -14, -10 }, Neck = { -25, -40, 0 },
				RightShoulder = { -30, 0, 22 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 12, 0, -98 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 82, 0, 57 }, RightKnee = { -4, 0, 0 }, RightAnkle = { -32, 0, 0 },
				LeftHip = { 62, 0, -10 }, LeftKnee = { -112, 0, 0 }, LeftAnkle = { -22, 0, 0 },
			} },
			{ t = 1.06, ease = { "Sine", "Out" }, pose = { -- HOLD A: the extension pushes a touch further
				Root = { 0, 434, 26, pos = Vector3.new(0, 1.24, 0) }, Waist = { -26, -14, -10 }, Neck = { -25, -40, 0 },
				RightShoulder = { -34, 0, 24 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 14, 0, -104 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 84, 0, 61 }, RightKnee = { -4, 0, 0 }, RightAnkle = { -32, 0, 0 },
				LeftHip = { 62, 0, -10 }, LeftKnee = { -112, 0, 0 }, LeftAnkle = { -22, 0, 0 },
			} },
			{ t = 1.22, ease = { "Sine", "InOut" }, pose = { -- HOLD B: held, starting to sink
				Root = { 0, 438, 22, pos = Vector3.new(0, 1.1, 0) }, Waist = { -26, -14, -10 }, Neck = { -22, -36, 0 },
				RightShoulder = { -30, 0, 22 }, RightElbow = { 18, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 12, 0, -96 }, LeftElbow = { 12, 0, 0 }, LeftWrist = { -10, 0, 0 },
				RightHip = { 80, 0, 54 }, RightKnee = { -10, 0, 0 }, RightAnkle = { -32, 0, 0 },
				LeftHip = { 62, 0, -10 }, LeftKnee = { -112, 0, 0 }, LeftAnkle = { -22, 0, 0 },
			} },
			{ t = 1.31, ease = { "Quad", "In" }, pose = { -- UNWIND 540
				Root = { 0, 540, 10, pos = Vector3.new(0, 0.85, 0) }, Waist = { -10, 0, 0 }, Neck = { 6, -30, 0 },
				RightShoulder = { 30, 0, 50 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 30, 0, -56 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 60, 0, 30 }, RightKnee = { -72, 0, 0 }, RightAnkle = { -20, 0, 0 },
				LeftHip = { 30, 0, -8 }, LeftKnee = { -44, 0, 0 }, LeftAnkle = { -20, 0, 0 },
			} },
			{ t = 1.39, ease = { "Linear", "Out" }, pose = { -- UNWIND 630, legs reach for the ground
				Root = { 0, 630, 4, pos = Vector3.new(0, 0.42, 0) }, Waist = { -10, 0, 0 }, Neck = { 8, -20, 0 },
				RightShoulder = { 24, 0, 64 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 24, 0, -64 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 34, 0, 14 }, RightKnee = { -46, 0, 0 }, RightAnkle = { -12, 0, 0 },
				LeftHip = { 34, 0, -12 }, LeftKnee = { -46, 0, 0 }, LeftAnkle = { -12, 0, 0 },
			} },
			{ t = 1.46, ease = { "Quad", "Out" }, pose = { -- LAND 720: superhero crouch, fingertips down
				Root = { 0, 720, 0, pos = Vector3.new(0, -1.15, 0.02) }, Waist = { -38, 10, 0 }, Neck = { 40, -10, 0 },
				RightShoulder = { 42, 0, -12 }, RightElbow = { 12, 0, 0 }, RightWrist = { -30, 0, 0 },
				LeftShoulder = { -38, 0, -50 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 18, 5, 19 }, RightKnee = { -138, 0, 0 }, RightAnkle = { 71, 1, 1 },
				LeftHip = { 101, -5, -15 }, LeftKnee = { -117, 0, 0 }, LeftAnkle = { 15, -4, 1 },
			} },
			{ t = 1.56, ease = { "Back", "Out" }, pose = { -- SETTLE
				Root = { 0, 720, 0, pos = Vector3.new(0, -1.08, 0.04) }, Waist = { -34, 8, 0 }, Neck = { 36, -8, 0 },
				RightShoulder = { 39, -2, -13 }, RightElbow = { 13, 0, 0 }, RightWrist = { -30, 0, 0 },
				LeftShoulder = { -30, 0, -46 }, LeftElbow = { 26, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 22, 5, 20 }, RightKnee = { -136, 0, 0 }, RightAnkle = { 68, 1, 1 },
				LeftHip = { 97, -4, -15 }, LeftKnee = { -113, 0, 0 }, LeftAnkle = { 15, -3, 2 },
			} },
			{ t = 1.7, ease = { "Sine", "InOut" }, pose = { -- RISE
				Root = { 0, 720, 0, pos = Vector3.new(0, -0.45, 0) }, Waist = { -10, 4, 0 }, Neck = { 6, -4, 0 },
				RightShoulder = { 18, 0, 22 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 14, 0, -26 }, LeftElbow = { 36, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 21, -3, 12 }, RightKnee = { -72, 0, 0 }, RightAnkle = { 50, -5, -9 },
				LeftHip = { 57, 1, -11 }, LeftKnee = { -70, 0, 0 }, LeftAnkle = { 13, -1, 5 },
			} },
			{ t = 1.84, ease = { "Sine", "InOut" }, pose = { -- REST
				Root = { 0, 0, 0, pos = Vector3.new(0, 0, 0) }, Waist = { -4, 0, 0 }, Neck = { 0, 0, 0 },
				RightShoulder = { 10, 0, 14 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 },
				LeftShoulder = { 10, 0, -14 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 },
				RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
				LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, LeftAnkle = { 0, 0, 0 },
			} },
			},
		},
	}
end
