#!/usr/bin/env python3
"""Evalúa la tonalidad sobre un corpus anotado (p. ej. GiantSteps) con la métrica MIREX.

Entradas:
  cromas.tsv       salida de `mmn key --chroma`: fichero  nombre  camelot  margen  12 valores
  anotaciones.tsv  id  "C minor"  (id = nombre de fichero sin extensión)
Compara perfiles publicados con perfiles aprendidos (mediana del cromagrama rotado a C por
modo, como en Faraldo 2016) en validación cruzada de 10 partes.

Uso: python3 tools/evaluar_tonalidad.py cromas.tsv anotaciones.tsv
"""
import csv
import sys

import numpy as np

ROOTS = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
         "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11, "Cb": 11}
KK = (np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]),
      np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]))
TEMP = (np.array([5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0]),
        np.array([5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]))


def parse(s):
    s = s.strip()
    for name in sorted(ROOTS, key=len, reverse=True):
        if s.startswith(name):
            return ROOTS[name], ("minor" in s)
    return None


def mirex(e, r):
    (et, em), (rt, rm) = e, r
    if et == rt and em == rm:
        return 1.0
    if em == rm and ((et - rt) % 12 in (5, 7)):
        return 0.5
    if (not rm) and em and et == (rt + 9) % 12:
        return 0.3
    if rm and (not em) and et == (rt + 3) % 12:
        return 0.3
    if et == rt and em != rm:
        return 0.2
    return 0.0


def estimate(c, prof):
    best, bk = -2, None
    for mode in (0, 1):
        for t in range(12):
            r = np.corrcoef(c, np.roll(prof[mode], t))[0, 1]
            if r > best:
                best, bk = r, (t, mode == 1)
    return bk


def learn(C, refs):
    """Perfil por modo = mediana de los cromagramas rotados a C (como Faraldo 2016, 'edma')."""
    out = []
    for mode in (False, True):
        rows = [np.roll(c, -t) for c, (t, m) in zip(C, refs) if m == mode]
        out.append(np.median(rows, axis=0) if rows else np.ones(12))
    return tuple(out)


def score(C, refs, prof):
    return float(np.mean([mirex(estimate(c, prof), r) for c, r in zip(C, refs)]))


def main(cpath, apath):
    ann = {r[0]: parse(r[1]) for r in csv.reader(open(apath), delimiter="\t") if len(r) > 1}
    C, refs = [], []
    for r in csv.reader(open(cpath), delimiter="\t"):
        key = r[0].rsplit(".", 1)[0]
        if key in ann and ann[key] is not None and len(r) >= 16:
            C.append(np.array(r[4:16], float))
            refs.append(ann[key])
    C = np.array(C)
    print(f"pistas: {len(C)}")
    print(f"Krumhansl: MIREX {score(C, refs, KK):.3f}")
    print(f"Temperley: MIREX {score(C, refs, TEMP):.3f}")
    idx = np.random.default_rng(0).permutation(len(C))
    s = []
    for k in range(10):
        te = idx[k::10]
        tr = np.setdiff1d(idx, te)
        p = learn(C[tr], [refs[i] for i in tr])
        s.append(score(C[te], [refs[i] for i in te], p))
    print(f"perfil aprendido (mediana): MIREX en validación cruzada {np.mean(s):.3f} ± {np.std(s):.3f}")
    p = learn(C, refs)
    exact = np.mean([estimate(c, p) == r for c, r in zip(C, refs)])
    print(f"  exactas (en muestra) {exact:.3f}")
    for name, v in zip(("mayor", "menor"), p):
        print(f"  {name}: {{" + ", ".join(f"{x:.4f}" for x in v / v.max()) + "}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
