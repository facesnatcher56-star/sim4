"""Extra object models, part B (appliances / hobby / utility). Same conventions as models_a.py."""


def washing_machine(B, tube):
    b = B()
    b.box("white", 0, 0.45, 0.05, 0.8, 0.9, 0.7)
    b.box("gray", 0, 0.92, 0.05, 0.82, 0.04, 0.72)
    b.box("steel", 0, 0.5, -0.305, 0.5, 0.5, 0.02)
    b.box("screen", 0, 0.5, -0.32, 0.4, 0.4, 0.01)
    b.box("glass", 0, 0.5, -0.33, 0.34, 0.34, 0.005)
    b.box("black", 0, 0.8, -0.3, 0.7, 0.12, 0.02)
    b.box("steel", 0.22, 0.8, -0.32, 0.08, 0.08, 0.03)
    b.box("paint_b", -0.25, 0.8, -0.32, 0.12, 0.05, 0.02)
    legs(b, "gray", (-0.35, 0.35), (-0.25, 0.35), 0.03, 0.06)
    return [("washing_machine", b, (0, 0, 0))]


def legs(b, mat, xs, zs, h, t):
    for x in xs:
        for z in zs:
            b.box(mat, x, h / 2, z, t, h, t)


def microwave_cart(B, tube):
    b = B()
    b.box("wood", 0, 0.36, 0.1, 0.8, 0.72, 0.55)
    b.box("wood_light", 0, 0.38, -0.18, 0.7, 0.55, 0.02)
    b.box("brass", 0.28, 0.45, -0.2, 0.03, 0.14, 0.03)
    b.box("wood_dark", 0, 0.74, 0.1, 0.86, 0.04, 0.6)
    b.box("steel", 0, 0.94, 0.1, 0.62, 0.36, 0.46)
    b.box("black", -0.07, 0.94, -0.135, 0.38, 0.28, 0.02)
    b.box("gray", 0.2, 0.94, -0.135, 0.12, 0.28, 0.02)
    b.box("screen", 0.2, 1.04, -0.147, 0.08, 0.04, 0.01)
    return [("microwave_cart", b, (0, 0, 0))]


def coffee_maker(B, tube):
    b = B()
    b.box("wood", 0, 0.36, 0.1, 0.8, 0.72, 0.55)
    b.box("stone", 0, 0.74, 0.1, 0.86, 0.04, 0.6)
    b.box("black", 0, 1.0, 0.28, 0.34, 0.48, 0.22)
    b.box("black", 0, 1.22, 0.1, 0.34, 0.08, 0.3)
    b.box("steel", 0, 0.78, 0.1, 0.22, 0.02, 0.2)
    b.cyl("glass", 0, 0.79, 0.1, 0.07, 0.2, seg=10)
    b.cyl("coffee", 0, 0.79, 0.1, 0.06, 0.12, seg=10)
    b.box("red_paint", 0.0, 1.1, 0.165, 0.05, 0.03, 0.01)
    b.cyl("white", -0.3, 0.76, -0.05, 0.05, 0.08)
    b.cyl("white", -0.18, 0.76, -0.1, 0.05, 0.08)
    b.box("wood_dark", 0.3, 0.77, 0.0, 0.14, 0.04, 0.14)
    return [("coffee_maker", b, (0, 0, 0))]


def tea_kettle(B, tube):
    b = B()
    b.box("wood_light", 0, 0.34, 0.1, 0.7, 0.04, 0.5)
    legs(b, "wood", (-0.3, 0.3), (-0.12, 0.3), 0.34, 0.05)
    b.box("wood_light", 0, 0.12, 0.1, 0.62, 0.03, 0.44)
    b.cyl("steel", 0, 0.36, 0.1, 0.14, 0.24, r2=0.1, seg=12)
    b.cyl("black", 0, 0.6, 0.1, 0.05, 0.03, seg=8)
    tube(b, "steel", (0.08, 0.5, 0.1), (0.22, 0.56, 0.1), 0.018)
    b.box("black", -0.14, 0.5, 0.1, 0.03, 0.22, 0.03)
    b.cyl("white", -0.25, 0.36, -0.05, 0.045, 0.08)
    b.cyl("white", 0.25, 0.36, -0.05, 0.045, 0.08)
    b.box("teal", 0, 0.38, -0.15, 0.2, 0.01, 0.12)
    return [("tea_kettle", b, (0, 0, 0))]


