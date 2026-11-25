"""
Light electric dirt bike in the style of the Sur-Ron Light Bee X.

Proportions were measured from a side-view reference photo (720 px square,
bike facing left). Every (x, y) pair below is a pixel in that photo and is
converted to metres with P(). Scale: 19" wheels (70/100-19 tyres, 0.623 m
outer diameter) span 220 px, giving 2.83 mm per pixel and a 1.25 m wheelbase,
which matches the real bike's published 1260 mm.

No brand logos or names are modelled; graphics are generic stripes.
"""

import math

from mathutils import Matrix, Vector

import bikekit as K

NAME = "SurRon"
REF = dict(size=720, scale=0.00283, center_px=(360, 360), mid_x=359, ground=580,
           camera_side=+1)  # photo shows the bike's left (+X) side

S = REF["scale"]
GROUND = REF["ground"]
MIDX = REF["mid_x"]


def P(x, y):
    """Photo pixel -> (Y, Z) metres. Image-left is the front (-Y)."""
    return ((x - MIDX) * S, (GROUND - y) * S)


def P3(x, y, X=0.0):
    Y, Z = P(x, y)
    return Vector((X, Y, Z))


def L(pts):
    return [P(x, y) for (x, y) in pts]


R_TIRE = 0.3113
FRONT_AXLE = Vector((0.0, P(139, 0)[0], R_TIRE))
REAR_AXLE = Vector((0.0, P(581, 0)[0], R_TIRE))
SWING_PIVOT = P3(425, 420)

# Fork geometry measured from the photo: leg centre line x = 207.5 - 0.39 (y - 335)
FORK_K = 0.39
LEG_X = 0.085           # fork leg centre distance from bike centre line
STEM_OFF = 0.032        # steering axis sits this far behind the fork legs
ZF = Vector((0.0, FORK_K, 1.0)).normalized()       # up the fork
YF = Vector((0.0, ZF.z, -ZF.y))                     # rearwards in clamp plane


def fa(y, X=0.0):
    """Point on the fork-leg axis at photo row y."""
    return P3(207.5 - FORK_K * (y - 335), y, X)


def steer(y, X=0.0):
    """Point on the steering (head tube) axis at photo row y."""
    return fa(y, X) + YF * STEM_OFF


def fork_frame(o):
    m = Matrix((Vector((1, 0, 0)), YF, ZF)).transposed().to_4x4()
    m.translation = o
    return m


