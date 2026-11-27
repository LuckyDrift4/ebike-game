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

-- tyre grip by surface (Enum.Material names; knobbly dirt-bike tyres); anything else 0.95
local SURFACE_GRIP = {
	Asphalt = 1.0,
	Concrete = 1.0,
	Pavement = 1.0,
	Brick = 0.95,
	Cobblestone = 0.9,
	Slate = 0.95,
	Rock = 0.95,
	Basalt = 0.95,
	Limestone = 0.95,
	Sandstone = 0.95,
	Granite = 0.95,
	Marble = 0.85,
	Wood = 0.95,
	WoodPlanks = 0.95,
	Plastic = 0.95,
	SmoothPlastic = 0.9,
	Fabric = 0.95,
	Metal = 0.85,
	DiamondPlate = 0.95,
	CorrodedMetal = 0.9,
	Foil = 0.8,
	Glass = 0.75,
	Grass = 0.95,
	LeafyGrass = 0.95,
	Ground = 1.0,
	Mud = 0.85,
	Sand = 0.85,
	Salt = 0.85,
	Snow = 0.8,
	Ice = 0.35,
	Glacier = 0.4,
	CrackedLava = 0.95,
	Pebble = 0.9,
	Rubber = 1.1,
	Carpet = 1.0,
	Cardboard = 0.9,
	Plaster = 0.95,
	Leather = 0.95,
	ClayRoofTiles = 0.95,
	RoofShingles = 0.95,
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
	self.stoppieMax = 0
	self.brakeTime = 0
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
	-- (but a wall - anything taller than the axle - can't be climbed: the wheel guard hits it)
	local O = E + up * travel
	local axle = E + up * (travel * 0.5)
	for _, th in ipairs(FAN) do
		local s, co = math.abs(math.sin(th)), math.cos(th)
		local d = -up * co + fwd * math.sin(th)
		local h = workspace:Raycast(O, d * math.min(R / s, travel + R), self.params)
		if h and h.Normal.Y < 0.5 then
			local ahead = fwd * (if th > 0 then 1 else -1)
			if workspace:Raycast(axle, ahead * (R + 0.15), self.params) then
				h = nil
			end
		end
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
	return (SURFACE_GRIP[name] or 0.95) * cfg.Grip
end

function Physics:crash(reason: string)
	local cfg = self.cfg
	-- with Crashes off, only looping it (or ending up on its back) throws the rider off;
	-- a bike with nobody on it ("off", "rider") always falls over
	local allowed = cfg.Crashes
		or reason == "off"
		or reason == "rider"
		or reason == "test"
		or (cfg.LoopCrash and (reason == "loop" or reason == "flip"))
	if not self.crashed and allowed then
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
			-- holding E + throttle eases it up to WheelieAngle (kept under the balance point) and
			-- holds it there; letting off either lowers it. Without the assist a big disturbance
			-- (a bump, a landing) can still take it over.
			local top = math.max(math.min(math.rad(cfg.WheelieAngle), thetaB - math.rad(cfg.WheelieSweetSpot)), 0)
			local rising = back > 0 and throttle > 0.5 and speed > 2
			local goal = if rising then top else 0
			local step = clamp((goal - self.aim) * 4, -cfg.WheelieAimDown * (if back > 0 then 1 else 1.5), cfg.WheelieAimUp)
			self.aim = clamp(self.aim + step * h, 0, top)
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

	-- stoppie: brake at speed (or Q + brake) and the bike pivots on the front tyre; the
	-- faster it was going when the braking started, the higher the rear goes
	local asking = brake > 0.3 and (forward > 0 or cfg.StoppieOnBrake)
	self.brakeTime = if brake > 0.3 then self.brakeTime + h else 0
	if control and frontDown and (asking or self.stoppieOn) and not self.wheelieOn then
		local gn = con[1].gn
		thetaS = -math.asin(clamp(fwd:Dot(gn), -1, 1)) -- rear up from the ground under the front tyre
		local r = self.com - con[1].P
		local toBalF = math.pi / 2 - math.atan2(r:Dot(Y), -r:Dot(levelFwd))
		local Ic = Ip + m * r:Dot(levelFwd) ^ 2
		local flat = gn.Y > 0.97 and fwd.Y > -0.25 -- not down a steep hill (it would go over the bars)
		-- only when the brake goes on hard while going straight and upright (never mid-corner)
		local straight = math.abs(lean) < 0.15 and math.abs(self.steerAngle) < 0.06 and self.brakeTime < 0.3
		if not self.stoppieOn and asking and speed > cfg.StoppieMinSpeed and straight and flat then
			self.stoppieOn = true
			self.aimS = math.max(thetaS, 0)
			local full = math.max(cfg.StoppieFullSpeed - cfg.StoppieMinSpeed, 1)
			self.stoppieMax = math.rad(cfg.StoppieAngle) * clamp((speed - cfg.StoppieMinSpeed * 0.5) / full, 0.15, 1)
		end
		if self.stoppieOn then
			local holding = asking and speed > 2
			-- the rear eases up, rolls on the front, and eases back down as the bike slows
			local slowing = clamp((speed - 3) / 28, 0, 1)
			slowing = slowing * slowing * (3 - 2 * slowing)
			local cap = math.min(self.stoppieMax * slowing, thetaS + toBalF - math.rad(6))
			local goal = if holding then math.max(cap, 0) else 0
			local step = clamp((goal - self.aimS) * 5, -cfg.StoppieAimDown, cfg.StoppieAimUp)
			self.aimS = clamp(self.aimS + step * h, 0, math.max(cap, 0))
			local wn = cfg.WheelieControl
			local x = -r:Dot(levelFwd) -- centre of mass behind the front tyre
			local H = math.max(r:Dot(Y), 0.5) -- and above it
			local wantRate = clamp(wn * 0.5 * (self.aimS - thetaS), -1.5, 1.5)
			local thetaRate = -self.w:Cross(fwd):Dot(con[1].gn) / math.max(math.cos(thetaS), 0.2)
			local need = Ic * (wn * 1.5 * (wantRate - thetaRate)) + m * g * x -- rear-up torque needed
			-- 1. the front brake lifts the rear - hard, but not so hard it's over in an instant
			local perBrake = m * H * cfg.FrontBrake
			local bMax = math.max(math.min(brake, cfg.StoppieDecel / cfg.FrontBrake), 0.3)
			local b = clamp(need / perBrake, math.min(0.3 * brake, bMax), bMax)
			frontBrakeUse = b
			local rest = need - b * perBrake
			-- 2. the rider throws their weight over the bars to get the rear up and keep it there
			local lift = (if holding then 1 else 0.5) * m * g * cfg.StoppieLift
			local shove = clamp(rest, 0, lift)
			rest -= shove
			-- 3. body weight forward / back for the rest
			local shift = clamp(rest, -m * g * cfg.RiderShift, m * g * cfg.RiderShift)
			riderTorque = -(shift + shove)
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
		local wn = cfg.AirControl
		local alpha = clamp(wn * wn * (aim - pitch) - 2 * wn * pitchRate * 0.8, -cfg.AirPitch, cfg.AirPitch)
		if not cfg.AirAssist then
			-- all manual: the bike keeps its spin; E pulls the nose up
			alpha = cfg.AirPitch * (back - forward)
		end
		alpha += cfg.AirThrottle * (throttle - brake)
		riderTorque = Ip * alpha
		if cfg.AirAssist then
			self:spin(Y, (-steerIn * cfg.AirYaw - self.w:Dot(Y)) * (1 - math.exp(-4 * h)))
		elseif steerIn ~= 0 then
			self:spin(Y, -steerIn * cfg.AirYaw * 2 * h)
		end
	elseif control and not self.wheelieOn and not self.stoppieOn then
		-- weight forward / back while riding
		riderTorque = m * g * cfg.RiderShift * (back - forward) * 0.5
		if frontDown ~= rearDown and cfg.LipHold and math.abs(speed) > 8 then
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
	elseif not self.crashed and airborne and control and cfg.AirAssist then
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
	elseif brake > 0 and speed < 1.5 and driver and not self.stoppieOn and cfg.ReverseSpeed > 0 then
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
				if driver and throttle == 0 and drive == 0 and math.abs(speed) < 4 and not self.wheelieOn and not self.stoppieOn then
					decel += 60 -- stopped: the rider holds the brakes, it doesn't creep or roll back
				end
				if i == 1 then
					-- leaned over, the rider brakes gently on the front (trail braking) so the rear
					-- keeps its weight and grip instead of going light and stepping out
					local trail = if frontBrakeUse then 1 else 1 - 0.45 * clamp((math.abs(lean) - 0.1) / 0.4, 0, 1)
					decel += (frontBrakeUse or brake) * cfg.FrontBrake * trail
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
	-- with crashes off the rider always saves it: far more strength once it's leaned right over
	local rollMax = cfg.RollTorque * m * g * h * (if not cfg.Crashes and math.abs(lean) > 0.9 then 3 else 1)
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
				-- brakes and motor never use more than 80% of the grip (ABS / traction control):
				-- the rest keeps the tyre gripping sideways, so it doesn't lock up or slide out
				local wantT = clamp(k.Jt0, -0.8 * k.limit, 0.8 * k.limit)
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
		self.sliding[i] = slip[i] > 0.05 -- once it lets go, it slides on with less grip
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
