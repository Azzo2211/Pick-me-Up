"""Corpi vestiti del kit: un'unica mesh per vestito (pelle, abiti e accessori),
legata allo scheletro di CharacterModel. Le corporature del foglio (snello, medio,
atletico, muscoloso, robusto) e il corpo femminile sono chiavi di forma della
stessa mesh: si costruisce lo stesso vestito con misure diverse e Blender ne
ricava le differenze.
"""
import math
from mathutils import Vector
from kit_core import (Cage, ring, smooth, lerp, sgnpow, SKIN, MAIN, SECOND, LIGHT, LEATHER, METAL, GOLD, DARK,
                      BOOT, ACCENT, WOOD, LIGHT2, METAL_DARK)

# -----------------------------------------------------------------------------
# Misure
# -----------------------------------------------------------------------------

AVERAGE = dict(
    sh=0.2, leg_x=0.1,
    chest=0.156, chest_d=0.098, waist=0.126, waist_d=0.084, hip=0.144, hip_d=0.093, bust=0.0, belly=0.0, pec=0.006,
    neck=0.05, trap=0.118, delt=0.043, arm=0.037, elbow=0.03, fore=0.033, wrist=0.023,
    thigh=0.073, knee=0.049, calf=0.051, ankle=0.031, hand=1.0, foot=1.0,
)


def body_params(kind):
    P = dict(AVERAGE)
    if kind == "fem":
        P.update(sh=0.19, chest=0.136, chest_d=0.088, waist=0.106, waist_d=0.074, hip=0.152, hip_d=0.098, bust=1.0, pec=0.0,
                 neck=0.041, trap=0.098, delt=0.034, arm=0.031, elbow=0.025, fore=0.027, wrist=0.019,
                 thigh=0.073, knee=0.044, calf=0.046, ankle=0.027, hand=0.88, foot=0.9)
    elif kind == "slim":
        for k in ("chest", "chest_d", "waist", "waist_d", "hip", "hip_d", "trap", "delt", "arm", "elbow", "fore", "thigh",
                  "knee", "calf"):
            P[k] *= 0.9
        P.update(sh=0.195, neck=0.046)
    elif kind == "athletic":
        P.update(sh=0.205, chest=0.166, chest_d=0.104, waist=0.128, delt=0.048, arm=0.041, fore=0.036, thigh=0.077,
                 calf=0.054, trap=0.124, neck=0.053, pec=0.01)
    elif kind == "muscular":
        P.update(sh=0.214, chest=0.182, chest_d=0.116, waist=0.14, waist_d=0.09, hip=0.15, delt=0.056, arm=0.047,
                 elbow=0.036, fore=0.041, wrist=0.027, thigh=0.084, knee=0.054, calf=0.058, trap=0.136, neck=0.058,
                 pec=0.016, hand=1.08)
    elif kind == "chubby":
        P.update(sh=0.208, chest=0.17, chest_d=0.112, waist=0.164, waist_d=0.118, hip=0.166, hip_d=0.108, belly=0.03,
                 delt=0.05, arm=0.045, elbow=0.037, fore=0.039, thigh=0.086, knee=0.056, calf=0.056, trap=0.128,
                 neck=0.056, pec=0.012, hand=1.05)
    return P


VARIANTS = ["fem", "slim", "athletic", "muscular", "chubby"]

# -----------------------------------------------------------------------------
# Pesi delle ossa
# -----------------------------------------------------------------------------

def _clean(w):
    w = {k: v for k, v in w.items() if v > 1e-3}
    top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    s = sum(v for _, v in top) or 1.0
    return {k: v / s for k, v in top}


def side_of(p):
    return "l" if p.x < 0.0 else "r"


def w_torso(p):
    t = smooth((p.y - 0.97) / 0.11)
    w = {"hips": 1.0 - t, "spine": t}
    if p.y > 1.49:
        h = smooth((p.y - 1.49) / 0.08)
        w = {"hips": w["hips"] * (1 - h), "spine": w["spine"] * (1 - h), "head": h}
    return _clean(w)


def w_arm(p):
    s = side_of(p)
    a = smooth((1.49 - p.y) / 0.08)
    e = smooth((1.19 - p.y) / 0.09)
    h = smooth((0.93 - p.y) / 0.05)
    return _clean({"spine": 1 - a, "arm_" + s: a * (1 - e), "fore_" + s: a * e * (1 - h), "hand_" + s: a * e * h})


def w_hand(p):
    s = side_of(p)
    h = smooth((0.93 - p.y) / 0.04)
    return _clean({"fore_" + s: 1 - h, "hand_" + s: h})


def w_leg(p):
    s = side_of(p)
    a = smooth((1.0 - p.y) / 0.12)
    k = smooth((0.53 - p.y) / 0.1)
    return _clean({"hips": 1 - a, "leg_" + s: a * (1 - k), "shin_" + s: a * k})


def w_foot(p):
    return {"shin_" + side_of(p): 1.0}


def w_skirt(p, follow=0.55):
    """Gonne e falde: il bacino le porta, in basso seguono un po' le gambe."""
    if p.y > 1.0:
        return w_torso(p)
    s = side_of(p)
    share = smooth((0.98 - p.y) / 0.5) * follow * smooth((abs(p.x) - 0.01) / 0.07)
    return _clean({"hips": 1 - share, "leg_" + s: share})


def w_cape(p):
    if p.y > 1.05:
        return w_torso(p)
    t = smooth((1.05 - p.y) / 0.3) * 0.5
    return _clean({"spine": 1 - t, "hips": t})


def w_spine(p):
    return {"spine": 1.0}


def w_hips(p):
    return {"hips": 1.0}


# -----------------------------------------------------------------------------
# Busto come funzione continua (per appoggiarci sopra grembiuli, cinghie, piastre)
# -----------------------------------------------------------------------------

def torso_profile(P):
    """(y, rx, zf, zb) dal cavallo al collo."""
    hip, hd, wa, wd, ch, cd = P["hip"], P["hip_d"], P["waist"], P["waist_d"], P["chest"], P["chest_d"]
    b = P["belly"]
    return [
        (0.86, hip * 0.86, hd * 0.8, hd * 0.86),
        (0.92, hip * 0.97, hd * 0.92, hd * 1.02),
        (0.98, hip, hd * 0.97, hd * 1.08),
        (1.05, (hip + wa) * 0.5, wd * 1.02 + b * 0.5, wd * 1.04),
        (1.12, wa, wd + b, wd * 0.96),
        (1.19, lerp(wa, ch, 0.45), lerp(wd, cd, 0.45) + b * 0.75, lerp(wd, cd, 0.5) * 0.95),
        (1.26, ch * 0.98, cd * 0.98 + b * 0.3, cd * 0.92),
        (1.32, ch, cd, cd * 0.94),
        (1.38, ch * 1.03, cd * 0.94, cd * 0.93),
        (1.43, ch * 1.04, cd * 0.8, cd * 0.86),
        (1.465, P["trap"] * 1.18, cd * 0.62, cd * 0.7),
        (1.49, P["trap"] * 0.78, P["neck"] * 1.35, P["neck"] * 1.55),
        (1.505, P["neck"] * 1.2, P["neck"] * 1.1, P["neck"] * 1.3),
    ]


