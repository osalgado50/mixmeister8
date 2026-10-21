import wave, array, sys
def seg(p, t, d):
    w=wave.open(p); w.setpos(int(t*44100)); x=array.array('h', w.readframes(int(d*44100))); return x[::2]
for t in [100, 239, 245, 300, 330, 470, 700, 1200, 2000]:
    a=seg(sys.argv[1], t, 1.0); b=seg(sys.argv[2], t-0.05, 1.1)
    best=(0,-1e30)
    for lag in range(0, 4410, 2):
        c=sum(a[i]*b[i+lag] for i in range(0, len(a), 8))
        if c>best[1]: best=(lag,c)
    lag=best[0]; lo=max(0,lag-3); bb=best
    for l in range(lo, lag+4):
        c=sum(a[i]*b[i+l] for i in range(0,len(a),4))
        if c>bb[1]: bb=(l,c)
    print('%5d s: desfase %+.2f ms' % (t, (bb[0]-2205)/44.1))
