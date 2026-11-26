----------------------------------------------------------------------------------------------------------------------------------------------------------------

local Config = (function()
	-- RideKit settings. Tweak these in Studio while play-testing.
	-- Distances are in studs, speeds in studs/second, angles in degrees unless noted.
	local Config = {
		-- names of the parts RideKit looks for inside the bike model
		WheelPartName = "Wheel", -- the two invisible cylinder wheels
		SteerHingeName = "TripleTreeHinge", -- steering head (fork pivots around this)
		SwingHingeName = "RearSwingArmHinge", -- swingarm pivot
		SeatPartKeyword = "seat", -- part whose name contains this is the seat (else the highest seat-shaped part)
		FallbackRake = 26, -- steering-axis angle if there is no TripleTreeHinge

		-- engine / handling
		MaxSpeed = 70, -- ~70 km/h at Roblox scale
		ReverseSpeed = 10,
		Acceleration = 34,
		BrakeDecel = 70,
		CoastDecel = 5,
		SteerRate = 2.4, -- heading change (rad/s) at full lock
		FullTurnSpeed = 10, -- below this speed steering is weaker (a bike can't turn on the spot)
		MaxSteerAngle = 17, -- visual bar angle at walking pace (less at speed; the lean clips are posed at 14)
		MaxLean = 35, -- lean into corners at speed
		LeanFullSpeed = 30,
		LeanResponse = 6,
		SideGrip = 10, -- how quickly sideways sliding is killed (1/s)

		-- suspension (raycast)
		SuspensionTravel = 0.5,
		SpringRate = 1.0, -- 1.0 = sits at half travel; higher = stiffer
		Damping = 0.75, -- 1.0 = no rebound at all; lower = springier (stays stable)
		WeightTransfer = 0.0012, -- nose dive under braking / squat under throttle (rad per stud/s²)
		AlignResponsiveness = 40,
		ChassisDensity = 0.7,

		-- wheelie (hold E on keyboard / X on gamepad / on-screen button on mobile)
		WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
		WheelieAngle = 24,
		WheelieMinSpeed = 6,

		-- rider placement on the seat (R6)
		SeatHeight = "auto", -- "auto" = as low as needed for the feet to reach the pegs, or a number
		-- (HumanoidRootPart height above the seat top, e.g. 1.0)
		SeatForward = "auto", -- "auto" = slide forward until the hands reach the bars, or a number
		GripInset = 0.25, -- hands sit this far in from the ends of the handlebar
		PegInset = 0.15, -- feet sit this far in from the ends of the foot-peg bar

		-- rider animation (keyframed in Blender: blender/anim/ride_anims.blend)
		AnimBlendSpeed = 7, -- how fast the rider moves between ride / tuck / brake / lean / wheelie
		Pose = { TorsoLean = 0.35 }, -- forward lean the seat position is fitted for (matches the Blender clips)
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

		local center = (front.Position + rear.Position) / 2 + up * (radR * 0.7)
		local chassis = Instance.new("Part")
		chassis.Name = "RideKit_Chassis"
		chassis.Size = Vector3.new(1.1, 1.1, wheelbase * 0.75)
		chassis.CFrame = CFrame.lookAt(center, center + fwd)
		chassis.Transparency = 1
		chassis.CanCollide = true
		chassis.CanQuery = false
		chassis.CustomPhysicalProperties = PhysicalProperties.new(cfg.ChassisDensity, 0, 0, 1, 1)
		chassis.Anchored = true
		chassis.Parent = bike

		local att = Instance.new("Attachment")
		att.Name = "RideKit_Att"
		att.Parent = chassis
		local align = Instance.new("AlignOrientation")
		align.Name = "RideKit_Align"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = att
		align.Responsiveness = cfg.AlignResponsiveness
		align.MaxTorque = math.huge
		align.CFrame = chassis.CFrame.Rotation
		align.Parent = chassis

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
			if not part:IsA("BasePart") or ours[part] then
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
		return { chassis = chassis, seat = seat, prompt = prompt, align = align }
	end

	return Rig
end)()
local Physics = (function()
	-- RideKit.Physics: raycast-suspension bike. Runs on whoever owns the bike's
	-- physics: the rider's client while riding, the server while it coasts to a stop.

	local Physics = {}
	Physics.__index = Physics

	function Physics.new(bike: Model, cfg)
		local self = setmetatable({}, Physics)
		self.bike = bike
		self.cfg = cfg
		self.chassis = bike:WaitForChild("RideKit_Chassis") :: BasePart
		self.align = self.chassis:WaitForChild("RideKit_Align") :: AlignOrientation
		self.wheels = {
			{ localPos = bike:GetAttribute("RK_FrontAxle"), radius = bike:GetAttribute("RK_RadiusF") },
			{ localPos = bike:GetAttribute("RK_RearAxle"), radius = bike:GetAttribute("RK_RadiusR") },
		}
		self.comp = { cfg.SuspensionTravel * 0.5, cfg.SuspensionTravel * 0.5 }
		self.params = RaycastParams.new()
		self.params.FilterType = Enum.RaycastFilterType.Exclude
		self.params.FilterDescendantsInstances = { bike }
		self.params.IgnoreWater = false
		self:resetHeading()
		return self
	end

	-- re-read heading from the chassis (call when taking over the physics)
	function Physics:resetHeading()
		local look = self.chassis.CFrame.LookVector
		self.yaw = math.atan2(-look.X, -look.Z)
		self.pitch = 0
		self.roll = 0
		self.wheelie = 0
		self.accel = 0
		self.lastVF = nil
	end

	function Physics:setIgnore(list: { Instance })
		self.params.FilterDescendantsInstances = list
	end

	-- suspension compression for wheel i (0 = fully extended) and the ground hit
	function Physics:probe(i: number): (number, RaycastResult?)
		local cfg = self.cfg
		local w = self.wheels[i]
		local cf = self.chassis.CFrame
		local upv = cf.UpVector
		local travel = cfg.SuspensionTravel
		local mount = cf:PointToWorldSpace(w.localPos) + upv * (travel * 0.5)
		local hit = workspace:Raycast(mount, -upv * (travel + w.radius + 0.6), self.params)
		if hit then
			local dist = (hit.Position - mount).Magnitude
			return math.clamp(travel + w.radius - dist, 0, travel * 1.6), hit
		end
		return 0, nil
	end

	-- one physics step. throttle/steer are -1..1; returns forward speed
	function Physics:step(dt: number, throttle: number, steer: number, wheelieHeld: boolean, hasDriver: boolean): number
		local cfg = self.cfg
		local ch = self.chassis
		dt = math.clamp(dt, 1 / 240, 1 / 20)
		local mass = ch.AssemblyMass
		local g = workspace.Gravity
		local upv = ch.CFrame.UpVector
		local travel = cfg.SuspensionTravel
		local k = cfg.SpringRate * g / travel -- per wheel; two wheels hold the bike at half travel
		local cd = cfg.Damping * math.sqrt(2 * k)

		-- suspension: implicit (backward-Euler) spring + damper along the bike's up axis.
		-- A plain per-frame spring force lags the 240 Hz physics by a frame, which eats
		-- the damping and makes the bike bounce; solving it implicitly is stable at any
		-- frame rate and settles at ride height.
		local hits = {}
		local grounded = false
		local n, C, rateSum, rateN = 0, 0, 0, 0
		for i = 1, 2 do
			local comp, hit = self:probe(i)
			if hit and comp > 0 then
				hits[i] = hit
				grounded = true
				n += 1
				C += comp + 3 * math.max(comp - travel, 0) -- stiff bump stop past full travel
				if self.comp[i] > 0 then
					rateSum += (comp - self.comp[i]) / dt
					rateN += 1
				end
				self.comp[i] = comp
			else
				self.comp[i] = 0
			end
		end
		if n > 0 then
			local gUp = g * math.max(upv.Y, 0.2)
			-- chassis speed along up, measured from how fast the springs extend
			local vUp = if rateN > 0 then -rateSum / rateN else ch.AssemblyLinearVelocity:Dot(upv)
			local vNew = (vUp + dt * (k * C - gUp)) / (1 + n * k * dt * dt + n * cd * dt)
			local dv = math.clamp(vNew - vUp + gUp * dt, -g * dt * 2, g * dt * 8)
			ch:ApplyImpulse(upv * dv * mass)
		end

		-- drive, brake and tyre grip in the heading frame
		local fwd = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
		local right = Vector3.new(math.cos(self.yaw), 0, -math.sin(self.yaw))
		local v = ch.AssemblyLinearVelocity
		local vF = v:Dot(fwd)
		local vS = v:Dot(right)
		if grounded then
			local target, rate
			if throttle > 0.05 then
				target = throttle * cfg.MaxSpeed
				rate = if vF < -0.5 then cfg.BrakeDecel else cfg.Acceleration
			elseif throttle < -0.05 then
				if vF > 0.5 then
					target, rate = 0, cfg.BrakeDecel
				else
					target, rate = throttle * cfg.ReverseSpeed, cfg.Acceleration * 0.5
				end
			else
				target = 0
				rate = if hasDriver then cfg.CoastDecel else cfg.BrakeDecel
			end
			local dv = math.clamp(target - vF, -rate * dt, rate * dt)
			local side = -vS * (1 - math.exp(-cfg.SideGrip * dt))
			ch:ApplyImpulse((fwd * dv + right * side) * mass)

			-- steering turns the heading; weak at walking pace, gentler at top speed
			local speed = math.abs(vF)
			local turn = math.clamp(speed / cfg.FullTurnSpeed, 0, 1) * (1 - 0.45 * math.clamp(speed / cfg.MaxSpeed, 0, 1))
			local dir = if vF >= 0 then 1 else -1
			self.yaw -= steer * cfg.SteerRate * turn * dir * dt
		end

		-- lean into corners (positive roll = lean left)
		local leanAmt = math.clamp(math.abs(vF) / cfg.LeanFullSpeed, 0, 1)
		local targetRoll = if grounded then -steer * math.rad(cfg.MaxLean) * leanAmt else self.roll
		self.roll += (targetRoll - self.roll) * (1 - math.exp(-cfg.LeanResponse * dt))

		-- pitch follows the ground under both wheels, plus the wheelie
		local targetPitch = self.pitch
		if hits[1] and hits[2] then
			local d = hits[1].Position - hits[2].Position
			if d.Magnitude > 0.1 then
				targetPitch = math.asin(math.clamp(d.Y / d.Magnitude, -1, 1))
			end
		elseif not grounded then
			targetPitch = self.pitch * (1 - dt * 0.4)
		end
		self.pitch += (targetPitch - self.pitch) * (1 - math.exp(-10 * dt))
		-- weight transfer: nose dives under braking, squats under acceleration
		if self.lastVF then
			local a = (vF - self.lastVF) / dt
			self.accel += (a - self.accel) * (1 - math.exp(-8 * dt))
		end
		self.lastVF = vF
		local transfer = if grounded then math.clamp(self.accel * cfg.WeightTransfer, -0.07, 0.05) else 0
		local wantWheelie = wheelieHeld and hits[2] ~= nil and vF > cfg.WheelieMinSpeed and throttle > 0.3
		local wTarget = if wantWheelie then math.rad(cfg.WheelieAngle) else 0
		self.wheelie += (wTarget - self.wheelie) * (1 - math.exp(-(if wantWheelie then 2.5 else 4) * dt))

		self.align.CFrame = CFrame.fromEulerAnglesYXZ(self.pitch + self.wheelie + transfer, self.yaw, self.roll)
		return vF
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

-- mount with the prompt (walking into the seat works too)
prompt.Triggered:Connect(function(player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and seat.Occupant == nil then
		seat:Sit(hum)
	end
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

local coasting = false
seat:GetPropertyChangedSignal("Occupant"):Connect(function()
	local occupant = seat.Occupant
	prompt.Enabled = occupant == nil
	if occupant then
		coasting = false
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		chassis.Anchored = false
		if player then
			chassis:SetNetworkOwner(player)
		end
	else
		if not chassis.Anchored then
			chassis:SetNetworkOwner(nil)
			physics:resetHeading()
			coasting = true
		end
	end
end)

-- after dismounting: brake to a stop on the server, then park (anchor) upright
local stillTime = 0
RunService.Stepped:Connect(function(_, dt)
	if not coasting then
		return
	end
	local speed = physics:step(dt, 0, 0, false, false)
	if math.abs(speed) < 0.5 then
		stillTime += dt
	else
		stillTime = 0
	end
	if stillTime > 0.75 then
		coasting = false
		stillTime = 0
		chassis.Anchored = true
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end
end)
