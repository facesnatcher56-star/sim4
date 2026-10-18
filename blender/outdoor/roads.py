"""Road, sidewalk, curb and ground tiles. All 1x1 m, top surface at y=0 (0.05 thick) like floor_tile.glb.
Orientation of an un-rotated tile: a line "on the +X edge" runs along Z; "stop/curb at -Z" is the -Z edge (the front)."""


def _tile(b, mat="asphalt"):
    b.box(mat, 0, -0.025, 0, 1.0, 0.05, 1.0)


def _paint(b, mat, cx, cz, sx, sz, h=0.006):
    b.box(mat, cx, h / 2, cz, sx, h, sz)


def poly_slab(b, mat, pts, y0, y1):
    """Extruded 2D polygon given as (x, z) Godot points -> slab from y0 to y1."""
    bm = b.bm
    top = [bm.verts.new(Builder._b(x, y1, z)) for x, z in pts]
    bot = [bm.verts.new(Builder._b(x, y0, z)) for x, z in pts]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    b._finish(top + bot, mat)


def _arc(r, cx, cz, a0, a1, n=8):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


@asset("road_asphalt", 1, 1, "plain asphalt tile with faint patches; the field of every road")
def road_asphalt():
    b = Builder(); _tile(b)
    _paint(b, "asphalt2", -0.2, 0.25, 0.45, 0.3, 0.003)
    _paint(b, "asphalt2", 0.25, -0.28, 0.3, 0.25, 0.003)
    return [("road_asphalt", b, (0, 0, 0))]


@asset("road_line", 1, 1, "solid yellow centre line along Z on the +X edge (rotate 180 for the -X edge; two tiles side by side = double line)")
def road_line():
    b = Builder(); _tile(b)
    _paint(b, "line_y", 0.455, 0, 0.09, 1.0)
    return [("road_line", b, (0, 0, 0))]


@asset("road_line_dash", 1, 1, "dashed white lane line along Z on the +X edge (tile has one dash)")
def road_line_dash():
    b = Builder(); _tile(b)
    _paint(b, "line_w", 0.46, 0, 0.08, 0.6)
    return [("road_line_dash", b, (0, 0, 0))]


@asset("road_edge", 1, 1, "asphalt with a solid white edge line along Z near the -X side (road edge next to a curb)")
def road_edge():
    b = Builder(); _tile(b)
    _paint(b, "line_w", -0.38, 0, 0.07, 1.0)
    return [("road_edge", b, (0, 0, 0))]


@asset("road_crosswalk", 1, 1, "zebra crossing: bars run along Z, spaced along X (pedestrians cross along X)")
def road_crosswalk():
    b = Builder(); _tile(b)
    for x in (-0.34, 0.0, 0.34):
        _paint(b, "line_w", x, 0, 0.2, 0.96)
    return [("road_crosswalk", b, (0, 0, 0))]


@asset("road_corner", 1, 1, "intersection corner: asphalt quarter-disc, sidewalk-coloured block in the -X,-Z corner with a curb arc. Rotate in 90 degree steps")
def road_corner():
    b = Builder()
    arc = _arc(1.0, 0.5, 0.5, 180 + 0, 270, 10)       # circle centred on the far (+X,+Z) corner, radius 1
    # arc runs from (-0.5, 0.5) to (0.5, -0.5)
    asph = list(arc) + [(0.5, 0.5)]
    side = [(-0.5, 0.5)] + arc[1:-1] + [(0.5, -0.5), (-0.5, -0.5)]
    poly_slab(b, "asphalt", asph, -0.05, 0.0)
    poly_slab(b, "paving", side, -0.05, 0.0)
    ring = _arc(1.0, 0.5, 0.5, 180, 270, 10)
    ring2 = _arc(0.92, 0.5, 0.5, 180, 270, 10)
    poly_slab(b, "curb", ring + ring2[::-1], 0.0, 0.03)
    return [("road_corner", b, (0, 0, 0))]


@asset("road_t", 1, 1, "T-junction through tile: asphalt, yellow centre line on the +X edge continues (branch comes in from -X)")
def road_t():
    b = Builder(); _tile(b)
    _paint(b, "line_y", 0.455, 0, 0.09, 1.0)
    _paint(b, "line_w", -0.5 + 0.06, 0, 0.12, 0.3)      # stop-bar stub on the branch side
    return [("road_t", b, (0, 0, 0))]


@asset("road_cross", 1, 1, "4-way intersection centre tile: asphalt with four small corner ticks")
def road_cross():
    b = Builder(); _tile(b)
    for sx in (-1, 1):
        for sz in (-1, 1):
            _paint(b, "line_w", sx * 0.42, sz * 0.46, 0.14, 0.05)
            _paint(b, "line_w", sx * 0.46, sz * 0.42, 0.05, 0.14)
    return [("road_cross", b, (0, 0, 0))]


@asset("road_dead_end", 1, 1, "road end cap: asphalt with a red/white barrier along the -Z edge (rotate to face the road)")
def road_dead_end():
    b = Builder(); _tile(b)
    for i in range(4):
        b.box("red_paint" if i % 2 == 0 else "white", -0.375 + 0.25 * i, 0.12, -0.42, 0.25, 0.14, 0.05)
    for x in (-0.46, 0.46):
        b.box("gray", x, 0.1, -0.42, 0.05, 0.2, 0.05)
    return [("road_dead_end", b, (0, 0, 0))]


