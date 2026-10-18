"""Body parts of the folk (Blender 5.1): base body, tops, bottoms, shoes. Coordinates are adult units (metres, Z up, +Y forward).

Objects produced (each one skinned to the same rig, toggled by Godot):
  body (neck, arms, hands, skull - always shown), legs_skin (bare legs - always under bottoms),
  top_0..6 (tee hoodie sweater shirt dress apron uniform), bottom_0..2 (trousers shorts skirt) - both with body-shape morphs,
  shoes_0..3 (shoes boots barefoot sneakers).
"""
import math
from mathutils import Vector
from folk_mesh import W, ramp, finish_morph, Mesher

V = Vector
TOPS = ["tee", "hoodie", "sweater", "shirt", "dress", "apron", "uniform"]
BOTTOMS = ["trousers", "shorts", "skirt"]
SHOES = ["shoes", "boots", "barefoot", "sneakers"]


# ------------------------------------------------------------------ weights
def w_torso(p):
    z = p.z
    a = ramp(z, 0.96, 1.04)
    b = ramp(z, 1.10, 1.18)
    d = {"hips": 1 - a, "spine": a * (1 - b), "chest": a * b}
    if z > 1.34:
        n = ramp(z, 1.34, 1.42)
        d = {"chest": 1 - n * 0.5, "neck": n * 0.5}
    return d


def w_hips(p):
    return {"hips": 1.0} if p.z < 1.0 else w_torso(p)


def w_ua(side):
    ua, fa = "upper_arm_" + side, "forearm_" + side

    def f(p):
        t = ramp(p.z, 1.05, 0.90)
        top = ramp(p.z, 1.25, 1.36)
        d = {ua: 1 - 0.5 * t, fa: 0.5 * t}
        if top > 0:
            d = {ua: (1 - top) * (1 - 0.5 * t) + top * 0.5, "shoulder_" + side: top * 0.25, "chest": top * 0.25}
        return d
    return f


def w_fa(side):
    ua, fa = "upper_arm_" + side, "forearm_" + side

    def f(p):
        t = ramp(1.05 - p.z, 0.0, 0.08)
        return {fa: 0.5 + 0.5 * t, ua: 0.5 - 0.5 * t}
    return f


def w_th(side):
    th, sn = "thigh_" + side, "shin_" + side

    def f(p):
        t = ramp(0.55 - p.z, 0.0, 0.10)
        return {th: 1 - 0.5 * t, sn: 0.5 * t}
    return f


def w_sn(side):
    th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side

    def f(p):
        t = ramp(0.55 - p.z, 0.0, 0.10)
        fo = ramp(0.16 - p.z, 0.0, 0.07)
        return {th: 0.5 * (1 - t) if p.z > 0.45 else 0.0, sn: (0.5 + 0.5 * t) * (1 - fo), ft: fo * 0.4}
    return f


def w_skirt(p):
    if p.z >= 0.99:
        return w_hips(p)
    s = ramp(0.99 - p.z, 0.0, 0.40) * 0.55
    side = "thigh_L" if p.x < 0 else "thigh_R"
    return {"hips": 1 - s, side: s}


# ------------------------------------------------------------------ torso profile (shape = chest, waist, hip, depth)
def torso_prof(wd, sh, grow=0.0):
    c, w, h, d = sh
    g = grow
    return [(0.0, 0.172 * wd * h + g, 0.116 * d + g), (0.12, 0.158 * wd * h + g, 0.108 * d + g),
            (0.30, 0.142 * wd * w + g, 0.100 * d + g), (0.5, 0.163 * wd * (w + c) * 0.5 + g, 0.105 * d + g),
            (0.72, 0.188 * wd * c + g, 0.112 * d + g), (0.88, 0.196 * wd * c + g, 0.104 * d + g),
            (0.96, 0.130 * wd + g * 0.5, 0.085 + g * 0.5), (1.0, 0.070, 0.060)]


def torso_tube(M, wd, sh, grow=0.0, mat="shirt"):
    M.tube(V((0, 0, 0.99)), V((0, 0, 1.43)), torso_prof(wd, sh, grow), mat, w_torso, seg=14)


