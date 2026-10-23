"""Task 60: read the object bench log (tools/object_bench_run.gd) and list what looks wrong per object, plus contact sheets per category.
    python tools/object_bench_report.py <bench log> <shot dir> [<sheet out dir>]
Prints one line per object: OK or the problems found. With a sheet dir, writes <category>.jpg: each object's day close-up and its first "in use" shot.
"""
import json
import os
import sys

CATS = [  # first match wins, on the object's tags or id
    ("beds", ["bed", "crib", "sleep"]),
    ("bathroom", ["bathroom", "plumbing", "toilet", "shower", "bath"]),
    ("kitchen", ["kitchen", "cook", "fridge", "stove", "kettle", "coffee", "microwave", "grill", "counter"]),
    ("seating", ["seat", "sofa", "chair", "bench", "stool", "armchair"]),
    ("electronics", ["electronics", "tv", "computer", "screen", "stereo", "music", "game", "terminal", "arcade"]),
    ("outdoor", ["outdoor", "garden", "park", "fishing", "hot_tub", "telescope", "tree", "fountain"]),
    ("work", ["work", "industrial", "office", "career", "factory", "warehouse", "workbench", "forklift", "assembly", "pallet", "site", "lift", "desk"]),
    ("shop and civic", ["shop", "civic", "service", "bank", "hospital", "police", "court", "school", "cell", "safe", "camera", "reception", "vending", "parking", "shelter", "till", "cooler", "shelf"]),
    ("decor", ["decor", "light", "lamp", "plant", "rug", "mirror", "art", "bookcase", "bookshelf", "table", "dresser", "wardrobe", "nightstand"]),
]
CEILING = {"pendant_light", "smoke_alarm", "security_camera", "ceiling_fan", "burglar_alarm", "motion_sensor", "sprinkler"}
SEATED = ("Sit", "Toilet", "Sleep", "Lie", "Bath")


def category(r):
    words = [str(t) for t in r.get("tags", [])] + [r["def"]]
    for name, keys in CATS:
        for k in keys:
            if any(k in w for w in words):
                return name
    return "other"


def problems(r):
    out = []
    d = r["def"]
    for p in r.get("place", []):
        if "err" in p:
            out.append("rot %d: %s" % (p["rot"], p["err"]))
            continue
        if "over" in p and not r.get("wall_mount"):
            worst = max(p["over"])
            if worst > 0.08:
                out.append("rot %d: model %.2f m past its footprint" % (p["rot"], worst))
            if p.get("fill", 1) < 0.08 and d not in CEILING:          # a ceiling piece covers a floor tile on purpose (it never blocks)
                out.append("rot %d: model fills %d%% of its footprint (invisible blocker?)" % (p["rot"], p["fill"] * 100))
        if "y" in p and d not in CEILING and not r.get("wall_mount"):
            if p["y"][0] > 0.05:
                out.append("rot %d: floats %.2f m above the floor" % (p["rot"], p["y"][0]))
            if p["y"][0] < -0.05:
                out.append("rot %d: sunk %.2f m into the floor" % (p["rot"], -p["y"][0]))
        if p.get("sold") is False:
            out.append("rot %d: could not be sold" % p["rot"])
    for p in r.get("wall", []):
        if "err" in p:
            continue
        if p.get("through_wall", -1) > 0.02:
            out.append("against a wall, rot %d: %.2f m through the wall" % (p["rot"], p["through_wall"]))
    if "upstairs" in r and not str(r["upstairs"]).startswith("ok") and not r.get("wall_mount"):
        out.append("upstairs: " + str(r["upstairs"]))
    for u in r.get("use", []):
        tag = "'%s'" % u["label"]
        if "skipped" in u:
            continue          # no longer on offer after the earlier actions: not a fault
        if not u["started"]:
            out.append(tag + ": never started")
            continue
        if u["ok"] is False:
            out.append(tag + ": failed")
        clips = [c for c in u["clips"] if c not in ("Walk", "Run")]
        if u["clips"] and not clips:
            out.append(tag + ": only the walk clip plays")
        if u["face_deg"] != -1 and abs(u["face_deg"]) > 60 and not any(c.startswith(SEATED) for c in clips):
            out.append(tag + ": faces %d degrees away from it" % u["face_deg"])
        if u["dist"] > 1.6:
            out.append(tag + ": used from %.1f m away" % u["dist"])
    if r.get("slots", 1) > 1 and r.get("private"):
        out.append("private but %d people can use it at once" % r["slots"])
    return out


def main():
    log, shots = sys.argv[1], sys.argv[2]
    sheets = sys.argv[3] if len(sys.argv) > 3 else ""
    rows = []
    up = {}
    for line in open(log, encoding="utf-8", errors="replace"):
        if line.startswith("BENCH {"):
            rows.append(json.loads(line[6:]))
        elif line.startswith("BENCH_UP "):
            parts = line.strip().split(" ", 2)
            up[parts[1]] = parts[2] if len(parts) > 2 else ""
    for r in rows:
        if r["def"] in up:
            r["upstairs"] = up[r["def"]]
    by_cat = {}
    for r in rows:
        c = category(r)
        by_cat.setdefault(c, []).append(r)
        p = problems(r)
        print("%-16s %-22s %s" % (c, r["def"], "OK" if not p else " | ".join(p)))
    if sheets:
        from PIL import Image, ImageDraw
        os.makedirs(sheets, exist_ok=True)
        tw, th = 480, 270
        for c, rs in by_cat.items():
            cells = []
            for r in sorted(rs, key=lambda x: x["def"]):
                day = os.path.join(shots, r["def"] + "_day.png")
                use = [os.path.join(shots, "%s_use_%s.png" % (r["def"], u["id"])) for u in r.get("use", [])]
                use = [u for u in use if os.path.exists(u)]
                cells.append((r["def"], day if os.path.exists(day) else None, use[0] if use else None))
            cols = 4
            rows_n = (len(cells) + 1) // 2
            sheet = Image.new("RGB", (cols * tw, rows_n * (th + 18)), (20, 24, 30))
            dr = ImageDraw.Draw(sheet)
            for i, (name, a, b) in enumerate(cells):
                x0 = (i % 2) * 2 * tw
                y0 = (i // 2) * (th + 18)
                dr.text((x0 + 6, y0 + 3), name + "   (left: placed, day   right: in use)", fill=(230, 230, 230))
                for k, pth in enumerate((a, b)):
                    if pth:
                        im = Image.open(pth).convert("RGB")
                        w, h = im.size
                        im = im.crop((int(w * 0.25), int(h * 0.2), int(w * 0.75), int(h * 0.8))).resize((tw, th))
                        sheet.paste(im, (x0 + k * tw, y0 + 18))
            sheet.save(os.path.join(sheets, c.replace(" ", "_") + ".jpg"), quality=78)


main()
