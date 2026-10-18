"""sim-4 Folk character builder (Blender 5.1, headless).

Run:
  "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python blender/folk.py
Options (after `--`):  --only folk_adult,folk_child   build a subset
                       --render DIR                    also render pose strips (workbench) into DIR
Outputs assets/models/folk_{adult,teen,child,elder,toddler,baby}.glb (+ folk.glb = copy of adult)
and blender/folk/clips.json (clip list).

Conventions: Blender Z up, character faces +Y (glTF/Godot -Z), character's right hand = +X ("_R").
Pose rotations are expressed in ARMATURE axes (X right, Y forward, Z up), relative to the parent bone:
    +X rotation swings a hanging limb FORWARD / leans a standing torso BACK,
    +Y rotation abducts the left limb (-X side) / adducts the right,
    +Z rotation turns the part counter-clockwise seen from above (to the character's left).
"""
import bpy, bmesh, math, os, sys, json, shutil
from mathutils import Vector, Matrix, Euler, Quaternion

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)
TAU = math.tau
PI = math.pi
FPS = 24

# ------------------------------------------------------------------ variants
VARIANTS = {
    #  name          scale  head-scale  stoop  baby
    "folk_adult":   dict(s=1.00, hs=1.00, stoop=0.0, w=1.00),
    "folk_teen":    dict(s=0.92, hs=1.05, stoop=0.0, w=0.95),
    "folk_child":   dict(s=0.68, hs=1.30, stoop=0.0, w=0.95),
    "folk_elder":   dict(s=0.96, hs=1.00, stoop=1.0, w=1.00),
    "folk_toddler": dict(s=0.50, hs=1.45, stoop=0.0, w=1.05),
    "folk_baby":    dict(s=0.30, hs=1.65, stoop=0.0, w=1.15),
}

# ------------------------------------------------------------------ materials
MATS = {  # name: (rgb, roughness)
    "skin":     ((0.90, 0.70, 0.56), 0.75),
    "hair":     ((0.25, 0.15, 0.10), 0.85),
    "eyes":     ((0.20, 0.30, 0.45), 0.2),
    "eyewhite": ((0.96, 0.96, 0.95), 0.3),
    "mouth":    ((0.62, 0.25, 0.25), 0.6),
    "shirt":    ((0.30, 0.52, 0.82), 0.9),
    "pants":    ((0.25, 0.26, 0.40), 0.9),
    "shoes":    ((0.14, 0.11, 0.10), 0.8),
}


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*col, 1.0)
    return m


# ------------------------------------------------------------------ skeleton (adult units, metres, Blender axes)
# name: (head, tail, parent)
def skeleton(hs):
    hz = 1.46
    B = {
        "hips":    ((0, 0, 0.93), (0, 0, 1.00), None),
        "spine":   ((0, 0, 1.00), (0, 0, 1.14), "hips"),
        "chest":   ((0, 0, 1.14), (0, 0, 1.34), "spine"),
        "neck":    ((0, 0, 1.38), (0, 0, hz), "chest"),
        "head":    ((0, 0, hz), (0, 0, hz + 0.26 * hs), "neck"),
    }
    for side, sx in (("L", -1), ("R", 1)):
        B["shoulder_" + side] = ((sx * 0.03, 0, 1.33), (sx * 0.17, 0, 1.33), "chest")
        B["upper_arm_" + side] = ((sx * 0.19, 0, 1.33), (sx * 0.215, 0, 1.05), "shoulder_" + side)
        B["forearm_" + side] = ((sx * 0.215, 0, 1.05), (sx * 0.235, 0, 0.80), "upper_arm_" + side)
        B["hand_" + side] = ((sx * 0.235, 0, 0.80), (sx * 0.245, 0, 0.69), "forearm_" + side)
        B["thigh_" + side] = ((sx * 0.09, 0, 0.93), (sx * 0.09, 0, 0.50), "hips")
        B["shin_" + side] = ((sx * 0.09, 0, 0.50), (sx * 0.09, 0, 0.085), "thigh_" + side)
        B["foot_" + side] = ((sx * 0.09, 0, 0.085), (sx * 0.09, 0.16, 0.03), "shin_" + side)
    return B


