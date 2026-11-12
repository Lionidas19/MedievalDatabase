# CLAUDE.md — MedievalDatabase

The engineering account of this project: why things are the way they are, and
which of them are load-bearing. Tracked, and meant to be read — by anyone
picking the code up, and by Claude. What a *reader* of the app needs is in
[README.md](README.md); how the source spreadsheet's formulas work is in
[tools/CALCULATIONS.md](tools/CALCULATIONS.md).

Nothing private belongs in here. The commissioning brief, the source
spreadsheet and the researcher's own files are not in this repository, and
should not be quoted into it — describe the requirement, not the document.

## What this is

A normalized SQLite database of English price records from Thorold Rogers'
*History of Agriculture and Prices in England, Vol. 2*, covering **1270–1291**,
plus a Flutter web app for browsing, filtering, sorting and editing it.

Two halves:

1. **Python ETL** (`tools/`) — *imported* the SQLite from the source
   spreadsheet, once. See "The database is the source of truth" below: it is
   no longer safe to rerun.
2. **Flutter web app** (`app/`) — browses/edits it, entirely client-side.

The audience is a **historian, not a developer**. Wording in the UI matters as
much as behaviour, and the codebase's comment style reflects that: comments
explain *why a historical decision was made*, not what the code does. Match it.

## What the app has to do

From the commissioning brief, which is not in this repository. Two things in
it drive the whole UI:

### Three audiences → three detail levels

| Audience | `DetailLevel` |
|---|---|
| Lay people wanting "what did glass cost in 1275", answered with averages over their filters | `basics` |
| Worldbuilders and academics wanting the specific entries and sources, and control over the output unit | `detailed` |
| Advanced researchers who know more about a record than the database does and have come to correct it | `everything` |

One reader is all three on different days, so this is a shared setting in
`state/view_preferences.dart`, applied by the table, the cards, the editor and
Quick lookup alike — not a mode chosen once.

### Asked for, and not finished

- ~~**`UKP 2026` conversion.**~~ **Done.** The
  researcher's current workbook carries a filled Currency tab, and
  `currency_factors` now holds a factor for all 250 years from 1270 to 1519.
  `currency_rebasing` was 2017 → 2026 at ×1.3444 until migration 3, which
  sets it to 2017 → 2017 at ×1: the researcher decided to report in 2017
  pounds rather than keep chasing inflation. The row stays, so the year the
  columns are labelled with is still read from the database.

  **How it is modelled, and why.** The tab gives `UKP 2017` and `UKP 2026` per
  year. Only the 2017 column is stored, as `base_pounds_per_penny`; the 2026
  column is the same figure times a single constant, so storing it too would
  be storing a derived value and would mean editing 250 rows every time
  inflation moves. `tools/currency.py` reads a `UKP <year>` pair as base and
  target and derives the multiplier from the ratio, **checking it is the same
  on every row** rather than trusting the first. It also checks the tab's
  `Pence` column is 1 throughout, because a 12 there would silently turn every
  factor into pounds per shilling.

  **Built, as of v0.0.3.** `pricing.dart` takes one combined factor and
  returns all three figures; see "Modern money is computed, never stored".
  They are computed rather than stored, because the third depends on the
  reader's chosen unit, even though the workbook now carries such a column.

  **Never invent the factors.** Retail prices, earnings and share of GDP give
  answers an order of magnitude apart. That choice was the researcher's, and
  they made it: the figures come from the National Archives converter.
- **A map to pick places from.** Blocked on the missing coordinates; see `review/`.
- **Splitting `Food`** into two columns, as asked, and splitting the month
  column, which mixes months, seasons and feast days.

### One requirement the data contradicts

The brief describes the Standards tab as not referenced by the database. The
recovered formulas say otherwise: `output X` and `CHOSEN OUTPUT Y` resolve
against Standards, and 69 of its 97 entries appear nowhere in Measures. See
`tools/CALCULATIONS.md`. The empirical finding wins — but raise it rather than
quietly overriding a requirement, because the researcher may know something
about the sheet's history that the formulas do not show.

## Layout

```
app/data/*.sqlite                THE source of truth (see below)
tools/build_normalized_db.py     the original import; refuses to rerun over logged work
tools/check_incoming_db.py       reviews a database sent back, before committing it
tools/migrate.py                 numbered schema changes, applied to whichever file arrives
tools/CALCULATIONS.md            how the spreadsheet's formulas work (recovered)
tools/dump_formulas.py           recovers those formulas from the workbook
tools/dimensions.py              works out what kind of thing each unit measures
tools/currency.py                reads the (empty) Currency sheet; self-tests
tools/validate_calculations.py   checks our results against the spreadsheet's
tools/build_review_db.py         builds the questions file for the researcher
review/*.sqlite                  questions awaiting the researcher's answers
docs/                            screenshots for the README
```

## The base SQLite

`app/data/1270s80sDatabase_normalized.sqlite` (~9.4 MB), UUID `TEXT` primary
keys throughout.

| Group | Tables | Rows |
|---|---|---|
| Facts | `price_entries` | 7,501 (7,435 with both an item and a price) |
| Place | `counties` / `places` | 66 / 789 |
| Taxonomy | `categories` → `subcategories` → `specifics` | 19 / 79 / 609 |
| Units | `measures` / `standards` | 576 / 99 |
| Conversions | `measure_conversions` / `standard_conversions` | 3,006 / 3,991 |
| Local variance | `place_measure_overrides` | 390 |
| Small dims | `time_periods` 67, `countries` 1, `sources` 1, `coin_types` 0, `multiplier_measures` 1 | |
| Modern money | `currency_factors` / `currency_rebasing` | 250 / 1, both filled |
| Test oracle | `excel_cached_calculations` | 7,501 |

### Three invariants that define the schema

1. **Recorded facts only.** Years, places, quantities, measures, £/s/d. Every
   value the spreadsheet *derived* by formula (total grams, price in pence,
   total sale, pence per output unit) is deliberately **not stored** — it is
   computed at runtime by `app/lib/services/pricing.dart`. Reason: the headline
   figure is "pence per X" and X is the reader's choice, so it cannot be a
   column. **Do not add derived columns to the database.**
2. **Measures and standards are two disjoint vocabularies.** `MEASURE 1/2/3` and
   the valuation measure resolve against `measures`; `output X` / `output Y`
   resolve against `standards`. They share 3 names out of ~586. An earlier build
   merged them into one `units` table — that was the bug this branch fixed. See
   `tools/CALCULATIONS.md`.
3. **`excel_cached_calculations` is a test oracle, not app data.** It holds what
   Google Sheets last computed, so the Dart reimplementation can be validated
   row by row. The app must never read it for display.

### Deliberate holes (do not "fix" them)

- `places.latitude/longitude` are empty — identifying `Souendon` or `Wyllindone`
  is research, not programming. The columns exist so answers have somewhere to go.
- `coin_types` is empty; the source records none.
- ~~`currency_factors` is empty~~ — filled as of the Leo2026v workbook. The
  remaining gap is the UI, not the data.
- `measures.dimension` / `standards.dimension` are **mostly read, not
  guessed**: 455 read from the researcher's own conversion columns, 45 guessed
  from the unit's name, 76 unknown. Only **64 entries** (0.9%) have a
  valuation measure that is guessed or unknown.

  It was 42% until the column names were checked. `dimensions.py` matches
  conversion-column headings exactly, and the current workbook renamed
  `Heads/Entities` to `Heads Entities` and split `Gallons` and `Quart` into
  ale and wine measures. Every countable unit silently lost its one piece of
  evidence. **A renamed column does not fail, it stops classifying**, which is
  the same failure mode as the Data column map and is why that one now has an
  assertion. If a re-import ever moves `read` downwards, look here first.
