"""Nature: 3 tree species x 2 sizes, bushes, flower bed, rocks, grass tufts, pond tile set.
Trees: nodes `trunk` (material bark) and `leaves` (material `leaves`; tint by season) [+ `blossom`]. Footprint = trunk tile.
"""

_LEAF = {"oak": ((0.40, 0.70, 0.30), 0.95, 0.0), "pine": ((0.20, 0.48, 0.32), 0.95, 0.0),
         "orn": ((0.52, 0.76, 0.36), 0.95, 0.0), "bush": ((0.30, 0.62, 0.28), 0.95, 0.0)}


def oak(s):
    t = Builder()
    tube(t, "bark", (0, 0, 0), (0, 2.5 * s, 0), 0.2 * s, 7, 0.14 * s)
    tube(t, "bark", (0, 1.8 * s, 0), (0.6 * s, 2.7 * s, 0.1 * s), 0.07 * s, 5)
    l = Builder()
    for x, y, z, r in ((0, 3.9, 0, 1.75), (1.05, 3.3, 0.3, 1.2), (-0.95, 3.35, -0.35, 1.2), (0.1, 3.4, 1.0, 1.1), (-0.2, 3.5, -1.0, 1.1), (0.2, 4.7, 0.1, 1.0)):
        l.sphere("leaves", x * s, y * s, z * s, r * s, 4, 7)
    return [("trunk", t, (0, 0, 0)), ("leaves", l, (0, 0, 0))]


def pine(s):
    t = Builder()
    tube(t, "bark", (0, 0, 0), (0, 1.4 * s, 0), 0.17 * s, 6, 0.12 * s)
    l = Builder()
    for y0, r, h in ((0.9, 1.45, 1.9), (2.0, 1.15, 1.7), (3.1, 0.85, 1.6), (4.1, 0.55, 1.5)):
        l.cyl("leaves", 0, y0 * s, 0, r * s, h * s, 0.0, 8)
    return [("trunk", t, (0, 0, 0)), ("leaves", l, (0, 0, 0))]


def ornamental(s):
    t = Builder()
    tube(t, "bark", (0, 0, 0), (0, 1.5 * s, 0), 0.09 * s, 6, 0.06 * s)
    l = Builder()
    l.sphere("leaves", 0, 2.1 * s, 0, 0.95 * s, 4, 7)
    l.sphere("leaves", 0.5 * s, 1.85 * s, 0.2 * s, 0.6 * s, 3, 6)
    l.sphere("leaves", -0.45 * s, 1.9 * s, -0.25 * s, 0.6 * s, 3, 6)
    f = Builder()
    for x, y, z in ((0.5, 2.7, 0.3), (-0.5, 2.5, 0.4), (0.1, 2.9, -0.3), (0.8, 2.1, -0.2), (-0.8, 2.2, -0.3), (0.0, 2.2, 0.85), (-0.2, 1.7, -0.75), (0.6, 1.6, 0.6)):
        f.box("blossom", x * s, y * s, z * s, 0.22 * s, 0.22 * s, 0.22 * s)
    return [("trunk", t, (0, 0, 0)), ("leaves", l, (0, 0, 0)), ("blossom", f, (0, 0, 0))]


for _nm, _fn, _big, _small, _lc in (("oak", oak, 1.0, 0.55, _LEAF["oak"]), ("pine", pine, 1.0, 0.55, _LEAF["pine"]),
                                   ("ornamental", ornamental, 1.15, 0.7, _LEAF["orn"])):
    asset("tree_%s_l" % _nm, 1, 1, "%s tree, large; nodes trunk, leaves (tint)%s" % (_nm, ", blossom" if _nm == "ornamental" else ""),
          pal={"leaves": _lc})((lambda f=_fn, s=_big: (lambda: f(s)))())
    asset("tree_%s_s" % _nm, 1, 1, "%s tree, small; nodes trunk, leaves (tint)%s" % (_nm, ", blossom" if _nm == "ornamental" else ""),
          pal={"leaves": _lc})((lambda f=_fn, s=_small: (lambda: f(s)))())