def easel_large(B, tube):
    b = B()
    for x, z in ((-0.8, -0.05), (0.8, -0.05)):
        b.box("wood", x, 0.95, z, 0.06, 1.9, 0.06)
    b.box("wood", 0, 1.9, -0.05, 1.7, 0.06, 0.06)
    tube(b, "wood", (-0.8, 0.9, -0.05), (-0.7, 0.0, 0.4), 0.025)
    tube(b, "wood", (0.8, 0.9, -0.05), (0.7, 0.0, 0.4), 0.025)
    b.box("wood", 0, 0.62, -0.1, 1.6, 0.05, 0.14)
    b.box("canvas", 0, 1.25, -0.1, 1.3, 1.1, 0.03)
    b.box("paint_a", -0.35, 1.45, -0.12, 0.45, 0.35, 0.01)
    b.box("paint_b", 0.2, 1.15, -0.12, 0.6, 0.4, 0.01)
    b.box("paint_c", 0.1, 1.55, -0.12, 0.25, 0.2, 0.01)
    b.box("leaf", -0.4, 1.0, -0.12, 0.3, 0.25, 0.01)
    b.box("wood_dark", 0.95, 0.5, -0.3, 0.3, 0.04, 0.3)
    b.cyl("paint_a", 0.9, 0.54, -0.3, 0.04, 0.05, seg=8)
    b.cyl("paint_b", 1.0, 0.54, -0.28, 0.04, 0.05, seg=8)
    return [("easel_large", b, (0, 0, 0))]


def workbench(B, tube):
    b = B()
    b.box("wood_light", 0, 0.88, 0.05, 1.9, 0.08, 0.7)
    legs(b, "wood_dark", (-0.88, 0.88), (-0.25, 0.3), 0.84, 0.08)
    b.box("wood_dark", 0, 0.2, 0.05, 1.8, 0.04, 0.6)
    b.box("wood", 0.5, 0.6, 0.05, 0.7, 0.4, 0.55)
    for i in range(2):
        b.box("wood_light", 0.5, 0.5 + i * 0.18, -0.23, 0.6, 0.15, 0.02)
        b.box("brass", 0.5, 0.5 + i * 0.18, -0.25, 0.1, 0.02, 0.02)
    b.box("wood_dark", 0, 1.5, 0.4, 1.9, 1.0, 0.04)
    b.box("steel", -0.6, 1.6, 0.37, 0.05, 0.4, 0.02)
    b.box("red_paint", -0.3, 1.55, 0.37, 0.08, 0.3, 0.03)
    b.box("steel", 0.0, 1.62, 0.37, 0.3, 0.05, 0.02)
    b.box("yellow_safety", 0.4, 1.5, 0.37, 0.1, 0.35, 0.03)
    b.box("steel", 0.7, 1.55, 0.37, 0.15, 0.3, 0.02)
    b.box("steel", -0.6, 0.97, -0.1, 0.16, 0.1, 0.14)
    b.box("black", -0.6, 1.04, -0.1, 0.05, 0.06, 0.05)
    b.box("yellow_safety", 0.1, 0.94, -0.05, 0.3, 0.04, 0.12)
    b.box("steel", 0.0, 0.94, 0.2, 0.2, 0.03, 0.05)
    return [("workbench", b, (0, 0, 0))]


