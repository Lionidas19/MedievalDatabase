/// What the Explorer table shows, and at which detail level.
///
/// The table used to be seven fixed columns sharing the width between them by
/// `flex`, which had two consequences: the other thirty-one recorded fields
/// were reachable only by opening one entry at a time in a dialog, and adding
/// a column made every existing one narrower. Columns now have real widths and
/// the table scrolls sideways, so "show me everything" is a setting rather
/// than a rewrite.
library;

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../services/trend.dart';
import '../../state/view_preferences.dart';
import '../../widgets/info_dot.dart';

/// What a column sorts by, or null where sorting it means nothing.
///
/// This used to be a fixed enum of seven sortable fields with a hand-written
/// comparison for each, which is why most of the table could not be sorted:
/// every new column needed two more edits somewhere else, and so never got
/// them. A column now carries its own sort key and the table asks for it.
typedef SortKey = Object? Function(PricedEntry);

/// Orders two sort keys of the same column.
///
/// Numbers compare as numbers and everything else as case-folded text, so
/// 'Bushel' and 'bushel' sort together and 9 sorts before 10 rather than after
/// it. Nulls are handled by the caller, which puts them last in *both*
/// directions — a missing value is absent data, not a low one, and reversing
/// the sort should not parade it to the top.
int compareSortKeys(Object a, Object b) {
  if (a is num && b is num) return a.compareTo(b);
  return a.toString().toLowerCase().compareTo(b.toString().toLowerCase());
}

/// One entry, priced in whatever unit the reader has chosen.
///
/// The calculation is run once per entry per pass and carried along, because
/// at the fullest detail level six columns are all reading different fields of
/// the same result.
class PricedEntry {
  const PricedEntry({
    required this.entry,
    required this.calc,
    required this.perUnit,
    required this.comparable,
    this.modernPerUnit,
    this.estimate,
  });

  final PriceEntry entry;
  final PriceCalculation calc;

  /// Pence per the chosen output unit, or null when the source cannot answer —
  /// either because the figures are missing or because the entry is measured
  /// in a kind of unit that does not reach the chosen one.
  final double? perUnit;

  /// False when this entry's measure is a different kind of thing from the
  /// chosen output unit: cattle by the head, asked for per kilogram.
  final bool comparable;

  /// [perUnit] in modern money, withheld exactly where [perUnit] is.
  ///
  /// Taken from the same decision as [perUnit] rather than read off the
  /// calculation, which always answers per the unit it was handed. The table
  /// used to read it from there, so a row that could not be priced per
  /// kilogram still showed a modern figure per kilogram beside the dash, and
  /// on "Recorded unit" the modern column was blank where the pence one was
  /// not.
  final double? modernPerUnit;

  /// A guess at what this entry would have cost, where the source cannot say
  /// and the reader has asked for estimates. Never a recorded figure, and
  /// never counted in any average.
  final TrendEstimate? estimate;
}

/// One column of the table.
class EntryColumn {
  const EntryColumn({
    required this.id,
    required this.label,
    required this.width,
    required this.value,
    this.sortKey,
    this.numeric = false,
    this.tooltip,
    this.explanation,
    this.cellTooltip,
    this.startsGroup = false,
  });

  /// Stable across renames and unit changes, unlike [label]: the heading of
  /// the per-unit column is "Pence per Kilograms" one moment and "Pence per
  /// Tower Pound" the next, and a sort should survive that.
  final String id;

  final String label;
  final double width;
  final String Function(PricedEntry) value;

  /// Null where the column cannot be sorted. Only two are: the info button
  /// and the row's own edit action have nothing to order by.
  final SortKey? sortKey;

  /// Per-cell explanation, where one cell in a column has something to say the
  /// others do not — a dash that needs a reason, mainly.
  final String? Function(PricedEntry)? cellTooltip;

  /// Right-aligned and set in tabular figures, so the column can be read down.
  final bool numeric;

  /// Shown on the header cell when a pointer hovers over it. For a hint that
  /// is worth having but that nobody needs to go looking for.
  final String? tooltip;

