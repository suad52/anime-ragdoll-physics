--!nocheck
-- ReplicatedStorage.HudShared.SliderCatalog (2026-11-14, sandbox shop): the SANDBOX SLIDERS. Each is one perk
-- (HudShared.PerkCatalog item with `slider` = its key; the Sandbox Sliders Pack holds all six). Shared by the panel
-- (StarterPlayerScripts.SandboxSliders), the save (ShopService.Ext.Sliders) and the systems that apply them:
--   speed   -> player attribute SpeedMul    StarterPlayerScripts.PerkMovement: walk speed x it
--   jump    -> JumpMul                      PerkMovement: jump height x it
--   gravity -> GravityMul                   SandboxSliders: this client's own workspace.Gravity = world gravity x it
--                                           (the client simulates its own body, so only that player feels it)
--   health  -> HealthMax (+ GodMode)        ServerScriptService.PlayerHealth: MaxHealth; god = an invisible ForceField
--                                           and a refill, so nothing that uses TakeDamage can hurt that player
--   damage  -> DamageMul                    Sandbox.Main: weapon and power damage on dummies x it
--   fling   -> FlingMul                     Sandbox.Main + GojoServer.RagdollService.flingScale: how far your hits throw
-- `legacy` = the retired perk that owns that slider too (2x Speed / 2x Jump bought before the sliders), and the value
-- such an owner starts on (legacyValue, while that old toggle was on: legacyEquip = its ShopService equip field).
-- The track is GEOMETRIC between min and max, so x1 sits near the middle of an x0.25 - x4 range and both ends get room.
local C = Color3.fromRGB
local S = {}

S.STD_GRAVITY = 196.2 -- Roblox's default; the world's gravity is workspace attribute WorldGravity while an event changes it

S.LIST = {
	{ key = "speed", perk = "RunSlider", attr = "SpeedMul", name = "RUN SPEED", jp = "速度", min = 0.25, max = 4, default = 1, unit = "x",
		color = C(110, 255, 160), legacy = "SpeedX2", legacyEquip = "speed", legacyValue = 2, desc = "How fast you run." },
	{ key = "jump", perk = "JumpSlider", attr = "JumpMul", name = "JUMP HEIGHT", jp = "跳躍", min = 0.25, max = 6, default = 1, unit = "x",
		color = C(150, 170, 255), legacy = "JumpX2", legacyEquip = "jump", legacyValue = 2, desc = "How high you jump." },
	{ key = "gravity", perk = "GravitySlider", attr = "GravityMul", name = "GRAVITY", jp = "重力", min = 0.05, max = 2.5, default = 1, unit = "%",
		color = C(190, 140, 255), desc = "Your own gravity - float like a feather or drop like a rock." },
	{ key = "health", perk = "HealthSlider", attr = "HealthMax", name = "MAX HEALTH", jp = "体力", min = 25, max = 5000, default = 250, unit = "hp",
		color = C(90, 230, 140), god = true, desc = "Your max health, plus GOD MODE: nothing can hurt you." },
	{ key = "damage", perk = "StrengthSlider", attr = "DamageMul", name = "STRENGTH", jp = "力", min = 0.25, max = 10, default = 1, unit = "x",
		color = C(255, 90, 90), desc = "How hard your weapons and powers hit dummies." },
	{ key = "fling", perk = "FlingSlider", attr = "FlingMul", name = "FLING POWER", jp = "吹飛", min = 0.25, max = 6, default = 1, unit = "x",
		color = C(90, 200, 255), desc = "How far your hits and throws send bodies." },
}
S.PACK = "SliderPack"
S.byKey, S.byPerk = {}, {}
for i, d in ipairs(S.LIST) do
	d.order = i
	S.byKey[d.key] = d
	S.byPerk[d.perk] = d
end

function S.clamp(def, v)
	v = tonumber(v)
	if not v or v ~= v then
		return def.default
	end
	return math.clamp(v, def.min, def.max)
end

-- a tidy value: health in 25 / 50 / 100 hp steps, gravity in 5% steps, multipliers 0.05 / 0.1 / 0.25
function S.snap(def, v)
	v = S.clamp(def, v)
	local step
	if def.unit == "hp" then
		step = v < 500 and 25 or (v < 2000 and 50 or 100)
	elseif def.unit == "%" then
		step = 0.05
	else
		step = v < 2 and 0.05 or (v < 5 and 0.1 or 0.25)
	end
	return S.clamp(def, math.floor(v / step + 0.5) * step)
end

-- track position 0..1 <-> value (geometric)
function S.alpha(def, v)
	v = S.clamp(def, v)
	return math.log(v / def.min) / math.log(def.max / def.min)
end
function S.value(def, a)
	a = math.clamp(a, 0, 1)
	local v = def.min * (def.max / def.min) ^ a
	-- a little sticky around the default, so it is easy to put back
	if math.abs(a - S.alpha(def, def.default)) < 0.018 then
		return def.default
	end
	return S.snap(def, v)
end

function S.format(def, v)
	v = S.clamp(def, v)
	if def.unit == "hp" then
		return string.format("%d", math.floor(v + 0.5))
	elseif def.unit == "%" then
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
	return "x" .. s
end

return S
