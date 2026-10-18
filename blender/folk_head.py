"""Head parts of the folk (Blender 5.1): skull, face feature variants, hair styles, facial hair, marks, glasses, hats, scarf, bags.

Objects: ears_0..2, eyes_0..3, brows_0..3, nose_0..3, mouth_0..3, hair_0..15 (hair_9 = bald, no mesh), fhair_1..3,
mark_1..2, glasses_1..2, hat_1..2, scarf_1, bag_1..2.
Head-local coordinates: x right, y forward (face), z up, about the head centre, scaled by the head scale hs.
"""
import math
import random
from mathutils import Vector
from folk_mesh import W, Mesher, torus

V = Vector
HAIR_STYLES = 16
BALD = 9


class Head:
    def __init__(self, hs):
        self.hs = hs
        self.hc = V((0, 0.005, 1.46 + 0.115 * hs - 0.012 * hs))

    def H(self, x, y, z):
        return self.hc + V((x, y, z)) * self.hs

    def E(self, M, c, r, mat, wfn=None, **kw):
        M.ellipsoid(self.H(*c), tuple(v * self.hs for v in r), mat, wfn or W("head"), **kw)

    def T(self, M, a, b, prof, mat, wfn=None, seg=6):
        s = self.hs
        M.tube(self.H(*a), self.H(*b), [(t, ru * s, rv * s) for (t, ru, rv) in prof], mat, wfn or W("head"), seg=seg)


def skull(M, hd):
    hd.E(M, (0, 0, 0), (0.093, 0.105, 0.115), "skin", rings=9, seg=14)
    hd.E(M, (0, 0.022, -0.065), (0.072, 0.072, 0.060), "skin", rings=6, seg=10)


# ------------------------------------------------------------------ face features (index = variant)
def ears(M, hd, i):
    sz = [(0.012, 0.02, 0.03), (0.016, 0.026, 0.04), (0.011, 0.018, 0.045)][i]
    dz = [-0.005, -0.01, 0.012][i]
    for sx in (-1, 1):
        hd.E(M, (sx * 0.094, 0.0, dz), sz, "skin", rings=4, seg=6)


# eyes: (spacing, size scale, height scale, z)
EYES = [(0.037, 1.0, 1.0, 0.015), (0.046, 1.15, 1.0, 0.015), (0.040, 1.25, 0.62, 0.012), (0.029, 0.88, 1.0, 0.012)]


def eyes(M, hd, i):
    sp, k, kh, z = EYES[i]
    for sx in (-1, 1):
        hd.E(M, (sx * sp, 0.088, z), (0.019 * k, 0.012, 0.016 * k * kh), "eyewhite", rings=4, seg=8)
        hd.E(M, (sx * sp, 0.096, z), (0.011 * k, 0.006, 0.011 * k * kh * (1.0 if kh > 0.8 else 1.25)), "eyes", rings=4, seg=8)


def brows(M, hd, i):
    sp = EYES[0][0]
    for sx in (-1, 1):
        if i == 0:
            hd.E(M, (sx * sp, 0.092, 0.047), (0.025, 0.008, 0.006), "hair", rings=3, seg=6)
        elif i == 1:      # thick
            hd.E(M, (sx * sp, 0.092, 0.046), (0.030, 0.010, 0.011), "hair", rings=3, seg=6)
        elif i == 2:      # arched, outer end up
            hd.T(M, (sx * 0.015, 0.093, 0.045), (sx * 0.06, 0.088, 0.055), [(0, 0.005, 0.006), (0.5, 0.007, 0.008), (1, 0.003, 0.004)], "hair")
        else:             # straight, low, angled in
            hd.T(M, (sx * 0.016, 0.093, 0.040), (sx * 0.058, 0.089, 0.048), [(0, 0.005, 0.006), (1, 0.004, 0.005)], "hair")


NOSES = [(0.014, 0.020, 0.022, -0.015), (0.012, 0.030, 0.034, -0.012), (0.011, 0.014, 0.014, -0.005), (0.022, 0.022, 0.020, -0.018)]


def nose(M, hd, i):
    rx, ry, rz, z = NOSES[i]
    hd.E(M, (0, 0.100 + ry * 0.2, z), (rx, ry, rz), "skin", rings=4, seg=6)


