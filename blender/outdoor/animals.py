"""Animals: dog, cat, bird. Segmented models (rigid nodes with pivots at the joints) + node-level animation clips
exported as glTF animations (Godot imports them into an AnimationPlayer). Front = -Z. Origin: centre on the ground.
dog/cat nodes: body, head, tail, leg_fl, leg_fr, leg_bl, leg_br. Clips: Idle (tail wag, head bob), Walk (diagonal leg gait).
bird nodes: body, head, tail, wing_l, wing_r, leg_l, leg_r. Clips: Idle (head bob/peck), Walk (hop), Fly (wing flap)."""


def _quad(s, hx, hy, hz, name, fur, fur2, ear_pointy, tail_len, tail_th, leg_h, body_len, body_w, body_h, head_s):
    ly = leg_h
    zf, zb = -body_len / 2 + 0.07, body_len / 2 - 0.07
    parts = []
    b = Builder()
    b.box(fur, 0, ly + body_h / 2, 0, body_w, body_h, body_len)
    b.box(fur2, 0, ly + 0.04, -body_len * 0.1, body_w * 0.9, body_h * 0.5, body_len * 0.5)       # belly/chest patch
    parts.append(("body", b, (0, 0, 0)))
    hy0 = ly + body_h * 0.9
    hz0 = -body_len / 2 - 0.02
    h = Builder()
    h.box(fur, 0, hy0, hz0 - head_s * 0.45, head_s, head_s * 0.9, head_s)
    h.box(fur2, 0, hy0 - head_s * 0.2, hz0 - head_s * 1.1, head_s * 0.55, head_s * 0.4, head_s * 0.5)
    h.box("nose", 0, hy0 - head_s * 0.05, hz0 - head_s * 1.36, head_s * 0.2, head_s * 0.15, head_s * 0.1)
    for sx in (-1, 1):
        if ear_pointy:
            tube(h, fur, (sx * head_s * 0.3, hy0 + head_s * 0.4, hz0 - head_s * 0.3), (sx * head_s * 0.38, hy0 + head_s * 0.95, hz0 - head_s * 0.3), head_s * 0.17, 3, 0.0)
        else:
            h.box(fur2 if name == "dog" else fur, sx * head_s * 0.55, hy0 + head_s * 0.05, hz0 - head_s * 0.3, head_s * 0.15, head_s * 0.5, head_s * 0.3)
        h.box("black", sx * head_s * 0.24, hy0 + head_s * 0.1, hz0 - head_s * 0.96, head_s * 0.1, head_s * 0.12, head_s * 0.05)
    parts.append(("head", h, (0, hy0 - head_s * 0.3, hz0 + 0.02)))
    t = Builder()
    tube(t, fur, (0, ly + body_h * 0.8, body_len / 2 - 0.03), (0, ly + body_h * 0.8 + tail_len * 0.8, body_len / 2 + tail_len * 0.4), tail_th, 5, tail_th * 0.7)
    parts.append(("tail", t, (0, ly + body_h * 0.8, body_len / 2 - 0.03)))
    for nm, x, z in (("leg_fl", -1, zf), ("leg_fr", 1, zf), ("leg_bl", -1, zb), ("leg_br", 1, zb)):
        l = Builder()
        lx = x * (body_w / 2 - 0.04)
        l.box(fur, lx, ly / 2 + 0.02, z, 0.08 * s, ly + 0.04, 0.09 * s)
        l.box(fur2, lx, 0.025, z - 0.015, 0.09 * s, 0.05, 0.12 * s)
        parts.append((nm, l, (lx, ly, z)))
    return parts


def dog():
    return _quad(1.0, 0, 0, 0, "dog", "fur_dog", "fur_dog2", False, 0.32, 0.04, 0.3, 0.62, 0.26, 0.28, 0.2)


def cat():
    return _quad(0.7, 0, 0, 0, "cat", "fur_cat", "fur_cat2", True, 0.4, 0.03, 0.17, 0.42, 0.18, 0.19, 0.15)


def _walk_keys():
    def leg(ph):
        return [(f, (v * ph, 0, 0), None) for f, v in ((1, 32), (7, 0), (13, -32), (19, 0), (25, 32))]
    return {"leg_fl": leg(1), "leg_br": leg(1), "leg_fr": leg(-1), "leg_bl": leg(-1)}


