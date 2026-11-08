"""Maschere dei ritratti dipinti: capelli (rosso), iridi (verde) e distanza dal centro
dell'iride (blu: 1 al centro, 0 al bordo; serve allo shader per pupilla e bordo dell'iride),
più la luminosità dipinta.

Servono allo shader di hero_portrait.gd per dare ai ritratti i colori di capelli e occhi
del generatore personaggi. Questa versione (8/11/2026) rifà le iridi e pulisce i capelli:

- iridi: cerchio dell'iride trovato da MediaPipe Face Landmarker (sui volti dipinti i punti
  dell'iride sono affidabili, la vecchia "ricerca del disco migliore" li spostava sulle
  palpebre), tagliato dall'apertura dell'occhio e da ciocche che lo coprono;
- capelli: la maschera vecchia (rosso) senza i pezzi di pelle dentro e intorno al viso
  (colore vicino a quello della pelle del viso, lontano da quello dei capelli) e senza buchini;
- catalogo: luminosità di capelli e iridi in OKLab (L del 5°, 50° e 97° percentile) e la
  tinta media dei capelli dipinti, come li usa lo shader.

Uso (dalla cartella del repository):
    python tools/character_kit/portrait_masks.py MODELLO.task [p001,p002,...] [--occhi]
--occhi rifà solo iridi e pupille e lascia i capelli come sono. Volti e occhi scartati o corretti
a mano: BAD_EYES, EYE_FIX e BAD_HAIR qui sotto.
MODELLO.task è face_landmarker.task di MediaPipe:
https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task
Serve: pip install mediapipe numpy scipy pillow
Le iridi si rifanno sempre da capo. I capelli partono dalla maschera che c'è: rilanciarlo su
maschere già pulite toglie ancora un po' di capelli (1–5% dei pixel), quindi per rifare tutto
conviene ripartire dalle maschere di prima di questa versione (commit 106589f).
"""
import json, sys
from pathlib import Path
import numpy as np
import scipy.ndimage as ndi
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "godot/assets/portraits"

# Volti controllati a occhio l'8/11/2026 (iridi ingrandite 3 volte, poi alla grandezza delle carte):
# iride trovata fuori posto o solo in parte, occhi chiusi, socchiusi dal ridere o coperti.
# Tengono gli occhi dipinti.
BAD_EYES = set("""
p003 p005 p015 p027 p031 p041 p045 p050 p051 p054 p069 p078 p080 p082 p088 p099 p110 p113 p116 p120
p129 p140 p143 p156 p157 p165 p171 p180 p190 p198 p200 p204 p206 p208 p215 p223 p224 p244 p247 p249 p257 p290 p296
p062 p068 p138 p159 p254 p261
p002 p025 p042 p122 p240 p251
""".split())

# Correzioni a mano degli occhi, controllate ingrandendo l'8/11/2026 ("sx"/"dx": l'occhio a sinistra
# o a destra nell'immagine).
# "via": l'occhio lontano di un volto di tre quarti, mezzo nascosto da palpebra o naso, oppure
# sfocato. Colorato diventava una striscia sulla palpebra: resta dipinto (si vede appena) e si
# colora solo l'altro.
# (dx, dy): MediaPipe metteva l'iride accanto a quella dipinta; iride e apertura dell'occhio si
# spostano di tanti pixel del ritratto.
_VIA_DX = """
p000 p083 p086 p090 p094 p096 p119 p121 p131 p133 p135 p139 p142 p145 p150 p151 p154 p155 p158
p162 p164 p167 p169 p173 p175 p182 p193 p195 p196 p202 p205 p212 p213 p218 p219 p222 p226 p233
p246 p250 p253 p264 p275 p281 p285 p288 p295 p297 p298
""".split()
_VIA_SX = "p057 p172 p277".split()
EYE_FIX = {**{p: {"dx": "via"} for p in _VIA_DX}, **{p: {"sx": "via"} for p in _VIA_SX},
           "p293": {"sx": (-8.5, 3.5)}}

