"""Building shells for non-player lots (viewed from outside). Footprint = the template's WALL bounding box
(small 10x7, medium 14x11, large 22x14, venues 22x14, townhouse 7x10 (no template)). Nodes: `body` (materials wall, trim, glass,
door_paint, base, awning...) and `roof` (material roof [+ chimney]) - hide `roof` when a player Folk is inside.
Front (door side) = -Z; the lot templates' door side is south, so the game rotates the shell 180 deg about Y (door x is mirrored)."""

PALETTE.update({
    "metal_dark": ((0.25, 0.27, 0.30), 0.4, 0.8),
    "teal":       ((0.18, 0.52, 0.58), 0.6, 0.0),
    "red_paint":  ((0.78, 0.14, 0.12), 0.5, 0.0),
    "yellow_safety": ((0.96, 0.80, 0.10), 0.6, 0.0),
    "brick":      ((0.58, 0.28, 0.20), 0.95, 0.0),
    "wall":       ((0.93, 0.88, 0.76), 0.95, 0.0),
    "coffee":     ((0.26, 0.14, 0.08), 0.5, 0.0),
    "brass":      ((0.80, 0.60, 0.22), 0.4, 0.7),
    "crop_green": ((0.30, 0.66, 0.26), 0.9, 0.0),
    "crop_orange": ((0.93, 0.50, 0.12), 0.8, 0.0),
})
OV = 0.35                      # eave overhang
DOOR_X = 0.5                   # door centre on the front face (model x)


def _win(b, side, along, y, w=1.1, h=1.2, W=0, D=0):
    """Window on a face; side N=-Z front, S=+Z, W=-X, E=+X; `along` = coordinate along the wall."""
    if side in "NS":
        z = (-D / 2 - 0.02) if side == "N" else (D / 2 + 0.02)
        zg = z + (-0.03 if side == "N" else 0.03)
        b.box("trim", along, y, z, w + 0.2, h + 0.2, 0.06)
        b.box("glass", along, y, zg, w, h, 0.03)
        b.box("trim", along, y - h / 2 - 0.12, z + (-0.04 if side == "N" else 0.04), w + 0.35, 0.07, 0.14)
    else:
        x = (-W / 2 - 0.02) if side == "W" else (W / 2 + 0.02)
        xg = x + (-0.03 if side == "W" else 0.03)
        b.box("trim", x, y, along, 0.06, h + 0.2, w + 0.2)
        b.box("glass", xg, y, along, 0.03, h, w)
        b.box("trim", x + (-0.04 if side == "W" else 0.04), y - h / 2 - 0.12, along, 0.14, 0.07, w + 0.35)


def _door(b, W, D, x=DOOR_X, w=1.0, h=2.1, step=True):
    z = -D / 2
    b.box("trim", x, (h + 0.2) / 2, z - 0.03, w + 0.3, h + 0.2, 0.08)
    b.box("door_paint", x, h / 2, z - 0.06, w, h, 0.08)
    b.box("brass", x + w * 0.35, h * 0.48, z - 0.12, 0.07, 0.07, 0.05) if "brass" in PALETTE else None
    if step:
        b.box("base", x, 0.05, z - 0.4, w + 0.7, 0.1, 0.7)


def _box(W, D, H, floors=1):
    b = Builder()
    b.box("base", 0, 0.1, 0, W + 0.1, 0.2, D + 0.1)
    b.box("wall", 0, 0.2 + (H - 0.2) / 2, 0, W, H - 0.2, D)
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box("trim", sx * (W / 2 - 0.03), H / 2, sz * (D / 2 - 0.03), 0.2, H, 0.2)
    for f in range(1, floors):
        b.box("trim", 0, 2.6 * f, 0, W + 0.12, 0.12, D + 0.12)
    b.box("trim", 0, H - 0.05, 0, W + 0.14, 0.12, D + 0.14)     # cornice
    return b


def _rhythm(b, W, D, H, floors, front_xs, side_zs, back_xs):
    for f in range(floors):
        y = 1.55 + 2.6 * f
        for x in front_xs:
            if f == 0 and abs(x - DOOR_X) < 1.3:
                continue
            _win(b, "N", x, y, W=W, D=D)
        for x in back_xs:
            _win(b, "S", x, y, W=W, D=D)
        for z in side_zs:
            _win(b, "W", z, y, W=W, D=D)
            _win(b, "E", z, y, W=W, D=D)


def _chimney(r, x, z, y0, h=1.6):
    r.box("chimney", x, y0 + h / 2, z, 0.6, h, 0.6)
    r.box("base", x, y0 + h + 0.04, z, 0.74, 0.1, 0.74)


