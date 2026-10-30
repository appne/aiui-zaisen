<script def>
{
  "navigationBarTitleText": "Zaisen"
}
</script>

<script setup>
// Keihan Main Line stations, display order = Demachiyanagi (top) to Yodoyabashi.
// Diagram grid: station KHn occupies rows firstRow..firstRow+2,
// firstRow = 1 + (42 - n) * 3  (verified against the official page HTML).
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
const URL = 'https://www.keihan.co.jp/zaisen-up/trainPositionList.json';

export default {
  data: {
    build: 'zai-b1',
    head: '在線 読込中...',
    foot: '',
    center: 4,
    L0: '', L1: '', L2: '', L3: '', L4: '', L5: '', L6: '', L7: '',
    L8: '', L9: '', L10: '', L11: '', L12: '', L13: '', L14: ''
  },
  _trains: [],
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
  segIndexOfRow(row) {
    // returns display index (0=Demachiyanagi) of the station whose block holds the row
    const n = 42 - Math.floor((row - 1) / 3);
    if (n < 1 || n > 42) return -1;
    return 42 - n;
  },
  fetchData() {
    const now = Date.now();
    if (now - this._lastFetch < 2000) return;
    this._lastFetch = now;
    this.setData({ head: '在線 読込中...' });
    try {
      wx.request({
        url: URL,
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
  trainsInSeg(segIdx) {
    const out = [];
    for (const o of this._trains) {
      const row = parseInt(o.locationRow, 10);
      if (isNaN(row) || row < 1 || row > 124) continue;
      if (this.segIndexOfRow(row) !== segIdx) continue;
      const info = (o.trainInfoObjects && o.trainInfoObjects[0]) || {};
      const dir = o.trainDirection === '0' ? '↑' : '↓';
      let s = dir + (info.trainTypeJp || '') + ' ' + (info.destStationNameJp || '') + '行';
      const dl = o.delay || '';
      if (dl && dl !== '±0' && dl !== '+0') s += ' ' + dl;
      out.push(s);
    }
    return out;
  },
  render() {
    const lines = [];
    const c = this.data.center;
    for (let i = c - 2; i <= c + 2; i++) {
      if (i < 0 || i >= STATIONS.length) { lines.push(''); continue; }
      const name = STATIONS[i][0];
      let s = (i === c ? '>' : ' ') + name;
      if (HOME[name]) s += ' *';
      lines.push(s);
      const tr = this.trainsInSeg(i);
      lines.push(tr.length ? '  ' + tr[0] : '');
      lines.push(tr.length > 1 ? '  ' + tr[1] + (tr.length > 2 ? ' …' : '') : '');
    }
    const patch = {};
    for (let k = 0; k < 15; k++) patch['L' + k] = lines[k] || '';
    this.setData(patch);
  },
  move(d) {
    let c = this.data.center + d;
    if (c < 2) c = 2;
    if (c > STATIONS.length - 3) c = STATIONS.length - 3;
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
