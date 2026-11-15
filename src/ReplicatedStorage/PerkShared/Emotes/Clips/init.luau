--!nocheck
-- PerkShared.Emotes.Clips (owner: emotes, 2026-11-07): the Emote Pack's three procedural clips (Taunt / Laugh /
-- Victory) for GojoShared.Client.ProceduralAnimator, plus each clip's flair beats (FX[id], drawn by PerkShared.Emotes).
-- clip = { length, fadeIn?, fadeOut?, keys = { { t, ease = {"Quad","Out"}, pose = { Joint = {x,y,z, pos = Vector3?} } } } }
-- Signs (the kits' measured ones): shoulder/elbow/hip/wrist flexion +X, knee flexion -X, forward lean Waist -X, +Y turns
-- left, right limb out Z+, left limb out Z-, Neck +X lifts the chin. Root pos (HumanoidRootPart frame): -Y crouches,
-- +Z slides back. CFrame.Angles applies Z first. Every key pair on one axis stays < 180 deg apart.
-- Legs only ever use the kits' FK-verified STAND / CROUCH / LOW / WIDE stances (feet on the floor), except the
-- Victory hop, which lifts the whole body on purpose.
-- ARMS (2026-11-08 realism pass): the elbow is a HINGE - Elbow keys use X only (0..140, never negative), any other
-- direction comes from the shoulder's twist. (The old fist-on-hip / wave / double-biceps / shrug poses bent the
-- elbow sideways with Z, which kinked the forearm off the upper arm like a broken joint.) Every new arm pose was
-- solved with a 2-bone IK against the stock R15 rig (wrist on its target, elbow pole set, then the wrist twist for
-- the palm) and swept by FK for forearms / hands passing through the torso or head. No "Back" easing (its overshoot
-- made the arms wobble like rubber): snappy keys use Quart Out. FOLLOW-THROUGH (bottom of this module): elbows trail
-- their shoulder by LAG.Elbow, wrists by LAG.Wrist and the head trails the chest by LAG.Neck, on every clip.
local V = Vector3.new
local C = Color3.fromRGB

