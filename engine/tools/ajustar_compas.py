#!/usr/bin/env python3
"""Ajusta los pesos de bar_score() a partir de `mmn bardiag` sobre una biblioteca.

Entrada: TSV, una línea por pista:  nombre  posición_MixMeister(0-3)  4 × 8 rasgos
Modelo: puntuación por posición s_j = w·f_j; se elige argmax_j. Ajuste por softmax
(entropía cruzada) con regularización L2; acierto medido en validación cruzada.

Uso: python3 tools/ajustar_compas.py compas-rasgos.tsv
Requiere numpy.
"""
import csv
import sys

import numpy as np

NAMES = ["ataque sub", "ataque graves", "ataque medios", "ataque agudos",
         "cambio armónico", "novedad compás", "salto nivel", "primer tiempo"]


def load(path):
    names, y, X = [], [], []
    for r in csv.reader(open(path), delimiter="\t"):
        if len(r) < 2 + 32:
            continue
        names.append(r[0])
        y.append(int(r[1]))
        X.append(np.array(r[2:34], float).reshape(4, 8))
    return names, np.array(y), np.array(X)


def fit(X, y, l2=1.0, iters=4000, lr=0.5):
    mu = np.abs(X).reshape(-1, X.shape[2]).mean(0) + 1e-9
    Xs = X / mu
    w = np.zeros(X.shape[2])
    for _ in range(iters):
        s = Xs @ w                      # (n, 4)
        s -= s.max(1, keepdims=True)
        p = np.exp(s)
        p /= p.sum(1, keepdims=True)
        onehot = np.eye(4)[y]
        g = np.einsum("nj,njf->f", p - onehot, Xs) / len(y) + l2 * w / len(y)
        w -= lr * g
    return w / mu


def acc(X, y, w):
    return float(np.mean(np.argmax(X @ w, 1) == y))


def main(path):
    names, y, X = load(path)
    print(f"pistas: {len(y)}")
    print(f"convención actual (primer tiempo que suena): {np.mean(np.argmax(X[:, :, 7], 1) == y):.3f}")
    idx = np.random.default_rng(0).permutation(len(y))
    for subset, label in [(list(range(8)), "todos los rasgos"), (list(range(7)), "sin 'primer tiempo'")]:
        a = []
        for k in range(10):
            te = idx[k::10]
            tr = np.setdiff1d(idx, te)
            w = fit(X[tr][:, :, subset], y[tr])
            a.append(acc(X[te][:, :, subset], y[te], w))
        print(f"{label}: validación cruzada 10 partes {np.mean(a):.3f} ± {np.std(a):.3f}")
    w = fit(X, y)
    print("pesos: {" + ", ".join(f"{v:.4f}" for v in w) + "}")
    for n, v in zip(NAMES, w):
        print(f"  {n:16s} {v:+.4f}")


if __name__ == "__main__":
    main(sys.argv[1])
