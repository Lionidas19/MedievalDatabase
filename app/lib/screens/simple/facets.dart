/// Which answers the Specifics lookup form could still find.
///
/// Every dropdown on that screen offers the whole vocabulary, whether or not
/// the records hold anything matching it. Pick a county, then a category the
/// county never traded, and the form cheerfully accepts both and reports
/// nothing — leaving the reader to guess whether they mis-set a filter or
/// discovered a gap in thirteenth-century England.
///
/// So the form asks first. For each dropdown, an option is *available* when
/// choosing it would leave at least one entry standing, judged against every
/// other filter but not against itself. That last part is what makes a facet a
/// facet: the county list has to ignore the county you already picked, or it
/// would only ever list the one.
///
/// Units are a different question and get their own answer. A unit is worth
/// offering when the entries that survive the filters are measured in a *kind*
/// of thing it can express — the case the screen exists to prevent is offering
/// kilograms for labour counted by the day.
library;

import '../../models/models.dart';

/// The filters a facet count is taken against.
class FacetQuery {
  const FacetQuery({
    required this.startYear,
    required this.endYear,
    this.county,
    this.locality,
    this.timePeriod,
    this.category,
    this.subcategory,
    this.specific,
    this.unitDimension,
  });

  /// The kind of unit the reader is pricing in, so an option can be counted
  /// on whether choosing it would produce *figures* rather than merely rows.
  ///
  /// Null for the two defaults, which can price anything, and which is also
  /// what [dimensionsComparable] says about a null dimension.
  final String? unitDimension;

  final double startYear;
  final double endYear;
  final String? county;
  final String? locality;
  final String? timePeriod;
  final String? category;
  final String? subcategory;
  final String? specific;
}

/// What one dropdown option would find.
///
/// Two numbers, because there are two ways for an option to be a dead end and
/// they deserve different treatment. [total] is how many records choosing it
/// returns. [priced] is how many of those can be expressed in the unit the
/// reader is pricing in.
///
/// An option with no records at all is struck out and disabled: there is
/// nothing behind it. An option with records but none that can be priced is
/// still worth choosing — the rows are real and the table will show them —
/// it just cannot contribute to an average, so it is sorted below the ones
/// that can and marked, rather than disabled.
class FacetCount {
  const FacetCount(this.total, this.priced);
  final int total;
  final int priced;

  FacetCount get oneMoreTotal => FacetCount(total + 1, priced);
  FacetCount get oneMoreBoth => FacetCount(total + 1, priced + 1);
}

/// How many entries each option would still find.
///
/// A name absent from a map means nothing matches it. Callers should treat
/// "absent" and "zero" alike; nothing is ever stored as zero.
class FacetCounts {
  const FacetCounts({
    required this.counties,
    required this.localities,
    required this.timePeriods,
    required this.categories,
    required this.subcategories,
    required this.specifics,
    required this.dimensions,
    required this.matching,
  });

  final Map<String, FacetCount> counties;
  final Map<String, FacetCount> localities;
  final Map<String, FacetCount> timePeriods;
  final Map<String, FacetCount> categories;
  final Map<String, FacetCount> subcategories;
  final Map<String, FacetCount> specifics;

  /// The kinds of unit the fully-matching entries are measured in — mass,
  /// volume, count and so on, with null for the ones nobody has classified.
  final Set<String?> dimensions;

  /// How many entries pass every filter at once.
  final int matching;

  /// The kinds of unit these entries use, in words a reader would use.
  ///
  /// The database's own names for them — 'per-unit', 'mass' — are the ETL's
  /// vocabulary and read as jargon in a sentence.
  String get dimensionsInWords {
    const readable = {
      'mass': 'weight',
      'volume': 'volume',
      'area': 'area',
      'length': 'length',
      'time': 'time',
      'count': 'the head or the dozen',
      'per-unit': 'the unit',
    };
    final words = {
      for (final d in dimensions) readable[d] ?? 'something unrecorded',
    }.toList()
      ..sort();
    if (words.length <= 1) return words.isEmpty ? 'nothing' : words.first;
    return '${words.take(words.length - 1).join(', ')} and ${words.last}';
  }

  /// Whether a unit of this dimension could price any of them.
  ///
  /// True when nothing matches at all: with no entries in hand there is no
  /// ground for calling a unit useless, and greying out every option because a
  /// county is empty would be its own kind of lie.
  bool canPriceIn(String? unitDimension) =>
      dimensions.isEmpty ||
      dimensions.any((d) => dimensionsComparable(d, unitDimension));

