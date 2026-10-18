"""Render previews (Workbench, headless):
  blender --background --python blender/outdoor/render_preview_outdoor.py -- <sheet>
sheet = tiles | props | vehicles | buildings | scene   ->  assets/preview_outdoor_<sheet>.png ; 'scene' = assembled sample street.
assets/preview_outdoor.png is the scene render (copy done by the caller)."""
import bpy, os, sys, json, math
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MD = os.path.join(ROOT, "assets", "models", "outdoor")
man = json.load(open(os.path.join(ROOT, "assets", "models", "manifest_outdoor.json")))
sheet = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "tiles"
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

_cache = {}


def descendants(o):
    out = [o]
    for c in o.children:
        out += descendants(c)
    return out


def place(oid, x, z, rot=0.0, label=False):
    """Place a glb at Godot (x, z), rotated `rot` degrees about Godot Y. Clones imported hierarchies (linked data)."""
    if oid not in _cache:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(MD, oid + ".glb"))
        new = [o for o in bpy.data.objects if o not in before]
        roots = [o for o in new if o.parent is None]
        _cache[oid] = roots
        for o in new:
            o.hide_render = True            # templates stay hidden; clones are rendered
        for r in roots:
            pass
    roots = _cache[oid]
    wrap = bpy.data.objects.new(oid + "_inst", None)
    bpy.context.scene.collection.objects.link(wrap)
    wrap.location = (x, -z, 0)
    wrap.rotation_euler = (0, 0, math.radians(rot))

    def clone(src, parent):
        c = src.copy()
        c.hide_render = False
        c.parent = parent
        if parent is wrap:
            c.matrix_parent_inverse.identity()
        bpy.context.scene.collection.objects.link(c)
        for ch in src.children:
            clone(ch, c)
        return c
    for r in roots:
        clone(r, wrap)
    return [wrap]


def text(s, x, z, size=0.3):
    t = bpy.data.curves.new("t", 'FONT'); t.body = s; t.size = size; t.align_x = 'CENTER'
    to = bpy.data.objects.new("t", t); bpy.context.scene.collection.objects.link(to)
    to.location = (x, -z, 0.02); to.rotation_euler = (0, 0, math.pi)
    return to


def grid(ids, cols, sp, tsize=0.3):
    for i, n in enumerate(ids):
        x = (i % cols) * sp; z = (i // cols) * sp
        place(n, x, z)
        text(n, x, z - sp * 0.42, tsize)       # label on the -Z (front) side so it reads from the front camera
    rows = (len(ids) + cols - 1) // cols
    return (cols - 1) * sp / 2, (rows - 1) * sp / 2, max(cols, rows) * sp


def ids_by(prefixes, exact=()):
    return [k for k in man if k.startswith(tuple(prefixes)) or k in exact]


def ground_plane(cx, cz, w, d, col=(0.36, 0.62, 0.28)):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(cx, -cz, -0.06))
    p = bpy.context.object; p.scale = (w, d, 1)
    m = bpy.data.materials.new("g"); m.diffuse_color = (*col, 1); p.data.materials.append(m)


