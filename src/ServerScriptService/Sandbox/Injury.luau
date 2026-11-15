--!nocheck
-- ServerScriptService.Sandbox.Injury: the anatomy of every dummy. One state per body: 15 regions (the R15 parts) with
-- bone / wound / burn / severed flags, nine organs, blood volume, pulse and consciousness. Everything that hurts a
-- dummy calls Injury.hit(model, { part, pos, type, amount, attacker }) - the weapons and hazards directly, the anime
-- fighters through ServerScriptService.PvP.onBodyHit (Sandbox.Main wires it). hit() decides fractures, organ damage,
-- bleeding and severing, draws the wounds on the body, and reports what happened in plain words (Injury.onEvent).
-- A 10 Hz loop runs the vitals: bleeding (arterial bleeds do not clot, cuts do), the pulse climbing as blood is lost
-- and collapsing below ~55%, consciousness, death and its cause - and it turns a hard landing into an injury.
-- Replicated on the model as attributes: Blood, BPM, Awake (0-100), State, Cause, Anat (see encode()).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Gore = require(script.Parent:WaitForChild("Gore")) -- (2026-11-14) the blood that leaves a body
local Wounds = require(script.Parent:WaitForChild("Wounds")) -- (2026-11-14) the wounds drawn on it

local Injury = {}
local states = {}
Injury.states = states
Injury.onEvent = nil -- (model, text, severity 1-4, attackerUserId?)
Injury.ragdoll = nil -- (model, duration?) set by Main: RagdollService.Ragdoll
Injury.onHarm = nil -- (model, pos, attacker?, kind, amount): every hit and severing. Sandbox.Wanderers finds the witnesses.

local C = Color3.fromRGB
local BLOOD, BLOOD_DARK, BONE = C(132, 10, 16), C(88, 6, 10), C(232, 224, 204)
local ORDER = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local ORGANS = { "brain", "heart", "lungL", "lungR", "liver", "stomach", "gut", "aorta", "spine" }
Injury.ORDER, Injury.ORGANS = ORDER, ORGANS
local REG = {
	Head = { label = "head", bone = "Skull", cut = "Decapitated", bleed = 14, chain = { "Head" } },
	UpperTorso = { label = "chest", bone = "Ribs" },
	LowerTorso = { label = "abdomen", bone = "Pelvis" },
}
for _, S in ipairs({ "Left", "Right" }) do
	local s = string.lower(S)
	REG[S .. "UpperArm"] = { label = s .. " upper arm", bone = S .. " humerus", cut = S .. " arm severed at the shoulder", artery = S .. " brachial artery severed", bleed = 3.4,
		chain = { S .. "UpperArm", S .. "LowerArm", S .. "Hand" } }
	REG[S .. "LowerArm"] = { label = s .. " forearm", bone = S .. " radius and ulna", cut = S .. " forearm severed", bleed = 2.2, chain = { S .. "LowerArm", S .. "Hand" } }
	REG[S .. "Hand"] = { label = s .. " hand", bone = S .. " wrist", cut = S .. " hand severed", bleed = 1.2, chain = { S .. "Hand" } }
	REG[S .. "UpperLeg"] = { label = s .. " thigh", bone = S .. " femur", cut = S .. " leg severed at the hip", artery = S .. " femoral artery severed", bleed = 5.2, leg = true,
		chain = { S .. "UpperLeg", S .. "LowerLeg", S .. "Foot" } }
	REG[S .. "LowerLeg"] = { label = s .. " shin", bone = S .. " tibia", cut = S .. " leg severed at the knee", bleed = 2.6, leg = true, chain = { S .. "LowerLeg", S .. "Foot" } }
	REG[S .. "Foot"] = { label = s .. " foot", bone = S .. " ankle", cut = S .. " foot severed", bleed = 1.2, leg = true, chain = { S .. "Foot" } }
end
Injury.REG = REG
local MUL = { blunt = 1, slash = 1.1, pierce = 0.8, bullet = 0.9, blast = 1.2, crush = 1.6, burn = 0.7, shock = 0.5 }
local FX_MIN = { blunt = 34, crush = 26, blast = 44, bullet = 999 }
local CAUSE = { blunt = "Blunt force trauma", slash = "Massive lacerations", pierce = "Stab wounds", bullet = "Gunshot wounds", blast = "Blast injuries",
	crush = "Crush injuries", burn = "Severe burns", shock = "Electrocution" }

local gore = Gore.folder
Injury.gore = gore

local function say(st, text, sev, by)
	st.lastEvent = text
	if Injury.onEvent then
		Injury.onEvent(st.model, text, sev or 1, by and by.UserId or st.lastBy)
	end
end

local function encode(st)
	local parts = {}
	for i, name in ipairs(ORDER) do
		local r = st.regions[name]
		parts[i] = tostring(math.floor(r.hp + 0.5)) .. (r.fx and "f" or "") .. (r.sev and "s" or "") .. ((r.burn or 0) >= 40 and "b" or "") .. ((r.cuts or 0) > 0 and "c" or "") .. ((r.holes or 0) > 0 and "p" or "")
	end
	local org = {}
	for i, k in ipairs(ORGANS) do
		org[i] = tostring(math.floor(st.organs[k] + 0.5))
	end
	return table.concat(parts, "|") .. ";" .. table.concat(org, ",")
