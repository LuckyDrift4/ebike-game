# R6 riding animations (Blender)

`make_ride_anims.py` builds `ride_anims.blend`. That file holds an R6 rider rig
on the surron2 bike and five keyframed clips on one timeline. The rider sits
upright on the seat, feet on the pegs and hands on the grips. In a wheelie they
slide back on the seat with their arms straight.

| Clip | Frames | Used when |
|---|---|---|
| Ride | 1–61 (loop) | always, as the base |
| Brake | 81–111 | braking and stoppies (braced on the bars) |
| LeanRight / LeanLeft | 131–161 / 181–211 | the bars turn: hands follow the grips, head looks into the turn |
| Wheelie | 231–261 | front wheel up: slid back on the seat, arms straight, body upright to the road |

How the rig is set up:
- **Bones:** they match Roblox's R6 joints exactly. Each bone's rest pose is the
  joint frame (`Part0 * C0`), and a bone's pose rotation is the joint's
  `Motor6D.Transform`.
- **Rider position:** the rider sits where RideKit seats them. `bike_ref.json`
  is exported by `roblox/tests/rig_test.luau`.
- **Hands, feet and head:** Damped Track constraints aim the arms at the
  `Aim Right Arm` / `Aim Left Arm` empties next to the grips, and the grips turn
  with the `SteerPivot` empty. The legs aim at the steps and the head looks at
  the `LookAt` empty.
- **Torso:** it is keyframed by hand. The keys were chosen so the hands land on
  the grips, within 0.07 studs, checked in `roblox/tests/anim_test.luau`.
- **Torso position:** a torso key can also have a location (the RootJoint
  `Transform` position). It's exported as `pos` and RideKit plays it. The
  Wheelie clip uses it to slide the hips back along the seat.

To rebuild everything from scratch:

```bash
blender --background --python blender/anim/make_ride_anims.py
```

The same command with a preview video added (`renders/ride_anims_preview.mp4`):

```bash
blender --background --python blender/anim/make_ride_anims.py -- --render
```

To edit by hand, open `ride_anims.blend`, change keys, save, then export only:

```bash
blender --background blender/anim/ride_anims.blend --python blender/anim/make_ride_anims.py -- --export-only
```

```bash
python roblox/build_ridekit.py
```

The export writes `roblox/anim/ride_anims.json`. `build_ridekit.py` turns it into
`RideKit/AnimData.lua`, which RideKit plays, and `RideAnims_R6.rbxmx` for the
Roblox Animation Editor.