def _interp_profile(prof, y):
    if y <= prof[0][0]:
        return prof[0][1:]
    for i in range(len(prof) - 1):
        y0, y1 = prof[i][0], prof[i + 1][0]
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            t = t * t * (3 - 2 * t) * 0.5 + t * 0.5
            return tuple(lerp(prof[i][k], prof[i + 1][k], t) for k in (1, 2, 3))
    return prof[-1][1:]


TORSO_POWER = 2.4


def chest_bump(P, x, y):
    """Petto: seno per il corpo femminile, pettorali per quello maschile."""
    bump = 0.0
    if P["bust"] > 0.0:
        for sx in (-1.0, 1.0):
            dx = (x - sx * 0.058) / 0.048
            dy = (y - 1.3) / 0.052
            bump += 0.034 * P["bust"] * math.exp(-(dx * dx + dy * dy) * 1.4)
    if P["pec"] > 0.0:
        for sx in (-1.0, 1.0):
            dx = (x - sx * 0.065) / 0.06
            dy = (y - 1.335) / 0.05
            bump += P["pec"] * math.exp(-(dx * dx + dy * dy) * 1.5)
    return bump


def torso_point(P, y, a, inflate=0.0, prof=None):
    prof = prof or torso_profile(P)
    rx, zf, zb = _interp_profile(prof, y)
    s, c = math.sin(a), math.cos(a)
    e = 2.0 / TORSO_POWER
    x = (rx + inflate) * sgnpow(s, e)
    if c >= 0:
        z = (zf + inflate) * sgnpow(c, e)
        z += chest_bump(P, x, y) * min(1.0, c * 2.0)
    else:
        z = (zb + inflate) * sgnpow(c, e)
    return Vector((x, y, z - 0.006))


def torso_front_z(P, x, y, inflate=0.0):
    """Profondità del davanti del busto all'altezza y e alla x data."""
    rx, zf, zb = _interp_profile(torso_profile(P), y)
    rx += inflate
    u = min(0.999, abs(x) / rx)
    z = (zf + inflate) * (1.0 - u ** TORSO_POWER) ** (1.0 / TORSO_POWER)
    return z + chest_bump(P, x, y) - 0.006


def torso_back_z(P, x, y, inflate=0.0):
    rx, zf, zb = _interp_profile(torso_profile(P), y)
    rx += inflate
    u = min(0.999, abs(x) / rx)
    return -(zb + inflate) * (1.0 - u ** TORSO_POWER) ** (1.0 / TORSO_POWER) - 0.006


def torso_rx(P, y, inflate=0.0):
    return _interp_profile(torso_profile(P), y)[0] + inflate


# -----------------------------------------------------------------------------
# Pezzi del corpo
# -----------------------------------------------------------------------------

def torso(c, P, slot_fn, y0=0.86, y1=1.505, inflate_fn=None, n=20, rings_y=None):
    prof = torso_profile(P)
    ys = rings_y or [0.86, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.29, 1.33, 1.37, 1.41, 1.44, 1.465, 1.49, 1.505]
    ys = [y for y in ys if y0 - 1e-6 <= y <= y1 + 1e-6]
    rings = []
    for y in ys:
        inf = inflate_fn(y) if inflate_fn else 0.0
        rings.append([torso_point(P, y, 2 * math.pi * i / n, inf, prof) for i in range(n)])
    return c.loft(rings, LIGHT, w_torso, slot_fn=lambda k, i, m: slot_fn(m))


def neck(c, P):
    rings = [ring((0, y, -0.01), P["neck"] * (1.04 if y < 1.47 else 1.0), P["neck"] * 0.95, P["neck"] * 1.05, n=12)
             for y in (1.44, 1.5, 1.56, 1.61)]
    c.loft(rings, SKIN, w_torso)


ARM_YS = [1.482, 1.47, 1.45, 1.42, 1.38, 1.32, 1.26, 1.2, 1.155, 1.11, 1.06, 1.0, 0.95, 0.915, 0.895]


def arm_shape(P, y):
    """(rx, rz, dx) del braccio all'altezza y: dx sposta il centro verso l'esterno."""
    d, a, e, f, w = P["delt"], P["arm"], P["elbow"], P["fore"], P["wrist"]
    table = [
        (1.482, d * 0.3, d * 0.3, -0.012),
        (1.47, d * 0.72, d * 0.68, -0.006),
        (1.45, d * 0.97, d * 0.9, 0.0),
        (1.42, d * 1.0, a * 1.06, 0.003),
        (1.38, a * 1.08, a * 1.02, 0.002),
        (1.32, a * 1.02, a * 0.98, 0.0),
        (1.26, a * 0.95, a * 0.94, 0.0),
        (1.2, (a + e) * 0.5, (a + e) * 0.5, 0.0),
        (1.155, e, e * 1.02, 0.0),
        (1.11, f * 1.02, f * 1.05, 0.0),
        (1.06, f, f * 1.02, 0.0),
        (1.0, f * 0.86, f * 0.9, 0.0),
        (0.95, w * 1.08, w * 1.2, 0.0),
        (0.915, w, w * 1.18, 0.0),
        (0.895, w * 0.9, w * 1.08, 0.0),
    ]
    for i in range(len(table) - 1):
        y0, y1 = table[i][0], table[i + 1][0]
        if y1 <= y <= y0:
            t = (y0 - y) / (y0 - y1)
            return tuple(lerp(table[i][k], table[i + 1][k], t) for k in (1, 2, 3))
    return table[0][1:] if y > table[0][0] else table[-1][1:]


def arms(c, P, slot_fn, extra_fn=None, n=12, ys=None, y_end=0.895):
    """extra_fn(y) -> (aggiunta al raggio, spostamento in basso del centro z)."""
    for side in (-1.0, 1.0):
        rings = []
        for y in (ys or ARM_YS):
            if y < y_end - 1e-6:
                continue
            rx, rz, dx = arm_shape(P, y)
            add, dz = extra_fn(y) if extra_fn else (0.0, 0.0)
            cx = side * (P["sh"] + dx)
            rings.append(ring((cx, y, dz), rx + add, rz + add, n=n))
        c.loft(rings, LIGHT, w_arm, slot_fn=lambda k, i, m: slot_fn(m))


