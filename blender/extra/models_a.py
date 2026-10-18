"""Extra furniture models, part A (bedroom / living / outdoor). Each fn(B, tube) returns [(name, Builder, pivot)].
Coordinates are GODOT coords (x right, y up, z back); FRONT faces -Z. B = Builder class, tube = angled-cylinder helper
(both injected by build_extra.py)."""


def legs(b, mat, xs, zs, h, t):
    for x in xs:
        for z in zs:
            b.box(mat, x, h / 2, z, t, h, t)


def crib(B, tube):
    b = B()
    b.box("wood_light", 0, 0.34, 0, 0.9, 0.04, 1.8)
    b.box("white", 0, 0.42, 0, 0.84, 0.1, 1.72)
    b.box("baby_blue", 0, 0.49, -0.2, 0.8, 0.04, 1.2)
    legs(b, "wood", (-0.43, 0.43), (-0.88, 0.88), 0.34, 0.06)
    for x in (-0.43, 0.43):
        for i in range(12):
            z = -0.8 + i * 0.145
            b.box("wood_light", x, 0.75, z, 0.025, 0.5, 0.025)
        b.box("wood", x, 1.02, 0, 0.05, 0.05, 1.8)
        b.box("wood", x, 0.5, 0, 0.04, 0.04, 1.8)
    b.box("wood", 0, 0.75, 0.9, 0.9, 0.75, 0.05)
    for i in range(6):
        b.box("wood_light", -0.375 + i * 0.15, 0.75, -0.9, 0.025, 0.5, 0.025)
    b.box("wood", 0, 1.02, -0.9, 0.9, 0.05, 0.05)
    b.box("white", 0, 0.54, 0.7, 0.4, 0.07, 0.25)
    return [("crib", b, (0, 0, 0))]


def dresser(B, tube):
    b = B()
    b.box("wood", 0, 0.42, 0.1, 0.92, 0.84, 0.5)
    b.box("wood_dark", 0, 0.86, 0.1, 0.98, 0.04, 0.56)
    for i in range(3):
        y = 0.18 + i * 0.25
        b.box("wood_light", 0, y, -0.16, 0.8, 0.21, 0.02)
        b.box("brass", -0.2, y, -0.18, 0.06, 0.03, 0.03)
        b.box("brass", 0.2, y, -0.18, 0.06, 0.03, 0.03)
    legs(b, "wood_dark", (-0.4, 0.4), (-0.12, 0.32), 0.05, 0.06)
    b.box("pot", 0.3, 0.93, 0.1, 0.12, 0.1, 0.12)
    b.box("book_blue", -0.2, 0.92, 0.1, 0.3, 0.06, 0.2)
    return [("dresser", b, (0, 0, 0))]


def wardrobe(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.95, 0.12, 0.95, 1.9, 0.55)
    b.box("wood", -0.23, 0.95, -0.17, 0.44, 1.8, 0.03)
    b.box("wood", 0.23, 0.95, -0.17, 0.44, 1.8, 0.03)
    b.box("brass", -0.05, 0.95, -0.2, 0.03, 0.2, 0.03)
    b.box("brass", 0.05, 0.95, -0.2, 0.03, 0.2, 0.03)
    b.box("wood_dark", 0, 1.94, 0.12, 1.0, 0.06, 0.6)
    b.box("wood_dark", 0, 0.03, -0.12, 0.95, 0.06, 0.06)
    return [("wardrobe", b, (0, 0, 0))]


def nightstand(B, tube):
    b = B()
    b.box("wood", 0, 0.28, 0.1, 0.5, 0.5, 0.42)
    b.box("wood_dark", 0, 0.54, 0.1, 0.54, 0.04, 0.46)
    b.box("wood_light", 0, 0.38, -0.11, 0.42, 0.18, 0.02)
    b.box("brass", 0, 0.38, -0.13, 0.08, 0.025, 0.025)
    b.box("wood_light", 0, 0.16, -0.11, 0.42, 0.18, 0.02)
    b.box("brass", 0, 0.16, -0.13, 0.08, 0.025, 0.025)
    b.cyl("steel", -0.1, 0.56, 0.1, 0.07, 0.03)
    b.cyl("steel", -0.1, 0.59, 0.1, 0.015, 0.2, seg=6)
    b.cyl("lamp_shade", -0.1, 0.76, 0.1, 0.13, 0.17, r2=0.07)
    b.box("white", 0.14, 0.6, 0.0, 0.1, 0.1, 0.07)
    return [("nightstand", b, (0, 0, 0))]


