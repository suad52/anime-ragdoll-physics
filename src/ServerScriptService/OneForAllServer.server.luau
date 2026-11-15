--!nocheck
local PvPBal = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) player damage/knockback balance
-- OneForAllServer: server side of the One For All kit (Deku). Owns cooldowns, targeting, every hit, the Blackwhip
-- reels, the ultimate's timeline and the Full Cowl 100% mode. Clients send intents through OneForAllKit.Remotes.Request
-- and render the timeline sent on Remotes.Broadcast; each caster's own client moves its own character along it.
--   AirForce (Q) | Detroit (E) | Blackwhip (R) | OFA (G, the ultimate) | AirStep (the passive's air jump)
-- The "SetKit" switch lives in VulpineServer.KitServer, which refuses a switch while the player's KitLocked is set.
--
-- Broadcast protocol (kind -> payload). t0 is server time (workspace:GetServerTimeNow()) at the cast.
--   Cooldown      (to the caster only) { skill, ends }
--   AirStep       { userId, t0, pos, mode }
--   AirForceCast  { id, userId, t0, origin, dir, stop, windup, speed, wall, target?, mode }
--   AirForceHit   { id, userId, pos, model, dir, mode }
--   DetroitCast   { id, userId, t0, origin, aim, charge, range, halfAngle, frontSpeed, stations = { {pos, t, r, sd} }, mode }
--   DetroitHit    { id, userId, pos, model, dir, k, core }
--   DetroitCancel { id, userId }
--   WhipCast      { id, userId, t0, origin, aim, gather, lash, speed, kick, targets = { {model, slot, latch, s} }, whiffEnds?, mode }
--   WhipLatch     { id, userId, model, pos }
--   WhipKick      { id, userId, center, aim, models, dirs, mode }
--   WhipCancel    { id, userId }
--   OFACast       { id, userId, t0, origin, aim, groundY, deck, C, indoor, charge, whipAt, leapAt, leapTime, leapRise,
--                   smashAt, hangUntil, modeAt }
--   OFAWhip       { id, userId, t0, C, targets = { {model, slot, latch} } }
--   OFALatch      { id, userId, model, pos }
--   OFASmash      { id, userId, fist, models }
--   OFAQuake      { id, userId, pos, hits }
--   OFACancel     { id, userId }
-- Full Cowl 100% is the character attribute "OFAMode" (= its end server time), cleared on expiry, death, respawn or a
-- kit change. A body being reeled carries the model attribute "WhippedBy" (= the caster's UserId).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = ReplicatedStorage:WaitForChild("OneForAllKit")
local CFG = require(Kit:WaitForChild("Config"))
local Remotes = Kit:WaitForChild("Remotes")
local Request = Remotes:WaitForChild("Request")
local Broadcast = Remotes:WaitForChild("Broadcast")

local KIT_ID = CFG.KitId
local SKILLS = { "AirForce", "Detroit", "Blackwhip", "OFA" }

-- hooks into the rest of the game, every one optional: ragdolls for NPC bodies, self-healing terrain craters, NPC
-- flee, explosive barrels and (only if CombatService ever grows it) breakable props
local GojoServer = ServerScriptService:WaitForChild("GojoServer", 10)
local RagdollService, GroundFX
do
	local mod = GojoServer and GojoServer:FindFirstChild("RagdollService")
	if mod then
		local ok, res = pcall(require, mod)
		if ok and type(res) == "table" then
			RagdollService = res
			pcall(RagdollService.Init)
		end
	end
	local vs = ServerScriptService:WaitForChild("VulpineServer", 10)
	local gfx = vs and vs:WaitForChild("GroundFX", 10)
	if gfx then
		local ok, res = pcall(require, gfx)
		if ok and type(res) == "table" then
			GroundFX = res
		end
	end
end

-- fires GojoServer.<name> (Threat, WorldBlast, BreakBlast) when it exists; looked up on every call, so a hook added
-- later starts working and a missing one is simply skipped
local function hook(name, ...)
	local ev = GojoServer and GojoServer:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then
		local ok, err = pcall(ev.Fire, ev, ...)
		if not ok then
			warn("[OneForAllServer] " .. name .. ": " .. tostring(err))
		end
	end
end

-- GroundFX.<fn>(...) when the module loaded
local function ground(fn, ...)
	local f = GroundFX and GroundFX[fn]
	if f then
		local ok, err = pcall(f, ...)
		if not ok then
			warn("[OneForAllServer] GroundFX." .. fn .. ": " .. tostring(err))
		end
	end
end

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)

---------------------------------------------------------------------------------------------------
-- shared helpers (copied from GodspeedServer; pushLoose from VulpineServer.KitServer)
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

-- (aim, flat): the client's camera direction with its pitch clamped to [minDeg, maxDeg] (KitServer's aimOf)
local function aimOf(payload, hrp, minDeg, maxDeg)
	local look = flatDir(hrp.CFrame.LookVector)
	local v = payload.aim
	if not finite(v) or v.Magnitude < 1e-3 then
		return look, look
	end
	local flat = flatDir(v, look)
	local pitch = math.clamp(math.asin(math.clamp(v.Unit.Y, -1, 1)), math.rad(minDeg), math.rad(maxDeg))
	return (flat * math.cos(pitch) + UP * math.sin(pitch)).Unit, flat
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

