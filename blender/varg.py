"""
Full-size electric motocross bike in the style of the Stark Varg MX.

Proportions were measured from a side-view reference photo (550 px square,
bike facing right, i.e. we see the bike's right side). Every (x, y) pair below
is a pixel in that photo, converted to metres with P(). Scale: 1480 mm
published wheelbase spans 300 px -> 4.93 mm per pixel, which also gives the
correct 21" front (80/100-21) and 19" rear (110/90-19) tyre diameters.

No brand logos or names are modelled.
"""

import math

from mathutils import Matrix, Vector

import bikekit as K
from surron import caliper  # same arc-caliper helper

NAME = "Varg"
REF = dict(size=550, scale=0.00493, center_px=(275, 275), mid_x=278, ground=401,
           camera_side=-1)  # photo shows the bike's right (-X) side

S = REF["scale"]
GROUND = REF["ground"]
MIDX = REF["mid_x"]


def P(x, y):
    """Photo pixel -> (Y, Z) metres. Image-right is the front (-Y)."""
    return (-(x - MIDX) * S, (GROUND - y) * S)


def P3(x, y, X=0.0):
    Y, Z = P(x, y)
    return Vector((X, Y, Z))


def L(pts):
    return [P(x, y) for (x, y) in pts]


def px_of(co):
    """World vertex -> photo pixel x (for width functions)."""
    return MIDX - co.y / S


def py_of(co):
    return GROUND - co.z / S


R_FRONT = 0.3467
R_REAR = 0.3403
FRONT_AXLE = Vector((0.0, P(428, 0)[0], R_FRONT))
REAR_AXLE = Vector((0.0, P(128, 0)[0], R_REAR))
SWING_PIVOT = P3(243, 300)

FORK_K = 0.455           # leg centre line x = 382.5 + 0.455 (y - 262)
LEG_X = 0.095
STEM_OFF = 0.022
ZF = Vector((0.0, FORK_K, 1.0)).normalized()
YF = Vector((0.0, ZF.z, -ZF.y))


def fa(y, X=0.0):
    return P3(382.5 + FORK_K * (y - 262), y, X)


def steer(y, X=0.0):
    return fa(y, X) + YF * STEM_OFF


def fork_frame(o):
    m = Matrix((Vector((1, 0, 0)), YF, ZF)).transposed().to_4x4()
    m.translation = o
    return m


