# Recovered calculation spec

The spreadsheet is the source of truth. Its derived columns were computed by
formulas that `build_normalized_db.py` discarded — it loads the workbook with
`data_only=True`, which reads cached *values* only. This document is the
recovered method, so the calculations can live in application code instead of
being frozen into the SQLite as precomputed columns.

Regenerate the raw evidence with `python tools/dump_formulas.py`.

## Where the formulas were hiding

The workbook is a **Google Sheets export**. Google functions Excel cannot
evaluate (`REGEXREPLACE`) are exported wrapped as:

```
=IFERROR(__xludf.DUMMYFUNCTION("<the real formula>"), <cached value>)
```

The outer `IFERROR` and `DUMMYFUNCTION` are export packaging, **not** logic.
The real formula is the string literal inside; the second argument is the
value Google last computed. Both are useful: the string is the method, the
cached value is the oracle to validate a reimplementation against.

## The two lookup vocabularies

The calculations resolve unit names against two *different* sheets, which are
effectively disjoint (488 vs 98 keys, only 3 shared):

| Sheet | Key column | Value column | Keys | Used by |
|---|---|---|---|---|
| `Measures` | `B` (MEASURE) | `C` (**Metric Value**) | 488 | MEASURE 1/2/3, Valuation Measure |
| `Standards` | `A` (MEASURE) | `B` (**Metric**) | 98 | OUTPUT X, CHOSEN OUTPUT Y |

Verified against the Data sheet:

| Data column | distinct values | resolve in Measures | resolve in Standards |
|---|---|---|---|
| MEASURE 1 | 134 | 133 | 1 |
| MEASURE 2 | 24 | 24 | 1 |
| MEASURE 3 | 6 | 6 | 0 |
| Valuation Measure | 125 | 124 | 1 |
| OUTPUT X | 4 | 1 | 4 |
| CHOSEN OUTPUT Y | 14 | 2 | 13 |

> **Schema implication.** `build_normalized_db.py` funnels all six columns
> through one `get_or_create_unit()` into a single `units` table. That merges
> two unrelated vocabularies, which makes a code-side lookup ambiguous. They
> need to be separate dimensions.

The value columns are **not** all grams despite the `total_grams` / `val_grams`
column names — they are a metric base per dimension (Acre → 4046.85 *square
metres*, Litres → 1). Treat them as "metric value", not mass.

## Lookup semantics to replicate exactly

- **First match wins.** `MATCH(..., 0)` returns the first hit. `Measures!B`
  has 490 rows / 488 distinct keys — `Hundred, Sawing [120 ft]` and
  `Sack, Wool (Standard) [364 lb]` each appear twice with different values.
- **Key normalisation** is `REGEXREPLACE(TEXT(x,"@"), "\"", "")` — coerce to
  text, strip double quotes. This is **not** cosmetic. No *lookup* key
  contains a quote, but Data-sheet cells do: the pre-2026 build skipped this
  step and produced 122 quoted names out of 752 in its `units` table, many of
  them duplicates of the same measure in both spellings
  (`Tun, Wine [252 gal]` appeared twice). Because `Measures!B` holds no
  quotes, every one of those quoted rows was permanently unmatchable. Strip
  the quotes before matching.
- **Non-numeric values exist** in both value columns: `Measures!C` has 465
  numeric, 3 blank, 20 text; `Standards!B` has 97 numeric and 1 text (the
  `Units` → `Grams/Units/Sq Metres` sub-header row). Treat non-numeric as
  unresolved.

## The calculation chain

Column letters are Data-sheet columns.

```
I,J,K   UNIT 1/2/3            quantities        (raw)
R,S,T   MEASURE 1/2/3         → Measures!C      (raw)
L       Multiplier/Workers                      (raw)
M,N,O   Pounds/Shillings/Pence                  (raw)
W       Valuation Measure     → Measures!C      (raw)
X       OUTPUT X              → Standards!B     (raw)
Y       CHOSEN OUTPUT Y       → Standards!B     (raw)
```

