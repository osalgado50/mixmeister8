#!/usr/bin/env python3
"""Ajusta los pesos del nivel métrico a partir de `mmn leveldiag` sobre una biblioteca.

Entrada: TSV, una línea por pista: nombre  bpm_mm  n  n × (bpm  etiqueta  6 rasgos)
Modelo: puntuación por candidato s = w·f; se elige el máximo. Softmax con L2.
Solo cuentan las pistas donde algún candidato coincide con MixMeister.

Uso: python3 tools/ajustar_nivel.py nivel-rasgos.tsv
"""
import csv
import sys

import numpy as np

NF = 6
NAMES = ["log pulso", "medio tiempo/tiempo", "log coherencia", "x=log2(bpm/120)", "x²", "log pulso graves"]


def load(path):
    tracks = []
    for r in csv.reader(open(path), delimiter="\t"):
        n = int(r[2])
        c = [r[3 + i * (2 + NF): 3 + (i + 1) * (2 + NF)] for i in range(n)]
        bpm = np.array([float(x[0]) for x in c])
        lab = np.array([int(x[1]) for x in c])
        F = np.array([[float(v) for v in x[2:]] for x in c])
        if lab.sum() >= 1:
            tracks.append((r[0], float(r[1]), bpm, int(np.argmax(lab)), F))
    return tracks


def fit(tracks, l2=1.0, iters=3000, lr=0.3):
    allF = np.vstack([t[4] for t in tracks])
    mu = np.abs(allF).mean(0) + 1e-9
    w = np.zeros(NF)
    for _ in range(iters):
        g = l2 * w / len(tracks)
        for _, _, _, y, F in tracks:
            s = (F / mu) @ w
            p = np.exp(s - s.max())
            p /= p.sum()
            g += ((p[:, None] * (F / mu)).sum(0) - (F / mu)[y]) / len(tracks)
        w -= lr * g
    return w / mu


def acc(tracks, w):
    return float(np.mean([np.argmax(F @ w) == y for _, _, _, y, F in tracks]))


def baseline(tracks):
    """Regla actual del motor: log(pulso) − 0,5·(x/0,5)²."""
    return float(np.mean([np.argmax(F[:, 0] - 2 * F[:, 3] ** 2) == y for _, _, _, y, F in tracks]))


def main(path):
    tr = load(path)
    print(f"pistas con candidato correcto: {len(tr)}")
    print(f"regla actual (pulso × prior 120): {baseline(tr):.3f}")
    idx = np.random.default_rng(0).permutation(len(tr))
    for l2 in (0.3, 1, 3, 10):
        a = []
        for k in range(10):
            te = set(idx[k::10].tolist())
            w = fit([t for i, t in enumerate(tr) if i not in te], l2=l2)
            a.append(acc([t for i, t in enumerate(tr) if i in te], w))
        print(f"l2={l2}: validación cruzada {np.mean(a):.3f} ± {np.std(a):.3f}")
    w = fit(tr, l2=1)
    print("pesos: {" + ", ".join(f"{v:.4f}" for v in w) + "}")
    for n, v in zip(NAMES, w):
        print(f"  {n:22s} {v:+.4f}")
    wrong = [(t[0], t[1], t[2][np.argmax(t[4] @ w)]) for t in tr if np.argmax(t[4] @ w) != t[3]]
    print("fallos:", *[f"\n  {n[:40]:40s} mm {b:7.2f} elegido {c:7.2f}" for n, b, c in wrong])


if __name__ == "__main__":
    main(sys.argv[1])
