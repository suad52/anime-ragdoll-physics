--!nocheck
-- ServerScriptService.Sandbox.Wanderers (2026-11-13): the owner asked for "a bunch of dummies just walking around the
-- place and doing random stuff". COUNT ordinary dummies (same rig, injuries, ragdoll and speech as every other - they
-- carry the attribute Wanderer) stroll the map on PathfindingService routes and, between walks, pick something to do:
--   stroll / jog somewhere - go and look at a machine (and remark on it) - wave at a player who is close - follow a
--   player about for a bit - stop and chat with another wanderer - dance, cheer, laugh - lie down for a nap - walk up
--   to one of the machines' red buttons and PRESS it ("What does this button do?")
-- They are not protected from anything - a wanderer that strolls onto the track when the train is due is the
-- train's. Dead ones are replaced out of sight, so the crowd stays at COUNT.
--
-- FRIGHT (same day): the owner asked for "actual reactions" - calm until they SEE harm, then shock, then panic.
--   * Injury.onHarm / Hazards.onPropHarm / Hazards.onBlast report every hurt dummy, hit prop and explosion. Every
--     0.2 s the reports are swept: a dummy in range, with a clear line to it and not looking the other way, saw it.
--   * A witness stops dead and SHOCKS (pose shockFace / shockHead / shockMouth: hands to the face, hands behind the
--     head, legs dropped into a horse stance), then decides: COWER where it is (the player is on top of it), back
--     away with its hands up and LEAVE (a small thing, or a machine did it), or PANIC.
--   * PANIC is slow on purpose - the owner: "not fast but ... really trying to make an effort to escape". 0.5-0.9 s
--     of scrambling on the spot, then 11-13 studs/s with the run cycle at 1.9x and both arms flailing, glancing
--     back, shouting, now and then tripping over. It runs until it is out of time AND 55 studs clear, stands bent
--     over panting, and stays wary of that player for 45 s (come within 14 studs and it flinches and runs again).
--   * The dummies posted at the machines (and the ones a player spawned) keep their place, but shock and cower too.
--   * The poses are DRAWN ON THE CLIENTS (StarterPlayerScripts.SandboxReactions) from the attribute React on the
--     model (+ ReactBy / ReactAt, and the tag Reacting). Nothing about a pose lives here except those attributes.
-- Studio: script.Control:Invoke("stats") -> a summary; ("act", name) makes the first idle wanderer do one thing;
-- ("fright", "shock" | "panic" | "cower" | "leave" | "pant") frightens one of the nearest player; ("pose", name).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

