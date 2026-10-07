import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';

/// The one option that prices anything, which the researcher asked for as
/// "a new all-inclusive option of Heads/Unit/Kilograms, so that it always
/// generates an outcome".
///
/// The promise has two halves, and both are easy to break by accident: every
/// record must come back with a figure, and records of the same kind must
/// come back in the same unit. The second is the half that distinguishes it
/// from [MetricItem.recordedUnit], which always answers but leaves one grain
/// record in quarters and the next in bushels.
void main() {
  PriceEntry entry({
    required String measureName,
    required double metricValue,
    String? dimension,
    double shillings = 4,
    double pence = 0,
    double quantity = 1,
  }) {
    final m = MetricItem('m-$measureName', measureName, metricValue,
        dimension: dimension);
    return PriceEntry(
      entryId: 'e-$measureName',
      year: 1275,
      category: 'Food',
      unit1: quantity,
      measure1: m,
      valuationMeasure: m,
      shillings: shillings,
      pence: pence,
    );
  }

  group('what the comparable unit resolves to', () {
    test('weight goes to kilograms, counted things to the head', () {
      final grain = entry(
          measureName: 'Quarter', metricValue: 279931.44, dimension: 'mass');
      final oxen =
          entry(measureName: 'Head', metricValue: 1, dimension: 'count');

      expect(grain.resolveOutputUnit(MetricItem.comparableUnit)?.name,
          'Kilograms');
      expect(oxen.resolveOutputUnit(MetricItem.comparableUnit)?.name,
          'Heads/Units');
    });

    test('volume and length have bases of their own', () {
      expect(
        entry(measureName: 'Gallon', metricValue: 4.4, dimension: 'volume')
            .resolveOutputUnit(MetricItem.comparableUnit)
            ?.name,
        'Litres',
      );
      expect(
        entry(measureName: 'Yard', metricValue: 0.91, dimension: 'length')
            .resolveOutputUnit(MetricItem.comparableUnit)
            ?.name,
        'Metres',
      );
    });

    test("the source's own normalisers count as countable", () {
      // `dimensionsComparable` already treats per-unit and count alike, so
      // the base has to agree with it or the two disagree about the same
      // record.
      final acre = entry(
          measureName: 'By the Acre', metricValue: 1, dimension: 'per-unit');
      expect(acre.resolveOutputUnit(MetricItem.comparableUnit)?.name,
          'Heads/Units');
    });

    test('an unclassified measure keeps its own recorded price', () {
      final unknown =
          entry(measureName: 'Gad, Steel', metricValue: 1, dimension: null);
      expect(unknown.resolveOutputUnit(MetricItem.comparableUnit), isNull);
    });
  });

  group('the promise it makes', () {
    test('every record comes back with a figure, whatever it is measured in',
        () {
      final kinds = [
        entry(measureName: 'Quarter', metricValue: 279931.44, dimension: 'mass'),
        entry(measureName: 'Head', metricValue: 1, dimension: 'count'),
        entry(measureName: 'Gallon', metricValue: 4.4, dimension: 'volume'),
        entry(measureName: 'Yard', metricValue: 0.91, dimension: 'length'),
        entry(measureName: 'By the Acre', metricValue: 1, dimension: 'per-unit'),
        entry(measureName: 'Gad, Steel', metricValue: 1, dimension: null),
      ];
      for (final e in kinds) {
        final p = e.pricedIn(MetricItem.comparableUnit);
        expect(p.comparable, isTrue, reason: e.entryId);
        expect(p.perUnit, isNotNull, reason: e.entryId);
        expect(p.perUnit!.isFinite, isTrue, reason: e.entryId);
      }
    });

    test('two records of the same kind come back in the same unit', () {
      // The whole point, and the thing the recorded unit cannot do: a quarter
      // and a bushel of the same goods should both end up per kilogram.
      final byQuarter = entry(
          measureName: 'Quarter', metricValue: 279931.44, dimension: 'mass');
      final byBushel = entry(
          measureName: 'Bushel', metricValue: 34991.43, dimension: 'mass');

      final a = byQuarter.pricedIn(MetricItem.comparableUnit);
      final b = byBushel.pricedIn(MetricItem.comparableUnit);
      expect(a.unit?.name, 'Kilograms');
      expect(b.unit?.name, 'Kilograms');

      // Same money, eight times the goods, so an eighth of the price per
      // kilogram. Priced by their own measures they would both read 48.
      expect(a.perUnit! / b.perUnit!, closeTo(1 / 8, 0.0001));
      expect(byQuarter.pricedIn(MetricItem.recordedUnit).perUnit,
          byBushel.pricedIn(MetricItem.recordedUnit).perUnit);
    });

    test('nothing is ever struck out for being the wrong kind', () {
      final oxen =
          entry(measureName: 'Head', metricValue: 1, dimension: 'count');
      expect(oxen.canBePricedPer(MetricItem.comparableUnit), isTrue);
      // Where a concrete unit would refuse it.
      final kg = MetricItem('kg', 'Kilograms', 1000, dimension: 'mass');
      expect(oxen.canBePricedPer(kg), isFalse);
    });
  });
}