MOUTHS = [(0.023, 0.008, 0.006, -0.05), (0.020, 0.010, 0.011, -0.052), (0.014, 0.008, 0.005, -0.050), (0.032, 0.008, 0.006, -0.048)]


def mouth(M, hd, i):
    rx, ry, rz, z = MOUTHS[i]
    hd.E(M, (0, 0.088, z), (rx, ry, rz), "mouth", rings=3, seg=8)
    if i == 3:       # smile corners
        for sx in (-1, 1):
            hd.E(M, (sx * 0.03, 0.085, z + 0.008), (0.006, 0.006, 0.006), "mouth", rings=3, seg=6)


# ------------------------------------------------------------------ face extras
def fhair(M, hd, i):
    if i == 1:        # moustache
        for sx in (-1, 1):
            hd.E(M, (sx * 0.014, 0.1, -0.036), (0.017, 0.009, 0.008), "hair", rings=3, seg=6)
    elif i == 2:      # goatee + moustache
        for sx in (-1, 1):
            hd.E(M, (sx * 0.014, 0.1, -0.036), (0.017, 0.009, 0.008), "hair", rings=3, seg=6)
        hd.E(M, (0, 0.085, -0.095), (0.026, 0.02, 0.028), "hair", rings=4, seg=8)
    else:             # full beard: shell around the lower face
        def keep(p):
            q = (p - hd.hc) / hd.hs
            return q.z < -0.03 and q.y > -0.03 and not (q.y > 0.08 and q.z > -0.065 and abs(q.x) < 0.03)
        hd.E(M, (0, 0.025, -0.06), (0.1, 0.085, 0.085), "hair", rings=8, seg=14, clip=keep)


def mark(M, hd, i):
    if i == 1:        # freckles
        pts = [(-0.045, 0.1, -0.012), (-0.056, 0.095, -0.02), (-0.035, 0.1, -0.022), (-0.025, 0.104, -0.008),
               (0.045, 0.1, -0.012), (0.056, 0.095, -0.02), (0.035, 0.1, -0.022), (0.025, 0.104, -0.008)]
        for p in pts:
            hd.E(M, p, (0.006, 0.004, 0.006), "freckles", rings=3, seg=5)
    else:             # beauty mark
        hd.E(M, (0.034, 0.096, -0.046), (0.0075, 0.005, 0.0075), "freckles", rings=3, seg=6)


def glasses(M, hd, i):
    sp, z = EYES[0][0], 0.014
    for sx in (-1, 1):
        s = hd.hs
        torus(M, hd.H(sx * sp, 0.108, z), 0.027 * s, 0.0028 * s, "frame", W("head"), n=14, seg=5, square=0.0 if i == 1 else 1.0)
        hd.T(M, (sx * 0.062, 0.1, z), (sx * 0.098, 0.0, z + 0.004), [(0, 0.0025, 0.0025), (1, 0.0025, 0.0025)], "frame", seg=4)
    hd.T(M, (-0.012, 0.108, z), (0.012, 0.108, z), [(0, 0.0025, 0.0025), (1, 0.0025, 0.0025)], "frame", seg=4)


# ------------------------------------------------------------------ hair
def _cap(m, hd, grow=0.012, back=0.0, top=0.0, low=0.06, mat="hair"):
    hs, hc = hd.hs, hd.hc

    def keep(p):
        q = (p - hc) / hs
        return q.z > low or (q.y < -0.025 and q.z > -0.075) and abs(q.x) < 0.09 or (q.z > -0.02 and q.y < -0.06)
    m.ellipsoid(hd.H(0, -0.012 + back * 0.4, 0.016 + top * 0.3),
                (hs * (0.093 + grow), hs * (0.108 + grow + back), hs * (0.113 + grow + top)),
                mat, W("head"), rings=9, seg=14, clip=keep)


