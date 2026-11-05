"""Modello 3D da un foglio di riferimento "turntable" (viste davanti, lati, dietro).

    python sheet_to_model.py user_models/warrior_sheet.png warrior user_models/warrior.glb

Poi, come per i modelli fatti dall'utente:

    python import_user_model.py user_models/warrior.glb warrior

Come si costruisce:
1. Si separa il personaggio dallo sfondo in ogni vista: lo sfondo del foglio è un
   gradiente in verticale, stimato riga per riga negli spazi vuoti tra le figure.
2. Il volume nasce dalla vista davanti: ogni parte si "gonfia" secondo la sua
   larghezza (braccia e gambe tonde, busto più profondo), poi ogni riga si tara sul
   profilo delle viste di lato (davanti e dietro, lato destro per la metà destra del
   corpo e lato sinistro per l'altra). Così di lato ha lo spessore vero del disegno e
   non è più un bassorilievo.
3. Davanti e dietro diventano due superfici cucite sul bordo. Ogni faccia prende il
   colore dalla vista che la guarda meglio (davanti, dietro o il lato).
4. Nella texture l'alfa segna i capelli (255 = niente capelli, 55 = capelli): il gioco
   li tinge col colore di capelli dell'eroe (painted_model.gdshader).

Le misure delle viste (colonne, centri, righe) dipendono dal foglio: stanno in SHEETS.
Serve il modulo Python di Blender con numpy, scipy e Pillow nello stesso ambiente.
"""
import os
import sys
import tempfile

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SHEETS = {
    "warrior": dict(
        band=(100, 480),                 # righe del foglio con le figure (sopra le etichette)
        gaps=[(2, 10), (378, 392), (605, 625), (738, 772), (885, 900), (1150, 1162), (1527, 1534)],
        front=(5, 380), back=(1160, 1530), right=(625, 730), left=(780, 880),
        cx=192.5, bx=1343.0, rz=680.0, lz=826.0,   # centro del corpo in ogni vista
        top=6, bottom=375,               # righe (nella fascia) della cima della testa e delle suole
        foot_zone=318,                   # da qui in giù l'ombra sul pavimento va tolta
        height=1.78,
        # capelli: riquadri delle teste, volti ed colli da escludere (colonne, righe nella fascia)
        heads=[(160, 228), (1310, 1378), (645, 718), (790, 862)], head_rows=58,
        faces=[(195, 43, 15.5, 13), (701, 45, 12, 12), (805, 45, 12, 12)],
        necks=[(672, 718, 46), (790, 834, 46), (172, 216, 52)],
    ),
}


def background(img, cfg):
    """Sfondo stimato riga per riga negli spazi tra le figure, interpolato in x."""
    H, W, _ = img.shape
    xs = np.array([(a + b) * 0.5 for a, b in cfg["gaps"]])
    bg = np.zeros_like(img)
    for r in range(H):
        meds = np.array([np.median(img[r, a:b], axis=0) for a, b in cfg["gaps"]])
        for ch in range(3):
            bg[r, :, ch] = np.interp(np.arange(W), xs, meds[:, ch])
    return bg


def silhouettes(img, cfg):
    diff = np.sqrt(((img - background(img, cfg)) ** 2).sum(-1))
    lo = diff > 9
    # vicino ai piedi solo i pixel accanto a un contrasto forte: l'ombra a terra è debole
    strong = ndi.binary_dilation(diff > 24, iterations=4)
    fz = cfg["foot_zone"]
    mask = lo.copy()
    mask[fz:] = lo[fz:] & strong[fz:]
    mask = ndi.binary_opening(mask, iterations=1)
    mask = ndi.binary_closing(mask, iterations=2)
    # si chiudono i buchi della stoffa scura, non lo spazio tra le gambe (che arriva ai piedi)
    holes = ndi.binary_fill_holes(mask) & ~mask
    lab, n = ndi.label(holes)
    for i in range(1, n + 1):
        reg = lab == i
        rows = np.nonzero(reg.any(1))[0]
        if reg.sum() < 150 or rows.max() < 300:
            mask |= reg
    lab, n = ndi.label(mask)
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    keep = np.zeros_like(mask)
    for i, s in enumerate(sizes):
        if s > 3000:
            keep |= lab == (i + 1)
    foot = keep[330:].copy()
    keep[330:] = ndi.binary_opening(foot, structure=np.ones((5, 1)))
    return ndi.gaussian_filter(keep.astype(float), 1.2) > 0.5


