#!/usr/bin/env python3
"""Ajusta los pesos de phase_score() a partir de `mmn phasediag` sobre una biblioteca.

Entrada: TSV con dos líneas por pista (fase de MixMeister = 0, contratiempo = 1):
    nombre  fase  coincide  48 flujos  48 caídas
Salida: los 8 pesos para src/analysis/rhythm.cpp y el acierto en validación cruzada.

Uso: python3 tools/ajustar_fase.py fase-rasgos.tsv
Requiere numpy.
"""
import csv
import sys

import numpy as np

GROUPS = [(30, 90), (90, 250), (250, 2000), (2000, 8000)]


def load(path):
    tracks = {}
    for r in csv.reader(open(path), delimiter="\t"):
        tracks.setdefault(r[0], {})[int(r[1])] = (np.array(r[3:51], float), np.array(r[51:99], float))
    names = [n for n in tracks if 0 in tracks[n] and 1 in tracks[n]]
    return names, tracks


def grouped(flux, decay):
    edges = np.array([30 * (8000 / 30) ** (b / 48) for b in range(49)])
    ctr = np.sqrt(edges[:-1] * edges[1:])
    feats = [flux[(ctr >= lo) & (ctr < hi)].mean() for lo, hi in GROUPS]
    feats += [decay[(ctr >= lo) & (ctr < hi)].mean() for lo, hi in GROUPS]
    return np.array(feats)


def fit(d, l2=1.0, iters=3000, lr=1.0):
    """Logística sin sesgo sobre diferencias antisimétricas: p = σ(w·(x_tiempo − x_contratiempo))."""
    X = np.vstack([d, -d])
    y = np.r_[np.ones(len(d)), np.zeros(len(d))]
    mu = np.abs(X).mean(0) + 1e-9
    Xs = X / mu
    w = np.zeros(X.shape[1])
    for _ in range(iters):
        p = 1 / (1 + np.exp(-Xs @ w))
        w -= lr * (Xs.T @ (p - y) / len(y) + l2 * w / len(y))
    return w / mu


def main(path):
    names, tracks = load(path)
    diff = np.array([grouped(*tracks[n][0]) - grouped(*tracks[n][1]) for n in names])
    idx = np.random.default_rng(0).permutation(len(diff))
    acc = []
    for k in range(10):
        te = idx[k::10]
        tr = np.setdiff1d(idx, te)
        acc.append(np.mean(diff[te] @ fit(diff[tr]) > 0))
    w = fit(diff)
    print(f"pistas: {len(names)}")
    print(f"validación cruzada 10 partes: {np.mean(acc):.3f} ± {np.std(acc):.3f}")
    print("pesos: {" + ", ".join(f"{v:.4f}" for v in w) + "}")


if __name__ == "__main__":
    main(sys.argv[1])
