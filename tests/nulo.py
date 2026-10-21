# Prueba nula: ¿la exportación (24 bits) es idéntica al audio decodificado? Uso: nulo.py export.wav ref.wav
import wave, sys
def load(p, start, n):
    w=wave.open(p); sw=w.getsampwidth(); ch=w.getnchannels(); w.setpos(start); raw=w.readframes(n)
    v=[int.from_bytes(raw[i:i+sw],'little',signed=True) for i in range(0,len(raw),sw)]
    return v if ch==2 else [x for x in v for _ in (0,1)]
a=load(sys.argv[1], 44100*30, 44100*10); b=load(sys.argv[2], 44100*30, 44100*10)
same=sum(1 for x,y in zip(a,b) if x==y)
print('%d %d' % (same, len(a)))
