import '../services/pricing.dart';

/// A generic (id, label) pair used to populate dropdown/autocomplete pickers
/// that are backed by a lookup table (places, sources, ...).
class LookupItem {
  const LookupItem(this.id, this.label);
  final String id;
  final String label;

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) => other is LookupItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// An entry from one of the two unit vocabularies, carrying the metric value
/// every calculation depends on.
///
/// `measures` and `standards` are separate tables on purpose — see
/// `tools/CALCULATIONS.md`. MEASURE 1/2/3 and the valuation measure come from
/// `measures`; output X and output Y come from `standards`.
///
/// [metricValue] is null when the source workbook names the unit but never
/// defines it. Such a unit contributes zero to a total rather than failing the
/// entry, exactly as the spreadsheet behaves.
class MetricItem {
  const MetricItem(this.id, this.name, this.metricValue);

  final String id;
  final String name;
  final double? metricValue;

  bool get isResolved => metricValue != null;

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) => other is MetricItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class CategoryOption {
  const CategoryOption(this.id, this.name);
  final String id;
  final String name;
}

class SubcategoryOption {
  const SubcategoryOption(this.id, this.categoryId, this.name);
  final String id;
  final String categoryId;
  final String name;
}

class SpecificOption {
  const SpecificOption(this.id, this.subcategoryId, this.name);
  final String id;
  final String subcategoryId;
  final String name;
}

/// One row of the price_entries fact table.
///
/// Only recorded facts are stored. Everything the old spreadsheet kept as a
/// derived column — total grams, price in pence, pence per output Y and the
/// rest — is computed on demand by [calculate], because the unit those figures
/// are "per" is chosen by the reader, not fixed by the record.
///
/// Dimension names and their metric values are resolved alongside the foreign
/// keys so the UI can display and calculate without extra queries.
class PriceEntry {
  PriceEntry({
    required this.entryId,
    this.legacyEntryNo,
    this.year,
    this.timePeriodId,
    this.timePeriodName,
    this.dayOfMonth,
    this.placeId,
    this.locality,
    this.county,
    this.specificId,
    this.category,
    this.subcategory,
    this.specific,
    this.unit1,
    this.unit2,
    this.unit3,
    this.measure1,
    this.measure2,
    this.measure3,
    this.multiplierWorkers,
    this.multiplierMeasureId,
    this.multiplierMeasureName,
    this.pounds,
    this.shillings,
    this.pence,
    this.valuationMeasure,
    this.outputX,
    this.outputY,
    this.statusInfo,
    this.food,
    this.countryId,
    this.countryName,
    this.coinTypeId,
    this.coinTypeName,
    this.information,
    this.sourceId,
    this.sourceCitation,
    this.page,
  });

  final String entryId;
  int? legacyEntryNo;
  int? year;
  String? timePeriodId;
  String? timePeriodName;
  int? dayOfMonth;

  String? placeId;
  String? locality;
  String? county;

  String? specificId;
  String? category;
  String? subcategory;
  String? specific;

  /// Quantities, each interpreted by the measure in the matching slot.
  double? unit1;
  double? unit2;
  double? unit3;
  MetricItem? measure1;
  MetricItem? measure2;
  MetricItem? measure3;

  double? multiplierWorkers;
  String? multiplierMeasureId;
  String? multiplierMeasureName;

  /// The recorded price. Often a price *per valuation measure* rather than a
  /// total, which is why [calculate] multiplies by the valuation count.
  double? pounds;
  double? shillings;
  double? pence;

  MetricItem? valuationMeasure;
  MetricItem? outputX;

  /// The entry's own default output unit. The reader may override it, which is
  /// the whole point of computing rather than storing the result.
  MetricItem? outputY;

  String? statusInfo;
  String? food;
  String? countryId;
  String? countryName;
  String? coinTypeId;
  String? coinTypeName;
  String? information;
  String? sourceId;
  String? sourceCitation;
  int? page;

