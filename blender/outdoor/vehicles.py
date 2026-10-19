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
    b.box("body", 0, 1.45, 0.0, 2.0, 2.3, 8.4)
    b.box("bus_stripe", 0, 0.78, 0.0, 2.02, 0.2, 8.42)
    for sx in (-1, 1):
        for i in range(5):
            b.box("glass", sx * 1.01, 1.95, -3.0 + i * 1.5, 0.04, 0.8, 1.2)
    b.box("glass", 0, 1.85, -4.21, 1.8, 1.0, 0.04)                                 # windscreen
    b.box("black", 0, 0.5, -4.25, 2.0, 0.35, 0.1); b.box("black", 0, 0.5, 4.25, 2.0, 0.35, 0.1)
    b.box("bus_stripe", 0, 2.7, -4.22, 1.2, 0.2, 0.03)                             # destination board
    b.box("headlight", -0.7, 0.8, -4.22, 0.3, 0.15, 0.04); b.box("headlight", 0.7, 0.8, -4.22, 0.3, 0.15, 0.04)
    b.box("taillight", -0.7, 0.8, 4.22, 0.3, 0.15, 0.04); b.box("taillight", 0.7, 0.8, 4.22, 0.3, 0.15, 0.04)
    return [("body", b, (0, 0, 0))] + _wheels(0.5, 0.3, 0.9, -2.9, 2.7)


def _with_hazards(fn, length):
    return lambda: fn() + _hazards(0.86, length / 2 + 0.02, 0.62)


def _reg_cars():
    for name, fn, L, W in (("hatchback", hatchback, 3.9, 1.8), ("sedan", sedan, 4.5, 1.9), ("van", van, 4.8, 1.95)):
        for cname, col in CAR_COLORS.items():
            asset("car_%s_%s" % (name, cname), W, L, "%s, %.1f m long, front -Z; nodes body, wheel_fl/fr/rl/rr (spin about X), hazard lamps haz_fl/fr/rl/rr (hidden by Godot until a crash); body paint = material 'body'" % (name, L),
                  pal={"body": col})(_with_hazards(fn, L))
    asset("bus", 2.1, 8.4, "city bus 8.4 m x 2.0 m, front -Z; nodes body, wheel_fl/fr/rl/rr", pal={"body": ((0.20, 0.52, 0.78), 0.5, 0.1)})(bus)


_reg_cars()


PALETTE.update({
    "siren_red":  ((0.95, 0.10, 0.10), 0.3, 0.0),
    "siren_blue": ((0.15, 0.30, 0.98), 0.3, 0.0),
    "hazard":     ((1.00, 0.62, 0.05), 0.3, 0.0),
    "taxi_sign":  ((1.00, 0.92, 0.55), 0.3, 0.0),
    "police_blue": ((0.12, 0.22, 0.55), 0.5, 0.0),
    "white_paint": ((0.94, 0.94, 0.95), 0.4, 0.2),
    "amb_red":    ((0.85, 0.12, 0.12), 0.5, 0.0),
    "fire_paint": ((0.80, 0.10, 0.08), 0.4, 0.2),
    "ladder":     ((0.78, 0.80, 0.82), 0.4, 0.6),
    "tow_paint":  ((0.95, 0.55, 0.10), 0.5, 0.2),
    "skin":       ((0.89, 0.70, 0.56), 0.8, 0.0),
    "frame":      ((0.20, 0.22, 0.26), 0.5, 0.4),
    "helmet":     ((0.95, 0.80, 0.15), 0.6, 0.0),
})
EMISSIVE.update({"siren_red": 3.0, "siren_blue": 3.0, "hazard": 3.0, "taxi_sign": 1.5})


def _hazards(hw, zf, y):
    """Four separate small lamp nodes (haz_fl/fr/rl/rr): Godot shows them blinking for hazard lights."""
    out = []
    for name, x, z in (("haz_fl", -hw, -zf), ("haz_fr", hw, -zf), ("haz_rl", -hw, zf), ("haz_rr", hw, zf)):
        b = Builder()
        b.box("hazard", 0, 0, 0, 0.2, 0.14, 0.08)
        out.append((name, b, (x * 0.93, y, z)))
    return out


