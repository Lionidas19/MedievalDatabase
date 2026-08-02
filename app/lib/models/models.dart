/// A generic (id, label) pair used to populate dropdown/autocomplete pickers
/// that are backed by a lookup table (units, places, sources, ...).
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

/// One row of the price_entries fact table, flattened with every dimension
/// name resolved for display, but keeping the raw foreign-key ids around so
/// edits can be written back precisely.
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
    this.multiplierWorkers,
    this.pounds,
    this.shillings,
    this.pence,
    this.statusInfo,
    this.measure1UnitId,
    this.measure1Name,
    this.measure2UnitId,
    this.measure2Name,
    this.measure3UnitId,
    this.measure3Name,
    this.multiplierMeasureId,
    this.multiplierMeasureName,
    this.totalGrams,
    this.valuationUnitId,
    this.valuationUnitName,
    this.outputXUnitId,
    this.outputXName,
    this.outputYUnitId,
    this.outputYName,
    this.outputXValue,
    this.valGrams,
    this.salesCalc,
    this.priceInPence,
    this.totalSaleInPence,
    this.pencePerOutputY,
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
  double? unit1;
  double? unit2;
  double? unit3;
  double? multiplierWorkers;
  double? pounds;
  double? shillings;
  double? pence;
  String? statusInfo;
  String? measure1UnitId;
  String? measure1Name;
  String? measure2UnitId;
  String? measure2Name;
  String? measure3UnitId;
  String? measure3Name;
  String? multiplierMeasureId;
  String? multiplierMeasureName;
  double? totalGrams;
  String? valuationUnitId;
  String? valuationUnitName;
  String? outputXUnitId;
  String? outputXName;
  String? outputYUnitId;
  String? outputYName;
  double? outputXValue;
  double? valGrams;
  double? salesCalc;
  double? priceInPence;
  double? totalSaleInPence;
  double? pencePerOutputY;
  String? countryId;
  String? countryName;
  String? coinTypeId;
  String? coinTypeName;
  String? information;
  String? sourceId;
  String? sourceCitation;
  int? page;

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
        multiplierWorkers: multiplierWorkers,
        pounds: pounds,
        shillings: shillings,
        pence: pence,
        statusInfo: statusInfo,
        measure1UnitId: measure1UnitId,
        measure1Name: measure1Name,
        measure2UnitId: measure2UnitId,
        measure2Name: measure2Name,
        measure3UnitId: measure3UnitId,
        measure3Name: measure3Name,
        multiplierMeasureId: multiplierMeasureId,
        multiplierMeasureName: multiplierMeasureName,
        totalGrams: totalGrams,
        valuationUnitId: valuationUnitId,
        valuationUnitName: valuationUnitName,
        outputXUnitId: outputXUnitId,
        outputXName: outputXName,
        outputYUnitId: outputYUnitId,
        outputYName: outputYName,
        outputXValue: outputXValue,
        valGrams: valGrams,
        salesCalc: salesCalc,
        priceInPence: priceInPence,
        totalSaleInPence: totalSaleInPence,
        pencePerOutputY: pencePerOutputY,
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
}