# Volti con capelli ricolorabili controllati a occhio l'8/11/2026 (ognuno ricolorato nel colore
# più lontano che HAIR_COMPAT permette): la maschera dei capelli prende anche bende, colletti,
# pellicce, occhiali, orecchini grandi o pelle, oppure lascia metà capelli col colore dipinto
# o fa puntini. Tengono i capelli dipinti (hair_ok falso): il gioco li dà solo a eroi con
# capelli di quel colore.
BAD_HAIR = set("""
p029 p034 p047 p059 p060 p063 p066 p082 p107 p113 p121 p124 p127 p143 p146 p147
p151 p172 p176 p200 p209 p217 p230 p233 p260 p264 p266 p271 p272 p273 p282 p295
""".split())

LEYE = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
REYE = [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398]
OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377,
        152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109]
BROWS = [[70, 63, 105, 66, 107, 55, 65, 52, 53, 46], [300, 293, 334, 296, 336, 285, 295, 282, 283, 276]]
LIPS = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185]

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
               [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
               [0.0259040371, 0.7827717662, -0.8086757660]])


def oklab(rgb: np.ndarray) -> np.ndarray:
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    return np.cbrt(lin @ M1.T) @ M2.T


def polygon(points, size, grow=0.0) -> np.ndarray:
    w, h = size
    img = Image.new("L", (w, h), 0)
    pts = [tuple(p) for p in points]
    ImageDraw.Draw(img).polygon(pts, fill=255)
    m = np.asarray(img) > 127
    if grow > 0: m = ndi.binary_dilation(m, iterations=int(round(grow)))
    return m


def kmeans(x: np.ndarray, k: int, it: int = 12) -> np.ndarray:
    if len(x) <= k: return x.copy()
    rng = np.random.default_rng(0)
    if len(x) > 4000: x = x[rng.choice(len(x), 4000, replace=False)]
    c = x[rng.choice(len(x), k, replace=False)]
    for _ in range(it):
        lab = ((x[:, None, :] - c[None]) ** 2).sum(-1).argmin(1)
        c = np.array([x[lab == j].mean(0) if (lab == j).any() else c[j] for j in range(k)])
    return c


def mindist(lab: np.ndarray, cent: np.ndarray) -> np.ndarray:
    d = np.full(lab.shape[:2], 9.0)
    for c in cent: d = np.minimum(d, np.sqrt(((lab - c) ** 2).sum(-1)))
    return d


def landmarker(model: str):
    import mediapipe as mp
    from mediapipe.tasks import python as mpt
    from mediapipe.tasks.python import vision
    opts = vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=model), num_faces=1,
                                        min_face_detection_confidence=0.15, min_face_presence_confidence=0.15)
    det = vision.FaceLandmarker.create_from_options(opts)

    def run(img: Image.Image):
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(np.asarray(img))))
        if not res.face_landmarks: return None
        w, h = img.size
        return np.array([[q.x * w, q.y * h] for q in res.face_landmarks[0]])
    run.close = det.close
    return run