def armchair(B, tube):
    b = B()
    b.box("fabric_blue", 0, 0.22, 0, 0.9, 0.3, 0.85)
    b.box("fabric_blue", 0, 0.46, -0.04, 0.6, 0.16, 0.65)
    b.box("fabric_blue", 0, 0.7, 0.36, 0.9, 0.62, 0.16)
    for x in (-0.38, 0.38):
        b.box("fabric_blue", x, 0.46, 0, 0.14, 0.4, 0.85)
    legs(b, "wood_dark", (-0.38, 0.38), (-0.35, 0.35), 0.08, 0.07)
    b.box("fabric_red", 0.18, 0.7, 0.24, 0.3, 0.3, 0.07)
    return [("armchair", b, (0, 0, 0))]


def coffee_table(B, tube):
    b = B()
    b.box("wood", 0, 0.38, 0, 1.5, 0.05, 0.7)
    b.box("wood_dark", 0, 0.12, 0, 1.4, 0.03, 0.6)
    legs(b, "wood_dark", (-0.7, 0.7), (-0.28, 0.28), 0.38, 0.06)
    b.cyl("white", 0.4, 0.405, 0.05, 0.05, 0.08)
    b.box("book_red", -0.3, 0.43, 0, 0.3, 0.03, 0.22)
    b.box("book_green", -0.3, 0.46, 0, 0.26, 0.03, 0.2)
    b.cyl("pot", 0.1, 0.405, -0.15, 0.07, 0.05, r2=0.09)
    return [("coffee_table", b, (0, 0, 0))]


def dining_chair(B, tube):
    b = B()
    b.box("fabric_tan", 0, 0.46, 0, 0.44, 0.07, 0.44)
    b.box("wood", 0, 0.42, 0, 0.46, 0.03, 0.46)
    legs(b, "wood_dark", (-0.19, 0.19), (-0.19, 0.19), 0.42, 0.045)
    b.box("wood", -0.19, 0.9, 0.2, 0.045, 0.9, 0.045)
    b.box("wood", 0.19, 0.9, 0.2, 0.045, 0.9, 0.045)
    b.box("fabric_tan", 0, 0.85, 0.2, 0.34, 0.3, 0.05)
    b.box("wood", 0, 1.03, 0.2, 0.44, 0.07, 0.05)
    return [("dining_chair", b, (0, 0, 0))]


def bar_stool(B, tube):
    b = B()
    b.cyl("fabric_red", 0, 0.72, 0, 0.18, 0.08)
    b.cyl("steel", 0, 0.0, 0, 0.2, 0.03)
    b.cyl("steel", 0, 0.03, 0, 0.025, 0.69, seg=6)
    b.cyl("steel", 0, 0.28, 0, 0.16, 0.025, seg=10)
    return [("bar_stool", b, (0, 0, 0))]


def single_bed(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.25, 0, 0.95, 0.3, 1.95)
    b.box("white", 0, 0.45, -0.03, 0.88, 0.2, 1.85)
    b.box("wood", 0, 0.6, 0.95, 0.95, 0.6, 0.08)
    b.box("wood", 0, 0.4, -0.97, 0.95, 0.3, 0.06)
    b.box("white", 0, 0.59, 0.68, 0.6, 0.1, 0.4)
    b.box("fabric_green", 0, 0.58, -0.28, 0.9, 0.06, 1.2)
    return [("single_bed", b, (0, 0, 0))]