def dumbbell_rack(B, tube):
    b = B()
    for x in (-0.38, 0.38):
        b.box("metal_dark", x, 0.35, 0.1, 0.05, 0.7, 0.5)
    for y in (0.15, 0.4, 0.62):
        b.box("metal_dark", 0, y, 0.1, 0.8, 0.04, 0.5)
    for i, (y, s) in enumerate(((0.2, 0.09), (0.45, 0.11), (0.67, 0.13))):
        b.box("steel", 0, y + 0.02, 0.0, 0.5, 0.025, 0.025)
        for x in (-0.22, 0.22):
            b.box("black", x, y + 0.02, 0.0, 0.1, s * 1.1, s * 1.1)
    b.box("black", 0, 0.03, -0.35, 0.6, 0.06, 0.3)
    b.cyl("black", 0.3, 0.06, -0.35, 0.12, 0.06, seg=12)
    return [("dumbbell_rack", b, (0, 0, 0))]


def pool_table(B, tube):
    b = B()
    b.box("wood_dark", 0, 0.78, 0, 1.95, 0.14, 0.95)
    b.box("felt_green", 0, 0.86, 0, 1.7, 0.02, 0.72)
    b.box("wood", 0, 0.9, -0.38, 1.85, 0.06, 0.1)
    b.box("wood", 0, 0.9, 0.38, 1.85, 0.06, 0.1)
    b.box("wood", -0.9, 0.9, 0, 0.1, 0.06, 0.8)
    b.box("wood", 0.9, 0.9, 0, 0.1, 0.06, 0.8)
    for x in (-0.88, 0.0, 0.88):
        for z in (-0.4, 0.4):
            if x == 0.0 and False:
                continue
            b.cyl("black", x, 0.87, z, 0.06, 0.03, seg=8)
    legs(b, "wood_dark", (-0.8, 0.8), (-0.3, 0.3), 0.72, 0.12)
    cols = ("paint_a", "paint_b", "paint_c", "white", "book_green", "black")
    k = 0
    for row in range(3):
        for j in range(row + 1):
            b.sphere(cols[k % len(cols)], 0.45 + row * 0.08, 0.895, (j - row / 2.0) * 0.1, 0.04, 3, 6)
            k += 1
    b.sphere("white", -0.45, 0.895, 0.0, 0.04, 3, 6)
    tube(b, "wood_light", (-0.5, 0.95, 0.3), (-0.95, 0.88, 0.5), 0.012)
    return [("pool_table", b, (0, 0, 0))]


def fire_extinguisher(B, tube):
    b = B()
    b.box("gray", 0, 0.015, 0.2, 0.34, 0.03, 0.2)
    b.box("white", 0, 0.5, 0.4, 0.34, 1.0, 0.03)
    b.cyl("red_paint", 0, 0.05, 0.2, 0.09, 0.4, r2=0.09, seg=12)
    b.sphere("red_paint", 0, 0.45, 0.2, 0.09, 3, 10)
    b.cyl("black", 0, 0.5, 0.2, 0.025, 0.07, seg=8)
    b.box("black", 0, 0.58, 0.2, 0.1, 0.03, 0.04)
    tube(b, "black", (0.04, 0.55, 0.2), (0.12, 0.3, 0.12), 0.012)
    b.box("red_paint", 0, 0.9, 0.38, 0.2, 0.1, 0.01)
    return [("fire_extinguisher", b, (0, 0, 0))]


def smoke_alarm(B, tube):
    b = B()
    b.cyl("white", 0, 2.55, 0, 0.13, 0.05, seg=14)
    b.cyl("gray", 0, 2.52, 0, 0.09, 0.03, seg=12)
    b.box("red_paint", 0.09, 2.52, 0, 0.025, 0.02, 0.025)
    return [("smoke_alarm", b, (0, 0, 0))]