def clean_hair(lab, hair, lm, size):
    """Toglie dalla maschera dei capelli i pezzi di pelle del viso e chiude i buchini."""
    w, h = size
    face = polygon(lm[OVAL], size)
    holes = np.zeros_like(face)
    for eye in (LEYE, REYE): holes |= polygon(lm[eye], size, 3)
    for brow in BROWS: holes |= polygon(lm[brow], size, 2)
    holes |= polygon(lm[LIPS], size, 2)
    L = lab[..., 0]
    skin_px = lab[face & ~holes & (hair < 0.2) & (L > 0.55)]
    core = hair > 0.8
    hair_px = lab[core & ~ndi.binary_dilation(face, iterations=4)]
    if len(skin_px) < 80 or len(hair_px) < 150: return hair
    # capelli chiari (biondi, bianchi, argento) hanno il colore della pelle: lì la pulizia
    # toglierebbe le ciocche sulla fronte, quindi si fa solo con capelli scuri o colorati
    if np.linalg.norm(np.median(skin_px, 0) - np.median(hair_px, 0)) < 0.12 or np.median(hair_px[:, 0]) > 0.62:
        return hair
    skin_c = kmeans(skin_px, 3)
    hair_c = kmeans(hair_px, 6)
    d_s = mindist(lab, skin_c)
    d_h = mindist(lab, hair_c)
    near = ndi.binary_dilation(face, iterations=10)
    skinlike = near & (d_s < 0.045) & (d_s < 0.6 * d_h)
    hard = (hair > 0.5) & ~skinlike
    # isole piccole: via; buchini (non pelle) chiusi
    lab_i, n = ndi.label(hard)
    if n:
        sizes = ndi.sum(hard, lab_i, range(1, n + 1))
        keep = np.zeros(n + 1, bool)
        keep[1:] = sizes >= 30
        hard = keep[lab_i]
    filled = ndi.binary_fill_holes(hard) & ~hard
    lab_h, nh = ndi.label(filled)
    if nh:
        sizes = ndi.sum(filled, lab_h, range(1, nh + 1))
        sk = ndi.mean(skinlike, lab_h, range(1, nh + 1))
        fill = np.zeros(nh + 1, bool)
        fill[1:] = (sizes < 40) & (sk < 0.3)
        hard |= fill[lab_h]
    soft = ndi.gaussian_filter(hard.astype(np.float32), 0.7)
    # il bordo morbido di prima resta dove non c'era pelle
    return np.where(skinlike, 0.0, np.maximum(np.minimum(soft * 1.2, 1.0), np.where(hard, hair, 0.0)))


