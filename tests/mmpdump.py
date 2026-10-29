# Vuelca marcadores TRKM, segmentos TRKS y EFXT de una .mmp (para comparar experimentos).
import struct, sys
b = open(sys.argv[1], 'rb').read()
def chunks(off, end):
    while off + 8 <= end:
        cid = b[off:off+4]; n = struct.unpack_from('<I', b, off+4)[0]
        yield cid, off+8, n
        off += 8 + n + (n & 1)
def walk(off, end, d):
    for cid, o, n in chunks(off, end):
        if cid in (b'LIST', b'RIFF'):
            print('  '*d + cid.decode() + ' ' + b[o:o+4].decode('latin1')); walk(o+4, o+n, d+1)
        elif cid == b'TRKM':
            t = struct.unpack_from('<I', b, o+4)[0]; pos = struct.unpack_from('<q', b, o+8)[0]
            fl = struct.unpack_from('<I', b, o+16)[0]; v = struct.unpack_from('<f', b, o+20)[0]
            print('  '*d + 'TRKM tipo %08X pos %10.4f s flag %08X valor %.4f  n=%d  %s' % (t, pos/1e6, fl, v, n, b[o:o+n][24:].hex() if n > 24 else ''))
        elif cid == b'EFXT':
            pid = struct.unpack_from('<I', b, o+4)[0]; f = struct.unpack_from('<9I', b, o)
            pb, nc = f[7], f[8]
            ps = struct.unpack_from('<%df' % (pb//4), b, o+36)
            name = b[o+36+pb:o+36+pb+2*(nc-1)].decode('utf-16le', 'replace')
            print('  '*d + 'EFXT %r id %08X campos %s params %s' % (name, pid, [hex(x) for x in f], ['%.3f' % p for p in ps]))
        elif cid == b'TRKS':
            a, z = struct.unpack_from('<qq', b, o+8)
            print('  '*d + 'TRKS %.3f-%.3f s %s' % (a/1e6, z/1e6, b[o:o+8].hex()))
        else:
            print('  '*d + cid.decode('latin1') + ' %d B %s' % (n, b[o:o+min(n,40)].hex()))
walk(0, len(b), 0)
