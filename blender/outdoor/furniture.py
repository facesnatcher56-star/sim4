"""Street furniture, fences, playground, fountain. Fence segments are 1 m long ALONG X, centred on the tile EDGE line (z=0),
like wall.glb (rotate 90 for Z edges). Corner pieces have arms along +X and +Z from the corner post at the origin."""


@asset("street_lamp", 1, 1, "street lamp 3.8 m; nodes pole, lamp_head (emissive material lamp_glow - toggle energy at night)")
def street_lamp():
    p = Builder()
    p.cyl("metal_dark", 0, 0, 0, 0.16, 0.12, 0.12, 8)
    p.cyl("metal_dark", 0, 0.12, 0, 0.065, 3.5, 0.05, 8)
    p.box("metal_dark", 0, 3.55, -0.2, 0.08, 0.08, 0.5)
    h = Builder()
    h.box("lamp_glow", 0, 3.44, -0.4, 0.3, 0.12, 0.3)
    h.box("metal_dark", 0, 3.54, -0.4, 0.38, 0.06, 0.38)
    return [("pole", p, (0, 0, 0)), ("lamp_head", h, (0, 3.5, -0.4))]


def _post(b, mat, x, z, h, w=0.08):
    b.box(mat, x, h / 2, z, w, h, w)


def _fence(kind, shape):
    """kind: picket | wood | hedge ; shape: straight | corner | gate"""
    b = Builder()
    if kind == "picket":
        m, h, hh = "white", 0.95, 0.8
    elif kind == "wood":
        m, h, hh = "wood", 1.6, 1.45
    else:
        m, h = "hedge", 1.1
    arms = {"straight": [(0, 1.0, "x")], "corner": [(0.25, 0.5, "x"), (0.25, 0.5, "z")], "gate": [(-0.375, 0.25, "x"), (0.375, 0.25, "x")]}[shape]

    def seg(c, length, ax):
        # c = centre offset along the arm axis
        if kind == "hedge":
            if ax == "x":
                b.box(m, c, h / 2, 0, length, h, 0.55) if shape != "corner" else b.box(m, c + 0.0, h / 2, 0, length + 0.0, h, 0.55)
            else:
                b.box(m, 0, h / 2, c, 0.55, h, length)
            return
        n = max(2, int(round(length / 0.13)))
        for i in range(n):
            o = c - length / 2 + (i + 0.5) * length / n
            if kind == "picket":
                hy = hh * 0.5 + 0.1
                (b.box(m, o, hy, 0, 0.07, hh, 0.03) if ax == "x" else b.box(m, 0, hy, o, 0.03, hh, 0.07))
            else:
                (b.box(m, o, h / 2, 0, length / n * 0.96, h, 0.05) if ax == "x" else b.box(m, 0, h / 2, o, 0.05, h, length / n * 0.96))
        for ry in ((0.28, 0.65) if kind == "picket" else (0.35, 1.2)):
            (b.box("wood_dark" if kind == "wood" else m, c, ry, 0.0, length, 0.06, 0.06) if ax == "x" else b.box("wood_dark" if kind == "wood" else m, 0, ry, c, 0.06, 0.06, length))

    for c, ln, ax in arms:
        seg(c, ln, ax)
    pm = "wood_dark" if kind != "hedge" else m
    if kind != "hedge":
        if shape == "straight":
            _post(b, pm, -0.5, 0, h + 0.05, 0.1); _post(b, pm, 0.5, 0, h + 0.05, 0.1)
        elif shape == "corner":
            _post(b, pm, 0, 0, h + 0.08, 0.12)
            _post(b, pm, 0.5, 0, h + 0.05, 0.1); _post(b, pm, 0, 0.5, h + 0.05, 0.1)
        else:
            _post(b, pm, -0.5, 0, h + 0.1, 0.12); _post(b, pm, 0.5, 0, h + 0.1, 0.12)
    parts = [("fence", b, (0, 0, 0))]
    if shape == "gate":
        g = Builder()
        gw = 0.84
        g.box(m if kind != "hedge" else "wood", 0, 0.3, 0, gw, 0.06, 0.05)
        g.box(m if kind != "hedge" else "wood", 0, hh * 0.9 if kind != "hedge" else 0.8, 0, gw, 0.06, 0.05)
        n = 6
        for i in range(n):
            g.box(m if kind != "hedge" else "wood", -gw / 2 + 0.07 + i * (gw - 0.14) / (n - 1), (0.5 if kind != "hedge" else 0.45), 0, 0.06, (hh if kind != "hedge" else 0.9) * 0.8, 0.04)
        parts.append(("gate_leaf", g, (-0.42, 0, 0)))
        if kind == "hedge":
            b.box("hedge", 0, 1.0, 0, 1.0, 0.25, 0.55)           # hedge arch lintel over the gate
    return parts


