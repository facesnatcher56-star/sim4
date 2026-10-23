"""Head parts of the folk (Blender 5.1): skull, face feature variants, hair styles, facial hair, marks, glasses, hats, scarf, bags.

Objects: ears_0..2, eyes_0..3, brows_0..3, nose_0..3, mouth_0..3, hair_0..15 (hair_9 = bald, no mesh), fhair_1..3,
mark_1..2, glasses_1..2, hat_1..2, scarf_1, bag_1..2.
Head-local coordinates: x right, y forward (face), z up, about the head centre, scaled by the head scale hs.

The skull is one surface P(phi, theta) (phi from the crown, theta from +x, the face at theta = 90 deg) with the jaw, chin,
brow, eye sockets and cheeks shaped into it. Features sit on that surface (Head.surf), and hair, beards and hats are shells
grown out of it with their thickness tapered to nothing at the hairline, so the edges are clean instead of clipped.
"""
import math
import random
from mathutils import Vector
from folk_mesh import W, Mesher, torus
from folk_body import sstep, lerp, torso_at, _tube_path

V = Vector
PI = math.pi
TAU = math.tau
HAIR_STYLES = 16
BALD = 9


def _g(t):
    return math.exp(-t * t)


def skull_pt(phi, th):
    """Head-local point on the skull."""
    sp, cp = math.sin(phi), math.cos(phi)
    ct, st = math.cos(th), math.sin(th)
    front = sstep(-0.3, 0.9, st)
    low = sstep(0.1, -0.95, cp)
    rx = 0.090 * (1 - 0.30 * low * (0.4 + 0.6 * front)) * (1 + 0.03 * sstep(0.2, -0.1, cp) * (1 - low))
    ry = 0.100 * (1 + 0.05 * (1 - front) * sstep(-0.3, 0.4, cp)) * (1 - 0.24 * low * (1 - front)) * (1 - 0.07 * front * (1 - abs(cp)))
    z = 0.112 * cp * (1 - 0.06 * sstep(-0.5, -1.0, cp))
    p = V((rx * sp * ct, ry * sp * st, z))
    p.y += 0.014 * front * sstep(-0.45, -0.85, cp) * sp                     # chin forward
    if p.y > 0:
        ax = abs(p.x)
        p.y += -0.006 * _g((ax - 0.036) / 0.017) * _g((p.z - 0.014) / 0.013)     # eye sockets
        p.y += 0.004 * _g((ax - 0.032) / 0.028) * _g((p.z - 0.042) / 0.010)      # brow ridge
        p.y += 0.003 * _g((ax - 0.052) / 0.020) * _g((p.z + 0.020) / 0.018)      # cheeks
    return p


def skull_n(phi, th):
    e = 1e-3
    a = skull_pt(phi + e, th) - skull_pt(phi - e, th)
    b = skull_pt(phi, th + e) - skull_pt(phi, th - e)
    n = a.cross(b)
    if n.length < 1e-9:
        return skull_pt(phi, th).normalized()
    n.normalize()
    if n.dot(skull_pt(phi, th)) < 0:
        n = -n
    return n