def materials(B):
    B.material("frame", (0.032, 0.036, 0.055), metal=0.35, rough=0.42, coat=0.35)
    B.material("panel", (0.075, 0.082, 0.11), metal=0.1, rough=0.5, coat=0.2)
    B.material("graphic", (0.80, 0.82, 0.86), rough=0.4)
    B.material("black", (0.018, 0.018, 0.02), rough=0.45)
    B.material("battery", (0.03, 0.03, 0.034), rough=0.6)
    B.material("rubber", (0.016, 0.016, 0.016), rough=0.88, spec=0.3)
    B.material("grip", (0.02, 0.02, 0.02), rough=0.8)
    B.material("seat", (0.022, 0.022, 0.024), rough=0.7)
    B.material("rim", (0.03, 0.03, 0.035), metal=0.6, rough=0.32)
    B.material("hub", (0.035, 0.035, 0.04), metal=0.6, rough=0.35)
    B.material("spoke", (0.62, 0.63, 0.65), metal=1.0, rough=0.25)
    B.material("steel", (0.55, 0.56, 0.58), metal=1.0, rough=0.3)
    B.material("alu", (0.70, 0.71, 0.73), metal=1.0, rough=0.3)
    B.material("chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.08)
    B.material("bronze", (0.60, 0.40, 0.20), metal=1.0, rough=0.22)
    B.material("blue", (0.16, 0.13, 0.62), metal=0.9, rough=0.28)
    B.material("spring", (0.03, 0.03, 0.033), metal=0.3, rough=0.5)
    B.material("chain", (0.33, 0.33, 0.35), metal=1.0, rough=0.4)
    B.material("caliper", (0.06, 0.06, 0.065), metal=0.6, rough=0.35)
    B.material("lens", (0.92, 0.94, 1.0), rough=0.05, emit=2.0)
    B.material("redlight", (0.75, 0.02, 0.02), rough=0.2, emit=1.0)
    B.material("screen", (0.02, 0.05, 0.08), metal=0.2, rough=0.05)


# --------------------------------------------------------------------------- #
def build_wheels(B):
    mats = dict(rubber="rubber", rim="rim", spoke="spoke", hub="hub", axle="alu")
    K.build_wheel(B, "FrontWheel", FRONT_AXLE, rim_d=0.4826, tire_h=0.070, tire_w=0.080,
                  rim_w=0.034, hub_w=0.085, hub_r=0.028, flange_r=0.045, mats=mats)
    K.build_wheel(B, "RearWheel", REAR_AXLE, rim_d=0.4826, tire_h=0.070, tire_w=0.084,
                  rim_w=0.036, hub_w=0.096, hub_r=0.032, flange_r=0.048, mats=mats)
    # brake rotors (round, drilled) ride with the wheels
    K.build_rotor(B, "FrontWheel", "steel", FRONT_AXLE, +0.056, 0.1015, 0.073,
                  style="round", holes=24, arms=5)
    K.build_rotor(B, "RearWheel", "steel", REAR_AXLE, -0.058, 0.1015, 0.075,
                  style="round", holes=24, arms=5)
    # 48T rear sprocket + carrier on the left (chain) side
    rp = K.build_sprocket(B, "RearWheel", "alu", REAR_AXLE, +0.060, 48, 0.0127, lighten=6)
    K.bm_cyl(B.bm("RearWheel", "hub"), K.wheel_matrix(REAR_AXLE), 0.046, 0.050, 0.058, segs=32)
    return rp


def caliper(B, group, axle, x, r_disc, ang, length=0.07, mat="caliper"):
    """Arc-shaped brake caliper straddling the disc edge at angle `ang`."""
    cy, cz = axle.y, axle.z
    half = length / 2 / r_disc
    ro, ri = r_disc + 0.012, r_disc - 0.030
    pts = []
    n = 8
    for k in range(n + 1):
        a = ang - half + 2 * half * k / n
        pts.append((cy + ro * math.cos(a), cz + ro * math.sin(a)))
    for k in range(n + 1):
        a = ang + half - 2 * half * k / n
        pts.append((cy + ri * math.cos(a), cz + ri * math.sin(a)))
    s = 1 if x > 0 else -1
    B.slab(group, mat, [pts], 0.046, bevel=0.008, x=x + s * 0.006)
    # pads/pistons hint: a darker inner block
    c = Vector((x + s * 0.03, cy + (r_disc - 0.01) * math.cos(ang), cz + (r_disc - 0.01) * math.sin(ang)))
    K.bm_cyl(B.bm(group, "alu"), K.axis_matrix(c, (s, 0, 0)), 0.009, -0.004, 0.003, segs=10)
    return Vector((x + s * 0.006, cy + (r_disc - 0.01) * math.cos(ang), cz + (r_disc - 0.01) * math.sin(ang)))


# --------------------------------------------------------------------------- #
def build_steering(B):
    G = "Steering"
    B.pivot(G, steer(258))
    for s in (1, -1):
        X = s * LEG_X
        bm = B.bm(G, "black")
        K.bm_tube(bm, fa(206, X), fa(372, X), 0.0265, segs=24)          # outer tube (USD)
        K.bm_tube(B.bm(G, "alu"), fa(200, X), fa(207, X), 0.021, segs=20)  # top cap
        K.bm_tube(B.bm(G, "rubber"), fa(370, X), fa(379, X), 0.0228, segs=24)  # dust seal
        K.bm_tube(B.bm(G, "bronze"), fa(376, X), fa(452, X), 0.0185, segs=24)  # stanchion
        K.bm_tube(bm, fa(447, X), fa(482, X), 0.0235, segs=20)          # axle lug
        K.box_between(bm, fa(474, X), FRONT_AXLE + Vector((X, 0, 0)), 0.034, 0.036)
        K.bm_cyl(bm, K.axis_matrix(FRONT_AXLE + Vector((X, 0, 0)), (1, 0, 0)), 0.021, -0.017, 0.017, 18)
        # pinch bolts on the lug
        for dz in (-0.012, 0.012):
            p = FRONT_AXLE + Vector((X + s * 0.017, 0.02, dz))
            K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(p, (s, 0, 0)), 0.004, 0, 0.004, 6)
        # red decal band on the stanchion (generic, no text)
    # triple clamps (black anodised)
    clamp = K.rounded_rect2d(0, STEM_OFF / 2, 2 * LEG_X + 0.072, STEM_OFF + 0.074, 0.034, n=5)
    B.slab_frame(G, "rim", [clamp], 0.026, fork_frame(fa(222)), bevel=0.005)
    B.slab_frame(G, "rim", [clamp], 0.040, fork_frame(fa(292)), bevel=0.006)
    for y in (222, 292):
        for s in (1, -1):  # clamp bolts
            p = fa(y, s * (LEG_X + 0.03)) + YF * 0.008
            K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(p, (s, 0, 0)), 0.0045, 0, 0.006, 6)
    K.bm_tube(B.bm(G, "alu"), steer(222) + ZF * 0.012, steer(222) + ZF * 0.028, 0.017, segs=6)

    # handlebar ---------------------------------------------------------------
    cb = P3(263, 204)
    half = [(0.0, 0.0, 0.0), (0.10, 0.0, 0.0), (0.17, -0.006, 0.035), (0.24, -0.014, 0.058),
            (0.32, -0.020, 0.066), (0.39, -0.024, 0.068)]

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
    path = K.catmull([cb + Vector(p) for p in full], 6)
    K.bm_sweep(B.bm(G, "rim"), path, 0.0112, segs=14)
    for s in (1, -1):
        K.bm_tube(B.bm(G, "grip"), bar_at(s * 0.255), bar_at(s * 0.392), 0.0165, segs=16)
        K.bm_tube(B.bm(G, "alu"), bar_at(s * 0.392), bar_at(s * 0.40), 0.0145, segs=12)
        # risers + bar clamp
        K.bm_tube(B.bm(G, "rim"), steer(222, s * 0.035) + ZF * 0.012, cb + Vector((s * 0.035, 0, -0.012)),
                  0.0135, segs=12)
        K.bm_box(B.bm(G, "rim"), K.axis_matrix(cb + Vector((s * 0.035, 0, 0)), (1, 0, 0)), 0.034, 0.034, 0.028)
        # master cylinder, reservoir, lever
        mc = bar_at(s * 0.215)
        K.bm_tube(B.bm(G, "black"), mc + Vector((-s * 0.02, -0.012, 0)), mc + Vector((s * 0.03, -0.012, 0)),
                  0.011, segs=12)
        K.bm_box(B.bm(G, "black"), Matrix.Translation(mc + Vector((-s * 0.005, -0.004, 0.026))), 0.034, 0.026, 0.02)
        K.box_between(B.bm(G, "alu"), mc + Vector((s * 0.03, -0.03, -0.004)),
                      bar_at(s * 0.37) + Vector((0, -0.048, -0.026)), 0.011, 0.007)
        K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(mc + Vector((s * 0.03, -0.03, -0.004)), (0, 0, 1)), 0.006, -0.008, 0.008, 8)
    # thumb throttle on the right (-X)
    tp = bar_at(-0.248)
    K.bm_tube(B.bm(G, "black"), tp + Vector((0.008, 0, 0)), tp + Vector((-0.012, 0, 0)), 0.0175, segs=14)
    K.box_between(B.bm(G, "black"), tp + Vector((-0.002, -0.012, -0.004)), tp + Vector((-0.004, -0.04, -0.02)),
                  0.016, 0.006)
    # small dash display
    dc = cb + Vector((0, 0.012, 0.03))
    Md = K.axis_matrix(dc, (0, 0.55, 0.835), hint=(0, 1, 0))
    K.bm_box(B.bm(G, "black"), Md, 0.088, 0.052, 0.02)
    K.bm_box(B.bm(G, "screen"), Md @ Matrix.Translation((0, 0, 0.0105)), 0.072, 0.038, 0.002)

    # headlight in front of the fork legs -----------------------------------------
    hc = P3(213, 280)
    Mh = fork_frame(hc)
    K.bm_box(B.bm(G, "black"), Mh, 0.135, 0.05, 0.075, top=(0.92, 0.9))
    K.bm_box(B.bm(G, "lens"), Mh @ Matrix.Translation((0, -0.026, 0.0)), 0.105, 0.004, 0.05)
    K.bm_box(B.bm(G, "black"), Mh @ Matrix.Translation((0, -0.029, 0.0)), 0.115, 0.004, 0.006)  # LED bar divider
    for s in (1, -1):
        K.bm_tube(B.bm(G, "black"), hc + Vector((s * 0.06, 0.01, 0.0)), fa(284, s * (LEG_X - 0.02)), 0.006, segs=6)

    # front brake caliper + mount (left side, follows the fork)
    cpos = caliper(B, G, FRONT_AXLE, 0.056, 0.1015, math.radians(28))
    K.box_between(B.bm(G, "rim"), cpos + Vector((0.01, 0, 0)), fa(463, LEG_X), 0.012, 0.03)

    # hoses / cables
    hose = B.bm(G, "black")
    mc_r = bar_at(-0.215) + Vector((0, -0.02, -0.01))
    mc_l = bar_at(0.215) + Vector((0, -0.02, -0.01))
    K.bm_sweep(hose, K.catmull([mc_r, cb + Vector((-0.14, -0.09, -0.05)), cb + Vector((-0.02, -0.15, -0.13)),
                                fa(300, LEG_X + 0.03) + Vector((0, -0.03, 0)), fa(400, LEG_X + 0.03),
                                fa(452, LEG_X + 0.032), cpos + Vector((0.025, 0.0, 0.025))], 6), 0.0045, segs=6)
    K.bm_sweep(hose, K.catmull([mc_l, cb + Vector((0.14, -0.07, -0.05)), cb + Vector((0.07, -0.03, -0.17)),
                                steer(300, 0.05) + Vector((0, 0.02, 0))], 6), 0.0045, segs=6)
    K.bm_sweep(hose, K.catmull([bar_at(-0.25) + Vector((0, 0.01, -0.012)), cb + Vector((-0.11, -0.03, -0.08)),
                                cb + Vector((-0.06, 0.0, -0.16)), steer(298, -0.05) + Vector((0, 0.02, 0))], 6),
                0.0035, segs=6)


