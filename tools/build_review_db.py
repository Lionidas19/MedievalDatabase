"""Builds a standalone SQLite file of everything that needs a human decision.

The point is to hand the researcher one file they can open in any SQLite
browser and work through — every inconsistency we hit while reimplementing the
spreadsheet's calculations, with enough provenance to find the original cell,
and blank columns where their answer goes.

Nothing here is a complaint about the data. Most of it is the ordinary residue
of a decade-long research spreadsheet, and several items are the researcher's
own deliberate markers that we simply cannot interpret without asking.

    python tools/build_review_db.py

Writes review/1270s80sDatabase_review.sqlite.
"""
import os
import re
import sys
import sqlite3
import zipfile
from collections import Counter
from xml.etree import ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dimensions

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(_REPO_ROOT, "Copy of 1270s80sDatabase.xlsx")
DB = os.path.join(_REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")
OUT_DIR = os.path.join(_REPO_ROOT, "review")
OUT = os.path.join(OUT_DIR, "1270s80sDatabase_review.sqlite")

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RNS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

MONTHS = {
    "january", "february", "march", "april", "may", "june", "july", "august",
    "september", "october", "november", "december",
    "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct",
    "nov", "dec",
}
SEASONS = {"spring", "summer", "autumn", "fall", "winter"}


# ------------------------------------------------------------ spreadsheet ---
zf = zipfile.ZipFile(SRC)
_wb = ET.fromstring(zf.read("xl/workbook.xml"))
_rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
_rid = {r.get("Id"): r.get("Target") for r in _rels}
SHEETS = {}
for _sh in _wb.iter(f"{NS}sheet"):
    _t = _rid[_sh.get(f"{RNS}id")]
    SHEETS[_sh.get("name")] = ("xl/" + _t.lstrip("/")).replace("xl/xl/", "xl/")

SHARED = []
if "xl/sharedStrings.xml" in zf.namelist():
    _sst = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    for _si in _sst.iter(f"{NS}si"):
        SHARED.append("".join(t.text or "" for t in _si.iter(f"{NS}t")))


def col_ix(ref):
    n = 0
    for ch in ref:
        if ch.isalpha():
            n = n * 26 + (ord(ch.upper()) - 64)
    return n


def sheet_rows(sheet, cols, first_row):
    """{row: {col: value}} for the requested columns."""
    want = set(cols)
    out = {}
    with zf.open(SHEETS[sheet]) as fh:
        for _event, el in ET.iterparse(fh, events=("end",)):
            if el.tag != f"{NS}c":
                continue
            ref = el.get("r") or ""
            digits = "".join(c for c in ref if c.isdigit())
            if digits:
                r, c = int(digits), col_ix(ref)
                if c in want and r >= first_row:
                    v = el.find(f"{NS}v")
                    if v is not None and v.text is not None:
                        out.setdefault(r, {})[c] = (
                            SHARED[int(v.text)] if el.get("t") == "s" else v.text)
            el.clear()
    return out


def as_num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


# --------------------------------------------------------------- schema -----
os.makedirs(OUT_DIR, exist_ok=True)
if os.path.exists(OUT):
    os.remove(OUT)
out = sqlite3.connect(OUT)
out.executescript("""
CREATE TABLE read_me (
    step        INTEGER PRIMARY KEY,
    topic       TEXT,
    explanation TEXT
);

-- One row per kind of problem, with what we need back from you.
CREATE TABLE issue_types (
    code           TEXT PRIMARY KEY,
    title          TEXT NOT NULL,
    affected       INTEGER NOT NULL,
    severity       TEXT NOT NULL,   -- blocking | important | informational
    what_we_found  TEXT NOT NULL,
    why_it_matters TEXT NOT NULL,
    what_we_need   TEXT NOT NULL
);

-- The individual cases. `your_answer` and `your_notes` are for you to fill in.
CREATE TABLE issues (
    issue_id     INTEGER PRIMARY KEY,
    code         TEXT NOT NULL REFERENCES issue_types(code),
    subject      TEXT,      -- the measure name, entry number, etc.
    entry_no     INTEGER,   -- Data sheet 'Entry', where applicable
    sheet        TEXT,      -- where to look in the workbook
    sheet_row    INTEGER,
    detail       TEXT,
    current_value TEXT,
    your_answer  TEXT,
    your_notes   TEXT
);

-- Every unit the Data sheet actually uses, with how often. The metric value
-- is the number all the calculations run on; `dimension` is the column we
-- need from you.
CREATE TABLE measure_worksheet (
    name          TEXT PRIMARY KEY,
    metric_value  REAL,
    times_used    INTEGER NOT NULL,
    used_as       TEXT,      -- quantity / valuation / both
    sheet_row     INTEGER,
    guessed_dimension TEXT,  -- our reading of YOUR conversion columns
    guess_evidence    TEXT,  -- why we read it that way
    dimension     TEXT,      -- <- YOU, only where the guess is wrong or blank
    is_estimate   TEXT,      -- <- YOU: yes/no  (we guessed from '?' markers)
    your_notes    TEXT
);

CREATE TABLE standard_worksheet (
    name         TEXT PRIMARY KEY,
    metric_value REAL,
    times_used   INTEGER NOT NULL,
    used_as      TEXT,       -- output X / output Y / both
    sheet_row    INTEGER,
    guessed_dimension TEXT,
    guess_evidence    TEXT,
    dimension    TEXT,       -- <- YOU, only where the guess is wrong or blank
    your_notes   TEXT
);

-- Where each place is. Empty: the map the brief asks for needs a position for
-- every locality, and the spreadsheet has none.
CREATE TABLE place_worksheet (
    locality    TEXT NOT NULL,
    county      TEXT,
    times_used  INTEGER NOT NULL,
    latitude    REAL,      -- <- YOU
    longitude   REAL,      -- <- YOU
    modern_name TEXT,      -- <- YOU, where the medieval spelling differs
    your_notes  TEXT,
    PRIMARY KEY (locality, county)
);

-- The Month column holds months, seasons and feast days together.
CREATE TABLE time_period_worksheet (
    name         TEXT PRIMARY KEY,
    times_used   INTEGER NOT NULL,
    looks_like   TEXT,       -- our guess
    kind         TEXT,       -- <- YOU: month | season | feast | term | other
    month_number INTEGER,    -- <- YOU, where one applies
    your_notes   TEXT
);
""")

readme = [
    (1, "What this file is",
     "Every inconsistency we found while rebuilding the price database from "
     "your spreadsheet, in one place. Open it in any SQLite browser "
     "(DB Browser for SQLite is free and works well). Start with the "
     "issue_types table."),
    (2, "How to use it",
     "issue_types lists each kind of problem, how many cases there are, and "
     "what we need from you. issues lists the individual cases with the sheet "
     "and row to look at. Columns named your_* are empty and are for your "
     "answers — type straight into them and send the file back."),
    (3, "The worksheets",
     "measure_worksheet, standard_worksheet, time_period_worksheet and "
     "place_worksheet are the big asks. Each lists real values from your "
     "spreadsheet with a few blank columns for you to fill in. These unlock "
     "things the app cannot do safely, or at all, without your knowledge — "
     "place_worksheet is what a map would be built from."),
    (4, "Nothing has been changed",
     "Your spreadsheet is the source of truth and has not been modified. This "
     "file is a set of questions, not a set of corrections."),
    (5, "The most important one",
     "The dimension of each unit. Your Metric Value column mixes grams, "
     "litres, square metres and plain counts, and without knowing which is "
     "which the app cannot tell that 'price per kilogram' is meaningful for "
     "grain but meaningless for cattle counted by the head. We have already "
     "guessed most of them from your own conversion columns — see "
     "dimension_guesses_to_confirm, and correct only what is wrong. "
     "measures_we_could_not_classify lists the ones we could not read."),
]
out.executemany("INSERT INTO read_me VALUES (?,?,?)", readme)


# ---------------------------------------------------------------- gather ----
db = sqlite3.connect(DB)
db.row_factory = sqlite3.Row

issues = []


def add(code, subject=None, entry_no=None, sheet=None, sheet_row=None,
        detail=None, current_value=None):
    issues.append((code, subject, entry_no, sheet, sheet_row, detail,
                   None if current_value is None else str(current_value)))


UNCERTAIN = re.compile(r"[?]")

# --- usage counts -----------------------------------------------------------
measure_usage = Counter()
measure_role = {}
for col, role in (("measure_1_id", "quantity"), ("measure_2_id", "quantity"),
                  ("measure_3_id", "quantity"),
                  ("valuation_measure_id", "valuation")):
    for r in db.execute(
            f"SELECT m.name AS n, COUNT(*) c FROM price_entries pe "
            f"JOIN measures m ON pe.{col} = m.measure_id GROUP BY m.name"):
        measure_usage[r["n"]] += r["c"]
        prev = measure_role.get(r["n"])
        measure_role[r["n"]] = "both" if prev and prev != role else role

standard_usage = Counter()
standard_role = {}
for col, role in (("output_x_standard_id", "output X"),
                  ("output_y_standard_id", "output Y")):
    for r in db.execute(
            f"SELECT s.name AS n, COUNT(*) c FROM price_entries pe "
            f"JOIN standards s ON pe.{col} = s.standard_id GROUP BY s.name"):
        standard_usage[r["n"]] += r["c"]
        prev = standard_role.get(r["n"])
        standard_role[r["n"]] = "both" if prev and prev != role else role

measures = {r["name"]: r for r in db.execute(
    "SELECT name, metric_value, sheet_row FROM measures")}
standards = {r["name"]: r for r in db.execute(
    "SELECT name, metric_value, sheet_row FROM standards")}

# --- undefined / unvalued units --------------------------------------------
for name, used in measure_usage.items():
    m = measures[name]
    if m["metric_value"] is None:
        code = "MEASURE_UNDEFINED" if m["sheet_row"] is None else "MEASURE_NO_METRIC"
        add(code, subject=name, sheet="Measures", sheet_row=m["sheet_row"],
            detail=f"used by {used} entries; contributes 0 to every total")

for name, used in standard_usage.items():
    s = standards[name]
    if s["metric_value"] is None:
        code = "STANDARD_UNDEFINED" if s["sheet_row"] is None else "STANDARD_NO_METRIC"
        add(code, subject=name, sheet="Standards", sheet_row=s["sheet_row"],
            detail=f"used by {used} entries; no price per unit can be produced")

# --- duplicate lookup keys --------------------------------------------------
for sheet, key_col, val_col, first, last in (
        ("Measures", 2, 3, 2, 492), ("Standards", 1, 2, 2, 99)):
    rows = sheet_rows(sheet, [key_col, val_col], first)
    seen = {}
    for r in sorted(rows):
        if r > last:
            continue
        k = rows[r].get(key_col)
        if not isinstance(k, str) or not k.strip():
            continue
        k = k.strip()
        if k in seen:
            first_row, first_val = seen[k]
            add("LOOKUP_DUPLICATE", subject=k, sheet=sheet, sheet_row=r,
                detail=f"also defined at row {first_row} with value "
                       f"{first_val!r}; only the first is ever used",
                current_value=rows[r].get(val_col))
        else:
            seen[k] = (r, rows[r].get(val_col))

# --- uncertainty markers ----------------------------------------------------
uncertain_names = set()
for sheet, key_col, first, last in (("Measures", 2, 2, 492),
                                    ("Standards", 1, 2, 99)):
    rows = sheet_rows(sheet, [key_col], first)
    for r in sorted(rows):
        if r > last:
            continue
        k = rows[r].get(key_col)
        if isinstance(k, str) and UNCERTAIN.search(k):
            uncertain_names.add(k.strip())
            usage = (measure_usage if sheet == "Measures" else standard_usage)
            add("UNCERTAIN_CONVERSION", subject=k.strip(), sheet=sheet,
                sheet_row=r,
                detail=f"contains '?', which reads as an unverified "
                       f"conversion; used by {usage.get(k.strip(), 0)} entries")

# --- entries that cannot produce the headline figure ------------------------
chain = db.execute("""
    SELECT pe.legacy_entry_no AS entry, pe.year,
           COALESCE(m1.metric_value,0)*COALESCE(pe.unit_1,0)
         + COALESCE(m2.metric_value,0)*COALESCE(pe.unit_2,0)
         + COALESCE(m3.metric_value,0)*COALESCE(pe.unit_3,0) AS total,
           pe.unit_1, pe.unit_2, pe.unit_3,
           m1.name AS m1, m1.metric_value AS m1v,
           vm.name AS vm, vm.metric_value AS vmv,
           oy.name AS oy, oy.metric_value AS oyv,
           COALESCE(pe.pounds,0)*240+COALESCE(pe.shillings,0)*12
         + COALESCE(pe.pence,0) AS price,
           pe.multiplier_workers AS mult,
           pl.locality, cat.name AS category,
           c.pence_per_output_y AS cached_per_y, c.errors
    FROM price_entries pe
    LEFT JOIN measures m1 ON pe.measure_1_id = m1.measure_id
    LEFT JOIN measures m2 ON pe.measure_2_id = m2.measure_id
    LEFT JOIN measures m3 ON pe.measure_3_id = m3.measure_id
    LEFT JOIN measures vm ON pe.valuation_measure_id = vm.measure_id
    LEFT JOIN standards oy ON pe.output_y_standard_id = oy.standard_id
    LEFT JOIN places pl ON pe.place_id = pl.place_id
    LEFT JOIN specifics sp ON pe.specific_id = sp.specific_id
    LEFT JOIN subcategories sub ON sp.subcategory_id = sub.subcategory_id
    LEFT JOIN categories cat ON sub.category_id = cat.category_id
    JOIN excel_cached_calculations c ON c.entry_id = pe.entry_id
""").fetchall()

for r in chain:
    e = r["entry"]
    if r["total"] == 0:
        has_qty = any(r[k] is not None for k in ("unit_1", "unit_2", "unit_3"))
        add("NO_QUANTITY", entry_no=e, sheet="Data",
            detail=("quantities are present but none of their measures has a "
                    "metric value" if has_qty
                    else "no quantity recorded in Unit 1/2/3"),
            current_value=f"units={r['unit_1']}/{r['unit_2']}/{r['unit_3']}, "
                          f"measure 1={r['m1']!r}")
    elif r["vmv"] is None:
        add("NO_VALUATION_METRIC", entry_no=e, sheet="Data",
            detail="the valuation measure has no metric value",
            current_value=r["vm"])
    elif r["oyv"] is None:
        add("NO_OUTPUT_METRIC", entry_no=e, sheet="Data",
            detail="the chosen output Y unit has no metric value",
            current_value=r["oy"])
    elif r["price"] == 0:
        add("ZERO_PRICE", entry_no=e, sheet="Data",
            detail="a quantity is recorded but the price is zero or blank")

    if r["year"] is None:
        add("MISSING_YEAR", entry_no=e, sheet="Data",
            detail="no year recorded, so the entry cannot be dated or "
                   "included in any date-range lookup")
    if r["locality"] is None:
        add("MISSING_PLACE", entry_no=e, sheet="Data",
            detail="no locality recorded in the Region column")
    if r["category"] is None:
        add("MISSING_CATEGORY", entry_no=e, sheet="Data",
            detail="no category chain, so the entry cannot be found by item")

# --- where our recomputation disagrees with the sheet -----------------------
def divide(a, b):
    return None if (a is None or not b) else a / b


for r in chain:
    total, vmv, oyv = r["total"], r["vmv"], r["oyv"]
    vc = divide(total, vmv)
    # The multiplier matters: IF(ISBLANK(L), price*count, price*count*L).
    sale = None if vc is None else (
        r["price"] * vc * (r["mult"] if r["mult"] is not None else 1))
    ours = divide(sale, divide(total, oyv))
    cached = r["cached_per_y"]
    if cached is None and ours is not None:
        # We produce a figure where the spreadsheet gave up. Usually means the
        # sheet's own lookup failed on a name that we manage to resolve.
        add("WE_ANSWER_SHEET_DID_NOT", entry_no=r["entry"], sheet="Data",
            detail=f"we compute {ours!r} per output unit, but the spreadsheet "
                   f"cached an error ({r['errors'] or 'no value'})",
            current_value=f"measure 1={r['m1']!r}, valuation={r['vm']!r}")
        continue
    if cached is not None and ours is None:
        add("SHEET_ANSWERED_WE_DO_NOT", entry_no=r["entry"], sheet="Data",
            detail=f"the spreadsheet cached {cached!r} but we cannot produce "
                   f"a figure from the recorded values",
            current_value=f"measure 1={r['m1']!r}, valuation={r['vm']!r}")
        continue
    if cached is None or ours is None:
        continue
    if abs(ours - cached) / max(abs(cached), abs(ours), 1e-12) > 1e-6:
        add("CALCULATION_DISAGREES", entry_no=r["entry"], sheet="Data",
            detail=f"we compute {ours!r} but the spreadsheet cached {cached!r}",
            current_value=r["m1"])

# --- quoted unit names in the Data sheet ------------------------------------
data_units = sheet_rows("Data", [1, 18, 19, 20, 23, 24, 25], 3)
quoted = Counter()
for r, cells in data_units.items():
    for c in (18, 19, 20, 23, 24, 25):
        v = cells.get(c)
        if isinstance(v, str) and '"' in v:
            quoted[v.strip()] += 1
for name, n in quoted.most_common():
    add("QUOTED_UNIT_NAME", subject=name, sheet="Data",
        detail=f"{n} cells wrap the unit name in quotation marks; the "
               f"Measures sheet has no quotes, so these only match once the "
               f"quotes are stripped")

# --- unfilled template rows -------------------------------------------------
# Detected against the spreadsheet, because the import drops these.
tail = sheet_rows("Data", [1, 2, 3, 6, 9, 13, 14, 15, 16, 36], 3)
blank = []
for r in sorted(tail):
    cells = tail[r]
    entry = cells.get(1)
    if entry is None:
        continue
    if not any(str(cells.get(c) or "").strip() for c in (2, 3, 6, 9, 13, 14, 15, 16, 36)):
        blank.append((int(as_num(entry) or 0), r))
if blank:
    add("BLANK_TEMPLATE_ROWS", subject=f"Entry {blank[0][0]}–{blank[-1][0]}",
        sheet="Data", sheet_row=blank[0][1],
        detail=f"{len(blank)} consecutive rows carry dropdown defaults "
               f"('Heads/Units' in all four unit columns, 'UK' for country) "
               f"and nothing else — no year, place, category, quantity or "
               f"price. Rows {blank[0][1]}–{blank[-1][1]} of the Data sheet.",
        current_value=f"{len(blank)} rows")

# --- questions that are not about individual rows ----------------------------
add("PLACES_HAVE_NO_POSITION", subject="244 localities in use", sheet="Places",
    detail="see the place_worksheet table; the fifty most-used cover about "
           "four fifths of the entries")
add("YEAR_MAY_START_AT_LADY_DAY", subject="the Year column", sheet="Data",
    detail="affects any lookup whose range crosses a year boundary")

# --- empty columns ----------------------------------------------------------
for table, label in (("coin_types", "Coin type"),):
    n = db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    if n == 0:
        add("COLUMN_UNUSED", subject=label, sheet="Data",
            detail="the column exists but no entry has a value")

out.executemany(
    "INSERT INTO issues(code, subject, entry_no, sheet, sheet_row, detail, "
    "current_value) VALUES (?,?,?,?,?,?,?)", issues)




# ------------------------------------------------------- dimension guess ----
# The classifier lives in tools/dimensions.py so the ETL and this file cannot
# drift apart on what a unit measures.
def guess_dimension(name, metric_value, targets, vocabulary="measure"):
    dim, why, _source = dimensions.guess(name, metric_value, targets,
                                         vocabulary=vocabulary)
    return dim, why


def targets_for(join_table, join_col, row_id):
    return {r[0] for r in db.execute(
        "SELECT target_name FROM " + join_table + " WHERE " + join_col + " = ?",
        (row_id,))}


# ------------------------------------------------------------ worksheets ----
measure_id_by_name = {r["name"]: r["measure_id"]
                      for r in db.execute("SELECT measure_id, name FROM measures")}
standard_id_by_name = {r["name"]: r["standard_id"]
                       for r in db.execute("SELECT standard_id, name FROM standards")}

for name, used in sorted(measure_usage.items()):
    m = measures[name]
    dim, why = guess_dimension(
        name, m["metric_value"],
        targets_for("measure_conversions", "measure_id",
                    measure_id_by_name[name]))
    out.execute(
        "INSERT INTO measure_worksheet(name, metric_value, times_used, "
        "used_as, sheet_row, guessed_dimension, guess_evidence, is_estimate) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (name, m["metric_value"], used, measure_role.get(name),
         m["sheet_row"], dim, why,
         "yes (guessed from '?')" if name in uncertain_names else None))