def hair_mask(img01, M, cfg):
    mx = img01.max(-1)
    mn = img01.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = img01[..., 0], img01[..., 1], img01[..., 2]
    hue = np.degrees(np.arctan2(np.sqrt(3) * (g - b), 2 * r - g - b)) % 360
    hair = ((hue >= 9) & (hue <= 42) & (mx < 0.62) & (sat > 0.18) & (sat < 0.8)) | (mx < 0.26)
    H, W = hair.shape
    yy, xx = np.mgrid[0:H, 0:W]
    out = np.zeros((H, W), bool)
    for a, b2 in cfg["heads"]:
        sub = np.zeros_like(hair)
        sub[:cfg["head_rows"], a:b2] = True
        out |= hair & sub
    for cx, cy, rx, ry in cfg["faces"]:
        out &= ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 >= 1
    for a, b2, r0 in cfg["necks"]:
        out[r0:, a:b2] = False
    out &= M
    out = ndi.binary_opening(out, iterations=1)
    out = ndi.binary_closing(out, iterations=1)
    return out


def build(sheet_path, name, out_path):
    cfg = SHEETS[name]
    y0, y1 = cfg["band"]
    full = Image.open(sheet_path).convert("RGB")
    band = np.asarray(full).astype(float)[y0:y1]
    M = silhouettes(band, cfg)
    hair = hair_mask(band / 255.0, M, cfg)
    BH, BW = M.shape
    # texture: la fascia delle figure, alfa = capelli
    rgba = np.zeros((BH, BW, 4), np.uint8)
    rgba[..., :3] = band.astype(np.uint8)
    rgba[..., 3] = (255 - 200 * ndi.gaussian_filter(hair.astype(float), 0.7)).clip(55, 255).astype(np.uint8)
    # la texture finisce dentro il glb: il file serve solo per l'esportazione
    tex_path = os.path.join(tempfile.mkdtemp(), name + "_texture.png")
    Image.fromarray(rgba, "RGBA").save(tex_path)

    FA, FB = cfg["front"]
    CX, BX, RZ, LZ = cfg["cx"], cfg["bx"], cfg["rz"], cfg["lz"]
    TOP, BOT = cfg["top"], cfg["bottom"]
    S = cfg["height"] / (BOT - TOP + 1)
    mf = M[:, FA:FB].copy()
    # ponte d'ombra tra gli stivali
    legs = ndi.binary_dilation(mf[BOT - 23], iterations=14)
    for r in range(BOT - 19, BH):
        mf[r] &= legs
    mf = ndi.binary_opening(mf, iterations=1)
    H, W = mf.shape
    xs = (np.arange(W) + FA - CX) * S
    ys = (BOT + 0.5 - np.arange(H)) * S

    def extents(a, b, cz, sign):
        zmax = np.full(H, np.nan)
        zmin = np.full(H, np.nan)
        for r in range(H):
            c = np.nonzero(M[r, a:b])[0]
            if len(c) == 0:
                continue
            lo, hi = (c.min() + a - cz) * S * sign, (c.max() + a - cz) * S * sign
            zmax[r], zmin[r] = max(lo, hi), min(lo, hi)
        ok = ~np.isnan(zmax)
        idx = np.arange(H)
        zmax = np.interp(idx, idx[ok], zmax[ok])
        zmin = np.interp(idx, idx[ok], zmin[ok])
        return ndi.median_filter(zmax, 9), ndi.median_filter(zmin, 9)

    rmax, rmin = extents(*cfg["right"], RZ, 1.0)    # lato destro: il davanti è a destra nell'immagine
    lmax, lmin = extents(*cfg["left"], LZ, -1.0)    # lato sinistro: specchiato
    # gonfiaggio: sezione tonda della larghezza locale
    D = ndi.distance_transform_edt(mf)
    R = np.maximum(D, ndi.maximum_filter(D, 31))
    h = np.sqrt(np.clip(D * (2 * R - D), 0, None)) * S
    kf = np.zeros((H, W))
    kb = np.zeros((H, W))
    for r in range(H):
        row = h[r]
        for half, zmx, zmn in ((xs < 0, rmax[r], rmin[r]), (xs >= 0, lmax[r], lmin[r])):
            hm = row[half].max() if half.any() else 0
            if hm <= 1e-6:
                continue
            kf[r, half] = max(zmx, 0.01) / hm
            kb[r, half] = max(-zmn, 0.01) / hm
    kf = ndi.uniform_filter1d(kf, 9, axis=1)
    kb = ndi.uniform_filter1d(kb, 9, axis=1)
    zf = np.where(mf, ndi.gaussian_filter(kf * h, 1.2), 0)
    zb = np.where(mf, ndi.gaussian_filter(-kb * h, 1.2), 0)

    # due campi d'altezza cuciti sul bordo
    idx = -np.ones((H, W), int)
    pix = np.argwhere(mf)
    idx[pix[:, 0], pix[:, 1]] = np.arange(len(pix))
    n = len(pix)
    V = np.zeros((2 * n, 3))
    V[:n, 0] = xs[pix[:, 1]]
    V[:n, 1] = ys[pix[:, 0]]
    V[:n, 2] = zf[pix[:, 0], pix[:, 1]]
    V[n:, :2] = V[:n, :2]
    V[n:, 2] = zb[pix[:, 0], pix[:, 1]]
    quad = mf[:-1, :-1] & mf[1:, :-1] & mf[:-1, 1:] & mf[1:, 1:]
    qr, qc = np.nonzero(quad)
    a = idx[qr, qc]
    b = idx[qr, qc + 1]
    c = idx[qr + 1, qc + 1]
    d = idx[qr + 1, qc]
    faces = [np.stack([a, d, c], 1), np.stack([a, c, b], 1), np.stack([a + n, c + n, d + n], 1), np.stack([a + n, b + n, c + n], 1)]
    kind = [np.zeros(len(a), int)] * 2 + [np.ones(len(a), int)] * 2
    edges = np.concatenate([np.stack([a, b], 1), np.stack([b, c], 1), np.stack([c, d], 1), np.stack([d, a], 1)])
    key = np.sort(edges, 1)
    uniq, counts = np.unique(key, axis=0, return_counts=True)
    rim = uniq[counts == 1]
    faces += [np.stack([rim[:, 0], rim[:, 1], rim[:, 1] + n], 1), np.stack([rim[:, 0], rim[:, 1] + n, rim[:, 0] + n], 1)]
    kind += [np.full(len(rim), 2)] * 2
    F = np.concatenate(faces)
    kind = np.concatenate(kind)

    # vista per ogni faccia: 0 davanti, 1 dietro, 2 lato destro, 3 lato sinistro
    p0, p1, p2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    nrm = np.cross(p1 - p0, p2 - p0)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-12
    cen = (p0 + p1 + p2) / 3
    view = np.where(kind == 0, 0, 1)
    side = (np.abs(nrm[:, 0]) > 0.82) | (kind == 2)
    view = np.where(side, np.where(cen[:, 0] < 0, 2, 3), view)

    def uv_of(p, v):
        r = BOT + 0.5 - p[:, 1] / S
        col = {0: CX + p[:, 0] / S, 1: BX - p[:, 0] / S, 2: RZ + p[:, 2] / S, 3: LZ - p[:, 2] / S}[v]
        return np.stack([col / BW, 1.0 - r / BH], 1), col, r

    UV = np.zeros((len(F), 3, 2))
    for v in range(4):
        sel = view == v
        for k in range(3):
            UV[sel, k] = uv_of(V[F[sel, k]], v)[0]
    # il lato fuori dalla sagoma laterale torna a davanti/dietro
    for v in (2, 3):
        sel = np.nonzero(view == v)[0]
        bad = np.zeros(len(sel), bool)
        for k in range(3):
            _, cc, rr = uv_of(V[F[sel, k]], v)
            ci = np.clip(cc.astype(int), 0, BW - 1)
            ri = np.clip(rr.astype(int), 0, BH - 1)
            bad |= ~M[ri, ci]
        fix = sel[bad]
        back = cen[fix, 2] < 0
        for k in range(3):
            uf = uv_of(V[F[fix, k]], 0)[0]
            ub = uv_of(V[F[fix, k]], 1)[0]
            UV[fix, k] = np.where(back[:, None], ub, uf)
    print("punti %d, facce %d, viste %s" % (len(V), len(F), np.bincount(view)))
    write_glb(V, F, UV, tex_path, name, out_path)


def write_glb(V, F, UV, tex_path, name, out_path):
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new(name)
    # coordinate del gioco (x, y su, z avanti) → Blender (x, -z, y)
    me.from_pydata([(float(x), float(-z), float(y)) for x, y, z in V], [], [tuple(int(i) for i in f) for f in F])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    flat = UV.reshape(-1, 2)
    loops = np.array([li for poly in me.polygons for li in poly.loop_indices])
    uv = np.zeros((len(me.loops), 2))
    uv[loops] = flat
    uvl.data.foreach_set("uv", uv.ravel())
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    img = bpy.data.images.load(os.path.abspath(tex_path))
    mat = bpy.data.materials.new(name + "_projection")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(out_path), export_format="GLB", use_selection=True, export_yup=True,
                              export_texcoords=True, export_normals=False, export_materials="EXPORT", export_image_format="AUTO")
    print("  %s" % out_path)


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3])
