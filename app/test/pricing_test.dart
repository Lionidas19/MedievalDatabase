import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/services/pricing.dart';

/// One real entry, with the values Google Sheets computed for it.
///
/// These are not invented numbers: every `x*` field was read out of
/// `excel_cached_calculations`, which the ETL carries over from the source
/// workbook. Regenerate them with the query in `tools/validate_calculations.py`
/// if the source is ever revised.
class _F {
  const _F(
    this.label, {
    required this.entry,
    this.u1,
    this.v1,
    this.u2,
    this.v2,
    this.u3,
    this.v3,
    this.valuation,
    this.outX,
    this.outY,
    this.pounds,
    this.shillings,
    this.pence,
    this.mult,
    required this.xTotal,
    this.xValCount,
    required this.xPrice,
    this.xSale,
    this.xOutX,
    this.xPerY,
  });

  final String label;
  final int entry;
  final double? u1, v1, u2, v2, u3, v3;
  final double? valuation, outX, outY;
  final double? pounds, shillings, pence, mult;
  final double xTotal, xPrice;
  final double? xValCount, xSale, xOutX, xPerY;

  PriceCalculation run() => calculatePrice(
        quantities: [
          MeasuredQuantity(u1, v1),
          MeasuredQuantity(u2, v2),
          MeasuredQuantity(u3, v3),
        ],
        price: RecordedPrice(pounds: pounds, shillings: shillings, pence: pence),
        valuationMetric: valuation,
        multiplierWorkers: mult,
        outputXMetric: outX,
        outputYMetric: outY,
      );
}

const _fixtures = <_F>[
  _F('single measure, whole shillings', entry: 3,
      u1: 1.0, v1: 279931.4427, u2: null, v2: 34991.43034, u3: null, v3: 8777.01711,
      valuation: 279931.4427, outX: 1000.0, outY: 1000.0,
      pounds: null, shillings: 6.0, pence: null, mult: null,
      xTotal: 279931.4427, xValCount: 1.0, xPrice: 72.0,
      xSale: 72.0, xOutX: 279.9314427, xPerY: 0.2572058334),
  _F('three measures', entry: 4,
      u1: 16.0, v1: 279931.4427, u2: 4.0, v2: 34991.43034, u3: 4.0, v3: 8777.01711,
      valuation: 279931.4427, outX: 1000.0, outY: 1000.0,
      pounds: null, shillings: 4.0, pence: 8.0, mult: null,
      xTotal: 4653976.873, xValCount: 16.62541667, xPrice: 56.0,
      xSale: 931.0233333, xOutX: 4653.976873, xPerY: 0.2000489815),
  _F('with a workers multiplier', entry: 44,
      u1: 1.0, v1: 1.0, u2: null, v2: null, u3: null, v3: null,
      valuation: 1.0, outX: 1.0, outY: 0.8379259259,
      pounds: null, shillings: null, pence: 2.0, mult: 1.0,
      xTotal: 1.0, xValCount: 1.0, xPrice: 2.0,
      xSale: 2.0, xOutX: 1.0, xPerY: 1.675851852),
  _F('fractional pence', entry: 8,
      u1: 81.0, v1: 279931.4427, u2: 6.0, v2: 34991.43034, u3: null, v3: 8777.01711,
      valuation: 279931.4427, outX: 1000.0, outY: 1000.0,
      pounds: null, shillings: 2.0, pence: 3.75, mult: null,
      xTotal: 22884395.44, xValCount: 81.75, xPrice: 27.75,
      xSale: 2268.5625, xOutX: 22884.39544, xPerY: 0.09913141494),
  _F('pounds present', entry: 314,
      u1: 38.0, v1: 165107.712, u2: null, v2: null, u3: null, v3: null,
      valuation: 165107.712, outX: 1000.0, outY: 1000.0,
      pounds: 5.0, shillings: 13.0, pence: 4.0, mult: null,
      xTotal: 6274093.057, xValCount: 38.0, xPrice: 1360.0,
      xSale: 51680.0, xOutX: 6274.093057, xPerY: 8.237047096),
  _F('unresolved measure and empty slot leave nothing to divide by', entry: 4795,
      u1: null, v1: 34991.43034, u2: 2.0, v2: null, u3: null, v3: null,
      valuation: 34991.43034, outX: 1000.0, outY: 1000.0,
      pounds: null, shillings: 3.0, pence: 8.0, mult: null,
      xTotal: 0.0, xValCount: 0.0, xPrice: 44.0,
      xSale: 0.0, xOutX: 0.0, xPerY: null),
  _F('large total sale', entry: 6785,
      u1: 4000.0, v1: 1200.0, u2: null, v2: null, u3: null, v3: null,
      valuation: 1.0, outX: 1.0, outY: 1.0,
      pounds: null, shillings: 8.0, pence: 4.0, mult: null,
      xTotal: 4800000.0, xValCount: 4800000.0, xPrice: 100.0,
      xSale: 480000000.0, xOutX: 4800000.0, xPerY: 100.0),
];