-- the caster still has this character and still holds this kit
local function valid(p, char)
	return liveChar(p) == char and p:GetAttribute("Kit") == KIT_ID
end

local function torsoOf(m)
	-- (2026-11-08) a player in a giant form answers at the point of its whole body nearest the attack (PvP.formRoot)
	return PvPBal.formRoot(m) or m:FindFirstChild("UpperTorso") or m:FindFirstChild("HumanoidRootPart")
end

local function alive(m)
	local h = m:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0 and m:GetAttribute("Dead") ~= true
end

-- held by something else (a Blue grab, a domain): pulls skip it, blasts damage it but never move it
local function held(m)
	return m:GetAttribute("GrabbedBy") ~= nil or m:GetAttribute("InDomain") ~= nil
end

local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP")) -- (2026-11-07) other players are targets too
-- every ragdollable NPC body in the world (alive or dead), plus every OTHER player's character (never the caster)
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

-- the world only (no characters, NPC bodies or effects): wall clamps, ground snaps, line of sight
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
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(list, m) -- a body standing outside workspace.NPCs must not block the line to itself
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

local function floorBelow(p, depth)
	refreshIgnore()
	local hit = workspace:Raycast(p, Vector3.new(0, -(depth or 40), 0), worldParams)
	return hit and hit.Position or nil
end

-- a root position for a character standing at `pos`, as high above its ground as `hrp` is above its own
local function standAt(hrp, pos)
	local own = floorBelow(hrp.Position, 30)
	local hip = own and (hrp.Position.Y - own.Y) or 3
	local g = floorBelow(Vector3.new(pos.X, math.max(pos.Y, hrp.Position.Y) + 1.5, pos.Z), 60)
	return g and Vector3.new(pos.X, g.Y + hip, pos.Z) or pos
end

-- nothing solid (world geometry only) between two points; call refreshIgnore() first
local function clearLine(a, b)
	local d = b - a
	if d.Magnitude < 1e-3 then
		return true
	end
	return workspace:Raycast(a, d, worldParams) == nil
end

-- the flat angle (degrees) between a flat offset and the aim; 0 for a body standing on the caster
local function angleTo(fl, aim)
	if fl.Magnitude < 0.5 then
		return 0
	end
	return math.deg(math.acos(math.clamp(fl.Unit:Dot(aim), -1, 1)))
end

local function merge(a, b)
	local out = {}
	for k, v in pairs(a) do
		out[k] = v
	end
	for k, v in pairs(b or {}) do
		out[k] = v
	end
	return out
end

local looseParams = OverlapParams.new()
looseParams.FilterType = Enum.RaycastFilterType.Exclude

-- loose physics props get shoved too (sign = -1 pulls inward)
local function pushLoose(pos, radius, speed, upBias, sign)
	local ignore = {}
	for _, n in ipairs({ "KitFX", "FX", "LocalFX" }) do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(CFG.TargetTag)) do
		table.insert(ignore, m)
	end
	looseParams.FilterDescendantsInstances = ignore
	local done = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(pos, radius, looseParams)) do
		local root = part.AssemblyRootPart
		if root and not root.Anchored and not done[root] then
			done[root] = true
			local off = root.Position - pos
			local k = math.clamp(1 - off.Magnitude / radius, 0, 1)
			local dir = ((off.Magnitude > 0.5 and off.Unit or UP) * (sign or 1) + UP * upBias).Unit
			pcall(function()
				root:ApplyImpulse(dir * speed * 0.6 * k * root.AssemblyMass)
			end)
		end
	end
end

local function fire(kind, data)
	Broadcast:FireAllClients(kind, data)
end

---------------------------------------------------------------------------------------------------
-- per-player state
local state = {} -- [player] = { cd = {}, busyUntil, last, id, mode = { char, untilT }?, airStepReady }
local function getState(p)
	local s = state[p]
	if not s then
		s = { cd = {}, busyUntil = 0, last = 0, id = 0, mode = nil, airStepReady = 0 }
		state[p] = s
	end
	return s
end

-- Full Cowl 100% is active on this character
local function inMode(s, char)
	return s.mode ~= nil and s.mode.char == char and now() < s.mode.untilT
end

local function endMode(p, s)
	if s.mode then
		local char = s.mode.char
		s.mode = nil
		if char and char.Parent then
			char:SetAttribute("OFAMode", nil)
		end
	end
end

local function sendCooldown(p, s, skill)
	Broadcast:FireClient(p, "Cooldown", { skill = skill, ends = s.cd[skill] or 0 })
end

-- alive, holding this kit, not mid-move, off cooldown
local function gate(p, s, skill)
	local char, hum, hrp = liveChar(p)
	if not char or p:GetAttribute("Kit") ~= KIT_ID then
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
-- ultimate (OFA) as well. The client shows the end time sent here, so its timer always matches
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