for name, used in sorted(standard_usage.items()):
    st = standards[name]
    dim, why = guess_dimension(
        name, st["metric_value"],
        targets_for("standard_conversions", "standard_id",
                    standard_id_by_name[name]),
        vocabulary="standard")
    out.execute(
        "INSERT INTO standard_worksheet(name, metric_value, times_used, "
        "used_as, sheet_row, guessed_dimension, guess_evidence) "
        "VALUES (?,?,?,?,?,?,?)",
        (name, st["metric_value"], used, standard_role.get(name),
         st["sheet_row"], dim, why))

for p in db.execute('''
        SELECT pl.locality AS locality, co.name AS county, COUNT(*) AS c
        FROM price_entries pe
        JOIN places pl ON pe.place_id = pl.place_id
        LEFT JOIN counties co ON pl.county_id = co.county_id
        GROUP BY pl.place_id ORDER BY c DESC'''):
    out.execute(
        "INSERT OR IGNORE INTO place_worksheet(locality, county, times_used) "
        "VALUES (?,?,?)", (p["locality"], p["county"], p["c"]))

periods = db.execute("""
    SELECT tp.name AS n, COUNT(*) c FROM price_entries pe
    JOIN time_periods tp ON pe.time_period_id = tp.time_period_id
    GROUP BY tp.name ORDER BY c DESC""").fetchall()
