import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'sqlite_service.dart';

const _uuid = Uuid();

/// All reads/writes against the opened sqlite database go through here.
/// Keeps the SQL in one place and gives the UI a small, typed surface.
class DatabaseRepository {
  DatabaseRepository(this._svc);

  final SqliteService _svc;
  CommonDatabase get _db => _svc.db;

  static const _entryColumns = '''
    pe.entry_id, pe.legacy_entry_no, pe.year, pe.time_period_id, tp.name AS time_period_name,
    pe.day_of_month, pe.place_id, pl.locality, co.name AS county,
    pe.specific_id, cat.name AS category, sub.name AS subcategory, sp.name AS specific,
    pe.unit_1, pe.unit_2, pe.unit_3, pe.multiplier_workers, pe.pounds, pe.shillings, pe.pence,
    pe.status_info,
    pe.measure_1_unit_id, m1.name AS measure_1_name,
    pe.measure_2_unit_id, m2.name AS measure_2_name,
    pe.measure_3_unit_id, m3.name AS measure_3_name,
    pe.multiplier_workers_measure_id, mm.name AS multiplier_measure_name,
    pe.total_grams,
    pe.valuation_measure_unit_id, vm.name AS valuation_unit_name,
    pe.output_x_unit_id, ox.name AS output_x_name,
    pe.chosen_output_y_unit_id, oy.name AS output_y_name,
    pe.output_x_value, pe.val_grams, pe.sales_calc, pe.price_in_pence,
    pe.total_sale_in_pence, pe.pence_per_output_y,
    pe.country_id, ctry.name AS country_name,
    pe.coin_type_id, coin.name AS coin_type_name,
    pe.information, pe.source_id, src.citation AS source_citation, pe.page
  ''';

  static const _entryJoins = '''
    FROM price_entries pe
    LEFT JOIN places pl ON pe.place_id = pl.place_id
    LEFT JOIN counties co ON pl.county_id = co.county_id
    LEFT JOIN specifics sp ON pe.specific_id = sp.specific_id
    LEFT JOIN subcategories sub ON sp.subcategory_id = sub.subcategory_id
    LEFT JOIN categories cat ON sub.category_id = cat.category_id
    LEFT JOIN time_periods tp ON pe.time_period_id = tp.time_period_id
    LEFT JOIN units m1 ON pe.measure_1_unit_id = m1.unit_id
    LEFT JOIN units m2 ON pe.measure_2_unit_id = m2.unit_id
    LEFT JOIN units m3 ON pe.measure_3_unit_id = m3.unit_id
    LEFT JOIN multiplier_measures mm ON pe.multiplier_workers_measure_id = mm.multiplier_measure_id
    LEFT JOIN units vm ON pe.valuation_measure_unit_id = vm.unit_id
    LEFT JOIN units ox ON pe.output_x_unit_id = ox.unit_id
    LEFT JOIN units oy ON pe.chosen_output_y_unit_id = oy.unit_id
    LEFT JOIN countries ctry ON pe.country_id = ctry.country_id
    LEFT JOIN coin_types coin ON pe.coin_type_id = coin.coin_type_id
    LEFT JOIN sources src ON pe.source_id = src.source_id
  ''';

