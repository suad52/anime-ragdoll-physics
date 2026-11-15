--!nocheck
-- PunchStyles (orchestrator 2026-11-07, v2): each fighter's 5-hit M1 string - punches AND kicks - plus two finisher
-- variants on hit 5: P[kit].launch (hold SPACE: a rising kick that sends them up) and P[kit].slam (in the air: an
-- axe kick that spikes them down). Built from a small move library (right-side moves; mirror() makes the left).
-- GojoClient.playPunch picks P[Kit][combo] (or the finisher) and whooshes clip.limb; strike times match
-- Config.Punch.HitDelays (light 0.13, mid 0.17, heavy 0.22). Signs: shoulder/elbow/hip/wrist flexion +X, knee
-- flexion -X, lean forward Waist -X, +Y turns left, right arm/leg out Z+; Root pos -Y crouches, -Z steps in.
local V = Vector3.new
local function merge(...)
	local out = {}
	for _, t in ipairs({ ... }) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end
local function R(y, z, rx, ry)
	return { Root = { rx or 0, ry or 0, 0, pos = V(0, y or 0, z or 0) } }
end

-- left <-> right: swap the joint names and flip yaw / roll
local function mirror(pose)
	local out = {}
	for name, v in pairs(pose) do
		local n = name
		if name:sub(1, 5) == "Right" then
			n = "Left" .. name:sub(6)
		elseif name:sub(1, 4) == "Left" then
			n = "Right" .. name:sub(5)
		end
		local m = { v[1] or 0, -(v[2] or 0), -(v[3] or 0) }
		if v.pos then
			m.pos = V(-v.pos.X, v.pos.Y, v.pos.Z)
		end
		out[n] = m
	end
	return out
end

-- head counter-turns the waist, chin lifts on a lean, twist <= 40, crouches bend the standing legs (feet stay down)
local function natural(pose)
	local p = table.clone(pose)
	local w = p.Waist
	if w then
		local yaw = math.clamp(w[2] or 0, -40, 40)
		p.Waist = { w[1] or 0, yaw, w[3] or 0 }
		local n = p.Neck or { 0, 0, 0 }
		local lift = (w[1] or 0) < -6 and (-(w[1]) - 6) * 0.6 or 0
		p.Neck = { (n[1] or 0) + lift, (n[2] or 0) - yaw * 0.7 - (p.Root and (p.Root[2] or 0) * 0.5 or 0), n[3] or 0 }
	end
	local r = p.Root
	if r and r.pos then
		local y = math.clamp(r.pos.Y, -0.7, 1.6)
		p.Root = { r[1] or 0, r[2] or 0, r[3] or 0, pos = V(0, y, math.clamp(r.pos.Z, -0.9, 0.45)) }
		if y < -0.05 then
			local th = math.deg(math.acos(math.clamp(1 + y / 2.1, -1, 1)))
			for _, side in ipairs({ "Right", "Left" }) do
				local hip, knee = p[side .. "Hip"], p[side .. "Knee"]
				local kicking = hip and ((hip[1] or 0) > 45 or math.abs(hip[3] or 0) > 30)
				if not kicking then
					p[side .. "Hip"] = { math.max(hip and hip[1] or 0, th), 0, hip and hip[3] or (side == "Right" and 6 or -6) }
					p[side .. "Knee"] = { math.min(knee and knee[1] or 0, -2 * th), 0, 0 }
					p[side .. "Ankle"] = { th * 0.9, 0, 0 }
				end
			end
		end
	end
	return p
end

local function toward(a, b, k)
	local out = {}
	for name, va in pairs(a) do
		local vb = b[name] or { 0, 0, 0 }
		local v = {}
		for i = 1, 3 do
			v[i] = (va[i] or 0) + ((vb[i] or 0) - (va[i] or 0)) * k
		end
		if va.pos or vb.pos then
			v.pos = (va.pos or V()):Lerp(vb.pos or V(), k)
		end
		out[name] = v
	end
	return out
end

local TIME = { light = { 0.42, 0.07, 0.13, 0.28 }, mid = { 0.50, 0.09, 0.17, 0.35 }, heavy = { 0.68, 0.11, 0.22, 0.48 } }

