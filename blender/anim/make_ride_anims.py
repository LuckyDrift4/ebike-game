"""
Ride animations for an R6 rider on the surron2 bike, made in Blender.

    blender --background --python blender/anim/make_ride_anims.py [-- --render]

Builds (in blender/anim/ride_anims.blend):
  * an R6 rig whose bones are exactly Roblox's R6 Motor6D joints
    (bone rest = joint frame Part0 * C0, bone pose rotation = Motor6D.Transform),
    seated where RideKit seats the rider (bike_ref.json, exported by the tests)
  * empties for the grips (on a steering pivot, so they turn with the bars),
    the foot steps, and a look-at target
  * Damped Track constraints: arms -> grips, legs -> steps, head -> look-at
  * keyframed torso / look-at / steering for each clip on one timeline:
      Ride (loop) | Brake | LeanRight | LeanLeft | Wheelie
    The rider sits upright on the seat (the pose the user asked for), legs straight down
    and a little forward, hands on the grips. In a wheelie they slide back on the seat, arms straight, body
    upright to the road and eyes level.
The constrained pose is sampled ("visual keying") and written to
roblox/anim/ride_anims.json as Roblox joint rotations, which RideKit plays and
build_ridekit.py turns into Animation Editor KeyframeSequences.
Optional --render writes a preview video to renders/ride_anims_preview.mp4.

Tweaking by hand: open ride_anims.blend in Blender, change the Torso keys, the
LookAt / Aim empties or the timing, save, then re-export without rebuilding:
    blender --background blender/anim/ride_anims.blend --python blender/anim/make_ride_anims.py -- --export-only
and run `python roblox/build_ridekit.py` to put the new clips into RideKit.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
REF = json.load(open(os.path.join(HERE, "bike_ref.json")))
FPS = 30

# Roblox (Y up, -Z forward) -> Blender (Z up) axes, and recentre on the bike
P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
ORIGIN = Matrix.Translation(-Vector(REF["chassis"]["p"]))


def rbx_cf(d):
    r, p = d["r"], d["p"]
    return Matrix(((r[0], r[1], r[2], p[0]), (r[3], r[4], r[5], p[1]), (r[6], r[7], r[8], p[2]), (0, 0, 0, 1)))


def cf_new(x, y, z, *r):
    return Matrix(((r[0], r[1], r[2], x), (r[3], r[4], r[5], y), (r[6], r[7], r[8], z), (0, 0, 0, 1)))


def to_b(M):
    """Roblox world frame -> Blender world frame (same local axes)."""
    return P @ ORIGIN @ M


def pt(v):
    return (P @ ORIGIN @ Vector((v[0], v[1], v[2], 1.0))).to_3d()


# --- R6 joints (Roblox defaults) -----------------------------------------------------
R6 = {  # bone (= Part1) : (parent bone, C0, C1)
    "Torso": ("HumanoidRootPart", cf_new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf_new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Head": ("Torso", cf_new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), cf_new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)),
    "Right Arm": ("Torso", cf_new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf_new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Arm": ("Torso", cf_new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf_new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
    "Right Leg": ("Torso", cf_new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), cf_new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)),
    "Left Leg": ("Torso", cf_new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), cf_new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)),
}
ORDER = ["Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]
SIZES = {"Torso": (2, 2, 1), "Head": (1.2, 1.2, 1.2), "Right Arm": (1, 2, 1), "Left Arm": (1, 2, 1),
         "Right Leg": (1, 2, 1), "Left Leg": (1, 2, 1)}

HRP = rbx_cf(REF["hrp"])
CHASSIS = rbx_cf(REF["chassis"])
FWD = (CHASSIS.to_3x3() @ Vector((0, 0, -1))).normalized()   # roblox
RIGHT = (CHASSIS.to_3x3() @ Vector((1, 0, 0))).normalized()
UP = (CHASSIS.to_3x3() @ Vector((0, 1, 0))).normalized()


def rest_frames():
    """Roblox world joint frames (Part0 * C0) and part frames at rest."""
    joint, part = {}, {"HumanoidRootPart": HRP}
    for name in ORDER:
        par, c0, c1 = R6[name]
        joint[name] = part[par] @ c0
        part[name] = joint[name] @ c1.inverted()
    return joint, part


def torso_rotation(lean, roll=0.0, twist=0.0):
    """Motor6D.Transform for RootJoint giving the torso this lean (forward +),
    roll (into a right turn +) and twist (shoulders to the right +), HRP-relative."""
    local = (Matrix.Rotation(-twist, 4, "Y") @ Matrix.Rotation(-roll, 4, "Z") @ Matrix.Rotation(-lean, 4, "X"))
    c0, c1 = R6["Torso"][1], R6["Torso"][2]
    T = c0.to_3x3().inverted() @ local.to_3x3() @ c1.to_3x3()
    return T.to_quaternion()


def stand_offset(forward, up):
    """RootJoint Transform translation that moves the torso this far forward / up
    (studs, along the HumanoidRootPart's axes). The joint frame's y is the HRP's +Z
    (back) and its z is the HRP's +Y (up)."""
    return Vector((0.0, -forward, up))


def torso_matrix(q_torso, t=None):
    par, c0, c1 = R6["Torso"]
    T = Matrix.Translation(t if t is not None else Vector((0, 0, 0)))
    return HRP @ c0 @ T @ q_torso.to_matrix().to_4x4() @ c1.inverted()


def shoulder_points(q_torso, t=None):
    """World (Roblox) shoulder/hip joint positions for a RootJoint rotation (+ translation)."""
    torso = torso_matrix(q_torso, t)
    return {n: (torso @ R6[n][1]).translation for n in ("Right Arm", "Left Arm", "Right Leg", "Left Leg")}


# --- scene ----------------------------------------------------------------------------
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    return sc


def empty(name, M, parent=None, size=0.15, shape="SPHERE"):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = shape
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    e.matrix_world = M
    e.rotation_mode = "QUATERNION"
    return e


def material(name, rgb, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    if m.node_tree is None:
        m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def box_obj(name, size, mat, bevel=0.04):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=2, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def build_rig():
    joint, part = rest_frames()
    arm_data = bpy.data.armatures.new("R6")
    arm = bpy.data.objects.new("R6_Rider", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones.new("HumanoidRootPart")
    eb.head, eb.tail = (0, 0, 0), (0, 0.6, 0)
    eb.matrix = to_b(HRP)
    for name in ORDER:
        b = arm_data.edit_bones.new(name)
        b.head, b.tail = (0, 0, 0), (0, 0.8, 0)
        b.matrix = to_b(joint[name])
        b.parent = arm_data.edit_bones[R6[name][0]]
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")

    # R6 body parts, parented to their bones
    skin = material("Skin", (0.95, 0.78, 0.6), 0.6)
    shirt = material("Shirt", (0.62, 0.74, 0.92), 0.7)
    pants = material("Pants", (0.07, 0.09, 0.16), 0.85)
    dark = material("Face", (0.03, 0.03, 0.03), 0.4)
    mats = {"Torso": shirt, "Head": skin, "Right Arm": shirt, "Left Arm": shirt, "Right Leg": pants, "Left Leg": pants}
    bpy.context.view_layer.update()
    for name in ORDER:
        ob = box_obj(name, SIZES[name], mats[name], 0.08 if name == "Head" else 0.04)
        pb = arm.pose.bones[name]
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = name
        ob.matrix_parent_inverse = (arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))).inverted()
        ob.matrix_basis = to_b(part[name])
        if name in ("Right Arm", "Left Arm"):  # hands
            h = box_obj(name + " Hand", (1.02, 0.35, 1.02), skin)
            h.parent = ob
            h.matrix_parent_inverse = Matrix()
            h.location = (0, -0.84, 0)  # roblox local -Y (bottom of the arm)
        if name in ("Right Leg", "Left Leg"):  # shoes
            s = box_obj(name + " Shoe", (1.04, 0.3, 1.04), dark)
            s.parent = ob
            s.matrix_parent_inverse = Matrix()
            s.location = (0, -0.86, 0)
        if name == "Head":  # face on the head's front (roblox local -Z)
            for dx in (-0.22, 0.22):
                e = box_obj("Eye", (0.12, 0.2, 0.05), dark, 0)
                e.parent = ob
                e.matrix_parent_inverse = Matrix()
                e.location = (dx, 0.12, -0.61)
            mo = box_obj("Mouth", (0.42, 0.06, 0.05), dark, 0)
            mo.parent = ob
            mo.matrix_parent_inverse = Matrix()
            mo.location = (0, -0.2, -0.61)
    return arm, joint


def build_targets(joint):
    steer = empty("SteerPivot", to_b(rbx_cf(REF["steerPivot"])), size=0.4, shape="ARROWS")
    targets = {}
    # grips ride on the steering pivot; the limbs aim at "Aim" empties next to them (keyed
    # per clip by aim_points(), since the hand / foot sits 0.5 off the limb's axis)
    for name, key, parent in (("Right Arm", "gripR", steer), ("Left Arm", "gripL", steer),
                              ("Right Leg", "pegR", None), ("Left Leg", "pegL", None)):
        g = Vector(REF[key])
        empty(key, Matrix.Translation(pt(g)), parent, 0.12)
        targets[name] = empty("Aim " + name, Matrix.Translation(pt(g)), None, 0.06, "PLAIN_AXES")
    look = empty("LookAt", Matrix.Translation(pt(Vector(REF["hrp"]["p"]) + FWD * 12 + UP * 0.6)), None, 0.3, "CUBE")
    return steer, targets, look


def add_constraints(arm, targets, look):
    for name, tgt in targets.items():
        c = arm.pose.bones[name].constraints.new("DAMPED_TRACK")
        c.target = tgt
        c.track_axis = "TRACK_NEGATIVE_Y"  # limbs hang along -Y of their joint frame
    c = arm.pose.bones["Head"].constraints.new("DAMPED_TRACK")
    c.target = look
    c.track_axis = "TRACK_NEGATIVE_Y"  # the face looks along -Y of the neck joint frame


def aim_points(steer_angle, q_torso, t=None):
    """Roblox-space aim point for each limb: the hand sits 0.5 outboard of the arm's
    axis and the foot 0.5 inboard of the leg's, along the torso's right vector, so aim
    the axis 0.5 the other way of the (steered) grip / step."""
    torso = torso_matrix(q_torso, t)
    rt = (torso.to_3x3() @ Vector((1, 0, 0))).normalized()
    spv = rbx_cf(REF["steerPivot"])
    rot = spv @ Matrix.Rotation(-steer_angle, 4, "Y") @ spv.inverted()
    gR = (rot @ Vector(REF["gripR"]).to_4d()).to_3d()
    gL = (rot @ Vector(REF["gripL"]).to_4d()).to_3d()
    # legs: straight down from the hips, a little forward (the user's reference photo), and
    # out to the sides so the feet sit over the pegs - either side of the bike, not through it.
    # (The foot is 0.5 inboard of the leg's joint axis, so the axis aims 0.5 further out.)
    down = -UP * math.cos(LEG_ANGLE) + FWD * math.sin(LEG_ANGLE)
    centre = CHASSIS.translation

    def leg_aim(hip, peg, side):
        aim = hip + down * 2.0
        out = (Vector(peg) - centre).dot(RIGHT) + side * (0.5 + LEG_SPREAD)  # wanted, across the bike
        return aim + RIGHT * (out - (aim - centre).dot(RIGHT))

    hR = (torso @ R6["Right Leg"][1]).translation
    hL = (torso @ R6["Left Leg"][1]).translation
    return {"Right Arm": gR - rt * 0.5, "Left Arm": gL + rt * 0.5,
            "Right Leg": leg_aim(hR, REF["pegR"], 1), "Left Leg": leg_aim(hL, REF["pegL"], -1),
            "gripR": gR, "gripL": gL}


HAND_REACH = math.hypot(0.5, 1.5)  # shoulder joint -> hand centre on an R6 arm
LEG_REACH = math.hypot(0.5, 2.0)  # hip joint -> foot centre on an R6 leg
LEG_ANGLE = math.radians(14)  # legs hang straight down from the hips, tilted this far forward
LEG_SPREAD = 0.1  # feet this much further out than the pegs (studs), clear of the bike


def best_lean(lean0, steer_angle, roll=0.0, twist0=0.0, lean_range=(-0.6, 1.0), w_lean=0.15):
    """Lean (and a small shoulder twist) that puts both arm aim points at arm's length
    from the shoulders, preferring a lean near lean0. Like an animator nudging the torso
    until the hands meet the bars."""
    best = None
    for i in range(int((lean_range[1] - lean_range[0]) / 0.01) + 1):
        lean = lean_range[0] + i * 0.01
        for k in range(-25, 26):
            tw = twist0 + k * 0.02
            q = torso_rotation(lean, roll, tw)
            sp = shoulder_points(q)
            g = aim_points(steer_angle, q)
            # the hand touches the grip only if the grip is exactly arm's reach from the shoulder
            eR = (g["gripR"] - sp["Right Arm"]).length - HAND_REACH
            eL = (g["gripL"] - sp["Left Arm"]).length - HAND_REACH
            cost = eR * eR + eL * eL + w_lean * (lean - lean0) ** 2 + 0.02 * (tw - twist0) ** 2
            if best is None or cost < best[0]:
                best = (cost, lean, tw)
    return best[1], best[2]


def best_seated(lean0, slide_range=(-0.9, 0.2), lean_span=0.5, w_lean=0.4, steer_angle=0.0):
    """Sitting, but free to slide along the seat (RootJoint position, hips stay on the seat):
    the lean nearest lean0 and the slide where both hands land exactly on the grips,
    with the feet as near the pegs as straight R6 legs allow."""
    best = None
    for i in range(int(2 * lean_span / 0.02) + 1):
        lean = lean0 - lean_span + i * 0.02
        q = torso_rotation(lean)
        for j in range(int((slide_range[1] - slide_range[0]) / 0.025) + 1):
            f = slide_range[0] + j * 0.025
            t = stand_offset(f, 0.0)
            sp = shoulder_points(q, t)
            g = aim_points(steer_angle, q, t)
            eR = (g["gripR"] - sp["Right Arm"]).length - HAND_REACH
            eL = (g["gripL"] - sp["Left Arm"]).length - HAND_REACH
            lR = (Vector(REF["pegR"]) - sp["Right Leg"]).length - LEG_REACH
            lL = (Vector(REF["pegL"]) - sp["Left Leg"]).length - LEG_REACH
            leg = sum((e * e if e > 0 else 0.3 * e * e) for e in (lR, lL))  # dangling short is worse
            cost = 6 * (eR * eR + eL * eL) + 0.5 * leg + w_lean * (lean - lean0) ** 2 + 0.05 * f * f
            if best is None or cost < best[0]:
                best = (cost, lean, f)
    return best[1], best[2]


# --- clips ----------------------------------------------------------------------------
STEER_ANIM = 0.24  # bars turned this much (rad) in the lean clips (matches RideKit MaxSteerAngle)
CLIPS = [
    # name, start frame, length (frames), loop
    ("Ride", 1, 60, True),
    ("Brake", 81, 30, True),
    ("LeanRight", 131, 30, True),
    ("LeanLeft", 181, 30, True),
    ("Wheelie", 231, 30, True),
]
WHEELIE_PITCH = math.radians(38)  # how far the bike is pitched up in a held wheelie (Config.WheelieAngle)
UPRIGHT = 0.0  # torso lean while sitting (0 = straight up); RideKit's Config.Pose.TorsoLean


def key_torso(arm, frame, q, t=None):
    pb = arm.pose.bones["Torso"]
    pb.rotation_quaternion = q
    pb.keyframe_insert("rotation_quaternion", frame=frame)
    pb.location = t if t is not None else Vector((0, 0, 0))  # = RootJoint Transform position
    pb.keyframe_insert("location", frame=frame)


def key_obj(ob, frame, loc=None, rot=None):
    if loc is not None:
        ob.location = loc
        ob.keyframe_insert("location", frame=frame)
    if rot is not None:
        ob.rotation_quaternion = rot
        ob.keyframe_insert("rotation_quaternion", frame=frame)


def animate(arm, steer, look, targets):
    base_rest = steer.rotation_quaternion.copy()
    look_rest = look.location.copy()
    hrp_p = Vector(REF["hrp"]["p"])

    def look_at(ahead=12.0, side=0.0, height=0.6):
        g = hrp_p + FWD * ahead + RIGHT * side + UP * height
        w = pt(g)
        return w

    def steer_rot(angle):
        # SteerPivot's local Y is the steering axis; turning right = -angle about it
        return base_rest @ Quaternion((0, 1, 0), -angle)

    report = {}

    def pose_at(frame, lean, roll, tw, steer_angle, t=None):
        q = torso_rotation(lean, roll, tw)
        key_torso(arm, frame, q, t)
        key_obj(steer, frame, rot=steer_rot(steer_angle))
        for name, p in aim_points(steer_angle, q, t).items():
            if name in targets:
                key_obj(targets[name], frame, loc=pt(p))

    # Ride: sat upright on the seat, gentle breathing and a look around (loop)
    lean, tw = best_lean(UPRIGHT, 0.0, w_lean=0.3)
    report["Ride"] = (lean, tw)
    s, n = CLIPS[0][1], CLIPS[0][2]
    for f, (dl, look_side, look_h) in zip((0, 15, 30, 45, 60),
                                           ((0, 0, 0.6), (0.02, 0.8, 0.5), (0, 0, 0.7), (0.02, -0.8, 0.5), (0, 0, 0.6))):
        l2, t2 = best_lean(lean + dl, 0.0, w_lean=0.3)
        pose_at(s + f, l2, 0, t2, 0.0)
        key_obj(look, s + f, loc=look_at(side=look_side, height=look_h))

    # Brake: still sat, braced on the bars, a touch back, eyes ahead
    lean, tw = best_lean(UPRIGHT - 0.08, 0.0, w_lean=0.3)
    report["Brake"] = (lean, tw)
    s = CLIPS[1][1]
    for f in (0, 30):
        pose_at(s + f, lean, 0, tw, 0.0)
        key_obj(look, s + f, loc=look_at(height=0.2))

    # Bars turned: the body stays with the bike (no hanging off), the shoulders follow the
    # bars just enough for the hands to stay on the grips, and the head looks into the turn
    for idx, sign in ((2, 1), (3, -1)):
        lean, tw = best_lean(UPRIGHT, sign * STEER_ANIM, twist0=sign * 0.1, w_lean=0.3)
        report[CLIPS[idx][0]] = (lean, tw)
        s = CLIPS[idx][1]
        for f in (0, 30):
            pose_at(s + f, lean, 0, tw, sign * STEER_ANIM)
            key_obj(look, s + f, loc=look_at(ahead=9.0, side=sign * 5.0, height=0.3))

    # Wheelie: slid back on the seat, arms pulled straight, the body leaning forward on the bike
    # so it stays fairly upright to the road, eyes level down the road
    lean, slide = best_seated(0.45)
    report["Wheelie"] = (lean, slide)
    s = CLIPS[4][1]
    level = -12.0 * math.tan(WHEELIE_PITCH)  # look target that's level with the road when pitched up
    for f, dl in ((0, 0.0), (15, 0.02), (30, 0.0)):
        l2, f2 = best_seated(lean + dl, slide_range=(slide - 0.2, slide + 0.2), lean_span=0.1, w_lean=2.0)
        pose_at(s + f, l2, 0, 0.0, 0.0, stand_offset(f2, 0.0))
        key_obj(look, s + f, loc=look_at(ahead=12.0, height=level))
    KEY_FRAMES["Wheelie"] = (0, 15, 30)

    for ob in [arm, steer, look] + list(targets.values()):
        ad = ob.animation_data
        if ad and ad.action:
            for fc in getattr(ad.action, "fcurves", []):
                for kp in fc.keyframe_points:
                    kp.interpolation = "BEZIER"
    return report


KEY_FRAMES = {"Ride": (0, 15, 30, 45, 60)}


def refine_hands(targets, iterations=6):
    """Nudge each arm's aim empty by whatever the hand still misses the grip by (Damped
    Track twists the arm a little when it bends far, moving the hand off its axis),
    re-keying it - what an animator does by eye. Runs per keyframe of every clip."""
    sc = bpy.context.scene
    worst = 0.0
    for name, start, length, loop in CLIPS:
        for f in KEY_FRAMES.get(name, (0, length)):
            for _ in range(iterations):
                sc.frame_set(start + f)
                for arm_name, grip in (("Right Arm", "gripR"), ("Left Arm", "gripL")):
                    hand = bpy.data.objects[arm_name].matrix_world @ Vector((0, -1, 0))
                    miss = hand - bpy.data.objects[grip].matrix_world.translation
                    aim = targets[arm_name]
                    aim.location = aim.location - miss
                    aim.keyframe_insert("location", frame=start + f)
            sc.frame_set(start + f)
            for arm_name, grip in (("Right Arm", "gripR"), ("Left Arm", "gripL")):
                hand = bpy.data.objects[arm_name].matrix_world @ Vector((0, -1, 0))
                worst = max(worst, (hand - bpy.data.objects[grip].matrix_world.translation).length)
    return worst


def sample_visual(arm, frame):
    """Constraint-evaluated local rotation of every bone (what 'visual keying' bakes),
    and the torso's translation (it moves off the seat when standing)."""
    bpy.context.scene.frame_set(frame)
    out, pos = {}, {}
    for name in ORDER:
        pb = arm.pose.bones[name]
        parent = pb.parent
        rest_local = parent.bone.matrix_local.inverted() @ pb.bone.matrix_local
        local = (parent.matrix @ rest_local).inverted() @ pb.matrix
        q = local.to_quaternion().normalized()
        out[name] = [round(q.x, 6), round(q.y, 6), round(q.z, 6), round(q.w, 6)]  # Roblox order
        t = local.translation
        if name == "Torso" and t.length > 1e-4:
            pos[name] = [round(t.x, 5), round(t.y, 5), round(t.z, 5)]
    return out, pos


def export(arm):
    clips = {}
    for name, start, length, loop in CLIPS:
        step = 3 if name == "Ride" else (15 if name == "Wheelie" else length)
        keys = []
        for f in range(0, length + 1, step):
            pose, pos = sample_visual(arm, start + f)
            key = {"t": round(f / FPS, 4), "pose": pose}
            if pos:
                key["pos"] = pos
            keys.append(key)
        clips[name] = {"length": round(length / FPS, 4), "loop": loop, "keys": keys,
                       "steer": STEER_ANIM if name == "LeanRight" else (-STEER_ANIM if name == "LeanLeft" else 0.0)}
    out = {"rig": "R6", "bike": REF["bike"], "fps": FPS, "joints": ORDER, "clips": clips,
           "note": "Motor6D.Transform rotations (x, y, z, w) sampled from blender/anim/ride_anims.blend"}
    os.makedirs(os.path.join(ROOT, "roblox", "anim"), exist_ok=True)
    with open(os.path.join(ROOT, "roblox", "anim", "ride_anims.json"), "w") as f:
        json.dump(out, f, indent=1)
    return out


def bake_copy(arm):
    """A constraint-free copy of the rig with the clips baked to keys (for FBX / editing)."""
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=1, frame_end=CLIPS[-1][1] + CLIPS[-1][2], only_selected=True, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={"POSE"})
    baked = arm.animation_data.action
    baked.name = "RideClips_Baked"
    bpy.ops.object.mode_set(mode="OBJECT")
    return baked