def bunk_bed(B, tube):
    b = B()
    for x in (-0.46, 0.46):
        for z in (-0.95, 0.95):
            b.box("wood", x, 0.9, z, 0.07, 1.8, 0.07)
    for y in (0.3, 1.15):
        b.box("wood_dark", 0, y, 0, 0.92, 0.07, 1.9)
        b.box("white", 0, y + 0.1, 0, 0.84, 0.12, 1.82)
        b.box("white", 0, y + 0.19, 0.7, 0.5, 0.08, 0.35)
    b.box("fabric_blue", 0, 0.46, -0.3, 0.86, 0.05, 1.1)
    b.box("fabric_red", 0, 1.31, -0.3, 0.86, 0.05, 1.1)
    for x in (-0.46, 0.46):
        b.box("wood", x, 1.5, 0, 0.04, 0.2, 1.9)
    for i in range(5):
        b.box("wood", 0.46, 0.25 + i * 0.3, -0.55, 0.05, 0.04, 0.3)
    return [("bunk_bed", b, (0, 0, 0))]


def desk(B, tube):
    b = B()
    b.box("wood", 0, 0.74, 0.05, 0.96, 0.05, 0.62)
    b.box("wood_dark", -0.4, 0.37, 0.05, 0.14, 0.72, 0.58)
    b.box("wood_dark", 0.46, 0.37, 0.05, 0.04, 0.72, 0.58)
    for i in range(3):
        b.box("wood_light", -0.4, 0.15 + i * 0.22, -0.25, 0.12, 0.17, 0.02)
        b.box("brass", -0.4, 0.15 + i * 0.22, -0.27, 0.05, 0.02, 0.02)
    b.cyl("steel", 0.3, 0.765, 0.3, 0.07, 0.02)
    b.cyl("steel", 0.3, 0.78, 0.3, 0.012, 0.3, seg=6)
    b.cyl("lamp_shade", 0.3, 1.0, 0.3, 0.1, 0.1, r2=0.04)
    b.box("canvas", -0.05, 0.78, -0.02, 0.35, 0.02, 0.25)
    b.cyl("pot", 0.1, 0.765, 0.25, 0.04, 0.09)
    return [("desk", b, (0, 0, 0))]


def bookcase_tall(B, tube):
    b = B()
    for x in (-0.47, 0.47):
        b.box("wood_dark", x, 1.05, 0.08, 0.06, 2.1, 0.36)
    b.box("wood_dark", 0, 1.05, 0.25, 0.94, 2.1, 0.03)
    levels = [0.03, 0.4, 0.75, 1.1, 1.45, 1.8, 2.08]
    for y in levels:
        b.box("wood", 0, y, 0.08, 0.94, 0.05, 0.36)
    cols = ["book_red", "book_blue", "book_green", "book_yellow", "paint_a", "paint_b"]
    n = 0
    for li in range(1, len(levels)):
        y0 = levels[li - 1] + 0.025
        x = -0.4
        while x < 0.36:
            w = 0.05 + 0.02 * ((n * 7) % 3)
            h = 0.2 + 0.04 * ((n * 5) % 4)
            b.box(cols[n % len(cols)], x + w / 2, y0 + h / 2, 0.06, w, h, 0.22)
            x += w + 0.012
            n += 1
    return [("bookcase_tall", b, (0, 0, 0))]


def piano(B, tube):
    b = B()
    b.box("piano", 0, 0.7, 0.2, 1.85, 1.2, 0.52)
    b.box("piano", 0, 1.33, 0.2, 1.9, 0.06, 0.56)
    b.box("piano", 0, 0.7, -0.1, 1.8, 0.1, 0.34)
    b.box("ivory", 0, 0.78, -0.2, 1.62, 0.04, 0.2)
    for i in range(14):
        b.box("black", -0.7 + i * 0.107, 0.815, -0.16, 0.05, 0.03, 0.11)
    for x in (-0.85, 0.85):
        b.box("piano", x, 0.35, -0.06, 0.08, 0.7, 0.12)
    b.box("brass", 0, 0.5, -0.07, 0.4, 0.02, 0.04)
    b.box("piano", 0, 1.1, -0.06, 1.0, 0.25, 0.02)
    b.box("canvas", 0, 1.1, -0.075, 0.5, 0.2, 0.005)
    b.cyl("fabric_red", 0, 0.42, -0.39, 0.17, 0.07)
    b.cyl("wood_dark", 0, 0.0, -0.39, 0.012, 0.42, seg=6)
    b.cyl("wood_dark", 0, 0.0, -0.39, 0.12, 0.02, seg=8)
    return [("piano", b, (0, 0, 0))]


