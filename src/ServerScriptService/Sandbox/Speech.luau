--!nocheck
-- ServerScriptService.Sandbox.Speech (2026-11-13): the dummies talk. The owner asked for them to "say random stuff
-- (sometimes directed towards the character)" in a black speech bubble. This picks WHO says WHAT; each client draws
-- the bubble (Net "say", model, text -> StarterPlayerScripts.SandboxWorld).
--   * only dummies with a player within earshot speak, each every 8-20 s, and never two lines inside 0.4 s
--   * what they say depends on where they are: a line about YOU if you are close (they turn to face you), about
--     your weapon if you are holding one, about the machine they are standing at, or just idle chatter
--   * a hit that does not kill gets a yelp now and then; getting back up gets a line; hooked, test-subject and
--     mutated bodies have their own
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local S = {}
local LINES = {
	idle = { "Lovely weather for standing still.", "I think I left the oven on.", "Does anyone know what day it is?", "My contract said 'light duties'.",
		"I'm on my break.", "Is it lunch yet?", "I used to model shirts, you know.", "Third day on the job.", "Has anyone seen Gary?",
		"I can't feel my legs. Oh wait. I can.", "Nobody mentioned a train.", "I should have been a scarecrow.", "Just standing here. Menacingly.",
		"I dreamt I was a crash test dummy.", "I give this place two stars.", "Is this the queue?", "My knees are not what they were.",
		"Somebody stole my trousers.", "I was promised a chair.", "It's quiet. Too quiet." },
	you = { "You've got that look in your eye.", "Oh good. It's you again.", "Hi. Please be normal.", "We're friends, right? Right?",
		"I don't like how you're looking at me.", "Nice to meet you. Stay over there.", "You seem like a reasonable person.",
		"Whatever you're thinking, don't.", "I have a family. Probably.", "Are you the new safety inspector?", "Go and bother Gary.",
		"You again? I just got comfortable.", "I've heard about you.", "Do I owe you money?", "You're standing very close." },
	armed = { "Let's talk about this.", "Put it down and we'll say no more.", "Is that thing safe?", "You don't need that. We're pals." },
	weapon = {
		bat = { "Lovely bat. Keep it over there.", "Batting practice is somewhere else." },
		axe = { "Who gave you an axe?!", "That's for trees. I'm not a tree." },
		katana = { "Is that sharp? It looks sharp.", "Nice sword. Very pointy." },
		sledge = { "That hammer is bigger than me.", "Building something? Please say yes." },
		gun = { "Whoa, whoa. Is that loaded?", "Take my wallet. I don't have one.", "Point that somewhere else." },
	},
	hurt = { "OW!", "Hey!", "What was that for?!", "My everything!", "Rude.", "I felt that one.", "Not the face!", "I'm telling HR.",
		"That's going to bruise.", "Medic? Anyone?", "I need that!", "Why?!" },
	up = { "I'm fine. I'm fine.", "Walk it off.", "Did anyone see that?", "I meant to do that.", "Round two, then.", "Still got it." },
	-- (2026-11-13) hurt and on the floor for good (Injury sets Hurt; RagdollService no longer stands those up)
	downed = { "I can't get up.", "Everything hurts.", "I'll just lie here.", "Is that my blood?", "Medic...", "I think something's broken.", "Don't mind me.", "Ow. Ow. Ow.",
		"Tell my post I loved it.", "Five more minutes. For ever.", "Not getting up from that one." },
	strapped = { "All the blood's going to my head.", "A little help?", "This is fine.", "I can see my house from here.", "Is this part of the tour?" },
	subject = { "Not the tentacles. Please.", "I was told this was a sleep study.", "Which button is the good one?", "Do I get paid for this?",
		"I look fine as I am!", "Is the glass soundproof? HELLO?" },
	roamer = { "I feel... different.", "FREEDOM!", "What have you done to me?", "Look at me now.", "I'm going to find Gary.", "Nobody can stop me." },
	site = {
		Grinder = { "I don't love this plank.", "What's that grinding noise?", "It's a long way down." },
		Press = { "Why is the ceiling so low?", "This floor has stains.", "What does the red button do?" },
		Fan = { "Bit breezy today.", "Is that fan plugged in?", "Hold on to your hat." },
		Propeller = { "Mind your shins.", "Who puts a propeller on the floor?" },
		Train = { "The train isn't due for hours.", "I'm sure it's a disused line.", "Do you hear a rumbling?" },
		Cannon = { "I am not getting in that.", "That wall looks sturdy." },
		Wrecker = { "That ball is just for show, right?", "It's swinging a bit." },
		Shark = { "Nice pond. Peaceful.", "Was that a fin?", "I can't swim." },
		Rex = { "Big lizard. Good lizard.", "It can't see us if we don't move." },
		Bear = { "Here, teddy teddy.", "He looks hungry." },
		Tower = { "Great view from up here.", "Don't push. Don't.", "I'm not good with heights." },
		Mines = { "Watch your step.", "Why is the ground beeping?" },
		Tesla = { "My hair is standing up.", "Is it meant to hum like that?" },
		Slide = { "Wheee. In theory.", "I'll take the stairs." },
		Ring = { "I could have been a contender.", "Ding ding." },
		Rocket = { "I always wanted to see space.", "Is it meant to smoke?" },
		Trampoline = { "Boing.", "My stomach is still up there." },
		SpikePit = { "Mind the gap.", "Those look pointy." },
		GasYard = { "No smoking, please.", "It smells like petrol here." },
		Disaster = { "The forecast said clear skies.", "Why is this room locked?" },
		Factory = { "Health and safety would love this.", "Where does this belt go?" },
	},
}
S.LINES = LINES
local ARMED = { bat = true, axe = true, katana = true, sledge = true, gun = true }
local EARSHOT, CLOSE = 80, 30

