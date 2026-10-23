"""Extra object models, part C (task 60: objects that had no model or wore another object's). Same conventions as models_a.py:
origin = footprint centre on the floor, front faces -Z (the user stands or sits on the -Z side), 1 unit = 1 m.
Seat and bed heights match the definitions these objects are cloned from (sofa seat ~0.6, armchair ~0.5, bed ~0.55)."""


def legs(b, mat, xs, zs, h, t):
    for x in xs:
        for z in zs:
            b.box(mat, x, h / 2, z, t, h, t)


# ---------------------------------------------------------------- seating and lying
def deck_chair(B, tube):
    b = B()
    tube(b, "wood", (-0.28, 0.0, -0.35), (-0.28, 0.75, 0.35), 0.025)
    tube(b, "wood", (0.28, 0.0, -0.35), (0.28, 0.75, 0.35), 0.025)
    tube(b, "wood", (-0.28, 0.0, 0.3), (-0.28, 0.45, -0.3), 0.025)
    tube(b, "wood", (0.28, 0.0, 0.3), (0.28, 0.45, -0.3), 0.025)
    b.box("fabric_blue", 0, 0.42, -0.08, 0.52, 0.03, 0.5)
    tube(b, "fabric_blue", (0, 0.44, 0.15), (0, 0.78, 0.36), 0.03)
    b.box("fabric_blue", 0, 0.62, 0.26, 0.52, 0.4, 0.03)
    return [("deck_chair", b, (0, 0, 0))]


def theatre_seat(B, tube):
    b = B()
    b.box("metal_dark", -0.3, 0.32, 0.05, 0.06, 0.64, 0.6)
    b.box("metal_dark", 0.3, 0.32, 0.05, 0.06, 0.64, 0.6)
    b.box("fabric_red", 0, 0.47, -0.02, 0.54, 0.12, 0.5)
    b.box("fabric_red", 0, 0.82, 0.27, 0.54, 0.7, 0.1)
    b.box("metal_dark", 0, 0.08, 0.05, 0.54, 0.16, 0.5)
    return [("theatre_seat", b, (0, 0, 0))]


def sunbed(B, tube):
    b = B()
    legs(b, "steel", (-0.27, 0.27), (-0.38, 0.38), 0.32, 0.04)
    b.box("white", 0, 0.34, -0.08, 0.6, 0.06, 0.66)
    b.box("fabric_tan", 0, 0.39, -0.08, 0.56, 0.05, 0.62)
    tube(b, "white", (0, 0.38, 0.25), (0, 0.85, 0.45), 0.04)
    b.box("fabric_tan", 0, 0.63, 0.35, 0.56, 0.5, 0.06)
    return [("sunbed", b, (0, 0, 0))]


def log_bench(B, tube):
    b = B()
    for x in (-0.7, 0.7):
        b.cyl("wood_dark", x, 0.0, 0.0, 0.17, 0.42, seg=10)
    b.box("wood", 0, 0.5, 0.0, 1.9, 0.16, 0.42)
    b.box("wood_dark", 0, 0.42, 0.0, 1.92, 0.04, 0.44)
    return [("log_bench", b, (0, 0, 0))]


def pew(B, tube):
    b = B()
    for x in (-0.94, 0.94):
        b.box("wood_dark", x, 0.48, 0.05, 0.06, 0.96, 0.5)
    b.box("wood", 0, 0.5, -0.02, 1.84, 0.06, 0.44)
    b.box("wood", 0, 0.82, 0.24, 1.84, 0.6, 0.05)
    b.box("wood_dark", 0, 0.12, 0.05, 1.84, 0.04, 0.4)
    b.box("wood_dark", 0, 1.08, 0.3, 1.88, 0.06, 0.14)          # book shelf on the back for the row behind
    return [("pew", b, (0, 0, 0))]


