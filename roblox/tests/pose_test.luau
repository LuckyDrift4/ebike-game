-- Runs RideKit's real Rig/Pose maths on surron1's measured parts with a
-- standard R6 rig, and prints every body part's CFrame as JSON lines.
-- (Executed by run_pose_test.mjs, which prepends rbxmath + the modules.)

local R6 = {
	Root = { C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	Neck = { C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	RS = { C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	LS = { C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	RH = { C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	LH = { C0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), C1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}
local j = { armLen = 2, legLen = 2 }
for k, v in pairs(R6) do
	j[k] = { C0 = v.C0, C1 = v.C1, Transform = CFrame.new(), CurrentAngle = 1.57, DesiredAngle = 1.57, MaxVelocity = 0.15 }
end

-- surron1.rbxm measurements (position, rotation rows, size)
local function part(px, py, pz, r, sx, sy, sz)
	return { cf = CFrame.new(px, py, pz, table.unpack(r)), size = Vector3.new(sx, sy, sz) }
end
local bar = part(-1.66, 4.871, -0.13, { 0.0236, 0.3646, -0.9309, -0.0010, 0.9311, 0.3646, 0.9997, -0.0077, 0.0224 }, 2.928, 0.36, 0.415)
local pegs = part(0.04, 2.049, -0.165, { 0, 0, -1, 0, 1, 0, 1, 0, 0 }, 1.533, 0.203, 0.191)
local seatRef = part(0.504, 4.089, -0.168, { 0, 0.0071, -1, 0, 1, 0.0071, 1, 0, 0 }, 0.678, 0.546, 1.723)
local frontPos, rearPos = Vector3.new(-3.093, 2.218, -0.123), Vector3.new(1.954, 2.164, -0.173)
local steerHinge, swingHinge = Vector3.new(-2.223, 3.826, -0.164), Vector3.new(0.11, 1.979, -0.179)

-- same frame maths as Rig.build
local up = Vector3.yAxis
local flat = frontPos - rearPos
local fwd = Vector3.new(flat.X, 0, flat.Z).Unit
local right = fwd:Cross(up)
local a = steerHinge - frontPos
a -= right * a:Dot(right)
local steerAxis = a.Unit
local center = (frontPos + rearPos) / 2 + up * (1.165 * 0.7)
local chassisCF = CFrame.lookAt(center, center + fwd)
local steerPivotCF = CFrame.fromMatrix(steerHinge, right, steerAxis)

local gripL, gripR = Rig.lateralEnds(bar.cf, bar.size, right, Config.GripInset, 0.6)
local pegL, pegR = Rig.lateralEnds(pegs.cf, pegs.size, right, Config.PegInset, 0.55)
local seatPos = Vector3.new(seatRef.cf.X, seatRef.cf.Y + 0.546 / 2 + 0.1, seatRef.cf.Z)
local riderY = Rig.riderHeight(seatPos.Y - 0.1, seatPos.Y, (pegL.Y + pegR.Y) / 2, Config)
local seatCF = CFrame.lookAt(seatPos, seatPos + fwd)
local hrpCF = seatCF * CFrame.new(Vector3.new(0, riderY, -Config.SeatForward))

local gripLl, gripRl = steerPivotCF:PointToObjectSpace(gripL), steerPivotCF:PointToObjectSpace(gripR)

local function v3(v) return string.format("[%.4f,%.4f,%.4f]", v.X, v.Y, v.Z) end
local function cfj(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return string.format("{\"p\":[%.4f,%.4f,%.4f],\"r\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f]}",
		x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
local function partCF(m, parentCF) return parentCF * m.C0 * m.Transform * m.C1:Inverse() end

local cases = {
	{ "idle", 0, 0, 0, 0, 0 },
	{ "cruise", 1, 0, 40, 0, 0 },
	{ "turnR", 0.6, 1, 20, math.rad(25), 0 },
	{ "wheelie", 1, 0, 25, 0, math.rad(24) },
}
for _, cs in ipairs(cases) do
	local name, thr, steer, speed, steerAng, wheelie = table.unpack(cs)
	-- steering turns the bars about the steering axis
	local sp = steerPivotCF * CFrame.fromAxisAngle(Vector3.yAxis, -steerAng)
	-- wheelie pitches the whole bike about the rear axle
	local pitch = CFrame.new(rearPos) * CFrame.fromAxisAngle(right, wheelie) * CFrame.new(-rearPos)
	local roll = CFrame.new(center - up * 1.4) * CFrame.fromAxisAngle(fwd, steer * math.rad(15) * math.min(speed / 30, 1)) * CFrame.new(-(center - up * 1.4))
	local bikeT = pitch * roll
	local hrp = bikeT * hrpCF
	local targets = {
		gripL = bikeT * (sp * gripLl), gripR = bikeT * (sp * gripRl),
		pegL = bikeT * pegL, pegR = bikeT * pegR,
	}
	local out = Pose.solve(j, hrp, bikeT * chassisCF, targets, Config.Pose, {
		throttle = thr, steer = steer, speed = speed, maxSpeed = Config.MaxSpeed, wheelie = wheelie, bounce = 0,
	})
	assert(j.RS.CurrentAngle == 0 and j.LH.DesiredAngle == 0, "legacy motor angles not cleared")
	local xf = {}
	for _, k in ipairs({ "Root", "Neck", "RS", "LS", "RH", "LH" }) do
		table.insert(xf, string.format("\"%s\":%s", k, cfj(j[k].Transform)))
	end
	print(string.format("XFORM {\"name\":\"%s\",%s}", name, table.concat(xf, ",")))
	local torso = partCF(j.Root, hrp)
	local parts = {
		HumanoidRootPart = hrp, Torso = torso, Head = partCF(j.Neck, torso),
		["Right Arm"] = partCF(j.RS, torso), ["Left Arm"] = partCF(j.LS, torso),
		["Right Leg"] = partCF(j.RH, torso), ["Left Leg"] = partCF(j.LH, torso),
	}
	local items = {}
	for k, c in pairs(parts) do
		table.insert(items, string.format("\"%s\":%s", k, cfj(c)))
	end
	print(string.format("CASE {\"name\":\"%s\",\"parts\":{%s},\"targets\":{\"gripL\":%s,\"gripR\":%s,\"pegL\":%s,\"pegR\":%s},"
		.. "\"hands\":{\"handL\":%s,\"handR\":%s,\"footL\":%s,\"footR\":%s},\"bike\":%s,\"steer\":%s}",
		name, table.concat(items, ","), v3(targets.gripL), v3(targets.gripR), v3(targets.pegL), v3(targets.pegR),
		v3(out.handL), v3(out.handR), v3(out.footL), v3(out.footR), cfj(bikeT * chassisCF), cfj(bikeT * sp)))
	print(string.format("%-8s hand->grip L %.3f R %.3f | foot->peg L %.3f R %.3f | head look %s | torso up %s",
		name, (out.handL - targets.gripL).Magnitude, (out.handR - targets.gripR).Magnitude,
		(out.footL - targets.pegL).Magnitude, (out.footR - targets.pegR).Magnitude,
		tostring(parts.Head.LookVector), tostring(torso.UpVector)))
end
print("seat top", seatPos.Y - 0.1, "rider HRP", tostring(hrpCF.Position), "grips", tostring(gripL), tostring(gripR), "pegs", tostring(pegL), tostring(pegR))