function S.init(ctx)
	local Dummies, net = ctx.Dummies, ctx.net
	local map = workspace:WaitForChild("Map")
	-- which machine a body is standing at: the nearest site model whose footprint it is inside
	local sites = {}
	for _, m in ipairs(map:GetChildren()) do
		if m:IsA("Model") and LINES.site[m.Name] then
			local ok, cf, size = pcall(function()
				return m:GetBoundingBox()
			end)
			if ok then
				table.insert(sites, { name = m.Name, pos = cf.Position, r = math.clamp(math.max(size.X, size.Z) * 0.5, 16, 60) })
			end
		end
	end
	local function siteAt(pos)
		local best, bd
		for _, s in ipairs(sites) do
			local d = ((pos - s.pos) * Vector3.new(1, 0, 1)).Magnitude
			if d < s.r and (not bd or d < bd) then
				best, bd = s.name, d
			end
		end
		return best
	end
	local function pick(list, st)
		local line = list[math.random(#list)]
		if line == st.lastLine and #list > 1 then
			line = list[math.random(#list)]
		end
		st.lastLine = line
		return line
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
		return best, bd, bhrp
	end
	local function turnToward(rec, pos)
		local model, hrp = rec.model, rec.hrp
		if model:GetAttribute("Roamer") or model:GetAttribute("Strapped") or model:GetAttribute("GrabbedBy") then
			return
		end
		if (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 1.5 then
			return -- a wanderer on its way somewhere: the walk decides which way it faces
		end
		local flat = (pos - hrp.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < 1.5 then
			return
		end
		local rot = CFrame.lookAt(Vector3.zero, flat).Rotation
		task.spawn(function()
			for _ = 1, 9 do
				if not model.Parent or model:GetAttribute("Ragdolled") or hrp.Anchored then
					return
				end
				hrp.CFrame = CFrame.new(hrp.Position) * hrp.CFrame.Rotation:Lerp(rot, 0.32)
				task.wait(0.03)
			end
		end)
	end

	local state = setmetatable({}, { __mode = "k" })
	local globalNext = 0
	local function say(model, st, text)
		local now = os.clock()
		st.said = now
		globalNext = now + 0.4
		net("say", model, text)
	end
	S.say = function(model, text) -- for other modules and for testing
		local st = state[model]
		if st then
			say(model, st, text)
		end
	end
	local function hook(model, rec, st)
		local hum = rec.hum
		local last = hum.Health
		hum.HealthChanged:Connect(function(h)
			local drop = last - h
			last = h
			local now = os.clock()
			if drop < 6 or h <= 0 or rec.dead or model:GetAttribute("Invuln") then
				return
			end
			if now - (st.hurtAt or 0) < 4 or now < globalNext or math.random() > 0.5 then
				return
			end
			local _, d = nearestPlayer(rec.hrp.Position)
			if d and d < EARSHOT then
				st.hurtAt = now
				st.next = now + 6 + math.random() * 8
				say(model, st, pick(LINES.hurt, st))
			end
		end)
		model:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if model:GetAttribute("Ragdolled") == false and not rec.dead and model.Parent then
				local now = os.clock()
				if now >= globalNext and now - (st.said or 0) > 2.5 and math.random() < 0.4 then
					local _, d = nearestPlayer(rec.hrp.Position)
					if d and d < EARSHOT then
						task.delay(0.5, function()
							if model.Parent and not rec.dead and not model:GetAttribute("Ragdolled") then
								say(model, st, pick(LINES.up, st))
							end
						end)
					end
				end
			end
		end)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local now = os.clock()
		for model, rec in pairs(Dummies.records) do
			local st = state[model]
			if not st then
				st = { next = now + 2 + math.random() * 12 }
				state[model] = st
				pcall(hook, model, rec, st)
			end
			if now >= st.next and not rec.dead and model.Parent and model:GetAttribute("React") == nil then
				local strapped = model:GetAttribute("Strapped") == true
				local down = model:GetAttribute("Ragdolled") == true
				if down and not strapped then
					st.next = now + 2 + math.random() * 3
					if model:GetAttribute("Hurt") and (model:GetAttribute("Awake") or 100) > 40 and now >= globalNext and math.random() < 0.3 then
						local _, dist = nearestPlayer(rec.hrp.Position)
						if dist and dist < EARSHOT then
							st.next = now + 7 + math.random() * 8
							say(model, st, pick(LINES.downed, st))
						end
					end
				else
					local player, dist, phrp = nearestPlayer(rec.hrp.Position)
					if not player or dist > EARSHOT then
						st.next = now + 3 + math.random() * 4 -- nobody to hear it
					elseif now < globalNext then
						st.next = now + 0.5 + math.random() * 2
					else
						st.next = now + 8 + math.random() * 12
						local r = math.random()
						local weapon = player:GetAttribute("Weapon")
						local site = siteAt(rec.hrp.Position)
						local text, face
						if strapped then
							text = pick(LINES.strapped, st)
						elseif model:GetAttribute("Subject") then
							text = pick((dist < CLOSE and r < 0.75) and LINES.subject or LINES.idle, st)
							face = dist < CLOSE
						elseif model:GetAttribute("Roamer") then
							text = pick(r < 0.7 and LINES.roamer or LINES.idle, st)
						elseif dist < CLOSE and ARMED[weapon] and r < 0.45 then
							text = pick((math.random() < 0.6 and LINES.weapon[weapon]) or LINES.armed, st)
							face = true
						elseif dist < CLOSE and r < 0.72 then
							text = pick(LINES.you, st)
							face = true
						elseif site and r < 0.88 then
							text = pick(LINES.site[site], st)
						else
							text = pick(LINES.idle, st)
						end
						if face then
							turnToward(rec, phrp.Position)
						end
						say(model, st, text)
					end
				end
			end
		end
	end)
end

return S
