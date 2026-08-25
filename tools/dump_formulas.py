"""Recovers the spreadsheet's calculation logic. See tools/CALCULATIONS.md.

build_normalized_db.py loads the workbook with data_only=True, which reads
cached *values* and throws the formulas away. This reads the formulas back
out so the calculations can be reimplemented in application code.

It reads the xlsx zip directly rather than via openpyxl: an .xlsx is a zip
of XML, and streaming <c r="A1"><f>formula</f><v>cached</v></c> is both far
faster than openpyxl's object model over 10k x 36 cells and gives us the
formula and its cached value together -- the method and the oracle.

    python tools/dump_formulas.py
"""
import os
import re
import zipfile
from collections import Counter
from xml.etree import ElementTree as ET

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(_REPO_ROOT, "Copy of 1270s80sDatabase.xlsx")

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RNS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

DATA_FIRST_ROW = 3
CELL_REF = re.compile(r"(\$?[A-Za-z]{1,3}\$?)(\d+)")

# Data-sheet columns, per build_normalized_db.py's column map.
DATA_COLS = {
    9: "UNIT 1", 10: "UNIT 2", 11: "UNIT 3", 12: "Multiplier/Workers",
    13: "Pounds", 14: "Shillings", 15: "Pence",
    18: "MEASURE 1", 19: "MEASURE 2", 20: "MEASURE 3",
    21: "Multiplier/Workers Measure", 22: "Total Grams",
    23: "Valuation Measure", 24: "OUTPUT X", 25: "CHOSEN OUTPUT Y",
    26: "OUTPUT X VALUE", 27: "Val Grams", 28: "Sales Calc",
    29: "Price in Pence", 30: "Total Sale in Pence", 31: "Pence per Output Y",
}
MEASURE_COLS = [18, 19, 20, 23]   # resolve against Measures!B
STANDARD_COLS = [24, 25]          # resolve against Standards!A


# ------------------------------------------------------------- workbook -----
zf = zipfile.ZipFile(SRC)

_wb = ET.fromstring(zf.read("xl/workbook.xml"))
_rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
_rid = {r.get("Id"): r.get("Target") for r in _rels}
SHEET_PATHS = {}
for _sh in _wb.iter(f"{NS}sheet"):
    _t = _rid[_sh.get(f"{RNS}id")]
    SHEET_PATHS[_sh.get("name")] = ("xl/" + _t.lstrip("/")).replace("xl/xl/", "xl/")

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


def col_name(n):
    s = ""
    while n:
        n, rem = divmod(n - 1, 26)
        s = chr(65 + rem) + s
    return s


def scan(sheet, cols=None, first_row=1):
    """Yields (row, col, formula_or_None, value_or_None) for the sheet."""
    want = set(cols) if cols else None
    with zf.open(SHEET_PATHS[sheet]) as fh:
        for _event, el in ET.iterparse(fh, events=("end",)):
            if el.tag != f"{NS}c":
                continue
            ref = el.get("r") or ""
            digits = "".join(c for c in ref if c.isdigit())
            if digits:
                r, c = int(digits), col_ix(ref)
                if r >= first_row and (want is None or c in want):
                    f_el = el.find(f"{NS}f")
                    v_el = el.find(f"{NS}v")
                    val = None
                    if v_el is not None and v_el.text is not None:
                        val = SHARED[int(v_el.text)] if el.get("t") == "s" else v_el.text
                    yield r, c, (f_el.text if f_el is not None else None), val
            el.clear()


def normalise(formula, row):
    """Collapse self-row references so identical formulas group together."""
    def rep(m):
        return f"{m.group(1)}{{r}}" if int(m.group(2)) == row else m.group(0)
    return CELL_REF.sub(rep, formula)