# ---- sidewalks / curbs ----------------------------------------------------------------------------------
def _lip(b, side):
    """Raised curb stone strip along a tile edge: 'N' = -Z edge, 'W' = -X edge."""
    if side == "N":
        b.box("curb", 0, -0.0075, -0.43, 1.0, 0.085, 0.14)
    else:
        b.box("curb", -0.43, -0.0075, 0, 0.14, 0.085, 1.0)


@asset("sidewalk", 1, 1, "paving slabs, top at y=0")
def sidewalk():
    b = Builder()
    _tile(b, "paving")
    _paint(b, "paving2", 0, 0, 1.0, 0.03, 0.004)
    _paint(b, "paving2", 0, 0, 0.03, 1.0, 0.004)
    return [("sidewalk", b, (0, 0, 0))]


@asset("sidewalk_curb", 1, 1, "sidewalk with a raised curb stone along the -Z edge (road is on the -Z side)")
def sidewalk_curb():
    b = Builder()
    _tile(b, "paving"); _lip(b, "N")
    _paint(b, "paving2", 0, 0.1, 0.03, 0.8, 0.004)
    return [("sidewalk_curb", b, (0, 0, 0))]


@asset("sidewalk_corner", 1, 1, "outside sidewalk corner: curb along -Z and -X edges (road wraps round that corner)")
def sidewalk_corner():
    b = Builder()
    _tile(b, "paving"); _lip(b, "N"); _lip(b, "W")
    return [("sidewalk_corner", b, (0, 0, 0))]


@asset("curb_ramp", 1, 1, "sidewalk curb ramp: curb on the -Z edge with a sloped ramp + yellow tactile patch in the middle")
def curb_ramp():
    b = Builder()
    _tile(b, "paving")
    b.box("curb", -0.36, -0.0075, -0.43, 0.28, 0.085, 0.14)
    b.box("curb", 0.36, -0.0075, -0.43, 0.28, 0.085, 0.14)
    hull(b, "paving", [(-0.22, 0, -0.5), (0.22, 0, -0.5), (-0.22, 0, -0.26), (0.22, 0, -0.26), (-0.22, 0.035, -0.26), (0.22, 0.035, -0.26)])
    _paint(b, "line_y", 0, -0.12, 0.44, 0.28, 0.008)
    return [("curb_ramp", b, (0, 0, 0))]


@asset("curb_straight", 1, 0.15, "bare curb stone 1.0 x 0.14 on the -Z edge (place along road edges); origin tile centre")
def curb_straight():
    b = Builder()
    b.box("curb", 0, 0.0175, -0.43, 1.0, 0.085, 0.14)
    return [("curb_straight", b, (0, 0, 0))]


@asset("curb_corner", 1, 1, "bare L-shaped curb stone on the -Z and -X edges")
def curb_corner():
    b = Builder()
    b.box("curb", 0.07, 0.0175, -0.43, 0.86, 0.085, 0.14)
    b.box("curb", -0.43, 0.0175, 0, 0.14, 0.085, 1.0)
    return [("curb_corner", b, (0, 0, 0))]


# ---- plain ground ---------------------------------------------------------------------------------------
@asset("ground_grass", 1, 1, "grass tile with two darker patches")
def ground_grass():
    b = Builder()
    _tile(b, "grass")
    _paint(b, "grass2", -0.2, 0.2, 0.4, 0.35, 0.003)
    _paint(b, "grass2", 0.25, -0.25, 0.3, 0.3, 0.003)
    return [("ground_grass", b, (0, 0, 0))]


@asset("ground_dirt", 1, 1, "bare earth tile")
def ground_dirt():
    b = Builder()
    _tile(b, "dirt")
    _paint(b, "dirt2", 0.15, 0.2, 0.45, 0.3, 0.003)
    _paint(b, "dirt2", -0.25, -0.25, 0.3, 0.25, 0.003)
    return [("ground_dirt", b, (0, 0, 0))]


@asset("ground_gravel", 1, 1, "gravel tile with pebbles")
def ground_gravel():
    b = Builder()
    _tile(b, "gravel")
    for i, (x, z) in enumerate([(-0.3, -0.3), (0.1, -0.35), (0.35, 0.1), (-0.1, 0.05), (-0.35, 0.3), (0.2, 0.35), (0.0, -0.1)]):
        b.box("gravel2", x, 0.008, z, 0.12, 0.016, 0.1 + 0.02 * (i % 3))
    return [("ground_gravel", b, (0, 0, 0))]


@asset("ground_sand", 1, 1, "sand tile with ripples")
def ground_sand():
    b = Builder()
    _tile(b, "sand")
    _paint(b, "sand2", 0, -0.2, 0.8, 0.05, 0.003)
    _paint(b, "sand2", 0, 0.2, 0.8, 0.05, 0.003)
    return [("ground_sand", b, (0, 0, 0))]
