"""Árbol completo de menús de un nib, a partir del JSON de `rea decode-interface-builder`.

Uso: python3 -I menu_tree.py ib.json "MainMenu.nib/keyedobjects.nib" salida.json salida.md

Solo lee recursos (títulos, atajos, selectores de acción), no código.
"""
import json, re, sys

ib, nib, out_json, out_md = sys.argv[1:5]
g = json.load(open(ib))['normalized_result']['graph']
nodes = {}
for x in g['nodes']:
    if nib not in x['id']:
        continue
    a = x.get('attributes') or {}
    uid = a.get('interface_builder_object_id')
    if uid is not None:
        nodes[int(uid)] = a
actions = {}  # uid del ítem -> selector
for x in g['nodes']:
    if nib in x['id'] and x['kind'] == 'action':
        a = x['attributes']
        src = (a.get('NSSource') or {}).get('archiveUID')
        if src is not None:
            actions[src] = a.get('selector')

MODS = [(1 << 17, 'shift'), (1 << 18, 'ctrl'), (1 << 19, 'opt'), (1 << 20, 'cmd')]


def ref(v):
    return v.get('archiveUID') if isinstance(v, dict) else None


def item(uid):
    a = nodes[uid]
    if a.get('NSIsSeparator'):
        return {'separator': True}
    key = a.get('NSKeyEquiv', '')
    mask = a.get('NSKeyEquivModMask', 0) if key else 0
    mods = [n for b, n in MODS if mask & b]
    if key and key != key.lower():
        mods = sorted(set(mods) | {'shift'})
    d = {'title': a.get('NSTitle', ''), 'key': key, 'mods': mods}
    sel = actions.get(uid) or (a.get('NSAction') if a.get('NSAction') != 'submenuAction:' else None)
    if sel:
        d['action'] = sel
    if a.get('NSTag'):
        d['tag'] = a['NSTag']
    if a.get('NSIsDisabled'):
        d['disabled'] = True
    if a.get('NSState'):
        d['state'] = a['NSState']
    if a.get('NSIsHidden'):
        d['hidden'] = True
    sub = ref(a.get('NSSubmenu'))
    if sub is not None:
        d['submenu'] = menu(sub)
    return d


def menu(uid):
    a = nodes[uid]
    arr = nodes.get(ref(a.get('NSMenuItems')), {}).get('NS.objects', [])
    return {'title': a.get('NSTitle', ''), 'uid': uid, 'items': [item(ref(o)) for o in arr]}


# Menús raíz: los que no son submenú de ningún ítem.
subs = {ref(a.get('NSSubmenu')) for a in nodes.values() if a.get('class_name') == 'NSMenuItem'}
roots = [u for u, a in sorted(nodes.items()) if a.get('class_name') == 'NSMenu' and u not in subs]
tree = [menu(u) for u in roots]
json.dump(tree, open(out_json, 'w'), indent=1, ensure_ascii=False)

SYM = {'cmd': '⌘', 'shift': '⇧', 'opt': '⌥', 'ctrl': '⌃'}
KEYS = {'\x7f': '⌫', '\r': '↩', ' ': 'Espacio', '\x1b': 'Esc', '': '⌦', '': '←', '': '→',
        '': '↑', '': '↓', '\t': '⇥'}


def shortcut(d):
    if not d.get('key'):
        return ''
    k = KEYS.get(d['key'], d['key'].upper())
    return ''.join(SYM[m] for m in ('ctrl', 'opt', 'shift', 'cmd') if m in d['mods']) + k


lines = ['# Menús de MixMeister Fusion 7.8 — árbol completo', '',
         'Generado con `tools/menu_tree.py` desde los nibs (solo recursos). Orden, separadores, atajos y',
         'acción de cada ítem. Los menús sin título son contextuales; se identifican por su contenido.', '']


def emit(m, depth):
    for d in m['items']:
        pad = '  ' * depth
        if d.get('separator'):
            lines.append(pad + '- ———')
            continue
        s = shortcut(d)
        extra = ' '.join(x for x in [f'`{s}`' if s else '', f"→ `{d['action']}`" if d.get('action') else '',
                                     '(oculto)' if d.get('hidden') else '', f"tag {d['tag']}" if d.get('tag') else ''] if x)
        lines.append(f"{pad}- **{d['title'] or '(sin título)'}** {extra}".rstrip())
        if 'submenu' in d:
            emit(d['submenu'], depth + 1)


for m in tree:
    lines.append(f"## {m['title'] or '(contextual)'} · uid {m['uid']}")
    emit(m, 0)
    lines.append('')
open(out_md, 'w').write('\n'.join(lines))
print(len(tree), 'menús raíz')
