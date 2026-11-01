"""Capigliature del kit, come gli "Hair Assets" del foglio: ogni taglio è una calotta
sul cranio più tante ciocche a punta con volume (sezione a lente che si assottiglia
fino alla punta), disposte a strati. Le ciocche seguono la testa, poi cadono libere;
quelle sulla fronte si fermano sopra le sopracciglia, così non coprono mai gli occhi.
Coordinate: rispetto al perno della testa. Posto 0 = capelli, 1 = strato interno.
"""
import math
import random
from mathutils import Vector
from kit_core import Cage, smooth, lerp
from kit_head import head_point, head_normal, CENTER

HAIR, HAIR_IN = 0, 1
W_HEAD = lambda p: {"head": 1.0}


def wrap(a):
    while a > math.pi:
        a -= 2 * math.pi
    while a < -math.pi:
        a += 2 * math.pi
    return a


def hairline(a, front=0.212, side=0.165, nape=0.04, sideburn=0.118):
    """Attaccatura dei capelli: fronte, tempie, basetta davanti all'orecchio, sopra
    l'orecchio, nuca."""
    x = abs(wrap(a))
    keys = [(0.0, front), (0.7, front - 0.012), (1.22, 0.172), (1.42, sideburn), (1.58, side), (1.9, side - 0.004),
            (2.3, 0.1), (math.pi, nape)]
    for i in range(len(keys) - 1):
        a0, y0 = keys[i]
        a1, y1 = keys[i + 1]
        if a0 <= x <= a1:
            t = (x - a0) / (a1 - a0)
            return lerp(y0, y1, smooth(t) * 0.6 + t * 0.4)
    return nape


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2 +
                        (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3) for i in range(len(p1)))


def body_push(p, margin=0.02):
    """Tiene le ciocche lunghe fuori da collo, spalle e busto (coordinate della testa)."""
    from kit_body import torso_profile, _interp_profile, AVERAGE, TORSO_POWER
    y_rig = p.y + 1.51
    q = Vector(p)
    if y_rig < 1.5:
        rx, zf, zb = _interp_profile(torso_profile(AVERAGE), y_rig)
        rx += margin + 0.012
        zf += margin + 0.012
        zb += margin + 0.012
        zc = -0.006
        dz = q.z - zc
        d = zf if dz >= 0 else zb
        u = (abs(q.x) / rx) ** TORSO_POWER + (abs(dz) / d) ** TORSO_POWER
        if u < 1.0:
            k = u ** (-1.0 / TORSO_POWER)
            q.x *= k
            q.z = zc + dz * k
    # spalle (attaccatura delle braccia)
    for sx in (-1.0, 1.0):
        c = Vector((sx * 0.2, 1.43 - 1.51, 0.0))
        v = q - c
        r = 0.074 + margin
        if v.length < r:
            if v.length < 1e-6:
                v = Vector((sx, 0.3, 0))
            q = c + v.normalized() * r
    return q


def head_push(p, min_lift):
    """Se il punto è dentro la testa (più un margine), lo spinge fuori in orizzontale."""
    if p.y > 0.27 or p.y < 0.015:
        return p
    a = math.atan2(p.x, p.z - CENTER.z)
    s = head_point(p.y, a, lift=min_lift)
    r_p = math.hypot(p.x, p.z - CENTER.z)
    r_s = math.hypot(s.x, s.z - CENTER.z)
    if r_p < r_s:
        k = r_s / max(r_p, 1e-6)
        return Vector((p.x * k, p.y, CENTER.z + (p.z - CENTER.z) * k))
    return p


# Volume e larghezza delle ciocche rispetto ai numeri dei tagli: i capelli degli
# anime sono molto più gonfi del cranio.
VOL = 1.5
WIDTH = 1.3
THICK = 1.25