def pelvis(M, wd, sh):
    h, d = sh[2], sh[3]
    M.tube(V((0, 0, 0.84)), V((0, 0, 1.08)),
           [(0.0, 0.07 * wd * h, 0.06 * wd), (0.04, 0.12 * wd * h, 0.09 * d), (0.36, 0.172 * wd * h, 0.112 * d),
            (0.7, 0.158 * wd * h, 0.104 * d), (1.0, 0.150 * wd * h, 0.100 * d)], "pants", w_hips, seg=12)


def sleeves(M, wd, mat="shirt", cuff=False):
    for side, sx in (("L", -1), ("R", 1)):
        M.tube(V((sx * 0.215, 0, 1.075)), V((sx * 0.235, 0, 0.84)),
               [(0, 0.052 * wd, 0.052 * wd), (0.1, 0.050 * wd, 0.050 * wd), (0.6, 0.046 * wd, 0.046 * wd), (1.0, 0.042 * wd, 0.042 * wd)],
               mat, w_fa(side), seg=8)
        if cuff:
            M.tube(V((sx * 0.232, 0, 0.855)), V((sx * 0.235, 0, 0.82)), [(0, 0.047 * wd, 0.047 * wd), (1, 0.047 * wd, 0.047 * wd)],
                   "accent", w_fa(side), seg=8)


def front(M, c, r, sh, mat="accent", rings=5, seg=8):
    """ellipsoid on the front of the torso (y scaled with the depth morph)."""
    M.ellipsoid(V((c[0], c[1] * sh[3], c[2])), r, mat, w_torso, rings=rings, seg=seg)


# ------------------------------------------------------------------ tops
def top_builder(kind, wd):
    def build(M, sh):
        g = {"hoodie": 0.016, "sweater": 0.012, "shirt": 0.008, "uniform": 0.010, "dress": 0.004}.get(kind, 0.0)
        torso_tube(M, wd, sh, g)
        if kind in ("hoodie", "sweater", "shirt", "uniform"):
            sleeves(M, wd, "shirt", cuff=(kind in ("sweater", "uniform")))
        if kind == "hoodie":
            M.ellipsoid(V((0, -0.08, 1.43)), (0.115, 0.075, 0.07), "shirt", w_torso, rings=6, seg=10)        # hood
            front(M, (0, 0.104, 1.09), (0.13, 0.035, 0.075), sh, "accent")                                  # pocket
        elif kind == "sweater":
            M.tube(V((0, 0, 1.385)), V((0, 0, 1.455)), [(0, 0.074, 0.070), (1, 0.062, 0.058)], "accent", w_torso, seg=12)    # neck rim
            M.tube(V((0, 0, 0.985)), V((0, 0, 1.03)), [(0, 0.176 * wd * sh[2] + 0.016, 0.120 * sh[3] + 0.014),
                                                      (1, 0.172 * wd * sh[2] + 0.016, 0.116 * sh[3] + 0.014)], "accent", w_torso, seg=14)
        elif kind == "shirt":
            for sx in (-1, 1):
                M.ellipsoid(V((sx * 0.045, 0.05 * sh[3], 1.435)), (0.045, 0.014, 0.028), "accent", w_torso, rings=4, seg=6)   # collar
            front(M, (0, 0.113, 1.22), (0.010, 0.012, 0.21), sh, "accent", rings=4, seg=6)                                   # buttons
        elif kind == "uniform":
            for sx in (-1, 1):
                M.ellipsoid(V((sx * 0.045, 0.05 * sh[3], 1.435)), (0.045, 0.014, 0.03), "accent", w_torso, rings=4, seg=6)
                M.ellipsoid(V((sx * 0.17 * sh[0], 0.0, 1.355)), (0.05, 0.05, 0.016), "accent", w_torso, rings=4, seg=8)         # epaulet
            front(M, (0, 0.113, 1.24), (0.020, 0.012, 0.13), sh, "accent", rings=4, seg=6)                                   # tie
            front(M, (0, 0.113, 1.38), (0.026, 0.014, 0.022), sh, "accent", rings=4, seg=6)
        elif kind == "dress":
            M.tube(V((0, 0, 1.02)), V((0, 0, 0.50)),
                   [(0.0, 0.158 * wd * sh[2], 0.105 * sh[3]), (0.25, 0.20 * wd * sh[2], 0.13 * sh[3]), (0.7, 0.255 * wd * sh[2], 0.17 * sh[3]),
                    (1.0, 0.285 * wd * sh[2], 0.19 * sh[3])], "shirt", w_skirt, seg=14)
            M.tube(V((0, 0, 1.02)), V((0, 0, 1.06)), [(0, 0.165 * wd * sh[1] + 0.008, 0.108 * sh[3] + 0.008),
                                                      (1, 0.165 * wd * sh[1] + 0.008, 0.108 * sh[3] + 0.008)], "accent", w_hips, seg=14)   # belt
        elif kind == "apron":
            c, w, h, d = sh
            m = 0.014
            rows = [(1.34, 0.195 * c * wd, 0.112 * d), (1.2, 0.168 * (w + c) * 0.5 * wd, 0.108 * d), (1.1, 0.15 * w * wd, 0.104 * d),
                    (1.0, 0.175 * h * wd, 0.115 * d), (0.9, 0.176 * h * wd, 0.116 * d), (0.78, 0.19 * h * wd, 0.125 * d), (0.64, 0.20 * h * wd, 0.132 * d)]
            rings = [(V((0, 0, z)), V((1, 0, 0)), V((0, 1, 0)), ru + m, rv + m) for (z, ru, rv) in rows]
            ru_at = {round(z, 3): ru + m for (z, ru, rv) in rows}

            def keep(p):      # decided on the angle only (x / ru), so every body-shape morph keeps the same topology
                ru0 = ru_at[min(ru_at, key=lambda zz: abs(zz - p.z))]
                return p.y > 0.0 and abs(p.x / ru0) < (0.62 if p.z > 1.17 else 0.95)
            M.ring_mesh(rings, "accent", w_skirt, 28, clip=keep)
            for sx in (-1, 1):
                M.tube(V((sx * 0.07, 0.07 * sh[3], 1.34)), V((sx * 0.06, 0.0, 1.43)), [(0, 0.012, 0.012), (1, 0.012, 0.012)], "accent", w_torso, seg=5)
    return build