BONE_ORDER = ["hips", "spine", "chest", "neck", "head",
              "shoulder_L", "upper_arm_L", "forearm_L", "hand_L", "shoulder_R", "upper_arm_R", "forearm_R", "hand_R",
              "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]


# ------------------------------------------------------------------ mesh builder
class Mesher:
    def __init__(self, bones, S):
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.bones = bones
        self.S = S
        self.mats = []

    def mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _w(self, v, wd):
        for b, w in wd.items():
            if w > 0.001:
                v[self.dl][self.bones.index(b)] = w

    def ring_mesh(self, rings, mat, wfn, seg=10, smooth=True, clip=None):
        """rings: list of (center Vector, u Vector, v Vector, ru, rv); ru<=0 & rv<=0 -> pole.
        Coordinates in adult units; scaled by S on creation. wfn(unit_pos)->weights dict."""
        bm = self.bm
        mid = self.mi(mat)
        grid = []
        newv = []
        for (c, u, v, ru, rv) in rings:
            if ru < 1e-6 and rv < 1e-6:
                vv = bm.verts.new(c * self.S)
                vv.co = c * self.S
                self._w(vv, wfn(c))
                grid.append([vv])
                newv.append(vv)
            else:
                row = []
                for k in range(seg):
                    a = TAU * k / seg
                    p = c + u * (ru * math.cos(a)) + v * (rv * math.sin(a))
                    vv = bm.verts.new(p * self.S)
                    self._w(vv, wfn(p))
                    row.append(vv)
                    newv.append(vv)
                grid.append(row)
        faces = []

        def addf(vs):
            try:
                f = bm.faces.new(vs)
                f.material_index = mid
                f.smooth = smooth
                faces.append(f)
            except ValueError:
                pass
        for i in range(len(grid) - 1):
            a, b = grid[i], grid[i + 1]
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                for k in range(seg):
                    addf((a[0], b[(k + 1) % seg], b[k]))
            elif len(b) == 1:
                for k in range(seg):
                    addf((a[k], a[(k + 1) % seg], b[0]))
            else:
                for k in range(seg):
                    k2 = (k + 1) % seg
                    addf((a[k], a[k2], b[k2], b[k]))
        # caps for open ends
        for row in (grid[0], grid[-1]):
            if len(row) > 1:
                cen = bm.verts.new(sum((v.co for v in row), Vector()) / len(row))
                cen.co = sum((v.co for v in row), Vector()) / len(row)
                # copy weights of first vertex
                for g, w in row[0][self.dl].items():
                    cen[self.dl][g] = w
                for k in range(seg):
                    if row is grid[0]:
                        addf((cen, row[(k + 1) % seg], row[k]))
                    else:
                        addf((cen, row[k], row[(k + 1) % seg]))
        if clip is not None:
            # remove vertices rejected by clip(unit_pos) -> keep?
            kill = [v for v in newv if v.is_valid and not clip(v.co / self.S)]
            bmesh.ops.delete(bm, geom=kill, context='VERTS')
        return faces

    # --- primitives
    def tube(self, p0, p1, prof, mat, wfn, seg=10):
        a, c = Vector(p0), Vector(p1)
        ax = (c - a).normalized()
        u = Vector((1, 0, 0)) if abs(ax.x) < 0.9 else Vector((0, 1, 0))
        u = (u - ax * u.dot(ax)).normalized()
        v = ax.cross(u)
        rings = [(a.lerp(c, t), u, v, ru, rv) for (t, ru, rv) in prof]
        self.ring_mesh(rings, mat, wfn, seg)

    def ellipsoid(self, c, r, mat, wfn, rings=7, seg=10, clip=None):
        c = Vector(c)
        rr = []
        for i in range(rings + 1):
            ph = PI * i / rings
            z = -math.cos(ph) * r[2]
            s = math.sin(ph)
            ru, rv = r[0] * s, r[1] * s
            if i in (0, rings):
                ru = rv = 0
            rr.append((c + Vector((0, 0, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), ru, rv))
        self.ring_mesh(rr, mat, wfn, seg, clip=clip)

    def finish(self, name, arm):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for b in self.bones:
            ob.vertex_groups.new(name=b)
        for m in self.mats:
            me.materials.append(get_mat(m))
        for p in me.polygons:
            p.use_smooth = True
        ob.parent = arm
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
        return ob


def W(b):
    return lambda p: {b: 1.0}


def ramp(x, a, b):
    return max(0.0, min(1.0, (x - a) / (b - a)))


# ------------------------------------------------------------------ body geometry
def build_body(M, hs, wd):
    """wd: width multiplier. Adds body parts to Mesher M. Returns head centre (adult units)."""
    V = Vector
    # --- weights
    def w_torso(p):
        z = p.z
        a = ramp(z, 0.96, 1.04)      # hips -> spine
        b = ramp(z, 1.10, 1.18)      # spine -> chest
        wh = 1 - a
        ws = a * (1 - b)
        wc = a * b
        d = {"hips": wh, "spine": ws, "chest": wc}
        if z > 1.34:
            n = ramp(z, 1.34, 1.42)
            d = {"chest": 1 - n * 0.5, "neck": n * 0.5}
        return d

    def w_hips(p):
        return {"hips": 1.0} if p.z < 1.0 else w_torso(p)

    # pants pelvis
    M.tube(V((0, 0, 0.84)), V((0, 0, 1.08)),
           [(0.0, 0.07 * wd, 0.06 * wd), (0.04, 0.12 * wd, 0.09 * wd), (0.36, 0.172 * wd, 0.112 * wd),
            (0.7, 0.158 * wd, 0.104 * wd), (1.0, 0.150 * wd, 0.100 * wd)], "pants", w_hips, seg=12)
    # shirt torso
    M.tube(V((0, 0, 0.99)), V((0, 0, 1.43)),
           [(0.0, 0.172 * wd, 0.116 * wd), (0.12, 0.158 * wd, 0.108 * wd), (0.30, 0.142 * wd, 0.100 * wd),
            (0.5, 0.163 * wd, 0.105 * wd), (0.72, 0.188 * wd, 0.112 * wd), (0.88, 0.196 * wd, 0.104 * wd),
            (0.96, 0.130 * wd, 0.085 * wd), (1.0, 0.070, 0.060)], "shirt", w_torso, seg=14)
    # neck
    M.tube(V((0, 0, 1.36)), V((0, 0, 1.50)), [(0, 0.052, 0.05), (1, 0.046, 0.046)], "skin",
           lambda p: {"neck": 1.0} if p.z > 1.40 else {"neck": 0.5, "chest": 0.5}, seg=8)

    for side, sx in (("L", -1), ("R", 1)):
        # arms
        sh = V((sx * 0.19, 0, 1.33))
        el = V((sx * 0.215, 0, 1.05))
        wr = V((sx * 0.235, 0, 0.80))
        ua, fa = "upper_arm_" + side, "forearm_" + side

        def w_ua(p, ua=ua, fa=fa, side=side):
            t = ramp(p.z, 1.05, 0.90)   # approaching elbow from above
            top = ramp(p.z, 1.25, 1.36)
            d = {ua: 1 - 0.5 * t, fa: 0.5 * t}
            if top > 0:
                d = {ua: (1 - top) * (1 - 0.5 * t) + top * 0.5, "shoulder_" + side: top * 0.25, "chest": top * 0.25}
            return d

        def w_fa(p, ua=ua, fa=fa):
            t = ramp(p.z, 1.05, 1.0 - 0.0001) if False else ramp(1.05 - p.z, 0.0, 0.08)
            return {fa: 0.5 + 0.5 * t, ua: 0.5 - 0.5 * t}
        M.ellipsoid(V((sx * 0.185, 0, 1.325)), (0.07 * wd, 0.068 * wd, 0.07 * wd), "shirt", w_ua)    # deltoid
        M.tube(sh, el, [(0, 0.062 * wd, 0.060 * wd), (0.5, 0.055 * wd, 0.054 * wd), (0.93, 0.050 * wd, 0.049 * wd),
                        (1.0, 0.0, 0.0)], "shirt", w_ua)
        M.tube(V((sx * 0.215, 0, 1.075)), wr, [(0, 0.0, 0.0), (0.07, 0.046 * wd, 0.046 * wd), (0.55, 0.040 * wd, 0.040 * wd),
                                               (1.0, 0.031 * wd, 0.030 * wd)], "skin", w_fa, seg=8)
        M.ellipsoid(el, (0.047 * wd, 0.047 * wd, 0.047 * wd), "skin", lambda p, ua=ua, fa=fa: {ua: 0.5, fa: 0.5}, rings=5, seg=8)
        # hand (mitten + thumb)
        hb = "hand_" + side
        M.ellipsoid(V((sx * 0.243, 0.0, 0.725)), (0.026, 0.045, 0.062), "skin", W(hb), rings=6, seg=8)
        M.ellipsoid(V((sx * 0.243 - sx * 0.01, 0.045, 0.745)), (0.013, 0.014, 0.03), "skin", W(hb), rings=4, seg=6)
        # legs
        th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side
        hip, kn, an = V((sx * 0.09, 0, 0.93)), V((sx * 0.09, 0, 0.50)), V((sx * 0.09, 0, 0.085))

        def w_th(p, th=th, sn=sn):
            t = ramp(0.55 - p.z, 0.0, 0.10)
            return {th: 1 - 0.5 * t, sn: 0.5 * t}

        def w_sn(p, th=th, sn=sn, ft=ft):
            t = ramp(0.55 - p.z, 0.0, 0.10)
            f = ramp(0.16 - p.z, 0.0, 0.07)
            return {th: 0.5 * (1 - t) if p.z > 0.45 else 0.0, sn: (0.5 + 0.5 * t) * (1 - f), ft: f * 0.4 + 0, **({} if f == 0 else {})}
        M.tube(hip, kn, [(0.0, 0.092 * wd, 0.092 * wd), (0.25, 0.088 * wd, 0.089 * wd), (0.75, 0.066 * wd, 0.066 * wd), (1.0, 0.058 * wd, 0.058 * wd)],
               "pants", w_th, seg=10)
        M.tube(kn + V((0, 0, 0.03)), an + V((0, 0, 0.02)), [(0.0, 0.058 * wd, 0.058 * wd), (0.3, 0.054 * wd, 0.054 * wd), (1.0, 0.040 * wd, 0.040 * wd)],
               "pants", w_sn, seg=10)
        M.ellipsoid(kn, (0.058 * wd, 0.058 * wd, 0.058 * wd), "pants", lambda p, th=th, sn=sn: {th: 0.5, sn: 0.5}, rings=5, seg=8)
        # shoe
        M.ellipsoid(V((sx * 0.09, 0.05, 0.048)), (0.052, 0.135, 0.050), "shoes", W(ft), rings=6, seg=10)
        M.ellipsoid(V((sx * 0.09, -0.01, 0.07)), (0.045, 0.06, 0.06), "shoes", W(ft), rings=5, seg=8)


def build_head(M, hs, hair_meshers):
    """Head parts, all weighted to 'head'. Positions are head-local * hs about the head centre."""
    V = Vector
    hc = V((0, 0.005, 1.46 + 0.115 * hs - 0.012 * hs + 0.0))
    # head-local -> adult-unit position
    H = lambda x, y, z: hc + V((x, y, z)) * hs
    hw = W("head")

    def E(c, r, mat, **kw):
        M.ellipsoid(H(*c), tuple(v * hs for v in r), mat, hw, **kw)
    E((0, 0, 0), (0.093, 0.105, 0.115), "skin", rings=9, seg=14)            # cranium
    E((0, 0.022, -0.065), (0.072, 0.072, 0.060), "skin", rings=6, seg=10)   # jaw / chin
    for sx in (-1, 1):
        E((sx * 0.094, 0.0, -0.005), (0.012, 0.02, 0.03), "skin", rings=4, seg=6)           # ears
        E((sx * 0.037, 0.088, 0.015), (0.019, 0.012, 0.016), "eyewhite", rings=4, seg=8)    # eye white
        E((sx * 0.037, 0.096, 0.015), (0.011, 0.006, 0.011), "eyes", rings=4, seg=8)         # iris
        E((sx * 0.037, 0.092, 0.047), (0.025, 0.008, 0.006), "hair", rings=3, seg=6)         # brow
    E((0, 0.104, -0.015), (0.014, 0.020, 0.022), "skin", rings=4, seg=6)                    # nose
    E((0, 0.088, -0.05), (0.023, 0.008, 0.006), "mouth", rings=3, seg=8)                    # mouth

    # ---- hair styles (separate meshers -> separate objects)
    def cap(m, grow=0.012, back=0.0, top=0.0, low=0.06):
        # skull cap that leaves the face/ears free
        def keep(p):
            q = (p - hc) / hs
            return q.z > low or (q.y < -0.025 and q.z > -0.075) and abs(q.x) < 0.09 or (q.z > -0.02 and q.y < -0.06)
        m.ellipsoid(H(0, -0.012 + back * 0.4, 0.016 + top * 0.3),
                    (hs * (0.093 + grow), hs * (0.108 + grow + back), hs * (0.113 + grow + top)),
                    "hair", W("head"), rings=9, seg=14, clip=keep)
    hh = lambda m, c, r, **kw: m.ellipsoid(H(*c), tuple(v * hs for v in r), "hair", W("head"), **kw)
    # 0 short crop
    cap(hair_meshers[0], 0.012)
    hh(hair_meshers[0], (0, 0.075, 0.075), (0.085, 0.03, 0.03), rings=4, seg=8)   # fringe
    # 1 buzz cut (tight)
    cap(hair_meshers[1], 0.005, low=0.02)
    # 2 long hair
    cap(hair_meshers[2], 0.014)
    hh(hair_meshers[2], (0, -0.075, -0.08), (0.105, 0.06, 0.20), rings=7, seg=10)
    hh(hair_meshers[2], (-0.085, -0.02, 0.0), (0.02, 0.05, 0.10), rings=5, seg=8)
    hh(hair_meshers[2], (0.085, -0.02, 0.0), (0.02, 0.05, 0.10), rings=5, seg=8)
    hh(hair_meshers[2], (0, 0.075, 0.075), (0.09, 0.03, 0.03), rings=4, seg=8)
    # 3 ponytail
    cap(hair_meshers[3], 0.012)
    hh(hair_meshers[3], (0, -0.12, 0.03), (0.04, 0.04, 0.04), rings=4, seg=8)
    hh(hair_meshers[3], (0, -0.15, -0.05), (0.032, 0.032, 0.08), rings=5, seg=8)
    hh(hair_meshers[3], (0, -0.16, -0.14), (0.025, 0.025, 0.07), rings=5, seg=8)
    # 4 spiky
    cap(hair_meshers[4], 0.008)
    import random
    for i, (x, y, ang) in enumerate([(0, 0.0, 0.0), (-0.05, 0.03, -0.5), (0.05, 0.03, 0.5), (-0.05, -0.05, -0.6), (0.05, -0.05, 0.6),
                                      (0, -0.07, 0.0), (0, 0.07, 0.0)]):
        base = H(x, y, 0.1)
        d = V((math.sin(ang) * 0.6, (0.4 if y > 0.05 else -0.4 if y < -0.06 else 0.0) * 0.6, 1.0)).normalized()
        hair_meshers[4].tube(base, base + d * 0.11 * hs, [(0, 0.03 * hs, 0.03 * hs), (1.0, 0, 0)], "hair", W("head"), seg=6)
    # 5 curly / afro
    hair_meshers[5].ellipsoid(H(0, -0.01, 0.035), (0.135 * hs, 0.135 * hs, 0.125 * hs), "hair", W("head"), rings=8, seg=14,
                              clip=lambda p: not (((p - hc) / hs).y > 0.01 and ((p - hc) / hs).z < 0.06) and ((p - hc) / hs).z > -0.065)


# ------------------------------------------------------------------ armature
def build_armature(name, S, hs):
    bd = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name, bd)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    sk = skeleton(hs)
    for bn in BONE_ORDER:
        h, t, par = sk[bn]
        eb = bd.edit_bones.new(bn)
        eb.head = Vector(h) * S
        eb.tail = Vector(t) * S
        eb.roll = 0
    for bn in BONE_ORDER:
        par = sk[bn][2]
        if par:
            bd.edit_bones[bn].parent = bd.edit_bones[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


# ------------------------------------------------------------------ pose library
class Pose:
    def __init__(self):
        self.r = {}
        self.loc = Vector((0, 0, 0))

    def rot(self, bone, x=0.0, y=0.0, z=0.0, tw=0.0):
        o = self.r.get(bone, (0, 0, 0, 0))
        self.r[bone] = (o[0] + x, o[1] + y, o[2] + z, o[3] + tw)
        return self

    def move(self, x=0.0, y=0.0, z=0.0):
        self.loc += Vector((x, y, z))
        return self

    # arms: fwd=raise forward, out=abduct, across=sweep toward the midline (rotation about Z, after raise), elbow=flex
    def arm(self, side, fwd=0.0, out=0.0, elbow=0.0, across=0.0, tw=0.0, wrist=0.0):
        sg = -1 if side == "L" else 1
        self.r["upper_arm_" + side] = (fwd, -sg * out, (across if side == "R" else -across), tw)
        self.r["forearm_" + side] = (elbow, 0, 0, 0)
        self.r["hand_" + side] = (wrist, 0, 0, 0)
        return self

    def leg(self, side, hip=0.0, knee=0.0, foot=0.0, out=0.0):
        sg = -1 if side == "L" else 1
        self.r["thigh_" + side] = (hip, -sg * out, 0, 0)
        self.r["shin_" + side] = (-knee, 0, 0, 0)
        self.r["foot_" + side] = (foot, 0, 0, 0)
        return self

    def relax(self, a=0.08, e=0.14):
        self.arm("L", 0.04, a, e)
        self.arm("R", 0.04, a, e)
        self.leg("L", out=0.03)
        self.leg("R", out=0.03)
        return self

    def sit(self, drop=0.40, knees=1.50):
        self.move(0, -0.02, -drop)
        for s in "LR":
            self.leg(s, knees, knees, 0.0, 0.05)
        return self

    def lie(self, drop=0.78):
        self.rot("hips", PI / 2)
        self.move(0, 0, -drop)
        return self

    def lerp(self, o, k):
        n = Pose()
        for b in set(self.r) | set(o.r):
            a = self.r.get(b, (0, 0, 0, 0))
            c = o.r.get(b, (0, 0, 0, 0))
            n.r[b] = tuple(a[i] * (1 - k) + c[i] * k for i in range(4))
        n.loc = self.loc.lerp(o.loc, k)
        return n


sn = lambda t, n=1, ph=0.0: math.sin(TAU * n * t + ph)
cs = lambda t, n=1, ph=0.0: math.cos(TAU * n * t + ph)
pos = lambda x: max(0.0, x)

LEGLEN = 0.86


def walk_pose(t, A=0.55, K=0.7, arm=0.5, elbow=0.35, lean=0.04, sway=0.02, hold=None, bob=0.75):
    ph = TAU * t
    p = Pose().relax()
    aL, aR = A * math.sin(ph), -A * math.sin(ph)
    kL = 0.10 + K * pos(math.cos(ph + 0.4))
    kR = 0.10 + K * pos(math.cos(ph + PI + 0.4))
    p.leg("L", aL, kL, -0.6 * (aL - kL), 0.02)
    p.leg("R", aR, kR, -0.6 * (aR - kR), 0.02)
    if hold:
        hold(p)
    else:
        p.arm("L", -arm * math.sin(ph), 0.07, elbow + 0.25 * pos(-math.sin(ph)))
        p.arm("R", arm * math.sin(ph), 0.07, elbow + 0.25 * pos(math.sin(ph)))
    p.rot("hips", 0, 0, 0.07 * math.sin(ph))
    p.rot("chest", -lean, 0, -0.12 * math.sin(ph))
    p.rot("head", lean * 0.5, 0, 0.05 * math.sin(ph))
    drop = LEGLEN * (1 - math.cos(max(abs(aL), abs(aR)))) * bob
    p.move(sway * math.sin(ph), 0, -drop)
    return p


def run_pose(t, A=0.95, K=1.55, arm=0.9, lean=0.17, hipz=-0.05, fly=0.05):
    ph = TAU * t
    p = Pose().relax()
    aL, aR = A * math.sin(ph) - 0.1, -A * math.sin(ph) - 0.1
    kL = 0.25 + K * pos(math.cos(ph + 0.5))
    kR = 0.25 + K * pos(math.cos(ph + PI + 0.5))
    p.leg("L", aL, kL, -0.4 * (aL - kL), 0.02)
    p.leg("R", aR, kR, -0.4 * (aR - kR), 0.02)
    p.arm("L", -arm * math.sin(ph), 0.1, 1.5)
    p.arm("R", arm * math.sin(ph), 0.1, 1.5)
    p.rot("hips", 0, 0, 0.10 * math.sin(ph))
    p.rot("chest", -lean, 0, -0.18 * math.sin(ph))
    p.rot("head", lean * 0.8, 0, 0.08 * math.sin(ph))
    p.move(0.012 * math.sin(ph), 0, hipz + fly * math.sin(ph) ** 2)
    return p


def idle_pose(t):
    p = Pose().relax()
    p.rot("chest", 0.018 * sn(t), 0, 0.02 * sn(t))
    p.rot("spine", 0.01 * sn(t))
    p.rot("head", 0.02 * sn(t, 1, 1.0), 0.03 * sn(t), 0.10 * sn(t, 1, 0.5))
    p.arm("L", 0.0, 0.0, 0.0)
    p.arm("L", 0.02 * sn(t, 1, 0.3), 0.01 * sn(t))
    p.arm("R", 0.02 * sn(t, 1, 1.3), 0.01 * sn(t))
    p.move(0.012 * sn(t), 0, 0.004 * sn(t, 2))
    p.rot("hips", 0, 0.015 * sn(t), 0)
    p.leg("L", 0.0, 0.0, 0.0, 0.0)
    return p


def sit_base(t, lean=0.0, hands="lap"):
    p = Pose().sit()
    p.rot("hips", 0.0)
    p.rot("spine", lean * 0.5 + 0.012 * sn(t))
    p.rot("chest", lean * 0.5 + 0.01 * sn(t))
    p.rot("foot_L", 0.0)
    if hands == "lap":
        p.arm("L", 0.45, 0.07, 1.15, 0.12)
        p.arm("R", 0.45, 0.07, 1.15, 0.12)
    return p


def sit_idle(t):
    p = sit_base(t)
    p.rot("head", 0.02 * sn(t, 1, 1.0), 0.0, 0.14 * sn(t, 1, 0.3))
    p.rot("forearm_R", 0.05 * sn(t, 2))
    p.leg("L", 1.5 + 0.03 * sn(t, 1), 1.5, 0, 0.05 + 0.03 * sn(t, 1, 1))
    return p


def sit_eat(t):
    p = sit_base(t, lean=-0.10, hands=None)
    bite = 0.5 - 0.5 * math.cos(TAU * t * 2)       # two bites per loop
    p.arm("R", 0.45 + 0.25 * bite, 0.12, 0.85 + 1.35 * bite, 0.15 * bite)
    p.arm("L", 0.9, 0.1, 0.75, 0.2)
    p.rot("head", 0.10 * bite - 0.05, 0, 0.0)
    p.rot("chest", -0.04 * bite)
    return p


def sit_watch(t):
    p = sit_base(t, lean=0.10)
    p.rot("head", 0.04 + 0.02 * sn(t, 3), 0.0, 0.06 * sn(t, 1))
    p.rot("chest", 0.015 * sn(t, 3))
    p.arm("L", 0.55, 0.15, 1.3, 0.1)
    p.arm("R", 0.30 + 0.05 * sn(t, 1), 0.2, 0.9 + 0.1 * pos(sn(t, 2)), 0.1)
    return p


def sleep_pose(t):
    p = Pose().lie()
    p.rot("chest", 0.02 * sn(t))
    p.rot("head", -0.05, 0.05)
    p.arm("L", 0.0, 0.12, 0.25)
    p.arm("R", 0.05, 0.14, 0.35)
    p.leg("L", 0.0, 0.05, 0.1, 0.07)
    p.leg("R", 0.05, 0.1, 0.1, 0.1)
    p.move(0, 0.0, 0.004 * sn(t))
    return p


def use_stand(t):
    p = Pose().relax()
    p.rot("chest", -0.07)
    p.rot("head", -0.08 + 0.02 * sn(t), 0, 0.05 * sn(t))
    p.arm("L", 0.55 + 0.04 * sn(t), 0.12, 1.25 + 0.08 * sn(t, 2))
    p.arm("R", 0.55 + 0.05 * sn(t, 1, 1.0), 0.12, 1.25 + 0.10 * sn(t, 2, 0.5))
    p.rot("hips", 0, 0.01 * sn(t))
    return p


def cook(t):
    p = Pose().relax()
    p.rot("spine", -0.10)
    p.rot("chest", -0.08)
    p.rot("head", -0.12)
    p.arm("R", 0.65 + 0.10 * sn(t), 0.12, 1.15 + 0.12 * cs(t), 0.0 + 0.28 * cs(t), 0)
    p.arm("L", 0.55, 0.15, 1.25, 0.25)
    p.rot("hand_R", 0.2 * sn(t, 2))
    return p


def wash(t):
    p = Pose().relax()
    p.rot("spine", -0.14)
    p.rot("chest", -0.12)
    p.rot("head", -0.18)
    p.arm("L", 0.55, 0.05, 1.35, 0.4 + 0.05 * sn(t, 2))
    p.arm("R", 0.55, 0.05, 1.35, 0.4 - 0.05 * sn(t, 2))
    p.rot("forearm_L", 0.14 * sn(t, 3))
    p.rot("forearm_R", -0.14 * sn(t, 3))
    return p


def read(t):
    p = Pose().relax()
    p.rot("chest", -0.03)
    p.rot("head", -0.32 + 0.02 * sn(t))
    flip = pos(sn(t, 1, 1.0)) ** 8
    p.arm("L", 0.55, 0.07, 1.55, 0.35)
    p.arm("R", 0.55 + 0.1 * flip, 0.07, 1.55 + 0.15 * flip, 0.35 - 0.3 * flip)
    p.rot("chest", 0.01 * sn(t))
    p.move(0.01 * sn(t))
    return p


def treadmill(t):
    p = run_pose(t, A=0.75, K=1.2, arm=0.8, lean=0.08, hipz=-0.03, fly=0.03)
    return p


def paint(t):
    p = Pose().relax()
    p.rot("spine", -0.04)
    p.rot("chest", -0.04, 0, 0.12)
    p.rot("head", -0.10 + 0.02 * sn(t, 2), 0, 0.12 * sn(t, 1, 0.5) - 0.08)
    sw = sn(t)
    p.arm("R", 1.25 + 0.08 * sn(t, 2), 0.15, 0.7 + 0.18 * sn(t, 2, 1.0), 0.15 + 0.25 * sw)
    p.arm("L", 0.7, 0.1, 1.7, 0.45)
    p.leg("L", 0.0, 0.0, 0, 0.12)
    p.leg("R", 0.05, 0.05, 0, 0.12)
    p.move(0.015 * sw)
    return p


def typing(t):
    p = Pose().relax()
    p.rot("spine", -0.05)
    p.rot("chest", -0.06)
    p.rot("head", -0.05 + 0.015 * sn(t, 2))
    p.arm("L", 0.50, 0.15, 1.20, 0.18)
    p.arm("R", 0.50, 0.15, 1.20, 0.18)
    p.rot("hand_L", -0.20 + 0.15 * sn(t, 6), 0)
    p.rot("hand_R", -0.20 + 0.15 * sn(t, 5, 1.3), 0)
    p.rot("forearm_L", 0.03 * sn(t, 6, 2))
    return p


def dance(t):
    ph = TAU * t
    p = Pose().relax()
    p.move(0.06 * math.sin(ph), 0, -0.05 - 0.04 * math.cos(2 * ph))
    p.rot("hips", 0, 0.12 * math.sin(ph), 0.18 * math.sin(ph))
    p.rot("chest", -0.04, -0.10 * math.sin(ph), -0.22 * math.sin(ph))
    p.rot("head", 0.04 * math.cos(2 * ph), 0.12 * math.sin(ph + 0.8), 0.12 * math.sin(ph))
    p.leg("L", 0.25 + 0.2 * math.cos(2 * ph), 0.5 + 0.4 * pos(math.cos(ph)), 0, 0.14)
    p.leg("R", 0.25 + 0.2 * math.cos(2 * ph + PI), 0.5 + 0.4 * pos(-math.cos(ph)), 0, 0.14)
    p.arm("L", 1.0 + 0.7 * math.sin(2 * ph), 0.7 + 0.2 * math.cos(ph), 1.2 + 0.5 * math.sin(2 * ph + 1))
    p.arm("R", 1.0 + 0.7 * math.sin(2 * ph + PI), 0.7 - 0.2 * math.cos(ph), 1.2 + 0.5 * math.sin(2 * ph + 1 + PI))
    return p


def talk(t):
    p = Pose().relax()
    g = sn(t, 1)
    p.rot("chest", 0.0, 0, 0.06 * sn(t, 1, 0.5))
    p.rot("head", 0.05 * sn(t, 3), 0.04 * sn(t, 2), 0.10 * sn(t, 1, 1.0))
    p.arm("R", 0.75 + 0.30 * g, 0.28, 1.25 + 0.30 * sn(t, 2, 0.6), 0.1 + 0.15 * cs(t))
    p.arm("L", 0.35 + 0.20 * pos(sn(t, 1, 2.0)), 0.18, 1.0 + 0.2 * pos(sn(t, 1, 2.0)), 0.15)
    p.move(0.01 * sn(t))
    return p


def laugh(t):
    ph = TAU * t
    p = Pose().relax()
    p.rot("head", 0.30 + 0.05 * math.sin(3 * ph), 0, 0.0)
    p.rot("chest", 0.10 + 0.07 * math.sin(3 * ph + 0.5), 0, 0)
    p.rot("spine", 0.06)
    p.move(0, 0, -0.03 + 0.012 * math.sin(3 * ph))
    p.leg("L", 0.08, 0.2, 0, 0.05)
    p.leg("R", 0.08, 0.2, 0, 0.05)
    p.arm("R", 0.55, 0.12, 1.65, 0.5 + 0.05 * math.sin(3 * ph))
    p.arm("L", 0.25, 0.25 + 0.1 * math.sin(3 * ph), 0.5)
    return p


def wave(t):
    ph = TAU * t
    p = Pose().relax()
    p.rot("head", 0.0, 0.05, -0.1 + 0.05 * math.sin(ph))
    p.arm("R", 0.15, 1.25, 1.7 - 0.15 * math.cos(ph), 0.0, 1.35 + 0.5 * math.sin(2 * ph))
    p.rot("chest", 0, -0.03, 0.04 * math.sin(2 * ph))
    return p


def cry(t):
    ph = TAU * t
    p = Pose().relax()
    sob = math.sin(3 * ph) * 0.5 + 0.5
    p.rot("chest", -0.22 - 0.03 * sob)
    p.rot("spine", -0.10)
    p.rot("head", -0.38 - 0.03 * sob)
    p.move(0, 0, -0.012 * sob)
    p.arm("L", 0.65, -0.05, 2.35, 0.35 - 0.0, 0, 0)
    p.arm("R", 0.65, -0.05, 2.35, 0.35)
    p.rot("forearm_L", 0.04 * math.sin(3 * ph))
    p.rot("forearm_R", 0.04 * math.sin(3 * ph + 1))
    return p


def angry(t):
    ph = TAU * t
    p = Pose().relax()
    p.rot("spine", -0.06)
    p.rot("chest", -0.12, 0, 0.0)
    p.rot("head", -0.12 + 0.02 * math.sin(6 * ph), 0, 0.05 * math.sin(6 * ph))
    p.arm("L", 0.15, 0.22, 1.5, 0.0)
    p.arm("R", 0.15, 0.22, 1.5, 0.0)
    p.rot("hand_L", -0.2)
    p.rot("hand_R", -0.2)
    p.rot("upper_arm_L", 0.05 * math.sin(6 * ph))
    p.rot("upper_arm_R", 0.05 * math.sin(6 * ph + 1))
    p.leg("L", 0.0, 0.0, 0.0, 0.14)
    p.leg("R", 0.0 + 0.5 * pos(math.sin(ph * 2)) ** 3 * 0, 0.0, 0.0, 0.14)
    p.move(0, 0, -0.03 + 0.01 * math.sin(6 * ph))
    return p


def sad_idle(t):
    p = Pose().relax(0.04, 0.12)
    p.rot("spine", -0.12)
    p.rot("chest", -0.16 + 0.015 * sn(t))
    p.rot("head", -0.38 + 0.02 * sn(t, 1, 1.0), 0, 0.06 * sn(t, 1, 0.4))
    p.arm("L", 0.12, 0.05, 0.15)
    p.arm("R", 0.12, 0.05, 0.15)
    p.rot("shoulder_L", 0, 0, 0)
    p.move(0, 0, -0.012 + 0.003 * sn(t))
    p.leg("L", 0.02, 0.05, 0, 0.0)
    p.leg("R", 0.02, 0.05, 0, 0.0)
    return p


def hug(t):
    ph = TAU * t
    sq = 0.5 - 0.5 * math.cos(ph)
    p = Pose().relax()
    p.rot("spine", -0.08 - 0.03 * sq)
    p.rot("chest", -0.06 - 0.04 * sq)
    p.rot("head", 0.0, 0.18, 0.0)
    for s in "LR":
        p.arm(s, 1.15, 0.65 - 0.35 * sq, 0.7 + 0.3 * sq, 0.25 + 0.1 * sq, 0.0)
    p.leg("L", 0.05, 0.1, 0, 0.1)
    p.leg("R", 0.05, 0.1, 0, 0.1)
    p.move(0, 0.02, -0.01)
    return p


def kiss(t):
    ph = TAU * t
    pop = pos(math.sin(ph)) ** 2
    p = Pose().relax()
    p.rot("spine", -0.10)
    p.rot("chest", -0.10)
    p.rot("head", 0.04 * math.sin(2 * ph), 0.22, 0.0)
    p.arm("L", 1.1, 0.35, 0.9, 0.3)
    p.arm("R", 1.2, 0.35, 0.8, 0.25)
    p.leg("R", -0.45 * pop, 1.0 * pop, 0.5 * pop, 0.0)
    p.leg("L", 0.0, 0.0, 0.0, 0.02)
    p.move(0, 0.02, 0)
    return p


def carry(t):
    def hold(p):
        p.arm("L", 0.85, 0.02, 1.35, 0.55)
        p.arm("R", 0.85, 0.02, 1.35, 0.55)
    return walk_pose(t, A=0.45, K=0.6, hold=hold, lean=-0.05)


def shower(t):
    ph = TAU * t
    m = 0.5 + 0.5 * math.sin(ph)    # 1 = hands up scrubbing hair, 0 = washing chest
    p = Pose().relax()
    up = Pose()
    up.arm("L", 2.3, 0.35, 1.7, 0.1)
    up.arm("R", 2.3, 0.35, 1.7, 0.1)
    up.rot("forearm_L", 0.30 * math.sin(6 * ph))
    up.rot("forearm_R", -0.30 * math.sin(6 * ph))
    up.rot("head", 0.30)
    dn = Pose()
    dn.arm("L", 0.7, 0.05, 1.5, 0.55)
    dn.arm("R", 0.7, 0.05, 1.5, 0.55)
    dn.rot("forearm_R", 0.2 * math.sin(6 * ph))
    dn.rot("head", -0.1)
    dn.rot("chest", -0.08)
    mix = dn.lerp(up, m)
    for b, v in mix.r.items():
        p.r[b] = v
    return p


def toilet_sit(t):
    p = sit_base(t, lean=-0.18, hands=None)
    p.rot("head", -0.25 + 0.015 * sn(t), 0, 0.0)
    p.arm("L", 0.55, 0.12, 1.3, 0.2)
    p.arm("R", 0.55, 0.12, 1.3, 0.2)
    p.rot("forearm_R", 0.04 * sn(t, 2))
    return p


def swim_idle(t):
    ph = TAU * t
    p = Pose().relax()
    p.move(0, 0, -0.30 + 0.025 * math.sin(ph))
    p.rot("chest", 0.04, 0, 0)
    p.leg("L", 0.7 + 0.35 * math.sin(2 * ph), 1.0 + 0.3 * math.sin(2 * ph + 1), 0, 0.12)
    p.leg("R", 0.7 - 0.35 * math.sin(2 * ph), 1.0 - 0.3 * math.sin(2 * ph + 1), 0, 0.12)
    p.arm("L", 0.5, 0.75 + 0.2 * math.sin(2 * ph), 0.5, 0.0)
    p.arm("R", 0.5, 0.75 - 0.2 * math.sin(2 * ph), 0.5, 0.0)
    p.rot("head", -0.05, 0, 0.1 * math.sin(ph))
    return p


def baby_idle(t):
    ph = TAU * t
    p = Pose().lie(0.78)
    p.rot("head", 0.0, 0.0, 0.35 * math.sin(ph))
    p.arm("L", 1.1 + 0.5 * math.sin(2 * ph), 0.5, 0.7 + 0.4 * math.sin(2 * ph + 1), 0.0)
    p.arm("R", 1.1 + 0.5 * math.sin(2 * ph + 2), 0.5, 0.7 + 0.4 * math.sin(2 * ph + 3), 0.0)
    p.leg("L", 1.0 + 0.5 * math.sin(2 * ph + 1), 1.0 + 0.5 * math.sin(2 * ph + 2.2), 0.0, 0.25)
    p.leg("R", 1.0 + 0.5 * math.sin(2 * ph + 4), 1.0 + 0.5 * math.sin(2 * ph + 5.2), 0.0, 0.25)
    p.move(0, 0, 0.005 * math.sin(2 * ph))
    return p


def baby_crawl(t):
    ph = TAU * t
    p = Pose()
    p.rot("hips", -1.42)
    p.move(0, -0.05, -0.43)
    # arms straight down to the floor; opposite arm/leg
    p.arm("L", 1.42 + 0.45 * math.sin(ph), 0.1, 0.0)
    p.arm("R", 1.42 - 0.45 * math.sin(ph), 0.1, 0.0)
    p.rot("forearm_L", 0.25 * pos(math.cos(ph)))
    p.rot("forearm_R", 0.25 * pos(-math.cos(ph)))
    p.leg("L", 1.42 - 0.2 - 0.45 * math.sin(ph), 1.5 - 0.3 * math.sin(ph) + 0.3 * pos(math.cos(ph)), 0.5, 0.1)
    p.leg("R", 1.42 - 0.2 + 0.45 * math.sin(ph), 1.5 + 0.3 * math.sin(ph) + 0.3 * pos(-math.cos(ph)), 0.5, 0.1)
    p.rot("chest", 0.0, 0, 0.12 * math.sin(ph))
    p.rot("neck", 0.55)
    p.rot("head", 0.55)
    p.move(0.012 * math.sin(ph), 0, 0)
    return p


# --- one-shots (list of (frame, Pose))
def faint_keys(fast=False):
    k = []
    s = Pose().relax()
    k.append((1, s))
    a = Pose().relax()
    a.rot("hips", 0.0)
    a.move(0, 0, -0.10)
    a.leg("L", 0.3, 0.7, 0, 0.1)
    a.leg("R", 0.3, 0.7, 0, 0.1)
    a.rot("chest", 0.15)
    a.rot("head", 0.4 if not fast else -0.3, 0, 0.2)
    a.arm("L", 0.5, 0.5, 0.4)
    a.arm("R", 0.5, 0.5, 0.4)
    b = Pose().relax()
    b.rot("hips", 0.9)
    b.move(0, -0.25, -0.42)
    b.leg("L", 0.7, 1.2, 0, 0.1)
    b.leg("R", 0.5, 1.0, 0, 0.1)
    b.rot("head", 0.3, 0, 0.3)
    b.arm("L", 0.9, 0.9, 0.3)
    b.arm("R", 0.5, 0.8, 0.5)
    c = sleep_pose(0.0)
    c.rot("head", 0.0, 0, 0.3)
    c.arm("L", 0.0, 0.25, 0.2)
    c.arm("R", 0.0, 0.3, 0.1)
    c.arm("R", -0.2, -0.0, -0.3)   # sprawl: undo the sleep arm-on-chest
    c.r["upper_arm_R"] = (0.0, -0.3, 0.0, 0.0)
    c.r["forearm_R"] = (0.2, 0, 0, 0)
    c.r["hand_R"] = (0, 0, 0, 0)
    c.leg("L", 0.0, 0.0, 0.1, 0.2)
    c.leg("R", 0.0, 0.0, 0.1, 0.2)
    f = (lambda n: max(2, int(n * (0.5 if fast else 1.0))))
    k += [(f(10), a), (f(22), b), (f(34), c), (f(48), c)]
    return k


def fall_keys():
    # trip: arms flail, stumble forward then slump backwards-seated into lying
    s = Pose().relax()
    a = Pose().relax()
    a.rot("hips", -0.1)
    a.rot("chest", -0.3)
    a.move(0, 0.08, -0.06)
    a.arm("L", 1.6, 0.9, 0.3)
    a.arm("R", 1.4, 1.2, 0.2)
    a.leg("L", 0.7, 0.2, 0, 0.1)
    a.leg("R", -0.4, 0.9, 0, 0.1)
    b = Pose().relax()
    b.rot("hips", 0.55)
    b.rot("chest", 0.15)
    b.move(0, -0.2, -0.45)
    b.arm("L", 0.6, 1.2, 0.3)
    b.arm("R", 0.9, 1.4, 0.2)
    b.leg("L", 1.0, 0.6, 0, 0.2)
    b.leg("R", 0.9, 0.7, 0, 0.2)
    c = faint_keys(True)[3][1]
    return [(1, s), (6, a), (13, b), (20, c), (34, c)]


CYCLIC = {  # name: (frames, fn)
    "Idle": (96, idle_pose), "Walk": (20, walk_pose), "Run": (16, run_pose),
    "Sit_Idle": (96, sit_idle), "Sit_Eat": (72, sit_eat), "Sit_Watch": (96, sit_watch),
    "Sleep": (96, sleep_pose), "Use_Stand": (48, use_stand), "Cook": (48, cook), "Wash": (48, wash),
    "Read": (96, read), "Exercise_Treadmill": (18, treadmill), "Paint": (72, paint), "Type": (48, typing),
    "Dance": (48, dance), "Talk": (72, talk), "Laugh": (24, laugh), "Wave": (36, wave), "Cry": (48, cry),
    "Angry": (48, angry), "Sad_Idle": (96, sad_idle), "Hug": (72, hug), "Kiss": (96, kiss), "Carry": (20, carry),
    "Shower": (72, shower), "ToiletSit": (96, toilet_sit), "Swim_idle": (48, swim_idle),
    "Baby_Idle": (48, baby_idle), "Baby_Crawl": (32, baby_crawl),
}
ONESHOT = {"Faint": faint_keys, "Fall": fall_keys}
CLIP_NAMES = list(CYCLIC) + list(ONESHOT)


# ------------------------------------------------------------------ build one variant
def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions):
        for it in list(coll):
            coll.remove(it)


def apply_pose(arm, B, pose, S, stoop):
    r = dict(pose.r)

    def add(b, x=0, y=0, z=0):
        o = r.get(b, (0, 0, 0, 0))
        r[b] = (o[0] + x, o[1] + y, o[2] + z, o[3])
    if stoop:
        add("spine", -0.07 * stoop)
        add("chest", -0.10 * stoop)
        add("neck", 0.04 * stoop)
        add("head", 0.04 * stoop)
        add("thigh_L", 0.0)
    for pb in arm.pose.bones:
        e = r.get(pb.name, (0, 0, 0, 0))
        Bm = B[pb.name]
        R = Euler((e[0], e[1], e[2]), 'XYZ').to_matrix()
        if e[3]:
            axis = Bm.col[1].normalized()
            R = R @ Matrix.Rotation(e[3], 3, axis)
        basis = Bm.transposed() @ R @ Bm
        pb.rotation_mode = 'QUATERNION'
        q = basis.to_quaternion()
        pb.rotation_quaternion = q
        if pb.name == "hips":
            pb.location = Bm.transposed() @ (pose.loc * S)
        else:
            pb.location = (0, 0, 0)


def build_variant(name, cfg, only_render=None):
    clear_scene()
    S, hs, wd = cfg["s"], cfg["hs"], cfg["w"]
    arm = build_armature(name, S, hs)
    M = Mesher(BONE_ORDER, S)
    build_body(M, hs, wd)
    hair_m = [Mesher(BONE_ORDER, S) for _ in range(6)]
    build_head(M, hs, hair_m)
    body = M.finish("body", arm)
    hairs = [hm.finish("hair_%d" % i, arm) for i, hm in enumerate(hair_m)]
    for i, h in enumerate(hairs):
        h.hide_viewport = i != 0
        h.hide_render = i != 0
        # keep all exported visible; Godot toggles visibility
        h.hide_viewport = False
        h.hide_render = False

    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    B = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
    arm.animation_data_create()
    scene = bpy.context.scene
    scene.render.fps = FPS

    def key(frame, pose, prevq):
        apply_pose(arm, B, pose, S, cfg["stoop"])
        for pb in arm.pose.bones:
            q = pb.rotation_quaternion
            if pb.name in prevq:
                q.make_compatible(prevq[pb.name])
                pb.rotation_quaternion = q
            prevq[pb.name] = q.copy()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "hips":
                pb.keyframe_insert("location", frame=frame)

    for cname, (n, fn) in CYCLIC.items():
        act = bpy.data.actions.new(cname)
        act.use_fake_user = True
        arm.animation_data.action = act
        step = 2 if n <= 48 else 3
        prevq = {}
        frames = list(range(0, n, step)) + [n]
        for f in frames:
            key(1 + f, fn((f % n) / n if f < n else 0.0), prevq)
        act.use_frame_range = True
        act.frame_start, act.frame_end = 1, n + 1
        act["loop"] = True
    for cname, kf in ONESHOT.items():
        act = bpy.data.actions.new(cname)
        act.use_fake_user = True
        arm.animation_data.action = act
        keys = kf()
        last = keys[-1][0]
        prevq = {}
        for f in range(1, last + 1, 2 if last > 20 else 1):
            # interpolate between neighbouring keys (smoothstep)
            for i in range(len(keys) - 1):
                if keys[i][0] <= f <= keys[i + 1][0]:
                    f0, p0 = keys[i]
                    f1, p1 = keys[i + 1]
                    k = (f - f0) / max(1, f1 - f0)
                    k = k * k * (3 - 2 * k)
                    key(f, p0.lerp(p1, k), prevq)
                    break
        key(last, keys[-1][1], prevq)
        act.use_frame_range = True
        act.frame_start, act.frame_end = 1, last
    bpy.ops.object.mode_set(mode='POSE')
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    arm.animation_data.action = None
    bpy.ops.object.mode_set(mode='OBJECT')
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True, export_cameras=False, export_lights=False,
                              export_apply=False, export_animations=True, export_animation_mode='ACTIONS',
                              export_skins=True, export_force_sampling=True)
    print("built", name, os.path.getsize(path), "bytes")
    return arm, B


