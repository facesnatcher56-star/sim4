"""Shared mesh helpers for the folk builders (Blender 5.1): materials, the skinned Mesher, morph-target objects."""
import bpy, bmesh, math
from mathutils import Vector

TAU = math.tau
PI = math.pi

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
    "accent":   ((0.85, 0.85, 0.85), 0.85),
    "frame":    ((0.05, 0.05, 0.06), 0.4),
    "freckles": ((0.55, 0.32, 0.22), 0.9),
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



# ------------------------------------------------------------------ morph targets (body shape)
# shape = (chest, waist, hip, depth) multipliers of the average torso. Godot blends them: slim/broad = body_type,
# soft/angular = frame (neutral frame = no morph).
BASE_SHAPE = (1.0, 1.0, 1.0, 1.0)
MORPHS = {
    "slim":    (0.92, 0.82, 0.88, 0.90),
    "broad":   (1.05, 1.18, 1.08, 1.12),
    "soft":    (0.96, 0.88, 1.14, 1.05),
    "angular": (1.05, 1.00, 0.92, 0.97),
}


def finish_morph(build, name, arm, bones, S):
    """build(M, shape) fills a Mesher; returns the object with one shape key per MORPHS entry (same topology each time)."""
    M = Mesher(bones, S)
    build(M, BASE_SHAPE)
    ob = M.finish(name, arm)
    ob.data.uv_layers.new(name="UVMap")        # Godot generates tangents for morphed meshes and needs UVs for that
    ob.shape_key_add(name="Basis", from_mix=False)
    n = len(ob.data.vertices)
    for key, sh in MORPHS.items():
        M2 = Mesher(bones, S)
        build(M2, sh)
        tmp = bpy.data.meshes.new("tmp")
        M2.bm.to_mesh(tmp)
        M2.bm.free()
        assert len(tmp.vertices) == n, (name, key, len(tmp.vertices), n)
        sk = ob.shape_key_add(name=key, from_mix=False)
        for i, v in enumerate(tmp.vertices):
            sk.data[i].co = v.co
        bpy.data.meshes.remove(tmp)
    return ob


def torus(M, c, R, r, mat, wfn, n=16, seg=6, square=0.0):
    """Ring (glasses frame) in the XZ plane around centre c; square 0..1 squares the outline."""
    c = Vector(c)
    rings = []
    for i in range(n + 1):
        a = TAU * (i % n) / n
        ca, sa = math.cos(a), math.sin(a)
        k = 1.0 / max(abs(ca), abs(sa)) if square > 0 else 1.0
        rr = R * (1.0 + (k - 1.0) * square * 0.8) if square > 0 else R
        rad = Vector((ca, 0, sa))
        rings.append((c + rad * rr, rad, Vector((0, 1, 0)), r, r))
    M.ring_mesh(rings, mat, wfn, seg)
