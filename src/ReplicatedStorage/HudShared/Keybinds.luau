--!nocheck
-- HudShared.Keybinds (2026-11-11, "have the option to have keybinds"): the ONE place every client script asks "which
-- action did this key press mean?". CLIENT only. An action is named by its DEFAULT key - the key every kit's code and
-- Config already use - so converting a script is mechanical:
--   input.KeyCode == Enum.KeyCode.Q              ->  Keybinds.logical(input.KeyCode) == Enum.KeyCode.Q
--   CFG.Keys lookups / reverse maps on input.KeyCode -> look up Keybinds.logical(input.KeyCode) instead
--   UserInputService:IsKeyDown(Enum.KeyCode.Q)  ->  Keybinds.isDown(Enum.KeyCode.Q)
--   a key label "Q" drawn on a button          ->  Keybinds.label(Enum.KeyCode.Q) (+ refresh on Keybinds.Changed)
-- API
--   Keybinds.logical(physicalKey) -> the default key whose action is bound to that physical key; the key itself when
--     nothing was moved onto it; Enum.KeyCode.Unknown when the key's own action was moved to another key (so the old
--     key stops firing it). Anything that is not a KeyCode passes through unchanged.
--   Keybinds.physical(defaultKey) -> the key currently bound to that action
--   Keybinds.isDown(defaultKey) -> boolean
--   Keybinds.label(defaultKey) -> short text for a key chip ("Q", "LCTRL", "SHIFT", "1" ...)
--   Keybinds.ACTIONS -> ordered { { key = Enum.KeyCode, name = "...", hint = "..." } } (the rebindable actions;
--     SettingsMenu's CONTROLS tab draws this list)
--   Keybinds.set(defaultKey, physicalKey | nil) -> ok, reason. nil = back to default. Binding a key another action uses
--     SWAPS the two. Keys in Keybinds.FORBIDDEN (movement, Escape, chat, camera...) are refused.
--   Keybinds.reset() ; Keybinds.serialize() -> "Q=Z;E=V" (only changed actions) ; Keybinds.load(str)
--   Keybinds.Changed (RBXScriptSignal) fires after any change
-- The player's saved binds arrive as Settings.keys (the Settings attribute JSON, ShopService.Ext.Settings) and are
-- loaded at require time and whenever the attribute changes; SettingsMenu sends edits with ShopRequest "settings".
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local K = Enum.KeyCode
local Keybinds = {}

Keybinds.ACTIONS = {
	{ key = K.Q, name = "MOVE 1", hint = "first ability" },
	{ key = K.E, name = "MOVE 2", hint = "second ability" },
	{ key = K.R, name = "MOVE 3", hint = "third ability" },
	{ key = K.F, name = "MOVE 4", hint = "Naruto's Kurama, Goku's flight" },
	{ key = K.G, name = "ULTIMATE", hint = "your fighter's ultimate" },
	{ key = K.X, name = "RELEASE", hint = "leave a giant form" },
	-- (2026-11-14) DASH removed with the dash itself (owner: "remove dashing from this game"); breaking out of a stun is the
	-- BLOCK key now. A saved "LeftShift=..." bind is simply ignored by decode (not an action any more).
	{ key = K.Z, name = "BLOCK", hint = "hold to block hits from the front; while stunned: break out" }, -- (2026-11-11) StarterPlayerScripts.GuardClient
	{ key = K.LeftShift, name = "SHIFT LOCK", hint = "lock the camera behind you" },
	{ key = K.B, name = "EMOTES", hint = "emote wheel" },
	-- (2026-11-15) TAUNTS removed (owner: "remove the taunts"); a saved "T=..." bind is ignored by decode like DASH's
	{ key = K.One, name = "GADGET 1", hint = "gadget bar" },
	{ key = K.Two, name = "GADGET 2", hint = "gadget bar" },
	{ key = K.Three, name = "GADGET 3", hint = "gadget bar" },
	{ key = K.Four, name = "GADGET 4", hint = "gadget bar" },
	{ key = K.Five, name = "GADGET 5", hint = "gadget bar" },
}
local isAction = {}
for _, a in ipairs(Keybinds.ACTIONS) do
	isAction[a.key] = true
end

Keybinds.FORBIDDEN = {}
for _, n in ipairs({ "W", "A", "S", "D", "Space", "Escape", "Tab", "Slash", "Backquote", "Return", "KeypadEnter", "Backspace",
	"Up", "Down", "Left", "Right", "I", "O", "Comma", "Period", "PageUp", "PageDown", "F9", "F10", "F11", "F12", "LeftSuper",
	"RightSuper", "LeftMeta", "RightMeta", "Unknown", "Menu", "Print", "BackSlash", "Home", "End" }) do -- \ Home End: Roblox's CoreGui owns them
	Keybinds.FORBIDDEN[K[n]] = true
end

local bind = {} -- [default KeyCode] = physical KeyCode (only actions that were moved)
local rev = {} -- [physical KeyCode] = default KeyCode
local changed = Instance.new("BindableEvent")
Keybinds.Changed = changed.Event

local function rebuild()
	rev = {}
	for d, p in pairs(bind) do
		rev[p] = d
	end
end

function Keybinds.physical(d)
	return bind[d] or d
end

function Keybinds.logical(k)
	if typeof(k) ~= "EnumItem" or k.EnumType ~= Enum.KeyCode then
		return k
	end
	local d = rev[k]
	if d then
		return d
	end
	if bind[k] then
		return K.Unknown -- this key's own action was moved to another key
	end
	return k
end

function Keybinds.isDown(d)
	return UserInputService:IsKeyDown(Keybinds.physical(d))
end

local SHORT = {
	LeftControl = "LCTRL", RightControl = "RCTRL", LeftShift = "SHIFT", RightShift = "RSHIFT", LeftAlt = "ALT", RightAlt = "RALT",
	CapsLock = "CAPS", Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8",
	Nine = "9", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'", BackSlash = "\\",
	KeypadZero = "NUM0", KeypadOne = "NUM1", KeypadTwo = "NUM2", KeypadThree = "NUM3", KeypadFour = "NUM4", KeypadFive = "NUM5",
	KeypadSix = "NUM6", KeypadSeven = "NUM7", KeypadEight = "NUM8", KeypadNine = "NUM9", Delete = "DEL", Insert = "INS",
}
function Keybinds.label(d)
	local p = Keybinds.physical(d)
	return SHORT[p.Name] or string.upper(p.Name)
end

function Keybinds.isAction(d)
	return isAction[d] == true
end

-- set without firing (load / set share it)
local function put(d, p)
	if p == nil or p == d then
		bind[d] = nil
	else
		bind[d] = p
	end
end

function Keybinds.set(d, p)
	if not isAction[d] then
		return false, "not a rebindable action"
	end
	if p ~= nil and (typeof(p) ~= "EnumItem" or p.EnumType ~= Enum.KeyCode or Keybinds.FORBIDDEN[p]) then
		return false, "that key can't be used"
	end
	p = p or d
	local old = Keybinds.physical(d)
	if old == p then
		return true
	end
	-- the action that has p now (moved onto it, or p's own default action still sitting on it) swaps to d's old key
	local owner = rev[p] or ((isAction[p] and not bind[p]) and p or nil)
	if owner and owner ~= d then
		put(owner, old)
	end
	put(d, p)
	rebuild()
	changed:Fire()
	return true
end

function Keybinds.reset()
	bind = {}
	rebuild()
	changed:Fire()
end

function Keybinds.serialize()
	local parts = {}
	for d, p in pairs(bind) do
		table.insert(parts, d.Name .. "=" .. p.Name)
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

local function decode(str)
	local out, used = {}, {}
	if type(str) ~= "string" then
		return out
	end
	for dn, pn in string.gmatch(str, "(%w+)=(%w+)") do
		local okD, d = pcall(function()
			return K[dn]
		end)
		local okP, p = pcall(function()
			return K[pn]
		end)
		if okD and okP and d and p and isAction[d] and not Keybinds.FORBIDDEN[p] and not used[p] and out[d] == nil then
			used[p] = true
			out[d] = p
		end
	end
	return out
end

function Keybinds.load(str)
	local nb = decode(str)
	-- a key moved onto another action's default while that action stayed put would leave two actions on one key:
	-- the moved one wins and the displaced default action goes to the moved one's old key
	bind = {}
	for d, p in pairs(nb) do
		bind[d] = p
	end
	for d, p in pairs(nb) do
		if isAction[p] and bind[p] == nil and p ~= d then
			bind[p] = d
		end
	end
	for d, p in pairs(bind) do
		if p == d then
			bind[d] = nil
		end
	end
	rebuild()
	changed:Fire()
end

-- the saved binds (Settings.keys) - at require time and whenever the server publishes the Settings attribute
local player = Players.LocalPlayer
local function fromSettings()
	local raw = player and player:GetAttribute("Settings")
	if type(raw) ~= "string" then
		return
	end
	local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(t) == "table" and type(t.keys) == "string" and t.keys ~= Keybinds.serialize() then
		Keybinds.load(t.keys)
	end
end
if player then
	pcall(fromSettings)
	player:GetAttributeChangedSignal("Settings"):Connect(function()
		pcall(fromSettings)
	end)
end

return Keybinds
