--!nocheck
-- ReplicatedStorage.CityShared.DayNight (2026-11-07): the day/night cycle - one source of truth for its clock and look.
-- ServerScriptService.DayNightService stamps workspace "DayNightEpoch" (server time when the cycle's clock was 0:00);
-- every client (StarterPlayerScripts.DayNightClient) turns the shared server time into the same ClockTime and paints
-- Lighting from the KEYS below, so every player sees the same sky. Nothing on the server writes Lighting.
--
-- Night is the city's signature neon look (the Lighting the map was built with); day is a clear blue sky. The night
-- skybox (Lighting.Sky's own textures) is swapped for Roblox's default sky in daylight, around sunrise / sunset.
-- Tuning: change PHASES (how long each part of the day lasts, in real seconds) and KEYS (the look at a clock time).
local M = {}

M.ENABLED = true
-- a new server starts its first day here (the neon evening the city was designed in)
M.START_CLOCK = 20.6

-- one full day, from midnight, in order. from / to = in-game ClockTime (hours), secs = real seconds that stretch lasts.
-- 15 minutes a day: ~6.75 min of night, ~5.5 min of daylight, ~1.5 min for each sunrise / sunset.
M.PHASES = {
	{ name = "night", from = 0, to = 5, secs = 210 },
	{ name = "dawn", from = 5, to = 7.5, secs = 75 },
	{ name = "day", from = 7.5, to = 16.5, secs = 330 },
	{ name = "dusk", from = 16.5, to = 19.5, secs = 90 },
	{ name = "night", from = 19.5, to = 24, secs = 195 },
}
M.CYCLE = 0
for _, ph in ipairs(M.PHASES) do
	M.CYCLE += ph.secs
end

-- the skybox: the night textures before SKY_DAY_FROM and after SKY_NIGHT_FROM, Roblox's default sky in between
M.SKY_DAY_FROM = 5.9
M.SKY_NIGHT_FROM = 18.7

-- street lamps / signs (Lights under workspace.City) are scaled by `lights` in each key (1 = as built)
M.LIGHTS_ROOT = "City"

-- banners when the day turns (StarterPlayerScripts.DayNightClient shows them)
M.BANNERS = {
	{ at = 6.0, text = "DAYBREAK", jp = "夜明け", color = Color3.fromRGB(255, 190, 120) },
	{ at = 18.9, text = "NIGHTFALL", jp = "日暮れ", color = Color3.fromRGB(170, 140, 255) },
}

local C = Color3.fromRGB
-- the look at a clock time; values in between are eased. NIGHT = exactly the map's built Lighting.
local NIGHT = {
	Brightness = 2.2, Ambient = C(52, 48, 76), OutdoorAmbient = C(110, 100, 156), ExposureCompensation = 0.35,
	EnvironmentDiffuseScale = 0.5, EnvironmentSpecularScale = 1,
	atm = { Density = 0.33, Offset = 0.06, Color = C(150, 104, 196), Decay = C(44, 32, 86), Glare = 0.35, Haze = 2.2 },
	grade = { Brightness = 0.03, Contrast = 0.14, Saturation = 0.12, TintColor = C(232, 226, 255) },
	bloom = { Intensity = 1.05, Threshold = 0.9, Size = 28 },
	rays = { Intensity = 0.03, Spread = 0.6 },
	lights = 1,
}
local DAWN = {
	Brightness = 2.4, Ambient = C(92, 74, 98), OutdoorAmbient = C(150, 112, 140), ExposureCompensation = 0.2,
	EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 1,
	atm = { Density = 0.36, Offset = 0.1, Color = C(255, 172, 150), Decay = C(122, 82, 140), Glare = 0.6, Haze = 2.4 },
	grade = { Brightness = 0.03, Contrast = 0.12, Saturation = 0.15, TintColor = C(255, 236, 232) },
	bloom = { Intensity = 0.9, Threshold = 1, Size = 26 },
	rays = { Intensity = 0.12, Spread = 0.55 },
	lights = 0.55,
}
local DAY = {
	Brightness = 3, Ambient = C(118, 116, 136), OutdoorAmbient = C(150, 150, 172), ExposureCompensation = 0.05,
	EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1,
	atm = { Density = 0.28, Offset = 0.12, Color = C(199, 220, 255), Decay = C(106, 140, 190), Glare = 0.15, Haze = 1.1 },
	grade = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.08, TintColor = C(255, 252, 248) },
	bloom = { Intensity = 0.6, Threshold = 1.3, Size = 24 },
	rays = { Intensity = 0.06, Spread = 0.5 },
	lights = 0.12,
}
local DUSK = {
	Brightness = 2.4, Ambient = C(98, 66, 92), OutdoorAmbient = C(160, 102, 132), ExposureCompensation = 0.25,
	EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 1,
	atm = { Density = 0.38, Offset = 0.08, Color = C(255, 142, 122), Decay = C(132, 60, 122), Glare = 0.7, Haze = 2.6 },
	grade = { Brightness = 0.03, Contrast = 0.13, Saturation = 0.18, TintColor = C(255, 230, 236) },
	bloom = { Intensity = 1, Threshold = 0.95, Size = 27 },
	rays = { Intensity = 0.12, Spread = 0.55 },
	lights = 0.8,
}
-- (clock, look) in order; the list wraps at 24
M.KEYS = {
	{ 0, NIGHT },
	{ 4.6, NIGHT },
	{ 6.2, DAWN },
	{ 7.8, DAY },
	{ 16.2, DAY },
	{ 17.9, DUSK },
	{ 19.6, NIGHT },
	{ 24, NIGHT },
}

-- seconds into the cycle -> ClockTime
function M.clockAt(s)
	s = s % M.CYCLE
	for _, ph in ipairs(M.PHASES) do
		if s < ph.secs then
			return ph.from + (ph.to - ph.from) * (s / ph.secs)
		end
		s -= ph.secs
	end
	return 0
end

-- ClockTime -> seconds into the cycle (the inverse of clockAt)
function M.secondsAt(clock)
	clock = clock % 24
	local acc = 0
	for _, ph in ipairs(M.PHASES) do
		if clock < ph.to then
			return acc + ph.secs * (clock - ph.from) / (ph.to - ph.from)
		end
		acc += ph.secs
	end
	return 0
end

function M.phaseAt(clock)
	clock = clock % 24
	for _, ph in ipairs(M.PHASES) do
		if clock < ph.to then
			return ph.name
		end
	end
	return "night"
end

-- 0 in full daylight .. 1 at night (from the lights curve; drives lamps and the HUD)
function M.nightness(clock)
	local look = M.sample(clock)
	return math.clamp((look.lights - DAY.lights) / (NIGHT.lights - DAY.lights), 0, 1)
end

local function mix(a, b, t)
	if type(a) == "number" then
		return a + (b - a) * t
	end
	return a:Lerp(b, t) -- Color3
end
local function mixTable(a, b, t)
	local out = {}
	for k, v in pairs(a) do
		if type(v) == "table" then
			out[k] = mixTable(v, b[k], t)
		else
			out[k] = mix(v, b[k], t)
		end
	end
	return out
end
M.mixTable = mixTable

-- the eased look at a clock time
function M.sample(clock)
	clock = clock % 24
	local keys = M.KEYS
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if clock >= a[1] and clock <= b[1] then
			local span = b[1] - a[1]
			local t = span > 0 and (clock - a[1]) / span or 0
			t = t * t * (3 - 2 * t) -- smoothstep
			return mixTable(a[2], b[2], t)
		end
	end
	return mixTable(NIGHT, NIGHT, 0)
end

-- the shared clock right now (nil until the server has stamped it, or with the cycle switched off). Studio test hooks:
-- workspace DayNightFreeze = <ClockTime> holds the hour, DayNightSpeed = <n> runs the day n times faster.
function M.clockNow()
	if workspace:GetAttribute("DayNightEnabled") == false then
		return nil
	end
	local freeze = workspace:GetAttribute("DayNightFreeze")
	if type(freeze) == "number" then
		return freeze % 24
	end
	local epoch = workspace:GetAttribute("DayNightEpoch")
	if type(epoch) ~= "number" then
		return nil
	end
	local speed = tonumber(workspace:GetAttribute("DayNightSpeed")) or 1
	return M.clockAt((workspace:GetServerTimeNow() - epoch) * speed)
end

-- NIGHT OUTLINES (2026-11-07, StarterPlayerScripts.NightOutlines): a faint outline round people after dark so they
-- read against the city. OutlineTransparency at full night (1 = invisible); they fade in with the dusk.
M.OUTLINES = {
	ENABLED = true,
	NPC = 0.62, -- every city NPC, one Highlight over the whole workspace.NPCs model
	PLAYER = 0.5, -- other players, tinted with their fighter's colour
	NPC_COLOR = Color3.fromRGB(205, 215, 255),
	MAX_PLAYERS = 8, -- nearest first; the engine draws at most 31 Highlights and the kits use some
	RANGE = 320,
	FADE_FROM = 0.3, -- nightness (0 day .. 1 night) where they start to show
}

function M.skyIsDay(clock)
	clock = clock % 24
	return clock >= M.SKY_DAY_FROM and clock < M.SKY_NIGHT_FROM
end

return M