def materials(B):
    B.material("red", (0.56, 0.012, 0.016), rough=0.22, coat=0.6)
    B.material("seat", (0.045, 0.045, 0.05), rough=0.78)
    B.material("tankcover", (0.025, 0.025, 0.03), rough=0.3, coat=0.4)
    B.material("black", (0.018, 0.018, 0.02), rough=0.45)
    B.material("battery", (0.032, 0.032, 0.036), rough=0.6)
    B.material("battrib", (0.06, 0.06, 0.066), metal=0.3, rough=0.45)
    B.material("frame", (0.02, 0.02, 0.022), metal=0.4, rough=0.35)
    B.material("rubber", (0.016, 0.016, 0.016), rough=0.88, spec=0.3)
    B.material("grip", (0.02, 0.02, 0.02), rough=0.8)
    B.material("rim", (0.03, 0.03, 0.035), metal=0.6, rough=0.3)
    B.material("hub", (0.56, 0.57, 0.6), metal=1.0, rough=0.3)
    B.material("spoke", (0.62, 0.63, 0.65), metal=1.0, rough=0.25)
    B.material("steel", (0.55, 0.56, 0.58), metal=1.0, rough=0.3)
    B.material("alu", (0.52, 0.53, 0.55), metal=1.0, rough=0.38)
    B.material("chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.08)
    B.material("gold", (0.80, 0.56, 0.22), metal=1.0, rough=0.2)
    B.material("stanchion", (0.035, 0.035, 0.04), metal=0.8, rough=0.15)
    B.material("cover", (0.84, 0.85, 0.87), metal=0.25, rough=0.25)
    B.material("plate", (0.74, 0.75, 0.77), rough=0.35)
    B.material("sprocket", (0.72, 0.52, 0.18), metal=1.0, rough=0.3)
    B.material("chain", (0.30, 0.30, 0.32), metal=1.0, rough=0.4)
    B.material("caliper", (0.05, 0.05, 0.055), metal=0.6, rough=0.35)
    B.material("spring", (0.03, 0.03, 0.033), metal=0.3, rough=0.5)
    B.material("screen", (0.02, 0.04, 0.06), metal=0.2, rough=0.05)
    B.material("redlight", (0.75, 0.02, 0.02), rough=0.2, emit=1.0)


# --------------------------------------------------------------------------- #
def build_wheels(B):
    mats = dict(rubber="rubber", rim="rim", spoke="spoke", hub="hub", axle="steel")
    K.build_wheel(B, "FrontWheel", FRONT_AXLE, rim_d=0.5334, tire_h=0.080, tire_w=0.088,
                  rim_w=0.040, hub_w=0.098, hub_r=0.03, flange_r=0.05, knob_pitch=0.05, mats=mats)
    K.build_wheel(B, "RearWheel", REAR_AXLE, rim_d=0.4826, tire_h=0.099, tire_w=0.112,
                  rim_w=0.052, hub_w=0.11, hub_r=0.034, flange_r=0.052, knob_pitch=0.052, mats=mats)
    K.build_rotor(B, "FrontWheel", "steel", FRONT_AXLE, -0.062, 0.130, 0.098, style="wave",
                  waves=12, holes=24, carrier_mat="alu", arms=6)
    K.build_rotor(B, "RearWheel", "steel", REAR_AXLE, -0.067, 0.110, 0.082, style="wave",
                  waves=10, holes=20, carrier_mat="alu", arms=5)
    rp = K.build_sprocket(B, "RearWheel", "sprocket", REAR_AXLE, +0.066, 50, 0.015875, thick=0.006, lighten=6)
    K.bm_cyl(B.bm("RearWheel", "hub"), K.wheel_matrix(REAR_AXLE), 0.05, 0.055, 0.063, segs=32)
    return rp


# --------------------------------------------------------------------------- #
def build_steering(B):
    G = "Steering"
    B.pivot(G, steer(192))
    fwd = -YF  # forward-up in the clamp plane
    for s in (1, -1):
        X = s * LEG_X
        K.bm_tube(B.bm(G, "gold"), fa(160, X), fa(268, X), 0.0305, segs=24)       # outer tube
        K.bm_tube(B.bm(G, "alu"), fa(151, X), fa(161, X), 0.022, segs=20)         # top cap
        K.bm_tube(B.bm(G, "rubber"), fa(266, X), fa(274, X), 0.0262, segs=24)     # seal
        K.bm_tube(B.bm(G, "stanchion"), fa(270, X), fa(328, X), 0.024, segs=24)   # stanchion
        # plastic fork guard wrapped round the front of the stanchion
        g0, g1 = fa(278, X) + fwd * 0.013, fa(322, X) + fwd * 0.013
        K.box_between(B.bm(G, "black"), g0, g1, 0.054, 0.03, up=tuple(fwd))
        K.bm_tube(B.bm(G, "black"), fa(318, X), fa(346, X), 0.03, segs=20)        # axle lug
        K.box_between(B.bm(G, "black"), fa(336, X), FRONT_AXLE + Vector((X, 0, 0)), 0.042, 0.04)
        K.bm_cyl(B.bm(G, "black"), K.axis_matrix(FRONT_AXLE + Vector((X, 0, 0)), (1, 0, 0)), 0.025, -0.02, 0.02, 18)
        for dz in (-0.014, 0.014):
            p = FRONT_AXLE + Vector((X + s * 0.02, 0.026, dz))
            K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(p, (s, 0, 0)), 0.0045, 0, 0.004, 6)
    clamp = K.rounded_rect2d(0, STEM_OFF / 2, 2 * LEG_X + 0.08, STEM_OFF + 0.08, 0.038, n=5)
    B.slab_frame(G, "frame", [clamp], 0.03, fork_frame(fa(168)), bevel=0.006)
    B.slab_frame(G, "frame", [clamp], 0.045, fork_frame(fa(216)), bevel=0.007)
    for y in (168, 216):
        for s in (1, -1):
            for dz in (-0.008, 0.008):
                p = fa(y, s * (LEG_X + 0.035)) + YF * 0.01 + ZF * dz
                K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(p, (s, 0, 0)), 0.0045, 0, 0.006, 6)

    # handlebar (MX bend, swept back) -------------------------------------------
    cb = P3(334, 156)
    half = [(0.0, 0.0, 0.0), (0.09, 0.006, 0.0), (0.16, 0.03, 0.024), (0.24, 0.062, 0.034),
            (0.32, 0.078, 0.036), (0.40, 0.085, 0.036)]

    def bar_at(x):
        sgn = 1 if x >= 0 else -1
        ax = abs(x)
        for (x0, y0, z0), (x1, y1, z1) in zip(half, half[1:]):
            if ax <= x1:
                t = (ax - x0) / (x1 - x0)
                return cb + Vector((sgn * ax, K.lerp(y0, y1, t), K.lerp(z0, z1, t)))
        x1, y1, z1 = half[-1]
        return cb + Vector((sgn * ax, y1, z1))

    full = [(-x, y, z) for (x, y, z) in reversed(half[1:])] + half
    K.bm_sweep(B.bm(G, "frame"), K.catmull([cb + Vector(p) for p in full], 6), 0.0112, segs=14)
    K.bm_tube(B.bm(G, "frame"), cb + Vector((-0.11, 0.004, 0.0)), cb + Vector((0.11, 0.004, 0.0)), 0.0145, segs=14)
    K.bm_box(B.bm(G, "black"), Matrix.Translation(cb + Vector((0, -0.005, 0.03))), 0.24, 0.018, 0.035)  # bar pad
    for s in (1, -1):
        K.bm_tube(B.bm(G, "grip"), bar_at(s * 0.265), bar_at(s * 0.40), 0.0168, segs=16)
        K.bm_tube(B.bm(G, "black"), bar_at(s * 0.40), bar_at(s * 0.407), 0.0175, segs=12)
        K.bm_tube(B.bm(G, "frame"), steer(168, s * 0.042) + ZF * 0.015, cb + Vector((s * 0.042, 0, -0.012)),
                  0.014, segs=12)
        K.bm_box(B.bm(G, "alu"), K.axis_matrix(cb + Vector((s * 0.042, 0, 0)), (1, 0, 0)), 0.036, 0.036, 0.03)
        mc = bar_at(s * 0.225)
        K.bm_tube(B.bm(G, "black"), mc + Vector((-s * 0.02, -0.014, 0)), mc + Vector((s * 0.03, -0.014, 0)),
                  0.0115, segs=12)
        K.bm_box(B.bm(G, "black"), Matrix.Translation(mc + Vector((-s * 0.006, -0.006, 0.027))), 0.036, 0.028, 0.02)
        K.box_between(B.bm(G, "alu"), mc + Vector((s * 0.03, -0.032, -0.004)),
                      bar_at(s * 0.38) + Vector((0, -0.05, -0.024)), 0.012, 0.007)
        K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(mc + Vector((s * 0.03, -0.032, -0.004)), (0, 0, 1)), 0.006,
                 -0.008, 0.008, 8)
    # twist throttle housing (right, -X)
    tp = bar_at(-0.255)
    K.bm_tube(B.bm(G, "black"), tp + Vector((0.012, 0, 0)), tp + Vector((-0.016, 0, 0)), 0.021, segs=16)
    # phone-style dash display facing the rider
    dc = cb + Vector((0, 0.018, 0.05))
    Md = K.axis_matrix(dc, (0, 0.74, 0.67), hint=(0, 1, 0))
    K.bm_box(B.bm(G, "black"), Md, 0.08, 0.13, 0.02)
    K.bm_box(B.bm(G, "screen"), Md @ Matrix.Translation((0, 0, 0.0105)), 0.068, 0.114, 0.002)
    K.box_between(B.bm(G, "black"), cb + Vector((0, 0.0, 0.012)), dc - Vector((0, 0.01, 0.0)), 0.03, 0.02)

    # front number plate: curved plate in front of the fork, between the clamps
    pc = steer(188) + fwd * 0.075
    Mp = Matrix((Vector((1, 0, 0)), ZF, fwd)).transposed().to_4x4()
    Mp.translation = pc
    plate = []
    for k in range(25):  # rounded shield, wider at the top
        a = math.pi * 2 * k / 24
        u, v = math.cos(a), math.sin(a)
        w = 0.115 if v > 0 else 0.115 - 0.03 * (-v)
        plate.append((w * (abs(u) ** 0.7) * (1 if u >= 0 else -1), 0.105 * (abs(v) ** 0.8) * (1 if v >= 0 else -1)))
    me = K.slab_mesh_frame([plate[:-1]], 0.005, Mp, bevel=0.002)

    def plate_curve(co):
        u = co.x / 0.115
        co.y += 0.045 * u * u
        return co
    K.deform_mesh(me, plate_curve)
    B.add_mesh(G, "plate", me)
    for s in (1, -1):
        K.box_between(B.bm(G, "black"), pc + Vector((s * 0.06, 0.03, 0.0)), fa(200, s * LEG_X), 0.01, 0.012)

    # front fender (red)
    ff = [(369, 202), (380, 202), (424, 204), (452, 215), (460, 220), (424, 212), (385, 214), (378, 215),
          (372, 215), (371, 206)]

    def fender_taper(co):
        x = px_of(co)
        w = K.lerp(0.075, 0.045, min(max((x - 370) / 90, 0), 1))
        co.x *= w / 0.075
        return co
    B.slab(G, "red", [L(ff)], 0.15, bevel=0.01, fn=fender_taper)

    # front caliper (right side) + hose
    cpos = caliper(B, G, FRONT_AXLE, -0.062, 0.130, math.radians(24), length=0.08)
    K.box_between(B.bm(G, "black"), cpos + Vector((-0.012, 0, 0)), fa(334, -LEG_X), 0.014, 0.034)
    hose = B.bm(G, "black")
    mc_r = bar_at(-0.225) + Vector((0, -0.02, -0.012))
    K.bm_sweep(hose, K.catmull([mc_r, cb + Vector((-0.15, -0.08, -0.05)), cb + Vector((-0.12, -0.15, -0.14)),
                                fa(240, -LEG_X - 0.034) + fwd * 0.01, fa(300, -LEG_X - 0.034),
                                cpos + Vector((-0.025, 0.0, 0.03))], 6), 0.0045, segs=6)
    K.bm_sweep(hose, K.catmull([bar_at(0.225) + Vector((0, -0.02, -0.012)), cb + Vector((0.14, -0.06, -0.06)),
                                cb + Vector((0.06, 0.01, -0.13)), steer(216, 0.05) + Vector((0, 0.04, 0))], 6),
               0.0045, segs=6)


