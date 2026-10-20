import json, re, sys, collections
d = json.load(open(sys.argv[1]))['normalized_result']
docs = collections.OrderedDict((x['relative_path'], {'titles':[], 'texts':[], 'menus':[], 'classes':set(), 'actions':[], 'outlets':[]}) for x in d['documents'])
def doc_of(i):
    m = re.match(r'ib:"([^"]+)"', i); return m.group(1) if m else None
for x in d['graph']['nodes']:
    p = doc_of(x['id']); a = x.get('attributes') or {}
    if p not in docs: continue
    D = docs[p]
    if a.get('NSWindowTitle'): D['titles'].append(a['NSWindowTitle'])
    if a.get('NSClassName') and not a['NSClassName'].startswith('NS'): D['classes'].add(a['NSClassName'])
    cn = a.get('class_name','')
    if cn == 'NSMenuItem' and a.get('NSTitle'): D['menus'].append(a['NSTitle'] + (f" [{a['NSKeyEquiv']}]" if a.get('NSKeyEquiv') else ''))
    elif cn == 'NSMenu' and a.get('NSTitle'): D['menus'].append('## ' + a['NSTitle'])
    else:
        for k in ('NSContents','NSTitle','NSHeaderToolTip','NSToolTip','NSPlaceholderString'):
            v = a.get(k)
            if isinstance(v, str) and v.strip() and len(v) < 200: D['texts'].append(v.strip())
    if x['kind'] == 'action':
        src = (a.get('NSSource') or {}).get('className','?')
        D['actions'].append(f"{a.get('selector')}  <- {src}")
    if x['kind'] == 'outlet': D['outlets'].append(a.get('NSLabel'))
out = ['# Inventario de interfaz (nibs de MixMeister Studio 7.8)', '', 'Generado con `rea decode-interface-builder`. Solo datos de recursos: títulos, textos, menús, selectores de acción y clases propias referenciadas.', '']
for p, D in docs.items():
    out.append(f"## {p.split('/')[-1] if 'MainMenu' not in p else 'MainMenu.nib/'+p.split('/')[-1]}")
    if D['titles']: out.append('**Ventanas:** ' + ' · '.join(dict.fromkeys(D['titles'])))
    if D['classes']: out.append('**Clases propias:** ' + ', '.join(sorted(D['classes'])))
    if D['menus']: out.append('**Menús:** ' + ' | '.join(D['menus']))
    if D['texts']: out.append('**Textos:** ' + ' · '.join(dict.fromkeys(D['texts'])))
    if D['actions']: out.append('**Acciones:** ' + ', '.join(sorted(set(a.split('  <-')[0] for a in D['actions']))))
    if D['outlets']: out.append('**Outlets:** ' + ', '.join(sorted(set(filter(None, D['outlets'])))))
    out.append('')
open(sys.argv[2],'w').write('\n'.join(out))
print(len(out))
