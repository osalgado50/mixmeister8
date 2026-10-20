import plistlib, sys
p = plistlib.load(open(sys.argv[1],'rb')); O = p['$objects']
def r(x):
    return O[x.data] if isinstance(x, plistlib.UID) else x
def cls(o):
    return r(o['$class'])['$classname'] if isinstance(o, dict) and '$class' in o else type(o).__name__
def coll(o):
    o = r(o)
    if isinstance(o, dict) and 'NS.keys' in o:
        return {r(k): r(v) for k, v in zip(o['NS.keys'], o['NS.objects'])}
    if isinstance(o, dict) and 'NS.objects' in o: return [r(v) for v in o['NS.objects']]
    return o
TYPES = {0:'Undefined',100:'Int16',200:'Int32',300:'Int64',400:'Decimal',500:'Double',600:'Float',700:'String',800:'Boolean',900:'Date',1000:'Binary',1100:'UUID',1200:'URI',1800:'Transformable',2000:'ObjectID'}
root = r(p['$top']['root'])
ents = coll(root.get('NSEntities'))
for name, e in ents.items():
    print(f"\n### {name}  (clase: {r(e.get('NSClassNameForEntity'))})")
    props = coll(e.get('NSProperties')) or {}
    for pn, pr in props.items():
        c = cls(pr)
        if 'Relationship' in c:
            dest = r(pr.get('NSDestinationEntity')); dn = r(dest.get('NSEntityName')) if isinstance(dest, dict) else dest
            mx = pr.get('NSMaxCount'); print(f"- {pn}: -> {dn} ({'a-muchos' if mx in (0,None) or (isinstance(mx,int) and mx>1) else 'a-uno'})")
        else:
            t = pr.get('NSAttributeType'); opt = pr.get('NSIsOptional')
            print(f"- {pn}: {TYPES.get(t, t)}{'' if opt else ' (obligatorio)'}")
