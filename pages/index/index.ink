<script def>
{
  "navigationBarTitleText": "Zaisen"
}
</script>

<script setup>
// Keihan Main Line stations, display order = Demachiyanagi (top) to Yodoyabashi.
// Diagram grid: station KHn occupies rows firstRow..firstRow+2,
// firstRow = 1 + (42 - n) * 3  (verified against the official page HTML).
// Row offset inside a station block (verified against live data 2026-10-31):
//   offset 0 = AT that station, offset 1/2 = in the section between that
//   station and the next station toward Yodoyabashi.
// Display rules (zai-b10):
//   - No blank lines: stations and trains are packed into a flat line list.
//   - A train stopped at a station is wrapped in [ ].
//   - A stopped train waiting for a following train to pass it at that
//     station is wrapped in [[ ]] (judged from the official timetable:
//     startTimeList.json joined by wdfBlockNo; a station entry with a real
//     departure time = stop, "99:99" or absent = pass). Only stations with
//     passing facilities can host an overtake (OVERTAKE below); e.g.
//     Kiyomizu-Gojo has no refuge platform, so no [[ ]] there.
const STATIONS = [
  ['出町柳', 42], ['神宮丸太町', 41], ['三条', 40], ['祇園四条', 39],
  ['清水五条', 38], ['七条', 37], ['東福寺', 36], ['鳥羽街道', 35],
  ['伏見稲荷', 34], ['龍谷大前深草', 33], ['藤森', 32], ['墨染', 31],
  ['丹波橋', 30], ['伏見桃山', 29], ['中書島', 28], ['淀', 27],
  ['石清水八幡宮', 26], ['橋本', 25], ['樟葉', 24], ['牧野', 23],
  ['御殿山', 22], ['枚方市', 21], ['枚方公園', 20], ['光善寺', 19],
  ['香里園', 18], ['寝屋川市', 17], ['萱島', 16], ['大和田', 15],
  ['古川橋', 14], ['門真市', 13], ['西三荘', 12], ['守口市', 11],
  ['土居', 10], ['滝井', 9], ['千林', 8], ['森小路', 7],
  ['関目', 6], ['野江', 5], ['京橋', 4], ['天満橋', 3],
  ['北浜', 2], ['淀屋橋', 1]
];
const HOME = { '清水五条': 1, '龍谷大前深草': 1 };
// Stations where a stopped train can be overtaken (refuge/passing
// facilities). 'up' = up direction only (Iwashimizu-Hachimangu).
const OVERTAKE = {
  '三条': 'both', '龍谷大前深草': 'both', '丹波橋': 'both', '淀': 'both',
  '樟葉': 'both', '枚方市': 'both', '香里園': 'both', '萱島': 'both',
  '守口市': 'both', '京橋': 'both', '石清水八幡宮': 'up'
};
const URL_POS = 'https://www.keihan.co.jp/zaisen-up/trainPositionList.json';
const URL_TT = 'https://www.keihan.co.jp/zaisen-up/startTimeList.json';
// Auto-reload runs every 90 seconds for 10 minutes. The official JSON is
// regenerated roughly once a minute (measured gaps of 60-71 s, not
// published), so 90 s stays clear of hammering it while missing little.
const RELOAD_MS = 90 * 1000;
const RELOAD_WINDOW_MS = 10 * 60 * 1000;
const RELOAD_MARKS = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩'];
// Abbreviations for the next-trains display on each station line,
// e.g. "清水五条 *:急淀10:準出5" (express for Yodoyabashi in 10 min,
// semi-express for Demachiyanagi in 5 min).
const TYPE_AB = {
  '普通': '普', '準急': '準', '急行': '急', '特急': '特',
  '快速急行': '快', '区間急行': '区', '通勤準急': '通',
  '通勤快急': '通', '快速特急': '快', 'ライナー': 'ラ'
};
const DEST_AB = {
  '淀屋橋': '淀', '出町柳': '出', '中之島': '中', '樟葉': '樟',
  '枚方市': '枚', '三条': '三', '丹波橋': '丹', '中書島': '書',
  '宇治': '宇', '私市': '私', '交野市': '交', '寝屋川市': '寝',
  '萱島': '萱', '守口市': '守', '京橋': '京', '天満橋': '天',
  '淀': '淀', '石清水八幡宮': '八', '伏見桃山': '桃', '墨染': '墨',
  '藤森': '藤', '龍谷大前深草': '龍', '伏見稲荷': '稲',
  '東福寺': '東', '七条': '七', '清水五条': '清', '祇園四条': '祇',
  '神宮丸太町': '神'
};