def _quad_post(objs):
    set_clip(objs, "Walk", {**_walk_keys(),
                            "tail": [(1, (-8, 0, 0), None), (13, (8, 0, 0), None), (25, (-8, 0, 0), None)],
                            "head": [(1, (0, 0, 0), (0, 0, 0)), (7, (4, 0, 0), None), (13, (0, 0, 0), None), (19, (4, 0, 0), None), (25, (0, 0, 0), None)]})
    set_clip(objs, "Idle", {"tail": [(1, (0, -22, 0), None), (7, (0, 22, 0), None), (13, (0, -22, 0), None), (19, (0, 22, 0), None), (25, (0, -22, 0), None)],
                            "head": [(1, (0, 0, 0), None), (25, (-6, 0, 0), None), (49, (0, 0, 0), None)]})


asset("dog", 0.4, 0.9, "dog ~0.9 m long; nodes body head tail leg_fl leg_fr leg_bl leg_br; clips Idle, Walk", post=_quad_post)(dog)
asset("cat", 0.3, 0.7, "cat ~0.7 m long; nodes body head tail leg_fl leg_fr leg_bl leg_br; clips Idle, Walk", post=_quad_post)(cat)


def bird():
    b = Builder()
    blob(b, "bird_blue", 0, 0.2, 0, 0.1, 0.1, 0.14, 3, 6)
    blob(b, "bird_belly", 0, 0.16, -0.03, 0.08, 0.07, 0.1, 3, 6)
    h = Builder()
    blob(h, "bird_blue", 0, 0.32, -0.1, 0.065, 0.065, 0.065, 3, 6)
    tube(h, "beak", (0, 0.31, -0.15), (0, 0.31, -0.23), 0.025, 4, 0.0)
    for sx in (-1, 1):
        h.box("black", sx * 0.035, 0.34, -0.14, 0.02, 0.02, 0.02)
    t = Builder()
    rbox(t, "bird_blue", 0, 0.2, 0.2, 0.07, 0.02, 0.18, rx=-18)
    parts = [("body", b, (0, 0, 0)), ("head", h, (0, 0.28, -0.07)), ("tail", t, (0, 0.21, 0.12))]
    for nm, sx in (("wing_l", -1), ("wing_r", 1)):
        w = Builder()
        rbox(w, "bird_blue", sx * 0.1, 0.18, 0.02, 0.025, 0.12, 0.2, rz=sx * -4)
        parts.append((nm, w, (sx * 0.095, 0.25, 0.0)))
    for nm, sx in (("leg_l", -1), ("leg_r", 1)):
        l = Builder()
        l.box("beak", sx * 0.035, 0.05, 0.0, 0.015, 0.1, 0.015)
        l.box("beak", sx * 0.035, 0.005, -0.02, 0.035, 0.01, 0.06)
        parts.append((nm, l, (sx * 0.035, 0.1, 0.0)))
    return parts


def _bird_post(objs):
    set_clip(objs, "Idle", {"head": [(1, (0, 0, 0), None), (10, (28, 0, 0), None), (14, (0, 0, 0), None), (36, (0, 0, 0), None), (40, (-8, 0, 0), None), (48, (0, 0, 0), None)],
                            "tail": [(1, (0, 0, 0), None), (24, (10, 0, 0), None), (48, (0, 0, 0), None)]})
    set_clip(objs, "Walk", {"leg_l": [(1, (30, 0, 0), None), (7, (-30, 0, 0), None), (13, (30, 0, 0), None)],
                            "leg_r": [(1, (-30, 0, 0), None), (7, (30, 0, 0), None), (13, (-30, 0, 0), None)],
                            "head": [(1, (0, 0, 0), None), (4, (-10, 0, 0), None), (7, (0, 0, 0), None), (10, (-10, 0, 0), None), (13, (0, 0, 0), None)]})
    set_clip(objs, "Fly", {"wing_l": [(1, (0, 0, -12), None), (5, (0, 0, -80), None), (9, (0, 0, -12), None)],
                           "wing_r": [(1, (0, 0, 12), None), (5, (0, 0, 80), None), (9, (0, 0, 12), None)],
                           "tail": [(1, (0, 0, 0), None), (5, (-10, 0, 0), None), (9, (0, 0, 0), None)]})


asset("bird", 0.25, 0.4, "small songbird; nodes body head tail wing_l wing_r leg_l leg_r; clips Idle, Walk, Fly (wing_* pivot at the shoulders)", post=_bird_post)(bird)
