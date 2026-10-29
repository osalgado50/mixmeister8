# GiantSteps Tempo (anotaciones v2 de Schreiber, 664 pistas EDM): Accuracy1 (±4 %) y Accuracy2
# (también ×2, ×½, ×3, ×⅓). Uso: gs_tempo.py analisis.jsonl anotaciones.tsv [--fallos]
# analisis.jsonl: una salida de `mmn analyze --json` por línea.
import json, sys, collections
ann = {l.split('\t')[0]: float(l.split('\t')[1]) for l in open(sys.argv[2]) if '\t' in l}
res = {}
for line in open(sys.argv[1]):
    line = line.strip().rstrip(',')
    if line.startswith('{'):   # una pista por línea (salida de `mmn analyze --json`)
        r = json.loads(line)
        res[r['file'].rsplit('.', 1)[0]] = r
    elif line.startswith('[{'):
        for r in json.loads(line):
            res[r['file'].rsplit('.', 1)[0]] = r
n = a1 = a2 = 0
kinds = collections.Counter()
fallos = []
for k, t in ann.items():
    if k not in res or t <= 0: continue
    n += 1
    e = res[k]['bpm']
    ok1 = abs(e / t - 1) <= 0.04
    ok2 = any(abs(e / (t * f) - 1) <= 0.04 for f in (1, 2, .5, 3, 1/3))
    a1 += ok1; a2 += ok2
    if not ok1:
        r = e / t
        kinds['×2' if abs(r/2-1) < .04 else '×½' if abs(r*2-1) < .04 else '×3' if abs(r/3-1) < .04 else '×⅓' if abs(r*3-1) < .04 else '×3/2' if abs(r/1.5-1) < .04 else '×2/3' if abs(r*1.5-1) < .04 else 'otro'] += 1
        fallos.append((k, t, e))
print(f'GiantSteps Tempo: {n} pistas · Accuracy1 {100*a1/n:.1f} % · Accuracy2 {100*a2/n:.1f} % · fallos: ' + ', '.join(f'{k} {v}' for k, v in kinds.most_common()))
ms = [res[k]['ms'] for k in ann if k in res]
print(f'tiempo medio {sum(ms)/len(ms):.0f} ms por pista (2 min)')
if '--fallos' in sys.argv:
    for k, t, e in fallos: print(f'  {k}: anotado {t:.1f}, motor {e:.2f}')
