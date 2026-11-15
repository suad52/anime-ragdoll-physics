-- ServerScriptService.DayNightService (2026-11-07): starts the day/night cycle. It only stamps the shared clock -
-- workspace "DayNightEpoch" = the server time (workspace:GetServerTimeNow()) when the cycle's clock read 0:00 - and every
-- client paints Lighting from it (StarterPlayerScripts.DayNightClient, look + timing in ReplicatedStorage.CityShared.DayNight).
-- The server itself never writes Lighting.
--
-- Studio test hooks (workspace attributes, read live by every client):
--   DayNightFreeze = <ClockTime>  hold the sky at that hour (nil = run)
--   DayNightSpeed  = <number>     run the cycle this many times faster (nil = 1)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DN = require(ReplicatedStorage:WaitForChild("CityShared"):WaitForChild("DayNight"))

workspace:SetAttribute("DayNightCycle", DN.CYCLE)
workspace:SetAttribute("DayNightEpoch", workspace:GetServerTimeNow() - DN.secondsAt(DN.START_CLOCK))
workspace:SetAttribute("DayNightEnabled", DN.ENABLED)
print(string.format("[DayNight] online - a %d-minute day, starting at %.1f h", math.floor(DN.CYCLE / 60 + 0.5), DN.START_CLOCK))
