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
