import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'sqlite_service.dart';

const _uuid = Uuid();

/// All reads/writes against the opened sqlite database go through here.
/// Keeps the SQL in one place and gives the UI a small, typed surface.
///
/// The database holds recorded facts only; derived figures are computed by
/// `pricing.dart`. What this class must supply for that to work is the metric
/// value behind every measure and standard, which is why the entry query
/// carries `metric_value` alongside each name.
class DatabaseRepository {
  DatabaseRepository(this._svc);

  final SqliteService _svc;
  CommonDatabase get _db => _svc.db;

  static const _entryColumns = '''
    pe.entry_id, pe.legacy_entry_no, pe.year,
    pe.time_period_id, tp.name AS time_period_name, pe.day_of_month,
    pe.place_id, pl.locality, co.name AS county,
    pe.specific_id, cat.name AS category, sub.name AS subcategory, sp.name AS specific,
    pe.unit_1, pe.unit_2, pe.unit_3,
    pe.measure_1_id, m1.name AS measure_1_name, m1.metric_value AS measure_1_metric,
    pe.measure_2_id, m2.name AS measure_2_name, m2.metric_value AS measure_2_metric,
    pe.measure_3_id, m3.name AS measure_3_name, m3.metric_value AS measure_3_metric,
    pe.multiplier_workers,
    pe.multiplier_measure_id, mm.name AS multiplier_measure_name,
    pe.pounds, pe.shillings, pe.pence,
    pe.valuation_measure_id, vm.name AS valuation_measure_name,
      vm.metric_value AS valuation_measure_metric,
    pe.output_x_standard_id, ox.name AS output_x_name, ox.metric_value AS output_x_metric,
    pe.output_y_standard_id, oy.name AS output_y_name, oy.metric_value AS output_y_metric,
    pe.status_info, pe.food,
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
    LEFT JOIN measures m1 ON pe.measure_1_id = m1.measure_id
    LEFT JOIN measures m2 ON pe.measure_2_id = m2.measure_id
    LEFT JOIN measures m3 ON pe.measure_3_id = m3.measure_id
    LEFT JOIN measures vm ON pe.valuation_measure_id = vm.measure_id
    LEFT JOIN multiplier_measures mm ON pe.multiplier_measure_id = mm.multiplier_measure_id
    LEFT JOIN standards ox ON pe.output_x_standard_id = ox.standard_id
    LEFT JOIN standards oy ON pe.output_y_standard_id = oy.standard_id
    LEFT JOIN countries ctry ON pe.country_id = ctry.country_id
    LEFT JOIN coin_types coin ON pe.coin_type_id = coin.coin_type_id
    LEFT JOIN sources src ON pe.source_id = src.source_id
  ''';

