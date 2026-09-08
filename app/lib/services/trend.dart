/// Guesses at prices the source never recorded.
///
/// Everything else in this application refuses to invent a figure. This file
/// does the opposite, on purpose, and so has to be the most cautious thing
/// here: an estimate that looks like a record would corrupt the research the
/// database exists to support.
///
/// Three rules hold it in place.
///
///  * **It fits the middle of each year, not every sale.** A single year holds
///    saffron beside barley, and a least-squares line over raw values would be
///    dragged wherever the dearest record sits. One median per year, then a
///    line through those.
///  * **It refuses more often than it answers.** Three separate years at
///    minimum, a positive result, and never more than a decade beyond the
///    years actually observed. Outside that it returns nothing rather than a
///    number nobody should use.
///  * **It never becomes data.** Estimates are excluded from every average,
///    median and group figure the app reports. They are drawn differently,
///    labelled as estimates, and off by default.
///
/// The fit is linear because a straight line through a handful of medieval
/// harvest years is already a strong claim; anything more elaborate would
/// dress up the same thin evidence in better clothes.
library;

import 'statistics.dart';

/// A straight line through the middle price of each year.
class Trend {
  const Trend({
    required this.slope,
    required this.intercept,
    required this.years,
    required this.firstYear,
    required this.lastYear,
    required this.rSquared,
    required this.basis,
  });

  /// Pence per unit gained per year. Negative where the price fell.
  final double slope;
  final double intercept;

  /// How many distinct years the line was fitted through.
  final int years;
  final int firstYear;
  final int lastYear;

  /// How much of the year-to-year movement the line accounts for, 0 to 1.
  ///
  /// Reported rather than enforced. Prices genuinely jump with the harvest, so
  /// a low value is not necessarily a bad fit of a real trend — but a reader
  /// deciding whether to trust a guess deserves to see it.
  final double rSquared;

  /// What the line was fitted over — 'Food / Grain / Wheat' or a broader
  /// branch of the tree, whichever had enough years.
  final String basis;

  /// How far outside the observed years an estimate is still offered.
  ///
  /// A line through 1270-1291 says nothing whatever about 1450. Ten years is
  /// already generous for a series this short.
  static const maxExtrapolation = 10;

  /// The estimate for [year], or null where this line should not be asked.
  double? at(int year) {
    if (year < firstYear - maxExtrapolation ||
        year > lastYear + maxExtrapolation) {
      return null;
    }
    final value = intercept + slope * year;
    // A negative price is the line telling us it has left the region where it
    // means anything.
    return value > 0 ? value : null;
  }

  bool isExtrapolated(int year) => year < firstYear || year > lastYear;
}

/// The fewest distinct years a line may be fitted through.
const minimumYearsForTrend = 3;

/// Fits a trend through `year -> price` observations.
///
/// [observations] is every priced entry's year and its price per the chosen
/// unit. Returns null when the evidence is too thin to draw a line through.
Trend? fitTrend(Iterable<(int year, double value)> observations,
    {required String basis}) {
  // One median per year: robust to a year that happens to hold one spice
  // record among the grain.
  final byYear = <int, List<double>>{};
  for (final (year, value) in observations) {
    if (!value.isFinite || value <= 0) continue;
    byYear.putIfAbsent(year, () => []).add(value);
  }
  if (byYear.length < minimumYearsForTrend) return null;

  final points = <(double, double)>[
    for (final entry in byYear.entries)
      (entry.key.toDouble(), PriceStats.from(entry.value).median!),
  ];

  final n = points.length;
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0;
  for (final (x, y) in points) {
    sx += x;
    sy += y;
    sxy += x * y;
    sxx += x * x;
  }
  final denominator = n * sxx - sx * sx;
  // Every observation in one year: a vertical line, which is no line at all.
  if (denominator == 0) return null;

  final slope = (n * sxy - sx * sy) / denominator;
  final intercept = (sy - slope * sx) / n;

  final meanY = sy / n;
  var ssTotal = 0.0, ssResidual = 0.0;
  for (final (x, y) in points) {
    final predicted = intercept + slope * x;
    ssTotal += (y - meanY) * (y - meanY);
    ssResidual += (y - predicted) * (y - predicted);
  }
  final rSquared = ssTotal == 0 ? 1.0 : (1 - ssResidual / ssTotal).clamp(0.0, 1.0);

  final years = byYear.keys.toList()..sort();
  return Trend(
    slope: slope,
    intercept: intercept,
    years: n,
    firstYear: years.first,
    lastYear: years.last,
    rSquared: rSquared.toDouble(),
    basis: basis,
  );
}

/// What an estimate is, and what it rests on.
class TrendEstimate {
  const TrendEstimate({
    required this.value,
    required this.trend,
    required this.extrapolated,
  });

  final double value;
  final Trend trend;

  /// True where the year sits outside the years the line was fitted through,
  /// which is a materially weaker claim than filling a gap between them.
  final bool extrapolated;

  /// Said in full, because this is the number that must never be mistaken for
  /// a record.
  String explain(String unitName, int year) {
    final direction = trend.slope >= 0 ? 'rising' : 'falling';
    return 'Estimated, not recorded: about '
        '${value.toStringAsFixed(value < 1 ? 4 : 2)} pence per $unitName in '
        '$year.\n\n'
        'Fitted through the middle price of each of ${trend.years} years '
        '(${trend.firstYear}–${trend.lastYear}) for ${trend.basis}, a '
        '$direction trend accounting for '
        '${(trend.rSquared * 100).round()}% of the year-to-year movement.'
        '${extrapolated ? '\n\nThis year lies outside those, so the figure is '
            'an extrapolation and weaker still.' : ''}'
        '\n\nNo average or median in this app includes it.';
  }
}
