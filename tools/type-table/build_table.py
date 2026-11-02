#!/usr/bin/env python3
"""Build zaisen's train-type table from pdf_runs.json (Keihan's official
all-trains timetable PDFs) and validate it against startTimeList.json plus
the live position feed.

Signature (shared spec with the agent):
- Universe: the 42 Keihan Main Line stations in zaisen STATIONS order
  (index 0 = Demachiyanagi ... 41 = Yodoyabashi).
- The signature is the STOP SET only: 'S' at stations the train stops at,
  '.' elsewhere. Pass marks are NOT used: the timetable JSON omits minor
  pass stations entirely while the PDF marks every pass, so the two
  sources only agree on stops. ('-' in the timetable = the run's boundary
  station, which is served, so it counts as a stop.)
- Key: dir|dest|pattern. Timetable entries whose destination is the
  Neyagawa signal yard are keyed by their last passenger stop instead
  (the PDF names that stop as the destination).

Output agent_table.json:
- W / H: {key: typeAb} for keys whose type is unambiguous per day type.
- T: {key: {kitahamaDepTime: typeAb}} for keys shared by two types
  (the Liner vs Limited Express stop sets are identical); the agent
  disambiguates by the train's Kitahama departure time. Kitahama is a
  single-line row in the PDF: at two-line (arrival/departure) stations
  like Kyobashi the PDF's extracted time runs 1 minute ahead of the
  timetable JSON, while single-line stations agree exactly.
"""
import json
import sys
from collections import Counter, defaultdict

STATIONS = ['出町柳', '神宮丸太町', '三条', '祇園四条', '清水五条', '七条', '東福寺',
            '鳥羽街道', '伏見稲荷', '龍谷大前深草', '藤森', '墨染', '丹波橋', '伏見桃山',
            '中書島', '淀', '石清水八幡宮', '橋本', '樟葉', '牧野', '御殿山', '枚方市',
            '枚方公園', '光善寺', '香里園', '寝屋川市', '萱島', '大和田', '古川橋',
            '門真市', '西三荘', '守口市', '土居', '滝井', '千林', '森小路', '関目',
            '野江', '京橋', '天満橋', '北浜', '淀屋橋']
IDX = {n: i for i, n in enumerate(STATIONS)}
TYPE_AB = {'特急': '特', '準急': '準', '急行': '急', '快速急行': '快', '快速特急': '快',
           '区間急行': '区', '通勤準急': '通', '通勤快急': '通', 'ライナー': 'ラ',
           '普通': '普', '深夜急行': '急'}


def pdf_key(run):
    pat = ''.join('S' if run['cells'].get(n) == 'S' else '.' for n in STATIONS)
    return f"{run['dir']}|{run['dest']}|{pat}"


def tt_key(entry):
    dia = entry['diaStationInfoObjects']
    cells = {}
    served = []
    for s in dia:
        n = s['stationNameJp']
        if n not in IDX:
            continue
        if s['stationDepTime'] != '99:99':
            cells[n] = 'S'
        served.append(IDX[n])
    if not served:
        return None, 0
    direction = 'up' if served[-1] < served[0] else 'down'
    pat = ''.join(cells.get(n, '.') for n in STATIONS)
    dest = dia[-1]['stationNameJp'] if dia else ''
    if dest == '寝屋川信号場':
        stops = [s['stationNameJp'] for s in dia if cells.get(s['stationNameJp']) == 'S']
        if stops:
            dest = stops[-1]
    return f"{direction}|{dest}|{pat}", pat.count('S')


def norm_time(t):
    """PDF prints '6:50', the timetable JSON prints '06:50' — unify."""
    if not t or ':' not in t:
        return t
    h, m = t.split(':')
    return f'{int(h)}:{m}'