def vending_machine(B, tube):
    b = B()
    b.box("red_paint", 0, 0.9, 0.05, 0.85, 1.8, 0.8)
    b.box("black", -0.1, 1.15, -0.355, 0.55, 1.1, 0.02)
    b.box("glass", -0.1, 1.15, -0.37, 0.5, 1.05, 0.005)
    cols = ("paint_a", "paint_b", "paint_c", "leaf", "white")
    for r in range(5):
        for c in range(4):
            b.box(cols[(r + c) % 5], -0.28 + c * 0.12, 0.78 + r * 0.2, -0.33, 0.08, 0.12, 0.04)
    b.box("gray", 0.33, 1.3, -0.36, 0.12, 0.45, 0.03)
    for i in range(6):
        b.box("steel", 0.33, 1.15 + (i % 3) * 0.12, -0.38 + 0.0, 0.05, 0.03, 0.01)
    b.box("black", 0.33, 0.95, -0.37, 0.1, 0.03, 0.02)
    b.box("black", 0, 0.2, -0.37, 0.6, 0.2, 0.02)
    b.box("white", 0, 1.75, -0.36, 0.7, 0.1, 0.02)
    b.box("gray", 0, 0.03, -0.35, 0.8, 0.06, 0.1)
    return [("vending_machine", b, (0, 0, 0))]


def terminal(B, tube):
    b = B()
    b.box("gray", 0, 0.75, 0.15, 0.7, 1.5, 0.5)
    b.box("black", 0, 1.3, -0.11, 0.54, 0.4, 0.04)
    b.box("screen", 0, 1.3, -0.135, 0.46, 0.32, 0.01)
    b.box("black", 0, 0.98, -0.18, 0.5, 0.06, 0.2)
    for r in range(3):
        for c in range(3):
            b.box("white", -0.1 + c * 0.1, 0.995, -0.24 + r * 0.05, 0.07, 0.02, 0.035)
    b.box("black", 0, 0.78, -0.11, 0.3, 0.05, 0.03)
    b.box("black", 0, 0.62, -0.11, 0.3, 0.08, 0.03)
    b.box("teal", 0, 1.56, 0.15, 0.7, 0.1, 0.5)
    b.box("yellow_safety", 0.22, 0.78, -0.125, 0.06, 0.03, 0.01)
    b.box("gray", 0, 0.03, 0.15, 0.78, 0.06, 0.58)
    return [("terminal", b, (0, 0, 0))]


def telescope(B, tube):
    b = B()
    for ang in (0, 2.094, 4.188):
        import math
        x = math.sin(ang) * 0.3
        z = math.cos(ang) * 0.3
        tube(b, "wood_dark", (0, 1.1, 0), (x, 0.0, z), 0.02)
    b.cyl("metal_dark", 0, 1.05, 0, 0.06, 0.1, seg=8)
    tube(b, "white", (0.18, 1.0, 0.25), (-0.15, 1.5, -0.3), 0.07)
    tube(b, "brass", (-0.15, 1.5, -0.3), (-0.2, 1.58, -0.38), 0.085)
    tube(b, "black", (0.2, 0.97, 0.28), (0.24, 0.92, 0.33), 0.05)
    b.box("black", 0.0, 1.12, 0.0, 0.08, 0.06, 0.08)
    return [("telescope", b, (0, 0, 0))]


def park_bench(B, tube):
    b = B()
    for x in (-0.8, 0.8):
        b.box("metal_dark", x, 0.25, 0.0, 0.08, 0.5, 0.5)       # cast-iron ends
        b.box("metal_dark", x, 0.6, 0.22, 0.08, 0.5, 0.06)
    for i in range(4):
        b.box("wood_light", 0, 0.52, -0.2 + i * 0.13, 1.9, 0.05, 0.1)     # seat slats (top y~0.55)
    for i in range(3):
        b.box("wood_light", 0, 0.62 + i * 0.12, 0.25, 1.9, 0.09, 0.04)    # back slats
    return [("park_bench", b, (0, 0, 0))]