-- starts the cooldown (shortened in Full Cowl 100% and by the cooldown perks) and the lock; returns the cast id
local function commit(p, s, skill, t, lock, char)
	local cd = CFG[skill].Cooldown
	if inMode(s, char) then
		cd *= CFG.Mode.CooldownMul[skill] or 1
	end
	cd *= perkMul(p, skill == "OFA")
	s.cd[skill] = t + cd
	s.busyUntil = t + lock
	s.id += 1
	sendCooldown(p, s, skill)
	return s.id
end

---------------------------------------------------------------------------------------------------
-- hits

-- velocities pinned at zero for `secs`, then `after()`: the server half of the hit-stop
local function freezeBody(m, secs, after)
	local untilT = os.clock() + secs
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not m.Parent or os.clock() >= untilT then
			conn:Disconnect()
			local ok, err = pcall(after)
			if not ok then
				warn("[OneForAllServer] hit-stop: " .. tostring(err))
			end
			return
		end
		for _, part in ipairs(m:GetChildren()) do
			if part:IsA("BasePart") and not part.Anchored then
				part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			end
		end
	end)
end

-- damage + kill credit + ragdoll + (optionally hit-stopped) fling. Held bodies take the damage but keep still.
local function strike(p, m, vel, damage, rag, o)
	o = o or {}
	if not m.Parent or (p and m == p.Character) then
		return
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if damage and damage > 0 and hum and hum.Health > 0 and m:GetAttribute("Dead") ~= true then
		m:SetAttribute("LastHitBy", p.UserId)
		hum:TakeDamage(PvPBal.dmg(hum, damage))
	end
	if not RagdollService then
		return
	end
	if not vel or held(m) then
		RagdollService.Ragdoll(m, rag)
		return
	end
	local spin = o.spin or randomUnit() * 10
	if o.hitStop and o.hitStop > 0 then
		RagdollService.Ragdoll(m, rag + o.hitStop)
		freezeBody(m, o.hitStop, function()
			if m.Parent and not held(m) then
				RagdollService.Fling(m, vel, spin, rag)
			end
		end)
	else
		RagdollService.Fling(m, vel, spin, rag)
	end
end

-- reel a body toward a point (call every Heartbeat): homing velocity, no spin. False once it can no longer be reeled
local function reel(m, slot, gain, maxSpeed, rag)
	local tt = m.Parent and torsoOf(m)
	if not tt or held(m) or not RagdollService then
		return false
	end
	local v = (slot - tt.Position) * gain
	if v.Magnitude > maxSpeed then
		v = v.Unit * maxSpeed
	end
	RagdollService.Fling(m, v, Vector3.zero, rag)
	return true
end

-- clears WhippedBy, but only if this caster set it
local function unwhip(m, uid)
	if m.Parent and m:GetAttribute("WhippedBy") == uid then
		m:SetAttribute("WhippedBy", nil)
	end
end

-- runs `step(e)` every Heartbeat (e = server seconds since t0) until it returns true; an error stops it and calls
-- `onError()` so nothing is left reeling or locked
local function timeline(label, t0, step, onError)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local ok, res = pcall(step, now() - t0)
		if not ok then
			conn:Disconnect()
			warn("[OneForAllServer] " .. label .. ": " .. tostring(res))
			pcall(onError)
		elseif res then
			conn:Disconnect()
		end
	end)
end

-- task.delay to an absolute cast time (t0 + at)
local function at(t0, secs, fn, ...)
	return task.delay(math.max(t0 + secs - now(), 0), fn, ...)
end

---------------------------------------------------------------------------------------------------
-- PASSIVE: Full Cowl's air step. The client moves itself (predicted); the server only guards the broadcast
local function airStep(p, s, payload)
	local char, hum, hrp = liveChar(p)
	if not char or p:GetAttribute("Kit") ~= KIT_ID then
		return
	end
	local t = now()
	if t < (s.airStepReady or 0) then
		return
	end
	local airborne = hum.FloorMaterial == Enum.Material.Air
	if not airborne then
		-- the server's FloorMaterial lags a client-owned body: also accept feet more than 2.5 studs off the ground
		local g = floorBelow(hrp.Position, 60)
		local standH = hum.HipHeight + hrp.Size.Y * 0.5
		airborne = g == nil or (hrp.Position.Y - g.Y) - standH > 2.5
	end
	if not airborne then
		return
	end
	local mode = inMode(s, char)
	local AS = CFG.Passive.AirStep
	s.airStepReady = t + (mode and AS.ModeCooldown or AS.Cooldown)
	local pos = payload.pos
	if not finite(pos) or (pos - hrp.Position).Magnitude > 15 then
		pos = hrp.Position
	end
	fire("AirStep", { userId = p.UserId, t0 = t, pos = pos, mode = mode })
end