def hands(c, P, slot, glove_cuff=0.0):
    hs = P["hand"]
    for side in (-1.0, 1.0):
        x0 = side * P["sh"]
        rings = []
        # dal polso alla punta delle dita, un po' piegate verso il palmo
        for y, tx, tz, curl in ((0.912, 0.017, 0.027, 0.0), (0.885, 0.018, 0.033, 0.0), (0.855, 0.017, 0.036, 0.002),
                                (0.83, 0.015, 0.034, 0.006), (0.805, 0.012, 0.03, 0.011), (0.788, 0.007, 0.018, 0.016)):
            yy = 0.912 - (0.912 - y) * hs
            rings.append(ring((x0 - side * curl * hs, yy, 0.002 + curl * 0.3), tx * hs, tz * hs, n=8, power=2.4))
        c.loft(rings, slot, w_hand)
        # pollice
        t = [ring((x0 - side * 0.006 * hs, 0.892, 0.022 * hs), 0.009 * hs, 0.008 * hs, n=6),
             ring((x0 - side * 0.011 * hs, 0.866, 0.034 * hs), 0.0085 * hs, 0.008 * hs, n=6),
             ring((x0 - side * 0.016 * hs, 0.848, 0.04 * hs), 0.006 * hs, 0.006 * hs, n=6)]
        c.loft(t, slot, w_hand)
        if glove_cuff > 0.0:
            cuff = [ring((x0, y, 0.0), P["wrist"] + glove_cuff + r, P["wrist"] * 1.18 + glove_cuff + r, n=10)
                    for y, r in ((0.97, 0.004), (0.94, 0.002), (0.905, 0.0))]
            c.loft(cuff, slot, w_hand, crease_start=0.6)


LEG_YS = [1.0, 0.95, 0.9, 0.82, 0.72, 0.62, 0.55, 0.49, 0.43, 0.36, 0.29, 0.22, 0.16, 0.11, 0.08]


def leg_shape(P, y):
    t, k, cf, an = P["thigh"], P["knee"], P["calf"], P["ankle"]
    table = [
        (1.0, t * 0.92, t * 0.9, t * 0.95, 0.0),
        (0.95, t * 1.0, t * 0.96, t * 1.05, 0.0),
        (0.9, t * 1.02, t * 0.98, t * 1.04, 0.0),
        (0.82, t * 0.96, t * 0.94, t * 0.96, 0.0),
        (0.72, t * 0.86, t * 0.86, t * 0.84, 0.0),
        (0.62, (t + k) * 0.5 * 0.98, (t + k) * 0.5, (t + k) * 0.5 * 0.9, 0.0),
        (0.55, k * 1.04, k * 1.08, k * 0.96, 0.004),
        (0.49, k, k * 1.04, k * 0.96, 0.004),
        (0.43, cf * 0.94, cf * 0.92, cf * 1.08, 0.0),
        (0.36, cf * 0.96, cf * 0.9, cf * 1.16, -0.004),
        (0.29, cf * 0.82, cf * 0.8, cf * 1.0, -0.004),
        (0.22, an * 1.15, an * 1.1, an * 1.15, 0.0),
        (0.16, an * 1.02, an, an * 1.04, 0.0),
        (0.11, an, an, an, 0.0),
        (0.08, an * 0.95, an * 0.95, an * 0.95, 0.0),
    ]
    for i in range(len(table) - 1):
        y0, y1 = table[i][0], table[i + 1][0]
        if y1 <= y <= y0:
            u = (y0 - y) / (y0 - y1)
            return tuple(lerp(table[i][j], table[i + 1][j], u) for j in (1, 2, 3, 4))
    return table[0][1:] if y > table[0][0] else table[-1][1:]


def legs(c, P, slot_fn, extra_fn=None, y_end=0.08, n=12, ys=None):
    for side in (-1.0, 1.0):
        rings = []
        for y in (ys or LEG_YS):
            if y < y_end - 1e-6:
                continue
            rx, zf, zb, dz = leg_shape(P, y)
            add = extra_fn(y) if extra_fn else 0.0
            # le cosce partono un po' più vicine al centro
            cx = side * (P["leg_x"] - 0.012 * smooth((y - 0.85) / 0.15))
            rings.append(ring((cx, y, dz), rx + add, zf + add, zb + add, n=n))
        c.loft(rings, SECOND, w_leg, slot_fn=lambda k, i, m: slot_fn(m))


def boots(c, P, slot, top=0.3, cuff=0.0, sole_slot=None, toe=1.0, shaft_add=0.006, heel_slot=None):
    fs = P["foot"]
    for side in (-1.0, 1.0):
        x0 = side * P["leg_x"]
        rings = []
        for y in (top + 0.01, top, top - 0.04, 0.2, 0.14, 0.1, 0.075):
            if y > top + 0.011:
                continue
            rx, zf, zb, dz = leg_shape(P, min(y, 0.3))
            add = shaft_add + (cuff if y >= top - 0.005 else 0.0)
            rings.append(ring((x0, y, dz), rx + add, zf + add, zb + add, n=12))
        c.loft(rings, slot, w_foot, crease_start=0.5 if cuff > 0 else 0.0)
        # piede, dal tallone alla punta
        foot = []
        for z, rx, cy, up in ((-0.062, 0.026, 0.036, 0.03), (-0.05, 0.037, 0.045, 0.04), (-0.015, 0.042, 0.052, 0.046),
                              (0.035, 0.044, 0.042, 0.036), (0.085 * toe, 0.043, 0.032, 0.026),
                              (0.122 * toe, 0.035, 0.026, 0.02), (0.14 * toe, 0.017, 0.02, 0.012)):
            foot.append(ring((x0, cy * fs, z * fs + 0.012), rx * fs, up * fs, cy * fs, n=12, power=2.6, axis="z"))
        ss = sole_slot if sole_slot is not None else slot

        def foot_slot(k, i, m):
            return ss if m.y < 0.013 else slot
        c.loft(foot, slot, w_foot, slot_fn=foot_slot)


def band(c, P, y, h, slot, inflate=0.006, n=24, weights=w_torso, crease=0.7):
    """Fascia attorno al busto (cinture, orli)."""
    prof = torso_profile(P)
    rings = [[torso_point(P, yy, 2 * math.pi * i / n, inflate + extra, prof) for i in range(n)]
             for yy, extra in ((y + h * 0.5, 0.0), (y + h * 0.5, 0.004), (y - h * 0.5, 0.004), (y - h * 0.5, 0.0))]
    c.loft(rings, slot, weights, cap_start=False, cap_end=False, crease_start=crease, crease_end=crease)