- Years are **not** adjusted for the year start. These prices come off
  account rolls, whose year ran from **Michaelmas (29 September)** —
  corrected by the researcher from 25 March, which is a different convention:
  Lady Day is how a document was *dated*, Michaelmas is where the *accounting*
  year turned. Which one Rogers himself followed is still open.
  `calendar_test.dart` pins the wording so the wrong date cannot creep back.
- Rows 7801+ of the Data sheet are unfilled template rows, skipped on import.
- **Entries 7502–7800 are not imported.** They carried a year of 1286 and
  nothing else at all: no place, no item, no price, only the dropdown
  defaults the sheet stamps on blank rows. They used to reach the app as 299
  rows of dashes a reader could sort into, which is why it claimed 7,800
  entries while 7,501 said anything. The researcher confirmed they can go, and
  `CONTENT_COLUMNS` in the importer is the rule: **a year is not content.**
- **Entries 7441–7501 are imported and thin.** A year, Food / Grain / Wheat
  and a page number, but no place, quantity or price. They stay because they
  say something, and because the researcher intends to fill them in through
  the app and send the database back, which is the cycle below working as
  designed. 7,435 of the 7,501 have both an item and a price.

## The calculation layer

`app/lib/services/pricing.dart` is pure Dart over plain numbers — no database,
no browser — so it runs on the Dart VM under `flutter test`.

Two behaviours are intentional and **must not be "fixed"**:

- Each of the three quantity terms in `totalMetric` is guarded individually, so
  an undefined measure contributes zero rather than failing the entry. This
  mirrors the sheet's `IFERROR(lookup * qty, 0)`.
- Everything downstream is **unguarded**. A missing or zero divisor yields
  `null` — the sheet's `#N/A` / `#DIV/0!`. Thousands of entries genuinely have
  no price per output unit; reporting that honestly is the right answer.

`"Total Grams"` is a misnomer inherited from the source: the value is metric in
whatever base the measure's dimension uses (an acre contributes square metres).

**Dimensions** gate conversion: entries measured in a kind of unit that cannot
reach the requested output unit are **excluded from averages and reported**,
never converted. Food per kilogram excludes 85 entries and moves the mean from
366d to 2d — that is the feature working.

## App architecture

Flutter web, `provider` for state, `sqlite3` WASM.

