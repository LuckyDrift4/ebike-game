"""
Procedural modelling toolkit for the e-bike models.

Runs inside Blender (tested with Blender 5.3 / the `bpy` module).

World conventions used by every bike:
    X = across the bike   (+X is the bike's LEFT side, the chain side)
    Y = along the bike    (-Y is the FRONT of the bike)
    Z = up                (ground plane is Z = 0)
    Units are metres, real-world scale.

Geometry is accumulated into one bmesh per (group, material) pair so the final
export is a handful of clean meshes per bike (e.g. "FrontWheel_Rubber"), each
with its origin at a useful pivot (axle, steering head, swingarm pivot).
"""

import math
import random

import bpy  # noqa: F401  (must be imported before bmesh when using the bpy module)
import bmesh
import numpy as np
from mathutils import Matrix, Vector, geometry

TAU = math.tau


# --------------------------------------------------------------------------- #
#  Small math helpers
# --------------------------------------------------------------------------- #
def V(*a):
    if len(a) == 1:
        return Vector(a[0])
    return Vector(a)


def lerp(a, b, t):
    return a + (b - a) * t


def axis_matrix(origin, zdir, hint=None):
    """4x4 matrix whose local Z points along `zdir`, placed at `origin`."""
    z = Vector(zdir).normalized()
    if hint is None:
        hint = Vector((0, 0, 1)) if abs(z.z) < 0.9 else Vector((0, 1, 0))
    x = Vector(hint).cross(z)
    if x.length < 1e-8:
        x = Vector((1, 0, 0)).cross(z)
    x.normalize()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def wheel_matrix(center):
    """Local Z = world X (the axle). local (r cos t, r sin t, a) -> world (a, Y, Z)."""
    return axis_matrix(center, (1, 0, 0))


def catmull(pts, n=6, closed=False):
    """Catmull-Rom resample of a polyline (smooth bends for tubes/cables)."""
    P = [Vector(p) for p in pts]
    if len(P) < 3:
        return P
    out = []
    m = len(P)
    rng = range(m) if closed else range(m - 1)
    for i in rng:
        p0 = P[(i - 1) % m] if closed else P[max(i - 1, 0)]
        p1 = P[i]
        p2 = P[(i + 1) % m]
        p3 = P[(i + 2) % m] if closed else P[min(i + 2, m - 1)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t
                              + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(P[-1])
    return out


def circle2d(cx, cy, r, n=16, start=0.0):
    return [(cx + r * math.cos(start + TAU * k / n), cy + r * math.sin(start + TAU * k / n))
            for k in range(n)]


def rounded_rect2d(cx, cy, w, h, r, n=4, angle=0.0):
    """Rounded rectangle centred on (cx, cy), optionally rotated (radians)."""
    r = min(r, w / 2 - 1e-5, h / 2 - 1e-5)
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 1),
               (-w / 2 + r, -h / 2 + r, 2), (w / 2 - r, -h / 2 + r, 3)]
    for (x, y, q) in corners:
        for k in range(n + 1):
            a = q * math.pi / 2 + (math.pi / 2) * k / n
            pts.append((x + r * math.cos(a), y + r * math.sin(a)))
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for (x, y) in pts]


def stadium2d(p0, p1, r, n=8):
    """2D capsule between two points."""
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0)
    a0 = math.atan2(d.y, d.x)
    pts = []
    for k in range(n + 1):
        a = a0 + math.pi / 2 + math.pi * k / n
        pts.append((p0.x + r * math.cos(a), p0.y + r * math.sin(a)))
    for k in range(n + 1):
        a = a0 - math.pi / 2 + math.pi * k / n
        pts.append((p1.x + r * math.cos(a), p1.y + r * math.sin(a)))
    return pts


def clip_line_to_polygon(p0, p1, poly, steps=200):
    """Longest inside run of segment p0->p1 within polygon (2D)."""
    P0, P1 = np.asarray(p0, float), np.asarray(p1, float)
    ts = np.linspace(0, 1, steps)
    pts = P0[None] + (P1 - P0)[None] * ts[:, None]
    ins = _inside(pts, np.asarray(poly, float))
    best, cur = None, None
    for i, k in enumerate(ins):
        if k and cur is None:
            cur = i
        if (not k or i == steps - 1) and cur is not None:
            end = i if k else i - 1
            if best is None or end - cur > best[1] - best[0]:
                best = (cur, end)
            cur = None
    if best is None:
        return None
    return tuple(pts[best[0]]), tuple(pts[best[1]])


def offset_polyline2d(pts, w):
    """Closed outline of a 2D polyline thickened to width w (for bands/rails)."""
    P = [Vector(p) for p in pts]
    left, right = [], []
    for i, p in enumerate(P):
        a = P[max(i - 1, 0)]
        b = P[min(i + 1, len(P) - 1)]
        t = (b - a).normalized()
        n = Vector((-t.y, t.x))
        left.append(p + n * w / 2)
        right.append(p - n * w / 2)
    return [tuple(v) for v in left] + [tuple(v) for v in reversed(right)]


# --------------------------------------------------------------------------- #
#  bmesh primitives (all append into an existing bmesh)
# --------------------------------------------------------------------------- #
def bm_sweep(bm, pts, r, segs=8, closed=False, caps=True, radii=None):
    """Round tube swept along a 3D polyline (parallel-transport frames)."""
    P = [Vector(p) for p in pts]
    n = len(P)
    if n < 2:
        return
    T = []
    for i in range(n):
        if closed:
            a = P[(i + 1) % n] - P[(i - 1) % n]
        else:
            a = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        T.append(a.normalized())
    ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = (ref - T[0] * ref.dot(T[0])).normalized()
    rings = []
    for i in range(n):
        if i > 0:
            N = N - T[i] * N.dot(T[i])
            if N.length < 1e-8:
                N = ref - T[i] * ref.dot(T[i])
            N.normalize()
        B = T[i].cross(N)
        rr = radii[i] if radii else r
        ring = [bm.verts.new(P[i] + rr * (math.cos(TAU * k / segs) * N + math.sin(TAU * k / segs) * B))
                for k in range(segs)]
        rings.append(ring)
    m = n if closed else n - 1
    for i in range(m):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
    if caps and not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])


def bm_tube(bm, p0, p1, r0, r1=None, segs=12, caps=True):
    bm_sweep(bm, [p0, p1], r0, segs, caps=caps, radii=[r0, r0 if r1 is None else r1])


def bm_lathe(bm, M, prof, segs=32, closed=True, a0=0.0, a1=TAU):
    """Revolve a (axial, radius) profile around local Z of matrix M."""
    full = abs((a1 - a0) - TAU) < 1e-6
    nseg = segs if full else segs + 1
    rings = []
    for (a, r) in prof:
        if r < 1e-7:
            rings.append([bm.verts.new(M @ Vector((0, 0, a)))])
            continue
        ring = []
        for k in range(nseg):
            t = a0 + (a1 - a0) * k / segs
            ring.append(bm.verts.new(M @ Vector((r * math.cos(t), r * math.sin(t), a))))
        rings.append(ring)
    npf = len(prof)
    m = npf if closed else npf - 1
    for i in range(m):
        r0, r1 = rings[i], rings[(i + 1) % npf]
        kmax = segs
        for k in range(kmax):
            k1 = (k + 1) % nseg if full else k + 1
            if len(r0) == 1 and len(r1) == 1:
                continue
            if len(r0) == 1:
                bm.faces.new((r0[0], r1[k1], r1[k]))
            elif len(r1) == 1:
                bm.faces.new((r0[k], r0[k1], r1[0]))
            else:
                bm.faces.new((r0[k], r0[k1], r1[k1], r1[k]))


def bm_cyl(bm, M, r, z0, z1, segs=16):
    """Closed cylinder along local Z of M, from z0 to z1."""
    bm_lathe(bm, M, [(z0, 0), (z0, r), (z1, r), (z1, 0)], segs, closed=False)