def tent(B, tube):
    b = B()
    b.box("soil", 0, 0.01, 0.0, 1.9, 0.02, 1.9)
    tube(b, "fabric_green", (-0.9, 0.0, -0.85), (0.0, 1.35, -0.85), 0.03)
    tube(b, "fabric_green", (0.9, 0.0, -0.85), (0.0, 1.35, -0.85), 0.03)
    tube(b, "fabric_green", (-0.9, 0.0, 0.85), (0.0, 1.35, 0.85), 0.03)
    tube(b, "fabric_green", (0.9, 0.0, 0.85), (0.0, 1.35, 0.85), 0.03)
    tube(b, "wood_dark", (0.0, 1.35, -0.88), (0.0, 1.35, 0.88), 0.025)
    # the two sloped walls as thin slabs, the -Z end open (the sleeper lies inside on a mat)
    for s in (-1, 1):
        for i in range(6):
            y = 0.1 + i * 0.22
            x = s * (0.9 - 0.9 * (y / 1.35))
            b.box("fabric_green", x, y, 0.0, 0.22, 0.04, 1.7)
    b.box("fabric_blue", 0, 0.05, 0.0, 1.0, 0.06, 1.7)
    return [("tent", b, (0, 0, 0))]


def operating_table(B, tube):
    b = B()
    b.cyl("steel", 0, 0.0, 0.0, 0.18, 0.5, seg=12)
    b.box("metal_dark", 0, 0.03, 0.0, 0.6, 0.06, 0.9)
    b.box("steel", 0, 0.5, 0.0, 0.62, 0.06, 1.85)
    b.box("baby_blue", 0, 0.55, 0.0, 0.58, 0.05, 1.8)
    b.box("steel", 0.28, 1.6, -0.45, 0.06, 0.06, 0.6)          # the lamp arm over the table
    b.cyl("white", 0.28, 1.45, -0.7, 0.16, 0.12, seg=14)
    b.box("steel", 0.28, 0.8, -0.15, 0.05, 1.6, 0.05)
    return [("operating_table", b, (0, 0, 0))]


# ---------------------------------------------------------------- outdoor
def beach_umbrella(B, tube):
    b = B()
    b.cyl("white", 0, 0.0, 0, 0.18, 0.08, seg=12)
    b.cyl("white", 0, 0.08, 0, 0.025, 2.0, seg=8)
    b.cyl("red_paint", 0, 1.85, 0, 0.5, 0.24, r2=0.04, seg=8)          # inside its tile (a wider canopy went through walls)
    b.cyl("white", 0, 1.85, 0, 0.5, 0.03, seg=8)
    return [("beach_umbrella", b, (0, 0, 0))]


def campfire(B, tube):
    b = B()
    for i in range(8):
        import math
        a = i * math.pi / 4
        b.sphere("stone", math.cos(a) * 0.38, 0.07, math.sin(a) * 0.38, 0.1, 3, 6)
    b.box("soil", 0, 0.01, 0, 0.7, 0.02, 0.7)
    tube(b, "wood_dark", (-0.25, 0.04, -0.1), (0.25, 0.22, 0.1), 0.05)
    tube(b, "wood_dark", (0.25, 0.04, -0.1), (-0.25, 0.22, 0.1), 0.05)
    tube(b, "wood", (0.0, 0.04, -0.28), (0.0, 0.24, 0.25), 0.05)
    b.cyl("fire", 0, 0.1, 0, 0.14, 0.32, r2=0.0, seg=8)
    return [("campfire", b, (0, 0, 0))]


def fountain(B, tube):
    b = B()
    b.cyl("stone", 0, 0.0, 0, 0.48, 0.32, seg=16)
    b.cyl("water", 0, 0.3, 0, 0.42, 0.03, seg=16)
    b.cyl("stone", 0, 0.3, 0, 0.08, 0.55, seg=10)
    b.cyl("stone", 0, 0.85, 0, 0.24, 0.08, r2=0.16, seg=14)
    b.cyl("water", 0, 0.93, 0, 0.16, 0.02, seg=12)
    b.cyl("stone", 0, 0.93, 0, 0.04, 0.2, seg=8)
    return [("fountain", b, (0, 0, 0))]


def hiking_trail(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.8, 0.2, 0.1, 1.6, 0.1)
    b.box("wood", 0, 1.35, 0.14, 0.7, 0.45, 0.04)
    b.box("paint_c", -0.15, 1.42, 0.115, 0.28, 0.06, 0.01)          # the route lines on the board
    b.box("leaf", 0.1, 1.3, 0.115, 0.32, 0.06, 0.01)
    b.box("wood_dark", 0, 1.6, 0.14, 0.78, 0.05, 0.08)
    b.box("stone", 0, 0.05, 0.2, 0.3, 0.1, 0.3)
    return [("hiking_trail", b, (0, 0, 0))]


