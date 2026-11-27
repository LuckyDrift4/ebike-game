-- Drives RideKit's real Physics module in the rigid-body world from sim.luau and
-- checks how the bike behaves: settling, power, brakes, cornering lean, grip on
-- different surfaces, wheelies, stoppies, jumps, hills, bumps, kerbs, walls,
-- and that it all holds at 30, 60 and 144 fps.

local fails = 0
local function check(name, ok, detail)
	print(string.format("%s %s: %s", if ok then "ok  " else "FAIL", name, detail))
	if not ok then
		fails += 1
	end
end
local deg = math.deg
-- run fn with some Config values changed (the suite checks the settings that ship, and uses
-- this to check the optional ones: crashes on, wheelie assist, air assist, Q stoppies)
local function with(over, fn)
	local old = {}
	for k, v in pairs(over) do
		old[k] = Config[k]
		Config[k] = v
	end
	local ok, a, b = pcall(fn)
	for k, v in pairs(old) do
		Config[k] = v
	end
	if not ok then
		error(a)
	end
	return a, b
end
local FWD = Vector3.new(0, 0, -1) -- the bike starts facing -Z

local function new(opts)
	Sim.reset()
	if opts.world then
		opts.world(Sim.world)
	end
	local model, body = Sim.bike(Config, opts)
	local phys = Physics.new(model, Config)
	return phys, body
end

-- simple rider: hold a speed with the throttle
local function cruise(target, out)
	return math.clamp((target - out.speed) * 0.4, 0, 1)
end