export default {
  data: {
    build: 'zai-b10',
    head: '在線 読込中...',
    foot: '',
    center: 4,
    L0: '', L1: '', L2: '', L3: '', L4: '', L5: '', L6: '', L7: '',
    L8: '', L9: '', L10: '', L11: '', L12: '', L13: '', L14: ''
  },
  _trains: [],
  _tt: null,
  _ttTried: false,
  _lastFetch: 0,
  _headBase: '在線 読込中...',
  _reloadUntil: 0,
  _reloadTimer: null,
  _clockTimer: null,
  _delay: {},
  _posByWdf: {},
  _nowMin: -1,
  _elapsedSec: 0,
  onLoad() {
    this.probeLocation();
    this.startAutoReload();
    this.fetchData();
    // Recompute the "minutes left" displays every 10 seconds (no fetch).
    // The tick count also advances the anchored display clock.
    if (typeof setInterval !== 'undefined') {
      this._clockTimer = setInterval(() => {
        this._elapsedSec += 10;
        this.applyHead();
        this.render();
      }, 10000);
    }
  },
  onUnload() {
    this.stopAutoReload();
    if (this._clockTimer != null && typeof clearInterval !== 'undefined') {
      clearInterval(this._clockTimer);
    }
    this._clockTimer = null;
  },
  // Auto-reload: refetch positions every 90 seconds for 10 minutes after
  // the page is shown (or after Enter is pressed). While active, the
  // header carries a circled-number countdown of the remaining reload
  // slots (e.g. ⑦ at the start with a 90-second interval).
  autoActive() {
    return this._reloadUntil && Date.now() < this._reloadUntil;
  },
  applyHead() {
    let mark = '';
    if (this.autoActive()) {
      let n = Math.ceil((this._reloadUntil - Date.now()) / RELOAD_MS);
      if (n < 1) n = 1;
      if (n > 10) n = 10;
      mark = RELOAD_MARKS[n - 1];
    }
    this.setData({ head: mark + this._headBase });
  },
  startAutoReload() {
    this._reloadUntil = Date.now() + RELOAD_WINDOW_MS;
    if (this._reloadTimer == null && typeof setInterval !== 'undefined') {
      this._reloadTimer = setInterval(() => this.onReloadTick(), RELOAD_MS);
    }
    this.applyHead();
  },
  stopAutoReload() {
    if (this._reloadTimer != null && typeof clearInterval !== 'undefined') {
      clearInterval(this._reloadTimer);
    }
    this._reloadTimer = null;
  },
  onReloadTick() {
    if (!this.autoActive()) {
      this.stopAutoReload();
      this.applyHead();
      return;
    }
    this.fetchData();
  },
  probeLocation() {
    try {
      if (typeof wx !== 'undefined' && wx.getLocation) {
        wx.getLocation({
          type: 'wgs84',
          success: (r) => {
            this.setData({ foot: 'loc OK ' + r.latitude.toFixed(3) + ',' + r.longitude.toFixed(3) });
          },
          fail: () => { this.setData({ foot: 'loc NG' }); }
        });
      } else {
        this.setData({ foot: 'loc n/a' });
      }
    } catch (e) {
      this.setData({ foot: 'loc err' });
    }
  },
  parseTrain(o) {
    const row = parseInt(o.locationRow, 10);
    if (isNaN(row) || row < 1 || row > 124) return null;
    const n = 42 - Math.floor((row - 1) / 3);
    if (n < 1 || n > 42) return null;
    const info = (o.trainInfoObjects && o.trainInfoObjects[0]) || {};
    return {
      row: row,
      off: (row - 1) % 3,
      seg: 42 - n,
      dir: o.trainDirection === '0' ? '0' : '1',
      wdf: String(info.wdfBlockNo || ''),
      info: info,
      delay: o.delay || ''
    };
  },
  parsedTrains() {
    const out = [];
    for (const o of this._trains) {
      const t = this.parseTrain(o);
      if (t) out.push(t);
    }
    out.sort((a, b) => a.row - b.row);
    return out;
  },
  // true = stops at the station, false = passes, null = timetable unknown.
  // Values are either raw departure times ('99:99' = pass) from a fresh
  // fetch, or the pruned cache form ('1' = stop, '0' = pass).
  stopsAt(wdf, stationName) {
    if (!this._tt) return null;
    const entry = this._tt[wdf];
    if (!entry) return null;
    const v = entry[stationName];
    if (v === undefined) return false;
    if (v === '99:99' || v === '0') return false;
    return true;
  },
  // Is stopped train A (at station S, row = firstRow of S) being held for a
  // following train that will pass S without stopping?
  isOvertakeWait(a, all) {
    if (!this._tt) return false;
    const sName = STATIONS[a.seg][0];
    const cap = OVERTAKE[sName];
    if (!cap) return false;
    if (cap === 'up' && a.dir !== '0') return false;
    if (this.stopsAt(a.wdf, sName) !== true) return false;
    // rows of the section immediately behind S (between the previous
    // station and S): down trains come from smaller rows, up from larger.
    let behind;
    if (a.dir === '1') behind = { lo: a.row - 2, hi: a.row - 1 };
    else behind = { lo: a.row + 4, hi: a.row + 5 };
    for (const b of all) {
      if (b === a || b.dir !== a.dir) continue;
      if (b.row < behind.lo || b.row > behind.hi) continue;
      if (this.stopsAt(b.wdf, sName) === false) return true;
    }
    return false;
  },
  trainLabel(t, all, compact) {
    const info = t.info;
    const arrow = t.dir === '0' ? '↑' : '↓';
    // When several trains share a line, drop the trailing 行 to save width.
    let s = arrow + (info.trainTypeJp || '') + ' ' + (info.destStationNameJp || '') + (compact ? '' : '行');
    if (t.delay && t.delay !== '±0' && t.delay !== '+0') s += ' ' + t.delay;
    if (t.off === 0) {
      const sName = STATIONS[t.seg][0];
      if (this.stopsAt(t.wdf, sName) === false) return s; // passing through
      if (this.isOvertakeWait(t, all)) return '[[' + s + ']]';
      return '[' + s + ']';
    }
    return s;
  },
  fetchData() {
    const now = Date.now();
    if (now - this._lastFetch < 2000) return;
    this._lastFetch = now;
    this._headBase = '在線 読込中...';
    this.applyHead();
    try {
      wx.request({
        url: URL_POS,
        method: 'GET',
        success: (res) => {
          try {
            const d = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
            this._trains = d.locationObjects || [];
            // Anchor the display clock to the position file's server-side
            // creation time (JST wall time). Some preview runtimes have a
            // broken Date implementation that produced absurd minute
            // counts, so the minute math below uses NO Date at all: just
            // this wall-clock anchor plus the 10-second tick count.
            if (d.fileCreatedTime) {
              const fc = String(d.fileCreatedTime);
              const hh = parseInt(fc.slice(8, 10), 10);
              const mi = parseInt(fc.slice(10, 12), 10);
              const ss = parseInt(fc.slice(12, 14), 10);
              if (!isNaN(hh) && !isNaN(mi)) {
                this._nowMin = hh * 60 + mi + (isNaN(ss) ? 0 : ss) / 60;
                this._elapsedSec = 0;
              }
            }
            this._delay = {};
            this._posByWdf = {};
            for (const t of this.parsedTrains()) {
              this._posByWdf[t.wdf] = t;
              let dm = parseInt(t.info.delayMinutes, 10);
              if (isNaN(dm)) dm = parseInt(String(t.delay).replace('+', ''), 10);
              this._delay[t.wdf] = isNaN(dm) ? 0 : dm;
            }
            const t = String(d.fileCreatedTime || '');
            const hh = t.slice(8, 10), mm = t.slice(10, 12);
            this._headBase = '京阪 在線 ' + hh + ':' + mm + '現在';
          } catch (e) {
            // Keihan shows a maintenance page (HTML) during maintenance,
            // which lands here as a JSON parse failure.
            this._headBase = '在線 メンテナンス中かも';
          }
          this.applyHead();
          this.render();
          this.fetchTimetable();
        },
        fail: () => {
          this._headBase = '在線 取得失敗';
          this.applyHead();
          this.render();
        }
      });
    } catch (e) {
      this._headBase = '在線 取得不可';
      this.applyHead();
      this.render();
    }
  },
  // Timetable (for stop/pass judgement) is cached on the device: stopping
  // patterns barely change, so it is re-fetched only when the cached copy
  // is a week old or more. If storage or the fetch fails, display falls
  // back to geometry-only brackets.
  fetchTimetable() {
    if (this._ttTried) return;
    this._ttTried = true;
    const WEEK = 7 * 24 * 3600 * 1000;
    try {
      if (typeof wx !== 'undefined' && wx.getStorage) {
        wx.getStorage({
          key: 'zaisen_tt2',
          success: (r) => {
            const saved = r && r.data;
            if (saved && saved.map && saved.at && (Date.now() - saved.at) < WEEK) {
              this._tt = saved.map;
              this.render();
            } else {
              this.fetchTimetableRemote();
            }
          },
          fail: () => { this.fetchTimetableRemote(); }
        });
        return;
      }
    } catch (e) { /* fall through to remote fetch */ }
    this.fetchTimetableRemote();
  },
  fetchTimetableRemote() {
    try {
      wx.request({
        url: URL_TT,
        method: 'GET',
        success: (res) => {
          try {
            const d = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
            const map = {};
            for (const t of (d.TrainInfo || [])) {
              const m = {};
              const dia = t.diaStationInfoObjects || [];
              for (const s of dia) {
                m[s.stationNameJp] = s.stationDepTime;
              }
              if (dia.length) m['__dest'] = dia[dia.length - 1].stationNameJp;
              map[String(t.wdfBlockNo)] = m;
            }
            this._tt = map;
            this.saveTimetable(map);
          } catch (e) {
            this._tt = null;
          }
          this.render();
        },
        fail: () => { /* keep geometry-only display */ }
      });
    } catch (e) { /* keep geometry-only display */ }
  },
  // Save a pruned copy: main-line stations only, keeping the raw
  // departure-time strings (needed for the next-trains display).
  saveTimetable(fullMap) {
    try {
      if (typeof wx === 'undefined' || !wx.setStorage) return;
      const names = {};
      for (const pair of STATIONS) names[pair[0]] = 1;
      const pruned = {};
      for (const wdf in fullMap) {
        const src = fullMap[wdf];
        const m = {};
        for (const nm in src) {
          if (names[nm] || nm === '__dest') m[nm] = src[nm];
        }
        pruned[wdf] = m;
      }
      wx.setStorage({ key: 'zaisen_tt2', data: { at: Date.now(), map: pruned } });
    } catch (e) { /* cache is best-effort */ }
  },
  // Next two departures at a station, e.g. "急淀10:準出5". Computed from
  // the timetable (scheduled departure + the train's current delay).
  // Type abbreviations come from the live position feed, so a train that
  // has not started running yet shows its destination and minutes only.
  // Origin stations have no departure time in the data ("-"), so termini
  // starting there show nothing.
  // Current time-of-day in minutes (float) for the next-trains math:
  // the server-anchored wall clock when available, else the local clock.
  // Deliberately avoids epoch/Date arithmetic (see _nowMin note).
  nowMinutes() {
    if (this._nowMin >= 0) return this._nowMin + this._elapsedSec / 60;
    const d = new Date();
    return d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;
  },
  nextTrainsText(segIdx) {
    if (!this._tt) return '';
    const sName = STATIONS[segIdx][0];
    const nowMin = this.nowMinutes();
    const cands = [];
    for (const wdf in this._tt) {
      const entry = this._tt[wdf];
      const dep = entry[sName];
      if (!dep || dep === '99:99' || dep === '-') continue;
      // A train whose destination IS this station only arrives here;
      // its listed time is not a departure.
      const destName = entry['__dest'] || this.lastDestOf(entry);
      if (destName === sName) continue;
      const parts = dep.split(':');
      if (parts.length !== 2) continue;
      let diff = (parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10))
        + (this._delay[wdf] || 0) - nowMin;
      if (diff < -30) diff += 1440;
      else if (diff > 720) diff -= 1440;
      if (diff < -0.5) continue;
      const pos = this._posByWdf[wdf];
      if (pos) {
        if (pos.dir === '1' && (pos.seg > segIdx || (pos.seg === segIdx && pos.off > 0))) continue;
        if (pos.dir === '0' && pos.seg < segIdx) continue;
      }
      cands.push({ diff: diff, wdf: wdf, entry: entry });
    }
    cands.sort((a, b) => a.diff - b.diff);
    const items = [];
    for (let k = 0; k < Math.min(4, cands.length); k++) {
      const c = cands[k];
      let dest = '';
      const pos = this._posByWdf[c.wdf];
      if (pos && pos.info.destStationNameJp) dest = pos.info.destStationNameJp;
      let typeAb = '';
      if (pos && pos.info.trainTypeJp) {
        typeAb = TYPE_AB[pos.info.trainTypeJp] || String(pos.info.trainTypeJp).slice(0, 1);
      }
      if (!dest) dest = c.entry['__dest'] || this.lastDestOf(c.entry);
      const destAb = DEST_AB[dest] || String(dest).slice(0, 1);
      let mins = Math.floor(c.diff);
      if (mins < 0) mins = 0;
      items.push(typeAb + destAb + mins);
    }
    return items.join(':');
  },
  lastDestOf(entry) {
    // dia entries are in travel order per train; the destination is the
    // entry whose station is farthest along the itinerary. The timetable
    // object preserves insertion order, so take the last station name.
    let last = '';
    for (const nm in entry) {
      if (nm.indexOf('__') === 0) continue;
      last = nm;
    }
    return last;
  },
  render() {
    const all = this.parsedTrains();
    const bySeg = {};
    for (const t of all) {
      if (!bySeg[t.seg]) bySeg[t.seg] = [];
      bySeg[t.seg].push(t);
    }
    const lines = [];
    let centerLine = 0;
    for (let i = 0; i < STATIONS.length; i++) {
      const name = STATIONS[i][0];
      if (i === this.data.center) centerLine = lines.length;
      let s = (i === this.data.center ? '>' : ' ') + name;
      if (HOME[name]) s += ' *';
      const nt = this.nextTrainsText(i);
      if (nt) s += ':' + nt;
      lines.push(s);
      const tr = bySeg[i] || [];
      if (tr.length) {
        // Combine the block's trains onto one line, up to 3 trains.
        const shown = tr.slice(0, 3);
        const multi = shown.length > 1;
        let line = shown.map(t => this.trainLabel(t, all, multi)).join(' ');
        if (tr.length > 3) line += ' …';
        lines.push(multi ? line : '  ' + line);
      }
    }
    let start = centerLine - 5;
    if (start < 0) start = 0;
    if (start > lines.length - 15) start = Math.max(0, lines.length - 15);
    const patch = {};
    for (let k = 0; k < 15; k++) patch['L' + k] = lines[start + k] || '';
    this.setData(patch);
  },
  move(d) {
    let c = this.data.center + d;
    if (c < 0) c = 0;
    if (c > STATIONS.length - 1) c = STATIONS.length - 1;
    this.setData({ center: c });
    this.render();
  },
  onKeyUp(event) {
    if (event.code === 'ArrowUp') { event.preventDefault(); this.move(-1); }
    else if (event.code === 'ArrowDown') { event.preventDefault(); this.move(1); }
    else if (event.code === 'Enter') { event.preventDefault(); this.startAutoReload(); this.fetchData(); }
  }
}
</script>

