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
// Display rules (zai-b2):
//   - No blank lines: stations and trains are packed into a flat line list.
//   - A train stopped at a station is wrapped in [ ].
//   - A stopped train waiting for a following train to pass it at that
//     station is wrapped in [[ ]] (judged from the official timetable:
//     startTimeList.json joined by wdfBlockNo; a station entry with a real
//     departure time = stop, "99:99" or absent = pass).
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
const URL_POS = 'https://www.keihan.co.jp/zaisen-up/trainPositionList.json';
const URL_TT = 'https://www.keihan.co.jp/zaisen-up/startTimeList.json';

export default {
  data: {
    build: 'zai-b2',
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
  onLoad() {
    this.probeLocation();
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
  // true = stops at the station, false = passes, null = timetable unknown
  stopsAt(wdf, stationName) {
    if (!this._tt) return null;
    const entry = this._tt[wdf];
    if (!entry) return null;
    const v = entry[stationName];
    if (v === undefined) return false;
    if (v === '99:99') return false;
    return true;
  },
  // Is stopped train A (at station S, row = firstRow of S) being held for a
  // following train that will pass S without stopping?
  isOvertakeWait(a, all) {
    if (!this._tt) return false;
    const sName = STATIONS[a.seg][0];
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
  trainLabel(t, all) {
    const info = t.info;
    const arrow = t.dir === '0' ? '↑' : '↓';
    let s = arrow + (info.trainTypeJp || '') + ' ' + (info.destStationNameJp || '') + '行';
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
    this.setData({ head: '在線 読込中...' });
    try {
      wx.request({
        url: URL_POS,
        method: 'GET',
        success: (res) => {
          try {
            const d = typeof res.data === 'string' ? JSON.parse(res.data) : res.data;
            this._trains = d.locationObjects || [];
            const t = String(d.fileCreatedTime || '');
            const hh = t.slice(8, 10), mm = t.slice(10, 12);
            this.setData({ head: '京阪 在線 ' + hh + ':' + mm + '現在' });
          } catch (e) {
            this.setData({ head: '在線 解析エラー' });
          }
          this.render();
          this.fetchTimetable();
        },
        fail: () => {
          this.setData({ head: '在線 取得失敗' });
          this.render();
        }
      });
    } catch (e) {
      this.setData({ head: '在線 取得不可' });
      this.render();
    }
  },
  // One-time background fetch of the timetable (for stop/pass judgement).
  // If it fails, display falls back to geometry-only brackets.
  fetchTimetable() {
    if (this._ttTried) return;
    this._ttTried = true;
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
              for (const s of (t.diaStationInfoObjects || [])) {
                m[s.stationNameJp] = s.stationDepTime;
              }
              map[String(t.wdfBlockNo)] = m;
            }
            this._tt = map;
          } catch (e) {
            this._tt = null;
          }
          this.render();
        },
        fail: () => { /* keep geometry-only display */ }
      });
    } catch (e) { /* keep geometry-only display */ }
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
      lines.push(s);
      const tr = bySeg[i] || [];
      const max = Math.min(tr.length, 3);
      for (let k = 0; k < max; k++) lines.push('  ' + this.trainLabel(tr[k], all));
      if (tr.length > 3) lines.push('  …');
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
    else if (event.code === 'Enter') { event.preventDefault(); this.fetchData(); }
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
