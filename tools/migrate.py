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
MIGRATIONS = [
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