class Head:
    def __init__(self, hs):
        self.hs = hs
        self.hc = V((0, 0.005, 1.46 + 0.115 * hs - 0.012 * hs))

    def H(self, x, y, z):
        return self.hc + V((x, y, z)) * self.hs

    def L(self, p):
        """local Vector -> absolute"""
        return self.hc + p * self.hs

    def E(self, M, c, r, mat, wfn=None, **kw):
        M.ellipsoid(self.H(*c), tuple(v * self.hs for v in r), mat, wfn or W("head"), **kw)

    def T(self, M, a, b, prof, mat, wfn=None, seg=6):
        s = self.hs
        M.tube(self.H(*a), self.H(*b), [(t, ru * s, rv * s) for (t, ru, rv) in prof], mat, wfn or W("head"), seg=seg)

    def angles(self, x, z, front=True):
        """(phi, theta) of the skull point with local x and z on the front (or back) half."""
        phi = math.acos(max(-0.99, min(0.99, z / 0.112)))
        th = math.acos(max(-0.99, min(0.99, x / (0.09 * max(0.3, math.sin(phi))))))
        if not front:
            th = -th
        for _ in range(12):
            p = skull_pt(phi, th)
            fx, fz = p.x - x, p.z - z
            if abs(fx) + abs(fz) < 1e-6:
                break
            e = 1e-4
            a = (skull_pt(phi + e, th) - p) / e
            b = (skull_pt(phi, th + e) - p) / e
            det = a.x * b.z - b.x * a.z
            if abs(det) < 1e-9:
                break
            dphi = (fx * b.z - b.x * fz) / det
            dth = (a.x * fz - fx * a.z) / det
            phi = max(0.02, min(PI - 0.02, phi - dphi))
            th = th - dth
        return phi, th

    def surf(self, x, z, off=0.0):
        """Local point on the face at (x, z) pushed `off` along the normal, and the normal."""
        phi, th = self.angles(x, z)
        n = skull_n(phi, th)
        return skull_pt(phi, th) + n * off, n

    def put(self, M, x, z, off, r, mat, wfn=None, rings=4, seg=8):
        p, n = self.surf(x, z, off)
        self.E(M, tuple(p), r, mat, wfn, rings=rings, seg=seg)

    def path(self, M, pts_local, radii, mat, seg=6, wfn=None):
        """Tube through head-local bezier control points (absolute radii scaled by hs)."""
        _tube_path(M, tuple(self.L(p) for p in pts_local), [r * self.hs for r in radii], mat, wfn or W("head"), seg=seg)


def skull(M, hd):
    R, SEG = 16, 22
    rows = [[hd.L(skull_pt(0.0, 0.0))]]
    for i in range(1, R):
        phi = PI * i / R
        rows.append([hd.L(skull_pt(phi, TAU * k / SEG)) for k in range(SEG)])
    rows.append([hd.L(skull_pt(PI, 0.0))])
    M.loft(rows, "skin", W("head"), closed=True, caps=False)


# ------------------------------------------------------------------ face features (index = variant)
def ears(M, hd, i):
    sz = [(0.011, 0.019, 0.030), (0.015, 0.025, 0.038), (0.010, 0.017, 0.040)][i]
    dz = [-0.004, -0.008, 0.008][i]
    for sx in (-1, 1):
        p = skull_pt(math.acos(dz / 0.112), 0.0 if sx > 0 else PI)
        hd.E(M, (p.x + sx * 0.004, -0.006, dz), sz, "skin", rings=6, seg=10)
        hd.E(M, (p.x + sx * 0.010, -0.004, dz + 0.002), (sz[0] * 0.5, sz[1] * 0.62, sz[2] * 0.7), "skin", rings=4, seg=8)  # rim


# eyes: (spacing, size scale, height scale, z)
EYES = [(0.036, 1.0, 1.0, 0.014), (0.040, 1.12, 1.0, 0.014), (0.037, 1.18, 0.66, 0.012), (0.031, 0.90, 1.0, 0.012)]


def eyes(M, hd, i):
    sp, k, kh, z = EYES[i]
    for sx in (-1, 1):
        x = sx * sp
        hd.put(M, x, z, -0.001, (0.0165 * k, 0.008, 0.0115 * k * kh), "eyewhite", rings=6, seg=12)
        hd.put(M, x + sx * 0.001, z, 0.0040, (0.0088 * k, 0.0035, 0.0088 * k * min(1.0, kh * 1.25)), "eyes", rings=5, seg=12)
        hd.put(M, x + sx * 0.001, z, 0.0062, (0.0042 * k, 0.0022, 0.0042 * k * min(1.0, kh * 1.25)), "frame", rings=4, seg=8)
        hd.put(M, x + sx * 0.001 + 0.003 * k, z + 0.0035 * k * kh, 0.0072, (0.0016, 0.001, 0.0016), "eyewhite", rings=3, seg=6)
        # upper lid: a thin skin crease over the eye white, so the eye reads as set into the face
        p0, _ = hd.surf(x - 0.019 * k, z + 0.002, 0.0)
        p1, _ = hd.surf(x, z + 0.013 * k * kh, 0.006)
        p2, _ = hd.surf(x + 0.019 * k, z + 0.002, 0.0)
        hd.path(M, (p0, p1, p2) if sx > 0 else (p2, p1, p0), [0.0015, 0.0028, 0.0028, 0.0015], "skin", seg=5)