class Hair:
    def __init__(self, seed=1):
        self.c = Cage()
        self.rng = random.Random(seed)

    def j(self, amount):
        return self.rng.uniform(-amount, amount)

    # --- calotta -----------------------------------------------------------------------

    def scalp(self, line=None, lift=0.0055, top_lift=None):
        line = line or (lambda a: hairline(a))
        top_lift = lift if top_lift is None else top_lift
        n = 36
        rows = 10
        rings = []
        for k in range(rows):
            t = k / (rows - 1)
            row = []
            for i in range(n):
                a = 2 * math.pi * i / n
                y = lerp(line(a), 0.27, t ** 0.85)
                row.append(head_point(y, a, lift=lerp(lift, top_lift, t) * VOL))
            rings.append(row)
        self.c.loft(rings, HAIR_IN, W_HEAD, cap_start=False, cap_end=True,
                    ao_fn=lambda p: 0.85)

    # --- ciocche --------------------------------------------------------------------------

    def path(self, ctrl, steps=10, free=None):
        """ctrl: [(y, a, lift)] sulla testa, interpolati; free: prolungamento libero
        dict(length, down, out, fwd, flick, curl, steps)."""
        pts = []
        cc = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
        segs = len(ctrl) - 1
        for s in range(segs):
            for k in range(steps):
                t = k / steps
                y, a, lift = catmull(cc[s], cc[s + 1], cc[s + 2], cc[s + 3], t)
                pts.append(head_point(y, a, lift=lift * VOL))
        y, a, lift = ctrl[-1]
        pts.append(head_point(y, a, lift=lift * VOL))
        if free:
            L = free.get("length", 0.05)
            n = free.get("steps", 8)
            d = (pts[-1] - pts[-2]).normalized()
            P = pts[-1]
            out = Vector((P.x, 0.0, P.z - CENTER.z))
            out = out.normalized() if out.length > 1e-6 else Vector((0, 0, -1))
            target = (Vector((0, -1, 0)) * free.get("down", 1.0) + out * free.get("out", 0.0) +
                      Vector((0, 0, 1)) * free.get("fwd", 0.0) + d * free.get("keep", 0.6))
            target.normalize()
            side = Vector((0, 1, 0)).cross(out).normalized()
            for k in range(1, n + 1):
                u = k / n
                d = (d * (1.0 - free.get("turn", 0.35)) + target * free.get("turn", 0.35)).normalized()
                P = P + d * (L / n)
                q = P + out * free.get("flick", 0.0) * u ** 3 + side * free.get("curl", 0.0) * u ** 2
                q += Vector((0, 0, 0))
                q = head_push(q, free.get("min_lift", 0.008))
                q = body_push(q, free.get("body_margin", 0.018))
                wave = free.get("wave", 0.0)
                if wave:
                    q += side * math.sin(u * math.pi * free.get("waves", 2.0)) * wave
                pts.append(q)
        return pts

    def lock(self, pts, width, thick=0.42, slot=HAIR, prof=None, n=6, flat_out=None):
        """Ciocca a punta lungo `pts`. width = mezza larghezza alla radice."""
        c = self.c
        m = len(pts)
        width *= WIDTH
        thick *= THICK
        rings = []
        ids = []
        length = sum((pts[i + 1] - pts[i]).length for i in range(m - 1))
        acc = 0.0
        for k in range(m - 1):
            if k > 0:
                acc += (pts[k] - pts[k - 1]).length
            t = acc / max(length, 1e-6)
            f = prof(t) if prof else (1.0 - t) ** 0.85 * (1.0 + 0.7 * t)
            w = width * f
            p = pts[k]
            tan = (pts[k + 1] - pts[max(k - 1, 0)]).normalized()
            out = head_normal(p) if flat_out is None else flat_out(p)
            out = out - tan * out.dot(tan)
            if out.length < 1e-6:
                out = Vector((0, 0, 1))
            out.normalize()
            side = tan.cross(out).normalized()
            th = max(w * thick, 0.0012)
            row = []
            for i in range(n):
                a = 2 * math.pi * i / n
                # lente: bordi sottili ai lati, dorso pieno sopra, più piatta sotto
                o = math.sin(a)
                o = o if o > 0 else o * 0.55
                q = p + side * math.cos(a) * w + out * o * th
                row.append(c.vert(q, {"head": 1.0}, lerp(0.8, 1.0, smooth(t / 0.45))))
            ids.append(row)
        tip = c.vert(pts[-1], {"head": 1.0}, 1.0)
        c.face(list(reversed(ids[0])), slot)
        for k in range(len(ids) - 1):
            for i in range(n):
                j = (i + 1) % n
                c.face((ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]), slot)
        for i in range(n):
            c.face((ids[-1][i], ids[-1][(i + 1) % n], tip), slot)

    # --- gruppi di ciocche --------------------------------------------------------------

    def bangs(self, count=5, span=0.62, tip_y=0.176, center_tip=None, root_y=0.252, mid_y=0.214, sweep=0.12,
              vol=0.017, width=0.026, jitter=0.012, root_span=0.35, part=None, flick=0.0, tip_a_scale=1.0):
        """Frangia: dalle radici in cima scendono sulla fronte. Punte sopra le sopracciglia;
        la ciocca centrale può scendere di più (tra gli occhi)."""
        for i in range(count):
            u = lerp(-1.0, 1.0, i / max(count - 1, 1)) if count > 1 else 0.0
            a_mid = u * span
            a_root = u * root_span
            sw = sweep
            if part is not None:
                sw = sweep * (1.0 if a_mid >= part else -1.0)
            a_tip = (a_mid + sw) * tip_a_scale
            ty = tip_y + abs(u) * 0.006 + self.j(jitter * 0.4)
            if center_tip is not None and abs(u) < 0.25:
                ty = center_tip
            # niente punte davanti agli occhi
            x_tip = math.sin(a_tip) * 0.1
            if 0.012 < abs(x_tip) < 0.07:
                ty = max(ty, 0.166)
            ctrl = [(root_y, a_root, 0.002), (lerp(root_y, mid_y, 0.55), lerp(a_root, a_mid, 0.6), vol),
                    (mid_y, a_mid + sw * 0.3, vol * 0.85), (ty, a_tip, 0.006 + flick)]
            self.lock(self.path(ctrl, steps=6), width * (1.0 + self.j(0.15)), thick=0.45)

    def layer(self, a0, a1, count, root_y, tip_y, vol, width, swirl=0.0, free=None, tip_lift=0.008,
              jitter=0.01, a_jit=0.04, mid_t=0.45, root_lift=0.002, thick=0.42):
        """Strato di ciocche tra gli angoli a0 e a1 (giro della testa), dalla cima a tip_y."""
        for i in range(count):
            u = (i + 0.5) / count
            a = lerp(a0, a1, u) + self.j(a_jit)
            ty = tip_y + self.j(jitter)
            my = lerp(root_y, ty, mid_t)
            ctrl = [(root_y, a * 0.55 if abs(wrap(a)) < 2.0 else a, root_lift), (my, a + swirl * 0.5, vol),
                    (ty, a + swirl, tip_lift)]
            fr = None
            if free:
                fr = dict(free)
                fr["length"] = free.get("length", 0.05) * (1.0 + self.j(0.2))
            self.lock(self.path(ctrl, steps=6, free=fr), width * (1.0 + self.j(0.18)), thick=thick)

    def crown(self, count, vol, width, length=0.06, spread=0.5):
        """Ciuffi corti in cima per dare volume e qualche punta."""
        for i in range(count):
            a = 2 * math.pi * i / count + self.j(0.3)
            y0 = 0.262
            y1 = 0.262 - length * (0.7 + self.j(0.25))
            ctrl = [(0.268, a, 0.002), (lerp(y0, y1, 0.5), a + self.j(spread * 0.3), vol), (y1, a + self.j(spread * 0.3), vol * 0.7)]
            self.lock(self.path(ctrl, steps=5), width, thick=0.5)