def hair(M, hd, i):
    hh = lambda c, r, **kw: hd.E(M, c, r, "hair", **kw)
    if i == 0:
        _cap(M, hd, 0.012)
        hh((0, 0.075, 0.075), (0.085, 0.03, 0.03), rings=4, seg=8)
    elif i == 1:
        _cap(M, hd, 0.005, low=0.02)
    elif i == 2:
        _cap(M, hd, 0.014)
        hh((0, -0.075, -0.08), (0.105, 0.06, 0.20), rings=7, seg=10)
        hh((-0.085, -0.02, 0.0), (0.02, 0.05, 0.10), rings=5, seg=8)
        hh((0.085, -0.02, 0.0), (0.02, 0.05, 0.10), rings=5, seg=8)
        hh((0, 0.075, 0.075), (0.09, 0.03, 0.03), rings=4, seg=8)
    elif i == 3:
        _cap(M, hd, 0.012)
        hh((0, -0.12, 0.03), (0.04, 0.04, 0.04), rings=4, seg=8)
        hh((0, -0.15, -0.05), (0.032, 0.032, 0.08), rings=5, seg=8)
        hh((0, -0.16, -0.14), (0.025, 0.025, 0.07), rings=5, seg=8)
    elif i == 4:
        _cap(M, hd, 0.008)
        for (x, y, ang) in [(0, 0.0, 0.0), (-0.05, 0.03, -0.5), (0.05, 0.03, 0.5), (-0.05, -0.05, -0.6), (0.05, -0.05, 0.6), (0, -0.07, 0.0), (0, 0.07, 0.0)]:
            base = hd.H(x, y, 0.1)
            d = V((math.sin(ang) * 0.6, (0.4 if y > 0.05 else -0.4 if y < -0.06 else 0.0) * 0.6, 1.0)).normalized()
            M.tube(base, base + d * 0.11 * hd.hs, [(0, 0.03 * hd.hs, 0.03 * hd.hs), (1.0, 0, 0)], "hair", W("head"), seg=6)
    elif i == 5:
        hs, hc = hd.hs, hd.hc
        M.ellipsoid(hd.H(0, -0.01, 0.035), (0.135 * hs,) * 2 + (0.125 * hs,), "hair", W("head"), rings=8, seg=14,
                    clip=lambda p: not (((p - hc) / hs).y > 0.01 and ((p - hc) / hs).z < 0.06) and ((p - hc) / hs).z > -0.065)
    elif i == 6:      # short curls
        _cap(M, hd, 0.006, low=0.03)
        rnd = random.Random(6)
        for k in range(16):
            a = k * 2.399
            r = 0.035 + 0.075 * ((k % 5) / 5.0)
            hh((math.cos(a) * r, math.sin(a) * r * 1.05 - 0.01, 0.1 + 0.025 * (1 - r / 0.11) + rnd.uniform(0, 0.012)), (0.03, 0.03, 0.03), rings=4, seg=6)
        for sx in (-1, 1):
            hh((sx * 0.085, -0.01, 0.045), (0.03, 0.04, 0.035), rings=4, seg=6)
    elif i == 7:      # bun
        _cap(M, hd, 0.010)
        hh((0, -0.03, 0.15), (0.05, 0.05, 0.045), rings=6, seg=10)
        hh((0, 0.075, 0.075), (0.08, 0.025, 0.025), rings=4, seg=8)
    elif i == 8:      # braids
        _cap(M, hd, 0.012)
        for sx in (-1, 1):
            for k in range(5):
                hh((sx * 0.085, -0.045 - k * 0.006, -0.02 - k * 0.058), (0.024, 0.024, 0.034), rings=4, seg=6)
            hh((sx * 0.085, -0.075, -0.3), (0.016, 0.016, 0.02), rings=3, seg=6)
        hh((0, 0.075, 0.075), (0.085, 0.028, 0.028), rings=4, seg=8)
    elif i == 9:      # bald
        pass
    elif i == 10:     # mohawk
        _cap(M, hd, -0.004, low=0.115)
        for k in range(6):
            y = 0.08 - k * 0.034
            hh((0, y, 0.11 + 0.03 * math.sin(math.pi * (k + 0.5) / 6)), (0.014, 0.024, 0.05), rings=4, seg=6)
    elif i == 11:     # long straight, centre parting
        _cap(M, hd, 0.014)
        hh((0, -0.085, -0.17), (0.105, 0.05, 0.30), rings=8, seg=10)
        for sx in (-1, 1):
            hh((sx * 0.092, -0.03, -0.07), (0.018, 0.05, 0.17), rings=6, seg=8)
        hh((0, 0.078, 0.07), (0.09, 0.025, 0.035), rings=4, seg=8)
    elif i == 12:     # bob
        hs, hc = hd.hs, hd.hc
        _cap(M, hd, 0.016)
        M.ellipsoid(hd.H(0, -0.012, -0.045), (0.118 * hs, 0.122 * hs, 0.085 * hs), "hair", W("head"), rings=7, seg=14,
                    clip=lambda p: not (((p - hc) / hs).y > 0.02 and ((p - hc) / hs).z > -0.1) and ((p - hc) / hs).z < 0.0)
        hh((0, 0.078, 0.065), (0.09, 0.025, 0.03), rings=4, seg=8)
    elif i == 13:     # quiff
        _cap(M, hd, 0.010)
        hh((0, 0.06, 0.125), (0.075, 0.07, 0.05), rings=6, seg=10)
        hh((0.03, 0.095, 0.1), (0.04, 0.03, 0.03), rings=4, seg=6)
    elif i == 14:     # pigtails
        _cap(M, hd, 0.012)
        for sx in (-1, 1):
            hh((sx * 0.105, -0.02, 0.045), (0.034, 0.034, 0.034), rings=4, seg=8)
            hh((sx * 0.135, -0.02, -0.05), (0.03, 0.03, 0.095), rings=5, seg=8)
        hh((0, 0.075, 0.075), (0.085, 0.028, 0.028), rings=4, seg=8)
    else:             # shaggy
        _cap(M, hd, 0.016, back=0.01)
        for sx in (-1, 1):
            hh((sx * 0.10, 0.0, -0.01), (0.03, 0.06, 0.075), rings=5, seg=8)
        hh((0, -0.1, -0.03), (0.09, 0.04, 0.09), rings=5, seg=10)
        hh((0, 0.07, 0.09), (0.09, 0.035, 0.04), rings=4, seg=8)
        hh((-0.04, 0.085, 0.07), (0.03, 0.02, 0.04), rings=4, seg=6)


