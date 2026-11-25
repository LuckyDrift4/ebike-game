"""
Blacked-out Sur-Ron Light Bee X, matched to the owner's photo of their bike:

- satin black forged frame, swingarm, sub-frame and ribbed battery covers
  (no stripe graphics)
- black rims, hubs and spokes; silver front rotor and axle nuts
- bronze-gold brake levers, foot pegs, shock body and chain
- black upside-down fork with silver top caps, long front fender, rear hugger
- no headlight; the kick stand is a separate part that swings down for the
  parked renders

Geometry comes from surron.py (same measured proportions); only the build
options and the colour/finish palette differ.
"""

import surron as base

NAME = "SurRonBlack"
REF = base.REF
STYLE = dict(graphics=False, full_ribs=True)
# renders: an open dirt quarry instead of the city square
SCENE = dict(hdri="quarry_01_1k.hdr", rot=290.0)

BRONZE = (0.50, 0.33, 0.13)


def materials(B):
    # satin / textured blacks, each slightly different like the real bike
    B.material("frame", (0.020, 0.020, 0.022), metal=0.35, rough=0.48, coat=0.15, bump=("noise", 900, 0.07),
               dirt=0.18)
    B.material("panel", (0.024, 0.024, 0.027), rough=0.55, bump=("noise", 700, 0.05), dirt=0.1)
    B.material("black", (0.016, 0.016, 0.018), rough=0.5, bump=("noise", 800, 0.06), dirt=0.2)
    B.material("battery", (0.03, 0.03, 0.034), rough=0.6, dirt=0.15)
    B.material("seat", (0.02, 0.02, 0.022), rough=0.72, bump=("grip", 260, 0.4))
    B.material("grip", (0.02, 0.02, 0.02), rough=0.8, bump=("grip", 500, 0.35))
    B.material("rubber", (0.016, 0.016, 0.016), rough=0.85, spec=0.3, bump=("rubber", 300, 0.12), dirt=0.28)
    B.material("cable", (0.012, 0.012, 0.013), rough=0.55)
    B.material("mesh", (0.02, 0.02, 0.022), metal=0.6, rough=0.45, dirt=0.15)
    B.material("rim", (0.018, 0.018, 0.02), metal=0.6, rough=0.32, dirt=0.15)
    B.material("hub", (0.02, 0.02, 0.022), metal=0.6, rough=0.35, dirt=0.15)
    B.material("spoke", (0.03, 0.03, 0.032), metal=0.7, rough=0.3, dirt=0.1)
    B.material("caliper", (0.03, 0.03, 0.033), metal=0.6, rough=0.35, dirt=0.2)
    B.material("bronze", (0.025, 0.025, 0.028), metal=0.8, rough=0.18)      # black DLC fork stanchions
    B.material("spring", (0.025, 0.025, 0.028), metal=0.3, rough=0.5, dirt=0.15)
    # bare metal
    B.material("steel", (0.55, 0.56, 0.58), metal=1.0, rough=0.3, dirt=0.12)
    B.material("alu", (0.66, 0.67, 0.69), metal=1.0, rough=0.3, aniso=0.5, bump=("brushed", 60, 0.02))
    B.material("chrome", (0.9, 0.9, 0.92), metal=1.0, rough=0.08)
    # bronze-gold anodised accents
    B.material("gold", BRONZE, metal=1.0, rough=0.28)
    B.material("lever", BRONZE, metal=1.0, rough=0.3)
    B.material("peg", BRONZE, metal=1.0, rough=0.35, dirt=0.2)
    B.material("shock", (0.55, 0.37, 0.15), metal=1.0, rough=0.25)
    B.material("chain", (0.42, 0.31, 0.15), metal=1.0, rough=0.4, dirt=0.35)
    # lights / misc
    B.material("graphic", (0.80, 0.82, 0.86), rough=0.4)
    B.material("lens", (0.92, 0.94, 1.0), rough=0.05, emit=2.0)
    B.material("redlight", (0.75, 0.02, 0.02), rough=0.2, emit=1.0)
    B.material("screen", (0.02, 0.05, 0.08), metal=0.2, rough=0.05)
    B.material("glass", (0.35, 0.38, 0.42), rough=0.02, emit=0.12)
    B.material("drl", (0.85, 0.9, 1.0), rough=0.1, emit=0.35)


def build(B):
    saved_style, saved_materials = dict(base.STYLE), base.materials
    base.STYLE.update(STYLE)
    base.materials = materials          # geometry functions look materials up by key
    try:
        base.build(B)
    finally:
        base.STYLE.clear()
        base.STYLE.update(saved_style)
        base.materials = saved_materials


def rig_points():
    return base.rig_points()
