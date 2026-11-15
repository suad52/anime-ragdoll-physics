--!nocheck
-- ZangetsuServer.Moves.BankaiGrab (2026-11-08, "give him a recast as a grab attack which he can use to string into a
-- combo"): G AGAIN inside Tensa Zangetsu - TENSA GRAB, the combo starter. ZangetsuClient sends "BankaiGrab" instead
-- of "Bankai" while its character's BankaiUntil runs; outside the mode this refuses. Numbers: Config.BankaiGrab.
--   0.00     gate (its own cooldown) + the pick: the body under the cursor, else the nearest body in front - alive and
--            STANDING (never one already down or held: the grab starts a combo, it can't pick a body up off the floor
--            past the "no M1 on the ground" rule), no giant forms, line of sight from his chest. The victim is stunned
--            at once (it can't walk out of the dash). BankaiGrabCast to every client.
--   DashAt   (his own client) he flash-steps to `arrive`: HoldDist short of the victim and Side to its right, so the
--            victim stands in front of his LEFT (free) hand
--   GrabAt   the victim is HELD: GrabbedBy = his userId, its root anchored and pinned every Heartbeat to his hand -
--            where it stood at GrabAt, raised into the lift (LiftDist ahead, Lift up) by LiftAt, shaking in the grip,
--            then from SlamAt driven down and forward onto its feet at the drop point. Anchoring works on a player
--            victim too: an anchored part has no network owner, so the server's pin replicates to its own client.
--   Crush[i] a crushing pulse: CrushDamage (BankaiGrabTick)
--   ReleaseAt set down ON ITS FEET DropDist in front of him (wall-clamped), unanchored, ReleaseDamage, stunned for
--            Stagger while standing - so the M1 (which skips bodies that are down) connects. BankaiGrabRelease.
-- Every exit lets go: the release, the victim dying / leaving / being taken by something else, the caster dying /
-- unequipping / leaving (__reset), a timeline error (BankaiGrabCancel). Nothing in reach: a clutch at the air
-- (BankaiGrabCast with whiff = true), WhiffCooldown.
return function(S)
	local M = {}
	local Players = game:GetService("Players")
	local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP"))
	local UP, FLAT = S.UP or Vector3.yAxis, S.FLAT or Vector3.new(1, 0, 1)

	local function num(v, d)
		return type(v) == "number" and v or d
	end
	local function cfg()
		return type(S.CFG.BankaiGrab) == "table" and S.CFG.BankaiGrab or {}
	end
	local function rootOf(m)
		return typeof(m) == "Instance" and m:FindFirstChild("HumanoidRootPart") or nil
	end
	-- a standing root's height over the floor under it
	local function hipOf(r)
		local fb = S.floorBelow(r.Position, 30)
		return fb and math.clamp(r.Position.Y - fb.Y, 1, 12) or 3
	end

	local holds = {} -- [Player] = the live hold { id, uid, target, freed, anchored, wasAnchored }

	-- let the victim go (undoing only what this hold set), standing at standCF when given
	local function letGo(h, standCF)
		if not h or h.freed then
			return
		end
		h.freed = true
		local m = h.target
		local r = rootOf(m)
		if r and r.Parent and h.anchored then
			if typeof(standCF) == "CFrame" then
				r.CFrame = standCF
			end
			r.Anchored = h.wasAnchored == true
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end
		if m and m.Parent and m:GetAttribute("GrabbedBy") == h.uid then
			m:SetAttribute("GrabbedBy", nil)
		end
	end

	local function grabbable(m, char)
		if m == char or not S.alive(m) or S.held(m) then
			return false
		end
		if PvP.isDown(m) or S.isRagdolled(m) or PvP.isForm(m) then
			return false
		end
		if m:GetAttribute("SlashedBy") ~= nil or m:GetAttribute("WhippedBy") ~= nil then
			return false -- another move already has it
		end
		if m:GetAttribute("AscForm") == "Instinct" or m:GetAttribute("SuperArmor") or m:GetAttribute("Guardian") then
			return false
		end
		return rootOf(m) ~= nil
	end

	local function pick(char, hrp, payload, G)
		local origin = hrp.Position
		local _, flat = S.aimOf(payload, hrp, -30, 30)
		local cursor = type(payload) == "table" and payload.target or nil
		if not S.finite(cursor) then
			cursor = nil
		end
		local best, bestScore
		local hits = S.inRadius(origin, num(G.Range, 30), {
			alive = true, los = origin + UP * 1.5, skipHeld = true, maxDY = num(G.MaxDY, 12),
		}) or {}
		for _, h in ipairs(hits) do
			local m = h.m
			if grabbable(m, char) then
				local ang = S.angleTo((h.tp - origin) * FLAT, flat)
				local onCursor = cursor ~= nil and ((h.tp - cursor) * FLAT).Magnitude <= num(G.CursorRadius, 7)
				if onCursor or ang <= num(G.HalfAngle, 75) then
					local score = h.d + ang * 0.12 - (onCursor and 100 or 0)
					if not bestScore or score < bestScore then
						best, bestScore = h, score
					end
				end
			end
		end
		return best, flat
	end

	function M.BankaiGrab(p, st, payload)
		local c0 = p.Character
		if not c0 or not S.inMode(p, c0) then
			return -- the recast exists only inside Tensa Zangetsu
		end
		local char, _, hrp, t = S.gate(p, "BankaiGrab")
		if not char then
			return
		end
		local G = cfg()
		local uid = p.UserId
		local best, flat = pick(char, hrp, payload, G)

		if not best then
			-- a clutch at the air: a short lock and a short cooldown (no S.commit: that would start the full one)
			st.id += 1
			local id = st.id
			local lock = num(G.WhiffLock, 0.45)
			st.busyUntil = math.max(st.busyUntil, t + lock)
			st.cd.BankaiGrab = t + num(G.WhiffCooldown, 1.5)
			S.fireTo(p, "Cooldown", { skill = "BankaiGrab", ends = st.cd.BankaiGrab })
			S.fire("BankaiGrabCast", { id = id, userId = uid, t0 = t, origin = hrp.Position, face = flat, lock = lock, whiff = true })
			return
		end

		local m = best.m
		local tr = rootOf(m)
		local origin = hrp.Position
		local toV = S.flatDir(tr.Position - origin, flat)
		local right = toV:Cross(UP)
		-- he arrives HoldDist short of the victim and Side to its right, so it stands in front of his LEFT hand
		local hold, side = num(G.HoldDist, 1.8), num(G.Side, 1.0)
		local want = tr.Position - toV * hold + right * side
		if S.clampPath(tr.Position - toV * hold, right, side + 2) < side then
			want, side = tr.Position - toV * hold, 0 -- a wall at his right: straight in front instead
		end
		local arrivePos = S.standAt(hrp, want)
		if not S.finite(arrivePos) then
			arrivePos = origin
		end
		local arriveCF = CFrame.lookAt(arrivePos, arrivePos + toV)
		local vHip, cHip = hipOf(tr), hipOf(hrp)
		local dy = vHip - cHip -- a taller / shorter rig stands its root higher / lower
		local function facing(pos)
			return CFrame.lookAt(pos, pos - toV) -- the victim faces him
		end
		-- the hold: where it stands (in front of his left hand), the lift, and the drop - centred in front of him for
		-- the M1 and clamped short of a wall
		local grabCF = facing(arrivePos + toV * hold - right * side + UP * dy)
		local liftCF = facing(arrivePos + toV * num(G.LiftDist, 1.65) - right * side + UP * (dy + num(G.Lift, 0.7)))
		local room = S.clampPath(arrivePos, toV, num(G.DropDist, 4.2) + 2)
		local dropD = math.clamp(room, 2.2, num(G.DropDist, 4.2))
		local dropPos = arrivePos + toV * dropD
		local fb = S.floorBelow(dropPos + UP * 3, 20)
		dropPos = fb and Vector3.new(dropPos.X, fb.Y + vHip, dropPos.Z) or (dropPos + UP * dy)
		local dropCF = facing(dropPos)
		local slotPos = liftCF.Position -- the client draws the grip from here

		local lock = num(G.Lock, 0.92)
		local id = S.commit(p, "BankaiGrab", t, lock, char)
		local dashAt, grabAt = num(G.DashAt, 0.1), num(G.GrabAt, 0.16)
		local liftAt, slamAt = num(G.LiftAt, 0.3), num(G.SlamAt, 0.74)
		local releaseAt, stagger = num(G.ReleaseAt, 0.84), num(G.Stagger, 1.3)
		local crush = type(G.Crush) == "table" and G.Crush or { 0.36, 0.52, 0.68 }
		pcall(S.stun, m, releaseAt + stagger) -- frozen through the dash; still stunned after the release

		letGo(holds[p])
		local h = { id = id, uid = uid, target = m, freed = false }
		holds[p] = h
		S.fire("BankaiGrabCast", {
			id = id, userId = uid, t0 = t, origin = origin, face = toV, lock = lock, arrive = arriveCF, target = m,
			slot = slotPos, drop = dropPos, dashAt = dashAt, grabAt = grabAt, crush = crush, releaseAt = releaseAt,
			stagger = stagger,
		})

		local function cancel(why)
			letGo(h)
			if holds[p] == h then
				holds[p] = nil
			end
			S.fire("BankaiGrabCancel", { id = id, userId = uid, why = why })
			S.release(p, id)
		end

		local grabbed, nextCrush = false, 1
		S.timeline("BankaiGrab", t, function(e)
			if h.freed then
				return true
			end
			if not S.valid(p, char) then
				cancel("caster")
				return true
			end
			local r = rootOf(m)
			if not r or not m.Parent or not S.alive(m) then
				cancel("victim")
				return true
			end
			if not grabbed and e >= grabAt then
				if S.held(m) then
					cancel("taken") -- a Blue grab / a domain got it first
					return true
				end
				grabbed = true
				m:SetAttribute("GrabbedBy", uid)
				h.wasAnchored = r.Anchored
				h.anchored = true
				r.Anchored = true
			end
			if grabbed then
				-- the hold follows his left hand: raised from where it stood into the lift, shaking in the grip through
				-- the crush, then slammed down and forward onto its feet. The jitter also changes the CFrame every frame,
				-- so the pin keeps re-replicating to a player victim's own client (an unchanged value would not resend)
				local cf
				if e < liftAt then
					local k = math.clamp((e - grabAt) / math.max(liftAt - grabAt, 0.01), 0, 1)
					cf = grabCF:Lerp(liftCF, k * k * (3 - 2 * k))
				elseif e < slamAt then
					cf = liftCF
				else
					local k = math.clamp((e - slamAt) / math.max(releaseAt - slamAt, 0.01), 0, 1)
					cf = liftCF:Lerp(dropCF, k * k)
				end
				local j = (e < slamAt) and math.sin(e * 55) * 0.06 or 0.01 * math.sin(e * 90)
				r.CFrame = cf * CFrame.new(j, math.cos(e * 41) * 0.04, 0) * CFrame.Angles(0, 0, j * 0.6)
			end
			while nextCrush <= #crush and e >= crush[nextCrush] do
				local i = nextCrush
				nextCrush += 1
				if grabbed then
					S.hurt(p, m, num(G.CrushDamage, 4))
					S.fire("BankaiGrabTick", { id = id, userId = uid, i = i, pos = slotPos })
				end
			end
			if e >= releaseAt then
				letGo(h, dropCF)
				if holds[p] == h then
					holds[p] = nil
				end
				if grabbed and m.Parent then
					S.hurt(p, m, num(G.ReleaseDamage, 10))
					pcall(S.stun, m, stagger)
				end
				S.fire("BankaiGrabRelease", { id = id, userId = uid, pos = dropPos, model = m })
				S.log("BankaiGrab: %s held and dropped %s", p.Name, m.Name)
				return true
			end
			return false
		end, function()
			cancel("error")
		end)
	end

	-- died / respawn / unequip / left: let the victim go at once
	function M.__reset(p, st, why)
		local h = holds[p]
		if h then
			holds[p] = nil
			letGo(h)
			S.fire("BankaiGrabCancel", { id = h.id, userId = h.uid, why = why or "reset" })
		end
	end

	return M
end