# --------------------------------------------------------------------------- #
def build_body(B):
    G = "Body"
    B.pivot(G, Vector((0, 0, 0.5)))

    # head stock + head tube
    K.bm_tube(B.bm(G, "frame"), steer(226), steer(292), 0.029, segs=20)
    B.slab(G, "frame", [L([(250, 238), (272, 240), (292, 254), (300, 280), (296, 304), (270, 306), (252, 296)])],
           0.15, bevel=0.012)

    # forged main spars (pair), running from head stock to the swingarm pivot plates
    spar = [(256, 236), (275, 243), (300, 262), (330, 284), (360, 306), (390, 334), (420, 366), (440, 390),
            (448, 406), (447, 428), (437, 442), (420, 444), (408, 432), (395, 392), (370, 368), (340, 342),
            (310, 318), (285, 300), (264, 292), (254, 282), (252, 250)]
    B.slab_pair(G, "frame", [L(spar)], 0.032, 0.088, bevel=0.007)
    # lower cradle rails down the front of the battery and under the motor
    for s in (1, -1):
        rail = [P3(x, y, s * 0.07) for (x, y) in [(262, 296), (282, 302), (296, 320), (301, 360), (303, 400),
                                                  (305, 430), (314, 452), (332, 468), (370, 474), (410, 472),
                                                  (432, 458), (440, 440)]]
        K.bm_sweep(B.bm(G, "frame"), K.catmull(rail, 4), 0.016, segs=12)
        cross = [P3(x, y, s * 0.075) for (x, y) in [(302, 400), (340, 404), (380, 408), (420, 418)]]
        K.bm_sweep(B.bm(G, "frame"), K.catmull(cross, 4), 0.012, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(304, 420, -0.07), P3(304, 420, 0.07), 0.013, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(380, 474, -0.07), P3(380, 474, 0.07), 0.013, segs=10)

    # battery block, side covers and stripe graphics
    batt = [(296, 300), (388, 300), (405, 330), (430, 372), (436, 400), (432, 410), (304, 410), (298, 360)]
    B.slab(G, "battery", [L(batt)], 0.15, bevel=0.01)
    cover = [(300, 303), (386, 303), (402, 331), (426, 372), (431, 398), (306, 406), (301, 360)]
    B.slab_pair(G, "panel", [L(cover)], 0.006, 0.078, bevel=0.0025)
    gfx = [[(305, 334), (322, 334), (333, 368), (313, 368)]]
    for k, y0 in enumerate([352, 361, 370, 379, 388]):
        x0 = 337 + k * 2
        x1 = 366 + k * 7
        gfx.append([(x0, y0), (x1, y0), (x1 + 3, y0 + 4), (x0 + 1, y0 + 4)])
    gfx.append([(392, 360), (418, 384), (414, 388), (388, 364)])
    gfx.append([(388, 372), (420, 398), (414, 401), (384, 376)])
    for g in gfx:
        B.slab_pair(G, "graphic", [L(g)], 0.0012, 0.0815)

    # top cover over the controller
    top = [(280, 262), (372, 262), (384, 270), (388, 290), (380, 302), (296, 302), (282, 288)]
    B.slab(G, "black", [L(top)], 0.17, bevel=0.014)
    for s in (1, -1):
        for k in range(5):  # controller cooling fins peeking out
            K.bm_box(B.bm(G, "alu"), Matrix.Translation(P3(330 + k * 9, 288, s * 0.086)), 0.006, 0.006, 0.04)
        K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(P3(372, 292, s * 0.085), (s, 0, 0)), 0.008, 0, 0.006, 8)

    # motor + reduction case
    mc = P3(373, 442)
    Mm = K.wheel_matrix(mc)
    K.bm_cyl(B.bm(G, "black"), Mm, 0.069, -0.058, 0.058, segs=40)
    for s in (1, -1):
        prof = [(s * 0.058, 0.069), (s * 0.064, 0.066), (s * 0.064, 0.052), (s * 0.059, 0.049),
                (s * 0.059, 0.032), (s * 0.067, 0.029), (s * 0.067, 0.0)]
        K.bm_lathe(B.bm(G, "alu"), Mm, prof, segs=40, closed=False)
        for k in range(8):
            a = K.TAU * k / 8
            p = mc + Vector((s * 0.064, 0.059 * math.cos(a), 0.059 * math.sin(a)))
            K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(p, (s, 0, 0)), 0.004, 0, 0.004, 6)
    B.slab(G, "black", [K.stadium2d(P(394, 446), P(428, 436), 0.036, 10)], 0.024, bevel=0.007, x=0.078)
    K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(P3(428, 436, 0.09), (1, 0, 0)), 0.012, 0, 0.004, 12)
    # bash guard under the motor
    guard = [(318, 462), (336, 476), (410, 479), (432, 467), (428, 461), (406, 471), (338, 469), (323, 457)]
    B.slab(G, "black", [L(guard)], 0.13, bevel=0.004)

    # final-drive front sprocket (11T, chain side)
    rp_front = K.build_sprocket(B, G, "steel", P3(428, 436), 0.060, 11, 0.0127, lighten=0)

    # rear shock (DNM style: blue reservoir, black coil)
    st, sb = P3(403, 328), P3(452, 400)
    d = sb - st
    perp = d.normalized().cross(Vector((1, 0, 0)))
    if perp.y > 0:
        perp = -perp
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(st, (1, 0, 0)), 0.013, -0.016, 0.016, 14)
    K.bm_tube(B.bm(G, "black"), st + d * 0.04, st + d * 0.48, 0.021, segs=18)
    K.bm_tube(B.bm(G, "blue"), st + d * 0.03 + perp * 0.036, st + d * 0.40 + perp * 0.036, 0.016, segs=16)
    K.box_between(B.bm(G, "blue"), st + d * 0.08, st + d * 0.08 + perp * 0.036, 0.018, 0.02, up=(1, 0, 0))
    K.bm_tube(B.bm(G, "blue"), st + d * 0.24, st + d * 0.27, 0.036, segs=20)
    K.bm_tube(B.bm(G, "chrome"), st + d * 0.46, st + d * 0.94, 0.0085, segs=12)
    K.bm_sweep(B.bm(G, "spring"), K.coil_points(st + d * 0.27, sb - d * 0.11, 0.031, 7.5), 0.0048, segs=8)
    K.bm_tube(B.bm(G, "black"), sb - d * 0.12, sb - d * 0.09, 0.034, segs=20)
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(sb, (1, 0, 0)), 0.012, -0.015, 0.015, 14)
    B.slab_pair(G, "frame", [K.stadium2d(P(403, 328), P(398, 306), 0.017)], 0.006, 0.022)

    # sub-frame tubes under the seat
    for s in (1, -1):
        X = s * 0.062
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(382, 300, X), P3(420, 301, X), P3(470, 298, X),
                                                P3(512, 292, X)], 5), 0.011, segs=10)
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(404, 336, X), P3(432, 318, X), P3(468, 299, X)], 5),
                   0.011, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(505, 293, -0.062), P3(505, 293, 0.062), 0.01, segs=10)

    # seat + integrated rear fender (one black piece), tapering towards the tail
    seat = [(386, 284), (394, 279), (420, 279), (450, 280), (480, 278), (510, 272), (535, 268), (560, 264),
            (580, 261), (581, 264), (560, 269), (540, 274), (520, 282), (500, 289), (470, 297), (440, 300),
            (405, 301), (388, 297), (383, 290)]
    W = 0.23

    def seat_taper(co):
        x = co.y / S + MIDX
        if x < 500:
            w = W
        elif x < 545:
            w = K.lerp(W, 0.13, (x - 500) / 45)
        else:
            w = K.lerp(0.13, 0.06, min((x - 545) / 36, 1.0))
        co.x *= w / W
        return co
    B.slab(G, "seat", [L(seat)], W, bevel=0.035, res=3, fn=seat_taper)

    # tail light + reflector bracket
    K.bm_sweep(B.bm(G, "black"), [P3(447, 296), P3(449, 310), P3(451, 322)], 0.005, segs=6)
    K.bm_box(B.bm(G, "redlight"), Matrix.Translation(P3(451, 318)), 0.05, 0.008, 0.025)
    K.bm_box(B.bm(G, "redlight"), Matrix.Translation(P3(568, 270)), 0.035, 0.015, 0.01)

    # foot pegs with teeth
    for s in (1, -1):
        c = P3(447, 463, s * 0.15)
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(c), 0.09, 0.045, 0.018)
        for k in range(5):
            for dy in (-0.019, 0.019):
                K.bm_box(B.bm(G, "alu"), Matrix.Translation(c + Vector((s * (-0.036 + 0.018 * k), dy, 0.011))),
                         0.006, 0.006, 0.008)
        K.box_between(B.bm(G, "frame"), P3(441, 455, s * 0.07), c - Vector((s * 0.04, 0, 0)), 0.03, 0.026)

    # kick stand (left side, folded)
    K.bm_sweep(B.bm(G, "black"), K.catmull([P3(440, 457, 0.095), P3(478, 463, 0.11), P3(515, 468, 0.116)], 4),
               0.0085, segs=8)
    K.bm_box(B.bm(G, "black"), Matrix.Translation(P3(517, 469, 0.116)), 0.03, 0.02, 0.008)
    return rp_front


