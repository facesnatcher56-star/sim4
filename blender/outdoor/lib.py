"""Shared helpers for the outdoor kit. exec'd by blender/build_outdoor.py into ONE namespace (G); model modules
(roads.py, vehicles.py, ...) are exec'd into the same namespace and register assets with @asset(...).
All coordinates passed to helpers are GODOT coordinates (x right, y up, z back; front = -Z), like Builder.box."""
import bpy, bmesh, math, os, json
from mathutils import Vector, Euler

# ---- palette ---------------------------------------------------------------------------------------
PALETTE.update({
    "asphalt":   ((0.26, 0.27, 0.30), 0.95, 0.0),
    "asphalt2":  ((0.31, 0.32, 0.35), 0.95, 0.0),
    "line_y":    ((0.95, 0.78, 0.15), 0.7, 0.0),
    "line_w":    ((0.93, 0.93, 0.90), 0.7, 0.0),
    "paving":    ((0.72, 0.70, 0.66), 0.9, 0.0),
    "paving2":   ((0.64, 0.62, 0.59), 0.9, 0.0),
    "curb":      ((0.80, 0.79, 0.76), 0.8, 0.0),
    "grass":     ((0.36, 0.64, 0.28), 0.95, 0.0),
    "grass2":    ((0.31, 0.57, 0.24), 0.95, 0.0),
    "grass_blade": ((0.42, 0.72, 0.30), 0.95, 0.0),
    "dirt":      ((0.50, 0.37, 0.24), 1.0, 0.0),
    "dirt2":     ((0.43, 0.31, 0.20), 1.0, 0.0),
    "gravel":    ((0.62, 0.60, 0.56), 1.0, 0.0),
    "gravel2":   ((0.50, 0.49, 0.47), 1.0, 0.0),
    "sand":      ((0.86, 0.78, 0.55), 1.0, 0.0),
    "sand2":     ((0.78, 0.69, 0.47), 1.0, 0.0),
    "water":     ((0.24, 0.55, 0.80), 0.1, 0.0),
    "pond_bed":  ((0.15, 0.32, 0.42), 1.0, 0.0),
    "bark":      ((0.40, 0.27, 0.16), 0.95, 0.0),
    "leaves":    ((0.38, 0.68, 0.30), 0.95, 0.0),
    "blossom":   ((0.96, 0.62, 0.74), 0.9, 0.0),
    "flower_r":  ((0.90, 0.22, 0.25), 0.9, 0.0),
    "flower_y":  ((0.97, 0.84, 0.20), 0.9, 0.0),
    "flower_w":  ((0.96, 0.96, 0.92), 0.9, 0.0),
    "flower_p":  ((0.72, 0.40, 0.85), 0.9, 0.0),
    "rock":      ((0.58, 0.58, 0.56), 0.95, 0.0),
    "rock_dark": ((0.44, 0.44, 0.43), 0.95, 0.0),
    "green_paint": ((0.18, 0.40, 0.28), 0.6, 0.0),
    "hedge":     ((0.20, 0.45, 0.22), 1.0, 0.0),
    "lamp_glow": ((1.00, 0.92, 0.65), 0.4, 0.0),
    "headlight": ((0.98, 0.95, 0.80), 0.3, 0.0),
    "taillight": ((0.80, 0.08, 0.08), 0.4, 0.0),
    "tyre":      ((0.07, 0.07, 0.08), 0.9, 0.0),
    "hub":       ((0.75, 0.77, 0.80), 0.3, 0.8),
    "body":      ((0.75, 0.15, 0.15), 0.45, 0.2),
    "roof":      ((0.55, 0.22, 0.18), 0.9, 0.0),
    "trim":      ((0.95, 0.94, 0.90), 0.8, 0.0),
    "door_paint": ((0.30, 0.20, 0.35), 0.7, 0.0),
    "base":      ((0.55, 0.54, 0.52), 0.95, 0.0),
    "chimney":   ((0.50, 0.30, 0.25), 0.95, 0.0),
    "awning":    ((0.80, 0.25, 0.22), 0.9, 0.0),
    "sign_face": ((0.92, 0.92, 0.88), 0.6, 0.0),
    "playground_r": ((0.85, 0.22, 0.20), 0.7, 0.0),
    "playground_b": ((0.22, 0.45, 0.82), 0.7, 0.0),
    "playground_y": ((0.95, 0.78, 0.18), 0.7, 0.0),
    "fur_dog":   ((0.72, 0.50, 0.28), 0.95, 0.0),
    "fur_dog2":  ((0.95, 0.90, 0.80), 0.95, 0.0),
    "fur_cat":   ((0.88, 0.55, 0.22), 0.95, 0.0),
    "fur_cat2":  ((0.98, 0.95, 0.90), 0.95, 0.0),
    "nose":      ((0.10, 0.08, 0.08), 0.6, 0.0),
    "bird_blue": ((0.25, 0.50, 0.85), 0.9, 0.0),
    "bird_belly": ((0.97, 0.92, 0.80), 0.9, 0.0),
    "beak":      ((0.95, 0.65, 0.15), 0.7, 0.0),
    "bus_stripe": ((0.95, 0.80, 0.15), 0.6, 0.0),
    "marble":    ((0.88, 0.87, 0.84), 0.5, 0.0),
    "hydrant_red": ((0.82, 0.14, 0.12), 0.5, 0.0),
    "trash_green": ((0.22, 0.40, 0.30), 0.7, 0.0),
    "sand_box":  ((0.88, 0.80, 0.55), 1.0, 0.0),
})
EMISSIVE = {"lamp_glow": 2.5, "headlight": 0.6, "taillight": 0.5}
ALPHA = {"glass": 0.3, "water": 0.72}