# brows: inner point, peak, outer point as (x, z) and the thickness at the inner end
BROWS = [((0.013, 0.040), (0.036, 0.047), (0.058, 0.040), 0.0042),
         ((0.012, 0.039), (0.036, 0.046), (0.058, 0.040), 0.0065),
         ((0.014, 0.039), (0.040, 0.054), (0.060, 0.043), 0.0040),
         ((0.013, 0.035), (0.036, 0.041), (0.058, 0.044), 0.0045)]


def brows(M, hd, i):
    a, b, c, t = BROWS[i]
    for sx in (-1, 1):
        pts = [hd.surf(sx * q[0], q[1], 0.002)[0] for q in (a, b, c)]
        pts[1] = pts[1] + (pts[1] - (pts[0] + pts[2]) * 0.5) * 1.0         # bezier control so the curve passes the peak
        hd.path(M, pts, [t, t * 0.95, t * 0.75, t * 0.45], "hair", seg=6)


# noses: rows (z, how far it stands out, half width) from the bridge down to the nostrils
NOSES = [[(0.024, 0.000, 0.006), (0.010, 0.004, 0.0065), (-0.004, 0.008, 0.0075), (-0.016, 0.013, 0.0095), (-0.025, 0.012, 0.0140), (-0.031, 0.006, 0.0150)],
         [(0.026, 0.001, 0.0065), (0.010, 0.007, 0.0075), (-0.006, 0.013, 0.0085), (-0.020, 0.019, 0.0105), (-0.030, 0.016, 0.0150), (-0.036, 0.008, 0.0160)],
         [(0.018, 0.000, 0.0055), (0.006, 0.002, 0.0060), (-0.006, 0.006, 0.0075), (-0.015, 0.010, 0.0100), (-0.022, 0.009, 0.0125), (-0.027, 0.004, 0.0130)],
         [(0.024, 0.000, 0.0070), (0.010, 0.004, 0.0085), (-0.004, 0.008, 0.0105), (-0.016, 0.012, 0.0135), (-0.025, 0.012, 0.0190), (-0.031, 0.006, 0.0200)]]


def nose(M, hd, i):
    rows = NOSES[i]
    seg = 10
    out = []
    top = hd.surf(0.0, rows[0][0] + 0.006, -0.004)[0]
    out.append([hd.L(top)])
    for (z, pr, hw) in rows:
        base, _ = hd.surf(0.0, z, 0.0)
        ring = []
        for k in range(seg):
            a = TAU * k / seg
            ca, sa = math.cos(a), math.sin(a)
            y = base.y - 0.006 + ((pr + 0.006) * sa ** 0.8 if sa > 0 else 0.006 * sa)
            ring.append(hd.L(V((hw * ca, y, z))))
        out.append(ring)
    bot = hd.surf(0.0, rows[-1][0] - 0.004, -0.004)[0]
    out.append([hd.L(bot)])
    M.loft(out, "skin", W("head"), closed=True, caps=False)
    for sx in (-1, 1):                                                       # nostril wings
        z, pr, hw = rows[-2]
        hd.put(M, sx * hw * 0.80, z - 0.004, 0.0, (0.0042, 0.0045, 0.0040), "skin", rings=4, seg=8)


# mouths: (half width, upper lip, lower lip, z, smile)
MOUTHS = [(0.021, 0.0034, 0.0046, -0.054, 0.002), (0.020, 0.0046, 0.0062, -0.055, 0.001),
          (0.015, 0.0028, 0.0038, -0.053, 0.000), (0.026, 0.0034, 0.0044, -0.052, 0.007)]


def _lip(M, hd, w, r, z, smile, dz, mat):
    n = 9
    rows = []
    for j in range(n):
        u = -1 + 2 * j / (n - 1)
        x = u * w
        zz = z + smile * u * u + dz * (1 - u * u)
        c, nn = hd.surf(x, zz, 0.0)
        rr = r * (1 - u * u) ** 0.5 + 0.0012
        rows.append([hd.L(c + V((0, rr * 0.8 * math.cos(TAU * k / 6), rr * math.sin(TAU * k / 6)))) for k in range(6)])
    rows.insert(0, [rows[0][0] * 0 + sum(rows[0], V()) / 6])
    rows.append([sum(rows[-1], V()) / 6])
    M.loft(rows, mat, W("head"), closed=True, caps=False)


