--!nocheck
-- HitReact (2026-11-06): hit reactions for NPC bodies - every kit, every hit.
--
-- A body that is hit while it is still on its feet (or held up by a move - a cinematic) plays a procedural flinch on
-- every client: it snaps away from the blow, arches back, the head whips, the arms fly and a foot steps back, then it
-- recovers. Bodies that are ragdolled react through physics instead (RagdollService runs loose joints and whiplash
-- flings), so the clip never plays on a ragdoll.
--
-- Two ways to trigger it:
--   * nothing: HitReactClient watches every RagdollNPC-tagged humanoid's health; a drop plays a flinch pushed away
--     from the attacker (LastHitBy, else the nearest player) and sized by the damage. HitReactServer adds a small
--     physical shove to a standing, unheld body.
--   * explicit, from server code that wants a specific look (Ichigo's M1):
--       HitReact.mark(model, pushDir, power, style)   -- replicates through attributes; suppresses the generic one
--     style: nil/"flinch" (bend away), "twist" (a sideways cut spins the chest away), "fold" (doubled over / driven
--     down), "lift" (a rising hit: up on the toes, head thrown back). power ~0.4 (graze) .. 1.6 (huge).
-- Client side: HitReact.play(model, pushDir, power, style) plays it locally (HitReactClient calls this).
local RunService = game:GetService("RunService")

local HitReact = {}

local FLAT = Vector3.new(1, 0, 1)

function HitReact.mark(model, dir, power, style, noShove)
	if not model or not model.Parent then
		return
	end
	if typeof(dir) == "Vector3" and dir == dir then
		local f = dir * FLAT
		if f.Magnitude > 1e-3 then
			model:SetAttribute("HitDir", Vector3.new(f.Unit.X, math.clamp(dir.Unit.Y, -1, 1), f.Unit.Z))
		end
	end
	model:SetAttribute("HitPower", math.clamp(tonumber(power) or 1, 0.1, 2))
	model:SetAttribute("HitStyle", type(style) == "string" and style or "")
	model:SetAttribute("HitSeq", (model:GetAttribute("HitSeq") or 0) + 1)
end

-- server: slide a STANDING body `dist` studs along `dir` over `dur` seconds. A plain HRP velocity is eaten by the
-- humanoid's ground control in a frame or two (measured: 14 studs/s moved a stunned dummy 0.1 studs), so a short
-- line-constrained LinearVelocity carries it instead; gravity and the other axes stay free.
function HitReact.slide(model, dir, dist, dur)
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp or hrp.Anchored or typeof(dir) ~= "Vector3" or dir ~= dir then
		return
	end
	local f = dir * FLAT
	if f.Magnitude < 1e-3 or not dist or dist <= 0 then
		return
	end
	dur = dur or 0.14
	local old = hrp:FindFirstChild("HitReactSlide")
	if old then
		old:Destroy()
	end
	local att = hrp:FindFirstChild("HitReactAtt") or Instance.new("Attachment")
	att.Name = "HitReactAtt"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Name = "HitReactSlide"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	lv.LineDirection = f.Unit
	lv.LineVelocity = dist / dur
	lv.MaxForce = 1e5
	lv.Parent = hrp
	task.delay(dur, function()
		if lv.Parent then
			lv:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- client: the flinch clip, built per hit in the body's own frame
local PA
local active = setmetatable({}, { __mode = "k" })
local rng = Random.new()

local JOINTS = {
	"Root", "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist",
	"RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle",
}

local function scaled(pose, k, kHead)
	local out = {}
	for name, v in pairs(pose) do
		local m = (name == "Neck" and kHead) or k
		local t = { (v[1] or 0) * m, (v[2] or 0) * m, (v[3] or 0) * m }
		if v.pos then
			t.pos = v.pos * m
		end
		out[name] = t
	end
	return out
end

local function zero()
	local out = {}
	for _, n in ipairs(JOINTS) do
		out[n] = { 0, 0, 0 }
	end
	out.Root.pos = Vector3.zero
	return out
end

local function add(pose, name, x, y, z, pos)
	local v = pose[name]
	v[1], v[2], v[3] = v[1] + (x or 0), v[2] + (y or 0), v[3] + (z or 0)
	if pos then
		v.pos = (v.pos or Vector3.zero) + pos
	end
end

-- b = pushed backward (+) / forward (-), s = pushed to its right (+) / left (-), u = upward share, p = power
local function peakPose(style, b, s, u, p)
	local P = zero()
	local sgn = s >= 0 and 1 or -1
	local side = math.abs(s)
	local jit = function(a)
		return rng:NextNumber(-a, a)
	end
	-- the common core: the chest takes the blow and bends away, the head whips, the arms trail and fly out
	add(P, "Root", 6 * b * p, 0, -7 * s * p, Vector3.new(0.55 * s * p, -0.18 * p, 0.8 * b * p))
	add(P, "Waist", 18 * b * p, jit(6), -15 * s * p)
	add(P, "Neck", 26 * b * p + 14 * u * p, jit(10), -14 * s * p)
	add(P, "RightShoulder", (30 + 22 * b) * p, 0, (24 + 14 * s) * p)
	add(P, "LeftShoulder", (30 + 22 * b) * p, 0, -(24 - 14 * s) * p)
	add(P, "RightElbow", 38 * p + jit(10), 0, 0)
	add(P, "LeftElbow", 38 * p + jit(10), 0, 0)
	add(P, "RightWrist", -18 * p, 0, 0)
	add(P, "LeftWrist", -18 * p, 0, 0)
	-- a stumble: one foot steps back under the lean, the other knee gives
	local back = (b >= 0) == (rng:NextNumber() < 0.5)
	local st, other = back and "Right" or "Left", back and "Left" or "Right"
	add(P, st .. "Hip", -18 * b * p, 0, 0)
	add(P, st .. "Knee", -30 * p, 0, 0)
	add(P, st .. "Ankle", 16 * p, 0, 0)
	add(P, other .. "Hip", 10 * b * p, 0, 0)
	add(P, other .. "Knee", -14 * p, 0, 0)
	if style == "twist" then
		-- a sideways cut: the whole upper body spins away from it, the arms are flung round after it
		local k = math.min((0.6 + side) * p, 1.3)
		add(P, "Root", 0, -16 * sgn * k, -6 * s * p)
		add(P, "Waist", 4 * p, -32 * sgn * k, -10 * s * p)
		add(P, "Neck", 6 * p, -26 * sgn * k, -10 * s * p)
		add(P, sgn > 0 and "LeftShoulder" or "RightShoulder", 35 * p, 0, (sgn > 0 and -40 or 40) * p)
		add(P, sgn > 0 and "RightShoulder" or "LeftShoulder", -30 * p, 0, (sgn > 0 and 30 or -30) * p)
	elseif style == "fold" then
		-- doubled over / driven down: fold at the waist, both knees buckle, the head drops
		P.Waist[1] = -38 * p
		P.Neck[1] = -22 * p
		P.Root[1] = -8 * p
		P.Root.pos = Vector3.new(0.3 * s * p, -0.75 * p, 0.35 * b * p)
		for _, sd in ipairs({ "Right", "Left" }) do
			P[sd .. "Hip"] = { 42 * p, 0, (sd == "Right" and 6 or -6) * p }
			P[sd .. "Knee"] = { -62 * p, 0, 0 }
			P[sd .. "Ankle"] = { 22 * p, 0, 0 }
			P[sd .. "Shoulder"] = { 48 * p, 0, (sd == "Right" and 14 or -14) * p }
			P[sd .. "Elbow"] = { 55 * p, 0, 0 }
		end
	elseif style == "lift" then
		-- a rising hit: thrown up onto the toes, arched back, head thrown back, arms flung up
		add(P, "Root", 6 * p, 0, 0, Vector3.new(0, 0.35 * p, 0))
		add(P, "Waist", 14 * p, 0, 0)
		add(P, "Neck", 20 * p, 0, 0)
		add(P, "RightShoulder", 60 * p, 0, 30 * p)
		add(P, "LeftShoulder", 60 * p, 0, -30 * p)
		add(P, "RightAnkle", -24 * p, 0, 0)
		add(P, "LeftAnkle", -24 * p, 0, 0)
	end
	-- keep it human: clamp the big joints
	P.Waist[1] = math.clamp(P.Waist[1], -45, 34)
	P.Neck[1] = math.clamp(P.Neck[1], -35, 48)
	for _, n in ipairs({ "RightKnee", "LeftKnee" }) do
		P[n][1] = math.clamp(P[n][1], -80, 0)
	end
	for _, n in ipairs({ "RightElbow", "LeftElbow" }) do
		P[n][1] = math.clamp(P[n][1], 0, 110)
	end
	return P
end

local function buildClip(style, b, s, u, p)
	local P = peakPose(style, b, s, u, p)
	local fold = style == "fold"
	local len = (fold and 0.95 or 0.66) * (0.85 + 0.2 * math.min(p, 1.5))
	return {
		length = len,
		fadeIn = 0.02,
		fadeOut = 0.14,
		keys = {
			{ t = 0, pose = zero() },
			{ t = 0.065, ease = { "Quad", "Out" }, pose = P }, -- the snap
			{ t = 0.14, ease = { "Sine", "Out" }, pose = scaled(P, 1.06, 1.14) }, -- the head and arms keep going
			{ t = len * (fold and 0.55 or 0.48), ease = { "Quad", "InOut" }, pose = scaled(P, fold and 0.75 or 0.42, fold and 0.7 or 0.36) },
			{ t = len, ease = { "Quad", "InOut" }, pose = zero() },
		},
	}
end

-- push = world direction the body is knocked (away from the attacker); power ~0.4..1.6
function HitReact.play(model, push, power, style)
	if not RunService:IsClient() then
		return nil
	end
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if not hrp or model:GetAttribute("Ragdolled") or model:GetAttribute("Dead") then
		return nil
	end
	if not PA then
		local ok, m = pcall(require, script.Parent:WaitForChild("Client"):WaitForChild("ProceduralAnimator"))
		if not ok then
			return nil
		end
		PA = m
	end
	if typeof(push) ~= "Vector3" or push ~= push or (push * FLAT).Magnitude < 1e-3 then
		push = -hrp.CFrame.LookVector
	end
	local f = (push * FLAT).Unit
	local lp = hrp.CFrame:VectorToObjectSpace(f)
	local b, s = lp.Z, lp.X
	local u = math.clamp(push.Unit.Y, 0, 1)
	local p = math.clamp(tonumber(power) or 1, 0.25, 1.8)
	local prev = active[model]
	if prev and prev:isPlaying() then
		prev:stop(0.06)
	end
	local st = (style == "twist" or style == "fold" or style == "lift") and style or nil
	local ok, track = pcall(PA.play, model, buildClip(st, b, s, u, p))
	if ok and track then
		active[model] = track
		return track
	end
	return nil
end

return HitReact
