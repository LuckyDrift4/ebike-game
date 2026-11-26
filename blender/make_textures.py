"""
Generate the decal / graphic textures used by the bike models.

Run with a normal Python that has Pillow (not inside Blender):
    python blender/make_textures.py
Writes PNGs to blender/assets/textures/. All text is generic (no brands).
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assets", "textures")
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_C = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def noise_bg(w, h, base, amp=6, seed=1):
    import random
    rnd = random.Random(seed)
    im = Image.new("RGB", (w, h), base)
    px = im.load()
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            d = rnd.randint(-amp, amp)
            c = tuple(max(0, min(255, v + d)) for v in base)
            for yy in (y, y + 1):
                for xx in (x, x + 1):
                    if xx < w and yy < h:
                        px[xx, yy] = c
    return im


def cover_graphic(name, accent, accent2=(235, 238, 242), base=(24, 25, 28), mirror=False):
    """Battery side-cover print: dark panel, bold slanted blocks and speed stripes.
    The image spans the cover's side-view bounding box (front of bike = left)."""
    W, H = 1024, 800
    im = noise_bg(W, H, base, amp=4, seed=3)
    d = ImageDraw.Draw(im)
    # subtle technical hex pattern
    for j in range(0, H, 46):
        for i in range(0, W, 54):
            ox = i + (27 if (j // 46) % 2 else 0)
            pts = [(ox + 18 * math.cos(a), j + 18 * math.sin(a)) for a in [k * math.pi / 3 for k in range(6)]]
            d.line(pts + [pts[0]], fill=(34, 35, 39), width=2)
    # big white slanted blocks near the front
    d.polygon([(40, 210), (205, 210), (275, 560), (110, 560)], fill=accent2)
    d.polygon([(220, 210), (262, 210), (332, 560), (290, 560)], fill=accent2)
    # accent (lime) slashes
    d.polygon([(330, 330), (380, 330), (450, 690), (400, 690)], fill=accent)
    d.polygon([(400, 330), (425, 330), (495, 690), (470, 690)], fill=accent)
    # speed stripes towards the rear
    for k in range(6):
        y = 420 + k * 42
        x0 = 520 + k * 18
        d.polygon([(x0, y), (x0 + 340 - k * 20, y), (x0 + 352 - k * 20, y + 18), (x0 + 12, y + 18)],
                  fill=accent2 if k % 3 else accent)
    # chevrons upper rear
    for k in range(4):
        x = 640 + k * 70
        d.polygon([(x, 150), (x + 40, 150), (x + 80, 230), (x + 40, 310), (x, 310), (x + 40, 230)],
                  fill=(60, 62, 68))
    if mirror:  # right-hand side: graphic mirrored so it still flows front-to-back
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        d = ImageDraw.Draw(im)
    # small spec text (generic), always readable
    f = font(FONT_C, 30)
    d.text((140 if mirror else 560, 720), "72V  LITHIUM  POWER", fill=(150, 152, 158), font=f)
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    im.save(os.path.join(OUT, name))


def tire_sidewall(name, text_col=(214, 40, 30), base=(20, 20, 20)):
    """Sidewall band: u = around the tyre (two repeats), v = across the band."""
    W, H = 4096, 160
    im = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(im)
    big = font(FONT_B, 92)
    small = font(FONT_C, 40)
    for rep in range(2):
        x0 = rep * W // 2
        d.text((x0 + 120, 28), "TRAIL  KING", fill=text_col, font=big)
        d.text((x0 + 900, 58), "70/100-19  57M  TUBE TYPE", fill=(205, 205, 205), font=small)
        d.text((x0 + 1500, 58), "ROTATION", fill=(205, 205, 205), font=small)
        d.polygon([(x0 + 1720, 70), (x0 + 1840, 70), (x0 + 1840, 52), (x0 + 1880, 82), (x0 + 1840, 112),
                   (x0 + 1840, 94), (x0 + 1720, 94)], fill=(205, 205, 205))
    im.save(os.path.join(OUT, name))


def fork_decal(name, col=(210, 35, 30)):
    """Fork-leg wrap: u = around the leg (front half), v = up the leg."""
    W, H = 256, 1024
    im = Image.new("RGB", (W, H), (22, 22, 24))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 80, W, 110], fill=col)
    d.rectangle([0, 900, W, 960], fill=col)
    txt = Image.new("RGBA", (800, 200), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)
    td.text((10, 40), "AIR  SUSPENSION", fill=col + (255,), font=font(FONT_B, 70))
    txt = txt.rotate(90, expand=True)
    im.paste(txt, (60, 120), txt)
    im.save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    cover_graphic("cover_lime.png", accent=(190, 230, 20))
    cover_graphic("cover_lime_r.png", accent=(190, 230, 20), mirror=True)
    tire_sidewall("tire_sidewall_red.png")
    fork_decal("fork_red.png")
    print("textures written to", OUT)


if __name__ == "__main__":
    main()
