# Notes for working on this repo

## Roblox scripts the user pastes into Studio

- Paste-in scripts (`roblox/RideKit_Server.lua`, `roblox/RideKit_Client.lua`)
  must start with code, never with prose comment lines. A copy that drops the
  start of a comment line leaves bare text, and the whole script fails to
  parse. Put setup instructions in the chat message or a README instead.
- Never ask the user to paste a `.rbxmx` / `.rbxm` file into a script. Those
  are model files for **Insert from File**. Prefer the two paste-in scripts.
- The rider is an R6 avatar. The bike model is `surron1.rbxm` (two invisible
  `Wheel` parts, `TripleTreeHinge`, `RearSwingArmHinge`).
- After changing anything in `roblox/RideKit/`, regenerate the packages with
  `python roblox/build_ridekit.py` and run the Luau tests in `roblox/tests/`
  (see `run_pose_test.mjs`).
