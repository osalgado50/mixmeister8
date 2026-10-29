# Resumen de una validación (salida de `mmn tsv` por pista): nivel métrico, tempo, fase, compás,
# tiempo de análisis y tipos de error. Uso: resumen2.py validacion.tsv [--fallos]
import csv, statistics as st, sys
from collections import Counter
d = [x for x in csv.reader(open(sys.argv[1], encoding='utf-8', errors='replace'), delimiter='\t') if len(x) >= 11]
n = len(d)
ok = [x for x in d if x[5] == '1']
def ratio_kind(r):
    for k, v in [('×2', 2), ('×½', .5), ('×3/2', 1.5), ('×2/3', 2/3), ('×4/3', 4/3), ('×3/4', .75), ('×3', 3), ('×⅓', 1/3)]:
        if abs(r / v - 1) < 0.03: return k
    return 'otro'
kinds = Counter(ratio_kind(float(x[4])) for x in d if x[5] != '1')
print(f'pistas: {n}')
print(f'mismo nivel métrico: {len(ok)} ({100*len(ok)/n:.1f} %)   fallos: ' + ', '.join(f'{k} {v}' for k, v in kinds.most_common()))
db = [abs(float(x[3]) - float(x[2])) for x in ok]
print(f'|ΔBPM| (mismo nivel): mediana {st.median(db):.4f}, p90 {sorted(db)[int(.9*len(db))]:.4f}, > 0,1 BPM: {sum(1 for v in db if v > .1)}')
ph = [x for x in ok if x[6] not in ('nan', '')]
fase = [x for x in ph if abs(float(x[6])) < 0.1]
media = [x for x in ph if abs(abs(float(x[6])) - 0.5) < 0.1]
print(f'fase (< 0,1 tiempos): {len(fase)} de {len(ph)} ({100*len(fase)/max(1,len(ph)):.1f} %); a contratiempo: {len(media)}')
bar = [x for x in fase if x[7] == '0']
print(f'compás (con la fase bien): {len(bar)} de {len(fase)} ({100*len(bar)/max(1,len(fase)):.1f} %)')
ms = [float(x[10]) for x in d]; secs = [float(x[1]) for x in d]
print(f'tiempo por pista: media {st.mean(ms):.0f} ms, mediana {st.median(ms):.0f} ms (pistas de {st.mean(secs)/60:.1f} min de media); {sum(secs)/max(1e-9,sum(ms)/1000):.0f}× tiempo real')
if '--fallos' in sys.argv:
    for x in d:
        if x[5] != '1': print('  NIVEL', ratio_kind(float(x[4])), f'mm {float(x[2]):.2f} nuevo {float(x[3]):.2f}', x[0][:60])