```
V  Total Grams          = IFERROR(measures(R) * I, 0)
                        + IFERROR(measures(S) * J, 0)
                        + IFERROR(measures(T) * K, 0)

AA Val Grams            = measures(W)

AB Sales Calc           = V / AA

AC Price in Pence       = M*240 + N*12 + O

AD Total Sale in Pence  = IF(ISBLANK(L), AC * AB, AC * AB * L)

Z  Output X Value       = V / standards(X)

AE Pence per Output Y   = AD / (V / standards(Y))
```

Note the error handling, which is load-bearing:

- In `V`, each of the three terms is **individually** wrapped in `IFERROR(…, 0)`,
  so an unresolvable measure contributes zero rather than poisoning the row.
- `AA`, `Z` and `AE` have **no** error guard in the original. When `V` is 0,
  `AE` is `#DIV/0!` — which is precisely what 2,941 rows cache. That is the
  source's own answer for those rows, not a bug to paper over, and it explains
  why `pence_per_output_y` is populated for only 7,405 of 10,379 rows.

## Known gaps in the source

- `Garb, Steel [81 lb]` appears in MEASURE 1 and Valuation Measure but is
  absent from `Measures!B`, so those rows contribute 0 to Total Grams.
- One CHOSEN OUTPUT Y value resolves only in `Measures`, not `Standards`,
  so its `AE` cannot compute.
- Column `U` (Multiplier/Workers Measure, 819 values) is referenced by **no
  formula**. The multiplier `L` is used raw. The ETL still stores it as
  `multiplier_workers_measure_id`; it is decorative.
- Column `Q` ("Food", 171 values) is unused by both the formulas and the ETL.

## Reconciliation with the client brief