# ------------------------------------------------------------------ pose-strip rendering
def render_strips(arm, B, cfg, outdir, clips, cols=5, tag="strip"):
    os.makedirs(outdir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = 260, 340
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_cavity = False
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    scene.world.color = (0.55, 0.62, 0.7)
    # ground plane
    me = bpy.data.meshes.new("gnd")
    me.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    g = bpy.data.objects.new("gnd", me)
    scene.collection.objects.link(g)
    gm = bpy.data.materials.new("gm")
    gm.diffuse_color = (0.35, 0.40, 0.36, 1)
    me.materials.append(gm)
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = 2.1
    co = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(co)
    scene.camera = co
    co.location = (2.6, 3.2, 1.6)
    d = Vector((0, 0, 0.82)) - co.location
    co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    for i in range(1, 6):
        h = bpy.data.objects.get("hair_%d" % i)
        if h:
            h.hide_render = True
    hair_i = int(os.environ.get("HAIR", "0"))
    files = []
    views = [((2.4, 3.0, 1.5), 0.0), ((2.4, 3.0, 1.5), 0.4), ((-2.4, 3.0, 1.5), 0.8), ((3.8, 0.0, 1.0), 0.4)]
    for cname in clips:
        act = bpy.data.actions.get(cname)
        if not act:
            continue
        arm.animation_data.action = act
        n = int(act.frame_end)
        for i, (cp, frac) in enumerate(views):
            co.location = cp
            d = Vector((0, 0, 0.82)) - co.location
            co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
            scene.frame_set(int(1 + (n - 1) * frac))
            bpy.context.view_layer.update()
            fp = os.path.join(outdir, "%s__%s__%d.png" % (tag, cname, i))
            scene.render.filepath = fp
            bpy.ops.render.render(write_still=True)
            files.append((cname, i, fp))
    bpy.ops.object.mode_set(mode='OBJECT')
    json.dump(files, open(os.path.join(outdir, tag + "_files.json"), "w"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    render = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    if "--render" in argv:
        render = argv[argv.index("--render") + 1]
    for name, cfg in VARIANTS.items():
        if only and name not in only:
            continue
        arm, B = build_variant(name, cfg)
        if name == "folk_adult":
            shutil.copyfile(os.path.join(OUT, "folk_adult.glb"), os.path.join(OUT, "folk.glb"))
        if render:
            render_strips(arm, B, cfg, render, [c for c in CLIP_NAMES if c in os.environ.get("CLIPS", ",".join(CLIP_NAMES)).split(",")], tag=name)
    os.makedirs(os.path.join(ROOT, "blender", "folk"), exist_ok=True)
    json.dump({"clips": CLIP_NAMES, "variants": list(VARIANTS)}, open(os.path.join(ROOT, "blender", "folk", "clips.json"), "w"), indent=1)
    print("DONE")


main()