def life_ring(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.65, 0.3, 0.1, 1.3, 0.1)
    b.box("wood", 0, 1.1, 0.24, 0.62, 0.62, 0.03)
    for i in range(12):
        import math
        a = i * math.pi / 6
        b.box("red_paint" if i % 3 else "white", math.cos(a) * 0.22, 1.1 + math.sin(a) * 0.22, 0.2, 0.14, 0.14, 0.07)
    return [("life_ring", b, (0, 0, 0))]


def meteorite(B, tube):
    b = B()
    b.box("soil", 0, 0.02, 0, 0.95, 0.04, 0.95)
    b.sphere("metal_dark", 0, 0.28, 0, 0.32, 4, 7)
    b.sphere("black", 0.18, 0.3, -0.1, 0.18, 3, 6)
    b.sphere("fire", -0.12, 0.42, -0.18, 0.05, 2, 5)
    return [("meteorite", b, (0, 0, 0))]


def debris(B, tube):
    b = B()
    tube(b, "wood_dark", (-0.4, 0.05, -0.3), (0.35, 0.12, 0.25), 0.05)
    tube(b, "wood", (-0.3, 0.05, 0.3), (0.4, 0.08, -0.2), 0.04)
    b.box("brick", 0.15, 0.06, 0.15, 0.22, 0.12, 0.1)
    b.box("brick", -0.2, 0.06, -0.05, 0.22, 0.12, 0.1)
    b.box("leaf", 0.05, 0.03, -0.3, 0.4, 0.06, 0.25)
    b.box("metal_dark", -0.25, 0.04, 0.3, 0.3, 0.02, 0.2)
    return [("debris", b, (0, 0, 0))]


def generator(B, tube):
    b = B()
    b.box("metal_dark", 0, 0.06, 0, 0.8, 0.12, 0.55)
    b.box("yellow_safety", 0, 0.38, 0, 0.75, 0.5, 0.5)
    b.box("black", 0.18, 0.66, 0, 0.3, 0.08, 0.3)
    b.box("metal_dark", -0.2, 0.42, -0.26, 0.28, 0.24, 0.02)
    b.cyl("steel", 0.3, 0.6, 0.15, 0.04, 0.3, seg=8)
    return [("generator", b, (0, 0, 0))]


def playground(B, tube):
    b = B()
    for x in (-0.8, 0.0):
        for z in (-0.4, 0.4):
            b.box("red_paint", x, 0.75, z, 0.08, 1.5, 0.08)
    b.box("wood", -0.4, 1.0, 0.0, 0.88, 0.06, 0.88)
    b.box("red_paint", -0.4, 1.6, 0.0, 0.95, 0.06, 0.95)
    tube(b, "yellow_safety", (0.0, 1.0, 0.0), (0.85, 0.08, 0.0), 0.12)          # the slide
    tube(b, "steel", (-0.9, 0.0, -0.75), (-0.9, 1.0, -0.4), 0.025)
    tube(b, "steel", (-0.7, 0.0, -0.75), (-0.7, 1.0, -0.4), 0.025)
    for y in (0.25, 0.5, 0.75):
        b.box("steel", -0.8, y, -0.75 + y * 0.35, 0.24, 0.03, 0.04)
    b.box("soil", 0, 0.01, 0, 1.95, 0.02, 1.95)
    return [("playground", b, (0, 0, 0))]


def public_bin(B, tube):
    b = B()
    b.cyl("leaf", 0, 0.0, 0, 0.22, 0.85, r2=0.24, seg=12)
    b.cyl("metal_dark", 0, 0.85, 0, 0.26, 0.06, seg=12)
    b.box("metal_dark", 0, 0.45, 0.24, 0.08, 0.9, 0.06)
    return [("public_bin", b, (0, 0, 0))]


def sandbags(B, tube):
    b = B()
    for row, y in ((0, 0.1), (1, 0.28), (2, 0.46)):
        n = 3 - row
        for i in range(n):
            x = (i - (n - 1) / 2) * 0.32
            b.box("fabric_tan", x, y, 0.1, 0.3, 0.18, 0.5)
    return [("sandbags", b, (0, 0, 0))]


def slip_mat(B, tube):
    b = B()
    b.box("black", 0, 0.01, 0, 0.9, 0.02, 0.6)
    for i in range(6):
        b.box("gray", -0.35 + i * 0.14, 0.022, 0, 0.04, 0.005, 0.55)
    return [("slip_mat", b, (0, 0, 0))]