# ------------------------------------------------------------------ bottoms
def bottom_builder(kind, wd):
    def build(M, sh):
        pelvis(M, wd, sh)
        h = sh[2]
        if kind == "skirt":
            M.tube(V((0, 0, 1.0)), V((0, 0, 0.56)),
                   [(0.0, 0.156 * wd * h, 0.104 * sh[3]), (0.3, 0.19 * wd * h, 0.125 * sh[3]), (0.75, 0.235 * wd * h, 0.16 * sh[3]),
                    (1.0, 0.255 * wd * h, 0.175 * sh[3])], "pants", w_skirt, seg=14)
            return
        for side, sx in (("L", -1), ("R", 1)):
            hip, kn, an = V((sx * 0.09, 0, 0.93)), V((sx * 0.09, 0, 0.50)), V((sx * 0.09, 0, 0.085))
            if kind == "shorts":
                M.tube(hip, V((sx * 0.09, 0, 0.66)), [(0.0, 0.092 * wd, 0.092 * wd), (0.5, 0.090 * wd, 0.090 * wd), (1.0, 0.088 * wd, 0.088 * wd)],
                       "pants", w_th(side), seg=10)
            else:
                M.tube(hip, kn, [(0.0, 0.092 * wd, 0.092 * wd), (0.25, 0.088 * wd, 0.089 * wd), (0.75, 0.066 * wd, 0.066 * wd), (1.0, 0.058 * wd, 0.058 * wd)],
                       "pants", w_th(side), seg=10)
                M.tube(kn + V((0, 0, 0.03)), an + V((0, 0, 0.02)), [(0.0, 0.058 * wd, 0.058 * wd), (0.3, 0.054 * wd, 0.054 * wd), (1.0, 0.040 * wd, 0.040 * wd)],
                       "pants", w_sn(side), seg=10)
                th, sn = "thigh_" + side, "shin_" + side
                M.ellipsoid(kn, (0.058 * wd, 0.058 * wd, 0.058 * wd), "pants", lambda p, th=th, sn=sn: {th: 0.5, sn: 0.5}, rings=5, seg=8)
    return build


