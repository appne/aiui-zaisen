# Train-type table generator (zai-b24)

zaisen's departure countdown gets its train types from this table,
generated from Keihan's **official all-trains timetable PDFs**
(京阪本線・中之島線・鴨東線「全列車時刻表」, linked from
https://www.keihan.co.jp/traffic/time-fare/time.html) — not from
inference. The live position feed's type wins while a train is
running; the table covers trains that have not started yet.

## Regenerate (after every diagram revision)

```sh
cd tools/type-table
for i in 1 2 3 4; do
  curl -O "https://www.keihan.co.jp/traffic/time-fare/pdf/time01-$i.pdf"
done
python3 parse_pdf.py      # PDFs -> pdf_runs.json (needs poppler's pdftotext)
curl -O https://www.keihan.co.jp/zaisen-up/startTimeList.json
python3 build_table.py startTimeList.json   # -> agent_table.json + validation
```

`build_table.py` prints the match rate against the live timetable
file and (if `/tmp/pos_now.json` exists) a ground-truth comparison
against the position feed. Expect ~99%+ resolution of main-line
services and zero type disagreements; investigate before shipping
if either slips.

Then splice `agent_table.json` into `pages/index/index.ink`
(replace the `TYPE_TABLE` value) and bump the build id.

## How matching works

- Signature = stop set only, over the 42 main-line stations:
  key `dir|dest|pattern`. Pass marks are unusable for matching —
  the timetable JSON omits minor pass stations that the PDF marks.
- Weekday and holiday diagrams get separate tables (W / H).
- A few stop patterns are shared by two types (the Liner's stop set
  equals the Limited Express's); those keys live in T and are
  disambiguated by the train's Kitahama departure time. (Kyobashi
  cannot be used: at two-line arrival/departure stations the PDF's
  extracted time runs one minute ahead of the timetable JSON.)
- Depot-terminating services are keyed by their last passenger
  stop; the PDF never names the Neyagawa signal yard.

The agent warns in its header (⚠種別表) when the table's coverage
of the timetable actually in use drops under 85% — that is the
signal to run this regeneration.