  PriceEntry _rowToEntry(Row r) {
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

    /// Rebuilds a lookup item from the three columns the query carries for it.
    MetricItem? metric(String idCol, String nameCol, String metricCol) {
      final id = s(idCol);
      if (id == null) return null;
      return MetricItem(id, s(nameCol) ?? '(unnamed)', d(metricCol));
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
      measure1: metric('measure_1_id', 'measure_1_name', 'measure_1_metric'),
      measure2: metric('measure_2_id', 'measure_2_name', 'measure_2_metric'),
      measure3: metric('measure_3_id', 'measure_3_name', 'measure_3_metric'),
      multiplierWorkers: d('multiplier_workers'),
      multiplierMeasureId: s('multiplier_measure_id'),
      multiplierMeasureName: s('multiplier_measure_name'),
      pounds: d('pounds'),
      shillings: d('shillings'),
      pence: d('pence'),
      valuationMeasure: metric(
          'valuation_measure_id', 'valuation_measure_name', 'valuation_measure_metric'),
      outputX: metric('output_x_standard_id', 'output_x_name', 'output_x_metric'),
      outputY: metric('output_y_standard_id', 'output_y_name', 'output_y_metric'),
      statusInfo: s('status_info'),
      food: s('food'),
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

  /// Loads every price entry with all dimension names and metric values
  /// resolved. For ~10k rows this is comfortably fast in-memory; filtering and
  /// sorting then happen in Dart on the resulting list.
  List<PriceEntry> loadAllEntries() {
    final rows =
        _db.select('SELECT $_entryColumns $_entryJoins ORDER BY pe.legacy_entry_no');
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

  // ----------------------------------------------------------- dimensions --

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
        'SELECT subcategory_id, category_id, name FROM subcategories '
        'WHERE category_id = ? ORDER BY name',
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
        'SELECT specific_id, subcategory_id, name FROM specifics '
        'WHERE subcategory_id = ? ORDER BY name',
        [subcategoryId],
      )
      .map((r) => SpecificOption(
            r['specific_id'] as String,
            r['subcategory_id'] as String,
            r['name'] as String,
          ))
      .toList();

  List<MetricItem> _metricItems(String table, String idCol) => _db
      .select('SELECT $idCol, name, metric_value FROM $table ORDER BY name')
      .map((r) => MetricItem(
            r[idCol] as String,
            r['name'] as String,
            (r['metric_value'] as num?)?.toDouble(),
          ))
      .toList();

  /// The vocabulary for MEASURE 1/2/3 and the valuation measure.
  List<MetricItem> get measures => _metricItems('measures', 'measure_id');

  /// The vocabulary for output X and output Y — a different table from
  /// [measures] on purpose.
  List<MetricItem> get standards => _metricItems('standards', 'standard_id');

  /// The standards a reader can meaningfully ask for a price "per". Anything
  /// without a metric value cannot produce an answer, so offering it would
  /// only ever yield a dash.
  List<MetricItem> get outputUnitChoices =>
      standards.where((s) => s.isResolved).toList();

  List<LookupItem> get sources => _db
      .select('SELECT source_id, citation FROM sources ORDER BY citation')
      .map((r) => LookupItem(r['source_id'] as String, r['citation'] as String))
      .toList();

  List<LookupItem> get timePeriods => _db
      .select('SELECT time_period_id, name FROM time_periods ORDER BY name')
      .map((r) => LookupItem(r['time_period_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get multiplierMeasures => _db
      .select('SELECT multiplier_measure_id, name FROM multiplier_measures ORDER BY name')
      .map((r) =>
          LookupItem(r['multiplier_measure_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get countries => _db
      .select('SELECT country_id, name FROM countries ORDER BY name')
      .map((r) => LookupItem(r['country_id'] as String, r['name'] as String))
      .toList();

  List<LookupItem> get coinTypes => _db
      .select('SELECT coin_type_id, name FROM coin_types ORDER BY name')
      .map((r) => LookupItem(r['coin_type_id'] as String, r['name'] as String))
      .toList();

  // ---------------------------------------------------------------- writes --

  /// Persists every editable field of [entry] back to price_entries.
  void saveEntry(PriceEntry entry) {
    _db.execute(
      '''UPDATE price_entries SET
        year = ?, time_period_id = ?, day_of_month = ?, place_id = ?, specific_id = ?,
        unit_1 = ?, unit_2 = ?, unit_3 = ?,
        measure_1_id = ?, measure_2_id = ?, measure_3_id = ?,
        multiplier_workers = ?, multiplier_measure_id = ?,
        pounds = ?, shillings = ?, pence = ?,
        valuation_measure_id = ?, output_x_standard_id = ?, output_y_standard_id = ?,
        status_info = ?, food = ?, country_id = ?, coin_type_id = ?,
        information = ?, source_id = ?, page = ?
      WHERE entry_id = ?''',
      [
        entry.year, entry.timePeriodId, entry.dayOfMonth, entry.placeId,
        entry.specificId,
        entry.unit1, entry.unit2, entry.unit3,
        entry.measure1?.id, entry.measure2?.id, entry.measure3?.id,
        entry.multiplierWorkers, entry.multiplierMeasureId,
        entry.pounds, entry.shillings, entry.pence,
        entry.valuationMeasure?.id, entry.outputX?.id, entry.outputY?.id,
        entry.statusInfo, entry.food, entry.countryId, entry.coinTypeId,
        entry.information, entry.sourceId, entry.page,
        entry.entryId,
      ],
    );
  }

  /// Creates a blank entry and returns its id.
  ///
  /// The new row gets the next legacy entry number so it sorts to the end of
  /// the table, and inherits the country if the database only knows one —
  /// there is no sense making an editor pick "UK" every time when it is the
  /// only option on record.
  String createEntry() {
    final id = _uuid.v4();
    final nextNo = _db
        .select('SELECT COALESCE(MAX(legacy_entry_no), 0) + 1 AS n '
            'FROM price_entries')
        .first['n'] as int;

    final countries = _db.select('SELECT country_id FROM countries LIMIT 2');
    final soleCountry =
        countries.length == 1 ? countries.first['country_id'] as String : null;

    _db.execute(
      'INSERT INTO price_entries(entry_id, legacy_entry_no, country_id) '
      'VALUES (?, ?, ?)',
      [id, nextNo, soleCountry],
    );
    return id;
  }

  /// Removes an entry for good.
  ///
  /// The spreadsheet's cached figures for the row go too; they are keyed to
  /// the entry and foreign keys are on, so they would block the delete.
  void deleteEntry(String entryId) {
    _db.execute(
      'DELETE FROM excel_cached_calculations WHERE entry_id = ?',
      [entryId],
    );
    _db.execute('DELETE FROM price_entries WHERE entry_id = ?', [entryId]);
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
        _db.execute('INSERT INTO counties(county_id, name) VALUES (?, ?)',
            [countyId, trimmedCounty]);
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
  String resolveOrCreateSpecificChain(
      String category, String subcategory, String specific) {
    String findOrInsert(String table, String idCol, String name,
        {String? parentCol, String? parentId}) {
      final whereParent = parentCol != null ? ' AND $parentCol = ?' : '';
      final args = parentCol != null ? [name, parentId] : [name];
      final existing = _db.select(
        'SELECT $idCol FROM $table WHERE name = ?$whereParent',
        args,
      );
      if (existing.isNotEmpty) return existing.first[idCol] as String;
      final id = _uuid.v4();
      if (parentCol != null) {
        _db.execute(
          'INSERT INTO $table($idCol, $parentCol, name) VALUES (?, ?, ?)',
          [id, parentId, name],
        );
      } else {
        _db.execute('INSERT INTO $table($idCol, name) VALUES (?, ?)', [id, name]);
      }
      return id;
    }

    final categoryId = findOrInsert('categories', 'category_id', category.trim());
    final subcategoryId = findOrInsert(
      'subcategories', 'subcategory_id', subcategory.trim(),
      parentCol: 'category_id', parentId: categoryId,
    );
    return findOrInsert(
      'specifics', 'specific_id', specific.trim(),
      parentCol: 'subcategory_id', parentId: subcategoryId,
    );
  }

  /// Finds a measure or standard by name, creating it with no metric value if
  /// it is new.
  ///
  /// A newly invented unit deliberately has `metric_value` NULL: we do not know
  /// what one of it is worth in metric, and guessing would silently corrupt
  /// every figure derived from it. It will contribute zero until someone fills
  /// the value in, which is the same thing the source spreadsheet does.
  MetricItem? _resolveOrCreateMetric(
      String table, String idCol, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final trimmed = name.trim().replaceAll('"', '');
    final existing = _db.select(
      'SELECT $idCol, name, metric_value FROM $table WHERE name = ?',
      [trimmed],
    );
    if (existing.isNotEmpty) {
      final r = existing.first;
      return MetricItem(
        r[idCol] as String,
        r['name'] as String,
        (r['metric_value'] as num?)?.toDouble(),
      );
    }
    final id = _uuid.v4();
    _db.execute(
      'INSERT INTO $table($idCol, name, metric_value) VALUES (?, ?, NULL)',
      [id, trimmed],
    );
    return MetricItem(id, trimmed, null);
  }

  MetricItem? resolveOrCreateMeasure(String? name) =>
      _resolveOrCreateMetric('measures', 'measure_id', name);

  MetricItem? resolveOrCreateStandard(String? name) =>
      _resolveOrCreateMetric('standards', 'standard_id', name);

  /// Finds a lookup row by name in a single-column-key table, creating it if
  /// it doesn't exist yet. Returns null for blank input.
  String? _resolveOrCreate(
      String table, String idCol, String nameCol, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final trimmed = name.trim();
    final existing =
        _db.select('SELECT $idCol FROM $table WHERE $nameCol = ?', [trimmed]);
    if (existing.isNotEmpty) return existing.first[idCol] as String;
    final id = _uuid.v4();
    _db.execute('INSERT INTO $table($idCol, $nameCol) VALUES (?, ?)', [id, trimmed]);
    return id;
  }

  String? resolveOrCreateSource(String? citation) =>
      _resolveOrCreate('sources', 'source_id', 'citation', citation);
  String? resolveOrCreateCountry(String? name) =>
      _resolveOrCreate('countries', 'country_id', 'name', name);
  String? resolveOrCreateCoinType(String? name) =>
      _resolveOrCreate('coin_types', 'coin_type_id', 'name', name);
  String? resolveOrCreateTimePeriod(String? name) =>
      _resolveOrCreate('time_periods', 'time_period_id', 'name', name);
  String? resolveOrCreateMultiplierMeasure(String? name) =>
      _resolveOrCreate(
          'multiplier_measures', 'multiplier_measure_id', 'name', name);
}
