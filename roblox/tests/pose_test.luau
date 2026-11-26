-- Runs RideKit's real Rig + Pose logic on the part data of both bike models
-- (tests/bikes_data.luau) with a standard R6 rig:
--   * sorts every part into body / steer / wheels / swingarm like Rig.build
--   * picks the seat, pegs, grips and rider position
--   * solves the riding pose for idle, cruise, right turn and wheelie
-- Prints a summary, CASE lines (body-part CFrames for rendering) and XFORM
-- lines (solved joint transforms for the Animation Editor pose).
-- Executed by run_pose_test.mjs, which prepends rbxmath + the modules + Bikes.

local POSE_BIKE = "surron2" -- whose solved pose is exported for the Animation Editor

local R6 = {
	Root = { C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	Neck = { C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	RS = { C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	LS = { C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	RH = { C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	LH = { C0 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), C1 = CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

local function v3(v) return string.format("[%.4f,%.4f,%.4f]", v.X, v.Y, v.Z) end
local function cfj(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return string.format("{\"p\":[%.4f,%.4f,%.4f],\"r\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f]}",
		x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end
local function partCF(m, parentCF) return parentCF * m.C0 * m.Transform * m.C1:Inverse() end

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

for _, bikeName in ipairs({ "surron1", "surron2" }) do
	-- parts -> CFrames
	local parts = {}
	for _, p in ipairs(Bikes[bikeName]) do
		local r = p.rot
		table.insert(parts, {
			ref = p.ref,
			name = p.name,
			cf = CFrame.new(p.pos[1], p.pos[2], p.pos[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]),
			size = Vector3.new(p.size[1], p.size[2], p.size[3]),
			anc = p.anc,
		})
	end
	local wheels, steerHinge, swingHinge = {}, nil, nil
	for _, p in ipairs(parts) do
		if p.name == Config.WheelPartName then table.insert(wheels, p) end
		if p.name == Config.SteerHingeName then steerHinge = p end
		if p.name == Config.SwingHingeName then swingHinge = p end
	end
	check(#wheels == 2, bikeName .. ": two Wheel parts")
	local front, rear = wheels[1], wheels[2]
	if (wheels[2].cf.Position - steerHinge.cf.Position).Magnitude < (wheels[1].cf.Position - steerHinge.cf.Position).Magnitude then
		front, rear = wheels[2], wheels[1]
	end
	-- same frame maths as Rig.build
	local up = Vector3.yAxis
	local flat = front.cf.Position - rear.cf.Position
	local fwd = Vector3.new(flat.X, 0, flat.Z).Unit
	local right = fwd:Cross(up)
	local radF = math.max(front.size.Y, front.size.Z) / 2
	local radR = math.max(rear.size.Y, rear.size.Z) / 2
	local wheelbase = Vector3.new(flat.X, 0, flat.Z).Magnitude
	local a = steerHinge.cf.Position - front.cf.Position
	a -= right * a:Dot(right)
	local steerAxis = a.Unit
	local steerPos = steerHinge.cf.Position
	local swingPos = swingHinge.cf.Position
	local center = (front.cf.Position + rear.cf.Position) / 2 + up * (radR * 0.7)
	local chassisCF = CFrame.lookAt(center, center + fwd)
	local steerPivotCF = CFrame.fromMatrix(steerPos, right, steerAxis)
	local ctx = {
		frontPos = front.cf.Position, rearPos = rear.cf.Position, radF = radF, radR = radR,
		steerPos = steerPos, steerAxis = steerAxis, swingPos = swingPos, fwd = fwd, right = right, up = up,
	}
	-- classify
	local counts = { body = 0, steer = 0, frontSpin = 0, swing = 0, rearSpin = 0 }
	local groupOf = {}
	local bar, barWidth, bodyParts = nil, 0, {}
	local function within(p, w)
		for _, x in ipairs(p.anc) do
			if x[3] == w.ref then return true end
		end
		return false
	end
	for _, p in ipairs(parts) do
		local ancestors = {}
		for _, x in ipairs(p.anc) do
			table.insert(ancestors, { name = x[1], class = x[2] })
		end
		local g = Rig.classify({
			name = p.name, pos = p.cf.Position, isFront = p == front, isRear = p == rear,
			inFront = within(p, front), inRear = within(p, rear), ancestors = ancestors,
		}, ctx)
		counts[g] += 1
		groupOf[p.name] = g
		if g == "steer" then
			local w = Rig.extentAlong(p.cf, p.size, right)
			if w > barWidth then bar, barWidth = p, w end
		elseif g == "body" then
			table.insert(bodyParts, { name = p.name, parentName = if p.anc[1] then p.anc[1][1] else "", cf = p.cf, size = p.size })
		end
	end
	local seat = Rig.pickSeat(bodyParts, Config.SeatPartKeyword, ctx)
	local pegL, pegR = Rig.pickPegs(bodyParts, right, Config.PegInset)
	local rider = Rig.riderSetup({
		seat = seat, bar = { cf = bar.cf, size = bar.size }, gripsGuess = {}, pegL = pegL, pegR = pegR,
		fwd = fwd, right = right, up = up, center = center, radR = radR, wheelbase = wheelbase,
	}, Config)
	print(string.format("[%s] body %d, steer %d, front wheel %d, swingarm %d, rear wheel %d | bar %q | seat %q | pegs %s %s | rider forward %.2f",
		bikeName, counts.body, counts.steer, counts.frontSpin, counts.swing, counts.rearSpin, bar.name,
		seat and seat.name or "(none)", tostring(pegL), tostring(pegR), rider.forward))

	-- expectations per model
	if bikeName == "surron2" then
		check(seat and string.find(seat.name, "attachments_Mesh.002", 1, true) ~= nil, "surron2 seat is the seat mesh")
		check(groupOf["handlebar_a.001_handlebar_renthal"] == "steer", "surron2 handlebar steers")
		check(groupOf["brakes.001_grey1.003"] == "steer", "surron2 brake levers steer")
		check(groupOf["headlight_l.001_hadnlebars.003"] == "steer", "surron2 headlight steers")
		check(groupOf["fork_front_Mesh.005_grey1.003"] == "steer", "surron2 fork steers")
		check(groupOf["wheel_lf.child.001_tyre001_d"] == "frontSpin", "surron2 front tyre spins")
		check(groupOf["bikedisc_f.001_frontbrake197_d"] == "frontSpin", "surron2 front disc spins")
		check(groupOf["wheel_lr.child.001_tyre001_d"] == "rearSpin", "surron2 rear tyre spins")
		check(groupOf["swingarm2.001_vehicle_generic_smallspecmap_[PRIMARY]"] == "swing", "surron2 swingarm moves with suspension")
		check(groupOf["mudguard.001_black.007"] == "swing", "surron2 hugger moves with swingarm")
		check(groupOf["Fender"] == "body", "surron2 rear fender stays on the body")
		check(groupOf["engine_Mesh.002_grey1.002"] == "body", "surron2 motor stays on the body")
	else
		check(seat and seat.name == "Guts Seat", "surron1 seat")
		check(groupOf["handlebars.019"] == "steer", "surron1 handlebar steers")
		check(groupOf["swingarm.007"] == "swing", "surron1 swingarm")
	end

	-- pose
	local j = { armLen = 2, legLen = 2 }
	for k, v in pairs(R6) do
		j[k] = { C0 = v.C0, C1 = v.C1, Transform = CFrame.new(), CurrentAngle = 1.57, DesiredAngle = 1.57, MaxVelocity = 0.15 }
	end
	local seatCF = CFrame.lookAt(rider.seatPos, rider.seatPos + fwd)
	local hrpCF = seatCF * CFrame.new(rider.riderOffset)
	local gripLl, gripRl = steerPivotCF:PointToObjectSpace(rider.gripL), steerPivotCF:PointToObjectSpace(rider.gripR)
	local cases = {
		{ "idle", 0, 0, 0, 0, 0 },
		{ "cruise", 1, 0, 40, 0, 0 },
		{ "turnR", 0.6, 1, 20, math.rad(25), 0 },
		{ "wheelie", 1, 0, 25, 0, math.rad(24) },
	}
	for _, cs in ipairs(cases) do
		local name, thr, steer, speed, steerAng, wheelie = table.unpack(cs)
		local sp = steerPivotCF * CFrame.fromAxisAngle(Vector3.yAxis, -steerAng)
		local pitch = CFrame.new(rear.cf.Position) * CFrame.fromAxisAngle(right, wheelie) * CFrame.new(-rear.cf.Position)
		local pivot = center - up * 1.4
		local roll = CFrame.new(pivot) * CFrame.fromAxisAngle(fwd, steer * math.rad(15) * math.min(speed / 30, 1)) * CFrame.new(-pivot)
		local bikeT = pitch * roll
		local hrp = bikeT * hrpCF
		local targets = {
			gripL = bikeT * (sp * gripLl), gripR = bikeT * (sp * gripRl),
			pegL = bikeT * rider.pegL, pegR = bikeT * rider.pegR,
		}
		j.mem = nil
		local out = Pose.solve(j, hrp, bikeT * chassisCF, targets, Config.Pose, {
			throttle = thr, steer = steer, speed = speed, maxSpeed = Config.MaxSpeed, wheelie = wheelie, bounce = 0,
		})
		local torso = partCF(j.Root, hrp)
		local head = partCF(j.Neck, torso)
		local eh = math.max((out.handL - targets.gripL).Magnitude, (out.handR - targets.gripR).Magnitude)
		local ef = math.max((out.footL - targets.pegL).Magnitude, (out.footR - targets.pegR).Magnitude)
		print(string.format("  %-8s worst hand->grip %.3f  worst foot->peg %.3f  head·forward %+.2f", name, eh, ef,
			head.LookVector:Dot((bikeT * chassisCF).LookVector)))
		check(eh < 0.25, `{bikeName} {name}: hands reach the grips`)
		check(head.LookVector:Dot((bikeT * chassisCF).LookVector) > 0.85, `{bikeName} {name}: head looks forward`)
		check(j.RS.CurrentAngle == 0 and j.LH.DesiredAngle == 0, "legacy motor angles cleared")
		local body = {
			HumanoidRootPart = hrp, Torso = torso, Head = head,
			["Right Arm"] = partCF(j.RS, torso), ["Left Arm"] = partCF(j.LS, torso),
			["Right Leg"] = partCF(j.RH, torso), ["Left Leg"] = partCF(j.LH, torso),
		}
		local items = {}
		for k, c in pairs(body) do
			table.insert(items, string.format("\"%s\":%s", k, cfj(c)))
		end
		print(string.format("CASE {\"bike\":\"%s\",\"name\":\"%s\",\"parts\":{%s},\"targets\":{\"gripL\":%s,\"gripR\":%s,\"pegL\":%s,\"pegR\":%s},"
			.. "\"hands\":{\"handL\":%s,\"handR\":%s,\"footL\":%s,\"footR\":%s},\"bikecf\":%s,\"steer\":%s,\"axles\":[%s,%s],\"radius\":%.3f}",
			bikeName, name, table.concat(items, ","), v3(targets.gripL), v3(targets.gripR), v3(targets.pegL), v3(targets.pegR),
			v3(out.handL), v3(out.handR), v3(out.footL), v3(out.footR), cfj(bikeT * chassisCF), cfj(bikeT * sp),
			v3(bikeT * front.cf.Position), v3(bikeT * rear.cf.Position), radF))
		if bikeName == POSE_BIKE then
			local xf = {}
			for _, k in ipairs({ "Root", "Neck", "RS", "LS", "RH", "LH" }) do
				table.insert(xf, string.format("\"%s\":%s", k, cfj(j[k].Transform)))
			end
			print(string.format("XFORM {\"name\":\"%s\",%s}", name, table.concat(xf, ",")))
		end
	end
end
print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