def mouth(M, hd, i):
    w, ru, rl, z, smile = MOUTHS[i]
    _lip(M, hd, w, ru, z + 0.0032, smile, 0.0, "mouth")
    _lip(M, hd, w * 0.9, rl, z - 0.0045, smile, -0.0012, "mouth")


# ------------------------------------------------------------------ shells grown from the skull
def shell(M, hd, cols, prow, thick, mat, closed, wfn=None, nrow=10, pole=False):
    """cols: list of theta; prow(theta) -> (phi0, phi1) range; thick(u, v, theta) -> offset (u along phi 0..1, v across 0..1).
    pole=True starts every column at the crown (one shared vertex)."""
    rows = [[] for _ in range(nrow)]
    nc = len(cols)
    for j, th in enumerate(cols):
        p0, p1 = prow(th)
        v = j / max(1, nc - 1)
        for i in range(nrow):
            u = i / (nrow - 1)
            phi = lerp(p0, p1, u)
            rows[i].append(hd.L(skull_pt(phi, th) + skull_n(phi, th) * thick(u, v, th)))
    if pole:
        rows[0] = [hd.L(skull_pt(0.0, 0.0) + V((0, 0, thick(0.0, 0.5, 0.0))))]
    M.loft(rows, mat, wfn or W("head"), closed=closed, caps=False)


def _alpha(th):
    """Angle from the face direction, 0..pi."""
    d = (th - PI / 2 + PI) % TAU - PI
    return abs(d)


def _keys(keys, a):
    """Smooth interpolation of (alpha_deg, value) keys."""
    a = math.degrees(a)
    for (a0, v0), (a1, v1) in zip(keys, keys[1:]):
        if a0 <= a <= a1:
            t = (a - a0) / (a1 - a0)
            t = t * t * (3 - 2 * t)
            return lerp(v0, v1, t)
    return keys[-1][1]


def zphi(z):
    return math.acos(max(-0.99, min(0.99, z / 0.112)))


def cap(M, hd, line, thick, top=0.0, back=0.0, front=0.0, edge=0.003, mat="hair", seg=36, nrow=11, side_bulge=0.0, locks=0):
    """Hair (or hat) cap: line = [(alpha_deg, hairline z)] from the face (0) round to the back (180)."""
    cols = [TAU * k / seg for k in range(seg)]

    def prow(th):
        return 0.0, zphi(_keys(line, _alpha(th)))

    def tk(u, v, th):
        a = _alpha(th)
        t = thick + top * (1 - u) ** 2 + back * sstep(90, 180, math.degrees(a)) * math.sin(PI * min(1, u * 1.1)) \
            + front * sstep(80, 0, math.degrees(a)) * math.sin(PI * min(1.0, u * 1.2) * 0.9) \
            + side_bulge * _g((math.degrees(a) - 95) / 40) * math.sin(PI * u)
        if locks:                                         # a few soft locks towards the hairline
            t *= 1 + 0.35 * sstep(0.35, 0.9, u) * math.sin(th * locks) ** 2
        return edge + (t - edge) * sstep(1.0, 0.80, u) if u > 0.80 else t
    shell(M, hd, cols, prow, tk, mat, True, nrow=nrow, pole=True)