# -----------------------------------------------------------------------------
# I tagli del foglio
# -----------------------------------------------------------------------------

def style_short(h, spiky=True):
    """Corti (Guardia D, Studioso D): ciuffi corti con punte all'insù, nuca scoperta."""
    h.scalp()
    h.crown(9, 0.02, 0.03, length=0.05)
    h.bangs(count=5, span=0.6, tip_y=0.19, sweep=0.14, vol=0.018, width=0.027)
    for side in (-1, 1):
        h.layer(side * 0.85, side * 1.85, 4, 0.255, 0.148, 0.018, 0.027, swirl=side * 0.12,
                free=dict(length=0.018, down=0.2, out=1.0, flick=0.006, turn=0.5) if spiky else None)
    h.layer(1.85, 4.43, 8, 0.258, 0.075, 0.017, 0.03,
            free=dict(length=0.02, down=0.3, out=1.0, flick=0.006, turn=0.5) if spiky else None)


def style_crop(h):
    """Rasati corti (Popolano B): aderenti alla testa, frangia cortissima."""
    h.scalp(lift=0.006, top_lift=0.008)
    h.crown(7, 0.01, 0.026, length=0.04)
    h.bangs(count=5, span=0.55, tip_y=0.205, sweep=0.08, vol=0.01, width=0.022, jitter=0.004)
    for side in (-1, 1):
        h.layer(side * 0.85, side * 1.85, 4, 0.255, 0.16, 0.01, 0.024, swirl=side * 0.08, tip_lift=0.006)
    h.layer(1.85, 4.43, 8, 0.258, 0.08, 0.01, 0.026, tip_lift=0.006)


