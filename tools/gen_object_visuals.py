"""Generates data/object_visuals.json (task 33.3). Edit this file or the JSON directly; the JSON is the source of truth at run time.
Run: python -I tools/gen_object_visuals.py"""
import json


def part(shape, size, pos, color, rot=None, emit=0, flicker=0, light=None, grid=None, grow=None):
    p = {"shape": shape, "size": size, "pos": pos, "color": color}
    if rot: p["rot"] = rot
    if emit: p["emit"] = emit
    if flicker: p["flicker"] = flicker
    if light: p["light"] = light
    if grid: p["grid"] = grid
    if grow: p["grow"] = grow
    return p


def st(id, when=None, **kw):
    d = {"id": id}
    if when is not None: d["when"] = when
    d.update(kw)
    return d


def eq(k, v): return {"key": k, "eq": v}


O = {}
T = {}
T["dirt"] = {"id": "dirt", "states": [
    st("filthy", [{"key": "dirtiness", "ratio_gte": 0.6}], overlay="#54391499"),
    st("dirty", [{"key": "dirtiness", "ratio_gte": 0.3}], overlay="#5a45284d"),
    st("clean")]}
T["broken"] = {"id": "broken", "states": [
    st("broken", [eq("broken", True)], overlay="#1c1c1c99",
       fx=[{"kind": "sparks", "pos": [0, 0.05, 0], "on_top": True}, {"kind": "smoke", "pos": [0, 0.1, 0], "on_top": True}]),
    st("ok")]}
T["screen_on"] = {"id": "screen", "states": [
    st("on", [{"any": [eq("on", True), {"in_use": True}]}], surfaces={"screen": {"color": "#4f98e6", "emit": 1.05, "flicker": 0.5}},
       parts=[part("box", [0.01, 0.01, 0.01], [0, 0.8, -0.4], "#8fc4ff", light=[3.2, 0.55])]),
    st("off")]}
T["spoiled"] = {"id": "spoiled", "states": [
    st("spoiled", [{"key": "spoiled", "ratio_gte": 0.3}], fx=[{"kind": "stink", "pos": [0, 0.05, 0], "on_top": True}]), st("fresh")]}

# potted plant: dry / watered / wilting (+ being watered)
O["plant"] = {"layers": [
    {"id": "water", "states": [
        st("wilting", [{"key": "water", "lte": 1.5}], surfaces={"soil": "#c9a878", "leaf": "#a39a3a"}, scale=[1, 0.8, 1], tilt=11,
           parts=[part("box", [0.09, 0.012, 0.05], [0.3, 0.012, 0.1], "#6b5a2a", rot=[0, 30, 0]),
                  part("box", [0.07, 0.012, 0.05], [-0.28, 0.012, -0.12], "#7a6430", rot=[0, -40, 0])]),
        st("dry", [{"key": "water", "lte": 3.5}], surfaces={"soil": "#c4a373", "leaf": "#bcc47e"}),
        st("watered", [{"key": "water", "gte": 8.5}], surfaces={"soil": "#241810"},
           parts=[part("cyl", [0.36, 0.004], [0, 0.004, 0], "#5f86a8b0"),
                  part("sphere", [0.02], [0.2, 0.62, 0.05], "#a8dcff", emit=0.6),
                  part("sphere", [0.018], [-0.18, 0.72, -0.08], "#a8dcff", emit=0.6),
                  part("sphere", [0.016], [0.05, 0.9, 0.15], "#a8dcff", emit=0.6)]),
        st("moist", surfaces={"soil": "#4a3322"})]},
    {"id": "being_watered", "states": [st("pouring", [{"in_use": True}], fx=[{"kind": "drops", "pos": [0.05, 1.25, -0.05]}]), st("idle")]}]}

# garden plot: soil wetness, crop stages (bare, sprouts, growing, leafy, ripe with fruit, wilted), weeds
G = {"nx": 5, "nz": 2, "x0": -0.72, "dx": 0.36, "z0": -0.17, "dz": 0.34}


