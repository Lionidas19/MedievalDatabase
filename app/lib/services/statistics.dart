/// Summary figures over a set of prices.
///
/// Median first, everywhere. The source measures goods in units many thousands
/// of times apart, and even within one output unit a broad selection holds
/// saffron beside barley — a mean over that says almost nothing, while the
/// median says what a typical record looks like. Food across the whole range
/// has a median of 0.17 pence per kilogram and a mean of 366.
///
/// The mean is still offered, because for a narrow selection it is the more
/// useful of the two and refusing to show it would be its own kind of
/// paternalism.
library;

class PriceStats {
  const PriceStats._({
    required this.count,
    required this.median,
    required this.mean,
    required this.mode,
    required this.lowest,
    required this.highest,
  });

  static const empty = PriceStats._(
    count: 0,
    median: null,
    mean: null,
    mode: null,
    lowest: null,
    highest: null,
  );

  /// How many values these figures were taken over. Never assume it matches
  /// the number of entries on screen: an entry the source cannot price is
  /// excluded rather than counted as zero.
  final int count;

  final double? median;
  final double? mean;

  /// The most common value, to the nearest hundredth of a penny.
  ///
  /// Unrounded, a mode over computed figures is meaningless — no two divisions
  /// land on the same twelfth decimal place, so every value would be its own
  /// mode.
  final double? mode;

  final double? lowest;
  final double? highest;

  bool get isEmpty => count == 0;

  /// True when the values span far enough that a mean misleads.
  ///
  /// Not a proxy for mixed-up units — entries measured in the wrong kind of
  /// unit are excluded before they get here. What is left is real spread: a
  /// broad category holds both barley at a fraction of a penny per kilogram
  /// and spices at thousands.
  bool get isWidelySpread {
    if (count < 5) return false;
    final m = median;
    if (m == null || m <= 0) return false;
    return (highest ?? 0) / m > 100;
  }

  /// How many times the middle of the pack the dearest value is.
  double? get spreadFactor {
    final m = median;
    if (m == null || m <= 0) return null;
    return (highest ?? 0) / m;
  }

  factory PriceStats.from(Iterable<double> values) {
    final sorted = [
      for (final v in values)
        if (v.isFinite) v,
    ]..sort();
    if (sorted.isEmpty) return empty;

    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;

    final counts = <double, int>{};
    for (final v in sorted) {
      final bucket = (v * 100).round() / 100;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    final mode =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return PriceStats._(
      count: sorted.length,
      median: median,
      mean: sorted.reduce((a, b) => a + b) / sorted.length,
      mode: mode,
      lowest: sorted.first,
      highest: sorted.last,
    );
  }
}