---------------------------------------------------------------------------------------------------
-- Q: Delaware Smash: Air Force. One air bullet down the (pitch-clamped) camera line; the first living body in the
-- 4-stud corridor takes it when the bullet arrives, and an air burst shoves everything round the impact
local function castAirForce(p, s, payload)
	local char, _, hrp, t = gate(p, s, "AirForce")
	if not char then
		return
	end
	local A = CFG.AirForce
	local uid = p.UserId
	local mode = inMode(s, char)
	local k = mode and CFG.Mode.DamageMul or 1
	local aim, flat = aimOf(payload, hrp, A.PitchMin, A.PitchMax)
	local origin = hrp.Position + UP * 1.0 + flat * 1.6 -- the fingertip
	local dist = clampPath(origin, aim, A.Range) -- also refreshes the ignore list for clearLine
	local best, bestAlong
	for _, m in ipairs(targets(p)) do
		if alive(m) then
			PvPBal.aimSeg(m, origin, origin + aim * dist) -- (2026-11-10) forms: nearest the air bullet's line
			local tp = torsoOf(m).Position
			local rel = tp - origin
			local along = rel:Dot(aim)
			if along > 0.5 and along <= dist + 2 and (rel - aim * along).Magnitude <= A.HitRadius
				and (not bestAlong or along < bestAlong) and clearLine(origin, tp) then
				best, bestAlong = m, along
			end
		end
	end
	local stop = best and bestAlong or dist
	local id = commit(p, s, "AirForce", t, A.Lock, char)
	fire("AirForceCast", {
		id = id, userId = uid, t0 = t, origin = origin, dir = aim, stop = stop, windup = A.Windup, speed = A.Speed,
		wall = (best == nil and dist < A.Range), target = best, mode = mode,
	})
	hook("Threat", origin + aim * math.min(stop, 40), 14, 0.7)
	task.delay(A.Windup + stop / A.Speed, function()
		local endPt = origin + aim * stop
		if best then
			PvPBal.aimAt(endPt) -- (2026-11-10) a form is struck where the bullet stops
			local tt = best.Parent and torsoOf(best)
			if not tt or (tt.Position - endPt).Magnitude > A.Escape then
				return -- it got away: the clients draw an air pop at the end point
			end
			local impact = tt.Position
			strike(p, best, (aim * A.Knockback + UP * A.UpKnock) * k, A.Damage * k, A.RagTime)
			-- the air burst: every other body (alive or dead) round the impact
			for _, m in ipairs(targets(p)) do
				PvPBal.aimAt(impact) -- (2026-11-10) forms: nearest the air burst
				if m ~= best then
					local off = torsoOf(m).Position - impact
					if off.Magnitude <= A.Splash then
						local fl = off * FLAT
						local radial = fl.Magnitude > 0.5 and fl.Unit or randomFlat()
						strike(p, m, (radial + UP * 0.4).Unit * A.Knockback * A.SplashMul * k, A.SplashDamage * k, 2)
					end
				end
			end
			pushLoose(impact, 10, 80, 0.3, 1)
			hook("WorldBlast", impact, 5, uid)
			hook("BreakBlast", impact, 4, aim, 60, uid)
			fire("AirForceHit", { id = id, userId = uid, pos = impact, model = best, dir = aim, mode = mode })
		elseif dist < A.Range then
			-- a wall: the clients draw the burst from the cast payload
			hook("WorldBlast", endPt, 5, uid)
			hook("BreakBlast", endPt, 4, aim, 60, uid)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- E: Detroit Smash. Coil, punch; the wind pressure races out along a cone at FrontSpeed, flinging bodies in order of
-- distance and carving a trench of craters. In Full Cowl 100% it is Delaware Detroit Smash (Mode.Detroit overrides)
local function castDetroit(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Detroit")
	if not char then
		return
	end
	local uid = p.UserId
	local mode = inMode(s, char)
	local D = mode and merge(CFG.Detroit, CFG.Mode.Detroit) or CFG.Detroit
	local flingMul = mode and (D.FlingMul or 1.3) or 1
	local aim = flatDir(payload.aim, hrp.CFrame.LookVector)
	local origin = hrp.Position
	local id = commit(p, s, "Detroit", t, D.Lock, char)

	-- the trench: one crater per station distance, stopping at the first wall, kept only where the wave skims ground
	local wall = clampPath(origin, aim, D.Range)
	local stations = {}
	for _, sd in ipairs(mode and D.ModeStations or D.Stations) do
		if sd > wall then
			break
		end
		local pt = origin + aim * sd
		local g = groundAt(pt, 14)
		if g and pt.Y - g.Y < 9 then
			table.insert(stations, { pos = g, t = D.Charge + sd / D.FrontSpeed, r = D.CraterBase + D.CraterPerStud * sd, sd = sd })
		end
	end
	fire("DetroitCast", {
		id = id, userId = uid, t0 = t, origin = origin, aim = aim, charge = D.Charge, range = D.Range,
		halfAngle = D.HalfAngle, frontSpeed = D.FrontSpeed, stations = stations, mode = mode,
	})
	hook("Threat", origin + aim * D.Range * 0.5, D.Range * 0.55, 0.9)

	at(t, D.Charge, function()
		if not valid(p, char) then
			if s.id == id then
				s.busyUntil = 0
			end
			fire("DetroitCancel", { id = id, userId = uid })
			return
		end
		local _, _, h2 = liveChar(p)
		local fist = h2.Position + aim * 2.5 + UP * 0.5
		local chest = h2.Position + UP * 1.2
		refreshIgnore()
		local hits = {}
		for _, m in ipairs(targets(p)) do -- alive or dead: corpses fly too, but take no damage
			local tp = torsoOf(m).Position
			local rel = tp - origin
			local fl = rel * FLAT
			local d = fl.Magnitude
			local ang = angleTo(fl, aim)
			local core = (tp - fist).Magnitude <= D.CoreRadius and ang <= D.CoreAngle
			local cone = d <= D.Range and ang <= D.HalfAngle and math.abs(rel.Y) <= D.MaxY
			if (core or cone) and clearLine(chest, tp) then
				table.insert(hits, { m = m, d = d, core = core, radial = d > 0.5 and fl.Unit or aim })
			end
		end
		local coreDir = (aim + UP * D.CoreUp).Unit
		for _, h in ipairs(hits) do
			task.delay(h.d / D.FrontSpeed, function()
				local m = h.m
				local tt = m.Parent and torsoOf(m)
				if not tt then
					return
				end
				local k = 1 - math.clamp((h.d - 12) / (D.Range - 12), 0, 1)
				local dir
				if h.core then
					dir, k = coreDir, 1
					strike(p, m, coreDir * math.min(D.CoreFling * flingMul, 320), D.Damage, D.RagTime,
						{ hitStop = D.HitStop, spin = aim:Cross(UP) * 16 })
				else
					dir = (h.radial:Lerp(aim, D.AimBlend).Unit + UP * D.UpBias).Unit
					local dmg = D.Damage * (D.FarMul + (1 - D.FarMul) * k)
					local spd = math.min((D.FlingFar + (D.FlingNear - D.FlingFar) * k) * flingMul, 320)
					strike(p, m, dir * spd, dmg, D.RagTime, { spin = randomUnit() * 12 })
				end
				fire("DetroitHit", { id = id, userId = uid, pos = tt.Position, model = m, dir = dir, k = k, core = h.core })
			end)
		end
		for _, st in ipairs(stations) do
			at(t, st.t, function()
				ground("impact", st.pos, st.r, D.Rocks, D.RockSpeed)
				pushLoose(st.pos, D.PushRadius, D.PushSpeed, D.PushUp, 1)
				hook("WorldBlast", st.pos, st.r + 3, uid)
				hook("BreakBlast", st.pos, st.r + 4, aim, 90, uid)
			end)
		end
		print(string.format("[OneForAll] Detroit #%d hit %d bodies", id, #hits))
	end)
end

---------------------------------------------------------------------------------------------------
-- R: Blackwhip -> St. Louis Smash. Tendrils latch up to MaxTargets bodies in a cone and reel them to slots in front
-- of him, then one spinning roundhouse kicks everything at the gather point out in a fan
local function castBlackwhip(p, s, payload)
	local char, _, hrp, t = gate(p, s, "Blackwhip")
	if not char then
		return
	end
	local B = CFG.Blackwhip
	local uid = p.UserId
	local mode = inMode(s, char)
	local k = mode and CFG.Mode.DamageMul or 1
	local aim = flatDir(payload.aim, hrp.CFrame.LookVector)
	local origin = hrp.Position
	local side = aim:Cross(UP).Unit
	local chest = origin + UP * 1.2
	local G = origin + aim * B.GatherForward + UP * B.GatherUp

	refreshIgnore()
	local pool = {}
	for _, m in ipairs(targets(p)) do
		if not held(m) and m:GetAttribute("WhippedBy") == nil then
			local tp = torsoOf(m).Position
			local rel = tp - origin
			local d = rel.Magnitude
			local ang = angleTo(rel * FLAT, aim)
			if d <= B.Range and math.abs(rel.Y) < 20 and ang <= B.Cone and clearLine(chest, tp) then
				-- living bodies first; corpses fill the spare slots
				table.insert(pool, { m = m, d = d, lat = rel:Dot(side), score = d + ang * 0.3 - (alive(m) and 15 or 0) })
			end
		end
	end
	table.sort(pool, function(a, b)
		return a.score < b.score
	end)
	local chosen = {}
	for i = 1, math.min(mode and B.ModeMaxTargets or B.MaxTargets, #pool) do
		chosen[i] = pool[i]
	end
	table.sort(chosen, function(a, b)
		return a.lat < b.lat
	end)
	local n = #chosen
	local list = {}
	for i, c in ipairs(chosen) do
		c.s = n > 1 and (-1 + 2 * (i - 1) / (n - 1)) or 0 -- left -> right in [-1, 1]
		c.slot = G + side * (i - (n + 1) / 2) * B.SlotSpacing
		c.latch = B.LashAt + c.d / B.Speed
		list[i] = { model = c.m, slot = c.slot, latch = c.latch, s = c.s }
	end
	local id = commit(p, s, "Blackwhip", t, B.Lock, char)
	local whiffEnds
	if n == 0 then
		whiffEnds = {}
		for _, deg in ipairs({ -30, 0, 30 }) do
			local dir = CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(aim)
			table.insert(whiffEnds, origin + dir * clampPath(origin, dir, 40) + UP * 1)
		end
	end
	fire("WhipCast", {
		id = id, userId = uid, t0 = t, origin = origin, aim = aim, gather = G, lash = B.LashAt, speed = B.Speed,
		kick = B.KickAt, targets = list, whiffEnds = whiffEnds, mode = mode,
	})

	local function releaseAll()
		for _, c in ipairs(chosen) do
			unwhip(c.m, uid)
		end
	end
	local function cancel()
		releaseAll()
		if s.id == id then
			s.busyUntil = 0
		end
		fire("WhipCancel", { id = id, userId = uid })
	end

	-- 0.66: ST. LOUIS SMASH
	local function kick()
		local kicked, seen = {}, {}
		for _, c in ipairs(chosen) do
			if c.latched and not c.dropped and c.m.Parent and torsoOf(c.m) then
				seen[c.m] = true
				table.insert(kicked, { m = c.m, s = c.s })
			end
		end
		-- plus anything at the gather point (held bodies there take the damage but keep still)
		for _, m in ipairs(targets(p)) do
			if not seen[m] then
				PvPBal.aimAt(G) -- (2026-11-10) forms: nearest the kick point
				local off = torsoOf(m).Position - G
				if off.Magnitude <= B.KickRadius then
					seen[m] = true
					table.insert(kicked, { m = m, s = math.clamp(off:Dot(side), -1, 1) })
				end
			end
		end
		local models, dirs = {}, {}
		for _, kb in ipairs(kicked) do
			local v = ((aim + side * kb.s * B.KickFan).Unit + UP * B.KickUp).Unit
			strike(p, kb.m, v * B.KickFling * k, B.KickDamage * k, B.RagTime, { hitStop = B.HitStop, spin = aim:Cross(UP) * B.Spin })
			unwhip(kb.m, uid)
			table.insert(models, kb.m)
			table.insert(dirs, v)
		end
		releaseAll()
		ground("ring", G, 6, 6, 35)
		pushLoose(G, 14, 110, 0.4, 1)
		hook("WorldBlast", G, 8, uid)
		fire("WhipKick", { id = id, userId = uid, center = G, aim = aim, models = models, dirs = dirs, mode = mode })
		print(string.format("[OneForAll] Blackwhip #%d latched %d, kicked %d", id, n, #models))
	end

	timeline("Blackwhip #" .. id, t, function(e)
		if not valid(p, char) then
			cancel()
			return true
		end
		for _, c in ipairs(chosen) do
			if not c.latched then
				if not c.dropped and e >= c.latch then
					local tt = c.m.Parent and torsoOf(c.m)
					if tt and (tt.Position - origin).Magnitude <= 60 and not held(c.m) and c.m:GetAttribute("WhippedBy") == nil then
						c.latched = true
						strike(p, c.m, nil, B.LatchDamage * k, B.RagTime)
						c.m:SetAttribute("WhippedBy", uid)
						fire("WhipLatch", { id = id, userId = uid, model = c.m, pos = tt.Position })
					else
						c.dropped = true
					end
				end
			elseif not c.dropped and e < B.PullUntil then
				if not reel(c.m, c.slot, B.PullGain, B.PullMax, B.RagTime) then
					c.dropped = true -- it became held (or vanished): let it go
					unwhip(c.m, uid)
				end
			end
		end
		if e >= B.KickAt then
			kick()
			return true
		end
		return false
	end, cancel)
end

---------------------------------------------------------------------------------------------------
-- G: One For All 1,000,000%. Storm and charge, Blackwhip hauls up to MaxTargets bodies into a ring over him, he leaps
-- and smashes straight up through them, the quake hits everything else round him, then Full Cowl 100%
local function castOFA(p, s, payload)
	local char, _, hrp, t = gate(p, s, "OFA")
	if not char then
		return
	end
	local O = CFG.OFA
	local uid = p.UserId
	local aim = flatDir(payload.aim, hrp.CFrame.LookVector)
	local origin = hrp.Position
	local g0 = groundAt(origin)
	local groundY = g0 and g0.Y or (origin.Y - 3)

	-- ceiling probe: under a roof the cluster hangs lower and the leap is shorter; indoors the column stops there
	local clusterUp, leapRise, indoor = O.ClusterUp, O.LeapRise, false
	local roof = workspace:Raycast(origin, UP * 40, worldParams) -- groundAt just refreshed the ignore list
	if roof then
		local hd = roof.Position.Y - origin.Y
		if hd <= O.ClusterUp + 6 then
			clusterUp = math.max(hd - 5, 6)
			leapRise = math.max(clusterUp - 4, 3)
		end
		if hd <= O.MinCeiling then
			indoor = true
		end
	end
	local C = origin + aim * O.ClusterForward + UP * clusterUp
	local id = commit(p, s, "OFA", t, O.Lock, char)
	fire("OFACast", {
		id = id, userId = uid, t0 = t, origin = origin, aim = aim, groundY = groundY, deck = groundY + O.DeckHeight,
		C = C, indoor = indoor, charge = O.Charge, whipAt = O.WhipAt, leapAt = O.LeapAt, leapTime = O.LeapTime,
		leapRise = leapRise, smashAt = O.SmashAt, hangUntil = O.HangUntil, modeAt = O.ModeAt,
	})
	hook("Threat", origin, 60, 1.2)

	local chosen = {}
	local picked = false
	local function releaseAll()
		for _, c in ipairs(chosen) do
			unwhip(c.m, uid)
		end
	end
	local function cancel()
		releaseAll()
		if s.id == id then
			s.busyUntil = 0
		end
		fire("OFACancel", { id = id, userId = uid })
	end

	-- 0.5: pick the bodies; nearest first (living before dead), slots on a ring round C, alternately high and low
	local function pick()
		local _, _, h = liveChar(p)
		local chest = h.Position + UP * 1.2
		refreshIgnore()
		local pool = {}
		for _, m in ipairs(targets(p)) do
			if not held(m) and m:GetAttribute("WhippedBy") == nil then
				local tp = torsoOf(m).Position
				local d = (tp - chest).Magnitude
				if d <= O.WhipRange and clearLine(chest, tp) then
					table.insert(pool, { m = m, d = d, rank = (alive(m) and 0 or 1e5) + d })
				end
			end
		end
		table.sort(pool, function(a, b)
			return a.rank < b.rank
		end)
		local n = math.min(#pool, O.MaxTargets)
		local phase = math.atan2(aim.Z, aim.X)
		local list = {}
		for i = 1, n do
			local c = pool[i]
			local a = phase + (i - 1) / n * math.pi * 2
			c.slot = C + Vector3.new(math.cos(a) * O.ClusterRing, (i % 2 == 0) and 1.2 or -1.2, math.sin(a) * O.ClusterRing)
			c.latch = O.WhipAt + c.d / O.WhipSpeed
			chosen[i] = c
			list[i] = { model = c.m, slot = c.slot, latch = c.latch }
		end
		fire("OFAWhip", { id = id, userId = uid, t0 = t, C = C, targets = list })
	end

	-- 1.46: the quake round the ground point, the crater flower, the world hooks
	local function quake(inSet, smashed)
		local g = groundAt(origin) or Vector3.new(origin.X, groundY, origin.Z)
		local n = 0
		for _, m in ipairs(targets(p)) do -- groundAt refreshed the ignore list
			if not inSet[m] then
				PvPBal.aimAt(g) -- (2026-11-10) forms: nearest the quake
				local tp = torsoOf(m).Position
				local off = tp - g
				local dist = off.Magnitude
				if dist <= O.QuakeRadius and clearLine(g + UP * 3, tp) then
					local kq = 1 - dist / O.QuakeRadius
					local fl = off * FLAT
					local radial = fl.Magnitude > 0.5 and fl.Unit or randomFlat()
					local spd = O.QuakeFlingFar + (O.QuakeFlingNear - O.QuakeFlingFar) * kq
					local dmg = O.QuakeDamage * (O.QuakeFarMul + (1 - O.QuakeFarMul) * kq)
					strike(p, m, (radial + UP * O.QuakeUp).Unit * spd, dmg, 3)
					n += 1
				end
			end
		end
		ground("impact", g, O.CraterRadius, 14, 80)
		for j, R in ipairs(O.RingCraters) do
			for i = 1, R.n do
				local a = math.pi * 2 * i / R.n + (math.random() * 0.6 - 0.3)
				local x, z = g.X + math.cos(a) * R.r, g.Z + math.sin(a) * R.r
				local pt = groundAt(Vector3.new(x, g.Y + 20, z), 50) or Vector3.new(x, g.Y, z)
				-- ring 1 staggers inside its delay; later rings start at their delay and stagger 0.05 s across
				local d = (j == 1) and (R.delay * i / R.n) or (R.delay + 0.05 * i / R.n)
				task.delay(d, ground, "impact", pt, R.size, R.rocks, R.speed)
			end
		end
		pushLoose(g, 80, 170, 0.5, 1)
		hook("WorldBlast", g, 40, uid)
		hook("BreakBlast", g, 45, UP, 120, uid)
		hook("Threat", g, 120, 3)
		fire("OFAQuake", { id = id, userId = uid, pos = g, hits = n })
		print(string.format("[OneForAll] #%d smashed %d, quaked %d", id, smashed, n))
	end

	-- 2.5: Full Cowl 100%
	local function startMode()
		if not valid(p, char) then
			return
		end
		local untilT = now() + CFG.Mode.Time
		s.mode = { char = char, untilT = untilT }
		char:SetAttribute("OFAMode", untilT)
		if s.id == id then
			s.busyUntil = t + O.Lock
		end
	end

	-- 1.40: 1,000,000% DETROIT SMASH, straight up through the cluster
	local function smash()
		local set, inSet = {}, {}
		for _, c in ipairs(chosen) do
			if c.latched and not c.dropped and c.m.Parent and torsoOf(c.m) then
				inSet[c.m] = true
				table.insert(set, c.m)
			end
		end
		for _, m in ipairs(targets(p)) do
			PvPBal.aimAt(C) -- (2026-11-10) forms: nearest the smash
			if not inSet[m] and not held(m) and (torsoOf(m).Position - C).Magnitude <= O.SmashRadius then
				inSet[m] = true
				table.insert(set, m)
			end
		end
		for _, m in ipairs(set) do
			local fl = (torsoOf(m).Position - C) * FLAT
			local radial = fl.Magnitude > 0.5 and fl.Unit or randomFlat()
			strike(p, m, (UP + radial * O.SmashSpread + aim * O.SmashForward).Unit * O.SmashFling, O.SmashDamage, O.RagTime,
				{ hitStop = O.HitStop, spin = randomUnit() * 20 })
			unwhip(m, uid)
		end
		releaseAll()
		fire("OFASmash", { id = id, userId = uid, fist = C - UP * 3, models = set })
		at(t, O.SmashAt + O.QuakeDelay, quake, inSet, #set)
		at(t, O.ModeAt, startMode)
	end

	timeline("OFA #" .. id, t, function(e)
		if not valid(p, char) then
			cancel()
			return true
		end
		if not picked and e >= O.WhipAt then
			picked = true
			pick()
		end
		for _, c in ipairs(chosen) do
			if not c.latched then
				if not c.dropped and e >= c.latch then
					local tt = c.m.Parent and torsoOf(c.m)
					if tt and not held(c.m) and c.m:GetAttribute("WhippedBy") == nil then
						c.latched = true
						strike(p, c.m, nil, O.LatchDamage, O.RagTime)
						c.m:SetAttribute("WhippedBy", uid)
						fire("OFALatch", { id = id, userId = uid, model = c.m, pos = tt.Position })
					else
						c.dropped = true
					end
				end
			elseif not c.dropped then
				if not reel(c.m, c.slot, O.PullGain, O.PullMax, O.RagTime) then
					c.dropped = true -- it became held (or vanished): let it go
					unwhip(c.m, uid)
				end
			end
		end
		if e >= O.SmashAt then
			smash()
			return true
		end
		return false
	end, cancel)
end

---------------------------------------------------------------------------------------------------
-- requests, characters and the timers
local CASTS = {
	AirForce = castAirForce,
	Detroit = castDetroit,
	Blackwhip = castBlackwhip,
	OFA = castOFA,
}

Request.OnServerEvent:Connect(function(p, action, payload)
	if typeof(action) ~= "string" or p:GetAttribute("Kit") ~= KIT_ID then
		return
	end
	local s = getState(p)
	if type(payload) ~= "table" then
		payload = {}
	end
	if action == "AirStep" then
		airStep(p, s, payload) -- its own server guard; never eats a cast inside the limiter window
		return
	end
	local fn = CASTS[action]
	if not fn then
		return
	end
	local c = os.clock()
	if c - s.last < 0.08 then
		return
	end
	s.last = c
	local ok, err = pcall(fn, p, s, payload)
	if not ok then
		warn("[OneForAllServer] " .. action .. ": " .. tostring(err))
	end
end)

local function onPlayer(p)
	local s = getState(p)
	p.CharacterAdded:Connect(function()
		endMode(p, s)
		s.busyUntil = 0
		s.airStepReady = 0
	end)
	p:GetAttributeChangedSignal("Kit"):Connect(function()
		if p:GetAttribute("Kit") ~= KIT_ID then
			endMode(p, s)
		else
			for _, skill in ipairs(SKILLS) do
				sendCooldown(p, s, skill) -- the HUD picks up any cooldown still running from before a switch
			end
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

-- (2026-11-07 perks) ULT NOW (a consumable): ShopService fires PerkHooks.UltReset(player); a One For All holder gets
-- the ultimate's cooldown cleared, and the HUD hears it the usual way (a Cooldown message with the new end time)
task.spawn(function()
	local hooks = game:GetService("ServerStorage"):WaitForChild("PerkHooks", 30)
	local ultReset = hooks and hooks:WaitForChild("UltReset", 10)
	if ultReset and ultReset:IsA("BindableEvent") then
		ultReset.Event:Connect(function(p)
			if typeof(p) ~= "Instance" or not p:IsA("Player") or p:GetAttribute("Kit") ~= KIT_ID then
				return
			end
			local s = getState(p)
			s.cd.OFA = 0
			sendCooldown(p, s, "OFA")
		end)
	else
		warn("[OneForAllServer] ServerStorage.PerkHooks.UltReset missing; Ult Now will not reach this kit")
	end
end)

RunService.Heartbeat:Connect(function()
	local t = now()
	for p, s in pairs(state) do
		if s.mode and (liveChar(p) ~= s.mode.char or t >= s.mode.untilT) then
			endMode(p, s)
		end
		-- no switching fighter mid-move (VulpineServer.KitServer's SetKit checks this). Only the EQUIPPED kit's server
		-- writes KitLocked (every kit server shares the attribute), so this one keeps out of it while another is held
		if p:GetAttribute("Kit") == KIT_ID then
			local locked = t < s.busyUntil
			if p:GetAttribute("KitLocked") ~= (locked or nil) then
				p:SetAttribute("KitLocked", locked or nil)
			end
		end
	end
end)

print("[OneForAllServer] online")
