"""Vehicles: hatchback / sedan / van (4 colours each) + bus. Front = -Z. Origin: centre, on the ground.
Nodes: body (materials body, glass, trim/black), wheel_fl wheel_fr wheel_rl wheel_rr (pivot = axle centre, spin about X).
Body paint material is called `body` so Godot can recolour it with a surface override."""

CAR_COLORS = {
    "red":    ((0.78, 0.14, 0.14), 0.4, 0.2),
    "blue":   ((0.18, 0.38, 0.80), 0.4, 0.2),
    "white":  ((0.93, 0.93, 0.91), 0.4, 0.2),
    "yellow": ((0.96, 0.78, 0.15), 0.4, 0.2),
}


def _wheel(r, w, x, z, tyre="tyre"):
    b = Builder()
    tube(b, tyre, (x - w / 2, r, z), (x + w / 2, r, z), r, 12)
    tube(b, "hub", (x - w / 2 - 0.01, r, z), (x + w / 2 + 0.01, r, z), r * 0.55, 8)
    return b


def _wheels(r, w, hx, zf, zr):
    out = []
    for name, x, z in (("wheel_fl", -hx, zf), ("wheel_fr", hx, zf), ("wheel_rl", -hx, zr), ("wheel_rr", hx, zr)):
        out.append((name, _wheel(r, w, x, z), (x, r, z)))
    return out


def _lights(b, hw, zf, zr, y, hy=0.1):
    for sx in (-1, 1):
        b.box("headlight", sx * (hw - 0.3), y, zf, 0.3, hy, 0.06)
        b.box("taillight", sx * (hw - 0.28), y, zr, 0.28, hy, 0.06)
    b.box("black", 0, y - 0.05, zf - 0.005, hw * 1.0, 0.1, 0.05)       # grille
    b.box("black", 0, y - 0.0, zr + 0.0, hw * 0.3, 0.05, 0.04)         # plate


def _bumpers(b, hw, zf, zr, y=0.38):
    b.box("black", 0, y, zf - 0.02, hw * 2.02, 0.2, 0.12)
    b.box("black", 0, y, zr + 0.02, hw * 2.02, 0.2, 0.12)


def hatchback():
    b = Builder(); hw = 0.86
    b.box("body", 0, 0.55, 0.0, 1.72, 0.5, 3.9)                                   # lower body
    hull(b, "glass", [(-0.8, 0.8, -0.55), (0.8, 0.8, -0.55), (-0.8, 0.8, 1.85), (0.8, 0.8, 1.85),
                      (-0.7, 1.4, -0.05), (0.7, 1.4, -0.05), (-0.7, 1.4, 1.45), (0.7, 1.4, 1.45)])   # cabin glass
    b.box("body", 0, 1.42, 0.7, 1.5, 0.07, 1.6)                                    # roof
    for sx in (-1, 1):
        b.box("body", sx * 0.77, 1.1, 0.5, 0.05, 0.62, 0.12)                       # B pillar
    _bumpers(b, hw, -1.95, 1.95); _lights(b, hw, -1.97, 1.97, 0.62)
    return [("body", b, (0, 0, 0))] + _wheels(0.31, 0.2, 0.8, -1.2, 1.15)


def sedan():
    b = Builder(); hw = 0.9
    b.box("body", 0, 0.56, 0.0, 1.8, 0.52, 4.5)
    hull(b, "glass", [(-0.82, 0.82, -0.8), (0.82, 0.82, -0.8), (-0.82, 0.82, 1.15), (0.82, 0.82, 1.15),
                      (-0.7, 1.38, -0.35), (0.7, 1.38, -0.35), (-0.7, 1.38, 0.8), (0.7, 1.38, 0.8)])
    b.box("body", 0, 1.4, 0.22, 1.5, 0.07, 1.12)
    for sx in (-1, 1):
        b.box("body", sx * 0.8, 1.1, 0.22, 0.05, 0.56, 0.1)
    _bumpers(b, hw, -2.25, 2.25); _lights(b, hw, -2.27, 2.27, 0.65)
    return [("body", b, (0, 0, 0))] + _wheels(0.32, 0.22, 0.84, -1.45, 1.4)


def van():
    b = Builder(); hw = 0.94
    b.box("body", 0, 0.78, 0.0, 1.88, 0.95, 4.8)                                    # box body
    hull(b, "body", [(-0.92, 1.25, -2.4), (0.92, 1.25, -2.4), (-0.92, 1.25, 2.4), (0.92, 1.25, 2.4),
                     (-0.92, 2.05, -1.55), (0.92, 2.05, -1.55), (-0.92, 2.05, 2.4), (0.92, 2.05, 2.4)])
    rbox(b, "glass", 0, 1.67, -1.98, 1.7, 0.62, 0.04, rx=-28)                       # windscreen
    for sx in (-1, 1):
        b.box("glass", sx * 0.95, 1.65, -1.3, 0.04, 0.5, 0.7)                       # cab window
        b.box("glass", sx * 0.95, 1.65, 0.6, 0.04, 0.5, 0.9)
    b.box("black", 0, 1.22, 0.0, 1.9, 0.04, 4.82)                                   # trim line
    _bumpers(b, hw, -2.4, 2.4, 0.4); _lights(b, hw, -2.42, 2.42, 0.72, 0.14)
    return [("body", b, (0, 0, 0))] + _wheels(0.34, 0.22, 0.86, -1.5, 1.5)


def bus():
    b = Builder()
    b.box("body", 0, 1.5, 0.0, 2.5, 2.4, 9.0)
    b.box("bus_stripe", 0, 0.78, 0.0, 2.52, 0.2, 9.02)
    for sx in (-1, 1):
        for i in range(5):
            b.box("glass", sx * 1.26, 2.0, -3.4 + i * 1.6, 0.04, 0.8, 1.3)
    b.box("glass", 0, 1.9, -4.51, 2.2, 1.0, 0.04)                                  # windscreen
    b.box("black", 0, 0.5, -4.55, 2.5, 0.35, 0.1); b.box("black", 0, 0.5, 4.55, 2.5, 0.35, 0.1)
    b.box("bus_stripe", 0, 2.78, -4.52, 1.4, 0.2, 0.03)                            # destination board
    b.box("headlight", -0.85, 0.8, -4.52, 0.3, 0.15, 0.04); b.box("headlight", 0.85, 0.8, -4.52, 0.3, 0.15, 0.04)
    b.box("taillight", -0.85, 0.8, 4.52, 0.3, 0.15, 0.04); b.box("taillight", 0.85, 0.8, 4.52, 0.3, 0.15, 0.04)
    return [("body", b, (0, 0, 0))] + _wheels(0.5, 0.3, 1.1, -3.1, 2.9)


def _reg_cars():
    for name, fn, L, W in (("hatchback", hatchback, 3.9, 1.8), ("sedan", sedan, 4.5, 1.9), ("van", van, 4.8, 1.95)):
        for cname, col in CAR_COLORS.items():
            asset("car_%s_%s" % (name, cname), W, L, "%s, %.1f m long, front -Z; nodes body, wheel_fl/fr/rl/rr (spin about X); body paint = material 'body'" % (name, L),
                  pal={"body": col})(fn)
    asset("bus", 2.6, 9.0, "city bus 9 m, front -Z; nodes body, wheel_fl/fr/rl/rr", pal={"body": ((0.20, 0.52, 0.78), 0.5, 0.1)})(bus)


_reg_cars()
