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
	-- Search the seat position (forward along the seat, hip height) where the riding posture
	-- (Pose.TorsoLean; 0 = sitting upright) puts the hands on the grips and the feet near the
	-- pegs, with the hips on the seat.
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
				+ 3 * (hipY - seatTop) ^ 2 -- sat right on it, not hovering
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
