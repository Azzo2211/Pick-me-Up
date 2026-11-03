"""Strumenti comuni del kit dei personaggi.

Tutto si costruisce in coordinate Godot (x a destra, y in alto, z in avanti: il
personaggio guarda verso +z) e in unità dello scheletro di CharacterModel (un
adulto medio è alto circa 1,78). Solo alla fine i punti passano a Blender.

Una "gabbia" (Cage) è una mesh grezza fatta di anelli: Blender la suddivide
(superficie di suddivisione), così le forme diventano morbide. Ogni faccia ha un
"posto" della tavolozza (pelle, stoffa principale, metallo...): in Godot il colore
di ogni posto lo decide l'eroe. Il posto viaggia nella seconda UV (x = posto,
y = ombra fissa), che il formato glTF non converte come fa con i colori.
"""
import math
import bpy
import bmesh
from mathutils import Vector

# Posti della tavolozza: lo stesso elenco è in scripts/characters/character_kit.gd
SKIN, MAIN, SECOND, LIGHT, LEATHER, METAL, GOLD, DARK, BOOT, ACCENT, WOOD, LIGHT2, METAL_DARK, MOUTH, LINE = range(15)

# Scheletro: le stesse articolazioni di CharacterModel, con il riposo dell'adulto medio.
BONES = [
    ("hips", None, (0.0, 0.95, 0.0)),
    ("spine", "hips", (0.0, 1.01, 0.0)),
    ("head", "spine", (0.0, 1.51, 0.0)),
    ("arm_l", "spine", (-0.2, 1.43, 0.0)),
    ("fore_l", "arm_l", (-0.2, 1.14, 0.0)),
    ("hand_l", "fore_l", (-0.2, 0.88, 0.0)),
    ("arm_r", "spine", (0.2, 1.43, 0.0)),
    ("fore_r", "arm_r", (0.2, 1.14, 0.0)),
    ("hand_r", "fore_r", (0.2, 0.88, 0.0)),
    ("leg_l", "hips", (-0.1, 0.92, 0.0)),
    ("shin_l", "leg_l", (-0.1, 0.47, 0.0)),
    ("leg_r", "hips", (0.1, 0.92, 0.0)),
    ("shin_r", "leg_r", (0.1, 0.47, 0.0)),
]
BONE_NAMES = [b[0] for b in BONES]
HEAD_PIVOT = Vector((0.0, 1.51, 0.0))


def to_blender(p):
    return (p[0], -p[2], p[1])


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def sgnpow(v, e):
    return math.copysign(abs(v) ** e, v)


def ring(center, rx, zf, zb=None, n=16, power=2.0, power_back=None, mod=None, axis="y"):
    """Anello orizzontale (asse y) a superellisse: rx mezza larghezza, zf profondità
    davanti, zb dietro. power 2 = ellisse, più alto = più squadrato. Il punto 0 è
    davanti (+z), si gira verso +x. mod(angolo, punto) può spostare i punti.
    Con axis="z" l'anello sta nel piano xy (per i piedi): rx in x, zf sopra, zb sotto."""
    zb = zf if zb is None else zb
    pb = power if power_back is None else power_back
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        s, c = math.sin(a), math.cos(a)
        pw = power if c >= 0.0 else pb
        e = 2.0 / pw
        x = rx * sgnpow(s, e)
        d = (zf if c >= 0.0 else zb) * sgnpow(c, e)
        if axis == "y":
            p = Vector((center[0] + x, center[1], center[2] + d))
        else:
            p = Vector((center[0] + x, center[1] + d, center[2]))
        if mod is not None:
            p = mod(a, p)
        pts.append(p)
    return pts