def grid(**k):
    g = dict(G)
    g.update(k)
    return g


O["garden_plot"] = {"layers": [
    {"id": "soil", "states": [st("dry", [{"key": "water", "lte": 1.5}], surfaces={"soil": "#c9a979"}),
                              st("wet", [{"key": "water", "gte": 4}], surfaces={"soil": "#241810"}),
                              st("moist", surfaces={"soil": "#4a3322"})]},
    {"id": "crop", "states": [
        st("wilted", [{"key": "growth", "gte": 1}, {"key": "water", "lte": 1}], hide=["crop_*"],
           parts=[part("sphere", [0.09], [0, 0.27, 0], "#a09a46", grid=G, rot=[0, 0, 20])]),
        st("ripe", [{"key": "growth", "gte": 8}], hide=["crop_*"], parts=[
            part("sphere", [0.14], [0, 0.32, 0], "#36883a", grid=G),
            part("sphere", [0.05], [0.08, 0.4, -0.07], "#d9392b", emit=0.15, grid=G),
            part("sphere", [0.05], [-0.07, 0.34, -0.1], "#e8742c", emit=0.1, grid=G)]),
        st("leafy", [{"key": "growth", "gte": 6}], hide=["crop_*"], parts=[part("sphere", [0.13], [0, 0.31, 0], "#3f9a3a", grid=G)]),
        st("growing", [{"key": "growth", "gte": 3}], hide=["crop_*"], parts=[part("cone", [0.07, 0.24], [0, 0.33, 0], "#5fb046", grid=G)]),
        st("sprouts", [{"key": "growth", "gte": 1}], hide=["crop_*"], parts=[part("cone", [0.035, 0.09], [0, 0.255, 0], "#7fcf5a", grid=G)]),
        st("bare", hide=["crop_*"])]},
    {"id": "weeds", "states": [
        st("overgrown", [{"key": "weeds", "gte": 6}], parts=[
            part("cone", [0.05, 0.2], [0, 0.31, 0], "#6f7a35", grid=grid(nx=4, nz=1, x0=-0.54, z0=0.0)),
            part("cone", [0.05, 0.26], [0, 0.34, 0], "#5f6a2d", grid=grid(nx=5, nz=2, x0=-0.72, z0=-0.38, dz=0.76))]),
        st("weedy", [{"key": "weeds", "gte": 3}], parts=[part("cone", [0.045, 0.17], [0, 0.3, 0], "#6f7a35", grid=grid(nx=4, nz=1, x0=-0.54, z0=0.0))]),
        st("tidy")]}]}

# dirty / clean (tint), broken (sparks, smoke, dark tint)
for d in ["fridge", "stove", "counter", "table", "toilet", "shower", "bathtub", "sink", "rug", "dresser", "coffee_table", "desk",
          "grill", "hot_tub", "bar_counter", "microwave_cart", "coffee_maker"]:
    O[d] = {"layers": ["@dirt"]}
for d in ["fridge", "stove", "toilet", "shower", "bathtub", "sink", "tv", "treadmill", "computer", "grill", "hot_tub", "stereo",
          "washing_machine", "microwave_cart", "coffee_maker", "vending_machine", "terminal"]:
    O.setdefault(d, {"layers": []})["layers"].append("@broken")
O["toilet"]["layers"].append({"id": "grime_spots", "states": [
    st("spots", [{"key": "dirtiness", "ratio_gte": 0.5}],
       parts=[part("cyl", [0.07, 0.004], [0, 0.445, -0.05], "#3b2f1a"), part("cyl", [0.04, 0.004], [0.06, 0.445, 0.08], "#3b2f1a")]), st("none")]})
