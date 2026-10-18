"""Regenerate every sim-4 3D asset.

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python blender/build_all.py

All geometry is authored in GODOT coordinates (x right, y up, z back; front = -Z)
and converted to Blender (x, -z, y) when vertices are created, so the exported
glTF is +Y up, 1 unit = 1 m, front faces -Z.
"""
import bpy, bmesh, os, json, math, sys
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)

# --------------------------------------------------------------- palette
PALETTE = {
    "wood":       ((0.55, 0.36, 0.20), 0.8, 0.0),
    "wood_dark":  ((0.33, 0.20, 0.11), 0.8, 0.0),
    "wood_light": ((0.78, 0.60, 0.38), 0.8, 0.0),
    "white":      ((0.90, 0.90, 0.88), 0.6, 0.0),
    "porcelain":  ((0.96, 0.96, 0.97), 0.3, 0.0),
    "steel":      ((0.70, 0.72, 0.75), 0.35, 0.8),
    "black":      ((0.06, 0.06, 0.07), 0.5, 0.0),
    "gray":       ((0.45, 0.46, 0.48), 0.7, 0.0),
    "stone":      ((0.62, 0.62, 0.60), 0.6, 0.0),
    "fabric_blue":((0.25, 0.40, 0.70), 0.95, 0.0),
    "fabric_red": ((0.70, 0.25, 0.25), 0.95, 0.0),
    "fabric_tan": ((0.80, 0.70, 0.55), 0.95, 0.0),
    "leaf":       ((0.20, 0.58, 0.25), 0.9, 0.0),
    "pot":        ((0.72, 0.40, 0.26), 0.9, 0.0),
    "soil":       ((0.25, 0.16, 0.10), 1.0, 0.0),
    "water":      ((0.35, 0.65, 0.85), 0.1, 0.0),
    "screen":     ((0.10, 0.25, 0.40), 0.2, 0.0),
    "lamp_shade": ((0.98, 0.88, 0.60), 0.9, 0.0),
    "canvas":     ((0.95, 0.94, 0.88), 0.9, 0.0),
    "paint_a":    ((0.85, 0.25, 0.20), 0.9, 0.0),
    "paint_b":    ((0.20, 0.45, 0.80), 0.9, 0.0),
    "paint_c":    ((0.95, 0.80, 0.20), 0.9, 0.0),
    "book_red":   ((0.70, 0.18, 0.18), 0.9, 0.0),
    "book_blue":  ((0.20, 0.30, 0.65), 0.9, 0.0),
    "book_green": ((0.22, 0.50, 0.30), 0.9, 0.0),
    "book_yellow":((0.85, 0.72, 0.25), 0.9, 0.0),
    "wall":       ((0.92, 0.90, 0.85), 0.95, 0.0),
    "floor_wood": ((0.62, 0.44, 0.27), 0.7, 0.0),
    "floor_wood2":((0.55, 0.38, 0.23), 0.7, 0.0),
    "tile_a":     ((0.85, 0.88, 0.90), 0.3, 0.0),
    "tile_b":     ((0.60, 0.70, 0.76), 0.3, 0.0),
    "carpet":     ((0.52, 0.38, 0.55), 1.0, 0.0),
    "rug":        ((0.72, 0.25, 0.22), 1.0, 0.0),
    "rug_accent": ((0.93, 0.80, 0.45), 1.0, 0.0),
    "skin":       ((0.90, 0.70, 0.55), 0.8, 0.0),
    "hair":       ((0.25, 0.15, 0.10), 0.9, 0.0),
    "shirt":      ((0.30, 0.52, 0.82), 0.9, 0.0),
    "pants":      ((0.25, 0.26, 0.40), 0.9, 0.0),
    "shoe":       ((0.12, 0.10, 0.10), 0.8, 0.0),
}
GLASS = {"glass"}


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if name == "glass":
        col, rough, metal = (0.7, 0.85, 0.95), 0.05, 0.0
        bsdf.inputs["Alpha"].default_value = 0.25
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    else:
        col, rough, metal = PALETTE[name]
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*col, 1.0)
    return m