for p in periods:
    low = p["n"].strip().lower()
    guess = ("month" if low in MONTHS else
             "season" if low in SEASONS else
             "term" if "term" in low else "feast or other")
    out.execute(
        "INSERT INTO time_period_worksheet(name, times_used, looks_like) "
        "VALUES (?,?,?)", (p["n"], p["c"], guess))


# ----------------------------------------------------------- issue types ----
counts = Counter(i[0] for i in issues)
TYPES = [
    ("MEASURE_UNDEFINED", "A measure the Data sheet uses is missing from the Measures sheet",
     "blocking",
     "An entry names a unit of measure that the Measures sheet never defines.",
     "Because there is no metric value, the quantity contributes nothing and "
     "the entry silently prices at zero. Your spreadsheet does exactly the "
     "same thing, so these entries are already blank there.",
     "Either add the measure to the Measures sheet with its metric value, or "
     "tell us which existing measure it should have been."),
    ("MEASURE_NO_METRIC", "A measure exists but has no metric value",
     "blocking",
     "The Measures sheet lists the name but column C (Metric Value) is empty "
     "or not a number.",
     "Same effect as above: any entry using it computes as zero.",
     "Fill in the metric value, or confirm the measure is obsolete."),
    ("STANDARD_UNDEFINED", "An output unit is missing from the Standards sheet",
     "blocking",
     "An entry's OUTPUT X or CHOSEN OUTPUT Y names something the Standards "
     "sheet does not define. Note these are looked up in Standards, not "
     "Measures — they are two separate lists.",
     "No price-per-unit can be produced for the entry.",
     "Add it to Standards, or tell us the correct Standards entry to use."),
    ("STANDARD_NO_METRIC", "An output unit has no metric value",
     "blocking",
     "Listed in Standards but column B is empty or not a number.",
     "No price-per-unit can be produced.",
     "Fill in the metric value."),
    ("LOOKUP_DUPLICATE", "The same name is defined twice, with different values",
     "important",
     "A name appears on two rows of a lookup sheet with different numbers.",
     "Your formulas use MATCH, which stops at the first hit, so the second "
     "row has never had any effect. If the second row is the corrected one, "
     "every calculation using it has been wrong.",
     "Tell us which row is correct, and delete or rename the other."),
    ("UNCERTAIN_CONVERSION", "A conversion marked with '?'",
     "important",
     "20 measure names contain question marks, e.g. 'Garb, Steel [?81 lb?]' "
     "and 'Sum, Fish ??'. We read these as your own note that the conversion "
     "is unverified.",
     "We have treated them as ordinary values. If they are estimates, every "
     "figure derived from them inherits that uncertainty and arguably should "
     "be shown differently.",
     "Confirm what '?' means. If it marks an estimate, we will label those "
     "figures as approximate in the app rather than presenting them as exact."),
    ("NO_QUANTITY", "The entry has no usable quantity",
     "informational",
     "Either Unit 1/2/3 are all empty, or their measures have no metric value.",
     "There is nothing to divide the price by, so no price-per-unit exists. "
     "Your spreadsheet shows #DIV/0! for these.",
     "Nothing needed unless you know the missing quantity. Listed so you can "
     "see the scale of the gap."),
    ("NO_VALUATION_METRIC", "The valuation measure has no metric value",
     "important",
     "The entry names a valuation measure that carries no number.",
     "The total sale price cannot be worked out.",
     "Supply the metric value for the measure named in current_value."),
    ("NO_OUTPUT_METRIC", "The output unit has no metric value",
     "important",
     "The entry's chosen output unit carries no number.",
     "No price-per-unit can be shown for this entry.",
     "Supply the metric value, or choose a different output unit."),
    ("ZERO_PRICE", "A quantity is recorded but the price is zero",
     "informational",
     "Pounds, shillings and pence are all blank or zero while a quantity "
     "exists.",
     "The entry prices at zero, which will drag any average downwards.",
     "Confirm whether the price is genuinely unknown (better left blank) or "
     "was missed during transcription."),
    ("MISSING_YEAR", "No year recorded", "important",
     "The Year column is empty.",
     "The entry cannot be dated, so it never appears in a date-range lookup — "
     "roughly a quarter of the database.",
     "Supply years where you can. Where the source genuinely gives no date, "
     "tell us and we will treat undated entries as a category of their own."),
    ("MISSING_PLACE", "No locality recorded", "informational",
     "The Region column is empty.",
     "The entry cannot be found by place.",
     "Supply the locality where the source gives one."),
    ("MISSING_CATEGORY", "No category recorded", "informational",
     "Category / Subcategory / Specifics are empty.",
     "The entry cannot be found by item, which is how most people will look.",
     "Supply the category chain where you can."),
    ("CALCULATION_DISAGREES", "Our result differs from the spreadsheet's",
     "important",
     "We reimplemented your formulas and compared every entry against the "
     "value your spreadsheet had cached. These are the ones that differ.",
     "Your spreadsheet is the source of truth, so a difference means either "
     "we have misread a formula or the cached value is stale.",
     "Look at the entry and tell us which figure is right."),
    ("BLANK_TEMPLATE_ROWS", "The last 2,579 rows of the Data sheet are empty",
     "important",
     "Rows 7801 to 10379 (Entry 7801-10379) hold nothing but the dropdown "
     "defaults: 'Heads/Units' in Measure 1, Valuation Measure, Output X and "
     "Output Y, and 'UK' for Country. No year, place, category, quantity or "
     "price appears in any of them.",
     "They look like real records to anything counting rows. They made the "
     "database appear to hold 10,379 entries when it holds 7,800, made "
     "'Heads/Units' appear to be the most-used measure in the collection, and "
     "made it look as though a quarter of the data could not be priced. With "
     "them excluded, 7,405 of 7,800 entries price successfully — 95%.",
     "Confirm these are unused rows left over from setting up the sheet. We "
     "currently skip them on import. If any of them are meant to hold data, "
     "tell us and we will stop."),
    ("WE_ANSWER_SHEET_DID_NOT", "We produce a price where the spreadsheet showed an error",
     "important",
     "The spreadsheet cached #DIV/0! or #N/A for this entry, but our "
     "reimplementation resolves the units and produces a number.",
     "Almost always a spelling difference: the entry names a measure the way "
     "the Measures sheet spells it, including its '?' marks, so our lookup "
     "succeeds where the sheet's did not. We would rather show nothing than "
     "show a figure you have not sanctioned.",
     "Check the entry. If the figure is right we will keep it; if the "
     "spreadsheet was right to refuse, tell us and we will suppress it."),
    ("SHEET_ANSWERED_WE_DO_NOT", "The spreadsheet had a price and we do not",
     "blocking",
     "The spreadsheet cached a number but our reimplementation cannot "
     "reproduce one.",
     "This would be a straight regression — a figure your database used to "
     "show that ours does not.",
     "None expected; if any appear here, it is our bug to fix, not yours."),
    ("QUOTED_UNIT_NAME", "Unit names wrapped in quotation marks",
     "informational",
     "16,139 cells in the Data sheet wrap the unit name in quotes, while the "
     "Measures sheet never does.",
     "Your formulas strip the quotes before matching, so this has always "
     "worked. We do the same. Worth knowing because an earlier version of our "
     "import did not, and silently produced 122 duplicate units.",
     "Nothing needed. Listed for completeness."),
    ("PLACES_HAVE_NO_POSITION", "No map is possible without locating the places",
     "important",
     "The brief sketches a map to pick places from. Neither the spreadsheet "
     "nor the database records where any of the localities are. 244 of them "
     "actually appear in the price entries, and the fifty most-used cover "
     "about four fifths of the data.",
     "We will not invent coordinates. Medieval spellings like 'Souendon' and "
     "'Wyllindone' cannot be looked up reliably, and a wrong position in a "
     "research database is worse than none at all.",
     "Fill in latitude and longitude in place_worksheet, most-used first — the "
     "top fifty localities cover most of the entries. Where the medieval "
     "spelling differs from the modern place, the modern_name column helps as "
     "much as the coordinates do."),
    ("YEAR_MAY_START_AT_LADY_DAY", "Which day did the year begin on?",
     "blocking",
     "Medieval English years commonly began on 25 March rather than "
     "1 January, so a record written 'January 1275' may be January 1276 by "
     "modern reckoning.",
     "This shifts a whole year, and it potentially affects every entry — "
     "unlike the Julian/Gregorian difference, which is seven days and touches "
     "only the hundred-odd entries carrying a day of the month. Any date-range "
     "lookup crossing a year boundary is affected.",
     "Tell us which convention Thorold Rogers used, and whether the years in "
     "your Year column are as he printed them or already adjusted. Until then "
     "the app shows years exactly as recorded and says it has not adjusted "
     "them."),
    ("COLUMN_UNUSED", "A column is defined but never filled in",
     "informational",
     "The column exists in the sheet and in the database but no entry uses it.",
     "Harmless, but it appears as an empty field in the editor.",
     "Tell us whether to keep it, in case you intend to use it later."),
]
for code, title, severity, found, matters, need in TYPES:
    out.execute(
        "INSERT INTO issue_types(code, title, affected, severity, "
        "what_we_found, why_it_matters, what_we_need) VALUES (?,?,?,?,?,?,?)",
        (code, title, counts.get(code, 0), severity, found, matters, need))

