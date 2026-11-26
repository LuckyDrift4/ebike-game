-- RideKit settings. Tweak these in Studio while play-testing.
-- Distances are in studs, speeds in studs/second, angles in degrees unless noted.
local Config = {
	-- names of the parts RideKit looks for inside the bike model
	WheelPartName = "Wheel", -- the two invisible cylinder wheels
	SteerHingeName = "TripleTreeHinge", -- steering head (fork pivots around this)
	SwingHingeName = "RearSwingArmHinge", -- swingarm pivot
	SeatPartKeyword = "seat", -- first part whose name contains this is used to place the seat
	FallbackRake = 26, -- steering-axis angle if there is no TripleTreeHinge

	-- engine / handling
	MaxSpeed = 70, -- ~70 km/h at Roblox scale
	ReverseSpeed = 10,
	Acceleration = 34,
	BrakeDecel = 70,
	CoastDecel = 5,
	SteerRate = 2.4, -- heading change (rad/s) at full lock
	FullTurnSpeed = 10, -- below this speed steering is weaker (a bike can't turn on the spot)
	MaxSteerAngle = 30, -- visual fork angle at walking pace (less at speed)
	MaxLean = 35, -- lean into corners at speed
	LeanFullSpeed = 30,
	LeanResponse = 6,
	SideGrip = 10, -- how quickly sideways sliding is killed (1/s)

	-- suspension (raycast)
	SuspensionTravel = 0.5,
	SpringRate = 1.0, -- 1.0 = sits at half travel when parked
	Damping = 0.45,
	AlignResponsiveness = 40,
	ChassisDensity = 0.7,

	-- wheelie (hold E on keyboard / X on gamepad / on-screen button on mobile)
	WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	WheelieAngle = 24,
	WheelieMinSpeed = 6,

	-- rider placement on the seat (R6)
	SeatHeight = "auto", -- "auto" = as low as needed for the feet to reach the pegs, or a number
	-- (HumanoidRootPart height above the seat top, e.g. 1.0)
	SeatForward = 0.55, -- slide the rider forward on the seat (towards the bars)
	GripInset = 0.25, -- hands sit this far in from the ends of the handlebar
	PegInset = 0.15, -- feet sit this far in from the ends of the foot-peg bar

	-- rider pose (radians). Hands are aimed at the grips and feet at the pegs
	-- automatically; these only shape the body around them.
	Pose = {
		TorsoLean = 0.30, -- leaning forward over the bars
		TorsoLeanThrottle = 0.10, -- extra tuck when accelerating
		TorsoLeanSpeed = 0.08, -- extra tuck at top speed
		BrakeLeanBack = 0.12,
		WheelieLeanBack = 0.30,
		MaxExtraLean = 0.45, -- lean up to this much further when the grips are out of reach
		TurnLean = 0.18, -- rider leans further into the corner than the bike
		TurnTwist = 0.15, -- shoulders follow the bars (fine-tuned automatically so both hands reach)
		HeadTurn = 0.30, -- look into the corner
		HeadDown = 0.10, -- slight chin-down when slow
		HeadUp = 0.10, -- look further ahead at speed
		Bounce = 0.04, -- body bob from the suspension
	},}

return Config
