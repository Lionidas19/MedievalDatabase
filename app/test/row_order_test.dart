import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/entry_columns.dart';
import 'package:price_explorer/services/trend.dart';

/// Pick a unit most of the selection cannot be expressed in and the rows it
/// cannot answer for used to sit scattered down the table. Reading the figures
/// then meant sorting by that column first, purely to drive the blanks out of
/// the way, which is a workaround the reader should not have to discover.
///
/// They sink now, whatever the sort is, and the chosen sort applies within
/// each half. Nothing is hidden: the count still says how many there are and
/// the rows are still there, below.
void main() {
  PricedEntry row({
    required int year,
    double? perUnit,
    TrendEstimate? estimate,
  }) {
    final e = PriceEntry(entryId: 'e$year-$perUnit', year: year);
    return PricedEntry(
      entry: e,
      calc: e.calculate(),
      perUnit: perUnit,
      comparable: perUnit != null,
      estimate: estimate,
    );
  }

  double? byYear(PricedEntry p) => p.entry.year?.toDouble();

  List<int> yearsOf(List<PricedEntry> rows) =>
      [for (final r in rows) r.entry.year!];

  group('rows the chosen unit cannot answer for', () {
    test('sink below the ones it can, under an ascending sort', () {
      final rows = [
        row(year: 1270, perUnit: null),
        row(year: 1271, perUnit: 5),
        row(year: 1272, perUnit: null),
        row(year: 1273, perUnit: 7),
      ]..sort((a, b) =>
          comparePricedEntries(a, b, key: byYear, ascending: true));
      expect(yearsOf(rows), [1271, 1273, 1270, 1272]);
    });

    test('stay below when the sort is flipped', () {
      // The point of sinking them: reversing the sort must not parade the
      // blanks to the top, which is the same rule the per-column nulls follow.
      final rows = [
        row(year: 1270, perUnit: null),
        row(year: 1271, perUnit: 5),
        row(year: 1272, perUnit: null),
        row(year: 1273, perUnit: 7),
      ]..sort((a, b) =>
          comparePricedEntries(a, b, key: byYear, ascending: false));
      // The sunk half obeys the same sort, so 1272 comes before 1270 here.
      expect(yearsOf(rows), [1273, 1271, 1272, 1270]);
    });

    test('sink even when no column is sorted at all', () {
      final rows = [
        row(year: 1270, perUnit: null),
        row(year: 1271, perUnit: 5),
      ]..sort((a, b) =>
          comparePricedEntries(a, b, key: null, ascending: true));
      expect(yearsOf(rows), [1271, 1270]);
    });

    test('an estimate counts as a figure and keeps its place', () {
      // It is drawn in the cell with a tilde, and a reader who turned
      // estimates on is asking to see exactly those rows.
      final rows = [
        row(year: 1270, perUnit: null),
        row(
          year: 1271,
          perUnit: null,
          estimate: const TrendEstimate(
            value: 3,
            extrapolated: false,
            trend: Trend(
              slope: 0.1,
              intercept: 1,
              years: 5,
              firstYear: 1270,
              lastYear: 1275,
              rSquared: 0.8,
              basis: 'Food / Grain / Wheat',
            ),
          ),
        ),
      ]..sort((a, b) =>
          comparePricedEntries(a, b, key: byYear, ascending: true));
      expect(yearsOf(rows), [1271, 1270]);
    });

    test('a genuine nought is a figure, not a blank', () {
      // 14 entries really do record a price of nothing, and the source means
      // something by it.
      final rows = [
        row(year: 1270, perUnit: null),
        row(year: 1271, perUnit: 0),
      ]..sort((a, b) =>
          comparePricedEntries(a, b, key: byYear, ascending: true));
      expect(yearsOf(rows), [1271, 1270]);
    });
  });
}