def style_wavy(h, long_=False):
    """Mossi (Guardia A, Mercante C): tanto volume, ciocche a S, orecchie coperte a metà."""
    h.scalp(lift=0.007)
    h.crown(8, 0.026, 0.032, length=0.06)
    h.bangs(count=6, span=0.7, tip_y=0.172, center_tip=0.15, sweep=0.18, vol=0.026, width=0.028, jitter=0.01)
    for side in (-1, 1):
        h.layer(side * 0.8, side * 1.9, 5, 0.255, 0.12, 0.026, 0.03, swirl=side * 0.2,
                free=dict(length=0.045, down=1.0, out=0.55, flick=0.008, turn=0.4, curl=side * 0.006))
    h.layer(1.9, 4.38, 9, 0.258, 0.07, 0.025, 0.032,
            free=dict(length=0.06 if not long_ else 0.12, down=1.0, out=0.45, flick=0.01, turn=0.4, wave=0.006))


def style_medium(h):
    """Media lunghezza (Guardia B): riga in mezzo, ciocche laterali fino alla mascella."""
    h.scalp(lift=0.006)
    h.crown(6, 0.02, 0.03, length=0.05)
    h.bangs(count=6, span=0.72, tip_y=0.168, center_tip=0.155, sweep=0.22, vol=0.02, width=0.027, part=0.0)
    for side in (-1, 1):
        h.layer(side * 0.75, side * 1.6, 3, 0.25, 0.16, 0.022, 0.03, swirl=side * 0.25,
                free=dict(length=0.1, down=1.0, out=0.25, fwd=0.15, flick=0.006, turn=0.5))
        h.layer(side * 1.6, side * 2.2, 3, 0.255, 0.13, 0.02, 0.03,
                free=dict(length=0.08, down=1.0, out=0.3, flick=0.006, turn=0.5))
    h.layer(2.2, 4.08, 7, 0.258, 0.07, 0.02, 0.032, free=dict(length=0.07, down=1.0, out=0.3, flick=0.008, turn=0.45))


def ponytail(h, at_y=0.13, length=0.16, count=6, width=0.022, band=True, lift=0.03):
    tie = head_point(at_y, math.pi, lift=lift)
    for i in range(count):
        a = 2 * math.pi * i / count
        off = Vector((math.cos(a) * 0.012, math.sin(a) * 0.01, 0.0))
        pts = [tie + off * 0.6 + Vector((0, 0.004, 0.012))]
        P = tie + off
        d = Vector((off.x * 3, -1.0, -0.35)).normalized()
        n = 9
        for k in range(1, n + 1):
            u = k / n
            d = (d + Vector((0, -0.12, 0.02))).normalized()
            P = P + d * (length * (1.0 + h.j(0.15)) / n)
            q = body_push(P + off * (1.0 + u * 1.5), 0.02)
            pts.append(q)
        h.lock(pts, width * (1 + h.j(0.15)), thick=0.6, prof=lambda t: (1.0 - t) ** 0.7 * (0.9 + 0.9 * t))
    if band:
        from kit_core import ring
        rings = [ring((tie.x, tie.y + dy, tie.z - 0.004), 0.013 + r, 0.011 + r, n=10, axis="z")
                 for dy, r in ((0.002, 0.0), (0.0, 0.002), (-0.006, 0.002), (-0.008, 0.0))]
        # anello attorno alla coda (asse z)
        rings = []
        for dz, r in ((0.006, 0.0), (0.003, 0.003), (-0.006, 0.003), (-0.009, 0.0)):
            rings.append([tie + Vector((math.cos(2 * math.pi * i / 10) * (0.014 + r), math.sin(2 * math.pi * i / 10) * (0.012 + r), dz - 0.004))
                          for i in range(10)])
        h.c.loft(rings, 2, W_HEAD)


