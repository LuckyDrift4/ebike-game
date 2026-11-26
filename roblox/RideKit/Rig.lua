-- RideKit.Rig (server): turns a static, anchored bike model into a rideable rig.
--
-- Every BasePart of the model is sorted into one of five groups and welded to
-- that group's root:
--   body        -> RideKit_Chassis   (invisible physics box, carries everything)
--   steer       -> RideKit_SteerPivot (forks, bars, levers; turns about the steering axis)
--   frontSpin   -> RideKit_FrontHub   (front wheel mesh; spins, steers, compresses)
--   swing       -> RideKit_SwingPivot (swingarm, chain, mudguard; pivots with the suspension)
--   rearSpin    -> RideKit_RearHub    (rear wheel mesh; spins)
-- The roots are joined with Motor6Ds whose Transform the client animates.

local Rig = {}

local STEER_WORDS = { "fork", "handlebar", "lever", "grip", "triple", "clamp", "throttle" }
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

local function insideModelNamed(part: Instance, root: Instance, names): boolean
	local p = part.Parent
	while p and p ~= root do
		if names[string.lower(p.Name)] then
			return true
		end
		p = p.Parent
	end
	return false
end

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

-- perpendicular distance from point p to the line through a with unit direction d,
-- and the coordinate of p along that line
local function lineDistance(p: Vector3, a: Vector3, d: Vector3): (number, number)
	local v = p - a
	local along = v:Dot(d)
	return (v - d * along).Magnitude, along
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
	local frontHub = helper("RideKit_FrontHub", CFrame.fromMatrix(front.Position, right, up), bike)
	local swingPivot = helper("RideKit_SwingPivot", CFrame.fromMatrix(swingPos, right, up), bike)
	local rearHub = helper("RideKit_RearHub", CFrame.fromMatrix(rear.Position, right, up), bike)
	motor("RideKit_SteerMotor", chassis, steerPivot)
	motor("RideKit_FrontHubMotor", steerPivot, frontHub)
	motor("RideKit_SwingMotor", chassis, swingPivot)
	motor("RideKit_RearHubMotor", swingPivot, rearHub)

	-- 3. sort every part into a group --------------------------------------------
	local ours = {
		[chassis] = true,
		[steerPivot] = true,
		[frontHub] = true,
		[swingPivot] = true,
		[rearHub] = true,
	}
	local counts = { body = 0, steer = 0, frontSpin = 0, swing = 0, rearSpin = 0 }
	for _, part in ipairs(bike:GetDescendants()) do
		if not part:IsA("BasePart") or ours[part] then
			continue
		end
		local group = "body"
		local pos = part.Position
		local dF = (pos - front.Position).Magnitude
		local dR = (pos - rear.Position).Magnitude
		local steerDist, steerAlong = lineDistance(pos, steerPos, steerAxis)
		if part == front then
			group = "frontSpin"
		elseif part == rear then
			group = "rearSpin"
		elseif dF < radF * 0.3 then
			group = "frontSpin" -- wheel mesh / rim / tyre / disc: centred on the axle
		elseif dR < radR * 0.3 then
			group = "rearSpin"
		elseif part:IsDescendantOf(front) or insideModelNamed(part, bike, STEER_MODELS) or hasWord(part.Name, STEER_WORDS) then
			group = "steer"
		elseif part:IsDescendantOf(rear) or (hasWord(part.Name, SWING_WORDS) and (pos - swingPos):Dot(fwd) < 0.2) then
			group = "swing" -- only parts behind the swingarm pivot
		elseif steerDist < 0.4 and steerAlong > -0.4 then
			group = "steer" -- small bits on the steering column (clamp bolts, stem)
		end
		local root = ({
			body = chassis,
			steer = steerPivot,
			frontSpin = frontHub,
			swing = swingPivot,
			rearSpin = rearHub,
		})[group]
		weld(root, part)
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		counts[group] += 1
	end

	-- 4. seat -------------------------------------------------------------------------
	local seatRef: BasePart? = nil
	for _, d in ipairs(bike:GetDescendants()) do
		if d:IsA("BasePart") and not ours[d] and string.find(string.lower(d.Name), cfg.SeatPartKeyword, 1, true) then
			seatRef = d
			break
		end
	end
	local seatPos
	if seatRef then
		seatPos = Vector3.new(seatRef.Position.X, seatRef.Position.Y + seatRef.ExtentsSize.Y / 2 + 0.1, seatRef.Position.Z)
	else
		seatPos = center + up * (radR * 1.6) - fwd * wheelbase * 0.1
	end
	local seat = Instance.new("VehicleSeat")
	seat.Name = "RideKit_Seat"
	seat.Size = Vector3.new(1, 0.2, 1.2)
	seat.CFrame = CFrame.lookAt(seatPos, seatPos + fwd)
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
	bike:AddTag("RideKitBike")
	bike:SetAttribute("RideKitReady", true)

	print(
		`RideKit: {bike.Name} rigged. body {counts.body}, steering {counts.steer}, front wheel {counts.frontSpin}, `
			.. `swingarm {counts.swing}, rear wheel {counts.rearSpin} parts`
	)
	return { chassis = chassis, seat = seat, prompt = prompt, align = align }
end

return Rig