def bm_box(bm, M, sx, sy, sz, top=(1.0, 1.0), base_z=None):
    """Box in local frame M. Centred unless base_z is given (then z from base_z
    to base_z+sz). `top` scales the top face (taper)."""
    z0 = -sz / 2 if base_z is None else base_z
    z1 = z0 + sz
    hx, hy = sx / 2, sy / 2
    tx, ty = hx * top[0], hy * top[1]
    vs = [M @ Vector(p) for p in [(-hx, -hy, z0), (hx, -hy, z0), (hx, hy, z0), (-hx, hy, z0),
                                  (-tx, -ty, z1), (tx, -ty, z1), (tx, ty, z1), (-tx, ty, z1)]]
    v = [bm.verts.new(p) for p in vs]
    for f in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]:
        bm.faces.new([v[i] for i in f])


def bm_knob(bm, M, sx, sy, sz, chamfer=0.22):
    """Tyre knob: tapered block with chamfered top edges (base at local z=0)."""
    hx, hy = sx / 2, sy / 2
    zc = sz * (1 - chamfer)
    rings = [((hx, hy), 0.0), ((hx * 0.93, hy * 0.92), zc), ((hx * 0.72, hy * 0.68), sz)]
    vs = []
    for (ax, ay), z in rings:
        vs.append([bm.verts.new(M @ Vector(p)) for p in [(-ax, -ay, z), (ax, -ay, z), (ax, ay, z), (-ax, ay, z)]])
    for a, b in zip(vs, vs[1:]):
        for i in range(4):
            bm.faces.new((a[i], a[(i + 1) % 4], b[(i + 1) % 4], b[i]))
    bm.faces.new(vs[-1])
    bm.faces.new(list(reversed(vs[0])))


def bolt(bm, p, normal, r=0.005, h=0.004, washer=True, segs=6):
    """Hex bolt head (with optional washer) sitting on a surface at p."""
    n = Vector(normal).normalized()
    M = axis_matrix(p, n)
    if washer:
        bm_cyl(bm, M, r * 1.45, 0.0, 0.0012, segs=12)
    bm_cyl(bm, M, r, 0.0005, h, segs=segs)