def fall(M, hd, z_end, thick, span=200.0, z_top=0.02, flare=0.04, front_z=None, mat="hair", seg=17, nrow=9):
    """Hair hanging from the back and sides of the head down to head-local z_end, draped over the neck and shoulders.
    span = degrees covered round the back (centred on the back of the head). front_z: shorter ends at the sides (face framing)."""
    half = math.radians(span) / 2
    cols = [-PI / 2 - half + 2 * half * k / (seg - 1) for k in range(seg)]
    outer, inner = [], []
    for i in range(nrow):
        u = i / (nrow - 1)
        ro, ri = [], []
        for j, th in enumerate(cols):
            v = abs(j / (seg - 1) * 2 - 1)                       # 0 at the back, 1 at the sides
            ze = z_end if front_z is None else lerp(z_end, front_z, sstep(0.55, 1.0, v))
            z = lerp(z_top, ze, u)
            phi = zphi(max(z, -0.06))
            base = skull_pt(phi, th)
            tk = thick * (1 - 0.75 * sstep(0.6, 1.0, v)) * lerp(0.55, 1.0, sstep(0.0, 0.2, u))
            r = V((base.x, base.y, 0)).length + tk
            if z < -0.06:                                        # below the jaw the hair hangs straight, flaring a little
                r += flare * (-0.06 - z) / 0.3
            d = V((math.cos(th), math.sin(th), 0))
            p = V((d.x * r * (1.0 if base.x == 0 else 1.0), d.y * r, z))
            ab = hd.L(p)
            ab.x *= lerp(1.0, 0.58, sstep(1.48, 1.25, ab.z))           # long hair gathers towards the middle of the back
            if ab.z < 1.42:                                      # rest on the shoulders and back instead of passing through
                hw, fr, bk, sq = torso_at(ab.z - 0.035, (1, 1, 1, 1), 1.0)
                dx, dy = ab.x, ab.y
                ang = math.atan2(dy / (fr if dy > 0 else bk), dx / hw)
                rr = math.hypot(dx, dy)
                tx = hw * math.copysign(abs(math.cos(ang)) ** (2 / sq), math.cos(ang))
                ty = (fr if dy > 0 else bk) * math.copysign(abs(math.sin(ang)) ** (2 / sq), math.sin(ang))
                need = math.hypot(tx, ty) + 0.034
                if rr < need:
                    s = need / max(1e-6, rr)
                    ab = V((ab.x * s, ab.y * s, ab.z))
            ro.append(ab)
            ctr = V((hd.hc.x, hd.hc.y, ab.z))
            ri.append(ctr + (ab - ctr) * (1 - min(0.5, 0.8 * tk * hd.hs / max(0.02, (ab - ctr).length))))
        outer.append(ro)
        inner.append(ri)
    tip = [[(a + b) * 0.5 + V((0, 0, -0.004)) for a, b in zip(outer[-1], inner[-1])]]
    rows = outer + tip + list(reversed(inner))
    neck_z = hd.hc.z - 0.10 * hd.hs

    def wf(p):
        k = sstep(neck_z, neck_z - 0.12, p.z)
        return {"head": 1 - k, "neck": k * 0.4, "chest": k * 0.6}
    M.loft(rows, mat, wf, closed=False, caps=False)


def puffs(M, hd, n, line_z, r, seed, mat="hair", lift=0.0):
    """n round curls scattered over the cap above head-local z line_z, half sunk into it."""
    rnd = random.Random(seed)
    for k in range(n):
        a = k * 2.399963
        zf = 1 - (k + 0.5) / n
        z = lerp(line_z, 0.112, zf ** 0.8)
        phi = zphi(z)
        th = a
        if _alpha(th) < 0.6 and z < 0.07:
            th = -th
        p = skull_pt(phi, th) + skull_n(phi, th) * (r * 0.25 + lift)
        rr = r * rnd.uniform(0.85, 1.15)
        hd.E(M, tuple(p), (rr, rr, rr), mat, rings=4, seg=7)


# hairline presets: (alpha_deg, z): face, temple, above the ear, behind the ear, nape
LINE = [(0, 0.064), (40, 0.050), (70, 0.016), (88, 0.030), (108, -0.028), (140, -0.052), (180, -0.062)]
LINE_HIGH = [(0, 0.070), (40, 0.058), (75, 0.040), (100, 0.034), (130, -0.010), (180, -0.040)]
LINE_FRINGE = [(0, 0.036), (35, 0.040), (75, 0.030), (100, 0.012), (130, -0.040), (180, -0.065)]
LINE_EARS = [(0, 0.060), (40, 0.046), (75, 0.024), (100, -0.030), (130, -0.055), (180, -0.065)]