def guitar_stand(B, tube):
    b = B()
    tube(b, "metal_dark", (0, 0.5, 0.1), (-0.22, 0.0, 0.1), 0.018)
    tube(b, "metal_dark", (0, 0.5, 0.1), (0.22, 0.0, 0.1), 0.018)
    tube(b, "metal_dark", (0, 0.5, 0.1), (0, 0.0, 0.32), 0.018)
    tube(b, "metal_dark", (0, 0.5, 0.1), (0, 0.0, -0.12), 0.018)
    b.cyl("wood_light", -0.05, 0.38, 0.1, 0.17, 0.04, r2=0.17, seg=12)
    b.sphere("wood_light", -0.05, 0.56, 0.1, 0.17, 4, 8)
    b.cyl("wood", -0.05, 0.65, 0.1, 0.14, 0.04, r2=0.14, seg=12)
    b.box("black", -0.05, 0.56, 0.065, 0.07, 0.07, 0.01)
    tube(b, "wood_dark", (-0.05, 0.68, 0.1), (-0.05, 1.32, 0.1), 0.025)
    b.box("black", -0.05, 1.38, 0.1, 0.07, 0.14, 0.03)
    b.box("black", 0.33, 0.2, 0.1, 0.3, 0.4, 0.22)
    b.box("gray", 0.33, 0.21, -0.012, 0.24, 0.3, 0.01)
    return [("guitar_stand", b, (0, 0, 0))]


def fishing_spot(B, tube):
    b = B()
    b.box("soil", 0, 0.06, 0.2, 1.95, 0.12, 0.62)
    b.box("water", 0, 0.1, 0.2, 1.8, 0.04, 0.5)
    b.box("stone", 0, 0.1, 0.52, 1.95, 0.14, 0.1)
    b.box("stone", -0.93, 0.1, 0.2, 0.1, 0.14, 0.62)
    b.box("stone", 0.93, 0.1, 0.2, 0.1, 0.14, 0.62)
    b.box("stone", 0, 0.1, -0.1, 1.95, 0.14, 0.08)
    for i in range(8):
        b.box("wood_light", -0.7 + i * 0.2, 0.09, -0.32, 0.18, 0.05, 0.34)
    for x in (-0.8, 0.8):
        b.box("wood_dark", x, 0.1, -0.45, 0.07, 0.2, 0.07)
    for x, z in ((-0.7, 0.4), (-0.6, 0.45), (0.7, 0.4), (0.8, 0.42)):
        b.box("crop_green", x, 0.42, z, 0.02, 0.6, 0.02)
        b.box("wood_dark", x, 0.74, z, 0.045, 0.14, 0.045)
    b.box("leaf", 0.3, 0.13, 0.15, 0.2, 0.01, 0.15)
    b.box("leaf", -0.2, 0.13, 0.3, 0.16, 0.01, 0.12)
    return [("fishing_spot", b, (0, 0, 0))]


def garden_plot(B, tube):
    b = B()
    b.box("soil", 0, 0.11, 0, 1.84, 0.2, 0.84)
    b.box("wood", 0, 0.13, -0.45, 1.96, 0.26, 0.06)
    b.box("wood", 0, 0.13, 0.45, 1.96, 0.26, 0.06)
    b.box("wood", -0.95, 0.13, 0, 0.06, 0.26, 0.96)
    b.box("wood", 0.95, 0.13, 0, 0.06, 0.26, 0.96)
    for ix in range(6):
        for iz in range(2):
            x = -0.75 + ix * 0.3
            z = -0.18 + iz * 0.36
            if (ix + iz) % 3 == 0:
                b.sphere("crop_orange", x, 0.34, z, 0.1, 3, 6)
                b.box("crop_green", x, 0.42, z, 0.04, 0.1, 0.04)
            else:
                b.sphere("crop_green", x, 0.34, z, 0.13, 3, 6)
    b.box("wood_dark", 0.8, 0.5, -0.45, 0.04, 0.5, 0.04)
    b.box("canvas", 0.8, 0.72, -0.45, 0.16, 0.12, 0.02)
    return [("garden_plot", b, (0, 0, 0))]


