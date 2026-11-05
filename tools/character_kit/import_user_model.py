"""Porta nel gioco un modello 3D fatto dall'utente (glb senza scheletro, in posa a T).

    python import_user_model.py user_models/guard.glb guard [cartella di uscita]

Il modello viene centrato e portato all'altezza dello scheletro di CharacterModel,
poi gli si dà lo stesso scheletro del kit (13 ossa con gli stessi nomi), con le ossa
messe dove sono davvero le articolazioni del modello: le braccia restano tese come
nel file. In Godot ogni osso riceve una correzione che porta l'arto del modello nella
posa del gioco (braccia lungo i fianchi), così le animazioni del kit funzionano anche
qui (vedi character_model.gd, _user_rest_fix e _sync_skeleton).

I pesi si calcolano dalla posizione: braccia nella fascia delle braccia, gambe solo
vicino alla linea della gamba (mantello e tabarro restano al bacino), testa sopra il
collo. Le facce che legano il braccio al mantello sotto di lui si tagliano, altrimenti
abbassando il braccio si tirerebbe dietro un telo.

Serve il modulo Python di Blender (pip install bpy==5.2.3).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402
import kit_core as K  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_OUT = os.path.join(ROOT, "godot", "assets", "characters", "user")
TARGET_TOP = 1.78   # cima della testa dell'adulto medio del kit


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


# Articolazioni per modello, in unità del gioco dopo centratura e scala (x a destra,
# y in alto, z in avanti). Misurate sul profilo del modello (vedi measure()).
PRESETS = {
    "guard": dict(
        neck=1.545,            # perno della testa
        shoulder_x=0.22, arm_y=1.395, elbow_x=0.48, wrist_x=0.70, arm_half=0.075,
        hips=0.9, hip_x=0.11, knee=0.48, ankle=0.105, ankle_x=0.235, leg_r=0.065,
        spine=0.96,
    ),
    # Guerriero dal foglio "Turntable game-ready" (tools/character_kit/sheet_to_model.py):
    # braccia un po' in giù verso le mani (arm_drop = discesa per unità di x)
    "warrior": dict(
        neck=1.53,
        shoulder_x=0.19, arm_y=1.404, elbow_x=0.47, wrist_x=0.71, arm_half=0.068, arm_drop=0.1,
        hips=0.92, hip_x=0.1, knee=0.49, ankle=0.11, ankle_x=0.18, leg_r=0.06,
        spine=0.98,
    ),
}


def arm_line(J, ax):
    """Altezza della linea del braccio a distanza ax dal centro."""
    return J["arm_y"] - max(0.0, ax - J["shoulder_x"]) * J.get("arm_drop", 0.0)


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    with bpy.context.temp_override(active_object=meshes[0], selected_editable_objects=meshes, selected_objects=meshes):
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    with bpy.context.temp_override(object=obj, active_object=obj, selected_editable_objects=[obj], selected_objects=[obj]):
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    return obj


def normalize(obj):
    """Piedi a terra, testa al centro, alto come l'adulto del kit."""
    me = obj.data
    cos = [v.co for v in me.vertices]
    top = max(c.z for c in cos)
    bottom = min(c.z for c in cos)
    head = [c for c in cos if c.z > bottom + (top - bottom) * 0.9]
    cx = (min(c.x for c in head) + max(c.x for c in head)) * 0.5
    s = TARGET_TOP / (top - bottom)
    for v in me.vertices:
        v.co = Vector(((v.co.x - cx) * s, v.co.y * s, (v.co.z - bottom) * s))
    me.update()
    return s


def measure(obj):
    """Profilo del modello (larghezza per altezza), per scegliere le articolazioni."""
    rows = {}
    for v in obj.data.vertices:
        g = Vector((v.co.x, v.co.z, -v.co.y))
        k = round(g.y / 0.05)
        lo, hi = rows.get(k, (9, -9))
        rows[k] = (min(lo, g.x), max(hi, g.x))
    for k in sorted(rows):
        print("  y %.2f  x %.3f .. %.3f" % (k * 0.05, rows[k][0], rows[k][1]))


def joints(J):
    sx, ay = J["shoulder_x"], J["arm_y"]
    out = {
        "hips": (0.0, J["hips"] + 0.03, 0.0),
        "spine": (0.0, J["spine"], 0.0),
        "head": (0.0, J["neck"], 0.0),
    }
    for side, s in (("l", -1.0), ("r", 1.0)):
        out["arm_" + side] = (s * sx, ay, 0.0)
        out["fore_" + side] = (s * J["elbow_x"], arm_line(J, J["elbow_x"]), 0.0)
        out["hand_" + side] = (s * J["wrist_x"], arm_line(J, J["wrist_x"]), 0.0)
        out["leg_" + side] = (s * J["hip_x"], J["hips"], 0.0)
        out["shin_" + side] = (s * leg_x(J, J["knee"]), J["knee"], 0.0)
    return out