O["sink"]["layers"].append({"id": "grime_spots", "states": [
    st("spots", [{"key": "dirtiness", "ratio_gte": 0.5}],
       parts=[part("cyl", [0.09, 0.004], [0.0, 0.865, 0.05], "#3b2f1a"), part("box", [0.14, 0.006, 0.1], [-0.2, 0.865, 0.2], "#4a3a20", rot=[0, 25, 0])]),
    st("none")]})

# screens
O["tv"]["layers"].append("@screen_on")
O["computer"]["layers"].append("@screen_on")
O["stereo"]["layers"].append({"id": "display", "states": [
    st("on", [{"in_use": True}], surfaces={"screen": {"color": "#7dffa0", "emit": 1.6}}), st("off")]})
O["treadmill"]["layers"].append({"id": "display", "states": [
    st("on", [{"in_use": True}], surfaces={"screen": {"color": "#7dffa0", "emit": 1.6}}), st("off")]})

# fridge: door opens while somebody uses it (not while wiping it), spoiled food smells
O["fridge"]["layers"].append("@spoiled")
O["fridge"]["layers"].append({"id": "door", "states": [
    st("open", [{"use_not_tag": ["clean"]}], parts=[
        part("box", [0.74, 1.62, 0.012], [0, 0.93, -0.353], "#fff6dc", emit=1.1, light=[2.2, 0.5]),
        part("box", [0.78, 1.7, 0.05], [-0.299, 0.93, -0.747], "#e9ecef", rot=[0, 75, 0])]), st("shut")]})

# stove burners glow while cooking; grill flames too
bur = [part("cyl", [0.085, 0.012], [x, 0.965, z], "#ff4a1c", emit=2.2) for x, z in [(-0.16, -0.12), (0.16, -0.12), (-0.16, 0.22), (0.16, 0.22)]]
bur.append(part("box", [0.01, 0.01, 0.01], [0, 1.1, 0.05], "#ff8a3a", light=[2.4, 0.7]))
O["stove"]["layers"].append({"id": "burners", "states": [
    st("cooking", [{"use_tag": ["cook"]}], parts=bur, fx=[{"kind": "steam", "pos": [0, 1.0, 0.05]}]), st("off")]})
O["grill"]["layers"].append({"id": "flames", "states": [
    st("cooking", [{"use_tag": ["cook"]}], surfaces={"fire": {"color": "#ff7a2a", "emit": 2.2, "flicker": 0.5}}, fx=[{"kind": "smoke", "pos": [0, 1.2, 0]}]),
    st("off")]})


# lamps on / off
def lamp(pos, shade="lamp_shade", rng=4.2, en=0.9):
    return {"layers": [{"id": "light", "states": [
        st("on", [eq("on", True)], surfaces={shade: {"color": "#ffe3a3", "emit": 2.0}},
           parts=[part("sphere", [0.03], pos, "#ffd98a", emit=2.5, light=[rng, en])]), st("off")]}]}


O["lamp"] = lamp([0, 1.42, 0])
O["nightstand"] = lamp([-0.1, 0.85, 0.1], rng=3.0, en=0.7)
O["pendant_light"] = lamp([0, 1.8, 0], rng=5.0, en=1.0)

# beds: made = the model as it is; unmade = the neat blanket is hidden and a rumpled one lies on top
unmade = [part("box", [1.78, 0.03, 1.5], [0, 0.64, -0.12], "#ecebf0"),
          part("box", [1.5, 0.14, 0.85], [0.15, 0.71, -0.45], "#7f9bc4", rot=[0, 8, 3]),
          part("box", [0.9, 0.16, 0.6], [-0.35, 0.75, -0.1], "#6c88b4", rot=[0, -18, -5]),
          part("box", [0.08, 0.55, 0.8], [0.97, 0.38, -0.5], "#7f9bc4", rot=[0, 0, -4]),
          part("box", [0.6, 0.14, 0.34], [-0.2, 0.7, 0.65], "#f1efe8", rot=[0, 22, 0])]
