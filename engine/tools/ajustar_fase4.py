#!/usr/bin/env python3
"""Ajusta los pesos de quarter_score() a partir de `mmn phasediag4` sobre una biblioteca.

Entrada: TSV de `mmn phasediag4`, 4 líneas por pista (j = 0..3, cuartos de tiempo desde el
tiempo de MixMeister): nombre  j  nuestra_rejilla_aquí(0/1)  bombo  48 × flujo  48 × caída.
Rasgos por posición: los 8 de phase_features (flujo y caída medios en 4 grupos de bandas:
< 90 Hz, 90-250, 250-2k, > 2k) y el bombo. Modelo: softmax sobre las 4 posiciones con pesos
compartidos; la regla del motor solo cambia la posición elegida si otra gana por `margen`.

Uso: python3 tools/ajustar_fase4.py diag-phasediag4.tsv
"""
import csv
import sys
from collections import OrderedDict

import numpy as np

NB = 48
EDGES = [90, 250, 2000]


def load(path):
    rows = OrderedDict()
    for r in csv.reader(open(path), delimiter="\t"):
        if len(r) != 4 + 2 * NB:
            continue
        rows.setdefault(r[0], {})[int(r[1])] = (float(r[2]), float(r[3]), np.array(r[4:4 + NB], float),
                                                np.array(r[4 + NB:], float))
    names = [n for n, v in rows.items() if len(v) == 4]
    mine = np.array([[rows[n][j][0] for j in range(4)] for n in names])
    kick = np.array([[rows[n][j][1] for j in range(4)] for n in names])
    fl = np.array([[rows[n][j][2] for j in range(4)] for n in names])
    dc = np.array([[rows[n][j][3] for j in range(4)] for n in names])
    c = 30 * (8000 / 30) ** ((np.arange(NB) + .5) / NB)
    g = np.digitize(c, EDGES)
    X = np.stack([fl[:, :, g == k].mean(2) for k in range(4)] + [dc[:, :, g == k].mean(2) for k in range(4)] + [kick], 2)
    return names, mine, X


def fit(X, l2=1.0, iters=1500, lr=0.5):
    Xc = X - X.mean(1, keepdims=True)
    mu = Xc.reshape(-1, X.shape[2]).std(0) + 1e-9
    Z = Xc / mu
    n = len(X)
    w = np.zeros(X.shape[2])
    for _ in range(iters):
        s = Z @ w
        s -= s.max(1, keepdims=True)
        p = np.exp(s)
        p /= p.sum(1, keepdims=True)
        g = (p[:, :, None] * Z).sum(1) - Z[:, 0]   # la posición 0 es siempre la de MixMeister
        w -= lr * (g.mean(0) + l2 * w / n)
    return w / mu


def rule(X, w, cur, margin):
    s = X @ w
    b = s.argmax(1)
    i = np.arange(len(b))
    return np.where(s[i, b] - s[i, cur] > margin, b, cur)


def main(path):
    names, mine, X = load(path)
    N = len(names)
    cur = mine.argmax(1)
    print(f"pistas: {N}")
    print(f"rejilla actual en la posición de MixMeister: {np.mean(cur == 0):.4f}")
    idx = np.random.default_rng(0).permutation(N)
    for margin in (0, 0.25, 0.5, 1.0):
        hit = np.zeros(N, bool)
        for k in range(10):
            te = np.zeros(N, bool)
            te[idx[k::10]] = True
            w = fit(X[~te])
            hit[te] = rule(X[te], w, cur[te], margin) == 0
        print(f"margen {margin}: validación cruzada {hit.mean():.4f}")
    w = fit(X)
    print("pesos: {" + ", ".join(f"{v:.4f}" for v in w) + "}")


if __name__ == "__main__":
    main(sys.argv[1])
