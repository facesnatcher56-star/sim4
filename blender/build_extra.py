"""Build the EXTRA content models (38 objects) without touching build_all.py or existing models.

Run:  "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python blender/build_extra.py

Re-uses Builder / palette / export from build_all.py (its source is exec'd with the trailing main() call removed, so
nothing existing is regenerated). Model sources live in blender/extra/models_a.py and models_b.py.
Outputs: assets/models/<id>.glb, assets/models/manifest_extra.json (same schema as manifest.json),
blender/footprints_extra.json. Conventions: see blender/README.md (front = -Z, origin = footprint centre on the floor).
"""
import bpy, bmesh, os, sys, json
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.join(ROOT, "blender")

# ---- load the shared builder library (build_all.py minus its final main() call) -------------------
_src = open(os.path.join(HERE, "build_all.py"), encoding="utf-8").read()
_cut = _src.rstrip().rfind("\nmain()")
assert _cut > 0, "build_all.py layout changed: could not strip main()"
LIB = {"__name__": "build_all_lib", "__file__": os.path.join(HERE, "build_all.py")}
exec(compile(_src[:_cut], "build_all.py", "exec"), LIB)
Builder = LIB["Builder"]
PALETTE = LIB["PALETTE"]
build_static = LIB["build_static"]
OUT = LIB["OUT"]

# ---- extra palette entries ------------------------------------------------------------------------
PALETTE.update({
    "baby_blue":    ((0.62, 0.78, 0.92), 0.95, 0.0),
    "brass":        ((0.80, 0.60, 0.22), 0.4, 0.7),
    "piano":        ((0.05, 0.05, 0.06), 0.25, 0.0),
    "ivory":        ((0.94, 0.92, 0.84), 0.5, 0.0),
    "fabric_green": ((0.28, 0.52, 0.34), 0.95, 0.0),
    "crop_green":   ((0.30, 0.66, 0.26), 0.9, 0.0),
    "crop_orange":  ((0.93, 0.50, 0.12), 0.8, 0.0),
    "red_paint":    ((0.78, 0.14, 0.12), 0.5, 0.0),
    "yellow_safety": ((0.96, 0.80, 0.10), 0.6, 0.0),
    "teal":         ((0.18, 0.52, 0.58), 0.6, 0.0),
    "brick":        ((0.58, 0.28, 0.20), 0.95, 0.0),
    "fire":         ((0.98, 0.45, 0.08), 0.5, 0.0),
    "silver":       ((0.82, 0.86, 0.90), 0.1, 0.9),
    "metal_dark":   ((0.25, 0.27, 0.30), 0.4, 0.8),
    "felt_green":   ((0.10, 0.45, 0.26), 1.0, 0.0),
    "coffee":       ((0.26, 0.14, 0.08), 0.5, 0.0),
})


def tube(b, mat, p0, p1, r, seg=8):
    """Angled cylinder between two points given in GODOT coordinates."""
    g0 = Vector(Builder._b(*p0))
    g1 = Vector(Builder._b(*p1))
    d = g1 - g0
    length = d.length
    before = set(b.bm.verts)
    bmesh.ops.create_cone(b.bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=length)
    vs = [v for v in b.bm.verts if v not in before]
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    mid = (g0 + g1) / 2
    for v in vs:
        v.co = q @ v.co + mid
    b._finish(vs, mat)


def _load(name):
    ns = {"__name__": name}
    path = os.path.join(HERE, "extra", name + ".py")
    exec(compile(open(path, encoding="utf-8").read(), path, "exec"), ns)
    return ns


A = _load("models_a")
Bm = _load("models_b")
Cm = _load("models_c")          # task 60: objects that had no model or wore another one