def bm_sweep_rect(bm, pts, w, h, up=(1, 0, 0), caps=True):
    """Rectangular-section bar along a polyline: width w along `up`, height h."""
    P = [Vector(p) for p in pts]
    n = len(P)
    upv = Vector(up).normalized()
    rings = []
    for i in range(n):
        t = (P[min(i + 1, n - 1)] - P[max(i - 1, 0)]).normalized()
        a = (upv - t * upv.dot(t)).normalized()
        b = t.cross(a)
        rings.append([bm.verts.new(P[i] + a * (sx * w / 2) + b * (sy * h / 2))
                      for (sx, sy) in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[(k + 1) % 4], r1[(k + 1) % 4], r1[k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])


def box_between(bm, p0, p1, w, h, up=(0, 0, 1)):
    """Rectangular bar from p0 to p1, width w (across 'side'), height h (along up)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    M = axis_matrix((p0 + p1) / 2, d, hint=up)
    bm_box(bm, M, w, h, d.length)


# --------------------------------------------------------------------------- #
#  Curve based slabs (rounded-edge extrusions of traced 2D side profiles)
# --------------------------------------------------------------------------- #
# Profile coordinates are (Y, Z) side-view points. The slab is extruded along X.
_SIDE = Matrix(((0, 0, 1, 0),
                (1, 0, 0, 0),
                (0, 1, 0, 0),
                (0, 0, 0, 1)))  # curve local x->Y, y->Z, z->X


def slab_mesh(loops, thick, bevel=0.0, res=2, x=0.0):
    """Extrude one or more closed (Y,Z) loops (later loops inside earlier ones
    become holes) to a slab `thick` wide, centred on X = x, with rounded edges."""
    cu = bpy.data.curves.new("slab", 'CURVE')
    cu.dimensions = '2D'
    cu.fill_mode = 'BOTH'
    for loop in loops:
        sp = cu.splines.new('POLY')
        sp.points.add(len(loop) - 1)
        for p, (u, v) in zip(sp.points, loop):
            p.co = (u, v, 0, 1)
        sp.use_cyclic_u = True
    b = min(bevel, thick / 2 * 0.95)
    cu.extrude = max(thick / 2 - b, 1e-5)
    cu.bevel_depth = b
    cu.bevel_resolution = res
    cu.offset = -b
    ob = bpy.data.objects.new("slab_tmp", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    T = Matrix.Translation((x, 0, 0)) @ _SIDE
    me.transform(T)
    return me


def slab_mesh_frame(loops, thick, M, bevel=0.0, res=2):
    """Like slab_mesh but the (u, v) loops live in the XY plane of frame M and
    the extrusion runs along M's local Z (centred)."""
    me = slab_mesh(loops, thick, bevel, res, 0.0)
    me.transform(_SIDE.inverted())
    me.transform(M)
    return me


def deform_mesh(me, fn):
    for v in me.vertices:
        v.co = fn(v.co.copy())


# --------------------------------------------------------------------------- #
#  Inflated solids: smooth, rounded bodies whose silhouette is a traced outline
# --------------------------------------------------------------------------- #
def _subdivide_loop(loop, h):
    out = []
    n = len(loop)
    for i in range(n):
        a = np.asarray(loop[i], float)
        b = np.asarray(loop[(i + 1) % n], float)
        k = max(1, int(math.ceil(np.linalg.norm(b - a) / h)))
        for j in range(k):
            out.append(a + (b - a) * j / k)
    return np.array(out)


def _seg_dist(P, A, B):
    """Distance from points P (N,2) to the nearest of segments A->B (M,2)."""
    AB = B - A
    L2 = (AB ** 2).sum(1)
    L2[L2 == 0] = 1e-12
    out = np.empty(len(P))
    for s in range(0, len(P), 1024):
        p = P[s:s + 1024][:, None, :]
        t = np.clip(((p - A[None]) * AB[None]).sum(2) / L2[None], 0, 1)
        proj = A[None] + t[..., None] * AB[None]
        out[s:s + 1024] = np.sqrt(((p - proj) ** 2).sum(2)).min(1)
    return out


def _inside(P, loop):
    x, y = P[:, 0], P[:, 1]
    res = np.zeros(len(P), bool)
    B = np.roll(loop, -1, axis=0)
    for (x1, y1), (x2, y2) in zip(loop, B):
        cond = (y1 > y) != (y2 > y)
        xi = x1 + (y - y1) * (x2 - x1) / ((y2 - y1) if y2 != y1 else 1e-30)
        res ^= cond & (x < xi)
    return res


def inflate_mesh(loops, h, t_fn, r, c_fn=None, frame=None, rings=3, fn=None, pocket=None, extra=()):
    """Smooth solid whose outline (silhouette along the w axis) is `loops[0]`
    (later loops are holes). Points are (u, v); the solid is built along w:
      half-thickness t_fn(u, v), centre c_fn(u, v), edge radius r.
    Edges are rounded with a quarter circle of radius min(r, t); if r >= t the
    body is a closed pillow, otherwise a flat band joins the two halves.
    Coordinates map to world as (X=w, Y=u, Z=v), or through `frame` as (u, v, w).
    pocket=(rim, depth, ramp): forged-style recess: the faces drop by `depth`
    starting `rim` in from the outline, over a draft of width `ramp`."""
    c_fn = c_fn or (lambda u, v: 0.0)
    bl = [_subdivide_loop(l, h) for l in loops]
    A = np.concatenate(bl)
    B = np.concatenate([np.roll(l, -1, 0) for l in bl])

    def material(P):
        m = _inside(P, bl[0])
        for hl in bl[1:]:
            m &= ~_inside(P, hl)
        return m

    pts = [A]
    # rings of points inset from the boundary to resolve the rounded edge (and pocket walls)
    dists = [r * (1 - math.cos((math.pi / 2) * k / (rings + 1))) for k in range(1, rings + 1)]
    if pocket:
        rim, depth, ramp = pocket
        dists += [rim, rim + ramp * 0.33, rim + ramp * 0.66, rim + ramp]
    dists += list(extra)
    for dk in dists:
        if dk < 1e-6:
            continue
        for l in bl:
            tng = np.roll(l, -1, 0) - np.roll(l, 1, 0)
            tng /= np.linalg.norm(tng, axis=1)[:, None] + 1e-12
            nrm = np.stack([-tng[:, 1], tng[:, 0]], 1)
            for sgn in (1, -1):
                C = l + sgn * nrm * dk
                if not len(C):
                    continue
                ok = material(C)
                if ok.any():
                    d = _seg_dist(C[ok], A, B)
                    good = np.abs(d - dk) < max(0.3 * dk, 0.0008) if dk < 0.01 else np.abs(d - dk) < 0.2 * h
                    pts.append(C[ok][good])
    # interior hex grid
    mn, mx = bl[0].min(0), bl[0].max(0)
    xs = np.arange(mn[0] + h / 2, mx[0], h)
    ys = np.arange(mn[1] + h / 2, mx[1], h * 0.866)
    if len(xs) and len(ys):
        G = np.array([(x + (h / 2 if j % 2 else 0.0), y) for j, y in enumerate(ys) for x in xs])
        G = G[material(G)]
        if len(G):
            G = G[_seg_dist(G, A, B) > 0.45 * h]
            pts.append(G)
    P = np.concatenate(pts)
    nb = len(A)
    edges = []
    o = 0
    for l in bl:
        n = len(l)
        edges += [(o + i, o + (i + 1) % n) for i in range(n)]
        o += n
    res = geometry.delaunay_2d_cdt([Vector(p) for p in P], edges, [], 1, 1e-7)
    V2 = np.array([tuple(v) for v in res[0]])
    tris = [f for f in res[2] if len(f) == 3]
    # drop triangles outside the material (robustness against holes)
    cen = np.array([V2[list(f)].mean(0) for f in tris])
    keep = material(cen)
    tris = [f for f, k in zip(tris, keep) if k]
    d = _seg_dist(V2, A, B)
    is_b = d < 1e-6
    bm = bmesh.new()
    front, back = {}, {}
    for i, (u, v) in enumerate(V2):
        t = max(t_fn(u, v), 1e-4)
        rr = min(r, t)
        if d[i] >= rr:
            off = t
        else:
            off = t - rr + math.sqrt(max(rr * rr - (rr - d[i]) ** 2, 0.0))
        if pocket and d[i] > rim:
            x = min((d[i] - rim) / ramp, 1.0)
            off -= depth * x * x * (3 - 2 * x)
        c = c_fn(u, v)
        pf = (u, v, c + off)
        pb = (u, v, c - off)
        if frame is None:
            pf, pb = (pf[2], pf[0], pf[1]), (pb[2], pb[0], pb[1])
        else:
            pf, pb = tuple(frame @ Vector(pf)), tuple(frame @ Vector(pb))
        if fn:
            pf, pb = fn(Vector(pf)), fn(Vector(pb))
        front[i] = bm.verts.new(pf)
        if is_b[i] and off < 1e-6:
            back[i] = front[i]
        else:
            back[i] = bm.verts.new(pb)
    for f in tris:
        a, b_, c_ = f
        try:
            bm.faces.new((front[a], front[b_], front[c_]))
        except ValueError:
            pass
        try:
            bm.faces.new((back[c_], back[b_], back[a]))
        except ValueError:
            pass
    # side band where the halves do not meet
    for (i, j) in res[1]:
        if is_b[i] and is_b[j] and front[i] is not back[i]:
            try:
                bm.faces.new((front[i], back[i], back[j], front[j]))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("inflated")
    bm.to_mesh(me)
    bm.free()
    return me


# --------------------------------------------------------------------------- #
#  Decals: thin UV-mapped sheets carrying printed graphics / lettering
# --------------------------------------------------------------------------- #
def decal_planar(bm, loop_yz, x, rect, facing, h=0.01):
    """Flat printed sheet in the plane X = x, shaped like `loop_yz`, facing +X
    (facing=1) or -X (facing=-1). rect=(y0, z0, y1, z1) maps to UV 0..1."""
    uv = bm.loops.layers.uv.verify()
    outer = _subdivide_loop(loop_yz, h)
    edges = [(i, (i + 1) % len(outer)) for i in range(len(outer))]
    mn, mx = outer.min(0), outer.max(0)
    xs = np.arange(mn[0] + h / 2, mx[0], h)
    zs = np.arange(mn[1] + h / 2, mx[1], h)
    G = np.array([(a, b) for a in xs for b in zs]) if len(xs) and len(zs) else np.zeros((0, 2))
    if len(G):
        G = G[_inside(G, outer)]
    P = np.concatenate([outer, G]) if len(G) else outer
    res = geometry.delaunay_2d_cdt([Vector(p) for p in P], edges, [], 1, 1e-7)
    V2 = res[0]
    vs = [bm.verts.new((x, p[0], p[1])) for p in V2]
    y0, z0, y1, z1 = rect
    for f in res[2]:
        if len(f) != 3:
            continue
        c = sum((Vector(V2[i]) for i in f), Vector((0, 0))) / 3
        if not _inside(np.array([tuple(c)]), outer)[0]:
            continue
        a, b, cc = (vs[i] for i in f)
        n = (b.co - a.co).cross(cc.co - a.co)
        tri = (a, b, cc) if n.x * facing > 0 else (a, cc, b)
        try:
            face = bm.faces.new(tri)
        except ValueError:
            continue
        for lp in face.loops:
            lp[uv].uv = ((lp.vert.co.y - y0) / (y1 - y0), (lp.vert.co.z - z0) / (z1 - z0))


def decal_tire_band(bm, center, side, r0, r1, a_of_r, segs=144, flip=False):
    """Ring band on a tyre sidewall (u around, v across), facing outwards (side=+1/-1)."""
    uv = bm.loops.layers.uv.verify()
    c = Vector(center)
    rings = []
    nr = 4
    for j in range(nr + 1):
        r = r0 + (r1 - r0) * j / nr
        a = side * a_of_r(r)
        rings.append([bm.verts.new(c + Vector((a, r * math.cos(TAU * k / segs), r * math.sin(TAU * k / segs))))
                      for k in range(segs)])
    for j in range(nr):
        for k in range(segs):
            k1 = (k + 1) % segs
            quad = [rings[j][k], rings[j][k1], rings[j + 1][k1], rings[j + 1][k]]
            n = (quad[1].co - quad[0].co).cross(quad[3].co - quad[0].co)
            if n.x * side < 0:
                quad.reverse()
            face = bm.faces.new(quad)
            for lp in face.loops:
                vco = lp.vert.co - c
                t = math.atan2(vco.z, vco.y) % TAU
                if k1 == 0 and t < 1e-6 + TAU / segs * 0.5 and (lp.vert in (rings[j][0], rings[j + 1][0])):
                    t = TAU
                u = t / TAU
                if flip:
                    u = 1.0 - u
                rr = math.hypot(vco.y, vco.z)
                lp[uv].uv = (u, (rr - r0) / (r1 - r0))


def decal_wrap(bm, p0, p1, r, center_dir, half_angle, segs=16, flip=False):
    """Partial cylinder sleeve around the axis p0->p1, centred on direction center_dir."""
    uv = bm.loops.layers.uv.verify()
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0).normalized()
    cd = Vector(center_dir)
    cd = (cd - ax * cd.dot(ax)).normalized()
    bd = ax.cross(cd)
    rows = []
    for t in (0.0, 1.0):
        base = p0.lerp(p1, t)
        row = []
        for k in range(segs + 1):
            a = -half_angle + 2 * half_angle * k / segs
            row.append(bm.verts.new(base + r * (math.cos(a) * cd + math.sin(a) * bd)))
        rows.append(row)
    for k in range(segs):
        quad = [rows[0][k], rows[0][k + 1], rows[1][k + 1], rows[1][k]]
        mid = (quad[0].co + quad[2].co) / 2
        out = mid - p0
        out -= ax * out.dot(ax)
        n = (quad[1].co - quad[0].co).cross(quad[3].co - quad[0].co)
        if n.dot(out) < 0:
            quad.reverse()
        face = bm.faces.new(quad)
        for lp in face.loops:
            kk = rows[0].index(lp.vert) if lp.vert in rows[0] else rows[1].index(lp.vert)
            v = 0.0 if lp.vert in rows[0] else 1.0
            u = kk / segs
            lp[uv].uv = ((1.0 - u) if flip else u, v)