# --------------------------------------------------------------- geometry builder
class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.bm.verts.layers.int.new("grp")
        self.mats = []
        self.groups = {}  # group name -> [vert indices]  (filled lazily by tag())
        self._tag = None
        self._tagged = {}

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _finish(self, verts, mat):
        idx = self.mi(mat)
        for v in verts:
            for f in v.link_faces:
                f.material_index = idx
        if self._tag:
            if self._tag not in self._tagged:
                self._tagged[self._tag] = len(self._tagged) + 1
            lay = self.bm.verts.layers.int.get("grp")
            for v in verts:
                v[lay] = self._tagged[self._tag]

    @staticmethod
    def _b(x, y, z):  # godot -> blender
        return (x, -z, y)

    def box(self, mat, cx, cy, cz, sx, sy, sz):
        before = set(self.bm.verts)
        bmesh.ops.create_cube(self.bm, size=1.0)
        vs = [v for v in self.bm.verts if v not in before]
        for v in vs:
            gx, gy, gz = v.co.x, v.co.z, -v.co.y  # blender->godot (unit cube)
            v.co = Vector(self._b(cx + gx * sx, cy + gy * sy, cz + gz * sz))
        self._finish(vs, mat)

    def cyl(self, mat, cx, y0, cz, r, h, r2=None, seg=12):
        before = set(self.bm.verts)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r, radius2=(r if r2 is None else r2), depth=h)
        vs = [v for v in self.bm.verts if v not in before]
        for v in vs:
            v.co = Vector((v.co.x + cx, v.co.y - cz, v.co.z + y0 + h / 2))
        self._finish(vs, mat)

    def sphere(self, mat, cx, cy, cz, rad, rings=6, segs=10):
        bm = self.bm
        vs = []
        top = bm.verts.new((cx, -cz, cy + rad)); vs.append(top)
        grid = []
        for i in range(1, rings):
            phi = math.pi * i / rings
            row = []
            for k in range(segs):
                th = 2 * math.pi * k / segs
                v = bm.verts.new((cx + rad * math.sin(phi) * math.cos(th), -cz + rad * math.sin(phi) * math.sin(th), cy + rad * math.cos(phi)))
                row.append(v); vs.append(v)
            grid.append(row)
        bot = bm.verts.new((cx, -cz, cy - rad)); vs.append(bot)
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((top, grid[0][k2], grid[0][k]))
            bm.faces.new((bot, grid[-1][k], grid[-1][k2]))
            for r in range(len(grid) - 1):
                bm.faces.new((grid[r][k], grid[r][k2], grid[r + 1][k2], grid[r + 1][k]))
        self._finish(vs, mat)

    def tag(self, name):
        self._tag = name

    def build_object(self, name, pivot=(0, 0, 0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        pv = Vector(self._b(*pivot))
        if pv.length:
            bmesh.ops.translate(self.bm, verts=self.bm.verts[:], vec=-pv)
        me = bpy.data.meshes.new(name)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for g in self._tagged:
            ob.vertex_groups.new(name=g)
        dl = None
        if self._tagged:
            dl = self.bm.verts.layers.deform.verify()
            lay = self.bm.verts.layers.int.get("grp")
            names = {i: g for g, i in self._tagged.items()}
            for v in self.bm.verts:
                gid = v[lay]
                if gid:
                    v[dl][ob.vertex_groups[names[gid]].index] = 1.0
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(get_mat(m))
        for p in me.polygons:
            p.use_smooth = False
        ob.location = pv
        return ob


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


# --------------------------------------------------------------- assets
# Each fn returns list of (node_name, Builder, pivot).  One entry => the mesh is the root node.

def fridge():
    b = Builder()
    b.box("white", 0, 0.9, 0.05, 0.8, 1.8, 0.8)
    b.box("black", 0, 1.22, -0.355, 0.8, 0.02, 0.012)
    b.box("steel", 0.3, 1.5, -0.375, 0.04, 0.3, 0.04)
    b.box("steel", 0.3, 0.85, -0.375, 0.04, 0.5, 0.04)
    b.box("gray", 0, 0.03, -0.35, 0.78, 0.06, 0.1)
    return [("fridge", b, (0, 0, 0))]


def stove():
    b = Builder()
    b.box("white", 0, 0.45, 0.05, 0.9, 0.9, 0.8)
    b.box("black", 0, 0.92, 0.05, 0.9, 0.04, 0.8)
    for x in (-0.2, 0.2):
        for z in (-0.18, 0.28):
            b.cyl("gray", x, 0.94, z, 0.12, 0.02)
    b.box("black", 0, 0.38, -0.355, 0.62, 0.36, 0.012)
    b.box("steel", 0, 0.6, -0.375, 0.6, 0.03, 0.03)
    for x in (-0.3, -0.1, 0.1, 0.3):
        b.cyl("steel", x, 0.78, -0.36, 0.03, 0.04, seg=8)
    b.box("white", 0, 1.0, 0.4, 0.9, 0.16, 0.06)
    return [("stove", b, (0, 0, 0))]


def table():
    b = Builder()
    b.box("wood", 0, 0.72, 0, 1.9, 0.06, 0.9)
    for x in (-0.85, 0.85):
        for z in (-0.38, 0.38):
            b.box("wood_dark", x, 0.345, z, 0.08, 0.69, 0.08)
    return [("table", b, (0, 0, 0))]


def chair():
    b = Builder()
    b.box("wood", 0, 0.45, 0, 0.42, 0.05, 0.42)
    for x in (-0.17, 0.17):
        for z in (-0.17, 0.17):
            b.box("wood_dark", x, 0.215, z, 0.05, 0.43, 0.05)
    b.box("wood", 0, 0.72, 0.19, 0.42, 0.5, 0.04)
    return [("chair", b, (0, 0, 0))]


def bed():
    b = Builder()
    b.box("wood_dark", 0, 0.25, 0, 1.9, 0.3, 1.95)
    b.box("white", 0, 0.45, -0.03, 1.8, 0.2, 1.85)
    b.box("wood", 0, 0.6, 0.95, 1.9, 0.6, 0.08)
    b.box("wood", 0, 0.4, -0.97, 1.9, 0.3, 0.06)
    b.box("white", -0.45, 0.59, 0.68, 0.7, 0.1, 0.4)
    b.box("white", 0.45, 0.59, 0.68, 0.7, 0.1, 0.4)
    b.box("fabric_blue", 0, 0.58, -0.28, 1.84, 0.06, 1.2)
    return [("bed", b, (0, 0, 0))]


def toilet():
    b = Builder()
    b.box("porcelain", 0, 0.2, -0.02, 0.34, 0.4, 0.5)
    b.box("white", 0, 0.42, -0.06, 0.38, 0.04, 0.46)
    b.box("porcelain", 0, 0.58, 0.3, 0.42, 0.44, 0.16)
    b.box("steel", 0.15, 0.83, 0.3, 0.05, 0.03, 0.05)
    return [("toilet", b, (0, 0, 0))]


def shower():
    b = Builder()
    b.box("porcelain", 0, 0.05, 0, 0.95, 0.1, 0.95)
    b.box("tile_b", 0, 1.1, 0.46, 0.95, 2.2, 0.04)
    b.box("glass", -0.46, 1.1, 0, 0.02, 2.0, 0.92)
    b.box("glass", 0.46, 1.1, 0, 0.02, 2.0, 0.92)
    b.box("glass", -0.2, 1.1, -0.46, 0.55, 2.0, 0.02)
    b.box("steel", -0.46, 1.05, 0, 0.03, 2.1, 0.03)
    b.box("steel", 0, 1.2, 0.42, 0.04, 1.8, 0.04)
    b.box("steel", 0, 2.08, 0.3, 0.04, 0.04, 0.26)
    b.cyl("steel", 0, 2.02, 0.18, 0.1, 0.04)
    return [("shower", b, (0, 0, 0))]


def bathtub():
    b = Builder()
    b.box("porcelain", 0, 0.3, 0, 1.9, 0.6, 0.9)
    b.box("water", 0, 0.57, 0, 1.7, 0.04, 0.7)
    b.box("steel", 0.8, 0.7, 0.3, 0.06, 0.2, 0.06)
    b.box("steel", 0.8, 0.8, 0.2, 0.06, 0.05, 0.2)
    return [("bathtub", b, (0, 0, 0))]


def sink():
    b = Builder()
    b.box("wood", 0, 0.4, 0.05, 0.8, 0.8, 0.7)
    b.box("porcelain", 0, 0.83, 0.05, 0.88, 0.06, 0.78)
    b.box("steel", 0, 0.865, 0.0, 0.5, 0.02, 0.4)
    b.cyl("steel", 0, 0.86, 0.32, 0.03, 0.25)
    b.box("steel", 0, 1.08, 0.23, 0.04, 0.04, 0.2)
    b.box("white", 0, 1.15, 0.43, 0.6, 0.05, 0.05)
    return [("sink", b, (0, 0, 0))]


def sofa():
    b = Builder()
    b.box("fabric_red", 0, 0.25, 0, 1.9, 0.3, 0.9)
    for x in (-0.45, 0.45):
        b.box("fabric_red", x, 0.5, -0.05, 0.9, 0.18, 0.72)
    b.box("fabric_red", 0, 0.68, 0.36, 1.9, 0.55, 0.18)
    for x in (-0.91, 0.91):
        b.box("fabric_red", x, 0.5, 0, 0.14, 0.45, 0.9)
    for x in (-0.1, 0.1):
        b.box("wood_dark", x * 8, 0.04, -0.4, 0.06, 0.08, 0.06)
    return [("sofa", b, (0, 0, 0))]


def tv():
    b = Builder()
    b.box("wood_dark", 0, 0.25, 0, 0.9, 0.5, 0.4)
    b.box("black", 0, 0.8, 0, 0.9, 0.52, 0.05)
    b.box("screen", 0, 0.8, -0.027, 0.82, 0.44, 0.012)
    b.box("gray", 0, 0.53, 0, 0.2, 0.06, 0.15)
    return [("tv", b, (0, 0, 0))]


def bookshelf():
    b = Builder()
    for x in (-0.45, 0.45):
        b.box("wood", x, 0.95, 0.08, 0.05, 1.9, 0.34)
    b.box("wood_dark", 0, 0.95, 0.24, 0.9, 1.9, 0.03)
    levels = [0.03, 0.42, 0.78, 1.14, 1.5, 1.88]
    for y in levels:
        b.box("wood", 0, y, 0.08, 0.9, 0.05, 0.34)
    cols = ["book_red", "book_blue", "book_green", "book_yellow"]
    n = 0
    for li in range(1, 5):
        y0 = levels[li - 1] + 0.025
        x = -0.38
        while x < 0.34:
            w = 0.05 + 0.02 * ((n * 7) % 3)
            h = 0.22 + 0.04 * ((n * 5) % 4)
            b.box(cols[n % 4], x + w / 2, y0 + h / 2, 0.08, w, h, 0.22)
            x += w + 0.01
            n += 1
            if (li == 3 and n % 11 == 0):
                x += 0.2
    return [("bookshelf", b, (0, 0, 0))]


def easel():
    b = Builder()
    for x, z in ((-0.3, -0.1), (0.3, -0.1), (0, 0.3)):
        b.box("wood", x, 0.8, z, 0.04, 1.6, 0.04)
    b.box("canvas", 0, 1.05, -0.12, 0.6, 0.8, 0.03)
    b.box("paint_a", -0.12, 1.15, -0.14, 0.2, 0.2, 0.01)
    b.box("paint_b", 0.1, 1.0, -0.14, 0.25, 0.2, 0.01)
    b.box("paint_c", 0.0, 1.25, -0.14, 0.12, 0.1, 0.01)
    b.box("wood", 0, 0.58, -0.16, 0.64, 0.03, 0.12)
    return [("easel", b, (0, 0, 0))]


def treadmill():
    b = Builder()
    b.box("black", 0, 0.12, 0.05, 0.6, 0.14, 0.9)
    b.box("gray", 0, 0.2, 0.05, 0.5, 0.02, 0.84)
    for x in (-0.3, 0.3):
        b.box("steel", x, 0.3, 0.05, 0.04, 0.3, 0.9)
        b.box("steel", x, 0.75, -0.38, 0.04, 1.1, 0.04)
    b.box("black", 0, 1.22, -0.4, 0.62, 0.2, 0.1)
    b.box("screen", 0, 1.22, -0.452, 0.4, 0.12, 0.01)
    b.box("steel", 0, 1.0, -0.4, 0.6, 0.03, 0.03)
    return [("treadmill", b, (0, 0, 0))]


def computer():
    b = Builder()
    b.box("wood", 0, 0.72, 0.05, 0.95, 0.05, 0.7)
    for x in (-0.45, 0.45):
        b.box("wood_dark", x, 0.35, 0.05, 0.04, 0.7, 0.66)
    b.box("black", 0, 0.78, 0.25, 0.08, 0.1, 0.08)
    b.box("black", 0, 1.02, 0.25, 0.6, 0.38, 0.04)
    b.box("screen", 0, 1.02, 0.228, 0.54, 0.32, 0.01)
    b.box("black", 0, 0.76, -0.1, 0.4, 0.02, 0.14)
    b.box("gray", 0.36, 0.92, 0.2, 0.14, 0.32, 0.3)
    return [("computer", b, (0, 0, 0))]


def counter():
    b = Builder()
    b.box("wood", 0, 0.4, 0, 0.96, 0.8, 0.9)
    b.box("stone", 0, 0.85, 0, 1.0, 0.06, 0.98)
    for x in (-0.22, 0.22):
        b.box("steel", x, 0.62, -0.46, 0.03, 0.2, 0.02)
    b.box("wood_dark", 0, 0.03, -0.44, 0.94, 0.06, 0.04)
    return [("counter", b, (0, 0, 0))]


def plant():
    b = Builder()
    b.cyl("pot", 0, 0, 0, 0.2, 0.35, r2=0.24)
    b.cyl("soil", 0, 0.34, 0, 0.2, 0.03)
    b.cyl("wood_dark", 0, 0.35, 0, 0.03, 0.45, seg=6)
    b.sphere("leaf", 0, 0.9, 0, 0.3)
    b.sphere("leaf", 0.18, 0.7, 0.08, 0.2)
    b.sphere("leaf", -0.16, 0.72, -0.1, 0.2)
    return [("plant", b, (0, 0, 0))]


def lamp():
    b = Builder()
    b.cyl("steel", 0, 0, 0, 0.15, 0.03)
    b.cyl("steel", 0, 0.03, 0, 0.02, 1.35, seg=6)
    b.cyl("lamp_shade", 0, 1.3, 0, 0.2, 0.3, r2=0.1)
    return [("lamp", b, (0, 0, 0))]


def trash_bin():
    b = Builder()
    b.cyl("gray", 0, 0, 0, 0.14, 0.5, r2=0.18)
    b.cyl("black", 0, 0.5, 0, 0.19, 0.04)
    return [("trash_bin", b, (0, 0, 0))]


def rug():
    b = Builder()
    b.box("rug", 0, 0.01, 0, 0.96, 0.02, 0.96)
    b.box("rug_accent", 0, 0.0125, 0, 0.7, 0.025, 0.7)
    b.box("rug", 0, 0.014, 0, 0.45, 0.028, 0.45)
    return [("rug", b, (0, 0, 0))]


# structure
def wall():
    b = Builder()
    b.box("wall", 0, 1.3, 0, 1.0, 2.6, 0.15)
    b.box("wood_dark", 0, 0.06, 0, 1.0, 0.12, 0.17)
    return [("wall", b, (0, 0, 0))]


def door():
    f = Builder()
    for x in (-0.46, 0.46):
        f.box("wood_dark", x, 1.0, 0, 0.08, 2.0, 0.18)
    f.box("wood_dark", 0, 2.04, 0, 1.0, 0.08, 0.18)
    f.box("wall", 0, 2.32, 0, 1.0, 0.56, 0.15)
    leaf = Builder()
    leaf.box("wood", 0, 1.0, 0, 0.84, 1.96, 0.04)
    leaf.box("steel", 0.3, 1.0, -0.04, 0.05, 0.05, 0.06)
    leaf.box("steel", 0.3, 1.0, 0.04, 0.05, 0.05, 0.06)
    # leaf pivot at hinge (left edge); rotate node about Y to open
    return [("frame", f, (0, 0, 0)), ("leaf", leaf, (-0.42, 0, 0))]


def window():
    b = Builder()
    for x in (-0.45, 0.45):
        b.box("wall", x, 1.3, 0, 0.1, 2.6, 0.15)
    b.box("wall", 0, 0.45, 0, 0.8, 0.9, 0.15)
    b.box("wall", 0, 2.3, 0, 0.8, 0.6, 0.15)
    b.box("wood_dark", 0, 0.12 - 0.0, 0, 1.0, 0.12, 0.17)
    b.box("wood_dark", 0, 0.92, 0, 0.8, 0.04, 0.22)
    b.box("glass", 0, 1.45, 0, 0.8, 1.1, 0.01)
    b.box("wood_dark", 0, 1.45, 0, 0.03, 1.1, 0.03)
    b.box("wood_dark", 0, 1.45, 0, 0.8, 0.03, 0.03)
    for x in (-0.4, 0.4):
        b.box("wood_dark", x, 1.45, 0, 0.03, 1.1, 0.05)
    b.box("wood_dark", 0, 2.0, 0, 0.8, 0.03, 0.05)
    return [("window", b, (0, 0, 0))]


def floor_wood():
    b = Builder()
    for i in range(4):
        b.box("floor_wood" if i % 2 == 0 else "floor_wood2", -0.375 + 0.25 * i, -0.025, 0, 0.245, 0.05, 1.0)
    return [("floor_wood", b, (0, 0, 0))]


def floor_tile():
    b = Builder()
    for i in range(2):
        for j in range(2):
            b.box("tile_a" if (i + j) % 2 == 0 else "tile_b", -0.25 + 0.5 * i, -0.025, -0.25 + 0.5 * j, 0.5, 0.05, 0.5)
    return [("floor_tile", b, (0, 0, 0))]


def floor_carpet():
    b = Builder()
    b.box("carpet", 0, -0.025, 0, 1.0, 0.05, 1.0)
    return [("floor_carpet", b, (0, 0, 0))]


# tile footprint (w along X, d along Z) per object; height measured from geometry
FOOT = {
    "fridge": (1, 1), "stove": (1, 1), "table": (2, 1), "chair": (1, 1), "bed": (2, 2),
    "toilet": (1, 1), "shower": (1, 1), "bathtub": (2, 1), "sink": (1, 1), "sofa": (2, 1),
    "tv": (1, 1), "bookshelf": (1, 1), "easel": (1, 1), "treadmill": (1, 1), "computer": (1, 1),
    "counter": (1, 1), "plant": (1, 1), "lamp": (1, 1), "trash_bin": (1, 1), "rug": (1, 1),
    "wall": (1, 1), "door": (1, 1), "window": (1, 1),
    "floor_wood": (1, 1), "floor_tile": (1, 1), "floor_carpet": (1, 1),
}
NOTES = {
    "fridge": "front (door) faces -Z", "stove": "front faces -Z; hob on top",
    "table": "2x1: long axis X; origin at footprint centre",
    "chair": "seat top y=0.47, backrest at +Z; sitter faces -Z",
    "bed": "2x2; headboard/pillows at +Z; mattress top y~0.55 (sleep surface); foot end -Z",
    "toilet": "tank at +Z; sitter faces -Z", "shower": "open side faces -Z; user stands inside",
    "bathtub": "2x1 long axis X; faucet at +X end", "sink": "front faces -Z",
    "sofa": "2x1; backrest at +Z; seat top y~0.6", "tv": "screen faces -Z",
    "bookshelf": "open front faces -Z", "easel": "canvas faces -Z",
    "treadmill": "user stands on belt facing -Z towards console", "computer": "desk+pc; monitor faces -Z, user sits at -Z side",
    "counter": "front faces -Z; top y=0.88", "plant": "", "lamp": "floor lamp",
    "trash_bin": "", "rug": "1x1 flat, top y~0.03; tile or scale in Godot",
    "wall": "1.0 x 2.6 x 0.15 along X, centred on tile edge line; rotate 90deg for Z-edges",
    "door": "root with nodes 'frame' and 'leaf'; leaf origin is the hinge (x=-0.42), rotate leaf about Y to open; same 1.0x2.6x0.15 slot as wall",
    "window": "wall piece with glass opening, same slot as wall",
    "floor_wood": "top surface at y=0", "floor_tile": "top surface at y=0", "floor_carpet": "top surface at y=0",
}

FURNITURE = [fridge, stove, table, chair, bed, toilet, shower, bathtub, sink, sofa, tv, bookshelf,
             easel, treadmill, computer, counter, plant, lamp, trash_bin, rug]
STRUCTURE = [wall, door, window, floor_wood, floor_tile, floor_carpet]


def export(path, anim=False):
    kw = dict(filepath=path, export_format='GLB', export_yup=True, export_cameras=False,
              export_lights=False, export_apply=not anim)
    if anim:
        kw["export_animation_mode"] = 'ACTIONS'
        kw["export_animations"] = True
        kw["export_skins"] = True
    else:
        kw["export_animations"] = False
    bpy.ops.export_scene.gltf(**kw)


def bbox_godot():
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            g = (w.x, w.z, -w.y)
            for i in range(3):
                mn[i] = min(mn[i], g[i])
                mx[i] = max(mx[i], g[i])
    return mn, mx


def build_static(fn):
    clear_scene()
    parts = fn()
    name = fn.__name__
    if len(parts) == 1:
        n, b, pv = parts[0]
        b.build_object(name, pv)
    else:
        root = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(root)
        for n, b, pv in parts:
            ob = b.build_object(n, pv)
            ob.parent = root
    bpy.context.view_layer.update()
    path = os.path.join(OUT, name + ".glb")
    export(path)
    mn, mx = bbox_godot()
    return path, mn, mx


# --------------------------------------------------------------- folk
BONES = {  # name: (head position godot, parent)
    "hips": ((0, 0.9, 0), None),
    "torso": ((0, 0.9, 0), "hips"),
    "head": ((0, 1.4, 0), "torso"),
    "arm_l": ((-0.27, 1.38, 0), "torso"),
    "arm_r": ((0.27, 1.38, 0), "torso"),
    "leg_l": ((-0.1, 0.9, 0), "hips"),
    "leg_r": ((0.1, 0.9, 0), "hips"),
}


def build_folk(name, s, tint=None):
    clear_scene()
    b = Builder()
    sc = lambda *a: [x * s for x in a]
    shirt = tint or "shirt"
    # legs (+x = character's right, character faces -Z)
    for side, x in (("leg_l", -0.1), ("leg_r", 0.1)):
        b.tag(side)
        b.box("pants", *sc(x, 0.47, 0, 0.15, 0.86, 0.17))
        b.box("shoe", *sc(x, 0.04, -0.04, 0.16, 0.08, 0.27))
    b.tag("torso")
    b.box(shirt, *sc(0, 1.15, 0, 0.4, 0.5, 0.24))
    b.box("pants", *sc(0, 0.93, 0, 0.38, 0.1, 0.23))
    b.tag("head")
    b.box("skin", *sc(0, 1.43, 0, 0.08, 0.06, 0.08))
    b.sphere("skin", *sc(0, 1.56, 0, 0.15))
    b.sphere("hair", *sc(0, 1.6, 0.035, 0.155))
    b.box("skin", *sc(0, 1.53, -0.15, 0.04, 0.05, 0.04))
    for x in (-0.055, 0.055):
        b.box("black", *sc(x, 1.58, -0.14, 0.03, 0.035, 0.02))
    for side, x in (("arm_l", -0.27), ("arm_r", 0.27)):
        b.tag(side)
        b.box(shirt, *sc(x, 1.19, 0, 0.12, 0.4, 0.13))
        b.box("skin", *sc(x, 0.9, 0, 0.1, 0.2, 0.11))
    b.tag(None)
    mesh = b.build_object(name + "_mesh")

    arm_data = bpy.data.armatures.new(name + "_arm")
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for bn, (head, parent) in BONES.items():
        eb = arm_data.edit_bones.new(bn)
        h = Vector((head[0] * s, -head[2] * s, head[1] * s))
        eb.head = h
        eb.tail = h + Vector((0, 0, 0.12 * s))
        eb.roll = 0
    for bn, (head, parent) in BONES.items():
        if parent:
            arm_data.edit_bones[bn].parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    mesh.parent = arm
    mod = mesh.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm

    # ---- animations (bone local axes: +X rot swings hanging limbs forward (-Z), tips up-pointing parts back)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    pbs = arm.pose.bones
    for pb in pbs:
        pb.rotation_mode = 'XYZ'
    arm.animation_data_create()

    def reset():
        for pb in pbs:
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)

    def key(frame, pose):
        reset()
        for bn, vals in pose.items():
            if "rot" in vals:
                pbs[bn].rotation_euler = vals["rot"]
            if "loc" in vals:
                pbs[bn].location = tuple(v * s for v in vals["loc"])
        for pb in pbs:
            pb.keyframe_insert("rotation_euler", frame=frame)
            pb.keyframe_insert("location", frame=frame)

    def clip(cname, frames):
        act = bpy.data.actions.new(cname)
        arm.animation_data.action = act
        for f, pose in frames:
            key(f, pose)
        act.use_fake_user = True

    R = lambda x=0, y=0, z=0: {"rot": (x, y, z)}
    # Idle: 2s loop @24fps
    clip("Idle", [
        (1, {"torso": R(0.0), "arm_l": R(0, 0, 0.04), "arm_r": R(0, 0, -0.04)}),
        (25, {"torso": R(0.03), "head": R(-0.03), "arm_l": R(0.02, 0, 0.06), "arm_r": R(0.02, 0, -0.06)}),
        (49, {"torso": R(0.0), "arm_l": R(0, 0, 0.04), "arm_r": R(0, 0, -0.04)}),
    ])
    # Walk: 1s loop
    a = 0.6
    def wk(t):
        return {"leg_l": R(a * t), "leg_r": R(-a * t), "arm_l": R(-0.7 * a * t, 0, 0.05), "arm_r": R(0.7 * a * t, 0, -0.05),
                "torso": R(0, 0.06 * t, 0), "hips": {"loc": (0, -0.02 * (1 - abs(t)), 0)}}
    clip("Walk", [(1, wk(1)), (7, wk(0)), (13, wk(-1)), (19, wk(0)), (25, wk(1))])
    # Sit: hips lowered, legs forward, hands on lap (pose held; 1s loop)
    sit = {"hips": {"loc": (0, -0.43, 0)}, "leg_l": R(1.45), "leg_r": R(1.45),
           "arm_l": R(0.6, 0, 0.1), "arm_r": R(0.6, 0, -0.1)}
    clip("Sit", [(1, sit), (25, dict(sit, head=R(0.04))), (49, sit)])
    # Sleep: lying on back, head toward +Z, hips lowered to body half-thickness
    sl = {"hips": {"rot": (math.pi / 2, 0, 0), "loc": (0, -0.76, 0)}, "arm_l": R(0, 0, 0.1), "arm_r": R(0, 0, -0.1)}
    sl2 = {"hips": {"rot": (math.pi / 2, 0, 0), "loc": (0, -0.76, 0)}, "torso": R(-0.03), "arm_l": R(0, 0, 0.1), "arm_r": R(0, 0, -0.1)}
    clip("Sleep", [(1, sl), (37, sl2), (73, sl)])
    # Use (generic arms-forward interaction)
    u1 = {"arm_l": R(1.2, 0, 0.1), "arm_r": R(1.2, 0, -0.1), "torso": R(0.05)}
    u2 = {"arm_l": R(0.9, 0, 0.1), "arm_r": R(1.35, 0, -0.1), "torso": R(0.08)}
    clip("Use", [(1, u1), (13, u2), (25, u1)])
    # Eat: right hand to mouth repeatedly
    e1 = {"arm_r": R(0.7, 0, -0.1), "arm_l": R(0.4, 0, 0.1), "head": R(0.0)}
    e2 = {"arm_r": R(2.1, 0, -0.25), "arm_l": R(0.4, 0, 0.1), "head": R(0.08)}
    clip("Eat", [(1, e1), (13, e2), (19, e2), (31, e1), (37, e1)])

    reset()
    arm.animation_data.action = None
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.scene.render.fps = 24
    path = os.path.join(OUT, name + ".glb")
    export(path, anim=True)
    return path


def main():
    manifest = {}
    foot = {}
    for fn in FURNITURE + STRUCTURE:
        name = fn.__name__
        path, mn, mx = build_static(fn)
        w, d = FOOT[name]
        h = round(mx[1], 2)
        if name.startswith("floor_"):
            h = 0.0
        elif name in ("wall", "door", "window"):
            w, d = 1, 1
        foot[name] = [w, d, h]
        manifest[name] = {"file": "res://assets/models/%s.glb" % name, "footprint": [w, d, h],
                          "notes": NOTES.get(name, ""),
                          "bounds_min": [round(v, 3) for v in mn], "bounds_max": [round(v, 3) for v in mx]}
        print("built", name, [round(v, 2) for v in mn], [round(v, 2) for v in mx])
    for name, s in (("folk", 1.0), ("folk_child", 0.68)):
        path = build_folk(name, s, tint=("shirt" if s == 1.0 else "fabric_red"))
        manifest[name] = {"file": "res://assets/models/%s.glb" % name, "footprint": [1, 1, round(1.72 * s, 2)],
                          "notes": "skinned armature; bones hips,torso,head,arm_l,arm_r,leg_l,leg_r; clips Idle,Walk,Sit,Sleep,Use,Eat; faces -Z"}
        foot[name] = [1, 1, round(1.72 * s, 2)]
        print("built", name)
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(ROOT, "blender", "footprints.json"), "w") as f:
        json.dump(foot, f, indent=2)
    bad = [k for k in manifest if not os.path.exists(os.path.join(OUT, k + ".glb")) or os.path.getsize(os.path.join(OUT, k + ".glb")) < 500]
    print("MISSING/EMPTY:", bad)
    print("DONE", len(manifest))


main()
