/// The spreadsheet's calculation chain, reimplemented.
///
/// `tools/CALCULATIONS.md` records how these formulas were recovered from the
/// source workbook and what each one meant there. Everything in this file is a
/// pure function over plain numbers — no database, no browser — so it runs
/// under `flutter test` on the Dart VM and can be validated row by row against
/// the values Google Sheets cached.
///
/// Two behaviours are deliberate and must not be "fixed":
///
///  * Each of the three quantity terms in [totalMetric] is guarded
///    individually, so a measure the source never defined contributes zero
///    rather than failing the entry. That mirrors the sheet's
///    `IFERROR(lookup * qty, 0)`.
///  * Everything downstream is unguarded. When a divisor is missing or zero
///    the result is null, which is the sheet's `#N/A` / `#DIV/0!`. 2,941 of
///    10,379 entries genuinely have no price per output unit; reporting that
///    honestly is the correct answer, not a gap to paper over.
library;

/// Divides, treating a missing or zero divisor as "no answer" — the sheet's
/// `#DIV/0!`. Zero is not a near-miss here: a zero denominator means the
/// entry's quantity never resolved, so any number we invented would be wrong.
double? _divide(double? numerator, double? denominator) {
  if (numerator == null || denominator == null || denominator == 0) return null;
  final result = numerator / denominator;
  return result.isFinite ? result : null;
}

/// One quantity paired with the metric value of the measure it is counted in.
///
/// [metricValue] is null when the source never defined that measure, in which
/// case the pair contributes nothing.
class MeasuredQuantity {
  const MeasuredQuantity(this.quantity, this.metricValue);

  final double? quantity;
  final double? metricValue;

  /// True when the measure resolved — useful for explaining a zero result to
  /// the reader instead of silently showing one.
  bool get isResolved => metricValue != null;

  double get metric => (metricValue ?? 0) * (quantity ?? 0);
}

/// The recorded price, in the source's £/s/d.
///
/// The brief notes these are "often unit prices NOT the total price — think of
/// it like someone's hourly wage rather than their pay slip", which is why
/// [PriceCalculation.totalSaleInPence] multiplies by the valuation count.
class RecordedPrice {
  const RecordedPrice({this.pounds, this.shillings, this.pence});

  final double? pounds;
  final double? shillings;
  final double? pence;

  /// The sheet's "Val Meas Price per Numb in Pence": `£×240 + s×12 + d`.
  double get inPence =>
      (pounds ?? 0) * 240 + (shillings ?? 0) * 12 + (pence ?? 0);

  bool get isZero => inPence == 0;
}

/// Everything the chain derives for one entry, at one chosen output unit.
///
/// A null field means the source could not answer either — see the class-level
/// note above.
class PriceCalculation {
  const PriceCalculation({
    required this.totalMetric,
    required this.priceInPence,
    required this.valuationMetric,
    required this.valuationCount,
    required this.totalSaleInPence,
    required this.outputXValue,
    required this.outputYQuantity,
    required this.pencePerOutputY,
    required this.unresolvedMeasures,
  });

  /// Sheet column V, "Total Grams" — a misnomer inherited from the source.
  /// The value is metric in whatever base the measure's dimension uses, so an
  /// acre contributes square metres, not mass.
  final double totalMetric;

  /// Sheet column AC, "Val Meas Price per Numb in Pence".
  final double priceInPence;

  /// Sheet column AA, "Val Meas in Grams" — the metric value of one valuation
  /// measure. Null when that measure never resolved.
  final double? valuationMetric;

  /// Sheet column AB, "Val Meas Number" — how many valuation measures this
  /// entry covers.
  final double? valuationCount;

  /// Sheet column AD, "Total Sale in Pence".
  final double? totalSaleInPence;

  /// Sheet column Z, "Output X Value".
  final double? outputXValue;

  /// The entry's quantity expressed in the reader's chosen output unit.
  final double? outputYQuantity;

  /// Sheet column AE, "Pence per Output Y" — the headline figure.
  final double? pencePerOutputY;

  /// How many of the three quantity slots named a measure the source never
  /// defined. Non-zero means [totalMetric] is an undercount, which is worth
  /// surfacing rather than hiding.
  final int unresolvedMeasures;

  bool get hasPricePerOutput => pencePerOutputY != null;
}

/// Runs the chain for one entry.
///
/// [outputYMetric] is the reader's choice, not a property of the record: the
/// brief describes it as "the dropdown menu that gets altered" to ask what a
/// price is in modern kilograms or historic ounces. Pass the entry's own
/// stored default when the reader has not chosen.
PriceCalculation calculatePrice({
  required List<MeasuredQuantity> quantities,
  required RecordedPrice price,
  double? valuationMetric,
  double? multiplierWorkers,
  double? outputXMetric,
  double? outputYMetric,
}) {
  var totalMetric = 0.0;
  var unresolved = 0;
  for (final q in quantities) {
    totalMetric += q.metric;
    // Only count a slot as unresolved if it actually carried a quantity —
    // an empty slot naming no measure is normal, not a data problem.
    if (!q.isResolved && (q.quantity ?? 0) != 0) unresolved++;
  }

  final priceInPence = price.inPence;
  final valuationCount = _divide(totalMetric, valuationMetric);

  // IF(ISBLANK(multiplier), price × count, price × count × multiplier)
  final totalSaleInPence = valuationCount == null
      ? null
      : priceInPence * valuationCount * (multiplierWorkers ?? 1);

  final outputYQuantity = _divide(totalMetric, outputYMetric);

  return PriceCalculation(
    totalMetric: totalMetric,
    priceInPence: priceInPence,
    valuationMetric: valuationMetric,
    valuationCount: valuationCount,
    totalSaleInPence: totalSaleInPence,
    outputXValue: _divide(totalMetric, outputXMetric),
    outputYQuantity: outputYQuantity,
    pencePerOutputY: _divide(totalSaleInPence, outputYQuantity),
    unresolvedMeasures: unresolved,
  );
}

/// Formats a pence figure for display, keeping small values readable without
/// implying more precision than the source has.
String formatPence(double? pence, {int maxDecimals = 3}) {
  if (pence == null) return '—';
  if (pence == pence.roundToDouble()) return pence.toInt().toString();
  final s = pence.toStringAsFixed(maxDecimals);
  return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
}