def solar_panel(B, tube):
    b = B()
    for x in (-0.35, 0.35):
        b.box("steel", x, 0.3, 0.2, 0.05, 0.6, 0.05)
        b.box("steel", x, 0.15, -0.25, 0.05, 0.3, 0.05)
    tube(b, "screen", (0.0, 0.32, -0.3), (0.0, 0.62, 0.25), 0.02)
    for i in range(3):
        y = 0.35 + i * 0.1
        z = -0.25 + i * 0.18
        b.box("fabric_blue", 0, y, z, 0.85, 0.03, 0.17)
    return [("solar_panel", b, (0, 0, 0))]


def storm_shelter(B, tube):
    b = B()
    b.box("stone", 0, 0.1, 0, 0.9, 0.2, 0.9)
    b.box("metal_dark", 0, 0.24, 0, 0.75, 0.06, 0.75)
    b.box("steel", 0, 0.28, -0.25, 0.3, 0.04, 0.05)
    tube(b, "yellow_safety", (-0.4, 0.2, -0.4), (0.4, 0.2, -0.4), 0.02)
    return [("storm_shelter", b, (0, 0, 0))]


def storm_shutters(B, tube):
    b = B()
    for i in range(3):
        b.box("wood_light" if i % 2 else "wood", -0.2 + i * 0.2, 0.75, 0.15 + i * 0.05, 0.5, 1.5, 0.04)
    b.box("wood_dark", 0, 0.03, 0.2, 0.9, 0.06, 0.3)
    return [("storm_shutters", b, (0, 0, 0))]


def streetlamp(B, tube):
    b = B()
    b.cyl("metal_dark", 0, 0.0, 0, 0.12, 0.3, r2=0.07, seg=10)
    b.cyl("metal_dark", 0, 0.3, 0, 0.05, 3.0, seg=8)
    tube(b, "metal_dark", (0.0, 3.2, 0.0), (0.0, 3.35, -0.25), 0.04)
    b.box("metal_dark", 0, 3.33, -0.3, 0.26, 0.08, 0.36)
    b.box("lamp_shade", 0, 3.27, -0.3, 0.22, 0.03, 0.3)
    return [("streetlamp", b, (0, 0, 0))]


def water_tank(B, tube):
    b = B()
    legs(b, "steel", (-0.32, 0.32), (-0.32, 0.32), 0.6, 0.06)
    b.cyl("teal", 0, 0.6, 0, 0.42, 0.9, seg=16)
    b.cyl("teal", 0, 1.5, 0, 0.42, 0.12, r2=0.1, seg=16)
    b.cyl("steel", 0.3, 0.2, -0.3, 0.04, 0.45, seg=8)
    return [("water_tank", b, (0, 0, 0))]


def well(B, tube):
    b = B()
    b.cyl("stone", 0, 0.0, 0, 0.45, 0.7, seg=14)
    b.cyl("black", 0, 0.68, 0, 0.36, 0.03, seg=14)
    for x in (-0.42, 0.42):
        b.box("wood_dark", x, 1.0, 0, 0.08, 1.3, 0.08)
    tube(b, "wood", (-0.5, 1.75, 0.0), (0.0, 2.05, 0.0), 0.03)
    tube(b, "wood", (0.5, 1.75, 0.0), (0.0, 2.05, 0.0), 0.03)
    tube(b, "wood_dark", (-0.42, 1.4, 0.0), (0.42, 1.4, 0.0), 0.04)
    b.cyl("wood", 0, 0.9, 0, 0.1, 0.18, seg=8)
    return [("well", b, (0, 0, 0))]


def podium(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.03, 0.05, 0.6, 0.06, 0.5)
    b.box("wood", 0, 0.55, 0.08, 0.5, 1.0, 0.36)
    tube(b, "wood", (0, 1.05, 0.22), (0, 1.15, -0.1), 0.02)
    b.box("wood_light", 0, 1.12, 0.05, 0.56, 0.04, 0.42)
    b.cyl("metal_dark", 0.15, 1.14, -0.08, 0.012, 0.25, seg=6)
    return [("podium", b, (0, 0, 0))]