def leg_x(J, y):
    t = (J["hips"] - y) / (J["hips"] - J["ankle"])
    t = max(0.0, min(1.0, t))
    return J["hip_x"] + (J["ankle_x"] - J["hip_x"]) * t


def weights(p, J):
    """Pesi delle ossa per un punto (coordinate del gioco)."""
    side = "l" if p.x < 0 else "r"
    ax = abs(p.x)
    sx, ay = J["shoulder_x"], J["arm_y"]
    w = {}
    # busto: bacino in basso, schiena in alto
    t = smooth((p.y - (J["hips"] - 0.02)) / 0.16)
    torso = {"hips": 1.0 - t, "spine": t}
    # braccio: fascia orizzontale fuori dalla spalla; vicino alla spalla si sfuma
    dy = p.y - arm_line(J, ax)
    if dy > 0.0:
        # sopra il braccio ci sono solo gli spallacci: vanno col braccio (niente "ali")
        band = 1.0
    else:
        band = 1.0 - smooth((-dy - J["arm_half"]) / 0.03)
        if ax > sx + 0.07:
            # sotto il braccio pende il mantello: taglio netto
            band = 1.0 if -dy < J["arm_half"] + 0.012 else 0.0
    a = smooth((ax - (sx - 0.04)) / 0.1) * band
    fore = smooth((ax - (J["elbow_x"] - 0.04)) / 0.08)
    hand = smooth((ax - (J["wrist_x"] - 0.02)) / 0.05)
    # testa
    h = smooth((p.y - (J["neck"] - 0.025)) / 0.05) * (1.0 - smooth((ax - 0.1) / 0.05))
    # gamba: solo vicino alla sua linea
    lw = 0.0
    if p.y < J["hips"] + 0.08:
        dist = abs(ax - leg_x(J, p.y))
        lw = (1.0 - smooth((dist - J["leg_r"]) / 0.045)) * smooth((J["hips"] + 0.06 - p.y) / 0.14)
        if p.y < J["ankle"] + 0.06:
            lw = max(lw, 1.0 - smooth((dist - J["leg_r"] - 0.06) / 0.04))
    knee = smooth((J["knee"] + 0.04 - p.y) / 0.08)
    rest = 1.0
    if h > 0.0:
        w["head"] = h
        rest -= h
    if a > 0.0 and rest > 0.0:
        aa = a * rest
        w["arm_" + side] = aa * (1.0 - fore)
        w["fore_" + side] = aa * fore * (1.0 - hand)
        w["hand_" + side] = aa * fore * hand
        rest -= aa
    if lw > 0.0 and rest > 0.0:
        ll = lw * rest
        w["leg_" + side] = ll * (1.0 - knee)
        w["shin_" + side] = ll * knee
        rest -= ll
    if rest > 0.0:
        for k, v in torso.items():
            w[k] = w.get(k, 0.0) + v * rest
    w = {k: v for k, v in w.items() if v > 1e-3}
    top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    s = sum(v for _, v in top) or 1.0
    return {k: v / s for k, v in top}


def arm_share(w):
    return sum(v for k, v in w.items() if k[:4] in ("arm_", "fore", "hand"))


## Apertura delle braccia nel gioco (character_model.gd, USER_ARM_OPEN) e massimo
## avvicinamento salvato nel colore (painted_model.gdshader, arm_front).
ARM_OPEN = 0.3
PULL_MAX = 0.3
CELL = 0.03


def arm_pulls(pts, ws, J):
    """Per ogni punto del braccio: di quanto sta dentro il corpo una volta abbassato.
    Griglia sul piano della vista frontale: davanti del corpo (z massimo senza braccia)
    contro davanti del braccio nella stessa cella, più un margine."""
    sx, ay = J["shoulder_x"], J["arm_y"]
    body = {}
    hang = [None] * len(pts)
    for i, p in enumerate(pts):
        a = arm_share(ws[i])
        if a < 0.05:
            key = (round(p.x / CELL), round(p.y / CELL))
            body[key] = max(body.get(key, -1.0), p.z)
            continue
        side = 1.0 if p.x > 0 else -1.0
        # dalla posa a T al braccio abbassato: rotazione attorno alla spalla
        ang = -side * (math.pi / 2 - ARM_OPEN)
        dx, dy = p.x - side * sx, p.y - ay
        c, s_ = math.cos(ang), math.sin(ang)
        hx, hy = side * sx + dx * c - dy * s_, ay + dx * s_ + dy * c
        hang[i] = (p.x + (hx - p.x) * a, p.y + (hy - p.y) * a)
    arm_front = {}
    for i, h in enumerate(hang):
        if h is None:
            continue
        key = (round(h[0] / CELL), round(h[1] / CELL))
        arm_front[key] = max(arm_front.get(key, -1.0), pts[i].z)
    out = [0.0] * len(pts)
    for i, h in enumerate(hang):
        if h is None:
            continue
        kx, ky = round(h[0] / CELL), round(h[1] / CELL)
        front = max(body.get((kx + ox, ky + oy), -1.0) for ox in (-1, 0, 1) for oy in (-1, 0, 1))
        if front < -0.5:
            continue
        own = arm_front[(kx, ky)]
        out[i] = max(0.0, front - own + 0.02) * arm_share(ws[i])
    return out


