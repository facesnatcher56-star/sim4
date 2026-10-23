"""Weapon models (task 57), grounded and plain, real sizes in metres. Hand-held items, so NOT the floor convention of the other parts:
origin = the middle of the grip, the business end points forward (-Z), up = +Y. FolkProps hangs them on hand_R with weapons.json "hold".
Materials come from the shared palette (build_all.py + build_extra.py)."""


# ---------------------------------------------------------------- improvised
def broken_bottle(B, tube):
    b = B()
    b.cyl("bottle_glass", 0, -0.02, 0.0, 0.014, 0.09, seg=10)          # neck in the hand
    b.cyl("bottle_glass", 0, 0.07, 0.0, 0.034, 0.05, r2=0.03, seg=10)
    for i, (x, z, h) in enumerate([(0.02, 0.0, 0.06), (-0.018, 0.012, 0.045), (0.0, -0.022, 0.07)]):
        tube(b, "bottle_glass", (x * 0.8, 0.12, z * 0.8), (x, 0.12 + h, z), 0.008, seg=4)          # jagged edge
    return [("broken_bottle", b, (0, 0, 0))]


def brick(B, tube):
    b = B()
    b.box("brick", 0, 0, -0.05, 0.1, 0.065, 0.2)
    return [("brick", b, (0, 0, 0))]


def pipe(B, tube):
    b = B()
    tube(b, "steel", (0, 0, 0.12), (0, 0, -0.48), 0.016, seg=10)
    b.cyl("metal_dark", 0, -0.02, 0.12, 0.022, 0.04, seg=10)          # a threaded collar at the end
    return [("pipe", b, (0, 0, 0))]


def kitchen_knife(B, tube):
    b = B()
    b.box("black", 0, 0, 0.0, 0.018, 0.026, 0.11)                       # handle
    b.box("silver", 0, 0.004, -0.15, 0.003, 0.034, 0.19)                # blade
    b.box("silver", 0, 0.004, -0.255, 0.003, 0.016, 0.03)               # tip
    return [("kitchen_knife", b, (0, 0, 0))]


def screwdriver(B, tube):
    b = B()
    tube(b, "yellow_safety", (0, 0, 0.05), (0, 0, -0.04), 0.016, seg=10)
    tube(b, "steel", (0, 0, -0.04), (0, 0, -0.16), 0.004, seg=6)
    b.box("steel", 0, 0, -0.165, 0.008, 0.002, 0.012)
    return [("screwdriver", b, (0, 0, 0))]


# ---------------------------------------------------------------- melee
def baseball_bat(B, tube):
    b = B()
    tube(b, "wood_light", (0, 0, 0.1), (0, 0, -0.25), 0.016, seg=10)
    tube(b, "wood_light", (0, 0, -0.25), (0, 0, -0.72), 0.033, seg=10)
    tube(b, "wood_dark", (0, 0, 0.1), (0, 0, 0.125), 0.024, seg=10)    # knob
    tube(b, "black", (0, 0, 0.09), (0, 0, -0.08), 0.018, seg=10)       # grip tape
    return [("baseball_bat", b, (0, 0, 0))]


def crowbar(B, tube):
    b = B()
    tube(b, "red_paint", (0, 0.0, 0.12), (0, 0.0, -0.42), 0.012, seg=6)
    tube(b, "red_paint", (0, 0.0, 0.12), (0, 0.05, 0.17), 0.012, seg=6)          # the hook
    tube(b, "red_paint", (0, 0.05, 0.17), (0, 0.02, 0.2), 0.011, seg=6)
    b.box("steel", 0, -0.004, -0.43, 0.022, 0.006, 0.03)                         # flattened end
    return [("crowbar", b, (0, 0, 0))]


def hammer(B, tube):
    b = B()
    tube(b, "wood", (0, 0, 0.08), (0, 0, -0.22), 0.014, seg=8)
    b.box("metal_dark", 0, 0, -0.235, 0.03, 0.03, 0.03)
    b.box("metal_dark", 0, 0.035, -0.235, 0.026, 0.05, 0.026)                    # face up
    b.box("metal_dark", 0, -0.04, -0.235, 0.022, 0.05, 0.012)                    # claw down
    return [("hammer", b, (0, 0, 0))]


def hunting_knife(B, tube):
    b = B()
    b.box("wood_dark", 0, 0, 0.0, 0.022, 0.03, 0.12)
    b.box("brass", 0, 0, -0.065, 0.03, 0.05, 0.008)                     # guard
    b.box("steel", 0, 0.003, -0.14, 0.004, 0.036, 0.15)
    b.box("steel", 0, 0.009, -0.225, 0.004, 0.02, 0.025)
    return [("hunting_knife", b, (0, 0, 0))]


def switchblade(B, tube):
    b = B()
    b.box("black", 0, 0, 0.0, 0.016, 0.022, 0.11)
    b.box("silver", 0, 0.002, -0.06, 0.012, 0.012, 0.012)
    b.box("silver", 0, 0.003, -0.12, 0.003, 0.022, 0.1)
    return [("switchblade", b, (0, 0, 0))]


