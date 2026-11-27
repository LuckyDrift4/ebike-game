----------------------------------------------------------------------------------------------------------------------------------------------------------------

local Config = (function()
	-- RideKit settings. Tweak these in Studio while play-testing.
	-- Distances are in studs, speeds in studs/second (shown as km/h), angles in degrees.
	local Config = {
		-- names of the parts RideKit looks for inside the bike model
		WheelPartName = "Wheel", -- the two invisible cylinder wheels
		SteerHingeName = "TripleTreeHinge", -- steering head (fork pivots around this)
		SwingHingeName = "RearSwingArmHinge", -- swingarm pivot
		SeatPartKeyword = "seat", -- part whose name contains this is the seat (else the highest seat-shaped part)
		FallbackRake = 26, -- steering-axis angle if there is no TripleTreeHinge

		-- motor (electric: full pull from a standstill, then constant power)
		MaxSpeed = 75,
		Acceleration = 55, -- pull at low speed (studs/s²; gravity is 196)
		PowerBand = 0.4, -- full pull up to this fraction of MaxSpeed
		ReverseSpeed = 8, -- hold S when stopped
		CoastDecel = 4, -- motor braking with the throttle closed
		RollingDrag = 1.5,

		-- brakes (S brakes both wheels; how hard, before the tyres give up)
		FrontBrake = 95,
		RearBrake = 55,

		-- tyres
		Grip = 1.0, -- times the surface grip: asphalt 1.05, concrete 1, grass 0.7, dirt 0.65, sand 0.5, mud 0.4, ice 0.15
		SlideGrip = 0.8, -- grip left once a tyre slides (lower = longer drifts)
		LateralStiffness = 0.9, -- how firmly a gripping tyre stops sideways sliding (0..1)
		TyreProfile = 0.35, -- radius of the tyre's round cross-section (a leaned bike rolls on its shoulder)

		-- steering and lean (the rider holds the lean that balances the turn)
		MaxSteerAngle = 17, -- bar angle at walking pace; less at speed so the lean never passes MaxLean
		SteerSpeed = 1.8, -- how fast the bars turn (rad/s)
		MaxLean = 38,
		RollStiffness = 7, -- how firmly the rider pulls the bike to the balancing lean
		RollRate = 3.5, -- fastest lean change (rad/s)
		RollTorque = 3, -- how much the rider can do to hold it up (x weight x studs)

		-- suspension (a spring and damper per wheel)
		SuspensionTravel = 0.8,
		SpringRate = 1.0, -- 1 = sits at half travel; higher = stiffer
		Damping = 0.55, -- compression damping (1 = critical); lower = softer over bumps
		ReboundDamping = 0.9, -- extension damping; higher = no kick back off jump lips
		MaxSuspensionSpeed = 40,

		-- body: the bike and rider's weight sit in the invisible RideKit_Chassis box
		ChassisDensity = 1.6, -- bike + rider: about twice a walking avatar
		ComHeight = 2.0, -- centre of mass above the axles, in wheel radii (bike + rider: about hip height)
		ComBack = 0.04, -- centre of mass toward the rear wheel, fraction of the wheelbase

		-- wheelie: hold E (gamepad X) with the throttle on. Throttle raises the front, off lowers
		-- it, S is the rear brake. The balance bar shows how close you are to the balance point.
		WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
		WheelieMinSpeed = 5,
		WheelieAssist = true, -- true: covers the rear brake so you never go past the balance point
		-- false: hold the throttle too long and you loop it
		WheelieSweetSpot = 4, -- degrees below the balance point the assist holds you at
		WheelieAimUp = 1.1, -- how fast the front rises with the throttle on (rad/s)
		WheelieAimDown = 0.55, -- how fast it comes down with the throttle off
		WheelieLift = 2.6, -- how hard the motor lifts the front
		RiderShift = 0.45, -- how far the rider moves their weight back or forward (studs)
		WheelieControl = 7, -- how tightly the rider holds the angle
		WheelieSteer = 0.5, -- steering in a wheelie, times normal (you lean it round)
		LoopOutAngle = 22, -- degrees past the balance point before it's gone

		-- stoppie: hold Q (gamepad Y) and brake. Q on its own: stand up / weight forward
		StoppieKeys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonY },
		StoppieMinSpeed = 14,
		StoppieAngle = 20, -- highest the rear wheel goes (degrees)
		StoppieAimUp = 1.0, -- how fast the rear rises while braking (rad/s)
		StoppieAimDown = 1.4, -- how fast it comes down when you let go
		StoppieLift = 2.0, -- the rider's shove that gets the rear up

		-- in the air the rider lines the bike up with the way it's flying; E / Q lift / drop the
		-- nose, throttle / brake spin the rear wheel up / stop it, A / D turn it a little
		AirAssist = true, -- false: no lining up (nor holding it steady off lips), E / Q rotate it directly
		AirControl = 6, -- how quickly the rider lines it up (rad/s)
		AirLean = 0.6, -- how far E / Q tip it from the flight path (rad)
		AirPitch = 14, -- strongest rotation the rider can make (rad/s²)
		AirThrottle = 2.5,
		AirYaw = 1.5,

		-- crashes: you come off and the bike falls over
		Crashes = true,
		CrashLean = 72, -- lean that can't be saved
		CrashImpact = 30, -- speed lost at once (a wall) that throws you off
		DismountCrashSpeed = 25, -- jump off faster than this and the bike falls

		-- rider placement on the seat (R6)
		SeatHeight = "auto", -- "auto" = as low as needed for the feet to reach the pegs, or a number
		-- (HumanoidRootPart height above the seat top, e.g. 1.0)
		SeatForward = "auto", -- "auto" = slide forward until the hands reach the bars, or a number
		GripInset = 0.25, -- hands sit this far in from the ends of the handlebar
		PegInset = 0.15, -- feet sit this far in from the ends of the foot-peg bar

		-- rider animation (keyframed in Blender: blender/anim/ride_anims.blend)
		AnimBlendSpeed = 8, -- how fast the rider moves between the clips
		Pose = { TorsoLean = 0.35 }, -- forward lean the seat position is fitted for (matches the Blender clips)

		-- on-screen speed, wheelie timer and balance bar for the rider
		ShowHud = true,
	}

	return Config