  /// Runs the recovered calculation chain for this entry.
  ///
  /// Pass [outputY] to answer "what is this per kilogram / per Tower pound?";
  /// omit it to use the entry's own recorded default.
  PriceCalculation calculate({MetricItem? outputY}) {
    final chosen = outputY ?? this.outputY;
    return calculatePrice(
      quantities: [
        MeasuredQuantity(unit1, measure1?.metricValue),
        MeasuredQuantity(unit2, measure2?.metricValue),
        MeasuredQuantity(unit3, measure3?.metricValue),
      ],
      price: RecordedPrice(pounds: pounds, shillings: shillings, pence: pence),
      valuationMetric: valuationMeasure?.metricValue,
      multiplierWorkers: multiplierWorkers,
      outputXMetric: outputX?.metricValue,
      outputYMetric: chosen?.metricValue,
    );
  }

  /// Short human label for a place, e.g. "Cranfield, Bedfordshire".
  String get placeLabel {
    if (locality == null || locality!.isEmpty) return '—';
    if (county == null || county!.isEmpty) return locality!;
    return '$locality, $county';
  }

  /// "Food / Grain / Wheat" style label for the category chain.
  String get categoryLabel {
    final parts = [category, subcategory, specific]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  /// £/s/d rendered as a compact string, e.g. "2s 6d" or "£1 3s 4d".
  String get priceLabel {
    final p = pounds ?? 0;
    final s = shillings ?? 0;
    final d = pence ?? 0;
    if (p == 0 && s == 0 && d == 0) return '—';
    final parts = <String>[];
    if (p != 0) parts.add('£${_fmt(p)}');
    if (s != 0) parts.add('${_fmt(s)}s');
    if (d != 0) parts.add('${_fmt(d)}d');
    return parts.join(' ');
  }

  /// The recorded quantities with their measures, e.g. "16 Quarter / 4 Bushel".
  String get quantityLabel {
    final parts = <String>[];
    for (final (q, m) in [
      (unit1, measure1),
      (unit2, measure2),
      (unit3, measure3),
    ]) {
      if (q == null) continue;
      parts.add(m == null ? _fmt(q) : '${_fmt(q)} ${m.name}');
    }
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  PriceEntry copy() => PriceEntry(
        entryId: entryId,
        legacyEntryNo: legacyEntryNo,
        year: year,
        timePeriodId: timePeriodId,
        timePeriodName: timePeriodName,
        dayOfMonth: dayOfMonth,
        placeId: placeId,
        locality: locality,
        county: county,
        specificId: specificId,
        category: category,
        subcategory: subcategory,
        specific: specific,
        unit1: unit1,
        unit2: unit2,
        unit3: unit3,
        measure1: measure1,
        measure2: measure2,
        measure3: measure3,
        multiplierWorkers: multiplierWorkers,
        multiplierMeasureId: multiplierMeasureId,
        multiplierMeasureName: multiplierMeasureName,
        pounds: pounds,
        shillings: shillings,
        pence: pence,
        valuationMeasure: valuationMeasure,
        outputX: outputX,
        outputY: outputY,
        statusInfo: statusInfo,
        food: food,
        countryId: countryId,
        countryName: countryName,
        coinTypeId: coinTypeId,
        coinTypeName: coinTypeName,
        information: information,
        sourceId: sourceId,
        sourceCitation: sourceCitation,
        page: page,
      );
}

enum AverageKind { mean, median, mode, all }

extension AverageKindLabel on AverageKind {
  String get label => switch (this) {
        AverageKind.mean => 'Mean average',
        AverageKind.median => 'Median average',
        AverageKind.mode => 'Mode average',
        AverageKind.all => 'All entries',
      };

  /// Fits a segmented button without wrapping.
  String get shortLabel => switch (this) {
        AverageKind.mean => 'Mean',
        AverageKind.median => 'Median',
        AverageKind.mode => 'Mode',
        AverageKind.all => 'All',
      };
}