def mailbox(B, tube):
    b = B()
    b.box("wood", 0, 0.5, 0, 0.09, 1.0, 0.09)
    b.box("wood", 0, 1.0, 0.0, 0.18, 0.04, 0.6)
    b.box("teal", 0, 1.15, 0, 0.3, 0.25, 0.5)
    b.box("teal", 0, 1.29, 0, 0.26, 0.04, 0.46)
    b.box("black", 0, 1.13, -0.255, 0.22, 0.12, 0.01)
    b.box("red_paint", 0.17, 1.28, 0.1, 0.02, 0.16, 0.04)
    b.box("red_paint", 0.17, 1.37, 0.1, 0.02, 0.04, 0.12)
    b.box("white", 0, 1.2, 0.2, 0.2, 0.06, 0.12)
    return [("mailbox", b, (0, 0, 0))]


def grill(B, tube):
    b = B()
    for x, z in ((-0.25, -0.15), (0.25, -0.15), (0, 0.25)):
        tube(b, "metal_dark", (x * 0.4, 0.62, z * 0.4), (x, 0.0, z), 0.022)
    b.cyl("black", 0, 0.6, 0, 0.33, 0.2, r2=0.36, seg=14)
    b.cyl("steel", 0, 0.8, 0, 0.35, 0.04, seg=14)
    b.sphere("black", 0, 0.82, 0, 0.35, 4, 12)
    b.box("black", 0.0, 1.15, -0.34, 0.2, 0.04, 0.04)
    b.box("wood_dark", 0.0, 0.62, -0.42, 0.34, 0.04, 0.12)
    b.box("wood", 0.45, 0.72, 0.0, 0.1, 0.04, 0.5)
    b.box("fire", 0, 0.72, 0, 0.3, 0.03, 0.3)
    return [("grill", b, (0, 0, 0))]


def hot_tub(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.36, 0, 1.9, 0.72, 1.9)
    b.box("white", 0, 0.76, 0, 1.9, 0.08, 1.9)
    b.box("water", 0, 0.78, 0, 1.6, 0.05, 1.6)
    b.box("white", 0, 0.5, 0, 1.2, 0.01, 1.2)
    b.cyl("white", -0.5, 0.78, -0.5, 0.05, 0.03)
    b.cyl("white", 0.5, 0.78, 0.5, 0.05, 0.03)
    for i in range(4):
        b.box("wood", -0.75 + i * 0.5, 0.35, -0.955, 0.4, 0.55, 0.02)
    b.box("wood_light", 0, 0.1, -1.05, 0.9, 0.2, 0.2)
    b.box("steel", 0.82, 0.88, 0.82, 0.06, 0.1, 0.06)
    return [("hot_tub", b, (0, 0, 0))]


def mirror(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.95, 0.12, 0.62, 1.7, 0.05)
    b.box("glass", 0, 0.98, 0.09, 0.5, 1.5, 0.01)
    b.box("silver", 0, 0.98, 0.1, 0.5, 1.5, 0.005)
    b.box("wood_dark", -0.28, 0.06, 0.12, 0.06, 0.12, 0.4)
    b.box("wood_dark", 0.28, 0.06, 0.12, 0.06, 0.12, 0.4)
    b.box("brass", 0, 1.82, 0.1, 0.1, 0.06, 0.04)
    return [("mirror", b, (0, 0, 0))]