def _get_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if name == "glass":
        col, rough, metal = (0.62, 0.80, 0.92), 0.05, 0.0
    else:
        col, rough, metal = PALETTE[name]
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if name in ALPHA:
        bsdf.inputs["Alpha"].default_value = ALPHA[name]
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = (*col, 1.0)
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    m.diffuse_color = (*col, 1.0)
    return m


LIB["get_mat"] = _get_mat      # Builder.build_object resolves get_mat in LIB's globals


# ---- extra geometry ----------------------------------------------------------------------------------
def rbox(b, mat, cx, cy, cz, sx, sy, sz, rx=0.0, ry=0.0, rz=0.0):
    """Box centred (cx,cy,cz) size (sx,sy,sz), rotated by (rx,ry,rz) degrees about its centre (Godot axes)."""
    before = set(b.bm.verts)
    bmesh.ops.create_cube(b.bm, size=1.0)
    vs = [v for v in b.bm.verts if v not in before]
    eu = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ')
    for v in vs:
        loc = Vector((v.co.x * sx, v.co.z * sy, -v.co.y * sz))
        loc.rotate(eu)
        v.co = Vector(Builder._b(cx + loc.x, cy + loc.y, cz + loc.z))
    b._finish(vs, mat)


def hull(b, mat, pts):
    """Convex hull of Godot-space points (prisms, wedges, frusta, roofs)."""
    vs = [b.bm.verts.new(Builder._b(*p)) for p in pts]
    bmesh.ops.convex_hull(b.bm, input=vs, use_existing_faces=False)
    vs = [v for v in vs if v.is_valid]
    b._finish(vs, mat)


def frustum(b, mat, cx, y0, cz, w0, d0, w1, d1, h):
    hull(b, mat, [(cx + sx * w0 / 2, y0, cz + sz * d0 / 2) for sx in (-1, 1) for sz in (-1, 1)] +
         [(cx + sx * w1 / 2, y0 + h, cz + sz * d1 / 2) for sx in (-1, 1) for sz in (-1, 1)])