def _gable_roof(r, W, D, H, rh, axis="x"):
    gable(r, "roof", 0, H, 0, W + 2 * OV, D + 2 * OV, rh, axis)


def _hip_roof(r, W, D, H, rh):
    fw, fd = W + 2 * OV, D + 2 * OV
    if fw >= fd:
        frustum(r, "roof", 0, H, 0, fw, fd, max(0.3, fw - fd), 0.3, rh)
    else:
        frustum(r, "roof", 0, H, 0, fw, fd, 0.3, max(0.3, fd - fw), rh)


def _flat_roof(r, W, D, H, parapet=0.5):
    r.box("roof", 0, H + 0.1, 0, W + 0.2, 0.2, D + 0.2)
    for sz in (-1, 1):
        r.box("trim", 0, H + 0.2 + parapet / 2 - 0.1, sz * (D / 2 + 0.05), W + 0.3, parapet, 0.18)
    for sx in (-1, 1):
        r.box("trim", sx * (W / 2 + 0.05), H + 0.2 + parapet / 2 - 0.1, 0, 0.18, parapet, D + 0.1)


def _awning(b, x, y, z, w, d=1.1, tilt=22):
    n = max(2, int(w / 0.5))
    for i in range(n):
        rbox(b, "awning" if i % 2 == 0 else "white", x - w / 2 + (i + 0.5) * w / n, y, z - d / 2 * math.cos(math.radians(tilt)),
             w / n, 0.05, d, rx=tilt)