  /// What this column means, in plain English.
  ///
  /// Columns carrying one get an info button in the header, so the explanation
  /// can be *asked for* rather than only hovered over — a distinction that
  /// decides whether it exists at all on a touch screen, where there is no
  /// hover and a tap is already spoken for by sorting.
  ///
  /// Only Year, Place, Item and Quantity go without one. They say what they
  /// are; an info button on them would be noise, and noise next to every
  /// heading is how people learn to stop reading them.
  final String? explanation;

  /// True on the first column of each run — what it cost, what that works out
  /// to, how it was reached, what else the record says, where it came from.
  /// The table draws a seam here, which is the only thing keeping
  /// twenty-three columns from reading as one undifferentiated wall.
  final bool startsGroup;
}

/// Records as text to paste: a line of headings, then one line per record,
/// tab-separated, which is what a spreadsheet takes as rows and columns.
///
/// The headings and values are the table's own, at whatever detail level it
/// is showing, so what lands in the spreadsheet is what was on the screen.
/// The dash the table draws for "the source does not say" becomes an empty
/// cell: in a spreadsheet a dash is text, and text breaks a column of sums.
String recordsAsText(List<PricedEntry> records, List<EntryColumn> columns) {
  final shown = [
    for (final c in columns)
      if (c.sortKey != null) c,
  ];
  String clean(String s) {
    final flat = s.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
    return flat == '—' ? '' : flat;
  }

  return [
    shown.map((c) => clean(c.label)).join('\t'),
    for (final p in records) shown.map((c) => clean(c.value(p))).join('\t'),
  ].join('\n');
}

String _dash(Object? v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? '—' : s;
}

/// A money figure, rounded to the penny and never beyond.
///
/// The conversion rests on a factor quoted to two decimals, so printing
/// 212.52275 would be claiming a precision the reference data does not have.
/// Figures in the thousands drop the pence entirely, where they are noise.
String _pounds(double? value) {
  if (value == null) return '\u2014';
  if (value.abs() >= 1000) return '\u00a3${value.round()}';
  return '\u00a3${value.toStringAsFixed(2)}';
}

String _num(double? v) => v == null ? '—' : formatPence(v);