def guard_dog_kennel(B, tube):
    b = B()
    b.box("wood", 0, 0.35, 0.05, 0.75, 0.7, 0.7)
    tube(b, "wood_dark", (-0.42, 0.7, 0.05), (0.0, 0.98, 0.05), 0.04)
    tube(b, "wood_dark", (0.42, 0.7, 0.05), (0.0, 0.98, 0.05), 0.04)
    b.box("wood_dark", -0.22, 0.85, 0.05, 0.5, 0.04, 0.78)
    b.box("wood_dark", 0.22, 0.85, 0.05, 0.5, 0.04, 0.78)
    b.box("black", 0, 0.28, -0.31, 0.32, 0.4, 0.02)
    b.cyl("steel", 0.3, 0.0, -0.38, 0.1, 0.06, seg=10)          # the bowl
    return [("guard_dog_kennel", b, (0, 0, 0))]


def parking_bay(B, tube):
    b = B()
    for x in (-0.97, 0.97):
        b.box("white", x, 0.005, 0, 0.06, 0.01, 1.95)
    b.box("white", 0, 0.005, 0.95, 1.95, 0.01, 0.06)
    b.box("stone", 0, 0.06, 0.72, 0.9, 0.12, 0.12)          # the wheel stop
    return [("parking_bay", b, (0, 0, 0))]


def stage(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.2, 0, 1.95, 0.4, 0.95)
    b.box("wood", 0, 0.41, 0, 1.95, 0.02, 0.95)
    for x in (-0.9, 0.9):
        b.box("fabric_red", x, 1.5, 0.4, 0.15, 2.2, 0.08)
    b.box("fabric_red", 0, 2.55, 0.4, 1.95, 0.2, 0.1)
    b.box("wood_dark", 0, 0.48, -0.42, 0.6, 0.12, 0.04)          # footlights
    b.box("lamp_shade", 0, 0.48, -0.445, 0.5, 0.05, 0.01)
    return [("stage", b, (0, 0, 0))]


# ---------------------------------------------------------------- work
def assembly_line(B, tube):
    b = B()
    legs(b, "steel", (-0.85, 0.85), (-0.2, 0.2), 0.8, 0.06)
    b.box("metal_dark", 0, 0.82, 0, 1.9, 0.06, 0.5)
    b.box("black", 0, 0.86, 0, 1.85, 0.02, 0.42)
    for x in (-0.6, 0.0, 0.6):
        b.box("fabric_tan", x, 0.93, 0, 0.3, 0.12, 0.26)
    b.box("yellow_safety", -0.92, 1.2, 0.2, 0.08, 0.8, 0.08)
    b.box("yellow_safety", 0.92, 1.2, 0.2, 0.08, 0.8, 0.08)
    b.box("yellow_safety", 0, 1.6, 0.2, 1.9, 0.08, 0.08)
    b.box("red_paint", 0.85, 1.05, -0.24, 0.1, 0.1, 0.04)
    return [("assembly_line", b, (0, 0, 0))]


def forklift(B, tube):
    b = B()
    b.box("yellow_safety", 0.25, 0.42, 0.1, 1.0, 0.55, 0.75)
    b.box("black", 0.45, 1.05, 0.1, 0.5, 0.06, 0.75)
    for x in (0.25, 0.65):
        b.box("black", x, 0.75, 0.42, 0.04, 0.6, 0.04)
        b.box("black", x, 0.75, -0.22, 0.04, 0.6, 0.04)
    b.box("fabric_tan", 0.45, 0.78, 0.1, 0.36, 0.08, 0.3)
    for z in (-0.18, 0.38):
        b.cyl("black", -0.05, 0.0, z, 0.1, 0.2, seg=10)
        b.cyl("black", 0.6, 0.0, z, 0.1, 0.2, seg=10)
    b.box("metal_dark", -0.32, 1.0, 0.1, 0.06, 1.9, 0.5)          # the mast
    b.box("steel", -0.6, 0.06, -0.05, 0.6, 0.04, 0.1)          # forks
    b.box("steel", -0.6, 0.06, 0.25, 0.6, 0.04, 0.1)
    return [("forklift", b, (0, 0, 0))]


def site_materials(B, tube):
    b = B()
    b.box("wood", -0.45, 0.06, 0, 0.9, 0.12, 0.9)
    for i in range(4):
        b.box("wood_light", -0.45, 0.16 + i * 0.08, 0, 0.88, 0.07, 0.86 - i * 0.04)
    for i in range(3):
        for j in range(2):
            b.box("brick", 0.4 + (j - 0.5) * 0.26, 0.08 + i * 0.13, -0.15 + (i % 2) * 0.1, 0.24, 0.12, 0.5)
    b.cyl("gray", 0.55, 0.0, 0.32, 0.14, 0.4, seg=10)
    return [("site_materials", b, (0, 0, 0))]


