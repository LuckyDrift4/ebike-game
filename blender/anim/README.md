# R6 riding animations (Blender)

`make_ride_anims.py` builds `ride_anims.blend`. That file holds an R6 rider rig
on the surron2 bike and ten keyframed clips on one timeline. RideKit layers
them by what the bike is doing, so the weights come from the physics:

| Clip | Frames | Used when |
|---|---|---|
| Ride | 1–61 (loop) | always, as the base |
| Tuck | 81–111 | on the throttle |
| Brake | 131–161 | braking |
| LeanRight / LeanLeft | 181–211 / 231–261 | the bars turn (hands follow the grips) |
| Wheelie | 281–311 | front wheel up |
| Stand | 331–361 | in the air, holding Q (attack position) |
| Stoppie | 381–411 | rear wheel up on the brakes |
| HangRight / HangLeft | 431–461 / 481–511 | the bike leans into a corner |

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
- **Standing (Stand, Stoppie):** the torso also moves (its key has a location,
  which is the RootJoint `Transform` position). R6 legs can't bend, so it goes
  where both legs are exactly a leg's length from the pegs. The feet land on
  them within 0.06 studs, and the hands still reach the grips.

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