<page>
  <view class="container">
    <text class="head">{{ head }}</text>
    <text class="line">{{ L0 }}</text>
    <text class="line">{{ L1 }}</text>
    <text class="line">{{ L2 }}</text>
    <text class="line">{{ L3 }}</text>
    <text class="line">{{ L4 }}</text>
    <text class="line">{{ L5 }}</text>
    <text class="line">{{ L6 }}</text>
    <text class="line">{{ L7 }}</text>
    <text class="line">{{ L8 }}</text>
    <text class="line">{{ L9 }}</text>
    <text class="line">{{ L10 }}</text>
    <text class="line">{{ L11 }}</text>
    <text class="line">{{ L12 }}</text>
    <text class="line">{{ L13 }}</text>
    <text class="line">{{ L14 }}</text>
    <text class="foot">{{ foot }} {{ build }}</text>
  </view>
</page>

<style>
.container {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: flex-start;
  height: 100vh;
  padding: 10px;
}

.head {
  color: #40FF5E;
  font-size: 26px;
  line-height: 30px;
  margin-bottom: 6px;
}

.line {
  color: #40FF5E;
  font-size: 20px;
  line-height: 24px;
}

.foot {
  color: #40FF5E99;
  font-size: 16px;
  line-height: 20px;
  margin-top: 6px;
}
</style>
