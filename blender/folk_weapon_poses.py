"""Task 57b clips for holding and using a weapon (folk.py CYCLIC). Same conventions as folk.py; `make(h)` returns {clip: (frames, fn)}.
One-handed (blade, bar, bat, spray, knuckles): Hold_1H at the side, Threaten_1H raised at the other person. A handgun: Hold_Pistol held low,
Threaten_Pistol aimed with both hands. A long gun: Hold_Long held low across the body with the left hand on the fore-end, Aim_Long with the
stock at the right shoulder. The weapon itself hangs on hand_R (FolkProps, weapons.json "hold"); the fists are the grip_L / grip_R shape keys.
"""


def make(h):
    Pose, sn = h["Pose"], h["sn"]

    def breathe(p, t, k=1.0):
        p.rot("chest", 0.015 * k * sn(t), 0, 0)
        p.rot("head", 0.01 * sn(t, 1, 1.0), 0, 0.04 * sn(t, 1, 0.5))
        return p

    def stance(p):
        p.leg("L", -0.08, 0.12, 0, 0.10)
        p.leg("R", 0.10, 0.16, 0, 0.10)
        return p

    def hold_1h(t):
        p = breathe(Pose().relax(), t)
        p.arm("R", 0.18, 0.10, 0.40, 0.05)
        return p

    def threaten_1h(t):
        p = stance(breathe(Pose().relax(), t, 0.6))
        p.rot("spine", -0.05)
        p.rot("chest", -0.06, 0, 0.12)
        p.rot("head", -0.04)
        p.arm("R", 1.05 + 0.04 * sn(t, 2), 0.10, 0.30, 0.15)
        p.arm("L", 0.25, 0.25, 0.70, 0.0)
        return p

    def hold_pistol(t):
        p = breathe(Pose().relax(), t)
        p.arm("R", 0.30, 0.08, 0.35, 0.10)
        return p

    def threaten_pistol(t):
        p = stance(breathe(Pose().relax(), t, 0.4))
        p.rot("chest", -0.04, 0, 0.10)
        p.rot("head", -0.06)
        p.arm("R", 1.45 + 0.02 * sn(t, 2), 0.05, 0.08, 0.18)
        p.arm("L", 1.30 + 0.02 * sn(t, 2), 0.05, 0.45, 0.42)
        return p

    def hold_long(t):
        p = breathe(Pose().relax(), t)
        p.arm("R", 0.18, 0.06, 0.95, 0.25)          # the grip at the right hip
        p.arm("L", 0.50, 0.00, 0.55, 0.50)          # the left hand forward and low on the fore-end: the muzzle points down ahead
        return p

    def aim_long(t):
        p = stance(breathe(Pose().relax(), t, 0.4))
        p.rot("chest", -0.03, 0, 0.18)
        p.rot("head", -0.10, 0, -0.08)
        p.arm("R", 0.95, 0.30, 1.55, 0.45)          # the grip just in front of the right shoulder, the stock against it
        p.arm("L", 1.62, 0.00, 0.30, 0.50)          # the left arm out along the barrel
        return p

    return {"Hold_1H": (48, hold_1h), "Threaten_1H": (48, threaten_1h), "Hold_Pistol": (48, hold_pistol), "Threaten_Pistol": (48, threaten_pistol),
            "Hold_Long": (48, hold_long), "Aim_Long": (48, aim_long)}