# --------------------------------------------------------------------------- #
#  Builder: materials, accumulation per (group, material), finalisation
# --------------------------------------------------------------------------- #
def _surface_texture(nt, bsdf, kind, scale, strength):
    """Procedural micro-surface for renders: 'noise' (cast/paint texture),
    'grip' (seat cover), 'rubber', 'brushed'. Only affects Blender renders."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = strength
    if kind == "grip":
        tex = nt.nodes.new("ShaderNodeTexVoronoi")
        tex.inputs["Scale"].default_value = scale
        nt.links.new(tc.outputs["Object"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Distance"], bump.inputs["Height"])
    elif kind == "brushed":
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, 1.0, 1.0)
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 40.0
        tex.inputs["Detail"].default_value = 12.0
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
    else:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Detail"].default_value = 6.0 if kind == "noise" else 10.0
        nt.links.new(tc.outputs["Object"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Fac"], bump.inputs["Height"])
        if kind == "rubber":
            rr = nt.nodes.new("ShaderNodeMapRange")
            rr.inputs["To Min"].default_value = bsdf.inputs["Roughness"].default_value - 0.08
            rr.inputs["To Max"].default_value = min(bsdf.inputs["Roughness"].default_value + 0.08, 1.0)
            nt.links.new(tex.outputs["Fac"], rr.inputs["Value"])
            nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    if "Coat Normal" in bsdf.inputs and bsdf.inputs["Coat Weight"].default_value > 0:
        pass  # keep the clear coat glassy-smooth over the textured base


def _split_bmesh(bm, max_tris):
    """Yield bmeshes of at most ~max_tris triangles, keeping connected pieces whole."""
    if len(bm.faces) <= max_tris:
        return [bm]
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    bm.verts.index_update()
    seen = set()
    islands = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        islands.append(isl)
    groups, cur, n = [], [], 0
    for isl in islands:
        if n + len(isl) > max_tris and cur:
            groups.append(cur)
            cur, n = [], 0
        cur.append(isl)
        n += len(isl)
    if cur:
        groups.append(cur)
    out = []
    uv_src = bm.loops.layers.uv.active
    for grp in groups:
        nb = bmesh.new()
        uv_dst = nb.loops.layers.uv.new("UVMap") if uv_src else None
        vmap = {}
        for isl in grp:
            for f in isl:
                vs = []
                for v in f.verts:
                    if v.index not in vmap:
                        vmap[v.index] = nb.verts.new(v.co)
                    vs.append(vmap[v.index])
                try:
                    nf = nb.faces.new(vs)
                except ValueError:
                    continue
                if uv_src:
                    for l_new, l_old in zip(nf.loops, f.loops):
                        l_new[uv_dst].uv = l_old[uv_src].uv
        out.append(nb)
    bm.free()
    return out


def _edge_bevel(nt, bsdf, radius):
    """Render-time rounded edge highlights (Cycles Bevel node), chained before any bump."""
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 6
    bev.inputs["Radius"].default_value = radius
    link = bsdf.inputs["Normal"].links[0] if bsdf.inputs["Normal"].is_linked else None
    if link and link.from_node.bl_idname == "ShaderNodeBump":
        nt.links.new(bev.outputs["Normal"], link.from_node.inputs["Normal"])
    else:
        nt.links.new(bev.outputs["Normal"], bsdf.inputs["Normal"])


def _wear(nt, bsdf, amount):
    """Scuffed paint: bare metal shows through on sharp convex edges and in fine
    scratches (Cycles 'Pointiness' + stretched noise). Render-only."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    edge = nt.nodes.new("ShaderNodeMapRange")
    edge.inputs["From Min"].default_value = 0.53
    edge.inputs["From Max"].default_value = 0.62
    nt.links.new(geo.outputs["Pointiness"], edge.inputs["Value"])
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 35.0
    nz.inputs["Detail"].default_value = 8.0
    nt.links.new(geo.outputs["Position"], nz.inputs["Vector"])
    patchy = nt.nodes.new("ShaderNodeMapRange")
    patchy.inputs["From Min"].default_value = 0.45
    patchy.inputs["From Max"].default_value = 0.6
    nt.links.new(nz.outputs["Fac"], patchy.inputs["Value"])
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = 'MULTIPLY'
    nt.links.new(edge.outputs["Result"], m1.inputs[0])
    nt.links.new(patchy.outputs["Result"], m1.inputs[1])
    # fine scratches: noise stretched along one axis, thresholded hard
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (2.0, 2.0, 90.0)
    mp.inputs["Rotation"].default_value = (0.4, 0.9, 0.2)
    nt.links.new(geo.outputs["Position"], mp.inputs["Vector"])
    sc = nt.nodes.new("ShaderNodeTexNoise")
    sc.inputs["Scale"].default_value = 60.0
    sc.inputs["Detail"].default_value = 2.0
    nt.links.new(mp.outputs["Vector"], sc.inputs["Vector"])
    scr = nt.nodes.new("ShaderNodeMapRange")
    scr.inputs["From Min"].default_value = 0.70
    scr.inputs["From Max"].default_value = 0.74
    scr.inputs["To Max"].default_value = 0.6
    nt.links.new(sc.outputs["Fac"], scr.inputs["Value"])
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = 'MAXIMUM'
    nt.links.new(m1.outputs[0], mx.inputs[0])
    nt.links.new(scr.outputs["Result"], mx.inputs[1])
    fac = nt.nodes.new("ShaderNodeMath")
    fac.operation = 'MULTIPLY'
    fac.use_clamp = True
    fac.inputs[1].default_value = amount
    nt.links.new(mx.outputs[0], fac.inputs[0])
    base = bsdf.inputs["Base Color"].default_value[:]
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = 'RGBA'
    mixc.inputs["A"].default_value = base
    mixc.inputs["B"].default_value = (0.26, 0.265, 0.275, 1.0)
    nt.links.new(fac.outputs[0], mixc.inputs["Factor"])
    nt.links.new(mixc.outputs["Result"], bsdf.inputs["Base Color"])
    mm = nt.nodes.new("ShaderNodeMapRange")
    mm.inputs["To Min"].default_value = bsdf.inputs["Metallic"].default_value
    mm.inputs["To Max"].default_value = 1.0
    nt.links.new(fac.outputs[0], mm.inputs["Value"])
    nt.links.new(mm.outputs["Result"], bsdf.inputs["Metallic"])


