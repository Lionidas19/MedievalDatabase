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
  });

  final double startYear;
  final double endYear;
  final String? county;
  final String? locality;
  final String? timePeriod;
  final String? category;
  final String? subcategory;
  final String? specific;
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

  final Map<String, int> counties;
  final Map<String, int> localities;
  final Map<String, int> timePeriods;
  final Map<String, int> categories;
  final Map<String, int> subcategories;
  final Map<String, int> specifics;

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
/// tested once against each axis and records which axes it fails. An entry
/// that fails none counts towards every list; one that fails exactly one
/// counts towards that list alone — it would match if you changed only that
/// filter, which is precisely what the dropdown is offering to do. Fail two
/// and it is out of reach either way.
FacetCounts countFacets(Iterable<PriceEntry> entries, FacetQuery q) {
  final counties = <String, int>{};
  final localities = <String, int>{};
  final timePeriods = <String, int>{};
  final categories = <String, int>{};
  final subcategories = <String, int>{};
  final specifics = <String, int>{};
  final dimensions = <String?>{};
  var matching = 0;

  Map<String, int> mapFor(_Axis axis) => switch (axis) {
        _Axis.county => counties,
        _Axis.locality => localities,
        _Axis.timePeriod => timePeriods,
        _Axis.category => categories,
        _Axis.subcategory => subcategories,
        _Axis.specific => specifics,
      };

  String? valueFor(_Axis axis, PriceEntry e) => switch (axis) {
        _Axis.county => e.county,
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

    _Axis? soleFailure;
    var failures = 0;
    void check(_Axis axis, bool passes) {
      if (passes) return;
      failures++;
      soleFailure = axis;
    }

    check(_Axis.county, q.county == null || e.county == q.county);
    check(_Axis.locality, q.locality == null || e.locality == q.locality);
    check(_Axis.timePeriod,
        q.timePeriod == null || e.timePeriodName == q.timePeriod);
    check(_Axis.category, q.category == null || e.category == q.category);
    check(_Axis.subcategory,
        q.subcategory == null || e.subcategory == q.subcategory);
    check(_Axis.specific, q.specific == null || e.specific == q.specific);

    if (failures > 1) continue;

    if (failures == 0) {
      matching++;
      dimensions.add(e.primaryMeasure?.dimension);
      for (final axis in _Axis.values) {
        final v = valueFor(axis, e);
        if (v != null) mapFor(axis).update(v, (n) => n + 1, ifAbsent: () => 1);
      }
    } else {
      final axis = soleFailure!;
      final v = valueFor(axis, e);
      if (v != null) mapFor(axis).update(v, (n) => n + 1, ifAbsent: () => 1);
    }
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
