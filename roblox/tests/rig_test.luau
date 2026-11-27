-- Runs RideKit's real Rig logic on the part data of both bike models
-- (tests/bikes_data.luau):
--   * sorts every part into body / steer / fork lowers / wheels / swingarm like Rig.build
--   * picks the seat, pegs, grips and rider position
-- and prints a REF line (rider placement + bike points) that the Blender
-- animation (blender/anim/make_ride_anims.py) is built on.
-- Executed by run_tests.mjs.

local POSE_BIKE = "surron2" -- whose rider placement the Blender animation is built on

local function v3(v) return string.format("[%.4f,%.4f,%.4f]", v.X, v.Y, v.Z) end
local function cfj(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return string.format("{\"p\":[%.4f,%.4f,%.4f],\"r\":[%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f]}",
		x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

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
	local com = Rig.chassisCenter(front.cf.Position, rear.cf.Position, radR, fwd, up, Config)
	local chassisCF = CFrame.lookAt(com, com + fwd)
	local steerPivotCF = CFrame.fromMatrix(steerPos, right, steerAxis)
	local ctx = {
		frontPos = front.cf.Position, rearPos = rear.cf.Position, radF = radF, radR = radR,
		steerPos = steerPos, steerAxis = steerAxis, swingPos = swingPos, fwd = fwd, right = right, up = up,
	}
	-- classify
	local counts = { body = 0, steer = 0, frontSlide = 0, frontSpin = 0, swing = 0, rearSpin = 0 }
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
			parentIsFront = p.anc[1] ~= nil and p.anc[1][3] == front.ref,
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
	print(string.format("[%s] body %d, steer %d, fork lowers %d, front wheel %d, swingarm %d, rear wheel %d | bar %q | seat %q | pegs %s %s | rider forward %.2f",
		bikeName, counts.body, counts.steer, counts.frontSlide, counts.frontSpin, counts.swing, counts.rearSpin, bar.name,
		seat and seat.name or "(none)", tostring(pegL), tostring(pegR), rider.forward))

	-- expectations per model
	if bikeName == "surron2" then
		check(seat and string.find(seat.name, "attachments_Mesh.002", 1, true) ~= nil, "surron2 seat is the seat mesh")
		check(groupOf["handlebar_a.001_handlebar_renthal"] == "steer", "surron2 handlebar steers")
		check(groupOf["brakes.001_grey1.003"] == "steer", "surron2 brake levers steer")
		check(groupOf["headlight_l.001_hadnlebars.003"] == "steer", "surron2 headlight steers")
		check(groupOf["fork_front_Mesh.005_grey1.003"] == "frontSlide", "surron2 fork lower slides with the wheel")
		check(groupOf["1Circle.004_M_Fox40_1_0"] == "frontSlide", "surron2 Fox fork lower slides with the wheel")
		check(groupOf["fork_front_Mesh.003_black.005"] == "steer", "surron2 fork upper stays in the clamps")
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
		check(groupOf["forks_l"] == "frontSlide", "surron1 fork lower slides with the wheel")
		check(groupOf["forks_u.001"] == "steer", "surron1 fork upper stays in the clamps")
	end

	-- reference data for the Blender animation (blender/anim/make_ride_anims.py)
	if bikeName == POSE_BIKE then
		local seatCF0 = CFrame.lookAt(rider.seatPos, rider.seatPos + fwd)
		print(string.format("REF {\"bike\":\"%s\",\"hrp\":%s,\"chassis\":%s,\"steerPivot\":%s,\"gripL\":%s,\"gripR\":%s,"
			.. "\"pegL\":%s,\"pegR\":%s,\"frontAxle\":%s,\"rearAxle\":%s,\"radF\":%.4f,\"radR\":%.4f,"
			.. "\"seat\":{\"cf\":%s,\"size\":%s},\"bar\":{\"cf\":%s,\"size\":%s},\"swingPivot\":%s,\"maxSteer\":%.4f}",
			bikeName, cfj(seatCF0 * CFrame.new(rider.riderOffset)), cfj(chassisCF), cfj(steerPivotCF),
			v3(rider.gripL), v3(rider.gripR), v3(rider.pegL), v3(rider.pegR), v3(front.cf.Position), v3(rear.cf.Position),
			radF, radR, cfj(seat.cf), v3(seat.size), cfj(bar.cf), v3(bar.size), v3(swingPos), math.rad(Config.MaxSteerAngle)))
	end

end
print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
