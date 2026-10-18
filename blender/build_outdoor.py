"""Build the OUTDOOR / neighborhood kit (roads, vehicles, nature, street furniture, building shells, animals).

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python blender/build_outdoor.py
Filter: set env ONLY=car_sedan_red,tree_oak_l (comma list; or a prefix ending in * e.g. ONLY=house_*) -> rebuild just those
(manifest/footprints are merged, not replaced).
Outputs: assets/models/outdoor/<id>.glb, assets/models/manifest_outdoor.json, blender/outdoor/footprints.json.
Sources: blender/outdoor/{lib,roads,vehicles,nature,furniture,buildings,animals}.py (exec'd into one namespace).
Conventions: see blender/outdoor/README.md (1 unit = 1 m, origin = footprint centre on the ground, front = -Z).
"""
import bpy, bmesh, os, sys, json, math
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, "blender")
OD = os.path.join(HERE, "outdoor")
OUT = os.path.join(ROOT, "assets", "models", "outdoor")
os.makedirs(OUT, exist_ok=True)

_src = open(os.path.join(HERE, "build_all.py"), encoding="utf-8").read()
_cut = _src.rstrip().rfind("\nmain()")
assert _cut > 0, "build_all.py layout changed: could not strip main()"
LIB = {"__name__": "build_all_lib", "__file__": os.path.join(HERE, "build_all.py")}
exec(compile(_src[:_cut], "build_all.py", "exec"), LIB)

G = dict(LIB)                      # one shared namespace: Builder, PALETTE, clear_scene, bbox_godot ... + our helpers
G["LIB"] = LIB
G["__name__"] = "outdoor"
for mod in ("lib", "roads", "vehicles", "nature", "furniture", "buildings", "animals"):
    p = os.path.join(OD, mod + ".py")
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), G)

REG = G["REG"]
PALETTE = G["PALETTE"]


def match(oid, only):
    for o in only:
        if o.endswith("*") and oid.startswith(o[:-1]):
            return True
        if oid == o:
            return True
    return False


def main():
    only = [n for n in os.environ.get("ONLY", "").split(",") if n]
    mpath = os.path.join(ROOT, "assets", "models", "manifest_outdoor.json")
    fpath = os.path.join(OD, "footprints.json")
    manifest = json.load(open(mpath)) if only and os.path.exists(mpath) else {}
    foot = json.load(open(fpath)) if only and os.path.exists(fpath) else {}
    for oid, w, d, note, fn, kw in REG:
        if only and not match(oid, only):
            continue
        saved = {}
        for k, v in kw.get("pal", {}).items():
            saved[k] = PALETTE.get(k)
            PALETTE[k] = v
        G["purge"]()
        parts = fn()
        objs = G["build_parts"](oid, parts)
        if kw.get("post"):
            kw["post"](objs)
        bpy.context.view_layer.update()
        path = os.path.join(OUT, oid + ".glb")
        G["export_glb"](path, anim=bool(kw.get("post")))
        mn, mx = G["bbox_godot"]()
        for k, v in saved.items():
            PALETTE[k] = v
        h = round(mx[1], 2)
        foot[oid] = [w, d, h]
        nodes = sorted({o.name for o in bpy.context.scene.objects})
        manifest[oid] = {"file": "res://assets/models/outdoor/%s.glb" % oid, "footprint": [w, d, h], "notes": note,
                         "bounds_min": [round(v, 3) for v in mn], "bounds_max": [round(v, 3) for v in mx],
                         "nodes": nodes, "size_kb": round(os.path.getsize(path) / 1024, 1)}
        if kw.get("entry"):
            manifest[oid]["entry"] = kw["entry"]
        print("built", oid, [round(v, 2) for v in mn], [round(v, 2) for v in mx], manifest[oid]["size_kb"], "KB")
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1)
    with open(fpath, "w") as f:
        json.dump(foot, f, indent=1)
    big = [k for k, v in manifest.items() if v["size_kb"] > 300]
    print("OVER 300KB:", big)
    print("DONE", len(manifest))


main()
