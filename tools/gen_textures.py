#!/usr/bin/env python3
"""Genera le texture del fogliame usate dalla base e dalle missioni.

Le immagini sono originali, prodotte da questo script (nessun asset esterno):
  godot/assets/textures/leaves.png   atlante 2x2 di ciuffi di foglie (scala di grigi + alfa)
  godot/assets/textures/needles.png  atlante 2x1 di rametti di conifera
  godot/assets/textures/grass.png    atlante 2x1 di ciuffi d'erba
Il colore vero arriva dai vertici della mesh: qui conta solo la luminosità.

Uso: python3 tools/gen_textures.py
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "godot" / "assets" / "textures"
SS = 2  # supersampling


class Canvas:
    """Tela RGBA premoltiplicata in float, disegnata in supersampling."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w * SS, h * SS
        self.rgb = np.zeros((self.h, self.w), np.float32)  # luminanza premoltiplicata
        self.a = np.zeros((self.h, self.w), np.float32)

    def over(self, x0: int, y0: int, lum: np.ndarray, alpha: np.ndarray) -> None:
        h, w = alpha.shape
        x1, y1 = x0 + w, y0 + h
        cx0, cy0 = max(0, x0), max(0, y0)
        cx1, cy1 = min(self.w, x1), min(self.h, y1)
        if cx0 >= cx1 or cy0 >= cy1:
            return
        sa = alpha[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        sl = lum[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]
        dst_a = self.a[cy0:cy1, cx0:cx1]
        dst_l = self.rgb[cy0:cy1, cx0:cx1]
        self.rgb[cy0:cy1, cx0:cx1] = sl * sa + dst_l * (1.0 - sa)
        self.a[cy0:cy1, cx0:cx1] = sa + dst_a * (1.0 - sa)

    def image(self) -> Image.Image:
        a = self.a
        lum = np.where(a > 1e-4, self.rgb / np.maximum(a, 1e-4), 0.0)
        # niente aloni scuri nei mipmap: i pixel trasparenti prendono il colore vicino
        lum = _dilate(lum, a)
        rgba = np.dstack([lum, lum, lum, a])
        img = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
        return img.resize((self.w // SS, self.h // SS), Image.LANCZOS)


def _dilate(lum: np.ndarray, a: np.ndarray, steps: int = 24) -> np.ndarray:
    filled = a > 0.02
    out = lum.copy()
    for _ in range(steps):
        if filled.all():
            break
        acc = np.zeros_like(out)
        cnt = np.zeros_like(out)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(filled, (dy, dx), (0, 1))
            acc += np.where(sh, np.roll(out, (dy, dx), (0, 1)), 0.0)
            cnt += sh
        grow = (~filled) & (cnt > 0)
        out[grow] = acc[grow] / cnt[grow]
        filled = filled | grow
    out[~filled] = out[filled].mean() if filled.any() else 0.5
    return out


def leaf(canvas: Canvas, cx: float, cy: float, angle: float, length: float, width: float, shade: float, rng) -> None:
    """Foglia a mandorla con nervatura centrale; coordinate in pixel finali."""
    cx, cy, length, width = cx * SS, cy * SS, length * SS, width * SS
    r = int(length + 3)
    xs = np.arange(int(cx) - r, int(cx) + r + 1)
    ys = np.arange(int(cy) - r, int(cy) + r + 1)
    X, Y = np.meshgrid(xs + 0.5 - cx, ys + 0.5 - cy)
    d = np.array([math.cos(angle), math.sin(angle)])
    along = (X * d[0] + Y * d[1]) / length  # -1 base, +1 punta
    across = (-X * d[1] + Y * d[0])
    t = np.clip(along, -1.0, 1.0)
    profile = np.clip(1.0 - t * t, 0.0, 1.0) ** 0.62 * (1.0 + 0.18 * t) * np.where(t > 0.55, 1.0 - (t - 0.55) * 0.9, 1.0)
    half = width * 0.5 * profile
    sd = half - np.abs(across)
    inside = (np.abs(along) <= 1.0)
    alpha = np.clip(sd / 1.2 + 0.5, 0.0, 1.0) * inside * np.clip((1.0 - np.abs(along)) * length / 1.5, 0.0, 1.0)
    midrib = np.exp(-(across / (0.9 * SS)) ** 2) * np.clip(1.0 - along, 0.0, 1.0)
    side = np.sign(across)
    lum = shade * (0.78 + 0.22 * (along * 0.5 + 0.5))
    lum = lum * (1.0 - 0.22 * midrib) * (0.86 + 0.14 * side * 0.5 + 0.07)
    edge = np.clip(sd / (2.0 * SS), 0.0, 1.0)
    lum = lum * (0.8 + 0.2 * edge)
    # nervature laterali leggere
    veins = 0.5 + 0.5 * np.sin(along * 14.0 + np.abs(across) / max(width, 1.0) * 10.0)
    lum = lum * (0.95 + 0.05 * veins)
    canvas.over(int(cx) - r, int(cy) - r, lum.astype(np.float32), alpha.astype(np.float32))


def twig(canvas: Canvas, x0, y0, x1, y1, w0, w1, shade) -> None:
    n = 24
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        w = w0 + (w1 - w0) * t
        disc(canvas, x, y, w * 0.5, shade)


def disc(canvas: Canvas, cx, cy, radius, shade) -> None:
    cx, cy, radius = cx * SS, cy * SS, radius * SS
    r = int(radius + 2)
    xs = np.arange(int(cx) - r, int(cx) + r + 1)
    ys = np.arange(int(cy) - r, int(cy) + r + 1)
    X, Y = np.meshgrid(xs + 0.5 - cx, ys + 0.5 - cy)
    dist = np.sqrt(X * X + Y * Y)
    alpha = np.clip(radius - dist + 0.5, 0.0, 1.0)
    lum = np.full_like(alpha, shade)
    canvas.over(int(cx) - r, int(cy) - r, lum.astype(np.float32), alpha.astype(np.float32))


def leaf_cluster(canvas: Canvas, ox: int, oy: int, size: int, seed: int, small: bool) -> None:
    """Ciuffo di foglie attorno a qualche rametto, dentro un riquadro size x size."""
    rng = np.random.default_rng(seed)
    c = size * 0.5
    branches = []
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.62 + rng.uniform(-0.2, 0.2)
        ln = size * rng.uniform(0.3, 0.42)
        bx, by = ox + c, oy + size * 0.88
        ex, ey = ox + c + math.cos(a) * ln, oy + size * 0.88 + math.sin(a) * ln * 1.6
        branches.append((bx, by, ex, ey))
        twig(canvas, bx, by, ex, ey, 3.0, 1.0, 0.28)
    count = 230 if small else 170
    leaves = []
    for _ in range(count):
        bx, by, ex, ey = branches[rng.integers(len(branches))]
        t = rng.uniform(0.25, 1.15)
        px = bx + (ex - bx) * t + rng.normal(0, size * 0.07)
        py = by + (ey - by) * t + rng.normal(0, size * 0.07)
        dx, dy = px - (ox + c), py - (oy + c)
        if dx * dx + dy * dy > (size * 0.46) ** 2:
            continue
        out = math.atan2(py - by, px - bx)
        ang = out + rng.normal(0, 0.55)
        ln = size * (rng.uniform(0.05, 0.075) if small else rng.uniform(0.065, 0.09))
        leaves.append((py, px, ang, ln, ln * rng.uniform(0.85, 1.1), rng.uniform(0.5, 1.0)))
    # prima le foglie in basso (dietro), poi quelle in alto
    leaves.sort(key=lambda v: -v[0])
    for py, px, ang, ln, wd, shade in leaves:
        leaf(canvas, px, py, ang, ln, wd, shade, rng)


def spray_body(canvas: Canvas, ox: int, oy: int, w: int, h: int, shade: float) -> None:
    """Sagoma piena del rametto (dietro gli aghi): da lontano resta compatta."""
    W, H = w * SS, h * SS
    ys, xs = np.mgrid[0:H, 0:W]
    u = (xs + 0.5) / W - 0.5          # -0.5..0.5
    v = 1.0 - (ys + 0.5) / H          # 0 base, 1 punta
    half = np.clip(0.3 * np.sin(np.clip(v * 1.05, 0, 1) * math.pi) * (1.0 - v * 0.45), 0, 0.5)
    sd = (half - np.abs(u)) * W
    alpha = np.clip(sd / 3.0, 0.0, 1.0) * (v > 0.03) * (v < 0.96)
    lum = np.full_like(alpha, shade) * (0.8 + 0.2 * v)
    canvas.over(ox * SS, oy * SS, lum.astype(np.float32), alpha.astype(np.float32))


def needle_spray(canvas: Canvas, ox: int, oy: int, w: int, h: int, seed: int) -> None:
    """Rametto di conifera: asse dal basso in alto, aghi obliqui sui due lati."""
    rng = np.random.default_rng(seed)
    cx = ox + w * 0.5
    spray_body(canvas, ox, oy, w, h, 0.42)
    twig(canvas, cx, oy + h * 0.98, cx, oy + h * 0.06, 4.0, 1.2, 0.3)
    for side in (-1, 1):
        for k in range(7):
            y = oy + h * (0.86 - k * 0.115) + rng.uniform(-4, 4)
            ln = w * (0.4 - k * 0.04)
            ex = cx + side * ln
            ey = y - ln * 0.7
            twig(canvas, cx, y, ex, ey, 2.4, 0.8, 0.3)
            # aghi lungo il rametto laterale
            for j in range(26):
                t = j / 25
                px = cx + (ex - cx) * t
                py = y + (ey - y) * t
                for s2 in (-1, 1):
                    a = math.atan2(ey - y, ex - cx) + s2 * rng.uniform(0.6, 0.95)
                    nl = rng.uniform(12, 17) * (1.0 - 0.3 * t)
                    leaf(canvas, px + math.cos(a) * nl * 0.5, py + math.sin(a) * nl * 0.5, a, nl * 0.5, 3.6, rng.uniform(0.55, 1.0), rng)
    # aghi lungo l'asse principale
    for j in range(40):
        t = j / 39
        py = oy + h * (0.95 - t * 0.88)
        for s2 in (-1, 1):
            a = -math.pi / 2 + s2 * rng.uniform(0.5, 0.9)
            nl = rng.uniform(8, 12)
            leaf(canvas, cx + math.cos(a) * nl * 0.5, py + math.sin(a) * nl * 0.5, a, nl * 0.5, 2.2, rng.uniform(0.6, 1.0), rng)


def grass_card(canvas: Canvas, ox: int, oy: int, w: int, h: int, seed: int) -> None:
    rng = np.random.default_rng(seed)
    blades = []
    for _ in range(34):
        x = ox + w * 0.5 + rng.normal(0, w * 0.16)
        bend = rng.normal(0, 0.35)
        hh = h * rng.uniform(0.45, 0.95)
        blades.append((x, bend, hh, rng.uniform(0.55, 1.0), rng.uniform(3.0, 5.5)))
    blades.sort(key=lambda b: b[2])
    for x, bend, hh, shade, width in blades:
        steps = int(hh * 1.5)
        for i in range(steps):
            t = i / steps
            px = x + bend * hh * t * t
            py = oy + h - hh * t
            wd = width * (1.0 - t) + 0.6
            lum = shade * (0.55 + 0.45 * t)
            disc(canvas, px, py, wd * 0.5, lum)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    leaves = Canvas(512, 512)
    for i, (ox, oy) in enumerate(((0, 0), (256, 0), (0, 256), (256, 256))):
        leaf_cluster(leaves, ox, oy, 256, 100 + i, small=i >= 2)
    leaves.image().save(OUT / "leaves.png")

    needles = Canvas(512, 256)
    needle_spray(needles, 0, 0, 256, 256, 7)
    needle_spray(needles, 256, 0, 256, 256, 8)
    needles.image().save(OUT / "needles.png")

    grass = Canvas(512, 256)
    grass_card(grass, 0, 0, 256, 256, 21)
    grass_card(grass, 256, 0, 256, 256, 22)
    grass.image().save(OUT / "grass.png")
    print("textures ->", OUT)


if __name__ == "__main__":
    main()