-- 1. drop and settle ------------------------------------------------------------------
for _, fps in ipairs({ 30, 60, 144 }) do
	local phys, body = new({ at = Vector3.new(0, 1.2209 * (1 + Config.ComHeight) + 0.3, 0) })
	local ys = {}
	Sim.run(phys, body, fps, 3, function() return { driver = true } end, function(_, out)
		table.insert(ys, body.CFrame.Y)
	end)
	local final = ys[#ys]
	local flips = 0
	for i = fps + 2, #ys do
		if (ys[i] - ys[i - 1]) * (ys[i - 1] - ys[i - 2]) < -1e-7 then
			flips += 1
		end
	end
	local lo, hi = math.huge, -math.huge
	for i = math.floor(#ys * 0.6), #ys do
		lo, hi = math.min(lo, ys[i]), math.max(hi, ys[i])
	end
	local sag = phys.out.comp[2]
	check(
		`settle @{fps}fps`,
		flips <= 2 and hi - lo < 0.01 and math.abs(sag - Config.SuspensionTravel / 2) < 0.06 and not phys.crashed,
		string.format("sag F %.3f R %.3f (half travel %.3f), jitter %.4f, wobbles after 1 s %d", phys.out.comp[1], sag, Config.SuspensionTravel / 2, hi - lo, flips)
	)
end

-- 2. full throttle -----------------------------------------------------------------------
do
	local phys, body = new({})
	local t50, frontUp, maxPitch = nil, 0, 0
	local out = Sim.run(phys, body, 60, 9, function() return { driver = true, throttle = 1 } end, function(t, o)
		if not t50 and o.speed >= 50 then
			t50 = t
		end
		if not o.contact[1] then
			frontUp += 1
		end
		maxPitch = math.max(maxPitch, deg(math.asin(body.CFrame.LookVector.Y)))
	end)
	check(
		"top speed",
		math.abs(out.speed - Config.MaxSpeed) < Config.MaxSpeed * 0.06 and frontUp == 0 and not out.crashed,
		string.format("%.1f studs/s after 9 s (MaxSpeed %d), 0-50 in %.2f s, squat %.2f deg, front lifted %d frames", out.speed, Config.MaxSpeed, t50 or -1, maxPitch, frontUp)
	)
end

-- 3. braking from 60 ------------------------------------------------------------------------
do
	local phys, body = new({ velocity = FWD * 60 })
	local start = body.CFrame.Position
	local stopT, dive, rearUp = nil, 0, 0
	Sim.run(phys, body, 60, 4, function() return { driver = true, brake = if stopT then 0 else 1 } end, function(t, o)
		if not stopT and o.speed < 0.5 then
			stopT = t
		end
		if not stopT then
			dive = math.max(dive, o.comp[1] - o.comp[2])
			if not o.contact[2] then
				rearUp += 1
			end
		end
	end)
	local dist = (body.CFrame.Position - start).Magnitude
	check(
		"brakes",
		stopT ~= nil and dist < 30 and dive > 0.1 and not phys.crashed,
		string.format("60 -> 0 in %.2f s over %.1f studs (%.0f studs/s^2), fork dive %.2f more than rear, rear lifted %d frames", stopT or -1, dist, 60 / (stopT or 1), dive, rearUp)
	)
end

-- 4. cornering: steady lean matches the turn (atan(v^2 / g r)) -----------------------------------
local function corner(v, fps, material, steer, secs)
	local phys, body = new({
		velocity = FWD * v,
		world = function(w)
			w.material = function() return material or "Asphalt" end
		end,
	})
	local leans, rates, maxSlip, start = {}, {}, 0, nil
	local t90 = nil
	Sim.run(phys, body, fps, secs or 4, function(t, o)
		return { driver = true, throttle = cruise(v, o), steer = if t > 0.5 then steer or 1 else 0 }
	end, function(t, o)
		if t > 2.5 then
			table.insert(leans, o.lean)
			table.insert(rates, -body.AssemblyAngularVelocity.Y)
		end
		maxSlip = math.max(maxSlip, o.slip[1], o.slip[2])
	end)
	local function avg(a)
		local s = 0
		for _, x in ipairs(a) do
			s += x
		end
		return s / math.max(#a, 1)
	end
	local lean, rate = avg(leans), avg(rates)
	local speed = phys.out.speed
	local predicted = math.atan(speed * rate / workspace.Gravity)
	return { lean = lean, rate = rate, radius = speed / math.max(math.abs(rate), 1e-6), predicted = predicted, slip = maxSlip, crashed = phys.crashed, reason = phys.crashReason, speed = speed }
end
for _, v in ipairs({ 20, 40, 65 }) do
	local r = corner(v, 60)
	check(
		`corner {v}`,
		not r.crashed and math.abs(deg(r.lean - r.predicted)) < 4 and deg(math.abs(r.lean)) < Config.MaxLean + 3 and r.slip < 0.05,
		string.format("speed %.1f, radius %.1f studs, lean %.1f deg (balance %.1f), tyre slip %.2f", r.speed, r.radius, deg(r.lean), deg(r.predicted), r.slip)
	)
end
do
	local a, b, c = corner(45, 30), corner(45, 60), corner(45, 144)
	check(
		"frame rate",
		math.abs(deg(a.lean - b.lean)) < 3 and math.abs(deg(c.lean - b.lean)) < 3 and not (a.crashed or b.crashed or c.crashed),
		string.format("lean at 45 studs/s: 30fps %.1f, 60fps %.1f, 144fps %.1f deg", deg(a.lean), deg(b.lean), deg(c.lean))
	)
end
do
	local r = corner(45, 60, "Ice")
	check("ice (crashes off: slides, stays on)", r.slip > 0.2 and not r.crashed and math.abs(deg(r.lean)) < 60, string.format("tyre slip %.2f, lean %.0f, crashed %s (%s)", r.slip, deg(r.lean), tostring(r.crashed), tostring(r.reason)))
	local rc = with({ Crashes = true }, function() return corner(45, 60, "Ice") end)
	check("ice (crashes on)", rc.crashed, string.format("tyre slip %.2f, crashed %s (%s)", rc.slip, tostring(rc.crashed), tostring(rc.reason)))
	local s = corner(30, 60, "Sand")
	check("sand", not s.crashed, string.format("lean %.1f deg, tyre slip %.2f, crashed %s", deg(s.lean), s.slip, tostring(s.crashed)))
end

-- 5. wheelies ------------------------------------------------------------------------------------
local function wheelie(assist, inputFn, secs)
	Config.WheelieAssist = assist
	local phys, body = new({ velocity = FWD * 22 })
	local up, n, angles, bal, maxAngle = 0, 0, 0, 0, 0
	local startUp = nil
	Sim.run(phys, body, 60, secs, inputFn, function(t, o)
		if t > 1.5 and t < secs - 2.5 then
			n += 1
			if not o.contact[1] then
				up += 1
				angles += o.wheelieAngle
				bal += o.balanceAngle
			end
		end
		if not startUp and not o.contact[1] then
			startUp = t
		end
		maxAngle = math.max(maxAngle, o.wheelieAngle)
	end)
	Config.WheelieAssist = true
	return {
		frac = up / math.max(n, 1),
		angle = angles / math.max(up, 1),
		balance = bal / math.max(up, 1),
		crashed = phys.crashed,
		reason = phys.crashReason,
		speed = phys.out.speed,
		maxAngle = maxAngle,
		startUp = startUp,
		front = phys.out.contact[1],
	}
end
do
	-- hold E + W for 6 s, then let go
	local r = wheelie(true, function(t) return { driver = true, throttle = if t < 7.5 then 1 else 0, leanBack = if t < 7.5 then 1 else 0 } end, 10)
	check(
		"wheelie (assist)",
		r.frac > 0.95 and not r.crashed and r.front and r.balance - r.angle < math.rad(8),
		string.format("front up %.0f%% of the time from %.2f s, %.1f deg (balance point %.1f), max %.1f, back down %s, speed %.1f", r.frac * 100, r.startUp or -1, deg(r.angle), deg(r.balance), deg(r.maxAngle), tostring(r.front), r.speed)
	)
	-- assist off, the player watches the balance bar: throttle until near the balance point
	local tap = wheelie(false, function(t, o)
		local on = o.wheelieAngle < o.balanceAngle - math.rad(7)
		return { driver = true, throttle = if on and t < 7.5 then 1 else 0, leanBack = if t < 7.5 then 1 else 0 }
	end, 10)
	check("wheelie (throttle by eye, no assist)", tap.frac > 0.8 and not tap.crashed, string.format("front up %.0f%%, %.1f deg (balance %.1f), crashed %s", tap.frac * 100, deg(tap.angle), deg(tap.balance), tostring(tap.crashed)))
	-- hold it pinned with no assist: loops over
	local loop = wheelie(false, function() return { driver = true, throttle = 1, leanBack = 1 } end, 6)
	check("loop out (no assist)", loop.crashed and loop.reason == "loop", string.format("crashed %s (%s), max angle %.1f deg", tostring(loop.crashed), tostring(loop.reason), deg(loop.maxAngle)))
	-- no assist, pinned, but the rear brake saves it when near the balance point
	local saved, braked = nil, false
	saved = wheelie(false, function(t, o)
		if o.balanceAngle - o.wheelieAngle < math.rad(2) and not o.contact[1] then
			braked = true
		end
		local b = if braked and o.wheelieAngle > o.balanceAngle - math.rad(15) then 1 else 0
		if o.wheelieAngle < o.balanceAngle - math.rad(15) then
			braked = false
		end
		return { driver = true, throttle = if b > 0 then 0 else 1, brake = b, leanBack = if t < 6 then 1 else 0 }
	end, 8)
	check("rear brake saves it", not saved.crashed and saved.frac > 0.7, string.format("front up %.0f%%, crashed %s", saved.frac * 100, tostring(saved.crashed)))
end

-- 6. stoppie ---------------------------------------------------------------------------------------
local function stoppie(v, input)
	local phys, body = new({ velocity = FWD * v })
	local rearUp, maxA = 0, 0
	Sim.run(phys, body, 60, 4, input, function(_, o)
		if not o.contact[2] then
			rearUp += 1
		end
		maxA = math.max(maxA, o.stoppieAngle)
	end)
	return phys, rearUp, maxA
end
do
	-- just S: the faster you were going, the bigger it is
	local brakeOnly = function(_, o) return { driver = true, brake = if o.speed > 0.5 then 1 else 0 } end
	local results = {}
	for _, v in ipairs({ 12, 30, 45, 65 }) do
		local p, up, a = stoppie(v, brakeOnly)
		results[v] = { up = up, a = deg(a), crashed = p.crashed, speed = p.out.speed, down = p.out.contact[1] and p.out.contact[2] }
	end
	local r12, r30, r45, r65 = results[12], results[30], results[45], results[65]
	check(
		"stoppie on S grows with speed",
		r12.up == 0 and r30.up > 0 and r65.a > r45.a and r45.a > r30.a and r65.a > 18 and not (r30.crashed or r45.crashed or r65.crashed) and r65.down,
		string.format("rear up / highest: from 12 %d fr %.0f deg, 30 %d fr %.0f deg, 45 %d fr %.0f deg, 65 %d fr %.0f deg", r12.up, r12.a, r30.up, r30.a, r45.up, r45.a, r65.up, r65.a)
	)
end
with({ StoppieOnBrake = false }, function()
	local phys, body = new({ velocity = FWD * 45 })
	local rearUp, maxA = 0, 0
	Sim.run(phys, body, 60, 4, function(_, o) return { driver = true, brake = if o.speed > 0.5 then 1 else 0, leanForward = 1 } end, function(_, o)
		if not o.contact[2] then
			rearUp += 1
		end
		maxA = math.max(maxA, o.stoppieAngle)
	end)
	check("stoppie (Q + brake)", rearUp > 20 and not phys.crashed and phys.out.contact[2] and math.abs(phys.out.speed) < 1, string.format("rear up %d frames, max %.1f deg, speed now %.1f, both wheels down %s", rearUp, deg(maxA), phys.out.speed, tostring(phys.out.contact[1] and phys.out.contact[2])))
	local p2, up2 = stoppie(45, function(_, o) return { driver = true, brake = if o.speed > 0.5 then 1 else 0 } end)
	check("no stoppie from S when it's off", up2 == 0, string.format("rear up %d frames", up2))
end)

-- 7. jump off a kicker ------------------------------------------------------------------------------
local function kicker(w)
	w.height = function(_, z)
		local d = -z - 20
		if d > 0 and d < 10 then
			return d * 5 / 10
		end
		return 0
	end
end
-- pitch of the bike when it touches down after the kicker
local function jump(input)
	local phys, body = new({ velocity = FWD * 55, world = kicker })
	local air, maxAir, maxComp, landed, landPitch, lastAirPitch = 0, 0, 0, false, nil, 0
	Sim.run(phys, body, 60, 4, function(t, o) return input(o) end, function(t, o)
		if o.airborne then
			air += 1 / 60
			maxAir = math.max(maxAir, air)
			lastAirPitch = deg(math.asin(body.CFrame.LookVector.Y))
		else
			if air > 0.15 then
				landed = true
				landPitch = landPitch or lastAirPitch
			end
			air = 0
		end
		if landed then
			maxComp = math.max(maxComp, o.comp[1], o.comp[2])
		end
	end)
	return { phys = phys, air = maxAir, landed = landed, comp = maxComp, pitch = landPitch or 0 }
end
with({ AirAssist = true }, function()
	local r = jump(function(o) return { driver = true, throttle = cruise(55, o) } end)
	local p = r.phys
	check("jump", r.air > 0.2 and r.landed and not p.crashed and p.out.contact[1] and p.out.contact[2], string.format("airtime %.2f s, lands at %.1f deg, landing compression %.2f (travel %.2f), crashed %s", r.air, r.pitch, r.comp, Config.SuspensionTravel, tostring(p.crashed)))
	-- hold E in the air: lands nose up (still rideable); Q: nose down
	local e = jump(function(o) return { driver = true, throttle = cruise(55, o), leanBack = if o.airborne then 1 else 0 } end)
	local q = jump(function(o) return { driver = true, throttle = cruise(55, o), leanForward = if o.airborne then 1 else 0 } end)
	check("air control (assisted)", e.pitch > r.pitch + 6 and q.pitch < r.pitch - 6 and not e.phys.crashed, string.format("lands at %.1f deg holding E, %.1f holding Q, %.1f with neither; crashed %s %s", e.pitch, q.pitch, r.pitch, tostring(e.phys.crashed), tostring(q.phys.crashed)))
end)
do
	-- all manual in the air (as shipped): still lands it; E lifts the nose
	local r = jump(function(o) return { driver = true, throttle = cruise(55, o) } end)
	local e = jump(function(o) return { driver = true, throttle = cruise(55, o), leanBack = if o.airborne then 1 else 0 } end)
	check("jump (manual air)", r.landed and not r.phys.crashed and e.pitch > r.pitch + 5, string.format("airtime %.2f s, lands at %.1f deg, %.1f holding E, crashed %s", r.air, r.pitch, e.pitch, tostring(r.phys.crashed)))
end

-- 8. hill climb ---------------------------------------------------------------------------------------
do
	local slope = math.tan(math.rad(14))
	local phys, body = new({
		velocity = FWD * 15,
		world = function(w)
			w.height = function(_, z) return math.max(-z - 10, 0) * slope end
		end,
	})
	local minSpeed = math.huge
	Sim.run(phys, body, 60, 5, function() return { driver = true, throttle = 1 } end, function(t, o)
		if t > 1.5 then
			minSpeed = math.min(minSpeed, o.speed)
		end
	end)
	check("hill climb 14 deg", minSpeed > 12 and not phys.crashed and phys.out.contact[1], string.format("slowest %.1f studs/s up the hill, now %.1f, height %.1f", minSpeed, phys.out.speed, body.CFrame.Y))
end

-- 9. bumps ------------------------------------------------------------------------------------------
do
	local phys, body = new({
		velocity = FWD * 40,
		world = function(w)
			w.height = function(_, z) return 0.15 * (1 - math.cos(z * 2 * math.pi / 7)) end
		end,
	})
	local onGround, n, maxPitch = 0, 0, 0
	Sim.run(phys, body, 60, 5, function(_, o) return { driver = true, throttle = cruise(40, o) } end, function(t, o)
		if t > 1 then
			n += 1
			if o.contact[1] and o.contact[2] then
				onGround += 1
			end
			maxPitch = math.max(maxPitch, math.abs(deg(math.asin(body.CFrame.LookVector.Y))))
		end
	end)
	check("bumps", onGround / n > 0.85 and not phys.crashed and maxPitch < 12, string.format("both wheels down %.0f%%, pitch within %.1f deg", onGround / n * 100, maxPitch))
end

-- 10. kerb -----------------------------------------------------------------------------------------
do
	local phys, body = new({
		velocity = FWD * 15,
		world = function(w)
			w.boxes = { { min = Vector3.new(-20, -1, -400), max = Vector3.new(20, 0.6, -12), material = "Concrete" } }
		end,
	})
	local y0 = body.CFrame.Y
	Sim.run(phys, body, 60, 3, function(_, o) return { driver = true, throttle = cruise(15, o) } end)
	check("kerb 0.6", body.CFrame.Y > y0 + 0.4 and not phys.crashed and phys.out.speed > 8, string.format("rode up %.2f studs, speed %.1f, crashed %s", body.CFrame.Y - y0, phys.out.speed, tostring(phys.crashed)))
end

-- 11. wall ------------------------------------------------------------------------------------------
do
	local phys, body = new({
		velocity = FWD * 50,
		world = function(w)
			w.boxes = { { min = Vector3.new(-20, 0, -60), max = Vector3.new(20, 20, -40) } }
		end,
	})
	Sim.run(phys, body, 60, 2, function(_, o) return { driver = true, throttle = 0 } end)
	check("wall (crashes off: stops)", not phys.crashed and math.abs(phys.out.speed) < 5 and body.CFrame.UpVector.Y > 0.5, string.format("crashed %s (%s), speed %.1f, upright %.2f", tostring(phys.crashed), tostring(phys.crashReason), phys.out.speed, body.CFrame.UpVector.Y))
	with({ Crashes = true }, function()
		local p2, b2 = new({ velocity = FWD * 50, world = function(w) w.boxes = { { min = Vector3.new(-20, 0, -60), max = Vector3.new(20, 20, -40) } } end })
		Sim.run(p2, b2, 60, 2, function() return { driver = true, throttle = 1 } end)
		check("wall (crashes on)", p2.crashed and p2.crashReason == "hit", string.format("crashed %s (%s)", tostring(p2.crashed), tostring(p2.crashReason)))
	end)
end

-- 12. rider gets off: rolls to a stop, stays up ---------------------------------------------------------
do
	local phys, body = new({ velocity = FWD * 15 })
	Sim.run(phys, body, 60, 4, function() return { driver = false, brake = 0.6 } end)
	check("coast to a stop", math.abs(phys.out.speed) < 0.5 and math.abs(deg(phys.out.lean)) < 3, string.format("speed %.2f, lean %.1f deg", phys.out.speed, deg(phys.out.lean)))
end

-- 13. harder stuff --------------------------------------------------------------------------------------
do
	-- brake hard in the middle of a fast corner: runs wide, may slide, should stay up
	local phys, body = new({ velocity = FWD * 45 })
	Sim.run(phys, body, 60, 3, function(t, o) return { driver = true, throttle = if t < 1.5 then cruise(45, o) else 0, brake = if t >= 1.5 and o.speed > 0.5 then 1 else 0, steer = if t > 0.3 then 1 else 0 } end)
	check("brake in a corner", not phys.crashed and math.abs(phys.out.speed) < 2, string.format("crashed %s (%s), speed %.1f", tostring(phys.crashed), tostring(phys.crashReason), phys.out.speed))
	-- full throttle round a corner on dirt: the rear steps out
	local p2, b2 = new({ velocity = FWD * 30, world = function(w) w.material = function() return "Ice" end end })
	local rearSlip = 0
	Sim.run(p2, b2, 60, 3, function(t) return { driver = true, throttle = 1, steer = if t > 0.3 then 1 else 0 } end, function(_, o)
		rearSlip = math.max(rearSlip, o.slip[2])
	end)
	check("power slide on ice", rearSlip > 0.05 and not p2.crashed, string.format("rear slip up to %.2f, crashed %s (%s)", rearSlip, tostring(p2.crashed), tostring(p2.crashReason)))
	-- steer in a wheelie
	local p3, b3 = new({ velocity = FWD * 22 })
	local yaw0 = b3.CFrame.LookVector
	Sim.run(p3, b3, 60, 5, function(t, o) return { driver = true, throttle = 1, leanBack = 1, steer = if t > 1.5 then 1 else 0 } end)
	local turned = deg(math.acos(math.clamp(yaw0:Dot(Vector3.new(b3.CFrame.LookVector.X, 0, b3.CFrame.LookVector.Z).Unit), -1, 1)))
	check("steer a wheelie", not p3.crashed and turned > 30 and not p3.out.contact[1], string.format("turned %.0f deg on the back wheel, still up %s, crashed %s (%s)", turned, tostring(not p3.out.contact[1]), tostring(p3.crashed), tostring(p3.crashReason)))
	-- wheelie at 30 fps
	local p4, b4 = new({ velocity = FWD * 22 })
	local up = 0
	Sim.run(p4, b4, 30, 6, function() return { driver = true, throttle = 1, leanBack = 1 } end, function(t, o)
		if t > 1.5 and not o.contact[1] then
			up += 1
		end
	end)
	check("wheelie @30fps", not p4.crashed and up > 120, string.format("front up %d of %d frames, crashed %s", up, 135, tostring(p4.crashed)))
	-- steep downhill on the brakes
	local p5, b5 = new({ velocity = FWD * 20, world = function(w) w.height = function(_, z) return -math.max(-z - 8, 0) * math.tan(math.rad(30)) end end })
	Sim.run(p5, b5, 60, 3, function(_, o) return { driver = true, brake = if o.speed > 15 then 1 else 0 } end)
	check("30 deg downhill", not p5.crashed and p5.out.contact[1] and p5.out.contact[2], string.format("crashed %s (%s), speed %.1f", tostring(p5.crashed), tostring(p5.crashReason), p5.out.speed))
	-- ride off a 5 stud drop
	local p6, b6 = new({ velocity = FWD * 30, world = function(w) w.height = function(_, z) return if z > -15 then 0 else -5 end end })
	Sim.run(p6, b6, 60, 3, function(_, o) return { driver = true, throttle = cruise(30, o) } end)
	check("5 stud drop", not p6.crashed and p6.out.contact[1] and p6.out.contact[2], string.format("crashed %s (%s), speed %.1f", tostring(p6.crashed), tostring(p6.crashReason), p6.out.speed))
	-- reverse
	local p7, b7 = new({})
	Sim.run(p7, b7, 60, 3, function() return { driver = true, brake = 1 } end)
	check("no reverse (S at a stop)", p7.out.speed > -0.5 and not p7.crashed, string.format("speed %.1f", p7.out.speed))
	with({ ReverseSpeed = 8 }, function()
		local p9, b9 = new({})
		Sim.run(p9, b9, 60, 3, function() return { driver = true, brake = 1 } end)
		check("reverse when it's on", p9.out.speed < -5.5, string.format("speed %.1f", p9.out.speed))
	end)
	-- a crashed bike with no rider falls over
	local p8, b8 = new({ velocity = FWD * 20 })
	p8:crash("test")
	Sim.run(p8, b8, 60, 4, function() return { driver = false } end)
	check("crashed bike falls over", math.abs(deg(p8.out.lean)) > 45, string.format("lean %.0f deg, speed %.1f", deg(p8.out.lean), p8.out.speed))
end

print(string.format("raycasts per frame: %.1f", Sim.rays / math.max(Sim.frames, 1)))
if fails > 0 then
	print(`FAIL {fails} physics checks`)
else
	print("all physics checks passed")
end
