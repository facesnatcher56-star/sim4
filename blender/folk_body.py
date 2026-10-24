"""Body parts of the folk (Blender 5.1): base body, tops, bottoms, shoes. Coordinates are adult units (metres, Z up, +Y forward).

Objects produced (each one skinned to the same rig, toggled by Godot):
  body (neck, arms, hands, skull - always shown), legs_skin (bare legs - always under bottoms),
  top_0..6 (tee hoodie sweater shirt dress apron uniform), bottom_0..2 (trousers shorts skirt) - both with body-shape morphs,
  shoes_0..3 (shoes boots barefoot sneakers).

Limbs are one continuous loft per arm / leg (shoulder to wrist, hip to ankle) with rings packed around the elbow and knee and
weights blended across the joint, so they bend without a seam or a ball. Clothes reuse the same rings and weights, grown
outward, so they bend exactly like the skin under them.
"""
import math
from mathutils import Vector
from folk_mesh import W, ramp, finish_morph, Mesher

V = Vector
TAU = math.tau
TOPS = ["tee", "hoodie", "sweater", "shirt", "dress", "apron", "uniform"]
BOTTOMS = ["trousers", "shorts", "skirt"]
SHOES = ["shoes", "boots", "barefoot", "sneakers"]


def sstep(a, b, x):
    t = ramp(x, a, b)
    return t * t * (3 - 2 * t)


def spow(v, e):
    return math.copysign(abs(v) ** e, v)


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ torso
# (z, half width, front depth, back depth, squareness, band). band = which body-shape factor scales the width.
TORSO = [
    (0.855, 0.030, 0.026, 0.030, 2.0, "h"),     # crotch
    (0.872, 0.105, 0.066, 0.078, 2.2, "h"),
    (0.900, 0.164, 0.086, 0.104, 2.3, "h"),     # seat
    (0.940, 0.176, 0.092, 0.110, 2.4, "h"),     # widest at the hips
    (0.985, 0.165, 0.094, 0.098, 2.4, "h"),
    (1.035, 0.152, 0.094, 0.088, 2.3, "hw"),
    (1.085, 0.141, 0.092, 0.083, 2.2, "w"),     # waist
    (1.145, 0.150, 0.098, 0.088, 2.3, "wc"),
    (1.205, 0.166, 0.108, 0.094, 2.5, "c"),     # chest
    (1.265, 0.178, 0.110, 0.096, 2.6, "c"),
    (1.315, 0.182, 0.098, 0.094, 2.5, "c"),
    (1.350, 0.176, 0.080, 0.084, 2.6, "s"),     # top of the shoulders
    (1.378, 0.126, 0.064, 0.070, 2.2, "s"),
    (1.398, 0.068, 0.050, 0.054, 2.0, "n"),     # base of the neck
]


def _band(sh, band):
    c, w, h, d = sh
    return {"h": h, "hw": (h + w) * 0.5, "w": w, "wc": (w + c) * 0.5, "c": c, "s": (1 + c) * 0.5, "n": 1.0}[band]


