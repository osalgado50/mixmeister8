# Dónde difieren dos exportaciones: segundos con diferencia (> -60 dB respecto a la señal). Uso: difftramo.py a.wav b.wav
import wave, sys, math
A = wave.open(sys.argv[1]); B = wave.open(sys.argv[2]); sr = A.getframerate(); sw = A.getsampwidth()
n = min(A.getnframes(), B.getnframes()) // sr
dif = []
for s in range(n):
    ra = A.readframes(sr); rb = B.readframes(sr)
    xa = [int.from_bytes(ra[i:i+sw], 'little', signed=True) for i in range(0, len(ra), sw * 4)]
    xb = [int.from_bytes(rb[i:i+sw], 'little', signed=True) for i in range(0, len(rb), sw * 4)]
    e = sum((p - q) ** 2 for p, q in zip(xa, xb)); sig = sum(p * p for p in xa) + 1
    dif.append(10 * math.log10(e / sig + 1e-12))
on = [s for s, d in enumerate(dif) if d > -60]
tramos = []
for s in on:
    if tramos and s == tramos[-1][1] + 1: tramos[-1][1] = s
    else: tramos.append([s, s])
print('segundos distintos:', len(on), 'tramos:', ' '.join('%d-%d' % (a, z + 1) for a, z in tramos) or 'ninguno')