def hair(M, hd, i):
    if i == 0:        # short crop
        cap(M, hd, LINE, 0.009, top=0.008, front=0.006, locks=6)
    elif i == 1:      # buzz cut
        cap(M, hd, LINE, 0.0035, edge=0.001)
    elif i == 2:      # long (to the shoulders), ears covered
        cap(M, hd, LINE_EARS, 0.012, top=0.006, side_bulge=0.008, locks=7)
        fall(M, hd, -0.24, 0.016, span=215, front_z=-0.13, flare=0.03)
    elif i == 3:      # ponytail
        cap(M, hd, LINE, 0.006, top=0.003)
        hd.E(M, (0, -0.112, 0.020), (0.022, 0.018, 0.020), "accent", rings=4, seg=8)          # hair tie
        hd.path(M, (V((0, -0.118, 0.022)), V((0, -0.165, -0.03)), V((0, -0.14, -0.23))), [0.024, 0.028, 0.026, 0.020, 0.010], "hair", seg=8)
    elif i == 4:      # spiky
        cap(M, hd, LINE, 0.008)
        for k in range(11):
            a = k * 2.399963
            z = lerp(0.05, 0.112, (k + 0.5) / 11)
            phi = zphi(z) * 0.95
            th = a if _alpha(a) > 0.4 or z > 0.09 else -a
            b = skull_pt(phi, th) + skull_n(phi, th) * 0.004
            n = (skull_n(phi, th) + V((0, 0.25 if _alpha(th) < 1.2 else -0.1, 0.5))).normalized()
            hd.path(M, (b, b + n * 0.03, b + n * 0.06), [0.022, 0.016, 0.009, 0.002], "hair", seg=6)
    elif i == 5:      # afro
        cap(M, hd, LINE, 0.036, top=0.022, back=0.014, side_bulge=0.016, front=-0.006, nrow=12, locks=8, edge=0.006)
    elif i == 6:      # short curls
        cap(M, hd, LINE, 0.006, edge=0.002)
        puffs(M, hd, 40, 0.030, 0.013, 6)
    elif i == 7:      # bun
        cap(M, hd, LINE, 0.006, top=0.002)
        hd.E(M, (0, -0.045, 0.135), (0.046, 0.044, 0.040), "hair", rings=7, seg=12)
        hd.T(M, (0, -0.040, 0.100), (0, -0.044, 0.112), [(0, 0.034, 0.032), (1, 0.034, 0.032)], "accent", seg=10)
    elif i == 8:      # braids
        cap(M, hd, LINE_EARS, 0.007)
        for sx in (-1, 1):
            for k in range(6):
                hd.E(M, (sx * 0.078, -0.055 + k * 0.004, -0.06 - k * 0.042), (0.020, 0.019, 0.026), "hair", rings=5, seg=8)
            hd.E(M, (sx * 0.078, -0.033, -0.318), (0.012, 0.012, 0.012), "accent", rings=4, seg=6)
            hd.E(M, (sx * 0.078, -0.030, -0.338), (0.015, 0.014, 0.022), "hair", rings=4, seg=7)
    elif i == 9:      # bald
        pass
    elif i == 10:     # mohawk
        cap(M, hd, LINE, 0.0015, edge=0.0008)
        rows = []
        for k in range(12):
            t = k / 11
            phi = lerp(0.95, -1.9, t)            # from the forehead over the crown to the back
            th = PI / 2 if phi >= 0 else -PI / 2
            b = skull_pt(abs(phi), th)
            nrm = skull_n(abs(phi), th)
            h = 0.010 + 0.032 * math.sin(PI * min(1, t * 1.1)) ** 0.6
            row = []
            for j in range(8):
                a2 = TAU * j / 8
                row.append(hd.L(b + nrm * (h * 0.5 + 0.5 * h * math.sin(a2)) + V((0.013 * math.cos(a2) * (1 - 0.3 * max(0, math.sin(a2))), 0, 0))))
            rows.append(row)
        rows.insert(0, [sum(rows[0], V()) / 8])
        rows.append([sum(rows[-1], V()) / 8])
        M.loft(rows, "hair", W("head"), closed=True, caps=False)
    elif i == 11:     # long straight, centre parting
        cap(M, hd, LINE, 0.010, top=0.002, side_bulge=0.010)
        fall(M, hd, -0.36, 0.014, span=215, front_z=-0.16, flare=0.02)
    elif i == 12:     # bob with a fringe
        cap(M, hd, LINE_FRINGE, 0.014, top=0.006, side_bulge=0.012, edge=0.006)
        fall(M, hd, -0.105, 0.020, span=250, front_z=-0.085, flare=0.0)
    elif i == 13:     # quiff
        cap(M, hd, LINE, 0.008, top=0.010, front=0.018)
    elif i == 14:     # pigtails
        cap(M, hd, LINE, 0.008, top=0.003)
        for sx in (-1, 1):
            hd.E(M, (sx * 0.098, -0.03, 0.045), (0.016, 0.016, 0.016), "accent", rings=4, seg=8)
            hd.path(M, (V((sx * 0.104, -0.035, 0.045)), V((sx * 0.135, -0.04, 0.02)), V((sx * 0.118, -0.035, -0.12))),
                    [0.020, 0.025, 0.022, 0.012], "hair", seg=8)
    else:             # shaggy
        cap(M, hd, LINE_FRINGE, 0.016, top=0.008, side_bulge=0.012, edge=0.007, locks=9)
        fall(M, hd, -0.13, 0.018, span=200, front_z=-0.09, flare=0.02)


