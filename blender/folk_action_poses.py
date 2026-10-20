"""Task 33 action clips for the folk rig: what the body does while a folk waters, cooks, mops, repairs, phones, eats, digs, fishes, lifts,
writes, brushes teeth, sings, cradles a baby, ... Same conventions as folk.py (see its header); pose functions take t in [0, 1) and return a Pose.
`make(h)` gets the helpers of folk.py (Pose, sn, cs, pos, sit_base, TAU, PI) and returns {clip name: (frames, fn)} for folk.CYCLIC.
Hand props and particles for these clips live in data/animation_map.json (FolkProps / FolkFx), not here.
"""
import math


def make(h):
    Pose, sn, cs, pos, sit_base, TAU, PI = h["Pose"], h["sn"], h["cs"], h["pos"], h["sit_base"], h["TAU"], h["PI"]

    def base(sit, lean=0.0):
        return sit_base(0.0, lean=lean, hands=None) if sit else Pose().relax()

    def squat(p, depth=1.0, lean=0.30):
        """Knees bent, torso leaning in: a crouch beside the thing being worked on."""
        p.move(0, -0.10 * depth, -0.40 * depth)
        for s in "LR":
            p.leg(s, 1.20 * depth, 2.0 * depth, 0.25, 0.10)
        p.rot("spine", -lean * 0.5)
        p.rot("chest", -lean * 0.5)
        return p

    # ---- watering: can held out, tipped forward in a slow pour, other hand on the hip
    def pour(t):
        p = Pose().relax()
        tip = 0.5 - 0.5 * math.cos(TAU * t)            # 0 = level, 1 = poured
        p.rot("spine", -0.06)
        p.rot("chest", -0.07)
        p.rot("head", -0.28 + 0.03 * sn(t, 2))
        p.arm("R", 0.95 + 0.10 * tip, 0.30, 1.0 - 0.15 * tip, 0.10)
        p.rot("hand_R", 0.15 + 0.80 * tip)
        p.arm("L", 0.30, 0.45, 1.65, 0.0)
        return p

    # ---- cleaning: lean over, wide wiping strokes with a cloth, free hand braced on the hip
    def wipe(t):
        p = Pose().relax()
        sw = sn(t, 2)
        p.rot("spine", -0.14)
        p.rot("chest", -0.14, 0, 0.10 * sw)
        p.rot("head", -0.22)
        p.arm("R", 0.95, 0.12, 0.45 + 0.12 * sn(t, 2, 1.5), 0.05 + 0.40 * sw)
        p.arm("L", 0.30, 0.45, 1.65, 0.0)
        p.rot("hand_R", 0.4)
        p.move(0.012 * sw)
        return p

    # ---- mopping: both hands on the handle, body sways with the stroke
    def mop(t):
        p = Pose().relax()
        sw = sn(t, 2)
        p.rot("spine", -0.10)
        p.rot("chest", -0.08, 0, 0.14 * sw)
        p.rot("head", -0.24)
        p.rot("hips", 0, 0, -0.08 * sw)
        p.arm("R", 0.80, 0.10, 0.55, 0.28 + 0.22 * sw)
        p.arm("L", 0.70, 0.10, 0.75, 0.30 + 0.22 * sw)
        p.leg("L", 0.16 * sw, 0.15, 0, 0.06)
        p.leg("R", -0.16 * sw, 0.15, 0, 0.06)
        return p

    # ---- repairing: crouched, one hand holds the work still, the other turns a wrench in short pulls
    def repair(t):
        p = Pose().relax()
        squat(p, 1.0, 0.28)
        pull = pos(sn(t, 3)) ** 0.7
        p.rot("head", -0.25)
        p.arm("R", 1.05 + 0.22 * pull, 0.12, 0.65 - 0.25 * pull, 0.08 - 0.12 * pull)
        p.rot("hand_R", 0.5 * pull)
        p.arm("L", 0.85, 0.15, 0.85, 0.20)
        return p

    # ---- phone: to the ear for a call (hand on the hip), both hands low in front for a text
    def upper_call(p, t):
        p.arm("R", 0.85, 0.40, 2.45, 0.0)
        p.arm("L", 0.55, 0.12, 1.45, 0.55)
        p.rot("head", 0.04 * sn(t, 2), 0.0, -0.10 + 0.06 * sn(t, 1, 0.5))
        p.rot("chest", 0, 0, 0.04 * sn(t, 1))
        return p

    def phone_call(t):
        p = Pose().relax()
        p.move(0.012 * sn(t))
        return upper_call(p, t)

    def sit_phone_call(t):
        p = base(True, 0.05)
        p.rot("spine", 0.012 * sn(t))
        return upper_call(p, t)

    def upper_text(p, t):
        p.rot("head", -0.42 + 0.03 * sn(t, 2))
        p.rot("chest", -0.08)
        p.arm("R", 0.95, 0.10, 1.45, 0.38)
        p.arm("L", 0.95, 0.10, 1.45, 0.38)
        p.rot("hand_R", -0.10 + 0.14 * sn(t, 7))
        p.rot("hand_L", -0.10 + 0.12 * sn(t, 6, 1.0))
        return p

    def phone_text(t):
        return upper_text(Pose().relax(), t)

    def sit_phone_text(t):
        return upper_text(base(True, 0.05), t)

    # ---- eating / drinking on foot: hand to the mouth and back, plate or cup in the other hand
    def eat(t):
        p = Pose().relax()
        bite = 0.5 - 0.5 * math.cos(TAU * t * 2)
        p.rot("head", -0.12 + 0.12 * bite)
        p.arm("R", 0.55 + 0.35 * bite, 0.12, 0.90 + 1.30 * bite, 0.12 * bite)
        p.arm("L", 0.95, 0.12, 1.35, 0.45)
        p.rot("chest", -0.03 * bite)
        return p

    # ---- gardening: crouched, digging strokes with a trowel, the other hand steadies on the knee
    def dig(t):
        p = Pose().relax()
        squat(p, 1.1, 0.34)
        st = pos(sn(t, 3)) ** 0.8
        p.rot("head", -0.28)
        p.arm("R", 1.15 + 0.30 * st, 0.18, 0.55 + 0.35 * (1 - st), 0.10)
        p.rot("hand_R", 0.4 * st)
        p.arm("L", 0.85, 0.22, 0.50, 0.0)
        return p

    # ---- bending over: picking, nappy changes, helping somebody down low; hands busy at the floor / a table
    def bend(t):
        p = Pose().relax()
        w = sn(t, 2)
        p.rot("hips", -0.35)
        p.rot("spine", -0.45)
        p.rot("chest", -0.30)
        p.rot("head", 0.30)
        p.move(0, 0.06, -0.06)
        p.leg("L", 0.22, 0.28, 0, 0.06)
        p.leg("R", 0.22, 0.28, 0, 0.06)
        p.arm("R", 0.75 + 0.18 * w, 0.18, 0.35 + 0.15 * sn(t, 2, 1.0), 0.10)
        p.arm("L", 0.80, 0.18, 0.40 + 0.12 * w, 0.10)
        return p

    # ---- fishing: rod in two hands, patient, now and then a tug and a few turns of the reel
    def fish(t):
        p = Pose().relax()
        tug = pos(sn(t, 1, 0.5)) ** 10
        reel = pos(sn(t, 1, 3.6)) ** 3
        p.rot("head", -0.12 + 0.05 * sn(t, 1, 2.0), 0, 0.15)
        p.rot("chest", 0.05 * tug, 0, 0.08)
        p.arm("R", 0.85 + 0.35 * tug, 0.20, 1.05 - 0.15 * tug, 0.12)
        p.arm("L", 0.70 + 0.35 * tug, 0.22, 1.30 - 0.20 * tug, 0.20)
        p.rot("forearm_R", 0.30 * reel * sn(t, 8))
        p.leg("L", 0.0, 0.05, 0, 0.14)
        p.leg("R", 0.0, 0.05, 0, 0.14)
        return p

    # ---- weights: alternate bicep curls, a little knee bounce
    def lift(t):
        p = Pose().relax()
        c = 0.5 - 0.5 * math.cos(TAU * t * 2)
        c2 = 0.5 - 0.5 * math.cos(TAU * t * 2 + PI)
        p.rot("head", 0.02)
        p.arm("R", 0.12, 0.18, 0.15 + 2.05 * c, 0.0)
        p.arm("L", 0.12, 0.18, 0.15 + 2.05 * c2, 0.0)
        p.move(0, 0, -0.02 - 0.02 * cs(t, 4))
        p.leg("L", 0.10, 0.20, 0, 0.12)
        p.leg("R", 0.10, 0.20, 0, 0.12)
        return p

    # ---- writing by hand: head down, paper held flat with one hand, small pen strokes with the other
    def upper_write(p, t):
        p.rot("head", -0.40 + 0.03 * sn(t, 2))
        p.rot("chest", -0.08)
        p.arm("R", 0.95, 0.12, 1.25 + 0.08 * sn(t, 5), 0.30 + 0.05 * sn(t, 3))
        p.rot("hand_R", -0.1 + 0.2 * sn(t, 6))
        p.arm("L", 0.90, 0.14, 1.20, 0.28)
        return p

    def write(t):
        return upper_write(Pose().relax(), t)

    def sit_write(t):
        return upper_write(base(True, 0.10), t)

    # ---- brushing teeth: hand at the mouth, quick short strokes
    def brush_teeth(t):
        p = Pose().relax()
        p.rot("head", -0.10, 0, 0.05 * sn(t, 2))
        p.arm("R", 1.10, 0.10, 2.35 + 0.10 * sn(t, 8), 0.15)
        p.rot("forearm_R", 0.12 * sn(t, 8))
        p.arm("L", 0.45, 0.12, 1.50, 0.50)
        p.rot("chest", -0.04)
        return p

    # ---- singing into a microphone, free hand gesturing, swaying
    def sing(t):
        p = Pose().relax()
        s = sn(t, 1)
        p.rot("head", 0.12 + 0.04 * sn(t, 2), 0.04 * s, 0.10 * s)
        p.rot("chest", 0.0, 0, 0.08 * s)
        p.rot("hips", 0, 0.05 * s, 0.06 * s)
        p.arm("R", 1.15, 0.12, 2.30, 0.12)
        p.arm("L", 0.55 + 0.45 * pos(sn(t, 2)), 0.45 + 0.20 * pos(sn(t, 2)), 0.75, 0.0)
        p.leg("L", 0.05 + 0.05 * s, 0.1, 0, 0.12)
        p.leg("R", 0.05 - 0.05 * s, 0.1, 0, 0.12)
        p.move(0.015 * s, 0, -0.01 * abs(s))
        return p

    # ---- cradling a baby: both arms in front, a slow rock from side to side
    def cradle(t):
        p = Pose().relax()
        r = sn(t, 1)
        p.rot("head", -0.32, 0, 0.08 * r)
        p.rot("chest", -0.04, 0, 0.05 * r)
        p.rot("hips", 0, 0, -0.07 * r)
        p.arm("R", 1.00, 0.05, 1.45, 0.78)
        p.arm("L", 0.95, 0.05, 1.50, 0.72)
        p.leg("L", 0.04 * r, 0.08, 0, 0.06)
        p.leg("R", -0.04 * r, 0.08, 0, 0.06)
        p.move(0.012 * r)
        return p

    # ---- looking around / watching: slow head sweeps, a shrug now and then
    def look(t):
        p = Pose().relax()
        p.rot("head", 0.02 * sn(t, 2), 0.03, 0.55 * sn(t, 1))
        p.rot("neck", 0, 0, 0.12 * sn(t, 1))
        p.rot("chest", 0, 0, 0.14 * sn(t, 1, 0.3))
        p.arm("L", 0.06, 0.10, 0.20)
        p.arm("R", 0.06 + 0.5 * pos(sn(t, 1, 3.8)) ** 4, 0.10, 0.20 + 1.4 * pos(sn(t, 1, 3.8)) ** 4)
        p.move(0.01 * sn(t))
        return p

    # ---- thinking: a hand at the chin, the other arm across, head tilting
    def upper_think(p, t):
        p.rot("head", -0.10 + 0.04 * sn(t, 1), 0, 0.14 * sn(t, 1, 0.6))
        p.arm("R", 1.00, 0.14, 2.35, 0.30)
        p.arm("L", 0.65, 0.12, 1.55, 0.65)
        return p

    def think(t):
        p = Pose().relax()
        p.move(0.01 * sn(t))
        return upper_think(p, t)

    def sit_think(t):
        return upper_think(base(True, 0.05), t)

    # ---- reaching: the arm goes out to a shelf / machine / handle and comes back with something
    def reach(t):
        p = Pose().relax()
        e = pos(sn(t, 1, -0.6)) ** 0.6              # out and back
        p.rot("spine", -0.06 * e)
        p.rot("chest", -0.08 * e)
        p.rot("head", -0.08 * e)
        p.arm("R", 0.30 + 1.05 * e, 0.12, 1.30 - 1.00 * e, 0.10)
        p.arm("L", 0.04, 0.10, 0.18)
        p.move(0.01 * e)
        return p

    # ---- guitar: strum with the right hand, left hand along the neck
    def strum(t):
        p = Pose().relax()
        s = sn(t, 3)
        p.rot("head", -0.28, 0, 0.15 * sn(t, 1))
        p.rot("chest", 0, 0, 0.06 * sn(t, 1))
        p.arm("R", 0.60, 0.28, 1.15 + 0.12 * s, 0.35)
        p.arm("L", 1.05, 0.55, 1.05, 0.0)
        p.leg("L", 0.0, 0.05, 0, 0.12)
        p.leg("R", 0.05, 0.10, 0, 0.12)
        p.move(0.008 * sn(t, 1))
        return p

    # ---- piano: seated, both hands on the keys, wrists rolling
    def sit_piano(t):
        p = base(True, 0.14)
        p.rot("head", 0.04 + 0.04 * sn(t, 1), 0, 0.10 * sn(t, 1, 0.5))
        p.rot("chest", 0.02 * sn(t, 2), 0, 0.05 * sn(t, 1))
        p.arm("R", 0.80, 0.22 + 0.10 * sn(t, 2), 0.75, 0.10)
        p.arm("L", 0.80, 0.22 + 0.10 * sn(t, 2, 1.5), 0.75, 0.10)
        p.rot("hand_R", -0.15 + 0.18 * sn(t, 5))
        p.rot("hand_L", -0.15 + 0.18 * sn(t, 4, 1.0))
        return p

    # ---- balancing on a board / skis: low wide stance, arms out, sway
    def balance(t):
        p = Pose().relax()
        s = sn(t, 1)
        p.move(0.02 * s, 0, -0.16)
        p.rot("chest", -0.12, 0.05 * s, 0.10 * s)
        p.rot("head", 0.0, 0, -0.1 * s)
        p.leg("L", 0.55, 0.95, 0, 0.22)
        p.leg("R", 0.55, 0.95, 0, 0.22)
        p.arm("L", 0.35, 0.95 + 0.15 * s, 0.35)
        p.arm("R", 0.35, 0.95 - 0.15 * s, 0.35)
        return p

    # ---- relaxing: hands behind the head, face to the sky (standing) / leaning back (sitting)
    def upper_relax(p, t, lean):
        p.rot("head", lean + 0.03 * sn(t, 1))
        p.arm("R", 1.85, 0.75, 2.30, 0.0)
        p.arm("L", 1.85, 0.75, 2.30, 0.0)
        return p

    def relax_stand(t):
        p = Pose().relax()
        p.rot("chest", 0.08 + 0.015 * sn(t, 1))
        p.move(0.01 * sn(t))
        return upper_relax(p, t, 0.28)

    def sit_relax(t):
        p = base(True, -0.12)
        p.rot("spine", -0.22)
        p.rot("hips", -0.12)
        return upper_relax(p, t, 0.12)

    # ---- speech: both arms making points, a fist now and then
    def speech(t):
        p = Pose().relax()
        a = pos(sn(t, 2))
        b = pos(sn(t, 2, PI))
        p.rot("head", 0.04 * sn(t, 3), 0.03, 0.12 * sn(t, 1, 0.4))
        p.rot("chest", -0.03 * a, 0, 0.05 * sn(t, 1))
        p.arm("R", 0.80 + 0.55 * a, 0.35, 1.30 - 0.50 * a, 0.0)
        p.arm("L", 0.80 + 0.55 * b, 0.35, 1.30 - 0.50 * b, 0.0)
        return p

    # ---- aiming: both arms out in front, braced (fire extinguisher, hose)
    def aim(t):
        p = Pose().relax()
        p.rot("chest", -0.05)
        p.rot("head", -0.10)
        p.arm("R", 1.25, 0.15, 0.30 + 0.05 * sn(t, 3), 0.25)
        p.arm("L", 1.25, 0.15, 0.30 + 0.05 * sn(t, 3, 1.0), 0.25)
        p.leg("L", -0.1, 0.15, 0, 0.12)
        p.leg("R", 0.15, 0.20, 0, 0.12)
        return p

    return {
        "Pour": (72, pour), "Wipe": (48, wipe), "Mop": (48, mop), "Repair": (48, repair),
        "Phone_Call": (96, phone_call), "Sit_Phone_Call": (96, sit_phone_call),
        "Phone_Text": (48, phone_text), "Sit_Phone_Text": (48, sit_phone_text),
        "Eat": (72, eat), "Dig": (48, dig), "Bend": (72, bend), "Fish": (96, fish), "Lift": (48, lift),
        "Write": (72, write), "Sit_Write": (72, sit_write), "Brush_Teeth": (48, brush_teeth), "Sing": (72, sing),
        "Cradle": (96, cradle), "Look": (120, look), "Think": (96, think), "Sit_Think": (96, sit_think),
        "Reach": (72, reach), "Strum": (48, strum), "Sit_Piano": (72, sit_piano), "Balance": (72, balance),
        "Relax": (96, relax_stand), "Sit_Relax": (96, sit_relax), "Speech": (72, speech), "Aim": (48, aim),
    }