end)()
local Rig = (function()
	-- RideKit.Rig (server): turns a static, anchored bike model into a rideable rig.
	--
	-- Every BasePart of the model is sorted into one of five groups and welded to
	-- that group's root:
	--   body        -> RideKit_Chassis   (invisible physics box, carries everything)
	--   steer       -> RideKit_SteerPivot (forks, bars, levers; turns about the steering axis)
	--   frontSlide  -> RideKit_FrontSlider (fork lowers / axle bits: steer + slide with the fork, no spin)
	--   frontSpin   -> RideKit_FrontHub   (front wheel mesh; spins, steers, compresses)
	--   swing       -> RideKit_SwingPivot (swingarm, chain, mudguard; pivots with the suspension)
	--   rearSpin    -> RideKit_RearHub    (rear wheel mesh; spins)
	-- The roots are joined with Motor6Ds whose Transform the client animates.
	--
	-- Works with plain bike models (surron1: parts named fork/handlebar/swingarm)
	-- and chassis-kit style models (surron2: Misc > Wheel = handlebar assembly,
	-- FrontSection/RearSection > Wheel with WheelFixed / Parts, Misc > Step = pegs).
	-- The decision logic is in pure functions (classify, pickSeat, pickPegs,
	-- riderSetup) so it can be tested outside Roblox (see roblox/tests).

	local Rig = {}

	local STEER_WORDS = { "fork", "handlebar", "hadnlebar", "lever", "grip", "triple", "clamp", "throttle" }
	local STEER_MODELS = { forks = true, bars = true, brakes = true, handlebars = true, steering = true }
	local SWING_WORDS = { "swingarm", "swing arm", "chain", "mudguard", "hugger" }

	local function hasWord(name: string, words: { string }): boolean
		local n = string.lower(name)
		for _, w in ipairs(words) do
			if string.find(n, w, 1, true) then
				return true
			end
		end
		return false
	end
	Rig.hasWord = hasWord

	-- extent of a box along a world direction
	local function extentAlong(cf: CFrame, size: Vector3, dir: Vector3): number
		return math.abs(cf.RightVector:Dot(dir)) * size.X
			+ math.abs(cf.UpVector:Dot(dir)) * size.Y
			+ math.abs(cf.LookVector:Dot(dir)) * size.Z
	end
	Rig.extentAlong = extentAlong

	-- the two ends of a bar-shaped part along `right` (left end, right end), pulled in by `inset`
	function Rig.lateralEnds(cf: CFrame, size: Vector3, right: Vector3, inset: number, minHalf: number?): (Vector3, Vector3)
		local half = math.max(extentAlong(cf, size, right) / 2 - inset, minHalf or 0)
		return cf.Position - right * half, cf.Position + right * half
	end

	-- perpendicular distance from point p to the line through a with unit direction d,
	-- and the coordinate of p along that line
	local function lineDistance(p: Vector3, a: Vector3, d: Vector3): (number, number)
		local v = p - a
		local along = v:Dot(d)
		return (v - d * along).Magnitude, along
	end

	--[[ Which group a part belongs to.
	  info: { name, pos, isFront, isRear, inFront, inRear, parentIsFront, ancestors = { {name=, class=}, ... } }
	  ctx : { frontPos, rearPos, radF, radR, steerPos, steerAxis, swingPos, fwd }
	]]
	function Rig.classify(info, ctx): string
		if info.isFront then
			return "frontSpin"
		elseif info.isRear then
			return "rearSpin"
		end
		local pos = info.pos
		if (pos - ctx.frontPos).Magnitude < ctx.radF * 0.3 then
			return "frontSpin" -- tyre / rim / disc: centred on the axle
		elseif (pos - ctx.rearPos).Magnitude < ctx.radR * 0.3 then
			return "rearSpin"
		end
		if info.inFront then
			-- parts hung straight off the front wheel, or in its WheelFixed / SuspensionFixed
			-- model, are fork lowers: they slide with the wheel when the fork compresses
			if info.parentIsFront then
				return "frontSlide"
			end
			for _, a in ipairs(info.ancestors) do
				local n = string.lower(a.name)
				if n == "wheelfixed" or n == "suspensionfixed" then
					return "frontSlide"
				end
			end
			return "steer"
		end
		if hasWord(info.name, STEER_WORDS) then
			return "steer"
		end
		for _, a in ipairs(info.ancestors) do
			local n = string.lower(a.name)
			-- chassis kits keep the handlebar assembly in a Model named "Wheel" (the steering wheel)
			if STEER_MODELS[n] or (n == "wheel" and a.class == "Model") then
				return "steer"
			end
		end
		if info.inRear or (hasWord(info.name, SWING_WORDS) and (pos - ctx.swingPos):Dot(ctx.fwd) < 0.2) then
			return "swing" -- only parts behind the swingarm pivot
		end
		local d, along = lineDistance(pos, ctx.steerPos, ctx.steerAxis)
		if d < 0.4 and along > -0.4 then
			return "steer" -- small bits on the steering column (clamp bolts, stem)
		end
		return "body"
	end

	--[[ The seat: a part with "seat" in its name, else the highest seat-shaped part
	  (long front-to-back, narrow, thin) between the swingarm pivot and the rear axle.
	  parts: { {name, cf, size}, ... }; returns the chosen entry or nil ]]
	function Rig.pickSeat(parts, keyword: string, ctx)
		for _, p in ipairs(parts) do
			if string.find(string.lower(p.name), keyword, 1, true) then
				return p
			end
		end
		local best, bestTop = nil, -math.huge
		local x0 = (ctx.swingPos - ctx.rearPos):Dot(ctx.fwd) + 0.6 -- a bit ahead of the pivot
		for _, p in ipairs(parts) do
			local x = (p.cf.Position - ctx.rearPos):Dot(ctx.fwd)
			local long = extentAlong(p.cf, p.size, ctx.fwd)
			local wide = extentAlong(p.cf, p.size, ctx.right)
			local tall = extentAlong(p.cf, p.size, ctx.up)
			-- seat-shaped: long front-to-back, not wider than long, thin (not a frame or body shell)
			if x > 0.1 and x < x0 and long > 0.8 and long > wide and tall < 0.9 then
				local top = p.cf.Position:Dot(ctx.up) + extentAlong(p.cf, p.size, ctx.up) / 2
				if top > bestTop then
					best, bestTop = p, top
				end
			end
		end
		return best
	end

	--[[ Foot pegs: parts named *peg* / *step* (or inside a model with that name).
	  One wide part -> its two ends; several parts -> the outermost left and right.
	  parts: { {name, parentName, cf, size}, ... }; returns pegL, pegR (or nil) ]]
	function Rig.pickPegs(parts, right: Vector3, inset: number)
		local cands = {}
		for _, p in ipairs(parts) do
			local n, pn = string.lower(p.name), string.lower(p.parentName or "")
			if string.find(n, "peg", 1, true) or string.find(n, "step", 1, true)
				or string.find(pn, "peg", 1, true) or string.find(pn, "step", 1, true) then
				table.insert(cands, p)
			end
		end
		if #cands == 0 then
			return nil, nil
		elseif #cands == 1 then
			return Rig.lateralEnds(cands[1].cf, cands[1].size, right, inset, 0.55)
		end
		local lo, hi = cands[1], cands[1]
		for _, p in ipairs(cands) do
			if p.cf.Position:Dot(right) < lo.cf.Position:Dot(right) then
				lo = p
			end
			if p.cf.Position:Dot(right) > hi.cf.Position:Dot(right) then
				hi = p
			end
		end
		return lo.cf.Position, hi.cf.Position
	end

	--[[ Where the rider goes (R6).
	  d: { seat = {cf,size}|nil, bar = {cf,size}|nil, gripsGuess, pegL, pegR, fwd, right, up, center, radR, wheelbase }
	  returns { gripL, gripR, pegL, pegR, seatPos, riderOffset } where riderOffset is the
	  HumanoidRootPart position in the seat's frame (seat CFrame = lookAt(seatPos, seatPos + fwd)) ]]
	function Rig.riderSetup(d, cfg)
		local fwd, right, up = d.fwd, d.right, d.up
		-- grips
		local gripL, gripR
		if d.bar then
			gripL, gripR = Rig.lateralEnds(d.bar.cf, d.bar.size, right, cfg.GripInset, 0.6)
		else
			gripL, gripR = d.gripsGuess[1], d.gripsGuess[2]
		end
		-- seat
		local seatPos, seatTop, seatHalfLen
		if d.seat then
			local c = d.seat.cf.Position
			local halfH = extentAlong(d.seat.cf, d.seat.size, up) / 2
			seatTop = c:Dot(up) + halfH
			seatPos = c + up * (halfH + 0.1)
			seatHalfLen = extentAlong(d.seat.cf, d.seat.size, fwd) / 2
		else
			seatPos = d.center + up * (d.radR * 1.6) - fwd * d.wheelbase * 0.1
			seatTop = seatPos:Dot(up) - 0.1
			seatHalfLen = 0.8
		end
		-- R6 rider: HumanoidRootPart = torso centre, shoulders 0.5 above it (arms reach 1.5 to the
		-- hands, which sit 0.5 outboard), hips 1 below it (legs reach 2 to the feet, 0.5 inboard).
		-- Search the seat position (forward along the seat, hip height) where a natural forward
		-- lean puts the hands on the grips and the feet near the pegs.
		local lean = cfg.Pose.TorsoLean
		local sL, cL = math.sin(lean), math.cos(lean)
		local aimR, aimL = gripR - right * 0.5, gripL + right * 0.5
		local footR, footL = d.pegR + right * 0.5, d.pegL - right * 0.5
		local fixedF = type(cfg.SeatForward) == "number"
		local fixedH = type(cfg.SeatHeight) == "number"
		local best, bestF, bestHip = math.huge, 0, seatTop
		local fMax = if fixedF then cfg.SeatForward else seatHalfLen + 0.3
		local f0 = if fixedF then cfg.SeatForward else 0
		local h0 = if fixedH then seatTop + cfg.SeatHeight - 1 else seatTop - 0.3
		local h1 = if fixedH then h0 else seatTop + 0.15
		for f = f0, fMax + 1e-6, 0.05 do
			for hipY = h0, h1 + 1e-6, 0.05 do
				local base = seatPos + fwd * f
				local hrp = base + up * (hipY + 1 - seatPos:Dot(up))
				local sh = hrp + up * (0.5 * cL) + fwd * (0.5 * sL)
				local hip = hrp - up * cL - fwd * sL
				local eR = (aimR - (sh + right)).Magnitude - 1.5
				local eL = (aimL - (sh - right)).Magnitude - 1.5
				local lR = (footR - (hip + right)).Magnitude - 2
				local lL = (footL - (hip - right)).Magnitude - 2
				local function leg(e)
					return if e > 0 then e * e else 0.3 * e * e -- dangling short is worse than overshoot
				end
				local cost = 4 * (eR * eR + eL * eL) + leg(lR) + leg(lL)
					+ 2 * math.max(0, f - seatHalfLen) ^ 2 -- prefer sitting on the seat
					+ 2 * math.max(0, seatTop - 0.1 - hipY) ^ 2 -- and not sunk into it
				if cost < best then
					best, bestF, bestHip = cost, f, hipY
				end
			end
		end
		local forward = bestF
		local riderUp = bestHip + 1 - seatPos:Dot(up)
		return {
			gripL = gripL,
			gripR = gripR,
			pegL = d.pegL,
			pegR = d.pegR,
			seatPos = seatPos,
			riderOffset = Vector3.new(0, riderUp, -forward),
			forward = forward,
		}
	end

	-- where RideKit_Chassis goes (the bike + rider's centre of mass) and its size
	function Rig.chassisCenter(frontPos: Vector3, rearPos: Vector3, radR: number, fwd: Vector3, up: Vector3, cfg): Vector3
		local flat = frontPos - rearPos
		local wheelbase = Vector3.new(flat.X, 0, flat.Z).Magnitude
		return (frontPos + rearPos) / 2 + up * (radR * cfg.ComHeight) - fwd * (wheelbase * cfg.ComBack)
	end

	function Rig.chassisSize(wheelbase: number): Vector3
		return Vector3.new(1.2, 1.6, wheelbase * 1.15)
	end

	-- -------------------------------------------------------------------------------
	-- Instance helpers (Roblox only)
	-- -------------------------------------------------------------------------------
	local function helper(name: string, cf: CFrame, parent: Instance): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = cf
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.Parent = parent
		return p
	end

	local function motor(name: string, part0: BasePart, part1: BasePart): Motor6D
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
		m.C1 = CFrame.new()
		m.Parent = part0
		return m
	end

	local function weld(root: BasePart, part: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Name = "RideKit_Weld"
		w.Part0 = root
		w.Part1 = part
		w.Parent = part
	end

	local function ancestorsOf(part: Instance, root: Instance)
		local out = {}
		local p = part.Parent
		while p and p ~= root do
			table.insert(out, { name = p.Name, class = p.ClassName })
			p = p.Parent
		end
		return out
	end

	function Rig.build(bike: Model, cfg)
		if bike:GetAttribute("RideKitReady") then
			return
		end

		-- 1. find the wheels and pivots ------------------------------------------------
		local wheels = {}
		for _, d in ipairs(bike:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == cfg.WheelPartName then
				table.insert(wheels, d)
			end
		end
		assert(#wheels == 2, `RideKit: expected 2 parts named "{cfg.WheelPartName}" in {bike:GetFullName()}, found {#wheels}`)

		local steerHinge = bike:FindFirstChild(cfg.SteerHingeName, true) :: BasePart?
		local swingHinge = bike:FindFirstChild(cfg.SwingHingeName, true) :: BasePart?

		local front, rear = wheels[1], wheels[2]
		if steerHinge then
			if (wheels[2].Position - steerHinge.Position).Magnitude < (wheels[1].Position - steerHinge.Position).Magnitude then
				front, rear = wheels[2], wheels[1]
			end
		else
			-- the wheel nearer to anything called fork/handlebar is the front
			local best = math.huge
			for _, d in ipairs(bike:GetDescendants()) do
				if d:IsA("BasePart") and hasWord(d.Name, { "fork", "handlebar" }) then
					for i, w in ipairs(wheels) do
						local dist = (w.Position - d.Position).Magnitude
						if dist < best then
							best = dist
							front, rear = w, wheels[3 - i]
						end
					end
				end
			end
		end

		local up = Vector3.yAxis
		local flat = front.Position - rear.Position
		local fwd = Vector3.new(flat.X, 0, flat.Z).Unit
		local right = fwd:Cross(up)
		local radF = math.max(front.Size.Y, front.Size.Z) / 2
		local radR = math.max(rear.Size.Y, rear.Size.Z) / 2
		local wheelbase = Vector3.new(flat.X, 0, flat.Z).Magnitude

		local steerPos, steerAxis
		if steerHinge then
			steerPos = steerHinge.Position
			local a = steerHinge.Position - front.Position
			a -= right * a:Dot(right)
			steerAxis = a.Unit
		else
			local rake = math.rad(cfg.FallbackRake)
			steerAxis = (up * math.cos(rake) - fwd * math.sin(rake)).Unit
			steerPos = front.Position + steerAxis * radF * 1.6
		end
		local swingPos = if swingHinge then swingHinge.Position else rear.Position + fwd * wheelbase * 0.38

		-- 2. clear old joints, build roots ---------------------------------------------
		for _, d in ipairs(bike:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end

		local center = (front.Position + rear.Position) / 2 + up * (radR * 0.7) -- reference for the rider fit
		-- RideKit_Chassis carries all the mass (bike + rider): centred on the centre of mass,
		-- long enough to have a real bike's pitch inertia, and it's what hits walls
		local com = Rig.chassisCenter(front.Position, rear.Position, radR, fwd, up, cfg)
		local chassis = Instance.new("Part")
		chassis.Name = "RideKit_Chassis"
		chassis.Size = Rig.chassisSize(wheelbase)
		chassis.CFrame = CFrame.lookAt(com, com + fwd)
		chassis.Transparency = 1
		chassis.CanCollide = true
		chassis.CanQuery = false
		chassis.CanTouch = false
		chassis.RootPriority = 127
		chassis.CustomPhysicalProperties = PhysicalProperties.new(cfg.ChassisDensity, 0.5, 0, 1, 1)
		chassis.Anchored = true
		chassis.Parent = bike

		-- invisible guards inside each wheel: they only touch the ground when the suspension
		-- bottoms out or the bike falls over, and they stop the wheels going through walls
		for _, w in ipairs({ front, rear }) do
			local r = math.max(w.Size.Y, w.Size.Z) / 2
			local guard = Instance.new("Part")
			guard.Name = "RideKit_WheelGuard"
			guard.Shape = Enum.PartType.Cylinder
			guard.Size = Vector3.new(0.3, r * 1.4, r * 1.4)
			guard.CFrame = CFrame.fromMatrix(w.Position, right, up)
			guard.Transparency = 1
			guard.CanCollide = true
			guard.CanQuery = false
			guard.CanTouch = false
			guard.Massless = true
			guard.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0, 1, 1)
			guard.Anchored = false
			guard.Parent = bike
			weld(chassis, guard)
		end

		local steerPivot = helper("RideKit_SteerPivot", CFrame.fromMatrix(steerPos, right, steerAxis), bike)
		local frontSlider = helper("RideKit_FrontSlider", CFrame.fromMatrix(front.Position, right, steerAxis), bike)
		local frontHub = helper("RideKit_FrontHub", CFrame.fromMatrix(front.Position, right, up), bike)
		local swingPivot = helper("RideKit_SwingPivot", CFrame.fromMatrix(swingPos, right, up), bike)
		local rearHub = helper("RideKit_RearHub", CFrame.fromMatrix(rear.Position, right, up), bike)
		motor("RideKit_SteerMotor", chassis, steerPivot)
		motor("RideKit_FrontSlideMotor", steerPivot, frontSlider) -- slides along the steering axis
		motor("RideKit_FrontHubMotor", frontSlider, frontHub) -- spins
		motor("RideKit_SwingMotor", chassis, swingPivot)
		motor("RideKit_RearHubMotor", swingPivot, rearHub)

		-- 3. sort every part into a group --------------------------------------------
		local ours = {
			[chassis] = true,
			[steerPivot] = true,
			[frontSlider] = true,
			[frontHub] = true,
			[swingPivot] = true,
			[rearHub] = true,
		}
		local ctx = {
			frontPos = front.Position,
			rearPos = rear.Position,
			radF = radF,
			radR = radR,
			steerPos = steerPos,
			steerAxis = steerAxis,
			swingPos = swingPos,
			fwd = fwd,
			right = right,
			up = up,
		}
		local roots = {
			body = chassis,
			steer = steerPivot,
			frontSlide = frontSlider,
			frontSpin = frontHub,
			swing = swingPivot,
			rearSpin = rearHub,
		}
		local counts = { body = 0, steer = 0, frontSlide = 0, frontSpin = 0, swing = 0, rearSpin = 0 }
		local bar: BasePart? = nil -- widest steering part = handlebar
		local barWidth = 0
		local bodyParts = {}
		for _, part in ipairs(bike:GetDescendants()) do
			if not part:IsA("BasePart") or ours[part] or part.Name == "RideKit_WheelGuard" then
				continue
			end
			local group = Rig.classify({
				name = part.Name,
				pos = part.Position,
				isFront = part == front,
				isRear = part == rear,
				inFront = part:IsDescendantOf(front),
				inRear = part:IsDescendantOf(rear),
				parentIsFront = part.Parent == front,
				ancestors = ancestorsOf(part, bike),
			}, ctx)
			if group == "steer" then
				local w = extentAlong(part.CFrame, part.Size, right)
				if w > barWidth then
					bar, barWidth = part, w
				end
			elseif group == "body" then
				table.insert(bodyParts, {
					name = part.Name,
					parentName = if part.Parent then part.Parent.Name else "",
					cf = part.CFrame,
					size = part.Size,
					part = part,
				})
			end
			weld(roots[group], part)
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			counts[group] += 1
		end

		-- 4. seat, pegs, grips, rider position --------------------------------------------
		local seatRef = Rig.pickSeat(bodyParts, cfg.SeatPartKeyword, ctx)
		local pegL, pegR = Rig.pickPegs(bodyParts, right, cfg.PegInset)
		if not pegL then
			local c = swingPos + fwd * 0.35 + up * 0.05
			pegL, pegR = c - right * 0.6, c + right * 0.6
		end
		local gc = steerPos + steerAxis * 0.9 - fwd * 0.3
		local rider = Rig.riderSetup({
			seat = seatRef,
			bar = if bar then { cf = bar.CFrame, size = bar.Size } else nil,
			gripsGuess = { gc - right * 1.1, gc + right * 1.1 },
			pegL = pegL,
			pegR = pegR,
			fwd = fwd,
			right = right,
			up = up,
			center = center,
			radR = radR,
			wheelbase = wheelbase,
		}, cfg)

		local seat = Instance.new("VehicleSeat")
		seat.Name = "RideKit_Seat"
		seat.Size = Vector3.new(1, 0.2, 1.2)
		seat.CFrame = CFrame.lookAt(rider.seatPos, rider.seatPos + fwd)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.Massless = true
		seat.MaxSpeed = 0
		seat.Torque = 0
		seat.TurnSpeed = 0
		seat.HeadsUpDisplay = false
		seat.Anchored = false
		seat.Parent = bike
		weld(chassis, seat)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RideKit_Prompt"
		prompt.ActionText = "Ride"
		prompt.ObjectText = bike.Name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = seat

		-- 5. data for the client ---------------------------------------------------------
		bike.PrimaryPart = chassis
		bike:SetAttribute("RK_FrontAxle", chassis.CFrame:PointToObjectSpace(front.Position))
		bike:SetAttribute("RK_RearAxle", chassis.CFrame:PointToObjectSpace(rear.Position))
		bike:SetAttribute("RK_RadiusF", radF)
		bike:SetAttribute("RK_RadiusR", radR)
		bike:SetAttribute("RK_SwingArm", math.max((rear.Position - swingPos).Magnitude, 0.5))
		bike:SetAttribute("RK_GripL", steerPivot.CFrame:PointToObjectSpace(rider.gripL))
		bike:SetAttribute("RK_GripR", steerPivot.CFrame:PointToObjectSpace(rider.gripR))
		bike:SetAttribute("RK_PegL", chassis.CFrame:PointToObjectSpace(rider.pegL))
		bike:SetAttribute("RK_PegR", chassis.CFrame:PointToObjectSpace(rider.pegR))
		bike:SetAttribute("RK_RiderOffset", rider.riderOffset)
		bike:AddTag("RideKitBike")
		bike:SetAttribute("RideKitReady", true)

		print(
			`RideKit: {bike.Name} rigged. body {counts.body}, steering {counts.steer}, fork lowers {counts.frontSlide}, `
				.. `front wheel {counts.frontSpin}, `
				.. `swingarm {counts.swing}, rear wheel {counts.rearSpin} parts. `
				.. `Grips from "{if bar then bar.Name else "(guessed)"}", seat "{if seatRef then seatRef.name else "(guessed)"}", `
				.. `rider {string.format("%.2f", rider.forward)} forward`
		)
		return { chassis = chassis, seat = seat, prompt = prompt }
	end

	return Rig
end)()
local Physics = (function()
	-- RideKit.Physics: dirt-bike dynamics on one rigid body (RideKit_Chassis).
	-- Runs on whoever owns the bike's physics: the rider's client while riding,
	-- the server while it rolls to a stop. Roblox moves the body (gravity,
	-- collisions); every frame this adds impulses where real forces act:
	--
	--   * suspension: a spring and damper per wheel. They're solved implicitly and
	--     together, so they stay stable at any frame rate and the load moves between
	--     the wheels: the fork dives under braking and the rear squats under power.
	--   * wheels: round in side view (rays fan around each wheel, so it rolls up kerbs)
	--     and round in section (a leaned bike rolls on the tyre's shoulder).
	--   * tyres: at each contact patch, drive and brake force plus sideways grip,
	--     limited by a friction circle (grip x load x surface). Ask too much and
	--     the tyre slides: drifts on dirt, lowsides on ice.
	--   * steering: the front wheel turns and the bike follows its wheels. Lock
	--     shrinks with speed, so the balancing lean never passes MaxLean.
	--   * balance: the rider holds the lean that balances the turn.
	--   * pitch is free: wheelies, stoppies and air control come from the rider
	--     moving their weight and from throttle and brakes. The rest is physics:
	--     the bike pivots on the tyre, falls back down, or loops over.
	--   * crashes: lean too far, loop a wheelie, or hit a wall.
	--
	-- All the mass is in RideKit_Chassis (every other part, and the rider while
	-- seated, is massless), so its box inertia is the bike's inertia.

	local Physics = {}
	Physics.__index = Physics

	-- tyre grip by surface (Enum.Material names); anything else 0.9
	local SURFACE_GRIP = {
		Asphalt = 1.05,
		Concrete = 1.0,
		Pavement = 1.0,
		Brick = 0.95,
		Cobblestone = 0.85,
		Slate = 0.95,
		Rock = 0.9,
		Basalt = 0.95,
		Limestone = 0.9,
		Sandstone = 0.85,
		Granite = 0.95,
		Marble = 0.75,
		Wood = 0.85,
		WoodPlanks = 0.85,
		Plastic = 0.85,
		SmoothPlastic = 0.8,
		Fabric = 0.85,
		Metal = 0.75,
		DiamondPlate = 0.85,
		CorrodedMetal = 0.8,
		Foil = 0.6,
		Glass = 0.5,
		Grass = 0.7,
		LeafyGrass = 0.65,
		Ground = 0.65,
		Mud = 0.4,
		Sand = 0.5,
		Salt = 0.6,
		Snow = 0.35,
		Ice = 0.15,
		Glacier = 0.2,
		CrackedLava = 0.85,
		Pebble = 0.6,
		Rubber = 1.1,
		Carpet = 0.9,
		Cardboard = 0.7,
		Plaster = 0.85,
		Leather = 0.8,
		ClayRoofTiles = 0.85,
		RoofShingles = 0.85,
	}

	-- rays fanned around each wheel's rim (0 = straight down the suspension)
	local FAN = { math.rad(28), -math.rad(28), math.rad(56), -math.rad(56) }

	local function clamp(x, a, b)
		return math.max(a, math.min(b, x))
	end

	function Physics.new(bike: Model, cfg)
		local self = setmetatable({}, Physics)
		self.bike = bike
		self.cfg = cfg
		self.chassis = bike:WaitForChild("RideKit_Chassis") :: BasePart
		local fa = bike:GetAttribute("RK_FrontAxle") :: Vector3
		local ra = bike:GetAttribute("RK_RearAxle") :: Vector3
		self.wheels = {
			{ axle = fa, radius = bike:GetAttribute("RK_RadiusF") :: number },
			{ axle = ra, radius = bike:GetAttribute("RK_RadiusR") :: number },
		}
		self.wheelbase = (fa - ra).Magnitude
		self.params = RaycastParams.new()
		self.params.FilterType = Enum.RaycastFilterType.Exclude
		self.params.FilterDescendantsInstances = { bike }
		self.params.IgnoreWater = true -- the wheels sink, they don't ride on water
		self:reset()
		return self
	end

	-- call when the physics changes hands (mount / dismount)
	function Physics:reset()
		self.comp = { 0, 0 }
		self.load = { 0, 0 }
		self.steerAngle = 0
		self.crashed = false
		self.crashReason = nil
		self.fallSide = 1
		self.washTime = 0
		self.wheelieOn = false
		self.aim = 0
		self.aimI = 0
		self.stoppieOn = false
		self.aimS = 0
		self.sliding = { false, false }
		self.lastHs = nil
		self.impact = 0
		self.airTime = 0
		self.out = {
			speed = 0,
			steerAngle = 0,
			lean = 0,
			comp = { 0, 0 },
			contact = { false, false },
			slip = { 0, 0 },
			wheelie = false,
			wheelieAngle = 0,
			balanceAngle = 0.6,
			aim = 0,
			stoppie = false,
			stoppieAngle = 0,
			airborne = false,
			airTime = 0,
			crashed = false,
			crashReason = nil,
			rearBrakeAssist = 0,
			braking = false,
			standing = false,
		}
	end
	Physics.resetHeading = Physics.reset -- old name

	function Physics:setIgnore(list: { Instance })
		self.params.FilterDescendantsInstances = list
	end

	-- steering lock at this speed: the balancing lean at full lock is MaxLean
	-- (balance: sin(lean) = v^2 tan(steer) / (g wheelbase))
	function Physics.lockAt(cfg, wheelbase: number, speed: number): number
		local v = math.max(math.abs(speed), 1)
		local g = workspace.Gravity
		return math.min(math.rad(cfg.MaxSteerAngle), math.atan(wheelbase * g * math.sin(math.rad(cfg.MaxLean)) / (v * v)))
	end

	-- rigid-body helpers (state cached at the start of step) ---------------------------
	function Physics:invI(vec: Vector3): Vector3
		local l = self.cf:VectorToObjectSpace(vec)
		local I = self.I
		return self.cf:VectorToWorldSpace(Vector3.new(l.X / I.X, l.Y / I.Y, l.Z / I.Z))
	end

	function Physics:inertiaAbout(axis: Vector3): number
		local l = self.cf:VectorToObjectSpace(axis)
		local I = self.I
		return l.X * l.X * I.X + l.Y * l.Y * I.Y + l.Z * l.Z * I.Z
	end

	-- effective mass of the body at world point p along unit direction n
	function Physics:effMass(p: Vector3, n: Vector3): number
		local r = p - self.com
		return 1 / (1 / self.m + n:Dot(self:invI(r:Cross(n)):Cross(r)))
	end

	function Physics:pointVel(p: Vector3): Vector3
		return self.v + self.w:Cross(p - self.com)
	end

	function Physics:impulse(J: Vector3, at: Vector3)
		self.v += J / self.m
		self.w += self:invI((at - self.com):Cross(J))
		self.chassis:ApplyImpulseAtPosition(J, at)
	end

	function Physics:angImpulse(L: Vector3)
		self.w += self:invI(L)
		self.chassis:ApplyAngularImpulse(L)
	end

	-- change the spin about `axis` by dw and nothing else (a plain torque about a tilted axis
	-- would also tip the bike in pitch); returns the size of the angular impulse used
	function Physics:spin(axis: Vector3, dw: number): number
		local l = self.cf:VectorToObjectSpace(axis * dw)
		local I = self.I
		local L = self.cf:VectorToWorldSpace(Vector3.new(l.X * I.X, l.Y * I.Y, l.Z * I.Z))
		self:angImpulse(L)
		return L.Magnitude
	end

	--[[ Ground under wheel i. Returns
	    compression (0 = fully extended, SuspensionTravel = fully compressed),
	    the RaycastResult (nil in the air), the wheel centre, the contact normal and
	    the contact point. Also used by the client to move the forks and swingarm. ]]
	function Physics:probe(i: number)
		local cfg = self.cfg
		local w = self.wheels[i]
		local cf = self.chassis.CFrame
		local up, fwd, right = cf.UpVector, cf.LookVector, cf.RightVector
		local R = w.radius
		local travel = cfg.SuspensionTravel
		local E = cf:PointToWorldSpace(w.axle) - up * (travel * 0.5) -- axle at full extension
		local best, bestHit, bestN, bestP = 0, nil, nil, nil

		-- straight down: a round-section tyre on locally flat ground
		local hit = workspace:Raycast(E + up * (travel + 0.5), -up * (travel + R + 3), self.params)
		if hit then
			local n = hit.Normal
			local cosT = up:Dot(n)
			if cosT > 0.3 then
				local profile = math.min(cfg.TyreProfile, R * 0.5)
				local inPlane = n - right * n:Dot(right) -- ground normal seen in the wheel's plane
				local k = inPlane.Magnitude
				local c = ((R - profile) * k + profile - (E - hit.Position):Dot(n)) / cosT
				if c > best then
					best, bestHit, bestN = c, hit, n
					bestP = E + up * c - (if k > 1e-3 then inPlane / k else n) * (R - profile) - n * profile
				end
			end
		end

		-- fanned around the rim: kerbs, steps and lips meet the tyre before the axle is over them
		local O = E + up * travel
		for _, th in ipairs(FAN) do
			local s, co = math.abs(math.sin(th)), math.cos(th)
			local d = -up * co + fwd * math.sin(th)
			local h = workspace:Raycast(O, d * math.min(R / s, travel + R), self.params)
			if h then
				local t = (h.Position - O).Magnitude
				local disc = R * R - t * t * s * s
				if disc >= 0 then
					local c = travel - t * co + math.sqrt(disc)
					if c > best then
						local W = E + up * c
						local n = W - h.Position
						if n.Magnitude > 1e-3 then
							best, bestHit, bestN, bestP = c, h, n.Unit, h.Position
						end
					end
				end
			end
		end

		if not bestHit then
			return 0, nil, E, nil, nil
		end
		best = math.min(best, travel * 1.8)
		return best, bestHit, E + up * best, bestN, bestP
	end

	-- motor pull per unit throttle at this speed, and the air drag it works against
	-- (electric: full pull up to PowerBand x MaxSpeed, then constant power; drag = pull at MaxSpeed)
	function Physics:motor(speed: number): (number, number)
		local cfg = self.cfg
		local vb = cfg.MaxSpeed * cfg.PowerBand
		local v = math.max(speed, 0)
		return cfg.Acceleration * math.min(1, vb / math.max(v, 1)), cfg.Acceleration * vb / cfg.MaxSpeed ^ 3 * v * v
	end

	local function gripOf(hit, cfg): number
		local name = if hit.Material then hit.Material.Name else ""
		return (SURFACE_GRIP[name] or 0.9) * cfg.Grip
	end

	function Physics:crash(reason: string)
		if not self.crashed and self.cfg.Crashes then
			self.crashed = true
			self.crashReason = reason
			self.fallSide = if (self.out.lean or 0) >= 0 then 1 else -1
		end
	end

	--[[ One step. input = {
	      throttle 0..1, brake 0..1, steer -1..1 (+ = right),
	      leanBack 0..1 (wheelie), leanForward 0..1 (stoppie / stand), driver = bool }
	  Returns self.out. ]]
	function Physics:step(dt: number, input)
		local cfg = self.cfg
		local ch = self.chassis
		local h = clamp(dt, 1 / 240, 1 / 15)
		local cf = ch.CFrame
		local m = ch.AssemblyMass
		local s = ch.Size
		self.cf = cf
		self.m = m
		self.com = ch.AssemblyCenterOfMass
		self.v = ch.AssemblyLinearVelocity
		self.w = ch.AssemblyAngularVelocity
		local v0, w0 = self.v, self.w -- as the frame starts
		self.I = Vector3.new(
			m / 12 * (s.Y * s.Y + s.Z * s.Z),
			m / 12 * (s.X * s.X + s.Z * s.Z),
			m / 12 * (s.X * s.X + s.Y * s.Y)
		)
		local g = workspace.Gravity
		local up, fwd, right = cf.UpVector, cf.LookVector, cf.RightVector
		local Y = Vector3.yAxis
		local L = self.wheelbase
		local travel = cfg.SuspensionTravel
		local out = self.out
		local driver = input.driver == true

		local throttle = clamp(input.throttle or 0, 0, 1)
		local brake = clamp(input.brake or 0, 0, 1)
		local steerIn = clamp(input.steer or 0, -1, 1)
		local back = clamp(input.leanBack or 0, 0, 1)
		local forward = clamp(input.leanForward or 0, 0, 1)
		local control = driver and not self.crashed -- the rider is on and in control
		if not control then
			throttle, steerIn, back, forward = 0, 0, 0, 0
			if self.crashed then
				brake = 0
			end
		end

		local speed = self.v:Dot(fwd)
		local maxLean = math.rad(cfg.MaxLean)
		local lock = Physics.lockAt(cfg, L, speed)
		local steerStep = cfg.SteerSpeed * h
		self.steerAngle = clamp(self.steerAngle + clamp(steerIn * lock - self.steerAngle, -steerStep, steerStep), -lock, lock)

		-- level frame: lean is measured from upright, around the level forward direction
		local levelFwd = fwd - Y * fwd:Dot(Y)
		levelFwd = if levelFwd.Magnitude > 0.05 then levelFwd.Unit else (-(up - Y * up:Dot(Y))).Unit
		local levelRight = levelFwd:Cross(Y)
		local lean = math.atan2(up:Dot(levelRight), up:Dot(Y)) -- + = leaning right
		-- the axis the rider leans the bike about: forward, but square to the pitch axis so
		-- leaning a bike that's pitched up (a turning wheelie) doesn't tip it in pitch too
		local rollAxis = levelFwd - right * levelFwd:Dot(right)
		rollAxis = if rollAxis.Magnitude > 0.1 then rollAxis.Unit else levelFwd

		-- 1. contacts --------------------------------------------------------------------
		local con = {}
		for i = 1, 2 do
			local c, hit, W, n, P = self:probe(i)
			if hit and not (self.crashed and up.Y < 0.3) then
				-- a wheel can't sink into something faster than it's moving (a new ray catching
				-- an edge would otherwise kick it)
				local most = self.comp[i] + (v0 + w0:Cross(W - self.com)).Magnitude * h + 0.08
				if c > most then
					W -= up * (c - most)
					P -= up * (c - most)
					c = most
				end
				-- the ground's slope here (an edge or a wall face says nothing about it)
				local gn = if hit.Normal.Y > 0.6 then hit.Normal elseif n.Y > 0.6 then n else Y
				con[i] = { c = c, hit = hit, W = W, n = n, P = P, gn = gn, cos = math.max(up:Dot(n), 0.3) }
			end
		end
		local frontDown, rearDown = con[1] ~= nil, con[2] ~= nil

		-- 2. suspension: implicit spring + damper per wheel (solved with the tyres in step 5) ------
		local frontAxle = cf:PointToWorldSpace(self.wheels[1].axle)
		local rearAxle = cf:PointToWorldSpace(self.wheels[2].axle)
		local xF = math.max((frontAxle - self.com):Dot(fwd), 0.1)
		local xR = math.max((self.com - rearAxle):Dot(fwd), 0.1)
		local share = { xR / (xF + xR), xF / (xF + xR) }
		for i = 1, 2 do
			local k = con[i]
			if k then
				k.kk = cfg.SpringRate * m * g * share[i] / (travel * 0.5)
				k.cd = cfg.Damping * 2 * math.sqrt(k.kk * m * share[i])
				k.cr = cfg.ReboundDamping * 2 * math.sqrt(k.kk * m * share[i])
				k.me = self:effMass(k.P, k.n) * k.cos * k.cos
				k.vn0 = self:pointVel(k.P):Dot(k.n)
				-- extension speed: from how far the spring moved since last frame (exact at rest)
				local u = if self.comp[i] > 0 then -(k.c - self.comp[i]) / h else k.vn0 / k.cos
				k.u = clamp(u, -cfg.MaxSuspensionSpeed, cfg.MaxSuspensionSpeed)
				k.gu = g * k.n.Y / k.cos * h
				k.lam = 0
			end
		end
		-- one suspension row of the solver below
		local function suspend(k)
			local a = k.u + (self:pointVel(k.P):Dot(k.n) - k.vn0) / k.cos - k.gu
			local cEff = k.c + 4 * math.max(k.c - travel, 0) -- bump stop
			local soft = h * h * k.kk + h * (if a > 0 then k.cr else k.cd) -- rebound is damped harder
			local new = math.max(k.lam + (h * k.kk * cEff - soft * a - k.lam) / (1 + soft / k.me), 0)
			if k.c > travel then -- bottomed out: stop it going any further
				new = math.max(new, k.lam + k.me * (0.3 * (k.c - travel) / h - a))
			end
			new = math.min(new, 30 * m * g * h)
			local d = new - k.lam
			k.lam = new
			if d ~= 0 then
				self:impulse(k.n * (d / k.cos), k.P)
			end
		end
		for i = 1, 2 do
			self.comp[i] = if con[i] then con[i].c else 0
		end

		-- 3. the rider: wheelie / stoppie / air control -------------------------------------------
		local Ip = self:inertiaAbout(right)
		local pitchRate = self.w:Dot(right) -- + = nose rising
		local riderTorque = 0 -- about the right axis, + = nose up
		local rearAssist = 0
		local frontBrakeUse = nil -- the front brake the rider actually uses in a stoppie
		local wheelieThrottle = nil -- the throttle the rider actually uses in a wheelie
		local theta, thetaB, toBal = 0, 0.6, 0.6
		local thetaS = 0
		if rearDown then
			local gn = con[2].gn
			theta = math.asin(clamp(fwd:Dot(gn), -1, 1)) -- nose up from the ground under the rear tyre
			local r = self.com - con[2].P
			toBal = math.pi / 2 - math.atan2(r:Dot(Y), r:Dot(levelFwd)) -- still to go to the balance point
			thetaB = theta + toBal
		end
		local wasWheelie = self.wheelieOn
		if control and rearDown and (back > 0 or self.wheelieOn) then
			local r = self.com - con[2].P
			local x = r:Dot(levelFwd) -- centre of mass ahead of the rear tyre
			local Ic = Ip + m * x * x -- the tyre holds it up, not back: pitch inertia seen by the rider
			local H = math.max(r:Dot(Y), 0.5) -- and above it
			if not self.wheelieOn and back > 0 and speed > cfg.WheelieMinSpeed and throttle > 0.2 then
				self.wheelieOn = true
				self.aim = math.max(theta, 0)
				self.aimI = 0
			end
			if self.wheelieOn then
				-- E + throttle raises the angle the rider is going for, letting off lowers it
				local cap = if cfg.WheelieAssist then thetaB - math.rad(cfg.WheelieSweetSpot) else thetaB + 0.6
				local rate = if back > 0 and throttle > 0.5 and speed > 2 then cfg.WheelieAimUp else -cfg.WheelieAimDown
				if back == 0 then
					rate = -cfg.WheelieAimDown * 1.5
				end
				self.aim = clamp(self.aim + rate * h, 0, math.max(cap, 0))
				-- torque the rider needs about the rear tyre (pitch speed limited near the target)
				local wn = cfg.WheelieControl
				self.aimI = clamp(self.aimI + (self.aim - theta) * h, -0.3, 0.3) -- and remove any steady error
				local wantRate = clamp(wn * 0.5 * (self.aim - theta) + wn * 0.3 * self.aimI, -1.5, 1.5)
				local thetaRate = self.w:Cross(fwd):Dot(con[2].gn) / math.max(math.cos(theta), 0.2)
				local need = Ic * (wn * 1.5 * (wantRate - thetaRate)) + m * g * x
				-- 1. the throttle (the motor pushing the tyre forward lifts the front). Below the
				--    balance point it also gets the pop that lifts the front in the first place.
				local A, drag = self:motor(speed)
				local lift = clamp((0.9 - theta / math.max(thetaB, 0.2)) / 0.4, 0, 1) * m * g * cfg.WheelieLift
				local perThrottle = m * H * A + lift
				local base = -m * H * drag
				local thrMax = math.max(throttle, if back > 0 then 0.5 else 0.3)
				local thr = clamp((need - base) / math.max(perThrottle, 1e-6), 0, thrMax)
				wheelieThrottle = thr
				local rest = need - base - thr * perThrottle
				-- 2. body weight back / forward
				local shift = clamp(rest, -m * g * cfg.RiderShift, m * g * cfg.RiderShift)
				rest -= shift
				riderTorque = shift + thr * lift
				-- 3. past what that can do: cover the rear brake (assist), else it's up to you (S)
				if rest < 0 and cfg.WheelieAssist then
					rearAssist = clamp(-rest / (m * cfg.RearBrake * H), 0, 1)
				end
				if frontDown and self.aim <= 0.01 and back == 0 then
					self.wheelieOn = false
				end
			end
		elseif not rearDown or not control then
			self.wheelieOn = false
		end
		if self.wheelieOn and frontDown and self.aim <= 0.01 then
			self.wheelieOn = false
		end

		-- stoppie: weight forward and brake, pivot on the front tyre
		if control and frontDown and ((forward > 0 and brake > 0) or self.stoppieOn) and not self.wheelieOn then
			local gn = con[1].gn
			thetaS = -math.asin(clamp(fwd:Dot(gn), -1, 1)) -- rear up from the ground under the front tyre
			local r = self.com - con[1].P
			local toBalF = math.pi / 2 - math.atan2(r:Dot(Y), -r:Dot(levelFwd))
			local Ic = Ip + m * r:Dot(levelFwd) ^ 2
			if not self.stoppieOn and forward > 0 and brake > 0 and speed > cfg.StoppieMinSpeed then
				self.stoppieOn = true
				self.aimS = math.max(thetaS, 0)
			end
			if self.stoppieOn then
				local holding = forward > 0 and brake > 0 and speed > 2
				local cap = math.min(math.rad(cfg.StoppieAngle), thetaS + toBalF - math.rad(6))
				local rate = if holding then cfg.StoppieAimUp else -cfg.StoppieAimDown
				self.aimS = clamp(self.aimS + rate * h, 0, math.max(cap, 0))
				local wn = cfg.WheelieControl
				local x = -r:Dot(levelFwd) -- centre of mass behind the front tyre
				local H = math.max(r:Dot(Y), 0.5) -- and above it
				local wantRate = clamp(wn * 0.5 * (self.aimS - thetaS), -1.5, 1.5)
				local thetaRate = -self.w:Cross(fwd):Dot(con[1].gn) / math.max(math.cos(thetaS), 0.2)
				local need = Ic * (wn * 1.5 * (wantRate - thetaRate)) + m * g * x -- rear-up torque needed
				-- 1. the front brake lifts the rear (helped by a shove from the rider to get it up)
				local lift = clamp((0.6 - thetaS / math.max(cap, 0.1)) / 0.4, 0, 1) * m * g * cfg.StoppieLift
				local per = m * H * cfg.FrontBrake + lift
				local b = clamp(need / per, 0, math.max(brake, 0.3))
				frontBrakeUse = b
				-- 2. body weight forward / back for the rest
				local shift = clamp(need - b * per, -m * g * cfg.RiderShift, m * g * cfg.RiderShift)
				riderTorque = -(shift + b * lift)
				if toBalF < -math.rad(cfg.LoopOutAngle) then
					self:crash("endo")
				end
				if rearDown and self.aimS <= 0.01 and not holding then
					self.stoppieOn = false
				end
			end
		elseif not frontDown or not control then
			self.stoppieOn = false
		end

		local airborne = not frontDown and not rearDown
		if airborne then
			self.airTime += h
		else
			self.airTime = 0
		end
		if control and airborne then
			-- the rider lines the bike up with where it's flying (so it lands on both wheels);
			-- E / Q lift or drop the nose from there, throttle / brake spin the rear wheel up or stop it
			local vm = self.v.Magnitude
			local pitch = math.asin(clamp(fwd.Y, -1, 1))
			local flight = if vm > 5 then math.asin(clamp(self.v.Y / vm, -1, 1)) else 0
			local aim = clamp(flight, -0.7, 0.5)
			-- coming down: match the slope it's landing on (a touch nose-up on the flat)
			local below = workspace:Raycast(self.com, Vector3.new(0, -40, 0), self.params)
			if below then
				local d = levelFwd - below.Normal * levelFwd:Dot(below.Normal)
				local slope = if d.Magnitude > 1e-3 then math.asin(clamp(d.Unit.Y, -1, 1)) else 0
				local near = clamp((12 - (self.com.Y - below.Position.Y)) / 8, 0, 1)
				aim += (slope + 0.06 - aim) * near
			end
			aim += cfg.AirLean * (back - forward)
			local wn = if cfg.AirAssist then cfg.AirControl else 0
			local alpha = wn * wn * (aim - pitch) - 2 * wn * pitchRate * 0.8
			alpha = clamp(alpha, -cfg.AirPitch, cfg.AirPitch)
			if not cfg.AirAssist then
				alpha = cfg.AirPitch * (back - forward)
			end
			alpha += cfg.AirThrottle * (throttle - brake)
			riderTorque = Ip * alpha
			self:spin(Y, (-steerIn * cfg.AirYaw - self.w:Dot(Y)) * (1 - math.exp(-4 * h)))
		elseif control and not self.wheelieOn and not self.stoppieOn then
			-- weight forward / back while riding
			riderTorque = m * g * cfg.RiderShift * (back - forward) * 0.5
			if frontDown ~= rearDown and cfg.AirAssist and math.abs(speed) > 8 then
				-- one wheel went light (a lip, a bump, landing on one wheel): the rider holds the
				-- bike's attitude and lets it settle back onto the ground gently
				local k = con[if rearDown then 2 else 1]
				local rel = math.asin(clamp(fwd:Dot(k.gn), -1, 1))
				local r = self.com - k.P
				local Ic = Ip + m * r:Dot(levelFwd) ^ 2
				local wantRate = clamp(-3 * rel, -1.5, 1.5)
				-- (only as much as that tyre is actually holding the bike up: one rolling off an
				-- edge holds nothing)
				local support = clamp(self.load[if rearDown then 2 else 1] / (m * g), 0, 1)
				local gravity = -m * g * r:Cross(Y):Dot(right) -- gravity's pitch torque about that tyre
				local lim = m * g * (cfg.RiderShift + cfg.WheelieLift) * support
				riderTorque += clamp(Ic * 8 * (wantRate - pitchRate) - gravity * support, -lim, lim)
				if rearDown and rel > 0.12 then
					-- the front's coming up by itself: ease off the throttle (wheelie control)
					wheelieThrottle = throttle * clamp(1 - (rel - 0.12) / 0.15, 0, 1)
				end
			end
		end
		if riderTorque ~= 0 then
			self:angImpulse(right * (riderTorque * h))
		end

		-- a crashed bike with nobody holding it up falls over
		if self.crashed and not airborne and math.abs(lean) < 0.6 then
			local Ir = self:inertiaAbout(rollAxis)
			self:angImpulse(rollAxis * (Ir * 1.5 * self.fallSide * h))
		end

		-- 4. lean target: the lean that balances the turn ------------------------------------------
		local rollTarget = nil
		if not self.crashed and not airborne then
			local target = 0
			if math.abs(speed) > 3 then
				local steer = self.steerAngle * (if frontDown then 1 else cfg.WheelieSteer)
				local wKin = speed * math.tan(steer) / (L * math.max(math.cos(lean), 0.3))
				local wMeas = -self.w:Dot(Y)
				target = math.atan(speed * (0.6 * wKin + 0.4 * wMeas) / g)
			end
			target = clamp(target, -maxLean * 1.15, maxLean * 1.15)
			rollTarget = clamp((target - lean) * cfg.RollStiffness, -cfg.RollRate, cfg.RollRate)
			-- only the rear tyre down (wheelie): lean it round
			if rearDown and not frontDown and control then
				local n = con[2].gn
				local want = -speed * math.tan(self.steerAngle * cfg.WheelieSteer) / L
				self:spin(n, (want - self.w:Dot(n)) * (1 - math.exp(-8 * h)))
			end
		elseif not self.crashed and airborne and control then
			-- level the bike in the air
			self:spin(rollAxis, (-lean * 2 - self.w:Dot(rollAxis)) * (1 - math.exp(-3 * h)))
		end

		-- 5. tyres: drive / brake along the wheel, grip across it, inside the friction circle.
		-- Solved together with the rider's lean so the side force doesn't tip the bike over.
		local drive = 0
		if wheelieThrottle then
			throttle = wheelieThrottle
		end
		if throttle > 0 then
			local A, drag = self:motor(speed)
			drive = throttle * A - drag
		elseif brake > 0 and speed < 1.5 and driver and not self.stoppieOn then
			drive = -brake * cfg.Acceleration * 0.35 * clamp(1 + math.min(speed, 0) / cfg.ReverseSpeed, 0, 1)
			brake = 0
		end
		if rearAssist > 0 or frontBrakeUse then
			drive = math.min(drive, 0) -- off the throttle while braking to hold the angle
		end
		local slip = { 0, 0 }
		for i = 1, 2 do
			local k = con[i]
			if k then
				-- rolling direction: across the wheel's axle, along the ground (a leaned, steered
				-- wheel turns tighter than the bar angle: tan(steer) / cos(lean)). Along the ground's
				-- slope even on an edge, so drive and brakes don't flip the bike over a lip.
				local n = k.gn
				local axle = if i == 1 then CFrame.fromAxisAngle(up, -self.steerAngle):VectorToWorldSpace(right) else right
				local t = n:Cross(axle)
				if t.Magnitude > 1e-3 then
					t = t.Unit
					k.t, k.l = t, t:Cross(n)
					k.ml = self:effMass(k.P, k.l)
					k.mu = gripOf(k.hit, cfg) * (if self.sliding[i] then cfg.SlideGrip else 1)
					local Jt = if i == 2 then drive * m * h else 0
					local decel = cfg.RollingDrag * share[i]
					if i == 1 then
						decel += (frontBrakeUse or brake) * cfg.FrontBrake
					else
						decel += math.max(brake, rearAssist) * cfg.RearBrake + (if throttle == 0 then cfg.CoastDecel else 0)
					end
					-- brakes stop the wheel, never push the bike backwards: limit by the hub's speed
					local vHub = (v0 + w0:Cross(k.W - self.com)):Dot(t)
					Jt -= (if vHub >= 0 then 1 else -1) * math.min(decel * m * h, self:effMass(k.W, t) * math.abs(vHub))
					k.Jt0, k.Jt, k.Jl = Jt, 0, 0
				end
			end
		end
		local Ir = 1 / rollAxis:Dot(self:invI(rollAxis)) -- inertia felt by a torque about the lean axis
		local rollMax = cfg.RollTorque * m * g * h
		local rollAcc = 0
		for _ = 1, 8 do
			for i = 1, 2 do
				if con[i] then
					suspend(con[i])
				end
			end
			for _, i in ipairs({ 2, 1 }) do
				local k = con[i]
				if k and k.t then
					k.limit = k.mu * k.lam / k.cos
					local wantL = k.Jl - k.ml * self:pointVel(k.P):Dot(k.l) * cfg.LateralStiffness
					local wantT = k.Jt0
					local mag = math.sqrt(wantT * wantT + wantL * wantL)
					local sc = if mag > k.limit and mag > 1e-9 then k.limit / mag else 1
					wantT *= sc
					wantL *= sc
					self:impulse(k.t * (wantT - k.Jt) + k.l * (wantL - k.Jl), k.P)
					k.Jt, k.Jl = wantT, wantL
					slip[i] = 1 - sc
				end
			end
			if rollTarget then
				local new = clamp(rollAcc + Ir * (rollTarget - self.w:Dot(rollAxis)), -rollMax, rollMax)
				self:angImpulse(rollAxis * (new - rollAcc))
				rollAcc = new
			end
		end
		for i = 1, 2 do
			self.sliding[i] = slip[i] > 0.01 -- once it lets go, it slides on with less grip
			self.load[i] = if con[i] then con[i].lam / con[i].cos / h else 0 -- tyre load (force)
		end

		-- 6. crashes -----------------------------------------------------------------------------
		if control then
			if not airborne and math.abs(lean) > math.rad(cfg.CrashLean) then
				self:crash("lowside")
			end
			if up.Y < 0 or fwd.Y > math.sin(math.rad(78)) then
				self:crash(if fwd.Y > 0 then "loop" else "flip")
			end
			if frontDown and slip[1] > 0.3 and math.abs(lean) > 0.3 then
				self.washTime += h
			else
				self.washTime = 0
			end
			if self.washTime > 0.45 then
				self:crash("lowside")
			end
			if self.wheelieOn and toBal < -math.rad(cfg.LoopOutAngle) then
				self:crash("loop")
			end
			if frontDown and fwd.Y < -math.sin(math.rad(60)) then
				self:crash("endo") -- landed on the front, nose first
			end
		end
		-- hit something hard (a wall, a tall kerb)? Lost a lot of speed all at once.
		local hs = Vector3.new(self.v.X, 0, self.v.Z).Magnitude
		if self.lastHs then
			self.impact = self.impact * math.exp(-10 * h) + math.max(self.lastHs - hs, 0)
			if control and self.impact > cfg.CrashImpact then
				self:crash("hit")
			end
		end
		self.lastHs = hs
		if self.crashed then
			self.wheelieOn, self.stoppieOn = false, false
		end

		out.speed = speed
		out.steerAngle = self.steerAngle
		out.lean = lean
		out.comp[1], out.comp[2] = self.comp[1], self.comp[2]
		out.contact[1], out.contact[2] = frontDown, rearDown
		out.slip[1], out.slip[2] = slip[1], slip[2]
		out.wheelie = self.wheelieOn and not frontDown
		out.wheelieStarted = self.wheelieOn and not wasWheelie
		out.wheelieAngle = theta
		out.balanceAngle = thetaB
		out.aim = self.aim
		out.stoppie = self.stoppieOn and not rearDown
		out.stoppieAngle = thetaS
		out.airborne = airborne
		out.airTime = self.airTime
		out.crashed = self.crashed
		out.crashReason = self.crashReason
		out.rearBrakeAssist = rearAssist
		out.braking = brake > 0.1 and speed > 1
		out.standing = forward > 0 and brake == 0
		return out
	end

	return Physics
end)()

local bike = script.Parent :: Model

-- @body (everything below is shared with the single-file RideKit_Server.lua)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local rig = Rig.build(bike, Config)
local seat: VehicleSeat = rig.seat
local chassis: BasePart = rig.chassis
local prompt: ProximityPrompt = rig.prompt
local physics = Physics.new(bike, Config)

-- the rider's client tells us when they crash
local remote = Instance.new("RemoteEvent")
remote.Name = "RideKit_Remote"
remote.Parent = bike

local function isDown(): boolean
	return chassis.CFrame.UpVector.Y < 0.6
end

-- stand a fallen bike back up where it lies
local function pickUp()
	local cf = chassis.CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(cf.UpVector.X, 0, cf.UpVector.Z)
	end
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bike }
	local hit = workspace:Raycast(cf.Position + Vector3.yAxis * 6, Vector3.yAxis * -30, params)
	local ground = if hit then hit.Position.Y else cf.Position.Y - 3
	local rear = bike:GetAttribute("RK_RearAxle") :: Vector3
	local height = -rear.Y + (bike:GetAttribute("RK_RadiusR") :: number) + 0.1
	local pos = Vector3.new(cf.Position.X, ground + height, cf.Position.Z)
	chassis.Anchored = true
	chassis.CFrame = CFrame.lookAt(pos, pos + flat)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	physics:reset()
end

local function updatePrompt()
	prompt.Enabled = seat.Occupant == nil
	prompt.ActionText = if isDown() then "Pick up" else "Ride"
end

-- get on with the prompt (walking into the seat works too); a fallen bike gets picked up first
prompt.Triggered:Connect(function(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or seat.Occupant ~= nil then
		return
	end
	if isDown() or physics.crashed then
		pickUp()
		updatePrompt()
		return
	end
	seat:Sit(hum)
end)

-- place the rider on the seat: low enough for the feet to reach the pegs
seat.ChildAdded:Connect(function(child)
	if child.Name == "SeatWeld" and child:IsA("Weld") then
		task.defer(function()
			child.C0 = CFrame.new(bike:GetAttribute("RK_RiderOffset"))
			child.C1 = CFrame.new()
		end)
	end
end)

-- while seated the rider weighs nothing: the bike's mass already includes them,
-- so every avatar rides the same
local madeMassless = {}
local function setRiderMassless(character: Model?, on: boolean)
	if on and character then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and not d.Massless then
				d.Massless = true
				table.insert(madeMassless, d)
			end
		end
	else
		for _, p in ipairs(madeMassless) do
			if p.Parent then
				p.Massless = false
			end
		end
		table.clear(madeMassless)
	end
end

local coasting = false
local rider: Player? = nil
local stillTime = 0
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = seat.Occupant
	if occupant then
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if isDown() then
			pickUp()
		end
		coasting = false
		rider = player
		setRiderMassless(occupant.Parent, true)
		chassis.Anchored = false
		if player then
			chassis:SetNetworkOwner(player)
		end
	else
		setRiderMassless(nil, false)
		rider = nil
		if not chassis.Anchored then
			local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
			local crashed = physics.crashed
			chassis:SetNetworkOwner(nil)
			physics:reset()
			local leaning = chassis.CFrame.UpVector.Y < math.cos(math.rad(50))
			if crashed or leaning or math.abs(speed) > Config.DismountCrashSpeed then
				physics:crash("off") -- nobody holding it up: it falls over
			end
			coasting = true
			stillTime = 0
		end
	end
	updatePrompt()
end)

remote.OnServerEvent:Connect(function(player, what)
	if player == rider and what == "crash" then
		physics:crash("rider")
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy() -- thrown off
		end
	end
end)

-- after getting off: roll to a stop (or fall over), then park (anchor) where it ends up
RunService.Stepped:Connect(function(_, dt)
	if not coasting then
		return
	end
	local out = physics:step(dt, { driver = false, brake = if physics.crashed then 0 else 0.6 })
	local still = chassis.AssemblyLinearVelocity.Magnitude < 0.6 and chassis.AssemblyAngularVelocity.Magnitude < 0.4
	stillTime = if still then stillTime + dt else 0
	if stillTime > (if physics.crashed then 1.5 else 0.75) or chassis.Position.Y < workspace.FallenPartsDestroyHeight + 20 then
		coasting = false
		chassis.Anchored = true
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		updatePrompt()
	end
	if out.crashed and prompt.ActionText ~= "Pick up" and isDown() then
		updatePrompt()
	end
end)
