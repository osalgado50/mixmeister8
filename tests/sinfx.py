# Copia una .mmp quitando los efectos de las pistas (LIST TKEL) y sus marcadores; el master queda igual. Uso: sinfx.py in out
import struct, sys
b = open(sys.argv[1], 'rb').read()
def rebuild(off, end):
    out = b''
    while off + 8 <= end:
        cid = b[off:off+4]; n = struct.unpack_from('<I', b, off+4)[0]; o = off + 8
        nxt = off + 8 + n + (n & 1)
        if cid in (b'LIST', b'RIFF'):
            typ = b[o:o+4]
            if typ == b'TKEL': off = nxt; continue
            body = typ + rebuild(o+4, o+n)
            out += cid + struct.pack('<I', len(body)) + body + (b'\0' if len(body) & 1 else b'')
        elif (cid == b'TRKM' and struct.unpack_from('<I', b, o+4)[0] == 0x08000000):
            pass
        else:
            out += b[off:nxt]
        off = nxt
    return out
open(sys.argv[2], 'wb').write(rebuild(0, len(b)))
