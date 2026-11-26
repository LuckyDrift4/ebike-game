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
  (see `run_pose_test.mjs`).