O["bed"] = {"layers": [{"id": "made", "states": [st("unmade", [eq("made", False)], hide=["fabric_*", "baby_blue"], parts=unmade), st("made")]}]}
O["single_bed"] = {"extends": "bed", "part_scale": [0.5, 1, 1]}


# easels: the canvas fills in with the painting progress (washes, hills, a sun)
def easel(w, h, y0, zf, hide):
    zz = zf - 0.004
    return {"layers": [
        {"id": "blank", "states": [st("blank", [{"key": "progress", "ratio_lte": 0}], hide=hide), st("started")]},
        {"id": "wash", "states": [st("wash", [{"key": "progress", "ratio_gt": 0}], hide=hide, parts=[
            part("box", [w, h, 0.006], [0, y0 + h / 2, zz], "#f2d58c", grow={"key": "progress", "axis": 1, "min": 0.3, "lerp": True})])]},
        {"id": "detail", "states": [
            st("scene", [{"key": "progress", "ratio_gte": 0.5}], parts=[
                part("box", [w, h * 0.35, 0.008], [0, y0 + h * 0.175, zz - 0.003], "#4f9a4a"),
                part("cyl", [h * 0.12, 0.008], [w * 0.22, y0 + h * 0.72, zz - 0.003], "#f08a2b", rot=[90, 0, 0], emit=0.3)]),
            st("hills", [{"key": "progress", "ratio_gte": 0.25}], parts=[part("box", [w, h * 0.3, 0.008], [0, y0 + h * 0.15, zz - 0.003], "#4f9a4a")]),
            st("none")]}]}


O["easel"] = easel(0.58, 0.78, 0.67, -0.135, ["paint_*"])
O["easel_large"] = easel(1.28, 1.08, 0.72, -0.115, ["paint_*"])
O["trash_bin"] = {"layers": [{"id": "full", "states": [
    st("overflowing", [{"key": "fullness", "ratio_gte": 0.8}], fx=[{"kind": "stink", "pos": [0, 0.05, 0], "on_top": True}]), st("ok")]}]}

FX = {
    "sparks": {"amount": 14, "lifetime": 0.55, "explosiveness": 0.5, "dir": [0, 1, 0], "spread": 65, "v_min": 1.0, "v_max": 2.4,
               "gravity": [0, -6, 0], "size_min": 0.02, "size_max": 0.035, "color": "#ffc94a", "flashy": True},
    "smoke": {"amount": 8, "lifetime": 2.0, "dir": [0, 1, 0], "spread": 18, "v_min": 0.25, "v_max": 0.4, "gravity": [0, 0.1, 0],
              "size_min": 0.14, "size_max": 0.26, "color": "#2e2e2ee0"},
    "steam": {"amount": 8, "lifetime": 1.8, "dir": [0, 1, 0], "spread": 20, "v_min": 0.2, "v_max": 0.35, "gravity": [0, 0.1, 0],
              "size_min": 0.08, "size_max": 0.16, "color": "#f4f6f8a0"},
    "drops": {"amount": 14, "lifetime": 0.45, "dir": [0, -1, 0], "spread": 6, "v_min": 0.4, "v_max": 0.8, "gravity": [0, -7, 0],
              "size_min": 0.025, "size_max": 0.04, "color": "#8fd0ff"},
    "stink": {"amount": 5, "lifetime": 2.2, "dir": [0, 1, 0], "spread": 25, "v_min": 0.15, "v_max": 0.3, "gravity": [0, 0.05, 0],
              "size_min": 0.07, "size_max": 0.13, "color": "#8fb04a80"}}

json.dump({"version": 1, "near_tiles": 26,
           "about": "Task 33.3: object state -> visual. See scripts/world/object_visual_rules.gd for the schema. Generated by tools/gen_object_visuals.py.",
           "templates": T, "fx_kinds": FX, "objects": O},
          open("data/object_visuals.json", "w", encoding="utf-8"), indent=1)
