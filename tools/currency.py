"""Reads the workbook's Currency sheet into modern-money conversion factors.

The brief asks for three figures the app does not yet produce:

    UKP 2026 Total Sale      = f(Year, Total Sale in Pence,        Currency tab)
    UKP 2026 per Val Meas    = f(Year, Price per Numb in Pence,    Currency tab)
    UKP 2026 per output Y    = f(Year, the reader's output unit,   Currency tab)

and describes the tab itself as: "Dear database. Please translate this
medieval price to 2017 UK pricing, and then apply inflation to get us to early
2026. Will need updating because... you know... inflation."

The sheet was empty in the August export, so this module was first written
against the *stated contract* below rather than against real data. The
researcher has since supplied a filled tab, laid out differently, and both
layouts are now read.

**What the real tab looks like**, 1270 to 1519, one flat value per decade:

    Year   Function Value   UKP 2026   UKP 2017   Pence
    1270   4.086976         4.086976   3.04       1

Only two of those five columns carry information. `Function Value` duplicates
`UKP 2026` on every row and `Pence` is 1 throughout, meaning the figures are
per one penny. A `UKP <year>` pair is read as base and target: the earlier
year is the per-year factor and the ratio between them is the rebasing
multiplier, which in the supplied tab is a constant 1.3444 across all 250
rows. Storing it that way rather than storing the 2026 column keeps one number
to change when inflation moves, which is the whole reason the two steps are
separate.

**The contract layout**, still accepted, is:

    A1: Year   B1: Pounds per penny   C1: Basis   D1: Source   E1: Note
    A2: 1270   B2: 0.0000            ...

plus, anywhere on the sheet, a labelled cell with its value to the right:

    Base year             2017
    Target year           2026
    Inflation multiplier  1.xx

Header matching is loose (case, spacing and punctuation are ignored, and
several wordings are accepted) because a person filling in a spreadsheet
should not have to match a string exactly. It is not *guessy*, though: a
column has to be recognisable or it is reported as unread rather than assumed.

Two steps rather than one, because the brief's maintenance note is the whole
point. The year factors are a scholarly judgement made once; the rebasing
multiplier changes every year. Folding them together would mean re-deriving
twenty-two numbers annually to update one.

Self-test:

    python tools/currency.py
"""
import re
from dataclasses import dataclass, field


@dataclass
class Factor:
    """What one penny of `year` was worth, in the pounds of the base year."""
    year: int
    pounds_per_penny: float | None
    basis: str | None = None
    source: str | None = None
    note: str | None = None


@dataclass
class Rebasing:
    """Carrying the base year forward to the year being reported in."""
    base_year: int | None = None
    target_year: int | None = None
    multiplier: float | None = None
    source: str | None = None
    note: str | None = None

    @property
    def is_usable(self) -> bool:
        return self.multiplier is not None and self.base_year is not None


@dataclass
class CurrencySheet:
    factors: list = field(default_factory=list)
    rebasing: Rebasing | None = None
    header_row: int | None = None
    problems: list = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not self.factors and self.rebasing is None


# Accepted spellings, normalised. Anything not listed is left unread and
# reported, which is the right failure: a column we cannot name is a column we
# cannot safely guess the meaning of.
_YEAR = {"year", "years", "yr"}
_FACTOR = {
    "poundsperpenny", "perpenny", "poundsperpence", "pennyinpounds",
    "valueofapenny", "valueofonepenny", "factor", "conversionfactor",
    "pencetopounds", "pennytopounds", "modernpounds", "pounds",
}
_BASIS = {"basis", "index", "measure", "series", "method"}
_SOURCE = {"source", "citation", "reference", "authority"}
_NOTE = {"note", "notes", "comment", "comments", "remark", "remarks"}

# A column headed with a currency and a year, such as "UKP 2017" or
# "GBP 2026": the value of one penny expressed in that year's pounds. Two of
# them make a base and a target between them.
_DATED_MONEY = re.compile(r"^(?:ukp|gbp|usd|pounds?|p)(\d{4})$")

