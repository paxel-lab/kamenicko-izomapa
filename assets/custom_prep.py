# Vlastní úpravy dat, terénu a doplňků pro konkrétní město (Kamenice).
# Spouští se automaticky z prep.py v jednotlivých fázích (HOOK), takže prep.py zůstává čistý.

if HOOK == 'props':
    # Názvy a typy dominant na kartě budovy: volitelná pole "nazev" a "typ" v assets/dominanty.json
    # přepíšou name a cls v binfo u budovy napárované na dominantu. Bez těch polí se nic nemění.
    # Mění se jen popisek karty (binfo -> overlay.py), scéna a render zůstávají stejné.
    #
    # Párování: dominanta se spec je v DOM_BY_ID (Overture id budovy -> dominanta; binfo['oid'] je totéž id).
    # Dominanty bez spec (celá Kamenice zatím) v DOM_BY_ID nejsou, ty se párují stejným pravidlem jako
    # match_doms v prep.py: bod uvnitř půdorysu, jinak největší budova (nad 60 m²) do 25 m.
    _dom_json = json.load(open('assets/dominanty.json', encoding='utf-8')) if os.path.exists('assets/dominanty.json') else []
    _prejmenovat = [d for d in _dom_json if d.get('nazev') or d.get('typ')]
    if _prejmenovat:
        _bg = list(bld.geom)
        _bt = shapely.STRtree(_bg)
        _binfo_by_oid = {}                                                       # budova může mít víc dílů (záznamů binfo)
        for b_ in binfo: _binfo_by_oid.setdefault(b_['oid'], []).append(b_)
        _zabrano = {}                                                            # id budovy -> název dominanty, která ji přepsala
        for d in _prejmenovat:
            oid_ = None
            for o_, dd in DOM_BY_ID.items():                                    # DOM_BY_ID podle názvu dominanty
                if dd['name'] == d['name']: oid_ = o_; break
            if oid_ is None:
                x_, y_ = to_local(d['lon'], d['lat']); pt_ = Point(float(x_), float(y_))
                hit_ = [k for k in _bt.query(pt_.buffer(25)) if _bg[k].area > 60]
                in_ = [k for k in hit_ if _bg[k].buffer(1.0).contains(pt_)]
                cand_ = in_ or sorted(hit_, key=lambda k: -_bg[k].area)
                if cand_: oid_ = bld.id.iloc[cand_[0]]
            bis_ = _binfo_by_oid.get(oid_)
            if not bis_: continue                                                # budova je v jiném čtverci, nebo žádná není
            if oid_ in _zabrano: print('POZOR: budovu', oid_, 'přepisují dvě dominanty:', _zabrano[oid_], '+', d['name'])
            _zabrano[oid_] = d['name']
            for bi_ in bis_:
                if d.get('nazev'): bi_['name'] = d['nazev']
                if d.get('typ'): bi_['cls'] = d['typ']
            print('dominanta', d['name'], '-> karta:', bis_[0]['name'], '/', bis_[0]['cls'], f'({len(bis_)}x)')