class Cage:
    """Mesh grezza: punti, facce, posto di tavolozza per faccia, pesi delle ossa,
    ombra fissa (ao) e pieghe nette (crease) per punto."""

    def __init__(self):
        self.v = []
        self.f = []
        self.fs = []
        self.w = []
        self.ao = []
        self.crease = []

    def vert(self, p, w, ao=1.0):
        self.v.append(Vector(p))
        self.w.append(dict(w))
        self.ao.append(ao)
        return len(self.v) - 1

    def face(self, ids, slot):
        self.f.append(tuple(ids))
        self.fs.append(slot)

    def loft(self, rings, slot, weights, cap_start=True, cap_end=True, closed=True, slot_fn=None, ao_fn=None,
             crease_start=0.0, crease_end=0.0):
        """Unisce gli anelli in un tubo. weights(p) -> {osso: peso}. slot_fn(k, i, p) può
        cambiare il posto della faccia tra l'anello k e k+1 al segmento i."""
        n = len(rings[0])
        idx = []
        for r in rings:
            row = []
            for p in r:
                row.append(self.vert(p, weights(p), ao_fn(p) if ao_fn else 1.0))
            idx.append(row)
        segs = n if closed else n - 1
        for k in range(len(rings) - 1):
            for i in range(segs):
                j = (i + 1) % n
                ids = (idx[k][i], idx[k][j], idx[k + 1][j], idx[k + 1][i])
                s = slot
                if slot_fn is not None:
                    mid = (rings[k][i] + rings[k][j] + rings[k + 1][i] + rings[k + 1][j]) * 0.25
                    s = slot_fn(k, i, mid)
                self.face(ids, s)
        if closed and cap_start:
            self.face(list(reversed(idx[0])), slot if slot_fn is None else slot_fn(-1, 0, rings[0][0]))
        if closed and cap_end:
            self.face(idx[-1], slot if slot_fn is None else slot_fn(len(rings) - 1, 0, rings[-1][0]))
        if crease_start > 0.0:
            for i in range(segs):
                self.crease.append((idx[0][i], idx[0][(i + 1) % n], crease_start))
        if crease_end > 0.0:
            for i in range(segs):
                self.crease.append((idx[-1][i], idx[-1][(i + 1) % n], crease_end))
        return idx

    def sheet(self, grid, slot, weights, thickness, normal_fn=None, slot_fn=None, ao_back=0.8, crease=0.0):
        """Foglio con spessore (mantelli, grembiuli, piastre): grid[k][i] è la faccia
        esterna; si stacca un secondo strato verso l'interno di `thickness`.
        normal_fn(p) dà la direzione verso l'esterno (di solito dal centro del corpo)."""
        rows = len(grid)
        cols = len(grid[0])
        outer = []
        inner = []
        for k in range(rows):
            ro = []
            ri = []
            for i in range(cols):
                p = grid[k][i]
                # normale della superficie dalla griglia stessa
                a = grid[min(k + 1, rows - 1)][i] - grid[max(k - 1, 0)][i]
                b = grid[k][min(i + 1, cols - 1)] - grid[k][max(i - 1, 0)]
                nrm = b.cross(a)
                if nrm.length < 1e-9:
                    nrm = Vector((0, 0, 1))
                nrm.normalize()
                if normal_fn is not None and nrm.dot(normal_fn(p)) < 0.0:
                    nrm = -nrm
                ro.append(self.vert(p, weights(p), 1.0))
                ri.append(self.vert(p - nrm * thickness, weights(p), ao_back))
            outer.append(ro)
            inner.append(ri)
        for k in range(rows - 1):
            for i in range(cols - 1):
                mid = (grid[k][i] + grid[k + 1][i + 1]) * 0.5
                s = slot_fn(k, i, mid) if slot_fn else slot
                self.face((outer[k][i], outer[k][i + 1], outer[k + 1][i + 1], outer[k + 1][i]), s)
                self.face((inner[k][i], inner[k + 1][i], inner[k + 1][i + 1], inner[k][i + 1]), s)
        # bordi
        border = []
        for i in range(cols - 1):
            border.append((outer[0][i], outer[0][i + 1], inner[0][i + 1], inner[0][i]))
            border.append((outer[-1][i + 1], outer[-1][i], inner[-1][i], inner[-1][i + 1]))
        for k in range(rows - 1):
            border.append((outer[k + 1][0], outer[k][0], inner[k][0], inner[k + 1][0]))
            border.append((outer[k][-1], outer[k + 1][-1], inner[k + 1][-1], inner[k][-1]))
        for b in border:
            mid = (self.v[b[0]] + self.v[b[1]]) * 0.5
            self.face(b, slot_fn(0, 0, mid) if slot_fn else slot)
        if crease > 0.0:
            for b in border:
                self.crease.append((b[0], b[1], crease))
                self.crease.append((b[2], b[3], crease))
        return outer, inner

    def merge(self, other):
        off = len(self.v)
        self.v += other.v
        self.w += other.w
        self.ao += other.ao
        self.f += [tuple(i + off for i in f) for f in other.f]
        self.fs += other.fs
        self.crease += [(a + off, b + off, c) for a, b, c in other.crease]


# -----------------------------------------------------------------------------
# Da gabbia a oggetto Blender
# -----------------------------------------------------------------------------

def _link(obj):
    bpy.context.scene.collection.objects.link(obj)