# How many pence the figures are quoted per. Always 1 in the supplied tab, but
# a 12 here would silently turn every factor into pounds per shilling.
_PER = {"pence", "pennies", "perpence", "pencecount", "d"}

_BASE_YEAR = {"baseyear", "basisyear", "expressedin", "poundsofyear"}
_TARGET_YEAR = {"targetyear", "reportyear", "reportingyear", "presentyear"}
_MULTIPLIER = {
    "inflationmultiplier", "inflation", "multiplier", "rebasing",
    "rebasingmultiplier", "inflationfactor",
}

# A year the price records could plausibly carry, or a modern base year. Used
# only to tell a year cell from a stray number, never to reject data.
_YEAR_RANGE = range(1000, 2200)


def _norm(v):
    """Header text, stripped of everything that varies between typists."""
    if v is None:
        return ""
    return "".join(ch for ch in str(v).lower() if ch.isalnum())


def _text(v):
    if v is None:
        return None
    s = str(v).strip()
    return s or None


def _num(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = _text(v)
    if s is None:
        return None
    # A person may well type "£0.0042" or "1,234.5".
    s = s.replace("£", "").replace(",", "").strip()
    try:
        return float(s)
    except ValueError:
        return None


def _int(v):
    n = _num(v)
    return int(n) if n is not None and n == int(n) else None


def _find_labelled(values, labels):
    """A label cell's value: the first non-empty cell to its right.

    Spreadsheet people write `Base year | 2017` across two cells, and
    sometimes leave a blank between them for looks.
    """
    for i, cell in enumerate(values):
        if _norm(cell) in labels:
            for later in values[i + 1:]:
                if later is not None and _text(later) is not None:
                    return later
    return None


def parse(rows):
    """Reads `(row_number, values_tuple)` pairs into a [CurrencySheet].

    `values_tuple` is 0-indexed, so spreadsheet column A is `values[0]` —
    matching what `openpyxl`'s `values_only=True` yields.
    """
    rows = [(n, tuple(v)) for n, v in rows]
    result = CurrencySheet()

    header_row, cols = None, {}
    dated = {}          # year -> column index, from "UKP 2017" style headers
    per_pence_col = None
    for number, values in rows:
        found = {}
        here_dated = {}
        here_per = None
        for i, cell in enumerate(values):
            key = _norm(cell)
            for name, vocabulary in (("year", _YEAR), ("factor", _FACTOR),
                                     ("basis", _BASIS), ("source", _SOURCE),
                                     ("note", _NOTE)):
                if key in vocabulary and name not in found:
                    found[name] = i
            match = _DATED_MONEY.match(key)
            if match:
                here_dated.setdefault(int(match.group(1)), i)
            elif key in _PER and here_per is None:
                here_per = i
        # Two dated-money columns stand in for an explicit factor column: the
        # earlier year is the factor and the later one is where the rebasing
        # multiplier is read from.
        if "year" in found and "factor" not in found and len(here_dated) >= 1:
            found["factor"] = here_dated[min(here_dated)]
        # A year column on its own is not enough — the Data sheet has years
        # too, and a header row without a factor column tells us nothing.
        if "year" in found and "factor" in found:
            header_row, cols = number, found
            dated, per_pence_col = here_dated, here_per
            break

    result.header_row = header_row

    if header_row is not None:
        for number, values in rows:
            if number <= header_row:
                continue
            year = _int(values[cols["year"]] if len(values) > cols["year"] else None)
            if year is None or year not in _YEAR_RANGE:
                continue

            def cell(name):
                i = cols.get(name)
                return values[i] if i is not None and len(values) > i else None

            result.factors.append(Factor(
                year=year,
                pounds_per_penny=_num(cell("factor")),
                basis=_text(cell("basis")),
                source=_text(cell("source")),
                note=_text(cell("note")),
            ))

    # Two dated-money columns imply the rebasing without anybody labelling
    # it: the ratio between them *is* the multiplier. Checked across every row
    # rather than taken from the first, because a column of pasted values can
    # disagree with itself and nothing else would notice.
    derived = None
    if len(dated) >= 2 and header_row is not None:
        base_year, target_year = min(dated), max(dated)
        ratios = set()
        for number, values in rows:
            if number <= header_row:
                continue
            b = _num(values[dated[base_year]]
                     if len(values) > dated[base_year] else None)
            t = _num(values[dated[target_year]]
                     if len(values) > dated[target_year] else None)
            if b in (None, 0) or t is None:
                continue
            ratios.add(round(t / b, 9))
        if len(ratios) == 1:
            derived = Rebasing(
                base_year=base_year, target_year=target_year,
                multiplier=ratios.pop(),
                note=f"derived from the UKP {target_year} and UKP "
                     f"{base_year} columns, consistent on every row")
        elif ratios:
            result.problems.append(
                f"UKP {target_year} is not a constant multiple of UKP "
                f"{base_year}: {len(ratios)} different ratios across the "
                "sheet, so no single rebasing multiplier can be read")

    # The figures are per one penny. Anything else silently rescales them.
    if per_pence_col is not None and header_row is not None:
        per = {_num(values[per_pence_col])
               for number, values in rows
               if number > header_row and len(values) > per_pence_col
               and _num(values[per_pence_col]) is not None}
        if per and per != {1.0}:
            result.problems.append(
                "the Pence column is not 1 throughout (%s), so the factors "
                "are not per penny" % ", ".join(str(x) for x in sorted(per)))

    # The rebasing labels can sit anywhere, above or below the table.
    rebasing = Rebasing()
    for _, values in rows:
        rebasing.base_year = rebasing.base_year or _int(
            _find_labelled(values, _BASE_YEAR))
        rebasing.target_year = rebasing.target_year or _int(
            _find_labelled(values, _TARGET_YEAR))
        if rebasing.multiplier is None:
            rebasing.multiplier = _num(_find_labelled(values, _MULTIPLIER))
    if (rebasing.base_year or rebasing.target_year
            or rebasing.multiplier is not None):
        result.rebasing = rebasing
    elif derived is not None:
        # Labelled cells win where they exist; this is the fallback.
        result.rebasing = derived

    # --- what could not be read ------------------------------------------
    if header_row is None:
        populated = any(
            any(c is not None and _text(c) is not None for c in values)
            for _, values in rows)
        result.problems.append(
            "no Year/Pounds-per-penny header row found"
            + ("" if populated else " — the sheet is empty"))
    else:
        blank = [f.year for f in result.factors if f.pounds_per_penny is None]
        if blank:
            result.problems.append(
                f"{len(blank)} year(s) listed with no factor: "
                + ", ".join(str(y) for y in blank[:10])
                + (" ..." if len(blank) > 10 else ""))
        seen = [f.year for f in result.factors]
        duplicates = sorted({y for y in seen if seen.count(y) > 1})
        if duplicates:
            result.problems.append(
                "the same year appears more than once: "
                + ", ".join(str(y) for y in duplicates))

    if result.rebasing is None:
        result.problems.append(
            "no base year / target year / inflation multiplier found")
    elif result.rebasing.multiplier is None:
        result.problems.append("the inflation multiplier is missing")

    return result


def convert(pence, year, factors, rebasing):
    """Pence of `year` -> pounds of the rebasing's target year, or None.

    None wherever the reference data cannot answer, which is the same
    behaviour the rest of the calculation chain has: a figure that would look
    real and mean nothing is worse than a blank. See `app/lib/services/
    pricing.dart`, which is where this belongs once the factors arrive.
    """
    if pence is None or year is None:
        return None
    factor = factors.get(year)
    if factor is None or factor.pounds_per_penny is None:
        return None
    base = pence * factor.pounds_per_penny
    if rebasing is None or rebasing.multiplier is None:
        return None
    return base * rebasing.multiplier


# --------------------------------------------------------------- self-test --
def _self_test():
    empty = parse([(n, (None,) * 5) for n in range(1, 10)])
    assert empty.is_empty
    assert empty.header_row is None
    assert any("sheet is empty" in p for p in empty.problems), empty.problems

    sheet = parse([
        (1, ("Base year", 2017, None, None, None)),
        (2, ("Target year", 2026, None, None, None)),
        (3, ("Inflation multiplier", 1.34, None, None, None)),
        (4, (None,) * 5),
        (5, ("Year", "Pounds per penny", "Basis", "Source", "Note")),
        (6, (1270, 0.0042, "retail prices", "MeasuringWorth", "provisional")),
        (7, (1271, "£0.0043", "retail prices", None, None)),
        (8, (1272, None, None, None, None)),
        (9, ("not a year", 0.1, None, None, None)),
    ])
    assert sheet.header_row == 5
    assert [f.year for f in sheet.factors] == [1270, 1271, 1272]
    assert sheet.factors[0].pounds_per_penny == 0.0042
    # A typed pound sign and thousands separators must not lose the number.
    assert sheet.factors[1].pounds_per_penny == 0.0043
    assert sheet.factors[0].basis == "retail prices"
    assert sheet.rebasing.base_year == 2017
    assert sheet.rebasing.target_year == 2026
    assert sheet.rebasing.multiplier == 1.34
    assert sheet.rebasing.is_usable
    assert any("1272" in p for p in sheet.problems), sheet.problems

    # Headers a different typist might write, in a different column order.
    other = parse([
        (1, ("YR", "Basis", "Value of a penny")),
        (2, (1270, "earnings", 0.5)),
    ])
    assert other.header_row == 1, other
    assert other.factors[0].pounds_per_penny == 0.5
    assert other.factors[0].basis == "earnings"

    # A year column with no factor column is not a header row.
    assert parse([(1, ("Year", "Comments")), (2, (1270, "x"))]).header_row is None

    # The layout the researcher actually supplied: no labelled multiplier
    # anywhere, two dated-money columns, and a Pence column of 1s.
    real = parse([
        (1, ("Year", "Function Value", "UKP 2026", "UKP 2017", "Pence")),
        (2, (1270, 4.086976, 4.086976, 3.04, 1)),
        (3, (1271, 4.086976, 4.086976, 3.04, 1)),
        (4, (1280, 3.885316, 3.885316, 2.89, 1)),
    ])
    assert real.header_row == 1, real
    # The factor is the BASE year's column, not the target's: the multiplier
    # is kept separate so one edit updates every year.
    assert [f.year for f in real.factors] == [1270, 1271, 1280]
    assert real.factors[0].pounds_per_penny == 3.04
    assert real.rebasing.base_year == 2017
    assert real.rebasing.target_year == 2026
    assert abs(real.rebasing.multiplier - 1.3444) < 1e-9, real.rebasing
    assert real.rebasing.is_usable
    assert not real.problems, real.problems
    # And the round trip lands on the sheet's own 2026 column.
    assert abs(convert(1, 1270, {f.year: f for f in real.factors},
                       real.rebasing) - 4.086976) < 1e-9

    # A target column that is not a constant multiple cannot yield one
    # multiplier, and says so rather than picking the first row's.
    ragged = parse([
        (1, ("Year", "UKP 2026", "UKP 2017")),
        (2, (1270, 4.0, 2.0)),
        (3, (1271, 9.0, 3.0)),
    ])
    assert any("not a constant multiple" in p for p in ragged.problems), ragged

    # Pence of 12 would mean the factors are per shilling, not per penny.
    shillings = parse([
        (1, ("Year", "UKP 2026", "UKP 2017", "Pence")),
        (2, (1270, 4.086976, 3.04, 12)),
    ])
    assert any("not per penny" in p for p in shillings.problems), shillings

    factors = {f.year: f for f in sheet.factors}
    assert convert(240, 1270, factors, sheet.rebasing) == 240 * 0.0042 * 1.34
    # No factor, no answer — never a plausible-looking zero.
    assert convert(240, 1272, factors, sheet.rebasing) is None
    assert convert(240, 1999, factors, sheet.rebasing) is None
    assert convert(240, 1270, factors, Rebasing(2017, 2026, None)) is None
    assert convert(None, 1270, factors, sheet.rebasing) is None

    print("currency.py self-test ok")


if __name__ == "__main__":
    _self_test()