-- EXAGGERATION (2026-11-07 "much more exaggerated and flashy"): every pose is pushed further from the stance -
-- a deeper wind-up, a strike that overshoots past full extension, then settles - with anatomical caps.
local CAP = { Elbow = { 0, 155 }, Knee = { -155, 0 }, Wrist = { -80, 60 } }
local function exaggerate(pose, base, k)
	local out = {}
	for name, v in pairs(pose) do
		local b = base[name] or { 0, 0, 0 }
		local e = {}
		for i = 1, 3 do
			e[i] = (b[i] or 0) + ((v[i] or 0) - (b[i] or 0)) * k
		end
		for suffix, lim in pairs(CAP) do
			if name:sub(-#suffix) == suffix then
				e[1] = math.clamp(e[1], lim[1], lim[2])
			end
		end
		if v.pos then
			e.pos = (b.pos or V()):Lerp(v.pos, k)
		end
		out[name] = e
	end
	return out
end

-- whole-body tricks a move can carry: spin = degrees of Root yaw through the strike (a spinning kick), flip =
-- degrees of Root pitch (a flip kick), hop = studs the body leaps (visual; the HRP stays planted)
local function trick(pose, yaw, pitch, lift)
	local p = table.clone(pose)
	local r = p.Root or { 0, 0, 0 }
	local pos = r.pos or V()
	p.Root = { (r[1] or 0) + pitch, (r[2] or 0) + yaw, r[3] or 0, pos = pos + V(0, lift, 0) }
	return p
end

-- a clip from a move: { limb, wind, hit, spin?, flip?, hop? } on top of the style's stance
local function clip(kind, base, mv)
	local T = TIME[kind]
	local pb = natural(base)
	local pw = natural(exaggerate(merge(base, mv.wind), base, 1.3))
	local ph = natural(exaggerate(merge(base, mv.hit), base, 1.12))
	local po = natural(exaggerate(merge(base, mv.hit), base, 1.28)) -- the overshoot
	local spin, flip, hop = mv.spin or 0, mv.flip or 0, mv.hop or 0
	-- keys stay < 180 degrees apart so CFrame lerps take the long way round a full spin / flip (checked: the
	-- largest gap is ~166 degrees with the move's own Root yaw added); the settle key is built from the UN-tricked
	-- strike so the spin is only counted once
	local pr = trick(toward(ph, pb, 0.55), spin, flip, hop * 0.15)
	pw = trick(pw, spin * 0.22, flip * 0.1, hop * 0.55)
	ph = trick(ph, spin * 0.55, flip * 0.45, hop)
	po = trick(po, spin * 0.82, flip * 0.78, hop * 0.85)
	-- ROOT MOTION (read by GojoClient): how far the body really travels with this attack, and when. Punches step
	-- in WITH the strike; kicks carry the body forward AFTER it - the foot lands in front and the body follows.
	local kick = (mv.limb or ""):find("Foot") ~= nil
	local advance = mv.advance or (kick and 1.6 or 1.0)
	local late = mv.late
	if late == nil then
		late = kick
	end
	local adv0 = late and T[3] * 0.85 or T[2] * 0.5
	local adv1 = late and T[4] + 0.06 or T[3] + 0.07
	return { length = T[1], fadeIn = 0.05, fadeOut = kind == "heavy" and 0.22 or 0.16,
		advance = advance, adv0 = adv0, adv1 = adv1,
		limb = (spin ~= 0 or flip ~= 0) and "All" or mv.limb, heavy = kind == "heavy", tricky = spin ~= 0 or flip ~= 0 or hop > 0.5, keys = {
			{ t = T[2], ease = { "Sine", "Out" }, pose = pw }, -- big anticipation
			{ t = T[3], ease = { "Exponential", "Out" }, pose = ph }, -- the strike snaps out
			{ t = T[3] + 0.05, ease = { "Quad", "Out" }, pose = po }, -- overshoot
			{ t = T[4], ease = { "Back", "Out" }, pose = pr }, -- settle back into the stance
		} }
end

-- MOVE LIBRARY (right side) -----------------------------------------------------------------------------
local M = {}
local function arm(name, limb, wind, hit)
	M[name] = { limb = limb, wind = wind, hit = hit }
end
arm("jab", "Right", { RightShoulder = { 50, 0, 10 }, RightElbow = { 100, 0, 0 }, Waist = { 0, 10, 0 } },
	merge({ RightShoulder = { 88, 0, -4 }, RightElbow = { 4, 0, 0 }, Waist = { -4, -14, 0 } }, R(0, -0.15)))
arm("cross", "Right", merge({ RightShoulder = { 40, 0, 15 }, RightElbow = { 115, 0, 0 }, Waist = { 0, 18, 0 } }, R(0, 0.1, 0, 8)),
	merge({ RightShoulder = { 90, 0, -8 }, RightElbow = { 0, 0, 0 }, Waist = { -8, -28, 0 } }, R(-0.1, -0.3, 0, -10)))
arm("hook", "Right", { RightShoulder = { 75, 0, 70 }, RightElbow = { 85, 0, 0 }, Waist = { 0, 25, 0 } },
	merge({ RightShoulder = { 82, 0, -20 }, RightElbow = { 80, 0, 0 }, Waist = { -6, -32, 0 } }, R(-0.1, -0.15, 0, -12)))
arm("uppercut", "Right", merge({ RightShoulder = { -15, 0, 15 }, RightElbow = { 120, 0, 0 }, Waist = { -10, 15, 0 } }, R(-0.4)),
	merge({ RightShoulder = { 150, 0, -10 }, RightElbow = { 55, 0, 0 }, Waist = { 8, -15, 0 }, Neck = { 8, 0, 0 } }, R(0.2, -0.1)))
arm("backfist", "Right", { RightShoulder = { 70, 0, -55 }, RightElbow = { 110, 0, 0 }, Waist = { 0, 22, 0 } },
	{ RightShoulder = { 85, 0, 28 }, RightElbow = { 12, 0, 0 }, Waist = { -2, -18, 0 } })
arm("palm", "Right", merge({ RightShoulder = { 30, 0, 10 }, RightElbow = { 120, 0, 0 }, RightWrist = { 0, 0, 0 }, Waist = { 0, 14, 0 } }, R(-0.2, 0.15)),
	merge({ RightShoulder = { 92, 0, 0 }, RightElbow = { 0, 0, 0 }, RightWrist = { -65, 0, 0 }, Waist = { -8, -10, 0 } }, R(-0.25, -0.35)))
arm("chop", "Right", { RightShoulder = { 140, 0, 40 }, RightElbow = { 50, 0, 0 }, RightWrist = { -10, 0, 0 }, Waist = { 0, 20, 0 } },
	{ RightShoulder = { 45, 0, -50 }, RightElbow = { 5, 0, 0 }, RightWrist = { -10, 0, 0 }, Waist = { -10, -25, 0 } })
arm("claw", "Right", { RightShoulder = { 150, 0, 60 }, RightElbow = { 70, 0, 0 }, RightWrist = { 30, 0, 0 }, Waist = { -2, 25, 0 } },
	merge({ RightShoulder = { 30, 0, -45 }, RightElbow = { 30, 0, 0 }, RightWrist = { 30, 0, 0 }, Waist = { -18, -25, 0 } }, R(-0.15, -0.15)))
arm("hammer", "Right", merge({ RightShoulder = { 175, 0, 20 }, RightElbow = { 90, 0, 0 }, Waist = { 14, 20, 0 }, Neck = { -8, 0, 0 } }, R(0.15, 0.15)),
	merge({ RightShoulder = { 40, 0, -10 }, RightElbow = { 15, 0, 0 }, Waist = { -26, -15, 0 }, Neck = { -14, 0, 0 } }, R(-0.45, -0.3)))
-- kicks
arm("frontKick", "RightFoot", { RightHip = { 70, 0, 0 }, RightKnee = { -100, 0, 0 }, LeftKnee = { -15, 0, 0 }, Waist = { 6, 0, 0 } },
	merge({ RightHip = { 95, 0, 0 }, RightKnee = { -5, 0, 0 }, RightAnkle = { -20, 0, 0 }, LeftKnee = { -10, 0, 0 }, Waist = { 12, 0, 0 } }, R(0.05, 0.1)))
arm("roundhouse", "RightFoot", merge({ RightHip = { 40, 0, 30 }, RightKnee = { -90, 0, 0 }, LeftKnee = { -20, 0, 0 }, Waist = { 6, -20, 0 } }, R(0.1, 0, 0, -15)),
	merge({ RightHip = { 75, 0, 55 }, RightKnee = { -8, 0, 0 }, LeftHip = { -10, 0, 0 }, LeftKnee = { -12, 0, 0 }, Waist = { 10, 30, 0 } }, R(0.2, 0, 0, 25)))
arm("sideKick", "RightFoot", merge({ RightHip = { 50, 0, 40 }, RightKnee = { -110, 0, 0 }, LeftKnee = { -18, 0, 0 }, Waist = { 0, -20, 0 } }, R(0.05, 0, 0, 55)),
	merge({ RightHip = { 20, 0, 85 }, RightKnee = { -5, 0, 0 }, LeftKnee = { -14, 0, 0 }, Waist = { -6, -30, 0 } }, R(0.1, 0, 0, 75)))
arm("knee", "RightFoot", { RightHip = { 40, 0, 0 }, RightKnee = { -70, 0, 0 }, RightShoulder = { 120, 0, 20 }, LeftShoulder = { 120, 0, -20 },
	RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 } },
	merge({ RightHip = { 105, 0, 0 }, RightKnee = { -125, 0, 0 }, RightShoulder = { 85, 0, -15 }, LeftShoulder = { 85, 0, 15 }, RightElbow = { 75, 0, 0 },
		LeftElbow = { 75, 0, 0 }, Waist = { -14, 0, 0 } }, R(0.15, -0.15)))
arm("sweep", "RightFoot", merge({ Waist = { -8, 35, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -80, 0, 0 } }, R(-0.5, 0, 0, 20)),
	merge({ RightHip = { 50, 0, 70 }, RightKnee = { -5, 0, 0 }, LeftHip = { 45, 0, 0 }, LeftKnee = { -85, 0, 0 }, Waist = { -12, -30, 0 } }, R(-0.5, 0, 0, -30)))
arm("spinHook", "RightFoot", merge({ RightHip = { 30, 0, 20 }, RightKnee = { -60, 0, 0 }, Waist = { 0, -40, 0 } }, R(0, 0, 0, -45)),
	merge({ RightHip = { 70, 0, 60 }, RightKnee = { -15, 0, 0 }, LeftKnee = { -15, 0, 0 }, Waist = { 10, 30, 0 } }, R(0.15, 0, 0, 45)))
-- the two finisher variants
arm("launcher", "RightFoot", merge({ RightHip = { 10, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftHip = { 35, 0, 0 }, LeftKnee = { -70, 0, 0 }, Waist = { -14, 0, 0 },
	RightShoulder = { 30, 0, 30 }, LeftShoulder = { 30, 0, -30 } }, R(-0.45, 0.1)),
	merge({ RightHip = { 150, 0, 0 }, RightKnee = { -5, 0, 0 }, RightAnkle = { -30, 0, 0 }, LeftKnee = { -10, 0, 0 }, Waist = { 18, 0, 0 },
		RightShoulder = { -25, 0, 40 }, LeftShoulder = { -25, 0, -40 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 } }, R(0.4, 0)))
arm("axeKick", "RightFoot", merge({ RightHip = { 150, 0, 10 }, RightKnee = { -10, 0, 0 }, LeftKnee = { -20, 0, 0 }, Waist = { 14, 0, 0 } }, R(0.3, 0.1)),
	merge({ RightHip = { 35, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftHip = { 25, 0, 0 }, LeftKnee = { -35, 0, 0 }, Waist = { -22, 0, 0 } }, R(-0.3, -0.2)))

-- the flamboyant ones: spinning kicks, a backflip launcher, leaping knees / uppercuts / axe kick / hammer
M.roundhouse.spin = 360
M.spinHook.spin = -360
M.sweep.spin = 360
M.sideKick.hop = 0.5
M.knee.hop = 1.1
M.uppercut.hop = 0.9
M.axeKick.hop = 1.4
M.hammer.hop = 0.9
M.launcher.flip = -360
M.launcher.hop = 1.3
M.frontKick.hop = 0.35

-- studs each move carries the body forward (root motion)
for name, d in pairs({ jab = 0.8, cross = 1.3, hook = 1.0, uppercut = 1.2, backfist = 0.7, palm = 1.5, chop = 1.0, claw = 1.1, hammer = 1.7,
	frontKick = 1.5, roundhouse = 2.4, sideKick = 1.9, knee = 1.7, sweep = 1.3, spinHook = 2.1, launcher = 0.6, axeKick = 2.0 }) do
	M[name].advance = d
end
M.knee.late = false -- a knee drives in with the strike

local function L(name) -- the left-side version of a library move
	local m = M[name]
	return { limb = (string.gsub(m.limb, "Right", "Left")), wind = mirror(m.wind), hit = mirror(m.hit), spin = m.spin and -m.spin,
		flip = m.flip, hop = m.hop, advance = m.advance, late = m.late }
end
local function both(wind, hit, extra) -- a custom two-handed move
	local m = { limb = "Both", wind = wind, hit = hit }
	for k, v in pairs(extra or {}) do
		m[k] = v
	end
	return m
end

-- STYLES ------------------------------------------------------------------------------------------------
local BENT = { RightHip = { 14, 0, 8 }, RightKnee = { -24, 0, 0 }, LeftHip = { -6, 0, -8 }, LeftKnee = { -18, 0, 0 } }
local GUARD_L = { LeftShoulder = { 55, 0, 90 }, LeftElbow = { 95, 0, 0 } }
local GUARD_R = { RightShoulder = { 55, 0, -90 }, RightElbow = { 95, 0, 0 } }
local GUARD = merge(GUARD_L, GUARD_R)
local LOW = { RightShoulder = { 30, 0, 20 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 30, 0, -20 }, LeftElbow = { 70, 0, 0 } }
local BAL = { RightShoulder = { 20, 0, 35 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 20, 0, -35 }, LeftElbow = { 40, 0, 0 } }
local POCKET = { LeftShoulder = { -12, 0, -6 }, LeftElbow = { 35, 0, 0 } }

-- string = { move1..move5 }, base = stance + resting arms; kinds are light, light, mid, mid, heavy
local function style(base, moves, fin)
	local s = {}
	for i, mv in ipairs(moves) do
		s[i] = clip((i <= 2) and "light" or (i <= 4) and "mid" or "heavy", base, mv)
	end
	s.launch = clip("heavy", base, fin and fin.launch or M.launcher)
	s.slam = clip("heavy", base, fin and fin.slam or M.axeKick)
	return s
end

local P = {}
-- GOJO: unbothered, left hand in the pocket - jab, backfist, a lazy side kick, palm shove, roundhouse
P.Limitless = style(POCKET, { M.jab, M.backfist, M.sideKick, M.palm, M.roundhouse })
-- NARUTO: scrappy - hooks both sides, front kick, uppercut, then a two-fisted hammer smash
P.Vulpine = style(merge(BENT, LOW), { L("hook"), M.hook, M.frontKick, M.uppercut,
	both(merge({ RightShoulder = { 170, 0, 10 }, LeftShoulder = { 170, 0, -10 }, RightElbow = { 40, 0, 0 }, LeftElbow = { 40, 0, 0 }, Waist = { 14, 0, 0 } }, R(0.3, 0.1)),
		merge({ RightShoulder = { 70, 0, -15 }, LeftShoulder = { 70, 0, 15 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, Waist = { -25, 0, 0 } }, R(-0.5, -0.3)),
		{ hop = 1.2, advance = 2.2 }) })
-- KILLUA: assassin - knife-hand chops both sides, spinning hook kick, flying knee, twin palm thrust
P.Godspeed = style(merge(BENT, LOW), { M.chop, L("chop"), M.spinHook, L("knee"),
	both(merge({ RightShoulder = { 20, 0, 20 }, LeftShoulder = { 20, 0, -20 }, RightElbow = { 130, 0, 0 }, LeftElbow = { 130, 0, 0 }, Waist = { 6, 0, 0 } }, R(-0.5, 0.2)),
		merge({ RightShoulder = { 90, 0, -8 }, LeftShoulder = { 90, 0, 8 }, RightElbow = { 0, 0, 0 }, LeftElbow = { 0, 0, 0 }, RightWrist = { -70, 0, 0 },
			LeftWrist = { -70, 0, 0 }, Waist = { -14, 0, 0 } }, R(-0.45, -0.45)), { spin = 360, advance = 2.6 }) })
-- DEKU: Shoot Style - front kick, side kick, roundhouse, knee, then the SMASH punch
P.OneForAll = style(BAL, { M.frontKick, L("sideKick"), M.roundhouse, L("knee"),
	{ limb = "Right", wind = merge(GUARD_L, { RightShoulder = { 20, 0, 40 }, RightElbow = { 130, 0, 0 }, Waist = { 2, 35, 0 } }, R(-0.45, 0.25, 0, 10)),
		hit = merge(GUARD_L, { RightShoulder = { 95, 0, -5 }, RightElbow = { 0, 0, 0 }, Waist = { -14, -30, 0 } }, R(-0.35, -0.45, 0, -10)), advance = 2.8 } })
-- SASUKE: crisp taijutsu - jab, cross, left roundhouse, low sweep, lunging thrust
P.Tempest = style(merge(BENT, GUARD), { L("jab"), M.cross, L("roundhouse"), M.sweep,
	{ limb = "Right", wind = merge({ RightShoulder = { -30, 0, 30 }, RightElbow = { 60, 0, 0 }, RightWrist = { 20, 0, 0 }, LeftShoulder = { 60, 0, -60 },
		LeftElbow = { 80, 0, 0 }, Waist = { 10, 30, 0 } }, R(-0.55, 0.25)),
		hit = merge({ RightShoulder = { 92, 0, -4 }, RightElbow = { 0, 0, 0 }, RightWrist = { -30, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 20, 0, 0 },
			Waist = { -16, -20, 0 } }, R(-0.5, -0.45)), advance = 3.0 } })
-- SUKUNA: cruel claws - rake, rake, stomp kick, X-cross slash, overhead hammer-fist
P.Carver = style(merge(BENT, LOW), { M.claw, L("claw"), M.frontKick,
	both({ RightShoulder = { 150, 0, 40 }, LeftShoulder = { 150, 0, -40 }, RightElbow = { 60, 0, 0 }, LeftElbow = { 60, 0, 0 }, Waist = { 10, 0, 0 } },
		merge({ RightShoulder = { 40, 0, -60 }, LeftShoulder = { 40, 0, 60 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, Waist = { -20, 0, 0 } }, R(-0.3, -0.2)),
		{ hop = 0.8, advance = 1.4 }),
	M.hammer })
-- EREN: twin blades (2026-11-09, was a street-fighting punch string). The gear (ShifterServer.TitanSkins.gear) puts a
-- sword in each fist pointing out of the knuckles: forward with the arm hanging, so the blade's elevation is about
-- shoulder + elbow + wrist flexion. Diagonal cut, the same from the left, a spinning double slash, an X-cross cut,
-- then a leaping two-blade cleave; the finishers are a rising double slash (launch) and a plunging stab (slam).
-- .blade tells GojoClient.playPunch to light the swords' own trails instead of the fist whoosh.
local BLADES = { RightShoulder = { 15, 0, 18 }, RightElbow = { 25, 0, 0 }, LeftShoulder = { 15, 0, -18 }, LeftElbow = { 25, 0, 0 } }
M.slash = { limb = "Right", advance = 1.2,
	wind = merge({ RightShoulder = { 150, 0, 45 }, RightElbow = { 60, 0, 0 }, RightWrist = { 20, 0, 0 }, Waist = { 4, 28, 0 } }, R(0, 0.1, 0, 8)),
	hit = merge({ RightShoulder = { 50, 0, -45 }, RightElbow = { 8, 0, 0 }, RightWrist = { -55, 0, 0 }, Waist = { -12, -30, 0 } }, R(-0.15, -0.25, 0, -10)) }
P.Shifter = style(merge(BENT, BLADES), { M.slash, L("slash"),
	both({ RightShoulder = { 45, 0, -45 }, LeftShoulder = { 45, 0, -75 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 40, 0, 0 }, Waist = { 0, 35, 0 } },
		merge({ RightShoulder = { 35, 0, 80 }, LeftShoulder = { 35, 0, -80 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 }, RightWrist = { -30, 0, 0 },
			LeftWrist = { -30, 0, 0 }, Waist = { -6, -20, 0 } }, R(-0.2, -0.1)), { spin = 360, advance = 2.0 }),
	both({ RightShoulder = { 150, 0, -25 }, LeftShoulder = { 150, 0, 25 }, RightElbow = { 50, 0, 0 }, LeftElbow = { 50, 0, 0 }, RightWrist = { 20, 0, 0 },
		LeftWrist = { 20, 0, 0 }, Waist = { 10, 0, 0 } },
		merge({ RightShoulder = { 40, 0, 50 }, LeftShoulder = { 40, 0, -50 }, RightElbow = { 8, 0, 0 }, LeftElbow = { 8, 0, 0 }, RightWrist = { -50, 0, 0 },
			LeftWrist = { -50, 0, 0 }, Waist = { -20, 0, 0 } }, R(-0.3, -0.2)), { hop = 0.6, advance = 1.4 }),
	both(merge({ RightShoulder = { 175, 0, 10 }, LeftShoulder = { 175, 0, -10 }, RightElbow = { 70, 0, 0 }, LeftElbow = { 70, 0, 0 }, RightWrist = { 30, 0, 0 },
		LeftWrist = { 30, 0, 0 }, Waist = { 16, 0, 0 }, Neck = { -8, 0, 0 } }, R(0.3, 0.1)),
		merge({ RightShoulder = { 45, 0, -8 }, LeftShoulder = { 45, 0, 8 }, RightElbow = { 5, 0, 0 }, LeftElbow = { 5, 0, 0 }, RightWrist = { -60, 0, 0 },
			LeftWrist = { -60, 0, 0 }, Waist = { -28, 0, 0 }, Neck = { -12, 0, 0 } }, R(-0.5, -0.35)), { hop = 1.3, advance = 2.4 }) },
	{ launch = both(merge({ RightShoulder = { -30, 0, 25 }, LeftShoulder = { -30, 0, -25 }, RightElbow = { 20, 0, 0 }, LeftElbow = { 20, 0, 0 }, RightWrist = { -20, 0, 0 },
			LeftWrist = { -20, 0, 0 }, Waist = { -18, 0, 0 } }, R(-0.5, 0.1)),
			merge({ RightShoulder = { 165, 0, 15 }, LeftShoulder = { 165, 0, -15 }, RightElbow = { 15, 0, 0 }, LeftElbow = { 15, 0, 0 }, RightWrist = { 10, 0, 0 },
				LeftWrist = { 10, 0, 0 }, Waist = { 16, 0, 0 }, Neck = { 10, 0, 0 } }, R(0.4, 0)), { hop = 1.3, advance = 0.6 }),
		slam = both(merge({ RightShoulder = { 175, 0, 10 }, LeftShoulder = { 175, 0, -10 }, RightElbow = { 80, 0, 0 }, LeftElbow = { 80, 0, 0 }, RightWrist = { 30, 0, 0 },
			LeftWrist = { 30, 0, 0 }, Waist = { 14, 0, 0 } }, R(0.3, 0.1)),
			merge({ RightShoulder = { 30, 0, -5 }, LeftShoulder = { 30, 0, 5 }, RightElbow = { 10, 0, 0 }, LeftElbow = { 10, 0, 0 }, RightWrist = { -75, 0, 0 },
				LeftWrist = { -75, 0, 0 }, Waist = { -30, 0, 0 } }, R(-0.4, -0.2)), { hop = 1.4, advance = 2.0 }) })
P.Shifter.blade = true

P.moves = M -- (for debugging / other kits)
return P