# (id, module ns, w tiles along X, d tiles along Z, note)
SPEC = [
    ("crib", A, 1, 2, "1x2 baby crib; slats on the long sides; headboard at +Z; sleeper lies inside"),
    ("dresser", A, 1, 1, "drawers face -Z"),
    ("wardrobe", A, 1, 1, "double doors face -Z; 1.95 m tall"),
    ("nightstand", A, 1, 1, "bedside table with lamp; drawers face -Z; 0.5 m body centred in the tile"),
    ("armchair", A, 1, 1, "backrest at +Z; sitter faces -Z"),
    ("coffee_table", A, 2, 1, "2x1 low table, long axis X"),
    ("dining_chair", A, 1, 1, "padded seat top y~0.46, back at +Z"),
    ("bar_stool", A, 1, 1, "seat top y~0.80"),
    ("single_bed", A, 1, 2, "1x2; headboard/pillow at +Z; mattress top y~0.55"),
    ("bunk_bed", A, 1, 2, "1x2; lower mattress top y~0.45, upper y~1.3; ladder on +X side"),
    ("desk", A, 1, 1, "writing desk; user stands/sits at -Z side"),
    ("bookcase_tall", A, 1, 1, "2.1 m bookcase, open front faces -Z"),
    ("piano", A, 2, 1, "2x1 upright piano; keys and stool on the -Z side"),
    ("guitar_stand", A, 1, 1, "stand with an acoustic guitar and a small amp"),
    ("fishing_spot", A, 2, 1, "2x1 pond edge with a short pier on the -Z side; water behind it"),
    ("garden_plot", A, 2, 1, "2x1 raised bed; origin at footprint centre"),
    ("mailbox", A, 1, 1, "post-mounted mailbox; slot faces -Z"),
    ("grill", A, 1, 1, "kettle barbecue with side shelf"),
    ("hot_tub", A, 2, 2, "2x2 wooden hot tub; water surface y~0.8; steps on -Z side"),
    ("mirror", A, 1, 1, "standing mirror, glass faces -Z"),
    ("fireplace", A, 2, 1, "2x1 brick fireplace with hearth on the -Z side"),
    ("stereo", A, 1, 1, "cabinet with tall speakers; faces -Z"),
    ("bar_counter", A, 2, 1, "2x1 bar; customers stand on the -Z side"),
    ("ceiling_fan", A, 1, 1, "CEILING piece (geometry at y 2.2-2.6); use layer 'floor'"),
    ("pendant_light", A, 1, 1, "CEILING piece (geometry at y 1.85-2.6); use layer 'floor'"),
    ("washing_machine", Bm, 1, 1, "front-loader; door faces -Z"),
    ("microwave_cart", Bm, 1, 1, "microwave on a small cabinet; faces -Z"),
    ("coffee_maker", Bm, 1, 1, "coffee machine on a counter stand; faces -Z"),
    ("tea_kettle", Bm, 1, 1, "kettle and mugs on a small stand"),
    ("easel_large", Bm, 2, 1, "2x1 studio easel; canvas faces -Z"),
    ("workbench", Bm, 2, 1, "2x1 workbench with pegboard at +Z; user at -Z"),
    ("dumbbell_rack", Bm, 1, 1, "weights rack"),
    ("pool_table", Bm, 2, 1, "2x1 bar pool table; players stand on the -Z side"),
    ("fire_extinguisher", Bm, 1, 1, "extinguisher on a small plate with a wall board at +Z"),
    ("smoke_alarm", Bm, 1, 1, "CEILING piece (geometry at y 2.5-2.6); use layer 'floor'"),
    ("vending_machine", Bm, 1, 1, "front (glass) faces -Z"),
    ("terminal", Bm, 1, 1, "kiosk terminal / ATM; screen faces -Z"),
    ("telescope", Bm, 1, 1, "tripod telescope pointing towards -Z"),
    ("park_bench", Bm, 2, 1, "2x1 park bench, backrest at +Z; sitter faces -Z; seat top y~0.55"),
    ("deck_chair", Cm, 1, 1, "task 60"),
    ("theatre_seat", Cm, 1, 1, "task 60"),
    ("sunbed", Cm, 1, 1, "task 60"),
    ("log_bench", Cm, 2, 1, "task 60"),
    ("pew", Cm, 2, 1, "task 60"),
    ("tent", Cm, 2, 2, "task 60"),
    ("operating_table", Cm, 1, 2, "task 60"),
    ("beach_umbrella", Cm, 1, 1, "task 60"),
    ("campfire", Cm, 1, 1, "task 60"),
    ("fountain", Cm, 1, 1, "task 60"),
    ("hiking_trail", Cm, 1, 1, "task 60"),
    ("life_ring", Cm, 1, 1, "task 60"),
    ("meteorite", Cm, 1, 1, "task 60"),
    ("debris", Cm, 1, 1, "task 60"),
    ("generator", Cm, 1, 1, "task 60"),
    ("playground", Cm, 2, 2, "task 60"),
    ("public_bin", Cm, 1, 1, "task 60"),
    ("sandbags", Cm, 1, 1, "task 60"),
    ("slip_mat", Cm, 1, 1, "task 60"),
    ("solar_panel", Cm, 1, 1, "task 60"),
    ("storm_shelter", Cm, 1, 1, "task 60"),
    ("storm_shutters", Cm, 1, 1, "task 60"),
    ("streetlamp", Cm, 1, 1, "task 60"),
    ("water_tank", Cm, 1, 1, "task 60"),
    ("well", Cm, 1, 1, "task 60"),
    ("podium", Cm, 1, 1, "task 60"),
    ("guard_dog_kennel", Cm, 1, 1, "task 60"),
    ("parking_bay", Cm, 2, 2, "task 60"),
    ("stage", Cm, 2, 1, "task 60"),
    ("assembly_line", Cm, 2, 1, "task 60"),
    ("forklift", Cm, 2, 1, "task 60"),
    ("site_materials", Cm, 2, 1, "task 60"),
    ("vehicle_lift", Cm, 2, 1, "task 60"),
    ("pallet_rack", Cm, 1, 1, "task 60"),
    ("surf_rack", Cm, 1, 1, "task 60"),
    ("ski_rack", Cm, 1, 1, "task 60"),
    ("captain_wheel", Cm, 1, 1, "task 60"),
    ("slot_machine", Cm, 1, 1, "task 60"),
    ("phone", Cm, 1, 1, "task 60"),
    ("security_light", Cm, 1, 1, "task 60"),
    ("security_camera", Cm, 1, 1, "task 60"),
    ("motion_sensor", Cm, 1, 1, "task 60"),
    ("burglar_alarm", Cm, 1, 1, "task 60"),
    ("safe", Cm, 1, 1, "task 60"),
    ("vault_safe", Cm, 1, 1, "task 60"),
    ("medical_cabinet", Cm, 1, 1, "task 60"),
    ("first_aid_kit", Cm, 1, 1, "task 60"),
    ("public_toilet", Cm, 1, 1, "task 60"),
    ("shop_stall", Cm, 1, 1, "task 60"),
    ("souvenir_stand", Cm, 1, 1, "task 60"),
]


