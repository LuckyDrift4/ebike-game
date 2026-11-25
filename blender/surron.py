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
    B.material("frame", (0.032, 0.036, 0.055), metal=0.35, rough=0.42, coat=0.35, bump=("noise", 900, 0.06), dirt=0.18)
    B.material("panel", (0.065, 0.072, 0.095), metal=0.1, rough=0.5, coat=0.2, bump=("noise", 700, 0.05), dirt=0.08)
    B.material("graphic", (0.80, 0.82, 0.86), rough=0.4)
    B.material("black", (0.018, 0.018, 0.02), rough=0.5, bump=("noise", 800, 0.06), dirt=0.2)
    B.material("battery", (0.03, 0.03, 0.034), rough=0.6, dirt=0.15)
    B.material("rubber", (0.016, 0.016, 0.016), rough=0.85, spec=0.3, bump=("rubber", 300, 0.12), dirt=0.28)
    B.material("grip", (0.02, 0.02, 0.02), rough=0.8, bump=("grip", 500, 0.35))
    B.material("seat", (0.022, 0.022, 0.024), rough=0.72, bump=("grip", 260, 0.4))
    B.material("cable", (0.012, 0.012, 0.013), rough=0.55)
    B.material("mesh", (0.02, 0.02, 0.022), metal=0.6, rough=0.45, dirt=0.15)
    B.material("gold", (0.75, 0.50, 0.16), metal=1.0, rough=0.28)
    B.material("rim", (0.03, 0.03, 0.035), metal=0.6, rough=0.32, dirt=0.15)
    B.material("hub", (0.035, 0.035, 0.04), metal=0.6, rough=0.35, dirt=0.15)
    B.material("spoke", (0.42, 0.43, 0.45), metal=1.0, rough=0.35, dirt=0.1)
    B.material("steel", (0.55, 0.56, 0.58), metal=1.0, rough=0.3, dirt=0.12)
    B.material("alu", (0.70, 0.71, 0.73), metal=1.0, rough=0.3, aniso=0.5, bump=("brushed", 60, 0.02))
    B.material("chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.08)
    B.material("bronze", (0.60, 0.40, 0.20), metal=1.0, rough=0.22)
    B.material("blue", (0.16, 0.13, 0.62), metal=0.9, rough=0.28)
    B.material("spring", (0.03, 0.03, 0.033), metal=0.3, rough=0.5, dirt=0.15)
    B.material("chain", (0.33, 0.33, 0.35), metal=1.0, rough=0.4, dirt=0.35)
    B.material("caliper", (0.06, 0.06, 0.065), metal=0.6, rough=0.35, dirt=0.2)
    B.material("lens", (0.92, 0.94, 1.0), rough=0.05, emit=2.0)
    B.material("redlight", (0.75, 0.02, 0.02), rough=0.2, emit=1.0)
    B.material("screen", (0.02, 0.05, 0.08), metal=0.2, rough=0.05)
    B.material("glass", (0.35, 0.38, 0.42), metal=0.0, rough=0.02, emit=0.12)
    B.material("drl", (0.85, 0.9, 1.0), rough=0.1, emit=0.35)


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
    for g, ax in (("FrontWheel", FRONT_AXLE), ("RearWheel", REAR_AXLE)):  # valve stems + rim locks
        a = math.radians(-60)
        r0 = 0.4826 / 2 - 0.018
        p0 = ax + Vector((0, r0 * math.cos(a), r0 * math.sin(a)))
        p1 = ax + Vector((0, (r0 - 0.03) * math.cos(a), (r0 - 0.03) * math.sin(a)))
        K.bm_tube(B.bm(g, "steel"), p0, p1, 0.0035, segs=8)
        K.bm_tube(B.bm(g, "black"), p1, p1 + (p1 - p0).normalized() * 0.012, 0.0045, segs=8)
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
    # piston bores bulging on the outer half, bleed nipple, pad pin, banjo bolt
    for da in (-half * 0.45, half * 0.45):
        a = ang + da
        c = Vector((x + s * 0.029, cy + (r_disc - 0.008) * math.cos(a), cz + (r_disc - 0.008) * math.sin(a)))
        K.bm_cyl(B.bm(group, mat), K.axis_matrix(c, (s, 0, 0)), 0.0115, -0.004, 0.004, segs=20)
        K.bm_cyl(B.bm(group, "steel"), K.axis_matrix(c + Vector((s * 0.004, 0, 0)), (s, 0, 0)), 0.004, 0,
                 0.0015, segs=6)
    top = Vector((x + s * 0.018, cy + (r_disc + 0.014) * math.cos(ang), cz + (r_disc + 0.014) * math.sin(ang)))
    radial = Vector((0, math.cos(ang), math.sin(ang)))
    K.bm_tube(B.bm(group, "steel"), top - radial * 0.004, top + radial * 0.008, 0.0028, segs=6)
    K.bm_cyl(B.bm(group, "rubber"), K.axis_matrix(top + radial * 0.008, radial), 0.0035, 0, 0.005, segs=8)
    pin = Vector((x, cy + (r_disc + 0.006) * math.cos(ang), cz + (r_disc + 0.006) * math.sin(ang)))
    K.bm_tube(B.bm(group, "steel"), pin - Vector((0.03, 0, 0)), pin + Vector((0.03, 0, 0)), 0.0022, segs=6)
    bj = Vector((x + s * 0.034, cy + (r_disc + 0.004) * math.cos(ang + half * 0.9),
                 cz + (r_disc + 0.004) * math.sin(ang + half * 0.9)))
    K.bolt(B.bm(group, "steel"), bj, (s, 0, 0), r=0.006, h=0.007)
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
        K.bm_tube(B.bm(G, "gold"), fa(195, X), fa(201, X), 0.009, segs=12)       # rebound adjuster
        for y in (214, 236, 270):                                                  # machined rings
            K.bm_tube(B.bm(G, "rim"), fa(y, X), fa(y + 2.5, X), 0.0275, segs=24)
        K.bm_tube(B.bm(G, "steel"), fa(364, X), fa(369, X), 0.0272, segs=24)      # seal holder
        for dy in (-0.012, 0.012):                                                 # caliper mount ears
            e = fa(458, X) + YF * 0.028 + ZF * dy
            K.bm_cyl(B.bm(G, "black"), K.axis_matrix(e, (1, 0, 0)), 0.007, -0.006, 0.006, 12)
        K.bm_box(B.bm(G, "black"), fork_frame(fa(400, X + s * 0.027) - YF * 0.006), 0.008, 0.018, 0.02)
        for y in (248, 300):  # clamp pinch bolts, front face
            K.bolt(B.bm(G, "steel"), fa(y - (26 if y == 248 else 8), X) - YF * 0.03, -YF, r=0.004)
    # triple clamps (black anodised)
    clamp = K.rounded_rect2d(0, STEM_OFF / 2, 2 * LEG_X + 0.072, STEM_OFF + 0.074, 0.034, n=5)
    B.inflate(G, "rim", [clamp], 0.006, 0.013, 0.004, frame=fork_frame(fa(222)), pocket=(0.012, 0.003, 0.005))
    B.inflate(G, "rim", [clamp], 0.006, 0.02, 0.005, frame=fork_frame(fa(292)))
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
        # hydraulic master cylinder: clamp, body, reservoir with cap, curved lever
        mc = bar_at(s * 0.215)
        K.bm_tube(B.bm(G, "black"), mc + Vector((-s * 0.012, 0, 0)), mc + Vector((s * 0.012, 0, 0)), 0.0155, segs=16)
        K.bm_tube(B.bm(G, "black"), mc + Vector((-s * 0.02, -0.02, -0.002)), mc + Vector((s * 0.03, -0.02, -0.002)),
                  0.0105, segs=14)
        res = mc + Vector((-s * 0.004, -0.006, 0.027))
        K.bm_box(B.bm(G, "black"), Matrix.Translation(res), 0.036, 0.028, 0.02, top=(0.95, 0.92))
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(res + Vector((0, 0, 0.011))), 0.034, 0.026, 0.003)
        for dx in (-0.013, 0.013):
            K.bolt(B.bm(G, "steel"), res + Vector((dx, 0.009, 0.0125)), (0, 0, 1), r=0.0022, h=0.0015, washer=False)
        piv = mc + Vector((s * 0.03, -0.032, -0.004))
        K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(piv, (0, 0, 1)), 0.0065, -0.009, 0.009, 10)
        blade = K.catmull([piv, piv + Vector((s * 0.03, -0.014, -0.004)), piv + Vector((s * 0.08, -0.022, -0.014)),
                           piv + Vector((s * 0.125, -0.018, -0.022)), piv + Vector((s * 0.15, -0.01, -0.024))], 5)
        K.bm_sweep_rect(B.bm(G, "alu"), blade, 0.013, 0.0065, up=(0, 0, 1))
        K.bm_sweep(B.bm(G, "alu"), [blade[-1], blade[-1] + (blade[-1] - blade[-2]).normalized() * 0.008], 0.0075,
                   segs=10)
        for dz in (-0.009, 0.009):  # clamp screws
            K.bolt(B.bm(G, "steel"), mc + Vector((0, 0.0155, dz)), (0, 1, 0), r=0.0025, h=0.002, washer=False)
    # switch block (left): lights / horn / mode buttons
    sw = bar_at(0.245)
    K.bm_box(B.bm(G, "black"), K.axis_matrix(sw, (1, 0, 0)), 0.044, 0.046, 0.026, top=(0.9, 0.9))
    for k, (dy, dz) in enumerate(((-0.016, 0.008), (-0.018, -0.006), (-0.004, 0.02))):
        K.bm_cyl(B.bm(G, "redlight" if k == 2 else "rubber"), K.axis_matrix(sw + Vector((0, dy, dz)),
                 Vector((0, dy, dz)).normalized()), 0.0045, 0, 0.004, 10)
    # thumb throttle on the right (-X)
    tp = bar_at(-0.248)
    K.bm_tube(B.bm(G, "black"), tp + Vector((0.008, 0, 0)), tp + Vector((-0.012, 0, 0)), 0.0175, segs=14)
    K.box_between(B.bm(G, "black"), tp + Vector((-0.002, -0.012, -0.004)), tp + Vector((-0.004, -0.04, -0.02)),
                  0.016, 0.006)
    # small dash display
    dc = cb + Vector((0, 0.014, 0.034))
    Md = K.axis_matrix(dc, (0, 0.55, 0.835), hint=(0, 1, 0))
    B.inflate(G, "black", [K.rounded_rect2d(0, 0, 0.092, 0.056, 0.012, n=4)], 0.006, 0.011, 0.007, frame=Md)
    K.bm_box(B.bm(G, "screen"), Md @ Matrix.Translation((0, 0.002, 0.0112)), 0.074, 0.04, 0.0015)
    K.box_between(B.bm(G, "black"), cb + Vector((0, 0.0, 0.012)), dc - Vector((0, 0.006, 0.008)), 0.016, 0.012)

    # front fender hung under the bottom clamp
    m = fa(292) - ZF * 0.03
    prof = [(0.21, -0.042), (0.20, -0.03), (0.08, -0.002), (0.0, 0.004), (-0.12, 0.0), (-0.26, -0.024),
            (-0.37, -0.056), (-0.375, -0.064), (-0.26, -0.042), (-0.12, -0.022), (0.0, -0.016),
            (0.08, -0.02), (0.20, -0.048)]
    ff = [(m.y + dy, m.z + dz) for (dy, dz) in prof]

    def ff_hw(u, v):
        dy = u - m.y
        if dy < -0.06:
            return 0.05 + 0.02 * min((-dy - 0.06) / 0.1, 1.0)
        if dy > 0.06:
            return 0.05 - 0.012 * min((dy - 0.06) / 0.12, 1.0)
        return 0.05
    B.inflate(G, "black", [ff], 0.009, ff_hw, 0.008, fn=lambda co: co - Vector((0, 0, 1.9 * co.x * co.x)))
    K.box_between(B.bm(G, "black"), m + Vector((0, 0, 0.002)), fa(292) - ZF * 0.012, 0.05, 0.05)

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
    loom = B.bm(G, "cable")
    for k, (x0, r) in enumerate(((0.03, 0.0065), (-0.02, 0.0045), (0.0, 0.004))):
        K.bm_sweep(loom, K.catmull([dc + Vector((x0, 0.01, -0.01)), cb + Vector((x0 * 1.5, 0.05, -0.05)),
                                    steer(232, x0) + YF * 0.04, steer(262, x0 * 0.8) + YF * 0.035,
                                    steer(290, x0 * 0.6) + YF * 0.04], 6), r, segs=8)
    for y in (240, 262):  # cable ties
        K.bm_tube(B.bm(G, "black"), steer(y, -0.012) + YF * 0.04, steer(y, 0.04) + YF * 0.04, 0.009, segs=8)