@asset("bush_round", 1, 1, "round shrub, node leaves", pal={"leaves": _LEAF["bush"]})
def bush_round():
    l = Builder()
    l.sphere("leaves", 0, 0.42, 0, 0.42, 4, 7)
    l.sphere("leaves", 0.3, 0.3, 0.1, 0.3, 3, 6)
    l.sphere("leaves", -0.28, 0.3, -0.1, 0.32, 3, 6)
    s = Builder(); s.box("bark", 0, 0.05, 0, 0.12, 0.1, 0.12)
    return [("stem", s, (0, 0, 0)), ("leaves", l, (0, 0, 0))]


@asset("bush_flowering", 1, 1, "shrub with flowers; nodes leaves, flowers", pal={"leaves": _LEAF["bush"]})
def bush_flowering():
    l = Builder()
    l.sphere("leaves", 0, 0.4, 0, 0.4, 4, 7)
    l.sphere("leaves", 0.28, 0.3, 0.12, 0.28, 3, 6)
    l.sphere("leaves", -0.26, 0.3, -0.1, 0.3, 3, 6)
    f = Builder()
    for i, (x, y, z) in enumerate(((0.1, 0.78, 0.1), (-0.25, 0.6, 0.3), (0.35, 0.55, -0.1), (-0.15, 0.7, -0.3), (0.3, 0.5, 0.35), (-0.4, 0.45, -0.1))):
        f.box(("flower_r", "flower_y", "flower_p")[i % 3], x, y, z, 0.12, 0.12, 0.12)
    return [("leaves", l, (0, 0, 0)), ("flowers", f, (0, 0, 0))]


@asset("flower_bed", 2, 1, "2x1 raised flower bed with soil, leaves and flowers (nodes bed, leaves, flowers)", pal={"leaves": _LEAF["bush"]})
def flower_bed():
    bd = Builder()
    bd.box("wood_dark", 0, 0.1, -0.45, 2.0, 0.2, 0.1); bd.box("wood_dark", 0, 0.1, 0.45, 2.0, 0.2, 0.1)
    bd.box("wood_dark", -0.95, 0.1, 0, 0.1, 0.2, 0.8); bd.box("wood_dark", 0.95, 0.1, 0, 0.1, 0.2, 0.8)
    bd.box("soil", 0, 0.1, 0, 1.8, 0.18, 0.8)
    l = Builder(); f = Builder()
    for i in range(7):
        x = -0.8 + i * 0.267
        z = -0.18 if i % 2 == 0 else 0.18
        l.sphere("leaves", x, 0.27, z, 0.15, 3, 5)
        f.sphere(("flower_r", "flower_y", "flower_w", "flower_p")[i % 4], x, 0.44, z, 0.1, 3, 5)
    return [("bed", bd, (0, 0, 0)), ("leaves", l, (0, 0, 0)), ("flowers", f, (0, 0, 0))]


def _rock(b, mat, cx, cz, r, sy, rot):
    import random
    rnd = random.Random(int(abs(cx * 31 + cz * 17 + r * 7) * 100))
    pts = []
    for i in range(7):
        a = rot + i * math.tau / 7
        rr = r * (0.8 + 0.3 * rnd.random())
        pts.append((cx + rr * math.cos(a), 0.0, cz + rr * math.sin(a)))
    for i in range(4):
        a = rot + i * math.tau / 4 + 0.4
        pts.append((cx + 0.5 * r * math.cos(a), r * sy * (0.85 + 0.2 * rnd.random()), cz + 0.5 * r * math.sin(a)))
    hull(b, mat, pts)


@asset("rock_small", 1, 1, "small boulder")
def rock_small():
    b = Builder(); _rock(b, "rock", 0, 0, 0.3, 1.0, 0.3)
    return [("rock_small", b, (0, 0, 0))]


@asset("rock_large", 1, 1, "large boulder with a smaller one beside it")
def rock_large():
    b = Builder(); _rock(b, "rock", 0, 0, 0.55, 1.1, 0.0); _rock(b, "rock_dark", 0.45, 0.3, 0.28, 0.9, 1.0)
    return [("rock_large", b, (0, 0, 0))]


