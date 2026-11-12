"""Tratti dei ritratti dipinti che il personaggio 3D deve rispettare (12/11/2026).

Richiesta del proprietario: le immagini e i personaggi 3D devono corrispondere, e ogni
personaggio dell'immagine deve esserci anche nella base. Il catalogo dei ritratti
(godot/assets/portraits/portraits.json) diceva già sesso, colore dei capelli, pelle e alcune
sigle (barba, occhiali, cicatrice...). Questo strumento aggiunge quello che mancava per
costruire un personaggio riconoscibile:

- style       taglio dei capelli, tra quelli del kit 3D (guardati uno per uno sulle immagini)
- head        cosa porta in testa: kerchief (fazzoletto), bandana, hood (cappuccio), veil (velo),
              goggles (occhialoni), hat (cappello), circlet (cerchietto o fermagli d'oro),
              patch (benda sull'occhio), flowers (fiori)
- head_color  colore del copricapo
- hat         tipo di cappello: beret, straw, brim, tricorn, witch, fur, chef, cap
- long_beard  barba lunga (nani, vecchi maghi)
- cloth, cloth2  colori dei vestiti, presi dalla parte bassa dell'immagine

Uso (dalla cartella del repository):
    python tools/character_kit/portrait_traits.py [--sheet /percorso/controllo.png]
Serve: pip install numpy pillow. Riscrive portraits.json aggiungendo solo questi campi.
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "godot/assets/portraits"

STYLES = {"n": "none", "c": "crop", "s": "short", "m": "messy", "w": "wavy", "k": "slicked", "d": "medium",
          "y": "layered", "b": "bob", "t": "tied_back", "u": "bun", "r": "braid", "L": "long_straight", "W": "long_wavy"}
HEADS = {"K": "kerchief", "B": "bandana", "H": "hood", "V": "veil", "G": "goggles", "T": "hat", "C": "circlet", "P": "patch", "F": "flowers"}
COLORS = {"w": "#ece6d8", "r": "#8a2f33", "b": "#6b4a2e", "k": "#2a2530", "p": "#4a3264", "g": "#5a6038", "u": "#2f4a7a", "y": "#c9a85a", "s": "#8a8f98"}
# colore di partenza quando non è scritto
HEAD_DEFAULT = {"goggles": "#6b4a2e", "circlet": "#d9b65a", "patch": "#1f1b20", "flowers": "#f3ecdf", "hat": "#6b4a2e"}

# Un volto per riga: numero, taglio, copricapo[:colore[:tipo di cappello]]. Guardati uno per uno.
TABLE = """
000 m|001 W F|002 m|003 r K:w|004 W|005 W K:r|006 c B:b|007 m G|008 u|009 n
010 m|011 s K:r|012 m|013 W V:w|014 d|015 t|016 s|017 W H:p|018 t C|019 r
020 m|021 u C|022 k|023 L C|024 s|025 W|026 m|027 W F|028 u|029 d P
030 m|031 L|032 s B:k|033 d H:b|034 L|035 d V:w|036 n|037 W F|038 L T:s:witch|039 W
040 r K:b|041 m|042 d|043 b|044 n B:p|045 d K:w|046 L|047 d|048 k|049 m T:b:beret
050 r K:w|051 t|052 u C|053 k|054 W F|055 m T:b:beret|056 r K:w|057 d|058 u|059 s C
060 m P:w|061 W V:p|062 s T:r:beret|063 r|064 t|065 w|066 L|067 b T:k:beret|068 s T:y:straw|069 r K:w
070 W|071 W C|072 s|073 r K:w|074 m|075 W F|076 c|077 r G|078 u C|079 L
080 d V:w|081 s T:w:chef|082 w|083 u|084 d T:k:tricorn|085 m T:b:beret|086 L H:p|087 n|088 L H:k|089 s
090 d H:b|091 L F|092 k|093 r|094 t|095 d G|096 L K:w|097 n|098 L V:w|099 d H:p
100 t|101 u C|102 r K:w|103 k|104 W|105 m|106 d K:b|107 w|108 d K:w|109 m
110 m T:g:beret|111 L F|112 d P|113 m|114 k|115 W T:p:witch|116 s K:w|117 n|118 r H:w|119 w
120 s G|121 L|122 b K:p|123 L K:p|124 W F|125 d V:w|126 s|127 r|128 r K:w|129 L T:b:brim
130 c|131 r K:w|132 w|133 u C|134 c B:k|135 m|136 d K:p|137 u|138 d H:b|139 u C
140 m|141 r|142 w|143 W F|144 W|145 L H:k|146 m|147 u|148 s T:b:fur|149 W
150 m T:g:beret|151 u V:w|152 d|153 d V:w|154 w|155 W|156 s K:w|157 W F|158 d H:w|159 r T:y:straw
160 W K:r|161 s G|162 m|163 u|164 s T:k:tricorn|165 W|166 c|167 s T:b:beret|168 s|169 W C
170 d K:r|171 m|172 s|173 b|174 n|175 m|176 u|177 m T:p:witch|178 n P|179 r K:w
180 s|181 k|182 L|183 r K:w|184 c B:r|185 W|186 d V:w|187 L T:p:witch|188 n|189 m
190 s F|191 t|192 W|193 u|194 s T:y:straw|195 t|196 L F|197 n|198 m|199 W C
200 u|201 d|202 u C:w|203 m T:k:beret|204 d K:w|205 w|206 c B:r|207 W F|208 n|209 W V:p
210 s G|211 L V:w|212 d H:g|213 s|214 r T:k:brim|215 r T:w:fur|216 t|217 W F|218 d T:k:tricorn|219 s
220 L|221 s T:y:straw|222 L C|223 r|224 c B:r|225 n|226 r K:w|227 s|228 L|229 s T:g:beret
230 W P|231 L C:w|232 r|233 m|234 d T:b:beret|235 t|236 s|237 L H:k|238 k|239 L F
240 s T:k:beret|241 n|242 L C|243 L H:p|244 m|245 r K:w|246 m|247 r V:w|248 L B:r|249 d
250 m|251 r K:w|252 s B:r|253 u C|254 s T:r:beret|255 s T:b:beret|256 u|257 L F|258 c B:b|259 m H:b
260 r|261 s K:w|262 c|263 L V:w|264 w|265 u|266 d|267 r T:p:beret|268 s T:k:cap|269 W
270 n|271 m|272 L|273 u|274 n|275 b T:y:straw|276 r|277 m|278 m G|279 u
280 s|281 L H:p|282 d|283 s|284 d H:k|285 u|286 n|287 m|288 L V:k|289 s T:b:beret
290 r K:w|291 m|292 n|293 W K:r|294 k|295 m|296 L V:r|297 d T:b:brim|298 L F|299 s T:w:chef
"""
LONG_BEARD = {"p022", "p038", "p070", "p079", "p109", "p123", "p161", "p187", "p197", "p210", "p274", "p284"}

SKIN_HEX = ["#f8dfc4", "#edc9a7", "#dba887", "#bc8166", "#97634f", "#704438"]


def parse_table():
    out = {}
    for row in TABLE.strip().splitlines():
        for cell in row.split("|"):
            parts = cell.split()
            entry = {"style": STYLES[parts[1]]}
            if len(parts) > 2:
                bits = parts[2].split(":")
                head = HEADS[bits[0]]
                entry["head"] = head
                entry["head_color"] = COLORS[bits[1]] if len(bits) > 1 else HEAD_DEFAULT.get(head, "#6b4a2e")
                if head == "hat": entry["hat"] = bits[2] if len(bits) > 2 else "beret"
            out["p" + parts[0]] = entry
    return out


def to_oklab(rgb):
    c = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708 * c[..., 0] + 0.5363325363 * c[..., 1] + 0.0514459929 * c[..., 2]
    m = 0.2119034982 * c[..., 0] + 0.6806995451 * c[..., 1] + 0.1073969566 * c[..., 2]
    s = 0.0883024619 * c[..., 0] + 0.2817188376 * c[..., 1] + 0.6299787005 * c[..., 2]
    l, m, s = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], axis=-1)


def from_oklab(lab):
    l = (lab[0] + 0.3963377774 * lab[1] + 0.2158037573 * lab[2]) ** 3
    m = (lab[0] - 0.1055613458 * lab[1] - 0.0638541728 * lab[2]) ** 3
    s = (lab[0] - 0.0894841775 * lab[1] - 1.2914855480 * lab[2]) ** 3
    c = np.array([4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                  -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                  -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s])
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def hex_of(lab):
    rgb = np.clip(from_oklab(lab) * 255.0 + 0.5, 0, 255).astype(int)
    return "#%02x%02x%02x" % tuple(rgb)


def lab_of_hex(text):
    v = np.array([int(text[i:i + 2], 16) for i in (1, 3, 5)], dtype=float) / 255.0
    return to_oklab(v)


def kmeans(points, k, rounds=12):
    rng = np.random.default_rng(7)
    centers = points[rng.choice(len(points), k, replace=False)]
    for _ in range(rounds):
        d = ((points[:, None, :] - centers[None, :, :]) ** 2).sum(-1)
        label = d.argmin(1)
        for i in range(k):
            if (label == i).any(): centers[i] = points[label == i].mean(0)
    return centers, np.bincount(label, minlength=k)


def cloth_colors(entry):
    """Colori dei vestiti: la striscia in basso dell'immagine senza pelle, capelli e sfondo."""
    pid = entry["id"]
    img = np.asarray(Image.open(DIR / f"{pid}.jpg").convert("RGB"), dtype=float) / 255.0
    mask = np.asarray(Image.open(DIR / f"{pid}_mask.png").convert("RGB"), dtype=float) / 255.0
    h, w, _ = img.shape
    lab = to_oklab(img)
    # sfondo: bordi laterali a metà altezza, dove di solito non c'è niente
    side = np.concatenate([lab[int(h * 0.15):int(h * 0.5), :int(w * 0.03)].reshape(-1, 3), lab[int(h * 0.15):int(h * 0.5), int(w * 0.97):].reshape(-1, 3)])
    bg = np.median(side, axis=0)
    strip = lab[int(h * 0.76):].reshape(-1, 3)
    hair = mask[int(h * 0.76):, :, 0].reshape(-1) > 0.4
    keep = ~hair
    skin = str(entry.get("skin", "1"))
    if skin.isdigit():
        s = lab_of_hex(SKIN_HEX[min(int(skin), len(SKIN_HEX) - 1)])
        tint = np.hypot(strip[:, 1] - s[1], strip[:, 2] - s[2])
        keep &= ~((tint < 0.035) & (np.abs(strip[:, 0] - s[0]) < 0.24) & (strip[:, 0] > 0.42))
    keep &= np.sqrt(((strip - bg) ** 2).sum(1)) > 0.07
    points = strip[keep]
    if len(points) < 400: points = strip[~hair] if (~hair).sum() > 400 else strip
    centers, counts = kmeans(points[:: max(1, len(points) // 6000)], 3)
    order = np.argsort(-counts)
    main = centers[order[0]]
    second = None
    for i in order[1:]:
        if np.sqrt(((centers[i] - main) ** 2).sum()) > 0.12 and counts[i] > counts.sum() * 0.12:
            second = centers[i]
            break
    return hex_of(main), (hex_of(second) if second is not None else "")


def main():
    manifest = json.loads((DIR / "portraits.json").read_text(encoding="utf-8"))
    table = parse_table()
    missing = [e["id"] for e in manifest["portraits"] if e["id"] not in table]
    if missing: raise SystemExit("Volti senza tratti: " + ", ".join(missing))
    for e in manifest["portraits"]:
        for key in ("style", "head", "head_color", "hat", "long_beard", "cloth", "cloth2"): e.pop(key, None)
        e.update(table[e["id"]])
        if e["id"] in LONG_BEARD: e["long_beard"] = True
        e["cloth"], second = cloth_colors(e)
        if second: e["cloth2"] = second
    manifest["traits"] = "tools/character_kit/portrait_traits.py (taglio, copricapo, barba lunga, colori dei vestiti)"
    lines = ["{", '\t"version": %d,' % manifest["version"], '\t"source": %s,' % json.dumps(manifest["source"], ensure_ascii=False),
             '\t"masks": %s,' % json.dumps(manifest.get("masks", ""), ensure_ascii=False), '\t"traits": %s,' % json.dumps(manifest["traits"], ensure_ascii=False), '\t"portraits": [']
    rows = ["\t\t" + json.dumps(e, ensure_ascii=False) for e in manifest["portraits"]]
    lines.append(",\n".join(rows))
    lines += ["\t]", "}"]
    (DIR / "portraits.json").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("Tratti scritti per %d volti" % len(manifest["portraits"]))
    if "--sheet" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--sheet") + 1])
        cols, tw, th = 10, 196, 120
        entries = manifest["portraits"]
        sheet = Image.new("RGB", (cols * tw, ((len(entries) + cols - 1) // cols) * (th + 26)), (18, 22, 30))
        draw = ImageDraw.Draw(sheet)
        for k, e in enumerate(entries):
            x, y = (k % cols) * tw, (k // cols) * (th + 26)
            sheet.paste(Image.open(DIR / f"{e['id']}.jpg").convert("RGB").resize((tw - 4, th)), (x + 2, y))
            draw.rectangle([x + 2, y + th + 2, x + 60, y + th + 22], fill=e["cloth"])
            if e.get("cloth2"): draw.rectangle([x + 64, y + th + 2, x + 100, y + th + 22], fill=e["cloth2"])
            if e.get("head_color"): draw.rectangle([x + 108, y + th + 2, x + 132, y + th + 22], fill=e["head_color"])
            draw.text((x + 138, y + th + 6), e["id"][1:] + " " + e["style"][:6], fill=(230, 225, 205))
        sheet.save(out)
        print("Foglio di controllo:", out)


if __name__ == "__main__":
    main()
