--!nocheck
-- ZangetsuServer.Moves.M1 (owner sword-m1): the 4-hit sword combo, authoritative (DESIGN.md 5.1-5.2, CONTRACT 4.3).
--   swing 1-3: oriented box (HitboxSize) Range ahead along the flat aim; standing bodies are cut + knocked + stunned,
--              corpses are juggled. swing 4: the cleave's front cone, a launching strike with hit-stop
--   (2026-11-08) a living body that was flung and is still down (PvP.isDown) is passed over by every swing and wave
--   mode (Tensa Zangetsu): every swing also throws a slash wave along the aim (swing 4: a mini Getsuga that flings)
-- Broadcasts: M1Swing { id, userId, t0, combo, dir, hitAt, mode, wave (studs, wall-clamped, or nil) }
--             M1Hit { id, userId, combo, model, pos, dir, final, mode, wave (bool) }
--             M1Cancel { id, userId } (added kind: the caster died / unequipped before the swing landed)
-- st.M1 = { combo, last, lockUntil, gen } (gen bumps on __reset so a pending swing never lands after a death)
local PvP = require(game:GetService("ServerScriptService"):WaitForChild("PvP"))
local HitReact = (function()
	local ok, m = pcall(require, game:GetService("ReplicatedStorage"):WaitForChild("GojoShared"):WaitForChild("HitReact", 10))
	return ok and m or nil
end)()

