"""Render a contact sheet of every glb in assets/models -> assets/preview_extra.png (Workbench, headless)."""
import bpy, os, json, math
from mathutils import Vector
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MD = os.path.join(ROOT, "assets", "models")
man = json.load(open(os.path.join(MD, "manifest_extra.json")))
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
names = list(man.keys())
cols = 8; sp = 3.3
for i, n in enumerate(names):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MD, n + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    x = (i % cols) * sp; y = -(i // cols) * sp
    for o in new:
        if o.parent is None:
            o.location += Vector((x, y, 0))
    t = bpy.data.curves.new("t", 'FONT'); t.body = n; t.size = 0.3; t.align_x = 'CENTER'
    to = bpy.data.objects.new("t", t); bpy.context.scene.collection.objects.link(to)
    to.location = (x, y + 1.45, 0.01); to.rotation_euler = (0, 0, math.pi)
rows = (len(names) + cols - 1) // cols
cx = (cols - 1) * sp / 2; cy = -(rows - 1) * sp / 2
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.scene.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 30
cam.location = (cx + 4, cy + 22, 20); cam.rotation_euler = (Vector((cx, cy, 0.8)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = False
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.75, 0.78, 0.8)
sc.render.resolution_x = 2800; sc.render.resolution_y = 1700
sc.render.filepath = os.path.join(ROOT, "assets", "preview_extra.png")
bpy.ops.render.render(write_still=True)
print("PREVIEW OK")
