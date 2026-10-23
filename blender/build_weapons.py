"""Build the weapon models (task 57) into assets/models/<id>.glb. Hand-held items: they stay out of the object manifest.

Run:  "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" --background --python blender/build_weapons.py
Re-uses build_extra.py's library (its trailing main() call stripped). Models: blender/extra/models_w.py.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "build_extra.py"), encoding="utf-8").read()
_cut = _src.rstrip().rfind("\nmain()")
assert _cut > 0, "build_extra.py layout changed: could not strip main()"
LIB = {"__name__": "build_extra_lib", "__file__": os.path.join(HERE, "build_extra.py")}
exec(compile(_src[:_cut], "build_extra.py", "exec"), LIB)
LIB["PALETTE"].update({
    "bottle_glass": ((0.32, 0.52, 0.30), 0.15, 0.0),
})
Wm = LIB["_load"]("models_w")

for oid in Wm["IDS"]:
    fn = Wm[oid]

    def f(fn=fn):
        return fn(LIB["Builder"], LIB["tube"])
    f.__name__ = oid
    path, mn, mx = LIB["build_static"](f)
    print("built", oid, [round(v, 3) for v in mn], [round(v, 3) for v in mx])
print("DONE weapons", len(Wm["IDS"]))
