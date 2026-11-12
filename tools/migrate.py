"""Applies schema changes to a database file, in order, once each.

    python tools/migrate.py --check            # what would run, nothing written
    python tools/migrate.py                    # bring the shipped database up
    python tools/migrate.py path/to/other.sqlite

Why this exists rather than editing the database by hand:

The shipped `app/data/*.sqlite` is the source of truth, and the researcher's
copy of it is being added to continuously. So a cycle where the schema changes
*and* new entries arrive has an ordering problem. Hand-edit the repository's
copy to add a column and you are holding a database with last month's entries,
while the file that arrives has this month's and no column — the schema work is
stranded in the wrong file and has to be redone. In practice that means asking
the researcher to stop logging until you are finished.

Keeping each change as a numbered step removes the ordering entirely. Whatever
file arrives, run this against it and it comes out at the current schema. The
two kinds of update stop being coupled.

It also buys a readable history. The database is a binary blob, so git can
never show what changed inside it; this list is the only account of the schema
there is.

`PRAGMA user_version` records how far a file has come. 0 is the schema the ETL
produces, so a fresh build from the spreadsheet needs every step.
"""
import os
import sqlite3
import sys

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = os.path.join(
    _REPO_ROOT, "app", "data", "1270s80sDatabase_normalized.sqlite")


# Each step is (version, why it exists, SQL or a function taking a connection).
#
# Append only, and never edit one that has shipped: a database that already
# ran step 3 will never run it again, so changing it changes nothing for
# anybody who has it and everything for a fresh build. Correct a mistake with
# a new step.
#
# Most changes are one line, because SQLite takes ADD COLUMN directly:
#
#     (1, "Which kingdom or polity a place sat under.",
#      "ALTER TABLE places ADD COLUMN kingdom TEXT"),
#
# What SQLite will *not* do in place is change or drop a column, or add a
# constraint. Those need the documented twelve-step dance — build the new
# table, copy the rows across, drop the old, rename — which is why a step can
# also be a function:
#
#     def _split_food(conn):
#         conn.executescript(...)
#     (2, "The brief asks for Food to be two columns, not one.", _split_food),
#
# A function runs inside the same transaction as everything else here, so a
# failure half way leaves the file untouched.
def _drop_unfilled_tail(conn):
    """Entries 7441 to 7501: a year, wheat and a page number, nothing else.

    61 rows, every one of them identical: 1286, Food / Grain / Wheat, page 27,
    and no place, no quantity and no price. They are the tail of the Data
    sheet, where the dropdowns had been filled in but the record never was.

    They were kept at first on the assumption the researcher meant to fill
    them in through the app. He has now said twice to delete them, so they go.
    Deleted by what they contain rather than by row number, so the step cannot
    take a real record if the numbering ever shifts.
    """
    doomed = [
        r[0] for r in conn.execute(
            """SELECT e.entry_id
                 FROM price_entries e
                 LEFT JOIN specifics sp ON sp.specific_id = e.specific_id
                WHERE e.legacy_entry_no BETWEEN 7441 AND 7501
                  AND e.place_id IS NULL
                  AND e.unit_1 IS NULL AND e.unit_2 IS NULL
                  AND e.unit_3 IS NULL
                  AND e.pounds IS NULL AND e.shillings IS NULL
                  AND e.pence IS NULL
                  AND e.status_info IS NULL AND e.information IS NULL""")
    ]
    conn.executemany(
        "DELETE FROM price_entries WHERE entry_id = ?",
        [(i,) for i in doomed])
    # The test oracle is the frozen record of what the spreadsheet computed,
    # so rows for entries that no longer exist have to go with them or
    # check_incoming_db.py will report a dangling reference for ever after.
    conn.executemany(
        "DELETE FROM excel_cached_calculations WHERE entry_id = ?",
        [(i,) for i in doomed])
    print("    removed {} unfilled entries".format(len(doomed)))


