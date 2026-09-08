"""Checks a database sent back by the researcher before it becomes the one
everybody gets.

    python tools/check_incoming_db.py "~/Downloads/1270s80sDatabase-2026-09-07.sqlite"

The shipped `app/data/*.sqlite` is the source of truth for every visitor, and
it arrives here as a file exported from somebody's browser. Git cannot help
review it: the database is a binary blob, so `git diff` reports only that nine
megabytes changed. This prints what actually changed, and refuses the file
outright if it is broken.

Nothing here decides whether a change is *right* — correcting a misread price
is the whole point of the editor. It reports, so that whoever commits can see
what they are about to publish. Two exceptions are hard failures, because no
intended edit produces them: a database that will not open, and one whose
references no longer resolve.

Exit code 1 means do not commit this file.
"""
import os
import sqlite3
import sys

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = os.path.join(
    _REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")

# How many changed rows to name before summarising. Enough to see the shape of
# an afternoon's corrections, short of a wall of output when a whole column has
# been reworked.
SAMPLE = 15

problems = []   # fatal: do not commit
notes = []      # expected, but worth reading before pushing


def columns(conn, schema, table):
    return [r[1] for r in conn.execute('PRAGMA {}.table_info("{}")'.format(
        schema, table))]


def tables(conn, schema):
    return {r[0] for r in conn.execute(
        "SELECT name FROM {}.sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%'".format(schema))}


def check(incoming):
    if not os.path.exists(incoming):
        print("No such file: " + incoming)
        return 1
    if not os.path.exists(SHIPPED):
        print("No shipped database to compare against at " + SHIPPED)
        return 1

    try:
        conn = sqlite3.connect("file:{}?mode=ro".format(incoming), uri=True)
        conn.execute("SELECT 1 FROM sqlite_master LIMIT 1")
    except sqlite3.Error as e:
        print("Will not open as SQLite: {}".format(e))
        return 1

    # ---------------------------------------------------------- integrity ---
    bad = [r[0] for r in conn.execute("PRAGMA integrity_check") if r[0] != "ok"]
    if bad:
        problems.append("integrity_check: " + "; ".join(bad[:5]))

    # A browser export is a byte copy of an in-memory image, so a torn write is
    # unlikely. A file that travelled by email or a cloud drive has had plenty
    # of other chances to be mangled.
    orphans = list(conn.execute("PRAGMA foreign_key_check"))
    if orphans:
        by_table = {}
        for row in orphans:
            by_table[row[0]] = by_table.get(row[0], 0) + 1
        problems.append("references that no longer resolve: " + ", ".join(
            "{} ({})".format(t, n) for t, n in sorted(by_table.items())))

    conn.execute("ATTACH DATABASE ? AS base", (SHIPPED,))

    # ------------------------------------------------------------- shape ----
    here, there = tables(conn, "main"), tables(conn, "base")
    if there - here:
        problems.append("tables missing: " + ", ".join(sorted(there - here)))
    if here - there:
        notes.append("tables added: " + ", ".join(sorted(here - there)))

    for table in sorted(here & there):
        a = set(columns(conn, "main", table))
        b = set(columns(conn, "base", table))
        if b - a:
            problems.append("{}: columns missing: {}".format(
                table, ", ".join(sorted(b - a))))
        if a - b:
            notes.append("{}: columns added: {}".format(
                table, ", ".join(sorted(a - b))))

    v_in = conn.execute("PRAGMA main.user_version").fetchone()[0]
    v_out = conn.execute("PRAGMA base.user_version").fetchone()[0]
    if v_in != v_out:
        notes.append(
            "schema version {}, shipped is {} - run tools/migrate.py "
            "before committing".format(v_in, v_out))

    # ------------------------------------------------------------ content ---
    print("  {:<28} {:>9} {:>9}   change".format("table", "shipped", "incoming"))
    for table in sorted(here & there):
        n_in = conn.execute(
            'SELECT COUNT(*) FROM main."{}"'.format(table)).fetchone()[0]
        n_out = conn.execute(
            'SELECT COUNT(*) FROM base."{}"'.format(table)).fetchone()[0]
        delta = n_in - n_out
        if delta or table == "price_entries":
            mark = "{:+}".format(delta) if delta else "-"
            print("  {:<28} {:>9} {:>9}   {}".format(table, n_out, n_in, mark))

    # The frozen oracle. It records what Google Sheets computed for the
    # original 7,800 and is what app/test/calculation_corpus_test.dart holds
    # the Dart implementation to. Editing it would not break the app; it would
    # quietly destroy the only independent check on the calculation chain.
    if "excel_cached_calculations" in here & there:
        altered = conn.execute(
            "SELECT COUNT(*) FROM main.excel_cached_calculations i "
            "JOIN base.excel_cached_calculations b USING(entry_id) "
            "WHERE i.total_sale_in_pence IS NOT b.total_sale_in_pence "
            "   OR i.total_grams IS NOT b.total_grams").fetchone()[0]
        if altered:
            problems.append(
                "excel_cached_calculations altered in {} rows - it is the "
                "test oracle and must stay as the spreadsheet left it".format(
                    altered))

    # -------------------------------------------------- entries, in detail --
    shared = [c for c in columns(conn, "main", "price_entries")
              if c in columns(conn, "base", "price_entries") and c != "entry_id"]
    where = " OR ".join('i."{0}" IS NOT b."{0}"'.format(c) for c in shared)
    edited = list(conn.execute(
        "SELECT b.legacy_entry_no FROM main.price_entries i "
        "JOIN base.price_entries b USING(entry_id) "
        "WHERE {} ORDER BY b.legacy_entry_no".format(where)))
    if edited:
        notes.append("{} existing {} edited: {}".format(
            len(edited), _plural(len(edited)),
            _sample(r[0] for r in edited)))
        notes.append(
            "  -> those rows feed calculation_corpus_test.dart; run "
            "`cd app && flutter test` and expect it to disagree exactly "
            "where you meant it to")

    added = conn.execute(
        "SELECT COUNT(*) FROM main.price_entries WHERE entry_id NOT IN "
        "(SELECT entry_id FROM base.price_entries)").fetchone()[0]
    if added:
        notes.append("{} {} added".format(added, _plural(added)))

    # Deletion is a real feature of the editor, but it is the one edit that
    # cannot be spotted by reading the app afterwards - the row is simply not
    # there to notice.
    removed = list(conn.execute(
        "SELECT legacy_entry_no FROM base.price_entries WHERE entry_id NOT IN "
        "(SELECT entry_id FROM main.price_entries) ORDER BY legacy_entry_no"))
    if removed:
        notes.append("{} {} DELETED: {}".format(
            len(removed), _plural(len(removed)),
            _sample(r[0] for r in removed)))

    if not conn.execute(
            "SELECT COUNT(*) FROM main.price_entries").fetchone()[0]:
        problems.append("no price entries at all")

    # ------------------------------------------------------------ verdict ---
    print()
    for n in notes:
        print("  review   " + n)
    for p in problems:
        print("  STOP     " + p)
    print()
    if problems:
        print("Do not commit this file.")
        return 1
    print("Nothing broken. Read the review lines above, then copy it over")
    print(os.path.relpath(SHIPPED, _REPO_ROOT) + " and commit.")
    return 0


def _plural(n):
    return "entry" if n == 1 else "entries"


def _sample(numbers):
    ns = list(numbers)
    shown = ", ".join(str(n) for n in ns[:SAMPLE])
    return shown + (" and {} more".format(len(ns) - SAMPLE)
                    if len(ns) > SAMPLE else "")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(check(os.path.expanduser(sys.argv[1])))