def box(c, center, size, slot, weights, rot_y=0.0, crease=0.6, round_=0.0):
    """Scatola (borse, fibbie): otto punti, pieghe sugli spigoli."""
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    cs, sn = math.cos(rot_y), math.sin(rot_y)
    pts = []
    for y in (-hy, hy):
        for x, z in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)):
            px = x * cs + z * sn
            pz = -x * sn + z * cs
            pts.append(Vector((center[0] + px, center[1] + y, center[2] + pz)))
    ids = [c.vert(p, weights(p)) for p in pts]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    for f in faces:
        c.face([ids[i] for i in f], slot)
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)):
        c.crease.append((ids[a], ids[b], crease))


def strap(c, path, width, thick, slot, weights, out_fn, crease=0.5):
    """Cinghia lungo un percorso, appoggiata sulla superficie (out_fn dà l'esterno)."""
    rings = []
    for k, p in enumerate(path):
        tan = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]).normalized()
        out = out_fn(p)
        out = (out - tan * out.dot(tan)).normalized()
        side = tan.cross(out).normalized()
        hw = width * 0.5
        rings.append([p + side * hw, p + side * hw + out * thick, p - side * hw + out * thick, p - side * hw])
    c.loft(rings, slot, weights, crease_start=crease, crease_end=crease)


def out_strap(p):
    """Esterno per cinghie e bretelle: sul davanti e dietro in orizzontale, sopra le
    spalle verso l'alto."""
    v = Vector((p.x * 0.5, max(0.0, p.y - 1.42) * 6.0, p.z + 0.006))
    return v.normalized() if v.length > 1e-6 else Vector((0, 1, 0))


def out_from_axis(p):
    v = Vector((p.x, 0.0, p.z + 0.006))
    if v.length < 1e-6:
        return Vector((0, 0, 1))
    return v.normalized()


def front_sheet(c, P, top, bottom, hw_fn, slot, offset=0.008, thick=0.008, rows=10, cols=7, flare=0.08,
                weights=None, slot_fn=None, hang_from=0.95, crease=0.6, z_min_fn=None):
    """Pannello sul davanti (grembiule, tabarro): segue il busto e sotto il bacino scende
    libero davanti alle cosce."""
    grid = []
    hang_z = None
    for k in range(rows):
        y = lerp(top, bottom, k / (rows - 1))
        hw = hw_fn(y)
        row = []
        for i in range(cols):
            u = lerp(-1.0, 1.0, i / (cols - 1))
            x = u * hw
            if y >= hang_from:
                z = torso_front_z(P, x, y) + offset
            else:
                z0 = torso_front_z(P, x, hang_from) + offset
                z = z0 + (hang_from - y) * flare
                if z_min_fn is not None:
                    z = max(z, z_min_fn(x, y))
            row.append(Vector((x, y, z)))
        grid.append(row)
    return c.sheet(grid, slot, weights or (lambda p: w_skirt(p, 0.6)), thick, normal_fn=lambda p: Vector((0, 0, 1)),
                   slot_fn=slot_fn, crease=crease)


# -----------------------------------------------------------------------------
# Vestiti
# -----------------------------------------------------------------------------

def outfit_villager(P):
    """Popolano / lavoratore: camicia chiara con maniche arrotolate, grembiule di
    cuoio con bretelle incrociate dietro, calzoni larghi infilati negli stivali."""
    c = Cage()

    def torso_slot(m):
        return LIGHT if m.y > 1.0 else SECOND

    torso(c, P, torso_slot, inflate_fn=lambda y: 0.008 * smooth(1 - abs(y - 1.06) / 0.06))
    neck(c, P)

    def arm_slot(m):
        return LIGHT if m.y > 1.1 else SKIN

    def arm_extra(y):
        # camicia larga sopra, polsino arrotolato sotto il gomito
        if y > 1.16:
            return 0.005 * smooth((1.47 - y) / 0.08), 0.0
        if y > 1.1:
            return 0.012, 0.0
        return 0.0, 0.0
    arms(c, P, arm_slot, arm_extra, ys=[1.482, 1.47, 1.45, 1.42, 1.38, 1.32, 1.26, 1.2, 1.16, 1.155, 1.12, 1.105, 1.1,
                                       1.06, 1.0, 0.95, 0.915, 0.895])
    hands(c, P, SKIN)

    def leg_extra(y):
        return 0.014 * smooth((y - 0.28) / 0.15) * smooth((1.0 - y) / 0.2) + 0.006

    legs(c, P, lambda m: SECOND, leg_extra, y_end=0.22)
    boots(c, P, BOOT, top=0.31, cuff=0.012, sole_slot=DARK)
    # cintura e borsa
    band(c, P, 1.0, 0.03, LEATHER, inflate=0.012)
    box(c, (0.135, 0.985, 0.04), (0.035, 0.05, 0.05), LEATHER, w_hips, rot_y=0.5)
    box(c, (0.07, 1.0, torso_front_z(P, 0.07, 1.0) + 0.018), (0.028, 0.022, 0.006), GOLD, w_hips)
    # grembiule
    def apron_hw(y):
        if y > 1.18:
            return lerp(0.075, 0.09, smooth((1.36 - y) / 0.18))
        return lerp(0.09, 0.15, smooth((1.18 - y) / 0.2)) + (0.95 - y) * 0.06 * (y < 0.95)

    def zmin(x, y):
        return 0.07 + 0.02
    front_sheet(c, P, 1.37, 0.6, apron_hw, LEATHER, offset=0.016, thick=0.007, rows=12, cols=9, flare=0.06,
                z_min_fn=zmin)
    # bretelle: dalla pettorina sopra le spalle, incrociate dietro fino alla cintura
    for side in (-1.0, 1.0):
        path = []
        pts = [(0.068, 1.36, "f"), (0.08, 1.42, "f"), (0.092, 1.462, "f"), (0.097, 1.487, "t"), (0.094, 1.462, "b"),
               (0.085, 1.42, "b"), (0.05, 1.3, "b"), (-0.03, 1.16, "b"), (-0.09, 1.02, "b")]
        for x, y, where in pts:
            xx = side * x
            if where == "f":
                z = torso_front_z(P, xx, y) + 0.017
            elif where == "b":
                z = torso_back_z(P, xx, y) - 0.009
            else:
                z = -0.008
            path.append(Vector((xx, y, z)))
        strap(c, path, 0.022, 0.005, LEATHER, w_torso, out_strap)
    collar(c, P, LIGHT)
    return c


