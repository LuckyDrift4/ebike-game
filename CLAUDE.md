# Notes for working on this repo

## Roblox scripts the user pastes into Studio

- Paste-in scripts (`roblox/RideKit_Server.lua`, `roblox/RideKit_Client.lua`)
  must survive a copy that loses the start of the file. That has happened
  twice: it lost the first line and part of the second, and the user then
  deleted the broken top lines.
  - Never start with prose comment lines. Put setup instructions in the chat
    message or a README.
  - The files open with a line of 160 dashes, so any tail of it is still a
    comment.
  - Look up every service (`game:GetService(...)`) next to the code that uses
    it, not only at the top of the file.
  - `build_ridekit.py` generates the files this way. Check them by removing
    the first N characters and running StyLua `--check`.
- Never ask the user to paste a `.rbxmx` / `.rbxm` file into a script. Those
  are model files for **Insert from File**. Prefer the two paste-in scripts.
- The rider is an R6 avatar.
- The current bike model is `surron2.rbxm`, a chassis-kit layout:
  - `Misc > Wheel` is the handlebars.
  - `FrontSection` and `RearSection` each hold a `Wheel` part with `Parts` /
    `WheelFixed` inside.
  - `Misc > Step` holds the pegs.
  - The seat is `attachments_Mesh.002_zeus-web...`, found by its shape.
- `surron1.rbxm` must keep working too.
- `roblox/tests/bikes_data.luau` holds both models' part data. The tests check
  that parts are sorted correctly, that the right seat, pegs and grips are
  picked, and the pose on both bikes.
- After changing anything in `roblox/RideKit/`, regenerate the packages with
  `python roblox/build_ridekit.py` and run the Luau tests in `roblox/tests/`
  with `node roblox/tests/run_tests.mjs <test>.luau` (`rig_test`, `anim_test`,
  `physics_test`).

## Bike physics (`roblox/RideKit/Physics.lua`)

- It's real rigid-body physics on `RideKit_Chassis`, with no AlignOrientation.
  Every frame it applies impulses at the contact points:
  - suspension springs, solved implicitly;
  - tyre forces inside a friction circle;
  - the rider's lean;
  - the rider's pitch torques for wheelies, stoppies and air control.
- Suspension, tyres and lean are solved together in one Gauss-Seidel loop.
  Don't split them into separate passes: they fight across frames and the bike
  falls over.
- All the mass is in the chassis box. The rider is made massless while seated,
  so `Physics` computes the box inertia from `chassis.Size`. If the box size
  changes, change `Rig.chassisSize` and `Sim.bike` in `roblox/tests/sim.luau`
  together.
- Rider torques must not leak between axes on a pitched or leaned bike. Use
  `rollAxis` (square to the pitch axis) and `Physics:spin` for yaw.
- Brake and drive directions follow the ground slope (`gn`), not an edge's
  contact normal.
- `physics_test.luau` runs the real module in `sim.luau`, a rigid-body world
  with terrain, kerbs and walls. Every tuning change must keep all of its
  checks passing at 30, 60 and 144 fps.

## Rider animation

- **The user wants it made in Blender, not computed in code.** The clips are
  keyframed in `blender/anim/ride_anims.blend`, built by
  `blender/anim/make_ride_anims.py`. RideKit's `AnimPlayer` only plays and
  blends them. The blend weights come from the physics state. Don't bring back
  the old procedural `Pose` module.
- The rider always sits upright (`Pose.TorsoLean = 0`), like the user's
  reference photo: on the seat, legs straight to the pegs, hands on the grips.
  There's no tuck, no standing, no hanging into corners and no separate
  wheelie pose. The clips are Ride, Brake and LeanRight/LeanLeft (bars turned,
  head into the turn).
- Clips can still move the torso: an optional `pos` on a key is the RootJoint
  `Transform` position.
- No on-screen UI. The user asked for all of it to be removed. Keep the mobile
  Wheelie touch button.
- **Order of steps after rig changes:**
  1. `node roblox/tests/run_tests.mjs rig_test.luau`. This writes
     `blender/anim/bike_ref.json`.
  2. `blender --background --python blender/anim/make_ride_anims.py`.
  3. `python roblox/build_ridekit.py`.
  4. `node roblox/tests/run_tests.mjs anim_test.luau`. This checks the hands
     are on the grips in-game.