  static const empty = FacetCounts(
    counties: {},
    localities: {},
    timePeriods: {},
    categories: {},
    subcategories: {},
    specifics: {},
    dimensions: {},
    matching: 0,
  );
}

/// The axes a count can be taken along. Years are not among them: they are a
/// range rather than a list, so there is no option to grey out.
enum _Axis { county, locality, timePeriod, category, subcategory, specific }

/// Counts every dropdown's options in a single pass.
///
/// One pass rather than one per option: with 7,800 entries and some 250
/// options across the form, asking each option separately would be a quarter
/// of a million comparisons every time a filter moved. Instead each entry is
/// tested once against each filter, and counts towards a list wherever it
/// would match if only that choice were changed, which is precisely what the
/// dropdown is offering to do. For county, place and time that means passing
/// every other filter. For the item levels it means passing the ones above,
/// since changing a level clears those below it.
FacetCounts countFacets(Iterable<PriceEntry> entries, FacetQuery q) {
  final counties = <String, FacetCount>{};
  final localities = <String, FacetCount>{};
  final timePeriods = <String, FacetCount>{};
  final categories = <String, FacetCount>{};
  final subcategories = <String, FacetCount>{};
  final specifics = <String, FacetCount>{};
  final dimensions = <String?>{};
  var matching = 0;

  Map<String, FacetCount> mapFor(_Axis axis) => switch (axis) {
        _Axis.county => counties,
        _Axis.locality => localities,
        _Axis.timePeriod => timePeriods,
        _Axis.category => categories,
        _Axis.subcategory => subcategories,
        _Axis.specific => specifics,
      };

  String? valueFor(_Axis axis, PriceEntry e) => switch (axis) {
        // Counted under the bare name, so the counts line up with the
        // options the pickers actually offer. See [bareCountyName].
        _Axis.county => e.county == null ? null : bareCountyName(e.county!),
        _Axis.locality => e.locality,
        _Axis.timePeriod => e.timePeriodName,
        _Axis.category => e.category,
        _Axis.subcategory => e.subcategory,
        _Axis.specific => e.specific,
      };

  for (final e in entries) {
    // The year range is not a facet, so failing it puts an entry out of every
    // count rather than out of one.
    final year = e.year;
    if (year == null || year < q.startYear || year > q.endYear) continue;

    final county = q.county == null ||
        (e.county != null && bareCountyName(e.county!) == q.county);
    final locality = q.locality == null || e.locality == q.locality;
    final time = q.timePeriod == null || e.timePeriodName == q.timePeriod;
    final category = q.category == null || e.category == q.category;
    final subcategory =
        q.subcategory == null || e.subcategory == q.subcategory;
    final specific = q.specific == null || e.specific == q.specific;

    final where = county && locality && time;
    final what = category && subcategory && specific;

    // Which lists this record can count towards. County, place and time of
    // year are each judged against every other filter, as above.
    //
    // The three item levels are not, because they nest: choosing a category
    // clears the subcategory and specific beneath it, and choosing a
    // subcategory clears the specific. So each is judged without the levels
    // below it. Judged with them, picking "wheat" from the search box struck
    // out every other subcategory and every other category as "(none)" (no
    // fish is wheat), and the reader could not move off Grain at all without
    // first finding a way to clear it.
    final counts = <_Axis>[
      if (locality && time && what) _Axis.county,
      if (county && time && what) _Axis.locality,
      if (county && locality && what) _Axis.timePeriod,
      if (where) _Axis.category,
      if (where && category) _Axis.subcategory,
      if (where && category && subcategory) _Axis.specific,
    ];
    if (counts.isEmpty) continue;

    // Whether this record could be expressed in the unit being asked for,
    // which is a different question from whether it matches the filters.
    final priced =
        dimensionsComparable(e.primaryMeasure?.dimension, q.unitDimension);

    void tally(_Axis axis) {
      final v = valueFor(axis, e);
      if (v == null) return;
      mapFor(axis).update(
        v,
        (c) => priced ? c.oneMoreBoth : c.oneMoreTotal,
        ifAbsent: () => priced ? const FacetCount(1, 1) : const FacetCount(1, 0),
      );
    }

    if (where && what) {
      matching++;
      dimensions.add(e.primaryMeasure?.dimension);
    }
    counts.forEach(tally);
  }

  return FacetCounts(
    counties: counties,
    localities: localities,
    timePeriods: timePeriods,
    categories: categories,
    subcategories: subcategories,
    specifics: specifics,
    dimensions: dimensions,
    matching: matching,
  );
}
