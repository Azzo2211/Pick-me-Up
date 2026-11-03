"""Testa base del kit (senza capelli), come nel foglio: cranio tondo, viso piatto sul
davanti dove lo shader disegna occhi e bocca, mascella che scende a un mento
piccolo. I tre volti (bello, comune, rude), il viso femminile e le guance piene
sono chiavi di forma. Coordinate: rispetto al perno della testa di CharacterModel.
"""
import math
from mathutils import Vector
from kit_core import Cage, ring, smooth, lerp, sgnpow, SKIN, DARK, GOLD, LIGHT, METAL

# Altezza degli occhi e scala delle coordinate del volto (UV): lo shader del volto
# lavora in queste unità (x da -1 a 1 è la larghezza della faccia).
EYE_Y = 0.138
FACE_S = 0.1
CENTER = Vector((0.0, 0.165, -0.009))

# y, rx, zf, zb, potenza davanti, potenza dietro
HEAD_TABLE = [
    (0.272, 0.014, 0.014, 0.014, 2.0, 2.0),
    (0.263, 0.05, 0.048, 0.058, 2.0, 2.0),
    (0.248, 0.076, 0.071, 0.086, 2.05, 2.0),
    (0.226, 0.092, 0.086, 0.103, 2.15, 2.0),
    (0.2, 0.1, 0.094, 0.111, 2.3, 2.05),
    (0.172, 0.102, 0.097, 0.113, 2.45, 2.1),
    (0.148, 0.101, 0.098, 0.111, 2.7, 2.15),
    (0.126, 0.098, 0.096, 0.104, 2.6, 2.2),
    (0.106, 0.093, 0.093, 0.093, 2.3, 2.3),
    (0.089, 0.085, 0.09, 0.078, 2.0, 2.5),
    (0.073, 0.073, 0.087, 0.06, 1.72, 2.6),
    (0.059, 0.059, 0.083, 0.048, 1.52, 2.5),
    (0.046, 0.043, 0.077, 0.043, 1.42, 2.3),
    (0.036, 0.029, 0.066, 0.04, 1.5, 2.2),
    (0.028, 0.03, 0.035, 0.038, 2.0, 2.0),
    (0.012, 0.031, 0.03, 0.036, 2.0, 2.0),
]


# Viso degli anime: la parte sotto gli occhi è più corta del vero, la mascella più
# piena. Le altezze sotto gli occhi della tabella si accorciano di questo fattore.
LOWER_FACE = 0.94
JAW_FILL = 1.02


def squash(y):
    return y if y >= 0.148 else 0.148 - (0.148 - y) * LOWER_FACE


HEAD_TABLE = [(squash(y), rx * (JAW_FILL if 0.04 < y < 0.1 else 1.0), zf, zb, pf + (0.12 if 0.04 < y < 0.1 else 0.0), pb)
              for y, rx, zf, zb, pf, pb in HEAD_TABLE]


def head_table(kind=""):
    rows = []
    for y, rx, zf, zb, pf, pb in HEAD_TABLE:
        jaw = smooth((0.12 - y) / 0.08)       # 0 sopra le guance, 1 sul mento
        low = smooth((0.1 - y) / 0.05)
        if kind == "fem":
            rx *= 1.0 - 0.07 * jaw
            zf *= 1.0 - 0.025 * jaw
            if y < 0.05:
                rx *= 0.92
        elif kind == "sharp":
            rx *= 1.0 - 0.09 * jaw
            pf = lerp(pf, max(1.3, pf - 0.2), jaw)
        elif kind == "square":
            rx *= 1.0 + 0.11 * jaw * (1.0 - 0.5 * smooth((0.05 - y) / 0.02))
            pf = lerp(pf, pf + 0.45, low)
            zf += 0.002 * low
            if 0.15 < y < 0.18:
                zf += 0.003
        elif kind == "full":
            cheek = math.exp(-((y - 0.085) / 0.03) ** 2)
            rx += 0.009 * cheek
            zf += 0.003 * cheek
            zb += 0.006 * low
        rows.append((y, rx, zf, zb, pf, pb))
    return rows


def _interp(table, y):
    if y >= table[0][0]:
        return table[0][1:]
    for i in range(len(table) - 1):
        y0, y1 = table[i][0], table[i + 1][0]
        if y1 <= y <= y0:
            t = (y0 - y) / (y0 - y1)
            return tuple(lerp(table[i][k], table[i + 1][k], t) for k in range(1, 6))
    return table[-1][1:]