def collar(c, P, slot, h=0.026, open_front=0.5, lift=0.004):
    """Colletto della camicia attorno alla base del collo, aperto davanti."""
    n = 16
    rows = []
    for y, add in ((1.487, 0.006 + lift), (1.487 + h, 0.009 + lift)):
        row = []
        for i in range(n + 1):
            a = lerp(open_front, 2 * math.pi - open_front, i / n)
            r = P["neck"] + add
            row.append(Vector((math.sin(a) * r * 1.08, y + (0.006 if abs(math.cos(a)) < 0.5 else 0.0) * (y > 1.49),
                               -0.01 + math.cos(a) * r)))
        rows.append(row)
    c.sheet(rows, slot, w_torso, 0.004, normal_fn=lambda p: Vector((p.x, 0, p.z + 0.01)), crease=0.4)


# -----------------------------------------------------------------------------
# Pezzi che avvolgono il corpo: cappotti, tuniche, mantelli, gonne, spallacci
# -----------------------------------------------------------------------------

def hang_point(P, y, a, inflate, hang_y, flare, back=0.0, prof=None):
    """Punto attorno al busto; sotto hang_y il tessuto non segue più il corpo e scende
    allargandosi (flare per unità di altezza), con un po' di spinta all'indietro."""
    if y >= hang_y:
        return torso_point(P, y, a, inflate, prof)
    p = torso_point(P, hang_y, a, inflate, prof)
    d = hang_y - y
    k = 1.0 + flare * d
    q = Vector((p.x * k, y, (p.z + 0.006) * k - 0.006 - back * d))
    return q


def wrap_sheet(c, P, y_top, y_bot, a0, a1, slot, inflate=0.012, hang_y=0.95, flare=0.5, back=0.0, rows=12, cols=14,
               thick=0.008, weights=None, slot_fn=None, fold=0.0, folds=6.0, ao_back=0.72, crease=0.5, top_fn=None):
    """Telo attorno al busto tra gli angoli a0 e a1 (0 = davanti). top_fn(a) può
    abbassare il bordo alto (per esempio sulle spalle di un mantello)."""
    prof = torso_profile(P)
    grid = []
    for k in range(rows):
        t = k / (rows - 1)
        row = []
        for i in range(cols):
            u = i / (cols - 1)
            a = lerp(a0, a1, u)
            yt = top_fn(a) if top_fn else y_top
            y = lerp(yt, y_bot, t)
            p = hang_point(P, y, a, inflate, hang_y, flare, back, prof)
            if fold > 0.0 and y < hang_y:
                out = Vector((p.x, 0.0, p.z + 0.006))
                if out.length > 1e-6:
                    p += out.normalized() * fold * math.sin(u * math.pi * folds * 2.0) * smooth((hang_y - y) / 0.25)
            row.append(p)
        grid.append(row)
    return c.sheet(grid, slot, weights or (lambda p: w_skirt(p, 0.6)), thick, normal_fn=out_from_axis,
                   slot_fn=slot_fn, ao_back=ao_back, crease=crease)


def skirt(c, P, y_top, y_bot, slot, inflate=0.01, flare=0.4, n=20, rows=9, weights=None, slot_fn=None, hem_in=0.006):
    """Gonna o falda chiusa tutto attorno, con l'orlo ripiegato verso l'interno."""
    prof = torso_profile(P)
    rings = []
    ys = [lerp(y_top, y_bot, k / (rows - 1)) for k in range(rows)]
    for y in ys:
        rings.append([hang_point(P, y, 2 * math.pi * i / n, inflate, 0.97, flare, 0.0, prof) for i in range(n)])
    # orlo: un anello poco più su e più stretto chiude il bordo
    last = rings[-1]
    inner = [Vector((p.x * (1 - hem_in * 4), p.y + 0.02, (p.z + 0.006) * (1 - hem_in * 4) - 0.006)) for p in last]
    rings.append(inner)
    return c.loft(rings, slot, weights or (lambda p: w_skirt(p, 0.6)), cap_start=False, cap_end=False,
                  slot_fn=(lambda k, i, m: slot_fn(k, i, m)) if slot_fn else None)


def lathe(c, center, profile, slot, weights, n=12, thick=0.006, squash=(1.0, 1.0), crease=0.6, slot_inner=None):
    """Guscio tornito: profile = [(dy, r)] dall'alto in basso attorno a center; spessore
    verso l'interno, chiuso in cima. Per spallacci, ginocchiere, cupole."""
    sx, sz = squash
    rings = []
    for dy, r in profile:
        rings.append([Vector((center[0] + math.sin(2 * math.pi * i / n) * r * sx, center[1] + dy,
                              center[2] + math.cos(2 * math.pi * i / n) * r * sz)) for i in range(n)])
    inner = []
    for dy, r in reversed(profile):
        rr = max(r - thick, 0.002)
        inner.append([Vector((center[0] + math.sin(2 * math.pi * i / n) * rr * sx, center[1] + dy + thick * 0.5,
                              center[2] + math.cos(2 * math.pi * i / n) * rr * sz)) for i in range(n)])
    idx = c.loft(rings + inner, slot, weights, cap_start=True, cap_end=True)
    k = len(profile) - 1
    for i in range(n):
        c.crease.append((idx[k][i], idx[k][(i + 1) % n], crease))
        c.crease.append((idx[k + 1][i], idx[k + 1][(i + 1) % n], crease))
    return idx


def w_shoulder(p):
    s = side_of(p)
    return _clean({"arm_" + s: 0.72, "spine": 0.28})


def pauldron(c, P, side, slot, lames=3, size=1.0, trim=None):
    """Spallaccio a lamelle sovrapposte, come nel foglio."""
    cx = side * (P["sh"] + 0.006)
    r0 = (P["delt"] + 0.034) * size
    # cupola principale
    lathe(c, (cx, 1.43, 0.0), [(0.085 * size, 0.012), (0.08 * size, r0 * 0.55), (0.066 * size, r0 * 0.86),
                               (0.04 * size, r0 * 1.0), (0.012 * size, r0 * 1.04), (-0.004, r0 * 1.06)],
          slot, w_shoulder, n=14, thick=0.007, squash=(1.0, 0.95))
    for k in range(1, lames):
        y = 1.43 - 0.03 * k * size
        r = r0 * (1.04 + 0.03 * k)
        lathe(c, (cx + side * 0.004 * k, y, 0.0), [(0.03, r * 0.94), (0.012, r), (-0.012, r * 1.02)],
              trim if (trim is not None and k == lames - 1) else slot, w_shoulder, n=14, thick=0.006,
              squash=(1.0, 0.95))