def main():
    manifest = {}
    foot = {}
    only = [n for n in os.environ.get("ONLY", "").split(",") if n]    # ONLY=park_bench rebuilds just those glbs (manifest untouched)
    for oid, mod, w, d, note in SPEC:
        if only and oid not in only:
            continue
        fn = mod[oid]

        def make(fn=fn, oid=oid):
            def f():
                return fn(Builder, tube)
            f.__name__ = oid
            return f

        path, mn, mx = build_static(make())
        h = round(mx[1], 2)
        foot[oid] = [w, d, h]
        manifest[oid] = {"file": "res://assets/models/%s.glb" % oid, "footprint": [w, d, h], "notes": note,
                         "bounds_min": [round(v, 3) for v in mn], "bounds_max": [round(v, 3) for v in mx]}
        print("built", oid, [round(v, 2) for v in mn], [round(v, 2) for v in mx])
    if only:
        print("DONE (partial)", only)
        return
    with open(os.path.join(OUT, "manifest_extra.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    with open(os.path.join(HERE, "footprints_extra.json"), "w") as f:
        json.dump(foot, f, indent=2)
    bad = [k for k in manifest if not os.path.exists(os.path.join(OUT, k + ".glb")) or os.path.getsize(os.path.join(OUT, k + ".glb")) < 500]
    print("MISSING/EMPTY:", bad)
    print("DONE", len(manifest))


main()