def gable(b, mat, cx, y0, cz, w, d, h, axis="x"):
    """Gable roof prism, base w x d at y0, ridge height h. axis='x': ridge runs along X (slopes face +-Z)."""
    if axis == "x":
        pts = [(cx + sx * w / 2, y0, cz + sz * d / 2) for sx in (-1, 1) for sz in (-1, 1)]
        pts += [(cx + sx * w / 2, y0 + h, cz) for sx in (-1, 1)]
    else:
        pts = [(cx + sx * w / 2, y0, cz + sz * d / 2) for sx in (-1, 1) for sz in (-1, 1)]
        pts += [(cx, y0 + h, cz + sz * d / 2) for sz in (-1, 1)]
    hull(b, mat, pts)


def tube(b, mat, p0, p1, r, seg=8, r2=None):
    """Cylinder/cone between two GODOT points."""
    g0 = Vector(Builder._b(*p0)); g1 = Vector(Builder._b(*p1))
    d = g1 - g0
    before = set(b.bm.verts)
    bmesh.ops.create_cone(b.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=(r if r2 is None else r2), depth=d.length)
    vs = [v for v in b.bm.verts if v not in before]
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    mid = (g0 + g1) / 2
    for v in vs:
        v.co = q @ v.co + mid
    b._finish(vs, mat)


def blob(b, mat, cx, cy, cz, rx, ry, rz, rings=4, segs=7):
    """Squashed low-poly sphere (ellipsoid)."""
    n0 = len(b.bm.verts)
    b.sphere(mat, cx, cy, cz, 1.0, rings, segs)
    vs = list(b.bm.verts)[n0:]
    for v in vs:
        gx, gy, gz = v.co.x - cx, v.co.z - cy, -v.co.y - cz
        v.co = Vector(Builder._b(cx + gx * rx, cy + gy * ry, cz + gz * rz))


# ---- asset registry / builder -----------------------------------------------------------------------
REG = []     # (id, w, d, note, fn, kw)


def asset(oid, w, d, note="", **kw):
    def deco(fn):
        REG.append((oid, w, d, note, fn, kw))
        return fn
    return deco


def purge():
    clear_scene()
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def build_parts(oid, parts):
    """parts = [(node, Builder, pivot)] -> objects in scene; single part => the mesh is the root."""
    if len(parts) == 1:
        n, b, pv = parts[0]
        return {n: b.build_object(oid, pv)}
    root = bpy.data.objects.new(oid, None)
    bpy.context.scene.collection.objects.link(root)
    objs = {}
    for n, b, pv in parts:
        ob = b.build_object(n, pv)
        ob.parent = root
        objs[n] = ob
    return objs


def set_clip(objs, clip, keys):
    """keys: {node: [(frame, (rx,ry,rz) degrees about Godot axes, (dx,dy,dz) Godot offset or None)]} -> one NLA
    track per clip name (the glTF exporter turns each track into an animation)."""
    for node, kfs in keys.items():
        ob = objs[node]
        base_loc = ob.location.copy()
        act = bpy.data.actions.new("%s_%s" % (node, clip))
        ob.animation_data_create()
        ob.animation_data.action = act
        ob.rotation_mode = 'XYZ'
        for fr, rot, off in kfs:
            ob.rotation_euler = (math.radians(rot[0]), math.radians(-rot[2]), math.radians(rot[1]))
            ob.location = base_loc + (Vector(Builder._b(*off)) if off else Vector())
            ob.keyframe_insert("rotation_euler", frame=fr)
            ob.keyframe_insert("location", frame=fr)
        ob.rotation_euler = (0, 0, 0)
        ob.location = base_loc
        tr = ob.animation_data.nla_tracks.new()
        tr.name = clip
        st = tr.strips.new(clip, 1, act)
        st.name = clip
        ob.animation_data.action = None


def export_glb(path, anim=False):
    kw = dict(filepath=path, export_format='GLB', export_yup=True, export_cameras=False,
              export_lights=False, export_apply=True, export_animations=anim)
    if anim:
        kw["export_animation_mode"] = 'NLA_TRACKS'
        kw["export_apply"] = False
    bpy.ops.export_scene.gltf(**kw)