end

local function stateOf(st)
	if st.dead then
		return "Dead"
	elseif st.awake < 25 then
		return "Unconscious"
	elseif st.blood < 62 or st.heartStopAt then
		return "Critical"
	elseif st.bleedA + st.bleedM > 0.25 then
		return "Bleeding"
	elseif st.touched then
		return "Injured"
	end
	return "Healthy"
end

local function push(st, force)
	local m = st.model
	if not m.Parent then
		return
	end
	local b, p, a = math.floor(st.blood + 0.5), math.floor(st.bpm + 0.5), math.floor(st.awake + 0.5)
	if m:GetAttribute("Blood") ~= b then m:SetAttribute("Blood", b) end
	if m:GetAttribute("BPM") ~= p then m:SetAttribute("BPM", p) end
	if m:GetAttribute("Awake") ~= a then m:SetAttribute("Awake", a) end
	local s = stateOf(st)
	if m:GetAttribute("State") ~= s then m:SetAttribute("State", s) end
	if st.dirty or force then
		st.dirty = false
		m:SetAttribute("Anat", encode(st))
	end
end

function Injury.register(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local st = { model = model, hum = hum, regions = {}, organs = {}, blood = 100, bleedA = 0, bleedM = 0, bpm = 68 + math.random(0, 12), awake = 100, pain = 0,
		dead = false, marks = {}, base = {}, lastSaid = {} }
	for _, n in ipairs(ORDER) do
		st.regions[n] = { hp = 100 }
		local p = model:FindFirstChild(n)
		if p then
			st.base[n] = p.Color
		end
	end
	for _, k in ipairs(ORGANS) do
		st.organs[k] = 100
	end
	states[model] = st
	model:SetAttribute("Cause", "")
	push(st, true)
	return st
end
function Injury.forget(model)
	states[model] = nil
end
function Injury.get(model)
	return states[model]
end

---------------------------------------------------------------------------------------------------------- visuals
-- (2026-11-14, owner: "make the injuries and blood spill and such on the npcs a lot more realistic and gore-y") the
-- wounds drawn on the body are Sandbox.Wounds now, the blood that leaves it Sandbox.Gore (droplets that land and
-- stain, puddles that grow with the blood lost, scraps). These two keep the names the hazards and machines call.
local spurt, pool = Gore.spurt, Gore.pool
Injury.spurt, Injury.pool = spurt, pool
-- An artery that is open sprays in time with the pulse: hard while there is blood to lose, weaker as it runs out,
-- nothing once the heart has stopped. The vitals loop fires each beat for every entry in st.pumps.
local function pump(st, onPart, pos, dir, strength)
	if not onPart or not onPart.Parent then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "Artery"
	att.Parent = onPart
	att.WorldCFrame = CFrame.lookAt(pos, pos + dir)
	local P = { att = att, e = Gore.emitter(att, 19, 9), s = strength or 1, born = os.clock(), n = 0 }
	st.pumps = st.pumps or {}
	table.insert(st.pumps, P)
	return P
end
local function beat(P, f)
	P.e.Speed = NumberRange.new(4 + 6 * f, 7 + 15 * f)
	P.e:Emit(3 + math.floor(11 * f))
	P.n += 1
	if P.n % 2 == 1 and os.clock() - P.born < 14 then -- every other beat throws drops that land and stain
		Gore.spray(P.att.WorldPosition, P.att.WorldCFrame.LookVector, { n = f > 0.55 and 2 or 1, particles = 0, speed = 7 + 15 * f, spread = 11, size = 0.42 })
	end
end
local function tint(st, name)
	local p = st.model:FindFirstChild(name)
	local r, base = st.regions[name], st.base[name]
	if not p or not base then
		return
	end
	local col = base:Lerp(C(112, 62, 100), math.clamp((r.bruise or 0) / 120, 0, 1) * 0.2) -- (2026-11-14) blunt damage only, and faint: the bruises are Sandbox.Wounds' patches (this used to turn any hurt limb lilac)
	col = col:Lerp(C(124, 14, 18), math.clamp(r.wet or 0, 0, 1) * 0.14) -- (2026-11-14) a little: the red patches are Sandbox.Wounds' (more than this turned a white body pink)
	col = col:Lerp(C(86, 10, 14), math.clamp(r.pulp or 0, 0, 1) * 0.78) -- (a crushed head)
	col = col:Lerp(C(34, 28, 26), math.clamp((r.burn or 0) / 110, 0, 0.85))
	p.Color = col
end

------------------------------------------------------------------------------------------------------------ death
local function die(st, cause)
	if st.dead then
		return
	end
	st.dead = true
	st.cause = cause
	st.bpm, st.awake = 0, 0
	st.model:SetAttribute("Cause", cause)
	push(st, true)
	say(st, "DEAD - " .. cause, 4)
	-- (2026-11-14) what was still in it drains out where it comes to rest
	if st.bleedA + st.bleedM > 0.4 or st.blood < 80 then
		local model, amount = st.model, 5 + (st.bleedA + st.bleedM) * 2
		task.delay(1.6, function()
			local low = model.Parent and (model:FindFirstChild("LowerTorso") or model:FindFirstChild("UpperTorso"))
			if low then
				st.poolRec = Gore.feed(st.poolRec, low.Position, amount)
			end
		end)
	end
	if st.hum and st.hum.Health > 0 then
		st.hum.Health = 0
	end
end
-- the humanoid ran out of health first (raw damage): name the cause from the last thing that hit it
function Injury.humDied(model)
	local st = states[model]
	if st and not st.dead then
		die(st, st.fatal or CAUSE[st.lastType or "blunt"] or "Massive trauma")
	end
end
-- (2026-11-13) the owner: "the characters who are injured are somehow standing up? fix that". Measured: any weapon hit
-- only knocked a body down on a TIMER, so six of six got up 1.5-2 s after a bat / katana / sledgehammer, bleeding or
-- not. The attribute Hurt is set by the first blow that does damage, and RagdollService will not stand a Hurt body
-- up again. A body that was never hurt (put down after a grab, tripped, napping) still gets up.
local function hurt(st)
	if not st.hurt then
		st.hurt = true
		st.model:SetAttribute("Hurt", true)
	end
end
local function down(st)
	if not st.down then
		st.down = true
		if Injury.ragdoll then
			Injury.ragdoll(st.model, nil)
		end
	end
end

---------------------------------------------------------------------------------------------------------- severing
function Injury.sever(model, partName, by, dir, kind, opts)
	if model:GetAttribute("Invuln") or model:GetAttribute("Boss") then
		return false
	end
	local st = states[model]
	local R = REG[partName]
	local part = model:FindFirstChild(partName)
	if not st or not R or not R.chain or not part or st.regions[partName].sev then
		return false
	end
	if Injury.onHarm then
		pcall(Injury.onHarm, model, part.Position, by, "sever", 60)
	end
	hurt(st)
	local wasDead = st.dead
	local jointPos, parentPart
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("AnimationConstraint") or c:IsA("BallSocketConstraint") then
			for _, a in ipairs({ c.Attachment0, c.Attachment1 }) do
				if a and a.Parent and a.Parent:IsA("BasePart") then
					if a.Parent == part then
						jointPos = jointPos or a.WorldPosition
					else
						parentPart = a.Parent
					end
				end
			end
			c:Destroy()
		end
	end
	jointPos = jointPos or part.Position
	local axis = part.Position - jointPos
	axis = axis.Magnitude > 0.05 and axis.Unit or -part.CFrame.UpVector
	local piece = Instance.new("Model")
	piece.Name = "Severed"
	for _, n in ipairs(R.chain) do
		local p = model:FindFirstChild(n)
		if p then
			st.regions[n].sev = true
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("AnimationConstraint") then
					c.Enabled = false
				end
			end
			p.Parent = piece
			p.CanCollide, p.Massless = true, false
			p.CollisionGroup = "Ragdolls"
			p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.1)
		end
	end
	piece.Parent = gore()
	-- (2026-11-14) both cut ends are dressed: torn muscle, fat, the bone standing proud, skin hanging (Sandbox.Wounds)
	local dia = math.min(part.Size.X, part.Size.Z) * 0.9
	local stump = Wounds.stump(parentPart, jointPos, axis, dia)
	Wounds.stump(part, jointPos, -axis, dia)
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	local push = (dir or Vector3.zero) * 14 + Vector3.new(math.random(-6, 6), 12, math.random(-6, 6))
	for _, p in ipairs(piece:GetChildren()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity += push
		end
	end
	if typeof(by) == "Instance" and by:IsA("Player") then -- (2026-11-13) the limb flies on the attacker's screen at once, like the body
		for _, p in ipairs(piece:GetChildren()) do
			if p:IsA("BasePart") then
				pcall(function()
					p:SetNetworkOwner(by)
				end)
			end
		end
	end
	-- the cut itself: a burst both ways, scraps (more when it was torn off than cut), a puddle
	local torn = kind == "blast" or kind == "crush"
	local vapor = opts and opts.vapor -- (2026-11-14, power wounds) erased or burnt away: nothing is thrown, little is spilt
	if vapor then
		piece:Destroy()
		Gore.spray(jointPos, axis + Vector3.new(0, 0.3, 0), { n = 1, particles = 8, speed = 9, spread = 40, size = 0.35, mist = true })
	else
		Gore.spray(jointPos, axis + Vector3.new(0, 0.35, 0), { n = 8, particles = 30, speed = 22, spread = 30, size = 0.7, mist = true })
		Gore.spray(jointPos, -axis + Vector3.new(0, 0.3, 0), { n = 3, particles = 10, speed = 12, spread = 35, size = 0.5 })
		Gore.gibs(jointPos, (dir or Vector3.zero) + axis * 0.5, torn and 5 or 2)
		Gore.sfx("wet", jointPos, 0.5, 1.5)
		pool(jointPos, 2.6 + math.random() * 1.2)
	end
	-- the stump pumps with the heart (the vitals loop), for as long as there is a heart beating
	local P = stump and not wasDead and pump(st, stump, jointPos, axis, math.clamp(R.bleed / 3.4, 0.5, 1.5)) or nil
	-- the limb that came off drips where it tumbles and leaves a puddle where it comes to rest
	for _, t in ipairs({ 0.45, 1, 1.8 }) do
		task.delay(t, function()
			if part.Parent then
				Gore.drop(part.Position, 0.5, part.AssemblyLinearVelocity)
			end
		end)
	end
	task.delay(3.2, function()
		if part.Parent then
			pool(part.Position, 1.4 + math.random())
		end
	end)
	Debris:AddItem(piece, 75)
	st.dirty = true
	if not st.dead then
		say(st, R.cut, partName == "Head" and 4 or 3, by)
		st.bleedA += R.bleed
		if R.artery then
			say(st, R.artery, 3, by)
		end
		st.pain = 100
		if partName == "Head" then
			st.fatal = "Decapitation"
			die(st, "Decapitation")
		elseif R.leg then
			down(st)
		end
	end
	if P and st.dead then
		for i = 1, 6 do -- the heart has a few beats left in it
			task.delay(i * 0.33, function()
				if P.att.Parent then
					beat(P, 1 - i / 7.5)
				end
			end)
		end
	end
	return true, stump
end

-- (2026-11-14, power wounds) CUT IN TWO at the waist (a world-cutting slash, a black Getsuga). The two halves stay in
-- the model - both are still its body - but nothing joins them any more.
function Injury.bisect(model, by, dir)
	local st = states[model]
	local up, low = model:FindFirstChild("UpperTorso"), model:FindFirstChild("LowerTorso")
	if not st or not up or not low or st.bisected or model:GetAttribute("Invuln") or model:GetAttribute("Boss") then
		return false
	end
	local jointPos
	for _, c in ipairs(up:GetChildren()) do
		if c:IsA("AnimationConstraint") or c:IsA("BallSocketConstraint") then
			local a0, a1 = c.Attachment0, c.Attachment1
			if (a0 and a0.Parent == low) or (a1 and a1.Parent == low) then
				local mine = (a0 and a0.Parent == up) and a0 or a1
				jointPos = jointPos or (mine and mine.WorldPosition)
				c:Destroy()
			end
		end
	end
	if not jointPos then
		return false
	end
	st.bisected = true
	if Injury.onHarm then
		pcall(Injury.onHarm, model, jointPos, by, "sever", 90)
	end
	hurt(st)
	local wasDead = st.dead
	local axis = up.Position - jointPos
	axis = axis.Magnitude > 0.05 and axis.Unit or up.CFrame.UpVector
	local dia = math.min(up.Size.X, up.Size.Z) * 1.15
	local stump = Wounds.stump(low, jointPos, axis, dia)
	Wounds.stump(up, jointPos, -axis, dia)
	local flat = (dir or Vector3.zero) * Vector3.new(1, 0, 1)
	pcall(function()
		up:SetNetworkOwner(nil)
	end)
	up.AssemblyLinearVelocity += flat * 16 + Vector3.new(math.random(-4, 4), 15, math.random(-4, 4))
	up.AssemblyAngularVelocity += Vector3.new(math.random(-6, 6), math.random(-3, 3), math.random(-6, 6))
	Gore.spray(jointPos, axis + Vector3.new(0, 0.3, 0), { n = 9, particles = 36, speed = 22, spread = 55, size = 0.75, mist = true })
	Gore.spray(jointPos, -axis + flat * 0.4, { n = 5, particles = 16, speed = 13, spread = 50, size = 0.6 })
	Gore.gibs(jointPos, flat + axis * 0.4, 3)
	Gore.sfx("wet", jointPos, 0.6, 1.3)
	pool(jointPos, 3.4 + math.random() * 1.4)
	local P = stump and not wasDead and pump(st, stump, jointPos, axis, 1.5) or nil
	st.dirty = true
	if not st.dead then
		say(st, "Cut in two at the waist", 4, by)
		st.bleedA += 16
		st.pain = 100
		st.fatal = "Bisected"
		die(st, "Bisected")
	end
	if P then
		for i = 1, 6 do
			task.delay(i * 0.33, function()
				if P.att.Parent then
					beat(P, 1 - i / 7.5)
				end
			end)
		end
	end
	return true
end

------------------------------------------------------------------------------------------------------- organ damage
local ORGAN_TEXT = {
	lungL = { 60, "Left lung punctured", 3, 1.3 }, lungR = { 60, "Right lung punctured", 3, 1.3 }, liver = { 60, "Liver lacerated", 3, 2.2 },
	stomach = { 60, "Stomach perforated", 2, 0.5 }, gut = { 60, "Intestines perforated", 2, 0.5 },
}
local function organ(st, key, dmg, by)
	local o = st.organs
	local before = o[key]
	if before <= 0 or st.dead then
		return
	end
	local now = math.max(0, before - dmg)
	o[key] = now
	st.dirty = true
	if key == "brain" then
		if now <= 0 then
			say(st, "Brain destroyed", 4, by)
			die(st, "Catastrophic brain injury")
		elseif now < 40 and before >= 40 then
			say(st, "Traumatic brain injury", 3, by)
			st.awakeCap = 15
		elseif now < 75 and before >= 75 then
			say(st, "Concussion", 2, by)
			st.awakeCap = 70
		end
	elseif key == "heart" then
		if now <= 0 then
			say(st, "Heart ruptured", 4, by)
			st.bleedA += 7
			st.fatal = "Cardiac rupture"
			st.heartStopAt = os.clock() + 2.5
		elseif before >= 100 then
			say(st, "Cardiac contusion", 3, by)
			st.bleedA += 0.8
		end
	elseif key == "aorta" then
		if now <= 35 and before > 35 then
			say(st, "Aorta ruptured", 4, by)
			st.bleedA += 10
			st.fatal = "Aortic rupture - bled out"
		end
	elseif key == "spine" then
		if now <= 40 and before > 40 then
			say(st, "Spinal cord severed - paralysed", 3, by)
			down(st)
		end
	else
		local T = ORGAN_TEXT[key]
		if T and now < T[1] and before >= T[1] then
			say(st, T[2], T[3], by)
			st.bleedA += T[4]
			if key == "lungL" or key == "lungR" then
				st.lungsDown = (st.lungsDown or 0) + 1
			end
		end
	end
end
local function pick(weights)
	local total = 0
	for _, w in ipairs(weights) do
		total += w[2]
	end
	local r = math.random() * total
	for _, w in ipairs(weights) do
		r -= w[2]
		if r <= 0 then
			return w[1]
		end
	end
	return weights[1][1]
end
local CHEST = { { "lungL", 0.32 }, { "lungR", 0.32 }, { "heart", 0.22 }, { "aorta", 0.14 } }
local BELLY = { { "liver", 0.3 }, { "stomach", 0.25 }, { "gut", 0.3 }, { "spine", 0.15 } }

---------------------------------------------------------------------------------------------------------------- hit
local function once(st, key, secs)
	local t = os.clock()
	if (st.lastSaid[key] or 0) > t then
		return false
	end
	st.lastSaid[key] = t + (secs or 3)
	return true
end
function Injury.hit(model, info)
	if model:GetAttribute("Invuln") then -- (2026-11-13) a DIAMOND test subject (Sandbox.Mutations) cannot be hurt
		return
	end
	-- (2026-11-15, shop EVENTS) the GIANT BOSS DUMMY (ServerScriptService.PerkMapEvents.BossDummy) has a health pool, not
	-- an anatomy: a hit is plain damage, and no wound, fracture, bleed or severing can kill it early
	if model:GetAttribute("Boss") then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if typeof(info.attacker) == "Instance" and info.attacker:IsA("Player") then
			model:SetAttribute("LastHitBy", info.attacker.UserId)
		end
		if hum and hum.Health > 0 then
			hum:TakeDamage(math.max(tonumber(info.amount) or 0, 0))
		end
		return
	end
	local st = states[model]
	if not st then
		return
	end
	local part = info.part
	if typeof(part) == "string" then
		part = model:FindFirstChild(part)
	end
	if part and part.Parent ~= model and part.Parent and REG[part.Parent.Name] and part.Parent.Parent == model then
		part = part.Parent -- a wound or stump on the limb
	end
	if not part or part.Parent ~= model or not REG[part.Name] then
		part = model:FindFirstChild("UpperTorso")
		if not part then
			return
		end
	end
	local name = part.Name
	local r, R = st.regions[name], REG[name]
	local kind, a, by = info.type or "blunt", math.max(0, info.amount or 10), info.attacker
	local pos = info.pos or part.Position
	if by then
		st.lastBy = by.UserId
		model:SetAttribute("LastHitBy", by.UserId)
	end
	if Injury.onHarm then
		pcall(Injury.onHarm, model, pos, by, kind, a)
	end
	st.lastType, st.touched, st.dirty = kind, true, true
	if a > 0 then
		hurt(st)
	end
	r.hp = math.max(0, r.hp - a * (MUL[kind] or 1))
	st.pain = math.min(100, st.pain + a * 0.5)
	local dir = info.dir or Vector3.zero
	local alive = not st.dead
	-- wounds you can see (Sandbox.Wounds) and the blood they throw (Sandbox.Gore). A body hit many times a second (an
	-- SMG, a saw) gets a limb's full dressing at most ~8 times a second and a spray ~12 times.
	local nowT = os.clock()
	-- (2026-11-14, power wounds) info.nodraw: the caller (Sandbox.Powers) draws this wound itself; info.nospray: and
	-- its blood; info.nosever: a blow that never takes the limb off, however hard
	local full = not info.nodraw and nowT - (r.fxAt or 0) >= 0.12
	if full then
		r.fxAt = nowT
	end
	local wet = not info.nospray and nowT - (st.sprayAt or 0) >= 0.08
	if wet then
		st.sprayAt = nowT
	end
	local flat = dir.Magnitude > 0.1 and dir.Unit or Vector3.zero
	if kind == "slash" then
		if full then
			Wounds.gash(st, part, pos, a)
		end
		r.cuts = (r.cuts or 0) + 1
		r.wet = math.min(1, (r.wet or 0) + a / 110)
		if wet then -- thrown off the blade: along the cut, and up
			Gore.spray(pos, flat * 0.8 + Vector3.new((math.random() - 0.5) * 0.9, 0.45, (math.random() - 0.5) * 0.9), { n = math.clamp(math.floor(a / 9), 2, 7),
				particles = math.clamp(math.floor(a / 3), 6, 22), speed = 13 + a * 0.12, spread = 30, size = 0.55, mist = a >= 30 })
		end
		if alive then
			st.bleedM += a * 0.02
			if once(st, name .. "cut", 4) then
				say(st, (a >= 26 and "Deep laceration: " or "Laceration: ") .. R.label, a >= 26 and 2 or 1, by)
			end
		end
	elseif kind == "pierce" or kind == "bullet" then
		if not info.nodraw then
			Wounds.hole(st, part, pos, a, not full)
		end
		r.holes = (r.holes or 0) + 1
		r.wet = math.min(1, (r.wet or 0) + a / 140)
		if wet then -- a little comes back out the way it went in
			Gore.spray(pos, -flat + Vector3.new(0, 0.25, 0), { n = 1, particles = math.clamp(math.floor(a / 6), 3, 9), speed = 9, spread = 38, size = 0.3, mist = true })
		end
		-- a bullet that goes through: a bigger, torn hole where it leaves, and what it carries out lands behind the body
		if kind == "bullet" and full and flat.Magnitude > 0.5 and ((R.chain and name ~= "Head") or math.random() < math.clamp(a / 45, 0.35, 0.9)) then
			local out = Wounds.exit(st, part, pos, flat, a)
			if out then
				Gore.spray(out, flat + Vector3.new(0, 0.12, 0), { n = math.clamp(math.floor(a / 7), 2, 8), particles = math.clamp(math.floor(a / 2.5), 8, 26),
					speed = 20 + a * 0.2, spread = 15, size = 0.45, mist = true })
			end
		end
		if alive then
			st.bleedM += a * 0.024
			if once(st, name .. kind, 3) then
				say(st, (kind == "bullet" and "Gunshot wound: " or "Stab wound: ") .. R.label, 2, by)
			end
		end
	elseif kind == "burn" or kind == "shock" then
		if a >= 8 and full then
			Wounds.burn(st, part, pos, a)
		end
		local before = r.burn or 0
		r.burn = before + a * (kind == "shock" and 0.6 or 1)
		if alive and r.burn >= 90 and before < 90 then
			say(st, "Third-degree burns: " .. R.label, 3, by)
		elseif alive and r.burn >= 40 and before < 40 then
			say(st, (kind == "shock" and "Electrical burns: " or "Second-degree burns: ") .. R.label, 2, by)
		end
		if alive and kind == "shock" and a >= 40 and math.random() < a / 220 and not st.heartStopAt then
			say(st, "Ventricular fibrillation", 4, by)
			st.fatal = "Electrocution - cardiac arrest"
			st.heartStopAt = os.clock() + 3
		end
	else -- blunt / crush / blast
		r.bruise = (r.bruise or 0) + a
		if a >= 12 and full then
			Wounds.bruise(st, part, pos, a)
		end
		-- a blow hard enough splits the skin (and so does a lighter one on a limb already beaten soft)
		if full and (a >= 34 or (kind == "crush" and a >= 20) or (r.hp <= 40 and a >= 18)) then
			Wounds.gash(st, part, pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.3, a * 0.5, true)
			r.wet = math.min(1, (r.wet or 0) + a / 200)
			if alive then
				st.bleedM += a * 0.006
			end
			if wet then
				Gore.spray(pos, -flat * 0.3 + Vector3.new(math.random() - 0.5, 0.7, math.random() - 0.5), { n = math.clamp(math.floor(a / 22), 1, 4),
					particles = math.clamp(math.floor(a / 6), 4, 14), speed = 11 + a * 0.06, spread = 40, size = 0.45 })
			end
		end
		if kind == "blast" and a >= 30 then
			if full then
				Wounds.burn(st, part, pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5), a * 0.6)
			end
			r.burn = (r.burn or 0) + a * 0.35
		end
		if alive and a >= 15 and not r.fx and once(st, name .. "bruise", 5) then
			say(st, "Contusion: " .. R.label, 1, by)
		end
	end
	tint(st, name)
	if alive then
		-- bones
		if not r.fx and (a >= (FX_MIN[kind] or 999) or ((kind == "blunt" or kind == "crush" or kind == "blast") and r.hp <= 42) or (kind == "bullet" and math.random() < 0.3)) then
			r.fx = true
			say(st, R.bone .. " fractured", (name == "Head" or name == "LowerTorso") and 3 or 2, by)
			-- (2026-11-14) an open fracture: the broken end comes out through the skin
			if R.chain and name ~= "Head" and (kind == "blunt" or kind == "crush" or kind == "blast") and math.random() < (kind == "crush" and 0.7 or 0.4) then
				local at, out = Wounds.boneOut(st, part)
				say(st, "Open fracture: " .. R.label, 3, by)
				st.bleedM += 0.7
				r.wet = math.min(1, (r.wet or 0) + 0.3)
				tint(st, name)
				Gore.spray(at, out + Vector3.new(0, 0.4, 0), { n = 2, particles = 8, speed = 10, spread = 35, size = 0.4 })
			end
			if R.leg or name == "LowerTorso" then
				down(st)
			end
			if name == "UpperTorso" and a >= 46 and math.random() < 0.4 then
				organ(st, pick({ { "lungL", 1 }, { "lungR", 1 } }), 55, by)
			end
		end
		-- organs
		if name == "Head" then
			if kind == "pierce" or kind == "bullet" then
				if once(st, "skullpen", 6) then
					say(st, "Skull penetrated", 3, by)
				end
				organ(st, "brain", a * 2.6, by)
			elseif kind == "crush" and a >= 70 then
				say(st, "Skull crushed", 4, by)
				organ(st, "brain", 200, by)
				if Wounds.crushHead(st, part) then -- (2026-11-14) it shows: the head gives way, and what comes out of it
					Gore.spray(part.Position, Vector3.yAxis, { n = 7, particles = 26, speed = 17, spread = 70, size = 0.65, mist = true })
					Gore.gibs(part.Position, dir, 3)
					Gore.sfx("wet", part.Position, 0.6, 1.4)
					r.wet, r.pulp = 1, 1
					tint(st, name)
				end
			elseif kind == "blunt" or kind == "crush" or kind == "blast" then
				organ(st, "brain", a * 0.8, by)
			elseif kind == "slash" and a >= 30 and math.random() < 0.35 and not st.carotid then
				st.carotid = true
				say(st, "Carotid artery severed", 4, by)
				-- (2026-11-14) the side of the neck sprays in time with the pulse
				pump(st, part, part.CFrame:PointToWorldSpace(Vector3.new(part.Size.X * 0.3, -part.Size.Y * 0.42, 0)), (part.CFrame.RightVector + Vector3.yAxis * 0.5).Unit, 1)
				st.bleedA += 6.5
				st.fatal = "Carotid artery severed - bled out"
			end
		elseif name == "UpperTorso" or name == "LowerTorso" then
			local table_ = (name == "UpperTorso") and CHEST or BELLY
			if kind == "pierce" or kind == "bullet" then
				if math.random() < math.clamp(a / 55, 0.3, 0.92) then
					organ(st, pick(table_), a * (kind == "bullet" and 2.3 or 1.9), by)
				end
			elseif kind == "slash" and a >= 40 then
				if math.random() < 0.45 then
					organ(st, pick(table_), a * 1.3, by)
				end
			elseif (kind == "crush" and a >= 55) or (kind == "blast" and a >= 65) then
				organ(st, pick(table_), a * 1.1, by)
				if math.random() < 0.5 then
					organ(st, pick(table_), a * 0.8, by)
				end
			elseif kind == "blunt" and a >= 60 and name == "UpperTorso" and math.random() < 0.25 then
				organ(st, "heart", 30, by)
			end
		end
	end
	-- severing (the dead can still be taken apart)
	if R.chain and not r.sev and not info.nosever then
		if name == "Head" then
			if (kind == "slash" and a >= 50) or (kind == "blast" and a >= 110) then
				Injury.sever(model, name, by, dir, kind)
			end
		elseif (kind == "slash" and a >= 36 and (r.hp <= 0 or a >= 52)) or (kind == "blast" and a >= 78 and math.random() < 0.55) or (kind == "crush" and a >= 120) then
			Injury.sever(model, name, by, dir, kind)
		end
	end
	if alive and not st.dead then
		push(st)
	end