def head_point(y, a, table=None, lift=0.0):
    """Punto della testa all'altezza y e all'angolo a (0 = davanti, verso +x)."""
    rx, zf, zb, pf, pb = _interp(table or HEAD_TABLE, y)
    s, c = math.sin(a), math.cos(a)
    p = pf if c >= 0 else pb
    e = 2.0 / p
    x = rx * sgnpow(s, e)
    z = (zf if c >= 0 else zb) * sgnpow(c, e)
    pt = Vector((x, y, z + CENTER.z))
    # naso appena accennato
    if c > 0:
        nose = math.exp(-((y - squash(0.108)) / 0.013) ** 2) * math.exp(-(a / 0.16) ** 2)
        pt.z += 0.0075 * nose
    if lift != 0.0:
        pt += head_normal(pt) * lift
    return pt


def head_normal(p):
    """Direzione verso l'esterno, abbastanza buona per staccare capelli e accessori."""
    v = p - CENTER
    if p.y < CENTER.y:
        v.y *= 0.35
    if v.length < 1e-6:
        return Vector((0, 1, 0))
    return v.normalized()


HEAD_YS = [squash(y) for y in (0.272, 0.268, 0.263, 0.256, 0.248, 0.238, 0.226, 0.213, 0.2, 0.186, 0.172, 0.16, 0.148,
                                0.137, 0.126, 0.116, 0.106, 0.097, 0.089, 0.081, 0.073, 0.066, 0.059, 0.052, 0.046, 0.041,
                                0.036, 0.032, 0.028, 0.02, 0.012)]


def build_head(kind=""):
    table = head_table(kind)
    c = Cage()
    n = 32
    rings = [[head_point(y, 2 * math.pi * i / n, table) for i in range(n)] for y in HEAD_YS]
    c.loft(rings, SKIN, lambda p: {"head": 1.0})
    # orecchie: ovali sottili inclinati all'indietro, un po' staccati dal cranio
    for side in (-1.0, 1.0):
        rings = []
        for y, w, d in ((0.163, 0.004, 0.006), (0.157, 0.009, 0.015), (0.142, 0.012, 0.021), (squash(0.124), 0.012, 0.021),
                        (squash(0.108), 0.01, 0.016), (squash(0.097), 0.006, 0.009), (squash(0.092), 0.003, 0.004)):
            x = side * (0.094 + 0.004 * smooth((y - 0.1) / 0.05))
            z = -0.018 - 0.01 * smooth((y - 0.1) / 0.06)
            rings.append(ring((x, y, z), w, d, n=8))
        c.loft(rings, SKIN, lambda p: {"head": 1.0})
    return c


def face_uv(p):
    return (p.x / FACE_S, (p.y - EYE_Y) / FACE_S)


def face_front(p):
    a = math.atan2(p.x, p.z - CENTER.z)
    f = max(0.0, math.cos(a))
    if p.y > 0.235:
        f *= 1.0 - smooth((p.y - 0.235) / 0.02)
    return f


# -----------------------------------------------------------------------------
# Accessori della testa
# -----------------------------------------------------------------------------

def eye_center(side):
    p = head_point(EYE_Y, side * 0.42)
    return Vector((side * 0.039, EYE_Y, p.z))


def build_glasses():
    """Occhiali tondi da studioso: due cerchi, il ponte e le stanghette fino alle orecchie."""
    c = Cage()
    w = lambda p: {"head": 1.0}
    for side in (-1.0, 1.0):
        ctr = eye_center(side) + Vector((0, 0.002, 0.016))
        rings = []
        m = 18
        for i in range(m + 1):
            a = 2 * math.pi * i / m
            p = ctr + Vector((math.cos(a) * 0.023, math.sin(a) * 0.021, 0.0))
            rings.append(ring_tube(p, Vector((-math.sin(a), math.cos(a), 0)), 0.0022))
        c.loft(rings, DARK, w, cap_start=False, cap_end=False)
        # stanghetta
        a0 = ctr + Vector((side * 0.023, 0.0, 0.0))
        pts = [a0, a0 + Vector((side * 0.012, 0.0, -0.01)), Vector((side * 0.101, EYE_Y + 0.004, -0.02)),
               Vector((side * 0.1, EYE_Y - 0.004, -0.045))]
        rings = [ring_tube(pts[k], (pts[min(k + 1, 3)] - pts[max(k - 1, 0)]).normalized(), 0.0018) for k in range(4)]
        c.loft(rings, DARK, w)
    l = eye_center(-1) + Vector((0.023, 0.006, 0.016))
    r = eye_center(1) + Vector((-0.023, 0.006, 0.016))
    mid = (l + r) * 0.5 + Vector((0, 0.003, 0.004))
    pts = [l, mid, r]
    rings = [ring_tube(pts[k], (pts[min(k + 1, 2)] - pts[max(k - 1, 0)]).normalized(), 0.0018) for k in range(3)]
    c.loft(rings, DARK, w)
    return c