def torso_at(z, sh, wd):
    """Interpolated (half width, front, back, squareness) at height z, shaped by the body morph."""
    rows = [(r[0], r[1] * wd * _band(sh, r[5]), r[2] * sh[3], r[3] * sh[3], r[4]) for r in TORSO]
    if z <= rows[0][0]:
        return rows[0][1:]
    for a, b in zip(rows, rows[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(lerp(a[i], b[i], t) for i in range(1, 5))
    return rows[-1][1:]


def torso_ring(z, sh, wd, grow=0.0, seg=16, pec=0.0, scale=1.0):
    hw, fr, bk, sq = torso_at(z, sh, wd)
    e = 2.0 / sq
    pts = []
    for k in range(seg):
        a = TAU * k / seg
        ca, sa = math.cos(a), math.sin(a)
        x = (hw + grow) * scale * spow(ca, e)
        y = ((fr if sa > 0 else bk) + grow) * scale * spow(sa, e)
        if pec and sa > 0:
            y += pec * math.exp(-((abs(x) - 0.075) / 0.05) ** 2) * sstep(1.15, 1.22, z) * (1 - sstep(1.29, 1.33, z)) * sa
        pts.append(V((x, y, z)))
    return pts


def torso_zs(z0, z1):
    zs = [z0] + [r[0] for r in TORSO if z0 < r[0] < z1] + [z1]
    out = [zs[0]]
    for z in zs[1:]:                 # split long gaps so the silhouette stays round
        n = max(1, int((z - out[-1]) / 0.05 + 0.999))
        out += [lerp(out[-1], z, (i + 1) / n) for i in range(n)]
    return out


def w_torso(p):
    z = p.z
    a = sstep(0.96, 1.06, z)
    b = sstep(1.10, 1.20, z)
    d = {"hips": 1 - a, "spine": a * (1 - b), "chest": a * b}
    if z > 1.36:
        n = sstep(1.36, 1.43, z)
        d = {"chest": 1 - n * 0.6, "neck": n * 0.6}
    if z > 1.27 and abs(p.x) > 0.12:     # the shoulder caps follow the shoulder bone a little
        k = sstep(0.12, 0.18, abs(p.x)) * sstep(1.27, 1.33, z) * 0.3
        d = {b: w * (1 - k) for b, w in d.items()}
        d["shoulder_" + ("L" if p.x < 0 else "R")] = k
    if z < 0.95 and abs(p.x) > 0.03:     # the seat follows the thighs a little
        k = 0.35 * sstep(0.95, 0.88, z) * sstep(0.03, 0.10, abs(p.x))
        d = {b: w * (1 - k) for b, w in d.items()}
        d["thigh_" + ("L" if p.x < 0 else "R")] = k
    return d


def torso_part(M, sh, wd, z0, z1, grow, mat="shirt", seg=16, pec=0.006, close_bottom=False, close_top=False):
    zs = torso_zs(z0, z1)
    rows = [torso_ring(z, sh, wd, grow, seg, pec) for z in zs]
    if close_bottom:
        rows.insert(0, [V((0, -0.004, z0 - 0.006))])
    if close_top:
        rows.append([V((0, 0, z1 + 0.004))])
    M.loft(rows, mat, w_torso, closed=True, caps=False)


# ------------------------------------------------------------------ limbs (one loft per limb, rings along a bone chain)
# arm profile: (s along the chain from the shoulder top, lateral radius, front radius, outward offset, forward offset)
ARM = [(0.000, 0.024, 0.026, -0.006, 0.0), (0.015, 0.044, 0.046, -0.002, 0.0), (0.040, 0.052, 0.052, 0.0, 0.0),
       (0.080, 0.051, 0.050, 0.002, 0.0), (0.125, 0.046, 0.047, 0.0, 0.0), (0.159, 0.044, 0.046, 0.0, 0.004),
       (0.214, 0.040, 0.041, 0.0, 0.002), (0.259, 0.037, 0.037, 0.0, 0.0), (0.284, 0.036, 0.035, 0.0, -0.002),
       (0.299, 0.036, 0.035, 0.0, -0.004), (0.319, 0.038, 0.036, 0.0, -0.002), (0.359, 0.040, 0.037, 0.002, 0.0),
       (0.404, 0.037, 0.033, 0.0, 0.0), (0.454, 0.032, 0.028, 0.0, 0.0), (0.504, 0.027, 0.023, 0.0, 0.0),
       (0.539, 0.025, 0.020, 0.0, 0.0)]
# leg profile from the top of the thigh (z 0.96) down to the ankle
LEG = [(0.000, 0.070, 0.078, 0.0, 0.0), (0.040, 0.078, 0.088, 0.0, 0.0), (0.110, 0.080, 0.087, 0.0, 0.002),
       (0.200, 0.076, 0.080, 0.0, 0.004), (0.290, 0.066, 0.068, 0.0, 0.003), (0.370, 0.056, 0.058, 0.0, 0.002),
       (0.420, 0.052, 0.054, 0.0, 0.004), (0.450, 0.050, 0.054, 0.0, 0.007), (0.475, 0.049, 0.053, 0.0, 0.006),
       (0.505, 0.049, 0.051, 0.0, 0.0), (0.550, 0.051, 0.054, 0.0, -0.008), (0.610, 0.053, 0.057, 0.0, -0.012),
       (0.680, 0.046, 0.049, 0.0, -0.008), (0.750, 0.037, 0.038, 0.0, -0.003), (0.820, 0.030, 0.031, 0.0, 0.0),
       (0.860, 0.028, 0.032, 0.0, 0.004), (0.875, 0.028, 0.032, 0.0, 0.006)]


class Chain:
    """A bone chain (list of joint points) for one side; maps s (distance from the first point) to a centre and frame."""
    def __init__(self, pts, sx):
        self.p = [V(q) for q in pts]
        self.sx = sx
        self.L = [0.0]
        for a, b in zip(self.p, self.p[1:]):
            self.L.append(self.L[-1] + (b - a).length)

    def seg(self, s):
        for i in range(len(self.p) - 1):
            if s <= self.L[i + 1] or i == len(self.p) - 2:
                return i
        return 0

    def at(self, s):
        i = self.seg(s)
        t = (s - self.L[i]) / max(1e-6, self.L[i + 1] - self.L[i])
        c = self.p[i].lerp(self.p[i + 1], t)
        tan = (self.p[i + 1] - self.p[i]).normalized()
        for j in range(1, len(self.p) - 1):          # ease the frame through each joint
            k = sstep(-0.05, 0.05, s - self.L[j]) - 0.5
            if abs(s - self.L[j]) < 0.05:
                d0 = (self.p[j] - self.p[j - 1]).normalized()
                d1 = (self.p[j + 1] - self.p[j]).normalized()
                tan = d0.lerp(d1, k + 0.5).normalized()
        u = V((1, 0, 0))
        u = (u - tan * u.dot(tan)).normalized()
        v = tan.cross(u)
        if v.y < 0:
            v = -v
        return c, u, v

    def ring(self, s, rx, ry, dx, dy, grow=0.0, seg=12):
        c, u, v = self.at(s)
        pts = []
        for k in range(seg):
            a = TAU * k / seg
            pts.append(c + u * ((rx + grow) * math.cos(a) + dx * self.sx) + v * ((ry + grow) * math.sin(a) + dy))
        return pts


def prof_at(prof, s):
    if s <= prof[0][0]:
        return prof[0][1:]
    for a, b in zip(prof, prof[1:]):
        if a[0] <= s <= b[0]:
            t = (s - a[0]) / (b[0] - a[0])
            return tuple(lerp(a[i], b[i], t) for i in range(1, 5))
    return prof[-1][1:]


def arm_chain(side):
    sx = -1 if side == "L" else 1
    return Chain([(sx * 0.176, 0, 1.335), (sx * 0.215, 0, 1.05), (sx * 0.235, 0, 0.80)], sx)


def leg_chain(side):
    sx = -1 if side == "L" else 1
    return Chain([(sx * 0.09, 0, 0.96), (sx * 0.09, 0, 0.50), (sx * 0.09, 0, 0.085)], sx)


def arm_w(side, s):
    ua, fa, hd = "upper_arm_" + side, "forearm_" + side, "hand_" + side
    L1 = 0.2876
    t = sstep(L1 - 0.045, L1 + 0.045, s)
    d = {ua: 1 - t, fa: t}
    if s < 0.08:
        k = sstep(0.0, 0.08, s)
        d = {ua: 0.55 + 0.45 * k, "shoulder_" + side: 0.25 * (1 - k), "chest": 0.20 * (1 - k)}
    if s > 0.505:
        h = sstep(0.505, 0.55, s) * 0.5
        d = {fa: 1 - h, hd: h}
    return d


def leg_w(side, s):
    th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side
    L1 = 0.46
    t = sstep(L1 - 0.05, L1 + 0.05, s)
    d = {th: 1 - t, sn: t}
    if s < 0.10:
        k = sstep(0.0, 0.10, s)
        d = {th: 0.7 + 0.3 * k, "hips": 0.3 * (1 - k)}
    if s > 0.83:
        f = sstep(0.83, 0.875, s) * 0.35
        d = {sn: 1 - f, ft: f}
    return d


def limb_ss(prof, s0, s1, step=0.03):
    """Ring stations between s0 and s1: every profile key in the range plus fill-ins no longer than `step`."""
    ks = [s0] + [r[0] for r in prof if s0 < r[0] < s1] + [s1]
    out = [ks[0]]
    for s in ks[1:]:
        n = max(1, int((s - out[-1]) / step + 0.999))
        out += [lerp(out[-1], s, (i + 1) / n) for i in range(n)]
    return out


def limb(M, chain, prof, wfn, side, s0, s1, mat, grow=0.0, seg=12, flare=0.0, pole0=False, pole1=False, cuff=None, rk=1.0):
    ss = limb_ss(prof, s0, s1)
    rows, wr = [], []
    for i, s in enumerate(ss):
        rx, ry, dx, dy = prof_at(prof, s)
        g = grow + (flare if i == len(ss) - 1 else 0.0)
        rows.append(chain.ring(s, rx * rk, ry * rk, dx, dy, g, seg))
        wr.append(wfn(side, s))
    if pole0:
        c, u, v = chain.at(s0)
        rows.insert(0, [c - (chain.p[1] - chain.p[0]).normalized() * 0.012])
        wr.insert(0, wr[0])
    if pole1:
        c, u, v = chain.at(s1)
        rows.append([c + (chain.p[-1] - chain.p[-2]).normalized() * 0.01])
        wr.append(wr[-1])
    M.loft(rows, mat, wrows=wr, closed=True, caps=False)
    if cuff:                                          # (length, extra grow, material) band at the end of the sleeve / leg
        ln, cg, cm = cuff
        cr, cw = [], []
        for s in (s1 - ln, s1):
            rx, ry, dx, dy = prof_at(prof, s)
            cr.append(chain.ring(s, rx * rk, ry * rk, dx, dy, grow + cg, seg))
            cw.append(wfn(side, s))
        M.loft(cr, cm, wrows=cw, closed=True, caps=False)


# ------------------------------------------------------------------ hands and feet
FINGERS = [(0.027, 0.062, 0.0082), (0.009, 0.070, 0.0086), (-0.009, 0.066, 0.0083), (-0.025, 0.053, 0.0074)]


def _bez(a, b, c, t):
    return a * (1 - t) ** 2 + b * 2 * t * (1 - t) + c * t * t


def _tube_path(M, pts, radii, mat, wd, seg=6, flat=1.0):
    """Tube through 3 bezier control points with a rounded tip; flat < 1 flattens it front-to-back of the path."""
    rows = []
    n = len(radii)
    for i in range(n):
        t = i / (n - 1)
        c = _bez(*pts, t)
        tan = (_bez(*pts, min(1, t + 0.05)) - _bez(*pts, max(0, t - 0.05))).normalized()
        u = V((1, 0, 0))
        u = (u - tan * u.dot(tan)).normalized()
        v = tan.cross(u)
        rows.append([c + u * (radii[i] * flat * math.cos(TAU * k / seg)) + v * (radii[i] * math.sin(TAU * k / seg)) for k in range(seg)])
    rows.append([_bez(*pts, 1.0) + (_bez(*pts, 1.0) - _bez(*pts, 0.9)).normalized() * radii[-1] * 0.8])
    M.loft(rows, mat, wd, closed=True, caps=False)


def hand(M, side, wd=1.0, mat="skin", curl=0.0):
    """curl 0 = relaxed open hand, 1 = a fist closed round a grip (the grip_L / grip_R shape keys; same topology either way)."""
    sx = -1 if side == "L" else 1
    hb = "hand_" + side
    wh = W(hb)
    # palm: wrist to knuckles, thin across (x), wide front to back (y)
    PALM = [(0.818, 0.236, 0.021, 0.021, 0.0), (0.788, 0.238, 0.018, 0.029, 0.002), (0.765, 0.240, 0.0175, 0.039, 0.004),
            (0.742, 0.241, 0.0165, 0.042, 0.003), (0.724, 0.240, 0.0145, 0.040, 0.002), (0.714, 0.238, 0.010, 0.033, 0.001)]
    rows, wr = [], []
    for (z, cx, rx, ry, cy) in PALM:
        rows.append([V((sx * (cx + rx * math.cos(TAU * k / 10)), cy + ry * math.sin(TAU * k / 10), z)) for k in range(10)])
        wr.append({"forearm_" + side: 0.4, hb: 0.6} if z > 0.8 else {hb: 1.0})
    rows.append([V((sx * 0.237, 0.001, 0.709))])
    wr.append({hb: 1.0})
    M.loft(rows, mat, wrows=wr, closed=True, caps=False)
    for (y, ln, r) in FINGERS:
        a = V((sx * 0.240, y, 0.726))
        b = V((sx * 0.239, y * 1.02, 0.726 - ln * 0.55))
        c = V((sx * 0.228, y * 1.04, 0.726 - ln))
        bc = V((sx * 0.228, y, 0.700))                  # curled: down over the knuckle, then back up into the palm
        cc = V((sx * 0.214, y * 0.95, 0.722))
        _tube_path(M, (a, b.lerp(bc, curl), c.lerp(cc, curl)), [r, r * 0.98, r * 0.92, r * 0.82], mat, wh, seg=6, flat=0.9)
    a = V((sx * 0.231, 0.022, 0.786))
    b = V((sx * 0.225, 0.041, 0.766)).lerp(V((sx * 0.219, 0.036, 0.752)), curl)          # the thumb closes over the fingers
    c = V((sx * 0.222, 0.047, 0.742)).lerp(V((sx * 0.214, 0.022, 0.735)), curl)
    _tube_path(M, (a, b, c), [0.0115, 0.0105, 0.0095, 0.0080], mat, wh, seg=6)


# foot sections along y: (y, half width, height, inward shift at the toes)
FOOT = [(-0.040, 0.025, 0.060), (-0.020, 0.031, 0.078), (0.015, 0.035, 0.078), (0.055, 0.039, 0.060),
        (0.095, 0.043, 0.044), (0.130, 0.043, 0.034), (0.155, 0.036, 0.027), (0.168, 0.026, 0.020)]


def foot(M, side, mat, grow=0.0, sole=0.0, length=0.0, seg=12, top_cut=None):
    """A foot shell from heel to toe; grow fattens it (shoes), sole lifts the shell off the ground, length stretches the toe."""
    sx = -1 if side == "L" else 1
    ft = "foot_" + side
    rows = []
    rows.append([V((sx * 0.09, -0.048 - grow, 0.034 + sole))])
    for (y, hw, h) in FOOT:
        y2 = y * (1 + length) if y > 0 else y - grow * 0.6
        hh = h + grow + sole * 0.4
        if top_cut is not None:
            hh = min(hh, top_cut)
        cz = sole + hh * 0.5
        cx = sx * (0.09 - 0.010 * sstep(0.05, 0.16, y))
        ring = []
        for k in range(seg):
            a = TAU * k / seg
            ca, sa = math.cos(a), math.sin(a)
            zz = cz + hh * 0.5 * (spow(sa, 0.55) if sa < 0 else sa)       # flat sole, round top
            ring.append(V((cx + (hw + grow) * spow(ca, 0.8), y2, zz)))
        rows.append(ring)
    rows.append([V((sx * 0.08, FOOT[-1][0] * (1 + length) + 0.012 + grow * 0.5, sole + 0.012))])
    M.loft(rows, mat, W(ft), closed=True, caps=False)


# ------------------------------------------------------------------ tops
SLEEVE = {"tee": 0.15, "dress": 0.10, "apron": 0.15, "hoodie": 0.540, "sweater": 0.540, "shirt": 0.530, "uniform": 0.530}
GROW = {"tee": 0.014, "hoodie": 0.024, "sweater": 0.019, "shirt": 0.015, "dress": 0.010, "apron": 0.014, "uniform": 0.016}
HEM = {"tee": 0.925, "hoodie": 0.895, "sweater": 0.905, "shirt": 0.915, "dress": 0.995, "apron": 0.925, "uniform": 0.915}


def front_patch(M, sh, wd, z0, z1, xw, grow, mat, seg=6, curve=1.0):
    """A thin panel lying on the front of the torso (pocket, placket, apron bib) between z0 and z1, |x| < xw."""
    rows = []
    for z in (z0, lerp(z0, z1, 0.5), z1):
        hw, fr, bk, sq = torso_at(z, sh, wd)
        row = []
        for k in range(seg + 1):
            x = lerp(-xw, xw, k / seg)
            t = min(0.999, abs(x) / (hw + grow))
            y = (fr + grow) * (1 - t ** sq) ** (1.0 / sq)
            row.append(V((x, y, z)))
        rows.append(row)
    back = [[p - V((0, 0.004, 0)) for p in r] for r in rows]
    M.loft(rows + list(reversed(back)) + [rows[0]], mat, w_torso, closed=False, caps=False)


def collar(M, sh, wd, grow, mat):
    """Two shirt collar wings folding down from the neckline."""
    for sx in (-1, 1):
        pts = [[V((sx * 0.012, 0.062, 1.390)), V((sx * 0.052, 0.050, 1.408)), V((sx * 0.072, 0.012, 1.412))],
               [V((sx * 0.022, 0.082, 1.348)), V((sx * 0.072, 0.070, 1.370)), V((sx * 0.100, 0.022, 1.385))]]
        thick = [[p + V((0, -0.004, 0.002)) for p in r] for r in pts]
        M.loft([pts[0], pts[1], thick[1], thick[0], pts[0]], mat, w_torso, closed=False, caps=False)


def top_builder(kind, wd):
    def build(M, sh):
        g = GROW[kind]
        torso_part(M, sh, wd, HEM[kind], 1.405, g, "shirt", seg=18)
        for side in "LR":
            ch = arm_chain(side)
            cuff = None
            if kind in ("sweater", "hoodie"):
                cuff = (0.04, 0.003, "accent" if kind == "sweater" else "shirt")
            elif kind in ("shirt", "uniform"):
                cuff = (0.03, 0.002, "shirt")
            limb(M, ch, ARM, arm_w, side, 0.0, SLEEVE[kind], "shirt", grow=g * 0.8, seg=12,
                 flare=0.006 if SLEEVE[kind] < 0.3 else 0.0, cuff=cuff, rk=wd)
        if kind == "hoodie":
            _tube_path(M, (V((-0.085, 0.035, 1.385)), V((0.0, -0.215, 1.455)), V((0.085, 0.035, 1.385))),
                       [0.022, 0.034, 0.036, 0.034, 0.022], "shirt", w_torso, seg=8)                           # hood rolled behind the neck
            front_patch(M, sh, wd, 0.97, 1.10, 0.10, g + 0.005, "shirt", seg=8)                             # pocket
            for sx in (-1, 1):
                M.tube(V((sx * 0.03, 0.09 * sh[3] + g, 1.37)), V((sx * 0.034, 0.105 * sh[3] + g, 1.25)),
                       [(0, 0.004, 0.004), (1, 0.004, 0.004)], "accent", w_torso, seg=4)                     # drawstrings
        elif kind == "sweater":
            torso_part(M, sh, wd, HEM[kind], HEM[kind] + 0.045, g + 0.004, "accent", seg=18)               # ribbed hem
            M.tube(V((0, 0.002, 1.383)), V((0, 0.004, 1.418)), [(0, 0.074, 0.066), (1, 0.060, 0.056)], "accent", w_torso, seg=14)
        elif kind in ("shirt", "uniform"):
            collar(M, sh, wd, g, "accent" if kind == "shirt" else "shirt")
            front_patch(M, sh, wd, HEM[kind] + 0.01, 1.35, 0.012, g + 0.002, "accent", seg=2)               # button placket
            if kind == "uniform":
                for sx in (-1, 1):
                    M.tube(V((sx * 0.07, 0, 1.372)), V((sx * 0.175, 0, 1.362)), [(0, 0.022, 0.006), (1, 0.024, 0.006)],
                           "accent", w_torso, seg=6)                                                           # epaulets
                front_patch(M, sh, wd, 1.20, 1.37, 0.022, g + 0.006, "accent", seg=2)                           # tie
        elif kind == "dress":
            sk = []
            for i, z in enumerate((1.02, 0.94, 0.84, 0.72, 0.60, 0.50)):
                t = i / 5
                hw, fr, bk, sq = torso_at(max(z, 0.90), sh, wd)
                fl = 0.075 * t ** 1.2
                sk.append([V(((hw + g + fl) * math.cos(TAU * k / 20), ((fr if math.sin(TAU * k / 20) > 0 else bk) + g + fl * 0.8)
                              * math.sin(TAU * k / 20), z)) for k in range(20)])
            M.loft(sk, "shirt", w_skirt, closed=True, caps=False)
            torso_part(M, sh, wd, 1.045, 1.085, g + 0.005, "accent", seg=18)                               # belt
        elif kind == "apron":
            front_patch(M, sh, wd, 1.06, 1.33, 0.085, g + 0.004, "accent", seg=6)                           # bib
            ap = []
            for z in (1.07, 0.95, 0.80, 0.66):
                hw, fr, bk, sq = torso_at(max(z, 0.90), sh, wd)
                row = []
                for k in range(9):
                    x = lerp(-0.15, 0.15, k / 8) * (hw / 0.165)
                    t = min(0.99, abs(x) / (hw + g + 0.01))
                    row.append(V((x, (fr + g + 0.012) * (1 - t ** 2.4) ** (1 / 2.4) + (0.95 - min(z, 0.95)) * 0.15, z)))
                ap.append(row)
            M.loft(ap, "accent", w_skirt, closed=False, caps=False)
            torso_part(M, sh, wd, 1.05, 1.07, g + 0.005, "accent", seg=18)                                  # waist tie
            for sx in (-1, 1):
                M.tube(V((sx * 0.07, 0.085 * sh[3] + g, 1.33)), V((sx * 0.045, 0.02, 1.415)), [(0, 0.008, 0.004), (1, 0.008, 0.004)],
                       "accent", w_torso, seg=4)
        else:   # tee: a slightly raised crew neck
            M.tube(V((0, 0.002, 1.385)), V((0, 0.003, 1.405)), [(0, 0.070 + g, 0.058 + g), (1, 0.064 + g, 0.054 + g)], "shirt", w_torso, seg=14)
    return build


# ------------------------------------------------------------------ bottoms
def w_skirt(p):
    """Skirts follow both thighs more the lower they hang; across the middle the two thighs share it, so the hem
    stretches between the legs instead of splitting open."""
    if p.z >= 0.99:
        return w_torso(p)
    s = sstep(1.02, 0.86, p.z) * 0.92
    r = 1.0 / (1.0 + math.exp(-p.x / 0.035))      # 0 on the left, 1 on the right
    return {"hips": 1 - s, "thigh_L": s * (1 - r), "thigh_R": s * r}


def bottom_builder(kind, wd):
    g = 0.006

    def build(M, sh):
        torso_part(M, sh, wd, 0.855, 1.045, g, "pants", seg=18, close_bottom=True)
        torso_part(M, sh, wd, 1.015, 1.045, g + 0.003, "pants", seg=18)                                   # waistband
        if kind == "skirt":
            sk = []
            for i, z in enumerate((1.02, 0.94, 0.84, 0.72, 0.60)):
                t = i / 4
                hw, fr, bk, sq = torso_at(max(z, 0.90), sh, wd)
                fl = 0.07 * t ** 1.2
                sk.append([V(((hw + g + 0.004 + fl) * math.cos(TAU * k / 20),
                              ((fr if math.sin(TAU * k / 20) > 0 else bk) + g + 0.004 + fl * 0.8) * math.sin(TAU * k / 20), z))
                           for k in range(20)])
            M.loft(sk, "pants", w_skirt, closed=True, caps=False)
            return
        end = 0.33 if kind == "shorts" else 0.862
        for side in "LR":
            limb(M, leg_chain(side), LEG, leg_w, side, 0.0, end, "pants", grow=0.011, seg=12,
                 flare=0.008 if kind == "shorts" else 0.006, rk=wd)
    return build


def legs_skin(M, wd):
    for side in "LR":
        limb(M, leg_chain(side), LEG, leg_w, side, 0.0, 0.875, "skin", seg=12, rk=wd)


def shoes(M, kind, wd):
    for side in "LR":
        if kind == "barefoot":
            foot(M, side, "skin")
            continue
        sole = 0.012 if kind in ("sneakers", "boots") else 0.008
        foot(M, side, "shoes", grow=0.007, sole=sole, length=0.04)
        foot(M, side, "accent" if kind == "sneakers" else "frame", grow=0.010, sole=0.0, length=0.05, top_cut=sole + 0.004, seg=12)
        if kind == "boots":
            ch = leg_chain(side)
            limb(M, ch, LEG, leg_w, side, 0.66, 0.875, "shoes", grow=0.012, seg=12, cuff=(0.025, 0.003, "shoes"), rk=wd)
        elif kind == "sneakers":
            sx = -1 if side == "L" else 1
            for k in range(3):                                                                             # laces
                y = 0.035 + k * 0.025
                z = 0.085 - k * 0.010
                M.tube(V((sx * 0.07, y, z)), V((sx * 0.11, y, z)), [(0, 0.004, 0.003), (1, 0.004, 0.003)], "accent", W("foot_" + side), seg=4)


# ------------------------------------------------------------------ base body (neck, arms, hands) - skull is added by folk_head
def base_body(M, wd, curl_l=0.0, curl_r=0.0):
    M.tube(V((0, 0.004, 1.35)), V((0, 0.008, 1.50)), [(0, 0.060, 0.056), (0.5, 0.053, 0.051), (1, 0.050, 0.048)], "skin",
           lambda p: {"neck": 1.0} if p.z > 1.42 else {"neck": 0.5, "chest": 0.5}, seg=12)
    for side in "LR":
        limb(M, arm_chain(side), ARM, arm_w, side, 0.0, 0.546, "skin", seg=12, rk=wd, pole1=True)
        hand(M, side, wd, curl=curl_l if side == "L" else curl_r)


def build_clothes(arm, bones, S, wd):
    obs = []
    for i, k in enumerate(TOPS):
        obs.append(finish_morph(top_builder(k, wd), "top_%d" % i, arm, bones, S))
    for i, k in enumerate(BOTTOMS):
        obs.append(finish_morph(bottom_builder(k, wd), "bottom_%d" % i, arm, bones, S))
    M = Mesher(bones, S)
    legs_skin(M, wd)
    obs.append(M.finish("legs_skin", arm))
    for i, k in enumerate(SHOES):
        M = Mesher(bones, S)
        shoes(M, k, wd)
        obs.append(M.finish("shoes_%d" % i, arm))
    return obs
