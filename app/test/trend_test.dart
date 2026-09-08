import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/services/trend.dart';

/// The estimator is the one part of this app that invents a number, so its
/// refusals matter more than its answers.
void main() {
  Trend? fit(List<(int, double)> points) =>
      fitTrend(points, basis: 'Food / Grain / Wheat');

  test('a clean straight line is recovered exactly', () {
    final t = fit([(1270, 10), (1271, 12), (1272, 14), (1273, 16)])!;
    expect(t.slope, closeTo(2, 1e-9));
    expect(t.at(1274), closeTo(18, 1e-6));
    expect(t.rSquared, closeTo(1, 1e-9));
    expect(t.years, 4);
  });

  test('it fits the middle of each year, not every sale', () {
    // 1272 holds one wild record. Fitting raw values would tilt the line;
    // fitting the year's median should not notice it at all.
    final withOutlier = fit([
      (1270, 10),
      (1271, 12),
      (1272, 14), (1272, 14), (1272, 5000),
      (1273, 16),
    ])!;
    expect(withOutlier.slope, closeTo(2, 1e-6));
    expect(withOutlier.at(1274), closeTo(18, 1e-6));
  });

  test('two years are not enough to draw a line through', () {
    expect(fit([(1270, 10), (1271, 12)]), isNull);
    expect(fit([(1270, 10), (1270, 12), (1270, 14)]), isNull,
        reason: 'three records in one year is still one year');
  });

  test('a falling trend is followed downwards', () {
    final t = fit([(1270, 20), (1271, 18), (1272, 16)])!;
    expect(t.slope, lessThan(0));
    expect(t.at(1273), closeTo(14, 1e-6));
  });

  test('it will not extrapolate beyond a decade', () {
    final t = fit([(1270, 10), (1271, 12), (1272, 14)])!;
    expect(t.at(1282), isNotNull);
    expect(t.at(1283), isNull, reason: 'eleven years past the evidence');
    expect(t.at(1259), isNull);
  });

  test('a line that would predict a negative price declines to', () {
    final t = fit([(1270, 30), (1271, 20), (1272, 10)])!;
    expect(t.at(1273), isNull, reason: 'the line has run below zero');
  });

  test('filling a gap is distinguished from reaching past the evidence', () {
    final t = fit([(1270, 10), (1272, 14), (1274, 18)])!;
    expect(t.isExtrapolated(1271), isFalse, reason: 'between observed years');
    expect(t.isExtrapolated(1275), isTrue);
  });

  test('worthless and negative observations are ignored', () {
    final t = fit([
      (1270, 10),
      (1271, 0),
      (1271, 12),
      (1272, double.infinity),
      (1272, 14),
    ])!;
    expect(t.years, 3);
    expect(t.slope, closeTo(2, 1e-6));
  });

  test('scattered years still fit, and say how well', () {
    final t = fit([(1270, 10), (1271, 25), (1272, 11), (1273, 24)])!;
    expect(t.rSquared, lessThan(0.5), reason: 'the reader should see this');
    expect(t.at(1274), isNotNull);
  });

  test('an estimate explains itself as an estimate', () {
    final t = fit([(1270, 10), (1271, 12), (1272, 14)])!;
    final e = TrendEstimate(value: t.at(1275)!, trend: t, extrapolated: true);
    final text = e.explain('Kilograms', 1275);
    expect(text, contains('Estimated, not recorded'));
    expect(text, contains('Food / Grain / Wheat'));
    expect(text, contains('extrapolation'));
    expect(text, contains('No average or median in this app includes it'));
  });
}