def unwrap(formula):
    """Unwrap a Google Sheets export: IFERROR(__xludf.DUMMYFUNCTION("f"), v)."""
    if "__xludf.DUMMYFUNCTION" not in formula:
        return formula
    m = re.search(r'DUMMYFUNCTION\("(.*)"\)\s*,', formula, re.S)
    if not m:
        return formula
    # un-escape the doubled quotes, and rejoin Excel's "…"&"…" string splits
    return m.group(1).replace('""', '"').replace('"&"', "")


def norm_key(s):
    """The REGEXREPLACE(TEXT(x,"@"),'"','') the formulas apply before MATCH."""
    return s.replace('"', "").strip() if isinstance(s, str) else s


# ------------------------------------------------------------- formulas -----
print("=" * 76)
print("FORMULA SHAPES  (Data sheet)")
print("=" * 76)

shapes, samples, literals = {}, {}, Counter()
for r, c, f, v in scan("Data", cols=list(DATA_COLS), first_row=DATA_FIRST_ROW):
    if f:
        shape = normalise("=" + f, r)
        shapes.setdefault(c, Counter())[shape] += 1
        samples.setdefault(c, {}).setdefault(shape, (r, v))
    elif v is not None:
        literals[c] += 1

for c, name in DATA_COLS.items():
    total = sum(shapes.get(c, {}).values())
    print(f"\ncol {c:>2} ({col_name(c):>2})  {name}")
    if not total:
        print(f"      no formulas, {literals[c]} literal values")
        continue
    print(f"      {total} formulas, {literals[c]} literals, "
          f"{len(shapes[c])} distinct shapes")
    for shape, n in shapes[c].most_common(2):
        row, cached = samples[c][shape]
        print(f"      {n:>6}x  {unwrap(shape)}")
        print(f"              [row {row} cached -> {cached}]")


# -------------------------------------------------------------- lookups -----
def load_lookup(sheet, key_col, val_col):
    """Name -> value, first match winning, as MATCH(..., 0) does."""
    rows = {}
    for r, c, _f, v in scan(sheet, cols=[key_col, val_col], first_row=2):
        rows.setdefault(r, {})[c] = v
    out = {}
    for r in sorted(rows):
        k = rows[r].get(key_col)
        if k is not None:
            out.setdefault(norm_key(k), rows[r].get(val_col))
    return out


measures = load_lookup("Measures", 2, 3)
standards = load_lookup("Standards", 1, 2)


def isnum(v):
    try:
        float(v)
        return True
    except (TypeError, ValueError):
        return False


print()
print("=" * 76)
print("LOOKUP TABLES")
print("=" * 76)
for label, d in (("Measures!B -> C 'Metric Value'", measures),
                 ("Standards!A -> B 'Metric'", standards)):
    n_num = sum(1 for v in d.values() if isnum(v))
    print(f"  {label:<32} {len(d):>4} keys  "
          f"({n_num} numeric, {len(d) - n_num} blank/text)")

print()
print("  overlap between the two vocabularies: "
      f"{len(set(measures) & set(standards))}")


# ---------------------------------------------------------- resolvability ---
print()
print("=" * 76)
print("DO THE DATA COLUMNS RESOLVE?")
print("=" * 76)
print(f"  {'column':<28}{'distinct':>9}{'in Measures':>13}{'in Standards':>14}"
      f"{'neither':>9}")

seen = {}
for r, c, _f, v in scan("Data", cols=MEASURE_COLS + STANDARD_COLS,
                        first_row=DATA_FIRST_ROW):
    if v is not None:
        seen.setdefault(c, Counter())[norm_key(v)] += 1

for c in MEASURE_COLS + STANDARD_COLS:
    vals = seen.get(c, Counter())
    in_m = sum(1 for v in vals if v in measures)
    in_s = sum(1 for v in vals if v in standards)
    missing = [v for v in vals if v not in measures and v not in standards]
    print(f"  {DATA_COLS[c]:<28}{len(vals):>9}{in_m:>13}{in_s:>14}"
          f"{len(missing):>9}")
    if missing:
        print(f"      unresolved: {missing[:4]}")