# --- bike stand-in for the preview --------------------------------------------------------
def stand_in(steer):
    black = material("Black", (0.02, 0.02, 0.022), 0.45)
    red = material("Red", (0.55, 0.03, 0.03), 0.3, 0.2)
    metal = material("Metal", (0.6, 0.6, 0.62), 0.3, 1.0)
    rubber = material("Rubber", (0.015, 0.015, 0.015), 0.9)
    objs = []

    def tube(a, b, r, mat, parent=None):
        a, b = pt(a), pt(b)
        d = b - a
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(a + b) / 2, vertices=20)
        o = bpy.context.object
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        o.data.materials.append(mat)
        if parent:
            bpy.context.view_layer.update()
            mw = o.matrix_world.copy()
            o.parent = parent
            o.matrix_parent_inverse = parent.matrix_world.inverted()
            o.matrix_world = mw
        objs.append(o)
        return o

    def wheel(c, r, parent=None):
        c3 = pt(c)
        bpy.ops.mesh.primitive_torus_add(major_radius=r - 0.17, minor_radius=0.17, location=c3, major_segments=48,
                                         minor_segments=12)
        t = bpy.context.object
        t.rotation_euler = (P.to_3x3() @ RIGHT).to_track_quat("Z", "Y").to_euler()
        t.data.materials.append(rubber)
        bpy.ops.mesh.primitive_torus_add(major_radius=r - 0.4, minor_radius=0.05, location=c3, major_segments=48,
                                         minor_segments=8)
        rim = bpy.context.object
        rim.rotation_euler = t.rotation_euler
        rim.data.materials.append(metal)
        for o in (t, rim):
            if parent:
                bpy.context.view_layer.update()
                mw = o.matrix_world.copy()
                o.parent = parent
                o.matrix_parent_inverse = parent.matrix_world.inverted()
                o.matrix_world = mw
            objs.append(o)
        for k in range(12):
            a = 2 * math.pi * k / 12
            dirv = FWD * math.cos(a) + UP * math.sin(a)
            tube(Vector(c), Vector(c) + dirv * (r - 0.42), 0.02, metal, parent)

    fa, ra = Vector(REF["frontAxle"]), Vector(REF["rearAxle"])
    sp = rbx_cf(REF["steerPivot"])
    head = sp.translation
    axis = (sp.to_3x3() @ Vector((0, 1, 0))).normalized()
    wheel(fa, REF["radF"], steer)
    wheel(ra, REF["radR"])
    for s in (-1, 1):
        tube(head + RIGHT * s * 0.32 - axis * 0.2, fa + RIGHT * s * 0.32, 0.11, black, steer)  # forks
    tube(Vector(REF["gripL"]) + RIGHT * 0.25, Vector(REF["gripR"]) - RIGHT * 0.25, 0.07, black, steer)  # bar
    for g, s in ((REF["gripL"], -1), (REF["gripR"], 1)):
        tube(Vector(g) - RIGHT * s * 0.35, Vector(g) + RIGHT * s * 0.05, 0.12, rubber, steer)  # grips
    tube(head - axis * 0.25, head + axis * 0.5, 0.17, red, steer)  # head tube / clamps
    piv = Vector(REF["swingPivot"])
    seat = rbx_cf(REF["seat"]["cf"])
    st = seat.translation
    tube(head, piv + UP * 0.9, 0.2, red)  # main frame
    tube(head - axis * 0.3, piv + FWD * 0.3, 0.16, red)
    tube(piv + UP * 0.9, st - FWD * 0.9 - UP * 0.05, 0.12, red)  # subframe
    for s in (-1, 1):
        tube(piv + RIGHT * s * 0.3, ra + RIGHT * s * 0.3, 0.1, red)  # swingarm
    tube(Vector(REF["pegL"]), Vector(REF["pegR"]), 0.07, metal)
    # seat and battery boxes
    ss = REF["seat"]["size"]
    o = box_obj("Seat", (ss[0], ss[1], ss[2]), black, 0.12)
    o.matrix_world = to_b(seat)
    objs.append(o)
    bat = box_obj("Battery", (0.62, 1.4, 1.2), black, 0.08)
    bat.matrix_world = to_b(Matrix.Translation((head + piv) / 2 + UP * 0.15) @ CHASSIS.to_3x3().to_4x4())
    objs.append(bat)
    return objs