def style_tied_back(h):
    """Legati dietro (Guardia C): tirati indietro in una coda corta, due ciocche libere sul viso."""
    h.scalp(lift=0.005)
    h.bangs(count=4, span=0.5, tip_y=0.186, sweep=0.2, vol=0.014, width=0.024, part=0.0)
    for side in (-1, 1):
        # tutto scorre verso il nodo dietro
        for i in range(5):
            a = side * (0.5 + i * 0.32)
            ctrl = [(0.25, a * 0.6, 0.002), (0.21, a + side * 0.2, 0.014), (0.16, side * (math.pi - 0.35 - i * 0.04), 0.012),
                    (0.135, side * (math.pi - 0.05), 0.01)]
            h.lock(h.path(ctrl, steps=5), 0.03, thick=0.4)
        # ciocca libera davanti all'orecchio
        ctrl = [(0.245, side * 0.42, 0.002), (0.205, side * 0.92, 0.016), (0.15, side * 1.22, 0.012)]
        h.lock(h.path(ctrl, steps=5, free=dict(length=0.08, down=1.0, out=0.3, fwd=0.2, flick=0.004, turn=0.5)), 0.018,
               thick=0.4)
    h.layer(2.1, 4.18, 6, 0.255, 0.12, 0.012, 0.03, tip_lift=0.01)
    ponytail(h, at_y=0.135, length=0.13, count=6, width=0.022)


def style_slicked(h):
    """Tirati indietro (Mercante A): volume sulla fronte, tutto pettinato verso la nuca."""
    h.scalp(lift=0.006)
    for i in range(9):
        a = lerp(-1.05, 1.05, i / 8)
        ctrl = [(0.208, a, 0.002), (0.245, a * 0.9, 0.024), (0.262, a * 0.75 + math.pi * 0.0, 0.022),
                (0.23, (math.pi - 0.6 + abs(a) * 0.5) * (1 if a >= 0 else -1) if abs(a) > 0.1 else math.pi, 0.016)]
        h.lock(h.path(ctrl, steps=6, free=dict(length=0.03, down=0.6, out=0.8, flick=0.006, turn=0.5)), 0.03,
               thick=0.45)
    for side in (-1, 1):
        h.layer(side * 1.15, side * 2.0, 4, 0.24, 0.15, 0.014, 0.028, swirl=side * 0.35, tip_lift=0.008)
    h.layer(2.0, 4.28, 7, 0.255, 0.075, 0.016, 0.032, free=dict(length=0.025, down=0.4, out=1.0, flick=0.006, turn=0.5))
    # una ciocca ribelle sulla fronte
    ctrl = [(0.236, 0.25, 0.006), (0.215, 0.28, 0.02), (0.185, 0.36, 0.01)]
    h.lock(h.path(ctrl, steps=5), 0.016, thick=0.45)


