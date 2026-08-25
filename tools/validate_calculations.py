"""Validates the recovered calculation chain against the spreadsheet.

Two jobs:

  1. Recompute every derived value in Python, straight from the rebuilt
     schema, and compare it to what Google Sheets cached. This checks that the
     database carries everything a calculation needs and that the formulas in
     tools/CALCULATIONS.md were read correctly.

  2. Emit app/test/fixtures/calculation_corpus.csv so the Dart implementation
     in app/lib/services/pricing.dart can be held to the same standard by
     `flutter test`, with no database or browser involved.

    python tools/validate_calculations.py

The spreadsheet is the source of truth: a disagreement here is a bug in our
reimplementation, not a finding about the data.
"""
import csv
import os
import sqlite3

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(_REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")
CORPUS = os.path.join(_REPO_ROOT, "app", "test", "fixtures", "calculation_corpus.csv")

# Cached values are rounded to about ten significant figures, so compare
# relatively. See "Pasted values vs live formulas" in tools/CALCULATIONS.md.
TOLERANCE = 1e-6

QUERY = """
SELECT pe.legacy_entry_no                                   AS entry,
       pe.unit_1 AS u1, m1.metric_value AS v1,
       pe.unit_2 AS u2, m2.metric_value AS v2,
       pe.unit_3 AS u3, m3.metric_value AS v3,
       vm.metric_value AS valuation,
       ox.metric_value AS out_x,
       oy.metric_value AS out_y,
       pe.pounds AS l, pe.shillings AS s, pe.pence AS d,
       pe.multiplier_workers AS mult,
       c.total_grams                      AS x_total,
       c.val_meas_number                  AS x_val_count,
       c.val_meas_price_per_numb_in_pence AS x_price,
       c.total_sale_in_pence              AS x_sale,
       c.output_x_value                   AS x_out_x,
       c.pence_per_output_y               AS x_per_y
FROM price_entries pe
LEFT JOIN measures  m1 ON pe.measure_1_id         = m1.measure_id
LEFT JOIN measures  m2 ON pe.measure_2_id         = m2.measure_id
LEFT JOIN measures  m3 ON pe.measure_3_id         = m3.measure_id
LEFT JOIN measures  vm ON pe.valuation_measure_id = vm.measure_id
LEFT JOIN standards ox ON pe.output_x_standard_id = ox.standard_id
LEFT JOIN standards oy ON pe.output_y_standard_id = oy.standard_id
JOIN excel_cached_calculations c ON c.entry_id = pe.entry_id
ORDER BY pe.legacy_entry_no
"""


def divide(numerator, denominator):
    """The sheet's division: a missing or zero divisor has no answer."""
    if numerator is None or not denominator:
        return None
    return numerator / denominator


def calculate(r):
    """The chain from tools/CALCULATIONS.md. Mirrors pricing.dart exactly."""
    # Each term guarded individually: an undefined measure contributes zero.
    total = ((r["v1"] or 0) * (r["u1"] or 0)
             + (r["v2"] or 0) * (r["u2"] or 0)
             + (r["v3"] or 0) * (r["u3"] or 0))
    price = (r["l"] or 0) * 240 + (r["s"] or 0) * 12 + (r["d"] or 0)
    val_count = divide(total, r["valuation"])
    sale = None if val_count is None else price * val_count * (
        r["mult"] if r["mult"] is not None else 1)
    out_x_value = divide(total, r["out_x"])
    per_y = divide(sale, divide(total, r["out_y"]))
    return {
        "total": total, "price": price, "val_count": val_count,
        "sale": sale, "out_x": out_x_value, "per_y": per_y,
    }


def close_enough(got, want):
    if want is None:
        return True          # the sheet cached an error; nothing to compare
    if got is None:
        return False
    scale = max(abs(want), abs(got), 1e-12)
    return abs(got - want) / scale < TOLERANCE


conn = sqlite3.connect(DB)
conn.row_factory = sqlite3.Row
rows = conn.execute(QUERY).fetchall()

FIELDS = [("total", "x_total"), ("price", "x_price"), ("val_count", "x_val_count"),
          ("sale", "x_sale"), ("out_x", "x_out_x"), ("per_y", "x_per_y")]

agree = {k: 0 for k, _ in FIELDS}
differ = {k: 0 for k, _ in FIELDS}
uncached = {k: 0 for k, _ in FIELDS}
offenders = []

for r in rows:
    got = calculate(r)
    row_bad = []
    for key, cached_col in FIELDS:
        want = r[cached_col]
        if want is None:
            uncached[key] += 1
            continue
        if close_enough(got[key], want):
            agree[key] += 1
        else:
            differ[key] += 1
            row_bad.append((key, got[key], want))
    if row_bad:
        offenders.append((r["entry"], row_bad))

print(f"entries checked: {len(rows)}")
print()
print(f"{'value':<12}{'agree':>8}{'differ':>8}{'no cached':>11}{'match':>10}")
for key, _ in FIELDS:
    a, d, u = agree[key], differ[key], uncached[key]
    rate = f"{a / (a + d) * 100:.2f}%" if (a + d) else "n/a"
    print(f"{key:<12}{a:>8}{d:>8}{u:>11}{rate:>10}")

print()
if offenders:
    print(f"entries that disagree: {len(offenders)}")
    for entry, bad in offenders[:10]:
        print(f"  entry {entry}")
        for key, g, w in bad:
            print(f"     {key:<10} computed={g!r}  spreadsheet={w!r}")
else:
    print("no disagreements")

# ------------------------------------------------------- Dart test corpus ---
os.makedirs(os.path.dirname(CORPUS), exist_ok=True)
COLUMNS = ["entry", "u1", "v1", "u2", "v2", "u3", "v3", "valuation", "out_x",
           "out_y", "l", "s", "d", "mult", "x_total", "x_val_count", "x_price",
           "x_sale", "x_out_x", "x_per_y"]

with open(CORPUS, "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(COLUMNS)
    for r in rows:
        w.writerow(["" if r[c] is None else repr(float(r[c])) if isinstance(r[c], (int, float)) else r[c]
                    for c in COLUMNS])

size_kb = os.path.getsize(CORPUS) / 1024
print()
print(f"wrote {CORPUS} ({len(rows)} rows, {size_kb:.0f} KB)")
print("  -> app/test/calculation_corpus_test.dart holds pricing.dart to the same standard")
conn.close()
