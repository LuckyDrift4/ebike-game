"""
Build the e-bike models, save .blend files, export FBX/GLB for Roblox and
render preview images.

Usage (Blender 4.2+ / 5.x):
    blender --background --python blender/build.py -- [surron] [varg] [--no-render]
               [--check-ref path/to/photo.png] [--samples N]
or with the `bpy` Python module:
    python blender/build.py surron varg

Outputs go to ../models/ and ../renders/ relative to this file.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import importlib  # noqa: E402

import bikekit as K  # noqa: E402

BIKES = ["surron", "surron_black", "varg"]
HDRI_ROT = 200.0   # backdrop rotation that puts the sunny square behind the hero camera


def parse(argv):
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = argv[1:]
    names = [a for a in argv if a in BIKES] or list(BIKES)
    opts = dict(render="--no-render" not in argv, check="--check" in argv, samples=64, only_check=False)
    if "--samples" in argv:
        opts["samples"] = int(argv[argv.index("--samples") + 1])
    if "--only-check" in argv:
        opts["only_check"] = True
        opts["check"] = True
    return names, opts


def build_one(name, opts):
    mod = importlib.import_module(name)
    K.reset_scene()
    B = K.Builder(mod.NAME)
    print(f"Building {mod.NAME} ...")
    mod.build(B)
    objs = B.finalize()
    os.makedirs(os.path.join(ROOT, "models"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "renders"), exist_ok=True)
    if not opts["only_check"]:
        objs_sorted = [o for o in B.objects]
        K.export(objs_sorted,
                 fbx_path=os.path.join(ROOT, "models", f"{mod.NAME}.fbx"),
                 glb_path=os.path.join(ROOT, "models", f"{mod.NAME}.glb"))

    # photographic scene: HDR backdrop + shadow catcher (kept in the .blend for re-rendering)
    scene = getattr(mod, "SCENE", {})
    hdri = os.path.join(HERE, "assets", scene.get("hdri", "san_giuseppe_bridge_2k.hdr"))
    hdri_rot = scene.get("rot", HDRI_ROT)
    if os.path.exists(hdri):
        K.setup_hdri(hdri, hdri_rot, 1.0, samples=opts["samples"])
    else:
        K.setup_outdoor(samples=opts["samples"])
    k = 1.12 if mod.NAME == "Varg" else 1.0   # bigger bike -> step back a little
    tgt = Vector((0, 0.0, 0.52 * k))
    side = mod.REF["camera_side"]
    cams = {
        "hero": K.camera("Cam_Hero", (2.35 * k, -2.05 * k, 0.9), tgt, lens=40, fstop=4.0),
        "front34": K.camera("Cam_Front34", (-1.95 * k, -2.15 * k, 1.05), tgt, lens=35, fstop=4.0),
        "rear34": K.camera("Cam_Rear34", (2.25 * k, 2.5 * k, 0.78), tgt, lens=38, fstop=4.0),
        "owner": K.camera("Cam_Owner", (-0.95 * k, -1.45 * k, 0.95), Vector((0.0, 0.05, 0.5 * k)), lens=24,
                          fstop=5.6),
        "detail": K.camera("Cam_Detail", (1.25 * k, -0.25 * k, 0.75), Vector((0, 0.05, 0.5 * k)), lens=40,
                           fstop=2.8),
        "side": K.camera("Cam_Side", (7.5 * k * side, 0.0, 0.62), (0, 0.0, 0.55 * k), lens=85),
    }
    ref = mod.REF
    # orthographic camera matching the reference photo framing for overlay checks
    s = ref["scale"]
    cy = (ref["center_px"][0] - ref["mid_x"]) * s * (1 if ref["camera_side"] > 0 else -1)
    cz = (ref["ground"] - ref["center_px"][1]) * s
    cx = 6.0 * ref["camera_side"]
    cams["check"] = K.camera("Cam_RefCheck", (cx, cy, cz), (0, cy, cz), ortho=ref["size"] * s)

    if not opts["only_check"]:
        import json
        rig = {}
        for k, v in mod.rig_points().items():
            rig[k] = [round(c, 4) for c in v] if hasattr(v, "__len__") else round(v, 4)
        rig["_axes"] = "Blender coords in metres: +X = bike's left, -Y = front, +Z = up, ground at Z=0"
        rig["meshes"] = {o.name: {"pivot": [round(c, 4) for c in o.location], "tris": len(o.data.polygons)}
                         for o in B.objects}
        with open(os.path.join(ROOT, "models", f"{mod.NAME}_rig.json"), "w") as f:
            json.dump(rig, f, indent=2)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "models", f"{mod.NAME}.blend"),
                                    compress=True)

    if opts["render"]:
        lean = pose_parked(B.objects)
        if lean:
            print(f"parked on the kick stand, leaning {lean:.1f} deg")
        outs = []
        if not opts["only_check"]:
            for key, res in [("hero", (1600, 1040)), ("side", (1600, 1040)), ("front34", (1600, 1040)),
                             ("rear34", (1600, 1040)), ("detail", (1600, 1040)), ("owner", (1200, 1600))]:
                p = os.path.join(ROOT, "renders", f"{mod.NAME}_{key}.jpg")
                K.aim_hdri(cams[key], hdri_rot)
                K.render(cams[key], p, res)
                outs.append(p)
        if opts["check"]:
            os.makedirs(os.path.join(ROOT, "renders", "_check"), exist_ok=True)
            p = os.path.join(ROOT, "renders", "_check", f"{mod.NAME}.png")
            bpy.context.scene.objects["Ground"].hide_render = True
            K.render(cams["check"], p, (ref["size"], ref["size"]))
            outs.append(p)
        print("rendered:", *outs, sep="\n  ")


class _MatRecorder:
    """Stand-in Builder that only records material definitions."""

    def __init__(self):
        self.mats = {}

    def material(self, key, rgb, metal=0.0, rough=0.5, coat=0.0, emit=0.0, spec=0.5, **_render_only):
        self.mats[key] = dict(rgb=rgb, metal=metal, rough=rough, emit=emit)


def write_roblox_colors():
    """Generate roblox/BikeColors.lua: colours + materials per mesh name suffix."""
    def srgb(c):
        c = max(0.0, min(1.0, c))
        v = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
        return int(round(v * 255))

    lines = ["-- Generated by blender/build.py. Do not edit by hand.",
             "-- ModuleScript: colours/materials for the imported bike MeshParts.",
             "-- Each MeshPart is named <Bike>_<Group>_<material>[n], e.g. SurRon_FrontWheel_rubber",
             "-- (big meshes are split into SurRon_Body_frame, SurRon_Body_frame2, ... to stay under 20k tris).",
             "--   local BikeColors = require(path.to.BikeColors)",
             "--   BikeColors.apply(workspace.SurRon)",
             "",
             "local BikeColors = {}", ""]
    for name in BIKES:
        mod = importlib.import_module(name)
        rec = _MatRecorder()
        mod.materials(rec)
        lines.append(f"BikeColors.{mod.NAME} = {{")
        for key, m in rec.mats.items():
            r, g, b = (srgb(c) for c in m["rgb"])
            if m["emit"] > 0:
                mat = "Neon"
            elif key in ("chrome",):
                mat = "Foil"
            elif m["metal"] >= 0.8:
                mat = "Metal"
            elif key in ("rubber", "grip", "seat"):
                mat = "Rubber"
            else:
                mat = "SmoothPlastic"
            refl = 0.35 if key == "chrome" else (0.1 if m["metal"] >= 0.8 else 0.0)
            lines.append(f"\t{key} = {{ color = Color3.fromRGB({r}, {g}, {b}), material = Enum.Material.{mat}, "
                         f"reflectance = {refl} }},")
        lines.append("}")
        lines.append("")
    lines += [
        "function BikeColors.apply(model: Instance)",
        "\tfor _, part in ipairs(model:GetDescendants()) do",
        "\t\tif part:IsA(\"MeshPart\") then",
        "\t\t\tlocal bike, _group, mat = string.match(part.Name, \"^(%w+)_(%w+)_(%a+)%d*$\")",
        "\t\t\tlocal t = bike and BikeColors[bike] and BikeColors[bike][mat]",
        "\t\t\tif t then",
        "\t\t\t\tpart.Color = t.color",
        "\t\t\t\tpart.Material = t.material",
        "\t\t\t\tpart.Reflectance = t.reflectance",
        "\t\t\tend",
        "\t\tend",
        "\tend",
        "end",
        "",
        "return BikeColors",
        ""]
    os.makedirs(os.path.join(ROOT, "roblox"), exist_ok=True)
    with open(os.path.join(ROOT, "roblox", "BikeColors.lua"), "w") as f:
        f.write("\n".join(lines))


def pose_parked(objs, deploy=(-100.0, -25.0, 0.0), max_lean=14.0):
    """For renders only: swing the kick stand down and lean the bike onto it
    (the saved .blend / FBX keep the upright riding pose)."""
    ks = [o for o in objs if o.get("group") == "Kickstand"]
    if not ks:
        return 0.0
    root = bpy.data.objects.new("BikeRoot", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        o.parent = root
    for o in ks:
        o.rotation_euler = tuple(math.radians(a) for a in deploy)
    lean = 0.0
    for i in range(0, int(max_lean * 4) + 1):
        lean = i * 0.25
        root.rotation_euler = (0.0, math.radians(lean), 0.0)
        bpy.context.view_layer.update()
        mz = min((o.matrix_world @ v.co).z for o in ks for v in o.data.vertices)
        if mz <= 0.002:
            break
    return lean


def main():
    names, opts = parse(sys.argv)
    for n in names:
        build_one(n, opts)
    write_roblox_colors()


if __name__ == "__main__":
    main()
