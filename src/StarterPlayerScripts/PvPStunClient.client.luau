--!nocheck
-- StarterPlayerScripts.PvPStunClient (2026-11-08): PvP stun + ragdoll on MY character (the server can't move it).
--   STUN    while my character's StunnedUntil (server time - the kits and HitReactServer stamp it on whoever they hit)
--           is in the future, or while I'm ragdolled: no walking, no jumping - the way a stunned NPC stands still.
--           This place has no PlayerModule to switch off, so every frame, right after the input step, the humanoid's
--           move direction is zeroed and its jump cleared (works for keyboard, gamepad and touch alike; knockback
--           impulses still move the body). The server refuses my moves for the same window (ServerScriptService.PvP
--           .stunned). Super-armour forms (SuperArmor, the guardian, Ultra Instinct) ignore it.
--   RAGDOLL while the server has my rig loosened (character attribute Ragdolled, ServerScriptService.PvP.ragdoll) my
--           humanoid goes limp (Physics), so a tumble is a real ragdoll instead of a plank; it gets up when the
--           server puts the rig back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function immune(char)
	return char:GetAttribute("SuperArmor") or char:GetAttribute("Guardian") or char:GetAttribute("AscForm") == "Instinct"
end

local locked = false
local function setLocked(on)
	locked = on
end

local function lockedNow()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or immune(char) then
		return nil
	end
	local su = tonumber(char:GetAttribute("StunnedUntil")) or 0
	if su > workspace:GetServerTimeNow() or char:GetAttribute("Ragdolled") == true then
		return hum, char
	end
	return nil
end

-- after the control scripts have written this frame's move + jump (RenderPriority.Input), take them back
RunService:BindToRenderStep("PvPStunLock", Enum.RenderPriority.Input.Value + 1, function()
	local hum = lockedNow()
	if hum then
		hum:Move(Vector3.zero, false)
		hum.Jump = false
	end
end)

local function hookChar(char)
	setLocked(false)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	char:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if hum.Health <= 0 then
			return
		end
		if char:GetAttribute("Ragdolled") then
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		elseif hum:GetState() == Enum.HumanoidStateType.Physics then
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

player.CharacterAdded:Connect(hookChar)
if player.Character then
	task.spawn(hookChar, player.Character)
end

RunService.Stepped:Connect(function()
	local hum, char = lockedNow()
	setLocked(hum ~= nil)
	if hum then
		hum:Move(Vector3.zero, false)
		hum.Jump = false
		if char:GetAttribute("Ragdolled") and hum:GetState() ~= Enum.HumanoidStateType.Physics and hum:GetState() ~= Enum.HumanoidStateType.Dead then
			hum:ChangeState(Enum.HumanoidStateType.Physics) -- a kit's tumble handler set PlatformStand after we went limp
		end
	end
end)