def machete(B, tube):
    b = B()
    b.box("black", 0, 0, 0.0, 0.024, 0.032, 0.13)
    b.box("steel", 0, 0.01, -0.3, 0.004, 0.05, 0.47)
    b.box("steel", 0, 0.016, -0.55, 0.004, 0.04, 0.04)
    return [("machete", b, (0, 0, 0))]


def brass_knuckles(B, tube):
    b = B()
    b.box("brass", 0, 0.02, 0.0, 0.1, 0.02, 0.012)                      # the bar across the knuckles
    for x in (-0.036, -0.012, 0.012, 0.036):
        b.cyl("brass", x, -0.003, 0.0, 0.013, 0.006, seg=8)
    b.box("brass", 0, -0.025, 0.012, 0.07, 0.02, 0.012)                  # the palm rest
    return [("brass_knuckles", b, (0, 0, 0))]


# ---------------------------------------------------------------- non-lethal
def pepper_spray(B, tube):
    b = B()
    b.cyl("red_paint", 0, -0.05, 0.0, 0.017, 0.1, seg=12)
    b.cyl("black", 0, 0.05, 0.0, 0.012, 0.02, seg=10)
    b.box("black", 0, 0.065, -0.008, 0.01, 0.01, 0.014)
    return [("pepper_spray", b, (0, 0, 0))]


def taser(B, tube):
    b = B()
    b.box("yellow_safety", 0, 0.03, -0.06, 0.03, 0.04, 0.13)
    b.box("black", 0, -0.02, 0.0, 0.026, 0.08, 0.035)                    # grip
    b.box("black", 0, 0.03, -0.13, 0.034, 0.044, 0.02)                   # cartridge face
    return [("taser", b, (0, 0, 0))]


# ---------------------------------------------------------------- firearms
def revolver(B, tube):
    b = B()
    b.box("wood_dark", 0, -0.04, 0.02, 0.026, 0.09, 0.04)                # grip
    b.box("metal_dark", 0, 0.025, -0.02, 0.03, 0.04, 0.06)              # frame
    tube(b, "metal_dark", (0, 0.025, 0.005), (0, 0.025, -0.04), 0.02, seg=8)     # cylinder
    tube(b, "metal_dark", (0, 0.035, -0.05), (0, 0.035, -0.16), 0.008, seg=8)    # barrel
    b.box("metal_dark", 0, -0.005, -0.03, 0.006, 0.02, 0.03)            # trigger guard
    return [("revolver", b, (0, 0, 0))]


def pistol(B, tube):
    b = B()
    b.box("black", 0, -0.04, 0.02, 0.026, 0.09, 0.035)
    b.box("black", 0, 0.025, -0.05, 0.028, 0.032, 0.17)                  # slide
    b.box("black", 0, -0.005, -0.03, 0.006, 0.02, 0.035)
    return [("pistol", b, (0, 0, 0))]


def shotgun(B, tube):
    b = B()
    b.box("wood", 0, -0.03, 0.17, 0.04, 0.07, 0.3)                       # stock
    b.box("metal_dark", 0, 0.0, -0.02, 0.04, 0.05, 0.12)                 # receiver
    tube(b, "metal_dark", (0, 0.015, -0.08), (0, 0.015, -0.75), 0.011, seg=8)    # barrel
    tube(b, "metal_dark", (0, -0.008, -0.08), (0, -0.008, -0.6), 0.01, seg=8)    # magazine tube
    b.box("wood", 0, -0.01, -0.3, 0.038, 0.035, 0.14)                    # pump
    b.box("metal_dark", 0, -0.035, 0.0, 0.006, 0.03, 0.04)
    return [("shotgun", b, (0, 0, 0))]


def hunting_rifle(B, tube):
    b = B()
    b.box("wood", 0, -0.03, 0.17, 0.04, 0.07, 0.32)
    b.box("wood", 0, -0.01, -0.2, 0.036, 0.04, 0.4)                      # fore-end
    b.box("metal_dark", 0, 0.012, -0.02, 0.03, 0.04, 0.14)
    tube(b, "metal_dark", (0, 0.02, -0.08), (0, 0.02, -0.8), 0.009, seg=8)
    tube(b, "black", (0, 0.065, 0.02), (0, 0.065, -0.2), 0.016, seg=10)          # scope
    b.box("black", 0, 0.045, -0.09, 0.012, 0.03, 0.02)
    tube(b, "metal_dark", (0.025, 0.02, 0.0), (0.05, 0.02, 0.01), 0.005, seg=6)  # bolt
    b.box("metal_dark", 0, -0.035, 0.0, 0.006, 0.03, 0.04)
    return [("hunting_rifle", b, (0, 0, 0))]


IDS = ["broken_bottle", "brick", "pipe", "kitchen_knife", "screwdriver", "baseball_bat", "crowbar", "hammer", "hunting_knife", "switchblade",
       "machete", "brass_knuckles", "pepper_spray", "taser", "revolver", "pistol", "shotgun", "hunting_rifle"]