# ------------------------------------------------------------------ hats, scarf, bags
def hat(M, hd, i):
    if i == 1:        # cap with brim
        _cap(M, hd, 0.030, top=-0.004, low=0.045, mat="accent")
        hd.E(M, (0, 0.105, 0.052), (0.085, 0.07, 0.01), "accent", rings=4, seg=10)
    else:             # beanie with cuff
        _cap(M, hd, 0.026, top=0.012, low=0.0, mat="accent")
        hd.T(M, (0, -0.005, 0.0), (0, -0.005, 0.045), [(0, 0.123, 0.130), (1, 0.121, 0.128)], "accent", seg=14)
        hd.E(M, (0, -0.01, 0.145), (0.025, 0.025, 0.025), "accent", rings=4, seg=8)


def scarf(M, hd):
    wn = lambda p: {"neck": 0.6, "chest": 0.4}
    M.tube(V((0, 0, 1.40)), V((0, 0, 1.475)), [(0, 0.135, 0.105), (0.4, 0.098, 0.092), (1, 0.078, 0.072)], "accent", wn, seg=12)
    M.tube(V((0.05, 0.118, 1.42)), V((0.06, 0.125, 1.15)), [(0, 0.042, 0.016), (1, 0.046, 0.016)], "accent", lambda p: {"chest": 1.0}, seg=6)


def bag(M, hd, i):
    wc = lambda p: {"chest": 0.7, "spine": 0.3}
    if i == 1:        # backpack
        M.ellipsoid(V((0, -0.135, 1.2)), (0.115, 0.075, 0.16), "accent", wc, rings=6, seg=10)
        for sx in (-1, 1):
            M.tube(V((sx * 0.095, -0.03, 1.37)), V((sx * 0.1, -0.12, 1.28)), [(0, 0.016, 0.008), (1, 0.016, 0.008)], "accent", wc, seg=4)
            M.tube(V((sx * 0.095, 0.02, 1.38)), V((sx * 0.1, 0.085, 1.2)), [(0, 0.016, 0.008), (1, 0.016, 0.008)], "accent", wc, seg=4)
    else:             # satchel: strap across the chest + bag at the hip
        wh = lambda p: {"chest": 0.5, "hips": 0.5}
        M.tube(V((0.085, 0.112, 1.375)), V((-0.12, 0.122, 1.1)), [(0, 0.02, 0.008), (1, 0.02, 0.008)], "accent", wc, seg=4)
        M.tube(V((-0.12, 0.122, 1.1)), V((-0.22, 0.05, 0.95)), [(0, 0.02, 0.008), (1, 0.02, 0.008)], "accent", wh, seg=4)
        M.ellipsoid(V((-0.235, 0.0, 0.93)), (0.055, 0.11, 0.085), "accent", wh, rings=5, seg=8)
