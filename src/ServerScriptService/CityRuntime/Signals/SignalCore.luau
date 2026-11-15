-- ServerScriptService.CityRuntime.Signals.SignalCore - the pure signal cycle (streets builder, 2026-11-07).
-- states(t, signals) -> lit, attrs: lit["<Group>|<Lamp>"] = true/false for every group in CONTRACT.md section 7, at
-- t seconds after the epoch; attrs = { ScramblePhase, ScramblePhaseEnd (t of its end), CrossPhase, CrossPhaseEnd }.
local Core = {}

local function cycle(order, t)
	local total = 0
	for _, p in ipairs(order) do
		total += p[2]
	end
	local m = t % total
	local base = t - m
	local acc = 0
	for _, p in ipairs(order) do
		if m < acc + p[2] then
			return p[1], base + acc + p[2], acc + p[2] - m
		end
		acc += p[2]
	end
	return order[1][1], base + total, total - m
end
Core.cycle = cycle

function Core.orders(signals)
	local sc, cr = signals.scramble, signals.cross
	return { { "stop", sc.stop }, { "walk", sc.walk }, { "flash", sc.flash } },
		{ { "x", cr.x }, { "allred", cr.allred1 }, { "z", cr.z }, { "allred", cr.allred2 } }
end

function Core.states(t, signals)
	local scrOrder, crossOrder = Core.orders(signals)
	local sp, sEnd, sRem = cycle(scrOrder, t)
	local cp, cEnd, cRem = cycle(crossOrder, t)
	local blink = (t % 1) < 0.5
	local lit = {}
	-- pedestrians
	lit["scramble|walk"] = (sp == "walk") or (sp == "flash" and blink)
	lit["scramble|stop"] = (sp == "stop")
	for _, g in ipairs({ "x", "z" }) do
		local go = (cp == g)
		lit[g .. "|walk"] = go and (cRem > 4 or blink)
		lit[g .. "|stop"] = not go
	end
	-- vehicles: green while their phase runs (amber its last 3 s), red otherwise
	local function veh(group, green, rem)
		lit[group .. "|green"] = green and rem > 3
		lit[group .. "|amber"] = green and rem <= 3
		lit[group .. "|red"] = not green
	end
	veh("scramble_veh", sp == "stop", sRem)
	veh("veh_x", cp == "x", cRem)
	veh("veh_z", cp == "z", cRem)
	return lit, { ScramblePhase = sp, ScramblePhaseEnd = sEnd, CrossPhase = cp, CrossPhaseEnd = cEnd }
end

Core.LAMP_COLOR = { walk = "SIGNAL_GREEN", stop = "SIGNAL_RED", green = "SIGNAL_GREEN", amber = "SIGNAL_AMBER", red = "SIGNAL_RED" }

function Core.paint(part, lamp, on, palette)
	if on then
		part.Color = palette[Core.LAMP_COLOR[lamp] or "SIGNAL_OFF"]
		part.Material = Enum.Material.Neon
	else
		part.Color = palette.SIGNAL_OFF
		part.Material = Enum.Material.SmoothPlastic
	end
end

return Core
