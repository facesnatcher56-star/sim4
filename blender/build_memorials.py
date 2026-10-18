"""Build the memorial models (grave tombstone, urn) used by scripts/systems/graves.gd. Standalone so it never touches the other
model builders:   blender --background --python blender/build_memorials.py     -> assets/models/grave.glb, urn.glb
Conventions as in blender/README.md (front = -Z, origin = footprint centre on the floor)."""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "build_all.py"), encoding="utf-8").read()
_cut = _src.rstrip().rfind("\nmain()")
assert _cut > 0
LIB = {"__name__": "build_all_lib", "__file__": os.path.join(HERE, "build_all.py")}
exec(compile(_src[:_cut], "build_all.py", "exec"), LIB)
Builder, PALETTE, build_static = LIB["Builder"], LIB["PALETTE"], LIB["build_static"]
PALETTE.update({"grave_stone": ((0.58, 0.60, 0.62), 0.8, 0.0), "grave_moss": ((0.30, 0.45, 0.28), 0.95, 0.0), "urn_clay": ((0.62, 0.42, 0.28), 0.6, 0.0)})


def grave():
    b = Builder()
    b.box("grave_moss", 0, 0.03, 0.12, 0.62, 0.06, 0.95)        # low grass mound
    b.box("grave_stone", 0, 0.08, -0.25, 0.5, 0.16, 0.14)       # base
    b.box("grave_stone", 0, 0.45, -0.25, 0.38, 0.6, 0.1)        # slab
    b.cyl("grave_stone", 0, 0.75, -0.25, 0.19, 0.1, seg=16)     # rounded top (disc on its side approximated by a short cylinder)
    return [("grave", b, (0, 0, 0))]


def urn():
    b = Builder()
    b.box("wood_dark", 0, 0.05, 0, 0.46, 0.1, 0.46)              # plinth
    b.cyl("urn_clay", 0, 0.1, 0, 0.17, 0.32, r2=0.17, seg=14)
    b.sphere("urn_clay", 0, 0.42, 0, 0.17, 3, 12)
    b.cyl("urn_clay", 0, 0.5, 0, 0.07, 0.1, seg=12)
    b.cyl("wood", 0, 0.6, 0, 0.09, 0.04, seg=12)
    return [("urn", b, (0, 0, 0))]


for fn in (grave, urn):
    path, mn, mx = build_static(fn)
    print("built", fn.__name__, path, [round(v, 2) for v in mn], [round(v, 2) for v in mx])
