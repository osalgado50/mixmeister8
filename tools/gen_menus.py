"""Genera app/Sources/MixMeister8/Generated/MenuSpec.swift desde docs/spec/menus-fusion.json.

Los menús de MixMeister 8 salen así del árbol extraído de los nibs de Fusion 7.8: mismos títulos,
orden, separadores, atajos y selectores de acción. Cambios deliberados, y solo estos:
  · el nombre de la app ("MixMeister" → "MixMeister 8") y la ayuda ("MixMeister Fusion Help");
  · fuera "Buy Now..." y "Register Online...": no hay licencias ni registro (ni PACE).
Uso: python3 tools/gen_menus.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tree = json.load(open(os.path.join(ROOT, 'docs/spec/menus-fusion.json')))
by_uid = {m['uid']: m for m in tree}

# Menús contextuales: uid en el nib → nombre en la app.
CONTEXT = {705: 'playlist', 841: 'libraryColumns', 885: 'playlistColumns', 943: 'timelineTrack', 986: 'timelineMarker',
           993: 'timelineRange', 1013: 'timelineRuler', 1021: 'timelineRulerMarker', 1027: 'timelineStrips',
           1036: 'library', 1122: 'songSlicer'}
DROP = {'Buy Now...', 'Register Online...'}
RENAME = {'About MixMeister': 'About MixMeister 8', 'Hide MixMeister': 'Hide MixMeister 8',
          'Quit MixMeister': 'Quit MixMeister 8', 'MixMeister Fusion Help': 'MixMeister 8 Help', 'MixMeister': 'MixMeister 8'}


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def key_literal(k):
    out = ''
    for ch in k:
        o = ord(ch)
        out += ch if 0x20 <= o < 0x7f and ch not in '"\\' else '\\u{%x}' % o
    return out


def clean(items):
    out = []
    for d in items:
        if d.get('title') in DROP:
            continue
        if d.get('separator') and (not out or out[-1].get('separator')):
            continue
        out.append(d)
    while out and out[-1].get('separator'):
        out.pop()
    return out


def item(d, ind):
    p = ' ' * ind
    if d.get('separator'):
        return p + '.separator'
    title = RENAME.get(d['title'], d['title'])
    args = [f'"{esc(title)}"']
    if d.get('action'):
        args.append(f'action: "{d["action"]}"')
    if d.get('key'):
        args.append(f'key: "{key_literal(d["key"])}"')
        args.append('mods: [' + ', '.join('.' + m for m in d['mods']) + ']')
    if d.get('tag'):
        args.append(f'tag: {d["tag"]}')
    if 'submenu' in d:
        args.append('submenu: ' + menu(d['submenu'], ind))
    return p + '.item(' + ', '.join(args) + ')'


def menu(m, ind):
    title = RENAME.get(m['title'], m['title'])
    inner = ',\n'.join(item(d, ind + 4) for d in clean(m['items']))
    return f'MenuSpec("{esc(title)}", [\n{inner}\n{" " * ind}])'


out = ['// GENERADO por tools/gen_menus.py desde docs/spec/menus-fusion.json — no editar a mano.', '',
       'enum MenuSpecs {',
       '    static let main = ' + menu(by_uid[1700], 4)]
for uid, name in CONTEXT.items():
    out.append(f'    static let {name} = ' + menu(by_uid[uid], 4))
out.append('}')
dst = os.path.join(ROOT, 'app/Sources/MixMeister8/Generated/MenuSpec.swift')
os.makedirs(os.path.dirname(dst), exist_ok=True)
open(dst, 'w').write('\n'.join(out) + '\n')
print('escrito', dst)