# ------------------------------------------------------------------ face extras
def _jaw_shell(M, hd, top_z, centre_z, thick, mat="hair"):
    """Beard over the jaw and chin: from the sideburns (top_z at the ears) down under the chin; centre_z = top at the chin middle."""
    cols = [lerp(-0.25, PI + 0.25, k / 16) for k in range(17)]

    def prow(th):
        a = _alpha(th)
        z = lerp(centre_z, top_z, sstep(0.25, 1.4, a))
        return zphi(z), lerp(2.62, 2.40, sstep(0.2, 1.4, a))

    def tk(u, v, th):
        e = sstep(0.0, 0.15, u) * sstep(0.0, 0.10, v) * sstep(1.0, 0.90, v) * sstep(1.0, 0.75, u)
        return 0.001 + thick * e
    shell(M, hd, cols, prow, tk, mat, False, nrow=9)


def moustache(M, hd, w=0.027, r=0.0055):
    pts = [hd.surf(x, z, 0.003)[0] for (x, z) in ((-w, -0.050), (0.0, -0.037), (w, -0.050))]
    pts[1] = pts[1] + V((0, 0.003, -0.004))
    hd.path(M, pts, [0.003, r, r, 0.003], "hair", seg=6)
    hd.path(M, (pts[0], (pts[0] + pts[1]) * 0.5 + V((0, 0.002, 0.004)), pts[1]), [0.003, r * 0.9, r * 0.9, r], "hair", seg=6)


def fhair(M, hd, i):
    if i == 1:        # moustache
        moustache(M, hd)
    elif i == 2:      # goatee + moustache
        moustache(M, hd, 0.024, 0.005)
        cols = [lerp(PI / 2 - 0.35, PI / 2 + 0.35, k / 8) for k in range(9)]

        def tk(u, v, th):
            return 0.001 + 0.009 * sstep(0.0, 0.2, u) * math.sin(PI * v) ** 0.6 * sstep(1.0, 0.8, u)
        shell(M, hd, cols, lambda th: (zphi(-0.068), 2.7), tk, "hair", False, nrow=8)
    else:             # full beard
        moustache(M, hd)
        _jaw_shell(M, hd, 0.006, -0.066, 0.008)


def mark(M, hd, i):
    if i == 1:        # freckles
        pts = [(-0.045, -0.010), (-0.056, -0.018), (-0.036, -0.020), (-0.026, -0.006), (-0.050, -0.002),
               (0.045, -0.010), (0.056, -0.018), (0.036, -0.020), (0.026, -0.006), (0.050, -0.002), (-0.008, 0.002), (0.008, 0.0)]
        for (x, z) in pts:
            hd.put(M, x, z, 0.0, (0.0035, 0.0015, 0.0035), "freckles", rings=3, seg=6)
    else:             # beauty mark
        hd.put(M, 0.033, -0.044, 0.0, (0.0045, 0.002, 0.0045), "freckles", rings=3, seg=6)


def glasses(M, hd, i):
    sp, z = EYES[0][0], 0.014
    s = hd.hs
    for sx in (-1, 1):
        c, n = hd.surf(sx * sp, z, 0.0)
        c = V((c.x, c.y + 0.014, c.z))
        torus(M, hd.L(c), 0.024 * s, 0.0024 * s, "frame", W("head"), n=16, seg=5, square=0.0 if i == 1 else 1.0)
        side = skull_pt(zphi(z + 0.004), 0.0 if sx > 0 else PI)
        hd.T(M, (sx * (sp + 0.024), c.y, z), (side.x + sx * 0.004, -0.01, z + 0.006), [(0, 0.0022, 0.0022), (1, 0.0022, 0.0022)], "frame", seg=4)
    br, _ = hd.surf(0.0, z + 0.004, 0.0)
    hd.T(M, (-sp + 0.024, br.y + 0.010, z + 0.003), (sp - 0.024, br.y + 0.010, z + 0.003), [(0, 0.0022, 0.0022), (1, 0.0022, 0.0022)], "frame", seg=4)