local function merge(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end
local function seq(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			table.insert(out, v)
		end
	end
	return out
end
local function key(t, pose, style, dir)
	return { t = t, ease = { style or "Quad", dir or "Out" }, pose = pose }
end
-- n shake keys over (t0, t1] alternating +/- amp degrees on the named joints around `pose` (the kits' tremble).
-- twist (default 0.6) = the Y share of each shake; 0 = a pure nod, which moves both hands alike (a Y twist on the
-- waist swings one hand forward while the other goes back, so only one of them looked like it was twitching)
local function tremble(t0, t1, n, pose, joints, amp, twist)
	twist = twist or 0.6
	local keys = {}
	for i = 1, n do
		local s = (i % 2 == 0) and 1 or -1
		local p = {}
		for name, v in pairs(pose) do
			if joints[name] then
				p[name] = { (v[1] or 0) + amp * s, (v[2] or 0) + amp * twist * s, v[3] or 0, pos = v.pos }
			else
				p[name] = v
			end
		end
		table.insert(keys, { t = t0 + (t1 - t0) * i / n, ease = { "Sine", "InOut" }, pose = p })
	end
	return keys
end

---------------------------------------------------------------------------------------------------
-- stances (STAND / CROUCH / LOW / WIDE / RELAX are the FK-verified ones from the Deku / Ichigo / Luffy kits)
local STAND = {
	Root = { 0, 0, 0, pos = V(0, 0, 0) }, LeftHip = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 },
	RightKnee = { 0, 0, 0 }, LeftAnkle = { 0, 0, 0 }, RightAnkle = { 0, 0, 0 },
}
local CROUCH = {
	Root = { 0, 0, 0, pos = V(0, -0.7, 0) }, LeftHip = { 55, 0, -10 }, RightHip = { 55, 0, 10 },
	LeftKnee = { -102, 0, 0 }, RightKnee = { -102, 0, 0 }, LeftAnkle = { 43, 0, 0 }, RightAnkle = { 43, 0, 0 },
}
local LOW = {
	Root = { 0, 0, 0, pos = V(0, -0.5, 0) }, LeftHip = { 43, 0, -12 }, RightHip = { 42, 0, 12 },
	LeftKnee = { -82, 0, 0 }, RightKnee = { -83, 0, 0 }, LeftAnkle = { 39, 0, 0 }, RightAnkle = { 39, 0, 0 },
}
-- planted split stance: left foot forward, right leg braced back
local WIDE = {
	Root = { 0, 0, 0, pos = V(0, -0.65, 0.15) },
	LeftHip = { 58, 0, -16 }, LeftKnee = { -101, 0, 0 }, LeftAnkle = { 43, 0, 0 },
	RightHip = { -39, 0, 16 }, RightKnee = { -21, 0, 0 }, RightAnkle = { 64, 0, 0 },
}
local RELAX = { LeftShoulder = { 10, 0, -14 }, LeftElbow = { 24, 0, 0 }, LeftWrist = { 0, 0, 0 } }
local RELAX_R = { RightShoulder = { 10, 0, 14 }, RightElbow = { 24, 0, 0 }, RightWrist = { 0, 0, 0 } }
local REST = merge(STAND, RELAX, RELAX_R, { Waist = { -2, 0, 0 }, Neck = { 0, 0, 0 } })

local Clips = {}

---------------------------------------------------------------------------------------------------
-- TAUNT (2.6 s): a coiled dip, then side-on in the split stance with the chin up, the right fist on the hip and the
-- lead (left) hand held out - three big "come here" curls of the fingers - then "BRING IT": squared up, chest out,
-- arms flung wide, shaking with it.
local T_ANTIC = merge(LOW, {
	Waist = { -14, 12, 0 }, Neck = { -8, -8, 0 },
	RightShoulder = { 42, 0, 18 }, RightElbow = { 105, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 42, 0, -18 }, LeftElbow = { 105, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
local T_SET = merge(WIDE, {
	Waist = { 6, -24, 0 }, Neck = { 16, 20, 0 },
	RightShoulder = { -62, 32, 26 }, RightElbow = { 88, 0, 0 }, RightWrist = { 10, -6, 0 }, -- fist on the hip, elbow out and back (IK)
	LeftShoulder = { 84, 0, -6 }, LeftElbow = { 8, 0, 0 }, LeftWrist = { -35, 0, 0 },      -- lead hand out, open
})
local T_CURL = merge(T_SET, {
	Neck = { 22, 20, 0 },
	LeftShoulder = { 70, 0, -6 }, LeftElbow = { 78, 0, 0 }, LeftWrist = { 55, 0, 0 },
})
local T_BRING = merge(WIDE, {
	Waist = { 16, 0, 0 }, Neck = { 22, 0, 0 },
	RightShoulder = { 25, 0, 80 }, RightElbow = { 28, 0, 0 }, RightWrist = { -20, 0, 0 },
	LeftShoulder = { 25, 0, -80 }, LeftElbow = { 28, 0, 0 }, LeftWrist = { -20, 0, 0 },
})
local T_BRING2 = merge(T_BRING, {
	Waist = { 20, 0, 0 }, Neck = { 26, 0, 0 },
	RightShoulder = { 30, 0, 92 }, LeftShoulder = { 30, 0, -92 },
})
local SHAKE_UPPER = { Waist = true, Neck = true, RightShoulder = true, LeftShoulder = true }

Clips.Taunt = {
	length = 2.6, fadeIn = 0.08, fadeOut = 0.3,
	keys = seq(
		{
			key(0.12, T_ANTIC, "Quad", "Out"),
			key(0.32, T_SET, "Quart", "Out"),
			key(0.55, T_CURL, "Quad", "InOut"),
			key(0.74, T_SET, "Quart", "Out"),
			key(0.95, T_CURL, "Quad", "InOut"),
			key(1.14, T_SET, "Quart", "Out"),
			key(1.35, T_CURL, "Quad", "InOut"),
			key(1.56, T_SET, "Quart", "Out"),
			key(1.78, T_BRING, "Quart", "Out"),
			key(1.92, T_BRING2, "Sine", "InOut"),
		},
		tremble(1.92, 2.22, 5, T_BRING2, SHAKE_UPPER, 3),
		{ key(2.45, REST, "Sine", "InOut") }
	),
}

---------------------------------------------------------------------------------------------------
-- LAUGH (2.6 s): a sharp breath in, then thrown back with the hands on the belly, bouncing with it - then doubled
-- over, one hand clutching the belly and the other slapping the knee three times, head still up laughing at you.
local L_INHALE = merge(STAND, {
	Waist = { 8, 0, 0 }, Neck = { 12, 0, 0 },
	RightShoulder = { 0, 30, 12 }, RightElbow = { 45, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 0, -30, -12 }, LeftElbow = { 45, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
-- hands on the belly: the upper arm twisted in (Y) so the bent forearm folds across the stomach (FK: hands 0.78 in
-- front of the torso centre, 0.6 below the chest centre, 0.5 either side of the midline)
local BELLY_R = { RightShoulder = { -10, 60, 6 }, RightElbow = { 70, 0, 0 }, RightWrist = { 0, 0, 0 } }
local BELLY_L = { LeftShoulder = { -10, -60, -6 }, LeftElbow = { 70, 0, 0 }, LeftWrist = { 0, 0, 0 } }
local L_BACK = merge(STAND, BELLY_R, BELLY_L, {
	Root = { 0, 0, 0, pos = V(0, 0, 0.15) },
	Waist = { 24, 0, 0 }, Neck = { 32, 0, 0 },
})
-- one "HA" (2026-11-08): the chest pumps back and the shoulders hop. The ARM ANGLES never change, so the hands stay
-- pressed on the belly and only ride the body (the old L_BACK2 changed the shoulder angles too, so both hands slid
-- up and down the stomach four times a second, out of step with the chest). `a` = 0..1 strength of the laugh.
local function laughPeak(a)
	return merge(L_BACK, {
		Root = { 0, 0, 0, pos = V(0, 0.05 * a, 0.15 + 0.04 * a) },
		Waist = { 24 + 7 * a, 0, 0 }, Neck = { 32 + 10 * a, 0, 0 },
		RightShoulder = { -10, 60, 6, pos = V(0, 0.05 * a, 0) }, LeftShoulder = { -10, -60, -6, pos = V(0, 0.05 * a, 0) },
	})
end
local L_DOUBLE = merge(LOW, BELLY_L, {                                                 -- left still on the belly
	Waist = { -36, 0, 0 }, Neck = { 26, 0, 0 },
	RightShoulder = { 15, 0, -25 }, RightElbow = { 40, 0, 0 }, RightWrist = { 0, 0, 0 },  -- palm on the right thigh
})
local L_SLAP_UP = merge(L_DOUBLE, {
	Waist = { -30, 0, 0 }, Neck = { 30, 0, 0 },
	RightShoulder = { 110, 0, 30 }, RightElbow = { 70, 0, 0 },
})

-- the laugh's pulses: a quick pump (Quad Out) and a softer release per gap; the gaps lengthen and the pumps shrink
-- as the laugh runs out of breath
local function laughBounce(t0, gaps)
	local keys, t = {}, t0
	for i, g in ipairs(gaps) do
		local a = 1 - (i - 1) / (#gaps + 1)
		table.insert(keys, key(t + g * 0.4, laughPeak(a), "Quad", "Out"))
		t += g
		table.insert(keys, key(t, L_BACK, "Sine", "InOut"))
	end
	return keys
end

Clips.Laugh = {
	length = 2.6, fadeIn = 0.06, fadeOut = 0.3,
	keys = seq(
		{
			key(0.12, L_INHALE, "Quad", "Out"),
			key(0.3, L_BACK, "Quart", "Out"),
		},
		laughBounce(0.3, { 0.11, 0.11, 0.12, 0.12, 0.13, 0.13, 0.14, 0.14 }), -- 8 "HA"s, 0.3 -> 1.3 s
		{
			key(1.48, L_DOUBLE, "Quart", "Out"),
			key(1.6, L_SLAP_UP, "Quad", "Out"),
			key(1.72, L_DOUBLE, "Quad", "In"),
			key(1.84, L_SLAP_UP, "Quad", "Out"),
			key(1.96, L_DOUBLE, "Quad", "In"),
			key(2.08, L_SLAP_UP, "Quad", "Out"),
			key(2.2, L_DOUBLE, "Quad", "In"),
			key(2.48, REST, "Sine", "InOut"),
		}
	),
}

---------------------------------------------------------------------------------------------------
-- VICTORY (2.8 s): gathered into a crouch with the fists crossed, then a hop with the right fist punched at the sky
-- and the legs tucked, a squash landing, the hero pose (split stance, fist high, the other on the hip, chin up) and
-- three "YES!" fist pumps.
local V_GATHER = merge(CROUCH, {
	Waist = { -22, 0, 0 }, Neck = { -12, 0, 0 },
	RightShoulder = { 70, 0, -28 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { 70, 0, 28 }, LeftElbow = { 120, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
local V_LEAP = {
	Root = { 0, 0, 0, pos = V(0, 0.9, 0) },
	LeftHip = { 55, 0, -8 }, RightHip = { 30, 0, 8 }, LeftKnee = { -95, 0, 0 }, RightKnee = { -60, 0, 0 },
	LeftAnkle = { 10, 0, 0 }, RightAnkle = { 10, 0, 0 },
	Waist = { 14, 0, 0 }, Neck = { 28, 0, 0 },
	RightShoulder = { 172, 0, 8 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { -20, 0, -30 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
}
local V_LAND = merge(LOW, {
	Waist = { -8, 0, 0 }, Neck = { 12, 0, 0 },
	RightShoulder = { 162, 0, 12 }, RightElbow = { 12, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { -20, 0, -30 }, LeftElbow = { 100, 0, 0 }, LeftWrist = { 0, 0, 0 },
})
local V_HERO = merge(WIDE, {
	Waist = { 6, -14, 0 }, Neck = { 24, 10, 0 },
	RightShoulder = { 172, 0, 10 }, RightElbow = { 0, 0, 0 }, RightWrist = { 0, 0, 0 },
	LeftShoulder = { -62, -32, -26 }, LeftElbow = { 88, 0, 0 }, LeftWrist = { 10, 6, 0 }, -- fist on the hip, elbow out and back (IK)
})
local V_PUMP = merge(V_HERO, {
	Waist = { 4, -14, 0 }, Neck = { 16, 10, 0 },
	RightShoulder = { 148, 0, 24 }, RightElbow = { 62, 0, 0 },
})

Clips.Victory = {
	length = 2.8, fadeIn = 0.06, fadeOut = 0.3,
	keys = seq(
		{
			key(0.16, V_GATHER, "Quad", "Out"),
			key(0.36, V_LEAP, "Exponential", "Out"),
			key(0.56, V_LAND, "Quad", "In"),
			key(0.8, V_HERO, "Quart", "Out"),
			key(1.08, V_PUMP, "Quad", "In"),
			key(1.26, V_HERO, "Quart", "Out"),
			key(1.48, V_PUMP, "Quad", "In"),
			key(1.66, V_HERO, "Quart", "Out"),
			key(1.88, V_PUMP, "Quad", "In"),
			key(2.06, V_HERO, "Quart", "Out"),
		},
		tremble(2.06, 2.34, 4, V_HERO, { Waist = true, Neck = true }, 2),
		{ key(2.62, REST, "Sine", "InOut") }
	),
}

---------------------------------------------------------------------------------------------------
-- flair beats (seconds from the clip's start), drawn by PerkShared.Emotes on every client:
--   text    a comic word over the head (pop, wobble, fade)       { t, kind="text", text, c0, c1, size, hold, rot }
--   ha      a ring of "HA" letters bursting round the head       { t, kind="ha", n }
--   spark   a burst of sparkles from a body part                  { t, kind="spark", part, n, color }
--   flash   a shockwave ring flash at a body part                 { t, kind="flash", part, color, size }
--   whoosh  a short whoosh on the root part                       { t, kind="whoosh", pitch, volume }
local GOLD, SUN, WHITE = C(255, 205, 60), C(255, 240, 150), C(255, 255, 255)
local EMBER, RED = C(255, 140, 50), C(255, 70, 60)
Clips.FX = {
	Taunt = {
		{ t = 0.3, kind = "text", text = "COME ON!", c0 = WHITE, c1 = EMBER, size = 6, hold = 1.3, rot = -8 },
		{ t = 0.3, kind = "whoosh", pitch = 1.2, volume = 0.35 },
		{ t = 1.76, kind = "text", text = "BRING IT!", c0 = SUN, c1 = RED, size = 8, hold = 0.75, rot = 6 },
		{ t = 1.76, kind = "flash", part = "UpperTorso", color = EMBER, size = 9 },
		{ t = 1.76, kind = "whoosh", pitch = 0.9, volume = 0.45 },
	},
	Laugh = {
		{ t = 0.28, kind = "ha", n = 7 },
		{ t = 0.85, kind = "ha", n = 5 },
		{ t = 1.5, kind = "ha", n = 7 },
	},
	Victory = {
		{ t = 0.34, kind = "whoosh", pitch = 1.1, volume = 0.45 },
		{ t = 0.36, kind = "spark", part = "RightHand", n = 34, color = GOLD },
		{ t = 0.36, kind = "flash", part = "RightHand", color = SUN, size = 7 },
		{ t = 0.78, kind = "text", text = "VICTORY!", c0 = SUN, c1 = GOLD, size = 8, hold = 1.5, rot = -5 },
		{ t = 0.8, kind = "flash", part = "LowerTorso", color = GOLD, size = 11 },
		{ t = 1.1, kind = "spark", part = "RightHand", n = 12, color = SUN },
		{ t = 1.5, kind = "spark", part = "RightHand", n = 12, color = GOLD },
		{ t = 1.9, kind = "spark", part = "RightHand", n = 14, color = SUN },
	},
}

-- MORE EMOTES (2026-11-07): every ModuleScript child of this module is an emote PACK. A pack returns a FUNCTION that
-- receives the kit below and returns { clips = { Id = clip }, fx = { Id = beats }, glyph = { Id = "字" } }. (A child
-- cannot require this module back - that is a recursive require - so the helpers and the FK-verified stances are
-- handed to it.) Ids must also be listed in HudShared.PerkCatalog.EMOTES to appear in the wheel and the inventory.
Clips.GLYPH = { Taunt = "挑", Laugh = "笑", Victory = "勝" }
Clips.Kit = {
	V = V, C = C, key = key, seq = seq, merge = merge, tremble = tremble,
	STAND = STAND, CROUCH = CROUCH, LOW = LOW, WIDE = WIDE, RELAX = RELAX, RELAX_R = RELAX_R,
	GOLD = GOLD, SUN = SUN, WHITE = WHITE, EMBER = EMBER, RED = RED,
}
local packs = script:GetChildren()
table.sort(packs, function(a, b)
	return a.Name < b.Name
end)
for _, ch in ipairs(packs) do
	if ch:IsA("ModuleScript") then
		local ok, res = pcall(function()
			local fn = require(ch)
			return type(fn) == "function" and fn(Clips.Kit) or fn
		end)
		if ok and type(res) == "table" then
			for id, c in pairs(res.clips or {}) do
				Clips[id] = c
			end
			for id, f in pairs(res.fx or {}) do
				Clips.FX[id] = f
			end
			for id, g in pairs(res.glyph or {}) do
				Clips.GLYPH[id] = g
			end
		else
			warn("[Emotes.Clips] emote pack " .. ch.Name .. " failed to load: " .. tostring(res))
		end
	end
end

-- FOLLOW-THROUGH (2026-11-08): a body moves from the core out - the chest leads, the elbow follows a beat behind the
-- shoulder and the hand behind the elbow. Each key's elbow / wrist / neck angles are re-timed LAG seconds later (as
-- their own single-joint keys; ProceduralAnimator interpolates every joint separately), so arms swing and settle
-- instead of moving as one rigid block. Applied once to every clip, the packs' included.
local LAG = { LeftElbow = 0.035, RightElbow = 0.035, LeftWrist = 0.07, RightWrist = 0.07, Neck = 0.04 }
for id, clip in pairs(Clips) do
	if type(clip) == "table" and type(clip.keys) == "table" and not clip._followThrough then
		local keys = {}
		for _, k in ipairs(clip.keys) do
			local base = {}
			for name, v in pairs(k.pose) do
				if LAG[name] then
					table.insert(keys, { t = math.min(k.t + LAG[name], clip.length), ease = k.ease, pose = { [name] = v } })
				else
					base[name] = v
				end
			end
			table.insert(keys, { t = k.t, ease = k.ease, pose = base })
		end
		table.sort(keys, function(a, b)
			return a.t < b.t
		end)
		clip.keys = keys
		clip._followThrough = true
	end
end

return Clips