def main():
    runs = json.load(open('pdf_runs.json'))
    tt = json.load(open(sys.argv[1] if len(sys.argv) > 1 else '/tmp/tt_now.json'))
    types_by = {'weekday': defaultdict(set), 'holiday': defaultdict(set)}
    for r in runs:
        types_by[r['day']][pdf_key(r)].add(r['type'])
    colliding = set()
    for day in types_by:
        for k, v in types_by[day].items():
            if len(v) > 1:
                colliding.add(k)
    print('colliding keys (all days):', len(colliding))
    W = {k: TYPE_AB[next(iter(v))] for k, v in types_by['weekday'].items()
         if k not in colliding}
    H = {k: TYPE_AB[next(iter(v))] for k, v in types_by['holiday'].items()
         if k not in colliding}
    # T: disambiguate colliding keys by Kyobashi departure time.
    T = {}
    t_conflicts = 0
    for k in colliding:
        m = {}
        for r in runs:
            if pdf_key(r) != k:
                continue
            kt = norm_time(r.get('times', {}).get('北浜'))
            if not kt:
                continue
            ab = TYPE_AB[r['type']]
            if kt in m and m[kt] != ab:
                t_conflicts += 1
                m[kt] = None
            else:
                m[kt] = ab
        T[k] = {t: ab for t, ab in m.items() if ab}
        print(f'  T key dest={k.split("|")[1]} times={len(T[k])} '
              f'({Counter(T[k].values())})')
    print('T time conflicts dropped:', t_conflicts)

    def resolve(key, day, kyo_time):
        own = W if day == 'weekday' else H
        other = H if day == 'weekday' else W
        if key in own:
            return own[key]
        if kyo_time and key in T and kyo_time in T[key]:
            return T[key][kyo_time]
        return other.get(key)

    # validate against today's timetable (weekday file)
    matched = mainline = branch = 0
    type_by_wdf = {}
    for e in tt['TrainInfo']:
        k, nstops = tt_key(e)
        if k is None or nstops <= 1:
            branch += 1
            continue
        mainline += 1
        kyo = norm_time(next((s['stationDepTime'] for s in e['diaStationInfoObjects']
                              if s['stationNameJp'] == '北浜'), None))
        t = resolve(k, 'weekday', kyo)
        if t:
            matched += 1
            type_by_wdf[str(e['wdfBlockNo'])] = t
    print(f'timetable: mainline {mainline}, resolved {matched} '
          f'({matched / mainline:.1%}), branch-only {branch}')
    json.dump({'W': W, 'H': H, 'T': T,
               'meta': {'diagram': '2026-08-24', 'source': 'keihan time01-1..4.pdf'}},
              open('agent_table.json', 'w'), ensure_ascii=False)
    json.dump(type_by_wdf, open('type_by_wdf_today.json', 'w'), ensure_ascii=False)
    print('wrote agent_table.json  W=%d H=%d T=%d' % (len(W), len(H), len(T)))
    full = {'特': '特急', '準': '準急', '急': '急行', '快': '快速急行', '区': '区間急行',
            '通': '通勤準急/快急', 'ラ': 'ライナー', '普': '普通'}
    try:
        pos = json.load(open('/tmp/pos_now.json'))
        ok = ng = skip = 0
        for loc in pos.get('locationObjects', []):
            for info in (loc.get('trainInfoObjects') or []):
                w = str(info.get('wdfBlockNo'))
                mine = type_by_wdf.get(w)
                if mine is None:
                    skip += 1
                    continue
                if full[mine] == info.get('trainTypeJp') or \
                   (mine == '快' and info.get('trainTypeJp') == '快速特急') or \
                   (mine == '通' and info.get('trainTypeJp') == '通勤快急'):
                    ok += 1
                else:
                    ng += 1
                    print('MISMATCH wdf', w, 'table=', mine, 'feed=', info.get('trainTypeJp'))
        print(f'ground truth vs live feed: agree {ok}, disagree {ng}, branch/none {skip}')
    except FileNotFoundError:
        print('no /tmp/pos_now.json — skipped ground-truth check')


if __name__ == '__main__':
    main()
