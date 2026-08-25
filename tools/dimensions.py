"""Works out what kind of thing each unit measures.

The spreadsheet's Metric Value column mixes grams, litres, square metres and
plain counts. Nothing labels which is which, and without that the app cannot
tell that "price per kilogram" is meaningful for grain and meaningless for
cattle counted by the head — the difference between a median of 0.17 pence and
a mean of 366.

The researcher did classify these units, without meaning to: the extra columns
of the Measures and Standards sheets record which system each unit converts
into. A unit with a Litres figure is a volume; one with a Gram figure is a
mass; one carrying only Heads/Entities is a count. Reading their own columns
beats guessing from names.

Everything here is provisional until the researcher confirms it — see
tools/build_review_db.py, which puts each guess in front of them with the
evidence behind it.
"""

#: Columns that only ever appear on a real weight.
STRONG_MASS = {
    "Gram", "Kg", "US Pound", "US Pounds", "US Ounce", "US Dram", "US Grain",
    "Troy Pound/Ap lb", "US Stone", "US Clove", "Units (grams/grains)",
}

#: Grain-counts are filled in for all sorts of units, countable ones included —
#: 'Dozen, Lampreys [12 heads]' carries a Barley Grains figure. On their own
#: they say nothing about what kind of unit this is.
WEAK_MASS = {"Wheat Grains", "Barley Grains"}

COUNT = {"Heads/Entities", "Bundles", "Pairs"}
VOLUME = {"Litres", "Gallons", "Quart", "Wine Pint", "US Bushel", "US Peck"}
LENGTH = {"Metres", "Km", "Cm", "Feet", "Inches", "Yards"}

#: Last resort, for units carrying no conversion columns at all.
NAME_HINTS = [
    ("area", ("acre", "sq yd", "rood", "perch")),
    ("length", ("mile", " ft", "yard", "ell ", "foot")),
    ("volume", ("gal]", "gallon", "litre", "pipe", "tun,", "hogshead")),
    ("count", ("heads", "dozen", "hundred", "thousand", "pairs", "score",
               "garb", "bundle", "units")),
    ("mass", (" lb", "grains", "ounce", "stone", "pound", "clove", "wey",
              "sack", "fother")),
]

#: A unit of this "dimension" is a normaliser rather than a measurement — the
#: brief's device for "treat this as a single unit so later calculations do not
#: multiply it". See `comparable` for what it will and will not convert into.
PER_UNIT = "per-unit"


#: The Standards sheet is a full conversion matrix: every row carries a figure
#: for every column, so which columns a row has says nothing about what it
#: measures. Its names are unambiguous instead — 'Tower Bushel', 'Old English
#: Mile', 'Acre (Cornwall to Statutory)' — so those are read directly. Order
#: matters: 'Acre' before the weight words, since no acre name contains one.
STANDARD_NAME_RULES = [
    ("area", ("acre",)),
    ("time", ("interval",)),
    ("length", ("metres", "mile")),
    ("volume", ("litres",)),
    ("count", ("heads/units", "units")),
    ("mass", ("gram", "kilogram", "bushel", "clove", "ounce", "peck", "pound",
              "quarter", "stone", "mark", "pennyweight", "dram", "crannock",
              "parts")),
]


def guess(name, metric_value, targets, vocabulary="measure"):
    """Returns (dimension_or_None, evidence, confidence).

    `targets` is the set of conversion-column names the unit carries, which is
    informative for Measures and useless for Standards — see
    STANDARD_NAME_RULES. Confidence is 'read' when taken from the researcher's
    own data, 'guessed' when inferred from the name, 'none' when we could not
    tell.
    """
    lowered = name.lower()

    if vocabulary == "standard":
        if lowered.startswith("by the") and metric_value == 1:
            return (PER_UNIT,
                    'name begins "By the" with a metric value of 1 — reads as '
                    "a normaliser rather than a measurement", "read")
        for dim, needles in STANDARD_NAME_RULES:
            if any(n in lowered for n in needles):
                return (dim, f"a {dim} standard by name", "read")
        return (None, "name does not say what kind of unit this is", "none")


    if lowered.startswith("by the") and metric_value == 1:
        return (PER_UNIT,
                'name begins "By the" with a metric value of 1 — reads as a '
                "normaliser rather than a measurement", "read")

    count = targets & COUNT
    volume = targets & VOLUME
    length = targets & LENGTH
    strong = targets & STRONG_MASS
    weak = targets & WEAK_MASS

    # Checked before mass on purpose. A unit that converts to a number of
    # heads is a count even if the sheet also worked out what those heads
    # weigh in grains; the reverse is not true.
    if count and not strong and not volume and not length:
        return ("count", "converts to " + ", ".join(sorted(count)), "read")

    if volume and not length and not strong:
        return ("volume", "converts to " + ", ".join(sorted(volume)[:4]), "read")

    if length and not volume and not strong:
        return ("length", "converts to " + ", ".join(sorted(length)[:4]), "read")

    if strong and not volume and not length and not count:
        return ("mass", "converts to " + ", ".join(sorted(strong)[:4]), "read")

    if weak and not (count or volume or length or strong):
        return ("mass", "converts to " + ", ".join(sorted(weak)), "read")

    present = [n for n, s in (("count", count), ("volume", volume),
                              ("length", length), ("mass", strong)) if s]
    if len(present) > 1:
        return (None,
                "converts to " + " and ".join(present) +
                " — genuinely ambiguous, needs your call", "none")

    for dim, needles in NAME_HINTS:
        if any(n in lowered for n in needles):
            return (dim,
                    "guessed from the name; it carries no conversion columns "
                    "to read", "guessed")

    return (None, "no conversion columns, and nothing in the name to go on",
            "none")


#: 'per-unit' and 'count' both mean "so many indivisible things", so a price
#: recorded per head converts happily to a price per dozen. Neither converts
#: to a weight: a day's labour priced per kilogram is as meaningless as cattle
#: priced by the kilogram, and the spreadsheet will compute both without
#: complaint.
_INTERCHANGEABLE = ({PER_UNIT, "count"},)


def comparable(a, b):
    """Whether a quantity measured in `a` can be expressed in `b`.

    Unknown dimensions are treated as comparable. Refusing to answer wherever
    we happen to be ignorant would hide far more real data than it protects,
    and the app still warns when a spread looks dimensionally mixed.
    """
    if a is None or b is None:
        return True
    if a == b:
        return True
    return any({a, b} <= group for group in _INTERCHANGEABLE)
