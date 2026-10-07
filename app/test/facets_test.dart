import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/simple/facets.dart';

/// Facet counting is the one piece of Specifics lookup with an answer that can be
/// checked rather than looked at: given these records and these filters, this
/// option finds something and that one does not.
void main() {
  PriceEntry entry({
    required int year,
    required String county,
    required String locality,
    required String category,
    String subcategory = 'Grain',
    String specific = 'Wheat',
    String? timePeriod,
    String? dimension = 'mass',
  }) =>
      PriceEntry(
        entryId: '$year-$county-$category-$specific-$locality',
        year: year,
        county: county,
        locality: locality,
        category: category,
        subcategory: subcategory,
        specific: specific,
        timePeriodName: timePeriod,
        measure1: MetricItem('m', 'Quarter', 279931.44, dimension: dimension),
      );

  final records = [
    entry(year: 1270, county: 'Norfolk', locality: 'Banham', category: 'Food'),
    entry(year: 1275, county: 'Norfolk', locality: 'Banham', category: 'Food'),
    // Labour is counted by the day, and only ever in Yorkshire.
    entry(
      year: 1275,
      county: 'Yorkshire',
      locality: 'Skipton',
      category: 'Labour',
      subcategory: 'Threshing',
      specific: 'Day',
      dimension: 'count',
    ),
    entry(year: 1288, county: 'Durham', locality: 'Stillington', category: 'Food'),
  ];

  const wholeRange = FacetQuery(startYear: 1270, endYear: 1291);

  test('with nothing chosen, every option that has records is available', () {
    final f = countFacets(records, wholeRange);
    expect(f.matching, 4);
    expect(f.counties.keys, containsAll(['Norfolk', 'Yorkshire', 'Durham']));
    expect({for (final e in f.categories.entries) e.key: e.value.total},
        {'Food': 3, 'Labour': 1});
  });

  test('a county with no labour makes Labour unavailable', () {
    final f = countFacets(
        records, const FacetQuery(startYear: 1270, endYear: 1291, county: 'Norfolk'));
    expect(f.categories['Food']?.total, 2);
    expect(f.categories.containsKey('Labour'), isFalse,
        reason: 'Norfolk has no labour on record');
  });

  test('a category counts counties as if that category were the only filter',
      () {
    final f = countFacets(
        records, const FacetQuery(startYear: 1270, endYear: 1291, category: 'Labour'));
    // Yorkshire is the only county with labour, but the county list must not
    // collapse to the one already chosen — nothing is chosen here.
    expect({for (final e in f.counties.entries) e.key: e.value.total},
        {'Yorkshire': 1});
    // And the category list still shows Food, because changing only the
    // category would find it.
    expect(f.categories['Food']?.total, 3);
  });

  test('the chosen facet is counted ignoring itself', () {
    final f = countFacets(
        records,
        const FacetQuery(
            startYear: 1270, endYear: 1291, county: 'Norfolk', category: 'Food'));
    // Counties are counted as though no county were chosen, so the other
    // counties holding Food still appear and can be switched to.
    expect(f.counties.keys, containsAll(['Norfolk', 'Durham']));
    expect(f.counties.containsKey('Yorkshire'), isFalse,
        reason: 'Yorkshire has no Food');
  });

  test('the year range is a gate, not a facet', () {
    final f = countFacets(
        records, const FacetQuery(startYear: 1270, endYear: 1272));
    expect(f.matching, 1);
    expect(f.categories.containsKey('Labour'), isFalse);
    expect({for (final e in f.counties.entries) e.key: e.value.total},
        {'Norfolk': 1});
  });

  test('labour counted by the day cannot be priced by weight', () {
    final f = countFacets(
        records, const FacetQuery(startYear: 1270, endYear: 1291, category: 'Labour'));
    expect(f.dimensions, {'count'});
    expect(f.canPriceIn('mass'), isFalse,
        reason: 'this is the case the whole feature exists for');
    expect(f.canPriceIn('count'), isTrue);
    // 'per-unit' and 'count' are the same idea: so many indivisible things.
    expect(f.canPriceIn('per-unit'), isTrue);
    // An unclassified unit stays on offer rather than being ruled out.
    expect(f.canPriceIn(null), isTrue);
  });

  test('grain can be priced by weight', () {
    final f = countFacets(
        records, const FacetQuery(startYear: 1270, endYear: 1291, category: 'Food'));
    expect(f.dimensions, {'mass'});
    expect(f.canPriceIn('mass'), isTrue);
    expect(f.canPriceIn('count'), isFalse);
  });

  test('when nothing matches, no unit is called useless', () {
    final f = countFacets(records,
        const FacetQuery(startYear: 1270, endYear: 1291, county: 'Nowhere'));
    expect(f.matching, 0);
    expect(f.canPriceIn('mass'), isTrue);
    expect(f.canPriceIn('count'), isTrue);
  });

  test('an entry failing two filters is out of reach either way', () {
    // Changing only the county would still leave the wrong category, so
    // Yorkshire must not be offered as a way to rescue this lookup.
    final f = countFacets(
        records,
        const FacetQuery(
            startYear: 1270, endYear: 1291, county: 'Norfolk', category: 'Fuel'));
    expect(f.matching, 0);
    expect(f.counties, isEmpty);
  });

  group('options that cannot answer in the chosen unit', () {
    // Labour is paid by the day, so with kilograms selected it has records
    // but no figures. That is a different state from having no records, and
    // the dropdown treats it differently: sorted below, marked, still
    // choosable, because the rows are real and worth looking at.
    PriceEntry e(String category, String? dimension) => PriceEntry(
          entryId: '$category-$dimension',
          year: 1275,
          county: 'Norfolk',
          category: category,
          unit1: 1,
          measure1: MetricItem('m', 'm', 1, dimension: dimension),
          valuationMeasure: MetricItem('m', 'm', 1, dimension: dimension),
          shillings: 1,
        );

    final entries = [
      e('Food', 'mass'),
      e('Food', 'mass'),
      e('Labour', 'count'),
    ];

    test('counted separately from how many records an option has', () {
      final f = countFacets(
        entries,
        const FacetQuery(startYear: 1270, endYear: 1291, unitDimension: 'mass'),
      );
      expect(f.categories['Food']?.total, 2);
      expect(f.categories['Food']?.priced, 2);
      // Records, but none of them priceable by weight.
      expect(f.categories['Labour']?.total, 1);
      expect(f.categories['Labour']?.priced, 0);
    });

    test('both defaults can price everything, so nothing is held back', () {
      // The two sentinels have no dimension, and a null dimension compares
      // true against anything. See [dimensionsComparable].
      final f = countFacets(
        entries,
        const FacetQuery(startYear: 1270, endYear: 1291),
      );
      expect(f.categories['Food']?.priced, 2);
      expect(f.categories['Labour']?.priced, 1);
    });
  });
}
