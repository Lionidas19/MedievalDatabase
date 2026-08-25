# Medieval Price Database

A normalized SQLite database of English price records from the 1270s–80s
(sourced from Thorold Rogers' *History of Agriculture and Prices in England*,
Vol. 2), plus a Flutter web app for browsing, filtering, sorting and editing
it.

10,379 price entries covering 1270–1291, across 789 places, 66 counties and
633 specific goods and services.

## Layout

```
Copy of 1270s80sDatabase.xlsx    the source spreadsheet — the source of truth
tools/build_normalized_db.py     rebuilds the sqlite database from it
tools/CALCULATIONS.md            how the spreadsheet's formulas work
tools/dump_formulas.py           recovers those formulas from the workbook
tools/validate_calculations.py   checks our results against the spreadsheet's
app/                             the Flutter viewer/editor app
app/data/                        the database the app ships with
```

## What lives where

The spreadsheet is the source of truth and is never written to. The database
holds **recorded facts only** — years, places, quantities, measures, £/s/d.

Everything the spreadsheet derived by formula is deliberately *not* stored.
Total metric weight, price in pence, total sale, price per output unit: all of
it is computed at runtime by [`app/lib/services/pricing.dart`](app/lib/services/pricing.dart).

That is not tidiness for its own sake. The headline figure is "pence per X",
and X is chosen by the reader — kilograms, Tower pounds, bushels. A figure
whose unit is a question the reader asks cannot be a column in a table.

## Running the app

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) and
any modern browser.

```bash
cd app
flutter pub get
flutter run -d chrome
```

The database is bundled with the app and loads on startup — there is nothing
to pick and no folder to choose.

### From VS Code

1. Install the recommended extensions when prompted (Dart + Flutter), or
   install `Dart-Code.flutter` manually.
2. Open this repository's root folder in VS Code.
3. Run and Debug (`F5`) → pick **"Price Explorer (Chrome)"**.

### Saving your edits

Edits are saved automatically into private browser storage, so closing the tab
does not lose them and the next visit picks up where you left off. That storage
is private to one browser on one machine and invisible to your file manager,
so it is a safety net rather than a filing system.

**Download a copy** writes the database to your device as a new timestamped
`.sqlite` file — the only form you can keep, move or send to somebody else.
**Open file** loads one back in. Nothing is ever overwritten in place, and the
bundled default is one menu click away.

Entries can be added and deleted as well as edited.

## The two views

**Explorer** is the full table: search, filter by county, category and year,
sort by any column, and edit any entry. The `d / <unit>` column is computed
live against whichever output unit is selected in **Price per**.

**Quick lookup** answers a question in a sentence — *in [country], between
[years], [category] was valued at how many pence per [unit]* — and reports the
median, mean or mode across matching entries. It comes in two shapes, following
the researcher's own sketches: **Simple** asks the fewest questions it can,
**Detailed** adds region, locality, time of year and the full category chain.

### How units are handled

The source measures goods in different *kinds* of unit: some by weight, some by
volume, some by area, and some simply by the head or the dozen. Only weights
convert honestly into kilograms.

Each unit therefore carries a dimension, worked out from the researcher's own
conversion columns. Entries measured in a kind of unit that cannot reach the
one you asked for are left out of the average and reported, rather than
converted into a number that would look real and mean nothing. Asking for Food
per kilogram excludes 85 entries on that basis and drops the mean from 366
pence to 2.

These dimensions are **provisional** until the researcher confirms them — see
`review/`.

### Dates

The accounts are Julian, so a full date in them is seven days behind modern
reckoning; the editor shows both where a date exists, which is for about one
entry in seventy. Years are shown exactly as recorded. Medieval English years
often began on 25 March, so an entry dated early in the year may belong to the
following year by modern reckoning — that has deliberately **not** been
adjusted for, because which convention the source used is an open question.

## Questions for the researcher

`python tools/build_review_db.py` writes `review/1270s80sDatabase_review.sqlite`
— one small file listing everything that needs a human decision, openable in
any SQLite browser. It holds the unit dimensions to confirm, the time periods
to classify as months or feasts, and the place coordinates a map would need.
Columns named `your_*` are blank, for answers to be typed straight in.

## Regenerating the database from the spreadsheet

```bash
pip install openpyxl
python tools/build_normalized_db.py
```

This rebuilds `app/data/1270s80sDatabase_normalized.sqlite` from scratch,
normalizing the spreadsheet's flat sheets into dimension and junction tables
with UUID keys. It prints a report of anything in the source that could not be
resolved.

Note that measures and standards are **two separate vocabularies**: MEASURE 1/2/3
and the valuation measure resolve against the Measures sheet, while output X and
output Y resolve against Standards. They share only 3 names out of 586, and 69
of the 97 Standards entries appear nowhere in Measures. See
[tools/CALCULATIONS.md](tools/CALCULATIONS.md) for why this matters.

## Tests

```bash
cd app
flutter test
```

Runs on the Dart VM — no browser, no WASM. Alongside the unit tests,
`calculation_corpus_test.dart` replays all 10,379 entries through the
calculator and compares every derived value against what the spreadsheet
computed for the same entry.

To re-check against the database directly and regenerate that corpus:

```bash
python tools/validate_calculations.py
```