def cut_arm_bridges(obj, J, ws):
    """Toglie le facce che uniscono il braccio teso al mantello che gli pende sotto."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    kill = []
    for f in bm.faces:
        shares = [arm_share(ws[v.index]) for v in f.verts]
        if max(shares) > 0.5 and min(shares) < 0.5:
            c = f.calc_center_median()
            if abs(c.x) > J["shoulder_x"] + 0.06:
                kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(kill)


def clean(obj, faces=24000):
    """I modelli generati sono spesso triangoli sciolti: si uniscono i punti doppi
    (le UV restano per angolo di faccia, quindi non si rovinano) e si alleggerisce
    la mesh, così ogni eroe costa poco anche in una folla."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()
    n = len(obj.data.polygons)
    if n > faces:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = faces / n
        K.apply_modifiers(obj)
    print("punti %d -> %d, facce %d -> %d" % (before, len(obj.data.vertices), n, len(obj.data.polygons)))


def build(src, name, out_dir):
    J = PRESETS[name]
    obj = load(src)
    obj.name = "body_" + name
    clean(obj)
    s = normalize(obj)
    print("scala %.3f" % s)
    measure(obj)
    me = obj.data
    ws = [weights(Vector((v.co.x, v.co.z, -v.co.y)), J) for v in me.vertices]
    cut = cut_arm_bridges(obj, J, ws)
    # facce tagliate: restano punti isolati da togliere
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    me = obj.data
    ws = [weights(Vector((v.co.x, v.co.z, -v.co.y)), J) for v in me.vertices]
    print("facce tagliate tra braccia e mantello: %d" % cut)
    for poly in me.polygons:
        poly.use_smooth = True
    groups = {b: obj.vertex_groups.new(name=b) for b in K.BONE_NAMES}
    for i, w in enumerate(ws):
        for b, val in w.items():
            groups[b].add([i], val, "REPLACE")
    # colore dei punti: R = quanto il punto è braccio. Il modello è un bassorilievo e il
    # braccio abbassato finirebbe dentro il mantello: il gioco lo disegna davanti
    # (painted_model.gdshader), solo quando si guarda il personaggio da davanti.
    # Quanto avvicinarlo (G, in unità di PULL_MAX) si misura col braccio già abbassato
    # come nel gioco: davanti al mantello ma non di più, così lo scudo resta davanti
    # all'avambraccio.
    pulls = arm_pulls([Vector((v.co.x, v.co.z, -v.co.y)) for v in me.vertices], ws, J)
    col = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, w in enumerate(ws):
        col.data[i].color = (arm_share(w), min(1.0, pulls[i] / PULL_MAX), 0.0, 1.0)
    me.color_attributes.active_color = col
    # scheletro con le articolazioni del modello
    pos = joints(J)
    arm = bpy.data.armatures.new("Armature")
    arm_obj = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    with bpy.context.temp_override(object=arm_obj, active_object=arm_obj):
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = {}
        for bname, parent, _ in K.BONES:
            eb = arm.edit_bones.new(bname)
            h = Vector(K.to_blender(pos[bname]))
            eb.head = h
            eb.tail = h + Vector((0, 0, 0.08))
            eb.roll = 0.0
            if parent:
                eb.parent = ebs[parent]
            ebs[bname] = eb
        bpy.ops.object.mode_set(mode="OBJECT")
    K.bind(obj, arm_obj)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s.glb" % name)
    for o in bpy.context.scene.objects:
        o.select_set(o in (obj, arm_obj))
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_animations=False, export_skins=True, export_morph=False, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="AUTO", export_influence_nb=4, export_def_bones=False,
        export_rest_position_armature=True, export_extras=False, export_vertex_color="ACTIVE",
    )
    print("  %s: %d punti" % (path, len(me.vertices)))


def main():
    args = sys.argv[1:]
    src = args[0]
    name = args[1]
    out_dir = args[2] if len(args) > 2 else DEFAULT_OUT
    build(src, name, out_dir)


if __name__ == "__main__":
    main()