# ---- the nine shells -----------------------------------------------------------------------------------
def house_small():
    W, D, H = 10, 7, 2.6
    b = _box(W, D, H); r = Builder()
    _door(b, W, D)
    _rhythm(b, W, D, H, 1, [-3.2, 3.6], [-1.5, 1.5], [-3, 0, 3])
    _gable_roof(r, W, D, H, 2.3, "x"); _chimney(r, -2.6, 0.6, H + 1.0)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def house_medium():
    W, D, H = 14, 11, 2.6
    b = _box(W, D, H); r = Builder()
    _door(b, W, D)
    _rhythm(b, W, D, H, 1, [-5, -2.4, 3, 5.4], [-3, 0, 3], [-5, -1.5, 2, 5])
    b.box("wood_dark", DOOR_X, 2.55, -D / 2 - 0.7, 2.6, 0.12, 1.5)                  # porch roof
    for sx in (-1, 1):
        b.box("trim", DOOR_X + sx * 1.15, 1.25, -D / 2 - 1.35, 0.14, 2.5, 0.14)
    _hip_roof(r, W, D, H, 2.8); _chimney(r, 3.5, 1.5, H + 1.2)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def house_large():
    W, D, H = 22, 14, 2.6
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.2)
    _rhythm(b, W, D, H, 1, [-9, -6, -3, 3.8, 7, 10], [-4.5, -1.5, 1.5, 4.5], [-9, -5, -1, 3, 7])
    b.box("wood_dark", DOOR_X, 2.55, -D / 2 - 0.8, 3.2, 0.12, 1.7)
    for sx in (-1, 1):
        b.box("trim", DOOR_X + sx * 1.5, 1.25, -D / 2 - 1.55, 0.18, 2.5, 0.18)
    gable(r, "roof", 0, H, 0, W + 2 * OV, D + 2 * OV, 3.8, "x")                   # main ridge along X
    gable(r, "roof", -5, H + 0.3, -1.5, 7.2, D + 2 * OV - 3, 3.4, "z")             # cross gable
    gable(r, "roof", 6.5, H + 0.3, 0.5, 6.2, D + 2 * OV - 3, 3.0, "z")
    _chimney(r, -8, 2.0, H + 1.4, 2.4); _chimney(r, 9, 2.0, H + 1.2, 2.2)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def townhouse():
    W, D, H = 7, 10, 5.2
    b = _box(W, D, H, 2); r = Builder()
    _door(b, W, D)
    _rhythm(b, W, D, H, 2, [-2.0, 2.4], [-3, 0, 3], [-2, 2])
    b.box("wood_dark", DOOR_X, 2.45, -D / 2 - 0.55, 2.0, 0.1, 1.1)
    gable(r, "roof", 0, H, 0, W + 2 * OV, D + 2 * OV, 2.4, "z")
    _chimney(r, -2.0, 2.5, H + 1.0)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def cafe():
    W, D, H = 22, 14, 3.4
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.1, h=2.2)
    for x in (-7.5, -3.5, 3.5, 7.5):
        _win(b, "N", x, 1.4, 2.4, 1.6, W, D)
        _awning(b, x, 2.65, -D / 2 - 0.05, 2.9, 1.0, 20)
    b.box("wood_dark", DOOR_X, 3.0, -D / 2 - 0.12, 4.2, 0.5, 0.12)               # sign board
    b.box("coffee", DOOR_X, 3.0, -D / 2 - 0.2, 3.8, 0.34, 0.04)
    _rhythm(b, W, D, H, 1, [], [-4, 0, 4], [-8, -3, 3, 8])
    _flat_roof(r, W, D, H, 0.4)
    r.box("metal_dark", 6, H + 0.8, 3, 1.4, 0.8, 1.4)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def gym():
    W, D, H = 22, 14, 4.2
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.4, h=2.3)
    b.box("red_paint", 0, 3.6, -D / 2 - 0.04, W + 0.2, 0.7, 0.1)                   # stripe band
    for x in (-8, -5.5, -3, 3.8, 6.3, 8.8):
        _win(b, "N", x, 2.6, 1.8, 0.9, W, D)
    b.box("black", DOOR_X, 3.62, -D / 2 - 0.12, 3.6, 0.45, 0.06)
    _rhythm(b, W, D, H, 1, [], [-4, 0, 4], [-8, -3, 3, 8])
    _flat_roof(r, W, D, H, 0.4)
    for x in (-5, 0, 5):
        r.box("steel", x, H + 0.65, 3.0, 1.6, 0.9, 1.6)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def library():
    W, D, H = 22, 14, 4.4
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.4, h=2.6, step=False)
    for k in range(3):                                                               # steps
        b.box("base", 0, 0.04 + 0.07 * k, -D / 2 - 1.5 + 0.3 * k, 6.0, 0.08 + 0.07 * k, 0.3)
    for x in (-3.6, -1.2, 1.2, 3.6):                                                 # columns
        b.cyl("marble", x, 0.2, -D / 2 - 1.0, 0.26, H - 0.6, 0.23, 10)
    b.box("marble", 0, H - 0.15, -D / 2 - 0.5, 9.2, 0.45, 1.6)                       # entablature
    hull(b, "marble", [(-4.6, H + 0.07, -D / 2 - 1.3), (4.6, H + 0.07, -D / 2 - 1.3), (-4.6, H + 0.07, -D / 2 + 0.1), (4.6, H + 0.07, -D / 2 + 0.1),
                       (0, H + 1.5, -D / 2 - 1.3), (0, H + 1.5, -D / 2 + 0.1)])         # pediment
    for x in (-8.5, -6.2, 6.8, 9.0):
        _win(b, "N", x, 2.4, 1.0, 2.0, W, D)
    _rhythm(b, W, D, H, 1, [], [-4, 0, 4], [-8, -3, 3, 8])
    b.box("trim", 0, H + 0.1, 0, W + 0.4, 0.3, D + 0.4)
    _hip_roof(r, W - 0.2, D - 0.2, H + 0.25, 2.6)
    r.box("roof", 0, H + 3.4, 0, 3.6, 0.9, 3.6)                                      # lantern
    frustum(r, "roof", 0, H + 4.3, 0, 3.9, 3.9, 0.3, 0.3, 1.4)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def market():
    W, D, H = 22, 14, 3.6
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.6, h=2.3)
    for x in (-8, -4.5, 3.6, 7, 9.5):
        _win(b, "N", x, 1.3, 2.4, 1.5, W, D)
    _awning(b, 0, 2.8, -D / 2 - 0.05, 20.0, 1.6, 22)
    b.box("yellow_safety", 0, 3.35, -D / 2 - 0.1, 8.0, 0.55, 0.1)
    for i in range(3):                                                               # produce crates
        b.box("wood_light", -7.5 + i * 1.1, 0.25, -D / 2 - 0.7, 0.9, 0.45, 0.6)
        b.box(("flower_r", "crop_orange", "crop_green")[i], -7.5 + i * 1.1, 0.5, -D / 2 - 0.7, 0.8, 0.1, 0.5) if "crop_orange" in PALETTE else None
    _rhythm(b, W, D, H, 1, [], [-4, 0, 4], [-8, -3, 3, 8])
    _flat_roof(r, W, D, H, 0.45)
    r.box("steel", -4, H + 0.7, 3.5, 2.4, 0.7, 1.6)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def office():
    W, D, H = 22, 14, 7.8
    b = _box(W, D, H, 3); r = Builder()
    _door(b, W, D, w=1.6, h=2.4, step=False)
    xs = [-9.0 + 2.0 * i for i in range(10)]
    for f in range(3):
        y = 1.8 + 2.6 * f
        for x in xs:
            if f == 0 and abs(x - DOOR_X) < 1.9:
                continue
            _win(b, "N", x, y, 1.4, 1.5, W, D)
            _win(b, "S", x, y, 1.4, 1.5, W, D)
        for z in (-4.5, -1.5, 1.5, 4.5):
            _win(b, "W", z, y, 1.4, 1.5, W, D); _win(b, "E", z, y, 1.4, 1.5, W, D)
    b.box("glass", DOOR_X, 3.0, -D / 2 - 0.06, 3.0, 0.5, 0.05)
    _flat_roof(r, W, D, H, 0.5)
    r.box("steel", -6, H + 0.9, 2, 3.0, 1.0, 2.0); r.box("steel", 5, H + 0.8, -2, 2.0, 0.8, 2.0)
    r.cyl("metal_dark", 8, H + 0.2, 3, 0.8, 1.4, 0.7, 8)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


