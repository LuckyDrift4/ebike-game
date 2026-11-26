# RideKit: make the Sur-Ron rideable (R6)

`RideKit.rbxmx` is a folder of scripts you drop inside a bike model. It turns
the static, anchored bike into a rideable one:

- **Riding:** throttle, brake, reverse, steering, lean into corners and
  wheelies, on raycast suspension.
- **Moving parts:** the wheels spin, the fork and bars turn, the front fork
  compresses and the swingarm moves with the suspension.
- **Rider animation:** made in Blender (`blender/anim/ride_anims.blend`).
  There are six keyframed R6 clips: ride, tuck, brake, lean left, lean right
  and wheelie. RideKit plays the Blender keyframes and blends between the clips
  with throttle, brake, steering and wheelie. Every client plays them, so
  nothing needs uploading.

It works with both bike models:

- **`surron1.rbxm`:** parts named fork, handlebar and swingarm.
- **`surron2.rbxm`:** the chassis-kit layout.
  - `Misc > Wheel` is the handlebar assembly.
  - `FrontSection` and `RearSection` each have a `Wheel` part with `Parts` and
    `WheelFixed` inside.
  - `Misc > Step` holds the foot pegs.
  - The seat is found by its shape.

Both need two invisible `Wheel` parts, a `TripleTreeHinge` and a
`RearSwingArmHinge`. If the model has a looped motor sound, a `Wind` sound or a
brake light (`Lights > brk`), RideKit uses them: the motor pitch rises with
speed and the brake light turns on when you brake.

## Easiest set-up: copy and paste two scripts

1. Delete any broken scripts you made earlier, for example one starting
   with `<roblox`.
2. In the Explorer, hover over the bike **Model** (the one with the two
   `Wheel` parts), click **+** and add a **Script** (a normal Script). Delete
   the `print("Hello world!")` line and paste **all** of
   `roblox/RideKit_Server.lua`.
3. Open **StarterPlayer > StarterPlayerScripts**, click **+** and add a
   **LocalScript**. Paste **all** of `roblox/RideKit_Client.lua`.
4. Press **Play**, walk to the bike and press **E**.

Use either this or the `RideKit.rbxmx` method below, not both.

## Set up with Insert from File

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

The rider is placed automatically:
- **Hands:** aimed at the ends of the handlebar, so they follow the bars when
  you steer.
- **Feet:** aimed at the foot pegs.
- **Height:** the rider sits just low enough for the feet to reach the pegs.
- **Head:** looks down the road and into corners.

The Output line `Grips from "...", pegs from "..."` shows which parts were
used. To adjust things, open `RideKit > Config` (or the top of the server
script):

- **Rider position:** `SeatForward` slides the rider toward the bars.
  `SeatHeight` is `"auto"` or a fixed number.
- **Hands and feet:** `GripInset` and `PegInset` move them inwards from the
  ends of the bar and pegs.
- **Body:** `Pose.TorsoLean` sets how far the rider leans over the bars, and
  `Pose.TurnLean`, `Pose.HeadTurn` and the others shape the body.
- **Handling:** `MaxSpeed`, `Acceleration`, `SteerRate`, `MaxLean`,
  `WheelieAngle` and the suspension values.

The R6 default `Animate` script would fight the pose while seated, so it is
paused for the local rider while riding and turned back on when they get off.

## Optional: the clips in the Animation Editor

`RideAnims_R6.rbxmx` holds the same Blender clips as KeyframeSequences, named
`RideRide`, `RideTuck`, `RideBrake`, `RideLeanRight`, `RideLeanLeft` and
`RideWheelie`.

1. Insert the file into your R6 dummy (`Rig`), then move the sequences into a
   folder named `AnimSaves` inside the rig. Create the folder if it isn't there.
2. Open the Animation Editor, select the rig, and load them from the **...**
   menu.

RideKit doesn't need them. They're there in case you want to edit the clips or
publish them yourself.

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
