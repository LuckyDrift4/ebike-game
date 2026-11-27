# RideKit: make the Sur-Ron rideable (R6)

`RideKit.rbxmx` is a folder of scripts you drop inside a bike model. It turns
the static, anchored bike into a rideable one:

- **Physics:** a real dirt-bike model, not a scripted glide.
  - Each wheel has its own spring and damper: the fork dives under braking and
    the rear squats under power.
  - The tyres grip by load and by surface (asphalt, grass, dirt, sand, mud,
    snow, ice). Ask too much of them and they slide.
  - Steering turns the front wheel. The bike leans exactly as far as the turn
    needs, the lean you'd see in real life.
  - Round wheels roll up kerbs. Jumps fly on real ballistics, and in the air
    the rider lines the bike up with the landing.
- **Wheelies and stoppies:** they use a real balance point.
  - Hold E with the throttle (while moving) and the front eases up to about 38
    degrees (`WheelieAngle`) and holds there. Letting off the throttle or E
    lowers it, and the rear brake (S) brings it down. A big bump or landing can
    still take it over, and you loop it and get thrown off.
  - Brake hard (S) at speed and the rear wheel lifts into a stoppie: a little
    at low speed, up to about 30 degrees when you were going fast.
- **Crashes:** off by default. Looping a wheelie (or landing upside down) still
  throws you off. A fallen bike: walk up and press E to pick it up.
  `Crashes = true` adds lowsides, wall hits and going over the bars.
- **Moving parts:** the wheels spin (and lock or spin up), the bars turn, the
  front fork slides and the swingarm moves with the suspension.
- **Rider animation:** made in Blender (`blender/anim/ride_anims.blend`).
  The rider sits upright on the seat, with legs straight down and a little
  forward and hands on the grips. The keyframed R6 clips are: riding, braced on the brakes, bars turned
  left and right (the head looks into the turn), and the wheelie (slid back,
  arms straight). RideKit plays the
  Blender keyframes and blends them by what the bike is doing. Every client
  plays them, so nothing needs uploading.

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

## Easiest set-up: one script, pasted in two places

`roblox/RideKit.lua` is a single script that goes in **both** places. It works
out where it's running and does the bike's part or the player's part.

1. Delete any RideKit scripts you made earlier (the old `RideKit_Server` and
   `RideKit_Client` code, or anything starting with `<roblox`).
2. In the Explorer, hover over the bike **Model** (the one with the two
   `Wheel` parts), click **+** and add a **Script** (a normal Script). Delete
   the `print("Hello world!")` line and paste **all** of `roblox/RideKit.lua`.
3. Open **StarterPlayer > StarterPlayerScripts**, click **+** and add a
   **LocalScript**. Paste **all** of the same `roblox/RideKit.lua` into it.
4. Press **Play**, walk to the bike and press **E**.

If the Script ends up somewhere other than inside the bike, the Output says
where it is and where it should go.

When you press Play, the Output shows `RideKit <version>: bike script running`
and `RideKit <version>: player script running`. The two versions must match.
If one copy is older, you get a warning saying so. Paste the newest file into
both.

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
| Wheelie (hold, with throttle, while moving) | E | X | Wheelie button |
| Stoppie | S at speed | left trigger at speed | thumbstick back at speed |
| Get off | Space | A | Jump button |

**Wheelies:**
- Hold E and the throttle: it eases up to about 38 degrees and holds. Let off
  to come down. S (rear brake) drops it fast.
- The balance point is about 45 degrees. A big bump or landing near it can
  loop it.
- `WheelieAssist = true` makes the rider cover the rear brake so it can never
  loop.
- A/D lean it round gently.

## Tuning

The rider is placed automatically:
- **Hands:** aimed at the ends of the handlebar, so they follow the bars when
  you steer.
- **Feet:** aimed at the foot pegs.
- **Height:** the rider sits just low enough for the feet to reach the pegs.
- **Head:** looks down the road and into corners.

The Output line `Grips from "...", pegs from "..."` shows which parts were
used. To adjust things, open `RideKit > Config` (or the top of the server
script). The comments there explain each value. The ones you'll most likely
change:

- **Motor:** `MaxSpeed`, `Acceleration`.
- **Brakes:** `FrontBrake`, `RearBrake`.
- **Grip:** `Grip` multiplies every surface's grip. Knobbly tyres grip on
  dirt, grass, sand and snow; only ice is really slippery. The brakes and
  motor never use more than 80% of the grip, so the tyres don't lock up or spin
  out. `SlideGrip` sets how slippery a sliding tyre gets.
- **Handling:** `MaxLean`, `MaxSteerAngle`, `SteerSpeed`.
- **Suspension:** `SuspensionTravel`, `SpringRate`, `Damping`,
  `ReboundDamping`.
- **Wheelie:**
  - `WheelieAssist` turns the loop protection on or off.
  - `WheelieAimUp` and `WheelieAimDown` set how fast the front rises and falls.
  - `WheelieSweetSpot` sets how far below the balance point the assist holds
    you.
- **Air:** all manual by default. E pulls the nose up, the throttle spins the
  rear wheel up (nose up) and the brake stops it (nose down). `AirAssist = true`
  makes the rider line up for landings.
- **Stoppies:** `StoppieOnBrake`, `StoppieMinSpeed`, `StoppieFullSpeed`,
  `StoppieAngle`, and `StoppieDecel` (lower makes it roll longer on the front).
  They only start when you brake hard going straight.
- **Wheelie height:** `WheelieAngle`.
- **Crashes:** `Crashes = true` turns on all crashes. `LoopCrash = false`
  stops looping a wheelie from throwing you off. `CrashLean` and `CrashImpact`
  set how hard you have to go before you come off.
- **Reverse:** `ReverseSpeed` (0 = none).
- **Rider position:** `SeatForward` slides the rider toward the bars.
  `SeatHeight` is `"auto"` or a fixed number.
- **Hands and feet:** `GripInset` and `PegInset` move them inwards from the
  ends of the bar and pegs.

The R6 default `Animate` script would fight the pose while seated, so it is
paused for the local rider while riding and turned back on when they get off.

## Optional: the clips in the Animation Editor

`RideAnims_R6.rbxmx` holds the same Blender clips as KeyframeSequences, named
`RideRide`, `RideBrake`, `RideLeanRight`, `RideLeanLeft` and `RideWheelie`.

1. Insert the file into your R6 dummy (`Rig`), then move the sequences into a
   folder named `AnimSaves` inside the rig. Create the folder if it isn't there.
2. Open the Animation Editor, select the rig, and load them from the **...**
   menu.

RideKit doesn't need them. They're there in case you want to edit the clips or
publish them yourself.

## Notes

- **Seat:** the bike gets its own invisible `VehicleSeat` (`RideKit_Seat`),
  placed on the part whose name contains "seat".
- **Mass:** all the weight sits in the invisible `RideKit_Chassis` box, at the
  bike and rider's centre of mass. That box is also what hits walls. Every
  other part, and the rider while seated, is massless, so every avatar rides
  the same. Invisible `RideKit_WheelGuard` parts inside the wheels stop them
  going through walls and catch the bike when it falls over.
- **When parked:** the bike is anchored. When someone gets on, it unanchors and
  that player's client simulates it. When they get off, it rolls to a stop
  and parks again. Jump off at speed and it falls over instead.
- **R15 avatars:** they can ride too, but they use the default sit pose,
  because the riding animation is for R6.
- **Something moves wrong:** if a part spins or steers when it shouldn't,
  check the counts in the Output. You can rename the part, since parts with
  "fork", "handlebar" or "lever" in the name steer, and "swingarm", "chain" or
  "mudguard" behind the pivot move with the swingarm. Or send me a screenshot.
- **Tests:** the physics is tested outside Roblox in a small rigid-body world
  (`roblox/tests/sim.luau`, `physics_test.luau`):
  - **Basics:** settling, top speed, braking, cornering lean at three speeds
    and three frame rates.
  - **Surfaces:** ice, sand and mud.
  - **Wheelies:** assisted, unassisted, looping out, saving it with the rear
    brake, steering one, and one at 30 fps.
  - **Stoppies:** on S, growing with speed, none at low speed.
  - **Jumps and air control:** manual and assisted.
  - **Terrain:** hills, bumps, kerbs, drops, a wall and a 30° descent.
