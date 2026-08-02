import openpyxl
import sqlite3
import uuid
import os

# Paths are relative to the repo root (this script lives in tools/).
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(_REPO_ROOT, "Copy of 1270s80sDatabase.xlsx")
OUT = os.path.join(_REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")
SAMPLE_SIZE = None  # None = convert every row

if os.path.exists(OUT):
    os.remove(OUT)

wb = openpyxl.load_workbook(SRC, data_only=True)


def new_id():
    return str(uuid.uuid4())


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
    UNIQUE(county_id, locality)
);

CREATE TABLE categories (
    category_id TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

CREATE TABLE subcategories (
    subcategory_id TEXT PRIMARY KEY,
    category_id     TEXT NOT NULL REFERENCES categories(category_id),
    name             TEXT NOT NULL,
    UNIQUE(category_id, name)
);

CREATE TABLE specifics (
    specific_id      TEXT PRIMARY KEY,
    subcategory_id   TEXT NOT NULL REFERENCES subcategories(subcategory_id),
    name             TEXT NOT NULL,
    UNIQUE(subcategory_id, name)
);

CREATE TABLE units (
    unit_id     TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE
);

-- long/junction form of the "Measures" sheet matrix (unit -> many target-unit rates)
CREATE TABLE unit_conversions (
    conversion_id   TEXT PRIMARY KEY,
    unit_id         TEXT NOT NULL REFERENCES units(unit_id),
    target_unit     TEXT NOT NULL,
    target_col_ix   INTEGER NOT NULL,
    rate            REAL
);

-- long/junction form of the "Standards" sheet matrix (unit -> weight-standard values)
CREATE TABLE unit_standards (
    standard_id     TEXT PRIMARY KEY,
    unit_id         TEXT NOT NULL REFERENCES units(unit_id),
    standard_name   TEXT NOT NULL,
    target_col_ix   INTEGER NOT NULL,
    value           REAL
);

-- long/junction form of the "Places" sheet matrix (place -> region-specific unit definitions)
CREATE TABLE place_unit_overrides (
    override_id     TEXT PRIMARY KEY,
    place_id        TEXT NOT NULL REFERENCES places(place_id),
    unit_id         TEXT NOT NULL REFERENCES units(unit_id),
    definition      TEXT
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

-- covers both calendar months ('May') and the non-month time references the
-- sheet also used in this column ('Michaelmas Term', 'Autumn', 'Christmas')
CREATE TABLE time_periods (
    time_period_id TEXT PRIMARY KEY,
    name           TEXT NOT NULL UNIQUE
);

CREATE TABLE multiplier_measures (
    multiplier_measure_id TEXT PRIMARY KEY,
    name                   TEXT NOT NULL UNIQUE
);

CREATE TABLE price_entries (
    entry_id                    TEXT PRIMARY KEY,
    legacy_entry_no              INTEGER,
    year                          INTEGER,
    time_period_id                TEXT REFERENCES time_periods(time_period_id),
    day_of_month                  INTEGER,
    place_id                      TEXT REFERENCES places(place_id),
    specific_id                   TEXT REFERENCES specifics(specific_id),
    unit_1                        REAL,
    unit_2                        REAL,
    unit_3                        REAL,
    multiplier_workers            REAL,
    pounds                        REAL,
    shillings                     REAL,
    pence                         REAL,
    status_info                   TEXT,
    measure_1_unit_id             TEXT REFERENCES units(unit_id),
    measure_2_unit_id             TEXT REFERENCES units(unit_id),
    measure_3_unit_id             TEXT REFERENCES units(unit_id),
    multiplier_workers_measure_id TEXT REFERENCES multiplier_measures(multiplier_measure_id),
    total_grams                   REAL,
    valuation_measure_unit_id     TEXT REFERENCES units(unit_id),
    output_x_unit_id              TEXT REFERENCES units(unit_id),
    chosen_output_y_unit_id       TEXT REFERENCES units(unit_id),
    output_x_value                REAL,
    val_grams                     REAL,
    sales_calc                    REAL,
    price_in_pence                REAL,
    total_sale_in_pence           REAL,
    pence_per_output_y            REAL,
    country_id                    TEXT REFERENCES countries(country_id),
    coin_type_id                  TEXT REFERENCES coin_types(coin_type_id),
    information                   TEXT,
    source_id                     TEXT REFERENCES sources(source_id),
    page                          INTEGER
);

CREATE INDEX idx_price_entries_place ON price_entries(place_id);
CREATE INDEX idx_price_entries_specific ON price_entries(specific_id);
CREATE INDEX idx_price_entries_year ON price_entries(year);
CREATE INDEX idx_price_entries_time_period ON price_entries(time_period_id);
CREATE INDEX idx_price_entries_country ON price_entries(country_id);
CREATE INDEX idx_unit_conversions_unit ON unit_conversions(unit_id);
CREATE INDEX idx_unit_standards_unit ON unit_standards(unit_id);
CREATE INDEX idx_place_overrides_place ON place_unit_overrides(place_id);
CREATE INDEX idx_subcategories_category ON subcategories(category_id);
CREATE INDEX idx_specifics_subcategory ON specifics(subcategory_id);
""")

# ------------------------------------------------------------- lookups ------
county_ids = {}       # name -> id
place_ids = {}        # (county_name_or_None, locality) -> id
locality_index = {}   # locality (first county seen wins) -> place_id, for Data sheet joins
category_ids = {}     # category name -> id
subcategory_ids = {}  # (category_id, subcategory name) -> id
specific_ids = {}     # (subcategory_id, specific name) -> id
unit_ids = {}         # name -> id
source_ids = {}       # citation -> id
country_ids = {}      # name -> id
coin_type_ids = {}    # name -> id
time_period_ids = {}  # name -> id
multiplier_measure_ids = {}  # name -> id


def _get_or_create(cache, table, id_col, name_col, name):
    if name is None:
        return None
    name = str(name).strip() if isinstance(name, str) else name
    if name == "":
        return None
    if name not in cache:
        new_uid = new_id()
        cache[name] = new_uid
        cur.execute(f"INSERT INTO {table}({id_col}, {name_col}) VALUES (?, ?)", (new_uid, name))
    return cache[name]


def get_or_create_country(name):
    return _get_or_create(country_ids, "countries", "country_id", "name", name)


def get_or_create_coin_type(name):
    return _get_or_create(coin_type_ids, "coin_types", "coin_type_id", "name", name)


def get_or_create_time_period(name):
    return _get_or_create(time_period_ids, "time_periods", "time_period_id", "name", name)


def get_or_create_multiplier_measure(name):
    return _get_or_create(
        multiplier_measure_ids, "multiplier_measures", "multiplier_measure_id", "name", name
    )


def get_or_create_unit(name):
    if not name:
        return None
    name = str(name).strip()
    if not name:
        return None
    if name not in unit_ids:
        uid = new_id()
        unit_ids[name] = uid
        cur.execute("INSERT INTO units(unit_id, name) VALUES (?, ?)", (uid, name))
    return unit_ids[name]


def get_or_create_place(locality, county_name=None):
    if not locality:
        return None
    key = (county_name, locality)
    if key not in place_ids:
        county_id = None
        if county_name:
            if county_name not in county_ids:
                cid = new_id()
                county_ids[county_name] = cid
                cur.execute("INSERT INTO counties(county_id, name) VALUES (?, ?)", (cid, county_name))
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
    """Used for the Data sheet, which records only a locality (no county)."""
    if not locality:
        return None
    if locality in locality_index:
        return locality_index[locality]
    return get_or_create_place(locality)


def get_or_create_category(name):
    if not name:
        return None
    if name not in category_ids:
        cid = new_id()
        category_ids[name] = cid
        cur.execute("INSERT INTO categories(category_id, name) VALUES (?, ?)", (cid, name))
    return category_ids[name]


def get_or_create_subcategory(category_id, name):
    if category_id is None or not name:
        return None
    key = (category_id, name)
    if key not in subcategory_ids:
        sid = new_id()
        subcategory_ids[key] = sid
        cur.execute(
            "INSERT INTO subcategories(subcategory_id, category_id, name) VALUES (?, ?, ?)",
            (sid, category_id, name),
        )
    return subcategory_ids[key]


def get_or_create_specific(subcategory_id, name):
    if subcategory_id is None or not name:
        return None
    key = (subcategory_id, name)
    if key not in specific_ids:
        spid = new_id()
        specific_ids[key] = spid
        cur.execute(
            "INSERT INTO specifics(specific_id, subcategory_id, name) VALUES (?, ?, ?)",
            (spid, subcategory_id, name),
        )
    return specific_ids[key]


def get_or_create_specific_chain(cat, subcat, spec):
    """Walks category -> subcategory -> specific, creating any missing level."""
    category_id = get_or_create_category(cat)
    subcategory_id = get_or_create_subcategory(category_id, subcat)
    return get_or_create_specific(subcategory_id, spec)


def get_or_create_source(citation):
    if not citation:
        return None
    if citation not in source_ids:
        sid = new_id()
        source_ids[citation] = sid
        cur.execute("INSERT INTO sources(source_id, citation) VALUES (?, ?)", (sid, citation))
    return source_ids[citation]


# ------------------------------------------------------------- Places -------
ws = wb["Places"]
override_cols = [(c, ws.cell(row=1, column=c).value) for c in range(4, ws.max_column + 1)]
override_cols = [(c, h) for c, h in override_cols if h]

for r in range(2, 712):
    county_name = ws.cell(row=r, column=1).value
    locality = ws.cell(row=r, column=2).value
    if not locality:
        continue
    pid = get_or_create_place(locality, county_name)
    for c, header in override_cols:
        val = ws.cell(row=r, column=c).value
        if val is None or (isinstance(val, str) and "N/A" in val):
            continue
        uid = get_or_create_unit(header)
        cur.execute(
            "INSERT INTO place_unit_overrides(override_id, place_id, unit_id, definition) VALUES (?, ?, ?, ?)",
            (new_id(), pid, uid, str(val)),
        )

# ---------------------------------------------------------- Categories ------
ws = wb["Categories"]
for r in range(2, 593):
    cat = ws.cell(row=r, column=1).value
    subcat = ws.cell(row=r, column=2).value
    spec = ws.cell(row=r, column=3).value
    if not cat:
        continue
    get_or_create_specific_chain(cat, subcat, spec)

# ------------------------------------------------------------- Measures -----
ws = wb["Measures"]
headers = {c: ws.cell(row=1, column=c).value for c in range(3, ws.max_column + 1)}
for r in range(2, 493):
    name = ws.cell(row=r, column=2).value
    if not name:
        continue
    uid = get_or_create_unit(name)
    for c, header in headers.items():
        if not header:
            continue
        val = ws.cell(row=r, column=c).value
        if val is None or not isinstance(val, (int, float)):
            continue
        cur.execute(
            "INSERT INTO unit_conversions(conversion_id, unit_id, target_unit, target_col_ix, rate) "
            "VALUES (?, ?, ?, ?, ?)",
            (new_id(), uid, header, c, val),
        )

# ------------------------------------------------------------ Standards -----
ws = wb["Standards"]
headers = {c: ws.cell(row=1, column=c).value for c in range(2, ws.max_column + 1)}
for r in range(2, 100):
    name = ws.cell(row=r, column=1).value
    if not name:
        continue
    uid = get_or_create_unit(name)
    for c, header in headers.items():
        if not header:
            continue
        val = ws.cell(row=r, column=c).value
        if val is None or not isinstance(val, (int, float)):
            continue
        cur.execute(
            "INSERT INTO unit_standards(standard_id, unit_id, standard_name, target_col_ix, value) "
            "VALUES (?, ?, ?, ?, ?)",
            (new_id(), uid, header, c, val),
        )

conn.commit()

# ---------------------------------------------------------- price_entries ---
ws = wb["Data"]
DATA_FIRST_ROW = 3
DATA_LAST_ROW = 10381
total_rows = DATA_LAST_ROW - DATA_FIRST_ROW + 1
if SAMPLE_SIZE is None:
    sample_rows = list(range(DATA_FIRST_ROW, DATA_LAST_ROW + 1))
else:
    step = max(1, total_rows // SAMPLE_SIZE)
    sample_rows = list(range(DATA_FIRST_ROW, DATA_LAST_ROW + 1, step))[:SAMPLE_SIZE]

col = {
    "Entry": 1, "Year": 2, "Region": 3, "Month": 4, "Day": 5,
    "Category": 6, "Subcategory": 7, "Specifics": 8,
    "UNIT 1": 9, "UNIT 2": 10, "UNIT 3": 11, "Multiplier/Workers": 12,
    "Pounds": 13, "Shillings": 14, "Pence": 15, "Status/Info": 16,
    "MEASURE 1": 18, "MEASURE 2": 19, "MEASURE 3": 20,
    "Multiplier/Workers Measure": 21, "Total Grams": 22,
    "Valuation Measure": 23, "OUTPUT X": 24, "CHOSEN OUTPUT Y": 25,
    "OUTPUT X VALUE": 26, "Val Grams": 27, "Sales Calc": 28,
    "Price in Pence": 29, "Total Sale in Pence": 30, "Pence per Output Y": 31,
    "Country": 32, "Coin type": 33, "Information": 34, "Source": 35, "Page": 36,
}


def v(row, name):
    return ws.cell(row=row, column=col[name]).value


def vnum(row, name):
    """Like v(), but returns None for anything that isn't actually a number
    (some cells hold cached Excel formula-error text like '#N/A' or
    '#DIV/0!' instead of a value)."""
    val = v(row, name)
    return val if isinstance(val, (int, float)) else None


inserted = 0
skipped_errors = 0
for r in sample_rows:
    entry_no = vnum(r, "Entry")
    if entry_no is None:
        continue

    place_id = get_place_by_locality(v(r, "Region"))
    specific_id = get_or_create_specific_chain(
        v(r, "Category"), v(r, "Subcategory"), v(r, "Specifics")
    )
    source_id = get_or_create_source(v(r, "Source"))

    day_of_month = vnum(r, "Day")
    day_of_month = int(day_of_month) if day_of_month is not None else None

    for name in (
        "UNIT 1", "UNIT 2", "UNIT 3", "Multiplier/Workers", "Pounds", "Shillings",
        "Pence", "Total Grams", "OUTPUT X VALUE", "Val Grams", "Sales Calc",
        "Price in Pence", "Total Sale in Pence", "Pence per Output Y", "Page",
    ):
        raw = v(r, name)
        if isinstance(raw, str):
            skipped_errors += 1

    year = vnum(r, "Year")

    cur.execute(
        """INSERT INTO price_entries (
            entry_id, legacy_entry_no, year, time_period_id, day_of_month, place_id, specific_id,
            unit_1, unit_2, unit_3, multiplier_workers, pounds, shillings, pence, status_info,
            measure_1_unit_id, measure_2_unit_id, measure_3_unit_id, multiplier_workers_measure_id,
            total_grams, valuation_measure_unit_id, output_x_unit_id, chosen_output_y_unit_id,
            output_x_value, val_grams, sales_calc, price_in_pence, total_sale_in_pence,
            pence_per_output_y, country_id, coin_type_id, information, source_id, page
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            new_id(), int(entry_no), int(year) if year is not None else None,
            get_or_create_time_period(v(r, "Month")), day_of_month, place_id, specific_id,
            vnum(r, "UNIT 1"), vnum(r, "UNIT 2"), vnum(r, "UNIT 3"), vnum(r, "Multiplier/Workers"),
            vnum(r, "Pounds"), vnum(r, "Shillings"), vnum(r, "Pence"), v(r, "Status/Info"),
            get_or_create_unit(v(r, "MEASURE 1")), get_or_create_unit(v(r, "MEASURE 2")),
            get_or_create_unit(v(r, "MEASURE 3")), get_or_create_multiplier_measure(v(r, "Multiplier/Workers Measure")),
            vnum(r, "Total Grams"), get_or_create_unit(v(r, "Valuation Measure")),
            get_or_create_unit(v(r, "OUTPUT X")), get_or_create_unit(v(r, "CHOSEN OUTPUT Y")),
            vnum(r, "OUTPUT X VALUE"), vnum(r, "Val Grams"), vnum(r, "Sales Calc"),
            vnum(r, "Price in Pence"), vnum(r, "Total Sale in Pence"), vnum(r, "Pence per Output Y"),
            get_or_create_country(v(r, "Country")), get_or_create_coin_type(v(r, "Coin type")),
            v(r, "Information"), source_id, vnum(r, "Page"),
        ),
    )
    inserted += 1

conn.commit()

print(f"counties: {len(county_ids)}")
print(f"places: {len(place_ids)}")
print(f"categories: {len(category_ids)}")
print(f"subcategories: {len(subcategory_ids)}")
print(f"specifics: {len(specific_ids)}")
print(f"units: {len(unit_ids)}")
print(f"sources: {len(source_ids)}")
print(f"countries: {len(country_ids)}")
print(f"coin_types: {len(coin_type_ids)}")
print(f"time_periods: {len(time_period_ids)}")
print(f"multiplier_measures: {len(multiplier_measure_ids)}")
print(f"price_entries inserted: {inserted}")
print(f"numeric cells that held formula-error text (nulled out): {skipped_errors}")

for t in ["unit_conversions", "unit_standards", "place_unit_overrides"]:
    n = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
    print(f"{t}: {n}")

conn.close()
print("done ->", OUT)