/// The cached values are rounded to about ten significant figures, so compare
/// relatively rather than exactly.
void _expectClose(double? actual, double? expected, String what) {
  if (expected == null) {
    expect(actual, isNull, reason: '$what should have no answer');
    return;
  }
  expect(actual, isNotNull, reason: '$what should have an answer');
  final scale = [expected.abs(), actual!.abs(), 1e-12]
      .reduce((a, b) => a > b ? a : b);
  expect((actual - expected).abs() / scale, lessThan(1e-6),
      reason: '$what: got $actual, spreadsheet says $expected');
}

void main() {
  group('matches the spreadsheet', () {
    for (final f in _fixtures) {
      test('entry ${f.entry} — ${f.label}', () {
        final r = f.run();
        _expectClose(r.totalMetric, f.xTotal, 'total metric');
        _expectClose(r.priceInPence, f.xPrice, 'price in pence');
        _expectClose(r.valuationCount, f.xValCount, 'valuation count');
        _expectClose(r.totalSaleInPence, f.xSale, 'total sale');
        _expectClose(r.outputXValue, f.xOutX, 'output X value');
        _expectClose(r.pencePerOutputY, f.xPerY, 'pence per output Y');
      });
    }
  });

  group('error semantics are reproduced, not repaired', () {
    test('an unresolved measure contributes zero rather than failing the entry', () {
      final r = calculatePrice(
        quantities: const [
          MeasuredQuantity(2, 100),
          MeasuredQuantity(3, null), // named, but never defined in Measures
        ],
        price: const RecordedPrice(pence: 12),
        valuationMetric: 100,
        outputYMetric: 100,
      );
      expect(r.totalMetric, 200, reason: 'only the resolved slot counts');
      expect(r.unresolvedMeasures, 1, reason: 'and the shortfall is reported');
      expect(r.pencePerOutputY, isNotNull);
    });

    test('an empty slot is normal and is not flagged as unresolved', () {
      final r = calculatePrice(
        quantities: const [
          MeasuredQuantity(2, 100),
          MeasuredQuantity(null, null),
        ],
        price: const RecordedPrice(pence: 12),
        valuationMetric: 100,
      );
      expect(r.unresolvedMeasures, 0);
    });

    test('zero total metric yields no price per output unit (#DIV/0!)', () {
      final r = calculatePrice(
        quantities: const [MeasuredQuantity(0, 100)],
        price: const RecordedPrice(shillings: 3),
        valuationMetric: 100,
        outputYMetric: 1000,
      );
      expect(r.totalMetric, 0);
      expect(r.valuationCount, 0);
      expect(r.totalSaleInPence, 0);
      expect(r.pencePerOutputY, isNull);
      expect(r.hasPricePerOutput, isFalse);
    });

    test('an unresolved valuation measure yields no total sale (#N/A)', () {
      final r = calculatePrice(
        quantities: const [MeasuredQuantity(2, 100)],
        price: const RecordedPrice(shillings: 3),
        valuationMetric: null,
        outputYMetric: 1000,
      );
      expect(r.valuationCount, isNull);
      expect(r.totalSaleInPence, isNull);
      expect(r.pencePerOutputY, isNull);
    });
  });

  group('recorded price', () {
    test('converts £/s/d to pence', () {
      expect(const RecordedPrice(pounds: 5, shillings: 13, pence: 4).inPence, 1360);
      expect(const RecordedPrice(shillings: 4, pence: 4).inPence, 52);
      expect(const RecordedPrice().inPence, 0);
    });

    test('keeps fractional pence', () {
      expect(const RecordedPrice(shillings: 2, pence: 3.75).inPence, 27.75);
    });
  });

  group('output unit is the reader\'s choice', () {
    test('changing the output unit rescales the answer proportionally', () {
      List<MeasuredQuantity> qty() => const [MeasuredQuantity(1, 1000)];
      const price = RecordedPrice(pence: 100);

      final perKilo = calculatePrice(
        quantities: qty(), price: price, valuationMetric: 1000, outputYMetric: 1000);
      final perGram = calculatePrice(
        quantities: qty(), price: price, valuationMetric: 1000, outputYMetric: 1);

      expect(perKilo.pencePerOutputY, 100);
      expect(perGram.pencePerOutputY, closeTo(0.1, 1e-12));
    });
  });

  group('formatPence', () {
    test('renders whole numbers without decimals', () {
      expect(formatPence(72), '72');
      expect(formatPence(0), '0');
    });
    test('trims trailing zeros', () {
      expect(formatPence(0.25), '0.25');
      expect(formatPence(0.2572058334), '0.257');
    });
    test('renders a missing value as an em dash', () {
      expect(formatPence(null), '—');
    });
  });
}