def irises(lab, hair, lm, size, fix=None):
    """Iride di ogni occhio: il cerchio dei punti dell'iride di MediaPipe (un po' più largo),
    dentro l'apertura dell'occhio e sotto le ciocche che lo coprono. "dark" dice quanto
    l'iride è più scura della pelle intorno: palpebre chiuse e cerchi finiti sulla pelle no.
    fix: correzioni a mano di EYE_FIX per questo volto."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    L = lab[..., 0]
    out = np.zeros((h, w), np.float32)
    radial = np.zeros((h, w), np.float32)
    eyes = []
    for c0, contour in ((468, LEYE), (473, REYE)):
        other = 473 if c0 == 468 else 468
        side = "sx" if lm[c0][0] < lm[other][0] else "dx"
        f = (fix or {}).get(side)
        shift = np.array(f, float) if isinstance(f, tuple) else np.zeros(2)
        c = lm[c0] + shift
        pts = lm[contour] + shift
        r = max(float(np.mean([np.linalg.norm(lm[c0 + k] - lm[c0]) for k in range(1, 5)])), 3.0) * 1.08
        opening = polygon(pts, size, 1)
        width = np.linalg.norm(pts[0] - pts[8])
        height = np.linalg.norm(pts[12] - pts[4])
        dist = np.sqrt((xx - c[0]) ** 2 + (yy - c[1]) ** 2)
        disc = np.clip((1.0 - dist / r) / 0.18, 0, 1) * opening
        cover = 1 - np.clip((hair - 0.3) / 0.4, 0, 1)
        visible = disc * cover
        inside = (disc > 0.5) & (cover > 0.5)
        ring = (dist > 1.6 * r) & (dist < 3.4 * r) & (hair < 0.3) & (L > 0.45) & ~polygon(pts, size, 2)
        dark = float(np.median(L[ring]) - np.median(L[inside])) if inside.sum() >= 6 and ring.sum() >= 20 else 0.0
        eyes.append(dict(r=r, open=height / max(width, 1e-3), area=float((disc > 0.5).sum()),
                         seen=float(inside.sum()), dark=dark, side=side, via=f == "via"))
        if f == "via": continue
        radial = np.maximum(radial, np.clip(1.0 - dist / r, 0, 1) * (visible > 0.02))
        out = np.maximum(out, visible)
    return ndi.gaussian_filter(out, 0.5), radial, eyes


def stats(L, w, thr):
    v = L[w > thr]
    if v.size < 12: v = L[w > 0.3]
    if v.size == 0: return 0.1, 0.35, 0.6
    return [round(float(np.percentile(v, q)), 3) for q in (5, 50, 97)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    eyes_only = "--occhi" in sys.argv
    model = args[0]
    only = set(args[1].split(",")) if len(args) > 1 else None
    detect = landmarker(model)
    manifest = json.loads((DIR / "portraits.json").read_text())
    counts = {"eyes": 0, "hair": 0}
    for e in manifest["portraits"]:
        pid = e["id"]
        if only is not None and pid not in only: continue
        img = Image.open(DIR / f"{pid}.jpg").convert("RGB")
        a = np.asarray(img).astype(np.float64) / 255.0
        old = np.asarray(Image.open(DIR / f"{pid}_mask.png").convert("RGB")).astype(np.float32) / 255.0
        hair = old[..., 0]
        lab = oklab(a)
        lm = detect(img)
        beast = "K" in e.get("flags", "")
        eyes = np.zeros(hair.shape, np.float32)
        radial = np.zeros(hair.shape, np.float32)
        e["has_eyes"] = False
        if lm is not None:
            if hair.max() > 0.5 and not eyes_only: hair = clean_hair(lab, hair, lm, img.size)
            if not beast:
                eyes, radial, info = irises(lab, hair, lm, img.size, EYE_FIX.get(pid))
                usable = [i for i in info if not i["via"] and i["open"] >= 0.15 and i["seen"] >= 14 and i["dark"] >= 0.07]
                hidden = [i for i in info if i["via"] or i["seen"] < 0.35 * max(i["area"], 1)]
                # un occhio solo colorato sembrerebbe eterocromia: l'altro dev'essere coperto
                # (o lontano e mezzo nascosto, EYE_FIX "via")
                if usable and len(usable) + len(hidden) >= 2 and pid not in BAD_EYES:
                    e["has_eyes"] = True
                else:
                    eyes[:] = 0
                    radial[:] = 0
        if pid in BAD_HAIR: e["hair_ok"] = False
        L = lab[..., 0]
        if e["has_eyes"]:
            e["eye_lo"], e["eye_mid"], e["eye_hi"] = stats(L, eyes, 0.6)
            counts["eyes"] += 1
        if e.get("has_hair"):
            e["hair_lo"], e["hair_mid"], e["hair_hi"] = stats(L, hair, 0.8)
            sel = hair > 0.8
            e["hair_a"] = round(float(np.median(lab[..., 1][sel])), 4) if sel.any() else 0.0
            e["hair_b"] = round(float(np.median(lab[..., 2][sel])), 4) if sel.any() else 0.0
            counts["hair"] += 1
        m = np.zeros(hair.shape + (3,), np.uint8)
        m[..., 0] = np.clip(hair * 255 + 0.5, 0, 255).astype(np.uint8)
        m[..., 1] = np.clip(eyes * 255 + 0.5, 0, 255).astype(np.uint8)
        m[..., 2] = np.clip(radial * 255 + 0.5, 0, 255).astype(np.uint8)
        Image.fromarray(m).save(DIR / f"{pid}_mask.png", optimize=True)
    detect.close()
    manifest["masks"] = "tools/character_kit/portrait_masks.py (luminosità in OKLab L)"
    (DIR / "portraits.json").write_text(json.dumps(manifest, indent=0, separators=(",", ":")))
    print(counts)


if __name__ == "__main__":
    main()