def bell_sleeves(c, P, slot, inner_slot, flare=0.05, y_cuff=0.95, cuff_slot=None, shoulder_add=0.008):
    """Maniche larghe a campana (tuniche, vesti): il bordo è aperto e mostra l'interno scuro."""
    for side in (-1.0, 1.0):
        rings = []
        ys = [1.482, 1.47, 1.45, 1.42, 1.38, 1.32, 1.26, 1.2, 1.14, 1.08, 1.02, y_cuff]
        for y in ys:
            rx, rz, dx = arm_shape(P, y)
            t = smooth((1.25 - y) / (1.25 - y_cuff))
            add = shoulder_add + flare * t
            rings.append(ring((side * (P["sh"] + dx), y - 0.02 * t, 0.012 * t), rx + add, rz + add, n=12))
        # bordo rivoltato e interno
        last = rings[-1]
        ctr = Vector((side * P["sh"], last[0].y, 0.012))
        rim = [ctr + (p - ctr) * 0.86 + Vector((0, 0.004, 0)) for p in last]
        deep = [ctr + (p - ctr) * 0.7 + Vector((0, 0.07, 0)) for p in last]
        n_main = len(rings)

        def sl(k, i, m, n_main=n_main):
            if k >= n_main - 1:
                return inner_slot
            if cuff_slot is not None and k == n_main - 2:
                return cuff_slot
            return slot
        c.loft(rings + [rim, deep], slot, w_arm, cap_start=True, cap_end=True, slot_fn=sl)


def tabard_slots(rows, cols, cross=True, border=GOLD, cloth=LIGHT):
    """Bordo dorato e croce al centro, dipinti sulle facce del telo."""
    def fn(k, i, m):
        if k >= rows - 2 or i == 0 or i >= cols - 2:
            return border
        if cross:
            mid = (cols - 1) // 2
            if (i in (mid - 1, mid) and 2 <= k <= 7) or (k in (4, 5) and mid - 3 <= i <= mid + 2):
                return border
        return cloth
    return fn


def gorget(c, P, slot, h=0.03, lift=0.012):
    rings = [ring((0, y, -0.008), P["neck"] + lift + r, P["neck"] + lift + r, n=16)
             for y, r in ((1.47, 0.012), (1.49, 0.006), (1.49 + h, 0.0), (1.49 + h, -0.004))]
    c.loft(rings, slot, w_torso, cap_start=False, cap_end=False, crease_end=0.6)


# -----------------------------------------------------------------------------
# Guardia / guerriero
# -----------------------------------------------------------------------------

def outfit_guard(P):
    """Guardia del foglio: corazza d'acciaio scuro, spallacci a lamelle, bracciali e
    schinieri, mantello rosso scuro con colletto, tabarro chiaro con bordo e croce d'oro."""
    c = Cage()
    torso(c, P, lambda m: MAIN if m.y > 1.0 else SECOND)
    neck(c, P)
    arms(c, P, lambda m: MAIN, lambda y: (0.006, 0.0))
    hands(c, P, LEATHER, glove_cuff=0.012)
    legs(c, P, lambda m: SECOND, lambda y: 0.008, y_end=0.22)
    boots(c, P, BOOT, top=0.3, sole_slot=DARK)
    # corazza: dal punto vita al collo, con la costola in mezzo e il fondo un po' svasato
    prof = torso_profile(P)
    n = 24
    rings = []
    for y, inf in ((1.03, 0.03), (1.06, 0.024), (1.12, 0.019), (1.2, 0.018), (1.28, 0.018), (1.36, 0.017), (1.42, 0.016),
                   (1.455, 0.014), (1.48, 0.01)):
        row = []
        for i in range(n):
            a = 2 * math.pi * i / n
            p = torso_point(P, y, a, inf, prof)
            if math.cos(a) > 0.0:
                p.z += 0.009 * math.exp(-(a / 0.22) ** 2) * smooth((1.44 - y) / 0.2)
            row.append(p)
        rings.append(row)
    top = rings[-1]
    ctr = Vector((0, 1.49, -0.008))
    rings.append([ctr + (p - ctr) * 0.0 + Vector(((p - ctr).x, 0, (p - ctr).z)).normalized() * (P["neck"] + 0.014)
                  + Vector((0, 0.0, 0)) for p in top])
    c.loft(rings, METAL, w_torso, crease_start=0.7)
    gorget(c, P, METAL_DARK)
    # falda a lamelle sotto la corazza
    for k, (y, h) in enumerate(((1.0, 0.04), (0.965, 0.04))):
        band(c, P, y, h, METAL, inflate=0.032 + 0.006 * k, crease=0.8)
    band(c, P, 1.04, 0.026, LEATHER, inflate=0.036)
    box(c, (0.0, 1.04, torso_front_z(P, 0.0, 1.04) + 0.045), (0.034, 0.03, 0.008), GOLD, w_hips)
    # cosciali che scendono dai fianchi
    for side in (-1.0, 1.0):
        grid = []
        for k in range(5):
            y = lerp(0.95, 0.76, k / 4)
            row = []
            for i in range(5):
                a = side * lerp(0.75, 1.75, i / 4)
                row.append(hang_point(P, y, a, 0.04, 0.95, 0.35, 0.0, prof))
            grid.append(row)
        c.sheet(grid, METAL, lambda p: w_skirt(p, 0.85), 0.006, normal_fn=out_from_axis, crease=0.7)
    # tabarro davanti e dietro
    rows, cols = 12, 9
    front_sheet(c, P, 1.02, 0.56, lambda y: 0.085 + (1.02 - y) * 0.05, LIGHT, offset=0.05, thick=0.006, rows=rows,
                cols=cols, flare=0.05, slot_fn=tabard_slots(rows, cols), hang_from=1.0,
                z_min_fn=lambda x, y: 0.1)
    grid = []
    for k in range(8):
        y = lerp(1.02, 0.62, k / 7)
        row = []
        for i in range(7):
            x = lerp(-0.09, 0.09, i / 6) * (1 + (1.02 - y) * 0.4)
            z = torso_back_z(P, x, min(y, 1.0)) - 0.05 - (1.0 - min(y, 1.0)) * 0.06
            row.append(Vector((x, y, min(z, -0.1))))
        grid.append(row)
    c.sheet(grid, LIGHT, lambda p: w_skirt(p, 0.6), 0.006, normal_fn=lambda p: Vector((0, 0, -1)),
            slot_fn=tabard_slots(8, 7, cross=False))
    # spallacci, bracciali, gomiti, ginocchiere, schinieri
    for side in (-1.0, 1.0):
        pauldron(c, P, side, METAL, lames=3, trim=METAL_DARK)
        x = side * P["sh"]
        lathe(c, (x, 1.08, 0.0), [(0.05, P["elbow"] + 0.012), (0.0, P["fore"] + 0.014), (-0.08, P["fore"] * 0.88 + 0.012),
                                  (-0.15, P["wrist"] + 0.013), (-0.16, P["wrist"] + 0.016)],
              METAL, w_arm, n=12, thick=0.005)
        lathe(c, (x, 1.15, 0.012), [(0.03, 0.01), (0.022, P["elbow"] * 0.8), (0.0, P["elbow"] + 0.016),
                                    (-0.02, P["elbow"] + 0.014)], METAL_DARK, w_arm, n=12, thick=0.005,
              squash=(0.9, 1.1))
        lx = side * P["leg_x"]
        lathe(c, (lx, 0.5, 0.01), [(0.035, 0.012), (0.02, P["knee"] * 0.85), (-0.01, P["knee"] + 0.02),
                                   (-0.035, P["knee"] + 0.016)], METAL_DARK, w_leg, n=12, thick=0.005, squash=(1.0, 1.15))
        lathe(c, (lx, 0.45, 0.0), [(0.0, P["calf"] + 0.014), (-0.08, P["calf"] + 0.018), (-0.18, P["ankle"] + 0.022),
                                   (-0.22, P["ankle"] + 0.024)], METAL, w_leg, n=12, thick=0.005)
    # mantello: dalle spalle fino ai polpacci, con il colletto alto dietro il collo
    wrap_sheet(c, P, 1.475, 0.36, math.pi - 1.25, math.pi + 1.25, ACCENT, inflate=0.04, hang_y=1.34, flare=0.25,
               back=0.12, rows=13, cols=15, thick=0.008, weights=w_cape, fold=0.008, folds=3.5,
               top_fn=lambda a: 1.475 - 0.03 * smooth((abs(abs(a) - math.pi) - 0.6) / 0.65))
    grid = []
    for k in range(3):
        y = lerp(1.475, 1.55, k / 2)
        row = []
        for i in range(9):
            a = math.pi + lerp(-1.25, 1.25, i / 8)
            r = P["neck"] + 0.03 + 0.012 * k
            row.append(Vector((math.sin(a) * r * 1.25, y, -0.012 + math.cos(a) * r)))
        grid.append(row)
    c.sheet(grid, ACCENT, w_torso, 0.007, normal_fn=lambda p: Vector((p.x, 0, p.z + 0.01)))
    return c


