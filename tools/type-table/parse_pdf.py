#!/usr/bin/env python3
"""Parse Keihan's official all-trains timetable PDFs (time01-1..4.pdf) into
per-run records: {book, direction, type, dest, cars, cells{station: S|x|.}}.

Uses `pdftotext -tsv` word boxes. Layout facts (verified against the PDFs):
- Each page is a time slice with the same header block repeated:
  rows labelled 列車種別 / 列車愛称 / 行先駅 / 両数・扉数・備考, then one row
  group per station (some stations have separate 着/発 sub-rows).
- A cell with an H:MM time = stop, 'レ' = pass, blank/arrow = not served.
"""
import json
import re
import subprocess
import sys
from collections import defaultdict

TYPES = ['快速特急', '快速急行', '区間急行', '通勤準急', '通勤快急', '深夜急行',
         '特急', '急行', '準急', '普通', 'ライナー']
TIME_RE = re.compile(r'^\d{1,2}:\d{2}$')
CARS_RE = re.compile(r'^(\d+)両')


def tsv_words(pdf, page):
    out = subprocess.run(
        ['pdftotext', '-tsv', '-f', str(page), '-l', str(page), pdf, '-'],
        capture_output=True, text=True, check=True).stdout
    words = []
    for line in out.splitlines()[1:]:
        f = line.split('\t')
        if len(f) < 12 or f[0] == '-1':
            continue
        try:
            left, top, width, height = float(f[6]), float(f[7]), float(f[8]), float(f[9])
        except ValueError:
            continue
        text = f[11].strip()
        if '#' in text:
            continue  # pdftotext -tsv structure artifact (###FLOW### etc.)
        if text:
            words.append({'x': left, 'y': top, 'w': width, 'h': height,
                          'xc': left + width / 2, 'yc': top + height / 2, 't': text})
    return words


def page_count(pdf):
    out = subprocess.run(['pdfinfo', pdf], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith('Pages:'):
            return int(line.split(':')[1])
    raise RuntimeError('no page count')


NAME_FIX = {'衹園四条': '祇園四条'}


def fix_name(n):
    return NAME_FIX.get(n, n)


def band(words, yc, tol):
    return [w for w in words if abs(w['yc'] - yc) <= tol]


def parse_page(pdf, page):
    words = tsv_words(pdf, page)
    if not words:
        return [], 'empty page'
    # Header labels live at the far left (x < 60).
    labels = {}
    for w in words:
        if w['x'] < 60 and w['t'] in ('列車種別', '行先駅'):
            labels[w['t']] = w
        if w['x'] < 60 and w['t'].startswith('両数'):
            labels['両数'] = w
    if '列車種別' not in labels or '行先駅' not in labels:
        return [], 'no header rows (cover/notes page?)'
    type_row = band(words, labels['列車種別']['yc'], 6)
    type_words = sorted([w for w in type_row if w['t'] in TYPES], key=lambda w: w['xc'])
    if not type_words:
        return [], 'no type tokens'
    cols = [w['xc'] for w in type_words]
    bounds = [0] + [(cols[i] + cols[i + 1]) / 2 for i in range(len(cols) - 1)] + [1e9]

    def col_of(xc):
        for i in range(len(cols)):
            if bounds[i] <= xc < bounds[i + 1]:
                return i
        return len(cols) - 1

    dest_row = band(words, labels['行先駅']['yc'], 6)
    dests = {}
    for w in dest_row:
        if w['x'] < 60:
            continue
        dests[col_of(w['xc'])] = fix_name(w['t'])
    cars = {}
    if '両数' in labels:
        for w in band(words, labels['両数']['yc'], 6):
            m = CARS_RE.match(w['t'])
            if m:
                cars[col_of(w['xc'])] = int(m.group(1))
    # Station rows: left labels below the header block, x < 60, not 着/発 alone.
    header_bottom = labels['行先駅']['yc'] + 12
    station_labels = sorted(
        [w for w in words if w['x'] < 60 and w['yc'] > header_bottom and w['t'] not in ('着', '発')],
        key=lambda w: w['yc'])
    # Group label words that share a line (multi-word names) and build row bands.
    rows = []  # (station_name, y_top, y_bottom)
    for w in station_labels:
        if rows and abs(w['yc'] - rows[-1][2]) <= 6:
            rows[-1][0] += w['t']
            continue
        rows.append([w['t'], w['yc'], w['yc']])
    # Row band boundaries: midpoints between successive label centres; a
    # station's band includes its 着/発 sub-rows (they sit between labels).
    runs = []
    for ci, tw in enumerate(type_words):
        runs.append({'type': tw['t'], 'dest': dests.get(ci), 'cars': cars.get(ci),
                     'cells': {}, 'times': {}})
    for ri, (name, lyc, _c) in enumerate(rows):
        y0 = lyc - 9 if ri == 0 else (rows[ri - 1][1] + lyc) / 2
        y1 = (lyc + rows[ri + 1][1]) / 2 if ri + 1 < len(rows) else 1e9
        cell_words = [w for w in words
                      if w['x'] >= 60 and y0 <= w['yc'] < y1]
        per_col = defaultdict(list)
        for w in sorted(cell_words, key=lambda w: (w['yc'], w['xc'])):
            per_col[col_of(w['xc'])].append(w)
        for ci in range(len(cols)):
            ws = per_col.get(ci, [])
            toks = [w['t'] for w in ws]
            times = [t for t in toks if TIME_RE.match(t)]
            if times:
                runs[ci]['cells'][fix_name(name)] = 'S'
                # 着/発 sub-rows: the later (lower) time is the departure.
                runs[ci]['times'][fix_name(name)] = times[-1]
            elif any(t == 'レ' for t in toks):
                runs[ci]['cells'][fix_name(name)] = 'x'
            else:
                runs[ci]['cells'][fix_name(name)] = '.'
    bad = [r for r in runs if not r['dest']]
    return runs, ('missing dest for %d cols' % len(bad)) if bad else ''


def main():
    books = {
        'time01-1.pdf': ('weekday', 'up'),
        'time01-2.pdf': ('weekday', 'down'),
        'time01-3.pdf': ('holiday', 'up'),
        'time01-4.pdf': ('holiday', 'down'),
    }
    all_runs = []
    for pdf, (day, direction) in books.items():
        n = page_count(pdf)
        for p in range(1, n + 1):
            runs, note = parse_page(pdf, p)
            for r in runs:
                r['day'] = day
                r['dir'] = direction
                r['book'] = pdf
                r['page'] = p
            if note:
                print(f'{pdf} p{p}: {note} (runs={len(runs)})', file=sys.stderr)
            all_runs.extend(runs)
        print(f'{pdf}: pages={n}', file=sys.stderr)
    print(f'total runs parsed: {len(all_runs)}', file=sys.stderr)
    json.dump(all_runs, open('pdf_runs.json', 'w'), ensure_ascii=False)
    from collections import Counter
    print(Counter((r['day'], r['dir'], r['type']) for r in all_runs))


if __name__ == '__main__':
    main()
