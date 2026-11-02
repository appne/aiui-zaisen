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
// Display rules (zai-b23):
//   - Train position lines show the car count (live carsOfTrain)
//     right after the type for every train, e.g. ↑準急8 出町柳行,
//     so 4/7/8-car trains are all identifiable there.
//   - In the next-departures display, a 4-car train (from the live
//     feed's carsOfTrain; known only while the train is running) is
//     marked with a '.' right after its type kanji, e.g. a 4-car
//     sub-express to Yodoyabashi shows as 準.淀5. Short trains stop
//     at different platform positions, so they are worth spotting
//     at a glance. (zai-b20/b21 tried boxing a kanji with U+20DE
//     COMBINING ENCLOSING SQUARE; on the glasses it rendered as a
//     blank gap — combining enclosing marks do not render there.)
//   - Next-departure countdown: a train normally drops off 1 minute
//     after its (delay-adjusted) departure time, showing '-' during
//     that minute. But while fresh live position data says the train
//     has not departed this station yet (still approaching it or
//     stopped at it), it stays listed as '-' past that minute.
//   - No blank lines: stations and trains are packed into a flat line list.
//   - The visible window never starts on a train line: if it would, the
//     window is shifted up to that train's station line.
//   - A train stopped at a station is wrapped in [ ].
//   - A stopped train waiting for a following train to pass it at that
//     station is wrapped in [[ ]] (judged from the official timetable:
//     startTimeList.json joined by wdfBlockNo; a station entry with a real
//     departure time = stop, "99:99" or absent = pass). Only stations with
//     passing facilities can host an overtake (OVERTAKE below); e.g.
//     Kiyomizu-Gojo has no refuge platform, so no [[ ]] there.
// Display rules (zai-b24):
//   - Departure types no longer depend on the live position join
//     alone (startTimeList.json carries no type field, so a train
//     that had not started running showed no type). TYPE_TABLE below
//     is generated from Keihan's official all-trains timetable PDFs:
//     each timetable entry is matched by its stop pattern
//     (dir|dest|stop set over the 42 stations) and annotated with
//     __type when the timetable is fetched. The live feed's type
//     still wins when the train is running (it reflects same-day
//     changes); the table covers everything else, including trains
//     that have not departed yet.
//   - If the table's coverage of the fetched timetable (share of
//     main-line services it can type) drops under 85%, the header
//     gains a "⚠種別表" suffix: the timetable in use no longer
//     matches the table (a diagram revision, most likely) and the
//     table needs regenerating (tools/type-table/).
// zai-b25: the timetable cache is keyed to the service date. The
// timetable file is a per-day operations file (weekday and holiday
// diagrams carry different trains and number assignments), so a
// cache is only reused while the position file's date matches the
// date the cache was fetched for; a new service day refetches once.
// (The old week-long cache let a holiday file drive a Monday
// morning's countdowns on 2026-11-02: the train-number join failed
// across the board and every countdown item lost its type.)
// zai-b26: the "date" in that key is the SERVICE date with a 03:00
// boundary (see serviceDateStr): the last trains run past midnight
// (the timetable file spans 05:01-24:30, written as 24:xx), so
// between 00:00 and 03:00 the files still carry the previous
// service day even though their timestamps show the new calendar
// date. The same service date also drives the type table's
// weekday/holiday choice.
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
// Station coordinates (WGS84), aligned with STATIONS. Source: OpenStreetMap.
const COORDS = [
  [35.03027, 135.77268], [35.01867, 135.77224], [35.00902, 135.77233],
  [35.00323, 135.77193], [34.99561, 135.76845], [34.98907, 135.76791],
  [34.98126, 135.77002], [34.97349, 135.77004], [34.96889, 135.76926],
  [34.96436, 135.77010], [34.95681, 135.77021], [34.94803, 135.76902],
  [34.93891, 135.76540], [34.93281, 135.76437], [34.92672, 135.76017],
  [34.90651, 135.72118], [34.88463, 135.70007], [34.88175, 135.68404],
  [34.86195, 135.67536], [34.84385, 135.66559], [34.82917, 135.65395],
  [34.81614, 135.64872], [34.81140, 135.63939], [34.79787, 135.63020],
  [34.78476, 135.63099], [34.76407, 135.62084], [34.74735, 135.61083],
  [34.74301, 135.60286], [34.74007, 135.59166], [34.73806, 135.58291],
  [34.73734, 135.57566], [34.73530, 135.56520], [34.73071, 135.55992],
  [34.72761, 135.55727], [34.72431, 135.55501], [34.71938, 135.55163],
  [34.71250, 135.54693], [34.70712, 135.54326], [34.69699, 135.53217],
  [34.69033, 135.51642], [34.69150, 135.50758], [34.69250, 135.50129]
];
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
// Train-type table (zai-b24), generated from Keihan's official
// all-trains timetable PDFs (tools/type-table/build_table.py).
// W/H map "dir|dest|stopPattern" to a type abbreviation for the
// weekday / holiday diagrams; T disambiguates the few stop patterns
// shared by two types (Liner vs Limited Express, whose stop sets are
// identical) by Kitahama departure time ("H:MM", no leading zero).
const TYPE_TABLE = {"W":{"up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSS.......................................":"普","up|出町柳|SSSSSSSSSSSSSSSS..........................":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","up|出町柳|SSSSSS..S...S.SS..........................":"急","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS................":"急","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSSSSSSSSSS..":"普","up|樟葉|..................SSSSSSSSSSSSSS......SSSS":"区","up|出町柳|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSS.......................":"普","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","up|樟葉|..................SSSSSSSSS....S......SSSS":"準","up|香里園|........................SSSSSSSS......SS..":"区","up|萱島|..........................SSSSSSSSSSSSSSSS":"普","up|枚方市|.....................SSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSS......SSSS":"区","up|樟葉|..................S..S..SS.....S......SSSS":"快","up|萱島|..........................SSSSSS......SS..":"区","up|枚方市|.....................SSSSSSSSSSS......SSSS":"区","up|枚方市|.....................S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSSSSSSS......SS..":"区","up|出町柳|S.SS.S................................SSSS":"快","up|淀|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SSSSSSSSSSSSSS..........................":"普","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|淀|...............SSSSSSSSSSSS....S......SSSS":"準","up|枚方市|.....................SSSSSS....S......SS..":"準","up|枚方市|.....................SS.SS.....S......SSSS":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","up|枚方市|.....................S..SS.....S......SS..":"快","up|三条|..SS.S......S.S...S..S................SSSS":"特","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSSSSSSSSSSSS":"普","down|中之島|..........................SSSSSS......SS..":"区","down|中之島|..........................SSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSS......SSSS":"区","down|淀屋橋|...............SSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|..................SSSSSSSSSSSSSS......SSSS":"区","down|淀屋橋|..................S..SS.SS.....S......SSSS":"急","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀|SSSSSSSSSSSSSSSS..........................":"普","down|三条|SSS.......................................":"普","down|淀屋橋|.....................SSSSSS....S......SSSS":"準","down|淀屋橋|.....................S................SSSS":"特","down|淀屋橋|.....................SSSSSSSSSSSSSSSSSSSSS":"普","down|淀屋橋|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","down|樟葉|SSSSSSSSSSSSSSSSSSS.......................":"普","down|淀屋橋|...............SS.S..SS.SS.....S......SSSS":"急","down|淀屋橋|.....................S..SS............SSSS":"通","down|中之島|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS...........SSSS":"通","down|淀屋橋|S.SS.S......S.S...S..S..SS............SSSS":"通","down|中之島|.....................SSSSSSSSSSS......SS..":"区","down|淀屋橋|..................SSSSSSSSSSSSSSSSSSSSSSSS":"普","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS...........SSSS":"通","down|淀屋橋|.....................SSSSSS...........SSSS":"通","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","down|中之島|.....................SSSSSS...........SS..":"通","down|中之島|S.SS.S......S.S...S..S..SS............SS..":"通","down|中之島|..................SSSSSSSSS....S......SS..":"準","down|淀屋橋|.....................SSSSSSSSSSS......SSSS":"区","down|淀屋橋|..................S..S..SS.....S......SSSS":"快","down|淀屋橋|.....................S..SS.....S......SSSS":"快","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","down|淀屋橋|..................S..S................SSSS":"特","down|中之島|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|枚方市|SSSSSSSSSSSSSSSSSSSSSS....................":"普","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","down|樟葉|..SSSSSSSSSSSSSSSSS.......................":"普","down|枚方市|SSSSSS..S...S.S.S.S..S....................":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SS..":"準","down|中之島|..................S..S..SS.....S......SS..":"快","down|淀屋橋|S.SS.S................................SSSS":"快","down|樟葉|SSSSSS..S...S.S.S.S.......................":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀|SSSSSS..S...S.SS..........................":"急","down|淀|..SSSS..S...S.SS..........................":"急","down|守口市|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..........":"普","down|寝屋川市|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","down|寝屋川市|SSSSSS..S...S.S.S.S..SS.SS................":"急"},"H":{"up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSS.......................................":"普","up|出町柳|SSSSSSSSSSSSSSSS..........................":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","up|出町柳|SSSSSS..S...S.SS..........................":"急","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS................":"急","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|出町柳|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","up|萱島|..........................SSSSSS......SSSS":"区","up|萱島|..........................SSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|樟葉|..................S..SS.SS.....S......SSSS":"急","up|枚方市|.....................S..SS.....S......SSSS":"快","up|萱島|..........................SSSSSS......SS..":"区","up|出町柳|S.SS.S................................SSSS":"快","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","up|淀|...............SS.S..SS.SS.....S......SSSS":"急","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","up|樟葉|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","up|出町柳|SSSSSSSSSSSSSSSSSSS.......................":"普","up|樟葉|..................S..S..SS.....S......SSSS":"快","up|樟葉|..................SSSSSSSSS....S......SSSS":"準","up|樟葉|..................SSSSSSSSSSSSSS......SSSS":"区","up|出町柳|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","up|枚方市|.....................SSSSSS....S......SSSS":"準","up|淀|...............SSSSSSSSSSSS....S......SSSS":"準","up|萱島|..........................SSSSSSSSSSSSSSSS":"普","up|淀|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","up|三条|..SS.S......S.S...S..S................SSSS":"特","up|枚方市|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|..........................SSSSSSSSSSSSSSSS":"普","down|中之島|..........................SSSSSS......SS..":"区","down|中之島|..........................SSSSSSSSSSSSSS..":"普","down|淀屋橋|..................SSSSSSSSS....S......SSSS":"準","down|淀屋橋|..........................SSSSSS......SSSS":"区","down|淀屋橋|...............SSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|.....................SSSSSS....S......SSSS":"準","down|中之島|..................SSSSSSSSSSSSSSSSSSSSSS..":"普","down|中之島|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|三条|SSS.......................................":"普","down|淀屋橋|...............SS.S..SS.SS.....S......SSSS":"急","down|中之島|..SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|淀屋橋|SSSSSS..S...S.S.S.S..SS.SS.....S......SSSS":"急","down|淀屋橋|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS":"普","down|中之島|..................SSSSSSSSSSSSSS......SS..":"区","down|淀屋橋|..................S..S..SS.....S......SSSS":"快","down|中之島|...............SSSSSSSSSSSSSSSSSSSSSSSSS..":"普","down|中之島|..................S..S..SS.....S......SS..":"快","down|淀屋橋|S.SS.S......S.S...S..S..SS.....S......SSSS":"快","down|中之島|.....................SSSSSSSSSSSSSSSSSSS..":"普","down|淀|SSSSSSSSSSSSSSSS..........................":"普","down|中之島|.....................SSSSSSSSSSS......SS..":"区","down|淀屋橋|.....................S..SS.....S......SSSS":"快","down|淀|..SSSSSSSSSSSSSS..........................":"普","down|樟葉|..SSSSSSSSSSSSSSSSS.......................":"普","down|淀屋橋|..SSSSSSSSSSSSSSSSSSSSSSSSS....S......SSSS":"準","down|淀屋橋|S.SS.S................................SSSS":"快","down|淀|SSSSSS..S...S.SS..........................":"急","down|守口市|SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS..........":"普","down|寝屋川市|SSSSSSSSSSSSSSSSSSSSSSSSSS................":"普","down|寝屋川市|SSSSSS..S...S.S.S.S..SS.SS................":"急"},"T":{"down|淀屋橋|..................S..S..SS............SSSS":{"7:20":"ラ","7:31":"ラ","7:56":"通","8:12":"通","8:22":"ラ","8:32":"通","8:52":"ラ"},"down|淀屋橋|S.SS.S......S.S...S..S................SSSS":{"7:00":"特","7:13":"特","7:23":"特","7:37":"特","7:50":"特","8:02":"特","8:15":"特","8:28":"特","8:35":"特","8:41":"ラ","8:47":"特","8:55":"特","9:06":"特","9:15":"特","9:25":"特","9:34":"特","9:53":"特","10:11":"特","10:29":"特","10:42":"特","10:53":"特","11:05":"特","11:17":"特","11:29":"特","11:41":"特","11:53":"特","12:05":"特","12:17":"特","12:29":"特","12:41":"特","12:53":"特","13:05":"特","13:17":"特","13:29":"特","13:41":"特","13:53":"特","14:05":"特","14:17":"特","14:29":"特","14:41":"特","14:53":"特","15:05":"特","15:17":"特","15:29":"特","15:42":"特","15:54":"特","16:06":"特","16:18":"特","16:29":"特","16:41":"特","16:52":"特","17:04":"特","17:16":"特","17:29":"特","17:39":"特","17:53":"特","18:05":"特","18:17":"特","18:30":"特","18:54":"特","19:05":"ラ","19:07":"特","19:17":"特","19:29":"特","19:41":"特","19:51":"特","20:04":"特","20:14":"特","20:27":"特","20:40":"特","20:51":"特","21:03":"特","21:14":"特","21:27":"特","21:39":"特","21:51":"特","22:04":"特","22:18":"特","22:30":"特","22:43":"特","22:56":"特","23:14":"特","23:31":"特","7:01":"特","7:35":"特","7:48":"特","8:40":"特","8:51":"特","9:02":"特","9:16":"特","9:26":"特","9:39":"特","10:05":"特","10:16":"特","10:27":"特","10:40":"特","10:54":"特","13:28":"特","15:41":"特","15:53":"特","16:05":"特","16:17":"特","16:40":"特","16:51":"特","17:05":"特","17:28":"特","17:42":"特","18:04":"特","18:16":"特","18:41":"特","18:52":"特","19:06":"特","19:28":"特","19:54":"特","20:06":"特","20:17":"特","20:30":"特","20:53":"特","21:07":"特","21:21":"特","21:37":"特","21:52":"特","22:07":"特","22:23":"特","22:38":"特","22:54":"特","23:12":"特","23:30":"特","23:49":"特"},"down|淀屋橋|..SS.S......S.S...S..S................SSSS":{"6:29":"特","7:59":"ラ"},"up|出町柳|S.SS.S......S.S...S..S................SSSS":{"6:09":"特","6:39":"特","6:51":"特","7:01":"特","7:14":"特","7:22":"特","7:29":"特","7:39":"特","7:49":"特","7:58":"特","8:06":"特","8:21":"特","8:34":"特","8:48":"特","9:02":"特","9:24":"特","9:35":"特","9:46":"特","10:01":"特","10:12":"特","10:24":"特","10:37":"特","10:49":"特","11:01":"特","11:13":"特","11:25":"特","11:37":"特","11:49":"特","12:01":"特","12:13":"特","12:25":"特","12:37":"特","12:49":"特","13:01":"特","13:13":"特","13:25":"特","13:37":"特","13:49":"特","14:01":"特","14:13":"特","14:25":"特","14:37":"特","14:49":"特","15:01":"特","15:13":"特","15:25":"特","15:37":"特","15:49":"特","16:02":"特","16:13":"特","16:25":"特","16:37":"特","16:49":"特","17:02":"特","17:13":"特","17:24":"特","17:35":"特","17:37":"ラ","17:48":"特","17:59":"特","18:02":"ラ","18:15":"特","18:27":"特","18:36":"特","18:49":"特","19:01":"特","19:03":"ラ","19:14":"特","19:23":"特","19:26":"ラ","19:38":"特","19:51":"特","20:15":"特","20:27":"特","20:38":"特","21:03":"特","21:15":"特","21:27":"特","21:39":"特","21:51":"特","22:03":"特","22:16":"特","22:31":"特","22:52":"特","23:11":"特","6:16":"特","6:30":"特","6:46":"特","7:02":"特","7:13":"特","7:24":"特","7:36":"特","8:03":"特","8:14":"特","8:26":"特","8:38":"特","8:50":"特","9:03":"特","9:14":"特","9:25":"特","9:37":"特","9:49":"特","10:03":"特","10:14":"特","10:26":"特","10:38":"特","11:03":"特","16:01":"特","17:01":"特","17:14":"特","17:25":"特","17:38":"特","17:50":"特","18:01":"特","18:13":"特","18:25":"特","19:25":"特","19:37":"特","19:49":"特","20:16":"特","20:31":"特","21:02":"特","21:16":"特","21:31":"特","21:46":"特","22:01":"特"}},"meta":{"diagram":"2026-08-24","source":"keihan time01-1..4.pdf"}};
const STATION_IDX = {};
for (let si = 0; si < STATIONS.length; si++) STATION_IDX[STATIONS[si][0]] = si;

export default {
  data: {
    build: 'zai-b26',
    head: '在線 読込中...',
    foot: '',
    clock: '--:--',
    center: 4,
    L0: '', L1: '', L2: '', L3: '', L4: '', L5: '', L6: '', L7: '',
    L8: '', L9: '', L10: '', L11: '', L12: '', L13: '', L14: ''
  },
  _trains: [],
  _tt: null,
  _ttTried: false,
  _lastFetch: 0,
  _posAt: 0,
  _headBase: '在線 読込中...',
  _reloadUntil: 0,
  _reloadTimer: null,
  _clockTimer: null,
  _delay: {},
  _posByWdf: {},
  // The agent starts in focused mode (see the Enter toggle in onKeyUp).
  _focused: true,
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
    this.setData({ head: mark + this._headBase + (this._typeWarn ? ' ⚠種別表' : ''), clock: this.clockText() });
  },
  // Current time (HH:MM) for the footer's left end, from the same
  // anchored clock as the next-trains math.
  clockText() {
    const m = Math.floor(this.nowMinutes());
    const hh = Math.floor(m / 60) % 24;
    const mm = m % 60;
    return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm;
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
    const apply = (lat, lon) => {
      const idx = this.nearestStation(lat, lon);
      this.setData({ foot: 'loc OK ' + STATIONS[idx][0] + ' ' + lat.toFixed(3) + ',' + lon.toFixed(3) });
      // Centre on the nearest station, unless the user has
      // already scrolled away from the initial view.
      if (!this._userMoved && idx !== this.data.center) {
        this.setData({ center: idx });
        this.render();
      }
    };
    try {
      // The real glasses expose location only via navigator.geolocation
      // (verified on-device with the kensho probe, vrf-b2: wx.getLocation
      // and friends do not exist; geolocation returned a real fix).
      if (typeof navigator !== 'undefined' && navigator.geolocation &&
          typeof navigator.geolocation.getCurrentPosition === 'function') {
        let answered = false;
        navigator.geolocation.getCurrentPosition(
          (p) => {
            answered = true;
            if (p && p.coords) apply(p.coords.latitude, p.coords.longitude);
          },
          () => {
            if (!answered) { answered = true; this.setData({ foot: 'loc NG' }); }
          },
          { timeout: 8000 }
        );
        setTimeout(() => {
          if (!answered) { answered = true; this.setData({ foot: 'loc NG' }); }
        }, 9000);
        return;
      }
      if (typeof wx !== 'undefined' && wx.getLocation) {
        wx.getLocation({
          type: 'wgs84',
          success: (r) => apply(r.latitude, r.longitude),
          fail: () => { this.setData({ foot: 'loc NG' }); }
        });
      } else {
        this.setData({ foot: 'loc n/a' });
      }
    } catch (e) {
      this.setData({ foot: 'loc err' });
    }
  },
  nearestStation(lat, lon) {
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < COORDS.length; i++) {
      const dLa = lat - COORDS[i][0];
      const dLo = (lon - COORDS[i][1]) * 0.82;
      const d = dLa * dLa + dLo * dLo;
      if (d < bestD) { bestD = d; best = i; }
    }
    return best;
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
    // Car count goes right after the type (↑準急8 出町柳行).
    // When several trains share a line, drop the trailing 行 to save width.
    let s = arrow + (info.trainTypeJp || '') + String(info.carsOfTrain || '') + ' ' + (info.destStationNameJp || '') + (compact ? '' : '行');
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
              this._posDate = this.serviceDateStr(fc);
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
            this._posAt = Date.now();
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
  // Timetable (for stop/pass judgement) is cached on the device, keyed
  // to the service date (zai-b25): the file is regenerated per service
  // day and weekday/holiday diagrams differ, so the cached copy is
  // reused only when it was fetched for the same date as the current
  // position file. A new service day refetches once (the file is
  // ~4MB over the phone link, so per-launch refetching is not an
  // option). If storage or the fetch fails, display falls back to
  // geometry-only brackets.
  fetchTimetable() {
    if (this._ttTried) return;
    this._ttTried = true;
    try {
      if (typeof wx !== 'undefined' && wx.getStorage) {
        wx.getStorage({
          key: 'zaisen_tt3',
          success: (r) => {
            const saved = r && r.data;
            if (saved && saved.map && saved.forDate && this._posDate && saved.forDate === this._posDate) {
              this._tt = saved.map;
              this.updateTypeWarn();
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
            const dayType = this.ttDayType(d.fileCreatedTime);
            let covTotal = 0, covHit = 0;
            for (const t of (d.TrainInfo || [])) {
              const m = {};
              const dia = t.diaStationInfoObjects || [];
              for (const s of dia) {
                m[s.stationNameJp] = s.stationDepTime;
              }
              if (dia.length) m['__dest'] = dia[dia.length - 1].stationNameJp;
              const ann = this.typeKeyFor(m, dia);
              if (ann) {
                if (ann.nstop >= 2) covTotal++;
                const resolved = this.resolveType(ann.key, ann.kitahama, dayType);
                if (resolved) {
                  m['__type'] = resolved;
                  if (ann.nstop >= 2) covHit++;
                }
              }
              map[String(t.wdfBlockNo)] = m;
            }
            this._typeCov = covTotal ? covHit / covTotal : 1;
            this._tt = map;
            this.updateTypeWarn();
            this.saveTimetable(map, this.serviceDateStr(d.fileCreatedTime));
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
  // fcDate is the timetable file's own date; forDate is the position
  // file's date at fetch time — the cache is valid only for that
  // service date (zai-b25).
  saveTimetable(fullMap, fcDate) {
    try {
      if (typeof wx === 'undefined' || !wx.setStorage) return;
      const names = {};
      for (const pair of STATIONS) names[pair[0]] = 1;
      const pruned = {};
      for (const wdf in fullMap) {
        const src = fullMap[wdf];
        const m = {};
        for (const nm in src) {
          if (names[nm] || nm === '__dest' || nm === '__type') m[nm] = src[nm];
        }
        pruned[wdf] = m;
      }
      wx.setStorage({ key: 'zaisen_tt3', data: { at: Date.now(), fcDate: fcDate || '', forDate: this._posDate || '', map: pruned } });
    } catch (e) { /* cache is best-effort */ }
  },
  // (zai-b26) Service date (yyyymmdd) of a fileCreatedTime, with the
  // day boundary at 03:00 instead of midnight. Keihan's files describe
  // an operational day — the timetable spans 05:01-24:30, with
  // past-midnight times written as 24:xx — and in the small hours the
  // served files still carry the previous service day even though
  // their creation timestamp already shows the new calendar date.
  // Keying the timetable cache by calendar date would poison it when
  // the agent is opened between 00:00 and the content flip; with a
  // 03:00 boundary, 00:00-02:59 counts as the previous service day.
  serviceDateStr(fc) {
    const t = String(fc || '');
    const y = parseInt(t.slice(0, 4), 10), mo = parseInt(t.slice(4, 6), 10), dd = parseInt(t.slice(6, 8), 10);
    const hh = parseInt(t.slice(8, 10), 10);
    if (isNaN(y) || isNaN(mo) || isNaN(dd) || isNaN(hh) || hh >= 3) return t.slice(0, 8);
    const serial = (yy, mm, d) => {
      const y2 = mm <= 2 ? yy - 1 : yy;
      const era = Math.floor(y2 / 400);
      const yoe = y2 - era * 400;
      const mp = (mm + 9) % 12;
      const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
      return era * 146097 + yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    };
    const s = serial(y, mo, dd) - 1;
    const era = Math.floor(s / 146097);
    const doe = s - era * 146097;
    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    const y2 = yoe + era * 400;
    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    const mp = Math.floor((5 * doy + 2) / 153);
    const d2 = doy - Math.floor((153 * mp + 2) / 5) + 1;
    const m2 = mp < 10 ? mp + 3 : mp - 9;
    const y3 = m2 <= 2 ? y2 + 1 : y2;
    const p2 = (n) => String(n).padStart(2, '0');
    return '' + y3 + p2(m2) + p2(d2);
  },
  // (zai-b24) Day type ('weekday' | 'holiday') of a timetable file from
  // its fileCreatedTime (yyyymmdd...): Saturdays and Sundays use the
  // holiday diagram. (zai-b26) Judged on the SERVICE date (03:00
  // boundary, see serviceDateStr), so a file fetched in the small
  // hours is typed by the operational day it actually carries.
  // Day-of-week comes from a civil-date serial number anchored on
  // 2026-11-02 (a Monday) — no Date parsing involved.
  ttDayType(fc) {
    const t = this.serviceDateStr(fc);
    const y = parseInt(t.slice(0, 4), 10), mo = parseInt(t.slice(4, 6), 10), dd = parseInt(t.slice(6, 8), 10);
    if (isNaN(y) || isNaN(mo) || isNaN(dd)) return 'weekday';
    const serial = (yy, mm, d) => {
      const y2 = mm <= 2 ? yy - 1 : yy;
      const era = Math.floor(y2 / 400);
      const yoe = y2 - era * 400;
      const mp = (mm + 9) % 12;
      const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
      return era * 146097 + yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    };
    let dow = (serial(y, mo, dd) - serial(2026, 11, 2)) % 7;
    if (dow < 0) dow += 7;
    return dow >= 5 ? 'holiday' : 'weekday';
  },
  // (zai-b24) The TYPE_TABLE lookup key for one timetable entry:
  // "dir|dest|stopPattern" over the 42 main-line stations (stop set
  // only; '-' counts as a stop — it marks the run's boundary station).
  // Depot-terminating entries (dest = Neyagawa signal yard) are keyed
  // by their last passenger stop, as in the official PDF. Also returns
  // the Kitahama departure time (normalized to "H:MM") used by the T
  // disambiguation table, and the main-line stop count.
  typeKeyFor(m, dia) {
    let pat = '', nstop = 0, first = -1, last = -1, lastStop = '';
    for (let i = 0; i < STATIONS.length; i++) {
      const v = m[STATIONS[i][0]];
      if (v && v !== '99:99') { pat += 'S'; nstop++; } else pat += '.';
    }
    for (const s of dia) {
      const ix = STATION_IDX[s.stationNameJp];
      if (ix === undefined) continue;
      if (first < 0) first = ix;
      last = ix;
      if (s.stationDepTime && s.stationDepTime !== '99:99') lastStop = s.stationNameJp;
    }
    if (first < 0) return null;
    let dest = m['__dest'] || lastStop;
    if (dest === '寝屋川信号場') dest = lastStop;
    const dir = last < first ? 'up' : 'down';
    let kitahama = m['北浜'] || '';
    if (kitahama.indexOf(':') > 0) {
      const p = kitahama.split(':');
      kitahama = String(parseInt(p[0], 10)) + ':' + p[1];
    } else kitahama = '';
    return { key: dir + '|' + dest + '|' + pat, nstop, kitahama };
  },
  // (zai-b24) Resolve a type abbreviation: the file's own day-type
  // table first, then the Kitahama-time table for shared patterns,
  // then the other day type's table (covers national-holiday
  // weekdays, which are served by the holiday diagram).
  resolveType(key, kitahama, dayType) {
    if (!TYPE_TABLE) return '';
    const own = dayType === 'holiday' ? TYPE_TABLE.H : TYPE_TABLE.W;
    const other = dayType === 'holiday' ? TYPE_TABLE.W : TYPE_TABLE.H;
    if (own[key]) return own[key];
    const t = TYPE_TABLE.T[key];
    if (t && kitahama && t[kitahama]) return t[kitahama];
    return other[key] || '';
  },
  // (zai-b24) Keep the header's type-table warning in sync with the
  // coverage measured when the timetable was fetched (or recomputed
  // from the cached __type fields). Under 85% coverage the table no
  // longer matches the timetable in use — time to regenerate it.
  updateTypeWarn() {
    if (typeof this._typeCov !== 'number') {
      if (!this._tt) return;
      let total = 0, hit = 0;
      for (const wdf in this._tt) {
        const e = this._tt[wdf];
        let nstop = 0;
        for (let i = 0; i < STATIONS.length; i++) {
          const v = e[STATIONS[i][0]];
          if (v && v !== '99:99') nstop++;
        }
        if (nstop >= 2) { total++; if (e.__type) hit++; }
      }
      this._typeCov = total ? hit / total : 1;
    }
    this._typeWarn = this._typeCov < 0.85;
  },
  // Next departures at a station, e.g. "急淀10:準出5". Computed from
  // the timetable (scheduled departure + the train's current delay).
  // Type abbreviations come from the live position feed when the
  // train is running, else from the official-timetable type table
  // (zai-b24, the entry's __type).
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
      const pos = this._posByWdf[wdf];
      // Live position verdict for this station: has the train already
      // departed it? Down trains depart into this station's own block
      // sections toward Yodoyabashi (off > 0) or beyond; up trains
      // depart into the next block toward Demachiyanagi (seg < segIdx).
      let notDeparted = false;
      if (pos) {
        if (pos.dir === '1') {
          if (pos.seg > segIdx || (pos.seg === segIdx && pos.off > 0)) continue;
          notDeparted = true;
        } else {
          if (pos.seg < segIdx) continue;
          notDeparted = true;
        }
      }
      // Past the usual 1-minute grace, a train is kept (shown '-')
      // only while fresh position data says it has not departed this
      // station yet. The freshness bound (~2 reload cycles) keeps a
      // frozen position snapshot from holding an entry forever after
      // auto-reload ends or the feed stalls.
      if (diff < -1 &&
          !(notDeparted && Date.now() - this._posAt < RELOAD_MS * 2)) continue;
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
      if (!typeAb && c.entry.__type) typeAb = c.entry.__type;
      if (!dest) dest = c.entry['__dest'] || this.lastDestOf(c.entry);
      const destAb = DEST_AB[dest] || String(dest).slice(0, 1);
      // 4-car trains get a '.' after the type (see display rules).
      if (typeAb && pos && String(pos.info.carsOfTrain || '') === '4') typeAb += '.';
      // A train stays listed until 1 minute after its (delay-adjusted)
      // departure — or longer while live data says it has not departed
      // yet (see the hold rule above); whenever the remaining time is
      // past, it is shown as '-'.
      const mins = c.diff < 0 ? '-' : Math.floor(c.diff);
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
  // Focused mode: has this train already passed the focused station?
  // Down trains travel toward larger display indexes, up trains toward
  // smaller ones. A train inside the focused station's block counts as
  // "not passed" while it is at the station (down) or still approaching
  // it from below (up).
  notPassedFocus(t) {
    const f = this.data.center;
    if (t.dir === '1') return t.seg < f || (t.seg === f && t.off === 0);
    return t.seg > f || t.seg === f;
  },
  render() {
    const all = this.parsedTrains();
    const focusName = STATIONS[this.data.center][0];
    const bySeg = {};
    for (const t of all) {
      if (this._focused) {
        // Hide trains that do not stop at the focused station (the
        // timetable also excludes trains that never reach it), and
        // trains that have already passed it.
        if (this.stopsAt(t.wdf, focusName) === false) continue;
        if (!this.notPassedFocus(t)) continue;
      }
      if (!bySeg[t.seg]) bySeg[t.seg] = [];
      bySeg[t.seg].push(t);
    }
    const lines = [];
    let centerLine = 0;
    for (let i = 0; i < STATIONS.length; i++) {
      const name = STATIONS[i][0];
      const tr = bySeg[i] || [];
      // In focused mode, stations with no relevant train are hidden too
      // (the focused station itself always stays).
      if (this._focused && i !== this.data.center && tr.length === 0) continue;
      if (i === this.data.center) centerLine = lines.length;
      let s = (i === this.data.center ? '>' : ' ') + name;
      const nt = this.nextTrainsText(i);
      if (nt) s += ':' + nt;
      lines.push(s);
      // Combine the block's trains onto lines of up to 3 trains each;
      // any remaining trains continue on the next line.
      for (let s2 = 0; s2 < tr.length; s2 += 3) {
        const chunk = tr.slice(s2, s2 + 3);
        const multi = chunk.length > 1;
        const line = chunk.map(t => this.trainLabel(t, all, multi)).join(' ');
        // Indent train lines with one full-width space: leading half-width
        // spaces are ignored by the Ink text renderer (seen in previews).
        lines.push('　' + line);
      }
    }
    let start = centerLine - 5;
    if (start < 0) start = 0;
    if (start > lines.length - 14) start = Math.max(0, lines.length - 14);
    // If the window would start on a train line (indented with a
    // full-width space), back up to that train's station line so the
    // first visible line always identifies the station.
    while (start > 0 && lines[start].charAt(0) === '　') start--;
    const patch = {};
    for (let k = 0; k < 14; k++) patch['L' + k] = lines[start + k] || '';
    this.setData(patch);
  },
  move(d) {
    this._userMoved = true;
    let c = this.data.center + d;
    if (c < 0) c = 0;
    if (c > STATIONS.length - 1) c = STATIONS.length - 1;
    this.setData({ center: c });
    this.render();
  },
  onKeyUp(event) {
    if (event.code === 'ArrowUp') { event.preventDefault(); this.move(-1); }
    else if (event.code === 'ArrowDown') { event.preventDefault(); this.move(1); }
    else if (event.code === 'Enter') {
      event.preventDefault();
      // Click behaviour: while auto-reload is active, a click reloads,
      // resets the auto-reload window AND toggles the focused display
      // mode. While auto-reload is inactive, a click reloads and starts
      // auto-reload, leaving the mode unchanged.
      if (this.autoActive()) this._focused = !this._focused;
      this.startAutoReload();
      this.fetchData();
      this.render();
    }
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
    <text class="foot">{{ clock }} {{ foot }} {{ build }}</text>
  </view>
</page>

<style>
.container {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: flex-start;
  height: 100vh;
  padding: 6px;
}

.head {
  color: #40FF5E;
  font-size: 24px;
  line-height: 27px;
  margin-bottom: 3px;
}

.line {
  color: #40FF5E;
  font-size: 19px;
  line-height: 20px;
}

.foot {
  color: #40FF5E99;
  font-size: 15px;
  line-height: 17px;
  margin-top: 3px;
}
</style>