# --------------------------------------------------------------------------- #
def build_body(B):
    G = "Body"
    B.pivot(G, Vector((0, 0, 0.55)))

    # frame: head tube, twin spars down to the pivot, down tube, sub-frame
    K.bm_tube(B.bm(G, "frame"), steer(170), steer(220), 0.03, segs=20)
    spar = [(350, 178), (358, 200), (345, 214), (300, 233), (268, 241), (254, 254), (249, 272), (250, 300),
            (252, 314), (238, 318), (232, 300), (233, 270), (240, 246), (260, 229), (298, 216), (338, 194)]
    B.slab_pair(G, "frame", [L(spar)], 0.03, 0.078, bevel=0.007)
    K.bm_sweep(B.bm(G, "frame"), K.catmull([steer(214), P3(338, 236), P3(328, 256)], 5), 0.02, segs=12)
    for s in (1, -1):
        X = s * 0.085
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(258, 228, X), P3(220, 216, X), P3(180, 209, X),
                                                P3(148, 206, X)], 5), 0.012, segs=10)
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(236, 262, X), P3(205, 242, X), P3(172, 222, X),
                                                P3(150, 210, X)], 5), 0.012, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(160, 208, -0.085), P3(160, 208, 0.085), 0.011, segs=10)

    # battery pack (stressed member) with cooling ribs, and skid plate
    batt = [(257, 237), (289, 244), (301, 235), (314, 236), (318, 240), (323, 252), (329, 258), (329, 264),
            (322, 284), (326, 300), (320, 317), (308, 324), (272, 332), (257, 332)]
    B.slab(G, "battery", [L(batt)], 0.20, bevel=0.014)
    for s in (1, -1):
        for y in range(248, 320, 7):
            x1 = 316 if y < 300 else 312
            rib = K.offset_polyline2d([(281, y), (x1, y + 4)], 2.4)
            B.slab(G, "battrib", [L(rib)], 0.006, bevel=0.0015, x=s * 0.1)
    skid = [(240, 318), (250, 328), (272, 335), (308, 328), (322, 320), (332, 301), (336, 296), (328, 296),
            (318, 312), (305, 320), (272, 327), (252, 322), (244, 313)]
    B.slab(G, "black", [L(skid)], 0.18, bevel=0.006)

    # motor + covers
    mcen = P3(258, 296)
    K.bm_cyl(B.bm(G, "black"), K.wheel_matrix(mcen), 0.088, -0.088, 0.088, segs=40)
    cov = K.rounded_rect2d(*P(258, 293), 0.19, 0.24, 0.06, n=6)
    B.slab(G, "cover", [cov], 0.024, bevel=0.009, x=-0.098)
    B.slab(G, "black", [cov], 0.024, bevel=0.009, x=+0.098)
    for k in range(6):
        a = K.TAU * k / 6 + 0.3
        p = mcen + Vector((-0.111, 0.082 * math.cos(a), 0.1 * math.sin(a)))
        K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(p, (-1, 0, 0)), 0.0045, 0, 0.004, 6)
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(P3(262, 286, -0.111), (-1, 0, 0)), 0.014, 0, 0.006, 14)
    K.bm_sweep(B.bm(G, "alu"), [P3(255, 240, -0.104), P3(281, 286, -0.104)], 0.005, segs=6)
    rp_front = K.build_sprocket(B, G, "steel", P3(256, 306), 0.066, 13, 0.015875, thick=0.006, lighten=0)

    # rear shock + linkage
    st, sb = P3(222, 234), P3(203, 312)
    d = sb - st
    perp = d.normalized().cross(Vector((1, 0, 0)))
    if perp.y < 0:
        perp = -perp
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(st, (1, 0, 0)), 0.015, -0.018, 0.018, 14)
    K.bm_tube(B.bm(G, "black"), st + d * 0.03, st + d * 0.5, 0.025, segs=18)
    K.bm_tube(B.bm(G, "black"), st + d * 0.02 + perp * 0.04, st + d * 0.36 + perp * 0.04, 0.019, segs=16)
    K.box_between(B.bm(G, "black"), st + d * 0.06, st + d * 0.06 + perp * 0.04, 0.02, 0.022, up=(1, 0, 0))
    K.bm_tube(B.bm(G, "chrome"), st + d * 0.48, st + d * 0.95, 0.009, segs=12)
    K.bm_tube(B.bm(G, "alu"), st + d * 0.24, st + d * 0.27, 0.041, segs=20)
    K.bm_sweep(B.bm(G, "spring"), K.coil_points(st + d * 0.27, sb - d * 0.10, 0.036, 8), 0.0055, segs=8)
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(sb, (1, 0, 0)), 0.014, -0.016, 0.016, 14)
    for s in (1, -1):  # dog-bone links to the frame
        K.box_between(B.bm(G, "alu"), sb + Vector((s * 0.03, 0, 0)), P3(240, 320, s * 0.03), 0.012, 0.022)

    # seat
    seat = [(138, 203), (148, 201), (180, 203), (209, 207), (246, 208), (270, 205), (290, 198), (309, 190),
            (316, 192), (312, 200), (290, 212), (270, 222), (240, 226), (200, 224), (160, 218), (140, 212)]

    def seat_taper(co):
        x = px_of(co)
        if x > 200:
            w = K.lerp(0.12, 0.13, min((x - 200) / 100, 1))
        else:
            w = K.lerp(0.09, 0.12, max((x - 140) / 60, 0))
        co.x *= w / 0.13
        return co
    B.slab(G, "seat", [L(seat)], 0.26, bevel=0.032, res=3, fn=seat_taper)

    # dark tank cover in front of the seat
    tank = [(312, 196), (330, 182), (342, 172), (350, 180), (352, 192), (348, 205), (330, 207), (313, 204)]
    B.slab(G, "tankcover", [L(tank)], 0.18, bevel=0.016)

    # radiator-style shrouds: outer panels flare out towards the front
    def shroud_hw(co):
        x, y = px_of(co), py_of(co)
        return 0.135 + 0.0005 * (x - 226) + 0.0008 * (y - 200)

    shroud = [(226, 221), (253, 223), (289, 205), (301, 196), (306, 197), (308, 204), (321, 211), (341, 211),
              (349, 208), (364, 209), (366, 211), (362, 216), (356, 219), (351, 233), (347, 239), (339, 245),
              (334, 256), (328, 255), (324, 252), (319, 240), (314, 235), (301, 234), (289, 243), (269, 238),
              (253, 234), (226, 229)]
    for s in (1, -1):
        def place(co, s=s):
            co.x = s * shroud_hw(co) + (co.x - s * 0.15)
            return co
        B.slab(G, "red", [L(shroud)], 0.006, bevel=0.0025, x=s * 0.15, fn=place)
    body = [(226, 221), (253, 223), (289, 205), (301, 196), (306, 197), (308, 204), (321, 211), (338, 211),
            (338, 236), (320, 236), (301, 234), (289, 239), (269, 236), (253, 233), (226, 229)]

    def body_fill(co):
        co.x *= (shroud_hw(co) - 0.002) / 0.15
        return co
    B.slab(G, "red", [L(body)], 0.30, bevel=0.01, fn=body_fill)

    # rear side panels (thin) + black accent stripe
    side = [(138, 204), (160, 207), (190, 210), (232, 222), (232, 275), (227, 278), (214, 272), (203, 266),
            (191, 257), (179, 248), (156, 227), (138, 214)]
    for s in (1, -1):
        def sp(co, s=s):
            co.x = co.x - s * 0.12 + s * (0.118 + 0.0002 * (px_of(co) - 138))
            return co
        B.slab(G, "red", [L(side)], 0.005, bevel=0.002, x=s * 0.12, fn=sp)
        acc = [(141, 205), (176, 212), (178, 219), (174, 220), (153, 214)]

        def ap(co, s=s):
            co.x = co.x - s * 0.124 + s * (0.1225 + 0.0002 * (px_of(co) - 138))
            return co
        B.slab(G, "black", [L(acc)], 0.002, x=s * 0.124, fn=ap)

    # rear fender
    rf = [(81, 198), (131, 199), (150, 205), (156, 214), (152, 222), (141, 216), (132, 208), (109, 202),
          (95, 202)]

    def rf_taper(co):
        x = px_of(co)
        co.x *= K.lerp(0.05, 0.10, min(max((x - 81) / 70, 0), 1)) / 0.10
        return co
    B.slab(G, "red", [L(rf)], 0.20, bevel=0.006, fn=rf_taper)
    K.bm_box(B.bm(G, "redlight"), Matrix.Translation(P3(100, 205)), 0.04, 0.01, 0.012)

    # foot pegs + rear brake pedal
    for s in (1, -1):
        c = P3(236, 322, s * 0.165)
        K.bm_box(B.bm(G, "steel"), Matrix.Translation(c), 0.11, 0.05, 0.02)
        for k in range(6):
            for dy in (-0.022, 0.022):
                K.bm_box(B.bm(G, "steel"), Matrix.Translation(c + Vector((s * (-0.045 + 0.018 * k), dy, 0.012))),
                         0.006, 0.006, 0.009)
        K.box_between(B.bm(G, "frame"), P3(238, 316, s * 0.08), c - Vector((s * 0.05, 0, 0)), 0.03, 0.03)
    K.bm_sweep(B.bm(G, "steel"), [P3(243, 318, -0.118), P3(262, 322, -0.122), P3(290, 326, -0.125)],
               0.007, segs=8)
    K.bm_box(B.bm(G, "steel"), Matrix.Translation(P3(292, 325, -0.135)), 0.035, 0.02, 0.012)
    return rp_front


