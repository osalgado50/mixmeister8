# Dónde suena la pista 2 del --synctest (entra en 10 s, audio a 120 BPM, suena a TEMPO) frente al
# audio original. Uso: sincronia.py render.wav TEMPO ref.wav [desfase] → desfase máximo (ms) a partir de 20 s.
# desfase: muestras de la línea de tiempo de MixMeister frente a AVAudioFile (se descuentan).
import wave, sys, math
def env(path, t, dur, hop):
    w=wave.open(path); sr=w.getframerate(); sw=w.getsampwidth(); ch=w.getnchannels(); w.setpos(max(0,int(t*sr))); raw=w.readframes(int((dur+0.9)*sr))
    x=[abs(int.from_bytes(raw[i:i+sw],'little',signed=True)) for i in range(0,len(raw),sw*ch)]
    n=int(hop*sr/1000); out=[]; pos=0.0
    while int(pos)+n < len(x): a=int(pos); out.append(sum(x[a:a+n])/n); pos+=hop*sr/1000
    return out
def corr(a,b):
    ma=sum(a)/len(a); mb=sum(b)/len(b)
    num=sum((x-ma)*(y-mb) for x,y in zip(a,b)); den=math.sqrt(sum((x-ma)**2 for x in a)*sum((y-mb)**2 for y in b))+1e-9
    return num/den
f, tempo, ref = sys.argv[1], float(sys.argv[2]), sys.argv[3]; R = tempo/120
lead_ms = (int(sys.argv[4]) if len(sys.argv) > 4 else 0) / 44.1 / R
worst=0
for S in [20, 80, 160, 300]:
    src=env(ref, S, 1.5, R)[:1400]
    out=env(f, 10+S/R-0.4, 2.2, 1.0)
    best=max(range(0,800,2), key=lambda L: corr(src, out[L:L+1400]))
    best=max(range(max(0,best-2),best+3), key=lambda L: corr(src, out[L:L+1400]))
    worst=max(worst, abs(best-400-lead_ms))
print(round(worst))