# --------------------------------------------------------------------------- #
def build_body(B):
    G = "Body"
    B.pivot(G, Vector((0, 0, 0.5)))

    # head stock + head tube
    K.bm_tube(B.bm(G, "frame"), steer(226), steer(292), 0.029, segs=20)
    B.inflate(G, "frame", [L([(250, 238), (272, 240), (292, 254), (300, 280), (296, 304), (270, 306),
                              (252, 296)])], 0.007, 0.075, 0.008, pocket=(0.012, 0.007, 0.008))

    # forged main spars (pair), running from head stock to the swingarm pivot plates
    spar = [(256, 236), (275, 243), (300, 262), (330, 284), (360, 306), (390, 334), (420, 366), (440, 390),
            (448, 406), (447, 428), (437, 442), (420, 444), (408, 432), (395, 392), (370, 368), (340, 342),
            (310, 318), (285, 300), (264, 292), (254, 282), (252, 250)]
    B.inflate_pair(G, "frame", [L(spar)], 0.007, 0.02, 0.004, 0.088, pocket=(0.011, 0.007, 0.008))
    # lower cradle rails down the front of the battery and under the motor
    front = [tuple(v) for v in K.catmull([(262, 292), (282, 299), (296, 318), (301, 360), (304, 412)], 4)]
    B.inflate_pair(G, "frame", [L(K.offset_polyline2d(front, 18))], 0.006, 0.014, 0.004, 0.074,
                   pocket=(0.007, 0.004, 0.006))
    cradle = [(296, 404), (314, 403), (332, 409), (352, 413), (400, 415), (430, 417), (448, 430), (448, 448),
              (437, 464), (420, 476), (395, 483), (350, 483), (326, 476), (311, 461), (301, 440)]
    hole = K.circle2d(*P(373, 442), 27 * S, 40)
    B.inflate_pair(G, "frame", [L(cradle), hole], 0.006, 0.012, 0.004, 0.074, pocket=(0.009, 0.005, 0.006))
    cross = [tuple(v) for v in K.catmull([(306, 398), (340, 402), (380, 406), (420, 414)], 4)]
    B.inflate_pair(G, "frame", [L(K.offset_polyline2d(cross, 9))], 0.007, 0.01, 0.005, 0.077)
    # cooling grille on each side at the front of the battery
    for s in (1, -1):
        X = s * 0.083
        K.bm_sweep_rect(B.bm(G, "mesh"), [P3(304, 330, X), P3(318, 330, X), P3(320, 402, X), P3(306, 402, X),
                                         P3(304, 330, X)], 0.006, 0.004, up=(1, 0, 0))
        for k in range(12):
            y = 335 + k * 5.6
            K.box_between(B.bm(G, "mesh"), P3(304.5 + (y - 330) * 0.02, y, X), P3(318.5 + (y - 330) * 0.025, y, X),
                          0.003, 0.0035, up=(1, 0, 0))
    # bolts at the frame joints
    bb = B.bm(G, "steel")
    for s in (1, -1):
        for (x, y) in ((262, 250), (286, 262), (280, 292)):
            K.bolt(bb, P3(x, y, s * 0.075), (s, 0, 0), r=0.0055)
        for (x, y) in ((438, 424), (428, 437)):
            K.bolt(bb, P3(x, y, s * 0.107), (s, 0, 0), r=0.006)
        for (x, y) in ((318, 452), (345, 476), (420, 471), (440, 446), (304, 404)):
            K.bolt(bb, P3(x, y, s * 0.085), (s, 0, 0), r=0.005)
        for (x, y) in ((348, 418), (408, 420)):
            K.bolt(B.bm(G, "gold"), P3(x, y, s * 0.085), (s, 0, 0), r=0.0075, h=0.006)
        for (x, y) in ((382, 300), (404, 336)):
            K.bolt(bb, P3(x, y, s * 0.073), (s, 0, 0), r=0.0045)
        for (x, y) in ((306, 312), (378, 311), (312, 398), (420, 394)):
            K.bolt(bb, P3(x, y, s * 0.0815), (s, 0, 0), r=0.003, h=0.002, washer=False)
    K.bm_tube(B.bm(G, "frame"), P3(304, 420, -0.07), P3(304, 420, 0.07), 0.013, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(380, 474, -0.07), P3(380, 474, 0.07), 0.013, segs=10)

    # battery block, side covers and stripe graphics
    batt = [(296, 300), (388, 300), (405, 330), (430, 372), (436, 400), (432, 410), (304, 410), (298, 360)]
    B.inflate(G, "battery", [L(batt)], 0.016, 0.075, 0.015)
    cover = [(300, 303), (386, 303), (402, 331), (426, 372), (431, 398), (306, 406), (301, 360)]
    B.inflate_pair(G, "panel", [L(cover)], 0.007, 0.005, 0.0025, 0.077, pocket=(0.008, 0.003, 0.004))
    for s_ in (1, -1):  # moulded vertical ribs on the upper cover
        for k in range(7):
            x = 312 + k * 4.2
            K.box_between(B.bm(G, "panel"), P3(x, 312, s_ * 0.0795), P3(x + 1.0, 334, s_ * 0.0795), 0.003, 0.0035,
                          up=(1, 0, 0))
    gfx = [[(305, 334), (322, 334), (333, 368), (313, 368)]]
    for k, y0 in enumerate([352, 361, 370, 379, 388]):
        x0 = 337 + k * 2
        x1 = 366 + k * 7
        gfx.append([(x0, y0), (x1, y0), (x1 + 3, y0 + 4), (x0 + 1, y0 + 4)])
    gfx.append([(392, 360), (418, 384), (414, 388), (388, 364)])
    gfx.append([(388, 372), (420, 398), (414, 401), (384, 376)])
    for g in gfx:
        B.slab_pair(G, "graphic", [L(g)], 0.0008, 0.0794)

    # top cover over the controller
    top = [(280, 262), (372, 262), (384, 270), (388, 290), (380, 302), (296, 302), (282, 288)]
    B.inflate(G, "black", [L(top)], 0.009, 0.085, 0.014)
    for s in (1, -1):
        for k in range(5):  # controller cooling fins peeking out
            K.bm_box(B.bm(G, "alu"), Matrix.Translation(P3(330 + k * 9, 288, s * 0.086)), 0.006, 0.006, 0.04)
        K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(P3(372, 292, s * 0.085), (s, 0, 0)), 0.008, 0, 0.006, 8)
    kp = P3(356, 262) + Vector((0, 0, 0.002))
    K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(kp, (0, 0, 1)), 0.013, 0, 0.006, 20)
    K.bm_cyl(B.bm(G, "black"), K.axis_matrix(kp, (0, 0, 1)), 0.009, 0.006, 0.012, 16)
    K.bm_box(B.bm(G, "steel"), Matrix.Translation(kp + Vector((0, 0, 0.017))), 0.0025, 0.016, 0.012)
    K.bm_box(B.bm(G, "black"), Matrix.Translation(kp + Vector((0, 0, 0.027))), 0.005, 0.026, 0.011)
    cp = P3(296, 282, 0.086)
    K.bm_cyl(B.bm(G, "rubber"), K.axis_matrix(cp, (1, 0, 0)), 0.016, 0, 0.006, 20)
    K.bm_cyl(B.bm(G, "rubber"), K.axis_matrix(cp, (1, 0, 0)), 0.011, 0.006, 0.01, 16)
    # motor phase cables + sensor lead from controller to motor
    for k in range(3):
        X = 0.034 + k * 0.011
        K.bm_sweep(B.bm(G, "cable"), K.catmull([P3(384, 298, X), P3(396, 330, X + 0.004), P3(398, 380, X + 0.006),
                                                P3(388, 412, X)], 6), 0.0055, segs=8)
    K.bm_sweep(B.bm(G, "cable"), K.catmull([P3(380, 300, 0.068), P3(400, 340, 0.07), P3(402, 395, 0.07),
                                            P3(392, 418, 0.066)], 6), 0.003, segs=6)

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
    B.inflate(G, "black", [K.stadium2d(P(394, 446), P(428, 436), 0.036, 10)], 0.008, 0.012, 0.01, c=0.078)
    K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(P3(428, 436, 0.09), (1, 0, 0)), 0.012, 0, 0.004, 12)
    # bash guard under the motor
    guard = [(318, 462), (336, 476), (410, 479), (432, 467), (428, 461), (406, 471), (338, 469), (323, 457)]
    B.inflate(G, "black", [L(guard)], 0.007, 0.065, 0.006)

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
    K.bm_tube(B.bm(G, "blue"), st + d * 0.205, st + d * 0.235, 0.034, segs=20)       # lock ring
    K.bm_tube(B.bm(G, "alu"), st + d * 0.40 + perp * 0.036, st + d * 0.43 + perp * 0.036, 0.012, segs=12)
    K.bm_tube(B.bm(G, "rubber"), st + d * 0.50, st + d * 0.56, 0.013, segs=12)       # bump stop
    K.box_between(B.bm(G, "black"), sb - d * 0.09, sb, 0.034, 0.024, up=(0, 1, 0))  # clevis
    B.slab_pair(G, "frame", [K.stadium2d(P(403, 328), P(398, 306), 0.017)], 0.006, 0.022)
    for s in (1, -1):
        K.bolt(B.bm(G, "steel"), st + Vector((s * 0.026, 0, 0)), (s, 0, 0), r=0.006)

    # sub-frame tubes under the seat
    for s in (1, -1):
        X = s * 0.062
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(382, 300, X), P3(420, 301, X), P3(470, 298, X),
                                                P3(512, 292, X)], 5), 0.011, segs=10)
        K.bm_sweep(B.bm(G, "frame"), K.catmull([P3(404, 336, X), P3(432, 318, X), P3(468, 299, X)], 5),
                   0.011, segs=10)
    K.bm_tube(B.bm(G, "frame"), P3(505, 293, -0.062), P3(505, 293, 0.062), 0.01, segs=10)

    # seat + integrated rear fender (one black piece), tapering towards the tail
    seat = [(385, 287), (391, 280), (400, 278), (420, 279), (440, 280), (460, 278), (480, 274), (500, 271),
            (520, 267), (536, 265), (540, 268), (537, 273), (520, 279), (500, 285), (480, 290), (460, 295),
            (440, 298), (420, 298), (400, 297), (389, 294)]
    pan = [(390, 293), (420, 296), (440, 296), (460, 293), (480, 288), (500, 283), (520, 277), (537, 271),
           (539, 275), (520, 282), (500, 288), (480, 293), (460, 298), (440, 302), (420, 302), (400, 301),
           (391, 298)]
    rear = [(534, 271), (546, 268), (562, 265), (578, 261), (582, 263), (572, 267), (556, 271), (540, 276)]
    W = 0.23

    def seat_hw(u, v):
        x = u / S + MIDX
        if x < 500:
            w = W
        elif x < 545:
            w = K.lerp(W, 0.13, (x - 500) / 45)
        else:
            w = K.lerp(0.13, 0.06, min((x - 545) / 36, 1.0))
        return w / 2
    B.inflate(G, "seat", [L(seat)], 0.008, seat_hw, 0.045, fn=lambda co: co + Vector((0, 0, 0.004 * (1 - min((co.x / 0.11) ** 2, 1)))))
    B.inflate(G, "black", [L(pan)], 0.006, lambda u, v: seat_hw(u, v) - 0.006, 0.006)

    def rear_hw(u, v):
        x = u / S + MIDX
        return K.lerp(0.055, 0.03, min(max((x - 534) / 48, 0), 1))
    B.inflate(G, "black", [L(rear)], 0.005, rear_hw, 0.006, fn=lambda co: co - Vector((0, 0, 0.6 * co.x * co.x)))
    for s_ in (1, -1):  # seat bolts
        K.bolt(B.bm(G, "steel"), P3(470, 296, s_ * 0.104), (s_, 0, 0), r=0.004)

    # tail light + reflector bracket
    K.bm_sweep(B.bm(G, "black"), [P3(447, 296), P3(449, 310), P3(451, 322)], 0.005, segs=6)
    K.bm_box(B.bm(G, "redlight"), Matrix.Translation(P3(451, 318)), 0.05, 0.008, 0.025)
    th = P3(566, 272) - Vector((0, 0, 0.004))
    K.bm_box(B.bm(G, "black"), Matrix.Translation(th), 0.045, 0.03, 0.016, top=(0.9, 0.9))
    K.bm_box(B.bm(G, "redlight"), Matrix.Translation(th + Vector((0, 0.016, 0.0))), 0.038, 0.003, 0.01)

    # foot pegs with teeth
    for s in (1, -1):
        c = P3(447, 463, s * 0.15)
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(c), 0.09, 0.045, 0.018)
        for k in range(5):
            for dy in (-0.019, 0.019):
                K.bm_box(B.bm(G, "alu"), Matrix.Translation(c + Vector((s * (-0.036 + 0.018 * k), dy, 0.011))),
                         0.006, 0.006, 0.008)
        K.box_between(B.bm(G, "frame"), P3(441, 455, s * 0.07), c - Vector((s * 0.04, 0, 0)), 0.03, 0.026)
        hinge = c - Vector((s * 0.047, 0, 0))
        K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(hinge, (0, 1, 0)), 0.007, -0.028, 0.028, 12)
        K.bm_sweep(B.bm(G, "spring"), K.coil_points(hinge + Vector((0, -0.02, 0)), hinge + Vector((0, 0.02, 0)),
                                                    0.009, 4, 10), 0.0015, segs=5)

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
    B.inflate_pair(G, "frame", [L(arm)], 0.006, 0.015, 0.004, 0.080, pocket=(0.008, 0.006, 0.006))
    # shock linkage: rocker plates + dog-bone up to the shock clevis
    for s in (1, -1):
        B.inflate(G, "frame", [K.stadium2d(P(458, 404), P(468, 380), 0.013, 8)], 0.004, 0.004, 0.003, c=s * 0.03)
        K.bolt(B.bm(G, "steel"), P3(458, 404, s * 0.034), (s, 0, 0), r=0.005)
        K.bolt(B.bm(G, "steel"), P3(468, 380, s * 0.034), (s, 0, 0), r=0.005)
    K.box_between(B.bm(G, "frame"), P3(468, 380), P3(454, 398), 0.03, 0.016, up=(1, 0, 0))
    B.inflate(G, "frame", [L([(436, 400), (462, 396), (468, 424), (444, 432)])], 0.008, 0.08, 0.007)
    K.bm_cyl(B.bm(G, "alu"), K.axis_matrix(SWING_PIVOT, (1, 0, 0)), 0.021, -0.1, 0.1, 16)
    for s in (1, -1):
        K.bm_cyl(B.bm(G, "steel"), K.axis_matrix(SWING_PIVOT + Vector((s * 0.1, 0, 0)), (s, 0, 0)),
                 0.016, 0, 0.006, 6)
        # chain adjuster blocks at the axle
        K.bm_box(B.bm(G, "alu"), Matrix.Translation(REAR_AXLE + Vector((s * 0.096, 0.02, 0))), 0.008, 0.05, 0.026)
    B.slab_pair(G, "frame", [K.stadium2d(P(452, 400), P(452, 414), 0.016)], 0.006, 0.022)
    # stripe graphics on the left arm
    for k in range(3):
        B.slab(G, "graphic", [L(K.offset_polyline2d([(447, 404 + 5 * k), (505, 429 + 5 * k)], 1.8))],
               0.0008, x=0.0952)
    B.slab(G, "graphic", [L([(528, 446), (560, 458), (557, 466), (525, 454)])], 0.0008, x=0.0952)
    # chain slider
    B.inflate(G, "black", [L([(440, 398), (470, 397), (500, 410), (496, 414), (468, 403), (440, 404)])],
              0.006, 0.015, 0.005, c=0.08)
    # rear hugger mudguard over the tyre, bolted to the swingarm
    R0, R1 = R_TIRE + 0.022, R_TIRE + 0.04
    hug = [(REAR_AXLE.y + R1 * math.cos(math.radians(a)), REAR_AXLE.z + R1 * math.sin(math.radians(a)))
           for a in range(70, 147, 4)]
    hug += [(REAR_AXLE.y + R0 * math.cos(math.radians(a)), REAR_AXLE.z + R0 * math.sin(math.radians(a)))
            for a in range(146, 69, -4)]

    def hug_wrap(co):
        rad = Vector((0, co.y - REAR_AXLE.y, co.z - REAR_AXLE.z))
        if rad.length > 1e-6:
            co -= rad.normalized() * (2.2 * co.x * co.x)
        return co
    B.inflate(G, "black", [hug], 0.01, 0.055, 0.009, fn=hug_wrap)
    for s in (1, -1):
        a = math.radians(140)
        p = REAR_AXLE + Vector((s * 0.05, (R0 + 0.008) * math.cos(a), (R0 + 0.008) * math.sin(a)))
        K.box_between(B.bm(G, "black"), p, P3(500, 446, s * 0.068), 0.012, 0.02)
    # rear caliper on the right side, under the arm
    cp = caliper(B, G, REAR_AXLE, -0.058, 0.1015, math.radians(196))
    K.box_between(B.bm(G, "frame"), cp + Vector((-0.012, 0, 0)), P3(520, 458, -0.08), 0.01, 0.024)
    K.bm_sweep(B.bm(G, "cable"), K.catmull([cp + Vector((-0.02, 0.0, 0.02)), P3(540, 444, -0.096),
                                            P3(480, 418, -0.096), P3(440, 404, -0.095), P3(420, 396, -0.09)], 6),
               0.0045, segs=6)
    for k in range(3):  # hose clips
        p = P3(470 + 25 * k, 414 + 11 * k, -0.096)
        K.bm_box(B.bm(G, "black"), Matrix.Translation(p), 0.006, 0.012, 0.012)
    B.inflate(G, "black", [L([(520, 466), (550, 476), (548, 488), (518, 478)])], 0.005, 0.016, 0.006, c=0.066)
    for s in (1, -1):
        K.bolt(B.bm(G, "steel"), REAR_AXLE + Vector((s * 0.096, 0.047, 0)), (0, 1, 0), r=0.005, h=0.006)
        K.bm_tube(B.bm(G, "steel"), REAR_AXLE + Vector((s * 0.096, 0.047, 0)),
                  REAR_AXLE + Vector((s * 0.096, 0.07, 0)), 0.003, segs=6)
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
