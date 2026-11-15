--!nocheck
-- ServerScriptService.Sandbox.GunModels (2026-11-14): the gun slot's models, one per tier of Config.GUNS, built from
-- parts (the melee weapons' look). Main.buildWeapon welds them to the right hand; Main.shoot fires from "Muzzle".
--   GunModels.PARTS[id]                      -> the part list (below)
--   GunModels.build(id, base, parent, weldTo) -> builds the model's parts at base (the hand's grip frame) into
--                                               parent; weldTo = the hand they are welded to (nil = anchored, preview)
local C = Color3.fromRGB
-- (2026-11-14, owner: "give each gun the proper gun model, the smg model right now is a pistol") one recognisable
-- model per gun tier, built from parts like the melee weapons. Grip frame: the hand holds the pistol grip at the
-- origin, +Y up, the barrel points along -Z. Each entry:
--   { shape, sx, sy, sz, x, y, z, color, material, rx, ry, rz, name }
--   shape: "box" | "cyl" (a cylinder's LENGTH is sx - Roblox runs it along X - so ry = 90 lays it along the barrel)
--          | "ball" | "wedge"; rx / ry / rz in degrees (rx < 0 rakes a grip's foot backwards)
--   name "Muzzle": the barrel's tip - shots and tracers start there
local GM, BLK, STL, WD, OLV, BRS = C(46, 48, 54), C(26, 27, 31), C(168, 172, 182), C(122, 82, 50), C(80, 94, 62), C(196, 160, 82)
local MET, PLA, WOODM = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Wood
local GUN_PARTS = {
	pistol = { -- a polymer service pistol: slide, frame, raked grip, guard, sights
		{ "box", 0.26, 0.28, 1.42, 0, 0.47, -0.44, GM, MET },
		{ "box", 0.24, 0.16, 1.16, 0, 0.27, -0.34, BLK, PLA },
		{ "box", 0.24, 0.72, 0.36, 0, -0.06, 0.05, BLK, PLA, -12 },
		{ "box", 0.05, 0.04, 0.34, 0, 0.06, -0.33, BLK, PLA },
		{ "box", 0.05, 0.18, 0.05, 0, 0.14, -0.5, BLK, PLA },
		{ "box", 0.04, 0.13, 0.05, 0, 0.16, -0.27, BLK, PLA },
		{ "box", 0.16, 0.05, 0.06, 0, 0.635, -0.02, BLK, PLA },
		{ "box", 0.05, 0.05, 0.05, 0, 0.635, -1.08, BLK, PLA },
		{ "cyl", 0.06, 0.12, 0.12, 0, 0.5, -1.16, BLK, MET, 0, 90, 0, "Muzzle" },
	},
	revolver = { -- a long-barrel magnum: steel frame, fat cylinder, wooden grip, hammer
		{ "cyl", 1.36, 0.18, 0.18, 0, 0.52, -0.98, STL, MET, 0, 90, 0 },
		{ "box", 0.13, 0.13, 1.2, 0, 0.4, -0.94, STL, MET },
		{ "box", 0.22, 0.44, 0.6, 0, 0.42, -0.12, STL, MET },
		{ "cyl", 0.46, 0.5, 0.5, 0, 0.45, -0.2, C(132, 136, 146), MET, 0, 90, 0 },
		{ "box", 0.22, 0.74, 0.34, 0, -0.05, 0.14, WD, WOODM, -16 },
		{ "box", 0.08, 0.16, 0.12, 0, 0.7, 0.1, STL, MET, -25 },
		{ "box", 0.05, 0.04, 0.32, 0, 0.12, -0.12, STL, MET },
		{ "box", 0.04, 0.12, 0.05, 0, 0.18, -0.06, STL, MET },
		{ "box", 0.04, 0.09, 0.12, 0, 0.64, -1.58, STL, MET },
		{ "cyl", 0.04, 0.17, 0.17, 0, 0.52, -1.66, BLK, MET, 0, 90, 0, "Muzzle" },
	},
	smg = { -- a compact submachine gun: boxy receiver, curved mag ahead of the grip, front grip, folding wire stock
		{ "box", 0.3, 0.38, 1.7, 0, 0.47, -0.55, GM, MET },
		{ "box", 0.32, 0.32, 0.62, 0, 0.44, -1.62, BLK, PLA },
		{ "cyl", 0.5, 0.13, 0.13, 0, 0.5, -2.15, BLK, MET, 0, 90, 0 },
		{ "box", 0.2, 0.92, 0.26, 0, -0.18, -0.78, BLK, MET, 12 },
		{ "box", 0.24, 0.66, 0.34, 0, 0.0, 0.06, BLK, PLA, -12 },
		{ "box", 0.22, 0.5, 0.26, 0, 0.08, -1.55, BLK, PLA, 8 },
		{ "box", 0.05, 0.04, 0.36, 0, 0.13, -0.26, BLK, PLA },
		{ "box", 0.05, 0.06, 0.95, 0.13, 0.46, 0.78, GM, MET },
		{ "box", 0.05, 0.06, 0.95, -0.13, 0.46, 0.78, GM, MET },
		{ "box", 0.32, 0.42, 0.06, 0, 0.4, 1.25, BLK, PLA },
		{ "box", 0.12, 0.13, 0.1, 0, 0.72, -1.88, GM, MET },
		{ "box", 0.18, 0.1, 0.12, 0, 0.71, 0.2, GM, MET },
		{ "box", 0.07, 0.07, 0.3, 0.17, 0.58, -0.9, GM, MET },
		{ "cyl", 0.04, 0.14, 0.14, 0, 0.5, -2.42, BLK, MET, 0, 90, 0, "Muzzle" },
	},
	shotgun = { -- a pump action: long barrel over the tube magazine, wooden pump and stock
		{ "cyl", 3.0, 0.2, 0.2, 0, 0.56, -1.82, GM, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.18, 0.18, 0, 0.36, -1.5, GM, MET, 0, 90, 0 },
		{ "box", 0.32, 0.3, 0.86, 0, 0.37, -1.45, WD, WOODM },
		{ "box", 0.28, 0.44, 0.95, 0, 0.46, -0.12, GM, MET },
		{ "box", 0.24, 0.56, 0.34, 0, 0.06, 0.28, WD, WOODM, -24 },
		{ "box", 0.26, 0.44, 1.4, 0, 0.3, 1.12, WD, WOODM, 7 },
		{ "box", 0.27, 0.5, 0.08, 0, 0.21, 1.84, BLK, PLA, 7 },
		{ "box", 0.05, 0.04, 0.32, 0, 0.17, -0.02, GM, MET },
		{ "ball", 0.06, 0.06, 0.06, 0, 0.69, -3.24, BRS, MET },
		{ "cyl", 0.04, 0.22, 0.22, 0, 0.56, -3.32, BLK, MET, 0, 90, 0, "Muzzle" },
	},
	rifle = { -- a carbine: flat-top upper, handguard, angled mag, tube + stock, front sight post
		{ "box", 0.28, 0.3, 1.2, 0, 0.53, -0.36, GM, MET },
		{ "box", 0.26, 0.26, 0.9, 0, 0.29, -0.3, GM, MET },
		{ "box", 0.32, 0.32, 1.1, 0, 0.49, -1.5, BLK, PLA },
		{ "cyl", 0.9, 0.1, 0.1, 0, 0.5, -2.48, BLK, MET, 0, 90, 0 },
		{ "box", 0.06, 0.32, 0.08, 0, 0.73, -2.2, BLK, MET },
		{ "box", 0.1, 0.1, 1.9, 0, 0.72, -0.9, BLK, MET },
		{ "box", 0.18, 0.16, 0.14, 0, 0.82, 0.04, BLK, MET },
		{ "box", 0.2, 0.86, 0.32, 0, -0.08, -0.62, GM, MET, 14 },
		{ "box", 0.22, 0.62, 0.32, 0, 0.0, 0.12, BLK, PLA, -20 },
		{ "cyl", 0.62, 0.16, 0.16, 0, 0.5, 0.52, BLK, MET, 0, 90, 0 },
		{ "box", 0.24, 0.46, 0.72, 0, 0.4, 0.98, BLK, PLA },
		{ "box", 0.05, 0.04, 0.34, 0, 0.13, -0.2, BLK, MET },
		{ "cyl", 0.2, 0.17, 0.17, 0, 0.5, -3.02, GM, MET, 0, 90, 0, "Muzzle" },
	},
	sniper = { -- a bolt-action rifle: long barrel + brake, olive stock with cheek rest, big scope on rings
		{ "cyl", 2.6, 0.14, 0.14, 0, 0.52, -2.45, GM, MET, 0, 90, 0 },
		{ "box", 0.22, 0.2, 0.3, 0, 0.52, -3.86, GM, MET },
		{ "box", 0.26, 0.32, 1.3, 0, 0.52, -0.5, GM, MET },
		{ "box", 0.3, 0.36, 2.0, 0, 0.32, -0.75, OLV, PLA },
		{ "box", 0.28, 0.62, 1.0, 0, 0.24, 1.0, OLV, PLA },
		{ "box", 0.26, 0.12, 0.62, 0, 0.6, 0.92, OLV, PLA },
		{ "box", 0.22, 0.56, 0.3, 0, 0.0, 0.24, OLV, PLA, -20 },
		{ "box", 0.05, 0.04, 0.3, 0, 0.13, -0.08, GM, MET },
		{ "cyl", 1.6, 0.2, 0.2, 0, 0.94, -0.45, BLK, MET, 0, 90, 0 },
		{ "cyl", 0.36, 0.32, 0.32, 0, 0.94, -1.32, BLK, MET, 0, 90, 0 },
		{ "cyl", 0.26, 0.28, 0.28, 0, 0.94, 0.42, BLK, MET, 0, 90, 0 },
		{ "box", 0.1, 0.3, 0.1, 0, 0.74, -0.86, BLK, MET },
		{ "box", 0.1, 0.3, 0.1, 0, 0.74, -0.04, BLK, MET },
		{ "cyl", 0.3, 0.06, 0.06, 0.18, 0.56, 0.02, GM, MET },
		{ "ball", 0.12, 0.12, 0.12, 0.34, 0.56, 0.02, BLK, MET },
		{ "box", 0.04, 0.04, 0.04, 0, 0.52, -4.04, GM, MET, 0, 0, 0, "Muzzle" },
	},
	minigun = { -- a rotary gun: six barrels between two rings, motor drum, rear box, ammo can, carry handle
		{ "cyl", 1.0, 0.76, 0.76, 0, 0.7, -0.2, GM, MET, 0, 90, 0 },
		{ "box", 0.82, 0.82, 0.8, 0, 0.7, 0.56, BLK, MET },
		{ "cyl", 2.3, 0.13, 0.13, 0.22, 0.7, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.13, 0.13, 0.11, 0.89, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.13, 0.13, -0.11, 0.89, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.13, 0.13, -0.22, 0.7, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.13, 0.13, -0.11, 0.51, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 2.3, 0.13, 0.13, 0.11, 0.51, -1.95, STL, MET, 0, 90, 0 },
		{ "cyl", 0.12, 0.7, 0.7, 0, 0.7, -1.9, GM, MET, 0, 90, 0 },
		{ "cyl", 0.14, 0.72, 0.72, 0, 0.7, -3.0, GM, MET, 0, 90, 0, "Muzzle" },
		{ "box", 0.08, 0.08, 0.9, 0, 1.28, -0.2, BLK, MET },
		{ "box", 0.08, 0.22, 0.08, 0, 1.17, -0.6, BLK, MET },
		{ "box", 0.08, 0.22, 0.08, 0, 1.17, 0.2, BLK, MET },
		{ "box", 0.24, 0.6, 0.32, 0, 0.0, 0.3, BLK, PLA, -10 },
		{ "box", 0.5, 0.52, 0.72, 0.62, 0.5, 0.42, OLV, MET },
		{ "box", 0.3, 0.18, 0.5, 0.36, 0.62, -0.1, BLK, PLA },
	},
	launcher = { -- a shoulder-fired launcher: long tube, wooden heat guard, warhead with a nose cone, flared back
		{ "cyl", 4.0, 0.5, 0.5, 0, 0.78, -0.5, OLV, MET, 0, 90, 0 },
		{ "cyl", 1.2, 0.6, 0.6, 0, 0.78, -0.55, WD, WOODM, 0, 90, 0 },
		{ "cyl", 0.5, 0.74, 0.74, 0, 0.78, 1.55, GM, MET, 0, 90, 0 },
		{ "cyl", 0.7, 0.82, 0.82, 0, 0.78, -2.85, C(64, 76, 52), MET, 0, 90, 0 },
		{ "cyl", 0.5, 0.36, 0.36, 0, 0.78, -3.45, C(64, 76, 52), MET, 0, 90, 0 },
		{ "ball", 0.36, 0.36, 0.36, 0, 0.78, -3.7, C(64, 76, 52), MET, 0, 0, 0, "Muzzle" },
		{ "box", 0.22, 0.6, 0.3, 0, 0.1, 0.0, BLK, PLA, -10 },
		{ "box", 0.22, 0.56, 0.28, 0, 0.16, -1.15, BLK, PLA, 6 },
		{ "box", 0.1, 0.28, 0.24, -0.34, 1.1, -0.9, BLK, MET },
		{ "box", 0.05, 0.04, 0.3, 0, 0.18, -0.15, BLK, PLA },
	},
}

local GunModels = { PARTS = GUN_PARTS }
function GunModels.build(id, base, parent, weldTo)
	local spec = GUN_PARTS[id]
	if not spec then
		return false
	end
	for _, s in ipairs(spec) do
		local p
		if s[1] == "wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
			if s[1] == "cyl" then
				p.Shape = Enum.PartType.Cylinder
			elseif s[1] == "ball" then
				p.Shape = Enum.PartType.Ball
			end
		end
		p.Name = s[13] or "Part"
		p.Size = Vector3.new(s[2], s[3], s[4])
		p.Color, p.Material = s[8], s[9] or PLA
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.CFrame = base * CFrame.new(s[5], s[6], s[7]) * CFrame.Angles(math.rad(s[10] or 0), math.rad(s[11] or 0), math.rad(s[12] or 0))
		if weldTo then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = weldTo, p
			w.Parent = p
		else
			p.Anchored = true
		end
		p.Parent = parent
	end
	return true
end
return GunModels