def vehicle_lift(B, tube):
    b = B()
    for x in (-0.9, 0.9):
        b.box("red_paint", x, 1.1, 0.0, 0.14, 2.2, 0.2)
        tube(b, "steel", (x, 0.6, 0.0), (x * 0.55, 0.62, -0.35), 0.03)
        tube(b, "steel", (x, 0.6, 0.0), (x * 0.55, 0.62, 0.35), 0.03)
    b.box("red_paint", 0, 2.25, 0.0, 1.95, 0.1, 0.2)
    b.box("metal_dark", 0, 0.02, 0, 1.95, 0.04, 0.9)
    return [("vehicle_lift", b, (0, 0, 0))]


def pallet_rack(B, tube):
    b = B()
    for x in (-0.45, 0.45):
        for z in (-0.38, 0.38):
            b.box("fabric_blue", x, 1.1, z, 0.05, 2.2, 0.05)
    for y in (0.12, 0.95, 1.8):
        b.box("red_paint", 0, y, 0, 0.95, 0.05, 0.8)
        b.box("wood", 0, y + 0.06, 0, 0.8, 0.08, 0.7)
        b.box("fabric_tan", 0, y + 0.3, 0, 0.7, 0.42, 0.6)
    return [("pallet_rack", b, (0, 0, 0))]


def surf_rack(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.05, 0.1, 0.9, 0.1, 0.4)
    for x in (-0.4, 0.4):
        b.box("wood_dark", x, 0.8, 0.25, 0.06, 1.6, 0.06)
    for i, m in enumerate(("teal", "paint_c", "red_paint")):
        tube(b, m, (-0.25 + i * 0.25, 0.1, 0.05), (-0.25 + i * 0.25, 1.75, 0.22), 0.1)
    return [("surf_rack", b, (0, 0, 0))]


def ski_rack(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.05, 0.15, 0.9, 0.1, 0.3)
    b.box("wood_dark", 0, 1.3, 0.25, 0.9, 0.08, 0.1)
    for x in (-0.4, 0.4):
        b.box("wood_dark", x, 0.7, 0.25, 0.06, 1.4, 0.06)
    for i in range(4):
        x = -0.3 + i * 0.2
        tube(b, "red_paint" if i % 2 else "fabric_blue", (x, 0.1, 0.1), (x + 0.03, 1.6, 0.2), 0.03)
        tube(b, "steel", (x + 0.08, 0.1, 0.05), (x + 0.1, 1.3, 0.15), 0.012)
    return [("ski_rack", b, (0, 0, 0))]


def captain_wheel(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.5, 0.1, 0.25, 1.0, 0.25)
    b.cyl("brass", 0, 1.0, 0.1, 0.05, 0.08, seg=8)
    import math
    for i in range(8):
        a = i * math.pi / 4
        tube(b, "wood", (0, 1.1, -0.05), (math.cos(a) * 0.42, 1.1 + math.sin(a) * 0.42, -0.05), 0.025)
    for i in range(16):
        a = i * math.pi / 8
        a2 = (i + 1) * math.pi / 8
        tube(b, "wood", (math.cos(a) * 0.32, 1.1 + math.sin(a) * 0.32, -0.05), (math.cos(a2) * 0.32, 1.1 + math.sin(a2) * 0.32, -0.05), 0.03)
    return [("captain_wheel", b, (0, 0, 0))]


# ---------------------------------------------------------------- shop, civic, electronics
def slot_machine(B, tube):
    b = B()
    b.box("red_paint", 0, 0.65, 0.05, 0.6, 1.3, 0.55)
    b.box("black", 0, 1.0, -0.23, 0.48, 0.4, 0.02)
    for i in range(3):
        b.box("ivory", -0.15 + i * 0.15, 1.0, -0.245, 0.12, 0.3, 0.01)
    b.box("brass", 0, 1.38, 0.05, 0.62, 0.16, 0.57)
    b.box("lamp_shade", 0, 1.38, -0.235, 0.5, 0.1, 0.01)
    b.box("black", 0, 0.7, -0.26, 0.4, 0.06, 0.08)
    tube(b, "steel", (0.33, 0.85, 0.0), (0.38, 1.15, 0.0), 0.02)
    b.sphere("red_paint", 0.38, 1.17, 0.0, 0.05, 3, 6)
    return [("slot_machine", b, (0, 0, 0))]