def ring_tube(center, tangent, r, n=5):
    t = tangent.normalized()
    a = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    u = t.cross(a).normalized()
    v = t.cross(u).normalized()
    return [center + (u * math.cos(2 * math.pi * i / n) + v * math.sin(2 * math.pi * i / n)) * r for i in range(n)]


def build_headband():
    """Fascia di stoffa sulla fronte, annodata dietro (popolano del foglio)."""
    c = Cage()
    n = 28
    rings = []
    for y, lift in ((0.212, 0.0105), (0.207, 0.0135), (0.19, 0.0135), (0.185, 0.0105)):
        row = []
        for i in range(n):
            a = 2 * math.pi * i / n
            yy = y + 0.022 * (1 - math.cos(a)) * 0.5   # dietro sale un po'
            row.append(head_point(yy, a, lift=lift + 0.026))
        rings.append(row)
    c.loft(rings, LIGHT, lambda p: {"head": 1.0}, cap_start=False, cap_end=False)
    # nodo e due code dietro
    knot = head_point(0.22, math.pi, lift=0.044)
    from kit_body import box
    box(c, knot, (0.026, 0.02, 0.016), LIGHT, lambda p: {"head": 1.0}, crease=0.3)
    for side in (-1.0, 1.0):
        pts = [knot + Vector((side * 0.006, -0.004, -0.004)), knot + Vector((side * 0.02, -0.03, -0.012)),
               knot + Vector((side * 0.028, -0.06, -0.008))]
        rows = [[p + Vector((-0.007, 0, 0)), p + Vector((0.007, 0, 0))] for p in pts]
        c.sheet(rows, LIGHT, lambda p: {"head": 1.0}, 0.003, normal_fn=lambda p: Vector((0, 0, -1)))
    return c


MOUTH_Y = EYE_Y - 0.06   # altezza della bocca disegnata (mouth_y = -0.6 nello shader)


def build_beard(kind="short"):
    """Barba del foglio (mercante, studioso anziano): un guscio morbido sulla mascella che
    nasce sottile sulle guance e diventa più folto sul mento, con i baffi sopra la bocca;
    la bocca resta libera. Il pizzetto copre solo il mento."""
    c = Cage()
    w = lambda p: {"head": 1.0}
    chin = squash(0.012) + 0.004
    span = 1.62 if kind != "goatee" else 0.5
    cols = 23 if kind != "goatee" else 9
    rows = 9

    def top(a):
        x = abs(a)
        if kind == "goatee":
            return MOUTH_Y - 0.012
        # basetta davanti all'orecchio, guancia, poi sotto la bocca
        if x > 1.2:
            return lerp(0.104, 0.128, smooth((x - 1.2) / 0.4))
        if x > 0.52:
            return lerp(MOUTH_Y - 0.004, 0.104, smooth((x - 0.52) / 0.68))
        return MOUTH_Y - 0.013

    grid = []
    for k in range(rows):
        t = k / (rows - 1)
        row = []
        for i in range(cols):
            a = lerp(-span, span, i / (cols - 1))
            y = lerp(top(a), chin, t ** 0.9)
            lift = 0.0015 + 0.009 * smooth(t * 1.2) * (1.0 - 0.45 * smooth((abs(a) - 0.9) / 0.6))
            row.append(head_point(y, a, lift=lift))
        grid.append(row)
    # sotto il mento il guscio rientra verso il collo
    last = grid[-1]
    grid.append([Vector((p.x * 0.82, p.y - 0.01, CENTER.z + (p.z - CENTER.z) * 0.78)) for p in last])
    c.sheet(grid, DARK, w, 0.003, normal_fn=lambda p: head_normal(p), crease=0.0)
    if kind != "goatee":
        # baffi: una striscia sopra la bocca che scende ai lati fino alla barba
        pts = []
        for i in range(11):
            a = lerp(-0.62, 0.62, i / 10)
            y = MOUTH_Y + 0.013 - 0.016 * smooth((abs(a) - 0.2) / 0.42)
            pts.append((y, a))
        rows_m = []
        for dy, lift in ((0.006, 0.0015), (0.0, 0.0055), (-0.007, 0.002)):
            rows_m.append([head_point(y + dy * (1.0 - 0.4 * smooth((abs(a) - 0.3) / 0.3)), a, lift=lift) for y, a in pts])
        c.sheet(rows_m, DARK, w, 0.0025, normal_fn=lambda p: head_normal(p))
    return c