# --------------------------------------------------------------------------- #
def build_swingarm(B, rp_front, rp_rear):
    G = "Swingarm"
    B.pivot(G, SWING_PIVOT)
    arm = [(252, 292), (232, 290), (200, 298), (160, 312), (128, 320), (116, 325), (112, 334), (116, 343),
           (128, 347), (160, 340), (200, 326), (232, 318), (252, 312)]
    B.slab_pair(G, "alu", [L(arm)], 0.035, 0.09, bevel=0.009)
    B.slab(G, "alu", [L([(214, 296), (240, 290), (244, 312), (218, 321)])], 0.2, bevel=0.007)
    K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(SWING_PIVOT, (1, 0, 0)), 0.022, -0.115, 0.115, 16)
    for s in (1, -1):
        K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(SWING_PIVOT + Vector((s * 0.115, 0, 0)), (s, 0, 0)),
                 0.017, 0, 0.007, 6)
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(REAR_AXLE + Vector((s * 0.112, 0.02, 0))), 0.01, 0.055, 0.03)
    # chain slider (top) and chain guide (bottom) on the left arm
    B.slab(G, "black", [L([(250, 288), (200, 295), (170, 305), (172, 310), (202, 300), (250, 294)])],
           0.04, bevel=0.005, x=0.09)
    B.slab(G, "black", [L([(150, 345), (178, 340), (180, 356), (160, 362), (148, 356)])], 0.03, bevel=0.005,
           x=0.08)
    caliper(B, G, REAR_AXLE, -0.067, 0.110, math.radians(215), length=0.07)
    K.build_chain(B, G, "chain", 0.066, P(256, 306), rp_front, (REAR_AXLE.y, REAR_AXLE.z), rp_rear,
                  pitch=0.015875, plate_h=0.014, gap=0.012)


def build(B):
    materials(B)
    rp_rear = build_wheels(B)
    build_steering(B)
    rp_front = build_body(B)
    build_swingarm(B, rp_front, rp_rear)


def rig_points():
    """Key mechanical points (Blender coords, metres) for rigging in a game engine."""
    return dict(front_axle=FRONT_AXLE, rear_axle=REAR_AXLE, swingarm_pivot=SWING_PIVOT,
                steering_axis_top=steer(168), steering_axis_bottom=steer(216),
                wheel_radius_front=R_FRONT, wheel_radius_rear=R_REAR)