def legs_skin(M, wd):
    for side, sx in (("L", -1), ("R", 1)):
        th, sn = "thigh_" + side, "shin_" + side
        hip, kn, an = V((sx * 0.09, 0, 0.93)), V((sx * 0.09, 0, 0.50)), V((sx * 0.09, 0, 0.085))
        k = 0.93
        M.tube(hip, kn, [(0.0, 0.092 * wd * k, 0.092 * wd * k), (0.25, 0.088 * wd * k, 0.089 * wd * k), (0.75, 0.066 * wd * k, 0.066 * wd * k),
                         (1.0, 0.058 * wd * k, 0.058 * wd * k)], "skin", w_th(side), seg=10)
        M.tube(kn + V((0, 0, 0.03)), an + V((0, 0, 0.02)), [(0.0, 0.058 * wd * k, 0.058 * wd * k), (0.3, 0.054 * wd * k, 0.054 * wd * k),
                                                           (1.0, 0.040 * wd * k, 0.040 * wd * k)], "skin", w_sn(side), seg=10)
        M.ellipsoid(kn, (0.058 * wd * k,) * 3, "skin", lambda p, th=th, sn=sn: {th: 0.5, sn: 0.5}, rings=5, seg=8)


def shoes(M, kind, wd):
    for side, sx in (("L", -1), ("R", 1)):
        ft = "foot_" + side
        mat = "skin" if kind == "barefoot" else "shoes"
        M.ellipsoid(V((sx * 0.09, 0.05, 0.048)), (0.052, 0.135, 0.050), mat, W(ft), rings=6, seg=10)
        M.ellipsoid(V((sx * 0.09, -0.01, 0.07)), (0.045, 0.06, 0.06), mat, W(ft), rings=5, seg=8)
        if kind == "boots":
            M.tube(V((sx * 0.09, 0, 0.07)), V((sx * 0.09, 0, 0.31)), [(0, 0.062 * wd, 0.062 * wd), (1, 0.066 * wd, 0.066 * wd)], "shoes",
                   lambda p, side=side: {"shin_" + side: ramp(p.z, 0.07, 0.2) * 0.9 + 0.0, "foot_" + side: 1 - ramp(p.z, 0.07, 0.2) * 0.9}, seg=10)
        elif kind == "sneakers":
            M.ellipsoid(V((sx * 0.09, 0.05, 0.022)), (0.056, 0.14, 0.022), "accent", W(ft), rings=5, seg=10)                  # sole
            M.ellipsoid(V((sx * 0.09, 0.115, 0.075)), (0.03, 0.05, 0.02), "accent", W(ft), rings=4, seg=6)                    # toe cap


# ------------------------------------------------------------------ base body (neck, arms, hands) - skull is added by folk_head
def base_body(M, wd):
    M.tube(V((0, 0, 1.36)), V((0, 0, 1.50)), [(0, 0.052, 0.05), (1, 0.046, 0.046)], "skin",
           lambda p: {"neck": 1.0} if p.z > 1.40 else {"neck": 0.5, "chest": 0.5}, seg=8)
    for side, sx in (("L", -1), ("R", 1)):
        sh, el, wr = V((sx * 0.19, 0, 1.33)), V((sx * 0.215, 0, 1.05)), V((sx * 0.235, 0, 0.80))
        ua, fa = "upper_arm_" + side, "forearm_" + side
        M.ellipsoid(V((sx * 0.185, 0, 1.325)), (0.07 * wd, 0.068 * wd, 0.07 * wd), "shirt", w_ua(side))
        M.tube(sh, el, [(0, 0.062 * wd, 0.060 * wd), (0.5, 0.055 * wd, 0.054 * wd), (0.93, 0.050 * wd, 0.049 * wd), (1.0, 0.0, 0.0)],
               "shirt", w_ua(side))
        M.tube(V((sx * 0.215, 0, 1.075)), wr, [(0, 0.0, 0.0), (0.07, 0.046 * wd, 0.046 * wd), (0.55, 0.040 * wd, 0.040 * wd), (1.0, 0.031 * wd, 0.030 * wd)],
               "skin", w_fa(side), seg=8)
        M.ellipsoid(el, (0.047 * wd,) * 3, "skin", lambda p, ua=ua, fa=fa: {ua: 0.5, fa: 0.5}, rings=5, seg=8)
        hb = "hand_" + side
        M.ellipsoid(V((sx * 0.243, 0.0, 0.725)), (0.026, 0.045, 0.062), "skin", W(hb), rings=6, seg=8)
        M.ellipsoid(V((sx * 0.243 - sx * 0.01, 0.045, 0.745)), (0.013, 0.014, 0.03), "skin", W(hb), rings=4, seg=6)


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
