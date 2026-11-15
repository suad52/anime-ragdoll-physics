--!nocheck
-- ReplicatedStorage.PerkShared.TrailStyle (2026-11-07, owner: cosmetics) - the Trail Pack perk's looks.
--   TrailStyle.get(id)          -> the style table for "Rainbow" / "Gold" / "BlackFlame" (nil for "" / unknown ids)
--   TrailStyle.apply(trail, id) -> true when it styled the trail. Restyles the Trail in place (colour sequence, light
--     emission, width scale, texture, and for Black Flame the transparency) and hangs ONE companion Trail named
--     "PerkTrailGlow" inside it on the same two attachments - the hot core / halo / glitter layer. The companion is
--     switched on and off in step with the main trail (and cleared when it re-enables), and is destroyed with it.
--   TrailStyle.apply(trail, "") is a no-op on a trail this module never styled. On one it did, it puts back every
--     property it wrote (unless the caller has overwritten that property since) and removes the companion, so a
--     REUSED trail can be switched back to its normal look - call it every cast with the caster's EquipTrail:
--         TrailStyle.apply(trail, casterPlayer:GetAttribute("EquipTrail") or "")
--   Usable on the client and the server; never errors (bad / destroyed trails are ignored).
-- Tuning lives in STYLES below. Width values are WidthScale (x the distance between the trail's two attachments).
local TrailStyle = {}

local C = Color3.fromRGB
local function cs(points)
	local kps = {}
	for i, p in ipairs(points) do
		kps[i] = ColorSequenceKeypoint.new(p[1], p[2])
	end
	return ColorSequence.new(kps)
end
local function ns(points)
	local kps = {}
	for i, p in ipairs(points) do
		kps[i] = NumberSequenceKeypoint.new(p[1], p[2])
	end
	return NumberSequence.new(kps)
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- trail time axis: 0 = the newest point (at the limb), 1 = the oldest point (the tail)
local STYLES = {
	Rainbow = {
		id = "Rainbow",
		name = "RAINBOW",
		accent = C(255, 120, 220),
		swatch = { C(255, 60, 60), C(255, 235, 60), C(70, 255, 120), C(60, 200, 255), C(200, 80, 255) },
		color = cs({ { 0, C(255, 70, 70) }, { 0.16, C(255, 155, 40) }, { 0.32, C(255, 240, 70) }, { 0.48, C(80, 255, 130) },
			{ 0.64, C(60, 210, 255) }, { 0.8, C(100, 110, 255) }, { 1, C(210, 80, 255) } }),
		lightEmission = 1,
		lightInfluence = 0,
		widthScale = ns({ { 0, 1.4 }, { 0.6, 0.95 }, { 1, 0.12 } }),
		texture = "",
		-- a white-hot core down the middle turns the band into a neon tube
		glow = {
			color = cs({ { 0, C(255, 255, 255) }, { 1, C(255, 230, 255) } }),
			lightEmission = 1,
			widthScale = ns({ { 0, 0.4 }, { 1, 0.03 } }),
			transparency = ns({ { 0, 0 }, { 0.45, 0.45 }, { 1, 1 } }),
			texture = "",
			brightness = 2,
		},
	},
	Gold = {
		id = "Gold",
		name = "GOLD",
		accent = C(255, 205, 60),
		swatch = { C(255, 250, 225), C(255, 215, 80), C(255, 170, 30), C(190, 95, 10) },
		color = cs({ { 0, C(255, 250, 225) }, { 0.18, C(255, 222, 95) }, { 0.55, C(255, 172, 30) }, { 1, C(190, 92, 10) } }),
		lightEmission = 1,
		lightInfluence = 0,
		widthScale = ns({ { 0, 1.55 }, { 0.5, 1 }, { 1, 0.08 } }),
		texture = "",
		-- glitter: four-point stars pinned in the world (Static) so they hang in the air behind the strike
		glow = {
			color = cs({ { 0, C(255, 248, 200) }, { 1, C(255, 196, 60) } }),
			lightEmission = 1,
			widthScale = ns({ { 0, 2.3 }, { 1, 0.7 } }),
			transparency = ns({ { 0, 0 }, { 0.6, 0.3 }, { 1, 1 } }),
			texture = SPARKLE,
			textureMode = Enum.TextureMode.Static,
			textureLength = 1.5,
			brightness = 2.5,
		},
	},
	BlackFlame = {
		id = "BlackFlame",
		name = "BLACK FLAME",
		accent = C(255, 40, 80),
		swatch = { C(8, 2, 10), C(40, 6, 30), C(255, 40, 70), C(150, 20, 160) },
		-- a solid black band (alpha-blended: additive black would be invisible) that burns out crimson at the tail
		color = cs({ { 0, C(6, 2, 8) }, { 0.45, C(18, 4, 16) }, { 0.8, C(60, 6, 22) }, { 1, C(110, 10, 30) } }),
		lightEmission = 0,
		lightInfluence = 0,
		widthScale = ns({ { 0, 1.8 }, { 0.35, 1.35 }, { 1, 0.25 } }),
		transparency = ns({ { 0, 0 }, { 0.55, 0.2 }, { 1, 1 } }),
		texture = "",
		-- a wider crimson-violet halo of wispy flame around the black
		glow = {
			color = cs({ { 0, C(255, 40, 70) }, { 0.5, C(190, 20, 120) }, { 1, C(90, 0, 140) } }),
			lightEmission = 1,
			widthScale = ns({ { 0, 2.7 }, { 0.5, 2 }, { 1, 0.5 } }),
			transparency = ns({ { 0, 0.35 }, { 0.5, 0.6 }, { 1, 1 } }),
			texture = SMOKE,
			textureMode = Enum.TextureMode.Static,
			textureLength = 2.6,
			brightness = 2,
		},
	},
}
TrailStyle.STYLES = STYLES
TrailStyle.IDS = { "Rainbow", "Gold", "BlackFlame" }

function TrailStyle.get(id)
	return type(id) == "string" and STYLES[id] or nil
end

-- [style field] -> Trail property (only the fields a style sets are written)
local FIELDS = {
	{ "color", "Color" },
	{ "lightEmission", "LightEmission" },
	{ "lightInfluence", "LightInfluence" },
	{ "widthScale", "WidthScale" },
	{ "transparency", "Transparency" },
	{ "texture", "Texture" },
	{ "textureMode", "TextureMode" },
	{ "textureLength", "TextureLength" },
}
-- copied from the main trail onto the companion (so it draws the same stroke)
local SHAPE = { "Attachment0", "Attachment1", "Lifetime", "MinLength", "MaxLength", "FaceCamera" }

local state = setmetatable({}, { __mode = "k" }) -- [trail] = { id, orig = {prop = value}, wrote = {prop = value}, glow, conn }

local function isTrail(t)
	return typeof(t) == "Instance" and t:IsA("Trail")
end

local function copyShape(from, to)
	for _, prop in ipairs(SHAPE) do
		pcall(function()
			to[prop] = from[prop]
		end)
	end
end

local function dropGlow(st)
	if st.conn then
		st.conn:Disconnect()
		st.conn = nil
	end
	if st.glow then
		pcall(function()
			st.glow:Destroy()
		end)
		st.glow = nil
	end
end

-- put back what this module wrote, unless the caller has changed that property since
local function revert(trail, st)
	for prop, wrote in pairs(st.wrote) do
		pcall(function()
			if trail[prop] == wrote then
				trail[prop] = st.orig[prop]
			end
		end)
	end
	dropGlow(st)
	state[trail] = nil
end

local function ensureGlow(trail, st, g)
	local glow = st.glow
	if not glow or glow.Parent ~= trail then
		dropGlow(st)
		glow = Instance.new("Trail")
		glow.Name = "PerkTrailGlow"
		glow.LightInfluence = 0
		copyShape(trail, glow)
		glow.Enabled = trail.Enabled
		glow.Parent = trail
		st.glow = glow
		st.conn = trail:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not glow.Parent then
				return
			end
			if trail.Enabled then
				copyShape(trail, glow)
				glow:Clear()
			end
			glow.Enabled = trail.Enabled
		end)
	else
		copyShape(trail, glow)
	end
	glow.Color = g.color or trail.Color
	glow.LightEmission = g.lightEmission or 1
	glow.WidthScale = g.widthScale or NumberSequence.new(0.5)
	glow.Transparency = g.transparency or trail.Transparency
	glow.Texture = g.texture or ""
	glow.TextureMode = g.textureMode or Enum.TextureMode.Stretch
	glow.TextureLength = g.textureLength or 1
	if g.brightness then
		pcall(function()
			glow.Brightness = g.brightness
		end)
	end
end

function TrailStyle.apply(trail, id)
	if not isTrail(trail) then
		return false
	end
	local style = TrailStyle.get(id)
	local st = state[trail]
	if not style then
		if st then
			revert(trail, st)
		end
		return false
	end
	local ok = pcall(function()
		if st and st.id ~= style.id then
			revert(trail, st) -- switching looks: start again from the trail's own look
			st = nil
		end
		if not st then
			st = { id = style.id, orig = {}, wrote = {} }
			state[trail] = st
		end
		for _, f in ipairs(FIELDS) do
			local value = style[f[1]]
			if value ~= nil then
				local prop = f[2]
				local cur = trail[prop]
				if st.wrote[prop] == nil or cur ~= st.wrote[prop] then
					st.orig[prop] = cur -- first write, or the caller set a new base value since the last apply
				end
				trail[prop] = value
				st.wrote[prop] = value
			end
		end
		if style.glow then
			ensureGlow(trail, st, style.glow)
		else
			dropGlow(st)
		end
	end)
	return ok
end

return TrailStyle