def style_layered(h):
    """Scalati (Mercante B, Studioso B): soffici, a strati di lunghezze diverse."""
    h.scalp(lift=0.007)
    h.crown(9, 0.026, 0.03, length=0.055)
    h.bangs(count=7, span=0.72, tip_y=0.17, center_tip=0.152, sweep=0.16, vol=0.024, width=0.025, jitter=0.012)
    for side in (-1, 1):
        h.layer(side * 0.8, side * 1.7, 4, 0.255, 0.14, 0.026, 0.028, swirl=side * 0.18,
                free=dict(length=0.03, down=0.8, out=0.8, flick=0.01, turn=0.5))
        h.layer(side * 1.0, side * 2.0, 4, 0.245, 0.11, 0.018, 0.03, swirl=side * 0.12,
                free=dict(length=0.07, down=1.0, out=0.45, flick=0.008, turn=0.45))
    h.layer(2.0, 4.28, 8, 0.258, 0.09, 0.026, 0.03, free=dict(length=0.04, down=0.7, out=0.8, flick=0.01, turn=0.5))
    h.layer(2.3, 3.98, 6, 0.25, 0.07, 0.016, 0.03, free=dict(length=0.07, down=1.0, out=0.35, flick=0.008, turn=0.45))


def style_messy(h):
    """Spettinati (Mercante D, Popolano A): ciocche in tutte le direzioni, punte all'insù."""
    h.scalp(lift=0.007)
    h.crown(11, 0.028, 0.03, length=0.06, spread=1.2)
    h.bangs(count=6, span=0.68, tip_y=0.175, center_tip=0.158, sweep=0.15, vol=0.024, width=0.027, jitter=0.02)
    for side in (-1, 1):
        h.layer(side * 0.8, side * 1.9, 5, 0.255, 0.13, 0.026, 0.03, swirl=side * 0.25, a_jit=0.12,
                free=dict(length=0.035, down=0.1, out=1.0, flick=0.014, turn=0.6))
    h.layer(1.9, 4.38, 9, 0.258, 0.075, 0.026, 0.032, a_jit=0.1,
            free=dict(length=0.04, down=0.3, out=1.0, flick=0.014, turn=0.6))


def smooth_path(pts, margin=0.02, iters=3, keep=4):
    """Liscia un percorso dopo le spinte fuori dal corpo (niente zig-zag)."""
    pts = [Vector(p) for p in pts]
    for _ in range(iters):
        out = pts[:keep]
        for i in range(keep, len(pts) - 1):
            out.append((pts[i - 1] + pts[i] * 2 + pts[i + 1]) * 0.25)
        out.append(pts[-1])
        pts = [out[i] if i < keep else body_push(head_push(out[i], 0.008), margin) for i in range(len(out))]
    return pts


def drape(h, ctrl, tail, width, wave=0.0, steps=5, margin=0.022, thick=0.42):
    """Ciocca lunga: prima sulla testa (ctrl), poi giù per i punti `tail` (coordinate
    della testa), interpolati e tenuti fuori da spalle e busto."""
    head_pts = h.path(ctrl, steps=steps)
    anchor = [head_pts[-2], head_pts[-1]] + [Vector(t) for t in tail]
    cc = [anchor[0]] + anchor + [anchor[-1]]
    pts = list(head_pts)
    for sgi in range(1, len(anchor) - 1):
        for k in range(1, 5):
            t = k / 4
            q = Vector(catmull(cc[sgi], cc[sgi + 1], cc[sgi + 2], cc[sgi + 3], t))
            pts.append(q)
    if wave:
        side = Vector((1, 0, 0))
        n = len(pts)
        for i in range(len(head_pts), n):
            u = (i - len(head_pts)) / max(1, n - len(head_pts))
            pts[i] = pts[i] + side * math.sin(u * math.pi * 3.0) * wave * smooth(u * 3)
    pts = smooth_path([body_push(head_push(p, 0.008), margin) if i >= len(head_pts) else p for i, p in enumerate(pts)],
                      margin, keep=len(head_pts))
    h.lock(pts, width, thick=thick, prof=lambda t: (1.0 - t) ** 0.6 * (1.0 + 0.3 * t))