-- (2026-11-15, owner: "add a lot more npcs in the open area just walking around or having conversations or whatever
-- with eachother") two crowds: each wanderer belongs to one map (w.area) and only ever walks, looks and flees there.
-- THE RUINS (workspace.Arenas.Ruins) got one of its own; chats are twice as likely as before, with more to say.
local W = { COUNT = { Sandbox = 30, Ruins = 75 } } -- (2026-11-15, owner: "i want like 50 npcs in there" - the Ruins; then "make it 100"; then "from 100 to 75")
local ANIM = { walk = 507777826, run = 507767714, wave = 507770239, point = 507770453, cheer = 507770677, laugh = 507770818,
	dance1 = 507771019, dance2 = 507776043, dance3 = 507777268 }
local LOOPED = { walk = true, run = true, dance1 = true, dance2 = true, dance3 = true }
local AGENT = { AgentRadius = 2, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 8, Costs = { Water = math.huge } }
-- the buttons a wanderer may press: one-shot machines only, never a switch that stays on (the coil would empty the map)
local PRESSABLE = { "PressButton", "PlankPush", "Dispenser", "WreckSwing", "CannonFire" }
local SHOCKS = { "shockFace", "shockFace", "shockHead", "shockHead", "shockMouth" }
local SAY = {
	follow = { "Where are we going?", "I'll come with you.", "Lead the way.", "Are we there yet?", "I'm with this one." },
	press = { "What does this button do?", "Ooh. A button.", "I shouldn't. I'm going to.", "Red means push, right?" },
	pressed = { "Oops.", "Was that me?", "I regret nothing.", "Nobody saw that.", "It was like that when I got here." },
	nap = { "Just resting my eyes.", "Five minutes.", "Wake me if anything happens." },
	flee = { "RUN!", "Nope. Nope. Nope.", "Not again!", "I saw nothing!", "Every time!", "I'm out!", "GET AWAY FROM ME!" },
	bolt = { "Leave me alone!", "Help!", "Why me?!", "I just got here!", "What did I do?!" },
	greet = { "Oh, hello!", "Morning!", "Nice day for it.", "Hi there!", "You alright?" },
	chat = { "So I said, that's not my arm.", "Did you see what happened to Gary?", "They told me it was a desk job.", "I heard the rex is vegetarian.",
		"Do you ever feel watched?", "Have you tried the bounce park?", "I'm thinking of quitting.", "I don't trust that crane.",
		"My cousin works at the grinder.", "What time does the train come?", "Lovely weather for it.", "Did you get the memo?",
		"I think I left the oven on.", "Who keeps moving the dummies?", "I've been here since Tuesday.", "Is it lunch yet?",
		"I saw a guy fly earlier. Just... fly.", "My back's been funny since the trampoline.", "Do we get paid for this?", "Have you met the new guy?",
		"I had the weirdest dream.", "Don't tell anyone, but I can't swim.", "Someone stole my sandwich again.", "Rate my outfit. Honestly." },
	reply = { "No way.", "Ha! Classic.", "Tell me about it.", "You're joking.", "Typical.", "That tracks.", "Same time tomorrow?", "Don't remind me.",
		"Wait, really?", "Story of my life.", "I'd believe it.", "Mood.", "Ten out of ten.", "Not again.", "You and me both.", "Shh, they're listening." },
	-- fright
	gasp = { "WHAT?!", "Oh no.", "Did you SEE that?!", "No no no no.", "What did you DO?!", "That's not okay!", "Oh my days.", "They were just standing there!", "Why would you do that?!" },
	horror = { "THEY'RE DEAD!", "You MONSTER!", "Oh no oh no oh no.", "That was GARY!", "I'm going to be sick.", "MURDER!", "I can't look." },
	scream = { "AAAAH!", "HELP!", "SOMEBODY!", "Not me! Not me!", "Go go go go!", "My legs won't go faster!", "I'm running! I'm running!", "Don't look back!" },
	plead = { "Please don't.", "I didn't see anything!", "I have a family! Probably!", "Not the face.", "I'll be good!", "I'm just a dummy!" },
	pant = { "I think... I lost them.", "*wheeze*", "Can't... run... any more.", "Is it gone?", "Never coming back here.", "My heart..." },
	leave = { "I'm not getting involved.", "Nope. Leaving.", "I saw nothing.", "Not my business.", "Time to be somewhere else." },
	flinch = { "Stay back!", "Don't come any closer!", "Not you again!", "Keep away!" },
	trip = { "Oof!", "My ankle!", "Get up get up get up!", "No!" },
}

function W.init(ctx)
	local H, Dummies, Ragdoll, Injury = ctx.Hazards, ctx.Dummies, ctx.Ragdoll, ctx.Injury
	local Speech = require(script.Parent:WaitForChild("Speech"))
	local map = workspace:WaitForChild("Map")
	local rng = Random.new()
	local FLAT = Vector3.new(1, 0, 1)
	local function pick(t)
		return t[rng:NextInteger(1, #t)]
	end
	local function say(m, text)
		if Speech.say then
			Speech.say(m, text)
		end
	end
	local function nearestPlayer(pos)
		local best, bd, bhrp
		for _, p in ipairs(Players:GetPlayers()) do
			local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if not bd or d < bd then
					best, bd, bhrp = p, d, hrp
				end
			end
		end
		return best, bd or math.huge, bhrp
	end

	------------------------------------------------------------------------------------------- where they can go
	-- open ground: not inside a site's footprint, flat dry terrain, nothing standing on it
	local boxes, views = {}, {}
	for _, m in ipairs(map:GetChildren()) do
		if m:IsA("Model") and m.Name ~= "Scenery" and m.Name ~= "Bounds" and m.Name ~= "Spawn" then
			local ok, cf, size = pcall(function()
				return m:GetBoundingBox()
			end)
			if ok then
				table.insert(boxes, { cf = cf, half = size / 2 + Vector3.new(5, 0, 5), name = m.Name })
				-- a place to stand and look at it: by its signpost
				local posts = {}
				for _, c in ipairs(m:GetChildren()) do
					if c.Name == "SignPost" then
						table.insert(posts, c.Position)
					end
				end
				if #posts >= 2 then
					local mid = (posts[1] + posts[2]) / 2
					local out = (mid - cf.Position) * FLAT
					out = out.Magnitude > 1 and out.Unit or Vector3.zAxis
					table.insert(views, { pos = Vector3.new(mid.X, 0, mid.Z) + out * 6, look = cf.Position, name = m.Name })
				end
			end
		end
	end
	-- (2026-11-15) THE RUINS: places worth a look there too (views carry an area; a wanderer only picks its own)
	for _, v in ipairs(views) do
		v.area = "Sandbox"
	end
	local RUINS_SAY = {
		Ring = { "Who knocked these columns over?", "Fights here every night, apparently.", "This ring has seen things.", "I'm not standing in the middle." },
		Falls = { "Is that water safe to drink?", "I could look at this all day.", "Somebody fell in yesterday.", "Nice and peaceful. For once." },
		Yard = { "They train out here.", "Those dummies look nervous.", "I'm not going in there.", "Is that sand or something else?" },
	}
	local arena = workspace:FindFirstChild("Arenas") and workspace.Arenas:FindFirstChild("Ruins")
	local RC, RH = arena and arena:GetAttribute("Centre"), arena and arena:GetAttribute("Half")
	if RC and RH then
		for _, v in ipairs({ { "Ring", -32, 52, -32, 8 }, { "Falls", 104, -60, 104, -100 }, { "Yard", -94, 112, -134, 112 } }) do
			table.insert(views, { pos = RC + Vector3.new(v[2], 0, v[3]), look = RC + Vector3.new(v[4], 2, v[5]), name = v[1], area = "Ruins", lines = RUINS_SAY[v[1]] })
		end
	end
	local function areaOf(pos)
		if RC and RH and math.abs(pos.X - RC.X) < RH + 60 and math.abs(pos.Z - RC.Z) < RH + 60 then
			return "Ruins"
		end
		return "Sandbox"
	end
	local function inSite(p)
		for _, b in ipairs(boxes) do
			local l = b.cf:PointToObjectSpace(p)
			if math.abs(l.X) < b.half.X and math.abs(l.Z) < b.half.Z then
				return true
			end
		end
		return false
	end
	-- (2026-11-14) the field's floor is now green baseplate plates (workspace.Map.Baseplate) over grass lowered to
	-- y -0.4: a spot is found on the plates, and the plates under a spot are not clutter
	local plates = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Baseplate")
	local terrainOnly = RaycastParams.new()
	terrainOnly.FilterType = Enum.RaycastFilterType.Include
	terrainOnly.FilterDescendantsInstances = plates and { workspace.Terrain, plates } or { workspace.Terrain }
	local clutter = OverlapParams.new()
	clutter.FilterType = Enum.RaycastFilterType.Exclude
	clutter.FilterDescendantsInstances = plates and { Dummies.folder, plates } or { Dummies.folder }
	local spotsOf = { Sandbox = {}, Ruins = {} }
	local spots = spotsOf.Sandbox
	for _ = 1, 900 do
		if #spots >= 150 then
			break
		end
		-- (2026-11-14) the field is smaller and off-centre since the map was packed in: workspace.Map's FieldMin / FieldMax
		local fmap = workspace:FindFirstChild("Map")
		local fmin, fmax = fmap and fmap:GetAttribute("FieldMin") or Vector3.new(-352, 0, -352), fmap and fmap:GetAttribute("FieldMax") or Vector3.new(352, 0, 352)
		local p = Vector3.new(rng:NextNumber(fmin.X + 32, fmax.X - 32), 0, rng:NextNumber(fmin.Z + 32, fmax.Z - 32))
		if not inSite(p) then
			local hit = workspace:Raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -60, 0), terrainOnly)
			if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y) < 0.6 and hit.Normal.Y > 0.9 then
				if #workspace:GetPartBoundsInRadius(hit.Position + Vector3.new(0, 3.5, 0), 3.2, clutter) == 0 then
					table.insert(spots, hit.Position)
				end
			end
		end
	end
	-- (2026-11-15) the Ruins: anywhere on its open floor (grass or rock cells at y 0) with nothing standing there
	if arena and RC and RH then
		local floorParams = RaycastParams.new()
		floorParams.FilterType = Enum.RaycastFilterType.Include
		floorParams.FilterDescendantsInstances = { arena:FindFirstChild("Floor") }
		local free = OverlapParams.new()
		free.FilterType = Enum.RaycastFilterType.Exclude
		free.FilterDescendantsInstances = { Dummies.folder, arena:FindFirstChild("Floor") }
		local rs = spotsOf.Ruins
		for _ = 1, 1400 do
			if #rs >= 220 then -- (2026-11-15) 140 -> 220 spots for a crowd of 100
				break
			end
			local p = RC + Vector3.new(rng:NextNumber(-RH + 14, RH - 14), 0, rng:NextNumber(-RH + 14, RH - 14))
			local hit = workspace:Raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -60, 0), floorParams)
			if hit and math.abs(hit.Position.Y) < 0.6 and hit.Normal.Y > 0.9 and (hit.Instance.Name == "Grass" or hit.Instance.Name == "Rock") then
				if #workspace:GetPartBoundsInRadius(hit.Position + Vector3.new(0, 3.5, 0), 3.2, free) == 0 then
					table.insert(rs, hit.Position)
				end
			end
		end
	end
	local function spotNear(pos, minD, maxD)
		local spots = spotsOf[areaOf(pos)]
		if #spots == 0 then
			spots = spotsOf.Sandbox
		end
		local best
		for _ = 1, 14 do
			local s = spots[rng:NextInteger(1, #spots)]
			local d = ((s - pos) * FLAT).Magnitude
			if d >= minD and d <= maxD then
				return s
			end
			best = best or s
		end
		return best
	end
	local function spotAwayFrom(pos, danger)
		local spots = spotsOf[areaOf(pos)]
		if #spots == 0 then
			spots = spotsOf.Sandbox
		end
		local best, bs
		for _ = 1, 16 do
			local s = spots[rng:NextInteger(1, #spots)]
			local d = ((s - pos) * FLAT).Magnitude
			local away = ((s - danger) * FLAT).Magnitude
			if d > 35 and d < 130 then
				local score = away - d * 0.35
				if not bs or score > bs then
					best, bs = s, score
				end
			end
		end
		return best or spots[rng:NextInteger(1, #spots)]
	end
	-- the buttons they are allowed to press
	local buttons = {}
	for _, tag in ipairs(PRESSABLE) do
		for _, b in ipairs(CollectionService:GetTagged(tag)) do
			if b:IsA("BasePart") and H.buttons and H.buttons[b] then
				table.insert(buttons, { part = b, fn = H.buttons[b] })
			end
		end
	end

	------------------------------------------------------------------------------------------- the crowd
	local list = {}
	local byModel = {}
	local computing = 0
	local stats = { paths = 0, straight = 0, spawned = 0, presses = 0, chats = 0, events = 0, shocks = 0, panics = 0, cowers = 0, leaves = 0, trips = 0, bystanders = 0 }
	local function track(w, name)
		local tr = w.tracks[name]
		if tr == nil then
			tr = false
			local animator = w.hum:FindFirstChildOfClass("Animator")
			if animator then
				local a = Instance.new("Animation")
				a.AnimationId = "rbxassetid://" .. ANIM[name]
				local ok, t = pcall(function()
					return animator:LoadAnimation(a)
				end)
				if ok and t then
					t.Looped = LOOPED[name] == true
					t.Priority = (name == "walk" or name == "run") and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Action
					tr = t
				end
			end
			w.tracks[name] = tr
		end
		return tr or nil
	end
	local function stopEmote(w)
		if w.emote then
			local tr = w.tracks[w.emote]
			if tr and tr.IsPlaying then
				tr:Stop(0.25)
			end
			w.emote = nil
		end
	end
	local function emote(w, name)
		stopEmote(w)
		local tr = track(w, name)
		if tr then
			tr:Play(0.2)
			w.emote = name
		end
	end
	local function face(w, pos)
		local flat = (pos - w.hrp.Position) * FLAT
		if flat.Magnitude > 1 and not w.hrp.Anchored then
			w.hrp.CFrame = CFrame.lookAt(w.hrp.Position, w.hrp.Position + flat)
		end
	end
	local function halt(w)
		w.wps, w.onArrive = nil, nil
		w.pathId = (w.pathId or 0) + 1
		w.hum:Move(Vector3.zero)
		w.hum:MoveTo(w.hrp.Position)
	end
	local function idle(w, secs)
		w.state, w.actFn, w.onEnd = "idle", nil, nil
		w.untilT = os.clock() + (secs or rng:NextNumber(0.4, 1.6))
	end
	local function act(w, secs, fn, onEnd)
		w.state, w.actFn, w.onEnd = "act", fn, onEnd
		w.untilT = os.clock() + secs
	end
	local function goTo(w, goal, speed, onArrive)
		if not goal then
			idle(w)
			return
		end
		halt(w)
		w.goal, w.onArrive, w.speedNow = goal, onArrive, speed or w.speed
		w.state, w.untilT = "wait", os.clock() + 5
		local id = w.pathId
		task.spawn(function()
			while computing >= 4 do -- (2026-11-15) 3 -> 4 at once with 130 wanderers in the queue
				task.wait(0.1)
			end
			if w.pathId ~= id or not w.m.Parent then
				return
			end
			computing += 1
			local path = PathfindingService:CreatePath(AGENT)
			local ok = pcall(function()
				path:ComputeAsync(w.hrp.Position, goal)
			end)
			computing -= 1
			if w.pathId ~= id or not w.m.Parent or w.state ~= "wait" then
				return
			end
			if ok and path.Status == Enum.PathStatus.Success then
				w.wps, w.wi = path:GetWaypoints(), 2
				stats.paths += 1
			else -- no route found: walk straight at it and let the stuck check sort it out
				w.wps, w.wi = { { Position = goal } }, 1
				stats.straight += 1
			end
			local now = os.clock()
			w.state, w.stuckT, w.stuckN, w.lastPos, w.walkUntil = "walk", now, 0, w.hrp.Position, now + 50
		end)
	end
	local function arrive(w)
		local cb = w.onArrive
		halt(w)
		if cb then
			cb(w)
		else
			idle(w, rng:NextNumber(0.6, 2.4))
		end
	end

	------------------------------------------------------------------------------------------- fright
	-- what the clients draw: see StarterPlayerScripts.SandboxReactions
	local function setPose(m, pose, threat)
		if pose then
			m:SetAttribute("ReactBy", threat and threat.by and threat.by.UserId or nil)
			m:SetAttribute("ReactAt", threat and threat.pos or nil)
			m:SetAttribute("React", pose)
			CollectionService:AddTag(m, "Reacting")
		elseif m:GetAttribute("React") ~= nil then
			m:SetAttribute("React", nil)
			CollectionService:RemoveTag(m, "Reacting")
		end
	end
	-- where the thing it fears is NOW (a player moves; a place does not), how far, and the player's root if it is one
	local function threatPos(w)
		local th = w.threat
		if not th then
			return w.hrp.Position, 0, nil
		end
		local hrp = th.by and th.by.Character and th.by.Character:FindFirstChild("HumanoidRootPart")
		local p = hrp and hrp.Position or th.pos
		return p, ((p - w.hrp.Position) * FLAT).Magnitude, hrp
	end
	-- swing round to face something: quick, but not in one frame
	local function turn(m, hrp, pos)
		local flat = (pos - hrp.Position) * FLAT
		if flat.Magnitude < 1.5 then
			return
		end
		local rot = CFrame.lookAt(Vector3.zero, flat).Rotation
		task.spawn(function()
			for _ = 1, 7 do
				if not m.Parent or m:GetAttribute("Ragdolled") or hrp.Anchored then
					return
				end
				hrp.CFrame = CFrame.new(hrp.Position) * hrp.CFrame.Rotation:Lerp(rot, 0.4)
				task.wait(0.03)
			end
		end)
	end
	local function calm(w)
		if w.mood then
			w.mood = nil
			local by = w.threat and w.threat.by
			if by then
				w.waryOf, w.waryUntil = by, os.clock() + 45
			end
		end
		w.backing, w.again = nil, nil
		w.hum.AutoRotate = true
		setPose(w.m, nil)
	end
	local panic, pant
	local function runFrom(w)
		local tp = threatPos(w)
		goTo(w, spotAwayFrom(w.hrp.Position, tp), w.panicSpeed, function(w2)
			local now = os.clock()
			local _, d = threatPos(w2)
			if now < (w2.panicUntil or 0) or (d < 55 and now - (w2.panicStart or now) < 30) then
				runFrom(w2)
			else
				pant(w2)
			end
		end)
	end
	function panic(w, short, lines)
		local now = os.clock()
		if w.mood ~= "panic" then
			stats.panics += 1
			w.panicStart = now
			w.nextTrip = now + rng:NextNumber(3.5, 8)
		end
		w.mood = "panic"
		w.panicUntil = math.max(w.panicUntil or 0, now + (short and rng:NextNumber(5, 8) or rng:NextNumber(9, 15)))
		w.scrambleUntil = now + rng:NextNumber(0.5, 0.9) -- feet going, body not: the cartoon start
		w.nextTrip = math.max(w.nextTrip or 0, now + 4) -- never straight back down after getting up
		w.nextYelp = now + rng:NextNumber(2, 3.5)
		w.panicSpeed = rng:NextNumber(11, 13) -- NOT fast: the effort is in the legs and the arms
		w.hum.AutoRotate = true
		w.backing, w.chatting = nil, nil
		stopEmote(w)
		setPose(w.m, "panic", w.threat)
		say(w.m, pick(lines or SAY.flee))
		runFrom(w)
	end
	function pant(w)
		halt(w)
		w.mood = "pant"
		local tp = threatPos(w)
		turn(w.m, w.hrp, tp) -- it stops looking back the way it came
		setPose(w.m, "pant", w.threat)
		if rng:NextNumber() < 0.75 then
			say(w.m, pick(SAY.pant))
		end
		act(w, rng:NextNumber(3.5, 6), function(w2)
			local _, d, hrp = threatPos(w2)
			if hrp and d < 16 then -- it followed
				w2.again = true
				w2.untilT = 0
			end
		end, function(w2)
			if w2.again then
				w2.again = nil
				panic(w2, true, SAY.scream)
			else
				calm(w2)
			end
		end)
	end
	local function cower(w)
		halt(w)
		w.mood = "cower"
		stats.cowers += 1
		setPose(w.m, "cower", w.threat)
		if rng:NextNumber() < 0.8 then
			say(w.m, pick(SAY.plead))
		end
		act(w, rng:NextNumber(3, 5.5), function(w2)
			local _, d = threatPos(w2)
			if d > 34 then -- it has gone: now is the chance
				w2.untilT = 0
			end
		end, function(w2)
			panic(w2, true, SAY.scream)
		end)
	end
	-- not frightened enough to run: hands up, backing off the way it is NOT looking, then away at a hurry
	local function leave(w)
		local tp = threatPos(w)
		w.mood = "uneasy"
		stats.leaves += 1
		setPose(w.m, "shield", w.threat)
		w.hum.AutoRotate = false
		w.backing = true
		local away = (w.hrp.Position - tp) * FLAT
		away = away.Magnitude > 0.5 and away.Unit or -w.hrp.CFrame.LookVector
		act(w, rng:NextNumber(1.4, 2.2), function(w2)
			w2.hum.WalkSpeed = 4.5
			w2.hum:MoveTo(w2.hrp.Position + away * 6)
		end, function(w2)
			calm(w2)
			w2.quietUntil = os.clock() + 14
			if rng:NextNumber() < 0.6 then
				say(w2.m, pick(SAY.leave))
			end
			goTo(w2, spotAwayFrom(w2.hrp.Position, tp), 14)
		end)
	end
	local function decide(w)
		if w.mood ~= "shock" then
			return
		end
		local _, d = threatPos(w)
		local sev = w.sev or 1
		local r = rng:NextNumber()
		if not w.threat.by then
			leave(w) -- a machine did it: nothing to run from, but it is not staying to watch
		elseif w.threat.by and d < 11 and r < 0.35 then
			cower(w)
		elseif sev <= 1 and r < 0.3 then
			leave(w)
		else
			panic(w)
		end
	end
	-- the moment of seeing it: a beat of nothing, then the shock, then decide()
	local function startle(w, threat, sev, dist, pose, hold, lines)
		halt(w)
		stopEmote(w)
		w.chatting, w.backing = nil, nil
		w.hum.AutoRotate = true
		w.mood, w.sev, w.threat = "shock", sev, threat
		stats.shocks += 1
		act(w, math.clamp(dist / 150, 0.04, 0.4) + rng:NextNumber(0, 0.16), nil, function(w2)
			if w2.mood ~= "shock" then
				return
			end
			turn(w2.m, w2.hrp, (threatPos(w2)))
			setPose(w2.m, pose or pick(SHOCKS), w2.threat)
			local grave = (w2.sev or 1) >= 3
			if rng:NextNumber() < 0.75 then
				say(w2.m, pick(lines or (grave and SAY.horror or SAY.gasp)))
			end
			act(w2, hold or (grave and rng:NextNumber(1.0, 1.6) or rng:NextNumber(1.4, 2.4)), function(w3)
				local _, d, hrp = threatPos(w3)
				if hrp and d < 7 then -- too close to stand and stare
					w3.untilT = math.min(w3.untilT, os.clock() + 0.25)
				end
			end, decide)
		end)
	end
	local function noticed(w, ev, dist)
		local now = os.clock()
		local threat = { by = ev.by, pos = ev.pos }
		local mood = w.mood
		if mood == "test" then
			return
		elseif mood == "panic" then -- already running: it runs for longer, and from the newest thing
			if ev.by or not (w.threat and w.threat.by) then
				w.threat = threat
			end
			w.panicUntil = math.max(w.panicUntil or 0, now + rng:NextNumber(5, 9))
			setPose(w.m, "panic", w.threat)
		elseif mood == "shock" or mood == "cower" then
			w.sev = math.max(w.sev or 1, ev.sev)
			if ev.by then
				w.threat = threat
			end
		elseif mood == "pant" or mood == "uneasy" then
			if ev.by then
				w.threat = threat
				panic(w, true, SAY.scream)
			end
		else
			if not ev.by then -- machines hurt somebody every few seconds: one fright each, then it has seen it
				if now < (w.quietUntil or 0) then
					return
				end
				w.quietUntil = now + 25
			end
			startle(w, threat, ev.sev, dist)
		end
	end

	-- seeing ----------------------------------------------------------------------------------------------------
	local sight = RaycastParams.new()
	sight.FilterType = Enum.RaycastFilterType.Exclude
	sight.RespectCanCollide = true
	local goreFolder
	pcall(function()
		goreFolder = Injury.gore()
	end)
	local function canSee(hrp, ev, R)
		local from = hrp.Position + Vector3.new(0, 1.5, 0)
		local to = ev.pos + Vector3.new(0, 1.5, 0)
		local d = to - from
		local dist = d.Magnitude
		if dist > R then
			return false
		end
		if dist < 7 then
			return true, dist
		end
		if not ev.loud and dist > 26 and hrp.CFrame.LookVector:Dot(d.Unit) < -0.35 and rng:NextNumber() < 0.6 then
			return false -- well behind its back, and quiet (closer than that it is heard)
		end
		local hit = workspace:Raycast(from, d * 0.94, sight)
		if hit and hit.Instance.Transparency > 0.45 then -- glass: look again from the far side of it
			local p = hit.Position + d.Unit * 0.8
			hit = workspace:Raycast(p, (to - p) * 0.94, sight)
		end
		if hit then
			return ev.loud and dist < 40, dist -- a wall hides it, but not a bang next door
		end
		return true, dist
	end
	local pending = {}
	local function report(pos, by, sev, victim, loud)
		local key = by or ("anon" .. math.floor(pos.X / 90) .. "_" .. math.floor(pos.Z / 90))
		local ev = pending[key]
		if not ev then
			pending[key] = { pos = pos, by = by, sev = sev, victim = victim, loud = loud }
		else
			if sev > ev.sev then
				ev.pos, ev.sev, ev.victim = pos, sev, victim
			end
			ev.loud = ev.loud or loud
		end
	end
	Injury.onHarm = function(model, pos, by, kind, amount)
		if amount < 3 then
			return
		end
		local sev = (amount >= 40 or kind == "blast" or kind == "sever") and 3 or (amount >= 12 and 2 or 1)
		local w = byModel[model]
		if w and by then
			w.hurtBy, w.hurtT = by, os.clock()
		end
		if not by and sev < 2 then
			return
		end
		report(pos, by, sev, model, kind == "bullet" or kind == "blast")
	end
	H.onPropHarm = function(part, amount, by)
		report(part.Position, by, 1, nil, false)
	end
	H.onBlast = function(pos, radius, by)
		report(pos, by, 3, nil, true)
	end
	-- the ones posted at the machines, and the ones a player spawned: they keep their place
	local standers = {}
	local standCool = setmetatable({}, { __mode = "k" })
	local function standClear(m)
		standers[m] = nil
		if m.Parent then
			setPose(m, nil)
		end
	end
	local function standTick(now)
		for m, b in pairs(standers) do
			local rec = b.rec
			if not m.Parent or rec.dead or m:GetAttribute("Ragdolled") or m:GetAttribute("GrabbedBy") or m:GetAttribute("Strapped") then
				standClear(m)
			else
				local hrpT = b.threat.by and b.threat.by.Character and b.threat.by.Character:FindFirstChild("HumanoidRootPart")
				local tp = hrpT and hrpT.Position or b.threat.pos
				local d = ((tp - rec.hrp.Position) * FLAT).Magnitude
				if b.stage == 0 then
					if now >= b.at then
						b.stage, b.untilT = 1, now + rng:NextNumber(1.6, 3)
						turn(m, rec.hrp, tp)
						setPose(m, pick(SHOCKS), b.threat)
						stats.bystanders += 1
						if rng:NextNumber() < 0.35 then
							say(m, pick(b.sev >= 3 and SAY.horror or SAY.gasp))
						end
					end
				elseif b.stage == 1 then
					if now >= b.untilT then
						if hrpT and d < 28 then
							b.stage, b.untilT = 2, now + rng:NextNumber(3, 6)
							setPose(m, "cower", b.threat)
							if rng:NextNumber() < 0.3 then
								say(m, pick(SAY.plead))
							end
						else
							standCool[m] = math.max(standCool[m] or 0, now + 3)
							standClear(m)
						end
					end
				elseif now >= b.untilT or d > 42 then
					standCool[m] = math.max(standCool[m] or 0, now + 3)
					standClear(m)
				end
			end
		end
	end
	local function sweep(ev)
		local now = os.clock()
		local hrpT = ev.by and ev.by.Character and ev.by.Character:FindFirstChild("HumanoidRootPart")
		if ev.by and (not hrpT or (hrpT.Position - ev.pos).Magnitude > 110) then
			ev.by = nil -- whoever threw it is long gone: there is nobody here to be afraid of
		end
		local vrec = ev.victim and Dummies.records[ev.victim]
		if vrec and vrec.dead then
			ev.sev = 3
		end
		if not ev.by and ev.sev < 2 then
			return
		end
		local ex = { Dummies.folder }
		if goreFolder then
			table.insert(ex, goreFolder)
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ex, p.Character)
			end
		end
		sight.FilterDescendantsInstances = ex
		-- what a player does carries: it is watched from across the grass. What a machine does is only noticed close by -
		-- the machines never stop (measured: with one radius for both, 5 of the 18 were panicking 16 s after boot, untouched)
		local R = ev.by and (ev.loud and 95 or 62) or (ev.loud and 60 or 34)
		for _, w in ipairs(list) do
			if not w.down and not w.m:GetAttribute("Ragdolled") then
				if w.m == ev.victim then
					-- it was the one hit, and it is still on its feet
					if ev.by and w.mood ~= "panic" and w.mood ~= "test" then
						startle(w, { by = ev.by, pos = ev.pos }, 3, 0, "shield", rng:NextNumber(0.35, 0.6), SAY.bolt)
					end
				else
					local ok, dist = canSee(w.hrp, ev, R)
					if ok then
						noticed(w, ev, dist)
					end
				end
			end
		end
		if ev.by or rng:NextNumber() < 0.5 then
			local n = 0
			for m, rec in pairs(Dummies.records) do
				if n >= 10 then
					break
				end
				if not rec.dead and m ~= ev.victim and not standers[m] and not byModel[m] and now >= (standCool[m] or 0)
					and ((rec.station and rec.station.kind == "stand") or rec.owner)
					and not m:GetAttribute("Ragdolled") and not m:GetAttribute("GrabbedBy") and not m:GetAttribute("Strapped")
					and not m:GetAttribute("Roamer") and not m:GetAttribute("Subject") and not m:GetAttribute("Invuln") then
					local ok, dist = canSee(rec.hrp, ev, R * 0.8)
					if ok then
						n += 1
						standers[m] = { rec = rec, stage = 0, at = now + math.clamp(dist / 150, 0.04, 0.4) + rng:NextNumber(0, 0.2), threat = { by = ev.by, pos = ev.pos }, sev = ev.sev }
						if not ev.by then
							standCool[m] = now + 20
						end
					end
				end
			end
		end
	end

	------------------------------------------------------------------------------------------- things to do
	local DO = {}
	function DO.stroll(w)
		goTo(w, spotNear(w.hrp.Position, 25, 120), w.speed)
	end
	function DO.jog(w)
		goTo(w, spotNear(w.hrp.Position, 90, 260), 17)
	end
	function DO.look(w)
		local mine = {}
		local here = areaOf(w.hrp.Position)
		for _, v in ipairs(views) do
			if v.area == here then
				table.insert(mine, v)
			end
		end
		if #mine == 0 then
			return DO.stroll(w)
		end
		local v = mine[rng:NextInteger(1, #mine)]
		goTo(w, v.pos + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), w.speed, function(w2)
			face(w2, v.look)
			act(w2, rng:NextNumber(3, 6))
			local lines = v.lines or (Speech.LINES and Speech.LINES.site and Speech.LINES.site[v.name])
			if lines and rng:NextNumber() < 0.7 then
				say(w2.m, pick(lines))
			end
			if rng:NextNumber() < 0.4 then
				emote(w2, "point")
			end
		end)
	end
	function DO.dance(w)
		halt(w)
		local name = pick({ "dance1", "dance2", "dance3", "cheer", "laugh" })
		emote(w, name)
		act(w, LOOPED[name] and rng:NextNumber(5, 9) or 2.6)
	end
	function DO.nap(w)
		halt(w)
		say(w.m, pick(SAY.nap))
		act(w, 0.9, nil, function(w2)
			Ragdoll.Ragdoll(w2.m, rng:NextNumber(3, 5))
		end)
	end
	function DO.greet(w, hrp)
		halt(w)
		face(w, hrp.Position)
		emote(w, "wave")
		say(w.m, pick(SAY.greet))
		act(w, 2.8)
	end
	function DO.follow(w, player)
		halt(w)
		say(w.m, pick(SAY.follow))
		local side = rng:NextNumber(-4, 4)
		act(w, rng:NextNumber(9, 15), function(w2)
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				w2.untilT = 0
				return
			end
			local to = (hrp.Position - w2.hrp.Position) * FLAT
			if to.Magnitude > 7 then
				w2.hum.WalkSpeed = (to.Magnitude > 22) and 20 or 13
				w2.hum:MoveTo(hrp.Position - to.Unit * 5 + to.Unit:Cross(Vector3.yAxis) * side)
			else
				w2.hum:Move(Vector3.zero)
			end
		end, halt)
	end
	function DO.press(w)
		local near = {}
		for _, b in ipairs(buttons) do
			if b.part.Parent then
				local d = ((b.part.Position - w.hrp.Position) * FLAT).Magnitude
				if d < 150 then
					table.insert(near, { b, d })
				end
			end
		end
		if #near == 0 then
			return DO.stroll(w)
		end
		table.sort(near, function(a, b)
			return a[2] < b[2]
		end)
		local b = near[rng:NextInteger(1, math.min(3, #near))][1]
		local from = (w.hrp.Position - b.part.Position) * FLAT
		from = from.Magnitude > 1 and from.Unit or Vector3.xAxis
		goTo(w, Vector3.new(b.part.Position.X, 0, b.part.Position.Z) + from * 3.5, w.speed, function(w2)
			if ((b.part.Position - w2.hrp.Position) * FLAT).Magnitude > 9 then
				idle(w2) -- never got there
				return
			end
			face(w2, b.part.Position)
			say(w2.m, pick(SAY.press))
			act(w2, 1.3, nil, function(w3)
				stats.presses += 1
				task.spawn(function()
					pcall(b.fn, nil)
				end)
				emote(w3, "point")
				act(w3, 1.6, nil, function(w4)
					say(w4.m, pick(SAY.pressed))
					goTo(w4, spotNear(w4.hrp.Position, 30, 90), 15)
				end)
			end)
		end)
	end
	function DO.chat(w)
		local partner, bd
		for _, o in ipairs(list) do
			if o ~= w and not o.down and not o.chatting and not o.mood and (o.state == "idle" or o.state == "walk") then
				local d = ((o.hrp.Position - w.hrp.Position) * FLAT).Magnitude
				if d < 90 and (not bd or d < bd) then
					partner, bd = o, d
				end
			end
		end
		if not partner then
			return DO.stroll(w)
		end
		w.chatting, partner.chatting = true, true
		halt(partner)
		partner.state, partner.untilT = "wait", os.clock() + 20
		local off = (w.hrp.Position - partner.hrp.Position) * FLAT
		off = off.Magnitude > 1 and off.Unit or Vector3.xAxis
		goTo(w, partner.hrp.Position * FLAT + off * 4, w.speed, function(a)
			local b = partner
			local function over()
				a.chatting, b.chatting = nil, nil
			end
			if not b.m.Parent or b.down or b.mood or ((b.hrp.Position - a.hrp.Position) * FLAT).Magnitude > 12 then
				over()
				idle(a)
				if b.state == "wait" and not b.mood then
					idle(b)
				end
				return
			end
			stats.chats += 1
			face(a, b.hrp.Position)
			face(b, a.hrp.Position)
			act(a, 8.5, nil, over)
			act(b, 8.5)
			local script3 = { { a, pick(SAY.chat), 0.3 }, { b, pick(SAY.reply), 2.6 }, { a, pick(SAY.chat), 4.8 }, { b, pick(SAY.reply), 6.8 } }
			for _, s in ipairs(script3) do
				task.delay(s[3], function()
					if a.chatting and b.chatting and s[1].m.Parent and not s[1].down and not s[1].mood and s[1].state == "act" then
						say(s[1].m, s[2])
					end
				end)
			end
			task.delay(7.2, function()
				for _, x in ipairs({ a, b }) do
					if a.chatting and b.chatting and x.m.Parent and not x.down and not x.mood and x.state == "act" then
						emote(x, pick({ "laugh", "cheer" }))
					end
				end
			end)
		end)
		-- if the walk over never finishes, nobody is left waiting for ever
		task.delay(22, function()
			if w.chatting and w.state ~= "act" then
				w.chatting, partner.chatting = nil, nil
			end
		end)
	end
	local function choose(w)
		if w.mood or w.m:GetAttribute("React") ~= nil then
			calm(w) -- whatever frightened it is over
		end
		local pos = w.hrp.Position
		local player, pd, phrp = nearestPlayer(pos)
		local trusts = player and not (w.waryOf == player and os.clock() < (w.waryUntil or 0))
		local r = rng:NextNumber()
		-- (2026-11-15) a chat is now about a quarter of what they decide to do (it was 11%)
		if trusts and pd < 22 and r < 0.15 then
			DO.greet(w, phrp)
		elseif trusts and pd < 45 and r < 0.2 then
			DO.follow(w, player)
		elseif r < 0.32 then
			DO.look(w)
		elseif r < 0.58 then
			DO.chat(w)
		elseif r < 0.63 and #buttons > 0 then
			DO.press(w)
		elseif r < 0.72 then
			DO.dance(w)
		elseif r < 0.76 and not w.m:GetAttribute("Hurt") then
			DO.nap(w)
		elseif r < 0.85 then
			DO.jog(w)
		else
			DO.stroll(w)
		end
	end

	------------------------------------------------------------------------------------------- the loop
	local function spawnOne(area, at, firstIn)
		local spots = spotsOf[area] or {}
		if #spots == 0 then
			return
		end
		local spot = at
		for _ = 1, at and 0 or 14 do -- out of sight if it can be
			local s = spots[rng:NextInteger(1, #spots)]
			local _, d = nearestPlayer(s)
			spot = spot or s
			if d > 70 then
				spot = s
				break
			end
		end
		local m = Dummies.spawn(CFrame.new(spot + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), {})
		if not m then
			return
		end
		m:SetAttribute("Wanderer", true)
		local rec = Dummies.records[m]
		stats.spawned += 1
		m:SetAttribute("WanderArea", area)
		local w = { m = m, rec = rec, hum = m:FindFirstChildOfClass("Humanoid"), hrp = m:FindFirstChild("HumanoidRootPart"), tracks = {}, speed = rng:NextNumber(7.5, 10.5),
			state = "idle", untilT = os.clock() + (firstIn or rng:NextNumber(0.5, 4)), pathId = 0, area = area }
		table.insert(list, w)
		byModel[m] = w
	end
	local function trip(w)
		stats.trips += 1
		local look = w.hrp.CFrame.LookVector
		Ragdoll.Ragdoll(w.m, rng:NextNumber(0.9, 1.4))
		pcall(function()
			Ragdoll.Jolt(w.m, look * 16 + Vector3.new(0, 5, 0))
		end)
		if rng:NextNumber() < 0.5 then
			say(w.m, pick(SAY.trip))
		end
	end
	local function move(w)
		-- walk / run cycle to match what the legs are doing. Read off the body's own speed: Humanoid.MoveDirection stays
		-- at zero for a humanoid the server drives with MoveTo (measured), so it cannot be the test.
		local moving = (w.hrp.AssemblyLinearVelocity * FLAT).Magnitude > 1.5
		local panicking = w.mood == "panic"
		local want = moving and ((panicking or w.hum.WalkSpeed >= 15) and "run" or "walk") or nil
		if w.gait ~= want then
			if w.gait and w.tracks[w.gait] then
				w.tracks[w.gait]:Stop(0.2)
			end
			w.gait = want
			if want then
				local tr = track(w, want)
				if tr then
					tr:Play(0.2)
				end
			end
		end
		if want and w.tracks[want] then
			local rate
			if panicking then
				rate = 1.9 -- the legs go far faster than the ground does: that is the effort
			elseif w.backing then
				rate = -0.9 -- walking backwards
			else
				rate = math.clamp(w.hum.WalkSpeed / ((want == "run") and 16 or 9), 0.6, 1.8)
			end
			w.tracks[want]:AdjustSpeed(rate)
		end
		if moving and w.emote then
			stopEmote(w)
		end
		if not moving and w.rec and w.rec.track and not w.rec.track.IsPlaying then
			w.rec.track:Play(0.3) -- the ragdoll stops every track; put the idle back
		end
	end
	local function step(w, now)
		if w.state == "walk" then
			local wp = w.wps and w.wps[w.wi]
			if not wp or now > (w.walkUntil or 0) then
				arrive(w)
				return
			end
			local pos = w.hrp.Position
			if ((wp.Position - pos) * FLAT).Magnitude < 3.2 then
				w.wi += 1
				wp = w.wps[w.wi]
				if not wp then
					arrive(w)
					return
				end
				if wp.Action == Enum.PathWaypointAction.Jump then
					w.hum.Jump = true
				end
			end
			local sp = w.speedNow or w.speed
			if w.mood == "panic" then
				sp = (now < (w.scrambleUntil or 0)) and 3.2 or (w.panicSpeed or 12)
				if now >= (w.nextYelp or 0) then
					w.nextYelp = now + rng:NextNumber(2.6, 4.5)
					say(w.m, pick(SAY.scream))
				end
				if now >= (w.nextTrip or 0) then
					w.nextTrip = now + rng:NextNumber(5, 10)
					if rng:NextNumber() < 0.22 then
						trip(w)
						return
					end
				end
				if now > (w.panicUntil or 0) then
					local _, d = threatPos(w)
					if d > 60 then -- far enough, long enough
						pant(w)
						return
					end
				end
			end
			w.hum.WalkSpeed = sp
			w.hum:MoveTo(wp.Position)
			if (pos - w.lastPos).Magnitude > 1.5 then
				w.lastPos, w.stuckT = pos, now
			elseif now - w.stuckT > 2.2 then
				w.stuckT = now
				w.stuckN = (w.stuckN or 0) + 1
				if w.stuckN == 1 then
					w.hum.Jump = true
				else
					w.chatting = nil
					if w.mood == "panic" then
						runFrom(w) -- boxed in: another way out
					else
						halt(w)
						idle(w, 0.4) -- give up on that one
					end
				end
			end
		elseif w.state == "act" then
			if w.actFn then
				w.actFn(w)
			end
			if now >= w.untilT and w.state == "act" then
				local done = w.onEnd
				stopEmote(w)
				idle(w)
				if done then
					done(w)
				end
			end
		elseif w.state == "idle" then
			if now >= w.untilT then
				choose(w)
			end
		elseif w.state == "wait" then
			if now >= w.untilT then
				w.chatting = nil
				idle(w, 0.3)
			end
		end
	end

	local seenDead = setmetatable({}, { __mode = "k" })
	for m, rec in pairs(Dummies.records) do
		if rec.dead then
			seenDead[m] = true
		end
	end
	-- (2026-11-15, owner: "they slowly spawn in when they should all spawn in at once before the game starts") the
	-- whole crowd is put down the moment the server boots - each on a spot of its own (shuffled, no two on one spot),
	-- 26 a frame so no single frame takes the lot - instead of one every 0.5 s (130 took ~65 s). Their first moves are
	-- spread over 0.3-6 s so 130 path requests don't all queue at once. Only replacements for the dead still come one
	-- at a time, out of sight, through the loop below.
	local filling = true -- the top-up loop below keeps out until this is done
	task.spawn(function()
		local made = 0
		for area, n in pairs(W.COUNT) do
			local spots = spotsOf[area] or {}
			if #spots > 0 then
				local order = table.create(#spots)
				for i = 1, #spots do
					order[i] = spots[i]
				end
				for i = #order, 2, -1 do
					local j = rng:NextInteger(1, i)
					order[i], order[j] = order[j], order[i]
				end
				for k = 1, n do
					local ok, err = pcall(spawnOne, area, order[(k - 1) % #order + 1], rng:NextNumber(0.3, 6))
					if not ok then
						warn("[Wanderers] boot spawn: " .. tostring(err))
					end
					made += 1
					if made % 26 == 0 then
						task.wait()
					end
				end
			end
		end
		filling = false
	end)
	local acc, nextSpawn, nextDeaths = 0, os.clock() + 2, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		-- a death is the worst thing there is to see
		if now >= nextDeaths then
			nextDeaths = now + 0.4
			for m, rec in pairs(Dummies.records) do
				if rec.dead and not seenDead[m] then
					seenDead[m] = true
					local uid = m:GetAttribute("LastHitBy")
					report(rec.hrp.Position, uid and Players:GetPlayerByUserId(uid) or nil, 3, m, false)
				end
			end
		end
		for i = #list, 1, -1 do
			local w = list[i]
			local m = w.m
			if not m.Parent or not Dummies.is(m) or m:GetAttribute("Dead") then
				w.pathId += 1
				byModel[m] = nil
				table.remove(list, i)
				nextSpawn = math.max(nextSpawn, now + 6)
			elseif m:GetAttribute("Ragdolled") or m:GetAttribute("GrabbedBy") or m:GetAttribute("Strapped") then
				if not w.down then
					w.down = true
					w.gait, w.emote, w.chatting, w.backing = nil, nil, nil, nil
					halt(w) -- (2026-11-14) the walk it was on is cancelled: a downed body must not be steered (it spun in circles)
					w.hum.Jump = false
					w.pathId += 1
					w.hum.AutoRotate = true
					w.napping = w.state == "idle" and w.untilT > now -- it lay down by itself
				end
				local g = m:GetAttribute("GrabbedBy")
				local grabber = typeof(g) == "number" and Players:GetPlayerByUserId(g) or nil
				if grabber then -- being carried about is a thing to run from, once it is put down
					w.hurtBy, w.hurtT = grabber, now
				end
			else
				if w.down then -- back on its feet
					w.down = false
					local player, pd, phrp = nearestPlayer(w.hrp.Position)
					if w.mood == "test" then
						calm(w)
						idle(w, 1)
					elseif w.mood then -- it was frightened already (or it tripped as it ran): up and off again
						panic(w, true, SAY.scream)
					elseif w.hurtT and now - w.hurtT < 14 and w.hurtBy and w.hurtBy.Parent then -- somebody did this to it
						w.threat = { by = w.hurtBy, pos = w.hrp.Position }
						panic(w, false, SAY.bolt)
					elseif not w.napping and phrp and pd < 35 and rng:NextNumber() < 0.4 then
						w.threat = { by = player, pos = phrp.Position }
						panic(w, true, SAY.bolt)
					else
						idle(w, rng:NextNumber(0.8, 2))
					end
					w.napping = nil
				elseif not w.mood and w.waryOf and now < (w.waryUntil or 0) and now >= (w.nextFlinch or 0) then
					-- the one it ran from has come close again
					local hrp = w.waryOf.Character and w.waryOf.Character:FindFirstChild("HumanoidRootPart")
					if hrp and ((hrp.Position - w.hrp.Position) * FLAT).Magnitude < 14 then
						w.nextFlinch = now + 6
						startle(w, { by = w.waryOf, pos = hrp.Position }, 2, 0, "shield", rng:NextNumber(0.4, 0.7), SAY.flinch)
					end
				end
				local ok, err = pcall(step, w, now)
				if not ok then
					warn("[Wanderers] " .. tostring(err))
					calm(w)
					idle(w, 1)
				end
				move(w)
			end
		end
		for key, ev in pairs(pending) do
			pending[key] = nil
			stats.events += 1
			local ok, err = pcall(sweep, ev)
			if not ok then
				warn("[Wanderers] sweep: " .. tostring(err))
			end
		end
		standTick(now)
		if now >= nextSpawn and not filling then
			-- top up whichever crowd is furthest short of its count
			local have = {}
			for _, w in ipairs(list) do
				local a = w.area or "Sandbox"
				have[a] = (have[a] or 0) + 1
			end
			local need, short = nil, 0
			for area, n in pairs(W.COUNT) do
				if #spotsOf[area] > 0 and n - (have[area] or 0) > short then
					need, short = area, n - (have[area] or 0)
				end
			end
			if need then
				nextSpawn = now + 0.5
				spawnOne(need)
			end
		end
	end)

	if RunService:IsStudio() then
		local ctl = Instance.new("BindableFunction")
		ctl.Name = "Control"
		ctl.OnInvoke = function(cmd, a)
			local function free(near)
				local best, bd
				for _, w in ipairs(list) do
					if not w.down and not w.chatting and not w.mood and (w.state == "idle" or w.state == "walk") then
						local _, d = nearestPlayer(w.hrp.Position)
						if not near then
							return w
						end
						if not bd or d < bd then
							best, bd = w, d
						end
					end
				end
				return best
			end
			if cmd == "act" and DO[a] then
				local w = free(false)
				if not w then
					return nil
				end
				halt(w)
				local player, _, phrp = nearestPlayer(w.hrp.Position)
				if a == "greet" then
					DO.greet(w, phrp)
				elseif a == "follow" then
					DO.follow(w, player)
				else
					DO[a](w)
				end
				return w.m
			elseif cmd == "fright" or cmd == "pose" then
				local w = free(true)
				if not w then
					return nil
				end
				local player, d, phrp = nearestPlayer(w.hrp.Position)
				local threat = { by = player, pos = phrp and phrp.Position or w.hrp.Position }
				if cmd == "pose" then
					halt(w)
					w.mood, w.threat = "test", threat
					setPose(w.m, a, threat)
					act(w, 8, nil, calm)
				elseif a == "shock" then
					startle(w, threat, 2, d)
				else
					halt(w)
					w.mood, w.sev, w.threat = "shock", 2, threat
					local f = ({ panic = panic, cower = cower, leave = leave, pant = pant })[a]
					if f then
						f(w)
					end
				end
				return w.m
			end
			local states = {}
			for _, w in ipairs(list) do
				local k = w.down and "down" or (w.mood or w.state)
				states[k] = (states[k] or 0) + 1
			end
			local nStand = 0
			for _ in pairs(standers) do
				nStand += 1
			end
			local per = {}
			for _, w in ipairs(list) do
				local a = w.area or "?"
				per[a] = (per[a] or 0) + 1
			end
			return { count = #list, perArea = per, spots = { Sandbox = #spotsOf.Sandbox, Ruins = #spotsOf.Ruins }, views = #views, buttons = #buttons, states = states, standers = nStand, stats = stats }
		end
		ctl.Parent = script
	end
end

return W