def phone(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.38, 0.1, 0.45, 0.76, 0.35)
    b.box("wood", 0, 0.78, 0.1, 0.5, 0.04, 0.4)
    b.box("black", 0, 0.83, 0.12, 0.22, 0.06, 0.18)
    b.box("black", 0, 0.88, 0.06, 0.22, 0.04, 0.05)
    b.box("black", 0, 0.88, 0.18, 0.22, 0.04, 0.05)
    b.box("ivory", 0, 0.865, 0.12, 0.1, 0.005, 0.1)
    return [("phone", b, (0, 0, 0))]


def security_light(B, tube):
    b = B()
    b.box("metal_dark", 0, 0.05, 0.3, 0.2, 0.1, 0.2)
    b.cyl("metal_dark", 0, 0.1, 0.3, 0.04, 2.2, seg=8)
    b.box("metal_dark", 0, 2.25, 0.18, 0.3, 0.2, 0.2)
    b.box("lamp_shade", 0, 2.22, 0.075, 0.26, 0.14, 0.01)
    b.box("black", 0.12, 2.4, 0.2, 0.06, 0.06, 0.06)          # the motion eye
    return [("security_light", b, (0, 0, 0))]


def security_camera(B, tube):
    b = B()
    b.box("white", 0, 2.55, 0.0, 0.12, 0.1, 0.12)
    tube(b, "white", (0.0, 2.52, 0.0), (0.0, 2.42, -0.1), 0.02)
    b.box("white", 0, 2.38, -0.18, 0.12, 0.1, 0.24)
    b.box("black", 0, 2.38, -0.305, 0.08, 0.06, 0.01)
    b.sphere("red_paint", 0.04, 2.42, -0.3, 0.01, 2, 4)
    return [("security_camera", b, (0, 0, 0))]


def motion_sensor(B, tube):
    b = B()
    b.box("white", 0, 2.56, 0.0, 0.14, 0.08, 0.14)
    b.sphere("ivory", 0, 2.5, 0.0, 0.06, 3, 8)
    b.sphere("red_paint", 0.05, 2.53, -0.05, 0.01, 2, 4)
    return [("motion_sensor", b, (0, 0, 0))]


def burglar_alarm(B, tube):
    b = B()
    b.box("white", 0, 2.5, 0.0, 0.26, 0.18, 0.08)
    b.box("red_paint", 0, 2.5, -0.045, 0.22, 0.14, 0.01)
    b.box("lamp_shade", 0, 2.6, -0.02, 0.1, 0.03, 0.04)
    return [("burglar_alarm", b, (0, 0, 0))]


def safe(B, tube):
    b = B()
    b.box("metal_dark", 0, 0.4, 0.05, 0.6, 0.8, 0.6)
    b.box("gray", 0, 0.4, -0.255, 0.5, 0.7, 0.02)
    b.cyl("steel", -0.05, 0.4, -0.27, 0.07, 0.03, seg=12)
    b.box("steel", 0.15, 0.4, -0.275, 0.12, 0.03, 0.03)
    for y in (0.15, 0.65):
        b.box("steel", -0.25, y, -0.27, 0.04, 0.08, 0.03)
    return [("safe", b, (0, 0, 0))]


def vault_safe(B, tube):
    b = B()
    b.box("metal_dark", 0, 1.0, 0.1, 0.95, 2.0, 0.6)
    b.cyl("steel", 0, 0.25, -0.2, 0.28, 0.06, seg=20)
    b.box("steel", 0, 1.0, -0.21, 0.8, 1.7, 0.02)
    b.cyl("silver", 0, 1.0, -0.24, 0.16, 0.04, seg=14)
    for i in range(4):
        import math
        a = i * math.pi / 2
        tube(b, "silver", (0, 1.0, -0.26), (math.cos(a) * 0.26, 1.0 + math.sin(a) * 0.26, -0.26), 0.02)
    return [("vault_safe", b, (0, 0, 0))]