# ------------------------------------------------------------------ hats, scarf, bags
def hat(M, hd, i):
    if i == 1:        # cap with brim
        line = [(0, 0.052), (60, 0.046), (120, 0.030), (180, 0.024)]
        cap(M, hd, line, 0.028, top=0.004, edge=0.024, mat="accent", nrow=9)
        rows = []
        for k in range(5):
            t = k / 4
            row = []
            for j in range(9):
                a = lerp(0.25 * PI, 0.75 * PI, j / 8)
                b = skull_pt(zphi(0.050), a)
                r = V((b.x, b.y, 0)).length + 0.028 + 0.075 * t * math.sin(a) ** 2
                row.append(hd.L(V((math.cos(a) * r, math.sin(a) * r, 0.052 - 0.012 * t * t))))
            rows.append(row)
        thick = [[p + V((0, 0, 0.006 * hd.hs)) for p in r] for r in rows]
        M.loft(rows + list(reversed(thick)) + [rows[0]], "accent", W("head"), closed=False, caps=False)
    else:             # beanie with cuff
        line = [(0, 0.045), (60, 0.035), (120, 0.010), (180, 0.000)]
        cap(M, hd, line, 0.026, top=0.022, edge=0.022, mat="accent", nrow=9)
        cap_band = [(0, 0.045), (60, 0.035), (120, 0.010), (180, 0.000)]
        cols = [TAU * k / 28 for k in range(28)]
        shell(M, hd, cols, lambda th: (zphi(_keys(cap_band, _alpha(th)) + 0.032), zphi(_keys(cap_band, _alpha(th)) - 0.002)),
              lambda u, v, th: 0.031, "accent", True, nrow=3)
        hd.E(M, (0, -0.012, 0.150), (0.024, 0.024, 0.022), "accent", rings=5, seg=8)


def scarf(M, hd):
    wn = lambda p: {"neck": 0.6, "chest": 0.4}
    M.tube(V((0, 0.004, 1.385)), V((0, 0.006, 1.47)), [(0, 0.112, 0.098), (0.35, 0.082, 0.078), (1, 0.068, 0.066)], "accent", wn, seg=14)
    _tube_path(M, (V((0.05, 0.088, 1.42)), V((0.07, 0.125, 1.33)), V((0.06, 0.122, 1.17))), [0.020, 0.020, 0.020, 0.019], "accent",
               lambda p: {"chest": 1.0}, seg=6, flat=0.45)


def bag(M, hd, i):
    wc = lambda p: {"chest": 0.7, "spine": 0.3}
    if i == 1:        # backpack
        M.ellipsoid(V((0, -0.150, 1.19)), (0.115, 0.062, 0.155), "accent", wc, rings=7, seg=12)
        M.ellipsoid(V((0, -0.205, 1.12)), (0.080, 0.022, 0.060), "accent", wc, rings=4, seg=8)       # front pocket
        for sx in (-1, 1):
            _tube_path(M, (V((sx * 0.085, -0.09, 1.33)), V((sx * 0.11, 0.0, 1.43)), V((sx * 0.12, 0.112, 1.30))), [0.008] * 4, "accent", wc, seg=5, flat=0.4)
            _tube_path(M, (V((sx * 0.12, 0.112, 1.30)), V((sx * 0.15, 0.06, 1.12)), V((sx * 0.10, -0.10, 1.08))), [0.008] * 4, "accent", wc, seg=5, flat=0.4)
    else:             # satchel: strap across the chest + bag at the hip
        wh = lambda p: {"chest": 0.5, "hips": 0.5}
        _tube_path(M, (V((0.10, 0.02, 1.40)), V((0.0, 0.14, 1.27)), V((-0.17, 0.10, 1.05))), [0.010] * 4, "accent", wc, seg=5, flat=0.4)
        _tube_path(M, (V((0.10, 0.02, 1.40)), V((0.04, -0.13, 1.25)), V((-0.17, -0.06, 1.02))), [0.010] * 4, "accent", wc, seg=5, flat=0.4)
        M.ellipsoid(V((-0.215, 0.015, 0.95)), (0.040, 0.115, 0.085), "accent", wh, rings=6, seg=10)
        M.ellipsoid(V((-0.24, 0.015, 0.99)), (0.018, 0.112, 0.045), "accent", wh, rings=4, seg=8)          # flap