def school():
    W, D, H = 22, 14, 3.4
    b = _box(W, D, H); r = Builder()
    _door(b, W, D, w=1.6, h=2.4)
    b.box("trim", DOOR_X, 3.0, -D / 2 - 0.1, 3.6, 0.9, 0.12)
    b.box("playground_b", DOOR_X, 3.0, -D / 2 - 0.18, 3.2, 0.6, 0.04)
    for x in (-9, -6.5, -4, -1.5, 3.5, 6, 8.5, 10.5):
        _win(b, "N", x, 1.8, 1.4, 1.5, W, D)
    _rhythm(b, W, D, H, 1, [], [-4, 0, 4], [-8, -4, 0, 4, 8])
    _gable_roof(r, W, D, H, 2.6, "x")
    r.box("trim", DOOR_X, H + 3.1, 0, 2.2, 3.2, 2.2)                                 # bell tower
    r.box("clock", DOOR_X, H + 3.6, -1.12, 1.0, 1.0, 0.05) if "clock" in PALETTE else r.box("sign_face", DOOR_X, H + 3.6, -1.12, 1.0, 1.0, 0.05)
    frustum(r, "roof", DOOR_X, H + 4.7, 0, 2.6, 2.6, 0.2, 0.2, 1.4)
    return [("body", b, (0, 0, 0)), ("roof", r, (0, 0, 0))]


HOUSE_VARIANTS = {
    "a": {"wall": ((0.93, 0.87, 0.72), .95, 0), "roof": ((0.62, 0.26, 0.20), .9, 0), "door_paint": ((0.25, 0.35, 0.60), .7, 0)},
    "b": {"wall": ((0.66, 0.78, 0.90), .95, 0), "roof": ((0.30, 0.33, 0.40), .9, 0), "door_paint": ((0.80, 0.25, 0.22), .7, 0)},
    "c": {"wall": ((0.72, 0.82, 0.68), .95, 0), "roof": ((0.74, 0.40, 0.22), .9, 0), "door_paint": ((0.30, 0.20, 0.35), .7, 0)},
}
VENUE_VARIANTS = {
    "a": {"wall": ((0.90, 0.80, 0.62), .95, 0), "roof": ((0.38, 0.40, 0.45), .9, 0), "door_paint": ((0.20, 0.38, 0.55), .7, 0)},
    "b": {"wall": ((0.84, 0.50, 0.40), .95, 0), "roof": ((0.30, 0.30, 0.34), .9, 0), "door_paint": ((0.15, 0.28, 0.20), .7, 0)},
}
for _id, _fn, _w, _d, _tpl, _vars in (
        ("house_small", house_small, 10, 7, "small", HOUSE_VARIANTS), ("house_medium", house_medium, 14, 11, "medium", HOUSE_VARIANTS),
        ("house_large", house_large, 22, 14, "large", HOUSE_VARIANTS), ("townhouse", townhouse, 7, 10, None, HOUSE_VARIANTS),
        ("cafe", cafe, 22, 14, "cafe", VENUE_VARIANTS), ("gym", gym, 22, 14, "gym", VENUE_VARIANTS),
        ("library", library, 22, 14, "library", VENUE_VARIANTS), ("market", market, 22, 14, "market", VENUE_VARIANTS),
        ("office", office, 22, 14, "office", VENUE_VARIANTS), ("school", school, 22, 14, "school", VENUE_VARIANTS)):
    for _v, _pal in _vars.items():
        asset("%s_%s" % (_id, _v), _w, _d, "%s shell %dx%d m (template %s); nodes body, roof; door on -Z at x=+0.5" % (_id, _w, _d, _tpl),
              pal=_pal, entry={"side": "-Z", "door_x": DOOR_X, "template": _tpl})(_fn)
