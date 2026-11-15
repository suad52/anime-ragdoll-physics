--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- GodspeedServer: server side of the Godspeed kit (a lightning assassin). Owns cooldowns, targeting, every hit, the
-- electrocution status and the Godspeed barrage. Clients send intents through GodspeedKit.Remotes.Request and render
-- the timeline sent on Remotes.Broadcast; each caster's own client moves its own character along it.
--   Palm (Q) | Thunder (E) | Echo (R) | Godspeed (G, the ultimate). The "SetKit" switch lives in VulpineServer.KitServer.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("GodspeedKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")

-- hooks into the rest of the game: ragdolls for NPC bodies, NPC flee, breakable props
local RagdollService, Threat, WorldBlast
do
	local gs = ServerScriptService:WaitForChild("GojoServer", 10)
	local mod = gs and gs:FindFirstChild("RagdollService")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and res then
			RagdollService = res
			RagdollService.Init()
		end
	end
	Threat = gs and gs:FindFirstChild("Threat")
	WorldBlast = gs and gs:FindFirstChild("WorldBlast")
end

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

local function now()
	return workspace:GetServerTimeNow()
end

local function randomUnit()
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return v.Magnitude > 1e-3 and v.Unit or Vector3.xAxis
end

local function randomFlat()
	local a = math.random() * math.pi * 2
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function finite(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

-- a horizontal unit vector from `v`, or from `fallback` if `v` is unusable
local function flatDir(v, fallback)
	if finite(v) then
		local f = v * FLAT
		if f.Magnitude > 1e-3 then
			return f.Unit
		end
	end
	local f = (fallback or Vector3.new(0, 0, -1)) * FLAT
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

local function liveChar(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

local function torsoOf(m)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the attack (PvP.formRoot)
	return PvPBal.formRoot(m) or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
end

local function alive(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and m:GetAttribute("Dead") ~= true
end

local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) other players are targets too
-- every ragdollable NPC body in the world, plus every OTHER player's character (never the caster)
local function targets(caster)
	PvPBal.setAim(caster) -- (2026-11-08) forms are hit at their body point nearest this attacker
	local list = {}
	for _, m in ipairs(PvP.bodies(CFG.TargetTag, caster)) do
		if m:IsDescendantOf(workspace) and torsoOf(m) then
			table.insert(list, m)
		end
	end
	return list
end

-- the world only (no characters, NPCs or effects): wall clamps and ground snaps
local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshIgnore()
	local list = {}
	for _, n in ipairs({ "NPCs", "FX", "KitFX", "KitDebris", "LocalFX" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	worldParams.FilterDescendantsInstances = list
end

local function groundAt(pos, depth)
	refreshIgnore()
	local hit = workspace:Raycast(pos + UP * 6, Vector3.new(0, -(depth or 40), 0), worldParams)
	return hit and hit.Position or nil
end

-- how far you can travel from `from` along `dir` (up to `dist`) before a wall
local function clampPath(from, dir, dist)
	refreshIgnore()
	local hit = workspace:Raycast(from, dir * dist, worldParams)
	return hit and math.max((hit.Position - from).Magnitude - 2, 0) or dist
end

-- a root position for a character standing at `pos`, as high above its ground as `hrp` is above its own
local function floorBelow(p, depth)
	refreshIgnore()
	local hit = workspace:Raycast(p, Vector3.new(0, -(depth or 40), 0), worldParams)
	return hit and hit.Position or nil
end
local function standAt(hrp, pos)
	local own = floorBelow(hrp.Position, 30)
	local hip = own and (hrp.Position.Y - own.Y) or 3
	local g = floorBelow(Vector3.new(pos.X, math.max(pos.Y, hrp.Position.Y) + 1.5, pos.Z), 60)
	return g and Vector3.new(pos.X, g.Y + hip, pos.Z) or pos
end

-- nothing solid (world geometry only) between two points
local function clearLine(a, b)
	return workspace:Raycast(a, b - a, worldParams) == nil
end

local function worldHooks(p, pos, radius)
	if WorldBlast then
		WorldBlast:Fire(pos, radius, p.UserId)
	end
end

local function fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

---------------------------------------------------------------------------------------------------
-- per-player state
local state = {} -- [player] = { cd = {}, busyUntil, last, id, mode = { char, untilT }? }
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busyUntil = 0, last = 0, id = 0, mode = nil }
		state[p] = s
	end
	return s
end

local function inMode(s, char)
	return s.mode ~= nil and s.mode.char == char and now() < s.mode.untilT
end

local function sendCooldown(p, s, skill)
	Broadcast:FireClient(p, "Cooldown", { skill = skill, ends = s.cd[skill] or 0 })
end

-- alive, holding this kit, not mid-move, off cooldown
local function gate(p, s, skill)
	local char, hum, hrp = liveChar(p)
	if not char or p:GetAttribute("Kit") ~= CFG.KitId then
		return nil
	end
	if PvPBal.stunned(p) then -- (2026-11-08) stunned / knocked down in PvP: no moves
		return nil
	end
	local t = now()
	if t < s.busyUntil then
		return nil
	end
	if t < (s.cd[skill] or 0) then
		sendCooldown(p, s, skill)
		return nil
	end
	return char, hum, hrp, t
end

-- (2026-11-07 perks) the Robux cooldown perks, written by ShopService: CooldownMul on every move, UltChargeMul on the
-- ultimate (G) as well. The client shows the end time sent here, so its timer always matches
-- (2026-11-08) non-ultimate moves x PvPShared.Balance.NON_ULT_COOLDOWN_MUL ("double the cooldown on non ult abilities")
local BAL = require(game:GetService("ReplicatedStorage"):WaitForChild("PvPShared"):WaitForChild("Balance"))
local function perkMul(p, isUlt)
	local m = tonumber(p:GetAttribute("CooldownMul")) or 1
	if isUlt then
		m *= tonumber(p:GetAttribute("UltChargeMul")) or 1
	end
	if m ~= m or m <= 0 then
		m = 1
	end
	return math.clamp(m, 0.05, 4) * (isUlt and 1 or BAL.NON_ULT_COOLDOWN_MUL)
end

local function commit(p, s, skill, t, lock, char)
	local cd = CFG[skill].Cooldown
	if inMode(s, char) then
		cd *= CFG.Godspeed.CooldownMul[skill] or 1
	end
	cd *= perkMul(p, skill == "Godspeed")
	s.cd[skill] = t + cd
	s.busyUntil = t + lock
	s.id += 1
	sendCooldown(p, s, skill)
	return s.id
end

---------------------------------------------------------------------------------------------------
-- electrocution: the body is kept down and twitching while its "Shocked" attribute (a server time) is in the future
local shocked = {} -- [model] = { untilT, nextTwitch }

local function shock(model, secs)
	if not model.Parent then
		return
	end
	local rec = shocked[model]
	local untilT = math.max(rec and rec.untilT or 0, now() + secs)
	shocked[model] = { untilT = untilT, nextTwitch = 0 }
	model:SetAttribute("Shocked", untilT)
	if RagdollService then
		RagdollService.Ragdoll(model, secs + 0.4)
	end
end

-- damage + electrocution + a fling on one body (a body held by a Blue grab takes the damage but keeps still)
local function strike(p, model, vel, damage, shockSecs, ragTime)
	if not model.Parent or (p and model == p.Character) then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if damage and damage > 0 and hum and hum.Health > 0 and model:GetAttribute("Dead") ~= true then
		model:SetAttribute("LastHitBy", p.UserId)
		-- (2026-11-10, "buff Killua's damage a bit") PvPShared.Balance.KIT_DAMAGE_MUL.Godspeed, before the PvP caps
		local kitMul = type(BAL.KIT_DAMAGE_MUL) == "table" and tonumber(BAL.KIT_DAMAGE_MUL.Godspeed) or 1
		hum:TakeDamage(PvPBal.dmg(hum, damage * kitMul))
	end
	if shockSecs and shockSecs > 0 then
		shock(model, shockSecs)
	end
	if not RagdollService then
		return
	end
	local rag = math.max(ragTime or 2, shockSecs or 0)
	if vel and not model:GetAttribute("GrabbedBy") then
		RagdollService.Fling(model, vel, randomUnit() * 10, rag)
	else
		RagdollService.Ragdoll(model, rag)
	end
end

---------------------------------------------------------------------------------------------------
-- Q: Lightning Palm. A dash along the flat aim, cut short by walls and by the first body on the line, which takes the
-- palm when the dash arrives
local function castPalm(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Palm")
	if not char then
		return
	end
	local P = CFG.Palm
	local mode = inMode(s, char)
	local dir = flatDir(payload.aim, hrp.CFrame.LookVector)
	local origin = hrp.Position
	local dist = clampPath(origin, dir, P.Distance * (mode and CFG.Godspeed.PalmDistanceMul or 1))
	local best, bestAlong
	for _, m in ipairs(targets(p)) do
		if alive(m) then
			local rel = torsoOf(m).Position - origin
			local along = rel:Dot(dir)
			if along > -1 and along <= dist + P.HitRadius and math.abs(rel.Y) < 8 then
				local side = (rel - dir * along) * FLAT
				if side.Magnitude <= P.HitRadius and (not bestAlong or along < bestAlong) and clearLine(origin, origin + rel) then
					best, bestAlong = m, along
				end
			end
		end
	end
	local stop = best and math.clamp(bestAlong - 2.2, 0, dist) or dist
	local dashTime = math.max(stop / P.Speed, 0.06)
	local id = commit(p, s, "Palm", t, P.Lock + dashTime, char)
	local data = {
		id = id, userId = p.UserId, t0 = t, origin = origin, dir = dir, stop = stop, windup = P.Windup,
		dashTime = dashTime, target = best, mode = mode,
	}
	fire("PalmCast", data)
	if Threat then
		Threat:Fire(origin + dir * stop, 25, 1.2)
	end
	if best then
		task.delay(P.Windup + dashTime, function()
			local tt = best.Parent and torsoOf(best)
			if not tt or (tt.Position - (origin + dir * stop)).Magnitude > 12 then
				return -- it got away
			end
			local k = mode and CFG.Godspeed.DamageMul or 1
			strike(p, best, (dir * P.Knockback + UP * P.UpKnock) * k, P.Damage * k, P.ShockTime, 2.4)
			fire("PalmHit", { id = id, userId = p.UserId, pos = tt.Position, model = best, dir = dir })
			worldHooks(p, tt.Position, 6)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- E: Thunderbolt. A bolt from the sky on the cursor point (clamped into range, snapped to the ground)
local function castThunder(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Thunder")
	if not char then
		return
	end
	local T = CFG.Thunder
	local aimPt = finite(payload.target) and payload.target or (hrp.Position + hrp.CFrame.LookVector * 30)
	local off = (aimPt - hrp.Position) * FLAT
	local dir = off.Magnitude > 0.1 and off.Unit or flatDir(payload.aim, hrp.CFrame.LookVector)
	local d = math.clamp(off.Magnitude, T.MinRange, T.MaxRange)
	local pt = hrp.Position + dir * d
	pt = groundAt(Vector3.new(pt.X, math.max(pt.Y, aimPt.Y) + 30, pt.Z), 140) or (pt - UP * 3)
	local id = commit(p, s, "Thunder", t, T.Lock, char)
	fire("ThunderCast", { id = id, userId = p.UserId, t0 = t, point = pt, strike = T.StrikeTime, radius = T.Radius, dir = dir })
	if Threat then
		Threat:Fire(pt, T.Radius * 1.6, T.StrikeTime + 0.3)
	end
	task.delay(T.StrikeTime, function()
		local R = T.Radius
		local n = 0
		for _, m in ipairs(targets(p)) do
			PvPBal.aimAt(pt) -- (2026-11-10) a form answers at its body point nearest the strike, not the caster
			local rel = torsoOf(m).Position - pt
			local flat = rel * FLAT
			local horiz = flat.Magnitude
			if horiz <= R and math.abs(rel.Y) < R then
				local k = 1 - horiz / R
				local radial = horiz > 0.5 and flat.Unit or randomFlat()
				local v = (radial + UP * T.UpBias).Unit * T.Fling * (0.45 + 0.55 * k)
				strike(p, m, v, T.Damage * (0.6 + 0.4 * k), T.ShockTime, 3)
				n += 1
			end
		end
		worldHooks(p, pt, R * 0.6)
		fire("ThunderStrike", { id = id, userId = p.UserId, point = pt, hits = n })
	end)
end

---------------------------------------------------------------------------------------------------
-- R: Rhythm Echo. Blink behind the nearest living body in front of the caster and slash it; with nobody in reach,
-- just blink forward
local function castEcho(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Echo")
	if not char then
		return
	end
	local E = CFG.Echo
	local aim = flatDir(payload.aim, hrp.CFrame.LookVector)
	local origin = hrp.Position
	refreshIgnore()
	local best, bestScore
	for _, m in ipairs(targets(p)) do
		if alive(m) and not m:GetAttribute("GrabbedBy") then
			local rel = torsoOf(m).Position - origin
			local flat = rel * FLAT
			local d = flat.Magnitude
			if d > 0.5 and d <= E.Range and math.abs(rel.Y) < 25 then
				local ang = math.deg(math.acos(math.clamp(flat.Unit:Dot(aim), -1, 1)))
				if ang <= E.Cone then
					local score = d + ang * 0.4
					if (not bestScore or score < bestScore) and clearLine(origin, origin + rel) then
						best, bestScore = m, score
					end
				end
			end
		end
	end
	local dest, face
	if best then
		local tp = torsoOf(best).Position
		local toward = ((tp - origin) * FLAT).Unit
		local back = math.min(clampPath(tp, toward, E.BehindDist + 2), E.BehindDist)
		if back >= 1.5 then
			dest = standAt(hrp, tp + toward * back)
			face = -toward -- turned round to face the target's back
		else -- its back is to a wall: land in front of it instead
			dest = standAt(hrp, tp - toward * 2.5)
			face = toward
		end
	else
		dest = standAt(hrp, origin + aim * clampPath(origin, aim, E.NoTargetDist))
		face = aim
	end
	local id = commit(p, s, "Echo", t, E.Lock, char)
	fire("EchoCast", {
		id = id, userId = p.UserId, t0 = t, origin = origin, dest = dest, face = face, aim = aim, target = best,
		sway = E.SwayTime, slash = E.SlashTime,
	})
	if best then
		task.delay(E.SlashTime, function()
			local tt = best.Parent and torsoOf(best)
			if not tt or (tt.Position - dest).Magnitude > 14 then
				return
			end
			local k = inMode(s, char) and CFG.Godspeed.DamageMul or 1
			strike(p, best, (face * E.Knockback + UP * E.UpKnock) * k, E.Damage * k, E.ShockTime, 2.5)
			fire("EchoHit", { id = id, userId = p.UserId, pos = tt.Position, model = best, dir = face })
			worldHooks(p, tt.Position, 5)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- G: Godspeed. Charge, then blink through the nearest living bodies (a nearest-neighbour chain), striking each; then
-- the sky answers every body he touched at once; then Godspeed mode (character attribute "Godspeed" = end time)
local function endMode(p, s)
	if s.mode then
		local char = s.mode.char
		s.mode = nil
		if char and char.Parent then
			char:SetAttribute("Godspeed", nil)
		end
	end
end

local function castGodspeed(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Godspeed")
	if not char then
		return
	end
	local G = CFG.Godspeed
	-- provisional lock: the whole barrage at its longest; set properly once it is over
	local id = commit(p, s, "Godspeed", t, G.Charge + G.MaxTargets * G.HopEvery + G.FinaleDelay + 1, char)
	fire("GodspeedCast", { id = id, userId = p.UserId, t0 = t, charge = G.Charge, origin = hrp.Position })
	if Threat then
		Threat:Fire(hrp.Position, 60, G.Charge + 1)
	end
	task.spawn(function()
		task.wait(G.Charge)
		local c2, _, h2 = liveChar(p)
		if c2 ~= char or p:GetAttribute("Kit") ~= CFG.KitId then
			s.busyUntil = 0
			fire("GodspeedCancel", { id = id, userId = p.UserId })
			return
		end
		-- the chain: from Killua to the nearest body, from there to the next nearest, and so on
		local pool = {}
		for _, m in ipairs(targets(p)) do
			if alive(m) and (torsoOf(m).Position - h2.Position).Magnitude <= G.Range then
				table.insert(pool, m)
			end
		end
		local order, from = {}, h2.Position
		refreshIgnore()
		while #order < G.MaxTargets and #pool > 0 do
			local bi, bd
			for i, m in ipairs(pool) do
				local tp = torsoOf(m).Position
				local d = (tp - from).Magnitude
				if (not bd or d < bd) and clearLine(from, tp) then
					bi, bd = i, d
				end
			end
			if not bi then
				break -- everything left is behind a wall from here
			end
			local m = table.remove(pool, bi)
			table.insert(order, m)
			from = torsoOf(m).Position
		end
		local prev = h2.Position
		local struck = {}
		for i, m in ipairs(order) do
			if i > 1 then
				task.wait(G.HopEvery)
			end
			local c3, _, h3 = liveChar(p)
			if c3 ~= char then
				break
			end
			local tt = m.Parent and torsoOf(m)
			if tt then
				local tp = tt.Position
				local approach = (tp - prev) * FLAT
				approach = approach.Magnitude > 0.5 and approach.Unit or randomFlat()
				local dest = standAt(h3, tp - approach * math.min(clampPath(tp, -approach, 5), 3))
				fire("GodspeedHop", {
					id = id, userId = p.UserId, i = i, n = #order, from = prev, to = dest, face = approach, model = m, pos = tp,
				})
				strike(p, m, UP * G.HopPop + approach * 12, G.HopDamage, G.ShockTime, 2)
				table.insert(struck, m)
				prev = dest
			end
		end
		task.wait(#struck > 0 and G.FinaleDelay or 0.05)
		if liveChar(p) ~= char or p:GetAttribute("Kit") ~= CFG.KitId then
			s.busyUntil = 0
			fire("GodspeedCancel", { id = id, userId = p.UserId })
			return
		end
		local points = {}
		for _, m in ipairs(struck) do
			local tt = m.Parent and torsoOf(m)
			if tt then
				local radial = (tt.Position - prev) * FLAT
				radial = radial.Magnitude > 0.5 and radial.Unit or randomFlat()
				strike(p, m, (radial + UP * G.FinaleUp).Unit * G.FinaleFling, G.FinaleDamage, G.ShockTime, 3)
				table.insert(points, tt.Position)
			end
		end
		fire("GodspeedFinale", { id = id, userId = p.UserId, points = points, center = prev })
		worldHooks(p, prev, 12)
		s.busyUntil = now() + 0.15
		if liveChar(p) == char and p:GetAttribute("Kit") == CFG.KitId then
			local untilT = now() + G.ModeTime
			s.mode = { char = char, untilT = untilT }
			char:SetAttribute("Godspeed", untilT)
		end
		print(string.format("[Godspeed] #%d struck %d of %d bodies in range", id, #struck, #order))
	end)
end

---------------------------------------------------------------------------------------------------
-- requests, characters, the shock twitch and the timers
Request.OnServerEvent:Connect(function(p, action, payload)
	if typeof(action) ~= "string" or p:GetAttribute("Kit") ~= CFG.KitId then
		return
	end
	local s = getState(p)
	local c = os.clock()
	if c - s.last < 0.08 then
		return
	end
	s.last = c
	if type(payload) ~= "table" then
		payload = {}
	end
	if action == "Palm" then
		castPalm(p, s, payload)
	elseif action == "Thunder" then
		castThunder(p, s, payload)
	elseif action == "Echo" then
		castEcho(p, s, payload)
	elseif action == "Godspeed" then
		castGodspeed(p, s, payload)
	end
end)

local function onPlayer(p)
	local s = getState(p)
	p.CharacterAdded:Connect(function()
		endMode(p, s)
		s.busyUntil = 0
	end)
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		if p:GetAttribute("Kit") ~= CFG.KitId then
			endMode(p, s)
		end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

-- (2026-11-07 perks) ULT NOW (a consumable): ShopService fires PerkHooks.UltReset(player); a Godspeed holder gets the
-- ultimate's cooldown cleared, and the HUD hears it the usual way (a Cooldown message with the new end time)
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ultReset = hooks and hooks:WaitForChild("UltReset", 10)
	if ultReset and ultReset:IsA("BindableEvent") then
		ultReset.Event:Connect(function(p)
			if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= CFG.KitId then
				return
			end
			local s = getState(p)
			s.cd.Godspeed = 0
			sendCooldown(p, s, "Godspeed")
		end)
	else
		warn("[GodspeedServer] ServerStorage.PerkHooks.UltReset missing; Ult Now will not reach this kit")
	end
end)

RunService.Heartbeat:Connect(function()
	local t = now()
	local clock = os.clock()
	for model, rec in pairs(shocked) do
		if not model.Parent or t >= rec.untilT then
			shocked[model] = nil
			if model.Parent and (model:GetAttribute("Shocked") or 0) <= t + 0.01 then
				model:SetAttribute("Shocked", nil)
			end
		elseif clock >= rec.nextTwitch then
			rec.nextTwitch = clock + CFG.Shock.TwitchEvery * (0.6 + math.random() * 0.8)
			if RagdollService then
				RagdollService.Ragdoll(model, (rec.untilT - t) + 0.4) -- keep it down for as long as it is shocked
			end
			local ut = model:FindFirstChild("UpperTorso")
			if ut and not ut.Anchored then
				ut.AssemblyAngularVelocity += randomUnit() * CFG.Shock.Spin
			end
			for _, n in ipairs({ "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "Head" }) do
				local part = model:FindFirstChild(n)
				if part and not part.Anchored then
					part.AssemblyLinearVelocity += randomUnit() * CFG.Shock.LimbKick
				end
			end
		end
	end
	for p, s in pairs(state) do
		if s.mode and (liveChar(p) ~= s.mode.char or t >= s.mode.untilT) then
			endMode(p, s)
		end
		-- no switching fighter mid-move (VulpineServer.KitServer's SetKit checks this). Only the EQUIPPED kit's server
		-- writes KitLocked (every kit server shares the attribute), so this one keeps out of it while another is held
		if p:GetAttribute("Kit") == CFG.KitId then
			local locked = t < s.busyUntil
			if p:GetAttribute("KitLocked") ~= (locked or nil) then
				p:SetAttribute("KitLocked", locked or nil)
			end
		end
	end
end)

print("[GodspeedServer] online")