end
-- (2026-11-14, power wounds) what Sandbox.Powers needs from in here
function Injury.organ(model, key, dmg, by)
	local st = states[model]
	if st and st.organs[key] then
		organ(st, key, dmg, by)
	end
end
function Injury.say(model, text, sev, by)
	local st = states[model]
	if st and not st.dead then
		say(st, text, sev, by)
	end
end
function Injury.kill(model, cause)
	local st = states[model]
	if st and not st.dead then
		st.fatal = cause
		die(st, cause)
	end
end
function Injury.down(model)
	local st = states[model]
	if st then
		down(st)
	end
end
function Injury.tint(model, name)
	local st = states[model]
	if st and st.regions[name] then
		tint(st, name)
		st.dirty = true
	end
end
-- a blast: the nearest regions take it, falling off with distance (hazards + explosive fighters' moves)
function Injury.blast(model, center, radius, amount, by)
	if model:GetAttribute("Invuln") then
		return 0
	end
	if model:GetAttribute("Boss") then -- (2026-11-15) the boss: the caller turns this into plain damage
		return (tonumber(amount) or 0) * 0.5
	end
	local st = states[model]
	if not st then
		return 0
	end
	local best = 0
	local hits = 0
	local list = {}
	for _, n in ipairs(ORDER) do
		local p = model:FindFirstChild(n)
		if p then
			table.insert(list, { p, (p.Position - center).Magnitude })
		end
	end
	table.sort(list, function(x, y)
		return x[2] < y[2]
	end)
	for i = 1, math.min(#list, 4) do
		local p, d = list[i][1], list[i][2]
		local f = 1 - math.clamp(d / radius, 0, 1)
		if f > 0.05 then
			local amt = amount * f * (i == 1 and 1 or 0.6)
			best = math.max(best, amt)
			Injury.hit(model, { part = p, pos = p.Position + (center - p.Position).Unit * 0.5, type = "blast", amount = amt, attacker = by, dir = (p.Position - center).Unit })
			hits += 1
		end
	end
	return best
end

------------------------------------------------------------------------------------------------------------ vitals
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then
		return
	end
	local step = acc
	acc = 0
	local now = os.clock()
	for model, st in pairs(states) do
		if not model.Parent then
			states[model] = nil
		else
			-- hard landings: a ragdolled body that loses a lot of speed in one step has hit something
			local torso = model:FindFirstChild("UpperTorso")
			if torso and model:GetAttribute("Ragdolled") and not model:GetAttribute("GrabbedBy") and not model:GetAttribute("Strapped") then
				local sp = torso.AssemblyLinearVelocity.Magnitude
				local prior = math.min(st.lastSpeed or sp, st.lastSpeed2 or sp) -- fast for two samples running...
				local drop = prior - sp -- ...and then stopped
				st.lastSpeed2 = st.lastSpeed
				st.lastSpeed = sp
				if drop > 52 and now - (st.impactAt or 0) > 0.5 then
					st.impactAt = now
					local amt = math.min(95, (drop - 52) * 0.6 + 14)
					local where = pick({ { "Head", 0.18 }, { "UpperTorso", 0.3 }, { "LowerTorso", 0.2 }, { "LeftUpperLeg", 0.08 }, { "RightUpperLeg", 0.08 }, { "LeftUpperArm", 0.08 }, { "RightUpperArm", 0.08 } })
					local uid = model:GetAttribute("LastHitBy")
					Injury.hit(model, { part = where, type = "blunt", amount = amt, attacker = uid and Players:GetPlayerByUserId(uid) or nil })
					if st.hum and st.hum.Health > 0 then
						st.hum:TakeDamage(amt * 0.7)
					end
				end
			else
				st.lastSpeed, st.lastSpeed2 = nil, nil
			end
			if not st.dead and (st.touched or st.blood < 100) then
				st.bleedM *= 0.5 ^ (step / 18)
				if st.bleedM < 0.03 then
					st.bleedM = 0
				end
				local bleed = st.bleedA + st.bleedM
				st.blood = math.max(0, st.blood - bleed * step)
				st.pain = math.max(0, st.pain - 5 * step)
				-- (2026-11-14) the blood that is lost goes somewhere: a puddle under a body that is still, which grows with
				-- what it has actually lost; drips under one that is being thrown or dragged
				if bleed > 0.2 and torso then
					local vel = torso.AssemblyLinearVelocity
					if vel.Magnitude < 5 then
						st.spill = (st.spill or 0) + bleed * step
						if now - (st.poolAt or 0) > 0.6 then
							st.poolAt = now
							local low = model:FindFirstChild("LowerTorso") or torso
							st.poolRec = Gore.feed(st.poolRec, low.Position, st.spill)
							st.spill = 0
						end
					elseif bleed > 0.5 and now - (st.trailAt or 0) > 0.22 then
						st.trailAt = now
						Gore.drop(torso.Position, 0.3 + math.min(bleed, 6) * 0.09, vel)
					end
				end
				local target
				if st.heartStopAt then
					target = 0
				elseif st.blood > 55 then
					target = math.min(188, 72 + math.min(st.pain, 70) * 0.55 + (100 - st.blood) * 2.1)
				else
					target = 165 - (55 - st.blood) / 19 * 140
				end
				st.bpm += (math.max(0, target) - st.bpm) * math.min(1, step * 1.4)
				-- (2026-11-14) open arteries spray on each beat: faster as the heart races, weaker as the blood runs out
				if st.pumps then
					st.beat = (st.beat or 0) + st.bpm / 60 * step
					if st.beat >= 1 then
						st.beat = st.beat % 1
						local k = math.clamp((st.blood - 38) / 45, 0.12, 1)
						for i = #st.pumps, 1, -1 do
							local P = st.pumps[i]
							if not P.att.Parent then
								table.remove(st.pumps, i)
							else
								beat(P, k * P.s * math.clamp(1.15 - (now - P.born) / 24, 0.25, 1))
							end
						end
					end
				end
				local awake = 100 - math.max(0, 66 - st.blood) * 3.2 - (st.lungsDown or 0) * 12
				awake = math.clamp(math.min(awake, st.awakeCap or 100), 0, 100)
				st.awake += (awake - st.awake) * math.min(1, step * 0.9)
				if st.awake < 25 and not st.out then
					st.out = true
					say(st, "Lost consciousness", 3)
					down(st)
				end
				if st.heartStopAt and now >= st.heartStopAt then
					die(st, st.fatal or "Cardiac arrest")
				elseif st.blood <= 38 then
					die(st, st.fatal or "Exsanguination - bled out")
				elseif (st.lungsDown or 0) >= 2 and not st.heartStopAt then
					st.fatal = "Respiratory failure"
					st.heartStopAt = now + 9
				end
				if not st.dead then
					push(st)
				end
			elseif st.dirty then
				push(st)
			end
		end
	end
end)

-- (2026-11-14) burnt all over at once (the Factory's fire pit): every region charred to at least `amount`, tinted,
-- published - with no feed line per limb (the death names the cause)
function Injury.char(model, amount)
	local st = states[model]
	if not st then
		return
	end
	for _, n in ipairs(ORDER) do
		local r = st.regions[n]
		if r then
			r.burn = math.max(r.burn or 0, amount or 200)
			tint(st, n)
		end
	end
	st.touched, st.dirty = true, true
	push(st, true)
end

return Injury