# --------------------------------------------------------------------------- #
def build_swingarm(B, rp_front, rp_rear):
    G = "Swingarm"
    B.pivot(G, SWING_PIVOT)
    arm = [(418, 410), (436, 398), (462, 394), (486, 402), (530, 424), (575, 446), (596, 456), (602, 468),
           (596, 480), (580, 484), (560, 474), (520, 456), (480, 442), (450, 436), (428, 436), (416, 426)]
    B.slab_pair(G, "frame", [L(arm)], 0.026, 0.080, bevel=0.007)
    B.slab(G, "frame", [L([(436, 400), (462, 396), (468, 424), (444, 432)])], 0.16, bevel=0.006)
    K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(SWING_PIVOT, (1, 0, 0)), 0.021, -0.1, 0.1, 16)
    for s in (1, -1):
        K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(SWING_PIVOT + Vector((s * 0.1, 0, 0)), (s, 0, 0)),
                 0.016, 0, 0.006, 6)
        # chain adjuster blocks at the axle
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(REAR_AXLE + Vector((s * 0.096, 0.02, 0))), 0.008, 0.05, 0.026)
    B.slab_pair(G, "frame", [K.stadium2d(P(452, 400), P(452, 414), 0.016)], 0.006, 0.022)
    # stripe graphics on the left arm
    for k in range(3):
        B.slab(G, "graphic", [L(K.offset_polyline2d([(447, 405 + 5 * k), (505, 430 + 5 * k)], 2.0))],
               0.0012, x=0.0938)
    B.slab(G, "graphic", [L([(528, 446), (560, 458), (557, 466), (525, 454)])], 0.0012, x=0.0938)
    # chain slider
    B.slab(G, "black", [L([(440, 398), (470, 397), (500, 410), (496, 414), (468, 403), (440, 404)])],
           0.03, bevel=0.004, x=0.08)
    # rear caliper on the right side, under the arm
    caliper(B, G, REAR_AXLE, -0.058, 0.1015, math.radians(196))
    K.build_chain(B, G, "chain", 0.060, P(428, 436), rp_front, (REAR_AXLE.y, REAR_AXLE.z), rp_rear,
                  pitch=0.0127)


def build(B):
    materials(B)
    rp_rear = build_wheels(B)
    build_steering(B)
    rp_front = build_body(B)
    build_swingarm(B, rp_front, rp_rear)


def rig_points():
    """Key mechanical points (Blender coords, metres) for rigging in a game engine."""
    return dict(front_axle=FRONT_AXLE, rear_axle=REAR_AXLE, swingarm_pivot=SWING_PIVOT,
                steering_axis_top=steer(222), steering_axis_bottom=steer(292),
                wheel_radius_front=R_TIRE, wheel_radius_rear=R_TIRE)