for _k in ("picket", "wood", "hedge"):
    for _s in ("straight", "corner", "gate"):
        _desc = "%s %s, 1 m along X on the tile edge" % (_k, _s) + ("; corner arms +X and +Z" if _s == "corner" else "") + \
                ("; node gate_leaf hinge at x=-0.42 (rotate about Y to open)" if _s == "gate" else "")
        asset("fence_%s_%s" % (_k, _s), 1, 0.6 if _k == "hedge" else 0.15, _desc)((lambda k=_k, s=_s: (lambda: _fence(k, s)))())


@asset("mailbox_street", 1, 1, "kerb-side mailbox on a post, slot/flag faces -Z; node flag (rotate about X to raise)")
def mailbox_street():
    b = Builder()
    b.box("wood_dark", 0, 0.5, 0, 0.1, 1.0, 0.1)
    b.box("steel", 0, 1.1, 0, 0.32, 0.26, 0.5)
    b.box("fabric_blue", 0, 1.26, 0, 0.3, 0.1, 0.48)
    b.box("black", 0, 1.08, -0.26, 0.2, 0.14, 0.02)
    f = Builder()
    f.box("red_paint", 0.2, 1.22, 0.12, 0.03, 0.2, 0.05)
    f.box("red_paint", 0.2, 1.3, 0.12, 0.03, 0.05, 0.12)
    return [("mailbox", b, (0, 0, 0)), ("flag", f, (0.2, 1.14, 0.12))]


@asset("trash_can", 1, 1, "street litter bin, 0.95 m")
def trash_can():
    b = Builder()
    b.cyl("trash_green", 0, 0.0, 0, 0.27, 0.8, 0.3, 10)
    b.cyl("metal_dark", 0, 0.8, 0, 0.31, 0.07, 0.3, 10)
    b.cyl("black", 0, 0.87, 0, 0.12, 0.06, 0.1, 8)
    for a in range(0, 360, 90):
        b.box("metal_dark", 0.28 * math.cos(math.radians(a)), 0.4, 0.28 * math.sin(math.radians(a)), 0.03, 0.8, 0.03)
    return [("trash_can", b, (0, 0, 0))]


@asset("bench_street", 2, 1, "2x1 street bench, backrest at +Z, sitter faces -Z, seat top y~0.47")
def bench_street():
    b = Builder()
    for x in (-0.8, 0.8):
        b.box("metal_dark", x, 0.22, 0.0, 0.07, 0.44, 0.5)
        b.box("metal_dark", x, 0.65, 0.2, 0.07, 0.7, 0.07)
    for i in range(4):
        b.box("wood", 0, 0.45, -0.18 + i * 0.12, 1.8, 0.04, 0.1)
    for i in range(3):
        b.box("wood", 0, 0.62 + i * 0.13, 0.22, 1.8, 0.09, 0.04)
    return [("bench_street", b, (0, 0, 0))]


@asset("picnic_table", 2, 2, "2x2 picnic table with two benches (long axis X)")
def picnic_table():
    b = Builder()
    for i in range(4):
        b.box("wood", 0, 0.76, -0.33 + i * 0.22, 1.9, 0.05, 0.2)
    for sz in (-1, 1):
        for i in range(2):
            b.box("wood_light", 0, 0.44, sz * (0.65 + 0.1 * (i - 0.5) * 2 * 0.5 + 0.1 * i) , 1.9, 0.05, 0.14)
        for sx in (-1, 1):
            rbox(b, "wood_dark", sx * 0.75, 0.38, sz * 0.4, 0.07, 0.95, 0.07, rx=sz * 20)
    for sx in (-1, 1):
        b.box("wood_dark", sx * 0.75, 0.2, 0.0, 0.07, 0.07, 1.5)
    return [("picnic_table", b, (0, 0, 0))]


@asset("bus_stop", 3, 2, "3x2 bus shelter: roof, glass back (+Z), bench, timetable sign pole; open front -Z")
def bus_stop():
    b = Builder()
    for x in (-1.3, 1.3):
        b.box("metal_dark", x, 1.25, 0.8, 0.08, 2.5, 0.08)
        b.box("metal_dark", x, 1.25, -0.5, 0.08, 2.5, 0.08)
    b.box("teal", 0, 2.55, 0.15, 3.0, 0.1, 1.5)
    b.box("glass", 0, 1.3, 0.8, 2.5, 1.9, 0.04)
    b.box("glass", -1.3, 1.3, 0.15, 0.04, 1.9, 1.2)
    b.box("wood", 0, 0.46, 0.55, 2.2, 0.06, 0.38)
    b.box("metal_dark", -0.9, 0.22, 0.55, 0.06, 0.44, 0.3); b.box("metal_dark", 0.9, 0.22, 0.55, 0.06, 0.44, 0.3)
    b.box("yellow_safety", 1.65, 1.6, -0.5, 0.5, 0.5, 0.05)
    b.box("metal_dark", 1.65, 0.8, -0.5, 0.06, 1.6, 0.06)
    return [("bus_stop", b, (0, 0, 0))]


