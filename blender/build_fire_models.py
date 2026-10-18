"""Build the fire models (sprinkler head, burnt remains) used by data/incidents/03_fire.json. Standalone so it never touches the other
model builders:   blender --background --python blender/build_fire_models.py     -> assets/models/sprinkler.glb, ash_pile.glb
Conventions as in blender/README.md (front = -Z, origin = footprint centre on the floor)."""
import bpy, os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "build_all.py"), encoding="utf-8").read()
_cut = _src.rstrip().rfind("\nmain()")
assert _cut > 0
LIB = {"__name__": "build_all_lib", "__file__": os.path.join(HERE, "build_all.py")}
exec(compile(_src[:_cut], "build_all.py", "exec"), LIB)
Builder, PALETTE, build_static = LIB["Builder"], LIB["PALETTE"], LIB["build_static"]
PALETTE.update({"spr_brass": ((0.78, 0.62, 0.25), 0.4, 0.8), "spr_white": ((0.92, 0.93, 0.95), 0.5, 0.0), "spr_red": ((0.8, 0.12, 0.1), 0.35, 0.0),
                "ash_dark": ((0.14, 0.13, 0.13), 0.95, 0.0), "ash_grey": ((0.45, 0.44, 0.43), 0.95, 0.0), "ash_coal": ((0.05, 0.05, 0.05), 0.9, 0.0)})


def sprinkler():
    # ceiling sprinkler head (the object sits at ceiling height; the model is drawn at that height)
    b = Builder()
    b.cyl("spr_white", 0, 2.58, 0, 0.14, 0.04, seg=16)          # ceiling rose
    b.cyl("spr_brass", 0, 2.50, 0, 0.04, 0.10, seg=10)          # pipe stub
    b.sphere("spr_red", 0, 2.45, 0, 0.045, 3, 10)               # glass bulb
    b.box("spr_brass", 0, 2.43, 0, 0.16, 0.012, 0.012)          # deflector arms
    b.box("spr_brass", 0, 2.43, 0, 0.012, 0.012, 0.16)
    return [("sprinkler", b, (0, 0, 0))]


def ash_pile():
    b = Builder()
    b.cyl("ash_dark", 0, 0.01, 0, 0.46, 0.02, seg=14)             # soot patch
    b.cyl("ash_grey", -0.12, 0.03, 0.08, 0.15, 0.06, r2=0.05, seg=8)  # low heaps of ash
    b.cyl("ash_grey", 0.13, 0.025, -0.1, 0.12, 0.05, r2=0.04, seg=7)
    b.cyl("ash_grey", 0.05, 0.02, 0.18, 0.09, 0.04, r2=0.03, seg=7)
    for (x, z, sx, sy, sz) in ((-0.22, -0.14, 0.09, 0.05, 0.06), (0.2, 0.15, 0.06, 0.06, 0.08), (0.02, -0.05, 0.1, 0.04, 0.05),
                               (-0.05, 0.28, 0.05, 0.04, 0.05), (0.3, -0.22, 0.07, 0.05, 0.05), (-0.3, 0.12, 0.05, 0.04, 0.07)):
        b.box("ash_coal", x, sy * 0.5 + 0.02, z, sx, sy, sz)         # charred chunks
    return [("ash_pile", b, (0, 0, 0))]


for fn in (sprinkler, ash_pile):
    path, mn, mx = build_static(fn)
    print("built", fn.__name__, path, [round(v, 2) for v in mn], [round(v, 2) for v in mx])
