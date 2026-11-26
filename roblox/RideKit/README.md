# RideKit: make the Sur-Ron rideable (R6)

`RideKit.rbxmx` is a folder of scripts you drop inside a bike model. It turns
the static, anchored bike into a rideable one:

- **Riding:** throttle, brake, reverse, steering, lean into corners and
  wheelies, on raycast suspension.
- **Moving parts:** the wheels spin, the fork and bars turn, the front fork
  compresses and the swingarm moves with the suspension.
- **Rider animation:** an R6 riding pose done in code, with hands on the
  grips, feet on the pegs, a tuck under acceleration, leaning into turns,
  leaning back on wheelies, and the head up at speed. Everyone sees it and
  nothing needs uploading.

It was written for `surron1.rbxm`. It finds the two invisible `Wheel`
cylinders, the `TripleTreeHinge` steering pivot and the `RearSwingArmHinge`.

## Set up (2 minutes)

1. In Studio, right-click your bike **Model** in the Explorer and choose
   **Insert from File...**, then pick `roblox/RideKit.rbxmx`. The `RideKit`
   folder must sit directly inside the bike model, next to its parts.
2. Press **Play**. The Output window should print something like:
   `RideKit: Model rigged. body 135, steering 32, front wheel 3, swingarm 7, rear wheel 2 parts`.
3. Walk up to the bike and press **E** (Ride), or walk into the seat.

## Controls

| | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Throttle / brake / reverse | W / S | triggers | thumbstick |
| Steer | A / D | left stick | thumbstick |
| Wheelie (hold while riding) | E | X | Wheelie button |
| Get off | Space | A | Jump button |

## Tuning

Open `RideKit > Config` while play-testing:

- **Rider position:** `SeatHeight` and `SeatForward` move the rider on the
  seat. Raise `SeatHeight` if the legs sink into the bike.
- **Pose:** `Pose.ArmWorld` (hands to the grips), `Pose.LegWorld` and
  `Pose.LegSpread` (feet to the pegs), and `Pose.TorsoLean` (how far the
  rider leans over the bars).
- **Handling:** `MaxSpeed`, `Acceleration`, `SteerRate`, `MaxLean`,
  `WheelieAngle` and the suspension values.

## Optional: the pose as an Animation Editor animation

`RidePose_R6.rbxmx` is the same riding pose as a looping KeyframeSequence.
Use it to preview the pose on a dummy, or to publish an animation ID:

1. Insert it into your R6 dummy (`Rig`), then move it into a folder named
   `AnimSaves` inside the rig. Create the folder if it isn't there.
2. Open the Animation Editor, select the rig, then use **...** > **Load** >
   `RidePose_R6`.
3. To get an animation ID, use **...** > **Publish to Roblox**.

## Notes

- **Seat:** the bike gets its own invisible `VehicleSeat` (`RideKit_Seat`),
  placed on the part whose name contains "seat".
- **When parked:** the bike is anchored. When someone gets on, it unanchors and
  that player's client simulates it. When they get off, it rolls to a stop
  and parks again.
- **R15 avatars:** they can ride too, but they use the default sit pose,
  because the riding animation is for R6.
- **Something moves wrong:** if a part spins or steers when it shouldn't,
  check the counts in the Output. You can rename the part, since parts with
  "fork", "handlebar" or "lever" in the name steer, and "swingarm", "chain" or
  "mudguard" behind the pivot move with the swingarm. Or send me a screenshot.
