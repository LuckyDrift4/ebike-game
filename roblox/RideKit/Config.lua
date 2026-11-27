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
	ReverseSpeed = 0, -- hold S when stopped to back up this fast (0 = no reverse)
	CoastDecel = 4, -- motor braking with the throttle closed
	RollingDrag = 1.5,

	-- brakes (S brakes both wheels; how hard, before the tyres give up)
	FrontBrake = 95,
	RearBrake = 55,

	-- tyres
	Grip = 1.2, -- times the surface grip: asphalt 1.05, concrete 1, grass 0.7, dirt 0.65, sand 0.5, mud 0.4, ice 0.15
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

	-- wheelie: hold E (gamepad X, the Wheelie button on mobile) with the throttle on while
	-- moving. Throttle raises the front, off lowers it, S is the rear brake. Too high and you loop.
	WheelieKeys = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	WheelieMinSpeed = 5,
	WheelieAssist = false, -- true: covers the rear brake so you never go past the balance point
	WheelieSweetSpot = 4, -- degrees below the balance point the assist holds you at
	WheelieAimUp = 0.8, -- how fast the front rises with the throttle on (rad/s)
	WheelieAimDown = 0.55, -- how fast it comes down with the throttle off
	WheelieLift = 2.6, -- how hard the motor lifts the front
	RiderShift = 0.45, -- how far the rider moves their weight back or forward (studs)
	WheelieControl = 7, -- how tightly the rider holds the angle
	WheelieSteer = 0.5, -- steering in a wheelie, times normal (you lean it round)
	LoopOutAngle = 22, -- degrees past the balance point before it's gone

	-- stoppie: brake (S) at speed and the rear wheel lifts. A little at low speed, more the
	-- faster you were going, up to StoppieAngle at StoppieFullSpeed
	StoppieOnBrake = true, -- false: no stoppies from braking
	StoppieMinSpeed = 18, -- slower than this, braking is just braking
	StoppieFullSpeed = 60,
	StoppieAngle = 30, -- biggest stoppie (degrees)
	StoppieAimUp = 1.8, -- how fast the rear rises while braking (rad/s)
	StoppieAimDown = 1.4, -- how fast it comes down when you let go
	StoppieLift = 2.0, -- the rider's shove that gets the rear up

	-- in the air: E tips the nose up, the throttle spins the rear wheel up (nose up) and the
	-- brake stops it (nose down), A / D turn it a little
	AirAssist = false, -- true: the rider lines the bike up with the way it's flying
	LipHold = true, -- the rider holds the bike steady when one wheel leaves the ground (jump lips)
	AirControl = 6, -- how quickly the rider lines it up (rad/s)
	AirLean = 0.6, -- how far E / Q tip it from the flight path (rad)
	AirPitch = 14, -- strongest rotation the rider can make (rad/s²)
	AirThrottle = 2.5,
	AirYaw = 1.5,

	-- crashes: you come off and the bike falls over
	Crashes = false, -- true: also leaning too far, losing the front, hitting walls, over the bars
	LoopCrash = true, -- looping a wheelie (or landing upside down) throws you off
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
	Pose = { TorsoLean = 0.0 }, -- sitting upright: the seat position is fitted for this (matches the Blender clips)
}

return Config