def cage_to_object(cage, name, levels=2, groups=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([to_blender(p) for p in cage.v], [], cage.f)
    me.update()
    for i, poly in enumerate(me.polygons):
        poly.material_index = cage.fs[i]
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    _link(obj)
    # pieghe nette
    if cage.crease:
        edge_of = {}
        for e in me.edges:
            a, b = e.vertices
            edge_of[(min(a, b), max(a, b))] = e.index
        attr = me.attributes.get("crease_edge") or me.attributes.new("crease_edge", "FLOAT", "EDGE")
        for a, b, c in cage.crease:
            ei = edge_of.get((min(a, b), max(a, b)))
            if ei is not None:
                attr.data[ei].value = c
    # normali verso l'esterno, isola per isola
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    fix_inside_out(bm)
    bm.to_mesh(me)
    bm.free()
    if groups:
        vgs = {b: obj.vertex_groups.new(name=b) for b in BONE_NAMES}
        for i, w in enumerate(cage.w):
            for b, val in w.items():
                if val > 1e-4:
                    vgs[b].add([i], val, "REPLACE")
    ao = obj.vertex_groups.new(name="_ao")
    for i, a in enumerate(cage.ao):
        ao.add([i], a, "REPLACE")
    if levels > 0:
        mod = obj.modifiers.new("sub", "SUBSURF")
        mod.levels = levels
        mod.render_levels = levels
        mod.use_creases = True
        apply_modifiers(obj)
    return obj


def _islands(bm):
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, island = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        yield island


def fix_inside_out(bm):
    """recalc_face_normals sbaglia sui gusci sottili (spallacci, ginocchiere): li gira
    tutti verso l'interno, e il contorno nero li copre. Per ogni pezzo chiuso il volume
    con segno dice da che parte guardano davvero le facce: se è negativo si girano."""
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    flipped = 0
    for island in _islands(bm):
        if any(e.is_boundary for f in island for e in f.edges):
            continue
        vol = 0.0
        for f in island:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1]))
        if vol < 0.0:
            bmesh.ops.reverse_faces(bm, faces=island)
            flipped += 1
    return flipped


def apply_modifiers(obj):
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        for m in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)


def finish_attributes(obj, uv_fn=None, front_fn=None):
    """Dopo la suddivisione: seconda UV = (posto, ombra fissa) e prima UV dal
    proiettore uv_fn(punto godot) (il volto), altrimenti zero."""
    me = obj.data
    ao_group = obj.vertex_groups.get("_ao")
    ao = [1.0] * len(me.vertices)
    if ao_group is not None:
        gi = ao_group.index
        for v in me.vertices:
            for g in v.groups:
                if g.group == gi:
                    ao[v.index] = g.weight
        obj.vertex_groups.remove(ao_group)
    uv0 = me.uv_layers.new(name="UVMap")
    uv1 = me.uv_layers.new(name="Slot")
    for poly in me.polygons:
        slot = float(poly.material_index)
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            gp = Vector((co.x, co.z, -co.y))
            # glTF capovolge la v (v' = 1 - v): la si scrive già capovolta, così in Godot
            # arriva il valore giusto
            u, v = uv_fn(gp) if uv_fn else (0.0, 0.0)
            uv0.data[li].uv = (u, 1.0 - v)
            second = front_fn(gp) if front_fn else ao[vi]
            uv1.data[li].uv = (slot, 1.0 - second)
        poly.material_index = 0
    for poly in me.polygons:
        poly.use_smooth = True


def positions(obj):
    return [v.co.copy() for v in obj.data.vertices]


def add_shape_keys(obj, variants):
    """variants: {nome: [co blender per punto]} con la stessa topologia."""
    obj.shape_key_add(name="Basis", from_mix=False)
    for name, cos in variants.items():
        sk = obj.shape_key_add(name=name, from_mix=False)
        if len(cos) != len(sk.data):
            raise RuntimeError("variante %s: %d punti invece di %d" % (name, len(cos), len(sk.data)))
        for i, co in enumerate(cos):
            sk.data[i].co = co


def remove(obj):
    me = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


def make_armature():
    arm = bpy.data.armatures.new("Armature")
    obj = bpy.data.objects.new("Armature", arm)
    _link(obj)
    bpy.context.view_layer.objects.active = obj
    with bpy.context.temp_override(object=obj, active_object=obj):
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = {}
        for name, parent, head in BONES:
            eb = arm.edit_bones.new(name)
            h = Vector(to_blender(head))
            eb.head = h
            # tutte le ossa puntano in alto, senza rollio: in glTF il riposo non ha rotazioni
            eb.tail = h + Vector((0, 0, 0.08))
            eb.roll = 0.0
            if parent:
                eb.parent = ebs[parent]
            ebs[name] = eb
        bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def bind(mesh_obj, arm_obj):
    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)


def export_glb(path, objects):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
        export_animations=False, export_skins=True, export_morph=True, export_morph_normal=True,
        export_texcoords=True, export_normals=True, export_materials="NONE", export_vertex_color="NONE",
        export_influence_nb=4, export_def_bones=False, export_rest_position_armature=True, export_extras=False,
    )
