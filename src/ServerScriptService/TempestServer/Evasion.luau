--!nocheck
-- Evasion: the eye mode's auto-dodge, shared by every kit. Right before a kit applies a MELEE hit to a player,
-- it calls Evasion.tryEvade(victimCharacter, attackerModel); true means the hit was dodged (the victim blinked
-- behind the attacker) and the kit should skip it. TempestService installs the main handler (setHandler); other
-- dodge forms (the Ascendant kit's silver form) add theirs with addHandler. Any handler returning true = dodged.
local Evasion = {}
Evasion.handlers = {}

function Evasion.setHandler(fn)
	Evasion.handler = fn
end

function Evasion.addHandler(fn)
	table.insert(Evasion.handlers, fn)
end

function Evasion.tryEvade(victim, attacker)
	if not victim then
		return false
	end
	if Evasion.handler then
		local ok, dodged = pcall(Evasion.handler, victim, attacker)
		if ok and dodged == true then
			return true
		end
	end
	for _, fn in ipairs(Evasion.handlers) do
		local ok, dodged = pcall(fn, victim, attacker)
		if ok and dodged == true then
			return true
		end
	end
	return false
end

return Evasion
