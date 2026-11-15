--!nocheck
-- WRECKING BALL: a 12-stud iron ball on a rope under a gantry. WreckSwing (attribute Back = the way it is hauled
-- back) winches it up and lets go; the dummies and the crate pile stand in its path.
return function(K, model, cf, S)
	local PAL, C = K.PAL, K.C
	local M = Enum.Material
	local function L(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local GX, GY, RL = 16, 48, 34
	for _, sx in ipairs({ -1, 1 }) do
		K.part(model, "Tower", Vector3.new(3, GY, 3), L(sx * GX, GY / 2, 0), PAL.hazard, M.Metal)
		K.part(model, "TowerFoot", Vector3.new(9, 1, 9), L(sx * GX, 0.5, 0), PAL.concrete, M.Concrete)
		for _, sz in ipairs({ -1, 1 }) do
			K.part(model, "Brace", Vector3.new(1.4, 30, 1.4), L(sx * GX, 13, sz * 7) * CFrame.Angles(math.rad(sz * 28), 0, 0), PAL.steelDark, M.Metal)
		end
	end
	local beam = K.part(model, "Beam", Vector3.new(GX * 2 + 6, 2.6, 2.6), L(0, GY + 1.3, 0), PAL.hazard, M.Metal)
	K.part(model, "Winch", Vector3.new(4, 3, 4), L(0, GY + 4, 0), PAL.steelDark, M.Metal)
	local ball = K.ball(model, "WreckBall", 12, L(0, GY - RL - 6, 0).Position, C(44, 46, 52), M.Metal, { Anchored = false })
	ball.CustomPhysicalProperties = PhysicalProperties.new(10, 0.4, 0.05)
	local a0 = K.new("Attachment", { Name = "RopeTop", Position = Vector3.new(0, -1.3, 0) }, beam)
	local a1 = K.new("Attachment", { Name = "RopeBall", Position = Vector3.new(0, 6, 0) }, ball)
	K.new("RopeConstraint", { Attachment0 = a0, Attachment1 = a1, Length = RL, Visible = true, Thickness = 0.6, Color = BrickColor.new("Dark stone grey") }, ball)
	K.button(model, L(23, 0, 9), "WreckSwing", "Swing the ball", "Wrecking Ball", { Back = cf:VectorToWorldSpace(Vector3.new(0, 0, 1)) })
	K.danger(model, L(-22, 0, -12) * CFrame.Angles(0, math.rad(-24), 0))
	K.station(model, L(0, 0.3, -10), "stand", 8, 1)
	K.station(model, L(2.6, 0.3, -17), "stand", 8, 1)
	for i = -1, 1 do
		K.zone(model, "CrateSpawn", Vector3.new(1, 1, 1), L(i * 3.7, 0, -26), "CrateSpawn")
	end
	for _, x in ipairs({ -1.85, 1.85 }) do
		K.zone(model, "CrateSpawn", Vector3.new(1, 1, 1), L(x, 3.45, -26), "CrateSpawn")
	end
end