def preview(arm, steer, look, objs):
    """Render the clips one after another on the stand-in bike."""
    sc = bpy.context.scene
    root = empty("BikeRoot", Matrix(), size=0.5, shape="PLAIN_AXES")
    bpy.context.view_layer.update()
    for o in list(objs) + [arm, steer, look] + [o for o in bpy.context.scene.objects if o.name.startswith(("grip", "peg", "Aim "))]:
        if o.parent is None and o is not root:
            mw = o.matrix_world.copy()
            o.parent = root
            o.matrix_parent_inverse = root.matrix_world.inverted()
            o.matrix_world = mw
    # lean / pitch the whole bike like the game does (preview only)
    ground = pt(Vector(REF["rearAxle"]) - UP * REF["radR"])
    rear_axle = pt(REF["rearAxle"])
    fwd_b = (P.to_3x3() @ FWD).normalized()
    right_b = (P.to_3x3() @ RIGHT).normalized()
    root.rotation_mode = "QUATERNION"

    front_ground = pt(Vector(REF["frontAxle"]) - UP * REF["radF"])

    def pose_root(frame, roll=0.0, pitch=0.0):
        pivot = ground + fwd_b * 2.5 if roll else (front_ground if pitch < 0 else rear_axle)
        R = (Matrix.Translation(pivot) @ Matrix.Rotation(roll, 4, fwd_b) @ Matrix.Rotation(pitch, 4, right_b)
             @ Matrix.Translation(-pivot))
        root.matrix_world = R
        root.keyframe_insert("location", frame=frame)
        root.keyframe_insert("rotation_quaternion", frame=frame)

    for name, start, length, loop in CLIPS:
        roll = {"LeanRight": -0.25, "LeanLeft": 0.25}.get(name, 0.0)
        pitch = WHEELIE_PITCH if name == "Wheelie" else 0.0
        pose_root(start, roll, pitch)
        pose_root(start + length, roll, pitch)
    # ground + light + camera
    bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, ground.z))
    g = bpy.context.object
    g.data.materials.append(material("Ground", (0.36, 0.37, 0.4), 0.9))
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(3)
    so = bpy.data.objects.new("Sun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0, math.radians(35))
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    if w.node_tree is None:
        w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.95, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.7
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = 32
    cam = bpy.data.objects.new("Cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    tgt = pt(Vector(REF["hrp"]["p"]) - UP * 1.2 + FWD * 0.6)
    for name, start, length, loop in CLIPS:
        for f, ang in ((start, -0.55), (start + length, -0.95)):
            pos = tgt + Matrix.Rotation(ang, 3, "Z") @ Vector((-9.5, 0, 0)) + Vector((0, 0, 2.6))
            cam.location = pos
            cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
            cam.keyframe_insert("location", frame=f)
            cam.keyframe_insert("rotation_euler", frame=f)
    sc.frame_start, sc.frame_end = 1, CLIPS[-1][1] + CLIPS[-1][2]
    sc.render.resolution_x, sc.render.resolution_y = 800, 500
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 10
    sc.frame_step = 2  # preview at 15 fps (timing unchanged)
    sc.render.fps = FPS // 2
    sc.cycles.use_denoising = True
    sc.cycles.device = "CPU"
    sc.view_settings.view_transform = "AgX"
    if hasattr(sc.render.image_settings, "media_type"):
        sc.render.image_settings.media_type = "VIDEO"
    sc.render.image_settings.file_format = "FFMPEG"
    sc.render.ffmpeg.format = "MPEG4"
    sc.render.ffmpeg.codec = "H264"
    sc.render.ffmpeg.constant_rate_factor = "HIGH"
    sc.render.filepath = os.path.join(ROOT, "renders", "ride_anims_preview.mp4")


def main():
    if "--export-only" in sys.argv:
        arm = bpy.data.objects["R6_Rider"]
        out = export(arm)
        print("re-exported", len(out["clips"]), "clips from the open .blend")
        return
    reset()
    arm, joint = build_rig()
    steer, targets, look = build_targets(joint)
    add_constraints(arm, targets, look)
    report = animate(arm, steer, look, targets)
    print("hands off the grips after refining (worst, studs): %.3f" % refine_hands(targets))
    out = export(arm)
    print("torso lean / twist (or lean / forward / up) per clip:", {k: tuple(round(x, 2) for x in v) for k, v in report.items()})
    print("exported", len(out["clips"]), "clips ->", os.path.join(ROOT, "roblox", "anim", "ride_anims.json"))
    objs = stand_in(steer)
    preview(arm, steer, look, objs)
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "ride_anims.blend"))
    if "--render" in sys.argv:
        bpy.ops.render.render(animation=True)
        print("rendered", bpy.context.scene.render.filepath)


if __name__ == "__main__":
    main()
