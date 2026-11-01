"""Costruisce il kit dei personaggi di Riftward e lo esporta in glb per Godot.

    python build_kit.py [cartella di uscita] [solo: villager,parts,...]

Serve il modulo Python di Blender (pip install bpy==5.2.3, Python 3.13). Il gioco
non ne ha bisogno: usa i glb già esportati in godot/assets/characters/kit/.

Esce:
  body_<vestito>.glb  corpo vestito legato allo scheletro, chiavi di forma per
                      corporatura (fem, slim, athletic, muscular, chubby)
  parts.glb           testa base (chiavi fem, sharp, square, full), capigliature,
                      barbe, occhiali e fascia, tutto rispetto al perno della testa
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import kit_core as K  # noqa: E402
import kit_body  # noqa: E402
import kit_head  # noqa: E402
import kit_hair  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BODY_LEVELS = 1
DEFAULT_OUT = os.path.join(ROOT, "godot", "assets", "characters", "kit")


def _variant_positions(build, params_for, names, levels, base_count):
    out = {}
    for name in names:
        tmp = K.cage_to_object(build(params_for(name)), "tmp_" + name, levels=levels, groups=False)
        cos = K.positions(tmp)
        K.remove(tmp)
        if len(cos) != base_count:
            raise RuntimeError("%s: topologia diversa (%d invece di %d)" % (name, len(cos), base_count))
        out[name] = cos
    return out


def _check(base, variants, limit):
    for name, cos in variants.items():
        worst = max((a - b.co).length for a, b in zip(cos, base.data.vertices))
        if worst > limit:
            raise RuntimeError("chiave %s: spostamento %.3f troppo grande (punti mescolati?)" % (name, worst))


def build_outfit(name, out_dir):
    K.clear_scene()
    fn = kit_body.OUTFITS[name]
    base = K.cage_to_object(fn(kit_body.body_params("average")), "body_" + name, levels=BODY_LEVELS)
    variants = _variant_positions(fn, kit_body.body_params, kit_body.VARIANTS, BODY_LEVELS, len(base.data.vertices))
    _check(base, variants, 0.12)
    K.finish_attributes(base)
    K.add_shape_keys(base, variants)
    arm = K.make_armature()
    K.bind(base, arm)
    path = os.path.join(out_dir, "body_%s.glb" % name)
    K.export_glb(path, [arm, base])
    print("  %s: %d punti" % (os.path.basename(path), len(base.data.vertices)))


def build_parts(out_dir):
    K.clear_scene()
    objs = []
    head = K.cage_to_object(kit_head.build_head(""), "head", levels=1, groups=False)
    variants = _variant_positions(kit_head.build_head, lambda k: k, ["fem", "sharp", "square", "full"], 1,
                                  len(head.data.vertices))
    _check(head, variants, 0.03)
    K.finish_attributes(head, uv_fn=kit_head.face_uv, front_fn=kit_head.face_front)
    K.add_shape_keys(head, variants)
    objs.append(head)
    for style in kit_hair.STYLES:
        o = K.cage_to_object(kit_hair.build_hair(style), "hair_" + style, levels=0, groups=False)
        K.finish_attributes(o)
        objs.append(o)
    for name, cage, lv in (("glasses", kit_head.build_glasses(), 0), ("headband", kit_head.build_headband(), 1),
                           ("beard_short", kit_head.build_beard("short"), 1),
                           ("beard_goatee", kit_head.build_beard("goatee"), 1)):
        o = K.cage_to_object(cage, name, levels=lv, groups=False)
        K.finish_attributes(o)
        objs.append(o)
    path = os.path.join(out_dir, "parts.glb")
    K.export_glb(path, objs)
    print("  parts.glb: %d pezzi" % len(objs))


def main():
    args = [a for a in sys.argv[1:]]
    out_dir = args[0] if args else DEFAULT_OUT
    only = set(args[1].split(",")) if len(args) > 1 else None
    os.makedirs(out_dir, exist_ok=True)
    for name in kit_body.OUTFITS:
        if only is None or name in only:
            build_outfit(name, out_dir)
    if only is None or "parts" in only:
        build_parts(out_dir)


if __name__ == "__main__":
    main()