def _bar(y, z, width=0.7):
    """Roof light bar as nodes (bar_red, bar_blue) so Godot can flash them in turn."""
    br = Builder(); br.box("siren_red", 0, 0, 0, width / 2, 0.12, 0.22)
    bb = Builder(); bb.box("siren_blue", 0, 0, 0, width / 2, 0.12, 0.22)
    base = Builder(); base.box("black", 0, 0, 0, width, 0.05, 0.26)
    return [("bar_red", br, (-width / 4, y + 0.08, z)), ("bar_blue", bb, (width / 4, y + 0.08, z)), ("bar_base", base, (0, y + 0.02, z))]


def taxi():
    parts = sedan()
    b = parts[0][1]
    b.box("black", 0, 0.98, 0.0, 1.83, 0.06, 4.0)
    b.box("taxi_sign", 0, 1.55, 0.2, 0.7, 0.2, 0.28)
    return parts + _hazards(0.9, 2.27, 0.65)


def police_car():
    parts = sedan()
    b = parts[0][1]
    b.box("police_blue", 0, 0.62, 0.0, 1.82, 0.14, 4.0)
    b.box("police_blue", 0, 0.9, 1.9, 1.5, 0.05, 0.6)
    return parts + _bar(1.46, 0.2) + _hazards(0.9, 2.27, 0.65)


def ambulance():
    parts = van()
    b = parts[0][1]
    b.box("amb_red", 0, 1.0, 0.0, 1.92, 0.16, 4.82)
    for sx in (-1, 1):
        b.box("amb_red", sx * 0.96, 1.62, 0.9, 0.04, 0.42, 0.12)       # cross on the side
        b.box("amb_red", sx * 0.96, 1.62, 0.9, 0.04, 0.12, 0.42)
    return parts + _bar(2.05, -1.4, 0.9) + _hazards(0.94, 2.42, 0.72)


def fire_engine():
    b = Builder()
    b.box("fire_paint", 0, 0.95, 0.9, 1.95, 1.3, 5.0)                     # body / pump house
    b.box("fire_paint", 0, 1.1, -2.35, 1.95, 1.6, 1.6)                    # cab
    b.box("glass", 0, 1.6, -3.17, 1.7, 0.7, 0.04)                         # windscreen
    for sx in (-1, 1):
        b.box("glass", sx * 0.98, 1.6, -2.35, 0.04, 0.6, 1.0)
        b.box("trim", sx * 0.98, 1.0, 1.0, 0.04, 0.12, 4.6)               # side stripe
    b.box("ladder", 0, 1.78, 0.9, 0.6, 0.12, 4.6)                         # ladder on the roof
    for z in (-1.1, -0.3, 0.5, 1.3, 2.1, 2.9):
        b.box("ladder", 0, 1.84, z, 0.8, 0.06, 0.08)
    b.box("black", 0, 0.45, -3.2, 1.95, 0.3, 0.12); b.box("black", 0, 0.45, 3.4, 1.95, 0.3, 0.12)
    for sx in (-1, 1):
        b.box("headlight", sx * 0.7, 0.75, -3.2, 0.3, 0.15, 0.05)
        b.box("taillight", sx * 0.7, 0.75, 3.4, 0.3, 0.15, 0.05)
    return [("body", b, (0, 0, 0))] + _wheels(0.45, 0.28, 0.85, -2.1, 2.2) + _bar(1.9, -2.2, 0.9) + _hazards(0.96, 3.4, 0.8)


