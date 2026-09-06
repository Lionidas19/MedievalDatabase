import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/services/statistics.dart';

void main() {
  test('no values means no figures, not zeroes', () {
    final s = PriceStats.from(const []);
    expect(s.isEmpty, isTrue);
    expect(s.median, isNull);
    expect(s.mean, isNull);
    expect(s.count, 0);
  });

  test('median of an odd count is the middle value', () {
    expect(PriceStats.from([3, 1, 2]).median, 2);
  });

  test('median of an even count is the midpoint of the middle pair', () {
    expect(PriceStats.from([1, 2, 3, 4]).median, 2.5);
  });

  test('mode rounds to the hundredth, or every value is its own mode', () {
    // These are computed divisions, not tallies: unrounded, no two would meet.
    final s = PriceStats.from([0.1141, 0.1142, 0.1143, 0.9]);
    expect(s.mode, closeTo(0.11, 1e-9));
  });

  test('a spread of more than a hundredfold is called out', () {
    final narrow = PriceStats.from([1, 1.1, 1.2, 1.3, 1.4]);
    expect(narrow.isWidelySpread, isFalse);

    // Barley beside saffron: the mean here is not worth reporting alone.
    final wide = PriceStats.from([0.1, 0.11, 0.12, 0.13, 500]);
    expect(wide.isWidelySpread, isTrue);
    expect(wide.spreadFactor, greaterThan(100));
  });

  test('fewer than five values is too few to call widely spread', () {
    expect(PriceStats.from([0.1, 900]).isWidelySpread, isFalse);
  });

  test('infinities are dropped rather than poisoning the mean', () {
    final s = PriceStats.from([1, 2, double.infinity]);
    expect(s.count, 2);
    expect(s.mean, 1.5);
  });

  test('lowest and highest bound the sample', () {
    final s = PriceStats.from([5, 1, 9, 3]);
    expect(s.lowest, 1);
    expect(s.highest, 9);
    expect(s.count, 4);
  });
}