return function(S)
	local M = {}
	local CFG = S.CFG
	local UP = S.UP or Vector3.yAxis
	local FLAT = S.FLAT or Vector3.new(1, 0, 1)

	-- swings 1-3 throw the body around IN PLACE (the user: not flung back until the final hit): the forehand (R->L)
	-- knocks it to his left and spins its chest away, the backhand (L->R, rising) to his right, the overhead chop
	-- doubles it over. Only swing 4 launches. Returns the push direction + style for GojoShared.HitReact.
	local function reaction(combo, dir)
		local right = dir:Cross(UP)
		if right.Magnitude < 1e-3 then
			return dir, nil
		end
		right = right.Unit
		if combo == 1 then
			return (dir * 0.45 - right * 0.9).Unit, "twist"
		elseif combo == 2 then
			return (dir * 0.45 + right * 0.9 + UP * 0.35).Unit, "twist"
		end
		return (dir * 0.7 - UP * 0.4).Unit, "fold"
	end
	local function react(mdl, combo, dir, power)
		local push, style = reaction(combo, dir)
		if HitReact then
			pcall(HitReact.mark, mdl, push, power, style)
		end
		return push
	end

	local function pick(v, i)
		if type(v) == "table" then
			return v[i] or v[#v]
		end
		return v
	end

	-- a damage number for this swing. A field that Mode.M1 sets explicitly is final in mode (DECISIONS 9); every other
	-- one gets the mode multiplier exactly once (S.cfgFor may leave a per-swing LIST unmultiplied, so compare with base)
	local function damage(p, char, c, key, combo)
		local v = pick(c[key], combo)
		if type(v) ~= "number" then
			return 0
		end
		local mode = S.inMode(p, char)
		local modeT = CFG.Mode and CFG.Mode.M1
		if mode and modeT and modeT[key] ~= nil then
			return v
		end
		local base = CFG.M1 and pick(CFG.M1[key], combo)
		if mode and base == v then
			v *= S.dmgMul(p, char)
		end
		return v
	end

	local function state(st)
		local m = st.M1
		if type(m) ~= "table" then
			m = { combo = 0, last = -1e9, lockUntil = 0, gen = 0 }
			st.M1 = m
		end
		m.gen = m.gen or 0
		return m
	end

	local function resolve(p, st, char, id, gen, combo, final, dir, c, mode, wave)
		local m = st.M1
		if type(m) ~= "table" or m.gen ~= gen then
			return
		end
		local uid = p.UserId
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not S.valid(p, char) or not hrp then
			S.fire("M1Cancel", { id = id, userId = uid })
			S.release(p, id)
			return
		end
		local pos = hrp.Position
		local chest = pos + UP * 1.0
		local exclude = { [char] = true }
		-- (2026-11-10, "it's hard to hit people with the normal attack, especially when they're just running around") a
		-- PLAYER is also tested where it stood since this swing started, as the attacker saw it, in a slightly bigger
		-- shape (Core's o.lag -> PvP.lagOffsets + PvP.MELEE_PAD). delay = this swing's HitAt, the wait S.at puts between
		-- the server receiving the swing and this resolve. NPCs are tested exactly as before.
		local rewind = { by = p, delay = pick(c.HitAt, combo) or 0.14 }
		local hits
		if final then
			hits = S.inCone(pos, dir, c.FinalRadius or 11, c.FinalHalfAngle or 80, { los = chest, exclude = exclude, lag = rewind })
		else
			local cf = CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, -(c.Range or 6))
			hits = S.inBox(cf, c.HitboxSize or Vector3.new(9, 7, 8), { los = chest, exclude = exclude, lag = rewind })
		end
		local dmg = damage(p, char, c, "Damage", combo)
		local first
		PvP.m1Begin(final) -- (2026-11-09) M1 hits: full damage on players, and they break a cast; (2026-11-11) swing 4 breaks a block
		for _, h in ipairs(hits or {}) do
			local mdl = h.m
			local tp = mdl and mdl.Parent and S.torsoOf(mdl) -- a Part (query rows carry tp as a Vector3)
			if mdl and tp and not exclude[mdl] and not PvP.isDown(mdl) then
				exclude[mdl] = true
				first = first or tp.Position
				local fl = dir
				if final then
					local off = (tp.Position - pos) * FLAT
					local radial = off.Magnitude > 0.5 and off.Unit or dir
					local k = c.FinalFlingRadial or 0.6
					fl = (radial * k + dir * (1 - k))
					fl = fl.Magnitude > 1e-3 and fl.Unit or dir
					local L = c.FinalLaunch or Vector2.new(85, 45)
					local fv, fr = PvP.m1Finish(mdl, fl * L.X + UP * L.Y, c.RagTime or 2.6) -- (2026-11-09) a player stays within reach
					S.strike(p, mdl, fv, dmg, fr, { hitStop = c.FinalHitStop or 0.06 })
				elseif S.held(mdl) then
					react(mdl, combo, dir, 1)
					S.hurt(p, mdl, dmg)
				elseif S.alive(mdl) and not S.isRagdolled(mdl) then
					local push = react(mdl, combo, dir, combo == 3 and 1.25 or 1.1)
					S.hurt(p, mdl, dmg)
					S.stun(mdl, c.StunTime or 0.45)
					if HitReact and HitReact.slide then -- a stud or so along the swing: thrown around, still in reach
						HitReact.slide(mdl, push, c.HitSlide or 1, 0.12)
					else
						S.push(mdl, push * FLAT * (c.Knockback or 20) + UP * 2)
					end
				else
					local J = c.Juggle or Vector2.new(30, 32)
					local push = select(1, reaction(combo, dir)) * FLAT
					S.strike(p, mdl, push * J.X + UP * J.Y, dmg, c.RagTime or 2.6, { spin = push:Cross(UP) * 8 })
				end
				S.fire("M1Hit", {
					id = id, userId = uid, combo = combo, model = mdl, pos = tp.Position, dir = fl, final = final,
					mode = mode, wave = false,
				})
			end
		end
		PvP.m1End()
		S.hook("WorldBlast", first or (chest + dir * (c.Range or 6)), c.BlastRadius or 4.5, uid)
		if final then
			local g = S.groundAt(pos, 10)
			if g then
				S.ground("ring", g, c.RingRadius or 4, c.RingCount or 4, c.RingUp or 25)
			end
		end
		-- Tensa Zangetsu: the slash wave races `wave` studs along the aim; each body is cut when the wave reaches it
		if mode and type(wave) == "number" and wave > 0.5 then
			local travel = final and (c.FinalWaveTravel or 0.2) or (c.WaveTravel or 0.12)
			local wdmg = damage(p, char, c, final and "FinalWaveDamage" or "WaveDamage", combo)
			local list = S.nearSegment(chest, chest + dir * wave, c.WaveHalfWidth or 2.5, { los = chest, exclude = exclude, lag = rewind })
			for _, h in ipairs(list or {}) do
				local mdl = h.m
			local tp = mdl and mdl.Parent and S.torsoOf(mdl) -- a Part (query rows carry tp as a Vector3)
				if mdl and tp and not exclude[mdl] and not PvP.isDown(mdl) then
					exclude[mdl] = true
					local lag = travel * math.clamp((h.along or 0) / wave, 0, 1)
					task.delay(lag, function()
						if not mdl.Parent or type(st.M1) ~= "table" or st.M1.gen ~= gen or not S.valid(p, char) or PvP.isDown(mdl) then
							return
						end
						local tt = S.torsoOf(mdl) or tp
						if final then
							S.strike(p, mdl, dir * (c.FinalWaveFling or 120) + UP * (c.FinalWaveUp or 30), wdmg, c.RagTime or 2.6)
						else
							if not S.isRagdolled(mdl) then
								react(mdl, combo, dir, 0.9)
							end
							S.hurt(p, mdl, wdmg)
							if S.alive(mdl) and not S.held(mdl) and not S.isRagdolled(mdl) then
								S.stun(mdl, c.StunTime or 0.45)
							end
						end
						S.fire("M1Hit", {
							id = id, userId = uid, combo = combo, model = mdl, pos = tt.Position, dir = dir, final = final,
							mode = mode, wave = true,
						})
					end)
				end
			end
			task.delay(travel, function()
				S.hook("WorldBlast", chest + dir * wave, final and 5 or 3, uid)
			end)
		end
	end

	function M.M1(p, st, payload)
		local char, _, hrp, t = S.gate(p, "M1")
		if not char then
			return
		end
		local c = S.cfgFor(p, char, "M1")
		local m = state(st)
		if t - m.last < (c.SwingInterval or 0.34) - 0.04 or t < (m.lockUntil or 0) then
			return
		end
		if t - m.last > (c.ComboResetTime or 1.1) then
			m.combo = 0
		end
		local n = c.ComboLength or 4
		local combo = (m.combo or 0) % n + 1
		m.combo, m.last = combo, t
		local final = combo == n
		if final then
			m.lockUntil = t + (c.FinalCooldown or 0.85)
		end
		payload = type(payload) == "table" and payload or {}
		local mode = S.inMode(p, char)
		local dir = S.flatDir(payload.aim, hrp.CFrame.LookVector)
		local hitAt = pick(c.HitAt, combo) or 0.14
		local id = S.commit(p, "M1", t, pick(c.Lock, combo) or 0.16, char)
		local wave = nil
		if mode then
			local range = final and (c.FinalWaveRange or 30) or (c.WaveRange or 14)
			wave = math.max(S.clampPath(hrp.Position + UP * 1.0, dir, range) or range, 0)
		end
		local gen = m.gen
		S.fire("M1Swing", {
			id = id, userId = p.UserId, t0 = t, combo = combo, dir = dir, hitAt = hitAt, mode = mode, wave = wave,
		})
		S.at(t, hitAt, function()
			local ok, err = pcall(resolve, p, st, char, id, gen, combo, final, dir, c, mode, wave)
			if not ok then
				S.warn("M1", tostring(err))
				S.release(p, id)
			end
		end)
	end

	function M.__reset(p, st, why)
		local m = st and st.M1
		if type(m) == "table" then
			m.gen = (m.gen or 0) + 1
			m.combo, m.last, m.lockUntil = 0, -1e9, 0
		end
	end

	return M
end
