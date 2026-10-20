import sys, struct, zlib, os, bz2, lzma
import xml.etree.ElementTree as ET
src, out = sys.argv[1], sys.argv[2]
f = open(src,'rb')
magic, hsize, ver, tocc, tocu, ck = struct.unpack('>4sHHQQI', f.read(28))
assert magic == b'xar!'
f.seek(hsize); toc = zlib.decompress(f.read(tocc))
open(os.path.join(out,'TOC.xml'),'wb').write(toc)
heap = hsize + tocc
root = ET.fromstring(toc)
def walk(node, path):
    for fe in node.findall('file'):
        name = fe.findtext('name'); p = os.path.join(path, name)
        typ = fe.findtext('type')
        if typ == 'directory':
            os.makedirs(p, exist_ok=True); walk(fe, p)
        else:
            d = fe.find('data')
            if d is None: open(p,'wb').close(); continue
            off, ln = int(d.findtext('offset')), int(d.findtext('length'))
            enc = d.find('encoding').get('style')
            f.seek(heap+off); raw = f.read(ln)
            if 'gzip' in enc: raw = zlib.decompress(raw)
            elif 'bzip2' in enc: raw = bz2.decompress(raw)
            elif 'lzma' in enc or 'xz' in enc: raw = lzma.decompress(raw)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p,'wb').write(raw); print(p, len(raw))
walk(root.find('toc'), out)