def _classify_weights_given_in_pounds(conn):
    """Six measures whose metric value is a weight, left unclassified.

    `Ounce Avdp [1/12 lb]` holds 28.317139 and five `Gallon, X [1 Wine gal
    [8 lb]]` measures hold 3628.740924. The metric values in this database are
    grams, and those two numbers are a twelfth of a pound and eight pounds. So
    the source has already said what kind of thing these measure; the reader
    in `dimensions.py` simply had no conversion column to read it from.

    This is reading, not guessing. A gallon is a volume by its name, but the
    source gives this one as a weight, and the metric value is the figure
    every calculation uses: left as volume it would divide grams by litres.
    `dimension_source` records it as read rather than guessed for that reason.

    61 of the 64 entries the app reported as resting on an unclassified
    measure were these. The remaining three use `Skip, Corn (Cumberland)` and
    `Bula, Lead (Corff Castle)`, which have no metric value at all because
    nobody knows what they were, and those stay unclassified.
    """
    rows = conn.execute(
        """SELECT measure_id, name FROM measures
            WHERE dimension IS NULL AND metric_value IS NOT NULL
              AND (name LIKE '%[8 lb]%' OR name LIKE '%[1/12 lb]%')""").fetchall()
    conn.executemany(
        "UPDATE measures SET dimension = 'mass', dimension_source = 'read' "
        "WHERE measure_id = ?",
        [(r[0],) for r in rows])
    print("    classified {} measures as mass: {}".format(
        len(rows), ", ".join(sorted(r[1] for r in rows))))


def _report_in_2017_pounds(conn):
    """Report modern money in 2017 pounds, not 2026.

    The brief asked for UKP 2026, and the importer derived 2017 -> 2026 at
    x1.3444 from the workbook's two columns. The researcher has since decided
    against it: carrying the figures forward means keeping up with inflation
    for ever, and 2017 is the year the National Archives converter itself
    reports in. Their words: "let's just use the 2017 numbers and let users
    figure it out from there".

    Kept as a rebasing of x1 rather than deleted, so the app still reads the
    year it labels the columns with from the database, and moving to another
    year later is this same one-row change. The factors themselves are
    untouched: they were always 2017 pounds.
    """
    conn.execute(
        """UPDATE currency_rebasing
              SET target_year = base_year, multiplier = 1.0, note = ?
            WHERE id = 1 AND base_year = 2017""",
        ("Reported in the base year itself, at the researcher's request: "
         "no inflation carried forward.",))


MIGRATIONS = [
    (1, "Delete entries 7441-7501, which hold a year and nothing else.",
     _drop_unfilled_tail),
    (2, "Classify the six measures whose metric value is stated in pounds.",
     _classify_weights_given_in_pounds),
    (3, "Report modern money in 2017 pounds, as the researcher asked.",
     _report_in_2017_pounds),
]


def pending(version):
    return [m for m in sorted(MIGRATIONS) if m[0] > version]


def latest():
    return max((m[0] for m in MIGRATIONS), default=0)


def migrate(path, dry_run=False):
    if not os.path.exists(path):
        print("No such file: " + path)
        return 1

    conn = sqlite3.connect(path)
    version = conn.execute("PRAGMA user_version").fetchone()[0]
    todo = pending(version)

    print("{}\n  at schema version {}, latest is {}".format(
        os.path.relpath(path, _REPO_ROOT) if path.startswith(_REPO_ROOT)
        else path, version, latest()))

    if version > latest():
        # Someone else's newer file, or this checkout is behind. Applying
        # nothing is right, but say so rather than reporting "up to date".
        print("  ahead of this checkout - pull before touching it")
        return 1
    if not todo:
        print("  nothing to apply")
        return 0

    for number, why, _ in todo:
        print("  {} {}{}".format(number, why, " (not applied)" if dry_run else ""))
    if dry_run:
        return 0

    # Foreign keys off for the duration: a table rebuild drops and recreates a
    # table that other tables point at, and SQLite would reject that halfway
    # through even though the end state is sound. Checked again at the end,
    # which is the part that actually matters.
    conn.execute("PRAGMA foreign_keys = OFF")
    try:
        with conn:
            for number, _, step in todo:
                if callable(step):
                    step(conn)
                else:
                    conn.executescript(step)
                # Not a parameter: PRAGMA does not take one.
                conn.execute("PRAGMA user_version = {}".format(int(number)))
    except sqlite3.Error as e:
        print("  failed, nothing written: {}".format(e))
        return 1

    broken = list(conn.execute("PRAGMA foreign_key_check"))
    if broken:
        # The transaction has already committed by this point, so this is a
        # report rather than a rescue. Better to say it than to ship it.
        print("  applied, but {} references no longer resolve - "
              "restore from git and fix the step".format(len(broken)))
        return 1

    conn.execute("VACUUM")
    conn.close()
    print("  now at version {}".format(latest()))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--check"]
    sys.exit(migrate(
        os.path.expanduser(args[0]) if args else SHIPPED,
        dry_run="--check" in sys.argv))