def _dust(nt, bsdf, amount):
    """Dusty, scuffed lower parts: more dirt close to the ground, broken up by noise."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    hgt = nt.nodes.new("ShaderNodeMapRange")
    hgt.inputs["From Min"].default_value = 0.05
    hgt.inputs["From Max"].default_value = 0.55
    hgt.inputs["To Min"].default_value = 1.0
    hgt.inputs["To Max"].default_value = 0.0
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 9.0
    nz.inputs["Detail"].default_value = 10.0
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.42
    ramp.inputs["From Max"].default_value = 0.68
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    mul2 = nt.nodes.new("ShaderNodeMath")
    mul2.operation = 'MULTIPLY'
    mul2.inputs[1].default_value = amount
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], hgt.inputs["Value"])
    nt.links.new(geo.outputs["Position"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(hgt.outputs["Result"], mul.inputs[0])
    nt.links.new(ramp.outputs["Result"], mul.inputs[1])
    nt.links.new(mul.outputs[0], mul2.inputs[0])
    base = bsdf.inputs["Base Color"].default_value[:]
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = 'RGBA'
    mixc.inputs["A"].default_value = base
    mixc.inputs["B"].default_value = (0.30, 0.27, 0.23, 1.0)
    nt.links.new(mul2.outputs[0], mixc.inputs["Factor"])
    nt.links.new(mixc.outputs["Result"], bsdf.inputs["Base Color"])
    if not bsdf.inputs["Roughness"].is_linked:
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["To Min"].default_value = bsdf.inputs["Roughness"].default_value
        mr.inputs["To Max"].default_value = 0.95
        nt.links.new(mul2.outputs[0], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], bsdf.inputs["Roughness"])


class Builder:
    def __init__(self, name):
        self.name = name
        self.coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.coll)
        self.mats = {}
        self.decal_mats = set()
        self.bms = {}
        self.pivots = {}
        self.objects = []

    # materials ---------------------------------------------------------------
    def material(self, key, rgb, metal=0.0, rough=0.5, coat=0.0, emit=0.0, spec=0.5, bump=None,
                 aniso=0.0, bevel=0.0015, dirt=0.0, wear=0.0, image=None):
        name = f"{self.name}_{key}"
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color = (*rgb, 1.0)
        m.metallic = metal
        m.roughness = rough
        nt = m.node_tree
        if nt is None:
            m.use_nodes = True
            nt = m.node_tree
        b = nt.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*rgb, 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        b.inputs["Specular IOR Level"].default_value = spec
        b.inputs["Coat Weight"].default_value = coat
        if emit > 0:
            b.inputs["Emission Color"].default_value = (*rgb, 1.0)
            b.inputs["Emission Strength"].default_value = emit
        if aniso:
            b.inputs["Anisotropic"].default_value = aniso
        if image:  # printed decal: UV-mapped image drives the base colour
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(image, check_existing=True)
            tex.interpolation = 'Cubic'
            nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
            self.decal_mats.add(key)
            dirt = wear = 0.0
        if bump:
            _surface_texture(nt, b, *bump)
        if bevel and emit == 0:
            _edge_bevel(nt, b, bevel)
        if wear:
            _wear(nt, b, wear)
        if dirt:
            _dust(nt, b, dirt)
        self.mats[key] = m
        return m

    # geometry accumulation -----------------------------------------------------
    def bm(self, group, mat):
        k = (group, mat)
        if k not in self.bms:
            self.bms[k] = bmesh.new()
        return self.bms[k]

    def add_mesh(self, group, mat, me):
        self.bm(group, mat).from_mesh(me)
        bpy.data.meshes.remove(me)

    def slab(self, group, mat, loops, thick, bevel=0.0, res=2, x=0.0, fn=None):
        me = slab_mesh(loops, thick, bevel, res, x)
        if fn:
            deform_mesh(me, fn)
        self.add_mesh(group, mat, me)

    def slab_frame(self, group, mat, loops, thick, M, bevel=0.0, res=2):
        self.add_mesh(group, mat, slab_mesh_frame(loops, thick, M, bevel, res))

    def slab_pair(self, group, mat, loops, thick, x, bevel=0.0, res=2, fn=None):
        """Same profile on both sides of the bike at +x and -x."""
        for s in (1, -1):
            f = None if fn is None else (lambda co, s=s: fn(co, s))
            self.slab(group, mat, loops, thick, bevel, res, s * x, f)

    def inflate(self, group, mat, loops, h, t, r, c=0.0, frame=None, rings=3, fn=None, pocket=None, extra=()):
        """Rounded solid from a side outline. t / c may be numbers or f(u, v)."""
        t_fn = t if callable(t) else (lambda u, v, t=t: t)
        c_fn = c if callable(c) else (lambda u, v, c=c: c)
        self.add_mesh(group, mat, inflate_mesh(loops, h, t_fn, r, c_fn, frame, rings, fn, pocket, extra))

    def inflate_pair(self, group, mat, loops, h, t, r, x, rings=3, fn=None, c=None, pocket=None, extra=()):
        """Mirrored pair at +x / -x. c(u, v, side) may move the centre per side."""
        for s in (1, -1):
            if c is None:
                cc = s * x
            else:
                cc = (lambda u, v, s=s: c(u, v, s))
            self.inflate(group, mat, loops, h, t, r, cc, None, rings, fn, pocket, extra)

    def pivot(self, group, p):
        self.pivots[group] = Vector(p)

    # finalise -------------------------------------------------------------------
    def finalize(self, smooth_angle=48.0, verbose=True, max_tris=19000):
        report = []
        for (group, mat), bm in sorted(self.bms.items()):
            if not bm.faces:
                bm.free()
                continue
            if mat not in self.decal_mats:   # decal sheets are built facing outwards already
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
            for idx, chunk in enumerate(_split_bmesh(bm, max_tris)):
                name = f"{self.name}_{group}_{mat}" + (str(idx + 1) if idx else "")
                me = bpy.data.meshes.new(name)
                chunk.to_mesh(me)
                chunk.free()
                pv = self.pivots.get(group, Vector((0, 0, 0)))
                me.transform(Matrix.Translation(-pv))
                for p in me.polygons:
                    p.use_smooth = True
                if hasattr(me, "set_sharp_from_angle"):       # Blender 4.1+
                    me.set_sharp_from_angle(angle=math.radians(smooth_angle))
                else:                                          # Blender 4.0 and older
                    me.use_auto_smooth = True
                    me.auto_smooth_angle = math.radians(smooth_angle)
                me.materials.append(self.mats[mat])
                ob = bpy.data.objects.new(name, me)
                ob.location = pv
                wn = ob.modifiers.new("WeightedNormal", 'WEIGHTED_NORMAL')
                wn.mode = 'FACE_AREA'
                wn.weight = 80
                wn.keep_sharp = True
                ob["group"] = group
                ob["part_material"] = mat
                self.coll.objects.link(ob)
                self.objects.append(ob)
                report.append((name, len(me.polygons)))
        self.bms.clear()
        if verbose:
            tot = 0
            for n, t in report:
                tot += t
                flag = "  <-- over Roblox 20k limit!" if t > 20000 else ""
                print(f"  {n:40s} {t:7d} tris{flag}")
            print(f"  {self.name} total: {tot} tris in {len(report)} meshes")
        return report


# --------------------------------------------------------------------------- #
#  Wheels
# --------------------------------------------------------------------------- #
def _tire_carcass(rim_r, h, w):
    """Closed (axial, radius) profile of a dirt-bike tyre carcass (no knobs)."""
    hw = w / 2
    half = [(0.0, rim_r + 0.835 * h), (0.40 * hw, rim_r + 0.83 * h), (0.75 * hw, rim_r + 0.79 * h),
            (0.95 * hw, rim_r + 0.68 * h), (1.0 * hw, rim_r + 0.52 * h), (0.93 * hw, rim_r + 0.30 * h),
            (0.70 * hw, rim_r + 0.08 * h), (0.60 * hw, rim_r - 0.004), (0.0, rim_r - 0.004)]
    left = [(-a, r) for (a, r) in reversed(half)][1:-1]
    return half + left


def _carcass_r(rim_r, h, w, a):
    """Outer carcass radius at axial position a (for seating knobs)."""
    hw = w / 2
    t = min(abs(a) / hw, 1.0)
    pts = [(0.0, 0.835), (0.40, 0.83), (0.75, 0.79), (0.95, 0.68), (1.0, 0.52)]
    for (t0, r0), (t1, r1) in zip(pts, pts[1:]):
        if t <= t1:
            return rim_r + h * lerp(r0, r1, (t - t0) / (t1 - t0))
    return rim_r + 0.52 * h


def build_wheel(B, group, center, *, rim_d, tire_h, tire_w, rim_w,
                spokes=36, hub_w=0.10, hub_r=0.032, flange_r=0.048,
                knob_pitch=0.046, segs=72, mats=None, tire_style="mx",
                hub_offset=0.0):
    """Knobby tyre + rim + spokes + hub + axle. `center` is the axle centre.
    mats: dict with keys rubber, rim, spoke, hub, axle."""
    mats = mats or {}
    c = Vector(center)
    M = wheel_matrix(c)
    rim_r = rim_d / 2
    B.pivot(group, c)

    # --- tyre carcass
    bm = B.bm(group, mats.get("rubber", "rubber"))
    prof = [(a, r) for (a, r) in _tire_carcass(rim_r, tire_h, tire_w)]
    # lathe uses (axial, radius) with axial along local Z == world X
    bm_lathe(bm, M, prof, segs=segs, closed=True)

    # --- knobs
    r_out = rim_r + tire_h
    kh = tire_h * 0.2
    rows = int(round(TAU * r_out / knob_pitch))
    rng = random.Random(int(center.y * 1000) + 7)
    hw = tire_w / 2
    for i in range(rows):
        th = TAU * i / rows
        knobs = []
        if i % 2 == 0:
            knobs.append((-tire_w * 0.1, 0.020, tire_w * 0.17, 0.0))      # siped centre block (two halves)
            knobs.append((tire_w * 0.1, 0.020, tire_w * 0.17, 0.0))
            knobs.append((0.80 * hw, 0.017, tire_w * 0.20, 0.55))          # shoulders
            knobs.append((-0.80 * hw, 0.017, tire_w * 0.20, -0.55))
        else:
            knobs.append((0.42 * hw, 0.018, tire_w * 0.24, 0.12))
            knobs.append((-0.42 * hw, 0.018, tire_w * 0.24, -0.12))
            if tire_style == "mx":
                knobs.append((0.98 * hw, 0.014, tire_w * 0.14, 1.05))      # side knobs
                knobs.append((-0.98 * hw, 0.014, tire_w * 0.14, -1.05))
        for (a, tl, aw, tilt) in knobs:
            rr = _carcass_r(rim_r, tire_h, tire_w, a) - 0.002
            radial = Vector((0, math.cos(th), math.sin(th)))
            tang = Vector((0, -math.sin(th), math.cos(th)))
            ax = Vector((1, 0, 0))
            up = (radial * math.cos(tilt) + ax * math.sin(tilt)).normalized()
            side = tang.cross(up).normalized()
            # moulded knobs are not perfectly regular: small twist and size variation
            tw = rng.uniform(-0.07, 0.07)
            tang, side = (tang * math.cos(tw) + side * math.sin(tw)), (side * math.cos(tw) - tang * math.sin(tw))
            tl *= rng.uniform(0.93, 1.07)
            aw *= rng.uniform(0.94, 1.06)
            base = c + ax * a + radial * rr
            Mk = Matrix((side, tang, up)).transposed().to_4x4()
            Mk.translation = base
            h_k = kh * (0.85 if abs(tilt) > 0.9 else 1.0) * rng.uniform(0.94, 1.04)
            bm_knob(bm, Mk, aw, tl, h_k + 0.002)

    # sidewall details: rim-protector rib and a raised band where the lettering sits
    for sgn in (1, -1):
        a0 = sgn * (0.66 * hw)
        bm_lathe(bm, M, [(a0, rim_r + 0.006), (a0 + sgn * 0.006, rim_r + 0.01), (a0 + sgn * 0.004, rim_r + 0.016),
                         (a0 - sgn * 0.002, rim_r + 0.014)], segs=segs, closed=True)
        for k in range(36):  # lettering blocks (generic, no text)
            t0 = TAU * k / 36 + 0.05
            if k % 9 in (0, 8):
                continue
            ln = 0.012 + 0.006 * ((k * 7) % 3)
            for j in range(2 if k % 2 else 1):
                tt = t0 + j * 0.03
                rad = Vector((0, math.cos(tt), math.sin(tt)))
                tg = Vector((0, -math.sin(tt), math.cos(tt)))
                ar = sgn * (0.97 * hw)
                pos = c + Vector((ar, 0, 0)) + rad * (rim_r + 0.45 * tire_h)
                Mk = Matrix((tg, rad, Vector((sgn, 0, 0)))).transposed().to_4x4()
                Mk.translation = pos
                bm_box(bm, Mk, ln, 0.008, 0.0016, base_z=0.0)

    # --- rim (U channel, closed profile)
    bm = B.bm(group, mats.get("rim", "rim"))
    rw = rim_w / 2
    rp = [(-rw, rim_r + 0.008), (-rw, rim_r - 0.004), (-0.62 * rw, rim_r - 0.019),
          (0.62 * rw, rim_r - 0.019), (rw, rim_r - 0.004), (rw, rim_r + 0.008),
          (rw - 0.0035, rim_r + 0.008), (rw - 0.0035, rim_r + 0.0), (-rw + 0.0035, rim_r + 0.0),
          (-rw + 0.0035, rim_r + 0.008)]
    bm_lathe(bm, M, rp, segs=segs, closed=True)

    # --- hub
    bm = B.bm(group, mats.get("hub", "hub"))
    hw2 = hub_w / 2
    o = hub_offset
    hp = [(o - hw2 - 0.006, 0.011), (o - hw2 - 0.006, hub_r * 0.8), (o - hw2, flange_r),
          (o - hw2 + 0.006, flange_r), (o - hw2 + 0.014, hub_r), (o + hw2 - 0.014, hub_r),
          (o + hw2 - 0.006, flange_r), (o + hw2, flange_r), (o + hw2 + 0.006, hub_r * 0.8),
          (o + hw2 + 0.006, 0.011)]
    bm_lathe(bm, M, hp, segs=32, closed=True)

    # --- spokes (cross-3 tangential lacing) + nipples
    bm_s = B.bm(group, mats.get("spoke", "spoke"))
    half_n = spokes // 2
    alpha = TAU * 3 / half_n  # cross-3 angle hub->rim
    for i in range(spokes):
        side = 1 if i % 2 == 0 else -1
        k = i // 2
        lead = 1 if k % 2 == 0 else -1
        th_h = TAU * i / spokes
        th_r = th_h + lead * alpha * 0.5
        hx = o + side * (hw2 - 0.003)
        ph = c + Vector((hx, (flange_r - 0.006) * math.cos(th_h), (flange_r - 0.006) * math.sin(th_h)))
        pr = c + Vector((side * 0.004, (rim_r - 0.017) * math.cos(th_r), (rim_r - 0.017) * math.sin(th_r)))
        bm_tube(bm_s, ph, pr, 0.002, segs=6)
        d = (pr - ph).normalized()
        bm_tube(bm_s, pr - d * 0.004, pr + d * 0.012, 0.0032, segs=6)
        # J-bend head at the hub flange
        bm_cyl(bm_s, axis_matrix(ph, (side, 0, 0)), 0.0034, -0.0015, 0.0025, segs=8)
        # rim eyelet around the nipple
        er = rim_r - 0.0185
        pe = c + Vector((side * 0.004, er * math.cos(th_r), er * math.sin(th_r)))
        bm_cyl(bm_s, axis_matrix(pe, (0, math.cos(th_r), math.sin(th_r))), 0.0052, -0.001, 0.0012, segs=10)

    # --- hub bearing seals + rim lock
    bm = B.bm(group, mats.get("rim", "rim"))
    for sgn in (1, -1):
        bm_cyl(bm, M, 0.019, o + sgn * (hw2 + 0.006), o + sgn * (hw2 + 0.009), segs=24)
    a = math.radians(115)
    p = c + Vector((0, (rim_r - 0.02) * math.cos(a), (rim_r - 0.02) * math.sin(a)))
    bm_box(bm, axis_matrix(p, (0, math.cos(a), math.sin(a))), 0.026, 0.02, 0.012)
    bm_cyl(bm, axis_matrix(p - Vector((0, math.cos(a), math.sin(a))) * 0.006, (0, -math.cos(a), -math.sin(a))),
           0.0055, 0, 0.012, segs=6)

    # --- axle with nuts
    bm = B.bm(group, mats.get("axle", "axle"))
    bm_cyl(bm, M, 0.0105, o - hw2 - 0.03, o + hw2 + 0.03, segs=12)
    for s in (-1, 1):
        bm_cyl(bm, M, 0.017, o + s * (hw2 + 0.022) - 0.006, o + s * (hw2 + 0.022) + 0.006, segs=6)


def build_rotor(B, group, mat, center, x, r_out, r_in, *, style="round", waves=12,
                holes=24, thick=0.0045, carrier_mat=None, arms=6):
    """Brake rotor in the YZ plane at X = x (wave or round), plus carrier arms."""
    cy, cz = center[1], center[2]
    n = waves * 10 if style == "wave" else 96
    outer, inner = [], []
    for k in range(n):
        t = TAU * k / n
        if style == "wave":
            ro = r_out - 0.006 * (0.5 + 0.5 * math.cos(waves * t))
            ri = r_in + 0.004 * (0.5 + 0.5 * math.cos(waves * t + math.pi))
        else:
            ro, ri = r_out, r_in
        outer.append((cy + ro * math.cos(t), cz + ro * math.sin(t)))
        inner.append((cy + ri * math.cos(t), cz + ri * math.sin(t)))
    loops = [outer, list(reversed(inner))]
    rm = (r_out + r_in) / 2
    for k in range(holes):
        t = TAU * (k + 0.5) / holes
        rr = rm + (0.008 if k % 2 else -0.008) * (1 if style == "round" else 0.6)
        loops.append(circle2d(cy + rr * math.cos(t), cz + rr * math.sin(t), 0.0035, 8))
    B.slab(group, mat, loops, thick, bevel=0.0008, res=1, x=x)
    # carrier / spider
    cm = carrier_mat or mat
    car = [circle2d(cy, cz, r_in + 0.004, 64), circle2d(cy, cz, 0.022, 24)]
    for k in range(arms):
        t = TAU * (k + 0.5) / arms
        rr = (r_in + 0.03) / 2 + 0.006
        car.append(circle2d(cy + rr * math.cos(t), cz + rr * math.sin(t), (r_in - 0.03) * 0.42, 14, t))
    B.slab(group, cm, car, thick * 1.2, bevel=0.001, res=1, x=x + (0.002 if x > 0 else -0.002))
    # bolts
    bm = B.bm(group, "axle" if "axle" in B.mats else cm)
    for k in range(arms):
        t = TAU * k / arms
        rr = 0.036
        p = Vector((x, cy + rr * math.cos(t), cz + rr * math.sin(t)))
        s = 1 if x > 0 else -1
        bm_cyl(bm, axis_matrix(p, (s, 0, 0)), 0.0055, 0, 0.006, segs=6)


def build_sprocket(B, group, mat, center, x, teeth, pitch=0.0127, thick=0.005, lighten=5):
    cy, cz = center[1], center[2]
    rp = pitch / (2 * math.sin(math.pi / teeth))
    root, tip = rp - pitch * 0.33, rp + pitch * 0.42
    pts = []
    for k in range(teeth):
        t0 = TAU * k / teeth
        dt = TAU / teeth
        for f, r in [(0.0, root), (0.18, root), (0.36, tip), (0.64, tip), (0.82, root)]:
            pts.append((cy + r * math.cos(t0 + f * dt), cz + r * math.sin(t0 + f * dt)))
    loops = [pts, circle2d(cy, cz, min(0.028, root * 0.45), 24)]
    if lighten:
        rr = (root - 0.015 + 0.04) / 2
        hr = max((root - 0.015 - 0.04) / 2 * 0.8, 0.004)
        for k in range(lighten):
            t = TAU * k / lighten
            loops.append(circle2d(cy + rr * math.cos(t), cz + rr * math.sin(t), hr, 18, t))
    B.slab(group, mat, loops, thick, bevel=0.0008, res=1, x=x)
    return rp


def chain_loop(c1, r1, c2, r2, n=400):
    """Closed 2D path (Y,Z) of an open belt/chain around two circles.
    c1 = front (small) sprocket, c2 = rear sprocket."""
    c1, c2 = Vector(c1), Vector(c2)
    d = (c2 - c1).length
    u = (c2 - c1) / d
    nrm = Vector((-u.y, u.x))
    if nrm.y > 0 or (abs(nrm.y) < 1e-9 and nrm.x < 0):
        pass
    if nrm.y < 0:  # want nrm pointing up (+Z which is the 2D y)
        nrm = -nrm
    beta = math.asin((r2 - r1) / d)
    m_top = -math.sin(beta) * u + math.cos(beta) * nrm
    m_bot = -math.sin(beta) * u - math.cos(beta) * nrm

    def arc(c, r, a_from, a_to, through):
        # choose direction passing through angle `through`
        def norm(a):
            return a % TAU
        span_ccw = norm(a_to - a_from)
        passes_ccw = norm(through - a_from) < span_ccw
        if passes_ccw:
            angs = [a_from + span_ccw * k / 40 for k in range(41)]
        else:
            span_cw = TAU - span_ccw
            angs = [a_from - span_cw * k / 40 for k in range(41)]
        return [c + r * Vector((math.cos(a), math.sin(a))) for a in angs]

    a_top = math.atan2(m_top.y, m_top.x)
    a_bot = math.atan2(m_bot.y, m_bot.x)
    au = math.atan2(u.y, u.x)
    path = []
    path += [c1 + r1 * m_top, c2 + r2 * m_top]
    path += arc(c2, r2, a_top, a_bot, au)[1:]
    path += [c1 + r1 * m_bot]
    path += arc(c1, r1, a_bot, a_top, au + math.pi)[1:-1]
    return path


def resample_closed(path, step):
    P = [Vector(p) for p in path]
    segs = []
    tot = 0.0
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        L = (b - a).length
        segs.append((a, b, L))
        tot += L
    n = max(int(round(tot / step)), 3)
    step = tot / n
    out = []
    s_target = 0.0
    acc = 0.0
    it = iter(segs)
    a, b, L = next(it)
    for k in range(n):
        s_target = k * step
        while acc + L < s_target:
            acc += L
            a, b, L = next(it)
        t = (s_target - acc) / L if L > 0 else 0
        out.append(a.lerp(b, t))
    return out


def build_chain(B, group, mat, x, c1, r1, c2, r2, pitch=0.0127, plate_h=0.0105, gap=0.0095):
    """Roller chain: link plates + rollers along the loop (Y,Z) at X = x."""
    path = chain_loop(c1, r1, c2, r2)
    pts = resample_closed(path, pitch)
    bm = B.bm(group, mat)
    n = len(pts)
    for i in range(n):
        p0, p1 = pts[i], pts[(i + 1) % n]
        a = Vector((x, p0.x, p0.y))
        b = Vector((x, p1.x, p1.y))
        d = b - a
        mid = (a + b) / 2
        M = axis_matrix(mid, d, hint=(1, 0, 0))  # local x ~ across? keep plates thin in X
        for s in (-1, 1):
            Mo = Matrix.Translation((s * gap / 2 * (1.25 if i % 2 else 1.0), 0, 0)) @ M
            # plate: thin in X, tall in local radial, long along d
            bm_box(bm, Mo, plate_h, 0.0016, d.length * 1.25)
        Mr = axis_matrix(a, (1, 0, 0))
        bm_cyl(bm, Mr, 0.0038, -gap / 2, gap / 2, segs=6)
    return len(pts)


def coil_points(p0, p1, R, turns, per_turn=14):
    p0, p1 = Vector(p0), Vector(p1)
    M = axis_matrix(p0, p1 - p0)
    L = (p1 - p0).length
    n = int(turns * per_turn)
    return [M @ Vector((R * math.cos(TAU * k / per_turn), R * math.sin(TAU * k / per_turn), L * k / n))
            for k in range(n + 1)]


# --------------------------------------------------------------------------- #
#  Scene / render / export helpers
# --------------------------------------------------------------------------- #
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import addon_utils
    for a in ("cycles", "io_scene_fbx", "io_scene_gltf2"):
        try:
            addon_utils.enable(a, default_set=True)
        except Exception as e:  # pragma: no cover
            print("addon", a, e)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    sc.unit_settings.scale_length = 1.0


def _denoise(sc):
    """Use OpenImageDenoise when this Blender build has it (distro builds may not);
    otherwise render noise-free the slow way with more samples."""
    try:
        import _cycles
        has_oidn = bool(getattr(_cycles, "with_openimagedenoise", True))
    except ImportError:
        has_oidn = True
    sc.cycles.use_denoising = has_oidn
    if has_oidn:
        sc.cycles.denoiser = 'OPENIMAGEDENOISE'
    else:
        sc.cycles.samples = max(sc.cycles.samples * 4, 256)
        sc.cycles.adaptive_threshold = 0.02


def setup_render(res=(1600, 1000), samples=64):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    _denoise(sc)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'Medium High Contrast'
    w = bpy.data.worlds.new("World")
    sc.world = w
    nt = w.node_tree
    if nt is None:
        w.use_nodes = True
        nt = w.node_tree
    bg = nt.nodes.get("Background")
    bg.inputs[0].default_value = (0.95, 0.955, 0.965, 1)
    bg.inputs[1].default_value = 0.9


def add_studio(center=(0, 0, 0.5), size=6.0):
    c = Vector(center)
    # ground (shadow catcher look: light grey floor)
    me = bpy.data.meshes.new("floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    bm.to_mesh(me)
    bm.free()
    fl = bpy.data.objects.new("Floor", me)
    bpy.context.scene.collection.objects.link(fl)
    m = bpy.data.materials.new("floor")
    nt = m.node_tree
    if nt is None:
        m.use_nodes = True
        nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.8, 0.8, 0.82, 1)
    b.inputs["Roughness"].default_value = 0.6
    me.materials.append(m)
    fl.is_shadow_catcher = True

    def light(name, kind, loc, energy, size_, rot_target=None, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == 'AREA':
            ld.size = size_
        if kind == 'SUN':
            ld.angle = math.radians(size_)
        ob = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(ob)
        ob.location = loc
        if rot_target is not None:
            d = Vector(rot_target) - Vector(loc)
            ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        return ob

    light("Key", 'AREA', c + Vector((3.0, -2.5, 3.5)), 260, 2.0, c)
    light("Rim", 'AREA', c + Vector((0.5, 4.0, 3.0)), 160, 2.0, c)


def setup_outdoor(samples=96, sun_elev=38.0, sun_rot=-40.0):
    """Daylight scene: physical sky + sun, asphalt ground, AgX view."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    _denoise(sc)
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.view_settings.exposure = 0.35
    w = bpy.data.worlds.new("Sky")
    sc.world = w
    nt = w.node_tree
    if nt is None:
        w.use_nodes = True
        nt = w.node_tree
    bg = nt.nodes.get("Background")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = 'MULTIPLE_SCATTERING' if 'MULTIPLE_SCATTERING' in \
        sky.bl_rna.properties['sky_type'].enum_items.keys() else 'NISHITA'
    sky.sun_elevation = math.radians(sun_elev)
    sky.sun_rotation = math.radians(sun_rot)
    for prop, val in (("sun_disc", False), ("air_density", 1.0), ("dust_density", 2.0), ("altitude", 100.0)):
        if hasattr(sky, prop):
            setattr(sky, prop, val)
    nt.links.new(sky.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 0.11
    # sun lamp matching the sky's sun direction
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = 4.6
    ld.angle = math.radians(1.2)
    ld.color = (1.0, 0.96, 0.9)
    sun = bpy.data.objects.new("Sun", ld)
    sc.collection.objects.link(sun)
    el, rot = math.radians(sun_elev), math.radians(sun_rot)
    d = Vector((math.sin(rot) * math.cos(el), math.cos(rot) * math.cos(el), math.sin(el)))  # towards sun
    sun.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    # concrete paver ground
    me = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("Ground", me)
    sc.collection.objects.link(g)
    m = bpy.data.materials.new("asphalt")
    nt = m.node_tree
    if nt is None:
        m.use_nodes = True
        nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.offset = 0.0
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.008
    brick.inputs["Brick Width"].default_value = 0.4
    brick.inputs["Row Height"].default_value = 0.4
    brick.inputs["Color1"].default_value = (0.26, 0.255, 0.25, 1)
    brick.inputs["Color2"].default_value = (0.20, 0.195, 0.19, 1)
    brick.inputs["Mortar"].default_value = (0.05, 0.05, 0.05, 1)
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = 180.0
    n1.inputs["Detail"].default_value = 8.0
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = 3.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.55, 0.55, 0.56, 1)
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1)
    mul = nt.nodes.new("ShaderNodeMixRGB")
    mul.blend_type = 'MULTIPLY'
    mul.inputs[0].default_value = 1.0
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = 'MULTIPLY_ADD'
    mix.inputs[1].default_value = 0.35
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(tc.outputs["Object"], n1.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"])
    nt.links.new(n2.outputs["Fac"], mix.inputs[0])
    nt.links.new(n1.outputs["Fac"], mix.inputs[2])
    nt.links.new(mix.outputs[0], ramp.inputs[0])
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], mul.inputs[1])
    nt.links.new(ramp.outputs["Color"], mul.inputs[2])
    nt.links.new(mul.outputs[0], b.inputs["Base Color"])
    hm = nt.nodes.new("ShaderNodeMath")
    hm.operation = 'MULTIPLY_ADD'
    hm.inputs[1].default_value = 0.15
    nt.links.new(n1.outputs["Fac"], hm.inputs[0])
    nt.links.new(brick.outputs["Fac"], hm.inputs[2])
    nt.links.new(hm.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.88
    me.materials.append(m)


def setup_hdri(path, rot_deg=0.0, strength=1.0, samples=128, exposure=0.0):
    """Photographic backdrop: an HDR environment lights the bike and forms the
    background; an invisible shadow-catcher floor grounds it with real shadows."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    _denoise(sc)
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.view_settings.exposure = exposure
    w = bpy.data.worlds.new("HDRI")
    sc.world = w
    nt = w.node_tree
    if nt is None:
        w.use_nodes = True
        nt = w.node_tree
    bg = nt.nodes.get("Background")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(path, check_existing=True)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0, 0, math.radians(rot_deg))
    mp.name = "HDRI_Rotation"
    nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], bg.inputs[0])
    bg.inputs[1].default_value = strength
    me = bpy.data.meshes.new("ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=20)
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("Ground", me)
    sc.collection.objects.link(g)
    g.is_shadow_catcher = True


def camera(name, loc, target, lens=50, ortho=None, fstop=None):
    cd = bpy.data.cameras.new(name)
    if ortho:
        cd.type = 'ORTHO'
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    if fstop:
        cd.dof.use_dof = True
        cd.dof.focus_distance = (Vector(target) - Vector(loc)).length
        cd.dof.aperture_fstop = fstop
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = Vector(target) - Vector(loc)
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return ob


def aim_hdri(cam, base_rot_deg, base_view_deg=138.9):
    """Rotate the HDRI so a camera sees the same part of the backdrop that a camera
    looking along azimuth base_view_deg sees at base_rot_deg (seen = azimuth + rotation)."""
    w = bpy.context.scene.world
    if not w or not w.node_tree or "HDRI_Rotation" not in w.node_tree.nodes:
        return
    d = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    az = math.degrees(math.atan2(d.y, d.x))
    w.node_tree.nodes["HDRI_Rotation"].inputs["Rotation"].default_value = \
        (0, 0, math.radians(base_rot_deg + base_view_deg - az))


def render(cam, path, res=None):
    sc = bpy.context.scene
    sc.camera = cam
    if path.lower().endswith(".jpg"):
        sc.render.image_settings.file_format = 'JPEG'
        sc.render.image_settings.quality = 92
    else:
        sc.render.image_settings.file_format = 'PNG'
    if res:
        sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def export(objs, fbx_path=None, glb_path=None):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if fbx_path:
        bpy.ops.export_scene.fbx(filepath=fbx_path, use_selection=True, object_types={'MESH'}, embed_textures=True,
                                 apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
                                 axis_forward='Z', axis_up='Y', mesh_smooth_type='OFF',
                                 use_mesh_modifiers=True, add_leaf_bones=False, bake_space_transform=True,
                                 path_mode='COPY')
    if glb_path:
        bpy.ops.export_scene.gltf(filepath=glb_path, use_selection=True, export_format='GLB',
                                  export_yup=True, export_apply=True)
