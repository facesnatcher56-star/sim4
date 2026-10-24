"""Assemble every mesh object of one folk variant (body + all toggleable parts). Called from folk.py."""
import folk_body as FB
import folk_head as FH
import bpy
from folk_mesh import Mesher


def _grip_keys(body, bones, S, hd, wd):
    """Task 57b: shape keys grip_L / grip_R close each hand into a fist round a grip (Godot sets them while a weapon is drawn)."""
    body.data.uv_layers.new(name="UVMap")          # Godot needs UVs for the tangents of a morphed mesh
    body.shape_key_add(name="Basis", from_mix=False)
    n = len(body.data.vertices)
    for key, cl, cr in (("grip_L", 1.0, 0.0), ("grip_R", 0.0, 1.0)):
        M2 = Mesher(bones, S)
        FB.base_body(M2, wd, cl, cr)
        FH.skull(M2, hd)
        tmp = bpy.data.meshes.new("tmp")
        M2.bm.to_mesh(tmp)
        M2.bm.free()
        assert len(tmp.vertices) == n, (key, len(tmp.vertices), n)
        sk = body.shape_key_add(name=key, from_mix=False)
        for i, v in enumerate(tmp.vertices):
            sk.data[i].co = v.co
        bpy.data.meshes.remove(tmp)


def build_meshes(arm, bones, S, hs, wd):
    """Returns the list of created objects. Godot shows/tints the ones the appearance asks for."""
    hd = FH.Head(hs)
    obs = []
    M = Mesher(bones, S)
    FB.base_body(M, wd)
    FH.skull(M, hd)
    body = M.finish("body", arm)
    _grip_keys(body, bones, S, hd, wd)
    obs.append(body)

    def one(name, fn, *a):
        m = Mesher(bones, S)
        fn(m, hd, *a)
        obs.append(m.finish(name, arm))

    for i in range(3):
        one("ears_%d" % i, FH.ears, i)
    for i in range(len(FH.EYES)):
        one("eyes_%d" % i, FH.eyes, i)
    for i in range(4):
        one("brows_%d" % i, FH.brows, i)
        one("nose_%d" % i, FH.nose, i)
        one("mouth_%d" % i, FH.mouth, i)
    for i in range(FH.HAIR_STYLES):
        if i != FH.BALD:
            one("hair_%d" % i, FH.hair, i)
    for i in (1, 2, 3):
        one("fhair_%d" % i, FH.fhair, i)
    for i in (1, 2):
        one("mark_%d" % i, FH.mark, i)
        one("glasses_%d" % i, FH.glasses, i)
        one("hat_%d" % i, FH.hat, i)
        one("bag_%d" % i, FH.bag, i)
    one("scarf_1", lambda m, h: FH.scarf(m, h))
    obs += FB.build_clothes(arm, bones, S, wd)
    return obs
