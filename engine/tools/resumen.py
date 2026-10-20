import csv,statistics as st,sys
d=[x for x in csv.reader(open(sys.argv[1]),delimiter='\t') if len(x)>8]
for x in d: print(f'{x[0][:26]:<26} mm {float(x[2]):9.4f} nuevo {float(x[3]):9.4f} nivel {x[5]} entrada {float(x[6]):+.3f} t{int(x[7])+1}')
ok=[x for x in d if x[5]=='1']
print('nivel ok', len(ok), '/', len(d))
print('|dBPM| mediana %.4f max %.4f' % (st.median(abs(float(x[3])-float(x[2])) for x in ok), max(abs(float(x[3])-float(x[2])) for x in ok)))
ms=[float(x[6])*60/float(x[2])*1000 for x in ok]
print('desfase entrada (ms) mediana %.1f, |max| %.1f, medio tiempo: %d' % (st.median(ms), max(abs(m) for m in ms), sum(1 for x in ok if abs(float(x[6]))>0.25)))
print('entrada en tiempo 1:', sum(1 for x in ok if x[7]=='0'), '/', len(ok))