def fireplace(B, tube):
    b = B()
    b.box("brick", 0, 0.65, 0.2, 1.9, 1.3, 0.5)
    b.box("brick", 0, 1.8, 0.35, 0.9, 1.0, 0.25)
    b.box("wood_dark", 0, 1.32, 0.12, 1.98, 0.08, 0.6)
    b.box("black", 0, 0.4, -0.04, 0.9, 0.62, 0.05)
    b.box("fire", -0.15, 0.2, -0.07, 0.25, 0.25, 0.03)
    b.box("paint_c", 0.12, 0.18, -0.07, 0.22, 0.34, 0.03)
    b.box("fire", 0.0, 0.1, -0.08, 0.7, 0.1, 0.03)
    b.box("stone", 0, 0.04, -0.3, 1.7, 0.08, 0.45)
    b.box("wood_dark", 0.55, 0.12, -0.25, 0.2, 0.16, 0.14)
    b.box("brass", -0.7, 1.4, 0.1, 0.12, 0.12, 0.08)
    return [("fireplace", b, (0, 0, 0))]


def stereo(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.22, 0.1, 0.9, 0.44, 0.4)
    b.box("black", 0, 0.5, 0.1, 0.5, 0.1, 0.34)
    b.box("gray", 0, 0.6, 0.1, 0.5, 0.08, 0.34)
    b.box("screen", 0, 0.5, -0.075, 0.3, 0.05, 0.01)
    for x in (-0.37, 0.37):
        b.box("black", x, 0.55, 0.1, 0.22, 0.9, 0.3)
        b.cyl("gray", x, 0.4, -0.05, 0.07, 0.02, seg=10)
        b.cyl("gray", x, 0.8, -0.05, 0.04, 0.02, seg=8)
    return [("stereo", b, (0, 0, 0))]


def bar_counter(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.52, 0.2, 1.9, 1.04, 0.5)
    b.box("wood_light", 0, 1.07, 0.1, 2.0, 0.06, 0.7)
    b.box("brass", 0, 0.18, -0.12, 1.8, 0.03, 0.03)
    b.box("wood", 0, 0.55, -0.07, 1.8, 0.7, 0.02)
    for i in range(5):
        b.box("wood_dark", -0.7 + i * 0.35, 0.55, -0.085, 0.28, 0.6, 0.01)
    for i, c in enumerate(("paint_a", "leaf", "paint_c", "paint_b", "book_red")):
        b.cyl(c, -0.7 + i * 0.3, 1.1, 0.25, 0.05, 0.22, r2=0.03, seg=8)
    for x in (0.5, 0.65, 0.8):
        b.cyl("glass", x, 1.1, -0.05, 0.035, 0.1, seg=8)
    return [("bar_counter", b, (0, 0, 0))]


def ceiling_fan(B, tube):
    b = B()
    b.cyl("steel", 0, 2.5, 0, 0.12, 0.08)
    b.cyl("steel", 0, 2.35, 0, 0.015, 0.2, seg=6)
    b.cyl("wood_dark", 0, 2.22, 0, 0.1, 0.14, seg=10)
    b.sphere("lamp_shade", 0, 2.2, 0, 0.1, 3, 8)
    b.box("wood_light", 0, 2.32, 0, 0.95, 0.02, 0.16)
    b.box("wood_light", 0, 2.32, 0, 0.16, 0.02, 0.95)
    b.box("wood_dark", 0.5, 2.325, 0, 0.1, 0.015, 0.14)
    b.box("wood_dark", -0.5, 2.325, 0, 0.1, 0.015, 0.14)
    return [("ceiling_fan", b, (0, 0, 0))]


def pendant_light(B, tube):
    b = B()
    b.cyl("steel", 0, 2.58, 0, 0.06, 0.04)
    b.box("black", 0, 2.25, 0, 0.012, 0.7, 0.012)
    b.cyl("lamp_shade", 0, 1.88, 0, 0.3, 0.2, r2=0.07, seg=14)
    b.sphere("white", 0, 1.9, 0, 0.07, 3, 8)
    return [("pendant_light", b, (0, 0, 0))]
