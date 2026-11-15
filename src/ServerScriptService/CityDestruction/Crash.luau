-- ServerScriptService.CityDestruction.Crash (ModuleScript, orchestrator 2026-11-07)
-- Utility / movement breaking: anything that MOVES through the city fast enough smashes the breakables on its path -
-- dashes, blink-dashes, flight, grapples (any kit, no kit changes needed), bodies flung or dragged by attacks (players
-- and NPC dummies), and giant forms (Attack / Colossal Titan, Susanoo, Kurama, swarm giants) just by walking.
-- Positions are read every Heartbeat (CFrame-driven dashes have no velocity; a jump of > TELEPORT_FRAME studs in
-- one frame is a teleport and breaks nothing), and every 1 / HZ s the path since the last sweep is fed to the
-- service as kind "crash" impacts (damage x speed multiplier, never road markings, never merged with kit blasts).
-- Numbers: CityShared.DestructionConfig.CRASH.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Crash = {}

local V3 = Vector3.new
local ZERO = Vector3.zero
local min, max, clamp, sqrt, ceil = math.min, math.max, math.clamp, math.sqrt, math.ceil

function Crash.start(S, CFG)
	local C = CFG and CFG.CRASH
	if not C or C.ENABLED == false or type(S) ~= "table" or not S.impact or not S.hasNear then
		return nil
	end
	local PERIOD = 1 / (C.HZ or 20)
	local TELEPORT = C.TELEPORT_FRAME or 36
	local BIG_H = C.BIG_HEIGHT or 13
	local track = {} -- [model] = { prev, anchor, anchorT, sizeAt, big, off, h, half }
	local acc = 0
	S.counts.crash = S.counts.crash or 0
	S.counts.crashMovers = 0
	-- debug: Control:Invoke("crashlog", true) records every PLAYER sweep (speed, threshold, impacts) until turned off
	S.crashLog = {}
	local function note(uid, s)
		if S.crashDebug and uid then
			local log = S.crashLog
			log[#log + 1] = s
			if #log > 120 then
				table.remove(log, 1)
			end
		end
	end

	-- size of a body (refreshed twice a second): giant forms are parented INTO the character, so its box covers them
	local function measure(model, root, rec, t)
		if rec.sizeAt and t - rec.sizeAt < 0.5 then
			return
		end
		rec.sizeAt = t
		local ok, cf, ext = pcall(function()
			return model:GetBoundingBox()
		end)
		if not ok or not cf then
			rec.big = false
			return
		end
		rec.h = ext.Y
		rec.half = max(ext.X, ext.Z) * 0.5
		rec.off = cf.Position - root.Position
		-- tall AND really a form (a stray tall FX part inside a normal character must not turn it into a bulldozer)
		local sc = 1
		pcall(function()
			sc = model:GetScale()
		end)
		rec.big = ext.Y >= BIG_H and (sc >= 1.8 or model:GetAttribute("Morphed") == true
			or model:GetAttribute("Guardian") ~= nil or model:GetAttribute("TitanForm") ~= nil)
	end

	local function sweep(model, root, rec, from, to, dtS, uid, t, budget)
		local delta = to - from
		local dist = delta.Magnitude
		if dist < 0.05 or dist ~= dist then
			return 0
		end
		if t < (rec.holdUntil or 0) then
			return 0
		end
		if dist / dtS > (C.MAX_SPEED or 480) then
			rec.holdUntil = t + (C.TELEPORT_HOLD or 0.35) -- an interpolated client teleport, not a body moving
			note(uid, string.format("teleport %.0f/s to (%.0f,%.0f,%.0f)", dist / dtS, to.X, to.Y, to.Z))
			return 0
		end
		measure(model, root, rec, t)
		local hz = V3(delta.X, 0, delta.Z).Magnitude
		local vy = (C.VERTICAL_WEIGHT or 0.35) * delta.Y
		local eff = sqrt(hz * hz + vy * vy) / dtS
		local r, mult
		local pts
		if rec.big then
			if eff < (C.BIG_SPEED or 4) then
				return 0
			end
			local h = rec.h
			local n = clamp(ceil(h / (2 * max(rec.half, 4))), 1, 4)
			r = min(max(rec.half, h / (2 * n)), C.BIG_R_MAX or 40)
			mult = (C.BIG_MULT or 1.5) + eff / 60
			local bottom = rec.off.Y - h / 2
			pts = {}
			for i = 1, n do
				pts[i] = V3(rec.off.X, bottom + h * (i - 0.5) / n, rec.off.Z)
			end
		else
			local hum = model:FindFirstChildOfClass("Humanoid")
			local walk = 0
			if hum and not hum.PlatformStand and hum:GetState() ~= Enum.HumanoidStateType.Physics then
				walk = hum.WalkSpeed
			end
			local need = max(C.SPEED or 42, walk * (C.WALK_MULT or 1.35) + (C.WALK_PAD or 8))
			if eff < need then
				if eff > 20 then
					note(uid, string.format("slow %.0f<%.0f at (%.0f,%.0f,%.0f)", eff, need, to.X, to.Y, to.Z))
				end
				return 0
			end
			r = C.BODY_R or 3
			mult = clamp(eff / (C.MULT_PER or 55), 1, C.MULT_MAX or 5)
			pts = { ZERO }
		end
		local steps = clamp(ceil(dist / max(r, 2)), 1, C.MAX_STEPS or 8)
		local dir = delta.Unit
		local speedArg = min(eff, 400)
		local used = 0
		for s = 1, steps do
			local base = from + delta * (s / steps)
			for _, off in ipairs(pts) do
				if used >= budget then
					return used
				end
				local p = base + off
				if S.hasNear(p, r) then
					S.impact(p, r, dir, speedArg, uid, "crash", mult)
					used += 1
					S.counts.crash += 1
				end
			end
		end
		note(uid, string.format("hit %.0f/s x%.1f r%.0f steps %d impacts %d to (%.0f,%.0f,%.0f)%s", eff, mult, r, steps, used, to.X, to.Y, to.Z, rec.big and " BIG" or ""))
		return used
	end

	local list = {}
	local function gather()
		table.clear(list)
		for _, plr in ipairs(Players:GetPlayers()) do
			local ch = plr.Character
			if ch then
				list[#list + 1] = ch
				list[#list + 1] = plr.UserId
			end
		end
		if C.NPC ~= false then
			for _, name in ipairs({ "NPCs", "TitanSwarm" }) do
				local holder = workspace:FindFirstChild(name)
				if holder then
					for _, m in ipairs(holder:GetChildren()) do
						if m:IsA("Model") then
							local lh = m:GetAttribute("LastHitBy")
							list[#list + 1] = m
							list[#list + 1] = (type(lh) == "number") and lh or 0
						end
					end
				end
			end
		end
	end

	local seen = {}
	local conn = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		acc += dt
		local doSweep = acc >= PERIOD
		if doSweep then
			acc = 0
		end
		gather()
		table.clear(seen)
		local budget = C.MAX_PER_TICK or 48
		local movers = 0
		for i = 1, #list, 2 do
			local model, uid = list[i], list[i + 1]
			local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if root and root:IsA("BasePart") then
				seen[model] = true
				local pos = root.Position
				local rec = track[model]
				if not rec then
					rec = { prev = pos, anchor = pos, anchorT = t }
					track[model] = rec
				end
				if pos ~= pos or (pos - rec.prev).Magnitude > TELEPORT then
					rec.anchor, rec.anchorT = pos, t -- teleport / respawn / kit switch: nothing in between breaks
				end
				rec.prev = pos
				if doSweep then
					local from, dtS = rec.anchor, t - rec.anchorT
					rec.anchor, rec.anchorT = pos, t
					if dtS > 1e-3 and budget > 0 then
						local ok, used = pcall(sweep, model, root, rec, from, pos, dtS, (uid ~= 0) and uid or nil, t, budget)
						if ok and used > 0 then
							budget -= used
							movers += 1
						end
					end
				end
			end
		end
		if doSweep then
			for m in pairs(track) do
				if not seen[m] then
					track[m] = nil
				end
			end
			S.counts.crashMovers = movers
		end
	end)

	return {
		stop = function()
			conn:Disconnect()
		end,
	}
end

return Crash
