--!nocheck
-- ProceduralAnimator: plays keyframed poses on R15 rigs by writing joint .Transform every RunService.Stepped
-- (PreSimulation - the only point where a write beats the Animator on constraint rigs). Works for
-- AnimationConstraint rigs and Motor6D rigs alike. Joints a clip does not name keep their normal animation.
--
-- clip = { length, fadeIn?, fadeOut?, keys = { { t, ease = {"Quad","Out"}, pose = { Joint = {x,y,z, pos = Vector3?} } } } }
-- angles are degrees for CFrame.Angles(rad(x), rad(y), rad(z)); pos only makes sense on Root.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ProceduralAnimator = {}

local JOINTS = {
	Root = true, Waist = true, Neck = true, LeftShoulder = true, RightShoulder = true, LeftElbow = true,
	RightElbow = true, LeftWrist = true, RightWrist = true, LeftHip = true, RightHip = true, LeftKnee = true,
	RightKnee = true, LeftAnkle = true, RightAnkle = true,
	SwordGrip = true, -- a held weapon's Motor6D (RightHand -> Handle), e.g. Ichigo's Zangetsu
}

local chars = {} -- [character] = { joints = {}, tracks = {} }
local conn

local function findJoints(character)
	local joints = {}
	for _, d in ipairs(character:GetDescendants()) do
		if (d:IsA("AnimationConstraint") or d:IsA("Motor6D")) and JOINTS[d.Name] then
			joints[d.Name] = d
		end
	end
	return joints
end

local function toCF(v)
	if typeof(v) == "CFrame" then
		return v
	end
	local cf = CFrame.Angles(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
	if v.pos then
		cf = CFrame.new(v.pos) * cf
	end
	return cf
end

local function compile(clip)
	if clip._compiled then
		return clip._compiled
	end
	local perJoint = {}
	for _, key in ipairs(clip.keys) do
		local okS, style = pcall(function()
			return Enum.EasingStyle[(key.ease and key.ease[1]) or "Quad"]
		end)
		local okD, dir = pcall(function()
			return Enum.EasingDirection[(key.ease and key.ease[2]) or "Out"]
		end)
		style = okS and style or Enum.EasingStyle.Quad
		dir = okD and dir or Enum.EasingDirection.Out
		for name, v in pairs(key.pose) do
			perJoint[name] = perJoint[name] or {}
			table.insert(perJoint[name], { t = key.t, cf = toCF(v), style = style, dir = dir })
		end
	end
	for _, list in pairs(perJoint) do
		table.sort(list, function(a, b)
			return a.t < b.t
		end)
	end
	clip._compiled = perJoint
	return perJoint
end

local function sample(list, t)
	local n = #list
	if t <= list[1].t then
		return list[1].cf
	end
	if t >= list[n].t then
		return list[n].cf
	end
	for i = 1, n - 1 do
		local k1 = list[i + 1]
		if t < k1.t then
			local k0 = list[i]
			local a = TweenService:GetValue((t - k0.t) / (k1.t - k0.t), k1.style, k1.dir)
			return k0.cf:Lerp(k1.cf, a)
		end
	end
	return list[n].cf
end

local Track = {}
Track.__index = Track

function Track:stop(fade)
	if self.ended or self.stopping then
		return
	end
	self.stopping = true
	self.stopFade = math.max(fade or 0.2, 1e-3)
	self.stopStart = self.time
end

function Track:isPlaying()
	return not self.ended
end

function Track:setTime(t)
	self.time = t
end

local function smooth(w)
	return w * w * (3 - 2 * w)
end

local function weight(tr)
	local clip = tr.clip
	local w = 1
	local fin, fout = clip.fadeIn or 0.12, clip.fadeOut or 0.25
	if fin > 0 then
		w = math.min(w, (tr.time - tr.t0) / fin)
	end
	if fout > 0 then
		w = math.min(w, (clip.length - tr.time) / fout)
	end
	if tr.stopping then
		w = math.min(w, 1 - (tr.time - tr.stopStart) / tr.stopFade)
	end
	return smooth(math.clamp(w, 0, 1))
end

local function finish(tr)
	if tr.ended then
		return
	end
	tr.ended = true
	if tr.onEnd then
		task.spawn(tr.onEnd)
	end
end

local function step(_, dt)
	for character, entry in pairs(chars) do
		if not character.Parent then
			for _, tr in ipairs(entry.tracks) do
				finish(tr)
			end
			chars[character] = nil
		else
			local pose = {}
			local i = 1
			while i <= #entry.tracks do
				local tr = entry.tracks[i]
				tr.time += dt * tr.speed
				local done = tr.time >= tr.clip.length or (tr.stopping and tr.time - tr.stopStart >= tr.stopFade)
				if done then
					table.remove(entry.tracks, i)
					finish(tr)
				else
					local w = weight(tr)
					for name, list in pairs(tr.compiled) do
						local base = pose[name] or tr.blendFrom[name] or CFrame.identity
						pose[name] = base:Lerp(sample(list, tr.time), w)
					end
					i += 1
				end
			end
			entry.last = entry.last or {}
			for name, cf in pairs(pose) do
				local j = entry.joints[name]
				if j and j.Parent then
					j.Transform = cf
					entry.last[name] = cf
				end
			end
			entry.controlled = pose -- read by AnimeRun so the run never fights a clip
			if #entry.tracks == 0 then
				-- a finished clip must not leave its last pose behind. A joint no default animation drives (a giant
				-- form's Root) kept it, and Model:ScaleTo then scaled the leftover offset - the Shifter's Kneel left
				-- -1.3 studs on the Root that became -18 on the Colossal Titan, sinking it into the street. So every
				-- joint still holding what this animator last wrote goes back to rest (animated joints were already
				-- overwritten by their tracks this frame and are left alone).
				for name, cf in pairs(entry.last) do
					local j = entry.joints[name]
					if j and j.Parent and j.Transform == cf then
						j.Transform = CFrame.identity
					end
				end
				chars[character] = nil
			end
		end
	end
	if next(chars) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- opts: { startAt = seconds, speed = 1, onEnd = function }
function ProceduralAnimator.play(character, clip, opts)
	opts = opts or {}
	local entry = chars[character]
	if not entry then
		entry = { joints = findJoints(character), tracks = {} }
		chars[character] = entry
	end
	local start = math.max(opts.startAt or 0, 0)
	local track = setmetatable({
		clip = clip, compiled = compile(clip), time = start, t0 = start, speed = opts.speed or 1,
		onEnd = opts.onEnd, blendFrom = {}, ended = false,
	}, Track)
	for name in pairs(track.compiled) do
		local j = entry.joints[name]
		if j then
			track.blendFrom[name] = j.Transform
		end
	end
	table.insert(entry.tracks, track)
	if not conn then
		conn = RunService.Stepped:Connect(step)
	end
	return track
end

-- the joints a clip is driving on this character right now (nil when none): AnimeRun leaves these alone
function ProceduralAnimator.controlled(character)
	local e = chars[character]
	return e and e.controlled
end

function ProceduralAnimator.stopAll(character, fade)
	local entry = chars[character]
	if entry then
		for _, tr in ipairs(entry.tracks) do
			tr:stop(fade)
		end
	end
end

return ProceduralAnimator