def scene_street():
    ground_plane(14, 4, 90, 60)
    # horizontal road z=0..3 (x -22..46), vertical road x=18..21 (z -16..24)
    X0, X1 = -22, 46
    for x in range(X0, X1 + 1):
        for z, (idd, rot) in enumerate([("road_edge", -90), ("road_line", -90), ("road_line", 90), ("road_edge", 90)]):
            if 18 <= x <= 21:
                continue
            place(idd, x, z, rot)
        # sidewalks both sides
        if not (17 <= x <= 22):
            place("sidewalk_curb", x, -1, 180); place("sidewalk", x, -2)
            place("sidewalk_curb", x, 4, 0); place("sidewalk", x, 5)
    for z in range(-16, 25):
        if 0 <= z <= 3:
            continue
        for x, (idd, rot) in zip(range(18, 22), [("road_edge", 0), ("road_line", 0), ("road_line", 180), ("road_edge", 180)]):
            place(idd, x, z, rot)
        if not (-2 <= z <= 5):
            place("sidewalk_curb", 17, z, -90); place("sidewalk", 16, z)
            place("sidewalk_curb", 22, z, 90); place("sidewalk", 23, z)
    for x in range(18, 22):                                                     # intersection
        for z in range(0, 4):
            place("road_cross" if x in (19, 20) and z in (1, 2) else "road_asphalt", x, z)
    # rounded corners + sidewalk fill around the intersection
    place("road_corner", 17, -1, 0); place("road_corner", 22, -1, -90); place("road_corner", 22, 4, 180); place("road_corner", 17, 4, 90)
    for x in (17, 22):
        place("sidewalk", x, -2); place("sidewalk", x, 5)
    for z in range(0, 4):                                                       # crosswalk across the west arm
        place("road_crosswalk", 14, z, 90)
    place("curb_ramp", 14, -1, 180); place("curb_ramp", 14, 4, 0)
    # houses on the north side (front +Z => rotate 180)
    place("townhouse_c", -16, -9.5, 180); place("house_small_a", -6, -7.5, 180); place("house_medium_b", 8, -9.5, 180)
    place("cafe_a", 35, -11, 180)
    for x in range(-22, 16):
        if x % 2:
            place("fence_picket_straight", x + 0.0, -4.0, 0) if -21 < x < -12 or 1 < x < 14 else None
    # park + south side
    place("fountain", 32, 12); place("pond_water", 27, 9); place("tree_oak_l", 27, 14); place("tree_pine_l", 40, 10)
    place("tree_ornamental_l", 30, 7.5); place("tree_oak_s", 41, 16); place("tree_pine_s", 24, 20)
    place("picnic_table", 38, 18); place("bench_street", 32, 8.2, 0); place("swing_set", 28, 20); place("slide", 33, 20)
    place("sandbox", 24, 24) if False else None
    place("flower_bed", 36, 8.5); place("rock_large", 24.5, 12); place("rock_small", 41.5, 13); place("bush_flowering", 35, 7)
    place("bush_round", 25.5, 6.8); place("grass_tuft", 29.5, 16); place("grass_tuft", 31.5, 17.5); place("grass_tuft", 38.5, 12)
    place("tree_oak_l", 3, 8); place("tree_pine_l", 9, 10); place("tree_ornamental_s", 14, 7.5); place("tree_oak_s", -4, 7.5)
    place("tree_ornamental_l", -2, -3.2); place("tree_oak_l", 13.5, -3.1); place("tree_pine_s", -19, -3.2)
    place("bush_round", 3.5, -3.3); place("bush_flowering", -9.5, -3.3); place("flower_bed", -1.5, -4.2)
    for x in (-12, -2, 6, 12, 26, 40):                                           # lamps
        place("street_lamp", x, -1.35, 0)
    for x in (-8, 4, 30):
        place("street_lamp", x, 4.4, 180)
    place("bus_stop", 26, -1.6, 180); place("trash_can", 30, -1.2); place("fire_hydrant", 5, -1.4)
    place("mailbox_street", 0, -2.6, 0); place("sign_blank", 15.5, 4.7, 0)
    # vehicles
    place("car_van_white", 4, 2.5, -90); place("car_sedan_red", -5, 0.5, 90); place("car_hatchback_blue", 30, 2.5, -90)
    place("car_sedan_yellow", 12, 0.5, 90); place("car_hatchback_red", 18.5, 10, 180); place("car_van_blue", 20.5, -8, 0)
    place("bus", 40, 0.5, 90); place("car_hatchback_yellow", 19.5, 2.5 + 0 , 0) if False else None
    place("dog", 2, -3.4, 90); place("cat", 11, -3.0, 200); place("bird", 6.5, -2.0, 0)
    return 14, 4, 76


def main():
    sc = bpy.context.scene
    if sheet == "tiles":
        cx, cz, ext = grid(ids_by(("road_", "sidewalk", "curb_", "ground_", "pond_")), 8, 1.8, 0.14)
        scale = 15
    elif sheet == "props":
        ids = ids_by(("tree_", "bush_", "flower_", "rock_", "grass_", "street_lamp", "fence_", "mailbox", "trash", "bench", "picnic", "bus_stop", "swing", "slide",
                      "sandbox", "fountain", "sign_", "fire_", "dog", "cat", "bird"))
        cx, cz, ext = grid(ids, 8, 4.4, 0.25)
        scale = 42
    elif sheet == "vehicles":
        cx, cz, ext = grid(ids_by(("car_",), ("bus",)), 5, 6.5, 0.4)
        scale = 36
    elif sheet == "buildings":
        cx, cz, ext = grid(ids_by(("house_", "townhouse", "cafe", "gym", "library", "market", "office", "school")), 6, 28, 1.2)
        scale = 190
    else:
        cx, cz, ext = scene_street()
        scale = 80
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = scale; cam.data.clip_end = 1000
    k = ext
    if sheet == "scene":
        cam.location = (cx - 55, -cz - 75, 78)          # from the south-west, high
        look = Vector((cx + 4, -cz + 4, 0))
        sc.render.resolution_x, sc.render.resolution_y = 2400, 1500
    else:
        cam.location = (cx + k * 0.15, -cz + k * 0.75, k * 0.7)
        look = Vector((cx, -cz, 0.3))
        sc.render.resolution_x, sc.render.resolution_y = 2400, 1600
    cam.rotation_euler = (look - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = False
    sc.display.shading.show_shadows = True
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.74, 0.80, 0.86)
    sc.render.filepath = os.path.join(ROOT, "assets", "preview_outdoor_%s.png" % sheet)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW OK", sc.render.filepath)


main()