@asset("swing_set", 3, 2, "3x2 swing set; nodes frame, swing_l, swing_r (pivot at top bar: rotate about X; seats hang toward the viewer on -Z)")
def swing_set():
    f = Builder()
    for sx in (-1, 1):
        rbox(f, "playground_r", sx * 1.35, 1.1, -0.45, 0.1, 2.35, 0.1, rx=-12)
        rbox(f, "playground_r", sx * 1.35, 1.1, 0.45, 0.1, 2.35, 0.1, rx=12)
    f.box("playground_r", 0, 2.2, 0, 2.8, 0.12, 0.12)
    parts = [("frame", f, (0, 0, 0))]
    for nm, x in (("swing_l", -0.55), ("swing_r", 0.55)):
        s = Builder()
        s.box("metal_dark", x - 0.2, 1.2, 0, 0.02, 2.0, 0.02); s.box("metal_dark", x + 0.2, 1.2, 0, 0.02, 2.0, 0.02)
        s.box("playground_y" if x < 0 else "playground_b", x, 0.2, 0, 0.5, 0.05, 0.25)
        parts.append((nm, s, (x, 2.2, 0)))
    return parts


@asset("slide", 1, 3, "1x3 playground slide: ladder + platform at +Z, chute down to -Z")
def slide():
    b = Builder()
    for sx in (-1, 1):
        b.box("playground_b", sx * 0.4, 0.7, 1.0, 0.07, 1.4, 0.07)
        rbox(b, "playground_b", sx * 0.4, 0.55, 1.35, 0.06, 1.2, 0.06, rx=-20)
    b.box("wood", 0, 1.2, 1.0, 0.85, 0.06, 0.8)
    for y in (0.3, 0.6, 0.9):
        b.box("playground_y", 0, y, 1.5 - y * 0.2 + 0.1, 0.8, 0.04, 0.05)
    rbox(b, "playground_r", 0, 0.66, -0.4, 0.7, 0.05, 1.9, rx=-25)
    for sx in (-1, 1):
        rbox(b, "playground_r", sx * 0.37, 0.72, -0.4, 0.05, 0.12, 1.9, rx=-25)
    return [("slide", b, (0, 0, 0))]


@asset("sandbox", 2, 2, "2x2 sandbox with timber border, sand and a bucket")
def sandbox():
    b = Builder()
    b.box("sand_box", 0, 0.07, 0, 1.8, 0.14, 1.8)
    for sx in (-1, 1):
        b.box("wood", sx * 0.95, 0.15, 0, 0.1, 0.3, 2.0)
        b.box("wood", 0, 0.15, sx * 0.95, 2.0, 0.3, 0.1)
    b.cyl("playground_r", -0.3, 0.14, 0.2, 0.1, 0.14, 0.08, 8)
    b.box("playground_b", 0.35, 0.17, -0.25, 0.16, 0.06, 0.2)
    return [("sandbox", b, (0, 0, 0))]


@asset("fountain", 3, 3, "3x3 stone fountain: basin, tier, spout; node water is translucent")
def fountain():
    b = Builder()
    b.cyl("marble", 0, 0, 0, 1.45, 0.4, 1.4, 14)
    b.cyl("stone", 0, 0.4, 0, 1.2, 0.08, 1.2, 14)
    b.cyl("marble", 0, 0.0, 0, 0.35, 1.0, 0.25, 8)
    b.cyl("marble", 0, 1.0, 0, 0.75, 0.15, 0.7, 12)
    b.cyl("marble", 0, 1.15, 0, 0.2, 0.55, 0.12, 8)
    w = Builder()
    w.cyl("water", 0, 0.36, 0, 1.18, 0.04, 1.18, 14)
    w.cyl("water", 0, 1.15, 0, 0.62, 0.03, 0.62, 12)
    tube(w, "water", (0, 1.7, 0), (0, 1.1, 0), 0.04, 6, 0.1)
    return [("fountain", b, (0, 0, 0)), ("water", w, (0, 0, 0))]


@asset("sign_blank", 1, 1, "generic blank street sign on a post; node sign_face (replace its material/texture)")
def sign_blank():
    b = Builder()
    b.box("metal_dark", 0, 1.1, 0, 0.06, 2.2, 0.06)
    f = Builder()
    f.box("green_paint", 0, 2.0, -0.04, 0.8, 0.4, 0.03)
    f.box("sign_face", 0, 2.0, -0.062, 0.7, 0.3, 0.012)
    return [("post", b, (0, 0, 0)), ("sign_face", f, (0, 2.0, -0.04))]


@asset("fire_hydrant", 1, 1, "fire hydrant 0.75 m")
def fire_hydrant():
    b = Builder()
    b.cyl("hydrant_red", 0, 0, 0, 0.14, 0.12, 0.14, 8)
    b.cyl("hydrant_red", 0, 0.1, 0, 0.11, 0.5, 0.1, 8)
    b.sphere("hydrant_red", 0, 0.65, 0, 0.12, 3, 8)
    for sx in (-1, 1):
        tube(b, "steel", (sx * 0.1, 0.42, 0), (sx * 0.2, 0.42, 0), 0.05, 6)
    tube(b, "steel", (0, 0.42, -0.1), (0, 0.42, -0.19), 0.06, 6)
    return [("fire_hydrant", b, (0, 0, 0))]