| File | Role |
|---|---|
| `services/sqlite_service.dart` | sqlite3 WASM on an **in-memory VFS** — what makes byte-for-byte export possible |
| `services/local_store.dart` | mirrors those bytes into **OPFS** as a safety net; deliberately *not* the sqlite VFS |
| `services/database_repository.dart` | all SQL; loads lookups once, exposes typed models |
| `services/pricing.dart` | the calculation chain |
| `services/calendar.dart` | Julian↔Gregorian display (7-day offset) |
| `services/app_version.dart` | reads the version out of the bundled `pubspec.yaml` |
| `services/preference_store*.dart` | `localStorage` for display settings, split by platform so the Dart VM (and therefore `flutter test`) can still load anything that depends on it |
| `state/app_controller.dart` | ChangeNotifier: dirty tracking, debounced local save, add/edit/delete, timestamped export, and `revision` (bumped on every data change — the Explorer's result cache keys off it) |
| `state/view_preferences.dart` | `DetailLevel`, `GroupBy`, `ThemeVariant`, `TableDensity`, theme mode, Gregorian toggle; persisted |
| `screens/home_shell.dart` | app bar, nav rail / bottom nav, save indicator, Display button |
| `screens/guide_screen.dart` | **Guide** — what the app is and how to use it; launches the tour |
| `screens/tour/tour.dart` | the click-through tour, its targets and its overlay |
| `screens/display_settings.dart` | the one dialog for detail level, theme, palette, density, dates |
| `screens/advanced/advanced_view.dart` | **Explorer** — orchestrates the memoised filter→price→sort→group pipeline |
| `screens/advanced/entry_columns.dart` | which columns exist at which `DetailLevel`, and why a cell is empty |
| `screens/advanced/entry_table.dart` | the table: fixed widths, two-axis scroll, pinned group headings |
| `screens/advanced/filter_bar.dart` | `FilterState`, search, facet panel, active-filter chips |
| `screens/advanced/edit_entry_dialog.dart` | the entry editor, progressively disclosed |
| `screens/simple/simple_view.dart` | **Quick lookup** — the same `DetailLevel`, median/mean/mode |
| `theme.dart` | three palettes × light/dark × density, `Spacing`, `Radii`, `tabularFigures`, `Breakpoints` |

Two rules the Explorer depends on:

- **Never filter or price inside `build()`.** The pipeline touches 7,501
  entries; it is cached against `_ResultKey`, which includes
  `AppController.revision`. Without that it re-ran every time the save
  indicator ticked from "Saving…" to "Saved".
- **A column that appears at two levels keeps its width.** Wider levels add
  columns and scroll sideways; they never squeeze what was already there.
  `entry_table_test.dart` asserts this.
- **Every column carries an `explanation`**, Year, Place, Item and Quantity
  included. Those four once went without, as self-evident; the researcher
  wrote text for each, and most of the explanations are now his wording.
  Asserted in `entry_table_test.dart`. The time-of-year one quotes live
  counts from `DatabaseRepository.entryCounts`; it used to say "363 of the
  7,800" long after there were 7,440.
- **Columns are ordered the way a row is read**, not the way the spreadsheet
  stored it: when and where, what it was, what it cost, what that works out
  to, how the figure was reached, what else the record says, where it came
  from. `EntryColumn.startsGroup` marks each turn and the table draws a seam
  there. Both the order and the seams are asserted.
- **Rows are banded, not ruled.** The per-row divider is gone; `shaded` tints
  every other row, restarting under each group heading. Twenty-three columns
  is a long way for an eye to travel.
- **Column names say which figure they are.** There are four prices in a row
  and they used to be called Price, Price (d), d / <unit> and Total sale (d).
  Now: *Price as recorded*, *Price in pence*, *Pence per selected unit*,
  *Total sale in pence*; and *Quantity in metric* rather than Total (metric), which read as
  a total sale. Output X and Output Y keep the source's own names on purpose —
  the researcher knows them by those, and the tooltips explain them.

A cell whose text is too long for its column gets a tooltip carrying the whole
value. Whether it is too long is *estimated* from character count rather than
measured — laying out a TextPainter per cell would be hundreds of layouts a
frame to answer a question only the long values care about — so it errs toward
showing one.

A heading has to fit its name, its sort arrow and its info button at once. Two
column widths have already been too tight for that; if a heading is renamed,
budget `label + 22 (info) + 13 (arrow) + 16 (padding)`.

An explanation reaches a touch screen only because it has its own button. A
heading's tap is already spoken for by sorting, and there is no hover to fall
back on, so `_HeaderCell` puts the tooltip in `TooltipTriggerMode.manual` and
opens it with `ensureTooltipVisible()` from a small info target. Manual mode
does not affect mouse hover — that is in the framework's own docs — so one
message serves both without a second code path. Verified in a Playwright touch
context where `matchMedia('(hover: hover)')` is false.

Note that below 640px the Explorer shows cards, not a table, so there are no
column headings on a phone in portrait at all. These explanations are for
tablets and landscape.

Two constraint traps in `entry_table.dart`, both found by looking at the thing
rather than by reasoning about it:

- The group heading lives inside the horizontal scroll view, so it slid off to
  the left as soon as anyone scrolled right. Its contents are translated back
  by `horizontal.offset` and held to `viewportWidth` — but a bare `SizedBox`
  cannot be narrower than the tight width the sliver hands down, so it needs an
  `Align` to loosen the constraint first. Without that it stretches back to the
  full 3,400px and posts the median off-screen.
- A `Spacer` and a `Flexible` in the same `Row` share the free space between
  them, so wrapping that median in `Flexible` parked it mid-band; leaving it
  unwrapped meant it could not shrink, and a longer wording overflowed the row.
  It is now `Expanded` + `textAlign: right`, which both pins it to the end and
  lets it ellipse. `entry_table_test.dart` caught the overflow at compact
  density in a 700px window — that test exists for exactly this.

## Keeping the settings responsive

Changing a display setting once blocked the main thread for 250–620 ms.
Measured with a `PerformanceObserver` on `longtask` around each click, in a
release web build. Four rules came out of it; breaking any one brings the lag
straight back.

1. **Only the visible view subscribes.** `AdvancedView` and `SimpleView` both
   stay mounted in an `IndexedStack` so their state survives a switch, and an
   `IndexedStack` does *not* stop a hidden child rebuilding — a `context.watch`
   dirties that element wherever it sits. Each takes an `active` flag and uses
   `watch` only when it is the one on screen. This alone was ~80% of the cost
   of changing detail level: rebuilding Quick lookup, which nobody could see.
2. **`MaterialApp` rebuilds only for theme settings.** `main.dart` uses a
   `Selector` on `(themeMode, variant, density)`. Watching all of
   `ViewPreferences` meant a detail change tore down and rebuilt every screen.
3. **`AppTheme.build` is cached** per variant/brightness/density.
   `ColorScheme.fromSeed` plus two `GoogleFonts` text themes are expensive, and
   `MaterialApp` asks for both light and dark on every rebuild.
4. **`DatabaseRepository` lookups are memoised** and cleared by `_invalidate()`
   on every write. They are called from `build()` — `localities()` alone reads
   789 rows.

5. **`themeAnimationDuration: Duration.zero` on `MaterialApp`.** By default it
   cross-fades a theme change over 200 ms, and *every frame of that fade lerps
   a whole `ThemeData`* — colour scheme, all text styles, all component themes
   — and rebuilds every `Theme.of` dependent. A dozen full rebuilds of a dense
   table to perform a fade nobody asked for. This was the largest remaining
   cost of a palette change; removing it took one from 334 ms to 78 ms.

Where it landed, in a **release** build: detail changes 62–112 ms (from
424–620), palette and light/dark 78–224 ms (from 329–370). Switching to a
palette for the first time in a session is slower than switching back to one,
because `AppTheme.build` has to construct it before the cache holds it.

### The version in the corner of the rail

`pubspec.yaml` is declared as an asset and parsed at runtime rather than the
number being copied into a Dart constant. A constant is a second home for the
version, and the two drift the first time somebody bumps one and forgets the
other — a version label that lies is worse than none, because it is believed.
The regex is anchored to the start of a line: the generated pubspec says the
word "version" a dozen times in its comments before reaching the real one. The
build number after `+` is dropped, and a failed read shows nothing rather than
taking the app down with it.

`NavigationRail` has no bottom slot — its `trailing` sits directly under the
destinations, where it reads as a third one — so the label goes below the rail
in a `Column`, and the `Column` is painted `surfaceContainerLow` so no seam
shows where the rail's own background stops.

### The default unit is the one the source used

`MetricItem.recordedUnit` is a sentinel, not a row in `measures`: its id is
`__recorded__`, so it can never collide with a real measure or survive being
saved. Choosing it prices each entry against its own valuation measure, which
is just `calc.priceInPence`, the recorded shillings and pence. Nothing is
converted, so `canBePricedPer` always returns true and no entry can come back
empty.

It is the default in both views, labelled "The measure each record used".
The modern-units option (`comparableUnit`, "Modern (# or Metric Kg)") was the
default for a while; the researcher asked for this back. Kilograms was, and
observed testing showed
the cost: a reader who changed the unit to something the selection cannot
express saw an empty column, could not tell whether the app was broken or the
question unanswerable, and had no way back to where they started.

**The aggregate figures then mix measures**, and both views say so in red:
`across mixed measures` in the Explorer toolbar, a full note in Advanced
Search. Each row is sound on its own; a median across quarters, days and
stones is not a number anybody should compare with another. This is the one
place the app shows a figure it cannot fully stand behind, and it does it only
because the alternative (showing nothing) is what sent readers away thinking
it was broken. Do not quietly drop the warning to tidy the toolbar.

There is also a **Reset** in the toolbar, always present, which puts the
filters, unit, sort, grouping and estimates back to how the page opens. It is
distinct from "Clear all", which only appears once a filter is active, and so
is not on screen at all for the reader who most needs it.

### Estimates are the one place this app invents a number

`services/trend.dart` guesses at prices the source never recorded, which cuts
against every other rule here. It is allowed only because it is hemmed in:

- **It fits one median per year, not every sale.** A least-squares line over
  raw values would be dragged wherever the dearest record sits.
- **It refuses more than it answers.** Three distinct years minimum, a positive
  result, never more than ten years beyond the observed range — 80 estimates
  across 7,501 entries with the default filters.
- **It is never mistaken for data.** Drawn in italics with a `~`, and each
  carries a tooltip naming what it was fitted through and what fraction of the
  year-to-year movement that accounted for. It stays out of group medians.
- **The toolbar figures are computed twice** — once over recorded prices, once
  counting the estimates — and both are shown, labelled `recorded` and `with
  estimates`. The researcher asked for the estimates to count, and the only
  honest way to do that is to show what difference they made. Never collapse
  the two into one line.
- **Off by default.** A reader has to ask, via the Estimates chip.
- Deepest taxonomy level with enough years wins: wheat from wheat, else grain,
  else food — and the estimate says which.

Loosen any of that and the app starts quietly manufacturing history.

### Installable, and offline after one visit

`web/sw.js` is ours. **Flutter no longer generates a caching service worker** —
what it writes now unregisters itself and caches nothing — so the loader's
`serviceWorkerSettings` is deliberately not used, and the bootstrap registers
`sw.js` by hand.

Three decisions in it, each with a reason that is not obvious:

- **Registered before the engine loads, not on `window load`.** The engine,
  the renderer and the database are all fetched during the first load. A
  worker registered at the end of it controls none of them, and the reader who
  installs the app and then loses the network gets a blank page. Measured: 3
  files cached on a first visit when registered late, 19 when early.
- **The page reports what it loaded; there is no precache list.** Even
  registered early, the worker cannot see the requests that started before it
  activated. So after `load` the page hands over
  `performance.getEntriesByType('resource')` and the worker stores those. A
  hand-kept list of engine filenames would go stale silently, and it cannot
  know which CanvasKit build this browser wants — this way Chrome caches the
  5.5 MB chromium one and nothing else, rather than both to be safe.
- **The cache is named from `version.json`**, which Flutter generates from
  `pubspec.yaml`. So one number — the one in the corner of the rail — is also
  the release tag and the thing that retires an installed copy's cache. **Bump
  it on every publish after the first, data-only ones included.** Forgetting is
  not fatal because assets are stale-while-revalidate, but a bump is what makes
  the changeover clean rather than one-load-late. 0.0.1 is what the client
  first receives, and stays put for it: there is no earlier copy in anyone's
  browser for it to retire. **0.0.2 is the first bump**, because 0.0.1 did
  reach the researcher's testers: their feedback screenshots show it in the
  corner, so there are installed copies holding that cache.

Navigation is network-first so a deploy is seen on the next load rather than
the one after; everything else is stale-while-revalidate, because cache-first
would pin a reader to an old build forever and network-first would make every
load wait on 20 MB that did not change.

Verified: 19 files cached from a single visit, then the network cut entirely
and the app reaches 7,501 entries with zero page errors; manifest parses with
no errors; `beforeinstallprompt` fires. Note it will **not** fire under
Playwright's default profile — automation suppresses the banner — so test
installability with `launchPersistentContext` and some real interaction, or
you will conclude it is broken when it is not.

**The install invitation lives in the app's own ⋮ menu**, because the browser
puts its own control in the address bar where a reader who has never installed
a web app will not look. `beforeinstallprompt` fires once, early, and cannot be
asked for again, so `flutter_bootstrap.js` has to be listening before the
engine starts; it holds the event and calls `preventDefault()` so Chrome's
mini-infobar does not make the same offer in a second place.
`services/install_prompt.dart` is split by platform like `preference_store` —
the Dart VM has no `package:web`, and a widget that could not load there would
take the widget tests with it. The menu is built when opened rather than once,
since the offer arrives a moment after load and is spent as soon as it is
taken. It shows nothing in Firefox and Safari, which do not implement this.

The icons were Flutter's own logo until `tools/make_icons.py`. The mark is the
reverse of a long cross penny — the coin these records are counted in, Edward
I's recoinage of 1279 falling mid-period — which unlike a castle outline is
still legible at sixteen pixels. `manifest.json` was scaffold boilerplate too:
named `price_explorer`, described as "A new Flutter project", Flutter blue,
and locked to `portrait-primary`, which for a table twenty-three columns wide
was exactly wrong.

### The app must work with no internet

Two things reached the network at startup and both are now local. Neither was
obvious until the app was loaded with Google blocked:

- **The rendering engine.** Flutter fetches CanvasKit from `www.gstatic.com`
  unless told otherwise, so the app would not start offline — it fails with
  *"Failed to fetch dynamically imported module"*. `web/flutter_bootstrap.js`
  overrides it with `canvasKitBaseUrl: "canvaskit/"`, pointing at the copy
  Flutter already ships beside the app. Note the `--dart-define=
  FLUTTER_WEB_CANVASKIT_URL` route is **ignored** by current Flutter; the
  bootstrap config is the one that works.
- **The typefaces.** `google_fonts` downloaded Inter and Spectral at runtime.
  They are now real assets under `app/fonts/`, declared in `pubspec.yaml`, and
  the package is gone.

- **The engine's fallback typeface.** CanvasKit fetches one Roboto woff2 from
  `fonts.gstatic.com` at startup, and Noto faces on demand for glyphs the
  app's fonts do not cover. `fontFallbackBaseUrl` in the bootstrap redirects
  that at `web/fallback-fonts/`, where the one file it wants is shipped. The
  engine builds the URL as `${fontFallbackBaseUrl}roboto/v32/<hash>.woff2`, so
  the folder layout has to match exactly.

Builds also pass `--no-web-resources-cdn`, including in the Pages workflow.

Test it the way it was found: block `*.gstatic.com` and `*.googleapis.com` in
the browser and load the app. It should reach 7,501 entries with **zero blocked
requests and zero page errors** — there is now nothing left to block.

### Responsiveness is about height, not just width

A thirteen-inch laptop is wide enough for the whole table and has about 620px
of page once the browser has taken its share. On a table, height is what you
are looking at: every pixel of toolbar is a row of records you cannot see.
`Breakpoints.isShort(height)` (under 760px) drives a `dense` flag that:

- drops the detail chips from the Explorer toolbar — the app bar already
  carries that choice, so it is the one control that can go without loss, and
  losing it lets everything else fit on one row;
- narrows the group menu and shortens the entry count to '7501 / 7501';
- tightens the Specifics lookup's rhythm and drops the level description,
  which is what brings Generate back above the fold.

`isNarrow(width)` (under 1200px) separately trims the summary strip to median
and mean, rather than letting five figures wrap onto a second line.

At 1280x620 this took the Explorer from about 6.7 visible rows to 8.1.

### Editing is a place you have to go

Three changes with one intent, after watching readers edit records they meant
only to look at:

- A row tap **reads** (below).
- **New entry appears only at `everything`**, in both the toolbar and the
  overflow menu. A button offering to create records, sitting above a table
  somebody came to read, is the same mistake one step earlier.
- The views are named for what a reader wants, not what they contain:
  **Data Display** and **Advanced Search**. These were "Explorer" and
  "Specifics lookup"; the researcher renamed them twice, and the most recent
  naming is the one that stands.

### Modern money is computed, never stored

`pricing.dart` takes one number, `modernPoundsPerPenny`: what a single penny
of the entry's year is worth in the money being reported in.
`DatabaseRepository.modernPoundsPerPenny` builds it by multiplying
`currency_factors.base_pounds_per_penny` by the single `currency_rebasing`
multiplier, so the calculation layer touches neither table and stays pure
Dart over plain numbers.

Three figures come out, the brief's `UKP 2026 Total Sale`, `per Val Meas` and
`per Y`. The researcher's workbook keeps them as columns; we do not, for the
reason the schema has always given: the third depends on the unit the reader
picks, so it cannot be a column.

Two things that are easy to get wrong and are deliberate here:

- **Convert each entry, then average. Never average, then convert.** A
  selection spans years with different factors, so converting a median would
  mean choosing one year's factor for a span that has several. Advanced
  Search builds a parallel list of converted values and takes the same
  statistic over it, which is why its modern figure is not the pence figure
  times a constant.
- **The headings say per what.** `Price in 2026 £` sits beside `Price as
  recorded` and is that price; `2026 £ per <unit>` sits beside `Pence per
  <unit>` and is that figure. As "In 2026 money" and "In 2026 money per …"
  the researcher read the second as the total sale. It never was: entry 6744,
  6 Little Pound at 7d, gives £27.20 and £72.87, and a total sale of 42d
  would be about £163.
- **The per-unit modern figure comes from `pricedIn`**, carried on
  `PricedEntry.modernPerUnit`, not from `calc.modernPerOutputY`. The latter
  answers per whatever unit it was handed, so it showed a figure beside a
  withheld pence one, and a dash beside a real one on Recorded unit.
- **Both columns appear from Basics**, beside the recorded price, because the
  researcher asked for a modern equivalent visible "with no effort" and
  changing detail level is effort. `modernYear` is read from the database
  rather than hard-coded, and null hides the columns entirely: a column of
  dashes headed "In 2026 money" reads as a broken app when the truth is that
  nobody supplied the figures.

Every modern figure is prefixed "about" and its tooltip says it is a guide to
scale rather than a valuation. The factor is quoted to two decimals and rests
on a scholarly judgement with more than one defensible answer, so printing
£212.52275 would claim a precision nobody has. `entry_table_test.dart`
asserts the word "scale" survives in the explanation.

### A missing price is not a price of nought

`RecordedPrice.inPence` sums blanks as nought, and that is correct: the
spreadsheet's own formula is `£×240 + s×12 + d` over blank cells, and
`excel_cached_calculations` is compared against it. **Do not "fix" it.**

But nought is not a price. 66 entries record none at all, 61 of them in 1286,
and once "Recorded unit" became the default output unit that figure started
feeding every median, mean and chart on the screen. Counting those as nought
dragged the 1286 median to the floor and drew a trend line diving into the
axis.

So `PriceCalculation.recordedPricePerUnit` is `inPence` with the blanks taken
out, and that is what the views average. A *genuine* nought is kept, because
14 entries really do record one and the source is saying something by it.
`pricing_test.dart` pins all four cases.

### The figures are meant to be seen

They were a grey run of small text and observed testers "genuinely did not
recall seeing the averages at all", though they had just generated them. The
researcher asked for them to be "much more visually distinct, arguably the
first thing they should see".

They now sit in a tinted panel with the median set large and in the accent
colour. The median leads on purpose: with a mean of 253 against a median of
0.19, leading with the mean would be leading with the wrong number.

### The guide and the tour

`screens/guide_screen.dart` is the third rail destination, and
`screens/tour/tour.dart` the click-through tour it launches. The researcher
asked for "a little of both": a page that says what the database is and how to
use it, plus a tour that says "this button does x".

**Every word in both is placeholder.** He said he would write the copy. It is
written out properly rather than left as lorem so he can edit over something
real, and so the app is not embarrassing while we wait. Replace freely.

How the tour points at things:

- A control marks itself with `TourTarget(stop: TourStop.pricePer, ...)`,
  which registers a `GlobalKey` in a plain static map. A static registry
  rather than an InheritedWidget because registrations come from four screens
  and the only reader is an `OverlayEntry`, which sits in nobody's subtree.
- **A stop that is not on screen is skipped, not drawn.** Half these controls
  exist only at certain detail levels and below 640px there is no table at
  all, so `rectOf` returning null is the normal case rather than a fault.
- **A step may have no target at all.** The one about opening a record is
  like that: a row lives inside a sliver list and pointing at one of 7,501
  would mean threading a key through every row. A null stop centres the card.

The tour answers to the keys every web tour does: Right or Enter for next,
Left for back, Escape to leave. Next is given focus outright rather than by
`autofocus`, which stands aside when the page already has focus; and the
Explorer does not take focus back for its table while `Tour.isRunning`, or
the keys went to the table behind the scrim. A step with nothing to point at
is skipped **in the direction of travel**: always skipping forwards made Back
bounce off such a step and return to where it started.

The scrim is a `CustomPainter` doing `Path.combine(difference)` between the
screen and the hole. Tapping it advances, because that is what people try
first.

### `(?)` beside a control, and the text in one file

`widgets/info_dot.dart` holds both halves. `InfoDot` is the column headings'
mechanism made reusable — a tooltip in `TooltipTriggerMode.manual`, opened by
tapping a target of its own, because a plain tooltip is hover-only and half
the audience is on a tablet. Manual mode governs touch only, so a mouse still
gets hover without a second code path.

`Explain` holds every string. They are gathered in one class **so the
researcher can send prose and have it dropped in without anybody touching a
layout**; the ones there now are placeholders written from what each control
does. The Michaelmas note lives behind one of these rather than printed under
the date fields, which is what he asked for.

### The chart draws a median, and draws gaps as gaps

`widgets/price_trend_chart.dart` is a `CustomPainter` over plain numbers. No
package: the app must run with no network and ships no third-party chart
code, and a polyline is not worth a dependency.

Three decisions, each load-bearing:

- **The median per year, never the mean.** Across a broad selection the mean
  runs to 253 against a median of 0.19; a line of means is a line about one
  record.
- **A year with no priced record is a gap**, not a zero. The path breaks
  rather than diving to the axis and back, because a missing price is silence
  and a zero is a claim.
- **The mark is sized by how many records stand behind it**, so a year
  resting on two shows as a small dot rather than as a confident point.

It is fed from the same `priced` list as the headline figure, so the line can
never disagree with the number above it.

### Every dropdown is the filterable one

There are no bare `DropdownMenu`s left in `app/lib`. The Explorer's filter
panel kept four of them (County, Category, Dates, Group) long after the
shared widget existed, and they failed the same way Price per had: an
unbounded menu grew tall enough to flip *above* the field and cover the very
text being typed into it, so narrowing by typing was impossible. The reader's
words were "virtually impossible to type".

`FilterableDropdown` fixes it with `menuHeight: 320`, which is what makes the
list drop below the field and scroll. If a new dropdown appears anywhere, use
that widget. The same bug has now been found three times in three places.

### Sentence-length tooltips need a width

`Tooltip` has no default maximum, so a four-sentence message renders as one
line the full width of the monitor, which reads as a layout fault rather than
a message. Anything longer than a few words carries
`constraints: BoxConstraints(maxWidth: 380)`. The short ones ("Clear",
"Detail, theme and row height") are left alone because they wrap to nothing.
`ThemeData.tooltipTheme` cannot carry this: `TooltipThemeData` has no
constraints field, so it has to be per-widget.

### The importer checks its own column map

`build_normalized_db.py` reads the Data sheet **by position**, and between the
August export and the researcher's current workbook those positions moved:
three `UKP 2026` columns were inserted in the middle and the calculation
columns were reordered around them, so column 24 went from `OUTPUT X` to
`Val Meas in Grams`. Reading the new sheet with the old map produces a
database where every row loads, every count matches, and every derived figure
is taken from the wrong column.

So `COL` now has `EXPECTED_HEADERS` beside it and `check_data_headers()` runs
before anything is imported, matching heading text loosely (case, spacing and
punctuation ignored, because wording drifts harmlessly) and refusing outright
when a *position* has moved. Update the two together. Do not widen the check
to make it pass.

### Reading a record is not editing it

A tap on a row opens `entry_details_dialog.dart`, read-only, with one button
through to the editor. It used to open the editor directly, and observed
testing showed what that cost: a reader took the dialog for a search box and
changed a record, and afterwards nobody could say which record it had been.
Scrolling by tapping did it too. The pencil in the row still goes straight to
the editor, because clicking that says what it means.

The dialog is **generated from `columnsFor`** rather than listing fields of
its own. The table already knows every label, value, explanation and which
detail level each belongs to; a second copy would drift within a month and the
two would then disagree about what a record says. `entry_table_test.dart`
asserts that a tap calls `onRead` and never `onOpen`.

### Notes ride on the item, not in a column

Status Info, Food and Information say what kind of "Other" an `Other / Other /
Other` row is, and once lived only at Everything, twenty columns from the
item they explain. The researcher's suggestion was that they stay columns in
the database and stop being columns in the table: `RecordNotesMark`
(`widgets/record_notes.dart`) puts a small mark after the item wherever any
of the three holds text, at every level and on the phone cards, opened by
hover or by tap. The details dialog writes them out in full below Everything,
where there is room for a sentence. At Everything the columns stay too,
because that level is the one for sorting and editing them.

### The specific carries the weight

`widgets/item_label.dart` renders `Food / Grain / `**`Wheat`** with the path
muted and a size down, the specific bold. Read as one flat grey run,
`Food / Grain / Wheat` and `Food / Grain / Barley` are nine identical
characters followed by the only ones that matter, and readers locked onto the
category instead of the thing itself. The emphasis is **weight and contrast,
not size**: a larger glyph would change the line height of every row in a
table of 7,501. Used by the table, the phone cards, the details dialog and the
Specifics lookup result heading, so an answer is recognisably about the same
thing wherever it appears.

### Scrollbars have to be seen

`theme.dart` carries a `ScrollbarThemeData`, and the table's vertical bar sets
`thumbVisibility: true`. There was no scrollbar theme at all, so both axes
used Material's default (a thin, low-opacity grey, invisible on parchment) and
the vertical one appeared only while the list was actually moving. Observed
testing: readers did not know the table continued sideways, and did not know
they could move down it at all. On this table a scrollbar is not decoration,
it is the only thing saying there is more.

**The vertical bar wraps the sideways scroll, not the list.** Inside it, the
bar was drawn at the right-hand edge of the full row, which is off screen
whenever the table is wider than the window: missing in exactly the case it
was needed. It now sits outside with `notificationPredicate: depth == 1`,
because the list it tracks is one scroll view down, and the list's automatic
desktop bar is switched off so a second one does not lurk at the far edge.

### The table is usable from the keyboard alone

The researcher asked for it. A `Focus` round the table takes the keys,
autofocuses, and takes focus back on any pointer-down. Arrows, Page Up/Down,
Home and End move a **highlighted row** (`_cursorId`, held by entry id so it
survives a re-sort); Enter or Space opens it to read, Escape drops the
highlight, Left/Right scroll sideways, `/` goes to the search box and Enter in
the search box comes back. A click moves the highlight too, so reading a row
and closing it carries on from there. The highlight shows only while the
table has focus.

Three things that make it work and look like tidying:

- **Rows, their pencils and their note marks are out of the Tab order**
  (`canRequestFocus: false`, `ExcludeFocus`). Otherwise Tab walked every
  visible row before reaching anything else. The table is one Tab stop; the
  column headings are the next ones, and Enter on a heading sorts.
- **The header strip is a `Material`, not a coloured `Container`.** Ink paints
  on the nearest Material below it, so the Container hid the headings' focus
  tint completely and Tab appeared to vanish.
- **Hidden screens are wrapped in `ExcludeFocus`** in `home_shell.dart`. The
  `IndexedStack` keeps the table mounted behind Advanced Search, and it went
  on taking arrow keys there out of sight. `AdvancedView.didUpdateWidget`
  hands focus back to the table on return.

`entry_table_test.dart` drives the whole walk.

### Keys the reader already knows

Keyboard control was asked for "to the industry standard", so the
keys are borrowed rather than invented, and a habit from elsewhere works here:
`?` lists every key and `/` goes to search (Gmail, GitHub, YouTube); J and K
beside the arrows (the same); Alt with 1, 2 or 3 changes screen, as tabs are
numbered in browsers and editors, and **not Ctrl**, which the browser keeps
for its own tabs; arrows stop at either end of the rail, as in a list of tabs.

- **The app-wide keys sit ahead of the focus tree**, in
  `FocusManager.addEarlyKeyEventHandler`. A `Focus` round the screen only
  hears keys that start inside it, and on first load nothing has focus.
- **Read off the physical key**, because Option+1 on a Mac types `¡`.
- **Only from the main screen** (`ModalRoute.isCurrentOf`). Changing screen
  under an open record leaves a dialog about a screen nobody can see.
- **`?` and `/` stand aside while typing** (`isTypingText`), or nobody could
  search for either character.

`widgets/keyboard_help.dart` holds the one list, shown on the Tutorial page
and in the `?` dialog. Nothing ties it to the code that answers the keys, so
a key changed there must be changed here too, or the page promises keys that
do nothing. Below 480px every meaning drops under its keys at once; a `Wrap`
decided it row by row and the list stopped reading as a list.

### Sorting belongs to the column

There is no `SortField` enum any more. Each `EntryColumn` carries an `id` and a
`sortKey`, and the table sorts by whichever column's id is held in
`_sortColumnId`. The enum was why most of the table could not be sorted: every
new column needed two edits elsewhere and so never got them. Every column is
sortable now, asserted in `entry_table_test.dart`.

The `id` is stable where the label is not — the per-unit heading is "Pence per
Kilograms" one moment and "Pence per Tower Pound" the next. Missing values sort
last in *both* directions: a row with no page number is not a row with a low
one. And a sorted column can vanish when the detail level narrows, so the view
falls back rather than assuming it is still there.

### Answers do not vanish, and the button moves the page

Two things that made the app look broken when it was merely unable to answer:

- **The toolbar figures used to disappear** whenever the selection could not
  be priced in the chosen unit. A reader who had just changed the unit watched
  the numbers drop off the screen with no explanation. They now hold their
  place as dashes, with `none of these can be priced per <unit>` beside them,
  which is a different and recoverable thing.
- **Generate results scrolls to its answer.** It changed something below the
  fold, and with no visible scrollbar the button looked dead, so people
  pressed it twice.

Item suggestions are ordered by **how many entries actually sit under each
path**, not alphabetically. Typing `oats` offered `Agricultural Labour /
Mowing / Oats (Mowing)` before `Food / Grain / Oats`, because A sorts before
F. Counted once per `AppController.revision`: the count walks all 7,501
entries and the search box rebuilds on every keystroke.

### Quick lookup only offers what it can answer

`screens/simple/facets.dart` counts, in one pass over the entries, how many
each dropdown option would still find — judged against every *other* filter
but not against itself, which is what makes a facet a facet. Options that
would find nothing are sent to the bottom of the list, struck through, marked
`(none)` and disabled; the current selection stays enabled so nobody is
stranded on a value they cannot leave.

**Except the item levels, which nest.** Choosing a category clears the
subcategory and specific beneath it, and choosing a subcategory clears the
specific, so each item level is judged only against the levels *above* it.
Judged against every other filter, picking "wheat" from the item box struck
out every other subcategory and category as `(none)` (no fish is wheat) and
the reader could not leave Grain without clearing it first. `facets_test`
pins it.

**The specific counts at Basics too.** Basics drops region, locality and time
of year from the answer because it hides those controls. It used to drop the
specific for the same reason, but the item box is on screen at Basics and
sets one: "wheat" was answered with every grain under a heading reading
`Food / Grain`.

Units answer a different question: `canPriceIn` asks whether the surviving
entries are measured in a *kind* of thing the unit can express. This is the
case the screen exists for — Labour is paid by the day, so every unit of mass
is struck out for it. That also exposed a gap: the short unit list offered at
Basics was all weights and one volume, so counted categories had no usable
unit at all. `Heads/Units` is now in it.

Pure logic, no widgets, tested in `facets_test.dart` — including "a county
with no labour makes Labour unavailable" and "labour counted by the day cannot
be priced by weight".

### Every filter clears itself

The screen-wide **Clear** stays — it is for having narrowed too far and
wanting to start over — but each control also carries its own cross, because
undoing one choice should not mean rebuilding the other five. `AutocompleteField`
grows one whenever it holds text (which gives the entry editor eleven for
free), and a year box grows one only once that end has been moved off the
range the records cover, where it reads *Back to 1270* rather than blanking a
field that can never be empty.

**Every cross is out of the Tab order.** `ExcludeFocus` on the text-field
crosses, and a `trailingIconFocusNode` with `skipTraversal` on each
`FilterableDropdown`, because `DropdownMenu` wraps its trailing icon in a
focusable button of its own: each dropdown cost two Tab stops, three with a
cross inside, and the bare arrow was a button with no name. From the
keyboard, Backspace on the selected label clears a dropdown, and Ctrl+A then
Backspace clears a text box.

Two controls deliberately have none: the country, which has one value, and the
output unit, which is not a filter — every answer is *per* something, so there
is nothing coherent to clear it to. `_clearAll` leaves the unit alone for the
same reason.

### Choosing a suggestion from the keyboard

Three faults in `AutocompleteField`, all found by driving Advanced Search with
the keys alone, and each looks like something to tidy away:

- **`onSubmitted: (_) => onSubmit()`.** Without it, Arrow Down moved through
  the suggestions and Enter chose nothing: the half-typed text stood, no item
  was set, and Generate stayed disabled.
- **`onEditingComplete: () {}`.** A text field drops focus on Enter by
  default, so after choosing, the next Tab started from the top of the page.
- **The highlight is drawn and scrolled to from a `Builder`.** The `context`
  an `itemBuilder` receives belongs to the whole list, so scrolling *it* into
  view centred the entire list and opened the menu halfway down. The rows are
  wrapped in `ExcludeFocus` too: focusable, Tab fell into the open list and
  back, and the keyboard could never leave the box.

And the item box in Advanced Search is **not keyed** on the chosen category.
The key made the box follow the dropdowns, but it also destroyed the box
whenever a pick in it changed the category, and focus fell back to the
navigation rail. The field now follows a changed `initialValue` in
`didUpdateWidget`, as `FilterableDropdown` already did.

The navigation rail is a `FocusTraversalGroup`. Tab otherwise reads the page
in rows, and on Advanced Search took Tutorial after the three detail chips.

### A `DropdownMenu` you can type into

`FilterableDropdown` in `widgets/filterable_dropdown.dart` wraps `DropdownMenu` so that typing
narrows the options (`enableFilter` + `requestFocusOnTap`) and anything left in
the box that names no option is put back on blur. Without the second half a
category could sit reading 'dasdwadsd' — a value no record has, silently
filtering everything away.

**Never hand `DropdownMenu` a `focusNode` of your own.** Its text field then
never takes focus, so keystrokes reach nothing and `enableFilter` never
engages — `_enableFilter` is only set inside the field's own `onChanged`. The
blur is observed from outside with a `Focus` wrapper instead. This looks like
an obvious thing to tidy up and is not.

Two more things the same widget needs, both learned by watching it:

- `menuHeight: 320`. Unbounded, the menu grows tall enough to flip above the
  field and cover the very text being typed into it.
- **A cross to un-choose with.** Every level carries an `Any …` row, but the
  menu opens scrolled to the current selection, so that row sits above the
  fold and is no help. The `trailingIcon` becomes a clear button whenever
  something is chosen. Emptying the box by hand clears it too.
**Use it for every one of them.** Price per stayed a bare `DropdownMenu` long
after this widget existed, and was the worst control in the app for it: a
click put the caret mid-label, the list did not narrow, and somebody trying to
type "volume" ended up with `volumtotototototo` in the box and no way back. It
takes an optional `label`, because the Explorer's toolbar has no sentence
around it to say what the control is, and "Price per" is precisely the one
readers reported not understanding.

- **Select the label on focus** (`_selectAllOnEntry`, post-frame). The current
  label is real text in the controller, so without this the caret lands
  wherever the reader clicked and the first keystroke lands *inside* it —
  clicking the middle of `Any category` and typing `produce` gives
  `Any cateproducegory`, which matches nothing and opens an empty menu. This
  is what the reader meant by the typed text not working. It also makes one
  Backspace enough to empty the field, which is the keyboard route to
  un-choosing.

### Never put a long list in a `DropdownMenu`

It builds every entry up front. The Quick lookup locality picker held all 789
localities and froze the app for **5.2 seconds** on opening that screen in a
debug build (282 ms after the fix; release hid it at ~50 ms, which is why it
had to be reproduced under `flutter run`). Use `AutocompleteField` instead —
it caps at 50 options and only builds them while the overlay is open. The
editor already used it for exactly this reason. Anything past a few dozen
options should be typed, not scrolled: nobody finds 'Wyllindone' in a list.

A mouse can drag the table around: `DragToPanScrollBehavior` adds
`PointerDeviceKind.mouse` to `dragDevices`, **on the table only**. It was set
on `MaterialApp` once, and every other scrolling page then took a mouse drag
as a scroll before text selection could see it. Flutter
leaves it out by default because click-drag usually means selecting text; here
the table is ~3,000px wide and the alternatives were a shift-wheel and a
three-pixel scrollbar. Clicks and text selection are unaffected — a drag only
wins the gesture arena once nothing nearer the pointer has claimed it.

### Reading aids

The researcher asked for them, naming a dyslexia typeface. Three settings in
Display, under Reading, plus one change that is not a setting:

- **Typeface.** Inter, Atkinson Hyperlegible (Braille Institute, for low
  vision: I, l and 1 and O and 0 cannot be mistaken, which is what a column of
  place names and figures needs) or OpenDyslexic. Both extra faces are SIL
  OFL, shipped under `app/fonts/` with their licences in `fonts/licences/`
  and registered in `main.dart`. Bundled rather than fetched, like Inter,
  because the app runs offline. The evidence for OpenDyslexic is mixed, so
  the wording says some readers find it helps, not that it does.
- **Text size**, ×1.15 or ×1.3 on top of whatever the system asks for, via
  `MaterialApp.builder`. Not browser zoom, which shrinks the table's view of
  rows and columns at once.
- **Wider spacing**, added style by style in `AppTheme._spaced`. Not
  `TextTheme.apply(letterSpacingDelta: ...)`, which asserts on the styles
  Material leaves unset. The letter spacing is eased below the W3C's eighth
  of a size because OpenDyslexic, already wide, fell apart into single
  letters at the full amount.
- **The focus ring**, `widgets/focus_ring.dart`, always on and keyboard only.
  Material's focus tint was a tenth-strength wash, invisible on parchment, so
  Tab worked and nobody could see where it was. One ring painted over the
  whole app rather than every button restyled, which would miss whichever
  kind came next. It reads the focused box **at paint time**, so it is never
  a frame behind a scroll; it follows for 400 ms after a change, because
  focus often lands in a dialog that is still growing; and it skips anything
  over 40% of the window, which is the table, whose current row is its own
  highlight.

The typeface and spacing are part of `AppTheme`'s cache key and of the
`Selector` in `main.dart`. A family named outright anywhere in `lib/` would
stop the reading typeface at that widget; the rail's label styles needed one
for exactly that reason. `entry_table_test.dart` lays the table out at the
largest size with wide spacing in every typeface, density and level.

### Judge speed in release, not `flutter run`

`flutter run -d chrome` is a **debug** build, and on web that is roughly five
times slower than what ships. The same clicks, measured on the same machine:

| | release | debug |
|---|---|---|
| detail → Everything | 112 ms | 542 ms |
| palette → High contrast | 199 ms | 1,149 ms |
| light/dark → Dark | 224 ms | 932 ms |

A theme change costs about a second in debug and there is no fix for that
short of not measuring in debug — what remains is the rebuild of every widget
that read `Theme.of`, which is inherent to changing a theme. Serve
`build/web` (or `flutter run --release -d chrome`) before judging.

The one remaining structural lever, if it ever matters: the hidden view still
rebuilds on a theme change, because `active` gates the *notifier* subscription
and not the inherited `Theme` dependency. Measured at ~15% of a palette
change, and stopping it means unmounting the hidden view and moving its filter
state somewhere that survives. Not worth it at these numbers.

### Groups open and close, and start closed

Grouped, the table (and the phone cards) shows only the headings, each with
its median, until one is clicked. The researcher's request: grouping by year
should let a reader "look at the median price for 1270, then deselect to see
only 1280", and with every row on screen the headings were hundreds of rows
apart. Open groups are held by label in `_EntryTableState._open`, so they
survive a re-sort, a unit change or an edit. Headings are not Tab stops (two
dozen of them would trap Tab); the Open all / Close all bar above the table
is the keyboard route. The keyboard cursor walks only rows that are showing.

### Settlement filter, and (?) on Advanced Search

Filters has a Settlement box beside County: typed rather than picked
(hundreds of names), suggesting only the chosen county's, and filtering only
on an exact name. Changing the county lets go of it. Advanced Search carries a
(?) on every control, and where a control matches a table column the two read
the same `Explain` constant, which is what the researcher asked for.

### Every word can be copied

The researcher's sharpest complaint: everything had to be retyped.
`widgets/app_selection.dart` holds the answer, and each part of it was found
by trying the simpler version first.

- **A selection per screen and per dialog, never one round the app.** One in
  `MaterialApp.builder` held the keyboard from outside every dialog once
  something was selected: Escape stopped closing records. One round the
  `IndexedStack` was answered by whichever hidden screen came last.
  `home_shell.dart` wraps each view separately; the stack hit-tests only the
  visible one. **Do not reach for global keys to move the views between
  wrappers**: that was tried, and reparenting text mid-selection makes
  Flutter's own scroll-view selection throw at phone width.
- **`CopyLayout` goes inside each scroll view, round its content.** Flutter
  joins selected pieces with nothing between them (`Year1270Place...`), and a
  scroll view joins its own pieces before anything outside sees them. Inside,
  a piece lower down starts a new line and one beside it gets a tab, so a
  label and its value paste into a spreadsheet as two cells.
- **The table body is out of it** (`SelectionContainer.disabled`), because a
  drag there scrolls and a click opens the row. Ctrl+C on the highlighted
  row, or Copy in the record dialog, copies the row as headings over values,
  tab-separated, with the dash left as an empty cell (`recordsAsText`).
- **Dropdowns are out of it too**: `DropdownMenu` lays out every option
  unseen, and a drag across the toolbar copied all of them.
- **The tour takes focus back** whenever it leaves its scope, because a click
  inside a selectable page claims focus after the tour has given it to Next.

`copy_test.dart` pins both the row format and the line-and-tab joining.

Storage model, in the user's terms: OPFS is a **safety net**, downloading a
timestamped `.sqlite` is the only **filing system**. Nothing is overwritten in
place. Keep that distinction in any wording change.

## Commands

```bash
# the original import. Refuses if the database holds entries the spreadsheet
# cannot restore; --force only after moving the file somewhere safe.
pip install openpyxl && python tools/build_normalized_db.py

# review a database the researcher sent back, before it becomes everyone's
python tools/check_incoming_db.py ~/Downloads/whatever-they-sent.sqlite

# apply pending schema changes to it (--check to see what would run)
python tools/migrate.py ~/Downloads/whatever-they-sent.sqlite

# regenerate the test corpus / re-check against the DB directly
python tools/validate_calculations.py

# rebuild the researcher's questions file
python tools/build_review_db.py

cd app && flutter pub get
cd app && flutter run -d chrome     # or F5 -> "Price Explorer (Chrome)"
cd app && flutter test              # Dart VM, no browser, no WASM
```

## Tests

`app/test/calculation_corpus_test.dart` replays all 7,501 entries through the
calculator and compares six derived values each against
`test/fixtures/calculation_corpus.csv` (what the spreadsheet computed).
**All 7,501 now agree on all six, with zero disagreements.**

Entry 7292 was the one exception for months, and how it resolved is worth
keeping. Its measure is spelled `Garb, Steel [?81 lb?]`, and in the August
workbook the spreadsheet's own lookup failed on it: `Total Grams` blank, the
count cached as zero, the per-unit figure as `#DIV/0!`, while our code
resolved the measure and produced an answer. In the current workbook the same
row, with the spelling unchanged, resolves to 36741.00185 and 0.1905. The
sheet had simply failed to recalculate that cell; **our reading was right and
the source caught up.** The test reports a *recovered* divergence as loudly as
a new one, which is how this was noticed rather than silently absorbed.

`app/test/entry_table_test.dart` pumps the table at every detail level and
density in a window narrower than the widest column set. The table lays itself
out by hand, and that kind of layout fails by throwing during a render pass at
a size nobody happened to try.

124 tests, all passing.

## Repo hygiene notes

- `app/build/` is large (~334 MB with canvaskit WASM) but **not tracked** —
  `app/.gitignore` covers it with `/build/`. Local clutter only.
- Python bytecode is covered by `.gitignore` (`__pycache__/`).
- The `.sqlite` blob churns a large binary diff on every change, and git can
  never show what moved inside it — `tools/check_incoming_db.py` is how you
  read a change, and `tools/migrate.py`'s list is the only history of the
  schema. It is **no longer regenerable**: see below.
- The source spreadsheet and the commissioning brief are **not tracked**, by
  intention — see "What is deliberately not in this repository" below.

## What is deliberately not in this repository

- **The source spreadsheet** (`Leo2026v 1270s80sDatabase.xlsx`, and the
  earlier `Copy of ...`). `.gitignore` covers `*.xlsx` wholesale: it used to
  name the first file specifically, and the second arrived under a different
  name and would have been committed. The
  researcher's own working file, and not ours to publish. Everything in it
  that the app needs is already in `app/data/*.sqlite`, which is the source of
  truth now — see the next section. Kept locally, ignored by git.
- **The commissioning brief.** Same reason. Describe the requirement in here;
  do not quote the document into the repository.
- **`app/build/`** — rebuilt by CI on every push, ~334 MB with CanvasKit.

`tools/build_normalized_db.py`, `build_review_db.py` and `dump_formulas.py`
read the spreadsheet and so cannot run from a fresh clone. That is intended:
they are provenance for how the 7,501 entries got here, not part of the build.
Everything needed to build and run the app is present.

## The database is the source of truth

This changed once the researcher began logging records of their own, and it
inverts what the ETL is for.

`app/data/1270s80sDatabase_normalized.sqlite` is the artifact of record. The
spreadsheet is provenance for the original 7,501 rows and nothing more — it
cannot restore anything logged since. `build_normalized_db.py` therefore
refuses to run when the database holds entries that have no row in
`excel_cached_calculations` (the marker of having come from the workbook), or
when `user_version` is past 0. `--force` exists for genuinely starting over.

The cycle:

1. The researcher works in the deployed app and downloads a `.sqlite`.
2. They send it over.
3. `check_incoming_db.py` says what changed — entries added, edited, deleted,
   tables and columns gained or lost — and refuses outright on a file that
   will not open, has dangling references, or has had the test oracle edited.
   Git cannot review a 9 MB blob; this is the review.
4. `migrate.py` brings that file up to the current schema, if the schema moved
   while they were logging.
5. Copy it over `app/data/`, commit, push. Pages redeploys code and database
   together.

**Schema changes are numbered steps in `migrate.py`, never hand edits.** A
hand edit lives in one particular file, so the next database the researcher
sends invalidates it and the work is done again — which in practice means
asking them to stop logging until you are finished. A step applies to whatever
file arrives, so the two kinds of update stop being coupled. Append only:
editing a step that has already run changes nothing for anyone who has it, and
everything for a fresh import.

### What each situation looks like

**New records, nothing else.** `check_incoming_db.py` reports `63 entries
added`, nothing else. Copy over `app/data/`, `flutter test`, commit, push. No
migration, no code change.

**Records plus corrections to existing ones.** The report names them — `3
existing entries edited: 12, 340, 5001` — and separately names anything
deleted. This is the case git cannot help with at all: the database is a 9 MB
blob, and a deleted row is invisible in the app afterwards, so this report is
the only place it is ever seen. Nothing fails; whether those edits are wanted
is a judgement.

**A new field, while they are not logging.** Add a step to `migrate.py`, run
it on the repository's database, do the Dart work, commit both together. Code
and schema ship in one build so they cannot disagree.

**A new field, while they keep logging.** The case the design exists for. Do
not touch the repository's database. Write the step, do the Dart work, wait
for their file, then run `check_incoming_db.py` and `migrate.py` on *their*
file — it comes out at the new schema with their entries intact and nobody
froze. Order does not matter either way round: the check reports `schema
version 0, shipped is 1 — run tools/migrate.py before committing`.

**A damaged file.** Exit 1, do not commit. Fatal cases are: will not open,
fails `integrity_check`, dangling references, no entries at all, or
`excel_cached_calculations` altered — that table is the frozen record of what
the spreadsheet computed and the only independent check on the calculation
code, so nothing legitimate ever touches it.

**Somebody runs the ETL.** It stops without deleting anything, naming how many
entries the spreadsheet cannot account for. Silent on a clean database, so a
genuine re-import still works.

### Who can actually run the ETL

Only whoever holds the repository. The researcher uses the deployed site —
they never clone anything and never run Python — and the Pages workflow runs
only `flutter` commands, so no automated path touches it either.

So the guard protects against exactly one person: the maintainer, months
later, running a command the README used to call routine and CLAUDE.md used to
call "fully regenerable from the spreadsheet". Correcting those two sentences
was probably the larger safety fix; the guard is the belt to that pair of
braces.

And git is the real backstop — the `.sqlite` is tracked, so a destroyed
database is a `git checkout` away. **The one exception is the window in step 3
above**: their file copied into `app/data/` but not yet committed. Data lost
there is gone for good, because it exists nowhere else — not in the
spreadsheet, not in git history, and their browser copy has moved on. Commit
before doing anything else.

What is deliberately **not** decided yet: what happens to a reader's own
browser copy when a new build ships. Startup prefers the OPFS copy and falls
back to the bundled asset, so a returning reader keeps theirs and never sees
new data; the only way across today is *Start again from the bundled
database*, which discards their work. `user_version` is what a future answer
would key off — it is why the stamp is worth having before that conversation,
not after.

## Conventions

- Comments explain historical / data reasoning, not syntax. Long explanatory
  comments are the house style — keep them.
- Never invent a number the source cannot support. Show `—` and say why.
- Branch: `calculations-in-code`; PRs target `main`.