def style_long_straight(h, wave=0.0):
    """Lunghi e lisci (Studioso A): riga in mezzo, ciocche davanti alle spalle, dietro fino a metà schiena."""
    h.scalp(lift=0.006)
    h.crown(5, 0.016, 0.03, length=0.04)
    for side in (-1, 1):
        # frangia aperta in mezzo, verso le tempie
        for i in range(3):
            a_tip = side * (0.62 + i * 0.16)
            ctrl = [(0.262, side * 0.05, 0.002), (0.235, side * (0.25 + i * 0.12), 0.02),
                    (0.2, side * (0.48 + i * 0.15), 0.016), (0.168 - i * 0.012, a_tip, 0.008)]
            h.lock(h.path(ctrl, steps=6), 0.026, thick=0.42)
        # ciocche lunghe davanti, sopra le spalle e sul petto
        drape(h, [(0.25, side * 0.55, 0.002), (0.2, side * 1.0, 0.02), (0.13, side * 1.27, 0.014)],
              [(side * 0.108, 0.05, 0.03), (side * 0.125, -0.04, 0.07), (side * 0.13, -0.14, 0.096),
               (side * 0.124, -0.23, 0.106)], 0.03, wave)
        drape(h, [(0.25, side * 0.85, 0.002), (0.19, side * 1.22, 0.02), (0.12, side * 1.42, 0.014)],
              [(side * 0.122, 0.04, 0.0), (side * 0.152, -0.05, 0.03), (side * 0.158, -0.15, 0.055),
               (side * 0.15, -0.22, 0.064)], 0.03, wave)
        # ai lati, dietro le spalle
        for i in range(3):
            a = side * (1.75 + i * 0.3)
            p = head_point(0.08, a, lift=0.02)
            drape(h, [(0.26, a * 0.5, 0.002), (0.17, a, 0.022), (0.08, a, 0.018)],
                  [(p.x * 1.04, -0.02, min(p.z, -0.06) - 0.02), (p.x * 1.02, -0.13, min(p.z, -0.07) - 0.05),
                   (p.x * 0.98, -0.25, min(p.z, -0.07) - 0.06), (p.x * 0.95, -0.33, min(p.z, -0.07) - 0.055)],
                  0.034, wave)
    # dietro: tende di ciocche fino a metà schiena
    for i in range(7):
        a = math.pi + lerp(-0.85, 0.85, i / 6)
        p = head_point(0.08, a, lift=0.02)
        drape(h, [(0.265, wrap(a) * 0.4, 0.002), (0.18, a, 0.024), (0.08, a, 0.018)],
              [(p.x * 1.1, -0.02, p.z - 0.02), (p.x * 1.1, -0.14, p.z - 0.04), (p.x * 1.05, -0.26, p.z - 0.045),
               (p.x * 1.0, -0.36, p.z - 0.04)], 0.036, wave)


def braid(h, start, length=0.26, seg=0.026, width=0.02):
    """Treccia: nodi alternati a destra e a sinistra che scendono dietro la schiena."""
    P = start
    d = Vector((0, -1, -0.25)).normalized()
    count = int(length / seg)
    for k in range(count):
        side = 1.0 if k % 2 == 0 else -1.0
        w = width * (1.0 - 0.35 * k / count)
        a = P + Vector((side * w * 0.5, 0, 0))
        b = a + d * seg * 1.25 + Vector((-side * w * 0.9, 0, -0.004))
        mid = (a + b) * 0.5 + Vector((side * w * 0.3, 0, -0.006))
        pts = [body_push(a, 0.02), body_push(mid, 0.02), body_push(b, 0.02)]
        h.lock(pts, w * 0.9, thick=0.75, prof=lambda t: math.sin(math.pi * (0.25 + t * 0.75)) * 1.1)
        P = P + d * seg
        d = (d + Vector((0, -0.1, 0.03))).normalized()
    # codino finale
    pts = [P + Vector((0, 0.01, 0)), P + Vector((0.004, -0.02, -0.004)), P + Vector((0.006, -0.045, -0.002))]
    h.lock([body_push(p, 0.02) for p in pts], width * 0.7, thick=0.5)
    return P