# -----------------------------------------------------------------------------
# Mercante
# -----------------------------------------------------------------------------

def outfit_merchant(P):
    """Mercante del foglio: camicia chiara a maniche larghe, gilet lungo scuro aperto con
    bordi d'oro, fusciacca colorata, cintura con borse, calzoni larghi negli stivali."""
    c = Cage()
    torso(c, P, lambda m: LIGHT if m.y > 1.0 else SECOND)
    neck(c, P)

    def sleeve(y):
        if y > 0.99:
            return 0.004 + 0.016 * smooth((1.4 - y) / 0.25) * smooth((y - 0.99) / 0.12), 0.006 * smooth((1.3 - y) / 0.3)
        return 0.006, 0.0
    arms(c, P, lambda m: LIGHT2 if m.y < 0.985 else LIGHT, sleeve,
         ys=[1.482, 1.47, 1.45, 1.42, 1.38, 1.32, 1.26, 1.2, 1.155, 1.11, 1.06, 1.02, 0.995, 0.985, 0.95, 0.915, 0.895])
    hands(c, P, SKIN)
    legs(c, P, lambda m: SECOND, lambda y: 0.02 * smooth((y - 0.3) / 0.2) * smooth((1.0 - y) / 0.25) + 0.008,
         y_end=0.22)
    boots(c, P, BOOT, top=0.32, cuff=0.01, sole_slot=DARK)
    # gilet lungo, aperto davanti, con il bordo d'oro
    cols = 18

    def vest_slot(k, i, m):
        if i in (0, cols - 2) or k >= 12:
            return GOLD
        return MAIN
    wrap_sheet(c, P, 1.455, 0.66, 0.42, 2 * math.pi - 0.42, MAIN, inflate=0.016, hang_y=0.98, flare=0.42, rows=14,
               cols=cols, thick=0.008, slot_fn=vest_slot, fold=0.004, folds=4.0,
               top_fn=lambda a: 1.455 + 0.012 * smooth((abs(abs(a) - math.pi) - 1.6) / -1.0))
    # spalle del gilet (sopra le spalle, verso il collo)
    for side in (-1.0, 1.0):
        grid = []
        for k in range(4):
            row = []
            for i in range(4):
                x = side * lerp(0.075, 0.15, i / 3)
                yy = lerp(1.488, 1.462, i / 3)
                z = lerp(0.05, -0.065, k / 3)
                row.append(Vector((x, yy + 0.01, z)))
            grid.append(row)
        c.sheet(grid, MAIN, w_torso, 0.006, normal_fn=lambda p: Vector((0, 1, 0)))
    # fusciacca e cintura con borse
    band(c, P, 1.04, 0.06, ACCENT, inflate=0.026)
    band(c, P, 0.995, 0.024, LEATHER, inflate=0.03)
    for x, z_off, w, h in ((-0.12, 0.02, 0.04, 0.05), (0.11, 0.02, 0.035, 0.045), (0.15, -0.04, 0.03, 0.04)):
        z = torso_front_z(P, x, 0.98) + 0.04 if z_off > 0 else torso_back_z(P, x, 0.98) + 0.05
        box(c, (x, 0.975, z), (w, h, 0.03), LEATHER, w_hips, rot_y=math.atan2(x, 0.12))
    box(c, (0.0, 0.995, torso_front_z(P, 0.0, 0.995) + 0.036), (0.03, 0.026, 0.008), GOLD, w_hips)
    # coda della fusciacca
    grid = [[Vector((0.07 + 0.012 * i, lerp(1.03, 0.86, k / 4), torso_front_z(P, 0.08, 1.0) + 0.03 + k * 0.004))
             for i in range(3)] for k in range(5)]
    c.sheet(grid, ACCENT, lambda p: w_skirt(p, 0.5), 0.005, normal_fn=lambda p: Vector((0, 0, 1)))
    collar(c, P, LIGHT, h=0.03)
    return c


# -----------------------------------------------------------------------------
# Studioso / sacerdote
# -----------------------------------------------------------------------------