def medical_cabinet(B, tube):
    b = B()
    b.box("white", 0, 0.9, 0.12, 0.7, 1.8, 0.45)
    b.box("glass", -0.17, 1.2, -0.11, 0.33, 1.0, 0.01)
    b.box("glass", 0.17, 1.2, -0.11, 0.33, 1.0, 0.01)
    for y in (0.85, 1.2, 1.55):
        b.box("baby_blue", 0, y, 0.12, 0.64, 0.02, 0.4)
        b.box("white", -0.15, y + 0.08, 0.1, 0.1, 0.14, 0.1)
        b.box("red_paint", 0.12, y + 0.06, 0.1, 0.14, 0.1, 0.1)
    b.box("red_paint", 0, 1.72, -0.115, 0.14, 0.04, 0.01)
    b.box("red_paint", 0, 1.72, -0.115, 0.04, 0.14, 0.01)
    return [("medical_cabinet", b, (0, 0, 0))]


def first_aid_kit(B, tube):
    b = B()
    b.box("white", 0, 1.25, 0.35, 0.45, 0.35, 0.14)
    b.box("red_paint", 0, 1.25, 0.275, 0.1, 0.24, 0.01)
    b.box("red_paint", 0, 1.25, 0.275, 0.24, 0.1, 0.01)
    b.box("wood_dark", 0, 0.62, 0.44, 0.08, 1.24, 0.08)          # the post it hangs on
    return [("first_aid_kit", b, (0, 0, 0))]


def public_toilet(B, tube):
    b = B()
    for x in (-0.47, 0.47):
        b.box("gray", x, 1.1, 0.0, 0.05, 2.2, 0.95)
    b.box("gray", 0, 1.1, 0.47, 0.95, 2.2, 0.05)
    b.box("gray", 0, 2.22, 0.0, 0.98, 0.05, 0.98)
    b.box("tile_a", 0, 0.01, 0.0, 0.9, 0.02, 0.9)
    b.box("porcelain", 0, 0.2, 0.2, 0.34, 0.4, 0.5)          # the bowl at the back: the user sits on it facing out
    b.box("white", 0, 0.42, 0.16, 0.38, 0.04, 0.46)
    b.box("porcelain", 0, 0.58, 0.42, 0.42, 0.44, 0.06)
    b.box("gray", -0.42, 1.1, -0.44, 0.08, 2.0, 0.06)          # the door, swung open against the wall
    b.box("gray", -0.2, 1.1, -0.47, 0.44, 2.0, 0.04)
    return [("public_toilet", b, (0, 0, 0))]


def shop_stall(B, tube):
    b = B()
    b.box("wood", 0, 0.45, -0.1, 0.95, 0.9, 0.5)
    b.box("wood_light", 0, 0.92, -0.1, 0.98, 0.04, 0.55)
    for x in (-0.45, 0.45):
        b.box("wood_dark", x, 1.2, 0.3, 0.06, 2.4, 0.06)
    b.box("red_paint", 0, 2.25, 0.0, 1.0, 0.04, 0.85)
    for i in range(4):
        b.box("white" if i % 2 else "red_paint", -0.375 + i * 0.25, 2.15, -0.42, 0.25, 0.2, 0.02)
    for i, m in enumerate(("paint_a", "paint_b", "paint_c")):
        b.box(m, -0.3 + i * 0.3, 1.0, -0.12, 0.2, 0.12, 0.25)
    b.box("wood_dark", 0, 1.2, 0.3, 0.9, 0.5, 0.04)
    return [("shop_stall", b, (0, 0, 0))]


def souvenir_stand(B, tube):
    b = B()
    b.box("wood", 0, 0.45, 0.0, 0.85, 0.9, 0.5)
    b.box("wood_light", 0, 0.92, 0.0, 0.9, 0.04, 0.55)
    b.box("wood_dark", 0, 1.35, 0.2, 0.85, 0.85, 0.06)          # the display board
    for i in range(6):
        b.box(("paint_a", "paint_b", "paint_c", "teal", "brass", "red_paint")[i], -0.27 + (i % 3) * 0.27, 1.2 + (i // 3) * 0.3, 0.16, 0.18, 0.2, 0.02)
    b.cyl("ivory", -0.25, 0.94, -0.1, 0.06, 0.14, seg=8)
    b.cyl("teal", 0.0, 0.94, -0.1, 0.05, 0.1, seg=8)
    b.box("paint_c", 0.25, 0.98, -0.1, 0.14, 0.1, 0.14)
    return [("souvenir_stand", b, (0, 0, 0))]