/// The column set for [level], pricing against a unit named [unitName].
///
/// Ordered the way a row is read aloud rather than the way the spreadsheet
/// happened to store it: when and where, what it was, what it cost, what that
/// works out to, how the figure was reached, what else the record says, and
/// where it came from. [EntryColumn.startsGroup] marks each of those turns, so
/// the table can draw the seam.
/// [modernYear] labels the modern-money columns, e.g. 2017, and null hides
/// them. Null is the honest state when the database has no conversion
/// factors: a column of dashes headed "Price in 2017 £" tells a reader the
/// app is broken, when in fact nobody has supplied the figures.
///
/// [counts] lets an explanation quote how many entries carry a time of year.
/// Without it the sentence is left out rather than given a stale figure.
///
/// The explanations are the researcher's own wording, from his notes on the
/// tutorial, lightly edited. He means to rewrite them at greater length once
/// he has seen them in place.
List<EntryColumn> columnsFor(
  DetailLevel level,
  String unitName, {
  int? modernYear,
  EntryCounts? counts,
}) {
  final detailed = level.atLeastDetailed;
  final everything = level.isEverything;
  final recorded = unitName == MetricItem.recordedUnit.name;
  final modern = unitName == MetricItem.comparableUnit.name;
  // What "Price per" is set to now, for the end of the per-unit
  // explanations. The headings say only "selected unit", at his request, so
  // this is where a reader finds out which one.
  final setTo = recorded
      ? 'It is set to the measure each record used, named on each figure.'
      : modern
      ? 'It is set to Modern (# or Metric Kg): anything sold by weight '
            'per kilogram, counted things per head, volume per litre and '
            'length per metre.'
      : 'It is set to $unitName.';

  return [
    // ------------------------------------------------ when, where, what --
    if (detailed)
      EntryColumn(
        id: 'entryNo',
        label: 'Entry',
        width: 88,
        numeric: true,
        sortKey: (p) => p.entry.legacyEntryNo,
        explanation: 'This column records the individual entry number.',
        value: (p) => _dash(p.entry.legacyEntryNo),
      ),
    EntryColumn(
      id: 'year',
      label: 'Year',
      sortKey: (p) => p.entry.year,
      // Name, sort arrow and info button: label + 22 + 13 + 16. At 72, from
      // before it had an explanation, the heading clipped to "Y...".
      width: 92,
      numeric: true,
      explanation:
          'Year beginning on Michaelmas of the prior year and '
          'ending on Michaelmas of the current year: traditionally 29 '
          'September in the Julian calendar.',
      value: (p) => _dash(p.entry.year),
    ),
    if (detailed)
      EntryColumn(
        id: 'timeOfYear',
        label: 'Time of year',
        sortKey: (p) => p.entry.timePeriodName,
        // Narrower than its heading would suggest. Barely one entry in twenty
        // records a time of year, so this column is mostly dashes and does not
        // deserve the width its name implies.
        width: 128,
        explanation:
            '${Explain.timeOfYear}'
            '${counts == null ? '' : ' Only ${counts.timed} of the '
                      '${counts.total} entries carry one at all.'}',
        value: (p) => _dash(p.entry.timePeriodName),
      ),
    EntryColumn(
      id: 'place',
      label: 'Place',
      sortKey: (p) => p.entry.placeLabel,
      width: 200,
      // Not his last sentence, "at present you can only search or group
      // data by county": the search box always matched settlements by name,
      // and Filters now has a Settlement box. Grouping stops at county.
      explanation:
          'Settlement name and historic county name. Filters can narrow the '
          'table to one settlement; grouping works by county.',
      value: (p) => p.entry.placeLabel,
    ),
    EntryColumn(
      id: 'item',
      label: 'Item',
      sortKey: (p) => p.entry.categoryLabel,
      width: 260,
      explanation: Explain.item,
      value: (p) => p.entry.categoryLabel,
    ),
    // At Basics as well. A price means little without what it was a price
    // of, and "4s" reads very differently for a quarter of wheat and for a
    // pound of pepper. The researcher asked for it there for that reason.
    EntryColumn(
      id: 'quantity',
      label: 'Quantity',
      sortKey: (p) => p.entry.unit1,
      width: 190,
      explanation:
          'The historic total of items or people sold, paid, '
          'taxed or fined.',
      value: (p) => p.entry.quantityLabel,
    ),

    // ------------------------------------------------ what it cost ------
    EntryColumn(
      // "Price" on its own invited the question these names now answer:
      // which price? The recorded one, the same one in pence, the one per
      // unit, or the whole receipt? Each says so.
      id: 'price',
      label: 'Price as recorded',
      sortKey: (p) => p.calc.priceInPence,
      // Room for the name, the sort arrow and the info button at once — at 160
      // the heading clipped its own last letters the moment it was sorted on.
      width: 178,
      startsGroup: true,
      explanation:
          'The price per unit exactly as the record gives it, in pounds (£), '
          'shillings (s) and pence (d). This was typically by the quarter '
          'for grain, by the acre for agricultural work, or by the day for '
          'general labour. For the total cost see the column "Total sale in '
          'pence", shown at Everything.',
      value: (p) => p.entry.priceLabel,
    ),

    // Beside the recorded price, at every detail level, because this is the
    // one figure a lay reader can feel. Testing found people reading "4s 4d"
    // with no sense of whether it was a lot; the researcher asked for a
    // modern equivalent they could see "with no effort", and effort is
    // exactly what switching detail level is.
    if (modernYear != null)
      EntryColumn(
        // Named as a price, beside "Price as recorded", because it is that
        // same price and nothing else. As "In 2026 money" it was read as the
        // modern form of the per-unit figure, and the per-unit one as the
        // total sale: the headings said "in what" and never "per what".
        id: 'modernPrice',
        label: 'Price in $modernYear £',
        sortKey: (p) => p.calc.modernPerValuationMeasure,
        width: 168,
        numeric: true,
        explanation:
            'The recorded price in modern $modernYear British pounds (£), '
            'from the National Archives\' figure for a penny in the entry\'s '
            'own year. A guide to scale, not a valuation: what a penny '
            'bought in 1270 is a question with more than one defensible '
            'answer.',
        value: (p) => _pounds(p.calc.modernPerValuationMeasure),
        cellTooltip: (p) => p.calc.modernPerValuationMeasure != null
            ? null
            : p.entry.year == null
            ? 'No year on this entry, so there is no factor to convert by.'
            : 'No conversion factor for ${p.entry.year}.',
      ),
    if (everything)
      EntryColumn(
        id: 'priceInPence',
        label: 'Price in pence',
        sortKey: (p) => p.calc.priceInPence,
        width: 132,
        numeric: true,
        explanation:
            'The value of Price as recorded given in pence: 1 pound = 240 '
            'pence, 1 shilling = 12 pence.',
        value: (p) => _num(p.calc.priceInPence),
      ),

    // ------------------------------------------- what that works out to --
    EntryColumn(
      id: 'perUnit',
      // A fixed name, at his request, rather than "Pence per Kilograms" one
      // moment and "Pence per Tower Pound" the next. Which unit it is goes
      // at the end of the explanation, and on each figure where it varies.
      label: 'Pence per selected unit',
      sortKey: (p) => p.perUnit,
      width: 230,
      numeric: true,
      startsGroup: true,
      explanation:
          'The price in pence according to the "Price per" unit chosen '
          'above. This value is used for calculating averages. If "Price '
          'per" is left alone it matches the historic record. $setTo A '
          'figure shown as "~ 0.19" is an estimate from neighbouring years, '
          'never a record.',
      value: (p) => p.perUnit != null
          ? _num(p.perUnit)
          : p.estimate != null
          ? '~ ${formatPence(p.estimate!.value)}'
          : '—',
      cellTooltip: (p) {
        if (p.estimate != null) {
          return p.estimate!.explain(unitName, p.entry.year ?? 0);
        }
        // Priced by its own measure, the figure means nothing without
        // saying which measure that was.
        if (recorded && p.perUnit != null) {
          final measure = p.entry.valuationMeasure?.name;
          return measure == null
              ? 'Per whatever the source measured this by.'
              : 'Pence per $measure, the measure this entry was priced by.';
        }
        return missingPerUnitReason(p, unitName);
      },
    ),
    // At every level, and last at Basics: what one comparable unit would
    // cost today is the figure a lay reader most wants.
    if (modernYear != null)
      EntryColumn(
        id: 'modernPerUnit',
        label: '$modernYear £ per selected unit',
        sortKey: (p) => p.modernPerUnit,
        width: 240,
        numeric: true,
        explanation:
            'The price in $modernYear pounds (£) according to the "Price '
            'per" unit chosen above: the column to the left, converted by '
            'the figure for the entry\'s own year. $setTo Like the other '
            'modern figure, it shows scale, not a valuation.',
        value: (p) => _pounds(p.modernPerUnit),
        cellTooltip: (p) => p.modernPerUnit != null || p.perUnit == null
            ? null
            : p.entry.year == null
            ? 'No year on this entry, so there is no factor to convert by.'
            : 'No conversion factor for ${p.entry.year}.',
      ),
    if (everything)
      EntryColumn(
        id: 'totalSale',
        label: 'Total sale in pence',
        sortKey: (p) => p.calc.totalSaleInPence,
        width: 168,
        numeric: true,
        explanation:
            'The whole receipt in pence: the unit price times how '
            'many valuation measures the entry covers, times the number of '
            'workers where there is one.',
        value: (p) => _num(p.calc.totalSaleInPence),
      ),

    // --------------------------------------------- how it was reached ---
    // From More detail, though the rest of the working waits for Everything:
    // the metric quantity is the one piece of it a worldbuilder asks for.
    if (detailed)
      EntryColumn(
        // Not "Total": it is this entry's own quantity restated in metric,
        // which is a different thing from a total sale and was too easily read
        // as one.
        id: 'totalMetric',
        label: 'Quantity in metric',
        sortKey: (p) => p.calc.totalMetric,
        width: 168,
        numeric: true,
        startsGroup: true,
        explanation:
            'The entry\'s quantity converted to metric: grams for a '
            'weight, litres for a volume, square metres for an area. The '
            'source calls this column "Total Grams" for all three.',
        value: (p) => _num(p.calc.totalMetric),
      ),
    if (everything) ...[
      EntryColumn(
        id: 'workers',
        label: 'Workers',
        sortKey: (p) => p.entry.multiplierWorkers,
        width: 100,
        numeric: true,
        explanation:
            'How many people or things the recorded price covers. '
            'Where there is a number here, the total sale is multiplied by it.',
        value: (p) => _num(p.entry.multiplierWorkers),
      ),
      EntryColumn(
        id: 'measuredBy',
        label: 'Measured by',
        sortKey: (p) => p.entry.primaryMeasure?.dimension,
        width: 132,
        explanation:
            'What this entry is measured by — mass, volume, area, '
            'length or count. It decides which output units the entry can '
            'honestly be priced in. Provisional until the researcher confirms '
            'it.',
        value: (p) => _dash(p.entry.primaryMeasure?.dimension),
      ),
      EntryColumn(
        id: 'measure1',
        label: 'Measure 1',
        sortKey: (p) => p.entry.measure1?.name,
        width: 160,
        explanation:
            'The unit the first quantity is counted in, and the '
            'largest of the three — usually something like a quarter.',
        value: (p) => _dash(p.entry.measure1?.name),
      ),
      EntryColumn(
        id: 'measure2',
        label: 'Measure 2',
        sortKey: (p) => p.entry.measure2?.name,
        width: 160,
        explanation:
            'The unit for the second quantity, where the record '
            'needed one. Usually a smaller measure, such as a bushel.',
        value: (p) => _dash(p.entry.measure2?.name),
      ),
      EntryColumn(
        id: 'measure3',
        label: 'Measure 3',
        sortKey: (p) => p.entry.measure3?.name,
        width: 160,
        explanation:
            'The unit for the third quantity — the smallest, such as '
            'a peck. Rarely filled in.',
        value: (p) => _dash(p.entry.measure3?.name),
      ),
      EntryColumn(
        id: 'valuation',
        label: 'Valuation measure',
        sortKey: (p) => p.entry.valuationMeasure?.name,
        width: 180,
        explanation:
            'What the recorded price is a price of. The total sale '
            'multiplies by how many of these the entry covers.',
        value: (p) => _dash(p.entry.valuationMeasure?.name),
      ),
      EntryColumn(
        id: 'outputX',
        label: 'Output X',
        sortKey: (p) => p.entry.outputX?.name,
        width: 150,
        explanation:
            'A correction for entries priced by something other than '
            'weight — by the acre, say. Drawn from the Standards list, and '
            'not normally touched.',
        value: (p) => _dash(p.entry.outputX?.name),
      ),
      EntryColumn(
        id: 'outputY',
        label: 'Output Y',
        sortKey: (p) => p.entry.outputY?.name,
        width: 150,
        explanation:
            'The output unit this entry was recorded with. Only the '
            'default a reader sees before choosing their own in "Price per".',
        value: (p) => _dash(p.entry.outputY?.name),
      ),
    ],

    // ------------------------------------- what else the record says ----
    if (everything) ...[
      EntryColumn(
        id: 'status',
        label: 'Status / info',
        sortKey: (p) => p.entry.statusInfo,
        width: 220,
        startsGroup: true,
        explanation:
            'Whatever the record noted that fits in no other column, often '
            'the form a thing took: seed, old, crannock. Where a record has '
            'one, a note mark appears beside its item at every detail level.',
        value: (p) => _dash(p.entry.statusInfo),
      ),
      EntryColumn(
        id: 'food',
        label: 'Food',
        sortKey: (p) => p.entry.food,
        width: 170,
        explanation:
            'Beside labour, whether some of the pay was given as food '
            'rather than coin, and how much, as the record puts it.',
        value: (p) => _dash(p.entry.food),
      ),
      EntryColumn(
        id: 'coinType',
        label: 'Coin type',
        sortKey: (p) => p.entry.coinTypeName,
        width: 130,
        explanation:
            'Recorded where payment was made in forgeries or '
            'non-standard coin. No entry in this database uses it yet.',
        value: (p) => _dash(p.entry.coinTypeName),
      ),
      EntryColumn(
        id: 'information',
        label: 'Information',
        sortKey: (p) => p.entry.information,
        width: 260,
        explanation: 'Further notes the record carries about the entry.',
        value: (p) => _dash(p.entry.information),
      ),
      EntryColumn(
        id: 'country',
        label: 'Country',
        sortKey: (p) => p.entry.countryName,
        width: 120,
        explanation: 'Always the United Kingdom in this database.',
        value: (p) => _dash(p.entry.countryName),
      ),
    ],

    // -------------------------------------------- where it came from ----
    if (everything)
      EntryColumn(
        id: 'source',
        label: 'Source',
        sortKey: (p) => p.entry.sourceCitation,
        width: 240,
        startsGroup: true,
        explanation:
            'The work the entry was read from — Thorold Rogers, '
            'History of Agriculture and Prices in England, volume 2.',
        value: (p) => _dash(p.entry.sourceCitation),
      ),
    // Everything only. At More detail it was a column of page numbers nobody
    // reading there was going to look up, in width the modern figures use.
    if (everything)
      EntryColumn(
        id: 'page',
        label: 'Page',
        sortKey: (p) => p.entry.page,
        width: 92,
        numeric: true,
        explanation: 'The page of that work the entry was read off.',
        value: (p) => _dash(p.entry.page),
      ),
  ];
}