The researcher who built the workbook supplied a description of it ("Leo
info"). It confirms the recovered chain and supplies far better names than
the sheet headers, but contradicts the formulas on one point.

### Confirmed, with names worth adopting

| Sheet header | Client's name | Recovered formula |
|---|---|---|
| Val Grams (AA) | **Val Meas in Grams** | `measures(Valuation Measure)` |
| Sales Calc (AB) | **Val Meas Number** | `Total Grams / Val Meas in Grams` |
| Price in Pence (AC) | **Val Meas Price per Numb in Pence** | `£×240 + s×12 + d` |
| Total Sale in Pence (AD) | Total Sale in Pence | `AC × AB × multiplier` |

Two numeric fingerprints confirm the chain independently: the brief says
"1 quarter is (usually) 279931.4427 grams", which is the cached value of
`AA3`; and "4 shillings 4 pence … translates to 52 pence", which is `AC3`.

The brief also confirms two columns are dead weight — Multiplier Workers
Measure ("a likely unnecessary column") and the Places unit-override matrix
("not referenced by the data"), matching the formula evidence. The ETL still
materialises the latter as 390 `place_unit_overrides` rows; they are a
data-entry aid, not a calculation input.

Crucially, the brief notes £/s/d "are often unit prices NOT the total price
(think of it like someone's hourly wage rather than their pay slip)". That is
why Total Sale multiplies by Val Meas Number — the recorded price is per
valuation measure, not per entry.

### Contradicted by the formulas

The brief states Standards "is not referenced by the database" and that Output
X / Output Y are "Defined by Measures Tab". **Both are wrong.** `Z` and `AE`
resolve Output X and CHOSEN OUTPUT Y against `Standards!A:A`, not Measures.

The brief further states Standards is an abridged copy — "everything here is
listed in Measures somewhere". It is not:

- by name, 3 of 586 keys are shared;
- by value, only 28 of 97 Standards entries appear in `Measures!C`, and
  several of those are coincidental collisions on `1.0`;
- **69 of 97 have no counterpart at all**, including Kilograms, Wheat Grain,
  Barley Grain and the entire Tower Pennyweight → Quarter ladder.

Where names genuinely overlap (`Old English Mile`, `Tudor Mile`,
`Heads/Units`) the values agree, so there is no conflict to resolve — but
Standards is independent, unique and load-bearing, and must be modelled as its
own dimension rather than merged into `units`.

### Output Y is a query parameter, not a stored fact

The brief describes User Output Y as the control a reader changes to ask "what
is that in modern kilograms or US pounds?" — a per-query choice, not a
property of the record. The stored per-row value is best treated as a
*default* that the UI can override. This is the clearest argument for moving
the calculations into code: `pence_per_output_y` cannot be a stored column if
the unit it is "per" is chosen by the reader.

The `Formula` sheet sketches the intended query UI, and it is close to what
`simple_view.dart` already renders:

```
In [Country] [Region] [Locality]
Between The Year [1270] and [June] [1271]
[Food] [Grain] [Wheat]
was valued at how many... [Pence] Per [Units]     <-- the missing control
Return as [Mean Average]
GENERATE RESULTS
```

Only the `Per [Units]` selector is absent from the current app. The sheet also
carries "CACTUS VERSION" and "NOT AS CACTUS" variants of the same sentence,
and runs to row 708 — there is more design intent in it than the excerpt
above, worth reading before reworking the query UI.

### Described but not yet in the data

- **UKP 2026 conversions** (three columns keyed off a `Currency` tab). No such
  columns exist in the Data sheet, and the `Currency` sheet contains **zero
  non-empty cells** — it is an empty XML skeleton. This is a planned feature
  with no data behind it yet; the inflation/conversion factors still have to
  be sourced before it can be built.
- **Julian/Gregorian handling.** The brief wants a calendar toggle; the `Dates`
  sheet was abandoned because Google Sheets clamps pre-1899 dates.
- **Month column overloading.** It holds months, seasons and feast days
  together ("Michaelmas Term", "Autumn"), which the ETL faithfully reproduces
  as 67 mixed `time_periods` rows. The brief flags it as needing a split.
- **Food column** (`Q`, 171 values) — payment in kind. Unused by formulas and
  by the ETL; the brief suggests splitting it into two columns.

## Pasted values vs live formulas — resolved, no action needed

`AB`, `AC` and `AD` are live formulas in **row 3 only**; every other row holds
a pasted static value. Seven rows appeared to disagree with the sheet's own
`M*240 + N*12 + O`, which looked like the source contradicting itself.

It is not. All seven differ by at most **3.3e-08 absolute / 3.0e-10 relative** —
Google Sheets wrote the cached value rounded to ten significant digits
(`188.3333333`) where the exact result is `188.33333333333334`. That is
float formatting, not a data disagreement. Compute from the formula and
compare with a relative tolerance; there is no editorial decision to make.

## Validation status

The chain above, recomputed in SQL directly from the rebuilt schema and
compared against `excel_cached_calculations`, agrees with Google Sheets on
**10,378 of 10,379 entries** for all seven derived values (relative tolerance
1e-6). Match rates: total grams, val meas in grams, price in pence and pence
per output Y at 100.00%; val meas number, total sale and output X value at
99.99%.

The single divergence is **entry 7292**, and it is a source-data question
rather than a code one. `Measures` row 87 is named
`Garb, Steel [?81 lb?]` — with two literal ASCII question marks (0x3F). Most
Data rows spell it `Garb, Steel [81 lb]`, which matches nothing and therefore
contributes zero, in the spreadsheet and here alike. Entry 7292 is the lone
row that uses the `?` spelling, so it resolves to 36741.00185 for us, while
the spreadsheet still cached 0 for Total Grams and `#DIV/0!` for Pence per
Output Y.

Worth asking the researcher what that row is meant to say before deciding how
the calculator should treat it. Until then it is a known, isolated 0.01%
divergence, not a regression.