def style_braid(h):
    """Treccia (Studioso C): frangia leggera, tutto raccolto in una treccia dietro."""
    h.scalp(lift=0.006)
    h.bangs(count=5, span=0.6, tip_y=0.178, sweep=0.18, vol=0.016, width=0.025, part=0.0)
    for side in (-1, 1):
        for i in range(5):
            a = side * (0.6 + i * 0.3)
            ctrl = [(0.25, a * 0.6, 0.002), (0.2, a + side * 0.25, 0.014), (0.13, side * (math.pi - 0.3), 0.012),
                    (0.09, side * (math.pi - 0.06), 0.012)]
            h.lock(h.path(ctrl, steps=5), 0.03, thick=0.4)
        ctrl = [(0.24, side * 0.5, 0.002), (0.2, side * 1.0, 0.014), (0.14, side * 1.28, 0.01)]
        h.lock(h.path(ctrl, steps=5, free=dict(length=0.05, down=1.0, out=0.3, fwd=0.2, turn=0.5)), 0.016)
    h.layer(2.2, 4.08, 6, 0.255, 0.09, 0.012, 0.03, tip_lift=0.01)
    braid(h, head_point(0.085, math.pi, lift=0.016), length=0.28)


def style_bun(h):
    """Crocchia (Popolano D): capelli raccolti in alto dietro, qualche ciocca libera."""
    h.scalp(lift=0.006)
    h.bangs(count=5, span=0.6, tip_y=0.18, sweep=0.16, vol=0.016, width=0.025)
    knot = head_point(0.235, math.pi, lift=0.03)
    for side in (-1, 1):
        for i in range(4):
            a = side * (0.7 + i * 0.4)
            ctrl = [(0.245, a * 0.7, 0.002), (0.2, a, 0.014), (0.2, side * (math.pi - 0.4), 0.016),
                    (0.225, side * (math.pi - 0.08), 0.02)]
            h.lock(h.path(ctrl, steps=5), 0.03, thick=0.4)
        ctrl = [(0.24, side * 0.6, 0.002), (0.2, side * 1.1, 0.014), (0.15, side * 1.3, 0.01)]
        h.lock(h.path(ctrl, steps=5, free=dict(length=0.03, down=1.0, out=0.4, turn=0.5, flick=0.006)), 0.016)
    for i in range(6):
        a = math.pi + (i - 2.5) * 0.35
        ctrl = [(0.07, a, 0.004), (0.15, a * 0.98 + math.pi * 0.02, 0.014), (0.22, math.pi + (a - math.pi) * 0.3, 0.02)]
        h.lock(h.path(ctrl, steps=5), 0.03, thick=0.4)
    # la crocchia: ciocche arrotolate attorno al nodo
    for i in range(9):
        a = 2 * math.pi * i / 9
        r = 0.026
        pts = []
        for k in range(8):
            t = k / 7
            ang = a + t * 2.2
            pts.append(knot + Vector((math.cos(ang) * r * (1 - 0.3 * t), math.sin(ang) * r * (1 - 0.3 * t),
                                      -0.012 - 0.01 * math.sin(t * math.pi))))
        h.lock(pts, 0.018, thick=0.8, prof=lambda t: math.sin(math.pi * (0.15 + 0.85 * t)) ** 0.6)


def style_long_wavy(h):
    style_long_straight(h, wave=0.008)


def style_bob(h):
    """Caschetto: frangia dritta, punte fino al mento che girano verso il collo."""
    h.scalp(lift=0.007)
    h.crown(6, 0.02, 0.03, length=0.05)
    h.bangs(count=7, span=0.72, tip_y=0.172, sweep=0.04, vol=0.022, width=0.024, jitter=0.004)
    for side in (-1, 1):
        h.layer(side * 0.85, side * 1.95, 5, 0.255, 0.12, 0.024, 0.03, swirl=side * 0.05,
                free=dict(length=0.065, down=1.0, out=0.2, turn=0.5, curl=-side * 0.004, flick=-0.006))
    h.layer(1.95, 4.33, 8, 0.258, 0.08, 0.024, 0.032,
            free=dict(length=0.05, down=1.0, out=0.15, turn=0.5, flick=-0.008))


STYLES = {
    "short": style_short, "crop": style_crop, "wavy": style_wavy, "medium": style_medium,
    "tied_back": style_tied_back, "slicked": style_slicked, "layered": style_layered, "messy": style_messy,
    "long_straight": style_long_straight, "braid": style_braid, "bun": style_bun, "long_wavy": style_long_wavy,
    "bob": style_bob,
}


def build_hair(name, seed=7):
    h = Hair(seed + sum(ord(ch) for ch in name))
    STYLES[name](h)
    return h.c