/// Why an entry has no price per the chosen unit.
///
/// Worth saying out loud rather than leaving a dash: "cannot" and "the source
/// does not say" are different answers, and only one of them is a reason to
/// pick a different unit.
String? missingPerUnitReason(PricedEntry p, String unitName) {
  if (p.perUnit != null) return null;
  if (!p.comparable) {
    final kind = p.entry.primaryMeasure?.dimension;
    return 'Measured by ${kind ?? 'a different kind of unit'}, which does not '
        'convert to $unitName.';
  }
  if (p.calc.totalMetric == 0) {
    return 'The source records no quantity or unit to price this by.';
  }
  return 'The output or valuation unit has no metric value on record.';
}

/// Whether a row has anything at all in the per-unit column.
///
/// An estimate counts: it is drawn in the cell, marked with a tilde, and a
/// reader who turned estimates on is asking to see exactly those rows.
bool hasFigureInChosenUnit(PricedEntry p) =>
    p.perUnit != null || p.estimate != null;

/// Orders two rows of the table.
///
/// **A row the chosen unit cannot answer in sinks, whatever the sort is.**
/// Pick a unit most of the selection cannot express and the blanks used to
/// sit scattered down the table, so reading the figures meant sorting by that
/// column first just to drive them out of the way. They are not hidden: the
/// count says how many there are and the rows are still below. Within each
/// half the chosen sort applies as before.
///
/// After that, missing values sort last in *both* directions. A row with no
/// page number is not a row with a low one, and flipping the sort should not
/// parade the blanks to the top.
int comparePricedEntries(
  PricedEntry a,
  PricedEntry b, {
  required SortKey? key,
  required bool ascending,
}) {
  final aHas = hasFigureInChosenUnit(a);
  final bHas = hasFigureInChosenUnit(b);
  if (aHas != bHas) return aHas ? -1 : 1;
  if (key == null) return 0;

  final x = key(a);
  final y = key(b);
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  final cmp = compareSortKeys(x, y);
  return ascending ? cmp : -cmp;
}