  PriceEntry _rowToEntry(Row r) {
    // Defensive casts: a handful of source cells hold Excel formula-error
    // text (e.g. "#N/A") in what's otherwise a numeric column. Treat
    // anything that isn't actually a number/string as absent rather than
    // crashing the whole load.
    double? d(String c) {
      final v = r[c];
      return v is num ? v.toDouble() : null;
    }

    int? i(String c) {
      final v = r[c];
      return v is num ? v.toInt() : null;
    }

    String? s(String c) {
      final v = r[c];
      if (v == null) return null;
      return v is String ? v : v.toString();
    }

    return PriceEntry(
      entryId: r['entry_id'] as String,
      legacyEntryNo: i('legacy_entry_no'),
      year: i('year'),
      timePeriodId: s('time_period_id'),
      timePeriodName: s('time_period_name'),
      dayOfMonth: i('day_of_month'),
      placeId: s('place_id'),
      locality: s('locality'),
      county: s('county'),
      specificId: s('specific_id'),
      category: s('category'),
      subcategory: s('subcategory'),
      specific: s('specific'),
      unit1: d('unit_1'),
      unit2: d('unit_2'),
      unit3: d('unit_3'),
      multiplierWorkers: d('multiplier_workers'),
      pounds: d('pounds'),
      shillings: d('shillings'),
      pence: d('pence'),
      statusInfo: s('status_info'),
      measure1UnitId: s('measure_1_unit_id'),
      measure1Name: s('measure_1_name'),
      measure2UnitId: s('measure_2_unit_id'),
      measure2Name: s('measure_2_name'),
      measure3UnitId: s('measure_3_unit_id'),
      measure3Name: s('measure_3_name'),
      multiplierMeasureId: s('multiplier_workers_measure_id'),
      multiplierMeasureName: s('multiplier_measure_name'),
      totalGrams: d('total_grams'),
      valuationUnitId: s('valuation_measure_unit_id'),
      valuationUnitName: s('valuation_unit_name'),
      outputXUnitId: s('output_x_unit_id'),
      outputXName: s('output_x_name'),
      outputYUnitId: s('chosen_output_y_unit_id'),
      outputYName: s('output_y_name'),
      outputXValue: d('output_x_value'),
      valGrams: d('val_grams'),
      salesCalc: d('sales_calc'),
      priceInPence: d('price_in_pence'),
      totalSaleInPence: d('total_sale_in_pence'),
      pencePerOutputY: d('pence_per_output_y'),
      countryId: s('country_id'),
      countryName: s('country_name'),
      coinTypeId: s('coin_type_id'),
      coinTypeName: s('coin_type_name'),
      information: s('information'),
      sourceId: s('source_id'),
      sourceCitation: s('source_citation'),
      page: i('page'),
    );
  }

  int get totalEntryCount =>
      _db.select('SELECT COUNT(*) AS n FROM price_entries').first['n'] as int;

  /// Loads every price entry with all dimension names resolved. For ~10k
  /// rows this is comfortably fast in-memory; filtering/sorting happens in
  /// Dart on the resulting list.
  List<PriceEntry> loadAllEntries() {
    final rows = _db.select('SELECT $_entryColumns $_entryJoins ORDER BY pe.legacy_entry_no');
    return rows.map(_rowToEntry).toList();
  }

  PriceEntry? loadEntry(String entryId) {
    final rows = _db.select(
      'SELECT $_entryColumns $_entryJoins WHERE pe.entry_id = ?',
      [entryId],
    );
    if (rows.isEmpty) return null;
    return _rowToEntry(rows.first);
  }

  (int, int) get yearRange {
    final r = _db
        .select('SELECT MIN(year) AS lo, MAX(year) AS hi FROM price_entries')
        .first;
    return ((r['lo'] as int?) ?? 1270, (r['hi'] as int?) ?? 1500);
  }

