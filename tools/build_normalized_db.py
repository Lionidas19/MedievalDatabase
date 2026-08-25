"""Rebuilds the SQLite database from the source spreadsheet.

The spreadsheet is the source of truth; this script only ever reads it. The
database it produces holds *recorded facts only* -- every value the sheet
derived by formula is left out, to be computed in application code instead.
The recovered formulas are documented in tools/CALCULATIONS.md.

Two things here are easy to get wrong and are called out in the schema below:

  * MEASURE 1/2/3 and Valuation Measure are looked up in the Measures sheet,
    but OUTPUT X and CHOSEN OUTPUT Y are looked up in Standards. Those are
    two distinct vocabularies -- 586 names, 3 of them shared -- and 69 of the
    97 Standards entries have no counterpart in Measures at all. They get
    separate tables; merging them loses data the calculations depend on.

  * A name used by the Data sheet that is missing from its lookup sheet is
    still inserted, with metric_value NULL. That preserves what the record
    actually says and reproduces the sheet's own behaviour: an unresolvable
    measure contributes zero rather than failing the row.

    pip install openpyxl
    python tools/build_normalized_db.py
"""
import os
import sys
import sqlite3
import uuid
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import openpyxl

import dimensions

# Paths are relative to the repo root (this script lives in tools/).
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(_REPO_ROOT, "Copy of 1270s80sDatabase.xlsx")
OUT = os.path.join(_REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")

# Last populated row of each sheet.
PLACES_LAST_ROW = 711
CATEGORIES_LAST_ROW = 592
MEASURES_LAST_ROW = 492
STANDARDS_LAST_ROW = 99
DATA_FIRST_ROW = 3
DATA_LAST_ROW = 10381

if os.path.exists(OUT):
    os.remove(OUT)

# read_only streams the sheets instead of building a cell object per cell,
# which turns a multi-minute load into a few seconds. data_only gives us the
# cached results rather than the formula text.
wb = openpyxl.load_workbook(SRC, data_only=True, read_only=True)


def new_id():
    return str(uuid.uuid4())


def rows_of(sheet, first_row, last_row):
    """Streams (row_number, values_tuple). Indices into the tuple are 0-based,
    so spreadsheet column N is values[N - 1]."""
    ws = wb[sheet]
    for i, values in enumerate(
        ws.iter_rows(min_row=first_row, max_row=last_row, values_only=True),
        start=first_row,
    ):
        yield i, values


def at(values, col):
    """Spreadsheet column number -> value, tolerating short rows."""
    return values[col - 1] if len(values) >= col else None


def as_num(v):
    """Numbers only. Some cells hold cached formula-error text ('#N/A',
    '#DIV/0!') in otherwise numeric columns; those are not values."""
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def as_int(v):
    n = as_num(v)
    return int(n) if n is not None else None


def as_text(v):
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def norm_key(v):
    """The normalisation the sheet's formulas apply before MATCH():
    REGEXREPLACE(TEXT(x,"@"), '"', '') -- coerce to text, strip quotes."""
    s = as_text(v)
    return s.replace('"', "").strip() if s else None


# ---------------------------------------------------------------- schema ----
conn = sqlite3.connect(OUT)
conn.execute("PRAGMA foreign_keys = ON")
cur = conn.cursor()

cur.executescript("""
CREATE TABLE counties (
    county_id   TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE places (
    place_id    TEXT PRIMARY KEY,
    county_id   TEXT REFERENCES counties(county_id),
    locality    TEXT NOT NULL,

    -- Empty, and deliberately so. The brief asks for a map to pick places
    -- from, which needs a position for each of these 789 localities. The
    -- spreadsheet has none, and medieval spellings like 'Souendon' or
    -- 'Wyllindone' cannot be looked up reliably — identifying them is
    -- research, not programming. The columns exist so the answers have
    -- somewhere to go; see review/, place_worksheet.
    latitude    REAL,
    longitude   REAL,

    UNIQUE(county_id, locality)
);

CREATE TABLE categories (
    category_id TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE subcategories (
    subcategory_id TEXT PRIMARY KEY,
    category_id    TEXT NOT NULL REFERENCES categories(category_id),
    name           TEXT NOT NULL,
    UNIQUE(category_id, name)
);

CREATE TABLE specifics (
    specific_id    TEXT PRIMARY KEY,
    subcategory_id TEXT NOT NULL REFERENCES subcategories(subcategory_id),
    name           TEXT NOT NULL,
    UNIQUE(subcategory_id, name)
);

-- The Measures sheet: historic units of measurement, and what one of each is
-- worth in metric. Keyed on Measures!B, valued from Measures!C "Metric Value".
-- Despite the old total_grams/val_grams column names the value is metric per
-- dimension, not mass -- an acre is 4046.85 square metres.
-- Used by: MEASURE 1/2/3, Valuation Measure.
CREATE TABLE measures (
    measure_id   TEXT PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    metric_value REAL,      -- NULL when the sheet has no usable number
    sheet_row    INTEGER,   -- provenance back into Measures

    -- What kind of thing this measures: mass, volume, area, length, count, or
    -- 'per-unit' for the sheet's own normalisers. PROVISIONAL: worked out from
    -- the researcher's conversion columns (tools/dimensions.py) and not yet
    -- confirmed by them. dimension_source records how sure we are.
    dimension        TEXT,
    dimension_source TEXT   -- read | guessed | none
);

-- The Standards sheet: an independent vocabulary, NOT an abridged copy of
-- Measures (69 of its 97 entries appear nowhere in Measures). Keyed on
-- Standards!A, valued from Standards!B "Metric".
-- Used by: OUTPUT X, CHOSEN OUTPUT Y.
CREATE TABLE standards (
    standard_id  TEXT PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    metric_value REAL,
    sheet_row    INTEGER,
    dimension        TEXT,   -- see measures.dimension; equally provisional
    dimension_source TEXT
);

-- The remaining columns of each sheet, in long form. No calculation reads
-- these -- only the metric_value above is load-bearing -- but they are part
-- of the source and may support alternative output units later.
CREATE TABLE measure_conversions (
    conversion_id TEXT PRIMARY KEY,
    measure_id    TEXT NOT NULL REFERENCES measures(measure_id),
    target_name   TEXT NOT NULL,
    value         REAL
);

CREATE TABLE standard_conversions (
    conversion_id TEXT PRIMARY KEY,
    standard_id   TEXT NOT NULL REFERENCES standards(standard_id),
    target_name   TEXT NOT NULL,
    value         REAL
);

-- Region-specific unit definitions from the Places sheet. The researcher's
-- brief describes this sheet as a data-entry aid that "is not referenced by
-- the data", and no formula reads it. Retained as reference only.
CREATE TABLE place_measure_overrides (
    override_id TEXT PRIMARY KEY,
    place_id    TEXT NOT NULL REFERENCES places(place_id),
    measure_id  TEXT NOT NULL REFERENCES measures(measure_id),
    definition  TEXT
);

CREATE TABLE sources (
    source_id   TEXT PRIMARY KEY,
    citation    TEXT NOT NULL UNIQUE
);

CREATE TABLE countries (
    country_id  TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE coin_types (
    coin_type_id TEXT PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE
);

-- Covers both calendar months ('May') and the non-month time references the
-- sheet also used in this column ('Michaelmas Term', 'Autumn', 'Christmas').
CREATE TABLE time_periods (
    time_period_id TEXT PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE
);

-- What the Multiplier/Workers count refers to. No formula reads this; the
-- brief calls it "a likely unnecessary column". Kept because it is recorded.
CREATE TABLE multiplier_measures (
    multiplier_measure_id TEXT PRIMARY KEY,
    name                  TEXT NOT NULL UNIQUE
);

-- Recorded facts only. Every column the spreadsheet derived by formula --
-- Total Grams, Val Meas in Grams, Val Meas Number, Val Meas Price per Numb
-- in Pence, Total Sale in Pence, Output X Value, Pence per Output Y -- is
-- deliberately absent and belongs in application code. Pence per Output Y in
-- particular cannot be stored: the unit it is "per" is chosen by the reader.
CREATE TABLE price_entries (
    entry_id              TEXT PRIMARY KEY,
    legacy_entry_no       INTEGER,
    year                  INTEGER,
    time_period_id        TEXT REFERENCES time_periods(time_period_id),
    day_of_month          INTEGER,
    place_id              TEXT REFERENCES places(place_id),
    specific_id           TEXT REFERENCES specifics(specific_id),

    -- quantities, each interpreted by the measure in the matching slot
    unit_1                REAL,
    unit_2                REAL,
    unit_3                REAL,
    measure_1_id          TEXT REFERENCES measures(measure_id),
    measure_2_id          TEXT REFERENCES measures(measure_id),
    measure_3_id          TEXT REFERENCES measures(measure_id),

    multiplier_workers    REAL,
    multiplier_measure_id TEXT REFERENCES multiplier_measures(multiplier_measure_id),

    -- the recorded price. Often a *unit* price rather than a total, which is
    -- why the total sale multiplies by the valuation-measure count.
    pounds                REAL,
    shillings             REAL,
    pence                 REAL,

    valuation_measure_id  TEXT REFERENCES measures(measure_id),
    output_x_standard_id  TEXT REFERENCES standards(standard_id),
    output_y_standard_id  TEXT REFERENCES standards(standard_id),

    status_info           TEXT,
    food                  TEXT,   -- payment in kind, where it was not in coin
    country_id            TEXT REFERENCES countries(country_id),
    coin_type_id          TEXT REFERENCES coin_types(coin_type_id),
    information           TEXT,
    source_id             TEXT REFERENCES sources(source_id),
    page                  INTEGER
);

-- What Google Sheets last computed for the derived columns. NOT authoritative
-- and not read by the app: retained so the reimplementation can be validated
-- row by row against it (tools/CALCULATIONS.md). Drop once it agrees.
CREATE TABLE excel_cached_calculations (
    entry_id                         TEXT PRIMARY KEY REFERENCES price_entries(entry_id),
    total_grams                      REAL,
    val_meas_in_grams                REAL,
    val_meas_number                  REAL,
    val_meas_price_per_numb_in_pence REAL,
    total_sale_in_pence              REAL,
    output_x_value                   REAL,
    pence_per_output_y               REAL,
    -- cells that cached an error string instead of a number, e.g.
    -- 'pence_per_output_y=#DIV/0!'
    errors                           TEXT
);

CREATE INDEX idx_price_entries_place ON price_entries(place_id);
CREATE INDEX idx_price_entries_specific ON price_entries(specific_id);
CREATE INDEX idx_price_entries_year ON price_entries(year);
CREATE INDEX idx_price_entries_time_period ON price_entries(time_period_id);
CREATE INDEX idx_price_entries_country ON price_entries(country_id);
CREATE INDEX idx_price_entries_measure_1 ON price_entries(measure_1_id);
CREATE INDEX idx_price_entries_valuation ON price_entries(valuation_measure_id);
CREATE INDEX idx_price_entries_output_y ON price_entries(output_y_standard_id);
CREATE INDEX idx_measure_conversions_measure ON measure_conversions(measure_id);
CREATE INDEX idx_standard_conversions_standard ON standard_conversions(standard_id);
CREATE INDEX idx_place_overrides_place ON place_measure_overrides(place_id);
CREATE INDEX idx_subcategories_category ON subcategories(category_id);
CREATE INDEX idx_specifics_subcategory ON specifics(subcategory_id);
""")

# ------------------------------------------------------------- lookups ------
county_ids = {}              # name -> id
place_ids = {}               # (county_name_or_None, locality) -> id
locality_index = {}          # locality -> place_id, for Data sheet joins
category_ids = {}            # name -> id
subcategory_ids = {}         # (category_id, name) -> id
specific_ids = {}            # (subcategory_id, name) -> id
measure_ids = {}             # name -> id
standard_ids = {}            # name -> id
source_ids = {}
country_ids = {}
coin_type_ids = {}
time_period_ids = {}
multiplier_measure_ids = {}

stats = Counter()
dropped_duplicates = []      # (sheet, name) rows MATCH() would never reach
# Names used somewhere but never defined in their lookup sheet, tagged with
# where they were used. Only the ones used by Data affect a calculation; the
# Places ones are column headers on a reference-only sheet.
invented_measures = {}       # name -> 'Data' | 'Places'
invented_standards = {}      # name -> 'Data'


def _get_or_create(cache, table, id_col, name_col, name):
    name = as_text(name)
    if name is None:
        return None
    if name not in cache:
        uid = new_id()
        cache[name] = uid
        cur.execute(
            f"INSERT INTO {table}({id_col}, {name_col}) VALUES (?, ?)", (uid, name)
        )
    return cache[name]


def get_or_create_country(name):
    return _get_or_create(country_ids, "countries", "country_id", "name", name)


def get_or_create_coin_type(name):
    return _get_or_create(coin_type_ids, "coin_types", "coin_type_id", "name", name)


def get_or_create_time_period(name):
    return _get_or_create(time_period_ids, "time_periods", "time_period_id", "name", name)


def get_or_create_multiplier_measure(name):
    return _get_or_create(
        multiplier_measure_ids, "multiplier_measures", "multiplier_measure_id",
        "name", name,
    )


def get_or_create_source(citation):
    return _get_or_create(source_ids, "sources", "source_id", "citation", citation)


def get_or_create_place(locality, county_name=None):
    locality = as_text(locality)
    if locality is None:
        return None
    county_name = as_text(county_name)
    key = (county_name, locality)
    if key not in place_ids:
        county_id = None
        if county_name:
            if county_name not in county_ids:
                cid = new_id()
                county_ids[county_name] = cid
                cur.execute(
                    "INSERT INTO counties(county_id, name) VALUES (?, ?)",
                    (cid, county_name),
                )
            county_id = county_ids[county_name]
        pid = new_id()
        place_ids[key] = pid
        cur.execute(
            "INSERT INTO places(place_id, county_id, locality) VALUES (?, ?, ?)",
            (pid, county_id, locality),
        )
        locality_index.setdefault(locality, pid)
    return place_ids[key]


def get_place_by_locality(locality):
    """The Data sheet records only a locality, with no county."""
    locality = as_text(locality)
    if locality is None:
        return None
    if locality in locality_index:
        return locality_index[locality]
    return get_or_create_place(locality)


def get_or_create_category(name):
    return _get_or_create(category_ids, "categories", "category_id", "name", name)


def _child(cache, table, id_col, parent_col, parent_id, name):
    name = as_text(name)
    if parent_id is None or name is None:
        return None
    key = (parent_id, name)
    if key not in cache:
        uid = new_id()
        cache[key] = uid
        cur.execute(
            f"INSERT INTO {table}({id_col}, {parent_col}, name) VALUES (?, ?, ?)",
            (uid, parent_id, name),
        )
    return cache[key]


def get_or_create_specific_chain(cat, subcat, spec):
    """Walks category -> subcategory -> specific, creating any missing level."""
    category_id = get_or_create_category(cat)
    subcategory_id = _child(
        subcategory_ids, "subcategories", "subcategory_id", "category_id",
        category_id, subcat,
    )
    return _child(
        specific_ids, "specifics", "specific_id", "subcategory_id",
        subcategory_id, spec,
    )


def get_or_create_measure(name, metric_value=None, sheet_row=None, used_by=None):
    """First definition wins, mirroring MATCH(..., 0). A name used elsewhere
    but never defined in Measures is still inserted, with a NULL metric_value,
    so the record keeps saying what it says -- and so it resolves to zero,
    exactly as the sheet's IFERROR(..., 0) does."""
    name = norm_key(name)
    if name is None:
        return None
    if name not in measure_ids:
        uid = new_id()
        measure_ids[name] = uid
        cur.execute(
            "INSERT INTO measures(measure_id, name, metric_value, sheet_row) "
            "VALUES (?, ?, ?, ?)",
            (uid, name, as_num(metric_value), sheet_row),
        )
        if used_by:
            invented_measures[name] = used_by
    return measure_ids[name]


def get_or_create_standard(name, metric_value=None, sheet_row=None, used_by=None):
    name = norm_key(name)
    if name is None:
        return None
    if name not in standard_ids:
        uid = new_id()
        standard_ids[name] = uid
        cur.execute(
            "INSERT INTO standards(standard_id, name, metric_value, sheet_row) "
            "VALUES (?, ?, ?, ?)",
            (uid, name, as_num(metric_value), sheet_row),
        )
        if used_by:
            invented_standards[name] = used_by
    return standard_ids[name]


# ------------------------------------------------------------- Measures -----
# Column B is the name, column C the load-bearing "Metric Value"; D onwards
# are alternative expressions that no formula reads.
measures_header = next(iter(rows_of("Measures", 1, 1)))[1]
measure_targets = [
    (c, as_text(at(measures_header, c)))
    for c in range(4, len(measures_header) + 1)
]
measure_targets = [(c, h) for c, h in measure_targets if h]

for r, values in rows_of("Measures", 2, MEASURES_LAST_ROW):
    name = norm_key(at(values, 2))
    if not name:
        continue
    if name in measure_ids:
        dropped_duplicates.append(("Measures", name, r))
        continue
    mid = get_or_create_measure(name, at(values, 3), sheet_row=r)
    for c, header in measure_targets:
        v = as_num(at(values, c))
        if v is None:
            continue
        cur.execute(
            "INSERT INTO measure_conversions(conversion_id, measure_id, target_name, value) "
            "VALUES (?, ?, ?, ?)",
            (new_id(), mid, header, v),
        )

# ------------------------------------------------------------ Standards -----
# Column A is the name, column B the load-bearing "Metric"; C onwards are
# alternative expressions.
standards_header = next(iter(rows_of("Standards", 1, 1)))[1]
standard_targets = [
    (c, as_text(at(standards_header, c)))
    for c in range(3, len(standards_header) + 1)
]
standard_targets = [(c, h) for c, h in standard_targets if h]

for r, values in rows_of("Standards", 2, STANDARDS_LAST_ROW):
    name = norm_key(at(values, 1))
    if not name:
        continue
    if name in standard_ids:
        dropped_duplicates.append(("Standards", name, r))
        continue
    sid = get_or_create_standard(name, at(values, 2), sheet_row=r)
    for c, header in standard_targets:
        v = as_num(at(values, c))
        if v is None:
            continue
        cur.execute(
            "INSERT INTO standard_conversions(conversion_id, standard_id, target_name, value) "
            "VALUES (?, ?, ?, ?)",
            (new_id(), sid, header, v),
        )

# ------------------------------------------------ dimensions (provisional) ---
# Read once the conversion tables are complete. See tools/dimensions.py for why
# this can be inferred at all, and tools/build_review_db.py for how it is put
# to the researcher for confirmation.
for table, id_col, join_table, join_col in (
        ("measures", "measure_id", "measure_conversions", "measure_id"),
        ("standards", "standard_id", "standard_conversions", "standard_id")):
    rows = cur.execute(
        f"SELECT {id_col}, name, metric_value FROM {table}").fetchall()
    for row_id, name, metric_value in rows:
        targets = {
            r[0] for r in cur.execute(
                f"SELECT target_name FROM {join_table} WHERE {join_col} = ?",
                (row_id,))
        }
        dim, _why, source = dimensions.guess(
            name, metric_value, targets,
            vocabulary="standard" if table == "standards" else "measure")
        cur.execute(
            f"UPDATE {table} SET dimension = ?, dimension_source = ? "
            f"WHERE {id_col} = ?",
            (dim, source, row_id))
        stats[f"dimension {source}"] += 1

# ------------------------------------------------------------- Places -------
places_header = next(iter(rows_of("Places", 1, 1)))[1]
override_cols = [
    (c, as_text(at(places_header, c))) for c in range(4, len(places_header) + 1)
]
override_cols = [(c, h) for c, h in override_cols if h]

for r, values in rows_of("Places", 2, PLACES_LAST_ROW):
    locality = at(values, 2)
    if not as_text(locality):
        continue
    pid = get_or_create_place(locality, at(values, 1))
    for c, header in override_cols:
        val = at(values, c)
        if val is None or (isinstance(val, str) and "N/A" in val):
            continue
        mid = get_or_create_measure(header, used_by="Places")
        cur.execute(
            "INSERT INTO place_measure_overrides(override_id, place_id, measure_id, definition) "
            "VALUES (?, ?, ?, ?)",
            (new_id(), pid, mid, str(val)),
        )

# ---------------------------------------------------------- Categories ------
for _r, values in rows_of("Categories", 2, CATEGORIES_LAST_ROW):
    if not as_text(at(values, 1)):
        continue
    get_or_create_specific_chain(at(values, 1), at(values, 2), at(values, 3))

conn.commit()

# ---------------------------------------------------------- price_entries ---
COL = {
    "Entry": 1, "Year": 2, "Region": 3, "Month": 4, "Day": 5,
    "Category": 6, "Subcategory": 7, "Specifics": 8,
    "UNIT 1": 9, "UNIT 2": 10, "UNIT 3": 11, "Multiplier/Workers": 12,
    "Pounds": 13, "Shillings": 14, "Pence": 15, "Status/Info": 16, "Food": 17,
    "MEASURE 1": 18, "MEASURE 2": 19, "MEASURE 3": 20,
    "Multiplier/Workers Measure": 21, "Total Grams": 22,
    "Valuation Measure": 23, "OUTPUT X": 24, "CHOSEN OUTPUT Y": 25,
    "OUTPUT X VALUE": 26, "Val Grams": 27, "Sales Calc": 28,
    "Price in Pence": 29, "Total Sale in Pence": 30, "Pence per Output Y": 31,
    "Country": 32, "Coin type": 33, "Information": 34, "Source": 35, "Page": 36,
}

# Derived column -> the name it gets in excel_cached_calculations.
CACHED = [
    ("Total Grams", "total_grams"),
    ("Val Grams", "val_meas_in_grams"),
    ("Sales Calc", "val_meas_number"),
    ("Price in Pence", "val_meas_price_per_numb_in_pence"),
    ("Total Sale in Pence", "total_sale_in_pence"),
    ("OUTPUT X VALUE", "output_x_value"),
    ("Pence per Output Y", "pence_per_output_y"),
]

entries = []
cached = []
blank_rows = []

for r, values in rows_of("Data", DATA_FIRST_ROW, DATA_LAST_ROW):
    def v(name):
        return at(values, COL[name])

    entry_no = as_num(v("Entry"))
    if entry_no is None:
        continue

    # Rows 7801-10379 of the Data sheet are unfilled template rows: the
    # dropdowns still hold their default ('Heads/Units' in all four unit
    # columns, 'UK' for country) but nothing was ever recorded against them.
    # Importing them would inflate every count in the app by a third and make
    # 'Heads/Units' look like the most-used measure in the database. Skipped,
    # and reported at the end so the number is never silently assumed.
    if not any(as_text(v(c)) is not None for c in (
            "Year", "Region", "Category", "Subcategory", "Specifics",
            "UNIT 1", "UNIT 2", "UNIT 3", "Multiplier/Workers",
            "Pounds", "Shillings", "Pence", "Status/Info", "Food",
            "Information", "Page", "Month", "Day")):
        stats["blank template rows skipped"] += 1
        blank_rows.append(int(entry_no))
        continue

    entry_id = new_id()

    # A measure the Data sheet names but Measures never defines resolves to
    # NULL metric_value, which makes it contribute zero -- exactly what the
    # sheet's IFERROR(..., 0) does.
    def measure(col):
        return get_or_create_measure(v(col), used_by="Data")

    def standard(col):
        return get_or_create_standard(v(col), used_by="Data")

    entries.append((
        entry_id,
        int(entry_no),
        as_int(v("Year")),
        get_or_create_time_period(v("Month")),
        as_int(v("Day")),
        get_place_by_locality(v("Region")),
        get_or_create_specific_chain(v("Category"), v("Subcategory"), v("Specifics")),
        as_num(v("UNIT 1")),
        as_num(v("UNIT 2")),
        as_num(v("UNIT 3")),
        measure("MEASURE 1"),
        measure("MEASURE 2"),
        measure("MEASURE 3"),
        as_num(v("Multiplier/Workers")),
        get_or_create_multiplier_measure(v("Multiplier/Workers Measure")),
        as_num(v("Pounds")),
        as_num(v("Shillings")),
        as_num(v("Pence")),
        measure("Valuation Measure"),
        standard("OUTPUT X"),
        standard("CHOSEN OUTPUT Y"),
        as_text(v("Status/Info")),
        as_text(v("Food")),
        get_or_create_country(v("Country")),
        get_or_create_coin_type(v("Coin type")),
        as_text(v("Information")),
        get_or_create_source(v("Source")),
        as_int(v("Page")),
    ))

    numbers, errors = [], []
    for sheet_col, db_col in CACHED:
        raw = v(sheet_col)
        n = as_num(raw)
        numbers.append(n)
        if n is None and isinstance(raw, str) and raw.strip():
            errors.append(f"{db_col}={raw.strip()}")
            stats[f"cached error: {raw.strip()}"] += 1
    cached.append((entry_id, *numbers, "; ".join(errors) or None))

cur.executemany(
    """INSERT INTO price_entries (
        entry_id, legacy_entry_no, year, time_period_id, day_of_month, place_id,
        specific_id, unit_1, unit_2, unit_3, measure_1_id, measure_2_id,
        measure_3_id, multiplier_workers, multiplier_measure_id, pounds,
        shillings, pence, valuation_measure_id, output_x_standard_id,
        output_y_standard_id, status_info, food, country_id, coin_type_id,
        information, source_id, page
    ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
    entries,
)
cur.executemany(
    """INSERT INTO excel_cached_calculations (
        entry_id, total_grams, val_meas_in_grams, val_meas_number,
        val_meas_price_per_numb_in_pence, total_sale_in_pence, output_x_value,
        pence_per_output_y, errors
    ) VALUES (?,?,?,?,?,?,?,?,?)""",
    cached,
)

conn.commit()
wb.close()

# ------------------------------------------------------------- report -------
def count(table):
    return cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


print(f"price_entries        {count('price_entries'):>7}")
if blank_rows:
    print(f"  (skipped {len(blank_rows)} blank template rows, "
          f"Entry {min(blank_rows)}-{max(blank_rows)} — dropdown defaults only, "
          f"no recorded data)")
for t in ("counties", "places", "categories", "subcategories", "specifics",
          "measures", "standards", "measure_conversions", "standard_conversions",
          "place_measure_overrides", "time_periods", "multiplier_measures",
          "sources", "countries", "coin_types"):
    print(f"{t:<21}{count(t):>7}")

resolvable_m = cur.execute(
    "SELECT COUNT(*) FROM measures WHERE metric_value IS NOT NULL").fetchone()[0]
resolvable_s = cur.execute(
    "SELECT COUNT(*) FROM standards WHERE metric_value IS NOT NULL").fetchone()[0]
print()
for table in ("measures", "standards"):
    read = cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE dimension_source = 'read'"
    ).fetchone()[0]
    guessed = cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE dimension_source = 'guessed'"
    ).fetchone()[0]
    unknown = cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE dimension IS NULL"
    ).fetchone()[0]
    print(f"{table} dimensions: {read} read from the sheet, {guessed} guessed "
          f"from names, {unknown} unknown")

print()
print(f"measures with a metric value   {resolvable_m} of {count('measures')}")
print(f"standards with a metric value  {resolvable_s} of {count('standards')}")

if dropped_duplicates:
    print()
    print(f"duplicate lookup names, later rows unreachable by MATCH() "
          f"({len(dropped_duplicates)}):")
    for sheet, name, row in dropped_duplicates:
        print(f"  {sheet}!{row}  {name!r}")

def report_invented(invented, lookup_sheet):
    from_data = sorted(n for n, src in invented.items() if src == "Data")
    from_elsewhere = sorted(n for n, src in invented.items() if src != "Data")
    if from_data:
        print()
        print(f"!! used by Data but not defined in {lookup_sheet} "
              f"({len(from_data)}) -- these resolve to zero in every "
              f"calculation, in the spreadsheet as well as here:")
        for name in from_data:
            print(f"     {name!r}")
    if from_elsewhere:
        print()
        print(f"   named on the Places sheet but not defined in {lookup_sheet} "
              f"({len(from_elsewhere)}). Places is reference-only, so these "
              f"affect no calculation:")
        print(f"     {', '.join(repr(n) for n in from_elsewhere)}")


report_invented(invented_measures, "Measures")
report_invented(invented_standards, "Standards")

if stats:
    print()
    print("cached formula errors carried into excel_cached_calculations:")
    for k, n in stats.most_common():
        print(f"  {n:>6}  {k}")

conn.close()
print()
print("done ->", OUT)