def outfit_scholar(P):
    """Studioso del foglio: veste interna chiara fino ai piedi, veste esterna blu scuro
    aperta davanti con bordi d'oro, maniche a campana, stola bianca con croci d'oro,
    mantellina sulle spalle e cintura con borsa."""
    c = Cage()
    torso(c, P, lambda m: LIGHT)
    neck(c, P)
    bell_sleeves(c, P, MAIN, DARK, flare=0.045, y_cuff=0.95, cuff_slot=GOLD)
    hands(c, P, SKIN)
    legs(c, P, lambda m: SECOND, lambda y: 0.0, y_end=0.22)
    boots(c, P, BOOT, top=0.2, sole_slot=DARK)
    # veste interna fino alle caviglie
    skirt(c, P, 1.0, 0.11, LIGHT, inflate=0.012, flare=0.3, n=22, rows=10, weights=lambda p: w_skirt(p, 0.7))
    # veste esterna aperta davanti
    cols = 20

    def robe_slot(k, i, m):
        if i in (0, cols - 2) or k >= 13:
            return GOLD
        return MAIN
    wrap_sheet(c, P, 1.465, 0.1, 0.5, 2 * math.pi - 0.5, MAIN, inflate=0.022, hang_y=1.02, flare=0.36, rows=15,
               cols=cols, thick=0.008, slot_fn=robe_slot, fold=0.006, folds=5.0, weights=lambda p: w_skirt(p, 0.7))
    # stola bianca con croci d'oro, dal collo in giù
    for side in (-1.0, 1.0):
        grid = []
        rows = 11
        for k in range(rows):
            y = lerp(1.5, 0.6, k / (rows - 1))
            row = []
            for i in range(3):
                x = side * (0.032 + 0.024 * i + 0.012 * smooth((1.45 - y) / 0.2))
                if y > 1.0:
                    z = torso_front_z(P, x, y) + 0.03
                else:
                    z = torso_front_z(P, x, 1.0) + 0.03 + (1.0 - y) * 0.08
                if y > 1.46:
                    z = lerp(z, -0.02, smooth((y - 1.46) / 0.04))
                row.append(Vector((x, y, z)))
            grid.append(row)

        def stole_slot(k, i, m, rows=rows):
            if k >= rows - 3 and k != rows - 2:
                return GOLD
            if k == rows - 5:
                return GOLD
            return LIGHT2
        c.sheet(grid, LIGHT2, lambda p: w_skirt(p, 0.5), 0.005, normal_fn=lambda p: Vector((0, 0, 1)), slot_fn=stole_slot)
    # mantellina sulle spalle
    wrap_sheet(c, P, 1.5, 1.3, -math.pi + 0.0001, math.pi - 0.0001, MAIN, inflate=0.04, hang_y=1.45, flare=0.6,
               rows=8, cols=26, thick=0.007, weights=w_torso,
               top_fn=lambda a: 1.5, slot_fn=lambda k, i, m: GOLD if k >= 6 else MAIN)
    band(c, P, 1.06, 0.03, LEATHER, inflate=0.03)
    box(c, (0.12, 1.0, torso_front_z(P, 0.12, 1.0) + 0.03), (0.05, 0.065, 0.025), LEATHER, w_hips, rot_y=0.5)
    return c


# -----------------------------------------------------------------------------
# Cacciatore (Ranger)
# -----------------------------------------------------------------------------

def outfit_hunter(P):
    """Cacciatore: camicia, farsetto di cuoio, mantellina verde con cappuccio, bracciali,
    calzoni e stivali alti, cinghia della faretra di traverso."""
    c = Cage()
    torso(c, P, lambda m: LIGHT if m.y > 1.0 else SECOND)
    neck(c, P)
    arms(c, P, lambda m: LIGHT, lambda y: (0.004, 0.0))
    hands(c, P, LEATHER, glove_cuff=0.008)
    legs(c, P, lambda m: SECOND, lambda y: 0.006, y_end=0.22)
    boots(c, P, BOOT, top=0.44, cuff=0.012, sole_slot=DARK)
    # farsetto
    prof = torso_profile(P)
    n = 22
    rings = []
    for y, inf in ((0.92, 0.024), (0.98, 0.02), (1.06, 0.016), (1.15, 0.014), (1.25, 0.013), (1.35, 0.012),
                   (1.43, 0.011), (1.465, 0.009)):
        rings.append([torso_point(P, y, 2 * math.pi * i / n, inf, prof) for i in range(n)])
    ctr = Vector((0, 1.49, -0.008))
    rings.append([Vector((p.x, 1.488, p.z)) * 1.0 for p in [ctr + Vector(((q - ctr).x, 0, (q - ctr).z)).normalized() *
                                                           (P["neck"] + 0.016) for q in rings[-1]]])
    c.loft(rings, LEATHER, lambda p: w_skirt(p, 0.4) if p.y < 1.0 else w_torso(p), crease_start=0.6,
           slot_fn=lambda k, i, m: LEATHER if not (i in (0, n - 1) and m.y < 1.4) else DARK)
    band(c, P, 1.0, 0.026, DARK, inflate=0.03)
    # bracciali
    for side in (-1.0, 1.0):
        lathe(c, (side * P["sh"], 1.06, 0.0), [(0.0, P["fore"] + 0.012), (-0.07, P["fore"] * 0.9 + 0.011),
                                               (-0.12, P["wrist"] + 0.013), (-0.13, P["wrist"] + 0.016)],
              LEATHER, w_arm, n=12, thick=0.004)
    # mantellina con cappuccio abbassato
    wrap_sheet(c, P, 1.5, 1.3, -math.pi + 0.0001, math.pi - 0.0001, MAIN, inflate=0.035, hang_y=1.45, flare=0.7,
               rows=5, cols=26, thick=0.007, weights=w_torso, top_fn=lambda a: 1.5)
    hood = []
    for k in range(6):
        t = k / 5
        row = []
        for i in range(9):
            a = math.pi + lerp(-1.1, 1.1, i / 8)
            r = P["neck"] + 0.045 + 0.03 * math.sin(t * math.pi)
            row.append(Vector((math.sin(a) * r * 1.2, 1.5 - 0.05 * t + 0.05 * math.sin(t * math.pi * 0.5),
                               -0.03 + math.cos(a) * r - 0.04 * t)))
        hood.append(row)
    c.sheet(hood, MAIN, w_torso, 0.007, normal_fn=lambda p: Vector((p.x, 0.2, p.z + 0.02)))
    # mantello corto dietro
    wrap_sheet(c, P, 1.44, 0.7, math.pi - 1.0, math.pi + 1.0, MAIN, inflate=0.045, hang_y=1.3, flare=0.2, back=0.1,
               rows=10, cols=11, thick=0.007, weights=w_cape, fold=0.006, folds=3.0)
    # cinghia della faretra di traverso
    path = []
    for t in [k / 10 for k in range(11)]:
        x = lerp(-0.11, 0.13, t)
        y = lerp(1.47, 1.0, t)
        z = torso_front_z(P, x, y, 0.016) + 0.006
        path.append(Vector((x, y, z)))
    strap(c, path, 0.026, 0.006, DARK, w_torso, out_strap)
    return c


OUTFITS = {
    "villager": outfit_villager,
    "guard": outfit_guard,
    "merchant": outfit_merchant,
    "scholar": outfit_scholar,
    "hunter": outfit_hunter,
}