def tow_truck():
    b = Builder()
    b.box("tow_paint", 0, 0.85, -1.9, 1.9, 1.0, 1.5)                      # cab
    b.box("tow_paint", 0, 1.55, -1.9, 1.8, 0.7, 1.2)
    b.box("glass", 0, 1.55, -2.52, 1.6, 0.6, 0.04)
    b.box("black", 0, 0.7, 0.9, 1.95, 0.18, 4.2)                           # chassis
    b.box("tow_paint", 0, 0.92, 1.1, 1.9, 0.12, 3.8)                       # flat bed
    b.box("black", 0.0, 1.5, 0.2, 0.2, 1.2, 0.2)                           # boom post
    b.box("black", 0.0, 2.05, 0.9, 0.12, 0.12, 1.8)                        # boom
    b.box("black", 0, 0.45, -2.7, 1.9, 0.25, 0.1)
    for sx in (-1, 1):
        b.box("headlight", sx * 0.65, 0.75, -2.66, 0.3, 0.14, 0.05)
        b.box("taillight", sx * 0.7, 0.8, 3.0, 0.3, 0.14, 0.05)
    amber = Builder(); amber.box("hazard", 0, 0, 0, 0.5, 0.14, 0.2)
    return [("body", b, (0, 0, 0))] + _wheels(0.4, 0.26, 0.85, -1.9, 1.9) + [("bar_amber", amber, (0, 2.3, -1.9))] + _hazards(0.95, 3.0, 0.85)


def bike():
    b = Builder()                                                          # frame and rider, front is -Z
    b.box("frame", 0, 0.55, 0.0, 0.06, 0.06, 1.0)
    b.box("frame", 0, 0.75, -0.35, 0.05, 0.5, 0.05)
    b.box("frame", 0, 0.45, 0.45, 0.05, 0.5, 0.05)
    b.box("frame", 0, 1.0, -0.45, 0.5, 0.05, 0.05)                         # handlebars
    b.box("black", 0, 0.98, 0.35, 0.12, 0.05, 0.3)                         # saddle
    b.box("body", 0, 1.3, 0.2, 0.3, 0.6, 0.22)                             # rider torso (shirt colour)
    b.box("skin", 0, 1.78, 0.1, 0.2, 0.2, 0.2)                             # head
    b.box("helmet", 0, 1.92, 0.1, 0.24, 0.1, 0.24)
    for sx in (-1, 1):
        b.box("body", sx * 0.2, 1.1, -0.1, 0.07, 0.07, 0.5)                # arms to the bars
        b.box("frame", sx * 0.12, 0.75, 0.2, 0.1, 0.5, 0.12)               # legs
    wheels = []
    for name, z in (("wheel_f", -0.55), ("wheel_r", 0.55)):
        wb = Builder()
        tube(wb, "tyre", (-0.03, 0.33, z), (0.03, 0.33, z), 0.33, 12)
        tube(wb, "hub", (-0.035, 0.33, z), (0.035, 0.33, z), 0.2, 8)
        wheels.append((name, wb, (0, 0.33, z)))
    return [("body", b, (0, 0, 0))] + wheels


def _reg_more():
    asset("taxi", 1.9, 4.5, "taxi: yellow sedan, roof sign, hazard lamp nodes haz_fl/fr/rl/rr (hide them in Godot until needed)", pal={"body": ((0.96, 0.78, 0.15), 0.4, 0.2)})(taxi)
    asset("police_car", 1.9, 4.5, "patrol car: white sedan, blue stripe, roof bar nodes bar_red / bar_blue (flash them)", pal={"body": ((0.94, 0.94, 0.95), 0.4, 0.2)})(police_car)
    asset("ambulance", 1.95, 4.8, "ambulance: white van, red stripe and cross, roof bar nodes bar_red / bar_blue", pal={"body": ((0.94, 0.94, 0.95), 0.4, 0.2)})(ambulance)
    asset("fire_engine", 2.0, 6.8, "fire engine 6.8 m: red, ladder on the roof, bar nodes bar_red / bar_blue", pal={})(fire_engine)
    asset("tow_truck", 2.0, 5.8, "tow truck: orange cab and flat bed, amber light node bar_amber", pal={})(tow_truck)
    asset("bike", 0.7, 1.8, "bicycle with a rider; torso = material 'body' (tint with the shirt); nodes wheel_f / wheel_r (spin about X)", pal={"body": ((0.25, 0.45, 0.80), 0.8, 0.0)})(bike)


_reg_more()