out.executescript("""
CREATE VIEW summary AS
SELECT severity, code, title, affected
FROM issue_types WHERE affected > 0
ORDER BY CASE severity WHEN 'blocking' THEN 1 WHEN 'important' THEN 2
                       ELSE 3 END, affected DESC;

CREATE VIEW things_to_answer AS
SELECT t.severity, t.code, t.title, t.what_we_need, i.subject, i.entry_no,
       i.sheet, i.sheet_row, i.detail, i.current_value
FROM issues i JOIN issue_types t ON i.code = t.code
WHERE t.severity IN ('blocking', 'important')
ORDER BY CASE t.severity WHEN 'blocking' THEN 1 ELSE 2 END, t.code, i.entry_no;

CREATE VIEW measures_we_could_not_classify AS
SELECT name, metric_value, times_used, used_as, guess_evidence, is_estimate
FROM measure_worksheet
WHERE dimension IS NULL AND guessed_dimension IS NULL
ORDER BY times_used DESC;

-- Everything we did guess, most-used first, for a quick confirmation pass.
CREATE VIEW dimension_guesses_to_confirm AS
SELECT 'measure' AS kind, name, metric_value, times_used, guessed_dimension,
       guess_evidence
FROM measure_worksheet WHERE guessed_dimension IS NOT NULL
UNION ALL
SELECT 'standard', name, metric_value, times_used, guessed_dimension,
       guess_evidence
FROM standard_worksheet WHERE guessed_dimension IS NOT NULL
ORDER BY times_used DESC;
""")

out.commit()

print(f"wrote {OUT}")
print()
print(f"{'severity':<14}{'issue':<26}{'cases':>7}")
for row in out.execute("SELECT severity, code, affected FROM summary"):
    print(f"{row[0]:<14}{row[1]:<26}{row[2]:>7}")
print()
print(f"measure_worksheet     {out.execute('SELECT COUNT(*) FROM measure_worksheet').fetchone()[0]:>5} units to label")
print(f"standard_worksheet    {out.execute('SELECT COUNT(*) FROM standard_worksheet').fetchone()[0]:>5} units to label")
print(f"time_period_worksheet {out.execute('SELECT COUNT(*) FROM time_period_worksheet').fetchone()[0]:>5} periods to label")
print(f"issues                {out.execute('SELECT COUNT(*) FROM issues').fetchone()[0]:>5} rows")
print(f"size                  {os.path.getsize(OUT)/1024:>5.0f} KB")
out.close()
db.close()