@asset("rock_cluster", 2, 1, "three stones of mixed sizes")
def rock_cluster():
    b = Builder()
    _rock(b, "rock", -0.5, 0.0, 0.38, 0.9, 0.2); _rock(b, "rock_dark", 0.15, -0.1, 0.5, 1.0, 1.1); _rock(b, "rock", 0.65, 0.2, 0.22, 0.9, 2.0)
    return [("rock_cluster", b, (0, 0, 0))]


@asset("grass_tuft", 1, 1, "clump of tall grass blades (lay over ground_grass)")
def grass_tuft():
    b = Builder()
    for i, (x, z, h, lean) in enumerate(((0, 0, 0.32, 0), (0.12, 0.05, 0.26, 10), (-0.1, 0.08, 0.28, -12), (0.05, -0.12, 0.22, 6),
                                          (-0.14, -0.08, 0.2, -8), (0.18, -0.1, 0.18, 14), (-0.02, 0.17, 0.24, 0))):
        tube(b, "grass_blade", (x, 0, z), (x + lean * 0.004, h, z + (i - 3) * 0.01), 0.035, 3, 0.0)
    for (x, z) in ((-0.3, 0.3), (0.3, 0.32), (0.32, -0.3), (-0.32, -0.3)):
        for k in range(3):
            tube(b, "grass_blade", (x + k * 0.04, 0, z), (x + k * 0.05 - 0.02, 0.2 + 0.04 * k, z + 0.02), 0.03, 3, 0.0)
    return [("grass_tuft", b, (0, 0, 0))]


# ---- pond tile set --------------------------------------------------------------------------------------
def _pond(name, land, water):
    b = Builder()
    if land:
        poly_slab(b, "sand", land, -0.05, 0.0)
    w = Builder()
    poly_slab(w, "pond_bed", water, -0.05, -0.036)
    poly_slab(w, "water", water, -0.036, -0.012)
    return [("land", b, (0, 0, 0)), ("water", w, (0, 0, 0))] if land else [("water", w, (0, 0, 0))]


@asset("pond_water", 1, 1, "full water tile (surface y=-0.012, node water is translucent)")
def pond_water():
    parts = _pond("pond_water", None, [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)])
    r = Builder()
    for sx in (-1, 1):
        r.box("sand", sx * 0.485, -0.025, 0, 0.03, 0.05, 1.0)
        r.box("sand", 0, -0.025, sx * 0.485, 1.0, 0.05, 0.03)
    return [("rim", r, (0, 0, 0))] + parts


@asset("pond_edge", 1, 1, "straight shore: sand bank on the -Z side, water on the +Z side. Rotate for other sides")
def pond_edge():
    land = [(-0.5, -0.5), (0.5, -0.5), (0.5, -0.18), (0.25, -0.12), (0.0, -0.2), (-0.25, -0.1), (-0.5, -0.18)]
    water = [(-0.5, -0.18), (-0.25, -0.1), (0.0, -0.2), (0.25, -0.12), (0.5, -0.18), (0.5, 0.5), (-0.5, 0.5)]
    return _pond("pond_edge", land, water)


@asset("pond_corner_out", 1, 1, "convex water corner: water quarter-disc in the +X,+Z corner, sand elsewhere")
def pond_corner_out():
    arc = _arc(0.8, 0.5, 0.5, 180, 270, 8)       # (-0.3, 0.5) -> (0.5, -0.3)
    water = [(0.5, 0.5)] + arc
    land = [(-0.5, -0.5), (0.5, -0.5), (0.5, -0.3)] + arc[::-1][1:-1] + [(-0.3, 0.5), (-0.5, 0.5)]
    return _pond("pond_corner_out", land, water)


@asset("pond_corner_in", 1, 1, "concave water corner: water everywhere except a sand quarter-disc in the -X,-Z corner")
def pond_corner_in():
    arc = _arc(0.8, -0.5, -0.5, 0, 90, 8)        # (0.3, -0.5) -> (-0.5, 0.3)
    land = [(-0.5, -0.5)] + arc
    water = arc[::-1] + [(-0.5, 0.5), (0.5, 0.5), (0.5, -0.5), (0.3, -0.5)]
    water = [(0.3, -0.5)] + arc[1:] + [(-0.5, 0.5), (0.5, 0.5), (0.5, -0.5)]
    return _pond("pond_corner_in", land, water)