  List<LookupItem> get counties => _db
      .select('SELECT county_id, name FROM counties ORDER BY name')
      .map((r) => LookupItem(r['county_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> places({String? countyId}) {
    final where = countyId != null ? 'WHERE pl.county_id = ?' : '';
    final args = countyId != null ? [countyId] : const [];
    final rows = _db.select(
      '''SELECT pl.place_id, pl.locality, co.name AS county
         FROM places pl LEFT JOIN counties co ON pl.county_id = co.county_id
         $where ORDER BY pl.locality''',
      args,
    );
    return rows
        .map((r) => LookupItem(
              r['place_id'] as String,
              r['county'] == null
                  ? r['locality'] as String
                  : '${r['locality']}, ${r['county']}',
            ))
        .toList();
  }

  List<CategoryOption> get categories => _db
      .select('SELECT category_id, name FROM categories ORDER BY name')
      .map((r) => CategoryOption(r['category_id'] as String, r['name'] as String))
      .toList();

  List<SubcategoryOption> subcategoriesOf(String categoryId) => _db
      .select(
        'SELECT subcategory_id, category_id, name FROM subcategories WHERE category_id = ? ORDER BY name',
        [categoryId],
      )
      .map((r) => SubcategoryOption(
            r['subcategory_id'] as String,
            r['category_id'] as String,
            r['name'] as String,
          ))
      .toList();

  List<SpecificOption> specificsOf(String subcategoryId) => _db
      .select(
        'SELECT specific_id, subcategory_id, name FROM specifics WHERE subcategory_id = ? ORDER BY name',
        [subcategoryId],
      )
      .map((r) => SpecificOption(
            r['specific_id'] as String,
            r['subcategory_id'] as String,
            r['name'] as String,
          ))
      .toList();

  List<LookupItem> get units => _db
      .select('SELECT unit_id, name FROM units ORDER BY name')
      .map((r) => LookupItem(r['unit_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get sources => _db
      .select('SELECT source_id, citation FROM sources ORDER BY citation')
      .map((r) => LookupItem(r['source_id'] as String, r['citation'] as String))
      .toList();

  List<LookupItem> get timePeriods => _db
      .select('SELECT time_period_id, name FROM time_periods ORDER BY name')
      .map((r) => LookupItem(r['time_period_id'] as String, r['name'] as String))
      .toList();

  // ---------------------------------------------------------------- writes --

  /// Persists every editable field of [entry] back to price_entries.
  void saveEntry(PriceEntry entry) {
    _db.execute(
      '''UPDATE price_entries SET
        year = ?, time_period_id = ?, day_of_month = ?, place_id = ?, specific_id = ?,
        unit_1 = ?, unit_2 = ?, unit_3 = ?, multiplier_workers = ?,
        pounds = ?, shillings = ?, pence = ?, status_info = ?,
        measure_1_unit_id = ?, measure_2_unit_id = ?, measure_3_unit_id = ?,
        multiplier_workers_measure_id = ?, total_grams = ?,
        valuation_measure_unit_id = ?, output_x_unit_id = ?, chosen_output_y_unit_id = ?,
        output_x_value = ?, val_grams = ?, sales_calc = ?, price_in_pence = ?,
        total_sale_in_pence = ?, pence_per_output_y = ?,
        country_id = ?, coin_type_id = ?, information = ?, source_id = ?, page = ?
      WHERE entry_id = ?''',
      [
        entry.year, entry.timePeriodId, entry.dayOfMonth, entry.placeId, entry.specificId,
        entry.unit1, entry.unit2, entry.unit3, entry.multiplierWorkers,
        entry.pounds, entry.shillings, entry.pence, entry.statusInfo,
        entry.measure1UnitId, entry.measure2UnitId, entry.measure3UnitId,
        entry.multiplierMeasureId, entry.totalGrams,
        entry.valuationUnitId, entry.outputXUnitId, entry.outputYUnitId,
        entry.outputXValue, entry.valGrams, entry.salesCalc, entry.priceInPence,
        entry.totalSaleInPence, entry.pencePerOutputY,
        entry.countryId, entry.coinTypeId, entry.information, entry.sourceId, entry.page,
        entry.entryId,
      ],
    );
  }

  /// Finds a place by locality name (optionally within a county), creating
  /// one (and its county, if given and new) when it doesn't exist yet.
  String resolveOrCreatePlace(String locality, {String? county}) {
    final trimmedLocality = locality.trim();
    String? countyId;
    if (county != null && county.trim().isNotEmpty) {
      final trimmedCounty = county.trim();
      final existing = _db.select(
        'SELECT county_id FROM counties WHERE name = ?',
        [trimmedCounty],
      );
      if (existing.isNotEmpty) {
        countyId = existing.first['county_id'] as String;
      } else {
        countyId = _uuid.v4();
        _db.execute('INSERT INTO counties(county_id, name) VALUES (?, ?)', [countyId, trimmedCounty]);
      }
    }

    final existingPlace = _db.select(
      'SELECT place_id FROM places WHERE locality = ? AND (county_id IS ? OR county_id = ?)',
      [trimmedLocality, countyId, countyId],
    );
    if (existingPlace.isNotEmpty) {
      return existingPlace.first['place_id'] as String;
    }
    final placeId = _uuid.v4();
    _db.execute(
      'INSERT INTO places(place_id, county_id, locality) VALUES (?, ?, ?)',
      [placeId, countyId, trimmedLocality],
    );
    return placeId;
  }

  /// Walks category -> subcategory -> specific, creating any missing level,
  /// and returns the leaf specific_id.
  String resolveOrCreateSpecificChain(String category, String subcategory, String specific) {
    String findOrInsert(String table, String idCol, String nameCol, String name,
        {String? parentCol, String? parentId}) {
      final whereParent = parentCol != null ? ' AND $parentCol = ?' : '';
      final args = parentCol != null ? [name, parentId] : [name];
      final existing = _db.select(
        'SELECT $idCol FROM $table WHERE $nameCol = ?$whereParent',
        args,
      );
      if (existing.isNotEmpty) return existing.first[idCol] as String;
      final id = _uuid.v4();
      if (parentCol != null) {
        _db.execute(
          'INSERT INTO $table($idCol, $parentCol, $nameCol) VALUES (?, ?, ?)',
          [id, parentId, name],
        );
      } else {
        _db.execute('INSERT INTO $table($idCol, $nameCol) VALUES (?, ?)', [id, name]);
      }
      return id;
    }

    final categoryId = findOrInsert('categories', 'category_id', 'name', category.trim());
    final subcategoryId = findOrInsert(
      'subcategories', 'subcategory_id', 'name', subcategory.trim(),
      parentCol: 'category_id', parentId: categoryId,
    );
    return findOrInsert(
      'specifics', 'specific_id', 'name', specific.trim(),
      parentCol: 'subcategory_id', parentId: subcategoryId,
    );
  }

  List<LookupItem> get multiplierMeasures => _db
      .select('SELECT multiplier_measure_id, name FROM multiplier_measures ORDER BY name')
      .map((r) => LookupItem(r['multiplier_measure_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get countries => _db
      .select('SELECT country_id, name FROM countries ORDER BY name')
      .map((r) => LookupItem(r['country_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get coinTypes => _db
      .select('SELECT coin_type_id, name FROM coin_types ORDER BY name')
      .map((r) => LookupItem(r['coin_type_id'] as String, r['name'] as String))
      .toList();

  /// Finds a lookup row by name in a single-column-key table, creating it if
  /// it doesn't exist yet. Returns null for blank input.
  String? _resolveOrCreate(String table, String idCol, String nameCol, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final trimmed = name.trim();
    final existing = _db.select('SELECT $idCol FROM $table WHERE $nameCol = ?', [trimmed]);
    if (existing.isNotEmpty) return existing.first[idCol] as String;
    final id = _uuid.v4();
    _db.execute('INSERT INTO $table($idCol, $nameCol) VALUES (?, ?)', [id, trimmed]);
    return id;
  }

  String? resolveOrCreateUnit(String? name) =>
      _resolveOrCreate('units', 'unit_id', 'name', name);
  String? resolveOrCreateSource(String? citation) =>
      _resolveOrCreate('sources', 'source_id', 'citation', citation);
  String? resolveOrCreateCountry(String? name) =>
      _resolveOrCreate('countries', 'country_id', 'name', name);
  String? resolveOrCreateCoinType(String? name) =>
      _resolveOrCreate('coin_types', 'coin_type_id', 'name', name);
  String? resolveOrCreateTimePeriod(String? name) =>
      _resolveOrCreate('time_periods', 'time_period_id', 'name', name);
  String? resolveOrCreateMultiplierMeasure(String? name) =>
      _resolveOrCreate('multiplier_measures', 'multiplier_measure_id', 'name', name);
}
